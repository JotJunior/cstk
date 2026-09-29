#!/bin/sh
# test_cstk-jira-plugin-manifest.sh — cobre plugins/cstk-jira/.claude-plugin/plugin.json
# (cstk-jira, FASE 1.1.3).
#
# Nao existe um script .sh "dono" de plugin.json (e um manifesto de dados
# estatico consumido pelo harness Claude Code, mesmo caso ja resolvido para
# plugins/cstk/hooks/hooks.json em test_plugin-hooks-manifest.sh). Este teste
# cobre apenas o schema minimo do plugin.json do NOVO plugin cstk-jira,
# independente do registro em marketplace.json (isso e coberto por
# test_validate-plugin-manifests.sh, atualizado na tarefa 1.2 quando o
# plugin for de fato registrado no marketplace).
#
# Invariantes cobertos:
#   PJ-1  plugin.json e JSON valido
#   PJ-2  .name == "cstk-jira"
#   PJ-3  .version e .description sao strings nao-vazias (schema minimo)

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

PLUGIN_JSON="$REPO_ROOT/plugins/cstk-jira/.claude-plugin/plugin.json"

scenario_plugin_json_existe_e_e_json_valido() {
  [ -f "$PLUGIN_JSON" ] || { _fail "existe" "plugin.json ausente: $PLUGIN_JSON"; return 1; }
  capture jq -e . "$PLUGIN_JSON"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "json_parseavel" "plugin.json nao e JSON valido: $PLUGIN_JSON"
    return 1
  fi
}

scenario_plugin_json_name_e_cstk_jira() {
  _name=$(jq -r '.name // ""' "$PLUGIN_JSON")
  [ "$_name" = "cstk-jira" ] || { _fail "name" "esperado 'cstk-jira', obtido '$_name'"; return 1; }
}

scenario_plugin_json_schema_minimo_version_e_description() {
  _version=$(jq -r '.version // ""' "$PLUGIN_JSON")
  _description=$(jq -r '.description // ""' "$PLUGIN_JSON")
  [ -n "$_version" ] || { _fail "version" "plugin.json sem .version"; return 1; }
  [ -n "$_description" ] || { _fail "description" "plugin.json sem .description"; return 1; }
}

run_all_scenarios
