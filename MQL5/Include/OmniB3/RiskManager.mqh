//+------------------------------------------------------------------+
//|                                                 RiskManager.mqh  |
//|                Omni-B3 EA v1.1 — Gestão de Risco (B3/BRL)        |
//+------------------------------------------------------------------+
#property copyright "Projeto Omni-B3"
#property link      "https://github.com/helveciopereira/Stocks"
#property version   "1.10"
#property strict

#include "Defines.mqh"
#include "Logger.mqh"
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Gestão de Risco com múltiplas camadas de proteção                |
//+------------------------------------------------------------------+
class CRiskManager {
private:
    int      m_magic_number;
    double   m_equity_stop_percent;     // Equity mínima em % do saldo
    double   m_max_daily_dd_percent;    // DD diário máximo em %
    int      m_max_total_positions;     // Máx posições/níveis simultâneos
    double   m_min_margin_percent;      // Margem livre mínima em %
    bool     m_kill_switch;
    bool     m_daily_locked;
    double   m_initial_balance;         // Saldo no início do dia
    int      m_last_day;
    CLogger *m_logger;

    // Reseta contadores se mudou o dia
    void CheckDayReset() {
        MqlDateTime now;
        TimeCurrent(now);
        if(now.day != m_last_day) {
            m_last_day = now.day;
            m_daily_locked = false;
            m_initial_balance = AccountInfoDouble(ACCOUNT_BALANCE);
            m_logger.Info("RiskManager",
                StringFormat("🔄 Novo dia — Saldo base=R$%.2f", m_initial_balance));
        }
    }

    // Detecta filling mode para contra-ordens de emergência
    ENUM_ORDER_TYPE_FILLING DetectFilling(string symbol) {
        long filling = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
        if((filling & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
        if((filling & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
        return ORDER_FILLING_RETURN;
    }

public:
    CRiskManager(int magic_number, double equity_stop_pct, double max_daily_dd_pct,
                 int max_positions, double min_margin_pct, CLogger *logger) {

        m_magic_number        = magic_number;
        m_equity_stop_percent = equity_stop_pct;
        m_max_daily_dd_percent = max_daily_dd_pct;
        m_max_total_positions = max_positions;
        m_min_margin_percent  = min_margin_pct;
        m_kill_switch         = false;
        m_daily_locked        = false;
        m_logger              = logger;
        m_initial_balance     = AccountInfoDouble(ACCOUNT_BALANCE);

        MqlDateTime now;
        TimeCurrent(now);
        m_last_day = now.day;

        m_logger.Info("RiskManager",
            StringFormat("Init: EquityStop=%.0f%% | DDDiário=%.1f%% | MaxPos=%d | MargemMin=%.0f%%",
                         m_equity_stop_percent, m_max_daily_dd_percent,
                         m_max_total_positions, m_min_margin_percent));
    }

    //+--------------------------------------------------------------+
    //| Verifica se é seguro abrir novas posições                   |
    //| Parâmetro: current_levels — níveis virtuais da grade         |
    //+--------------------------------------------------------------+
    bool IsSafeToTrade(int current_levels) {
        CheckDayReset();

        // 1. Kill-Switch
        if(m_kill_switch) return false;

        // 2. Bloqueio diário
        if(m_daily_locked) return false;

        // 3. Equity Stop
        double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
        double balance = AccountInfoDouble(ACCOUNT_BALANCE);
        if(balance > 0 && (equity / balance * 100.0) < m_equity_stop_percent) {
            m_logger.Critical("RiskManager",
                StringFormat("🚨 EQUITY STOP! Equity=R$%.2f (%.1f%%)",
                             equity, equity / balance * 100.0));
            ActivateKillSwitch();
            return false;
        }

        // 4. DD Diário
        if(m_initial_balance > 0) {
            double daily_loss = m_initial_balance - equity;
            double daily_dd = (daily_loss / m_initial_balance) * 100.0;
            if(daily_dd > m_max_daily_dd_percent) {
                m_logger.Warning("RiskManager",
                    StringFormat("⚠️ DD Diário: %.2f%% (máx: %.2f%%)",
                                 daily_dd, m_max_daily_dd_percent));
                m_daily_locked = true;
                return false;
            }
        }

        // 5. Máximo de posições/níveis
        if(current_levels >= m_max_total_positions) return false;

        // 6. Margem livre
        double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
        double used_margin = AccountInfoDouble(ACCOUNT_MARGIN);
        if(used_margin > 0) {
            double margin_level = (free_margin / (free_margin + used_margin)) * 100.0;
            if(margin_level < m_min_margin_percent) {
                m_logger.Warning("RiskManager",
                    StringFormat("Margem baixa: %.1f%%", margin_level));
                return false;
            }
        }

        return true;
    }

    //+--------------------------------------------------------------+
    //| Kill-Switch: fecha tudo e desliga                             |
    //+--------------------------------------------------------------+
    void ActivateKillSwitch() {
        m_kill_switch = true;
        m_logger.Critical("RiskManager", "🔴 KILL-SWITCH! Fechando tudo...");

        CTrade trade;
        trade.SetExpertMagicNumber(m_magic_number);

        // Em NETTING: fecha todas as posições do magic number
        for(int i = PositionsTotal() - 1; i >= 0; i--) {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0) continue;
            if(PositionGetInteger(POSITION_MAGIC) == m_magic_number) {
                string sym = PositionGetString(POSITION_SYMBOL);
                trade.SetTypeFilling(DetectFilling(sym));
                trade.PositionClose(ticket);
            }
        }

        m_logger.Critical("RiskManager", "🔴 Kill-Switch executado. EA DESLIGADO.");
    }

    void ResetKillSwitch() {
        m_kill_switch = false;
        m_daily_locked = false;
        m_initial_balance = AccountInfoDouble(ACCOUNT_BALANCE);
        m_logger.Info("RiskManager", "🟢 Kill-Switch resetado.");
    }

    bool IsKillSwitchActive() { return m_kill_switch; }
    bool IsDailyLocked()      { return m_daily_locked; }
};

//+------------------------------------------------------------------+
