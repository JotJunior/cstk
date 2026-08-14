#!/bin/sh
# test_roadmap-mode.sh — cobre
# plugins/cstk/skills/agente-00c-runtime/scripts/roadmap-mode.sh (task 2.2,
# feature roadmap-mode).
#
# Cobertura:
#   is-enabled: ausencia de campo => false; true => true; false => false;
#               estado ilegivel (state-dir inexistente) => false; exit 0 sempre
#   set-enabled: sucesso (grava via state-rw.sh, backup+sha256);
#                valor invalido => exit 2;
#                trava write-once apos etapa posterior a constitution => exit 2

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/roadmap-mode.sh"
SCRIPT_RW="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/state-rw.sh"
SCRIPT_ONDAS="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/state-ondas.sh"
ORCH_AGENTE="$REPO_ROOT/plugins/cstk/agents/agente-00c-orchestrator.md"

if ! command -v jq >/dev/null 2>&1; then
  printf '# test_roadmap-mode.sh: jq ausente — pulando suite (instale: brew install jq)\n'
  exit 0
fi

# ==== helpers ====

# Cria um state minimo com roadmap_mode_enabled=$2 (default false).
_init_state() {
  _idir=$1
  _rm=${2:-false}
  sh "$SCRIPT_RW" init --state-dir "$_idir" \
    --projeto-alvo-path "/tmp/cstk-test" \
    --descricao "teste roadmap-mode (>=10 chars)" \
    --execucao-id "exec-rm-test-001" \
    --roadmap-mode "$_rm" 2>/dev/null
}

# ==== is-enabled ====

scenario_is_enabled_campo_ausente_retorna_false() {
  # Forca backend JSON (HOME isolado sem ~/.claude/cstk/config) para poder
  # remover o campo via jq e simular state legado, independente da config
  # global da maquina que roda a suite.
  _home="$TMPDIR_TEST/home-ausencia"
  mkdir -p "$_home"
  _sd="$TMPDIR_TEST/is-ausente"
  env HOME="$_home" sh "$SCRIPT_RW" init --state-dir "$_sd" \
    --projeto-alvo-path "/tmp/cstk-test" \
    --descricao "teste roadmap-mode (>=10 chars)" \
    --execucao-id "exec-rm-test-002" 2>/dev/null
  _sf="$_sd/state.json"
  [ -f "$_sf" ] || { _fail "fixture: state.json esperado (backend json)" ""; return 1; }
  _tmp=$(mktemp)
  jq 'del(.roadmap_mode_enabled)' "$_sf" > "$_tmp" && mv "$_tmp" "$_sf"
  env HOME="$_home" sh "$SCRIPT_RW" sha256-update --state-dir "$_sd" 2>/dev/null || :

  capture env HOME="$_home" "$SCRIPT" is-enabled --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT"; return 1; }
  [ "$_CAPTURED_STDOUT" = "false" ] || { _fail "stdout esperado 'false'" "obtido '$_CAPTURED_STDOUT'"; return 1; }
}

scenario_is_enabled_campo_true_retorna_true() {
  _sd="$TMPDIR_TEST/is-true"
  _init_state "$_sd" true
  capture "$SCRIPT" is-enabled --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT"; return 1; }
  [ "$_CAPTURED_STDOUT" = "true" ] || { _fail "stdout esperado 'true'" "obtido '$_CAPTURED_STDOUT'"; return 1; }
}

scenario_is_enabled_campo_false_retorna_false() {
  _sd="$TMPDIR_TEST/is-false"
  _init_state "$_sd" false
  capture "$SCRIPT" is-enabled --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT"; return 1; }
  [ "$_CAPTURED_STDOUT" = "false" ] || { _fail "stdout esperado 'false'" "obtido '$_CAPTURED_STDOUT'"; return 1; }
}

scenario_is_enabled_state_dir_inexistente_retorna_false_exit0() {
  _sd="$TMPDIR_TEST/is-inexistente/nao-existe"
  capture "$SCRIPT" is-enabled --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0 (contrato exit-0-sempre)" "obtido $_CAPTURED_EXIT"; return 1; }
  [ "$_CAPTURED_STDOUT" = "false" ] || { _fail "stdout esperado 'false'" "obtido '$_CAPTURED_STDOUT'"; return 1; }
}

# ==== set-enabled ====

scenario_set_enabled_grava_via_state_rw() {
  _sd="$TMPDIR_TEST/set-ok"
  _init_state "$_sd" false
  _hist_before=$(ls "$_sd/state-history/" 2>/dev/null | wc -l | tr -d ' ')

  capture "$SCRIPT" set-enabled --state-dir "$_sd" --value true
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "set-enabled exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }

  _hist_after=$(ls "$_sd/state-history/" 2>/dev/null | wc -l | tr -d ' ')
  [ "$_hist_after" -gt "$_hist_before" ] || { _fail "state-history nao cresceu" "antes=$_hist_before depois=$_hist_after"; return 1; }

  sh "$SCRIPT_RW" sha256-verify --state-dir "$_sd" >/dev/null 2>&1 \
    || { _fail "sha256-verify falhou apos set-enabled" ""; return 1; }

  capture "$SCRIPT" is-enabled --state-dir "$_sd"
  [ "$_CAPTURED_STDOUT" = "true" ] || { _fail "is-enabled apos set-enabled true" "obtido '$_CAPTURED_STDOUT'"; return 1; }
}

scenario_set_enabled_valor_invalido_exit2() {
  _sd="$TMPDIR_TEST/set-invalid"
  _init_state "$_sd" false
  capture "$SCRIPT" set-enabled --state-dir "$_sd" --value "yes"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit esperado 2" "obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_set_enabled_sem_state_dir_exit2() {
  capture "$SCRIPT" set-enabled --value true
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit esperado 2 (--state-dir obrigatorio)" "obtido $_CAPTURED_EXIT"; return 1; }
}

# Trava write-once (MUST): onda que ja executou etapa posterior a
# `constitution` (ex: specify) bloqueia set-enabled, exit 2, sem escrever.
scenario_set_enabled_trava_write_once_apos_specify() {
  _sd="$TMPDIR_TEST/set-write-once"
  _init_state "$_sd" false
  sh "$SCRIPT_ONDAS" start --state-dir "$_sd" >/dev/null 2>&1
  sh "$SCRIPT_ONDAS" end --state-dir "$_sd" \
    --motivo-termino etapa_concluida_avancando --add-etapa specify >/dev/null 2>&1

  capture "$SCRIPT" set-enabled --state-dir "$_sd" --value true
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit esperado 2 (write-once)" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "write-once" || return 1

  # Nao deveria ter escrito nada: campo continua false.
  capture "$SCRIPT" is-enabled --state-dir "$_sd"
  [ "$_CAPTURED_STDOUT" = "false" ] || { _fail "write-once nao deveria ter gravado" "obtido '$_CAPTURED_STDOUT'"; return 1; }
}

# Contra-exemplo: ondas que so executaram briefing/constitution NAO
# bloqueiam (a lista escopada do modo roadmap e exatamente essas duas +
# a propria etapa roadmap).
scenario_set_enabled_permitido_apos_apenas_briefing_constitution() {
  _sd="$TMPDIR_TEST/set-permitido"
  _init_state "$_sd" false
  sh "$SCRIPT_ONDAS" start --state-dir "$_sd" >/dev/null 2>&1
  sh "$SCRIPT_ONDAS" end --state-dir "$_sd" \
    --motivo-termino etapa_concluida_avancando --add-etapa briefing >/dev/null 2>&1
  sh "$SCRIPT_ONDAS" start --state-dir "$_sd" >/dev/null 2>&1
  sh "$SCRIPT_ONDAS" end --state-dir "$_sd" \
    --motivo-termino etapa_concluida_avancando --add-etapa constitution >/dev/null 2>&1

  capture "$SCRIPT" set-enabled --state-dir "$_sd" --value true
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0 (apenas briefing+constitution)" "obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
}

# ==== Encerramento terminal do modo roadmap (FASE 4, FR-004) ====
# Prosa textual em agente-00c-orchestrator.md — regressao de seguranca M1
# do quickstart Cenario 12: finalize (git push) MUST rodar com a guarda
# enforced ainda ATIVA, ou seja, ANTES da promocao de status terminal.

scenario_orchestrator_tem_bloco_encerramento_roadmap() {
  [ -f "$ORCH_AGENTE" ] || { _fail "arquivo ausente" "$ORCH_AGENTE"; return 2; }
  assert_exit 0 grep -Eq 'Encerramento terminal do modo roadmap' "$ORCH_AGENTE" || return 1
}

scenario_orchestrator_grava_termination_reason_concluido_roadmap() {
  assert_exit 0 grep -Eq 'concluido_roadmap' "$ORCH_AGENTE" || return 1
}

scenario_orchestrator_menciona_5_campos_write_multi_campo() {
  assert_exit 0 grep -Eiq '5 campos terminais' "$ORCH_AGENTE" || return 1
}

# Ordem textual: dentro do bloco de encerramento roadmap, "commit-mode.sh
# finalize" (passo 2) MUST aparecer em linha anterior a "concluido_roadmap"
# (passo 4 — promocao terminal). Inversao = regressao de seguranca M1.
scenario_orchestrator_finalize_antes_da_promocao_terminal() {
  _heading_line=$(grep -n 'Encerramento terminal do modo roadmap' "$ORCH_AGENTE" | head -1 | cut -d: -f1)
  [ -n "$_heading_line" ] || { _fail "heading nao encontrado" ""; return 1; }

  _finalize_line=$(tail -n "+$_heading_line" "$ORCH_AGENTE" | grep -n 'commit-mode.sh finalize' | head -1 | cut -d: -f1)
  _promocao_line=$(tail -n "+$_heading_line" "$ORCH_AGENTE" | grep -n 'concluido_roadmap' | head -1 | cut -d: -f1)
  [ -n "$_finalize_line" ] || { _fail "commit-mode.sh finalize nao encontrado apos o heading" ""; return 1; }
  [ -n "$_promocao_line" ] || { _fail "concluido_roadmap nao encontrado apos o heading" ""; return 1; }

  [ "$_finalize_line" -lt "$_promocao_line" ] \
    || { _fail "ordem invertida: finalize deve aparecer antes da promocao terminal" "finalize=$_finalize_line promocao=$_promocao_line"; return 1; }
}

scenario_orchestrator_menciona_guarda_enforced_ativa_no_bloco() {
  _heading_line=$(grep -n 'Encerramento terminal do modo roadmap' "$ORCH_AGENTE" | head -1 | cut -d: -f1)
  [ -n "$_heading_line" ] || { _fail "heading nao encontrado" ""; return 1; }
  assert_exit 0 sh -c "tail -n '+$_heading_line' '$ORCH_AGENTE' | grep -Eq 'guarda enforced'" || return 1
}

run_all_scenarios
