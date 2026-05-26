# Changelog

Todas as mudanças relevantes deste projeto são documentadas aqui.

O formato segue [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/) e
este projeto adere a [Semantic Versioning](https://semver.org/lang/pt-BR/).

## [4.3.0] - 2026-05-26

A skill `apply-insights` passa a consumir os dados do `/insights` nativo como
fonte PRIMÁRIA, em vez de depender de um resumo curado à mão (que ficava
desatualizado e podia ser de outro projeto). Mudança aditiva e retro-compatível
(degrada para o `.md` curado e depois para best-practices genéricas).

### Added

- **`global/skills/apply-insights/scripts/digest-facets.sh`**: agrega os facets
  per-sessão do `/insights` nativo (`~/.claude/usage-data/facets/*.json`) num
  digest markdown data-driven — distribuição de `goal_categories` e `outcome`,
  **`friction_counts` ranqueado** (sinal-chave para recomendações),
  `claude_helpfulness`, satisfação e **amostras de `friction_detail`** por tipo
  de fricção. Flags `--facets-dir`, `--samples N` (default 3) e `--top N`
  (default 15, corta a cauda longa de alta cardinalidade como `goal_categories`).
  `find -exec cat + | jq -s` evita ARG_MAX. **Degradação graciosa** (sem `jq`,
  diretório ausente, sem `*.json` ou `jq` falhando → exit 0 com stdout vazio).

### Changed

- **`apply-insights/SKILL.md`**: Step 1 reescrito com cadeia de fontes
  **facets digest → `~/.claude/insights/usage-insights.md` curado → genérico**,
  sempre preferindo o digest (atual, do projeto corrente) e informando ao
  usuário qual fonte foi usada. `description` e gotchas atualizados.

### Tests

- **`tests/test_digest-facets.sh`** (14 cenários): agregação, ranking
  descendente de fricção, cap `--top` da cauda longa, amostras de
  `friction_detail`, caso sem fricção, degradação (dir ausente/vazio, `jq`
  ausente via PATH shadow) e validação de argumentos (`--samples`/`--top`
  inválidos, arg desconhecido, `--help`).

## [4.2.0] - 2026-05-25

Enriquecimento da camada B do índice de conhecimento (`knowledge.db`) para
melhor observabilidade no futuro `cstk-panel`. Mudanças **aditivas e
retro-compatíveis**: o índice é derivado e reconstruível via
`cstk recall --reindex`; states e índices antigos seguem funcionando.

### Added

- **Coluna `tasks.titulo` (schema v3)**: a tabela `tasks` passa a guardar o
  título descritivo de cada task (do heading em `tasks.md`). Os orquestradores
  (`agente-00c` e `feature-00c`) gravam `.tasks[].titulo` ao registrar o
  outcome da task; a ingestão grava a coluna passando o valor por
  `secrets-filter.sh` (FR-017 — é o único campo de texto livre da camada B).
  Migração idempotente via `ALTER TABLE tasks ADD COLUMN titulo TEXT` em
  `recall_apply_schema`: índices v2 ganham a coluna **sem** precisar de
  `--reindex`; DBs novos já nascem com ela. Retro-compat: `.tasks[].titulo`
  ausente → `""`.
- **Evento `recall_consulted` + métrica de consultas ao histórico**: os
  orquestradores gravam um evento `recall_consulted` em `.eventos[]` a **cada**
  consulta do read-back loop (`cstk recall --context`) no início de
  `specify`/`plan` — **inclusive quando nada é retornado** (`hits=0`), caso que
  a Decisão `read-back PRE-DECISAO` não cobria (só registrada com `K>0`,
  FR-017). A métrica "quantas vezes o histórico foi consultado pelo
  orquestrador" = `COUNT(*) FROM events WHERE event_type='recall_consulted'`; a
  `descricao` carrega `etapa=… hits=N` para separar consultas produtivas das
  vazias. Sem mudança de schema (a ingestão de `events` aceita o tipo por
  convenção, sem allowlist). Best-effort: nunca gateia/aborta/atrasa a onda.

### Changed

- **`RECALL_SCHEMA_VERSION` 2 → 3** (apenas pela coluna `titulo`; o evento
  `recall_consulted` não altera schema).

### Tests

- `tests/cstk/test_recall.sh`: cobertura de `titulo` (scrub do segredo +
  retro-compat `""`), cenário `m13` da migração ALTER v2→v3 (coluna adicionada,
  linhas pré-existentes preservadas, idempotente) e `b23` da métrica
  `recall_consulted` (total + split produtivas/vazias). Asserts de
  `schema_version` atualizados para `3`.

## [4.1.1] - 2026-05-25

Correções na camada de memória cross-feature (`cstk recall`). Afetam apenas
`cli/lib/recall.sh` — o índice (`~/.claude/cstk/knowledge.db`) é derivado e
reconstruível via `cstk recall --reindex`. Sem mudança de schema.

### Fixed

- **Feature gravada como `unknown` no índice quando `state.json` não tem
  `short_name`**: a ingestão derivava o nome da feature apenas de
  `.short_name`. States legados sem o campo (gravados antes de o `init`
  versioná-lo) caíam no fallback `"unknown"`. Agora a resolução: (1) tolera
  `.execucao.short_name` além de `.short_name`; (2) quando ausente, deriva o
  short-name do diretório-pai no layout `feature-00c-state/<short-name>/`
  (checagem por componente — robusta para caminhos relativos e absolutos).
  O layout `agente-00c-state/` continua `unknown` por design (o orquestrador
  de projeto não grava `short_name` — anti-eco FR-011).
- **`--reindex` podia ESVAZIAR o índice (perda de dados)**: o `find` de
  descoberta de states, ao varrer uma raiz ampla (ex.: `$HOME` default), sai
  com status ≠0 ao tocar diretórios sem permissão — **mesmo tendo impresso
  matches válidos**. O idioma `find ... || _rx_states=""` descartava esses
  matches; como o reindex apaga o DB antes de repopular, o índice terminava
  vazio. Trocado por `|| :`, que preserva o stdout já capturado pela
  command-substitution.

### Tests

- `tests/cstk/test_recall.sh`: `scenario_16` (resolução de feature com
  `short_name` ausente — fallback por diretório, `.execucao.short_name`,
  caminho relativo, e `agente-00c-state` → `unknown`) e `scenario_17`
  (reindex preserva matches quando `find` sai ≠0).

## [4.1.0] - 2026-05-24

Melhorias de tooling de desenvolvimento (não afetam o tarball de release nem
o usuário instalado — apenas `tests/`, `.github/` e `.shellcheckrc`). O tarball
de catálogo é idêntico em conteúdo ao da v4.0.0; esta release é um marco de
repo (sincroniza CHANGELOG/tag) e gate de CI.

### Added

- **`tests/run.sh --fast` / `--slow`**: split da suite por velocidade. `--fast`
  pula a allowlist de tests lentos (`_is_slow_test`, derivada de medição — 11
  tests > ~5s somando ~177s de ~260s) e roda em ~1/3 do tempo; `--slow` roda só
  os lentos. Mutuamente exclusivos; compõem com PATTERN e `--list`/`--stats`.
- **`tests/run.sh --stats`**: agrega contagem de scenarios por arquivo (desc) +
  total. Respeita PATTERN e o filtro de velocidade.
- **`tests/test_run-modes.sh`**: cobertura dos novos modos (registrado como
  teste interno em `_is_internal_test`).
- **CI shellcheck advisory** (`.github/workflows/shellcheck.yml`): lint estático
  dos `.sh` em PR + push main, **não-gateante** (`continue-on-error`). Config de
  ruído sistêmico em `.shellcheckrc` (disable SC1091/SC2016/SC2148).

## [4.0.0] - 2026-05-24

**BREAKING** — feature `model-routing-por-onda`. O model-routing dos
orquestradores autônomos (`agente-00c`/`feature-00c`) **deixa de ser
audit-only**: o modelo escolhido agora **É APLICADO** à execução. Isto
**revoga a cláusula FR-017** da feature original `agente-00c-model-routing`
(v3.15.0), cuja premissa de que "o harness não aceita `model` no spawn,
logo a escolha é apenas auditoria" ficou **obsoleta** — o harness atual
aceita `model` no spawn de subagente (precedência sobre o frontmatter).
O gatilho do routing deixa de ser o caminho raro do spawn de clarify e
passa a ser **toda onda** do pipeline.

Por que MAJOR: muda o **contrato de comportamento** do orquestrador
(antes: sugere e audita, nunca aplica; depois: aplica por onda). Para
ativar o comportamento novo é preciso **build + install** da fonte
(`global/...`) — passo manual do operador; o tarball publicado é que
carrega o efeito. Camada de telemetria/auditoria permanece
retro-compatível (execuções antigas sem Decisão por-onda continuam
legíveis pelo agregador).

### Changed (BREAKING)

- **Mecanismo PRIMÁRIO — mapa fase→modelo por onda** (FR-014): novo
  `model-routing.sh wave-select --state-dir <SD>` resolve a fase (via
  `--etapa` ou `.etapa_corrente`) e retorna o modelo a **aplicar** na
  onda, com base no mapa versionado e determinístico
  `global/skills/agente-00c-runtime/references/phase-model-map.txt`
  (POSIX-puro, sem `jq`). Recorte default "3 faixas balanceado":
  `plan`/`analyze`/`constitution`→**opus**;
  `specify`/`clarify`/`checklist`/`create-tasks`/`briefing`→**sonnet**;
  `execute-task`→**sonnet** (piso refinável); `validate-docs`/`review-task`→**haiku**;
  fase não listada → `manter-atual` (FR-020 — nunca erro, evolução tolerada).
- **Aplicação no spawn de clarify** (US2, FR-003): o passo 8 da sequência
  pré-spawn passa `model=<escolha>` à tool Agent quando acionável
  (`escolha` ∈ {haiku,sonnet,opus} e `score >= 2`); em fallback/
  `manter-atual`/`score<2` o `model` é omitido e o subagente herda o
  `model:` do frontmatter. O par Decisão⟷spawn permanece 1-para-1
  (Invariante I1): a aplicação **não** cria 2a Decisão.
- **Documentação revogando o audit-only** (FR-017): banner de
  **supersessão** na spec arquivada `docs/specs/_archived/agente-00c-model-routing/spec.md`
  (Status + FR-017 + Princípio V + Out-of-Scope anotados); seção
  model-routing do `CLAUDE.md` reescrita (aplicação por onda + tabela
  fase→modelo + ordem de precedência); blocos pré-spawn dos dois agent
  files (`agente-00c-orchestrator.md`, `agente-00c-feature-orchestrator.md`)
  corrigidos para refletir aplicação (eliminadas as contradições internas
  com a nota FASE 5); `review-task/SKILL.md` ajustado.

### Added

- **`model-selector` como camada de REFINO** (FR-001/FR-019, US4): roda
  **só em `execute-task` com `--task-text`**, sobre o piso do mapa
  (sonnet), podendo **elevar→opus** (tarefa profunda) ou **rebaixar→haiku**
  (tarefa trivial). Catálogo de sinais (`global/skills/model-selector/references/sinais.md`)
  expandido além do MVP com vocabulário de fase/complexidade, coberto por
  corpus de teste (`tests/fixtures/model-selector-corpus/corpus.tsv`).
- **Precedência de resolução do modelo da onda**:
  `override manual (FR-016) > escalada mid-onda→opus (FR-015) > refino model-selector > mapa fase→modelo`.
  Override do operador via Decisão manual pré-onda lida pelo resume;
  escalada mid-onda via `.escalada_modelo_pendente=true` gravado pela onda
  anterior (sinaliza subestimação).
- **Idempotência por onda** (FR-008): `wave-select` ecoa o modelo já
  aplicado e **não** registra 2a Decisão quando já existe
  `DecisaoDeRoteamentoPorOnda` para a onda corrente (seguro em resume).
- **Auditoria sugerido-vs-aplicado** (US3, FR-012/SC-006):
  `model-routing-report.sh aggregate` ganha 2a seção "Seleção por onda —
  sugerido vs aplicado" (distribuição do modelo aplicado, por origem
  mapa/refino/override/fallback, taxas de fallback e override, contagem de
  divergências sugerido≠aplicado com `rotuladas`/`sem rotulo`). `sem rotulo`
  DEVE ser 0 (`review-task` escala finding `model-routing-divergencia-sem-rotulo`).
- **Integração nos commands** (FASE 3): `agente-00c`/`feature-00c` +
  respectivos `*-resume` aplicam o `wave-select` no início de cada onda e
  leem override manual pré-onda.
- **Cobertura de teste**: `tests/test_model-routing.sh`,
  `tests/test_model-routing-report.sh`,
  `tests/test_command-spawn-model-routing.sh`,
  `tests/test_orchestrator-spawn-model-apply.sh`,
  `tests/test_state-decisions-reconcile.sh`,
  `tests/cstk/test_model_selector_corpus.sh`, fixtures de state com routing
  por onda (mixed + unlabeled-divergence).

## [3.19.1] - 2026-05-24

Correções de coerência pós-`3.19.0`, sem mudança de comportamento do produto
(documentação + tooling de testes). Não altera o conteúdo funcional do tarball.

### Fixed

- **CHANGELOG — footer-links da série 3.x**: o rodapé de links de versão só
  cobria `1.0.0`/`1.1.0`/`2.0.0`; toda a série 3.x (28 versões, incluindo a
  própria `3.19.0`) estava sem link. Bloco regenerado a partir dos headings
  (formato `releases/tag/vX.Y.Z`, ordem descendente) — agora **31 headings =
  31 links**, consistente com a convenção Keep a Changelog.
- **`tests/run.sh --check-coverage` — falsos órfãos**: o check saía com
  exit 1 por 3 órfãos-de-script (`_log.sh`, `_state-dir.sh`, `classify.sh`) +
  27 órfãos-de-test que, na verdade, **possuem cobertura** — apenas sob tests
  de nome descritivo que não casa a convenção 1:1 `test_<base>.sh` (tests
  granulares de `model-selector` e tests de aspecto como
  `runtime-log-redaction`, `secrets-filter-backup`, `skills-cache-protocol`,
  `update-extra-kinds`, `state-dir-parametrization`). Adicionada allowlist
  coerente nos dois lados (`_is_internal_test` para tests +
  `_is_covered_by_named_test` para scripts), **cada isenção exigindo que o
  cobridor exista em disco** (anti-ponto-cego: se o script/test sumir, volta a
  ser órfão real). Resultado: `./tests/run.sh` → `ORPHANS: 0` (sem falso WARN) e
  `--check-coverage` → exit 0. Suíte completa 1043/0/0, sem regressão.

## [3.19.0] - 2026-05-24

Expande a **ingestão da memória de conhecimento** (`cstk recall`) para derivar
métricas de dashboard a partir do `state.json` transacional, **sem nunca
tocá-lo** (somente leitura) e **sem quebrar a propriedade de índice derivado**
(tudo reconstruível via `cstk recall --reindex`). O índice
(`~/.claude/cstk/knowledge.db`) sobe de **schema v1 → v2** de forma **aditiva e
retro-compatível** (`CREATE TABLE IF NOT EXISTS`): nenhuma das 4 tabelas
textuais existentes (`decisions`/`bloqueios`/`retros`/`skills`) muda de
semântica, e bases v1 instaladas migram em silêncio na primeira ingestão. Esta
feature prepara o terreno para um futuro `cstk-panel` (dashboard read-only,
**fora de escopo**): este repositório passa a ser a fonte da verdade das
métricas que o painel consumirá. Camada estritamente aditiva, best-effort,
read-only — nenhum breaking change nos modos existentes
(`search`/`--ingest`/`--reindex`/`--context`).

### Added

- **Camada A — métricas derivadas** em `cli/lib/recall.sh`: 3 novas tabelas
  ingeridas a partir de `.execucao`, `.ondas[]`, `.metricas_acumuladas`,
  `.orcamentos` e `.historico_movimento_circular` do `state.json`:
  - `executions` — uma linha por execução (proveniência project/feature/id,
    status, motivo de término filtrado, duração derivada; `NULL` quando
    `em_andamento`).
  - `waves` — uma linha por onda (ciclo de vida, `tool_calls`,
    `wallclock_seconds`, motivo de término).
  - `alert_signals` — uma linha por sinal de alerta (circular, budget breach),
    idempotente e tolerante a negativos.
  Métricas adicionais (latência humana de bloqueios, clarify-rate, mix de
  roteamento de modelos) ficam **deriváveis** a partir das tabelas — o mix de
  modelos permanece delegado ao agregador `model-routing-report.sh`.
- **Camada B — instrumentação** em `cli/lib/recall.sh` + nos dois
  orquestradores (`global/agents/agente-00c-feature-orchestrator.md` e
  `agente-00c-orchestrator.md`): 2 novas tabelas alimentadas por campos
  **aditivos** do `state.json`:
  - `tasks` — outcome por task (`outcome` pass|fail, testes rodados/passados,
    `lint_ok`, `arquivos_tocados`), chave natural
    `(project, feature, execucao_id, task_id)`.
  - `events` — eventos do ciclo de execução. Campos `.tasks[]`/`.eventos[]`
    gravados pelo **mesmo caminho de runtime auditado** dos demais writes —
    nenhum mecanismo de escrita novo (contract layer-b §5).
- **`schema_version` do índice 1 → 2** (registrado em `schema_meta`); migração
  aditiva e idempotente.

### Notes

- **Índice puramente derivado (FR-001/FR-002)**: a ingestão lê o `state.json`
  somente em modo leitura (`jq -r` + `wc -c`); auditoria empírica confirma zero
  write-back ao `state.json` e confinamento de `sqlite3` exclusivamente em
  `cli/lib/recall.sh` (FR-004). Base inteira reconstruível via `--reindex`.
- **Degradação graciosa (FR-003)**: ausência de `sqlite3`/`jq` nunca aborta a
  ingestão nem a onda — sai com status 0 emitindo aviso.
- **Idempotência (FR-008)**: toda escrita de entidade nova é idempotente por
  chave natural; re-ingerir a mesma execução não altera o índice.
- **Segredos (FR-006)**: todo texto livre persistido passa pelo filtro de
  segredos antes do `INSERT`.
- Spec: [`docs/specs/knowledge-db-metrics/`](docs/specs/knowledge-db-metrics/);
  contratos em
  [`contracts/recall-ingest-schema.md`](docs/specs/knowledge-db-metrics/contracts/recall-ingest-schema.md)
  e
  [`contracts/layer-b-instrumentation.md`](docs/specs/knowledge-db-metrics/contracts/layer-b-instrumentation.md).

## [3.18.0] - 2026-05-23

Fecha o **read-back loop** da memória de conhecimento cross-feature: até
v3.17.0 os orquestradores apenas ESCREVIAM no índice (`cstk recall --ingest`);
agora também LEEM de volta. Um novo modo `cstk recall --context` consulta o
índice (FTS5/bm25) com os termos da feature corrente e devolve um bloco
markdown enxuto pronto para injeção em prompt; os orquestradores `agente-00c`/
`feature-00c` o invocam num passo PRE-DECISAO no início das fases `specify` e
`plan`, injetando aprendizado de execuções passadas antes de decidir. Camada
estritamente aditiva, best-effort, read-only — nenhum breaking change nos modos
existentes (`search`/`--ingest`/`--reindex`).

### Added

- **Modo `cstk recall --context "<termos>"`** em `cli/lib/recall.sh`
  (`recall_mode_context`): retorna um ContextBlock markdown (`> Aprendizado
  recuperado (read-back loop) — K achados...` + uma linha por achado com
  proveniência `project/feature/wave (ts): body`). Flags: `--limit N`
  (default **4**), `--exclude-feature NAME` (anti-eco no SQL), `--max-bytes N`
  (default **2000**, corte por achado inteiro), `--type`/`--project`/`--db`
  (iguais ao modo busca). Composição **OR** entre termos (novo helper
  `fts_query_escape_or`, reusa `fts_phrase_escape`) — o modo busca permanece
  AND-implícito.
- **Passo PRE-DECISAO (read-back loop)** nos dois orquestradores
  (`global/agents/agente-00c-feature-orchestrator.md` e
  `agente-00c-orchestrator.md`): dispara somente em `specify`+`plan`, deriva
  termos de `aspectos_chave_iniciais` (≤8, fallback `projeto_alvo_descricao`),
  injeta o bloco com rótulo **UNTRUSTED / não-autoritativo** (defesa
  prompt-injection ASI09/LLM01) e registra Decisão auditável quando K>0
  (sem persistir o body bruto recuperado).

### Security

- Conteúdo recuperado pelo modo `--context` já foi *scrubbed* na ingestão
  (`secrets-filter.sh`) — o consumo não re-scrub (seguro por construção). NUL
  rejeitado em qualquer input; anti-eco aplicado no SQL via `sql_escape` (sem
  bypass por valor manipulado); injeção SQL/FTS tratada como literal.

### Notes

- `cstk recall --context` é **read-only** e **best-effort**: toda degradação
  (sem `sqlite3`, índice ausente/corrompido, zero achados, query degenerada)
  resulta em no-op silencioso (stdout vazio, exit 0) — nunca gateia uma onda.
  O teto de tempo (US3-3) é satisfeito pelo `.timeout 5000` do SQLite + a
  natureza best-effort, sem `timeout` wrapper dedicado (POSIX sh puro).
- Cobertura: 22 cenários novos em `tests/cstk/test_recall.sh` (modo `--context`
  faz parte de `recall.sh`, sem arquivo de teste órfão), rodados sob HOME real
  e HOME falso.

## [3.17.0] - 2026-05-23

Adiciona a camada aditiva de memória de conhecimento cross-feature: um índice
SQLite global (`~/.claude/cstk/knowledge.db`, FTS5) alimentado por um hook
best-effort no fim de cada onda dos orquestradores `agente-00c`/`feature-00c`,
e o novo comando `cstk recall` para busca cross-projeto/feature com
proveniência. O índice é puramente derivado — o `state.json` transacional
permanece a fonte de verdade, intacto, fora do caminho crítico. Sem breaking
changes.

### Added

- **Comando `cstk recall`** em `cli/lib/recall.sh` (POSIX sh + `jq` +
  `sqlite3`), com três modos:
  - **busca** (default): `cstk recall <query> [--project P] [--type T]
    [--limit N] [--db PATH]` — full-text via FTS5/bm25 sobre decisões,
    bloqueios, retro-execuções e skills invocadas, ordenado por relevância e
    exibindo proveniência (projeto / feature / onda / data). `--type` aceita
    `decision|bloqueio|retro|skill`; `--limit` exige inteiro positivo (default
    20).
  - **ingestão** (`--ingest --state-dir DIR`): extrai os registros de um
    `state.json` e faz upsert idempotente no índice (filtrado por
    `secrets-filter` antes da escrita). É o hook chamado no fim de onda.
  - **reconstrução** (`--reindex [--states-root DIR]`): reconstrói o índice a
    partir dos `state.json`/`state-history` existentes, tornando a base
    totalmente descartável e regenerável.
- **Hook de fim de onda** documentado em ambos os orquestradores
  (`agente-00c-orchestrator` e `agente-00c-feature-orchestrator`): após o
  backup filtrado da onda, invoca `cstk recall --ingest` em modo best-effort.
- **Segurança de entrada** em `recall.sh`: escaping em duas camadas (literais
  SQL via duplicação de aspas simples + tokens FTS5 via duplicação de aspas
  duplas), validação de `--limit` como inteiro, e rejeição/strip de bytes NUL.
- **Degradação graciosa**: a ausência de `sqlite3` ou `jq` nunca aborta uma
  onda — o hook e o `recall` saem com status 0 emitindo um aviso. O índice é
  isolado em `~/.claude/cstk/`, separado do estado transacional por projeto.
- **Cobertura**: 20 cenários em `tests/cstk/test_recall.sh` (quickstart 1-14,
  detector/strip de NUL, degradação sem `sqlite3`/`jq`, índice corrompido,
  reindex, adversariais e concorrência), `shellcheck -s sh` limpo. Spec em
  `docs/specs/cstk-knowledge-db/`.

## [3.16.0] - 2026-05-23

Adiciona a skill `decision-tree`, que gera um relatório HTML interativo em
forma de árvore de decisão a partir do `state.json` de uma execução
`agente-00c`/`feature-00c`. Inclui correção de conformidade (Princípio I e III
da constitution) e habilita a skill no profile `complementary`. Sem breaking
changes.

### Added

- **Skill `decision-tree`** em `global/skills/decision-tree/`: o script POSIX
  `render-decision-tree.sh` (subcomando `render --state PATH [--output FILE]
  [--title STR]`) extrai `.decisoes[]` via `jq` e injeta num template HTML
  autocontido (SVG + painel de detalhe + zoom, abre offline sem CDN). O tronco
  verde liga cronologicamente a `escolha` de cada Decisão à seguinte, de
  `dec-001` até um nó de conclusão. Invariantes IDT-1 (read-only), IDT-2
  (determinístico byte-a-byte), IDT-3 (POSIX puro), IDT-4 (render no cliente).
  Cobertura: 18 cenários em `tests/test_render-decision-tree.sh`,
  `shellcheck -s sh` limpo.
- **`complementary:decision-tree`** em `scripts/profiles.txt.in`: a skill agora
  é instalada por `cstk install --profile complementary` (e por `--profile
  all`). Antes só aparecia no profile auto-gerado `all`.
- **Spec retroativa** em `docs/specs/decision-tree/` (`spec.md` + `tasks.md`):
  ratifica o contrato já implementado para conformidade com o Princípio I (SDD
  recursivo) da constitution.

### Fixed

- **Seção `## Gotchas` ausente** em `global/skills/decision-tree/SKILL.md`
  (violava o Princípio III — "um SKILL.md sem Gotchas é incompleto" — e o
  quality gate `grep -L '## Gotchas'`). Adicionadas armadilhas reais: `jq`
  mandatório sem fallback, escape obrigatório de `</`, `escolha` fora das
  opções, proibição de timestamp no payload (IDT-2) e de CDN externo.
- **`model-selector` órfã de profile**: a skill (v3.14.0), consumida pelos
  orquestradores no passo 1 do model-routing, só estava no profile
  auto-gerado `all`. `cstk install` (default `sdd`) instalava os orquestradores
  mas deixava o fluxo de model-routing sem a skill que ele invoca. Adicionada a
  `sdd:model-selector` e `complementary:model-selector` em
  `scripts/profiles.txt.in` (mesma razão de `agente-00c-runtime`).

## [3.15.0] - 2026-05-23

Entrega da feature `agente-00c-model-routing` via pipeline SDD
autonoma `/feature-00c` em 21 ondas com 42+ decisoes auditaveis.
Integra a skill standalone `model-selector` (v3.14.0) aos
orquestradores autonomos `agente-00c` e `feature-00c` no spawn de
subagentes via tool Agent (clarify-asker + clarify-answerer),
registrando Decisao auditavel + entrada em
`.ondas[N].skills_invoked[]` por spawn. Sem breaking changes.

### Added

- **Helper POSIX `model-routing.sh`** em
  `global/skills/agente-00c-runtime/scripts/`: 3 subcomandos
  (`template`, `invoke`, `idempotent-check`) implementando
  invariantes INV-1..INV-6 do contract. `template` emite payload
  determinista para input do `model-selector`; `invoke` orquestra
  classify+register+skill-invoked em uma transacao atomica via
  state-lock; `idempotent-check` rejeita re-spawn com mesmo input
  (mesmo `decisao-id` + mesmo input-hash). Cobertura: 94 cenarios
  shell em `tests/test_model-routing.sh`, `shellcheck -s sh` limpo.
- **Reconciliador `state-decisions-reconcile.sh`** em
  `global/skills/agente-00c-runtime/scripts/`: 2 subcomandos
  (`detect`, `repair`). Resolve **half-records** (decisao sem
  entrada em `skills_invoked[]` ou vice-versa) detectados em
  retomadas pos-crash. `--dry-run` lista divergencias sem mutar;
  `--apply` reescreve mantendo append-only via merge auditavel.
  Cobertura: 11 cenarios em `tests/test_state-decisions-reconcile.sh`.
- **Agregador `model-routing-report.sh aggregate`** em
  `global/skills/agente-00c-runtime/scripts/`: consome state.json e
  emite tabela markdown (total de roteamentos, distribuicao por
  modelo `haiku|sonnet|opus|manter-atual`, taxa de fallback,
  half-records pendentes — deve ser 0). Consumido pelo
  `review-task` para auditoria de cobertura de model-routing.
  Cobertura: 17 cenarios em `tests/test_model-routing-report.sh`.
- **Integracao em `agente-00c-orchestrator.md` §5.e.bis**: nova
  secao "Roteamento de modelos pre-spawn" com sequencia 8-step e
  invariantes I1 (toda decisao gera skill_invoked match), I2 (toda
  retomada checa half-records), I3 (idempotencia por input-hash).
  Analogo em `agente-00c-feature-orchestrator.md`.
- **Auditoria em `review-task/SKILL.md` §4.5**: nova subsecao
  "Model-routing coverage" — review-task agora chama
  `model-routing-report.sh aggregate` e reporta saude do roteamento
  (cobertura de spawns, taxa de fallback, half-records).
- **Spec SDD completa** em
  `docs/specs/agente-00c-model-routing/`: spec.md (20 FRs),
  plan.md, research.md, data-model.md, quickstart.md, tasks.md
  (~100 tarefas em 7 fases), contracts/
  (`model-routing-helper.md` com 6 invariantes,
  `orchestrator-integration.md`), checklists/requirements.md
  (50 items, 4 load-bearing CHK032/CHK047/CHK048/CHK050).

### Fixed

- **Performance: watcher subshell leak** (descoberto durante
  execucao da feature): scripts internos do agente-00c-runtime
  spawnavam subshells de watcher em loop sem cleanup, causando
  ~16.8x overhead em ondas longas. Corrigido com trap EXIT
  explicito + PID tracking. Impacto: ondas de execute-task longas
  (>10min) agora finalizam ~17x mais rapido.

### Changed

- `review-task/SKILL.md` ganhou §4.5 (model-routing audit). Demais
  secoes inalteradas — comportamento backwards-compatible quando
  state.json nao tem `skills_invoked[]` com entries do model-selector.

## [3.14.0] - 2026-05-22

Tres entregas principais: (1) skill `model-selector` completa via
pipeline SDD autonoma, (2) Fases 1+2 da feature `artifact-cache`
(primitiva `state-cache.sh` + protocolo de leitura nas 4 skills SDD
principais), (3) otimizacoes de tokens/boot via trim de descriptions
em skills, commands e custom agents. Sem breaking changes.

### Added

- **Skill `model-selector`** (PR #17): sugestor de modelo
  (`haiku`/`sonnet`/`opus`) por heuristica POSIX pura.
  `scripts/classify.sh` (560+ linhas) classifica o input do operador em
  rasa/media/profunda e emite output markdown em 4 secoes fixas, com
  fallback `manter-atual` quando indeterminado (input <3 tokens ou
  empate de pesos). `scripts/report.sh` (118 linhas) agrega varias
  classificacoes via branch jq happy-path + fallback awk
  **byte-identical** (FR-010a — carve-out de optional-deps).
  Catalogo de sinais extensivel sem patch em `references/sinais.md`
  (15 verbos MVP, peso=1). Rotulos sempre abstratos — nunca versao
  concreta de modelo. 22 testes shell (~127 cenarios PASS),
  `shellcheck -s sh` limpo, `SKILL.md` <200 linhas. Entregue via
  pipeline SDD autonoma `/feature-00c` em 23 ondas com 100 decisoes
  auditaveis.
- **Protocolo de leitura cache em skills SDD (Fase 2 de
  artifact-cache)** (PR #16): `specify`, `clarify`, `plan` e
  `execute-task` agora consultam `state-cache.sh read` antes de ler
  briefing/constitution do disco, com fallback transparente. Reduz
  ~5-10k tokens/onda em pipelines longos do `agente-00c`/
  `feature-00c`. Hash-validation TOCTOU-safe via `_hash.sh`; skills
  standalone (sem state.json) preservam comportamento original.
- **Primitiva `state-cache.sh` + `_hash.sh` (Fase 1 de
  artifact-cache)** (PR #15): novo helper POSIX em
  `global/skills/agente-00c-runtime/scripts/state-cache.sh` com 6
  subcomandos (`init`, `read`, `write`, `invalidate`, `status`,
  `gc`) operando sobre namespace `artifact_cache` em `state.json`.
  Extensao `state-validate` aceita o novo schema. Helper sourceable
  `_hash.sh` centraliza calculo de SHA-256 com fallback
  `sha256sum`/`shasum`/`openssl`/awk.

### Added (drafts SDD — sem implementacao)

- **Feature SDD `agente-00c-artifact-cache`** drafts iniciais em
  `docs/specs/agente-00c-artifact-cache/`:
  - `spec.md` — feature spec completa com 4 User Stories
    (P1/P1/P2/P2), 17 Functional Requirements (FR-CACHE-001..017),
    Edge Cases, Constitutional Alignment, 5 Success Criteria,
    Out of Scope, e 5 Open Questions para `/clarify`.
  - `plan.md` — plano tecnico provisorio com Constitution Check,
    Data Model (state.json novo schema), API Contracts da primitiva
    nova `state-cache.sh` (6 subcomandos), Research (5 decisoes),
    Project Structure, Phase plan, Risks.
  - `tasks.md` — 20 tarefas em 5 fases (Clarify → Primitiva+schema →
    Skills → Orquestrador+report → Integracao+release), matriz de
    dependencias, coverage matrix Requirements×Tasks.
- Proposito: reduzir ~5-10k tokens/onda em pipelines longos do
  agente-00c via cache opcional de briefing.md + constitution.md
  em `state.json`, com hash-validation TOCTOU-safe e fallback
  preservado para skills standalone.
- Implementacao real fica deferida apos `/clarify` resolver as 5
  Open Questions.

### Changed

- **Slash commands + custom agents descriptions**: trim YAML `description:`
  em todos os 6 slash commands (`global/commands/`) e 6 custom agents
  (`global/agents/`). Reducao de ~5.245 chars para ~2.569 chars (~669 tokens
  economizados por boot, -51%). Triggers e discriminadores chave preservados
  (clarify-asker vs answerer, orchestrator vs feature-orchestrator, etc).
  Detalhes operacionais e flags permanecem no body de cada arquivo (so
  carrega quando o comando/agente e efetivamente invocado). Continuacao da
  otimizacao iniciada em PR #8 (skills); combinada, total ~2k tokens/boot.
  PR #9.
- **Skill descriptions**: trim YAML `description:` em todas as 21 skills de
  `global/skills/` (de ~10k chars / ~2.560 tok para ~4.6k chars / ~1.150 tok
  no contexto eager-loaded). Reducao de 54% nos descriptions, ~1.350 tokens
  economizados por boot. Triggers (frases em aspas) preservados — routing
  inalterado. Detalhe sobre frameworks, listas longas e clausulas
  "NAO use para X" extensas migrado para o body do `SKILL.md`
  (so carrega quando a skill e invocada). Otimizacao para reduzir custo
  por onda em pipelines longos (`agente-00c`, `feature-00c`). PR #8.

## [3.13.0] - 2026-05-20

Feature-00C — variante do agente-00C focada em **uma feature
individual** dentro de projeto que JA tem `briefing.md` +
`docs/constitution.md` ratificados. Reusa integralmente o runtime
POSIX do agente-00c via parametrizacao retrocompativel (zero
mudancas em comportamento do `/agente-00c`). Bump MINOR — nenhuma
breaking change.

### Added

- **3 slash commands**: `/feature-00c "<descricao>" [<short-name>]`
  (invocacao), `/feature-00c-resume <short-name>` (retomada com hash
  validation TOCTOU-safe), `/feature-00c-abort <short-name>` (aborto
  manual com SIGTERM + grace period 60s).
- **3 agentes custom**: `agente-00c-feature-orchestrator` (pipeline
  7-fases: specify → clarify → plan → checklist → create-tasks →
  execute-task → review-task), `feature-00c-clarify-asker`,
  `feature-00c-clarify-answerer` (algoritmo de score 0..3 identico
  ao 00c, mas 3a fonte = spec_corrente em vez de stack_sugerida).
- **Pre-flight `feature-00c-preflight.sh`** (FR-010A): valida hashes
  briefing + constitution registrados em state.json contra arquivos
  em disco; distingue MAJOR drift (bloqueio compulsorio) de
  MINOR/PATCH (aviso opcional). Output JSON estruturado.
- **Filtro de secrets estendido** (FR-029 §extensao + FR-036):
  `secrets-filter.sh for-backup` gera backups por onda com hash
  auto-registrado (`state_sha256_self`) sobre conteudo filtrado;
  `_log.sh` aplica filtro em stderr/stdout via helper sourceable
  com fallback `[NO-FILTER]` graceful.
- **§Quality Gates complementares** no
  `agente-00c-feature-orchestrator.md` (alinhamento com PR #6 /
  v3.12.0): integra `validate-documentation` (apos specify+plan),
  `owasp-security` (apos plan, findings critical/high =
  BloqueioHumano OBRIGATORIO) e `validate-docs-rendered` (apos
  create-tasks) como gates pos-artefato auditaveis.
- **`gate-finding` e `gate_skipped`** como `kind` validos de Decisao
  (`data-model.md` §Decisao). `/review-task` audita features com
  >2 skips sem justificativa como `quality-gate-bypass`.
- **Helper sourceable `_state-dir.sh`**: resolve diretorio de
  estado via precedencia `--state-dir arg > AGENTE_00C_STATE_DIR
  env > erro`. Inclui `_sd_flavor_to_report_name` para nomes
  canonicos por flavor (agente-00c | feature-00c).
- **Roundtrip empirico de secrets** documentado em
  `docs/specs/feature-00c/validation-runs/roundtrip-secrets-2026-05-20.md`
  — 7 checks PASSED empiricamente (contrato de privacidade da
  feature-00c validado).

### Changed

- **README.md**: nova subsecao "Feature-00C — Variante de escopo de
  feature individual" sob a secao Agente-00C, documentando os 3
  comandos novos + coexistencia com agente-00c.
- **`global/skills/agente-00c-runtime/SKILL.md`**: description
  atualizada mencionando os DOIS orquestradores que consomem o
  runtime; 3 secoes novas + 4 Gotchas cobrindo as adicoes.
- **21 scripts POSIX do agente-00c-runtime**: refactor de
  parametrizacao confirmado como majoritariamente DESNECESSARIO
  (auditoria empirica em
  `global/skills/agente-00c-runtime/scripts/_audit-paths.md`:
  18/21 ja aceitavam `--state-dir` desde v1.0).

### Tests

- **+33 cenarios POSIX** na suite global (de 651 → 672 PASS):
  - `tests/test_state-dir-parametrization.sh` (12 cenarios)
  - `tests/test_feature-00c-preflight.sh` (7 cenarios)
  - `tests/test_secrets-filter-backup.sh` (8 cenarios)
  - `tests/test_runtime-log-redaction.sh` (6 cenarios)
- **Template de cenarios manuais** em
  `docs/specs/feature-00c/validation-runs/quickstart-2026-05-20.md`
  (12 cenarios incluindo roundtrip empirico + gate-finding).

### Backward compatibility

- Zero breaking changes. `/agente-00c` continua funcionando
  bit-a-bit identico.
- Refactor de runtime e 100% retrocompativel — comportamento
  default preservado sem env var.
- Suite POSIX completa: 672 PASS / 0 FAIL / 0 ERROR / ~140s.

### Detalhamento

[`docs/specs/feature-00c/`](./docs/specs/feature-00c/): 37 FRs, 14
SCs, 11 user stories, plan + research (7 Decisions Phase 0), data-
model (8 entidades), 2 contracts (cli-invocation + report-format),
2 checklists (requirements 35 items, security 40 items), quickstart
(12 cenarios), validation-runs (coverage + quickstart-template +
roundtrip empirico).

## [3.12.0] - 2026-05-20

Auditoria estrategica de skills "complementares" do toolkit. Skills sem
referencia em nenhum orquestrador ou skill orquestradora eram codigo
morto — discoverable so via trigger phrase manual, e raramente
acionadas na pratica. Esta release toma decisao explicita skill-por-skill:
incentivar (integrando aos orquestradores), depreciar (com remocao
agendada), ou remover (quando project-specific demais para o toolkit).

### Added

- **Principio formal de escopo do toolkit** (README §Contribuindo):
  skills publicadas em `global/skills/` ou `language-related/<stack>/skills/`
  NAO devem nomear clientes/projetos especificos. Skills com forte
  acoplamento a um projeto pertencem ao proprio projeto, em
  `<projeto>/.claude/skills/`. Caso historico: `create-report`.
- **Quality Gates SDD no orchestrator** (`agente-00c-orchestrator.md`
  secao 5.f): 3 skills antes orfas (`validate-documentation`,
  `validate-docs-rendered`, `owasp-security`) viraram gates
  nao-bloqueantes pos-artefato no pipeline:
  - apos `specify` → `validate-documentation` em spec.md
  - apos `plan` → `validate-documentation` em plan.md + `owasp-security`
    (findings critical/high obrigam BloqueioHumano)
  - apos `create-tasks` → `validate-docs-rendered` no feature-dir

  Skip de gate e auditavel: requer Decisao com justificativa, e
  `/review-task` flaga features com >2 skips sem motivo solido como
  `quality-gate-bypass`.
- **Delegacao para skills Go em `execute-task` e `review-task`:**
  6 skills `go-*` antes orfas viraram atalhos explicitos quando stack
  detectado for Go (`execute-task` §4.2.1 e `review-task` "Atalhos de
  auditoria por stack"): `go-add-entity`, `go-add-consumer`,
  `go-add-migration`, `go-add-test`, `go-review-service`, `go-review-pr`.

### Deprecated

- **Skill `create-use-case`**: substituida por `specify` (formato SDD
  com user stories, success criteria e integracao com pipeline orquestrado).
  Frontmatter recebe `deprecated: true`, `deprecated_since: 3.12.0`,
  `remove_in: 4.0.0`. UC classico nao tem mais espaco no fluxo atual.
- **8 skills `dotnet-*`**: `dotnet-create-entity`, `dotnet-create-feature`,
  `dotnet-create-project`, `dotnet-create-test`,
  `dotnet-hexagonal-architecture`, `dotnet-infrastructure`,
  `dotnet-review-code`, `dotnet-testing`. Stack .NET descontinuada pelo
  mantenedor; sem substituto no toolkit global. Remocao agendada para
  v4.0.0 — usuarios que ainda usam .NET devem copiar para
  `<projeto>/.claude/skills/` antes da remocao.

### Removed

- **Skill `create-report`** (`language-related/go/skills/create-report/`):
  era altamente acoplada ao sistema GOB (nomes de servico hardcoded
  `gob-report-service`/`gob-go-commons`, exchange RabbitMQ `gob.reports`,
  caminhos ETCD do GOB, vocabulario macônico `lodge`/`federal`/`state_orient`,
  cabecalho fixo "Grande Oriente do Brasil" no PDF). Material project-specific
  pertence ao `<projeto>/.claude/skills/`, nao ao toolkit global. Caso
  historico que motivou o principio formal acima.

### Changed

- **README**: arvore de estrutura marca `create-use-case` e diretorio
  `language-related/dotnet/` como deprecated; tabela "Skills para .NET"
  recebe aviso de depreciacao; tabela "Skills para Go" reflete a
  delegacao via orquestradores; secao Contribuindo ganha o principio
  formal de escopo + regra #8 ("Generalize, ou pertence ao projeto").

### Why this release matters

Skills orfas (sem incentivo nos orquestradores) viram codigo morto
silencioso: ocupam espaco no install, complicam descoberta, mas
raramente sao acionadas. A auditoria desta release decidiu o destino
de cada uma das 24 skills "complementares" do toolkit:

- 13 ACTIVE (ja integradas — sem mudanca)
- 9 incentivadas via orquestradores (3 gates SDD + 6 go-* via
  execute-task/review-task)
- 4 mantidas standalone (`bugfix`, `advisor`, `image-generation`,
  `apply-insights` — uso por trigger manual cobre o caso)
- 9 deprecated (8 dotnet-* + create-use-case)
- 1 removida (`create-report`)

## [3.11.0] - 2026-05-19

Enforcement runtime do protocolo pre-flight constitution-conflict
(orchestrator.md §5.b). O hardening v3.8.0 documentou em texto que o
orquestrador deve emitir BloqueioHumano antes de invocar
`Skill(constitution)` quando `pipeline.sh constitution-conflict`
retorna exit=2, mas nao havia trava no runtime — dec-004 do projeto
github-pages-cstk-manual provou empiricamente que o agente pode
detectar exit=2 corretamente, listar as 3 opcoes canonicas, e ainda
assim decidir sozinho em Auto Mode (`--score 2`) e invocar a skill
sem aguardar resposta humana. Esta release fecha os dois caminhos de
bypass no runtime, sem mudar comportamento legitimo.

### Added

- **Trava em `state-decisions.sh register`**: quando `--opcoes` contem
  as 3 strings canonicas do BloqueioHumano pre-flight
  (`atualizar-global-via-bump-SemVer`,
  `criar-feature-delta-com-sync-impact-report`,
  `abortar-feature-sem-principios-proprios`), exige `--score 0`. Score
  maior reproduz dec-004 e e rejeitado com exit 1 + mensagem
  detalhada apontando para a sequencia correta (registrar score 0 →
  `bloqueios.sh register` → aguardar humano →
  `pipeline.sh require-blockade-resolved` → invocar skill).
- **`pipeline.sh require-blockade-resolved --state-dir SD --etapa STAGE`**:
  novo subcomando que valida cadeia decisao→bloqueio→resposta humana
  antes da invocacao da skill. Para `--etapa constitution`:
  - exit 0 se bloqueio respondido com `atualizar-global-via-bump-SemVer`
    ou `criar-feature-delta-com-sync-impact-report`;
  - exit 1 com diagnostico em stderr (`status: missing-preflight-decision`
    / `missing-blockade` / `blockade-pending` / `blockade-resolved-abort`
    / `blockade-invalid-response`) caso contrario;
  - outras etapas retornam `status: not-enforced` exit 0
    (extensivel para futuros protocolos).

### Changed

- **`global/agents/agente-00c-orchestrator.md` §5.b**: instrucao
  OBRIGATORIA para rodar `pipeline.sh require-blockade-resolved`
  antes de cada `Skill(constitution)`. Inclui descricao dos exit
  codes + referencia historica ao bypass dec-004 que motivou o
  enforcement.

### Tests

- 5 novos cenarios em `tests/test_state-decisions.sh` (22 total)
  cobrindo: rejeicao com 3 opcoes canonicas + score=2; aceitacao com
  score=0; ordem das opcoes irrelevante; backward-compat para
  decisoes posteriores (tipo ratificacao) com etapa=constitution mas
  opcoes diferentes; subconjunto parcial das canonicas nao dispara
  trava.
- 8 novos cenarios em `tests/test_pipeline.sh` (35 total) cobrindo:
  etapa nao-enforcada retorna 0; ausencia de decisao pre-flight
  falha; decisao sem bloqueio FK falha; bloqueio aguardando falha;
  respondido com criar-delta passa; respondido com atualizar-global
  passa; respondido com abortar falha; resposta nao-canonica falha.
- Suite completa: 639 PASS / 0 FAIL / 0 ORPHANS.

## [3.10.0] - 2026-05-19

Upgrade do `cstk session start`: nova flag `--claude` que, apos criar
a worktree isolada, entra no diretorio e dispara o Claude Code via
`exec claude`. Atalho para o fluxo mais comum (`cstk session start X
&& cd ../<repo>-X && claude`) em um unico comando.

### Added

- **`cstk session start <name> --claude`**: apos setup da sessao
  (worktree + branch + `.claude/` filtrado), faz `cd` para o path
  da sessao e substitui o processo cstk por `claude` (TTY herdado
  diretamente, sem shell intermediario). Combinavel com `--reset`,
  `--reuse` e `--force`. Quando `claude` nao esta no PATH, retorna
  exit 1 com hint manual (`cd <path> && claude`) — a sessao ja foi
  criada antes do launch, entao a falha e parcial e reversivel.

### Tests

- 3 novos scenarios em `tests/cstk/test_session.sh` (60 total na
  suite session, 626 no toolkit completo):
  - `scenario_start_claude_flag_launches_claude_binary`: stub de
    `claude` confirma que o CWD do exec e o path da sessao.
  - `scenario_start_claude_flag_missing_binary_exit_1`: PATH isolado
    sem `claude` retorna exit 1; sessao foi criada antes da falha.
  - `scenario_start_claude_flag_in_help_text`: help documenta a flag.

## [3.9.1] - 2026-05-19

Hotfix do release v3.9.0 — pipeline `release.yml` falhou em CI Ubuntu
por 2 testes ambient-specific. Sem mudanca de comportamento de feature.

### Fixed

- **`_session_pr` ordem de validacao**: spec FR-009 declara ordem
  `(a) sessao, (b) commits, (c) gh`. Implementacao inicial tinha gh
  check antes de commits check, fazendo `scenario_pr_no_commits_exit_13`
  retornar 12 (unauth) em vez de 13 (sem commits) em ambientes onde
  `gh auth status` falha (CI Ubuntu sem credenciais). Validacao local
  agora tem precedencia sobre dep externa, alinhado a spec.
- **Teste `scenario_pr_gh_not_installed_exit_11`**: PATH=/usr/bin:/bin
  incluia gh no CI Ubuntu (/usr/bin/gh). Refatorado para criar diretorio
  `isolated-bin` com symlinks apenas para essentials (git/sh/sed/etc),
  garantidamente sem gh — robusto entre macOS (brew em /opt/homebrew) e
  Ubuntu (apt em /usr/bin).

## [3.9.0] - 2026-05-19

Subcomando `cstk session` — sessoes paralelas isoladas via `git worktree`,
resolvendo colisao de working tree, branch HEAD e
`.claude/agente-00c-state/` quando o usuario abre multiplas features
simultaneas no mesmo repositorio. 4 verbos (`start`/`list`/`end`/`pr`),
zero dependencias alem de `git` + `gh` (dep opcional confinada em
`cli/lib/session.sh` sob amendment 1.1.0 da Constitution).

### Added

- **`cstk session start <name> [--reset|--reuse] [--force]`**: cria
  worktree em `<parent>/<repo>-<name>/` com branch resolvida segundo
  5 regras (nova / rastreando origin / reutilizar local / recriar
  com --reset / forcar com --reuse). Copia `.claude/` filtrado
  excluindo 8 artefatos runtime/per-env (agente-00c-state/,
  agente-00c-archive/, insights/, settings.local.json,
  agente-00c-whitelist, agente-00c-report.md,
  agente-00c-suggestions.md, .agente-00c-state.lock). `--reset` com
  commits nao-mergeados emite prompt interativo (bypassavel com
  `--force`).
- **`cstk session list [--json]`**: tabela com `NAME BRANCH IDLE
  STATUS PATH`; marcadores combinaveis `CURRENT,*,STALE`. Modo JSON
  emite array camelCase (`name`/`branch`/`path`/`idleDays`/`dirty`/
  `stale`/`current`) sem rodape. Ordenacao por idle ASC. Rodape "tip:
  rode 'git worktree prune'..." se houver STALE.
- **`cstk session end <name> [--force]`**: remove worktree + branch
  local com guards. Prompt interativo se ha mudancas nao commitadas,
  commits nao pushados ou PR aberto no GitHub. Detecta self-end
  (rodando de dentro da worktree-alvo → exit 14). `gh` opcional —
  ausente/unauth pula PR check com warning e prossegue.
- **`cstk session pr <name> [--draft] [--title T] [--body B] [--reviewer USER]`**:
  push + abre PR via `gh pr create`. Idempotente: se PR ja existe
  (OPEN/MERGED), retorna URL existente sem criar duplicata. Detecta
  default branch via `git symbolic-ref refs/remotes/origin/HEAD`
  (fallback `main`). Falha parcial (push OK + gh create falhou)
  emite stderr orientativo com comandos de recovery.
- **Boot-check `git >= 2.36`**: necessario para campo `prunable` em
  `git worktree list --porcelain`. Versao inferior → exit 15 com
  mensagem de upgrade.
- **15 exit codes especificos**: 5 (nome invalido), 6 (sessao ja
  existe), 7 (path ocupado), 8 (branch mergeada), 9 (sessao nao
  encontrada), 10 (cancelado), 11 (gh ausente), 12 (gh unauth), 13
  (sem commits), 14 (self-end), 15 (git antigo). Todos documentados
  em `contracts/cli-session.md` e exercitados por cenarios
  automatizados.
- **57 cenarios de teste** em `tests/cstk/test_session.sh` cobrindo
  os 4 subcomandos + helpers + dispatch + E2E + lint meta. 2
  cenarios de PR marcados como MANUAL (exigem rede + repo remoto
  GitHub).

### Changed

- **`cli/cstk` dispatcher**: adicionada `session` em 3 lugares
  (linha 159 case help, linha 196 dispatch principal, linha 141
  secao COMANDOS do help geral).
- **`README.md`**: nova secao "Sessoes paralelas" com exemplos e
  referencias para spec + contracts.
- **`CLAUDE.md`**: secao curta "Sessoes paralelas (cstk session)"
  apontando para a spec.

## [3.8.0] - 2026-05-19

Hardening do agente-00C contra dois bypasses encontrados em
`exec-2026-05-18-iniciacao-membro-rolledback`: (1) constitution raiz
ignorada com feature-delta silencioso (dec-004) e (2) `tasks.md` gerado
in-process sem invocar a skill `create-tasks` (dec-014). O fix endurece
`pipeline.sh detect-completion`, adiciona novo subcomando
`constitution-conflict` e introduz audit trail de invocacao de skills
via `state-ondas.sh record-skill`.

### Added

- **`pipeline.sh constitution-conflict`**: novo subcomando que detecta
  4 estados entre `docs/constitution.md` raiz e feature constitution
  (none-exists / pre-skill-alert / conflict / coordinated). Exit 2
  obriga o orquestrador a emitir BloqueioHumano com 3 opcoes
  (atualizar global via bump SemVer / criar feature-delta com Sync
  Impact Report / abortar) antes de invocar a skill `constitution`.
  Exit 1 sinaliza feature constitution silenciosa sem `Predecessor:`
  no header.
- **`state-ondas.sh record-skill`**: subcomando que registra invocacao
  formal de skill via tool Skill em `.ondas[-1].skills_invoked = [...]`.
  Idempotente para mesma combinacao (skill + decisao_id). Permite que
  `review-task` (e auditorias) identifiquem o anti-padrao "etapa
  marcada completa mas skill canonica nunca foi invocada".
- **`.ondas[N].skills_invoked: []`**: novo campo no schema do
  `state.json`, inicializado em `state-ondas.sh start`. Backward
  compatible — states pre-existentes nao quebram.
- **Regras 5.a/5.b/5.c/5.d/5.e no `agente-00c-orchestrator.md`**:
  invocacao via tool Skill OBRIGATORIA para `briefing`, `constitution`,
  `create-tasks`. Constitution exige pre-flight com
  `constitution-conflict` antes de chamar a skill. Cada etapa SDD chama
  `record-skill` apos a invocacao bem-sucedida.
- **19 novos cenarios de teste**: 13 em `test_pipeline.sh` (validacao
  briefing/tasks + 4 cenarios constitution-conflict + 2 cenarios de
  detect-completion constitution) e 7 em `test_state-ondas.sh`
  (record-skill: append, idempotencia, multi-skill, sem decisao_id,
  sem onda, validacao de flags, init com skills_invoked vazio).

### Changed

- **`pipeline.sh detect-completion --stage briefing`** agora valida
  estrutura minima do template (header `# (Project )?Briefing` + >=4
  secoes nucleares: Visao/Usuarios/Escopo/Prioridades/Restricoes/
  Stack/Qualidade/Futuro). Antes aceitava qualquer arquivo presente.
  Razao: defesa contra briefings rasos gerados in-process.
- **`pipeline.sh detect-completion --stage create-tasks`** agora valida
  estrutura do template da skill `create-tasks`: cabecalho `# Tarefas`
  ou `# Tasks`, presenca de `## FASE N`, legendas `[C]/[A]/[M]` (NAO
  aceita `P0/P1/P2/P3`), `## Matriz de Dependencias`,
  `## Resumo Quantitativo`, `## Escopo Coberto` e `## Escopo Excluido`.
  Antes so checava existencia do arquivo.
- **`pipeline.sh detect-completion --stage constitution`** quando raiz
  e feature constitution coexistem: agora exige header com
  `Predecessor:` ou referencia a `docs/constitution.md` nas primeiras
  30 linhas. Sem essa coordenacao explicita, retorna exit 1 com
  mensagem orientando o operador.

### Fixed

- **Bypass de skills SDD** (dec-004 + dec-014 da execucao-fonte): o
  orquestrador podia gerar `constitution.md` (feature-delta) e
  `tasks.md` direto via Write/Edit, sem invocar a skill canonica e sem
  detect-completion sinalizar problema. O artefato resultante drifa
  do template oficial — no caso real, `tasks.md` saiu sem Matriz de
  Dependencias / Resumo / Escopo, e a feature constitution criou 8
  principios proprios sem coordenacao com a global v1.0.0. Os 3
  gates novos (constitution-conflict + validacao estrutural + skills_invoked
  tracking) fecham esse furo em camadas: pre-flight bloqueia, validacao
  rejeita artefato fora-do-padrao, audit trail expoe etapa marcada
  completa sem skill invocada.

## [3.7.0] - 2026-05-16

Enriquecimento significativo da skill `owasp-security` com atualizacoes
posteriores a Janeiro/2026, incorporando 9 novas listas/standards e 6
mencoes de cobertura complementar. Reestruturada em `SKILL.md` (entry
point operacional) + 5 arquivos de referencia profunda em
`references/`, mantendo carregamento de contexto enxuto sem perder
profundidade.

### Added

- **OWASP LLM Top 10:2025**: nova secao irma a Agentic 2026 cobrindo
  riscos a nivel-modelo (LLM01 Prompt Injection, ..., LLM07 System
  Prompt Leakage, LLM08 Vector/Embedding Weaknesses, LLM10 Unbounded
  Consumption). Detalha indirect prompt injection (+32% Nov-2025 a
  Feb-2026 per Google), poisoning de RAG e inversao de embeddings.
- **OWASP API Security Top 10:2023**: secao completa com API1 BOLA,
  API3 BOPLA (mass assignment + excessive exposure), API6 Sensitive
  Business Flow Abuse, API7 SSRF (incluindo metadata-service guards) e
  API10 Unsafe Third-Party Consumption. Inclui patterns Python para
  cada risco.
- **OWASP CI/CD Top 10**: CICD-SEC-1..10 com deep dive em PPE (Direct,
  Indirect, Public), modern credential hygiene (OIDC federation, ESO,
  dynamic creds via Vault) e SLSA/Sigstore para integridade de
  artefato.
- **NIST SP 800-63B-4 (Final 31-Jul-2025)**: substitui aluso vaga por
  regras concretas — passwords 15 chars no AAL2, SHALL NOT impor
  composition rules, SHALL NOT requerer rotacao periodica, SHALL
  checar contra breached-password lists, SHALL NOT usar KBA recovery.
  Nova Section 5.3 Session Monitoring com reauth 12h/30min e
  step-up auth.
- **WebAuthn / Passkeys**: nova subsecao substituindo "MFA generico".
  Cobre WebAuthn L3 Working Draft (Jan-2025), passkeys como AAL2
  syncable authenticators, server-side requirements e armadilhas
  (origin check, sign-count monotonicity, cross-origin iframes).
- **OAuth 2.1 + FAPI 2.0**: cobertura de OAuth 2.1 (PKCE mandatory,
  implicit/password grants removidos), DPoP (RFC 9449) sender-
  constraining, PAR (RFC 9126), JAR (RFC 9101) e FAPI 2.0 Security
  Profile Final (19-Feb-2025) para APIs high-stakes.
- **MCP Authorization Spec (Jun-2025)**: expansao do ASI04 cobrindo
  RFC 8707 Resource Indicators, DPoP em MCP, ataque "confused deputy"
  em proxy servers e sanitizacao de tool descriptions. Checklist
  especifico para review de servidores MCP.
- **Post-Quantum Cryptography**: nova secao cobrindo FIPS 203 ML-KEM,
  204 ML-DSA, 205 SLH-DSA (publicadas 13-Ago-2024). Estrategia HNDL
  (Harvest-Now-Decrypt-Later), crypto agility, hybrid TLS
  (X25519+ML-KEM-768), timeline NIST IR 8547 e CNSA 2.0 (mandatory
  US-gov 2030-01-02).
- **Secrets Management 2026**: OIDC federation (GitHub Actions ↔ AWS
  STS), Workload Identity, External Secrets Operator, dynamic
  database credentials via Vault, SOPS/Sealed Secrets para GitOps,
  gitleaks/trufflehog em pre-commit + push protection.
- **CWE Top 25:2025 (CISA/MITRE, Dez-2025)**: tabela com top 25 + 
  mapeamento para OWASP Top 10:2025. Destaques: CWE-862 Missing
  Authorization subiu 5 posicoes, CWE-79 XSS retomou #1.
- **Modern prompt injection patterns**: indirect injection no wild
  (+32% trimestre), many-shot jailbreaking (exploits >128k context),
  tool-empowered jailbreaks (chains que individualmente parecem
  benignas). Cita pesquisa do Google e Anthropic.
- **MAESTRO threat modeling**: framework do Cloud Security Alliance
  (Fev-2025) estendendo STRIDE com camada AI-agent-specific. 7 layers
  de modelagem: foundation model, data, agent framework, tools,
  multi-agent orchestration, application logic, user/UI.
- **OWASP Mobile Top 10:2024 + MASVS 2.1**: cobertura M1-M10 com
  exemplos plataforma-especificos (Keychain iOS, EncryptedSharedPrefs
  Android, cert pinning OkHttp com backup pin).
- **OWASP Kubernetes Top 10 + Docker Top 10**: K01-K10 com Pod
  Security Standards (`restricted`), NetworkPolicy default deny,
  OPA/Kyverno admission policies, Falco runtime, distroless base
  images.
- **EU AI Act mapping**: regulation 2024/1689 com risk tiers
  (unacceptable/high-risk/limited/minimal/GPAI), obrigacoes vigentes
  desde 2-Ago-2025, multas ate EUR35M ou 7% turnover. Overlap com
  OWASP LLM Top 10 e Agentic 2026.

### Changed

- **`SKILL.md` reorganizado**: cabecalho `description` expandido para
  incluir 12+ novos triggers (passkey, FAPI, post-quantum, MCP
  security, prompt injection). Adicionada secao "Deep references"
  no topo apontando para `references/*.md`. Checklists de Auth,
  Data Protection e Agentic AI reescritos para refletir 2026 best
  practices (passkeys-first, OIDC federation, MCP OAuth 2.1).
  Gotchas atualizados com 5 regras novas (NIST 800-63B-4 no-rotation,
  passkey-first, MCP OAuth 2.1+RFC 8707+DPoP, PQC inventory now,
  LLM+Agentic complementares).
- **`OWASP-2025-2026-Report.md` expandido**: TOC reorganizado em 11
  secoes (era 5). ASVS V2.1.1 atualizado de "12 chars" para "12+
  (NIST 800-63B-4 raises to 15 for AAL2)". 6 novas secoes inseridas:
  API Security Top 10:2023, CI/CD Top 10, LLM Top 10:2025, NIST
  SP 800-63B-4 highlights, Post-Quantum Cryptography, CWE Top 25:2025.
  Sources reorganizadas por categoria (OWASP / Auth / Crypto / AI /
  Regulatory / Standards). Data atualizada para Maio/2026.
- **`README.md` linha de descricao da skill**: expandida para listar
  todas as 12 listas/standards cobertas (era apenas 3).

### Files

- `global/skills/owasp-security/SKILL.md` — 680 linhas (+110 vs 3.6.0)
- `global/skills/owasp-security/OWASP-2025-2026-Report.md` — 1061
  linhas (+269 vs 3.6.0)
- `global/skills/owasp-security/references/llm-agentic.md` — NOVO,
  273 linhas
- `global/skills/owasp-security/references/api-cicd.md` — NOVO,
  275 linhas
- `global/skills/owasp-security/references/auth-modern.md` — NOVO,
  277 linhas
- `global/skills/owasp-security/references/crypto-modern.md` — NOVO,
  198 linhas
- `global/skills/owasp-security/references/extras.md` — NOVO,
  223 linhas

## [3.6.0] - 2026-05-15

Evolucao pos-execucao do agente-00c — 14 recomendacoes priorizadas
derivadas da primeira execucao real (60 ondas, 224 decisoes,
exec-2026-05-11T19-59-58Z). Backlog completo em
`docs/specs/agente-00c-evolucao/tasks.md`; analise-fonte em
`docs/01-briefing-discovery/agente-00c-analise-licoes-aprendidas.md`.

### Added

- **FASE 1 P0 — Validacao empirica obrigatoria para `score=3`**:
  `state-decisions.sh register --score 3` agora EXIGE `--evidencia`
  (>=20 chars com comando empirico + fragmento literal do output).
  Sem evidencia, exit 1 com violacao de Principio I. Razao: 3
  decisoes historicas `score=3` afirmaram premissa tecnica falsa sem
  rodar tsc/test/grep. Adiciona Etapa 0 "Validacao Empirica de
  Premissas" no `execute-task/SKILL.md` e §Score-de-decisao no
  orchestrator.
- **FASE 1 P0 — Drift detector refatorado**: matcher bidirecional
  via tokens (`mcp-jira` casa com `integracao-bidirecional-mcp-jira`),
  3 camadas de aspectos (`iniciais` / `tecnicos` / `operacionais`),
  janela movel de 12 ondas (warn>=5 untouched, abort>=8) substitui o
  gatilho antigo de "5 consecutivas". Novos subcomandos
  `drift.sh mark-touched --aspecto X` e `drift.sh debug [--onda ID]`.
  Init aceita `--tecnicos`, `--operacionais` e `--force`.
- **FASE 1 P0 — Secrets-filter allow-list**: novo arquivo
  `.secrets-filter-ignore` (baseline com SAML_ISSUER, OIDC_ISSUER,
  COOKIE_DOMAIN, PUBLIC_*, VITE_*, etc); suporte a wildcard de
  sufixo; auto-descoberta de override por projeto-alvo
  (`<env-dir>/.claude/agente-00c-state/secrets-filter-ignore`);
  heuristica slug-com-separador para identificadores publicos
  curtos. Razao: identificadores publicos por design (sug-005,
  sug-049) eram redatados, removendo paths legiveis do report.
- **FASE 2 P1 — Pre-flight de bootstrap no briefing**: nova secao
  em `briefing/SKILL.md` instruindo geracao de
  `scripts/bootstrap-deps.sh` para stacks multi-workspace (npm
  workspaces, Go modules, Cargo). Amortiza N bloqueios `npm install`
  cirurgicos em batch unico antes de `/agente-00c`. Documentado
  tambem em `agente-00c.md` (checklist pre-execucao com heuristica
  de gap).
- **FASE 2 P1 — Sincronizacao bidirecional `tasks.md` ↔ codigo**:
  protocolo de 3 pontos (pre-execucao, decisao→sub-FASE, hook
  pos-onda) em `create-tasks/SKILL.md`; Etapa 9.3 nova em
  `execute-task/SKILL.md`; hook pos-detect-completion no
  orchestrator emitindo Decisao informativa quando diff vs checkbox
  diverge. Subsecao "Paridade de tipos compartilhados" (sug-028).
- **FASE 2 P1 — Mapeamento etapa → aspecto-chave automatizado**:
  novo subcomando `state-rw.sh infer-aspectos
  [--projeto-alvo-path PATH]` que aplica matcher fuzzy bidirecional
  (mesma logica do drift.sh) contra `git diff --name-only
  HEAD~1..HEAD` para inferir aspectos tocados pela onda. Orchestrator
  chama no hook pos-detect-completion + persiste em
  `.ondas[-1].aspectos_chave_tocados`. Tabela de fallback etapa →
  aspecto-tipico documentada.
- **FASE 3 P2 — Convencoes de Borda no plan**: nova ETAPA 5.4 em
  `plan/SKILL.md` exigindo tabela `Camada | Case style | Validacao |
  Fonte da verdade` para features com 2+ camadas. Roundtrip E2E
  obrigatorio no `quickstart.md` (chamada real, nao mock) para
  features com borda backend↔frontend. Novo pass G "Convencoes de
  Borda" em `analyze/SKILL.md`.
- **FASE 3 P2 — Decisoes de Infraestrutura Auditaveis no specify**:
  checklist de 6 itens (scheduling, key rotation, refresh policy,
  mutex multi-pod, backup/restore, idempotencia) virando FRs
  `FR-NN-INFRA-X` explicitos. `clarify/SKILL.md` ganhou categoria
  INFRA + reordenou prioridade (INFRA acima de UX).
- **FASE 3 P2 — Init de aspectos no briefing**: orchestrator §"Init
  de aspectos-chave (primeira onda apenas)" chama `drift.sh init`
  com 3 camadas apos briefing concluido. `/agente-00c-resume` aceita
  `--init-aspectos`, `--init-aspectos-tecnicos`,
  `--init-aspectos-operacionais` para execucoes legadas (relaxa
  idempotencia via `--force`).
- **FASE 4 P3 — Marco-aware retro a cada 25 ondas**: hook no passo
  10 do orchestrator emite bloqueio leve perguntando ao operador se
  deseja retro proativa em multiplos de 25 ondas. Atualiza
  `.proximo_marco_retrospectiva` no estado.
- **FASE 4 P3 — Schedule intent literal vs sentinel**: tabela do
  passo 11 do orchestrator ganhou coluna "Slash command pai".
  Pipelines de `/agente-00c-resume` usam `prompt` literal
  (`/agente-00c-resume --projeto-alvo-path <PAP>`), nao sentinel
  `<<autonomous-loop-dynamic>>` (que so funciona quando `/loop` e o
  pai).
- **FASE 4 P3 — Perfil `--runbook` no validate-documentation**:
  validacao de frontmatter (`title: RB-\d{3}:`, severidade,
  tempo-estimado, pre-requisitos), 6 secoes obrigatorias (incluindo
  Rollback quando severidade=critica), check de placeholders
  residuais (TODO/XXX/FIXME) e cross-refs validos.
- **FASE 4 P3 — Dry-run de Agent tool em clarify (orchestrator
  §5.a)**: antes do spawn de clarify-asker, verifica disponibilidade
  da tool Agent; se ausente, registra Decisao EXPLICITA de downgrade
  in-process (evita silent-fallback documentado em dec-006).
  `clarify/SKILL.md` ganhou secao "Modos de invocacao" referenciando
  o orchestrator.
- **FASE 4 P3 — Sistema canonico de tracking**: nova secao no topo
  do orchestrator instruindo a IGNORAR system-reminders sobre
  `TaskCreate`/`TaskUpdate`. Razao (sug-029): 8+ reminders em uma so
  onda historica; `state.json` + `state-decisions.sh` sao o sistema
  canonico (auditavel via 5 campos + score). Investigacao sobre hook
  do harness em `docs/specs/agente-00c-evolucao/notas-harness-hook.md`
  (conclusao: nao viavel hoje).

### Changed

- **BREAKING (interno) — `drift.sh check` muda semantica**: antes
  contava ondas CONSECUTIVAS sem aspecto (5 = abort); agora conta
  untouched em JANELA MOVEL das ultimas 12 ondas (5..7 = warn, >=8 =
  abort). Backbone tecnico intercalado (FASE 4.x) nao dispara mais
  abort. Stdout do `check` agora e numero de untouched na janela, nao
  consecutivas. Tests atualizados (21 cenarios, 21/21 verdes).
  Overrides via env: `DRIFT_WINDOW_SIZE`, `DRIFT_WARN_THRESHOLD`,
  `DRIFT_ABORT_THRESHOLD`.
- **BREAKING (interno) — schema do state.json**: adicionados
  campos opcionais `.aspectos_chave_tecnicos`,
  `.aspectos_chave_operacionais`, `.proximo_marco_retrospectiva`, e
  `.decisoes[].evidencia`. Backward-compatible para read; writers
  antigos que nao emitirem esses campos continuam funcionando.
- **BREAKING (interno) — `state-decisions.sh register` rejeita
  `score=3` sem `--evidencia`**: chamadas anteriores que emitiam
  `score=3` sem evidencia agora falham com exit 1. Para preservar
  comportamento antigo, baixar para `score=2` (que permanece valido
  sem evidencia).

### Fixed

- Drift detector deixava de detectar aspectos quando o aspecto era
  string longa contendo o token presente no texto (`integracao-
  bidirecional-mcp-jira` vs texto "mcp-jira ok"). Matcher
  bidirecional via tokens resolve.
- `SAML_ISSUER`, `COOKIE_DOMAIN`, `OIDC_ISSUER` (publicos por design)
  eram redatados como secrets, removendo paths legiveis do report.

### Testing

- `./tests/run.sh` full suite: **548 PASS / 0 FAIL / 0 ERROR / 0
  ORPHANS** apos a evolucao (+15 cenarios novos cobrindo evidencia
  score=3, drift fuzzy/camadas/janela/mark-touched/debug,
  secrets-filter allow-list/slug, e infer-aspectos).

## [3.5.3] - 2026-05-12

### Fixed

- **`cstk update` nao sincronizava `commands/` e `agents/`**: a funcao
  `update_main` em `cli/lib/update.sh` so iterava o manifest de skills.
  Commands e agents (infraestrutura global do toolkit, distribuida pelo
  install via `_install_apply_extra_kinds`) ficavam congelados em drift
  permanente apos a primeira instalacao. Sintoma reportado: orchestrator
  do agente-00C continuava emitindo "ScheduleWakeup nao disponivel neste
  harness" mesmo apos `cstk update`, porque o fix do commit 56b3959
  (orchestrator retorna `Schedule intent` em vez de invocar
  `ScheduleWakeup`) nunca alcancava o disco do usuario.

  Fix: novo `_update_apply_extra_kinds` espelha o do install, com
  semantica de update completa:
  - Idempotencia: release == manifest -> zero writes (mtime preservado)
  - Edit local: respeita `--force` (sobrescreve) e `--keep` (silencia);
    sem flag, conta em `skipped_edits` e propaga exit 4
  - Third-party (.md fora do manifest dedicado por kind): preservado
    por default; `--force` sobrescreve — caminho de recuperacao para
    instalacoes historicas em que o manifest dedicado por kind nunca
    foi criado
  - Manifest de skills vazio nao impede mais processar commands/agents
  - Summary reporta linhas `commands: ...` e `agents: ...` com seis
    counters (installed/updated/uptodate/kept/skipped/preserved)

  Help text de `cstk update --help` atualizado para refletir o escopo.
  Cobertura: 9 cenarios novos em `tests/cstk/test_update-extra-kinds.sh`
  (idempotencia, atualizacao real, third-party com/sem `--force`,
  edit local com `--force`/`--keep`/exit 4, dry-run zero writes,
  compat com tarball historico sem commands/agents). 12 cenarios
  existentes em `test_update.sh` continuam verdes.

- **agente-00c-orchestrator emitia `Schedule intent: none` mesmo com
  status `em_andamento`**: a nota explicativa do prompt comecava com
  "POR QUE NAO HA ScheduleWakeup AQUI" e descrevia o problema em tom
  negativo ("qualquer ScheduleWakeup invocado aqui firmaria — se
  firmasse — para um contexto ja extinto"). O LLM, executando como
  sub-agent, parafraseava essa explicacao e raciocinava "schedule nao
  funciona aqui, motivo=ScheduleWakeup_indisponivel" — emitindo
  `Schedule intent: none; motivo=ScheduleWakeup_indisponivel` mesmo
  quando deveria emitir `delaySeconds=...`. O slash command pai
  reproduzia a frase invalida ("Proxima onda agendada: nenhuma —
  ScheduleWakeup indisponivel; retomar via /agente-00c-resume"),
  efetivamente desabilitando schedule automatico.

  Fix em `global/agents/agente-00c-orchestrator.md`:
  - Nota de topo reescrita em tom positivo: "Schedule SEMPRE funciona.
    Voce decide os parametros, o pai executa." Lista explicita de
    antipadroes ("NUNCA emita `Schedule intent: none` com motivo
    `ScheduleWakeup indisponivel` ou similar").
  - Passo 11 reescrito: tabela de decisao expandida com coluna
    "Bloqueios pendentes" e marca **OBRIGATORIO** para o caso
    `em_andamento + 0 bloqueios`. Reforco final: "NUNCA emita
    `Schedule intent: none` com motivo `ScheduleWakeup_*`".

## [3.5.2] - 2026-05-12

### Fixed

- **`cstk 00c`: Ctrl+C nao abortava prompts limpo (#2)**: `trap
  '_00c_release_lock' EXIT INT TERM` rodava o cleanup mas nao chamava
  `exit`. POSIX consume o sinal apos o trap; `read -r` no loop de
  validacao retornava empty e o while prosseguia pedindo input —
  operador ficava preso no prompt e Ctrl+\ (SIGQUIT) era o unico escape,
  orfanando o lock per-path.

  Fix: split em duas traps. `EXIT` chama `_00c_release_lock` (cleanup);
  `INT`/`TERM` chamam `exit 130`/`exit 143`, que disparam o EXIT trap
  em sequencia. Operador sai com exit code POSIX correto e lock
  liberado.

  Regressao coberta via self-signal `kill -INT $$` em
  `scenario_issue_2_sigint_propaga_exit_130` (SIGINT real em background
  jobs nao eh testavel em POSIX sh por causa do SIG_IGN inherit).

- **agente-00c: pipeline.sh detect-completion nao reconhecia paths do
  `/initialize-docs` (#3)**: `detect-completion` so olhava em
  `--feature-dir` (`docs/specs/<feature>/`), mas as skills `briefing`
  e `constitution` salvam em paths project-level da hierarquia numerada:
  briefing -> `docs/01-briefing-discovery/briefing.md`, constitution ->
  `docs/constitution.md`. Orchestrator nunca detectava conclusao dessas
  etapas; double-write workaround duplicava o artefato em dois locais
  (suggestion `sug-001` da smoke v3.5.0).

  Fix: novo flag opcional `--projeto-alvo-path PAP` em
  `detect-completion`. Para briefing/constitution, paths do
  `/initialize-docs` sao aceitos como fallback alem do feature-dir.
  Orchestrator (`Loop principal item 6`) passa o PAP em todas as
  chamadas. Skills `briefing`/`constitution` permanecem inalteradas
  — caminho canonical delas continua nos paths numerados (decisao
  consciente: artefatos project-level separados de feature-level).

## [3.5.1] - 2026-05-12

### Fixed

- **`/agente-00c` falhava em install default por falta da skill
  `agente-00c-runtime`**: a runtime (infra interna que provê
  `state-rw.sh`, `path-guard.sh`, `whitelist-validate.sh` etc. ao
  orchestrator) so constava no profile `all` — `cstk install` default
  (profile `sdd`) instalava comandos e agentes do 00C mas deixava a
  runtime de fora. Resultado: `/agente-00c` falhava na primeira chamada
  Bash do orchestrator com referencia a script ausente.

  Tres camadas de fix:

  - `scripts/profiles.txt.in`: `agente-00c-runtime` agora pertence a
    `sdd` E `complementary` (alem do `all` ja existente). Qualquer
    install default carrega a runtime junto.
  - `cli/lib/00c-bootstrap.sh::_00c_check_deps`: pre-flight do
    `cstk 00c` estende para command + runtime executavel +
    orchestrator. Antes so checava o `.md` do command — instalacao
    parcial passava silenciosa e quebrava so dentro de uma onda.
  - `global/agents/agente-00c-orchestrator.md`: nova secao "Pre-flight
    da execucao" antes do loop de onda, com Bash check programatico de
    `state-rw.sh`/`state-lock.sh`/`path-guard.sh` (+x). Substitui a
    interpretacao em natural-language que estava produzindo
    diagnosticos hallucinados.

  Regression test em `tests/cstk/test_build-release.sh` garante que o
  profile `sdd` inclui `agente-00c-runtime` permanentemente.

- **Orchestrator (sub-agent) nao pode invocar `ScheduleWakeup` de forma
  sobrevivente**: o thread do sub-agent termina ao retornar o sumario
  para o slash command pai. Qualquer wakeup agendado pelo orchestrator
  firmaria — se firmasse — para contexto ja extinto. O resultado era o
  erro recorrente `Proxima onda agendada: nenhuma (ScheduleWakeup
  indisponivel — operador retoma via agente-00c-resume)`.

  Refactor para o padrao decide-aqui-executa-la:

  - `global/agents/agente-00c-orchestrator.md`: `ScheduleWakeup`
    removido de `allowed-tools`. Step 11 reescrito — orchestrator agora
    DECIDE `delaySeconds` + `reason` e grava o ISO planejado em
    `.ondas[-1].proxima_onda_agendada_para`. Step 13 (sumario)
    formaliza linha `Schedule intent: delaySeconds=N; reason="..."; prompt="..."`
    (ou `Schedule intent: none; motivo=<X>`) que o pai parseia.
  - `global/commands/agente-00c.md` e `global/commands/agente-00c-resume.md`:
    `ScheduleWakeup` adicionado ao `allowed-tools`. Novo step "Schedule
    da proxima onda" parseia a linha do sumario do orchestrator e
    invoca `ScheduleWakeup` no thread do pai. Em caso de falha, limpa
    `.ondas[-1].proxima_onda_agendada_para` via `state-rw.sh set`.

  Comportamento externo: `/agente-00c` e `/agente-00c-resume` agora
  realmente agendam a proxima onda quando o status e `em_andamento` sem
  bloqueios. O sumario ao operador mostra ISO real do wakeup, nao
  intencao do sub-agent.

## [3.5.0] - 2026-05-09

### Added

- **Subcomando `cstk 00c <path>` — bootstrap interativo do agente-00C
  (FASE 12 do `cstk-cli`)**: atalho recomendado para iniciar uma sessao
  do agente-00C. Cria diretorio do projeto-alvo, valida path, coleta
  parametros via prompts (descricao, stack JSON, whitelist de URLs) e
  invoca `claude` ja com `/agente-00c '<args>'` auto-submetido como
  primeiro turno. Elimina friccao de `mkdir`/`cd` + memorizar a sintaxe
  da slash command.

  - **Validacao defensiva** (FR-016b): rejeita path traversal `..`,
    rejeita 14 zonas de sistema (`/`, `/etc`, `/usr`, `/var`, `/bin`,
    `/sbin`, `/boot`, `/proc`, `/sys`, `~/.ssh`, `~/.gnupg`, `~/.aws`,
    `~/.config/claude` + canonicas e resolvidas no macOS); resolve
    symlinks via `realpath -m` (fallback POSIX `cd -P` para BSD).
    `<path>` exato em `$HOME` rejeitado, mas paths INSIDE `$HOME` sao
    permitidos.
  - **TTY-only** (FR-016a): subcomando recusa execucao em pipe/CI;
    `[ -t 0 ] && [ -t 1 ]`. Stderr pode ser redirecionado.
  - **Dir nao-vazio = recusa direta sem prompt** (FR-016b): finalidade
    e atalho para projeto NOVO; mensagem aponta `/agente-00c-resume`
    para retomada.
  - **Lock per-path** (FR-016h, novo): `mkdir <path>/.cstk-00c.lock/`
    atomico antes de qualquer prompt; release via `trap EXIT INT TERM`
    + release explicito antes do `exec claude`. Previne race entre
    duas instancias simultaneas no mesmo `<path>`.
  - **Dep checks** (FR-016d): claude CLI no PATH; `jq` no PATH (teste
    funcional via `jq --version`); `~/.claude/commands/agente-00c.md`
    instalado — ausencia dispara prompt `[Y/n]` para auto-install via
    `cstk install` em foreground (respeita lockfile global de FR-015).
    Falha do nested install propaga exit code + razao.
  - **Sanitizacao** (FR-016g): descricao escapada para shell single-quotes
    (`'` -> `'\''`); stack JSON compactada via `jq -c`; whitelist
    persistida em `<path>/.agente-00c-whitelist.txt` (chmod 600) e
    referenciada via path absoluto em `--whitelist` (evita argv overflow).
  - **Validacao de URL na whitelist**: espelha
    `agente-00c-runtime/scripts/whitelist-validate.sh` rejeitando
    patterns overly-broad (`**` puro, `*://*`, `https://*` sem dominio,
    host vazio, sem scheme http(s), wildcard fora do prefixo
    `*.dominio.tld`).
  - **Dry-run preview obrigatorio** (FR-016e): mostra path final,
    descricao, stack, whitelist count + path, e linha exata da
    `/agente-00c` que sera invocada. Confirmacao final `[Y/n]` (default
    Y); flag `--yes` pula apenas o prompt final + auto-install.
  - **Spawn auto-submit** (FR-016f): `exec claude "$slash_command"`
    passa a slash command como argv[1]; claude processa como primeiro
    turno automatico (sem exigir Enter adicional do operador).

  Implementacao em `cli/lib/00c-bootstrap.sh` (~480 linhas POSIX puro)
  com 16 helpers privados `_00c_*` + entry point publico
  `bootstrap_00c_main`. **Special-case no dispatcher** porque POSIX
  nao permite funcao com nome iniciando em digito (`00c_main` invalido).

  Cobertura de testes: 18 cenarios em `tests/cstk/test_00c-bootstrap.sh`
  com mocks de `claude` (registra argv) e `cstk install` (controlavel).
  Cenarios cobrem path validation, TTY, deps ausentes, prompts (descricao
  9/501 chars, com `$`, com unicode, JSON malformado, URL overly-broad),
  lock pre-existente, dry-run + cancel, happy path com argv correto,
  apostrofo escapado, JSON com aspas duplas internas. Suite total:
  **505 PASS / 0 FAIL**.

### Changed

- **Carve-out 1.1.0 atualizada**: `jq` agora obrigatorio em
  `cli/lib/00c-bootstrap.sh` (era opcional em outros comandos do cstk).
  Justificativa: validacao de stack JSON (FR-016c) + dep transitiva do
  `agente-00c-runtime` que o `cstk 00c` invoca via `/agente-00c` —
  falha cedo em FR-016d e melhor UX que erro tardio dentro da sessao
  do `claude`.

- **`cstk` dispatcher e `cstk --help` atualizados** com nova entrada
  `00c <path>` listando o subcomando entre os comandos validos.

- **README.md secao Agente-00C** documenta `cstk 00c <path>` como o
  caminho preferido para iniciar sessoes do agente-00C, com nota
  apontando `/agente-00c-resume` para retomada de execucoes existentes.

## [3.4.0] - 2026-05-09

### Changed

- **`/agente-00c` faz warm-up de permissoes em batch ANTES de spawnar
  o orquestrador (post-FASE 9 feedback)**: nova passo 0 invoca todas
  as 10 skills da pipeline + 3 agentes custom + ScheduleWakeup + Bash
  helpers + Read/Write em sequencia. Cada invocacao dispara o prompt
  nativo de permissao do Claude Code uma vez, com o operador presente.
  Apos confirmacao, o orquestrador roda autonomamente sem interrupcoes
  (resolve o problema de fluxo travado quando permissoes "lazy" pediam
  aprovacao em ondas posteriores onde o operador nao estava disponivel).
  `/agente-00c-resume` e `/agente-00c-abort` NAO refazem warm-up
  (resume = continuacao, abort = operacao curta com operador
  presente). Orquestrador ganhou secao "Warm-up de permissoes
  (pre-condicao)" documentando o contrato e instruindo deteccao de
  permissao pendente no meio de uma onda como BloqueioHumano.

### Added

- **Validacao end-to-end (parcial) e licoes da implementacao do agente-00C (FASE 9)**:

  - **`scripts/quickstart-shell-sim.sh`**: simula via Bash os 10 cenarios
    do quickstart compondo as primitivas dos 14 scripts do
    `agente-00c-runtime`. NAO invoca o agente Claude — exercita apenas
    composicao shell-level. Resultado: **10/10 PASS** em ~5s. Detecta
    regressao quando um script deixa de compor com outros (gate
    complementar a `tests/run.sh` que testa cada script isoladamente).

  - **`docs/specs/_archived/agente-00c/validation-runs/`** (novo diretorio): registro
    de execucoes do agente-00C. README com template + tipos
    (shell-simulation vs end-to-end-real). Primeiro registro:
    `2026-05-06-end-to-end-shell-simulation.md` (10/10 PASS, SCs
    validaveis em shell-level: SC-001, SC-002, SC-007, SC-008).

  - **`docs/specs/_archived/agente-00c/lessons-from-implementation.md`**: 5 licoes
    concretas da implementacao das 8 fases — bug jq em pipe (drift.sh),
    dupla resolucao de symlinks no macOS (path-guard.sh), "skills
    internas" como padrao (`agente-00c-runtime`), cobertura forçada
    como ROI alto (3 bugs descobertos), estratificacao 3-camadas
    (commands/agents/scripts). Cada licao com proposta concreta de FR
    para skill especifica + avaliacao contra constitution do toolkit
    (nenhuma requer amendment).

  Subtarefas da FASE 9 atendidas autonomamente: 9.1.1-9.1.11 (10
  cenarios shell-simulated + relatorio), 9.2.1-9.2.3 (bump MINOR
  determinado, CHANGELOG/README atualizados), 9.4.1-9.4.3 (licoes da
  implementacao + propostas FR + avaliacao constitution).

  Subtarefas pendentes (exigem operador): 9.2.4 (cstk doctor pos-release
  v3.4.0), 9.3.* (primeira execucao real do agente em projeto-alvo —
  exige 1-3h wallclock + curadoria de relatorio), 9.4.4 (abertura real
  de issues no toolkit — exige autorizacao + execucao com `gh`), 9.4.5
  (atualizar threat-model com threats observados em runtime real).

- **Relatorio e integracao com toolkit do agente-00C (FASE 8)**: 28
  subtarefas implementadas em 3 novos scripts cobrindo geracao de
  relatorio com 6 secoes auditaveis, registro de Sugestoes para skills
  globais e abertura automatica de Issue no toolkit GitHub.

  - `report.sh` (FR-011 + SC-001 + FR-012): subcomandos `generate` e
    `validate`. `generate` renderiza 6 secoes obrigatorias (Resumo
    Executivo com tabela de 15 campos + paragrafo, Linha do Tempo
    com tabela de ondas, Decisoes agrupadas por agente + lista
    detalhada, Bloqueios Humanos divididos em pendentes/respondidos/
    sem, Sugestoes em 3 niveis de severidade, Licoes Aprendidas
    cravado como placeholder em parcial e preenchivel via
    `--licoes-aprendidas` + `--final`) + Apendice A com 5 paths.
    `validate` checa as 6 secoes via `grep -qF` e reporta faltantes.
    Caller deve aplicar `secrets-filter.sh scrub` em pipe (FR-030).

  - `suggestions.sh` (FR-020): subcomandos `register`, `list`,
    `count`, `next-id`, `mark-issue`, `render-md`. Sugestoes vivem
    em DOIS lugares — `state.json .sugestoes[]` (ground truth JSON)
    + agente-00c-suggestions.md (export human-readable regerado a
    cada register/mark-issue). 3 severidades validadas:
    informativa, aviso, impeditiva. Diagnostico exige >=50 chars
    para forçar detalhamento acionavel. `mark-issue` atualiza
    `.issue_aberta` + incrementa `metricas_acumuladas.issues_toolkit_abertas`.

  - `issue.sh` (FR-021): subcomandos `create`, `check-duplicate`,
    `hash`. Excecao escopada ao Principio V — apenas `gh issue
    create --repo JotJunior/claude-ai-tips`. Hash de 8 chars do
    diagnostico normalizado (lowercase + collapse whitespace + sha256
    + cut) para dedup via `gh issue list --search`. Template do
    `contracts/issue-template.md` aplicado via heredoc (Skill afetada,
    Diagnostico, Reproducao com decisoes recentes, Por que e
    impeditivo, Proposta de correcao, Anexos). Defense in depth:
    `secrets-filter.sh scrub` aplicado 2x (no build do body + antes
    do `gh create`). Labels `agente-00c,bug,skill-global` criadas
    automaticamente se ausentes (`gh label create --force`). Falha
    de `gh create` (sem internet, rate limit) propaga exit 1; corpo
    truncado em ~4000 chars com pointer ao relatorio local. `--dry-run`
    imprime template completo sem chamar `gh`.

  Agente orquestrador atualizado (passo 12 do Loop principal) com
  template operacional completo: pipe de `report.sh generate |
  secrets-filter.sh scrub > <report.md>` + `report.sh validate`,
  fluxo de Sugestao (impeditiva => `issue.sh create`), retentativa
  + bloqueio humano em falha persistente.

  27 cenarios de teste novos em
  `tests/test_{report,suggestions,issue}.sh`. `test_issue.sh` cobre
  apenas dry-run + hash (chamadas reais a `gh` evitadas para nao
  gerar issues em produçao — validacao end-to-end na FASE 9.1.6).

- **Continuacao cross-sessao do agente-00C (FASE 7)**: 20 subtarefas
  cobrindo `ScheduleWakeup` para ondas curtas, `/agente-00c-resume`,
  fallback `/schedule` Routines para pausas longas, e
  `/agente-00c-abort`. Sem novos scripts — todas as primitivas
  necessarias ja existem nas FASES 2-6 (state-rw, state-validate,
  state-lock, bloqueios, sanitize, secrets-filter, state-ondas).

  - **`global/agents/agente-00c-orchestrator.md`** — passo 11 expandido:
    `ScheduleWakeup` invocado APENAS para ondas nao-terminais sem
    bloqueios pendentes; tabela de calibracao de `delaySeconds`
    respeitando cache Anthropic (5min TTL): 60-270s para continuacao
    normal, 1200-1800s apos threshold proxy. Sentinela
    `<<autonomous-loop-dynamic>>` documentada. Reason no formato
    `agente-00c onda <NNN+1> apos <motivo>`. Passo 13 cravou formato do
    sumario retornado ao operador.

  - **`global/agents/agente-00c-orchestrator.md`** — nova secao "Pausas
    longas e fallback `/schedule` Routines": template completo de
    routine `/schedule criar "..." cron="..." prompt="/agente-00c-resume
    --projeto-alvo-path <PAP>"`; orientacao para incluir no relatorio
    parcial quando `aguardando_humano` + sinais de inatividade;
    explicito "NAO criar routine automaticamente" (operador escolhe
    cron especifico).

  - **`global/commands/agente-00c-resume.md`** — substituido o esqueleto
    da FASE 1 por fluxo operacional de 8 passos: parse de args, lock
    acquire, validate + sha256-verify, branch por status (terminal /
    em_andamento / aguardando_humano), apply de `--resposta-bloqueio`
    com sanitizacao via `sanitize.sh limit-length --max 2000`, spawn
    do orquestrador com prompt indicando "CONTINUACAO de execucao
    existente" + `retomada_motivo`, lock release + sumario.

  - **`global/commands/agente-00c-abort.md`** — substituido o esqueleto
    por fluxo operacional de 8 passos: parse, validacao com fail-soft
    para schema invalido (abort PROCEDE — pode ser o motivo do abort),
    idempotencia explicita (status terminal = no-op), atualizacao via
    `state-rw.sh set` (backup automatico), stub minimal de relatorio
    com `secrets-filter.sh scrub` aplicado, commit local via
    `state-ondas.sh git-commit` (fail-soft se nao e repo git, NUNCA
    push), sumario com hash do commit.

  - **`README.md`** — limitacao "Schedule mínimo de 5 min via /loop"
    atualizada para refletir clamp [60, 3600s] do `ScheduleWakeup` +
    fallback `/schedule` Routines.

- **Seguranca do agente-00C (FASE 6 — todas as 9 sub-features sao [C])**:
  56 subtarefas implementadas em 5 scripts focados no
  `agente-00c-runtime`, cobrindo 8 FRs criticos (FR-017, FR-018, FR-024,
  FR-025, FR-026, FR-027, FR-028, FR-029, FR-030, FR-031) e 5 threats
  (T1, T2, T3, T4, T5).

  - `path-guard.sh` (FR-024 + FR-017): subcomandos `validate-target`,
    `check-write`, `resolve`. Resolve symlinks via `realpath`/`readlink -f`
    com fallback portavel para paths inexistentes. Lista de zonas
    proibidas cobre 20+ paths incluindo formas canonica (`/etc`) e
    resolvida no macOS (`/private/etc`); explicitamente NAO bloqueia
    `/var/folders` (mktemp). Resolve TAMBEM cada zona antes de comparar
    (defesa T2 contra symlinks adversariais que apontam para zona
    proibida via `~`).

  - `bash-guard.sh` (FR-018 + FR-028 + SC-008): subcomandos
    `check-blocklist`, `check-whitelist`, `check`. Blocklist: sudo,
    package managers (npm/pnpm/yarn/pip/gem/brew/go install/cargo
    install) sem prefixo `docker exec/run`, `git push` (qualquer
    remote), kubectl mutativo, terraform apply/destroy, aws cli
    mutativo, gcloud deploy, docker push, docker-compose push, helm
    install/upgrade/uninstall. Whitelist: detecta network calls
    (curl/wget/gh api,issue,pr,repo,browse/git fetch,pull,clone),
    extrai URL (incluindo via `--repo OWNER/NAME` para gh) e checa
    contra whitelist; converte glob simples (`**` -> `.*`, `*` ->
    `[^/]*`) em regex. Excecao escopada: `gh issue create --repo
    JotJunior/claude-ai-tips` bypass (FR-021).

  - `secrets-filter.sh` (FR-030): subcomandos `scrub`, `check`. Filtros
    em ordem (especificos primeiro para preservar tipo): AWS keys
    (`AKIA[A-Z0-9]{16,}`), Bearer tokens, basic auth em URLs, tokens
    com palavra-chave proxima (token/key/secret/password/pwd/auth/
    api_key/access_key precedendo valor 20+ chars), valores de chaves
    do `.env` (carregado via `--env-file`, valores < 8 chars
    ignorados). `[REDACTED]`, `[REDACTED-AWS-KEY]` e `[REDACTED-ENV]`
    distinguem tipo. Hashes git e UUIDs sem palavra-chave proxima NAO
    sao filtrados (anti-falso-positivo).

  - `sanitize.sh` (FR-025): subcomandos `limit-length`, `check-length`,
    `escape-commit-msg`, `escape-issue-body`, `escape-path`. Defaults
    cobrem `descricao_curta` (max 500 chars). `escape-commit-msg`
    remove newlines/tabs/dollars/backticks/quotes + limita 100 chars.
    `escape-issue-body` preserva newlines (markdown), remove `$(...)`
    e backticks. `escape-path` remove path traversal `..` + chars
    nao-`[A-Za-z0-9._-]` + limita 64 chars.

  - `whitelist-validate.sh` (FR-031): subcomandos `check`, `list`.
    Rejeita patterns "overly broad": `**` puro sem dominio, `*://*`
    (scheme com glob), `https://*` sem dominio, host vazio, sem
    scheme, wildcard fora do padrao prefixo `*.dominio.tld`.
    Diagnostico inclui numero da linha + motivo + conteudo.

  Agente orquestrador (`global/agents/agente-00c-orchestrator.md`)
  atualizado com tabela de primitivas estendida (5 novos scripts) +
  secao "Defesa em profundidade" reescrita listando os 7 mecanismos
  (bash-guard, path-guard, sanitize, secrets-filter, whitelist-validate,
  sha256-verify, goal alignment) com instrucoes operacionais explicitas
  para o LLM (quando invocar, qual subcomando, semantica de exit code).

  62 cenarios de teste novos em
  `tests/test_{path-guard,bash-guard,secrets-filter,sanitize,whitelist-validate}.sh`.
  Inclui casos adversariais: symlink que aponta para `~/.ssh`, comando
  Bash com `sudo`/`git push`/`docker push`/`kubectl apply`, payload com
  AWS key/Bearer/basic auth/.env values, whitelist com `**`/`*://*`/etc.

- **Autonomia controlada do agente-00C (FASE 5)**: 5 novos scripts em
  `global/skills/agente-00c-runtime/scripts/` cobrem os 5 mecanismos de
  aborto graceful que mantem o orquestrador dentro do orcamento e do
  escopo declarado (Principio IV — Autonomia Limitada com Aborto).

  - `budget.sh`: proxies de orcamento de sessao (FR-009, sem signal
    nativo de tokens). 3 dimensoes: tool_calls da onda (default 80),
    wallclock (default 5400s = 90min) e tamanho de state.json (default
    1MB). `check` exit 1 quando QUALQUER threshold dispara, com TSV
    `TIPO\tCURRENT\tTHRESHOLD` em stdout. Wallclock usa fallback portavel
    BSD/GNU para `date -d` vs `date -j -f`. State size via `stat -f %z`
    (BSD) / `stat -c %s` (GNU) / `wc -c` (fallback).

  - `cycles.sh`: limite de ciclos por etapa (FR-014.a — `loop_em_etapa`).
    `tick` incrementa contador; `--progress-made` zera (orquestrador
    decide quando 1 dos 4 indicadores de FR-014 aconteceu). `reset`
    explicito ao avancar de etapa (separacao de responsabilidades — nao
    infere mudanca via `.etapa_corrente`). Exit 3 em > 5 ciclos.

  - `circular.sh`: deteccao de movimento circular (FR-014.b). `push`
    armazena `{problema_hash, solucao_hash, timestamp}` em buffer FIFO
    de capacidade 6. Normalizacao: lowercase + nao-alfanumerico->space +
    20 primeiras palavras. `detect` exit 3 quando mesmo problema_hash
    aparece >=3 vezes (cobre o padrao "P=A,S=X / P=B,S=Y / P=A,S=Z /
    P=B,S=Y / P=A,S=X" do exemplo da spec).

  - `drift.sh`: drift detection / goal alignment (FR-027, threat T1).
    `init` grava 3..7 aspectos-chave (cravado pos-primeira-onda — recusa
    sobrescrever). `check` itera ondas do final para o inicio, conta
    consecutivas sem decisao mencionando aspecto (case-insensitive
    substring nos campos contexto/escolha/justificativa de cada
    decisao). Warn em 3 ondas (stderr, exit 0); abort em 5 (exit 3,
    motivo `desvio_de_finalidade`).

  - `retro.sh`: limite de retro-execucoes (FR-006). `check` valida
    `consumed < max` (default 2). `consume` exit 3 SEM mutar estado se
    incremento excederia max (defesa em profundidade — testado com
    snapshot before/after). Orquestrador converte 3a tentativa em
    BloqueioHumano via `bloqueios.sh register`.

  37 cenarios de teste em `tests/test_{budget,cycles,circular,drift,retro}.sh`.

  Agente orquestrador (`global/agents/agente-00c-orchestrator.md`)
  atualizado: tabela de primitivas inclui os 5 novos scripts; passos 7
  e 8 do Loop principal de uma onda referenciam cada gatilho de aborto
  com semantica explicita (motivo, exit code, acao do orquestrador).

- **Padrao clarify de dois atores (agente-00C FASE 4)**: implementacao
  do mecanismo de "Pause-or-Decide" (Principio II da feature), com
  mediacao orquestrada entre clarify-asker (gera 1-5 perguntas via skill
  clarify) e clarify-answerer (decide via heuristica de score 0..3).

  - `global/agents/agente-00c-clarify-asker.md`: prompt operacional
    completo. Inputs (`spec_path`, `briefing_path`, `etapa_corrente`,
    `decisoes_anteriores`, `quantidade_max_perguntas`); fluxo (Read +
    Skill clarify + filtro de redundantes); formato JSON cravado com
    `Q1..QN` + `default_sugerido` opcional; saida vazia `{ "perguntas":
    [] }` quando nao ha clarificacao pendente. Tools restritas a Skill+Read
    (sem Agent — bisneto nao recursiona).

  - `global/agents/agente-00c-clarify-answerer.md`: heuristica de score
    documentada (3 fontes: briefing, constitutions toolkit+feature,
    stack-sugerida). Tabela de decisao (>=2 decide, ==1 decide so se
    outras violarem constitution, ==0 pause-humano). Tie-breaker em 4
    niveis. Formato JSON com `pause_humano: bool` e
    `contexto_para_humano` quando aplicavel. Tools restritas a Read+Bash
    (Bash apenas para `date`).

  - `global/agents/agente-00c-orchestrator.md`: passo 5 do Loop
    principal expandido com fluxo de mediacao em 7 sub-passos (a-g):
    pre-flight via spawn-tracker, spawn asker, spawn answerer (irmaos),
    aplicar respostas validas como Decisao via state-decisions.sh,
    converter score 0 em BloqueioHumano via bloqueios.sh, fim de onda
    gracioso quando ha pendentes.

  - **Novo script** `global/skills/agente-00c-runtime/scripts/bloqueios.sh`:
    ciclo de vida de BloqueioHumano (FR-015, FR-016). 6 subcomandos:
    `register` (gera `block-NNN` sequencial; valida FK para Decisao
    existente; valida `pergunta >= 20 chars`; atualiza
    `.execucao.status = "aguardando_humano"` e
    `.metricas_acumuladas.bloqueios_humanos_total`); `respond` (marca
    `respondido` + grava `resposta_humana` + `respondido_em`; volta
    `.execucao.status = "em_andamento"` SO quando todos os bloqueios
    pendentes foram respondidos); `list` (TSV com filtro opcional por
    status); `count` (com `--pending-only`); `next-id`; `get`
    (JSON do bloqueio).

  14 cenarios de teste em `tests/test_bloqueios.sh` cobrem o lifecycle
  completo (register -> respond), FK violation, validacao de pergunta
  curta, status transitions com bloqueios multiplos, idempotencia.

- **Orquestrador raiz do agente-00C (FASE 3)**: 4 novos scripts em
  `global/skills/agente-00c-runtime/scripts/` cobrem state machine,
  decisoes auditaveis, tracking de subagentes e ciclo de vida de ondas.

  - `pipeline.sh`: 5 subcomandos. `stages` imprime as 10 etapas
    canonicas (briefing → constitution → specify → clarify → plan →
    checklist → create-tasks → execute-task → review-task →
    review-features). `next-stage`/`prev-stage` para avanco linear ou
    retro-execucao. `detect-completion` mapeia 7 etapas para artefatos
    esperados em `docs/specs/<feature>/`. `skill-conflict` detecta
    skill em local (`<projeto>/.claude/skills/`) + global
    (`~/.claude/skills/`) com 4 status (conflict/only-local/only-global/
    not-found); regra: local vence.
  - `state-decisions.sh`: registro auditavel (Principio I —
    Auditabilidade Total). `register` valida 5 campos obrigatorios
    (contexto>=20, opcoes_consideradas>=1, escolha, justificativa>=20,
    agente); falha = exit 1 com `violacao Principio I`. Ids `dec-NNN`
    sequenciais; linka a `onda_id` corrente; `--score` 0..3 para
    decisoes do clarify-answerer (FR-015). Atualiza
    `metricas_acumuladas.decisoes_total`. Subcomandos `count`, `list`,
    `next-id` para introspeccao.
  - `spawn-tracker.sh`: enforce FR-013 (max 3 niveis). `enter` valida
    `(current+1) <= 3` ANTES de qualquer escrita; falha = exit 3 SEM
    modificar estado. Atualiza `profundidade_max_atingida` e
    `subagentes_spawned`. `leave` decrementa (idempotente em min 1).
    `check` exposto para validacao read-only. Defesa em profundidade:
    agentes `agente-00c-clarify-asker` e `clarify-answerer` NAO
    declaram tool Agent.
  - `state-ondas.sh`: ciclo de vida de Ondas. `start` cria nova `onda-NNN`
    + reseta tool_calls/inicio_onda_corrente. `end` valida 1 dos 5
    motivos validos (etapa_concluida_avancando, threshold_proxy_atingido,
    bloqueio_humano, aborto, concluido), calcula wallclock (fallback
    portavel GNU `date -d` -> BSD `date -j -f`) e atualiza
    metricas_acumuladas. `tool-call-tick` para incrementar contador
    (backup so a cada 10 ticks p/ nao explodir state-history/).
    `git-commit --motivo MOTIVO` faz commit local no projeto-alvo
    (`chore(agente-00c): <onda-id> - <motivo>`); NUNCA `git push`
    (Principio V — Blast Radius Confinado).

  46 cenarios de teste em `tests/test_{pipeline,state-decisions,spawn-tracker,state-ondas}.sh`.

  Agente orquestrador (`global/agents/agente-00c-orchestrator.md`)
  atualizado com instrucoes operacionais detalhadas (13 passos do loop
  principal de uma onda) referenciando estas primitivas.

- **Skill interna `agente-00c-runtime` (agente-00C FASE 2)**: biblioteca
  POSIX consumida pelos agentes custom do agente-00C. NAO e
  user-invocavel — empacota helpers de estado, validacao e lock para a
  pipeline. Distribuida via `cstk install` (catalog/skills/) e instalada
  em `~/.claude/skills/agente-00c-runtime/`. Conteudo:

  - `scripts/state-rw.sh`: subcomandos `init`, `read`, `write`, `get`,
    `set`, `sha256-update`, `sha256-verify`, `path-check`. Implementa
    schema state.json v1.0.0, backups automaticos por onda em
    `state-history/`, integridade SHA-256 (FR-029), atomic write
    via mktemp+mv, write-probe para detectar permissao negada, captura
    de I/O errors (disco cheio).
  - `scripts/state-validate.sh`: validador FR-008 read-only com 10
    checagens (schema_version, 14 campos obrigatorios, 4 invariantes
    numericas, status x terminada_em, 5 campos de Decisao, integridade
    de FK BloqueioHumano -> Decisao, whitelist nao-vazia). Sem
    auto-correcao (Principio III).
  - `scripts/state-lock.sh`: subcomandos `acquire`, `release`, `check`,
    `check-execution-busy`. Lock via `mkdir` atomico em
    `<state-dir>/.lock/`; locks independentes por projeto-alvo
    (permite execucoes simultaneas em projetos distintos). TOCTOU
    residual (CHK072) documentado.

  Dependencia: `jq` (carve-out 1.1.0 da constitution para JSON
  estruturado). 36 cenarios de teste em `tests/test_state-{rw,validate,lock}.sh`.

- **`cstk install` distribui `commands/` e `agents/` (agente-00C FASE 1.2)**:
  o tarball de release agora inclui `catalog/commands/` e `catalog/agents/`
  (espelhos de `global/commands/` e `global/agents/`), e o `cstk install`
  copia esses `.md` soltos para `~/.claude/commands/` e `~/.claude/agents/`
  (respectivamente `./.claude/commands/` e `./.claude/agents/` em
  `--scope project`). Cada kind tem seu proprio manifest dedicado
  (`<dest>/.cstk-manifest`) com schema identico ao de skills.

  Comportamento: instalacao sempre processa TODOS os `.md` (sem filtro de
  profile — sao infraestrutura, nao skills); re-install vira "updated";
  arquivo pre-existente sem entry no manifest e PRESERVADO como third-party
  (FR-007). Tarballs historicos sem `catalog/commands/` ou
  `catalog/agents/` continuam validos — ambos os campos sao opcionais.

- **`cstk doctor` varre os 3 kinds (skills, commands, agents)**: drift em
  commands/agents (EDITED, MISSING, ORPHAN) e reportado com prefixo de
  kind (ex: `[EDITED]   commands/agente-00c`); skills continuam exibidas
  sem prefixo (compatibilidade backward). `--fix` remove entries MISSING
  do manifest correto por kind.

- **Esqueleto do agente-00C** em `global/commands/` (3 slash commands:
  `/agente-00c`, `/agente-00c-abort`, `/agente-00c-resume`) e
  `global/agents/` (3 agentes custom: orchestrator, clarify-asker,
  clarify-answerer). Esqueleto apenas — implementacao operacional ocorre
  ao longo das Fases 2-9 do backlog em
  `docs/specs/_archived/agente-00c/tasks.md`.

### Changed

- `manifest_default_path` aceita argumento opcional `kind` (default
  `skills` — backward compatible). Uso: `manifest_default_path global commands`.
- `hash.sh` exporta `hash_file <arquivo>` (wrapper sobre `sha256_file`)
  para cobrir artefatos single-file (commands/agents). `hash_dir`
  inalterado.

## [3.3.0] - 2026-05-05

### Added

- **Skill `review-features`**: relatorio comparativo de TODAS as features
  do projeto (cross-feature), complementar a `review-task` (que olha UMA
  feature). Saida: tabela com nome, descricao, % concluida, criticidade
  pendente e sugestao de acao por feature (`ARQUIVAR` / `ABANDONAR` /
  `PRIORIZAR` / `CONTINUAR` / `INDEFINIDO`).

  Heuristica deterministica:
  - `ARQUIVAR`: feature 100% concluida
  - `ABANDONAR`: 0% concluida e sem modificacao ha mais de 90 dias
  - `PRIORIZAR`: tem subtasks `[C]` pendentes e menos de 50% concluida
  - `CONTINUAR`: caso geral em andamento
  - `INDEFINIDO`: tasks.md vazio

  Acompanha script POSIX `scripts/aggregate.sh` (saida markdown ou
  JSON-lines via `--json`) com 16 cenarios de teste em
  `tests/test_aggregate.sh`. A skill e read-only — sugestao e recomendacao,
  nunca executa arquivar/deletar sem confirmacao do usuario.

## [3.2.3] - 2026-04-27

### Changed

- **`cstk install --help` agora lista os profiles disponiveis** (`sdd`,
  `complementary`, `all`) com o conteudo de cada um e marca `sdd` como
  default. Antes, o usuario via apenas "Default: sdd" e nao tinha como
  descobrir que existiam outros profiles nem o que cada um continha — a
  unica fonte era `scripts/profiles.txt.in` no repo, fora do alcance de
  quem instalou via tarball.

  Reportado por usuario: apos `cstk install` (default `sdd`), faltavam
  skills complementares (advisor, bugfix, owasp-security, etc.) e nao
  havia pista no help de como instala-las. Solucao: profile
  `complementary` instala as 9 skills de uso pontual; profile `all`
  instala tudo. Exemplos no help cobrem os 3 profiles + cherry-pick.

  Test atualizado: `scenario_install_help_exit_zero` verifica que os
  tres nomes de profile aparecem na saida.

## [3.2.2] - 2026-04-27

### Fixed

- **`cstk install` e `cstk update` sem `--from` agora consultam a API
  GitHub** para descobrir a ultima release, em vez de abortar com
  "vem na FASE 3.2 (bootstrap)" — mensagem misleading que sobreviveu
  a entrega da FASE 3.2 (que entregou apenas o bootstrap standalone,
  nao a resolucao no comando `cstk install`).

  Comportamento novo:
  - `--from URL` (explicit)             → usa a URL fornecida
  - `$CSTK_RELEASE_URL` (env)           → usa a URL do env
  - **(novo)** sem nada acima           → GitHub API /releases/latest

  Honra `$CSTK_REPO` para forks (default `JotJunior/claude-ai-tips`).
  Mesmo padrao ja em uso por `cstk self-update` desde FASE 5.

  Reportado por usuario: `cstk install` apos bootstrap retornava
  "[error] install: --from URL ausente e \$CSTK_RELEASE_URL nao setado"
  — quebrava o fluxo "instalar via one-liner depois `cstk install`"
  documentado no README.

  Test atualizado: `scenario_install_sem_from_e_sem_env_consulta_api`
  usa `CSTK_REPO=invalid/nonexistent` para forcar 404 da API e validar
  que o erro reportado e "falha ao consultar" (em vez de mensagem
  antiga sobre CSTK_RELEASE_URL nao setado).

## [3.2.1] - 2026-04-27

### Fixed

- **Bootstrap one-liner (`cli/install.sh`) e `cstk self-update` baixavam
  URL com 404.** A construcao da URL do tarball usava o tag completo
  (`cstk-v3.2.0.tar.gz`), mas `scripts/build-release.sh` strip o prefixo
  `v` ao gerar o asset (`cstk-3.2.0.tar.gz`). Match falhava com 404.

  Fix: ambos `cli/install.sh` e `cli/lib/self-update.sh` agora computam
  `TAG_BARE=${TAG#v}` e usam essa variante ao construir o filename do
  asset, mantendo o tag original (com `v`) no path do release. Comporta-
  mento alinhado com `build-release.sh`.

  **Impacto**: `releases/latest/download/install.sh` em v3.2.0 esta
  quebrado — usuarios precisam usar v3.2.1 (que fixa o asset URL ao
  baixar). v3.2.0 nao foi removida; tag continua presente para
  rastreabilidade do incidente.

  Descoberto por usuario reportando `curl: (22) ... 404` ao executar o
  one-liner publicado no README.

## [3.2.0] - 2026-04-26

### Added

- **`cstk` CLI (POSIX shell)** — toolkit de instalação, atualização e
  auditoria de skills. Substitui o `cp -r` manual documentado em
  `CLAUDE.md` por um fluxo rastreável: manifest por escopo (versão +
  `source_sha256` + ISO timestamp), lock concorrente via `mkdir`,
  verificação SHA-256 obrigatória em todo download (FR-010a),
  preservação de skills de terceiros (FR-007), políticas explícitas de
  conflito em update (`--force` / `--keep`, exit 4 quando edit local
  detectado sem flag — FR-008).

  **Comandos**: `install`, `update`, `self-update`, `list`, `doctor`.

  **Profiles**: `sdd` (default — pipeline SDD com 10 skills),
  `complementary` (9 skills independentes), `all` (todos os 35 skills),
  `language-go`, `language-dotnet`. Cherry-pick por nome também
  suportado; modo interativo via `--interactive` (seletor numerado em
  TTY).

  **Escopos**: `--scope global` (`~/.claude/skills/`, default) e
  `--scope project` (`./.claude/skills/`). Hooks de `language-*` são
  instalados APENAS em escopo de projeto (FR-009c) com merge automático
  de `settings.json` quando `jq` disponível, ou paste-block instrucional
  quando ausente (FR-009d).

  **Self-update atômico** (FR-006): par `bin + lib` tratado como unidade
  indivisível via stage-and-rename coordenado + boot-check de versão
  embutida vs versão da lib. Nunca toca o manifest de skills (FR-006a;
  verificável: mtime do `.cstk-manifest` preservado).

  **Pipeline de release** em `.github/workflows/release.yml` —
  triggered por `push tag v*`, valida testes (`tests/run.sh` + cstk
  suite), gera tarball determinístico via `scripts/build-release.sh`
  e publica via `gh release create` com `cstk-X.Y.Z.tar.gz`,
  `.sha256` e `install.sh` (asset standalone para o one-liner
  `curl <url> | sh`).

  **Observabilidade**: `cstk list` (TSV/pretty) + `cstk doctor`
  (4 estados de drift: OK, EDITED, MISSING, ORPHAN — SC-007).

  **Determinismo do tarball** (`scripts/build-release.sh`): mtime
  normalizado, `gzip -n`, ordenação `LC_ALL=C sort`, detecção
  GNU-vs-BSD tar para paths portáveis. Verificado: 2 builds
  consecutivos produzem o mesmo SHA-256.

  **Cobertura de testes**: 242 cenários (`tests/run.sh` global), zero
  falhas. Gap real único (Scenario 13 SC-003 byte-a-byte) coberto por
  `tests/cstk/test_quickstart-e2e.sh`.

  Spec completa em [`docs/specs/cstk-cli/`](docs/specs/_archived/cstk-cli/);
  documentação user-facing em [`README.md`](./README.md) §Instalação.

### Governance

- **Constitution 1.0.0 → 1.1.0 (MINOR amendment)**: nova subseção "Optional
  dependencies with graceful fallback" sob Princípio II disciplinando deps
  não-POSIX em três condições cumulativas (uso opcional com fallback
  verificável, confinamento em único arquivo, declaração explícita na feature).
  Nota complementar no Decision Framework item 4 reconhece subseções de
  carve-out como mecanismo válido quando precedidas por amendment MINOR.
  Não afrouxa Princípio II — Bash-isms seguem proibidos, `ripgrep`/`fd`/`bats`
  permanecem banidos mesmo como opcionais, deps obrigatórias continuam vetadas.
  Primeiro caso concreto sob a nova regra: `jq` opcional em `cli/lib/hooks.sh`
  da feature `cstk-cli`. Ver `docs/specs/constitution-amend-optional-deps/`
  para histórico completo de raciocínio.

## [3.1.1] - 2026-04-20

Versão PATCH — correção de bug latente em `validate.sh` análogo ao
histórico de `metrics.sh` (commit `ead1b68`).

### Fixed

- **`validate.sh` deixa de poluir stderr com `integer expression expected`.**
  As linhas 244–245 continham o mesmo padrão defeituoso `grep -c ... || printf '0'`
  que quebrou `metrics.sh`: em no-match, `grep -c` imprime `"0"` e sai com
  exit 1, disparando o fallback que concatena outro `"0"` — resultado
  `"0\n0"` quebra as comparações aritméticas subsequentes. Fix aplica o
  padrão seguro `VAR=$(grep -c ...) || VAR=0`.
- **Bug latente adicional revelado**: a aritmética corrompida fazia com
  que os três `if` do bloco "Próximos Passos" (`Corrigir N ERRO(s)`,
  `N AVISO(s)`, `Nenhuma ação necessária`) falhassem silenciosamente em
  docs válidos. Com o fix, a mensagem de sucesso `- Nenhuma acao
  necessaria. Documentacao renderiza corretamente.` volta a aparecer
  quando aplicável.
- Tabela Resumo do stdout deixa de renderizar `| X | 0\n0 |` em duas
  linhas quando algum contador é zero — agora sempre em linha única
  `| X | 0 |`.

### Added

- **`tests/test_validate.sh :: scenario_stderr_limpo_em_docs_validos`**:
  regressão dedicada que captura stderr ao rodar `validate.sh` contra
  `fixtures/docs-site/valid/` e falha se contiver `"integer expression
  expected"` ou `"[: "`. Protege contra o retorno do bug histórico.
- **Assertion adicional em `scenario_docs_validos`**: trava como
  invariant a linha "Nenhuma acao necessaria" que agora aparece em docs
  válidos.
- Feature SDD completa em `docs/specs/fix-validate-stderr-noise/`:
  spec + plan + research + quickstart + tasks + checklists/requirements
  (29 subtarefas, 100% concluídas).

### Contract preserved

- Exit codes de `validate.sh` inalterados (0 em sucesso, 1 em ERROs).
- Estrutura do stdout (seções, colunas, severidades) inalterada.
- Apenas valores numéricos corrigidos onde estavam corrompidos, e
  stderr limpo. Nenhum teste existente em `test_validate.sh` quebrou.

## [3.1.0] - 2026-04-20

Versão MINOR — adição de suíte automatizada de testes para os scripts
POSIX distribuídos em `global/skills/**/scripts/`.

### Added

- **Suite automatizada de testes em `tests/`** cobrindo os 5 scripts
  shell do toolkit (`metrics.sh`, `next-task-id.sh`, `next-uc-id.sh`,
  `scaffold.sh`, `validate.sh`). Entry point único `tests/run.sh` executa
  44 scenarios em 3–4 segundos e reporta status trichotômico
  PASS / FAIL / ERROR no formato TAP.

- **Harness POSIX puro** em `tests/lib/harness.sh` com gestão isolada
  por `mktemp -d` + `trap EXIT/INT/TERM`, e os helpers `assert_exit`,
  `assert_stdout_contains`, `assert_stderr_contains`, `assert_stdout_match`,
  `assert_no_side_effect`, `fixture` e `run_all_scenarios`. Zero
  Bash-isms; zero dependências além das ferramentas POSIX canônicas.

- **Regressão dedicada do bug histórico de `metrics.sh`**
  (`scenario_regressao_bug_grep_c_sem_matches`) protegendo contra o
  retorno do padrão defeituoso `grep -c ... || printf '0'` que
  concatenava `"0\n0"` e quebrava expressões aritméticas. Validado
  revertendo o fix temporariamente durante a entrega: a suíte detectou
  3 FAILs incluindo o dedicado.

- **Modos do runner**: `--list` (lista scenarios sem executar),
  `--check-coverage` (detecta scripts sem teste e testes sem script;
  exit 1 em órfão), filtragem por `PATTERN` posicional, `--help`.

- **Governança de cobertura (FR-009 da spec)**: no modo normal, órfãos
  aparecem como warning (`ORPHANS: N` + bloco `# WARN:`) sem bloquear;
  no modo `--check-coverage`, órfãos fazem exit 1. Convenção estrita
  `tests/test_<nome>.sh` para cada `global/skills/<skill>/scripts/<nome>.sh`.

- **`tests/README.md`** com quickstart, arquitetura, formato TAP, exit
  codes, contrato do harness (tabelas de helpers) e guia para adicionar
  teste ao script novo.

- **Spec completa em `docs/specs/shell-scripts-tests/`**: `spec.md` +
  `plan.md` + `research.md` + `data-model.md` + `contracts/runner-cli.md`
  + `quickstart.md` + `checklists/requirements.md` + `tasks.md`. Feature
  entregue em 5 fases, 113 subtarefas, 100% concluídas.

### Known issue (fora do escopo desta release)

- `validate.sh` (linhas 273–284) contém o mesmo padrão
  `grep -c || printf '0'` do bug histórico de `metrics.sh`. Afeta
  apenas stderr (não exit code nem stdout). Registrado em
  `docs/specs/shell-scripts-tests/tasks.md` §FASE 2. Candidato para
  nova feature em ciclo SDD separado.

## [3.0.0] - 2026-04-20

Versão MAJOR devido a remoção de asset distribuído (contrato de instalação
muda — usuários que faziam `cp -r global/insights/` precisam migrar).

### Removed (BREAKING)

- **Diretório `global/insights/` removido do repositório.** O arquivo
  `usage-insights.md` que vivia ali era uma curadoria específica de sessões
  de um usuário (Go + TypeScript + PostgreSQL multi-serviço), não um playbook
  genérico. Distribuí-lo como parte do toolkit confundia quem clonava: o
  conteúdo era tratado como autoritativo quando era apenas o snapshot de um
  contexto.

  **Como fica agora**:

  - A skill `apply-insights` continua funcionando — ela sempre leu de
    `~/.claude/insights/usage-insights.md` (espaço do usuário), nunca de
    `global/insights/` diretamente.
  - Se o arquivo `~/.claude/insights/usage-insights.md` existir, a skill o
    usa. Caso contrário, cai em best-practices genéricas (comportamento
    já documentado no SKILL.md).
  - O modelo recomendado agora: gerar o arquivo via a slash command nativa
    `/insights` do Claude Code (que analisa suas sessões reais) ou curá-lo
    manualmente. Cada usuário mantém o seu próprio.

  **Impacto para consumidores**:

  - O comando `cp -r global/insights/ ~/.claude/insights/` (documentado no
    README) não existe mais — o diretório-fonte foi removido.
  - Quem já tinha copiado o arquivo para `~/.claude/insights/` mantém a
    cópia local intocada.
  - README atualizado: seção "Insights de Uso" reescrita para refletir o
    modelo por-usuário; diagrama de estrutura e bloco de instalação
    limpos.
  - CLAUDE.md atualizado: seção "Renomeando uma skill" não referencia mais
    `global/insights/`.

### Migration

1. Se você dependia do arquivo distribuído:

   ```bash
   # O arquivo pode continuar no seu ~/.claude/insights/ se você já o copiou
   ls ~/.claude/insights/usage-insights.md

   # Caso contrário, gere o seu via o /insights nativo do Claude Code,
   # ou mantenha um playbook curado manualmente neste caminho
   ```

2. Se você referenciava `global/insights/` em scripts ou docs próprios,
   remover a referência — o caminho não resolve mais.

## [2.0.0] - 2026-04-19

Versão MAJOR devido a rename de skill user-visível (identificador de invocação
é contrato público).

### Changed (BREAKING)

- **Skill `insights` renomeada para `apply-insights`** — o Claude Code tem uma
  slash command nativa `/insights` (analisa suas sessões de uso) que colidia
  no namespace de autocomplete com a nossa skill homônima. As duas
  coexistiam sem uma sobrescrever a outra, mas a ambiguidade gerava atrito:
  - usuários precisavam selecionar a correta a cada invocação
  - documentação que referenciasse `/insights` ficava ambígua
  - hooks que tentassem invocar por string tinham comportamento indefinido

  Rename para `apply-insights` deixa claro que a função é **prescritiva**
  (aplicar um playbook ao projeto) — distinta da nativa, que é
  **introspectiva** (analisar sessões). A description da skill agora explicita
  essa diferença para o modelo.

  **Impacto para consumidores**:
  - Invocações via `/insights` agora rodam a skill nativa do Claude Code
  - Para a função antiga, usar `/apply-insights`
  - Arquivos CLAUDE.md / documentação que referenciavam `/insights` precisam
    ser atualizados

### Migration

1. Se o seu projeto tem instalação local: `.claude/skills/insights/` →
   `.claude/skills/apply-insights/`
2. Atualizar triggers em CLAUDE.md, memórias, hooks, scripts
3. Nova invocação: `/apply-insights` (ou qualquer dos triggers em português
   como "aplicar insights", "aplicar playbook", "melhorar claude.md")

## [1.1.0] - 2026-04-19

Refatoração ampla das 18 skills globais aplicando os princípios do artigo
["Skills no Claude Code: O Guia Definitivo"](./docs/artigo.md) e adicionando
1 nova skill. Todas as mudanças são backward-compatible na invocação pelo
nome — skills continuam respondendo aos mesmos triggers e argumentos.

### Added

- **Nova skill `validate-docs-rendered`** (categoria "Verificação de Produto"
  do artigo) — valida que a documentação Markdown realmente renderiza
  corretamente: diagramas Mermaid parseáveis, links internos sem 404,
  frontmatter YAML consistente, tabelas bem formadas, code blocks com
  linguagem declarada. Script POSIX `scripts/validate.sh` roda 5 checagens
  com exit code para uso em CI/hooks.

- **Seções `Gotchas` em todas as 18 skills preexistentes** — documentando
  armadilhas recorrentes e erros típicos. Segue a recomendação do artigo de
  que "o conteúdo mais valioso de uma skill é a seção de gotchas".

- **Scripts POSIX reutilizáveis em 4 skills**:
  - `initialize-docs/scripts/scaffold.sh` — cria estrutura 01-09 com READMEs
    template, idempotente, suporta `--dry-run`, `--force`, `--dir=PATH`
  - `create-use-case/scripts/next-uc-id.sh` — calcula próximo `UC-{DOMINIO}-NNN`
    disponível; suporta `--list` para auditar domínios existentes
  - `create-tasks/scripts/next-task-id.sh` — calcula próximo ID hierárquico
    (`1.3`, `1.2.4`) com regex ancorado para evitar falsos positivos
  - `review-task/scripts/metrics.sh` — extrai métricas de progresso do
    tasks.md em formato tabular + JSON

- **Arquitetura de skill-como-pasta** com subdiretórios para *progressive
  disclosure* em 8 skills (specify, plan, create-tasks, create-use-case,
  briefing, checklist, constitution, analyze):
  - `templates/` — templates preenchíveis (feature-spec, plan, tasks,
    briefing, constitution, data-model, contracts, quickstart, research,
    use-case)
  - `examples/` — exemplos concretos (specify tem `spec-good.md` e
    `spec-bad.md` com anti-patterns comentados)
  - `references/` — documentação de apoio (catálogos de items por domínio
    para checklist; consistency-checks para analyze; discovery-guide
    detalhado para briefing)

- **Composição explícita do pipeline SDD** — cada skill do pipeline agora
  documenta em seções `## Pré-requisitos` e `## Próximos passos` quais
  artefatos consome e qual skill é o passo lógico seguinte. Torna a sequência
  briefing → constitution → specify → clarify → plan → checklist →
  create-tasks → analyze → execute-task → review-task navegável sem
  tooling formal de dependências.

- **`config.json` em 3 skills** para configuração por projeto:
  - `create-use-case/config.json` — mapa de domínios customizados, output_dir,
    formato de ID, mínimos de qualidade
  - `create-tasks/config.json` — níveis de criticidade, paths de output
    (spec_derived vs standalone), prefixo de fase, granularidade
  - `initialize-docs/config.json` — estrutura de diretórios customizável,
    `keep_in_root`, `file_routing` por padrão

  Quando `config.json` está ausente, as skills usam defaults documentados.
  Quando presente, o projeto adapta as convenções sem bifurcar a skill.

### Changed

- **Reescrita do campo `description` de todas as 18 skills** no formato de
  *trigger conditions* ("Use quando o usuário X, Y ou Z. Também quando
  mencionar A, B, C. NÃO use quando W.") em vez de resumo. Isso melhora
  descoberta — o modelo precisa decidir *quando* invocar a skill, não apenas
  o que ela faz. Particularmente relevante com Opus 4.7, que interpreta
  descrições de forma mais literal.

- **Agnosticização completa das skills** — removidas referências específicas
  a projetos, stacks e convenções de qualquer cliente/codebase. Skills agora
  tratam stack (Go/Python/React/etc.), domínios de negócio (AUTH/CAD/PED) e
  paths internos (`services/{service}/...`) como exemplos ilustrativos
  marcados, não como assunções. Cada skill funciona em qualquer projeto.

- **`bugfix` reescrita para ser stack-agnostic** — os 8 passos do protocolo
  (Step 0..7) agora usam terminologia genérica de camadas ("server /
  backend", "client / frontend", "cross-boundary") em vez de listas
  específicas de Go/React. Comandos de build/test/lint apresentados em
  tabela por stack.

- **`execute-task` reescrita para ser stack-agnostic** — Etapa 7 (Lint) é
  agora uma tabela com comandos típicos por stack (Go, Node, Rust, Python,
  Java, .NET) em vez de assumir `go build ./...`.

- **`create-use-case`: domínios deixam de ser enum fixo** — a lista antiga
  (AUTH, CAD, PED, FIN, FAT, LOG, MON, INAD, REC, PROP, CONT, DOM) virou
  exemplo; a skill consulta `config.json` ou UCs existentes antes de
  perguntar ao usuário.

- **Templates extraídos do SKILL.md para arquivos separados** — reduzem o
  custo de contexto no momento da invocação: o modelo carrega o template
  só quando preenche, não toda vez que decide se invoca a skill.

### Moved

- `global/skills/create-use-case/template-uc.md` →
  `global/skills/create-use-case/templates/use-case.md`
  (alinhamento com a convenção `templates/` das demais skills)

### Documentation

- README.md atualizado com:
  - Seção "Anatomia de uma skill" documentando a arquitetura (SKILL.md +
    templates/examples/references/scripts/config.json)
  - Esclarecimento de que domínios (AUTH/CAD/PED/etc.) são configuráveis
    por projeto, não uma lista universal
  - Seção "Contribuindo" revisada com guidelines para novas skills
    (trigger-condition descriptions, gotchas, progressive disclosure)
  - Link para este CHANGELOG

### Estatísticas desta versão

- 18 skills preexistentes atualizadas
- 1 skill nova (`validate-docs-rendered`)
- 19 arquivos novos de templates/references/examples
- 5 scripts POSIX (4 nas skills existentes + 1 na skill nova)
- 3 arquivos `config.json`
- 5 commits incrementais (uma fase por commit)

---

## [1.0.0] - 2026-04-18

Primeira versão publicada do toolkit.

### Added

- 18 skills globais cobrindo pipeline SDD completo (briefing, constitution,
  specify, clarify, plan, checklist, create-tasks, analyze, execute-task,
  review-task) e skills complementares (advisor, bugfix, create-use-case,
  image-generation, initialize-docs, insights, owasp-security,
  validate-documentation)
- Skills específicas para Go (commit, create-report, go-add-entity,
  go-add-migration, go-add-test, go-add-consumer, go-review-pr,
  go-review-service) e hooks de validação
- Skills específicas para .NET (create-entity, create-feature,
  create-project, create-test, hexagonal-architecture, infrastructure,
  review-code, testing)
- Arquivo `global/insights/usage-insights.md` com padrões extraídos de 134
  sessões reais de uso
- README documentando estrutura, pipeline SDD sugerido e convenções de
  nomenclatura

[4.3.0]: https://github.com/JotJunior/claude-ai-tips/releases/tag/v4.3.0
[4.2.0]: https://github.com/JotJunior/claude-ai-tips/releases/tag/v4.2.0
[4.1.1]: https://github.com/JotJunior/claude-ai-tips/releases/tag/v4.1.1
[4.1.0]: https://github.com/JotJunior/claude-ai-tips/releases/tag/v4.1.0
[4.0.0]: https://github.com/JotJunior/claude-ai-tips/releases/tag/v4.0.0
[3.19.1]: https://github.com/JotJunior/claude-ai-tips/releases/tag/v3.19.1
[3.19.0]: https://github.com/JotJunior/claude-ai-tips/releases/tag/v3.19.0
[3.18.0]: https://github.com/JotJunior/claude-ai-tips/releases/tag/v3.18.0
[3.17.0]: https://github.com/JotJunior/claude-ai-tips/releases/tag/v3.17.0
[3.16.0]: https://github.com/JotJunior/claude-ai-tips/releases/tag/v3.16.0
[3.15.0]: https://github.com/JotJunior/claude-ai-tips/releases/tag/v3.15.0
[3.14.0]: https://github.com/JotJunior/claude-ai-tips/releases/tag/v3.14.0
[3.13.0]: https://github.com/JotJunior/claude-ai-tips/releases/tag/v3.13.0
[3.12.0]: https://github.com/JotJunior/claude-ai-tips/releases/tag/v3.12.0
[3.11.0]: https://github.com/JotJunior/claude-ai-tips/releases/tag/v3.11.0
[3.10.0]: https://github.com/JotJunior/claude-ai-tips/releases/tag/v3.10.0
[3.9.1]: https://github.com/JotJunior/claude-ai-tips/releases/tag/v3.9.1
[3.9.0]: https://github.com/JotJunior/claude-ai-tips/releases/tag/v3.9.0
[3.8.0]: https://github.com/JotJunior/claude-ai-tips/releases/tag/v3.8.0
[3.7.0]: https://github.com/JotJunior/claude-ai-tips/releases/tag/v3.7.0
[3.6.0]: https://github.com/JotJunior/claude-ai-tips/releases/tag/v3.6.0
[3.5.3]: https://github.com/JotJunior/claude-ai-tips/releases/tag/v3.5.3
[3.5.2]: https://github.com/JotJunior/claude-ai-tips/releases/tag/v3.5.2
[3.5.1]: https://github.com/JotJunior/claude-ai-tips/releases/tag/v3.5.1
[3.5.0]: https://github.com/JotJunior/claude-ai-tips/releases/tag/v3.5.0
[3.4.0]: https://github.com/JotJunior/claude-ai-tips/releases/tag/v3.4.0
[3.3.0]: https://github.com/JotJunior/claude-ai-tips/releases/tag/v3.3.0
[3.2.3]: https://github.com/JotJunior/claude-ai-tips/releases/tag/v3.2.3
[3.2.2]: https://github.com/JotJunior/claude-ai-tips/releases/tag/v3.2.2
[3.2.1]: https://github.com/JotJunior/claude-ai-tips/releases/tag/v3.2.1
[3.2.0]: https://github.com/JotJunior/claude-ai-tips/releases/tag/v3.2.0
[3.1.1]: https://github.com/JotJunior/claude-ai-tips/releases/tag/v3.1.1
[3.1.0]: https://github.com/JotJunior/claude-ai-tips/releases/tag/v3.1.0
[3.0.0]: https://github.com/JotJunior/claude-ai-tips/releases/tag/v3.0.0
[2.0.0]: https://github.com/JotJunior/claude-ai-tips/releases/tag/v2.0.0
[1.1.0]: https://github.com/JotJunior/claude-ai-tips/releases/tag/v1.1.0
[1.0.0]: https://github.com/JotJunior/claude-ai-tips/releases/tag/v1.0.0
