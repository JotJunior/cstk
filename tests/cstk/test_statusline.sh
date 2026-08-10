#!/bin/sh
# test_statusline.sh — cobre cli/lib/statusline.sh (feature plan-usage-capture,
# FASE 3 / tasks.md 3.1.1-3.1.6).
#
# HOME e SEMPRE controlado via env HOME=<sandbox> (mesmo padrao de
# test_hooks.sh _hooks_main_run_home) — statusline install/status
# operam sobre ${HOME}/.claude/settings.json, e o guard global do
# repositorio proibe mutar o HOME real em teste.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CSTK_LIB="$REPO_ROOT/cli/lib"
export CSTK_LIB

_has_jq() {
  command -v jq >/dev/null 2>&1
}

# _sl_home_fixture: cria HOME sandbox com o catalogo minimo
# (${HOME}/.claude/skills/agente-00c-runtime/hooks/statusline-plan-usage.sh)
# copiado do arquivo real desta feature. Retorna o path do HOME via stdout.
# TMPDIR_TEST e unico por scenario (run_all_scenarios chama mktemp_test em
# subshell isolada para cada um), entao "home" simples ja basta.
_sl_home_fixture() {
  _slh_home="$TMPDIR_TEST/home"
  mkdir -p "$_slh_home/.claude/skills/agente-00c-runtime/hooks"
  cp "$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/hooks/statusline-plan-usage.sh" \
    "$_slh_home/.claude/skills/agente-00c-runtime/hooks/statusline-plan-usage.sh"
  printf '%s' "$_slh_home"
}

_sl_script_path_for() {
  printf '%s/.claude/skills/agente-00c-runtime/hooks/statusline-plan-usage.sh' "$1"
}

# _sl_run HOME_DIR ARGS...: invoca statusline_main sob HOME controlado.
_sl_run() {
  _slr_home=$1
  shift
  capture env HOME="$_slr_home" CSTK_LIB="$CSTK_LIB" sh -c \
    '. "$CSTK_LIB/statusline.sh" && statusline_main "$@"' _ "$@"
}

# ==== install: settings.json sem statusLine.command previo (task 3.1.5) ====

scenario_install_sem_statusline_previa_cria_chave() {
  if ! _has_jq; then _error "no_jq" "skip"; return 2; fi
  _home=$(_sl_home_fixture)
  _script=$(_sl_script_path_for "$_home")

  _sl_run "$_home" install
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }

  [ -f "$_home/.claude/settings.json" ] || { _fail "settings" "settings.json nao foi criado"; return 1; }

  _cmd=$(jq -r '.statusLine.command' "$_home/.claude/settings.json")
  [ "$_cmd" = "$_script" ] || { _fail "statusLine.command" "esperado $_script, obtido $_cmd"; return 1; }
  return 0
}

# ==== install: settings.json com statusLine.command customizado previo
#      (task 3.1.6) — valor original preservado em
#      CSTK_STATUSLINE_INNER_COMMAND, nova chave aponta pro script ====

scenario_install_preserva_customizacao_previa() {
  if ! _has_jq; then _error "no_jq" "skip"; return 2; fi
  _home=$(_sl_home_fixture)
  _script=$(_sl_script_path_for "$_home")
  mkdir -p "$_home/.claude"
  printf '{"statusLine":{"command":"~/my-old-statusline.sh --flag"},"other":{"key":"preserved"}}\n' \
    > "$_home/.claude/settings.json"

  _sl_run "$_home" install
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }

  _cmd=$(jq -r '.statusLine.command' "$_home/.claude/settings.json")
  case "$_cmd" in
    *"CSTK_STATUSLINE_INNER_COMMAND="*"~/my-old-statusline.sh --flag"*"$_script")
      ;;
    *)
      _fail "wrapper" "esperava wrapper com CSTK_STATUSLINE_INNER_COMMAND preservando o comando antigo + script novo; obtido: $_cmd"
      return 1
      ;;
  esac

  _other=$(jq -r '.other.key' "$_home/.claude/settings.json")
  [ "$_other" = "preserved" ] || { _fail "other-keys" "chaves nao relacionadas devem ser preservadas"; return 1; }
  return 0
}

# ==== install: aspas duplas dentro do comando previo sobrevivem ao
#      round-trip de escaping (aspas simples aninhadas) ====

scenario_install_preserva_customizacao_com_aspas() {
  if ! _has_jq; then _error "no_jq" "skip"; return 2; fi
  _home=$(_sl_home_fixture)
  jq -n '{"statusLine":{"command":"~/old.sh --flag \"quoted arg\" '\''single'\''"}}' \
    > "$_home/.claude/settings.json"

  _sl_run "$_home" install
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }

  # settings.json continua JSON valido apos a escrita (jq -e falha se invalido).
  jq -e . "$_home/.claude/settings.json" >/dev/null 2>&1 \
    || { _fail "json-valido" "settings.json corrompido apos escapar aspas"; return 1; }

  _inner=$(jq -r '.statusLine.command' "$_home/.claude/settings.json")
  case "$_inner" in
    *'"quoted arg"'*) ;;
    *) _fail "aspas-preservadas" "aspas duplas do comando original devem sobreviver: $_inner"; return 1 ;;
  esac
  return 0
}

# ==== Idempotencia (task 3.1.3): 2x seguidas produz o mesmo settings.json,
#      sem aninhar wrapper sobre wrapper ====

scenario_install_idempotente_sem_customizacao() {
  if ! _has_jq; then _error "no_jq" "skip"; return 2; fi
  _home=$(_sl_home_fixture)

  _sl_run "$_home" install
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "1a-install" "exit $_CAPTURED_EXIT"; return 1; }
  _before=$(cat "$_home/.claude/settings.json")

  _sl_run "$_home" install
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "2a-install" "exit $_CAPTURED_EXIT"; return 1; }
  _after=$(cat "$_home/.claude/settings.json")

  [ "$_before" = "$_after" ] || { _fail "idempotencia" "settings.json mudou entre a 1a e a 2a instalacao"; return 1; }
  return 0
}

scenario_install_idempotente_com_customizacao() {
  if ! _has_jq; then _error "no_jq" "skip"; return 2; fi
  _home=$(_sl_home_fixture)
  printf '{"statusLine":{"command":"~/my-old-statusline.sh"}}\n' > "$_home/.claude/settings.json"

  _sl_run "$_home" install
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "1a-install" "exit $_CAPTURED_EXIT"; return 1; }
  _once=$(jq -r '.statusLine.command' "$_home/.claude/settings.json")
  # nao deve haver wrapper duplo (uma unica ocorrencia da variavel).
  _n_wraps=$(printf '%s' "$_once" | grep -o 'CSTK_STATUSLINE_INNER_COMMAND=' | wc -l | tr -d ' ')
  [ "$_n_wraps" = 1 ] || { _fail "1-wrap" "esperado exatamente 1 wrap, obtido $_n_wraps"; return 1; }

  # 2a chamada: idempotente, NAO deve envolver o wrapper de novo.
  _sl_run "$_home" install
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "2a-install" "exit $_CAPTURED_EXIT"; return 1; }
  _twice=$(jq -r '.statusLine.command' "$_home/.claude/settings.json")

  [ "$_once" = "$_twice" ] || { _fail "no-double-wrap" "statusLine.command mudou na 2a chamada: $_once -> $_twice"; return 1; }
  return 0
}

# ==== status (task 3.1.4) ====

scenario_status_nao_instalado_settings_ausente() {
  _home=$(_sl_home_fixture)
  _sl_run "$_home" status
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit" "esperado 1 (nao instalado), obtido $_CAPTURED_EXIT"; return 1; }
  case "$_CAPTURED_STDOUT" in
    *"nao instalado"*) ;;
    *) _fail "mensagem" "stdout deveria reportar 'nao instalado': $_CAPTURED_STDOUT"; return 1 ;;
  esac
  return 0
}

scenario_status_ativo_apos_install() {
  if ! _has_jq; then _error "no_jq" "skip"; return 2; fi
  _home=$(_sl_home_fixture)
  _sl_run "$_home" install
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "install" "exit $_CAPTURED_EXIT"; return 1; }

  _sl_run "$_home" status
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0 (ativo), obtido $_CAPTURED_EXIT"; return 1; }
  case "$_CAPTURED_STDOUT" in
    *"ativo"*) ;;
    *) _fail "mensagem" "stdout deveria reportar 'ativo': $_CAPTURED_STDOUT"; return 1 ;;
  esac
  return 0
}

scenario_status_aponta_para_outro_comando() {
  if ! _has_jq; then _error "no_jq" "skip"; return 2; fi
  _home=$(_sl_home_fixture)
  printf '{"statusLine":{"command":"~/totally-unrelated.sh"}}\n' > "$_home/.claude/settings.json"

  _sl_run "$_home" status
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit" "esperado 1 (nao ativo), obtido $_CAPTURED_EXIT"; return 1; }
  case "$_CAPTURED_STDOUT" in
    *"NAO ativa"*) ;;
    *) _fail "mensagem" "stdout deveria reportar captura nao ativa: $_CAPTURED_STDOUT"; return 1 ;;
  esac
  return 0
}

# ==== jq ausente: degrada graciosamente (Principio II carve-out) ====

scenario_install_sem_jq_orienta_colagem_manual() {
  _home=$(_sl_home_fixture)
  _shim="$TMPDIR_TEST/shimbin-$$"
  mkdir -p "$_shim"
  for _cmd in sh mktemp awk sed grep find head printf cp mv rm mkdir chmod ls \
              dirname basename tr cut wc env command sort uniq date cat; do
    _src=$(command -v "$_cmd" 2>/dev/null) || continue
    ln -sf "$_src" "$_shim/$_cmd" 2>/dev/null || :
  done
  capture env -i PATH="$_shim" HOME="$_home" CSTK_LIB="$CSTK_LIB" sh -c \
    '. "$CSTK_LIB/statusline.sh" && statusline_main install'
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit" "esperado 1 (jq ausente), obtido $_CAPTURED_EXIT"; return 1; }
  [ ! -f "$_home/.claude/settings.json" ] \
    || { _fail "no-write" "nao deveria escrever settings.json sem jq"; return 1; }
  case "$_CAPTURED_STDERR" in
    *"jq ausente"*) ;;
    *) _fail "mensagem" "stderr deveria orientar sobre jq ausente: $_CAPTURED_STDERR"; return 1 ;;
  esac
  return 0
}

# ==== --dry-run: nao escreve nada ====

scenario_install_dry_run_nao_escreve() {
  if ! _has_jq; then _error "no_jq" "skip"; return 2; fi
  _home=$(_sl_home_fixture)
  _sl_run "$_home" install --dry-run
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ ! -f "$_home/.claude/settings.json" ] \
    || { _fail "no-write" "--dry-run nao deveria criar settings.json"; return 1; }
  return 0
}

# ==== script ausente no catalogo: erro claro ====

scenario_install_script_ausente_no_catalogo() {
  _home="$TMPDIR_TEST/home-vazio"
  mkdir -p "$_home/.claude"
  _sl_run "$_home" install
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  case "$_CAPTURED_STDERR" in
    *"script nao encontrado"*) ;;
    *) _fail "mensagem" "stderr deveria reportar script ausente: $_CAPTURED_STDERR"; return 1 ;;
  esac
  return 0
}

# ==== --help ====

scenario_help_imprime_uso() {
  _home=$(_sl_home_fixture)
  _sl_run "$_home" --help
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  case "$_CAPTURED_STDERR" in
    *"cstk statusline"*) ;;
    *) _fail "help" "stderr deveria imprimir texto de uso: $_CAPTURED_STDERR"; return 1 ;;
  esac
  return 0
}

run_all_scenarios
