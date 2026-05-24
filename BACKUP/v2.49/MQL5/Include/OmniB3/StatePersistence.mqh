//+------------------------------------------------------------------+
//|                                           StatePersistence.mqh   |
//|           Omni-B3 EA v2.49 — Persistência de Estado               |
//|     Salva/carrega estado da grade para sobreviver restarts       |
//+------------------------------------------------------------------+
//| Copyright 2026, Projeto Omni-B3                                 |
//| https://github.com/helveciopereira/Stocks                        |
//+------------------------------------------------------------------+
#property copyright "Projeto Omni-B3"
#property link      "https://github.com/helveciopereira/Stocks"
#property version   "2.49"
#property strict

#include "Defines.mqh"
#include "Logger.mqh"

//+------------------------------------------------------------------+
//| Persistência de Estado em Arquivo                                 |
//|                                                                   |
//| Problema: Em contas NETTING, a posição real é agregada (1 só).   |
//| Os níveis virtuais da grade existem apenas na memória do EA.     |
//| Se o EA reiniciar (crash, atualização, restart do terminal),     |
//| perdemos o rastreamento de todos os níveis.                       |
//|                                                                   |
//| Solução: Serializar o array de SVirtualLevel em arquivo binário  |
//| com checksum. Auto-save a cada operação e periodicamente.        |
//+------------------------------------------------------------------+
class CStatePersistence {
private:
    string   m_file_name;     // Nome do arquivo de estado
    CLogger *m_logger;
    int      m_magic_number;
    string   m_symbol;
    datetime m_last_save;     // Última vez que salvou
    int      m_save_interval; // Intervalo de auto-save em segundos
    bool     m_dirty;         // Se tem mudanças não salvas

    //+--------------------------------------------------------------+
    //| Gera nome do arquivo baseado no símbolo e magic number      |
    //+--------------------------------------------------------------+
    string GenerateFileName() {
        return StringFormat("%s%s_%d.bin",
                           PERSISTENCE_FILE_PREFIX, m_symbol, m_magic_number);
    }

    //+--------------------------------------------------------------+
    //| Calcula checksum simples para integridade dos dados          |
    //| Soma XOR de todos os bytes dos preços e volumes               |
    //+--------------------------------------------------------------+
    uint CalculateChecksum(SVirtualLevel &levels[], int count) {
        uint checksum = 0;
        for(int i = 0; i < count; i++) {
            // XOR com componentes do nível para validação
            uint price_bits = 0;
            uint vol_bits = 0;
            // Usa casting seguro via unions implícitas
            checksum ^= (uint)(levels[i].entry_price * 100000.0);
            checksum ^= (uint)(levels[i].volume * 100.0);
            checksum ^= (uint)levels[i].direction;
            checksum ^= (uint)levels[i].level_index;
            checksum ^= (uint)levels[i].open_time;
        }
        return checksum;
    }

public:
    //+--------------------------------------------------------------+
    //| Construtor                                                    |
    //+--------------------------------------------------------------+
    CStatePersistence(string symbol, int magic_number, CLogger *logger,
                      int save_interval = PERSISTENCE_INTERVAL) {
        m_symbol        = symbol;
        m_magic_number  = magic_number;
        m_logger        = logger;
        m_save_interval = save_interval;
        m_last_save     = 0;
        m_dirty         = false;
        m_file_name     = GenerateFileName();

        m_logger.Info("Persist",
            StringFormat("Init: Arquivo=%s | Intervalo=%ds", m_file_name, m_save_interval));
    }

    //+--------------------------------------------------------------+
    //| Salva estado da grade em arquivo binário                     |
    //| Formato:                                                      |
    //|   [4 bytes] Versão do formato                                 |
    //|   [4 bytes] Magic number                                     |
    //|   [4 bytes] Quantidade de níveis                              |
    //|   [N × SVirtualLevel] Dados dos níveis                       |
    //|   [4 bytes] Checksum                                          |
    //+--------------------------------------------------------------+
    bool SaveState(SVirtualLevel &levels[], int count) {
        int handle = FileOpen(m_file_name,
            FILE_WRITE | FILE_BIN | FILE_COMMON);
        if(handle == INVALID_HANDLE) {
            m_logger.Error("Persist",
                StringFormat("Falha ao abrir para escrita: %s (erro=%d)",
                             m_file_name, GetLastError()));
            return false;
        }

        // Cabeçalho
        int version = PERSISTENCE_FORMAT_VERSION;
        FileWriteInteger(handle, version, INT_VALUE);
        FileWriteInteger(handle, m_magic_number, INT_VALUE);
        FileWriteInteger(handle, count, INT_VALUE);

        // Dados dos níveis
        for(int i = 0; i < count; i++) {
            FileWriteDouble(handle, levels[i].entry_price);
            FileWriteDouble(handle, levels[i].volume);
            FileWriteInteger(handle, levels[i].direction, INT_VALUE);
            FileWriteInteger(handle, levels[i].level_index, INT_VALUE);
            FileWriteInteger(handle, (int)levels[i].open_time, INT_VALUE);
            FileWriteInteger(handle, levels[i].is_active ? 1 : 0, INT_VALUE);
            FileWriteInteger(handle, levels[i].is_recovery ? 1 : 0, INT_VALUE);
            FileWriteDouble(handle, levels[i].accumulated_profit);
        }

        // Checksum
        uint checksum = CalculateChecksum(levels, count);
        FileWriteInteger(handle, (int)checksum, INT_VALUE);

        FileClose(handle);

        m_last_save = TimeCurrent();
        m_dirty = false;

        m_logger.Debug("Persist",
            StringFormat("Estado salvo: %d níveis | Checksum=%u", count, checksum));
        return true;
    }

    //+--------------------------------------------------------------+
    //| Carrega estado da grade de arquivo binário                   |
    //| Retorna: quantidade de níveis carregados (-1 = erro)         |
    //+--------------------------------------------------------------+
    int LoadState(SVirtualLevel &levels[]) {
        // Verifica se arquivo existe
        if(!FileIsExist(m_file_name, FILE_COMMON)) {
            m_logger.Info("Persist", "Nenhum estado salvo encontrado — grade limpa");
            return 0;
        }

        int handle = FileOpen(m_file_name,
            FILE_READ | FILE_BIN | FILE_COMMON);
        if(handle == INVALID_HANDLE) {
            m_logger.Error("Persist",
                StringFormat("Falha ao abrir para leitura: %s", m_file_name));
            return -1;
        }

        // Lê cabeçalho
        int version = FileReadInteger(handle, INT_VALUE);
        if(version != PERSISTENCE_FORMAT_VERSION) {
            m_logger.Warning("Persist",
                StringFormat("Versão incompatível: %d (esperado %d)",
                             version, PERSISTENCE_FORMAT_VERSION));
            FileClose(handle);
            return -1;
        }

        int magic = FileReadInteger(handle, INT_VALUE);
        if(magic != m_magic_number) {
            m_logger.Warning("Persist",
                StringFormat("Magic number diferente: %d (esperado %d)",
                             magic, m_magic_number));
            FileClose(handle);
            return -1;
        }

        int count = FileReadInteger(handle, INT_VALUE);
        if(count < 0 || count > GRID_MAX_ABSOLUTE) {
            m_logger.Error("Persist",
                StringFormat("Quantidade inválida de níveis: %d", count));
            FileClose(handle);
            return -1;
        }

        // Lê níveis
        ArrayResize(levels, count);
        for(int i = 0; i < count; i++) {
            levels[i].Reset();
            levels[i].entry_price       = FileReadDouble(handle);
            levels[i].volume            = FileReadDouble(handle);
            levels[i].direction         = FileReadInteger(handle, INT_VALUE);
            levels[i].level_index       = FileReadInteger(handle, INT_VALUE);
            levels[i].open_time         = (datetime)FileReadInteger(handle, INT_VALUE);
            levels[i].is_active         = FileReadInteger(handle, INT_VALUE) != 0;
            levels[i].is_recovery       = FileReadInteger(handle, INT_VALUE) != 0;
            levels[i].accumulated_profit = FileReadDouble(handle);
        }

        // Verifica checksum
        uint stored_checksum = (uint)FileReadInteger(handle, INT_VALUE);
        uint calc_checksum = CalculateChecksum(levels, count);
        FileClose(handle);

        if(stored_checksum != calc_checksum) {
            m_logger.Error("Persist",
                StringFormat("Checksum inválido! Armazenado=%u Calculado=%u",
                             stored_checksum, calc_checksum));
            // Não retorna -1 — tenta usar os dados mesmo assim
            m_logger.Warning("Persist", "Usando dados apesar do checksum inválido");
        }

        m_logger.Info("Persist",
            StringFormat("Estado restaurado: %d níveis | Checksum=%u",
                         count, calc_checksum));
        return count;
    }

    //+--------------------------------------------------------------+
    //| Verifica se é hora de auto-save                               |
    //+--------------------------------------------------------------+
    bool ShouldAutoSave() {
        if(!m_dirty) return false;
        return (TimeCurrent() - m_last_save) >= m_save_interval;
    }

    //+--------------------------------------------------------------+
    //| Marca que houve mudanças (precisa salvar)                    |
    //+--------------------------------------------------------------+
    void MarkDirty() { m_dirty = true; }

    //+--------------------------------------------------------------+
    //| Remove arquivo de estado (após fechamento total da grade)    |
    //+--------------------------------------------------------------+
    bool DeleteState() {
        if(FileIsExist(m_file_name, FILE_COMMON)) {
            if(FileDelete(m_file_name, FILE_COMMON)) {
                m_logger.Info("Persist", "Arquivo de estado removido");
                return true;
            }
        }
        return false;
    }

    //+--------------------------------------------------------------+
    //| Retorna nome do arquivo para log/diagnóstico                 |
    //+--------------------------------------------------------------+
    string GetFileName() { return m_file_name; }
};

//+------------------------------------------------------------------+
