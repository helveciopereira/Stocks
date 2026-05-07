//+------------------------------------------------------------------+
//|                                                  OmniB3_EA.mq5   |
//|                   Omni-B3 EA v1.1 — Minicontratos B3             |
//|                                                                   |
//|  Grid Trading com Smart Close para WIN/WDO (contas NETTING)      |
//|  Inspirado na metodologia Daniel Moraes (ToTheMoon)              |
//|  Adaptado para Real Brasileiro e minicontratos da Bovespa        |
//+------------------------------------------------------------------+
#property copyright   "Projeto Omni-B3"
#property link        "https://github.com/helveciopereira/Stocks"
#property version     "1.10"
#property description "Grid Trading para Minicontratos B3 (WIN/WDO)"
#property description "Smart Close com rastreamento virtual de níveis"
#property description "Adaptado para contas NETTING em Real (BRL)"

//+------------------------------------------------------------------+
//| INCLUDES                                                          |
//+------------------------------------------------------------------+
#include <OmniB3/Defines.mqh>
#include <OmniB3/Logger.mqh>
#include <OmniB3/PositionManager.mqh>
#include <OmniB3/GridEngine.mqh>
#include <OmniB3/SmartClose.mqh>
#include <OmniB3/RiskManager.mqh>
#include <OmniB3/TimeFilter.mqh>

//+------------------------------------------------------------------+
//| INPUTS — Parâmetros Configuráveis                                |
//+------------------------------------------------------------------+

//--- Perfil de Risco
input ENUM_RISK_PROFILE InpRiskProfile = PROFILE_CONSERVADOR; // ═══ Perfil de Risco ═══

//--- Configurações da Grade
input ENUM_GRID_TYPE      InpGridType    = GRID_FIXED;         // Tipo de Grade
input ENUM_GRID_DIRECTION InpDirection   = GRID_BUY_ONLY;      // Direção (Compra ou Venda)
input ENUM_LOT_MODE       InpLotMode     = LOT_FIXED;          // Modo de Lote
input double              InpInitialLot  = 1.0;                // Volume Inicial (contratos)
input double              InpLotMult     = 1.0;                // Multiplicador de Lote
input int                 InpMaxLevels   = 3;                  // Máximo de Níveis
input int                 InpFixedSpacing = 300;               // Espaçamento Fixo (pontos)

//--- ATR (Grade Dinâmica)
input int                 InpATRPeriod   = 14;                 // Período do ATR
input ENUM_TIMEFRAMES     InpATRTimeframe = PERIOD_M5;         // Timeframe do ATR
input double              InpATRMult     = 1.5;                // Multiplicador ATR

//--- Smart Close
input ENUM_CLOSE_TARGET   InpCloseTarget = CLOSE_WORST;        // Alvo do Smart Close
input double              InpMarginTicks = 3.0;                // Margem de Segurança (ticks)

//--- Gestão de Risco
input double InpEquityStopPct  = 90.0;   // Equity Stop (% do saldo)
input double InpMaxDailyDDPct  = 3.0;    // DD Diário Máximo (%)
input int    InpMaxPositions   = 10;      // Máx. Níveis Simultâneos
input double InpMinMarginPct   = 30.0;   // Margem Livre Mínima (%)

//--- Filtro de Horário (B3: 9:00 - 17:55)
input int    InpStartHour      = 9;       // Hora de Início
input int    InpStartMinute    = 5;       // Minuto de Início
input int    InpEndHour        = 17;      // Hora de Fim
input int    InpEndMinute      = 40;      // Minuto de Fim
input bool   InpFridayEarly    = true;    // Fechar cedo na Sexta?
input int    InpFridayEndHour  = 17;      // Hora fim na Sexta

//--- Sistema
input int            InpMagicNumber = 202605;   // Número Mágico
input ENUM_LOG_LEVEL InpLogLevel    = LOG_INFO;  // Nível de Log
input bool           InpLogToFile   = false;     // Salvar Log em Arquivo?

//+------------------------------------------------------------------+
//| OBJETOS GLOBAIS                                                   |
//+------------------------------------------------------------------+
CLogger          *Logger;
CPositionManager *PosManager;
CGridEngine      *Grid;
CSmartClose      *Smart;
CRiskManager     *Risk;
CTimeFilter      *TFilter;
bool              g_initialized = false;

//+------------------------------------------------------------------+
//| Aplica perfil de risco selecionado                               |
//+------------------------------------------------------------------+
void ApplyProfile(double &lot, double &mult, int &levels,
                  double &margin_ticks, double &equity_stop, double &daily_dd) {
    switch(InpRiskProfile) {
        case PROFILE_CONSERVADOR:
            // Conservador: poucos níveis, sem multiplicador
            // Ideal para iniciar testes em conta demo
            lot          = 1.0;     // 1 minicontrato
            mult         = 1.0;     // Sem multiplicador
            levels       = 3;       // Máximo 3 níveis
            margin_ticks = 3.0;     // 3 ticks de margem
            equity_stop  = 92.0;    // Equity stop em 92%
            daily_dd     = 2.0;     // DD diário máx 2%
            Logger.Info("EA", "📋 Perfil CONSERVADOR (1 contrato, 3 níveis, sem mult)");
            break;

        case PROFILE_MODERADO:
            // Moderado: mais níveis, multiplicador leve
            lot          = 1.0;
            mult         = 1.5;     // Multiplicador 1.5x
            levels       = 5;       // Até 5 níveis
            margin_ticks = 2.0;
            equity_stop  = 85.0;
            daily_dd     = 4.0;
            Logger.Info("EA", "📋 Perfil MODERADO (1 contrato, 5 níveis, mult 1.5x)");
            break;

        case PROFILE_CUSTOM:
            lot          = InpInitialLot;
            mult         = InpLotMult;
            levels       = InpMaxLevels;
            margin_ticks = InpMarginTicks;
            equity_stop  = InpEquityStopPct;
            daily_dd     = InpMaxDailyDDPct;
            Logger.Info("EA", "📋 Perfil PERSONALIZADO");
            break;
    }
}

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit() {
    // 1. Logger (primeiro — todos dependem dele)
    Logger = new CLogger(InpLogLevel, InpLogToFile);
    Logger.Info("EA", StringFormat("═══ Omni-B3 EA v%s ═══ Minicontratos B3", OMNIB3_VERSION));
    Logger.Info("EA", StringFormat("Símbolo: %s | Magic: %d", _Symbol, InpMagicNumber));

    // Info do símbolo para debug
    double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double vol_min    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double vol_step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    Logger.Info("EA", StringFormat("TickSize=%.2f | TickValue=R$%.2f | VolMin=%.0f | VolStep=%.0f",
                                   tick_size, tick_value, vol_min, vol_step));

    // 2. Aplica perfil
    double eff_lot, eff_mult, eff_margin, eff_equity, eff_dd;
    int    eff_levels;
    ApplyProfile(eff_lot, eff_mult, eff_levels, eff_margin, eff_equity, eff_dd);

    // 3. Position Manager
    PosManager = new CPositionManager(_Symbol, InpMagicNumber, Logger);
    PosManager.SyncOnStartup(); // Sincroniza com posição existente

    // 4. Grid Engine
    Grid = new CGridEngine(_Symbol, InpMagicNumber,
                           InpGridType, InpDirection, InpLotMode,
                           eff_lot, eff_mult, eff_levels,
                           InpFixedSpacing, InpATRPeriod, InpATRTimeframe,
                           InpATRMult, PosManager, Logger);

    // 5. Smart Close
    Smart = new CSmartClose(_Symbol, InpMagicNumber,
                            InpCloseTarget, eff_margin, PosManager, Logger);

    // 6. Risk Manager
    Risk = new CRiskManager(InpMagicNumber, eff_equity, eff_dd,
                            InpMaxPositions, InpMinMarginPct, Logger);

    // 7. Time Filter (horário B3)
    TFilter = new CTimeFilter(InpStartHour, InpStartMinute,
                              InpEndHour, InpEndMinute,
                              InpFridayEarly, InpFridayEndHour,
                              false, Logger); // false = hora local (BRT)

    g_initialized = true;
    Logger.Info("EA", "✅ Inicialização completa!");
    Logger.Info("EA", Grid.GetSpacingInfo());

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    if(Logger != NULL)
        Logger.Info("EA", StringFormat("Desligando... Razão: %d", reason));

    if(TFilter != NULL)    { delete TFilter;    TFilter = NULL; }
    if(Risk != NULL)       { delete Risk;        Risk = NULL; }
    if(Smart != NULL)      { delete Smart;       Smart = NULL; }
    if(Grid != NULL)       { delete Grid;        Grid = NULL; }
    if(PosManager != NULL) { delete PosManager;  PosManager = NULL; }
    if(Logger != NULL)     { delete Logger;      Logger = NULL; }

    g_initialized = false;
}

//+------------------------------------------------------------------+
//| Expert tick — Pipeline Principal                                  |
//|                                                                   |
//| 1. Risk → Seguro para operar?                                    |
//| 2. Smart Close → Abate parcial? (roda sempre, mesmo fora hora)  |
//| 3. Time Filter → Dentro do pregão?                               |
//| 4. Grid → Abrir novo nível?                                      |
//+------------------------------------------------------------------+
void OnTick() {
    if(!g_initialized) return;

    int levels = PosManager.CountLevels();

    // 1. Gestão de Risco
    if(!Risk.IsSafeToTrade(levels)) return;

    // 2. Smart Close (roda SEMPRE — fechamento não depende de horário)
    if(Smart.CheckAndExecute()) {
        Logger.Info("EA", "🎯 Smart Close executado");
        return;
    }

    // 3. Filtro de Horário B3
    if(!TFilter.IsTradeAllowed()) return;

    // 4. Motor de Grade
    Grid.ProcessGrid();
}

//+------------------------------------------------------------------+
//| Eventos do gráfico — Botão de Pânico                             |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam,
                  const double &dparam, const string &sparam) {
    if(id == CHARTEVENT_OBJECT_CLICK) {
        if(sparam == "btn_panic") {
            Logger.Critical("EA", "🔴 PÂNICO pressionado!");
            Risk.ActivateKillSwitch();
            if(PosManager != NULL) PosManager.ClearAllLevels();
        }
        if(sparam == "btn_reset") {
            Logger.Info("EA", "🟢 RESET pressionado");
            Risk.ResetKillSwitch();
        }
    }
}

//+------------------------------------------------------------------+
