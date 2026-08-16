#!/bin/sh
# test_command-spawn-mcp-lifecycle.sh — smoke textual sobre os 4 commands
# de spawn/resume que integram o ciclo de vida do servidor MCP (FASE 6
# task 6.2 da feature state-mcp-server).
#
# Feature: state-mcp-server
# Ref: docs/specs/state-mcp-server/tasks.md FASE 6 (6.2.1, 6.2.2, 6.2.3)
#      docs/specs/state-mcp-server/contracts/mcp-session-lifecycle.md
#        §"cstk mcp status" / §"cstk mcp start / stop" / §"cstk mcp status --live"
#
# Natureza: assert TEXTUAL no .md (nao ha helper novo nesta fase — a
# "implementacao" e a instrucao de status/start/stop embutida nos
# commands). Cobre as 4 fontes em plugins/cstk/commands/. NAO mapeia 1:1 a um
# unico .sh, portanto e registrado como interno em
# tests/run.sh::_is_internal_test (orphan-check) — mesmo padrao de
# test_command-spawn-model-routing.sh.
#
# Cobertura:
#   6.2.1 — /agente-00c e /feature-00c (inicio): `cstk mcp status` seguido
#     de `cstk mcp start`, ANTES do spawn do orquestrador, best-effort
#     (nunca aborta a pipeline).
#   6.2.2 — /agente-00c-resume e /feature-00c-resume: `cstk mcp status
#     --live` a cada retomada, sem reiniciar o container (paridade FR-011).
#   6.2.3 — encerramento: `cstk mcp stop` somente quando
#     `.execution.status` in {concluida, abortada}, nos 4 commands.
#   6.2.4 — nenhum dos 4 commands implementa geracao/injecao do token de
#     capacidade (task 1.2, cross-feature) — apenas documenta o
#     adiamento explicitamente.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CMD_INIT_AGENTE="$REPO_ROOT/plugins/cstk/commands/agente-00c.md"
CMD_INIT_FEAT="$REPO_ROOT/plugins/cstk/commands/feature-00c.md"
CMD_RES_AGENTE="$REPO_ROOT/plugins/cstk/commands/agente-00c-resume.md"
CMD_RES_FEAT="$REPO_ROOT/plugins/cstk/commands/feature-00c-resume.md"

# ==== 6.2.1: status + start ANTES do spawn, nos 2 commands de inicio ====

scenario_init_agente_instrui_mcp_status() {
  [ -f "$CMD_INIT_AGENTE" ] || { _error "arquivo ausente" "$CMD_INIT_AGENTE"; return 2; }
  assert_exit 0 grep -Eq 'cstk mcp status --state-dir' "$CMD_INIT_AGENTE" || return 1
}

scenario_init_agente_instrui_mcp_start() {
  assert_exit 0 grep -Eq 'cstk mcp start --state-dir' "$CMD_INIT_AGENTE" || return 1
}

scenario_init_feat_instrui_mcp_status() {
  [ -f "$CMD_INIT_FEAT" ] || { _error "arquivo ausente" "$CMD_INIT_FEAT"; return 2; }
  assert_exit 0 grep -Eq 'cstk mcp status --state-dir' "$CMD_INIT_FEAT" || return 1
}

scenario_init_feat_instrui_mcp_start() {
  assert_exit 0 grep -Eq 'cstk mcp start --state-dir' "$CMD_INIT_FEAT" || return 1
}

# status/start devem vir ANTES da secao "4. Selecao de modelo" (agente-00c)
# / "4. Selecionar modelo" (feature-00c), i.e. antes do spawn.
scenario_init_agente_mcp_antes_do_spawn() {
  _linha_mcp=$(grep -n 'cstk mcp start --state-dir' "$CMD_INIT_AGENTE" | head -1 | cut -d: -f1)
  _linha_spawn=$(grep -n '^### 4\. Selecao de modelo' "$CMD_INIT_AGENTE" | head -1 | cut -d: -f1)
  [ -n "$_linha_mcp" ] && [ -n "$_linha_spawn" ] || { _error "secao ausente" "mcp=$_linha_mcp spawn=$_linha_spawn"; return 1; }
  [ "$_linha_mcp" -lt "$_linha_spawn" ] || { _fail "ordem" "mcp start (linha $_linha_mcp) deveria vir antes do spawn (linha $_linha_spawn)"; return 1; }
  return 0
}

scenario_init_feat_mcp_antes_do_spawn() {
  _linha_mcp=$(grep -n 'cstk mcp start --state-dir' "$CMD_INIT_FEAT" | head -1 | cut -d: -f1)
  _linha_spawn=$(grep -n '^### 4\. Selecionar modelo' "$CMD_INIT_FEAT" | head -1 | cut -d: -f1)
  [ -n "$_linha_mcp" ] && [ -n "$_linha_spawn" ] || { _error "secao ausente" "mcp=$_linha_mcp spawn=$_linha_spawn"; return 1; }
  [ "$_linha_mcp" -lt "$_linha_spawn" ] || { _fail "ordem" "mcp start (linha $_linha_mcp) deveria vir antes do spawn (linha $_linha_spawn)"; return 1; }
  return 0
}

# ==== 6.2.2: status --live a cada retomada, sem restart ====

scenario_resume_agente_instrui_mcp_status_live() {
  [ -f "$CMD_RES_AGENTE" ] || { _error "arquivo ausente" "$CMD_RES_AGENTE"; return 2; }
  assert_exit 0 grep -Eq 'cstk mcp status --state-dir.*--live|cstk mcp status.*<SD>.*--live' "$CMD_RES_AGENTE" || return 1
}

scenario_resume_feat_instrui_mcp_status_live() {
  [ -f "$CMD_RES_FEAT" ] || { _error "arquivo ausente" "$CMD_RES_FEAT"; return 2; }
  assert_exit 0 grep -Eq -- '--live' "$CMD_RES_FEAT" || return 1
}

scenario_resume_agente_menciona_sem_restart() {
  # FR-010: verificar saude SEM reiniciar o container.
  assert_exit 0 grep -Eiq 'sem restart|sem reiniciar|nao reinicia' "$CMD_RES_AGENTE" || return 1
}

scenario_resume_feat_menciona_sem_restart() {
  assert_exit 0 grep -Eiq 'sem restart|sem reiniciar|nao reinicia' "$CMD_RES_FEAT" || return 1
}

# ==== 6.2.3: stop somente em estado terminal (concluida|abortada) ====

scenario_init_agente_instrui_mcp_stop_terminal() {
  assert_exit 0 grep -Eq 'cstk mcp stop --state-dir' "$CMD_INIT_AGENTE" || return 1
  assert_exit 0 grep -Eq 'concluida|abortada' "$CMD_INIT_AGENTE" || return 1
}

scenario_init_feat_instrui_mcp_stop_terminal() {
  assert_exit 0 grep -Eq 'cstk mcp stop --state-dir' "$CMD_INIT_FEAT" || return 1
  assert_exit 0 grep -Eq 'concluida|abortada' "$CMD_INIT_FEAT" || return 1
}

scenario_resume_agente_instrui_mcp_stop_terminal() {
  assert_exit 0 grep -Eq 'cstk mcp stop --state-dir' "$CMD_RES_AGENTE" || return 1
}

scenario_resume_feat_instrui_mcp_stop_terminal() {
  assert_exit 0 grep -Eq 'cstk mcp stop --state-dir' "$CMD_RES_FEAT" || return 1
}

# aguardando_humano NAO deve disparar stop (FR-010: sessao coextensiva com
# a execucao inteira, sobrevive a pausas entre ondas).
scenario_resume_agente_nao_para_em_aguardando_humano() {
  assert_exit 0 grep -Eq 'aguardando_humano.*NAO e terminal|NAO e terminal' "$CMD_RES_AGENTE" || return 1
}

scenario_resume_feat_nao_para_em_aguardando_humano() {
  assert_exit 0 grep -Eq 'aguardando_humano.*NAO e terminal|NAO e terminal' "$CMD_RES_FEAT" || return 1
}

# ==== dec-043 (consumada): injecao do token de capacidade no spawn ====
# A coordenacao cross-feature da task 1.2 foi CONSUMADA pos-v6.1.0: os 4
# commands leem o descritor mcp-server.json e injetam o session_id no
# contexto do spawn do orquestrador (SEC-H3: capacidade, nunca precedencia).

scenario_init_agente_injeta_token_no_spawn() {
  assert_exit 0 grep -Eiq 'token de capacidade' "$CMD_INIT_AGENTE" || return 1
  assert_exit 0 grep -Eq 'mcp-server\.json' "$CMD_INIT_AGENTE" || return 1
  assert_exit 0 grep -Eq '\.session_id' "$CMD_INIT_AGENTE" || return 1
  assert_exit 0 grep -Eq 'mcp__cstk-state__' "$CMD_INIT_AGENTE" || return 1
}

scenario_init_feat_injeta_token_no_spawn() {
  assert_exit 0 grep -Eiq 'token de capacidade' "$CMD_INIT_FEAT" || return 1
  assert_exit 0 grep -Eq 'mcp-server\.json' "$CMD_INIT_FEAT" || return 1
  assert_exit 0 grep -Eq '\.session_id' "$CMD_INIT_FEAT" || return 1
  assert_exit 0 grep -Eq 'mcp__cstk-state__' "$CMD_INIT_FEAT" || return 1
}

scenario_resume_agente_injeta_token_no_spawn() {
  assert_exit 0 grep -Eq 'mcp-server\.json' "$CMD_RES_AGENTE" || return 1
  assert_exit 0 grep -Eq '\.session_id' "$CMD_RES_AGENTE" || return 1
  assert_exit 0 grep -Eq 'mcp__cstk-state__' "$CMD_RES_AGENTE" || return 1
}

scenario_resume_feat_injeta_token_no_spawn() {
  assert_exit 0 grep -Eq 'mcp-server\.json' "$CMD_RES_FEAT" || return 1
  assert_exit 0 grep -Eq '\.session_id' "$CMD_RES_FEAT" || return 1
  assert_exit 0 grep -Eq 'mcp__cstk-state__' "$CMD_RES_FEAT" || return 1
}

scenario_token_nunca_ecoado_em_logs() {
  # Os 4 arquivos declaram explicitamente que o token nao vai a stdout/logs.
  for _f in "$CMD_INIT_AGENTE" "$CMD_INIT_FEAT" "$CMD_RES_AGENTE" "$CMD_RES_FEAT"; do
    grep -Eiq 'token NUNCA e? ?ecoado' "$_f" \
      || { _fail "declaracao de nao-eco do token ausente" "$_f"; return 1; }
  done
}

scenario_token_fallback_sem_mcp_no_prompt() {
  # Token vazio => prompt sem mencao a MCP (zero regressao, SC-004).
  for _f in "$CMD_INIT_AGENTE" "$CMD_INIT_FEAT" "$CMD_RES_AGENTE" "$CMD_RES_FEAT"; do
    grep -Eiq 'NAO mencione MCP' "$_f" \
      || { _fail "instrucao de fallback sem-MCP ausente" "$_f"; return 1; }
  done
}

# ==== mcp-direct-transport FASE 4 (FR-013): injecao generalizada, ====
# ==== independente de `mode` — condicao antiga `mode == "docker"` removida ====
# Ref: docs/specs/mcp-direct-transport/tasks.md 4.1/4.2;
#      contracts/cli-mcp-lifecycle.md §7 (P-1, P-2, P-3).

scenario_token_injecao_nao_condicionada_a_mode_nos_4_commands() {
  # A variavel _mcp_mode existia SO para gatear a injecao do token a
  # mode=="docker". Apos FR-013, a injecao le session_id direto do
  # descritor — _mcp_mode nao deve mais aparecer em nenhum dos 4 commands.
  for _f in "$CMD_INIT_AGENTE" "$CMD_INIT_FEAT" "$CMD_RES_AGENTE" "$CMD_RES_FEAT"; do
    if grep -Eq '_mcp_mode' "$_f"; then
      _fail "_mcp_mode ainda presente (condicao docker nao removida)" "$_f"
      return 1
    fi
  done
}

scenario_token_le_session_id_sem_guard_de_mode() {
  # Leitura de _mcp_token deve ser incondicional (nao dentro de um
  # `if [ ... = "docker" ]`) nos 4 commands.
  for _f in "$CMD_INIT_AGENTE" "$CMD_INIT_FEAT" "$CMD_RES_AGENTE" "$CMD_RES_FEAT"; do
    assert_exit 0 grep -Eq '_mcp_token=\$\(jq -r .\.session_id' "$_f" || return 1
  done
}

scenario_prosa_documenta_independencia_de_mode() {
  # Cada bloco de injecao deve declarar explicitamente a independencia de
  # `mode` (P-2 do contrato) — nao basta o codigo mudar silenciosamente.
  for _f in "$CMD_INIT_AGENTE" "$CMD_INIT_FEAT" "$CMD_RES_AGENTE" "$CMD_RES_FEAT"; do
    assert_exit 0 grep -Eiq 'independentemente do valor de .mode.' "$_f" || return 1
  done
}

# ==== Best-effort: chamadas MCP nunca abortam a pipeline (FR-007/FR-012) ====

scenario_init_agente_mcp_best_effort() {
  assert_exit 0 grep -Eiq 'best-effort' "$CMD_INIT_AGENTE" || return 1
}

scenario_init_feat_mcp_best_effort() {
  assert_exit 0 grep -Eiq 'best-effort' "$CMD_INIT_FEAT" || return 1
}

run_all_scenarios "$0"
