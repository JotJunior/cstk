#!/bin/sh
# test_path-contains.sh — cobre global/skills/converge/scripts/path-contains.sh.
#
# Ref: docs/specs/skill-converge/tasks.md tarefa 2.1.5
#      docs/specs/skill-converge/contracts/converge-interfaces.md §6

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/global/skills/converge/scripts/path-contains.sh"

# ---------- Contido / fora do root ----------

scenario_dentro_do_root_existente_exit0() {
  _root="$TMPDIR_TEST/proj"
  mkdir -p "$_root/scripts"
  touch "$_root/scripts/foo.sh"
  capture "$SCRIPT" --root "$_root" --path "$_root/scripts/foo.sh"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "scripts/foo.sh" || return 1
}

scenario_fora_do_root_exit1() {
  _root="$TMPDIR_TEST/proj"
  _outside="$TMPDIR_TEST/outside"
  mkdir -p "$_root" "$_outside"
  touch "$_outside/evil.sh"
  capture "$SCRIPT" --root "$_root" --path "$_outside/evil.sh"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "FR-018" || return 1
}

scenario_path_igual_ao_root_exit0() {
  _root="$TMPDIR_TEST/proj"
  mkdir -p "$_root"
  capture "$SCRIPT" --root "$_root" --path "$_root"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_path_relativo_resolvido_contra_cwd() {
  _root="$TMPDIR_TEST/proj"
  mkdir -p "$_root/scripts"
  touch "$_root/scripts/foo.sh"
  capture env -i PATH="$PATH" HOME="$HOME" sh -c \
    "cd '$_root' && '$SCRIPT' --root '$_root' --path scripts/foo.sh"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "scripts/foo.sh" || return 1
}

# ---------- Erros de uso (exit 2) ----------

scenario_path_ausente_exit2() {
  _root="$TMPDIR_TEST/proj"
  mkdir -p "$_root"
  capture "$SCRIPT" --root "$_root"
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_sem_argumentos_exit2() {
  capture "$SCRIPT"
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_flag_desconhecida_exit2() {
  capture "$SCRIPT" --bogus x --path /tmp
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_root_explicito_inexistente_exit2() {
  capture "$SCRIPT" --root "$TMPDIR_TEST/nao-existe" --path "$TMPDIR_TEST/nao-existe/foo.sh"
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_help_exit0() {
  capture "$SCRIPT" --help
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "Uso:" || return 1
}

# ---------- Resolucao automatica de --root (tarefa 1.2) ----------

scenario_root_auto_via_git_diretorio() {
  _repo="$TMPDIR_TEST/repo"
  mkdir -p "$_repo/.git" "$_repo/sub/deeper"
  touch "$_repo/sub/deeper/file.sh"
  capture env -i PATH="$PATH" HOME="$HOME" sh -c \
    "cd '$_repo/sub/deeper' && '$SCRIPT' --path '$_repo/sub/deeper/file.sh'"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
}

scenario_root_auto_via_git_arquivo_worktree() {
  # Worktrees usam .git como ARQUIVO (gitdir: ...), nao diretorio.
  _repo="$TMPDIR_TEST/worktree-repo"
  mkdir -p "$_repo/sub"
  printf 'gitdir: /somewhere/else\n' > "$_repo/.git"
  touch "$_repo/sub/file.sh"
  capture env -i PATH="$PATH" HOME="$HOME" sh -c \
    "cd '$_repo/sub' && '$SCRIPT' --path '$_repo/sub/file.sh'"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
}

scenario_root_auto_via_constitution_fallback() {
  # Sem .git em nenhum ancestral, mas com docs/constitution.md.
  _proj="$TMPDIR_TEST/fakeproj"
  mkdir -p "$_proj/docs" "$_proj/sub"
  touch "$_proj/docs/constitution.md"
  touch "$_proj/sub/file.sh"
  capture env -i PATH="$PATH" HOME="$HOME" sh -c \
    "cd '$_proj/sub' && '$SCRIPT' --path '$_proj/sub/file.sh'"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "fakeproj/sub/file.sh" || return 1
}

scenario_root_auto_sem_marcador_abort_exit2() {
  # Diretorio isolado sem .git nem docs/constitution.md em nenhum ancestral
  # plausivel (dentro do tmpdir de teste, fora do repo real).
  _iso="$TMPDIR_TEST/isolated/a/b/c"
  mkdir -p "$_iso"
  capture env -i PATH="$PATH" HOME="$HOME" sh -c \
    "cd '$_iso' && '$SCRIPT' --path foo.sh"
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "root" || return 1
}

# ---------- Symlink escape (Scenario 16, SEC-2/CHK007) ----------

scenario_symlink_dentro_root_aponta_fora_alvo_existente_exit1() {
  _root="$TMPDIR_TEST/proj"
  _outside="$TMPDIR_TEST/victim"
  mkdir -p "$_root" "$_outside"
  ln -s "$_outside" "$_root/escape"
  capture "$SCRIPT" --root "$_root" --path "$_root/escape"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_symlink_dentro_root_cauda_inexistente_exit1() {
  # O symlink existe e resolve para fora; o arquivo final dentro do alvo
  # do symlink NAO existe ainda. Contencao MUST detectar mesmo assim
  # (canonicaliza o ancestral existente antes de recompor a cauda).
  _root="$TMPDIR_TEST/proj"
  _outside="$TMPDIR_TEST/victim"
  mkdir -p "$_root" "$_outside"
  ln -s "$_outside" "$_root/escape"
  capture "$SCRIPT" --root "$_root" --path "$_root/escape/nested/new-file.sh"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_symlink_dentro_root_aponta_para_dentro_exit0() {
  # Contraste: symlink que aponta para DENTRO do proprio root deve passar.
  _root="$TMPDIR_TEST/proj"
  mkdir -p "$_root/real"
  touch "$_root/real/file.sh"
  ln -s "$_root/real" "$_root/alias"
  capture "$SCRIPT" --root "$_root" --path "$_root/alias/file.sh"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
}

# ---------- Paths adversariais (SEC-1) ----------

scenario_adversarial_paths_nao_executam() {
  _root="$TMPDIR_TEST/proj"
  mkdir -p "$_root"

  capture "$SCRIPT" --root "$_root" --path '$(whoami)'
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit dolar-parenteses" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }

  capture "$SCRIPT" --root "$_root" --path '`id`'
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit backtick" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }

  capture "$SCRIPT" --root "$_root" --path '; rm -rf /tmp/should-not-exist-path-contains-marker'
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit semicolon" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }

  # Confirma que nada foi de fato executado (o path literal nao criou nem
  # apagou nada no filesystem real).
  if [ -e "/tmp/should-not-exist-path-contains-marker" ]; then
    _fail "side-effect" "adversarial path foi executado: marker existe"
    return 1
  fi

  assert_no_side_effect || return 1
}

scenario_glob_no_path_nao_expande() {
  # "*" no path deve permanecer LITERAL no path resolvido — nunca expandido
  # contra arquivos reais do disco (glob desabilitado via "set -f" na
  # normalizacao lexical, SEC-1). Se o "*" fosse expandido, um dos arquivos
  # "chamariz" abaixo apareceria no lugar dele na saida.
  _root="$TMPDIR_TEST/proj"
  mkdir -p "$_root/nonexistent"
  touch "$_root/nonexistent/candidate-a.txt" "$_root/nonexistent/candidate-b.txt"
  capture "$SCRIPT" --root "$_root" --path "$_root/nonexistent/*/weird.sh"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "exit" "esperado 0 (contido, mesmo com * literal na cauda), obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stdout_contains "nonexistent/*/weird.sh" || return 1
  assert_stdout_not_contains "candidate-a.txt" || return 1
  assert_stdout_not_contains "candidate-b.txt" || return 1
}

# ---------- Regressao: ".." em cauda inexistente nao escapa o root ----------

scenario_dotdot_traversal_cauda_inexistente_exit1() {
  _root="$TMPDIR_TEST/proj"
  mkdir -p "$_root"
  capture "$SCRIPT" --root "$_root" --path "$_root/foo/../../../../etc/passwd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "exit" "esperado 1 (escape via .. deve ser bloqueado), obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_dotdot_dentro_do_root_nao_escapa_exit0() {
  # Contraste: ".." que permanece DENTRO do root apos colapsar deve passar.
  _root="$TMPDIR_TEST/proj"
  mkdir -p "$_root/sub"
  touch "$_root/other.sh"
  capture "$SCRIPT" --root "$_root" --path "$_root/sub/../other.sh"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
}

run_all_scenarios
