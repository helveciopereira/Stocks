//+------------------------------------------------------------------+
//|                                                  TimeFilter.mqh  |
//|               Omni-B3 EA v2.47 â€” Filtro de HorÃ¡rio (B3)          |
//|       Dias permitidos, reduÃ§Ã£o por tempo, criaÃ§Ã£o de pendentes   |
//+------------------------------------------------------------------+
//| Copyright 2026, Projeto Omni-B3                                 |
//| https://github.com/helveciopereira/Stocks                        |
//+------------------------------------------------------------------+
#property copyright "Projeto Omni-B3"
#property link      "https://github.com/helveciopereira/Stocks"
#property version   "2.47"
#property strict

#include "Defines.mqh"
#include "Logger.mqh"

//+------------------------------------------------------------------+
//| Filtro de horÃ¡rio adaptado para B3 â€” v2.0                        |
//|                                                                   |
//| Melhorias inspiradas no ToTheMoon v3.5:                           |
//| - Dias da semana permitidos (configurÃ¡vel por dia)               |
//| - Hora de mudar dia (para cÃ¡lculos de P&L diÃ¡rio)               |
//| - Modo de fechamento no horÃ¡rio limite                           |
//| - ReduÃ§Ã£o de TakeProfit por tempo                                |
//| - Tempo restante para logs e dashboard                           |
//|                                                                   |
//| PregÃ£o B3: 9:00 - 17:55 (BRT) para minicontratos                |
//+------------------------------------------------------------------+
class CTimeFilter {
private:
    int      m_start_hour;
    int      m_start_minute;
    int      m_end_hour;
    int      m_end_minute;
    bool     m_friday_early_close;   // Fechar mais cedo na sexta
    int      m_friday_end_hour;
    bool     m_use_server_time;      // Usar hora do servidor vs local

    // Dias da semana permitidos
    bool     m_allow_sunday;
    bool     m_allow_monday;
    bool     m_allow_tuesday;
    bool     m_allow_wednesday;
    bool     m_allow_thursday;
    bool     m_allow_friday;
    bool     m_allow_saturday;

    // Hora de mudar dia (para cÃ¡lculos diÃ¡rios)
    int      m_day_change_hour;
    int      m_day_change_minute;

    // Modo de fechamento no horÃ¡rio limite
    ENUM_TIME_CLOSE_MODE m_close_mode;

    // ReduÃ§Ã£o de TakeProfit por tempo (minutos antes do fim)
    int      m_reduce_minutes;       // Quantos minutos antes do fim comeÃ§ar
    ENUM_TIME_REDUCE_TYPE m_reduce_type; // O que reduzir

    // Estado
    bool     m_was_inside;           // Se estava dentro do horÃ¡rio no tick anterior
    bool     m_close_executed;       // Se fechamento de fim de horÃ¡rio jÃ¡ executou

    CLogger *m_logger;

    //+--------------------------------------------------------------+
    //| ObtÃ©m hora atual (local ou servidor)                          |
    //+--------------------------------------------------------------+
    void GetCurrentTime(MqlDateTime &now) {
        if(m_use_server_time)
            TimeCurrent(now);
        else
            TimeLocal(now);
    }

    //+--------------------------------------------------------------+
    //| Verifica se dia da semana estÃ¡ permitido                      |
    //+--------------------------------------------------------------+
    bool IsDayAllowed(int day_of_week) {
        switch(day_of_week) {
            case 0: return m_allow_sunday;
            case 1: return m_allow_monday;
            case 2: return m_allow_tuesday;
            case 3: return m_allow_wednesday;
            case 4: return m_allow_thursday;
            case 5: return m_allow_friday;
            case 6: return m_allow_saturday;
            default: return false;
        }
    }

public:
    //+--------------------------------------------------------------+
    //| Construtor                                                    |
    //+--------------------------------------------------------------+
    CTimeFilter(int start_hour, int start_minute,
                int end_hour, int end_minute,
                bool friday_early, int friday_end_hour,
                bool use_server_time, CLogger *logger) {

        m_start_hour         = start_hour;
        m_start_minute       = start_minute;
        m_end_hour           = end_hour;
        m_end_minute         = end_minute;
        m_friday_early_close = friday_early;
        m_friday_end_hour    = friday_end_hour;
        m_use_server_time    = use_server_time;
        m_logger             = logger;

        // B3 nÃ£o opera fim de semana
        m_allow_sunday    = false;
        m_allow_monday    = true;
        m_allow_tuesday   = true;
        m_allow_wednesday = true;
        m_allow_thursday  = true;
        m_allow_friday    = true;
        m_allow_saturday  = false;

        m_day_change_hour   = 0;
        m_day_change_minute = 0;

        m_close_mode      = TCLOSE_NONE;
        m_reduce_minutes  = 0;
        m_reduce_type     = TIME_REDUCE_NONE;

        m_was_inside      = false;
        m_close_executed  = false;

        m_logger.Info("TimeFilter",
            StringFormat("Init: Janela=%02d:%02d-%02d:%02d | SextaAntecip=%s(%02d:00) | Hora=%s",
                         m_start_hour, m_start_minute, m_end_hour, m_end_minute,
                         m_friday_early_close ? "Sim" : "NÃ£o", m_friday_end_hour,
                         m_use_server_time ? "Servidor" : "Local"));
    }

    //+--------------------------------------------------------------+
    //| Configura dias permitidos                                     |
    //+--------------------------------------------------------------+
    void SetAllowedDays(bool sun, bool mon, bool tue, bool wed,
                        bool thu, bool fri, bool sat) {
        m_allow_sunday    = sun;
        m_allow_monday    = mon;
        m_allow_tuesday   = tue;
        m_allow_wednesday = wed;
        m_allow_thursday  = thu;
        m_allow_friday    = fri;
        m_allow_saturday  = sat;
    }

    //+--------------------------------------------------------------+
    //| Configura hora de mudar dia                                   |
    //+--------------------------------------------------------------+
    void SetDayChangeTime(int hour, int minute) {
        m_day_change_hour = hour;
        m_day_change_minute = minute;
    }

    //+--------------------------------------------------------------+
    //| Configura modo de fechamento no horÃ¡rio                      |
    //+--------------------------------------------------------------+
    void SetCloseMode(ENUM_TIME_CLOSE_MODE mode) {
        m_close_mode = mode;
    }

    //+--------------------------------------------------------------+
    //| Configura reduÃ§Ã£o de TP por tempo                             |
    //+--------------------------------------------------------------+
    void SetTimeReduction(int minutes_before_end, ENUM_TIME_REDUCE_TYPE type) {
        m_reduce_minutes = minutes_before_end;
        m_reduce_type = type;
    }

    //+--------------------------------------------------------------+
    //| Verifica se estamos dentro do horÃ¡rio de operaÃ§Ã£o             |
    //+--------------------------------------------------------------+
    bool IsTradeAllowed() {
        MqlDateTime now;
        GetCurrentTime(now);

        int day_week = now.day_of_week;
        int current_minutes = now.hour * 60 + now.min;

        // Dia da semana permitido?
        if(!IsDayAllowed(day_week)) return false;

        // Sexta-feira: fechamento antecipado
        if(m_friday_early_close && day_week == 5) {
            int friday_end = m_friday_end_hour * 60;
            if(current_minutes >= friday_end) return false;
        }

        // Janela de horÃ¡rio do pregÃ£o
        int start_minutes = m_start_hour * 60 + m_start_minute;
        int end_minutes   = m_end_hour * 60 + m_end_minute;

        bool is_inside = (current_minutes >= start_minutes && current_minutes < end_minutes);

        // Detecta transiÃ§Ã£o de dentro â†’ fora (apenas log)
        if(m_was_inside && !is_inside) {
            m_logger.Info("TimeFilter", "â° Fim do horÃ¡rio de operaÃ§Ã£o");
        }
        // Reseta flag quando volta para dentro do horÃ¡rio (no dia seguinte ou ao reativar)
        if(is_inside && !m_was_inside) {
            m_close_executed = false;
            m_logger.Info("TimeFilter", "â° InÃ­cio do horÃ¡rio de operaÃ§Ã£o. Resetando controle de fechamento.");
        }

        m_was_inside = is_inside;
        return is_inside;
    }

    //+--------------------------------------------------------------+
    //| Verifica se deve fechar no fim do horÃ¡rio                    |
    //| Retorna true se deve fechar AGORA                            |
    //+--------------------------------------------------------------+
    bool ShouldCloseOnTime() {
        if(m_close_mode == TCLOSE_NONE) return false;

        MqlDateTime now;
        GetCurrentTime(now);
        int current_minutes = now.hour * 60 + now.min;
        int end_minutes = m_end_hour * 60 + m_end_minute;

        // Na sexta, usa horÃ¡rio antecipado
        if(m_friday_early_close && now.day_of_week == 5)
            end_minutes = m_friday_end_hour * 60;

        // Chegou no horÃ¡rio de fechar?
        if(current_minutes >= end_minutes && !m_close_executed) {
            m_close_executed = true; // Define como executado imediatamente para evitar mÃºltiplos fechamentos no mesmo dia
            m_logger.Info("TimeFilter", "â° HorÃ¡rio limite atingido. Disparando fechamento forÃ§ado.");
            return true;
        }
        return false;
    }

    //+--------------------------------------------------------------+
    //| Verifica se estamos no perÃ­odo de reduÃ§Ã£o de TP              |
    //| Retorna fator de reduÃ§Ã£o (1.0 = sem reduÃ§Ã£o, 0.1 = mÃ­nimo)  |
    //+--------------------------------------------------------------+
    double GetTPReductionFactor() {
        if(m_reduce_minutes <= 0 || m_reduce_type == TIME_REDUCE_NONE) return 1.0;

        MqlDateTime now;
        GetCurrentTime(now);
        int current_minutes = now.hour * 60 + now.min;
        int end_minutes = m_end_hour * 60 + m_end_minute;

        if(m_friday_early_close && now.day_of_week == 5)
            end_minutes = m_friday_end_hour * 60;

        int remaining = end_minutes - current_minutes;
        if(remaining > m_reduce_minutes) return 1.0;  // Ainda nÃ£o Ã© hora
        if(remaining <= 0) return 0.1;  // MÃ­nimo

        // ReduÃ§Ã£o linear
        double factor = (double)remaining / (double)m_reduce_minutes;
        if(factor < 0.1) factor = 0.1;
        return factor;
    }

    //+--------------------------------------------------------------+
    //| Retorna tipo de reduÃ§Ã£o ativo                                 |
    //+--------------------------------------------------------------+
    ENUM_TIME_REDUCE_TYPE GetReduceType() { return m_reduce_type; }

    //+--------------------------------------------------------------+
    //| Retorna modo de fechamento no horÃ¡rio                        |
    //+--------------------------------------------------------------+
    ENUM_TIME_CLOSE_MODE GetCloseMode() { return m_close_mode; }

    //+--------------------------------------------------------------+
    //| Retorna minutos restantes atÃ© fim do pregÃ£o                  |
    //+--------------------------------------------------------------+
    int GetRemainingMinutes() {
        MqlDateTime now;
        GetCurrentTime(now);
        int current_minutes = now.hour * 60 + now.min;
        int end_minutes = m_end_hour * 60 + m_end_minute;

        if(m_friday_early_close && now.day_of_week == 5)
            end_minutes = m_friday_end_hour * 60;

        return end_minutes - current_minutes;
    }

    //+--------------------------------------------------------------+
    //| Status para dashboard                                         |
    //+--------------------------------------------------------------+
    string GetStatus() {
        int remaining = GetRemainingMinutes();
        double reduction = GetTPReductionFactor();
        return StringFormat("Janela: %02d:%02d-%02d:%02d | %s | Restam: %dmin%s",
                           m_start_hour, m_start_minute, m_end_hour, m_end_minute,
                           IsTradeAllowed() ? "âœ… ABERTO" : "âŒ FECHADO",
                           remaining > 0 ? remaining : 0,
                           reduction < 1.0 ? StringFormat(" | Red=%.0f%%", reduction * 100) : "");
    }
};

//+------------------------------------------------------------------+
