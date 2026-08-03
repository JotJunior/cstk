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
. "$TESTS_ROOT/lib/latency.sh"

SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/hooks/pretooluse-bash-guard.sh"
HELPER="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/_hook-active-exec.sh"

# _run_hook JSON -> invoca o script com JSON via stdin; popula _CAPTURED_*.
_run_hook() {
  capture sh -c 'printf "%s" "$1" | "$2"' _ "$1" "$SCRIPT"
}

# _require_sqlite3 -> marca o scenario como ERROR (pre-requisito ausente) e
# retorna 2 se `sqlite3` nao estiver no PATH deste ambiente de teste.
# Uso: `_require_sqlite3 || return 2` na primeira linha de scenarios sob backend SQLite.
_require_sqlite3() {
  command -v sqlite3 >/dev/null 2>&1 && return 0
  _error "no_sqlite3" "sqlite3 indisponivel neste ambiente de teste"
  return 1
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

# _active_feature_db CWD SHORT STATUS -> fixture feature-00c ativa, backend
# SQLite (paridade com tests/test__hook-active-exec.sh::_sqlite_state_db).
# WAL habilitado (paridade com producao real via state-db-schema.sh).
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

# _make_shim_path_no_sqlite: PATH completo (symlinks) COM jq mas SEM
# sqlite3. Armadilha conhecida do repositorio (memoria de projeto
# feedback_test_path_stub_cannot_hide_usrbin.md): um PATH minimo/stub nao
# esconde binarios resolvidos por caminho absoluto (/usr/bin,
# /opt/homebrew/bin, ...) — o teste MUST montar PATH completo com symlinks
# para tudo, exceto o binario sob supressao. Espelha
# tests/test__hook-active-exec.sh::_make_shim_path_no_sqlite (manter em sync).
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
# Isola o hook num diretorio SEM sibling scripts/COMPLETO, com HOME
# apontando para um scratch vazio (sem .claude/skills/agente-00c-runtime/
# scripts/) — os 3 candidatos de resolucao (sibling, cwd project-scope,
# HOME global-scope) falham para bash-guard.sh, forcando o ramo
# "bash-guard.sh ausente". O sibling scripts/ carrega APENAS
# _hook-active-exec.sh (helper novo, task 3.1) — sem ele a deteccao
# tri-estado falharia PRIMEIRO ("_hook-active-exec.sh ausente", scenario
# dedicado abaixo), mascarando o alvo original deste scenario.
scenario_bash_guard_ausente_mecanismo_falhou() {
  _isolated="$TMPDIR_TEST/isolated/hooks"
  mkdir -p "$_isolated"
  cp "$SCRIPT" "$_isolated/pretooluse-bash-guard.sh"
  chmod +x "$_isolated/pretooluse-bash-guard.sh"
  mkdir -p "$TMPDIR_TEST/isolated/scripts"
  cp "$HELPER" "$TMPDIR_TEST/isolated/scripts/_hook-active-exec.sh"

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

# ==== _hook-active-exec.sh ausente/ilegivel -> deny + MECANISMO_FALHOU ====
#
# Isola o hook num diretorio SEM sibling scripts/ ALGUM (nem o helper novo),
# com HOME apontando para scratch vazio — os 2 candidatos de resolucao do
# helper (sibling, HOME global-scope; ordem invertida SEC-H1) falham,
# forcando o novo ramo "_hook-active-exec.sh ausente ou ilegivel" (task 3.1.1,
# feature hooks-db-parity FASE 3), ANTES de qualquer tentativa de resolver
# bash-guard.sh.
scenario_hook_active_exec_helper_ausente_mecanismo_falhou() {
  _isolated="$TMPDIR_TEST/isolated-no-helper/hooks"
  mkdir -p "$_isolated"
  cp "$SCRIPT" "$_isolated/pretooluse-bash-guard.sh"
  chmod +x "$_isolated/pretooluse-bash-guard.sh"

  _fake_home="$TMPDIR_TEST/fake-home-no-helper"
  mkdir -p "$_fake_home"
  _proj="$TMPDIR_TEST/project-no-helper"
  _active_feature "$_proj" "enforced-guards" "em_andamento"

  _json='{"cwd":"'"$_proj"'","tool_name":"Bash","tool_input":{"command":"ls"}}'
  capture env HOME="$_fake_home" \
    sh -c 'printf "%s" "$1" | "$2"' _ "$_json" "$_isolated/pretooluse-bash-guard.sh"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains '"permissionDecision": "deny"' || return 1
  assert_stdout_contains "MECANISMO_FALHOU" || return 1
  assert_stdout_contains "_hook-active-exec.sh ausente" || return 1

  _log=$(_enforcement_log "$_proj")
  case "$_log" in
    *'"outcome":"blocked-mechanism-failure"'*) : ;;
    *) _fail "log outcome" "esperado blocked-mechanism-failure; log=$_log"; return 1 ;;
  esac
}

# ==== FASE 3 (hooks-db-parity) — paridade backend SQLite (task 3.2) ====

# ---- 3.2.1: guarda bloqueia sob state.db -> deny REGRA_VIOLADA ----

scenario_db_comando_bloqueavel_gera_deny_regra_violada() {
  _require_sqlite3 || return 2
  _active_feature_db "$TMPDIR_TEST" "hooks-db-parity" "em_andamento"
  _json='{"cwd":"'"$TMPDIR_TEST"'","tool_name":"Bash","tool_input":{"command":"git push origin main"}}'
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
  case "$_log" in
    *"feature-00c-state/hooks-db-parity/state.db"*) : ;;
    *) _fail "log detected_execution_path" "esperado sufixo .../state.db; log=$_log"; return 1 ;;
  esac
}

# ---- 3.2.2: comando permitido segue permitido sob state.db ----

scenario_db_comando_inocuo_passa_sem_decisao() {
  _require_sqlite3 || return 2
  _active_feature_db "$TMPDIR_TEST" "hooks-db-parity" "em_andamento"
  _json='{"cwd":"'"$TMPDIR_TEST"'","tool_name":"Bash","tool_input":{"command":"ls -la"}}'
  _run_hook "$_json"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "esperado vazio (Caso 1), obtido: $_CAPTURED_STDOUT"; return 1; }

  _log=$(_enforcement_log "$TMPDIR_TEST")
  case "$_log" in
    *'"outcome":"allowed"'*) : ;;
    *) _fail "log outcome" "esperado allowed; log=$_log"; return 1 ;;
  esac
}

# ---- 3.2.3: fail-closed sem sqlite3 (state.db presente) -> MECANISMO_FALHOU ----

scenario_db_sqlite3_ausente_mecanismo_falhou() {
  _active_feature_db "$TMPDIR_TEST" "hooks-db-parity" "em_andamento"
  _require_sqlite3 || return 2
  _shim=$(_make_shim_path_no_sqlite)
  _json='{"cwd":"'"$TMPDIR_TEST"'","tool_name":"Bash","tool_input":{"command":"ls"}}'
  capture env -i PATH="$_shim" HOME="$TMPDIR_TEST" \
    sh -c 'printf "%s" "$1" | "$2"' _ "$_json" "$SCRIPT"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -n "$_CAPTURED_STDOUT" ] || { _fail "stdout" "nunca vazio neste caminho (MECANISMO_FALHOU)"; return 1; }
  assert_stdout_contains "MECANISMO_FALHOU" || return 1
}

# ---- 3.2.4: ausencia total de state -> exit 0, zero arquivo, nunca MECANISMO_FALHOU ----
# (backend-agnostico: nao ha nem state.json nem state.db — coberto pelo
# scenario_fora_de_execucao_ativa_zero_interferencia acima, sem fixture de
# backend algum; mantido aqui como referencia cruzada ao Cenario 8.)

# ---- 3.2.5: state.db corrompido -> MECANISMO_FALHOU ----

scenario_db_corrompido_mecanismo_falhou() {
  _require_sqlite3 || return 2
  mkdir -p "$TMPDIR_TEST/.claude/feature-00c-state/hooks-db-parity"
  printf 'not a database' > "$TMPDIR_TEST/.claude/feature-00c-state/hooks-db-parity/state.db"
  _json='{"cwd":"'"$TMPDIR_TEST"'","tool_name":"Bash","tool_input":{"command":"ls"}}'
  _run_hook "$_json"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains '"permissionDecision": "deny"' || return 1
  assert_stdout_contains "MECANISMO_FALHOU" || return 1

  _log=$(_enforcement_log "$TMPDIR_TEST")
  case "$_log" in
    *'"outcome":"blocked-mechanism-failure"'*) : ;;
    *) _fail "log outcome" "esperado blocked-mechanism-failure; log=$_log"; return 1 ;;
  esac
}

# ---- 3.2.6: execucao terminal sob state.db -> comportamento identico ao Cenario 8 ----

scenario_db_execucao_terminal_zero_interferencia() {
  _require_sqlite3 || return 2
  _active_feature_db "$TMPDIR_TEST" "hooks-db-parity" "concluida"
  _json='{"cwd":"'"$TMPDIR_TEST"'","tool_name":"Bash","tool_input":{"command":"git push origin main"}}'
  _run_hook "$_json"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "esperado vazio (status terminal = fora de escopo), obtido: $_CAPTURED_STDOUT"; return 1; }
  [ -f "$TMPDIR_TEST/.claude/enforcement-log.jsonl" ] \
    && { _fail "log" "enforcement-log.jsonl NAO deveria existir sob execucao terminal"; return 1; }
  return 0
}

# ---- 3.2.7: paridade — mesmo comando produz a mesma categoria de bloqueio sob json e sob db ----

scenario_paridade_json_vs_db_mesma_categoria_bloqueio() {
  _require_sqlite3 || return 2

  _proj_json="$TMPDIR_TEST/proj-json"
  _active_feature "$_proj_json" "paridade" "em_andamento"
  _json='{"cwd":"'"$_proj_json"'","tool_name":"Bash","tool_input":{"command":"git push origin main"}}'
  _run_hook "$_json"
  _log_json=$(_enforcement_log "$_proj_json")
  case "$_log_json" in
    *'"category":"git-push"'*) _cat_json="git-push" ;;
    *) _fail "categoria json" "esperado git-push; log=$_log_json"; return 1 ;;
  esac

  _proj_db="$TMPDIR_TEST/proj-db"
  _active_feature_db "$_proj_db" "paridade" "em_andamento"
  _json='{"cwd":"'"$_proj_db"'","tool_name":"Bash","tool_input":{"command":"git push origin main"}}'
  _run_hook "$_json"
  _log_db=$(_enforcement_log "$_proj_db")
  case "$_log_db" in
    *'"category":"git-push"'*) _cat_db="git-push" ;;
    *) _fail "categoria db" "esperado git-push; log=$_log_db"; return 1 ;;
  esac

  [ "$_cat_json" = "$_cat_db" ] || { _fail "paridade" "categorias divergem: json=$_cat_json db=$_cat_db"; return 1; }

  case "$_log_json" in
    *'"outcome":"blocked-by-rule"'*) : ;;
    *) _fail "outcome json" "esperado blocked-by-rule; log=$_log_json"; return 1 ;;
  esac
  case "$_log_db" in
    *'"outcome":"blocked-by-rule"'*) : ;;
    *) _fail "outcome db" "esperado blocked-by-rule; log=$_log_db"; return 1 ;;
  esac
}

# ==== FASE 6 (hooks-db-parity) — gate de latencia automatizado (task 6.1) ====
#
# Mede a latencia end-to-end do hook real (mediana de N=20 + 3 warm-up
# descartados, research.md Decision 3) contra um state-dir SQLite ativo
# criado no proprio scenario. Teto 400ms para o hook de guarda (orcamento
# da spec ~177ms; medido hoje 17.36ms — folga de ~23x, absorve CI lento
# sem tornar o gate mudo a regressoes de ordem de grandeza). Skip (nao
# fail) se perl ou sqlite3 estiverem ausentes: e gate de performance, nao
# de disponibilidade de ferramenta.

scenario_gate_latencia_mediana_guarda_sob_state_db() {
  _require_perl || return 2
  _require_sqlite3 || return 2
  _active_feature_db "$TMPDIR_TEST" "gate-latencia" "em_andamento"
  _json='{"cwd":"'"$TMPDIR_TEST"'","tool_name":"Bash","tool_input":{"command":"ls -la"}}'
  _mediana=$(_measure_median_ms 3 20 sh -c 'printf "%s" "$1" | "$2"' _ "$_json" "$SCRIPT")
  [ -n "$_mediana" ] || { _error "medicao_falhou" "_measure_median_ms nao produziu mediana"; return 2; }
  [ "$_mediana" -le 400 ] 2>/dev/null \
    || { _fail "latencia" "mediana=${_mediana}ms excede teto de 400ms (FR-005/SC-003, research Decision 3)"; return 1; }
}

run_all_scenarios
exit $?
