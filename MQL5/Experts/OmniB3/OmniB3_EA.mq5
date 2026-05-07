//+------------------------------------------------------------------+
//|                                                  OmniB3_EA.mq5   |
//|                   Omni-B3 EA v1.0 — Orquestrador Principal       |
//|                                                                   |
//|  EA de Grid Trading com Smart Close inspirado na metodologia     |
//|  de Daniel Moraes (ToTheMoon). Opera em grade bi-direcional     |
//|  com fechamento inteligente e múltiplas camadas de proteção.     |
//+------------------------------------------------------------------+
#property copyright   "Projeto Omni-B3"
#property link        "https://github.com/seu-usuario/Stocks"
#property version     "1.00"
#property description "Grid Trading EA com Smart Close e Gestão de Risco Avançada"
#property description "Inspirado na metodologia Daniel Moraes (ToTheMoon)"
#property description "Opera AUDCAD M5 em conta Hedging"

//+------------------------------------------------------------------+
//| INCLUDES — Módulos do Ecossistema                                |
//+------------------------------------------------------------------+
#include <OmniB3/Defines.mqh>
#include <OmniB3/Logger.mqh>
#include <OmniB3/PositionManager.mqh>
#include <OmniB3/GridEngine.mqh>
#include <OmniB3/SmartClose.mqh>
#include <OmniB3/RiskManager.mqh>
#include <OmniB3/TimeFilter.mqh>

//+------------------------------------------------------------------+
//| INPUTS — Parâmetros Configuráveis pelo Usuário                   |
//+------------------------------------------------------------------+

//--- Perfil de Risco (atalho para NoPain ou UpFuji)
input ENUM_RISK_PROFILE InpRiskProfile = PROFILE_NOPAIN;     // ═══ Perfil de Risco ═══

//--- Configurações da Grade
input ENUM_GRID_TYPE      InpGridType      = GRID_DYNAMIC_ATR; // Tipo de Grade
input ENUM_GRID_DIRECTION InpDirection     = GRID_BIDIRECTIONAL; // Direção da Grade
input ENUM_LOT_MODE       InpLotMode       = LOT_MULTIPLIER;  // Modo de Lote
input double              InpInitialLot    = 0.01;             // Lote Inicial
input double              InpLotMultiplier = 1.2;              // Multiplicador de Lote
input int                 InpMaxLevels     = 5;                // Máximo de Níveis da Grade
input int                 InpFixedSpacing  = 100;              // Espaçamento Fixo (pontos)

//--- Configurações do ATR (Grade Dinâmica)
input int                 InpATRPeriod     = 14;               // Período do ATR
input ENUM_TIMEFRAMES     InpATRTimeframe  = PERIOD_M5;        // Timeframe do ATR
input double              InpATRMultiplier = 1.5;              // Multiplicador do ATR

//--- Configurações do Smart Close
input ENUM_CLOSE_TARGET   InpCloseTarget   = CLOSE_WORST;      // Alvo do Smart Close
input double              InpMarginPoints  = 3.0;              // Margem de Segurança (pontos)

//--- Gestão de Risco
input double InpEquityStopPct   = 70.0;   // Equity Stop (% do saldo)
input double InpMaxDailyDDPct   = 5.0;    // DD Diário Máximo (%)
input int    InpMaxPositions    = 20;      // Máx. Posições Simultâneas (global)
input double InpMinMarginPct   = 20.0;    // Margem Livre Mínima (%)

//--- Filtro de Horário
input int    InpStartHour       = 1;       // Hora de Início (0-23)
input int    InpEndHour         = 23;      // Hora de Fim (0-23)
input bool   InpFridayBlock     = true;    // Bloquear Sexta-feira?
input int    InpFridayBlockHour = 20;      // Hora do Bloqueio na Sexta
input bool   InpMondayDelay     = true;    // Delay na Segunda-feira?
input int    InpMondayStartHour = 2;       // Hora de Início na Segunda

//--- Sistema
input int              InpMagicNumber = 202605; // Número Mágico
input ENUM_LOG_LEVEL   InpLogLevel    = LOG_INFO; // Nível de Log
input bool             InpLogToFile   = false;    // Salvar Log em Arquivo?

//+------------------------------------------------------------------+
//| VARIÁVEIS GLOBAIS — Objetos dos Módulos                          |
//+------------------------------------------------------------------+
CLogger          *Logger;          // Sistema de logging
CPositionManager *PosManager;      // Gerenciador de posições
CGridEngine      *Grid;            // Motor de grade
CSmartClose      *Smart;           // Fechamento inteligente
CRiskManager     *Risk;            // Gestor de risco
CTimeFilter      *TimeFilter;     // Filtro de horário

//+------------------------------------------------------------------+
//| VARIÁVEIS DE CONTROLE                                            |
//+------------------------------------------------------------------+
bool g_initialized = false;        // Flag de inicialização bem-sucedida

//+------------------------------------------------------------------+
//| Aplica configurações do perfil de risco selecionado              |
//| Modifica os inputs para refletir os presets NoPain ou UpFuji     |
//+------------------------------------------------------------------+
void ApplyRiskProfile(double &lot, double &mult, int &levels, double &atr_mult,
                      double &margin_pts, double &equity_stop, double &daily_dd) {
    switch(InpRiskProfile) {
        case PROFILE_NOPAIN:
            // NoPain: Conservador — ~3% ao mês, DD máx ~20%
            // Baseado no sinal NoPain MT5 (ID: 2262642) do Daniel Moraes
            lot          = 0.01;
            mult         = 1.2;
            levels       = 5;
            atr_mult     = 1.5;
            margin_pts   = 3.0;
            equity_stop  = 75.0;
            daily_dd     = 4.0;
            Logger.Info("EA", "📋 Perfil NoPain aplicado (Conservador)");
            break;

        case PROFILE_UPFUJI:
            // UpFuji: Agressivo — ~5.5% ao mês, DD máx ~31%
            // Baseado no sinal UpFuji MT5 (ID: 2308095) do Daniel Moraes
            lot          = 0.01;
            mult         = 1.4;
            levels       = 7;
            atr_mult     = 1.2;
            margin_pts   = 2.0;
            equity_stop  = 65.0;
            daily_dd     = 6.0;
            Logger.Info("EA", "📋 Perfil UpFuji aplicado (Agressivo)");
            break;

        case PROFILE_CUSTOM:
            // Custom: usa os inputs definidos pelo usuário diretamente
            lot          = InpInitialLot;
            mult         = InpLotMultiplier;
            levels       = InpMaxLevels;
            atr_mult     = InpATRMultiplier;
            margin_pts   = InpMarginPoints;
            equity_stop  = InpEquityStopPct;
            daily_dd     = InpMaxDailyDDPct;
            Logger.Info("EA", "📋 Perfil Personalizado — usando inputs do usuário");
            break;
    }
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//| Chamada uma vez quando o EA é carregado no gráfico               |
//+------------------------------------------------------------------+
int OnInit() {
    // ═══════════════════════════════════════════════════════════════
    // VERIFICAÇÃO DE PRÉ-REQUISITOS
    // ═══════════════════════════════════════════════════════════════

    // Verifica se a conta é do tipo Hedging (obrigatório para grid)
    if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE)
        != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING) {
        Print("❌ ERRO FATAL: Esta estratégia requer uma conta HEDGING!");
        Print("   Sua conta é do tipo NETTING. Troque de conta ou corretora.");
        return(INIT_FAILED);
    }

    // ═══════════════════════════════════════════════════════════════
    // INICIALIZAÇÃO DOS MÓDULOS (ordem importa: dependências primeiro)
    // ═══════════════════════════════════════════════════════════════

    // 1. Logger — primeiro, pois todos os módulos dependem dele
    Logger = new CLogger(InpLogLevel, InpLogToFile);
    Logger.Info("EA", StringFormat("═══ Omni-B3 EA v%s ═══ Inicializando...", OMNIB3_VERSION));
    Logger.Info("EA", StringFormat("Símbolo: %s | Magic: %d | Perfil: %s",
                                   _Symbol, InpMagicNumber, EnumToString(InpRiskProfile)));

    // 2. Aplica perfil de risco (NoPain, UpFuji ou Custom)
    double eff_lot, eff_mult, eff_atr_mult, eff_margin_pts, eff_equity_stop, eff_daily_dd;
    int    eff_levels;
    ApplyRiskProfile(eff_lot, eff_mult, eff_levels, eff_atr_mult,
                     eff_margin_pts, eff_equity_stop, eff_daily_dd);

    // 3. Position Manager — segundo, pois Grid e Smart dependem dele
    PosManager = new CPositionManager(_Symbol, InpMagicNumber, Logger);

    // 4. Grid Engine — motor de abertura de ordens
    Grid = new CGridEngine(_Symbol, InpMagicNumber,
                           InpGridType, InpDirection, InpLotMode,
                           eff_lot, eff_mult, eff_levels,
                           InpFixedSpacing, InpATRPeriod, InpATRTimeframe,
                           eff_atr_mult, PosManager, Logger);

    // 5. Smart Close — fechamento inteligente
    Smart = new CSmartClose(_Symbol, InpMagicNumber,
                            InpCloseTarget, eff_margin_pts,
                            PosManager, Logger);

    // 6. Risk Manager — proteção de capital
    Risk = new CRiskManager(InpMagicNumber,
                            eff_equity_stop, eff_daily_dd,
                            InpMaxPositions, InpMinMarginPct, Logger);

    // 7. Time Filter — controle de horário
    TimeFilter = new CTimeFilter(InpStartHour, InpEndHour,
                                 InpFridayBlock, InpFridayBlockHour,
                                 InpMondayDelay, InpMondayStartHour,
                                 true, Logger);

    g_initialized = true;
    Logger.Info("EA", "✅ Todos os módulos inicializados com sucesso!");
    Logger.Info("EA", Grid.GetSpacingInfo());

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//| Chamada quando o EA é removido do gráfico ou MT5 é fechado      |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    if(Logger != NULL)
        Logger.Info("EA", StringFormat("Desligando Omni-B3 EA... Razão: %d", reason));

    // Libera memória de todos os módulos na ordem inversa
    if(TimeFilter != NULL)  { delete TimeFilter;  TimeFilter = NULL; }
    if(Risk != NULL)        { delete Risk;         Risk = NULL; }
    if(Smart != NULL)       { delete Smart;        Smart = NULL; }
    if(Grid != NULL)        { delete Grid;         Grid = NULL; }
    if(PosManager != NULL)  { delete PosManager;   PosManager = NULL; }
    if(Logger != NULL)      { delete Logger;       Logger = NULL; }

    g_initialized = false;
}

//+------------------------------------------------------------------+
//| Expert tick function — PIPELINE PRINCIPAL DE EXECUÇÃO            |
//|                                                                   |
//| Ordem de execução (pipeline):                                    |
//|  1. Verificação de inicialização                                 |
//|  2. Gestão de Risco → Equity segura?                             |
//|  3. Smart Close → Condição de abate parcial?                     |
//|  4. Filtro de Horário → Permitido operar?                        |
//|  5. Motor de Grade → Abrir novo nível?                           |
//|                                                                   |
//| NOTA: O Smart Close roda ANTES do filtro de horário porque      |
//| queremos poder fechar posições a qualquer momento, mesmo fora   |
//| da janela de operação. Apenas a ABERTURA é filtrada por horário. |
//+------------------------------------------------------------------+
void OnTick() {
    // Proteção contra chamadas antes da inicialização completa
    if(!g_initialized) return;

    // ═══ ETAPA 1: GESTÃO DE RISCO ═══
    // Verifica equity, drawdown, margem e kill-switch
    // Se qualquer condição de risco for violada, o EA para
    if(!Risk.IsSafeToTrade()) {
        return; // Bloqueado pelo gestor de risco
    }

    // ═══ ETAPA 2: SMART CLOSE (ABATE PARCIAL) ═══
    // Verifica se o lucro acumulado é suficiente para fechar
    // a posição com maior prejuízo. Roda SEMPRE, independente
    // do horário, para proteger o capital.
    if(Smart.CheckAndExecute()) {
        Logger.Info("EA", "🎯 Abate Parcial executado — ciclo de proteção ativo");
        return; // Após smart close, pula este tick para estabilizar
    }

    // ═══ ETAPA 3: FILTRO DE HORÁRIO ═══
    // Verifica se estamos na janela permitida para novas ordens
    // Se fora do horário, não abre nada (mas smart close acima já rodou)
    if(!TimeFilter.IsTradeAllowed()) {
        return; // Fora da janela de operação
    }

    // ═══ ETAPA 4: MOTOR DE GRADE ═══
    // Verifica se o preço se moveu o suficiente para abrir um
    // novo nível da grade. Respeita direção configurada
    // (compra, venda ou bi-direcional)
    Grid.ProcessGrid();
}

//+------------------------------------------------------------------+
//| Tratamento de eventos do gráfico                                 |
//| Implementa o botão de PÂNICO visual no gráfico                  |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam) {
    // Detecta clique em objeto do gráfico
    if(id == CHARTEVENT_OBJECT_CLICK) {
        // Se clicou no botão de pânico
        if(sparam == "btn_panic") {
            Logger.Critical("EA", "🔴 BOTÃO DE PÂNICO pressionado pelo usuário!");
            Risk.ActivateKillSwitch();
        }
        // Se clicou no botão de reset
        if(sparam == "btn_reset") {
            Logger.Info("EA", "🟢 RESET solicitado pelo usuário");
            Risk.ResetKillSwitch();
        }
    }
}

//+------------------------------------------------------------------+
