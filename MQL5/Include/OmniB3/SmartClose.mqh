//+------------------------------------------------------------------+
//|                                                  SmartClose.mqh  |
//|                  Omni-B3 EA v1.0 — Fechamento Inteligente        |
//|     Usa lucro de posições vencedoras para fechar a perdedora     |
//+------------------------------------------------------------------+
#property copyright "Projeto Omni-B3"
#property link      "https://github.com/seu-usuario/Stocks"
#property version   "1.00"
#property strict

#include "Defines.mqh"
#include "Logger.mqh"
#include "PositionManager.mqh"
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Classe de Fechamento Inteligente (Smart Close / Abate Parcial)   |
//|                                                                   |
//| Filosofia: Em vez de usar Stop Loss tradicional, o EA acumula    |
//| lucro nas posições vencedoras e usa esse lucro para "comprar"    |
//| a saída da posição com maior prejuízo. Isso reduz a exposição   |
//| sem fechar o ciclo inteiro no vermelho.                          |
//|                                                                   |
//| Gatilho: Σ Lucro(positivas) >= |Prejuízo(pior)| + Margem        |
//| Onde Margem = N_pontos × Volume_pior × TickValue                |
//+------------------------------------------------------------------+
class CSmartClose {
private:
    string             m_symbol;         // Símbolo operado
    int                m_magic_number;   // Magic number do EA
    ENUM_CLOSE_TARGET  m_close_target;   // Modo: pior ou mais antiga
    double             m_margin_points;  // Pontos de margem de segurança
    CTrade             m_trade;          // Objeto de trade para fechar ordens
    CPositionManager  *m_pos_manager;    // Gerenciador de posições
    CLogger           *m_logger;         // Sistema de logging
    datetime           m_last_close_time;// Timestamp do último fechamento

    //+--------------------------------------------------------------+
    //| Calcula o custo da margem de segurança em USD                |
    //| A margem evita fechar ordens sem lucro real após spread/comissão |
    //|                                                               |
    //| Fórmula: Margem = Pontos × Volume × (TickValue / TickSize)  |
    //| Exemplo: 3pts × 0.01lot × (1.0 / 0.00001) = 3.00 USD       |
    //+--------------------------------------------------------------+
    double CalculateMarginCost(double volume) {
        double tick_value = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
        double tick_size  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);

        if(tick_size <= 0.0) {
            m_logger.Error("SmartClose", "TickSize inválido (zero)!");
            return 999999.0; // Retorna valor alto para impedir fechamento
        }

        return m_margin_points * volume * (tick_value / tick_size)
               * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    }

    //+--------------------------------------------------------------+
    //| Verifica se o cooldown entre fechamentos já expirou          |
    //| Evita múltiplos fechamentos em ticks consecutivos            |
    //+--------------------------------------------------------------+
    bool IsCooldownExpired() {
        return (TimeCurrent() - m_last_close_time) >= SMART_CLOSE_COOLDOWN;
    }

    //+--------------------------------------------------------------+
    //| Fecha uma posição específica pelo seu ticket                 |
    //| Parâmetro: ticket — identificador da posição a fechar        |
    //| Retorna: true se o fechamento foi bem-sucedido               |
    //+--------------------------------------------------------------+
    bool ClosePosition(ulong ticket) {
        if(!PositionSelectByTicket(ticket)) {
            m_logger.Warning("SmartClose",
                StringFormat("Posição #%d não encontrada para fechamento", ticket));
            return false;
        }

        bool result = m_trade.PositionClose(ticket);

        if(result) {
            m_logger.Info("SmartClose",
                StringFormat("✅ Posição #%d fechada com sucesso", ticket));
        } else {
            m_logger.Error("SmartClose",
                StringFormat("❌ Falha ao fechar posição #%d: Erro=%d | %s",
                             ticket, GetLastError(), m_trade.ResultComment()));
        }

        return result;
    }

    //+--------------------------------------------------------------+
    //| Executa o abate parcial para uma direção específica          |
    //|                                                               |
    //| Processo:                                                     |
    //| 1. Obtém o estado da grade (pior posição, soma dos lucros)   |
    //| 2. Verifica se Σ lucros >= |pior prejuízo| + margem         |
    //| 3. Se sim, fecha a pior posição + posições lucrativas        |
    //| 4. Atualiza timestamp do último fechamento (cooldown)        |
    //+--------------------------------------------------------------+
    bool ProcessDirection(ENUM_POSITION_TYPE pos_type) {
        // Obtém estado completo da grade nesta direção
        SGridState state = m_pos_manager.GetGridState(pos_type);

        // Precisa de pelo menos 2 posições (1 perdedora + 1 lucrativa)
        if(state.total_levels < 2) return false;

        // Se não há posição perdedora ou lucrativa, não há o que fazer
        if(state.worst_ticket == 0 || state.worst_profit >= 0.0) return false;
        if(state.positive_profit_sum <= 0.0) return false;

        // Calcula a margem de segurança em USD
        double margin = CalculateMarginCost(state.worst_lot);

        // ═══════════════════════════════════════════════════════════
        // GATILHO PRINCIPAL DO SMART CLOSE:
        // A soma dos lucros das posições vencedoras deve ser suficiente
        // para cobrir o prejuízo da pior posição + margem de segurança
        // ═══════════════════════════════════════════════════════════
        double required = MathAbs(state.worst_profit) + margin;

        if(state.positive_profit_sum >= required) {
            m_logger.Info("SmartClose",
                StringFormat("🎯 GATILHO ATIVADO [%s] | Lucros=%.2f | Necessário=%.2f | Pior=#%d (%.2f USD)",
                             (pos_type == POSITION_TYPE_BUY ? "COMPRA" : "VENDA"),
                             state.positive_profit_sum,
                             required,
                             state.worst_ticket,
                             state.worst_profit));

            // Executa o fechamento em cascata
            return ExecuteSmartClose(pos_type, state);
        }

        return false;
    }

    //+--------------------------------------------------------------+
    //| Executa o fechamento em cascata (abate parcial)              |
    //|                                                               |
    //| Estratégia de fechamento:                                     |
    //| 1. Fecha a posição com maior prejuízo (alvo principal)       |
    //| 2. Fecha posições lucrativas até cobrir o prejuízo + margem  |
    //| 3. Para de fechar quando o "débito" for quitado              |
    //|                                                               |
    //| Isso é o "pulo do gato" do Daniel Moraes — em vez de um SL  |
    //| que fecha tudo no vermelho, o EA "sacrifica" lucros parciais |
    //| para eliminar a posição mais tóxica do portfólio.            |
    //+--------------------------------------------------------------+
    bool ExecuteSmartClose(ENUM_POSITION_TYPE pos_type, SGridState &state) {
        int    closed_count = 0;  // Contador de posições fechadas
        double closed_pnl   = 0.0; // P&L total das posições fechadas

        // PASSO 1: Fecha a posição com maior prejuízo
        if(ClosePosition(state.worst_ticket)) {
            closed_count++;
            closed_pnl += state.worst_profit; // Adiciona o prejuízo (negativo)
            m_logger.Info("SmartClose",
                StringFormat("📉 Pior posição fechada: #%d | P&L=%.2f USD",
                             state.worst_ticket, state.worst_profit));
        } else {
            m_logger.Error("SmartClose", "Falha ao fechar posição alvo. Abortando Smart Close.");
            return false;
        }

        // PASSO 2: Fecha posições lucrativas para cobrir o débito
        // O "débito" é o prejuízo que acabamos de realizar
        ulong  profitable_tickets[];
        double profitable_profits[];
        int profit_count = m_pos_manager.GetProfitableTickets(pos_type,
                                                              profitable_tickets,
                                                              profitable_profits);

        for(int i = 0; i < profit_count; i++) {
            // Se já cobrimos o débito, paramos de fechar
            // (queremos fechar o mínimo necessário de posições lucrativas)
            if(closed_pnl >= 0.0) break;

            if(ClosePosition(profitable_tickets[i])) {
                closed_count++;
                closed_pnl += profitable_profits[i];
                m_logger.Info("SmartClose",
                    StringFormat("📈 Posição lucrativa fechada: #%d | P&L=%.2f | Saldo do ciclo=%.2f",
                                 profitable_tickets[i], profitable_profits[i], closed_pnl));
            }
        }

        // Atualiza o timestamp do cooldown
        m_last_close_time = TimeCurrent();

        // Log final do ciclo de Smart Close
        m_logger.Info("SmartClose",
            StringFormat("═══ Ciclo concluído: %d posições fechadas | P&L líquido=%.2f USD ═══",
                         closed_count, closed_pnl));

        return true;
    }

public:
    //+--------------------------------------------------------------+
    //| Construtor — inicializa com configurações e dependências     |
    //+--------------------------------------------------------------+
    CSmartClose(string symbol, int magic_number,
                ENUM_CLOSE_TARGET close_target, double margin_points,
                CPositionManager *pos_manager, CLogger *logger) {

        m_symbol         = symbol;
        m_magic_number   = magic_number;
        m_close_target   = close_target;
        m_margin_points  = margin_points;
        m_pos_manager    = pos_manager;
        m_logger         = logger;
        m_last_close_time = 0;

        // Configura o objeto de trade
        m_trade.SetExpertMagicNumber(m_magic_number);
        m_trade.SetDeviationInPoints(10);

        m_logger.Info("SmartClose",
            StringFormat("Inicializado: %s | Alvo=%s | Margem=%.1f pts",
                         m_symbol,
                         EnumToString(m_close_target),
                         m_margin_points));
    }

    //+--------------------------------------------------------------+
    //| Método principal: verifica e executa o Smart Close           |
    //| Chamado pelo OnTick() do EA principal                        |
    //| Processa ambas as direções (compra e venda) independentemente|
    //| Retorna: true se algum fechamento foi executado              |
    //+--------------------------------------------------------------+
    bool CheckAndExecute() {
        // Verifica cooldown para evitar fechamentos em sequência rápida
        if(!IsCooldownExpired()) return false;

        bool executed = false;

        // Processa Smart Close para posições de COMPRA
        if(ProcessDirection(POSITION_TYPE_BUY)) {
            executed = true;
        }

        // Processa Smart Close para posições de VENDA
        if(ProcessDirection(POSITION_TYPE_SELL)) {
            executed = true;
        }

        return executed;
    }
};

//+------------------------------------------------------------------+
