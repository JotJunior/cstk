#!/bin/sh
# test_pretooluse-bash-guard.sh — cobre
# global/skills/agente-00c-runtime/hooks/pretooluse-bash-guard.sh (US1,
# enforced-guards, task 2.6).
#
# Ref: docs/specs/enforced-guards/{contracts/pretooluse-hook.md,
#      contracts/enforcement-log.md, quickstart.md Scenarios 1-4}.
#
# O script sob teste NAO aceita argv — le JSON do stdin (contrato do
# harness). Invocamos via `sh -c 'printf "%s" "$1" | "$2"' _ "$json" "$SCRIPT"`
# (positional params evitam problemas de quoting com o JSON, que contem
# aspas duplas — mesmo idioma de tests/test_state-rw.sh).

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/hooks/pretooluse-bash-guard.sh"

# _run_hook JSON -> invoca o script com JSON via stdin; popula _CAPTURED_*.
_run_hook() {
  capture sh -c 'printf "%s" "$1" | "$2"' _ "$1" "$SCRIPT"
}

# _active_feature CWD SHORT STATUS -> cria fixture de execucao feature-00c ativa.
_active_feature() {
  _af_cwd=$1
  _af_short=$2
  _af_status=$3
  mkdir -p "$_af_cwd/.claude/feature-00c-state/$_af_short"
  printf '{"execution":{"status":"%s"}}' "$_af_status" \
    > "$_af_cwd/.claude/feature-00c-state/$_af_short/state.json"
}

# _active_agente CWD STATUS -> cria fixture de execucao agente-00c ativa.
_active_agente() {
  mkdir -p "$1/.claude/agente-00c-state"
  printf '{"execution":{"status":"%s"}}' "$2" > "$1/.claude/agente-00c-state/state.json"
}

# _enforcement_log CWD -> imprime conteudo do enforcement-log.jsonl (vazio se ausente).
_enforcement_log() {
  cat "$1/.claude/enforcement-log.jsonl" 2>/dev/null || :
}

# _make_shim_path: PATH controlado com POSIX essenciais, SEM jq. Espelha
# tests/cstk/test_hooks.sh::_make_shim_path (manter listas em sync).
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

# ==== Scenario 1 (quickstart): comando bloqueavel -> deny + REGRA_VIOLADA ====

scenario_comando_bloqueavel_gera_deny_regra_violada() {
  _active_feature "$TMPDIR_TEST" "enforced-guards" "em_andamento"
  _json='{"session_id":"s1","cwd":"'"$TMPDIR_TEST"'","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git push origin main"}}'
  _run_hook "$_json"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0 (Decision 1), obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains '"permissionDecision": "deny"' || return 1
  assert_stdout_contains "REGRA_VIOLADA" || return 1
  assert_stdout_contains "git-push" || return 1

  _log=$(_enforcement_log "$TMPDIR_TEST")
  case "$_log" in
    *'"outcome":"blocked-by-rule"'*) : ;;
    *) _fail "log outcome" "esperado blocked-by-rule; log=$_log"; return 1 ;;
  esac
  case "$_log" in
    *'"category":"git-push"'*) : ;;
    *) _fail "log category" "esperado git-push; log=$_log"; return 1 ;;
  esac
  case "$_log" in
    *'"detected_execution":"feature-00c"'*) : ;;
    *) _fail "log detected_execution" "esperado feature-00c; log=$_log"; return 1 ;;
  esac
}

# ==== Scenario 2: comando inocuo dentro de execucao ativa -> passa ====

scenario_comando_inocuo_passa_sem_decisao() {
  _active_feature "$TMPDIR_TEST" "enforced-guards" "em_andamento"
  _json='{"cwd":"'"$TMPDIR_TEST"'","tool_name":"Bash","tool_input":{"command":"ls -la"}}'
  _run_hook "$_json"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "esperado vazio (Caso 1), obtido: $_CAPTURED_STDOUT"; return 1; }

  _log=$(_enforcement_log "$TMPDIR_TEST")
  case "$_log" in
    *'"outcome":"allowed"'*) : ;;
    *) _fail "log outcome" "esperado allowed (comando permitido dentro de execucao ativa); log=$_log"; return 1 ;;
  esac
}

# ==== Scenario 3: fora de execucao ativa -> exit 0 sem decisao, sem log ====

scenario_fora_de_execucao_ativa_zero_interferencia() {
  # Nenhum state.json em .claude/{agente-00c,feature-00c}-state — sessao
  # manual comum do operador (FR-006/dec-012).
  _json='{"cwd":"'"$TMPDIR_TEST"'","tool_name":"Bash","tool_input":{"command":"git push origin main"}}'
  _run_hook "$_json"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "esperado vazio (fora de escopo), obtido: $_CAPTURED_STDOUT"; return 1; }
  [ -f "$TMPDIR_TEST/.claude/enforcement-log.jsonl" ] \
    && { _fail "log" "enforcement-log.jsonl NAO deveria existir fora de escopo"; return 1; }
  return 0
}

# ==== Scenario 4a: jq ausente -> deny + MECANISMO_FALHOU ====

scenario_jq_ausente_mecanismo_falhou() {
  _active_feature "$TMPDIR_TEST" "enforced-guards" "em_andamento"
  _shim=$(_make_shim_path)
  _json='{"cwd":"'"$TMPDIR_TEST"'","tool_name":"Bash","tool_input":{"command":"ls"}}'
  capture env -i PATH="$_shim" HOME="$TMPDIR_TEST" \
    sh -c 'printf "%s" "$1" | "$2"' _ "$_json" "$SCRIPT"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  # Fallback sem jq emite JSON compacto (sem espaco apos ':'), diferente do
  # jq -n pretty-printed usado nos demais cenarios — checagem agnostica a
  # formatacao de whitespace.
  assert_stdout_contains "permissionDecision" || return 1
  assert_stdout_contains "deny" || return 1
  assert_stdout_contains "MECANISMO_FALHOU" || return 1
  assert_stdout_contains "jq ausente" || return 1
}

# ==== Scenario 4b: bash-guard.sh ausente -> deny + MECANISMO_FALHOU ====
#
# Isola o hook num diretorio SEM sibling scripts/, com HOME apontando para
# um scratch vazio (sem .claude/skills/agente-00c-runtime/scripts/) — os 3
# candidatos de resolucao (sibling, cwd project-scope, HOME global-scope)
# falham, forcando o ramo "bash-guard.sh ausente".
scenario_bash_guard_ausente_mecanismo_falhou() {
  _isolated="$TMPDIR_TEST/isolated/hooks"
  mkdir -p "$_isolated"
  cp "$SCRIPT" "$_isolated/pretooluse-bash-guard.sh"
  chmod +x "$_isolated/pretooluse-bash-guard.sh"

  _fake_home="$TMPDIR_TEST/fake-home"
  mkdir -p "$_fake_home"
  _proj="$TMPDIR_TEST/project"
  _active_feature "$_proj" "enforced-guards" "em_andamento"

  _json='{"cwd":"'"$_proj"'","tool_name":"Bash","tool_input":{"command":"ls"}}'
  capture env HOME="$_fake_home" \
    sh -c 'printf "%s" "$1" | "$2"' _ "$_json" "$_isolated/pretooluse-bash-guard.sh"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains '"permissionDecision": "deny"' || return 1
  assert_stdout_contains "MECANISMO_FALHOU" || return 1
  assert_stdout_contains "bash-guard.sh ausente" || return 1

  _log=$(_enforcement_log "$_proj")
  case "$_log" in
    *'"outcome":"blocked-mechanism-failure"'*) : ;;
    *) _fail "log outcome" "esperado blocked-mechanism-failure; log=$_log"; return 1 ;;
  esac
}

# ==== Erros do proprio contrato: stdin invalido / vazio ====

scenario_stdin_invalido_mecanismo_falhou() {
  _active_feature "$TMPDIR_TEST" "enforced-guards" "em_andamento"
  capture sh -c 'printf "%s" "not-json-at-all" | "$1"' _ "$SCRIPT"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "MECANISMO_FALHOU" || return 1
}

scenario_stdin_vazio_mecanismo_falhou() {
  capture sh -c 'printf "" | "$1"' _ "$SCRIPT"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "MECANISMO_FALHOU" || return 1
  assert_stdout_contains "stdin vazio" || return 1
}

scenario_tool_name_diferente_de_bash_ignora() {
  _active_feature "$TMPDIR_TEST" "enforced-guards" "em_andamento"
  _json='{"cwd":"'"$TMPDIR_TEST"'","tool_name":"Write","tool_input":{"file_path":"x"}}'
  _run_hook "$_json"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "esperado vazio (defesa em profundidade do matcher)"; return 1; }
}

# ==== Precedencia multi-execucao (task 1.3/CHK007, consumida por 2.2.4/2.6.3) ====

scenario_precedencia_agente00c_vence_sobre_feature00c() {
  _active_agente "$TMPDIR_TEST" "em_andamento"
  _active_feature "$TMPDIR_TEST" "zzz-feature" "em_andamento"
  _json='{"cwd":"'"$TMPDIR_TEST"'","tool_name":"Bash","tool_input":{"command":"ls"}}'
  _run_hook "$_json"
  _log=$(_enforcement_log "$TMPDIR_TEST")
  case "$_log" in
    *'"detected_execution":"agente-00c"'*) : ;;
    *) _fail "precedencia" "esperado agente-00c vencer; log=$_log"; return 1 ;;
  esac
}

scenario_precedencia_lexicografica_entre_feature00c() {
  _active_feature "$TMPDIR_TEST" "zzz-feature" "em_andamento"
  _active_feature "$TMPDIR_TEST" "aaa-feature" "aguardando_humano"
  _json='{"cwd":"'"$TMPDIR_TEST"'","tool_name":"Bash","tool_input":{"command":"ls"}}'
  _run_hook "$_json"
  _log=$(_enforcement_log "$TMPDIR_TEST")
  case "$_log" in
    *"feature-00c-state/aaa-feature/state.json"*) : ;;
    *) _fail "precedencia lexicografica" "esperado aaa-feature (menor byte-wise) vencer; log=$_log"; return 1 ;;
  esac
}

# ==== Secret scrub antes de truncar (task 1.4/CHK020, consumido por 2.3.5/2.6.3) ====

scenario_secret_scrub_precede_truncagem_a_500_chars() {
  _active_feature "$TMPDIR_TEST" "x" "em_andamento"
  _prefix=$(printf 'a%.0s' $(seq 1 480))
  _cmd="curl -H 'Authorization: Bearer ${_prefix}SECRETVALUE123456789TAIL' https://example.com"
  # tool_input.command via jq -Rs garante escaping correto do payload (aspas
  # simples dentro do comando nao devem quebrar o JSON de entrada do teste).
  if ! command -v jq >/dev/null 2>&1; then
    _error "no_jq" "jq indisponivel no ambiente de teste — nao consigo montar o payload adversarial com seguranca"
    return 2
  fi
  _json=$(printf '%s' "$_cmd" | jq -Rs --arg cwd "$TMPDIR_TEST" '{cwd:$cwd, tool_name:"Bash", tool_input:{command:.}}')
  _run_hook "$_json"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }

  # Secret NAO pode vazar nem no stdout (permissionDecisionReason) nem no log.
  case "$_CAPTURED_STDOUT" in
    *"SECRETVALUE123456789TAIL"*) _fail "stdout vazou secret" "$_CAPTURED_STDOUT"; return 1 ;;
  esac
  _log=$(_enforcement_log "$TMPDIR_TEST")
  case "$_log" in
    *"SECRETVALUE123456789TAIL"*) _fail "log vazou secret" "$_log"; return 1 ;;
  esac
  case "$_log" in
    *"[REDACTED]"*) : ;;
    *) _fail "log sem marcador de redacao" "$_log"; return 1 ;;
  esac
}

run_all_scenarios
exit $?
