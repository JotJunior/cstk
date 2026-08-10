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
# `cstk plan-usage` (sem args) e `cstk plan-usage history` (consulta
# publica, FASE 4.1/4.2) AINDA NAO IMPLEMENTADOS nesta onda — apenas o
# subcomando interno `ingest --stdin` necessario para desbloquear FASE 2
# (statusline-plan-usage.sh so consegue persistir via este subcomando,
# research.md Decision 6 — o hook roda fora do processo `cstk` e nao tem
# acesso direto a `cli/lib/recall.sh`).
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
  cstk plan-usage                 uso mais recente por escopo [FASE 4 — pendente]
  cstk plan-usage history         serie temporal por escopo   [FASE 4 — pendente]
  cstk plan-usage ingest --stdin  uso interno do hook statusline-plan-usage.sh
USAGE
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
    '')
      log_error "cstk plan-usage: consulta publica ainda nao implementada (FASE 4 desta feature)"
      _plan_usage_usage_text
      return 1
      ;;
    history)
      log_error "cstk plan-usage history: ainda nao implementada (FASE 4 desta feature)"
      return 1
      ;;
    *)
      log_error "cstk plan-usage: subcomando desconhecido: $_pum_sub"
      _plan_usage_usage_text
      return 2
      ;;
  esac
}
