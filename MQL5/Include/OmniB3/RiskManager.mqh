//+------------------------------------------------------------------+
//|                                                 RiskManager.mqh  |
//|                    Omni-B3 EA v1.0 — Gestão de Risco e Capital   |
//|       Equity Stop, Drawdown Diário, Kill-Switch e Proteções      |
//+------------------------------------------------------------------+
#property copyright "Projeto Omni-B3"
#property link      "https://github.com/seu-usuario/Stocks"
#property version   "1.00"
#property strict

#include "Defines.mqh"
#include "Logger.mqh"
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Classe de Gestão de Risco do EA                                  |
//|                                                                   |
//| Implementa múltiplas camadas de proteção de capital:             |
//|  - Equity Stop: fecha tudo se equity cair abaixo de X%          |
//|  - Max Drawdown Diário: limita perda por dia                     |
//|  - Max Posições: limite global de ordens simultâneas             |
//|  - Kill-Switch: botão de pânico que desliga o EA                 |
//|  - Margem livre: verifica se há margem para novas ordens         |
//+------------------------------------------------------------------+
class CRiskManager {
private:
    int      m_magic_number;            // Magic number do EA
    double   m_equity_stop_percent;     // % de equity para shutdown (ex: 70%)
    double   m_max_daily_dd_percent;    // % máximo de DD diário (ex: 5%)
    int      m_max_total_positions;     // Máximo de posições simultâneas
    double   m_min_margin_percent;      // Margem livre mínima em %
    bool     m_kill_switch;             // Flag global de pânico
    bool     m_daily_locked;            // Flag de bloqueio diário
    double   m_initial_balance;         // Saldo no início do dia
    double   m_account_initial_equity;  // Equity base para cálculo de DD
    int      m_last_day;                // Dia anterior (para reset diário)
    CLogger *m_logger;                  // Sistema de logging

    //+--------------------------------------------------------------+
    //| Reseta contadores diários se mudou o dia                     |
    //+--------------------------------------------------------------+
    void CheckDayReset() {
        MqlDateTime now;
        TimeCurrent(now);
        if(now.day != m_last_day) {
            m_last_day = now.day;
            m_daily_locked = false;
            m_initial_balance = AccountInfoDouble(ACCOUNT_BALANCE);
            m_logger.Info("RiskManager",
                StringFormat("🔄 Novo dia — Saldo base=%.2f | DD diário resetado",
                             m_initial_balance));
        }
    }

public:
    //+--------------------------------------------------------------+
    //| Construtor com parâmetros de proteção                        |
    //+--------------------------------------------------------------+
    CRiskManager(int magic_number,
                 double equity_stop_percent,
                 double max_daily_dd_percent,
                 int max_total_positions,
                 double min_margin_percent,
                 CLogger *logger) {

        m_magic_number          = magic_number;
        m_equity_stop_percent   = equity_stop_percent;
        m_max_daily_dd_percent  = max_daily_dd_percent;
        m_max_total_positions   = max_total_positions;
        m_min_margin_percent    = min_margin_percent;
        m_kill_switch           = false;
        m_daily_locked          = false;
        m_logger                = logger;
        m_initial_balance       = AccountInfoDouble(ACCOUNT_BALANCE);
        m_account_initial_equity = AccountInfoDouble(ACCOUNT_EQUITY);

        MqlDateTime now;
        TimeCurrent(now);
        m_last_day = now.day;

        m_logger.Info("RiskManager",
            StringFormat("Inicializado: EquityStop=%.1f%% | DDDiário=%.1f%% | MaxPos=%d | MargemMin=%.1f%%",
                         m_equity_stop_percent, m_max_daily_dd_percent,
                         m_max_total_positions, m_min_margin_percent));
    }

    //+--------------------------------------------------------------+
    //| Verifica se é seguro abrir novas posições                   |
    //| Retorna: true se TODAS as condições de segurança estão OK   |
    //+--------------------------------------------------------------+
    bool IsSafeToTrade() {
        // Reset diário de contadores
        CheckDayReset();

        // VERIFICAÇÃO 1: Kill-Switch ativado?
        if(m_kill_switch) {
            return false; // EA desligado por pânico
        }

        // VERIFICAÇÃO 2: Bloqueio diário ativo?
        if(m_daily_locked) {
            return false; // DD diário excedido
        }

        // VERIFICAÇÃO 3: Equity Stop
        double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
        double balance = AccountInfoDouble(ACCOUNT_BALANCE);
        if(balance > 0 && (equity / balance * 100.0) < m_equity_stop_percent) {
            m_logger.Critical("RiskManager",
                StringFormat("🚨 EQUITY STOP! Equity=%.2f (%.1f%% do saldo)",
                             equity, equity / balance * 100.0));
            ActivateKillSwitch();
            return false;
        }

        // VERIFICAÇÃO 4: Drawdown Diário
        if(m_initial_balance > 0) {
            double daily_loss = m_initial_balance - balance;
            double daily_dd_pct = (daily_loss / m_initial_balance) * 100.0;
            if(daily_dd_pct > m_max_daily_dd_percent) {
                m_logger.Warning("RiskManager",
                    StringFormat("⚠️ DD Diário excedido: %.2f%% (máx: %.2f%%)",
                                 daily_dd_pct, m_max_daily_dd_percent));
                m_daily_locked = true;
                return false;
            }
        }

        // VERIFICAÇÃO 5: Máximo de posições
        int total_positions = 0;
        for(int i = PositionsTotal() - 1; i >= 0; i--) {
            ulong ticket = PositionGetTicket(i);
            if(ticket > 0 && PositionGetInteger(POSITION_MAGIC) == m_magic_number) {
                total_positions++;
            }
        }
        if(total_positions >= m_max_total_positions) {
            m_logger.Debug("RiskManager",
                StringFormat("Limite de posições atingido: %d/%d",
                             total_positions, m_max_total_positions));
            return false;
        }

        // VERIFICAÇÃO 6: Margem Livre
        double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
        double total_margin = AccountInfoDouble(ACCOUNT_MARGIN);
        if(total_margin > 0) {
            double margin_level = (free_margin / (free_margin + total_margin)) * 100.0;
            if(margin_level < m_min_margin_percent) {
                m_logger.Warning("RiskManager",
                    StringFormat("Margem livre baixa: %.1f%% (mín: %.1f%%)",
                                 margin_level, m_min_margin_percent));
                return false;
            }
        }

        return true; // Todas as verificações passaram
    }

    //+--------------------------------------------------------------+
    //| Ativa o Kill-Switch: fecha TODAS as posições e desliga o EA  |
    //| Este é o botão de pânico — ação irreversível até reinício    |
    //+--------------------------------------------------------------+
    void ActivateKillSwitch() {
        m_kill_switch = true;
        m_logger.Critical("RiskManager", "🔴 KILL-SWITCH ATIVADO! Fechando todas as posições...");

        CTrade trade;
        trade.SetExpertMagicNumber(m_magic_number);

        // Fecha todas as posições deste magic number
        int closed = 0;
        for(int i = PositionsTotal() - 1; i >= 0; i--) {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0) continue;
            if(PositionGetInteger(POSITION_MAGIC) == m_magic_number) {
                if(trade.PositionClose(ticket)) {
                    closed++;
                }
            }
        }

        m_logger.Critical("RiskManager",
            StringFormat("🔴 Kill-Switch: %d posições fechadas. EA DESLIGADO.", closed));
    }

    //+--------------------------------------------------------------+
    //| Desativa o Kill-Switch (para reset manual)                   |
    //+--------------------------------------------------------------+
    void ResetKillSwitch() {
        m_kill_switch = false;
        m_daily_locked = false;
        m_initial_balance = AccountInfoDouble(ACCOUNT_BALANCE);
        m_logger.Info("RiskManager", "🟢 Kill-Switch resetado. EA reativado.");
    }

    //+--------------------------------------------------------------+
    //| Retorna status do Kill-Switch                                |
    //+--------------------------------------------------------------+
    bool IsKillSwitchActive() { return m_kill_switch; }

    //+--------------------------------------------------------------+
    //| Retorna status do bloqueio diário                            |
    //+--------------------------------------------------------------+
    bool IsDailyLocked() { return m_daily_locked; }
};

//+------------------------------------------------------------------+
