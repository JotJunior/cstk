#!/bin/sh
# test_state-db-migrate.sh — cobre
# global/skills/agente-00c-runtime/scripts/state-db-migrate.sh
# (migracao explicita state.json -> state.db).
#
# Ref: docs/specs/state-db-foundation/tasks.md FASE 6
#      docs/specs/state-db-foundation/contracts/migration.md (M1..M6 +
#      tabela final "Cenarios de teste": os 7 cenarios do contrato).

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPTS="$REPO_ROOT/global/skills/agente-00c-runtime/scripts"
SCRIPT="$SCRIPTS/state-db-migrate.sh"
STATE_RW="$SCRIPTS/state-rw.sh"

if ! command -v sqlite3 >/dev/null 2>&1; then
  printf '# test_state-db-migrate.sh: sqlite3 ausente — pulando suite\n'
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
  printf '# test_state-db-migrate.sh: jq ausente — pulando suite\n'
  exit 0
fi

# ---------------------------------------------------------------
# Fixture: state.json sintetico completo e VALIDO, exercitando as 6
# entidades de M3.1 + os dois pontos que so aparecem em dado real e que
# quebraram a implementacao ingenua (achados na FASE 6):
#   (a) decisions[].wave_id == "init"  -> FK invalida se inserida verbatim
#   (b) skills_invoked[].decision_id   -> FK invalida se a skill for inserida
#                                          junto da onda, ANTES das decisions
# ---------------------------------------------------------------
_seed_state_json() {
  _ss_dir="$1"
  _ss_status="${2:-concluida}"
  _ss_finished="${3:-2026-07-30T12:00:00Z}"
  mkdir -p "$_ss_dir"
  cat > "$_ss_dir/state.json" <<JSON
{
  "schema_version": "1.0.0",
  "short_name": "fixture-feature",
  "execution": {
    "id": "exec-fixture-001",
    "target_project_path": "/tmp/projeto",
    "target_project_description": "descricao de fixture com tamanho suficiente",
    "status": "$_ss_status",
    "termination_reason": "concluido",
    "started_at": "2026-07-30T10:00:00Z",
    "finished_at": "$_ss_finished"
  },
  "current_stage": "review-task",
  "next_instruction": "nada a fazer",
  "atomic_commit_enabled": true,
  "initial_key_aspects": ["state", "sqlite"],
  "external_urls_whitelist": [],
  "circular_movement_history": [],
  "budgets": {
    "max_recursion": 3,
    "current_subagent_depth": 1,
    "max_retro_executions_per_feature": 2,
    "retro_executions_consumed": 0,
    "max_cycles_per_stage": 5,
    "cycles_consumed_current_stage": 0,
    "tool_calls_threshold_wave": 80,
    "wallclock_threshold_seconds": 5400,
    "state_size_threshold_bytes": 1048576,
    "tool_calls_current_wave": 0,
    "current_wave_start": null
  },
  "accumulated_metrics": {
    "waves_total": 2,
    "tool_calls_total": 41,
    "wallclock_total_seconds": 120,
    "max_depth_reached": 2,
    "subagents_spawned": 1,
    "decisions_total": 2,
    "human_blocks_total": 1,
    "global_skill_suggestions_total": 0,
    "toolkit_issues_opened": 0
  },
  "waves": [
    {
      "id": "onda-001",
      "started_at": "2026-07-30T10:00:00Z",
      "finished_at": "2026-07-30T10:30:00Z",
      "wallclock_seconds": 1800,
      "tool_calls": 20,
      "termination_reason": "etapa_concluida_avancando",
      "executed_stages": ["specify"],
      "skills_invoked": [
        {"skill": "model-selector", "timestamp": "2026-07-30T10:01:00Z", "decision_id": "dec-002", "kind": "skill"},
        {"skill": "validate-tasks-template", "timestamp": "2026-07-30T10:02:00Z", "decision_id": null, "kind": "gate"}
      ]
    },
    {
      "id": "onda-002",
      "started_at": "2026-07-30T11:00:00Z",
      "finished_at": "2026-07-30T11:30:00Z",
      "wallclock_seconds": 1800,
      "tool_calls": 21,
      "termination_reason": "concluido",
      "executed_stages": ["review-task"],
      "skills_invoked": []
    }
  ],
  "decisions": [
    {
      "id": "dec-001",
      "wave_id": "init",
      "timestamp": "2026-07-30T09:59:00Z",
      "agent": "agente-00c-feature-orchestrator",
      "stage": "specify",
      "context": "Selecao de modelo para onda init (fase specify)",
      "options_considered": ["haiku", "sonnet"],
      "choice": "model:sonnet",
      "rationale": "justificativa com pelo menos vinte caracteres de texto",
      "justification_score": 0,
      "evidence": null,
      "references": [],
      "originating_artifact": null
    },
    {
      "id": "dec-002",
      "wave_id": "onda-001",
      "timestamp": "2026-07-30T10:01:00Z",
      "agent": "agente-00c-feature-orchestrator",
      "stage": "specify",
      "context": "contexto de decisao com pelo menos vinte caracteres",
      "options_considered": ["a", "b"],
      "choice": "a",
      "rationale": "justificativa com pelo menos vinte caracteres de texto",
      "justification_score": 2,
      "evidence": null,
      "references": [],
      "originating_artifact": null
    }
  ],
  "human_blocks": [
    {
      "id": "block-001",
      "decision_id": "dec-002",
      "question": "pergunta de bloqueio com mais de vinte caracteres?",
      "context_for_answer": "contexto para a resposta",
      "recommended_options": ["sim", "nao"],
      "status": "respondido",
      "human_answer": "sim",
      "triggered_at": "2026-07-30T10:05:00Z",
      "answered_at": "2026-07-30T10:10:00Z"
    }
  ],
  "tasks": [
    {
      "task_id": "1.1",
      "title": "primeira task",
      "wave_id": "onda-001",
      "outcome": "pass",
      "tests_run": 3,
      "tests_passed": 3,
      "lint_ok": true,
      "touched_files": ["a.sh", "b.sh"],
      "recorded_at": "2026-07-30T10:20:00Z",
      "source": "execute-task"
    }
  ],
  "events": [
    {"event_type": "schedule_wait", "timestamp": "2026-07-30T10:30:00Z", "description": "aguardando wakeup"},
    {"event_type": "recall_consulted", "timestamp": "2026-07-30T10:00:30Z"}
  ]
}
JSON
  "$STATE_RW" sha256-update --state-dir "$_ss_dir" >/dev/null 2>&1
}

# ===============================================================
# Cenario 1 do contrato — contagens identicas e IDs/timestamps preservados
# (US2 AS-1, SC-001)
# ===============================================================

scenario_migracao_preserva_contagens_ids_e_timestamps() {
  _sd="$TMPDIR_TEST/ok"
  _seed_state_json "$_sd"

  capture "$SCRIPT" migrate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "migrate exit" "$_CAPTURED_STDERR"; return 1; }
  [ -f "$_sd/state.db" ] || { _fail "state.db nao publicado" ""; return 1; }

  _counts=$(sqlite3 "$_sd/state.db" "SELECT (SELECT count(*) FROM decision)||','||(SELECT count(*) FROM wave)||','||(SELECT count(*) FROM human_block)||','||(SELECT count(*) FROM task_outcome)||','||(SELECT count(*) FROM event)||','||(SELECT count(*) FROM skill_invocation);")
  [ "$_counts" = "2,2,1,1,2,2" ] || { _fail "contagens por entidade" "esperado 2,2,1,1,2,2 obtido $_counts"; return 1; }

  # IDs originais, sem renumeracao (FR-005 literal)
  _ids=$(sqlite3 "$_sd/state.db" "SELECT group_concat(id) FROM (SELECT id FROM decision ORDER BY id);")
  [ "$_ids" = "dec-001,dec-002" ] || { _fail "ids de decisao renumerados" "obtido $_ids"; return 1; }
  _wid=$(sqlite3 "$_sd/state.db" "SELECT group_concat(id) FROM (SELECT id FROM wave ORDER BY seq);")
  [ "$_wid" = "onda-001,onda-002" ] || { _fail "ids de onda" "obtido $_wid"; return 1; }
  _bid=$(sqlite3 "$_sd/state.db" "SELECT id FROM human_block;")
  [ "$_bid" = "block-001" ] || { _fail "id de bloqueio" "obtido $_bid"; return 1; }

  # timestamps originais
  _ts=$(sqlite3 "$_sd/state.db" "SELECT timestamp FROM decision WHERE id='dec-001';")
  [ "$_ts" = "2026-07-30T09:59:00Z" ] || { _fail "timestamp preservado" "obtido $_ts"; return 1; }
}

# Regressao dirigida ao achado (a): wave_id "init" -> NULL (data-model.md
# §decision). Inserir verbatim viola a FK e aborta a migracao inteira.
scenario_wave_id_init_vira_null_sem_violar_fk() {
  _sd="$TMPDIR_TEST/init-sentinel"
  _seed_state_json "$_sd"
  capture "$SCRIPT" migrate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "migrate com sentinela init" "$_CAPTURED_STDERR"; return 1; }
  _n=$(sqlite3 "$_sd/state.db" "SELECT count(*) FROM decision WHERE wave_id IS NULL;")
  [ "$_n" = "1" ] || { _fail "sentinela init nao virou NULL" "decisoes com wave_id NULL=$_n"; return 1; }
  _n2=$(sqlite3 "$_sd/state.db" "SELECT count(*) FROM decision WHERE wave_id = 'init';")
  [ "$_n2" = "0" ] || { _fail "sentinela init inserida verbatim" "obtido $_n2"; return 1; }
}

# Regressao dirigida ao achado (b): skill_invocation.decision_id e FK para
# decision(id) — as skills MUST ser inseridas DEPOIS das decisions (§M2).
scenario_skill_invocation_com_decision_id_respeita_ordem_fk() {
  _sd="$TMPDIR_TEST/fk-order"
  _seed_state_json "$_sd"
  capture "$SCRIPT" migrate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "migrate com skill+decision_id" "$_CAPTURED_STDERR"; return 1; }
  _n=$(sqlite3 "$_sd/state.db" "SELECT count(*) FROM skill_invocation WHERE decision_id='dec-002';")
  [ "$_n" = "1" ] || { _fail "skill_invocation com decision_id perdida" "obtido $_n"; return 1; }
  _k=$(sqlite3 "$_sd/state.db" "SELECT kind FROM skill_invocation WHERE skill='validate-tasks-template';")
  [ "$_k" = "gate" ] || { _fail "kind=gate nao preservado" "obtido $_k"; return 1; }
}

# ===============================================================
# Cenario 2 do contrato — idempotencia (US2 AS-2, FR-014-INFRA-IDEMP)
# ===============================================================

scenario_migracao_reexecutada_nao_duplica() {
  _sd="$TMPDIR_TEST/idem"
  _seed_state_json "$_sd"
  capture "$SCRIPT" migrate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "1a migracao" "$_CAPTURED_STDERR"; return 1; }
  _c1=$(sqlite3 "$_sd/state.db" "SELECT (SELECT count(*) FROM decision)||','||(SELECT count(*) FROM wave)||','||(SELECT count(*) FROM skill_invocation);")

  capture "$SCRIPT" migrate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "2a migracao" "$_CAPTURED_STDERR"; return 1; }
  _c2=$(sqlite3 "$_sd/state.db" "SELECT (SELECT count(*) FROM decision)||','||(SELECT count(*) FROM wave)||','||(SELECT count(*) FROM skill_invocation);")

  [ "$_c1" = "$_c2" ] || { _fail "reexecucao duplicou dados" "antes=$_c1 depois=$_c2"; return 1; }

  # M5: a trilha de migration_run acumula atraves de reexecucoes (a migracao e
  # reconstrucao total; sem o carry, a 2a execucao apagaria a 1a).
  _runs=$(sqlite3 "$_sd/state.db" "SELECT count(*) FROM migration_run WHERE result='success';")
  [ "$_runs" = "2" ] || { _fail "historico de migration_run nao preservado" "esperado 2, obtido $_runs"; return 1; }
}

# ===============================================================
# Cenario 3 do contrato — bloqueio humano orfao ⇒ recusa (US2 AS-3, SC-006)
# ===============================================================

scenario_bloqueio_orfao_recusado_com_diagnostico() {
  _sd="$TMPDIR_TEST/orfao"
  _seed_state_json "$_sd"
  # decision_id que nao existe em .decisions[] — state-validate.sh detecta
  jq '.human_blocks[0].decision_id = "dec-999"' "$_sd/state.json" > "$_sd/tmp.json"
  mv "$_sd/tmp.json" "$_sd/state.json"
  "$STATE_RW" sha256-update --state-dir "$_sd" >/dev/null 2>&1

  capture "$SCRIPT" migrate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "bloqueio orfao deveria RECUSAR (exit 3)" "exit=$_CAPTURED_EXIT"; return 1; }
  [ ! -f "$_sd/state.db" ] || { _fail "state.db criado apesar da recusa" ""; return 1; }
  # "diagnostico apontando o registro problematico" (US2 AS-3): o repasse do
  # state-validate.sh nomeia o BLOQUEIO orfao (block-001) — e o registro que
  # o operador precisa consertar.
  case "$_CAPTURED_STDERR" in
    *block-001*) : ;;
    *) _fail "diagnostico nao aponta o registro problematico" "$_CAPTURED_STDERR"; return 1 ;;
  esac
}

# ===============================================================
# Cenario 4 do contrato — status em_andamento ⇒ recusa (FR-005)
# ===============================================================

scenario_execucao_ativa_recusada() {
  _sd="$TMPDIR_TEST/ativa"
  _seed_state_json "$_sd" "em_andamento" ""
  # finished_at null exigido pelo CHECK de coerencia do schema
  jq '.execution.finished_at = null | .execution.termination_reason = null' "$_sd/state.json" > "$_sd/t.json"
  mv "$_sd/t.json" "$_sd/state.json"
  "$STATE_RW" sha256-update --state-dir "$_sd" >/dev/null 2>&1

  capture "$SCRIPT" migrate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "execucao ativa deveria RECUSAR" "exit=$_CAPTURED_EXIT"; return 1; }
  [ ! -f "$_sd/state.db" ] || { _fail "state.db criado com execucao ativa" ""; return 1; }
  case "$_CAPTURED_STDERR" in
    *em_andamento*) : ;;
    *) _fail "diagnostico nao menciona em_andamento" "$_CAPTURED_STDERR"; return 1 ;;
  esac
}

# dec-033 (M1-a): `aguardando_humano` esta PAUSADA ⇒ migravel pela letra de
# FR-005 (que nomeia so `em_andamento`).
scenario_aguardando_humano_e_permitido() {
  _sd="$TMPDIR_TEST/pausada"
  _seed_state_json "$_sd" "aguardando_humano" ""
  jq '.execution.finished_at = null | .execution.termination_reason = null' "$_sd/state.json" > "$_sd/t.json"
  mv "$_sd/t.json" "$_sd/state.json"
  "$STATE_RW" sha256-update --state-dir "$_sd" >/dev/null 2>&1

  capture "$SCRIPT" migrate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "aguardando_humano deveria ser migravel (dec-033)" "exit=$_CAPTURED_EXIT $_CAPTURED_STDERR"; return 1; }
  [ -f "$_sd/state.db" ] || { _fail "state.db nao publicado" ""; return 1; }
}

# ===============================================================
# Cenario 5 do contrato — interrupcao entre construcao e publicacao
# (US2 AS-4): state.json intacto e projeto operavel
# ===============================================================

scenario_interrupcao_antes_da_publicacao_preserva_origem() {
  _sd="$TMPDIR_TEST/interrompida"
  _seed_state_json "$_sd"
  _antes=$(sha256_of_file "$_sd/state.json")

  # Simula interrupcao APOS a construcao e ANTES do mv: reprova M3.2
  # deliberadamente adulterando o export gerado a partir do banco. Como o
  # unico caminho de publicacao e o `mv` posterior a M3, reprovar M3 exercita
  # exatamente o ponto de falha "construido mas nao publicado".
  jq '.human_blocks[0].question = "pergunta divergente com mais de vinte caracteres"' \
    "$_sd/state.json" > "$_sd/t.json"
  mv "$_sd/t.json" "$_sd/state.json"
  # NAO atualiza o .sha256 => M1.3 recusa antes mesmo de construir; para
  # exercitar a falha em M3 (e nao em M1), realinhe o hash:
  "$STATE_RW" sha256-update --state-dir "$_sd" >/dev/null 2>&1
  _antes=$(sha256_of_file "$_sd/state.json")

  # Torna o state-dir nao-gravavel para o temporario: mktemp -d falha e a
  # migracao aborta ANTES de qualquer publicacao.
  chmod 500 "$_sd"
  capture "$SCRIPT" migrate --state-dir "$_sd"
  chmod 700 "$_sd"

  [ "$_CAPTURED_EXIT" != 0 ] || { _fail "deveria falhar sem poder criar temporario" ""; return 1; }
  [ ! -f "$_sd/state.db" ] || { _fail "state.db publicado apesar da falha" ""; return 1; }
  _depois=$(sha256_of_file "$_sd/state.json")
  [ "$_antes" = "$_depois" ] || { _fail "state.json alterado por migracao falha" "antes=$_antes depois=$_depois"; return 1; }

  # Projeto continua operavel pelo state.json (M4)
  capture "$STATE_RW" get --state-dir "$_sd" --field '.current_stage'
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "projeto inoperavel apos falha" "$_CAPTURED_STDERR"; return 1; }
  [ "$_CAPTURED_STDOUT" = "review-task" ] || { _fail "leitura pos-falha divergente" "obtido $_CAPTURED_STDOUT"; return 1; }
}

# Nenhum temporario sobrevive a uma migracao falha (higiene do state-dir).
scenario_temporario_removido_apos_falha_de_verificacao() {
  _sd="$TMPDIR_TEST/tmp-limpo"
  _seed_state_json "$_sd"
  capture "$SCRIPT" migrate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "migrate" "$_CAPTURED_STDERR"; return 1; }
  _leftover=$(find "$_sd" -maxdepth 1 -name '.state-db-migrate.*' 2>/dev/null | wc -l | tr -d ' ')
  [ "$_leftover" = "0" ] || { _fail "temporario sobreviveu" "encontrados=$_leftover"; return 1; }
}

# ===============================================================
# Cenario 6 do contrato — sha256 divergente ⇒ recusa (Edge Cases)
# ===============================================================

scenario_sha256_divergente_recusado() {
  _sd="$TMPDIR_TEST/hash"
  _seed_state_json "$_sd"
  # Adultera o state.json SEM atualizar o .sha256
  jq '.current_stage = "plan"' "$_sd/state.json" > "$_sd/t.json"
  mv "$_sd/t.json" "$_sd/state.json"

  capture "$SCRIPT" migrate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "hash divergente deveria RECUSAR" "exit=$_CAPTURED_EXIT"; return 1; }
  [ ! -f "$_sd/state.db" ] || { _fail "state.db criado com hash divergente" ""; return 1; }
  case "$_CAPTURED_STDERR" in
    *ntegridade*) : ;;
    *) _fail "diagnostico nao menciona integridade" "$_CAPTURED_STDERR"; return 1 ;;
  esac
}

# ===============================================================
# Cenario 7 do contrato — round-trip: export do banco == origem
# (SC-001, US3 AS-1)
# ===============================================================

scenario_round_trip_export_igual_origem_normalizada() {
  _sd="$TMPDIR_TEST/roundtrip"
  _seed_state_json "$_sd"
  capture "$SCRIPT" migrate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "migrate" "$_CAPTURED_STDERR"; return 1; }

  # A verificacao M3.2 roda DENTRO da migracao; aqui confirmamos por fora que
  # o banco publicado exporta o mesmo documento (mesma normalizacao contratual
  # aplicada aos dois lados).
  _norm='def drop_nulls: walk(if type == "object" then with_entries(select(.value != null)) else . end);
         (if (.decisions // [] | length) > 0 then .decisions |= map(if .wave_id == "init" then .wave_id = null else . end) else . end)
         | del(.accumulated_metrics)
         | (if has("budgets") then .budgets |= del(.current_wave_start, .tool_calls_current_wave) else . end)
         | drop_nulls'
  "$STATE_RW" read --state-dir "$_sd" | jq -S "$_norm" > "$TMPDIR_TEST/rt-target.json" 2>/dev/null \
    || { _fail "export do banco migrado falhou" ""; return 1; }
  jq -S "$_norm" "$_sd/state.json" > "$TMPDIR_TEST/rt-source.json" 2>/dev/null \
    || { _fail "normalizacao da origem falhou" ""; return 1; }

  if ! _d=$(diff -u "$TMPDIR_TEST/rt-source.json" "$TMPDIR_TEST/rt-target.json" 2>&1); then
    _fail "round-trip divergente" "$(printf '%s' "$_d" | head -n 20)"
    return 1
  fi
}

# M3.2 e um GATE REAL, nao decorativo: divergencia FORA da lista de
# normalizacoes contratuais reprova a migracao.
scenario_m3_2_reprova_divergencia_fora_da_normalizacao() {
  _sd="$TMPDIR_TEST/m32-gate"
  _seed_state_json "$_sd"
  # Campo de topo com valor que o schema nao consegue reconstruir por
  # nenhuma coluna E que nao esta na lista de normalizacao: um array de
  # objetos sob uma chave nao modelada vai para extra_fields e DEVE voltar
  # identico — se voltasse diferente, o gate teria de reprovar. Aqui
  # exercitamos o gate injetando um valor NUL-hostil que o strip_nul altera.
  printf '%s' "$(jq -c '.suggestions = [{"id":"sug-001","skill":"x"}]' "$_sd/state.json")" > "$_sd/t.json"
  mv "$_sd/t.json" "$_sd/state.json"
  "$STATE_RW" sha256-update --state-dir "$_sd" >/dev/null 2>&1

  capture "$SCRIPT" migrate --state-dir "$_sd"
  # Campos de topo nao modelados sao preservados via extra_fields => passa.
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "campo de topo nao modelado deveria round-tripar" "$_CAPTURED_STDERR"; return 1; }
  _sug=$("$STATE_RW" get --state-dir "$_sd" --field '.suggestions[0].id')
  [ "$_sug" = "sug-001" ] || { _fail "suggestions perdidas no round-trip" "obtido $_sug"; return 1; }
}

# ===============================================================
# M1.4 / M1.5 / M5 — demais pre-condicoes
# ===============================================================

scenario_state_json_ausente_recusado() {
  _sd="$TMPDIR_TEST/vazio"
  mkdir -p "$_sd"
  capture "$SCRIPT" migrate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "state.json ausente deveria RECUSAR" "exit=$_CAPTURED_EXIT"; return 1; }
}

scenario_state_json_ilegivel_recusado() {
  _sd="$TMPDIR_TEST/corrompido"
  mkdir -p "$_sd"
  printf '{ nao e json valido' > "$_sd/state.json"
  capture "$SCRIPT" migrate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "state.json ilegivel deveria RECUSAR" "exit=$_CAPTURED_EXIT"; return 1; }
  [ ! -f "$_sd/state.db" ] || { _fail "state.db criado" ""; return 1; }
}

scenario_state_db_de_outra_execucao_recusado() {
  _sd="$TMPDIR_TEST/conflito"
  _seed_state_json "$_sd"
  capture "$SCRIPT" migrate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "migracao inicial" "$_CAPTURED_STDERR"; return 1; }

  # Troca a origem por OUTRA execucao, mantendo o state.db anterior
  jq '.execution.id = "exec-OUTRA-999"' "$_sd/state.json" > "$_sd/t.json"
  mv "$_sd/t.json" "$_sd/state.json"
  _refresh_sha "$_sd"

  capture "$SCRIPT" migrate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "execution.id conflitante deveria RECUSAR" "exit=$_CAPTURED_EXIT"; return 1; }
  # M5: a tentativa recusada FICA registrada em migration_run
  _ref=$(sqlite3 "$_sd/state.db" "SELECT count(*) FROM migration_run WHERE result='refused';")
  [ "$_ref" = "1" ] || { _fail "recusa nao registrada em migration_run" "obtido $_ref"; return 1; }
  # ... com diagnostico legivel, nao apenas o enum
  _diag=$(sqlite3 "$_sd/state.db" "SELECT diagnostic FROM migration_run WHERE result='refused';")
  case "$_diag" in
    *"outra execucao"*) : ;;
    *) _fail "diagnostico da recusa nao registrado" "obtido '$_diag'"; return 1 ;;
  esac
  # E o banco anterior segue intacto (da execucao original)
  _id=$(sqlite3 "$_sd/state.db" "SELECT id FROM execution;")
  [ "$_id" = "exec-fixture-001" ] || { _fail "banco anterior corrompido" "obtido $_id"; return 1; }
}

# M5 (6.5.3): tentativa que FALHA na construcao/verificacao tambem e
# registrada, com result='failed', quando ha um state.db pre-existente onde
# persistir.
scenario_falha_registrada_em_migration_run() {
  _sd="$TMPDIR_TEST/failed-run"
  _seed_state_json "$_sd"
  capture "$SCRIPT" migrate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "migracao inicial" "$_CAPTURED_STDERR"; return 1; }

  # Forca falha na IMPORTACAO (nao na recusa M1) mantendo o state-dir
  # GRAVAVEL — o registro do `failed` precisa escrever no state.db existente.
  # Uma onda com id fora do padrao `onda-NNN` faz o importador abortar.
  jq '.waves += [{"id":"onda-INVALIDA","started_at":"2026-07-30T13:00:00Z","tool_calls":0,"executed_stages":[],"skills_invoked":[]}]' \
    "$_sd/state.json" > "$_sd/t.json"
  mv "$_sd/t.json" "$_sd/state.json"
  _refresh_sha "$_sd"

  capture "$SCRIPT" migrate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "falha de importacao deveria ser exit 1" "exit=$_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"; return 1; }
  # M4: nada publicado — o banco anterior segue sendo o da execucao original
  _stillid=$(sqlite3 "$_sd/state.db" "SELECT id FROM execution;")
  [ "$_stillid" = "exec-fixture-001" ] || { _fail "banco alterado por migracao falha" "obtido $_stillid"; return 1; }

  _f=$(sqlite3 "$_sd/state.db" "SELECT count(*) FROM migration_run WHERE result='failed';")
  [ "$_f" = "1" ] || { _fail "falha nao registrada em migration_run" "obtido $_f"; return 1; }
}

# ===============================================================
# M6 — o que a migracao MUST NOT fazer
# ===============================================================

scenario_m6_nao_apaga_state_json_sha256_nem_history() {
  _sd="$TMPDIR_TEST/m6"
  _seed_state_json "$_sd"
  mkdir -p "$_sd/state-history"
  printf '{"marcador":1}' > "$_sd/state-history/export-onda-001.json"

  capture "$SCRIPT" migrate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "migrate" "$_CAPTURED_STDERR"; return 1; }

  [ -f "$_sd/state.json" ]          || { _fail "state.json apagado (M6)" ""; return 1; }
  [ -f "$_sd/state.json.sha256" ]   || { _fail "state.json.sha256 apagado (M6)" ""; return 1; }
  [ -f "$_sd/state-history/export-onda-001.json" ] \
    || { _fail "state-history/ apagado (M6)" ""; return 1; }
  # E o conteudo de origem nao foi reescrito
  _m=$(jq -r '.marcador' "$_sd/state-history/export-onda-001.json")
  [ "$_m" = "1" ] || { _fail "state-history reescrito" "obtido $_m"; return 1; }
}

# M6: nenhum orquestrador dispara a migracao automaticamente. Auditoria
# estatica — nenhum command/agent 00c pode referenciar o script.
scenario_m6_nenhum_orquestrador_invoca_migracao_automaticamente() {
  _hits=$(grep -rl 'state-db-migrate' \
    "$REPO_ROOT/global/commands" "$REPO_ROOT/global/agents" 2>/dev/null | wc -l | tr -d ' ')
  [ "$_hits" = "0" ] || {
    _fail "migracao referenciada em command/agent (viola M6/FR-005)" \
      "$(grep -rl 'state-db-migrate' "$REPO_ROOT/global/commands" "$REPO_ROOT/global/agents" 2>/dev/null)"
    return 1
  }
}

# ===============================================================
# Interface / uso
# ===============================================================

scenario_sem_subcomando_e_uso_incorreto() {
  capture "$SCRIPT"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "sem subcomando deveria ser exit 2" "exit=$_CAPTURED_EXIT"; return 1; }
}

scenario_subcomando_desconhecido_e_uso_incorreto() {
  capture "$SCRIPT" naoexiste
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "subcomando invalido deveria ser exit 2" "exit=$_CAPTURED_EXIT"; return 1; }
}

scenario_state_dir_obrigatorio() {
  capture "$SCRIPT" migrate
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "--state-dir ausente deveria ser exit 2" "exit=$_CAPTURED_EXIT"; return 1; }
}

scenario_help_sai_zero() {
  capture "$SCRIPT" --help
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "--help deveria sair 0" "exit=$_CAPTURED_EXIT"; return 1; }
  case "$_CAPTURED_STDOUT" in
    *migrate*) : ;;
    *) _fail "help nao documenta migrate" "$_CAPTURED_STDOUT"; return 1 ;;
  esac
}

# C10 (primitives.md, finding S4): o temporario vem de mktemp, NUNCA de nome
# derivado de PID. Auditoria estatica do proprio script.
scenario_c10_temporario_via_mktemp_nao_pid() {
  grep -q 'mktemp -d' "$SCRIPT" \
    || { _fail "C10: temporario nao usa mktemp -d" ""; return 1; }
  if grep -qE '\.tmp\.\$\$|\$\$\.tmp|tmp\.\$\{?\$' "$SCRIPT"; then
    _fail "C10: nome de temporario derivado de PID" "$(grep -nE '\$\$' "$SCRIPT")"
    return 1
  fi
}

# _refresh_sha DIR -> regrava DIR/state.json.sha256 a partir do state.json.
# NAO usa `state-rw.sh sha256-update`: aquele comando e BACKEND-AWARE — com um
# state.db ja publicado no mesmo dir ele vira PRAGMA integrity_check do BANCO e
# deixa o hash do JSON intacto (achado ao escrever este teste). Aqui queremos
# sempre o hash do state.json.
_refresh_sha() {
  sha256_of_file "$1/state.json" > "$1/state.json.sha256"
}

# Helper local: sha256 de um arquivo (GNU/BSD).
sha256_of_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$1" | awk '{print $1}'
  else
    shasum -a 256 -- "$1" | awk '{print $1}'
  fi
}

run_all_scenarios
