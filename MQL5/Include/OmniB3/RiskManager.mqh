//+------------------------------------------------------------------+
//|                                                 RiskManager.mqh  |
//|                Omni-B3 EA v2.46 â€” GestÃ£o de Risco (B3/BRL)        |
//|         Limites expandidos: diÃ¡rio, total, por DD, por conta     |
//+------------------------------------------------------------------+
//| Copyright 2026, Projeto Omni-B3                                 |
//| https://github.com/helveciopereira/Stocks                        |
//+------------------------------------------------------------------+
#property copyright "Projeto Omni-B3"
#property link      "https://github.com/helveciopereira/Stocks"
#property version   "2.46"
#property strict

#include "Defines.mqh"
#include "Logger.mqh"
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| GestÃ£o de Risco com mÃºltiplas camadas de proteÃ§Ã£o â€” v2.13        |
//|                                                                   |
//| Inspirado nos "LIMITS" do ToTheMoon v3.5:                         |
//| - Limites por lucro/prejuÃ­zo atual, diÃ¡rio e total               |
//| - Limites por DD% do saldo e do capital lÃ­quido                  |
//| - Limites por quantidade de ordens (total, ganhadoras, perdedoras)|
//| - Limites de equity e saldo mÃ­nimo/mÃ¡ximo                        |
//| - Kill-switch de emergÃªncia                                       |
//+------------------------------------------------------------------+
class CRiskManager {
private:
    int      m_magic_number;

    // Equity Stop (proteÃ§Ã£o principal)
    double   m_equity_stop_percent;     // Equity mÃ­nima em % do saldo
    double   m_max_daily_dd_percent;    // DD diÃ¡rio mÃ¡ximo em %
    int      m_max_total_positions;     // MÃ¡x posiÃ§Ãµes/nÃ­veis simultÃ¢neos
    double   m_min_margin_percent;      // Margem livre mÃ­nima em %

    // Limites atuais (por ciclo de trade)
    double   m_limit_profit_current;    // Lucro mÃ¡ximo atual (R$) â€” fecha e para
    double   m_limit_loss_current;      // Perda mÃ¡xima atual (R$) â€” fecha e para
    double   m_limit_profit_pct_current;// Lucro mÃ¡ximo atual (%)
    double   m_limit_loss_pct_current;  // Perda mÃ¡xima atual (%)
    int      m_wait_after_limit;        // Segundos para aguardar apÃ³s limite
    bool     m_stop_after_limit;        // Parar completamente apÃ³s limite?

    // Limites diÃ¡rios
    double   m_limit_profit_daily;      // Lucro mÃ¡ximo diÃ¡rio (R$)
    double   m_limit_loss_daily;        // Perda mÃ¡xima diÃ¡ria (R$)
    double   m_limit_dd_daily;          // DD% mÃ¡ximo diÃ¡rio
    int      m_limit_orders_daily;      // MÃ¡x ordens por dia
    int      m_limit_wins_daily;        // MÃ¡x ordens ganhadoras por dia
    int      m_limit_losses_daily;      // MÃ¡x ordens perdedoras por dia
    bool     m_allow_grid_outside_limit;// Abrir grid mesmo fora do limite diÃ¡rio?

    // Limites de conta
    double   m_min_balance;             // Saldo mÃ­nimo para operar (R$)
    double   m_min_equity;              // Capital lÃ­quido mÃ­nimo (R$)
    double   m_max_balance;             // Saldo mÃ¡ximo â€” para quando atingir
    double   m_max_equity;              // Equity mÃ¡xima â€” para quando atingir
    double   m_limit_dd_equity_pct;     // DD% mÃ¡ximo do capital lÃ­quido
    int      m_wait_after_dd_equity;    // Segundos para aguardar apÃ³s DD equity
    bool     m_stop_after_dd_equity;    // Parar apÃ³s DD equity?

    // Estado
    bool     m_kill_switch;
    bool     m_daily_locked;
    bool     m_limit_locked;            // Travado por limite atual
    double   m_initial_balance;         // Saldo no inÃ­cio do dia
    double   m_initial_equity;          // Equity no inÃ­cio do dia
    int      m_last_day;
    int      m_daily_order_count;       // Contador de ordens do dia
    int      m_daily_wins;              // Ganhos do dia
    int      m_daily_losses;            // Perdas do dia
    double   m_daily_profit;            // Lucro acumulado do dia
    double   m_daily_max_dd;            // Drawdown diÃ¡rio mÃ¡ximo registrado
    datetime m_limit_lock_time;         // Quando foi travado por limite

    CLogger *m_logger;

    //+--------------------------------------------------------------+
    //| Reseta contadores se mudou o dia                              |
    //+--------------------------------------------------------------+
    void CheckDayReset() {
        MqlDateTime now;
        TimeCurrent(now);
        if(now.day != m_last_day) {
            m_last_day = now.day;
            m_daily_locked = false;
            m_limit_locked = false;
            m_initial_balance = AccountInfoDouble(ACCOUNT_BALANCE);
            m_initial_equity = AccountInfoDouble(ACCOUNT_EQUITY);
            m_daily_order_count = 0;
            m_daily_wins = 0;
            m_daily_losses = 0;
            m_daily_profit = 0.0;
            m_daily_max_dd = 0.0;
            m_logger.Info("RiskManager",
                StringFormat("ðŸ”„ Novo dia â€” Saldo=R$%.2f | Equity=R$%.2f",
                             m_initial_balance, m_initial_equity));
        }
    }

    //+--------------------------------------------------------------+
    //| Detecta filling mode para contra-ordens de emergÃªncia        |
    //+--------------------------------------------------------------+
    ENUM_ORDER_TYPE_FILLING DetectFilling(string symbol) {
        long filling = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
        if((filling & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
        if((filling & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
        return ORDER_FILLING_RETURN;
    }

public:
    //+--------------------------------------------------------------+
    //| Construtor                                                    |
    //+--------------------------------------------------------------+
    CRiskManager(int magic_number, double equity_stop_pct, double max_daily_dd_pct,
                 int max_positions, double min_margin_pct, CLogger *logger) {

        m_magic_number        = magic_number;
        m_equity_stop_percent = equity_stop_pct;
        m_max_daily_dd_percent = max_daily_dd_pct;
        m_max_total_positions = max_positions;
        m_min_margin_percent  = min_margin_pct;
        m_kill_switch         = false;
        m_daily_locked        = false;
        m_limit_locked        = false;
        m_logger              = logger;
        m_initial_balance     = AccountInfoDouble(ACCOUNT_BALANCE);
        m_initial_equity      = AccountInfoDouble(ACCOUNT_EQUITY);

        // Defaults â€” limites desabilitados (0 = sem limite)
        m_limit_profit_current = 0.0;
        m_limit_loss_current   = 0.0;
        m_limit_profit_pct_current = 0;
        m_limit_loss_pct_current   = 0;
        m_wait_after_limit     = 0;
        m_stop_after_limit     = false;

        m_limit_profit_daily   = 0.0;
        m_limit_loss_daily     = 0.0;
        m_limit_dd_daily       = 0.0;
        m_limit_orders_daily   = 0;
        m_limit_wins_daily     = 0;
        m_limit_losses_daily   = 0;
        m_allow_grid_outside_limit = true;

        m_min_balance          = 0.0;
        m_min_equity           = 0.0;
        m_max_balance          = 0.0;
        m_max_equity           = 0.0;
        m_limit_dd_equity_pct  = 0.0;
        m_wait_after_dd_equity = 0;
        m_stop_after_dd_equity = false;

        m_daily_order_count    = 0;
        m_daily_wins           = 0;
        m_daily_losses         = 0;
        m_daily_profit         = 0.0;
        m_daily_max_dd         = 0.0;
        m_limit_lock_time      = 0;

        MqlDateTime now;
        TimeCurrent(now);
        m_last_day = now.day;

        m_logger.Info("RiskManager",
            StringFormat("Init: EquityStop=%.0f%% | DDDiÃ¡rio=%.1f%% | MaxPos=%d | MargemMin=%.0f%%",
                         m_equity_stop_percent, m_max_daily_dd_percent,
                         m_max_total_positions, m_min_margin_percent));
    }

    //+--------------------------------------------------------------+
    //| Configura limites atuais (por ciclo de trade)                |
    //+--------------------------------------------------------------+
    void SetCurrentLimits(double profit, double loss, int profit_pct, int loss_pct,
                          int wait, bool stop) {
        m_limit_profit_current = profit;
        m_limit_loss_current = loss;
        m_limit_profit_pct_current = profit_pct;
        m_limit_loss_pct_current = loss_pct;
        m_wait_after_limit = wait;
        m_stop_after_limit = stop;
    }

    //+--------------------------------------------------------------+
    //| Configura limites diÃ¡rios                                     |
    //+--------------------------------------------------------------+
    void SetDailyLimits(double profit, double loss, double dd_pct,
                        int max_orders, int max_wins, int max_losses,
                        bool allow_grid) {
        m_limit_profit_daily = profit;
        m_limit_loss_daily = loss;
        m_limit_dd_daily = dd_pct;
        m_limit_orders_daily = max_orders;
        m_limit_wins_daily = max_wins;
        m_limit_losses_daily = max_losses;
        m_allow_grid_outside_limit = allow_grid;
    }

    //+--------------------------------------------------------------+
    //| Configura limites de conta                                    |
    //+--------------------------------------------------------------+
    void SetAccountLimits(double min_balance, double min_equity,
                          double max_balance, double max_equity,
                          double dd_equity_pct, int wait_dd, bool stop_dd) {
        m_min_balance = min_balance;
        m_min_equity = min_equity;
        m_max_balance = max_balance;
        m_max_equity = max_equity;
        m_limit_dd_equity_pct = dd_equity_pct;
        m_wait_after_dd_equity = wait_dd;
        m_stop_after_dd_equity = stop_dd;
    }

    //+--------------------------------------------------------------+
    //| Verifica se Ã© seguro abrir novas posiÃ§Ãµes                   |
    //| ParÃ¢metro: current_levels â€” nÃ­veis virtuais da grade         |
    //+--------------------------------------------------------------+
    bool IsSafeToTrade(int current_levels) {
        CheckDayReset();

        // 1. Kill-Switch (trava absoluta de emergÃªncia)
        if(m_kill_switch) {
            m_logger.Warning("RiskManager", "[BLOQUEIO] OperaÃ§Ã£o bloqueada pelo Kill-Switch ativo (EA desativado).");
            return false;
        }

        // 2. Bloqueio diÃ¡rio
        if(m_daily_locked) {
            m_logger.Warning("RiskManager", "[BLOQUEIO] OperaÃ§Ã£o bloqueada devido a algum limite diÃ¡rio de proteÃ§Ã£o atingido hoje.");
            return false;
        }

        // 3. Bloqueio por limite atual (ciclo ativo)
        if(m_limit_locked) {
            if(m_stop_after_limit) {
                m_logger.Warning("RiskManager", "[BLOQUEIO] Parada permanente ativada apÃ³s atingir limite de perda/lucro configurado.");
                return false;
            }
            // Verifica se tempo de espera expirou
            int elapsed = (int)(TimeCurrent() - m_limit_lock_time);
            if(m_wait_after_limit > 0 && elapsed < m_wait_after_limit) {
                m_logger.Warning("RiskManager", StringFormat("[BLOQUEIO] Cooldown ativo. Aguardando tempo regulamentar de %d segundos apÃ³s limite (%d segundos restantes).",
                                 m_wait_after_limit, m_wait_after_limit - elapsed));
                return false;
            }
            m_limit_locked = false;  // Tempo expirou, libera
        }

        double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
        double balance = AccountInfoDouble(ACCOUNT_BALANCE);

        // 4. Equity Stop (Bloqueio crÃ­tico de liquidez)
        if(balance > 0 && (equity / balance * 100.0) < m_equity_stop_percent) {
            m_logger.Critical("RiskManager",
                StringFormat("ðŸš¨ EQUITY STOP! Capital LÃ­quido (R$%.2f) caiu abaixo do limite de %.1f%% do Saldo (R$%.2f) â€” Atual: %.1f%%. Ativando Kill-Switch!",
                             equity, m_equity_stop_percent, balance, equity / balance * 100.0));
            ActivateKillSwitch();
            return false;
        }

        // 5. Drawdown DiÃ¡rio e Limites DiÃ¡rios
        if(m_initial_balance > 0) {
            double daily_loss = m_initial_balance - equity;
            double daily_dd = (daily_loss > 0) ? (daily_loss / m_initial_balance) * 100.0 : 0.0;
            
            // Atualiza drawdown diÃ¡rio mÃ¡ximo registrado
            if(daily_dd > m_daily_max_dd) m_daily_max_dd = daily_dd;

            // Drawdown DiÃ¡rio MÃ¡ximo (%)
            if(m_max_daily_dd_percent > 0 && daily_dd > m_max_daily_dd_percent) {
                m_logger.Warning("RiskManager",
                    StringFormat("âš ï¸ DD DiÃ¡rio Atingido: %.2f%% de drawdown (Limite MÃ¡ximo: %.2f%%). Bloqueando operaÃ§Ãµes diÃ¡rias para preservar capital inicial de R$%.2f.",
                                 daily_dd, m_max_daily_dd_percent, m_initial_balance));
                m_daily_locked = true;
                return false;
            }

            // Limite diÃ¡rio de perda em R$
            if(m_limit_loss_daily > 0.0 && daily_loss >= m_limit_loss_daily) {
                m_logger.Warning("RiskManager",
                    StringFormat("âš ï¸ Perda diÃ¡ria limite atingida: R$%.2f de perda flutuante/realizada (Limite MÃ¡ximo: R$%.2f). OperaÃ§Ãµes bloqueadas hoje.",
                                 daily_loss, m_limit_loss_daily));
                m_daily_locked = true;
                return false;
            }

            // Limite diÃ¡rio de lucro em R$
            if(m_limit_profit_daily > 0.0 && (equity - m_initial_balance) >= m_limit_profit_daily) {
                m_logger.Info("RiskManager",
                    StringFormat("âœ… Meta diÃ¡ria de lucro atingida! Lucro acumulado hoje: R$%.2f (Meta: R$%.2f). OperaÃ§Ãµes encerradas hoje.",
                                 equity - m_initial_balance, m_limit_profit_daily));
                m_daily_locked = true;
                return false;
            }
        }

        // 6. Limite de ordens diÃ¡rias (Overtrading)
        if(m_limit_orders_daily > 0 && m_daily_order_count >= m_limit_orders_daily) {
            m_logger.Warning("RiskManager",
                StringFormat("âš ï¸ Limite diÃ¡rio de ordens atingido: %d ordens executadas hoje (Limite MÃ¡ximo: %d). Bloqueando novas entradas.",
                             m_daily_order_count, m_limit_orders_daily));
            m_daily_locked = true;
            return false;
        }
        if(m_limit_wins_daily > 0 && m_daily_wins >= m_limit_wins_daily) {
            m_logger.Warning("RiskManager",
                StringFormat("âš ï¸ Limite diÃ¡rio de vitÃ³rias (trades vencedores) atingido: %d vitÃ³rias (Limite MÃ¡ximo: %d). Bloqueando novas entradas.",
                             m_daily_wins, m_limit_wins_daily));
            m_daily_locked = true;
            return false;
        }
        if(m_limit_losses_daily > 0 && m_daily_losses >= m_limit_losses_daily) {
            m_logger.Warning("RiskManager",
                StringFormat("âš ï¸ Limite diÃ¡rio de perdas (trades perdedores) atingido: %d perdas (Limite MÃ¡ximo: %d). Bloqueando novas entradas.",
                             m_daily_losses, m_limit_losses_daily));
            m_daily_locked = true;
            return false;
        }

        // 7. MÃ¡ximo de posiÃ§Ãµes/nÃ­veis simultÃ¢neos da grade
        if(current_levels >= m_max_total_positions) {
            m_logger.Warning("RiskManager",
                StringFormat("[BLOQUEIO] Limite de nÃ­veis simultÃ¢neos alcanÃ§ado: %d nÃ­veis ativos (Limite MÃ¡ximo: %d). Aguardando fechamento de nÃ­veis.",
                             current_levels, m_max_total_positions));
            return false;
        }

        // 8. Margem livre da corretora (Margem Livre / Margem Exigida)
        double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
        double used_margin = AccountInfoDouble(ACCOUNT_MARGIN);
        if(used_margin > 0) {
            double margin_level = (free_margin / (free_margin + used_margin)) * 100.0;
            if(margin_level < m_min_margin_percent) {
                m_logger.Warning("RiskManager",
                    StringFormat("ðŸš¨ Margem Livre Insuficiente na Corretora! Margem livre calculada em %.1f%% do capital garantido, inferior ao limite de seguranÃ§a configurado de %.1f%%. Novas entradas bloqueadas para evitar Stop Out compulsÃ³rio pela corretora.", 
                                 margin_level, m_min_margin_percent));
                return false;
            }
        }

        // 9. Limites de conta (saldo e equity mÃ­nimos)
        if(m_min_balance > 0.0 && balance < m_min_balance) {
            m_logger.Warning("RiskManager",
                StringFormat("Saldo abaixo do mÃ­nimo: R$%.2f (mÃ­n: R$%.2f)",
                             balance, m_min_balance));
            return false;
        }
        if(m_min_equity > 0.0 && equity < m_min_equity) {
            m_logger.Warning("RiskManager",
                StringFormat("Equity abaixo do mÃ­nimo: R$%.2f (mÃ­n: R$%.2f)",
                             equity, m_min_equity));
            return false;
        }

        // 10. Meta de saldo/equity mÃ¡ximos (para quando atingir)
        if(m_max_balance > 0.0 && balance >= m_max_balance) {
            m_logger.Info("RiskManager",
                StringFormat("âœ… Meta de saldo atingida: R$%.2f", balance));
            return false;
        }

        return true;
    }

    //+--------------------------------------------------------------+
    //| Registra uma ordem completada (para contadores diÃ¡rios)      |
    //+--------------------------------------------------------------+
    void RegisterOrder(bool is_win, double profit) {
        m_daily_order_count++;
        m_daily_profit += profit;
        if(is_win) m_daily_wins++;
        else       m_daily_losses++;
    }

    //+--------------------------------------------------------------+
    //| Kill-Switch: fecha tudo e desliga                             |
    //+--------------------------------------------------------------+
    void ActivateKillSwitch() {
        m_kill_switch = true;
        m_logger.Critical("RiskManager", "ðŸ”´ KILL-SWITCH! Fechando tudo...");

        CTrade trade;
        trade.SetExpertMagicNumber(m_magic_number);

        for(int i = PositionsTotal() - 1; i >= 0; i--) {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0) continue;
            if(PositionGetInteger(POSITION_MAGIC) == m_magic_number) {
                string sym = PositionGetString(POSITION_SYMBOL);
                trade.SetTypeFilling(DetectFilling(sym));
                trade.PositionClose(ticket);
            }
        }

        m_logger.Critical("RiskManager", "ðŸ”´ Kill-Switch executado. EA DESLIGADO.");
    }

    //+--------------------------------------------------------------+
    //| Reset do Kill-Switch e locks                                  |
    //+--------------------------------------------------------------+
    void ResetKillSwitch() {
        m_kill_switch = false;
        m_daily_locked = false;
        m_limit_locked = false;
        m_initial_balance = AccountInfoDouble(ACCOUNT_BALANCE);
        m_initial_equity = AccountInfoDouble(ACCOUNT_EQUITY);
        m_logger.Info("RiskManager", "ðŸŸ¢ Kill-Switch resetado.");
    }

    //+--------------------------------------------------------------+
    //| Getters de estado                                              |
    //+--------------------------------------------------------------+
    bool   IsKillSwitchActive() { return m_kill_switch; }
    bool   IsDailyLocked()      { return m_daily_locked; }
    bool   IsLimitLocked()      { return m_limit_locked; }
    double GetDailyProfit()     { return m_daily_profit; }
    int    GetDailyOrderCount() { return m_daily_order_count; }
    double GetDailyMaxDrawdown() { return m_daily_max_dd; }

    //+--------------------------------------------------------------+
    //| Status para dashboard                                         |
    //+--------------------------------------------------------------+
    string GetStatusString() {
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        double daily_pnl = equity - m_initial_balance;
        return StringFormat("Risco: Ordens=%d/%d | P&L Dia=R$%.2f | Kill=%s",
                           m_daily_order_count,
                           m_limit_orders_daily > 0 ? m_limit_orders_daily : 999,
                           daily_pnl,
                           m_kill_switch ? "ðŸ”´" : "ðŸŸ¢");
    }
};

//+------------------------------------------------------------------+
