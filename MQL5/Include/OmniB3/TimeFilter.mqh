//+------------------------------------------------------------------+
//|                                                  TimeFilter.mqh  |
//|                  Omni-B3 EA v1.0 — Filtro de Horário             |
//|     Controle de janelas de operação e bloqueios temporais        |
//+------------------------------------------------------------------+
#property copyright "Projeto Omni-B3"
#property link      "https://github.com/seu-usuario/Stocks"
#property version   "1.00"
#property strict

#include "Defines.mqh"
#include "Logger.mqh"

//+------------------------------------------------------------------+
//| Classe de Filtro Temporal para operações                         |
//|                                                                   |
//| Controla QUANDO o EA pode abrir novas posições:                  |
//|  - Janela de horário (hora início / hora fim)                    |
//|  - Bloqueio de sexta-feira (evita manter posições no fim de semana)|
//|  - Delay de segunda-feira (evita gaps de abertura)               |
//|  - Bloqueio em dias específicos                                  |
//+------------------------------------------------------------------+
class CTimeFilter {
private:
    int      m_start_hour;           // Hora de início permitida (0-23)
    int      m_end_hour;             // Hora de fim permitida (0-23)
    bool     m_friday_block;         // Se bloqueia novas ordens na sexta
    int      m_friday_block_hour;    // Hora a partir da qual bloqueia na sexta
    bool     m_monday_delay;         // Se aplica delay na segunda
    int      m_monday_start_hour;    // Hora que libera operações na segunda
    bool     m_use_server_time;      // true=hora do servidor, false=hora local
    CLogger *m_logger;               // Sistema de logging

public:
    //+--------------------------------------------------------------+
    //| Construtor com configuração de horários                      |
    //+--------------------------------------------------------------+
    CTimeFilter(int start_hour, int end_hour,
                bool friday_block, int friday_block_hour,
                bool monday_delay, int monday_start_hour,
                bool use_server_time,
                CLogger *logger) {

        m_start_hour        = start_hour;
        m_end_hour          = end_hour;
        m_friday_block      = friday_block;
        m_friday_block_hour = friday_block_hour;
        m_monday_delay      = monday_delay;
        m_monday_start_hour = monday_start_hour;
        m_use_server_time   = use_server_time;
        m_logger            = logger;

        m_logger.Info("TimeFilter",
            StringFormat("Inicializado: Janela=%02d:00-%02d:00 | SextaBlock=%s(%02d:00) | SegDelay=%s(%02d:00)",
                         m_start_hour, m_end_hour,
                         m_friday_block ? "Sim" : "Não", m_friday_block_hour,
                         m_monday_delay ? "Sim" : "Não", m_monday_start_hour));
    }

    //+--------------------------------------------------------------+
    //| Verifica se o horário atual permite abertura de novas ordens |
    //| Retorna: true se estamos dentro da janela de operação        |
    //+--------------------------------------------------------------+
    bool IsTradeAllowed() {
        MqlDateTime now;

        // Usa hora do servidor (TimeCurrent) ou hora local
        if(m_use_server_time)
            TimeCurrent(now);
        else
            TimeLocal(now);

        int hour     = now.hour;
        int day_week = now.day_of_week; // 0=Dom, 1=Seg, ..., 5=Sex, 6=Sáb

        // BLOQUEIO: Fim de semana (sábado e domingo)
        if(day_week == 0 || day_week == 6) {
            return false;
        }

        // BLOQUEIO: Sexta-feira após horário configurado
        // Evita abrir grades que podem sofrer gap no fim de semana
        if(m_friday_block && day_week == 5 && hour >= m_friday_block_hour) {
            m_logger.Debug("TimeFilter", "Bloqueio de sexta-feira ativo");
            return false;
        }

        // BLOQUEIO: Segunda-feira antes do horário configurado
        // Evita abrir posições durante possíveis gaps de abertura
        if(m_monday_delay && day_week == 1 && hour < m_monday_start_hour) {
            m_logger.Debug("TimeFilter", "Delay de segunda-feira ativo");
            return false;
        }

        // VERIFICAÇÃO: Janela de horário
        // Suporta janelas que cruzam a meia-noite (ex: 22:00 - 06:00)
        if(m_start_hour < m_end_hour) {
            // Janela normal (ex: 01:00 - 23:00)
            if(hour < m_start_hour || hour >= m_end_hour) {
                return false;
            }
        } else if(m_start_hour > m_end_hour) {
            // Janela que cruza meia-noite (ex: 22:00 - 06:00)
            if(hour < m_start_hour && hour >= m_end_hour) {
                return false;
            }
        }
        // Se start == end, opera 24h (sem filtro de horário)

        return true;
    }

    //+--------------------------------------------------------------+
    //| Retorna string com status do filtro para display/log         |
    //+--------------------------------------------------------------+
    string GetStatus() {
        return StringFormat("Janela: %02d:00-%02d:00 | Permitido: %s",
                           m_start_hour, m_end_hour,
                           IsTradeAllowed() ? "✅ SIM" : "❌ NÃO");
    }
};

//+------------------------------------------------------------------+
