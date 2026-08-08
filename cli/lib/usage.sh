#!/bin/sh
# usage.sh — subcomando `cstk usage` (feature loose-usage-capture, FASE 4).
#
# Consulta o consumo AVULSO (fora de execucoes agente-00c/feature-00c)
# capturado pelo hook `posttooluse-loose-usage.sh` no sidecar
# `~/.claude/cstk/loose-usage/<process_key>/seg-*/`. Este arquivo e o UNICO
# tradutor sidecar->DB (plan.md §Convencoes de Borda "Mapper layer"):
#
#   - `usage_map_sidecar_to_db` (task 4.1): varre os segmentos, invoca
#     `otel-usage.sh delta --state-dir <segmento>` por segmento, converte o
#     JSON `by_model` em linhas `loose_usage` e faz UPSERT pela chave
#     natural (process_key, segment_id, model). Chamado ingest-on-read por
#     `cstk usage`/`cstk usage compare` — best-effort, nunca aborta a
#     listagem.
#   - `usage_cmd_list` (task 4.2): `cstk usage` — listagem por projeto.
#   - `usage_cmd_compare` (task 4.3): `cstk usage compare` — avulso vs
#     pipeline (`loose_usage` vs `wave_model_usage`), agregacao lado a
#     lado, NUNCA JOIN linha a linha (granularidades diferentes).
#   - `usage_cmd_prune` (task 4.4): `cstk usage prune` — poda os segmentos
#     fechados do sidecar mais antigos que o TTL (camada de captura) e as
#     linhas `loose_usage` correspondentes (camada de indice, delegado a
#     `recall_prune_loose_usage` de `cli/lib/recall.sh`).
#
# RESTRICAO DE ARQUITETURA (Constitution II, contracts/cli-usage.md
# §Restricao de arquitetura): este arquivo NUNCA invoca `sqlite3`
# diretamente — toda operacao de banco delega aos helpers ja existentes de
# `cli/lib/recall.sh` (unico arquivo autorizado a `sqlite3`).
#
# Campo nao medido vira NULL/`null`/"nao medido", NUNCA 0 fabricado
# (Principio VI / FR-005 / SC-004) — mesma politica de `wave_model_usage`.
#
# Despachado por cli/cstk: `cstk usage ...` -> usage_main "$@".
#
# POSIX sh puro. Deps OPCIONAIS: sqlite3, jq (ausencia degrada gracioso
# conforme contracts/cli-usage.md §Comportamento sem dados).

if [ -n "${_CSTK_USAGE_LOADED:-}" ]; then
  return 0 2>/dev/null
fi
_CSTK_USAGE_LOADED=1

if [ -n "${CSTK_LIB:-}" ] && [ -f "$CSTK_LIB/common.sh" ]; then
  # shellcheck source=./common.sh
  . "$CSTK_LIB/common.sh"
fi

# recall.sh concentra sql_escape/validate_limit/value_has_nul/strip_nul,
# a camada de conexao (recall_have_sqlite3/recall_have_jq/recall_resolve_db/
# recall_ensure_db_dir/recall_apply_schema/recall_normalize_db_perms/
# recall_query_sql/recall_apply_sql_with_retry), recall_real_or_null/
# recall_int_or_null e recall_prune_loose_usage (task 2.2.1) — usage.sh
# reusa tudo isso em vez de reimplementar (Constitution II).
if [ -n "${CSTK_LIB:-}" ] && [ -f "$CSTK_LIB/recall.sh" ]; then
  # shellcheck source=./recall.sh
  . "$CSTK_LIB/recall.sh"
fi

if ! command -v log_warn >/dev/null 2>&1; then
  log_info() { printf '[info] %s\n' "$*" >&2; }
  log_warn() { printf '[warn] %s\n' "$*" >&2; }
  log_error() { printf '[error] %s\n' "$*" >&2; }
fi

# Locale pinado: este arquivo formata float (awk printf de share_pct/blended
# em _usage_share_pct_text/_usage_blended). Sob locale pt_BR o printf de
# float produz virgula decimal ("50,000000") em vez de ponto — mesmo bug
# real ja corrigido em otel-usage.sh (linha 120/114-118: 2 cenarios de
# test_otel-usage falhavam para operadores com LANG=pt_BR.UTF-8). Pinar aqui
# protege PRODUCAO (CLI rodando no shell do operador), nao so os testes.
LC_ALL=C
export LC_ALL

# ==== Exit codes (contracts/cli-usage.md) ====
USAGE_EXIT_OK=0
USAGE_EXIT_ERROR=1
USAGE_EXIT_USAGE=2

# ==== Usage text ====
_usage_usage_text() {
  cat <<'USAGETXT'
cstk usage — consumo avulso (fora de execucoes agente-00c/feature-00c)

USO:
  cstk usage [--project P] [--since ISO] [--limit N] [--json] [--db PATH]
  cstk usage compare [--project P] [--since ISO] [--json] [--db PATH]
  cstk usage prune [--dry-run] [--older-than-days N] [--db PATH]

LISTAGEM (default): uma secao por projeto, uma linha por modelo (modelo,
  tokens, custo, participacao). Campo sem medicao imprime "nao medido".
  --project P        default: projeto do diretorio corrente
  --since ISO        filtra por captured_at >= ISO
  --limit N          maximo de modelos (default 20; inteiro positivo)
  --json             saida maquina-legivel
  --db PATH          indice (default $CSTK_KNOWLEDGE_DB ou ~/.claude/cstk/knowledge.db)

COMPARE: mix de modelos e custo blended (avulso vs pipeline), lado a lado.
  Mesmas flags de listagem, exceto --limit (nao aplicavel).

PRUNE: poda segmentos fechados do sidecar + linhas de indice acima do TTL.
  --dry-run              reporta sem remover
  --older-than-days N    default $CSTK_LOOSE_USAGE_RETENTION_DAYS ou 90
  --db PATH              indice

Documentacao: docs/specs/loose-usage-capture/contracts/cli-usage.md
USAGETXT
}

# ==========================================================================
# Helpers de filesystem (sidecar) — task 4.1
# ==========================================================================

# _usage_sidecar_root -> imprime a raiz do sidecar de captura avulsa.
_usage_sidecar_root() {
  printf '%s/.claude/cstk/loose-usage\n' "${HOME:-/tmp}"
}

# _usage_project_from_cwd -> imprime o basename do diretorio corrente
# (default de --project, contracts/cli-usage.md).
_usage_project_from_cwd() {
  basename -- "$(pwd)" 2>/dev/null
}

# _usage_runtime_script_path NAME -> imprime o path do script NAME do
# runtime agente-00c-runtime. Mesmo padrao de _mcp_runtime_script_path
# (cli/lib/mcp.sh): (1) PATH; (2) layout de repo relativo a CSTK_LIB;
# (3) layout instalado em ~/.claude.
_usage_runtime_script_path() {
  _urs_name=$1
  if command -v "$_urs_name" >/dev/null 2>&1; then
    command -v "$_urs_name"
    return 0
  fi
  if [ -n "${CSTK_LIB:-}" ]; then
    _urs_repo="$CSTK_LIB/../../plugins/cstk/skills/agente-00c-runtime/scripts/$_urs_name"
    if [ -f "$_urs_repo" ]; then
      printf '%s\n' "$_urs_repo"
      return 0
    fi
  fi
  _urs_default="${HOME:-/tmp}/.claude/skills/agente-00c-runtime/scripts/$_urs_name"
  if [ -f "$_urs_default" ]; then
    printf '%s\n' "$_urs_default"
    return 0
  fi
  return 1
}

# _usage_file_mtime_epoch FILE -> epoch da ultima modificacao, ou vazio.
# GNU (-c '%Y') primeiro, fallback BSD (-f '%m') — mesmo padrao GNU-first
# de recall_normalize_db_perms.
_usage_file_mtime_epoch() {
  stat -c '%Y' -- "$1" 2>/dev/null || stat -f '%m' -- "$1" 2>/dev/null || return 1
}

# _usage_epoch_to_iso EPOCH -> ISO 8601 UTC. GNU (-d @EPOCH) primeiro,
# fallback BSD (-r EPOCH) — mesma tecnica de _plu_iso_to_epoch invertida.
_usage_epoch_to_iso() {
  date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null
}

# _usage_segment_latest_epoch SEG_DIR -> epoch do arquivo mais recente entre
# closed/otel-end.tsv/otel-start.tsv (nao existe timestamp per-segmento
# persistido no sidecar: meta.tsv so guarda o current_segment do processo).
# Deriva de um fato observavel do filesystem (mtime real), nunca fabrica.
_usage_segment_latest_epoch() {
  _usle_dir="$1"
  _usle_latest=0
  for _usle_f in "$_usle_dir/closed" "$_usle_dir/otel-end.tsv" "$_usle_dir/otel-start.tsv"; do
    [ -f "$_usle_f" ] || continue
    _usle_e=$(_usage_file_mtime_epoch "$_usle_f") || continue
    case "$_usle_e" in ''|*[!0-9]*) continue ;; esac
    if [ "$_usle_e" -gt "$_usle_latest" ]; then _usle_latest=$_usle_e; fi
  done
  [ "$_usle_latest" -gt 0 ] || return 1
  printf '%s\n' "$_usle_latest"
}

# _usage_segment_captured_at SEG_DIR -> ISO 8601 UTC (data-model.md
# §Entity LooseUsageRecord campo captured_at).
_usage_segment_captured_at() {
  _usca_epoch=$(_usage_segment_latest_epoch "$1") || return 1
  _usage_epoch_to_iso "$_usca_epoch"
}

# _usage_meta_get META_FILE FIELD -> valor da chave em meta.tsv (formato
# chave<TAB>valor) — mesmo padrao de _plu_meta_get do hook.
_usage_meta_get() {
  [ -f "$1" ] || return 1
  awk -F '\t' -v k="$2" '$1==k {print $2; found=1} END {exit !found}' "$1" 2>/dev/null
}

# ==========================================================================
# Task 4.1 — Mapper sidecar -> DB
# ==========================================================================

# usage_map_sidecar_to_db DB_PATH -> varre `~/.claude/cstk/loose-usage/*/
# seg-*/`, invoca `otel-usage.sh delta` por segmento e faz UPSERT das linhas
# `loose_usage` correspondentes. Best-effort/ingest-on-read: qualquer
# degradacao (sidecar ausente, otel-usage.sh irresolvivel, jq ausente,
# delta null) e no-op silencioso, NUNCA aborta o caller. Assume que o DB
# JA tem o schema aplicado (caller chama recall_apply_schema antes).
usage_map_sidecar_to_db() {
  _umd_db="$1"
  _umd_root=$(_usage_sidecar_root)
  [ -d "$_umd_root" ] || return 0

  _umd_otel=$(_usage_runtime_script_path otel-usage.sh) || {
    log_warn "cstk usage: otel-usage.sh nao resolvido; mapeamento sidecar->DB pulado"
    return 0
  }
  recall_have_jq || return 0

  _umd_now=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || return 0

  for _umd_proc_dir in "$_umd_root"/*/; do
    [ -d "$_umd_proc_dir" ] || continue
    _umd_process_key=$(basename -- "${_umd_proc_dir%/}")
    _umd_meta="${_umd_proc_dir}meta.tsv"
    _umd_proj_path=$(_usage_meta_get "$_umd_meta" project_path) || _umd_proj_path=""
    _umd_proj_path=$(printf '%s' "$_umd_proj_path" | strip_nul)
    [ -n "$_umd_proj_path" ] || continue
    _umd_project=$(basename -- "$_umd_proj_path")
    [ -n "$_umd_project" ] || continue

    for _umd_seg_dir in "${_umd_proc_dir}"seg-*/; do
      [ -d "$_umd_seg_dir" ] || continue
      _umd_seg_id=$(basename -- "${_umd_seg_dir%/}")
      _umd_open=1
      [ -f "${_umd_seg_dir}closed" ] && _umd_open=0

      _umd_captured=$(_usage_segment_captured_at "$_umd_seg_dir") || continue

      _umd_delta=$("$_umd_otel" delta --state-dir "${_umd_seg_dir%/}" 2>/dev/null) || _umd_delta="null"
      [ -n "$_umd_delta" ] || _umd_delta="null"
      [ "$_umd_delta" != "null" ] || continue

      _umd_models=$(printf '%s' "$_umd_delta" | jq -r '(.by_model // {}) | keys[]' 2>/dev/null) || _umd_models=""
      [ -n "$_umd_models" ] || continue

      _umd_sql=""
      _umd_OLDIFS="$IFS"
      IFS='
'
      for _umd_model in $_umd_models; do
        _umd_model=$(printf '%s' "$_umd_model" | strip_nul)
        [ -n "$_umd_model" ] || continue
        _umd_cost=$(printf '%s' "$_umd_delta" | jq -r --arg m "$_umd_model" '.by_model[$m].cost_usd // ""' 2>/dev/null) || _umd_cost=""
        _umd_tok=$(printf '%s' "$_umd_delta" | jq -r --arg m "$_umd_model" '.by_model[$m].total_tokens // ""' 2>/dev/null) || _umd_tok=""
        _umd_cost=$(printf '%s' "$_umd_cost" | strip_nul)
        _umd_tok=$(printf '%s' "$_umd_tok" | strip_nul)
        _umd_cost_sql=$(recall_real_or_null "$_umd_cost")
        _umd_tok_sql=$(recall_int_or_null "$_umd_tok")
        _umd_sql="$_umd_sql
INSERT INTO loose_usage(project,project_path,process_key,segment_id,model,cost_usd,total_tokens,segment_open,captured_at,ingested_at)
VALUES('$(sql_escape "$_umd_project")','$(sql_escape "$_umd_proj_path")','$(sql_escape "$_umd_process_key")','$(sql_escape "$_umd_seg_id")','$(sql_escape "$_umd_model")',$_umd_cost_sql,$_umd_tok_sql,$_umd_open,'$(sql_escape "$_umd_captured")','$(sql_escape "$_umd_now")')
ON CONFLICT(process_key,segment_id,model) DO UPDATE SET project=excluded.project,project_path=excluded.project_path,cost_usd=excluded.cost_usd,total_tokens=excluded.total_tokens,segment_open=excluded.segment_open,captured_at=excluded.captured_at,ingested_at=excluded.ingested_at;"
      done
      IFS="$_umd_OLDIFS"
      [ -n "$_umd_sql" ] && recall_apply_sql_with_retry "$_umd_db" "$_umd_sql" >/dev/null 2>&1
    done
  done
  return 0
}

# _usage_prepare_db DB_FLAG -> resolve o DB, garante schema+permissao e roda
# o mapper ingest-on-read. Best-effort: falha de schema/dir nao aborta —
# a listagem segue com o DB no estado em que estiver (possivelmente vazio).
# Imprime o path resolvido em stdout.
_usage_prepare_db() {
  _upd_db=$(recall_resolve_db "$1")
  if recall_ensure_db_dir "$_upd_db" && recall_apply_schema "$_upd_db" >/dev/null 2>&1; then
    recall_normalize_db_perms "$_upd_db"
    usage_map_sidecar_to_db "$_upd_db"
  fi
  printf '%s\n' "$_upd_db"
}

# ==========================================================================
# Renderizacao compartilhada (texto + --json)
# ==========================================================================

# _usage_share_pct MODEL_TOKENS TOTAL_TOKENS -> "NN.N%" ou "nao medido".
_usage_share_pct_text() {
  _uspt_m="$1"; _uspt_t="$2"
  if [ -n "$_uspt_m" ] && [ -n "$_uspt_t" ] && [ "$_uspt_t" != "0" ]; then
    awk -v m="$_uspt_m" -v t="$_uspt_t" 'BEGIN{printf "%.1f%%", (m/t)*100}'
  else
    printf 'nao medido'
  fi
}

# _usage_render_text_rows PROJECT ROWS TOTAL_TOKENS -> texto por modelo.
# ROWS: linhas "model|@|cost|@|tokens" (recall_query_sql .separator |@|).
_usage_render_text_rows() {
  _urtr_project="$1"; _urtr_rows="$2"; _urtr_total="$3"
  printf 'projeto: %s\n' "$_urtr_project"
  if [ -z "$_urtr_rows" ]; then
    printf '  nao medido — sem cobertura de captura\n'
    return 0
  fi
  printf '%s\n' "$_urtr_rows" | while IFS= read -r _urtr_line; do
    [ -n "$_urtr_line" ] || continue
    _urtr_m=$(printf '%s' "$_urtr_line" | awk -F '\\|@\\|' '{print $1}')
    _urtr_c=$(printf '%s' "$_urtr_line" | awk -F '\\|@\\|' '{print $2}')
    _urtr_t=$(printf '%s' "$_urtr_line" | awk -F '\\|@\\|' '{print $3}')
    [ -n "$_urtr_m" ] || _urtr_m="(desconhecido)"
    _urtr_c_disp="nao medido"
    [ -n "$_urtr_c" ] && _urtr_c_disp=$(printf '$%s' "$_urtr_c")
    _urtr_t_disp="nao medido"
    [ -n "$_urtr_t" ] && _urtr_t_disp="$_urtr_t"
    _urtr_share=$(_usage_share_pct_text "$_urtr_t" "$_urtr_total")
    printf '  %-24s tokens=%-12s custo=%-12s participacao=%s\n' \
      "$_urtr_m" "$_urtr_t_disp" "$_urtr_c_disp" "$_urtr_share"
  done
}

# _usage_rows_to_json_models ROWS TOTAL_TOKENS -> array JSON [{model,
# total_tokens, cost_usd[, share_pct]}]. share_pct so entra quando
# TOTAL_TOKENS != "" (contrato: `cstk usage --json` nao inclui share_pct,
# `cstk usage compare --json` inclui via chamada com TOTAL_TOKENS).
_usage_rows_to_json_models() {
  _urtjm_rows="$1"
  _urtjm_total="${2:-}"
  if [ -z "$_urtjm_rows" ]; then
    printf '[]'
    return 0
  fi
  _urtjm_tot_json="null"
  [ -n "$_urtjm_total" ] && _urtjm_tot_json="$_urtjm_total"
  printf '%s\n' "$_urtjm_rows" \
    | awk -F '\\|@\\|' '{print $1"\t"$2"\t"$3}' \
    | jq -R -s --argjson tot "$_urtjm_tot_json" '
        [ split("\n")[] | select(length>0) | split("\t")
          | {model: .[0],
             cost_usd: (if .[1]=="" then null else (.[1]|tonumber) end),
             total_tokens: (if .[2]=="" then null else (.[2]|tonumber) end)}
          | if $tot != null then
              . + {share_pct: (if (.total_tokens != null and ($tot|tonumber) != 0)
                                then ((.total_tokens / ($tot|tonumber)) * 100) else null end)}
            else . end
        ]
      ' 2>/dev/null
}

# ==========================================================================
# Task 4.2 — `cstk usage` (listagem por projeto)
# ==========================================================================

usage_cmd_list() {
  _ul_project=""
  _ul_since=""
  _ul_limit="20"
  _ul_json=0
  _ul_db_flag=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --project) shift; _ul_project="${1:-}" ;;
      --since) shift; _ul_since="${1:-}" ;;
      --limit) shift; _ul_limit="${1:-}" ;;
      --json) _ul_json=1 ;;
      --db) shift; _ul_db_flag="${1:-}" ;;
      -h|--help) _usage_usage_text; return "$USAGE_EXIT_OK" ;;
      *) log_error "cstk usage: flag invalida: $1"; return "$USAGE_EXIT_USAGE" ;;
    esac
    shift || break
  done

  for _ul_in in "$_ul_project" "$_ul_since" "$_ul_db_flag"; do
    if value_has_nul "$_ul_in"; then
      log_error "cstk usage: byte NUL em input rejeitado"
      return "$USAGE_EXIT_USAGE"
    fi
  done

  if ! validate_limit "$_ul_limit"; then
    log_error "cstk usage: --limit deve ser inteiro positivo (recebido: '$_ul_limit')"
    return "$USAGE_EXIT_USAGE"
  fi

  [ -n "$_ul_project" ] || _ul_project=$(_usage_project_from_cwd)

  if ! recall_have_sqlite3; then
    log_warn "cstk usage: sqlite3 nao instalado; consumo avulso indisponivel"
    return "$USAGE_EXIT_ERROR"
  fi

  # Ingest-on-read (best-effort): tenta preparar/popular o indice a partir
  # do sidecar ANTES de checar ausencia — cobre o caso "primeira consulta
  # nunca houve execucao 00c anterior", quando knowledge.db ainda nao
  # existe. Se apos a tentativa o arquivo continuar ausente (sqlite3 OK mas
  # dir nao-gravavel, por exemplo), degrada para "nao medido" (FR-005).
  _ul_db=$(_usage_prepare_db "$_ul_db_flag")
  if [ ! -f "$_ul_db" ]; then
    log_warn "cstk usage: indice ausente ($_ul_db); rode com telemetria ativa para popular"
    if [ "$_ul_json" -eq 1 ] && recall_have_jq; then
      jq -n --arg proj "$_ul_project" '{project: $proj, category: "loose", models: []}'
    else
      printf 'projeto: %s\n' "$_ul_project"
      printf '  nao medido\n'
    fi
    return "$USAGE_EXIT_OK"
  fi

  _ul_where="WHERE project = '$(sql_escape "$_ul_project")'"
  [ -n "$_ul_since" ] && _ul_where="$_ul_where AND captured_at >= '$(sql_escape "$_ul_since")'"

  _ul_rows=$(recall_query_sql "$_ul_db" ".mode list
.separator |@|
SELECT model, SUM(cost_usd), SUM(total_tokens)
FROM loose_usage
$_ul_where
GROUP BY model
ORDER BY SUM(total_tokens) DESC
LIMIT $_ul_limit;") || _ul_rows=""

  _ul_total=$(recall_query_sql "$_ul_db" "SELECT SUM(total_tokens) FROM loose_usage $_ul_where;") || _ul_total=""

  if [ "$_ul_json" -eq 1 ]; then
    if recall_have_jq; then
      _ul_models_json=$(_usage_rows_to_json_models "$_ul_rows")
      [ -n "$_ul_models_json" ] || _ul_models_json="[]"
      jq -n --arg proj "$_ul_project" --argjson models "$_ul_models_json" \
        '{project: $proj, category: "loose", models: $models}'
    else
      log_warn "cstk usage: jq ausente; --json indisponivel, usando texto"
      _usage_render_text_rows "$_ul_project" "$_ul_rows" "$_ul_total"
    fi
  else
    _usage_render_text_rows "$_ul_project" "$_ul_rows" "$_ul_total"
  fi
  return "$USAGE_EXIT_OK"
}

# ==========================================================================
# Task 4.3 — `cstk usage compare` (avulso vs pipeline)
# ==========================================================================

usage_cmd_compare() {
  _uc_project=""
  _uc_since=""
  _uc_json=0
  _uc_db_flag=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --project) shift; _uc_project="${1:-}" ;;
      --since) shift; _uc_since="${1:-}" ;;
      --json) _uc_json=1 ;;
      --db) shift; _uc_db_flag="${1:-}" ;;
      -h|--help) _usage_usage_text; return "$USAGE_EXIT_OK" ;;
      *) log_error "cstk usage compare: flag invalida: $1"; return "$USAGE_EXIT_USAGE" ;;
    esac
    shift || break
  done

  for _uc_in in "$_uc_project" "$_uc_since" "$_uc_db_flag"; do
    if value_has_nul "$_uc_in"; then
      log_error "cstk usage compare: byte NUL em input rejeitado"
      return "$USAGE_EXIT_USAGE"
    fi
  done

  [ -n "$_uc_project" ] || _uc_project=$(_usage_project_from_cwd)

  if ! recall_have_sqlite3; then
    log_warn "cstk usage compare: sqlite3 nao instalado; consumo indisponivel"
    return "$USAGE_EXIT_ERROR"
  fi

  # Ingest-on-read (best-effort), mesma logica de usage_cmd_list: sempre
  # tenta preparar/popular o indice antes de consultar (cobre o caso
  # "primeira consulta, knowledge.db ainda nao existe").
  _uc_db=$(_usage_prepare_db "$_uc_db_flag")

  _uc_loose_where="WHERE project = '$(sql_escape "$_uc_project")'"
  [ -n "$_uc_since" ] && _uc_loose_where="$_uc_loose_where AND captured_at >= '$(sql_escape "$_uc_since")'"
  _uc_pipe_where="WHERE project = '$(sql_escape "$_uc_project")'"
  [ -n "$_uc_since" ] && _uc_pipe_where="$_uc_pipe_where AND source_ts >= '$(sql_escape "$_uc_since")'"

  _uc_loose_rows=""
  _uc_pipe_rows=""
  _uc_loose_total=""
  _uc_pipe_total=""
  _uc_loose_cost=""
  _uc_pipe_cost=""
  if [ -f "$_uc_db" ]; then
    _uc_loose_rows=$(recall_query_sql "$_uc_db" ".mode list
.separator |@|
SELECT model, SUM(cost_usd), SUM(total_tokens) FROM loose_usage $_uc_loose_where GROUP BY model ORDER BY model;") || _uc_loose_rows=""
    _uc_pipe_rows=$(recall_query_sql "$_uc_db" ".mode list
.separator |@|
SELECT model, SUM(cost_usd), SUM(total_tokens) FROM wave_model_usage $_uc_pipe_where GROUP BY model ORDER BY model;") || _uc_pipe_rows=""
    _uc_loose_totals_raw=$(recall_query_sql "$_uc_db" ".mode list
.separator |@|
SELECT SUM(cost_usd), SUM(total_tokens) FROM loose_usage $_uc_loose_where;") || _uc_loose_totals_raw=""
    _uc_pipe_totals_raw=$(recall_query_sql "$_uc_db" ".mode list
.separator |@|
SELECT SUM(cost_usd), SUM(total_tokens) FROM wave_model_usage $_uc_pipe_where;") || _uc_pipe_totals_raw=""
    _uc_loose_cost=$(printf '%s' "$_uc_loose_totals_raw" | awk -F '\\|@\\|' '{print $1}')
    _uc_loose_total=$(printf '%s' "$_uc_loose_totals_raw" | awk -F '\\|@\\|' '{print $2}')
    _uc_pipe_cost=$(printf '%s' "$_uc_pipe_totals_raw" | awk -F '\\|@\\|' '{print $1}')
    _uc_pipe_total=$(printf '%s' "$_uc_pipe_totals_raw" | awk -F '\\|@\\|' '{print $2}')
  fi

  _uc_loose_blended=$(_usage_blended "$_uc_loose_cost" "$_uc_loose_total")
  _uc_pipe_blended=$(_usage_blended "$_uc_pipe_cost" "$_uc_pipe_total")

  if [ "$_uc_json" -eq 1 ] && recall_have_jq; then
    _uc_loose_models=$(_usage_rows_to_json_models "$_uc_loose_rows" "${_uc_loose_total:-}")
    _uc_pipe_models=$(_usage_rows_to_json_models "$_uc_pipe_rows" "${_uc_pipe_total:-}")
    [ -n "$_uc_loose_models" ] || _uc_loose_models="[]"
    [ -n "$_uc_pipe_models" ] || _uc_pipe_models="[]"
    jq -n \
      --arg proj "$_uc_project" \
      --argjson loose_models "$_uc_loose_models" \
      --argjson pipe_models "$_uc_pipe_models" \
      --arg loose_blended "$_uc_loose_blended" \
      --arg pipe_blended "$_uc_pipe_blended" \
      '{
        project: $proj,
        categories: [
          { category: "loose", models: $loose_models,
            blended_cost_per_mtok: (if $loose_blended == "" then null else ($loose_blended | tonumber) end) },
          { category: "pipeline", models: $pipe_models,
            blended_cost_per_mtok: (if $pipe_blended == "" then null else ($pipe_blended | tonumber) end) }
        ]
      }'
  else
    [ "$_uc_json" -eq 1 ] && log_warn "cstk usage compare: jq ausente; --json indisponivel, usando texto"
    printf 'projeto: %s\n' "$_uc_project"
    printf '== loose ==\n'
    _usage_render_text_rows "$_uc_project" "$_uc_loose_rows" "$_uc_loose_total" | tail -n +2
    printf '  blended_cost_per_mtok=%s\n' "${_uc_loose_blended:-nao medido}"
    printf '== pipeline ==\n'
    _usage_render_text_rows "$_uc_project" "$_uc_pipe_rows" "$_uc_pipe_total" | tail -n +2
    printf '  blended_cost_per_mtok=%s\n' "${_uc_pipe_blended:-nao medido}"
  fi
  return "$USAGE_EXIT_OK"
}

# _usage_blended COST TOKENS -> "SUM(cost)/SUM(tokens)*1e6" ou "" quando
# TOKENS ausente/0 (divisao indefinida nunca vira 0 — Principio VI).
_usage_blended() {
  _ub_cost="$1"; _ub_tok="$2"
  if [ -z "$_ub_cost" ] || [ -z "$_ub_tok" ] || [ "$_ub_tok" = "0" ]; then
    printf ''
    return 0
  fi
  awk -v c="$_ub_cost" -v t="$_ub_tok" 'BEGIN{printf "%.6f", (c/t)*1000000}'
}

# ==========================================================================
# Task 4.4 — `cstk usage prune` (retencao/expurgo)
# ==========================================================================

usage_cmd_prune() {
  _up_dry=0
  _up_days_flag=""
  _up_db_flag=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run) _up_dry=1 ;;
      --older-than-days) shift; _up_days_flag="${1:-}" ;;
      --db) shift; _up_db_flag="${1:-}" ;;
      -h|--help) _usage_usage_text; return "$USAGE_EXIT_OK" ;;
      *) log_error "cstk usage prune: flag invalida: $1"; return "$USAGE_EXIT_USAGE" ;;
    esac
    shift || break
  done

  _up_days="$_up_days_flag"
  [ -n "$_up_days" ] || _up_days="${CSTK_LOOSE_USAGE_RETENTION_DAYS:-90}"
  case "$_up_days" in
    ''|*[!0-9]*)
      log_error "cstk usage prune: --older-than-days deve ser inteiro (recebido: '$_up_days')"
      return "$USAGE_EXIT_USAGE"
      ;;
  esac

  if value_has_nul "$_up_db_flag"; then
    log_error "cstk usage prune: byte NUL em input rejeitado"
    return "$USAGE_EXIT_USAGE"
  fi

  if ! recall_have_sqlite3; then
    log_warn "cstk usage prune: sqlite3 nao instalado; poda da camada de indice indisponivel"
    return "$USAGE_EXIT_ERROR"
  fi

  _up_root=$(_usage_sidecar_root)
  if [ ! -d "$_up_root" ]; then
    log_warn "cstk usage prune: sidecar ausente ($_up_root)"
    printf 'nada a podar\n'
    return "$USAGE_EXIT_OK"
  fi

  _up_now_epoch=$(date -u +%s 2>/dev/null) || _up_now_epoch=""
  _up_cutoff_epoch=""
  if [ -n "$_up_now_epoch" ]; then
    _up_cutoff_epoch=$((_up_now_epoch - _up_days * 86400))
  fi

  _up_list=$(mktemp 2>/dev/null) || {
    log_error "cstk usage prune: mktemp falhou"
    return "$USAGE_EXIT_ERROR"
  }
  _up_eligible=0

  for _up_proc_dir in "$_up_root"/*/; do
    [ -d "$_up_proc_dir" ] || continue
    _up_process_key=$(basename -- "${_up_proc_dir%/}")
    for _up_seg_dir in "${_up_proc_dir}"seg-*/; do
      [ -d "$_up_seg_dir" ] || continue
      [ -f "${_up_seg_dir}closed" ] || continue
      _up_seg_id=$(basename -- "${_up_seg_dir%/}")
      _up_seg_epoch=$(_usage_segment_latest_epoch "$_up_seg_dir") || continue
      if [ -n "$_up_cutoff_epoch" ] && [ "$_up_seg_epoch" -lt "$_up_cutoff_epoch" ] 2>/dev/null; then
        printf '%s\t%s\t%s\n' "$_up_process_key" "$_up_seg_id" "${_up_seg_dir%/}" >> "$_up_list"
        _up_eligible=$((_up_eligible + 1))
      fi
    done
  done

  if [ "$_up_eligible" -eq 0 ]; then
    rm -f -- "$_up_list"
    printf 'nada a podar — sem segmentos alem do TTL\n'
    return "$USAGE_EXIT_OK"
  fi

  _up_db=$(recall_resolve_db "$_up_db_flag")
  _up_tab=$(printf '\t')

  while IFS="$_up_tab" read -r _up_pk _up_sid _up_dir; do
    [ -n "$_up_pk" ] || continue
    if [ "$_up_dry" -eq 1 ]; then
      printf 'action=would-remove process_key=%s segment=%s\n' "$_up_pk" "$_up_sid"
    else
      if rm -rf -- "$_up_dir" 2>/dev/null; then
        printf 'action=removed process_key=%s segment=%s\n' "$_up_pk" "$_up_sid"
      else
        printf 'action=remove-failed process_key=%s segment=%s\n' "$_up_pk" "$_up_sid"
      fi
    fi
  done < "$_up_list"
  rm -f -- "$_up_list"

  if [ "$_up_dry" -eq 1 ]; then
    _up_db_n=$(recall_prune_loose_usage "$_up_db" "$_up_days" --dry-run) || _up_db_n="0"
    printf 'total: %d segmentos elegiveis (dry-run), %s linhas de indice elegiveis\n' "$_up_eligible" "$_up_db_n"
  else
    _up_db_n=$(recall_prune_loose_usage "$_up_db" "$_up_days") || _up_db_n="0"
    printf 'total: %d segmentos removidos, %s linhas de indice removidas\n' "$_up_eligible" "$_up_db_n"
  fi
  return "$USAGE_EXIT_OK"
}

# ==========================================================================
# Task 4.5 — Dispatcher
# ==========================================================================

usage_main() {
  _um_sub="${1:-}"
  case "$_um_sub" in
    compare)
      shift
      usage_cmd_compare "$@"
      return $?
      ;;
    prune)
      shift
      usage_cmd_prune "$@"
      return $?
      ;;
    -h|--help)
      _usage_usage_text
      return "$USAGE_EXIT_OK"
      ;;
    ''|--*)
      usage_cmd_list "$@"
      return $?
      ;;
    *)
      log_error "cstk usage: subcomando/flag desconhecido: $_um_sub"
      _usage_usage_text
      return "$USAGE_EXIT_USAGE"
      ;;
  esac
}
