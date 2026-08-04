# Contract: deltas de interface do runtime (state-db-runtime-parity)

Interfaces CLI internas do runtime 00c alteradas/criadas pela feature. Toda
assinatura abaixo foi extraida ou validada contra o codigo real (paths
citados).

**Protocolo de validacao das assinaturas propostas (CHK008, FASE 1/1.1.4) —
CONCLUIDO:** cada tarefa implementadora dona de uma assinatura proposta —
1.2.6 (`_state-read.sh`, §4, onda-006), 3.1.7 (`set` multi-campo, §1,
onda-012), 4.2.5 (`acquire --force`, §2, onda-013) — validou a assinatura
shipada via sonda empirica (invocacao real do helper/teste), atualizou o
texto para a assinatura REAL com Decisao auditavel em divergencia e removeu
o marcador da secao. Gate satisfeito: nenhum marcador residual neste arquivo.

## 1. `state-rw.sh set` — multi-campo atomico (FR-005)

Existente (fonte: `state-rw.sh:649` `_sr_cmd_set`):

```
state-rw.sh set --state-dir DIR --field F --value V
  # V = JSON valido (strings com aspas); exit 2 uso, exit 1 falha
```

Extensao (validada na implementacao — FASE 3, onda-012; assinatura conferida
por sonda empirica: `tests/test_state-rw.sh` 66/66, incl. promocao terminal
sob C2 e rejeicao all-or-nothing):

```
state-rw.sh set --state-dir DIR --field F1 --value V1 [--field F2 --value V2]...
  # N pares aplicados atomicamente:
  #   JSON   = 1 write do documento com todos os setpaths (pipeline jq unico)
  #   SQLite = 1 transacao BEGIN IMMEDIATE...COMMIT
  # 1 par => comportamento atual inalterado (retrocompat FR-004)
  # --value sem --field previo, ou --field sem --value ao fim => exit 2 (uso)
  # invariante violada (CHECK do schema) => exit 1 + diagnostico
  #   (invariante + campos do lote), estado intacto (rollback automatico)
  # MESMO --field repetido no lote => LAST-WINS na ordem de aplicacao
  #   (pares aplicados sequencialmente; o ultimo valor do path prevalece),
  #   NAO erro de uso. [CHK009, decisao FASE 1/1.1.1]
```

Deltas fixados na implementacao (divergencias vs a proposta original,
protocolo CHK008 — Decisao auditavel na onda-012):

- **CHECKs do SQLite sao avaliados POR STATEMENT, nao deferidos ao COMMIT**
  (verificado empiricamente: `BEGIN; UPDATE status; UPDATE finished_at;
  COMMIT` viola C2 com exit 19). "Todos os fragmentos na transacao" foi
  refinado para: colunas de `execution` coalescidas num UNICO UPDATE
  multi-coluna, e colunas de `wave` num UNICO UPDATE por onda (a tabela
  wave tambem tem CHECK cross-coluna `termination_reason x finished_at`).
  E isso que habilita a promocao terminal canonica. `SET col=a, col=b` e
  legal em SQLite com o ultimo vencendo — o last-wins do CHK009 sai da
  propria ordem dos pares.
- **Resyncs de array nao entram em lote** (`.events`, `.waves`,
  `.decisions`, `.human_blocks`, `.tasks`) nem o fallback extra_fields de
  campo de ONDA nao mapeado: o merge read-modify-write pre-transacao
  perderia updates entre pares do mesmo lote. Rejeicao explicita (exit 1)
  ANTES de qualquer escrita; o set single-field dedicado continua cobrindo
  esses paths integralmente.
- **`--field` repetido com par PENDENTE (sem `--value` entre eles)
  sobrescreve o pendente** — continuidade com o last-wins de flags do
  parser single-par anterior; nao e erro de uso.

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

Semantica validada na implementacao (FASE 4, onda-013 — sonda empirica:
`tests/test_state-lock.sh` 25/25, incl. os 9 cenarios novos de owner/force;
refinada pela mitigacao TOCTOU dec-059/block-001 → spec FR-007a):

```
state-lock.sh acquire --state-dir DIR [--force] [--owner-pid N]
```

- **Dono do lock (FR-007a)**: TODA aquisicao grava `<DIR>/.lock/owner`
  (`pid=` + `acquired_at=`) pos-mkdir, best-effort — o mkdir permanece a
  primitiva atomica. Default do pid: `$PPID`; override via `--owner-pid N`
  (numerico; senao exit 2). `check` e o diagnostico de contention do
  `acquire` reportam o dono (pid, vivo/morto, acquired_at); lock legado
  sem owner = dono-desconhecido.
- lock ausente: identico a `acquire` normal (mkdir + owner, exit 0; sem
  evento force);
- lock detido + dono VIVO (`kill -0` sucede): force RECUSADO — exit 3 +
  `diag_emit error lock-force-denied-owner-alive`; lock e owner intactos
  (dec-059: nunca forcar dono vivo);
- lock detido + dono morto (`kill -0` falha): remocao (`rmdir`, fallback
  `rm -rf` por causa do arquivo owner interno) + `mkdir` na mesma
  invocacao, `diag_emit warning lock-force-acquired` com pid antigo/novo,
  exit 0;
- lock detido legado SEM owner: consuma como dono-desconhecido com aviso
  explicito em stderr + `lock-force-acquired` (`pid antigo=desconhecido`);
- falha de remocao/mkdir: exit 1 + `diag_emit error
  lock-force-remove-failed` / `lock-force-reacquire-failed`;
- `acquire` SEM `--force`: comportamento preservado (exit 3 se detido;
  mensagens legadas intactas; adicoes: gravacao do owner na aquisicao e
  linha aditiva de dono no diagnostico de contention);
- `--force`/`--owner-pid` fora do `acquire`: exit 2 (uso).
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
