#!/bin/sh
# jira-setup.sh — logica deterministica de apoio a skill interativa
# `jira-setup` (feature cstk-jira, FASE 6 tarefa 6.1).
#
# Ref: docs/specs/cstk-jira/data-model.md Entity ProjectConfig; docs/specs/
#      cstk-jira/checklists/ux.md CHK004/CHK006; docs/specs/cstk-jira/
#      checklists/api.md CHK006; docs/specs/cstk-jira/contracts/jira-rest.md
#      R5/R8; plugins/cstk-jira/skills/jira-setup/SKILL.md.
#
# A skill (LLM) conduz a entrevista e chama `jira-io.sh request`/`json-get`
# para descobrir tipos de issue (R8) e transicoes (R5). Este script cobre
# APENAS a parte deterministica que precisa de teste automatizado (POSIX
# sh puro, sem `jq`):
#
#   jira-setup.sh check-status-mapping PENDING IN_PROGRESS PASS FAIL \
#                                       STATUS [STATUS...]
#       — PENDING/IN_PROGRESS/PASS/FAIL sao os nomes de status escolhidos
#         pelo operador para o mapeamento local `pending`/`in_progress`/
#         `pass`/`fail`; STATUS... e a lista de status REALMENTE descoberta
#         no workflow do projeto (extraida pela skill de
#         `GET .../transitions` R5, campo `transitions[].to.name`).
#         Regras (data-model.md Entity ProjectConfig "Validation rules"):
#           1. FAIL MUST ser diferente de PASS.
#           2. Os 4 valores MUST estar entre os status descobertos (nunca
#              digitados de memoria pelo agente/operador).
#         Falha de qualquer regra => diagnostico em stderr LISTANDO os
#         status disponiveis descobertos no mesmo fluxo (ux CHK004) e
#         exit 1. Sucesso => exit 0, sem stdout.
#
#   jira-setup.sh check-link-type ID CANDIDATE_ID...
#       — r02 FASE 18 tarefa 18.1.1 (contracts/plugin-scripts.md
#         `jira-setup.sh check-link-type`; research.md Decision R2-6;
#         spec.md FR-025 Clarification): ID e o `link_type_id` que o
#         operador confirmou; CANDIDATE_ID... e a lista de ids REALMENTE
#         devolvida por `GET /rest/api/3/issueLinkType` (R16) NESTA MESMA
#         execucao (SEC-13) — a skill descobre via `jira-io.sh
#         request GET`, este script so valida a MEMBERSHIP (mesmo
#         idioma de `check-status-mapping`/R5: a network fica na skill,
#         o script e puro/deterministico). ID fora da lista => exit 1
#         com a lista de candidatos no diagnostico; nunca aceita um id
#         digitado de memoria.
#
#   jira-setup.sh resolve-link-type
#       — r02 FASE 18 tarefa 18.2.1/18.2.2 (research.md Decision R2-6;
#         spec.md FR-025 Clarification): usado quando `link_type_id` esta
#         VAZIO em ProjectConfig (operador nao confirmou nenhum na ETAPA 7
#         do setup). Le de stdin, uma linha TAB-separada por tipo REALMENTE
#         devolvido por R16 NESTA MESMA execucao (SEC-13, mesmo idioma de
#         check-link-type): `ID<TAB>INWARD<TAB>OUTWARD`. Compara
#         (case-insensitive) `INWARD` e `OUTWARD` contra a raiz fixa
#         "block" (nunca vocabulario arbitrario); candidato = linha cujas
#         DUAS frases contem a raiz. Exatamente 1 candidato -> imprime o
#         `ID` em stdout, exit 0. 0 candidatos -> exit 1, diagnostico
#         "unrepresentable reason=no_link_type". 2+ candidatos (ambiguidade)
#         -> exit 1, diagnostico "unrepresentable reason=ambiguous_link_type"
#         (NUNCA escolhe arbitrariamente o primeiro). Puro/deterministico —
#         nenhuma chamada de rede aqui (a leitura de R16 fica na skill/no
#         motor de sync, mesma divisao de responsabilidade de
#         check-link-type).
#
#   jira-setup.sh write-config KEY=VALUE [KEY=VALUE...]
#       — Grava `ProjectConfig` (mesmo arquivo/formato de `jira-config.sh`,
#         `${CSTK_JIRA_CONFIG:-./.claude/cstk-jira/config}`) de forma
#         ATOMICA: monta um arquivo temporario com todos os pares
#         informados, valida com `jira-config.sh validate` (delega, nunca
#         duplica as regras) e SO ENTAO move (`mv`, mesma particao) para o
#         caminho final. Se a validacao falhar, o arquivo temporario e
#         removido e o caminho final NUNCA e tocado — nenhum config parcial
#         ou invalido chega a existir como arquivo "final" (ux CHK006/FR-007,
#         tasks.md 6.1.5). Apos gravar com sucesso, devolve (best-effort)
#         eventos `auth_failed` do outbox a `queued` via
#         `jira-sync.sh requeue-auth-failed` (FR-016 / data-model.md
#         OutboxEvent auth_failed->queued, tasks.md 12.6.1).
#
# Convencoes (Principio II / mesmas de jira-config.sh):
#   `#!/bin/sh`, `set -eu`, sem bash-isms; dados em stdout, diagnostico em
#   stderr. Exit codes: 0 sucesso; 1 erro geral (mapeamento/config invalido);
#   2 uso incorreto.
#
# Nenhuma credencial passa por este script (Credential e tratada so por
# jira-config.sh credential-check + jira-io.sh request, nunca aqui).

set -eu

_JS_NAME="jira-setup"

_js_die_usage() { printf '%s: %s\n' "$_JS_NAME" "$1" >&2; exit 2; }
_js_die()       { printf '%s: %s\n' "$_JS_NAME" "$1" >&2; exit "${2:-1}"; }

_js_usage() {
  cat <<'HELP'
jira-setup.sh — apoio deterministico a skill interativa jira-setup

USO:
  jira-setup.sh check-status-mapping PENDING IN_PROGRESS PASS FAIL STATUS...
      Valida o mapeamento local -> status Jira contra a lista de status
      REALMENTE descoberta (R5). Rejeita FAIL == PASS e qualquer valor fora
      da lista descoberta, listando os status disponiveis no diagnostico.

  jira-setup.sh check-link-type ID CANDIDATE_ID...
      Valida que ID (link_type_id confirmado pelo operador) esta entre os
      CANDIDATE_ID... devolvidos por GET /rest/api/3/issueLinkType (R16)
      nesta execucao. ID fora da lista => exit 1 com os candidatos.

  jira-setup.sh resolve-link-type
      Le de stdin linhas ID<TAB>INWARD<TAB>OUTWARD (tipos de R16 desta
      execucao). Exatamente 1 linha com inward E outward contendo "block"
      (case-insensitive) => imprime o ID, exit 0. 0 ou 2+ candidatos =>
      exit 1 com "unrepresentable reason=no_link_type|ambiguous_link_type".

  jira-setup.sh write-config KEY=VALUE [KEY=VALUE...]
      Grava ProjectConfig atomicamente (temp file + jira-config.sh validate
      + mv). Config invalido/incompleto => nada e gravado no caminho final.

EXIT CODES:
  0 sucesso   1 mapeamento/config invalido   2 uso incorreto
HELP
}

# _js_script_dir — diretorio deste script (mesma tecnica de jira-io.sh
# _ji_script_dir), usado para localizar jira-config.sh irmao.
_js_script_dir() {
  CDPATH='' cd -- "$(dirname -- "$0")" && pwd
}

_JS_JIRA_CONFIG_SCRIPT="$(_js_script_dir)/jira-config.sh"

# FASE 12 tarefa 12.6.1 (FR-016 / data-model.md OutboxEvent
# auth_failed->queued): apos `write-config` gravar com sucesso, devolve
# eventos `auth_failed` a `queued` — a credencial e GLOBAL ao projeto
# (`_JS_CONFIG_FILE` acima), entao uma reconfiguracao bem-sucedida vale
# para todas as features do outbox compartilhado (sem --feature).
_JS_JIRA_SYNC_SCRIPT="$(_js_script_dir)/jira-sync.sh"

# Mesmo path/convencao de _JC_CONFIG_FILE em jira-config.sh — as duas
# ferramentas MUST concordar sobre onde o ProjectConfig vive.
_JS_CONFIG_FILE="${CSTK_JIRA_CONFIG:-./.claude/cstk-jira/config}"

# _js_contains VALUE STATUS... -> exit 0 se VALUE casa (igualdade exata,
# case-sensitive) com algum dos STATUS seguintes.
_js_contains() {
  _jsc_needle="$1"
  shift
  for _jsc_hay in "$@"; do
    [ "$_jsc_needle" = "$_jsc_hay" ] && return 0
  done
  return 1
}

_js_cmd_check_status_mapping() {
  [ "$#" -ge 5 ] || _js_die_usage \
    "check-status-mapping requer PENDING IN_PROGRESS PASS FAIL e ao menos 1 STATUS"
  _jscm_pending="$1"
  _jscm_inprogress="$2"
  _jscm_pass="$3"
  _jscm_fail="$4"
  shift 4
  # "$@" agora e a lista de status descobertos (STATUS...)
  _jscm_list=$(printf '%s, ' "$@")
  _jscm_list=${_jscm_list%, }

  if [ "$_jscm_fail" = "$_jscm_pass" ]; then
    _js_die "status_fail e status_pass nao podem ser o mesmo ('$_jscm_pass') — escolha um status distinto do workflow. Status disponiveis: $_jscm_list"
  fi

  for _jscm_label_val in \
    "pending:$_jscm_pending" \
    "in_progress:$_jscm_inprogress" \
    "pass:$_jscm_pass" \
    "fail:$_jscm_fail"
  do
    _jscm_label=${_jscm_label_val%%:*}
    _jscm_val=${_jscm_label_val#*:}
    if ! _js_contains "$_jscm_val" "$@"; then
      _js_die "status '$_jscm_val' (mapeado para '$_jscm_label') nao esta entre os status descobertos no workflow do projeto. Status disponiveis: $_jscm_list"
    fi
  done

  return 0
}

# _js_cmd_check_link_type ID CANDIDATE_ID... — r02 FASE 18 tarefa 18.1.1
# (SEC-13): membership PURA (mesmo idioma de _js_cmd_check_status_mapping
# com R5) — ID so e aceito se estiver entre os CANDIDATE_ID... que a skill
# leu de R16 nesta execucao. NUNCA um id digitado de memoria (a lista vem
# sempre de fora, nunca de um literal fixo aqui).
_js_cmd_check_link_type() {
  [ "$#" -ge 2 ] || _js_die_usage \
    "check-link-type requer ID e ao menos 1 CANDIDATE_ID"
  _jsclt_id="$1"
  shift
  _jsclt_list=$(printf '%s, ' "$@")
  _jsclt_list=${_jsclt_list%, }

  _js_contains "$_jsclt_id" "$@" \
    || _js_die "link_type_id '$_jsclt_id' nao esta entre os candidatos devolvidos por GET /rest/api/3/issueLinkType (R16) nesta execucao. Candidatos: $_jsclt_list"

  return 0
}

# _js_cmd_resolve_link_type — r02 FASE 18 tarefa 18.2.1/18.2.2. Le de
# stdin: ID<TAB>INWARD<TAB>OUTWARD por linha (candidatos de R16 nesta
# execucao, SEC-13). Nunca aceita argumentos posicionais (a lista so pode
# vir de stdin — evita truncamento de shell/awk em frases com espaco).
_js_cmd_resolve_link_type() {
  [ "$#" -eq 0 ] || _js_die_usage \
    "resolve-link-type nao aceita argumentos (leia via stdin: ID<TAB>INWARD<TAB>OUTWARD por linha)"

  _jsrlt_out=$(awk -F '\t' '
    BEGIN { n = 0; nmatch = 0 }
    NF >= 3 && $1 != "" {
      n++
      inward = tolower($2)
      outward = tolower($3)
      if (index(inward, "block") > 0 && index(outward, "block") > 0) {
        nmatch++
        matched[nmatch] = $1
      }
    }
    END {
      print n
      print nmatch
      for (i = 1; i <= nmatch; i++) print matched[i]
    }
  ')

  _jsrlt_n=$(printf '%s\n' "$_jsrlt_out" | sed -n '1p')
  _jsrlt_nmatch=$(printf '%s\n' "$_jsrlt_out" | sed -n '2p')

  case "$_jsrlt_nmatch" in
    1)
      printf '%s\n' "$_jsrlt_out" | sed -n '3p'
      return 0
      ;;
    0)
      _js_die "unrepresentable reason=no_link_type: nenhum dos $_jsrlt_n tipo(s) de R16 tem inward E outward contendo 'block' (case-insensitive) — link_type_id automatico indisponivel"
      ;;
    *)
      _jsrlt_matched_list=$(printf '%s\n' "$_jsrlt_out" | sed -n '3,$p' | tr '\n' ',' | sed 's/,$//')
      _js_die "unrepresentable reason=ambiguous_link_type: $_jsrlt_nmatch candidatos casam 'block' em inward e outward ($_jsrlt_matched_list) — escolha arbitraria proibida, confirme link_type_id manualmente no setup"
      ;;
  esac
}

_js_cmd_write_config() {
  [ "$#" -ge 1 ] || _js_die_usage "write-config requer ao menos um KEY=VALUE"

  _jswc_dir=$(dirname -- "$_JS_CONFIG_FILE")
  mkdir -p -- "$_jswc_dir" 2>/dev/null \
    || _js_die "nao foi possivel criar diretorio: $_jswc_dir"

  _jswc_tmp="$_jswc_dir/.jira-setup-config.tmp.$$"
  _jswc_err="$_jswc_tmp.err"
  # trap de limpeza — nunca deixa temp file para tras em falha inesperada.
  trap 'rm -f "$_jswc_tmp" "$_jswc_err" 2>/dev/null || :' EXIT INT TERM

  : > "$_jswc_tmp"
  for _jswc_kv in "$@"; do
    case "$_jswc_kv" in
      *=*) printf '%s\n' "$_jswc_kv" >> "$_jswc_tmp" ;;
      *)
        _js_die_usage "argumento invalido (esperado KEY=VALUE): $_jswc_kv"
        ;;
    esac
  done

  if ! CSTK_JIRA_CONFIG="$_jswc_tmp" "$_JS_JIRA_CONFIG_SCRIPT" validate \
        >/dev/null 2>"$_jswc_err"; then
    _jswc_diag=$(cat -- "$_jswc_err" 2>/dev/null || :)
    _js_die "config invalido — NADA foi gravado em $_JS_CONFIG_FILE: $_jswc_diag"
  fi

  mv -- "$_jswc_tmp" "$_JS_CONFIG_FILE"
  trap - EXIT INT TERM

  # FASE 12 tarefa 12.6.1 (FR-016 / data-model.md OutboxEvent
  # auth_failed->queued): ProjectConfig acabou de ser gravado com sucesso —
  # a skill so chega ate aqui (ETAPA 7) apos a credencial ja ter sido
  # validada na ETAPA 2 (`jira-io.sh request GET /rest/api/3/myself`).
  # Devolve qualquer evento `auth_failed` a `queued` para o proximo drain
  # reprocessar. Best-effort/aditivo: nunca desfaz a gravacao acima nem
  # falha write-config caso o outbox nao exista ou jira-sync.sh nao esteja
  # disponivel (ex.: ambiente de teste isolado sem o script irmao).
  if [ -x "$_JS_JIRA_SYNC_SCRIPT" ]; then
    if _jswc_requeue_out=$("$_JS_JIRA_SYNC_SCRIPT" requeue-auth-failed 2>&1); then
      printf '%s\n' "$_jswc_requeue_out"
    else
      printf '%s: aviso — requeue-auth-failed falhou apos gravar config (nao bloqueia a reconfiguracao): %s\n' \
        "$_JS_NAME" "$_jswc_requeue_out" >&2
    fi
  fi

  return 0
}

# --- dispatcher ---------------------------------------------------------

_js_sub="${1:-}"
[ "$#" -ge 1 ] && shift || :

case "$_js_sub" in
  ''|-h|--help|help)
    _js_usage
    exit 0
    ;;
  check-status-mapping)
    _js_cmd_check_status_mapping "$@"
    ;;
  check-link-type)
    _js_cmd_check_link_type "$@"
    ;;
  resolve-link-type)
    _js_cmd_resolve_link_type "$@"
    ;;
  write-config)
    _js_cmd_write_config "$@"
    ;;
  *)
    _js_die_usage "subcomando desconhecido: $_js_sub (validos: check-status-mapping, check-link-type, resolve-link-type, write-config)"
    ;;
esac
