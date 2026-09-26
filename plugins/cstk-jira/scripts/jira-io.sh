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
# ESCOPO ATE AGORA (3.1 `deps-check`+`request` com host unico/SEC-5, 3.2
# allowlist de charset em PATH/SEC-1, e 3.3 credencial temporaria segura/
# SEC-4). NAO implementado aqui (fica para as proximas tarefas da FASE 3,
# cada uma com seus proprios testes):
#   - 3.4 classificacao fina de status HTTP (auth_failed/deferred/retry) —
#     esta versao so distingue "requisicao OK, corpo em stdout" (qualquer
#     status exceto 3xx) de erro mecanico (3xx, DELETE, host/METHOD/PATH
#     invalidos, dependencia ausente, credencial ausente/incompleta);
#   - 3.5 `json-get`/`json-build` (SEC-3) — subcomandos ainda nao existem
#     neste dispatcher. A JQL de FASE 7 (SEC-3) MUST reusar `validate-segment`
#     (abaixo) para cada valor interpolado — nenhum texto livre entra em JQL.
#
# SEC-4 (tarefa 3.3): `request` agora envia autenticacao Basic (email + API
# token — data-model.md Entity Credential, `contracts/jira-rest.md` linha 5)
# via arquivo de config temporario do cliente HTTP (`-K`, diretiva `user =
# "email:token"`, que o cliente HTTP converte no header `Authorization`
# internamente — a credencial em si NUNCA aparece em argv). Arquivo + o
# diretorio privado que o contem sao criados com `umask 077` (elimina a
# janela de corrida entre "criar" e "restringir permissao", CWE-377) e
# removidos por `trap` em EXIT/INT/TERM — mesmo padrao "trap split" de
# `cli/lib/00c-bootstrap.sh` `_00c_release_lock` (EXIT roda a limpeza; INT/
# TERM chamam `exit` explicito, que entao dispara o EXIT trap em sequencia;
# sem o `exit` explicito, POSIX nao garante que o processo de fato termine
# so por ter um trap instalado no sinal). A credencial em si vem do arquivo
# global `${XDG_CONFIG_HOME:-$HOME/.config}/cstk-jira/credentials` (mesmo
# path de `jira-config.sh` `_JC_CRED_FILE`; existencia/permissao 0600
# conferidas via `jira-config.sh credential-check` ANTES de ler o conteudo).
#
# Subcomandos (contrato final documentado em plugin-scripts.md; os tres
# abaixo existem nesta tarefa):
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
#         SEC-1: PATH e recusado (exit 2, SEM requisicao) se contiver `..`,
#         `//`, `\`, `@`, `#`, espaco, CR/LF ou qualquer outro byte de
#         controle, em qualquer posicao — esta e a checagem que cobre TODOS
#         os pontos de interpolacao do motor R1-R11 (contracts/jira-rest.md),
#         porque `request` e o UNICO ponto por onde qualquer chamada R1-R11
#         de fato dispara: bastando o motor futuro (jira-sync.sh/jira-map.sh,
#         FASE 4+) montar o PATH com os segmentos ja validados por
#         `validate-segment` (abaixo), esta guarda central cobre o resto.
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
#         SEC-4: ANTES de disparar a requisicao, confere `jira-config.sh
#         credential-check` (existencia + modo 0600) e le `email`/
#         `api_token` do arquivo de Credential; grava um arquivo de config
#         temporario do cliente HTTP (`umask 077`, diretorio privado,
#         removido por `trap` em EXIT/INT/TERM) com a diretiva `user =
#         "email:token"` e o passa via `-K` — a credencial NUNCA aparece em
#         argv/linha de comando do cliente HTTP nem em log.
#         Corpo da resposta em stdout; `http_status=<codigo>` na 1a linha
#         de stderr.
#
#   jira-io.sh validate-segment VALUE [VALUE...]
#       — SEC-1: valida cada VALUE contra a allowlist FECHADA de charset
#         `[A-Za-z0-9_-]` (nao-vazio, sem excecao). Uso pretendido: o motor
#         (jira-sync.sh/jira-map.sh, FASE 4+) chama isto para `jira_id`,
#         `jira_key` e `project_key` ANTES de interpolar qualquer PATH ou
#         JQL — nunca depois. Nao exige `jq`/cliente HTTP (deps-check nao e
#         chamado aqui): validacao de string pura, POSIX `case`. Exit 0 se
#         TODOS os VALUE casarem; exit 2 (uso incorreto) no primeiro que
#         falhar, sem revelar o valor bruto em stderr (pode conter bytes de
#         controle).
#
# Exit codes (mesma convencao de jira-config.sh):
#   0 sucesso
#   1 erro geral / falha de requisicao (rede, 3xx recusado, etc.)
#   2 uso incorreto (METHOD fora da allowlist, PATH sem `/rest/`, PATH/
#     segmento fora da allowlist SEC-1, args)
#   3 ProjectConfig ausente/inacessivel (propagado de jira-config.sh get)
#   4 credencial ausente/permissao insegura (propagado de jira-config.sh
#     credential-check) ou incompleta (falta `email`/`api_token` no arquivo)
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
      (DELETE nunca existe como opcao valida). PATH deve comecar com /rest/
      e nao pode conter .. // \ @ # espaco CR/LF/controle (SEC-1).
      Autenticacao Basic (email + API token de Credential) enviada via
      arquivo de config temporario do cliente HTTP (SEC-4) — nunca em argv.

  jira-io.sh validate-segment VALUE [VALUE...]
      Valida cada VALUE contra a allowlist [A-Za-z0-9_-] (SEC-1), a usar
      pelo motor ANTES de interpolar jira_id/jira_key/project_key em
      PATH ou JQL.

EXIT CODES:
  0 sucesso   1 erro geral/requisicao   2 uso incorreto
  3 ProjectConfig ausente   4 credencial ausente/incompleta
  5 dependencia ausente
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

# --- Credential (SEC-4, tarefa 3.3) -------------------------------------
#
# Path identico a `_JC_CRED_FILE` de jira-config.sh (data-model.md Entity
# Credential: arquivo GLOBAL unico por maquina, fora do repo). jira-io.sh
# NAO duplica a checagem de existencia/permissao (delega a `jira-config.sh
# credential-check`, que ja e a dona dessa validacao) — so LE o conteudo
# (email/api_token) apos essa checagem passar.
_JI_CRED_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/cstk-jira/credentials"

# _ji_cred_check — delega a jira-config.sh credential-check (existencia +
# modo 0600 exato do arquivo de Credential). Nunca imprime conteudo.
_ji_cred_check() {
  "$(_ji_script_dir)/jira-config.sh" credential-check
}

# _ji_cred_read KEY — imprime o valor de KEY (`email`|`api_token`) em
# $_JI_CRED_FILE; exit 1 se a chave nao existir. Mesmo parse de
# `_jc_read_raw` em jira-config.sh (linha a linha, split no PRIMEIRO '=',
# '#'/branco ignorados) — deliberadamente NAO extraido para um helper
# compartilhado (cada script mantem sua propria copia minima, sem
# acoplamento entre os dois arquivos alem do path do arquivo e do
# subcomando `credential-check`).
_ji_cred_read() {
  _jicr_key="$1"
  _jicr_found="no"
  while IFS= read -r _jicr_line || [ -n "$_jicr_line" ]; do
    case "$_jicr_line" in
      ''|'#'*)
        : # linha em branco ou comentario — ignorada
        ;;
      *=*)
        _jicr_k=${_jicr_line%%=*}
        _jicr_v=${_jicr_line#*=}
        if [ "$_jicr_k" = "$_jicr_key" ]; then
          printf '%s\n' "$_jicr_v"
          _jicr_found="yes"
        fi
        ;;
    esac
  done < "$_JI_CRED_FILE"
  [ "$_jicr_found" = "yes" ]
}

# _ji_curlrc_escape VALUE — escapa `\` e `"` para uso dentro de um valor
# entre aspas duplas na diretiva `user = "..."` de um arquivo `-K` do
# cliente HTTP (sintaxe de config: valores entre aspas suportam escape de
# `\`/`"` — defesa contra api_token/email com esses bytes, ainda que raro).
_ji_curlrc_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# _ji_cred_cleanup — acao do trap EXIT de `request`: remove o arquivo de
# config temporario de credencial + o arquivo de resposta, depois o
# diretorio privado (so remove se ja estiver vazio — `rmdir` com `|| :`
# porque, sob `set -eu`, uma falha de `rmdir` sendo o ULTIMO comando de um
# `&&`/`if` NAO e isenta de errexit). Variaveis podem estar vazias (sinal
# chegou antes de qualquer recurso existir) — `rm -f`/o guard `[ -n ... ]`
# cobrem esse caso sem diagnostico de erro.
_ji_cred_cleanup() {
  rm -f -- "$_jir_cred_file" "$_jir_tmp_out" 2>/dev/null
  if [ -n "$_jir_cred_dir" ]; then
    rmdir -- "$_jir_cred_dir" 2>/dev/null || :
  fi
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

# _ji_charset_ok VALUE — SEC-1: allowlist FECHADA [A-Za-z0-9_-], nao-vazio.
# POSIX puro (case + bracket expression), sem dependencia externa. Usado
# tanto por `validate-segment` quanto (potencialmente) por chamadores
# futuros que queiram validar um valor isolado antes de montar PATH/JQL.
_ji_charset_ok() {
  [ -n "$1" ] || return 1
  case "$1" in
    *[!A-Za-z0-9_-]*) return 1 ;;
  esac
  return 0
}

# _ji_path_has_forbidden_bytes PATH — SEC-1: verdadeiro (exit 0) se PATH
# contiver qualquer um dos padroes/bytes proibidos: `..`, `//`, `\`, `@`,
# `#`, espaco, ou qualquer byte de controle (inclui CR/LF). Aplicado ao
# PATH inteiro recebido por `request` — como `request` e o UNICO ponto de
# disparo de requisicao (deps-check nao conta), esta e a guarda central que
# cobre todos os pontos de interpolacao do motor (R1-R11), independente de
# onde/como o PATH foi montado antes de chegar aqui.
_ji_path_has_forbidden_bytes() {
  case "$1" in
    *..*|*//*|*"\\"*|*@*|*"#"*|*" "*) return 0 ;;
  esac
  # LF: printf '%s' sem terminador; wc -l so conta se ha \n EMBUTIDO no meio
  # do valor (nao um trailing newline artificial, que nao existe aqui).
  _jipfb_lines=$(printf '%s' "$1" | wc -l | tr -d ' ')
  [ "$_jipfb_lines" -gt 0 ] && return 0
  # CR e qualquer outro byte de controle (grep opera por linha; LF ja foi
  # coberto acima porque grep nunca veria o \n como dado de uma linha).
  if printf '%s' "$1" | LC_ALL=C grep -q '[[:cntrl:]]'; then
    return 0
  fi
  return 1
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

  # SEC-1 (tarefa 3.2): recusa PATH com byte/sequencia proibida SEM disparar
  # requisicao. Valor bruto NAO e ecoado (pode conter CR/LF/controle).
  if _ji_path_has_forbidden_bytes "$_jir_path"; then
    _ji_die_usage "PATH contem byte/sequencia proibida (.. // \\ @ # espaco CR/LF/controle) — recusado sem requisicao (SEC-1)"
  fi

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

  # SEC-4 (tarefa 3.3): declarar os recursos temporarios ANTES de instalar
  # o trap unico — cobre EXIT/INT/TERM mesmo que um sinal chegue antes de
  # qualquer recurso existir. Trap "split" (mesmo padrao de
  # cli/lib/00c-bootstrap.sh `_00c_release_lock`): EXIT roda a limpeza;
  # INT/TERM chamam `exit` explicito, que entao dispara o EXIT trap em
  # sequencia — sem o `exit` explicito, um sinal fatal por convencao (INT/
  # TERM) NAO teria garantia de terminar so por ter a acao instalada.
  _jir_cred_dir=""
  _jir_cred_file=""
  _jir_tmp_out=""
  trap '_ji_cred_cleanup' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  _ji_cred_check \
    || _ji_die "credencial rejeitada (ausente ou permissao insegura) — rode 'jira-config.sh credential-check' para diagnostico" 4

  _jir_email=$(_ji_cred_read email) \
    || _ji_die "credencial incompleta: campo 'email' ausente em $_JI_CRED_FILE" 4
  _jir_api_token=$(_ji_cred_read api_token) \
    || _ji_die "credencial incompleta: campo 'api_token' ausente em $_JI_CRED_FILE" 4
  [ -n "$_jir_email" ] \
    || _ji_die "credencial incompleta: campo 'email' vazio em $_JI_CRED_FILE" 4
  [ -n "$_jir_api_token" ] \
    || _ji_die "credencial incompleta: campo 'api_token' vazio em $_JI_CRED_FILE" 4

  # `umask 077` ANTES de criar diretorio E arquivo — elimina a janela de
  # corrida entre "criar" e "restringir permissao" (CWE-377/SEC-4).
  # `mktemp -d` ja cria com 0700 nos dois lados (GNU/BSD); o umask garante
  # o mesmo para o ARQUIVO criado logo abaixo por redirecionamento simples.
  _jir_orig_umask=$(umask)
  umask 077
  _jir_cred_dir=$(mktemp -d "${TMPDIR:-/tmp}/jira-io-cred.XXXXXX") \
    || _ji_die "falha ao criar diretorio temporario de credencial" 1
  _jir_cred_file="$_jir_cred_dir/curlrc"
  _jir_email_esc=$(_ji_curlrc_escape "$_jir_email")
  _jir_token_esc=$(_ji_curlrc_escape "$_jir_api_token")
  printf 'user = "%s:%s"\n' "$_jir_email_esc" "$_jir_token_esc" > "$_jir_cred_file"
  umask "$_jir_orig_umask"

  _jir_tmp_out=$(mktemp "${TMPDIR:-/tmp}/jira-io.XXXXXX") \
    || _ji_die "falha ao criar arquivo temporario de resposta" 1

  # Sem `-L` (SEC-5: nunca seguir redirect) e sem `-k`/`--insecure` (TLS
  # sempre verificado — nao ha flag neste script para desativar). Um unico
  # disparo por chamada: nao ha caminhada de `Location` (diferente de
  # cli/lib/http.sh), porque este script so fala com `site_host`. `-K`
  # carrega a credencial (SEC-4) — NUNCA aparece como argv literal.
  _jir_ec=0
  if [ -n "$_jir_body_file" ]; then
    _jir_status=$(curl -sS --connect-timeout 10 --max-time 60 \
      -K "$_jir_cred_file" \
      -X "$_jir_method" \
      -H 'Accept: application/json' -H 'Content-Type: application/json' \
      --data-binary "@${_jir_body_file}" \
      -o "$_jir_tmp_out" -w '%{http_code}' \
      -- "$_jir_url") || _jir_ec=$?
  else
    _jir_status=$(curl -sS --connect-timeout 10 --max-time 60 \
      -K "$_jir_cred_file" \
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

# _ji_cmd_validate_segment VALUE [VALUE...] — SEC-1: valida cada VALUE
# contra a allowlist FECHADA [A-Za-z0-9_-]. Nao exige jq/cliente HTTP (nao
# chama _ji_cmd_deps_check). Uso pretendido: o motor (jira-sync.sh/
# jira-map.sh) chama isto para jira_id/jira_key/project_key ANTES de montar
# PATH ou JQL — a mesma allowlist que `request` reforca no PATH inteiro.
_ji_cmd_validate_segment() {
  [ "$#" -ge 1 ] || _ji_die_usage "validate-segment requer ao menos 1 VALUE"
  for _jivs_val in "$@"; do
    _ji_charset_ok "$_jivs_val" \
      || _ji_die_usage "segmento fora da allowlist [A-Za-z0-9_-] (SEC-1) — jira_id/jira_key/project_key devem casar esse charset antes de qualquer interpolacao em PATH ou JQL"
  done
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
  validate-segment)
    _ji_cmd_validate_segment "$@"
    ;;
  request)
    _ji_cmd_request "$@"
    ;;
  *)
    _ji_die_usage "subcomando desconhecido: $_ji_sub (validos: deps-check, request, validate-segment)"
    ;;
esac
