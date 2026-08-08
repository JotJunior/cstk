#!/bin/sh
# test_plugin-hooks-manifest.sh — cobre plugins/cstk/hooks/hooks.json
# (claude-plugin-packaging, FASE 5.3.4).
#
# Nao existe um script .sh "dono" de hooks.json (e um manifesto de dados
# estatico consumido pelo harness Claude Code) — teste dedicado em vez de
# extensao de test_hooks-integration.sh (que cobre integracao install/
# update com o SNIPPET classico, escopo distinto).
#
# Invariantes cobertos (contracts/plugin-artifacts.md Artefato 4):
#   HK-1  conjunto de eventos/matchers identico ao settings.snippet.json classico
#   HK-2  posttooluse-loose-usage.sh ausente (opt-in nunca vira default)
#   HK-3  todo command invoca via sh "<path>"
#   HK-4  todo path e prefixado por ${CLAUDE_PLUGIN_ROOT}
#   HK-5  todo hook entry tem timeout: 5

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

PLUGIN_HOOKS="$REPO_ROOT/plugins/cstk/hooks/hooks.json"
CLASSIC_SNIPPET="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/hooks/settings.snippet.json"

_events_matchers() {
  jq -c '[.hooks | to_entries[] | .key as $ev | .value[] | {event:$ev, matcher:.matcher}] | sort_by(.event,.matcher)' "$1"
}

_all_commands() {
  jq -r '[.hooks | to_entries[] | .value[] | .hooks[] | .command] | .[]' "$1"
}

_all_timeouts() {
  jq -r '[.hooks | to_entries[] | .value[] | .hooks[] | (.timeout // "MISSING")] | .[]' "$1"
}

scenario_hooks_json_e_json_valido() {
  capture jq -e . "$PLUGIN_HOOKS"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "json_parseavel" "plugins/cstk/hooks/hooks.json nao e JSON valido"
    return 1
  fi
}

# HK-1: conjunto de eventos/matchers identico ao classico.
scenario_hk1_paridade_eventos_matchers() {
  [ -f "$CLASSIC_SNIPPET" ] || { _fail "snippet_classico_ausente" "$CLASSIC_SNIPPET nao encontrado"; return 1; }
  _plugin_em=$(_events_matchers "$PLUGIN_HOOKS")
  _classic_em=$(_events_matchers "$CLASSIC_SNIPPET")
  if [ "$_plugin_em" != "$_classic_em" ]; then
    _fail "hk1_paridade" "plugin=$_plugin_em classico=$_classic_em"
    return 1
  fi
}

# HK-2: posttooluse-loose-usage.sh ausente (opt-in nao vira default).
scenario_hk2_loose_usage_ausente() {
  _cmds=$(_all_commands "$PLUGIN_HOOKS")
  case "$_cmds" in
    *posttooluse-loose-usage.sh*)
      _fail "hk2_ausencia" "posttooluse-loose-usage.sh NAO deveria aparecer em hooks.json (opt-in): $_cmds"
      return 1
      ;;
  esac
}

# HK-3: todo command invoca via sh "<path>".
scenario_hk3_invocacao_via_sh() {
  _cmds=$(_all_commands "$PLUGIN_HOOKS")
  _OLD_IFS=$IFS
  IFS='
'
  for _c in $_cmds; do
    case "$_c" in
      'sh "'*'"') : ;;
      *)
        _fail "hk3_sh_wrapper" "command nao segue padrao sh \"<path>\": $_c"
        IFS=$_OLD_IFS
        return 1
        ;;
    esac
  done
  IFS=$_OLD_IFS
}

# HK-4: todo path e prefixado por ${CLAUDE_PLUGIN_ROOT}.
scenario_hk4_prefixo_claude_plugin_root() {
  _cmds=$(_all_commands "$PLUGIN_HOOKS")
  _OLD_IFS=$IFS
  IFS='
'
  for _c in $_cmds; do
    case "$_c" in
      *'${CLAUDE_PLUGIN_ROOT}'*) : ;;
      *)
        _fail "hk4_prefixo" "command sem prefixo \${CLAUDE_PLUGIN_ROOT}: $_c"
        IFS=$_OLD_IFS
        return 1
        ;;
    esac
  done
  IFS=$_OLD_IFS
}

# HK-5: timeout: 5 em toda entrada.
scenario_hk5_timeout_5() {
  _timeouts=$(_all_timeouts "$PLUGIN_HOOKS")
  _OLD_IFS=$IFS
  IFS='
'
  for _t in $_timeouts; do
    if [ "$_t" != "5" ]; then
      _fail "hk5_timeout" "timeout esperado=5, encontrado=$_t"
      IFS=$_OLD_IFS
      return 1
    fi
  done
  IFS=$_OLD_IFS
}

# Confirma que os 3 scripts referenciados de fato existem no plugin (nao
# so no classico) — evita hooks.json apontar para path que nao existe mais
# apos a relocacao da FASE 4.
scenario_scripts_referenciados_existem() {
  _cmds=$(_all_commands "$PLUGIN_HOOKS")
  _OLD_IFS=$IFS
  IFS='
'
  for _c in $_cmds; do
    # Extrai o path entre aspas duplas e substitui ${CLAUDE_PLUGIN_ROOT}
    # pela raiz real do plugin cstk (relativo a REPO_ROOT).
    _rel=$(printf '%s' "$_c" | sed -n 's/.*"\${CLAUDE_PLUGIN_ROOT}\(.*\)".*/\1/p')
    if [ -z "$_rel" ]; then
      _fail "extracao_path" "nao consegui extrair path relativo de: $_c"
      IFS=$_OLD_IFS
      return 1
    fi
    _abs="$REPO_ROOT/plugins/cstk$_rel"
    if [ ! -f "$_abs" ]; then
      _fail "script_referenciado_ausente" "$_abs nao existe (command: $_c)"
      IFS=$_OLD_IFS
      return 1
    fi
  done
  IFS=$_OLD_IFS
}

run_all_scenarios
