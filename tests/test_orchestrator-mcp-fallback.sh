#!/bin/sh
# test_orchestrator-mcp-fallback.sh — cobre FASE 6 task 6.3 da feature
# state-mcp-server: fallback sem Docker (FR-007, FR-012, SC-004).
#
# Feature: state-mcp-server
# Ref: docs/specs/state-mcp-server/tasks.md FASE 6 task 6.3
#      docs/specs/state-mcp-server/quickstart.md Scenario 7
#      docs/specs/state-mcp-server/spec.md FR-007, FR-012, SC-004
#
# Natureza: HIBRIDO — parte textual (smoke sobre os 4 commands + os 2
# agentes orquestradores, mesmo padrao de test_command-spawn-mcp-lifecycle.sh
# / test_command-spawn-model-routing.sh) + parte FUNCIONAL (roda `cstk mcp
# status`/`start` de verdade com `docker` ausente do PATH — via
# _path_without_docker, derivado dinamicamente do PATH real do host, NUNCA
# um PATH hardcoded/minimo — e confirma que uma "onda" completa via Bash
# puro (state-ondas.sh + state-decisions.sh) termina com exit 0,
# independente do resultado do mcp start). NAO mapeia 1:1 a um unico
# script sob a convencao de FASE 9.3 — registrado interno em
# tests/run.sh::_is_internal_test.
#
# 6.3.1: confirma, por CONSTRUCAO, que `cstk mcp status`/`start`
#   indisponivel nao afeta o caminho Bash: os 2 agentes orquestradores
#   (agente-00c-orchestrator.md, agente-00c-feature-orchestrator.md) nao
#   listam NENHUMA tool `mcp__*` no frontmatter `tools:` — o pipeline
#   inteiro roda hoje via Bash (state-*.sh), zero dependencia de MCP
#   (a injecao de tools MCP no orquestrador e a task 1.2, cross-feature,
#   explicitamente fora do escopo desta feature — 6.2.4). Os 4 commands
#   pai chamam `cstk mcp status`/`start`/`stop` sempre em modo best-effort
#   (`|| :` / redirecionados, nunca gateando o fluxo).
# 6.3.2: prova FUNCIONAL de SC-004 — com docker ausente do PATH, uma
#   execucao completa (init + start onda + decisao + end onda) roda ate o
#   fim identica ao caminho com Docker disponivel.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CMD_INIT_AGENTE="$REPO_ROOT/global/commands/agente-00c.md"
CMD_INIT_FEAT="$REPO_ROOT/global/commands/feature-00c.md"
CMD_RES_AGENTE="$REPO_ROOT/global/commands/agente-00c-resume.md"
CMD_RES_FEAT="$REPO_ROOT/global/commands/feature-00c-resume.md"
AGENT_ORCH="$REPO_ROOT/global/agents/agente-00c-orchestrator.md"
AGENT_FEAT_ORCH="$REPO_ROOT/global/agents/agente-00c-feature-orchestrator.md"

CSTK_BIN="$REPO_ROOT/cli/cstk"
CSTK_LIB_DIR="$REPO_ROOT/cli/lib"
STATE_RW="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-rw.sh"
STATE_ONDAS="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-ondas.sh"
STATE_DECISIONS="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-decisions.sh"

if ! command -v jq >/dev/null 2>&1; then
  printf '# test_orchestrator-mcp-fallback.sh: jq ausente — pulando suite\n'
  exit 0
fi

# ---------- 6.3.1: prova estrutural (textual) ----------

scenario_orchestrator_agente_nao_lista_tool_mcp() {
  [ -f "$AGENT_ORCH" ] || { _error "arquivo ausente" "$AGENT_ORCH"; return 2; }
  if grep -Eq '^\s*-\s*mcp__' "$AGENT_ORCH"; then
    _fail "tool_mcp_listada" "agente-00c-orchestrator.md lista tool mcp__* no frontmatter — dependencia de MCP quebraria SC-004"
    return 1
  fi
  return 0
}

scenario_orchestrator_feature_nao_lista_tool_mcp() {
  [ -f "$AGENT_FEAT_ORCH" ] || { _error "arquivo ausente" "$AGENT_FEAT_ORCH"; return 2; }
  if grep -Eq '^\s*-\s*mcp__' "$AGENT_FEAT_ORCH"; then
    _fail "tool_mcp_listada" "agente-00c-feature-orchestrator.md lista tool mcp__* no frontmatter — dependencia de MCP quebraria SC-004"
    return 1
  fi
  return 0
}

# `cstk mcp status`/`start`/`stop` nos 4 commands: nunca sem uma forma de
# supressao de erro (`|| :`, `>/dev/null 2>&1 || :`, `2>/dev/null || :`)
# na mesma linha ou imediatamente ligada — best-effort, nunca gateia.
_assert_mcp_call_best_effort() {
  _file=$1
  _pattern=$2
  _line=$(grep -nE "$_pattern" "$_file" | head -1)
  [ -n "$_line" ] || { _fail "chamada_ausente" "$_pattern nao encontrada em $_file"; return 1; }
  case "$_line" in
    *'|| :'*) return 0 ;;
  esac
  _fail "nao_best_effort" "linha sem '|| :' em $_file: $_line"
  return 1
}

scenario_init_agente_mcp_start_best_effort() {
  _assert_mcp_call_best_effort "$CMD_INIT_AGENTE" 'cstk mcp start --state-dir' || return 1
}

scenario_init_feat_mcp_start_best_effort() {
  _assert_mcp_call_best_effort "$CMD_INIT_FEAT" 'cstk mcp start --state-dir' || return 1
}

scenario_resume_agente_mcp_live_best_effort() {
  _assert_mcp_call_best_effort "$CMD_RES_AGENTE" 'cstk mcp status --state-dir.*--live' || return 1
}

scenario_resume_feat_mcp_live_best_effort() {
  _assert_mcp_call_best_effort "$CMD_RES_FEAT" 'cstk mcp status --state-dir.*--live' || return 1
}

scenario_init_agente_mcp_stop_best_effort() {
  _assert_mcp_call_best_effort "$CMD_INIT_AGENTE" 'cstk mcp stop --state-dir' || return 1
}

scenario_init_feat_mcp_stop_best_effort() {
  _assert_mcp_call_best_effort "$CMD_INIT_FEAT" 'cstk mcp stop --state-dir' || return 1
}

scenario_resume_agente_mcp_stop_best_effort() {
  _assert_mcp_call_best_effort "$CMD_RES_AGENTE" 'cstk mcp stop --state-dir' || return 1
}

scenario_resume_feat_mcp_stop_best_effort() {
  _assert_mcp_call_best_effort "$CMD_RES_FEAT" 'cstk mcp stop --state-dir' || return 1
}

# ---------- 6.3.2: prova funcional (SC-004) ----------

# _path_without_docker -> copia do PATH real removendo so o(s) dir(s) com
# `docker` executavel (derivado dinamicamente — CLAUDE.md "PATH-stub nao
# esconde binario de /usr/bin"; mesmo padrao de tests/cstk/test_mcp.sh).
_path_without_docker() {
  _pwd_out=""
  _pwd_ifs_save=$IFS
  IFS=:
  for _pwd_dir in $PATH; do
    IFS=$_pwd_ifs_save
    [ -n "$_pwd_dir" ] || continue
    [ -x "$_pwd_dir/docker" ] && continue
    if [ -z "$_pwd_out" ]; then
      _pwd_out="$_pwd_dir"
    else
      _pwd_out="$_pwd_out:$_pwd_dir"
    fi
  done
  IFS=$_pwd_ifs_save
  printf '%s' "$_pwd_out"
}

_cstk_mcp_no_docker() {
  env CSTK_LIB="$CSTK_LIB_DIR" HOME="$TMPDIR_TEST/home" PATH="$(_path_without_docker)" \
    sh "$CSTK_BIN" mcp "$@"
}

scenario_status_sem_docker_reporta_unavailable_exit_0() {
  _sd="$TMPDIR_TEST/sd-sc004-status"
  mkdir -p "$_sd"
  capture _cstk_mcp_no_docker status --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "status exit" "esperado 0, obtido $_CAPTURED_EXIT ($_CAPTURED_STDERR)"; return 1; }
  assert_stdout_contains "status=unavailable" || return 1
}

scenario_start_sem_docker_reporta_bash_fallback_exit_3() {
  _sd="$TMPDIR_TEST/sd-sc004-start"
  mkdir -p "$_sd"
  capture env HOME="$TMPDIR_TEST/home" "$STATE_RW" init --state-dir "$_sd" \
    --execucao-id "exec-sc004" --projeto-alvo-path "$TMPDIR_TEST" \
    --descricao "SC-004 headless fixture"
  [ "$_CAPTURED_EXIT" = 0 ] || { _error "init falhou" "$_CAPTURED_STDERR"; return 2; }

  capture _cstk_mcp_no_docker start --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "start exit" "esperado 3, obtido $_CAPTURED_EXIT ($_CAPTURED_STDERR)"; return 1; }
  assert_stdout_contains "reason=docker-absent" || return 1
  assert_stdout_contains "mode=bash-fallback" || return 1
}

# Prova central de SC-004: com `start` ja tendo falhado (docker ausente),
# uma execucao "headless/cron" completa via Bash puro — inicia onda,
# registra uma decisao, fecha a onda — SEM qualquer intervencao manual e
# SEM checar o resultado do mcp start (nunca gateia). Simula fielmente o
# que um command pai + orquestrador fariam numa maquina sem Docker.
scenario_execucao_headless_completa_via_bash_apos_start_falho() {
  _sd="$TMPDIR_TEST/sd-sc004-headless"
  mkdir -p "$_sd"
  capture env HOME="$TMPDIR_TEST/home" "$STATE_RW" init --state-dir "$_sd" \
    --execucao-id "exec-sc004-headless" --projeto-alvo-path "$TMPDIR_TEST" \
    --descricao "SC-004 headless completion fixture"
  [ "$_CAPTURED_EXIT" = 0 ] || { _error "init falhou" "$_CAPTURED_STDERR"; return 2; }

  # 1. mcp start falha (docker ausente) — resultado IGNORADO deliberadamente,
  #    espelhando `|| :` dos commands (best-effort, nunca gateia).
  _cstk_mcp_no_docker start --state-dir "$_sd" >/dev/null 2>&1 || :

  # 2. onda inicia normalmente via Bash, independente do passo 1
  capture env HOME="$TMPDIR_TEST/home" "$STATE_ONDAS" start --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _error "state-ondas start falhou" "$_CAPTURED_STDERR"; return 1; }
  _onda_id=$_CAPTURED_STDOUT
  [ -n "$_onda_id" ] || { _fail "onda_id_vazio" "state-ondas.sh start nao retornou id"; return 1; }

  # 3. decisao registrada normalmente (prova de que o pipeline funcional
  #    de auditoria — Principio I — nao depende de MCP)
  capture env HOME="$TMPDIR_TEST/home" "$STATE_DECISIONS" register --state-dir "$_sd" \
    --agente "test-sc004" --etapa "execute-task" \
    --contexto "SC-004: decisao registrada via Bash sem MCP disponivel" \
    --opcoes '["a","b"]' --escolha "a" \
    --justificativa "prova funcional de fallback headless" --score 2
  [ "$_CAPTURED_EXIT" = 0 ] || { _error "state-decisions register falhou" "$_CAPTURED_STDERR"; return 1; }

  # 4. onda fecha normalmente
  capture env HOME="$TMPDIR_TEST/home" "$STATE_ONDAS" end --state-dir "$_sd" \
    --motivo-termino etapa_concluida_avancando
  [ "$_CAPTURED_EXIT" = 0 ] || { _error "state-ondas end falhou" "$_CAPTURED_STDERR"; return 1; }

  # 5. resultado funcional identico ao caminho com Docker: onda registrada,
  #    decisao persistida, mode continua bash-fallback no descritor mcp
  #    (nenhuma mutacao espuria por causa da falha do passo 1)
  _n_ondas=$(jq -r '.waves | length' "$_sd/state.json" 2>/dev/null) || _n_ondas="0"
  [ "$_n_ondas" -ge 1 ] || { _fail "onda_nao_persistida" "esperado >=1 onda, obtido $_n_ondas"; return 1; }

  _n_dec=$(jq -r '[.decisions[]? | select(.context | contains("SC-004"))] | length' "$_sd/state.json" 2>/dev/null) || _n_dec="0"
  [ "$_n_dec" = "1" ] || { _fail "decisao_nao_persistida" "esperado 1 decisao SC-004, obtido $_n_dec"; return 1; }

  _mode=$(jq -r '.mode // "-"' "$_sd/mcp-server.json" 2>/dev/null) || _mode="-"
  [ "$_mode" = "bash-fallback" ] || { _fail "descritor_mode" "esperado bash-fallback, obtido $_mode"; return 1; }

  return 0
}

run_all_scenarios "$0"
