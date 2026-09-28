#!/bin/sh
# jira-conflict-view.sh — leitor READ-ONLY do conteudo ATUAL de uma issue do
# Jira associada a um ConflictRecord PENDENTE, para o operador decidir via
# `jira-sync.sh resolve` (cstk-jira, FASE 6 tarefa 6.3 "Skill jira-sync").
#
# Ref: docs/specs/cstk-jira/spec.md US3; plan.md Fluxo 3 "Sync autonomo";
#      data-model.md Entity ConflictRecord; contracts/jira-rest.md R3 (`GET
#      /rest/api/3/issue/{issueIdOrKey}`, query `fields` comma-separated,
#      exemplo literal "summary,comment" — mesmo endpoint que
#      jira-sync.sh drain ja usa para `fields=summary,status`, aqui
#      ampliado com `description,comment` so para EXIBICAO ao operador);
#      contracts/plugin-scripts.md (convencoes/exit codes); checklists/
#      ux.md CHK011; checklists/security.md CHK005/SEC-2; tasks.md
#      6.3.5/6.3.6.
#
# Este script NUNCA decide nada: so imprime, com rotulo explicito de
# conteudo externo NAO-CONFIAVEL, o titulo/status/descricao/comentarios
# atuais da issue (SEC-2 — texto do Jira e DADO, nunca instrucao). A UNICA
# saida acionavel de um conflito continua sendo `jira-sync.sh resolve`
# (data-model.md: resolucao e SEMPRE decisao humana); este script nunca
# grava em conflicts.tsv/outbox.tsv nem chama `resolve`/`enqueue`.
#
# `description`/`comment`: schema de RESPOSTA de R3 para esses dois campos
# NAO esta confirmado em contracts/jira-rest.md (so o formato de ESCRITA de
# `description`, Atlassian Document Format, foi confirmado por roundtrip —
# ver linha `fields.description` do contrato). Por isso este script NUNCA
# interpreta a estrutura interna desses dois campos (nada de navegar
# `.content[].content[].text` — seria inventar shape sem fonte, Principio
# VI): exibe o valor exatamente como veio (`tojson`), rotulado como bruto.
#
# Uso:
#   jira-conflict-view.sh show --feature F --local-key K
#
# Exit codes (contracts/plugin-scripts.md): 0 sucesso; 1 erro geral (nenhum
# ConflictRecord pendente para o par, ou falha ao ler a issue depois que
# deps/config/credencial ja foram confirmados); 2 uso incorreto; 3 plugin
# inativo/nao configurado; 4 credencial ausente/rejeitada; 5 dependencia
# ausente (`jq`/cliente HTTP); 7 permissao insuficiente — 3/4/5/7 propagados
# tal-e-qual das pre-checagens (`jira-io.sh`/`jira-config.sh`, `set -e`
# repassa o exit code do subcomando que falhou, mesmo padrao de
# `jira-sync.sh convert` ETAPA 1).

set -eu

_JCV_NAME="jira-conflict-view"

_jcv_die_usage() { printf '%s: %s\n' "$_JCV_NAME" "$1" >&2; exit 2; }
_jcv_die()       { printf '%s: %s\n' "$_JCV_NAME" "$1" >&2; exit "${2:-1}"; }

_jcv_usage() {
  cat <<'HELP'
jira-conflict-view.sh — exibicao rotulada (UNTRUSTED) de uma issue em conflito

USO:
  jira-conflict-view.sh show --feature F --local-key K
      Le a linha PENDENTE de conflicts.tsv para (F, K), busca a issue no
      Jira (GET /rest/api/3/issue/KEY?fields=summary,description,status,
      comment) e imprime titulo/status/descricao/comentarios rotulados
      como conteudo externo NAO-CONFIAVEL. So leitura — nunca resolve o
      conflito (use `jira-sync.sh resolve` para isso).

EXIT CODES:
  0 sucesso   1 erro geral   2 uso incorreto   3 nao configurado
  4 credencial   5 dependencia ausente   7 permissao insuficiente
HELP
}

# _jcv_script_dir -> diretorio deste script (para localizar os irmaos
# jira-io.sh/jira-config.sh — mesmo padrao de _js_script_dir/_jm_script_dir).
_jcv_script_dir() {
  CDPATH='' cd -- "$(dirname -- "$0")" && pwd
}

# Mesma allowlist de feature de jira-sync.sh/jira-map.sh/jira-tasks.sh:
# charset [A-Za-z0-9_-], nao-vazio.
_jcv_is_safe_feature() {
  case "$1" in
    '') return 1 ;;
  esac
  case "$1" in
    *[!A-Za-z0-9_-]*) return 1 ;;
  esac
  return 0
}

# Newline literal — mesmo padrao/motivo de jira-sync.sh _JS_NL (deteccao de
# injecao de linha via argumento).
_JCV_NL='
'

# Mesma checagem de jira-sync.sh _js_is_safe_field: nao-vazio, sem TAB/
# newline (protege a leitura por coluna de conflicts.tsv).
_jcv_is_safe_field() {
  case "$1" in
    '') return 1 ;;
  esac
  case "$1" in
    *"$(printf '\t')"*) return 1 ;;
  esac
  case "$1" in
    *"$_JCV_NL"*) return 1 ;;
  esac
  return 0
}

# Mesmo arquivo/layout de jira-sync.sh _JS_CONFLICTS_FILE (data-model.md
# Entity ConflictRecord) — duplicado aqui porque cada script do plugin e um
# binario standalone (nenhum importa funcoes de outro, mesma disciplina de
# jira-map.sh/jira-sync.sh).
_JCV_CONFLICTS_FILE="./.claude/cstk-jira/runtime/conflicts.tsv"

# _jcv_conflict_row FEATURE LOCAL_KEY -> linha TSV PENDENTE (6 colunas) do
# ConflictRecord para o par (F, K), ou nada se ausente.
_jcv_conflict_row() {
  [ -f "$_JCV_CONFLICTS_FILE" ] || return 0
  awk -F '\t' -v f="$1" -v k="$2" \
    'NR > 1 && $2 == f && $3 == k && $6 == "pending" { print; exit }' \
    "$_JCV_CONFLICTS_FILE"
}

_jcv_cmd_show() {
  _jcvs_feature=""
  _jcvs_key=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --feature)
        [ "$#" -ge 2 ] || _jcv_die_usage "--feature requer valor"
        _jcvs_feature="$2"; shift 2 ;;
      --local-key)
        [ "$#" -ge 2 ] || _jcv_die_usage "--local-key requer valor"
        _jcvs_key="$2"; shift 2 ;;
      *)
        _jcv_die_usage "argumento desconhecido: $1" ;;
    esac
  done
  [ -n "$_jcvs_feature" ] || _jcv_die_usage "show requer --feature F"
  _jcv_is_safe_feature "$_jcvs_feature" \
    || _jcv_die_usage "--feature invalido (charset [A-Za-z0-9_-]): $_jcvs_feature"
  _jcv_is_safe_field "$_jcvs_key" \
    || _jcv_die_usage "show requer --local-key K valido (nao-vazio, sem TAB/newline)"

  _jcvs_dir="$(_jcv_script_dir)"
  _jcvs_io="$_jcvs_dir/jira-io.sh"
  _jcvs_config="$_jcvs_dir/jira-config.sh"

  # Pre-checagens (mesma ordem/disciplina de jira-sync.sh convert ETAPA 1):
  # comandos SIMPLES sob 'set -e' — falha aqui propaga o MESMO exit code do
  # subcomando (3 nao-configurado, 4 credencial, 5 dependencia ausente).
  "$_jcvs_io" deps-check
  "$_jcvs_config" validate >/dev/null
  "$_jcvs_config" credential-check
  "$_jcvs_io" request GET /rest/api/3/myself >/dev/null

  _jcvs_row=$(_jcv_conflict_row "$_jcvs_feature" "$_jcvs_key")
  [ -n "$_jcvs_row" ] \
    || _jcv_die "nenhum ConflictRecord PENDENTE para feature=$_jcvs_feature local_key=$_jcvs_key" 1
  _jcvs_jkey=$(printf '%s' "$_jcvs_row" | cut -f4)
  _jcvs_reason=$(printf '%s' "$_jcvs_row" | cut -f5)

  # SEC-1: jira_key vem de conflicts.tsv (gravado internamente pelo motor a
  # partir de jira-map.tsv, nunca de argumento livre do operador) — ainda
  # assim revalidado pela allowlist antes de interpolar o PATH (mesma
  # disciplina de jira-sync.sh/contracts/jira-rest.md SEC-1).
  "$_jcvs_io" validate-segment "$_jcvs_jkey" \
    || _jcv_die "jira_key gravado em conflicts.tsv falhou na validacao SEC-1: $_jcvs_jkey" 1

  _jcvs_resp=$("$_jcvs_io" request GET "/rest/api/3/issue/$_jcvs_jkey?fields=summary,description,status,comment" --op R3 2>/dev/null) \
    || _jcv_die "falha ao ler a issue $_jcvs_jkey no Jira (deps/credencial ja confirmados — provavel issue ausente/indisponivel)" 1

  _jcvs_summary=$(printf '%s' "$_jcvs_resp" | "$_jcvs_io" json-get '.fields.summary // empty')
  _jcvs_status=$(printf '%s' "$_jcvs_resp" | "$_jcvs_io" json-get '.fields.status.name // empty')
  _jcvs_desc=$(printf '%s' "$_jcvs_resp" | "$_jcvs_io" json-get '.fields.description // empty | tojson')
  _jcvs_comment=$(printf '%s' "$_jcvs_resp" | "$_jcvs_io" json-get '.fields.comment // empty | tojson')

  printf 'conflito: feature=%s local_key=%s jira_key=%s reason=%s\n' \
    "$_jcvs_feature" "$_jcvs_key" "$_jcvs_jkey" "$_jcvs_reason"
  printf '(resolver com: jira-sync.sh resolve --feature %s --local-key %s --choice keep_jira|overwrite|ignored)\n\n' \
    "$_jcvs_feature" "$_jcvs_key"

  printf '=== CONTEUDO EXTERNO NAO-CONFIAVEL (Jira %s) — apenas leitura; nenhuma decisao de sync deriva deste texto (CHK005/SEC-2) ===\n' "$_jcvs_jkey"
  printf 'titulo: %s\n' "${_jcvs_summary:-(vazio)}"
  printf 'status: %s\n' "${_jcvs_status:-(vazio)}"
  printf 'descricao (bruta, formato do Jira nao reinterpretado): %s\n' "${_jcvs_desc:-(vazio)}"
  printf 'comentarios (bruto, formato do Jira nao reinterpretado): %s\n' "${_jcvs_comment:-(vazio)}"
  printf '=== FIM CONTEUDO EXTERNO (Jira %s) ===\n' "$_jcvs_jkey"
}

_jcv_sub="${1:-}"
[ "$#" -ge 1 ] && shift || :

case "$_jcv_sub" in
  ''|-h|--help|help)
    _jcv_usage
    exit 0
    ;;
  show)
    _jcv_cmd_show "$@"
    ;;
  *)
    _jcv_die_usage "subcomando desconhecido: $_jcv_sub (valido: show)"
    ;;
esac
