# Feature Specification: agente-00c model-routing

**Feature**: `agente-00c-model-routing`
**Created**: 2026-05-22
**Status**: Draft (clarified) — **FR-017 SUPERSEDIDO** (ver banner abaixo)
**Parent feature**: [model-selector](../model-selector/spec.md) (skill standalone, concluida) — esta feature completa a entrega ao integrar a skill aos orquestradores.

> **⚠️ SUPERSESSÃO (2026-05-24, feature `model-routing-por-onda` v4.0.0 — BREAKING)**
>
> A cláusula **FR-017 audit-only** desta spec foi **REVOGADA**. A premissa
> de que "o harness não aceita `model` como parâmetro de spawn" está
> **obsoleta** — o harness atual aceita `model` no spawn de subagente (com
> precedência sobre o frontmatter). O model-routing **deixou de ser
> auditoria pura**: o modelo agora É APLICADO, por onda (mecanismo primário
> via mapa fase→modelo) e no spawn de `clarify-asker`/`clarify-answerer`. A
> Decisão auditável permanece, mas como rastro da APLICAÇÃO, não como
> substituto dela. O `model-selector` passa a ser camada de REFINO (suggest
> sobre o mapa), e o operador pode dar override via Decisão manual pré-onda.
> Detalhes em [`../../model-routing-por-onda/spec.md`](../../model-routing-por-onda/spec.md)
> (FR-017 da nova feature). Esta spec arquivada permanece como registro
> histórico do contrato anterior.

## Clarifications

### Session 2026-05-22 (onda-002)

Resolvidos via padrao feature-00c-clarify-asker + feature-00c-clarify-answerer (5 perguntas, 5 respostas score >=2, 0 bloqueios humanos). Decisoes auditaveis: dec-002 (batch asker) + dec-003..dec-007 (respostas answerer).

- **Q1 (FR-005, dec-003)**: Mapeamento de score 0..2 (skill) → 0..3 (runtime) e exatamente `0→0, 1→2, 2→3`. Score=2 da skill exige >=2 sinais matched, e FR-006 ja exige citacao literal dos sinais — esses sinais SAO a `--evidencia >=20 chars` requerida pela trava de score=3 do `state-decisions.sh`.
- **Q2 (FR-012, dec-004)**: Idempotencia em retomadas usa **busca em `.decisoes[]` por `(contexto matchando "Selecao de modelo para subagente <subagent_type>") AND (onda_id == onda_corrente)`**. Source-of-truth unica; nao adicionar campo novo em `.ondas[N]` (Principio III preserva formato canonico).
- **Q3 (FR-015, dec-005)**: Granularidade e **1 invocacao por spawn**. Perfis distintos asker (enumerativo) vs answerer (reflexivo) produzem sinais diferentes na skill — sugestao compartilhada quebraria Principio V.
- **Q4 (FR-018, dec-006)**: Agregacao para review-task usa **derivacao real-time de `.decisoes[]` via jq** — coerente com Q2. Volume tipico <100 decisoes/feature torna performance nao-issue.
- **Q5 (FR-013, dec-007)**: Truncagem usa **2000 chars iniciais + marcador literal `...[truncated]...` + 2000 chars finais** (total 4016, margem para UTF-8 multi-byte). Preserva extremos semanticos (perfil + saida esperada).

## Contexto

A skill `model-selector` foi entregue em uma feature anterior e vive em
`global/skills/model-selector/`. Ela classifica uma tarefa textual em
faixa de complexidade (rasa / media / profunda) e sugere um rotulo
abstrato de modelo (`haiku` / `sonnet` / `opus` / `manter-atual`) +
score 0..2 + alternativa de fallback, com contrato explicito de
"suggest-only, never silent switch".

Validacao empirica em 2026-05-22:
`grep -rln "model-selector" global/` retorna APENAS arquivos dentro de
`global/skills/model-selector/`. Os orquestradores autonomos
`agente-00c` e `feature-00c` (e seus subagentes asker/answerer) nunca
invocam a skill. Logo, toda decisao de modelo para subagentes hoje e
implicita / herdada do harness — sem rastro auditavel, sem
deterministica baseada na natureza da tarefa.

Esta feature fecha o gap fazendo os orquestradores consultarem a skill
nos pontos de delegacao via tool Agent (atualmente: fase clarify, com
spawn de asker e answerer) e registrarem a sugestao como Decisao
auditavel + entrada no audit trail da onda.

## User Scenarios & Testing

### User Story 1 — Rastro auditavel de selecao de modelo por subagente (Priority: P1)

Como operador rodando `agente-00c` ou `feature-00c` em um projeto, eu
quero que cada ponto de delegacao a subagente registre auditavelmente
qual modelo foi sugerido para a tarefa daquele subagente e quais
sinais textuais motivaram a sugestao, para que eu possa revisar
qualidade e custo apos a execucao sem reabrir o pipeline.

**Why this priority**: e o motivo central da feature. Sem essa
auditabilidade, todas as outras stories sao adornos. Habilita US-3
diretamente (auditor consome o rastro) e gera os dados para qualquer
analise de custo/qualidade futura.

**Independent Test**: rodar uma execucao agente-00c ou feature-00c
ate fim de fase clarify; abrir `state.json` e confirmar que existe ao
menos uma Decisao com `contexto` matchando o padrao
`Selecao de modelo para subagente <subagent_type>` e ao menos um
registro em `.ondas[N].skills_invoked` com `skill = "model-selector"`
ligado por `decisao_id`. A US-1 considera-se satisfeita mesmo sem US-2
ou US-3.

**Acceptance Scenarios**:

1. **Given** o orquestrador-00c em fase clarify pronto para spawnar
   `agente-00c-clarify-asker`, **When** o orquestrador completa a
   sequencia de pre-spawn, **Then** o `state.json` contem uma Decisao
   nova cujo `contexto` referencia o subagente `clarify-asker` e cuja
   `escolha` e um dos rotulos validos (`haiku`/`sonnet`/`opus`/
   `manter-atual`/`fallback-default`) e ha uma entrada em
   `.ondas[N].skills_invoked` apontando para essa Decisao.
2. **Given** o feature-orchestrator em fase clarify pronto para
   spawnar `feature-00c-clarify-answerer` na sequencia (apos o asker),
   **When** o orquestrador completa a sequencia de pre-spawn do
   answerer, **Then** existe uma Decisao separada para o
   `clarify-answerer` (alem da do asker), com seus proprios sinais e
   escolha.
3. **Given** um operador inspecionando `state.json` apos a fase, **When**
   ele aplica `jq '.decisoes[] | select(.contexto | test("Selecao de
   modelo"))'`, **Then** ele recupera todas as decisoes de selecao em
   ordem cronologica, cada uma com `agente`, `etapa`, `opcoes`,
   `escolha`, `justificativa`, `score`, `timestamp` preenchidos.

---

### User Story 2 — Graceful degradation se model-selector ausente ou falha (Priority: P1)

Como mantenedor do toolkit, eu quero que a integracao continue
funcional mesmo quando `model-selector` esta desinstalada, com
contrato I/O quebrado, ou retorna exit nao-zero, para que a integracao
nao crie nova dependencia obrigatoria capaz de quebrar execucoes
existentes.

**Why this priority**: tambem P1 porque uma quebra de regressao no
spawn de subagentes derruba todo o pipeline clarify. Principio II da
constitution exige fallback gracioso para deps opcionais.

**Independent Test**: simular ausencia da skill (renomear
`global/skills/model-selector/` temporariamente ou injetar exit 127),
rodar o orquestrador ate fim de fase clarify, e confirmar que: (a) o
spawn de asker/answerer ocorreu normalmente; (b) existe Decisao
registrada com escolha = `fallback-default` e justificativa
referenciando a falha; (c) nenhum bloqueio humano foi aberto por causa
disso; (d) exit-code do orquestrador permanece 0.

**Acceptance Scenarios**:

1. **Given** `model-selector` ausente do disco, **When** o orquestrador
   chega ao pre-spawn de clarify-asker, **Then** o orquestrador
   registra Decisao com `escolha = "fallback-default"`, `justificativa`
   contendo o motivo da falha (ex: `Skill not found`), e prossegue
   para spawn do asker sem erro.
2. **Given** `model-selector` presente mas retornando output mal-formado
   (ex: stdout vazio ou faltando secao `## Sugestao`), **When** o
   orquestrador processa a saida, **Then** mesma Decisao
   `fallback-default` e registrada (justificativa cita parse-failure)
   e o spawn segue.
3. **Given** a tool Skill indisponivel no harness (caso hipotetico
   raro), **When** o orquestrador tenta invocar `model-selector`,
   **Then** o mesmo padrao fallback se aplica — pipeline nao trava.

---

### User Story 3 — Relatorio agregado de selecao de modelo via review-task (Priority: P2)

Como auditor pos-execucao consumindo `review-task` em uma feature
executada apos a integracao, eu quero ver um agregado das selecoes
de modelo da feature (por fase e por subagente), incluindo
distribuicao dos rotulos sugeridos e contagem de fallbacks, para
identificar padroes de tarefa que demandam revisao da heuristica.

**Why this priority**: P2 — agrega valor real para o ciclo de
melhoria, mas nao impede a feature de ser util. US-1 + US-2 entregam
MVP; US-3 entrega o "loop fechado" de feedback.

**Independent Test**: apos US-1 produzir Decisoes e skills_invoked,
invocar `review-task` na feature e confirmar que o relatorio contem
uma secao agregando os rotulos de modelo escolhidos por subagente +
contagem de fallbacks. A US-3 pode ser implementada via consulta
direta a `state.json` (sem novo campo) ou via campo dedicado — a
escolha pertence ao plan.

**Acceptance Scenarios**:

1. **Given** uma feature executada com 2 ondas de clarify (asker +
   answerer em cada onda = 4 selecoes de modelo), **When** o auditor
   roda `review-task` nessa feature, **Then** o relatorio contem
   secao com 4 selecoes detalhadas (subagente, etapa, modelo
   sugerido, score, fallback-flag).
2. **Given** uma feature na qual `model-selector` falhou 1 vez em 4
   spawns, **When** o auditor le o relatorio, **Then** existe contagem
   explicita `fallback-default: 1/4 (25%)`.

---

### Edge Cases

- **Spawn em depth maxima**: o orquestrador detectou via
  `spawn-tracker.sh check` que esta no nivel maximo de subagente
  (depth=3) e ABORTA antes de spawnar. A invocacao do model-selector
  deve acontecer ANTES desse check? Resposta esperada: invocar APOS o
  spawn-tracker confirmar viabilidade — gasto inutil se vamos abortar.
  Vai virar FR explicito.
- **Score 0 retornado pelo answerer ao final da fase**: a Decisao de
  selecao de modelo nao deve disparar `pause-humano` por si propria —
  ela e sempre Decisao "tecnica" do orquestrador, nao mediada por
  answerer. A escala de score do model-selector (0..2) e MAPEADA para
  a escala do runtime (0..3) por uma funcao explicita; score 0 da skill
  vira score 0 do runtime sem disparar bloqueio.
- **Retomada via `/agente-00c-resume` ou `/feature-00c-resume` no meio
  da fase clarify**: o estado retomado ja contem as Decisoes registradas
  ate ali; o orquestrador NAO deve reinvocar `model-selector` para
  spawns ja realizados (deduplicacao por subagente + onda).
- **Mesma onda spawna asker, recebe `perguntas: []`, NAO spawna
  answerer**: a Decisao de selecao para o answerer NAO deve ser
  registrada (nao houve spawn). Invariante: 1 Decisao por spawn real,
  nao por spawn potencial.
- **Multiplas retomadas dentro da mesma fase**: garantir idempotencia
  — uma retomada nao adiciona Decisoes duplicadas para o mesmo
  subagente da mesma onda.
- **Input do model-selector excede 4096 chars** (limite documentado
  no contrato I/O da skill): orquestrador DEVE truncar o input antes de
  invocar, com aviso na justificativa da Decisao.

## Requirements

### Functional Requirements

- **FR-001**: Os orquestradores `agente-00c-orchestrator` e
  `agente-00c-feature-orchestrator` MUST invocar a skill
  `model-selector` antes de cada spawn de subagente via tool Agent,
  passando como input textual uma descricao da tarefa do subagente
  (perfil + entradas esperadas + saida esperada).
- **FR-002**: O input textual passado ao `model-selector` MUST ser
  determinado por um template por `subagent_type` (ex: template
  distinto para `clarify-asker` vs `clarify-answerer`), garantindo
  classificacao consistente entre invocacoes para o mesmo tipo de
  subagente.
- **FR-003**: O orquestrador MUST registrar a sugestao do
  `model-selector` como Decisao auditavel via
  `state-decisions.sh register` com os 5 campos obrigatorios
  (`contexto`, `opcoes`, `escolha`, `justificativa`, `score`) + agente
  + etapa, antes de prosseguir com o spawn.
- **FR-004**: O orquestrador MUST chamar
  `state-ondas.sh record-skill --skill model-selector --decisao-id
  <dec-NNN>` apos registrar a Decisao, criando audit trail consumivel
  por `review-task`.
- **FR-005**: A escala de score do `model-selector` (0..2) MUST ser
  mapeada para a escala de score do runtime (0..3) pela funcao
  deterministica `map(s) = {0→0, 1→2, 2→3}` (resolvido em clarify,
  dec-003). Score=2 da skill exige >=2 sinais matched (vide
  `classify.sh` linha 401), e FR-006 ja exige citacao literal desses
  sinais na justificativa — esses sinais constituem a `--evidencia
  >=20 chars` requerida pela trava de score=3 em `state-decisions.sh`
  (linhas 187-192). Score=0 da skill mapeia para 0 do runtime mas NAO
  dispara bloqueio (vide FR-009).
- **FR-006**: A `justificativa` da Decisao MUST citar literalmente os
  sinais detectados pelo `model-selector` (extraidos da secao
  `## Sinais detectados` do markdown de saida), preservando
  rastreabilidade fim-a-fim do "por que esse modelo".
- **FR-007**: A `escolha` da Decisao MUST ser exatamente o rotulo
  retornado pelo `model-selector` (`haiku` / `sonnet` / `opus` /
  `manter-atual`), exceto no caso de fallback (ver FR-008).
- **FR-008**: Se `model-selector` retornar `exit != 0`, output
  mal-formado (faltando secao `## Sugestao` ou campo `modelo`), ou
  estiver ausente do disco, o orquestrador MUST registrar Decisao com
  `escolha = "fallback-default"`, `score = 0`, `justificativa` citando
  o motivo da falha + caracteres iniciais do stderr (ate 200 chars),
  e PROSSEGUIR com o spawn sem bloquear.
- **FR-009**: O fallback de FR-008 MUST NAO abrir bloqueio humano,
  MUST NAO interromper a onda, e MUST NAO contar como ciclo perdido
  para os detectores `cycles.sh` / `circular.sh`.
- **FR-010**: O orquestrador MUST aplicar a invocacao do
  `model-selector` APOS o `spawn-tracker.sh check` confirmar
  viabilidade do spawn (depth disponivel) — invocacao em depth
  esgotada e desperdicio.
- **FR-011**: A invocacao do `model-selector` MUST acontecer ANTES do
  `spawn-tracker.sh enter` (que incrementa o contador), garantindo que
  o Bash da skill rode no nivel do orquestrador, nao no nivel do
  subagente prestes a nascer.
- **FR-012**: O orquestrador MUST garantir idempotencia em retomadas:
  uma Decisao de selecao de modelo ja registrada para o par
  (`subagent_type`, `onda_id`) NAO deve ser duplicada caso o
  orquestrador seja retomado e re-execute o caminho de pre-spawn.
  Mecanismo (resolvido em clarify, dec-004): busca em `.decisoes[]`
  por `(contexto matchando "Selecao de modelo para subagente
  <subagent_type>") AND (onda_id == onda_corrente)` via `jq` POSIX.
  Source-of-truth unica em `.decisoes[]`; NAO adicionar marcador novo
  em `.ondas[N]` (preserva Principio III — formato canonico do
  state-schema).
- **FR-013**: Se o input ao `model-selector` exceder 4096 chars, o
  orquestrador MUST truncar para 4016 chars usando o esquema
  deterministico (resolvido em clarify, dec-007): **2000 chars
  iniciais + marcador literal `...[truncated]...` (16 chars) + 2000
  chars finais**. Margem dentro de 4096 absorve overhead de UTF-8
  multi-byte. Preserva extremos semanticos (perfil + saida esperada).
  A `justificativa` da Decisao MUST mencionar a truncagem explicitamente.
- **FR-014**: O orquestrador MUST suportar a integracao mesmo quando a
  feature de cache de artefatos (`agente-00c-artifact-cache`) esta
  ativa — a invocacao do `model-selector` nao depende de cache, ela
  classifica a tarefa do subagente, nao o briefing/constitution.
- **FR-015**: Os DOIS spawns da fase clarify (asker, depois answerer)
  MUST gerar Decisoes SEPARADAS de selecao de modelo, pois os perfis
  das tarefas sao distintos (asker = enumerativo / determinismo
  estrutural; answerer = reflexivo / reconciliacao com constitution).
  Granularidade confirmada (resolvido em clarify, dec-005): **1
  invocacao do `model-selector` por spawn**, nao por fase.
  Compartilhar a sugestao forcaria mesma faixa para tarefas
  heterogeneas — viola Principio V (profundidade sobre adocao).
- **FR-016**: A documentacao dos orquestradores
  (`global/agents/agente-00c-orchestrator.md` e
  `global/agents/agente-00c-feature-orchestrator.md`) MUST ser
  atualizada para descrever a sequencia de pre-spawn (`spawn-tracker
  check` → `model-selector invoke` → `register Decisao` →
  `record-skill` → `spawn-tracker enter` → tool Agent).
- **FR-017** ~~(audit-only)~~ **[REVOGADO em v4.0.0 — ver banner no topo]**:
  ~~A escolha registrada na Decisao MUST permanecer SUGESTAO — o
  orquestrador NAO MUST passar hint de modelo automatico para a tool
  Agent (preserva contrato "suggest-only" da skill). Aplicacao
  automatica fica fora do escopo desta feature.~~ A feature
  `model-routing-por-onda` revogou esta cláusula: o modelo agora É
  aplicado (por onda e no spawn de clarify), porque a premissa "harness
  não aceita model no spawn" ficou obsoleta. O `model-selector` vira
  camada de refino sobre o mapa fase→modelo; o operador pode override
  via Decisão manual pré-onda.
- **FR-018**: `review-task` MUST conseguir agregar as Decisoes de
  `Selecao de modelo` por `subagent_type` e por `etapa`, produzindo
  pelo menos: (a) contagem por rotulo (`haiku` / `sonnet` / `opus` /
  `manter-atual` / `fallback-default`); (b) percentual de fallbacks.
  Mecanismo (resolvido em clarify, dec-006): **derivacao real-time de
  `.decisoes[]` via `jq`** no momento da invocacao do `review-task`.
  Query base: `jq '.decisoes[] | select(.contexto | test("^Selecao
  de modelo para subagente "))' state.json`. Sem novo campo agregado
  em `.ondas[N]` — source-of-truth unica em `.decisoes[]` elimina
  risco de drift apos edicao manual em pos-mortem.
- **FR-019**: A integracao MUST permanecer POSIX puro nos scripts
  envolvidos: nenhum bash-ism nem dependencia de `jq` adicional alem
  das ja exigidas pelo `agente-00c-runtime`. Helpers novos (se
  necessarios) DEVEM seguir o padrao dos scripts existentes em
  `~/.claude/skills/agente-00c-runtime/scripts/`.
- **FR-020**: A integracao MUST NAO emitir qualquer telemetria remota
  (Principio IV) — todo registro vive em `state.json` local.

### Decisoes de Infraestrutura Auditaveis

| Tipo de decisao | FR correspondente | Status |
|-----------------|-------------------|--------|
| Politica de scheduling | N/A | Feature nao adiciona scheduler novo; herda do orquestrador host |
| Politica de key rotation | N/A | Feature nao criptografa dados |
| Refresh policy | N/A | Feature nao consome token externo |
| Mutex multi-pod | N/A | Orquestrador ja serializa via `state-lock.sh` |
| Backup / restore | N/A | Decisoes ja entram no backup do `state.json` existente |
| Idempotencia | FR-012 | Resolvida em clarify (dec-004): busca em `.decisoes[]` por (contexto + onda_id) |
| Mapeamento de score | FR-005 | Resolvida em clarify (dec-003): `0→0, 1→2, 2→3` |
| Granularidade de spawn | FR-015 | Resolvida em clarify (dec-005): 1 invocacao por spawn |
| Agregacao para review-task | FR-018 | Resolvida em clarify (dec-006): derivacao real-time via `jq` sobre `.decisoes[]` |
| Truncagem de input | FR-013 | Resolvida em clarify (dec-007): 2000 inicio + `...[truncated]...` + 2000 fim |

### Key Entities

- **Decisao de selecao de modelo**: registro persistido em
  `state.json` (vertical `.decisoes[]`) com `agente` =
  `<orquestrador>`, `etapa` = `<fase corrente>`, `contexto` =
  `Selecao de modelo para subagente <subagent_type>` (formato fixo
  para grepabilidade), `opcoes` = rotulos validos retornados pela
  skill, `escolha` = rotulo escolhido (ou `fallback-default`),
  `justificativa` = sinais detectados literais + observacoes,
  `score` = inteiro 0..3 (mapeado de 0..2), `timestamp` = ISO-8601.
- **Registro de skill invocada**: entrada em
  `.ondas[N].skills_invoked[]` com `skill = "model-selector"`,
  `decisao_id = <dec-NNN>`, `timestamp`. Audit trail consumivel pelo
  `review-task`.
- **Template de input por subagent_type**: catalogo deterministico
  (em arquivo de referencia da skill ou inline na documentacao dos
  agents) que mapeia `subagent_type` → string textual de tarefa
  passada ao `model-selector`. Garante FR-002.

## Constitution Alignment

- **Principio I (SDD recursivo)**: esta feature segue o pipeline
  completo (spec → clarify → plan → checklist → create-tasks →
  execute-task → review-task). Todos os 3 marcadores de ambiguidade
  declarados na onda-001 + 4 DIAs originais foram resolvidos em
  clarify (onda-002, dec-003..dec-007). Esta spec, plan, tasks ficarao em
  `docs/specs/agente-00c-model-routing/`.
- **Principio II (POSIX puro)**: FR-019 + FR-020 reforcam. Qualquer
  helper novo segue a disciplina da pasta `~/.claude/skills/
  agente-00c-runtime/scripts/`. A skill `model-selector` ja e POSIX
  pura (verificado na spec arquivada).
- **Principio III (formato canonico de skill)**: feature NAO altera a
  skill — adiciona consumidores. Contrato I/O da skill permanece
  imutavel. Skill continua progressive-disclosure.
- **Principio IV (zero coleta remota)**: FR-020 explicito. Decisoes e
  skills_invoked persistem apenas em `state.json` local.
- **Principio V (profundidade sobre adocao)**: feature prefere
  registro auditavel + fallback robusto ao inves de "automacao magica"
  que tornaria a integracao opaca. FR-017 protege esse principio ao
  manter a sugestao como sugestao. **[NOTA v4.0.0: FR-017 audit-only
  revogado — ver banner no topo. O Princípio V continua honrado porque
  a aplicação por onda é determinística (mapa fase→modelo) + refino
  auditável + override manual, não "automação mágica opaca".]**

## Success Criteria

### Measurable Outcomes

- **SC-001**: Apos a feature, 100% dos spawns de subagente nos
  orquestradores autonomos (medido em uma execucao real end-to-end
  com fase clarify acionada) MUST gerar uma Decisao com `contexto`
  matchando o padrao `Selecao de modelo para subagente *`.
- **SC-002**: Apos a feature, o overhead de tool calls por fase
  clarify MUST ficar em ate 3 tool calls extras por spawn (1 Skill +
  1 register Decisao + 1 record-skill), confirmavel via
  `state.json.metricas.tool_calls_total` antes e depois.
- **SC-003**: Apos a feature, em pelo menos 1 execucao real, o
  `review-task` MUST produzir um agregado contendo distribuicao de
  rotulos de modelo por subagente — verificavel inspecionando o
  relatorio salvo em `docs/specs/<feature>/review-<onda-id>.md` onde
  `<onda-id>` segue a convencao `onda-NNN` zero-padded do toolkit (path
  canonico definido em F5.2.1; formato canonico do agregado em
  `contracts/review-task-aggregate.md`).
- **SC-004**: A integracao MUST manter compatibilidade com a feature
  `agente-00c-artifact-cache` ativa — uma execucao com cache ON +
  model-routing ON nao gera erros adicionais.
- **SC-005**: Em teste de regressao com `model-selector` desinstalada
  (renomeada), o pipeline de clarify MUST concluir com exit 0 e
  exatamente 0 bloqueios humanos relacionados a essa ausencia.
- **SC-006**: O tempo de invocacao do `model-selector` por spawn MUST
  permanecer abaixo de 2 segundos em maquina dev tipica (skill ja e
  POSIX classify.sh — esperado <500ms). Verificavel via comparacao
  de timestamps das Decisoes consecutivas.

## Out-of-Scope

Este escopo NAO inclui:

1. ~~Aplicacao automatica do modelo sugerido (passar hint para tool
   Agent). DIA-1 do briefing original — decidida explicitamente em
   favor de NAO aplicar (FR-017), respeitando contrato suggest-only
   da skill.~~ **Mudanca de politica futura requer nova feature.**
   **[v4.0.0: a "nova feature" prevista aconteceu — `model-routing-por-onda`
   trouxe a aplicação para dentro do escopo. Este item de Out-of-Scope
   ficou obsoleto.]**
2. Cache persistente de classificacoes entre features ou entre
   execucoes (DIA-2 do briefing). Reinvocacao a cada spawn dentro
   da onda; cache cross-onda fica para spec futura se houver
   evidencia de custo proibitivo.
3. Integracao com pontos de delegacao alem da fase clarify (ex:
   futuras fases que spawnam subagentes via tool Agent). Esta feature
   define o padrao; aplicar a novos pontos vira mudanca incremental
   trivial seguindo a documentacao atualizada em FR-016.
4. Modificacao da skill `model-selector` em si. Catalogo de sinais,
   contrato I/O, exit codes — tudo permanece como entregue. Bugs na
   skill viram bugfix separado.
5. UI de tuning humano da heuristica (ex: operador override do rotulo
   sugerido em runtime). Futuro, depende de evidencia de demanda.

## Open Ambiguities (para clarify)

Todas as 4 DIAs originais e o edge case de FR-013 foram resolvidos na
onda-002 (clarify). Vide secao `## Clarifications` no topo deste
documento. **Status**: 0 ambiguidades pendentes; spec pronta para a
fase `plan`.

## References

- [model-selector spec original (skill standalone)](../model-selector/spec.md)
- [model-selector SKILL.md](../../../global/skills/model-selector/SKILL.md)
- [model-selector catalogo de sinais](../../../global/skills/model-selector/references/sinais.md)
- [agente-00c-orchestrator (host 1)](../../../global/agents/agente-00c-orchestrator.md)
- [agente-00c-feature-orchestrator (host 2)](../../../global/agents/agente-00c-feature-orchestrator.md)
- [docs/constitution.md](../../constitution.md)
- [docs/01-briefing-discovery/briefing.md](../../01-briefing-discovery/briefing.md)
