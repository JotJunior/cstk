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

# _require_sqlite3 -> marca o scenario como ERROR (pre-requisito ausente) e
# retorna 2 se `sqlite3` nao estiver no PATH deste ambiente de teste.
_require_sqlite3() {
  command -v sqlite3 >/dev/null 2>&1 && return 0
  _error "no_sqlite3" "sqlite3 indisponivel neste ambiente de teste"
  return 1
}

# _active_feature_db CWD SHORT STATUS -> fixture feature-00c ativa, backend
# SQLite (paridade com tests/test__hook-active-exec.sh::_sqlite_state_db).
_active_feature_db() {
  _afd_dir="$1/.claude/feature-00c-state/$2"
  mkdir -p "$_afd_dir"
  sqlite3 "$_afd_dir/state.db" \
    "PRAGMA journal_mode=WAL; CREATE TABLE execution(status TEXT); INSERT INTO execution VALUES('$3');" \
    >/dev/null 2>&1
}

# _active_agente_db CWD STATUS -> idem, para agente-00c-state.
_active_agente_db() {
  _aad_dir="$1/.claude/agente-00c-state"
  mkdir -p "$_aad_dir"
  sqlite3 "$_aad_dir/state.db" \
    "PRAGMA journal_mode=WAL; CREATE TABLE execution(status TEXT); INSERT INTO execution VALUES('$2');" \
    >/dev/null 2>&1
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

# _make_shim_path_no_sqlite: PATH completo (symlinks) COM jq mas SEM
# sqlite3. Armadilha conhecida do repositorio (memoria de projeto
# feedback_test_path_stub_cannot_hide_usrbin.md) — PATH deve conter TODOS
# os binarios via symlink, exceto o suprimido, nunca um PATH minimo/stub.
# Espelha tests/test_pretooluse-bash-guard.sh::_make_shim_path_no_sqlite.
_make_shim_path_no_sqlite() {
  _shim="$TMPDIR_TEST/shimbin-no-sqlite"
  mkdir -p "$_shim"
  for _cmd in sh jq mktemp awk sed grep find head printf cp mv rm mkdir \
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

# ==== FASE 4 (hooks-db-parity) — paridade backend SQLite (task 4.2) ====

# ---- 4.2.1 (Cenario 3): 5 disparos sob state.db -> 5 linhas, permissao 600 ----

scenario_db_cinco_disparos_appendam_cinco_linhas() {
  _require_sqlite3 || return 2
  _active_feature_db "$TMPDIR_TEST" "hooks-db-parity" "em_andamento"
  _json=$(_json_for "$TMPDIR_TEST" "Bash")
  _i=1
  while [ "$_i" -le 5 ]; do
    _run_hook "$_json"
    _i=$((_i + 1))
  done
  _side="$TMPDIR_TEST/.claude/feature-00c-state/hooks-db-parity/tool-call-ticks.log"
  [ "$(_ticks_count "$_side")" = 5 ] || { _fail "sidecar" "esperado 5 linhas, obtido $(_ticks_count "$_side")"; return 1; }
  # NAO asserta permissao 600 aqui: data-model.md (entidade WaveTickSidecar,
  # "Nenhuma mudanca de formato, permissao ou teto") + plan.md SEC-L1
  # ("tool-call-ticks.log criado sem umask 077 - pre-existente") documentam
  # que este sidecar NAO recebeu a mesma mitigacao de umask 077/chmod 600 do
  # sidecar irmao (wave-agent-usage.jsonl) — risco Low aceito como residual
  # (bloqueio-001/dec-026). tasks.md 4.2.1 menciona "permissao 600" mas esse
  # texto diverge do desenho ja aprovado; seguimos o artefato ratificado.
}

# ---- 4.2.2 (Cenario 4): precedencia agente-00c > feature-00c independente de backend ----

scenario_db_precedencia_agente_sobre_feature_backends_mistos() {
  _require_sqlite3 || return 2
  _active_agente_db "$TMPDIR_TEST" "em_andamento"
  _active_feature "$TMPDIR_TEST" "minha-feat-json" "em_andamento"
  _run_hook "$(_json_for "$TMPDIR_TEST" "Bash")"
  [ "$(_ticks_count "$TMPDIR_TEST/.claude/agente-00c-state/tool-call-ticks.log")" = 1 ] \
    || { _fail "precedencia" "tick deveria ir para agente-00c-state (backend sqlite)"; return 1; }
  [ -f "$TMPDIR_TEST/.claude/feature-00c-state/minha-feat-json/tool-call-ticks.log" ] \
    && { _fail "precedencia" "feature-00c (json) NAO deveria receber tick quando agente-00c (sqlite) esta ativo"; return 1; }
  return 0
}

# ---- 4.2.3 (Cenario 6): fail-open sem sqlite3 (state.db presente) -> exit 0, silencioso ----

scenario_db_sqlite3_ausente_fail_open() {
  _active_feature_db "$TMPDIR_TEST" "hooks-db-parity" "em_andamento"
  _require_sqlite3 || return 2
  _shim=$(_make_shim_path_no_sqlite)
  _json=$(_json_for "$TMPDIR_TEST" "Bash")
  capture env -i PATH="$_shim" HOME="$TMPDIR_TEST" \
    sh -c 'printf "%s" "$1" | "$2"' _ "$_json" "$SCRIPT"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "fail-open exige exit 0 sem sqlite3, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "esperado vazio: $_CAPTURED_STDOUT"; return 1; }
  [ -z "$_CAPTURED_STDERR" ] || { _fail "stderr" "fail-open NUNCA emite stderr: $_CAPTURED_STDERR"; return 1; }
  [ -f "$TMPDIR_TEST/.claude/feature-00c-state/hooks-db-parity/tool-call-ticks.log" ] \
    && { _fail "sidecar" "sem sqlite3 o helper retorna indeterminada -> sem tick"; return 1; }
  return 0
}

# ---- 4.2.4 (Cenarios 8/10): sem state ou status terminal sob state.db -> zero efeito ----

scenario_db_execucao_terminal_zero_efeito() {
  _require_sqlite3 || return 2
  _active_feature_db "$TMPDIR_TEST" "hooks-db-parity" "concluida"
  _run_hook "$(_json_for "$TMPDIR_TEST" "Bash")"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -f "$TMPDIR_TEST/.claude/feature-00c-state/hooks-db-parity/tool-call-ticks.log" ] \
    && { _fail "sidecar" "state concluido (sqlite) NAO deveria receber tick"; return 1; }
  return 0
}

# ---- 4.2.5 (Cenario 9): state.db corrompido -> exit 0, silencioso, sem sidecar ----

scenario_db_corrompido_fail_open() {
  _require_sqlite3 || return 2
  mkdir -p "$TMPDIR_TEST/.claude/feature-00c-state/hooks-db-parity"
  printf 'not a database' > "$TMPDIR_TEST/.claude/feature-00c-state/hooks-db-parity/state.db"
  _run_hook "$(_json_for "$TMPDIR_TEST" "Bash")"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "esperado vazio: $_CAPTURED_STDOUT"; return 1; }
  [ -z "$_CAPTURED_STDERR" ] || { _fail "stderr" "fail-open NUNCA emite stderr: $_CAPTURED_STDERR"; return 1; }
  [ -f "$TMPDIR_TEST/.claude/feature-00c-state/hooks-db-parity/tool-call-ticks.log" ] \
    && { _fail "sidecar" "state.db corrompido -> indeterminada -> sem tick"; return 1; }
  return 0
}

# ---- 4.2.6 (Cenario 12): roundtrip real via state-ondas.sh start/end contabiliza N ticks ----

scenario_db_roundtrip_state_ondas_contabiliza_ticks() {
  _require_sqlite3 || return 2
  _RUNTIME_SCRIPTS="$REPO_ROOT/global/skills/agente-00c-runtime/scripts"

  # Fixture SQLite via config global state_backend=sqlite simulada com HOME
  # falso (mesmo padrao de tests/test__state-read.sh::_mk_sqlite_state_dir).
  _home="$TMPDIR_TEST/home-sqlite"
  mkdir -p "$_home/.claude/cstk"
  printf 'state_backend=sqlite\n' > "$_home/.claude/cstk/config"

  _feature_cwd="$TMPDIR_TEST/proj"
  _sd="$_feature_cwd/.claude/feature-00c-state/roundtrip"
  mkdir -p "$_sd"
  env HOME="$_home" "$_RUNTIME_SCRIPTS/state-rw.sh" init --state-dir "$_sd" \
    --execucao-id "exec-roundtrip" --projeto-alvo-path "$_feature_cwd" \
    --descricao "descricao de teste com tamanho suficiente para validacao" \
    >/dev/null 2>&1 \
    || { _error "init_falhou" "state-rw.sh init nao inicializou o state-dir de fixture"; return 2; }
  [ -f "$_sd/state.db" ] || { _error "backend_nao_sqlite" "fixture nao produziu state.db"; return 2; }

  "$_RUNTIME_SCRIPTS/state-ondas.sh" start --state-dir "$_sd" >/dev/null 2>&1

  _i=1
  while [ "$_i" -le 4 ]; do
    _run_hook "$(_json_for "$_feature_cwd" "Bash")"
    _i=$((_i + 1))
  done

  [ "$(_ticks_count "$_sd/tool-call-ticks.log")" = 4 ] \
    || { _fail "sidecar" "esperado 4 ticks pre-end, obtido $(_ticks_count "$_sd/tool-call-ticks.log")"; return 1; }

  "$_RUNTIME_SCRIPTS/state-ondas.sh" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando >/dev/null 2>&1

  _tool_calls=$("$_RUNTIME_SCRIPTS/state-rw.sh" get --state-dir "$_sd" --field '.waves[-1].tool_calls' 2>/dev/null)
  [ "$_tool_calls" = "4" ] \
    || { _fail "agregacao" "esperado .waves[-1].tool_calls == 4 apos state-ondas end, obtido: $_tool_calls"; return 1; }
}

run_all_scenarios
exit $?
