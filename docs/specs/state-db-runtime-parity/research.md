# Research: Paridade do runtime 00c com o backend SQLite

**Feature**: `state-db-runtime-parity`
**Date**: 2026-08-02
**Input**: spec.md (5 US, 12 FRs) + diretrizes vinculantes do orquestrador (onda-003)

Todas as decisoes abaixo foram aterradas em sondas empiricas sobre o repo
(commit-base: pos-`a06e747`); nenhum fato foi suposto.

## Decision 1 — Estrategia de porte: helper sourceable comum (nao repetir o padrao 15x)

**Decision**: extrair o padrao de materializacao da v6.2.2 (commit `a06e747`,
funcao `_rp_state_file` de `report.sh`) para um sibling sourceable novo,
`global/skills/agente-00c-runtime/scripts/_state-read.sh`, consumido pelos
leitores do manifest FR-001. O helper expoe (nomes em ingles,
`[PROPOSTA — a validar na implementacao]`):

- `state_read_materialize STATE_DIR` — imprime o path de um arquivo JSON com o
  estado canonico: usa `STATE_DIR/state.json` direto quando existe; senao
  resolve o sibling `state-rw.sh` (`CDPATH= cd -- "$(dirname -- "$0")" && pwd -P`,
  padrao ja usado em `feature-00c-preflight.sh:76`) e materializa
  `state-rw.sh read` num `mktemp` (NUNCA dentro do state-dir — FR-003
  anti-mirror); registra o tmp para cleanup.
- `state_read_cleanup` — remove os tmps registrados; cada consumidor instala
  `trap state_read_cleanup EXIT INT TERM` (mesma disciplina do
  `_rp_cleanup_tmp_state` de `report.sh`).

**Rationale**:

1. **Precedente forte**: o runtime ja tem 10 siblings sourceable `_*.sh`
   (`_diag.sh`, `_log.sh`, `_hash.sh`, `_state-rw-db.sh`, `_state-dir.sh`,
   `_bloqueios-db.sh`, ...), cada um com teste proprio na convencao
   `tests/test__<nome>.sh` (8 arquivos `test__*` existentes). O helper novo se
   encaixa na convencao sem inventar mecanismo.
2. **Drift ja observado com apenas 2 copias**: `report.sh` e
   `feature-00c-preflight.sh` (ambos do fix minimo `a06e747`) ja carregam duas
   variantes quase-identicas do mesmo bloco (~30 linhas). Repetir em 14+
   scripts multiplicaria o drift — exatamente a classe de bug que a US5 quer
   extinguir.
3. **Custo do helper e pago uma vez**: +1 script (+`tests/test__state-read.sh`
   +cobertura `--check-coverage`); o hash_dir do manifest da skill absorve o
   arquivo novo automaticamente no build (nenhuma entrada manual de manifest
   por arquivo).
4. **A varredura estatica (FR-009b) fica mais forte**: com o helper, a
   allowlist de "codigo real que PODE tocar `state.json`" se reduz a
   `state-rw.sh`, `_state-rw-db.sh` (fundacao) e `_state-read.sh` (fallback
   JSON). Qualquer outro hit em codigo real = falha da varredura.

**Alternatives considered**:

- *Repetir o padrao por script (15x)* — rejeitado: ~30 linhas x 15 = ~450
  linhas duplicadas; drift inevitavel (ja ha 2 variantes); contradiz US5.
- *Subcomando novo `state-rw.sh materialize`* — rejeitado: `state-rw.sh read`
  ja e a interface canonica cross-backend; o que falta e apenas a disciplina
  tmp+trap+fallback do lado do consumidor, que e responsabilidade do caller
  (lifetime do tmp pertence ao processo consumidor, nao ao state-rw). Alem
  disso um subcomando que imprime path de tmp sem dono de cleanup vazaria
  arquivos.
- *Consolidar `report.sh`/`feature-00c-preflight.sh` no helper nesta feature* —
  ADOTADO como refactor incluido: os 2 scripts do fix minimo migram para o
  helper comum (elimina as 2 variantes), mantendo seus testes existentes
  verdes (`test_report.sh`, `test_feature-00c-preflight.sh` ja tem cenarios
  sqlite do a06e747 que provam equivalencia).

**Nuance obrigatoria — leitores que tambem ESCREVEM**: parte do manifest nao e
read-only: `cycles.sh tick`, `circular.sh push`, `retro.sh consume`,
`suggestions.sh register`, `state-cache.sh metrics-bump`/`set-resumo`
mutam estado. A materializacao cobre apenas a LEITURA; toda mutacao desses
helpers MUST ser roteada por `state-rw.sh set`/`write` (ja backend-agnosticos
na fundacao), nunca por write direto no tmp (que seria descartado) nem no
`state.json` (que pode nao existir). O plan.md classifica o manifest em
reader-only vs read-write e o quickstart tem cenario cobrindo um mutador.

## Decision 2 — `set` multi-campo: acumular pares e aplicar num unico write/transacao

**Decision**: estender o parser de `_sr_cmd_set` (`state-rw.sh:649`) para
acumular N pares `--field F --value V` (a flag `--value` fecha o par corrente;
ordem preservada). Aplicacao:

- **Backend JSON**: um unico pipeline jq que aplica todos os setpaths e um
  unico `_sr_atomic_write` (hoje ja e 1 write para 1 par; vira 1 write para N
  pares).
- **Backend SQLite**: refatorar `_sr_db_set` (`_state-rw-db.sh:657`) para
  separar a COMPOSICAO do statement da EXECUCAO transacional: cada par gera
  seu(s) fragmento(s) SQL (os cases existentes ja produzem fragmentos —
  `_sr_db_upsert_wave`, `_sr_db_upsert_decision`, `UPDATE execution SET ...`),
  e TODOS os fragmentos do lote sao envelopados num unico
  `BEGIN IMMEDIATE; ... COMMIT;` via `_state_db_exec_with_retry`. Hoje cada
  case abre a propria transacao; o refactor move o envelope para o dispatcher.

**Rationale**: a CHECK Constraint 2 do schema
(`references/state-db-schema.sql`, "consistencia status x finished_at":
`status IN ('abortada','concluida') AND finished_at IS NOT NULL` OU
`status IN ('em_andamento','aguardando_humano') AND finished_at IS NULL`)
rejeita QUALQUER estado intermediario da promocao terminal feita campo-a-campo
— e exatamente a falha de campo da spec (US2). Um unico envelope transacional
faz o SQLite avaliar as constraints no estado final do lote. Retrocompat
(FR-004): 1 par = mesmo caminho de codigo com lote de tamanho 1 —
comportamento e mensagens atuais preservados.

**FR-006 (diagnostico de rejeicao)**: capturar stderr do `sqlite3` na falha do
lote e mapear `CHECK constraint failed` para mensagem citando a invariante e
os campos do lote; transacao revertida = estado intacto por construcao. No
backend JSON nao ha CHECK equivalente (documento livre) — a rejeicao aplicavel
e a ja existente de `--value` nao-JSON; equivalencia contratual documentada no
contrato.

**Alternatives considered**: subcomando novo (`set-batch`) — rejeitado no
clarify (dec-008): interface unica, sem superficie nova.

## Decision 3 — `state-lock.sh acquire --force`: rmdir+mkdir numa invocacao unica auditavel

**Decision**: adicionar a flag `--force` ao subcomando `acquire`
(`state-lock.sh:103`): com `--force`, se o lock existe, remover
(`rmdir -- "$_SL_LOCK"`) e readquirir (`mkdir`) na MESMA invocacao, emitindo
diagnostico auditavel via `diag_emit` (canal ja usado no script, evento
proposto `lock-force-acquired`) registrando que a aquisicao foi forcada.
`acquire` sem `--force` permanece byte-identico (FR-007). A janela de race
rmdir→mkdir e documentada no cabecalho como herdeira da limitacao TOCTOU ja
aceita (CHK072, comentario `state-lock.sh:24-25`) — o clarify (dec-007) ja
estabeleceu que o substituto em 2 chamadas tem a MESMA janela sem a
auditabilidade.

**Rationale**: o contrato shipado ja invoca a flag
(`global/commands/feature-00c-abort.md:91`:
`state-lock.sh acquire --state-dir "$AGENTE_00C_STATE_DIR" --force`) com
SIGTERM + grace 60s ANTES (linhas 59-91) e proibicao explicita de
force-imediato (linha 172). Implementar a flag alinha implementacao ao
contrato sem emenda-lo. Restricao de uso (nunca primeiro recurso) permanece
CONTRATUAL (prosa do abort) — o script nao tem como verificar SIGTERM previo;
a auditoria via `diag_emit` + relatorio compensa.

**FR-010 (bonus do mesmo script)**: `check-execution-busy`
(`state-lock.sh:145-152`) le `state.json` via jq direto em CODIGO real
(consumido por `global/commands/agente-00c.md:149`) — portado no mesmo touch
via `_state-read.sh` (ja confirmado no clarify/Edge Cases da spec).

## Decision 4 — Exit 7 contratual em `report.sh` (generate E emit)

**Decision**: trocar o exit code das duas mortes por estado ausente —
`report.sh` `_rp_cmd_generate` (`_rp_die "generate: estado ausente ..." 1`) e
`_rp_cmd_emit` (`_rp_die "emit: estado ausente ..." 1`) — de `1` para `7`,
mantendo TODOS os demais `_rp_die`/`_rp_die_usage` inalterados.

**Rationale**: dec-011 (clarify, score 3): mesma classe de falha nos dois
subcomandos; o contrato de invocacao do feature-00c define exit 7 = "falha na
geracao do relatorio com estado preservado". A materializacao do a06e747 ja
garante que o check `[ -f "$_sf" ]` so falha quando NEM `state.json` NEM
`state.db` legivel existem — exatamente o cenario contratual.

## Decision 5 — Varredura anti-regressao FR-009: teste de composicao + registro no harness

**Decision**: criar `tests/test_state-parity-sweep.sh` com as duas camadas:

- **(a) DINAMICA**: fixture inicializa state-dir SQLite via `state-rw.sh init`
  (config global `state_backend=sqlite` simulada com `$HOME` falso — padrao ja
  usado na suite, cf. memoria `cli/lib resolve helper via CSTK_LIB`), popula
  estado (ondas/decisoes via primitivas), e executa o MANIFEST explicito dos
  leitores do FR-001 (lista literal no teste, um cenario por helper). Falha
  se: stdout/stderr contem `state.json ausente`; exit code diverge do
  contratual; ou existe `state.json` no state-dir apos a varredura (SC-004
  anti-mirror).
- **(b) ESTATICA**: `grep -n 'state\.json'` sobre
  `global/skills/agente-00c-runtime/scripts/*.sh` + `cli/lib/00c-bootstrap.sh`;
  cada hit fora da ALLOWLIST explicita (arquivo+classificacao) falha o teste.
  Allowlist inicial aterrada na auditoria FR-010 desta pesquisa:
  - codigo real legitimo: `state-rw.sh`, `_state-rw-db.sh` (fundacao),
    `_state-read.sh` (fallback JSON), `state-lock.sh` (path builder
    `_SL_STATE` usado só no fluxo JSON pos-porte, se restar);
  - prosa (comentarios/mensagens): `secrets-filter.sh`,
    `cli/lib/00c-bootstrap.sh:446` (mensagem de log sobre jq — UNICO hit do
    bootstrap; auditado nesta onda: o bootstrap le estado via probe de
    `state-rw.sh`, linha 457, ja conformante), cabecalhos/comentarios dos
    demais.
  A camada estatica compara HITS DE CODIGO (nao linhas de comentario `#` nem
  strings de mensagem listadas) — e o que detecta helper novo fora do manifest
  (US5 AS2).
- Registro no harness: o sweep nao mapeia 1:1 para um script — registrar em
  `tests/run.sh::_is_internal_test` com justificativa, precedente exato:
  `test_state-db-concurrency.sh` (decisao onda-013 da `state-db-foundation`,
  recuperada via read-back nesta onda).

**Rationale**: dec-009 do clarify fixa as duas camadas; o precedente de teste
de composicao interno ja existe no harness; manifest dinamico da a garantia
comportamental e o grep estatico a garantia estrutural (classe fechada).

## Decision 6 — Manifest de porte: classificacao reader-only vs read-write

Sonda desta onda (`grep -c 'state.json'` por script) confirma os 15 alvos do
FR-001 + os 2 achados FR-010. Classificacao para o design:

| Script | Hits | Classe | Observacao |
|---|---|---|---|
| `budget.sh` | 3 | reader | `_bd_state_file()` builder direto (`:48`) |
| `cycles.sh` | 6 | read-write | `tick` muta → `state-rw.sh set` |
| `circular.sh` | 7 | read-write | `push` muta |
| `drift.sh` | 10 | reader | `check`/`extract` |
| `retro.sh` | 4 | read-write | `consume` muta |
| `suggestions.sh` | 10 | read-write | `register` muta |
| `wave-usage-report.sh` | 19 | reader | maior contagem de hits |
| `model-routing.sh` | 14 | reader | `idempotent-check`/`wave-select` leem |
| `model-routing-report.sh` | 11 | reader | `aggregate` |
| `state-cache.sh` | 13 | read-write | `get-resumo` le; `metrics-bump` muta |
| `state-validate.sh` | 8 | reader | schema check sobre doc materializado |
| `state-decisions-reconcile.sh` | 6 | read-write | `check` le; `repair --apply` muta |
| `issue.sh` | 2 | read-write | registra issue no state |
| `pipeline.sh` | 2 | reader | |
| `cli/lib/00c-bootstrap.sh` | 1 | prosa | so mensagem de log (`:446`) — sem porte de codigo |
| `state-lock.sh` (FR-010) | 3 | reader | `check-execution-busy` e codigo real |

**Resolucao de sibling no unico consumidor fora do dir**: nenhum — o unico
script de `cli/lib/` no escopo (bootstrap) nao precisa de porte de codigo.
Todos os consumidores do helper vivem no MESMO diretorio de scripts do
runtime; a resolucao `dirname $0` cobre 100% dos casos.

## Unknowns restantes

Nenhum. Todos os NEEDS CLARIFICATION da spec foram resolvidos no clarify
(sessao 2026-08-02) e as diretrizes vinculantes do orquestrador foram
verificadas contra o codigo real nesta pesquisa.
