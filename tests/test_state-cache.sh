#!/bin/sh
# test_state-cache.sh — cobre global/skills/agente-00c-runtime/scripts/state-cache.sh.
#
# Ref: docs/specs/agente-00c-artifact-cache/tasks.md T1.5
#      docs/specs/agente-00c-artifact-cache/spec.md SC-005 (>= 15 cenarios)

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-cache.sh"
RW="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-rw.sh"

if ! command -v jq >/dev/null 2>&1; then
  printf '# test_state-cache.sh: jq ausente — pulando suite\n'
  exit 0
fi

# Helpers

_init_state() {
  capture "$RW" init --state-dir "$1" \
    --execucao-id "exec-cache-test" \
    --projeto-alvo-path "/tmp/p" \
    --descricao "test cache"
  [ "$_CAPTURED_EXIT" = 0 ]
}

_make_small_source() {
  cat >"$1" <<'EOF'
# Briefing pequeno

## Visao
Sistema de teste.

## Usuarios
Devs.
EOF
}

_make_big_source() {
  _i=0
  {
    printf '# Briefing grande\n\n'
    while [ "$_i" -lt 60 ]; do
      printf '## Secao %d\n\nConteudo descritivo da secao %d explicando o que ela faz.\n\n' "$_i" "$_i"
      _i=$((_i + 1))
    done
  } >"$1"
}

# Ensure helper que usa $_sd e $_src
_ensure() {
  assert_exit 0 "$SCRIPT" ensure --state-dir "$1" --artifact briefing --source-path "$2"
}

# ==== Cenarios ====

scenario_ensure_passthrough_arquivo_pequeno() {
  _sd="$TMPDIR_TEST/state"
  _src="$TMPDIR_TEST/briefing.md"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  _make_small_source "$_src"
  assert_exit 0 "$SCRIPT" ensure --state-dir "$_sd" --artifact briefing --source-path "$_src" || return 1
  assert_stderr_contains "estrategia=passthrough" || return 1
}

scenario_ensure_resumo_arquivo_grande() {
  _sd="$TMPDIR_TEST/state"
  _src="$TMPDIR_TEST/briefing.md"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  _make_big_source "$_src"
  assert_exit 0 "$SCRIPT" ensure --state-dir "$_sd" --artifact briefing --source-path "$_src" || return 1
  assert_stderr_contains "estrategia=resumo" || return 1
}

scenario_ensure_source_ausente_exit_1() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  assert_exit 1 "$SCRIPT" ensure --state-dir "$_sd" --artifact briefing --source-path "/tmp/nonexistent-state-cache-$$"
}

scenario_ensure_state_dir_ausente_exit_2() {
  # source-path PRECISA existir, senao o check de source (exit 1) acontece antes do de state-dir (exit 2)
  _src="$TMPDIR_TEST/dummy-src.md"
  printf '# x\n' >"$_src"
  assert_exit 2 "$SCRIPT" ensure --state-dir "/tmp/no-such-state-$$" --artifact briefing --source-path "$_src"
}

scenario_ensure_artifact_invalido_exit_2() {
  _sd="$TMPDIR_TEST/state"
  _src="$TMPDIR_TEST/dummy-src.md"
  printf '# x\n' >"$_src"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  assert_exit 2 "$SCRIPT" ensure --state-dir "$_sd" --artifact "spec" --source-path "$_src"
}

scenario_get_resumo_hit_retorna_conteudo() {
  _sd="$TMPDIR_TEST/state"
  _src="$TMPDIR_TEST/briefing.md"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  _make_big_source "$_src"
  _ensure "$_sd" "$_src" || return 1
  assert_exit 0 "$SCRIPT" get-resumo --state-dir "$_sd" --artifact briefing || return 1
  assert_stdout_contains "## Secao" || return 1
}

scenario_get_resumo_passthrough_exit_1() {
  _sd="$TMPDIR_TEST/state"
  _src="$TMPDIR_TEST/briefing.md"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  _make_small_source "$_src"
  _ensure "$_sd" "$_src" || return 1
  assert_exit 1 "$SCRIPT" get-resumo --state-dir "$_sd" --artifact briefing
}

scenario_get_resumo_cache_vazio_exit_1() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  assert_exit 1 "$SCRIPT" get-resumo --state-dir "$_sd" --artifact briefing
}

scenario_get_resumo_drift_dispara_miss() {
  _sd="$TMPDIR_TEST/state"
  _src="$TMPDIR_TEST/briefing.md"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  _make_big_source "$_src"
  _ensure "$_sd" "$_src" || return 1
  printf '\n\n## Nova secao apos cache\n\nNovo conteudo.\n' >>"$_src"
  assert_exit 1 "$SCRIPT" get-resumo --state-dir "$_sd" --artifact briefing
}

scenario_check_drift_sem_mudanca_exit_0() {
  _sd="$TMPDIR_TEST/state"
  _src="$TMPDIR_TEST/briefing.md"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  _make_big_source "$_src"
  _ensure "$_sd" "$_src" || return 1
  assert_exit 0 "$SCRIPT" check-drift --state-dir "$_sd" --artifact briefing
}

scenario_check_drift_minor_exit_1() {
  _sd="$TMPDIR_TEST/state"
  _src="$TMPDIR_TEST/briefing.md"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  _make_big_source "$_src"
  _ensure "$_sd" "$_src" || return 1
  printf '\n\n## Mais uma\n\nTexto curto.\n' >>"$_src"
  assert_exit 1 "$SCRIPT" check-drift --state-dir "$_sd" --artifact briefing
}

scenario_check_drift_major_chars_exit_2() {
  _sd="$TMPDIR_TEST/state"
  _src="$TMPDIR_TEST/briefing.md"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  _make_big_source "$_src"
  _ensure "$_sd" "$_src" || return 1
  printf '# Briefing\n## Visao\nso isso.\n' >"$_src"
  assert_exit 2 "$SCRIPT" check-drift --state-dir "$_sd" --artifact briefing
}

scenario_check_drift_source_sumiu_exit_2() {
  _sd="$TMPDIR_TEST/state"
  _src="$TMPDIR_TEST/briefing.md"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  _make_big_source "$_src"
  _ensure "$_sd" "$_src" || return 1
  rm -f -- "$_src"
  assert_exit 2 "$SCRIPT" check-drift --state-dir "$_sd" --artifact briefing
}

scenario_check_drift_cache_vazio_exit_0() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  assert_exit 0 "$SCRIPT" check-drift --state-dir "$_sd" --artifact briefing
}

scenario_invalidate_zera_cache() {
  _sd="$TMPDIR_TEST/state"
  _src="$TMPDIR_TEST/briefing.md"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  _make_big_source "$_src"
  _ensure "$_sd" "$_src" || return 1
  assert_exit 0 "$SCRIPT" invalidate --state-dir "$_sd" --artifact briefing --razao "test" || return 1
  assert_exit 0 "$SCRIPT" status --state-dir "$_sd" --artifact briefing || return 1
  assert_stdout_contains "null" || return 1
}

scenario_invalidate_sem_razao_exit_2() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  assert_exit 2 "$SCRIPT" invalidate --state-dir "$_sd" --artifact briefing
}

scenario_metrics_bump_hit_incrementa_contador() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  assert_exit 0 "$SCRIPT" metrics-bump --state-dir "$_sd" --tipo hit --chars-economizados 2000 || return 1
  _val=$(jq -r '.metricas_acumuladas.cache.tokens_cache_hits // 0' "$_sd/state.json")
  if [ "$_val" != "1" ]; then
    _fail "tokens_cache_hits esperado 1, got $_val"
    return 1
  fi
  _tok=$(jq -r '.metricas_acumuladas.cache.tokens_economizados_estimados // 0' "$_sd/state.json")
  if [ "$_tok" != "500" ]; then
    _fail "tokens_economizados esperado 500, got $_tok"
    return 1
  fi
}

scenario_metrics_bump_miss_drift() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  assert_exit 0 "$SCRIPT" metrics-bump --state-dir "$_sd" --tipo miss-drift || return 1
  _val=$(jq -r '.metricas_acumuladas.cache.tokens_cache_misses_drift // 0' "$_sd/state.json")
  if [ "$_val" != "1" ]; then
    _fail "miss-drift esperado 1, got $_val"
    return 1
  fi
}

scenario_metrics_bump_tipo_invalido_exit_2() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  assert_exit 2 "$SCRIPT" metrics-bump --state-dir "$_sd" --tipo "invalido"
}

scenario_status_cache_vazio_retorna_null() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  assert_exit 0 "$SCRIPT" status --state-dir "$_sd" --artifact briefing || return 1
  assert_stdout_contains "null" || return 1
}

scenario_ensure_resumo_chars_menor_que_source() {
  _sd="$TMPDIR_TEST/state"
  _src="$TMPDIR_TEST/briefing.md"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  _make_big_source "$_src"
  _ensure "$_sd" "$_src" || return 1
  _src_chars=$(jq -r '.briefing_cache.source_chars' "$_sd/state.json")
  _res_chars=$(jq -r '.briefing_cache.resumo_chars' "$_sd/state.json")
  if [ "$_res_chars" -ge "$_src_chars" ]; then
    _fail "FR-CACHE-017: resumo_chars ($_res_chars) deve ser < source_chars ($_src_chars)"
    return 1
  fi
}

scenario_subcomando_desconhecido_exit_2() {
  assert_exit 2 "$SCRIPT" "comando-invalido"
}

scenario_sem_subcomando_exit_2() {
  assert_exit 2 "$SCRIPT"
}

run_all_scenarios
