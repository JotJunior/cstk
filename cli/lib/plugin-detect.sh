# plugin-detect.sh — deteccao read-only de plugins do Claude Code
# instalados/habilitados (feature claude-plugin-packaging, FASE 6).
#
# Ref: docs/specs/claude-plugin-packaging/contracts/cli-plugin-awareness.md
#      §Helper compartilhado
#      docs/specs/claude-plugin-packaging/research.md Decision 4
#      docs/specs/claude-plugin-packaging/data-model.md Entity Distribution Path
#
# Funcoes exportadas:
#   plugin_enabled <nome>        — exit 0 instalado E habilitado;
#                                   1 nao (de forma definitiva);
#                                   2 indeterminado (jq ausente/JSON invalido)
#   plugin_install_path <nome>   — stdout=path absoluto do install mais
#                                   recente para "<nome>@*"; exit 0 ok, 1 nao
#                                   encontrado (inclusive jq ausente/JSON invalido)
#   plugin_hooks_present <nome>  — exit 0 se <installPath>/hooks/hooks.json
#                                   existe e e legivel; 1 caso contrario
#   plugin_settings_enabled <nome> — exit 0 se settings.json (SO esse
#                                   arquivo, NAO installed_plugins.json)
#                                   diz habilitado; 1 caso contrario
#                                   (arquivo ausente, JSON invalido, jq
#                                   ausente, ou nao habilitado). Sinal MAIS
#                                   FRACO que plugin_enabled — usado por
#                                   `cstk doctor` como GATE de exibicao da
#                                   secao Distribution Paths (contrato
#                                   Scenario 7: installed_plugins.json
#                                   corrompido, mas settings.json ainda diz
#                                   habilitado, MUST mostrar a secao com
#                                   status=undetermined, nao omiti-la).
#
# **jq sob amendment 1.1.0 (Optional dependencies with graceful fallback,
# docs/constitution.md)**: uso confinado a este arquivo (condicao b — grep
# por "jq" neste arquivo localiza toda mencao introduzida por esta feature).
# Ausencia de jq ou JSON malformado SEMPRE degrada — NUNCA falso-positivo:
#   - plugin_enabled: exit 2 (indeterminado)
#   - plugin_install_path / plugin_hooks_present: exit 1 (nao encontrado)
# Consumidores (hooks.sh, setup.sh, doctor.sh) tratam qualquer exit != 0
# de plugin_enabled como "nao habilitado" e seguem o caminho classico —
# falha de deteccao NUNCA pode suprimir a camada classica de guardas
# (contrato §Degradacao — assimetria deliberada).
#
# Fontes lidas (read-only — este arquivo NUNCA escreve nelas):
#   ~/.claude/plugins/installed_plugins.json  .plugins["<nome>@<mkt>"][].installPath
#   ~/.claude/settings.json                    .enabledPlugins["<nome>@<mkt>"] == true
#
# "<nome>" e o nome do plugin SEM marketplace (ex.: "cstk"); a chave real
# no registro nativo e "<nome>@<marketplace>" — casamos por PREFIXO
# "<nome>@" (com o "@" incluso, para "cstk@" nao casar "cstk-language-go@").
#
# POSIX sh puro, exceto pelo uso confinado de jq documentado acima.

if [ -n "${_CSTK_PLUGIN_DETECT_LOADED:-}" ]; then
  return 0 2>/dev/null
fi
_CSTK_PLUGIN_DETECT_LOADED=1

# shellcheck source=/dev/null
. "${CSTK_LIB:?CSTK_LIB must be set}/common.sh"

_plugin_detect_installed_json() {
  printf '%s' "${HOME:?HOME nao setado}/.claude/plugins/installed_plugins.json"
}

_plugin_detect_settings_json() {
  printf '%s' "${HOME:?HOME nao setado}/.claude/settings.json"
}

# plugin_install_path <nome>
#
# stdout = installPath absoluto do registro mais recente (maior
# lastUpdated, com installedAt como desempate/fallback) dentre as chaves
# "<nome>@*" de installed_plugins.json. Exit 0 se encontrado; 1 se o
# arquivo esta ausente, jq esta ausente, o JSON e invalido, ou nenhuma
# chave casa o prefixo — nenhum desses casos e distinguido no exit code
# (a funcao so tem 2 estados: ok/nao encontrado, por contrato).
plugin_install_path() {
  if [ "$#" -ne 1 ] || [ -z "$1" ]; then
    log_error "plugin-detect: plugin_install_path espera 1 argumento (nome)"
    return 1
  fi
  _pip_name=$1
  _pip_file=$(_plugin_detect_installed_json)

  [ -f "$_pip_file" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1

  _pip_path=$(jq -r --arg prefix "${_pip_name}@" '
    (.plugins // {})
    | to_entries
    | map(select(.key | startswith($prefix)))
    | map(.value)
    | flatten(1)
    | sort_by(.lastUpdated // .installedAt // "")
    | last
    | .installPath // empty
  ' -- "$_pip_file" 2>/dev/null) || return 1

  [ -n "$_pip_path" ] || return 1
  printf '%s\n' "$_pip_path"
  return 0
}

# plugin_hooks_present <nome>
#
# Exit 0 se <installPath>/hooks/hooks.json existe e e legivel; 1 caso
# contrario (inclusive quando plugin_install_path falha em resolver o
# path — plugin nao instalado conta como "hooks ausentes").
plugin_hooks_present() {
  if [ "$#" -ne 1 ] || [ -z "$1" ]; then
    log_error "plugin-detect: plugin_hooks_present espera 1 argumento (nome)"
    return 1
  fi
  _php_path=$(plugin_install_path "$1") || return 1
  [ -r "$_php_path/hooks/hooks.json" ]
}

# plugin_enabled <nome>
#
# Exit 0: instalado E habilitado (ambos os sinais — research.md Decision 4).
# Exit 1: nao habilitado de forma DEFINITIVA — arquivo ausente em qualquer
#         dos dois sinais, ou presente mas sem entrada casando/true.
# Exit 2: indeterminado — jq ausente, ou JSON invalido em qualquer um dos
#         dois arquivos. Consumidores MUST tratar exit 2 como "nao
#         habilitado" (fail-closed do lado da guarda classica).
plugin_enabled() {
  if [ "$#" -ne 1 ] || [ -z "$1" ]; then
    log_error "plugin-detect: plugin_enabled espera 1 argumento (nome)"
    return 2
  fi
  _pe_name=$1

  if ! command -v jq >/dev/null 2>&1; then
    return 2
  fi

  _pe_installed_file=$(_plugin_detect_installed_json)
  _pe_settings_file=$(_plugin_detect_settings_json)

  # Sinal 1: instalado.
  if [ ! -f "$_pe_installed_file" ]; then
    return 1
  fi
  if ! jq -e . -- "$_pe_installed_file" >/dev/null 2>&1; then
    return 2
  fi
  _pe_installed_count=$(jq -r --arg prefix "${_pe_name}@" '
    (.plugins // {}) | to_entries | map(select(.key | startswith($prefix))) | length
  ' -- "$_pe_installed_file" 2>/dev/null) || return 2
  case "$_pe_installed_count" in
    ''|*[!0-9]*) return 2 ;;
  esac
  [ "$_pe_installed_count" -gt 0 ] || return 1

  # Sinal 2: habilitado.
  if [ ! -f "$_pe_settings_file" ]; then
    return 1
  fi
  if ! jq -e . -- "$_pe_settings_file" >/dev/null 2>&1; then
    return 2
  fi
  _pe_enabled_count=$(jq -r --arg prefix "${_pe_name}@" '
    (.enabledPlugins // {}) | to_entries
    | map(select((.key | startswith($prefix)) and .value == true)) | length
  ' -- "$_pe_settings_file" 2>/dev/null) || return 2
  case "$_pe_enabled_count" in
    ''|*[!0-9]*) return 2 ;;
  esac
  [ "$_pe_enabled_count" -gt 0 ] || return 1

  return 0
}

# plugin_settings_enabled <nome>
#
# Verifica SOMENTE settings.json (ignora installed_plugins.json por
# completo). Exit 0 se habilitado; 1 em qualquer outro caso (arquivo
# ausente, JSON invalido, jq ausente, ou nao habilitado) — sinal binario,
# sem estado "indeterminado" (ao contrario de plugin_enabled), porque este
# helper existe apenas como GATE mais tolerante para `cstk doctor`: se nem
# o sinal fraco (so settings.json) confirma habilitacao, a secao
# Distribution Paths e omitida por completo (contrato §cstk doctor,
# status classic-only).
plugin_settings_enabled() {
  if [ "$#" -ne 1 ] || [ -z "$1" ]; then
    log_error "plugin-detect: plugin_settings_enabled espera 1 argumento (nome)"
    return 1
  fi
  _pse_name=$1

  command -v jq >/dev/null 2>&1 || return 1

  _pse_settings_file=$(_plugin_detect_settings_json)
  [ -f "$_pse_settings_file" ] || return 1
  jq -e . -- "$_pse_settings_file" >/dev/null 2>&1 || return 1

  _pse_count=$(jq -r --arg prefix "${_pse_name}@" '
    (.enabledPlugins // {}) | to_entries
    | map(select((.key | startswith($prefix)) and .value == true)) | length
  ' -- "$_pse_settings_file" 2>/dev/null) || return 1
  case "$_pse_count" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$_pse_count" -gt 0 ]
}
