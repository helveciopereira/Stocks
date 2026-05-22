//+------------------------------------------------------------------+
//|                                                      Logger.mqh  |
//|                         Omni-B3 EA v2.45 — Sistema de Logging     |
//|             Logging estruturado com níveis e saída formatada      |
//+------------------------------------------------------------------+
#property copyright "Projeto Omni-B3"
#property link      "https://github.com/helveciopereira/Stocks"
#property version   "2.45"
#property strict

#include "Defines.mqh"

//+------------------------------------------------------------------+
//| Classe responsável pelo sistema de logging do EA                 |
//| Centraliza todas as mensagens com formatação padronizada,        |
//| filtro por nível de verbosidade e output para Print() e arquivo. |
//+------------------------------------------------------------------+
class CLogger {
private:
    ENUM_LOG_LEVEL m_min_level;     // Nível mínimo para exibir mensagens
    bool           m_file_enabled;  // Se deve salvar logs em arquivo
    string         m_file_name;     // Nome do arquivo de log
    int            m_file_handle;   // Handle do arquivo aberto
    int            m_message_count; // Contador de mensagens (para diagnóstico)

    //+--------------------------------------------------------------+
    //| Converte o enum de nível para string legível em PT-BR        |
    //+--------------------------------------------------------------+
    string LevelToString(ENUM_LOG_LEVEL level) {
        switch(level) {
            case LOG_DEBUG:    return "DEBUG";
            case LOG_INFO:     return "INFO";
            case LOG_WARNING:  return "AVISO";
            case LOG_ERROR:    return "ERRO";
            case LOG_CRITICAL: return "CRÍTICO";
            default:           return "???";
        }
    }

    //+--------------------------------------------------------------+
    //| Formata a mensagem com timestamp, nível e módulo              |
    //+--------------------------------------------------------------+
    string FormatMessage(ENUM_LOG_LEVEL level, string module, string message) {
        // Formato: [2026.05.07 15:30:45][INFO][GridEngine] Mensagem aqui
        return StringFormat("[%s][%s][%s] %s",
                           TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
                           LevelToString(level),
                           module,
                           message);
    }

    //+--------------------------------------------------------------+
    //| Escreve a mensagem no arquivo de log (se habilitado)         |
    //+--------------------------------------------------------------+
    void WriteToFile(string formatted_message) {
        if(!m_file_enabled) return;

        // Abre o arquivo se ainda não estiver aberto
        if(m_file_handle == INVALID_HANDLE) {
            m_file_handle = FileOpen(m_file_name,
                FILE_WRITE | FILE_READ | FILE_TXT | FILE_SHARE_READ | FILE_ANSI);
            if(m_file_handle == INVALID_HANDLE) {
                // Se não conseguir abrir, desabilita para evitar tentativas repetidas
                m_file_enabled = false;
                Print("Logger: FALHA ao abrir arquivo de log: ", m_file_name);
                return;
            }
            // Move cursor para o final do arquivo (append)
            FileSeek(m_file_handle, 0, SEEK_END);
        }

        // Escreve a linha com quebra de linha
        FileWriteString(m_file_handle, formatted_message + "\n");
        FileFlush(m_file_handle);
    }

public:
    //+--------------------------------------------------------------+
    //| Construtor — configura nível mínimo e opção de arquivo       |
    //+--------------------------------------------------------------+
    CLogger(ENUM_LOG_LEVEL min_level = LOG_INFO, bool enable_file = false) {
        m_min_level     = min_level;
        m_file_enabled  = enable_file;
        m_file_handle   = INVALID_HANDLE;
        m_message_count = 0;

        // Gera nome do arquivo com data para rotação diária
        m_file_name = StringFormat("OmniB3_Log_%s.txt",
                                   TimeToString(TimeCurrent(), TIME_DATE));
        // Substitui pontos por underscores no nome do arquivo
        StringReplace(m_file_name, ".", "_");
    }

    //+--------------------------------------------------------------+
    //| Destrutor — fecha arquivo de log se estiver aberto           |
    //+--------------------------------------------------------------+
    ~CLogger() {
        if(m_file_handle != INVALID_HANDLE) {
            FileClose(m_file_handle);
        }
    }

    //+--------------------------------------------------------------+
    //| Método principal de logging — filtra por nível e despacha    |
    //+--------------------------------------------------------------+
    void Log(ENUM_LOG_LEVEL level, string module, string message) {
        // Ignora mensagens abaixo do nível mínimo configurado
        if(level < m_min_level) return;

        string formatted = FormatMessage(level, module, message);
        m_message_count++;

        // Sempre imprime no terminal do MT5 (aba Experts)
        Print(formatted);

        // Opcionalmente salva em arquivo
        WriteToFile(formatted);
    }

    //+--------------------------------------------------------------+
    //| Atalhos de conveniência para cada nível de log               |
    //+--------------------------------------------------------------+

    // Mensagens de depuração detalhadas (ex: valores de variáveis)
    void Debug(string module, string message)    { Log(LOG_DEBUG, module, message); }

    // Informações operacionais normais (ex: "Ordem aberta com sucesso")
    void Info(string module, string message)     { Log(LOG_INFO, module, message); }

    // Situações anormais mas não críticas (ex: "Spread alto, aguardando")
    void Warning(string module, string message)  { Log(LOG_WARNING, module, message); }

    // Falhas que impedem uma operação (ex: "Erro ao enviar ordem")
    void Error(string module, string message)    { Log(LOG_ERROR, module, message); }

    // Falhas graves que exigem ação imediata (ex: "Equity abaixo do limite")
    void Critical(string module, string message) { Log(LOG_CRITICAL, module, message); }

    //+--------------------------------------------------------------+
    //| Altera o nível mínimo de log em tempo de execução            |
    //+--------------------------------------------------------------+
    void SetLevel(ENUM_LOG_LEVEL level) {
        m_min_level = level;
    }

    //+--------------------------------------------------------------+
    //| Retorna o total de mensagens logadas nesta sessão             |
    //+--------------------------------------------------------------+
    int GetMessageCount() { return m_message_count; }
};

//+------------------------------------------------------------------+
