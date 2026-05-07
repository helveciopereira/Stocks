//+------------------------------------------------------------------+
//|                                                  GridEngine.mqh  |
//|                      Omni-B3 EA v1.0 — Motor de Grade Completo   |
//|     Abertura de ordens em grade com ATR dinâmico ou fixo,        |
//|     suporte bi-direcional e multiplicador de lotes               |
//+------------------------------------------------------------------+
#property copyright "Projeto Omni-B3"
#property link      "https://github.com/seu-usuario/Stocks"
#property version   "1.00"
#property strict

#include "Defines.mqh"
#include "Logger.mqh"
#include "PositionManager.mqh"
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Classe principal do Motor de Grade (Grid Engine)                 |
//|                                                                   |
//| Responsabilidades:                                                |
//|  - Calcular espaçamento entre níveis (fixo ou ATR)               |
//|  - Calcular tamanho do lote para cada nível                      |
//|  - Abrir novas ordens quando o preço se afasta o suficiente      |
//|  - Respeitar limites máximos de níveis (trava de segurança)      |
//|  - Operar em modo bi-direcional (compra e venda simultâneas)     |
//+------------------------------------------------------------------+
class CGridEngine {
private:
    // Configuração da grade
    ENUM_GRID_TYPE      m_grid_type;       // Tipo: fixo ou dinâmico
    ENUM_GRID_DIRECTION m_direction;       // Direção: compra, venda ou ambos
    ENUM_LOT_MODE       m_lot_mode;        // Modo de lote: fixo ou multiplicador

    // Parâmetros numéricos
    string  m_symbol;                      // Símbolo operado
    int     m_magic_number;                // Magic number do EA
    double  m_initial_lot;                 // Lote inicial (nível 0)
    double  m_lot_multiplier;              // Multiplicador: Lote_n = Lote₀ × Mult^n
    int     m_max_levels;                  // Máximo de níveis permitidos
    int     m_fixed_spacing;               // Espaçamento fixo em pontos
    int     m_atr_period;                  // Período do ATR
    ENUM_TIMEFRAMES m_atr_timeframe;       // Timeframe do ATR
    double  m_atr_multiplier;              // Multiplicador do ATR para espaçamento

    // Handles de indicadores e objetos
    int     m_atr_handle;                  // Handle do indicador ATR
    CTrade  m_trade;                       // Objeto de trade para enviar ordens

    // Referências externas
    CPositionManager *m_pos_manager;       // Gerenciador de posições
    CLogger          *m_logger;            // Sistema de logging

    //+--------------------------------------------------------------+
    //| Obtém o valor atual do ATR                                   |
    //| Retorna: valor do ATR em preço (não em pontos)               |
    //+--------------------------------------------------------------+
    double GetATRValue() {
        if(m_atr_handle == INVALID_HANDLE) {
            m_logger.Error("GridEngine", "Handle do ATR inválido!");
            return 0.0;
        }

        double atr_buffer[1];
        // CopyBuffer retorna a quantidade de dados copiados
        if(CopyBuffer(m_atr_handle, 0, 0, 1, atr_buffer) <= 0) {
            m_logger.Error("GridEngine", "Falha ao copiar buffer do ATR");
            return 0.0;
        }

        return atr_buffer[0];
    }

    //+--------------------------------------------------------------+
    //| Verifica se o spread atual está dentro do limite aceitável   |
    //| Retorna: true se o spread estiver OK para operar             |
    //+--------------------------------------------------------------+
    bool IsSpreadAcceptable() {
        double spread_points = (double)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
        if(spread_points > MAX_SPREAD_POINTS) {
            m_logger.Warning("GridEngine",
                StringFormat("Spread muito alto: %.0f pontos (máx: %d)",
                             spread_points, MAX_SPREAD_POINTS));
            return false;
        }
        return true;
    }

    //+--------------------------------------------------------------+
    //| Normaliza o volume para os limites do broker                 |
    //| Respeita volume mínimo, máximo e step do símbolo             |
    //+--------------------------------------------------------------+
    double NormalizeLot(double lot) {
        double min_lot  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
        double max_lot  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
        double step_lot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);

        // Arredonda para o step mais próximo (para baixo)
        lot = MathFloor(lot / step_lot) * step_lot;

        // Aplica limites
        if(lot < min_lot) lot = min_lot;
        if(lot > max_lot) lot = max_lot;

        return NormalizeDouble(lot, 2);
    }

    //+--------------------------------------------------------------+
    //| Gera o comentário padronizado para a ordem                   |
    //| Inclui prefixo, versão e nível da grade para rastreabilidade |
    //+--------------------------------------------------------------+
    string BuildOrderComment(int level, string direction) {
        return StringFormat("%s_v%s_%s_L%d",
                           OMNIB3_COMMENT_PREFIX,
                           OMNIB3_VERSION,
                           direction,
                           level);
    }

    //+--------------------------------------------------------------+
    //| Abre uma ordem de COMPRA no mercado                          |
    //| Parâmetro: level — nível atual da grade                      |
    //| Retorna: true se a ordem foi executada com sucesso            |
    //+--------------------------------------------------------------+
    bool OpenBuyOrder(int level) {
        double lot = CalculateLotSize(level);
        if(lot <= 0.0) return false;

        double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
        string comment = BuildOrderComment(level, "BUY");

        // Envia ordem de compra a mercado sem SL/TP
        // (gestão virtual feita pelo Smart Close)
        bool result = m_trade.Buy(lot, m_symbol, ask, 0, 0, comment);

        if(result) {
            m_logger.Info("GridEngine",
                StringFormat("🟢 COMPRA aberta: Nível=%d | Lote=%.2f | Preço=%.5f",
                             level, lot, ask));
        } else {
            m_logger.Error("GridEngine",
                StringFormat("❌ Falha ao abrir COMPRA: Nível=%d | Erro=%d | %s",
                             level, GetLastError(), m_trade.ResultComment()));
        }

        return result;
    }

    //+--------------------------------------------------------------+
    //| Abre uma ordem de VENDA no mercado                           |
    //| Parâmetro: level — nível atual da grade                      |
    //| Retorna: true se a ordem foi executada com sucesso            |
    //+--------------------------------------------------------------+
    bool OpenSellOrder(int level) {
        double lot = CalculateLotSize(level);
        if(lot <= 0.0) return false;

        double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        string comment = BuildOrderComment(level, "SELL");

        // Envia ordem de venda a mercado sem SL/TP
        bool result = m_trade.Sell(lot, m_symbol, bid, 0, 0, comment);

        if(result) {
            m_logger.Info("GridEngine",
                StringFormat("🔴 VENDA aberta: Nível=%d | Lote=%.2f | Preço=%.5f",
                             level, lot, bid));
        } else {
            m_logger.Error("GridEngine",
                StringFormat("❌ Falha ao abrir VENDA: Nível=%d | Erro=%d | %s",
                             level, GetLastError(), m_trade.ResultComment()));
        }

        return result;
    }

    //+--------------------------------------------------------------+
    //| Processa a lógica de grade para uma direção específica       |
    //| Verifica se o preço andou o suficiente e abre novo nível     |
    //+--------------------------------------------------------------+
    void ProcessGridDirection(ENUM_POSITION_TYPE pos_type) {
        // Conta posições atuais nesta direção
        int current_levels = m_pos_manager.CountPositionsByType(pos_type);

        // Trava de segurança: não ultrapassa o máximo de níveis
        int safe_max = MathMin(m_max_levels, GRID_MAX_ABSOLUTE);
        if(current_levels >= safe_max) {
            return; // Grade cheia — não abre mais
        }

        // Obtém espaçamento atual em preço
        double spacing = CalculateGridSpacing();
        if(spacing <= 0.0) return;

        double current_ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
        double current_bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);

        // Se não há posições nesta direção, abre a primeira (nível 0)
        if(current_levels == 0) {
            if(pos_type == POSITION_TYPE_BUY) {
                OpenBuyOrder(0);
            } else {
                OpenSellOrder(0);
            }
            return;
        }

        // Obtém preço da última posição aberta nesta direção
        double last_price = m_pos_manager.GetLastOpenPrice(pos_type);
        if(last_price <= 0.0) return;

        // Lógica de abertura do próximo nível:
        // COMPRA: preço caiu spacing pontos abaixo da última compra
        // VENDA:  preço subiu spacing pontos acima da última venda
        if(pos_type == POSITION_TYPE_BUY) {
            // Se o preço atual (ASK) caiu o suficiente, abre nova compra
            // (preço médio melhora ao comprar mais barato)
            if(last_price - current_ask >= spacing) {
                OpenBuyOrder(current_levels);
            }
        } else {
            // Se o preço atual (BID) subiu o suficiente, abre nova venda
            // (preço médio melhora ao vender mais caro)
            if(current_bid - last_price >= spacing) {
                OpenSellOrder(current_levels);
            }
        }
    }

public:
    //+--------------------------------------------------------------+
    //| Construtor completo com todos os parâmetros configuráveis    |
    //+--------------------------------------------------------------+
    CGridEngine(string symbol, int magic_number,
                ENUM_GRID_TYPE grid_type, ENUM_GRID_DIRECTION direction,
                ENUM_LOT_MODE lot_mode, double initial_lot, double lot_multiplier,
                int max_levels, int fixed_spacing,
                int atr_period, ENUM_TIMEFRAMES atr_timeframe, double atr_multiplier,
                CPositionManager *pos_manager, CLogger *logger) {

        m_symbol         = symbol;
        m_magic_number   = magic_number;
        m_grid_type      = grid_type;
        m_direction      = direction;
        m_lot_mode       = lot_mode;
        m_initial_lot    = initial_lot;
        m_lot_multiplier = lot_multiplier;
        m_fixed_spacing  = fixed_spacing;
        m_atr_period     = atr_period;
        m_atr_timeframe  = atr_timeframe;
        m_atr_multiplier = atr_multiplier;
        m_pos_manager    = pos_manager;
        m_logger         = logger;

        // Aplica trava absoluta de segurança no número de níveis
        m_max_levels = MathMin(max_levels, GRID_MAX_ABSOLUTE);

        // Configura o objeto de trade
        m_trade.SetExpertMagicNumber(m_magic_number);
        m_trade.SetDeviationInPoints(10);  // Slippage máximo aceito
        m_trade.SetTypeFilling(ORDER_FILLING_FOK);

        // Cria o handle do indicador ATR (se modo dinâmico)
        m_atr_handle = INVALID_HANDLE;
        if(m_grid_type == GRID_DYNAMIC_ATR) {
            m_atr_handle = iATR(m_symbol, m_atr_timeframe, m_atr_period);
            if(m_atr_handle == INVALID_HANDLE) {
                m_logger.Error("GridEngine", "Falha ao criar handle do ATR!");
            } else {
                m_logger.Info("GridEngine",
                    StringFormat("ATR configurado: Período=%d | TF=%s | Mult=%.2f",
                                 m_atr_period,
                                 EnumToString(m_atr_timeframe),
                                 m_atr_multiplier));
            }
        }

        m_logger.Info("GridEngine",
            StringFormat("Inicializado: %s | Tipo=%s | Dir=%s | Lote=%.2f | MaxNíveis=%d",
                         m_symbol,
                         EnumToString(m_grid_type),
                         EnumToString(m_direction),
                         m_initial_lot,
                         m_max_levels));
    }

    //+--------------------------------------------------------------+
    //| Destrutor — libera o handle do indicador ATR                 |
    //+--------------------------------------------------------------+
    ~CGridEngine() {
        if(m_atr_handle != INVALID_HANDLE) {
            IndicatorRelease(m_atr_handle);
        }
    }

    //+--------------------------------------------------------------+
    //| Calcula o tamanho do lote para o nível especificado          |
    //| Fórmula: Lote_n = Lote₀ × Multiplicador^n                   |
    //| Se LOT_FIXED, retorna sempre o lote inicial                  |
    //+--------------------------------------------------------------+
    double CalculateLotSize(int current_level) {
        double lot;

        if(m_lot_mode == LOT_FIXED) {
            // Modo fixo: mesmo lote em todos os níveis
            lot = m_initial_lot;
        } else {
            // Modo multiplicador: lote cresce exponencialmente
            lot = m_initial_lot * MathPow(m_lot_multiplier, current_level);
        }

        return NormalizeLot(lot);
    }

    //+--------------------------------------------------------------+
    //| Calcula o espaçamento da grade em PREÇO (não em pontos)     |
    //| GRID_FIXED: converte pontos fixos para preço                 |
    //| GRID_DYNAMIC_ATR: usa ATR × multiplicador                    |
    //+--------------------------------------------------------------+
    double CalculateGridSpacing() {
        if(m_grid_type == GRID_FIXED) {
            // Converte pontos para preço: pontos × tamanho_do_ponto
            double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
            return m_fixed_spacing * point;
        } else {
            // ATR já retorna em unidades de preço
            double atr = GetATRValue();
            if(atr <= 0.0) {
                m_logger.Warning("GridEngine", "ATR retornou zero, usando fallback fixo");
                double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
                return m_fixed_spacing * point;  // Fallback para espaçamento fixo
            }
            return atr * m_atr_multiplier;
        }
    }

    //+--------------------------------------------------------------+
    //| Método principal: processa a lógica de grade a cada tick     |
    //| Chamado pelo OnTick() do EA principal                        |
    //| Verifica spread e delega para cada direção configurada       |
    //+--------------------------------------------------------------+
    void ProcessGrid() {
        // Verifica spread antes de qualquer operação
        if(!IsSpreadAcceptable()) return;

        // Processa conforme a direção configurada
        switch(m_direction) {
            case GRID_BUY_ONLY:
                ProcessGridDirection(POSITION_TYPE_BUY);
                break;

            case GRID_SELL_ONLY:
                ProcessGridDirection(POSITION_TYPE_SELL);
                break;

            case GRID_BIDIRECTIONAL:
                // Bi-direcional: processa compra E venda independentemente
                ProcessGridDirection(POSITION_TYPE_BUY);
                ProcessGridDirection(POSITION_TYPE_SELL);
                break;
        }
    }

    //+--------------------------------------------------------------+
    //| Retorna referência ao objeto CTrade (para uso externo)       |
    //+--------------------------------------------------------------+
    CTrade *GetTradeObject() {
        return &m_trade;
    }

    //+--------------------------------------------------------------+
    //| Retorna o espaçamento atual formatado para log               |
    //+--------------------------------------------------------------+
    string GetSpacingInfo() {
        double spacing = CalculateGridSpacing();
        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        double spacing_points = (point > 0) ? spacing / point : 0;

        return StringFormat("Espaçamento: %.5f (%.0f pts)", spacing, spacing_points);
    }
};

//+------------------------------------------------------------------+
