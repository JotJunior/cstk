#!/bin/sh
# git-probe.sh — unico arquivo da skill `reconcile-docs` que invoca `git`
# (carve-out 1.1.0 da constitution: git OPCIONAL, confinado, com fallback).
#
# Ref: docs/specs/code-reconciliation/contracts/cli-invocation.md §7
#      research Decision 6; FR-016; checklists/security.md CHK008
#
# Uso:
#   git-probe.sh changed-since --root <dir> --feature-dir <dir>
#       caminhos alterados em commits POSTERIORES ao ultimo commit que tocou os
#       documentos da feature (um por linha, ordenados, sem duplicatas)
#   git-probe.sh status --root <dir>
#       `git status --porcelain` (arquivos untracked listados um a um), ordenado
#   git-probe.sh can-write --root <dir>
#       pre-condicao de escrita (dec-035 / FR-016): so ha gravacao com VCS, pois
#       a reversao pelo git e a unica rede de seguranca. Em repositorio git:
#       `WRITE\tallowed`, exit 0. Sem git (ausente, fora de repositorio ou falha
#       de git): `WRITE\tdenied-no-git`, exit 3 -> o chamador MUST tratar qualquer
#       exit != 0 (inclusive script ausente) como recusa e forcar `--dry-run`.
#
# Sempre invoca `git -c core.fsmonitor=false ...` (neutraliza comando via
# configuracao do repositorio) e SO subcomandos de leitura: `rev-parse`,
# `status --porcelain`, `log --name-only`. GIT_OPTIONAL_LOCKS=0 impede que o
# `status` atualize o indice (a sonda nao altera nada no repositorio).
# Com dados: emite a linha final `STATUS\tok`. Sem `git` no PATH, fora de
# repositorio ou em falha de git: nenhuma linha de dados, SO `STATUS\tno-git`,
# exit 0 (fallback FR-016 — a verificacao segue pela leitura do codigo).
#
# Exit: 0 (inclusive no-git em status/changed-since) | 1 raiz inexistente |
#       2 uso incorreto | 3 (so can-write) escrita recusada por falta de git
# POSIX sh, sem jq.

set -eu

_GP_NAME="git-probe"
TAB=$(printf '\t')

_gp_usage() {
  cat <<'USAGE' >&2
Uso:
  git-probe.sh changed-since --root <dir> --feature-dir <dir>
  git-probe.sh status --root <dir>
  git-probe.sh can-write --root <dir>
USAGE
}

_gp_nogit() {
  if [ "${_GP_CMD:-}" = can-write ]; then printf 'WRITE\tdenied-no-git\n'; exit 3; fi
  printf 'STATUS\tno-git\n'; exit 0
}

# Unica porta de entrada para o git: somente leitura, sem fsmonitor.
_gp_git() {
  GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -c core.quotepath=off -C "$_GP_ROOT" "$@"
}

[ $# -ge 1 ] || { _gp_usage; exit 2; }
_GP_CMD=$1
shift
case "$_GP_CMD" in changed-since | status | can-write) : ;; *) _gp_usage; exit 2 ;; esac

_GP_ROOT=""; _GP_FDIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || { _gp_usage; exit 2; }; _GP_ROOT=$2; shift 2 ;;
    --feature-dir) [ $# -ge 2 ] || { _gp_usage; exit 2; }; _GP_FDIR=$2; shift 2 ;;
    *) _gp_usage; exit 2 ;;
  esac
done
[ -n "$_GP_ROOT" ] || { _gp_usage; exit 2; }
if [ "$_GP_CMD" = changed-since ] && [ -z "$_GP_FDIR" ]; then _gp_usage; exit 2; fi
[ -d "$_GP_ROOT" ] || { printf '%s: raiz inexistente: %s\n' "$_GP_NAME" "$_GP_ROOT" >&2; exit 1; }

command -v git >/dev/null 2>&1 || _gp_nogit
[ "$(_gp_git rev-parse --is-inside-work-tree 2>/dev/null || true)" = true ] || _gp_nogit

case "$_GP_CMD" in
  can-write)
    printf 'WRITE\tallowed\n'
    ;;
  status)
    _GP_OUT=$(_gp_git status --porcelain --untracked-files=all 2>/dev/null) || _gp_nogit
    if [ -n "$_GP_OUT" ]; then printf '%s\n' "$_GP_OUT" | LC_ALL=C sort; fi
    printf 'STATUS\tok\n'
    ;;
  changed-since)
    _GP_REAL=$(cd "$_GP_ROOT" && pwd -P)
    case "$_GP_FDIR" in
      /*) _GP_REL=${_GP_FDIR#"$_GP_REAL"/} ;;
      *) _GP_REL=$_GP_FDIR ;;
    esac
    _GP_REL=${_GP_REL%/}
    case "$_GP_REL" in
      '' | /* | ../* | */../* | ..) printf '%s: feature-dir fora da raiz: %s\n' "$_GP_NAME" "$_GP_FDIR" >&2; exit 2 ;;
    esac
    # Repositorio sem commits: nao ha historico a priorizar.
    if ! _gp_git rev-parse --verify -q HEAD >/dev/null 2>&1; then
      printf 'STATUS\tok\n'
      exit 0
    fi
    _GP_LAST=$(_gp_git log -1 --format=%H -- "$_GP_REL" 2>/dev/null) || _gp_nogit
    if [ -n "$_GP_LAST" ]; then
      _GP_OUT=$(_gp_git log --name-only --format= "$_GP_LAST..HEAD" 2>/dev/null) || _gp_nogit
      if [ -n "$_GP_OUT" ]; then printf '%s\n' "$_GP_OUT" | grep -v '^$' | LC_ALL=C sort -u || true; fi
    fi
    printf 'STATUS\tok\n'
    ;;
esac
exit 0
