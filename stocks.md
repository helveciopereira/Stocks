# 💹 Projeto Omni-B3 v2.10: EA de Grid Trading Avançado e Ordem Única — Minicontratos B3

## 1. Visão Geral
Expert Advisor (EA) em **MQL5** para MetaTrader 5, implementando **Grid Trading Avançado com Smart Close** e **Modo Ordem Única com Martingale** para **minicontratos da Bovespa (WIN/WDO)** em contas **NETTING**.

**Evolução v2.00 → v2.10**: Conclusão da **Fase 2 de Evolução**. Incorpora painel gráfico premium néon com suporte a temas e botões interativos (`CDashboard`), modo de negociação de contratos individuais sem grade (`CSingleOrder`) com Martingale/Anti-Martingale integrado, e filtro de notícias com calendário econômico nativo do MT5 (`CNewsFilter`) com ações de bloqueio dinâmicas.

### Estratégia
- **Entrada**: Grade tradicional (compra OU venda) com espaçamento fixo, dinâmico (ATR), step multiplicador OU Modo Ordem Única (Single Order).
- **Sinais**: 12+ indicadores técnicos (RSI, CCI, Bollinger, Envelopes, MAs, VWAP, HILO, Pivot, ADX, ATR, Candle Sequence, Price GAP).
- **Gestão**: Rastreamento virtual de níveis com persistência binária — sobrevive a falhas e reinícios de terminal.
- **Saída**: 12+ modos de fechamento (Smart Close, TP total/monetário/aceitável, BreakEven, por quantidade, aceitar perda) ou fechamento por sinal contrário.
- **Proteção**: Recovery Mode automático, Money Management, Kill-Switch, limites de segurança e Filtro de Notícias Nativo.
- **Moeda**: Real Brasileiro (BRL) na conta Rico-DEMO.

### Diferença NETTING vs HEDGING
| Aspecto | HEDGING (Forex) | NETTING (B3) |
|:---|:---|:---|
| Posições por símbolo | Múltiplas independentes | Uma única agregada |
| Bi-direcional | Sim (compra + venda) | Não (uma direção) |
| Fechamento individual | Por ticket | Por contra-ordem parcial |
| Rastreamento de níveis | Via posições reais | Via array virtual interno |

---

## 2. Stack Tecnológica

| Camada | Tecnologia | Função |
|:---|:---|:---|
| **Linguagem** | MQL5 (C++) | Lógica de trading robusta |
| **Plataforma** | MetaTrader 5 | Execução e testes de estratégia |
| **Conta** | NETTING (Rico-DEMO) | Padrão B3 do mercado brasileiro |
| **Ativos** | WIN (Mini Índice), WDO (Mini Dólar) | Minicontratos de alto giro |
| **Moeda** | BRL (Real Brasileiro) | Conta em reais |
| **Saldo Demo** | R$ 10.000,00 | Plataforma Demo de simulação real |

### Especificações dos Minicontratos

| Parâmetro | WIN (Mini Índice) | WDO (Mini Dólar) |
|:---|:---|:---|
| Tick Size | 5 pontos | 0,5 pontos |
| Tick Value | R$ 1,00/contrato | R$ 5,00/contrato |
| Volume Mínimo | 1 contrato | 1 contrato |
| Horário | 9:00 - 17:55 | 9:00 - 17:55 |
| Margem (aprox.) | ~R$ 100/contrato | ~R$ 150/contrato |

---

## 3. Arquitetura Modular (14 Módulos)

```
MQL5/
├── Experts/OmniB3/
│   └── OmniB3_EA.mq5              # Orquestrador principal (~120 inputs)
└── Include/OmniB3/
    ├── Defines.mqh                 # Enums, structs, constantes (35+ enums)
    ├── Logger.mqh                  # Logging com níveis e arquivo
    ├── IndicatorHub.mqh            # 12+ indicadores + filtros técnicos
    ├── MoneyManager.mqh            # Saldo robô, xPreset, ajuste moeda
    ├── StatePersistence.mqh        # Persistência binária com checksum
    ├── RecoveryMode.mqh            # Recovery automático por DD%/ordens
    ├── PositionManager.mqh         # Rastreamento virtual + persistência
    ├── GridEngine.mqh              # Grade: step mult, candle gigante, indicadores
    ├── SmartClose.mqh              # 12+ modos de fechamento
    ├── RiskManager.mqh             # Limites: atual/diário/conta
    ├── TimeFilter.mqh              # Horário B3, dias, redução TP tempo
    ├── Dashboard.mqh       [NOVO]  # Painel gráfico interativo (Néon)
    ├── SingleOrder.mqh     [NOVO]  # Modo Ordem Única (SL/TP/BE + Martingale)
    └── NewsFilter.mqh      [NOVO]  # Filtro Calendário Notícias nativo MT5
```

### Pipeline de Execução Avançado (OnTick)
```
1. Dashboard     → Detecta cliques em botões (Pausa, Pânico, Fechar Tudo, Reset)
2. NewsFilter    → Avalia proximidade de eventos. Notícia crítica?
                 ├─ Ação CLOSE_ALL  → Encerra tudo e retorna
                 └─ Ação STOP_ALL   → Bloqueia execução e retorna
3. MoneyManager  → StopLoss do robô atingido?
4. RiskManager   → Equity/DD/margem seguros?
5. SingleOrder   → Se Ordem Única Habilitada:
                 ├─ Trailing BreakEven & SL/TP
                 ├─ Fechar por sinal contrário?
                 └─ Abertura por sinal técnico (respeitando Martingale & Cooldown)
6. GridEngine    → Se Grade Tradicional Habilitada:
                 ├─ RecoveryMode: Avaliar ativação/desativação
                 ├─ SmartClose: Algum modo de fechamento dispara?
                 ├─ TimeFilter: Dentro do pregão da B3?
                 ├─ IndicatorHub: Sinal composto + Filtros (ATR, ADX)
                 └─ GridEngine: Abrir novo nível virtual de grade
```

---

## 4. Detalhes dos Módulos da Fase 2

### A. Painel e Dashboard Gráfico (`CDashboard`)
- **Visual Néon**: Fundo semi-transparente estilo *glassmorphism*, perfeito para telas modernas.
- **Métricas Completas**: Exibe Saldo, Capital Líquido (Equity), P&L Diário, P&L Flutuante, Drawdown %, Níveis Ativos e Próxima Notícia do calendário.
- **Controle Interativo**:
  - `🚨 PANICO (KILL)`: Fecha todas as ordens e posições imediatamente e trava o EA de novas aberturas.
  - `❌ FECHAR TUDO`: Encerra a série ou posição aberta de imediato a mercado.
  - `⏸ PAUSAR EA / ▶ RETOMAR`: Permite suspender novas entradas temporariamente sem desinstalar o robô.
  - `🔄 RESET DIARIO`: Redefine o estado do Kill-Switch e contadores diários.

### B. Modo Ordem Única (`CSingleOrder`)
- **SL/TP/BE Individual**: Ao invés de fazer média, trabalha com StopLoss e TakeProfit em pontos definidos por trade.
- **BreakEven Trailing**: Move o StopLoss para o ponto de entrada mais uma pequena margem assim que o mercado atinge o limite de ativação.
- **Martingale Sequencial**:
  - `Martingale`: Dobra ou multiplica o lote inicial em caso de trade perdedor.
  - `Anti-Martingale`: Aumenta o tamanho do lote em caso de ganho sequencial para maximizar lucros.
- **Cooldown de Espera**: Bloqueia novas ordens por N segundos após uma perda ou ganho para deixar o mercado se acalmar.

### C. Filtro de Notícias (`CNewsFilter`)
- **Calendário Nativo do MT5**: Carrega dados do calendário oficial sem precisar de URLs WebRequest.
- **Filtro Moeda e Impacto**: Escolhe filtrar BRL, USD ou ALL com base em impacto Médio ou Alto.
- **Ações Inteligentes**:
  - `NEWS_ACTION_STOP_INITIAL`: Não permite abrir nova série (Nível 0), mas permite que a grade se movimente para recuperar posições se já estiver ativa.
  - `NEWS_ACTION_STOP_ALL`: Bloqueia totalmente o envio de qualquer nova ordem.
  - `NEWS_ACTION_CLOSE_ALL`: Zera todas as posições abertas na iminência de um anúncio de forte impacto.

---

## 5. Perfis de Risco (para R$10.000)

| Parâmetro | Conservador | Moderado | Agressivo |
|:---|:---|:---|:---|
| Modo Principal | Ordem Única | Grade Tradicional | Grade Tradicional |
| Volume Inicial | 1 contrato | 1 contrato | 2 contratos |
| Multiplicador | x1 (sem) | 1.3x | 1.5x |
| Máx. Níveis | 1 (Single) | 5 | 8 |
| Passo (pts) | - | 300 | 200 |
| Step mult | - | 1.2 | 1.3 |
| Equity Stop | 92% | 85% | 80% |
| DD Diário máx | 2% | 3% | 5% |
| Filtro Notícias | Sim (Stop Initial) | Sim (Stop Initial) | Desabilitado |

---

## 6. Roadmap Atualizado

- [x] v1.0.0 — Implementação base (Forex/HEDGING)
- [x] v1.1.0 — Adaptação para B3/NETTING com rastreamento virtual
- [x] v2.0.0 — **Reescrita completa (Fase 1)**: 12+ indicadores, 12+ modos de fechamento, Recovery, Persistência, Money Management.
- [x] v2.1.0 — **Novas Funcionalidades (Fase 2)**: CDashboard néon interativo, CSingleOrder com Martingale e CNewsFilter calendário do MT5.
- [ ] v2.2.0 — Backtesting, calibração fina e empacotamento de presets (.set) otimizados para WIN/WDO.
- [ ] v3.0.0 — Multi-Ativos Completo (WIN + WDO simultâneo, P&L agregado).

---

## 7. Referências
- MQL5 Community — Daniel Moraes (tec_daniel) — ToTheMoon EA v3.5
- MetaTrader 5 MQL5 Reference — Calendário Econômico, Funções Gráficas e Trailing.
- B3 — Especificações de Minicontratos (WIN/WDO)
