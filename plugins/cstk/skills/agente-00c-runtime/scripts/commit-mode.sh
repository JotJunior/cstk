#!/bin/sh
# commit-mode.sh — helper POSIX para o modo opt-in atomic-commit.
#
# Feature: atomic-commit-pr (staging por allowlist: living-specs FASE 5)
# Ref:     docs/specs/_archived/atomic-commit-pr/contracts/commit-mode.md
#          docs/specs/_archived/atomic-commit-pr/spec.md §FR-002..011
#          docs/specs/living-specs/contracts/commit-staging-cli.md
#          docs/specs/living-specs/spec.md FR-014..FR-017
#
# Subcomandos:
#   is-enabled   --state-dir DIR
#   set-enabled  --state-dir DIR --value <true|false>
#   guard-branch --state-dir DIR --projeto-alvo-path PATH
#   ensure-branch --projeto-alvo-path PATH --short-name NAME
#                 [--prefix PREFIX/]
#                 Garante HEAD fora da branch default ANTES da execucao
#                 comecar (atomic-commit-ensure-branch FR-001..003):
#                 cria/troca para <prefix><short-name> (prefix default
#                 "feature/") quando HEAD esta na default; no-op senao.
#                 Nao substitui guard-branch (defesa em profundidade por
#                 onda). Invocado pelos commands pai no opt-in/resume.
#   probe-pending-work --state-dir DIR --projeto-alvo-path PATH -- BRANCH
#                 Sonda READ-ONLY de trabalho nao integrado (feature
#                 reopen-flow, FR-021). Ver contracts/pending-work-probe.md.
#   stage-message --feature NAME --stage STAGE
#   task-message  --feature NAME --task-ids "ID[,ID...]" [--brief TEXT]
#   finalize     --state-dir DIR --projeto-alvo-path PATH [--session NAME]
#                [--title T] [--body B]
#   snapshot      --state-dir DIR --projeto-alvo-path PATH
#   stage-derived --state-dir DIR --projeto-alvo-path PATH [--scope-dir REL_DIR]...
#                 REL_DIR e RELATIVO a raiz do projeto-alvo. Um valor
#                 ABSOLUTO sob --projeto-alvo-path e normalizado para
#                 relativo automaticamente (tolerancia, nao contrato).
#
# Exit codes globais:
#   0  sucesso / caso tratado (inclui skips nao-fatais; stage-derived: >=1 path staged)
#   1  erro generico (ex: git ausente, write falhou)
#   2  erro de uso (flag faltando ou valor invalido)
#   3  recusa de guard (branch default ou modo desabilitado — nao-fatal);
#      stage-derived: allowlist vazia, nada staged (FR-016, nao-fatal)
#
# POSIX sh puro. Zero deps obrigatorias.
# Deps opcionais: jq (state read/write), git (branch/commit), gh (PR).
# Ausencia de dep opcional => skip com status gravado, NUNCA aborta a onda.
#
# snapshot/stage-derived (FR-014): staging EXPLICITO por allowlist derivada —
# jamais `git add -A`/`git add .`/`git add --all` em qualquer caminho de
# codigo. `stage-derived` so inclui untracked se `snapshot` rodou antes na
# mesma onda (baseline ausente => untracked ficam FORA, fail-closed —
# nunca fallback para staging amplo).

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

# Tenta sourcear _diag.sh do mesmo dir (envelope DIAG| uniforme, ja
# canonico em agente-00c-runtime/scripts/ — sem vendoring necessario aqui).
_cm_diag_sourced=0
if [ -n "${_cm_sd:-}" ] && [ -f "$_cm_sd/_diag.sh" ]; then
  # shellcheck disable=SC1090
  . "$_cm_sd/_diag.sh" && _cm_diag_sourced=1
fi

# _cm_diag SEVERITY CODE MESSAGE FIX — no-op se _diag.sh indisponivel.
_cm_diag() {
  [ "$_cm_diag_sourced" = 1 ] || return 0
  diag_emit "$1" "$2" "$3" "$4" || :
}

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

# Token de nome ([A-Za-z0-9._-], 1..64 chars) — mesmo padrao fail-closed
# do --add-etapa de state-ondas.sh. Usado por ensure-branch (FR-003).
_cm_is_name_token() {
  case "$1" in ''|*[!A-Za-z0-9._-]*) return 1 ;; esac
  [ "${#1}" -le 64 ]
}

# Resolve a branch default do repo em $1: origin/HEAD e autoritativo
# quando ha remote. Sem remote (repo local / origin/HEAD nao setado),
# imprime vazio — caso em que a convencao main/master vale como default.
# O exit status de um pipe e o do ULTIMO comando (o sed, que sai 0 mesmo
# com entrada vazia) — nesta forma o `|| ...` NUNCA dispara (issue #98).
# Captura em duas etapas para o fallback ser alcancavel.
_cm_resolve_default_branch() {
  _rdb_sr=$(git -C "$1" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null) || _rdb_sr=""
  printf '%s' "$_rdb_sr" | sed 's@^refs/remotes/origin/@@'
}

# _cm_branch_is_default PAP BRANCH — 0 se BRANCH e a default de PAP.
# Sem remote, o nome do branch default de `git init` VARIA por ambiente
# (macOS default "main", muitos Linux/CI default "master"): AMBOS contam.
_cm_branch_is_default() {
  _bid_default=$(_cm_resolve_default_branch "$1")
  if [ -n "$_bid_default" ]; then
    [ "$2" = "$_bid_default" ]
  else
    [ "$2" = "main" ] || [ "$2" = "master" ]
  fi
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

  printf '%s\n' "$_head"

  # Resolucao de default compartilhada com ensure-branch — regra UNICA
  # (_cm_branch_is_default): origin/HEAD autoritativo com remote;
  # convencao main/master sem remote.
  if _cm_branch_is_default "$_pap" "$_head"; then
    _default=$(_cm_resolve_default_branch "$_pap")
    [ -n "$_default" ] || _default=$_head
    _cm_err "guard-branch: HEAD esta na branch default '$_default' — commit/push bloqueado (FR-005)"
    return 3
  fi

  return 0
}

# ---------- subcomando: ensure-branch ----------
# ensure-branch --projeto-alvo-path PATH --short-name NAME [--prefix PREFIX/]
# Garante HEAD fora da branch default ANTES da execucao comecar
# (atomic-commit-ensure-branch FR-001..003). Invocado pelos commands pai
# no momento do opt-in de atomic-commit (e em resume/reopen, idempotente).
# NAO substitui guard-branch — que permanece como defesa em profundidade
# por onda (operador pode voltar para a default mid-execucao).
# stdout: "noop <branch>" | "created <target>" | "switched <target>"
# exit: 0 sucesso/no-op, 1 git ausente/nao-repo/checkout falhou, 2 uso
_cm_cmd_ensure_branch() {
  _pap=""
  _short=""
  _prefix="feature/"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --projeto-alvo-path) _pap=$2;    shift 2 ;;
      --short-name)        _short=$2;  shift 2 ;;
      --prefix)            _prefix=$2; shift 2 ;;
      *) _cm_die_usage "ensure-branch: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_pap" ]   || _cm_die_usage "ensure-branch: --projeto-alvo-path obrigatorio"
  [ -n "$_short" ] || _cm_die_usage "ensure-branch: --short-name obrigatorio"
  _cm_is_name_token "$_short" || _cm_die_usage \
    "ensure-branch: --short-name aceita token ([A-Za-z0-9._-], ate 64 chars, sem espaco/prosa); recebido: '$_short'"
  case "$_prefix" in
    */) _cm_is_name_token "${_prefix%/}" || _cm_die_usage \
          "ensure-branch: --prefix aceita token terminado em '/'; recebido: '$_prefix'" ;;
    *)  _cm_die_usage "ensure-branch: --prefix deve terminar em '/'; recebido: '$_prefix'" ;;
  esac

  if ! _cm_require_git; then
    _cm_err "ensure-branch: git nao encontrado no PATH"
    return 1
  fi

  _head=$(git -C "$_pap" rev-parse --abbrev-ref HEAD 2>/dev/null) || {
    _cm_err "ensure-branch: nao e um repositorio git ou git falhou em $_pap"
    return 1
  }

  # Ja fora da default (inclui HEAD detached, que nunca casa main/master
  # nem origin/HEAD): no-op observavel — mesmo criterio do guard-branch.
  if ! _cm_branch_is_default "$_pap" "$_head"; then
    printf 'noop %s\n' "$_head"
    return 0
  fi

  _target="${_prefix}${_short}"
  if git -C "$_pap" rev-parse --verify --quiet "refs/heads/$_target" >/dev/null 2>&1; then
    # Branch da feature ja existe (resume/reopen, ou criada fora): trocar.
    if ! git -C "$_pap" checkout "$_target" >/dev/null 2>&1; then
      _cm_err "ensure-branch: git checkout $_target falhou (working tree conflita com a branch? resolva ou use cstk session start)"
      return 1
    fi
    printf 'switched %s\n' "$_target"
  else
    # checkout -b preserva a working tree corrente (mudancas nao-comitadas
    # migram junto — e o desejado no opt-in em cima de trabalho em curso).
    if ! git -C "$_pap" checkout -b "$_target" >/dev/null 2>&1; then
      _cm_err "ensure-branch: git checkout -b $_target falhou"
      return 1
    fi
    printf 'created %s\n' "$_target"
  fi
  return 0
}

# ---------- subcomando: probe-pending-work ----------
# probe-pending-work --state-dir DIR --projeto-alvo-path PATH -- BRANCH
#
# Sonda READ-ONLY de trabalho nao integrado do round anterior (feature
# reopen-flow, FR-021). Contrato:
#   docs/specs/feature-reopen/contracts/pending-work-probe.md
#
# stdout: PROBE|<branch>|<default_branch>|<merged>|<pr_state>|<pr_url>|<source>|<probe_status>
# exit: 0 checked (git respondeu; gh pode ou nao ter respondido)
#       3 skipped-no-git (git ausente / PAP nao e repo / BRANCH inexistente)
#       1 erro generico de IO/permissao nao coberto pelos casos acima
#       2 uso incorreto
#
# Regra fail-closed (dec-038, task 1.2): um campo so recebe valor concreto
# quando a leitura que o produz foi bem-sucedida E parseada. Qualquer outro
# desfecho MUST manter o campo em "unknown" — PROIBIDO o idioma
# `cmd 2>/dev/null || var=""` seguido de tratar vazio como resposta negativa
# (anti-padrao ja presente em `finalize`, linhas ~726/771 deste arquivo;
# esta sonda NAO o repete).
_cm_cmd_probe_pending_work() {
  _sdir=""
  _pap=""
  _branch=""
  _seen_sep=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)         _sdir=$2; shift 2 ;;
      --projeto-alvo-path) _pap=$2;  shift 2 ;;
      --)
        shift
        _seen_sep=1
        if [ "$#" -gt 0 ]; then
          _branch=$1
          shift
        fi
        break
        ;;
      *) _cm_die_usage "probe-pending-work: flag desconhecida: $1" ;;
    esac
  done
  [ "$_seen_sep" = 1 ] || _cm_die_usage "probe-pending-work: '--' obrigatorio antes de BRANCH"
  [ -n "$_sdir" ]   || _cm_die_usage "probe-pending-work: --state-dir obrigatorio"
  [ -n "$_pap" ]    || _cm_die_usage "probe-pending-work: --projeto-alvo-path obrigatorio"
  [ -n "$_branch" ] || _cm_die_usage "probe-pending-work: BRANCH obrigatorio apos --"

  _default_branch="unknown"
  _merged="unknown"
  _pr_state="unknown"
  _pr_url="-"
  _source=""
  _probe_status=""

  _cm_probe_emit() {
    printf 'PROBE|%s|%s|%s|%s|%s|%s|%s\n' \
      "$_branch" "$_default_branch" "$_merged" "$_pr_state" "$_pr_url" "$_source" "$_probe_status"
  }

  # Passo b: git ausente no PATH -> skipped-no-git (T-51 style: nunca
  # infere negativo de ausencia)
  if ! command -v git >/dev/null 2>&1; then
    _probe_status="skipped-no-git"
    _source="command -v git"
    _cm_probe_emit
    return 3
  fi

  # PAP precisa ser um repositorio git valido
  if ! git -C "$_pap" rev-parse --git-dir >/dev/null 2>&1; then
    _probe_status="skipped-no-git"
    _source="git -C $_pap rev-parse --git-dir"
    _cm_probe_emit
    return 3
  fi

  # Passo c: BRANCH precisa existir local ou como remote-tracking (origin).
  # `--` ja separou BRANCH de flags (T-52); refs/heads/$_branch nunca
  # comeca por '-' mesmo quando $_branch comeca, entao o comando abaixo e
  # seguro sem separador adicional.
  if git -C "$_pap" rev-parse --verify --quiet "refs/heads/$_branch" >/dev/null 2>&1; then
    _branch_ref="refs/heads/$_branch"
  elif git -C "$_pap" rev-parse --verify --quiet "refs/remotes/origin/$_branch" >/dev/null 2>&1; then
    _branch_ref="refs/remotes/origin/$_branch"
  else
    _probe_status="skipped-no-git"
    _source="git -C $_pap rev-parse --verify --quiet refs/heads/$_branch"
    _cm_probe_emit
    return 3
  fi

  # Passo d: default_branch — mesmo padrao de guard-branch/finalize.
  # O exit status de um pipe e o do ULTIMO comando (o sed, que sai 0 mesmo
  # com entrada vazia) — nesta forma o `|| ...` NUNCA dispara (issue #98).
  # Captura em duas etapas para o fallback ser alcancavel.
  _sr=$(git -C "$_pap" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null) || _sr=""
  _dflt=$(printf '%s' "$_sr" | sed 's@^refs/remotes/origin/@@')
  _default_ref=""
  if [ -n "$_dflt" ]; then
    _default_branch="$_dflt"
    _default_ref="refs/remotes/origin/$_dflt"
  elif git -C "$_pap" rev-parse --verify --quiet refs/heads/main >/dev/null 2>&1; then
    _default_branch="main"
    _default_ref="refs/heads/main"
  elif git -C "$_pap" rev-parse --verify --quiet refs/heads/master >/dev/null 2>&1; then
    _default_branch="master"
    _default_ref="refs/heads/master"
  fi

  if [ -z "$_default_ref" ]; then
    # Nem origin/HEAD nem main/master locais resolvem uma branch default —
    # git nao consegue estabelecer o fato primario (merge). Dobra na mesma
    # categoria de b/c (git nao pode responder): skipped-no-git.
    _probe_status="skipped-no-git"
    _source="git -C $_pap symbolic-ref refs/remotes/origin/HEAD"
    _cm_probe_emit
    return 3
  fi

  # Passo e: merged? `--is-ancestor` responde por exit code: 0=sim, 1=nao
  # (resposta definitiva), >1=erro de execucao (nunca vira "no" — I-P1).
  _merge_source="git merge-base --is-ancestor"
  if git -C "$_pap" merge-base --is-ancestor "$_branch_ref" "$_default_ref" 2>/dev/null; then
    _merged="yes"
  else
    _mb_rc=$?
    if [ "$_mb_rc" = 1 ]; then
      _merged="no"
    else
      # Falha de execucao do merge-base (ex: object store corrompido) —
      # mesma categoria de "git nao pode responder".
      _probe_status="skipped-no-git"
      _source="$_merge_source"
      _cm_probe_emit
      return 3
    fi
  fi

  # Passos f/g/h: gh e dependencia OPCIONAL (carve-out ja usado por
  # `finalize`). merged (dado primario de FR-021) ja foi checado acima —
  # o exit permanece 0 daqui em diante independente do desfecho de gh.
  if ! command -v gh >/dev/null 2>&1; then
    _probe_status="skipped-gh-missing"
    _source="$_merge_source; command -v gh"
    _cm_probe_emit
    return 0
  fi

  if ! gh auth status >/dev/null 2>&1; then
    _probe_status="skipped-gh-unauth"
    _source="$_merge_source; gh auth status"
    _cm_probe_emit
    return 0
  fi

  # Passo h: gh pr view — exit code e stdout capturados SEPARADAMENTE
  # (I-P1; PROIBIDO o idioma `cmd 2>/dev/null || var=""` que colapsa
  # timeout/nao-autenticado/ausencia-real-de-PR em um unico "vazio").
  # Qualquer desfecho que nao seja exit 0 + JSON reconhecido mantem
  # pr_state=unknown/pr_url="-" — NUNCA "closed"/"merged" inferido.
  _gh_source="gh pr view $_branch --json url,state"
  _pr_rc=0
  _pr_json=$(gh pr view "$_branch" --json url,state 2>/dev/null) || _pr_rc=$?
  if [ "$_pr_rc" = 0 ] && [ -n "$_pr_json" ]; then
    case "$_pr_json" in
      *'"state":"OPEN"'*)   _pr_state="open" ;;
      *'"state":"CLOSED"'*) _pr_state="closed" ;;
      *'"state":"MERGED"'*) _pr_state="merged" ;;
    esac
    if [ "$_pr_state" != "unknown" ]; then
      _pr_url=$(printf '%s' "$_pr_json" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p')
      [ -n "$_pr_url" ] || _pr_url="-"
    fi
  fi

  # probe_status: o enum (dec-038, candidato 3 descartado) nao distingue
  # "sem PR"/"rede indisponivel"/"rate-limit" — todos colapsam em
  # pr_state=unknown acima. O dado primario (merged) foi checado de fato
  # (exit-codes table §0), entao "checked" e o valor correto mesmo quando
  # pr_state permaneceu unknown.
  _probe_status="checked"
  _source="$_merge_source; $_gh_source"
  _cm_probe_emit
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
    converge)     _scope="converge" ;;
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

  # Multiplos IDs (format N.M): agrupar em RUNS contiguos DENTRO da mesma
  # fase (major), emitindo "A-B" por run com >=2 IDs e "A" para run unitario,
  # unidos por ", ".
  #
  # A transicao de fase NUNCA conta como continuidade. A heuristica antiga
  # aceitava "major = prev_major+1 e minor = 1" como contiguo, sem verificar
  # se os minors intermediarios da fase anterior estavam de fato na lista:
  # com --task-ids "1.1,2.1,2.2,2.3" (1.2/1.3 bloqueadas nesta onda) ela
  # emitia "feat: tasks 1.1-2.3", implicando FALSAMENTE que 1.2/1.3 foram
  # concluidas. Nao ha como saber daqui qual e o ultimo minor esperado de
  # uma fase (isso mora no tasks.md), entao a compressao cross-fase e
  # abandonada: "1.1,2.1,2.2,2.3" -> "feat: tasks 1.1, 2.1-2.3".
  _id_list=$(printf '%s' "$_ids" | tr ',' '\n' | sed 's/^ *//;s/ *$//;/^$/d')

  _out=""
  _run_first=""
  _run_last=""
  _run_n=0
  _prev_major=""
  _prev_minor=""
  _prev_numeric=0

  while IFS= read -r _id; do
    [ -z "$_id" ] && continue

    _major=$(printf '%s' "$_id" | cut -d'.' -f1)
    _minor=$(printf '%s' "$_id" | cut -d'.' -f2)

    # ID nao-numerico (ex: "A.1", "1", "1.x") jamais entra em aritmetica —
    # sob `set -eu` um $(( )) sobre nao-numero aborta o script inteiro.
    _numeric=1
    case "$_major" in ''|*[!0-9]*) _numeric=0 ;; esac
    case "$_minor" in ''|*[!0-9]*) _numeric=0 ;; esac

    _continues=0
    if [ "$_run_n" -gt 0 ] && [ "$_numeric" = 1 ] && [ "$_prev_numeric" = 1 ] \
       && [ "$_major" = "$_prev_major" ] \
       && [ "$_minor" -eq $((_prev_minor + 1)) ]; then
      _continues=1
    fi

    if [ "$_continues" = 1 ]; then
      _run_last="$_id"
      _run_n=$((_run_n + 1))
    else
      if [ "$_run_n" -gt 0 ]; then
        if [ "$_run_n" -eq 1 ]; then _seg="$_run_first"; else _seg="$_run_first-$_run_last"; fi
        if [ -z "$_out" ]; then _out="$_seg"; else _out="$_out, $_seg"; fi
      fi
      _run_first="$_id"
      _run_last="$_id"
      _run_n=1
    fi

    _prev_major="$_major"
    _prev_minor="$_minor"
    _prev_numeric="$_numeric"
  done << EOF
$_id_list
EOF

  # Flush do ultimo run.
  if [ "$_run_n" -gt 0 ]; then
    if [ "$_run_n" -eq 1 ]; then _seg="$_run_first"; else _seg="$_run_first-$_run_last"; fi
    if [ -z "$_out" ]; then _out="$_seg"; else _out="$_out, $_seg"; fi
  fi

  if [ -n "$_brief" ]; then
    printf 'feat: tasks %s %s\n' "$_out" "$_brief"
  else
    printf 'feat: tasks %s\n' "$_out"
  fi
  return 0
}

# ---------- subcomando: snapshot ----------
# snapshot --state-dir DIR --projeto-alvo-path PATH
# Captura o conjunto de untracked ATUAL do repo (git status --porcelain,
# linhas "?? "), paths ordenados, grava em DIR/commit-baseline.txt
# (sidecar — nunca dentro do state.json, nunca versionado; 1 baseline por
# onda, sobrescreve a anterior).
# exit: 0 gravado; 1 erro git/IO; 2 uso incorreto
_cm_cmd_snapshot() {
  _sdir=""
  _pap=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)          _sdir=$2; shift 2 ;;
      --projeto-alvo-path)  _pap=$2;  shift 2 ;;
      *) _cm_die_usage "snapshot: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sdir" ] || _cm_die_usage "snapshot: --state-dir obrigatorio"
  [ -n "$_pap" ]  || _cm_die_usage "snapshot: --projeto-alvo-path obrigatorio"

  if ! _cm_require_git; then
    _cm_err "snapshot: git nao encontrado no PATH"
    _cm_diag "error" "git-missing" "git nao encontrado no PATH" "instale git ou ajuste o PATH antes de habilitar atomic-commit"
    return 1
  fi

  mkdir -p "$_sdir" 2>/dev/null || {
    _cm_err "snapshot: nao foi possivel criar diretorio $_sdir"
    return 1
  }

  _baseline="$_sdir/commit-baseline.txt"
  _tmp="$_baseline.tmp.$$"

  # -z: NUL-terminated entries, paths NUNCA quoted/C-style-escaped pelo git
  # (independe de core.quotepath) — unica forma robusta de extrair paths com
  # espaco/unicode sem parsing ambiguo (CHK029). --untracked-files=all
  # desliga o "rollup" de diretorio inteiro-untracked numa unica entrada
  # ("?? dir/") — sem isso, um diretorio de feature novo (ex: docs/) vira 1
  # entrada so, quebrando o casamento por prefixo de --scope-dir. Convertido
  # para uma linha por entrada via tr (paths nao contem NUL; newline
  # literal em nome de arquivo e fora de escopo, mesma limitacao aceita
  # pelo restante do runtime POSIX).
  # LC_ALL=C: baseline e comparado via `comm` em stage-derived, que exige
  # ordenacao IDENTICA — collation de locale (pt_BR etc.) divergente entre
  # as duas invocacoes faz untracked pre-existente "vazar" como novo.
  if ! git -C "$_pap" status --porcelain -z --untracked-files=all 2>/dev/null \
      | tr '\0' '\n' | sed -n 's/^?? //p' | LC_ALL=C sort > "$_tmp"; then
    rm -f "$_tmp" 2>/dev/null || :
    _cm_err "snapshot: 'git status --porcelain' falhou em $_pap"
    _cm_diag "error" "git-status-failed" "git status --porcelain falhou em $_pap" "confirme que $_pap e um repositorio git valido"
    return 1
  fi

  mv "$_tmp" "$_baseline" || {
    _cm_err "snapshot: falha ao gravar $_baseline"
    return 1
  }

  return 0
}

# ---------- subcomando: stage-derived ----------
# stage-derived --state-dir DIR --projeto-alvo-path PATH [--scope-dir REL_DIR]...
# Computa a CommitAllowlist (tracked_changed + untracked_new via baseline
# de snapshot) e faz `git add -- <path>` por entrada — NUNCA `git add -A`,
# `git add .`, `git add --all` (FR-014).
# exit: 0 (>=1 path staged); 3 (allowlist vazia — nada a commitar, FR-016);
#       1 (erro git); 2 (uso incorreto)
_cm_cmd_stage_derived() {
  _sdir=""
  _pap=""
  _scope_file="${TMPDIR:-/tmp}/cm-scopes.$$"
  _has_scope=0
  : > "$_scope_file"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)          _sdir=$2; shift 2 ;;
      --projeto-alvo-path)  _pap=$2;  shift 2 ;;
      --scope-dir)
        # Remove barra final para comparacao consistente de prefixo.
        printf '%s\n' "${2%/}" >> "$_scope_file"
        _has_scope=1
        shift 2
        ;;
      *) rm -f "$_scope_file" 2>/dev/null || :; _cm_die_usage "stage-derived: flag desconhecida: $1" ;;
    esac
  done
  if [ -z "$_sdir" ] || [ -z "$_pap" ]; then
    rm -f "$_scope_file" 2>/dev/null || :
    [ -n "$_sdir" ] || _cm_die_usage "stage-derived: --state-dir obrigatorio"
    _cm_die_usage "stage-derived: --projeto-alvo-path obrigatorio"
  fi

  if ! _cm_require_git; then
    rm -f "$_scope_file" 2>/dev/null || :
    _cm_err "stage-derived: git nao encontrado no PATH"
    _cm_diag "error" "git-missing" "git nao encontrado no PATH" "instale git ou ajuste o PATH antes de habilitar atomic-commit"
    return 1
  fi

  # --scope-dir e RELATIVO a raiz do projeto-alvo (casa por prefixo contra
  # os paths de `git status --porcelain`, que sao SEMPRE relativos). Passar
  # um path ABSOLUTO fazia o filtro nunca casar e devolver rc=3 "allowlist
  # vazia" — diagnostico enganoso, ja que havia arquivos staged-aveis.
  # Normalizamos aqui (depois do parse: --projeto-alvo-path pode vir DEPOIS
  # de --scope-dir em argv) em vez de exigir que todo chamador acerte o
  # formato: os prompts dos orquestradores passam <FD>, que resolve para
  # absoluto em varios pontos.
  if [ "$_has_scope" = 1 ]; then
    _pap_prefix="${_pap%/}/"
    _scope_norm="$_scope_file.norm"
    : > "$_scope_norm"
    while IFS= read -r _sc_line; do
      [ -z "$_sc_line" ] && continue
      case "$_sc_line" in
        "$_pap_prefix"*)
          _sc_line="${_sc_line#"$_pap_prefix"}"
          ;;
        /*)
          # Absoluto FORA do projeto-alvo: nao ha relativo equivalente.
          # Mantido como veio (nunca vai casar, mesmo comportamento de
          # antes), mas agora com diagnostico em vez de rc=3 silencioso.
          _cm_err "stage-derived: --scope-dir absoluto fora de --projeto-alvo-path: $_sc_line (esperado path RELATIVO a $_pap)"
          _cm_diag "warning" "scope-dir-outside-repo" "--scope-dir $_sc_line nao esta sob $_pap" "passe --scope-dir relativo a raiz do projeto-alvo (ex: docs/specs/<feature>)"
          ;;
      esac
      printf '%s\n' "$_sc_line" >> "$_scope_norm"
    done < "$_scope_file"
    mv "$_scope_norm" "$_scope_file"
  fi

  _raw="${TMPDIR:-/tmp}/cm-raw.$$"
  _tracked="${TMPDIR:-/tmp}/cm-tracked.$$"
  _untracked_cur="${TMPDIR:-/tmp}/cm-untracked-cur.$$"
  _untracked_new="${TMPDIR:-/tmp}/cm-untracked-new.$$"
  _allowlist="${TMPDIR:-/tmp}/cm-allowlist.$$"
  _filtered="${TMPDIR:-/tmp}/cm-filtered.$$"

  _cm_cleanup_stage_derived() {
    rm -f "$_scope_file" "$_raw" "$_tracked" "$_untracked_cur" \
      "$_untracked_new" "$_allowlist" "$_filtered" 2>/dev/null || :
  }

  # -z: NUL-terminated entries, paths NUNCA quoted/C-style-escaped pelo git
  # (independe de core.quotepath — medido empiricamente: mesmo com
  # core.quotepath=false, `--porcelain` sem -z ainda envolve em aspas
  # duplas qualquer path com espaco, quebrando parsing por split simples).
  # -z e a UNICA forma robusta de extrair paths com espaco/unicode sem
  # ambiguidade (CHK029). --untracked-files=all desliga o "rollup" de
  # diretorio inteiro-untracked numa unica entrada — sem isso, um path
  # dentro de um diretorio de feature novo nunca casa com --scope-dir (o
  # git colapsa TODO o diretorio novo em "?? dir/"). Convertido para 1
  # linha por campo via tr (paths nao contem NUL; newline literal em nome
  # de arquivo e fora de escopo).
  if ! git -C "$_pap" status --porcelain -z --untracked-files=all 2>/dev/null \
      | tr '\0' '\n' > "$_raw"; then
    _cm_cleanup_stage_derived
    _cm_err "stage-derived: 'git status --porcelain' falhou em $_pap"
    _cm_diag "error" "git-status-failed" "git status --porcelain falhou em $_pap" "confirme que $_pap e um repositorio git valido"
    return 1
  fi

  # Split por posicao fixa (cols 1-2 = XY, col 3 = espaco, col 4+ = path)
  # em vez de word-splitting, entao paths com espaco sao preservados
  # corretamente. Renames/copies (X ou Y == R/C) emitem, no formato -z, um
  # segundo campo NUL-terminado logo em seguida com o path ANTIGO — usamos
  # so o path NOVO (a entrada corrente) e descartamos esse campo extra.
  : > "$_tracked"
  : > "$_untracked_cur"
  _skip_next=0
  while IFS= read -r _line; do
    if [ "$_skip_next" = 1 ]; then
      _skip_next=0
      continue
    fi
    [ -z "$_line" ] && continue
    _xy=$(printf '%s' "$_line" | cut -c1-2)
    _rest=$(printf '%s' "$_line" | cut -c4-)
    case "$_xy" in
      *R*|*C*) _skip_next=1 ;;
    esac
    if [ "$_xy" = "??" ]; then
      printf '%s\n' "$_rest" >> "$_untracked_cur"
    else
      printf '%s\n' "$_rest" >> "$_tracked"
    fi
  done < "$_raw"

  # LC_ALL=C em sort/comm: mesma collation do snapshot (baseline) — `comm`
  # exige ordenacao identica dos dois lados (issue #49).
  LC_ALL=C sort -u -o "$_tracked" "$_tracked"
  LC_ALL=C sort -u -o "$_untracked_cur" "$_untracked_cur"

  _baseline="$_sdir/commit-baseline.txt"
  if [ -f "$_baseline" ]; then
    LC_ALL=C comm -13 "$_baseline" "$_untracked_cur" > "$_untracked_new" 2>/dev/null || : > "$_untracked_new"
  else
    _cm_err "stage-derived: baseline ausente ($_baseline) — untracked ficam FORA do staging (fail-closed, nunca fallback amplo)"
    _cm_diag "warning" "baseline-missing" "commit-baseline.txt ausente em $_sdir" "chame 'commit-mode.sh snapshot' antes de stage-derived para incluir untracked novos"
    : > "$_untracked_new"
  fi

  cat "$_tracked" "$_untracked_new" | LC_ALL=C sort -u > "$_allowlist"

  if [ "$_has_scope" = 1 ]; then
    : > "$_filtered"
    while IFS= read -r _path; do
      [ -z "$_path" ] && continue
      while IFS= read -r _scope; do
        [ -z "$_scope" ] && continue
        case "$_path" in
          "$_scope"/*|"$_scope")
            printf '%s\n' "$_path" >> "$_filtered"
            break
            ;;
        esac
      done < "$_scope_file"
    done < "$_allowlist"
    LC_ALL=C sort -u -o "$_filtered" "$_filtered"
    cp "$_filtered" "$_allowlist" 2>/dev/null || :
  fi

  if [ ! -s "$_allowlist" ]; then
    _cm_cleanup_stage_derived
    _cm_out "stage-derived: allowlist vazia — nada a commitar (FR-016)"
    return 3
  fi

  _add_failed=0
  while IFS= read -r _path; do
    [ -z "$_path" ] && continue
    if ! git -C "$_pap" add -- "$_path" 2>/dev/null; then
      _cm_err "stage-derived: 'git add -- $_path' falhou"
      _cm_diag "error" "git-add-failed" "git add -- $_path falhou" "verifique se o path existe/e valido em $_pap"
      _add_failed=1
    fi
  done < "$_allowlist"

  _cm_cleanup_stage_derived

  if [ "$_add_failed" = 1 ]; then
    return 1
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
  # issue #139: `_x=$(cmd)` herda o exit de `cmd`; sob `set -eu` (topo do
  # script) um exit != 0 aqui ABORTAVA o finalize ANTES do `_guard_rc=$?`,
  # e os dois ramos abaixo (skipped-default-branch / error) eram codigo
  # morto — o finalize vazava exit 1 (repo sem commits, HEAD unborn) ou
  # exit 3 (HEAD na default) em vez do contrato "sempre exit 0 +
  # .push_pr_result registrado". Mesmo padrao ja aplicado ao `cstk session
  # pr` mais abaixo (`|| _cstk_rc=$?`).
  _guard_rc=0
  _branch_out=$(_cm_cmd_guard_branch --state-dir "$_sdir" --projeto-alvo-path "$_pap") || _guard_rc=$?
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
  # issue #98: nesta forma o `|| _default="main"` NUNCA disparava (exit do
  # pipe = exit do sed = 0). _default virava "", o rev-list "..branch"
  # degenerava para 0 e o finalize concluia "sem commits novos", pulando
  # push+PR EM SILENCIO. Captura em duas etapas torna o fallback real.
  _sr=$(git -C "$_pap" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null) || _sr=""
  _default=$(printf '%s' "$_sr" | sed 's@^refs/remotes/origin/@@')
  [ -n "$_default" ] || _default="main"
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
    # sug-008: com PR OPEN pre-existente, o push AINDA e obrigatorio —
    # retornar pr-exists sem empurrar deixava commits locais fora do PR
    # (caso real: state-mcp-server, push pulado com PR #69 aberto).
    _ex_json=$(gh pr view "$_curr_branch" --json url,state 2>/dev/null) || _ex_json=""
    if [ -n "$_ex_json" ]; then
      case "$_ex_json" in
        *'"state":"OPEN"'*)
          _ex_url=$(printf '%s' "$_ex_json" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p')
          if git -C "$_pap" push -u origin "$_curr_branch" 2>/dev/null; then
            _cm_out "finalize: PR ja existe (pr-exists), branch empurrada: $_ex_url"
            _cm_record_result "pr-exists" "$_curr_branch" "$_ex_url" "PR pre-existente reusado; push executado"
          else
            _cm_err "finalize: PR existe mas 'git push' falhou — commits locais fora do PR"
            _cm_record_result "error" "$_curr_branch" "$_ex_url" "PR pre-existente; git push falhou"
          fi
          return 0
          ;;
        *'"state":"MERGED"'*)
          _ex_url=$(printf '%s' "$_ex_json" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p')
          _cm_out "finalize: PR ja existe (pr-exists): $_ex_url"
          _cm_record_result "pr-exists" "$_curr_branch" "$_ex_url" "PR pre-existente (merged)"
          return 0
          ;;
      esac
    fi

    # Executar cstk session pr (delega push + PR).
    # `|| _cstk_rc=$?` e OBRIGATORIO: o script roda sob `set -eu` e um
    # `eval` cru numa linha propria aborta a funcao INTEIRA quando o
    # comando falha — antes de qualquer _cm_record_result, quebrando a
    # garantia documentada "finalize e sempre exit 0 + push_pr_result
    # sempre gravado" (observado em campo: exit 9 com .push_pr_result null).
    _cstk_rc=0
    eval "cstk session pr $_cstk_args" >/dev/null 2>&1 || _cstk_rc=$?
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
  # sug-008: push ANTES do check de PR existente — com PR OPEN, o push
  # continua obrigatorio (atualiza o PR); so MERGED dispensa push.
  _ex_json=$(gh pr view "$_curr_branch" --json url,state 2>/dev/null) || _ex_json=""
  case "$_ex_json" in
    *'"state":"MERGED"'*)
      _ex_url=$(printf '%s' "$_ex_json" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p')
      _cm_out "finalize: PR ja existe (pr-exists): $_ex_url"
      _cm_record_result "pr-exists" "$_curr_branch" "$_ex_url" "PR pre-existente (merged)"
      return 0
      ;;
  esac

  # Push
  if ! git -C "$_pap" push -u origin "$_curr_branch" 2>/dev/null; then
    _cm_err "finalize: 'git push -u origin $_curr_branch' falhou — skip nao-fatal"
    _cm_err "finalize: verifique conectividade e permissoes: cd $_pap && git push -u origin $_curr_branch"
    _cm_record_result "error" "$_curr_branch" "" "git push falhou"
    return 0
  fi

  # PR OPEN pre-existente: push ja feito acima — reusar.
  case "$_ex_json" in
    *'"state":"OPEN"'*)
      _ex_url=$(printf '%s' "$_ex_json" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p')
      _cm_out "finalize: PR ja existe (pr-exists), branch empurrada: $_ex_url"
      _cm_record_result "pr-exists" "$_curr_branch" "$_ex_url" "PR pre-existente reusado; push executado"
      return 0
      ;;
  esac

  # gh pr create
  # sug-007: sem --title/--body o gh nao-interativo FALHA (era a causa de
  # "push feito, PR nao criado" — caso real state-mcp-server). Default:
  # --fill (titulo/corpo derivados dos commits da branch).
  #
  # O gatilho do --fill era `||` (so quando AMBOS faltavam) e deixava um
  # buraco: medido em gh 2.67.0, `--title` SOZINHO produz o mesmo FlagError
  # que nenhuma flag ("must provide `--title` and `--body` ..."), entao
  # `finalize --title X` sem --body reproduzia o defeito que a sug-007
  # deveria ter fechado. Gatilho corrigido para `-z title OU -z body`;
  # --fill combina com --title/--body (medido). Mesmo fix aplicado em
  # cli/lib/session.sh (_session_pr), onde o sintoma foi observado.
  # NOTA set -eu (issue #139): nada de `[ -n "$x" ] && _gh_args=...` como
  # ULTIMO comando de um ramo — o teste falso vira exit 1 do `if` inteiro e
  # aborta a funcao. Blocos `if` explicitos, sem `&&` terminal.
  _gh_args="--base $_default --head $_curr_branch"
  if [ -z "$_title" ] || [ -z "$_body" ]; then
    _gh_args="$_gh_args --fill"
  fi
  if [ -n "$_title" ]; then
    _gh_args="$_gh_args --title $_title"
  fi
  if [ -n "$_body" ]; then
    _gh_args="$_gh_args --body $_body"
  fi

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

[ "$#" -gt 0 ] || _cm_die_usage "subcomando obrigatorio: is-enabled|set-enabled|guard-branch|ensure-branch|probe-pending-work|stage-message|task-message|finalize|snapshot|stage-derived"

_CM_CMD=$1
shift

case "$_CM_CMD" in
  is-enabled)         _cm_cmd_is_enabled         "$@" ;;
  set-enabled)        _cm_cmd_set_enabled        "$@" ;;
  guard-branch)       _cm_cmd_guard_branch       "$@" ;;
  ensure-branch)      _cm_cmd_ensure_branch      "$@" ;;
  probe-pending-work) _cm_cmd_probe_pending_work "$@" ;;
  stage-message)      _cm_cmd_stage_message      "$@" ;;
  task-message)       _cm_cmd_task_message       "$@" ;;
  finalize)           _cm_cmd_finalize           "$@" ;;
  snapshot)           _cm_cmd_snapshot           "$@" ;;
  stage-derived)      _cm_cmd_stage_derived      "$@" ;;
  *)
    _cm_die_usage "subcomando desconhecido: $_CM_CMD (validos: is-enabled|set-enabled|guard-branch|ensure-branch|probe-pending-work|stage-message|task-message|finalize|snapshot|stage-derived)"
    ;;
esac
