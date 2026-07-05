# Contract: derivacao de `project`/`feature`/`session` na ingestao (recall.sh)

**Feature**: `recall-worktree-identity` | **Date**: 2026-06-05
**Arquivo**: `cli/lib/recall.sh` (UNICO arquivo tocado no runtime cstk —
confinamento de deps preservado; entrega via `cstk self-update`)
**Pontos de integracao**: `recall_ingest_state_json` (:741+),
`recall_ingest_memories` (:1517+), `recall_mode_reindex` (:2034+),
`recall_apply_schema` (:597+), `recall_schema_ddl` (:378+)

## 1. Funcao de derivacao canonica (nova, unica fonte de verdade)

```text
recall_derive_canonical STATE_JSON_PATH TARGET_PROJECT_PATH -> stdout: nome
```

| Camada | Condicao | Resultado |
|--------|----------|-----------|
| 1 | `.execution.canonical_project` presente e nao-vazio no state | esse valor (FR-003) |
| 2 | senao: `TARGET_PROJECT_PATH/.git` e ARQUIVO e `git -C <path> rev-parse --git-common-dir` resolve | `basename(dirname(common-dir absoluto))` (FR-004 viva) |
| 3 | senao | `basename(TARGET_PROJECT_PATH)` (FR-004 final = comportamento atual) |

Garantias:

- **Nunca falha**: toda subchamada com `2>/dev/null`; exit sempre 0; stdout
  sempre nao-vazio quando `TARGET_PROJECT_PATH` nao-vazio (FR-008).
- **POSIX sh puro**; `git` e invocacao opcional com fallback graceful
  (amendment 1.1.0 — condicoes (a)(b)(c) documentadas em research Decision 9).
- **Read-only sobre o state.json** (apenas jq de leitura — invariante da
  feature cstk-knowledge-db preservada).
- **Camada 2 normaliza common-dir relativo para absoluto antes do `dirname`**
  (CHK026): `git rev-parse --git-common-dir` pode retornar path RELATIVO (ex:
  `.git`) quando chamado no projeto raiz, ou ABSOLUTO quando chamado em
  worktree — depende da versao do git e do cwd. A normalizacao obrigatoria e:
  ```sh
  COMMON=$(git -C "$PAP" rev-parse --git-common-dir 2>/dev/null) || COMMON=""
  # Se relativo, prefixar com $PAP para obter absoluto (POSIX portatil)
  case "$COMMON" in
    /*) : ;;  # ja absoluto
    *)  COMMON="$PAP/$COMMON" ;;  # relativo → prefixar
  esac
  CANONICAL=$(basename "$(dirname "$COMMON")")
  ```
  Exemplo concreto: `COMMON="../../.git"` com `PAP="/tmp/wt-dir"` →
  `COMMON="/tmp/wt-dir/../../.git"` → `dirname` → `/tmp` → `basename` = `tmp`
  (nao ideal, mas determinístico; na pratica git-em-worktree retorna absoluto
  — sonda empirica git 2.50.1: worktree → absoluto, projeto-raiz → relativo).
  Alternativa: `--path-format=absolute` (git 2.37+) normaliza direto, mas cria
  dep de versao minima; a normalizacao manual POSIX acima e a via portatil.

## 2. Aplicacao por coluna e layout

| Coluna | `feature-00c-state/<short>/` | `agente-00c-state/` |
|--------|------------------------------|----------------------|
| `project` | `recall_derive_canonical(...)` | `recall_derive_canonical(...)` |
| `feature` | `short_name` (inalterado) | `recall_derive_canonical(...)` — substitui o basename bruto de `:775-778` |
| `session` | `.execution.session_name // NULL` | idem |

Aplica-se IDENTICAMENTE em `--ingest` (hook por onda + manual) e `--reindex`
(FR-006).

**Seguranca (A05 Injection — obrigatorio)**: os tres valores novos
(`canonical_project` derivado, `session`, e qualquer output de
`recall_derive_canonical`) sao UNTRUSTED (originam de basename de path do
filesystem e de campo de state.json) e MUST passar por `sql_escape()` ao
entrar em literais SQL — mesmo caminho dos valores existentes
(`recall.sh:879`, `:928`: `'$(sql_escape "$_isj_project")'`). A invocacao de
git na camada 2 MUST ser por vetor de argumentos com variaveis quotadas
(`git -C "$PATH" rev-parse --git-common-dir`), NUNCA via `eval`/interpolacao
em string de comando; usar apenas plumbing read-only (`rev-parse` — nao
comandos que tocam index/status, evitando vetores tipo `core.fsmonitor` de
repo hostil).

Memorias (`recall_ingest_memories`): diretorio varrido continua
`~/.claude/projects/<encoded target_project_path>/memory/`; atribuicao
`project` passa pela mesma funcao (research Decision 8).
`recall_ingest_memories_dir` (reverse-derivation, sem state) NAO muda —
limitacao documentada (CQ1 estendida).

## 3. Schema v8 (`recall_apply_schema` + `recall_schema_ddl`)

- `RECALL_SCHEMA_VERSION=8`.
- DDL fresco: `session TEXT` adicionada aos CREATEs de `executions` e
  `waves`; upserts `ON CONFLICT ... DO UPDATE SET` das duas tabelas ganham
  `session=excluded.session`.
- Migracao v7→v8 (bloco de ALTERs aditivos existente, `:638-648` como
  padrao): para cada tabela `executions`/`waves`, `PRAGMA table_info` checa a
  coluna `session`; ausente → `ALTER TABLE <t> ADD COLUMN session TEXT;`.
  Sem DROP; idempotente em re-execucao (FR-009/SC-006).
- Caminho pre-v7 existente (DROP one-time) inalterado — apos o drop, o DDL
  v8 ja cria as colunas.
- `knowledge_fts`: INTOCADA (research Decision 6 — FTS5 sem ADD COLUMN; drop
  perderia conhecimento de worktrees removidas).

## 4. Anti-eco (paridade FR-007) — contrato cruzado com os orquestradores

| Lado | Valor | Onde |
|------|-------|------|
| Ingestao | `feature` por layout (tabela §2) | `cli/lib/recall.sh` |
| agente-00c | `EXCLUDE_FEATURE = .execution.canonical_project // basename(target_project_path)` lido do PROPRIO state.json | `global/agents/agente-00c-orchestrator.md` §read-back |
| feature-00c | `--exclude-feature <short_name>` (inalterado) | `global/agents/agente-00c-feature-orchestrator.md` §4.bis |

REGRA DURA: os tres pontos mudam NA MESMA entrega (recall.sh via
`self-update`; agents via `update`). Divergencia = eco do proprio
conhecimento no read-back (bug v4.7.2; US4).

## 5. Saidas de consulta

- Busca FTS (`recall_mode_search`/`recall_mode_context`): output INALTERADO
  (a FTS nao carrega `session`).
- US2 AC3 (visibilidade de sessao) satisfeito via "busca filtrada": coluna
  `session` consultavel por SQL direto sobre `executions`/`waves` (cenario
  documentado no quickstart §3) e disponivel ao cstk-panel (consumidor da
  camada de metricas).

## 6. Testes (SC-005/SC-006)

`tests/cstk/test_recall.sh` ganha cenarios: derivacao em 3 camadas (com e sem
campo congelado; worktree fake com `.git` arquivo; git ausente via PATH
desacoplado — ver memoria `feedback_test_path_stub_cannot_hide_usrbin`),
coluna `session` populada e NULL, migracao v8 sobre fixture v7 sem perda,
anti-eco com nome canonico, no-regression projeto normal.
