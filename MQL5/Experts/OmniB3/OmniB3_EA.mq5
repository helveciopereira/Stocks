//+------------------------------------------------------------------+
//|                                                  OmniB3_EA.mq5   |
//|                  Omni-B3 EA v2.49 — Minicontratos B3             |
//|                                                                   |
//|  Grid Trading Avançado para WIN/WDO (contas NETTING)             |
//|  12+ modos de fechamento | 12+ indicadores | Recovery Mode      |
//|  Persistência de estado | Money Management | Filtros avançados   |
//|  NOVO v2.49: Janela Flutuante de Trades e Alvos Gráficos Néon     |
//|  Inspirado na metodologia Daniel Moraes (ToTheMoon v3.5)         |
//|  Adaptado para Real Brasileiro e minicontratos da Bovespa        |
//+------------------------------------------------------------------+
#property copyright   "Projeto Omni-B3"
#property link        "https://github.com/helveciopereira/Stocks"
#property version     "2.49"
#property description "Grid Trading Avançado para Minicontratos B3 (WIN/WDO)"
#property description "12+ modos de fechamento | 12+ indicadores técnicos"
#property description "Persistência de estado | Recovery | Money Management"
#property description "NOVO v2.49: Painel Flutuante de Operações e Alvos Virtuais Néon"
#property description "Adaptado para contas NETTING em Real (BRL)"
#property description "Versao 2.49 com Painel de Operacoes Recentes e Desenhos Graficos"

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
#include <OmniB3/Dashboard.mqh>
#include <OmniB3/SingleOrder.mqh>
#include <OmniB3/NewsFilter.mqh>
#include <OmniB3/Visuals.mqh>

//+------------------------------------------------------------------+
//| =============== DADOS INICIAIS ===============                    |
//+------------------------------------------------------------------+
input string           InpSeparator0 = "======== DADOS INICIAIS ========";   // ===================
input int              InpMagicNumber = 202605;    // Número Mágico (ID único do EA)
input ENUM_LOG_LEVEL   InpLogLevel    = LOG_INFO;  // Nível de Log
input bool             InpLogToFile   = false;     // Salvar Log em Arquivo?
input string           InpComment     = "";        // Comentário nas Ordens (vazio = padrão)
input int              InpSpreadMax   = 30;        // Spread Máximo (pontos)

//+------------------------------------------------------------------+
//| =============== GERENCIAR DINHEIRO ===============                |
//+------------------------------------------------------------------+
input string           InpSeparator1 = "======== GERENCIAR DINHEIRO ========";  // ===================
input ENUM_BALANCE_MODE InpBalanceMode = BAL_FULL_ACCOUNT; // Modo do Saldo do Robô
input double           InpBalanceValue = 10000.0;  // Valor do Saldo (R$) ou Porcentagem
input double           InpMaxBalance   = 0.0;      // Saldo Máximo do Robô (0=sem teto)

input string           InpSepPreset = "---- Multiplicador de Preset ----";  // ----------------
input ENUM_PRESET_MODE InpPresetMode = PRESET_DISABLED;  // Modo xPreset
input double           InpPresetFactor = 10000.0;  // Fator Base (R$ para x1)

input string           InpSepStopMM = "---- StopLoss do Robô ----";  // ----------------
input double           InpMMStopAmount  = 0.0;     // StopLoss Valor (R$, 0=desab.)
input double           InpMMStopPercent = 0.0;     // StopLoss DD% (0=desab.)
input double           InpMMMaxLoss     = 0.0;     // Prejuízo Atual Máx (R$, 0=desab.)
input int              InpMMWaitLoss    = 0;        // Aguardar após Prejuízo (seg)
input bool             InpMMStopLoss    = false;    // Parar após Prejuízo?

//+------------------------------------------------------------------+
//| =============== ABERTURA ===============                           |
//+------------------------------------------------------------------+
input string           InpSeparator2 = "======== ABERTURA ========";  // ===================
input ENUM_RISK_PROFILE InpRiskProfile = PROFILE_CUSTOM;  // Perfil de Risco
input ENUM_GRID_DIRECTION InpDirection = GRID_BUY_ONLY;   // Direção (Compra ou Venda)

input string           InpSepIndicator = "---- Indicador de Sinal ----";  // ----------------
input ENUM_INDICATOR_SIGNAL InpSignalInd = OB3_IND_RSI;            // Indicador Principal
input ENUM_INDICATOR_STRATEGY InpSignalStrat = STRAT_STANDARD;  // Estratégia do Sinal
input ENUM_INDICATOR_SIGNAL InpConfirm1 = OB3_IND_NONE;             // Confirmação 1
input ENUM_INDICATOR_STRATEGY InpConfStrat1 = STRAT_DISABLED;   // Estratégia Confirm. 1
input ENUM_INDICATOR_SIGNAL InpConfirm2 = OB3_IND_NONE;             // Confirmação 2
input ENUM_INDICATOR_STRATEGY InpConfStrat2 = STRAT_DISABLED;   // Estratégia Confirm. 2
input ENUM_INDICATOR_SIGNAL InpConfirm3 = OB3_IND_NONE;             // Confirmação 3
input ENUM_INDICATOR_STRATEGY InpConfStrat3 = STRAT_DISABLED;   // Estratégia Confirm. 3
input ENUM_INDICATOR_SIGNAL InpConfirm4 = OB3_IND_NONE;             // Confirmação 4
input ENUM_INDICATOR_STRATEGY InpConfStrat4 = STRAT_DISABLED;   // Estratégia Confirm. 4
input bool             InpUseIndInitial = true;     // Usar Indicador na Ordem Inicial?
input bool             InpUseIndGrid    = false;    // Usar Indicador nas Ordens da Grid?
input bool             InpOpenOnCandle  = true;     // Abrir Apenas no Início do Candle?

input string           InpSepLots = "---- Lotes ----";  // ----------------
input double           InpInitialLot  = 1.0;       // Volume Inicial (contratos)
input double           InpLotMin      = 1.0;       // Lote Mínimo
input double           InpLotMax      = 100.0;     // Lote Máximo

input string           InpSepWait = "---- Espera ----";  // ----------------
input int              InpWaitSameDir   = 30;      // Espera entre Ordens Mesma Dir. (seg)
input int              InpGiantCandleWaitInit = 0;  // Espera Candle Gigante Inicial (seg)
input int              InpGiantCandleSizeInit = 100;// Tamanho Candle Gigante Inicial (pts)
input int              InpGiantCandleWaitGrid = 0;  // Espera Candle Gigante Grid (seg)
input int              InpGiantCandleSizeGrid = 100;// Tamanho Candle Gigante Grid (pts)
input double           InpMaxDDNoOpen  = 50.0;     // Não Abrir se DD Robô > % (0=desab.)

//+------------------------------------------------------------------+
//| =============== MODO GRADE ===============                        |
//+------------------------------------------------------------------+
input string           InpSeparator3 = "======== MODO GRADE (GRID) ========";  // ===================
input ENUM_GRID_TYPE   InpGridType    = GRID_FIXED;  // Tipo de Grade
input ENUM_CLOSE_MODE  InpCloseMode   = CMODE_SMART_WORST;  // Modo de Fechamento
input int              InpMaxLevels   = 5;          // Máximo de Níveis
input double           InpMinProfit   = 0.0;        // Lucro Mínimo p/ Fechar (R$)

input string           InpSepTP = "---- TakeProfit ----";  // ----------------
input ENUM_TP_MODE     InpTPMode       = TP_FIXED_POINTS;  // Modo do TakeProfit
input double           InpTPPoints     = 100.0;    // TakeProfit (pontos)
input double           InpTPMonetary   = 0.0;      // TakeProfit Monetário (R$)
input double           InpTPAcceptable = 0.0;       // TP Aceitável (pontos, negativo=aceitar perda)
input double           InpTPMultiplier = 1.0;       // Multiplicador do TP
input ENUM_TP_REDUCE_TYPE InpTPReduceType = TP_REDUCE_NONE;  // Modo de Redução do TP
input double           InpTPReduceDD   = 100.0;    // DD% para Reduzir TP
input int              InpTPReduceTime = 0;         // Minutos para Redução do TP

input string           InpSepBE = "---- BreakEven ----";  // ----------------
input ENUM_BE_MODE     InpBEMode      = BE_DISABLED;  // Modo BreakEven
input double           InpBEPoints    = 0.0;       // BreakEven (pontos)
input double           InpBEAcceptable = 0.0;      // BE Aceitável (pontos)
input ENUM_BE_TYPE     InpBEType      = BE_STATIC;  // Tipo BreakEven
input double           InpBETrailFactor = 1.0;     // Fator Trailing

input string           InpSepStep = "---- Passo da Grade ----";  // ----------------
input int              InpFixedSpacing = 300;       // Espaçamento Fixo (pontos)
input double           InpStepMultiplier = 1.0;     // Multiplicador do Passo (1=sem mult)
input int              InpStepMin     = 0;          // Passo Mínimo (pontos, 0=sem)
input int              InpStepMax     = 0;          // Passo Máximo (pontos, 0=sem)
input int              InpAddedStep   = 0;          // Pontos Extras na Abertura
input int              InpAddedStepDecay = 0;       // Segundos para Zerar Extras

input string           InpSepATR = "---- ATR (Grade Dinâmica) ----";  // ----------------
input int              InpATRPeriod   = 14;         // Período do ATR
input ENUM_TIMEFRAMES  InpATRTimeframe = PERIOD_M5; // Timeframe do ATR
input double           InpATRMult     = 1.5;        // Multiplicador ATR

input string           InpSepNext = "---- Próximo Lote ----";  // ----------------
input ENUM_NEXT_LOT_MODE InpNextLotMode = NEXT_LOT_WAIT_MULTIPLY;  // Modo do Próximo Lote
input double           InpNextLotFactor = 1.3;      // Fator do Próximo Lote
input int              InpNextLotWait  = 600;       // Espera entre Ordens da Grid (seg)
input int              InpNextLotStartWait = 1;     // Começar a Esperar no Nível
input int              InpNextLotStopWait = 100;    // Parar de Esperar no Nível
input bool             InpAllowBigLot = false;      // Permitir Lote Grande?

input string           InpSepQuantity = "---- Fechamento por Quantidade ----";  // ----------------
input double           InpLotSumTotal  = 0.0;       // Fechar se Soma Lotes > (0=desab.)
input int              InpOrderCountTotal = 0;       // Fechar se Qtde Ordens > (0=desab.)
input double           InpAcceptLoss   = 0.0;       // Aceitar Prejuízo (R$, negativo)
input double           InpDDAcceptLoss = 0.0;        // DD% para Aceitar Perda

input string           InpSepRecov = "---- Recovery ----";  // ----------------
input double           InpRecoveryDD    = 100.0;    // DD% para Ativar Recovery (100=desab.)
input int              InpRecoveryOrders = 0;        // Qtde Ordens p/ Recovery (0=desab.)
input bool             InpRecoveryLock   = false;    // Travar em Recovery?
input ENUM_CLOSE_MODE  InpRecoveryCloseMode = CMODE_ACCEPT_LOSS;  // Modo Fech. Recovery
input int              InpRecoveryExtraStep = 0;     // Pontos Extras no Passo (Recovery)
input double           InpRecoveryExtraLot  = 0.0;   // Fator Extra no Lote (Recovery)
input int              InpRecoveryTP  = 100;         // TakeProfit em Recovery (pts)

//+------------------------------------------------------------------+
//| =============== INDICADORES ===============                       |
//+------------------------------------------------------------------+
input string           InpSeparator4 = "======== INDICADORES ========";  // ===================
input string           InpSepRSI = "---- RSI ----";  // ----------------
input int              InpRSIPeriod = 14;           // Período RSI
input ENUM_TIMEFRAMES  InpRSITimeframe = PERIOD_M5; // Timeframe RSI
input double           InpRSIUpper  = 70.0;         // RSI Sobrecompra
input double           InpRSILower  = 30.0;         // RSI Sobrevenda

input string           InpSepCCI = "---- CCI ----";  // ----------------
input int              InpCCIPeriod = 14;           // Período CCI
input ENUM_TIMEFRAMES  InpCCITimeframe = PERIOD_M5; // Timeframe CCI
input double           InpCCIUpper  = 100.0;        // CCI Superior
input double           InpCCILower  = -100.0;       // CCI Inferior

input string           InpSepBB = "---- Bollinger Bands ----";  // ----------------
input int              InpBBPeriod = 20;            // Período Bollinger
input ENUM_TIMEFRAMES  InpBBTimeframe = PERIOD_M5;  // Timeframe Bollinger
input double           InpBBDeviation = 2.0;        // Desvio Bollinger

input string           InpSepEnv = "---- Envelopes ----";  // ----------------
input int              InpEnvPeriod = 14;           // Período Envelopes
input ENUM_TIMEFRAMES  InpEnvTimeframe = PERIOD_M5; // Timeframe Envelopes
input double           InpEnvDeviation = 0.1;       // Desvio Envelopes (%)

input string           InpSepMA = "---- Médias Móveis ----";  // ----------------
input int              InpMAFastPeriod = 9;         // Período MA Rápida
input int              InpMASlowPeriod = 21;        // Período MA Lenta
input ENUM_TIMEFRAMES  InpMATimeframe = PERIOD_M5;  // Timeframe MAs
input ENUM_MA_METHOD   InpMAMethod = MODE_SMA;      // Método (SMA/EMA)

input string           InpSepHILO = "---- HILO ----";  // ----------------
input int              InpHILOPeriod = 3;           // Período HILO
input ENUM_TIMEFRAMES  InpHILOTimeframe = PERIOD_M5;// Timeframe HILO

input string           InpSepADX = "---- ADX ----";  // ----------------
input int              InpADXPeriod = 14;           // Período ADX
input ENUM_TIMEFRAMES  InpADXTimeframe = PERIOD_M5; // Timeframe ADX
input double           InpADXMin = 22.0;            // ADX Mínimo (força)

//+------------------------------------------------------------------+
//| =============== FILTROS ===============                            |
//+------------------------------------------------------------------+
input string           InpSeparator5 = "======== FILTROS ========";  // ===================
input double           InpATRFilterMin = 0.0;       // ATR Mínimo (0=desab.)
input double           InpATRFilterMax = 999999.0;  // ATR Máximo
input long             InpVolFilterMin = 0;          // Volume Mínimo (0=desab.)

//+------------------------------------------------------------------+
//| =============== LIMITES ===============                            |
//+------------------------------------------------------------------+
input string           InpSeparator6 = "======== LIMITES (STOP) ========";  // ===================
input string           InpSepCurrent = "---- Atual ----";  // ----------------
input double           InpLimitProfitCurrent = 0.0;  // Lucro Máx Atual (R$, 0=desab.)
input double           InpLimitLossCurrent   = 0.0;  // Perda Máx Atual (R$, 0=desab.)
input int              InpWaitAfterLimit     = 0;    // Aguardar após Limite (seg)
input bool             InpStopAfterLimit     = false;// Parar após Limite?

input string           InpSepDaily = "---- Diário ----";  // ----------------
input double           InpLimitProfitDaily = 0.0;    // Lucro Máx Diário (R$, 0=desab.)
input double           InpLimitLossDaily   = 0.0;    // Perda Máx Diária (R$, 0=desab.)
input double           InpMaxDailyDDPct    = 3.0;    // DD Diário Máximo (%)
input int              InpMaxOrdersDaily   = 0;      // Máx Ordens/Dia (0=sem limite)
input int              InpMaxWinsDaily     = 0;       // Máx Ganhos/Dia (0=sem limite)
input int              InpMaxLossesDaily   = 0;       // Máx Perdas/Dia (0=sem limite)

input string           InpSepAccount = "---- Conta ----";  // ----------------
input double           InpEquityStopPct  = 85.0;     // Equity Stop (% do saldo)
input int              InpMaxPositions   = 10;        // Máx Níveis Simultâneos
input double           InpMinMarginPct   = 30.0;     // Margem Livre Mínima (%)
input double           InpMinBalance     = 0.0;       // Saldo Mínimo (R$, 0=desab.)
input double           InpMinEquity      = 0.0;       // Equity Mínima (R$, 0=desab.)

//+------------------------------------------------------------------+
//| =============== HORÃ?RIO ===============                            |
//+------------------------------------------------------------------+
input string           InpSeparator7 = "======== HORÃ?RIO PERMITIDO ========";  // ===================
input int              InpStartHour    = 9;          // Hora de Início
input int              InpStartMinute  = 5;          // Minuto de Início
input int              InpEndHour      = 17;         // Hora de Fim
input int              InpEndMinute    = 40;         // Minuto de Fim
input bool             InpFridayEarly  = true;       // Fechar Cedo na Sexta?
input int              InpFridayEndHour = 17;        // Hora Fim na Sexta
input ENUM_TIME_CLOSE_MODE InpTimeCloseMode = TCLOSE_NONE;  // Modo Fechamento no Horário
input int              InpReduceMinutes = 60;        // Minutos antes do Fim p/ Reduzir TP
input ENUM_TIME_REDUCE_TYPE InpReduceType = TIME_REDUCE_NONE;  // O que Reduzir?
input bool             InpUseServerTime = true;      // Usar Hora do Servidor (Recomendado B3)

input string           InpSepDays = "---- Dias Permitidos ----";  // ----------------
input bool             InpAllowMonday    = true;     // Operar Segunda?
input bool             InpAllowTuesday   = true;     // Operar Terça?
input bool             InpAllowWednesday = true;     // Operar Quarta?
input bool             InpAllowThursday  = true;     // Operar Quinta?
input bool             InpAllowFriday    = true;     // Operar Sexta?

//+------------------------------------------------------------------+
//| =============== FASE 2: NOVOS INPUTS ===============              |
//+------------------------------------------------------------------+
input string           InpSeparator8 = "======== FASE 2: PAINEL E DASHBOARD ========"; // ===================
input bool             InpUseDashboard   = true;     // Habilitar Painel Gráfico?
input ENUM_DASHBOARD_THEME InpDashboardTheme = THEME_DARK_MODERN; // Tema do Painel
input int              InpDashboardX     = 20;       // Posição X do Painel (pixels)
input int              InpDashboardY     = 40;       // Posição Y do Painel (pixels)

input string           InpSeparatorVisuals = "======== CONFIGURAÇÕES VISUAIS v2.45 ========"; // ===================
input bool             InpShowTargetLines       = true;  // Exibir Linhas de Alvos Virtuais?
input bool             InpShowTradeHistory     = true;  // Exibir Mapa Histórico de Trades?
input bool             InpShowRecentTradesPanel = true;  // Exibir Painel de Trades Recentes?

input string           InpSeparator9 = "======== FASE 2: ORDEM ÚNICA (SINGLE) ========"; // ===================
input ENUM_SINGLE_ORDER_MODE InpSingleOrderMode = SINGLE_DISABLED; // Modo de Operação (Ordem Única)
input double           InpSingleSLPoints = 200.0;    // StopLoss do Trade (pontos)
input double           InpSingleTPPoints = 150.0;    // TakeProfit do Trade (pontos)
input double           InpSingleBEActivation = 100.0; // Ativação BreakEven (pontos, 0=desab.)
input double           InpSingleBEMargin = 10.0;     // Margem Acima da Entrada (pontos)
input ENUM_MARTINGALE_MODE InpSingleMartMode = MARTINGALE_NONE; // Modo de Martingale
input double           InpSingleMartMultiplier = 2.0; // Multiplicador de Lotes
input int              InpSingleMartSteps = 3;       // Limite de Multiplicações Consecutivas
input int              InpSingleWaitLoss = 0;        // Espera após Perda (segundos)
input int              InpSingleWaitWin  = 0;        // Espera após Ganho (segundos)
input bool             InpSingleCloseOpposite = true; // Fechar posição se houver sinal contrário?

input string           InpSeparatorTrailing = "======== TRAILING STOP & TRAILING TP (v2.35) ========"; // ===================
input bool             InpUseTrailing      = false;     // Habilitar Gain/Stop Gain Móvel?
input double           InpTrailingTrigger  = 150.0;     // Gatilho para Ativar (pontos)
input double           InpTrailingStopDist = 150.0;     // Distância do Stop Gain (pontos)
input double           InpTrailingTPDist   = 200.0;     // Distância do Gain Móvel (pontos)
input double           InpTrailingStep     = 10.0;      // Passo de Atualização (pontos)

input string           InpSeparator10 = "======== FASE 2: FILTRO DE NOTÃ?CIAS ========"; // ===================
input bool             InpNewsEnabled    = false;    // Habilitar Filtro de Notícias?
input ENUM_NEWS_IMPORTANCE InpNewsMinImportance = NEWS_IMPORTANCE_HIGH; // Importância Mínima
input ENUM_NEWS_ACTION InpNewsAction     = NEWS_ACTION_STOP_INITIAL; // Ação do EA Durante Notícia
input int              InpNewsBefore     = 15;       // Bloquear Minutos Antes da Notícia
input int              InpNewsAfter      = 15;       // Bloquear Minutos Depois da Notícia
input string           InpNewsCurrency   = "BRL";    // Moeda Filtrada (BRL, USD ou ALL)

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
CDashboard        *Dash;
CSingleOrder      *Single;
CNewsFilter       *News;
CVisuals           *Visuals;
CRecentTradesPanel *RecentPanel;

bool               g_initialized = false;
bool               g_ea_paused = false;     // Controle interativo de pausa via dashboard
string             g_status_msg = "Aguardando mercado";

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit() {
    // === 1. Logger (primeiro — todos dependem dele) ===
    Logger = new CLogger(InpLogLevel, InpLogToFile);
    Logger.Info("EA", StringFormat("=== Omni-B3 EA v%s === Minicontratos B3", OMNIB3_VERSION));
    Logger.Info("EA", StringFormat("Símbolo: %s | Magic: %d", _Symbol, InpMagicNumber));

    // Info do símbolo para debug
    double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double vol_min    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double vol_step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    Logger.Info("EA", StringFormat("TickSize=%.2f | TickValue=R$%.2f | VolMin=%.0f | VolStep=%.0f",
                                   tick_size, tick_value, vol_min, vol_step));

    // === 2. Indicator Hub ===
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
    if(InpSignalInd != OB3_IND_NONE) {
        sig_count++;
        ArrayResize(active_signals, sig_count);
        active_signals[sig_count - 1] = InpSignalInd;
    }
    // Adiciona confirmações
    ENUM_INDICATOR_SIGNAL confirms[4] = {InpConfirm1, InpConfirm2, InpConfirm3, InpConfirm4};
    for(int i = 0; i < 4; i++) {
        if(confirms[i] != OB3_IND_NONE) {
            sig_count++;
            ArrayResize(active_signals, sig_count);
            active_signals[sig_count - 1] = confirms[i];
        }
    }

    IndHub.Initialize(active_signals, sig_count);

    // === 3. Money Manager ===
    MoneyMgr = new CMoneyManager(Logger);
    MoneyMgr.SetBalanceMode(InpBalanceMode, InpBalanceValue, InpMaxBalance);
    MoneyMgr.SetPresetMode(InpPresetMode, InpPresetFactor);
    MoneyMgr.SetStopLoss(InpMMStopAmount, InpMMStopPercent, InpMMMaxLoss,
                          InpMMWaitLoss, InpMMStopLoss);

    // === 4. Persistência de Estado ===
    Persistence = new CStatePersistence(_Symbol, InpMagicNumber, Logger);

    // === 5. Recovery Mode ===
    Recovery = new CRecoveryMode(Logger);
    Recovery.SetTriggers(InpRecoveryDD, InpRecoveryOrders, InpRecoveryLock);
    Recovery.SetRecoveryParams(InpRecoveryCloseMode, InpRecoveryExtraStep,
                                InpRecoveryExtraLot, InpRecoveryTP);

    // === 6. Position Manager ===
    PosManager = new CPositionManager(_Symbol, InpMagicNumber, Logger);
    PosManager.SetPersistence(Persistence);
    PosManager.SyncOnStartup();

    // === 7. Grid Engine ===
    // Sanitização e validação estrita de InpDirection (evita presets inválidos fora do enumerador)
    ENUM_GRID_DIRECTION verified_direction = InpDirection;
    if(InpDirection != GRID_BUY_ONLY && InpDirection != GRID_SELL_ONLY) {
        Logger.Warning("EA", StringFormat("[AVISO] Direção de grade inválida (%d) detectada! Normalizando para GRID_BUY_ONLY (0).", (int)InpDirection));
        verified_direction = GRID_BUY_ONLY;
    }

    Grid = new CGridEngine(_Symbol, InpMagicNumber,
                           InpGridType, verified_direction,
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

    // === 8. Smart Close ===
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
    Smart.SetTrailing(InpUseTrailing, InpTrailingTrigger, InpTrailingStopDist, InpTrailingTPDist, InpTrailingStep);

    // === 9. Risk Manager ===
    Risk = new CRiskManager(InpMagicNumber, InpEquityStopPct, InpMaxDailyDDPct,
                            InpMaxPositions, InpMinMarginPct, Logger);

    Risk.SetCurrentLimits(InpLimitProfitCurrent, InpLimitLossCurrent, 0, 0,
                          InpWaitAfterLimit, InpStopAfterLimit);
    Risk.SetDailyLimits(InpLimitProfitDaily, InpLimitLossDaily, 0.0,
                        InpMaxOrdersDaily, InpMaxWinsDaily, InpMaxLossesDaily, true);
    Risk.SetAccountLimits(InpMinBalance, InpMinEquity, 0.0, 0.0, 0.0, 0, false);

    // === 10. Time Filter ===
    TFilter = new CTimeFilter(InpStartHour, InpStartMinute,
                              InpEndHour, InpEndMinute,
                              InpFridayEarly, InpFridayEndHour,
                              InpUseServerTime, Logger);

    TFilter.SetAllowedDays(false, InpAllowMonday, InpAllowTuesday,
                           InpAllowWednesday, InpAllowThursday,
                           InpAllowFriday, false);
    TFilter.SetCloseMode(InpTimeCloseMode);
    TFilter.SetTimeReduction(InpReduceMinutes, InpReduceType);

    // === 11. FASE 2: Single Order Módulo ===
    Single = new CSingleOrder();
    Single.Init(Logger, InpMagicNumber, InpSingleOrderMode, InpSingleSLPoints, InpSingleTPPoints,
                InpSingleBEActivation, InpSingleBEMargin, InpSingleMartMode, InpSingleMartMultiplier,
                InpSingleMartSteps, InpSingleWaitLoss, InpSingleWaitWin, InpSingleCloseOpposite,
                InpUseTrailing, InpTrailingTrigger, InpTrailingStopDist, InpTrailingTPDist, InpTrailingStep);

    // === 12. FASE 2: News Filter Módulo ===
    News = new CNewsFilter();
    News.Init(Logger, InpNewsEnabled, InpNewsMinImportance, InpNewsAction, InpNewsBefore, InpNewsAfter, InpNewsCurrency);

    // === 13. FASE 2: Dashboard Visual ===
    Dash = new CDashboard();
    if(InpUseDashboard) {
        Dash.Init(Logger, InpDashboardTheme, InpDashboardX, InpDashboardY);
    }

    // === 14. OMNI-B3 v2.45: Módulo Visual e Painel de Operações Recentes ===
    Visuals = new CVisuals();
    if(InpShowTradeHistory || InpShowTargetLines) {
        Visuals.Init(Logger, InpMagicNumber, _Symbol);
    }

    RecentPanel = new CRecentTradesPanel();
    if(InpShowRecentTradesPanel) {
        int recent_x = InpDashboardX + 340; // Posicionado ao lado do dashboard principal (largura 320 + folga 20)
        int recent_y = InpDashboardY;
        RecentPanel.Init(Logger, InpDashboardTheme, recent_x, recent_y, InpMagicNumber, _Symbol);
        RecentPanel.Update();
    }

    // Timer periódico de persistência e redesenho
    EventSetTimer(SMART_CLOSE_COOLDOWN); // Reduzido de 30 para 5 segundos para dashboard mais dinâmico

    g_initialized = true;
    g_status_msg = "Rodando normal";
    Logger.Info("EA", "[OK] Inicialização completa! v" + OMNIB3_VERSION);
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

    // Limpeza de objetos da Fase 2
    if(Dash        != NULL) { Dash.Deinit(); delete Dash; Dash = NULL; }
    if(RecentPanel != NULL) { RecentPanel.Deinit(); delete RecentPanel; RecentPanel = NULL; }
    if(Visuals     != NULL) { Visuals.Deinit(); delete Visuals; Visuals = NULL; }
    if(Single      != NULL) { delete Single;        Single = NULL; }
    if(News        != NULL) { delete News;          News = NULL; }

    // Limpeza base
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
//+------------------------------------------------------------------+
void OnTick() {
    if(!g_initialized) return;

    // Se o robô foi pausado pelo usuário via dashboard, suspende execução de novos trades
    if(g_ea_paused) {
        g_status_msg = "Suspenso (Pausa)";
        return;
    }

    int levels = PosManager.CountLevels();
    datetime current_time = TimeCurrent();

    // FASE 2: FILTRO DE NOTÃ?CIAS
    int news_act_val = (int)NEWS_ACTION_NONE;
    bool has_news_block = News.CheckNewsBlock(current_time, news_act_val);
    ENUM_NEWS_ACTION news_act = (ENUM_NEWS_ACTION)news_act_val;

    if(has_news_block) {
        if(news_act == NEWS_ACTION_CLOSE_ALL) {
            Logger.Warning("EA", "[ALERTA] Notícia ativa com ação FECHAR TUDO. Encerrando operações.");
            PosManager.ClearAllLevels();
            g_status_msg = "Bloq. Noticia (Fechado)";
            return;
        }
        else if(news_act == NEWS_ACTION_STOP_ALL) {
            g_status_msg = "Bloq. Noticia (Stop All)";
            if(levels > 0) Smart.CheckAndExecute(); // Só gerencia fechamentos por segurança
            return;
        }
    }

    // 1. Money Manager — StopLoss do robô
    if(MoneyMgr.IsStopLossHit()) {
        Risk.ActivateKillSwitch();
        PosManager.ClearAllLevels();
        g_status_msg = "StopLoss Robô Atingido";
        return;
    }

    // 2. Gestão de Risco
    if(!Risk.IsSafeToTrade(levels)) {
        g_status_msg = "Bloqueado por Risco";
        if(levels > 0) Smart.CheckAndExecute();
        return;
    }

    // FASE 2: TRAILING BREAKEVEN E TRAILING STOP DO MODO ORDEM ÚNICA (SINGLE ORDER)
    if(InpSingleOrderMode == SINGLE_ENABLED && levels > 0) {
        double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
        Single.ManageBreakEven(_Symbol, bid, ask, tick);
        Single.ManageTrailing(_Symbol, bid, ask, tick);
    }

    // 3. Recovery Mode — avalia estado (apenas em modo grade tradicional)
    if(InpSingleOrderMode == SINGLE_DISABLED && levels > 0) {
        SGridState state = PosManager.GetGridState();
        Recovery.Evaluate(state.max_drawdown_pct, state.total_levels);

        if(Recovery.IsActive()) {
            g_status_msg = "Modo Recovery Ativo";
            if(Smart.CheckAndExecute(Recovery.GetCloseMode())) {
                Logger.Info("EA", "[ALVO] Recovery Close executado");
                if(PosManager.CountLevels() == 0) Recovery.Reset();
                return;
            }
        }
    }

    // 4. Smart Close (roda SEMPRE — fechamento não depende de horário)
    if(levels > 0) {
        if(Smart.CheckAndExecute()) {
            Logger.Info("EA", "[ALVO] Smart Close executado");
            g_status_msg = "Fechamento Smart";
            return;
        }
    }

    // Salvaguarda Estrita de Day Trade B3: Se o robô opera em modo Day Trade (TCLOSE_IMMEDIATE)
    // e existem posições ativas cujas aberturas ocorreram em datas passadas (dias anteriores),
    // nós liquidamos tudo a mercado imediatamente no primeiro tick do dia para evitar Swing Trade involuntário!
    if(levels > 0 && InpTimeCloseMode == TCLOSE_IMMEDIATE) {
        SGridState state = PosManager.GetGridState();
        if(state.oldest_level_time > 0) {
            MqlDateTime oldest_dt, current_dt;
            TimeToStruct(state.oldest_level_time, oldest_dt);
            TimeToStruct(TimeCurrent(), current_dt);
            
            // Se o dia da abertura da posição foi anterior ao dia atual do servidor
            if(oldest_dt.year < current_dt.year || 
               (oldest_dt.year == current_dt.year && oldest_dt.mon < current_dt.mon) || 
               (oldest_dt.year == current_dt.year && oldest_dt.mon == current_dt.mon && oldest_dt.day < current_dt.day)) {
                
                Logger.Warning("EA", StringFormat("ðŸ›¡ï¸? Salvaguarda Day Trade acionada! Detectada posição antiga de %04d.%02d.%02d. Liquidando toda a grade a mercado.", 
                                                   oldest_dt.year, oldest_dt.mon, oldest_dt.day));
                
                // Limpa os níveis virtuais
                PosManager.ClearAllLevels();
                
                // E liquida a posição real física no MT5
                if(PositionSelect(_Symbol) && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) {
                    ulong ticket = PositionGetInteger(POSITION_TICKET);
                    CTrade trade;
                    trade.SetExpertMagicNumber(InpMagicNumber);
                    trade.PositionClose(ticket);
                }
                
                g_status_msg = "Resgate Day Trade Executado";
                return;
            }
        }
    }

    // 5. Filtro de Horário B3
    if(!TFilter.IsTradeAllowed()) {
        g_status_msg = "Fora de Horário";
        if(levels > 0 && TFilter.ShouldCloseOnTime()) {
            ENUM_TIME_CLOSE_MODE tclose = TFilter.GetCloseMode();
            if(tclose == TCLOSE_IMMEDIATE) {
                Smart.CheckAndExecute(CMODE_TP_TOTAL);
                Logger.Info("EA", "Fechamento por horário");
            }
        }
        return;
    }

    // 6. Indicadores — obtém sinal composto
    int signal = 0;
    if(InpSignalInd != OB3_IND_NONE) {
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
    if(!IndHub.PassAllFilters()) {
        g_status_msg = "Sinal bloqueado por Filtro";
        return;
    }

    // FASE 2: BLOQUEIO PARCIAL DE NOTÃ?CIA (NãO ABRE NOVA SÉRIE, MAS PERMITE MANTENÇãO DE GRID)
    if(has_news_block && news_act == NEWS_ACTION_STOP_INITIAL) {
        if(levels == 0) {
            g_status_msg = "Bloq. Inicial (Noticia)";
            return; // Bloqueia início da série
        }
    }

    g_status_msg = (levels > 0) ? "Grade em Andamento" : "Aguardando Sinal";

    // 8. FASE 2: PIPELINE DO MODO ORDEM ÚNICA
    if(InpSingleOrderMode == SINGLE_ENABLED) {
        // Verifica se há fechamento da ordem por sinal contrário
        if(levels > 0) {
            if(Single.CheckOppositeSignalClose(_Symbol, signal)) {
                g_status_msg = "Fechado Sinal Contrário";
                return;
            }
        }
        
        // Tentativa de abertura de nova ordem
        if(levels == 0 && signal != 0) {
            if(Single.CanOpenNewOrder(current_time)) {
                double lot = Single.CalculateLot(InpInitialLot, InpLotMin, InpLotMax);
                if(Single.OpenOrder(_Symbol, signal, lot, OMNIB3_COMMENT_PREFIX + "_Single")) {
                    // Adiciona o nível virtual no PositionManager para rastreamento centralizado
                    double price = (signal == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
                    PosManager.RegisterLevel(price, lot, signal);
                    g_status_msg = "Ordem Única Aberta";
                }
            }
        }
    } 
    // PIPELINE DA GRADE TRADICIONAL (GRID TRADING v2.0)
    else {
        Grid.ProcessGrid(signal);
    }

    // === OMNI-B3 v2.45: Atualização em Tempo Real de Linhas Horizontais de Alvos e Histórico ===
    if(g_initialized) {
        if(InpShowTargetLines && Visuals != NULL) {
            int levels_cnt = PosManager.CountLevels();
            bool is_active = (levels_cnt > 0);
            double avg_prc = 0.0;
            double tp_prc = 0.0;
            double sl_prc = 0.0;
            int pos_type = POSITION_TYPE_BUY;

            if(is_active) {
                SGridState state = PosManager.GetGridState();
                avg_prc = state.avg_price;
                tp_prc = Smart.GetTakeProfitPrice();
                sl_prc = Smart.GetStopLossPrice();
                
                if(InpSingleOrderMode == SINGLE_ENABLED) {
                    pos_type = (Single.GetPositionDirection() == 1) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
                } else {
                    pos_type = (InpDirection == GRID_BUY_ONLY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
                }
            }
            Visuals.DrawTargetLines(is_active, avg_prc, tp_prc, sl_prc, pos_type);
        }

        if(InpShowTradeHistory && Visuals != NULL) {
            Visuals.OnTickVisual();
        }
    }
}

//+------------------------------------------------------------------+
//| Timer — Persistência e Atualização do Dashboard                   |
//+------------------------------------------------------------------+
void OnTimer() {
    if(!g_initialized) return;

    // Auto-save periódico do estado
    PosManager.AutoSave();

    // FASE 2: ATUALIZAÇãO DO DASHBOARD GRÃ?FICO
    if(InpUseDashboard && Dash != NULL) {
        SGridState g_state = PosManager.GetGridState();
        double balance = AccountInfoDouble(ACCOUNT_BALANCE);
        double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
        double d_profit = Risk.GetDailyProfit();
        double d_max_dd = Risk.GetDailyMaxDrawdown();
        SNewsState n_state = News.GetNextNewsState();

        Dash.Update(g_state, balance, equity, d_profit, d_max_dd, g_status_msg, g_ea_paused, n_state);
    }

    // FASE 2: ATUALIZAÇãO DO MONITOR DE OPERAÇÕES RECENTES (v2.45)
    if(InpShowRecentTradesPanel && RecentPanel != NULL) {
        RecentPanel.Update();
    }
}

//+------------------------------------------------------------------+
//| Eventos do gráfico — Botões interativos                           |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam,
                  const double &dparam, const string &sparam) {
    if(!g_initialized) return;

    // Repassa o evento para a classe do Dashboard tratar
    if(InpUseDashboard && Dash != NULL) {
        string action = Dash.OnChartEvent(id, lparam, dparam, sparam);
        
        if(action != "") {
            if(action == "Panic") {
                Logger.Critical("EA", "[ALERTA] BOTãO PÂNICO PREVENTIVO ACIONADO VIA DASHBOARD!");
                Risk.ActivateKillSwitch();
                PosManager.ClearAllLevels();
                
                // Fecha a posição real física no MT5
                if(PositionSelect(_Symbol) && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) {
                    ulong ticket = PositionGetInteger(POSITION_TICKET);
                    CTrade trade;
                    trade.SetExpertMagicNumber(InpMagicNumber);
                    trade.PositionClose(ticket);
                }
                
                if(Recovery != NULL) Recovery.Reset();
                g_status_msg = "PANICO - BLOQUEADO";
            }
            else if(action == "CloseAll") {
                Logger.Warning("EA", " Fechando todas as ordens e niveis via Painel.");
                PosManager.ClearAllLevels();
                
                // Fecha a posição real física no MT5
                if(PositionSelect(_Symbol) && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) {
                    ulong ticket = PositionGetInteger(POSITION_TICKET);
                    CTrade trade;
                    trade.SetExpertMagicNumber(InpMagicNumber);
                    trade.PositionClose(ticket);
                }
                
                g_status_msg = "Zerar via Painel";
            }
            else if(action == "Pause") {
                g_ea_paused = !g_ea_paused;
                Logger.Info("EA", g_ea_paused ? "¸ EA pausado pelo painel" : "[RUN] EA retomado pelo painel");
                g_status_msg = g_ea_paused ? "Pausado via Painel" : "Rodando normal";
            }
            else if(action == "Reset") {
                Logger.Info("EA", "[RESET] Resetando Kill-Switch e limites diarios via painel.");
                Risk.ResetKillSwitch();
                if(Recovery != NULL) Recovery.Reset();
                if(Single != NULL) Single.ResetMartingale();
                g_status_msg = "Limites resetados";
            }
            
            // Força um timer tick para atualizar visualmente os botões
            OnTimer();
        }
    }

    // Tratamento dos cliques clássicos caso o painel esteja desativado
    if(!InpUseDashboard && id == CHARTEVENT_OBJECT_CLICK) {
        if(sparam == "btn_panic") {
            Logger.Critical("EA", "[PANICO] PÂNICO clássico pressionado!");
            Risk.ActivateKillSwitch();
            if(PosManager != NULL) PosManager.ClearAllLevels();
            
            // Fecha a posição real física no MT5
            if(PositionSelect(_Symbol) && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) {
                ulong ticket = PositionGetInteger(POSITION_TICKET);
                CTrade trade;
                trade.SetExpertMagicNumber(InpMagicNumber);
                trade.PositionClose(ticket);
            }
            
            if(Recovery != NULL) Recovery.Reset();
        }
        if(sparam == "btn_reset") {
            Logger.Info("EA", "[RESET] RESET clássico pressionado");
            Risk.ResetKillSwitch();
            if(Recovery != NULL) Recovery.Reset();
        }
    }
}
