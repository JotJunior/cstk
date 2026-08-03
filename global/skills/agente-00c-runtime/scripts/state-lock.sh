#!/bin/sh
# state-lock.sh — lock anti-concorrencia do agente-00C via mkdir atomico.
#
# Ref: docs/specs/agente-00c/spec.md FR-022, edge case "multiplas execucoes"
#      docs/specs/agente-00c/contracts/cli-invocation.md
#      docs/specs/agente-00c/checklists/checklist-seguranca.md CHK072 (residual)
#
# Sintaxe:
#   state-lock.sh acquire --state-dir DIR [--owner-pid N]
#       — cria <DIR>/.lock/ atomicamente. Exit 3 se ja detido.
#         Grava o DONO (arquivo <DIR>/.lock/owner com pid= + acquired_at=)
#         pos-mkdir, best-effort — o mkdir permanece a primitiva atomica
#         (spec state-db-runtime-parity FR-007a, dec-059). Default do pid:
#         $PPID (processo invocador); override via --owner-pid.
#   state-lock.sh acquire --state-dir DIR --force [--owner-pid N]
#       — freio de emergencia do abort (FR-007/FR-007a): so consuma se o
#         dono estiver comprovadamente morto (kill -0 falha) OU o lock for
#         legado sem owner (aviso explicito de dono-desconhecido). Dono
#         VIVO => recusa (exit 3 + diagnostico). Todo force sobre lock
#         detido emite diag_emit lock-force-acquired com pid antigo/novo.
#         Pre-condicao CONTRATUAL (nao verificada aqui): SIGTERM + grace
#         period antes (feature-00c-abort.md); nunca primeiro recurso.
#   state-lock.sh release --state-dir DIR
#       — remove <DIR>/.lock/ (idempotente; inclui o arquivo owner).
#   state-lock.sh check --state-dir DIR
#       — exit 0 se acquirable (lock livre), exit 3 se detido (reporta o
#         dono quando o arquivo owner existe).
#   state-lock.sh check-execution-busy --state-dir DIR
#       — exit 0 se nao ha execucao em andamento (estado ausente OU status
#         terminal). Exit 3 se ha execucao com status em_andamento
#         ou aguardando_humano (instrui /agente-00c-resume ou
#         /agente-00c-abort). Le o estado via _state-read.sh — cobre os
#         DOIS backends (state.json e state.db — feature
#         state-db-runtime-parity FR-010; falha de materializacao propaga,
#         nunca degrada mudo, FR-012).
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
# POSIX sh + mkdir/rmdir + (jq + _state-read.sh apenas em
# check-execution-busy; o lock em si NAO depende do estado para
# adquirir/liberar).

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

# Materializacao de estado legivel nos dois backends (json/sqlite) — usada
# apenas por check-execution-busy (state-db-runtime-parity FR-010). O lock
# mkdir permanece independente do estado (acquire/release/check intactos).
# shellcheck source=./_state-read.sh
. "$_SL_DIR/_state-read.sh"
trap state_read_cleanup EXIT INT TERM

_sl_die_usage() {
  printf '%s: %s\n' "$_SL_NAME" "$1" >&2
  exit 2
}

_sl_print_help() {
  cat >&2 <<'HELP'
state-lock.sh — lock anti-concorrencia do agente-00C.

USO:
  state-lock.sh <subcomando> --state-dir DIR [--force] [--owner-pid N]

SUBCOMANDOS:
  acquire                Cria <DIR>/.lock/ atomicamente e grava o dono
                         (.lock/owner: pid + acquired_at). Exit 3 se ja
                         detido. Com --force (fluxo de abort, FR-007a):
                         consuma so com dono morto ou lock legado sem
                         owner (aviso); dono VIVO = recusa (exit 3).
                         --owner-pid sobrepoe o PID gravado (default PPID).
  release                Remove <DIR>/.lock/ (idempotente).
  check                  Exit 0 se acquirable, 3 se detido (reporta dono).
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
_SL_FORCE=0
_SL_OWNER_PID=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --state-dir) _SL_STATE_DIR=$2; shift 2 ;;
    --force) _SL_FORCE=1; shift ;;
    --owner-pid)
      [ "$#" -ge 2 ] || _sl_die_usage "--owner-pid exige valor"
      case "$2" in
        ''|*[!0-9]*) _sl_die_usage "--owner-pid exige PID numerico (obtido: $2)" ;;
      esac
      _SL_OWNER_PID=$2; shift 2 ;;
    *) _sl_die_usage "flag desconhecida: $1" ;;
  esac
done
[ -n "$_SL_STATE_DIR" ] || _sl_die_usage "--state-dir obrigatorio"
if [ "$_SL_SUBCMD" != "acquire" ]; then
  [ "$_SL_FORCE" = 0 ] || _sl_die_usage "--force so e valido com acquire"
  [ -z "$_SL_OWNER_PID" ] || _sl_die_usage "--owner-pid so e valido com acquire"
fi

_SL_LOCK="$_SL_STATE_DIR/.lock"
_SL_STATE="$_SL_STATE_DIR/state.json"
_SL_OWNER_FILE="$_SL_LOCK/owner"

# Grava o dono do lock (FR-007a, dec-059): pid + timestamp dentro do .lock.
# Best-effort (nunca falha o acquire) — o mkdir e a primitiva atomica; o
# owner e metadado de auditoria/verificacao para o --force e o check.
_sl_write_owner() {
  {
    printf 'pid=%s\n' "${_SL_OWNER_PID:-$PPID}"
    printf 'acquired_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$_SL_OWNER_FILE" 2>/dev/null || :
}

# Imprime o pid do dono registrado, ou string vazia (lock legado sem owner
# ou owner ilegivel/malformado — tratado como dono-desconhecido, 4.1.bis.3).
_sl_owner_pid() {
  [ -f "$_SL_OWNER_FILE" ] || { printf ''; return 0; }
  _sl_op=$(sed -n 's/^pid=\([0-9][0-9]*\)$/\1/p' "$_SL_OWNER_FILE" 2>/dev/null | head -n 1) || _sl_op=""
  printf '%s' "$_sl_op"
}

# Imprime o acquired_at do dono registrado, ou vazio.
_sl_owner_ts() {
  [ -f "$_SL_OWNER_FILE" ] || { printf ''; return 0; }
  sed -n 's/^acquired_at=\(.*\)$/\1/p' "$_SL_OWNER_FILE" 2>/dev/null | head -n 1 || :
}

# Linha aditiva de stderr descrevendo o dono do lock detido (4.1.bis.2).
_sl_report_owner() {
  _sl_ro_pid=$(_sl_owner_pid)
  if [ -n "$_sl_ro_pid" ]; then
    if kill -0 "$_sl_ro_pid" 2>/dev/null; then _sl_ro_alive="vivo"; else _sl_ro_alive="morto"; fi
    printf '       dono do lock: pid=%s (%s), acquired_at=%s\n' \
      "$_sl_ro_pid" "$_sl_ro_alive" "$(_sl_owner_ts)" >&2
  else
    printf '       dono do lock: desconhecido (lock legado sem arquivo owner)\n' >&2
  fi
}

# Remove o lock detido e readquire na MESMA invocacao (caminho autorizado
# do --force). Falha de remocao/mkdir => exit 1 com diagnostico (contract §2).
_sl_force_consummate() {
  _sl_fc_old=$1
  if ! rmdir -- "$_SL_LOCK" 2>/dev/null; then
    rm -rf -- "$_SL_LOCK" 2>/dev/null || :
  fi
  if [ -d "$_SL_LOCK" ]; then
    printf '%s: acquire --force: nao consegui remover %s\n' "$_SL_NAME" "$_SL_LOCK" >&2
    diag_emit error lock-force-remove-failed "acquire --force: falha ao remover $_SL_LOCK" \
      "verifique permissoes do state-dir e remova manualmente: rm -rf $_SL_LOCK" || :
    exit 1
  fi
  if ! mkdir -- "$_SL_LOCK" 2>/dev/null; then
    printf '%s: acquire --force: falha ao readquirir %s apos remocao\n' "$_SL_NAME" "$_SL_LOCK" >&2
    diag_emit error lock-force-reacquire-failed "acquire --force: mkdir falhou em $_SL_LOCK apos remocao" \
      "possivel corrida com outro processo; re-execute o acquire" || :
    exit 1
  fi
  _sl_write_owner
  diag_emit warning lock-force-acquired \
    "acquire --force: lock removido e readquirido em $_SL_LOCK (pid antigo=$_sl_fc_old, pid novo=${_SL_OWNER_PID:-$PPID})" \
    "aquisicao forcada auditavel (FR-007a); confirme que o SIGTERM + grace period precedeu este force" || :
  exit 0
}

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
      _sl_write_owner
      exit 0
    fi
    if [ "$_SL_FORCE" = 1 ]; then
      # Freio de emergencia (FR-007/FR-007a, dec-059): verificar o dono
      # ANTES de consumar — nunca forcar dono vivo.
      _sl_pid=$(_sl_owner_pid)
      if [ -n "$_sl_pid" ]; then
        if kill -0 "$_sl_pid" 2>/dev/null; then
          printf '%s: acquire --force RECUSADO: dono do lock esta VIVO (pid=%s, acquired_at=%s)\n' \
            "$_SL_NAME" "$_sl_pid" "$(_sl_owner_ts)" >&2
          printf '       nunca force um lock com dono vivo (FR-007a); encerre o processo primeiro (SIGTERM + grace).\n' >&2
          diag_emit error lock-force-denied-owner-alive \
            "acquire --force: dono do lock vivo (pid=$_sl_pid) em $_SL_LOCK — force recusado" \
            "encerre o processo dono (SIGTERM + grace period) e so entao repita o acquire --force" || :
          exit 3
        fi
        # Dono comprovadamente morto (kill -0 falhou) — autorizado.
        _sl_force_consummate "$_sl_pid"
      fi
      # Lock legado SEM owner (dono-desconhecido, 4.1.bis.3): heuristica
      # antiga (pre-condicao contratual SIGTERM+grace) + aviso explicito.
      printf '%s: AVISO: lock legado sem arquivo owner (dono-desconhecido) — forcando com base na pre-condicao contratual (SIGTERM + grace period ja executados).\n' "$_SL_NAME" >&2
      _sl_force_consummate "desconhecido"
    fi
    printf '%s: lock ja detido em %s\n' "$_SL_NAME" "$_SL_LOCK" >&2
    printf '       outro processo do agente-00C esta ativo neste projeto.\n' >&2
    printf '       Se acredita que e stale, remova manualmente: rmdir %s\n' "$_SL_LOCK" >&2
    _sl_report_owner
    diag_emit error lock-contention "acquire: lock ja detido em $_SL_LOCK" \
      "aguarde o outro processo liberar, ou se tiver certeza que e stale: rmdir $_SL_LOCK" || :
    exit 3
    ;;
  release)
    if [ -d "$_SL_LOCK" ]; then
      if ! rmdir -- "$_SL_LOCK" 2>/dev/null; then
        # Conteudo esperado dentro do lock dir: arquivo owner (FR-007a).
        rm -rf -- "$_SL_LOCK" 2>/dev/null \
          || { printf '%s: nao consegui remover %s\n' "$_SL_NAME" "$_SL_LOCK" >&2; exit 1; }
      fi
    fi
    exit 0
    ;;
  check)
    if [ -d "$_SL_LOCK" ]; then
      printf '%s: lock detido em %s\n' "$_SL_NAME" "$_SL_LOCK" >&2
      _sl_report_owner
      diag_emit error lock-contention "check: lock detido em $_SL_LOCK" \
        "aguarde o outro processo liberar, ou se tiver certeza que e stale: rmdir $_SL_LOCK" || :
      exit 3
    fi
    exit 0
    ;;
  check-execution-busy)
    # Materializa o estado nos dois backends (FR-010). Sob JSON devolve o
    # proprio path do state.json (caminho identico ao legado — FR-004);
    # sob SQLite devolve tmp legivel. Falha de materializacao (sqlite3
    # ausente, state.db corrompido) propaga via set -e (FR-012).
    _sf=$(state_read_materialize "$_SL_STATE_DIR")
    if [ ! -f "$_sf" ]; then
      exit 0
    fi
    if ! command -v jq >/dev/null 2>&1; then
      printf '%s: jq nao encontrado no PATH (necessario para check-execution-busy).\n' "$_SL_NAME" >&2
      exit 1
    fi
    # Path exibido nas mensagens: o armazenamento REAL do estado (nunca o
    # tmp materializado). Sob JSON permanece byte-identico ao legado.
    if [ -f "$_SL_STATE_DIR/state.db" ]; then
      _SL_STATE_SHOW="$_SL_STATE_DIR/state.db"
    else
      _SL_STATE_SHOW="$_SL_STATE"
    fi
    _status=$(jq -r '(.execution.status // .execucao.status) // ""' "$_sf" 2>/dev/null) || _status=""
    case "$_status" in
      em_andamento|aguardando_humano)
        printf '%s: ja existe execucao em status "%s" em %s.\n' "$_SL_NAME" "$_status" "$_SL_STATE_SHOW" >&2
        printf '       Use /agente-00c-resume para retomar ou /agente-00c-abort para abortar.\n' >&2
        exit 3
        ;;
      ""|abortada|concluida)
        exit 0
        ;;
      *)
        printf '%s: status desconhecido em %s: "%s"\n' "$_SL_NAME" "$_SL_STATE_SHOW" "$_status" >&2
        exit 1
        ;;
    esac
    ;;
  *)
    _sl_die_usage "subcomando desconhecido: $_SL_SUBCMD (use --help)"
    ;;
esac
