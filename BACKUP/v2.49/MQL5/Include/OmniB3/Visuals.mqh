//+------------------------------------------------------------------+
//|                                                      Visuals.mqh |
//|                     Omni-B3 EA v2.49 — Módulo Visual Avançado     |
//|        Desenho de Alvos Virtuais e Histórico de Trades no Gráfico|
//+------------------------------------------------------------------+
//| Copyright 2026, Projeto Omni-B3                                 |
//| https://github.com/helveciopereira/Stocks                        |
//+------------------------------------------------------------------+
#property copyright "Projeto Omni-B3"
#property link      "https://github.com/helveciopereira/Stocks"
#property version     "2.49"
#property strict

#include <OmniB3/Defines.mqh>
#include <OmniB3/Logger.mqh>

//+------------------------------------------------------------------+
//| CLASSE CVisuals                                                  |
//| Gerencia setas de trade, linhas de alvos e textos flutuantes     |
//+------------------------------------------------------------------+
class CVisuals {
private:
    long     m_chart_id;        // ID do Gráfico
    int      m_sub_window;      // Sub-janela (0 = principal)
    string   m_prefix;          // Prefixo único para evitar conflito com outros EAs
    int      m_magic_number;    // Número mágico do EA para filtrar trades
    string   m_symbol;          // Ativo operado
    CLogger *m_logger;          // Logger do sistema
    int      m_last_deals_count;// Quantidade de deals na última checagem

    // Cores néon premium para manter consistência estética
    color    m_color_tp;        // Verde Néon
    color    m_color_sl;        // Coral Néon
    color    m_color_avg;       // Ciano Néon (Preço Médio Compra)
    color    m_color_avg_sell;  // Amarelo Néon (Preço Médio Venda)
    color    m_color_text;      // Branco Néon / Suave

    // Método auxiliar para criar linhas horizontais
    bool     CreateHLine(string name, double price, color clr, ENUM_LINE_STYLE style, int width, string desc);
    // Método auxiliar para deletar objetos com base no nome
    void     DeleteObject(string name);

public:
             CVisuals();
            ~CVisuals();

    // Inicializa o módulo visual
    bool     Init(CLogger *logger, int magic_number, string symbol);
    // Deinicialização geral, limpa objetos visuais criados
    void     Deinit();

    // Limpa todas as linhas de alvos e desenhos do gráfico
    void     Clear();

    // Atualiza as linhas horizontais virtuais (Preço Médio, Take Profit, Stop Loss)
    void     DrawTargetLines(bool is_grid_active, double avg_price, double tp_price, double sl_price, int pos_type);

    // Varre o histórico completo da conta e desenha as setas, conector de tendência e resultados financeiros
    void     DrawTradeHistory();

    // Checa se houve novas transações de histórico e reconstrói se necessário
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
    m_color_tp         = C'0,230,180';    // Turquesa/Verde Néon brilhante
    m_color_sl         = C'255,80,100';   // Coral Néon brilhante
    m_color_avg        = C'0,162,255';    // Azul Néon brilhante (Compra)
    m_color_avg_sell   = C'255,193,7';    // Amarelo Néon brilhante (Venda)
    m_color_text       = C'240,242,245';  // Branco premium
}

//+------------------------------------------------------------------+
//| Destrutor                                                        |
//+------------------------------------------------------------------+
CVisuals::~CVisuals() {
    Deinit();
}

//+------------------------------------------------------------------+
//| Inicialização                                                    |
//+------------------------------------------------------------------+
bool CVisuals::Init(CLogger *logger, int magic_number, string symbol) {
    m_logger       = logger;
    m_magic_number = magic_number;
    m_symbol       = symbol;
    m_chart_id     = ChartID();
    m_sub_window   = 0;

    // Ativa exibição de descrições de objetos no gráfico para podermos ver as legendas das linhas
    ChartSetInteger(m_chart_id, CHART_SHOW_OBJECT_DESCR, true);

    // Desativa a exibição automática do histórico de transações nativo do MetaTrader 5
    // para evitar poluição visual e conflito com o nosso histórico de trades premium.
    ChartSetInteger(m_chart_id, CHART_SHOW_TRADE_HISTORY, false);

    // Desenha o histórico inicial acumulado de todos os dias operados
    DrawTradeHistory();

    if(m_logger != NULL) m_logger.Info("Visuals", "Módulo de desenho gráfico premium inicializado para v2.49.");
    return true;
}

//+------------------------------------------------------------------+
//| Deinicialização                                                  |
//+------------------------------------------------------------------+
void CVisuals::Deinit() {
    Clear();
}

//+------------------------------------------------------------------+
//| Limpa todas as linhas de alvos e desenhos do gráfico             |
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
    // Se a grade ou posição não estiver ativa, deletamos todas as linhas de alvo
    if(!is_grid_active || avg_price <= 0.0) {
        DeleteObject("Line_Avg");
        DeleteObject("Line_TP");
        DeleteObject("Line_SL");
        ChartRedraw(m_chart_id);
        return;
    }

    // 1. Linha do Preço Médio
    color avg_clr = (pos_type == POSITION_TYPE_BUY) ? m_color_avg : m_color_avg_sell;
    string avg_desc = "OmniB3 PREÇO MÉDIO VIRTUAL (" + ((pos_type == POSITION_TYPE_BUY) ? "COMPRA" : "VENDA") + "): R$ " + DoubleToString(avg_price, _Digits);
    CreateHLine("Line_Avg", avg_price, avg_clr, STYLE_DASH, 2, avg_desc);

    // 2. Linha do Take Profit Virtual
    if(tp_price > 0.0) {
        // Estima o ganho com base nos pontos do TP até a média (valores meramente indicativos no rótulo)
        double diff_points = MathAbs(tp_price - avg_price);
        string tp_desc = "OmniB3 ALVO TAKE PROFIT VIRTUAL (+R$): R$ " + DoubleToString(tp_price, _Digits);
        CreateHLine("Line_TP", tp_price, m_color_tp, STYLE_SOLID, 2, tp_desc);
    } else {
        DeleteObject("Line_TP");
    }

    // 3. Linha do Stop Loss Virtual
    if(sl_price > 0.0) {
        string sl_desc = "OmniB3 PROTEÇãO STOP LOSS VIRTUAL (TRILING): R$ " + DoubleToString(sl_price, _Digits);
        CreateHLine("Line_SL", sl_price, m_color_sl, STYLE_SOLID, 2, sl_desc);
    } else {
        DeleteObject("Line_SL");
    }

    ChartRedraw(m_chart_id);
}

//+------------------------------------------------------------------+
//| Desenha as setas, conector de tendência e resultados no gráfico  |
//+------------------------------------------------------------------+
void CVisuals::DrawTradeHistory() {
    // Solicita o histórico completo da conta desde o primeiro registro (tempo = 0)
    if(!HistorySelect(0, TimeCurrent())) {
        if(m_logger != NULL) m_logger.Error("Visuals", "Erro ao carregar histórico de transações.");
        return;
    }

    int total_deals = HistoryDealsTotal();
    m_last_deals_count = total_deals;

    // Estruturas auxiliares para agrupar as entradas de cada Posição
    // Chave: ID da Posição, Valor: Ã?ndice do Deal ou Preço/Tempo correspondente
    // Como MQL5 nativo não tem mapas associativos dinâmicos rápidos, usaremos arrays paralelos simples
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

        // Filtro de consistência rígido: mesmo símbolo e mesmo magic number
        if(deal_symbol != m_symbol || deal_magic != m_magic_number) continue;

        if(entry_type == DEAL_ENTRY_IN) {
            // Registra a entrada desta posição
            bool found = false;
            for(int j=0; j<pos_count; j++) {
                if(pos_ids[j] == pos_id) {
                    // Posição já registrada (pode ser aumento de posição na grade). Mantemos a primeira entrada.
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

    // Segundo passo: Localiza as saídas (DEAL_ENTRY_OUT) e desenha os caminhos e resultados correspondentes
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

            // Busca a entrada correspondente a esta posição ID
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

                // Identificadores únicos dos objetos gráficos para esta transação específica
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

                // 2. Seta de Saída
                if(ObjectFind(m_chart_id, exit_arrow_name) < 0) {
                    ObjectCreate(m_chart_id, exit_arrow_name, OBJ_ARROW, m_sub_window, exit_time, exit_price);
                    ObjectSetInteger(m_chart_id, exit_arrow_name, OBJPROP_ARROWCODE, 252); // Seta em forma de X de saída / fechamento
                    ObjectSetInteger(m_chart_id, exit_arrow_name, OBJPROP_COLOR, (net_profit >= 0.0) ? m_color_tp : m_color_sl);
                    ObjectSetInteger(m_chart_id, exit_arrow_name, OBJPROP_WIDTH, 2);
                    ObjectSetInteger(m_chart_id, exit_arrow_name, OBJPROP_BACK, true);
                    ObjectSetInteger(m_chart_id, exit_arrow_name, OBJPROP_SELECTABLE, false);
                    ObjectSetInteger(m_chart_id, exit_arrow_name, OBJPROP_HIDDEN, true);
                }

                // 3. Linha Conectora de Tendência (Entrada -> Saída)
                if(ObjectFind(m_chart_id, trend_line_name) < 0) {
                    ObjectCreate(m_chart_id, trend_line_name, OBJ_TREND, m_sub_window, ent_time, ent_price, exit_time, exit_price);
                    ObjectSetInteger(m_chart_id, trend_line_name, OBJPROP_COLOR, (net_profit >= 0.0) ? m_color_tp : m_color_sl);
                    ObjectSetInteger(m_chart_id, trend_line_name, OBJPROP_STYLE, STYLE_DOT); // Linha pontilhada estilizada
                    ObjectSetInteger(m_chart_id, trend_line_name, OBJPROP_WIDTH, 1);
                    ObjectSetInteger(m_chart_id, trend_line_name, OBJPROP_RAY_RIGHT, false); // Não estender a linha para a direita
                    ObjectSetInteger(m_chart_id, trend_line_name, OBJPROP_BACK, true);
                    ObjectSetInteger(m_chart_id, trend_line_name, OBJPROP_SELECTABLE, false);
                    ObjectSetInteger(m_chart_id, trend_line_name, OBJPROP_HIDDEN, true);
                }

                // 4. Texto Flutuante com o Valor Monetário Obtido (P&L Formatado Néon em Negrito)
                if(ObjectFind(m_chart_id, text_lbl_name) < 0) {
                    // Calcula um offset vertical leve para o texto não sobrepor a seta (ex: 25 pontos de WIN)
                    double offset = 0.0;
                    double point_val = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
                    if(point_val > 0.0) {
                        // Offset de cerca de 25 pontos do ativo
                        offset = (ent_type == DEAL_TYPE_BUY) ? 25.0 * point_val : -25.0 * point_val;
                    }
                    
                    ObjectCreate(m_chart_id, text_lbl_name, OBJ_TEXT, m_sub_window, exit_time, exit_price + offset);
                    
                    // Formatação premium do resultado da operação conforme especificação:
                    // Lucro: +R$ X.XX em Azul Néon (C'0,229,255') e em negrito.
                    // Prejuízo: -R$ X.XX em Vermelho (C'255,0,0') e em negrito.
                    string text_out = "";
                    color text_color;
                    if(net_profit >= 0.0) {
                        text_out = "+R$ " + DoubleToString(net_profit, 2);
                        text_color = C'0,229,255'; // Azul Néon vibrante
                    } else {
                        text_out = "-R$ " + DoubleToString(MathAbs(net_profit), 2);
                        text_color = C'255,0,0'; // Vermelho vibrante
                    }
                    
                    ObjectSetString(m_chart_id, text_lbl_name, OBJPROP_TEXT, text_out);
                    ObjectSetString(m_chart_id, text_lbl_name, OBJPROP_FONT, "Trebuchet MS Bold"); // Fonte em negrito premium
                    ObjectSetInteger(m_chart_id, text_lbl_name, OBJPROP_FONTSIZE, 9); // Fonte um pouco maior para clareza
                    ObjectSetInteger(m_chart_id, text_lbl_name, OBJPROP_COLOR, text_color);
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
//| Loop Otimizado de Tick para monitorar novas transações           |
//+------------------------------------------------------------------+
void CVisuals::OnTickVisual() {
    // Chamamos a varredura do histórico apenas se o número de deals na conta mudou
    // Isso economiza 99.9% de processamento comparado com rodar a cada varredura pura
    if(HistorySelect(0, TimeCurrent())) {
        int current_deals = HistoryDealsTotal();
        if(current_deals != m_last_deals_count) {
            DrawTradeHistory();
        }
    }
}

//+------------------------------------------------------------------+
//| Auxiliar: Criação ou atualização de HLINE                        |
//+------------------------------------------------------------------+
bool CVisuals::CreateHLine(string name, double price, color clr, ENUM_LINE_STYLE style, int width, string desc) {
    string obj_name = m_prefix + name;

    // Se já existir, apenas move o preço e atualiza a descrição
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
