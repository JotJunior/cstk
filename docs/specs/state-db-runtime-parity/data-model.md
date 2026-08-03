# Data Model: state-db-runtime-parity

**Feature**: `state-db-runtime-parity` | **Date**: 2026-08-02

Nao ha entidade de dominio NOVA persistida: a feature altera o ACESSO ao
StateStore existente (fundacao `state-db-foundation`), nao seu schema. O
modelo abaixo descreve as entidades operacionais da spec e as invariantes que
o design precisa respeitar.

## Entity: StateStore

Estado de uma execucao 00c, persistido em UM de dois backends por state-dir.

| Aspecto | Backend JSON | Backend SQLite |
|---|---|---|
| Arquivo | `<state-dir>/state.json` | `<state-dir>/state.db` |
| Interface canonica de leitura | `state-rw.sh read/get` | idem (dispatch interno `_state-rw-db.sh`) |
| Interface canonica de escrita | `state-rw.sh set/write` | idem |
| Invariantes de consistencia | nenhuma imposta pelo storage | CHECK constraints do schema (abaixo) |

**Invariantes relevantes (fonte: `references/state-db-schema.sql`, tabela
`execution`)**:

- C1 — enum: `status IN ('em_andamento','aguardando_humano','abortada','concluida')`
- C2 — terminal↔timestamp: `(status IN ('abortada','concluida') AND finished_at IS NOT NULL) OR (status IN ('em_andamento','aguardando_humano') AND finished_at IS NULL)`
- C3 — profundidade: `subagent_depth >= 1 AND <= max_recursion`
- C4 — tetos: `cycles_consumed_current_stage <= max_cycles_per_stage`; `retro_executions_consumed <= max_retro_executions_per_feature`

C2 e a invariante que EXIGE a escrita multi-campo (FR-005): promocao terminal
campo-a-campo cria estado intermediario que C2 rejeita.

**Regra anti-mirror (FR-003)**: nenhum fluxo materializa `state.json` DENTRO
de um state-dir SQLite. Materializacoes de leitura vao para `mktemp` fora do
state-dir e sao removidas por trap.

## Entity: RuntimeHelper (manifest do porte)

Script POSIX que consome o StateStore. Estado do porte por classe (fonte:
research.md Decision 6):

| Classe | Scripts | Caminho de leitura pos-porte | Caminho de escrita pos-porte |
|---|---|---|---|
| reader | budget, drift, wave-usage-report, model-routing, model-routing-report, state-validate, pipeline, state-lock(`check-execution-busy`) | `_state-read.sh` → jq sobre arquivo materializado | n/a |
| read-write | cycles, circular, retro, suggestions, state-cache, state-decisions-reconcile, issue | idem | mutacao SEMPRE via `state-rw.sh set` (jamais write no tmp) |
| prosa (sem porte) | `cli/lib/00c-bootstrap.sh` | ja conformante (probe `state-rw.sh`) | n/a |

**Transicao de estado do helper (leitura)**:

```
state.json existe?  ──sim──> usa direto (retrocompat FR-004, zero mudanca)
       │nao
state-rw.sh (sibling) executavel?  ──nao──> path inexistente → diagnostico
       │sim                                  "estado ausente" do proprio helper
state-rw.sh read → mktemp  ──falha──> idem (inclui sqlite3 ausente: state-rw
       │ok                            ja falha rapido citando a dependencia,
       ▼                              FR-012)
jq pipelines EXISTENTES inalterados sobre o tmp; trap remove no exit
```

## Entity: LockHandle

Mutex de state-dir (`<state-dir>/.lock/`, mkdir atomico, nao-reentrante).

| Operacao | Antes | Depois |
|---|---|---|
| `acquire` | mkdir; exit 3 se detido | inalterado (byte-identico) |
| `acquire --force` | NAO EXISTE (referenciado por contrato) | rmdir do lock detido + mkdir, mesma invocacao; `diag_emit` de aquisicao forcada; exit 0 |
| `check` | exit 0 livre / 3 detido | inalterado |
| `check-execution-busy` | le `state.json` via jq direto | le via `_state-read.sh` (backend-agnostico); semantica de exits preservada (0 livre / 3 busy / 1 erro) |

**Restricao de uso do `--force`** (contratual, nao verificavel pelo script):
somente no fluxo de abort APOS SIGTERM + grace 60s
(`feature-00c-abort.md:59-91,172`). Janela TOCTOU rmdir→mkdir herdada da
limitacao CHK072 ja aceita e documentada.

## Operation: multi-field atomic set (FR-005/FR-006)

Assinatura: `state-rw.sh set --state-dir D --field F1 --value V1 [--field F2 --value V2 ...]`

| Backend | Aplicacao | Falha (invariante violada) |
|---|---|---|
| JSON | todos os setpaths num unico jq → 1 `_sr_atomic_write` | n/a estrutural (validacao de JSON por par preservada) |
| SQLite | fragmentos SQL de todos os pares num UNICO `BEGIN IMMEDIATE; ...; COMMIT;` | rollback da transacao inteira; stderr do sqlite3 mapeado para diagnostico com invariante + campos do lote; estado intacto |

Retrocompat: lote de tamanho 1 = comportamento atual (FR-004).

## Entity: SweepScenario

Teste de composicao `tests/test_state-parity-sweep.sh` (registrado como
interno no harness — precedente `test_state-db-concurrency.sh`).

| Camada | Input | Criterio de falha |
|---|---|---|
| dinamica | state-dir SQLite populado + manifest literal dos leitores FR-001 | qualquer helper emite `state.json ausente`; exit divergente do contratual; `state.json` presente no state-dir pos-varredura (SC-004) |
| estatica | `grep 'state\.json'` em `scripts/*.sh` + `cli/lib/00c-bootstrap.sh` | hit de CODIGO real fora da allowlist (research.md Decision 5) |
