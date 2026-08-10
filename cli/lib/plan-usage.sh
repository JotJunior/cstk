#!/bin/sh
# plan-usage.sh — subcomando `cstk plan-usage` (feature plan-usage-capture).
#
# Camada SQL do gauge de uso do plano (rate_limits do payload da
# statusline), delegada integralmente a `cli/lib/recall.sh` (unico arquivo
# autorizado a `sqlite3` — Constitution II / research.md Decision 6).
#
# `plan_usage_cmd_ingest_stdin` (task 4.3) e o subcomando INTERNO
# `cstk plan-usage ingest --stdin`, consumido exclusivamente por
# `plugins/cstk/skills/agente-00c-runtime/hooks/statusline-plan-usage.sh`
# (research.md Decision 6): recebe o payload BRUTO da statusline via stdin,
# extrai `rate_limits.<scope>.*` via `jq`, aplica o throttle de FR-010
# (research.md Decision 4: compara contra o ULTIMO registro persistido do
# escopo, sem cache auxiliar) e delega o INSERT a
# `recall_plan_usage_insert()` (cli/lib/recall.sh). Exit SEMPRE 0, mesmo em
# erro interno (task 4.3.3) — nunca propaga falha para a sessao do
# operador que renderiza a statusline (Principio IV).
#
# Ausencia total de `rate_limits` no payload -> NENHUM INSERT (dec-029);
# ausencia PARCIAL (escopo presente mas campo ausente dentro dele) ->
# INSERT com NULL explicito, nunca 0 fabricado (Principio VI).
#
# `plan_usage_cmd_show` (task 4.1) e `plan_usage_cmd_history` (task 4.2)
# sao a consulta PUBLICA (`cstk plan-usage` / `cstk plan-usage history`,
# FASE 4.1/4.2) — leitura pura via recall_query_sql, sem sqlite3 direto
# (Constitution II). NULL vira "nao medido" no texto e `null` JSON, nunca
# `0` fabricado (Principio VI/dec-029/SC-002). `history` reusa
# literalmente `--limit`/`--since` de `cstk usage` (dec-014, sem
# convencao nova de paginacao).
#
# Despachado por cli/cstk: `cstk plan-usage ...` -> plan_usage_main "$@".
#
# POSIX sh puro. Deps OPCIONAIS: sqlite3, jq (ausencia degrada gracioso,
# mesma disciplina de usage.sh/recall.sh).

if [ -n "${_CSTK_PLAN_USAGE_LOADED:-}" ]; then
  return 0 2>/dev/null
fi
_CSTK_PLAN_USAGE_LOADED=1

if [ -n "${CSTK_LIB:-}" ] && [ -f "$CSTK_LIB/common.sh" ]; then
  # shellcheck source=./common.sh
  . "$CSTK_LIB/common.sh"
fi

# recall.sh concentra sql_escape, a camada de conexao
# (recall_have_sqlite3/recall_have_jq/recall_resolve_db/
# recall_ensure_db_dir/recall_apply_schema/recall_normalize_db_perms/
# recall_apply_sql_with_retry), recall_real_or_null/recall_int_or_null e
# recall_plan_usage_insert (task 1.2) — plan-usage.sh reusa tudo isso em
# vez de reimplementar (Constitution II).
if [ -n "${CSTK_LIB:-}" ] && [ -f "$CSTK_LIB/recall.sh" ]; then
  # shellcheck source=./recall.sh
  . "$CSTK_LIB/recall.sh"
fi

if ! command -v log_warn >/dev/null 2>&1; then
  log_info() { printf '[info] %s\n' "$*" >&2; }
  log_warn() { printf '[warn] %s\n' "$*" >&2; }
  log_error() { printf '[error] %s\n' "$*" >&2; }
fi

_pu_now_iso() {
  date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf '1970-01-01T00:00:00Z'
}

# _pu_last_scope_row DB SCOPE -> "used_percentage|resets_at" do ULTIMO
# registro persistido daquele escopo. Confinamento sqlite3 (Constitution
# II / task 2.5.2): delega a recall_plan_usage_last_scope_row
# (cli/lib/recall.sh) — este arquivo NUNCA invoca `sqlite3` diretamente.
_pu_last_scope_row() {
  recall_plan_usage_last_scope_row "$1" "$2"
}

# _pu_2dp VALOR -> valor TRUNCADO (nao arredondado) a 2 casas decimais
# (string). Truncar, nao arredondar: quickstart.md Cenario 3 exige que
# 7.001 E 7.009 (3a casa decimal variando) comparem IGUAIS a 7.00 — sob
# arredondamento padrao 7.009 viraria 7.01 (falharia o teste). Manipulacao
# de string pura (POSIX sh, sem awk/bc) evita ruido de ponto-flutuante que
# `int(v*100)/100` teria (ex.: 7.05*100 pode virar 704.999... e truncar
# errado para 704). Entrada vazia/nao-numerica -> "" (NULL-vs-NULL,
# dec-050, comparado por igualdade de string a jusante).
_pu_2dp() {
  case "$1" in
    ''|*[!0-9.-]*) printf '' ; return 0 ;;
  esac
  case "$1" in
    *.*)
      _p2_int=${1%%.*}
      _p2_frac=${1#*.}
      _p2_frac=$(printf '%s' "$_p2_frac" | cut -c1-2)
      while [ "${#_p2_frac}" -lt 2 ]; do _p2_frac="${_p2_frac}0"; done
      printf '%s.%s' "$_p2_int" "$_p2_frac"
      ;;
    *)
      printf '%s.00' "$1"
      ;;
  esac
}

# _pu_throttle_discard DB SCOPE NEW_USED NEW_RESETS -> 0 (descarta, repete
# o ultimo registro dentro da tolerancia) ou 1 (persiste — mudou alem de 2
# casas decimais OU resets_at mudou OU nao ha registro anterior).
#
# NULL-vs-NULL (dec-050, residual CHK010/tasks.md 2.3.4): comparado via
# igualdade de string apos normalizacao (ambos "" = ambos NULL = identico
# -> descarta), extensao natural da regra geral sem caso especial.
_pu_throttle_discard() {
  _ptd_db="$1"
  _ptd_scope="$2"
  _ptd_new_used="$3"
  _ptd_new_resets="$4"

  _ptd_last=$(_pu_last_scope_row "$_ptd_db" "$_ptd_scope") || return 1
  [ -n "$_ptd_last" ] || return 1

  _ptd_last_used=${_ptd_last%%|*}
  _ptd_last_resets=${_ptd_last#*|}

  _ptd_new_used_r=$(_pu_2dp "$_ptd_new_used")
  _ptd_last_used_r=$(_pu_2dp "$_ptd_last_used")

  if [ "$_ptd_new_used_r" = "$_ptd_last_used_r" ] && [ "$_ptd_new_resets" = "$_ptd_last_resets" ]; then
    return 0
  fi
  return 1
}

# plan_usage_cmd_ingest_stdin -> le payload bruto da statusline via stdin,
# extrai rate_limits.<scope>.*, aplica throttle e insere via
# recall_plan_usage_insert. Exit SEMPRE 0 (task 4.3.3) — qualquer falha
# interna (jq/sqlite3 ausente, JSON malformado, INSERT falho) e best-effort
# silencioso, nunca propaga para o caller (o hook da statusline).
plan_usage_cmd_ingest_stdin() {
  _pis_payload=$(cat 2>/dev/null) || return 0
  [ -n "$_pis_payload" ] || return 0

  recall_have_jq 2>/dev/null || return 0
  printf '%s' "$_pis_payload" | jq empty >/dev/null 2>&1 || return 0

  # Ausencia TOTAL de rate_limits -> nenhum INSERT (dec-029).
  _pis_has_rl=$(printf '%s' "$_pis_payload" | jq -r 'has("rate_limits")' 2>/dev/null) || return 0
  [ "$_pis_has_rl" = "true" ] || return 0

  recall_have_sqlite3 2>/dev/null || return 0

  _pis_session_id=$(printf '%s' "$_pis_payload" | jq -r '.session_id // ""' 2>/dev/null) || _pis_session_id=""
  _pis_project_path=$(printf '%s' "$_pis_payload" | jq -r '.workspace.current_dir // .workspace.project_dir // ""' 2>/dev/null) || _pis_project_path=""
  [ -n "$_pis_project_path" ] || return 0
  _pis_project=$(basename -- "$_pis_project_path" 2>/dev/null) || return 0

  _pis_db=$(recall_resolve_db "") || return 0
  recall_ensure_db_dir "$_pis_db" >/dev/null 2>&1 || return 0
  recall_apply_schema "$_pis_db" >/dev/null 2>&1 || return 0

  _pis_now=$(_pu_now_iso)

  for _pis_scope in five_hour seven_day; do
    _pis_has_scope=$(printf '%s' "$_pis_payload" | jq -r --arg s "$_pis_scope" 'has("rate_limits") and (.rate_limits | has($s))' 2>/dev/null) || _pis_has_scope="false"
    [ "$_pis_has_scope" = "true" ] || continue

    _pis_used=$(printf '%s' "$_pis_payload" | jq -r --arg s "$_pis_scope" '.rate_limits[$s].used_percentage // ""' 2>/dev/null) || _pis_used=""
    _pis_resets=$(printf '%s' "$_pis_payload" | jq -r --arg s "$_pis_scope" '.rate_limits[$s].resets_at // ""' 2>/dev/null) || _pis_resets=""

    if _pu_throttle_discard "$_pis_db" "$_pis_scope" "$_pis_used" "$_pis_resets"; then
      continue
    fi

    recall_plan_usage_insert "$_pis_db" "$_pis_project" "$_pis_project_path" \
      "$_pis_session_id" "$_pis_scope" "$_pis_used" "$_pis_resets" \
      "$_pis_now" "$_pis_now" >/dev/null 2>&1 || :
  done

  return 0
}

_plan_usage_usage_text() {
  cat <<'USAGE'
cstk plan-usage — consulta o gauge de uso do plano (rate_limits/five_hour,
seven_day) capturado via statusline (FASE 2, plan-usage-capture).

USO:
  cstk plan-usage [--json] [--db PATH]
  cstk plan-usage history [--scope five_hour|seven_day] [--limit N]
                           [--since ISO] [--json] [--db PATH]
  cstk plan-usage ingest --stdin  uso interno do hook statusline-plan-usage.sh

  --json    saida maquina-legivel
  --db PATH indice (default $CSTK_KNOWLEDGE_DB ou ~/.claude/cstk/knowledge.db)
USAGE
}

# ==========================================================================
# Task 4.1 — `cstk plan-usage` (uso mais recente)
# ==========================================================================

# _pu_local_time EPOCH -> horario local formatado (apresentacao apenas — a
# persistencia continua epoch INTEGER, FR-003/Cenario 5). `date -r` e
# BSD/macOS-first (ambiente-alvo desta feature); sem fallback GNU (`date -d
# @EPOCH`) porque o CLI so precisa rodar no ambiente do operador (macOS/zsh,
# Constitution). Se a conversao falhar (comando indisponivel/erro), imprime
# o epoch cru — nunca fabrica um formato (Principio VI).
_pu_local_time() {
  [ -n "$1" ] || { printf ''; return 0; }
  date -r "$1" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || printf '%s' "$1"
}

# _pu_row_field ROW INDEX -> campo INDEX (1-based) de uma linha
# "used|resets|captured" (separador `|`, recall_query_sql .separator |).
_pu_row_field() {
  printf '%s' "$1" | awk -F '|' -v i="$2" '{print $i}'
}

# _pu_scope_text_line SCOPE ROW -> linha de texto para um escopo. ROW vazio
# (sem captura) ou used_percentage vazio -> "nao medido" (nunca 0,
# dec-029/SC-002).
_pu_scope_text_line() {
  _pstl_scope="$1"
  _pstl_row="$2"
  if [ -z "$_pstl_row" ]; then
    printf '%s: nao medido\n' "$_pstl_scope"
    return 0
  fi
  _pstl_used=$(_pu_row_field "$_pstl_row" 1)
  _pstl_resets=$(_pu_row_field "$_pstl_row" 2)
  if [ -z "$_pstl_used" ]; then
    printf '%s: nao medido\n' "$_pstl_scope"
    return 0
  fi
  _pstl_resets_disp="nao medido"
  [ -n "$_pstl_resets" ] && _pstl_resets_disp=$(_pu_local_time "$_pstl_resets")
  printf '%s: %s%% usado (reset: %s)\n' "$_pstl_scope" "$_pstl_used" "$_pstl_resets_disp"
}

# _pu_scope_json ROW -> objeto JSON {used_percentage,resets_at,captured_at}
# para um escopo, com null explicito quando o campo/linha estiver ausente
# (nunca 0 fabricado — SC-002).
_pu_scope_json() {
  _psj_row="$1"
  if [ -z "$_psj_row" ]; then
    printf '{"used_percentage":null,"resets_at":null,"captured_at":null}'
    return 0
  fi
  _psj_used=$(_pu_row_field "$_psj_row" 1)
  _psj_resets=$(_pu_row_field "$_psj_row" 2)
  _psj_captured=$(_pu_row_field "$_psj_row" 3)
  jq -n \
    --arg used "$_psj_used" --arg resets "$_psj_resets" --arg captured "$_psj_captured" \
    '{
      used_percentage: (if $used == "" then null else ($used | tonumber) end),
      resets_at: (if $resets == "" then null else ($resets | tonumber) end),
      captured_at: (if $captured == "" then null else $captured end)
    }' 2>/dev/null
}

plan_usage_cmd_show() {
  _pcs_json=0
  _pcs_db_flag=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --json) _pcs_json=1 ;;
      --db) shift; _pcs_db_flag="${1:-}" ;;
      -h|--help) _plan_usage_usage_text; return 0 ;;
      *)
        log_error "cstk plan-usage: flag desconhecida: $1"
        return 2
        ;;
    esac
    shift || break
  done

  if ! recall_have_sqlite3 2>/dev/null; then
    log_warn "cstk plan-usage: sqlite3 nao instalado; consulta indisponivel"
    return 1
  fi

  _pcs_db=$(recall_resolve_db "$_pcs_db_flag")

  _pcs_row_5h=""
  _pcs_row_7d=""
  _pcs_have_data=0
  if [ -f "$_pcs_db" ]; then
    _pcs_row_5h=$(recall_query_sql "$_pcs_db" ".mode list
.separator |
SELECT used_percentage, resets_at, captured_at FROM plan_usage WHERE scope='five_hour' ORDER BY id DESC LIMIT 1;") || _pcs_row_5h=""
    _pcs_row_7d=$(recall_query_sql "$_pcs_db" ".mode list
.separator |
SELECT used_percentage, resets_at, captured_at FROM plan_usage WHERE scope='seven_day' ORDER BY id DESC LIMIT 1;") || _pcs_row_7d=""
    [ -n "$_pcs_row_5h" ] || [ -n "$_pcs_row_7d" ] && _pcs_have_data=1
  else
    log_warn "cstk plan-usage: indice ausente ($_pcs_db); nenhuma captura registrada ainda"
  fi

  if [ "$_pcs_json" -eq 1 ]; then
    if recall_have_jq 2>/dev/null; then
      _pcs_json_5h=$(_pu_scope_json "$_pcs_row_5h")
      _pcs_json_7d=$(_pu_scope_json "$_pcs_row_7d")
      [ -n "$_pcs_json_5h" ] || _pcs_json_5h='{"used_percentage":null,"resets_at":null,"captured_at":null}'
      [ -n "$_pcs_json_7d" ] || _pcs_json_7d='{"used_percentage":null,"resets_at":null,"captured_at":null}'
      jq -n --argjson five_hour "$_pcs_json_5h" --argjson seven_day "$_pcs_json_7d" \
        '{five_hour: $five_hour, seven_day: $seven_day}'
    else
      log_warn "cstk plan-usage: jq ausente; --json indisponivel, usando texto"
      if [ -f "$_pcs_db" ] && [ "$_pcs_have_data" -eq 0 ]; then
        printf 'nao medido — nenhuma captura registrada ainda\n'
      else
        _pu_scope_text_line "five_hour" "$_pcs_row_5h"
        _pu_scope_text_line "seven_day" "$_pcs_row_7d"
      fi
    fi
  else
    if [ -f "$_pcs_db" ] && [ "$_pcs_have_data" -eq 0 ]; then
      printf 'nao medido — nenhuma captura registrada ainda\n'
    else
      _pu_scope_text_line "five_hour" "$_pcs_row_5h"
      _pu_scope_text_line "seven_day" "$_pcs_row_7d"
    fi
  fi
  return 0
}

# ==========================================================================
# Task 4.2 — `cstk plan-usage history` (serie temporal)
# ==========================================================================

# _pu_history_rows DB SCOPE LIMIT SINCE -> ate LIMIT linhas
# "used|resets|captured" das capturas MAIS RECENTES do escopo (respeitando
# --since), em ORDEM CRONOLOGICA (a mais antiga primeiro). A query busca as
# LIMIT mais recentes (ORDER BY id DESC LIMIT N) e entao inverte via o idioma
# POSIX sed classico de reverse ('1!G;h;$!d') — portavel BSD/GNU, sem `tac`
# (nao existe no macOS). DB ausente -> nenhuma linha (caller decide a
# mensagem, paridade 4.1.5).
_pu_history_rows() {
  _phr_db="$1"; _phr_scope="$2"; _phr_limit="$3"; _phr_since="$4"
  [ -f "$_phr_db" ] || return 0
  _phr_where="WHERE scope='$(sql_escape "$_phr_scope")'"
  [ -n "$_phr_since" ] && _phr_where="$_phr_where AND captured_at >= '$(sql_escape "$_phr_since")'"
  recall_query_sql "$_phr_db" ".mode list
.separator |
SELECT used_percentage, resets_at, captured_at FROM plan_usage $_phr_where ORDER BY id DESC LIMIT $_phr_limit;" \
    | sed '1!G;h;$!d'
}

# _pu_rows_to_json_array ROWS -> array JSON [{used_percentage,resets_at,
# captured_at}]. ROWS vazio -> "[]" (array vazio, NUNCA null — contrato
# 4.2.3: a chave do escopo pedido sempre existe, o array e que fica vazio
# quando nao ha captura no filtro).
_pu_rows_to_json_array() {
  _prtja_rows="$1"
  if [ -z "$_prtja_rows" ]; then
    printf '[]'
    return 0
  fi
  printf '%s\n' "$_prtja_rows" \
    | awk -F '|' '{print $1"\t"$2"\t"$3}' \
    | jq -R -s '
        [ split("\n")[] | select(length>0) | split("\t")
          | {used_percentage: (if .[0]=="" then null else (.[0]|tonumber) end),
             resets_at: (if .[1]=="" then null else (.[1]|tonumber) end),
             captured_at: (if .[2]=="" then null else .[2] end)}
        ]
      ' 2>/dev/null
}

# _pu_history_render_text DB SCOPES LIMIT SINCE DB_EXISTS -> uma secao de
# texto por escopo (SCOPES separado por espaco), ate LIMIT linhas em ordem
# cronologica. Mesma tabela de comportamento sem dados de 4.1.5/4.1.6
# (4.2.4): DB_EXISTS=0 -> "nao medido" por escopo (paridade 4.1.5); DB
# presente mas sem linha no filtro -> "nao medido — nenhuma captura
# registrada ainda" por escopo (paridade 4.1.6).
_pu_history_render_text() {
  _phrt_db="$1"; _phrt_scopes="$2"; _phrt_limit="$3"; _phrt_since="$4"; _phrt_db_exists="$5"
  for _phrt_s in $_phrt_scopes; do
    printf '== %s ==\n' "$_phrt_s"
    if [ "$_phrt_db_exists" -eq 0 ]; then
      printf '  nao medido\n'
      continue
    fi
    _phrt_rows=$(_pu_history_rows "$_phrt_db" "$_phrt_s" "$_phrt_limit" "$_phrt_since")
    if [ -z "$_phrt_rows" ]; then
      printf '  nao medido — nenhuma captura registrada ainda\n'
      continue
    fi
    printf '%s\n' "$_phrt_rows" | while IFS= read -r _phrt_line; do
      [ -n "$_phrt_line" ] || continue
      _phrt_used=$(_pu_row_field "$_phrt_line" 1)
      _phrt_captured=$(_pu_row_field "$_phrt_line" 3)
      if [ -n "$_phrt_used" ]; then
        printf '  %s  %s%%\n' "$_phrt_captured" "$_phrt_used"
      else
        printf '  %s  nao medido\n' "$_phrt_captured"
      fi
    done
  done
}

plan_usage_cmd_history() {
  _pch_scope=""
  _pch_limit="20"
  _pch_since=""
  _pch_json=0
  _pch_db_flag=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --scope) shift; _pch_scope="${1:-}" ;;
      --limit) shift; _pch_limit="${1:-}" ;;
      --since) shift; _pch_since="${1:-}" ;;
      --json) _pch_json=1 ;;
      --db) shift; _pch_db_flag="${1:-}" ;;
      -h|--help) _plan_usage_usage_text; return 0 ;;
      *)
        log_error "cstk plan-usage history: flag desconhecida: $1"
        return 2
        ;;
    esac
    shift || break
  done

  case "$_pch_scope" in
    ''|five_hour|seven_day) ;;
    *)
      log_error "cstk plan-usage history: --scope invalido (esperado five_hour|seven_day, recebido: '$_pch_scope')"
      return 2
      ;;
  esac

  if ! validate_limit "$_pch_limit"; then
    log_error "cstk plan-usage history: --limit deve ser inteiro positivo (recebido: '$_pch_limit')"
    return 2
  fi

  if ! recall_have_sqlite3 2>/dev/null; then
    log_warn "cstk plan-usage history: sqlite3 nao instalado; consulta indisponivel"
    return 1
  fi

  _pch_db=$(recall_resolve_db "$_pch_db_flag")
  _pch_db_exists=0
  [ -f "$_pch_db" ] && _pch_db_exists=1
  [ "$_pch_db_exists" -eq 1 ] || log_warn "cstk plan-usage history: indice ausente ($_pch_db); nenhuma captura registrada ainda"

  _pch_scopes="five_hour seven_day"
  [ -n "$_pch_scope" ] && _pch_scopes="$_pch_scope"

  if [ "$_pch_json" -eq 1 ]; then
    if recall_have_jq 2>/dev/null; then
      _pch_json_out="{}"
      for _pch_s in $_pch_scopes; do
        _pch_rows=""
        [ "$_pch_db_exists" -eq 1 ] && _pch_rows=$(_pu_history_rows "$_pch_db" "$_pch_s" "$_pch_limit" "$_pch_since")
        _pch_arr=$(_pu_rows_to_json_array "$_pch_rows")
        [ -n "$_pch_arr" ] || _pch_arr="[]"
        _pch_json_out=$(printf '%s' "$_pch_json_out" | jq --arg k "$_pch_s" --argjson v "$_pch_arr" '. + {($k): $v}' 2>/dev/null) || _pch_json_out="{}"
      done
      printf '%s\n' "$_pch_json_out"
    else
      log_warn "cstk plan-usage history: jq ausente; --json indisponivel, usando texto"
      _pu_history_render_text "$_pch_db" "$_pch_scopes" "$_pch_limit" "$_pch_since" "$_pch_db_exists"
    fi
  else
    _pu_history_render_text "$_pch_db" "$_pch_scopes" "$_pch_limit" "$_pch_since" "$_pch_db_exists"
  fi
  return 0
}

plan_usage_main() {
  _pum_sub="${1:-}"
  case "$_pum_sub" in
    ingest)
      shift
      case "${1:-}" in
        --stdin)
          plan_usage_cmd_ingest_stdin
          return 0
          ;;
        *)
          log_error "cstk plan-usage ingest: flag desconhecida (esperado --stdin)"
          return 2
          ;;
      esac
      ;;
    -h|--help)
      _plan_usage_usage_text
      return 0
      ;;
    ''|--*)
      plan_usage_cmd_show "$@"
      return $?
      ;;
    history)
      shift
      plan_usage_cmd_history "$@"
      return $?
      ;;
    *)
      log_error "cstk plan-usage: subcomando desconhecido: $_pum_sub"
      _plan_usage_usage_text
      return 2
      ;;
  esac
}
