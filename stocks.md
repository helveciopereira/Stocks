# 💹 Projeto Omni-B3 v1.1: EA de Grid Trading — Minicontratos B3

## 1. Visão Geral
Expert Advisor (EA) em **MQL5** para MetaTrader 5, implementando **Grid Trading com Smart Close** para **minicontratos da Bovespa (WIN/WDO)** em contas **NETTING**.

### Estratégia
- **Entrada**: Grade unidirecional (compra OU venda) com espaçamento fixo ou dinâmico (ATR)
- **Gestão**: Rastreamento virtual de níveis — cada nível é registrado internamente com preço e volume
- **Saída**: Smart Close — lucro virtual dos níveis positivos é usado para "pagar" o fechamento do pior nível
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
| **Plataforma** | MetaTrader 5 | Execução e backtesting |
| **Conta** | NETTING (Rico, XP, Clear) | Padrão B3 |
| **Ativos** | WIN (Mini Índice), WDO (Mini Dólar) | Minicontratos |
| **Moeda** | BRL (Real Brasileiro) | Conta em reais |

### Especificações dos Minicontratos

| Parâmetro | WIN (Mini Índice) | WDO (Mini Dólar) |
|:---|:---|:---|
| Tick Size | 5 pontos | 0,5 pontos |
| Tick Value | R$ 1,00/contrato | R$ 5,00/contrato |
| Volume Mínimo | 1 contrato | 1 contrato |
| Horário | 9:00 - 17:55 | 9:00 - 17:55 |
| Margem (aprox.) | ~R$ 100/contrato | ~R$ 150/contrato |

---

## 3. Arquitetura Modular (7 Módulos)

```
MQL5/
├── Experts/OmniB3/
│   └── OmniB3_EA.mq5          # Orquestrador principal
└── Include/OmniB3/
    ├── Defines.mqh             # Enums, structs (SVirtualLevel), constantes
    ├── Logger.mqh              # Logging com níveis e arquivo
    ├── PositionManager.mqh     # Rastreamento virtual de níveis (NETTING)
    ├── GridEngine.mqh          # Motor de grade com detecção de filling
    ├── SmartClose.mqh          # Abate parcial via contra-ordem
    ├── RiskManager.mqh         # Equity stop, DD diário, kill-switch
    └── TimeFilter.mqh          # Horário B3 (9:00-17:55)
```

### Pipeline de Execução (OnTick)
```
1. RiskManager  → Equity segura? DD dentro do limite?
2. SmartClose   → Lucro virtual suficiente para abate?
3. TimeFilter   → Dentro do pregão da B3?
4. GridEngine   → Preço andou o bastante para novo nível?
```

---

## 4. Lógica de Grade para NETTING

### Como funciona em NETTING
1. **Nível 0**: EA abre 1 contrato de compra → Posição real: COMPRA 1 @ 130.000
2. **Nível 1**: Preço cai 300pts → EA compra mais 1 → Posição real: COMPRA 2 @ média 129.850
3. **Nível 2**: Preço cai mais 300pts → EA compra mais 1 → Posição real: COMPRA 3 @ média 129.700
4. **Smart Close**: Preço sobe, nível 2 está lucrativo o bastante → EA vende 2 contratos (fecha nível 0 + 2)

### Rastreamento Virtual
Como NETTING tem apenas 1 posição, cada "nível" é registrado internamente:
```
m_levels[0] = { price: 130000, vol: 1, dir: BUY }  ← Pior (mais alto)
m_levels[1] = { price: 129700, vol: 1, dir: BUY }
m_levels[2] = { price: 129400, vol: 1, dir: BUY }  ← Melhor (mais baixo)
```

---

## 5. Perfis de Risco

| Parâmetro | Conservador | Moderado |
|:---|:---|:---|
| Volume inicial | 1 contrato | 1 contrato |
| Multiplicador | 1.0 (sem) | 1.5x |
| Máx. níveis | 3 | 5 |
| Margem Smart Close | 3 ticks | 2 ticks |
| Equity Stop | 92% | 85% |
| DD Diário máx | 2% | 4% |

---

## 6. Padrões de Código

- **Paradigma**: Orientação a Objetos estrita
- **Documentação**: 100% em Português Brasileiro
- **Tipagem**: Estática e rigorosa (MQL5)
- **Filling Mode**: Detecção automática (IOC/FOK/RETURN)
- **Volume**: Contratos inteiros (mínimo 1)

---

## 7. Roadmap

- [x] v1.0.0 — Implementação base (Forex/HEDGING)
- [x] v1.1.0 — Adaptação para B3/NETTING com rastreamento virtual
- [ ] v1.2.0 — Backtesting e calibração de parâmetros para WIN
- [ ] v1.3.0 — Suporte a WDO (Mini Dólar)
- [ ] v1.4.0 — Dashboard visual no gráfico (labels, P&L, botões)
- [ ] v2.0.0 — Filtros inteligentes (tendência, volatilidade)

---

## 8. Referências
- MQL5 Community — Daniel Moraes (tec_daniel) — ToTheMoon EA
- MetaTrader 5 MQL5 Reference — Trade Functions
- B3 — Especificações de Minicontratos
