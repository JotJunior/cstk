#!/bin/sh
# _state-rw-db.sh — implementacao do backend SQLite para state-rw.sh
# (feature state-db-foundation, FASE 3 task 3.2).
#
# Ref: docs/specs/state-db-foundation/tasks.md FASE 3, task 3.2
#      docs/specs/state-db-foundation/contracts/primitives.md §C1 C2 C7
#      docs/specs/state-db-foundation/contracts/export.md
#      docs/specs/state-db-foundation/data-model.md
#
# NAO e executavel diretamente. Sourced por state-rw.sh (que ja fez
# `. _state-db.sh` antes) — depende de sql_escape/strip_nul/_state_db_*.
#
# Escopo desta task: reconstrucao completa (read/get) e escrita (set/write)
# das 9 entidades JA modeladas em data-model.md. O export "oficial" (gatilho
# automatico ao fim da onda, E5/E6 do contrato) e FASE 5 — aqui o mecanismo
# de leitura ja fica funcionalmente completo porque FASE 5 o REUSA
# (contracts/export.md, Opcao A: "state-rw.sh read" vira o export).
#
# GAP CONHECIDO E DOCUMENTADO (nao um bug silencioso): contracts/export.md
# lista `suggestions`, `retros`, `next_retrospective_milestone` entre os
# campos que os demais scripts acrescentam ao longo da execucao, mas
# data-model.md fechou o schema em 9 entidades SEM tabela/coluna dedicada
# para eles. Ate uma FASE futura fechar esse gap (schema amendment), esses
# campos — e qualquer outro campo de TOPO nao modelado — sao preservados
# via o catch-all `execution.extra_fields` (JSON object), reconciliado de
# volta ao documento no `read`. Nenhum dado e perdido; apenas nao ganha
# tratamento relacional (sem FK/CHECK) enquanto o gap nao fecha.
#
# Fechamento parcial (state-db-runtime-parity, lote 2.4 / dec-052):
#   - `.suggestions` vive em extra_fields (catch-all) e os contadores
#     derivados `accumulated_metrics.global_skill_suggestions_total` /
#     `toolkit_issues_opened` sao computados NO read a partir dele
#     (nao mais hardcoded 0) — suggestions.sh nao precisa (nem pode)
#     gravar contador sob sqlite.
#   - `.accumulated_metrics.cache` (state-cache.sh metrics-bump) e o UNICO
#     path de accumulated_metrics gravavel via set: persiste em
#     extra_fields.cache_metrics (chave interna, nunca exposta no doc) e o
#     read remonta em .accumulated_metrics.cache.
#
# Funcoes expostas (todas exigem STATE_DIR ja resolvido para backend sqlite
# pelo caller — `_sr_backend` — e state.db existente):
#   _sr_db_file STATE_DIR                    -> imprime STATE_DIR/state.db
#   _sr_backend STATE_DIR                    -> imprime "sqlite" ou "json"
#   _sr_db_read STATE_DIR                    -> imprime o documento JSON completo
#   _sr_db_set STATE_DIR FIELD VALUE_JSON    -> aplica mutacao pontual
#   _sr_db_write_document STATE_DIR JSON     -> substitui/upserta a partir de
#                                                um documento completo
#   _sr_db_integrity_check STATE_DIR         -> exit 0 se 'ok', 1 senao (C7)

_sr_db_file() { printf '%s/state.db\n' "$1"; }

# _sr_backend STATE_DIR -> "sqlite" se state.db existe, senao "json" (C2).
_sr_backend() {
  if [ -f "$(_sr_db_file "$1")" ]; then
    printf 'sqlite\n'
  else
    printf 'json\n'
  fi
}

# ---------- Helpers de literal SQL (C8: strip_nul + sql_escape sempre) ----------

# _sr_sql_quote VALUE -> imprime 'valor-escapado' (nunca NULL; caller decide
# NULL separadamente quando aplicavel).
_sr_sql_quote() {
  _sq_v=$(printf '%s' "$1" | strip_nul)
  printf "'%s'" "$(sql_escape "$_sq_v")"
}

# _sr_sql_literal TYPE VALUE_JSON -> imprime o literal SQL correto para o
# TYPE (str|int|bool|json), a partir de um VALUE_JSON (JSON valido — o
# mesmo formato aceito por `--value`). JSON null -> SQL NULL em todo tipo.
_sr_sql_literal() {
  _sl_type="$1"
  _sl_json="$2"
  if [ "$(printf '%s' "$_sl_json" | jq -c 'if . == null then "y" else "n" end' 2>/dev/null)" = '"y"' ]; then
    printf 'NULL'
    return 0
  fi
  case "$_sl_type" in
    str)
      _sl_raw=$(printf '%s' "$_sl_json" | jq -r '.' 2>/dev/null) \
        || _sr_die "set: --value nao e JSON valido para campo texto" 1
      _sr_sql_quote "$_sl_raw"
      ;;
    int)
      printf '%s' "$_sl_json" | jq -e 'type == "number"' >/dev/null 2>&1 \
        || _sr_die "set: --value precisa ser numero para este campo" 1
      printf '%s' "$_sl_json" | jq -c '.'
      ;;
    bool)
      _sl_b=$(printf '%s' "$_sl_json" | jq -c '.' 2>/dev/null)
      case "$_sl_b" in
        true)  printf '1' ;;
        false) printf '0' ;;
        *) _sr_die "set: --value precisa ser true/false/null para este campo" 1 ;;
      esac
      ;;
    json)
      _sl_compact=$(printf '%s' "$_sl_json" | jq -c '.' 2>/dev/null) \
        || _sr_die "set: --value nao e JSON valido" 1
      _sr_sql_quote "$_sl_compact"
      ;;
    *)
      _sr_die "set: tipo interno desconhecido '$_sl_type'" 1
      ;;
  esac
}

_sr_exec_id() {
  _state_db_exec "$1" "SELECT id FROM execution LIMIT 1;"
}

# ---------- INSERT de execution para um documento NOVO (init, FASE 5) ----------
#
# feature state-backend-config, FASE 5 (task 5.1.3): `state-rw.sh init` sob
# effective_backend=sqlite cria state.db diretamente — NUNCA passa por
# state.json/migracao (research.md Decision 3: state-db-migrate.sh RECUSA
# .execution.status = em_andamento, que e exatamente o status que init
# sempre escreve; logo "init -> migrate" e estruturalmente impossivel).
#
# Espelha `_sdm_insert_execution` (state-db-migrate.sh) coluna-a-coluna —
# MESMA ordem, MESMAS 32 colunas — mas le de um DOC_FILE (o documento que
# `_sr_cmd_init` acabou de montar via jq) em vez do state.json de origem de
# uma migracao. SQL montado em shell (nao dentro do jq) pela mesma razao de
# `_sdm_insert_execution`: literal SQL simples-aspeado dentro de um script
# jq single-quoted no shell e fonte classica de quebra de quoting.

# _sr_ie_jq_raw DOC_FILE FILTER -> extrai texto ("" se null/ausente).
_sr_ie_jq_raw() { jq -r "$2 // empty" "$1" 2>/dev/null || printf ''; }
# _sr_ie_jq_json DOC_FILE FILTER -> extrai JSON compacto.
_sr_ie_jq_json() { jq -c "$2" "$1" 2>/dev/null || printf 'null'; }
# _sr_ie_jq_int DOC_FILE FILTER DEFAULT -> extrai inteiro (com default).
_sr_ie_jq_int() { jq -r "$2 // $3" "$1" 2>/dev/null || printf '%s' "$3"; }

# _sr_ie_lit_str VALUE -> literal SQL: NULL se vazio, senao 'valor-escapado'.
_sr_ie_lit_str() {
  if [ -z "$1" ]; then printf 'NULL'; else printf "'%s'" "$(printf '%s' "$1" | strip_nul | sed "s/'/''/g")"; fi
}
# _sr_ie_lit_json JSON -> literal SQL: NULL se vazio/`null`, senao 'json'.
_sr_ie_lit_json() {
  if [ -z "$1" ] || [ "$1" = "null" ]; then printf 'NULL'; else
    printf "'%s'" "$(printf '%s' "$1" | strip_nul | sed "s/'/''/g")"; fi
}

# _sr_db_insert_execution_from_doc_file DB DOC_FILE -> INSERT da linha unica
# de `execution`. Chamado UMA vez, em banco recem-criado (schema aplicado
# por state-db-schema.sh create) e sem execution ainda — diferente de
# `_sr_db_write_document`, que faz UPDATE assumindo a linha ja existente.
_sr_db_insert_execution_from_doc_file() {
  _ie_db="$1"; _ie_doc="$2"
  _ie_atomic=$(_sr_ie_jq_json "$_ie_doc" '.atomic_commit_enabled')
  _ie_atomic_sql="NULL"
  case "$_ie_atomic" in true) _ie_atomic_sql=1 ;; false) _ie_atomic_sql=0 ;; esac

  # roadmap-mode (feature roadmap-mode, contracts/cli-roadmap-mode.md §1):
  # sem coluna dedicada (research.md Decision 1) — pousa no catch-all
  # `extra_fields`, sempre com o booleano explicito (true OU false) para
  # espelhar o backend JSON, onde `.roadmap_mode_enabled` e sempre gravado
  # (nunca ausente). `_sr_db_read` faz merge de extra_fields no documento
  # (linha ~353), entao o campo reaparece no `read`/`get` identico aos dois
  # backends.
  _ie_roadmap=$(_sr_ie_jq_json "$_ie_doc" '.roadmap_mode_enabled')
  case "$_ie_roadmap" in true) : ;; *) _ie_roadmap="false" ;; esac

  # delivery-tier (feature delivery-tier, contracts/cli-delivery-tier.md §5):
  # mesmo padrao do roadmap-mode acima — sem coluna dedicada (research.md
  # Decision 1), pousa no MESMO catch-all `extra_fields`. Sem compor as DUAS
  # chaves aqui, o tier nao existiria no `init` sob SQLite (apenas apos um
  # `set` posterior), violando FR-002 ("gravado no init") EM SILENCIO. Default
  # cloud-public quando ausente/fora do enum (paridade com o default de
  # `state-rw.sh init`, que ja recusa token invalido antes de chegar aqui).
  _ie_delivery_tier=$(_sr_ie_jq_raw "$_ie_doc" '.delivery_tier')
  case "$_ie_delivery_tier" in
    local|internal-network|cloud-internal|cloud-public) : ;;
    *) _ie_delivery_tier="cloud-public" ;;
  esac
  _ie_extra_json=$(jq -cn --argjson v "$_ie_roadmap" --arg t "$_ie_delivery_tier" \
    '{roadmap_mode_enabled: $v, delivery_tier: $t}')

  _ie_sql="INSERT INTO execution (id,schema_version,short_name,target_project_path,\
target_project_description,suggested_stack,status,termination_reason,started_at,\
finished_at,canonical_project,session_name,current_stage,next_instruction,\
atomic_commit_enabled,initial_key_aspects,subagent_depth,max_recursion,\
cycles_consumed_current_stage,max_cycles_per_stage,retro_executions_consumed,\
max_retro_executions_per_feature,tool_calls_threshold_wave,\
wallclock_threshold_seconds,state_size_threshold_bytes,external_urls_whitelist,\
circular_movement_history,prerequisites,briefing_cache,constitution_cache,\
push_pr_result,extra_fields) VALUES ("
  _ie_sql="$_ie_sql$(_sr_ie_lit_str "$(_sr_ie_jq_raw "$_ie_doc" '.execution.id')"),"
  _ie_sql="$_ie_sql$(_sr_ie_lit_str "$(jq -r '.schema_version // "1.0.0"' "$_ie_doc" 2>/dev/null || printf '1.0.0')"),"
  _ie_sql="$_ie_sql$(_sr_ie_lit_str "$(_sr_ie_jq_raw "$_ie_doc" '.short_name')"),"
  _ie_sql="$_ie_sql$(_sr_ie_lit_str "$(_sr_ie_jq_raw "$_ie_doc" '.execution.target_project_path')"),"
  _ie_sql="$_ie_sql$(_sr_ie_lit_str "$(_sr_ie_jq_raw "$_ie_doc" '.execution.target_project_description')"),"
  _ie_sql="$_ie_sql$(_sr_ie_lit_json "$(_sr_ie_jq_json "$_ie_doc" '.execution.suggested_stack')"),"
  _ie_sql="$_ie_sql$(_sr_ie_lit_str "$(_sr_ie_jq_raw "$_ie_doc" '.execution.status')"),"
  _ie_sql="$_ie_sql$(_sr_ie_lit_str "$(_sr_ie_jq_raw "$_ie_doc" '.execution.termination_reason')"),"
  _ie_sql="$_ie_sql$(_sr_ie_lit_str "$(_sr_ie_jq_raw "$_ie_doc" '.execution.started_at')"),"
  _ie_sql="$_ie_sql$(_sr_ie_lit_str "$(_sr_ie_jq_raw "$_ie_doc" '.execution.finished_at')"),"
  _ie_sql="$_ie_sql$(_sr_ie_lit_str "$(_sr_ie_jq_raw "$_ie_doc" '.execution.canonical_project')"),"
  _ie_sql="$_ie_sql$(_sr_ie_lit_str "$(_sr_ie_jq_raw "$_ie_doc" '.execution.session_name')"),"
  _ie_sql="$_ie_sql$(_sr_ie_lit_str "$(_sr_ie_jq_raw "$_ie_doc" '.current_stage')"),"
  _ie_sql="$_ie_sql$(_sr_ie_lit_str "$(_sr_ie_jq_raw "$_ie_doc" '.next_instruction')"),"
  _ie_sql="$_ie_sql$_ie_atomic_sql,"
  _ie_sql="$_ie_sql$(_sr_ie_lit_json "$(_sr_ie_jq_json "$_ie_doc" '.initial_key_aspects // []')"),"
  _ie_sql="$_ie_sql$(_sr_ie_jq_int "$_ie_doc" '.budgets.current_subagent_depth' 1),"
  _ie_sql="$_ie_sql$(_sr_ie_jq_int "$_ie_doc" '.budgets.max_recursion' 3),"
  _ie_sql="$_ie_sql$(_sr_ie_jq_int "$_ie_doc" '.budgets.cycles_consumed_current_stage' 0),"
  _ie_sql="$_ie_sql$(_sr_ie_jq_int "$_ie_doc" '.budgets.max_cycles_per_stage' 5),"
  _ie_sql="$_ie_sql$(_sr_ie_jq_int "$_ie_doc" '.budgets.retro_executions_consumed' 0),"
  _ie_sql="$_ie_sql$(_sr_ie_jq_int "$_ie_doc" '.budgets.max_retro_executions_per_feature' 2),"
  _ie_sql="$_ie_sql$(_sr_ie_jq_int "$_ie_doc" '.budgets.tool_calls_threshold_wave' 80),"
  _ie_sql="$_ie_sql$(_sr_ie_jq_int "$_ie_doc" '.budgets.wallclock_threshold_seconds' 5400),"
  _ie_sql="$_ie_sql$(_sr_ie_jq_int "$_ie_doc" '.budgets.state_size_threshold_bytes' 1048576),"
  _ie_sql="$_ie_sql$(_sr_ie_lit_json "$(_sr_ie_jq_json "$_ie_doc" '.external_urls_whitelist // []')"),"
  _ie_sql="$_ie_sql$(_sr_ie_lit_json "$(_sr_ie_jq_json "$_ie_doc" '.circular_movement_history // []')"),"
  _ie_sql="$_ie_sql$(_sr_ie_lit_json "$(_sr_ie_jq_json "$_ie_doc" '.prerequisites')"),"
  _ie_sql="$_ie_sql$(_sr_ie_lit_json "$(_sr_ie_jq_json "$_ie_doc" '.briefing_cache')"),"
  _ie_sql="$_ie_sql$(_sr_ie_lit_json "$(_sr_ie_jq_json "$_ie_doc" '.constitution_cache')"),"
  _ie_sql="$_ie_sql$(_sr_ie_lit_json "$(_sr_ie_jq_json "$_ie_doc" '.push_pr_result')"),"
  _ie_sql="$_ie_sql$(_sr_ie_lit_json "$_ie_extra_json"));"

  _state_db_exec_with_retry "$_ie_db" "$_ie_sql" >/dev/null 2>&1 || return 1
  return 0
}

# ---------- C7: sha256-update/sha256-verify sob backend SQLite ----------

# _sr_db_integrity_check STATE_DIR -> exit 0 se PRAGMA integrity_check = 'ok'
# (dec-025: cobertura de adulteracao deliberada e integrity_check apenas,
# regresso aceito face ao sha256-verify anterior — operador local confiavel).
_sr_db_integrity_check() {
  _dbic_db=$(_sr_db_file "$1")
  [ -f "$_dbic_db" ] || _sr_die "sha256-verify: state.db ausente em $1" 1
  _dbic_out=$(_state_db_exec "$_dbic_db" "PRAGMA integrity_check;" 2>&1) \
    || { printf '%s\n' "$_dbic_out" >&2; return 1; }
  if [ "$_dbic_out" = "ok" ]; then
    return 0
  fi
  printf '%s: integrity_check divergente:\n%s\n' "$_SR_NAME" "$_dbic_out" >&2
  diag_emit error hash-mismatch "sha256-verify: PRAGMA integrity_check divergente sob backend SQLite" \
    "state.db pode estar corrompido — restaure a partir do export mais recente em state-history/" || :
  return 1
}

# ============================================================
# READ — reconstrucao completa do documento JSON (E1-E4 do
# contracts/export.md, consumido tambem por `get`)
# ============================================================

_sr_db_read() {
  _sdbr_sd="$1"
  _sdbr_db=$(_sr_db_file "$_sdbr_sd")
  [ -f "$_sdbr_db" ] || _sr_die "read: state.db ausente em $_sdbr_sd" 1

  _sdbr_sql="SELECT json_object(
    'schema_version', schema_version,
    'short_name', short_name,
    'execution', json_object(
      'id', id,
      'target_project_path', target_project_path,
      'target_project_description', target_project_description,
      'suggested_stack', json(coalesce(suggested_stack,'null')),
      'status', status,
      'termination_reason', termination_reason,
      'started_at', started_at,
      'finished_at', finished_at,
      'canonical_project', canonical_project,
      'session_name', session_name
    ),
    'prerequisites', json(coalesce(prerequisites,'null')),
    'current_stage', current_stage,
    'next_instruction', next_instruction,
    'waves', (SELECT coalesce(json_group_array(json_object(
        'id', w.id,
        'started_at', w.started_at,
        'finished_at', w.finished_at,
        'wallclock_seconds', w.wallclock_seconds,
        'tool_calls', w.tool_calls,
        'termination_reason', w.termination_reason,
        'next_wave_scheduled_for', w.next_wave_scheduled_for,
        'executed_stages', json(coalesce(w.executed_stages,'[]')),
        'skills_invoked', (SELECT coalesce(json_group_array(json_object(
            'skill', si.skill,
            'timestamp', si.timestamp,
            'decision_id', si.decision_id,
            'kind', si.kind
          )),'[]') FROM (SELECT * FROM skill_invocation WHERE wave_id = w.id ORDER BY id) si),
        'agent_usage', json(coalesce(w.agent_usage,'null')),
        'agent_spawns', json(coalesce(w.agent_spawns,'null')),
        'otel_usage', json(coalesce(w.otel_usage,'null')),
        'extra_fields', json(coalesce(w.extra_fields,'{}'))
      )),'[]') FROM (SELECT * FROM wave WHERE execution_id = execution.id ORDER BY seq) w),
    'decisions', (SELECT coalesce(json_group_array(json_object(
        'id', d.id,
        'wave_id', d.wave_id,
        'timestamp', d.timestamp,
        'agent', d.agent,
        'stage', d.stage,
        'context', d.context,
        'options_considered', json(d.options_considered),
        'choice', d.choice,
        'rationale', d.rationale,
        'justification_score', d.justification_score,
        'evidence', d.evidence,
        'references', json(coalesce(d.\"references\",'null')),
        'originating_artifact', d.originating_artifact
      )),'[]') FROM (SELECT * FROM decision WHERE execution_id = execution.id ORDER BY rowid) d),
    'human_blocks', (SELECT coalesce(json_group_array(json_object(
        'id', h.id,
        'decision_id', h.decision_id,
        'question', h.question,
        'context_for_answer', h.context_for_answer,
        'recommended_options', json(coalesce(h.recommended_options,'null')),
        'status', h.status,
        'human_answer', h.human_answer,
        'triggered_at', h.triggered_at,
        'answered_at', h.answered_at
      )),'[]') FROM (SELECT * FROM human_block WHERE execution_id = execution.id ORDER BY rowid) h),
    'budgets', json_object(
      'max_recursion', max_recursion,
      'current_subagent_depth', subagent_depth,
      'max_retro_executions_per_feature', max_retro_executions_per_feature,
      'retro_executions_consumed', retro_executions_consumed,
      'max_cycles_per_stage', max_cycles_per_stage,
      'cycles_consumed_current_stage', cycles_consumed_current_stage,
      'tool_calls_threshold_wave', tool_calls_threshold_wave,
      'wallclock_threshold_seconds', wallclock_threshold_seconds,
      'state_size_threshold_bytes', state_size_threshold_bytes,
      'tool_calls_current_wave', coalesce((SELECT tool_calls FROM wave WHERE execution_id = execution.id AND termination_reason IS NULL),0),
      'current_wave_start', (SELECT started_at FROM wave WHERE execution_id = execution.id AND termination_reason IS NULL)
    ),
    'accumulated_metrics', json_object(
      'waves_total', (SELECT count(*) FROM wave WHERE execution_id = execution.id),
      'tool_calls_total', coalesce((SELECT sum(tool_calls) FROM wave WHERE execution_id = execution.id),0),
      'wallclock_total_seconds', coalesce((SELECT sum(wallclock_seconds) FROM wave WHERE execution_id = execution.id),0),
      'max_depth_reached', subagent_depth,
      'subagents_spawned', 0,
      'decisions_total', (SELECT count(*) FROM decision WHERE execution_id = execution.id),
      'human_blocks_total', (SELECT count(*) FROM human_block WHERE execution_id = execution.id),
      'global_skill_suggestions_total', json_array_length(coalesce(json_extract(execution.extra_fields,'$.suggestions'),'[]')),
      'toolkit_issues_opened', (SELECT count(*) FROM json_each(coalesce(json_extract(execution.extra_fields,'$.suggestions'),'[]')) AS je WHERE json_extract(je.value,'$.issue_opened') IS NOT NULL),
      'cache', json(coalesce(json_extract(execution.extra_fields,'$.cache_metrics'),'null'))
    ),
    'external_urls_whitelist', json(coalesce(external_urls_whitelist,'[]')),
    'circular_movement_history', json(coalesce(circular_movement_history,'[]')),
    'initial_key_aspects', json(coalesce(initial_key_aspects,'[]')),
    'atomic_commit_enabled', json(CASE atomic_commit_enabled WHEN 1 THEN 'true' WHEN 0 THEN 'false' ELSE 'null' END),
    'tasks', (SELECT coalesce(json_group_array(json_object(
        'task_id', t.task_id,
        'title', t.title,
        'wave_id', t.wave_id,
        'outcome', t.outcome,
        'tests_run', t.tests_run,
        'tests_passed', t.tests_passed,
        'lint_ok', json(CASE t.lint_ok WHEN 1 THEN 'true' WHEN 0 THEN 'false' ELSE 'null' END),
        'touched_files', json(t.touched_files),
        'recorded_at', t.recorded_at,
        'source', t.source
      )),'[]') FROM (SELECT * FROM task_outcome WHERE execution_id = execution.id ORDER BY rowid) t),
    'events', (SELECT coalesce(json_group_array(json_object(
        'event_type', e.event_type,
        'timestamp', e.timestamp,
        'description', e.description
      )),'[]') FROM (SELECT * FROM event WHERE execution_id = execution.id ORDER BY id) e),
    'briefing_cache', json(coalesce(briefing_cache,'null')),
    'constitution_cache', json(coalesce(constitution_cache,'null')),
    'push_pr_result', json(coalesce(push_pr_result,'null')),
    'extra_fields', json(coalesce(extra_fields,'{}'))
  ) FROM execution LIMIT 1;"

  _sdbr_raw=$(_state_db_exec "$_sdbr_db" "$_sdbr_sql") || _sr_die "read: consulta SQLite falhou" 1
  [ -n "$_sdbr_raw" ] || _sr_die "read: tabela execution vazia em $_sdbr_db (banco corrompido?)" 1

  printf '%s\n' "$_sdbr_raw" | jq '
    def drop_null_keys(ks):
      reduce ks[] as $k (.; if (has($k) and .[$k] == null) then del(.[$k]) else . end);

    ((.extra_fields // {}) | del(.cache_metrics)) as $ext
    | (del(.extra_fields)) as $core
    | ($ext + $core)
    | drop_null_keys(["short_name"])
    | (if (has("short_name") | not) then del(.prerequisites) else . end)
    | .accumulated_metrics |= drop_null_keys(["cache"])
    | .execution |= drop_null_keys(["canonical_project","session_name"])
    | .waves |= map(
        ((.extra_fields // {})) as $we
        | (del(.extra_fields)) as $wc
        | ($we + $wc)
        | drop_null_keys(["agent_usage","agent_spawns","otel_usage"])
      )
    | .events |= map(drop_null_keys(["description"]))
  '
}

# ============================================================
# SET — mutacao pontual (dispatcher por classe de path)
# ============================================================

# _sr_exec_col_lookup BARE -> define _sr_lu_col/_sr_lu_type (vazios se
# BARE nao mapeia para nenhuma coluna conhecida de `execution`).
_sr_exec_col_lookup() {
  _lu=$1
  case "$_lu" in
    execution.*) _lu=${_lu#execution.} ;;
  esac
  _sr_lu_col=""
  _sr_lu_type=""
  case "$_lu" in
    id|schema_version|execution.id|execution.schema_version)
      _sr_die "set: campo '.$1' e imutavel apos init" 1 ;;
    short_name)                            _sr_lu_col=short_name; _sr_lu_type=str ;;
    current_stage)                         _sr_lu_col=current_stage; _sr_lu_type=str ;;
    next_instruction)                      _sr_lu_col=next_instruction; _sr_lu_type=str ;;
    atomic_commit_enabled)                 _sr_lu_col=atomic_commit_enabled; _sr_lu_type=bool ;;
    initial_key_aspects)                   _sr_lu_col=initial_key_aspects; _sr_lu_type=json ;;
    external_urls_whitelist)               _sr_lu_col=external_urls_whitelist; _sr_lu_type=json ;;
    circular_movement_history)             _sr_lu_col=circular_movement_history; _sr_lu_type=json ;;
    prerequisites)                         _sr_lu_col=prerequisites; _sr_lu_type=json ;;
    briefing_cache)                        _sr_lu_col=briefing_cache; _sr_lu_type=json ;;
    constitution_cache)                    _sr_lu_col=constitution_cache; _sr_lu_type=json ;;
    push_pr_result)                        _sr_lu_col=push_pr_result; _sr_lu_type=json ;;
    target_project_path)                   _sr_lu_col=target_project_path; _sr_lu_type=str ;;
    target_project_description)            _sr_lu_col=target_project_description; _sr_lu_type=str ;;
    suggested_stack)                       _sr_lu_col=suggested_stack; _sr_lu_type=json ;;
    status)                                _sr_lu_col=status; _sr_lu_type=str ;;
    termination_reason)                    _sr_lu_col=termination_reason; _sr_lu_type=str ;;
    started_at)                            _sr_lu_col=started_at; _sr_lu_type=str ;;
    finished_at)                           _sr_lu_col=finished_at; _sr_lu_type=str ;;
    canonical_project)                     _sr_lu_col=canonical_project; _sr_lu_type=str ;;
    session_name)                          _sr_lu_col=session_name; _sr_lu_type=str ;;
    budgets.current_subagent_depth)        _sr_lu_col=subagent_depth; _sr_lu_type=int ;;
    budgets.max_recursion)                 _sr_lu_col=max_recursion; _sr_lu_type=int ;;
    budgets.cycles_consumed_current_stage) _sr_lu_col=cycles_consumed_current_stage; _sr_lu_type=int ;;
    budgets.max_cycles_per_stage)          _sr_lu_col=max_cycles_per_stage; _sr_lu_type=int ;;
    budgets.retro_executions_consumed)     _sr_lu_col=retro_executions_consumed; _sr_lu_type=int ;;
    budgets.max_retro_executions_per_feature) _sr_lu_col=max_retro_executions_per_feature; _sr_lu_type=int ;;
    budgets.tool_calls_threshold_wave)     _sr_lu_col=tool_calls_threshold_wave; _sr_lu_type=int ;;
    budgets.wallclock_threshold_seconds)   _sr_lu_col=wallclock_threshold_seconds; _sr_lu_type=int ;;
    budgets.state_size_threshold_bytes)    _sr_lu_col=state_size_threshold_bytes; _sr_lu_type=int ;;
    budgets.tool_calls_current_wave|budgets.current_wave_start)
      _sr_die "set: campo '.$1' e derivado da onda aberta — nao gravavel diretamente sob backend SQLite" 1 ;;
    accumulated_metrics.*)
      _sr_die "set: campo '.$1' e derivado (accumulated_metrics) — nao gravavel sob backend SQLite (excecao: '.accumulated_metrics.cache' inteiro, tratado antes deste lookup)" 1 ;;
    *) : ;;
  esac
}

# _sr_db_wave_field_resolve DB BARE -> resolve "waves[-1].NAME"/"waves[N].NAME"
# em _sr_wfr_wave_id / _sr_wfr_name / _sr_wfr_col / _sr_wfr_type. col/type
# vazios = campo sem coluna dedicada (fallback extra_fields, decisao do
# caller). Read-only: faz apenas SELECTs; morre em path malformado/onda
# ausente ANTES de qualquer escrita.
_sr_db_wave_field_resolve() {
  _wfr_db="$1"; _wfr_bare="$2"
  _wfr_sel=${_wfr_bare#waves[}
  [ "$_wfr_sel" != "$_wfr_bare" ] || _sr_die "set: path de onda malformado: '.$_wfr_bare'" 1
  _wfr_idx=${_wfr_sel%%]*}
  _wfr_rest=${_wfr_sel#*].}
  [ "$_wfr_rest" != "$_wfr_sel" ] && [ -n "$_wfr_rest" ] \
    || _sr_die "set: path de onda malformado (esperado 'waves[N].campo'): '.$_wfr_bare'" 1
  # Suporta somente um segmento apos o indice — nesting mais profundo
  # (ex.: waves[-1].skills_invoked[0].skill) nao e usado hoje e cairia em
  # fallback ambiguo; falha explicita em vez de mesclar errado (C1/anti-fabricacao).
  case "$_wfr_rest" in
    *.*|*\[*) _sr_die "set: path de onda com aninhamento nao suportado sob backend SQLite: '.$_wfr_bare'" 1 ;;
  esac
  _sr_wfr_name="$_wfr_rest"

  if [ "$_wfr_idx" = "-1" ]; then
    _sr_wfr_wave_id=$(_state_db_exec "$_wfr_db" "SELECT id FROM wave ORDER BY seq DESC LIMIT 1;")
  else
    case "$_wfr_idx" in
      ''|*[!0-9]*) _sr_die "set: indice de onda invalido: '$_wfr_idx' (so -1 ou inteiro >= 0 suportado)" 1 ;;
    esac
    _wfr_seq=$((_wfr_idx + 1))
    _sr_wfr_wave_id=$(_state_db_exec "$_wfr_db" "SELECT id FROM wave WHERE seq = $_wfr_seq;")
  fi
  [ -n "$_sr_wfr_wave_id" ] || _sr_die "set: onda nao encontrada para '.$_wfr_bare'" 1

  _sr_wfr_col=""
  _sr_wfr_type=""
  case "$_sr_wfr_name" in
    finished_at)               _sr_wfr_col=finished_at; _sr_wfr_type=str ;;
    wallclock_seconds)         _sr_wfr_col=wallclock_seconds; _sr_wfr_type=int ;;
    tool_calls)                _sr_wfr_col=tool_calls; _sr_wfr_type=int ;;
    termination_reason)        _sr_wfr_col=termination_reason; _sr_wfr_type=str ;;
    next_wave_scheduled_for)   _sr_wfr_col=next_wave_scheduled_for; _sr_wfr_type=str ;;
    executed_stages)           _sr_wfr_col=executed_stages; _sr_wfr_type=json ;;
    agent_usage)                _sr_wfr_col=agent_usage; _sr_wfr_type=json ;;
    agent_spawns)               _sr_wfr_col=agent_spawns; _sr_wfr_type=json ;;
    otel_usage)                _sr_wfr_col=otel_usage; _sr_wfr_type=json ;;
    # Campos MODELADOS fora de wave.<coluna> — o fallback extra_fields seria
    # SOMBREADO pela reconstrucao real na leitura (skills_invoked vem da
    # tabela skill_invocation; id/started_at sao identidade da linha) e o
    # `set` reportaria "atualizado" sem efeito observavel (caso real:
    # sugestoes wp-intel/mcp-server-host sug-001, cstk/mcp-direct-transport
    # sug-002). Falhar alto, apontando o caminho certo — nunca sucesso falso.
    skills_invoked)
      _sr_die "set: '.$_wfr_bare' e derivado da tabela skill_invocation sob backend SQLite (extra_fields seria sombreado na leitura) — use 'state-ondas.sh record-skill' (ou 'state-rw.sh write' com o documento inteiro)" 1 ;;
    id|started_at)
      _sr_die "set: '.$_wfr_bare' e identidade da onda sob backend SQLite (imutavel via set) — use 'state-ondas.sh start' / 'state-rw.sh write'" 1 ;;
    *) : ;;
  esac
}

# _sr_db_set_wave_field DB BARE VALUE_JSON -> "waves[-1].NAME" ou "waves[N].NAME"
_sr_db_set_wave_field() {
  _wf_db="$1"; _wf_bare="$2"; _wf_value="$3"
  _sr_db_wave_field_resolve "$_wf_db" "$_wf_bare"

  if [ -n "$_sr_wfr_col" ]; then
    _wf_sqlval=$(_sr_sql_literal "$_sr_wfr_type" "$_wf_value")
    _wf_sql="UPDATE wave SET $_sr_wfr_col = $_wf_sqlval WHERE id = $(_sr_sql_quote "$_sr_wfr_wave_id");"
  else
    _wf_cur_extra=$(_state_db_exec "$_wf_db" "SELECT coalesce(extra_fields,'{}') FROM wave WHERE id = $(_sr_sql_quote "$_sr_wfr_wave_id");")
    _wf_new_extra=$(printf '%s' "$_wf_cur_extra" | jq -c --argjson v "$_wf_value" --arg n "$_sr_wfr_name" '.[$n] = $v') \
      || _sr_die "set: jq falhou ao mesclar campo de onda '$_sr_wfr_name'" 1
    _wf_sqlval=$(_sr_sql_literal json "$_wf_new_extra")
    _wf_sql="UPDATE wave SET extra_fields = $_wf_sqlval WHERE id = $(_sr_sql_quote "$_sr_wfr_wave_id");"
  fi
  _state_db_exec_with_retry "$_wf_db" "BEGIN IMMEDIATE; $_wf_sql COMMIT;" \
    || _sr_die "set: UPDATE wave.$_sr_wfr_name falhou" 1
}

# _sr_db_replace_events DB EXEC_ID ARRAY_JSON -> DELETE+INSERT (leaf table,
# sem FK de terceiros; seguro porque `event` nao e referenciada por ninguem).
_sr_db_replace_events() {
  _re_db="$1"; _re_exec_id="$2"; _re_arr="$3"
  _re_tmp=$(mktemp) || _sr_die "set: mktemp falhou" 1
  printf '%s' "$_re_arr" | jq -c '.[]' > "$_re_tmp" 2>/dev/null \
    || { rm -f -- "$_re_tmp"; _sr_die "set: --value de '.events' nao e array JSON valido" 1; }

  _re_sql="BEGIN IMMEDIATE; DELETE FROM event WHERE execution_id = $(_sr_sql_quote "$_re_exec_id");"
  while IFS= read -r _re_row; do
    _re_type=$(printf '%s' "$_re_row" | jq -r '.event_type')
    _re_ts=$(printf '%s' "$_re_row" | jq -r '.timestamp')
    _re_desc=$(printf '%s' "$_re_row" | jq -r '.description // empty')
    _re_desc_sql="NULL"
    [ -n "$_re_desc" ] && _re_desc_sql=$(_sr_sql_quote "$_re_desc")
    _re_sql="$_re_sql INSERT INTO event (execution_id,event_type,timestamp,description) VALUES ($(_sr_sql_quote "$_re_exec_id"),$(_sr_sql_quote "$_re_type"),$(_sr_sql_quote "$_re_ts"),$_re_desc_sql);"
  done < "$_re_tmp"
  rm -f -- "$_re_tmp"
  _re_sql="$_re_sql COMMIT;"
  _state_db_exec_with_retry "$_re_db" "$_re_sql" || _sr_die "set: resync de '.events' falhou" 1
}

# _sr_db_upsert_wave DB EXEC_ID WAVE_JSON [WITH_SKILLS] -> UPSERT de UMA onda
# + (por default) resync do seu skills_invoked (leaf table, seguro
# DELETE+INSERT por wave_id).
#
# WITH_SKILLS=no OMITE o bloco de skill_invocation, para o caller emiti-lo
# DEPOIS das decisions. Necessario porque skill_invocation.decision_id e FK
# para decision(id): emitir a skill junto da onda (ordem
# execution -> wave+skills -> decision) viola a FK sempre que a skill carrega
# decision_id — que e o caso normal do two-step register+record-skill do
# model-routing. A ordem correta e a do contracts/migration.md §M2:
# execution -> wave -> decision -> human_block/skill_invocation/task/event.
# Achado empiricamente na FASE 6 ao migrar state.json reais (os fixtures
# sinteticos da FASE 3 nao tinham skills_invoked com decision_id).
_sr_db_upsert_wave() {
  _uw_db="$1"; _uw_exec_id="$2"; _uw_row="$3"; _uw_with_skills="${4:-yes}"
  _uw_id=$(printf '%s' "$_uw_row" | jq -r '.id')
  _uw_seq=$(printf '%s' "$_uw_id" | sed -n 's/^onda-0*\([0-9][0-9]*\)$/\1/p')
  [ -n "$_uw_seq" ] || _sr_die "write: id de onda invalido (esperado 'onda-NNN'): '$_uw_id'" 1
  _uw_started=$(printf '%s' "$_uw_row" | jq -r '.started_at')
  _uw_finished=$(printf '%s' "$_uw_row" | jq -r '.finished_at // empty')
  _uw_wallclock=$(printf '%s' "$_uw_row" | jq -r '.wallclock_seconds // empty')
  _uw_toolcalls=$(printf '%s' "$_uw_row" | jq -r '.tool_calls // 0')
  _uw_term=$(printf '%s' "$_uw_row" | jq -r '.termination_reason // empty')
  _uw_nextsched=$(printf '%s' "$_uw_row" | jq -r '.next_wave_scheduled_for // empty')
  _uw_stages=$(printf '%s' "$_uw_row" | jq -c '.executed_stages // []')
  _uw_agent_usage=$(printf '%s' "$_uw_row" | jq -c '.agent_usage // null')
  _uw_agent_spawns=$(printf '%s' "$_uw_row" | jq -c '.agent_spawns // null')
  _uw_otel=$(printf '%s' "$_uw_row" | jq -c '.otel_usage // null')
  _uw_extra=$(printf '%s' "$_uw_row" | jq -c 'del(.id,.started_at,.finished_at,.wallclock_seconds,.tool_calls,.termination_reason,.next_wave_scheduled_for,.executed_stages,.skills_invoked,.agent_usage,.agent_spawns,.otel_usage,.extra_fields)')

  _uw_sql="INSERT INTO wave (id,execution_id,seq,started_at,finished_at,wallclock_seconds,tool_calls,termination_reason,next_wave_scheduled_for,executed_stages,agent_usage,agent_spawns,otel_usage,extra_fields) VALUES ("
  _uw_sql="$_uw_sql$(_sr_sql_quote "$_uw_id"),$(_sr_sql_quote "$_uw_exec_id"),$_uw_seq,$(_sr_sql_quote "$_uw_started"),"
  _uw_sql="$_uw_sql$([ -n "$_uw_finished" ] && _sr_sql_quote "$_uw_finished" || printf NULL),"
  _uw_sql="$_uw_sql$([ -n "$_uw_wallclock" ] && printf '%s' "$_uw_wallclock" || printf NULL),"
  _uw_sql="$_uw_sql$_uw_toolcalls,"
  _uw_sql="$_uw_sql$([ -n "$_uw_term" ] && _sr_sql_quote "$_uw_term" || printf NULL),"
  _uw_sql="$_uw_sql$([ -n "$_uw_nextsched" ] && _sr_sql_quote "$_uw_nextsched" || printf NULL),"
  _uw_sql="$_uw_sql$(_sr_sql_quote "$_uw_stages"),"
  _uw_sql="$_uw_sql$([ "$_uw_agent_usage" != "null" ] && _sr_sql_quote "$_uw_agent_usage" || printf NULL),"
  _uw_sql="$_uw_sql$([ "$_uw_agent_spawns" != "null" ] && _sr_sql_quote "$_uw_agent_spawns" || printf NULL),"
  _uw_sql="$_uw_sql$([ "$_uw_otel" != "null" ] && _sr_sql_quote "$_uw_otel" || printf NULL),"
  _uw_sql="$_uw_sql$(_sr_sql_quote "$_uw_extra")"
  _uw_sql="$_uw_sql) ON CONFLICT(id) DO UPDATE SET seq=excluded.seq, started_at=excluded.started_at, finished_at=excluded.finished_at, wallclock_seconds=excluded.wallclock_seconds, tool_calls=excluded.tool_calls, termination_reason=excluded.termination_reason, next_wave_scheduled_for=excluded.next_wave_scheduled_for, executed_stages=excluded.executed_stages, agent_usage=excluded.agent_usage, agent_spawns=excluded.agent_spawns, otel_usage=excluded.otel_usage, extra_fields=excluded.extra_fields;"
  printf '%s' "$_uw_sql"

  [ "$_uw_with_skills" = "no" ] && return 0
  _sr_db_wave_skills_sql "$_uw_row"
}

# _sr_db_wave_skills_sql WAVE_JSON -> imprime o resync (DELETE+INSERT) do
# skills_invoked de UMA onda. Separado de _sr_db_upsert_wave para permitir
# emissao APOS as decisions (FK skill_invocation.decision_id -> decision.id).
_sr_db_wave_skills_sql() {
  _ws_row="$1"
  _ws_id=$(printf '%s' "$_ws_row" | jq -r '.id')
  _ws_skills=$(printf '%s' "$_ws_row" | jq -c '.skills_invoked // []')
  printf ' DELETE FROM skill_invocation WHERE wave_id = %s;' "$(_sr_sql_quote "$_ws_id")"
  _ws_stmp=$(mktemp) || _sr_die "write: mktemp falhou" 1
  printf '%s' "$_ws_skills" | jq -c '.[]' > "$_ws_stmp" 2>/dev/null
  while IFS= read -r _ws_srow; do
    _ws_sk=$(printf '%s' "$_ws_srow" | jq -r '.skill')
    _ws_sts=$(printf '%s' "$_ws_srow" | jq -r '.timestamp')
    _ws_sdec=$(printf '%s' "$_ws_srow" | jq -r '.decision_id // empty')
    _ws_skind=$(printf '%s' "$_ws_srow" | jq -r '.kind // "skill"')
    printf ' INSERT INTO skill_invocation (wave_id,skill,timestamp,decision_id,kind) VALUES (%s,%s,%s,%s,%s);' \
      "$(_sr_sql_quote "$_ws_id")" "$(_sr_sql_quote "$_ws_sk")" "$(_sr_sql_quote "$_ws_sts")" \
      "$([ -n "$_ws_sdec" ] && _sr_sql_quote "$_ws_sdec" || printf NULL)" "$(_sr_sql_quote "$_ws_skind")"
  done < "$_ws_stmp"
  rm -f -- "$_ws_stmp"
}

_sr_db_upsert_decision() {
  _ud_exec_id="$1"; _ud_row="$2"
  _ud_id=$(printf '%s' "$_ud_row" | jq -r '.id')
  # wave_id sentinela "init" -> NULL (data-model.md §decision: `FK -> wave(id),
  # NULL p/ "init"`). Decisoes registradas pelo command PAI antes da primeira
  # onda (ex.: wave-select pre-onda) carregam wave_id="init", que nao e uma
  # onda real — inseri-lo verbatim viola a FK. Achado empiricamente na FASE 6:
  # 10 dos 19 state.json reais de .claude/feature-00c-state/ tem essa
  # sentinela.
  _ud_wid=$(printf '%s' "$_ud_row" | jq -r 'if (.wave_id // "") == "init" then "" else (.wave_id // empty) end')
  _ud_ts=$(printf '%s' "$_ud_row" | jq -r '.timestamp')
  _ud_agent=$(printf '%s' "$_ud_row" | jq -r '.agent')
  _ud_stage=$(printf '%s' "$_ud_row" | jq -r '.stage')
  _ud_ctx=$(printf '%s' "$_ud_row" | jq -r '.context')
  _ud_opts=$(printf '%s' "$_ud_row" | jq -c '.options_considered')
  _ud_choice=$(printf '%s' "$_ud_row" | jq -r '.choice')
  _ud_rat=$(printf '%s' "$_ud_row" | jq -r '.rationale')
  _ud_score=$(printf '%s' "$_ud_row" | jq -r '.justification_score // empty')
  _ud_evid=$(printf '%s' "$_ud_row" | jq -r '.evidence // empty')
  _ud_refs=$(printf '%s' "$_ud_row" | jq -c '.references // null')
  _ud_origin=$(printf '%s' "$_ud_row" | jq -r '.originating_artifact // empty')

  printf 'INSERT INTO decision (id,execution_id,wave_id,timestamp,agent,stage,context,options_considered,choice,rationale,justification_score,evidence,"references",originating_artifact) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) ON CONFLICT(id) DO UPDATE SET wave_id=excluded.wave_id, timestamp=excluded.timestamp, agent=excluded.agent, stage=excluded.stage, context=excluded.context, options_considered=excluded.options_considered, choice=excluded.choice, rationale=excluded.rationale, justification_score=excluded.justification_score, evidence=excluded.evidence, "references"=excluded."references", originating_artifact=excluded.originating_artifact;' \
    "$(_sr_sql_quote "$_ud_id")" \
    "$(_sr_sql_quote "$_ud_exec_id")" \
    "$([ -n "$_ud_wid" ] && _sr_sql_quote "$_ud_wid" || printf NULL)" \
    "$(_sr_sql_quote "$_ud_ts")" \
    "$(_sr_sql_quote "$_ud_agent")" \
    "$(_sr_sql_quote "$_ud_stage")" \
    "$(_sr_sql_quote "$_ud_ctx")" \
    "$(_sr_sql_quote "$_ud_opts")" \
    "$(_sr_sql_quote "$_ud_choice")" \
    "$(_sr_sql_quote "$_ud_rat")" \
    "$([ -n "$_ud_score" ] && printf '%s' "$_ud_score" || printf NULL)" \
    "$([ -n "$_ud_evid" ] && _sr_sql_quote "$_ud_evid" || printf NULL)" \
    "$(_sr_sql_quote "$_ud_refs")" \
    "$([ -n "$_ud_origin" ] && _sr_sql_quote "$_ud_origin" || printf NULL)"
}

_sr_db_upsert_human_block() {
  _uh_exec_id="$1"; _uh_row="$2"
  _uh_id=$(printf '%s' "$_uh_row" | jq -r '.id')
  _uh_decid=$(printf '%s' "$_uh_row" | jq -r '.decision_id')
  _uh_q=$(printf '%s' "$_uh_row" | jq -r '.question')
  _uh_ctx=$(printf '%s' "$_uh_row" | jq -r '.context_for_answer')
  _uh_rec=$(printf '%s' "$_uh_row" | jq -c '.recommended_options // null')
  _uh_status=$(printf '%s' "$_uh_row" | jq -r '.status')
  _uh_ans=$(printf '%s' "$_uh_row" | jq -r '.human_answer // empty')
  _uh_trig=$(printf '%s' "$_uh_row" | jq -r '.triggered_at')
  _uh_answ_at=$(printf '%s' "$_uh_row" | jq -r '.answered_at // empty')

  printf 'INSERT INTO human_block (id,execution_id,decision_id,question,context_for_answer,recommended_options,status,human_answer,triggered_at,answered_at) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) ON CONFLICT(id) DO UPDATE SET decision_id=excluded.decision_id, question=excluded.question, context_for_answer=excluded.context_for_answer, recommended_options=excluded.recommended_options, status=excluded.status, human_answer=excluded.human_answer, triggered_at=excluded.triggered_at, answered_at=excluded.answered_at;' \
    "$(_sr_sql_quote "$_uh_id")" \
    "$(_sr_sql_quote "$_uh_exec_id")" \
    "$(_sr_sql_quote "$_uh_decid")" \
    "$(_sr_sql_quote "$_uh_q")" \
    "$(_sr_sql_quote "$_uh_ctx")" \
    "$(_sr_sql_quote "$_uh_rec")" \
    "$(_sr_sql_quote "$_uh_status")" \
    "$([ -n "$_uh_ans" ] && _sr_sql_quote "$_uh_ans" || printf NULL)" \
    "$(_sr_sql_quote "$_uh_trig")" \
    "$([ -n "$_uh_answ_at" ] && _sr_sql_quote "$_uh_answ_at" || printf NULL)"
}

_sr_db_upsert_task() {
  _ut_exec_id="$1"; _ut_row="$2"
  _ut_tid=$(printf '%s' "$_ut_row" | jq -r '.task_id')
  _ut_title=$(printf '%s' "$_ut_row" | jq -r '.title // ""')
  _ut_wid=$(printf '%s' "$_ut_row" | jq -r '.wave_id')
  _ut_outcome=$(printf '%s' "$_ut_row" | jq -r '.outcome')
  _ut_tr=$(printf '%s' "$_ut_row" | jq -r '.tests_run // 0')
  _ut_tp=$(printf '%s' "$_ut_row" | jq -r '.tests_passed // 0')
  # SEM `// null` (mesma classe de bug de .atomic_commit_enabled acima):
  # jq trata `false` como falsy, entao `.lint_ok // null` perderia um
  # lint_ok=false real. Chave ausente ja produz `null` sem o `//`.
  _ut_lint=$(printf '%s' "$_ut_row" | jq -c '.lint_ok')
  _ut_files=$(printf '%s' "$_ut_row" | jq -c '.touched_files // []')
  _ut_rec=$(printf '%s' "$_ut_row" | jq -r '.recorded_at')
  _ut_src=$(printf '%s' "$_ut_row" | jq -r '.source // empty')
  _ut_lint_sql="NULL"
  case "$_ut_lint" in true) _ut_lint_sql=1 ;; false) _ut_lint_sql=0 ;; esac

  printf 'INSERT INTO task_outcome (execution_id,task_id,title,wave_id,outcome,tests_run,tests_passed,lint_ok,touched_files,recorded_at,source) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) ON CONFLICT(execution_id,task_id) DO UPDATE SET title=excluded.title, wave_id=excluded.wave_id, outcome=excluded.outcome, tests_run=excluded.tests_run, tests_passed=excluded.tests_passed, lint_ok=excluded.lint_ok, touched_files=excluded.touched_files, recorded_at=excluded.recorded_at, source=excluded.source;' \
    "$(_sr_sql_quote "$_ut_exec_id")" \
    "$(_sr_sql_quote "$_ut_tid")" \
    "$(_sr_sql_quote "$_ut_title")" \
    "$(_sr_sql_quote "$_ut_wid")" \
    "$(_sr_sql_quote "$_ut_outcome")" \
    "$_ut_tr" "$_ut_tp" "$_ut_lint_sql" \
    "$(_sr_sql_quote "$_ut_files")" \
    "$(_sr_sql_quote "$_ut_rec")" \
    "$([ -n "$_ut_src" ] && _sr_sql_quote "$_ut_src" || printf NULL)"
}

# _sr_db_set STATE_DIR FIELD VALUE_JSON -> dispatcher de `set` sob backend
# SQLite. FIELD e um path jq (ex.: '.events', '.waves[-1].tool_calls',
# '.current_stage', '.next_retrospective_milestone').
_sr_db_set() {
  _sds_sd="$1"; _sds_field="$2"; _sds_value="$3"
  _sds_db=$(_sr_db_file "$_sds_sd")
  [ -f "$_sds_db" ] || _sr_die "set: state.db ausente em $_sds_sd" 1
  _sds_exec_id=$(_sr_exec_id "$_sds_db")
  [ -n "$_sds_exec_id" ] || _sr_die "set: execution ausente em $_sds_db" 1
  _sds_bare=${_sds_field#.}

  case "$_sds_bare" in
    events)
      _sr_db_replace_events "$_sds_db" "$_sds_exec_id" "$_sds_value"
      ;;
    waves)
      _sds_tmp=$(mktemp) || _sr_die "set: mktemp falhou" 1
      printf '%s' "$_sds_value" | jq -c '.[]' > "$_sds_tmp" 2>/dev/null \
        || { rm -f -- "$_sds_tmp"; _sr_die "set: --value de '.waves' nao e array JSON valido" 1; }
      _sds_sql="BEGIN IMMEDIATE;"
      while IFS= read -r _sds_row; do
        _sds_sql="$_sds_sql $(_sr_db_upsert_wave "$_sds_db" "$_sds_exec_id" "$_sds_row")"
      done < "$_sds_tmp"
      rm -f -- "$_sds_tmp"
      _sds_sql="$_sds_sql COMMIT;"
      _state_db_exec_with_retry "$_sds_db" "$_sds_sql" || _sr_die "set: resync de '.waves' falhou" 1
      ;;
    decisions|human_blocks|tasks)
      _sds_tmp=$(mktemp) || _sr_die "set: mktemp falhou" 1
      printf '%s' "$_sds_value" | jq -c '.[]' > "$_sds_tmp" 2>/dev/null \
        || { rm -f -- "$_sds_tmp"; _sr_die "set: --value de '.$_sds_bare' nao e array JSON valido" 1; }
      _sds_sql="BEGIN IMMEDIATE;"
      while IFS= read -r _sds_row; do
        case "$_sds_bare" in
          decisions)    _sds_stmt=$(_sr_db_upsert_decision "$_sds_exec_id" "$_sds_row") ;;
          human_blocks) _sds_stmt=$(_sr_db_upsert_human_block "$_sds_exec_id" "$_sds_row") ;;
          tasks)        _sds_stmt=$(_sr_db_upsert_task "$_sds_exec_id" "$_sds_row") ;;
        esac
        _sds_sql="$_sds_sql $_sds_stmt"
      done < "$_sds_tmp"
      rm -f -- "$_sds_tmp"
      _sds_sql="$_sds_sql COMMIT;"
      _state_db_exec_with_retry "$_sds_db" "$_sds_sql" || _sr_die "set: resync de '.$_sds_bare' falhou" 1
      ;;
    waves\[*)
      _sr_db_set_wave_field "$_sds_db" "$_sds_bare" "$_sds_value"
      ;;
    accumulated_metrics.cache)
      # Metricas de cache (state-cache.sh metrics-bump — state-db-runtime-parity
      # 2.4.3): sem coluna dedicada no schema; persiste o objeto inteiro em
      # extra_fields.cache_metrics e o read remonta em .accumulated_metrics.cache
      # (drop se null). Demais paths accumulated_metrics.* seguem derivados
      # (die abaixo via _sr_exec_col_lookup).
      _sds_cur_extra=$(_state_db_exec "$_sds_db" "SELECT coalesce(extra_fields,'{}') FROM execution LIMIT 1;")
      _sds_new_extra=$(printf '%s' "$_sds_cur_extra" | jq -c --argjson v "$_sds_value" '.cache_metrics = $v') \
        || _sr_die "set: jq falhou ao aplicar cache_metrics em extra_fields" 1
      _sds_sqlval=$(_sr_sql_literal json "$_sds_new_extra")
      _state_db_exec_with_retry "$_sds_db" "BEGIN IMMEDIATE; UPDATE execution SET extra_fields = $_sds_sqlval; COMMIT;" \
        || _sr_die "set: UPDATE execution.extra_fields (cache_metrics) falhou" 1
      ;;
    *)
      _sr_exec_col_lookup "$_sds_bare"
      if [ -n "$_sr_lu_col" ]; then
        _sds_sqlval=$(_sr_sql_literal "$_sr_lu_type" "$_sds_value")
        _state_db_exec_with_retry "$_sds_db" "BEGIN IMMEDIATE; UPDATE execution SET $_sr_lu_col = $_sds_sqlval; COMMIT;" \
          || _sr_die "set: UPDATE execution.$_sr_lu_col falhou" 1
      else
        case "$_sds_bare" in
          *.*|*\[*)
            _sr_die "set: campo nao suportado sob backend SQLite (path aninhado nao modelado): '$_sds_field' — so campos de topo simples tem fallback para extra_fields" 1
            ;;
          execution|accumulated_metrics)
            # Objeto inteiro de um container MODELADO (colunas da tabela
            # execution / metricas derivadas): cair em extra_fields.execution
            # seria sombreado pela reconstrucao real na leitura — o `set`
            # reportaria sucesso e `.execution.status` continuaria o antigo
            # (caso real: sugestao wp-intel/mcp-server-host sug-003). Falhar
            # alto e apontar o caminho por campo.
            _sr_die "set: '$_sds_field' e um container modelado sob backend SQLite (extra_fields seria sombreado na leitura) — atualize campo a campo ('.execution.status', ...) ou use 'state-rw.sh write' com o documento inteiro" 1
            ;;
        esac
        _sds_cur_extra=$(_state_db_exec "$_sds_db" "SELECT coalesce(extra_fields,'{}') FROM execution LIMIT 1;")
        _sds_new_extra=$(printf '%s' "$_sds_cur_extra" | jq -c --argjson v "$_sds_value" "$_sds_field = \$v") \
          || _sr_die "set: jq falhou ao aplicar '$_sds_field' em extra_fields" 1
        _sds_sqlval=$(_sr_sql_literal json "$_sds_new_extra")
        _state_db_exec_with_retry "$_sds_db" "BEGIN IMMEDIATE; UPDATE execution SET extra_fields = $_sds_sqlval; COMMIT;" \
          || _sr_die "set: UPDATE execution.extra_fields falhou" 1
      fi
      ;;
  esac
}

# _sr_db_set_multi STATE_DIR PAIRS_JSON -> `set` multi-campo atomico sob
# backend SQLite (state-db-runtime-parity FR-005/FR-006).
# PAIRS_JSON = [{"f":".campo","v":<json>}, ...] (>= 2 pares; valores ja
# validados como JSON pelo caller `_sr_cmd_set`).
#
# Regras (contracts/runtime-interfaces.md §1):
# - classifica e valida TODOS os pares ANTES de qualquer escrita
#   (all-or-nothing: par invalido => die sem tocar o estado);
# - aplica tudo numa UNICA transacao BEGIN IMMEDIATE...COMMIT;
# - colunas de `execution` sao coalescidas num UNICO UPDATE multi-coluna, e
#   colunas de `wave` num UNICO UPDATE por onda: CHECKs do SQLite sao
#   avaliados POR STATEMENT, nao deferidos ao COMMIT (verificado
#   empiricamente: `BEGIN; UPDATE status; UPDATE finished_at; COMMIT` viola
#   C2 com exit 19, enquanto `UPDATE ... SET status=..., finished_at=...`
#   passa). E isso que habilita a promocao terminal canonica
#   (status+finished_at+termination_reason no mesmo set);
# - `SET col = a, col = b` e legal em SQLite e o ULTIMO vence (verificado
#   empiricamente) — o last-wins de `--field` duplicado (CHK009) sai da
#   propria ordem dos pares, sem dedup;
# - resyncs de array (.events/.waves/.decisions/.human_blocks/.tasks) e o
#   fallback extra_fields de campo de ONDA nao mapeado NAO sao suportados em
#   lote (o merge read-modify-write pre-transacao perderia updates entre
#   pares do mesmo lote); rejeicao explicita antes de qualquer escrita — o
#   set single-field dedicado continua cobrindo esses paths.
_sr_db_set_multi() {
  _sm_sd="$1"; _sm_pairs="$2"
  _sm_db=$(_sr_db_file "$_sm_sd")
  [ -f "$_sm_db" ] || _sr_die "set: state.db ausente em $_sm_sd" 1
  _sm_exec_id=$(_sr_exec_id "$_sm_db")
  [ -n "$_sm_exec_id" ] || _sr_die "set: execution ausente em $_sm_db" 1

  _sm_n=$(printf '%s' "$_sm_pairs" | jq 'length')
  _sm_lote=$(printf '%s' "$_sm_pairs" | jq -r '[.[].f] | join(" ")')

  _sm_exec_sets=""   # fragmentos "col = literal" do UPDATE execution unico
  _sm_extra=""       # extra_fields de execution (lazy; merges sequenciais)
  _sm_extra_dirty=0
  _sm_wave_ids=""    # wave ids distintos do lote (ordem de aparicao)
  _sm_wave_count=0   # quantos ids distintos (indexa _sm_wsets_N/_sm_wid_N)

  # ---- Fase 1: classificar/validar todos os pares (nenhuma escrita) ----
  _sm_i=0
  while [ "$_sm_i" -lt "$_sm_n" ]; do
    _sm_f=$(printf '%s' "$_sm_pairs" | jq -r ".[$_sm_i].f")
    _sm_v=$(printf '%s' "$_sm_pairs" | jq -c ".[$_sm_i].v")
    _sm_bare=${_sm_f#.}
    case "$_sm_bare" in
      events|waves|decisions|human_blocks|tasks)
        _sr_die "set: campo '.$_sm_bare' (resync de array) nao e suportado em lote multi-campo — grave-o numa invocacao set single-field dedicada" 1
        ;;
      accumulated_metrics.cache)
        [ -n "$_sm_extra" ] || _sm_extra=$(_state_db_exec "$_sm_db" "SELECT coalesce(extra_fields,'{}') FROM execution LIMIT 1;")
        _sm_extra=$(printf '%s' "$_sm_extra" | jq -c --argjson v "$_sm_v" '.cache_metrics = $v') \
          || _sr_die "set: jq falhou ao aplicar cache_metrics em extra_fields" 1
        _sm_extra_dirty=1
        ;;
      waves\[*)
        _sr_db_wave_field_resolve "$_sm_db" "$_sm_bare"
        [ -n "$_sr_wfr_col" ] \
          || _sr_die "set: campo de onda '$_sm_f' sem coluna dedicada nao e suportado em lote multi-campo — grave-o numa invocacao set single-field dedicada" 1
        _sm_lit=$(_sr_sql_literal "$_sr_wfr_type" "$_sm_v")
        # Agrupa por onda: 1 UPDATE multi-coluna por wave id (CHECKs de wave
        # tambem sao cross-coluna, ex. termination_reason x finished_at).
        _sm_widx=0
        _sm_found=""
        for _sm_wid_i in $_sm_wave_ids; do
          if [ "$_sm_wid_i" = "$_sr_wfr_wave_id" ]; then _sm_found=$_sm_widx; break; fi
          _sm_widx=$((_sm_widx + 1))
        done
        if [ -z "$_sm_found" ]; then
          _sm_found=$_sm_wave_count
          _sm_wave_ids="${_sm_wave_ids:+$_sm_wave_ids }$_sr_wfr_wave_id"
          eval "_sm_wid_$_sm_found=\$_sr_wfr_wave_id"
          eval "_sm_wsets_$_sm_found=''"
          _sm_wave_count=$((_sm_wave_count + 1))
        fi
        eval "_sm_wprev=\$_sm_wsets_$_sm_found"
        eval "_sm_wsets_$_sm_found=\"\${_sm_wprev:+\$_sm_wprev, }\$_sr_wfr_col = \$_sm_lit\""
        ;;
      *)
        _sr_exec_col_lookup "$_sm_bare"
        if [ -n "$_sr_lu_col" ]; then
          _sm_lit=$(_sr_sql_literal "$_sr_lu_type" "$_sm_v")
          _sm_exec_sets="${_sm_exec_sets:+$_sm_exec_sets, }$_sr_lu_col = $_sm_lit"
        else
          case "$_sm_bare" in
            *.*|*\[*)
              _sr_die "set: campo nao suportado sob backend SQLite (path aninhado nao modelado): '$_sm_f' — so campos de topo simples tem fallback para extra_fields" 1
              ;;
            execution|accumulated_metrics)
              # Mesma regra do set simples (container modelado nunca cai em
              # extra_fields sombreado) — lote inteiro rejeitado, estado intacto.
              _sr_die "set: '$_sm_f' e um container modelado sob backend SQLite (extra_fields seria sombreado na leitura) — atualize campo a campo ('.execution.status', ...) ou use 'state-rw.sh write' com o documento inteiro" 1
              ;;
          esac
          [ -n "$_sm_extra" ] || _sm_extra=$(_state_db_exec "$_sm_db" "SELECT coalesce(extra_fields,'{}') FROM execution LIMIT 1;")
          _sm_extra=$(printf '%s' "$_sm_extra" | jq -c --argjson v "$_sm_v" "$_sm_f = \$v") \
            || _sr_die "set: jq falhou ao aplicar '$_sm_f' em extra_fields" 1
          _sm_extra_dirty=1
        fi
        ;;
    esac
    _sm_i=$((_sm_i + 1))
  done

  # ---- Fase 2: montar a transacao unica e executar ----
  if [ "$_sm_extra_dirty" = 1 ]; then
    _sm_extra_lit=$(_sr_sql_literal json "$_sm_extra")
    _sm_exec_sets="${_sm_exec_sets:+$_sm_exec_sets, }extra_fields = $_sm_extra_lit"
  fi
  _sm_sql="BEGIN IMMEDIATE;"
  [ -n "$_sm_exec_sets" ] && _sm_sql="$_sm_sql UPDATE execution SET $_sm_exec_sets;"
  _sm_widx=0
  while [ "$_sm_widx" -lt "$_sm_wave_count" ]; do
    eval "_sm_wid=\$_sm_wid_$_sm_widx"
    eval "_sm_wsets=\$_sm_wsets_$_sm_widx"
    # shellcheck disable=SC2154 # _sm_wid/_sm_wsets sao atribuidas via eval acima
    _sm_sql="$_sm_sql UPDATE wave SET $_sm_wsets WHERE id = $(_sr_sql_quote "$_sm_wid");"
    _sm_widx=$((_sm_widx + 1))
  done
  _sm_sql="$_sm_sql COMMIT;"
  _state_db_exec_with_retry "$_sm_db" "$_sm_sql" \
    || _sr_die "set: transacao multi-campo rejeitada (invariante do schema violada? veja o erro do sqlite acima) — lote: $_sm_lote; estado intacto (rollback automatico)" 1
}

# ============================================================
# WRITE — importacao de documento completo (substituicao autoritativa)
# ============================================================

_sr_db_write_document() {
  _wd_sd="$1"; _wd_doc="$2"
  _wd_db=$(_sr_db_file "$_wd_sd")
  [ -f "$_wd_db" ] || _sr_die "write: state.db ausente em $_wd_sd" 1
  _wd_exec_id=$(_sr_exec_id "$_wd_db")
  [ -n "$_wd_exec_id" ] || _sr_die "write: execution ausente em $_wd_db" 1

  # --- execution: colunas conhecidas + extra_fields (substituicao total —
  # write() e "documento completo", diferente do merge pontual do set) ---
  _wd_short=$(printf '%s' "$_wd_doc" | jq -r '.short_name // empty')
  _wd_stage=$(printf '%s' "$_wd_doc" | jq -r '.current_stage')
  _wd_next=$(printf '%s' "$_wd_doc" | jq -r '.next_instruction')
  # SEM `// null`: jq trata `false` como falsy, entao `.atomic_commit_enabled
  # // null` colapsa o valor legitimo `false` (o default do campo — a maioria
  # das execucoes reais) para `null`, perdendo o dado no UPDATE abaixo
  # (bug achado empiricamente na FASE 8 desta feature, ao migrar um state.json
  # de fixture com atomic_commit_enabled=false: M3.2 reprovava toda vez). Sem
  # o `//`, chave ausente ja produz `null` por padrao do jq — nenhum
  # comportamento de fallback e perdido.
  _wd_atomic=$(printf '%s' "$_wd_doc" | jq -c '.atomic_commit_enabled')
  _wd_atomic_sql="NULL"
  case "$_wd_atomic" in true) _wd_atomic_sql=1 ;; false) _wd_atomic_sql=0 ;; esac
  _wd_ika=$(printf '%s' "$_wd_doc" | jq -c '.initial_key_aspects // []')
  _wd_urls=$(printf '%s' "$_wd_doc" | jq -c '.external_urls_whitelist // []')
  _wd_circ=$(printf '%s' "$_wd_doc" | jq -c '.circular_movement_history // []')
  _wd_prereq=$(printf '%s' "$_wd_doc" | jq -c '.prerequisites // null')
  _wd_brief=$(printf '%s' "$_wd_doc" | jq -c '.briefing_cache // null')
  _wd_const=$(printf '%s' "$_wd_doc" | jq -c '.constitution_cache // null')
  _wd_pr=$(printf '%s' "$_wd_doc" | jq -c '.push_pr_result // null')
  _wd_stack=$(printf '%s' "$_wd_doc" | jq -c '.execution.suggested_stack // null')
  _wd_status=$(printf '%s' "$_wd_doc" | jq -r '.execution.status')
  _wd_term=$(printf '%s' "$_wd_doc" | jq -r '.execution.termination_reason // empty')
  _wd_started=$(printf '%s' "$_wd_doc" | jq -r '.execution.started_at')
  _wd_finished=$(printf '%s' "$_wd_doc" | jq -r '.execution.finished_at // empty')
  _wd_canon=$(printf '%s' "$_wd_doc" | jq -r '.execution.canonical_project // empty')
  _wd_sess=$(printf '%s' "$_wd_doc" | jq -r '.execution.session_name // empty')
  _wd_tpp=$(printf '%s' "$_wd_doc" | jq -r '.execution.target_project_path')
  _wd_tpd=$(printf '%s' "$_wd_doc" | jq -r '.execution.target_project_description')
  _wd_extra=$(printf '%s' "$_wd_doc" | jq -c 'del(.schema_version,.short_name,.execution,.prerequisites,.current_stage,.next_instruction,.waves,.decisions,.human_blocks,.tasks,.events,.budgets,.accumulated_metrics,.external_urls_whitelist,.circular_movement_history,.initial_key_aspects,.atomic_commit_enabled,.briefing_cache,.constitution_cache,.push_pr_result)')

  _wd_sql="BEGIN IMMEDIATE; UPDATE execution SET "
  _wd_sql="${_wd_sql}short_name=$([ -n "$_wd_short" ] && _sr_sql_quote "$_wd_short" || printf NULL),"
  _wd_sql="${_wd_sql}current_stage=$(_sr_sql_quote "$_wd_stage"),"
  _wd_sql="${_wd_sql}next_instruction=$(_sr_sql_quote "$_wd_next"),"
  _wd_sql="${_wd_sql}atomic_commit_enabled=$_wd_atomic_sql,"
  _wd_sql="${_wd_sql}initial_key_aspects=$(_sr_sql_quote "$_wd_ika"),"
  _wd_sql="${_wd_sql}external_urls_whitelist=$(_sr_sql_quote "$_wd_urls"),"
  _wd_sql="${_wd_sql}circular_movement_history=$(_sr_sql_quote "$_wd_circ"),"
  _wd_sql="${_wd_sql}prerequisites=$([ "$_wd_prereq" != "null" ] && _sr_sql_quote "$_wd_prereq" || printf NULL),"
  _wd_sql="${_wd_sql}briefing_cache=$([ "$_wd_brief" != "null" ] && _sr_sql_quote "$_wd_brief" || printf NULL),"
  _wd_sql="${_wd_sql}constitution_cache=$([ "$_wd_const" != "null" ] && _sr_sql_quote "$_wd_const" || printf NULL),"
  _wd_sql="${_wd_sql}push_pr_result=$([ "$_wd_pr" != "null" ] && _sr_sql_quote "$_wd_pr" || printf NULL),"
  _wd_sql="${_wd_sql}suggested_stack=$([ "$_wd_stack" != "null" ] && _sr_sql_quote "$_wd_stack" || printf NULL),"
  _wd_sql="${_wd_sql}status=$(_sr_sql_quote "$_wd_status"),"
  _wd_sql="${_wd_sql}termination_reason=$([ -n "$_wd_term" ] && _sr_sql_quote "$_wd_term" || printf NULL),"
  _wd_sql="${_wd_sql}started_at=$(_sr_sql_quote "$_wd_started"),"
  _wd_sql="${_wd_sql}finished_at=$([ -n "$_wd_finished" ] && _sr_sql_quote "$_wd_finished" || printf NULL),"
  _wd_sql="${_wd_sql}canonical_project=$([ -n "$_wd_canon" ] && _sr_sql_quote "$_wd_canon" || printf NULL),"
  _wd_sql="${_wd_sql}session_name=$([ -n "$_wd_sess" ] && _sr_sql_quote "$_wd_sess" || printf NULL),"
  _wd_sql="${_wd_sql}target_project_path=$(_sr_sql_quote "$_wd_tpp"),"
  _wd_sql="${_wd_sql}target_project_description=$(_sr_sql_quote "$_wd_tpd"),"
  _wd_sql="${_wd_sql}extra_fields=$(_sr_sql_quote "$_wd_extra")"
  _wd_sql="${_wd_sql} WHERE id = $(_sr_sql_quote "$_wd_exec_id");"

  # --- waves (SEM skills_invoked) — FK-dependente de execution, precede
  # decisions/tasks. As skills_invoked sao emitidas mais abaixo, DEPOIS das
  # decisions, porque skill_invocation.decision_id e FK para decision(id)
  # (ordem do contracts/migration.md §M2). ---
  _wd_wtmp=$(mktemp) || _sr_die "write: mktemp falhou" 1
  printf '%s' "$_wd_doc" | jq -c '.waves[]? // empty' > "$_wd_wtmp" 2>/dev/null
  while IFS= read -r _wd_wrow; do
    _wd_sql="$_wd_sql $(_sr_db_upsert_wave "$_wd_db" "$_wd_exec_id" "$_wd_wrow" no)"
  done < "$_wd_wtmp"

  # --- decisions — FK-dependente de wave ---
  _wd_dtmp=$(mktemp) || _sr_die "write: mktemp falhou" 1
  printf '%s' "$_wd_doc" | jq -c '.decisions[]? // empty' > "$_wd_dtmp" 2>/dev/null
  while IFS= read -r _wd_drow; do
    _wd_sql="$_wd_sql $(_sr_db_upsert_decision "$_wd_exec_id" "$_wd_drow")"
  done < "$_wd_dtmp"
  rm -f -- "$_wd_dtmp"

  # --- skills_invoked — FK-dependente de wave E de decision ---
  while IFS= read -r _wd_wrow; do
    _wd_sql="$_wd_sql $(_sr_db_wave_skills_sql "$_wd_wrow")"
  done < "$_wd_wtmp"
  rm -f -- "$_wd_wtmp"

  # --- human_blocks — FK-dependente de decision ---
  _wd_htmp=$(mktemp) || _sr_die "write: mktemp falhou" 1
  printf '%s' "$_wd_doc" | jq -c '.human_blocks[]? // empty' > "$_wd_htmp" 2>/dev/null
  while IFS= read -r _wd_hrow; do
    _wd_sql="$_wd_sql $(_sr_db_upsert_human_block "$_wd_exec_id" "$_wd_hrow")"
  done < "$_wd_htmp"
  rm -f -- "$_wd_htmp"

  # --- tasks — FK-dependente de wave ---
  _wd_ttmp=$(mktemp) || _sr_die "write: mktemp falhou" 1
  printf '%s' "$_wd_doc" | jq -c '.tasks[]? // empty' > "$_wd_ttmp" 2>/dev/null
  while IFS= read -r _wd_trow; do
    _wd_sql="$_wd_sql $(_sr_db_upsert_task "$_wd_exec_id" "$_wd_trow")"
  done < "$_wd_ttmp"
  rm -f -- "$_wd_ttmp"

  # --- events — leaf, substituicao total ---
  _wd_events=$(printf '%s' "$_wd_doc" | jq -c '.events // []')
  _wd_sql="$_wd_sql DELETE FROM event WHERE execution_id = $(_sr_sql_quote "$_wd_exec_id");"
  _wd_etmp=$(mktemp) || _sr_die "write: mktemp falhou" 1
  printf '%s' "$_wd_events" | jq -c '.[]' > "$_wd_etmp" 2>/dev/null
  while IFS= read -r _wd_erow; do
    _wd_etype=$(printf '%s' "$_wd_erow" | jq -r '.event_type')
    _wd_ets=$(printf '%s' "$_wd_erow" | jq -r '.timestamp')
    _wd_edesc=$(printf '%s' "$_wd_erow" | jq -r '.description // empty')
    _wd_edesc_sql="NULL"
    [ -n "$_wd_edesc" ] && _wd_edesc_sql=$(_sr_sql_quote "$_wd_edesc")
    _wd_sql="$_wd_sql INSERT INTO event (execution_id,event_type,timestamp,description) VALUES ($(_sr_sql_quote "$_wd_exec_id"),$(_sr_sql_quote "$_wd_etype"),$(_sr_sql_quote "$_wd_ets"),$_wd_edesc_sql);"
  done < "$_wd_etmp"
  rm -f -- "$_wd_etmp"

  _wd_sql="$_wd_sql COMMIT;"
  _state_db_exec_with_retry "$_wd_db" "$_wd_sql" || _sr_die "write: importacao do documento falhou" 1
}
