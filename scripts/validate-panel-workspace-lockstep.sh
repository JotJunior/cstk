#!/bin/sh
# validate-panel-workspace-lockstep.sh — gate deterministico de lockstep de
# versao entre os workspaces npm do painel (panel/).
#
# Ref: docs/specs/panel-monorepo/tasks.md FASE 5.1/5.2/5.3
#      docs/specs/panel-monorepo/spec.md FR-015, FR-016
#      scripts/validate-plugin-manifests.sh (par simetrico: cobre lockstep
#      dos 3 manifestos do toolkit via MP-5; este script cobre o
#      equivalente para os 4 package.json + package-lock.json do painel)
#
# Invariantes SEMPRE checados (independente de contexto release/nao-release):
#   WL-1  os 4 package.json (panel/, apps/server, apps/web,
#         packages/shared-types) e o package-lock.json existem nos paths
#         esperados
#   WL-2  todos os 5 arquivos acima sao JSON parseavel
#   WL-3  .version dos 4 package.json e identica entre si
#   WL-4  package-lock.json reflete a mesma versao em .version (raiz),
#         .packages[""].version e .packages["<workspace>"].version para
#         cada um dos 3 workspaces (apps/server, apps/web,
#         packages/shared-types) — lockfileVersion 3
#
# Invariante condicional (paridade com MP-5 de validate-plugin-manifests.sh,
# FR-015/FR-016 — lockstep com a tag SemVer do repositorio unificado):
#   WL-5  a versao lockstep (WL-3/WL-4) == --version informado
#           - sem --version: WL-5 pulado (aviso, nada a comparar)
#           - com --version, sem --strict: mismatch = aviso
#           - com --version E --strict: mismatch = erro (uso: release.yml)
#
# Uso:
#   validate-panel-workspace-lockstep.sh [--version X.Y.Z] [--strict] \
#     [--repo-root DIR] [--panel-dir DIR]
#
# Exit:
#   0  nenhum erro (podem existir avisos em stderr)
#   1  pelo menos um erro (WL-1..WL-4 sempre; WL-5 so com --strict)
#   2  uso invalido / dependencia ausente (jq)

set -eu

REPO_ROOT="."
PANEL_DIR="panel"
VERSION=""
STRICT=0

while [ $# -gt 0 ]; do
  case "$1" in
    --version)
      [ $# -ge 2 ] || { printf 'validate-panel-workspace-lockstep: --version exige valor\n' >&2; exit 2; }
      VERSION=$2
      shift 2
      ;;
    --strict)
      STRICT=1
      shift
      ;;
    --repo-root)
      [ $# -ge 2 ] || { printf 'validate-panel-workspace-lockstep: --repo-root exige valor\n' >&2; exit 2; }
      REPO_ROOT=$2
      shift 2
      ;;
    --panel-dir)
      [ $# -ge 2 ] || { printf 'validate-panel-workspace-lockstep: --panel-dir exige valor\n' >&2; exit 2; }
      PANEL_DIR=$2
      shift 2
      ;;
    -h|--help)
      printf 'Uso: %s [--version X.Y.Z] [--strict] [--repo-root DIR] [--panel-dir DIR]\n' "$(basename "$0")"
      exit 0
      ;;
    *)
      printf 'validate-panel-workspace-lockstep: argumento desconhecido: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

command -v jq >/dev/null 2>&1 || {
  printf 'validate-panel-workspace-lockstep: jq ausente no PATH\n' >&2
  exit 2
}

PANEL_ABS="$REPO_ROOT/$PANEL_DIR"
ERRORS=0
WARNINGS=0

_err() { printf 'ERROR: %s\n' "$1" >&2; ERRORS=$((ERRORS + 1)); }
_warn() { printf 'WARN: %s\n' "$1" >&2; WARNINGS=$((WARNINGS + 1)); }

if [ ! -d "$PANEL_ABS" ]; then
  _err "panel dir ausente: $PANEL_ABS"
  printf 'validate-panel-workspace-lockstep: %d erro(s), %d aviso(s)\n' "$ERRORS" "$WARNINGS" >&2
  exit 1
fi

ROOT_PJ="$PANEL_ABS/package.json"
SERVER_PJ="$PANEL_ABS/apps/server/package.json"
WEB_PJ="$PANEL_ABS/apps/web/package.json"
SHARED_PJ="$PANEL_ABS/packages/shared-types/package.json"
LOCK="$PANEL_ABS/package-lock.json"

# WL-1: paths esperados
for _f in "$ROOT_PJ" "$SERVER_PJ" "$WEB_PJ" "$SHARED_PJ" "$LOCK"; do
  if [ ! -f "$_f" ]; then
    _err "WL-1: arquivo ausente: $_f"
  fi
done

if [ "$ERRORS" -gt 0 ]; then
  printf 'validate-panel-workspace-lockstep: %d erro(s), %d aviso(s)\n' "$ERRORS" "$WARNINGS" >&2
  exit 1
fi

# WL-2: JSON parseavel
for _f in "$ROOT_PJ" "$SERVER_PJ" "$WEB_PJ" "$SHARED_PJ" "$LOCK"; do
  if ! jq -e . "$_f" >/dev/null 2>&1; then
    _err "WL-2: JSON invalido: $_f"
  fi
done

if [ "$ERRORS" -gt 0 ]; then
  printf 'validate-panel-workspace-lockstep: %d erro(s), %d aviso(s)\n' "$ERRORS" "$WARNINGS" >&2
  exit 1
fi

V_ROOT=$(jq -r '.version // ""' "$ROOT_PJ")
V_SERVER=$(jq -r '.version // ""' "$SERVER_PJ")
V_WEB=$(jq -r '.version // ""' "$WEB_PJ")
V_SHARED=$(jq -r '.version // ""' "$SHARED_PJ")

# WL-3: os 4 package.json em lockstep (referencia = panel/package.json)
[ "$V_SERVER" = "$V_ROOT" ] || _err "WL-3: apps/server/package.json version '$V_SERVER' != panel/package.json version '$V_ROOT'"
[ "$V_WEB" = "$V_ROOT" ]    || _err "WL-3: apps/web/package.json version '$V_WEB' != panel/package.json version '$V_ROOT'"
[ "$V_SHARED" = "$V_ROOT" ] || _err "WL-3: packages/shared-types/package.json version '$V_SHARED' != panel/package.json version '$V_ROOT'"

# WL-4: package-lock.json em lockstep
LOCKFILE_VERSION=$(jq -r '.lockfileVersion // ""' "$LOCK")
if [ "$LOCKFILE_VERSION" != "3" ]; then
  _warn "WL-4: package-lock.json lockfileVersion='$LOCKFILE_VERSION' (esperado 3); checagem de lockstep assume o layout .packages[\"<workspace>\"] de lockfileVersion 3"
fi

LOCK_TOP_VERSION=$(jq -r '.version // ""' "$LOCK")
LOCK_ROOT_PKG_VERSION=$(jq -r '.packages[""].version // ""' "$LOCK")
LOCK_SERVER_VERSION=$(jq -r '.packages["apps/server"].version // ""' "$LOCK")
LOCK_WEB_VERSION=$(jq -r '.packages["apps/web"].version // ""' "$LOCK")
LOCK_SHARED_VERSION=$(jq -r '.packages["packages/shared-types"].version // ""' "$LOCK")

[ "$LOCK_TOP_VERSION" = "$V_ROOT" ]      || _err "WL-4: package-lock.json .version '$LOCK_TOP_VERSION' != panel/package.json version '$V_ROOT'"
[ "$LOCK_ROOT_PKG_VERSION" = "$V_ROOT" ] || _err "WL-4: package-lock.json .packages[\"\"].version '$LOCK_ROOT_PKG_VERSION' != panel/package.json version '$V_ROOT'"
[ "$LOCK_SERVER_VERSION" = "$V_ROOT" ]   || _err "WL-4: package-lock.json .packages[\"apps/server\"].version '$LOCK_SERVER_VERSION' != panel/package.json version '$V_ROOT'"
[ "$LOCK_WEB_VERSION" = "$V_ROOT" ]      || _err "WL-4: package-lock.json .packages[\"apps/web\"].version '$LOCK_WEB_VERSION' != panel/package.json version '$V_ROOT'"
[ "$LOCK_SHARED_VERSION" = "$V_ROOT" ]   || _err "WL-4: package-lock.json .packages[\"packages/shared-types\"].version '$LOCK_SHARED_VERSION' != panel/package.json version '$V_ROOT'"

# WL-5: lockstep com a tag SemVer do repositorio unificado (condicional)
if [ -n "$VERSION" ]; then
  if [ "$V_ROOT" != "$VERSION" ]; then
    if [ "$STRICT" = "1" ]; then
      _err "WL-5: panel/package.json version '$V_ROOT' != --version '$VERSION'"
    else
      _warn "WL-5: panel/package.json version '$V_ROOT' != --version '$VERSION' (fora de release, apenas aviso)"
    fi
  fi
else
  _warn "WL-5: --version nao informado, lockstep com a tag de release pulado"
fi

if [ "$ERRORS" -gt 0 ]; then
  printf 'validate-panel-workspace-lockstep: %d erro(s), %d aviso(s)\n' "$ERRORS" "$WARNINGS" >&2
  exit 1
fi
printf 'validate-panel-workspace-lockstep: OK (%d aviso(s))\n' "$WARNINGS" >&2
exit 0
