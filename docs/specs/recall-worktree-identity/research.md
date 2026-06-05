# Research: Recall Worktree Identity

**Feature**: `recall-worktree-identity` | **Date**: 2026-06-05
**Spec**: [spec.md](./spec.md) | **Phase**: 0 (research)

Todas as decisoes abaixo foram aterradas por sondas empiricas no codebase
(linhas citadas conferidas em 2026-06-05, commit base `0f9f2be`).

---

## Decision 1 — Deteccao de worktree: `test -f .git` + `git rev-parse --git-common-dir`

**Decision**: o command pai (`/feature-00c`, `/agente-00c`) detecta worktree
verificando se `<target_project_path>/.git` e ARQUIVO (`test -f`, POSIX puro).
Quando positivo, resolve o repo canonico via
`git -C <target_project_path> rev-parse --git-common-dir`; o projeto canonico e
`basename(dirname(<common-dir absoluto>))` — o diretorio que CONTEM o `.git`
comum.

**Rationale**:
- Num worktree git, `.git` e um arquivo de ponteiro (`gitdir: <path>`); no repo
  raiz e diretorio. `test -f` e deterministico, zero-custo e POSIX.
- `git rev-parse --git-common-dir` retorna o `.git` do repo principal a partir
  de qualquer worktree — e o mecanismo oficial do git, robusto a layouts
  (`git worktree add` em qualquer path). Atencao de implementacao: o retorno
  pode ser RELATIVO ao cwd; normalizar para absoluto antes do `dirname`
  (ex: prefixar com o cwd quando nao comecar com `/`).
- O `cstk session start` cria worktrees em `<parent-of-repo>/<repo-name>-<name>`
  (`cli/lib/session.sh:237-243`, `_session_worktree_path`), mas a deteccao NAO
  depende desse naming — funciona para qualquer worktree git.

**Alternatives considered**:
- `git rev-parse --show-toplevel`: rejeitado — dentro do worktree retorna o
  toplevel DO worktree (o path fantasma), nao o repo principal.
- Parsear o arquivo `.git` (`gitdir: ...`) manualmente: rejeitado — formato e
  detalhe interno do git; `rev-parse` e a interface estavel.
- Depender do naming `<repo>-<name>` do session.sh para deduzir o canonico:
  rejeitado como mecanismo primario (fragil para worktrees criadas fora do
  `cstk session`); usado APENAS para derivar `session_name` (Decision 2).

---

## Decision 2 — Derivacao de `session_name`: sufixo apos `<canonical>-` no basename do worktree

**Decision**: com o canonico resolvido (Decision 1), `session_name` =
sufixo de `basename(target_project_path)` apos o prefixo `<canonical>-`.
Ex: worktree `/Users/jot/Projects/cstk-minha-feature` + canonico `cstk` →
`session_name = "minha-feature"`. Se o basename NAO comeca com `<canonical>-`
(worktree criada fora do `cstk session`), `session_name` fica VAZIO e apenas
`canonical_project` e congelado.

**Rationale**: e a inversao exata do naming de `_session_worktree_path`
(`session.sh:243`: `printf '%s/%s-%s\n' "$_parent" "$_repo_name" "$_name"`).
C3 da spec define este mecanismo explicitamente. Worktrees fora da convencao
ainda ganham atribuicao de projeto correta (o objetivo P1); apenas a
proveniencia de sessao (P2) degrada para ausente — comportamento documentado,
nao silencioso.

**Alternatives considered**:
- Ler o nome da branch do worktree como session_name: rejeitado — branch pode
  divergir do nome da sessao (regras FR-001 do session.sh permitem reuso de
  branch existente) e o acoplamento seria mais frouxo que o naming do path.
- Registrar a sessao num arquivo de metadata escrito pelo `session start`:
  rejeitado — exigiria mudanca no session.sh e nao cobriria worktrees ja
  criadas; o naming do path ja carrega a informacao.

---

## Decision 3 — Congelamento no INIT (flags novas do `state-rw.sh init`), nao em hook posterior

**Decision**: `state-rw.sh init` ganha duas flags OPCIONAIS:
`--canonical-project NAME` e `--session-name NAME`, gravadas em
`execution.canonical_project` e `execution.session_name` quando nao-vazias
(ausentes do state.json quando omitidas — sem chave nula). A DETECCAO
(Decision 1+2) vive no command pai (`/feature-00c` §init, `/agente-00c` §init),
que passa os valores ao init. O `state-rw.sh` permanece burro: grava o que
recebe, nao invoca git.

**Rationale**:
- A validacao empirica da C5 (Decision 4) mostra que o state criado DENTRO da
  worktree morre com `cstk session end`. O conhecimento chega a knowledge.db
  pelo ingest AO VIVO (hook 10.bis por onda) — portanto a proveniencia correta
  precisa estar no state DESDE A PRIMEIRA ONDA. Congelar depois (hook tardio,
  retrofit) deixaria janela de ondas ingeridas com nome fantasma.
- Manter o git fora do `state-rw.sh` preserva a separacao de camadas: o
  runtime e CRUD puro de state (testavel sem repo git); a deteccao e politica
  do command pai (mesmo lugar que ja resolve `realpath`, lock e init —
  ver contrato "Fronteira command↔orquestrador").
- Flags opcionais = retro-compat total: chamadas existentes do init (modo
  projeto e modo feature) seguem validas sem mudanca (FR-010).

**Alternatives considered**:
- Detectar worktree DENTRO do `state-rw.sh init`: rejeitado — introduz
  dependencia de git no runtime CRUD e duplica a politica nos dois modos;
  command pai ja e o dono do init (C3).
- Campo derivado on-the-fly a cada ingest (sem congelar): rejeitado — falha
  exatamente no cenario-alvo (worktree removida; `--reindex` e ingests tardios
  nao conseguem mais resolver git ao vivo). O congelamento e o que da
  robustez pos-remocao.

---

## Decision 4 — Validacao empirica da premissa C5: parcialmente INCORRETA (erratum) + fronteira do `--reindex`

**Decision**: o plan NAO herda a C5 literal. Comportamento real validado por
sonda, com ERRATUM registrado:

Sondas executadas (2026-06-05):

1. `grep -n EXCLUDES cli/lib/session.sh` →
   `session.sh:68`: `_CSTK_SESSION_CLAUDE_EXCLUDES="agente-00c-state
   agente-00c-archive agente-00c-report.md agente-00c-suggestions.md
   settings.local.json agente-00c-whitelist .agente-00c-state.lock insights"`.
   **`feature-00c-state` NAO esta na lista** — a C5 afirma que esta ("O
   `.claude/agente-00c-state/` e `.claude/feature-00c-state/` estao listados
   em `_CSTK_SESSION_CLAUDE_EXCLUDES`"): **falso para feature-00c-state**.
   Consequencia: states de feature PRE-existentes no repo raiz SAO COPIADOS
   para a worktree no `session start` (`cp -R` em `session.sh:357`; so os
   excludes sao removidos em `:359-361`).
2. `git check-ignore -v .claude/feature-00c-state .claude/agente-00c-state` →
   ambos cobertos por `.gitignore:3` (`.claude`). State NAO viaja pela branch.
3. Leitura de `cli/lib/recall.sh`: ingest deriva project em `:751-755`
   (`basename(.execution.target_project_path // .execucao.projeto_alvo_path)`);
   feature em `:767-778` (layout `feature-00c-state/<short>/` → short-name;
   layout `agente-00c-state/` → basename do projeto, paridade EXCLUDE_FEATURE
   comentada em `:767-768`); reindex de memorias com reverse-derivation do
   encoded path em `:1587-1594` (limitacao CQ1 ja documentada).

Comportamento real consolidado:

- **State criado DENTRO da worktree** (orquestrador iniciado la): vive no
  `.claude/` da worktree, **morre com `cstk session end`** (worktree removida)
  e nao viaja pela branch (gitignored). E o caso-alvo desta feature.
- **State de feature PRE-existente no repo raiz**: e COPIADO para a worktree
  (nao esta nos excludes). Risco colateral documentado: duas copias do mesmo
  state divergem se o orquestrador rodar na copia. FORA DO ESCOPO desta
  feature corrigir os excludes (pertence ao namespace cstk-session); o
  congelamento proposto e ortogonal e nao piora esse cenario.
- **O que vale da C5**: a conclusao final ("ingest com canonical_project
  congelado funciona pos-`session end`") permanece valida, mas pelo motivo
  CERTO: o ingest por onda (10.bis) acontece AO VIVO enquanto a worktree
  existe — o conhecimento chega a knowledge.db ANTES da remocao, ja com a
  proveniencia correta gravada pelo congelamento no init.

**Fronteira explicita do `--reindex`** (compromisso que o plan declara e a
spec FR-006/SC-003 devem ser lidos sob esta luz): `--reindex` varre states
EXISTENTES no disco. States que viviam exclusivamente numa worktree ja
removida NAO EXISTEM MAIS — nenhum mecanismo os reindexara. A robustez
pos-remocao vem (a) do que ja foi ingerido ao vivo e (b) de states congelados
que SOBREVIVEM (ex: state pre-existente no repo raiz, ou state de worktree
cujo disco ainda existe). FR-006/SC-003 sao satisfeitos para "state.json
congelado disponivel ao reindex" — nunca prometido reindex de arquivo
inexistente.

**Rationale**: herdar a C5 literal produziria um plan que promete `--reindex`
de states que nao existem. O erratum deve ser visivel para o checklist e o
analyze (consistencia cross-artifact).

**Alternatives considered**:
- Corrigir a C5 na spec agora: adiado — mudanca de spec em fase de plan exige
  ciclo proprio; o erratum aqui e rastreavel e o `/analyze` pode promover a
  correcao textual. A conclusao operacional da C5 nao muda.
- Adicionar `feature-00c-state` aos EXCLUDES como parte desta feature:
  rejeitado — escopo de outra feature (cstk-session); mudaria semantica de
  copia de sessao sem spec propria (Principio I).

---

## Decision 5 — Fallback em 3 camadas na ingestao (FR-003/FR-004)

**Decision**: a derivacao de `project` no ingest (`recall.sh`,
`recall_ingest_state_json` e `recall_ingest_memories`) passa a ser:

1. **Camada 1 (preferida)**: `.execution.canonical_project` do state.json,
   quando presente e nao-vazio.
2. **Camada 2 (fallback vivo)**: se ausente E `<target_project_path>/.git` e
   ARQUIVO E `git rev-parse --git-common-dir` resolve → canonico ao vivo
   (mesmo algoritmo da Decision 1). Cobre states antigos com worktree ainda
   em disco (US1 cenario 2).
3. **Camada 3 (fallback final)**: `basename(target_project_path)` —
   comportamento atual preservado byte-a-byte (US1 cenarios 3-4, FR-010).

Toda falha em qualquer camada degrada SILENCIOSAMENTE para a proxima
(FR-008): `2>/dev/null`, exit nunca propagado, nenhum abort de onda.

**Rationale**: e a abordagem B+A decidida pelo operador na spec. A camada 1 e
O(1) (campo ja no jq de leitura existente); a camada 2 so roda no caso raro
(state antigo + `.git` arquivo); a camada 3 e o codigo atual. Projetos
normais (`.git` diretorio) nunca pagam o custo do git (curto-circuito no
`test -f`).

**Alternatives considered**:
- Somente camada 1 + 3 (sem git ao vivo): rejeitado — US1 cenario 2 e
  requisito explicito (states antigos pre-feature com worktree viva).
- Cache do resultado da camada 2 de volta no state.json: rejeitado — o ingest
  e READ-ONLY sobre o state.json por invariante da feature cstk-knowledge-db
  (zero risco no caminho transacional). Escrever quebraria o contrato.

---

## Decision 6 — Schema v8: `ALTER TABLE ADD COLUMN session` em `executions` + `waves`; FTS INTOCADA

**Decision**: `RECALL_SCHEMA_VERSION` 7→8. Migracao em `recall_apply_schema`
segue o padrao aditivo JA EXISTENTE no arquivo (`recall.sh:638-648`, ALTERs
de `tasks.title` e `decisions.options`): `PRAGMA table_info(<tabela>)` para
checar presenca da coluna; se ausente, `ALTER TABLE <t> ADD COLUMN session
TEXT;`. DDL fresco (`recall_schema_ddl`) ja inclui `session TEXT` nos dois
CREATEs. `knowledge_fts` NAO recebe coluna `session`.

**Rationale**:
- O padrao PRAGMA+ALTER e idempotente, sem DROP, sem perda de dados — exato
  requisito do FR-009 e do edge case de schema da spec. SQLite nao tem
  `ADD COLUMN IF NOT EXISTS`; o guard via PRAGMA e a forma canonica ja em uso.
- **FTS fica fora por impossibilidade tecnica + risco**: FTS5 nao suporta
  `ALTER TABLE ADD COLUMN`; incluir `session` na FTS exigiria DROP + CREATE +
  repopulacao via reindex — mas o reindex NAO recupera entradas de states ja
  removidos (Decision 4). Dropar a FTS destruiria exatamente o conhecimento
  que esta feature quer proteger. Alem disso, a FTS so indexa os tipos de
  conhecimento (decision/block/retro/skill/memory/suggestion —
  `RECALL_TYPE_ENUM`, `recall.sh:94`); `executions`/`waves` sao telemetria
  (camada A do knowledge-db-metrics) e nunca estiveram na FTS.
- US2 AC3 ("sessao visivel no resultado ou na busca filtrada") e satisfeito
  pela via "busca filtrada": a coluna `session` e diretamente consultavel
  (query SQL documentada no quickstart; o cstk-panel — consumidor designado
  da camada de metricas — pode exibi-la). O output do `recall` de busca
  (alimentado pela FTS) permanece inalterado nesta feature.

**Alternatives considered**:
- DROP+CREATE da FTS com `session` (como o v7 fez com as tabelas pt→en):
  rejeitado — o v7 podia dropar porque reindex repopulava; aqui a premissa
  falha para worktrees removidas (Decision 4). Perda real de dados.
- Tabela separada `sessions(execution_id, session)`: rejeitado — overkill
  para um atributo 1:1 de execucao; coluna direta e mais simples e segue o
  padrao das demais colunas de proveniencia.

---

## Decision 7 — Paridade anti-eco: derivacao de `feature` (layout agente-00c) tambem usa o canonico; orquestradores atualizados em conjunto

**Decision**: o anti-eco (`--exclude-feature`) filtra pela coluna `feature`
(`recall.sh`, `recall_mode_context`: `AND feature != '<excl>'`). Hoje, no
layout `agente-00c-state/`, `feature = basename(projeto_alvo_path)`
(`recall.sh:775-778`) — que dentro de worktree seria o nome FANTASMA. Logo:

1. A derivacao de `feature` para o layout `agente-00c-state/` passa a usar o
   MESMO valor canonico de `project` (3 camadas da Decision 5). Layout
   `feature-00c-state/<short>/` segue usando o short-name (inalterado —
   short-name nao depende de path).
2. Os DOIS agentes (`global/agents/agente-00c-orchestrator.md` §read-back e
   `global/agents/agente-00c-feature-orchestrator.md` §4.bis) tem a derivacao
   de `EXCLUDE_FEATURE` atualizada NA MESMA MUDANCA: o agente-00c deriva de
   `.execution.canonical_project // basename(target_project_path)` (lido do
   proprio state); o feature-00c segue usando `short_name` (sem mudanca
   funcional, mas a nota de paridade e atualizada para citar esta feature).

**Rationale**: e o invariante acoplado documentado no bug v4.7.2 (memoria
`project_knowledge_db_agente00c_feature`, recuperada no read-back loop desta
onda): "o valor de `feature` ingerido para agente-00c DEVE ser igual ao
`--exclude-feature` do anti-eco; ambos derivam da mesma fonte; se um mudar e
o outro nao, o orquestrador ecoa as proprias escritas". FR-007 e US4 exigem
exatamente isso. Editar `cli/lib/recall.sh` + os 2 orchestrators juntos
(entrega: recall.sh via `cstk self-update`, agents via `cstk update`).

**Alternatives considered**:
- Manter `feature` fantasma e trocar o anti-eco para filtrar por `project`:
  rejeitado — quebraria o anti-eco do feature-00c (que exclui por short-name,
  nao por projeto) e mudaria semantica de coluna estavel da FTS.

---

## Decision 8 — Memorias de worktree (US5, P4 — doc-only por C2, com 1 ajuste de atribuicao no ingest)

**Decision**:

1. **Ingest ao vivo** (`recall_ingest_memories`, `recall.sh:1517-1528`): o
   DIRETORIO varrido continua sendo `~/.claude/projects/<encoded
   target_project_path>/memory/` (e la que o Claude Code grava as memorias da
   sessao que rodou NA worktree), mas a ATRIBUICAO `project` passa a usar a
   mesma derivacao canonica em 3 camadas (Decision 5). Resultado: memorias
   criadas durante sessao de worktree ficam pesquisaveis sob o projeto
   canonico.
2. **Reindex de memorias por diretorio** (`recall_ingest_memories_dir`,
   `recall.sh:1587-1594`, reverse-derivation do encoded path): comportamento
   MANTIDO e DOCUMENTADO — sem state.json associado, o reindex de um dir
   encoded de worktree atribui pelo basename do path (possivelmente
   fantasma). E a extensao natural da limitacao CQ1 ja registrada no codigo.
   Memorias de sessoes removidas permanecem IDENTIFICAVEIS por path via
   `cstk recall --list-memories` (US5 AC2) — o operador pode migrar/remover
   manualmente.

**Rationale**: C2 fixa o escopo minimo como "decisao explicitamente
documentada, sem silencio". O ajuste (1) e de baixo custo porque o ingest de
memorias JA le o state.json para derivar project (`recall.sh:1521-1528`) —
reaproveita a mesma funcao de derivacao da Decision 5, mantendo UMA fonte de
verdade. O item (2) e doc-only: reverse-derivation nao tem state para
consultar, e inventar resolucao extra para dirs orfaos seria especulativo.

**Alternatives considered**:
- Migrar fisicamente memorias de `<encoded worktree>` para `<encoded repo
  raiz>`: rejeitado — mexe em dados do harness (`~/.claude/projects/`) fora
  do contrato do toolkit; risco sem requisito que o justifique (P4).

---

## Decision 9 — Confinamento de deps e conformidade com amendment 1.1.0 (Principio II)

**Decision**: nenhuma dependencia nova. `git` na deteccao (command pai e
camada 2 do ingest) e invocacao OPCIONAL com fallback graceful (camadas 3 /
campo congelado); `sqlite3`/`jq` permanecem confinados onde ja estao
(`cli/lib/recall.sh` para sqlite3; jq ja e dep estabelecida do runtime
00C). A unica mencao nova a `git` em `cli/lib/recall.sh` (camada 2) mantem a
condicao (b) do amendment satisfeita por arquivo: grep por `git rev-parse`
localiza as mencoes em `cli/lib/recall.sh`, `cli/lib/session.sh` (ja
existente) e nos commands/agents 00C (markdown de orquestracao, nao script).

**Rationale**: condicoes (a)(b)(c) do amendment 1.1.0: (a) a feature funciona
sem git via campo congelado + fallback basename, coberto por teste (SC-005);
(b) confinamento por arquivo identificavel; (c) esta secao + spec §Decisoes
de Infraestrutura declaram a dep e o fallback.

---

## Resumo de unknowns

Nenhum `[NEEDS CLARIFICATION]` pendente. C1-C5 da spec cobertas; C5 herdada
COM erratum documentado (Decision 4).
