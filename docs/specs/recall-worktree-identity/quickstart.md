# Quickstart: Recall Worktree Identity — cenarios de teste

**Feature**: `recall-worktree-identity` | **Date**: 2026-06-05
**Spec**: [spec.md](./spec.md) | **Contracts**: [contracts/](./contracts/)

Cenarios de validacao manual/automatizada. Os cenarios 1-2 e 4-6 devem virar
casos em `tests/cstk/test_recall.sh` e `tests/test_state-rw.sh` (SC-005).
Ambiente: `CSTK_KNOWLEDGE_DB` apontando para DB temporario em todos os
cenarios (nunca tocar o DB real do operador).

---

## Cenario 1 — Roundtrip REAL de ingestao com `canonical_project` (happy path, US1 AC1 + US2 AC1)

Roundtrip de verdade: state em disco → `cstk recall --ingest` real → query SQL
real no DB resultante (sem mock, sem fixture de output).

1. Criar worktree simulada: `mkdir -p /tmp/rwi/cstk-minha-feature && printf 'gitdir: /tmp/rwi/cstk/.git/worktrees/minha-feature\n' > /tmp/rwi/cstk-minha-feature/.git`
2. Criar state-dir `feature-00c-state/demo-feat/` com state.json minimo valido contendo `execution.target_project_path=/tmp/rwi/cstk-minha-feature`, `execution.canonical_project="cstk"`, `execution.session_name="minha-feature"`, `short_name="demo-feat"`, 1 decision e 1 wave.
3. `CSTK_KNOWLEDGE_DB=/tmp/rwi/k.db cstk recall --ingest --state-dir <state-dir>`
4. `sqlite3 /tmp/rwi/k.db "SELECT project, feature, session FROM executions;"`

**Expected**: `cstk|demo-feat|minha-feature` — projeto CANONICO (nao
`cstk-minha-feature`), feature = short-name, sessao preservada. Mesma checagem
em `waves` retorna `session='minha-feature'` (SC-001).

5. Comparar shape: `sqlite3 /tmp/rwi/k.db "PRAGMA table_info(executions);"` contem coluna `session` TEXT conforme [contracts/ingest-derivation.md §3](./contracts/ingest-derivation.md).

---

## Cenario 2 — Fallback em 3 camadas (US1 AC2-AC4)

**2a. Camada 2 (state antigo + worktree viva)**:
1. State SEM `canonical_project`, `target_project_path` apontando para worktree fake com `.git` ARQUIVO valido apontando para repo real criado com `git worktree add`.
2. Ingerir. **Expected**: `project` = basename do repo principal (resolucao git ao vivo).

**2a-rel. Sub-cenario: common-dir retornado como path RELATIVO** (CHK026):

> **Contexto empirico** (sonda git 2.50.1 em 2026-06-05): `git rev-parse --git-common-dir`
> retorna `.git` (RELATIVO) quando chamado NO projeto raiz, e um path ABSOLUTO quando
> chamado de uma worktree. Portanto o sub-caso de common-dir relativo ocorre quando
> a camada 2 e invocada com `target_project_path` sendo o proprio projeto raiz (nao
> deveria chegar aqui, mas o contrato garante o fallback). Na pratica, worktrees reais
> sempre retornam absoluto — mas a normalizacao defensiva e necessaria para versoes
> antigas de git ou caminhos inesperados.

Normalizacao esperada: `COMMON="../../.git"` → `"$PAP/$COMMON"` → `realpath` → `dirname`

1. State SEM `canonical_project`, `target_project_path=/tmp/rwi/wt-rel`, com `.git` sendo
   ARQUIVO contendo `gitdir: ../../main-repo/.git/worktrees/wt-rel` (path relativo
   simulando old git behavior).
2. Criar `/tmp/rwi/main-repo/.git/worktrees/wt-rel/gitdir` e `/tmp/rwi/main-repo/.git`
   como diretorio (fixture de repo raiz simulado).
3. Invocar a funcao `recall_derive_canonical` com `COMMON` = path relativo.
   Normalizacao deve prefixar `"$PAP/"` e resolver antes do `dirname`.
4. **Expected**: `project='main-repo'` (basename do diretorio pai do `.git` COMUM, resolvido
   via normalizacao absoluta). Exit 0.

Nota: `--path-format=absolute` (git 2.37+) pode ser usado em vez da normalizacao manual
quando disponivel, mas o contrato usa a normalizacao POSIX (`"$PAP/$COMMON"`) como via
portatil — nao depende de versao minima de git (FR-008).

**2b. Camada 3 (state antigo + worktree removida)**:
1. State SEM `canonical_project`, `target_project_path=/tmp/rwi/gone-cstk-x` (inexistente).
2. Ingerir. **Expected**: `project='gone-cstk-x'` (basename — comportamento anterior, sem erro, exit 0).

**2c. Sem regressao (projeto normal)**:
1. State SEM `canonical_project`, `target_project_path` com `.git` DIRETORIO.
2. Ingerir. **Expected**: `project` = basename, `session` NULL — byte-identico ao pre-feature (FR-010).

**2d. git ausente (error case FR-008)**:
1. Cenario 2a, mas com `git` fora do PATH do subprocesso de ingest (PATH desacoplado do SUT — nao tentar esconder `/usr/bin/git` por stub).
2. Ingerir. **Expected**: degrada para camada 3 silenciosamente; exit 0; nenhuma mensagem fatal.

---

## Cenario 3 — Busca filtrada por sessao (US2 AC3)

1. Apos o cenario 1: `sqlite3 /tmp/rwi/k.db "SELECT execution_id, project, session FROM executions WHERE session='minha-feature';"`

**Expected**: retorna a execucao ingerida. (A visibilidade de sessao e via
coluna consultavel — research Decision 6; o output da busca FTS permanece
inalterado.)

2. `CSTK_KNOWLEDGE_DB=/tmp/rwi/k.db cstk recall "qualquer-termo" --project cstk`

**Expected**: achados da execucao de worktree retornam sob `--project cstk`
(SC-002) — nenhum resultado exige `--project cstk-minha-feature`.

---

## Cenario 4 — Migracao v7→v8 idempotente sobre DB existente (SC-006, FR-009)

1. Criar fixture DB v7: aplicar o DDL v7 atual + `INSERT` de 1 linha em `executions` e 1 em `waves` + `schema_meta.schema_version='7'`.
2. Rodar qualquer comando que abra o DB com o codigo v8 (ex: `cstk recall --ingest` do cenario 1 apontando para este DB).
3. `sqlite3 db "PRAGMA table_info(executions);"` e `PRAGMA table_info(waves);`
4. `sqlite3 db "SELECT COUNT(*) FROM executions;"`

**Expected**: coluna `session` presente nas duas tabelas; linhas pre-existentes
INTACTAS (count inalterado, `session` NULL nelas); `schema_version='8'`.

5. Rodar o passo 2 NOVAMENTE. **Expected**: exit 0, sem erro de coluna duplicada (idempotencia).

---

## Cenario 5 — Anti-eco com nome canonico (US4, FR-007)

1. Apos o cenario 1 (execucao de worktree ingerida com `project='cstk'`; para o layout agente-00c, repetir com state em `agente-00c-state/` → `feature='cstk'`).
2. `CSTK_KNOWLEDGE_DB=/tmp/rwi/k.db cstk recall --context "<termos do conteudo ingerido>" --exclude-feature cstk`

**Expected**: achados da execucao agente-00c de worktree EXCLUIDOS (anti-eco
funciona com o nome canonico — US4 AC1).

3. `... --exclude-feature cstk-minha-feature`

**Expected**: achados RETORNAM (nenhum registro tem feature fantasma pos-correcao — US4 AC2).

---

## Cenario 6 — Init congela proveniencia (US3; contrato [state-rw-init.md](./contracts/state-rw-init.md))

1. `state-rw.sh init --state-dir /tmp/rwi/sd --projeto-alvo-path /tmp/rwi/cstk-minha-feature --descricao "t" --execucao-id e1 --canonical-project cstk --session-name minha-feature`
2. `jq '.execution.canonical_project, .execution.session_name' /tmp/rwi/sd/state.json`

**Expected**: `"cstk"` e `"minha-feature"` (US3 AC1).

3. Init SEM as flags. **Expected**: as duas chaves AUSENTES do JSON (US3 AC2) — `jq 'has' == false`.
4. Init com `--session-name x` SEM `--canonical-project`. **Expected**: exit 2 + mensagem de uso em stderr (error case).

---

## Cenario 7 — Fronteira do `--reindex` (FR-006/SC-003, doc + teste)

1. State congelado (cenario 1) com a worktree fake REMOVIDA do disco (`rm -rf /tmp/rwi/cstk-minha-feature`), state preservado.
2. `CSTK_KNOWLEDGE_DB=/tmp/rwi/k2.db cstk recall --reindex --states-root /tmp/rwi`
3. Query como no cenario 1.

**Expected**: `project='cstk'` identico ao ingest com worktree viva (SC-003 —
o campo congelado garante o resultado independente do disco). NOTA de
fronteira (research Decision 4): isto vale para states que EXISTEM no disco;
states que viviam so na worktree removida nao sao reindexaveis — a robustez
deles vem do ingest ao vivo ja ocorrido.

---

## Cenario 8 — Memorias de worktree (US5, doc-only por C2)

Verificacao documental: research Decision 8 e
[contracts/ingest-derivation.md §2](./contracts/ingest-derivation.md) declaram
explicitamente: (a) ingest de memorias atribui ao projeto canonico (varrendo o
encoded path REAL da worktree); (b) reverse-derivation do reindex de dirs
orfaos mantem atribuicao por path (limitacao CQ1 estendida); (c) memorias de
sessoes removidas identificaveis via `cstk recall --list-memories` (US5 AC2).

**Expected**: as tres declaracoes presentes nos artefatos (US5 AC1 — "sem
silencio sobre o comportamento"). Teste automatizado de atribuicao canonica de
memoria: opcional, recomendado junto ao cenario 1 (mesma fixture).
