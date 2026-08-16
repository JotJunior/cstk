#!/bin/sh
# test_mcp-build-lazy.sh — cobre
# plugins/cstk/skills/agente-00c-runtime/scripts/mcp-build-lazy.sh.
#
# Ref: docs/specs/mcp-direct-transport/tasks.md FASE 2 task 2.2.6
#      (gate manual documentado no Cenario 0 do quickstart; a suite
#      automatizada aqui cobre o contrato do script em isolamento —
#      sem rede real, via stub de `npm` no PATH, mesma filosofia
#      hermetica de tests/cstk/test_serve.sh).
#
# ESCOPO: contrato de `mcp-build-lazy.sh ensure --dir <path>` — nunca
# instala nada de verdade. Um `npm` fake no PATH prova QUE comando foi
# invocado (ou nao), nunca executa instalacao real.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/mcp-build-lazy.sh"

# _make_pkg_dir DIR -> cria package.json + package-lock.json minimos
# (lockfile presente = pre-requisito de reprodutibilidade, CHK015).
_make_pkg_dir() {
  _mpd_dir="$1"
  mkdir -p "$_mpd_dir"
  printf '{"name":"fixture","version":"0.0.0"}\n' > "$_mpd_dir/package.json"
  printf '{"lockfileVersion":3}\n' > "$_mpd_dir/package-lock.json"
}

# _stub_npm_builds_entrypoint BIN_DIR DIR -> npm fake: `ci --ignore-scripts`
# loga a chamada; `run build` cria DIR/dist/src/index.js (simula tsc).
_stub_npm_builds_entrypoint() {
  _snbe_bin="$1"
  _snbe_dir="$2"
  cat > "$_snbe_bin/npm" <<STUB
#!/bin/sh
printf 'npm %s\n' "\$*" >> "$TMPDIR_TEST/npm-calls.log"
case "\$*" in
  "ci --ignore-scripts")
    exit 0
    ;;
  *"run build"*)
    mkdir -p "$_snbe_dir/dist/src"
    printf 'module.exports={};\n' > "$_snbe_dir/dist/src/index.js"
    exit 0
    ;;
esac
exit 0
STUB
  chmod +x "$_snbe_bin/npm"
}

_stub_npm_install_fails() {
  _snif_bin="$1"
  cat > "$_snif_bin/npm" <<STUB
#!/bin/sh
printf 'npm %s\n' "\$*" >> "$TMPDIR_TEST/npm-calls.log"
case "\$*" in
  "ci --ignore-scripts") exit 1 ;;
esac
exit 0
STUB
  chmod +x "$_snif_bin/npm"
}

_stub_npm_build_fails() {
  _snbf_bin="$1"
  cat > "$_snbf_bin/npm" <<STUB
#!/bin/sh
printf 'npm %s\n' "\$*" >> "$TMPDIR_TEST/npm-calls.log"
case "\$*" in
  "ci --ignore-scripts") exit 0 ;;
  *"run build"*) exit 2 ;;
esac
exit 0
STUB
  chmod +x "$_snbf_bin/npm"
}

_npm_calls() {
  cat "$TMPDIR_TEST/npm-calls.log" 2>/dev/null
}

_run_ensure() {
  _re_dir="$1"
  _re_bin="${2:-}"
  if [ -n "$_re_bin" ]; then
    capture env PATH="$_re_bin:$PATH" "$SCRIPT" ensure --dir "$_re_dir"
  else
    capture "$SCRIPT" ensure --dir "$_re_dir"
  fi
}

scenario_entrypoint_ja_existe_e_noop_nao_chama_npm() {
  _dir="$TMPDIR_TEST/proj-cached"
  _make_pkg_dir "$_dir"
  mkdir -p "$_dir/dist/src"
  printf 'module.exports={};\n' > "$_dir/dist/src/index.js"
  _bin="$TMPDIR_TEST/stubs-noop"
  mkdir -p "$_bin"
  # npm ausente do PATH restrito de proposito: se o script chamar npm
  # aqui, falharia por "nao encontrado" e o teste pegaria a regressao.
  _run_ensure "$_dir" "$_bin"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "noop exit" "esperado 0, obtido $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "$_dir/dist/src/index.js" || return 1
}

scenario_lockfile_ausente_falha_fail_closed() {
  _dir="$TMPDIR_TEST/proj-no-lock"
  mkdir -p "$_dir"
  printf '{"name":"fixture"}\n' > "$_dir/package.json"
  _run_ensure "$_dir"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "sem lockfile exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "package-lock.json ausente" || return 1
}

scenario_npm_ausente_no_path_falha() {
  _dir="$TMPDIR_TEST/proj-no-npm"
  _make_pkg_dir "$_dir"
  _bare="$TMPDIR_TEST/bare-bin"
  mkdir -p "$_bare"
  for _u in sh cd pwd dirname printf cat command; do
    _p=$(command -v "$_u" 2>/dev/null) || continue
    ln -sf "$_p" "$_bare/$_u" 2>/dev/null || :
  done
  capture env PATH="$_bare" "$SCRIPT" ensure --dir "$_dir"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "npm ausente exit" "esperado 1, obtido $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains "npm nao encontrado" || return 1
}

scenario_build_completo_instala_fixado_e_ignora_scripts() {
  _dir="$TMPDIR_TEST/proj-build-ok"
  _make_pkg_dir "$_dir"
  _bin="$TMPDIR_TEST/stubs-ok"
  mkdir -p "$_bin"
  _stub_npm_builds_entrypoint "$_bin" "$_dir"
  _run_ensure "$_dir" "$_bin"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "build exit" "esperado 0, obtido $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "$_dir/dist/src/index.js" || return 1
  [ -f "$_dir/dist/src/index.js" ] || { _fail "entrypoint deveria existir apos build" ""; return 1; }
  # Mitigacao R8 (CHK001/CHK015): a instalacao usou EXATAMENTE `npm ci
  # --ignore-scripts` (fixada por lockfile + sem scripts de ciclo de
  # vida) — nunca `npm install`.
  case "$(_npm_calls)" in
    *"npm ci --ignore-scripts"*) : ;;
    *) _fail "esperava chamada 'npm ci --ignore-scripts'" "$(_npm_calls)"; return 1 ;;
  esac
  case "$(_npm_calls)" in
    *"npm install"*) _fail "npm install NUNCA deveria ser chamado (mitigacao R8)" "$(_npm_calls)"; return 1 ;;
  esac
  case "$(_npm_calls)" in
    *"run build"*) : ;;
    *) _fail "esperava chamada 'npm ... run build'" "$(_npm_calls)"; return 1 ;;
  esac
}

scenario_instalacao_falha_propaga_erro() {
  _dir="$TMPDIR_TEST/proj-install-fail"
  _make_pkg_dir "$_dir"
  _bin="$TMPDIR_TEST/stubs-installfail"
  mkdir -p "$_bin"
  _stub_npm_install_fails "$_bin"
  _run_ensure "$_dir" "$_bin"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "install falho exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "instalacao de dependencias falhou" || return 1
  [ -f "$_dir/dist/src/index.js" ] && { _fail "entrypoint nao deveria existir" ""; return 1; }
  return 0
}

scenario_build_falha_propaga_erro() {
  _dir="$TMPDIR_TEST/proj-build-fail"
  _make_pkg_dir "$_dir"
  _bin="$TMPDIR_TEST/stubs-buildfail"
  mkdir -p "$_bin"
  _stub_npm_build_fails "$_bin"
  _run_ensure "$_dir" "$_bin"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "build falho exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "build (npm run build) falhou" || return 1
}

scenario_dir_ausente_exit_2_uso_incorreto() {
  assert_exit 2 "$SCRIPT" ensure --dir "$TMPDIR_TEST/nao-existe-mesmo" || return 1
}

scenario_flag_dir_ausente_exit_2() {
  assert_exit 2 "$SCRIPT" ensure || return 1
}

scenario_subcomando_desconhecido_exit_2() {
  assert_exit 2 "$SCRIPT" bogus --dir "$TMPDIR_TEST" || return 1
}

scenario_sem_args_mostra_uso_exit_0() {
  assert_exit 0 "$SCRIPT" || return 1
  assert_stdout_contains "uso:" || return 1
}

run_all_scenarios
