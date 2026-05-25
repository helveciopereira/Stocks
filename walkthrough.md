# 🚶‍♂️ Walkthrough: Consistência de Versão Geral e Dashboard Dinâmico (v2.61)

Nesta versão, realizamos uma higienização cosmética e de consistência sistemática em toda a base de código do robô **Omni-B3**, elevando-o para a versão **v2.61** (+0.01 de incremento por se tratar de correções e alinhamento de strings de versão de baixa complexidade). Unificamos todas as diretivas de versão obsoletas que estavam dispersas pelos 16 arquivos do projeto, garantindo conformidade absoluta com a `RULE[user_global]`.

---

## 🛠️ O que foi Desenvolvido e Implementado na v2.61?

### 1. Refatoração Dinâmica do Título do Painel no Dashboard (`Dashboard.mqh`)
* **O Problema**: A string do título do painel néon na linha 733 estava definida estaticamente como " OMNI - B3   EA  v2.10". Isso exibia uma versão defasada e incorreta no gráfico, gerando confusão visual sobre a versão ativa real do robô.
* **A Solução**: Substituímos a string de versão estática por uma concatenação dinâmica que faz uso direto da constante central do sistema. A linha 733 passou a ser: `CreateLabel("Title", " OMNI - B3   EA  v" + OMNIB3_VERSION, m_x_offset + 15, m_y_offset + 12, 11, m_color_accent, "Outfit");`. Agora, qualquer atualização na constante global `#define OMNIB3_VERSION` será herdada automaticamente pelo painel gráfico em tempo real!

### 2. Unificação Sistemática das Propriedades de Versão (`#property version`)
* **O Problema**: Cada arquivo include (.mqh) possuía sua propriedade `#property version` desatualizada em relação à versão principal do projeto (alguns em `2.35`, outros em `2.50` e alguns em `2.60`).
* **A Solução**: Padronizamos as tags `#property version` de todos os 15 includes (.mqh) e do script principal (`.mq5`) para "2.61". Atualizamos também os comentários dos cabeçalhos estruturais no topo de cada arquivo para apontar para a versão `v2.61`.

### 3. Atualização de Parâmetros de Input Obsoletos no Script Principal (`OmniB3_EA.mq5`)
* **O Problema**: Os separadores visuais estáticos na interface de inputs de parâmetros do MT5 ainda continham versões obsoletas de desenvolvimento passados (e.g., `InpSeparatorVisuals` exibia "v2.45" e `InpSeparatorTrailing` exibia "v2.35").
* **A Solução**: Atualizamos essas strings literais de input no código do `OmniB3_EA.mq5` para "v2.61", unificando por completo a identidade do robô na tela de propriedades do usuário do MetaTrader 5.

### 4. Backups de Segurança da v2.60 e Versionamento
* **Backup de Segurança**: Criamos uma pasta dedicada em `c:\Projetos\Stocks\BACKUP\v2.60\` contendo a cópia idêntica e intacta de todos os 16 arquivos da versão anterior, preservando o histórico físico conforme a regra do usuário.
* **Compilação Homologada**: O robô foi compilado síncronamente via MetaEditor64 e obteve **0 erros e 0 warnings**, gerando o executável `OmniB3_EA.ex5` higienizado com sucesso.

---

## 📖 Como Usar e Configurar na v2.61

Nenhuma nova configuração lógica ou parâmetro foi adicionado a esta versão de correção. As melhorias são puramente de consistência de identidade, exibição visual do painel e tags de cabeçalho.
1. **Painel Gráfico**: Ao carregar o robô no gráfico do WIN ou WDO, o título do cabeçalho agora exibirá corretamente **"OMNI - B3   EA  v2.61"**.
2. **Propriedades do Input**: Na aba de parâmetros do robô do MT5, as marcas e divisórias de seção agora estão devidamente atualizadas para a **v2.61**.

---


# 🚶‍♂️ Walkthrough: Grade sob Bloqueio Diário, Priorização de Day Trade e Compactação Estética (v2.60)

Nesta versão, realizamos uma atualização lógica estrutural e altamente importante, elevando o robô **Omni-B3** para a versão **v2.60** (+0.1 de incremento por se tratar de correções lógicas de alta criticidade e arquitetura de riscos). Solucionamos os problemas operacionais de rebaixamento diário revelados nos relatórios de backtests, implementamos o reset diário inteligente do Kill-Switch no modo simulado e aplicamos uma compactação estética e remoção de tabulações em toda a base de código, deixando o editor extremamente limpo, profissional e legível.

---

## 🛠️ O que foi Desenvolvido e Implementado na v2.60?

### 1. Desvio de Grade sob Bloqueio Diário no RiskManager (`RiskManager.mqh`)
* **O Problema**: O limite de Drawdown Diário (5.0%), ao ser atingido flutuante no mercado, ativava a trava e bloqueava **toda e qualquer** ordem subsequente do robô. No modo grade (preço médio), isso impedia o robô de enviar novas ordens para gerenciar e recuperar a posição de compra/venda aberta no Nível 0. A grade ficava congelada enquanto o mercado caía, resultando no acionamento catastrófico do Equity Stop com perdas severas de 38% do saldo.
* **A Solução**: Reformulamos o método `IsSafeToTrade(int current_levels)`. Agora, todas as travas diárias operacionais (drawdown diário, limite de perdas, limite de lucros e limites de overtrading) **bloqueiam apenas o início de novas séries** (`current_levels == 0`). Se já existirem posições abertas na grade (`current_levels > 0`), o robô **terá permissão de continuar a abrir os níveis subsequentes** para gerenciar e recuperar a operação com segurança.
* **Preservação de Limites**: Assim que o limite é violado, o robô ativa imediatamente a flag `m_daily_locked = true` incondicionalmente em memória, impedindo de forma absoluta a abertura de quaisquer novas séries operacionais após a atual ser liquidada.

### 2. Reset Automático do Kill-Switch no Testador (`RiskManager.mqh`)
* **O Problema**: O limite inviolável do `Equity Stop` de liquidez (ex: 70% do saldo) ou limites de drawdown do `RiskManager`, ao serem ativados no mercado real, desligam o EA em definitivo (Kill-Switch) por segurança profissional. No entanto, em simulações do Testador de Estratégias (backtests), se o Kill-Switch fosse ativado em uma terça-feira, o EA ficava desligado permanentemente pelo resto de toda a simulação (quarta, quinta, sexta, etc.), impedindo o usuário de testar o robô nos dias seguintes.
* **A Solução**: No método `CheckDayReset()`, adicionamos uma verificação nativa do MQL5 para detectar se o EA está rodando no Testador (`MQLInfoInteger(MQL_TESTER) == true`). Caso esteja em modo backtest, o Kill-Switch é redefinido automaticamente (`m_kill_switch = false`) a cada virada de dia, permitindo que a simulação prosiga normalmente para os próximos dias, enquanto a segurança estrita e o desligamento permanente são totalmente preservados no mercado real!

### 3. Sincronização Imediata da Memória Virtual no Pânico (`OmniB3_EA.mq5`)
* **O Problema**: Quando o `IsSafeToTrade` do `RiskManager` acionava o Kill-Switch (como no Equity Stop), ele encerrava com sucesso as posições físicas do MT5 na corretora, mas a nossa memória virtual da grade (`levels` ou `total_levels`) permanecia em `3` (Nível 2). Ao tentar rodar o OnTick subsequente, o robô continuava achando que existiam posições e gerava o loop de erros `Posição real não encontrada!` no fechamento por horário de fim de dia, além da ativação incorreta da Salvaguarda Day Trade na abertura do dia seguinte.
* **A Solução**: No expert principal `OmniB3_EA.mq5`, se a verificação de risco de `IsSafeToTrade` falhar devido à ativação de um Kill-Switch (com `Risk.IsKillSwitchActive() == true`), e constarem níveis em memória virtual (`levels > 0`), nós de imediato limpamos a memória chamando `PosManager.ClearAllLevels()` e zeramos a variável `levels = 0`, garantindo sincronia perfeita e atômica da memória com o estado físico de liquidação total da corretora.

### 4. Cooldown de 10 Minutos nos Logs de Risco (`RiskManager.mqh`)
* **O Problema**: Quando o robô entrava em modo bloqueado por algum limite de risco, a função `IsSafeToTrade` econseguiam emitir avisos explicativos a cada tick de mercado, gerando gigabytes de logs de texto repetitivos e poluição nos diários do MetaTrader.
* **A Solução**: Implementamos controle de tempo estático (`static datetime`) em todos os logs de aviso repetitivos no `RiskManager.mqh`. Agora, as mensagens de aviso só serão impressas no diário a cada **10 minutos (600 segundos)** de bloqueio, poupando espaço em disco e garantindo um log de experts limpo e legível.

### 5. Prioridade Atômica de Salvaguardas no Topo de OnTick (`OmniB3_EA.mq5`)
* **O Problema**: A verificação de risco `IsSafeToTrade` ficava posicionada antes do filtro de horário operacional e do fechamento Day Trade no pipeline do tick. Ao bloquear por drawdown, o robô abortava a execução de `OnTick()` de forma precoce via `return;`. Por causa disso, a verificação de horário às 15:40 **nunca era executada**, fazendo a posição aberta durar ativa até o dia seguinte em modo Swing Trade de altíssimo risco.
* **A Solução**: Deslocamos a **Salvaguarda Estrita de Day Trade B3** (fechamento de posições de dias anteriores) e o **Filtro de Horário B3** para o **topo absoluto** do pipeline de execução no método `OnTick()`. O robô agora liquidará e fechará as posições físicas do pregão mesmo que esteja sob bloqueios operacionais diários ou restrições de risco, blindando a conta contra Swing Trades indesejados.

### 6. Compactação Estética e Limpeza Geral de Enters e Tabulações (Todos os 16 arquivos)
* **O Problema**: Nas edições e conversões passadas, gerou-se uma grande quantidade de quebras de linha em branco consecutivas e tabulações redundantes em todos os arquivos de código, inflando artificialmente o script principal para quase 7.000 linhas e degradando a estética.
* **A Solução**: Varremos os 16 arquivos do projeto, colapsando qualquer sequência consecutiva de 3 ou mais quebras de linha em uma única linha em branco limpa (`\n\n`), removendo caracteres Unicode não-CP1252 (como emojis e setas multibytes, substituídos por tags seguras como `[PROTECAO]` e `[ALERTA]`) e salvando em CP1252 no formato Windows (CRLF). O código agora está incrivelmente compacto, sofisticado e rápido de navegar.

---

## 📖 Como Usar e Configurar na v2.60

1. **Gestão de Risco Inteligente**: Configure o Drawdown Diário Máximo (`InpMaxDailyDDPercent` = `5.0`) ou limite de perda monetária (`InpLimitLossDaily`). Se a operação inicial entrar em prejuízo flutuante maior que 5.0%, o robô continuará a gerenciar as ordens da grade de preço médio perfeitamente para recuperar a operação. Porém, assim que a grade for fechada a mercado (lucro ou prejuízo), o EA não abrirá nenhuma nova série no dia.
2. **Day Trade Inviolável**: As posições de fim de dia serão incondicionalmente liquidadas às 16:40 e travadas, independentemente do EA estar sob bloqueio diário de risco, mantendo total proteção da conta.

---

# 🚶‍♂️ Walkthrough: Grade Bidirecional e Correção de Fechamento por Horário (v2.50)

Nesta versão, realizamos uma atualização lógica estrutural e altamente importante, elevando o robô **Omni-B3** para a versão **v2.50** (+0.1 de incremento por se tratar de uma atualização lógica de alta relevância). Introduzimos o **Modo Bidirecional de Exclusividade Mútua** (`GRID_BOTH`), permitindo ao robô operar tanto comprado quanto vendido dinamicamente sem ferir a conformidade na B3, e solucionamos o bug crítico do **Fechamento Automático de Fim de Dia** (Day Trade), que impedia a liquidação das ordens no prejuízo.

---

## 🛠️ O que foi Desenvolvido e Implementado na v2.50?

### 1. Modo Bidirecional de Exclusividade Mútua (`GRID_BOTH`)
* **O Problema**: A Bolsa brasileira (B3) opera sob o ecossistema de contas **NETTING** para minicontratos (WIN/WDO), o que impede e anula a manutenção de posições simultâneas de compra e venda no mesmo ativo. Por isso, a direção operacional clássica precisava de uma inteligência bidirecional, mas que garantisse exclusividade de ponta ativa.
* **A Solução**: Adicionamos a opção `GRID_BOTH` no parâmetro de entrada `InpDirection` (Defines.mqh). Quando habilitado:
  * Se a grade estiver limpa (sem posições), o robô aguarda o sinal composto dos indicadores: um sinal de alta abre COMPRA (`OpenBuyOrder(0)`) e um de baixa abre VENDA (`OpenSellOrder(0)`).
  * No momento em que a primeira ordem (nível 0) é aberta (ex: Compra), a grade inteira assume essa direção ativa.
  * Todas as decisões de novos níveis subsequentes da grade respeitam a direção da grade aberta por meio do novo método de verificação `m_pos_manager.GetGridDirection()`.
  * Sinais opostos (venda) são estritamente ignorados até que a grade de compra seja 100% liquidada pelo Smart Close, garantindo total conformidade operacional e de margem na B3.

### 2. Correção de Fechamento Incondicional de Fim de Dia (Day Trade)
* **O Problema**: Nas versões anteriores, quando o horário limite (ex: 16:40 ou 16:45) era atingido, o robô tentava fechar a grade chamando `Smart.CheckAndExecute(CMODE_TP_TOTAL)`. Este modo avaliava se o P&L atingiu o Take Profit monetário ou pontos configurado. Se a operação estivesse no prejuízo (drawdown flutuante comum em fins de dia), a função **rejeitava o fechamento** e a flag `m_close_executed` ficava travada em `true`, impedindo novas tentativas. As posições perduravam abertas para o dia seguinte, forçando Swing Trade de alto risco.
* **A Solução**:
  * Implementamos o método público `Smart.CloseAllPositions()` em [SmartClose.mqh](file:///c:/Projetos/Stocks/MQL5/Include/OmniB3/SmartClose.mqh), que executa a liquidação física a mercado **100% incondicional e síncrona** da grade, independentemente do P&L (lucro ou prejuízo).
  * No arquivo [TimeFilter.mqh](file:///c:/Projetos/Stocks/MQL5/Include/OmniB3/TimeFilter.mqh), adicionamos o método público `ResetCloseExecuted()`.
  * No loop central de ticks em [OmniB3_EA.mq5](file:///c:/Projetos/Stocks/MQL5/Experts/OmniB3/OmniB3_EA.mq5), se o horário for atingido, chamamos `Smart.CloseAllPositions()`. Caso a corretora enfrente lentidão ou rejeição de rede temporária no fechamento, o robô chama `TFilter.ResetCloseExecuted()` e continua tentando fechar a cada novo tick de forma síncrona até obter sucesso absoluto (níveis = 0), blindando a conta.

### 3. Backup de Segurança da v2.49 e Versionamento
* **Backup de Segurança**: Criamos uma cópia física completa de todos os arquivos de código da versão anterior **v2.49** na pasta dedicada `c:\Projetos\Stocks\BACKUP\v2.49\MQL5\`, em total conformidade com a `RULE[user_global]`.
* **Versionamento**: Elevamos as referências de cabeçalho nos 16 arquivos do projeto e atualizamos a constante global `#define OMNIB3_VERSION "2.50"` em [Defines.mqh](file:///c:/Projetos/Stocks/MQL5/Include/OmniB3/Defines.mqh).

---

## 📖 Como Usar e Configurar na v2.50

Acesse a nova aba de parâmetros e configure:
1. **Direção Bidirecional Exclusiva** (`InpDirection` = `GRID_BOTH`): O robô operará tanto comprado quanto vendido com base nos sinais, mas só iniciará uma direção se não houver posições ativas da outra.
2. **Day Trade Blindado** (`InpEndHour` = `16`, `InpEndMinute` = `40`): O robô liquidará **incondicionalmente** a mercado todas as posições da grade às 16:40 e travará novas entradas, repetindo a tentativa em todos os ticks até que o fechamento total seja confirmado na corretora.
