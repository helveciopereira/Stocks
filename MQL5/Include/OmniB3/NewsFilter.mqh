﻿//+------------------------------------------------------------------+
//|                                                   NewsFilter.mqh |
//|                     Omni-B3 EA v2.48 — Filtro de Notícias Nativo  |
//|  Proteção contra Alta Volatilidade de Calendário Econômico do MT5 |
//|  Verifica eventos próximos e bloqueia abertura/execução do EA    |
//+------------------------------------------------------------------+
//| Copyright 2026, Projeto Omni-B3                                 |
//| https://github.com/helveciopereira/Stocks                        |
//+------------------------------------------------------------------+
#property copyright "Projeto Omni-B3"
#property link      "https://github.com/helveciopereira/Stocks"
#property version     "2.48"
#property strict

#include <OmniB3/Defines.mqh>
#include <OmniB3/Logger.mqh>

//+------------------------------------------------------------------+
//| CLASSE CNewsFilter                                               |
//| Gerencia o calendário econômico integrado do MT5 para a B3       |
//+------------------------------------------------------------------+
class CNewsFilter {
private:
    bool                 m_enabled;          // Filtro ativado?
    ENUM_NEWS_IMPORTANCE m_min_importance;   // Importância mínima para filtrar
    ENUM_NEWS_ACTION     m_action;           // Ação tomada durante o bloqueio
    int                  m_minutes_before;   // Minutos para bloquear antes do evento
    int                  m_minutes_after;    // Minutos para bloquear após o evento
    string               m_currency_filter;  // Moeda filtrada ("BRL", "USD", "ALL")
    
    // Estado de notícias carregado
    MqlCalendarValue     m_values[];         // Valores dos eventos carregados
    int                  m_total_events;     // Quantidade total de eventos carregados
    datetime             m_last_update_date; // Data da última atualização de dados

    // Estrutura para guardar a próxima notícia mais próxima
    SNewsState           m_next_news;
    
    CLogger             *m_logger;           // Ponteiro para o Logger centralizado

    // Auxiliares internos de filtragem
    bool                 IsEventRelevant(const MqlCalendarValue &value, const MqlCalendarEvent &event, const MqlCalendarCountry &country);

public:
                         CNewsFilter();
                        ~CNewsFilter();

    // Inicialização
    void                 Init(CLogger *logger,
                              bool enabled, 
                              ENUM_NEWS_IMPORTANCE min_imp, 
                              ENUM_NEWS_ACTION action, 
                              int min_before, 
                              int min_after, 
                              string currency);

    // Carrega/atualiza os dados de calendário do dia
    bool                 UpdateCalendarData();

    // Verifica se o robô está em período de bloqueio por notícia
    // Retorna true se houver bloqueio ativo e preenche a ação correspondente
    bool                 CheckNewsBlock(datetime current_time, int &out_action);

    // Retorna a struct de estado da próxima notícia mais próxima
    SNewsState           GetNextNewsState() const { return m_next_news; }
};

//+------------------------------------------------------------------+
//| Construtor                                                       |
//+------------------------------------------------------------------+
CNewsFilter::CNewsFilter() {
    m_enabled          = false;
    m_min_importance   = NEWS_IMPORTANCE_NONE;
    m_action           = NEWS_ACTION_NONE;
    m_minutes_before   = 15;
    m_minutes_after    = 15;
    m_currency_filter  = "BRL";
    m_total_events     = 0;
    m_last_update_date = 0;
    m_logger           = NULL;
    m_next_news.Clear();
}

//+------------------------------------------------------------------+
//| Destrutor                                                        |
//+------------------------------------------------------------------+
CNewsFilter::~CNewsFilter() {
}

//+------------------------------------------------------------------+
//| Inicialização                                                    |
//+------------------------------------------------------------------+
void CNewsFilter::Init(CLogger *logger,
                        bool enabled, 
                        ENUM_NEWS_IMPORTANCE min_imp, 
                        ENUM_NEWS_ACTION action, 
                        int min_before, 
                        int min_after, 
                        string currency) {
    m_logger          = logger;
    m_enabled         = enabled;
    m_min_importance  = min_imp;
    m_action          = action;
    m_minutes_before  = min_before;
    m_minutes_after   = min_after;
    m_currency_filter = currency;
    
    // Deixa em maiúsculo para comparação segura
    StringToUpper(m_currency_filter);
    
    m_next_news.Clear();

    if(m_enabled) {
        if(m_logger != NULL) {
            m_logger.Info("NewsFilter", StringFormat("Filtro de Noticias Inicializado: Moeda=%s, Importancia Minima=%d, Bloqueio=%dmin antes e %dmin depois.", 
                                      m_currency_filter, m_min_importance, m_minutes_before, m_minutes_after));
        }
        UpdateCalendarData();
    }
}

//+------------------------------------------------------------------+
//| Carrega as Notícias do Dia do Calendário Nativo do MT5            |
//+------------------------------------------------------------------+
bool CNewsFilter::UpdateCalendarData() {
    if(!m_enabled) return false;

    datetime today = TimeCurrent();
    // Zera horas, minutos e segundos para pegar do início do dia
    MqlDateTime dt;
    TimeToStruct(today, dt);
    dt.hour = 0;
    dt.min = 0;
    dt.sec = 0;
    datetime start_of_day = StructToTime(dt);

    // Se já atualizamos hoje e temos dados, não precisa recarregar toda hora
    if(m_last_update_date == start_of_day && m_total_events > 0) {
        return true;
    }

    // Período de busca: de hoje até o final do dia
    datetime end_of_day = start_of_day + 86400;

    // Busca o histórico de notícias nativo do terminal
    m_total_events = CalendarValueHistory(m_values, start_of_day, end_of_day);
    
    if(m_total_events > 0) {
        m_last_update_date = start_of_day;
        if(m_logger != NULL) {
            m_logger.Info("NewsFilter", StringFormat("Carregados %d eventos do dia de hoje.", m_total_events));
        }
        return true;
    } else {
        if(m_logger != NULL) {
            m_logger.Warning("NewsFilter", "Nenhum evento carregado do calendario do MT5. Verifique a conexao do terminal ou se a aba Calendario esta ativa.");
        }
        return false;
    }
}

//+------------------------------------------------------------------+
//| Verifica se um evento do calendário é relevante para o EA        |
//+------------------------------------------------------------------+
bool CNewsFilter::IsEventRelevant(const MqlCalendarValue &value, const MqlCalendarEvent &event, const MqlCalendarCountry &country) {
    // 1. Filtragem por Moeda
    string currency = country.currency;
    StringToUpper(currency);

    if(m_currency_filter != "ALL") {
        if(currency != m_currency_filter) {
            // Se filtramos WIN/WDO, USD e BRL são as moedas relevantes globais
            if(m_currency_filter == "BRL" && currency != "BRL" && currency != "USD") {
                return false;
            }
            else if(m_currency_filter != "BRL" && currency != m_currency_filter) {
                return false;
            }
        }
    }

    // 2. Filtragem por nível de importância (impacto da notícia)
    ENUM_CALENDAR_EVENT_IMPORTANCE imp = event.importance;
    
    if(m_min_importance == NEWS_IMPORTANCE_HIGH) {
        if(imp != CALENDAR_IMPORTANCE_HIGH) return false;
    }
    else if(m_min_importance == NEWS_IMPORTANCE_MEDIUM) {
        if(imp != CALENDAR_IMPORTANCE_MODERATE && imp != CALENDAR_IMPORTANCE_HIGH) return false;
    }
    else if(m_min_importance == NEWS_IMPORTANCE_LOW) {
        if(imp == CALENDAR_IMPORTANCE_NONE) return false;
    }
    else if(m_min_importance == NEWS_IMPORTANCE_NONE) {
        return false; // Desabilitado
    }

    return true;
}

//+------------------------------------------------------------------+
//| Executa a varredura e verifica se há bloqueio ativo              |
//+------------------------------------------------------------------+
bool CNewsFilter::CheckNewsBlock(datetime current_time, int &out_action) {
    out_action = (int)NEWS_ACTION_NONE;
    if(!m_enabled) return false;

    // Atualiza o calendário se virou o dia
    UpdateCalendarData();

    if(m_total_events <= 0) return false;

    bool is_blocked = false;
    m_next_news.Clear();
    int closest_seconds_to = 9999999; // Valor muito alto inicial

    // Varre todas as notícias do dia carregadas
    for(int i = 0; i < m_total_events; i++) {
        MqlCalendarEvent event;
        MqlCalendarCountry country;
        
        // Pega detalhes do evento e do país correspondente
        if(!CalendarEventById(m_values[i].event_id, event)) continue;
        if(!CalendarCountryById(event.country_id, country)) continue;

        // Verifica se é relevante
        if(!IsEventRelevant(m_values[i], event, country)) continue;

        datetime event_time = m_values[i].time;
        
        // Se a notícia ainda não tem horário definido (ex: dia inteiro)
        if(event_time == 0) continue;

        // Calcula a diferença em segundos para o evento
        int seconds_to = (int)(event_time - current_time);

        // Limites de bloqueio convertidos em segundos
        int block_before_sec = m_minutes_before * 60;
        int block_after_sec  = m_minutes_after * 60;

        // Se o preço atual está dentro da janela crítica:
        // [Horário_Notícia - m_minutes_before] até [Horário_Notícia + m_minutes_after]
        if(seconds_to >= -block_after_sec && seconds_to <= block_before_sec) {
            is_blocked = true;
            out_action = (int)m_action;

            // Se for o evento ativo ou mais próximo no futuro, salva os dados
            if(seconds_to >= 0 && seconds_to < closest_seconds_to) {
                closest_seconds_to = seconds_to;
                
                m_next_news.event_name = event.name;
                m_next_news.event_time = event_time;
                m_next_news.currency   = country.currency;
                m_next_news.importance = (int)event.importance;
                m_next_news.seconds_to = seconds_to;
                m_next_news.is_active  = true;
            }
        }
        // Se ainda não bloqueou mas é o mais próximo no futuro
        else if(seconds_to > block_before_sec && seconds_to < closest_seconds_to) {
            closest_seconds_to = seconds_to;
            
            m_next_news.event_name = event.name;
            m_next_news.event_time = event_time;
            m_next_news.currency   = country.currency;
            m_next_news.importance = (int)event.importance;
            m_next_news.seconds_to = seconds_to;
            m_next_news.is_active  = false; // Ainda não bloqueado
        }
    }

    if(is_blocked) {
        if(m_logger != NULL) {
            m_logger.Warning("NewsFilter", StringFormat("Bloqueio ATIVO devido a noticia proxima: %s em %d min. Acao: %d", 
                                         m_next_news.event_name, m_next_news.seconds_to / 60, m_action));
        }
    }

    return is_blocked;
}
