#!/bin/sh
# state-db-migrate.sh — migracao EXPLICITA de state.json -> state.db
# (feature state-db-foundation, FASE 6).
#
# Ref: docs/specs/state-db-foundation/spec.md FR-005, FR-006, FR-014-INFRA-IDEMP
#      docs/specs/state-db-foundation/contracts/migration.md (M1..M6)
#      docs/specs/state-db-foundation/contracts/primitives.md §C10 (mktemp)
#      docs/specs/state-db-foundation/data-model.md (9 entidades)
#
# NOMEACAO (migration.md §Nomeacao — colisao a evitar): este script NAO e um
# subcomando de state-rw.sh porque `state-rw.sh migrate` JA EXISTE com outro
# significado (migracao do schema INTERNO do state.json, pt-BR -> EN). Dois
# sentidos sob o mesmo verbo, no mesmo script, e armadilha de operador.
# A UX do operador e `cstk state migrate --state-dir DIR` (cli/lib/state.sh),
# que DELEGA a este script (dec-034: "B para a UX, delegando a A a
# implementacao").
#
# Subcomandos:
#   state-db-migrate.sh migrate --state-dir DIR
#       — Migra <DIR>/state.json para <DIR>/state.db. NUNCA automatica:
#         so roda por invocacao explicita do operador (M6/FR-005).
#
# Exit codes:
#   0  sucesso (state.db publicado e verificado)
#   1  falha (erro de IO, sqlite3 ausente, verificacao M3 reprovada)
#   2  uso incorreto
#   3  RECUSADO por pre-condicao M1 (execucao ativa, estado invalido,
#      integridade divergente, state.db conflitante) — distinguivel de 1
#      para o operador saber que NADA foi tocado
#
# GARANTIAS (M4/M6): o state.json de origem, seu .sha256 e state-history/
# NUNCA sao apagados nem reescritos. Em qualquer ponto de falha o projeto
# continua operavel pelo state.json original.
#
# POSIX sh. Deps: sqlite3, jq (obrigatorias nesta camada — carve-out do
# amendment 1.3.0 da constitution; fail-fast com diagnostico abaixo).

set -eu

_SDM_NAME="state-db-migrate"
_SDM_SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P)

# shellcheck source=./_state-db.sh
. "$_SDM_SELF_DIR/_state-db.sh"

_sdm_die_usage() {
  printf '%s: %s\n' "$_SDM_NAME" "$1" >&2
  exit 2
}

# _sdm_die MSG [EXIT] -> diagnostico em stderr + exit (default 1).
_sdm_die() {
  printf '%s: %s\n' "$_SDM_NAME" "$1" >&2
  exit "${2:-1}"
}

# _sdm_refuse MSG -> recusa por pre-condicao M1 (exit 3, nada foi tocado).
# Registra a tentativa recusada em migration_run do state.db JA EXISTENTE,
# quando houver (M5: "toda tentativa — inclusive as recusadas"). Quando nao
# ha state.db, nao existe onde persistir: o diagnostico em stderr + exit 3
# e o registro (documentado, nao um esquecimento).
_sdm_refuse() {
  _sdm_r_msg="$1"
  if [ -n "${_SDM_DB:-}" ] && [ -f "${_SDM_DB:-}" ]; then
    _sdm_record_run "$_SDM_DB" refused "$_sdm_r_msg" '' '' || :
  fi
  printf '%s: RECUSADO: %s\n' "$_SDM_NAME" "$_sdm_r_msg" >&2
  printf '%s: nada foi modificado — state.json de origem intacto\n' "$_SDM_NAME" >&2
  exit 3
}

_sdm_require() {
  command -v "$1" >/dev/null 2>&1 || _sdm_die \
    "$1 nao encontrado no PATH — dependencia obrigatoria da camada de estado transacional (docs/constitution.md amendment 1.3.0)" 1
}

_sdm_iso_now() { date -u +%FT%TZ; }

# _sdm_sha256_file FILE -> hash sha256 (mesma logica de state-rw.sh:_sr_sha256_file).
_sdm_sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -- "$1" | awk '{print $1}'
  else
    _sdm_die "sha256sum/shasum ausente — instale coreutils ou perl-shasum" 1
  fi
}

# _sdm_record_run DB RESULT DIAG COUNTS_SRC COUNTS_TGT -> INSERT em migration_run.
# Best-effort: falha de registro NUNCA muda o desfecho da migracao (o registro
# e evidencia auditavel, nao o resultado em si).
_sdm_record_run() {
  _rr_db="$1"; _rr_result="$2"; _rr_diag="$3"; _rr_cs="$4"; _rr_ct="$5"
  _rr_sql="INSERT INTO migration_run (execution_id,source_path,source_sha256,started_at,finished_at,result,diagnostic,counts_source,counts_target) VALUES ("
  _rr_sql="$_rr_sql'$(sql_escape "${_SDM_EXEC_ID:-desconhecido}")',"
  _rr_sql="$_rr_sql'$(sql_escape "${_SDM_SRC:-}")',"
  _rr_sql="$_rr_sql'$(sql_escape "${_SDM_SRC_SHA:-}")',"
  _rr_sql="$_rr_sql'$(sql_escape "${_SDM_STARTED_AT:-}")',"
  _rr_sql="$_rr_sql'$(sql_escape "$(_sdm_iso_now)")',"
  _rr_sql="$_rr_sql'$(sql_escape "$_rr_result")',"
  _rr_sql="$_rr_sql$([ -n "$_rr_diag" ] && printf "'%s'" "$(sql_escape "$_rr_diag")" || printf NULL),"
  _rr_sql="$_rr_sql$([ -n "$_rr_cs" ] && printf "'%s'" "$(sql_escape "$_rr_cs")" || printf NULL),"
  _rr_sql="$_rr_sql$([ -n "$_rr_ct" ] && printf "'%s'" "$(sql_escape "$_rr_ct")" || printf NULL));"
  _state_db_exec "$_rr_db" "$_rr_sql" >/dev/null 2>&1 || return 1
  return 0
}

# ============================================================
# M3.2 — normalizacao contratual para a comparacao campo-a-campo
# ============================================================
#
# O export do state.db (state-rw.sh read) NAO e byte-identico ao state.json de
# origem por tres transformacoes DOCUMENTADAS pelo contrato — nenhuma delas e
# perda de dado. Aplicamos a MESMA normalizacao aos dois lados; qualquer
# divergencia FORA desta lista reprova a migracao (M3.2).
#
# 1. decisions[].wave_id == "init" -> null
#    data-model.md §decision: `wave_id | TEXT | FK -> wave(id), NULL p/ "init"`.
#    Sentinela de decisao registrada antes da primeira onda.
#
# 2. chaves de valor null <-> chave ausente
#    O export emite explicitamente `briefing_cache: null` quando a coluna e
#    NULL, e OMITE `agent_usage: null` (drop_null_keys do _sr_db_read). Ou
#    seja: "ausente" e "null" sao o MESMO estado nos dois formatos. A
#    normalizacao remove recursivamente toda chave de valor null dos dois
#    lados, tornando a comparacao insensivel a essa escolha de representacao.
#
# 3. accumulated_metrics — agregado DERIVADO, recomputado pelo export
#    Todo campo de accumulated_metrics e um contador sobre entidades que a
#    migracao preserva integralmente (waves, decisions, human_blocks,
#    waves[].agent_spawns, waves[].agent_usage, suggestions). Sob state.json
#    ele e um CACHE mantido por incremento; sob state.db ele e recomputado por
#    SELECT a cada leitura. Divergir e esperado (o cache podia estar defasado,
#    e as 9 entidades fechadas em data-model.md nao modelam os agregados
#    agent_*). Nenhum INSUMO se perde — so o cache do agregado. Para nao
#    perder nem isso forensicamente, o objeto accumulated_metrics de ORIGEM e
#    gravado integralmente em migration_run.counts_source.
#
# 4. budgets.current_wave_start / budgets.tool_calls_current_wave — derivados
#    da ONDA ABERTA. Nao ha coluna para eles no schema: o export os calcula
#    com `SELECT ... FROM wave WHERE termination_reason IS NULL` (e
#    _sr_db_set RECUSA grava-los: "campo derivado da onda aberta — nao
#    gravavel diretamente sob backend SQLite"). Com uma onda aberta os dois
#    lados coincidem; numa execucao concluida (nenhuma onda aberta) o
#    state.json ainda carrega o valor da ULTIMA onda, ja obsoleto, enquanto o
#    export corretamente nao produz nenhum. Divergencia de cache defasado, nao
#    de dado migrado.
#
# A lista acima e FECHADA e derivada do contrato — nao um "ajuste ate passar".
# Qualquer divergencia fora dela reprova a migracao (M3.2).
_SDM_NORMALIZE_JQ='
  def drop_nulls:
    walk(if type == "object" then with_entries(select(.value != null)) else . end);
  (.decisions // []) as $d
  | (if ($d | length) > 0
     then .decisions |= map(if .wave_id == "init" then .wave_id = null else . end)
     else . end)
  | del(.accumulated_metrics)
  | (if has("budgets")
     then .budgets |= del(.current_wave_start, .tool_calls_current_wave)
     else . end)
  | drop_nulls
'

# ============================================================
# migrate
# ============================================================

_sdm_cmd_migrate() {
  _SDM_SD=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _SDM_SD=$2; shift 2 ;;
      *) _sdm_die_usage "migrate: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_SDM_SD" ] || _sdm_die_usage "migrate: --state-dir obrigatorio"

  _sdm_require sqlite3
  _sdm_require jq

  [ -d "$_SDM_SD" ] || _sdm_die "migrate: state-dir nao existe: $_SDM_SD" 1
  _SDM_SRC="$_SDM_SD/state.json"
  _SDM_DB="$_SDM_SD/state.db"
  _SDM_STARTED_AT=$(_sdm_iso_now)

  # ---------- M1: pre-condicoes (recusar antes de tocar em qualquer coisa) ----------

  # M1.4 — state.json ausente/ilegivel
  [ -f "$_SDM_SRC" ] || _sdm_refuse "state.json ausente em $_SDM_SD (nada a migrar)"
  jq -e . "$_SDM_SRC" >/dev/null 2>&1 \
    || _sdm_refuse "state.json nao e JSON parseavel (jq -e . '$_SDM_SRC' para localizar o erro)"

  _SDM_EXEC_ID=$(jq -r '.execution.id // ""' "$_SDM_SRC")
  [ -n "$_SDM_EXEC_ID" ] \
    || _sdm_refuse "state.json sem .execution.id — origem nao identificavel (chave de idempotencia, M5)"
  _SDM_SRC_SHA=$(_sdm_sha256_file "$_SDM_SRC")

  # M1.1 — execucao ativa. `aguardando_humano` E PERMITIDO (dec-033): FR-005
  # nomeia so `em_andamento` e admite "pausada"; aguardando_humano esta pausada.
  _sdm_status=$(jq -r '.execution.status // ""' "$_SDM_SRC")
  [ "$_sdm_status" != "em_andamento" ] || _sdm_refuse \
    "execucao ativa (.execution.status = em_andamento) — conclua, aborte (/feature-00c-abort) ou aguarde a pausa antes de migrar (FR-005)"

  # M1.2 — estado invalido. state-validate.sh le state.json DIRETO (nao passa
  # por state-rw.sh), logo continua validando a ORIGEM mesmo quando ja existe
  # state.db. Cobre SC-006/US2 AS-3 (bloqueio humano orfao) sem codigo novo.
  if ! _sdm_val=$("$_SDM_SELF_DIR/state-validate.sh" --state-dir "$_SDM_SD" 2>&1); then
    _sdm_refuse "state.json invalido segundo state-validate.sh: $(printf '%s' "$_sdm_val" | tr '\n' ' ')"
  fi

  # M1.3 — integridade divergente. NAO delegamos a `state-rw.sh sha256-verify`
  # incondicionalmente porque ele e backend-aware: com state.db presente ele
  # verifica o BANCO (PRAGMA integrity_check), nao o state.json de origem —
  # exatamente o oposto do que M1.3 pede numa reexecucao. Comparamos o
  # state.json.sha256 com o hash real da origem (mesma semantica do caminho
  # JSON de sha256-verify).
  _sdm_shafile="$_SDM_SD/state.json.sha256"
  if [ -f "$_sdm_shafile" ]; then
    _sdm_stored=$(head -n 1 -- "$_sdm_shafile" | tr -d '[:space:]')
    [ "$_sdm_stored" = "$_SDM_SRC_SHA" ] || _sdm_refuse \
      "integridade divergente do state.json (stored=$_sdm_stored actual=$_SDM_SRC_SHA) — rode state-rw.sh sha256-update se a mudanca foi legitima, senao investigue tampering"
  fi

  # M1.5 / M5 — state.db pre-existente de OUTRA execucao ⇒ recusar.
  if [ -f "$_SDM_DB" ]; then
    _sdm_prev_id=$(_state_db_exec "$_SDM_DB" "SELECT id FROM execution LIMIT 1;" 2>/dev/null) || _sdm_prev_id=""
    if [ -n "$_sdm_prev_id" ] && [ "$_sdm_prev_id" != "$_SDM_EXEC_ID" ]; then
      _sdm_refuse "state.db existente e de outra execucao (banco=$_sdm_prev_id origem=$_SDM_EXEC_ID) — intervencao humana necessaria (M5)"
    fi
  fi

  # ---------- M2: CONSTRUIR fora (temporario) ----------
  #
  # mktemp -d no PROPRIO state-dir: mesmo filesystem (requisito do mv atomico
  # de M4) e nome aleatorio, NUNCA derivado de PID (primitives.md §C10,
  # finding S4). Um DIRETORIO (nao um arquivo) porque o banco em construcao
  # precisa se chamar exatamente `state.db` para que `state-rw.sh write`
  # resolva o backend SQLite por presenca do arquivo (_sr_backend) e reuse o
  # importador FK-ordenado ja auditado, em vez de duplicar o mapeamento aqui.
  _SDM_TMPDIR=$(mktemp -d -- "$_SDM_SD/.state-db-migrate.XXXXXX") \
    || _sdm_die "migrate: mktemp -d falhou em $_SDM_SD" 1
  _sdm_tmpdb="$_SDM_TMPDIR/state.db"

  # _sdm_abort_build MSG [EXIT] -> descarta o temporario e aborta (M4: nada
  # publicado, state.json intacto). Registra `failed` em migration_run do
  # state.db PRE-EXISTENTE quando houver (M5: "toda tentativa"); numa primeira
  # migracao que falha nao existe banco algum onde registrar — o diagnostico
  # em stderr + exit nao-zero e o registro.
  _sdm_abort_build() {
    if [ -f "$_SDM_DB" ]; then
      _sdm_record_run "$_SDM_DB" failed "$1" '' '' || :
    fi
    rm -rf -- "$_SDM_TMPDIR" 2>/dev/null || :
    _sdm_die "$1" "${2:-1}"
  }

  # M2.2 — schema + PRAGMAs (WAL + chmod 600 aplicados por state-db-schema.sh)
  "$_SDM_SELF_DIR/state-db-schema.sh" create --db "$_sdm_tmpdb" >/dev/null 2>&1 \
    || _sdm_abort_build "migrate: falha ao aplicar o schema no temporario"

  # feature structural-decision-human-gate (task 1.2.4, INV-E3): defesa em
  # profundidade — `create` ja materializa as colunas [NOVO] via o DDL
  # atualizado, mas `ensure` e idempotente/barato e fecha o mesmo dos tres
  # pontos de escrita citados no contrato, sem depender de o DDL nunca
  # divergir do que `ensure` sabe adicionar.
  "$_SDM_SELF_DIR/state-db-schema.sh" ensure --db "$_sdm_tmpdb" >/dev/null 2>&1 \
    || _sdm_abort_build "migrate: falha ao garantir schema aditivo (ensure) no temporario"

  # M2.3 — insercao na ordem imposta pelas FKs:
  #   execution -> wave -> decision -> human_block/skill_invocation/task/event
  #
  # A linha de `execution` entra aqui (o importador de documento faz UPDATE,
  # nao INSERT — ele assume a execucao ja existente). Todas as colunas de
  # budget entram nesta INSERT porque o importador nao as toca. IDs e
  # timestamps ORIGINAIS, sem renumeracao (FR-005 literal).
  _sdm_insert_execution "$_sdm_tmpdb" || _sdm_abort_build "migrate: INSERT da execution falhou"

  # Demais entidades via o importador FK-ordenado ja auditado
  # (_sr_db_write_document, exercitado por tests/test_state-rw.sh).
  if ! _sdm_werr=$("$_SDM_SELF_DIR/state-rw.sh" write --state-dir "$_SDM_TMPDIR" < "$_SDM_SRC" 2>&1); then
    _sdm_abort_build "migrate: importacao das entidades falhou: $(printf '%s' "$_sdm_werr" | tr '\n' ' ')"
  fi

  # ---------- M3: VERIFICAR (falha ⇒ remove o temporario e aborta) ----------

  _sdm_counts_src=$(_sdm_counts_source "$_SDM_SRC")
  _sdm_counts_tgt=$(_sdm_counts_target "$_sdm_tmpdb")

  # M3.1 — contagem por entidade
  if [ "$_sdm_counts_src" != "$_sdm_counts_tgt" ]; then
    _sdm_abort_build "migrate: M3.1 reprovada — contagem por entidade divergente
  origem : $_sdm_counts_src
  destino: $_sdm_counts_tgt"
  fi

  # M3.2 — comparacao campo-a-campo via round-trip (export do banco recem
  # construido vs state.json de origem, ambos canonicalizados e normalizados
  # pelas 3 transformacoes contratuais de _SDM_NORMALIZE_JQ).
  _sdm_exp="$_SDM_TMPDIR/export.json"
  if ! "$_SDM_SELF_DIR/state-rw.sh" read --state-dir "$_SDM_TMPDIR" > "$_sdm_exp" 2>/dev/null; then
    _sdm_abort_build "migrate: M3.2 reprovada — export do banco migrado falhou"
  fi
  _sdm_a="$_SDM_TMPDIR/norm-source.json"
  _sdm_b="$_SDM_TMPDIR/norm-target.json"
  jq -S "$_SDM_NORMALIZE_JQ" "$_SDM_SRC" > "$_sdm_a" 2>/dev/null \
    || _sdm_abort_build "migrate: M3.2 reprovada — normalizacao da origem falhou"
  jq -S "$_SDM_NORMALIZE_JQ" "$_sdm_exp" > "$_sdm_b" 2>/dev/null \
    || _sdm_abort_build "migrate: M3.2 reprovada — normalizacao do export falhou"
  if ! _sdm_diff=$(diff -u "$_sdm_a" "$_sdm_b" 2>&1); then
    _sdm_abort_build "migrate: M3.2 reprovada — export do banco migrado diverge do state.json de origem
$(printf '%s' "$_sdm_diff" | head -n 40)"
  fi

  # M5 — preserva o historico de migration_run do banco anterior (a migracao e
  # reconstrucao TOTAL; sem isso, reexecutar apagaria a trilha de auditoria).
  if [ -f "$_SDM_DB" ]; then
    _sdm_carry_migration_runs "$_SDM_DB" "$_sdm_tmpdb" || :
  fi

  # Registra a tentativa bem-sucedida ANTES de publicar (o banco publicado ja
  # nasce com sua propria evidencia dentro).
  _sdm_record_run "$_sdm_tmpdb" success "" "$_sdm_counts_src" "$_sdm_counts_tgt" || :

  # ---------- M4: PUBLICAR (mv atomico, mesmo filesystem) ----------
  #
  # O -wal/-shm do temporario sao descartaveis: o checkpoint abaixo integra o
  # WAL ao arquivo principal, de modo que o `mv` de um unico arquivo publica um
  # banco completo. Sem isso, mover so o state.db deixaria para tras
  # transacoes ainda no WAL.
  _state_db_exec "$_sdm_tmpdb" "PRAGMA wal_checkpoint(TRUNCATE);" >/dev/null 2>&1 || :
  mv -f -- "$_sdm_tmpdb" "$_SDM_DB" \
    || _sdm_abort_build "migrate: publicacao (mv) falhou — state.json de origem intacto"
  _state_db_secure_perms "$_SDM_DB"
  rm -rf -- "$_SDM_TMPDIR" 2>/dev/null || :

  # M6: state.json, state.json.sha256 e state-history/ permanecem intactos —
  # nenhuma remocao acontece em ponto algum deste script (grep -n 'rm ' cobre
  # so o temporario). O state.json passa a ser export/legado (Decision 9).
  printf '%s: migrate: state.db publicado em %s\n' "$_SDM_NAME" "$_SDM_DB"
  printf '%s: migrate: contagens verificadas (M3.1) %s\n' "$_SDM_NAME" "$_sdm_counts_src"
  printf '%s: migrate: round-trip verificado (M3.2) contra %s\n' "$_SDM_NAME" "$_SDM_SRC"
  printf '%s: migrate: state.json PRESERVADO como export/legado (M6)\n' "$_SDM_NAME"
}

# _sdm_lit_str VALUE -> literal SQL: NULL se vazio, senao 'escapado'.
# (String vazia e NULL sao indistinguiveis aqui de proposito: nenhuma coluna
# de `execution` distingue "ausente" de "vazio" — o export reconstroi ambas
# como ausencia, e a normalizacao M3.2 trata null == ausente.)
_sdm_lit_str() {
  if [ -z "$1" ]; then printf 'NULL'; else printf "'%s'" "$(printf '%s' "$1" | strip_nul | sed "s/'/''/g")"; fi
}

# _sdm_lit_json JSON -> literal SQL: NULL se vazio/`null`, senao 'json'.
_sdm_lit_json() {
  if [ -z "$1" ] || [ "$1" = "null" ]; then printf 'NULL'; else
    printf "'%s'" "$(printf '%s' "$1" | strip_nul | sed "s/'/''/g")"; fi
}

# _sdm_jq_raw FILTER -> extrai texto do state.json de origem ("" se null).
_sdm_jq_raw() { jq -r "$1 // empty" "$_SDM_SRC" 2>/dev/null || printf ''; }
# _sdm_jq_json FILTER -> extrai JSON compacto do state.json de origem.
_sdm_jq_json() { jq -c "$1" "$_SDM_SRC" 2>/dev/null || printf 'null'; }
# _sdm_jq_int FILTER DEFAULT -> extrai inteiro (com default).
_sdm_jq_int() { jq -r "$1 // $2" "$_SDM_SRC" 2>/dev/null || printf '%s' "$2"; }

# _sdm_insert_execution DB -> INSERT da linha unica de `execution`, com todas
# as colunas escalares + blobs JSON, a partir do state.json de origem.
#
# SQL montado em shell (nao em jq) deliberadamente: gerar SQL DENTRO do
# programa jq exigiria aspas simples literais no meio de um script jq
# single-quoted no shell — fonte classica de quebra de quoting. Aqui o jq so
# EXTRAI valores e todo literal passa por strip_nul + escape de aspas
# (primitives.md §C8), igual ao resto do runtime.
_sdm_insert_execution() {
  _ie_db="$1"
  _ie_atomic=$(_sdm_jq_json '.atomic_commit_enabled')
  _ie_atomic_sql="NULL"
  case "$_ie_atomic" in true) _ie_atomic_sql=1 ;; false) _ie_atomic_sql=0 ;; esac

  _ie_sql="INSERT INTO execution (id,schema_version,short_name,target_project_path,\
target_project_description,suggested_stack,status,termination_reason,started_at,\
finished_at,canonical_project,session_name,current_stage,next_instruction,\
atomic_commit_enabled,initial_key_aspects,subagent_depth,max_recursion,\
cycles_consumed_current_stage,max_cycles_per_stage,retro_executions_consumed,\
max_retro_executions_per_feature,tool_calls_threshold_wave,\
wallclock_threshold_seconds,state_size_threshold_bytes,external_urls_whitelist,\
circular_movement_history,prerequisites,briefing_cache,constitution_cache,\
push_pr_result) VALUES ("
  _ie_sql="$_ie_sql$(_sdm_lit_str "$(_sdm_jq_raw '.execution.id')"),"
  _ie_sql="$_ie_sql$(_sdm_lit_str "$(jq -r '.schema_version // "1.0.0"' "$_SDM_SRC")"),"
  _ie_sql="$_ie_sql$(_sdm_lit_str "$(_sdm_jq_raw '.short_name')"),"
  _ie_sql="$_ie_sql$(_sdm_lit_str "$(_sdm_jq_raw '.execution.target_project_path')"),"
  _ie_sql="$_ie_sql$(_sdm_lit_str "$(_sdm_jq_raw '.execution.target_project_description')"),"
  _ie_sql="$_ie_sql$(_sdm_lit_json "$(_sdm_jq_json '.execution.suggested_stack')"),"
  _ie_sql="$_ie_sql$(_sdm_lit_str "$(_sdm_jq_raw '.execution.status')"),"
  _ie_sql="$_ie_sql$(_sdm_lit_str "$(_sdm_jq_raw '.execution.termination_reason')"),"
  _ie_sql="$_ie_sql$(_sdm_lit_str "$(_sdm_jq_raw '.execution.started_at')"),"
  _ie_sql="$_ie_sql$(_sdm_lit_str "$(_sdm_jq_raw '.execution.finished_at')"),"
  _ie_sql="$_ie_sql$(_sdm_lit_str "$(_sdm_jq_raw '.execution.canonical_project')"),"
  _ie_sql="$_ie_sql$(_sdm_lit_str "$(_sdm_jq_raw '.execution.session_name')"),"
  _ie_sql="$_ie_sql$(_sdm_lit_str "$(_sdm_jq_raw '.current_stage')"),"
  _ie_sql="$_ie_sql$(_sdm_lit_str "$(_sdm_jq_raw '.next_instruction')"),"
  _ie_sql="$_ie_sql$_ie_atomic_sql,"
  _ie_sql="$_ie_sql$(_sdm_lit_json "$(_sdm_jq_json '.initial_key_aspects // []')"),"
  _ie_sql="$_ie_sql$(_sdm_jq_int '.budgets.current_subagent_depth' 1),"
  _ie_sql="$_ie_sql$(_sdm_jq_int '.budgets.max_recursion' 3),"
  _ie_sql="$_ie_sql$(_sdm_jq_int '.budgets.cycles_consumed_current_stage' 0),"
  _ie_sql="$_ie_sql$(_sdm_jq_int '.budgets.max_cycles_per_stage' 5),"
  _ie_sql="$_ie_sql$(_sdm_jq_int '.budgets.retro_executions_consumed' 0),"
  _ie_sql="$_ie_sql$(_sdm_jq_int '.budgets.max_retro_executions_per_feature' 2),"
  _ie_sql="$_ie_sql$(_sdm_jq_int '.budgets.tool_calls_threshold_wave' 80),"
  _ie_sql="$_ie_sql$(_sdm_jq_int '.budgets.wallclock_threshold_seconds' 5400),"
  _ie_sql="$_ie_sql$(_sdm_jq_int '.budgets.state_size_threshold_bytes' 1048576),"
  _ie_sql="$_ie_sql$(_sdm_lit_json "$(_sdm_jq_json '.external_urls_whitelist // []')"),"
  _ie_sql="$_ie_sql$(_sdm_lit_json "$(_sdm_jq_json '.circular_movement_history // []')"),"
  _ie_sql="$_ie_sql$(_sdm_lit_json "$(_sdm_jq_json '.prerequisites')"),"
  _ie_sql="$_ie_sql$(_sdm_lit_json "$(_sdm_jq_json '.briefing_cache')"),"
  _ie_sql="$_ie_sql$(_sdm_lit_json "$(_sdm_jq_json '.constitution_cache')"),"
  _ie_sql="$_ie_sql$(_sdm_lit_json "$(_sdm_jq_json '.push_pr_result')"));"

  _state_db_exec_with_retry "$_ie_db" "$_ie_sql" >/dev/null 2>&1 || return 1
  return 0
}

# _sdm_counts_source JSON -> JSON compacto com a contagem das 6 entidades
# listadas em migration.md §M3.1 (chaves em ordem fixa para comparacao literal).
_sdm_counts_source() {
  jq -c '{
    decisions:    (.decisions    // [] | length),
    waves:        (.waves        // [] | length),
    human_blocks: (.human_blocks // [] | length),
    tasks:        (.tasks        // [] | length),
    events:       (.events       // [] | length),
    skill_invocation: ([(.waves // [])[].skills_invoked // [] | .[]] | length)
  }' "$1" 2>/dev/null
}

# _sdm_counts_target DB -> mesmo formato, via COUNT(*) no banco.
_sdm_counts_target() {
  _ct_raw=$(_state_db_exec "$1" "SELECT
    (SELECT count(*) FROM decision) || '|' ||
    (SELECT count(*) FROM wave) || '|' ||
    (SELECT count(*) FROM human_block) || '|' ||
    (SELECT count(*) FROM task_outcome) || '|' ||
    (SELECT count(*) FROM event) || '|' ||
    (SELECT count(*) FROM skill_invocation);" 2>/dev/null) || return 1
  printf '%s' "$_ct_raw" | awk -F'|' '{
    printf "{\"decisions\":%s,\"waves\":%s,\"human_blocks\":%s,\"tasks\":%s,\"events\":%s,\"skill_invocation\":%s}",
      $1,$2,$3,$4,$5,$6 }'
}

# _sdm_carry_migration_runs OLD_DB NEW_DB -> copia migration_run do banco
# anterior para o novo (preserva a trilha de auditoria atraves de reexecucoes).
_sdm_carry_migration_runs() {
  _cm_old="$1"; _cm_new="$2"
  _cm_dump=$(_state_db_exec "$_cm_old" \
    "SELECT 'INSERT INTO migration_run (execution_id,source_path,source_sha256,started_at,finished_at,result,diagnostic,counts_source,counts_target) VALUES (' ||
       quote(execution_id) || ',' || quote(source_path) || ',' || quote(source_sha256) || ',' ||
       quote(started_at) || ',' || quote(finished_at) || ',' || quote(result) || ',' ||
       quote(diagnostic) || ',' || quote(counts_source) || ',' || quote(counts_target) || ');'
     FROM migration_run ORDER BY id;" 2>/dev/null) || return 1
  [ -n "$_cm_dump" ] || return 0
  _state_db_exec "$_cm_new" "$_cm_dump" >/dev/null 2>&1 || return 1
  return 0
}

_sdm_main() {
  [ "$#" -ge 1 ] || _sdm_die_usage "subcomando obrigatorio (migrate)"
  _sdm_sub=$1; shift
  case "$_sdm_sub" in
    migrate) _sdm_cmd_migrate "$@" ;;
    -h|--help|help)
      cat <<'HELP'
state-db-migrate.sh — migracao explicita state.json -> state.db

USO:
  state-db-migrate.sh migrate --state-dir DIR

EXIT CODES:
  0 sucesso   1 falha   2 uso incorreto   3 recusado por pre-condicao (M1)

Nunca roda automaticamente: so por invocacao explicita do operador (FR-005).
O state.json de origem e sempre preservado (M6).
HELP
      exit 0
      ;;
    *) _sdm_die_usage "subcomando desconhecido: $_sdm_sub" ;;
  esac
}

_sdm_main "$@"
