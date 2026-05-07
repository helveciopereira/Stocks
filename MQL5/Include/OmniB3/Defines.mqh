//+------------------------------------------------------------------+
//|                                                     Defines.mqh  |
//|                         Omni-B3 EA v1.0 — Definições Centrais    |
//|          Enumerações, Estruturas e Constantes do Ecossistema      |
//+------------------------------------------------------------------+
#property copyright "Projeto Omni-B3"
#property link      "https://github.com/seu-usuario/Stocks"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| CONSTANTES GLOBAIS DO SISTEMA                                    |
//+------------------------------------------------------------------+

// Versão do EA para rastreabilidade em logs e comentários de ordens
#define OMNIB3_VERSION        "1.0.0"

// Prefixo usado nos comentários das ordens para identificação
#define OMNIB3_COMMENT_PREFIX "OmniB3"

// Limite físico absoluto de níveis de grade (trava de segurança final)
// Mesmo que o usuário configure mais, este é o teto inviolável
#define GRID_MAX_ABSOLUTE     10

// Número máximo de símbolos que o EA pode gerenciar simultaneamente
#define MAX_SYMBOLS           6

// Cooldown em segundos entre execuções do Smart Close
// Evita loops de fechamento em ticks consecutivos
#define SMART_CLOSE_COOLDOWN  5

// Margem de segurança padrão em pontos para o gatilho do Smart Close
// Representa o "colchão" extra além do breakeven para garantir lucro
#define SMART_CLOSE_MARGIN_POINTS 3.0

// Spread máximo permitido (em pontos) para abrir novas ordens
// Protege contra abertura em momentos de spread muito alto
#define MAX_SPREAD_POINTS     50

//+------------------------------------------------------------------+
//| ENUMERAÇÕES — Tipos de Grade                                     |
//+------------------------------------------------------------------+

// Define como o espaçamento entre os níveis da grade é calculado
enum ENUM_GRID_TYPE {
    GRID_FIXED,         // Grade Fixa — espaçamento constante em pontos
    GRID_DYNAMIC_ATR    // Grade Dinâmica — espaçamento baseado no ATR
};

//+------------------------------------------------------------------+
//| ENUMERAÇÕES — Direção da Grade                                   |
//+------------------------------------------------------------------+

// Define em qual direção o EA pode abrir ordens de grade
enum ENUM_GRID_DIRECTION {
    GRID_BUY_ONLY,      // Apenas Compra — grade unidirecional de compra
    GRID_SELL_ONLY,      // Apenas Venda — grade unidirecional de venda
    GRID_BIDIRECTIONAL   // Bi-direcional — compra E venda simultâneas
};

//+------------------------------------------------------------------+
//| ENUMERAÇÕES — Modo de Gerenciamento de Lotes                     |
//+------------------------------------------------------------------+

// Define como o tamanho do lote evolui a cada nível da grade
enum ENUM_LOT_MODE {
    LOT_FIXED,           // Lote Fixo — mesmo volume em todos os níveis
    LOT_MULTIPLIER       // Multiplicador — Lote_n = Lote₀ × Mult^(n-1)
};

//+------------------------------------------------------------------+
//| ENUMERAÇÕES — Modo de Seleção do Smart Close                     |
//+------------------------------------------------------------------+

// Define qual posição perdedora será alvo do fechamento inteligente
enum ENUM_CLOSE_TARGET {
    CLOSE_WORST,         // Pior Posição — maior prejuízo absoluto
    CLOSE_OLDEST         // Mais Antiga — primeira ordem da grade (FIFO)
};

//+------------------------------------------------------------------+
//| ENUMERAÇÕES — Perfil de Risco (Presets)                          |
//+------------------------------------------------------------------+

// Perfis pré-configurados inspirados nos sinais do Daniel Moraes
enum ENUM_RISK_PROFILE {
    PROFILE_NOPAIN,      // NoPain — Conservador (~3%/mês, DD ~20%)
    PROFILE_UPFUJI,      // UpFuji — Agressivo (~5.5%/mês, DD ~31%)
    PROFILE_CUSTOM       // Personalizado — usuário define tudo
};

//+------------------------------------------------------------------+
//| ENUMERAÇÕES — Níveis de Log                                      |
//+------------------------------------------------------------------+

// Define a verbosidade do sistema de logging
enum ENUM_LOG_LEVEL {
    LOG_DEBUG,           // Debug — mensagens detalhadas de depuração
    LOG_INFO,            // Info — informações operacionais normais
    LOG_WARNING,         // Aviso — situações anormais mas não críticas
    LOG_ERROR,           // Erro — falhas que impedem uma operação
    LOG_CRITICAL         // Crítico — falhas que exigem intervenção imediata
};

//+------------------------------------------------------------------+
//| ESTRUTURA — Dados de um Nível da Grade                           |
//+------------------------------------------------------------------+

// Armazena todas as informações de uma posição individual na grade
struct SGridLevel {
    ulong             ticket;        // Ticket da posição no MT5
    int               level;         // Número do nível (0, 1, 2, ...)
    ENUM_POSITION_TYPE type;         // Tipo: POSITION_TYPE_BUY ou SELL
    double            lot;           // Volume da posição
    double            open_price;    // Preço de abertura
    double            profit;        // Lucro/Prejuízo atual em USD
    double            profit_points; // Lucro/Prejuízo em pontos
    datetime          open_time;     // Data/hora de abertura
    bool              is_active;     // Se a posição ainda está aberta

    // Construtor padrão — inicializa tudo zerado
    void Reset() {
        ticket      = 0;
        level       = 0;
        type        = POSITION_TYPE_BUY;
        lot         = 0.0;
        open_price  = 0.0;
        profit      = 0.0;
        profit_points = 0.0;
        open_time   = 0;
        is_active   = false;
    }
};

//+------------------------------------------------------------------+
//| ESTRUTURA — Estado Geral de uma Grade (por símbolo e direção)    |
//+------------------------------------------------------------------+

// Consolida o estado completo de todas as posições de uma grade
struct SGridState {
    string  symbol;              // Símbolo do ativo (ex: AUDCAD)
    int     total_levels;        // Quantidade de níveis abertos
    double  total_volume;        // Volume total (soma de todos os lotes)
    double  total_profit;        // P&L total aberto em USD
    double  avg_price;           // Preço médio ponderado por volume
    double  worst_profit;        // Pior prejuízo individual em USD
    ulong   worst_ticket;        // Ticket da posição com pior prejuízo
    double  worst_lot;           // Volume da posição com pior prejuízo
    double  best_profit;         // Melhor lucro individual em USD
    ulong   best_ticket;         // Ticket da posição com melhor lucro
    double  positive_profit_sum; // Soma dos lucros das posições positivas

    // Construtor padrão — inicializa tudo zerado
    void Reset() {
        symbol              = "";
        total_levels        = 0;
        total_volume        = 0.0;
        total_profit        = 0.0;
        avg_price           = 0.0;
        worst_profit        = 0.0;
        worst_ticket        = 0;
        worst_lot           = 0.0;
        best_profit         = 0.0;
        best_ticket         = 0;
        positive_profit_sum = 0.0;
    }
};

//+------------------------------------------------------------------+
//| ESTRUTURA — Configuração de um Símbolo para Multi-Symbol         |
//+------------------------------------------------------------------+

// Cada símbolo operado tem sua própria configuração independente
struct SSymbolConfig {
    string symbol;               // Nome do símbolo (ex: "AUDCAD")
    bool   enabled;              // Se está habilitado para operação
    double initial_lot;          // Lote inicial para este símbolo
    double lot_multiplier;       // Multiplicador de lote
    int    max_levels;           // Máximo de níveis da grade
    int    fixed_spacing;        // Espaçamento fixo (se GRID_FIXED)
    double atr_multiplier;       // Multiplicador do ATR (se GRID_DYNAMIC)
    int    magic_number;         // Magic number único para este símbolo

    // Inicializa com valores padrão seguros
    void SetDefaults(string sym, int magic) {
        symbol         = sym;
        enabled        = true;
        initial_lot    = 0.01;
        lot_multiplier = 1.0;
        max_levels     = 5;
        fixed_spacing  = 100;
        atr_multiplier = 1.5;
        magic_number   = magic;
    }
};

//+------------------------------------------------------------------+
