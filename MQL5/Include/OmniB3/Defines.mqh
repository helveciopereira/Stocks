//+------------------------------------------------------------------+
//|                                                     Defines.mqh  |
//|                         Omni-B3 EA v1.1 — Definições Centrais    |
//|          Adaptado para B3 (NETTING) — Minicontratos WIN/WDO      |
//+------------------------------------------------------------------+
#property copyright "Projeto Omni-B3"
#property link      "https://github.com/helveciopereira/Stocks"
#property version   "1.10"
#property strict

//+------------------------------------------------------------------+
//| CONSTANTES GLOBAIS DO SISTEMA                                    |
//+------------------------------------------------------------------+
#define OMNIB3_VERSION        "1.1.0"
#define OMNIB3_COMMENT_PREFIX "OmniB3"

// Limite absoluto de níveis de grade (trava inviolável)
#define GRID_MAX_ABSOLUTE     10

// Máximo de símbolos simultâneos
#define MAX_SYMBOLS           6

// Cooldown em segundos entre execuções do Smart Close
#define SMART_CLOSE_COOLDOWN  5

// Margem de segurança padrão em ticks para o Smart Close
// Para WIN: 1 tick = 5 pontos = R$1,00 por contrato
#define SMART_CLOSE_MARGIN_TICKS 3.0

// Spread máximo em pontos para abrir ordens
// WIN costuma ter spread de 5-15 pontos
#define MAX_SPREAD_POINTS     30

//+------------------------------------------------------------------+
//| ENUMERAÇÕES                                                      |
//+------------------------------------------------------------------+

// Tipo de espaçamento da grade
enum ENUM_GRID_TYPE {
    GRID_FIXED,         // Grade Fixa — espaçamento constante em pontos
    GRID_DYNAMIC_ATR    // Grade Dinâmica — espaçamento baseado no ATR
};

// Direção da grade (NETTING: sem bi-direcional simultâneo)
enum ENUM_GRID_DIRECTION {
    GRID_BUY_ONLY,      // Apenas Compra — grade de compra (média para baixo)
    GRID_SELL_ONLY       // Apenas Venda — grade de venda (média para cima)
};

// Modo de gerenciamento de lotes (volume em contratos inteiros)
enum ENUM_LOT_MODE {
    LOT_FIXED,           // Fixo — mesmo volume em todos os níveis
    LOT_MULTIPLIER       // Multiplicador — Vol_n = Vol₀ × Mult^(n-1)
};

// Alvo do Smart Close
enum ENUM_CLOSE_TARGET {
    CLOSE_WORST,         // Pior Nível — maior prejuízo virtual
    CLOSE_OLDEST         // Mais Antigo — primeiro nível da grade
};

// Perfis de risco pré-configurados para B3
enum ENUM_RISK_PROFILE {
    PROFILE_CONSERVADOR, // Conservador — poucos níveis, sem multiplicador
    PROFILE_MODERADO,    // Moderado — mais níveis, multiplicador leve
    PROFILE_CUSTOM       // Personalizado — usuário define tudo
};

// Níveis de log
enum ENUM_LOG_LEVEL {
    LOG_DEBUG,
    LOG_INFO,
    LOG_WARNING,
    LOG_ERROR,
    LOG_CRITICAL
};

//+------------------------------------------------------------------+
//| ESTRUTURA — Nível Virtual da Grade                               |
//|                                                                   |
//| Em contas NETTING existe apenas 1 posição por símbolo. Para      |
//| rastrear cada nível da grade individualmente, mantemos um array  |
//| interno de "níveis virtuais" com preço de entrada e volume.      |
//| O P&L de cada nível é calculado em tempo real.                   |
//+------------------------------------------------------------------+
struct SVirtualLevel {
    double   entry_price;    // Preço de entrada deste nível
    double   volume;         // Volume em contratos
    int      direction;      // +1 = compra, -1 = venda
    int      level_index;    // Índice do nível (0, 1, 2, ...)
    datetime open_time;      // Data/hora de abertura
    bool     is_active;      // Se está ativo

    // Inicializa zerado
    void Reset() {
        entry_price = 0.0;
        volume      = 0.0;
        direction   = 0;
        level_index = 0;
        open_time   = 0;
        is_active   = false;
    }

    // Calcula P&L virtual deste nível em moeda da conta (BRL)
    // current_price: preço atual (bid para compra, ask para venda)
    // tick_size: SYMBOL_TRADE_TICK_SIZE (ex: 5 para WIN)
    // tick_value: SYMBOL_TRADE_TICK_VALUE (ex: 1.00 para WIN)
    double CalculateProfit(double current_price, double tick_size, double tick_value) {
        if(!is_active || tick_size <= 0.0) return 0.0;
        double price_diff = direction * (current_price - entry_price);
        return (price_diff / tick_size) * tick_value * volume;
    }
};

//+------------------------------------------------------------------+
//| ESTRUTURA — Estado Consolidado da Grade                          |
//+------------------------------------------------------------------+
struct SGridState {
    string  symbol;
    int     total_levels;        // Níveis virtuais ativos
    double  total_volume;        // Volume total em contratos
    double  total_profit;        // P&L total virtual em BRL
    double  avg_price;           // Preço médio ponderado
    double  worst_profit;        // Pior P&L individual
    int     worst_index;         // Índice do pior nível no array
    double  worst_volume;        // Volume do pior nível
    double  best_profit;         // Melhor P&L individual
    int     best_index;          // Índice do melhor nível
    double  positive_profit_sum; // Soma dos P&L positivos

    void Reset() {
        symbol              = "";
        total_levels        = 0;
        total_volume        = 0.0;
        total_profit        = 0.0;
        avg_price           = 0.0;
        worst_profit        = 0.0;
        worst_index         = -1;
        worst_volume        = 0.0;
        best_profit         = 0.0;
        best_index          = -1;
        positive_profit_sum = 0.0;
    }
};

//+------------------------------------------------------------------+
