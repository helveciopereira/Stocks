//+------------------------------------------------------------------+
//|                                               MoneyManager.mqh   |
//|              Omni-B3 EA v2.25 — Gestão de Capital                 |
//|       Saldo do Robô, preset multiplier, ajuste de moeda          |
//+------------------------------------------------------------------+
#property copyright "Projeto Omni-B3"
#property link      "https://github.com/helveciopereira/Stocks"
#property version   "2.25"
#property strict

#include "Defines.mqh"
#include "Logger.mqh"

//+------------------------------------------------------------------+
//| Gestão de Capital e Dimensionamento de Lotes                      |
//|                                                                   |
//| Inspirado no sistema "Money Manage" do ToTheMoon v3.5:            |
//| - Saldo do Robô (separado do saldo da conta)                     |
//| - Multiplicador de preset (xPreset): ajusta lotes pelo saldo     |
//| - StopLoss por DD máximo do saldo do robô                        |
//| - Ajuste de moeda (BRL → USD equivalente para cálculos)          |
//+------------------------------------------------------------------+
class CMoneyManager {
private:
    CLogger *m_logger;

    // Modo do saldo do robô
    ENUM_BALANCE_MODE m_balance_mode;
    double  m_fixed_balance;       // Saldo fixo (BAL_FIXED_VALUE)
    double  m_balance_percentage;  // % do saldo da conta (BAL_PERCENTAGE)
    double  m_max_balance;         // Teto do saldo do robô (0 = sem teto)

    // Preset multiplier (xPreset)
    ENUM_PRESET_MODE m_preset_mode;
    double  m_preset_factor;       // Fator base (ex: 1200 USD = x1)

    // Ajuste de moeda da conta
    double  m_currency_rate;       // Taxa de conversão (ex: BRL/USD = 5.50)

    // Stops do Money Manager
    double  m_stoploss_amount;     // StopLoss em valor (R$)
    double  m_stoploss_percent;    // StopLoss em % do saldo do robô
    double  m_current_loss;        // Prejuízo atual acumulado (negativo)
    double  m_max_loss_amount;     // Prejuízo máximo atual antes de parar
    int     m_wait_after_loss;     // Segundos para aguardar após atingir perda máx
    bool    m_stop_after_loss;     // Parar completamente após perda máxima?

    // Cache
    double  m_last_robot_balance;  // Último saldo calculado do robô
    datetime m_last_calc_time;     // Última vez que calculou

public:
    //+--------------------------------------------------------------+
    //| Construtor                                                    |
    //+--------------------------------------------------------------+
    CMoneyManager(CLogger *logger) {
        m_logger = logger;

        // Defaults — modo simples, usa saldo total da conta
        m_balance_mode      = BAL_FULL_ACCOUNT;
        m_fixed_balance     = 0.0;
        m_balance_percentage = 100.0;
        m_max_balance       = 0.0;

        m_preset_mode       = PRESET_DISABLED;
        m_preset_factor     = 1000.0;

        m_currency_rate     = 1.0;  // Sem conversão por padrão

        m_stoploss_amount   = 0.0;
        m_stoploss_percent  = 0.0;
        m_current_loss      = 0.0;
        m_max_loss_amount   = 0.0;
        m_wait_after_loss   = 0;
        m_stop_after_loss   = false;

        m_last_robot_balance = 0.0;
        m_last_calc_time    = 0;
    }

    //+--------------------------------------------------------------+
    //| Configura modo do saldo do robô                              |
    //+--------------------------------------------------------------+
    void SetBalanceMode(ENUM_BALANCE_MODE mode, double value, double max_balance) {
        m_balance_mode = mode;
        m_max_balance = max_balance;

        switch(mode) {
            case BAL_FULL_ACCOUNT:
                m_logger.Info("MoneyMgr", "Saldo: 100% da conta");
                break;
            case BAL_PERCENTAGE:
                m_balance_percentage = value;
                m_logger.Info("MoneyMgr",
                    StringFormat("Saldo: %.0f%% da conta", m_balance_percentage));
                break;
            case BAL_FIXED_VALUE:
                m_fixed_balance = value;
                m_logger.Info("MoneyMgr",
                    StringFormat("Saldo fixo: R$%.2f", m_fixed_balance));
                break;
        }
    }

    //+--------------------------------------------------------------+
    //| Configura preset multiplier                                   |
    //+--------------------------------------------------------------+
    void SetPresetMode(ENUM_PRESET_MODE mode, double factor) {
        m_preset_mode = mode;
        m_preset_factor = factor;

        if(mode != PRESET_DISABLED)
            m_logger.Info("MoneyMgr",
                StringFormat("Preset: Modo=%s Fator=R$%.2f",
                             EnumToString(mode), factor));
    }

    //+--------------------------------------------------------------+
    //| Configura ajuste de moeda                                    |
    //| rate: taxa BRL/USD (ex: 5.50 significa 1 USD = 5.50 BRL)    |
    //+--------------------------------------------------------------+
    void SetCurrencyRate(double rate) {
        m_currency_rate = (rate > 0.0) ? rate : 1.0;
        m_logger.Info("MoneyMgr",
            StringFormat("Moeda: Taxa=%.2f", m_currency_rate));
    }

    //+--------------------------------------------------------------+
    //| Configura stops do Money Manager                             |
    //+--------------------------------------------------------------+
    void SetStopLoss(double amount, double percent, double max_loss,
                     int wait_seconds, bool stop_after) {
        m_stoploss_amount  = amount;
        m_stoploss_percent = percent;
        m_max_loss_amount  = max_loss;
        m_wait_after_loss  = wait_seconds;
        m_stop_after_loss  = stop_after;
    }

    //+--------------------------------------------------------------+
    //| Calcula o saldo efetivo do robô (quanto pode usar)           |
    //+--------------------------------------------------------------+
    double GetRobotBalance() {
        double balance = 0.0;

        switch(m_balance_mode) {
            case BAL_FULL_ACCOUNT:
                balance = AccountInfoDouble(ACCOUNT_BALANCE);
                break;
            case BAL_PERCENTAGE:
                balance = AccountInfoDouble(ACCOUNT_BALANCE) * m_balance_percentage / 100.0;
                break;
            case BAL_FIXED_VALUE:
                balance = m_fixed_balance;
                break;
        }

        // Aplica teto se configurado
        if(m_max_balance > 0.0 && balance > m_max_balance)
            balance = m_max_balance;

        m_last_robot_balance = balance;
        m_last_calc_time = TimeCurrent();
        return balance;
    }

    //+--------------------------------------------------------------+
    //| Calcula o multiplicador de preset                             |
    //| Retorna fator pelo qual multiplicar os lotes do preset        |
    //| Exemplo: preset base = 1200 USD, saldo = 2400 → mult = 2.0  |
    //+--------------------------------------------------------------+
    double GetPresetMultiplier() {
        if(m_preset_mode == PRESET_DISABLED || m_preset_factor <= 0.0)
            return 1.0;

        double reference = 0.0;
        switch(m_preset_mode) {
            case PRESET_BY_BALANCE:
                reference = GetRobotBalance();
                break;
            case PRESET_BY_EQUITY:
                reference = AccountInfoDouble(ACCOUNT_EQUITY);
                break;
            default:
                return 1.0;
        }

        // Converte para moeda de referência se necessário
        reference /= m_currency_rate;

        double mult = reference / m_preset_factor;

        // Mínimo x0.01 (nunca zero)
        if(mult < 0.01) mult = 0.01;

        return mult;
    }

    //+--------------------------------------------------------------+
    //| Calcula lote ajustado pelo Money Manager                     |
    //| base_lot: lote base do preset/configuração                   |
    //| Retorna: lote ajustado pelo multiplicador                    |
    //+--------------------------------------------------------------+
    double CalculateAdjustedLot(double base_lot) {
        double mult = GetPresetMultiplier();
        return NormalizeDouble(base_lot * mult, 2);
    }

    //+--------------------------------------------------------------+
    //| Verifica se o StopLoss do Money Manager foi atingido         |
    //| Retorna true se deve PARAR de operar                         |
    //+--------------------------------------------------------------+
    bool IsStopLossHit() {
        double robot_balance = GetRobotBalance();

        // StopLoss por valor absoluto
        if(m_stoploss_amount > 0.0) {
            double equity = AccountInfoDouble(ACCOUNT_EQUITY);
            double loss = robot_balance - equity;
            if(loss >= m_stoploss_amount) {
                m_logger.Critical("MoneyMgr",
                    StringFormat("🚨 StopLoss $: Perda=R$%.2f (máx=R$%.2f)",
                                 loss, m_stoploss_amount));
                return true;
            }
        }

        // StopLoss por porcentagem
        if(m_stoploss_percent > 0.0 && robot_balance > 0.0) {
            double equity = AccountInfoDouble(ACCOUNT_EQUITY);
            double dd_pct = ((robot_balance - equity) / robot_balance) * 100.0;
            if(dd_pct >= m_stoploss_percent) {
                m_logger.Critical("MoneyMgr",
                    StringFormat("🚨 StopLoss %%: DD=%.1f%% (máx=%.1f%%)",
                                 dd_pct, m_stoploss_percent));
                return true;
            }
        }

        // Prejuízo atual máximo
        if(m_max_loss_amount > 0.0 && MathAbs(m_current_loss) >= m_max_loss_amount) {
            m_logger.Warning("MoneyMgr",
                StringFormat("Prejuízo atual: R$%.2f (máx=R$%.2f)",
                             m_current_loss, m_max_loss_amount));
            return true;
        }

        return false;
    }

    //+--------------------------------------------------------------+
    //| Atualiza o prejuízo atual acumulado                          |
    //+--------------------------------------------------------------+
    void UpdateCurrentLoss(double loss) {
        m_current_loss = loss;
    }

    //+--------------------------------------------------------------+
    //| Reseta o acumulador de perda (novo ciclo/dia)                |
    //+--------------------------------------------------------------+
    void ResetCurrentLoss() {
        m_current_loss = 0.0;
    }

    //+--------------------------------------------------------------+
    //| Retorna informações para o dashboard                         |
    //+--------------------------------------------------------------+
    string GetStatusString() {
        return StringFormat("Saldo Robô: R$%.2f | xPreset: %.2fx | Moeda: %.2f",
                           m_last_robot_balance, GetPresetMultiplier(), m_currency_rate);
    }
};

//+------------------------------------------------------------------+
