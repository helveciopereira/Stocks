//+------------------------------------------------------------------+
//|                                                     Defines.mqh  |
//|                         Omni-B3 EA v2.0 — Definições Centrais    |
//|          Adaptado para B3 (NETTING) — Minicontratos WIN/WDO      |
//+------------------------------------------------------------------+
#property copyright "Projeto Omni-B3"
#property link      "https://github.com/helveciopereira/Stocks"
#property version     "2.14"
#property strict

//+------------------------------------------------------------------+
//| CONSTANTES GLOBAIS DO SISTEMA                                    |
//+------------------------------------------------------------------+
#define OMNIB3_VERSION        "2.14"
#define OMNIB3_COMMENT_PREFIX "OmniB3"

// Limite absoluto de níveis de grade (trava inviolável de segurança)
#define GRID_MAX_ABSOLUTE     20

// Máximo de símbolos simultâneos no modo Multi-Ativos
#define MAX_SYMBOLS           6

// Cooldown em segundos entre execuções do Smart Close
#define SMART_CLOSE_COOLDOWN  5

// Margem de segurança padrão em ticks para o Smart Close
// Para WIN: 1 tick = 5 pontos = R$1,00 por contrato
#define SMART_CLOSE_MARGIN_TICKS 3.0

// Spread máximo em pontos para abrir ordens
// WIN costuma ter spread de 5-15 pontos
#define MAX_SPREAD_POINTS     30

// Intervalo de auto-save do estado em segundos
#define PERSISTENCE_INTERVAL  30

// Máximo de indicadores de confirmação
#define MAX_CONFIRMATIONS     4

// Nome do arquivo de persistência de estado
#define PERSISTENCE_FILE_PREFIX "OmniB3_State_"

// Versão do formato de persistência (para compatibilidade)
#define PERSISTENCE_FORMAT_VERSION 1

//+------------------------------------------------------------------+
//| ENUMERAÇÕES — Sistema de Indicadores                             |
//+------------------------------------------------------------------+

// Indicadores de sinal de entrada disponíveis
// Cada indicador retorna: +1 (compra), -1 (venda), 0 (neutro)
enum ENUM_INDICATOR_SIGNAL {
    OB3_IND_NONE,               // Nenhum — abre sem indicador
    OB3_IND_RSI,                // RSI — Sobrecompra/Sobrevenda
    OB3_IND_CCI,                // CCI — Commodity Channel Index
    OB3_IND_BOLLINGER,          // Bollinger Bands — Toque nas bandas
    OB3_IND_ENVELOPES,          // Envelopes — Desvio percentual da média
    OB3_IND_MOVING_AVERAGES,    // Médias Móveis — Cruzamento rápida/lenta
    OB3_IND_VWAP,               // VWAP — Volume Weighted Average Price
    OB3_IND_HILO,               // HILO — High-Low Activator
    OB3_IND_PIVOT_POINT,        // Pivot Point — Suporte e Resistência
    OB3_IND_ATR_SIGNAL,         // ATR — Sinal por volatilidade
    OB3_IND_ADX_SIGNAL,         // ADX — Força da tendência
    OB3_IND_CANDLE_SEQUENCE,    // Sequência de Candles — Padrão direcional
    OB3_IND_PRICE_GAP           // GAP no Preço — Diferença entre candles
};

// Estratégia de compra/venda para cada indicador
enum ENUM_INDICATOR_STRATEGY {
    STRAT_DISABLED,         // Desabilitado
    STRAT_STANDARD,         // Padrão — lógica original do indicador
    STRAT_REVERSE,          // Reverso — inverte o sinal
    STRAT_FILTER_ONLY       // Apenas Filtro — não gera sinal, só filtra
};

//+------------------------------------------------------------------+
//| ENUMERAÇÕES — Filtros de Indicadores                             |
//+------------------------------------------------------------------+

// Filtros que NÃO geram sinal, apenas bloqueiam abertura
enum ENUM_INDICATOR_FILTER {
    FILTER_NONE,            // Nenhum filtro
    FILTER_ADX,             // Filtro ADX — mínimo de força
    FILTER_ATR,             // Filtro ATR — faixa de volatilidade
    FILTER_VOLUME,          // Filtro Volume — volume mínimo
    FILTER_CANDLE_SIZE,     // Filtro Tamanho Candle — corpo mínimo/máximo
    FILTER_PRICE_GAP,       // Filtro GAP — distância mínima entre preços
    FILTER_BOLLINGER,       // Filtro Bollinger — dentro/fora das bandas
    FILTER_ENVELOPES        // Filtro Envelopes — dentro/fora dos envelopes
};

//+------------------------------------------------------------------+
//| ENUMERAÇÕES — Grade (Grid)                                       |
//+------------------------------------------------------------------+

// Tipo de espaçamento da grade
enum ENUM_GRID_TYPE {
    GRID_FIXED,             // Grade Fixa — espaçamento constante em pontos
    GRID_DYNAMIC_ATR        // Grade Dinâmica — espaçamento baseado no ATR
};

// Direção da grade (NETTING: sem bi-direcional simultâneo)
enum ENUM_GRID_DIRECTION {
    GRID_BUY_ONLY,          // Apenas Compra — grade de compra (média para baixo)
    GRID_SELL_ONLY          // Apenas Venda — grade de venda (média para cima)
};

// Modo de gerenciamento de lotes (volume em contratos inteiros)
enum ENUM_LOT_MODE {
    LOT_FIXED,              // Fixo — mesmo volume em todos os níveis
    LOT_MULTIPLIER          // Multiplicador — Vol_n = Vol₀ × Mult^(n-1)
};

// Modo de cálculo do próximo lote da grid
enum ENUM_NEXT_LOT_MODE {
    NEXT_LOT_FIXED,         // Fixo — sempre o mesmo lote
    NEXT_LOT_MULTIPLY,      // Multiplicar — lote × fator a cada nível
    NEXT_LOT_ADD,           // Somar — lote + incremento a cada nível
    NEXT_LOT_WAIT_MULTIPLY, // Aguardar + Multiplicar — espera tempo entre ordens
    NEXT_LOT_WAIT_ADD       // Aguardar + Somar — espera tempo entre ordens
};

//+------------------------------------------------------------------+
//| ENUMERAÇÕES — Smart Close / Fechamento                           |
//+------------------------------------------------------------------+

// Alvo do Smart Close (qual nível fechar)
enum ENUM_CLOSE_TARGET {
    CLOSE_WORST,            // Pior Nível — maior prejuízo virtual
    CLOSE_OLDEST            // Mais Antigo — primeiro nível da grade
};

// Modos de fechamento da grade (expandido do ToTheMoon)
enum ENUM_CLOSE_MODE {
    CMODE_SMART_WORST,      // Smart Close — fecha pior nível com lucro dos demais
    CMODE_SMART_OLDEST,     // Smart Close — fecha mais antigo com lucro dos demais
    CMODE_TP_TOTAL,         // TakeProfit Total — fecha tudo quando P&L total > TP
    CMODE_TP_MONETARY,      // TakeProfit Monetário — fecha quando lucro > R$ X
    CMODE_HALF_CLOSE,       // Fechar Metade — fecha 50% dos lucrativos
    CMODE_LOT_SUM_TOTAL,    // Soma de Lotes — fecha quando lote total > limite
    CMODE_LOT_SUM_HALF,     // Soma de Lotes (metade) — fecha 50% se lote > limite
    CMODE_LOT_AVG_TOTAL,    // Média de Lotes — fecha quando média > limite
    CMODE_ORDER_COUNT,      // Qtde Ordens — fecha quando qtde > limite
    CMODE_ORDER_COUNT_HALF, // Qtde Ordens (metade) — fecha 50% se qtde > limite
    CMODE_ACCEPT_LOSS,      // Aceitar Prejuízo — fecha com perda se DD baixo
    CMODE_BREAKEVEN         // BreakEven — fecha quando preço atinge média ± margem
};

//+------------------------------------------------------------------+
//| ENUMERAÇÕES — TakeProfit Avançado                                |
//+------------------------------------------------------------------+

// Modo do TakeProfit
enum ENUM_TP_MODE {
    TP_FIXED_POINTS,        // Fixo em pontos
    TP_ATR_BASED,           // Baseado no ATR
    TP_MONETARY             // Valor monetário (BRL)
};

// Modo de redução do TakeProfit com o tempo
enum ENUM_TP_REDUCE_TYPE {
    TP_REDUCE_NONE,         // Sem redução
    TP_REDUCE_BY_TIME,      // Reduzir por tempo (minutos)
    TP_REDUCE_BY_DD,        // Reduzir por drawdown (%)
    TP_REDUCE_BY_SEARCH     // Reduzir quando preço se aproxima
};

//+------------------------------------------------------------------+
//| ENUMERAÇÕES — BreakEven                                          |
//+------------------------------------------------------------------+

// Modo do BreakEven
enum ENUM_BE_MODE {
    BE_DISABLED,            // Desabilitado
    BE_FIXED_POINTS,        // Fixo em pontos
    BE_ATR_BASED            // Baseado no ATR
};

// Tipo do BreakEven
enum ENUM_BE_TYPE {
    BE_STATIC,              // Estático — move SL para entrada e para
    BE_TRAILING             // Trailing — segue o preço com distância
};

//+------------------------------------------------------------------+
//| ENUMERAÇÕES — Perfil e Gestão                                    |
//+------------------------------------------------------------------+

// Perfis de risco pré-configurados para B3
enum ENUM_RISK_PROFILE {
    PROFILE_CONSERVADOR,    // Conservador — poucos níveis, sem multiplicador
    PROFILE_MODERADO,       // Moderado — mais níveis, multiplicador leve
    PROFILE_AGRESSIVO,      // Agressivo — muitos níveis, multiplicador alto
    PROFILE_CUSTOM          // Personalizado — usuário define tudo
};

// Modo de cálculo do saldo do robô
enum ENUM_BALANCE_MODE {
    BAL_FULL_ACCOUNT,       // Saldo Total — usa todo o saldo da conta
    BAL_PERCENTAGE,         // Porcentagem — % do saldo da conta
    BAL_FIXED_VALUE         // Valor Fixo — valor fixo em BRL
};

// Modo do preset multiplier (xPreset)
enum ENUM_PRESET_MODE {
    PRESET_DISABLED,        // Desabilitado — usa lotes fixos
    PRESET_BY_BALANCE,      // Por Saldo — ajusta lotes pelo saldo
    PRESET_BY_EQUITY        // Por Capital Líquido — ajusta pelo equity
};

// Níveis de log
enum ENUM_LOG_LEVEL {
    LOG_DEBUG,              // Debug — tudo (muito verboso)
    LOG_INFO,               // Info — operações normais
    LOG_WARNING,            // Aviso — situações anormais
    LOG_ERROR,              // Erro — falhas de operação
    LOG_CRITICAL            // Crítico — falhas graves
};

// Modo de redução por tempo para fechamento
enum ENUM_TIME_REDUCE_TYPE {
    TIME_REDUCE_NONE,       // Sem redução
    TIME_REDUCE_TP,         // Reduzir apenas TakeProfit
    TIME_REDUCE_TP_BE,      // Reduzir TakeProfit e BreakEven
    TIME_REDUCE_ALL         // Reduzir TakeProfit, BreakEven e Monetário
};

// Modo de fechamento no horário limite
enum ENUM_TIME_CLOSE_MODE {
    TCLOSE_NONE,            // Não fechar — manter posição aberta
    TCLOSE_IMMEDIATE,       // Fechar imediatamente — a mercado
    TCLOSE_IF_PROFIT,       // Fechar só se lucrativo
    TCLOSE_REDUCE_TP        // Reduzir TP e aguardar
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
    double   entry_price;       // Preço de entrada deste nível
    double   volume;            // Volume em contratos
    int      direction;         // +1 = compra, -1 = venda
    int      level_index;       // Índice do nível (0, 1, 2, ...)
    datetime open_time;         // Data/hora de abertura
    bool     is_active;         // Se está ativo
    bool     is_recovery;       // Se foi aberto em modo recovery
    double   accumulated_profit;// Lucro acumulado neste nível (para tracking)
    datetime last_update_time;  // Última atualização do P&L

    // Inicializa zerado
    void Reset() {
        entry_price       = 0.0;
        volume            = 0.0;
        direction         = 0;
        level_index       = 0;
        open_time         = 0;
        is_active         = false;
        is_recovery       = false;
        accumulated_profit = 0.0;
        last_update_time  = 0;
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
    int     total_levels;           // Níveis virtuais ativos
    double  total_volume;           // Volume total em contratos
    double  total_profit;           // P&L total virtual em BRL
    double  avg_price;              // Preço médio ponderado
    double  worst_profit;           // Pior P&L individual
    int     worst_index;            // Índice do pior nível no array
    double  worst_volume;           // Volume do pior nível
    double  best_profit;            // Melhor P&L individual
    int     best_index;             // Índice do melhor nível
    double  positive_profit_sum;    // Soma dos P&L positivos
    int     positive_count;         // Quantidade de níveis lucrativos
    int     negative_count;         // Quantidade de níveis perdedores
    double  max_drawdown_pct;       // Drawdown % da grade
    datetime oldest_level_time;     // Tempo do nível mais antigo

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
        positive_count      = 0;
        negative_count      = 0;
        max_drawdown_pct    = 0.0;
        oldest_level_time   = 0;
    }
};

//+------------------------------------------------------------------+
//| ESTRUTURA — Configuração de Indicador                            |
//+------------------------------------------------------------------+
struct SIndicatorConfig {
    ENUM_INDICATOR_SIGNAL   type;       // Tipo do indicador
    ENUM_INDICATOR_STRATEGY strategy;   // Estratégia (padrão, reverso, filtro)
    int                     period;     // Período principal
    ENUM_TIMEFRAMES         timeframe;  // Timeframe
    int                     price_type; // Tipo de preço (PRICE_CLOSE, etc.)
    double                  param1;     // Parâmetro extra 1 (ex: nível superior)
    double                  param2;     // Parâmetro extra 2 (ex: nível inferior)
    double                  param3;     // Parâmetro extra 3 (ex: desvio)

    void Reset() {
        type      = OB3_IND_NONE;
        strategy  = STRAT_DISABLED;
        period    = 14;
        timeframe = PERIOD_CURRENT;
        price_type = 1; // PRICE_CLOSE
        param1    = 0.0;
        param2    = 0.0;
        param3    = 0.0;
    }
};

//+------------------------------------------------------------------+
//| ESTRUTURA — Resultado diário para tracking                       |
//+------------------------------------------------------------------+
struct SDailyResult {
    datetime date;              // Data do dia
    double   profit;            // Lucro total do dia
    double   max_dd;            // Drawdown máximo do dia
    int      total_orders;      // Total de ordens do dia
    int      winning_orders;    // Ordens ganhadoras
    int      losing_orders;     // Ordens perdedoras

    void Reset() {
        date           = 0;
        profit         = 0.0;
        max_dd         = 0.0;
        total_orders   = 0;
        winning_orders = 0;
        losing_orders  = 0;
    }
};

//+------------------------------------------------------------------+
//| ENUMERAÇÕES — Modo Ordem Única (Single Order)                    |
//+------------------------------------------------------------------+

// Modo de operação: Grade tradicional ou Ordem Única
enum ENUM_SINGLE_ORDER_MODE {
    SINGLE_DISABLED,        // Grade Tradicional — abre novos níveis virtuais
    SINGLE_ENABLED          // Ordem Única — apenas uma ordem por vez com SL/TP
};

// Modo de Martingale em sequência de trades (para Ordem Única)
enum ENUM_MARTINGALE_MODE {
    MARTINGALE_NONE,        // Sem martingale — lotes sempre iguais ao inicial
    MARTINGALE_STANDARD,    // Martingale — multiplica lote após perda
    ANTI_MARTINGALE         // Anti-Martingale — multiplica lote após ganho
};

//+------------------------------------------------------------------+
//| ENUMERAÇÕES — Filtro de Notícias (News Filter)                   |
//+------------------------------------------------------------------+

// Importância das notícias no calendário econômico
enum ENUM_NEWS_IMPORTANCE {
    NEWS_IMPORTANCE_NONE,   // Desabilitado
    NEWS_IMPORTANCE_LOW,    // Baixo impacto
    NEWS_IMPORTANCE_MEDIUM, // Médio impacto
    NEWS_IMPORTANCE_HIGH,   // Alto impacto (2 ou 3 estrelas)
    NEWS_IMPORTANCE_ALL     // Qualquer impacto
};

// Ação do robô durante período de notícias bloqueadas
enum ENUM_NEWS_ACTION {
    NEWS_ACTION_NONE,           // Nenhuma ação
    NEWS_ACTION_STOP_ALL,       // Bloquear Tudo — não abre ordem inicial nem novas grades
    NEWS_ACTION_STOP_INITIAL,   // Bloquear Inicial — não abre nova série, mas permite grade gerenciar
    NEWS_ACTION_CLOSE_ALL       // Fechar Tudo — fecha posições e limpa ordens pendentes
};

//+------------------------------------------------------------------+
//| CONSTANTES E ENUMS — Dashboard Visual                            |
//+------------------------------------------------------------------+

// Paleta de cores para o dashboard
enum ENUM_DASHBOARD_THEME {
    THEME_DARK_MODERN,      // Moderno Escuro (preto/cinza e azul néon)
    THEME_LIGHT_CLEAN,      // Limpo Claro (branco e azul suave)
    THEME_GLASSMORPHISM     // Glassmorphism translúcido
};

// Estrutura para estado das notícias no dashboard
struct SNewsState {
    string   event_name;    // Nome do evento econômico
    datetime event_time;    // Hora do evento
    string   currency;      // Moeda do evento
    int      importance;    // Nível de importância (1, 2, 3)
    int      seconds_to;    // Segundos para o evento (negativo se já passou)
    bool     is_active;     // Se está ativo no momento

    void Clear() {
        event_name = "";
        event_time = 0;
        currency = "";
        importance = 0;
        seconds_to = 0;
        is_active = false;
    }
};

//+------------------------------------------------------------------+

