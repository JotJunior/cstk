#!/bin/sh
# commit-mode.sh — helper POSIX para o modo opt-in atomic-commit.
#
# Feature: atomic-commit-pr
# Ref:     docs/specs/atomic-commit-pr/contracts/commit-mode.md
#          docs/specs/atomic-commit-pr/spec.md §FR-002..011
#
# Subcomandos:
#   is-enabled   --state-dir DIR
#   set-enabled  --state-dir DIR --value <true|false>
#   guard-branch --state-dir DIR --projeto-alvo-path PATH
#   stage-message --feature NAME --stage STAGE
#   task-message  --feature NAME --task-ids "ID[,ID...]" [--brief TEXT]
#   finalize     --state-dir DIR --projeto-alvo-path PATH [--session NAME]
#                [--title T] [--body B]
#
# Exit codes globais:
#   0  sucesso / caso tratado (inclui skips nao-fatais)
#   1  erro generico (ex: git ausente, write falhou)
#   2  erro de uso (flag faltando ou valor invalido)
#   3  recusa de guard (branch default ou modo desabilitado — nao-fatal)
#
# POSIX sh puro. Zero deps obrigatorias.
# Deps opcionais: jq (state read/write), git (branch/commit), gh (PR).
# Ausencia de dep opcional => skip com status gravado, NUNCA aborta a onda.

set -eu

_CM_NAME="commit-mode"

# ---------- helpers de log ----------

# Tenta sourcear _log.sh do mesmo dir; fallback para printf simples.
_cm_selfdir() { cd -- "$(dirname -- "$0")" && pwd; }
_cm_log_sourced=0
if _cm_sd=$(_cm_selfdir 2>/dev/null) && [ -f "$_cm_sd/_log.sh" ]; then
  # shellcheck disable=SC1090
  . "$_cm_sd/_log.sh" && _cm_log_sourced=1
fi

_cm_err() {
  if [ "$_cm_log_sourced" = 1 ]; then
    log_err "$_CM_NAME: $*"
  else
    printf '%s: %s\n' "$_CM_NAME" "$*" >&2
  fi
}

_cm_out() {
  if [ "$_cm_log_sourced" = 1 ]; then
    log_out "$_CM_NAME: $*"
  else
    printf '%s: %s\n' "$_CM_NAME" "$*"
  fi
}

_cm_die() {
  _cm_err "$1"
  exit "${2:-1}"
}

_cm_die_usage() {
  _cm_err "$1"
  exit 2
}

# ---------- helpers internos ----------

# Localiza state-rw.sh no mesmo diretorio que este script.
_cm_rw() {
  _cm_sd=$(_cm_selfdir 2>/dev/null) || _cm_die "nao foi possivel resolver selfdir" 1
  printf '%s/state-rw.sh' "$_cm_sd"
}

# Verifica se jq esta disponivel.
_cm_require_jq() {
  command -v jq >/dev/null 2>&1 || _cm_die "jq nao encontrado no PATH" 1
}

# Verifica se git esta disponivel.
_cm_require_git() {
  command -v git >/dev/null 2>&1 || return 1
  return 0
}

# ---------- subcomando: is-enabled ----------
# is-enabled --state-dir DIR
# stdout: "true" ou "false"
# exit: 0 sempre (campo ausente => false)
_cm_cmd_is_enabled() {
  _sdir=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sdir=$2; shift 2 ;;
      *) _cm_die_usage "is-enabled: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sdir" ] || _cm_die_usage "is-enabled: --state-dir obrigatorio"

  _rw=$(_cm_rw)
  [ -f "$_rw" ] || _cm_die "state-rw.sh nao encontrado: $_rw" 1

  # Leitura via state-rw.sh get; campo ausente => jq retorna null => false
  _val=$(sh "$_rw" get --state-dir "$_sdir" \
    --field '.atomic_commit_enabled // false' 2>/dev/null) || _val="false"

  case "$_val" in
    true)  printf 'true\n';  return 0 ;;
    false) printf 'false\n'; return 0 ;;
    *)     printf 'false\n'; return 0 ;;  # defensivo: qualquer outro valor => false
  esac
}

# ---------- subcomando: set-enabled ----------
# set-enabled --state-dir DIR --value <true|false>
# exit: 0 sucesso, 1 write falhou, 2 uso incorreto
_cm_cmd_set_enabled() {
  _sdir=""
  _value=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sdir=$2;  shift 2 ;;
      --value)     _value=$2; shift 2 ;;
      *) _cm_die_usage "set-enabled: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sdir" ]  || _cm_die_usage "set-enabled: --state-dir obrigatorio"
  [ -n "$_value" ] || _cm_die_usage "set-enabled: --value obrigatorio"

  case "$_value" in
    true|false) ;;
    *) _cm_die_usage "set-enabled: --value aceita apenas 'true' ou 'false'" ;;
  esac

  _rw=$(_cm_rw)
  [ -f "$_rw" ] || _cm_die "state-rw.sh nao encontrado: $_rw" 1

  sh "$_rw" set --state-dir "$_sdir" \
    --field '.atomic_commit_enabled' \
    --value "$_value" || _cm_die "set-enabled: falha ao gravar state" 1

  return 0
}

# ---------- subcomando: guard-branch ----------
# guard-branch --state-dir DIR --projeto-alvo-path PATH
# stdout: nome do branch atual
# exit: 0 (nao-default), 3 (default — nao-fatal), 1 (git ausente/nao-repo)
_cm_cmd_guard_branch() {
  _sdir=""
  _pap=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)          _sdir=$2; shift 2 ;;
      --projeto-alvo-path)  _pap=$2;  shift 2 ;;
      *) _cm_die_usage "guard-branch: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sdir" ] || _cm_die_usage "guard-branch: --state-dir obrigatorio"
  [ -n "$_pap" ]  || _cm_die_usage "guard-branch: --projeto-alvo-path obrigatorio"

  # git obrigatorio para esta operacao
  if ! _cm_require_git; then
    _cm_err "guard-branch: git nao encontrado no PATH"
    return 1
  fi

  # Obter branch atual
  _head=$(git -C "$_pap" rev-parse --abbrev-ref HEAD 2>/dev/null) || {
    _cm_err "guard-branch: nao e um repositorio git ou git falhou em $_pap"
    return 1
  }

  # Resolver branch default: mesmo algoritmo de _session_default_branch
  # (remote HEAD => fallback "main")
  _default=$(git -C "$_pap" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
    | sed 's@^refs/remotes/origin/@@') || _default=""
  [ -n "$_default" ] || _default="main"

  printf '%s\n' "$_head"

  if [ "$_head" = "$_default" ]; then
    _cm_err "guard-branch: HEAD esta na branch default '$_default' — commit/push bloqueado (FR-005)"
    return 3
  fi

  return 0
}

# ---------- subcomando: stage-message ----------
# stage-message --feature NAME --stage STAGE
# stdout: mensagem Conventional Commits
# exit: 0; 2 em args faltando
_cm_cmd_stage_message() {
  _feature=""
  _stage=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --feature) _feature=$2; shift 2 ;;
      --stage)   _stage=$2;   shift 2 ;;
      *) _cm_die_usage "stage-message: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_feature" ] || _cm_die_usage "stage-message: --feature obrigatorio"
  [ -n "$_stage" ]   || _cm_die_usage "stage-message: --stage obrigatorio"

  # Mapeamento stage -> scope Conventional Commits
  case "$_stage" in
    specify)      _scope="spec" ;;
    clarify)      _scope="spec" ;;
    plan)         _scope="plan" ;;
    checklist)    _scope="checklist" ;;
    create-tasks) _scope="tasks" ;;
    briefing)     _scope="briefing" ;;
    constitution) _scope="constitution" ;;
    review-task)  _scope="review" ;;
    *)            _scope="$_stage" ;;
  esac

  printf 'docs(%s): %s %s\n' "$_scope" "$_stage" "$_feature"
  return 0
}

# ---------- subcomando: task-message ----------
# task-message --feature NAME --task-ids "ID[,ID...]" [--brief TEXT]
# stdout: mensagem Conventional Commits
# exit: 0; 2 em args faltando
_cm_cmd_task_message() {
  _feature=""
  _ids=""
  _brief=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --feature)  _feature=$2; shift 2 ;;
      --task-ids) _ids=$2;     shift 2 ;;
      --brief)    _brief=$2;   shift 2 ;;
      *) _cm_die_usage "task-message: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_feature" ] || _cm_die_usage "task-message: --feature obrigatorio"
  [ -n "$_ids" ]     || _cm_die_usage "task-message: --task-ids obrigatorio"

  # Contar IDs (separados por virgula)
  _count=$(printf '%s' "$_ids" | tr ',' '\n' | grep -c .)

  if [ "$_count" -eq 1 ]; then
    # ID unico
    _id_clean=$(printf '%s' "$_ids" | tr -d ' ')
    if [ -n "$_brief" ]; then
      printf 'feat: task %s %s\n' "$_id_clean" "$_brief"
    else
      printf 'feat: task %s\n' "$_id_clean"
    fi
    return 0
  fi

  # Multiplos IDs: checar contiguidade
  # Separa em lista de IDs e verifica se formam range continuo
  # IDs format: N.M (ex: 1.1, 1.2, 2.1)
  _first=""
  _last=""
  _prev_major=""
  _prev_minor=""
  _is_range=1

  # Processar cada ID na lista
  _n=0
  _id_list=$(printf '%s' "$_ids" | tr ',' '\n' | sed 's/^ *//;s/ *$//')
  while IFS= read -r _id; do
    [ -z "$_id" ] && continue
    _n=$((_n + 1))
    [ "$_n" -eq 1 ] && _first="$_id"
    _last="$_id"

    # Extrair major.minor
    _major=$(printf '%s' "$_id" | cut -d'.' -f1)
    _minor=$(printf '%s' "$_id" | cut -d'.' -f2)

    if [ "$_n" -gt 1 ]; then
      # Verificar contiguidade: mesmo major e minor = prev+1,
      # OU major = prev_major+1 e minor = 1 (transicao de fase)
      if [ "$_major" = "$_prev_major" ]; then
        _expected=$((_prev_minor + 1))
        if [ "$_minor" != "$_expected" ]; then
          _is_range=0
        fi
      else
        _expected_major=$((_prev_major + 1))
        if [ "$_major" != "$_expected_major" ] || [ "$_minor" != "1" ]; then
          _is_range=0
        fi
      fi
    fi

    _prev_major="$_major"
    _prev_minor="$_minor"
  done << EOF
$_id_list
EOF

  if [ "$_is_range" = 1 ]; then
    # Range contiguos
    if [ -n "$_brief" ]; then
      printf 'feat: tasks %s-%s %s\n' "$_first" "$_last" "$_brief"
    else
      printf 'feat: tasks %s-%s\n' "$_first" "$_last"
    fi
  else
    # Lista nao-contigua: substituir virgulas por ", "
    _ids_formatted=$(printf '%s' "$_ids" | sed 's/,/, /g')
    if [ -n "$_brief" ]; then
      printf 'feat: tasks %s %s\n' "$_ids_formatted" "$_brief"
    else
      printf 'feat: tasks %s\n' "$_ids_formatted"
    fi
  fi
  return 0
}

# ---------- subcomando: finalize ----------
# finalize --state-dir DIR --projeto-alvo-path PATH [--session NAME]
#          [--title T] [--body B]
# stdout: JSON com PushPRResult
# exit: 0 (sempre em casos tratados); 2 (uso incorreto)
_cm_cmd_finalize() {
  _sdir=""
  _pap=""
  _session=""
  _title=""
  _body=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)         _sdir=$2;    shift 2 ;;
      --projeto-alvo-path) _pap=$2;     shift 2 ;;
      --session)           _session=$2; shift 2 ;;
      --title)             _title=$2;   shift 2 ;;
      --body)              _body=$2;    shift 2 ;;
      *) _cm_die_usage "finalize: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sdir" ] || _cm_die_usage "finalize: --state-dir obrigatorio"
  [ -n "$_pap" ]  || _cm_die_usage "finalize: --projeto-alvo-path obrigatorio"

  _rw=$(_cm_rw)
  [ -f "$_rw" ] || _cm_die "state-rw.sh nao encontrado: $_rw" 1

  _now=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || _now="unknown"

  # Funcao auxiliar para gravar PushPRResult e emitir JSON
  _cm_record_result() {
    _s="$1"
    _br="${2:-}"
    _url="${3:-}"
    _reason="${4:-}"

    # Gravar via state-rw.sh set (caminho auditado; state-history + sha256)
    _result_json=$(printf '{"status":"%s","branch":"%s","pr_url":"%s","reason":"%s","recorded_at":"%s"}' \
      "$_s" "$_br" "$_url" "$_reason" "$_now")
    sh "$_rw" set --state-dir "$_sdir" \
      --field '.push_pr_result' \
      --value "$_result_json" 2>/dev/null || _cm_err "finalize: falha ao gravar push_pr_result (status=$_s)"

    printf '%s\n' "$_result_json"
  }

  # Passo 1: is-enabled?
  _enabled=$(_cm_cmd_is_enabled --state-dir "$_sdir")
  if [ "$_enabled" != "true" ]; then
    _cm_err "finalize: atomic-commit desabilitado — skip (skipped-disabled)"
    _cm_record_result "skipped-disabled" "" "" "atomic_commit_enabled=false"
    return 0
  fi

  # Passo 2: guard-branch
  _branch_out=$(_cm_cmd_guard_branch --state-dir "$_sdir" --projeto-alvo-path "$_pap")
  _guard_rc=$?
  _curr_branch=$(printf '%s' "$_branch_out" | head -1)

  if [ "$_guard_rc" = 3 ]; then
    _cm_err "finalize: HEAD na branch default — push/PR bloqueado (skipped-default-branch)"
    _cm_record_result "skipped-default-branch" "$_curr_branch" "" "HEAD e a branch default"
    return 0
  fi
  if [ "$_guard_rc" != 0 ]; then
    _cm_err "finalize: guard-branch falhou (exit $_guard_rc) — skip com status error"
    _cm_record_result "error" "$_curr_branch" "" "guard-branch exit $_guard_rc"
    return 0
  fi

  # Passo 3: verificar se tem commits novos vs default
  _default=$(git -C "$_pap" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
    | sed 's@^refs/remotes/origin/@@') || _default="main"
  _ahead=$(git -C "$_pap" rev-list "${_default}..$_curr_branch" --count 2>/dev/null) || _ahead="0"
  if [ "$_ahead" = "0" ]; then
    _cm_err "finalize: branch '$_curr_branch' nao tem commits novos vs '$_default' — skip (skipped-no-commits)"
    _cm_record_result "skipped-no-commits" "$_curr_branch" "" "zero commits ahead of $_default"
    return 0
  fi

  # Passo 4: gh disponivel?
  if ! command -v gh >/dev/null 2>&1; then
    _cm_err "finalize: gh CLI nao encontrado — skip nao-fatal (skipped-gh-missing)"
    _cm_err "finalize: commits locais intactos; instale gh: https://cli.github.com"
    _cm_record_result "skipped-gh-missing" "$_curr_branch" "" "gh CLI nao instalado"
    return 0
  fi

  # Passo 5: gh autenticado?
  if ! gh auth status >/dev/null 2>&1; then
    _cm_err "finalize: gh nao autenticado — skip nao-fatal (skipped-gh-unauth)"
    _cm_err "finalize: rode 'gh auth login' para autenticar"
    _cm_record_result "skipped-gh-unauth" "$_curr_branch" "" "gh nao autenticado"
    return 0
  fi

  # Passo 6: tentar via cstk session pr se --session fornecido
  # cstk deve estar no PATH (instalado em ~/.local/bin/cstk)
  if [ -n "$_session" ] && command -v cstk >/dev/null 2>&1; then
    _cstk_args="$_session"
    [ -n "$_title" ] && _cstk_args="$_cstk_args --title $_title"
    [ -n "$_body" ]  && _cstk_args="$_cstk_args --body $_body"

    # Checar idempotencia: PR ja existe?
    _ex_json=$(gh pr view "$_curr_branch" --json url,state 2>/dev/null) || _ex_json=""
    if [ -n "$_ex_json" ]; then
      case "$_ex_json" in
        *'"state":"OPEN"'*|*'"state":"MERGED"'*)
          _ex_url=$(printf '%s' "$_ex_json" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p')
          _cm_out "finalize: PR ja existe (pr-exists): $_ex_url"
          _cm_record_result "pr-exists" "$_curr_branch" "$_ex_url" "PR pre-existente reusado"
          return 0
          ;;
      esac
    fi

    # Executar cstk session pr (delega push + PR)
    eval "cstk session pr $_cstk_args" >/dev/null 2>&1
    _cstk_rc=$?
    if [ "$_cstk_rc" = 0 ]; then
      # Obter URL do PR criado
      _pr_url=$(gh pr view "$_curr_branch" --json url -q '.url' 2>/dev/null) || _pr_url=""
      _cm_out "finalize: PR aberto via cstk session pr: $_pr_url"
      _cm_record_result "pr-opened" "$_curr_branch" "$_pr_url" "via cstk session pr"
      return 0
    fi
    # cstk falhou: cair no fallback git push + gh pr create
    _cm_err "finalize: cstk session pr falhou (exit $_cstk_rc); tentando fallback git push + gh pr create"
  fi

  # Passo 7: fallback — git push + gh pr create diretamente
  # Idempotencia: checar PR existente
  _ex_json=$(gh pr view "$_curr_branch" --json url,state 2>/dev/null) || _ex_json=""
  if [ -n "$_ex_json" ]; then
    case "$_ex_json" in
      *'"state":"OPEN"'*|*'"state":"MERGED"'*)
        _ex_url=$(printf '%s' "$_ex_json" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p')
        _cm_out "finalize: PR ja existe (pr-exists): $_ex_url"
        _cm_record_result "pr-exists" "$_curr_branch" "$_ex_url" "PR pre-existente reusado"
        return 0
        ;;
    esac
  fi

  # Push
  if ! git -C "$_pap" push -u origin "$_curr_branch" 2>/dev/null; then
    _cm_err "finalize: 'git push -u origin $_curr_branch' falhou — skip nao-fatal"
    _cm_err "finalize: verifique conectividade e permissoes: cd $_pap && git push -u origin $_curr_branch"
    _cm_record_result "error" "$_curr_branch" "" "git push falhou"
    return 0
  fi

  # gh pr create
  _gh_args="--base $_default --head $_curr_branch"
  [ -n "$_title" ] && _gh_args="$_gh_args --title $_title"
  [ -n "$_body" ]  && _gh_args="$_gh_args --body $_body"

  _pr_url=$(eval "cd $_pap && gh pr create $_gh_args" 2>/dev/null) || _pr_url=""
  if [ -z "$_pr_url" ]; then
    # gh pr create pode ter falhado; checar se PR foi criado mesmo assim
    _pr_url=$(gh pr view "$_curr_branch" --json url -q '.url' 2>/dev/null) || _pr_url=""
    if [ -z "$_pr_url" ]; then
      _cm_err "finalize: 'gh pr create' falhou — push ja feito, PR nao criado"
      _cm_err "finalize: retry manual: cd $_pap && gh pr create --base $_default --head $_curr_branch"
      _cm_record_result "error" "$_curr_branch" "" "push ok mas gh pr create falhou"
      return 0
    fi
  fi

  _cm_out "finalize: PR aberto: $_pr_url"
  _cm_record_result "pr-opened" "$_curr_branch" "$_pr_url" "via git push + gh pr create"
  return 0
}

# ---------- dispatch ----------

[ "$#" -gt 0 ] || _cm_die_usage "subcomando obrigatorio: is-enabled|set-enabled|guard-branch|stage-message|task-message|finalize"

_CM_CMD=$1
shift

case "$_CM_CMD" in
  is-enabled)    _cm_cmd_is_enabled    "$@" ;;
  set-enabled)   _cm_cmd_set_enabled   "$@" ;;
  guard-branch)  _cm_cmd_guard_branch  "$@" ;;
  stage-message) _cm_cmd_stage_message "$@" ;;
  task-message)  _cm_cmd_task_message  "$@" ;;
  finalize)      _cm_cmd_finalize      "$@" ;;
  *)
    _cm_die_usage "subcomando desconhecido: $_CM_CMD (validos: is-enabled|set-enabled|guard-branch|stage-message|task-message|finalize)"
    ;;
esac
