//+------------------------------------------------------------------+
//|                                                  SmartClose.mqh  |
//|              Omni-B3 EA v1.1 — Smart Close para B3/NETTING       |
//|   Usa lucro virtual de níveis para fechar posição parcialmente   |
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
//| Smart Close para contas NETTING                                  |
//|                                                                   |
//| Em NETTING, não podemos fechar posições individuais por ticket.  |
//| Em vez disso:                                                     |
//| 1. Calculamos P&L virtual de cada nível da grade                 |
//| 2. Quando Σ lucros >= |pior prejuízo| + margem:                 |
//|    a) Calculamos volume total a reduzir (pior + lucrativos)      |
//|    b) Enviamos UMA contra-ordem para reduzir a posição           |
//|    c) Removemos os níveis virtuais fechados                      |
//+------------------------------------------------------------------+
class CSmartClose {
private:
    string             m_symbol;
    int                m_magic_number;
    ENUM_CLOSE_TARGET  m_close_target;
    double             m_margin_ticks;    // Margem em ticks
    CTrade             m_trade;
    CPositionManager  *m_pos_manager;
    CLogger           *m_logger;
    datetime           m_last_close_time;

    //+--------------------------------------------------------------+
    //| Calcula custo da margem de segurança em BRL                  |
    //| margem_ticks × tick_value × volume                           |
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

public:
    //+--------------------------------------------------------------+
    //| Construtor                                                    |
    //+--------------------------------------------------------------+
    CSmartClose(string symbol, int magic_number,
                ENUM_CLOSE_TARGET close_target, double margin_ticks,
                CPositionManager *pos_manager, CLogger *logger) {

        m_symbol         = symbol;
        m_magic_number   = magic_number;
        m_close_target   = close_target;
        m_margin_ticks   = margin_ticks;
        m_pos_manager    = pos_manager;
        m_logger         = logger;
        m_last_close_time = 0;

        m_trade.SetExpertMagicNumber(m_magic_number);
        m_trade.SetDeviationInPoints(10);
        m_trade.SetTypeFilling(DetectFillingMode());

        m_logger.Info("SmartClose",
            StringFormat("Init: %s | Alvo=%s | Margem=%.1f ticks",
                         m_symbol, EnumToString(m_close_target), m_margin_ticks));
    }

    //+--------------------------------------------------------------+
    //| Método principal: verifica e executa Smart Close              |
    //| Retorna: true se fechamento foi executado                    |
    //+--------------------------------------------------------------+
    bool CheckAndExecute() {
        if(!IsCooldownExpired()) return false;

        // Obtém estado da grade virtual
        SGridState state = m_pos_manager.GetGridState();

        // Mínimo 2 níveis para Smart Close funcionar
        if(state.total_levels < 2) return false;

        // Precisa ter nível perdedor E níveis lucrativos
        if(state.worst_index < 0 || state.worst_profit >= 0.0) return false;
        if(state.positive_profit_sum <= 0.0) return false;

        // Calcula margem de segurança em BRL
        double margin = CalculateMarginCost(state.worst_volume);

        // ═══ GATILHO DO SMART CLOSE ═══
        double required = MathAbs(state.worst_profit) + margin;

        if(state.positive_profit_sum >= required) {
            m_logger.Info("SmartClose",
                StringFormat("🎯 GATILHO! Lucros=R$%.2f | Necessário=R$%.2f | Pior=R$%.2f",
                             state.positive_profit_sum, required, state.worst_profit));
            return ExecuteSmartClose(state);
        }

        return false;
    }

private:
    //+--------------------------------------------------------------+
    //| Executa o abate parcial em NETTING                           |
    //|                                                               |
    //| 1. Identifica volume a fechar (pior + lucrativos suficientes)|
    //| 2. Envia UMA contra-ordem para reduzir posição               |
    //| 3. Remove níveis virtuais correspondentes                    |
    //+--------------------------------------------------------------+
    bool ExecuteSmartClose(SGridState &state) {
        // Determina direção da posição atual
        // Se estamos comprando, fechamos vendendo (e vice-versa)
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
        double volume_to_close = state.worst_volume; // Começa com o pior
        double accumulated_profit = state.worst_profit; // Negativo
        int    indices_to_remove[];
        int    remove_count = 1;
        ArrayResize(indices_to_remove, 1);
        indices_to_remove[0] = state.worst_index;

        // Adiciona níveis lucrativos até cobrir o débito
        for(int i = 0; i < profit_count; i++) {
            if(accumulated_profit >= 0.0) break; // Já cobriu

            double level_vol = m_pos_manager.GetLevelVolume(profitable_indices[i]);
            volume_to_close += level_vol;
            accumulated_profit += profitable_profits[i];

            remove_count++;
            ArrayResize(indices_to_remove, remove_count);
            indices_to_remove[remove_count - 1] = profitable_indices[i];
        }

        // Segurança: não fechar mais que a posição real
        if(volume_to_close > real_volume) {
            volume_to_close = real_volume;
        }

        // Normaliza volume
        double step = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
        volume_to_close = MathFloor(volume_to_close / step) * step;
        if(volume_to_close < SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN)) {
            m_logger.Warning("SmartClose", "Volume a fechar muito pequeno");
            return false;
        }

        // Envia contra-ordem para reduzir posição
        bool result = false;
        string comment = StringFormat("%s_SC", OMNIB3_COMMENT_PREFIX);

        if(pos_type == POSITION_TYPE_BUY) {
            // Posição é compra → vende para reduzir
            double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
            result = m_trade.Sell(volume_to_close, m_symbol, bid, 0, 0, comment);
        } else {
            // Posição é venda → compra para reduzir
            double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
            result = m_trade.Buy(volume_to_close, m_symbol, ask, 0, 0, comment);
        }

        if(result) {
            m_logger.Info("SmartClose",
                StringFormat("✅ Fechados %.0f contratos | %d níveis | P&L estimado=R$%.2f",
                             volume_to_close, remove_count, accumulated_profit));

            // Remove níveis virtuais fechados
            m_pos_manager.RemoveLevelsByIndices(indices_to_remove, remove_count);

            // Se fechou tudo, limpa
            if(volume_to_close >= real_volume) {
                m_pos_manager.ClearAllLevels();
                m_logger.Info("SmartClose", "Posição totalmente fechada — grade limpa");
            }

            m_last_close_time = TimeCurrent();
        } else {
            m_logger.Error("SmartClose",
                StringFormat("❌ Falha ao fechar: Erro=%d | %s",
                             GetLastError(), m_trade.ResultComment()));
        }

        return result;
    }
};

//+------------------------------------------------------------------+
