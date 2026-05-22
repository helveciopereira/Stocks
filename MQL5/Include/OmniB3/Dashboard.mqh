//+------------------------------------------------------------------+
//|                                                    Dashboard.mqh |
//|                       Omni-B3 EA v2.35 â€” Painel GrÃ¡fico Visual    |
//|        ExibiÃ§Ã£o de EstatÃ­sticas em Tempo Real e BotÃµes de AÃ§Ã£o   |
//|  Criado com design premium nÃ©on, suporte a temas e micro-painÃ©is|
//+------------------------------------------------------------------+
#property copyright "Projeto Omni-B3"
#property link      "https://github.com/helveciopereira/Stocks"
#property version     "2.35"
#property strict

#include <OmniB3/Defines.mqh>
#include <OmniB3/Logger.mqh>

//+------------------------------------------------------------------+
//| CLASSE CDashboard                                                |
//| Gerencia toda a interface grÃ¡fica do robÃ´ no grÃ¡fico do MT5       |
//+------------------------------------------------------------------+
class CDashboard {
private:
    long                 m_chart_id;        // ID do GrÃ¡fico atual
    int                  m_sub_window;      // Sub-janela (0 = grÃ¡fico principal)
    string               m_prefix;          // Prefixo para objetos grÃ¡ficos Ãºnicos
    ENUM_DASHBOARD_THEME m_theme;           // Tema de cores ativo
    bool                 m_is_visible;      // Visibilidade do painel
    bool                 m_is_paused;       // Estado do botÃ£o de pausa do EA
    CLogger             *m_logger;          // Ponteiro para o Logger centralizado
    
    // Cores de acordo com o tema
    color                m_color_bg;        // Cor de fundo principal
    color                m_color_border;    // Cor das bordas
    color                m_color_text;      // Cor do texto padrÃ£o
    color                m_color_positive;  // Cor de destaque positivo (Verde/Azul NÃ©on)
    color                m_color_negative;  // Cor de destaque negativo (Vermelho NÃ©on)
    color                m_color_accent;    // Cor de destaque secundÃ¡ria
    color                m_color_button;    // Cor de fundo dos botÃµes
    color                m_color_btn_text;  // Cor do texto dos botÃµes

    // DimensÃµes e posicionamento
    int                  m_x_offset;        // DistÃ¢ncia do canto esquerdo
    int                  m_y_offset;        // DistÃ¢ncia do topo
    int                  m_width;           // Largura do painel principal
    int                  m_height;          // Altura do painel principal

    // MÃ©todos auxiliares para criaÃ§Ã£o rÃ¡pida de objetos
    bool                 CreateLabel(string name, string text, int x, int y, int size, color clr, string font="Outfit");
    bool                 CreateRect(string name, int x, int y, int w, int h, color bg, color border, int border_width=1);
    bool                 CreateButton(string name, string text, int x, int y, int w, int h, color bg, color text_clr, string font="Outfit");
    
    // Configura as cores base com base no tema escolhido
    void                 ApplyTheme();

public:
                         CDashboard();
                        ~CDashboard();

    // InicializaÃ§Ã£o do Painel
    bool                 Init(CLogger *logger, ENUM_DASHBOARD_THEME theme=THEME_DARK_MODERN, int x=20, int y=40);
    // DestrÃ³i todos os objetos grÃ¡ficos do painel
    void                 Deinit();

    // Renderiza e atualiza todas as informaÃ§Ãµes do painel
    void                 Update(const SGridState &grid_state, 
                                double account_balance, 
                                double account_equity, 
                                double daily_profit, 
                                double daily_max_dd,
                                string status_msg,
                                bool ea_paused,
                                const SNewsState &next_news);

    // Processa cliques em botÃµes e eventos do grÃ¡fico
    // Retorna a aÃ§Ã£o executada caso um botÃ£o seja clicado
    string               OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam);
    
    // Exibe ou oculta o painel
    void                 SetVisibility(bool visible);
    bool                 IsVisible() const { return m_is_visible; }
};

//+------------------------------------------------------------------+
//| Construtor PadrÃ£o                                                |
//+------------------------------------------------------------------+
CDashboard::CDashboard() {
    m_chart_id   = 0;
    m_sub_window = 0;
    m_prefix     = "OmniB3_DB_";
    m_theme      = THEME_DARK_MODERN;
    m_is_visible = true;
    m_is_paused  = false;
    m_x_offset   = 20;
    m_y_offset   = 40;
    m_width      = 320;
    m_height     = 420;
    m_logger     = NULL;
}

//+------------------------------------------------------------------+
//| Destrutor                                                        |
//+------------------------------------------------------------------+
CDashboard::~CDashboard() {
    Deinit();
}

//+------------------------------------------------------------------+
//| InicializaÃ§Ã£o do Dashboard                                       |
//+------------------------------------------------------------------+
bool CDashboard::Init(CLogger *logger, ENUM_DASHBOARD_THEME theme, int x, int y) {
    m_logger     = logger;
    m_chart_id   = ChartID();
    m_sub_window = 0;
    m_theme      = theme;
    m_x_offset   = x;
    m_y_offset   = y;
    
    ApplyTheme();
    
    // Limpa objetos antigos com mesmo prefixo para evitar conflitos
    Deinit();
    
    return true;
}

//+------------------------------------------------------------------+
//| DeinicializaÃ§Ã£o e Limpeza                                        |
//+------------------------------------------------------------------+
void CDashboard::Deinit() {
    // Apaga todos os objetos criados por este dashboard
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
//| Aplica o tema de cores selecionado                               |
//+------------------------------------------------------------------+
void CDashboard::ApplyTheme() {
    switch(m_theme) {
        case THEME_LIGHT_CLEAN:
            m_color_bg       = C'245,247,250';
            m_color_border   = C'210,215,223';
            m_color_text     = C'44,53,64';
            m_color_positive = C'40,167,69';    // Verde escuro
            m_color_negative = C'220,53,69';    // Vermelho
            m_color_accent   = C'0,123,255';    // Azul clÃ¡ssico
            m_color_button   = C'225,230,238';
            m_color_btn_text = C'44,53,64';
            break;
            
        case THEME_GLASSMORPHISM:
            m_color_bg       = C'15,20,30';     // Fundo escuro levemente transparente
            m_color_border   = C'100,120,150';  // Borda mais clara brilhante
            m_color_text     = C'220,230,242';
            m_color_positive = C'80,240,120';   // Verde esmeralda nÃ©on
            m_color_negative = C'255,100,120';  // Coral nÃ©on
            m_color_accent   = C'0,229,255';    // Ciano elÃ©trico
            m_color_button   = C'40,50,70';
            m_color_btn_text = C'255,255,255';
            break;
            
        case THEME_DARK_MODERN:
        default:
            m_color_bg       = C'10,13,18';     // Cinza ultra escuro premium
            m_color_border   = C'35,42,54';     // Borda grafite
            m_color_text     = C'240,242,245';  // Branco suave
            m_color_positive = C'0,230,180';    // Turquesa NÃ©on brilhante
            m_color_negative = C'255,80,100';   // Coral NÃ©on brilhante
            m_color_accent   = C'0,162,255';    // Azul NÃ©on dinÃ¢mico
            m_color_button   = C'25,32.47';     // Fundo botÃ£o escuro
            m_color_btn_text = C'240,242,245';
            break;
    }
}

//+------------------------------------------------------------------+
//| AtualizaÃ§Ã£o e Redesenho de EstatÃ­sticas                          |
//+------------------------------------------------------------------+
void CDashboard::Update(const SGridState &grid_state, 
                        double account_balance, 
                        double account_equity, 
                        double daily_profit, 
                        double daily_max_dd,
                        string status_msg,
                        bool ea_paused,
                        const SNewsState &next_news) {
    if(!m_is_visible) return;

    m_is_paused = ea_paused;

    // 1. Criar Painel de Fundo Principal
    // Para efeito glassmorphism no MT5, usamos um retÃ¢ngulo preenchido
    CreateRect("Panel_BG", m_x_offset, m_y_offset, m_width, m_height, m_color_bg, m_color_border, 2);
    
    // TÃ­tulo Principal com efeito nÃ©on azul
    CreateLabel("Title", " OMNI - B3   EA  v2.10", m_x_offset + 15, m_y_offset + 12, 11, m_color_accent, "Outfit");
    CreateRect("Title_Separator", m_x_offset + 15, m_y_offset + 35, m_width - 30, 2, m_color_border, m_color_border);

    // 2. Primeira SeÃ§Ã£o: Conta & BalanÃ§o
    int y = m_y_offset + 48;
    CreateLabel("Lbl_Balance", "Saldo do RobÃ´:", m_x_offset + 20, y, 9, m_color_text);
    CreateLabel("Val_Balance", "R$ " + DoubleToString(account_balance, 2), m_x_offset + 160, y, 9, m_color_text);

    y += 20;
    CreateLabel("Lbl_Equity", "Capital LÃ­quido:", m_x_offset + 20, y, 9, m_color_text);
    CreateLabel("Val_Equity", "R$ " + DoubleToString(account_equity, 2), m_x_offset + 160, y, 9, m_color_text);

    // Lucro DiÃ¡rio com cor dinÃ¢mica (verde se positivo, coral se negativo)
    y += 20;
    CreateLabel("Lbl_Daily", "Lucro DiÃ¡rio (P&L):", m_x_offset + 20, y, 9, m_color_text);
    color daily_clr = (daily_profit >= 0.0) ? m_color_positive : m_color_negative;
    string sign = (daily_profit >= 0.0) ? "+" : "";
    CreateLabel("Val_Daily", sign + "R$ " + DoubleToString(daily_profit, 2), m_x_offset + 160, y, 9, daily_clr);

    // 3. Segunda SeÃ§Ã£o: Estado da Grade (Grid)
    y += 28;
    CreateRect("Sec1_Separator", m_x_offset + 15, y, m_width - 30, 1, m_color_border, m_color_border);
    
    y += 10;
    CreateLabel("Lbl_Grid_Header", "ESTADO DA GRADE", m_x_offset + 15, y, 8, m_color_accent);

    y += 20;
    CreateLabel("Lbl_Symbol", "SÃ­mbolo Ativo:", m_x_offset + 20, y, 9, m_color_text);
    CreateLabel("Val_Symbol", (grid_state.symbol == "") ? _Symbol : grid_state.symbol, m_x_offset + 160, y, 9, m_color_text);

    y += 20;
    CreateLabel("Lbl_Levels", "NÃ­veis Ativos:", m_x_offset + 20, y, 9, m_color_text);
    color levels_clr = (grid_state.total_levels > 0) ? m_color_accent : m_color_text;
    CreateLabel("Val_Levels", IntegerToString(grid_state.total_levels) + " / 20", m_x_offset + 160, y, 9, levels_clr);

    y += 20;
    CreateLabel("Lbl_Volume", "Volume Total:", m_x_offset + 20, y, 9, m_color_text);
    CreateLabel("Val_Volume", DoubleToString(grid_state.total_volume, 0) + " contratos", m_x_offset + 160, y, 9, m_color_text);

    // Lucro Flutuante com cor dinÃ¢mica
    y += 20;
    CreateLabel("Lbl_Float", "Lucro Flutuante:", m_x_offset + 20, y, 9, m_color_text);
    color float_clr = (grid_state.total_profit >= 0.0) ? m_color_positive : m_color_negative;
    sign = (grid_state.total_profit >= 0.0) ? "+" : "";
    CreateLabel("Val_Float", sign + "R$ " + DoubleToString(grid_state.total_profit, 2), m_x_offset + 160, y, 9, float_clr);

    // Drawdown Atual do RobÃ´
    y += 20;
    double current_dd = 0.0;
    if(account_balance > 0.0) {
        current_dd = ((account_balance - account_equity) / account_balance) * 100.0;
        if(current_dd < 0.0) current_dd = 0.0;
    }
    CreateLabel("Lbl_Drawdown", "Drawdown do RobÃ´:", m_x_offset + 20, y, 9, m_color_text);
    color dd_clr = (current_dd > 10.0) ? m_color_negative : m_color_text;
    CreateLabel("Val_Drawdown", DoubleToString(current_dd, 2) + "%", m_x_offset + 160, y, 9, dd_clr);

    // 4. Terceira SeÃ§Ã£o: NotÃ­cias & CalendÃ¡rio
    y += 28;
    CreateRect("Sec2_Separator", m_x_offset + 15, y, m_width - 30, 1, m_color_border, m_color_border);
    
    y += 10;
    CreateLabel("Lbl_News_Header", "FILTRO DE NOTÃCIAS (MT5)", m_x_offset + 15, y, 8, m_color_accent);

    y += 20;
    if(next_news.is_active) {
        string time_str = TimeToString(next_news.event_time, TIME_MINUTES);
        string m_stars = "";
        for(int star=0; star<next_news.importance; star++) m_stars += "â˜…";
        string news_info = next_news.currency + " - " + m_stars + " (" + time_str + ")";
        CreateLabel("Val_News_Name", StringSubstr(next_news.event_name, 0, 32) + "...", m_x_offset + 20, y, 8, m_color_negative);
        CreateLabel("Val_News_Time", "Evento em: " + IntegerToString(next_news.seconds_to / 60) + " min (" + news_info + ")", m_x_offset + 20, y + 15, 8, m_color_text);
        y += 15;
    } else {
        CreateLabel("Val_News_Status", "Sem notÃ­cias impactantes prÃ³ximas", m_x_offset + 20, y, 8, m_color_positive);
    }

    // Status / Logs rÃ¡pidos
    y += 26;
    CreateRect("Sec3_Separator", m_x_offset + 15, y, m_width - 30, 1, m_color_border, m_color_border);
    
    y += 8;
    color status_clr = (StringFind(status_msg, "Erro") >= 0 || StringFind(status_msg, "Bloqueado") >= 0) ? m_color_negative : m_color_accent;
    if(ea_paused) {
        status_msg = "RobÃ´ PAUSADO pelo UsuÃ¡rio";
        status_clr = m_color_negative;
    }
    CreateLabel("Val_Status", "STATUS: " + status_msg, m_x_offset + 15, y, 8, status_clr);

    // 5. Quarta SeÃ§Ã£o: BotÃµes Interativos
    y += 25;
    color btn_panic_color = C'220,53,69'; // Coral brilhante para PÃ¢nico
    color btn_pause_color = ea_paused ? C'40,167,69' : C'255,193,7'; // Verde se pausado (clique para rodar), amarelo se rodando

    CreateButton("Btn_Panic", "ðŸš¨ PANICO (KILL)", m_x_offset + 15, y, 138, 25, btn_panic_color, C'255,255,255', "Outfit");
    CreateButton("Btn_CloseAll", "âŒ FECHAR TUDO", m_x_offset + 167, y, 138, 25, m_color_button, m_color_btn_text, "Outfit");

    y += 30;
    string pause_lbl = ea_paused ? "â–¶ RETOMAR EA" : "â¸ PAUSAR EA";
    CreateButton("Btn_Pause", pause_lbl, m_x_offset + 15, y, 138, 25, btn_pause_color, ea_paused ? C'255,255,255' : C'0,0,0', "Outfit");
    CreateButton("Btn_Reset", "ðŸ”„ RESET DIARIO", m_x_offset + 167, y, 138, 25, m_color_button, m_color_btn_text, "Outfit");

    ChartRedraw(m_chart_id);
}

//+------------------------------------------------------------------+
//| Eventos do GrÃ¡fico (Cliques nos BotÃµes)                          |
//+------------------------------------------------------------------+
string CDashboard::OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
    if(id != CHARTEVENT_OBJECT_CLICK) return "";

    // Verifica se o objeto clicado pertence ao nosso painel
    if(StringFind(sparam, m_prefix) != 0) return "";

    string btn_name = StringSubstr(sparam, StringLen(m_prefix));
    if(m_logger != NULL) m_logger.Info("Dashboard", "BotÃ£o clicado: " + btn_name);

    // Redefine o estado do botÃ£o para "nÃ£o pressionado"
    ObjectSetInteger(m_chart_id, sparam, OBJPROP_STATE, false);
    ChartRedraw(m_chart_id);

    return btn_name;
}

//+------------------------------------------------------------------+
//| Define a Visibilidade do Painel                                  |
//+------------------------------------------------------------------+
void CDashboard::SetVisibility(bool visible) {
    m_is_visible = visible;
    if(!visible) {
        Deinit();
    }
}

//+------------------------------------------------------------------+
//| AUXILIAR: CriaÃ§Ã£o de RetÃ¢ngulo preenchido                        |
//+------------------------------------------------------------------+
bool CDashboard::CreateRect(string name, int x, int y, int w, int h, color bg, color border, int border_width) {
    string obj_name = m_prefix + name;
    
    // Deleta se jÃ¡ existe para garantir posicionamento atualizado
    if(ObjectFind(m_chart_id, obj_name) >= 0) {
        ObjectDelete(m_chart_id, obj_name);
    }

    if(!ObjectCreate(m_chart_id, obj_name, OBJ_RECTANGLE_LABEL, m_sub_window, 0, 0)) {
        return false;
    }

    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_XSIZE, w);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_YSIZE, h);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_BGCOLOR, bg);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_COLOR, border);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_WIDTH, border_width);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_BACK, false);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_SELECTED, false);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_HIDDEN, true);
    
    return true;
}

//+------------------------------------------------------------------+
//| AUXILIAR: CriaÃ§Ã£o de Texto (Label)                               |
//+------------------------------------------------------------------+
bool CDashboard::CreateLabel(string name, string text, int x, int y, int size, color clr, string font) {
    string obj_name = m_prefix + name;

    if(ObjectFind(m_chart_id, obj_name) >= 0) {
        ObjectDelete(m_chart_id, obj_name);
    }

    if(!ObjectCreate(m_chart_id, obj_name, OBJ_LABEL, m_sub_window, 0, 0)) {
        return false;
    }

    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_YDISTANCE, y);
    ObjectSetString(m_chart_id, obj_name, OBJPROP_TEXT, text);
    ObjectSetString(m_chart_id, obj_name, OBJPROP_FONT, font);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_FONTSIZE, size);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_COLOR, clr);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_BACK, false);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_SELECTED, false);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_HIDDEN, true);

    return true;
}

//+------------------------------------------------------------------+
//| AUXILIAR: CriaÃ§Ã£o de BotÃ£o Interativo                            |
//+------------------------------------------------------------------+
bool CDashboard::CreateButton(string name, string text, int x, int y, int w, int h, color bg, color text_clr, string font) {
    string obj_name = m_prefix + name;

    if(ObjectFind(m_chart_id, obj_name) >= 0) {
        ObjectDelete(m_chart_id, obj_name);
    }

    if(!ObjectCreate(m_chart_id, obj_name, OBJ_BUTTON, m_sub_window, 0, 0)) {
        return false;
    }

    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_XSIZE, w);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_YSIZE, h);
    ObjectSetString(m_chart_id, obj_name, OBJPROP_TEXT, text);
    ObjectSetString(m_chart_id, obj_name, OBJPROP_FONT, font);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_FONTSIZE, 8);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_COLOR, text_clr);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_BGCOLOR, bg);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_BORDER_COLOR, m_color_border);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_BACK, false);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_SELECTED, false);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_HIDDEN, true);

    return true;
}

//+------------------------------------------------------------------+
//| CLASSE CRecentTradesPanel                                        |
//| Gerencia um painel flutuante independente para listar trades     |
//+------------------------------------------------------------------+
class CRecentTradesPanel {
private:
    long                 m_chart_id;        // ID do GrÃ¡fico atual
    int                  m_sub_window;      // Sub-janela (0 = grÃ¡fico principal)
    string               m_prefix;          // Prefixo para objetos grÃ¡ficos Ãºnicos
    ENUM_DASHBOARD_THEME m_theme;           // Tema de cores ativo
    bool                 m_is_visible;      // Visibilidade do painel
    CLogger             *m_logger;          // Ponteiro para o Logger
    int                  m_magic_number;    // NÃºmero mÃ¡gico do robÃ´
    string               m_symbol;          // Ativo operado

    // Cores de acordo com o tema
    color                m_color_bg;        
    color                m_color_border;    
    color                m_color_text;      
    color                m_color_positive;  
    color                m_color_negative;  
    color                m_color_accent;    

    // DimensÃµes e posicionamento
    int                  m_x_offset;        
    int                  m_y_offset;        
    int                  m_width;           
    int                  m_height;          

    // MÃ©todos auxiliares para criaÃ§Ã£o rÃ¡pida de objetos
    bool                 CreateLabel(string name, string text, int x, int y, int size, color clr, string font="Outfit");
    bool                 CreateRect(string name, int x, int y, int w, int h, color bg, color border, int border_width=1);
    void                 ApplyTheme();

public:
                         CRecentTradesPanel();
                        ~CRecentTradesPanel();

    // InicializaÃ§Ã£o do Painel Flutuante
    bool                 Init(CLogger *logger, ENUM_DASHBOARD_THEME theme, int x, int y, int magic, string symbol);
    // DestrÃ³i objetos grÃ¡ficos
    void                 Deinit();
    // Renderiza e atualiza o histÃ³rico na tabela flutuante
    void                 Update();
    // Define visibilidade
    void                 SetVisibility(bool visible);
    bool                 IsVisible() const { return m_is_visible; }
};

//+------------------------------------------------------------------+
//| Construtor PadrÃ£o                                                |
//+------------------------------------------------------------------+
CRecentTradesPanel::CRecentTradesPanel() {
    m_chart_id     = 0;
    m_sub_window   = 0;
    m_prefix       = "OmniB3_RT_";
    m_theme        = THEME_DARK_MODERN;
    m_is_visible   = true;
    m_x_offset     = 360; // Posicionado ao lado do dashboard principal (largura 320 + offset 40)
    m_y_offset     = 40;
    m_width        = 330;
    m_height       = 175;
    m_logger       = NULL;
    m_magic_number = 0;
    m_symbol       = "";
}

//+------------------------------------------------------------------+
//| Destrutor                                                        |
//+------------------------------------------------------------------+
CRecentTradesPanel::~CRecentTradesPanel() {
    Deinit();
}

//+------------------------------------------------------------------+
//| InicializaÃ§Ã£o                                                    |
//+------------------------------------------------------------------+
bool CRecentTradesPanel::Init(CLogger *logger, ENUM_DASHBOARD_THEME theme, int x, int y, int magic, string symbol) {
    m_logger       = logger;
    m_chart_id     = ChartID();
    m_sub_window   = 0;
    m_theme        = theme;
    m_x_offset     = x;
    m_y_offset     = y;
    m_magic_number = magic;
    m_symbol       = symbol;

    ApplyTheme();
    Deinit(); // Limpa resÃ­duos antigos antes de iniciar

    return true;
}

//+------------------------------------------------------------------+
//| DeinicializaÃ§Ã£o e Limpeza                                        |
//+------------------------------------------------------------------+
void CRecentTradesPanel::Deinit() {
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
//| Aplica o tema de cores                                           |
//+------------------------------------------------------------------+
void CRecentTradesPanel::ApplyTheme() {
    switch(m_theme) {
        case THEME_LIGHT_CLEAN:
            m_color_bg       = C'245,247,250';
            m_color_border   = C'210,215,223';
            m_color_text     = C'44,53,64';
            m_color_positive = C'40,167,69';
            m_color_negative = C'220,53,69';
            m_color_accent   = C'0,123,255';
            break;
            
        case THEME_GLASSMORPHISM:
            m_color_bg       = C'15,20,30';
            m_color_border   = C'100,120,150';
            m_color_text     = C'220,230,242';
            m_color_positive = C'80,240,120';
            m_color_negative = C'255,100,120';
            m_color_accent   = C'0,229,255';
            break;
            
        case THEME_DARK_MODERN:
        default:
            m_color_bg       = C'10,13,18';
            m_color_border   = C'35,42,54';
            m_color_text     = C'240,242,245';
            m_color_positive = C'0,230,180';
            m_color_negative = C'255,80,100';
            m_color_accent   = C'0,162,255';
            break;
    }
}

//+------------------------------------------------------------------+
//| Atualiza as informaÃ§Ãµes do Painel Flutuante                     |
//+------------------------------------------------------------------+
void CRecentTradesPanel::Update() {
    if(!m_is_visible) return;

    // 1. Cria o RetÃ¢ngulo de Fundo Flutuante
    CreateRect("Panel_BG", m_x_offset, m_y_offset, m_width, m_height, m_color_bg, m_color_border, 2);

    // TÃ­tulo do painel flutuante
    CreateLabel("Title", " ðŸ“Š MONITOR DE OPERAÃ‡Ã•ES RECENTES", m_x_offset + 15, m_y_offset + 12, 9, m_color_accent, "Outfit");
    CreateRect("Title_Separator", m_x_offset + 15, m_y_offset + 30, m_width - 30, 2, m_color_border, m_color_border);

    // CabeÃ§alho da Tabela
    int y = m_y_offset + 38;
    CreateLabel("H_Ticket", "TICKET", m_x_offset + 20, y, 8, m_color_border);
    CreateLabel("H_Type", "TIPO", m_x_offset + 100, y, 8, m_color_border);
    CreateLabel("H_Vol", "VOL", m_x_offset + 170, y, 8, m_color_border);
    CreateLabel("H_Profit", "LUCRO (BRL)", m_x_offset + 220, y, 8, m_color_border);

    // Varre o histÃ³rico de deals para pegar os Ãºltimos 5 trades finalizados
    if(!HistorySelect(0, TimeCurrent())) return;

    int total_deals = HistoryDealsTotal();
    int rows_drawn = 0;
    y += 18;

    // Percorre do mais recente para o mais antigo buscando saÃ­das
    for(int i = total_deals - 1; i >= 0 && rows_drawn < 5; i--) {
        ulong ticket = HistoryDealGetTicket(i);
        if(ticket == 0) continue;

        string deal_symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
        long   deal_magic  = HistoryDealGetInteger(ticket, DEAL_MAGIC);
        long   entry_type  = HistoryDealGetInteger(ticket, DEAL_ENTRY);
        long   pos_id      = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);

        if(deal_symbol != m_symbol || deal_magic != m_magic_number) continue;

        // Filtra estritamente deals que sÃ£o de fechamento (saÃ­da) para listar a operaÃ§Ã£o consolidada
        if(entry_type == DEAL_ENTRY_OUT || entry_type == DEAL_ENTRY_OUT_BY) {
            double exit_price = HistoryDealGetDouble(ticket, DEAL_PRICE);
            double profit     = HistoryDealGetDouble(ticket, DEAL_PROFIT);
            double commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
            double swap       = HistoryDealGetDouble(ticket, DEAL_SWAP);
            double net_profit = profit + commission + swap;
            double volume     = HistoryDealGetDouble(ticket, DEAL_VOLUME);
            long   deal_type  = HistoryDealGetInteger(ticket, DEAL_TYPE);

            // A direÃ§Ã£o original da posiÃ§Ã£o Ã© inversa ao tipo do deal de saÃ­da (Netting)
            string dir_str = "";
            color dir_clr = m_color_text;
            if(deal_type == DEAL_TYPE_SELL) {
                dir_str = "COMPRA";
                dir_clr = m_color_positive;
            } else {
                dir_str = "VENDA";
                dir_clr = m_color_negative;
            }

            // Exibe a linha na tabela
            string row_suf = "_" + IntegerToString(rows_drawn);
            CreateLabel("R_Tkt" + row_suf, "#" + IntegerToString(pos_id), m_x_offset + 20, y, 8, m_color_text);
            CreateLabel("R_Typ" + row_suf, dir_str, m_x_offset + 100, y, 8, dir_clr);
            CreateLabel("R_Vol" + row_suf, DoubleToString(volume, 0), m_x_offset + 170, y, 8, m_color_text);

            color profit_clr = (net_profit >= 0.0) ? m_color_positive : m_color_negative;
            string sign = (net_profit >= 0.0) ? "+" : "";
            CreateLabel("R_Prf" + row_suf, sign + "R$ " + DoubleToString(net_profit, 2), m_x_offset + 220, y, 8, profit_clr);

            y += 20;
            rows_drawn++;
        }
    }

    // Limpa linhas excedentes antigas que possam ter ficado caso tenhamos menos de 5 deals no histÃ³rico
    for(int r = rows_drawn; r < 5; r++) {
        string row_suf = "_" + IntegerToString(r);
        ObjectDelete(m_chart_id, m_prefix + "R_Tkt" + row_suf);
        ObjectDelete(m_chart_id, m_prefix + "R_Typ" + row_suf);
        ObjectDelete(m_chart_id, m_prefix + "R_Vol" + row_suf);
        ObjectDelete(m_chart_id, m_prefix + "R_Prf" + row_suf);
    }

    ChartRedraw(m_chart_id);
}

//+------------------------------------------------------------------+
//| Visibilidade                                                     |
//+------------------------------------------------------------------+
void CRecentTradesPanel::SetVisibility(bool visible) {
    m_is_visible = visible;
    if(!visible) {
        Deinit();
    }
}

//+------------------------------------------------------------------+
//| AUXILIAR: CriaÃ§Ã£o de RetÃ¢ngulo preenchido                        |
//+------------------------------------------------------------------+
bool CRecentTradesPanel::CreateRect(string name, int x, int y, int w, int h, color bg, color border, int border_width) {
    string obj_name = m_prefix + name;

    if(ObjectFind(m_chart_id, obj_name) >= 0) {
        ObjectDelete(m_chart_id, obj_name);
    }

    if(!ObjectCreate(m_chart_id, obj_name, OBJ_RECTANGLE_LABEL, m_sub_window, 0, 0)) {
        return false;
    }

    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_XSIZE, w);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_YSIZE, h);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_BGCOLOR, bg);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_COLOR, border);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_WIDTH, border_width);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_BACK, false);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_SELECTED, false);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_HIDDEN, true);
    
    return true;
}

//+------------------------------------------------------------------+
//| AUXILIAR: CriaÃ§Ã£o de Texto                                       |
//+------------------------------------------------------------------+
bool CRecentTradesPanel::CreateLabel(string name, string text, int x, int y, int size, color clr, string font) {
    string obj_name = m_prefix + name;

    if(ObjectFind(m_chart_id, obj_name) >= 0) {
        ObjectDelete(m_chart_id, obj_name);
    }

    if(!ObjectCreate(m_chart_id, obj_name, OBJ_LABEL, m_sub_window, 0, 0)) {
        return false;
    }

    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_YDISTANCE, y);
    ObjectSetString(m_chart_id, obj_name, OBJPROP_TEXT, text);
    ObjectSetString(m_chart_id, obj_name, OBJPROP_FONT, font);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_FONTSIZE, size);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_COLOR, clr);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_BACK, false);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_SELECTED, false);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_HIDDEN, true);

    return true;
}

