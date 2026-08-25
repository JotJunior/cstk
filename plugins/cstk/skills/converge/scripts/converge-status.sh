#!/bin/sh
# converge-status.sh — mecanica deterministica do ConvergenceStatusRecord
# (marcador append-only em <feature-dir>/converge-report.md) para a etapa
# `converge` da pipeline SDD oficial.
#
# Ref: docs/specs/pipeline-converge/contracts/converge-status-cli.md
#      docs/specs/pipeline-converge/data-model.md §Entity ConvergenceStatusRecord
#      docs/specs/pipeline-converge/plan.md §Revisao de seguranca (F1-F8)
#      docs/specs/pipeline-converge/tasks.md FASE 2 (tarefa 2.1)
#
# POSIX sh puro (`set -eu`), sem `jq` (Constitution II — mesma excecao do
# diretorio `plugins/cstk/skills/converge/scripts/` ja adotada por
# converge-tasks.sh/path-contains.sh). Zero `eval` sobre conteudo lido
# (SEC-1); valores sempre por argv, nunca interpolados em shell.
#
# Subcomandos:
#
#   converge-status.sh record --feature-dir DIR --outcome clean|actionable \
#                             --provenance gate|standalone --actionable N \
#                             [--note TEXT]
#       Apenda uma linha ConvergenceStatusRecord. Calcula `at` (UTC agora) e
#       `tasks-digest` a partir de <DIR>/tasks.md.
#
#   converge-status.sh latest --feature-dir DIR
#       Imprime a ultima linha de status do arquivo, literal.
#
#   converge-status.sh check --feature-dir DIR [--quiet]
#       Veredito consumido por execute-task/review-task/pipeline.sh/
#       orquestradores. Vocabulario de saida fechado: converged |
#       risk-accepted | "pending actionable=N" | stale | never |
#       not-applicable.
#
#   converge-status.sh accept-risk --feature-dir DIR --justificativa TEXT \
#                                 [--decisao-id dec-NNN]
#       Apenda outcome=risk-accepted com o digest corrente do tasks.md.
#       SEMPRE invocacao do OPERADOR (F8) — nenhum orquestrador autonomo
#       deve chamar este subcomando por conta propria.
#
#   converge-status.sh audit --specs-root DIR [--json]
#       Auditoria agregada (fecha CHK016 / SC-002 / SC-003): para cada
#       feature com backlog esgotado sob DIR, verifica se o ultimo registro
#       comprova convergencia (outcome=clean|risk-accepted com tasks-digest
#       batendo o atual). Exit 1 se houver ao menos uma nao-conforme.
#
# Convencoes gerais (contrato): dados em stdout, diagnostico em stderr.
# Exit: 0 sucesso/veredito positivo | 1 veredito negativo/erro geral |
#       2 uso incorreto (inclui violacao de contencao de path, F3) |
#       3 estado "nunca convergiu" (so em check/latest).

set -eu

_CS_NAME="converge-status"

_cs_usage() {
  cat <<'USAGE' >&2
Uso: converge-status.sh <subcomando> [flags]

Subcomandos:
  record       --feature-dir DIR --outcome clean|actionable \
               --provenance gate|standalone --actionable N [--note TEXT]
  latest       --feature-dir DIR
  check        --feature-dir DIR [--quiet]
  accept-risk  --feature-dir DIR --justificativa TEXT [--decisao-id dec-NNN]
  audit        --specs-root DIR [--json]

Exit: 0 sucesso/veredito positivo | 1 veredito negativo/erro geral |
      2 uso incorreto | 3 nunca convergiu (so em check/latest)
USAGE
}

_cs_die_usage() {
  printf '%s: %s\n' "$_CS_NAME" "$1" >&2
  exit 2
}

_cs_die_io() {
  printf '%s: %s\n' "$_CS_NAME" "$1" >&2
  exit 1
}

# ---------- Contencao de path (F3) — reusa path-contains.sh do mesmo dir ----------

# _cs_resolve_dir DIR -> imprime o path resolvido (absoluto, symlinks
# canonicalizados) em stdout se DIR esta contido na raiz do projeto-alvo
# (resolucao automatica de --root: .git/ -> docs/constitution.md -> abort).
# Retorna 1 em qualquer falha (fora da raiz, irresolvivel, path-contains.sh
# ausente) — caller MUST mapear para exit 2 (uso incorreto, sem escrita).
_cs_resolve_dir() {
  _d=$1
  _script_dir=$(cd -- "$(dirname -- "$0")" && pwd -P) || {
    printf '%s: nao foi possivel resolver o diretorio do proprio script\n' "$_CS_NAME" >&2
    return 1
  }
  _pc="${_script_dir}/path-contains.sh"
  if [ ! -x "$_pc" ]; then
    printf '%s: path-contains.sh ausente/nao-executavel: %s\n' "$_CS_NAME" "$_pc" >&2
    return 1
  fi
  if ! _resolved=$("$_pc" --path "$_d" 2>&1); then
    printf '%s: path fora da raiz do projeto-alvo ou irresolvivel (F3, blast radius): %s\n' "$_CS_NAME" "$_d" >&2
    printf '  diagnostico: %s\n' "$_resolved" >&2
    return 1
  fi
  printf '%s\n' "$_resolved"
}

# ---------- Rejeicao de metacaracteres do formato (F7) ----------

# _cs_reject_meta VALUE LABEL -> aborta (exit 2) se VALUE contem ';', '-->'
# ou newline. Valores vazios (flag nao passada) sao permitidos (opcionais).
_cs_reject_meta() {
  _val=$1
  _label=$2
  [ -n "$_val" ] || return 0
  case "$_val" in
    *';'*) _cs_die_usage "${_label} contem ';' (nao permitido — protege o formato do marcador)" ;;
  esac
  case "$_val" in
    *'-->'*) _cs_die_usage "${_label} contem '-->' (nao permitido — protege o formato do marcador)" ;;
  esac
  # Deteccao de newline embutida: "$(cmd)" sempre remove newlines finais
  # (POSIX), entao "_cs_nl=$(printf '\n')" resultaria em string VAZIA e
  # tornaria o case "*${_cs_nl}*" um match universal (bug: qualquer valor
  # seria rejeitado). `wc -l` conta newlines embutidas sem essa armadilha.
  _cs_nlcount=$(printf '%s' "$_val" | wc -l | tr -d '[:space:]')
  [ "$_cs_nlcount" = "0" ] || _cs_die_usage "${_label} contem newline (nao permitido)"
}

# ---------- Rejeicao de destino-symlink (F6) ----------

_cs_reject_symlink() {
  _f=$1
  if [ -L "$_f" ]; then
    _cs_die_usage "destino e symlink, recusado (F6): $_f"
  fi
}

# ---------- Digest do tasks.md (Decision 6) ----------

# _cs_tasks_digest FILE -> imprime 12 hex minusculos (sha256 do conteudo
# integral do arquivo). Hash proprio, sem acoplar a agente-00c-runtime/
# scripts/_hash.sh (mesmo padrao ja adotado por converge-tasks.sh
# _ct_sha256_12, mas operando direto sobre o arquivo em vez de uma string).
_cs_tasks_digest() {
  _f=$1
  _os=$(uname -s 2>/dev/null)
  case "$_os" in
    # MINGW*/MSYS*/CYGWIN* (Git Bash & cia no Windows) reusam o mesmo
    # sha256sum do Linux — presente e funcional nesses ambientes (issue
    # #157). Sem esse ramo, a ETAPA 7 da skill converge (gravar o
    # ConvergenceStatusRecord) era inexecutavel no Windows, sem workaround:
    # o marcador so pode ser escrito por este script.
    Linux|MINGW*|MSYS*|CYGWIN*)
      sha256sum -- "$_f" | awk '{print substr($1,1,12)}'
      ;;
    Darwin)
      shasum -a 256 -- "$_f" | awk '{print substr($1,1,12)}'
      ;;
    *)
      _cs_die_io "SO nao suportado para sha256: $_os (esperado Linux|Darwin|MINGW*|MSYS*|CYGWIN*)"
      ;;
  esac
}

# ---------- Escrita atomica append-only (F5) ----------

# _cs_append_line REPORT LINE -> apenda LINE (uma linha) ao final de
# REPORT via mktemp+mv (mesmo padrao de converge-tasks.sh append-phase /
# state-rw.sh _sr_atomic_write). Preserva integralmente o conteudo
# pre-existente; cria o arquivo se ausente.
_cs_append_line() {
  _report=$1
  _line=$2
  _dir=$(dirname -- "$_report")
  _tmp=$(mktemp -- "${_report}.XXXXXX") || _cs_die_io "mktemp falhou em $_dir"
  if [ -f "$_report" ]; then
    if ! cat -- "$_report" > "$_tmp" 2>/dev/null; then
      rm -f -- "$_tmp" 2>/dev/null || :
      _cs_die_io "falha ao ler $_report"
    fi
  fi
  if ! printf '%s\n' "$_line" >> "$_tmp"; then
    rm -f -- "$_tmp" 2>/dev/null || :
    _cs_die_io "falha ao escrever em arquivo temporario"
  fi
  if ! mv -f -- "$_tmp" "$_report"; then
    rm -f -- "$_tmp" 2>/dev/null || :
    _cs_die_io "mv atomico falhou: $_tmp -> $_report"
  fi
}

# ---------- Parse ancorado do marcador (F2) ----------

# _cs_latest_line REPORT -> imprime a ULTIMA linha que casa
# `^<!-- converge-status: .* -->$`. Exit 1 se arquivo ausente ou sem
# nenhum registro (toda prosa fora desse formato e ignorada).
_cs_latest_line() {
  _f=$1
  [ -f "$_f" ] || return 1
  _l=$(grep -E '^<!-- converge-status: .* -->$' -- "$_f" | tail -n 1)
  [ -n "$_l" ] || return 1
  printf '%s\n' "$_l"
}

# _cs_strip_marker LINE -> imprime o conteudo interno (entre
# "converge-status: " e " -->").
_cs_strip_marker() {
  printf '%s\n' "$1" | sed -e 's/^<!-- converge-status: //' -e 's/ -->$//'
}

# _cs_field INNER FIELD -> imprime o valor de FIELD (chave=valor,
# separados por "; "). Exit 1 se FIELD ausente. Split puramente textual
# (sem awk RS multi-char — nao portavel entre GNU/BSD awk): usa IFS=';'
# + trim do espaco separador de "; ", seguro porque record()/accept-risk()
# ja rejeitam ';' em qualquer valor de campo (F7) — nenhum campo pode
# conter o proprio separador.
_cs_field() {
  _inner=$1
  _field=$2
  _old_ifs=$IFS
  IFS=';'
  set -f
  # shellcheck disable=SC2086
  set -- $_inner
  IFS=$_old_ifs
  set +f
  for _kv in "$@"; do
    _kv=${_kv# }
    case "$_kv" in
      "${_field}="*)
        printf '%s\n' "${_kv#"${_field}="}"
        return 0
        ;;
    esac
  done
  return 1
}

# ---------- Veredito compartilhado por check/audit ----------

# _cs_tasks_has_lines FILE -> exit 0 se FILE existe e tem >=1 linha de
# tarefa (qualquer estado: [ ]/[~]/[x]/[!] — decisao 1.2, fecha CHK004).
_cs_tasks_has_lines() {
  _f=$1
  [ -f "$_f" ] || return 1
  grep -qE '^[[:space:]]*-[[:space:]]*\[[ x~!]\]' -- "$_f"
}

# _cs_tasks_all_done FILE -> exit 0 se nenhuma linha `- [ ]`/`- [~]`
# (pendente/em-andamento) resta — mesmo criterio de "backlog esgotado" do
# gate execute-task->converge.
_cs_tasks_all_done() {
  _f=$1
  ! grep -qE '^[[:space:]]*-[[:space:]]*\[[ ~]\]' -- "$_f"
}

# _cs_status_for_dir RESOLVED_DIR -> stdout: veredito (converged |
# risk-accepted | "pending actionable=N" | stale | never); exit 0/1/3.
# NAO decide not-applicable — caller confere _cs_tasks_has_lines antes.
_cs_status_for_dir() {
  _d=$1
  _tasks="${_d}/tasks.md"
  _report="${_d}/converge-report.md"
  if ! _line=$(_cs_latest_line "$_report"); then
    printf 'never\n'
    return 3
  fi
  _inner=$(_cs_strip_marker "$_line")
  if ! _outcome=$(_cs_field "$_inner" outcome); then
    printf 'never\n'
    return 3
  fi
  case "$_outcome" in
    actionable)
      if ! _n=$(_cs_field "$_inner" actionable); then
        _n='?'
      fi
      printf 'pending actionable=%s\n' "$_n"
      return 1
      ;;
    clean | risk-accepted)
      if ! _rec_digest=$(_cs_field "$_inner" tasks-digest); then
        printf 'never\n'
        return 3
      fi
      _cur_digest=$(_cs_tasks_digest "$_tasks")
      if [ "$_rec_digest" = "$_cur_digest" ]; then
        if [ "$_outcome" = clean ]; then
          printf 'converged\n'
        else
          printf 'risk-accepted\n'
        fi
        return 0
      fi
      printf 'stale\n'
      return 1
      ;;
    *)
      printf 'never\n'
      return 3
      ;;
  esac
}

# ---------- record ----------

_cs_cmd_record() {
  _dir=""
  _outcome=""
  _provenance=""
  _actionable=""
  _note=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --feature-dir)
        [ "$#" -ge 2 ] || _cs_die_usage "--feature-dir requer valor"
        _dir=$2
        shift 2
        ;;
      --outcome)
        [ "$#" -ge 2 ] || _cs_die_usage "--outcome requer valor"
        _outcome=$2
        shift 2
        ;;
      --provenance)
        [ "$#" -ge 2 ] || _cs_die_usage "--provenance requer valor"
        _provenance=$2
        shift 2
        ;;
      --actionable)
        [ "$#" -ge 2 ] || _cs_die_usage "--actionable requer valor"
        _actionable=$2
        shift 2
        ;;
      --note)
        [ "$#" -ge 2 ] || _cs_die_usage "--note requer valor"
        _note=$2
        shift 2
        ;;
      -h | --help)
        _cs_usage
        exit 0
        ;;
      *) _cs_die_usage "flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_dir" ] || _cs_die_usage "--feature-dir e obrigatorio"
  [ -n "$_outcome" ] || _cs_die_usage "--outcome e obrigatorio"
  [ -n "$_provenance" ] || _cs_die_usage "--provenance e obrigatorio"
  [ -n "$_actionable" ] || _cs_die_usage "--actionable e obrigatorio"
  case "$_outcome" in
    clean | actionable) : ;;
    *) _cs_die_usage "--outcome deve ser clean|actionable (risk-accepted so via accept-risk)" ;;
  esac
  case "$_provenance" in
    gate | standalone) : ;;
    *) _cs_die_usage "--provenance deve ser gate|standalone" ;;
  esac
  case "$_actionable" in
    '' | *[!0-9]*) _cs_die_usage "--actionable deve ser inteiro >= 0" ;;
  esac
  if [ "$_outcome" = clean ] && [ "$_actionable" -ne 0 ]; then
    _cs_die_usage "outcome=clean exige --actionable 0"
  fi
  if [ "$_outcome" = actionable ] && [ "$_actionable" -lt 1 ]; then
    _cs_die_usage "outcome=actionable exige --actionable >= 1"
  fi
  _cs_reject_meta "$_note" "--note"
  _rdir=$(_cs_resolve_dir "$_dir") || exit 2
  _tasks="${_rdir}/tasks.md"
  [ -f "$_tasks" ] || _cs_die_usage "tasks.md ausente: $_tasks"
  _report="${_rdir}/converge-report.md"
  _cs_reject_symlink "$_report"
  _at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  _digest=$(_cs_tasks_digest "$_tasks")
  _line="<!-- converge-status: outcome=${_outcome}; provenance=${_provenance}; at=${_at}; actionable=${_actionable}; tasks-digest=${_digest}"
  [ -n "$_note" ] && _line="${_line}; note=${_note}"
  _line="${_line} -->"
  _cs_append_line "$_report" "$_line"
}

# ---------- latest ----------

_cs_cmd_latest() {
  _dir=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --feature-dir)
        [ "$#" -ge 2 ] || _cs_die_usage "--feature-dir requer valor"
        _dir=$2
        shift 2
        ;;
      -h | --help)
        _cs_usage
        exit 0
        ;;
      *) _cs_die_usage "flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_dir" ] || _cs_die_usage "--feature-dir e obrigatorio"
  _rdir=$(_cs_resolve_dir "$_dir") || exit 2
  _report="${_rdir}/converge-report.md"
  if ! _line=$(_cs_latest_line "$_report"); then
    exit 1
  fi
  printf '%s\n' "$_line"
}

# ---------- check ----------

_cs_cmd_check() {
  _dir=""
  _quiet="no"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --feature-dir)
        [ "$#" -ge 2 ] || _cs_die_usage "--feature-dir requer valor"
        _dir=$2
        shift 2
        ;;
      --quiet)
        _quiet="yes"
        shift
        ;;
      -h | --help)
        _cs_usage
        exit 0
        ;;
      *) _cs_die_usage "flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_dir" ] || _cs_die_usage "--feature-dir e obrigatorio"
  _rdir=$(_cs_resolve_dir "$_dir") || exit 2
  _tasks="${_rdir}/tasks.md"
  if ! _cs_tasks_has_lines "$_tasks"; then
    [ "$_quiet" = yes ] || printf 'not-applicable\n'
    exit 0
  fi
  if _veredito=$(_cs_status_for_dir "$_rdir"); then
    _code=0
  else
    _code=$?
  fi
  [ "$_quiet" = yes ] || printf '%s\n' "$_veredito"
  exit "$_code"
}

# ---------- accept-risk ----------

_cs_cmd_accept_risk() {
  _dir=""
  _just=""
  _decid=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --feature-dir)
        [ "$#" -ge 2 ] || _cs_die_usage "--feature-dir requer valor"
        _dir=$2
        shift 2
        ;;
      --justificativa)
        [ "$#" -ge 2 ] || _cs_die_usage "--justificativa requer valor"
        _just=$2
        shift 2
        ;;
      --decisao-id)
        [ "$#" -ge 2 ] || _cs_die_usage "--decisao-id requer valor"
        _decid=$2
        shift 2
        ;;
      -h | --help)
        _cs_usage
        exit 0
        ;;
      *) _cs_die_usage "flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_dir" ] || _cs_die_usage "--feature-dir e obrigatorio"
  if [ -z "$_just" ] && [ -z "$_decid" ]; then
    _cs_die_usage "--justificativa ou --decisao-id e obrigatorio (aceite nunca mudo)"
  fi
  _cs_reject_meta "$_just" "--justificativa"
  _cs_reject_meta "$_decid" "--decisao-id"
  _rdir=$(_cs_resolve_dir "$_dir") || exit 2
  _tasks="${_rdir}/tasks.md"
  [ -f "$_tasks" ] || _cs_die_usage "tasks.md ausente: $_tasks"
  _report="${_rdir}/converge-report.md"
  _cs_reject_symlink "$_report"

  # actionable carregado do ultimo registro pendente (outcome=actionable),
  # se houver — preserva no aceite de risco quantos achados foram aceitos,
  # em vez de fabricar 0 quando de fato havia N pendentes (decisao de
  # design do implementador; contrato nao fixa este valor explicitamente).
  _prev_actionable=0
  if _prev_line=$(_cs_latest_line "$_report"); then
    _prev_inner=$(_cs_strip_marker "$_prev_line")
    if _prev_outcome=$(_cs_field "$_prev_inner" outcome) && [ "$_prev_outcome" = actionable ]; then
      if _pa=$(_cs_field "$_prev_inner" actionable); then
        case "$_pa" in
          '' | *[!0-9]*) _prev_actionable=0 ;;
          *) _prev_actionable=$_pa ;;
        esac
      fi
    fi
  fi

  _at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  _digest=$(_cs_tasks_digest "$_tasks")
  _line="<!-- converge-status: outcome=risk-accepted; provenance=standalone; at=${_at}; actionable=${_prev_actionable}; tasks-digest=${_digest}"
  [ -n "$_decid" ] && _line="${_line}; decision-id=${_decid}"
  [ -n "$_just" ] && _line="${_line}; note=${_just}"
  _line="${_line} -->"
  _cs_append_line "$_report" "$_line"
}

# ---------- audit ----------

_cs_cmd_audit() {
  _root=""
  _json="no"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --specs-root)
        [ "$#" -ge 2 ] || _cs_die_usage "--specs-root requer valor"
        _root=$2
        shift 2
        ;;
      --json)
        _json="yes"
        shift
        ;;
      -h | --help)
        _cs_usage
        exit 0
        ;;
      *) _cs_die_usage "flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_root" ] || _cs_die_usage "--specs-root e obrigatorio"
  [ -d "$_root" ] || _cs_die_usage "--specs-root nao existe ou nao e diretorio: $_root"
  _rroot=$(_cs_resolve_dir "$_root") || exit 2

  _conformant=0
  _nonconformant=0
  _nc_list=""
  _json_items=""

  for _feat_dir in "$_rroot"/*/; do
    [ -d "$_feat_dir" ] || continue
    _feat_dir=${_feat_dir%/}
    _feat=$(basename -- "$_feat_dir")
    _tasks="${_feat_dir}/tasks.md"
    _cs_tasks_has_lines "$_tasks" || continue
    _cs_tasks_all_done "$_tasks" || continue

    if _veredito=$(_cs_status_for_dir "$_feat_dir"); then
      _conformant=$((_conformant + 1))
    else
      _nonconformant=$((_nonconformant + 1))
      _nc_list="${_nc_list}${_feat}: ${_veredito}
"
      _json_items="${_json_items}{\"feature\":\"${_feat}\",\"veredito\":\"${_veredito}\"},"
    fi
  done

  if [ "$_json" = yes ]; then
    if [ -n "$_json_items" ]; then
      _json_items=${_json_items%,}
      printf '[%s]\n' "$_json_items"
    else
      printf '[]\n'
    fi
  else
    printf 'conformant=%s non-conformant=%s\n' "$_conformant" "$_nonconformant"
    [ -n "$_nc_list" ] && printf '%s' "$_nc_list"
  fi

  [ "$_nonconformant" -eq 0 ] || exit 1
  exit 0
}

# ---------- dispatch ----------

[ "$#" -ge 1 ] || {
  _cs_usage
  exit 2
}

_cs_cmd=$1
shift

case "$_cs_cmd" in
  record) _cs_cmd_record "$@" ;;
  latest) _cs_cmd_latest "$@" ;;
  check) _cs_cmd_check "$@" ;;
  accept-risk) _cs_cmd_accept_risk "$@" ;;
  audit) _cs_cmd_audit "$@" ;;
  -h | --help)
    _cs_usage
    exit 0
    ;;
  *) _cs_die_usage "subcomando desconhecido: $_cs_cmd" ;;
esac
