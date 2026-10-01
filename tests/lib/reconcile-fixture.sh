#!/bin/sh
# reconcile-fixture.sh — helper de teste da skill reconcile-docs.
# Copia tests/fixtures/reconcile-docs/ para um diretorio temporario, com ou
# sem `git init` (uso exclusivo de teste; o `git` da skill vive so em
# git-probe.sh).
#
# Uso (a partir de um test file com TESTS_ROOT definido):
#   . "$TESTS_ROOT/lib/reconcile-fixture.sh"
#   rd_make_fixture git      # ou: nogit
#   -> imprime o caminho do diretorio criado; exporta nada.
#
# Sem dependencia de bash: POSIX sh, mktemp portavel (-d com template).

rd_make_fixture() {
  _rd_mode=${1:-git}
  _rd_src="${TESTS_ROOT:?TESTS_ROOT nao definido}/fixtures/reconcile-docs"
  [ -d "$_rd_src" ] || { printf 'reconcile-fixture: fixture ausente: %s\n' "$_rd_src" >&2; return 2; }
  _rd_dir=$(mktemp -d "${TMPDIR:-/tmp}/reconcile-docs.XXXXXX") || return 2
  cp -R "$_rd_src"/. "$_rd_dir"/ || return 2
  if [ "$_rd_mode" = git ]; then
    (
      cd "$_rd_dir" &&
      git init -q . &&
      git add -A . &&
      git -c user.name=fixture -c user.email=fixture@example.invalid \
        -c commit.gpgsign=false commit -q -m "fixture" 
    ) >/dev/null 2>&1 || return 2
  fi
  printf '%s\n' "$_rd_dir"
}
