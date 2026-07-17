#!/bin/sh
# test_posttooluse-tool-call-tick.sh — cobre
# global/skills/agente-00c-runtime/hooks/posttooluse-tool-call-tick.sh
# (hook PostToolUse de metrica de tool calls por onda; sidecar append-only).
#
# Politica sob teste (INVERSA ao pretooluse-bash-guard.sh): fail-OPEN
# absoluto — o hook NUNCA emite decisao, NUNCA sai com exit != 0 e NUNCA
# escreve no state.json; unico efeito permitido e o append em
# <state-dir>/tool-call-ticks.log quando ha execucao ativa.
#
# Mesmo idioma de invocacao do test_pretooluse-bash-guard.sh: o script nao
# aceita argv — le JSON do stdin via
# `sh -c 'printf "%s" "$1" | "$2"' _ "$json" "$SCRIPT"`.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/hooks/posttooluse-tool-call-tick.sh"

# _run_hook JSON -> invoca o script com JSON via stdin; popula _CAPTURED_*.
_run_hook() {
  capture sh -c 'printf "%s" "$1" | "$2"' _ "$1" "$SCRIPT"
}

# _active_feature CWD SHORT STATUS -> fixture de execucao feature-00c.
_active_feature() {
  mkdir -p "$1/.claude/feature-00c-state/$2"
  printf '{"execution":{"status":"%s"}}' "$3" \
    > "$1/.claude/feature-00c-state/$2/state.json"
}

# _active_agente CWD STATUS -> fixture de execucao agente-00c.
_active_agente() {
  mkdir -p "$1/.claude/agente-00c-state"
  printf '{"execution":{"status":"%s"}}' "$2" > "$1/.claude/agente-00c-state/state.json"
}

# _ticks_count FILE -> nº de linhas do sidecar (0 se ausente).
_ticks_count() {
  [ -f "$1" ] || { printf '0'; return 0; }
  wc -l < "$1" | tr -d '[:space:]'
}

# _json_for CWD TOOL -> payload PostToolUse minimo do harness.
_json_for() {
  printf '{"cwd":"%s","hook_event_name":"PostToolUse","tool_name":"%s","tool_input":{}}' "$1" "$2"
}

# _make_shim_path: PATH controlado com POSIX essenciais, SEM jq. Espelha
# tests/test_pretooluse-bash-guard.sh::_make_shim_path (manter em sync).
_make_shim_path() {
  _shim="$TMPDIR_TEST/shimbin"
  mkdir -p "$_shim"
  for _cmd in sh mktemp awk sed grep find head printf cp mv rm mkdir \
              chmod ls dirname basename tr cut wc env command sort \
              uniq date cat; do
    _src=$(command -v "$_cmd" 2>/dev/null) || continue
    [ -n "$_src" ] || continue
    ln -sf "$_src" "$_shim/$_cmd" 2>/dev/null || :
  done
  printf '%s' "$_shim"
}

# ==== Cenario: execucao feature-00c ativa -> appende 1 tick no sidecar ====

scenario_execucao_feature_ativa_appende_tick() {
  _active_feature "$TMPDIR_TEST" "minha-feat" "em_andamento"
  _run_hook "$(_json_for "$TMPDIR_TEST" "Bash")"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "esperado vazio (metrica silenciosa), obtido: $_CAPTURED_STDOUT"; return 1; }
  _side="$TMPDIR_TEST/.claude/feature-00c-state/minha-feat/tool-call-ticks.log"
  [ "$(_ticks_count "$_side")" = 1 ] || { _fail "sidecar" "esperado 1 linha em $_side, obtido $(_ticks_count "$_side")"; return 1; }
}

# ==== Cenario: ticks acumulam (3 calls -> 3 linhas) ====

scenario_multiplos_ticks_acumulam() {
  _active_feature "$TMPDIR_TEST" "minha-feat" "em_andamento"
  _json=$(_json_for "$TMPDIR_TEST" "Read")
  _run_hook "$_json"
  _run_hook "$_json"
  _run_hook "$_json"
  _side="$TMPDIR_TEST/.claude/feature-00c-state/minha-feat/tool-call-ticks.log"
  [ "$(_ticks_count "$_side")" = 3 ] || { _fail "sidecar" "esperado 3 linhas, obtido $(_ticks_count "$_side")"; return 1; }
}

# ==== Cenario: fora de execucao ativa -> zero interferencia, sem sidecar ====

scenario_fora_de_execucao_zero_interferencia() {
  _run_hook "$(_json_for "$TMPDIR_TEST" "Bash")"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "esperado vazio, obtido: $_CAPTURED_STDOUT"; return 1; }
  find "$TMPDIR_TEST" -name 'tool-call-ticks.log' 2>/dev/null | grep -q . \
    && { _fail "sidecar" "NAO deveria existir sidecar fora de execucao ativa"; return 1; }
  return 0
}

# ==== Cenario: status terminal nao ticka ====

scenario_status_terminal_nao_ticka() {
  _active_feature "$TMPDIR_TEST" "feat-velha" "concluida"
  _run_hook "$(_json_for "$TMPDIR_TEST" "Bash")"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -f "$TMPDIR_TEST/.claude/feature-00c-state/feat-velha/tool-call-ticks.log" ] \
    && { _fail "sidecar" "state concluido NAO deveria receber tick"; return 1; }
  return 0
}

# ==== Cenario: aguardando_humano tambem conta como ativa ====

scenario_aguardando_humano_ticka() {
  _active_feature "$TMPDIR_TEST" "feat-pausada" "aguardando_humano"
  _run_hook "$(_json_for "$TMPDIR_TEST" "Skill")"
  _side="$TMPDIR_TEST/.claude/feature-00c-state/feat-pausada/tool-call-ticks.log"
  [ "$(_ticks_count "$_side")" = 1 ] || { _fail "sidecar" "aguardando_humano e status ativo (mesma regra do bash-guard); esperado 1 tick"; return 1; }
}

# ==== Cenario: precedencia agente-00c > feature-00c (mesma regra do guard) ====

scenario_agente_precede_feature() {
  _active_agente "$TMPDIR_TEST" "em_andamento"
  _active_feature "$TMPDIR_TEST" "minha-feat" "em_andamento"
  _run_hook "$(_json_for "$TMPDIR_TEST" "Bash")"
  [ "$(_ticks_count "$TMPDIR_TEST/.claude/agente-00c-state/tool-call-ticks.log")" = 1 ] \
    || { _fail "precedencia" "tick deveria ir para agente-00c-state"; return 1; }
  [ -f "$TMPDIR_TEST/.claude/feature-00c-state/minha-feat/tool-call-ticks.log" ] \
    && { _fail "precedencia" "feature-00c NAO deveria receber tick quando agente-00c esta ativo"; return 1; }
  return 0
}

# ==== Cenario: entre features ativas, menor short lexicografico vence ====

scenario_feature_menor_short_vence() {
  _active_feature "$TMPDIR_TEST" "zebra-feat" "em_andamento"
  _active_feature "$TMPDIR_TEST" "alpha-feat" "em_andamento"
  _run_hook "$(_json_for "$TMPDIR_TEST" "Write")"
  [ "$(_ticks_count "$TMPDIR_TEST/.claude/feature-00c-state/alpha-feat/tool-call-ticks.log")" = 1 ] \
    || { _fail "precedencia" "menor short (alpha-feat) deveria receber o tick"; return 1; }
  [ -f "$TMPDIR_TEST/.claude/feature-00c-state/zebra-feat/tool-call-ticks.log" ] \
    && { _fail "precedencia" "zebra-feat NAO deveria receber tick"; return 1; }
  return 0
}

# ==== Cenario: jq ausente -> fail-OPEN (no-op, NUNCA deny) ====

scenario_jq_ausente_fail_open() {
  _active_feature "$TMPDIR_TEST" "minha-feat" "em_andamento"
  _shim=$(_make_shim_path)
  _json=$(_json_for "$TMPDIR_TEST" "Bash")
  capture env -i PATH="$_shim" HOME="$TMPDIR_TEST" \
    sh -c 'printf "%s" "$1" | "$2"' _ "$_json" "$SCRIPT"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "fail-open exige exit 0 sem jq, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "fail-open NUNCA emite decisao (contraste com o guard fail-closed): $_CAPTURED_STDOUT"; return 1; }
  [ -f "$TMPDIR_TEST/.claude/feature-00c-state/minha-feat/tool-call-ticks.log" ] \
    && { _fail "sidecar" "sem jq nao ha deteccao segura -> sem tick"; return 1; }
  return 0
}

# ==== Cenario: stdin vazio / JSON invalido -> no-op exit 0 ====

scenario_stdin_vazio_fail_open() {
  _active_feature "$TMPDIR_TEST" "minha-feat" "em_andamento"
  _run_hook ""
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "esperado vazio: $_CAPTURED_STDOUT"; return 1; }
  return 0
}

scenario_stdin_invalido_fail_open() {
  _active_feature "$TMPDIR_TEST" "minha-feat" "em_andamento"
  _run_hook "isto nao e json {"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -f "$TMPDIR_TEST/.claude/feature-00c-state/minha-feat/tool-call-ticks.log" ] \
    && { _fail "sidecar" "JSON invalido nao pode gerar tick"; return 1; }
  return 0
}

# ==== Cenario: tool_name vazio -> payload anomalo, sem tick ====

scenario_tool_name_vazio_nao_ticka() {
  _active_feature "$TMPDIR_TEST" "minha-feat" "em_andamento"
  _run_hook "{\"cwd\":\"$TMPDIR_TEST\",\"hook_event_name\":\"PostToolUse\"}"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -f "$TMPDIR_TEST/.claude/feature-00c-state/minha-feat/tool-call-ticks.log" ] \
    && { _fail "sidecar" "payload sem tool_name nao pode gerar tick"; return 1; }
  return 0
}

run_all_scenarios
exit $?
