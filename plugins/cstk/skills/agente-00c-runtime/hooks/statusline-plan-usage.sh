#!/bin/sh
# statusline-plan-usage.sh — entry-point de `statusLine.command` (feature
# plan-usage-capture, FASE 2). Configurado no `settings.json` do harness
# via a chave IRMA `statusLine.command` (distinta do array
# `.hooks.PostToolUse[]` que os demais hooks deste diretorio usam —
# research.md Decision 1).
#
# Contrato: docs/specs/plan-usage-capture/contracts/statusline-hook.md
# Research: docs/specs/plan-usage-capture/research.md (Decisions 1-6)
# Fonte do schema OBSERVADO do payload: memoria
# reference_statusline_usage_payload.md (Claude Code 2.1.226, macOS,
# 2026-08-10) — NAO INVENTAR campo fora dela (Constitution VI).
#
# Disciplina fail-open (molde: posttooluse-loose-usage.sh): sem `set -e`,
# cada passo trata a propria falha com no-op, exit SEMPRE 0, e o script
# MUST sempre emitir ALGO em stdout (contrato de saida — nunca deixar a UI
# da statusline em branco).
#
# `statusline-plan-usage.sh` roda FORA do processo `cstk` (invocado
# diretamente pelo harness) e por isso NAO tem acesso direto a
# `cli/lib/recall.sh` — a persistencia (extracao completa + throttle +
# INSERT) e delegada via subprocesso a `cstk plan-usage ingest --stdin`
# (research.md Decision 6, cli/lib/plan-usage.sh task 4.3). Este script
# extrai localmente so os campos necessarios para (a) decidir se vale a
# pena invocar o subprocesso (rate_limits ausente -> nem tenta) e (b)
# construir o fallback minimo de stdout (2.4.2) — NUNCA toca `sqlite3`
# diretamente (task 2.5.2).

set -u

# ---------------------------------------------------------------------------
# Passo 1: ler stdin UMA VEZ (necessario tanto para extracao quanto para
# encaminhar ao comando interno / forward de payload bruto).
# ---------------------------------------------------------------------------
_SPU_INPUT=$(cat 2>/dev/null) || _SPU_INPUT=""

# ---------------------------------------------------------------------------
# Passo 2: jq disponivel? (dep opcional confinada, research.md Decision 3)
# ---------------------------------------------------------------------------
_SPU_HAVE_JQ=0
command -v jq >/dev/null 2>&1 && _SPU_HAVE_JQ=1

# ---------------------------------------------------------------------------
# Passo 3: payload valido (JSON parseavel)? So tenta se jq disponivel e
# stdin nao-vazio. JSON malformado -> extracao pulada (task 2.1.4).
# ---------------------------------------------------------------------------
_SPU_VALID_JSON=0
if [ "$_SPU_HAVE_JQ" = 1 ] && [ -n "$_SPU_INPUT" ]; then
  if printf '%s' "$_SPU_INPUT" | jq empty >/dev/null 2>&1; then
    _SPU_VALID_JSON=1
  fi
fi

# ---------------------------------------------------------------------------
# Passo 4: extracao (task 2.1) — so quando jq+JSON validos. Campos NAO
# consumidos por esta feature (fora de escopo, FR-006): .cost,
# .context_window, .exceeds_200k_tokens, .thinking, .effort, .output_style,
# .version.
# ---------------------------------------------------------------------------
_SPU_SESSION_ID=""
_SPU_PROJECT_PATH=""
_SPU_MODEL_NAME=""
_SPU_HAS_RL="false"
_SPU_FH_USED=""
_SPU_FH_RESETS=""
_SPU_SD_USED=""
_SPU_SD_RESETS=""

if [ "$_SPU_VALID_JSON" = 1 ]; then
  _SPU_SESSION_ID=$(printf '%s' "$_SPU_INPUT" | jq -r '.session_id // ""' 2>/dev/null) || _SPU_SESSION_ID=""
  _SPU_PROJECT_PATH=$(printf '%s' "$_SPU_INPUT" | jq -r '.workspace.current_dir // .workspace.project_dir // ""' 2>/dev/null) || _SPU_PROJECT_PATH=""
  _SPU_MODEL_NAME=$(printf '%s' "$_SPU_INPUT" | jq -r '.model.display_name // ""' 2>/dev/null) || _SPU_MODEL_NAME=""
  _SPU_HAS_RL=$(printf '%s' "$_SPU_INPUT" | jq -r 'has("rate_limits")' 2>/dev/null) || _SPU_HAS_RL="false"
  if [ "$_SPU_HAS_RL" = "true" ]; then
    _SPU_FH_USED=$(printf '%s' "$_SPU_INPUT" | jq -r '.rate_limits.five_hour.used_percentage // ""' 2>/dev/null) || _SPU_FH_USED=""
    _SPU_FH_RESETS=$(printf '%s' "$_SPU_INPUT" | jq -r '.rate_limits.five_hour.resets_at // ""' 2>/dev/null) || _SPU_FH_RESETS=""
    _SPU_SD_USED=$(printf '%s' "$_SPU_INPUT" | jq -r '.rate_limits.seven_day.used_percentage // ""' 2>/dev/null) || _SPU_SD_USED=""
    _SPU_SD_RESETS=$(printf '%s' "$_SPU_INPUT" | jq -r '.rate_limits.seven_day.resets_at // ""' 2>/dev/null) || _SPU_SD_RESETS=""
  fi
fi

# Introspeccao de teste (task 2.1.5) — NUNCA stdout (contaminaria a UI),
# so stderr, e so quando explicitamente pedido via env var. Fixture de
# teste consome isto para validar a extracao sem depender do pipeline de
# persistencia (task 2.2) nem do contrato de pass-through (task 2.4).
if [ "${CSTK_STATUSLINE_DEBUG:-}" = "1" ]; then
  printf 'session_id=%s project_path=%s model=%s has_rate_limits=%s five_hour.used=%s five_hour.resets=%s seven_day.used=%s seven_day.resets=%s\n' \
    "$_SPU_SESSION_ID" "$_SPU_PROJECT_PATH" "$_SPU_MODEL_NAME" "$_SPU_HAS_RL" \
    "$_SPU_FH_USED" "$_SPU_FH_RESETS" "$_SPU_SD_USED" "$_SPU_SD_RESETS" >&2
fi

# ---------------------------------------------------------------------------
# Passo 5 (task 2.2/2.3): persistencia — delegada via subprocesso a
# `cstk plan-usage ingest --stdin` (research.md Decision 6). So tenta
# quando rate_limits esta presente (dec-029: ausencia total nunca gera
# INSERT, entao nem vale a pena invocar o subprocesso) e `cstk` esta
# resolvivel no PATH (task 2.5.1: `cstk`/`sqlite3` indisponivel -> captura
# pulada, sem erro). Payload BRUTO (nao os campos ja extraidos) e
# reencaminhado — o subcomando faz sua propria extracao completa +
# throttle + INSERT (4.3.2), este script so decide SE vale a pena chamar.
# Saida do subprocesso e sempre descartada (nunca contamina stdout/stderr
# da statusline — task 2.4.3).
# ---------------------------------------------------------------------------
if [ "$_SPU_VALID_JSON" = 1 ] && [ "$_SPU_HAS_RL" = "true" ]; then
  if _SPU_CSTK_BIN=$(command -v cstk 2>/dev/null) && [ -n "$_SPU_CSTK_BIN" ]; then
    printf '%s' "$_SPU_INPUT" | "$_SPU_CSTK_BIN" plan-usage ingest --stdin >/dev/null 2>&1 || :
  fi
fi

# ---------------------------------------------------------------------------
# Passo 6 (task 2.4): pass-through obrigatorio do stdout (contrato de
# saida — o script MUST sempre imprimir algo, nunca deixar a UI em branco;
# NUNCA imprimir erro de diagnostico em stdout).
# ---------------------------------------------------------------------------
if [ -n "${CSTK_STATUSLINE_INNER_COMMAND:-}" ]; then
  # Reencaminha o payload ORIGINAL (stdin intacto, inclusive se malformado
  # — pass-through best-effort do stdin cru, task 2.1.4/2.4.1) para o
  # comando interno e repassa o stdout dele verbatim.
  printf '%s' "$_SPU_INPUT" | sh -c "$CSTK_STATUSLINE_INNER_COMMAND" 2>/dev/null
  exit 0
fi

if [ "$_SPU_VALID_JSON" = 1 ]; then
  # Fallback minimo de 1 linha (2.4.2) — nao inventado, so campos ja
  # capturados desta mesma sessao (model.display_name + five_hour.used_percentage
  # quando disponivel).
  if [ -n "$_SPU_MODEL_NAME" ] && [ "$_SPU_MODEL_NAME" != "null" ]; then
    _SPU_LABEL="$_SPU_MODEL_NAME"
  else
    _SPU_LABEL="claude"
  fi
  if [ -n "$_SPU_FH_USED" ] && [ "$_SPU_FH_USED" != "null" ]; then
    printf '%s (%s%% used)\n' "$_SPU_LABEL" "$_SPU_FH_USED"
  else
    printf '%s\n' "$_SPU_LABEL"
  fi
else
  # Sem jq, ou JSON invalido/vazio: nao ha campo algum disponivel para
  # montar um fallback data-driven sem inventar (Principio VI) — 1 linha
  # neutra, nunca vazia (preserva a UI de quem nao configurou nada antes).
  printf 'claude\n'
fi

exit 0
