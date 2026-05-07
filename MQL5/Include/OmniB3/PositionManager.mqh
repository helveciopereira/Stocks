//+------------------------------------------------------------------+
//|                                              PositionManager.mqh |
//|                     Omni-B3 EA v1.0 — Gerenciador de Posições    |
//|         Centraliza consultas, cálculos de P&L e preço médio      |
//+------------------------------------------------------------------+
#property copyright "Projeto Omni-B3"
#property link      "https://github.com/seu-usuario/Stocks"
#property version   "1.00"
#property strict

#include "Defines.mqh"
#include "Logger.mqh"

//+------------------------------------------------------------------+
//| Classe centralizadora de consulta e análise de posições          |
//| Filtra posições por símbolo e magic number, calcula métricas     |
//| como preço médio ponderado, P&L total e identifica extremos.     |
//+------------------------------------------------------------------+
class CPositionManager {
private:
    string   m_symbol;          // Símbolo filtrado (ex: "AUDCAD")
    int      m_magic_number;    // Magic number para filtrar posições do EA
    CLogger *m_logger;          // Ponteiro para o logger global

public:
    //+--------------------------------------------------------------+
    //| Construtor — recebe símbolo, magic e referência ao logger    |
    //+--------------------------------------------------------------+
    CPositionManager(string symbol, int magic_number, CLogger *logger) {
        m_symbol       = symbol;
        m_magic_number = magic_number;
        m_logger       = logger;
    }

    //+--------------------------------------------------------------+
    //| Conta quantas posições abertas pertencem a este EA/símbolo   |
    //| Retorna: número de posições ativas                           |
    //+--------------------------------------------------------------+
    int CountPositions() {
        int count = 0;
        for(int i = PositionsTotal() - 1; i >= 0; i--) {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0) continue;
            if(PositionGetString(POSITION_SYMBOL) == m_symbol &&
               PositionGetInteger(POSITION_MAGIC) == m_magic_number) {
                count++;
            }
        }
        return count;
    }

    //+--------------------------------------------------------------+
    //| Conta posições de um tipo específico (BUY ou SELL)           |
    //| Parâmetro: pos_type — POSITION_TYPE_BUY ou POSITION_TYPE_SELL|
    //| Retorna: número de posições do tipo especificado             |
    //+--------------------------------------------------------------+
    int CountPositionsByType(ENUM_POSITION_TYPE pos_type) {
        int count = 0;
        for(int i = PositionsTotal() - 1; i >= 0; i--) {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0) continue;
            if(PositionGetString(POSITION_SYMBOL) == m_symbol &&
               PositionGetInteger(POSITION_MAGIC) == m_magic_number &&
               (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == pos_type) {
                count++;
            }
        }
        return count;
    }

    //+--------------------------------------------------------------+
    //| Monta o estado completo da grade para um tipo de posição     |
    //| Parâmetro: pos_type — POSITION_TYPE_BUY ou SELL              |
    //| Retorna: struct SGridState preenchida com todas as métricas  |
    //|                                                               |
    //| Esta é a função mais importante do módulo. Ela varre todas   |
    //| as posições abertas e calcula:                                |
    //|  - Preço médio ponderado por volume                          |
    //|  - P&L total aberto                                          |
    //|  - Posição com maior lucro (melhor) e maior prejuízo (pior)  |
    //|  - Soma dos lucros positivos (usado pelo Smart Close)        |
    //+--------------------------------------------------------------+
    SGridState GetGridState(ENUM_POSITION_TYPE pos_type) {
        SGridState state;
        state.Reset();
        state.symbol = m_symbol;

        // Variáveis auxiliares para cálculo do preço médio ponderado
        double weighted_price_sum = 0.0;  // Σ (volume × preço)
        state.worst_profit = 0.0;         // Inicializa como zero (neutro)

        for(int i = PositionsTotal() - 1; i >= 0; i--) {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0) continue;

            // Filtra: mesmo símbolo, mesmo magic, mesmo tipo
            if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
            if(PositionGetInteger(POSITION_MAGIC) != m_magic_number) continue;
            if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != pos_type) continue;

            // Extrai dados da posição
            double volume     = PositionGetDouble(POSITION_VOLUME);
            double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
            double profit     = PositionGetDouble(POSITION_PROFIT);
            double swap       = PositionGetDouble(POSITION_SWAP);
            double total_pl   = profit + swap;  // P&L real inclui swap

            // Acumula para o estado geral
            state.total_levels++;
            state.total_volume += volume;
            state.total_profit += total_pl;
            weighted_price_sum += (volume * open_price);

            // Identifica a posição com maior prejuízo (candidata ao Smart Close)
            if(total_pl < state.worst_profit) {
                state.worst_profit = total_pl;
                state.worst_ticket = ticket;
                state.worst_lot    = volume;
            }

            // Identifica a posição com maior lucro
            if(total_pl > state.best_profit) {
                state.best_profit = total_pl;
                state.best_ticket = ticket;
            }

            // Soma lucros positivos (usado como "combustível" do Smart Close)
            if(total_pl > 0.0) {
                state.positive_profit_sum += total_pl;
            }
        }

        // Calcula preço médio ponderado por volume
        // Fórmula: Σ(Volume_i × Preço_i) / Σ(Volume_i)
        if(state.total_volume > 0.0) {
            state.avg_price = weighted_price_sum / state.total_volume;
        }

        return state;
    }

    //+--------------------------------------------------------------+
    //| Retorna o estado combinado (compra + venda) de todas posições|
    //| Útil para calcular P&L geral e verificar limites de risco    |
    //+--------------------------------------------------------------+
    SGridState GetCombinedState() {
        SGridState buy_state  = GetGridState(POSITION_TYPE_BUY);
        SGridState sell_state = GetGridState(POSITION_TYPE_SELL);

        SGridState combined;
        combined.Reset();
        combined.symbol       = m_symbol;
        combined.total_levels = buy_state.total_levels + sell_state.total_levels;
        combined.total_volume = buy_state.total_volume + sell_state.total_volume;
        combined.total_profit = buy_state.total_profit + sell_state.total_profit;
        combined.positive_profit_sum = buy_state.positive_profit_sum + sell_state.positive_profit_sum;

        // Pior entre as duas direções
        if(buy_state.worst_profit < sell_state.worst_profit) {
            combined.worst_profit = buy_state.worst_profit;
            combined.worst_ticket = buy_state.worst_ticket;
            combined.worst_lot    = buy_state.worst_lot;
        } else {
            combined.worst_profit = sell_state.worst_profit;
            combined.worst_ticket = sell_state.worst_ticket;
            combined.worst_lot    = sell_state.worst_lot;
        }

        return combined;
    }

    //+--------------------------------------------------------------+
    //| Obtém o preço de abertura da última posição de um tipo       |
    //| Usado para calcular se o preço andou o suficiente para abrir |
    //| um novo nível da grade                                       |
    //+--------------------------------------------------------------+
    double GetLastOpenPrice(ENUM_POSITION_TYPE pos_type) {
        double   last_price = 0.0;
        datetime last_time  = 0;

        for(int i = PositionsTotal() - 1; i >= 0; i--) {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0) continue;

            if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
            if(PositionGetInteger(POSITION_MAGIC) != m_magic_number) continue;
            if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != pos_type) continue;

            datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
            // Encontra a mais recente (maior datetime)
            if(open_time > last_time) {
                last_time  = open_time;
                last_price = PositionGetDouble(POSITION_PRICE_OPEN);
            }
        }
        return last_price;
    }

    //+--------------------------------------------------------------+
    //| Obtém o preço de abertura da posição mais antiga de um tipo  |
    //| Usado quando o modo de Smart Close é CLOSE_OLDEST            |
    //+--------------------------------------------------------------+
    double GetOldestOpenPrice(ENUM_POSITION_TYPE pos_type, ulong &out_ticket) {
        double   oldest_price = 0.0;
        datetime oldest_time  = D'2099.01.01';
        out_ticket = 0;

        for(int i = PositionsTotal() - 1; i >= 0; i--) {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0) continue;

            if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
            if(PositionGetInteger(POSITION_MAGIC) != m_magic_number) continue;
            if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != pos_type) continue;

            datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
            if(open_time < oldest_time) {
                oldest_time  = open_time;
                oldest_price = PositionGetDouble(POSITION_PRICE_OPEN);
                out_ticket   = ticket;
            }
        }
        return oldest_price;
    }

    //+--------------------------------------------------------------+
    //| Coleta todos os tickets das posições lucrativas              |
    //| Retorna: array de tickets com lucro > 0, ordenados por lucro |
    //+--------------------------------------------------------------+
    int GetProfitableTickets(ENUM_POSITION_TYPE pos_type, ulong &tickets[], double &profits[]) {
        int count = 0;

        // Primeira passagem: contar quantas posições lucrativas existem
        for(int i = PositionsTotal() - 1; i >= 0; i--) {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0) continue;
            if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
            if(PositionGetInteger(POSITION_MAGIC) != m_magic_number) continue;
            if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != pos_type) continue;

            double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
            if(profit > 0.0) count++;
        }

        if(count == 0) return 0;

        // Redimensiona os arrays de saída
        ArrayResize(tickets, count);
        ArrayResize(profits, count);
        int idx = 0;

        // Segunda passagem: preencher os arrays
        for(int i = PositionsTotal() - 1; i >= 0; i--) {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0) continue;
            if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
            if(PositionGetInteger(POSITION_MAGIC) != m_magic_number) continue;
            if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != pos_type) continue;

            double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
            if(profit > 0.0 && idx < count) {
                tickets[idx] = ticket;
                profits[idx] = profit;
                idx++;
            }
        }

        return count;
    }

    //+--------------------------------------------------------------+
    //| Atualiza o símbolo gerenciado (para uso multi-símbolo)       |
    //+--------------------------------------------------------------+
    void SetSymbol(string symbol) {
        m_symbol = symbol;
    }

    //+--------------------------------------------------------------+
    //| Atualiza o magic number (para uso multi-símbolo)             |
    //+--------------------------------------------------------------+
    void SetMagic(int magic) {
        m_magic_number = magic;
    }
};

//+------------------------------------------------------------------+
