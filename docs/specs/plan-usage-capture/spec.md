# Feature Specification: Captura de Uso do Plano via Statusline (Plan Usage Capture)

**Feature**: `plan-usage-capture`
**Created**: 2026-08-10
**Status**: Draft

## Clarifications

### Session 2026-08-10

- Q: Qual a tolerancia de dedupe do throttle FR-010 para `used_percentage`? → A: tolerancia de 2 casas decimais — duas capturas so sao consideradas identicas (e descartaveis pelo throttle) se `used_percentage` bater ate a 2a casa decimal; alem disso conta como mudanca real.
- Q: Qual a janela temporal do throttle FR-010 (ultimas N capturas ou so a ultima)? → A: sem janela temporal — o throttle compara sempre contra o ULTIMO registro persistido daquele escopo (`five_hour`/`seven_day`), nao uma janela de tempo.
- Q: Qual a dimensao do schema `plan_usage` — global (so a conta) ou com dimensao de projeto/sessao? → A: manter dimensao de projeto/sessao (`project`, `project_path`, `session_id`), como as demais tabelas do knowledge.db (ex.: `loose_usage`); o gauge continua sendo da CONTA, a dimensao registra apenas DE ONDE a captura veio.
- Q: Qual o formato de `captured_at`/`ingested_at`? → A: TEXT ISO 8601 (ex.: `2026-08-07T04:38:14Z`), alinhado a convencao de toda a knowledge.db — nunca epoch segundos. Distinto de `resets_at` (FR-003), que permanece epoch segundos por ser assim que a statusline emite esse campo especifico; `captured_at`/`ingested_at` sao carimbos proprios da ingestao do cstk, nao um campo repassado do payload.
- Q: A consulta de historico do FR-008 via CLI deve ter limite/janela padrao? → A: sim — reusar as flags ja existentes de `cstk usage` (`--limit N`, default 20; `--since ISO`), sem inventar convencao nova.

### Session 2026-08-10 (integracao pos-checklist, dec-029/dec-030)

- Q: Quando `rate_limits` esta AUSENTE do payload inteiro (sessao sem
  nenhuma resposta de API completada), o sistema insere uma linha `NULL`
  em `plan_usage` ou nao insere nada? → A: NAO insere linha (dec-029). A
  ausencia de linha E o proprio estado "nao medido". O objetivo "nunca 0"
  se cumpre na LEITURA (a CLI mostra "nao medido", nunca "0%"), nao
  escrevendo uma linha `NULL` a cada render antes da 1a resposta de API
  completar (o que tambem eliminaria o flooding da tabela e a
  indefinicao de comparacao NULL-vs-NULL no throttle de FR-010). Ressalva:
  a coluna `used_percentage`/`resets_at` continua NULLABLE — quando
  `rate_limits` ESTA presente mas um campo especifico vem ausente/nulo
  dentro de um escopo capturado (caso defensivo/malformado), a linha E
  inserida com `NULL` nesse campo, nunca `0`.
- Q: A feature deve incluir `.cost`/`.context_window` (e as colunas
  correlatas de custo/tokens de sessao do rascunho original do operador
  — `session_cost_usd`, `session_input_tokens`, `session_output_tokens`,
  `cache_read_input_tokens`, `cache_creation_input_tokens`, `model_id`)
  no escopo, alem de `rate_limits`? → A: NAO — corte confirmado
  (dec-030). `plan_usage` cobre exclusivamente o gauge de uso do plano
  (`rate_limits`); `.cost`/`.context_window` ficam fora de escopo,
  reservados para uma feature futura dedicada a custo/tokens de sessao.
  Consequencia formal: a regra "cost/context_window sao cumulativos da
  SESSAO — agregar com MAX, jamais SUM" fica **N/A para esta feature**,
  por ausencia de qualquer coluna cumulativa persistida por `plan_usage`.

## User Scenarios & Testing

### User Story 1 - Consultar o uso atual do plano sem credencial OAuth (Priority: P1)

Como operador do Claude Code, eu quero consultar quanto do meu limite de
plano (`/usage`) ja foi consumido nas janelas de 5 horas e 7 dias, usando o
`cstk`, sem precisar fornecer credencial OAuth, para saber o quao perto
estou de ser limitado antes de continuar trabalhando.

**Why this priority**: e a capacidade minima que entrega valor sozinha — sem
ela, o operador so descobre que bateu o limite quando o Claude Code ja
recusa a proxima resposta. A statusline e a unica via observada que expoe
esse dado sem OAuth.

**Independent Test**: com o comando de statusline configurado para
alimentar a captura, completar pelo menos uma resposta de API numa sessao e,
em seguida, consultar via CLI o percentual usado e o horario de reset das
janelas `five_hour` e `seven_day`, sem qualquer intervencao manual de
coleta.

**Acceptance Scenarios**:

1. **Given** uma sessao em que ao menos uma resposta de API completou,
   **When** o operador consulta o uso do plano via `cstk`, **Then** o
   sistema retorna o percentual usado e o horario de reset para `five_hour`
   e `seven_day` separadamente.
2. **Given** que a statusline nunca expos `seven_day_opus`,
   `seven_day_sonnet` ou dados de creditos (exigem OAuth), **When** o
   operador consulta o uso do plano, **Then** o sistema nao apresenta esses
   campos como se fossem dados capturados — apenas `five_hour` e
   `seven_day`.

---

### User Story 2 - Acompanhar a evolucao do uso do plano ao longo do tempo (Priority: P2)

Como operador que roda sessoes longas ou multiplas sessoes no mesmo dia, eu
quero ver como o uso do plano evoluiu ao longo de uma janela (5h ou 7d), e
nao apenas o ultimo valor, para conseguir antecipar quando vou atingir o
limite e ajustar meu ritmo de trabalho.

**Why this priority**: um unico valor pontual (Story 1) ja tem valor, mas
nao revela tendencia — sem historico, o operador nao sabe se esta
consumindo rapido ou devagar dentro da janela. Depende da captura basica da
Story 1 existir, mas e verificavel isoladamente a partir de duas ou mais
capturas.

**Independent Test**: acumular pelo menos duas capturas de uso do plano
(por exemplo, em dois momentos distintos de uma mesma sessao ou em sessoes
diferentes) e verificar que o historico consultado via CLI mostra as
capturas em ordem cronologica, cada uma com seu percentual e timestamp.

**Acceptance Scenarios**:

1. **Given** duas ou mais capturas de uso do plano registradas para a
   janela `five_hour`, **When** o operador consulta o historico dessa
   janela, **Then** o sistema apresenta as capturas em ordem cronologica com
   percentual usado e timestamp de cada uma.
2. **Given** capturas registradas tanto para `five_hour` quanto para
   `seven_day`, **When** o operador consulta o historico, **Then** as duas
   janelas sao apresentadas como series distintas, sem mistura de escopo.

---

### User Story 3 - Nunca confundir "nao medido" com "zero" (Priority: P3)

Como operador que confia nos numeros que o `cstk` reporta, eu quero que uma
sessao sem nenhuma resposta de API completada apareca como "uso nao
disponivel para esta captura", e nunca como "0% usado", para nao tomar
decisoes com base num dado fabricado que parece zero de verdade.

**Why this priority**: um "0%" fabricado e pior que nenhum dado — sugere
folga de limite que pode nao existir. Refinamento de integridade sobre as
Stories 1 e 2, testavel isoladamente simulando a ausencia do campo
`rate_limits` no payload.

**Independent Test**: apresentar ao mecanismo de captura um payload de
statusline em que a chave `rate_limits` esta ausente (sessao aberta e
fechada sem nenhuma resposta de API) e verificar que a captura resultante
NAO grava linha nova em `plan_usage` (dec-029) e que a consulta
subsequente via CLI reporta "nao medido", nunca o valor `0`.

**Acceptance Scenarios**:

1. **Given** um payload de statusline sem a chave `rate_limits`, **When** a
   captura processa esse payload, **Then** nenhuma linha nova e inserida em
   `plan_usage` para aquela captura (dec-029) — a ausencia de linha e o
   estado "nao medido", nunca uma linha com valor zero fabricado.
2. **Given** um banco onde nenhuma captura de um escopo existe ainda
   (nenhuma resposta de API completou em nenhuma sessao), **When** o
   operador consulta o uso do plano via CLI, **Then** o sistema apresenta
   esse escopo como "nao medido" explicito, distinto de qualquer `0%` real
   que venha a existir no futuro.

---

### Edge Cases

- O que acontece quando a chave `rate_limits` esta ausente do payload
  (sessao sem nenhuma resposta de API completada)? O sistema MUST NOT
  inserir linha em `plan_usage` para aquela captura — a ausencia de linha
  E o estado "nao medido" (dec-029). Na leitura (FR-007/FR-008), esse
  estado MUST ser apresentado como "nao medido", nunca como `0`
  (Constitution VI; ver Story 3). Ressalva: quando `rate_limits` estiver
  presente mas um campo especifico (`used_percentage` ou `resets_at`)
  vier ausente dentro de um escopo capturado, o sistema MUST persistir
  `NULL` explicito somente para aquele campo — a coluna permanece
  NULLABLE para esse caso defensivo.
- Como o sistema trata `resets_at`, que chega como numero em epoch segundos
  na statusline mesmo o contrato do endpoint `/api/oauth/usage` declarando
  `string|null`? O sistema MUST tratar `resets_at` como epoch em segundos
  na via da statusline, sem reinterpretar como string ISO — a fonte de
  verdade e o payload observado, nao o contrato do endpoint que a feature
  nao consome.
- Como o sistema trata o ruido de float em `used_percentage` (ex.:
  `7.000000000000001`)? O sistema MUST persistir o valor como veio, sem
  arredondar na ingestao — arredondamento e, se necessario, responsabilidade
  exclusiva da camada de apresentacao.
- O que acontece se a statusline renderizar o mesmo gauge repetidas vezes
  em sucessao rapida (comportamento orientado a evento, nao a polling)? O
  sistema MUST evitar persistir capturas redundantes identicas em sucessao
  imediata (throttle), para nao inflar o historico com ruido sem
  informacao nova.
- Como testar esta feature, dado que a statusline nao dispara em `claude
  -p`? O teste automatizado MUST alimentar a via de ingestao com um payload
  fixture apresentado via stdin, nunca depender de uma sessao interativa
  real.
- O que acontece com campos que existem apenas na resposta de `GET
  /api/oauth/usage` (`seven_day_opus`, `seven_day_sonnet`, creditos/
  `extra_usage`)? Estao fora de escopo desta feature — o sistema MUST NOT
  tentar captura-los a partir da statusline, que nunca os emite.
- O que acontece quando o operador ja tem uma statusline customizada
  configurada (`statusLine.command` no `settings.json` do harness)? Como
  essa chave e UNICA, instalar esta feature sem cuidado sobrescreveria a
  customizacao existente. O sistema MUST preservar a customizacao previa
  via pass-through: quando a variavel de ambiente
  `CSTK_STATUSLINE_INNER_COMMAND` estiver definida, `statusline-plan-usage.sh`
  MUST reencaminhar o payload original (stdin, sem modificacao) para o
  comando nela referenciado e repassar o stdout dele verbatim, capturando
  o uso do plano como efeito colateral best-effort — nunca substituindo o
  texto renderizado pela statusline customizada do operador.

## Requirements

### Functional Requirements

- **FR-001**: O sistema MUST ingerir o payload JSON recebido via stdin do
  comando de statusline e extrair `rate_limits.five_hour` e
  `rate_limits.seven_day` quando presentes.
- **FR-002**: Quando a chave `rate_limits` estiver ausente do payload
  (sessao sem nenhuma resposta de API completada), o sistema MUST NOT
  inserir linha em `plan_usage` para aquela captura — a ausencia de linha
  E o estado "nao medido" (dec-029); o sistema MUST NUNCA fabricar `0` nem
  inserir uma linha `NULL` como substituta. Quando `rate_limits` estiver
  presente mas `used_percentage` ou `resets_at` vier ausente/nulo dentro
  de um escopo capturado (caso defensivo/malformado), o sistema MUST
  persistir `NULL` explicito somente para o campo faltante (a coluna
  permanece NULLABLE para esse caso), nunca `0`.
- **FR-003**: O sistema MUST persistir `resets_at` como epoch em segundos
  (numero), sem reinterpretar ou converter como string ISO.
- **FR-004**: O sistema MUST persistir `used_percentage` como valor real
  (ponto flutuante), exatamente como reportado pela statusline, sem
  arredondar na ingestao.
- **FR-005**: O sistema MUST tratar `five_hour` e `seven_day` como escopos/
  series distintos, nunca mesclando ou derivando um a partir do outro.
- **FR-006**: O sistema MUST restringir a captura aos campos `five_hour` e
  `seven_day` emitidos pela statusline; MUST NOT tentar capturar
  `seven_day_opus`, `seven_day_sonnet` ou dados de creditos
  (`extra_usage`), que exigem credencial OAuth e estao fora de escopo.
  MUST NOT tambem capturar os demais campos do payload que a statusline
  emite mas que nao pertencem ao gauge `rate_limits`: `.model`, `.cost`,
  `.context_window`, `.exceeds_200k_tokens`, `.thinking`, `.effort`,
  `.output_style`, `.version` (ver `contracts/statusline-hook.md`
  §Contrato de entrada, "Campos NAO consumidos por esta feature").
- **FR-007**: Usuarios MUST ser capazes de consultar, via CLI `cstk`, a
  captura mais recente conhecida do uso do plano (percentual usado +
  horario de reset) para `five_hour` e `seven_day`. Quando nao houver
  nenhuma captura conhecida para um escopo (nenhuma linha em `plan_usage`
  para ele, porque `rate_limits` nunca esteve presente numa resposta de
  API completada), o sistema MUST apresentar esse escopo como "nao
  medido" explicito, nunca como `0%` (Constitution VI; dec-029).
- **FR-008**: Usuarios MUST ser capazes de consultar o historico de
  capturas de uso do plano ao longo do tempo (nao apenas a mais recente),
  em ordem cronologica, por escopo. A consulta MUST reusar as flags ja
  existentes de `cstk usage` (`--limit N`, default 20; `--since ISO`) para
  limitar/janelar o resultado — sem introduzir uma convencao nova de
  paginacao para esta feature.
- **FR-009**: O sistema MUST persistir cada captura numa tabela dedicada
  (`plan_usage`) no repositorio de conhecimento local (mesmo indice ja
  usado por outras features de uso, ex.: `cstk recall`), com o
  correspondente bump de versao de schema e migracao. A tabela MUST manter
  dimensao de projeto/sessao (`project`, `project_path`, `session_id`),
  na mesma convencao das demais tabelas do knowledge.db (ex.:
  `loose_usage`) — o gauge medido continua sendo o da CONTA (nao do
  projeto/sessao); a dimensao registra apenas a proveniencia da captura.
- **FR-010**: O sistema MUST evitar persistir capturas redundantes
  identicas (mesmo escopo, mesmo percentual, mesmo horario de reset) em
  sucessao imediata, dado que a statusline renderiza por evento e nao por
  polling controlado. O throttle MUST comparar cada nova captura apenas
  contra o ULTIMO registro persistido daquele escopo (`five_hour` ou
  `seven_day`), sem janela temporal; duas capturas do mesmo escopo sao
  consideradas identicas (e portanto descartadas) somente quando
  `used_percentage` bate ate a 2a casa decimal e `resets_at` e igual —
  qualquer diferenca alem da 2a casa decimal conta como mudanca real e
  MUST ser persistida.
- **FR-014**: O sistema MUST persistir `captured_at` (carimbo de quando a
  captura foi processada) e `ingested_at` (carimbo de ingestao no
  knowledge.db) como TEXT em formato ISO 8601 (ex.:
  `2026-08-07T04:38:14Z`), na mesma convencao usada pelas demais tabelas
  do knowledge.db — nunca como epoch. Isto e distinto de `resets_at`
  (FR-003), que permanece epoch em segundos por ser o formato em que a
  propria statusline emite esse campo.
- **FR-011**: O sistema MUST permanecer 100% local — nenhuma captura de uso
  do plano e transmitida para fora do ambiente do operador (Principio IV da
  constitution do projeto).
- **FR-012**: A suite de teste automatizado desta feature MUST validar o
  comportamento de ingestao usando um payload fixture apresentado via
  stdin, nunca dependendo de uma sessao interativa real (a statusline nao
  dispara em modo nao-interativo).
- **FR-015**: A captura MUST ser fail-open/best-effort em qualquer cenario
  de degradacao — `jq` ausente, `sqlite3` ausente, `knowledge.db`
  inacessivel (sem permissao de escrita), ou payload JSON malformado. Em
  TODOS esses cenarios o sistema MUST: (a) pular a captura silenciosamente
  (sem inserir linha em `plan_usage`); (b) imprimir em stdout o texto de
  fallback/pass-through normal da statusline, exatamente como se a captura
  nao existisse; (c) sair sempre com exit code `0`. O sistema MUST NUNCA
  imprimir erro de diagnostico da captura em stdout (contaminaria a UI
  renderizada) nem atrasar perceptivelmente a renderizacao — erros, se
  logados, vao para stderr ou sao descartados silenciosamente (mesma
  disciplina fail-open de `posttooluse-loose-usage.sh`).
> **FR-013-INFRA-SCHED**: a cadencia de captura e determinada por eventos
> do harness (o comando de statusline e invocado a cada render de UI, nao
> por um agendador externo tipo cron); o throttle mencionado em FR-010 e
> responsabilidade do proprio mecanismo de ingestao, nao de um scheduler
> separado. Demais itens do checklist (rotacao de chave, refresh de token
> externo, mutex multi-pod, backup) N/A — a feature nao persiste segredos,
> nao depende de token externo com TTL, e cada captura e um processo local
> de vida curta (o comando de statusline) sem estado compartilhado entre
> replicas.

### Key Entities

- **Captura de Uso do Plano (Plan Usage Snapshot)**: um registro pontual do
  gauge de uso da conta para um escopo de janela (`five_hour` ou
  `seven_day`), com percentual usado (ou ausencia explicita) e horario de
  reset (epoch segundos, ou ausencia explicita), capturado a partir de um
  render do comando de statusline. Persistido na tabela dedicada
  `plan_usage` do repositorio de conhecimento local, com dimensao de
  proveniencia (`project`, `project_path`, `session_id`) na mesma
  convencao das demais tabelas do knowledge.db — o gauge medido e sempre
  da CONTA, a dimensao so registra a origem da captura. Carrega dois
  carimbos de tempo proprios da ingestao, `captured_at` e `ingested_at`,
  ambos TEXT em formato ISO 8601 — distintos de `resets_at`, que
  permanece epoch em segundos por ser o formato emitido pela statusline.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Apos pelo menos uma resposta de API completar numa sessao com
  a captura configurada, o operador consegue consultar via CLI o percentual
  mais recente de uso do plano para `five_hour` e `seven_day`, sem fornecer
  nenhuma credencial OAuth.
- **SC-002**: Para 100% das capturas em que `rate_limits` esta ausente do
  payload, nenhuma linha e inserida em `plan_usage` (dec-029) — e para
  100% das consultas em que nao ha captura conhecida de um escopo, a
  leitura via CLI reporta "nao medido", nunca `0%` nem um dado fabricado.
- **SC-003**: A partir de pelo menos duas capturas consecutivas na mesma
  janela, o operador consegue visualizar a evolucao do uso do plano ao
  longo do tempo sem cruzar dados manualmente de fontes separadas.
- **SC-004**: 100% dos horarios de reset persistidos sao interpretaveis
  diretamente como epoch em segundos, sem erro de parsing por presumir
  formato string.
- **SC-005**: Nenhuma captura de uso do plano desta feature e transmitida
  para fora do ambiente local do operador — verificavel pela ausencia de
  qualquer chamada de rede na via de ingestao.

## Delta Requirements

**Skip**: feature adiciona uma capacidade inteiramente nova (captura de
gauge de limite do plano via statusline); nao ha nenhuma capability
documentada em `docs/specs/current/` referente a captura de uso do plano ou
`rate_limits` a ser alterada, removida ou renomeada — o corpus canonico
atual cobre apenas atomic-commit-staging, guards e gates de delta/spec, sem
sobreposicao com este escopo — agente-00c-feature-orchestrator, 2026-08-10
