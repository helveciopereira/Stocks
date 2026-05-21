//+------------------------------------------------------------------+
//|                                                  OmniB3_EA.mq5   |
//|                   Omni-B3 EA v2.0 — Minicontratos B3             |
//|                                                                   |
//|  Grid Trading Avançado para WIN/WDO (contas NETTING)             |
//|  12+ modos de fechamento | 12+ indicadores | Recovery Mode      |
//|  Persistência de estado | Money Management | Filtros avançados   |
//|  Inspirado na metodologia Daniel Moraes (ToTheMoon v3.5)         |
//|  Adaptado para Real Brasileiro e minicontratos da Bovespa        |
//+------------------------------------------------------------------+
#property copyright   "Projeto Omni-B3"
#property link        "https://github.com/helveciopereira/Stocks"
#property version     "2.00"
#property description "Grid Trading Avançado para Minicontratos B3 (WIN/WDO)"
#property description "12+ modos de fechamento | 12+ indicadores técnicos"
#property description "Persistência de estado | Recovery | Money Management"
#property description "Adaptado para contas NETTING em Real (BRL)"

//+------------------------------------------------------------------+
//| INCLUDES                                                          |
//+------------------------------------------------------------------+
#include <OmniB3/Defines.mqh>
#include <OmniB3/Logger.mqh>
#include <OmniB3/IndicatorHub.mqh>
#include <OmniB3/MoneyManager.mqh>
#include <OmniB3/StatePersistence.mqh>
#include <OmniB3/RecoveryMode.mqh>
#include <OmniB3/PositionManager.mqh>
#include <OmniB3/GridEngine.mqh>
#include <OmniB3/SmartClose.mqh>
#include <OmniB3/RiskManager.mqh>
#include <OmniB3/TimeFilter.mqh>

//+------------------------------------------------------------------+
//| ═══════════════ DADOS INICIAIS ═══════════════                    |
//+------------------------------------------------------------------+
input string           InpSeparator0 = "════════ DADOS INICIAIS ════════";   // ═══════════════════
input int              InpMagicNumber = 202605;    // Número Mágico (ID único do EA)
input ENUM_LOG_LEVEL   InpLogLevel    = LOG_INFO;  // Nível de Log
input bool             InpLogToFile   = false;     // Salvar Log em Arquivo?
input string           InpComment     = "";        // Comentário nas Ordens (vazio = padrão)
input int              InpSpreadMax   = 30;        // Spread Máximo (pontos)

//+------------------------------------------------------------------+
//| ═══════════════ GERENCIAR DINHEIRO ═══════════════                |
//+------------------------------------------------------------------+
input string           InpSeparator1 = "════════ GERENCIAR DINHEIRO ════════";  // ═══════════════════
input ENUM_BALANCE_MODE InpBalanceMode = BAL_FULL_ACCOUNT; // Modo do Saldo do Robô
input double           InpBalanceValue = 10000.0;  // Valor do Saldo (R$) ou Porcentagem
input double           InpMaxBalance   = 0.0;      // Saldo Máximo do Robô (0=sem teto)

input string           InpSepPreset = "---- Multiplicador de Preset ----";  // ────────────────
input ENUM_PRESET_MODE InpPresetMode = PRESET_DISABLED;  // Modo xPreset
input double           InpPresetFactor = 10000.0;  // Fator Base (R$ para x1)

input string           InpSepStopMM = "---- StopLoss do Robô ----";  // ────────────────
input double           InpMMStopAmount  = 0.0;     // StopLoss Valor (R$, 0=desab.)
input double           InpMMStopPercent = 0.0;     // StopLoss DD% (0=desab.)
input double           InpMMMaxLoss     = 0.0;     // Prejuízo Atual Máx (R$, 0=desab.)
input int              InpMMWaitLoss    = 0;        // Aguardar após Prejuízo (seg)
input bool             InpMMStopLoss    = false;    // Parar após Prejuízo?

//+------------------------------------------------------------------+
//| ═══════════════ ABERTURA ═══════════════                           |
//+------------------------------------------------------------------+
input string           InpSeparator2 = "════════ ABERTURA ════════";  // ═══════════════════
input ENUM_RISK_PROFILE InpRiskProfile = PROFILE_CUSTOM;  // Perfil de Risco
input ENUM_GRID_DIRECTION InpDirection = GRID_BUY_ONLY;   // Direção (Compra ou Venda)

input string           InpSepIndicator = "---- Indicador de Sinal ----";  // ────────────────
input ENUM_INDICATOR_SIGNAL InpSignalInd = IND_RSI;            // Indicador Principal
input ENUM_INDICATOR_STRATEGY InpSignalStrat = STRAT_STANDARD;  // Estratégia do Sinal
input ENUM_INDICATOR_SIGNAL InpConfirm1 = IND_NONE;             // Confirmação 1
input ENUM_INDICATOR_STRATEGY InpConfStrat1 = STRAT_DISABLED;   // Estratégia Confirm. 1
input ENUM_INDICATOR_SIGNAL InpConfirm2 = IND_NONE;             // Confirmação 2
input ENUM_INDICATOR_STRATEGY InpConfStrat2 = STRAT_DISABLED;   // Estratégia Confirm. 2
input ENUM_INDICATOR_SIGNAL InpConfirm3 = IND_NONE;             // Confirmação 3
input ENUM_INDICATOR_STRATEGY InpConfStrat3 = STRAT_DISABLED;   // Estratégia Confirm. 3
input ENUM_INDICATOR_SIGNAL InpConfirm4 = IND_NONE;             // Confirmação 4
input ENUM_INDICATOR_STRATEGY InpConfStrat4 = STRAT_DISABLED;   // Estratégia Confirm. 4
input bool             InpUseIndInitial = true;     // Usar Indicador na Ordem Inicial?
input bool             InpUseIndGrid    = false;    // Usar Indicador nas Ordens da Grid?
input bool             InpOpenOnCandle  = true;     // Abrir Apenas no Início do Candle?

input string           InpSepLots = "---- Lotes ----";  // ────────────────
input double           InpInitialLot  = 1.0;       // Volume Inicial (contratos)
input double           InpLotMin      = 1.0;       // Lote Mínimo
input double           InpLotMax      = 100.0;     // Lote Máximo

input string           InpSepWait = "---- Espera ----";  // ────────────────
input int              InpWaitSameDir   = 30;      // Espera entre Ordens Mesma Dir. (seg)
input int              InpGiantCandleWaitInit = 0;  // Espera Candle Gigante Inicial (seg)
input int              InpGiantCandleSizeInit = 100;// Tamanho Candle Gigante Inicial (pts)
input int              InpGiantCandleWaitGrid = 0;  // Espera Candle Gigante Grid (seg)
input int              InpGiantCandleSizeGrid = 100;// Tamanho Candle Gigante Grid (pts)
input double           InpMaxDDNoOpen  = 50.0;     // Não Abrir se DD Robô > % (0=desab.)

//+------------------------------------------------------------------+
//| ═══════════════ MODO GRADE ═══════════════                        |
//+------------------------------------------------------------------+
input string           InpSeparator3 = "════════ MODO GRADE (GRID) ════════";  // ═══════════════════
input ENUM_GRID_TYPE   InpGridType    = GRID_FIXED;  // Tipo de Grade
input ENUM_CLOSE_MODE  InpCloseMode   = CMODE_SMART_WORST;  // Modo de Fechamento
input int              InpMaxLevels   = 5;          // Máximo de Níveis
input double           InpMinProfit   = 0.0;        // Lucro Mínimo p/ Fechar (R$)

input string           InpSepTP = "---- TakeProfit ----";  // ────────────────
input ENUM_TP_MODE     InpTPMode       = TP_FIXED_POINTS;  // Modo do TakeProfit
input double           InpTPPoints     = 100.0;    // TakeProfit (pontos)
input double           InpTPMonetary   = 0.0;      // TakeProfit Monetário (R$)
input double           InpTPAcceptable = 0.0;       // TP Aceitável (pontos, negativo=aceitar perda)
input double           InpTPMultiplier = 1.0;       // Multiplicador do TP
input ENUM_TP_REDUCE_TYPE InpTPReduceType = TP_REDUCE_NONE;  // Modo de Redução do TP
input double           InpTPReduceDD   = 100.0;    // DD% para Reduzir TP
input int              InpTPReduceTime = 0;         // Minutos para Redução do TP

input string           InpSepBE = "---- BreakEven ----";  // ────────────────
input ENUM_BE_MODE     InpBEMode      = BE_DISABLED;  // Modo BreakEven
input double           InpBEPoints    = 0.0;       // BreakEven (pontos)
input double           InpBEAcceptable = 0.0;      // BE Aceitável (pontos)
input ENUM_BE_TYPE     InpBEType      = BE_STATIC;  // Tipo BreakEven
input double           InpBETrailFactor = 1.0;     // Fator Trailing

input string           InpSepStep = "---- Passo da Grade ----";  // ────────────────
input int              InpFixedSpacing = 300;       // Espaçamento Fixo (pontos)
input double           InpStepMultiplier = 1.0;     // Multiplicador do Passo (1=sem mult)
input int              InpStepMin     = 0;          // Passo Mínimo (pontos, 0=sem)
input int              InpStepMax     = 0;          // Passo Máximo (pontos, 0=sem)
input int              InpAddedStep   = 0;          // Pontos Extras na Abertura
input int              InpAddedStepDecay = 0;       // Segundos para Zerar Extras

input string           InpSepATR = "---- ATR (Grade Dinâmica) ----";  // ────────────────
input int              InpATRPeriod   = 14;         // Período do ATR
input ENUM_TIMEFRAMES  InpATRTimeframe = PERIOD_M5; // Timeframe do ATR
input double           InpATRMult     = 1.5;        // Multiplicador ATR

input string           InpSepNext = "---- Próximo Lote ----";  // ────────────────
input ENUM_NEXT_LOT_MODE InpNextLotMode = NEXT_LOT_WAIT_MULTIPLY;  // Modo do Próximo Lote
input double           InpNextLotFactor = 1.3;      // Fator do Próximo Lote
input int              InpNextLotWait  = 600;       // Espera entre Ordens da Grid (seg)
input int              InpNextLotStartWait = 1;     // Começar a Esperar no Nível
input int              InpNextLotStopWait = 100;    // Parar de Esperar no Nível
input bool             InpAllowBigLot = false;      // Permitir Lote Grande?

input string           InpSepQuantity = "---- Fechamento por Quantidade ----";  // ────────────────
input double           InpLotSumTotal  = 0.0;       // Fechar se Soma Lotes > (0=desab.)
input int              InpOrderCountTotal = 0;       // Fechar se Qtde Ordens > (0=desab.)
input double           InpAcceptLoss   = 0.0;       // Aceitar Prejuízo (R$, negativo)
input double           InpDDAcceptLoss = 0.0;        // DD% para Aceitar Perda

input string           InpSepRecov = "---- Recovery ----";  // ────────────────
input double           InpRecoveryDD    = 100.0;    // DD% para Ativar Recovery (100=desab.)
input int              InpRecoveryOrders = 0;        // Qtde Ordens p/ Recovery (0=desab.)
input bool             InpRecoveryLock   = false;    // Travar em Recovery?
input ENUM_CLOSE_MODE  InpRecoveryCloseMode = CMODE_ACCEPT_LOSS;  // Modo Fech. Recovery
input int              InpRecoveryExtraStep = 0;     // Pontos Extras no Passo (Recovery)
input double           InpRecoveryExtraLot  = 0.0;   // Fator Extra no Lote (Recovery)
input int              InpRecoveryTP  = 100;         // TakeProfit em Recovery (pts)

//+------------------------------------------------------------------+
//| ═══════════════ INDICADORES ═══════════════                       |
//+------------------------------------------------------------------+
input string           InpSeparator4 = "════════ INDICADORES ════════";  // ═══════════════════

input string           InpSepRSI = "---- RSI ----";  // ────────────────
input int              InpRSIPeriod = 14;           // Período RSI
input ENUM_TIMEFRAMES  InpRSITimeframe = PERIOD_M5; // Timeframe RSI
input double           InpRSIUpper  = 70.0;         // RSI Sobrecompra
input double           InpRSILower  = 30.0;         // RSI Sobrevenda

input string           InpSepCCI = "---- CCI ----";  // ────────────────
input int              InpCCIPeriod = 14;           // Período CCI
input ENUM_TIMEFRAMES  InpCCITimeframe = PERIOD_M5; // Timeframe CCI
input double           InpCCIUpper  = 100.0;        // CCI Superior
input double           InpCCILower  = -100.0;       // CCI Inferior

input string           InpSepBB = "---- Bollinger Bands ----";  // ────────────────
input int              InpBBPeriod = 20;            // Período Bollinger
input ENUM_TIMEFRAMES  InpBBTimeframe = PERIOD_M5;  // Timeframe Bollinger
input double           InpBBDeviation = 2.0;        // Desvio Bollinger

input string           InpSepEnv = "---- Envelopes ----";  // ────────────────
input int              InpEnvPeriod = 14;           // Período Envelopes
input ENUM_TIMEFRAMES  InpEnvTimeframe = PERIOD_M5; // Timeframe Envelopes
input double           InpEnvDeviation = 0.1;       // Desvio Envelopes (%)

input string           InpSepMA = "---- Médias Móveis ----";  // ────────────────
input int              InpMAFastPeriod = 9;         // Período MA Rápida
input int              InpMASlowPeriod = 21;        // Período MA Lenta
input ENUM_TIMEFRAMES  InpMATimeframe = PERIOD_M5;  // Timeframe MAs
input ENUM_MA_METHOD   InpMAMethod = MODE_SMA;      // Método (SMA/EMA)

input string           InpSepHILO = "---- HILO ----";  // ────────────────
input int              InpHILOPeriod = 3;           // Período HILO
input ENUM_TIMEFRAMES  InpHILOTimeframe = PERIOD_M5;// Timeframe HILO

input string           InpSepADX = "---- ADX ----";  // ────────────────
input int              InpADXPeriod = 14;           // Período ADX
input ENUM_TIMEFRAMES  InpADXTimeframe = PERIOD_M5; // Timeframe ADX
input double           InpADXMin = 22.0;            // ADX Mínimo (força)

//+------------------------------------------------------------------+
//| ═══════════════ FILTROS ═══════════════                            |
//+------------------------------------------------------------------+
input string           InpSeparator5 = "════════ FILTROS ════════";  // ═══════════════════
input double           InpATRFilterMin = 0.0;       // ATR Mínimo (0=desab.)
input double           InpATRFilterMax = 999999.0;  // ATR Máximo
input long             InpVolFilterMin = 0;          // Volume Mínimo (0=desab.)

//+------------------------------------------------------------------+
//| ═══════════════ LIMITES ═══════════════                            |
//+------------------------------------------------------------------+
input string           InpSeparator6 = "════════ LIMITES (STOP) ════════";  // ═══════════════════

input string           InpSepCurrent = "---- Atual ----";  // ────────────────
input double           InpLimitProfitCurrent = 0.0;  // Lucro Máx Atual (R$, 0=desab.)
input double           InpLimitLossCurrent   = 0.0;  // Perda Máx Atual (R$, 0=desab.)
input int              InpWaitAfterLimit     = 0;    // Aguardar após Limite (seg)
input bool             InpStopAfterLimit     = false;// Parar após Limite?

input string           InpSepDaily = "---- Diário ----";  // ────────────────
input double           InpLimitProfitDaily = 0.0;    // Lucro Máx Diário (R$, 0=desab.)
input double           InpLimitLossDaily   = 0.0;    // Perda Máx Diária (R$, 0=desab.)
input double           InpMaxDailyDDPct    = 3.0;    // DD Diário Máximo (%)
input int              InpMaxOrdersDaily   = 0;      // Máx Ordens/Dia (0=sem limite)
input int              InpMaxWinsDaily     = 0;       // Máx Ganhos/Dia (0=sem limite)
input int              InpMaxLossesDaily   = 0;       // Máx Perdas/Dia (0=sem limite)

input string           InpSepAccount = "---- Conta ----";  // ────────────────
input double           InpEquityStopPct  = 85.0;     // Equity Stop (% do saldo)
input int              InpMaxPositions   = 10;        // Máx Níveis Simultâneos
input double           InpMinMarginPct   = 30.0;     // Margem Livre Mínima (%)
input double           InpMinBalance     = 0.0;       // Saldo Mínimo (R$, 0=desab.)
input double           InpMinEquity      = 0.0;       // Equity Mínima (R$, 0=desab.)

//+------------------------------------------------------------------+
//| ═══════════════ HORÁRIO ═══════════════                            |
//+------------------------------------------------------------------+
input string           InpSeparator7 = "════════ HORÁRIO PERMITIDO ════════";  // ═══════════════════
input int              InpStartHour    = 9;          // Hora de Início
input int              InpStartMinute  = 5;          // Minuto de Início
input int              InpEndHour      = 17;         // Hora de Fim
input int              InpEndMinute    = 40;         // Minuto de Fim
input bool             InpFridayEarly  = true;       // Fechar Cedo na Sexta?
input int              InpFridayEndHour = 17;        // Hora Fim na Sexta
input ENUM_TIME_CLOSE_MODE InpTimeCloseMode = TCLOSE_NONE;  // Modo Fechamento no Horário
input int              InpReduceMinutes = 60;        // Minutos antes do Fim p/ Reduzir TP
input ENUM_TIME_REDUCE_TYPE InpReduceType = TIME_REDUCE_NONE;  // O que Reduzir?

input string           InpSepDays = "---- Dias Permitidos ----";  // ────────────────
input bool             InpAllowMonday    = true;     // Operar Segunda?
input bool             InpAllowTuesday   = true;     // Operar Terça?
input bool             InpAllowWednesday = true;     // Operar Quarta?
input bool             InpAllowThursday  = true;     // Operar Quinta?
input bool             InpAllowFriday    = true;     // Operar Sexta?

//+------------------------------------------------------------------+
//| OBJETOS GLOBAIS                                                   |
//+------------------------------------------------------------------+
CLogger           *Logger;
CIndicatorHub     *IndHub;
CMoneyManager     *MoneyMgr;
CStatePersistence *Persistence;
CRecoveryMode     *Recovery;
CPositionManager  *PosManager;
CGridEngine       *Grid;
CSmartClose       *Smart;
CRiskManager      *Risk;
CTimeFilter       *TFilter;
bool               g_initialized = false;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit() {
    // ═══ 1. Logger (primeiro — todos dependem dele) ═══
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

    // ═══ 2. Indicator Hub ═══
    IndHub = new CIndicatorHub(_Symbol, Logger);

    // Configura indicadores
    IndHub.SetupRSI(InpRSIPeriod, InpRSITimeframe, InpRSIUpper, InpRSILower);
    IndHub.SetupCCI(InpCCIPeriod, InpCCITimeframe, InpCCIUpper, InpCCILower);
    IndHub.SetupBollinger(InpBBPeriod, InpBBTimeframe, InpBBDeviation);
    IndHub.SetupEnvelopes(InpEnvPeriod, InpEnvTimeframe, InpEnvDeviation);
    IndHub.SetupMA(InpMAFastPeriod, InpMASlowPeriod, InpMATimeframe, InpMAMethod);
    IndHub.SetupHILO(InpHILOPeriod, InpHILOTimeframe);
    IndHub.SetupATR(InpATRPeriod, InpATRTimeframe, InpATRFilterMin, InpATRFilterMax);
    IndHub.SetupADX(InpADXPeriod, InpADXTimeframe, InpADXMin);
    IndHub.SetupVolumeFilter(InpVolFilterMin);

    // Monta lista de indicadores ativos para inicializar
    ENUM_INDICATOR_SIGNAL active_signals[];
    int sig_count = 0;

    // Adiciona indicador principal
    if(InpSignalInd != IND_NONE) {
        sig_count++;
        ArrayResize(active_signals, sig_count);
        active_signals[sig_count - 1] = InpSignalInd;
    }
    // Adiciona confirmações
    ENUM_INDICATOR_SIGNAL confirms[4] = {InpConfirm1, InpConfirm2, InpConfirm3, InpConfirm4};
    for(int i = 0; i < 4; i++) {
        if(confirms[i] != IND_NONE) {
            sig_count++;
            ArrayResize(active_signals, sig_count);
            active_signals[sig_count - 1] = confirms[i];
        }
    }

    IndHub.Initialize(active_signals, sig_count);

    // ═══ 3. Money Manager ═══
    MoneyMgr = new CMoneyManager(Logger);
    MoneyMgr.SetBalanceMode(InpBalanceMode, InpBalanceValue, InpMaxBalance);
    MoneyMgr.SetPresetMode(InpPresetMode, InpPresetFactor);
    MoneyMgr.SetStopLoss(InpMMStopAmount, InpMMStopPercent, InpMMMaxLoss,
                          InpMMWaitLoss, InpMMStopLoss);

    // ═══ 4. Persistência de Estado ═══
    Persistence = new CStatePersistence(_Symbol, InpMagicNumber, Logger);

    // ═══ 5. Recovery Mode ═══
    Recovery = new CRecoveryMode(Logger);
    Recovery.SetTriggers(InpRecoveryDD, InpRecoveryOrders, InpRecoveryLock);
    Recovery.SetRecoveryParams(InpRecoveryCloseMode, InpRecoveryExtraStep,
                                InpRecoveryExtraLot, InpRecoveryTP);

    // ═══ 6. Position Manager ═══
    PosManager = new CPositionManager(_Symbol, InpMagicNumber, Logger);
    PosManager.SetPersistence(Persistence);
    PosManager.SyncOnStartup();

    // ═══ 7. Grid Engine ═══
    Grid = new CGridEngine(_Symbol, InpMagicNumber,
                           InpGridType, InpDirection,
                           LOT_FIXED, InpInitialLot, InpNextLotFactor,
                           InpMaxLevels, InpFixedSpacing,
                           InpATRPeriod, InpATRTimeframe, InpATRMult,
                           PosManager, IndHub, Logger);

    Grid.SetRecoveryMode(Recovery);
    Grid.SetStepMultiplier(InpStepMultiplier, InpStepMin, InpStepMax);
    Grid.SetAddedStep(InpAddedStep, InpAddedStepDecay);
    Grid.SetNextLot(InpNextLotMode, InpNextLotFactor, InpNextLotWait,
                    InpNextLotStartWait, InpNextLotStopWait,
                    InpAllowBigLot, true);
    Grid.SetGiantCandle(InpGiantCandleWaitInit, InpGiantCandleSizeInit,
                        InpGiantCandleWaitGrid, InpGiantCandleSizeGrid);
    Grid.SetIndicatorUsage(InpUseIndInitial, InpUseIndGrid, InpOpenOnCandle);
    Grid.SetWaitTime(InpWaitSameDir);

    // ═══ 8. Smart Close ═══
    Smart = new CSmartClose(_Symbol, InpMagicNumber,
                            InpCloseMode, SMART_CLOSE_MARGIN_TICKS,
                            PosManager, Logger);

    Smart.SetTakeProfit(InpTPMode, InpTPPoints, InpTPMonetary,
                        InpTPAcceptable, 0.0, InpTPMultiplier);
    Smart.SetTPReduction(InpTPReduceType, InpTPReduceDD, 0.0, InpTPReduceTime, true);
    Smart.SetBreakEven(InpBEMode, InpBEPoints, InpBEAcceptable,
                       InpBEType, InpBETrailFactor);
    Smart.SetQuantityLimits(InpLotSumTotal, 0.0, 0.0,
                            InpOrderCountTotal, 0, InpMinProfit);
    Smart.SetAcceptLoss(InpDDAcceptLoss, InpAcceptLoss);

    // ═══ 9. Risk Manager ═══
    Risk = new CRiskManager(InpMagicNumber, InpEquityStopPct, InpMaxDailyDDPct,
                            InpMaxPositions, InpMinMarginPct, Logger);

    Risk.SetCurrentLimits(InpLimitProfitCurrent, InpLimitLossCurrent, 0, 0,
                          InpWaitAfterLimit, InpStopAfterLimit);
    Risk.SetDailyLimits(InpLimitProfitDaily, InpLimitLossDaily, 0.0,
                        InpMaxOrdersDaily, InpMaxWinsDaily, InpMaxLossesDaily, true);
    Risk.SetAccountLimits(InpMinBalance, InpMinEquity, 0.0, 0.0, 0.0, 0, false);

    // ═══ 10. Time Filter ═══
    TFilter = new CTimeFilter(InpStartHour, InpStartMinute,
                              InpEndHour, InpEndMinute,
                              InpFridayEarly, InpFridayEndHour,
                              false, Logger);

    TFilter.SetAllowedDays(false, InpAllowMonday, InpAllowTuesday,
                           InpAllowWednesday, InpAllowThursday,
                           InpAllowFriday, false);
    TFilter.SetCloseMode(InpTimeCloseMode);
    TFilter.SetTimeReduction(InpReduceMinutes, InpReduceType);

    // ═══ Timer para persistência e dashboard ═══
    EventSetTimer(PERSISTENCE_INTERVAL);

    g_initialized = true;
    Logger.Info("EA", "✅ Inicialização completa! v" + OMNIB3_VERSION);
    Logger.Info("EA", Grid.GetSpacingInfo());
    Logger.Info("EA", MoneyMgr.GetStatusString());

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    if(Logger != NULL)
        Logger.Info("EA", StringFormat("Desligando... Razão: %d", reason));

    // Salva estado antes de sair
    if(PosManager != NULL) PosManager.SaveStateNow();

    EventKillTimer();

    if(TFilter     != NULL) { delete TFilter;      TFilter = NULL; }
    if(Risk        != NULL) { delete Risk;          Risk = NULL; }
    if(Smart       != NULL) { delete Smart;         Smart = NULL; }
    if(Grid        != NULL) { delete Grid;          Grid = NULL; }
    if(PosManager  != NULL) { delete PosManager;    PosManager = NULL; }
    if(Recovery    != NULL) { delete Recovery;      Recovery = NULL; }
    if(Persistence != NULL) { delete Persistence;   Persistence = NULL; }
    if(MoneyMgr    != NULL) { delete MoneyMgr;      MoneyMgr = NULL; }
    if(IndHub      != NULL) { delete IndHub;        IndHub = NULL; }
    if(Logger      != NULL) { delete Logger;        Logger = NULL; }

    g_initialized = false;
}

//+------------------------------------------------------------------+
//| Expert tick — Pipeline Principal                                  |
//|                                                                   |
//| 1. MoneyManager → StopLoss do robô atingido?                    |
//| 2. RiskManager  → Equity/DD/margem seguros?                     |
//| 3. Recovery     → Avaliar se ativa/desativa recovery             |
//| 4. SmartClose   → Algum modo de fechamento dispara?             |
//| 5. TimeFilter   → Dentro do pregão da B3?                       |
//| 6. Indicadores  → Qual o sinal dos indicadores?                 |
//| 7. Filtros      → Todos os filtros passam?                      |
//| 8. GridEngine   → Abrir novo nível?                              |
//+------------------------------------------------------------------+
void OnTick() {
    if(!g_initialized) return;

    int levels = PosManager.CountLevels();

    // 1. Money Manager — StopLoss do robô
    if(MoneyMgr.IsStopLossHit()) {
        Risk.ActivateKillSwitch();
        PosManager.ClearAllLevels();
        return;
    }

    // 2. Gestão de Risco
    if(!Risk.IsSafeToTrade(levels)) {
        // Mesmo fora de segurança, Smart Close pode fechar posições
        if(levels > 0) Smart.CheckAndExecute();
        return;
    }

    // 3. Recovery Mode — avalia estado
    if(levels > 0) {
        SGridState state = PosManager.GetGridState();
        Recovery.Evaluate(state.max_drawdown_pct, state.total_levels);

        // Se recovery está ativo, usa modo de fechamento do recovery
        if(Recovery.IsActive()) {
            if(Smart.CheckAndExecute(Recovery.GetCloseMode())) {
                Logger.Info("EA", "🎯 Recovery Close executado");
                // Verifica se deve desativar recovery
                if(PosManager.CountLevels() == 0) Recovery.Reset();
                return;
            }
        }
    }

    // 4. Smart Close (roda SEMPRE — fechamento não depende de horário)
    if(levels > 0) {
        if(Smart.CheckAndExecute()) {
            Logger.Info("EA", "🎯 Smart Close executado");
            return;
        }
    }

    // 5. Filtro de Horário B3
    if(!TFilter.IsTradeAllowed()) {
        // Verifica fechamento no fim do horário
        if(levels > 0 && TFilter.ShouldCloseOnTime()) {
            ENUM_TIME_CLOSE_MODE tclose = TFilter.GetCloseMode();
            if(tclose == TCLOSE_IMMEDIATE) {
                SGridState state = PosManager.GetGridState();
                Smart.CheckAndExecute(CMODE_TP_TOTAL);
                Logger.Info("EA", "⏰ Fechamento por horário");
            }
        }
        return;
    }

    // 6. Indicadores — obtém sinal composto
    int signal = 0;
    if(InpSignalInd != IND_NONE) {
        ENUM_INDICATOR_SIGNAL conf_arr[4];
        ENUM_INDICATOR_STRATEGY conf_strat_arr[4];
        conf_arr[0] = InpConfirm1;  conf_strat_arr[0] = InpConfStrat1;
        conf_arr[1] = InpConfirm2;  conf_strat_arr[1] = InpConfStrat2;
        conf_arr[2] = InpConfirm3;  conf_strat_arr[2] = InpConfStrat3;
        conf_arr[3] = InpConfirm4;  conf_strat_arr[3] = InpConfStrat4;

        signal = IndHub.GetCompositeSignal(InpSignalInd, InpSignalStrat,
                                            conf_arr, conf_strat_arr, 4);
    }

    // 7. Filtros — verifica todos
    if(!IndHub.PassAllFilters()) return;

    // 8. Motor de Grade — abre novos níveis
    Grid.ProcessGrid(signal);
}

//+------------------------------------------------------------------+
//| Timer — Persistência periódica e redução de TP por tempo         |
//+------------------------------------------------------------------+
void OnTimer() {
    if(!g_initialized) return;

    // Auto-save periódico do estado
    PosManager.AutoSave();
}

//+------------------------------------------------------------------+
//| Eventos do gráfico — Botões de controle                          |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam,
                  const double &dparam, const string &sparam) {
    if(id == CHARTEVENT_OBJECT_CLICK) {
        if(sparam == "btn_panic") {
            Logger.Critical("EA", "🔴 PÂNICO pressionado!");
            Risk.ActivateKillSwitch();
            if(PosManager != NULL) PosManager.ClearAllLevels();
            if(Recovery != NULL) Recovery.Reset();
        }
        if(sparam == "btn_reset") {
            Logger.Info("EA", "🟢 RESET pressionado");
            Risk.ResetKillSwitch();
            if(Recovery != NULL) Recovery.Reset();
        }
    }
}

//+------------------------------------------------------------------+
