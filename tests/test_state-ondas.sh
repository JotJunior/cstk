#!/bin/sh
# test_state-ondas.sh — cobre plugins/cstk/skills/agente-00c-runtime/scripts/state-ondas.sh.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/state-ondas.sh"
RW="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/state-rw.sh"

if ! command -v jq >/dev/null 2>&1; then
  printf '# test_state-ondas.sh: jq ausente — pulando suite\n'
  exit 0
fi

_init_state() {
  # $2 opcional: projeto-alvo-path real (default "/tmp/p" para cenarios que
  # nao exercitam git de verdade). Cenarios de git-commit precisam do path
  # REAL para que `state-ondas.sh start` (living-specs FASE 5) consiga
  # derivar .execution.target_project_path e capturar o baseline de
  # untracked no inicio da onda.
  _init_pap="${2:-/tmp/p}"
  capture "$RW" init --state-dir "$1" \
    --execucao-id "exec-onda-test" --projeto-alvo-path "$_init_pap" --descricao "POC ondas"
}

scenario_start_cria_onda_001() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "start" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "onda-001" || return 1
  capture "$SCRIPT" current-id --state-dir "$_sd"
  assert_stdout_contains "onda-001" || return 1
}

scenario_start_sequencial_gera_onda_002() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando
  capture "$SCRIPT" start --state-dir "$_sd"
  assert_stdout_contains "onda-002" || return 1
}


# budget-resume-wallclock (FR-004/SC-001/SC-003): `start` reseta
# .budgets.current_wave_start mesmo quando a onda ANTERIOR foi fechada com
# um current_wave_start herdado ja no passado (o cenario real de uma
# retomada: `end` NAO reseta o campo — ver comentario acima de
# `_so_cmd_start`). O state "onda encerrada + current_wave_start antigo"
# preparado aqui representa uniformemente AMBOS os caminhos de retomada do
# feature-00c (pos-agendamento e pos-bloqueio-humano) — ver invariante
# "resume sempre segue onda fechada" em agente-00c-feature-orchestrator.md.
scenario_start_apos_onda_fechada_reseta_wallclock() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando
  # Simula o campo herdado da onda ja fechada apontando bem no passado.
  capture "$RW" set --state-dir "$_sd" \
    --field '.budgets.current_wave_start' --value '"2020-01-01T00:00:00Z"'
  capture "$RW" get --state-dir "$_sd" --field '.budgets.current_wave_start'
  assert_stdout_contains "2020-01-01" || return 1
  # Retomada: state-ondas.sh start (passo 3.bis) DEVE regravar current_wave_start.
  capture "$SCRIPT" start --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "start pos-retomada" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "onda-002" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.budgets.current_wave_start'
  assert_stdout_not_contains "2020-01-01" || return 1
}

# ==== mcp-elicitation-optins FASE 9 (M4, task 9.3.1): guarda mecanica da
# Invariante I-2 — `start` recusa abrir onda-001 se houver `field`
# aplicavel ao executionKind (derivado do LAYOUT do state-dir — mesmo
# padrao de _hook-active-exec.sh/mcp-session.sh) sem NENHUM registro em
# `.optin_responses[]`. Onda-002+ nunca e gateada (o campo so precisa ser
# resolvido uma vez, no nascimento da execucao). ====

scenario_start_onda001_recusada_sem_optin_feature00c() {
  _sd="$TMPDIR_TEST/feature-00c-state/demo-feature/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" != 0 ] || { _fail "start deveria recusar onda-001 sem optin" "obtido exit 0"; return 1; }
  assert_stderr_contains "optin-invariant-i2" || return 1
  assert_stderr_contains "atomic_commit" || return 1
}

scenario_start_onda001_aceita_com_optin_feature00c() {
  _sd="$TMPDIR_TEST/feature-00c-state/demo-feature/state"
  _init_state "$_sd"
  capture "$RW" set --state-dir "$_sd" --field '.optin_responses' \
    --value '[{"field":"atomic_commit","channel":"structured","outcome":"accepted","applied_value":"true","recorded_at":"2026-08-17T00:00:00Z","reason":null}]'
  capture "$SCRIPT" start --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "start" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "onda-001" || return 1
}

scenario_start_onda001_recusada_agente00c_faltam_2_de_3_campos() {
  _sd="$TMPDIR_TEST/agente-00c-state"
  _init_state "$_sd"
  capture "$RW" set --state-dir "$_sd" --field '.optin_responses' \
    --value '[{"field":"atomic_commit","channel":"structured","outcome":"accepted","applied_value":"true","recorded_at":"2026-08-17T00:00:00Z","reason":null}]'
  capture "$SCRIPT" start --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" != 0 ] || { _fail "start deveria recusar" "obtido exit 0"; return 1; }
  assert_stderr_contains "roadmap_mode" || return 1
  assert_stderr_contains "delivery_tier" || return 1
}

# Prova que "aplicavel" e QUALQUER registro (nao so terminal — Regra R-2 de
# data-model.md e sobre a Invariante I-1, nao I-2): unavailable/failed
# (o mecanismo TENTOU) tambem satisfazem a guarda.
scenario_start_onda001_aceita_agente00c_com_registro_nao_terminal() {
  _sd="$TMPDIR_TEST/agente-00c-state"
  _init_state "$_sd"
  capture "$RW" set --state-dir "$_sd" --field '.optin_responses' \
    --value '[{"field":"atomic_commit","channel":"structured","outcome":"accepted","applied_value":"true","recorded_at":"2026-08-17T00:00:00Z","reason":null},{"field":"roadmap_mode","channel":"structured","outcome":"declined","applied_value":"false","recorded_at":"2026-08-17T00:00:01Z","reason":null},{"field":"delivery_tier","channel":"structured","outcome":"unavailable","applied_value":"cloud-public","recorded_at":"2026-08-17T00:00:02Z","reason":null}]'
  capture "$SCRIPT" start --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "start" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "onda-001" || return 1
}

scenario_start_onda002_nao_e_gateada_pela_invariante_i2() {
  _sd="$TMPDIR_TEST/feature-00c-state/demo-feature/state"
  _init_state "$_sd"
  capture "$RW" set --state-dir "$_sd" --field '.optin_responses' \
    --value '[{"field":"atomic_commit","channel":"structured","outcome":"accepted","applied_value":"true","recorded_at":"2026-08-17T00:00:00Z","reason":null}]'
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando
  capture "$SCRIPT" start --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "start onda-002" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "onda-002" || return 1
}

# Layout sinteticos/nao-canonicos (sem /feature-00c-state/ nem
# /agente-00c-state) sao NO-OP — sem como derivar executionKind com
# confianca, a guarda nao adivinha (evita falso-positivo generalizado, ex.:
# state-dirs de teste com paths arbitrarios).
scenario_start_onda001_layout_desconhecido_nao_e_gateado() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "start (layout desconhecido)" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "onda-001" || return 1
}

scenario_tool_call_tick_incrementa() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" tool-call-tick --state-dir "$_sd"
  assert_stdout_contains "1" || return 1
  capture "$SCRIPT" tool-call-tick --state-dir "$_sd"
  assert_stdout_contains "2" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.budgets.tool_calls_current_wave'
  assert_stdout_contains "2" || return 1
}

scenario_end_atualiza_onda_e_acumulados() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" tool-call-tick --state-dir "$_sd"
  capture "$SCRIPT" tool-call-tick --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino bloqueio_humano \
    --add-etapa briefing
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "end" "$_CAPTURED_STDERR"; return 1; }
  capture "$RW" get --state-dir "$_sd" --field '.waves[-1].termination_reason'
  assert_stdout_contains "bloqueio_humano" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.waves[-1].tool_calls'
  assert_stdout_contains "2" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.accumulated_metrics.waves_total'
  assert_stdout_contains "1" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.accumulated_metrics.tool_calls_total'
  assert_stdout_contains "2" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.waves[-1].executed_stages'
  assert_stdout_contains "briefing" || return 1
}

# --next-instruction: grava .next_instruction NO MESMO write atomico do
# fechamento da onda. Antes exigia um `state-rw.sh set` separado; como
# `end` tambem escreve no state.json, seguir a ordem literal
# backup -> hash -> end do prompt deixava backup/sha defasados.
scenario_end_next_instruction_grava_no_mesmo_write() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando \
    --next-instruction "Retomar em plan: rodar skill plan sobre docs/specs/x"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "end" "$_CAPTURED_STDERR"; return 1; }
  capture "$RW" get --state-dir "$_sd" --field '.next_instruction'
  assert_stdout_contains "Retomar em plan" || return 1

  # O sha256 gravado por `end` precisa bater com o state.json final —
  # e exatamente isso que o caminho antigo (set separado APOS end)
  # quebrava.
  if [ -f "$_sd/state.json.sha256" ]; then
    _expected=$(awk '{print $1}' "$_sd/state.json.sha256")
    if command -v shasum >/dev/null 2>&1; then
      _actual=$(shasum -a 256 "$_sd/state.json" | awk '{print $1}')
    elif command -v sha256sum >/dev/null 2>&1; then
      _actual=$(sha256sum "$_sd/state.json" | awk '{print $1}')
    else
      _actual="$_expected"
    fi
    [ "$_expected" = "$_actual" ] \
      || { _fail "sha256 defasado apos end --next-instruction" "esperado $_expected, obtido $_actual"; return 1; }
  fi
  return 0
}

# Sem a flag, .next_instruction NAO e tocado por `end`.
scenario_end_sem_next_instruction_preserva_campo() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$RW" set --state-dir "$_sd" --field '.next_instruction' --value '"valor previo"'
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "end" "$_CAPTURED_STDERR"; return 1; }
  capture "$RW" get --state-dir "$_sd" --field '.next_instruction'
  assert_stdout_contains "valor previo" || return 1
  return 0
}

# Texto com aspas/newline nao pode quebrar o JSON (serializado via jq -Rs).
scenario_end_next_instruction_texto_com_aspas() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando \
    --next-instruction 'usar "aspas" e $cifrao no texto'
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "end" "$_CAPTURED_STDERR"; return 1; }
  jq -e . "$_sd/state.json" >/dev/null 2>&1 \
    || { _fail "state.json invalido apos --next-instruction com aspas" "jq falhou"; return 1; }
  _got=$(jq -r '.next_instruction' "$_sd/state.json")
  [ "$_got" = 'usar "aspas" e $cifrao no texto' ] \
    || { _fail "next_instruction corrompido" "obtido '$_got'"; return 1; }
  return 0
}

scenario_end_next_instruction_vazia_exit2() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando \
    --next-instruction ""
  [ "$_CAPTURED_EXIT" = 2 ] \
    || { _fail "valor vazio" "esperado exit 2, obtido $_CAPTURED_EXIT"; return 1; }
  return 0
}

# record-task: task_id = heading "### N.M" do tasks.md, nunca N.M.K
# (subtarefa/checkbox). Gravar no nivel errado ja aconteceu em campo (7
# entradas, so descobertas depois pelo reconcile-tasks). Aviso, nao erro.
scenario_record_task_id_com_3_niveis_avisa_sem_falhar() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" record-task --state-dir "$_sd" --task-id "4.1.1" --outcome pass
  [ "$_CAPTURED_EXIT" = 0 ] \
    || { _fail "record-task deve continuar gravando" "obtido exit $_CAPTURED_EXIT"; return 1; }
  printf '%s' "$_CAPTURED_STDERR" | grep -q 'AVISO' \
    || { _fail "esperado aviso de nivel em stderr" "stderr: $_CAPTURED_STDERR"; return 1; }
  # Aviso nao pode impedir a gravacao.
  _got=$(jq -r '.tasks[-1].task_id' "$_sd/state.json")
  [ "$_got" = "4.1.1" ] || { _fail "entrada nao gravada" "obtido '$_got'"; return 1; }
  return 0
}

scenario_record_task_id_dois_niveis_sem_aviso() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" record-task --state-dir "$_sd" --task-id "4.1" --outcome pass
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "record-task" "$_CAPTURED_STDERR"; return 1; }
  printf '%s' "$_CAPTURED_STDERR" | grep -q 'AVISO' \
    && { _fail "N.M nao pode disparar aviso de nivel" "stderr: $_CAPTURED_STDERR"; return 1; }
  return 0
}

scenario_end_motivo_invalido_falha() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino motivo_invalido
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "motivo invalido" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_end_sem_onda_em_andamento_falha() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "end sem onda" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  # Mensagem legada permanece byte-a-byte identica (SC-006, openspec-hygiene).
  assert_stderr_contains "nao ha onda em andamento" || return 1
  # Envelope diagnostico aditivo (openspec-hygiene FR-012/FR-015).
  assert_stderr_contains "DIAG|error|no-open-wave|" || return 1
}

scenario_proxima_agendada_para_persiste() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando \
    --proxima-agendada-para "2026-05-05T15:30:00Z"
  capture "$RW" get --state-dir "$_sd" --field '.waves[-1].next_wave_scheduled_for'
  assert_stdout_contains "2026-05-05T15:30:00Z" || return 1
}

scenario_current_id_retorna_init_sem_onda() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" current-id --state-dir "$_sd"
  assert_stdout_contains "init" || return 1
}

scenario_git_commit_cria_commit() {
  _sd="$TMPDIR_TEST/state"
  _pap="$TMPDIR_TEST/proj"
  mkdir -p "$_pap"
  ( cd "$_pap" && git init -q -b main \
    && git config user.email t@t \
    && git config user.name t )
  # state.json aponta para o repo REAL (nao o fake "/tmp/p") + start ANTES
  # de qualquer arquivo novo: e o `start` (living-specs FASE 5) quem
  # captura o baseline de untracked "no inicio da onda" (data-model.md
  # UntrackedBaseline) — hello.txt so entra no diff porque e criado DEPOIS
  # do baseline, nunca porque git-commit varre tudo cegamente.
  _init_state "$_sd" "$_pap"
  capture "$SCRIPT" start --state-dir "$_sd"
  ( cd "$_pap" && touch hello.txt )
  capture "$SCRIPT" git-commit --state-dir "$_sd" --projeto-alvo-path "$_pap" \
    --motivo "test commit FASE 3"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "commit" "$_CAPTURED_STDERR"; return 1; }
  _msg=$(git -C "$_pap" log -1 --pretty=%s)
  case "$_msg" in
    *"chore(agente-00c):"*"test commit FASE 3"*) ;;
    *) _fail "commit msg" "esperado contem 'chore(agente-00c)' e motivo; obtido: $_msg"; return 1 ;;
  esac
  _shown=$(git -C "$_pap" show --name-only --format= HEAD)
  case "$_shown" in
    *hello.txt*) : ;;
    *) _fail "hello.txt deveria estar no commit" "obtido: $_shown"; return 1 ;;
  esac
}

scenario_git_commit_idempotente_sem_changes() {
  _sd="$TMPDIR_TEST/state"
  _pap="$TMPDIR_TEST/proj"
  _init_state "$_sd"
  mkdir -p "$_pap"
  ( cd "$_pap" && git init -q -b main \
    && git config user.email t@t && git config user.name t \
    && touch x && git add . && git commit -q -m initial )
  capture "$SCRIPT" git-commit --state-dir "$_sd" --projeto-alvo-path "$_pap" \
    --motivo "noop"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "no-op exit" "$_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "nada para commitar" || return 1
}

scenario_git_commit_sem_repo_falha() {
  _sd="$TMPDIR_TEST/state"
  _pap="$TMPDIR_TEST/notrepo"
  _init_state "$_sd"
  mkdir -p "$_pap"
  capture "$SCRIPT" git-commit --state-dir "$_sd" --projeto-alvo-path "$_pap" \
    --motivo "x"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "sem repo" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "nao e repositorio git" || return 1
}

# ==== record-skill (defesa contra dec-014 da exec rolledback) ====
scenario_record_skill_append_basico() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" record-skill --state-dir "$_sd" --skill briefing --decisao-id dec-001
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT; $_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "1" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.waves[-1].skills_invoked[0].skill'
  assert_stdout_contains "briefing" || return 1
}

scenario_record_skill_idempotente_mesma_skill_e_decisao() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" record-skill --state-dir "$_sd" --skill constitution --decisao-id dec-004
  capture "$SCRIPT" record-skill --state-dir "$_sd" --skill constitution --decisao-id dec-004
  assert_stdout_contains "1" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.waves[-1].skills_invoked | length'
  assert_stdout_contains "1" || return 1
}

scenario_record_skill_multiplas_skills_acumulam() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" record-skill --state-dir "$_sd" --skill briefing --decisao-id dec-001
  capture "$SCRIPT" record-skill --state-dir "$_sd" --skill constitution --decisao-id dec-004
  capture "$SCRIPT" record-skill --state-dir "$_sd" --skill create-tasks --decisao-id dec-014
  assert_stdout_contains "3" || return 1
}

scenario_record_skill_sem_decisao_id_funciona() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" record-skill --state-dir "$_sd" --skill briefing
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "1" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.waves[-1].skills_invoked[0].decision_id'
  assert_stdout_contains "null" || return 1
}

# ==== record-skill --kind (higiene da metrica de skills, revisao 5.15.0) ====

scenario_record_skill_kind_default_e_skill() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" record-skill --state-dir "$_sd" --skill specify --decisao-id dec-001
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_STDERR"; return 1; }
  capture "$RW" get --state-dir "$_sd" --field '.waves[-1].skills_invoked[0].kind'
  assert_stdout_contains "skill" || return 1
}

scenario_record_skill_kind_gate_gravado() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" record-skill --state-dir "$_sd" \
    --skill validate-tasks-template --decisao-id dec-002 --kind gate
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_STDERR"; return 1; }
  capture "$RW" get --state-dir "$_sd" --field '.waves[-1].skills_invoked[0].kind'
  assert_stdout_contains "gate" || return 1
}

scenario_record_skill_kind_invalido_usage() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" record-skill --state-dir "$_sd" --skill x --kind tool
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "kind invalido exit" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "kind" || return 1
}

scenario_record_skill_sem_onda_falha() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  # Nao chamar start
  capture "$SCRIPT" record-skill --state-dir "$_sd" --skill briefing
  if [ "$_CAPTURED_EXIT" = 0 ]; then
    _fail "exit" "esperado != 0, obtido 0"
    return 1
  fi
  # Mensagem legada permanece byte-a-byte identica (SC-006, openspec-hygiene).
  assert_stderr_contains "nenhuma onda em andamento" || return 1
  # Envelope diagnostico aditivo (openspec-hygiene FR-012/FR-015).
  assert_stderr_contains "DIAG|error|no-open-wave|" || return 1
}

scenario_record_skill_obriga_flags() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  # Sem --skill
  capture "$SCRIPT" record-skill --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" = 0 ]; then
    _fail "exit" "esperado != 0 sem --skill"
    return 1
  fi
  assert_stderr_contains "skill obrigatorio" || return 1
}

scenario_start_inclui_skills_invoked_vazio() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$RW" get --state-dir "$_sd" --field '.waves[-1].skills_invoked'
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "[]" || return 1
}

# ==== record-task (.tasks[] auditavel — rede contra perda de tasks) ====
scenario_record_task_append_basico() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" record-task --state-dir "$_sd" --task-id 1.1 \
    --titulo "Setup" --outcome pass --testes-rodados 3 --testes-passados 3 \
    --lint-ok true --arquivos '["a.go"]' --origem execute-task
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "record-task" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "1" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.tasks[0].task_id'
  assert_stdout_contains "1.1" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.tasks[0].wave_id'
  assert_stdout_contains "onda-001" || return 1
}

scenario_record_task_nao_exige_onda() {
  # .tasks[] e top-level; record-task funciona sem onda em andamento
  # (diferente de record-skill). Garante back-fill em review-task.
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" record-task --state-dir "$_sd" --task-id 9.9 --outcome pass
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "record-task sem onda" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "1" || return 1
}

scenario_record_task_upsert_idempotente() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" record-task --state-dir "$_sd" --task-id 1.1 --titulo "v1" --outcome pass
  capture "$SCRIPT" record-task --state-dir "$_sd" --task-id 1.1 --titulo "v2" --outcome fail
  assert_stdout_contains "1" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.tasks | length'
  assert_stdout_contains "1" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.tasks[0].title'
  assert_stdout_contains "v2" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.tasks[0].outcome'
  assert_stdout_contains "fail" || return 1
}

scenario_record_task_if_absent_nao_clobbera() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" record-task --state-dir "$_sd" --task-id 1.1 --titulo "real" --outcome pass --origem execute-task
  capture "$SCRIPT" record-task --state-dir "$_sd" --task-id 1.1 --titulo "derivada" --outcome pass --origem reconcile --if-absent
  assert_stdout_contains "1" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.tasks[0].title'
  assert_stdout_contains "real" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.tasks[0].source'
  assert_stdout_contains "execute-task" || return 1
}

scenario_record_task_multiplas_acumulam() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" record-task --state-dir "$_sd" --task-id 1.1 --outcome pass
  capture "$SCRIPT" record-task --state-dir "$_sd" --task-id 1.2 --outcome pass
  capture "$SCRIPT" record-task --state-dir "$_sd" --task-id 1.3 --outcome fail
  assert_stdout_contains "3" || return 1
}

scenario_record_task_valida_outcome() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  assert_exit 2 "$SCRIPT" record-task --state-dir "$_sd" --task-id 1.1 --outcome talvez || return 1
}

scenario_record_task_valida_testes_passados_le_rodados() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  assert_exit 2 "$SCRIPT" record-task --state-dir "$_sd" --task-id 1.1 --outcome pass \
    --testes-rodados 1 --testes-passados 5 || return 1
}

scenario_record_task_valida_arquivos_array() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  assert_exit 2 "$SCRIPT" record-task --state-dir "$_sd" --task-id 1.1 --outcome pass \
    --arquivos 'naoarray' || return 1
}

scenario_record_task_obriga_flags() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  assert_exit 2 "$SCRIPT" record-task --state-dir "$_sd" --outcome pass || return 1
  assert_exit 2 "$SCRIPT" record-task --state-dir "$_sd" --task-id 1.1 || return 1
}

# ==== reconcile-tasks (rede deterministica contra perda — fonte: tasks.md) ====
_write_tasks_md() {
  # backlog com mix de estados: 1.1 e 1.3 concluidas; 1.2 parcial; 2.1 bloqueada;
  # 2.1.1-bis (emergente) concluida.
  cat > "$1" <<'TASKS'
# Tarefas Projeto X

## FASE 1 - Fundacao

### 1.1 Setup do Projeto `[A]`

- [x] 1.1.1 Criar repo
- [x] 1.1.2 CI

### 1.2 Dominio `[C]`

- [x] 1.2.1 Entidades
- [ ] 1.2.2 Regras

### 1.3 Persistencia `[A]`

- [x] 1.3.1 Migrations
- [x] 1.3.2 Repo

## FASE 2 - Backend

### 2.1 Handlers `[A]`

- [!] 2.1.1 Bloqueada
- [x] 2.1.2 Outra

### 2.1.1-bis Hotfix emergente `[C]`

- [x] 2.1.1-bis.1 patch

## Resumo Quantitativo

| Fase | Tarefas |
|------|---------|
TASKS
}

scenario_reconcile_tasks_dry_run_lista_concluidas_ausentes() {
  _sd="$TMPDIR_TEST/state"
  _md="$TMPDIR_TEST/tasks.md"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  _write_tasks_md "$_md"
  capture "$SCRIPT" reconcile-tasks --state-dir "$_sd" --tasks-md "$_md" --dry-run
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "reconcile dry-run" "$_CAPTURED_STDERR"; return 1; }
  # concluidas e ausentes: 1.1, 1.3, 2.1.1-bis
  assert_stdout_contains "1.1" || return 1
  assert_stdout_contains "1.3" || return 1
  assert_stdout_contains "2.1.1-bis" || return 1
}

scenario_reconcile_tasks_ignora_pendentes_e_bloqueadas() {
  _sd="$TMPDIR_TEST/state"
  _md="$TMPDIR_TEST/tasks.md"
  _init_state "$_sd"
  _write_tasks_md "$_md"
  capture "$SCRIPT" reconcile-tasks --state-dir "$_sd" --tasks-md "$_md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "reconcile apply" "$_CAPTURED_STDERR"; return 1; }
  # 3 concluidas back-filled (1.1, 1.3, 2.1.1-bis). 1.2 (parcial) e 2.1 ([!]) fora.
  assert_stdout_contains "3" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.tasks | length'
  assert_stdout_contains "3" || return 1
  # equidade exata (NAO contains, que faz match de substring: "2.1.1-bis" ~ "2.1")
  capture "$RW" get --state-dir "$_sd" --field '[.tasks[].task_id] | any(. == "1.2")'
  assert_stdout_contains "false" || return 1
  capture "$RW" get --state-dir "$_sd" --field '[.tasks[].task_id] | any(. == "2.1")'
  assert_stdout_contains "false" || return 1
  # mas a emergente 2.1.1-bis (concluida) DEVE estar presente
  capture "$RW" get --state-dir "$_sd" --field '[.tasks[].task_id] | any(. == "2.1.1-bis")'
  assert_stdout_contains "true" || return 1
}

scenario_reconcile_tasks_extrai_titulo_sem_criticidade() {
  _sd="$TMPDIR_TEST/state"
  _md="$TMPDIR_TEST/tasks.md"
  _init_state "$_sd"
  _write_tasks_md "$_md"
  capture "$SCRIPT" reconcile-tasks --state-dir "$_sd" --tasks-md "$_md"
  capture "$RW" get --state-dir "$_sd" --field '.tasks[] | select(.task_id=="1.1") | .title'
  assert_stdout_contains "Setup do Projeto" || return 1
  # nao deve carregar a tag de criticidade [A]
  if printf '%s' "$_CAPTURED_STDOUT" | grep -q '\['; then
    _fail "titulo" "titulo carregou tag de criticidade: $_CAPTURED_STDOUT"; return 1
  fi
}

scenario_reconcile_tasks_nao_clobbera_entrada_real() {
  _sd="$TMPDIR_TEST/state"
  _md="$TMPDIR_TEST/tasks.md"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  # entrada real previa para 1.1 (execute-task)
  capture "$SCRIPT" record-task --state-dir "$_sd" --task-id 1.1 --titulo "REAL" \
    --outcome pass --origem execute-task
  _write_tasks_md "$_md"
  capture "$SCRIPT" reconcile-tasks --state-dir "$_sd" --tasks-md "$_md"
  # so 1.3 e 2.1.1-bis sao novas (1.1 ja existe)
  assert_stdout_contains "2" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.tasks[] | select(.task_id=="1.1") | .title'
  assert_stdout_contains "REAL" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.tasks[] | select(.task_id=="1.1") | .source'
  assert_stdout_contains "execute-task" || return 1
}

scenario_reconcile_tasks_idempotente() {
  _sd="$TMPDIR_TEST/state"
  _md="$TMPDIR_TEST/tasks.md"
  _init_state "$_sd"
  _write_tasks_md "$_md"
  capture "$SCRIPT" reconcile-tasks --state-dir "$_sd" --tasks-md "$_md"
  assert_stdout_contains "3" || return 1
  capture "$SCRIPT" reconcile-tasks --state-dir "$_sd" --tasks-md "$_md"
  assert_stdout_contains "0" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.tasks | length'
  assert_stdout_contains "3" || return 1
}

scenario_reconcile_tasks_md_ausente_falha() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  assert_exit 1 "$SCRIPT" reconcile-tasks --state-dir "$_sd" \
    --tasks-md "$TMPDIR_TEST/nao-existe.md" || return 1
}

scenario_reconcile_tasks_obriga_flags() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  assert_exit 2 "$SCRIPT" reconcile-tasks --state-dir "$_sd" || return 1
}

# ---- cura de titulos vazios (onda execute-task longa gravada em lote) ----
scenario_reconcile_tasks_cura_titulo_vazio() {
  _sd="$TMPDIR_TEST/state"
  _md="$TMPDIR_TEST/tasks.md"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  # entrada real previa SEM --titulo (title="") com tests 39/39 — replica o
  # sintoma do lote de onda-009.
  capture "$SCRIPT" record-task --state-dir "$_sd" --task-id 1.1 \
    --outcome pass --testes-rodados 39 --testes-passados 39 --origem execute-task
  _write_tasks_md "$_md"
  capture "$SCRIPT" reconcile-tasks --state-dir "$_sd" --tasks-md "$_md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "reconcile cura" "$_CAPTURED_STDERR"; return 1; }
  # titulo curado a partir do heading em tasks.md
  capture "$RW" get --state-dir "$_sd" --field '.tasks[] | select(.task_id=="1.1") | .title'
  assert_stdout_contains "Setup do Projeto" || return 1
  # NAO carrega a tag de criticidade
  if printf '%s' "$_CAPTURED_STDOUT" | grep -q '\['; then
    _fail "cura titulo" "titulo curado carregou tag: $_CAPTURED_STDOUT"; return 1
  fi
  # tests_run/passed PRESERVADOS (39/39) — cura nunca fabrica/zera contagem
  capture "$RW" get --state-dir "$_sd" --field '.tasks[] | select(.task_id=="1.1") | .tests_run'
  assert_stdout_contains "39" || return 1
}

scenario_reconcile_tasks_cura_titulo_nivel_checkbox() {
  # onda execute-task longa grava no nivel do CHECKBOX (N.M.K), nao do heading;
  # o titulo deve ser curado a partir do texto do checkbox em tasks.md.
  _sd="$TMPDIR_TEST/state"
  _md="$TMPDIR_TEST/tasks.md"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" record-task --state-dir "$_sd" --task-id 1.1.1 \
    --outcome pass --testes-rodados 39 --testes-passados 39 --origem execute-task
  _write_tasks_md "$_md"
  capture "$SCRIPT" reconcile-tasks --state-dir "$_sd" --tasks-md "$_md"
  capture "$RW" get --state-dir "$_sd" --field '.tasks[] | select(.task_id=="1.1.1") | .title'
  assert_stdout_contains "Criar repo" || return 1
}

scenario_reconcile_tasks_cura_nao_clobbera_titulo_existente() {
  _sd="$TMPDIR_TEST/state"
  _md="$TMPDIR_TEST/tasks.md"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" record-task --state-dir "$_sd" --task-id 1.1 --titulo "REAL" \
    --outcome pass --origem execute-task
  _write_tasks_md "$_md"
  capture "$SCRIPT" reconcile-tasks --state-dir "$_sd" --tasks-md "$_md"
  capture "$RW" get --state-dir "$_sd" --field '.tasks[] | select(.task_id=="1.1") | .title'
  assert_stdout_contains "REAL" || return 1
}

scenario_reconcile_tasks_dry_run_nao_cura() {
  _sd="$TMPDIR_TEST/state"
  _md="$TMPDIR_TEST/tasks.md"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" record-task --state-dir "$_sd" --task-id 1.1 \
    --outcome pass --origem execute-task
  _write_tasks_md "$_md"
  capture "$SCRIPT" reconcile-tasks --state-dir "$_sd" --tasks-md "$_md" --dry-run
  # dry-run nao escreve: title de 1.1 permanece vazio
  capture "$RW" get --state-dir "$_sd" --field '.tasks[] | select(.task_id=="1.1") | .title'
  if [ -n "$_CAPTURED_STDOUT" ] && [ "$_CAPTURED_STDOUT" != "" ]; then
    _fail "dry-run cura" "dry-run alterou o titulo: [$_CAPTURED_STDOUT]"; return 1
  fi
}

# ==== back-compat pt-BR (schema-en-migration §6: readers leem state legado) ====
# Os writers do state-ondas assumem EN-on-disk (garantido pelo migrate
# defensivo do command-pai), igual ao exemplar drift.sh mark-touched. O que
# DEVE continuar funcionando em state legado/misto sao os READERS, via fallback
# (.en // .pt). Estes cenarios montam state.json com chaves pt-BR direto no
# disco (SEM passar por state-rw.sh init, que ja produz EN) e provam que os
# readers ainda leem os valores pt.

# state legado puro pt-BR com 1 onda + orcamentos pt (sem nenhuma chave EN).
_write_legacy_ptbr_state() {
  jq -n '{
    schema_version: 6,
    ondas: [
      { id: "onda-007", inicio: "2026-05-01T10:00:00Z", fim: null,
        etapas_executadas: ["briefing"], tool_calls: 0, wallclock_seconds: 0,
        motivo_termino: null, proxima_onda_agendada_para: null,
        skills_invoked: [] }
    ],
    orcamentos: { tool_calls_onda_corrente: 4, inicio_onda_corrente: "2026-05-01T10:00:00Z" },
    metricas_acumuladas: { ondas_total: 6, tool_calls_total: 50 }
  }' > "$1/state.json"
}

scenario_ptbr_legacy_current_id_le_via_fallback() {
  # current-id le .ondas[-1].id de um state pt-BR puro.
  _sd="$TMPDIR_TEST/state"
  mkdir -p "$_sd"
  _write_legacy_ptbr_state "$_sd"
  capture "$SCRIPT" current-id --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "ptbr current-id" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "onda-007" || return 1
}

scenario_ptbr_legacy_tool_call_tick_le_e_converge() {
  # tool-call-tick le o contador pt (.orcamentos.tool_calls_onda_corrente=4),
  # incrementa para 5 e ESCREVE em chave EN (.budgets.tool_calls_current_wave).
  _sd="$TMPDIR_TEST/state"
  mkdir -p "$_sd"
  _write_legacy_ptbr_state "$_sd"
  capture "$SCRIPT" tool-call-tick --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "ptbr tick" "$_CAPTURED_STDERR"; return 1; }
  # leu 4 (pt) -> 5
  assert_stdout_contains "5" || return 1
  # convergencia EN-on-disk: o writer grava a chave EN
  capture "$RW" get --state-dir "$_sd" --field '.budgets.tool_calls_current_wave'
  assert_stdout_contains "5" || return 1
}

scenario_ptbr_legacy_start_next_num_le_via_fallback() {
  # start deriva o proximo numero de onda lendo .ondas (pt, max=onda-007 => 008)
  # e grava a nova onda em chave EN (.waves).
  _sd="$TMPDIR_TEST/state"
  mkdir -p "$_sd"
  _write_legacy_ptbr_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "ptbr start" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "onda-008" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.waves[-1].id'
  assert_stdout_contains "onda-008" || return 1
}

scenario_ptbr_legacy_end_le_tool_calls_via_fallback() {
  # end consolida tool_calls da onda lendo o contador pt
  # (.orcamentos.tool_calls_onda_corrente). Onda em EN (.waves) ja existe — o
  # cenario que o migrate defensivo produz: container EN + orcamentos legado pt.
  _sd="$TMPDIR_TEST/state"
  mkdir -p "$_sd"
  jq -n '{
    schema_version: 6,
    waves: [
      { id: "onda-003", started_at: "2026-05-01T10:00:00Z", finished_at: null,
        executed_stages: [], tool_calls: 0, wallclock_seconds: 0,
        termination_reason: null, next_wave_scheduled_for: null, skills_invoked: [] }
    ],
    orcamentos: { tool_calls_onda_corrente: 9, inicio_onda_corrente: "2026-05-01T10:00:00Z" }
  }' > "$_sd/state.json"
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino concluido
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "ptbr end" "$_CAPTURED_STDERR"; return 1; }
  # leu 9 do contador pt e gravou em waves[-1].tool_calls (chave EN)
  capture "$RW" get --state-dir "$_sd" --field '.waves[-1].tool_calls'
  assert_stdout_contains "9" || return 1
}

scenario_ptbr_legacy_record_skill_idempotencia_le_decisao_id() {
  # A idempotencia do record-skill compara decisao_id da entrada existente.
  # Entrada legada usa a chave pt `decisao_id`; o reader le via fallback
  # (.decision_id // .decisao_id), entao re-registrar a mesma skill+decisao
  # NAO duplica.
  _sd="$TMPDIR_TEST/state"
  mkdir -p "$_sd"
  jq -n '{
    schema_version: 6,
    waves: [
      { id: "onda-001", started_at: "2026-05-01T10:00:00Z", finished_at: null,
        executed_stages: [], tool_calls: 0, wallclock_seconds: 0,
        termination_reason: null, next_wave_scheduled_for: null,
        skills_invoked: [ { skill: "briefing", timestamp: "t", decisao_id: "dec-001" } ] }
    ]
  }' > "$_sd/state.json"
  capture "$SCRIPT" record-skill --state-dir "$_sd" --skill briefing --decisao-id dec-001
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "ptbr record-skill" "$_CAPTURED_STDERR"; return 1; }
  # idempotente: continua 1 (a entrada pt foi reconhecida via fallback)
  assert_stdout_contains "1" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.waves[-1].skills_invoked | length'
  assert_stdout_contains "1" || return 1
}

# ---------------------------------------------------------------------------
# wave-status + reconcile-wave (rede de seguranca anti "onda nao fechada")
# ---------------------------------------------------------------------------

scenario_wave_status_none_quando_sem_onda() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" wave-status --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "wave-status" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "none" || return 1
}

scenario_wave_status_open_apos_start() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" wave-status --state-dir "$_sd"
  assert_stdout_contains "open" || return 1
}

scenario_wave_status_closed_apos_end() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando
  capture "$SCRIPT" wave-status --state-dir "$_sd"
  assert_stdout_contains "closed" || return 1
}

scenario_reconcile_wave_noop_quando_fechada() {
  # Onda ja fechada -> NO-OP (exit 0, stdout "noop (closed)"). E a guarda que
  # torna seguro o pai chamar reconcile-wave a CADA onda.
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando
  capture "$SCRIPT" reconcile-wave --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "reconcile noop" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "noop" || return 1
}

scenario_reconcile_wave_noop_quando_sem_onda() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" reconcile-wave --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "reconcile noop none" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "noop (none)" || return 1
}

scenario_reconcile_wave_fecha_e_avanca_ponteiro() {
  # Onda aberta na fase specify -> fecha (etapa_concluida_avancando) e avanca
  # current_stage para clarify. E a recuperacao deterministica do bug
  # "orquestrador parou cedo sem fechar a onda".
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$RW" set --state-dir "$_sd" --field '.current_stage' --value '"specify"'
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" reconcile-wave --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "reconcile open" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "reconciled" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.current_stage'
  assert_stdout_contains "clarify" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.waves[-1].termination_reason'
  assert_stdout_contains "etapa_concluida_avancando" || return 1
  # skill da fase registrada (audit)
  capture "$RW" get --state-dir "$_sd" --field '.waves[-1].skills_invoked | length'
  assert_stdout_contains "1" || return 1
}

scenario_reconcile_wave_idempotente_nao_double_conta() {
  # Re-chamada apos reconciliar NAO incrementa accumulated_metrics.waves_total
  # nem re-avanca o ponteiro (guarda de idempotencia). Protege contra o pai
  # chamar reconcile-wave em onda que o orquestrador JA fechou corretamente.
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$RW" set --state-dir "$_sd" --field '.current_stage' --value '"specify"'
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" reconcile-wave --state-dir "$_sd"
  capture "$RW" get --state-dir "$_sd" --field '.accumulated_metrics.waves_total'
  assert_stdout_contains "1" || return 1
  # segunda chamada: noop
  capture "$SCRIPT" reconcile-wave --state-dir "$_sd"
  assert_stdout_contains "noop" || return 1
  # waves_total continua 1 (sem double-count)
  capture "$RW" get --state-dir "$_sd" --field '.accumulated_metrics.waves_total'
  assert_stdout_contains "1" || return 1
  # current_stage continua clarify (sem over-advance)
  capture "$RW" get --state-dir "$_sd" --field '.current_stage'
  assert_stdout_contains "clarify" || return 1
}

# Bugfix 8.1.1 (dec-098 de mcp-elicitation-optins; dec-053/dec-068 antes):
# em execute-task, reconcile-wave so pode avancar a fase se o tasks.md nao
# tiver NENHUM `- [ ]`. Sem isso o pai chegava com 26/92 pendentes e
# promovia para review-task (4 ocorrencias na mesma linha de trabalho).
scenario_reconcile_wave_execute_task_backlog_aberto_nao_avanca() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$RW" set --state-dir "$_sd" --field '.current_stage' --value '"execute-task"'
  _md="$TMPDIR_TEST/tasks-aberto.md"
  printf '## FASE 1\n### 1.1 Tarefa `[A]`\n- [x] 1.1.1 feita\n- [ ] 1.1.2 pendente\n- [ ] 1.1.3 pendente\n' > "$_md"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" reconcile-wave --state-dir "$_sd" --terminal-phase review-task --tasks-md "$_md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "reconcile hold" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "HOLD" || return 1
  # fase NAO avancou
  capture "$RW" get --state-dir "$_sd" --field '.current_stage'
  assert_stdout_contains "execute-task" || { _fail "fase avancou" "esperado execute-task, obtido: $_CAPTURED_STDOUT"; return 1; }
  # e NAO promoveu a terminal (o pior desfecho: _rcw_next vazio caindo no ramo terminal)
  capture "$RW" get --state-dir "$_sd" --field '.execution.status'
  assert_stdout_contains "em_andamento" || { _fail "promoveu terminal" "status: $_CAPTURED_STDOUT"; return 1; }
  # onda foi fechada mesmo assim (nao fica aberta)
  capture "$RW" get --state-dir "$_sd" --field '.waves[-1].finished_at'
  case "$_CAPTURED_STDOUT" in null|"") _fail "onda aberta" "hold devia fechar a onda"; return 1;; esac
  # next_instruction registra o motivo
  capture "$RW" get --state-dir "$_sd" --field '.next_instruction'
  assert_stdout_contains "pendente" || return 1
}

# Negativo do hold: backlog SEM `- [ ]` (tudo [x] e [!]) => avanca normalmente.
scenario_reconcile_wave_execute_task_backlog_completo_avanca() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$RW" set --state-dir "$_sd" --field '.current_stage' --value '"execute-task"'
  _md="$TMPDIR_TEST/tasks-completo.md"
  printf '## FASE 1\n### 1.1 Tarefa `[A]`\n- [x] 1.1.1 feita\n- [!] 1.1.2 bloqueada com motivo\n' > "$_md"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" reconcile-wave --state-dir "$_sd" --terminal-phase review-task --tasks-md "$_md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "reconcile avanca" "$_CAPTURED_STDERR"; return 1; }
  case "$_CAPTURED_STDOUT" in *HOLD*) _fail "hold indevido" "backlog completo nao pode dar HOLD: $_CAPTURED_STDOUT"; return 1;; esac
  capture "$RW" get --state-dir "$_sd" --field '.current_stage'
  assert_stdout_contains "review-task" || { _fail "nao avancou" "esperado review-task, obtido: $_CAPTURED_STDOUT"; return 1; }
}

# --dry-run reporta o HOLD sem escrever nada.
scenario_reconcile_wave_dry_run_reporta_hold() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$RW" set --state-dir "$_sd" --field '.current_stage' --value '"execute-task"'
  _md="$TMPDIR_TEST/tasks-dry.md"
  printf -- '- [ ] 1.1.1 pendente\n' > "$_md"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" reconcile-wave --state-dir "$_sd" --terminal-phase review-task --tasks-md "$_md" --dry-run
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "dry-run" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "HOLD" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.waves[-1].finished_at'
  case "$_CAPTURED_STDOUT" in null|"") : ;; *) _fail "dry-run escreveu" "onda foi fechada em dry-run"; return 1;; esac
}

scenario_reconcile_wave_terminal_promove_status_feature00c() {
  # feature-00c: review-task e terminal. --terminal-phase review-task evita
  # que pipeline.sh avance erroneamente para review-features. Deve promover
  # .execution.status para concluida.
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$RW" set --state-dir "$_sd" --field '.current_stage' --value '"review-task"'
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" reconcile-wave --state-dir "$_sd" --terminal-phase review-task
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "reconcile terminal" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "terminal" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.execution.status'
  assert_stdout_contains "concluida" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.execution.termination_reason'
  assert_stdout_contains "concluido" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.waves[-1].termination_reason'
  assert_stdout_contains "concluido" || return 1
}

scenario_reconcile_wave_sha256_consistente() {
  # Apos reconciliar, o sha256 do state.json deve bater (state-rw.sh set
  # recomputa). Senao o resume seguinte falha o gate de integridade.
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$RW" set --state-dir "$_sd" --field '.current_stage' --value '"plan"'
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" reconcile-wave --state-dir "$_sd"
  assert_exit 0 "$RW" sha256-verify --state-dir "$_sd" || return 1
}

scenario_reconcile_wave_dry_run_nao_escreve() {
  # --dry-run descreve a acao sem fechar a onda nem mexer no ponteiro.
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$RW" set --state-dir "$_sd" --field '.current_stage' --value '"specify"'
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" reconcile-wave --state-dir "$_sd" --dry-run
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "dry-run" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "would reconcile" || return 1
  # onda continua aberta
  capture "$SCRIPT" wave-status --state-dir "$_sd"
  assert_stdout_contains "open" || return 1
  # ponteiro intacto
  capture "$RW" get --state-dir "$_sd" --field '.current_stage'
  assert_stdout_contains "specify" || return 1
}

scenario_reconcile_wave_phase_override() {
  # --phase fixa a fase explicitamente (pai pode pinar), ignorando current_stage.
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$RW" set --state-dir "$_sd" --field '.current_stage' --value '"specify"'
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" reconcile-wave --state-dir "$_sd" --phase plan
  assert_stdout_contains "next=checklist" || return 1
  # O avanco respeita a fase PINADA (end --advance-from), nao .current_stage.
  capture "$RW" get --state-dir "$_sd" --field '.current_stage'
  assert_stdout_contains "checklist" || return 1
}

scenario_reconcile_wave_next_instruction_coerente() {
  # wave-close-advance SC-001: apos reconciliar, next_instruction referencia
  # a MESMA etapa de current_stage (fechamento + ponteiro num write atomico).
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$RW" set --state-dir "$_sd" --field '.current_stage' --value '"specify"'
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" reconcile-wave --state-dir "$_sd"
  capture "$RW" get --state-dir "$_sd" --field '.current_stage'
  assert_stdout_contains "clarify" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.next_instruction'
  assert_stdout_contains "Iniciar etapa clarify" || return 1
}

# ==== end --advance (wave-close-advance FR-001..FR-004) ====
# Avanco do ponteiro INTEIRO (current_stage + next_instruction) no MESMO
# write atomico do fechamento — elimina a classe do meio-avanco (fase
# avancada + next_instruction stale, invisivel ao reconcile-wave).

scenario_end_advance_avanca_ponteiro_no_mesmo_write() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$RW" set --state-dir "$_sd" --field '.current_stage' --value '"specify"'
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" \
    --motivo-termino etapa_concluida_avancando --advance
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "end --advance" "$_CAPTURED_STDERR"; return 1; }
  capture "$RW" get --state-dir "$_sd" --field '.current_stage'
  assert_stdout_contains "clarify" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.next_instruction'
  assert_stdout_contains "Iniciar etapa clarify" || return 1
  capture "$SCRIPT" wave-status --state-dir "$_sd"
  assert_stdout_contains "closed" || return 1
}

scenario_end_advance_next_instruction_sobrescreve_so_texto() {
  # FR-004: --next-instruction refina o TEXTO; o avanco de fase ocorre igual.
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$RW" set --state-dir "$_sd" --field '.current_stage' --value '"clarify"'
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" \
    --motivo-termino etapa_concluida_avancando --advance \
    --next-instruction "Iniciar etapa plan — priorizar o modelo de dados."
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "end --advance custom" "$_CAPTURED_STDERR"; return 1; }
  capture "$RW" get --state-dir "$_sd" --field '.current_stage'
  assert_stdout_contains "plan" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.next_instruction'
  assert_stdout_contains "priorizar o modelo de dados" || return 1
}

scenario_end_advance_motivo_incompativel_falha_sem_write() {
  # FR-001/SC-002: --advance so com etapa_concluida_avancando; falha ANTES
  # de qualquer write (onda segue aberta, ponteiro intacto).
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$RW" set --state-dir "$_sd" --field '.current_stage' --value '"specify"'
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" \
    --motivo-termino threshold_proxy_atingido --advance
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit esperado 2" "obtido $_CAPTURED_EXIT"; return 1; }
  capture "$SCRIPT" wave-status --state-dir "$_sd"
  assert_stdout_contains "open" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.current_stage'
  assert_stdout_contains "specify" || return 1
}

scenario_end_advance_fase_terminal_falha_sem_write() {
  # FR-003/SC-002: fase corrente == --terminal-phase => fail-closed; o
  # fechamento terminal usa --motivo-termino concluido + promocao, nunca
  # --advance.
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$RW" set --state-dir "$_sd" --field '.current_stage' --value '"review-task"'
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" \
    --motivo-termino etapa_concluida_avancando --advance --terminal-phase review-task
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit esperado 2" "obtido $_CAPTURED_EXIT"; return 1; }
  capture "$SCRIPT" wave-status --state-dir "$_sd"
  assert_stdout_contains "open" || return 1
}

scenario_end_advance_fase_desconhecida_falha_sem_write() {
  # pipeline.sh nao resolve proxima fase de token fora da lista => exit 2.
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$RW" set --state-dir "$_sd" --field '.current_stage' --value '"fase-inexistente"'
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" \
    --motivo-termino etapa_concluida_avancando --advance
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit esperado 2" "obtido $_CAPTURED_EXIT"; return 1; }
  capture "$SCRIPT" wave-status --state-dir "$_sd"
  assert_stdout_contains "open" || return 1
}

scenario_end_advance_flags_orfas_exit2() {
  # --terminal-phase/--advance-from sem --advance sao erro de uso.
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" \
    --motivo-termino etapa_concluida_avancando --terminal-phase review-task
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "terminal-phase orfa: exit esperado 2" "obtido $_CAPTURED_EXIT"; return 1; }
  capture "$SCRIPT" end --state-dir "$_sd" \
    --motivo-termino etapa_concluida_avancando --advance-from specify
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "advance-from orfa: exit esperado 2" "obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_end_advance_mode_roadmap_passthrough() {
  # 2.5.1: --mode roadmap e repassado a pipeline.sh next-stage; a lista
  # escopada (briefing constitution roadmap) resolve constitution->roadmap,
  # nao specify (contracts/cli-roadmap-mode.md §4).
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$RW" set --state-dir "$_sd" --field '.current_stage' --value '"constitution"'
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" \
    --motivo-termino etapa_concluida_avancando --advance --mode roadmap
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "end --advance --mode roadmap" "$_CAPTURED_STDERR"; return 1; }
  capture "$RW" get --state-dir "$_sd" --field '.current_stage'
  assert_stdout_contains "roadmap" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.next_instruction'
  assert_stdout_contains "Iniciar etapa roadmap" || return 1
}

scenario_end_advance_mode_omitido_usa_lista_completa() {
  # Sem --mode, comportamento atual intacto: constitution->specify (lista
  # completa), nao roadmap (contracts/cli-roadmap-mode.md §4 "Sem --mode, o
  # comportamento e o atual").
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$RW" set --state-dir "$_sd" --field '.current_stage' --value '"constitution"'
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" \
    --motivo-termino etapa_concluida_avancando --advance
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "end --advance sem mode" "$_CAPTURED_STDERR"; return 1; }
  capture "$RW" get --state-dir "$_sd" --field '.current_stage'
  assert_stdout_contains "specify" || return 1
}

scenario_end_mode_sem_advance_exit2() {
  # 2.5.2: --mode sem --advance e erro de uso, mesma politica de
  # --terminal-phase/--advance-from.
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" \
    --motivo-termino etapa_concluida_avancando --mode roadmap
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "mode orfa: exit esperado 2" "obtido $_CAPTURED_EXIT"; return 1; }
  capture "$SCRIPT" wave-status --state-dir "$_sd"
  assert_stdout_contains "open" || return 1
}

scenario_end_advance_terminal_phase_roadmap_intacto() {
  # 2.5.3: --terminal-phase roadmap continua fail-closed quando a fase
  # corrente ja e roadmap, mesmo com --mode roadmap presente (contracts/
  # cli-roadmap-mode.md §4.1 — sem regressao no comportamento existente).
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$RW" set --state-dir "$_sd" --field '.current_stage' --value '"roadmap"'
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" \
    --motivo-termino etapa_concluida_avancando --advance --mode roadmap --terminal-phase roadmap
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit esperado 2" "obtido $_CAPTURED_EXIT"; return 1; }
  capture "$SCRIPT" wave-status --state-dir "$_sd"
  assert_stdout_contains "open" || return 1
}

scenario_sqlite_end_advance_mode_roadmap_passthrough() {
  # Paridade SQLite do passthrough --mode (2.5.1).
  _sd="$TMPDIR_TEST/sqlite-end-advance-mode"
  _seed_sqlite_backend "$_sd" || return 1   # seed: current_stage=execute-task
  capture "$RW" set --state-dir "$_sd" --field '.current_stage' --value '"constitution"'
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" \
    --motivo-termino etapa_concluida_avancando --advance --mode roadmap
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sqlite end --advance --mode roadmap" "$_CAPTURED_STDERR"; return 1; }
  capture "$RW" get --state-dir "$_sd" --field '.current_stage'
  assert_stdout_contains "roadmap" || return 1
}

scenario_git_commit_worktree() {
  # Regressao: em git worktree o `.git` e ARQUIVO (`gitdir: ...`), nao diretorio.
  # O check antigo `[ -d "$_pap/.git" ]` dava falso-negativo e quebrava commit
  # dentro de `cstk session` (que usa worktrees).
  _sd="$TMPDIR_TEST/state"
  _main="$TMPDIR_TEST/mainrepo"
  _wt="$TMPDIR_TEST/wt"
  mkdir -p "$_main"
  ( cd "$_main" && git init -q -b main \
    && git config user.email t@t && git config user.name t \
    && touch base.txt && git add . && git commit -q -m initial \
    && git worktree add -b feat "$_wt" ) >/dev/null 2>&1
  [ -f "$_wt/.git" ] || { _fail "worktree setup" ".git deveria ser ARQUIVO em $_wt"; return 1; }
  # state.json aponta para o worktree real + start ANTES do arquivo novo
  # (baseline capturado no inicio da onda — mesma razao de
  # scenario_git_commit_cria_commit).
  _init_state "$_sd" "$_wt"
  capture "$SCRIPT" start --state-dir "$_sd"
  ( cd "$_wt" && touch novo.txt )
  capture "$SCRIPT" git-commit --state-dir "$_sd" --projeto-alvo-path "$_wt" \
    --motivo "commit em worktree"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "worktree commit" "exit=$_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"; return 1; }
  _msg=$(git -C "$_wt" log -1 --pretty=%s)
  case "$_msg" in
    *"chore(agente-00c):"*"commit em worktree"*) ;;
    *) _fail "worktree commit msg" "obtido: $_msg"; return 1 ;;
  esac
}

# ==== quickstart.md Cenario 7: wave-commit endurecido (living-specs FASE 5.5) ====
# alien.pptx untracked PRE-EXISTENTE (analogo ao incidente real) +
# mudanca tracked em docs/specs/feat-x/spec.md => commit contem SO a
# mudanca tracked, alien.pptx permanece untracked. Confirma que o site 3
# da research Decision 1 (git add -- .) esta convergido ao mesmo helper de
# staging dos demais sites (5.1-5.4).

scenario_5_5_wave_commit_endurecido_exclui_alien() {
  _sd="$TMPDIR_TEST/state"
  _pap="$TMPDIR_TEST/proj-wc"
  mkdir -p "$_pap/docs/specs/feat-x"
  ( cd "$_pap" && git init -q -b main \
    && git config user.email t@t && git config user.name t \
    && printf 's\n' > docs/specs/feat-x/spec.md \
    && git add -A && git commit -q -m initial )

  # alien.pptx untracked PRE-EXISTENTE, antes de start capturar o baseline.
  printf 'alien\n' > "$_pap/alien.pptx"

  _init_state "$_sd" "$_pap"
  capture "$SCRIPT" start --state-dir "$_sd"
  [ -f "$_sd/commit-baseline.txt" ] || { _fail "baseline" "commit-baseline.txt deveria existir apos start"; return 1; }
  grep -qx "alien.pptx" "$_sd/commit-baseline.txt" \
    || { _fail "baseline conteudo" "alien.pptx deveria estar no baseline"; return 1; }

  # Trabalho da onda: mudanca TRACKED.
  printf 's2\n' >> "$_pap/docs/specs/feat-x/spec.md"

  capture "$SCRIPT" git-commit --state-dir "$_sd" --projeto-alvo-path "$_pap" \
    --motivo "wave-commit endurecido"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "git-commit exit" "obtido $_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"; return 1; }

  _shown=$(git -C "$_pap" show --name-only --format= HEAD)
  case "$_shown" in
    *alien.pptx*) _fail "alien.pptx nao deveria estar no commit" "obtido: $_shown"; return 1 ;;
  esac
  case "$_shown" in
    *"docs/specs/feat-x/spec.md"*) : ;;
    *) _fail "spec.md deveria estar no commit" "obtido: $_shown"; return 1 ;;
  esac

  _untracked=$(git -C "$_pap" status --porcelain | grep '^??' || :)
  case "$_untracked" in
    *alien.pptx*) : ;;
    *) _fail "alien.pptx deveria permanecer untracked" "obtido: $_untracked"; return 1 ;;
  esac
}

# ==== issue #49: baseline stale invalidado no start ====
# A captura do baseline e best-effort e silenciosa. Se ela falha numa onda
# nova, o commit-baseline.txt da onda ANTERIOR nao pode sobreviver:
# stage-derived o trataria como valido e tudo que ficou untracked desde
# aquela onda antiga "vazaria" como novo no wave-commit (o incidente dos
# ~45 arquivos .claude/). start remove o baseline ANTES de qualquer
# early-return: falha de captura => arquivo AUSENTE => fail-closed.
scenario_issue49_start_invalida_baseline_stale_quando_captura_falha() {
  _sd="$TMPDIR_TEST/state-stale-baseline"
  # projeto-alvo inexistente: a captura early-returns sem gravar baseline
  _init_state "$_sd" "$TMPDIR_TEST/projeto-que-nao-existe"
  printf 'stale-da-onda-anterior.txt\n' > "$_sd/commit-baseline.txt"
  capture "$SCRIPT" start --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "start exit" "$_CAPTURED_STDERR"; return 1; }
  [ ! -f "$_sd/commit-baseline.txt" ] \
    || { _fail "baseline stale sobreviveu ao start" "$(cat "$_sd/commit-baseline.txt")"; return 1; }
}

# ==== Sidecar de ticks do hook PostToolUse (tool-call-ticks.log) ====

scenario_end_soma_sidecar_ao_campo_do_state() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  # 2 ticks manuais (campo do state) + 5 ticks do hook (sidecar).
  capture "$SCRIPT" tool-call-tick --state-dir "$_sd"
  capture "$SCRIPT" tool-call-tick --state-dir "$_sd"
  printf 't1\nt2\nt3\nt4\nt5\n' > "$_sd/tool-call-ticks.log"
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "end" "$_CAPTURED_STDERR"; return 1; }
  _tc=$(jq -r '.waves[-1].tool_calls' "$_sd/state.json")
  [ "$_tc" = 7 ] || { _fail "tool_calls" "esperado 7 (2 campo + 5 sidecar), obtido $_tc"; return 1; }
  _acc=$(jq -r '.accumulated_metrics.tool_calls_total' "$_sd/state.json")
  [ "$_acc" = 7 ] || { _fail "accumulated" "esperado 7, obtido $_acc"; return 1; }
  # Sidecar consumido: end reseta para nao vazar para a proxima onda.
  [ -f "$_sd/tool-call-ticks.log" ] \
    && { _fail "sidecar" "end deveria remover o sidecar consumido"; return 1; }
  return 0
}

scenario_start_reseta_sidecar_residual() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  # Residuo de ticks do overhead de fechamento (entre end e start).
  printf 'residuo1\nresiduo2\n' > "$_sd/tool-call-ticks.log"
  capture "$SCRIPT" start --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "start" "$_CAPTURED_STDERR"; return 1; }
  [ -f "$_sd/tool-call-ticks.log" ] \
    && { _fail "sidecar" "start deveria zerar o sidecar (janela = start->end)"; return 1; }
  return 0
}

scenario_end_sem_sidecar_usa_so_o_campo() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" tool-call-tick --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "end" "$_CAPTURED_STDERR"; return 1; }
  _tc=$(jq -r '.waves[-1].tool_calls' "$_sd/state.json")
  [ "$_tc" = 1 ] || { _fail "tool_calls" "sem sidecar, esperado 1 (so campo), obtido $_tc"; return 1; }
}

# ==== Sidecar de uso de agente (wave-agent-usage.jsonl, wave-token-metrics FASE 3) ====

_wau_write_sidecar() {
  # $1 = state-dir; escreve 3 SpawnUsage: completo + parcial + indisponivel.
  cat > "$1/wave-agent-usage.jsonl" <<'JSONL'
{"agent_id":"a1","agent_type":"x","status":"completo","model":"sonnet","models_used":null,"total_tokens":100,"input_tokens":60,"output_tokens":40,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"tool_use_count":5,"duration_ms":1000,"source":"live","observed_at":"t"}
{"agent_id":"a2","agent_type":"y","status":"parcial","model":"sonnet","models_used":null,"total_tokens":50,"input_tokens":null,"output_tokens":null,"cache_read_input_tokens":null,"cache_creation_input_tokens":null,"tool_use_count":null,"duration_ms":null,"source":"live","observed_at":"t"}
{"agent_id":"a3","agent_type":"z","status":"indisponivel","model":"nao-aplicavel","models_used":null,"total_tokens":null,"input_tokens":null,"output_tokens":null,"cache_read_input_tokens":null,"cache_creation_input_tokens":null,"tool_use_count":null,"duration_ms":null,"source":"live","observed_at":"t"}
JSONL
}

scenario_end_agrega_sidecar_agent_usage_misto() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  _wau_write_sidecar "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "end" "$_CAPTURED_STDERR"; return 1; }

  _total=$(jq -r '.waves[-1].agent_usage.spawns_total' "$_sd/state.json")
  [ "$_total" = 3 ] || { _fail "spawns_total" "esperado 3, obtido $_total"; return 1; }
  _with_usage=$(jq -r '.waves[-1].agent_usage.spawns_with_usage' "$_sd/state.json")
  [ "$_with_usage" = 2 ] || { _fail "spawns_with_usage" "esperado 2 (completo+parcial), obtido $_with_usage"; return 1; }
  _unavail=$(jq -r '.waves[-1].agent_usage.spawns_unavailable' "$_sd/state.json")
  [ "$_unavail" = 1 ] || { _fail "spawns_unavailable" "esperado 1, obtido $_unavail"; return 1; }
  _tot_tok=$(jq -r '.waves[-1].agent_usage.total_tokens' "$_sd/state.json")
  [ "$_tot_tok" = 150 ] || { _fail "total_tokens" "esperado 150 (100+50), obtido $_tot_tok"; return 1; }
  _spawns_n=$(jq -r '.waves[-1].agent_spawns | length' "$_sd/state.json")
  [ "$_spawns_n" = 3 ] || { _fail "agent_spawns" "esperado 3 entradas brutas, obtido $_spawns_n"; return 1; }
  return 0
}

scenario_end_agent_usage_sem_sidecar_produz_null() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "end" "$_CAPTURED_STDERR"; return 1; }
  _au=$(jq -r '.waves[-1].agent_usage' "$_sd/state.json")
  [ "$_au" = "null" ] || { _fail "agent_usage" "esperado null (sem sidecar), obtido $_au"; return 1; }
  _sp=$(jq -c '.waves[-1].agent_spawns' "$_sd/state.json")
  [ "$_sp" = "[]" ] || { _fail "agent_spawns" "esperado [], obtido $_sp"; return 1; }
  return 0
}

scenario_end_agent_usage_ignora_linhas_corrompidas() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  # 2 linhas validas + 1 corrompida no meio: agregacao MUST descartar a
  # corrompida sem abortar o `end` inteiro (Principio VI — nunca fabrica,
  # mas tambem nunca falha por causa de dado ilegivel de terceiros).
  cat > "$_sd/wave-agent-usage.jsonl" <<'JSONL'
{"agent_id":"a1","agent_type":"x","status":"completo","model":"sonnet","models_used":null,"total_tokens":100,"input_tokens":60,"output_tokens":40,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"tool_use_count":5,"duration_ms":1000,"source":"live","observed_at":"t"}
{ isto nao e json valido
{"agent_id":"a2","agent_type":"y","status":"completo","model":"sonnet","models_used":null,"total_tokens":25,"input_tokens":10,"output_tokens":15,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"tool_use_count":2,"duration_ms":300,"source":"live","observed_at":"t"}
JSONL
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "end" "linha corrompida nao deveria abortar end: $_CAPTURED_STDERR"; return 1; }
  _total=$(jq -r '.waves[-1].agent_usage.spawns_total' "$_sd/state.json")
  [ "$_total" = 2 ] || { _fail "spawns_total" "esperado 2 (linha corrompida descartada), obtido $_total"; return 1; }
  _tot_tok=$(jq -r '.waves[-1].agent_usage.total_tokens' "$_sd/state.json")
  [ "$_tot_tok" = 125 ] || { _fail "total_tokens" "esperado 125 (100+25), obtido $_tot_tok"; return 1; }
  return 0
}

scenario_end_agent_usage_null_nunca_fabrica_zero() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  # Todos indisponivel: spawns_with_usage=0, mas spawns_total>0 -> agent_usage
  # NAO deve ser null (houve spawn); campos numericos MUST ser null, nunca 0.
  cat > "$_sd/wave-agent-usage.jsonl" <<'JSONL'
{"agent_id":"a1","agent_type":"x","status":"indisponivel","model":"nao-aplicavel","models_used":null,"total_tokens":null,"input_tokens":null,"output_tokens":null,"cache_read_input_tokens":null,"cache_creation_input_tokens":null,"tool_use_count":null,"duration_ms":null,"source":"live","observed_at":"t"}
JSONL
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "end" "$_CAPTURED_STDERR"; return 1; }
  _au=$(jq -r '.waves[-1].agent_usage' "$_sd/state.json")
  [ "$_au" != "null" ] || { _fail "agent_usage" "spawns_total=1 (mesmo indisponivel) nao deveria produzir agent_usage null"; return 1; }
  _tot_tok=$(jq -r '.waves[-1].agent_usage.total_tokens' "$_sd/state.json")
  [ "$_tot_tok" = "null" ] || { _fail "total_tokens" "esperado null (nao observado), NUNCA 0 fabricado, obtido $_tot_tok"; return 1; }
  _with_usage=$(jq -r '.waves[-1].agent_usage.spawns_with_usage' "$_sd/state.json")
  [ "$_with_usage" = 0 ] || { _fail "spawns_with_usage" "esperado 0, obtido $_with_usage"; return 1; }
  return 0
}

scenario_start_reseta_sidecar_agent_usage_residual() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  # Residuo de spawns + sentinela de cap do ciclo anterior.
  printf '{"agent_id":"residuo"}\n' > "$_sd/wave-agent-usage.jsonl"
  : > "$_sd/.wave-agent-usage-cap-warned"
  capture "$SCRIPT" start --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "start" "$_CAPTURED_STDERR"; return 1; }
  [ -f "$_sd/wave-agent-usage.jsonl" ] \
    && { _fail "sidecar" "start deveria zerar wave-agent-usage.jsonl (janela = start->end)"; return 1; }
  [ -f "$_sd/.wave-agent-usage-cap-warned" ] \
    && { _fail "sentinela" "start deveria remover o sentinela de cap-warned residual"; return 1; }
  return 0
}

scenario_end_reseta_sidecar_agent_usage_consumido() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  _wau_write_sidecar "$_sd"
  : > "$_sd/.wave-agent-usage-cap-warned"
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "end" "$_CAPTURED_STDERR"; return 1; }
  [ -f "$_sd/wave-agent-usage.jsonl" ] \
    && { _fail "sidecar" "end deveria remover o sidecar consumido"; return 1; }
  [ -f "$_sd/.wave-agent-usage-cap-warned" ] \
    && { _fail "sentinela" "end deveria remover o sentinela de cap-warned consumido"; return 1; }
  return 0
}

scenario_end_acumula_accumulated_metrics_agent_entre_ondas() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  # Onda 1: com sidecar (contribui dado real).
  capture "$SCRIPT" start --state-dir "$_sd"
  _wau_write_sidecar "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "end onda1" "$_CAPTURED_STDERR"; return 1; }

  # Onda 2: SEM sidecar (nenhum spawn) — acumulado nao deve ser corrompido
  # com 0 fabricado; total de tokens permanece o da onda 1.
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "end onda2" "$_CAPTURED_STDERR"; return 1; }

  _spawns_total=$(jq -r '.accumulated_metrics.agent_spawns_total' "$_sd/state.json")
  [ "$_spawns_total" = 3 ] || { _fail "agent_spawns_total" "esperado 3 (so onda1 contribuiu), obtido $_spawns_total"; return 1; }
  _tokens_total=$(jq -r '.accumulated_metrics.agent_tokens_total' "$_sd/state.json")
  [ "$_tokens_total" = 150 ] || { _fail "agent_tokens_total" "esperado 150 (onda2 nao fabrica 0), obtido $_tokens_total"; return 1; }

  # Onda 3: novo sidecar -> acumulado soma sobre o total anterior.
  capture "$SCRIPT" start --state-dir "$_sd"
  _wau_write_sidecar "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "end onda3" "$_CAPTURED_STDERR"; return 1; }
  _tokens_total3=$(jq -r '.accumulated_metrics.agent_tokens_total' "$_sd/state.json")
  [ "$_tokens_total3" = 300 ] || { _fail "agent_tokens_total onda3" "esperado 300 (150+150), obtido $_tokens_total3"; return 1; }
  _spawns_with_usage_total=$(jq -r '.accumulated_metrics.agent_spawns_with_usage_total' "$_sd/state.json")
  [ "$_spawns_with_usage_total" = 4 ] || { _fail "agent_spawns_with_usage_total" "esperado 4 (2+0+2), obtido $_spawns_with_usage_total"; return 1; }
  return 0
}

# ==== Telemetria OTel: consumo real da onda (otel_usage) ====
#
# O sidecar de spawn (posttooluse-agent-usage.sh) nunca captura o consumo do
# PROPRIO orquestrador, porque o spawn dele envolve a onda e seu tool_result
# chega depois do `end`. Os contadores OTel sao incrementados a cada API
# request, entao o delta start->end fecha essa lacuna.

# _otel_fixture FILE COST_MAIN COST_SUB — formato REAL do exporter
# Prometheus (labels na ordem real; `terminal_type` antes de `type`).
_otel_fixture() {
  {
    printf 'claude_code_cost_usage_total{session_id="sess-w",terminal_type="ghostty",model="claude-opus-5[1m]",query_source="main"} %s\n' "$2"
    printf 'claude_code_cost_usage_total{session_id="sess-w",terminal_type="ghostty",model="claude-opus-5[1m]",query_source="subagent"} %s\n' "$3"
    printf 'claude_code_token_usage_total{session_id="sess-w",terminal_type="ghostty",model="claude-opus-5[1m]",query_source="subagent",type="output"} 100\n'
  } > "$1"
}

scenario_end_otel_usage_null_sem_telemetria() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  # Isolamento de ambiente OBRIGATORIO (sug-006): sem forcar o endpoint, o
  # cenario cai no default (localhost:9464) e, numa maquina com
  # CLAUDE_CODE_ENABLE_TELEMETRY=1 + OTEL_METRICS_EXPORTER=prometheus ativos,
  # o snapshot FUNCIONA — otel_usage nao fica null e o cenario falha sem que
  # haja defeito no codigo. Porta alta fechada = "maquina sem telemetria"
  # deterministico. Simetrico ao export de scenario_end_otel_usage_captura_
  # delta_da_onda, que aponta para uma fixture file://.
  CSTK_OTEL_ENDPOINT="http://127.0.0.1:59999/metrics"; export CSTK_OTEL_ENDPOINT
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando
  unset CSTK_OTEL_ENDPOINT
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "end" "$_CAPTURED_STDERR"; return 1; }
  # Telemetria desligada => AUSENTE (null), jamais zero fabricado.
  _got=$(jq -r '.waves[-1].otel_usage' "$_sd/state.json")
  [ "$_got" = "null" ] || { _fail "otel_usage" "esperado null sem telemetria, obtido '$_got'"; return 1; }
  return 0
}

# ==== Motivo da ausencia de medicao OTel persistido na onda ====
#
# `otel_usage: null` sozinho e mudo: o painel mostra "s/ dado" e o operador
# nao tem como saber se a telemetria estava desligada, se o processo do
# exporter trocou no meio da onda, ou se havia duas sessoes disputando. O
# motivo SEMPRE foi conhecido no fechamento — e sempre foi descartado pelo
# `2>/dev/null` de _so_otel_delta.

# _otel_fixture_sess FILE SESSION COST -> fixture com session_id explicito
# (o _otel_fixture padrao fixa "sess-w"; aqui o ponto e trocar a sessao).
_otel_fixture_sess() {
  printf 'claude_code_cost_usage_total{session_id="%s",terminal_type="ghostty",model="claude-opus-5[1m]",query_source="main"} %s\n' \
    "$2" "$3" > "$1"
}

scenario_end_otel_absent_reason_exporter_trocou() {
  _sd="$TMPDIR_TEST/otel-reason-troca"
  _init_state "$_sd"
  _fx="$TMPDIR_TEST/otel-troca.txt"
  CSTK_OTEL_ENDPOINT="file://$_fx"; export CSTK_OTEL_ENDPOINT

  _otel_fixture_sess "$_fx" "sess-antiga" 1.0
  capture "$SCRIPT" start --state-dir "$_sd"
  # Restart do Claude Code no MEIO da onda: exporter novo, sessao outra.
  _otel_fixture_sess "$_fx" "sess-nova" 0.2
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando
  _e=$_CAPTURED_EXIT; _err=$_CAPTURED_STDERR
  unset CSTK_OTEL_ENDPOINT
  [ "$_e" = 0 ] || { _fail "end" "$_err"; return 1; }

  _got=$(jq -r '.waves[-1].otel_usage' "$_sd/state.json")
  [ "$_got" = "null" ] || { _fail "otel_usage" "esperado null, obtido '$_got'"; return 1; }
  _reason=$(jq -r '.waves[-1].otel_absent_reason // ""' "$_sd/state.json")
  [ "$_reason" = "exporter-trocou" ] \
    || { _fail "otel_absent_reason" "esperado exporter-trocou, obtido '$_reason'"; return 1; }
  return 0
}

scenario_end_otel_absent_reason_sem_telemetria() {
  _sd="$TMPDIR_TEST/otel-reason-off"
  _init_state "$_sd"
  CSTK_OTEL_ENDPOINT="http://127.0.0.1:59999/metrics"; export CSTK_OTEL_ENDPOINT
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando
  unset CSTK_OTEL_ENDPOINT
  _reason=$(jq -r '.waves[-1].otel_absent_reason // ""' "$_sd/state.json")
  [ "$_reason" = "sem-snapshot" ] \
    || { _fail "otel_absent_reason" "esperado sem-snapshot (telemetria off), obtido '$_reason'"; return 1; }
  return 0
}

# Onda medida NAO ganha a chave — motivo so existe onde ha ausencia.
scenario_end_onda_medida_nao_grava_motivo() {
  _sd="$TMPDIR_TEST/otel-reason-ok"
  _init_state "$_sd"
  _fx="$TMPDIR_TEST/otel-ok.txt"
  CSTK_OTEL_ENDPOINT="file://$_fx"; export CSTK_OTEL_ENDPOINT
  _otel_fixture "$_fx" 1.0 0.5
  capture "$SCRIPT" start --state-dir "$_sd"
  _otel_fixture "$_fx" 4.0 3.5
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando
  unset CSTK_OTEL_ENDPOINT
  _has=$(jq -r 'has("otel_absent_reason") | tostring' <<EOF
$(jq -c '.waves[-1]' "$_sd/state.json")
EOF
)
  [ "$_has" = "false" ] \
    || { _fail "otel_absent_reason" "onda medida NAO deve carregar motivo"; return 1; }
  return 0
}

scenario_end_otel_usage_captura_delta_da_onda() {
  _sd="$TMPDIR_TEST/state-otel"
  _init_state "$_sd"
  _fx="$TMPDIR_TEST/otel-live.txt"

  # export explicito: a atribuicao-prefixo `VAR=x capture ...` nao propaga
  # para o subprocesso que `capture` executa.
  CSTK_OTEL_ENDPOINT="file://$_fx"; export CSTK_OTEL_ENDPOINT

  # start: baseline
  _otel_fixture "$_fx" 1.0 0.5
  capture "$SCRIPT" start --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { unset CSTK_OTEL_ENDPOINT; _fail "start" "$_CAPTURED_STDERR"; return 1; }

  # a onda consome: contadores cumulativos sobem
  _otel_fixture "$_fx" 4.0 3.5
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando
  _e=$_CAPTURED_EXIT; _err=$_CAPTURED_STDERR
  unset CSTK_OTEL_ENDPOINT
  [ "$_e" = 0 ] || { _fail "end" "$_err"; return 1; }

  _cost=$(jq -r '.waves[-1].otel_usage.total_cost_usd' "$_sd/state.json")
  [ "$_cost" = "6" ] || { _fail "total_cost_usd" "esperado 6 ((4-1)+(3.5-0.5)), obtido '$_cost'"; return 1; }
  _sub=$(jq -r '.waves[-1].otel_usage.by_source.subagent.cost_usd' "$_sd/state.json")
  [ "$_sub" = "3" ] || { _fail "subagent cost" "esperado 3 (3.5-0.5), obtido '$_sub'"; return 1; }
  # PII jamais no state.json
  grep -q "user_email\|user_account_uuid" "$_sd/state.json" \
    && { _fail "PII" "label de PII vazou para o state.json"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# Hook marco-aware de retrospectiva proativa (a cada 25 ondas).
#
# Regressao real: o gatilho vivia SO como prosa no agente-00c-orchestrator.md
# e dependia de o orquestrador lembrar de calcular `waves.length % 25`.
# Falhou em producao (execucao de 31 ondas sem NENHUMA Decisao de marco).
# Aqui o gatilho e do proprio `end`, entao e testavel.
# ---------------------------------------------------------------------------

# Injeta N ondas JA FECHADAS direto no state (muito mais rapido que N
# start/end reais, que so somariam custo de jq sem cobrir nada a mais).
_seed_waves() {
  _sw_sd=$1; _sw_n=$2
  _sw_tmp="$_sw_sd/state.seed.json"
  jq --argjson n "$_sw_n" '
    .waves = [range(0; $n) | {
      id: ("onda-" + (("00" + ((.+1)|tostring)) | .[-3:])),
      started_at: "2026-01-01T00:00:00Z",
      finished_at: "2026-01-01T00:01:00Z",
      wallclock_seconds: 60,
      tool_calls: 0,
      termination_reason: "etapa_concluida_avancando",
      next_wave_scheduled_for: null,
      executed_stages: [],
      skills_invoked: [],
      touched_key_aspects: []
    }]
  ' "$_sw_sd/state.json" > "$_sw_tmp" && mv -f "$_sw_tmp" "$_sw_sd/state.json"
  capture "$RW" sha256-update --state-dir "$_sw_sd"
}

# Fecha a onda de indice N (seed de N-1 + um start/end real).
_close_wave_n() {
  _cw_sd=$1; _cw_n=$2; _cw_motivo=$3
  _seed_waves "$_cw_sd" "$((_cw_n - 1))"
  capture "$SCRIPT" start --state-dir "$_cw_sd"
  capture "$SCRIPT" end --state-dir "$_cw_sd" --motivo-termino "$_cw_motivo"
}

scenario_marco_25_dispara_decisao_e_bloqueio() {
  _sd="$TMPDIR_TEST/state-marco25"
  _init_state "$_sd"
  _close_wave_n "$_sd" 25 etapa_concluida_avancando
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "end" "$_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains "marco de 25 ondas" || return 1

  _n=$(jq -r '.decisions | length' "$_sd/state.json")
  [ "$_n" = 1 ] || { _fail "decisoes" "esperado 1 Decisao de marco, obtido $_n"; return 1; }
  _ctx=$(jq -r '.decisions[-1].context' "$_sd/state.json")
  case "$_ctx" in
    "Marco de 25 ondas atingido"*) : ;;
    *) _fail "context" "esperado prefixo 'Marco de 25 ondas atingido', obtido '$_ctx'"; return 1 ;;
  esac
  _n=$(jq -r '.human_blocks | length' "$_sd/state.json")
  [ "$_n" = 1 ] || { _fail "bloqueios" "esperado 1 bloqueio LEVE, obtido $_n"; return 1; }
  # Bloqueio linkado a Decisao (Principio I) e LEVE (operador pode recusar).
  _dec=$(jq -r '.decisions[-1].id' "$_sd/state.json")
  _lnk=$(jq -r '.human_blocks[-1].decision_id' "$_sd/state.json")
  [ "$_dec" = "$_lnk" ] || { _fail "link" "bloqueio aponta '$_lnk', Decisao e '$_dec'"; return 1; }
  jq -e '.human_blocks[-1].recommended_options | index("nao-continuar")' "$_sd/state.json" >/dev/null     || { _fail "opcoes" "bloqueio precisa oferecer 'nao-continuar' (LEVE)"; return 1; }
  # Milestone so avanca DEPOIS de Decisao + bloqueio gravados.
  _ms=$(jq -r '.next_retrospective_milestone' "$_sd/state.json")
  [ "$_ms" = 50 ] || { _fail "milestone" "esperado 50, obtido '$_ms'"; return 1; }
  _st=$(jq -r '.execution.status' "$_sd/state.json")
  [ "$_st" = "aguardando_humano" ] || { _fail "status" "esperado aguardando_humano, obtido '$_st'"; return 1; }
  return 0
}

scenario_marco_nao_redispara_na_onda_seguinte() {
  _sd="$TMPDIR_TEST/state-marco-idem"
  _init_state "$_sd"
  _close_wave_n "$_sd" 25 etapa_concluida_avancando
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "end onda 26" "$_CAPTURED_STDERR"; return 1; }
  case "$_CAPTURED_STDERR" in
    *"marco de 26 ondas"*) _fail "idempotencia" "marco redisparou na onda 26"; return 1 ;;
  esac
  _n=$(jq -r '.decisions | length' "$_sd/state.json")
  [ "$_n" = 1 ] || { _fail "idempotencia" "marco redisparou: $_n Decisoes"; return 1; }
  _n=$(jq -r '.human_blocks | length' "$_sd/state.json")
  [ "$_n" = 1 ] || { _fail "idempotencia" "marco redisparou: $_n bloqueios"; return 1; }
  return 0
}

# Motivos terminais/bloqueados nao disparam, e — critico — NAO consomem a
# milestone: ela fica pendente para a proxima onda que de fato avancar.
scenario_marco_nao_dispara_em_motivo_terminal() {
  for _m in bloqueio_humano aborto concluido; do
    _sd="$TMPDIR_TEST/state-marco-$_m"
    _init_state "$_sd"
    _close_wave_n "$_sd" 25 "$_m"
    [ "$_CAPTURED_EXIT" = 0 ] || { _fail "end $_m" "$_CAPTURED_STDERR"; return 1; }
    _n=$(jq -r '.decisions | length' "$_sd/state.json")
    [ "$_n" = 0 ] || { _fail "motivo=$_m" "nao devia registrar Decisao de marco (obtido $_n)"; return 1; }
    _ms=$(jq -r '.next_retrospective_milestone // "ausente"' "$_sd/state.json")
    [ "$_ms" = "ausente" ] || { _fail "motivo=$_m" "milestone consumida sem disparo ('$_ms')"; return 1; }
  done
  return 0
}

# Self-healing: o gatilho e `>= milestone`, nao `% 25 == 0`. Uma execucao que
# passou de 25 sem disparar (exatamente o caso mcp-project-scafold, 31 ondas
# sem marco) dispara na primeira onda que avanca, em vez de esperar a 50a.
scenario_marco_dispara_atrasado_quando_passou_do_multiplo() {
  _sd="$TMPDIR_TEST/state-marco-atrasado"
  _init_state "$_sd"
  _close_wave_n "$_sd" 31 etapa_concluida_avancando
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "end" "$_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains "marco de 31 ondas" || return 1
  _ms=$(jq -r '.next_retrospective_milestone' "$_sd/state.json")
  [ "$_ms" = 50 ] || { _fail "milestone" "esperado 50 para 31 ondas, obtido '$_ms'"; return 1; }
  return 0
}

scenario_marco_desligavel_por_env() {
  _sd="$TMPDIR_TEST/state-marco-off"
  _init_state "$_sd"
  CSTK_RETRO_MILESTONE_DISABLED=1; export CSTK_RETRO_MILESTONE_DISABLED
  _close_wave_n "$_sd" 25 etapa_concluida_avancando
  _e=$_CAPTURED_EXIT; _err=$_CAPTURED_STDERR
  unset CSTK_RETRO_MILESTONE_DISABLED
  [ "$_e" = 0 ] || { _fail "end" "$_err"; return 1; }
  _n=$(jq -r '.decisions | length' "$_sd/state.json")
  [ "$_n" = 0 ] || { _fail "kill-switch" "marco disparou com CSTK_RETRO_MILESTONE_DISABLED=1"; return 1; }
  return 0
}

# Contrato best-effort: registrar o marco NUNCA pode derrubar o fechamento da
# onda. Sem os scripts irmaos, `end` ainda fecha a onda com exit 0 e a
# milestone fica intacta (nova tentativa na proxima onda).
scenario_marco_falho_nao_derruba_end() {
  _sd="$TMPDIR_TEST/state-marco-bestefort"
  _init_state "$_sd"
  _seed_waves "$_sd" 24
  # Copia do diretorio de scripts SEM os irmaos que o hook precisa. Copia o
  # diretorio inteiro porque state-ondas.sh sourceia _diag.sh — a ausencia
  # sob teste e a dos helpers do HOOK, nao a do runtime de diagnostico.
  _iso="$TMPDIR_TEST/iso-scripts"
  rm -rf "$_iso"; mkdir -p "$_iso"
  cp "$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/"*.sh "$_iso/"
  rm -f "$_iso/state-decisions.sh" "$_iso/bloqueios.sh"
  capture "$_iso/state-ondas.sh" start --state-dir "$_sd"
  capture "$_iso/state-ondas.sh" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "end" "hook derrubou o fechamento da onda: $_CAPTURED_STDERR"; return 1; }
  # A onda FOI fechada de verdade.
  _tr=$(jq -r '.waves[-1].termination_reason' "$_sd/state.json")
  [ "$_tr" = "etapa_concluida_avancando" ] || { _fail "onda" "onda nao foi fechada ('$_tr')"; return 1; }
  _ms=$(jq -r '.next_retrospective_milestone // "ausente"' "$_sd/state.json")
  [ "$_ms" = "ausente" ] || { _fail "milestone" "consumida apesar do hook ter falhado ('$_ms')"; return 1; }
  return 0
}

# --add-etapa e token de etapa, nunca prosa: o knowledge.db deriva
# waves.stages/n_stages de executed_stages, e um resumo de conclusao gravado
# aqui corrompia o indice (caso real: 3 ondas com narrativa e n_stages=1).
scenario_end_add_etapa_rejeita_prosa() {
  _sd="$TMPDIR_TEST/state-etapa-token"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando \
    --add-etapa "onda-029 concluida: task 5.3 avancou de 8/16 para 9/16 patterns"
  [ "$_CAPTURED_EXIT" != 0 ] || { _fail "prosa aceita" "end deveria rejeitar --add-etapa com prosa"; return 1; }
  # Rejeicao acontece no parse, ANTES de qualquer write: a onda segue aberta.
  _fim=$(jq -r '.waves[-1].finished_at // "aberta"' "$_sd/state.json")
  [ "$_fim" = "aberta" ] || { _fail "write parcial" "onda foi fechada apesar do erro ($_fim)"; return 1; }
  # Valor com newline embutido viraria 2+ etapas no split por linha: rejeita.
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando \
    --add-etapa "specify
prosa contrabandeada na segunda linha"
  [ "$_CAPTURED_EXIT" != 0 ] || { _fail "newline aceito" "token multi-linha deveria ser rejeitado"; return 1; }
  # Tokens legitimos (ponto, maiuscula, hifen) seguem aceitos.
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando \
    --add-etapa execute-task-F3.1 --add-etapa execute-task-F3.2
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "token valido" "$_CAPTURED_STDERR"; return 1; }
  _st=$(jq -r '.waves[-1].executed_stages | join(",")' "$_sd/state.json")
  [ "$_st" = "execute-task-F3.1,execute-task-F3.2" ] || { _fail "etapas" "obtido $_st"; return 1; }
}

# ==== Backend dual SQLite (feature state-db-foundation, FASE 3 task 3.3) ====
#
# Ref: docs/specs/state-db-foundation/contracts/primitives.md §C1 (paridade)
#      §C2 (selecao de backend) §C3 (semantica de erro nova) §C4 (transacao)
#
# Mesmo padrao de tests/test_state-rw.sh (task 3.2): aplica o DDL via
# state-db-schema.sh e semeia uma execution minima via sqlite3 diretamente
# (init nunca cria state.db — isso e a migracao, FASE 6, ainda nao
# implementada).

SCHEMA_SCRIPT="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/state-db-schema.sh"

if ! command -v sqlite3 >/dev/null 2>&1; then
  printf '# test_state-ondas.sh: sqlite3 ausente — pulando cenarios de backend SQLite\n'
else

# _seed_sqlite_backend DIR [TARGET_PROJECT_PATH] -> cria state.db com uma
# execution minima (id=exec-1), pronta para start/end/record-*/wave-status.
_seed_sqlite_backend() {
  _ssb_dir=$1
  _ssb_pap=${2:-/tmp/p}
  mkdir -p "$_ssb_dir"
  "$SCHEMA_SCRIPT" create --db "$_ssb_dir/state.db" >/dev/null 2>&1 \
    || { _fail "seed: schema create falhou" ""; return 1; }
  sqlite3 "$_ssb_dir/state.db" "
    PRAGMA foreign_keys=ON;
    INSERT INTO execution (id,schema_version,target_project_path,target_project_description,status,started_at,current_stage,next_instruction,external_urls_whitelist,circular_movement_history,initial_key_aspects,atomic_commit_enabled)
    VALUES ('exec-1','1.0.0','$_ssb_pap','desc de teste com detalhe','em_andamento','2026-07-30T00:00:00Z','execute-task','faca algo','[]','[]','[]',0);
  " || { _fail "seed: insert execution falhou" ""; return 1; }
}

scenario_sqlite_start_cria_onda_001() {
  _sd="$TMPDIR_TEST/sqlite-start"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" start --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sqlite start" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "onda-001" || return 1
  capture "$SCRIPT" current-id --state-dir "$_sd"
  assert_stdout_contains "onda-001" || return 1
}

scenario_sqlite_start_sequencial_gera_onda_002() {
  _sd="$TMPDIR_TEST/sqlite-start-seq"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando
  capture "$SCRIPT" start --state-dir "$_sd"
  assert_stdout_contains "onda-002" || return 1
}

# C3: start com onda ja aberta MUST falhar (ux_wave_single_open) — mudanca
# de comportamento autorizada face ao path JSON, que hoje duplica a onda
# silenciosamente (por isso o orquestrador carrega a guarda wave-status).
scenario_sqlite_start_onda_ja_aberta_falha() {
  _sd="$TMPDIR_TEST/sqlite-start-dup"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" start --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "primeiro start" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" start --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" != 0 ] || { _fail "segundo start deveria falhar (C3)" "obtido exit 0"; return 1; }
  # Guarda wave-status continua valida como defesa em profundidade (task 3.3.4).
  capture "$SCRIPT" wave-status --state-dir "$_sd"
  assert_stdout_contains "open" || return 1
  capture "$SCRIPT" current-id --state-dir "$_sd"
  assert_stdout_contains "onda-001" || return 1
}

# mcp-elicitation-optins FASE 9 (M4, task 9.3.1) sob backend SQLite —
# `.optin_responses` idem sob backend JSON (via extra_fields, task 4.2.2 —
# state-rw.sh get e backend-agnostico, a guarda nao precisa de branch por
# backend).
scenario_sqlite_start_onda001_recusada_sem_optin_feature00c() {
  _sd="$TMPDIR_TEST/feature-00c-state/demo-feature/sqlite-optin"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" start --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" != 0 ] || { _fail "sqlite start deveria recusar onda-001 sem optin" "obtido exit 0"; return 1; }
  assert_stderr_contains "optin-invariant-i2" || return 1
  assert_stderr_contains "atomic_commit" || return 1
}

scenario_sqlite_start_onda001_aceita_com_optin_feature00c() {
  _sd="$TMPDIR_TEST/feature-00c-state/demo-feature/sqlite-optin-ok"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$RW" set --state-dir "$_sd" --field '.optin_responses' \
    --value '[{"field":"atomic_commit","channel":"structured","outcome":"accepted","applied_value":"true","recorded_at":"2026-08-17T00:00:00Z","reason":null}]'
  capture "$SCRIPT" start --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sqlite start" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "onda-001" || return 1
}

scenario_sqlite_wave_status_transicoes() {
  _sd="$TMPDIR_TEST/sqlite-wave-status"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" wave-status --state-dir "$_sd"
  assert_stdout_contains "none" || return 1
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" wave-status --state-dir "$_sd"
  assert_stdout_contains "open" || return 1
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando
  capture "$SCRIPT" wave-status --state-dir "$_sd"
  assert_stdout_contains "closed" || return 1
}

scenario_sqlite_current_id_init_sem_onda() {
  _sd="$TMPDIR_TEST/sqlite-current-id-init"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" current-id --state-dir "$_sd"
  assert_stdout_contains "init" || return 1
}

scenario_sqlite_end_sem_onda_aberta_falha() {
  _sd="$TMPDIR_TEST/sqlite-end-no-open"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando
  [ "$_CAPTURED_EXIT" != 0 ] || { _fail "end sem onda deveria falhar" "obtido exit 0"; return 1; }
}

scenario_sqlite_end_atualiza_onda_e_acumulados() {
  _sd="$TMPDIR_TEST/sqlite-end-acumulados"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" tool-call-tick --state-dir "$_sd"
  capture "$SCRIPT" tool-call-tick --state-dir "$_sd"
  assert_stdout_contains "2" || return 1
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino bloqueio_humano \
    --add-etapa briefing
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sqlite end" "$_CAPTURED_STDERR"; return 1; }
  capture "$RW" get --state-dir "$_sd" --field '.waves[-1].termination_reason'
  assert_stdout_contains "bloqueio_humano" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.waves[-1].tool_calls'
  assert_stdout_contains "2" || return 1
  # accumulated_metrics e DERIVADO por agregacao SQL sob backend sqlite
  # (_sr_db_read) — nao ha campo separado a manter em sincronia.
  capture "$RW" get --state-dir "$_sd" --field '.accumulated_metrics.waves_total'
  assert_stdout_contains "1" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.accumulated_metrics.tool_calls_total'
  assert_stdout_contains "2" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.waves[-1].executed_stages'
  assert_stdout_contains "briefing" || return 1
}

# ==== end --advance sob backend SQLite (wave-close-advance FR-006) ====
# Paridade: mesmo comportamento do path JSON; avanco na MESMA transacao C4.

scenario_sqlite_end_advance_avanca_ponteiro_na_mesma_transacao() {
  _sd="$TMPDIR_TEST/sqlite-end-advance"
  _seed_sqlite_backend "$_sd" || return 1   # seed: current_stage=execute-task
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" \
    --motivo-termino etapa_concluida_avancando --advance
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sqlite end --advance" "$_CAPTURED_STDERR"; return 1; }
  capture "$RW" get --state-dir "$_sd" --field '.current_stage'
  assert_stdout_contains "review-task" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.next_instruction'
  assert_stdout_contains "Iniciar etapa review-task" || return 1
  capture "$SCRIPT" wave-status --state-dir "$_sd"
  assert_stdout_contains "closed" || return 1
}

scenario_sqlite_end_advance_fase_terminal_falha_sem_write() {
  # SC-002 sob SQLite: fail-closed ANTES da transacao; onda segue aberta e
  # ponteiro intacto (seed: current_stage=execute-task, instrucao "faca algo").
  _sd="$TMPDIR_TEST/sqlite-end-advance-terminal"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" \
    --motivo-termino etapa_concluida_avancando --advance --terminal-phase execute-task
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit esperado 2" "obtido $_CAPTURED_EXIT"; return 1; }
  capture "$SCRIPT" wave-status --state-dir "$_sd"
  assert_stdout_contains "open" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.next_instruction'
  assert_stdout_contains "faca algo" || return 1
}

# ---- FASE 5 (state-db-foundation): export derivado, contracts/export.md ----

# 5.2.1/5.2.3 (SC-004): `end` sob backend sqlite dispara o export
# automaticamente, refletindo a onda recem-fechada (freshness trivial —
# gerado sincronamente dentro do proprio `end`).
scenario_sqlite_end_gera_export_snapshot_automatico() {
  _sd="$TMPDIR_TEST/sqlite-end-export-auto"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" start --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "start" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" tool-call-tick --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino concluido
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "end" "$_CAPTURED_STDERR"; return 1; }

  _snap=$(ls "$_sd"/state-history/export-onda-001-*.json 2>/dev/null | head -1)
  [ -n "$_snap" ] && [ -f "$_snap" ] \
    || { _fail "export automatico nao gerado (5.2.1)" "$_sd/state-history"; return 1; }

  _reason=$(jq -r '.waves[-1].termination_reason' "$_snap" 2>/dev/null)
  [ "$_reason" = "concluido" ] \
    || { _fail "export nao reflete termination_reason da onda fechada (SC-004)" "$_reason"; return 1; }
  _tc=$(jq -r '.waves[-1].tool_calls' "$_snap" 2>/dev/null)
  [ "$_tc" = "1" ] \
    || { _fail "export nao reflete tool_calls da onda fechada (SC-004)" "$_tc"; return 1; }

  # E1: o export automatico tambem passa em state-validate.sh
  _validate_dir="$TMPDIR_TEST/validate-auto-export"
  mkdir -p "$_validate_dir"
  cp "$_snap" "$_validate_dir/state.json"
  capture sh "$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/state-validate.sh" --state-dir "$_validate_dir"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "export automatico nao passa em state-validate.sh (E1)" "$_CAPTURED_STDERR"; return 1; }
}

# 5.2.2/5.2.4 (E6): falha ao gerar o export MUST NOT reverter nem impedir o
# fechamento da onda no state.db (fonte de verdade). Simula a falha
# ocupando state-history/ com um arquivo comum (nao diretorio) — mkdir -p
# falha sem tocar em permissoes do state-dir (que quebraria o proprio
# UPDATE do state.db, nao so o export).
scenario_sqlite_end_e6_falha_export_nao_reverte_fechamento() {
  _sd="$TMPDIR_TEST/sqlite-end-export-e6"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" start --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "start" "$_CAPTURED_STDERR"; return 1; }
  : > "$_sd/state-history"

  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando
  _exit=$_CAPTURED_EXIT
  _stderr="$_CAPTURED_STDERR"
  rm -f "$_sd/state-history"  # restaura para cleanup

  [ "$_exit" = 0 ] \
    || { _fail "end deveria seguir exit 0 mesmo com export falho (E6)" "$_stderr"; return 1; }
  case "$_stderr" in
    *export*) : ;;
    *) _fail "falha do export deveria ser reportada em stderr (E6)" "$_stderr"; return 1 ;;
  esac
  capture "$RW" get --state-dir "$_sd" --field '.waves[-1].termination_reason'
  assert_stdout_contains "etapa_concluida_avancando" || return 1
}

# 5.3.1/5.3.2: gatilho sob demanda — comando explicito, reflete mutacoes
# aplicadas apos snapshots anteriores, nomes distintos por chamada.
scenario_sqlite_export_snapshot_sob_demanda_multiplas_mutacoes() {
  _sd="$TMPDIR_TEST/sqlite-export-sob-demanda"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" start --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "start" "$_CAPTURED_STDERR"; return 1; }

  capture "$SCRIPT" export-snapshot --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "export-snapshot 1 exit" "$_CAPTURED_STDERR"; return 1; }
  _snap1="$_CAPTURED_STDOUT"
  [ -f "$_snap1" ] || { _fail "export-snapshot 1 nao criou arquivo" "$_snap1"; return 1; }
  _stage1=$(jq -r '.current_stage' "$_snap1" 2>/dev/null)
  [ "$_stage1" = "execute-task" ] || { _fail "snapshot1.current_stage" "$_stage1"; return 1; }

  capture "$RW" set --state-dir "$_sd" --field '.current_stage' --value '"plan"'
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "set current_stage" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" tool-call-tick --state-dir "$_sd"

  capture "$SCRIPT" export-snapshot --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "export-snapshot 2 exit" "$_CAPTURED_STDERR"; return 1; }
  _snap2="$_CAPTURED_STDOUT"
  [ -f "$_snap2" ] || { _fail "export-snapshot 2 nao criou arquivo" "$_snap2"; return 1; }
  [ "$_snap1" != "$_snap2" ] \
    || { _fail "snapshots sucessivos deveriam ter nomes distintos" "$_snap1"; return 1; }
  _stage2=$(jq -r '.current_stage' "$_snap2" 2>/dev/null)
  [ "$_stage2" = "plan" ] \
    || { _fail "snapshot2 nao reflete mutacao aplicada apos snapshot1 (5.3.2)" "$_stage2"; return 1; }
}

# export-snapshot tambem funciona sob backend JSON (backend-agnostico —
# reusa `state-rw.sh read`, que ja dispatcha por backend).
scenario_json_export_snapshot_sob_demanda() {
  _sd="$TMPDIR_TEST/json-export-sob-demanda"
  capture "$RW" init --state-dir "$_sd" --execucao-id "exec-export" \
    --projeto-alvo-path "/tmp/proj" --descricao "descricao valida >=10"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "init json" "$_CAPTURED_STDERR"; return 1; }

  capture "$SCRIPT" export-snapshot --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "export-snapshot json exit" "$_CAPTURED_STDERR"; return 1; }
  _snap="$_CAPTURED_STDOUT"
  [ -f "$_snap" ] || { _fail "export-snapshot json nao criou arquivo" "$_snap"; return 1; }
  jq -e . "$_snap" >/dev/null 2>&1 || { _fail "export-snapshot json nao e JSON valido" ""; return 1; }
}

# 5.4.1 (FR-013-INFRA-BACKUP, literal: "com a restauracao validada por
# teste antes de ser considerada disponivel"): um snapshot de
# state-history/ (export serializado) restaurado como state.json de um
# state-dir NOVO (backend JSON) e de fato OPERAVEL — nao so passa em
# state-validate.sh, mas sustenta get/current-id/wave-status e permite
# iniciar onda nova a partir dele.
scenario_sqlite_export_snapshot_restauracao_operavel_fr013() {
  _sd="$TMPDIR_TEST/sqlite-export-origem"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" start --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "start origem" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "end origem" "$_CAPTURED_STDERR"; return 1; }

  _snap=$(ls "$_sd"/state-history/export-onda-001-*.json 2>/dev/null | head -1)
  [ -n "$_snap" ] || { _fail "export automatico ausente para restauracao" ""; return 1; }

  _restore_dir="$TMPDIR_TEST/restaurado"
  mkdir -p "$_restore_dir"
  cp "$_snap" "$_restore_dir/state.json"

  capture "$RW" get --state-dir "$_restore_dir" --field '.current_stage'
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "get pos-restauracao" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "execute-task" || return 1

  capture "$SCRIPT" current-id --state-dir "$_restore_dir"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "current-id pos-restauracao" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "onda-001" || return 1

  capture "$SCRIPT" wave-status --state-dir "$_restore_dir"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "wave-status pos-restauracao" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "closed" || return 1

  # Operavel de verdade: uma onda NOVA pode comecar a partir do restaurado.
  capture "$SCRIPT" start --state-dir "$_restore_dir"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "start pos-restauracao" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "onda-002" || return 1
}

scenario_sqlite_end_add_etapa_acumula_multiplas() {
  _sd="$TMPDIR_TEST/sqlite-end-etapas"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando \
    --add-etapa execute-task-F3.1 --add-etapa execute-task-F3.2
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sqlite end etapas" "$_CAPTURED_STDERR"; return 1; }
  capture "$RW" get --state-dir "$_sd" --field '.waves[-1].executed_stages | join(",")'
  assert_stdout_contains "execute-task-F3.1,execute-task-F3.2" || return 1
}

scenario_sqlite_end_next_instruction_persiste() {
  _sd="$TMPDIR_TEST/sqlite-end-next-instr"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando \
    --next-instruction "Continuar com a proxima fase"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sqlite end next-instr" "$_CAPTURED_STDERR"; return 1; }
  capture "$RW" get --state-dir "$_sd" --field '.next_instruction'
  assert_stdout_contains "Continuar com a proxima fase" || return 1
}

scenario_sqlite_record_skill_idempotente() {
  _sd="$TMPDIR_TEST/sqlite-record-skill"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" start --state-dir "$_sd"
  # decision_id de skill_invocation tem FK para decision(id) — semeia uma
  # Decisao minima valida (todas as CHECK de data-model.md) para exercitar
  # o caminho com --decisao-id preenchido.
  sqlite3 "$_sd/state.db" "
    PRAGMA foreign_keys=ON;
    INSERT INTO decision (id,execution_id,timestamp,agent,stage,context,options_considered,choice,rationale)
    VALUES ('dec-001','exec-1','2026-07-30T00:00:00Z','feature-00c-feature-orchestrator','specify','contexto de teste com detalhe suficiente','[\"a\",\"b\"]','a','justificativa de teste com detalhe suficiente');
  " || { _fail "seed decision" ""; return 1; }
  capture "$SCRIPT" record-skill --state-dir "$_sd" --skill specify --decisao-id dec-001
  assert_stdout_contains "1" || return 1
  capture "$SCRIPT" record-skill --state-dir "$_sd" --skill specify --decisao-id dec-001
  assert_stdout_contains "1" || return 1
  capture "$SCRIPT" record-skill --state-dir "$_sd" --skill clarify
  assert_stdout_contains "2" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.waves[-1].skills_invoked | length'
  assert_stdout_contains "2" || return 1
}

scenario_sqlite_record_skill_sem_onda_falha() {
  _sd="$TMPDIR_TEST/sqlite-record-skill-no-wave"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" record-skill --state-dir "$_sd" --skill specify
  [ "$_CAPTURED_EXIT" != 0 ] || { _fail "record-skill sem onda deveria falhar" "obtido exit 0"; return 1; }
}

scenario_sqlite_record_task_upsert_idempotente() {
  _sd="$TMPDIR_TEST/sqlite-record-task-upsert"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" record-task --state-dir "$_sd" --task-id 4.1 --titulo "Original" \
    --outcome fail --testes-rodados 3 --testes-passados 1
  assert_stdout_contains "1" || return 1
  capture "$SCRIPT" record-task --state-dir "$_sd" --task-id 4.1 --titulo "Corrigida" \
    --outcome pass --testes-rodados 3 --testes-passados 3
  assert_stdout_contains "1" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.tasks[] | select(.task_id=="4.1") | .outcome'
  assert_stdout_contains "pass" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.tasks[] | select(.task_id=="4.1") | .title'
  assert_stdout_contains "Corrigida" || return 1
}

scenario_sqlite_record_task_if_absent_nao_clobbera() {
  _sd="$TMPDIR_TEST/sqlite-record-task-if-absent"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" record-task --state-dir "$_sd" --task-id 4.2 --titulo "REAL" \
    --outcome pass --origem execute-task
  capture "$SCRIPT" record-task --state-dir "$_sd" --task-id 4.2 --titulo "DERIVADO" \
    --outcome pass --origem reconcile --if-absent
  capture "$RW" get --state-dir "$_sd" --field '.tasks[] | select(.task_id=="4.2") | .title'
  assert_stdout_contains "REAL" || return 1
}

scenario_sqlite_reconcile_tasks_backfill_e_idempotente() {
  _sd="$TMPDIR_TEST/sqlite-reconcile-tasks"
  _md="$TMPDIR_TEST/sqlite-tasks.md"
  _seed_sqlite_backend "$_sd" || return 1
  _write_tasks_md "$_md"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" reconcile-tasks --state-dir "$_sd" --tasks-md "$_md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sqlite reconcile-tasks" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "3" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.tasks | length'
  assert_stdout_contains "3" || return 1
  # idempotente: segunda chamada nao back-filla de novo
  capture "$SCRIPT" reconcile-tasks --state-dir "$_sd" --tasks-md "$_md"
  assert_stdout_contains "0" || return 1
}

scenario_sqlite_reconcile_tasks_dry_run_nao_escreve() {
  _sd="$TMPDIR_TEST/sqlite-reconcile-tasks-dry"
  _md="$TMPDIR_TEST/sqlite-tasks-dry.md"
  _seed_sqlite_backend "$_sd" || return 1
  _write_tasks_md "$_md"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" reconcile-tasks --state-dir "$_sd" --tasks-md "$_md" --dry-run
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "dry-run" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "1.1" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.tasks | length'
  assert_stdout_contains "0" || return 1
}

scenario_sqlite_git_commit_cria_commit() {
  _sd="$TMPDIR_TEST/sqlite-git-commit"
  _pap="$TMPDIR_TEST/sqlite-proj"
  mkdir -p "$_pap"
  ( cd "$_pap" && git init -q -b main \
    && git config user.email t@t \
    && git config user.name t )
  _seed_sqlite_backend "$_sd" "$_pap" || return 1
  capture "$SCRIPT" start --state-dir "$_sd"
  ( cd "$_pap" && touch hello.txt )
  capture "$SCRIPT" git-commit --state-dir "$_sd" --projeto-alvo-path "$_pap" \
    --motivo "sqlite commit FASE 3.3"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sqlite git-commit" "$_CAPTURED_STDERR"; return 1; }
  _msg=$(git -C "$_pap" log -1 --pretty=%s)
  case "$_msg" in
    *"chore(agente-00c):"*"sqlite commit FASE 3.3"*) ;;
    *) _fail "sqlite commit msg" "obtido: $_msg"; return 1 ;;
  esac
}

scenario_sqlite_reconcile_wave_noop_quando_sem_onda() {
  _sd="$TMPDIR_TEST/sqlite-reconcile-wave-noop"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" reconcile-wave --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "reconcile-wave noop" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "noop (none)" || return 1
}

scenario_sqlite_reconcile_wave_fecha_e_avanca_ponteiro() {
  _sd="$TMPDIR_TEST/sqlite-reconcile-wave-fecha"
  _seed_sqlite_backend "$_sd" || return 1
  # current_stage=execute-task (default do seed): terminal-phase precisa
  # casar com a fase CORRENTE para acionar o ramo terminal — se nao, a
  # fase corrente possui proxima real no pipeline (execute-task ->
  # review-task) e reconcile-wave apenas avanca o ponteiro (ramo nao-
  # terminal), que e o comportamento correto (nao um bug).
  capture "$RW" set --state-dir "$_sd" --field '.current_stage' --value '"review-task"'
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" reconcile-wave --state-dir "$_sd" --terminal-phase review-task
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sqlite reconcile-wave" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" wave-status --state-dir "$_sd"
  assert_stdout_contains "closed" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.execution.status'
  assert_stdout_contains "concluida" || return 1
}

# Paridade C1: a MESMA sequencia de operacoes produz o MESMO stdout sob os
# dois backends para current-id/wave-status.
scenario_sqlite_paridade_current_id_wave_status_com_backend_json() {
  _sd_json="$TMPDIR_TEST/parity-json-ondas"
  capture "$RW" init --state-dir "$_sd_json" --execucao-id "exec-parity" \
    --projeto-alvo-path "/tmp/p" --descricao "POC paridade ondas"
  capture "$SCRIPT" start --state-dir "$_sd_json"
  capture "$SCRIPT" tool-call-tick --state-dir "$_sd_json"
  capture "$SCRIPT" end --state-dir "$_sd_json" --motivo-termino etapa_concluida_avancando
  capture "$SCRIPT" current-id --state-dir "$_sd_json"
  _json_id="$_CAPTURED_STDOUT"
  capture "$SCRIPT" wave-status --state-dir "$_sd_json"
  _json_status="$_CAPTURED_STDOUT"

  _sd_db="$TMPDIR_TEST/parity-sqlite-ondas"
  _seed_sqlite_backend "$_sd_db" || return 1
  capture "$SCRIPT" start --state-dir "$_sd_db"
  capture "$SCRIPT" tool-call-tick --state-dir "$_sd_db"
  capture "$SCRIPT" end --state-dir "$_sd_db" --motivo-termino etapa_concluida_avancando
  capture "$SCRIPT" current-id --state-dir "$_sd_db"
  _db_id="$_CAPTURED_STDOUT"
  capture "$SCRIPT" wave-status --state-dir "$_sd_db"
  _db_status="$_CAPTURED_STDOUT"

  [ "$_json_id" = "$_db_id" ] || { _fail "paridade current-id" "json='$_json_id' sqlite='$_db_id'"; return 1; }
  [ "$_json_status" = "$_db_status" ] || { _fail "paridade wave-status" "json='$_json_status' sqlite='$_db_status'"; return 1; }
}

# Task 4.1.1/4.2.2 (FASE 4): branch de selecao de backend explicito por C2 —
# um state.json coexistente e export/legado, NUNCA consultado como fonte.
# Prova positiva: onda aberta no state.db ("open") com state.json divergente
# (0 waves => "none" se fosse lido por engano) — wave-status deve refletir
# sempre o state.db.
scenario_c2_state_json_coexistente_ignorado_quando_state_db_presente() {
  _sd="$TMPDIR_TEST/c2-coexist-ondas"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" start --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "c2: start sqlite" "$_CAPTURED_STDERR"; return 1; }

  # state.json divergente no MESMO diretorio (0 waves => "none" se lido).
  printf '{"waves":[]}\n' > "$_sd/state.json"

  capture "$SCRIPT" wave-status --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "c2 wave-status exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "open" \
    || { _fail "c2: wave-status deveria refletir state.db (open), nao o state.json coexistente" "obtido $_CAPTURED_STDOUT"; return 1; }

  # state.json coexistente permanece intocado.
  _stale_now=$(cat "$_sd/state.json")
  [ "$_stale_now" = '{"waves":[]}' ] \
    || { _fail "c2: state.json coexistente foi modificado" "obtido: $_stale_now"; return 1; }
}

# ---- Motivo da ausencia OTel sob backend SQLite (paridade C1) ----
#
# Equivalente da chave achatada do path JSON: sob SQLite o motivo vai para
# o catch-all `extra_fields`, que a view materializa como
# `.waves[i].extra_fields`.

scenario_sqlite_end_otel_absent_reason_exporter_trocou() {
  _sd="$TMPDIR_TEST/sqlite-otel-reason"
  _seed_sqlite_backend "$_sd" || return 1
  _fx="$TMPDIR_TEST/otel-sqlite-troca.txt"
  CSTK_OTEL_ENDPOINT="file://$_fx"; export CSTK_OTEL_ENDPOINT

  _otel_fixture_sess "$_fx" "sess-antiga" 1.0
  capture "$SCRIPT" start --state-dir "$_sd"
  _otel_fixture_sess "$_fx" "sess-nova" 0.2
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando
  _e=$_CAPTURED_EXIT; _err=$_CAPTURED_STDERR
  unset CSTK_OTEL_ENDPOINT
  [ "$_e" = 0 ] || { _fail "sqlite end" "$_err"; return 1; }

  _reason=$(sqlite3 "$_sd/state.db" \
    "SELECT json_extract(extra_fields,'\$.otel_absent_reason') FROM wave WHERE seq=1;")
  [ "$_reason" = "exporter-trocou" ] \
    || { _fail "extra_fields" "esperado exporter-trocou em extra_fields, obtido '$_reason'"; return 1; }
  _otel=$(sqlite3 "$_sd/state.db" "SELECT coalesce(otel_usage,'null') FROM wave WHERE seq=1;")
  [ "$_otel" = "null" ] || { _fail "otel_usage" "esperado NULL, obtido '$_otel'"; return 1; }
  return 0
}

# MERGE, nunca overwrite: `extra_fields` e catch-all compartilhado (ex.:
# touched_key_aspects). Gravar o motivo NAO pode apagar o vizinho.
scenario_sqlite_end_otel_reason_preserva_extra_fields() {
  _sd="$TMPDIR_TEST/sqlite-otel-merge"
  _seed_sqlite_backend "$_sd" || return 1
  _fx="$TMPDIR_TEST/otel-sqlite-merge.txt"
  CSTK_OTEL_ENDPOINT="file://$_fx"; export CSTK_OTEL_ENDPOINT

  _otel_fixture_sess "$_fx" "sess-antiga" 1.0
  capture "$SCRIPT" start --state-dir "$_sd"
  sqlite3 "$_sd/state.db" \
    "UPDATE wave SET extra_fields='{\"touched_key_aspects\":[\"auth\"]}' WHERE seq=1;" \
    || { unset CSTK_OTEL_ENDPOINT; _fail "fixture" "UPDATE extra_fields falhou"; return 1; }
  _otel_fixture_sess "$_fx" "sess-nova" 0.2
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando
  unset CSTK_OTEL_ENDPOINT

  _asp=$(sqlite3 "$_sd/state.db" \
    "SELECT json_extract(extra_fields,'\$.touched_key_aspects[0]') FROM wave WHERE seq=1;")
  [ "$_asp" = "auth" ] \
    || { _fail "merge" "extra_fields pre-existente foi sobrescrito (touched_key_aspects='$_asp')"; return 1; }
  _reason=$(sqlite3 "$_sd/state.db" \
    "SELECT json_extract(extra_fields,'\$.otel_absent_reason') FROM wave WHERE seq=1;")
  [ "$_reason" = "exporter-trocou" ] \
    || { _fail "merge" "motivo nao gravado junto do vizinho, obtido '$_reason'"; return 1; }
  return 0
}

fi # sqlite3 disponivel

run_all_scenarios
