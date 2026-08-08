#!/bin/sh
# _log.sh — Helpers POSIX sourceable para emissao de logs com filtro de
# secrets aplicado ANTES da emissao (FR-036).
#
# Ref: docs/specs/feature-00c/spec.md FR-036, FR-029 §"Escopo do filtro"
#      docs/specs/feature-00c/research.md Decision 6
#      docs/specs/feature-00c/tasks.md FASE 2 task 2.3.1
#
# NAO e executavel diretamente. Use:
#   . "$(dirname -- "$0")/_log.sh"
#   log_err "Erro: $detalhe"          # vai para stderr, filtrado
#   log_out "OK: gravado em $path"    # vai para stdout, filtrado
#
# Comportamento:
#   - Pipea cada mensagem por secrets-filter.sh scrub ANTES de emitir.
#   - Padrao fail-safe: se filtro falha (ex: secrets-filter.sh ausente),
#     emite mensagem RAW com prefixo "[NO-FILTER]" em stderr — preferindo
#     observabilidade degradada a silencio total.
#   - Sem `--env-file`: usa apenas regex estaticos do filtro (tokens,
#     AWS, Bearer, basic auth). Para projetos que carregam .env, callers
#     que tem o path podem chamar log_err_env / log_out_env (variantes
#     futuras — fora do MVP).

# _log_script_dir → diretorio onde secrets-filter.sh reside.
# Precedencia:
#   1. env var AGENTE_00C_RUNTIME_SCRIPTS_DIR (set explicitamente por caller)
#   2. dirname de $0 (funciona quando _log.sh foi sourceado de outro script)
# Razao: POSIX nao oferece forma portavel de descobrir o path do proprio
# arquivo quando ele e sourceado via `.` — `$0` aponta para o parent.
_log_script_dir() {
  if [ -n "${AGENTE_00C_RUNTIME_SCRIPTS_DIR:-}" ]; then
    printf '%s' "$AGENTE_00C_RUNTIME_SCRIPTS_DIR"
    return 0
  fi
  _d=$(dirname -- "$0")
  (cd "$_d" 2>/dev/null && pwd) || printf '%s' "$_d"
}

# _log_filter_cmd → path do secrets-filter.sh.
_log_filter_cmd() {
  _sd=$(_log_script_dir)
  printf '%s/secrets-filter.sh' "$_sd"
}

# log_err MESSAGE...
#   Emite mensagem em stderr apos passar por secrets-filter.sh scrub.
log_err() {
  _msg="$*"
  _f=$(_log_filter_cmd)
  if [ ! -x "$_f" ] && [ ! -f "$_f" ]; then
    printf '[NO-FILTER] %s\n' "$_msg" >&2
    return 0
  fi
  # Ordem critica: primeiro >&2 dup stdout para stderr, dai 2>/dev/null
  # silencia warnings do filtro. Sem essa ordem, redirecionamento
  # `2>/dev/null >&2` resulta em ambos fds apontando para /dev/null.
  _t=$(mktemp 2>/dev/null) || _t="/tmp/_log_err_$$"
  if printf '%s\n' "$_msg" | sh "$_f" scrub > "$_t" 2>/dev/null; then
    cat "$_t" >&2
    rm -f -- "$_t"
  else
    rm -f -- "$_t"
    printf '[NO-FILTER] %s\n' "$_msg" >&2
  fi
}

# log_out MESSAGE...
#   Emite mensagem em stdout apos passar por secrets-filter.sh scrub.
log_out() {
  _msg="$*"
  _f=$(_log_filter_cmd)
  if [ ! -x "$_f" ] && [ ! -f "$_f" ]; then
    printf '[NO-FILTER] %s\n' "$_msg"
    return 0
  fi
  _t=$(mktemp 2>/dev/null) || _t="/tmp/_log_out_$$"
  if printf '%s\n' "$_msg" | sh "$_f" scrub > "$_t" 2>/dev/null; then
    cat "$_t"
    rm -f -- "$_t"
  else
    rm -f -- "$_t"
    printf '[NO-FILTER] %s\n' "$_msg"
  fi
}
