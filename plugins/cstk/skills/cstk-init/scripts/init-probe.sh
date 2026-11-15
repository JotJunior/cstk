#!/bin/sh
# init-probe.sh — sondagem deterministica da skill cstk-init (feature cstk-init, tarefa 4.1).
#
# Subcomandos (contrato: SKILL.md §1 e §2):
#   preflight --root <dir>      ROOT / WRITE / VCS; exit 0 se WRITE ok, 3 se negado
#   artifacts --root <dir>      estado de briefing / constitution / specs ativas
#   version   --skill-dir <dir> versao do cstk instalado (plugin.json > manifest > unknown)
#
# Unico script da skill que invoca `git` (carve-out 1.1.0), so em `preflight`, com
# GIT_OPTIONAL_LOCKS=0 e core.fsmonitor=false. `git` ausente/falha = VCS none.
# Seam de teste: INIT_PROBE_GIT_BIN (default `git`) permite simular a ausencia do git
# sem manipular o PATH.
#
# Nenhum acesso de rede; nenhuma escrita; caminhos do projeto-alvo sao tratados como dado
# (sempre entre aspas, `--` antes de caminhos, sem eval/source). Conteudo de arquivo do
# projeto-alvo so e lido para a versao do rodape da constitution (e nunca via symlink).
#
# Exit: 0 sucesso; 1 erro geral (ex.: raiz inexistente em `artifacts`); 2 uso incorreto;
#       3 escrita negada (`preflight`).

set -eu
LC_ALL=C
export LC_ALL

TAB=$(printf '\t')
NL='
'

_usage() {
  cat >&2 <<'EOF'
uso:
  init-probe.sh preflight --root <dir>
  init-probe.sh artifacts --root <dir>
  init-probe.sh version   --skill-dir <dir>
EOF
}

_die_usage() {
  printf 'init-probe: %s\n' "$1" >&2
  _usage
  exit 2
}

# _has_ctl <string> — 0 se contem TAB ou newline (quebraria o TSV de saida).
_has_ctl() {
  case "$1" in
    *"$TAB"*|*"$NL"*) return 0 ;;
  esac
  return 1
}

# ---------------------------------------------------------------- preflight

cmd_preflight() {
  _root="$1"
  [ -n "$_root" ] || _die_usage "preflight exige --root"
  if [ ! -e "$_root" ]; then
    printf 'ROOT\t%s\nWRITE\tdenied-missing\nVCS\tnone\n' "$_root"
    return 3
  fi
  if [ ! -d "$_root" ]; then
    printf 'ROOT\t%s\nWRITE\tdenied-not-dir\nVCS\tnone\n' "$_root"
    return 3
  fi
  _abs=$(cd -P -- "$_root" 2>/dev/null && pwd -P) || {
    printf 'ROOT\t%s\nWRITE\tdenied-readonly\nVCS\tnone\n' "$_root"
    return 3
  }
  if [ ! -w "$_abs" ] || [ ! -x "$_abs" ]; then
    printf 'ROOT\t%s\nWRITE\tdenied-readonly\nVCS\tnone\n' "$_abs"
    return 3
  fi
  printf 'ROOT\t%s\nWRITE\tok\nVCS\t%s\n' "$_abs" "$(_vcs_state "$_abs")"
  return 0
}

# _vcs_state <abs-root> — git-clean | git-dirty | none (nunca falha; fail-safe = none).
_vcs_state() {
  _gbin=${INIT_PROBE_GIT_BIN:-git}
  command -v "$_gbin" >/dev/null 2>&1 || { printf 'none'; return 0; }
  (
    # variaveis do ambiente nao podem redirecionar o repositorio consultado
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR 2>/dev/null || :
    GIT_OPTIONAL_LOCKS=0
    export GIT_OPTIONAL_LOCKS
    cd -P -- "$1" 2>/dev/null || { printf 'none'; exit 0; }
    "$_gbin" -c core.fsmonitor=false rev-parse --is-inside-work-tree >/dev/null 2>&1 \
      || { printf 'none'; exit 0; }
    _out=$("$_gbin" -c core.fsmonitor=false status --porcelain -- . 2>/dev/null) \
      || { printf 'none'; exit 0; }
    if [ -n "$_out" ]; then printf 'git-dirty'; else printf 'git-clean'; fi
  )
}

# ---------------------------------------------------------------- artifacts

# _confined_file <abs-root> <rel> — 0 se <rel> e arquivo regular e o seu diretorio fisico
# (`cd -P`) esta dentro da raiz fisica (o symlink no ULTIMO componente continua contando como
# presente — so existencia, e a versao nunca e lida por ele, ver `_constitution_version`). Symlink de diretorio que escapa da raiz
# (ex.: `docs -> /fora`) faz o artefato contar como ausente: nada fora da raiz e sondado nem
# lido (FR-023).
_confined_file() {
  [ -f "$1/$2" ] || return 1
  _cf_d=$(cd -P -- "$(dirname -- "$1/$2")" 2>/dev/null && pwd -P) || return 1
  case "$_cf_d" in
    "$1"|"$1"/*) return 0 ;;
  esac
  return 1
}

# _constitution_version <file> — versao do rodape (`**Version**: X`) ou `-`.
# Nao le symlink (leitura confinada a arquivos reais da raiz — FR-023).
_constitution_version() {
  [ -f "$1" ] && [ ! -L "$1" ] || { printf -- '-'; return 0; }
  _v=$(sed -n 's/.*\*\*Version\*\*:[[:space:]]*\([0-9A-Za-z][0-9A-Za-z.+_-]*\).*/\1/p' "$1" 2>/dev/null | tail -n 1)
  [ -n "$_v" ] && printf '%s' "$_v" || printf -- '-'
}

cmd_artifacts() {
  _root="$1"
  [ -n "$_root" ] || _die_usage "artifacts exige --root"
  [ -d "$_root" ] || { printf 'init-probe: raiz inexistente: %s\n' "$_root" >&2; return 1; }
  _abs=$(cd -P -- "$_root" && pwd -P) || return 1

  _canon="docs/briefing.md"
  _legacy="docs/01-briefing-discovery/briefing.md"
  _has_c=0; _has_l=0
  _confined_file "$_abs" "$_canon" && _has_c=1
  _confined_file "$_abs" "$_legacy" && _has_l=1
  if [ "$_has_c" = 1 ] && [ "$_has_l" = 1 ]; then
    printf 'briefing\tboth\t%s,%s\t-\n' "$_canon" "$_legacy"
  elif [ "$_has_c" = 1 ]; then
    printf 'briefing\tcanonical\t%s\t-\n' "$_canon"
  elif [ "$_has_l" = 1 ]; then
    printf 'briefing\tlegacy\t%s\t-\n' "$_legacy"
  else
    printf 'briefing\tabsent\t-\t-\n'
  fi

  if _confined_file "$_abs" docs/constitution.md; then
    printf 'constitution\tpresent\tdocs/constitution.md\t%s\n' \
      "$(_constitution_version "$_abs/docs/constitution.md")"
  else
    printf 'constitution\tabsent\t-\t-\n'
  fi

  for _d in "$_abs"/docs/specs/*/; do
    [ -d "$_d" ] || continue
    _name=$(basename "$_d")
    case "$_name" in
      _archived|current) continue ;;
    esac
    _has_ctl "$_name" && continue
    _confined_file "$_abs" "docs/specs/$_name/spec.md" || continue
    printf 'spec\tpresent\tdocs/specs/%s/spec.md\t%s\n' "$_name" "$_name"
  done
  return 0
}

# ---------------------------------------------------------------- version

# _valid_version <s> — so caracteres de versao (nunca eco de conteudo arbitrario).
_valid_version() {
  case "$1" in
    ''|*[!0-9A-Za-z.+_-]*) return 1 ;;
  esac
  return 0
}

cmd_version() {
  _sd="$1"
  [ -n "$_sd" ] || _die_usage "version exige --skill-dir"
  # remove barras finais; basename = nome da skill no manifest
  while :; do
    case "$_sd" in
      */) _sd=${_sd%/} ;;
      *) break ;;
    esac
  done
  _skill=$(basename "$_sd")

  _pj="$_sd/../../.claude-plugin/plugin.json"
  if [ -f "$_pj" ]; then
    _v=$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$_pj" 2>/dev/null | head -n 1)
    if _valid_version "$_v"; then
      printf 'CSTK_VERSION\t%s\tplugin-json\n' "$_v"
      return 0
    fi
  fi

  _mf="$_sd/../.cstk-manifest"
  if [ -f "$_mf" ]; then
    _v=$(awk -F'\t' -v s="$_skill" '$1 == s && $1 !~ /^#/ { print $2; exit }' "$_mf" 2>/dev/null || :)
    if _valid_version "$_v"; then
      printf 'CSTK_VERSION\t%s\tmanifest\n' "$_v"
      return 0
    fi
  fi

  printf 'CSTK_VERSION\tunknown\tunknown\n'
  return 0
}

# ---------------------------------------------------------------- main

[ $# -ge 1 ] || { _usage; exit 2; }
_sub="$1"
shift

_root=""
_skill_dir=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      [ $# -ge 2 ] || _die_usage "--root exige valor"
      _root="$2"; shift 2 ;;
    --skill-dir)
      [ $# -ge 2 ] || _die_usage "--skill-dir exige valor"
      _skill_dir="$2"; shift 2 ;;
    -h|--help)
      _usage; exit 0 ;;
    *)
      _die_usage "argumento desconhecido: $1" ;;
  esac
done

case "$_sub" in
  preflight) cmd_preflight "$_root" ;;
  artifacts) cmd_artifacts "$_root" ;;
  version)   cmd_version "$_skill_dir" ;;
  -h|--help) _usage; exit 0 ;;
  *) _die_usage "subcomando desconhecido: $_sub" ;;
esac
