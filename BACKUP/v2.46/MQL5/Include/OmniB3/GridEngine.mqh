//+------------------------------------------------------------------+
//|                                                  GridEngine.mqh  |
//|                  Omni-B3 EA v2.46 â€” Motor de Grade (B3/NETTING)  |
//|   Step multiplicador, candle gigante, integraÃ§Ã£o indicadores     |
//+------------------------------------------------------------------+
#property copyright "Projeto Omni-B3"
#property link      "https://github.com/helveciopereira/Stocks"
#property version   "2.46"
#property strict

#include "Defines.mqh"
#include "Logger.mqh"
#include "PositionManager.mqh"
#include "IndicatorHub.mqh"
#include "RecoveryMode.mqh"
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Motor de Grade adaptado para B3 (contas NETTING)                 |
//|                                                                   |
//| v2.0 â€” Melhorias inspiradas no ToTheMoon v3.5:                   |
//| - Step multiplicador (passo cresce a cada nÃ­vel)                 |
//| - Valor somado ao passo que diminui com o tempo                  |
//| - Next Lot avanÃ§ado com fator + tempo de espera                  |
//| - Controle de Candle Gigante                                      |
//| - IntegraÃ§Ã£o com IndicatorHub para validar aberturas             |
//| - IntegraÃ§Ã£o com RecoveryMode para ajustes dinÃ¢micos             |
//+------------------------------------------------------------------+
class CGridEngine {
private:
    ENUM_GRID_TYPE      m_grid_type;
    ENUM_GRID_DIRECTION m_direction;
    ENUM_LOT_MODE       m_lot_mode;
    ENUM_NEXT_LOT_MODE  m_next_lot_mode;

    string  m_symbol;
    int     m_magic_number;
    double  m_initial_lot;        // Volume inicial em contratos
    double  m_lot_multiplier;     // Multiplicador de lote entre nÃ­veis
    int     m_max_levels;
    int     m_fixed_spacing;      // EspaÃ§amento fixo em pontos

    // ATR para grade dinÃ¢mica
    int     m_atr_period;
    ENUM_TIMEFRAMES m_atr_timeframe;
    double  m_atr_multiplier;

    // Step multiplicador â€” passo crescente a cada nÃ­vel
    double  m_step_multiplier;    // Multiplicador do passo (ex: 1.2 = +20%)
    int     m_step_min;           // Passo mÃ­nimo em pontos (0 = sem limite)
    int     m_step_max;           // Passo mÃ¡ximo em pontos (0 = sem limite)

    // Valor somado ao passo que diminui com o tempo
    int     m_added_step;         // Pontos extras na abertura
    int     m_added_step_decay;   // Segundos para zerar o valor somado

    // Next Lot â€” controle de prÃ³ximo lote
    double  m_next_lot_factor;    // Fator do prÃ³ximo lote (multiplicar ou somar)
    int     m_next_lot_wait;      // Segundos de espera entre ordens da grid
    int     m_next_lot_start_wait;// A partir de qual nÃ­vel comeÃ§a a esperar
    int     m_next_lot_stop_wait; // Em qual nÃ­vel para de esperar
    bool    m_allow_big_lot;      // Permitir lote grande?
    bool    m_allow_smaller_bigger;// Permitir lote menor/maior que limites?

    // Candle Gigante â€” proteÃ§Ã£o contra movimentos bruscos
    int     m_giant_candle_wait_initial; // Segundos para esperar apÃ³s candle gigante (inicial)
    int     m_giant_candle_size_initial; // Tamanho em pontos do candle gigante (inicial)
    int     m_giant_candle_wait_grid;    // Segundos para esperar (grid)
    int     m_giant_candle_size_grid;    // Tamanho em pontos (grid)
    datetime m_last_giant_candle_time;   // Ãšltimo candle gigante detectado

    // Controle de espera entre ordens
    int     m_wait_open_same;     // Segundos entre ordens na mesma direÃ§Ã£o
    datetime m_last_order_time;   // Ãšltimo envio de ordem

    // Indicadores para abertura
    bool    m_use_indicator_initial;  // Usar indicador para ordem inicial?
    bool    m_use_indicator_grid;     // Usar indicador para ordens da grid?
    bool    m_open_on_candle;         // Abrir apenas no inÃ­cio do candle?

    CTrade  m_trade;

    CPositionManager *m_pos_manager;
    CIndicatorHub    *m_ind_hub;
    CRecoveryMode    *m_recovery;
    CLogger          *m_logger;

    //+--------------------------------------------------------------+
    //| Verifica se spread estÃ¡ aceitÃ¡vel                             |
    //+--------------------------------------------------------------+
    bool IsSpreadAcceptable() {
        double spread = (double)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
        if(spread > MAX_SPREAD_POINTS) {
            m_logger.Warning("GridEngine",
                StringFormat("Spread alto: %.0f pts (mÃ¡x: %d)", spread, MAX_SPREAD_POINTS));
            return false;
        }
        return true;
    }

    //+--------------------------------------------------------------+
    //| Verifica se Ãºltimo candle foi "gigante" (proteÃ§Ã£o)           |
    //| Um candle gigante indica notÃ­cia ou evento inesperado        |
    //+--------------------------------------------------------------+
    bool IsGiantCandle(int size_points) {
        if(size_points <= 0) return false;  // Desabilitado

        MqlRates rates[1];
        if(CopyRates(m_symbol, PERIOD_CURRENT, 0, 1, rates) <= 0) return false;

        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        double candle_size = MathAbs(rates[0].high - rates[0].low) / point;

        if(candle_size >= size_points) {
            m_last_giant_candle_time = TimeCurrent();
            m_logger.Warning("GridEngine",
                StringFormat("[CANDLE GIGANTE] %.0f pts (limite: %d)", candle_size, size_points));
            return true;
        }
        return false;
    }

    //+--------------------------------------------------------------+
    //| Verifica se estamos em perÃ­odo de espera apÃ³s candle gigante |
    //+--------------------------------------------------------------+
    bool IsWaitingAfterGiantCandle(int wait_seconds) {
        if(wait_seconds <= 0 || m_last_giant_candle_time == 0) return false;
        return (TimeCurrent() - m_last_giant_candle_time) < wait_seconds;
    }

    //+--------------------------------------------------------------+
    //| Verifica tempo de espera entre ordens                        |
    //+--------------------------------------------------------------+
    bool IsWaitingBetweenOrders() {
        if(m_wait_open_same <= 0) return false;
        return (TimeCurrent() - m_last_order_time) < m_wait_open_same;
    }

    //+--------------------------------------------------------------+
    //| Verifica espera do Next Lot (entre ordens da grid)           |
    //+--------------------------------------------------------------+
    bool IsWaitingNextLot(int current_level) {
        if(m_next_lot_wait <= 0) return false;

        // Verifica se estÃ¡ na faixa de espera
        if(current_level < m_next_lot_start_wait) return false;
        if(m_next_lot_stop_wait > 0 && current_level >= m_next_lot_stop_wait) return false;

        // Verifica se tempo de espera expirou
        return (TimeCurrent() - m_last_order_time) < m_next_lot_wait;
    }

    //+--------------------------------------------------------------+
    //| Normaliza volume para contratos inteiros vÃ¡lidos             |
    //| B3 minicontratos: min=1, step=1, max varia por broker       |
    //+--------------------------------------------------------------+
    double NormalizeLot(double lot) {
        double min_lot  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
        double max_lot  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
        double step_lot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);

        // Arredonda para o step mais prÃ³ximo (para baixo)
        lot = MathFloor(lot / step_lot) * step_lot;
        if(lot < min_lot) lot = min_lot;
        if(lot > max_lot) lot = max_lot;

        return NormalizeDouble(lot, 2);
    }

    //+--------------------------------------------------------------+
    //| Detecta modo de preenchimento aceito pelo sÃ­mbolo            |
    //| B3 geralmente usa RETURN ou IOC, nÃ£o FOK                     |
    //+--------------------------------------------------------------+
    ENUM_ORDER_TYPE_FILLING DetectFillingMode() {
        long filling = SymbolInfoInteger(m_symbol, SYMBOL_FILLING_MODE);

        // Testa cada modo na ordem de preferÃªncia para B3
        if((filling & SYMBOL_FILLING_IOC) != 0)
            return ORDER_FILLING_IOC;
        if((filling & SYMBOL_FILLING_FOK) != 0)
            return ORDER_FILLING_FOK;

        return ORDER_FILLING_RETURN;
    }

    //+--------------------------------------------------------------+
    //| Gera comentÃ¡rio padronizado para a ordem                     |
    //+--------------------------------------------------------------+
    string BuildComment(int level, string dir) {
        return StringFormat("%s_v%s_%s_L%d", OMNIB3_COMMENT_PREFIX,
                           OMNIB3_VERSION, dir, level);
    }

    //+--------------------------------------------------------------+
    //| Abre ordem de COMPRA (em NETTING, soma Ã  posiÃ§Ã£o existente)  |
    //+--------------------------------------------------------------+
    bool OpenBuyOrder(int level) {
        double lot = CalculateLotSize(level);
        if(lot <= 0.0) return false;

        double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
        string comment = BuildComment(level, "BUY");

        bool is_recovery = (m_recovery != NULL && m_recovery.IsActive());

        bool result = m_trade.Buy(lot, m_symbol, ask, 0, 0, comment);
        if(result) {
            // Registra nÃ­vel virtual no PositionManager
            m_pos_manager.RegisterLevel(ask, lot, 1, is_recovery);
            m_last_order_time = TimeCurrent();
            m_logger.Info("GridEngine",
                StringFormat("[COMPRA] Nivel=%d | %.0f contratos @ %.2f%s",
                             level, lot, ask, is_recovery ? " [RECOVERY]" : ""));
        } else {
            m_logger.Error("GridEngine",
                StringFormat("[ERRO COMPRA] Nivel=%d | Erro=%d | %s",
                             level, GetLastError(), m_trade.ResultComment()));
        }
        return result;
    }

    //+--------------------------------------------------------------+
    //| Abre ordem de VENDA (em NETTING, soma Ã  posiÃ§Ã£o existente)   |
    //+--------------------------------------------------------------+
    bool OpenSellOrder(int level) {
        double lot = CalculateLotSize(level);
        if(lot <= 0.0) return false;

        double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        string comment = BuildComment(level, "SELL");

        bool is_recovery = (m_recovery != NULL && m_recovery.IsActive());

        bool result = m_trade.Sell(lot, m_symbol, bid, 0, 0, comment);
        if(result) {
            m_pos_manager.RegisterLevel(bid, lot, -1, is_recovery);
            m_last_order_time = TimeCurrent();
            m_logger.Info("GridEngine",
                StringFormat("[VENDA] Nivel=%d | %.0f contratos @ %.2f%s",
                             level, lot, bid, is_recovery ? " [RECOVERY]" : ""));
        } else {
            m_logger.Error("GridEngine",
                StringFormat("[ERRO VENDA] Nivel=%d | Erro=%d | %s",
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
                CPositionManager *pos_manager, CIndicatorHub *ind_hub, CLogger *logger) {

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
        m_ind_hub        = ind_hub;
        m_logger         = logger;
        m_recovery       = NULL;
        m_max_levels     = MathMin(max_levels, GRID_MAX_ABSOLUTE);

        // Defaults para novos parÃ¢metros
        m_next_lot_mode      = NEXT_LOT_MULTIPLY;
        m_next_lot_factor    = 1.3;
        m_next_lot_wait      = 0;
        m_next_lot_start_wait = 1;
        m_next_lot_stop_wait = 100;
        m_allow_big_lot      = false;
        m_allow_smaller_bigger = true;

        m_step_multiplier    = 1.0;  // Sem multiplicaÃ§Ã£o por padrÃ£o
        m_step_min           = 0;
        m_step_max           = 0;
        m_added_step         = 0;
        m_added_step_decay   = 0;

        m_giant_candle_wait_initial = 0;
        m_giant_candle_size_initial = 100;
        m_giant_candle_wait_grid    = 0;
        m_giant_candle_size_grid    = 100;
        m_last_giant_candle_time    = 0;

        m_wait_open_same     = 30;
        m_last_order_time    = 0;

        m_use_indicator_initial = true;
        m_use_indicator_grid    = false;
        m_open_on_candle        = true;

        // Configura objeto de trade
        m_trade.SetExpertMagicNumber(m_magic_number);
        m_trade.SetDeviationInPoints(10);
        m_trade.SetTypeFilling(DetectFillingMode());

        m_logger.Info("GridEngine",
            StringFormat("Init: %s | Tipo=%s | Dir=%s | Vol=%.0f | MaxNÃ­veis=%d",
                         m_symbol, EnumToString(m_grid_type),
                         EnumToString(m_direction), m_initial_lot, m_max_levels));
    }

    //+--------------------------------------------------------------+
    //| Define referÃªncia ao Recovery Mode                            |
    //+--------------------------------------------------------------+
    void SetRecoveryMode(CRecoveryMode *recovery) { m_recovery = recovery; }

    //+--------------------------------------------------------------+
    //| Configura step multiplicador                                  |
    //+--------------------------------------------------------------+
    void SetStepMultiplier(double multiplier, int min_pts, int max_pts) {
        m_step_multiplier = multiplier;
        m_step_min = min_pts;
        m_step_max = max_pts;
        m_logger.Info("GridEngine",
            StringFormat("Step Mult: x%.2f | Min=%d | Max=%d pts",
                         multiplier, min_pts, max_pts));
    }

    //+--------------------------------------------------------------+
    //| Configura valor somado ao passo                               |
    //+--------------------------------------------------------------+
    void SetAddedStep(int extra_points, int decay_seconds) {
        m_added_step = extra_points;
        m_added_step_decay = decay_seconds;
    }

    //+--------------------------------------------------------------+
    //| Configura Next Lot avanÃ§ado                                   |
    //+--------------------------------------------------------------+
    void SetNextLot(ENUM_NEXT_LOT_MODE mode, double factor, int wait_seconds,
                    int start_wait, int stop_wait, bool allow_big, bool allow_sm_bg) {
        m_next_lot_mode = mode;
        m_next_lot_factor = factor;
        m_next_lot_wait = wait_seconds;
        m_next_lot_start_wait = start_wait;
        m_next_lot_stop_wait = stop_wait;
        m_allow_big_lot = allow_big;
        m_allow_smaller_bigger = allow_sm_bg;
        m_logger.Info("GridEngine",
            StringFormat("Next Lot: Modo=%s | Fator=%.2f | Espera=%ds",
                         EnumToString(mode), factor, wait_seconds));
    }

    //+--------------------------------------------------------------+
    //| Configura Candle Gigante                                      |
    //+--------------------------------------------------------------+
    void SetGiantCandle(int wait_initial, int size_initial, int wait_grid, int size_grid) {
        m_giant_candle_wait_initial = wait_initial;
        m_giant_candle_size_initial = size_initial;
        m_giant_candle_wait_grid = wait_grid;
        m_giant_candle_size_grid = size_grid;
    }

    //+--------------------------------------------------------------+
    //| Configura uso de indicadores                                  |
    //+--------------------------------------------------------------+
    void SetIndicatorUsage(bool use_initial, bool use_grid, bool open_candle) {
        m_use_indicator_initial = use_initial;
        m_use_indicator_grid = use_grid;
        m_open_on_candle = open_candle;
    }

    //+--------------------------------------------------------------+
    //| Configura tempo de espera entre ordens                       |
    //+--------------------------------------------------------------+
    void SetWaitTime(int wait_same_direction) {
        m_wait_open_same = wait_same_direction;
    }

    //+--------------------------------------------------------------+
    //| Calcula volume para o nÃ­vel especificado                     |
    //| Considera modo de lote, next lot e recovery                  |
    //+--------------------------------------------------------------+
    double CalculateLotSize(int level) {
        double lot;

        if(level == 0) {
            // Primeiro nÃ­vel â€” sempre lote inicial
            lot = m_initial_lot;
        } else {
            // NÃ­veis da grid â€” aplica modo de cÃ¡lculo
            switch(m_next_lot_mode) {
                case NEXT_LOT_FIXED:
                    lot = m_initial_lot;
                    break;
                case NEXT_LOT_MULTIPLY:
                case NEXT_LOT_WAIT_MULTIPLY:
                    lot = m_initial_lot * MathPow(m_next_lot_factor, level);
                    break;
                case NEXT_LOT_ADD:
                case NEXT_LOT_WAIT_ADD:
                    lot = m_initial_lot + (m_next_lot_factor * level);
                    break;
                default:
                    lot = m_initial_lot;
            }
        }

        // Aplica ajuste de recovery (lote extra)
        if(m_recovery != NULL && m_recovery.IsActive()) {
            lot += m_recovery.GetExtraLotFactor();
        }

        return NormalizeLot(lot);
    }

    //+--------------------------------------------------------------+
    //| Calcula espaÃ§amento da grade para um nÃ­vel especÃ­fico        |
    //| Considera step multiplier, valor somado e recovery           |
    //+--------------------------------------------------------------+
    double CalculateGridSpacing(int level = 0) {
        double base_spacing;

        if(m_grid_type == GRID_FIXED) {
            double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
            base_spacing = m_fixed_spacing * point;
        } else {
            // Grade dinÃ¢mica â€” usa ATR do IndicatorHub
            double atr = (m_ind_hub != NULL) ? m_ind_hub.GetATRValue() : 0.0;
            if(atr <= 0.0) {
                m_logger.Warning("GridEngine", "ATR=0, usando fallback fixo");
                base_spacing = m_fixed_spacing * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
            } else {
                base_spacing = atr * m_atr_multiplier;
            }
        }

        // Aplica step multiplier (passo cresce a cada nÃ­vel)
        if(m_step_multiplier > 1.0 && level > 0) {
            base_spacing *= MathPow(m_step_multiplier, level - 1);
        }

        // Aplica valor somado ao passo (diminui com o tempo)
        if(m_added_step > 0 && m_pos_manager.CountLevels() > 0) {
            double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
            double extra = m_added_step * point;

            // Diminui linearmente com o tempo
            if(m_added_step_decay > 0) {
                datetime oldest = m_pos_manager.GetOldestLevelTime();
                int elapsed = (int)(TimeCurrent() - oldest);
                double decay_factor = 1.0 - ((double)elapsed / m_added_step_decay);
                if(decay_factor < 0.0) decay_factor = 0.0;
                extra *= decay_factor;
            }
            base_spacing += extra;
        }

        // Aplica ajuste de recovery (passo extra)
        if(m_recovery != NULL && m_recovery.IsActive()) {
            double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
            base_spacing += m_recovery.GetExtraStepPoints() * point;
        }

        // Aplica limites de passo
        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        if(m_step_min > 0) {
            double min_spacing = m_step_min * point;
            if(base_spacing < min_spacing) base_spacing = min_spacing;
        }
        if(m_step_max > 0) {
            double max_spacing = m_step_max * point;
            if(base_spacing > max_spacing) base_spacing = max_spacing;
        }

        return base_spacing;
    }

    //+--------------------------------------------------------------+
    //| Processa lÃ³gica de grade a cada tick                         |
    //| Integra com indicadores, candle gigante, espera e recovery   |
    //+--------------------------------------------------------------+
    void ProcessGrid(int signal = 0) {
        if(!IsSpreadAcceptable()) return;

        int current_levels = m_pos_manager.CountLevels();
        int safe_max = MathMin(m_max_levels, GRID_MAX_ABSOLUTE);

        // Trava de seguranÃ§a
        if(current_levels >= safe_max) return;

        // Espera entre ordens
        if(IsWaitingBetweenOrders()) return;

        double spacing = CalculateGridSpacing(current_levels);
        if(spacing <= 0.0) return;

        // Se nÃ£o hÃ¡ nÃ­veis, abre o primeiro (nÃ­vel 0)
        if(current_levels == 0) {
            // Verifica candle gigante para ordem inicial
            if(m_giant_candle_wait_initial > 0) {
                if(IsGiantCandle(m_giant_candle_size_initial)) return;
                if(IsWaitingAfterGiantCandle(m_giant_candle_wait_initial)) return;
            }

            // Verifica indicador para ordem inicial (se configurado)
            if(m_use_indicator_initial && signal == 0) return;

            // Determina direÃ§Ã£o
            if(m_direction == GRID_BUY_ONLY) {
                if(m_use_indicator_initial && signal < 0) return;  // Sinal de venda â†’ nÃ£o compra
                OpenBuyOrder(0);
            } else {
                if(m_use_indicator_initial && signal > 0) return;  // Sinal de compra â†’ nÃ£o vende
                OpenSellOrder(0);
            }
            return;
        }

        // Verifica candle gigante para ordens da grid
        if(m_giant_candle_wait_grid > 0) {
            if(IsGiantCandle(m_giant_candle_size_grid)) return;
            if(IsWaitingAfterGiantCandle(m_giant_candle_wait_grid)) return;
        }

        // Verifica espera do Next Lot
        if(IsWaitingNextLot(current_levels)) return;

        // Verifica indicador para ordens da grid (se configurado)
        if(m_use_indicator_grid && m_ind_hub != NULL) {
            if(!m_ind_hub.PassAllFilters()) return;
        }

        // ObtÃ©m preÃ§o do Ãºltimo nÃ­vel
        double last_price = m_pos_manager.GetLastLevelPrice();
        if(last_price <= 0.0) return;

        double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
        double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);

        if(m_direction == GRID_BUY_ONLY) {
            // COMPRA: abre novo nÃ­vel quando preÃ§o CAI spacing pontos
            if(last_price - ask >= spacing) {
                OpenBuyOrder(current_levels);
            }
        } else {
            // VENDA: abre novo nÃ­vel quando preÃ§o SOBE spacing pontos
            if(bid - last_price >= spacing) {
                OpenSellOrder(current_levels);
            }
        }
    }

    //+--------------------------------------------------------------+
    //| Retorna referÃªncia ao CTrade para uso pelo SmartClose        |
    //+--------------------------------------------------------------+
    CTrade *GetTradeObject() { return &m_trade; }

    //+--------------------------------------------------------------+
    //| Info do espaÃ§amento para log                                  |
    //+--------------------------------------------------------------+
    string GetSpacingInfo() {
        double spacing = CalculateGridSpacing(0);
        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        double pts = (point > 0) ? spacing / point : 0;
        return StringFormat("EspaÃ§amento: %.2f (%.0f pts) | StepMult=%.2f",
                           spacing, pts, m_step_multiplier);
    }
};

//+------------------------------------------------------------------+
