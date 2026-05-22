//+------------------------------------------------------------------+
//|                                                   SingleOrder.mqh |
//|                     Omni-B3 EA v2.35 — Modo de Ordem Única        |
//|  Gerenciamento de Trades Individuais com Martingale Sequencial   |
//|  TP, SL, BreakEven independentes, Trailing Stop e Trailing TP    |
//+------------------------------------------------------------------+
#property copyright "Projeto Omni-B3"
#property link      "https://github.com/helveciopereira/Stocks"
#property version     "2.35"
#property strict

#include <OmniB3/Defines.mqh>
#include <OmniB3/Logger.mqh>
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| CLASSE CSingleOrder                                              |
//| Gerencia ordens simples independentes sem formação de grade      |
//+------------------------------------------------------------------+
class CSingleOrder {
private:
    CTrade              m_trade;            // Classe padrão de trade do MT5
    ulong               m_magic;            // Número Mágico
    ENUM_SINGLE_ORDER_MODE m_mode;          // Modo ativo (Habilitado/Desabilitado)
    
    // Configurações do Trade
    double              m_sl_points;        // StopLoss em pontos (0 = sem)
    double              m_tp_points;        // TakeProfit em pontos (0 = sem)
    double              m_be_activation;    // Ativação do BreakEven em pontos
    double              m_be_margin;        // Margem de lucro do BreakEven
    
    // Sistema Martingale / Anti-Martingale
    ENUM_MARTINGALE_MODE m_mart_mode;       // Modo de Martingale
    double              m_mart_multiplier;  // Multiplicador de lote
    int                 m_mart_max_steps;   // Limite de multiplicações consecutivas
    int                 m_consecutive_losses;// Contador de perdas consecutivas
    int                 m_consecutive_wins;  // Contador de ganhos consecutivos
    double              m_current_multiplier;// Multiplicador atual aplicado ao lote inicial

    // Lógicas de Espera (Cooldown)
    int                 m_wait_after_loss;  // Segundos de espera após uma perda
    int                 m_wait_after_win;   // Segundos de espera após um ganho
    datetime            m_last_close_time;  // Hora do fechamento do último trade
    double              m_last_trade_profit;// Lucro do último trade fechado

    // Auxiliares internos
    bool                m_be_applied;       // Sinalizador de BreakEven aplicado
    bool                m_close_on_opposite;// Fechar posição se houver sinal contrário?
    CLogger            *m_logger;           // Ponteiro para o Logger centralizado

    // Sistema de Trailing (Gain / Stop Gain Móveis)
    bool                m_use_trailing;     // Habilitar trailing móvel
    double              m_trail_trigger;    // Gatilho de ativação do trailing (pontos)
    double              m_trail_stop_dist;  // Distância do Stop Gain (pontos)
    double              m_trail_tp_dist;    // Distância do Gain Móvel (pontos)
    double              m_trail_step;       // Passo de atualização (pontos)
    bool                m_trail_active;     // Indica se o trailing está ativo no trade atual
    double              m_max_bid_seen;     // Maior preço Bid visto no trade de COMPRA
    double              m_min_ask_seen;     // Menor preço Ask visto no trade de VENDA

    // Rastreia o histórico para saber o resultado do último trade do Magic Number
    void                UpdateHistoryStats();

public:
                        CSingleOrder();
                       ~CSingleOrder();

    // Inicialização
    void                Init(CLogger *logger,
                             ulong magic, 
                             ENUM_SINGLE_ORDER_MODE mode,
                             double sl_pts, double tp_pts,
                             double be_act, double be_marg,
                             ENUM_MARTINGALE_MODE mart_mode,
                             double mart_mult, int mart_max_steps,
                             int wait_loss, int wait_win,
                             bool close_opposite,
                             bool use_trailing, double trail_trigger,
                             double trail_stop_dist, double trail_tp_dist,
                             double trail_step);

    // Verifica se podemos abrir uma nova ordem (cooldowns de espera)
    bool                CanOpenNewOrder(datetime current_time);

    // Retorna o lote calculated de acordo com Martingale/Anti-Martingale
    double              CalculateLot(double initial_lot, double lot_min, double lot_max);

    // Executa a abertura da ordem a mercado
    bool                OpenOrder(string symbol, int direction, double volume, string comment="");

    // Gerencia o trailing do StopLoss para BreakEven
    void                ManageBreakEven(string symbol, double current_bid, double current_ask, double tick_size);

    // Gerencia o trailing móvel físico (TakeProfit e StopLoss)
    void                ManageTrailing(string symbol, double current_bid, double current_ask, double tick_size);

    // Avalia fechamento por sinal contrário
    bool                CheckOppositeSignalClose(string symbol, int opposite_signal);

    // Resetador do histórico de Martingale
    void                ResetMartingale();
    
    // Getters para estatísticas
    int                 GetConsecutiveLosses() const { return m_consecutive_losses; }
    int                 GetConsecutiveWins()   const { return m_consecutive_wins; }
    double              GetCurrentMultiplier() const { return m_current_multiplier; }
};

//+------------------------------------------------------------------+
//| Construtor                                                       |
//+------------------------------------------------------------------+
CSingleOrder::CSingleOrder() {
    m_magic              = 0;
    m_mode               = SINGLE_DISABLED;
    m_sl_points          = 0.0;
    m_tp_points          = 0.0;
    m_be_activation      = 0.0;
    m_be_margin          = 0.0;
    m_mart_mode          = MARTINGALE_NONE;
    m_mart_multiplier    = 2.0;
    m_mart_max_steps     = 3;
    m_consecutive_losses = 0;
    m_consecutive_wins   = 0;
    m_current_multiplier = 1.0;
    m_wait_after_loss    = 0;
    m_wait_after_win     = 0;
    m_last_close_time    = 0;
    m_last_trade_profit  = 0.0;
    m_be_applied         = false;
    m_close_on_opposite  = false;
    m_logger             = NULL;
    
    // Inicialização do Trailing móvel
    m_use_trailing       = false;
    m_trail_trigger      = 0.0;
    m_trail_stop_dist    = 0.0;
    m_trail_tp_dist      = 0.0;
    m_trail_step         = 0.0;
    m_trail_active       = false;
    m_max_bid_seen       = 0.0;
    m_min_ask_seen       = 0.0;
}

//+------------------------------------------------------------------+
//| Destrutor                                                        |
//+------------------------------------------------------------------+
CSingleOrder::~CSingleOrder() {
}

//+------------------------------------------------------------------+
//| Inicialização das Configurações                                  |
//+------------------------------------------------------------------+
void CSingleOrder::Init(CLogger *logger,
                         ulong magic, 
                         ENUM_SINGLE_ORDER_MODE mode,
                         double sl_pts, double tp_pts,
                         double be_act, double be_marg,
                         ENUM_MARTINGALE_MODE mart_mode,
                         double mart_mult, int mart_max_steps,
                         int wait_loss, int wait_win,
                         bool close_opposite,
                         bool use_trailing, double trail_trigger,
                         double trail_stop_dist, double trail_tp_dist,
                         double trail_step) {
    m_logger            = logger;
    m_magic             = magic;
    m_mode              = mode;
    m_sl_points         = sl_pts;
    m_tp_points         = tp_pts;
    m_be_activation     = be_act;
    m_be_margin         = be_marg;
    m_mart_mode         = mart_mode;
    m_mart_multiplier   = mart_mult;
    m_mart_max_steps    = mart_max_steps;
    m_wait_after_loss   = wait_loss;
    m_wait_after_win    = wait_win;
    m_close_on_opposite = close_opposite;
    
    // Configurações do Trailing
    m_use_trailing      = use_trailing;
    m_trail_trigger     = trail_trigger;
    m_trail_stop_dist   = trail_stop_dist;
    m_trail_tp_dist     = trail_tp_dist;
    m_trail_step        = trail_step;
    m_trail_active      = false;
    m_max_bid_seen      = 0.0;
    m_min_ask_seen      = 0.0;
    
    m_trade.SetExpertMagicNumber(m_magic);
    m_be_applied = false;

    // Atualiza estatísticas iniciais com base no histórico da conta
    UpdateHistoryStats();
}

//+------------------------------------------------------------------+
//| Atualiza estatísticas baseadas no histórico da conta             |
//+------------------------------------------------------------------+
void CSingleOrder::UpdateHistoryStats() {
    if(m_magic == 0) return;

    // Solicita o histórico de negociação da conta
    if(!HistorySelect(0, TimeCurrent())) {
        if(m_logger != NULL) m_logger.Warning("SingleOrder", "Falha ao carregar o historico de trades.");
        return;
    }

    int total_deals = HistoryDealsTotal();
    m_consecutive_losses = 0;
    m_consecutive_wins   = 0;
    m_current_multiplier = 1.0;
    
    int losses_count = 0;
    int wins_count = 0;
    bool found_active_streak = false;

    // Varre de trás para frente para pegar os últimos resultados fechados
    for(int i = total_deals - 1; i >= 0; i--) {
        ulong ticket = HistoryDealGetTicket(i);
        if(ticket == 0) continue;

        // Filtra pelo Magic Number do nosso EA
        long deal_magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
        if(deal_magic != m_magic) continue;

        // Apenas negócios de saída (que fecharam posição) nos interessam
        long entry_type = HistoryDealGetInteger(ticket, DEAL_ENTRY);
        if(entry_type != DEAL_ENTRY_OUT && entry_type != DEAL_ENTRY_INOUT) continue;

        double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
        datetime close_time = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);

        // Define a data do último fechamento se for o mais recente
        if(m_last_close_time == 0) {
            m_last_close_time = close_time;
            m_last_trade_profit = profit;
        }

        if(profit < 0.0) {
            if(!found_active_streak) {
                losses_count++;
                wins_count = 0;
            }
        } else if(profit > 0.0) {
            if(!found_active_streak) {
                wins_count++;
                losses_count = 0;
            }
        }
        
        // Se encontramos uma transição, finalizamos a busca da sequência atual
        if(losses_count > 0 || wins_count > 0) {
            found_active_streak = true;
        }
    }

    m_consecutive_losses = losses_count;
    m_consecutive_wins   = wins_count;

    // Calcula o multiplicador atual de acordo com o modo
    if(m_mart_mode == MARTINGALE_STANDARD && m_consecutive_losses > 0) {
        int steps = MathMin(m_consecutive_losses, m_mart_max_steps);
        m_current_multiplier = MathPow(m_mart_multiplier, steps);
    } 
    else if(m_mart_mode == ANTI_MARTINGALE && m_consecutive_wins > 0) {
        int steps = MathMin(m_consecutive_wins, m_mart_max_steps);
        m_current_multiplier = MathPow(m_mart_multiplier, steps);
    }
    
    if(m_logger != NULL) {
        m_logger.Info("SingleOrder", StringFormat("Stats: Ultimo Lucro: R$%.2f, Perdas Seguidas: %d, Ganhos Seguidos: %d, Multiplicador Atual: x%.2f",
                                  m_last_trade_profit, m_consecutive_losses, m_consecutive_wins, m_current_multiplier));
    }
}

//+------------------------------------------------------------------+
//| Verifica se passou o Cooldown de espera após ganho/perda          |
//+------------------------------------------------------------------+
bool CSingleOrder::CanOpenNewOrder(datetime current_time) {
    if(m_mode == SINGLE_DISABLED) return false;
    if(m_last_close_time == 0) return true; // Sem histórico, pode operar

    int elapsed = (int)(current_time - m_last_close_time);

    // Se o último trade foi perdedor e temos cooldown de perda
    if(m_last_trade_profit < 0.0 && m_wait_after_loss > 0) {
        if(elapsed < m_wait_after_loss) {
            int remaining = m_wait_after_loss - elapsed;
            if(m_logger != NULL) m_logger.Debug("SingleOrder", StringFormat("Aguardando cooldown de perda (%d segundos restantes).", remaining));
            return false;
        }
    }
    // Se o último trade foi vencedor e temos cooldown de ganho
    else if(m_last_trade_profit > 0.0 && m_wait_after_win > 0) {
        if(elapsed < m_wait_after_win) {
            int remaining = m_wait_after_win - elapsed;
            if(m_logger != NULL) m_logger.Debug("SingleOrder", StringFormat("Aguardando cooldown de ganho (%d segundos restantes).", remaining));
            return false;
        }
    }

    return true;
}

//+------------------------------------------------------------------+
//| Calcula o lote baseado nas regras de Martingale                  |
//+------------------------------------------------------------------+
double CSingleOrder::CalculateLot(double initial_lot, double lot_min, double lot_max) {
    // Força a atualização do histórico antes de calcular o lote
    UpdateHistoryStats();

    double calculated_lot = initial_lot * m_current_multiplier;
    
    // Limita os valores aos limites mínimos e máximos da corretora/EA
    calculated_lot = MathMax(calculated_lot, lot_min);
    calculated_lot = MathMin(calculated_lot, lot_max);
    
    // Normaliza para contratos inteiros na B3 (WIN/WDO usam passos inteiros de 1 em 1)
    return MathRound(calculated_lot);
}

//+------------------------------------------------------------------+
//| Abre Ordem Única                                                 |
//+------------------------------------------------------------------+
bool CSingleOrder::OpenOrder(string symbol, int direction, double volume, string comment) {
    if(m_mode == SINGLE_DISABLED) return false;

    // Garante que não há nenhuma posição aberta com o Magic Number
    if(PositionSelect(symbol)) {
        long pos_magic = PositionGetInteger(POSITION_MAGIC);
        if(pos_magic == m_magic) {
            if(m_logger != NULL) m_logger.Warning("SingleOrder", "Impossivel abrir ordem. Ja existe posicao ativa.");
            return false;
        }
    }

    m_be_applied = false;
    m_trail_active = false;
    m_max_bid_seen = 0.0;
    m_min_ask_seen = 0.0;
    double price = 0.0;
    double sl = 0.0;
    double tp = 0.0;

    // Define preços e níveis de SL/TP com base na direção
    if(direction == 1) { // COMPRA
        price = SymbolInfoDouble(symbol, SYMBOL_ASK);
        if(m_sl_points > 0.0) sl = price - m_sl_points;
        if(m_tp_points > 0.0) tp = price + m_tp_points;
        
        m_trade.Buy(volume, symbol, price, sl, tp, comment);
    } 
    else if(direction == -1) { // VENDA
        price = SymbolInfoDouble(symbol, SYMBOL_BID);
        if(m_sl_points > 0.0) sl = price + m_sl_points;
        if(m_tp_points > 0.0) tp = price - m_tp_points;
        
        m_trade.Sell(volume, symbol, price, sl, tp, comment);
    }

    uint ret_code = m_trade.ResultRetcode();
    if(ret_code == TRADE_RETCODE_DONE || ret_code == TRADE_RETCODE_PLACED) {
        if(m_logger != NULL) {
            m_logger.Info("SingleOrder", StringFormat("Posição aberta com sucesso. Lote: %.0f, Preço: %.2f, SL: %.2f, TP: %.2f", 
                                      volume, price, sl, tp));
        }
        return true;
    } else {
        if(m_logger != NULL) {
            m_logger.Error("SingleOrder", StringFormat("Falha ao abrir ordem. Código de retorno: %d", ret_code));
        }
        return false;
    }
}

//+------------------------------------------------------------------+
//| Gerenciamento de BreakEven para a posição individual             |
//+------------------------------------------------------------------+
void CSingleOrder::ManageBreakEven(string symbol, double current_bid, double current_ask, double tick_size) {
    if(m_be_activation <= 0.0 || m_be_applied) return;

    if(!PositionSelect(symbol)) return;
    long pos_magic = PositionGetInteger(POSITION_MAGIC);
    if(pos_magic != m_magic) return;

    double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
    long pos_type = PositionGetInteger(POSITION_TYPE);
    double current_sl = PositionGetDouble(POSITION_SL);

    if(pos_type == POSITION_TYPE_BUY) {
        // Distância que o preço subiu acima da entrada
        double ppts = (current_bid - open_price);
        if(ppts >= m_be_activation) {
            double new_sl = open_price + m_be_margin;
            // Só ajusta se o SL for menor do que o novo SL de segurança
            if(current_sl < new_sl) {
                m_trade.PositionModify(symbol, new_sl, PositionGetDouble(POSITION_TP));
                m_be_applied = true;
                if(m_logger != NULL) m_logger.Info("SingleOrder", StringFormat("BreakEven aplicado na COMPRA. SL ajustado para: %.2f", new_sl));
            }
        }
    } 
    else if(pos_type == POSITION_TYPE_SELL) {
        // Distância que o preço caiu abaixo da entrada
        double ppts = (open_price - current_ask);
        if(ppts >= m_be_activation) {
            double new_sl = open_price - m_be_margin;
            // Só ajusta se o SL for maior ou não definido
            if(current_sl > new_sl || current_sl == 0.0) {
                m_trade.PositionModify(symbol, new_sl, PositionGetDouble(POSITION_TP));
                m_be_applied = true;
                if(m_logger != NULL) m_logger.Info("SingleOrder", StringFormat("BreakEven aplicado na VENDA. SL ajustado para: %.2f", new_sl));
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Fecha a Posição se houver Sinal Contrário                         |
//+------------------------------------------------------------------+
bool CSingleOrder::CheckOppositeSignalClose(string symbol, int opposite_signal) {
    if(!m_close_on_opposite || opposite_signal == 0) return false;

    if(!PositionSelect(symbol)) return false;
    long pos_magic = PositionGetInteger(POSITION_MAGIC);
    if(pos_magic != m_magic) return false;

    long pos_type = PositionGetInteger(POSITION_TYPE);
    bool should_close = false;

    // Se temos posição de compra e o sinal contrário é de VENDA (-1)
    if(pos_type == POSITION_TYPE_BUY && opposite_signal == -1) {
        should_close = true;
    }
    // Se temos posição de venda e o sinal contrário é de COMPRA (1)
    else if(pos_type == POSITION_TYPE_SELL && opposite_signal == 1) {
        should_close = true;
    }

    if(should_close) {
        if(m_logger != NULL) m_logger.Info("SingleOrder", "Fechando posicao ativa devido a SINAL CONTRARIO detectado.");
        m_trade.PositionClose(symbol);
        
        // Zera o estado do BreakEven
        m_be_applied = false;
        
        // Força a atualização do histórico
        UpdateHistoryStats();
        return true;
    }

    return false;
}

//+------------------------------------------------------------------+
//| Reseta os multiplicadores do Martingale                          |
//+------------------------------------------------------------------+
void CSingleOrder::ResetMartingale() {
    m_consecutive_losses = 0;
    m_consecutive_wins   = 0;
    m_current_multiplier = 1.0;
    if(m_logger != NULL) m_logger.Info("SingleOrder", "Multiplicadores do Martingale resetados manualmente.");
}

//+------------------------------------------------------------------+
//| Gerenciamento do Trailing Móvel Físico para Ordem Única          |
//+------------------------------------------------------------------+
void CSingleOrder::ManageTrailing(string symbol, double current_bid, double current_ask, double tick_size) {
    if(!m_use_trailing) return;

    // Tenta selecionar a posição correspondente ao Magic Number
    if(!PositionSelect(symbol)) return;
    long pos_magic = PositionGetInteger(POSITION_MAGIC);
    if(pos_magic != m_magic) return;

    double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
    long pos_type     = PositionGetInteger(POSITION_TYPE);
    double current_sl = PositionGetDouble(POSITION_SL);
    double current_tp = PositionGetDouble(POSITION_TP);

    // COMPRA
    if(pos_type == POSITION_TYPE_BUY) {
        double profit_pts = current_bid - open_price;

        // Se o trailing ainda não foi ativado, verifica o gatilho (trigger)
        if(!m_trail_active) {
            if(profit_pts >= m_trail_trigger) {
                m_trail_active = true;
                m_max_bid_seen = current_bid;
                if(m_logger != NULL) {
                    m_logger.Info("SingleOrder", StringFormat("🔥 Trailing Físico Ativado na COMPRA! Lucro: %.0f pts. Preço: %.2f", profit_pts, current_bid));
                }
            }
        }

        // Se o trailing estiver ativo, arrasta o SL e o TP
        if(m_trail_active) {
            if(current_bid > m_max_bid_seen) {
                m_max_bid_seen = current_bid;
            }

            // Calcula o Stop Loss (Stop Gain) e Take Profit (Gain) ideais
            double target_sl = m_max_bid_seen - m_trail_stop_dist;
            double target_tp = m_max_bid_seen + m_trail_tp_dist;

            // Arredonda para o tick_size da corretora
            if(tick_size > 0.0) {
                target_sl = NormalizeDouble(MathRound(target_sl / tick_size) * tick_size, _Digits);
                target_tp = NormalizeDouble(MathRound(target_tp / tick_size) * tick_size, _Digits);
            }

            // O Stop Gain só pode subir. Verificamos se o novo SL ideal está acima do SL atual
            // e se a diferença é de pelo menos m_trail_step
            bool modify_sl = false;
            if(current_sl == 0.0 || target_sl >= current_sl + m_trail_step) {
                // Apenas move para o breakeven ou lucro (acima da entrada)
                if(target_sl > open_price) {
                    modify_sl = true;
                }
            }

            // O Take Profit móvel também caminha na direção da alta
            bool modify_tp = false;
            if(current_tp == 0.0 || target_tp >= current_tp + m_trail_step) {
                modify_tp = true;
            }

            // Modifica se houver alteração pendente
            if(modify_sl || modify_tp) {
                double new_sl = modify_sl ? target_sl : current_sl;
                double new_tp = modify_tp ? target_tp : current_tp;

                if(m_trade.PositionModify(symbol, new_sl, new_tp)) {
                    if(m_logger != NULL) {
                        m_logger.Info("SingleOrder", StringFormat("⚡ Trailing COMPRA atualizado. SL: %.2f (antigo: %.2f) | TP: %.2f (antigo: %.2f)", new_sl, current_sl, new_tp, current_tp));
                    }
                } else {
                    if(m_logger != NULL) {
                        m_logger.Error("SingleOrder", StringFormat("❌ Falha ao modificar Trailing COMPRA. Código: %d", m_trade.ResultRetcode()));
                    }
                }
            }
        }
    }
    // VENDA
    else if(pos_type == POSITION_TYPE_SELL) {
        double profit_pts = open_price - current_ask;

        // Se o trailing ainda não foi ativado, verifica o gatilho (trigger)
        if(!m_trail_active) {
            if(profit_pts >= m_trail_trigger) {
                m_trail_active = true;
                m_min_ask_seen = current_ask;
                if(m_logger != NULL) {
                    m_logger.Info("SingleOrder", StringFormat("🔥 Trailing Físico Ativado na VENDA! Lucro: %.0f pts. Preço: %.2f", profit_pts, current_ask));
                }
            }
        }

        // Se o trailing estiver ativo, arrasta o SL e o TP
        if(m_trail_active) {
            if(current_ask < m_min_ask_seen) {
                m_min_ask_seen = current_ask;
            }

            // Calcula o Stop Loss (Stop Gain) e Take Profit (Gain) ideais
            double target_sl = m_min_ask_seen + m_trail_stop_dist;
            double target_tp = m_min_ask_seen - m_trail_tp_dist;

            // Arredonda para o tick_size da corretora
            if(tick_size > 0.0) {
                target_sl = NormalizeDouble(MathRound(target_sl / tick_size) * tick_size, _Digits);
                target_tp = NormalizeDouble(MathRound(target_tp / tick_size) * tick_size, _Digits);
            }

            // O Stop Gain na venda só pode descer. Verificamos se o novo SL ideal está abaixo do SL atual
            // e se a diferença é de pelo menos m_trail_step
            bool modify_sl = false;
            if(current_sl == 0.0 || target_sl <= current_sl - m_trail_step) {
                // Apenas move para o breakeven ou lucro (abaixo da entrada)
                if(target_sl < open_price) {
                    modify_sl = true;
                }
            }

            // O Take Profit móvel na venda também caminha na direção da baixa
            bool modify_tp = false;
            if(current_tp == 0.0 || target_tp <= current_tp - m_trail_step) {
                modify_tp = true;
            }

            // Modifica se houver alteração pendente
            if(modify_sl || modify_tp) {
                double new_sl = modify_sl ? target_sl : current_sl;
                double new_tp = modify_tp ? target_tp : current_tp;

                if(m_trade.PositionModify(symbol, new_sl, new_tp)) {
                    if(m_logger != NULL) {
                        m_logger.Info("SingleOrder", StringFormat("⚡ Trailing VENDA atualizado. SL: %.2f (antigo: %.2f) | TP: %.2f (antigo: %.2f)", new_sl, current_sl, new_tp, current_tp));
                    }
                } else {
                    if(m_logger != NULL) {
                        m_logger.Error("SingleOrder", StringFormat("❌ Falha ao modificar Trailing VENDA. Código: %d", m_trade.ResultRetcode()));
                    }
                }
            }
        }
    }
}
