//+------------------------------------------------------------------+
//|                                              PositionManager.mqh |
//|                 Omni-B3 EA v2.47 â€” Gerenciador de PosiÃ§Ãµes        |
//|       Rastreamento virtual de nÃ­veis para contas NETTING (B3)    |
//|       Com persistÃªncia de estado e integraÃ§Ã£o com Recovery       |
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
#include "StatePersistence.mqh"

//+------------------------------------------------------------------+
//| Gerenciador de PosiÃ§Ãµes para contas NETTING                      |
//|                                                                   |
//| Em NETTING existe apenas 1 posiÃ§Ã£o por sÃ­mbolo no MT5.           |
//| Para implementar grid, rastreamos cada nÃ­vel internamente        |
//| usando um array de SVirtualLevel. O P&L de cada nÃ­vel Ã©          |
//| calculado em tempo real com base no preÃ§o atual.                 |
//|                                                                   |
//| v2.0: Integra com StatePersistence para sobreviver restarts.     |
//+------------------------------------------------------------------+
class CPositionManager {
private:
    SVirtualLevel      m_levels[];       // Array de nÃ­veis virtuais
    int                m_level_count;    // Quantidade de nÃ­veis ativos
    string             m_symbol;
    int                m_magic_number;
    CLogger           *m_logger;
    CStatePersistence *m_persistence;    // PersistÃªncia de estado

public:
    //+--------------------------------------------------------------+
    //| Construtor                                                    |
    //+--------------------------------------------------------------+
    CPositionManager(string symbol, int magic_number, CLogger *logger) {
        m_symbol       = symbol;
        m_magic_number = magic_number;
        m_logger       = logger;
        m_level_count  = 0;
        m_persistence  = NULL;
        ArrayResize(m_levels, 0);
    }

    //+--------------------------------------------------------------+
    //| Destrutor â€” salva estado antes de destruir                   |
    //+--------------------------------------------------------------+
    ~CPositionManager() {
        // Salva estado final
        if(m_persistence != NULL && m_level_count > 0)
            m_persistence.SaveState(m_levels, m_level_count);
    }

    //+--------------------------------------------------------------+
    //| Define o mÃ³dulo de persistÃªncia                               |
    //+--------------------------------------------------------------+
    void SetPersistence(CStatePersistence *persistence) {
        m_persistence = persistence;
    }

    //+--------------------------------------------------------------+
    //| Sincroniza com posiÃ§Ã£o real e estado salvo ao iniciar o EA   |
    //| Prioridade: 1) Estado salvo, 2) PosiÃ§Ã£o real, 3) Grade limpa |
    //+--------------------------------------------------------------+
    void SyncOnStartup() {
        // 1. Tenta restaurar estado salvo
        if(m_persistence != NULL) {
            SVirtualLevel saved_levels[];
            int saved_count = m_persistence.LoadState(saved_levels);

            if(saved_count > 0) {
                // Verifica se posiÃ§Ã£o real ainda existe
                if(PositionSelect(m_symbol)) {
                    double real_volume = PositionGetDouble(POSITION_VOLUME);
                    double virtual_volume = 0.0;
                    for(int i = 0; i < saved_count; i++)
                        if(saved_levels[i].is_active)
                            virtual_volume += saved_levels[i].volume;

                    // ValidaÃ§Ã£o: volume virtual deve ser compatÃ­vel com real
                    if(MathAbs(virtual_volume - real_volume) <= 1.0) {
                        ArrayResize(m_levels, saved_count);
                        for(int i = 0; i < saved_count; i++)
                            m_levels[i] = saved_levels[i];
                        m_level_count = saved_count;

                        m_logger.Info("PosManager",
                            StringFormat("Estado restaurado: %d nÃ­veis | Vol virtual=%.0f | Vol real=%.0f",
                                         saved_count, virtual_volume, real_volume));
                        return;
                    } else {
                        m_logger.Warning("PosManager",
                            StringFormat("Volume incompatÃ­vel: virtual=%.0f real=%.0f â€” recriando",
                                         virtual_volume, real_volume));
                    }
                } else {
                    // PosiÃ§Ã£o nÃ£o existe mais â€” estado salvo Ã© invÃ¡lido
                    m_logger.Info("PosManager",
                        "PosiÃ§Ã£o real nÃ£o existe â€” descartando estado salvo");
                    m_persistence.DeleteState();
                }
            }
        }

        // 2. Tenta sincronizar com posiÃ§Ã£o real existente
        if(!PositionSelect(m_symbol)) {
            m_logger.Info("PosManager", "Nenhuma posiÃ§Ã£o existente â€” grade limpa");
            return;
        }

        // Verifica se Ã© do nosso magic number
        if(PositionGetInteger(POSITION_MAGIC) != m_magic_number) {
            m_logger.Warning("PosManager",
                "PosiÃ§Ã£o existente pertence a outro EA â€” ignorando");
            return;
        }

        // Cria nÃ­vel virtual Ãºnico para a posiÃ§Ã£o existente
        double volume = PositionGetDouble(POSITION_VOLUME);
        double price  = PositionGetDouble(POSITION_PRICE_OPEN);
        ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        int dir = (type == POSITION_TYPE_BUY) ? 1 : -1;

        SVirtualLevel level;
        level.Reset();
        level.entry_price = price;
        level.volume      = volume;
        level.direction   = dir;
        level.level_index = 0;
        level.open_time   = (datetime)PositionGetInteger(POSITION_TIME);
        level.is_active   = true;

        m_level_count = 1;
        ArrayResize(m_levels, 1);
        m_levels[0] = level;

        m_logger.Info("PosManager",
            StringFormat("PosiÃ§Ã£o existente sincronizada: %s %.0f contratos @ %.2f",
                         (dir > 0 ? "COMPRA" : "VENDA"), volume, price));

        // Salva estado imediatamente
        SaveStateNow();
    }

    //+--------------------------------------------------------------+
    //| Registra um novo nÃ­vel virtual apÃ³s abertura de ordem        |
    //+--------------------------------------------------------------+
    void RegisterLevel(double price, double volume, int direction, bool is_recovery = false) {
        SVirtualLevel level;
        level.Reset();
        level.entry_price = price;
        level.volume      = volume;
        level.direction   = direction;
        level.level_index = m_level_count;
        level.open_time   = TimeCurrent();
        level.is_active   = true;
        level.is_recovery = is_recovery;

        m_level_count++;
        ArrayResize(m_levels, m_level_count);
        m_levels[m_level_count - 1] = level;

        m_logger.Debug("PosManager",
            StringFormat("NÃ­vel %d registrado: %.0f contratos @ %.2f%s",
                         level.level_index, volume, price,
                         is_recovery ? " [RECOVERY]" : ""));

        // Marca para persistÃªncia
        if(m_persistence != NULL) m_persistence.MarkDirty();
    }

    //+--------------------------------------------------------------+
    //| Remove um nÃ­vel virtual por Ã­ndice no array                  |
    //+--------------------------------------------------------------+
    void RemoveLevelByArrayIndex(int array_index) {
        if(array_index < 0 || array_index >= m_level_count) return;

        // Desloca elementos para preencher o buraco
        for(int i = array_index; i < m_level_count - 1; i++) {
            m_levels[i] = m_levels[i + 1];
        }
        m_level_count--;
        ArrayResize(m_levels, MathMax(m_level_count, 0));

        // Marca para persistÃªncia
        if(m_persistence != NULL) m_persistence.MarkDirty();
    }

    //+--------------------------------------------------------------+
    //| Remove mÃºltiplos nÃ­veis por Ã­ndices (do maior para o menor)  |
    //+--------------------------------------------------------------+
    void RemoveLevelsByIndices(int &indices[], int count) {
        // Ordena Ã­ndices em ordem decrescente para remoÃ§Ã£o segura
        for(int i = 0; i < count - 1; i++) {
            for(int j = i + 1; j < count; j++) {
                if(indices[j] > indices[i]) {
                    int temp = indices[i];
                    indices[i] = indices[j];
                    indices[j] = temp;
                }
            }
        }
        // Remove do maior Ã­ndice para o menor
        for(int i = 0; i < count; i++) {
            RemoveLevelByArrayIndex(indices[i]);
        }
    }

    //+--------------------------------------------------------------+
    //| Retorna nÃºmero de nÃ­veis virtuais ativos                     |
    //+--------------------------------------------------------------+
    int CountLevels() {
        return m_level_count;
    }

    //+--------------------------------------------------------------+
    //| Retorna preÃ§o de entrada do Ãºltimo nÃ­vel registrado          |
    //+--------------------------------------------------------------+
    double GetLastLevelPrice() {
        if(m_level_count == 0) return 0.0;
        return m_levels[m_level_count - 1].entry_price;
    }

    //+--------------------------------------------------------------+
    //| Retorna o tempo do nÃ­vel mais antigo (para TakeProfit tempo) |
    //+--------------------------------------------------------------+
    datetime GetOldestLevelTime() {
        if(m_level_count == 0) return 0;
        datetime oldest = m_levels[0].open_time;
        for(int i = 1; i < m_level_count; i++) {
            if(m_levels[i].is_active && m_levels[i].open_time < oldest)
                oldest = m_levels[i].open_time;
        }
        return oldest;
    }

    //+--------------------------------------------------------------+
    //| Monta o estado consolidado da grade com P&L virtual          |
    //| Calcula P&L de cada nÃ­vel com base no preÃ§o atual            |
    //+--------------------------------------------------------------+
    SGridState GetGridState() {
        SGridState state;
        state.Reset();
        state.symbol = m_symbol;

        if(m_level_count == 0) return state;

        // ObtÃ©m dados do sÃ­mbolo para cÃ¡lculo de P&L
        double tick_size  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
        double tick_value = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
        double bid        = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        double ask        = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
        double weighted_price_sum = 0.0;
        state.oldest_level_time = TimeCurrent();

        for(int i = 0; i < m_level_count; i++) {
            if(!m_levels[i].is_active) continue;

            // Para P&L: compra usa bid (preÃ§o de saÃ­da), venda usa ask
            double exit_price = (m_levels[i].direction > 0) ? bid : ask;
            double profit = m_levels[i].CalculateProfit(exit_price, tick_size, tick_value);

            state.total_levels++;
            state.total_volume += m_levels[i].volume;
            state.total_profit += profit;
            weighted_price_sum += (m_levels[i].volume * m_levels[i].entry_price);

            // Pior nÃ­vel (maior prejuÃ­zo)
            if(profit < state.worst_profit || state.worst_index == -1) {
                if(profit < 0) {
                    state.worst_profit = profit;
                    state.worst_index  = i;
                    state.worst_volume = m_levels[i].volume;
                }
            }

            // Melhor nÃ­vel (maior lucro)
            if(profit > state.best_profit) {
                state.best_profit = profit;
                state.best_index  = i;
            }

            // Soma lucros positivos e conta categorias
            if(profit > 0.0) {
                state.positive_profit_sum += profit;
                state.positive_count++;
            } else if(profit < 0.0) {
                state.negative_count++;
            }

            // NÃ­vel mais antigo
            if(m_levels[i].open_time < state.oldest_level_time)
                state.oldest_level_time = m_levels[i].open_time;
        }

        // PreÃ§o mÃ©dio ponderado por volume
        if(state.total_volume > 0.0) {
            state.avg_price = weighted_price_sum / state.total_volume;
        }

        // Drawdown % da grade
        double robot_balance = AccountInfoDouble(ACCOUNT_BALANCE);
        if(robot_balance > 0.0 && state.total_profit < 0.0) {
            state.max_drawdown_pct = (MathAbs(state.total_profit) / robot_balance) * 100.0;
        }

        return state;
    }

    //+--------------------------------------------------------------+
    //| Retorna P&L virtual de um nÃ­vel especÃ­fico                   |
    //+--------------------------------------------------------------+
    double GetLevelProfit(int array_index) {
        if(array_index < 0 || array_index >= m_level_count) return 0.0;

        double tick_size  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
        double tick_value = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
        double exit_price = (m_levels[array_index].direction > 0)
                            ? SymbolInfoDouble(m_symbol, SYMBOL_BID)
                            : SymbolInfoDouble(m_symbol, SYMBOL_ASK);

        return m_levels[array_index].CalculateProfit(exit_price, tick_size, tick_value);
    }

    //+--------------------------------------------------------------+
    //| Retorna volume de um nÃ­vel especÃ­fico                        |
    //+--------------------------------------------------------------+
    double GetLevelVolume(int array_index) {
        if(array_index < 0 || array_index >= m_level_count) return 0.0;
        return m_levels[array_index].volume;
    }

    //+--------------------------------------------------------------+
    //| Retorna volume total real da posiÃ§Ã£o no MT5                  |
    //+--------------------------------------------------------------+
    double GetRealVolume() {
        if(!PositionSelect(m_symbol)) return 0.0;
        if(PositionGetInteger(POSITION_MAGIC) != m_magic_number) return 0.0;
        return PositionGetDouble(POSITION_VOLUME);
    }

    //+--------------------------------------------------------------+
    //| Coleta Ã­ndices dos nÃ­veis com P&L positivo, ordenados        |
    //| Retorna: quantidade de nÃ­veis lucrativos encontrados         |
    //+--------------------------------------------------------------+
    int GetProfitableLevelIndices(int &indices[], double &profits[]) {
        int count = 0;

        // Primeira passagem: contar
        for(int i = 0; i < m_level_count; i++) {
            double pl = GetLevelProfit(i);
            if(pl > 0.0) count++;
        }
        if(count == 0) return 0;

        ArrayResize(indices, count);
        ArrayResize(profits, count);
        int idx = 0;

        // Segunda passagem: preencher
        for(int i = 0; i < m_level_count; i++) {
            double pl = GetLevelProfit(i);
            if(pl > 0.0 && idx < count) {
                indices[idx] = i;
                profits[idx] = pl;
                idx++;
            }
        }
        return count;
    }

    //+--------------------------------------------------------------+
    //| Limpa todos os nÃ­veis virtuais (apÃ³s fechamento total)       |
    //+--------------------------------------------------------------+
    void ClearAllLevels() {
        m_level_count = 0;
        ArrayResize(m_levels, 0);
        m_logger.Info("PosManager", "Todos os nÃ­veis virtuais removidos");

        // Remove arquivo de persistÃªncia
        if(m_persistence != NULL)
            m_persistence.DeleteState();
    }

    //+--------------------------------------------------------------+
    //| Salva estado imediatamente (chamado apÃ³s operaÃ§Ãµes)          |
    //+--------------------------------------------------------------+
    void SaveStateNow() {
        if(m_persistence != NULL && m_level_count > 0)
            m_persistence.SaveState(m_levels, m_level_count);
    }

    //+--------------------------------------------------------------+
    //| Auto-save periÃ³dico (chamado pelo OnTimer)                   |
    //+--------------------------------------------------------------+
    void AutoSave() {
        if(m_persistence != NULL && m_persistence.ShouldAutoSave())
            m_persistence.SaveState(m_levels, m_level_count);
    }

    //+--------------------------------------------------------------+
    //| Retorna acesso direto ao array de nÃ­veis (para persistÃªncia) |
    //+--------------------------------------------------------------+
    int GetLevelsArray(SVirtualLevel &out_levels[]) {
        ArrayResize(out_levels, m_level_count);
        for(int i = 0; i < m_level_count; i++)
            out_levels[i] = m_levels[i];
        return m_level_count;
    }
};

//+------------------------------------------------------------------+
