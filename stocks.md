# 💹 Projeto Omni-B3 v1.0: EA de Grid Trading com Smart Close

## 1. Visão Geral e Objetivo
Expert Advisor (EA) de alta performance em **MQL5** para MetaTrader 5, implementando estratégia de **Grid Trading Bi-direcional com Fechamento Inteligente (Smart Close)**, inspirada na metodologia de Daniel Moraes (tec_daniel — ToTheMoon EA).

### Filosofia da Estratégia
- **Entrada**: Grade de ordens em ambas as direções (compra e venda) com espaçamento fixo ou dinâmico (ATR)
- **Saída**: Sem SL/TP tradicionais. O lucro de ordens vencedoras é usado para "pagar" o fechamento da pior perdedora (abate parcial)
- **Resultado**: Redução contínua de exposição sem fechar ciclos no prejuízo

### Referência: Sinais do Daniel Moraes

| Sinal | Crescimento | Meses Ativos | Retorno Mensal | Drawdown Máx | Par | Alavancagem |
|:---|:---|:---|:---|:---|:---|:---|
| **NoPain MT5** | 1.930% | 236 semanas | ~3,2% | 20,6% | AUDCAD | 1:100 |
| **UpFuji MT5** | 73,56% | 52 semanas | ~5,6% | 31,5% | AUDCAD | 1:200 |

---

## 2. Stack Tecnológica

| Camada | Tecnologia | Função |
|:---|:---|:---|
| **Linguagem** | MQL5 (C++) | Lógica de trading e execução de ordens |
| **Plataforma** | MetaTrader 5 | Execução, backtesting e gráficos |
| **Conta** | Hedging | Obrigatório para grade bi-direcional |
| **Ativo Padrão** | AUDCAD | Baixa volatilidade, ideal para grid |
| **Timeframe** | M5 | Timeframe operacional e do ATR |

---

## 3. Arquitetura Modular (7 Módulos)

```
MQL5/
├── Experts/OmniB3/
│   └── OmniB3_EA.mq5          # Orquestrador — pipeline de execução
└── Include/OmniB3/
    ├── Defines.mqh             # Enums, structs, constantes globais
    ├── Logger.mqh              # Logging estruturado com níveis
    ├── PositionManager.mqh     # Consulta e análise de posições
    ├── GridEngine.mqh          # Motor de grade com ATR real
    ├── SmartClose.mqh          # Fechamento inteligente (abate parcial)
    ├── RiskManager.mqh         # Equity stop, DD, kill-switch
    └── TimeFilter.mqh          # Filtro de horário e bloqueios
```

### Pipeline de Execução (OnTick)
```
1. RiskManager  → Equity segura? DD dentro do limite?
2. SmartClose   → Lucro suficiente para abater a pior posição?
3. TimeFilter   → Estamos dentro da janela de operação?
4. GridEngine   → Preço andou o bastante para novo nível?
```

---

## 4. Lógica de Grade (GridEngine)

### Espaçamento
- **GRID_FIXED**: Espaçamento constante em pontos (ex: 100 pontos)
- **GRID_DYNAMIC_ATR**: Espaçamento = `ATR(período) × multiplicador`

### Gerenciamento de Lotes
$$Lote_{n} = Lote_{inicial} \times Multiplicador^{n}$$
- **LOT_FIXED** (Mult=1.0): mesmo lote em todos os níveis
- **LOT_MULTIPLIER** (Mult=1.2): lote cresce a cada nível

### Direção
- **BUY_ONLY / SELL_ONLY**: Grade unidirecional
- **BIDIRECTIONAL**: Grades de compra e venda simultâneas (~50/50)

### Travas de Segurança
- Limite configurável de níveis (padrão: 5 NoPain, 7 UpFuji)
- Limite absoluto hardcoded: 10 níveis (inviolável)
- Verificação de spread máximo antes de cada abertura

---

## 5. Smart Close (Abate Parcial)

### Gatilho
$$\sum Lucro_{Positivas} \geq |Prejuízo_{Pior}| + (MargemPts \times Volume_{Pior} \times \frac{TickValue}{TickSize} \times Point)$$

### Processo de Fechamento
1. Fecha a posição com maior prejuízo (alvo)
2. Fecha posições lucrativas em sequência até cobrir o débito
3. Para quando o P&L líquido do ciclo ≥ 0

### Proteções
- Cooldown de 5 segundos entre execuções
- Mínimo de 2 posições para ativar
- Margem de segurança configurável (padrão: 3 pontos)

---

## 6. Gestão de Risco (RiskManager)

| Proteção | Descrição | Padrão NoPain | Padrão UpFuji |
|:---|:---|:---|:---|
| **Equity Stop** | Fecha tudo se equity < X% do saldo | 75% | 65% |
| **DD Diário** | Bloqueia novas ordens se DD > X% no dia | 4% | 6% |
| **Max Posições** | Limite global de ordens simultâneas | 20 | 20 |
| **Margem Livre** | Não abre se margem livre < X% | 20% | 20% |
| **Kill-Switch** | Botão de pânico — fecha tudo e desliga | Manual | Manual |

---

## 7. Filtro de Horário (TimeFilter)

- **Janela padrão**: 01:00 - 23:00 (horário do servidor)
- **Bloqueio sexta**: Não abre novas ordens após 20:00 (evita gap de fim de semana)
- **Delay segunda**: Não abre antes das 02:00 (evita gap de abertura)
- **Smart Close**: Opera 24/7 (fechamento nunca é bloqueado por horário)

---

## 8. Perfis de Risco (Presets)

### NoPain (Conservador)
- Inspirado no sinal NoPain MT5 — **1.930% em 236 semanas**
- Lote: 0.01 | Multiplicador: 1.2 | Máx Níveis: 5
- ATR Mult: 1.5 | Margem Smart Close: 3 pontos
- Meta: ~3% ao mês com drawdown máximo de ~20%

### UpFuji (Agressivo)
- Inspirado no sinal UpFuji MT5 — **73% em 52 semanas**
- Lote: 0.01 | Multiplicador: 1.4 | Máx Níveis: 7
- ATR Mult: 1.2 | Margem Smart Close: 2 pontos
- Meta: ~5.5% ao mês com drawdown máximo de ~31%

---

## 9. Padrões de Código

- **Paradigma**: Orientação a Objetos estrita
- **Documentação**: 100% em Português Brasileiro
- **Tipagem**: Estática e rigorosa (MQL5 nativo)
- **Logging**: Estruturado com níveis (DEBUG, INFO, WARNING, ERROR, CRITICAL)
- **Comentários de Ordem**: `OmniB3_v1.0.0_BUY_L3` (rastreabilidade)

---

## 10. Roadmap

- [x] **v0.5.0 — Fundação**: Defines, Logger
- [x] **v0.7.0 — Motor**: GridEngine, PositionManager
- [x] **v0.8.0 — Smart Close**: Fechamento inteligente real
- [x] **v0.9.0 — Risco**: RiskManager, TimeFilter, Kill-Switch
- [x] **v1.0.0 — Orquestrador**: EA principal, documentação
- [ ] **v1.1.0 — Backtest**: Validação AUDCAD M5 (2020-2026)
- [ ] **v1.2.0 — Multi-Símbolo**: Suporte a múltiplos pares
- [ ] **v2.0.0 — Dashboard**: Painel visual no gráfico (labels, botões)

---

## 11. Referências
- MQL5 Community — Daniel Moraes (tec_daniel) — ToTheMoon EA
- Sinal NoPain MT5: https://www.mql5.com/pt/signals/2262642
- Sinal UpFuji MT5: https://www.mql5.com/pt/signals/2308095
- MetaTrader 5 MQL5 Reference — Trade Functions
- HM1 Engenharia — Padrões de Qualidade 2026
