#!/bin/sh
# test_scaffold.sh — cobre plugins/cstk/skills/initialize-docs/scripts/scaffold.sh.
#
# Contrato:
#   scaffold.sh                   # cria docs/ em CWD
#   scaffold.sh --dir=PATH        # cria estrutura em PATH
#   scaffold.sh --dry-run         # mostra plano, nao escreve
#   scaffold.sh --force           # sobrescreve READMEs existentes
#   Exit: 0 sucesso, 2 argumento invalido, 1+ falha de escrita.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/initialize-docs/scripts/scaffold.sh"

# Os 9 diretorios top-level esperados (convencao do toolkit).
_TOP_DIRS="01-briefing-discovery 02-requisitos-casos-uso 03-modelagem-dados 04-arquitetura-sistema 05-definicao-apis 06-ui-ux-design 07-plano-testes 08-operacoes 09-entregaveis"

# ==== 3.4.1 criacao em dir novo ====

scenario_criacao_em_dir_novo() {
  _target="$TMPDIR_TEST/docs"
  assert_exit 0 sh "$SCRIPT" "--dir=$_target" || return 1
  for _d in $_TOP_DIRS; do
    if [ ! -d "$_target/$_d" ]; then
      _fail "scenario_criacao_em_dir_novo" "diretorio esperado ausente: $_d"
      return 1
    fi
  done
}

# ==== 3.4.2 dry-run — nao cria nada ====

scenario_dry_run() {
  _target="$TMPDIR_TEST/docs_dryrun"
  assert_exit 0 sh "$SCRIPT" "--dir=$_target" "--dry-run" || return 1
  # Em dry-run, o stdout deve conter as acoes planejadas.
  assert_stdout_contains "[dry-run]" || return 1
  # E o diretorio NAO deve ter sido criado.
  if [ -d "$_target" ]; then
    _fail "scenario_dry_run" "--dry-run criou $_target; deveria ter apenas imprimido o plano"
    return 1
  fi
}

# ==== 3.4.3 idempotente — rodar duas vezes nao quebra ====

scenario_idempotente() {
  _target="$TMPDIR_TEST/docs_idem"
  assert_exit 0 sh "$SCRIPT" "--dir=$_target" || return 1
  # Snapshot do conteudo apos primeira execucao
  _snap1=$(find "$_target" -type f | sort | xargs md5 2>/dev/null)
  # Segunda execucao — sem --force
  assert_exit 0 sh "$SCRIPT" "--dir=$_target" || return 1
  # Conteudo deve ser IDENTICO (nao sobrescrito)
  _snap2=$(find "$_target" -type f | sort | xargs md5 2>/dev/null)
  if [ "$_snap1" != "$_snap2" ]; then
    _fail "scenario_idempotente" "conteudo mudou entre execucoes consecutivas (deveria ser idempotente)"
    return 1
  fi
}

# ==== 3.4.4 --force sobrescreve READMEs modificados ====

scenario_force_sobrescreve() {
  _target="$TMPDIR_TEST/docs_force"
  # Primeira execucao cria estrutura completa.
  assert_exit 0 sh "$SCRIPT" "--dir=$_target" || return 1
  _readme="$_target/01-briefing-discovery/README.md"
  if [ ! -f "$_readme" ]; then
    _fail "scenario_force_sobrescreve" "README esperado nao foi criado pela primeira execucao: $_readme"
    return 1
  fi
  # Modifica o README para introduzir conteudo detectavel.
  printf 'USER_MODIFIED_MARKER\n' > "$_readme"
  # Sem --force, nao deve sobrescrever (idempotente).
  assert_exit 0 sh "$SCRIPT" "--dir=$_target" || return 1
  if ! grep -q "USER_MODIFIED_MARKER" "$_readme"; then
    _fail "scenario_force_sobrescreve" "README foi sobrescrito sem --force (deveria ser preservado)"
    return 1
  fi
  # Com --force, DEVE sobrescrever.
  assert_exit 0 sh "$SCRIPT" "--dir=$_target" "--force" || return 1
  if grep -q "USER_MODIFIED_MARKER" "$_readme"; then
    _fail "scenario_force_sobrescreve" "--force nao sobrescreveu o README"
    return 1
  fi
}

# ==== 3.4.5 sem permissao de escrita ====

scenario_sem_permissao_escrita() {
  _parent="$TMPDIR_TEST/readonly"
  mkdir -p "$_parent" || return 2
  chmod 555 "$_parent" || return 2
  # Tenta criar estrutura dentro do dir read-only. Scaffold tem set -eu,
  # entao mkdir falhando abortaria o script com exit != 0.
  capture sh "$SCRIPT" "--dir=$_parent/docs" || return 2
  # Restaura permissoes para o trap de limpeza conseguir remover.
  chmod 755 "$_parent" || :
  if [ "$_CAPTURED_EXIT" -eq 0 ]; then
    _fail "scenario_sem_permissao_escrita" "esperado exit != 0 em dir read-only, obtido 0"
    return 1
  fi
  # O dir final nao deve existir.
  if [ -d "$_parent/docs" ]; then
    _fail "scenario_sem_permissao_escrita" "estrutura foi criada apesar de readonly"
    return 1
  fi
}

# ==== 3.4.6 assert_no_side_effect — nada vazou para fora do tmpdir ====

scenario_sem_vazamento_de_arquivos() {
  # Executa scaffold dentro do tmpdir. Depois checa que o repo git nao teve
  # nenhum arquivo novo ou modificado (assert_no_side_effect usa git status).
  _target="$TMPDIR_TEST/docs_iso"
  assert_exit 0 sh "$SCRIPT" "--dir=$_target" || return 1
  assert_no_side_effect || return 1
}

run_all_scenarios
