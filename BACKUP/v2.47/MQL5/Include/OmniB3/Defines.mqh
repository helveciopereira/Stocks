//+------------------------------------------------------------------+
//|                                                     Defines.mqh  |
//|                         Omni-B3 EA v2.47 â€” DefiniÃ§Ãµes Centrais    |
//|          Adaptado para B3 (NETTING) â€” Minicontratos WIN/WDO      |
//|  VersÃ£o 2.47 com Painel de OperaÃ§Ãµes Recentes e Desenhos GrÃ¡ficos |
//+------------------------------------------------------------------+
#property copyright "Projeto Omni-B3"
#property link      "https://github.com/helveciopereira/Stocks"
#property version     "2.47"
#property strict

//+------------------------------------------------------------------+
//| CONSTANTES GLOBAIS DO SISTEMA                                    |
//+------------------------------------------------------------------+
#define OMNIB3_VERSION        "2.47"
#define OMNIB3_COMMENT_PREFIX "OmniB3"

// Limite absoluto de nÃ­veis de grade (trava inviolÃ¡vel de seguranÃ§a)
#define GRID_MAX_ABSOLUTE     20

// MÃ¡ximo de sÃ­mbolos simultÃ¢neos no modo Multi-Ativos
#define MAX_SYMBOLS           6

// Cooldown em segundos entre execuÃ§Ãµes do Smart Close
#define SMART_CLOSE_COOLDOWN  5

// Margem de seguranÃ§a padrÃ£o em ticks para o Smart Close
// Para WIN: 1 tick = 5 pontos = R$1,00 por contrato
#define SMART_CLOSE_MARGIN_TICKS 3.0

// Spread mÃ¡ximo em pontos para abrir ordens
// WIN costuma ter spread de 5-15 pontos
#define MAX_SPREAD_POINTS     30

// Intervalo de auto-save do estado em segundos
#define PERSISTENCE_INTERVAL  30

// MÃ¡ximo de indicadores de confirmaÃ§Ã£o
#define MAX_CONFIRMATIONS     4

// Nome do arquivo de persistÃªncia de estado
#define PERSISTENCE_FILE_PREFIX "OmniB3_State_"

// VersÃ£o do formato de persistÃªncia (para compatibilidade)
#define PERSISTENCE_FORMAT_VERSION 1

//+------------------------------------------------------------------+
//| ENUMERAÃ‡Ã•ES â€” Sistema de Indicadores                             |
//+------------------------------------------------------------------+

// Indicadores de sinal de entrada disponÃ­veis
// Cada indicador retorna: +1 (compra), -1 (venda), 0 (neutro)
enum ENUM_INDICATOR_SIGNAL {
    OB3_IND_NONE,               // Nenhum â€” abre sem indicador
    OB3_IND_RSI,                // RSI â€” Sobrecompra/Sobrevenda
    OB3_IND_CCI,                // CCI â€” Commodity Channel Index
    OB3_IND_BOLLINGER,          // Bollinger Bands â€” Toque nas bandas
    OB3_IND_ENVELOPES,          // Envelopes â€” Desvio percentual da mÃ©dia
    OB3_IND_MOVING_AVERAGES,    // MÃ©dias MÃ³veis â€” Cruzamento rÃ¡pida/lenta
    OB3_IND_VWAP,               // VWAP â€” Volume Weighted Average Price
    OB3_IND_HILO,               // HILO â€” High-Low Activator
    OB3_IND_PIVOT_POINT,        // Pivot Point â€” Suporte e ResistÃªncia
    OB3_IND_ATR_SIGNAL,         // ATR â€” Sinal por volatilidade
    OB3_IND_ADX_SIGNAL,         // ADX â€” ForÃ§a da tendÃªncia
    OB3_IND_CANDLE_SEQUENCE,    // SequÃªncia de Candles â€” PadrÃ£o direcional
    OB3_IND_PRICE_GAP           // GAP no PreÃ§o â€” DiferenÃ§a entre candles
};

// EstratÃ©gia de compra/venda para cada indicador
enum ENUM_INDICATOR_STRATEGY {
    STRAT_DISABLED,         // Desabilitado
    STRAT_STANDARD,         // PadrÃ£o â€” lÃ³gica original do indicador
    STRAT_REVERSE,          // Reverso â€” inverte o sinal
    STRAT_FILTER_ONLY       // Apenas Filtro â€” nÃ£o gera sinal, sÃ³ filtra
};

//+------------------------------------------------------------------+
//| ENUMERAÃ‡Ã•ES â€” Filtros de Indicadores                             |
//+------------------------------------------------------------------+

// Filtros que NÃƒO geram sinal, apenas bloqueiam abertura
enum ENUM_INDICATOR_FILTER {
    FILTER_NONE,            // Nenhum filtro
    FILTER_ADX,             // Filtro ADX â€” mÃ­nimo de forÃ§a
    FILTER_ATR,             // Filtro ATR â€” faixa de volatilidade
    FILTER_VOLUME,          // Filtro Volume â€” volume mÃ­nimo
    FILTER_CANDLE_SIZE,     // Filtro Tamanho Candle â€” corpo mÃ­nimo/mÃ¡ximo
    FILTER_PRICE_GAP,       // Filtro GAP â€” distÃ¢ncia mÃ­nima entre preÃ§os
    FILTER_BOLLINGER,       // Filtro Bollinger â€” dentro/fora das bandas
    FILTER_ENVELOPES        // Filtro Envelopes â€” dentro/fora dos envelopes
};

//+------------------------------------------------------------------+
//| ENUMERAÃ‡Ã•ES â€” Grade (Grid)                                       |
//+------------------------------------------------------------------+

// Tipo de espaÃ§amento da grade
enum ENUM_GRID_TYPE {
    GRID_FIXED,             // Grade Fixa â€” espaÃ§amento constante em pontos
    GRID_DYNAMIC_ATR        // Grade DinÃ¢mica â€” espaÃ§amento baseado no ATR
};

// DireÃ§Ã£o da grade (NETTING: sem bi-direcional simultÃ¢neo)
enum ENUM_GRID_DIRECTION {
    GRID_BUY_ONLY,          // Apenas Compra â€” grade de compra (mÃ©dia para baixo)
    GRID_SELL_ONLY          // Apenas Venda â€” grade de venda (mÃ©dia para cima)
};

// Modo de gerenciamento de lotes (volume em contratos inteiros)
enum ENUM_LOT_MODE {
    LOT_FIXED,              // Fixo â€” mesmo volume em todos os nÃ­veis
    LOT_MULTIPLIER          // Multiplicador â€” Vol_n = Volâ‚€ Ã— Mult^(n-1)
};

// Modo de cÃ¡lculo do prÃ³ximo lote da grid
enum ENUM_NEXT_LOT_MODE {
    NEXT_LOT_FIXED,         // Fixo â€” sempre o mesmo lote
    NEXT_LOT_MULTIPLY,      // Multiplicar â€” lote Ã— fator a cada nÃ­vel
    NEXT_LOT_ADD,           // Somar â€” lote + incremento a cada nÃ­vel
    NEXT_LOT_WAIT_MULTIPLY, // Aguardar + Multiplicar â€” espera tempo entre ordens
    NEXT_LOT_WAIT_ADD       // Aguardar + Somar â€” espera tempo entre ordens
};

//+------------------------------------------------------------------+
//| ENUMERAÃ‡Ã•ES â€” Smart Close / Fechamento                           |
//+------------------------------------------------------------------+

// Alvo do Smart Close (qual nÃ­vel fechar)
enum ENUM_CLOSE_TARGET {
    CLOSE_WORST,            // Pior NÃ­vel â€” maior prejuÃ­zo virtual
    CLOSE_OLDEST            // Mais Antigo â€” primeiro nÃ­vel da grade
};

// Modos de fechamento da grade (expandido do ToTheMoon)
enum ENUM_CLOSE_MODE {
    CMODE_SMART_WORST,      // Smart Close â€” fecha pior nÃ­vel com lucro dos demais
    CMODE_SMART_OLDEST,     // Smart Close â€” fecha mais antigo com lucro dos demais
    CMODE_TP_TOTAL,         // TakeProfit Total â€” fecha tudo quando P&L total > TP
    CMODE_TP_MONETARY,      // TakeProfit MonetÃ¡rio â€” fecha quando lucro > R$ X
    CMODE_HALF_CLOSE,       // Fechar Metade â€” fecha 50% dos lucrativos
    CMODE_LOT_SUM_TOTAL,    // Soma de Lotes â€” fecha quando lote total > limite
    CMODE_LOT_SUM_HALF,     // Soma de Lotes (metade) â€” fecha 50% se lote > limite
    CMODE_LOT_AVG_TOTAL,    // MÃ©dia de Lotes â€” fecha quando mÃ©dia > limite
    CMODE_ORDER_COUNT,      // Qtde Ordens â€” fecha quando qtde > limite
    CMODE_ORDER_COUNT_HALF, // Qtde Ordens (metade) â€” fecha 50% se qtde > limite
    CMODE_ACCEPT_LOSS,      // Aceitar PrejuÃ­zo â€” fecha com perda se DD baixo
    CMODE_BREAKEVEN         // BreakEven â€” fecha quando preÃ§o atinge mÃ©dia Â± margem
};

//+------------------------------------------------------------------+
//| ENUMERAÃ‡Ã•ES â€” TakeProfit AvanÃ§ado                                |
//+------------------------------------------------------------------+

// Modo do TakeProfit
enum ENUM_TP_MODE {
    TP_FIXED_POINTS,        // Fixo em pontos
    TP_ATR_BASED,           // Baseado no ATR
    TP_MONETARY             // Valor monetÃ¡rio (BRL)
};

// Modo de reduÃ§Ã£o do TakeProfit com o tempo
enum ENUM_TP_REDUCE_TYPE {
    TP_REDUCE_NONE,         // Sem reduÃ§Ã£o
    TP_REDUCE_BY_TIME,      // Reduzir por tempo (minutos)
    TP_REDUCE_BY_DD,        // Reduzir por drawdown (%)
    TP_REDUCE_BY_SEARCH     // Reduzir quando preÃ§o se aproxima
};

//+------------------------------------------------------------------+
//| ENUMERAÃ‡Ã•ES â€” BreakEven                                          |
//+------------------------------------------------------------------+

// Modo do BreakEven
enum ENUM_BE_MODE {
    BE_DISABLED,            // Desabilitado
    BE_FIXED_POINTS,        // Fixo em pontos
    BE_ATR_BASED            // Baseado no ATR
};

// Tipo do BreakEven
enum ENUM_BE_TYPE {
    BE_STATIC,              // EstÃ¡tico â€” move SL para entrada e para
    BE_TRAILING             // Trailing â€” segue o preÃ§o com distÃ¢ncia
};

//+------------------------------------------------------------------+
//| ENUMERAÃ‡Ã•ES â€” Perfil e GestÃ£o                                    |
//+------------------------------------------------------------------+

// Perfis de risco prÃ©-configurados para B3
enum ENUM_RISK_PROFILE {
    PROFILE_CONSERVADOR,    // Conservador â€” poucos nÃ­veis, sem multiplicador
    PROFILE_MODERADO,       // Moderado â€” mais nÃ­veis, multiplicador leve
    PROFILE_AGRESSIVO,      // Agressivo â€” muitos nÃ­veis, multiplicador alto
    PROFILE_CUSTOM          // Personalizado â€” usuÃ¡rio define tudo
};

// Modo de cÃ¡lculo do saldo do robÃ´
enum ENUM_BALANCE_MODE {
    BAL_FULL_ACCOUNT,       // Saldo Total â€” usa todo o saldo da conta
    BAL_PERCENTAGE,         // Porcentagem â€” % do saldo da conta
    BAL_FIXED_VALUE         // Valor Fixo â€” valor fixo em BRL
};

// Modo do preset multiplier (xPreset)
enum ENUM_PRESET_MODE {
    PRESET_DISABLED,        // Desabilitado â€” usa lotes fixos
    PRESET_BY_BALANCE,      // Por Saldo â€” ajusta lotes pelo saldo
    PRESET_BY_EQUITY        // Por Capital LÃ­quido â€” ajusta pelo equity
};

// NÃ­veis de log
enum ENUM_LOG_LEVEL {
    LOG_DEBUG,              // Debug â€” tudo (muito verboso)
    LOG_INFO,               // Info â€” operaÃ§Ãµes normais
    LOG_WARNING,            // Aviso â€” situaÃ§Ãµes anormais
    LOG_ERROR,              // Erro â€” falhas de operaÃ§Ã£o
    LOG_CRITICAL            // CrÃ­tico â€” falhas graves
};

// Modo de reduÃ§Ã£o por tempo para fechamento
enum ENUM_TIME_REDUCE_TYPE {
    TIME_REDUCE_NONE,       // Sem reduÃ§Ã£o
    TIME_REDUCE_TP,         // Reduzir apenas TakeProfit
    TIME_REDUCE_TP_BE,      // Reduzir TakeProfit e BreakEven
    TIME_REDUCE_ALL         // Reduzir TakeProfit, BreakEven e MonetÃ¡rio
};

// Modo de fechamento no horÃ¡rio limite
enum ENUM_TIME_CLOSE_MODE {
    TCLOSE_NONE,            // NÃ£o fechar â€” manter posiÃ§Ã£o aberta
    TCLOSE_IMMEDIATE,       // Fechar imediatamente â€” a mercado
    TCLOSE_IF_PROFIT,       // Fechar sÃ³ se lucrativo
    TCLOSE_REDUCE_TP        // Reduzir TP e aguardar
};

//+------------------------------------------------------------------+
//| ESTRUTURA â€” NÃ­vel Virtual da Grade                               |
//|                                                                   |
//| Em contas NETTING existe apenas 1 posiÃ§Ã£o por sÃ­mbolo. Para      |
//| rastrear cada nÃ­vel da grade individualmente, mantemos um array  |
//| interno de "nÃ­veis virtuais" com preÃ§o de entrada e volume.      |
//| O P&L de cada nÃ­vel Ã© calculado em tempo real.                   |
//+------------------------------------------------------------------+
struct SVirtualLevel {
    double   entry_price;       // PreÃ§o de entrada deste nÃ­vel
    double   volume;            // Volume em contratos
    int      direction;         // +1 = compra, -1 = venda
    int      level_index;       // Ãndice do nÃ­vel (0, 1, 2, ...)
    datetime open_time;         // Data/hora de abertura
    bool     is_active;         // Se estÃ¡ ativo
    bool     is_recovery;       // Se foi aberto em modo recovery
    double   accumulated_profit;// Lucro acumulado neste nÃ­vel (para tracking)
    datetime last_update_time;  // Ãšltima atualizaÃ§Ã£o do P&L

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

    // Calcula P&L virtual deste nÃ­vel em moeda da conta (BRL)
    // current_price: preÃ§o atual (bid para compra, ask para venda)
    // tick_size: SYMBOL_TRADE_TICK_SIZE (ex: 5 para WIN)
    // tick_value: SYMBOL_TRADE_TICK_VALUE (ex: 1.00 para WIN)
    double CalculateProfit(double current_price, double tick_size, double tick_value) {
        if(!is_active || tick_size <= 0.0) return 0.0;
        double price_diff = direction * (current_price - entry_price);
        return (price_diff / tick_size) * tick_value * volume;
    }
};

//+------------------------------------------------------------------+
//| ESTRUTURA â€” Estado Consolidado da Grade                          |
//+------------------------------------------------------------------+
struct SGridState {
    string  symbol;
    int     total_levels;           // NÃ­veis virtuais ativos
    double  total_volume;           // Volume total em contratos
    double  total_profit;           // P&L total virtual em BRL
    double  avg_price;              // PreÃ§o mÃ©dio ponderado
    double  worst_profit;           // Pior P&L individual
    int     worst_index;            // Ãndice do pior nÃ­vel no array
    double  worst_volume;           // Volume do pior nÃ­vel
    double  best_profit;            // Melhor P&L individual
    int     best_index;             // Ãndice do melhor nÃ­vel
    double  positive_profit_sum;    // Soma dos P&L positivos
    int     positive_count;         // Quantidade de nÃ­veis lucrativos
    int     negative_count;         // Quantidade de nÃ­veis perdedores
    double  max_drawdown_pct;       // Drawdown % da grade
    datetime oldest_level_time;     // Tempo do nÃ­vel mais antigo

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
//| ESTRUTURA â€” ConfiguraÃ§Ã£o de Indicador                            |
//+------------------------------------------------------------------+
struct SIndicatorConfig {
    ENUM_INDICATOR_SIGNAL   type;       // Tipo do indicador
    ENUM_INDICATOR_STRATEGY strategy;   // EstratÃ©gia (padrÃ£o, reverso, filtro)
    int                     period;     // PerÃ­odo principal
    ENUM_TIMEFRAMES         timeframe;  // Timeframe
    int                     price_type; // Tipo de preÃ§o (PRICE_CLOSE, etc.)
    double                  param1;     // ParÃ¢metro extra 1 (ex: nÃ­vel superior)
    double                  param2;     // ParÃ¢metro extra 2 (ex: nÃ­vel inferior)
    double                  param3;     // ParÃ¢metro extra 3 (ex: desvio)

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
//| ESTRUTURA â€” Resultado diÃ¡rio para tracking                       |
//+------------------------------------------------------------------+
struct SDailyResult {
    datetime date;              // Data do dia
    double   profit;            // Lucro total do dia
    double   max_dd;            // Drawdown mÃ¡ximo do dia
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
//| ENUMERAÃ‡Ã•ES â€” Modo Ordem Ãšnica (Single Order)                    |
//+------------------------------------------------------------------+

// Modo de operaÃ§Ã£o: Grade tradicional ou Ordem Ãšnica
enum ENUM_SINGLE_ORDER_MODE {
    SINGLE_DISABLED,        // Grade Tradicional â€” abre novos nÃ­veis virtuais
    SINGLE_ENABLED          // Ordem Ãšnica â€” apenas uma ordem por vez com SL/TP
};

// Modo de Martingale em sequÃªncia de trades (para Ordem Ãšnica)
enum ENUM_MARTINGALE_MODE {
    MARTINGALE_NONE,        // Sem martingale â€” lotes sempre iguais ao inicial
    MARTINGALE_STANDARD,    // Martingale â€” multiplica lote apÃ³s perda
    ANTI_MARTINGALE         // Anti-Martingale â€” multiplica lote apÃ³s ganho
};

//+------------------------------------------------------------------+
//| ENUMERAÃ‡Ã•ES â€” Filtro de NotÃ­cias (News Filter)                   |
//+------------------------------------------------------------------+

// ImportÃ¢ncia das notÃ­cias no calendÃ¡rio econÃ´mico
enum ENUM_NEWS_IMPORTANCE {
    NEWS_IMPORTANCE_NONE,   // Desabilitado
    NEWS_IMPORTANCE_LOW,    // Baixo impacto
    NEWS_IMPORTANCE_MEDIUM, // MÃ©dio impacto
    NEWS_IMPORTANCE_HIGH,   // Alto impacto (2 ou 3 estrelas)
    NEWS_IMPORTANCE_ALL     // Qualquer impacto
};

// AÃ§Ã£o do robÃ´ durante perÃ­odo de notÃ­cias bloqueadas
enum ENUM_NEWS_ACTION {
    NEWS_ACTION_NONE,           // Nenhuma aÃ§Ã£o
    NEWS_ACTION_STOP_ALL,       // Bloquear Tudo â€” nÃ£o abre ordem inicial nem novas grades
    NEWS_ACTION_STOP_INITIAL,   // Bloquear Inicial â€” nÃ£o abre nova sÃ©rie, mas permite grade gerenciar
    NEWS_ACTION_CLOSE_ALL       // Fechar Tudo â€” fecha posiÃ§Ãµes e limpa ordens pendentes
};

//+------------------------------------------------------------------+
//| CONSTANTES E ENUMS â€” Dashboard Visual                            |
//+------------------------------------------------------------------+

// Paleta de cores para o dashboard
enum ENUM_DASHBOARD_THEME {
    THEME_DARK_MODERN,      // Moderno Escuro (preto/cinza e azul nÃ©on)
    THEME_LIGHT_CLEAN,      // Limpo Claro (branco e azul suave)
    THEME_GLASSMORPHISM     // Glassmorphism translÃºcido
};

// Estrutura para estado das notÃ­cias no dashboard
struct SNewsState {
    string   event_name;    // Nome do evento econÃ´mico
    datetime event_time;    // Hora do evento
    string   currency;      // Moeda do evento
    int      importance;    // NÃ­vel de importÃ¢ncia (1, 2, 3)
    int      seconds_to;    // Segundos para o evento (negativo se jÃ¡ passou)
    bool     is_active;     // Se estÃ¡ ativo no momento

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

