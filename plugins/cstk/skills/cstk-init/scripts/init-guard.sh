#!/bin/sh
# init-guard.sh — guarda de escrita, varredura de segredos e migracao da skill cstk-init
# (feature cstk-init, tarefa 4.3).
#
# Contrato: SKILL.md ("Ciclo de escrita") e references/write-policy.md.
#
#   init-guard.sh check   --root <dir> --path <rel> --op <create|amend|migrate> [--confirmed]
#   init-guard.sh scan    --file <path> [--catalog-root <dir-de-skills>]
#   init-guard.sh scan    --probe [--catalog-root <dir-de-skills>]
#   init-guard.sh migrate --root <dir> --confirmed
#
# stdout / exit:
#   check   ALLOW<TAB><path>                       exit 0
#           DENY<TAB><path><TAB><reason>           exit 3
#           reason: outside-root | symlink-escape | not-allowlisted | exists | unconfirmed
#   scan    SCAN<TAB>clean | secret-found | unavailable      exit 0 | 3 | 4
#   --probe SCAN<TAB>available | unavailable                 exit 0 | 4
#   migrate MIGRATED<TAB><origem><TAB><destino> (exit 0) | DENY<TAB><path><TAB><reason> (exit 3)
#
# FAIL-CLOSED: erro do proprio mecanismo (raiz inexistente, arquivo ilegivel, argumento
# invalido) NUNCA produz ALLOW/clean — termina com exit != 0 (1 erro, 2 uso, 4 scanner).
#
# Seguranca:
#   - o caminho recebido e DADO hostil: `..`, caminho absoluto, `.`/componente vazio, TAB,
#     newline, barra final e qualquer symlink em QUALQUER componente sao negados;
#   - a resolucao nao usa `realpath`: a raiz e fixada com `cd -P`/`pwd -P` e cada componente
#     do caminho e testado com `-L` (se nenhum componente e symlink, o caminho fisico e o
#     lexical sob a raiz fisica);
#   - os matches do scanner NUNCA vao para stdout nem stderr (FR-024): o stderr do
#     `secrets-filter.sh check` (que contem os matches) e descartado;
#   - TOCTOU entre `check` e a escrita e risco aceito (security CHK017, dec-018);
#   - o guarda NAO impede um Write/Edit que o modelo faca sem consulta-lo: a imposicao e
#     PROCEDIMENTAL (FR-026, dec-026 D1=c).
#
# `migrate` e o UNICO subcomando que altera o sistema de arquivos: `mv` da origem fixa
# docs/01-briefing-discovery/briefing.md para o destino fixo docs/briefing.md (FR-032),
# validando confinamento por conta propria (sem depender de `check` previo).

set -eu
LC_ALL=C
export LC_ALL

TAB=$(printf '\t')
NL='
'

MIGRATE_SRC="docs/01-briefing-discovery/briefing.md"
MIGRATE_DST="docs/briefing.md"

_usage() {
  cat >&2 <<'EOF'
uso:
  init-guard.sh check   --root <dir> --path <rel> --op <create|amend|migrate> [--confirmed]
  init-guard.sh scan    --file <path> [--catalog-root <dir-de-skills>]
  init-guard.sh scan    --probe [--catalog-root <dir-de-skills>]
  init-guard.sh migrate --root <dir> --confirmed
EOF
}

_die_usage() {
  printf 'init-guard: %s\n' "$1" >&2
  _usage
  exit 2
}

# _printable <s> — substitui TAB/newline por `?` para nunca quebrar o TSV de saida.
_printable() {
  printf '%s' "$1" | tr '\t\n\r' '???'
}

_deny() {
  printf 'DENY\t%s\t%s\n' "$(_printable "$1")" "$2"
  exit 3
}

# ---------------------------------------------------------------- validacao de caminho

# _valid_slug <s> — kebab minusculo; nunca `-` inicial, `_`, `.` ou barra.
_valid_slug() {
  case "$1" in
    ''|-*|*[!a-z0-9-]*) return 1 ;;
  esac
  return 0
}

# _is_allowlisted <componentes...> — allowlist de 5 caminhos (contrato §6).
_is_allowlisted() {
  case $# in
    2)
      [ "$1" = docs ] || return 1
      [ "$2" = briefing.md ] || [ "$2" = constitution.md ] || return 1
      return 0 ;;
    4)
      [ "$1" = docs ] && [ "$2" = specs ] || return 1
      _valid_slug "$3" || return 1
      [ "$3" != current ] || return 1
      [ "$4" = spec.md ] || [ "$4" = data-model.md ] || return 1
      return 0 ;;
    5)
      [ "$1" = docs ] && [ "$2" = specs ] && [ "$4" = checklists ] || return 1
      _valid_slug "$3" || return 1
      [ "$3" != current ] || return 1
      case "$5" in *.md) ;; *) return 1 ;; esac
      _valid_slug "${5%.md}" || return 1
      return 0 ;;
  esac
  return 1
}

# _has_symlink_component <abs-root> <componentes...> — 0 se algum componente existente e symlink.
_has_symlink_component() {
  _cur=$1
  shift
  for _c in "$@"; do
    _cur="$_cur/$_c"
    if [ -L "$_cur" ]; then
      return 0
    fi
  done
  return 1
}

# _abs_root <dir> — raiz fisica ou aborta (fail-closed).
_abs_root() {
  [ -n "$1" ] || _die_usage "--root obrigatorio"
  [ -d "$1" ] || { printf 'init-guard: raiz inexistente: %s\n' "$1" >&2; exit 1; }
  cd -P -- "$1" 2>/dev/null && pwd -P || {
    printf 'init-guard: nao foi possivel resolver a raiz: %s\n' "$1" >&2; exit 1; }
}

# ---------------------------------------------------------------- check

cmd_check() {
  _root=$1; _rel=$2; _op=$3; _confirmed=$4
  [ -n "$_rel" ] || _die_usage "check exige --path"
  case "$_op" in
    create|amend|migrate) ;;
    '') _die_usage "check exige --op" ;;
    *) _die_usage "--op invalido: $_op (create|amend|migrate)" ;;
  esac
  _abs=$(_abs_root "$_root") || exit $?

  case "$_rel" in
    *"$TAB"*|*"$NL"*) _deny "$_rel" not-allowlisted ;;
    /*) _deny "$_rel" outside-root ;;
  esac

  _oldifs=$IFS
  IFS=/
  set -f
  # shellcheck disable=SC2086
  set -- $_rel
  set +f
  IFS=$_oldifs

  # `..` em qualquer componente: sai da raiz (checado antes de qualquer outra regra)
  for _c in "$@"; do
    [ "$_c" != ".." ] || _deny "$_rel" outside-root
  done

  if _has_symlink_component "$_abs" "$@"; then
    _deny "$_rel" symlink-escape
  fi

  # `.`/componente vazio (//) e barra final nao sao normalizados: fora da allowlist
  for _c in "$@"; do
    case "$_c" in
      ''|.) _deny "$_rel" not-allowlisted ;;
    esac
  done
  case "$_rel" in */) _deny "$_rel" not-allowlisted ;; esac

  if [ "$_op" = migrate ]; then
    [ "$_rel" = "$MIGRATE_SRC" ] || _deny "$_rel" not-allowlisted
    [ -f "$_abs/$MIGRATE_SRC" ] || _deny "$_rel" not-allowlisted
    if [ -e "$_abs/$MIGRATE_DST" ] || [ -L "$_abs/$MIGRATE_DST" ]; then
      _deny "$_rel" exists
    fi
    [ "$_confirmed" = 1 ] || _deny "$_rel" unconfirmed
    printf 'ALLOW\t%s\n' "$_rel"
    return 0
  fi

  _is_allowlisted "$@" || _deny "$_rel" not-allowlisted

  if [ "$_op" = create ]; then
    if [ -e "$_abs/$_rel" ] || [ -L "$_abs/$_rel" ]; then
      _deny "$_rel" exists
    fi
  else
    [ "$_confirmed" = 1 ] || _deny "$_rel" unconfirmed
  fi
  printf 'ALLOW\t%s\n' "$_rel"
  return 0
}

# ---------------------------------------------------------------- scan

# _scanner_path <catalog-root> — caminho do secrets-filter.sh (mesma raiz de catalogo da skill).
_scanner_path() {
  printf '%s/agente-00c-runtime/scripts/secrets-filter.sh' "$1"
}

_default_catalog_root() {
  _d=$(dirname -- "$0")
  cd -P -- "$_d/../.." 2>/dev/null && pwd -P || printf ''
}

# _run_scanner <scanner> <stdin-file> — imprime o exit do `secrets-filter.sh check`
# (stdout/stderr do scanner descartados: os matches nunca saem deste script).
_run_scanner() {
  _rc=0
  sh "$1" check < "$2" >/dev/null 2>&1 || _rc=$?
  printf '%s' "$_rc"
}

cmd_scan() {
  _file=$1; _probe=$2; _croot=$3
  if [ -z "$_croot" ]; then
    _croot=$(_default_catalog_root)
  fi
  _scanner=$(_scanner_path "$_croot")

  if [ "$_probe" = 1 ]; then
    [ -f "$_scanner" ] && [ -r "$_scanner" ] || { printf 'SCAN\tunavailable\n'; exit 4; }
    _tmp=$(mktemp "${TMPDIR:-/tmp}/init-guard-probe.XXXXXX") || { printf 'SCAN\tunavailable\n'; exit 4; }
    # amostra limpa deve passar (exit 0) e amostra sintetica com segredo deve ser detectada
    # (exit 1): um scanner quebrado ou "sempre limpo" e indisponivel (fail-closed).
    printf 'texto simples sem segredo\n' > "$_tmp"
    _clean=$(_run_scanner "$_scanner" "$_tmp")
    printf 'password: FIXTURE_FAKE_PROBE_0123456789\n' > "$_tmp"
    _dirty=$(_run_scanner "$_scanner" "$_tmp")
    rm -f "$_tmp"
    if [ "$_clean" = 0 ] && [ "$_dirty" = 1 ]; then
      printf 'SCAN\tavailable\n'
      return 0
    fi
    printf 'SCAN\tunavailable\n'
    exit 4
  fi

  [ -n "$_file" ] || _die_usage "scan exige --file ou --probe"
  if [ ! -f "$_file" ] || [ ! -r "$_file" ]; then
    printf 'init-guard: arquivo inexistente ou ilegivel: %s\n' "$(_printable "$_file")" >&2
    exit 1
  fi
  if [ ! -f "$_scanner" ] || [ ! -r "$_scanner" ]; then
    printf 'SCAN\tunavailable\n'
    exit 4
  fi
  case "$(_run_scanner "$_scanner" "$_file")" in
    0) printf 'SCAN\tclean\n'; return 0 ;;
    1) printf 'SCAN\tsecret-found\n'; exit 3 ;;
    *) printf 'SCAN\tunavailable\n'; exit 4 ;;
  esac
}

# ---------------------------------------------------------------- migrate

cmd_migrate() {
  _root=$1; _confirmed=$2
  _abs=$(_abs_root "$_root") || exit $?

  # confinamento proprio: nenhum componente de origem/destino pode ser symlink
  # shellcheck disable=SC2086
  if _has_symlink_component "$_abs" docs 01-briefing-discovery briefing.md \
    || _has_symlink_component "$_abs" docs briefing.md; then
    _deny "$MIGRATE_SRC" symlink-escape
  fi
  [ -f "$_abs/$MIGRATE_SRC" ] || _deny "$MIGRATE_SRC" not-allowlisted
  if [ -e "$_abs/$MIGRATE_DST" ] || [ -L "$_abs/$MIGRATE_DST" ]; then
    _deny "$MIGRATE_SRC" exists
  fi
  [ "$_confirmed" = 1 ] || _deny "$MIGRATE_SRC" unconfirmed

  mv -- "$_abs/$MIGRATE_SRC" "$_abs/$MIGRATE_DST" || {
    printf 'init-guard: falha ao mover o briefing legado\n' >&2; exit 1; }
  printf 'MIGRATED\t%s\t%s\n' "$MIGRATE_SRC" "$MIGRATE_DST"
  return 0
}

# ---------------------------------------------------------------- main

[ $# -ge 1 ] || { _usage; exit 2; }
_sub=$1
shift

_root=""; _path=""; _op=""; _confirmed=0
_file=""; _probe=0; _croot=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || _die_usage "--root exige valor"; _root=$2; shift 2 ;;
    --path) [ $# -ge 2 ] || _die_usage "--path exige valor"; _path=$2; shift 2 ;;
    --op) [ $# -ge 2 ] || _die_usage "--op exige valor"; _op=$2; shift 2 ;;
    --file) [ $# -ge 2 ] || _die_usage "--file exige valor"; _file=$2; shift 2 ;;
    --catalog-root) [ $# -ge 2 ] || _die_usage "--catalog-root exige valor"; _croot=$2; shift 2 ;;
    --confirmed) _confirmed=1; shift ;;
    --probe) _probe=1; shift ;;
    -h|--help) _usage 2>&1; exit 0 ;;
    *) _die_usage "argumento desconhecido: $1" ;;
  esac
done

case "$_sub" in
  check) cmd_check "$_root" "$_path" "$_op" "$_confirmed" ;;
  scan) cmd_scan "$_file" "$_probe" "$_croot" ;;
  migrate) cmd_migrate "$_root" "$_confirmed" ;;
  -h|--help) _usage 2>&1; exit 0 ;;
  *) _die_usage "subcomando desconhecido: $_sub" ;;
esac
