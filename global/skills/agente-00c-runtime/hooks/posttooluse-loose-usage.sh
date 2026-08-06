#!/bin/sh
# posttooluse-loose-usage.sh — hook PostToolUse (todas as tools, opt-in):
# captura consumo avulso (fora de execucoes agente-00c/feature-00c) via
# segmentos otel-usage.sh persistidos em
# ~/.claude/cstk/loose-usage/<process_key>/.
#
# Contrato: docs/specs/loose-usage-capture/contracts/hook-loose-usage.md
# Data model: docs/specs/loose-usage-capture/data-model.md
#
# Molde: posttooluse-tool-call-tick.sh (EXISTENTE) — herda integralmente
# as invariantes fail-open: sem `set -e`, cada passo trata a propria
# falha com no-op, NUNCA toca state.json/state.db/knowledge.db, stdout e
# stderr SEMPRE vazios, exit SEMPRE 0. PostToolUse dispara CONCORRENTE as
# tool calls — nenhuma escrita compartilhada transacional acontece aqui.
#
# DIFERENCA de politica frente ao molde: gatilho por CSTK_OTEL_ENDPOINT
# (nao por CLAUDE_CODE_ENABLE_TELEMETRY/OTEL_METRICS_EXPORTER — esses dois
# NAO chegam ao subprocesso do harness, sug-001/research.md Decision 3).
#
# POLARIDADE INVERTIDA da deteccao de execucao ativa (dec-006): este hook
# capura quando NAO ha execucao 00c ativa (o oposto do tick de metrica, que
# so grava quando HA execucao ativa). Ver tabela de exit codes abaixo.
#
# Opt-in: registrado SOMENTE via `cstk hooks install --with-loose-usage`
# (flag default DESLIGADA) — NUNCA pelo snippet obrigatorio dos 3 hooks
# core (settings.snippet.json).

set -u

_PLU_SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd) || _PLU_SELF_DIR=""

# ---------------------------------------------------------------------------
# Passo 1: CSTK_OTEL_ENDPOINT presente? (ancora de identidade do processo)
# ---------------------------------------------------------------------------
_PLU_ENDPOINT="${CSTK_OTEL_ENDPOINT:-}"
[ -n "$_PLU_ENDPOINT" ] || exit 0

# ---------------------------------------------------------------------------
# Passo 2: jq disponivel? (dep opcional, fail-open — igual ao molde)
# ---------------------------------------------------------------------------
command -v jq >/dev/null 2>&1 || exit 0

# ---------------------------------------------------------------------------
# Passo 3: parse do stdin; .cwd e .tool_name nao-vazios
# ---------------------------------------------------------------------------
_PLU_INPUT=$(cat 2>/dev/null) || exit 0
[ -n "$_PLU_INPUT" ] || exit 0

_PLU_CWD=$(printf '%s' "$_PLU_INPUT" | jq -r '.cwd // ""' 2>/dev/null) || exit 0
_PLU_TOOL_NAME=$(printf '%s' "$_PLU_INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || exit 0

[ -n "$_PLU_CWD" ] || exit 0
# tool_name vazio = payload anomalo do harness; nao inventa captura.
[ -n "$_PLU_TOOL_NAME" ] || exit 0

[ -n "${HOME:-}" ] || exit 0

# ---------------------------------------------------------------------------
# Derivacao de process_key: funcao estavel de (endpoint, project_path),
# com owner_pid como componente adicional QUANDO obtenivel via lsof
# (Constitution VI: indeterminavel grava "unknown", jamais PID chutado).
# Reimplementado inline (nao sourceia otel-usage.sh — script nao projetado
# para ser sourceado, so invocado por subcomando) mas confinado a mesma
# logica de _ou_port_owner (otel-usage.sh linha 443).
# ---------------------------------------------------------------------------
_plu_sanitize() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9_.-' '_'
}

_plu_hash() {
  printf '%s' "$1" | cksum 2>/dev/null | awk '{print $1}'
}

_plu_ep_port() {
  case "$1" in
    http://127.0.0.1:[0-9]*|http://localhost:[0-9]*)
      _plu_p=${1#http://*:}
      _plu_p=${_plu_p%%/*}
      printf '%s' "$_plu_p"
      return 0 ;;
  esac
  return 1
}

_plu_port_owner() {
  command -v lsof >/dev/null 2>&1 || return 1
  _plu_own=$(lsof -nP -tiTCP:"$1" -sTCP:LISTEN 2>/dev/null | head -n 1)
  [ -n "$_plu_own" ] || return 1
  printf '%s' "$_plu_own"
}

_PLU_OWNER_PID="unknown"
if _PLU_EP_PORT=$(_plu_ep_port "$_PLU_ENDPOINT" 2>/dev/null); then
  if _PLU_OWNER=$(_plu_port_owner "$_PLU_EP_PORT" 2>/dev/null); then
    _PLU_OWNER_PID="$_PLU_OWNER"
  fi
fi

_PLU_KEY_BASE=$(_plu_sanitize "$(basename "$_PLU_CWD" 2>/dev/null)")
_PLU_KEY_HASH=$(_plu_hash "${_PLU_ENDPOINT}|${_PLU_CWD}")
[ -n "$_PLU_KEY_HASH" ] || exit 0
if [ "$_PLU_OWNER_PID" != "unknown" ]; then
  _PLU_PROCESS_KEY="${_PLU_KEY_BASE}-${_PLU_KEY_HASH}-${_PLU_OWNER_PID}"
else
  _PLU_PROCESS_KEY="${_PLU_KEY_BASE}-${_PLU_KEY_HASH}"
fi

_PLU_ROOT="$HOME/.claude/cstk/loose-usage"
_PLU_PROC_DIR="$_PLU_ROOT/$_PLU_PROCESS_KEY"
_PLU_META="$_PLU_PROC_DIR/meta.tsv"

# ---------------------------------------------------------------------------
# Permissao restritiva (CHK021, paridade recall_normalize_db_perms):
# best-effort, chamada apos cada mkdir/escrita. Nunca bloqueia o caller.
# ---------------------------------------------------------------------------
_plu_secure_dir() { chmod 700 -- "$1" 2>/dev/null || :; }
_plu_secure_file() { chmod 600 -- "$1" 2>/dev/null || :; }

# ---------------------------------------------------------------------------
# Throttle: epoch helpers (BSD/GNU date), mesma tecnica de budget.sh
# _bd_iso_to_epoch — reimplementada aqui pois a cadeia de dependencias do
# contrato so autoriza _hook-active-exec.sh + otel-usage.sh.
# ---------------------------------------------------------------------------
_plu_iso_to_epoch() {
  if _plu_e=$(date -u -d "$1" +%s 2>/dev/null); then
    printf '%s' "$_plu_e"; return 0
  fi
  if _plu_e=$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null); then
    printf '%s' "$_plu_e"; return 0
  fi
  return 1
}

_plu_now_epoch() { date -u +%s 2>/dev/null || printf '0'; }
_plu_now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf ''; }

# _plu_meta_get FIELD -> valor da chave em meta.tsv (formato chave<TAB>valor)
_plu_meta_get() {
  [ -f "$_PLU_META" ] || return 1
  awk -F '\t' -v k="$1" '$1==k {print $2; found=1} END {exit !found}' "$_PLU_META" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Passo 4: throttle O(1) — mais barato antes de sondar estado (passo 5).
# Sem meta.tsv (primeira captura do processo), NAO ha o que throttlear.
# ---------------------------------------------------------------------------
_PLU_INTERVAL="${CSTK_LOOSE_USAGE_INTERVAL_S:-300}"
case "$_PLU_INTERVAL" in
  ''|*[!0-9]*) _PLU_INTERVAL=300 ;;
esac

if [ -f "$_PLU_META" ]; then
  _PLU_LAST_UPDATED=$(_plu_meta_get updated_at) || _PLU_LAST_UPDATED=""
  if [ -n "$_PLU_LAST_UPDATED" ]; then
    _PLU_LAST_EPOCH=$(_plu_iso_to_epoch "$_PLU_LAST_UPDATED") || _PLU_LAST_EPOCH=0
    _PLU_NOW_EPOCH=$(_plu_now_epoch)
    _PLU_DELTA=$(( _PLU_NOW_EPOCH - _PLU_LAST_EPOCH ))
    if [ "$_PLU_DELTA" -lt "$_PLU_INTERVAL" ] 2>/dev/null; then
      exit 0
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Passo 5: deteccao de execucao ativa, polaridade INVERTIDA (dec-006).
#
# Pre-check inline com builtins PUROS do shell (SEC-H1, paridade com
# _ptt_precheck_active_scope do molde): se NAO ha nenhum state.json/
# state.db sob agente-00c-state/ ou feature-00c-state/*/, conclui
# "inativa" SEM resolver nem sourcear o helper — e segue direto para a
# captura. So quando o pre-check acha algum state presente e que vale a
# pena sondar de fato via _hook-active-exec.sh.
# ---------------------------------------------------------------------------
_plu_precheck_active_scope() {
  _plu_pa_agente="$_PLU_CWD/.claude/agente-00c-state"
  if [ -f "$_plu_pa_agente/state.json" ] || [ -f "$_plu_pa_agente/state.db" ]; then
    return 0
  fi

  _plu_pa_froot="$_PLU_CWD/.claude/feature-00c-state"
  if [ -d "$_plu_pa_froot" ]; then
    for _plu_pa_d in "$_plu_pa_froot"/*/; do
      [ -d "$_plu_pa_d" ] || continue
      if [ -f "${_plu_pa_d}state.json" ] || [ -f "${_plu_pa_d}state.db" ]; then
        return 0
      fi
    done
  fi
  return 1
}

_PLU_HAE_RC=1
if _plu_precheck_active_scope; then
  # _plu_resolve_dep_hae REL_PATH -> cadeia de resolucao para
  # _hook-active-exec.sh, ordem $HOME ANTES de <cwd> (mesma ordem
  # MODIFICADA do molde/contrato hook-active-exec.md), teste -r (helpers
  # _*.sh nao sao executaveis).
  _plu_resolve_dep_hae() {
    _plu_rel=$1
    if [ -n "$_PLU_SELF_DIR" ] && [ -r "$_PLU_SELF_DIR/../$_plu_rel" ]; then
      printf '%s' "$_PLU_SELF_DIR/../$_plu_rel"
      return 0
    fi
    if [ -n "${HOME:-}" ] && [ -r "$HOME/.claude/skills/agente-00c-runtime/$_plu_rel" ]; then
      printf '%s' "$HOME/.claude/skills/agente-00c-runtime/$_plu_rel"
      return 0
    fi
    if [ -n "${_PLU_CWD:-}" ] && [ -r "$_PLU_CWD/.claude/skills/agente-00c-runtime/$_plu_rel" ]; then
      printf '%s' "$_PLU_CWD/.claude/skills/agente-00c-runtime/$_plu_rel"
      return 0
    fi
    return 1
  }

  if _PLU_HAE_HELPER=$(_plu_resolve_dep_hae "scripts/_hook-active-exec.sh"); then
    # shellcheck disable=SC1090 # caminho resolvido dinamicamente pela cadeia de candidatos acima
    . "$_PLU_HAE_HELPER"

    # SEC-M2: mesma politica de contencao dos hooks de metrica (50ms) —
    # este hook NAO e uma guarda (fail-closed), e OK degradar sob contencao.
    HAE_BUSY_TIMEOUT_MS=50
    export HAE_BUSY_TIMEOUT_MS

    if _PLU_HAE_OUT=$(hook_active_exec "$_PLU_CWD" 2>/dev/null); then
      _PLU_HAE_RC=0
    else
      _PLU_HAE_RC=$?
    fi
  else
    # Helper irresolvivel apesar do pre-check ter achado state: trata como
    # indeterminada (nunca vira captura sob incerteza — Constitution VI).
    _PLU_HAE_RC=2
  fi
fi

# Resolucao de dependencia de otel-usage.sh (mesma cadeia, teste -x pois e
# executado como subprocesso, nao sourceado).
_plu_resolve_dep_otel() {
  _plu_rel=$1
  if [ -n "$_PLU_SELF_DIR" ] && [ -x "$_PLU_SELF_DIR/../$_plu_rel" ]; then
    printf '%s' "$_PLU_SELF_DIR/../$_plu_rel"
    return 0
  fi
  if [ -n "${HOME:-}" ] && [ -x "$HOME/.claude/skills/agente-00c-runtime/$_plu_rel" ]; then
    printf '%s' "$HOME/.claude/skills/agente-00c-runtime/$_plu_rel"
    return 0
  fi
  if [ -n "${_PLU_CWD:-}" ] && [ -x "$_PLU_CWD/.claude/skills/agente-00c-runtime/$_plu_rel" ]; then
    printf '%s' "$_PLU_CWD/.claude/skills/agente-00c-runtime/$_plu_rel"
    return 0
  fi
  return 1
}

# _plu_next_seg SEG_ID -> proximo id "seg-NNN" (zero-padded a 3 digitos).
# awk trata "008" como decimal 8 (sem armadilha de octal do $(( )) puro).
_plu_next_seg() {
  _plu_n=${1#seg-}
  awk -v n="$_plu_n" 'BEGIN{printf "seg-%03d", (n+0)+1}'
}

# _plu_write_meta SEGMENT CREATED_AT -> (re)escreve meta.tsv por completo,
# atomico (tmp + mv), chmod 600. updated_at = agora.
_plu_write_meta() {
  _plu_seg=$1
  _plu_created=$2
  _plu_now=$(_plu_now_iso)
  [ -n "$_plu_now" ] || return 1
  _plu_tmp="$_PLU_META.tmp.$$"
  {
    printf 'schema\t1\n'
    printf 'project_path\t%s\n' "$_PLU_CWD"
    printf 'endpoint\t%s\n' "$_PLU_ENDPOINT"
    printf 'owner_pid\t%s\n' "$_PLU_OWNER_PID"
    printf 'created_at\t%s\n' "$_plu_created"
    printf 'updated_at\t%s\n' "$_plu_now"
    printf 'current_segment\t%s\n' "$_plu_seg"
  } > "$_plu_tmp" 2>/dev/null || { rm -f -- "$_plu_tmp" 2>/dev/null; return 1; }
  mv -- "$_plu_tmp" "$_PLU_META" 2>/dev/null || { rm -f -- "$_plu_tmp" 2>/dev/null; return 1; }
  _plu_secure_file "$_PLU_META"
  return 0
}

case "$_PLU_HAE_RC" in
  0)
    # ATIVA: fecha o segmento aberto (se existir), NAO captura. Trecho
    # nao persistido e descartado (Decision 5 / state transition table).
    if [ -f "$_PLU_META" ]; then
      _PLU_CUR_SEG=$(_plu_meta_get current_segment) || _PLU_CUR_SEG=""
      if [ -n "$_PLU_CUR_SEG" ]; then
        _PLU_SEG_DIR="$_PLU_PROC_DIR/$_PLU_CUR_SEG"
        if [ -d "$_PLU_SEG_DIR" ] && [ ! -f "$_PLU_SEG_DIR/closed" ]; then
          : > "$_PLU_SEG_DIR/closed" 2>/dev/null || :
        fi
      fi
    fi
    ;;
  1)
    # INATIVA: captura (Passos 6-7).
    _PLU_OTEL=$(_plu_resolve_dep_otel "scripts/otel-usage.sh") || exit 0

    mkdir -p -- "$_PLU_ROOT" 2>/dev/null || exit 0
    _plu_secure_dir "$_PLU_ROOT"
    mkdir -p -- "$_PLU_PROC_DIR" 2>/dev/null || exit 0
    _plu_secure_dir "$_PLU_PROC_DIR"

    if [ ! -f "$_PLU_META" ]; then
      # Processo novo: primeiro segmento.
      _PLU_SEG="seg-001"
      _PLU_SEG_DIR="$_PLU_PROC_DIR/$_PLU_SEG"
      mkdir -p -- "$_PLU_SEG_DIR" 2>/dev/null || exit 0
      _plu_secure_dir "$_PLU_SEG_DIR"

      "$_PLU_OTEL" snapshot --state-dir "$_PLU_SEG_DIR" --phase start \
        --endpoint "$_PLU_ENDPOINT" >/dev/null 2>&1 || :
      _plu_secure_file "$_PLU_SEG_DIR/otel-start.tsv"

      _PLU_NOW=$(_plu_now_iso)
      [ -n "$_PLU_NOW" ] || exit 0
      _plu_write_meta "$_PLU_SEG" "$_PLU_NOW" || :
    else
      _PLU_CUR_SEG=$(_plu_meta_get current_segment) || _PLU_CUR_SEG=""
      _PLU_CREATED=$(_plu_meta_get created_at) || _PLU_CREATED=$(_plu_now_iso)
      [ -n "$_PLU_CUR_SEG" ] || exit 0
      _PLU_SEG_DIR="$_PLU_PROC_DIR/$_PLU_CUR_SEG"

      if [ -f "$_PLU_SEG_DIR/closed" ]; then
        # Segmento anterior fechado: abre um novo.
        _PLU_SEG=$(_plu_next_seg "$_PLU_CUR_SEG")
        _PLU_SEG_DIR="$_PLU_PROC_DIR/$_PLU_SEG"
        mkdir -p -- "$_PLU_SEG_DIR" 2>/dev/null || exit 0
        _plu_secure_dir "$_PLU_SEG_DIR"

        "$_PLU_OTEL" snapshot --state-dir "$_PLU_SEG_DIR" --phase start \
          --endpoint "$_PLU_ENDPOINT" >/dev/null 2>&1 || :
        _plu_secure_file "$_PLU_SEG_DIR/otel-start.tsv"
      else
        # Segmento aberto: reescreve o snapshot mais recente.
        mkdir -p -- "$_PLU_SEG_DIR" 2>/dev/null || exit 0
        _plu_secure_dir "$_PLU_SEG_DIR"
        _PLU_SEG="$_PLU_CUR_SEG"
        _PLU_PHASE="end"
        [ -f "$_PLU_SEG_DIR/otel-start.tsv" ] || _PLU_PHASE="start"

        "$_PLU_OTEL" snapshot --state-dir "$_PLU_SEG_DIR" --phase "$_PLU_PHASE" \
          --endpoint "$_PLU_ENDPOINT" >/dev/null 2>&1 || :
        _plu_secure_file "$_PLU_SEG_DIR/otel-$_PLU_PHASE.tsv"
      fi

      _plu_write_meta "$_PLU_SEG" "$_PLU_CREATED" || :
    fi
    ;;
  *)
    # indeterminada (2) / uso incorreto (3): no-op total (Constitution VI —
    # nunca captura sob incerteza).
    ;;
esac

exit 0
