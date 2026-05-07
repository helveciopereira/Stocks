//+------------------------------------------------------------------+
//|                                              PositionManager.mqh |
//|                 Omni-B3 EA v1.1 — Gerenciador de Posições        |
//|       Rastreamento virtual de níveis para contas NETTING (B3)    |
//+------------------------------------------------------------------+
#property copyright "Projeto Omni-B3"
#property link      "https://github.com/helveciopereira/Stocks"
#property version   "1.10"
#property strict

#include "Defines.mqh"
#include "Logger.mqh"

//+------------------------------------------------------------------+
//| Gerenciador de Posições para contas NETTING                      |
//|                                                                   |
//| Em NETTING existe apenas 1 posição por símbolo no MT5.           |
//| Para implementar grid, rastreamos cada nível internamente        |
//| usando um array de SVirtualLevel. O P&L de cada nível é          |
//| calculado em tempo real com base no preço atual.                 |
//+------------------------------------------------------------------+
class CPositionManager {
private:
    SVirtualLevel m_levels[];        // Array de níveis virtuais
    int           m_level_count;     // Quantidade de níveis ativos
    string        m_symbol;
    int           m_magic_number;
    CLogger      *m_logger;

public:
    //+--------------------------------------------------------------+
    //| Construtor                                                    |
    //+--------------------------------------------------------------+
    CPositionManager(string symbol, int magic_number, CLogger *logger) {
        m_symbol       = symbol;
        m_magic_number = magic_number;
        m_logger       = logger;
        m_level_count  = 0;
        ArrayResize(m_levels, 0);
    }

    //+--------------------------------------------------------------+
    //| Sincroniza com posição real ao iniciar o EA                  |
    //| Se já existe posição aberta, cria um nível virtual para ela  |
    //+--------------------------------------------------------------+
    void SyncOnStartup() {
        // Verifica se há posição real aberta para este símbolo
        if(!PositionSelect(m_symbol)) {
            m_logger.Info("PosManager", "Nenhuma posição existente — grade limpa");
            return;
        }

        // Verifica se é do nosso magic number
        if(PositionGetInteger(POSITION_MAGIC) != m_magic_number) {
            m_logger.Warning("PosManager",
                "Posição existente pertence a outro EA — ignorando");
            return;
        }

        // Cria nível virtual para a posição existente
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
            StringFormat("Posição existente sincronizada: %s %.0f contratos @ %.2f",
                         (dir > 0 ? "COMPRA" : "VENDA"), volume, price));
    }

    //+--------------------------------------------------------------+
    //| Registra um novo nível virtual após abertura de ordem        |
    //+--------------------------------------------------------------+
    void RegisterLevel(double price, double volume, int direction) {
        SVirtualLevel level;
        level.Reset();
        level.entry_price = price;
        level.volume      = volume;
        level.direction   = direction;
        level.level_index = m_level_count;
        level.open_time   = TimeCurrent();
        level.is_active   = true;

        m_level_count++;
        ArrayResize(m_levels, m_level_count);
        m_levels[m_level_count - 1] = level;

        m_logger.Debug("PosManager",
            StringFormat("Nível %d registrado: %.0f contratos @ %.2f",
                         level.level_index, volume, price));
    }

    //+--------------------------------------------------------------+
    //| Remove um nível virtual por índice no array                  |
    //+--------------------------------------------------------------+
    void RemoveLevelByArrayIndex(int array_index) {
        if(array_index < 0 || array_index >= m_level_count) return;

        // Desloca elementos para preencher o buraco
        for(int i = array_index; i < m_level_count - 1; i++) {
            m_levels[i] = m_levels[i + 1];
        }
        m_level_count--;
        ArrayResize(m_levels, MathMax(m_level_count, 0));
    }

    //+--------------------------------------------------------------+
    //| Remove múltiplos níveis por índices (do maior para o menor)  |
    //+--------------------------------------------------------------+
    void RemoveLevelsByIndices(int &indices[], int count) {
        // Ordena índices em ordem decrescente para remoção segura
        for(int i = 0; i < count - 1; i++) {
            for(int j = i + 1; j < count; j++) {
                if(indices[j] > indices[i]) {
                    int temp = indices[i];
                    indices[i] = indices[j];
                    indices[j] = temp;
                }
            }
        }
        // Remove do maior índice para o menor
        for(int i = 0; i < count; i++) {
            RemoveLevelByArrayIndex(indices[i]);
        }
    }

    //+--------------------------------------------------------------+
    //| Retorna número de níveis virtuais ativos                     |
    //+--------------------------------------------------------------+
    int CountLevels() {
        return m_level_count;
    }

    //+--------------------------------------------------------------+
    //| Retorna preço de entrada do último nível registrado          |
    //+--------------------------------------------------------------+
    double GetLastLevelPrice() {
        if(m_level_count == 0) return 0.0;
        return m_levels[m_level_count - 1].entry_price;
    }

    //+--------------------------------------------------------------+
    //| Monta o estado consolidado da grade com P&L virtual          |
    //| Calcula P&L de cada nível com base no preço atual            |
    //+--------------------------------------------------------------+
    SGridState GetGridState() {
        SGridState state;
        state.Reset();
        state.symbol = m_symbol;

        if(m_level_count == 0) return state;

        // Obtém dados do símbolo para cálculo de P&L
        double tick_size  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
        double tick_value = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
        double bid        = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        double ask        = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
        double weighted_price_sum = 0.0;

        for(int i = 0; i < m_level_count; i++) {
            if(!m_levels[i].is_active) continue;

            // Para P&L: compra usa bid (preço de saída), venda usa ask
            double exit_price = (m_levels[i].direction > 0) ? bid : ask;
            double profit = m_levels[i].CalculateProfit(exit_price, tick_size, tick_value);

            state.total_levels++;
            state.total_volume += m_levels[i].volume;
            state.total_profit += profit;
            weighted_price_sum += (m_levels[i].volume * m_levels[i].entry_price);

            // Pior nível (maior prejuízo)
            if(profit < state.worst_profit || state.worst_index == -1) {
                if(profit < 0) {
                    state.worst_profit = profit;
                    state.worst_index  = i;
                    state.worst_volume = m_levels[i].volume;
                }
            }

            // Melhor nível (maior lucro)
            if(profit > state.best_profit) {
                state.best_profit = profit;
                state.best_index  = i;
            }

            // Soma lucros positivos
            if(profit > 0.0) {
                state.positive_profit_sum += profit;
            }
        }

        // Preço médio ponderado por volume
        if(state.total_volume > 0.0) {
            state.avg_price = weighted_price_sum / state.total_volume;
        }

        return state;
    }

    //+--------------------------------------------------------------+
    //| Retorna P&L virtual de um nível específico                   |
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
    //| Retorna volume de um nível específico                        |
    //+--------------------------------------------------------------+
    double GetLevelVolume(int array_index) {
        if(array_index < 0 || array_index >= m_level_count) return 0.0;
        return m_levels[array_index].volume;
    }

    //+--------------------------------------------------------------+
    //| Retorna volume total real da posição no MT5                  |
    //+--------------------------------------------------------------+
    double GetRealVolume() {
        if(!PositionSelect(m_symbol)) return 0.0;
        if(PositionGetInteger(POSITION_MAGIC) != m_magic_number) return 0.0;
        return PositionGetDouble(POSITION_VOLUME);
    }

    //+--------------------------------------------------------------+
    //| Coleta índices dos níveis com P&L positivo, ordenados        |
    //| Retorna: quantidade de níveis lucrativos encontrados         |
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
    //| Limpa todos os níveis virtuais (após fechamento total)       |
    //+--------------------------------------------------------------+
    void ClearAllLevels() {
        m_level_count = 0;
        ArrayResize(m_levels, 0);
        m_logger.Info("PosManager", "Todos os níveis virtuais removidos");
    }
};

//+------------------------------------------------------------------+
