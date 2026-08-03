# Contract: deltas de interface do runtime (state-db-runtime-parity)

Interfaces CLI internas do runtime 00c alteradas/criadas pela feature. Toda
assinatura EXISTENTE abaixo foi extraida do codigo real (paths citados);
assinaturas novas estao marcadas `[PROPOSTA — a validar na implementacao]`.

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
```

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

`[PROPOSTA — a validar na implementacao]`:

```
. "$(dirname -- "$0")/_state-read.sh"
sf=$(state_read_materialize "$STATE_DIR")   # imprime path legivel por jq
trap state_read_cleanup EXIT INT TERM        # remove tmps materializados
```

Garantias: nunca cria arquivo dentro do state-dir (FR-003); sob SQLite sem
`sqlite3` no host, propaga a falha rapida do `state-rw.sh read` (FR-012);
sob state-dir JSON devolve o proprio `state.json` (FR-004, zero mudanca).
