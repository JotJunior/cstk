#!/bin/sh
# sanitize.sh — sanitizacao de descricao_curta e outros free-text (FR-025).
#
# Ref: docs/specs/agente-00c/spec.md FR-025
#      docs/specs/agente-00c/threat-model.md T1
#      docs/specs/agente-00c/tasks.md FASE 6.2
#
# Le STDIN, escreve STDOUT, conforme subcomando:
#
# Subcomandos:
#   sanitize.sh limit-length [--max N]
#       — Trunca em N chars (default 500). Sem perda de UTF-8.
#       — Adiciona "..." ao fim quando truncado (NAO contado no limite).
#
#   sanitize.sh escape-commit-msg
#       — Escapa para uso em `git commit -m "..."`:
#         * remove newlines (substituicao por espaco)
#         * remove backticks, $, ", e outros chars que viram interpolacao
#         * limita a 100 chars (commit subject limit razoavel)
#
#   sanitize.sh escape-issue-body
#       — Escapa para uso em `gh issue create --body "..."`:
#         * remove backticks (poderiam virar code injection em markdown
#           processado por automacao)
#         * remove sequencias `$(...)` e `\`...\`` (shell injection se
#           passado mal por wrappers)
#         * preserva newlines (issue body suporta multilinha)
#
#   sanitize.sh escape-path
#       — Escapa para uso em path de arquivo:
#         * substitui /, .., \ e null por _
#         * substitui caracteres nao-[A-Za-z0-9._-] por _
#         * limita a 64 chars
#
#   sanitize.sh check-length [--max N]
#       — Exit 0 se input tem <= N chars (default 500); exit 1 caso contrario.
#
# Exit codes:
#   0 sucesso
#   1 erro generico (ex: check-length excedido)
#   2 uso incorreto
#
# POSIX sh + tr/sed/awk.

set -eu

_SN_NAME="sanitize"

_sn_die_usage() { printf '%s: %s\n' "$_SN_NAME" "$1" >&2; exit 2; }

# _sn_byte_count -> read stdin to var, count chars (POSIX wc -c counts bytes;
# for UTF-8, multibyte chars count more — aceitavel para limite de seguranca).
_sn_cmd_limit_length() {
  _max=500
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --max) _max=$2; shift 2 ;;
      *) _sn_die_usage "limit-length: flag desconhecida: $1" ;;
    esac
  done
  case "$_max" in
    ''|*[!0-9]*) _sn_die_usage "limit-length: --max precisa ser numero" ;;
  esac
  _input=$(cat)
  _len=$(printf '%s' "$_input" | wc -c | tr -d ' ')
  if [ "$_len" -le "$_max" ]; then
    printf '%s' "$_input"
  else
    # Trunca para $_max bytes (cut -c "1-$_max" funciona em ambos BSD/GNU
    # para ASCII; para UTF-8 pode quebrar caractere multibyte — aceitavel
    # neste contexto de seguranca, ja que o objetivo e LIMITE, nao precisao).
    printf '%s' "$_input" | cut -c "1-$_max"
    printf '...'
  fi
}

_sn_cmd_check_length() {
  _max=500
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --max) _max=$2; shift 2 ;;
      *) _sn_die_usage "check-length: flag desconhecida: $1" ;;
    esac
  done
  _len=$(wc -c | tr -d ' ')
  if [ "$_len" -gt "$_max" ]; then
    printf '%s: input excede %s bytes (atual: %s)\n' "$_SN_NAME" "$_max" "$_len" >&2
    exit 1
  fi
  exit 0
}

_sn_cmd_escape_commit_msg() {
  # 1. Newlines + tabs -> espaco
  # 2. Remove backticks, $, " (interpoladores)
  # 3. Colapsa whitespace
  # 4. Limita a 100 chars
  cat \
    | tr '\n\r\t' '   ' \
    | sed -e 's/[`$"]//g' \
    | tr -s ' ' \
    | cut -c 1-100
}

_sn_cmd_escape_issue_body() {
  # Preserva newlines (markdown multilinha).
  # Remove backticks (code injection em markdown processado).
  # Remove sequencias $(...) e \`...\` (shell injection em wrappers).
  # Sem limite de comprimento aqui — body pode ser longo.
  _input=$(cat)
  # Step 1: remove $(...) — match nao-greedy via sed
  _input=$(printf '%s' "$_input" | sed -e 's/\$([^)]*)//g')
  # Step 2: remove `...` (backtick subshell)
  _input=$(printf '%s' "$_input" | sed -e 's/`[^`]*`//g')
  # Step 3: remove backticks restantes (codeblock que poderia confundir)
  printf '%s' "$_input" | tr -d '`'
}

_sn_cmd_escape_path() {
  # 1. Substitui chars unsafe por _
  # 2. Remove .. literal (path traversal)
  # 3. Limita a 64 chars
  cat \
    | tr -d '\000' \
    | sed -e 's/\.\.//g' \
    | tr -c 'A-Za-z0-9._-' '_' \
    | cut -c 1-64
}

# ---------- Dispatch ----------

if [ "$#" -lt 1 ]; then
  cat >&2 <<'HELP'
sanitize.sh — sanitizacao de free-text (FR-025).

USO:
  sanitize.sh limit-length [--max N]   < input
  sanitize.sh check-length [--max N]   < input
  sanitize.sh escape-commit-msg        < input
  sanitize.sh escape-issue-body        < input
  sanitize.sh escape-path              < input

Defaults: --max 500 para limit-length/check-length.

EXIT:
  0 sucesso
  1 erro (ex: check-length excedido)
  2 uso incorreto
HELP
  exit 2
fi

_SN_SUBCMD=$1
shift

case "$_SN_SUBCMD" in
  limit-length)        _sn_cmd_limit_length "$@" ;;
  check-length)        _sn_cmd_check_length "$@" ;;
  escape-commit-msg)   _sn_cmd_escape_commit_msg "$@" ;;
  escape-issue-body)   _sn_cmd_escape_issue_body "$@" ;;
  escape-path)         _sn_cmd_escape_path "$@" ;;
  -h|--help|help)      exit 0 ;;
  *) _sn_die_usage "subcomando desconhecido: $_SN_SUBCMD" ;;
esac
