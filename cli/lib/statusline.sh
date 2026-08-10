#!/bin/sh
# statusline.sh — subcomando `cstk statusline` (feature plan-usage-capture,
# FASE 3 / tasks.md 3.1.1-3.1.6, dec-042).
#
# Provisiona a chave UNICA `statusLine.command` do settings.json do
# harness (research.md Decision 2, plan.md linha 17-24) apontando para
# `statusline-plan-usage.sh` (o entry-point de captura da FASE 2).
#
# Escopo: SEMPRE ${HOME}/.claude/settings.json — statusLine.command e uma
# preferencia de UI por operador (nao por projeto), paralelo ao que o
# proprio harness Claude Code trata como setting de usuario. Diferente de
# `cstk hooks install`, que e por-projeto (`--project-path`).
#
# Preservacao de customizacao previa (task 3.1.2, mitigacao do risco
# documentado em plan.md §Riscos conhecidos): se `statusLine.command` ja
# apontar para outro comando, o valor original e movido para a variavel
# de ambiente `CSTK_STATUSLINE_INNER_COMMAND`, e a nova chave passa a
# exportar essa variavel antes de invocar o script desta feature — o
# proprio script (`statusline-plan-usage.sh`, research.md Decision 2) le
# essa variavel e repassa o stdout do comando original verbatim
# (pass-through obrigatorio). NUNCA sobrescreve silenciosamente.
#
# Idempotencia (task 3.1.3): reinstalar detecta os dois formatos ja
# instalados (com ou sem customizacao previa) e e no-op — nunca aninha
# wrapper sobre wrapper.
#
# POSIX sh puro. Dep OPCIONAL: jq (carve-out ja vigente, research.md
# Decision 3) — ausente, aborta a escrita com orientacao de colagem
# manual (mesma disciplina de `cli/lib/hooks.sh` merge_settings).

if [ -n "${_CSTK_STATUSLINE_LOADED:-}" ]; then
  return 0 2>/dev/null
fi
_CSTK_STATUSLINE_LOADED=1

if [ -n "${CSTK_LIB:-}" ] && [ -f "$CSTK_LIB/common.sh" ]; then
  # shellcheck source=./common.sh
  . "$CSTK_LIB/common.sh"
fi

if ! command -v log_warn >/dev/null 2>&1; then
  log_info() { printf '[info] %s\n' "$*" >&2; }
  log_warn() { printf '[warn] %s\n' "$*" >&2; }
  log_error() { printf '[error] %s\n' "$*" >&2; }
fi

# _sl_detect_jq: exit 0 se jq disponivel, 1 se nao. Reusa detect_jq de
# hooks.sh quando ja carregado (mesmo processo `cstk`); senao checa
# diretamente — este arquivo pode ser sourceado standalone em teste.
_sl_detect_jq() {
  if command -v detect_jq >/dev/null 2>&1; then
    detect_jq
    return $?
  fi
  command -v jq >/dev/null 2>&1
}

# _sl_script_path CATALOG -> stdout: path do entry-point de captura sob o
# catalogo informado (default: ${HOME}/.claude).
_sl_script_path() {
  printf '%s/skills/agente-00c-runtime/hooks/statusline-plan-usage.sh' "$1"
}

# _sl_escape_single_quotes VALOR -> stdout: VALOR com toda aspas simples
# escapada para uso seguro dentro de aspas simples num comando de shell
# (' -> '\'').
_sl_escape_single_quotes() {
  printf '%s' "$1" | sed "s/'/'\\\\''/g"
}

_statusline_print_help() {
  cat >&2 <<'HELP'
cstk statusline — instala/inspeciona a captura de uso do plano via
statusLine.command (feature plan-usage-capture).

USO:
  cstk statusline install [--catalog DIR] [--dry-run]
  cstk statusline status  [--catalog DIR]

install:
  Escreve/atualiza a chave `statusLine.command` de
  ${HOME}/.claude/settings.json apontando para
  <catalog>/skills/agente-00c-runtime/hooks/statusline-plan-usage.sh
  (catalog default: ${HOME}/.claude).

  Se ja existir `statusLine.command` customizado (e distinto do script
  desta feature), o valor original e preservado movendo-o para a
  variavel de ambiente CSTK_STATUSLINE_INNER_COMMAND — NUNCA sobrescrito
  silenciosamente. Idempotente: rodar 2x seguidas nao aninha wrapper
  sobre wrapper.

status:
  Reporta se a captura esta instalada e ativa em
  ${HOME}/.claude/settings.json, sem escrever nada.

--catalog DIR: raiz do catalogo cstk (default: ${HOME}/.claude). Use para
apontar a um catalogo alternativo (ex: fixture de teste).
--dry-run: mostra o que seria escrito sem alterar settings.json.
HELP
}

# statusline_cmd_install [--catalog DIR] [--dry-run]
statusline_cmd_install() {
  _si_home="${HOME:?HOME nao setado}"
  _si_catalog="${_si_home}/.claude"
  _si_dry_run=0

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --catalog)
        [ "$#" -ge 2 ] || { log_error "statusline install: --catalog exige valor"; return 2; }
        _si_catalog=$2; shift 2 ;;
      --catalog=*) _si_catalog=${1#--catalog=}; shift ;;
      --dry-run) _si_dry_run=1; shift ;;
      -h|--help) _statusline_print_help; return 0 ;;
      *) log_error "statusline install: flag desconhecida: $1"; return 2 ;;
    esac
  done

  _si_script=$(_sl_script_path "$_si_catalog")
  if [ ! -f "$_si_script" ]; then
    log_error "statusline install: script nao encontrado: $_si_script"
    log_error "statusline install: rode 'cstk install' (ou 'cstk update') antes, ou passe --catalog DIR."
    return 1
  fi

  _si_settings="${_si_home}/.claude/settings.json"
  _si_settings_dir=$(dirname -- "$_si_settings")

  if ! _sl_detect_jq; then
    log_warn "statusline install: jq ausente — nao da para editar settings.json com seguranca."
    log_warn "statusline install: cole manualmente esta chave em $_si_settings:"
    printf '  "statusLine": { "command": "%s" }\n' "$_si_script" >&2
    return 1
  fi

  _si_cur=""
  if [ -f "$_si_settings" ]; then
    _si_cur=$(jq -r '.statusLine.command // empty' -- "$_si_settings" 2>/dev/null) || _si_cur=""
  fi

  case "$_si_cur" in
    "")
      _si_new="$_si_script"
      _si_msg="instalado (sem statusline previa)"
      ;;
    "$_si_script")
      log_info "statusline install: ja instalado e atualizado em $_si_settings (nada a fazer)"
      return 0
      ;;
    *"CSTK_STATUSLINE_INNER_COMMAND="*"$_si_script")
      log_info "statusline install: ja instalado (customizacao preservada) em $_si_settings (nada a fazer)"
      return 0
      ;;
    *)
      _si_escaped=$(_sl_escape_single_quotes "$_si_cur")
      _si_new="CSTK_STATUSLINE_INNER_COMMAND='${_si_escaped}' $_si_script"
      _si_msg="customizacao previa preservada em CSTK_STATUSLINE_INNER_COMMAND"
      ;;
  esac

  if [ "$_si_dry_run" = 1 ]; then
    log_info "[dry-run] statusline install: statusLine.command <- $_si_new ($_si_msg) em $_si_settings"
    return 0
  fi

  if [ ! -d "$_si_settings_dir" ]; then
    mkdir -p -- "$_si_settings_dir" || { log_error "statusline install: nao consegui criar $_si_settings_dir"; return 1; }
  fi

  if [ -f "$_si_settings" ]; then
    if ! cp -- "$_si_settings" "${_si_settings}.bak"; then
      log_error "statusline install: backup de $_si_settings falhou — abortando sem escrever"
      return 1
    fi
    _si_tmp=$(mktemp -- "${_si_settings_dir}/.cstk-statusline.XXXXXX") || {
      log_error "statusline install: mktemp em $_si_settings_dir falhou"
      return 1
    }
    if ! jq --arg cmd "$_si_new" '.statusLine.command = $cmd' -- "$_si_settings" > "$_si_tmp" 2>/dev/null; then
      log_error "statusline install: jq falhou ao mesclar $_si_settings (JSON invalido?)"
      rm -f -- "$_si_tmp"
      return 1
    fi
    if ! mv -f -- "$_si_tmp" "$_si_settings"; then
      log_error "statusline install: mv atomico falhou para $_si_settings"
      rm -f -- "$_si_tmp"
      return 1
    fi
  else
    if ! jq -n --arg cmd "$_si_new" '{"statusLine": {"command": $cmd}}' > "$_si_settings" 2>/dev/null; then
      log_error "statusline install: falha ao criar $_si_settings"
      return 1
    fi
  fi

  log_info "statusline install: $_si_msg ($_si_settings)"
  return 0
}

# statusline_cmd_status [--catalog DIR]
statusline_cmd_status() {
  _ss_home="${HOME:?HOME nao setado}"
  _ss_catalog="${_ss_home}/.claude"

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --catalog)
        [ "$#" -ge 2 ] || { log_error "statusline status: --catalog exige valor"; return 2; }
        _ss_catalog=$2; shift 2 ;;
      --catalog=*) _ss_catalog=${1#--catalog=}; shift ;;
      -h|--help) _statusline_print_help; return 0 ;;
      *) log_error "statusline status: flag desconhecida: $1"; return 2 ;;
    esac
  done

  _ss_script=$(_sl_script_path "$_ss_catalog")
  _ss_settings="${_ss_home}/.claude/settings.json"

  if [ ! -f "$_ss_settings" ]; then
    printf 'statusline: nao instalado (settings.json ausente: %s)\n' "$_ss_settings"
    return 1
  fi

  if ! _sl_detect_jq; then
    printf 'statusline: jq ausente — nao consigo inspecionar %s\n' "$_ss_settings"
    return 1
  fi

  _ss_cur=$(jq -r '.statusLine.command // empty' -- "$_ss_settings" 2>/dev/null) || _ss_cur=""
  if [ -z "$_ss_cur" ]; then
    printf 'statusline: nao instalado (statusLine.command ausente em %s)\n' "$_ss_settings"
    return 1
  fi

  case "$_ss_cur" in
    "$_ss_script")
      printf 'statusline: ativo (sem customizacao previa) -> %s\n' "$_ss_cur"
      return 0
      ;;
    *"CSTK_STATUSLINE_INNER_COMMAND="*"$_ss_script")
      printf 'statusline: ativo (customizacao previa preservada) -> %s\n' "$_ss_cur"
      return 0
      ;;
    *)
      printf 'statusline: statusLine.command aponta para outro comando (captura desta feature NAO ativa): %s\n' "$_ss_cur"
      return 1
      ;;
  esac
}

statusline_main() {
  _sl_sub="${1:-}"
  [ "$#" -ge 1 ] && shift || :

  case "$_sl_sub" in
    install) statusline_cmd_install "$@" ;;
    status) statusline_cmd_status "$@" ;;
    ''|-h|--help|help) _statusline_print_help; [ -z "$_sl_sub" ] && return 2 || return 0 ;;
    *)
      log_error "statusline: subcomando desconhecido: $_sl_sub (use: install, status)"
      return 2
      ;;
  esac
}
