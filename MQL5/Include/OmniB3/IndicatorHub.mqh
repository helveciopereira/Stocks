//+------------------------------------------------------------------+
//|                                                IndicatorHub.mqh  |
//|              Omni-B3 EA v2.45 — Hub Central de Indicadores        |
//|       Sistema unificado de sinais e filtros técnicos              |
//+------------------------------------------------------------------+
#property copyright "Projeto Omni-B3"
#property link      "https://github.com/helveciopereira/Stocks"
#property version   "2.45"
#property strict

#include "Defines.mqh"
#include "Logger.mqh"

//+------------------------------------------------------------------+
//| Hub centralizado de indicadores técnicos                          |
//|                                                                   |
//| Gerencia handles compartilhados para evitar duplicação de         |
//| cálculos. Cada indicador retorna um sinal normalizado:            |
//|   +1 = compra, -1 = venda, 0 = neutro                            |
//| O sistema suporta 1 indicador principal + 4 confirmações          |
//| e filtros independentes que bloqueiam operações.                  |
//+------------------------------------------------------------------+
class CIndicatorHub {
private:
    string          m_symbol;
    CLogger        *m_logger;

    // Handles dos indicadores (INVALID_HANDLE = não utilizado)
    int  m_h_rsi;
    int  m_h_cci;
    int  m_h_bb;           // Bollinger Bands
    int  m_h_envelopes;
    int  m_h_ma_fast;
    int  m_h_ma_slow;
    int  m_h_atr;
    int  m_h_adx;
    int  m_h_hilo;         // Usaremos MA para simular

    // Configurações dos indicadores
    // --- RSI ---
    int             m_rsi_period;
    ENUM_TIMEFRAMES m_rsi_tf;
    double          m_rsi_upper;       // Nível de sobrecompra (ex: 70)
    double          m_rsi_lower;       // Nível de sobrevenda (ex: 30)

    // --- CCI ---
    int             m_cci_period;
    ENUM_TIMEFRAMES m_cci_tf;
    double          m_cci_upper;       // Nível superior (ex: 100)
    double          m_cci_lower;       // Nível inferior (ex: -100)

    // --- Bollinger Bands ---
    int             m_bb_period;
    ENUM_TIMEFRAMES m_bb_tf;
    double          m_bb_deviation;

    // --- Envelopes ---
    int             m_env_period;
    ENUM_TIMEFRAMES m_env_tf;
    double          m_env_deviation;

    // --- Médias Móveis ---
    int             m_ma_fast_period;
    int             m_ma_slow_period;
    ENUM_TIMEFRAMES m_ma_tf;
    ENUM_MA_METHOD  m_ma_method;

    // --- ATR (para filtro) ---
    int             m_atr_period;
    ENUM_TIMEFRAMES m_atr_tf;

    // --- ADX (para filtro) ---
    int             m_adx_period;
    ENUM_TIMEFRAMES m_adx_tf;
    double          m_adx_min;         // Força mínima da tendência

    // --- HILO ---
    int             m_hilo_period;
    ENUM_TIMEFRAMES m_hilo_tf;

    // --- Filtros ---
    double          m_atr_filter_min;  // ATR mínimo para operar
    double          m_atr_filter_max;  // ATR máximo para operar
    long            m_vol_filter_min;  // Volume mínimo

    //+--------------------------------------------------------------+
    //| Lê valor de buffer de um indicador                           |
    //+--------------------------------------------------------------+
    double ReadBuffer(int handle, int buffer_index, int shift = 0) {
        if(handle == INVALID_HANDLE) return 0.0;
        double buf[1];
        if(CopyBuffer(handle, buffer_index, shift, 1, buf) <= 0) return 0.0;
        return buf[0];
    }

    //+--------------------------------------------------------------+
    //| Sinal do RSI — sobrecompra/sobrevenda                        |
    //| Compra quando RSI < lower, Venda quando RSI > upper          |
    //+--------------------------------------------------------------+
    int GetRSISignal() {
        double rsi = ReadBuffer(m_h_rsi, 0);
        if(rsi <= 0.0) return 0;
        if(rsi < m_rsi_lower) return +1;   // Sobrevenda → compra
        if(rsi > m_rsi_upper) return -1;   // Sobrecompra → venda
        return 0;
    }

    //+--------------------------------------------------------------+
    //| Sinal do CCI — cruzamento de níveis                          |
    //| Compra quando CCI < lower, Venda quando CCI > upper          |
    //+--------------------------------------------------------------+
    int GetCCISignal() {
        double cci = ReadBuffer(m_h_cci, 0);
        if(cci < m_cci_lower) return +1;
        if(cci > m_cci_upper) return -1;
        return 0;
    }

    //+--------------------------------------------------------------+
    //| Sinal das Bollinger Bands — toque nas bandas                 |
    //| Compra quando preço toca banda inferior                      |
    //| Venda quando preço toca banda superior                       |
    //+--------------------------------------------------------------+
    int GetBollingerSignal() {
        double upper = ReadBuffer(m_h_bb, 1);  // Banda superior
        double lower = ReadBuffer(m_h_bb, 2);  // Banda inferior
        double bid   = SymbolInfoDouble(m_symbol, SYMBOL_BID);

        if(upper <= 0.0 || lower <= 0.0) return 0;
        if(bid <= lower) return +1;   // Preço na banda inferior → compra
        if(bid >= upper) return -1;   // Preço na banda superior → venda
        return 0;
    }

    //+--------------------------------------------------------------+
    //| Sinal dos Envelopes — preço fora do envelope                 |
    //+--------------------------------------------------------------+
    int GetEnvelopesSignal() {
        double upper = ReadBuffer(m_h_envelopes, 0);  // Envelope superior
        double lower = ReadBuffer(m_h_envelopes, 1);  // Envelope inferior
        double bid   = SymbolInfoDouble(m_symbol, SYMBOL_BID);

        if(upper <= 0.0 || lower <= 0.0) return 0;
        if(bid <= lower) return +1;
        if(bid >= upper) return -1;
        return 0;
    }

    //+--------------------------------------------------------------+
    //| Sinal das Médias Móveis — cruzamento rápida/lenta            |
    //| Compra quando rápida > lenta, Venda quando rápida < lenta    |
    //+--------------------------------------------------------------+
    int GetMASignal() {
        double ma_fast = ReadBuffer(m_h_ma_fast, 0);
        double ma_slow = ReadBuffer(m_h_ma_slow, 0);

        if(ma_fast <= 0.0 || ma_slow <= 0.0) return 0;

        // Verifica cruzamento com margem para evitar ruído
        double diff = ma_fast - ma_slow;
        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        double min_diff = point * 5.0; // Mínimo de 5 pontos de diferença

        if(diff > min_diff)  return +1;  // Rápida acima → compra
        if(diff < -min_diff) return -1;  // Rápida abaixo → venda
        return 0;
    }

    //+--------------------------------------------------------------+
    //| Sinal do HILO — High-Low Activator                           |
    //| Simula com MA sobre High e Low                               |
    //+--------------------------------------------------------------+
    int GetHILOSignal() {
        // HILO usa MA sobre os máximos e mínimos dos candles
        double hilo_val = ReadBuffer(m_h_hilo, 0);
        double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);

        if(hilo_val <= 0.0) return 0;
        if(bid > hilo_val) return +1;
        if(bid < hilo_val) return -1;
        return 0;
    }

    //+--------------------------------------------------------------+
    //| Sinal do ADX — força da tendência                            |
    //| Compra quando DI+ > DI-, Venda quando DI- > DI+             |
    //| Só sinaliza se ADX > mínimo (tendência forte)                |
    //+--------------------------------------------------------------+
    int GetADXSignal() {
        double adx   = ReadBuffer(m_h_adx, 0);  // ADX principal
        double di_up = ReadBuffer(m_h_adx, 1);   // +DI
        double di_dn = ReadBuffer(m_h_adx, 2);   // -DI

        if(adx < m_adx_min) return 0;  // Tendência fraca
        if(di_up > di_dn) return +1;
        if(di_dn > di_up) return -1;
        return 0;
    }

public:
    //+--------------------------------------------------------------+
    //| Construtor — inicializa todos os handles como inválidos      |
    //+--------------------------------------------------------------+
    CIndicatorHub(string symbol, CLogger *logger) {
        m_symbol = symbol;
        m_logger = logger;

        // Inicializa todos os handles
        m_h_rsi = m_h_cci = m_h_bb = m_h_envelopes = INVALID_HANDLE;
        m_h_ma_fast = m_h_ma_slow = m_h_atr = m_h_adx = INVALID_HANDLE;
        m_h_hilo = INVALID_HANDLE;

        // Defaults
        m_rsi_period = 14;    m_rsi_tf = PERIOD_M5;
        m_rsi_upper = 70.0;   m_rsi_lower = 30.0;
        m_cci_period = 14;    m_cci_tf = PERIOD_M5;
        m_cci_upper = 100.0;  m_cci_lower = -100.0;
        m_bb_period = 20;     m_bb_tf = PERIOD_M5;     m_bb_deviation = 2.0;
        m_env_period = 14;    m_env_tf = PERIOD_M5;     m_env_deviation = 0.1;
        m_ma_fast_period = 9;  m_ma_slow_period = 21;
        m_ma_tf = PERIOD_M5;   m_ma_method = MODE_SMA;
        m_atr_period = 14;    m_atr_tf = PERIOD_M5;
        m_adx_period = 14;    m_adx_tf = PERIOD_M5;    m_adx_min = 22.0;
        m_hilo_period = 3;    m_hilo_tf = PERIOD_M5;
        m_atr_filter_min = 0.0;  m_atr_filter_max = 999999.0;
        m_vol_filter_min = 0;
    }

    //+--------------------------------------------------------------+
    //| Destrutor — libera todos os handles de indicadores           |
    //+--------------------------------------------------------------+
    ~CIndicatorHub() {
        if(m_h_rsi       != INVALID_HANDLE) IndicatorRelease(m_h_rsi);
        if(m_h_cci       != INVALID_HANDLE) IndicatorRelease(m_h_cci);
        if(m_h_bb        != INVALID_HANDLE) IndicatorRelease(m_h_bb);
        if(m_h_envelopes != INVALID_HANDLE) IndicatorRelease(m_h_envelopes);
        if(m_h_ma_fast   != INVALID_HANDLE) IndicatorRelease(m_h_ma_fast);
        if(m_h_ma_slow   != INVALID_HANDLE) IndicatorRelease(m_h_ma_slow);
        if(m_h_atr       != INVALID_HANDLE) IndicatorRelease(m_h_atr);
        if(m_h_adx       != INVALID_HANDLE) IndicatorRelease(m_h_adx);
        if(m_h_hilo      != INVALID_HANDLE) IndicatorRelease(m_h_hilo);
    }

    //+--------------------------------------------------------------+
    //| Configura parâmetros do RSI                                   |
    //+--------------------------------------------------------------+
    void SetupRSI(int period, ENUM_TIMEFRAMES tf, double upper, double lower) {
        m_rsi_period = period;  m_rsi_tf = tf;
        m_rsi_upper = upper;    m_rsi_lower = lower;
    }

    //+--------------------------------------------------------------+
    //| Configura parâmetros do CCI                                   |
    //+--------------------------------------------------------------+
    void SetupCCI(int period, ENUM_TIMEFRAMES tf, double upper, double lower) {
        m_cci_period = period;  m_cci_tf = tf;
        m_cci_upper = upper;    m_cci_lower = lower;
    }

    //+--------------------------------------------------------------+
    //| Configura parâmetros das Bollinger Bands                      |
    //+--------------------------------------------------------------+
    void SetupBollinger(int period, ENUM_TIMEFRAMES tf, double deviation) {
        m_bb_period = period;  m_bb_tf = tf;  m_bb_deviation = deviation;
    }

    //+--------------------------------------------------------------+
    //| Configura parâmetros dos Envelopes                            |
    //+--------------------------------------------------------------+
    void SetupEnvelopes(int period, ENUM_TIMEFRAMES tf, double deviation) {
        m_env_period = period;  m_env_tf = tf;  m_env_deviation = deviation;
    }

    //+--------------------------------------------------------------+
    //| Configura parâmetros das Médias Móveis                        |
    //+--------------------------------------------------------------+
    void SetupMA(int fast_period, int slow_period, ENUM_TIMEFRAMES tf, ENUM_MA_METHOD method) {
        m_ma_fast_period = fast_period;  m_ma_slow_period = slow_period;
        m_ma_tf = tf;  m_ma_method = method;
    }

    //+--------------------------------------------------------------+
    //| Configura parâmetros do ATR (para filtro e grid dinâmica)     |
    //+--------------------------------------------------------------+
    void SetupATR(int period, ENUM_TIMEFRAMES tf, double filter_min, double filter_max) {
        m_atr_period = period;  m_atr_tf = tf;
        m_atr_filter_min = filter_min;  m_atr_filter_max = filter_max;
    }

    //+--------------------------------------------------------------+
    //| Configura parâmetros do ADX                                   |
    //+--------------------------------------------------------------+
    void SetupADX(int period, ENUM_TIMEFRAMES tf, double min_level) {
        m_adx_period = period;  m_adx_tf = tf;  m_adx_min = min_level;
    }

    //+--------------------------------------------------------------+
    //| Configura parâmetros do HILO                                  |
    //+--------------------------------------------------------------+
    void SetupHILO(int period, ENUM_TIMEFRAMES tf) {
        m_hilo_period = period;  m_hilo_tf = tf;
    }

    //+--------------------------------------------------------------+
    //| Configura filtro de volume                                    |
    //+--------------------------------------------------------------+
    void SetupVolumeFilter(long min_volume) {
        m_vol_filter_min = min_volume;
    }

    //+--------------------------------------------------------------+
    //| Inicializa handles de indicadores que serão usados            |
    //| Chame após todas as configurações SetupXxx()                 |
    //| active_signals: array com indicadores ativos                  |
    //+--------------------------------------------------------------+
    bool Initialize(ENUM_INDICATOR_SIGNAL &active_signals[], int count) {
        bool ok = true;

        for(int i = 0; i < count; i++) {
            switch(active_signals[i]) {
                case OB3_IND_RSI:
                    m_h_rsi = iRSI(m_symbol, m_rsi_tf, m_rsi_period, PRICE_CLOSE);
                    if(m_h_rsi == INVALID_HANDLE) { ok = false; m_logger.Error("IndHub", "Falha RSI"); }
                    else m_logger.Info("IndHub", StringFormat("RSI: P=%d TF=%s Sup=%.0f Inf=%.0f", m_rsi_period, EnumToString(m_rsi_tf), m_rsi_upper, m_rsi_lower));
                    break;

                case OB3_IND_CCI:
                    m_h_cci = iCCI(m_symbol, m_cci_tf, m_cci_period, PRICE_CLOSE);
                    if(m_h_cci == INVALID_HANDLE) { ok = false; m_logger.Error("IndHub", "Falha CCI"); }
                    else m_logger.Info("IndHub", StringFormat("CCI: P=%d Sup=%.0f Inf=%.0f", m_cci_period, m_cci_upper, m_cci_lower));
                    break;

                case OB3_IND_BOLLINGER:
                    m_h_bb = iBands(m_symbol, m_bb_tf, m_bb_period, 0, m_bb_deviation, PRICE_CLOSE);
                    if(m_h_bb == INVALID_HANDLE) { ok = false; m_logger.Error("IndHub", "Falha BB"); }
                    else m_logger.Info("IndHub", StringFormat("Bollinger: P=%d Dev=%.1f", m_bb_period, m_bb_deviation));
                    break;

                case OB3_IND_ENVELOPES:
                    m_h_envelopes = iEnvelopes(m_symbol, m_env_tf, m_env_period, 0, MODE_SMA, PRICE_CLOSE, m_env_deviation);
                    if(m_h_envelopes == INVALID_HANDLE) { ok = false; m_logger.Error("IndHub", "Falha Envelopes"); }
                    else m_logger.Info("IndHub", StringFormat("Envelopes: P=%d Dev=%.2f", m_env_period, m_env_deviation));
                    break;

                case OB3_IND_MOVING_AVERAGES:
                    m_h_ma_fast = iMA(m_symbol, m_ma_tf, m_ma_fast_period, 0, m_ma_method, PRICE_CLOSE);
                    m_h_ma_slow = iMA(m_symbol, m_ma_tf, m_ma_slow_period, 0, m_ma_method, PRICE_CLOSE);
                    if(m_h_ma_fast == INVALID_HANDLE || m_h_ma_slow == INVALID_HANDLE) { ok = false; m_logger.Error("IndHub", "Falha MAs"); }
                    else m_logger.Info("IndHub", StringFormat("MAs: Rápida=%d Lenta=%d", m_ma_fast_period, m_ma_slow_period));
                    break;

                case OB3_IND_HILO:
                    // HILO simulado com MA sobre preço mediano (high+low)/2
                    m_h_hilo = iMA(m_symbol, m_hilo_tf, m_hilo_period, 0, MODE_SMA, PRICE_MEDIAN);
                    if(m_h_hilo == INVALID_HANDLE) { ok = false; m_logger.Error("IndHub", "Falha HILO"); }
                    else m_logger.Info("IndHub", StringFormat("HILO: P=%d", m_hilo_period));
                    break;

                case OB3_IND_ATR_SIGNAL:
                    if(m_h_atr == INVALID_HANDLE) {
                        m_h_atr = iATR(m_symbol, m_atr_tf, m_atr_period);
                        if(m_h_atr == INVALID_HANDLE) { ok = false; m_logger.Error("IndHub", "Falha ATR"); }
                    }
                    break;

                case OB3_IND_ADX_SIGNAL:
                    m_h_adx = iADX(m_symbol, m_adx_tf, m_adx_period);
                    if(m_h_adx == INVALID_HANDLE) { ok = false; m_logger.Error("IndHub", "Falha ADX"); }
                    else m_logger.Info("IndHub", StringFormat("ADX: P=%d Min=%.0f", m_adx_period, m_adx_min));
                    break;

                default:
                    break;
            }
        }

        // Inicializa ATR para filtros (se ainda não criado)
        if(m_h_atr == INVALID_HANDLE) {
            m_h_atr = iATR(m_symbol, m_atr_tf, m_atr_period);
            if(m_h_atr == INVALID_HANDLE)
                m_logger.Warning("IndHub", "ATR para filtros não disponível");
            else
                m_logger.Info("IndHub", StringFormat("ATR (filtro): P=%d", m_atr_period));
        }

        return ok;
    }

    //+--------------------------------------------------------------+
    //| Obtém sinal de um indicador específico                       |
    //| Retorna: +1 (compra), -1 (venda), 0 (neutro)                |
    //+--------------------------------------------------------------+
    int GetSignal(ENUM_INDICATOR_SIGNAL indicator, ENUM_INDICATOR_STRATEGY strategy) {
        if(strategy == STRAT_DISABLED) return 0;

        int raw_signal = 0;

        switch(indicator) {
            case OB3_IND_RSI:             raw_signal = GetRSISignal();        break;
            case OB3_IND_CCI:             raw_signal = GetCCISignal();        break;
            case OB3_IND_BOLLINGER:       raw_signal = GetBollingerSignal();  break;
            case OB3_IND_ENVELOPES:       raw_signal = GetEnvelopesSignal();  break;
            case OB3_IND_MOVING_AVERAGES: raw_signal = GetMASignal();         break;
            case OB3_IND_HILO:            raw_signal = GetHILOSignal();       break;
            case OB3_IND_ADX_SIGNAL:      raw_signal = GetADXSignal();        break;
            case OB3_IND_NONE:            return 0;
            default:                      return 0;
        }

        // Aplica estratégia
        if(strategy == STRAT_REVERSE) raw_signal *= -1;
        return raw_signal;
    }

    //+--------------------------------------------------------------+
    //| Obtém sinal composto (principal + confirmações)              |
    //| main_signal: indicador principal                              |
    //| main_strategy: estratégia do principal                       |
    //| confirms[]: array de indicadores de confirmação               |
    //| confirm_strats[]: estratégias correspondentes                 |
    //| confirm_count: quantidade de confirmações                     |
    //|                                                               |
    //| Retorna sinal apenas se TODOS concordam (ou são neutros)     |
    //+--------------------------------------------------------------+
    int GetCompositeSignal(ENUM_INDICATOR_SIGNAL main_signal,
                           ENUM_INDICATOR_STRATEGY main_strategy,
                           ENUM_INDICATOR_SIGNAL &confirms[],
                           ENUM_INDICATOR_STRATEGY &confirm_strats[],
                           int confirm_count) {
        // Sinal do indicador principal
        int primary = GetSignal(main_signal, main_strategy);
        if(primary == 0) return 0;  // Principal neutro → sem operação

        // Verifica confirmações (se ativas)
        for(int i = 0; i < confirm_count && i < MAX_CONFIRMATIONS; i++) {
            if(confirms[i] == OB3_IND_NONE || confirm_strats[i] == STRAT_DISABLED)
                continue;

            int conf_signal = GetSignal(confirms[i], confirm_strats[i]);

            // Se confirmação deu sinal contrário, bloqueia
            if(conf_signal != 0 && conf_signal != primary) {
                m_logger.Debug("IndHub",
                    StringFormat("Bloqueado por confirmação %d: principal=%d confirm=%d",
                                 i, primary, conf_signal));
                return 0;
            }
        }

        return primary;
    }

    //+--------------------------------------------------------------+
    //| Verifica filtro de ATR — volatilidade dentro da faixa?       |
    //+--------------------------------------------------------------+
    bool PassATRFilter() {
        if(m_atr_filter_min <= 0.0 && m_atr_filter_max >= 999999.0) return true;

        double atr = ReadBuffer(m_h_atr, 0);
        if(atr <= 0.0) return true;  // Sem dados → permite

        if(atr < m_atr_filter_min || atr > m_atr_filter_max) {
            m_logger.Debug("IndHub",
                StringFormat("Filtro ATR bloqueou: ATR=%.5f [min=%.5f max=%.5f]",
                             atr, m_atr_filter_min, m_atr_filter_max));
            return false;
        }
        return true;
    }

    //+--------------------------------------------------------------+
    //| Verifica filtro de ADX — tendência forte o suficiente?       |
    //+--------------------------------------------------------------+
    bool PassADXFilter() {
        if(m_h_adx == INVALID_HANDLE) return true;
        double adx = ReadBuffer(m_h_adx, 0);
        if(adx < m_adx_min) {
            m_logger.Debug("IndHub",
                StringFormat("Filtro ADX bloqueou: ADX=%.1f (min=%.1f)", adx, m_adx_min));
            return false;
        }
        return true;
    }

    //+--------------------------------------------------------------+
    //| Verifica filtro de Volume — volume suficiente?                |
    //+--------------------------------------------------------------+
    bool PassVolumeFilter() {
        if(m_vol_filter_min <= 0) return true;
        long vol = iVolume(m_symbol, PERIOD_CURRENT, 0);
        if(vol < m_vol_filter_min) {
            m_logger.Debug("IndHub",
                StringFormat("Filtro Volume bloqueou: Vol=%d (min=%d)", vol, m_vol_filter_min));
            return false;
        }
        return true;
    }

    //+--------------------------------------------------------------+
    //| Verifica TODOS os filtros ativos de uma só vez                |
    //+--------------------------------------------------------------+
    bool PassAllFilters() {
        if(!PassATRFilter())    return false;
        if(!PassADXFilter())    return false;
        if(!PassVolumeFilter()) return false;
        return true;
    }

    //+--------------------------------------------------------------+
    //| Obtém valor atual do ATR (para uso pelo GridEngine e outros) |
    //+--------------------------------------------------------------+
    double GetATRValue() {
        return ReadBuffer(m_h_atr, 0);
    }

    //+--------------------------------------------------------------+
    //| Obtém valor atual do ADX                                      |
    //+--------------------------------------------------------------+
    double GetADXValue() {
        return ReadBuffer(m_h_adx, 0);
    }

    //+--------------------------------------------------------------+
    //| Status resumido dos indicadores para log/dashboard            |
    //+--------------------------------------------------------------+
    string GetStatusString() {
        string s = "Indicadores: ";
        if(m_h_rsi       != INVALID_HANDLE) s += StringFormat("RSI=%.1f ", ReadBuffer(m_h_rsi, 0));
        if(m_h_cci       != INVALID_HANDLE) s += StringFormat("CCI=%.1f ", ReadBuffer(m_h_cci, 0));
        if(m_h_adx       != INVALID_HANDLE) s += StringFormat("ADX=%.1f ", ReadBuffer(m_h_adx, 0));
        if(m_h_atr       != INVALID_HANDLE) s += StringFormat("ATR=%.5f ", ReadBuffer(m_h_atr, 0));
        if(m_h_ma_fast   != INVALID_HANDLE) s += StringFormat("MAf=%.2f MAs=%.2f ", ReadBuffer(m_h_ma_fast, 0), ReadBuffer(m_h_ma_slow, 0));
        return s;
    }
};

//+------------------------------------------------------------------+
