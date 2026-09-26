#!/bin/sh
# jira-config.sh — leitura/validacao de ProjectConfig e checagem de
# Credential do plugin cstk-jira (feature cstk-jira, FASE 2 tarefa 2.1).
#
# Ref: docs/specs/cstk-jira/data-model.md Entity ProjectConfig, Entity
#      Credential; docs/specs/cstk-jira/contracts/plugin-scripts.md
#      `jira-config.sh`; docs/specs/cstk-jira/contracts/hooks.md (path do
#      config relativo ao cwd).
#
# Subcomandos:
#   jira-config.sh get KEY
#       — Le `<cwd>/.claude/cstk-jira/config` (key=value, `#`/linha em
#         branco ignorados); imprime o valor de KEY em stdout. Exit 3 se o
#         arquivo nao existir (FR-017 — plugin inativo, chamador trata como
#         no-op); exit 1 se KEY nao existir no arquivo.
#
#   jira-config.sh validate
#       — Confere presenca de todos os campos obrigatorios de ProjectConfig,
#         `site_host` como hostname puro (sem esquema/path/porta/userinfo) e
#         `status_fail != status_pass`. Exit 3 se o arquivo nao existir;
#         exit 1 com diagnostico em stderr no primeiro problema encontrado;
#         exit 0 (sem stdout) se tudo valido.
#
#   jira-config.sh credential-check
#       — Confere existencia e permissao exata 0600 do arquivo de
#         credencial (`${XDG_CONFIG_HOME:-$HOME/.config}/cstk-jira/credentials`).
#         NUNCA imprime o conteudo do arquivo. Exit 4 se ausente ou com
#         permissao diferente de 0600 (FR-016); exit 0 se ok.
#
# Convencoes (Principio II / contracts/plugin-scripts.md):
#   `#!/bin/sh`, `set -eu`, sem bash-isms; dados em stdout, diagnostico em
#   stderr. Exit codes: 0 sucesso; 1 erro geral; 2 uso incorreto; 3 plugin
#   inativo/nao configurado; 4 credencial ausente/rejeitada; 5 dependencia
#   ausente (nao usado neste script); 6 conflito/orfao (nao usado neste
#   script).
#
# Nenhum host/credencial e aceito por argumento (host vem de
# ProjectConfig.site_host, credencial de Credential — data-model.md).

set -eu

_JC_NAME="jira-config"

# CONFIG_FILE e relativo ao cwd (mesma convencao de contracts/hooks.md
# "<cwd>/.claude/cstk-jira/config") — script NUNCA aceita project-dir por
# argumento. Override apenas para uso interno de testes.
_JC_CONFIG_FILE="${CSTK_JIRA_CONFIG:-./.claude/cstk-jira/config}"

# Caminho da credencial: unico arquivo global por maquina (data-model.md
# Entity Credential), nunca por argumento.
_JC_CRED_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/cstk-jira/credentials"

_jc_die_usage() { printf '%s: %s\n' "$_JC_NAME" "$1" >&2; exit 2; }
_jc_die()       { printf '%s: %s\n' "$_JC_NAME" "$1" >&2; exit "${2:-1}"; }

_jc_usage() {
  cat <<'HELP'
jira-config.sh — leitura/validacao de ProjectConfig + checagem de Credential

USO:
  jira-config.sh get KEY             Le uma chave do config (stdout); exit 3 se ausente
  jira-config.sh validate            Valida campos obrigatorios + regras (data-model.md)
  jira-config.sh credential-check    Confere existencia + permissao 0600 da credencial

Config: <cwd>/.claude/cstk-jira/config (key=value, '#' comenta linha inteira)
Credencial: ${XDG_CONFIG_HOME:-$HOME/.config}/cstk-jira/credentials (0600)

EXIT CODES:
  0 sucesso   1 erro geral   2 uso incorreto   3 plugin inativo/config ausente
  4 credencial ausente/rejeitada
HELP
}

# _jc_read_raw KEY -> imprime o valor de KEY em $_JC_CONFIG_FILE, ou nada se
# ausente. Retorno: 0 sempre (ausencia de KEY nao e erro desta funcao — o
# chamador decide o exit code). Parse linha a linha, split no PRIMEIRO '=';
# '#'/branco ignorados (mesmo contrato de state-backend.sh P2, adaptado:
# aqui chave desconhecida nao invalida o arquivo inteiro, so nao casa).
_jc_read_raw() {
  _jcrr_key="$1"
  _jcrr_found="no"
  while IFS= read -r _jcrr_line || [ -n "$_jcrr_line" ]; do
    case "$_jcrr_line" in
      ''|'#'*)
        : # linha em branco ou comentario — ignorada
        ;;
      *=*)
        _jcrr_k=${_jcrr_line%%=*}
        _jcrr_v=${_jcrr_line#*=}
        if [ "$_jcrr_k" = "$_jcrr_key" ]; then
          printf '%s\n' "$_jcrr_v"
          _jcrr_found="yes"
        fi
        ;;
      *)
        : # linha sem '=' — ignorada (nao invalida o arquivo, diferente de P2)
        ;;
    esac
  done < "$_JC_CONFIG_FILE"
  [ "$_jcrr_found" = "yes" ]
}

_jc_cmd_get() {
  [ "$#" -ge 1 ] || _jc_die_usage "get requer KEY"
  _jcg_key="$1"
  [ -f "$_JC_CONFIG_FILE" ] || _jc_die "config ausente: $_JC_CONFIG_FILE (plugin inativo)" 3
  if ! _jc_read_raw "$_jcg_key"; then
    _jc_die "chave nao encontrada: $_jcg_key" 1
  fi
  return 0
}

# Campos obrigatorios de ProjectConfig (data-model.md, coluna Obrigatorio
# = "sim"; stage_status.<stage> e opcional, fora desta lista).
_JC_REQUIRED_FIELDS="config_version site_host project_key board_id \
issue_type_epic issue_type_task issue_type_subtask \
status_pending status_in_progress status_pass status_fail sync_autonomous"

# _jc_is_bare_hostname VALUE -> exit 0 se VALUE e um hostname puro (sem
# esquema, path, porta ou userinfo) — charset [A-Za-z0-9.-] apenas, que ja
# exclui ':', '/', '@' e espacos por construcao.
_jc_is_bare_hostname() {
  case "$1" in
    '') return 1 ;;
  esac
  case "$1" in
    *[!A-Za-z0-9.-]*) return 1 ;;
  esac
  return 0
}

_jc_cmd_validate() {
  [ -f "$_JC_CONFIG_FILE" ] || _jc_die "config ausente: $_JC_CONFIG_FILE (plugin inativo)" 3

  for _jcv_field in $_JC_REQUIRED_FIELDS; do
    _jcv_val=$(_jc_read_raw "$_jcv_field" 2>/dev/null) || _jcv_val=""
    if [ -z "$_jcv_val" ]; then
      _jc_die "campo obrigatorio ausente ou vazio: $_jcv_field" 1
    fi
  done

  _jcv_site_host=$(_jc_read_raw site_host)
  if ! _jc_is_bare_hostname "$_jcv_site_host"; then
    _jc_die "site_host invalido (esperado hostname puro, sem esquema/path/porta/userinfo): $_jcv_site_host" 1
  fi

  _jcv_status_pass=$(_jc_read_raw status_pass)
  _jcv_status_fail=$(_jc_read_raw status_fail)
  if [ "$_jcv_status_pass" = "$_jcv_status_fail" ]; then
    _jc_die "status_fail e status_pass sao iguais ('$_jcv_status_pass') — crie um status distinto no workflow do projeto Jira para representar falha" 1
  fi

  return 0
}

_jc_cmd_credential_check() {
  if [ ! -f "$_JC_CRED_FILE" ]; then
    _jc_die "credencial ausente: $_JC_CRED_FILE" 4
  fi
  # GNU (-c) primeiro, fallback BSD (-f) — mesma ordem de cli/lib/recall.sh
  # (BSD stat falha limpo em '-c' e cai no '-f'; a ordem inversa e o gotcha
  # ja documentado no projeto).
  _jccc_mode=$(stat -c '%a' -- "$_JC_CRED_FILE" 2>/dev/null) \
    || _jccc_mode=$(stat -f '%Lp' -- "$_JC_CRED_FILE" 2>/dev/null) \
    || _jccc_mode=""
  if [ -z "$_jccc_mode" ]; then
    _jc_die "nao foi possivel determinar a permissao de $_JC_CRED_FILE" 4
  fi
  if [ "$_jccc_mode" != "600" ]; then
    _jc_die "credencial com permissao insegura (esperado 0600, obtido 0$_jccc_mode): $_JC_CRED_FILE" 4
  fi
  return 0
}

# --- dispatcher ---------------------------------------------------------

_jc_sub="${1:-}"
[ "$#" -ge 1 ] && shift || :

case "$_jc_sub" in
  ''|-h|--help|help)
    _jc_usage
    exit 0
    ;;
  get)
    _jc_cmd_get "$@"
    ;;
  validate)
    _jc_cmd_validate "$@"
    ;;
  credential-check)
    _jc_cmd_credential_check "$@"
    ;;
  *)
    _jc_die_usage "subcomando desconhecido: $_jc_sub (validos: get, validate, credential-check)"
    ;;
esac
