#!/bin/sh
# jira-title.sh — compoe o `fields.summary` de uma issue Jira a partir das
# colunas do LocalWorkItem (`jira-tasks.sh items`). Fonte UNICA de verdade
# usada tanto pelo caminho REST (`jira-sync.sh convert`) quanto pelo caminho
# MCP (skill `jira-convert`), para que os dois produzam o MESMO titulo em
# qualquer issue criada (cstk-jira, FASE 6 tarefa 6.2.3; checklists/api.md
# CHK012 — "mesmo efeito observavel", nao dois comportamentos divergentes
# conforme o mecanismo disponivel no ambiente).
#
# Ref: docs/specs/cstk-jira/data-model.md Entity LocalWorkItem (comentario
#      2.2.5: "Titulo do Epic prefixado por fase" e nota de `jira-tasks.sh`
#      explicando que o padrao correto e para TASK, nao Epic);
#      `jira-sync.sh` `_js_cmd_convert` (logica original, ate onda-027
#      duplicada inline — extraida para este script exatamente para
#      eliminar essa duplicacao e fechar CHK012 por construcao).
#
# Regra (idem `_js_cmd_convert`, tasks.md 4.1.3):
#   epic    -> title tal-e-qual
#   task    -> "[<2 primeiras palavras de phase>] <local_key> <title>"
#              ex.: phase="FASE 6 - Skills Interativas" local_key="6.2"
#              -> "[FASE 6] 6.2 <title>"
#   subtask -> title tal-e-qual (data-model.md nao especifica prefixo)
#
# Subcomandos:
#   jira-title.sh compose --kind epic|task|subtask [--phase PHASE] \
#                          [--local-key KEY] --title TITLE
#       — Imprime em stdout o summary composto. `--phase`/`--local-key` sao
#         OBRIGATORIOS apenas para `--kind task` (ignorados, se informados,
#         para epic/subtask — o chamador pode repassar os mesmos 4 campos
#         de `jira-tasks.sh items` sem precisar ramificar por kind antes).
#
# Convencoes (Principio II / contracts/plugin-scripts.md):
#   `#!/bin/sh`, `set -eu`, sem bash-isms; dados em stdout, diagnostico em
#   stderr. Exit codes: 0 sucesso; 1 erro geral; 2 uso incorreto.
#
# Este script NAO toca rede/jq/jira-io.sh — pura manipulacao de string
# (POSIX sh + awk), deliberadamente independente do cliente HTTP para poder
# ser chamado tambem pelo caminho MCP (que nunca invoca jira-io.sh).

set -eu

_JT_NAME="jira-title"

_jt_die_usage() { printf '%s: %s\n' "$_JT_NAME" "$1" >&2; exit 2; }

_jt_usage() {
  cat <<'HELP'
jira-title.sh — compoe o fields.summary de uma issue Jira (fonte unica
usada por jira-sync.sh convert E pela skill jira-convert/caminho MCP)

USO:
  jira-title.sh compose --kind epic|task|subtask [--phase PHASE] \
                         [--local-key KEY] --title TITLE
      epic/subtask: imprime TITLE tal-e-qual (phase/local-key ignorados)
      task: imprime "[<2 primeiras palavras de PHASE>] KEY TITLE"
            (--phase e --local-key OBRIGATORIOS para kind=task)

EXIT CODES:
  0 sucesso   1 erro geral   2 uso incorreto
HELP
}

_jt_cmd_compose() {
  _jtc_kind=""
  _jtc_phase=""
  _jtc_key=""
  _jtc_title=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --kind)
        [ "$#" -ge 2 ] || _jt_die_usage "--kind requer valor"
        _jtc_kind="$2"; shift 2 ;;
      --phase)
        [ "$#" -ge 2 ] || _jt_die_usage "--phase requer valor"
        _jtc_phase="$2"; shift 2 ;;
      --local-key)
        [ "$#" -ge 2 ] || _jt_die_usage "--local-key requer valor"
        _jtc_key="$2"; shift 2 ;;
      --title)
        [ "$#" -ge 2 ] || _jt_die_usage "--title requer valor"
        _jtc_title="$2"; shift 2 ;;
      *)
        _jt_die_usage "argumento desconhecido: $1" ;;
    esac
  done

  case "$_jtc_kind" in
    epic|task|subtask) : ;;
    *) _jt_die_usage "--kind invalido (validos: epic, task, subtask): '$_jtc_kind'" ;;
  esac
  [ -n "$_jtc_title" ] || _jt_die_usage "compose requer --title nao-vazio"

  case "$_jtc_kind" in
    epic|subtask)
      printf '%s\n' "$_jtc_title"
      ;;
    task)
      [ -n "$_jtc_phase" ] || _jt_die_usage "compose --kind task requer --phase nao-vazio"
      [ -n "$_jtc_key" ] || _jt_die_usage "compose --kind task requer --local-key nao-vazio"
      _jtc_phase_tag=$(printf '%s' "$_jtc_phase" | awk '{print $1, $2}')
      printf '[%s] %s %s\n' "$_jtc_phase_tag" "$_jtc_key" "$_jtc_title"
      ;;
  esac
}

# --- dispatcher ---------------------------------------------------------

_jt_sub="${1:-}"
[ "$#" -ge 1 ] && shift || :

case "$_jt_sub" in
  ''|-h|--help|help)
    _jt_usage
    exit 0
    ;;
  compose)
    _jt_cmd_compose "$@"
    ;;
  *)
    _jt_die_usage "subcomando desconhecido: $_jt_sub (validos: compose)"
    ;;
esac
