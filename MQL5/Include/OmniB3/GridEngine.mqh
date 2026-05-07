//+------------------------------------------------------------------+
//|                                                  GridEngine.mqh  |
//|                  Omni-B3 EA v1.1 — Motor de Grade (B3/NETTING)   |
//|     Abertura de ordens em grade para minicontratos WIN/WDO       |
//+------------------------------------------------------------------+
#property copyright "Projeto Omni-B3"
#property link      "https://github.com/helveciopereira/Stocks"
#property version   "1.10"
#property strict

#include "Defines.mqh"
#include "Logger.mqh"
#include "PositionManager.mqh"
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Motor de Grade adaptado para B3 (contas NETTING)                 |
//|                                                                   |
//| Diferenças do NETTING vs HEDGING:                                |
//| - Apenas 1 posição por símbolo (ordens somam ao volume)          |
//| - Sem bi-direcional (compra OU venda, nunca ambos)               |
//| - Volume em contratos inteiros (1, 2, 3...)                      |
//| - Níveis rastreados virtualmente via PositionManager              |
//+------------------------------------------------------------------+
class CGridEngine {
private:
    ENUM_GRID_TYPE      m_grid_type;
    ENUM_GRID_DIRECTION m_direction;
    ENUM_LOT_MODE       m_lot_mode;

    string  m_symbol;
    int     m_magic_number;
    double  m_initial_lot;        // Volume inicial em contratos
    double  m_lot_multiplier;
    int     m_max_levels;
    int     m_fixed_spacing;      // Espaçamento fixo em pontos
    int     m_atr_period;
    ENUM_TIMEFRAMES m_atr_timeframe;
    double  m_atr_multiplier;

    int     m_atr_handle;
    CTrade  m_trade;

    CPositionManager *m_pos_manager;
    CLogger          *m_logger;

    //+--------------------------------------------------------------+
    //| Obtém valor atual do ATR                                     |
    //+--------------------------------------------------------------+
    double GetATRValue() {
        if(m_atr_handle == INVALID_HANDLE) return 0.0;
        double buf[1];
        if(CopyBuffer(m_atr_handle, 0, 0, 1, buf) <= 0) return 0.0;
        return buf[0];
    }

    //+--------------------------------------------------------------+
    //| Verifica se spread está aceitável                             |
    //+--------------------------------------------------------------+
    bool IsSpreadAcceptable() {
        double spread = (double)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
        if(spread > MAX_SPREAD_POINTS) {
            m_logger.Warning("GridEngine",
                StringFormat("Spread alto: %.0f pts (máx: %d)", spread, MAX_SPREAD_POINTS));
            return false;
        }
        return true;
    }

    //+--------------------------------------------------------------+
    //| Normaliza volume para contratos inteiros válidos             |
    //| B3 minicontratos: min=1, step=1, max varia por broker       |
    //+--------------------------------------------------------------+
    double NormalizeLot(double lot) {
        double min_lot  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
        double max_lot  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
        double step_lot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);

        // Arredonda para o step mais próximo (para baixo)
        lot = MathFloor(lot / step_lot) * step_lot;
        if(lot < min_lot) lot = min_lot;
        if(lot > max_lot) lot = max_lot;

        return NormalizeDouble(lot, 2);
    }

    //+--------------------------------------------------------------+
    //| Detecta modo de preenchimento aceito pelo símbolo            |
    //| B3 geralmente usa RETURN ou IOC, não FOK                     |
    //+--------------------------------------------------------------+
    ENUM_ORDER_TYPE_FILLING DetectFillingMode() {
        long filling = SymbolInfoInteger(m_symbol, SYMBOL_FILLING_MODE);

        // Testa cada modo na ordem de preferência para B3
        if((filling & SYMBOL_FILLING_IOC) != 0)
            return ORDER_FILLING_IOC;
        if((filling & SYMBOL_FILLING_FOK) != 0)
            return ORDER_FILLING_FOK;

        return ORDER_FILLING_RETURN;
    }

    //+--------------------------------------------------------------+
    //| Gera comentário padronizado para a ordem                     |
    //+--------------------------------------------------------------+
    string BuildComment(int level, string dir) {
        return StringFormat("%s_v%s_%s_L%d", OMNIB3_COMMENT_PREFIX,
                           OMNIB3_VERSION, dir, level);
    }

    //+--------------------------------------------------------------+
    //| Abre ordem de COMPRA (em NETTING, soma à posição existente)  |
    //+--------------------------------------------------------------+
    bool OpenBuyOrder(int level) {
        double lot = CalculateLotSize(level);
        if(lot <= 0.0) return false;

        double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
        string comment = BuildComment(level, "BUY");

        bool result = m_trade.Buy(lot, m_symbol, ask, 0, 0, comment);
        if(result) {
            // Registra nível virtual no PositionManager
            m_pos_manager.RegisterLevel(ask, lot, 1);
            m_logger.Info("GridEngine",
                StringFormat("🟢 COMPRA: Nível=%d | %.0f contratos @ %.2f",
                             level, lot, ask));
        } else {
            m_logger.Error("GridEngine",
                StringFormat("❌ Falha COMPRA: Nível=%d | Erro=%d | %s",
                             level, GetLastError(), m_trade.ResultComment()));
        }
        return result;
    }

    //+--------------------------------------------------------------+
    //| Abre ordem de VENDA (em NETTING, soma à posição existente)   |
    //+--------------------------------------------------------------+
    bool OpenSellOrder(int level) {
        double lot = CalculateLotSize(level);
        if(lot <= 0.0) return false;

        double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        string comment = BuildComment(level, "SELL");

        bool result = m_trade.Sell(lot, m_symbol, bid, 0, 0, comment);
        if(result) {
            m_pos_manager.RegisterLevel(bid, lot, -1);
            m_logger.Info("GridEngine",
                StringFormat("🔴 VENDA: Nível=%d | %.0f contratos @ %.2f",
                             level, lot, bid));
        } else {
            m_logger.Error("GridEngine",
                StringFormat("❌ Falha VENDA: Nível=%d | Erro=%d | %s",
                             level, GetLastError(), m_trade.ResultComment()));
        }
        return result;
    }

public:
    //+--------------------------------------------------------------+
    //| Construtor                                                    |
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
        m_max_levels     = MathMin(max_levels, GRID_MAX_ABSOLUTE);

        // Configura objeto de trade
        m_trade.SetExpertMagicNumber(m_magic_number);
        m_trade.SetDeviationInPoints(10);
        m_trade.SetTypeFilling(DetectFillingMode());

        // Handle do ATR (se grade dinâmica)
        m_atr_handle = INVALID_HANDLE;
        if(m_grid_type == GRID_DYNAMIC_ATR) {
            m_atr_handle = iATR(m_symbol, m_atr_timeframe, m_atr_period);
            if(m_atr_handle == INVALID_HANDLE)
                m_logger.Error("GridEngine", "Falha ao criar handle do ATR!");
            else
                m_logger.Info("GridEngine",
                    StringFormat("ATR: Período=%d | TF=%s | Mult=%.2f",
                                 m_atr_period, EnumToString(m_atr_timeframe), m_atr_multiplier));
        }

        m_logger.Info("GridEngine",
            StringFormat("Init: %s | Tipo=%s | Dir=%s | Vol=%.0f | MaxNíveis=%d",
                         m_symbol, EnumToString(m_grid_type),
                         EnumToString(m_direction), m_initial_lot, m_max_levels));
    }

    ~CGridEngine() {
        if(m_atr_handle != INVALID_HANDLE)
            IndicatorRelease(m_atr_handle);
    }

    //+--------------------------------------------------------------+
    //| Calcula volume para o nível especificado                     |
    //+--------------------------------------------------------------+
    double CalculateLotSize(int level) {
        double lot;
        if(m_lot_mode == LOT_FIXED)
            lot = m_initial_lot;
        else
            lot = m_initial_lot * MathPow(m_lot_multiplier, level);
        return NormalizeLot(lot);
    }

    //+--------------------------------------------------------------+
    //| Calcula espaçamento da grade em unidades de preço            |
    //+--------------------------------------------------------------+
    double CalculateGridSpacing() {
        if(m_grid_type == GRID_FIXED) {
            double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
            return m_fixed_spacing * point;
        } else {
            double atr = GetATRValue();
            if(atr <= 0.0) {
                m_logger.Warning("GridEngine", "ATR=0, usando fallback fixo");
                return m_fixed_spacing * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
            }
            return atr * m_atr_multiplier;
        }
    }

    //+--------------------------------------------------------------+
    //| Processa lógica de grade a cada tick                         |
    //+--------------------------------------------------------------+
    void ProcessGrid() {
        if(!IsSpreadAcceptable()) return;

        int current_levels = m_pos_manager.CountLevels();
        int safe_max = MathMin(m_max_levels, GRID_MAX_ABSOLUTE);

        // Trava de segurança
        if(current_levels >= safe_max) return;

        double spacing = CalculateGridSpacing();
        if(spacing <= 0.0) return;

        // Se não há níveis, abre o primeiro (nível 0)
        if(current_levels == 0) {
            if(m_direction == GRID_BUY_ONLY)
                OpenBuyOrder(0);
            else
                OpenSellOrder(0);
            return;
        }

        // Obtém preço do último nível
        double last_price = m_pos_manager.GetLastLevelPrice();
        if(last_price <= 0.0) return;

        double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
        double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);

        if(m_direction == GRID_BUY_ONLY) {
            // COMPRA: abre novo nível quando preço CAI spacing pontos
            if(last_price - ask >= spacing) {
                OpenBuyOrder(current_levels);
            }
        } else {
            // VENDA: abre novo nível quando preço SOBE spacing pontos
            if(bid - last_price >= spacing) {
                OpenSellOrder(current_levels);
            }
        }
    }

    //+--------------------------------------------------------------+
    //| Retorna referência ao CTrade para uso pelo SmartClose        |
    //+--------------------------------------------------------------+
    CTrade *GetTradeObject() { return &m_trade; }

    //+--------------------------------------------------------------+
    //| Info do espaçamento para log                                  |
    //+--------------------------------------------------------------+
    string GetSpacingInfo() {
        double spacing = CalculateGridSpacing();
        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        double pts = (point > 0) ? spacing / point : 0;
        return StringFormat("Espaçamento: %.2f (%.0f pts)", spacing, pts);
    }
};

//+------------------------------------------------------------------+
