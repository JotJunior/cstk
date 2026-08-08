#!/bin/sh
# validate-plugin-manifests.sh — gate deterministico dos manifestos de
# plugin/marketplace do cstk.
#
# Ref: docs/specs/claude-plugin-packaging/contracts/plugin-artifacts.md
#      docs/specs/claude-plugin-packaging/tasks.md FASE 5.1.3/5.4
#
# Invariantes SEMPRE checados (independente de contexto release/nao-release):
#   MP-1  .claude-plugin/marketplace.json e cada plugin.json referenciado
#         sao JSON parseavel
#   MP-2  .plugins | length == 2  (FR-003 exige exatamente 2 entradas)
#   MP-3  cada .plugins[].source (string relativa) resolve para diretorio
#         existente no repo
#   MP-4  cada diretorio de source contem .claude-plugin/plugin.json
#   MP-6  .plugins[].name e unico
#
# Invariante condicional (mecanismo de lockstep, FR-003):
#   MP-5  .plugins[].version (marketplace) E .version (plugin.json) ==
#         --version informado.
#           - sem --version: MP-5 pulado (aviso, nada a comparar)
#           - com --version, sem --strict: mismatch = aviso
#           - com --version E --strict: mismatch = erro (uso: release.yml)
#
# HK-1..HK-5 (paridade/forma de plugins/cstk/hooks/hooks.json) NAO sao
# checados aqui: ja cobertos por tests/cstk/test_plugin-hooks-manifest.sh,
# que roda dentro de ./tests/run.sh — ja um pre-requisito bloqueante do
# release.yml (etapa "Run test suite"). Duplicar a checagem aqui seria
# redundante sem ganho de cobertura.
#
# Uso:
#   validate-plugin-manifests.sh [--version X.Y.Z] [--strict] [--repo-root DIR]
#
# Exit:
#   0  nenhum erro (podem existir avisos em stderr)
#   1  pelo menos um erro (MP-1..MP-4/MP-6 sempre; MP-5 so com --strict)
#   2  uso invalido / dependencia ausente (jq)

set -eu

REPO_ROOT="."
VERSION=""
STRICT=0

while [ $# -gt 0 ]; do
  case "$1" in
    --version)
      [ $# -ge 2 ] || { printf 'validate-plugin-manifests: --version exige valor\n' >&2; exit 2; }
      VERSION=$2
      shift 2
      ;;
    --strict)
      STRICT=1
      shift
      ;;
    --repo-root)
      [ $# -ge 2 ] || { printf 'validate-plugin-manifests: --repo-root exige valor\n' >&2; exit 2; }
      REPO_ROOT=$2
      shift 2
      ;;
    -h|--help)
      printf 'Uso: %s [--version X.Y.Z] [--strict] [--repo-root DIR]\n' "$(basename "$0")"
      exit 0
      ;;
    *)
      printf 'validate-plugin-manifests: argumento desconhecido: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

command -v jq >/dev/null 2>&1 || {
  printf 'validate-plugin-manifests: jq ausente no PATH\n' >&2
  exit 2
}

MARKETPLACE="$REPO_ROOT/.claude-plugin/marketplace.json"
ERRORS=0
WARNINGS=0

_err() { printf 'ERROR: %s\n' "$1" >&2; ERRORS=$((ERRORS + 1)); }
_warn() { printf 'WARN: %s\n' "$1" >&2; WARNINGS=$((WARNINGS + 1)); }

if [ ! -f "$MARKETPLACE" ]; then
  _err "marketplace.json ausente: $MARKETPLACE"
  exit 1
fi

# MP-1 (marketplace.json)
if ! jq -e . "$MARKETPLACE" >/dev/null 2>&1; then
  _err "MP-1: marketplace.json nao e JSON valido: $MARKETPLACE"
  printf 'validate-plugin-manifests: %d erro(s), %d aviso(s)\n' "$ERRORS" "$WARNINGS" >&2
  exit 1
fi

# MP-2
_count=$(jq '.plugins | length' "$MARKETPLACE")
if [ "$_count" != "2" ]; then
  _err "MP-2: marketplace.json .plugins deve ter exatamente 2 entradas (encontrado: $_count)"
fi

# MP-6: nomes unicos
_names_dup=$(jq -r '[.plugins[].name] | group_by(.) | map(select(length > 1)) | flatten | unique | .[]' "$MARKETPLACE" 2>/dev/null || true)
if [ -n "$_names_dup" ]; then
  _err "MP-6: marketplace.json nomes duplicados em .plugins[].name: $(printf '%s' "$_names_dup" | tr '\n' ' ')"
fi

# MP-3, MP-4, MP-1 (plugin.json), MP-5 — por entrada
_idx=0
while [ "$_idx" -lt "$_count" ]; do
  _name=$(jq -r --argjson i "$_idx" '.plugins[$i].name' "$MARKETPLACE")
  _source=$(jq -r --argjson i "$_idx" '.plugins[$i].source' "$MARKETPLACE")
  _mkt_version=$(jq -r --argjson i "$_idx" '.plugins[$i].version // ""' "$MARKETPLACE")

  case "$_source" in
    ./*) _rel=${_source#./} ;;
    *) _rel=$_source ;;
  esac
  _abs="$REPO_ROOT/$_rel"

  if [ ! -d "$_abs" ]; then
    _err "MP-3: marketplace.json source '$_source' (plugin '$_name') nao resolve para diretorio existente"
  else
    _plugin_json="$_abs/.claude-plugin/plugin.json"
    if [ ! -f "$_plugin_json" ]; then
      _err "MP-4: marketplace.json source '$_source' (plugin '$_name') nao contem .claude-plugin/plugin.json"
    elif ! jq -e . "$_plugin_json" >/dev/null 2>&1; then
      _err "MP-1: plugin.json nao e JSON valido: $_plugin_json"
    else
      _pj_version=$(jq -r '.version // ""' "$_plugin_json")
      if [ -n "$VERSION" ]; then
        if [ "$_mkt_version" != "$VERSION" ]; then
          if [ "$STRICT" = "1" ]; then
            _err "MP-5: marketplace.json plugin '$_name' version '$_mkt_version' != --version '$VERSION'"
          else
            _warn "MP-5: marketplace.json plugin '$_name' version '$_mkt_version' != --version '$VERSION' (fora de release, apenas aviso)"
          fi
        fi
        if [ "$_pj_version" != "$VERSION" ]; then
          if [ "$STRICT" = "1" ]; then
            _err "MP-5: plugin.json ($_plugin_json) version '$_pj_version' != --version '$VERSION'"
          else
            _warn "MP-5: plugin.json ($_plugin_json) version '$_pj_version' != --version '$VERSION' (fora de release, apenas aviso)"
          fi
        fi
      else
        _warn "MP-5: --version nao informado, lockstep de versao pulado para plugin '$_name'"
      fi
    fi
  fi
  _idx=$((_idx + 1))
done

if [ "$ERRORS" -gt 0 ]; then
  printf 'validate-plugin-manifests: %d erro(s), %d aviso(s)\n' "$ERRORS" "$WARNINGS" >&2
  exit 1
fi
printf 'validate-plugin-manifests: OK (%d aviso(s))\n' "$WARNINGS" >&2
exit 0
