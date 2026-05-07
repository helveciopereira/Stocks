//+------------------------------------------------------------------+
//|                                                  TimeFilter.mqh  |
//|               Omni-B3 EA v1.1 — Filtro de Horário (B3)           |
//|          Horário da B3: 9:00 - 17:55 (horário de Brasília)       |
//+------------------------------------------------------------------+
#property copyright "Projeto Omni-B3"
#property link      "https://github.com/helveciopereira/Stocks"
#property version   "1.10"
#property strict

#include "Defines.mqh"
#include "Logger.mqh"

//+------------------------------------------------------------------+
//| Filtro de horário adaptado para B3                               |
//| Pregão regular: 9:00 - 17:55 (BRT)                              |
//| Minicontratos: 9:00 - 17:55 (com leilão de fechamento)          |
//+------------------------------------------------------------------+
class CTimeFilter {
private:
    int      m_start_hour;
    int      m_start_minute;
    int      m_end_hour;
    int      m_end_minute;
    bool     m_friday_early_close;   // Fechar mais cedo na sexta
    int      m_friday_end_hour;
    bool     m_use_server_time;
    CLogger *m_logger;

public:
    CTimeFilter(int start_hour, int start_minute,
                int end_hour, int end_minute,
                bool friday_early, int friday_end_hour,
                bool use_server_time, CLogger *logger) {

        m_start_hour        = start_hour;
        m_start_minute      = start_minute;
        m_end_hour          = end_hour;
        m_end_minute        = end_minute;
        m_friday_early_close = friday_early;
        m_friday_end_hour   = friday_end_hour;
        m_use_server_time   = use_server_time;
        m_logger            = logger;

        m_logger.Info("TimeFilter",
            StringFormat("Init: Janela=%02d:%02d-%02d:%02d | SextaAntecip=%s(%02d:00)",
                         m_start_hour, m_start_minute, m_end_hour, m_end_minute,
                         m_friday_early_close ? "Sim" : "Não", m_friday_end_hour));
    }

    //+--------------------------------------------------------------+
    //| Verifica se estamos dentro do horário de operação             |
    //+--------------------------------------------------------------+
    bool IsTradeAllowed() {
        MqlDateTime now;
        if(m_use_server_time)
            TimeCurrent(now);
        else
            TimeLocal(now);

        int day_week = now.day_of_week;
        int current_minutes = now.hour * 60 + now.min;

        // Fim de semana — B3 não opera
        if(day_week == 0 || day_week == 6) return false;

        // Sexta-feira: fechamento antecipado
        if(m_friday_early_close && day_week == 5) {
            int friday_end = m_friday_end_hour * 60;
            if(current_minutes >= friday_end) return false;
        }

        // Janela de horário do pregão
        int start_minutes = m_start_hour * 60 + m_start_minute;
        int end_minutes   = m_end_hour * 60 + m_end_minute;

        if(current_minutes < start_minutes || current_minutes >= end_minutes) {
            return false;
        }

        return true;
    }

    string GetStatus() {
        return StringFormat("Janela: %02d:%02d-%02d:%02d | Aberto: %s",
                           m_start_hour, m_start_minute, m_end_hour, m_end_minute,
                           IsTradeAllowed() ? "✅ SIM" : "❌ NÃO");
    }
};

//+------------------------------------------------------------------+
