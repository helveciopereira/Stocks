//+------------------------------------------------------------------+
//|                                                      Visuals.mqh |
//|                     Omni-B3 EA v2.46 â€” MÃ³dulo Visual AvanÃ§ado     |
//|        Desenho de Alvos Virtuais e HistÃ³rico de Trades no GrÃ¡fico|
//+------------------------------------------------------------------+
//| Copyright 2026, Projeto Omni-B3                                 |
//| https://github.com/helveciopereira/Stocks                        |
//+------------------------------------------------------------------+
#property copyright "Projeto Omni-B3"
#property link      "https://github.com/helveciopereira/Stocks"
#property version     "2.46"
#property strict

#include <OmniB3/Defines.mqh>
#include <OmniB3/Logger.mqh>

//+------------------------------------------------------------------+
//| CLASSE CVisuals                                                  |
//| Gerencia setas de trade, linhas de alvos e textos flutuantes     |
//+------------------------------------------------------------------+
class CVisuals {
private:
    long     m_chart_id;        // ID do GrÃ¡fico
    int      m_sub_window;      // Sub-janela (0 = principal)
    string   m_prefix;          // Prefixo Ãºnico para evitar conflito com outros EAs
    int      m_magic_number;    // NÃºmero mÃ¡gico do EA para filtrar trades
    string   m_symbol;          // Ativo operado
    CLogger *m_logger;          // Logger do sistema
    int      m_last_deals_count;// Quantidade de deals na Ãºltima checagem

    // Cores nÃ©on premium para manter consistÃªncia estÃ©tica
    color    m_color_tp;        // Verde NÃ©on
    color    m_color_sl;        // Coral NÃ©on
    color    m_color_avg;       // Ciano NÃ©on (PreÃ§o MÃ©dio Compra)
    color    m_color_avg_sell;  // Amarelo NÃ©on (PreÃ§o MÃ©dio Venda)
    color    m_color_text;      // Branco NÃ©on / Suave

    // MÃ©todo auxiliar para criar linhas horizontais
    bool     CreateHLine(string name, double price, color clr, ENUM_LINE_STYLE style, int width, string desc);
    // MÃ©todo auxiliar para deletar objetos com base no nome
    void     DeleteObject(string name);

public:
             CVisuals();
            ~CVisuals();

    // Inicializa o mÃ³dulo visual
    bool     Init(CLogger *logger, int magic_number, string symbol);
    // DeinicializaÃ§Ã£o geral, limpa objetos visuais criados
    void     Deinit();

    // Limpa todas as linhas de alvos e desenhos do grÃ¡fico
    void     Clear();

    // Atualiza as linhas horizontais virtuais (PreÃ§o MÃ©dio, Take Profit, Stop Loss)
    void     DrawTargetLines(bool is_grid_active, double avg_price, double tp_price, double sl_price, int pos_type);

    // Varre o histÃ³rico completo da conta e desenha as setas, conector de tendÃªncia e resultados financeiros
    void     DrawTradeHistory();

    // Checa se houve novas transaÃ§Ãµes de histÃ³rico e reconstrÃ³i se necessÃ¡rio
    void     OnTickVisual();
};

//+------------------------------------------------------------------+
//| Construtor                                                       |
//+------------------------------------------------------------------+
CVisuals::CVisuals() {
    m_chart_id         = 0;
    m_sub_window       = 0;
    m_prefix           = "OmniB3_VIS_";
    m_magic_number     = 0;
    m_symbol           = "";
    m_logger           = NULL;
    m_last_deals_count = 0;

    // Cores Tailored Neon
    m_color_tp         = C'0,230,180';    // Turquesa/Verde NÃ©on brilhante
    m_color_sl         = C'255,80,100';   // Coral NÃ©on brilhante
    m_color_avg        = C'0,162,255';    // Azul NÃ©on brilhante (Compra)
    m_color_avg_sell   = C'255,193,7';    // Amarelo NÃ©on brilhante (Venda)
    m_color_text       = C'240,242,245';  // Branco premium
}

//+------------------------------------------------------------------+
//| Destrutor                                                        |
//+------------------------------------------------------------------+
CVisuals::~CVisuals() {
    Deinit();
}

//+------------------------------------------------------------------+
//| InicializaÃ§Ã£o                                                    |
//+------------------------------------------------------------------+
bool CVisuals::Init(CLogger *logger, int magic_number, string symbol) {
    m_logger       = logger;
    m_magic_number = magic_number;
    m_symbol       = symbol;
    m_chart_id     = ChartID();
    m_sub_window   = 0;

    // Ativa exibiÃ§Ã£o de descriÃ§Ãµes de objetos no grÃ¡fico para podermos ver as legendas das linhas
    ChartSetInteger(m_chart_id, CHART_SHOW_OBJECT_DESCR, true);

    // Desenha o histÃ³rico inicial acumulado de todos os dias operados
    DrawTradeHistory();

    if(m_logger != NULL) m_logger.Info("Visuals", "MÃ³dulo de desenho grÃ¡fico premium inicializado para v2.46.");
    return true;
}

//+------------------------------------------------------------------+
//| DeinicializaÃ§Ã£o                                                  |
//+------------------------------------------------------------------+
void CVisuals::Deinit() {
    Clear();
}

//+------------------------------------------------------------------+
//| Limpa todas as linhas de alvos e desenhos do grÃ¡fico             |
//+------------------------------------------------------------------+
void CVisuals::Clear() {
    int total = ObjectsTotal(m_chart_id, m_sub_window, -1);
    for(int i = total - 1; i >= 0; i--) {
        string name = ObjectName(m_chart_id, i, m_sub_window, -1);
        if(StringFind(name, m_prefix) == 0) {
            ObjectDelete(m_chart_id, name);
        }
    }
    ChartRedraw(m_chart_id);
}

//+------------------------------------------------------------------+
//| Atualiza as linhas horizontais virtuais                          |
//+------------------------------------------------------------------+
void CVisuals::DrawTargetLines(bool is_grid_active, double avg_price, double tp_price, double sl_price, int pos_type) {
    // Se a grade ou posiÃ§Ã£o nÃ£o estiver ativa, deletamos todas as linhas de alvo
    if(!is_grid_active || avg_price <= 0.0) {
        DeleteObject("Line_Avg");
        DeleteObject("Line_TP");
        DeleteObject("Line_SL");
        ChartRedraw(m_chart_id);
        return;
    }

    // 1. Linha do PreÃ§o MÃ©dio
    color avg_clr = (pos_type == POSITION_TYPE_BUY) ? m_color_avg : m_color_avg_sell;
    string avg_desc = "OmniB3 PREÃ‡O MÃ‰DIO VIRTUAL (" + ((pos_type == POSITION_TYPE_BUY) ? "COMPRA" : "VENDA") + "): R$ " + DoubleToString(avg_price, _Digits);
    CreateHLine("Line_Avg", avg_price, avg_clr, STYLE_DASH, 2, avg_desc);

    // 2. Linha do Take Profit Virtual
    if(tp_price > 0.0) {
        // Estima o ganho com base nos pontos do TP atÃ© a mÃ©dia (valores meramente indicativos no rÃ³tulo)
        double diff_points = MathAbs(tp_price - avg_price);
        string tp_desc = "OmniB3 ALVO TAKE PROFIT VIRTUAL (+R$): R$ " + DoubleToString(tp_price, _Digits);
        CreateHLine("Line_TP", tp_price, m_color_tp, STYLE_SOLID, 2, tp_desc);
    } else {
        DeleteObject("Line_TP");
    }

    // 3. Linha do Stop Loss Virtual
    if(sl_price > 0.0) {
        string sl_desc = "OmniB3 PROTEÃ‡ÃƒO STOP LOSS VIRTUAL (TRILING): R$ " + DoubleToString(sl_price, _Digits);
        CreateHLine("Line_SL", sl_price, m_color_sl, STYLE_SOLID, 2, sl_desc);
    } else {
        DeleteObject("Line_SL");
    }

    ChartRedraw(m_chart_id);
}

//+------------------------------------------------------------------+
//| Desenha as setas, conector de tendÃªncia e resultados no grÃ¡fico  |
//+------------------------------------------------------------------+
void CVisuals::DrawTradeHistory() {
    // Solicita o histÃ³rico completo da conta desde o primeiro registro (tempo = 0)
    if(!HistorySelect(0, TimeCurrent())) {
        if(m_logger != NULL) m_logger.Error("Visuals", "Erro ao carregar histÃ³rico de transaÃ§Ãµes.");
        return;
    }

    int total_deals = HistoryDealsTotal();
    m_last_deals_count = total_deals;

    // Estruturas auxiliares para agrupar as entradas de cada PosiÃ§Ã£o
    // Chave: ID da PosiÃ§Ã£o, Valor: Ãndice do Deal ou PreÃ§o/Tempo correspondente
    // Como MQL5 nativo nÃ£o tem mapas associativos dinÃ¢micos rÃ¡pidos, usaremos arrays paralelos simples
    long   pos_ids[];
    double entry_prices[];
    datetime entry_times[];
    int    entry_types[];
    int    pos_count = 0;

    ArrayResize(pos_ids, total_deals);
    ArrayResize(entry_prices, total_deals);
    ArrayResize(entry_times, total_deals);
    ArrayResize(entry_types, total_deals);

    // Primeiro passo: Identifica e armazena todas as entradas (DEAL_ENTRY_IN) filtradas pelo nosso EA
    for(int i = 0; i < total_deals; i++) {
        ulong ticket = HistoryDealGetTicket(i);
        if(ticket == 0) continue;

        string deal_symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
        long   deal_magic  = HistoryDealGetInteger(ticket, DEAL_MAGIC);
        long   entry_type  = HistoryDealGetInteger(ticket, DEAL_ENTRY);
        long   pos_id      = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);

        // Filtro de consistÃªncia rÃ­gido: mesmo sÃ­mbolo e mesmo magic number
        if(deal_symbol != m_symbol || deal_magic != m_magic_number) continue;

        if(entry_type == DEAL_ENTRY_IN) {
            // Registra a entrada desta posiÃ§Ã£o
            bool found = false;
            for(int j=0; j<pos_count; j++) {
                if(pos_ids[j] == pos_id) {
                    // PosiÃ§Ã£o jÃ¡ registrada (pode ser aumento de posiÃ§Ã£o na grade). Mantemos a primeira entrada.
                    found = true;
                    break;
                }
            }
            if(!found) {
                pos_ids[pos_count]      = pos_id;
                entry_prices[pos_count] = HistoryDealGetDouble(ticket, DEAL_PRICE);
                entry_times[pos_count]  = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
                entry_types[pos_count]  = (int)HistoryDealGetInteger(ticket, DEAL_TYPE);
                pos_count++;
            }
        }
    }

    // Segundo passo: Localiza as saÃ­das (DEAL_ENTRY_OUT) e desenha os caminhos e resultados correspondentes
    for(int i = 0; i < total_deals; i++) {
        ulong ticket = HistoryDealGetTicket(i);
        if(ticket == 0) continue;

        string deal_symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
        long   deal_magic  = HistoryDealGetInteger(ticket, DEAL_MAGIC);
        long   entry_type  = HistoryDealGetInteger(ticket, DEAL_ENTRY);
        long   pos_id      = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);

        if(deal_symbol != m_symbol || deal_magic != m_magic_number) continue;

        if(entry_type == DEAL_ENTRY_OUT || entry_type == DEAL_ENTRY_OUT_BY) {
            double exit_price = HistoryDealGetDouble(ticket, DEAL_PRICE);
            datetime exit_time = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
            double profit     = HistoryDealGetDouble(ticket, DEAL_PROFIT);
            double commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
            double swap       = HistoryDealGetDouble(ticket, DEAL_SWAP);
            double net_profit = profit + commission + swap;

            // Busca a entrada correspondente a esta posiÃ§Ã£o ID
            int entry_idx = -1;
            for(int j = 0; j < pos_count; j++) {
                if(pos_ids[j] == pos_id) {
                    entry_idx = j;
                    break;
                }
            }

            if(entry_idx != -1) {
                double ent_price = entry_prices[entry_idx];
                datetime ent_time = entry_times[entry_idx];
                int ent_type     = entry_types[entry_idx];

                // Identificadores Ãºnicos dos objetos grÃ¡ficos para esta transaÃ§Ã£o especÃ­fica
                string suffix = "_" + IntegerToString(pos_id) + "_" + IntegerToString(exit_time);
                string entry_arrow_name = m_prefix + "EntryArrow" + suffix;
                string exit_arrow_name  = m_prefix + "ExitArrow" + suffix;
                string trend_line_name  = m_prefix + "TrendLine" + suffix;
                string text_lbl_name    = m_prefix + "ProfitText" + suffix;

                // 1. Seta de Entrada (Compra ou Venda)
                if(ObjectFind(m_chart_id, entry_arrow_name) < 0) {
                    ObjectCreate(m_chart_id, entry_arrow_name, OBJ_ARROW, m_sub_window, ent_time, ent_price);
                    ObjectSetInteger(m_chart_id, entry_arrow_name, OBJPROP_ARROWCODE, (ent_type == DEAL_TYPE_BUY) ? 233 : 234); // Seta cima / Seta baixo
                    ObjectSetInteger(m_chart_id, entry_arrow_name, OBJPROP_COLOR, (ent_type == DEAL_TYPE_BUY) ? m_color_avg : m_color_avg_sell);
                    ObjectSetInteger(m_chart_id, entry_arrow_name, OBJPROP_WIDTH, 2);
                    ObjectSetInteger(m_chart_id, entry_arrow_name, OBJPROP_BACK, true);
                    ObjectSetInteger(m_chart_id, entry_arrow_name, OBJPROP_SELECTABLE, false);
                    ObjectSetInteger(m_chart_id, entry_arrow_name, OBJPROP_HIDDEN, true);
                }

                // 2. Seta de SaÃ­da
                if(ObjectFind(m_chart_id, exit_arrow_name) < 0) {
                    ObjectCreate(m_chart_id, exit_arrow_name, OBJ_ARROW, m_sub_window, exit_time, exit_price);
                    ObjectSetInteger(m_chart_id, exit_arrow_name, OBJPROP_ARROWCODE, 252); // Seta em forma de X de saÃ­da / fechamento
                    ObjectSetInteger(m_chart_id, exit_arrow_name, OBJPROP_COLOR, (net_profit >= 0.0) ? m_color_tp : m_color_sl);
                    ObjectSetInteger(m_chart_id, exit_arrow_name, OBJPROP_WIDTH, 2);
                    ObjectSetInteger(m_chart_id, exit_arrow_name, OBJPROP_BACK, true);
                    ObjectSetInteger(m_chart_id, exit_arrow_name, OBJPROP_SELECTABLE, false);
                    ObjectSetInteger(m_chart_id, exit_arrow_name, OBJPROP_HIDDEN, true);
                }

                // 3. Linha Conectora de TendÃªncia (Entrada -> SaÃ­da)
                if(ObjectFind(m_chart_id, trend_line_name) < 0) {
                    ObjectCreate(m_chart_id, trend_line_name, OBJ_TREND, m_sub_window, ent_time, ent_price, exit_time, exit_price);
                    ObjectSetInteger(m_chart_id, trend_line_name, OBJPROP_COLOR, (net_profit >= 0.0) ? m_color_tp : m_color_sl);
                    ObjectSetInteger(m_chart_id, trend_line_name, OBJPROP_STYLE, STYLE_DOT); // Linha pontilhada estilizada
                    ObjectSetInteger(m_chart_id, trend_line_name, OBJPROP_WIDTH, 1);
                    ObjectSetInteger(m_chart_id, trend_line_name, OBJPROP_RAY_RIGHT, false); // NÃ£o estender a linha para a direita
                    ObjectSetInteger(m_chart_id, trend_line_name, OBJPROP_BACK, true);
                    ObjectSetInteger(m_chart_id, trend_line_name, OBJPROP_SELECTABLE, false);
                    ObjectSetInteger(m_chart_id, trend_line_name, OBJPROP_HIDDEN, true);
                }

                // 4. Texto Flutuante com o Valor MonetÃ¡rio Obtido
                if(ObjectFind(m_chart_id, text_lbl_name) < 0) {
                    // Calcula um offset vertical leve para o texto nÃ£o sobrepor a seta (ex: 20 pontos de WIN)
                    double offset = 0.0;
                    double point_val = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
                    if(point_val > 0.0) {
                        // Offset de cerca de 25 pontos do ativo
                        offset = (ent_type == DEAL_TYPE_BUY) ? 25.0 * point_val : -25.0 * point_val;
                    }
                    
                    ObjectCreate(m_chart_id, text_lbl_name, OBJ_TEXT, m_sub_window, exit_time, exit_price + offset);
                    
                    string sign = (net_profit >= 0.0) ? "+" : "";
                    string text_out = sign + "R$ " + DoubleToString(net_profit, 2);
                    
                    ObjectSetString(m_chart_id, text_lbl_name, OBJPROP_TEXT, text_out);
                    ObjectSetString(m_chart_id, text_lbl_name, OBJPROP_FONT, "Outfit");
                    ObjectSetInteger(m_chart_id, text_lbl_name, OBJPROP_FONTSIZE, 8);
                    ObjectSetInteger(m_chart_id, text_lbl_name, OBJPROP_COLOR, (net_profit >= 0.0) ? m_color_tp : m_color_sl);
                    ObjectSetInteger(m_chart_id, text_lbl_name, OBJPROP_ANCHOR, ANCHOR_BOTTOM);
                    ObjectSetInteger(m_chart_id, text_lbl_name, OBJPROP_BACK, false);
                    ObjectSetInteger(m_chart_id, text_lbl_name, OBJPROP_SELECTABLE, false);
                    ObjectSetInteger(m_chart_id, text_lbl_name, OBJPROP_HIDDEN, true);
                }
            }
        }
    }

    ChartRedraw(m_chart_id);
}

//+------------------------------------------------------------------+
//| Loop Otimizado de Tick para monitorar novas transaÃ§Ãµes           |
//+------------------------------------------------------------------+
void CVisuals::OnTickVisual() {
    // Chamamos a varredura do histÃ³rico apenas se o nÃºmero de deals na conta mudou
    // Isso economiza 99.9% de processamento comparado com rodar a cada varredura pura
    if(HistorySelect(0, TimeCurrent())) {
        int current_deals = HistoryDealsTotal();
        if(current_deals != m_last_deals_count) {
            DrawTradeHistory();
        }
    }
}

//+------------------------------------------------------------------+
//| Auxiliar: CriaÃ§Ã£o ou atualizaÃ§Ã£o de HLINE                        |
//+------------------------------------------------------------------+
bool CVisuals::CreateHLine(string name, double price, color clr, ENUM_LINE_STYLE style, int width, string desc) {
    string obj_name = m_prefix + name;

    // Se jÃ¡ existir, apenas move o preÃ§o e atualiza a descriÃ§Ã£o
    if(ObjectFind(m_chart_id, obj_name) >= 0) {
        ObjectSetDouble(m_chart_id, obj_name, OBJPROP_PRICE, price);
        ObjectSetString(m_chart_id, obj_name, OBJPROP_TEXT, desc);
        ObjectSetInteger(m_chart_id, obj_name, OBJPROP_COLOR, clr);
        return true;
    }

    // Cria novo objeto
    if(!ObjectCreate(m_chart_id, obj_name, OBJ_HLINE, m_sub_window, 0, price)) {
        return false;
    }

    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_COLOR, clr);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_STYLE, style);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_WIDTH, width);
    ObjectSetString(m_chart_id, obj_name, OBJPROP_TEXT, desc);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_BACK, false);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_SELECTED, false);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_HIDDEN, true);

    return true;
}

//+------------------------------------------------------------------+
//| Auxiliar: Deleta objetos de forma segura                        |
//+------------------------------------------------------------------+
void CVisuals::DeleteObject(string name) {
    string obj_name = m_prefix + name;
    if(ObjectFind(m_chart_id, obj_name) >= 0) {
        ObjectDelete(m_chart_id, obj_name);
    }
}
