#!/bin/sh
# jira-io.sh — UNICO arquivo do plugin cstk-jira que referencia `jq` e o
# cliente HTTP de linha de comando (o mesmo binario de `cli/lib/http.sh`),
# sob o carve-out 1.1.0 do Principio II (POSIX sh, zero dependencia) —
# consentido pelo operador em block-002 (plan.md Runtime B1 / dec-021).
#
# Ref: docs/specs/cstk-jira/plan.md SEC-1..SEC-5;
#      docs/specs/cstk-jira/contracts/plugin-scripts.md `jira-io.sh`;
#      docs/specs/cstk-jira/contracts/jira-rest.md (autenticacao Basic);
#      docs/specs/cstk-jira/data-model.md Entity ProjectConfig/Credential;
#      tasks.md FASE 3 tarefa 3.1.
#
# ESCOPO DESTA TAREFA (3.1 — `deps-check` + `request` com host unico e
# SEC-5): so a mecanica de transporte HTTPS. NAO implementado aqui (fica
# para as proximas tarefas da FASE 3, cada uma com seus proprios testes):
#   - 3.2 allowlist de charset em PATH/JQL (SEC-1) — `request` ainda so
#     confere o prefixo `/rest/`, nao o charset dos segmentos interpolados;
#   - 3.3 credencial (SEC-4) — esta versao de `request` NAO envia header
#     `Authorization` nenhum (o cliente HTTP roda sem config de credencial);
#   - 3.4 classificacao fina de status HTTP (auth_failed/deferred/retry) —
#     esta versao so distingue "requisicao OK, corpo em stdout" (qualquer
#     status exceto 3xx) de erro mecanico (3xx, DELETE, host/METHOD/PATH
#     invalidos, dependencia ausente);
#   - 3.5 `json-get`/`json-build` (SEC-3) — subcomandos ainda nao existem
#     neste dispatcher.
#
# Subcomandos (contrato final documentado em plugin-scripts.md; apenas os
# dois abaixo existem nesta tarefa):
#
#   jira-io.sh deps-check
#       — Confere `jq` e o cliente HTTP no PATH. Exit 5 + instrucao de
#         instalacao se faltar qualquer um dos dois (carve-out 1.1.0
#         condicao a).
#
#   jira-io.sh request METHOD PATH [--body-file F]
#       — METHOD restrito a allowlist FECHADA `GET`/`POST`/`PUT` — `DELETE`
#         nunca existe como opcao valida (FR-012); qualquer METHOD fora da
#         allowlist e uso incorreto (exit 2), nao erro de requisicao.
#         PATH MUST comecar com `/rest/`.
#         Monta `https://<site_host><PATH>` com `site_host` lido de
#         `jira-config.sh get site_host` (ProjectConfig); valida por
#         IGUALDADE EXATA (sem userinfo, sem porta) o host que sera de fato
#         requisitado contra `site_host` ANTES de disparar a requisicao
#         (defesa auditavel — a URL e sempre construida aqui, nunca
#         reparseada de uma resposta).
#         SEC-5: o cliente HTTP roda SEM seguir redirect (nenhuma flag de
#         "seguir localizacao" e usada) e COM verificacao TLS sempre ativa
#         (nao existe flag neste script para desliga-la). Resposta `3xx`
#         => erro imediato, SEM disparar segunda requisicao — nao ha
#         caminhada manual de `Location` como em `cli/lib/http.sh`, porque
#         `jira-io.sh` so fala com UM host (`site_host`) por design.
#         Corpo da resposta em stdout; `http_status=<codigo>` na 1a linha
#         de stderr.
#
# Exit codes (mesma convencao de jira-config.sh):
#   0 sucesso
#   1 erro geral / falha de requisicao (rede, 3xx recusado, etc.)
#   2 uso incorreto (METHOD fora da allowlist, PATH sem `/rest/`, args)
#   3 ProjectConfig ausente/inacessivel (propagado de jira-config.sh get)
#   5 dependencia ausente (`jq` ou cliente HTTP fora do PATH)
#
# Convencoes (Principio II / contracts/plugin-scripts.md):
#   `#!/bin/sh`, `set -eu`, sem bash-isms; dados em stdout, diagnostico em
#   stderr. Credencial NUNCA por argv (aplicavel a partir da tarefa 3.3).

set -eu

_JI_NAME="jira-io"

_ji_die_usage() { printf '%s: %s\n' "$_JI_NAME" "$1" >&2; exit 2; }
_ji_die()       { printf '%s: %s\n' "$_JI_NAME" "$1" >&2; exit "${2:-1}"; }

_ji_usage() {
  cat <<'HELP'
jira-io.sh — cliente REST do plugin cstk-jira (unico arquivo com jq + cliente HTTP)

USO:
  jira-io.sh deps-check
      Confere jq + cliente HTTP no PATH.

  jira-io.sh request METHOD PATH [--body-file F]
      Requisicao HTTPS contra <site_host><PATH>. METHOD em GET/POST/PUT
      (DELETE nunca existe como opcao valida). PATH deve comecar com /rest/.

EXIT CODES:
  0 sucesso   1 erro geral/requisicao   2 uso incorreto
  3 ProjectConfig ausente   5 dependencia ausente
HELP
}

# Resolve o diretorio deste script SO quando necessario (nao no topo do
# arquivo) — deps-check nao deve exigir `dirname`/`cd` alem do que o
# proprio interprete `sh` ja oferece como builtin, mantendo o cenario de
# "PATH minimo sem jq/curl" (task 3.1.5) livre de acoplamento acidental.
_ji_script_dir() {
  CDPATH='' cd -- "$(dirname -- "$0")" && pwd
}

# _ji_config_get KEY — delega a jira-config.sh (mesmo diretorio deste
# script); jira-io.sh NUNCA duplica a leitura/validacao de ProjectConfig.
_ji_config_get() {
  "$(_ji_script_dir)/jira-config.sh" get "$1"
}

_ji_cmd_deps_check() {
  _jidc_missing=""
  command -v jq   >/dev/null 2>&1 || _jidc_missing="$_jidc_missing jq"
  command -v curl >/dev/null 2>&1 || _jidc_missing="$_jidc_missing curl"
  if [ -n "$_jidc_missing" ]; then
    _ji_die "dependencia(s) ausente(s) no PATH:$_jidc_missing — instale (ex.: 'brew install jq curl' no macOS, 'apt-get install jq curl' em distros Debian/Ubuntu) e reexecute" 5
  fi
  return 0
}

# _ji_method_allowed METHOD — allowlist FECHADA (FR-012): DELETE nunca
# existe como opcao valida, mesmo digitado corretamente.
_ji_method_allowed() {
  case "$1" in
    GET|POST|PUT) return 0 ;;
    *) return 1 ;;
  esac
}

_ji_cmd_request() {
  _ji_cmd_deps_check

  [ "$#" -ge 2 ] || _ji_die_usage "request requer METHOD e PATH"
  _jir_method="$1"
  _jir_path="$2"
  shift 2

  _jir_body_file=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --body-file)
        [ "$#" -ge 2 ] || _ji_die_usage "--body-file requer argumento"
        _jir_body_file="$2"
        shift 2
        ;;
      *)
        _ji_die_usage "argumento desconhecido: $1"
        ;;
    esac
  done

  _ji_method_allowed "$_jir_method" || _ji_die_usage \
    "METHOD invalido: $_jir_method (permitido: GET, POST, PUT — DELETE nunca existe como opcao valida, FR-012)"

  case "$_jir_path" in
    /rest/*) : ;;
    *) _ji_die_usage "PATH deve comecar com /rest/: $_jir_path" ;;
  esac

  if [ -n "$_jir_body_file" ] && [ ! -r "$_jir_body_file" ]; then
    _ji_die_usage "--body-file nao legivel: $_jir_body_file"
  fi

  _jir_site_host=$(_ji_config_get site_host) \
    || _ji_die "nao foi possivel obter site_host de ProjectConfig" 3
  [ -n "$_jir_site_host" ] || _ji_die "site_host vazio em ProjectConfig" 3

  _jir_url="https://${_jir_site_host}${_jir_path}"

  # SEC-5 / defesa-em-profundidade (asserção auditavel, FR-015): o host
  # efetivamente presente na URL montada MUST ser byte-a-byte igual a
  # site_host — a URL e sempre construida aqui a partir do literal de
  # ProjectConfig, nunca reparseada de uma resposta ou de outra fonte;
  # esta checagem existe para que uma futura mudanca acidental na
  # montagem da URL (ex.: reintroduzir `-L`/seguir Location) seja pega
  # por este teste antes de qualquer requisicao real.
  _jir_after_scheme=${_jir_url#https://}
  _jir_url_host=${_jir_after_scheme%%/*}
  if [ "$_jir_url_host" != "$_jir_site_host" ]; then
    _ji_die "host divergente detectado antes da requisicao (esperado '$_jir_site_host', obtido '$_jir_url_host') — abortado sem requisicao" 1
  fi

  _jir_tmp_out=$(mktemp "${TMPDIR:-/tmp}/jira-io.XXXXXX") \
    || _ji_die "falha ao criar arquivo temporario de resposta" 1
  trap 'rm -f -- "$_jir_tmp_out"' EXIT INT TERM

  # Sem `-L` (SEC-5: nunca seguir redirect) e sem `-k`/`--insecure` (TLS
  # sempre verificado — nao ha flag neste script para desativar). Um unico
  # disparo por chamada: nao ha caminhada de `Location` (diferente de
  # cli/lib/http.sh), porque este script so fala com `site_host`.
  _jir_ec=0
  if [ -n "$_jir_body_file" ]; then
    _jir_status=$(curl -sS --connect-timeout 10 --max-time 60 \
      -X "$_jir_method" \
      -H 'Accept: application/json' -H 'Content-Type: application/json' \
      --data-binary "@${_jir_body_file}" \
      -o "$_jir_tmp_out" -w '%{http_code}' \
      -- "$_jir_url") || _jir_ec=$?
  else
    _jir_status=$(curl -sS --connect-timeout 10 --max-time 60 \
      -X "$_jir_method" \
      -H 'Accept: application/json' \
      -o "$_jir_tmp_out" -w '%{http_code}' \
      -- "$_jir_url") || _jir_ec=$?
  fi

  if [ "$_jir_ec" -ne 0 ]; then
    _ji_die "requisicao falhou (cliente HTTP exit $_jir_ec): $_jir_method $_jir_path" 1
  fi

  case "$_jir_status" in
    3??)
      _ji_die "resposta $_jir_status (redirecionamento) recusada SEM nova requisicao — SEC-5 nunca segue Location: $_jir_method $_jir_path" 1
      ;;
  esac

  printf 'http_status=%s\n' "$_jir_status" >&2
  cat -- "$_jir_tmp_out"
  return 0
}

# --- dispatcher ---------------------------------------------------------

_ji_sub="${1:-}"
[ "$#" -ge 1 ] && shift || :

case "$_ji_sub" in
  ''|-h|--help|help)
    _ji_usage
    exit 0
    ;;
  deps-check)
    _ji_cmd_deps_check "$@"
    ;;
  request)
    _ji_cmd_request "$@"
    ;;
  *)
    _ji_die_usage "subcomando desconhecido: $_ji_sub (validos: deps-check, request)"
    ;;
esac
