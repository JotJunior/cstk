---
description: 'Aborta manualmente feature-00c para um short-name. SIGTERM + grace period 60s para persistir state; force-acquire do lock como fallback (FR-025). Marca abortada, gera relatorio parcial, commit local. Idempotente.'
argument-hint: "<short-name> [--motivo <texto>] [--purge-backups]"
allowed-tools:
  - Bash
  - Read
  - Write
---

# /feature-00c-abort

Voce vai abortar manualmente uma execucao feature-00c em andamento
conforme contrato em `docs/specs/_archived/feature-00c/contracts/cli-invocation.md`
+ spec §FR-025 (SIGTERM + grace period).

## Argumentos recebidos

```
$ARGUMENTS
```

## Comportamento esperado

### 1. Parse de argumentos

```
short_name        = primeiro argumento posicional (OBRIGATORIO)
--motivo TEXTO    = default = "aborto manual"
--purge-backups   = flag opcional; apaga backups/ apos abort
--projeto PATH    = default = cwd
```

### 2. Localizar state dir

```
_proj=$(realpath "$PROJETO")
AGENTE_00C_STATE_DIR="$_proj/.claude/feature-00c-state/$SHORT"
export AGENTE_00C_STATE_DIR

if [ ! -d "$AGENTE_00C_STATE_DIR" ] || [ ! -f "$AGENTE_00C_STATE_DIR/state.json" ]; then
  stderr "feature-00c-state inexistente para '$SHORT' em $_proj — nada para abortar"
  exit 1
fi
```

### 3. Idempotencia — status terminal ja?

```
_status=$(state-rw.sh get --state-dir "$AGENTE_00C_STATE_DIR" --field '.execucao.status')

case "$_status" in
  abortada|concluida)
    echo "execucao ja em status terminal ($_status); nenhuma acao."
    exit 0
    ;;
esac
```

### 4. SIGTERM + grace period (FR-025 atualizado)

```
# Detectar se ha PID detentor do lock
_lock_dir="$AGENTE_00C_STATE_DIR/.lock"
_pid=""
if [ -d "$_lock_dir" ] && [ -f "$_lock_dir/pid" ]; then
  _pid=$(cat "$_lock_dir/pid" 2>/dev/null)
fi

if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null; then
  # Processo da onda vivo — enviar SIGTERM e aguardar grace
  kill -TERM "$_pid" 2>/dev/null || true

  # Grace period: aguardar ate 60s pela liberacao
  _grace=60
  _waited=0
  while [ "$_waited" -lt "$_grace" ]; do
    if ! kill -0 "$_pid" 2>/dev/null; then
      break  # processo encerrou graciosamente
    fi
    sleep 2
    _waited=$((_waited + 2))
  done

  # Se ainda vivo apos grace, force-acquire (fallback)
  if kill -0 "$_pid" 2>/dev/null; then
    stderr "aviso: onda corrente nao respondeu SIGTERM em ${_grace}s; force-acquire do lock"
  fi
fi

# Force-acquire do lock (mesmo se PID encerrou graciosamente, normalize estado)
state-lock.sh acquire --state-dir "$AGENTE_00C_STATE_DIR" --force
```

### 5. Marcar status=abortada + terminada_em + motivo

```
_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
_motivo="${MOTIVO:-aborto manual}"

state-rw.sh set --state-dir "$AGENTE_00C_STATE_DIR" \
  --field '.execucao.status' --value '"abortada"'
state-rw.sh set --state-dir "$AGENTE_00C_STATE_DIR" \
  --field '.execucao.terminada_em' --value "\"$_ts\""
state-rw.sh set --state-dir "$AGENTE_00C_STATE_DIR" \
  --field '.execucao.motivo_termino' --value "\"$_motivo\""

# Recomputar hash
state-rw.sh sha256-update --state-dir "$AGENTE_00C_STATE_DIR"
```

### 6. Gerar backup final + relatorio parcial (FR-019: <60s)

```
_wave=$(state-rw.sh get --state-dir "$AGENTE_00C_STATE_DIR" --field '.ondas | length')
cat "$AGENTE_00C_STATE_DIR/state.json" | secrets-filter.sh for-backup \
  --wave-number "$_wave" > "$AGENTE_00C_STATE_DIR/backups/wave-$(printf '%03d' "$_wave").json"

report.sh emit --flavor feature-00c --short-name "$SHORT" \
  --state-dir "$AGENTE_00C_STATE_DIR" --parcial
```

### 7. Commit local

```
( cd "$_proj" && git add ".claude/feature-00c-state/$SHORT/" docs/specs/$SHORT/ && \
  git commit -m "feature-00c abort: $SHORT ($_motivo)" 2>/dev/null )
```

(Falha silenciosa se nao for repo git ou nada para commitar.)

### 8. Purge opcional de backups

```
if [ "$PURGE_BACKUPS" = "true" ]; then
  rm -rf -- "$AGENTE_00C_STATE_DIR/backups"
  stderr "backups apagados (--purge-backups)"
fi
```

### 9. Cleanup

- `state-lock.sh release --state-dir "$AGENTE_00C_STATE_DIR"` SEMPRE
- Imprimir path do relatorio em stdout:
  ```
  echo "$AGENTE_00C_STATE_DIR/feature-00c-report.md"
  ```

## Exit codes

| Exit | Significado |
|------|-------------|
| 0 | Sucesso (incluindo idempotente em status terminal) |
| 1 | state.json inexistente ou erro de I/O critico |
| 7 | Falha na geracao do relatorio parcial |

## SC-005 (ajustado): tempo total max 120s no pior caso

- 60s grace period (SIGTERM aguarda onda persistir)
- 60s geracao de relatorio + backup

Caller deve aguardar ate 120s antes de assumir falha. Em retomadas
sucessivas (caso reinvoque por timeout), idempotencia garante exit 0.

## Anti-padroes

- **NAO force-acquire imediato** sem SIGTERM + grace — pode deixar
  state.json em meio de escrita (corrupcao parcial).
- **NAO ler** state.json sem antes adquirir lock (force) — race com
  onda corrente em escrita.
- **NAO apagar** state.json no abort — preservar para audit. Use
  `--purge-backups` apenas para `backups/` (audit fica em state.json
  + report).
- **NAO chamar** ScheduleWakeup em abort — status terminal nao gera
  nova onda.
