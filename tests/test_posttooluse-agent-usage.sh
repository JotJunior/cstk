#!/bin/sh
# test_posttooluse-agent-usage.sh — cobre
# global/skills/agente-00c-runtime/hooks/posttooluse-agent-usage.sh
# (hook PostToolUse/matcher "Agent" de metrica de uso de tokens por spawn;
# sidecar append-only wave-agent-usage.jsonl).
#
# Feature: wave-token-metrics, FASE 2, tarefa 2.1.9 (incorpora as
# subtarefas adiadas 1.2.5 e 1.3.4). Contrato:
# docs/specs/wave-token-metrics/contracts/hook-posttooluse-agent-usage.md §6.
#
# Politica sob teste (mesma familia de test_posttooluse-tool-call-tick.sh):
# fail-OPEN absoluto — o hook NUNCA emite decisao em stdout, NUNCA sai com
# exit != 0 e NUNCA escreve no state.json; unico efeito permitido e o
# append em <state-dir>/wave-agent-usage.jsonl quando ha execucao ativa e
# tool_name == "Agent".
#
# Mesmo idioma de invocacao do test_pretooluse-bash-guard.sh /
# test_posttooluse-tool-call-tick.sh: o script nao aceita argv — le JSON
# do stdin via `sh -c 'printf "%s" "$1" | "$2"' _ "$json" "$SCRIPT"`.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/hooks/posttooluse-agent-usage.sh"

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

# _sidecar_for CWD SHORT -> path do sidecar de uso para uma feature.
_sidecar_for() {
  printf '%s/.claude/feature-00c-state/%s/wave-agent-usage.jsonl' "$1" "$2"
}

# _lines_count FILE -> nº de linhas do sidecar (0 se ausente).
_lines_count() {
  [ -f "$1" ] || { printf '0'; return 0; }
  wc -l < "$1" | tr -d '[:space:]'
}

# _perm FILE -> permissao octal do arquivo (portavel BSD/GNU — mesmo
# padrao de tests/cstk/test_recall.sh:401).
_perm() {
  # GNU (-c) primeiro: no BSD 'stat -c' falha com exit != 0 e cai no -f.
  # A ordem inversa quebra no GNU, onde '-f' significa FILESYSTEM e sai 0
  # com output errado (o fallback nunca dispara).
  stat -c '%a' -- "$1" 2>/dev/null || stat -f '%Lp' -- "$1" 2>/dev/null
}

# _payload CWD TOOL_NAME TOOL_RESPONSE_JSON [TOOL_INPUT_JSON] -> payload
# PostToolUse completo via jq -n (evita quoting manual de JSON aninhado).
_payload() {
  _pl_ti=$4
  if [ -z "$_pl_ti" ]; then
    _pl_ti='{}'
  fi
  jq -n --arg cwd "$1" --arg tn "$2" --argjson tr "$3" --argjson ti "$_pl_ti" \
    '{cwd:$cwd,hook_event_name:"PostToolUse",tool_name:$tn,tool_input:$ti,tool_response:$tr}'
}

# _make_shim_path: PATH controlado com POSIX essenciais, SEM jq. Espelha
# tests/test_pretooluse-bash-guard.sh::_make_shim_path (manter em sync).
_make_shim_path() {
  _shim="$TMPDIR_TEST/shimbin"
  mkdir -p "$_shim"
  for _cmd in sh mktemp awk sed grep find head printf cp mv rm mkdir \
              chmod ls dirname basename tr cut wc env command sort \
              uniq date cat stat; do
    _src=$(command -v "$_cmd" 2>/dev/null) || continue
    [ -n "$_src" ] || continue
    ln -sf "$_src" "$_shim/$_cmd" 2>/dev/null || :
  done
  printf '%s' "$_shim"
}

# _make_shim_path_no_sqlite: PATH completo (symlinks) COM jq mas SEM
# sqlite3. Espelha tests/test_pretooluse-bash-guard.sh::_make_shim_path_no_sqlite
# (armadilha conhecida: PATH minimo/stub nao esconde binario absoluto).
_make_shim_path_no_sqlite() {
  _shim="$TMPDIR_TEST/shimbin-no-sqlite"
  mkdir -p "$_shim"
  for _cmd in sh jq mktemp awk sed grep find head printf cp mv rm mkdir \
              chmod ls dirname basename tr cut wc env command sort \
              uniq date cat stat; do
    _src=$(command -v "$_cmd" 2>/dev/null) || continue
    [ -n "$_src" ] || continue
    ln -sf "$_src" "$_shim/$_cmd" 2>/dev/null || :
  done
  printf '%s' "$_shim"
}

# ==== Cenario: spawn completed com usage completo -> status=completo ====

scenario_completed_com_usage_completo() {
  _active_feature "$TMPDIR_TEST" "minha-feat" "em_andamento"
  _tr='{"status":"completed","agentId":"a1b598e5d8f9a0318","content":[{"type":"text","text":"NAO PODE VAZAR"}],"resolvedModel":"claude-sonnet-5","totalTokens":131692,"totalDurationMs":681768,"totalToolUseCount":45,"usage":{"input_tokens":2,"output_tokens":1097,"cache_read_input_tokens":130176,"cache_creation_input_tokens":417}}'
  _ti='{"subagent_type":"general-purpose","prompt":"segredo de tarefa"}'
  _run_hook "$(_payload "$TMPDIR_TEST" "Agent" "$_tr" "$_ti")"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "esperado vazio (metrica silenciosa): $_CAPTURED_STDOUT"; return 1; }
  _side=$(_sidecar_for "$TMPDIR_TEST" "minha-feat")
  [ "$(_lines_count "$_side")" = 1 ] || { _fail "sidecar" "esperado 1 linha, obtido $(_lines_count "$_side")"; return 1; }
  _line=$(cat "$_side")
  echo "$_line" | jq -e '.status == "completo"' >/dev/null || { _fail "status" "$_line"; return 1; }
  echo "$_line" | jq -e '.agent_id == "a1b598e5d8f9a0318"' >/dev/null || { _fail "agent_id" "$_line"; return 1; }
  echo "$_line" | jq -e '.model == "claude-sonnet-5"' >/dev/null || { _fail "model" "$_line"; return 1; }
  echo "$_line" | jq -e '.total_tokens == 131692 and .input_tokens == 2 and .output_tokens == 1097' >/dev/null \
    || { _fail "breakdown" "$_line"; return 1; }
  echo "$_line" | jq -e '.tool_use_count == 45 and .duration_ms == 681768' >/dev/null \
    || { _fail "tool_use/duration" "$_line"; return 1; }
  echo "$_line" | jq -e '.source == "live"' >/dev/null || { _fail "source" "$_line"; return 1; }
}

# ==== Cenario: status=async_launched -> indisponivel, todos numericos null ====

scenario_async_launched_indisponivel() {
  _active_feature "$TMPDIR_TEST" "minha-feat" "em_andamento"
  _tr='{"status":"async_launched","agentId":"a35a086e9e6589c0b","description":"x","prompt":"y","outputFile":"z","resolvedModel":"claude-opus-4-8[1m]","isAsync":true,"canReadOutputFile":true}'
  _run_hook "$(_payload "$TMPDIR_TEST" "Agent" "$_tr")"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  _side=$(_sidecar_for "$TMPDIR_TEST" "minha-feat")
  _line=$(cat "$_side")
  echo "$_line" | jq -e '.status == "indisponivel"' >/dev/null || { _fail "status" "$_line"; return 1; }
  echo "$_line" | jq -e '.total_tokens == null and .input_tokens == null and .output_tokens == null' >/dev/null \
    || { _fail "numericos deveriam ser null, nao 0" "$_line"; return 1; }
  echo "$_line" | jq -e '.cache_read_input_tokens == null and .cache_creation_input_tokens == null' >/dev/null \
    || { _fail "cache deveria ser null" "$_line"; return 1; }
  echo "$_line" | jq -e '.tool_use_count == null and .duration_ms == null' >/dev/null \
    || { _fail "tool_use/duration deveriam ser null" "$_line"; return 1; }
}

# ==== Cenario: completed sem usage -> parcial, observados preenchidos ====

scenario_completed_sem_usage_parcial() {
  _active_feature "$TMPDIR_TEST" "minha-feat" "em_andamento"
  _tr='{"status":"completed","agentId":"xyz","resolvedModel":"claude-haiku-5"}'
  _run_hook "$(_payload "$TMPDIR_TEST" "Agent" "$_tr")"
  _side=$(_sidecar_for "$TMPDIR_TEST" "minha-feat")
  _line=$(cat "$_side")
  echo "$_line" | jq -e '.status == "parcial"' >/dev/null || { _fail "status" "$_line"; return 1; }
  echo "$_line" | jq -e '.model == "claude-haiku-5"' >/dev/null || { _fail "model observado" "$_line"; return 1; }
  echo "$_line" | jq -e '.total_tokens == null and .input_tokens == null' >/dev/null \
    || { _fail "campos nao observados deveriam ser null" "$_line"; return 1; }
}

# ==== Cenario: resolvedModel ausente -> model == "nao-aplicavel" ====

scenario_resolved_model_ausente_nao_aplicavel() {
  _active_feature "$TMPDIR_TEST" "minha-feat" "em_andamento"
  _tr='{"status":"completed","agentId":"sem-modelo","totalTokens":10}'
  _run_hook "$(_payload "$TMPDIR_TEST" "Agent" "$_tr")"
  _side=$(_sidecar_for "$TMPDIR_TEST" "minha-feat")
  _line=$(cat "$_side")
  echo "$_line" | jq -e '.model == "nao-aplicavel"' >/dev/null \
    || { _fail "model" "esperado literal nao-aplicavel (FR-003), obtido: $_line"; return 1; }
}

# ==== Cenario: jq ausente -> fail-OPEN (no-op, sidecar nao criado) ====

scenario_jq_ausente_fail_open() {
  _active_feature "$TMPDIR_TEST" "minha-feat" "em_andamento"
  _shim=$(_make_shim_path)
  _tr='{"status":"completed","agentId":"x","totalTokens":1}'
  _json=$(jq -n --arg cwd "$TMPDIR_TEST" --argjson tr "$_tr" \
    '{cwd:$cwd,hook_event_name:"PostToolUse",tool_name:"Agent",tool_input:{},tool_response:$tr}')
  capture env -i PATH="$_shim" HOME="$TMPDIR_TEST" \
    sh -c 'printf "%s" "$1" | "$2"' _ "$_json" "$SCRIPT"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "fail-open exige exit 0 sem jq, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "fail-open NUNCA emite decisao: $_CAPTURED_STDOUT"; return 1; }
  [ -f "$(_sidecar_for "$TMPDIR_TEST" "minha-feat")" ] \
    && { _fail "sidecar" "sem jq nao ha parsing seguro -> sem linha"; return 1; }
  return 0
}

# ==== Cenario: fora de execucao ativa -> zero interferencia, sem sidecar ====

scenario_fora_de_execucao_zero_interferencia() {
  _tr='{"status":"completed","agentId":"x","totalTokens":1}'
  _run_hook "$(_payload "$TMPDIR_TEST" "Agent" "$_tr")"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "esperado vazio: $_CAPTURED_STDOUT"; return 1; }
  find "$TMPDIR_TEST" -name 'wave-agent-usage.jsonl' 2>/dev/null | grep -q . \
    && { _fail "sidecar" "NAO deveria existir sidecar fora de execucao ativa"; return 1; }
  return 0
}

# ==== Cenario: status terminal (concluida) nao gera linha ====

scenario_status_terminal_nao_gera_linha() {
  _active_feature "$TMPDIR_TEST" "feat-velha" "concluida"
  _tr='{"status":"completed","agentId":"x","totalTokens":1}'
  _run_hook "$(_payload "$TMPDIR_TEST" "Agent" "$_tr")"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -f "$(_sidecar_for "$TMPDIR_TEST" "feat-velha")" ] \
    && { _fail "sidecar" "state concluido NAO deveria receber linha"; return 1; }
  return 0
}

# ==== Cenario: tool_name != Agent -> exit 0, sidecar nao criado ====

scenario_tool_name_diferente_de_agent_nao_gera_linha() {
  _active_feature "$TMPDIR_TEST" "minha-feat" "em_andamento"
  _run_hook "$(_payload "$TMPDIR_TEST" "Bash" '{}')"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -f "$(_sidecar_for "$TMPDIR_TEST" "minha-feat")" ] \
    && { _fail "sidecar" "matcher deve ser Agent, nao qualquer tool"; return 1; }
  return 0
}

# ==== Cenario: 2 features ativas -> menor short lexicografico vence ====

scenario_feature_menor_short_vence() {
  _active_feature "$TMPDIR_TEST" "zebra-feat" "em_andamento"
  _active_feature "$TMPDIR_TEST" "alpha-feat" "em_andamento"
  _tr='{"status":"completed","agentId":"x","totalTokens":1}'
  _run_hook "$(_payload "$TMPDIR_TEST" "Agent" "$_tr")"
  [ "$(_lines_count "$(_sidecar_for "$TMPDIR_TEST" "alpha-feat")")" = 1 ] \
    || { _fail "precedencia" "menor short (alpha-feat) deveria receber a linha"; return 1; }
  [ -f "$(_sidecar_for "$TMPDIR_TEST" "zebra-feat")" ] \
    && { _fail "precedencia" "zebra-feat NAO deveria receber linha"; return 1; }
  return 0
}

# ==== Cenario: agente-00c precede feature-00c (mesma regra do guard/tick) ====

scenario_agente_precede_feature() {
  _active_agente "$TMPDIR_TEST" "em_andamento"
  _active_feature "$TMPDIR_TEST" "minha-feat" "em_andamento"
  _tr='{"status":"completed","agentId":"x","totalTokens":1}'
  _run_hook "$(_payload "$TMPDIR_TEST" "Agent" "$_tr")"
  [ "$(_lines_count "$TMPDIR_TEST/.claude/agente-00c-state/wave-agent-usage.jsonl")" = 1 ] \
    || { _fail "precedencia" "linha deveria ir para agente-00c-state"; return 1; }
  [ -f "$(_sidecar_for "$TMPDIR_TEST" "minha-feat")" ] \
    && { _fail "precedencia" "feature-00c NAO deveria receber linha quando agente-00c esta ativo"; return 1; }
  return 0
}

# ==== Cenario: stdin vazio / JSON invalido -> no-op exit 0, sem crash ====

scenario_stdin_vazio_fail_open() {
  _active_feature "$TMPDIR_TEST" "minha-feat" "em_andamento"
  _run_hook ""
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "esperado vazio: $_CAPTURED_STDOUT"; return 1; }
  return 0
}

scenario_stdin_malformado_fail_open() {
  _active_feature "$TMPDIR_TEST" "minha-feat" "em_andamento"
  _run_hook "isto nao e json {"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -f "$(_sidecar_for "$TMPDIR_TEST" "minha-feat")" ] \
    && { _fail "sidecar" "JSON invalido nao pode gerar linha"; return 1; }
  return 0
}

# ==== Cenario: agentId ausente -> exit 0 sem linha (contrato §3) ====

scenario_agent_id_ausente_sem_linha() {
  _active_feature "$TMPDIR_TEST" "minha-feat" "em_andamento"
  _tr='{"status":"completed","totalTokens":1}'
  _run_hook "$(_payload "$TMPDIR_TEST" "Agent" "$_tr")"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -f "$(_sidecar_for "$TMPDIR_TEST" "minha-feat")" ] \
    && { _fail "sidecar" "sem agentId nao ha chave natural -> sem linha"; return 1; }
  return 0
}

# ==== Cenario: append repetido -> 2 spawns geram 2 linhas, ordem preservada ====

scenario_append_repetido_preserva_ordem() {
  _active_feature "$TMPDIR_TEST" "minha-feat" "em_andamento"
  _tr1='{"status":"completed","agentId":"primeiro","totalTokens":10}'
  _tr2='{"status":"completed","agentId":"segundo","totalTokens":20}'
  _run_hook "$(_payload "$TMPDIR_TEST" "Agent" "$_tr1")"
  _run_hook "$(_payload "$TMPDIR_TEST" "Agent" "$_tr2")"
  _side=$(_sidecar_for "$TMPDIR_TEST" "minha-feat")
  [ "$(_lines_count "$_side")" = 2 ] || { _fail "sidecar" "esperado 2 linhas, obtido $(_lines_count "$_side")"; return 1; }
  sed -n '1p' "$_side" | jq -e '.agent_id == "primeiro"' >/dev/null \
    || { _fail "ordem" "1a linha deveria ser 'primeiro'"; return 1; }
  sed -n '2p' "$_side" | jq -e '.agent_id == "segundo"' >/dev/null \
    || { _fail "ordem" "2a linha deveria ser 'segundo'"; return 1; }
}

# ==== Cenario: anti-vazamento — content/prompt nunca aparecem na linha ====

scenario_anti_vazamento_content_prompt() {
  _active_feature "$TMPDIR_TEST" "minha-feat" "em_andamento"
  _tr='{"status":"completed","agentId":"x","totalTokens":1,"content":[{"type":"text","text":"SEGREDO-DE-SAIDA-NAO-PODE-VAZAR"}]}'
  _ti='{"subagent_type":"general-purpose","prompt":"SEGREDO-DE-ENTRADA-NAO-PODE-VAZAR","description":"tambem nao pode vazar"}'
  _run_hook "$(_payload "$TMPDIR_TEST" "Agent" "$_tr" "$_ti")"
  _side=$(_sidecar_for "$TMPDIR_TEST" "minha-feat")
  _line=$(cat "$_side")
  case "$_line" in
    *SEGREDO*) _fail "vazamento" "linha do sidecar contem texto livre: $_line"; return 1 ;;
  esac
  echo "$_line" | jq -e 'has("content") | not' >/dev/null || { _fail "vazamento" "chave content presente"; return 1; }
  echo "$_line" | jq -e 'has("prompt") | not' >/dev/null || { _fail "vazamento" "chave prompt presente"; return 1; }
  echo "$_line" | jq -e 'has("description") | not' >/dev/null || { _fail "vazamento" "chave description presente"; return 1; }
}

# ==== Cenario: sidecar criado tem permissao 0600 (subtarefa 1.2.5) ====

scenario_sidecar_criado_com_permissao_0600() {
  _active_feature "$TMPDIR_TEST" "minha-feat" "em_andamento"
  _tr='{"status":"completed","agentId":"x","totalTokens":1}'
  _run_hook "$(_payload "$TMPDIR_TEST" "Agent" "$_tr")"
  _side=$(_sidecar_for "$TMPDIR_TEST" "minha-feat")
  [ -f "$_side" ] || { _fail "sidecar" "nao foi criado"; return 1; }
  _perm=$(_perm "$_side")
  [ "$_perm" = "600" ] || { _fail "permissao" "esperado 600, obtido $_perm"; return 1; }
}

# ==== Cenario: cap de 500 linhas (subtarefa 1.3.4) ====

scenario_cap_500_linhas_nao_adiciona_501() {
  _active_feature "$TMPDIR_TEST" "minha-feat" "em_andamento"
  _side=$(_sidecar_for "$TMPDIR_TEST" "minha-feat")
  _i=1
  while [ "$_i" -le 500 ]; do
    printf '{"filler":%s}\n' "$_i" >> "$_side"
    _i=$((_i + 1))
  done
  _tr='{"status":"completed","agentId":"linha-501","totalTokens":1}'
  _run_hook "$(_payload "$TMPDIR_TEST" "Agent" "$_tr")"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "cap deve ser fail-open, obtido $_CAPTURED_EXIT"; return 1; }
  [ "$(_lines_count "$_side")" = 500 ] \
    || { _fail "cap" "esperado 500 linhas (append pulado), obtido $(_lines_count "$_side")"; return 1; }
  [ -f "$TMPDIR_TEST/.claude/feature-00c-state/minha-feat/.wave-agent-usage-cap-warned" ] \
    || { _fail "sentinela" "sentinela de aviso deveria ter sido criado"; return 1; }
  case "$_CAPTURED_STDERR" in
    *"cap de 500"*) : ;;
    *) _fail "aviso" "esperado aviso de cap em stderr, obtido: $_CAPTURED_STDERR"; return 1 ;;
  esac
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "aviso deve ir para stderr, nao stdout: $_CAPTURED_STDOUT"; return 1; }
}

# ==== Cenario: cap ja avisado nesta onda -> nao duplica aviso ====

scenario_cap_sentinela_evita_aviso_duplicado() {
  _active_feature "$TMPDIR_TEST" "minha-feat" "em_andamento"
  _side=$(_sidecar_for "$TMPDIR_TEST" "minha-feat")
  _i=1
  while [ "$_i" -le 500 ]; do
    printf '{"filler":%s}\n' "$_i" >> "$_side"
    _i=$((_i + 1))
  done
  : > "$TMPDIR_TEST/.claude/feature-00c-state/minha-feat/.wave-agent-usage-cap-warned"
  _tr='{"status":"completed","agentId":"linha-501-de-novo","totalTokens":1}'
  _run_hook "$(_payload "$TMPDIR_TEST" "Agent" "$_tr")"
  [ -z "$_CAPTURED_STDERR" ] || { _fail "aviso duplicado" "sentinela ja existia, nao deveria reavisar: $_CAPTURED_STDERR"; return 1; }
  [ "$(_lines_count "$_side")" = 500 ] || { _fail "cap" "ainda deveria estar em 500"; return 1; }
}

# ==== FASE 5 (hooks-db-parity) — paridade backend SQLite (task 5.2) ====

# ---- 5.2.1 (Cenario 3): tool_response completo sob state.db -> 1 linha, permissao 600 ----

scenario_db_completed_com_usage_completo() {
  _require_sqlite3 || return 2
  _active_feature_db "$TMPDIR_TEST" "hooks-db-parity" "em_andamento"
  _tr='{"status":"completed","agentId":"a1b598e5d8f9a0318","resolvedModel":"claude-sonnet-5","totalTokens":131692,"totalDurationMs":681768,"totalToolUseCount":45,"usage":{"input_tokens":2,"output_tokens":1097}}'
  _run_hook "$(_payload "$TMPDIR_TEST" "Agent" "$_tr")"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "esperado vazio (metrica silenciosa): $_CAPTURED_STDOUT"; return 1; }
  _side=$(_sidecar_for "$TMPDIR_TEST" "hooks-db-parity")
  [ "$(_lines_count "$_side")" = 1 ] || { _fail "sidecar" "esperado 1 linha, obtido $(_lines_count "$_side")"; return 1; }
  _line=$(cat "$_side")
  echo "$_line" | jq -e '.status == "completo"' >/dev/null || { _fail "status" "$_line"; return 1; }
  echo "$_line" | jq -e '.agent_id == "a1b598e5d8f9a0318"' >/dev/null || { _fail "agent_id" "$_line"; return 1; }
  echo "$_line" | jq -e '.total_tokens == 131692' >/dev/null || { _fail "total_tokens" "$_line"; return 1; }
  echo "$_line" | jq -e '.source == "live"' >/dev/null || { _fail "source" "$_line"; return 1; }
  _perm=$(_perm "$_side")
  [ "$_perm" = "600" ] || { _fail "permissao" "esperado 600, obtido $_perm"; return 1; }
}

# ---- 5.2.2 (Cenario 6): fail-open sem sqlite3 (state.db presente) -> exit 0, silencioso ----

scenario_db_sqlite3_ausente_fail_open() {
  _active_feature_db "$TMPDIR_TEST" "hooks-db-parity" "em_andamento"
  _require_sqlite3 || return 2
  _shim=$(_make_shim_path_no_sqlite)
  _tr='{"status":"completed","agentId":"x","totalTokens":1}'
  _json=$(jq -n --arg cwd "$TMPDIR_TEST" --argjson tr "$_tr" \
    '{cwd:$cwd,hook_event_name:"PostToolUse",tool_name:"Agent",tool_input:{},tool_response:$tr}')
  capture env -i PATH="$_shim" HOME="$TMPDIR_TEST" \
    sh -c 'printf "%s" "$1" | "$2"' _ "$_json" "$SCRIPT"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "fail-open exige exit 0 sem sqlite3, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "esperado vazio: $_CAPTURED_STDOUT"; return 1; }
  [ -z "$_CAPTURED_STDERR" ] || { _fail "stderr" "fail-open NUNCA emite stderr: $_CAPTURED_STDERR"; return 1; }
  [ -f "$(_sidecar_for "$TMPDIR_TEST" "hooks-db-parity")" ] \
    && { _fail "sidecar" "sem sqlite3 o helper retorna indeterminada -> sem linha"; return 1; }
  return 0
}

# ---- 5.2.3 (Cenarios 8/9/10): sem state, state.db corrompido, ou status terminal -> zero efeito ----

scenario_db_execucao_terminal_zero_efeito() {
  _require_sqlite3 || return 2
  _active_feature_db "$TMPDIR_TEST" "hooks-db-parity" "concluida"
  _tr='{"status":"completed","agentId":"x","totalTokens":1}'
  _run_hook "$(_payload "$TMPDIR_TEST" "Agent" "$_tr")"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -f "$(_sidecar_for "$TMPDIR_TEST" "hooks-db-parity")" ] \
    && { _fail "sidecar" "state concluido (sqlite) NAO deveria receber linha"; return 1; }
  return 0
}

scenario_db_corrompido_zero_efeito() {
  _require_sqlite3 || return 2
  mkdir -p "$TMPDIR_TEST/.claude/feature-00c-state/hooks-db-parity"
  printf 'not a database' > "$TMPDIR_TEST/.claude/feature-00c-state/hooks-db-parity/state.db"
  _tr='{"status":"completed","agentId":"x","totalTokens":1}'
  _run_hook "$(_payload "$TMPDIR_TEST" "Agent" "$_tr")"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "esperado vazio: $_CAPTURED_STDOUT"; return 1; }
  [ -z "$_CAPTURED_STDERR" ] || { _fail "stderr" "fail-open NUNCA emite stderr: $_CAPTURED_STDERR"; return 1; }
  [ -f "$(_sidecar_for "$TMPDIR_TEST" "hooks-db-parity")" ] \
    && { _fail "sidecar" "state.db corrompido -> indeterminada -> sem linha"; return 1; }
  return 0
}

scenario_db_sem_state_zero_efeito() {
  _require_sqlite3 || return 2
  _tr='{"status":"completed","agentId":"x","totalTokens":1}'
  _run_hook "$(_payload "$TMPDIR_TEST" "Agent" "$_tr")"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  find "$TMPDIR_TEST" -name 'wave-agent-usage.jsonl' 2>/dev/null | grep -q . \
    && { _fail "sidecar" "NAO deveria existir sidecar sem nenhum state presente"; return 1; }
  return 0
}

run_all_scenarios
exit $?
