#!/bin/sh
# orchestrator-refs.sh — resolve as referencias de fase dos orquestradores
# (agente-00c-orchestrator e agente-00c-feature-orchestrator), movidas do
# prompt-base para arquivos lidos sob demanda.
#
# Ref: docs/specs/orchestrator-slim/contracts/orchestrator-refs-cli.md
#      docs/specs/orchestrator-slim/spec.md FR-008, FR-009, FR-010
#
# Subcomandos:
#   path --orchestrator <root|feature> --phase <phase>
#       stdout: caminho absoluto de
#       <raiz>/references/orchestrators/<orchestrator>/<phase>.md
#       exit 0 = arquivo regular, nao-symlink, legivel, com diretorio fisico
#                sob references/orchestrators/
#       exit 1 = raiz nao resolvida OU arquivo ausente/ilegivel/fora do
#                confinamento (stdout vazio; stderr = diagnostico)
#       exit 2 = uso incorreto (flag ausente, orchestrator fora do enum,
#                phase fora de [a-z0-9-]+ — bloqueia path traversal)
#   list [--orchestrator <root|feature>]
#       stdout: <orchestrator>TAB<phase>TAB<caminho-absoluto>, sort
#       exit 0 = raiz resolvida (lista vazia e valida); 1 = raiz nao
#                resolvida; 2 = uso incorreto
#
# Resolucao da raiz: `resolve_runtime_root strict` (ordem B — diretorio-irmao
# de $0 primeiro). O conteudo resolvido vira INSTRUCAO no contexto do
# orquestrador; priorizar a ancora do proprio processo impede que variavel de
# ambiente de processo pai redirecione a leitura (achado F3/dec-027).
#
# Sem dependencia de jq/sqlite3. POSIX sh.

set -eu

_OR_NAME="orchestrator-refs"

_or_err() {
  printf '%s: %s\n' "$_OR_NAME" "$*" >&2
}

_or_usage() {
  _or_err "uso: $_OR_NAME.sh path --orchestrator <root|feature> --phase <phase>"
  _or_err "     $_OR_NAME.sh list [--orchestrator <root|feature>]"
}

# Bootstrap do helper de raiz: ancora irma primeiro (mesma ordem strict).
_OR_SELF_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd) || _OR_SELF_DIR=""
_or_helper=""
if [ -n "$_OR_SELF_DIR" ] && [ -r "$_OR_SELF_DIR/_resolve-root.sh" ]; then
  _or_helper="$_OR_SELF_DIR/_resolve-root.sh"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -r "${CLAUDE_PLUGIN_ROOT}/skills/agente-00c-runtime/scripts/_resolve-root.sh" ]; then
  _or_helper="${CLAUDE_PLUGIN_ROOT}/skills/agente-00c-runtime/scripts/_resolve-root.sh"
elif [ -n "${HOME:-}" ] && [ -r "$HOME/.claude/skills/agente-00c-runtime/scripts/_resolve-root.sh" ]; then
  _or_helper="$HOME/.claude/skills/agente-00c-runtime/scripts/_resolve-root.sh"
fi
if [ -z "$_or_helper" ]; then
  _or_err "helper _resolve-root.sh nao encontrado (irmao de \$0, plugin, classico)"
  exit 1
fi
# shellcheck disable=SC1090 # caminho resolvido dinamicamente pela cadeia acima
. "$_or_helper"

# _or_valid_orch VALOR -> 0 se root|feature
_or_valid_orch() {
  case "$1" in
    root|feature) return 0 ;;
    *) return 1 ;;
  esac
}

# _or_valid_phase VALOR -> 0 se nao-vazio e composto so de [a-z0-9-]
# Classe enumerada (nao o intervalo a-z): em locales nao-C o intervalo pode
# casar maiusculas (colacao), o que aceitaria `Clarify` como fase.
_or_valid_phase() {
  [ -n "$1" ] || return 1
  case "$1" in
    *[!abcdefghijklmnopqrstuvwxyz0123456789-]*) return 1 ;;
    *) return 0 ;;
  esac
}

# _or_confined FILE BASE_FISICA -> 0 se FILE e arquivo regular, nao-symlink,
# legivel, e o diretorio fisico (cd -P) esta sob BASE_FISICA.
_or_confined() {
  _oc_file="$1"
  _oc_base="$2"
  [ -L "$_oc_file" ] && return 1
  [ -f "$_oc_file" ] || return 1
  [ -r "$_oc_file" ] || return 1
  _oc_dir=$(CDPATH='' cd -P -- "$(dirname -- "$_oc_file")" 2>/dev/null && pwd -P) || return 1
  case "$_oc_dir" in
    "$_oc_base"|"$_oc_base"/*) return 0 ;;
    *) return 1 ;;
  esac
}

# _or_root_and_base -> define _OR_ROOT (raiz resolvida) e _OR_BASE (diretorio
# fisico de references/orchestrators). exit 1 se nao resolve.
_or_root_and_base() {
  _OR_ROOT=$(resolve_runtime_root strict) || return 1
  [ -n "$_OR_ROOT" ] || return 1
  _OR_BASE=$(CDPATH='' cd -P -- "$_OR_ROOT/references/orchestrators" 2>/dev/null && pwd -P) || _OR_BASE=""
  return 0
}

_or_cmd_path() {
  _orch=""
  _phase=""
  _have_orch=0
  _have_phase=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --orchestrator)
        [ $# -ge 2 ] || { _or_err "--orchestrator exige valor"; return 2; }
        _orch="$2"; _have_orch=1; shift 2 ;;
      --phase)
        [ $# -ge 2 ] || { _or_err "--phase exige valor"; return 2; }
        _phase="$2"; _have_phase=1; shift 2 ;;
      *) _or_err "flag desconhecida: $1"; _or_usage; return 2 ;;
    esac
  done
  [ "$_have_orch" -eq 1 ] || { _or_err "--orchestrator obrigatorio"; _or_usage; return 2; }
  [ "$_have_phase" -eq 1 ] || { _or_err "--phase obrigatorio"; _or_usage; return 2; }
  _or_valid_orch "$_orch" || { _or_err "orchestrator invalido: '$_orch' (esperado root|feature)"; return 2; }
  _or_valid_phase "$_phase" || { _or_err "phase invalida: '$_phase' (esperado [a-z0-9-]+)"; return 2; }

  _or_root_and_base || { _or_err "raiz do agente-00c-runtime nao resolvida"; return 1; }
  [ -n "$_OR_BASE" ] || { _or_err "diretorio references/orchestrators ausente em $_OR_ROOT"; return 1; }
  _file="$_OR_ROOT/references/orchestrators/$_orch/$_phase.md"
  if ! _or_confined "$_file" "$_OR_BASE"; then
    _or_err "referencia ausente, ilegivel ou fora do confinamento: $_file"
    return 1
  fi
  printf '%s\n' "$_file"
  return 0
}

_or_cmd_list() {
  _only=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --orchestrator)
        [ $# -ge 2 ] || { _or_err "--orchestrator exige valor"; return 2; }
        _only="$2"; shift 2 ;;
      *) _or_err "flag desconhecida: $1"; _or_usage; return 2 ;;
    esac
  done
  if [ -n "$_only" ]; then
    _or_valid_orch "$_only" || { _or_err "orchestrator invalido: '$_only' (esperado root|feature)"; return 2; }
  fi
  _or_root_and_base || { _or_err "raiz do agente-00c-runtime nao resolvida"; return 1; }
  [ -n "$_OR_BASE" ] || return 0
  {
    for _o in root feature; do
      [ -z "$_only" ] || [ "$_only" = "$_o" ] || continue
      for _f in "$_OR_ROOT/references/orchestrators/$_o"/*.md; do
        [ -e "$_f" ] || [ -L "$_f" ] || continue
        _or_confined "$_f" "$_OR_BASE" || continue
        _p=$(basename -- "$_f" .md)
        _or_valid_phase "$_p" || continue
        printf '%s\t%s\t%s\n' "$_o" "$_p" "$_f"
      done
    done
  } | LC_ALL=C sort
  return 0
}

if [ $# -lt 1 ]; then
  _or_usage
  exit 2
fi

_or_sub="$1"
shift
case "$_or_sub" in
  path) _or_cmd_path "$@" ;;
  list) _or_cmd_list "$@" ;;
  -h|--help|help) _or_usage; exit 0 ;;
  *) _or_err "subcomando desconhecido: $_or_sub"; _or_usage; exit 2 ;;
esac
