# Contract: deltas de interface do runtime (state-db-runtime-parity)

Interfaces CLI internas do runtime 00c alteradas/criadas pela feature. Toda
assinatura EXISTENTE abaixo foi extraida do codigo real (paths citados);
assinaturas novas estao marcadas `[PROPOSTA — a validar na implementacao]`.

**Protocolo de validacao das assinaturas `[PROPOSTA]` (CHK008, FASE 1/1.1.4):**
cada tarefa implementadora dona de uma assinatura proposta — 1.2.6
(`_state-read.sh`, §4), 3.1.7 (`set` multi-campo, §1), 4.2.5 (`acquire
--force`, §2) — MUST, no MESMO commit que entrega a implementacao:
(a) validar a assinatura shipada contra este contract via sonda empirica
(invocacao real do helper/teste, nao leitura de prosa); (b) em divergencia,
atualizar o texto do contract para a assinatura REAL, registrando Decisao
auditavel (`state-decisions.sh register`) com a justificativa da mudanca;
(c) remover o marcador `[PROPOSTA — a validar na implementacao]` da secao.
Gate verificavel: ao fim da FASE 4, `grep -c 'PROPOSTA' <este arquivo>`
retorna 0; marcador residual = tarefa implementadora incompleta.

## 1. `state-rw.sh set` — multi-campo atomico (FR-005)

Existente (fonte: `state-rw.sh:649` `_sr_cmd_set`):

```
state-rw.sh set --state-dir DIR --field F --value V
  # V = JSON valido (strings com aspas); exit 2 uso, exit 1 falha
```

Extensao `[PROPOSTA — a validar na implementacao]`:

```
state-rw.sh set --state-dir DIR --field F1 --value V1 [--field F2 --value V2]...
  # N pares aplicados atomicamente:
  #   JSON   = 1 write do documento com todos os setpaths
  #   SQLite = 1 transacao BEGIN IMMEDIATE...COMMIT com todos os fragmentos
  # 1 par => comportamento atual inalterado (retrocompat FR-004)
  # --value sem --field previo, ou --field sem --value ao fim => exit 2 (uso)
  # invariante violada (CHECK do schema) => exit 1 + diagnostico
  #   (invariante + campos do lote), estado intacto
  # MESMO --field repetido no lote => LAST-WINS na ordem de aplicacao
  #   (pares aplicados sequencialmente; o ultimo valor do path prevalece),
  #   NAO erro de uso. [CHK009, decisao FASE 1/1.1.1]
```

Rationale do last-wins (CHK009): (a) dedup textual nao capta equivalencia
semantica de paths jq (`.a.b` == `.a["b"]`) — um guard exit-2 parcial daria
falsa seguranca; (b) a aplicacao sequencial e a semantica natural dos DOIS
backends (JSON: setpaths encadeados num pipeline jq; SQLite: fragmentos em
ordem na mesma transacao); (c) continuidade observavel — o parser atual
(`state-rw.sh:649` `_sr_cmd_set`) ja faz last-wins para flags repetidas no
modo single-par (`--field) _f=$2` sobrescreve sem checagem).

Caso de uso canonico (promocao terminal sob C2 do schema):

```
state-rw.sh set --state-dir "$SD" \
  --field '.execution.status' --value '"concluida"' \
  --field '.execution.finished_at' --value "\"$TS\"" \
  --field '.execution.termination_reason' --value '"concluido"'
```

## 2. `state-lock.sh acquire --force` (FR-007)

Assinatura JA REFERENCIADA por contrato shipado (fonte:
`global/commands/feature-00c-abort.md:91`):

```
state-lock.sh acquire --state-dir "$AGENTE_00C_STATE_DIR" --force
```

Semantica `[PROPOSTA — a validar na implementacao]`:

- lock ausente: identico a `acquire` normal (mkdir, exit 0);
- lock detido: `rmdir` + `mkdir` na mesma invocacao, `diag_emit` evento
  `lock-force-acquired` (auditavel), exit 0;
- falha de rmdir/mkdir: exit != 0 com diagnostico;
- `acquire` SEM `--force`: byte-identico ao atual (exit 3 se detido).
- Pre-condicao CONTRATUAL (nao verificada pelo script): SIGTERM + grace 60s
  antes (`feature-00c-abort.md:59-91`); `--force` nunca e primeiro recurso.

## 3. `report.sh generate|emit` — exit 7 por estado ausente (FR-008)

Contrato consumidor (fonte: contrato de invocacao do feature-00c, "falha na
geracao do relatorio: exit 7 + estado preservado"). Implementacao atual
retorna `1` nas duas mortes (`report.sh:452` generate, `report.sh:552` emit,
pos-`a06e747`). Delta:

```
report.sh generate --state-dir DIR ...   # sem state.json E sem state.db legivel
report.sh emit --flavor F --state-dir DIR ...
  => exit 7 + diagnostico em stderr; estado (se algum) preservado
  # demais exit codes (2 uso, 1 falhas genericas) INALTERADOS
```

## 4. `_state-read.sh` — sibling sourceable de materializacao (Decision 1)

Validada na implementacao (task 1.2.6, onda-006 — assinatura confirmada
contra `global/skills/agente-00c-runtime/scripts/_state-read.sh` via
`tests/test__state-read.sh`, 9/9 cenarios verdes):

```
. "$(dirname -- "$0")/_state-read.sh"
sf=$(state_read_materialize "$STATE_DIR")   # imprime path legivel por jq
trap state_read_cleanup EXIT INT TERM        # remove tmps materializados
```

Garantias: nunca cria arquivo dentro do state-dir (FR-003); sob SQLite sem
`sqlite3` no host, propaga a falha rapida do `state-rw.sh read` (FR-012);
sob state-dir JSON devolve o proprio `state.json` (FR-004, zero mudanca).

Notas fixadas na implementacao: rastreio de tmps por PID do shell
principal (template `state-read.$$.XXXXXX` em `$TMPDIR`) porque o uso
canonico `$(...)` roda em subshell — registro por variavel de shell nao
sobreviveria ate o trap; `state-dir` vazio como argumento => exit 2 (uso);
resolucao do `state-rw.sh` como sibling de `$0`, override via
`STATE_READ_RW` para callers fora do diretorio (testes).
