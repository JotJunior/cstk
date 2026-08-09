#!/bin/sh
# _state-ondas-db.sh — implementacao do backend SQLite para state-ondas.sh
# (feature state-db-foundation, FASE 3 task 3.3).
#
# Ref: docs/specs/state-db-foundation/tasks.md FASE 3, task 3.3
#      docs/specs/state-db-foundation/contracts/primitives.md §C1 C2 C3 C4 C6
#      docs/specs/state-db-foundation/data-model.md (entities wave/
#      skill_invocation/task_outcome)
#
# NAO e executavel diretamente. Sourced por state-ondas.sh, que ja fez
# `. _state-db.sh` e `. _state-rw-db.sh` antes — depende de sql_escape/
# strip_nul/_state_db_*/_sr_db_file/_sr_backend/_sr_exec_id/_sr_sql_quote
# (reuso deliberado dos primitivos ja testados da task 3.2, nao
# reimplementacao — mesmo racional de C8 para sql_escape/strip_nul).
#
# Funcoes expostas (todas exigem STATE_DIR ja resolvido para backend sqlite
# pelo caller via _sr_backend, e state.db existente):
#   _so_db_start DIR                          -> INSERT de nova onda (C3:
#                                                 onda ja aberta => exit 1,
#                                                 via ux_wave_single_open)
#   _so_db_end DIR MOTIVO PROXIMA ETAPAS_RAW NEXT_SET NEXT_RAW
#                                              -> fecha a onda aberta (uma
#                                                 unica transacao, C4). Apos
#                                                 o COMMIT, dispara o export
#                                                 derivado (FASE 5,
#                                                 contracts/export.md E5/E6
#                                                 — _so_export_snapshot,
#                                                 definida em
#                                                 state-ondas.sh) como
#                                                 gatilho automatico de
#                                                 FR-013-INFRA-BACKUP;
#                                                 best-effort, nunca reverte
#                                                 o fechamento ja commitado
#   _so_db_tool_call_tick DIR                 -> UPDATE wave.tool_calls+=1
#                                                 na onda aberta
#   _so_db_record_skill DIR SKILL DEC KIND    -> INSERT idempotente em
#                                                 skill_invocation (ultima
#                                                 onda por seq, igual ao
#                                                 .waves[-1] do path JSON)
#   _so_db_record_task DIR TID TTL WID OC TR TP LK AF ORIGEM IFABSENT
#                                              -> upsert em task_outcome
#                                                 (ON CONFLICT DO UPDATE, ou
#                                                 DO NOTHING se IFABSENT=yes)
#   _so_db_reconcile_tasks DIR TASKS_MD WID DRY
#                                              -> back-fill deterministico a
#                                                 partir do tasks.md
#   _so_db_wave_status DIR                    -> none|open|closed
#   _so_db_current_id DIR                     -> onda-NNN ou "init"
#
# GAP CONHECIDO E DOCUMENTADO (nao um bug silencioso, mesmo padrao da nota
# de _state-rw-db.sh): o hook marco-aware de retrospectiva proativa
# (_so_retro_milestone_fire, definido em state-ondas.sh) opera sobre
# state.json via jq direto no arquivo. Sob backend SQLite isso e um no-op
# silencioso e SEGURO (arquivo ausente -> jq falha -> _so_retro_milestone_due
# retorna 1 -> hook nunca dispara), nao uma falha de `end`. Adaptar esse hook
# para consultar o state.db exigiria tocar Decisao/Bloqueio tambem sob
# backend dual — fora do escopo de "Adaptar state-ondas.sh" (task 3.3, que
# cobre apenas start/end/wave-status/current-id, record-skill/record-task/
# reconcile-tasks, tool-call-tick/git-commit). Rastreado como gap conhecido.

# ---------- Helpers de agregacao (duplicados deliberadamente de
# _so_cmd_end no path JSON — ver nota de risco no cabecalho: preferimos
# duplicar ~15 linhas de jq a arriscar regressao no path JSON ja testado
# refatorando-o para uma funcao compartilhada) ----------

# _so_db_aggregate_agent_usage SPAWNS_JSON -> objeto agent_usage agregado
# (ou "null"). Mesma semantica de _so_cmd_end (path JSON): so agrega o que
# foi de fato observado no sidecar, nunca fabrica.
_so_db_aggregate_agent_usage() {
  printf '%s' "$1" | jq -c '
    . as $sp
    | ($sp | length) as $total
    | ([$sp[] | select(.status != "indisponivel")] | length) as $with_usage
    | ($total - $with_usage) as $unavailable
    | def sum_field(f): ([$sp[] | select(f != null) | f]) as $vals
        | if ($vals | length) > 0 then ($vals | add) else null end;
      if $total > 0 then {
        spawns_total: $total,
        spawns_with_usage: $with_usage,
        spawns_unavailable: $unavailable,
        total_tokens: sum_field(.total_tokens),
        input_tokens: sum_field(.input_tokens),
        output_tokens: sum_field(.output_tokens),
        cache_read_input_tokens: sum_field(.cache_read_input_tokens),
        cache_creation_input_tokens: sum_field(.cache_creation_input_tokens),
        tool_use_count: sum_field(.tool_use_count),
        duration_ms: sum_field(.duration_ms)
      } else null end
  ' 2>/dev/null
}

# ---------- Parsing de tasks.md (duplicado deliberadamente das duas awk
# inline de _so_cmd_reconcile_tasks — mesmo racional de risco acima) ----------

# _so_tasks_md_titlemap TASKS_MD -> stdout "id<TAB>titulo" por task com
# titulo resolvivel (heading tem precedencia sobre checkbox).
_so_tasks_md_titlemap() {
  awk '
    { sub(/\r$/, "") }
    /^### / {
      line = $0; sub(/^### +/, "", line)
      split(line, a, /[ \t]+/); id = a[1]
      if (id ~ /^[0-9]+(\.[0-9]+)+(-bis(\.[0-9]+)*)?$/) {
        t = line; sub(/^[^ \t]+[ \t]+/, "", t)
        gsub(/`/, "", t); sub(/[ \t]*\[[CAM]\][ \t]*$/, "", t)
        gsub(/\t/, " ", t); gsub(/  +/, " ", t)
        sub(/^ +/, "", t); sub(/ +$/, "", t)
        if (t != "") heading[id] = t
      }
      next
    }
    /^- \[.\] / {
      line = $0; sub(/^- \[.\][ \t]+/, "", line)
      split(line, a, /[ \t]+/); id = a[1]
      if (id ~ /^[0-9]+(\.[0-9]+)+(-bis(\.[0-9]+)*)?$/) {
        t = line; sub(/^[^ \t]+[ \t]+/, "", t)
        gsub(/`/, "", t); gsub(/\t/, " ", t); gsub(/  +/, " ", t)
        sub(/^ +/, "", t); sub(/ +$/, "", t)
        if (t != "" && !(id in checkbox)) checkbox[id] = t
      }
      next
    }
    END {
      for (k in checkbox) if (!(k in heading)) print k "\t" checkbox[k]
      for (k in heading) print k "\t" heading[k]
    }
  ' "$1"
}

# _so_tasks_md_missing TASKS_MD EXISTING_IDS_FILE -> stdout "id<TAB>titulo"
# por task CONCLUIDA (todas as subtarefas-checkbox [x]) ausente de EXISTING.
_so_tasks_md_missing() {
  _tmm_md="$1"; _tmm_exf="$2"
  awk -v exf="$_tmm_exf" '
    { sub(/\r$/, "") }
    FILENAME == exf { seen[$0] = 1; next }
    function flush() {
      if (cur != "" && nsub > 0 && ndone == nsub && !(cur in seen)) {
        print cur "\t" titulo
      }
      cur = ""; titulo = ""; nsub = 0; ndone = 0
    }
    /^#/ {
      flush()
      if ($0 ~ /^### /) {
        line = $0; sub(/^### +/, "", line)
        split(line, a, /[ \t]+/); id = a[1]
        if (id ~ /^[0-9]+(\.[0-9]+)+(-bis(\.[0-9]+)*)?$/) {
          cur = id
          t = line; sub(/^[^ \t]+[ \t]+/, "", t)
          gsub(/`/, "", t); sub(/[ \t]*\[[CAM]\][ \t]*$/, "", t)
          gsub(/\t/, " ", t)
          titulo = t
        }
      }
      next
    }
    /^- \[.\] / {
      if (cur != "") {
        st = substr($0, 4, 1)
        nsub++
        if (st == "x" || st == "X") ndone++
      }
      next
    }
    END { flush() }
  ' "$_tmm_exf" "$_tmm_md"
}

# ---------- start ----------

_so_db_start() {
  _sdb_sdir="$1"
  _sdb_db=$(_sr_db_file "$_sdb_sdir")
  [ -f "$_sdb_db" ] || _so_die "start: state.db ausente em $_sdb_sdir" 1
  _sdb_exec_id=$(_sr_exec_id "$_sdb_db")
  [ -n "$_sdb_exec_id" ] || _so_die "start: execution ausente em $_sdb_db" 1

  _sdb_num=$(_state_db_exec "$_sdb_db" \
    "SELECT coalesce(max(seq),0)+1 FROM wave WHERE execution_id=$(_sr_sql_quote "$_sdb_exec_id");")
  case "$_sdb_num" in ''|*[!0-9]*) _so_die "start: falha ao calcular seq da onda (backend sqlite)" 1 ;; esac
  _sdb_id=$(printf 'onda-%03d' "$_sdb_num")
  _sdb_now=$(_so_iso_now)

  _sdb_sql="BEGIN IMMEDIATE; INSERT INTO wave (id,execution_id,seq,started_at,finished_at,tool_calls,termination_reason,next_wave_scheduled_for,executed_stages,agent_usage,agent_spawns,otel_usage,extra_fields) VALUES ($(_sr_sql_quote "$_sdb_id"),$(_sr_sql_quote "$_sdb_exec_id"),$_sdb_num,$(_sr_sql_quote "$_sdb_now"),NULL,0,NULL,NULL,$(_sr_sql_quote '[]'),NULL,NULL,NULL,NULL); COMMIT;"

  # C3: onda ja aberta viola ux_wave_single_open — a constraint do banco
  # falha o INSERT; _state_db_exec_with_retry ja ecoa o erro sqlite3 em
  # stderr (nunca silenciado).
  _state_db_exec_with_retry "$_sdb_db" "$_sdb_sql" \
    || _so_die "start: INSERT de onda falhou (onda ja aberta, ou erro de banco — ver stderr acima) [backend sqlite]" 1

  # Sidecares + baseline + OTel: backend-agnosticos (arquivos no state-dir,
  # nao no state.db) — mesma sequencia do path JSON.
  _so_ticks_reset "$_sdb_sdir"
  _so_agent_usage_reset "$_sdb_sdir"
  _so_start_snapshot_baseline "$_sdb_sdir"
  _so_otel_reset "$_sdb_sdir"
  _so_otel_snapshot "$_sdb_sdir" start

  printf '%s\n' "$_sdb_id"
}

# ---------- end ----------

_so_db_end() {
  _e_sdir="$1"; _e_motivo="$2"; _e_proxima="$3"; _e_etapas_raw="$4"
  _e_next_set="$5"; _e_next_raw="$6"

  _e_db=$(_sr_db_file "$_e_sdir")
  [ -f "$_e_db" ] || _so_die "end: state.db ausente em $_e_sdir" 1
  _e_exec_id=$(_sr_exec_id "$_e_db")
  [ -n "$_e_exec_id" ] || _so_die "end: execution ausente em $_e_db" 1

  _e_wid=$(_state_db_exec "$_e_db" \
    "SELECT id FROM wave WHERE execution_id=$(_sr_sql_quote "$_e_exec_id") AND termination_reason IS NULL;")
  if [ -z "$_e_wid" ]; then
    diag_emit error no-open-wave "end: nao ha onda em andamento" \
      "rode state-ondas.sh start antes de end, ou confira se .waves ja foi fechado por outra chamada" || :
    _so_die "end: nao ha onda em andamento" 1
  fi

  _e_started=$(_state_db_exec "$_e_db" "SELECT started_at FROM wave WHERE id=$(_sr_sql_quote "$_e_wid");")
  _e_now=$(_so_iso_now)
  _e_wc=$(_so_wallclock "$_e_started" "$_e_now") || true

  _e_tc_field=$(_state_db_exec "$_e_db" "SELECT tool_calls FROM wave WHERE id=$(_sr_sql_quote "$_e_wid");")
  case "$_e_tc_field" in ''|*[!0-9]*) _e_tc_field=0 ;; esac
  _e_tc_side=$(_so_ticks_count "$_e_sdir")
  _e_tc=$((_e_tc_field + _e_tc_side))

  _e_cur_stages=$(_state_db_exec "$_e_db" "SELECT coalesce(executed_stages,'[]') FROM wave WHERE id=$(_sr_sql_quote "$_e_wid");")
  _e_etapas_json=$(printf '%s\n' "$_e_etapas_raw" | sed '/^$/d' | jq -R . | jq -s .)
  _e_stages_merged=$(printf '%s' "$_e_cur_stages" | jq -c --argjson add "$_e_etapas_json" '. + $add') \
    || _so_die "end: falha ao mesclar executed_stages (backend sqlite)" 1

  _e_proxima_sql="NULL"
  [ "$_e_proxima" != "null" ] && _e_proxima_sql=$(_sr_sql_quote "$_e_proxima")

  _e_next_instr_sql=""
  if [ "$_e_next_set" = 1 ]; then
    [ -n "$_e_next_raw" ] || _so_die "end: --next-instruction nao aceita valor vazio" 1
    _e_next_instr_sql=$(_sr_sql_quote "$_e_next_raw")
  fi

  # Agregacao do sidecar de uso de agente — mesma semantica do path JSON
  # (data-model.md "Entity: Consumo Agregado da Onda"), nunca fabrica.
  _e_spawns=$(_so_agent_usage_read "$_e_sdir")
  _e_au=$(_so_db_aggregate_agent_usage "$_e_spawns") || _e_au="null"
  [ -n "$_e_au" ] || _e_au="null"

  # Consumo OTel — sidecares TSV, backend-agnosticos.
  _so_otel_snapshot "$_e_sdir" end
  # Arquivo de motivo criado AQUI (fora do `$( )`) — ver _so_otel_delta.
  _e_otel_rf=$(mktemp 2>/dev/null) || _e_otel_rf=""
  _e_otel=$(_so_otel_delta "$_e_sdir" "$_e_otel_rf")
  case "$_e_otel" in ''|null) _e_otel="null" ;; esac
  _e_otel_reason=$(_so_otel_reason_read "$_e_otel_rf")
  [ -n "$_e_otel_rf" ] && rm -f -- "$_e_otel_rf" 2>/dev/null

  _e_spawns_sql="NULL"; [ "$_e_spawns" != "[]" ] && [ -n "$_e_spawns" ] && _e_spawns_sql=$(_sr_sql_quote "$_e_spawns")
  _e_au_sql="NULL"; [ "$_e_au" != "null" ] && _e_au_sql=$(_sr_sql_quote "$_e_au")
  _e_otel_sql="NULL"; [ "$_e_otel" != "null" ] && _e_otel_sql=$(_sr_sql_quote "$_e_otel")

  # Motivo da ausencia de medicao OTel -> catch-all `extra_fields` (o
  # equivalente sob SQLite da chave achatada que o path JSON grava na
  # onda). MERGE, nunca overwrite: `extra_fields` e compartilhado com
  # outros produtores (ex.: touched_key_aspects). So escreve quando ha
  # motivo — onda medida nao ganha chave nenhuma.
  _e_extra_sql=""
  if [ "$_e_otel" = "null" ] && [ -n "$_e_otel_reason" ]; then
    _e_extra_cur=$(_state_db_exec "$_e_db" \
      "SELECT coalesce(extra_fields,'{}') FROM wave WHERE id=$(_sr_sql_quote "$_e_wid");")
    case "$_e_extra_cur" in '') _e_extra_cur='{}' ;; esac
    _e_extra_new=$(printf '%s' "$_e_extra_cur" \
      | jq -c --arg r "$_e_otel_reason" '. + {otel_absent_reason: $r}' 2>/dev/null) || _e_extra_new=""
    [ -n "$_e_extra_new" ] && _e_extra_sql=", extra_fields=$(_sr_sql_quote "$_e_extra_new")"
  fi

  # C4: fechamento da onda + atualizacao de next_instruction na MESMA
  # transacao (paridade com o write atomico unico do path JSON).
  _e_sql="BEGIN IMMEDIATE; UPDATE wave SET finished_at=$(_sr_sql_quote "$_e_now"), wallclock_seconds=$_e_wc, tool_calls=$_e_tc, termination_reason=$(_sr_sql_quote "$_e_motivo"), next_wave_scheduled_for=$_e_proxima_sql, executed_stages=$(_sr_sql_quote "$_e_stages_merged"), agent_usage=$_e_au_sql, agent_spawns=$_e_spawns_sql, otel_usage=$_e_otel_sql$_e_extra_sql WHERE id=$(_sr_sql_quote "$_e_wid");"
  if [ "$_e_next_set" = 1 ]; then
    _e_sql="$_e_sql UPDATE execution SET next_instruction=$_e_next_instr_sql WHERE id=$(_sr_sql_quote "$_e_exec_id");"
  fi
  _e_sql="$_e_sql COMMIT;"

  _state_db_exec_with_retry "$_e_db" "$_e_sql" \
    || _so_die "end: UPDATE de onda falhou (backend sqlite)" 1

  # Export derivado (FASE 5, contracts/export.md E5/E6, dec-032 E5-a):
  # gatilho automatico ao fim da onda — reaproveita o export como mecanismo
  # de FR-013-INFRA-BACKUP sob backend SQLite sem introduzir backup nativo
  # do SQLite (research.md Decision 6). Roda DEPOIS do COMMIT acima: a
  # fonte de verdade (state.db) ja fechou a onda; E6 (MUST) exige que uma
  # falha aqui NUNCA reverta nem impeca esse fechamento — so degrada,
  # reportada em stderr por _so_export_snapshot (definida em
  # state-ondas.sh, disponivel neste escopo por sourcing).
  _so_export_snapshot "$_e_sdir" >/dev/null \
    || _so_log "end: export/backup derivado nao gerado nesta onda (E6: fechamento da onda ja commitado, nao afetado) [backend sqlite]"

  _so_ticks_reset "$_e_sdir"
  _so_agent_usage_reset "$_e_sdir"
  _so_otel_reset "$_e_sdir"
  _so_log "end: onda finalizada (motivo=$_e_motivo, wallclock=${_e_wc}s, tool_calls=$_e_tc) [backend sqlite]"

  # Hook marco-aware de retrospectiva: ver GAP CONHECIDO no cabecalho deste
  # arquivo. Deliberadamente NAO chamado aqui sob backend sqlite.
}

# ---------- tool-call-tick ----------

_so_db_tool_call_tick() {
  _sdb_sdir="$1"
  _sdb_db=$(_sr_db_file "$_sdb_sdir")
  [ -f "$_sdb_db" ] || _so_die "tool-call-tick: state.db ausente" 1
  _sdb_exec_id=$(_sr_exec_id "$_sdb_db")
  [ -n "$_sdb_exec_id" ] || _so_die "tool-call-tick: execution ausente" 1
  _sdb_wid=$(_state_db_exec "$_sdb_db" \
    "SELECT id FROM wave WHERE execution_id=$(_sr_sql_quote "$_sdb_exec_id") AND termination_reason IS NULL;")
  [ -n "$_sdb_wid" ] || _so_die "tool-call-tick: nenhuma onda aberta (backend sqlite) — rode state-ondas.sh start primeiro" 1
  _state_db_exec_with_retry "$_sdb_db" \
    "BEGIN IMMEDIATE; UPDATE wave SET tool_calls = tool_calls + 1 WHERE id = $(_sr_sql_quote "$_sdb_wid"); COMMIT;" \
    || _so_die "tool-call-tick: UPDATE falhou (backend sqlite)" 1
  _state_db_exec "$_sdb_db" "SELECT tool_calls FROM wave WHERE id = $(_sr_sql_quote "$_sdb_wid");"
}

# ---------- record-skill ----------

_so_db_record_skill() {
  _sdb_sdir="$1"; _sdb_skill="$2"; _sdb_dec="$3"; _sdb_kind="$4"
  _sdb_db=$(_sr_db_file "$_sdb_sdir")
  [ -f "$_sdb_db" ] || _so_die "record-skill: state.db ausente em $_sdb_sdir" 1
  _sdb_exec_id=$(_sr_exec_id "$_sdb_db")
  [ -n "$_sdb_exec_id" ] || _so_die "record-skill: execution ausente" 1

  # Ultima onda por seq (nao necessariamente aberta) — paridade exata com
  # o path JSON, que grava em .waves[-1] independente de estar fechada.
  _sdb_wid=$(_state_db_exec "$_sdb_db" \
    "SELECT id FROM wave WHERE execution_id=$(_sr_sql_quote "$_sdb_exec_id") ORDER BY seq DESC LIMIT 1;")
  if [ -z "$_sdb_wid" ]; then
    diag_emit error no-open-wave "record-skill: nenhuma onda em andamento (rode state-ondas.sh start primeiro)" \
      "rode state-ondas.sh start antes de record-skill" || :
    _so_die "record-skill: nenhuma onda em andamento (rode state-ondas.sh start primeiro)" 1
  fi

  _sdb_now=$(_so_iso_now)
  _sdb_dec_cmp="decision_id IS NULL"
  _sdb_dec_val="NULL"
  if [ -n "$_sdb_dec" ]; then
    _sdb_dec_cmp="decision_id = $(_sr_sql_quote "$_sdb_dec")"
    _sdb_dec_val=$(_sr_sql_quote "$_sdb_dec")
  fi

  # INSERT ... SELECT ... WHERE NOT EXISTS: check-then-insert atomico numa
  # unica statement, sem race entre a checagem e a escrita (C4/C6).
  _sdb_sql="BEGIN IMMEDIATE; INSERT INTO skill_invocation (wave_id,skill,timestamp,decision_id,kind) SELECT $(_sr_sql_quote "$_sdb_wid"),$(_sr_sql_quote "$_sdb_skill"),$(_sr_sql_quote "$_sdb_now"),$_sdb_dec_val,$(_sr_sql_quote "$_sdb_kind") WHERE NOT EXISTS (SELECT 1 FROM skill_invocation WHERE wave_id=$(_sr_sql_quote "$_sdb_wid") AND skill=$(_sr_sql_quote "$_sdb_skill") AND $_sdb_dec_cmp); COMMIT;"
  _state_db_exec_with_retry "$_sdb_db" "$_sdb_sql" \
    || _so_die "record-skill: INSERT falhou (backend sqlite)" 1
  _state_db_exec "$_sdb_db" "SELECT count(*) FROM skill_invocation WHERE wave_id=$(_sr_sql_quote "$_sdb_wid");"
}

# ---------- record-task ----------

# _so_db_record_task DIR TID TTL WID OC TR TP LK AF ORIGEM IFABSENT
# LK ja normalizado pelo caller para o literal "true"|"false"|"null".
_so_db_record_task() {
  _sdb_sdir="$1"; _sdb_tid="$2"; _sdb_ttl="$3"; _sdb_wid="$4"; _sdb_oc="$5"
  _sdb_tr="$6"; _sdb_tp="$7"; _sdb_lk="$8"; _sdb_af="$9"
  _sdb_origem="${10}"; _sdb_ifabsent="${11}"

  _sdb_db=$(_sr_db_file "$_sdb_sdir")
  [ -f "$_sdb_db" ] || _so_die "record-task: state.db ausente em $_sdb_sdir" 1
  _sdb_exec_id=$(_sr_exec_id "$_sdb_db")
  [ -n "$_sdb_exec_id" ] || _so_die "record-task: execution ausente" 1

  if [ -z "$_sdb_wid" ]; then
    _sdb_wid=$(_state_db_exec "$_sdb_db" \
      "SELECT id FROM wave WHERE execution_id=$(_sr_sql_quote "$_sdb_exec_id") ORDER BY seq DESC LIMIT 1;")
  fi

  _sdb_now=$(_so_iso_now)
  _sdb_lint_sql="NULL"
  case "$_sdb_lk" in true) _sdb_lint_sql=1 ;; false) _sdb_lint_sql=0 ;; esac
  _sdb_src_sql="NULL"
  [ -n "$_sdb_origem" ] && _sdb_src_sql=$(_sr_sql_quote "$_sdb_origem")

  _sdb_conflict="DO UPDATE SET title=excluded.title, wave_id=excluded.wave_id, outcome=excluded.outcome, tests_run=excluded.tests_run, tests_passed=excluded.tests_passed, lint_ok=excluded.lint_ok, touched_files=excluded.touched_files, recorded_at=excluded.recorded_at, source=excluded.source"
  [ "$_sdb_ifabsent" = "yes" ] && _sdb_conflict="DO NOTHING"

  _sdb_sql="BEGIN IMMEDIATE; INSERT INTO task_outcome (execution_id,task_id,title,wave_id,outcome,tests_run,tests_passed,lint_ok,touched_files,recorded_at,source) VALUES ($(_sr_sql_quote "$_sdb_exec_id"),$(_sr_sql_quote "$_sdb_tid"),$(_sr_sql_quote "$_sdb_ttl"),$(_sr_sql_quote "$_sdb_wid"),$(_sr_sql_quote "$_sdb_oc"),$_sdb_tr,$_sdb_tp,$_sdb_lint_sql,$(_sr_sql_quote "$_sdb_af"),$(_sr_sql_quote "$_sdb_now"),$_sdb_src_sql) ON CONFLICT(execution_id,task_id) $_sdb_conflict; COMMIT;"
  _state_db_exec_with_retry "$_sdb_db" "$_sdb_sql" \
    || _so_die "record-task: upsert falhou (backend sqlite)" 1
  _state_db_exec "$_sdb_db" "SELECT count(*) FROM task_outcome WHERE execution_id=$(_sr_sql_quote "$_sdb_exec_id");"
}

# ---------- reconcile-tasks ----------

_so_db_reconcile_tasks() {
  _rc_sdir="$1"; _rc_md="$2"; _rc_wid="$3"; _rc_dry="$4"

  _rc_db=$(_sr_db_file "$_rc_sdir")
  [ -f "$_rc_db" ] || _so_die "reconcile-tasks: state.db ausente em $_rc_sdir" 1
  _rc_exec_id=$(_sr_exec_id "$_rc_db")
  [ -n "$_rc_exec_id" ] || _so_die "reconcile-tasks: execution ausente" 1

  if [ -z "$_rc_wid" ]; then
    _rc_wid=$(_state_db_exec "$_rc_db" \
      "SELECT id FROM wave WHERE execution_id=$(_sr_sql_quote "$_rc_exec_id") ORDER BY seq DESC LIMIT 1;")
  fi

  # Cura de titulos vazios — mesma fonte rastreavel do path JSON (heading/
  # checkbox do tasks.md), nunca inventada (Principio VI).
  if [ "$_rc_dry" != "yes" ]; then
    _rc_titlemap=$(_so_tasks_md_titlemap "$_rc_md")
    if [ -n "$_rc_titlemap" ]; then
      while IFS="$(printf '\t')" read -r _rc_hid _rc_httl; do
        [ -n "$_rc_hid" ] || continue
        _state_db_exec_with_retry "$_rc_db" \
          "BEGIN IMMEDIATE; UPDATE task_outcome SET title=$(_sr_sql_quote "$_rc_httl") WHERE execution_id=$(_sr_sql_quote "$_rc_exec_id") AND task_id=$(_sr_sql_quote "$_rc_hid") AND (title IS NULL OR title=''); COMMIT;" \
          || _so_log "reconcile-tasks: cura de titulo falhou para $_rc_hid (best-effort, ignorado)"
      done <<EOF
$_rc_titlemap
EOF
    fi
  fi

  _rc_exfile=$(mktemp) || _so_die "mktemp falhou" 1
  _state_db_exec "$_rc_db" "SELECT task_id FROM task_outcome WHERE execution_id=$(_sr_sql_quote "$_rc_exec_id");" > "$_rc_exfile"

  _rc_missing=$(_so_tasks_md_missing "$_rc_md" "$_rc_exfile")
  rm -f -- "$_rc_exfile" 2>/dev/null || :

  if [ -z "$_rc_missing" ]; then
    [ "$_rc_dry" = "yes" ] || printf '0\n'
    return 0
  fi
  if [ "$_rc_dry" = "yes" ]; then
    printf '%s\n' "$_rc_missing" | cut -f1
    return 0
  fi

  _rc_count=0
  while IFS="$(printf '\t')" read -r _rc_id _rc_ttl; do
    [ -n "$_rc_id" ] || continue
    _so_db_record_task "$_rc_sdir" "$_rc_id" "$_rc_ttl" "$_rc_wid" pass 0 0 null "[]" reconcile yes >/dev/null \
      || _so_die "reconcile-tasks: record-task falhou para $_rc_id (backend sqlite)" 1
    _rc_count=$((_rc_count + 1))
  done <<EOF
$_rc_missing
EOF
  printf '%s\n' "$_rc_count"
}

# ---------- wave-status ----------

_so_db_wave_status() {
  _sdb_sdir="$1"
  _sdb_db=$(_sr_db_file "$_sdb_sdir")
  [ -f "$_sdb_db" ] || _so_die "wave-status: state.db ausente em $_sdb_sdir" 1
  _sdb_exec_id=$(_sr_exec_id "$_sdb_db")
  [ -n "$_sdb_exec_id" ] || _so_die "wave-status: execution ausente" 1
  _sdb_cnt=$(_state_db_exec "$_sdb_db" "SELECT count(*) FROM wave WHERE execution_id=$(_sr_sql_quote "$_sdb_exec_id");")
  if [ "$_sdb_cnt" = "0" ]; then
    printf 'none\n'
    return 0
  fi
  _sdb_term=$(_state_db_exec "$_sdb_db" \
    "SELECT termination_reason FROM wave WHERE execution_id=$(_sr_sql_quote "$_sdb_exec_id") ORDER BY seq DESC LIMIT 1;")
  if [ -z "$_sdb_term" ]; then
    printf 'open\n'
  else
    printf 'closed\n'
  fi
}

# ---------- current-id ----------

_so_db_current_id() {
  _sdb_sdir="$1"
  _sdb_db=$(_sr_db_file "$_sdb_sdir")
  [ -f "$_sdb_db" ] || _so_die "current-id: state.db ausente" 1
  _sdb_exec_id=$(_sr_exec_id "$_sdb_db")
  [ -n "$_sdb_exec_id" ] || _so_die "current-id: execution ausente" 1
  _sdb_id=$(_state_db_exec "$_sdb_db" \
    "SELECT id FROM wave WHERE execution_id=$(_sr_sql_quote "$_sdb_exec_id") ORDER BY seq DESC LIMIT 1;")
  if [ -z "$_sdb_id" ]; then
    printf 'init\n'
  else
    printf '%s\n' "$_sdb_id"
  fi
}
