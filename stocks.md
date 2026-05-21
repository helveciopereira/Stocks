# 💹 Projeto Omni-B3 v2.0: EA de Grid Trading Avançado — Minicontratos B3

## 1. Visão Geral
Expert Advisor (EA) em **MQL5** para MetaTrader 5, implementando **Grid Trading Avançado com Smart Close** para **minicontratos da Bovespa (WIN/WDO)** em contas **NETTING**.

**Evolução v1.1 → v2.0**: Reescrita significativa inspirada no **ToTheMoon v3.5** (Daniel Moraes), incorporando 12+ indicadores técnicos, 12+ modos de fechamento, gestão de capital avançada, Recovery Mode, persistência de estado e filtros inteligentes.

### Estratégia
- **Entrada**: Grade unidirecional (compra OU venda) com espaçamento fixo, dinâmico (ATR) ou multiplicador
- **Sinais**: 12+ indicadores técnicos (RSI, CCI, Bollinger, Envelopes, MAs, VWAP, HILO, Pivot, ADX, ATR, Candle Sequence, Price GAP)
- **Gestão**: Rastreamento virtual de níveis com persistência — sobrevive reinícios
- **Saída**: 12+ modos de fechamento (Smart Close, TP total/monetário/aceitável, BreakEven, por quantidade, aceitar perda)
- **Proteção**: Recovery Mode automático, Money Management, Kill-Switch, limites diários/por conta
- **Moeda**: Real Brasileiro (BRL)

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
| **Linguagem** | MQL5 (C++) | Lógica de trading |
| **Plataforma** | MetaTrader 5 | Execução e trading |
| **Conta** | NETTING (Rico-DEMO) | Padrão B3 |
| **Ativos** | WIN (Mini Índice), WDO (Mini Dólar) | Minicontratos |
| **Moeda** | BRL (Real Brasileiro) | Conta em reais |
| **Saldo Demo** | R$ 10.000,00 | Conta Rico-DEMO |

### Especificações dos Minicontratos

| Parâmetro | WIN (Mini Índice) | WDO (Mini Dólar) |
|:---|:---|:---|
| Tick Size | 5 pontos | 0,5 pontos |
| Tick Value | R$ 1,00/contrato | R$ 5,00/contrato |
| Volume Mínimo | 1 contrato | 1 contrato |
| Horário | 9:00 - 17:55 | 9:00 - 17:55 |
| Margem (aprox.) | ~R$ 100/contrato | ~R$ 150/contrato |

---

## 3. Arquitetura Modular (11 Módulos)

```
MQL5/
├── Experts/OmniB3/
│   └── OmniB3_EA.mq5              # Orquestrador principal (~100 inputs)
└── Include/OmniB3/
    ├── Defines.mqh                 # Enums, structs, constantes (30+ enums)
    ├── Logger.mqh                  # Logging com níveis e arquivo
    ├── IndicatorHub.mqh        [NOVO] # 12+ indicadores + filtros técnicos
    ├── MoneyManager.mqh        [NOVO] # Saldo robô, xPreset, ajuste moeda
    ├── StatePersistence.mqh    [NOVO] # Persistência binária com checksum
    ├── RecoveryMode.mqh        [NOVO] # Recovery automático por DD%/ordens
    ├── PositionManager.mqh         # Rastreamento virtual + persistência
    ├── GridEngine.mqh              # Grade: step mult, candle gigante, indicadores
    ├── SmartClose.mqh              # 12+ modos de fechamento
    ├── RiskManager.mqh             # Limites: atual/diário/conta
    └── TimeFilter.mqh              # Horário B3, dias, redução TP tempo
```

### Pipeline de Execução (OnTick)
```
1. MoneyManager  → StopLoss do robô atingido?
2. RiskManager   → Equity/DD/margem seguros?
3. RecoveryMode  → Avaliar ativação/desativação
4. SmartClose    → Algum modo de fechamento dispara? (em recovery usa modo alternativo)
5. TimeFilter    → Dentro do pregão da B3?
6. IndicatorHub  → Sinal composto (principal + 4 confirmações)
7. Filtros       → ATR, ADX, Volume passam?
8. GridEngine    → Abrir novo nível?
```

---

## 4. Lógica de Grade para NETTING

### Como funciona em NETTING
1. **Nível 0**: EA abre 1 contrato de compra → Posição real: COMPRA 1 @ 130.000
2. **Nível 1**: Preço cai (espaçamento × step_mult^0) → EA compra mais → Posição real: COMPRA 2+
3. **Nível 2**: Preço cai mais (espaçamento × step_mult^1) → EA compra mais → Posição cresce
4. **Smart Close**: Quando lucro virtual dos melhores cobre prejuízo do pior + margem → fecha parcial

### Rastreamento Virtual com Persistência
Como NETTING tem apenas 1 posição, cada "nível" é registrado internamente e **salvo em arquivo binário**:
```
m_levels[0] = { price: 130000, vol: 1, dir: BUY, recovery: false }  ← Pior
m_levels[1] = { price: 129700, vol: 1, dir: BUY, recovery: false }
m_levels[2] = { price: 129400, vol: 2, dir: BUY, recovery: true  }  ← Melhor (Recovery)
```

### Funcionalidades da Grade v2.0
| Funcionalidade | Descrição |
|:---|:---|
| **Step Multiplicador** | Passo cresce a cada nível (ex: 1.2 = +20%) |
| **Valor Somado** | Pontos extras que decaem com o tempo |
| **Next Lot** | Fator × ou + com espera entre ordens |
| **Candle Gigante** | Pausa após candle anormalmente grande |
| **Indicador Grid** | Usa indicadores para validar abertura de grid |
| **Recovery** | Altera grid quando DD alto |

---

## 5. Indicadores Técnicos (12+)

| Indicador | Tipo | Sinal |
|:---|:---|:---|
| **RSI** | Sobrecompra/Sobrevenda | < 30 → compra, > 70 → venda |
| **CCI** | Channel Index | < -100 → compra, > 100 → venda |
| **Bollinger Bands** | Toque nas bandas | Toca inferior → compra |
| **Envelopes** | Desvio da média | Fora do envelope → sinal |
| **Médias Móveis** | Cruzamento | Rápida > Lenta → compra |
| **VWAP** | Preço ponderado | Abaixo → compra |
| **HILO** | High-Low Activator | Preço > HILO → compra |
| **Pivot Point** | Suporte/Resistência | Toca suporte → compra |
| **ADX** | Força da tendência | DI+ > DI- → compra |
| **ATR** | Volatilidade | Faixa de operação |
| **Candle Sequence** | Padrão direcional | Sequência de alta → compra |
| **Price GAP** | Diferença entre candles | Gap significativo → sinal |

### Filtros (bloqueiam abertura sem gerar sinal)
- **Filtro ATR**: Volatilidade dentro da faixa aceitável
- **Filtro ADX**: Força mínima da tendência
- **Filtro Volume**: Volume mínimo no candle

---

## 6. Modos de Fechamento (12+)

| Modo | Descrição |
|:---|:---|
| **Smart Close (Pior)** | Lucro dos bons paga fechamento do pior nível |
| **Smart Close (Antigo)** | Fecha o mais antigo usando lucro dos outros |
| **TP Total** | Fecha tudo quando P&L total ≥ TakeProfit |
| **TP Monetário** | Fecha quando lucro ≥ R$ configurado |
| **Metade** | Fecha 50% dos lucrativos |
| **Soma Lotes Total** | Fecha quando soma de lotes ≥ limite |
| **Soma Lotes Metade** | Fecha metade se lotes ≥ limite |
| **Média Lotes** | Fecha quando média de lotes ≥ limite |
| **Qtde Ordens** | Fecha quando quantidade ≥ limite |
| **Qtde Ordens Metade** | Fecha metade se quantidade ≥ limite |
| **Aceitar Perda** | Fecha com perda se DD baixo e muitos lotes |
| **BreakEven** | Fecha quando preço atinge média ± margem |

### TakeProfit Avançado
- **Redução por Tempo**: TP diminui linearmente com o tempo
- **Redução por DD**: TP diminui quando drawdown aumenta
- **TP Aceitável**: Piso do TP (pode ser negativo para aceitar perda)

---

## 7. Perfis de Risco (para R$10.000)

| Parâmetro | Conservador | Moderado | Agressivo |
|:---|:---|:---|:---|
| Volume inicial | 1 contrato | 1 contrato | 2 contratos |
| Multiplicador | 1.0 (sem) | 1.3x | 1.5x |
| Máx. níveis | 3 | 5 | 8 |
| Passo (pts) | 400 | 300 | 200 |
| Step mult | 1.0 | 1.2 | 1.3 |
| Equity Stop | 92% | 85% | 80% |
| DD Diário máx | 2% | 3% | 5% |
| Recovery DD | desab. | 50% | 40% |

---

## 8. Padrões de Código

- **Paradigma**: Orientação a Objetos estrita
- **Documentação**: 100% em Português Brasileiro
- **Tipagem**: Estática e rigorosa (MQL5)
- **Filling Mode**: Detecção automática (IOC/FOK/RETURN)
- **Volume**: Contratos inteiros (mínimo 1)
- **Persistência**: Arquivo binário com checksum (sobrevive restarts)
- **Indicadores**: Handles compartilhados via IndicatorHub
- **Configuração**: ~100 inputs organizados por seção

---

## 9. Roadmap

- [x] v1.0.0 — Implementação base (Forex/HEDGING)
- [x] v1.1.0 — Adaptação para B3/NETTING com rastreamento virtual
- [x] v2.0.0 — **Reescrita completa**: 12+ indicadores, 12+ modos de fechamento, Recovery, Persistência, Money Management
- [ ] v2.1.0 — Backtesting e calibração de parâmetros para WIN
- [ ] v2.2.0 — Dashboard visual no gráfico (painel com P&L, indicadores, botões)
- [ ] v2.3.0 — Suporte a WDO (Mini Dólar) com presets dedicados
- [ ] v2.4.0 — Filtro de Notícias (calendário econômico MT5)
- [ ] v2.5.0 — Modo Ordem Única (single trade, sem grid)
- [ ] v3.0.0 — Multi-Ativos (WIN + WDO simultâneo, P&L agregado)

---

## 10. Referências
- MQL5 Community — Daniel Moraes (tec_daniel) — ToTheMoon EA v3.5
- MetaTrader 5 MQL5 Reference — Trade Functions, Indicators
- B3 — Especificações de Minicontratos (WIN/WDO)
- ToTheMoon v3.5 — PRESETS README (NoPain, NoFear, UpHill, etc.)
- ToTheMoon v3.5 — Changelog/Atualizações (v2.0 a v3.5)
