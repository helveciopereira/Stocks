//+------------------------------------------------------------------+
//|                                                  SmartClose.mqh  |
//|              Omni-B3 EA v2.45 — Smart Close para B3/NETTING       |
//|   12+ modos de fechamento inspirados no ToTheMoon v3.5          |
//+------------------------------------------------------------------+
#property copyright "Projeto Omni-B3"
#property link      "https://github.com/helveciopereira/Stocks"
#property version   "2.45"
#property strict

#include "Defines.mqh"
#include "Logger.mqh"
#include "PositionManager.mqh"
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Smart Close para contas NETTING — v2.0                            |
//|                                                                   |
//| Em NETTING, não podemos fechar posições individuais por ticket.  |
//| Em vez disso:                                                     |
//| 1. Calculamos P&L virtual de cada nível da grade                 |
//| 2. Dependendo do modo de fechamento, decidimos o que fechar      |
//| 3. Enviamos UMA contra-ordem para reduzir a posição              |
//| 4. Removemos os níveis virtuais correspondentes                  |
//|                                                                   |
//| 12+ modos de fechamento inspirados no ToTheMoon v3.5:            |
//| - Smart Close (pior/mais antigo)                                 |
//| - TakeProfit (total, monetário, aceitável)                       |
//| - BreakEven (estático, trailing)                                 |
//| - Por quantidade de ordens/lotes                                  |
//| - Aceitar prejuízo (quando DD baixo e muitos lotes)              |
//+------------------------------------------------------------------+
class CSmartClose {
private:
    string             m_symbol;
    int                m_magic_number;
    ENUM_CLOSE_MODE    m_close_mode;       // Modo de fechamento ativo
    ENUM_CLOSE_TARGET  m_close_target;     // Alvo (pior/mais antigo)
    double             m_margin_ticks;     // Margem de segurança em ticks

    // TakeProfit configurável
    ENUM_TP_MODE       m_tp_mode;          // Modo do TP (pontos, ATR, monetário)
    double             m_tp_points;        // TP em pontos
    double             m_tp_monetary;      // TP monetário (BRL)
    double             m_tp_acceptable;    // TP aceitável (pode ser negativo!)
    double             m_tp_monetary_acceptable; // TP monetário aceitável
    double             m_tp_multiplier;    // Multiplicador do TP

    // Redução do TP com o tempo
    ENUM_TP_REDUCE_TYPE m_tp_reduce_type;
    double             m_tp_reduce_dd;     // DD% para começar a reduzir
    double             m_tp_reduce_search; // Distância para buscar preço
    int                m_tp_reduce_time;   // Minutos para redução
    bool               m_reduce_last;      // Reduzir na última ordem?

    // BreakEven
    ENUM_BE_MODE       m_be_mode;
    double             m_be_points;        // BreakEven em pontos
    double             m_be_acceptable;    // BreakEven aceitável
    ENUM_BE_TYPE       m_be_type;          // Estático ou trailing
    double             m_be_trail_factor;  // Fator do trailing (0-1)

    // Limites para fechamento por quantidade
    double             m_lot_sum_total;    // Fecha se soma lotes > este valor
    double             m_lot_sum_half;     // Fecha metade se lotes > este valor
    double             m_lot_avg_total;    // Fecha se média lotes > este valor
    int                m_order_count_total;// Fecha se qtde ordens > este valor
    int                m_order_count_half; // Fecha metade se qtde > este valor
    double             m_lot_on_close;     // Lote para usar no fechamento
    double             m_min_profit;       // Lucro mínimo para fechar (pode ser negativo)

    // Aceitar prejuízo
    double             m_dd_accept_loss;   // DD% abaixo do qual aceitar perda
    double             m_accept_loss_value;// Valor de perda aceitável (BRL)

    // Trailing virtual da Grade (Gain e Stop Gain Móveis)
    bool               m_use_trailing;     // Habilitar trailing virtual para a grade
    double             m_trail_trigger;    // Gatilho de ativação do trailing (pontos)
    double             m_trail_stop_dist;  // Distância do Stop Gain (pontos)
    double             m_trail_tp_dist;    // Distância do Gain Móvel (pontos)
    double             m_trail_step;       // Passo de atualização (pontos)
    bool               m_trail_active;     // Indica se o trailing está ativo na grade
    double             m_max_price_seen;   // Rastreamento do extremo do preço a favor
    double             m_virtual_sl;       // Preço absoluto do Stop Gain virtual
    double             m_virtual_tp;       // Preço absoluto do Gain virtual

    CTrade             m_trade;
    CPositionManager  *m_pos_manager;
    CLogger           *m_logger;
    datetime           m_last_close_time;

    //+--------------------------------------------------------------+
    //| Calcula custo da margem de segurança em BRL                  |
    //+--------------------------------------------------------------+
    double CalculateMarginCost(double volume) {
        double tick_value = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
        return m_margin_ticks * tick_value * volume;
    }

    //+--------------------------------------------------------------+
    //| Verifica cooldown entre fechamentos                          |
    //+--------------------------------------------------------------+
    bool IsCooldownExpired() {
        return (TimeCurrent() - m_last_close_time) >= SMART_CLOSE_COOLDOWN;
    }

    //+--------------------------------------------------------------+
    //| Detecta modo de preenchimento do símbolo                     |
    //+--------------------------------------------------------------+
    ENUM_ORDER_TYPE_FILLING DetectFillingMode() {
        long filling = SymbolInfoInteger(m_symbol, SYMBOL_FILLING_MODE);
        if((filling & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
        if((filling & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
        return ORDER_FILLING_RETURN;
    }

    //+--------------------------------------------------------------+
    //| Calcula o TakeProfit efetivo considerando reduções            |
    //| Retorna valor em BRL que deve ser alcançado para fechar      |
    //+--------------------------------------------------------------+
    double CalculateEffectiveTP(SGridState &state) {
        double tp = 0.0;

        // Cálculo base do TP
        switch(m_tp_mode) {
            case TP_FIXED_POINTS: {
                double tick_size  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
                double tick_value = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
                double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
                tp = (m_tp_points * point / tick_size) * tick_value * state.total_volume;
                tp *= m_tp_multiplier;
                break;
            }
            case TP_MONETARY:
                tp = m_tp_monetary * m_tp_multiplier;
                break;
            default:
                tp = m_tp_points; // Fallback
        }

        // Aplica redução por tempo
        if(m_tp_reduce_type == TP_REDUCE_BY_TIME && m_tp_reduce_time > 0) {
            int elapsed_min = (int)((TimeCurrent() - state.oldest_level_time) / 60);
            if(elapsed_min > m_tp_reduce_time) {
                double reduce_factor = 1.0 - ((double)(elapsed_min - m_tp_reduce_time) /
                                               (double)m_tp_reduce_time);
                if(reduce_factor < 0.1) reduce_factor = 0.1; // Mínimo 10%
                tp *= reduce_factor;
                m_logger.Debug("SmartClose",
                    StringFormat("TP reduzido por tempo: fator=%.2f (%dmin)", reduce_factor, elapsed_min));
            }
        }

        // Aplica redução por DD
        if(m_tp_reduce_type == TP_REDUCE_BY_DD && m_tp_reduce_dd > 0.0) {
            if(state.max_drawdown_pct >= m_tp_reduce_dd) {
                double dd_factor = m_tp_reduce_dd / state.max_drawdown_pct;
                if(dd_factor < 0.1) dd_factor = 0.1;
                tp *= dd_factor;
                m_logger.Debug("SmartClose",
                    StringFormat("TP reduzido por DD: fator=%.2f (DD=%.1f%%)", dd_factor, state.max_drawdown_pct));
            }
        }

        // TP aceitável (piso — pode ser negativo para aceitar perda)
        double acceptable = (m_tp_mode == TP_MONETARY)
                            ? m_tp_monetary_acceptable
                            : m_tp_acceptable;
        if(acceptable != 0.0 && tp < acceptable) {
            // Não reduz abaixo do aceitável (a menos que aceitável seja negativo)
        }

        return tp;
    }

    //+--------------------------------------------------------------+
    //| Verifica Smart Close clássico (pior nível com lucro)         |
    //+--------------------------------------------------------------+
    bool CheckSmartClose(SGridState &state) {
        // Mínimo 2 níveis para Smart Close funcionar
        if(state.total_levels < 2) return false;
        if(state.worst_index < 0 || state.worst_profit >= 0.0) return false;
        if(state.positive_profit_sum <= 0.0) return false;

        // Margem de segurança
        double margin = CalculateMarginCost(state.worst_volume);
        double required = MathAbs(state.worst_profit) + margin;

        if(state.positive_profit_sum >= required) {
            m_logger.Info("SmartClose",
                StringFormat("🎯 Smart Close! Lucros=R$%.2f | Necessário=R$%.2f | Pior=R$%.2f",
                             state.positive_profit_sum, required, state.worst_profit));
            return ExecuteSmartClose(state);
        }
        return false;
    }

    //+--------------------------------------------------------------+
    //| Verifica TakeProfit Total (fecha tudo se P&L > TP)           |
    //+--------------------------------------------------------------+
    bool CheckTPTotal(SGridState &state) {
        double effective_tp = CalculateEffectiveTP(state);
        if(effective_tp <= 0.0 && m_tp_acceptable >= 0.0) return false;

        if(state.total_profit >= effective_tp) {
            m_logger.Info("SmartClose",
                StringFormat("🎯 TP Total! P&L=R$%.2f | TP=R$%.2f", state.total_profit, effective_tp));
            return ExecuteCloseAll(state);
        }
        return false;
    }

    //+--------------------------------------------------------------+
    //| Verifica BreakEven (fecha quando preço atinge média)         |
    //+--------------------------------------------------------------+
    bool CheckBreakEven(SGridState &state) {
        if(m_be_mode == BE_DISABLED) return false;
        if(state.total_levels < 2) return false;

        double acceptable = m_be_acceptable;
        // Converte aceitável para valor monetário
        double tick_size  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
        double tick_value = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
        double acceptable_money = (acceptable * SymbolInfoDouble(m_symbol, SYMBOL_POINT)
                                   / tick_size) * tick_value * state.total_volume;

        if(state.total_profit >= acceptable_money) {
            m_logger.Info("SmartClose",
                StringFormat("🎯 BreakEven! P&L=R$%.2f | Aceitável=R$%.2f",
                             state.total_profit, acceptable_money));
            return ExecuteCloseAll(state);
        }
        return false;
    }

    //+--------------------------------------------------------------+
    //| Verifica fechamento por quantidade de ordens/lotes            |
    //+--------------------------------------------------------------+
    bool CheckQuantityClose(SGridState &state) {
        // Fechar tudo por soma de lotes
        if(m_lot_sum_total > 0.0 && state.total_volume >= m_lot_sum_total) {
            if(state.total_profit >= m_min_profit) {
                m_logger.Info("SmartClose",
                    StringFormat("🎯 Lote Total! Vol=%.0f (máx=%.0f)", state.total_volume, m_lot_sum_total));
                return ExecuteCloseAll(state);
            }
        }

        // Fechar tudo por quantidade de ordens
        if(m_order_count_total > 0 && state.total_levels >= m_order_count_total) {
            if(state.total_profit >= m_min_profit) {
                m_logger.Info("SmartClose",
                    StringFormat("🎯 Qtde Total! Ordens=%d (máx=%d)", state.total_levels, m_order_count_total));
                return ExecuteCloseAll(state);
            }
        }

        return false;
    }

    //+--------------------------------------------------------------+
    //| Verifica aceitar prejuízo (quando DD baixo e muitos lotes)   |
    //+--------------------------------------------------------------+
    bool CheckAcceptLoss(SGridState &state) {
        if(m_accept_loss_value >= 0.0) return false;  // Precisa ser negativo
        if(state.total_levels < 2) return false;

        // Verifica se DD está abaixo do limiar
        if(m_dd_accept_loss > 0.0 && state.max_drawdown_pct > m_dd_accept_loss)
            return false;  // DD ainda alto demais

        // Verifica se perda está dentro do aceitável
        if(state.total_profit >= m_accept_loss_value) {
            m_logger.Info("SmartClose",
                StringFormat("🎯 Aceitar Perda! P&L=R$%.2f | Aceitável=R$%.2f | DD=%.1f%%",
                             state.total_profit, m_accept_loss_value, state.max_drawdown_pct));
            return ExecuteCloseAll(state);
        }
        return false;
    }

    //+--------------------------------------------------------------+
    //| Executa Smart Close parcial (fecha pior + lucrativos)         |
    //+--------------------------------------------------------------+
    bool ExecuteSmartClose(SGridState &state) {
        if(!PositionSelect(m_symbol)) {
            m_logger.Error("SmartClose", "Posição real não encontrada!");
            return false;
        }
        ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        double real_volume = PositionGetDouble(POSITION_VOLUME);

        // Coleta níveis lucrativos
        int    profitable_indices[];
        double profitable_profits[];
        int profit_count = m_pos_manager.GetProfitableLevelIndices(
                               profitable_indices, profitable_profits);

        // Calcula volume e índices a fechar
        double volume_to_close = state.worst_volume;
        double accumulated_profit = state.worst_profit;
        int    indices_to_remove[];
        int    remove_count = 1;
        ArrayResize(indices_to_remove, 1);
        indices_to_remove[0] = state.worst_index;

        // Adiciona lucrativos até cobrir o débito + margem
        for(int i = 0; i < profit_count; i++) {
            if(accumulated_profit >= 0.0) break;

            double level_vol = m_pos_manager.GetLevelVolume(profitable_indices[i]);
            volume_to_close += level_vol;
            accumulated_profit += profitable_profits[i];

            remove_count++;
            ArrayResize(indices_to_remove, remove_count);
            indices_to_remove[remove_count - 1] = profitable_indices[i];
        }

        return ExecutePartialClose(pos_type, real_volume, volume_to_close,
                                    indices_to_remove, remove_count, accumulated_profit);
    }

    //+--------------------------------------------------------------+
    //| Executa fechamento total (toda a posição)                     |
    //+--------------------------------------------------------------+
    bool ExecuteCloseAll(SGridState &state) {
        if(!PositionSelect(m_symbol)) {
            m_logger.Error("SmartClose", "Posição real não encontrada!");
            return false;
        }

        ulong ticket = PositionGetInteger(POSITION_TICKET);
        m_trade.SetTypeFilling(DetectFillingMode());
        bool result = m_trade.PositionClose(ticket);

        if(result) {
            m_logger.Info("SmartClose",
                StringFormat("[OK] Fechamento TOTAL! Vol=%.0f | P&L=R$%.2f | %d niveis",
                             state.total_volume, state.total_profit, state.total_levels));
            m_pos_manager.ClearAllLevels();
            m_last_close_time = TimeCurrent();
        } else {
            m_logger.Error("SmartClose",
                StringFormat("[ERRO] Falha fechamento total: Erro=%d | %s",
                             GetLastError(), m_trade.ResultComment()));
        }
        return result;
    }

    //+--------------------------------------------------------------+
    //| Executa fechamento parcial via contra-ordem em NETTING       |
    //+--------------------------------------------------------------+
    bool ExecutePartialClose(ENUM_POSITION_TYPE pos_type, double real_volume,
                              double volume_to_close, int &indices_to_remove[],
                              int remove_count, double accumulated_profit) {
        // Segurança: não fechar mais que a posição real
        if(volume_to_close > real_volume)
            volume_to_close = real_volume;

        // Normaliza volume
        double step = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
        volume_to_close = MathFloor(volume_to_close / step) * step;
        if(volume_to_close < SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN)) {
            m_logger.Warning("SmartClose", "Volume a fechar muito pequeno");
            return false;
        }

        // Envia contra-ordem
        bool result = false;
        string comment = StringFormat("%s_SC", OMNIB3_COMMENT_PREFIX);

        if(pos_type == POSITION_TYPE_BUY) {
            double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
            result = m_trade.Sell(volume_to_close, m_symbol, bid, 0, 0, comment);
        } else {
            double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
            result = m_trade.Buy(volume_to_close, m_symbol, ask, 0, 0, comment);
        }

        if(result) {
            m_logger.Info("SmartClose",
                StringFormat("[OK] Fechados %.0f contratos | %d niveis | P&L~R$%.2f",
                             volume_to_close, remove_count, accumulated_profit));

            m_pos_manager.RemoveLevelsByIndices(indices_to_remove, remove_count);

            // Se fechou tudo, limpa
            if(volume_to_close >= real_volume)
                m_pos_manager.ClearAllLevels();

            m_last_close_time = TimeCurrent();
        } else {
            m_logger.Error("SmartClose",
                StringFormat("[ERRO] Falha: Erro=%d | %s", GetLastError(), m_trade.ResultComment()));
        }
        return result;
    }

public:
    //+--------------------------------------------------------------+
    //| Construtor                                                    |
    //+--------------------------------------------------------------+
    CSmartClose(string symbol, int magic_number,
                ENUM_CLOSE_MODE close_mode, double margin_ticks,
                CPositionManager *pos_manager, CLogger *logger) {

        m_symbol         = symbol;
        m_magic_number   = magic_number;
        m_close_mode     = close_mode;
        m_close_target   = CLOSE_WORST;
        m_margin_ticks   = margin_ticks;
        m_pos_manager    = pos_manager;
        m_logger         = logger;
        m_last_close_time = 0;

        // Defaults TakeProfit
        m_tp_mode        = TP_FIXED_POINTS;
        m_tp_points      = 100;
        m_tp_monetary    = 0.0;
        m_tp_acceptable  = 0.0;
        m_tp_monetary_acceptable = 0.0;
        m_tp_multiplier  = 1.0;
        m_tp_reduce_type = TP_REDUCE_NONE;
        m_tp_reduce_dd   = 100.0;
        m_tp_reduce_search = 0.0;
        m_tp_reduce_time = 0;
        m_reduce_last    = true;

        // Defaults BreakEven
        m_be_mode        = BE_DISABLED;
        m_be_points      = 0.0;
        m_be_acceptable  = 0.0;
        m_be_type        = BE_STATIC;
        m_be_trail_factor = 1.0;

        // Defaults Quantidade
        m_lot_sum_total  = 0.0;
        m_lot_sum_half   = 0.0;
        m_lot_avg_total  = 0.0;
        m_order_count_total = 0;
        m_order_count_half  = 0;
        m_lot_on_close   = 0.0;
        m_min_profit     = 0.0;

        // Defaults Aceitar Perda
        m_dd_accept_loss = 0.0;
        m_accept_loss_value = 0.0;

        // Defaults Trailing virtual da Grade
        m_use_trailing      = false;
        m_trail_trigger     = 0.0;
        m_trail_stop_dist   = 0.0;
        m_trail_tp_dist     = 0.0;
        m_trail_step        = 0.0;
        m_trail_active      = false;
        m_max_price_seen    = 0.0;
        m_virtual_sl        = 0.0;
        m_virtual_tp        = 0.0;

        m_trade.SetExpertMagicNumber(m_magic_number);
        m_trade.SetDeviationInPoints(10);
        m_trade.SetTypeFilling(DetectFillingMode());

        m_logger.Info("SmartClose",
            StringFormat("Init: %s | Modo=%s | Margem=%.1f ticks",
                         m_symbol, EnumToString(m_close_mode), m_margin_ticks));
    }

    //+--------------------------------------------------------------+
    //| Configura TakeProfit                                          |
    //+--------------------------------------------------------------+
    void SetTakeProfit(ENUM_TP_MODE mode, double points, double monetary,
                       double acceptable, double monetary_acceptable,
                       double multiplier) {
        m_tp_mode = mode;
        m_tp_points = points;
        m_tp_monetary = monetary;
        m_tp_acceptable = acceptable;
        m_tp_monetary_acceptable = monetary_acceptable;
        m_tp_multiplier = multiplier;
    }

    //+--------------------------------------------------------------+
    //| Configura redução do TP                                       |
    //+--------------------------------------------------------------+
    void SetTPReduction(ENUM_TP_REDUCE_TYPE type, double dd_pct,
                        double search, int time_minutes, bool reduce_last) {
        m_tp_reduce_type = type;
        m_tp_reduce_dd = dd_pct;
        m_tp_reduce_search = search;
        m_tp_reduce_time = time_minutes;
        m_reduce_last = reduce_last;
    }

    //+--------------------------------------------------------------+
    //| Configura BreakEven                                           |
    //+--------------------------------------------------------------+
    void SetBreakEven(ENUM_BE_MODE mode, double points, double acceptable,
                      ENUM_BE_TYPE type, double trail_factor) {
        m_be_mode = mode;
        m_be_points = points;
        m_be_acceptable = acceptable;
        m_be_type = type;
        m_be_trail_factor = trail_factor;
    }

    //+--------------------------------------------------------------+
    //| Configura fechamento por quantidade                           |
    //+--------------------------------------------------------------+
    void SetQuantityLimits(double lot_sum_total, double lot_sum_half,
                           double lot_avg_total, int order_count_total,
                           int order_count_half, double min_profit) {
        m_lot_sum_total = lot_sum_total;
        m_lot_sum_half = lot_sum_half;
        m_lot_avg_total = lot_avg_total;
        m_order_count_total = order_count_total;
        m_order_count_half = order_count_half;
        m_min_profit = min_profit;
    }

    //+--------------------------------------------------------------+
    //| Configura aceitar prejuízo                                    |
    //+--------------------------------------------------------------+
    void SetAcceptLoss(double dd_threshold, double loss_value) {
        m_dd_accept_loss = dd_threshold;
        m_accept_loss_value = loss_value;
    }

    //+--------------------------------------------------------------+
    //| Configura o Trailing Virtual da Grade                        |
    //+--------------------------------------------------------------+
    void SetTrailing(bool use_trailing, double trigger, double stop_dist, double tp_dist, double step) {
        m_use_trailing    = use_trailing;
        m_trail_trigger   = trigger;
        m_trail_stop_dist = stop_dist;
        m_trail_tp_dist   = tp_dist;
        m_trail_step      = step;
        m_trail_active    = false;
        m_max_price_seen  = 0.0;
        m_virtual_sl      = 0.0;
        m_virtual_tp      = 0.0;
        
        m_logger.Info("SmartClose",
            StringFormat("Trailing Grade: Habilitado=%s | Gatilho=%.0f pts | StopDist=%.0f pts | TPDist=%.0f pts | Passo=%.0f pts",
                         use_trailing ? "Sim" : "Nao", trigger, stop_dist, tp_dist, step));
    }

    //+--------------------------------------------------------------+
    //| Lógica do Trailing Virtual da Grade (Gain/Stop Gain Móvel)   |
    //| Retorna true se a grade foi liquidada                         |
    //+--------------------------------------------------------------+
    bool CheckTrailingVirtual(SGridState &state) {
        if(!m_use_trailing) return false;

        // Se não houver níveis ativos na grade, reseta o estado do trailing
        if(state.total_levels == 0) {
            if(m_trail_active) {
                m_trail_active = false;
                m_max_price_seen = 0.0;
                m_virtual_sl = 0.0;
                m_virtual_tp = 0.0;
            }
            return false;
        }

        // Tenta selecionar a posição consolidada
        if(!PositionSelect(m_symbol)) {
            if(m_trail_active) {
                m_trail_active = false;
                m_max_price_seen = 0.0;
                m_virtual_sl = 0.0;
                m_virtual_tp = 0.0;
            }
            return false;
        }

        long pos_type = PositionGetInteger(POSITION_TYPE);
        double tick_size = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        double current_bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        double current_ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);

        // COMPRA
        if(pos_type == POSITION_TYPE_BUY) {
            double profit_pts = (current_bid - state.avg_price) / point;

            // Se ainda não ativou o trailing, verifica se o lucro em pontos atingiu o gatilho (trigger)
            if(!m_trail_active) {
                if(profit_pts >= m_trail_trigger) {
                    m_trail_active = true;
                    m_max_price_seen = current_bid;

                    // Define alvos virtuais iniciais (em preço absoluto)
                    m_virtual_sl = m_max_price_seen - (m_trail_stop_dist * point);
                    m_virtual_tp = m_max_price_seen + (m_trail_tp_dist * point);

                    if(tick_size > 0.0) {
                        m_virtual_sl = NormalizeDouble(MathRound(m_virtual_sl / tick_size) * tick_size, _Digits);
                        m_virtual_tp = NormalizeDouble(MathRound(m_virtual_tp / tick_size) * tick_size, _Digits);
                    }

                    m_logger.Info("SmartClose",
                        StringFormat("🔥 Trailing Virtual Grade Ativado na COMPRA! Lucro: %.0f pts. Preço: %.2f | SL: %.2f | TP: %.2f", 
                                     profit_pts, current_bid, m_virtual_sl, m_virtual_tp));
                }
            }

            // Se o trailing virtual estiver ativo, arrasta o SL e TP virtuais
            if(m_trail_active) {
                if(current_bid > m_max_price_seen) {
                    m_max_price_seen = current_bid;
                }

                // Níveis ideais de SL e TP
                double target_sl = m_max_price_seen - (m_trail_stop_dist * point);
                double target_tp = m_max_price_seen + (m_trail_tp_dist * point);

                if(tick_size > 0.0) {
                    target_sl = NormalizeDouble(MathRound(target_sl / tick_size) * tick_size, _Digits);
                    target_tp = NormalizeDouble(MathRound(target_tp / tick_size) * tick_size, _Digits);
                }

                // O Stop Gain virtual da compra só pode subir.
                // Respeitamos o passo para evitar atualizações microscópicas desnecessárias nos logs.
                double step_value = m_trail_step * point;
                if(target_sl >= m_virtual_sl + step_value) {
                    double old_sl = m_virtual_sl;
                    double old_tp = m_virtual_tp;
                    m_virtual_sl = target_sl;
                    m_virtual_tp = target_tp;
                    
                    m_logger.Info("SmartClose",
                        StringFormat("⚡ Trailing Virtual COMPRA atualizado. SL: %.2f (antigo: %.2f) | TP: %.2f (antigo: %.2f) | Bid Max: %.2f", 
                                     m_virtual_sl, old_sl, m_virtual_tp, old_tp, m_max_price_seen));
                }

                // Verifica condições de fechamento a mercado (saída)
                if(current_bid <= m_virtual_sl) {
                    m_logger.Info("SmartClose",
                        StringFormat("🚨 Trailing Virtual COMPRA atingido pelo Stop Gain! Preço: %.2f <= SL Virtual: %.2f. Fechando a grade inteira.", 
                                     current_bid, m_virtual_sl));
                    bool closed = ExecuteCloseAll(state);
                    if(closed) {
                        m_trail_active = false;
                        m_max_price_seen = 0.0;
                        m_virtual_sl = 0.0;
                        m_virtual_tp = 0.0;
                    }
                    return closed;
                }
                
                if(current_bid >= m_virtual_tp) {
                    m_logger.Info("SmartClose",
                        StringFormat("🎯 Trailing Virtual COMPRA atingido pelo Gain Móvel! Preço: %.2f >= TP Virtual: %.2f. Fechando a grade inteira.", 
                                     current_bid, m_virtual_tp));
                    bool closed = ExecuteCloseAll(state);
                    if(closed) {
                        m_trail_active = false;
                        m_max_price_seen = 0.0;
                        m_virtual_sl = 0.0;
                        m_virtual_tp = 0.0;
                    }
                    return closed;
                }
            }
        }
        // VENDA
        else if(pos_type == POSITION_TYPE_SELL) {
            double profit_pts = (state.avg_price - current_ask) / point;

            // Se ainda não ativou o trailing, verifica se o lucro em pontos atingiu o gatilho (trigger)
            if(!m_trail_active) {
                if(profit_pts >= m_trail_trigger) {
                    m_trail_active = true;
                    m_max_price_seen = current_ask;

                    // Define alvos virtuais iniciais (em preço absoluto)
                    m_virtual_sl = m_max_price_seen + (m_trail_stop_dist * point);
                    m_virtual_tp = m_max_price_seen - (m_trail_tp_dist * point);

                    if(tick_size > 0.0) {
                        m_virtual_sl = NormalizeDouble(MathRound(m_virtual_sl / tick_size) * tick_size, _Digits);
                        m_virtual_tp = NormalizeDouble(MathRound(m_virtual_tp / tick_size) * tick_size, _Digits);
                    }

                    m_logger.Info("SmartClose",
                        StringFormat("🔥 Trailing Virtual Grade Ativado na VENDA! Lucro: %.0f pts. Preço: %.2f | SL: %.2f | TP: %.2f", 
                                     profit_pts, current_ask, m_virtual_sl, m_virtual_tp));
                }
            }

            // Se o trailing virtual estiver ativo, arrasta o SL e TP virtuais
            if(m_trail_active) {
                if(current_ask < m_max_price_seen) {
                    m_max_price_seen = current_ask;
                }

                // Níveis ideais de SL e TP
                double target_sl = m_max_price_seen + (m_trail_stop_dist * point);
                double target_tp = m_max_price_seen - (m_trail_tp_dist * point);

                if(tick_size > 0.0) {
                    target_sl = NormalizeDouble(MathRound(target_sl / tick_size) * tick_size, _Digits);
                    target_tp = NormalizeDouble(MathRound(target_tp / tick_size) * tick_size, _Digits);
                }

                // O Stop Gain virtual da venda só pode descer.
                // Respeitamos o passo para evitar atualizações microscópicas desnecessárias nos logs.
                double step_value = m_trail_step * point;
                if(target_sl <= m_virtual_sl - step_value) {
                    double old_sl = m_virtual_sl;
                    double old_tp = m_virtual_tp;
                    m_virtual_sl = target_sl;
                    m_virtual_tp = target_tp;
                    
                    m_logger.Info("SmartClose",
                        StringFormat("⚡ Trailing Virtual VENDA atualizado. SL: %.2f (antigo: %.2f) | TP: %.2f (antigo: %.2f) | Ask Min: %.2f", 
                                     m_virtual_sl, old_sl, m_virtual_tp, old_tp, m_max_price_seen));
                }

                // Verifica condições de fechamento a mercado (saída)
                if(current_ask >= m_virtual_sl) {
                    m_logger.Info("SmartClose",
                        StringFormat("🚨 Trailing Virtual VENDA atingido pelo Stop Gain! Preço: %.2f >= SL Virtual: %.2f. Fechando a grade inteira.", 
                                     current_ask, m_virtual_sl));
                    bool closed = ExecuteCloseAll(state);
                    if(closed) {
                        m_trail_active = false;
                        m_max_price_seen = 0.0;
                        m_virtual_sl = 0.0;
                        m_virtual_tp = 0.0;
                    }
                    return closed;
                }
                
                if(current_ask <= m_virtual_tp) {
                    m_logger.Info("SmartClose",
                        StringFormat("🎯 Trailing Virtual VENDA atingido pelo Gain Móvel! Preço: %.2f <= TP Virtual: %.2f. Fechando a grade inteira.", 
                                     current_ask, m_virtual_tp));
                    bool closed = ExecuteCloseAll(state);
                    if(closed) {
                        m_trail_active = false;
                        m_max_price_seen = 0.0;
                        m_virtual_sl = 0.0;
                        m_virtual_tp = 0.0;
                    }
                    return closed;
                }
            }
        }

        return false;
    }

    //+--------------------------------------------------------------+
    //| Altera modo de fechamento (usado pelo RecoveryMode)          |
    //+--------------------------------------------------------------+
    void SetCloseMode(ENUM_CLOSE_MODE mode) {
        m_close_mode = mode;
        m_logger.Info("SmartClose",
            StringFormat("Modo alterado para: %s", EnumToString(mode)));
    }

    //+--------------------------------------------------------------+
    //| Método principal: verifica e executa fechamento               |
    //| Retorna: true se fechamento foi executado                    |
    //+--------------------------------------------------------------+
    bool CheckAndExecute(ENUM_CLOSE_MODE override_mode = (ENUM_CLOSE_MODE)-1) {
        if(!IsCooldownExpired()) return false;

        SGridState state = m_pos_manager.GetGridState();
        if(state.total_levels < 1) return false;

        // Se o trailing virtual estiver ativado, processa as verificações de Gain/Stop Gain móveis primeiro
        if(m_use_trailing) {
            if(CheckTrailingVirtual(state)) {
                return true;
            }
        }

        ENUM_CLOSE_MODE mode = (override_mode != (ENUM_CLOSE_MODE)-1)
                               ? override_mode : m_close_mode;

        // Salvaguarda TP de Segurança: Se o lucro total líquido da grade atingir o Take Profit Total
        // configurado (effective_tp), fechamos toda a grade imediatamente, independente do modo de fechamento!
        // Isso evita que posições altamente lucrativas fiquem presas em modos clássicos como CMODE_SMART_WORST/OLDEST.
        if(state.total_levels >= 1 && (mode == CMODE_SMART_WORST || mode == CMODE_SMART_OLDEST)) {
            double effective_tp = CalculateEffectiveTP(state);
            if(effective_tp > 0.0 || m_tp_acceptable < 0.0) {
                if(state.total_profit >= effective_tp) {
                    m_logger.Info("SmartClose",
                        StringFormat("🛡️ Salvaguarda TP Total atingida! P&L=R$%.2f | TP=R$%.2f. Fechando toda a grade por segurança.", state.total_profit, effective_tp));
                    return ExecuteCloseAll(state);
                }
            }
        }

        // Se houver apenas 1 nível ativo, os modos Smart Close clássicos (worst/oldest)
        // não conseguem realizar fechamentos parciais/combinados por exigirem >= 2 níveis.
        // Logo, para evitar que a ordem inicial corra indefinidamente no lucro ou prejuízo,
        // forçamos a validação de saída baseada no Take Profit Total configurado.
        if(state.total_levels == 1 && (mode == CMODE_SMART_WORST || mode == CMODE_SMART_OLDEST)) {
            return CheckTPTotal(state);
        }

        // Executa verificação baseada no modo ativo
        switch(mode) {
            case CMODE_SMART_WORST:
            case CMODE_SMART_OLDEST:
                return CheckSmartClose(state);

            case CMODE_TP_TOTAL:
                return CheckTPTotal(state);

            case CMODE_TP_MONETARY:
                // Verifica TP monetário direto
                if(m_tp_monetary > 0.0 && state.total_profit >= m_tp_monetary * m_tp_multiplier) {
                    m_logger.Info("SmartClose",
                        StringFormat("[TP] TP Monetario! P&L=R$%.2f | TP=R$%.2f",
                                     state.total_profit, m_tp_monetary * m_tp_multiplier));
                    return ExecuteCloseAll(state);
                }
                return false;

            case CMODE_BREAKEVEN:
                return CheckBreakEven(state);

            case CMODE_LOT_SUM_TOTAL:
            case CMODE_LOT_SUM_HALF:
            case CMODE_LOT_AVG_TOTAL:
            case CMODE_ORDER_COUNT:
            case CMODE_ORDER_COUNT_HALF:
                return CheckQuantityClose(state);

            case CMODE_ACCEPT_LOSS:
                return CheckAcceptLoss(state);

            case CMODE_HALF_CLOSE:
                // Fecha metade dos lucrativos
                if(state.positive_count >= 2 && state.total_profit > 0) {
                    m_logger.Info("SmartClose", "[TP] Fechando metade dos lucrativos");
                    return CheckSmartClose(state);
                }
                return false;

            default:
                return CheckSmartClose(state);
        }
    }

    //+--------------------------------------------------------------+
    //| Verifica TODOS os modos de fechamento (cascata)              |
    //| Útil quando múltiplas condições podem fechar                 |
    //+--------------------------------------------------------------+
    bool CheckAllModes() {
        if(!IsCooldownExpired()) return false;

        SGridState state = m_pos_manager.GetGridState();
        if(state.total_levels < 1) return false;

        // 1. TP Total (prioridade máxima)
        if(m_tp_points > 0 || m_tp_monetary > 0) {
            if(CheckTPTotal(state)) return true;
        }

        // 2. TP Monetário
        if(m_tp_monetary > 0.0) {
            if(state.total_profit >= m_tp_monetary * m_tp_multiplier) {
                m_logger.Info("SmartClose",
                    StringFormat("[TP] TP Monetario! R$%.2f", state.total_profit));
                return ExecuteCloseAll(state);
            }
        }

        // 3. Quantidade (lotes/ordens)
        if(CheckQuantityClose(state)) return true;

        // 4. Smart Close (padrão)
        if(CheckSmartClose(state)) return true;

        // 5. BreakEven
        if(CheckBreakEven(state)) return true;

        // 6. Aceitar perda (última opção)
        if(CheckAcceptLoss(state)) return true;

        return false;
    }

    //--- Getters para trailing stop virtual da grade (OmniB3 v2.45)
    bool   IsTrailingActive() const { return m_trail_active; }
    double GetStopLossPrice() const { return m_virtual_sl; }
    double GetTakeProfitPrice() const { return m_virtual_tp; }
};

//+------------------------------------------------------------------+
