#!/bin/sh
# state-lock.sh — lock anti-concorrencia do agente-00C via mkdir atomico.
#
# Ref: docs/specs/agente-00c/spec.md FR-022, edge case "multiplas execucoes"
#      docs/specs/agente-00c/contracts/cli-invocation.md
#      docs/specs/agente-00c/checklists/checklist-seguranca.md CHK072 (residual)
#
# Sintaxe:
#   state-lock.sh acquire --state-dir DIR
#       — cria <DIR>/.lock/ atomicamente. Exit 3 se ja detido.
#   state-lock.sh release --state-dir DIR
#       — remove <DIR>/.lock/ (idempotente).
#   state-lock.sh check --state-dir DIR
#       — exit 0 se acquirable (lock livre), exit 3 se detido.
#   state-lock.sh check-execution-busy --state-dir DIR
#       — exit 0 se nao ha execucao em andamento (state.json ausente OU
#         status terminal). Exit 3 se ha execucao com status em_andamento
#         ou aguardando_humano (instrui /agente-00c-resume ou
#         /agente-00c-abort).
#
# Permite invocacoes simultaneas em projetos-alvo distintos — cada um tem
# seu proprio state-dir e portanto seu proprio lock.
#
# Limitacao TOCTOU (CHK072): entre check-execution-busy e o inicio efetivo
# da execucao, outro processo PODE criar state.json. Tradeoff aceito —
# uso pessoal, baixa contencao.
#
# Exit codes:
#   0 sucesso
#   1 erro generico (FS error, jq ausente)
#   2 uso incorreto
#   3 lock ja detido OU execucao ja em andamento
#
# POSIX sh + mkdir/rmdir + (jq apenas em check-execution-busy).

set -eu

_SL_NAME="state-lock"
_SL_DIR=$(cd "$(dirname -- "$0")" && pwd)

# Envelope diagnostico aditivo (openspec-hygiene FR-012/FR-015 — escopo-piloto).
# Nota: o contrato da feature propos 2 codes (lock-contention, lock-stale),
# mas a leitura do codigo real (task 4.3.1) confirmou que NAO existe
# deteccao automatica de staleness aqui — "acquire" e "check" reportam a
# MESMA condicao (lock ja detido); o texto sobre "stale" e apenas uma
# sugestao textual para o operador remover manualmente. Migrado apenas
# `lock-contention`, aplicado nos 2 pontos de falha reais (acquire + check).
# shellcheck source=./_diag.sh
. "$_SL_DIR/_diag.sh"

_sl_die_usage() {
  printf '%s: %s\n' "$_SL_NAME" "$1" >&2
  exit 2
}

_sl_print_help() {
  cat >&2 <<'HELP'
state-lock.sh — lock anti-concorrencia do agente-00C.

USO:
  state-lock.sh <subcomando> --state-dir DIR

SUBCOMANDOS:
  acquire                Cria <DIR>/.lock/ atomicamente. Exit 3 se ja detido.
  release                Remove <DIR>/.lock/ (idempotente).
  check                  Exit 0 se acquirable, 3 se detido.
  check-execution-busy   Exit 0 se nao ha execucao em status nao-terminal;
                         3 se ha (instrui /agente-00c-resume ou abort).

EXIT:
  0 sucesso
  1 erro generico (FS, jq)
  2 uso incorreto
  3 conflito (lock detido OU execucao em andamento)
HELP
}

if [ "$#" -lt 1 ]; then
  _sl_print_help
  exit 2
fi

_SL_SUBCMD=$1
shift

case "$_SL_SUBCMD" in
  -h|--help|help) _sl_print_help; exit 0 ;;
esac

_SL_STATE_DIR=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --state-dir) _SL_STATE_DIR=$2; shift 2 ;;
    *) _sl_die_usage "flag desconhecida: $1" ;;
  esac
done
[ -n "$_SL_STATE_DIR" ] || _sl_die_usage "--state-dir obrigatorio"

_SL_LOCK="$_SL_STATE_DIR/.lock"
_SL_STATE="$_SL_STATE_DIR/state.json"

case "$_SL_SUBCMD" in
  acquire)
    # Garante diretorio pai. Sem -p para nao mascarar erro de FS read-only.
    if [ ! -d "$_SL_STATE_DIR" ]; then
      mkdir -p -- "$_SL_STATE_DIR" 2>/dev/null \
        || { printf '%s: nao consegui criar %s\n' "$_SL_NAME" "$_SL_STATE_DIR" >&2; exit 1; }
    fi
    # Semeia .gitignore "*" no state-dir desde o PRIMEIRO toque (acquire roda
    # antes do state-rw init no fluxo do command pai). Estado e runtime e
    # nunca deve ser versionado. Best-effort + idempotente (paridade com
    # _sr_ensure_state_dir em state-rw.sh).
    if [ ! -e "$_SL_STATE_DIR/.gitignore" ]; then
      printf '*\n' > "$_SL_STATE_DIR/.gitignore" 2>/dev/null || :
    fi
    if mkdir -- "$_SL_LOCK" 2>/dev/null; then
      exit 0
    fi
    printf '%s: lock ja detido em %s\n' "$_SL_NAME" "$_SL_LOCK" >&2
    printf '       outro processo do agente-00C esta ativo neste projeto.\n' >&2
    printf '       Se acredita que e stale, remova manualmente: rmdir %s\n' "$_SL_LOCK" >&2
    diag_emit error lock-contention "acquire: lock ja detido em $_SL_LOCK" \
      "aguarde o outro processo liberar, ou se tiver certeza que e stale: rmdir $_SL_LOCK" || :
    exit 3
    ;;
  release)
    if [ -d "$_SL_LOCK" ]; then
      if ! rmdir -- "$_SL_LOCK" 2>/dev/null; then
        # Pode existir conteudo dentro do lock dir — nao deveria, mas tolera.
        rm -rf -- "$_SL_LOCK" 2>/dev/null \
          || { printf '%s: nao consegui remover %s\n' "$_SL_NAME" "$_SL_LOCK" >&2; exit 1; }
      fi
    fi
    exit 0
    ;;
  check)
    if [ -d "$_SL_LOCK" ]; then
      printf '%s: lock detido em %s\n' "$_SL_NAME" "$_SL_LOCK" >&2
      diag_emit error lock-contention "check: lock detido em $_SL_LOCK" \
        "aguarde o outro processo liberar, ou se tiver certeza que e stale: rmdir $_SL_LOCK" || :
      exit 3
    fi
    exit 0
    ;;
  check-execution-busy)
    if [ ! -f "$_SL_STATE" ]; then
      exit 0
    fi
    if ! command -v jq >/dev/null 2>&1; then
      printf '%s: jq nao encontrado no PATH (necessario para check-execution-busy).\n' "$_SL_NAME" >&2
      exit 1
    fi
    _status=$(jq -r '(.execution.status // .execucao.status) // ""' "$_SL_STATE" 2>/dev/null) || _status=""
    case "$_status" in
      em_andamento|aguardando_humano)
        printf '%s: ja existe execucao em status "%s" em %s.\n' "$_SL_NAME" "$_status" "$_SL_STATE" >&2
        printf '       Use /agente-00c-resume para retomar ou /agente-00c-abort para abortar.\n' >&2
        exit 3
        ;;
      ""|abortada|concluida)
        exit 0
        ;;
      *)
        printf '%s: status desconhecido em %s: "%s"\n' "$_SL_NAME" "$_SL_STATE" "$_status" >&2
        exit 1
        ;;
    esac
    ;;
  *)
    _sl_die_usage "subcomando desconhecido: $_SL_SUBCMD (use --help)"
    ;;
esac
