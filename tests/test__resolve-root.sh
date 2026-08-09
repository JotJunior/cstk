#!/bin/sh
# test__resolve-root.sh — cobre _resolve-root.sh (resolucao dual-path da
# raiz de agente-00c-runtime: classico vs plugin nativo do Claude Code).
# Ref: docs/specs/_archived/2026-08-08-claude-plugin-packaging/contracts/plugin-artifacts.md
#      Artefato 5; tasks.md 3.1.5.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

RESOLVE_ROOT_LIB="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/_resolve-root.sh"

# _rr_mkroot DIR -> cria um candidato de raiz VALIDO (contem scripts/ e
# hooks/ — layout real de agente-00c-runtime/{hooks,scripts}). O hooks/ e
# necessario para os cenarios de sibling: `dirname $0` precisa resolver
# para um diretorio que EXISTE antes de `_rr_sibling_root` conseguir
# subir para o pai via `cd "$dir/.." && pwd`.
_rr_mkroot() {
  mkdir -p "$1/scripts" "$1/hooks"
}

# _rr_mkroot_no_scripts DIR -> cria um candidato INVALIDO (existe, sem scripts/).
_rr_mkroot_no_scripts() {
  mkdir -p "$1"
}

# _rr_call FAKE_ZERO MODE -> invoca resolve_runtime_root num subshell POSIX
# `sh` isolado, com $0=FAKE_ZERO (2o arg de `sh -c CODE NAME [ARGS]`).
# Preenche _CAPTURED_STDOUT/_CAPTURED_STDERR/_CAPTURED_EXIT via `capture`.
_rr_call() {
  _rr_fake_zero="$1"
  _rr_mode="$2"
  capture sh -c '. "$1"; resolve_runtime_root "$2"' "$_rr_fake_zero" "$RESOLVE_ROOT_LIB" "$_rr_mode"
}

# _rr_assert_exit EXPECTED -> compara _CAPTURED_EXIT (ja preenchido por
# _rr_call) sem re-executar nada — assert_exit do harness re-executaria o
# comando, o que quebraria a captura do subshell isolado.
_rr_assert_exit() {
  if [ "$_CAPTURED_EXIT" != "$1" ]; then
    _fail "_rr_assert_exit" "esperado exit=$1, obtido exit=$_CAPTURED_EXIT"
    return 1
  fi
  return 0
}

# ---- Ordem A (default): plugin -> sibling -> classico -> erro ----

scenario_ordem_a_plugin_vence_quando_todos_validos() {
  _plugin="$TMPDIR_TEST/plugin-root"
  _sibling="$TMPDIR_TEST/sib/agente-00c-runtime"
  _home="$TMPDIR_TEST/home"
  _rr_mkroot "$_plugin/skills/agente-00c-runtime"
  _rr_mkroot "$_sibling"
  _rr_mkroot "$_home/.claude/skills/agente-00c-runtime"

  CLAUDE_PLUGIN_ROOT="$_plugin" HOME="$_home" \
    _rr_call "$_sibling/hooks/caller.sh" ""

  _rr_assert_exit 0 || return 1
  assert_stdout_contains "$_plugin/skills/agente-00c-runtime" || return 1
}

scenario_ordem_a_sibling_quando_plugin_indefinido() {
  _sibling="$TMPDIR_TEST/sib/agente-00c-runtime"
  _home="$TMPDIR_TEST/home"
  _rr_mkroot "$_sibling"
  _rr_mkroot "$_home/.claude/skills/agente-00c-runtime"

  CLAUDE_PLUGIN_ROOT="" HOME="$_home" \
    _rr_call "$_sibling/hooks/caller.sh" ""

  _rr_assert_exit 0 || return 1
  assert_stdout_contains "$_sibling" || return 1
}

scenario_ordem_a_classico_quando_plugin_e_sibling_invalidos() {
  _home="$TMPDIR_TEST/home"
  _rr_mkroot "$_home/.claude/skills/agente-00c-runtime"

  CLAUDE_PLUGIN_ROOT="$TMPDIR_TEST/nao-existe" HOME="$_home" \
    _rr_call "$TMPDIR_TEST/nao-existe-tambem/hooks/caller.sh" ""

  _rr_assert_exit 0 || return 1
  assert_stdout_contains "$_home/.claude/skills/agente-00c-runtime" || return 1
}

scenario_ordem_a_erro_diagnostico_quando_nenhum_resolve() {
  CLAUDE_PLUGIN_ROOT="$TMPDIR_TEST/nao-existe" HOME="$TMPDIR_TEST/tambem-nao-existe" \
    _rr_call "$TMPDIR_TEST/nem-este/hooks/caller.sh" ""

  _rr_assert_exit 1 || return 1
  if [ -n "$_CAPTURED_STDOUT" ]; then
    _fail "stdout_vazio_em_falha" "stdout deveria ser vazio em falha, got: $_CAPTURED_STDOUT"
    return 1
  fi
  assert_stderr_contains "CLAUDE_PLUGIN_ROOT" || return 1
  assert_stderr_contains "diretorio-irmao" || return 1
  assert_stderr_contains "HOME" || return 1
}

scenario_ordem_a_candidato_existe_sem_scripts_e_rejeitado() {
  # plugin existe mas sem scripts/ -> invalido -> cai para sibling
  _plugin_invalido="$TMPDIR_TEST/plugin-sem-scripts"
  _rr_mkroot_no_scripts "$_plugin_invalido/skills/agente-00c-runtime"
  _sibling="$TMPDIR_TEST/sib2/agente-00c-runtime"
  _rr_mkroot "$_sibling"

  CLAUDE_PLUGIN_ROOT="$_plugin_invalido" HOME="$TMPDIR_TEST/sem-home" \
    _rr_call "$_sibling/hooks/caller.sh" ""

  _rr_assert_exit 0 || return 1
  assert_stdout_contains "$_sibling" || return 1
}

# ---- Ordem B (strict): sibling -> plugin -> classico -> erro ----

scenario_ordem_b_sibling_vence_mesmo_com_plugin_valido() {
  _plugin="$TMPDIR_TEST/plugin-root-b"
  _sibling="$TMPDIR_TEST/sib-b/agente-00c-runtime"
  _rr_mkroot "$_plugin/skills/agente-00c-runtime"
  _rr_mkroot "$_sibling"

  CLAUDE_PLUGIN_ROOT="$_plugin" HOME="$TMPDIR_TEST/sem-home-b" \
    _rr_call "$_sibling/hooks/caller.sh" "strict"

  _rr_assert_exit 0 || return 1
  assert_stdout_contains "$_sibling" || return 1
  # invariante de seguranca F3: NAO pode retornar a raiz do plugin quando
  # o sibling e valido, mesmo com CLAUDE_PLUGIN_ROOT setada
  case "$_CAPTURED_STDOUT" in
    *"$_plugin"*)
      _fail "ordem_b_nao_vaza_para_plugin" "Ordem B vazou para o candidato de plugin com sibling valido presente: $_CAPTURED_STDOUT"
      return 1
      ;;
  esac
}

scenario_ordem_b_plugin_quando_sibling_invalido() {
  _plugin="$TMPDIR_TEST/plugin-root-b2"
  _rr_mkroot "$_plugin/skills/agente-00c-runtime"

  CLAUDE_PLUGIN_ROOT="$_plugin" HOME="$TMPDIR_TEST/sem-home-b2" \
    _rr_call "$TMPDIR_TEST/sib-invalido-b2/hooks/caller.sh" "strict"

  _rr_assert_exit 0 || return 1
  assert_stdout_contains "$_plugin/skills/agente-00c-runtime" || return 1
}

scenario_ordem_b_classico_quando_sibling_e_plugin_invalidos() {
  _home="$TMPDIR_TEST/home-b3"
  _rr_mkroot "$_home/.claude/skills/agente-00c-runtime"

  CLAUDE_PLUGIN_ROOT="$TMPDIR_TEST/plugin-invalido-b3" HOME="$_home" \
    _rr_call "$TMPDIR_TEST/sib-invalido-b3/hooks/caller.sh" "strict"

  _rr_assert_exit 0 || return 1
  assert_stdout_contains "$_home/.claude/skills/agente-00c-runtime" || return 1
}

scenario_ordem_b_erro_diagnostico_quando_nenhum_resolve() {
  CLAUDE_PLUGIN_ROOT="$TMPDIR_TEST/plugin-nao-existe-b4" HOME="$TMPDIR_TEST/home-nao-existe-b4" \
    _rr_call "$TMPDIR_TEST/sib-nao-existe-b4/hooks/caller.sh" "strict"

  _rr_assert_exit 1 || return 1
  if [ -n "$_CAPTURED_STDOUT" ]; then
    _fail "stdout_vazio_em_falha" "stdout deveria ser vazio em falha, got: $_CAPTURED_STDOUT"
    return 1
  fi
  assert_stderr_contains "modo=strict" || return 1
  assert_stderr_contains "diretorio-irmao" || return 1
}

# ---- Casos de borda comuns aos 2 modos ----

scenario_zero_vazio_nao_quebra_resolucao() {
  # $0 vazio (cenario extremo: candidato sibling nao resolve, mas o
  # classico continua funcionando normalmente)
  _home="$TMPDIR_TEST/home-zero-vazio"
  _rr_mkroot "$_home/.claude/skills/agente-00c-runtime"

  CLAUDE_PLUGIN_ROOT="" HOME="$_home" _rr_call "" ""

  _rr_assert_exit 0 || return 1
  assert_stdout_contains "$_home/.claude/skills/agente-00c-runtime" || return 1
}

scenario_stdout_e_path_absoluto_normalizado() {
  _sibling="$TMPDIR_TEST/sib-norm/agente-00c-runtime"
  _rr_mkroot "$_sibling"

  CLAUDE_PLUGIN_ROOT="" HOME="$TMPDIR_TEST/sem-home-norm" \
    _rr_call "$_sibling/hooks/../hooks/caller.sh" ""

  _rr_assert_exit 0 || return 1
  case "$_CAPTURED_STDOUT" in
    /*) : ;;
    *)
      _fail "stdout_absoluto" "stdout nao e path absoluto: $_CAPTURED_STDOUT"
      return 1
      ;;
  esac
  case "$_CAPTURED_STDOUT" in
    *".."*)
      _fail "stdout_normalizado" "stdout contem '..' residual (nao normalizado): $_CAPTURED_STDOUT"
      return 1
      ;;
  esac
}

run_all_scenarios
