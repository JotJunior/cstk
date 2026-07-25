# Feature Specification: Metricas de Tokens por Spawn de Subagente

**Feature**: `wave-token-metrics`
**Created**: 2026-07-25
**Status**: Draft

## Clarifications

### Session 2026-07-25

- Q: Esta feature deve ESTENDER a infraestrutura de metricas por onda ja existente no toolkit (adicionando granularidade por spawn) ou introduzir um mecanismo de captura/armazenamento novo e independente? → A: Estender a infraestrutura ja existente, adicionando granularidade por spawn — mesmo padrao ja usado para tool_calls (fail-open, sidecar por onda, nunca bloqueia a orquestracao).

## User Scenarios & Testing

### User Story 1 - Ver tokens/tool-uses/duracao por onda no relatorio de execucao (Priority: P1)

Como operador que revisa uma execucao autonoma (`agente-00c`/`feature-00c`), ao
abrir o relatorio de uma onda concluida, quero ver o consumo real de tokens,
a contagem de tool-uses e a duracao de cada spawn de subagente daquela onda —
nao apenas a contagem de tool_calls que o toolkit usa hoje como proxy de
custo.

**Why this priority**: e o valor central da feature — sem isso, a metrica
"tool_calls" continua sendo a unica leitura de custo disponivel, que e um
proxy grosseiro (uma tool call de 50 tokens e uma de 50.000 tokens contam
igual). Sozinha, esta story ja entrega valor mensuravel ao operador.

**Independent Test**: concluir uma onda de uma execucao autonoma com pelo
menos um spawn de subagente e verificar que o relatorio da onda exibe
tokens/tool-uses/duracao daquele spawn (ou marca explicitamente a metrica
como indisponivel, nunca inventada — ver FR-009).

**Acceptance Scenarios**:

1. **Given** uma onda que spawnou 1 subagente e o subagente concluiu
   normalmente, **When** o operador abre o relatorio da onda, **Then** o
   relatorio mostra tokens consumidos, tool-uses e duracao daquele spawn.
2. **Given** uma onda que spawnou 3 subagentes em momentos diferentes,
   **When** o operador abre o relatorio da onda, **Then** o relatorio mostra
   as 3 metricas individualmente atribuidas a cada spawn, alem de um total
   agregado da onda.
3. **Given** um spawn cujo dado de uso nao pode ser obtido (ver Edge Cases),
   **When** o operador abre o relatorio, **Then** a metrica daquele spawn
   aparece marcada como indisponivel — nunca como zero ou um numero
   estimado.

---

### User Story 2 - Auditar custo x modelo roteado (Priority: P2)

Como operador que avalia se o roteamento automatico de modelos
(model-routing) esta sendo economico, quero cruzar, por onda, o modelo que
foi efetivamente roteado para cada subagente com o consumo de tokens
observado naquele spawn — para decidir se o mapa de roteamento (ou um
refino pontual) precisa mudar.

**Why this priority**: depende da User Story 1 (a metrica de tokens precisa
existir primeiro), mas e o que transforma a metrica bruta em decisao
acionavel — sem o cruzamento com o modelo roteado, o numero de tokens sozinho
nao diz se o roteamento esta caro ou barato.

**Independent Test**: rodar duas ondas que roteiam modelos diferentes para o
mesmo tipo de subagente e verificar que a auditoria de custo x roteamento
existente no toolkit consegue exibir, lado a lado, o modelo roteado e o
consumo de tokens de cada onda.

**Acceptance Scenarios**:

1. **Given** duas ondas historicas com modelos roteados diferentes para
   subagentes equivalentes, **When** o operador consulta a auditoria de
   custo x roteamento, **Then** consegue comparar tokens consumidos por
   modelo sem fazer calculo manual fora do toolkit.

---

### User Story 3 - Consultar historico de consumo entre features/projetos (Priority: P3)

Como operador que ja tem o habito de consultar decisoes e bloqueios
passados via memoria de conhecimento cross-feature do toolkit, quero que o
consumo de tokens por onda tambem fique disponivel nessa mesma memoria
historica, para poder perguntar "quanto essa categoria de tarefa costuma
consumir" antes de iniciar uma execucao nova.

**Why this priority**: e uma extensao natural de uma capacidade que ja
existe (a memoria cross-feature ja indexa decisoes, bloqueios e skills
invocadas); sem ela, a metrica de tokens fica presa a execucao onde foi
capturada e nao alimenta decisoes de planejamento futuras.

**Independent Test**: apos uma onda com metrica de tokens capturada, uma
consulta a memoria historica do toolkit por aquela feature/projeto retorna
o consumo de tokens registrado, junto com a proveniencia (projeto, feature,
onda, data) que a memoria ja oferece para outros tipos de registro.

**Acceptance Scenarios**:

1. **Given** uma onda com metricas de tokens ja capturadas e persistidas,
   **When** o operador consulta a memoria de conhecimento historica por
   aquela feature, **Then** o consumo de tokens da onda aparece no
   resultado, com a mesma proveniencia (projeto/feature/onda/data) dos
   demais tipos de registro ja indexados.

---

### User Story 4 - Reconstruir metricas de execucoes passadas (Priority: P4)

Como operador que so vai perceber o valor desta feature depois de ja ter
rodado varias execucoes autonomas sem ela, quero poder recuperar o consumo
de tokens dessas execucoes passadas a partir do que ja ficou registrado em
disco durante aquelas sessoes — em vez de perder esse historico ou precisar
re-executar tudo de novo so para gerar a metrica.

**Why this priority**: e um bonus de menor prioridade sobre as stories
anteriores — nao e necessario para o operador comecar a se beneficiar da
metrica em execucoes NOVAS (US1-US3 ja entregam isso). E candidata natural
a uma fase de implementacao separada, com seu proprio ritmo de validacao.

**Independent Test**: escolher uma execucao autonoma concluida antes desta
feature existir, cujos dados de sessao ainda estejam preservados em disco,
rodar a reconstrucao retroativa e confirmar que o consumo de tokens daquela
execucao passa a aparecer nos mesmos lugares onde apareceria se tivesse sido
capturado ao vivo.

**Acceptance Scenarios**:

1. **Given** uma execucao concluida antes desta feature existir, com os
   dados de sessao originais ainda preservados em disco, **When** o operador
   aciona a reconstrucao retroativa para essa execucao, **Then** o consumo
   de tokens passa a estar disponivel nos relatorios e na consulta
   historica, do mesmo jeito que uma execucao capturada ao vivo.
2. **Given** uma execucao cujos dados de sessao originais ja nao existem
   mais em disco (ex.: sessao expirada/removida), **When** o operador tenta
   reconstruir retroativamente, **Then** o sistema informa explicitamente
   que aquela execucao nao pode ser reconstruida — nunca preenche com um
   valor estimado.

---

### Edge Cases

- O que acontece quando um spawn de subagente falha/aborta antes de
  retornar (nunca completa)? O consumo parcial ate o momento da falha deve
  ser capturado, ou a metrica fica marcada como indisponivel para esse
  spawn especifico?
- O que acontece quando o dado de uso do subagente simplesmente nao esta
  disponivel para captura (ambiente degradado, fonte de dados ausente)? A
  onda continua normalmente, so sem aquela metrica (ver FR-008)?
- Como o sistema atribui a metrica quando varios subagentes rodam em
  paralelo dentro da mesma onda — cada spawn mantem sua metrica
  individual, alem do agregado da onda?
- O que acontece quando o operador tenta reconstruir retroativamente
  (US4) uma execucao cujos dados de sessao originais ja foram removidos do
  disco? (ver Acceptance Scenario 2 da US4)
- O que acontece quando duas execucoes rodam concorrentemente sobre o
  mesmo projeto — a atribuicao de consumo por onda continua correta sem
  misturar spawns de execucoes diferentes?

## Requirements

### Functional Requirements

- **FR-001**: O sistema MUST capturar, para cada spawn de subagente que
  completa dentro de uma onda de orquestracao autonoma, uma metrica de
  tokens consumidos associada aquele spawn.
- **FR-002**: O sistema MUST capturar, para cada spawn de subagente que
  completa dentro de uma onda, uma metrica de contagem de tool-uses e uma
  metrica de duracao associadas aquele spawn.
- **FR-003**: O sistema MUST associar cada metrica de spawn capturada a
  onda, a feature/projeto e, quando aplicavel, ao modelo que foi roteado
  para aquele spawn.
- **FR-004**: As metricas de spawn capturadas MUST permanecer consultaveis
  apos o encerramento da sessao de orquestracao (nao apenas visiveis
  durante a conversa ao vivo).
- **FR-005**: O sistema MUST exibir metricas agregadas de tokens/tool-uses/
  duracao por onda nos relatorios de execucao ja existentes da
  orquestracao autonoma.
- **FR-006**: O sistema MUST tornar as metricas historicas de consumo por
  spawn consultaveis entre features e projetos diferentes, de forma
  consistente com o que ja acontece hoje para outros tipos de registro da
  memoria de conhecimento cross-feature do toolkit.
- **FR-007**: O sistema MUST permitir correlacionar o consumo de tokens
  capturado com o modelo que foi roteado para aquele spawn (auditoria de
  custo x roteamento ja existente no toolkit), para o operador avaliar se
  o roteamento esta sendo economico.
- **FR-008**: A captura de metricas de spawn MUST ser best-effort — a
  ausencia ou malformacao da fonte de dados de uso subjacente MUST NOT
  abortar nem bloquear a onda de orquestracao.
- **FR-009**: O sistema MUST NOT inventar/estimar consumo de tokens quando
  o valor real nao esta disponivel para um spawn — uma metrica indisponivel
  MUST ser registrada explicitamente como ausente/desconhecida, nunca como
  um numero fabricado (Constitution Principio VI).
- **FR-010**: O sistema SHOULD suportar a reconstrucao de metricas de
  consumo para execucoes de orquestracao passadas, a partir de dados ja
  persistidos em disco durante aquelas sessoes, sem exigir que a sessao
  seja re-executada (US4, prioridade menor — candidata a fase de
  implementacao separada).
- **FR-011**: Quando a reconstrucao retroativa (FR-010) e acionada para uma
  execucao cujos dados de sessao originais ja nao existem mais em disco, o
  sistema MUST informar explicitamente que aquela execucao nao pode ser
  reconstruida, em vez de preencher a metrica com um valor estimado.

> Decisoes de infraestrutura: N/A alem do already-coberto por FR-008/FR-009
> (best-effort + nao-fabricacao) — a feature nao introduz scheduling,
> criptografia, refresh de token externo ou lock multi-pod novos; ela
> estende um mecanismo de captura best-effort que ja segue o mesmo padrao
> usado hoje para a metrica de tool_calls (fail-open, sidecar por onda,
> nunca bloqueia a orquestracao).

### Key Entities

- **Metrica de Uso de Spawn**: registro do consumo observado de um spawn de
  subagente concluido — tokens consumidos, contagem de tool-uses, duracao,
  e a associacao com a onda, a feature/projeto e o modelo roteado para
  aquele spawn. Pode ter campos individuais marcados como indisponiveis
  quando a fonte de dados subjacente nao permitiu captura-los (FR-009).
- **Consumo Agregado da Onda**: soma das Metricas de Uso de Spawn de todos
  os subagentes de uma mesma onda, exibida nos relatorios de execucao
  (FR-005).

## Success Criteria

### Measurable Outcomes

- **SC-001**: Para 100% dos spawns de subagente concluidos com sucesso
  dentro de uma onda orquestrada (quando a fonte de dados de uso estava
  disponivel), o relatorio da onda exibe tokens/tool-uses/duracao em vez de
  apenas uma contagem de tool_calls como proxy.
- **SC-002**: O operador consegue consultar retroativamente, para qualquer
  onda concluida, o consumo de tokens associado, sem precisar reabrir a
  sessao original de conversa.
- **SC-003**: Em uma auditoria de custo x modelo roteado, o operador
  consegue comparar, por onda, o modelo efetivamente roteado com o
  consumo de tokens observado, sem precisar fazer calculo manual fora do
  toolkit.
- **SC-004**: Quando o dado de uso nao esta disponivel para um spawn, 100%
  dos relatorios marcam a metrica daquele spawn explicitamente como
  indisponivel — nunca exibem um numero inventado ou um zero apresentado
  como valor real.
- **SC-005**: Para execucoes historicas cujos dados de sessao originais
  ainda existem em disco, o operador consegue reconstruir o consumo de
  tokens daquela execucao sem re-executar a pipeline de orquestracao.

## Assumptions & Dependencies

- **Fonte de dados verificada (evidencia observada nesta sessao,
  Constitution Principio VI)**: o transcript de sessao do Claude Code
  persistido em disco (`~/.claude/projects/<projeto-codificado>/<sessao>.jsonl`)
  contem, para cada retorno de spawn de subagente concluido, um registro
  de resultado da tool call com o total de tokens consumidos, a contagem
  total de tool-uses e a duracao total do spawn — confirmado pela
  correspondencia entre os valores desse registro (tokens=106664,
  tool-uses=38) e a contagem de tool-uses exibida ao operador ("38 tool
  uses") para a mesma onda de uma execucao real
  (`~/.claude/projects/-Users-jot-Projects--lab-Jot-financial-support/3695d350-2c3f-4356-aa3a-9e46918d9436.jsonl`).
  Adicionalmente, observou-se nesta propria sessao que o resultado da tool
  call de spawn devolvido ao orquestrador-pai ja carrega um resumo desses
  mesmos totais (tokens=68853, tool-uses=0, duracao=4698ms observados).
  Essas sao as duas fontes de dados sobre as quais esta feature assume
  que a captura e possivel — a spec nao prescreve qual das duas (ou ambas)
  sera usada; isso e decisao de `/plan`.
- **Risco em aberto — mecanismo exato de captura**: nao foi verificado
  ainda o payload exato que um hook de pos-execucao de tool call recebe no
  momento em que um spawn de subagente completa (qual identificador de
  tool chega, e se os totais de uso vem diretamente nesse payload ou
  exigem acesso ao arquivo de transcript por um caminho fornecido
  separadamente). Este e um risco tecnico a resolver na fase de pesquisa/
  plano — nao um requisito desta spec — e pode reduzir o conjunto de
  metricas capturaveis ao vivo (FR-001/FR-002) sem invalidar FR-010/FR-011
  (a reconstrucao retroativa le o transcript persistido diretamente, via
  caminho ja confirmado).
- **Nao contradiz decisao historica anterior sobre custo em tokens**: uma
  decisao registrada anteriormente no toolkit concluiu que "a harness nao
  expoe contabilidade de tokens a scripts/env" (checagem `env | grep -i
  token` vazia) e adotou `tool_calls` como proxy de custo. Essa conclusao
  permanece valida para o canal que foi testado (variaveis de ambiente
  disponiveis a scripts em execucao) — o canal que esta feature assume
  (dado persistido no transcript em disco e no resultado da tool call de
  spawn) e um canal diferente, nao testado por aquela decisao anterior.
- Esta feature nao especifica o schema de armazenamento nem o formato
  exato dos campos de captura — isso e decisao tecnica de `/plan`.
