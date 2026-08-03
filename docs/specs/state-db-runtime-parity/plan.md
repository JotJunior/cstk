# Implementation Plan: Paridade do runtime 00c com o backend SQLite

**Feature**: `state-db-runtime-parity` | **Date**: 2026-08-02
**Spec**: [spec.md](./spec.md) | **Research**: [research.md](./research.md)

## Summary

Fecha a lacuna de paridade das fases 1/2 do cutover `state.json` → `state.db`:
os 14 helpers leitores do runtime + `check-execution-busy` do lock passam a
ler estado pela interface canonica (`state-rw.sh read`) via um sibling
sourceable novo `_state-read.sh` (padrao de materializacao da v6.2.2,
`a06e747`, extraido para helper comum — research.md Decision 1); `state-rw.sh
set` ganha N pares `--field/--value` atomicos (1 write JSON / 1 transacao
SQLite) para satisfazer a CHECK C2 do schema na promocao terminal;
`state-lock.sh acquire` ganha `--force` conforme o contrato do abort ja
shipado; `report.sh generate|emit` retorna exit 7 contratual por estado
ausente; e uma varredura anti-regressao em 2 camadas (manifest dinamico +
grep estatico com allowlist) impede reintroducao da classe.

## Technical Context

| Campo | Valor |
|---|---|
| Language | POSIX sh puro (Constitution II, NON-NEGOTIABLE) |
| Dependencies | `jq` (ja obrigatorio no runtime); `sqlite3 >= 3.45.1` APENAS na camada de estado transacional (carve-out amendment 1.3.0) |
| Storage | StateStore dual-backend existente (`state.json` / `state.db`) — schema INALTERADO |
| Testing | harness `tests/run.sh` (~1100 cenarios); convencao `tests/test_<nome>.sh` por script; siblings `tests/test__<nome>.sh`; `--check-coverage` gateante |
| Platform | macOS/zsh + Linux CI (nada GNU-only) |
| Project type | toolkit CLI/skills — single-layer (shell runtime ↔ SQLite embutido) |
| Idioma | codigo/identificadores em ingles; comentarios/mensagens pt-br |
| Fora de escopo | hooks (`posttooluse-tool-call-tick.sh`, `pretooluse-bash-guard.sh`) — feature separada (dec-010) |

NEEDS CLARIFICATION restantes: 0 (clarify 2026-08-02 + research desta onda).

## Constitution Check

*Gate inicial e re-check pos-design executados nesta onda (constitution
v1.3.0).*

| Principio | Status | Notas |
|---|---|---|
| I. SDD recursivo (MUST) | PASS | feature roda a pipeline completa (spec clarificada → plan → checklist → tasks) |
| II. POSIX sh puro (MUST) | PASS | helper novo e POSIX sh; `sqlite3` confinado ao carve-out 1.3.0 (camada de estado); nenhum dep novo |
| III. Formato canonico de skill | N/A | runtime interno (`agente-00c-runtime` nao e user-invocavel); nenhum SKILL.md tocado |
| IV. Zero coleta remota (MUST) | PASS | nenhuma rede; tudo local |
| V. Profundidade > metricas | PASS | elimina classe de bug (guardas silenciosamente desligadas) na raiz + rede permanente (US5) |
| VI. Veracidade de dados (MUST) | PASS | todo fato do plano aterrado em sonda (paths/linhas citados); assinaturas novas marcadas [PROPOSTA] no contrato |

**Re-check pos-design**: PASS — o design nao adiciona servico/camada; 1 helper
sourceable segue o precedente dos 10 `_*.sh` existentes; nenhuma violacao a
justificar em Complexity Tracking.

## Project Structure

### Documentation (este diretorio)

```
docs/specs/state-db-runtime-parity/
├── spec.md
├── plan.md                          # este arquivo
├── research.md                      # 6 decisions aterradas
├── data-model.md                    # invariantes + manifest + transicoes
├── quickstart.md                    # cenarios de validacao
└── contracts/
    └── runtime-interfaces.md        # deltas de interface CLI
```

### Source Code (paths reais verificados)

```
global/skills/agente-00c-runtime/scripts/
├── _state-read.sh                   # NOVO — sibling sourceable (Decision 1)
├── state-rw.sh                      # set multi-campo (parser _sr_cmd_set:649)
├── _state-rw-db.sh                  # envelope transacional unico (_sr_db_set:657)
├── state-lock.sh                    # acquire --force + porte check-execution-busy
├── report.sh                        # exit 7 (:452,:552) + migra p/ _state-read.sh
├── feature-00c-preflight.sh         # migra copia local p/ _state-read.sh
├── budget.sh cycles.sh circular.sh drift.sh retro.sh suggestions.sh
├── wave-usage-report.sh model-routing.sh model-routing-report.sh
├── state-cache.sh state-validate.sh state-decisions-reconcile.sh
├── issue.sh pipeline.sh             # 14 leitores portados (Decision 6)
cli/lib/
└── 00c-bootstrap.sh                 # SEM porte (hit :446 e prosa — auditado)
tests/
├── test__state-read.sh              # NOVO — teste do sibling
├── test_state-parity-sweep.sh       # NOVO — FR-009 (interno, _is_internal_test)
└── test_<cada script tocado>.sh     # cenarios sqlite adicionados (FR-011)
```

## Convencoes de Borda

Feature single-layer (runtime shell ↔ SQLite embutido no mesmo host — sem
frontend/API/broker). Declaracao minima da unica borda real:

| Camada | Convencao | Validacao | Fonte da verdade |
|---|---|---|---|
| Colunas SQLite (`execution`, ...) | snake_case EN | CHECK constraints do schema | `references/state-db-schema.sql` |
| Campos JSON do StateStore | EN canonico (pos-migracao pt→EN) | `state-validate.sh` + canonicalizador do `state-rw.sh` | `state-rw.sh` |
| Interface entre camadas | `state-rw.sh read/get/set/write` — UNICO ponto de acesso | varredura FR-009 (estatica + dinamica) | `contracts/runtime-interfaces.md` |

Mapper layer: `_state-rw-db.sh` (JSON doc ↔ linhas SQLite), ja existente na
fundacao — esta feature NAO o altera estruturalmente, apenas refatora o
envelope transacional do `set`.

## Fases de implementacao (ordem por dependencia)

1. **F1 — `_state-read.sh` + teste**: helper sourceable (materialize/cleanup)
   + `tests/test__state-read.sh` (JSON direto, SQLite via read, anti-mirror,
   sqlite3 ausente, state-dir vazio).
2. **F2 — porte dos 14 leitores + `state-lock.sh check-execution-busy`**: um
   commit logico por grupo; jq pipelines internos INALTERADOS (so a origem do
   arquivo muda); mutadores (cycles/circular/retro/suggestions/state-cache/
   reconcile/issue) roteiam escrita por `state-rw.sh set`; cenarios sqlite
   nos testes de cada script (FR-011). Migrar `report.sh` +
   `feature-00c-preflight.sh` para o helper (elimina as 2 copias do a06e747).
3. **F3 — `set` multi-campo**: parser N pares + envelope transacional unico
   em `_sr_db_set` + write unico JSON; testes de promocao terminal (C2),
   rejeicao com estado intacto, retrocompat 1 par.
4. **F4 — `acquire --force`**: flag + `diag_emit` + testes (lock orfao,
   sem-force byte-identico, lock ausente).
5. **F5 — exit 7 em `report.sh`**: generate + emit; testes de contrato.
6. **F6 — varredura FR-009**: `tests/test_state-parity-sweep.sh` (2 camadas)
   + registro `_is_internal_test` + validacao `--check-coverage` verde.

Riscos e mitigacoes: regressao JSON (FR-004) coberta por suite existente — os
testes atuais de cada script rodam inalterados sob JSON; performance da
materializacao (1 `state-rw.sh read` extra por invocacao de helper) e aceita —
helpers rodam 1x por onda, e o caminho JSON permanece zero-overhead (arquivo
usado direto).

## Security Review (gate owasp-security, fase plan)

Findings do gate sobre o desenho (0 CRITICAL/HIGH; detalhes na Decisao da
onda-003):

- **LOW/A05**: o envelope transacional do `set` multi-campo MUST compor cada
  fragmento exclusivamente pelos helpers existentes (`_sr_sql_literal`,
  `_sr_exec_col_lookup`, `_sr_sql_quote` → `sql_escape`+`strip_nul`) — nunca
  interpolar `--field`/`--value` crus no SQL do lote (requisito de task F3).
- **MEDIUM/ASI02-03**: `acquire --force` auditavel — teste MUST assertar que
  todo force-acquire emite `diag_emit lock-force-acquired`; restricao de uso
  permanece contratual (`feature-00c-abort.md:172`). Janela TOCTOU herdada de
  CHK072: MITIGADA por decisao do operador (dec-059/block-001, CHK019) — o
  lock ganha dono (PID gravado na aquisicao) e o `--force` so consuma com
  dono comprovadamente morto (`kill -0` falha) ou lock legado sem owner
  (aviso explicito); dono vivo e SEMPRE recusado. Ver spec FR-007a.
- **LOW/A04**: materializacao SEMPRE via `mktemp` (0600), fora do state-dir,
  removida por trap; jamais path previsivel.
- **INFO (positivo)**: fail-closed preservado (exit 7; FR-012 falha rapida);
  a feature religa guardas de orcamento/aborto hoje desligadas sob SQLite.

## Complexity Tracking

Vazio — nenhuma violacao de constitution a justificar.
