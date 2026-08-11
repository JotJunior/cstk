#!/bin/sh
# state-rounds.sh — primitiva POSIX de rotacao de estado terminal para round
# preservado (feature-reopen, FASE 2).
#
# Ref: docs/specs/feature-reopen/contracts/state-rounds.md
#      docs/specs/feature-reopen/research.md Decision 1, Decision 2, Decision 3
#      docs/specs/feature-reopen/data-model.md
#      docs/specs/feature-reopen/tasks.md FASE 2
#
# Nao decide nada: recebe ordem, executa de forma recuperavel e reporta.
# Toda politica (triagem, confirmacao humana) vive na camada acima
# (comando /feature-00c --reopen, fora deste script).
#
# Subcomandos:
#   next-label --state-dir DIR
#       Calcula o proximo label sem escrever nada. Uma linha em stdout.
#   rotate --state-dir DIR [--label LABEL] [--dry-run]
#       Move o estado transacional terminal para rounds/<label>/.
#       Idempotencia: journal pendente ⇒ recusa (exit 3), instrui recover.
#   recover --state-dir DIR [--dry-run]
#       Resolve rotacao interrompida. Idempotente (sem journal ⇒ no-op).
#   list --state-dir DIR
#       Lista os rounds preservados, ordem lexicografica crescente. Read-only.
#
# Exit codes (uniformes em todos os subcomandos):
#   0  sucesso
#   1  erro generico (FS, sqlite, integridade)
#   2  uso incorreto (flag/subcomando invalido, obrigatorio ausente)
#   3  pre-condicao nao satisfeita (sem estado a rotacionar; rotacao pendente)
#
# Conformidade obrigatoria (Constitution Principio II, NON-NEGOTIABLE):
#   #!/bin/sh + set -eu; sem arrays, [[ ]], $'...', <<<, local, function.
#   Sem GNU-only (sed -i sem sufixo, stat GNU, readlink -f). Alvo real:
#   macOS/zsh (dev) e Ubuntu (CI).
#   sqlite3 e jq sao dependencia OBRIGATORIA aqui — carve-out do amendment
#   1.3.0 do Principio II (camada de estado transacional).

set -eu

_SR_NAME="state-rounds"
_SR_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

# shellcheck source=./_diag.sh
. "$_SR_DIR/_diag.sh"
# shellcheck source=./_state-db.sh
. "$_SR_DIR/_state-db.sh"
# shellcheck source=./_state-read.sh
. "$_SR_DIR/_state-read.sh"
trap state_read_cleanup EXIT INT TERM

_sr_die() {
  printf '%s: %s\n' "$_SR_NAME" "$1" >&2
  exit "${2:-1}"
}

_sr_die_usage() {
  printf '%s: %s\n' "$_SR_NAME" "$1" >&2
  exit 2
}

_sr_print_help() {
  cat >&2 <<'HELP'
state-rounds.sh — primitiva de rotacao de estado terminal (feature-reopen).

USO:
  state-rounds.sh next-label --state-dir DIR
  state-rounds.sh rotate --state-dir DIR [--label LABEL] [--dry-run]
  state-rounds.sh recover --state-dir DIR [--dry-run]
  state-rounds.sh list --state-dir DIR

EXIT:
  0 sucesso
  1 erro generico (FS, sqlite, integridade)
  2 uso incorreto
  3 pre-condicao nao satisfeita (sem estado; rotacao pendente)
HELP
}

# ---------------------------------------------------------------------------
# _sr_is_label_syntax_valid LABEL -> exit 0 se casa ^r[0-9]{2,}$, 1 senao.
# ---------------------------------------------------------------------------
_sr_is_label_syntax_valid() {
  _sllv_l="$1"
  case "$_sllv_l" in
    r[0-9][0-9]*) ;;
    *) return 1 ;;
  esac
  case "${_sllv_l#r}" in
    *[!0-9]*) return 1 ;;
  esac
  return 0
}

# ---------------------------------------------------------------------------
# _sr_next_label ROUNDS_DIR -> stdout: proximo label. Exit 1 se ROUNDS_DIR
# existe mas e ilegivel (ls falha por permissao). rounds/ ausente/vazio => r01.
# ---------------------------------------------------------------------------
_sr_next_label() {
  _snl_dir="$1"
  if [ ! -d "$_snl_dir" ]; then
    printf 'r01\n'
    return 0
  fi
  _snl_listing=$(ls -1 -- "$_snl_dir" 2>&1) || {
    printf '%s\n' "$_snl_listing" >&2
    return 1
  }
  _snl_max=0
  _snl_found=0
  for _snl_entry in $_snl_listing; do
    _sr_is_label_syntax_valid "$_snl_entry" || continue
    [ -d "$_snl_dir/$_snl_entry" ] || continue
    _snl_num=${_snl_entry#r}
    # remove zeros a esquerda para comparacao numerica segura (evita
    # interpretacao octal por `[ ]`/aritmetica com zero-padding, ex.: "08").
    _snl_num_noz=$(printf '%s' "$_snl_num" | sed 's/^0*//')
    [ -n "$_snl_num_noz" ] || _snl_num_noz=0
    _snl_found=1
    if [ "$_snl_num_noz" -gt "$_snl_max" ]; then
      _snl_max=$_snl_num_noz
    fi
  done
  if [ "$_snl_found" = 0 ]; then
    printf 'r01\n'
    return 0
  fi
  _snl_next=$((_snl_max + 1))
  printf 'r%02d\n' "$_snl_next"
  return 0
}

# ---------------------------------------------------------------------------
# _sr_write_journal PATH LABEL BACKEND FILES_CSV PHASE STARTED_AT
# Sobrescreve o journal inteiro (nao e append) -- write simples, nao atomico
# (arquivo pequeno, sob lock, sem consumidor concorrente legitimo).
# ---------------------------------------------------------------------------
_sr_write_journal() {
  _swj_path="$1"; _swj_label="$2"; _swj_backend="$3"
  _swj_files="$4"; _swj_phase="$5"; _swj_started="$6"
  {
    printf 'label=%s\n' "$_swj_label"
    printf 'backend=%s\n' "$_swj_backend"
    printf 'files=%s\n' "$_swj_files"
    printf 'staging=rounds/.%s.staging\n' "$_swj_label"
    printf 'phase=%s\n' "$_swj_phase"
    printf 'started_at=%s\n' "$_swj_started"
  } > "$_swj_path" 2>/dev/null || return 1
  return 0
}

# ---------------------------------------------------------------------------
# _sr_journal_field PATH KEY -> stdout: valor (primeira ocorrencia) ou vazio.
# Parser linha-a-linha proprio (regra J1) -- NUNCA `.`/`source`/`eval`.
# ---------------------------------------------------------------------------
_sr_journal_field() {
  sed -n "s/^$2=\\(.*\\)\$/\\1/p" "$1" 2>/dev/null | head -n 1
}

# ---------------------------------------------------------------------------
# _sr_staging_complete STAGING_DIR FILES_CSV -> exit 0 se todos os nomes de
# FILES_CSV existem em STAGING_DIR (via [ -f ]).
# ---------------------------------------------------------------------------
_sr_staging_complete() {
  _ssc_staging="$1"
  _ssc_files="$2"
  [ -d "$_ssc_staging" ] || return 1
  _ssc_saved_ifs=$IFS
  IFS=','
  for _ssc_f in $_ssc_files; do
    IFS="$_ssc_saved_ifs"
    [ -n "$_ssc_f" ] || continue
    if [ ! -f "$_ssc_staging/$_ssc_f" ]; then
      IFS="$_ssc_saved_ifs"
      return 1
    fi
    IFS=','
  done
  IFS="$_ssc_saved_ifs"
  return 0
}

# ---------------------------------------------------------------------------
# _sr_read_meta STATE_DIR -> stdout: "<execution_id>|<status>" lido via
# materializacao (funciona nos dois backends). "unknown|unknown" em qualquer
# falha (jq ausente, materializacao falha, JSON ilegivel) -- NUNCA aborta o
# caller; quem quiser tratar "ilegivel" como condicao distinta confere o
# valor de retorno (1 em falha de materializacao/parse).
# ---------------------------------------------------------------------------
_sr_read_meta() {
  _srm_dir="$1"
  if ! command -v jq >/dev/null 2>&1; then
    printf 'unknown|unknown\n'
    return 1
  fi
  _srm_file="$_srm_dir/state.json"
  if [ -f "$_srm_dir/state.db" ]; then
    _srm_tmp=$(state_read_materialize "$_srm_dir") || {
      printf 'unknown|unknown\n'
      return 1
    }
    _srm_file="$_srm_tmp"
  fi
  [ -f "$_srm_file" ] || {
    printf 'unknown|unknown\n'
    return 1
  }
  _srm_id=$(jq -r '.execution.id // "unknown"' "$_srm_file" 2>/dev/null) || {
    printf 'unknown|unknown\n'
    return 1
  }
  _srm_status=$(jq -r '.execution.status // "unknown"' "$_srm_file" 2>/dev/null) || {
    printf 'unknown|unknown\n'
    return 1
  }
  printf '%s|%s\n' "$_srm_id" "$_srm_status"
  return 0
}

if [ "$#" -lt 1 ]; then
  _sr_print_help
  exit 2
fi

_SR_SUBCMD=$1
shift

case "$_SR_SUBCMD" in
  -h|--help|help) _sr_print_help; exit 0 ;;
esac

_SR_STATE_DIR=""
_SR_LABEL=""
_SR_DRY_RUN=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --state-dir)
      [ "$#" -ge 2 ] || _sr_die_usage "--state-dir exige valor"
      _SR_STATE_DIR=$2; shift 2 ;;
    --label)
      [ "$#" -ge 2 ] || _sr_die_usage "--label exige valor"
      _SR_LABEL=$2; shift 2 ;;
    --dry-run) _SR_DRY_RUN=1; shift ;;
    *) _sr_die_usage "flag desconhecida: $1" ;;
  esac
done
[ -n "$_SR_STATE_DIR" ] || _sr_die_usage "--state-dir obrigatorio"
if [ "$_SR_SUBCMD" != "rotate" ] && [ -n "$_SR_LABEL" ]; then
  _sr_die_usage "--label so e valido com rotate"
fi
if [ "$_SR_SUBCMD" != "rotate" ] && [ "$_SR_SUBCMD" != "recover" ] && [ "$_SR_DRY_RUN" = 1 ]; then
  _sr_die_usage "--dry-run so e valido com rotate/recover"
fi

case "$_SR_SUBCMD" in
  next-label|rotate|recover|list) ;;
  *) _sr_die_usage "subcomando desconhecido: $_SR_SUBCMD (use --help)" ;;
esac

_SR_ROUNDS="$_SR_STATE_DIR/rounds"

# =============================================================================
# next-label
# =============================================================================
if [ "$_SR_SUBCMD" = "next-label" ]; then
  _SR_LBL=$(_sr_next_label "$_SR_ROUNDS") || _sr_die "rounds/ ilegivel: $_SR_ROUNDS" 1
  printf '%s\n' "$_SR_LBL"
  exit 0
fi

# =============================================================================
# list
# =============================================================================
if [ "$_SR_SUBCMD" = "list" ]; then
  [ -d "$_SR_ROUNDS" ] || exit 0
  _SL_LISTING=$(ls -1 -- "$_SR_ROUNDS" 2>/dev/null) || _SL_LISTING=""
  _SL_ANY_ILLEGIBLE=0
  for _sl_entry in $_SL_LISTING; do
    _sr_is_label_syntax_valid "$_sl_entry" || continue
    [ -d "$_SR_ROUNDS/$_sl_entry" ] || continue
    _sl_round_dir="$_SR_ROUNDS/$_sl_entry"
    if [ -f "$_sl_round_dir/state.db" ]; then
      _sl_backend="sqlite"; _sl_file="state.db"
    elif [ -f "$_sl_round_dir/state.json" ]; then
      _sl_backend="json"; _sl_file="state.json"
    else
      printf '%s|unknown|-|unknown|unknown|unknown\n' "$_sl_entry"
      _SL_ANY_ILLEGIBLE=1
      continue
    fi
    _sl_meta=$(_sr_read_meta "$_sl_round_dir") || _SL_ANY_ILLEGIBLE=1
    _sl_id=${_sl_meta%%|*}
    _sl_status=${_sl_meta#*|}
    _sl_finished="unknown"
    if command -v jq >/dev/null 2>&1; then
      _sl_meta_file="$_sl_round_dir/state.json"
      if [ "$_sl_backend" = "sqlite" ]; then
        _sl_meta_tmp=$(state_read_materialize "$_sl_round_dir" 2>/dev/null) && _sl_meta_file="$_sl_meta_tmp"
      fi
      [ -f "$_sl_meta_file" ] && _sl_finished=$(jq -r '.execution.finished_at // "unknown"' "$_sl_meta_file" 2>/dev/null) || :
      [ -n "$_sl_finished" ] || _sl_finished="unknown"
    fi
    printf '%s|%s|%s|%s|%s|%s\n' "$_sl_entry" "$_sl_backend" "$_sl_file" "$_sl_id" "$_sl_status" "$_sl_finished"
  done
  [ "$_SL_ANY_ILLEGIBLE" = 0 ] || exit 1
  exit 0
fi

# =============================================================================
# recover
# =============================================================================
if [ "$_SR_SUBCMD" = "recover" ]; then
  _RC_JOURNAL="$_SR_ROUNDS/.rotate-journal"

  if [ ! -f "$_RC_JOURNAL" ]; then
    printf 'RECOVER|none|-\n'
    exit 0
  fi

  _rc_label=$(_sr_journal_field "$_RC_JOURNAL" label)
  _rc_backend=$(_sr_journal_field "$_RC_JOURNAL" backend)
  _rc_files=$(_sr_journal_field "$_RC_JOURNAL" files)
  _rc_phase=$(_sr_journal_field "$_RC_JOURNAL" phase)

  # J3: label
  _sr_is_label_syntax_valid "$_rc_label" \
    || _sr_die "journal malformado: label invalido '$_rc_label'" 1
  # J7: enums
  case "$_rc_backend" in
    json|sqlite) ;;
    *) _sr_die "journal malformado: backend invalido '$_rc_backend'" 1 ;;
  esac
  case "$_rc_phase" in
    staged|moving) ;;
    *) _sr_die "journal malformado: phase invalido '$_rc_phase'" 1 ;;
  esac
  # J4: files fechado a {state.json, state.json.sha256, state.db}
  [ -n "$_rc_files" ] || _sr_die "journal malformado: files vazio" 1
  _rc_saved_ifs=$IFS
  IFS=','
  for _rc_f in $_rc_files; do
    IFS="$_rc_saved_ifs"
    case "$_rc_f" in
      state.json|state.json.sha256|state.db) ;;
      *) _sr_die "journal malformado: arquivo fora do fechado: '$_rc_f'" 1 ;;
    esac
    IFS=','
  done
  IFS="$_rc_saved_ifs"

  # J5: staging SEMPRE derivado do label (valor do journal so seria conferencia)
  _rc_staging="$_SR_ROUNDS/.$_rc_label.staging"
  _rc_target="$_SR_ROUNDS/$_rc_label"

  # J6: staging nao-symlink
  if [ -e "$_rc_staging" ] && [ -L "$_rc_staging" ]; then
    _sr_die "journal malformado: staging e symlink: $_rc_staging" 1
  fi

  if [ -d "$_rc_target" ]; then
    _rc_action="forward"
  elif _sr_staging_complete "$_rc_staging" "$_rc_files"; then
    _rc_action="forward"
  else
    _rc_action="rollback"
  fi

  if [ "$_SR_DRY_RUN" = 1 ]; then
    printf 'RECOVER|%s|%s\n' "$_rc_action" "$_rc_label"
    exit 0
  fi

  case "$_rc_action" in
    forward)
      if [ -d "$_rc_target" ]; then
        rm -f -- "$_RC_JOURNAL" 2>/dev/null || _sr_die "recover: nao consegui remover journal orfao" 1
      else
        mv -- "$_rc_staging" "$_rc_target" 2>/dev/null \
          || _sr_die "recover: mv (roll-forward) falhou: $_rc_staging -> $_rc_target" 1
        chmod 700 -- "$_rc_target" 2>/dev/null || :
        rm -f -- "$_RC_JOURNAL" 2>/dev/null || :
      fi
      printf 'RECOVER|forward|%s\n' "$_rc_label"
      ;;
    rollback)
      if [ -d "$_rc_staging" ]; then
        _rc_saved_ifs=$IFS
        IFS=','
        for _rc_f in $_rc_files; do
          IFS="$_rc_saved_ifs"
          if [ -f "$_rc_staging/$_rc_f" ]; then
            mv -- "$_rc_staging/$_rc_f" "$_SR_STATE_DIR/$_rc_f" 2>/dev/null \
              || _sr_die "recover: mv (roll-back) falhou: $_rc_f" 1
          fi
          IFS=','
        done
        IFS="$_rc_saved_ifs"
        rmdir -- "$_rc_staging" 2>/dev/null || rm -rf -- "$_rc_staging" 2>/dev/null || :
      fi
      rm -f -- "$_RC_JOURNAL" 2>/dev/null || :
      printf 'RECOVER|rollback|%s\n' "$_rc_label"
      ;;
  esac
  exit 0
fi

# =============================================================================
# rotate
# =============================================================================
# G4 (pre): state-dir nao-symlink
[ ! -L "$_SR_STATE_DIR" ] || _sr_die "state-dir e symlink: $_SR_STATE_DIR" 1
if [ -e "$_SR_ROUNDS" ]; then
  [ ! -L "$_SR_ROUNDS" ] || _sr_die "rounds/ e symlink: $_SR_ROUNDS" 1
fi

# Pre-condicao 1: estado presente na raiz
if [ ! -f "$_SR_STATE_DIR/state.json" ] && [ ! -f "$_SR_STATE_DIR/state.db" ]; then
  _sr_die "sem estado transacional em $_SR_STATE_DIR — nada a rotacionar" 3
fi

# Pre-condicao 2: ausencia de journal pendente
if [ -f "$_SR_ROUNDS/.rotate-journal" ]; then
  diag_emit error rotation-journal-pending \
    "rotate: rotacao pendente detectada em $_SR_ROUNDS/.rotate-journal" \
    "rode: state-rounds.sh recover --state-dir $_SR_STATE_DIR" || :
  _sr_die "rotacao pendente detectada — rode: state-rounds.sh recover --state-dir $_SR_STATE_DIR" 3
fi

# Pre-condicao 3: status terminal, delegado a state-lock.sh check-execution-busy
_RT_BUSY_RC=0
"$_SR_DIR/state-lock.sh" check-execution-busy --state-dir "$_SR_STATE_DIR" 1>&2 || _RT_BUSY_RC=$?
case "$_RT_BUSY_RC" in
  0) ;;
  3) exit 3 ;;
  *) _sr_die "check-execution-busy falhou (exit $_RT_BUSY_RC)" 1 ;;
esac

# backend + arquivos transacionais (Conjunto movido por backend, contrato)
if [ -f "$_SR_STATE_DIR/state.db" ]; then
  _RT_BACKEND="sqlite"
  _RT_STATE_FILE="state.db"
  _RT_FILES_CSV="state.db"
else
  _RT_BACKEND="json"
  _RT_STATE_FILE="state.json"
  if [ -f "$_SR_STATE_DIR/state.json.sha256" ]; then
    _RT_FILES_CSV="state.json,state.json.sha256"
  else
    _RT_FILES_CSV="state.json"
  fi
fi

# Pre-condicao 4: integrity_check sob sqlite (ANTES de qualquer escrita)
if [ "$_RT_BACKEND" = "sqlite" ]; then
  command -v sqlite3 >/dev/null 2>&1 || _sr_die "sqlite3 ausente no PATH (dependencia obrigatoria sob backend sqlite)" 1
  _RT_IC=$(_state_db_exec "$_SR_STATE_DIR/state.db" "PRAGMA integrity_check;" 2>&1) \
    || _sr_die "PRAGMA integrity_check falhou: $_RT_IC" 1
  if [ "$_RT_IC" != "ok" ]; then
    diag_emit error integrity-check-failed \
      "rotate: integrity_check divergente antes da rotacao (nada movido): $_RT_IC" \
      "restaure state.db a partir de state-history/ ou investigue corrupcao" || :
    _sr_die "integrity_check divergente (estado nao movido): $_RT_IC" 1
  fi
fi

# a. label
if [ -n "$_SR_LABEL" ]; then
  _sr_is_label_syntax_valid "$_SR_LABEL" \
    || _sr_die_usage "--label fora do padrao ^r[0-9]{2,}\$: $_SR_LABEL"
  [ ! -e "$_SR_ROUNDS/$_SR_LABEL" ] || _sr_die_usage "--label ja existente: $_SR_LABEL"
  _RT_LABEL="$_SR_LABEL"
else
  _RT_LABEL=$(_sr_next_label "$_SR_ROUNDS") || _sr_die "rounds/ ilegivel: $_SR_ROUNDS" 1
fi

_RT_STAGING="$_SR_ROUNDS/.$_RT_LABEL.staging"
_RT_TARGET="$_SR_ROUNDS/$_RT_LABEL"

[ ! -e "$_RT_TARGET" ] || _sr_die_usage "round ja existe: $_RT_TARGET"
if [ -e "$_RT_STAGING" ]; then
  [ ! -L "$_RT_STAGING" ] || _sr_die "staging preexistente e symlink: $_RT_STAGING" 1
fi

# Metadados para a linha de resposta, capturados ANTES de qualquer mutacao
# (funciona nos dois backends via materializacao).
_RT_META=$(_sr_read_meta "$_SR_STATE_DIR") || :
_RT_EXEC_ID=${_RT_META%%|*}
_RT_EXEC_STATUS=${_RT_META#*|}

if [ "$_SR_DRY_RUN" = 1 ]; then
  printf 'ROUND|%s|%s|%s|%s|%s\n' "$_RT_LABEL" "$_RT_BACKEND" "$_RT_STATE_FILE" "$_RT_EXEC_ID" "$_RT_EXEC_STATUS"
  exit 0
fi

# b1. G6 — assere lock detido (primitiva standalone, invocavel diretamente)
[ -d "$_SR_STATE_DIR/.lock" ] \
  || _sr_die "lock nao detido — rotate exige lock adquirido via 'state-lock.sh acquire --state-dir $_SR_STATE_DIR' antes de invocar" 3

# c/c1. checkpoint + barreira do WAL (sqlite apenas) — G1, G2
if [ "$_RT_BACKEND" = "sqlite" ]; then
  _RT_CK=$(_state_db_exec "$_SR_STATE_DIR/state.db" "PRAGMA wal_checkpoint(TRUNCATE);" 2>&1) \
    || _sr_die "wal_checkpoint falhou: $_RT_CK" 1
  _RT_CK_BUSY=$(printf '%s' "$_RT_CK" | head -n 1 | cut -d'|' -f1)
  if [ "$_RT_CK_BUSY" != "0" ]; then
    diag_emit error wal-checkpoint-busy \
      "rotate: wal_checkpoint(TRUNCATE) nao completou (busy=$_RT_CK_BUSY): $_RT_CK" \
      "aguarde leitores/escritores concorrentes liberarem o WAL e repita o rotate" || :
    _sr_die "wal_checkpoint nao completou (busy=$_RT_CK_BUSY) — commits em risco, abortando: $_RT_CK" 1
  fi
  if [ -f "$_SR_STATE_DIR/state.db-wal" ]; then
    _RT_WAL_SIZE=$(wc -c < "$_SR_STATE_DIR/state.db-wal" 2>/dev/null | tr -d ' ')
    [ -n "$_RT_WAL_SIZE" ] || _RT_WAL_SIZE=0
    if [ "$_RT_WAL_SIZE" != "0" ]; then
      diag_emit error wal-not-empty-after-checkpoint \
        "rotate: state.db-wal com $_RT_WAL_SIZE bytes apos checkpoint validado — barreira G2 recusa apagar" \
        "investigue por que o WAL nao esvaziou apesar de busy=0; nao prossiga sem entender" || :
      _sr_die "state.db-wal nao vazio apos checkpoint ($_RT_WAL_SIZE bytes) — abortando" 1
    fi
  fi
fi

# d. escreve journal (phase=staged)
mkdir -p -- "$_SR_ROUNDS" 2>/dev/null || _sr_die "nao consegui criar $_SR_ROUNDS" 1
_RT_JOURNAL="$_SR_ROUNDS/.rotate-journal"
_RT_STARTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
_sr_write_journal "$_RT_JOURNAL" "$_RT_LABEL" "$_RT_BACKEND" "$_RT_FILES_CSV" "staged" "$_RT_STARTED_AT" \
  || _sr_die "nao consegui escrever journal $_RT_JOURNAL" 1

# e. mkdir staging — G7 (chmod 700 best-effort)
mkdir -- "$_RT_STAGING" 2>/dev/null || _sr_die "nao consegui criar staging $_RT_STAGING" 1
chmod 700 -- "$_RT_STAGING" 2>/dev/null || :

# f. mv -- cada arquivo transacional -> staging (G5: -- em todo mv/rm/mkdir)
_RT_SAVED_IFS=$IFS
IFS=','
for _rt_f in $_RT_FILES_CSV; do
  IFS="$_RT_SAVED_IFS"
  mv -- "$_SR_STATE_DIR/$_rt_f" "$_RT_STAGING/$_rt_f" 2>/dev/null \
    || _sr_die "mv falhou: $_rt_f -> $_RT_STAGING" 1
  IFS=','
done
IFS="$_RT_SAVED_IFS"
_sr_write_journal "$_RT_JOURNAL" "$_RT_LABEL" "$_RT_BACKEND" "$_RT_FILES_CSV" "moving" "$_RT_STARTED_AT" \
  || _sr_die "nao consegui atualizar journal $_RT_JOURNAL (phase=moving)" 1

# g. sqlite: remove sidecars residuais (T-06 — round jamais contem -wal/-shm)
if [ "$_RT_BACKEND" = "sqlite" ]; then
  rm -f -- "$_SR_STATE_DIR/state.db-wal" "$_SR_STATE_DIR/state.db-shm" 2>/dev/null || :
fi

# h. re-ASSERT nao-symlink do alvo, imediatamente antes do commit
[ ! -L "$_RT_STAGING" ] || _sr_die "staging tornou-se symlink antes do commit: $_RT_STAGING" 1
[ ! -e "$_RT_TARGET" ] || _sr_die "round ja existe (corrida concorrente?): $_RT_TARGET" 1

# h1. COMMIT: rename atomico
mv -- "$_RT_STAGING" "$_RT_TARGET" 2>/dev/null \
  || _sr_die "commit falhou: mv $_RT_STAGING -> $_RT_TARGET" 1
chmod 700 -- "$_RT_TARGET" 2>/dev/null || :

# i. sqlite: integrity_check na copia dentro do round, apos commit — G3
if [ "$_RT_BACKEND" = "sqlite" ]; then
  if _RT_IC2=$(_state_db_exec "$_RT_TARGET/state.db" "PRAGMA integrity_check;" 2>&1); then
    if [ "$_RT_IC2" != "ok" ]; then
      diag_emit error integrity-check-failed \
        "rotate: integrity_check da copia em $_RT_TARGET divergente apos commit: $_RT_IC2" \
        "commit ja ocorreu (rename atomico); journal preservado — rode 'state-rounds.sh recover' para limpa-lo apos investigar" || :
      printf '%s: AVISO: integrity_check da copia em %s divergente apos commit: %s\n' "$_SR_NAME" "$_RT_TARGET" "$_RT_IC2" >&2
      exit 1
    fi
  else
    printf '%s: AVISO: nao consegui rodar integrity_check da copia em %s\n' "$_SR_NAME" "$_RT_TARGET" >&2
    exit 1
  fi
  # T-06: uma conexao sqlite3 em banco WAL recria -shm (e possivelmente um
  # -wal vazio) so por abrir/ler, mesmo em PRAGMA read-only como
  # integrity_check -- efeito colateral do proprio check acima, nao do
  # commit. Round preservado MUST conter so state.db (Conjunto movido por
  # backend, contrato); remove os sidecars reintroduzidos pela verificacao.
  rm -f -- "$_RT_TARGET/state.db-wal" "$_RT_TARGET/state.db-shm" 2>/dev/null || :
fi

# j. rm journal (so depois do integrity_check confirmar)
rm -f -- "$_RT_JOURNAL" 2>/dev/null || :

printf 'ROUND|%s|%s|%s|%s|%s\n' "$_RT_LABEL" "$_RT_BACKEND" "$_RT_STATE_FILE" "$_RT_EXEC_ID" "$_RT_EXEC_STATUS"
exit 0
