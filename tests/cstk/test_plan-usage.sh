#!/bin/sh
# test_plan-usage.sh — cobre cli/lib/plan-usage.sh, consulta publica
# `cstk plan-usage` / `cstk plan-usage history` (FASE 4.1/4.2, feature
# plan-usage-capture).
#
# Contrato: docs/specs/plan-usage-capture/contracts/cli-plan-usage.md
# secoes "cstk plan-usage" e "cstk plan-usage history".
#
# Cenarios `cstk plan-usage` (mapeados 1:1 aos subitens 4.1.2-4.1.8):
#   1  --json/--db flags aceitas + saida texto com dados (4.1.2/4.1.3)
#   2  texto: campo sem medicao imprime "nao medido", nunca "0" (4.1.3)
#   3  --json: null explicito quando escopo nunca teve captura (4.1.4)
#   4  --json e JSON parseavel com dados presentes (4.1.4)
#   5  knowledge.db ausente -> aviso stderr + "nao medido" nos 2 escopos, exit 0 (4.1.5)
#   6  tabela plan_usage vazia (db existe, sem linhas) -> mensagem dedicada, exit 0 (4.1.6)
#   7  sqlite3 ausente -> aviso stderr, exit 1 (4.1.7)
#   8  flag desconhecida -> uso em stderr, exit 2 (4.1.8)
#
# Cenarios `cstk plan-usage history` (mapeados aos subitens 4.2.1-4.2.6):
#   9  3 capturas crescentes -> historico em ordem cronologica, --scope
#      filtra (paridade quickstart.md Cenario 4) (4.2.1/4.2.2/4.2.5)
#   10 --json: chave so do escopo pedido, array vazio (nao null) sem
#      captura no filtro (4.2.3)
#   11 --since filtra identico a `cstk usage --since` (4.2.1/4.2.6)
#   12 --limit filtra e mantem ordem cronologica (4.2.1/4.2.6)
#   13 --scope invalido -> exit 2 (4.2.1)
#   14 knowledge.db ausente -> "nao medido" por escopo, exit 0 (4.2.4)
#
# DB de teste sempre via --db em $TMPDIR_TEST; HOME sempre isolado sob
# $TMPDIR_TEST (nunca ~/.claude real). Sem sessao real: captura semeada via
# `plan_usage_main ingest --stdin` (mesmo caminho de producao usado pelo
# hook da statusline, research.md Decision 6) alimentado por payload
# fixture — paridade com tests/test_statusline-plan-usage.sh.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CSTK_LIB="$REPO_ROOT/cli/lib"
export CSTK_LIB

_have_deps() {
  command -v sqlite3 >/dev/null 2>&1 && command -v jq >/dev/null 2>&1
}

# _pu_home HOME_DIR ARGS... -> roda plan_usage_main isolado sob HOME_DIR.
_pu_home() {
  _puh_home="$1"; shift
  env HOME="$_puh_home" \
    sh -c '. "$CSTK_LIB/plan-usage.sh"; plan_usage_main "$@"' _ "$@"
}

# _pu_fixture SCOPE USED RESETS -> payload minimo com rate_limits.<scope>
# (mesmo formato do payload real observado, paridade
# reference_statusline_usage_payload.md).
_pu_fixture_scope() {
  printf '{"session_id":"s","workspace":{"current_dir":"/tmp/proj"},"rate_limits":{"%s":{"used_percentage":%s,"resets_at":%s}}}' "$1" "$2" "$3"
}

# _pu_ingest HOME_DIR DB JSON -> semeia plan_usage via o caminho de producao
# `ingest --stdin` (aplica schema + INSERT), nao INSERT SQL direto no teste.
_pu_ingest() {
  _pi_home="$1"; _pi_db="$2"; _pi_json="$3"
  printf '%s' "$_pi_json" | env HOME="$_pi_home" CSTK_KNOWLEDGE_DB="$_pi_db" \
    sh -c '. "$CSTK_LIB/plan-usage.sh"; plan_usage_main ingest --stdin'
}

# _pu_touch_empty_db DB -> cria o arquivo do indice com o schema aplicado
# mas SEM nenhuma linha em plan_usage (cenario 4.1.6: tabela vazia, DB
# presente). Distinto de "DB ausente" (cenario 4.1.5).
_pu_touch_empty_db() {
  _pted_db="$1"
  sh -c '. "$CSTK_LIB/recall.sh"; recall_ensure_db_dir "$1" >/dev/null 2>&1; recall_apply_schema "$1" >/dev/null 2>&1' _ "$_pted_db"
}

# =========================================================================
# Cenario 1 — flags --json/--db aceitas + saida texto com dados (4.1.2/4.1.3)
# =========================================================================
scenario_01_flags_e_texto_com_dados() {
  _have_deps || return 0
  _db="$TMPDIR_TEST/k1.db"
  _pu_ingest "$TMPDIR_TEST" "$_db" "$(_pu_fixture_scope five_hour 7.50 1786372200)" >/dev/null 2>&1

  assert_exit 0 _pu_home "$TMPDIR_TEST" --db "$_db" || return 1
  assert_stdout_contains "five_hour: 7.5% usado" || return 1
  # reset formatado em local time (data ISO-like na apresentacao) — nunca o
  # epoch cru exposto ao usuario.
  assert_stdout_match "reset: [0-9]{4}-[0-9]{2}-[0-9]{2}" || return 1
  assert_stdout_not_contains "1786372200" || return 1
}

# =========================================================================
# Cenario 2 — campo sem medicao imprime "nao medido", nunca "0" (4.1.3)
# =========================================================================
scenario_02_nao_medido_nunca_zero() {
  _have_deps || return 0
  _db="$TMPDIR_TEST/k2.db"
  # so five_hour recebe captura; seven_day nunca e alimentado.
  _pu_ingest "$TMPDIR_TEST" "$_db" "$(_pu_fixture_scope five_hour 3.00 1786372200)" >/dev/null 2>&1

  assert_exit 0 _pu_home "$TMPDIR_TEST" --db "$_db" || return 1
  assert_stdout_contains "seven_day: nao medido" || return 1
  assert_stdout_not_contains "seven_day: 0" || return 1
}

# =========================================================================
# Cenario 3 — --json: null explicito quando escopo nunca teve captura (4.1.4)
# =========================================================================
scenario_03_json_null_sem_captura() {
  _have_deps || return 0
  _db="$TMPDIR_TEST/k3.db"
  _pu_ingest "$TMPDIR_TEST" "$_db" "$(_pu_fixture_scope five_hour 5.00 1786372200)" >/dev/null 2>&1

  assert_exit 0 _pu_home "$TMPDIR_TEST" --json --db "$_db" || return 1
  printf '%s' "$_CAPTURED_STDOUT" | jq -e . >/dev/null 2>&1 || {
    _fail "json_valido" "saida --json nao e JSON parseavel"
    return 1
  }
  _sd_used=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.seven_day.used_percentage')
  _sd_resets=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.seven_day.resets_at')
  _sd_captured=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.seven_day.captured_at')
  [ "$_sd_used" = "null" ] || { _fail "seven_day_used_null" "esperado null, obtido $_sd_used"; return 1; }
  [ "$_sd_resets" = "null" ] || { _fail "seven_day_resets_null" "esperado null, obtido $_sd_resets"; return 1; }
  [ "$_sd_captured" = "null" ] || { _fail "seven_day_captured_null" "esperado null, obtido $_sd_captured"; return 1; }
}

# =========================================================================
# Cenario 4 — --json e JSON parseavel com dados presentes nos 2 escopos (4.1.4)
# =========================================================================
scenario_04_json_com_dados() {
  _have_deps || return 0
  _db="$TMPDIR_TEST/k4.db"
  _pu_ingest "$TMPDIR_TEST" "$_db" \
    '{"session_id":"s","workspace":{"current_dir":"/tmp/proj"},"rate_limits":{"five_hour":{"used_percentage":7.0,"resets_at":1786372200},"seven_day":{"used_percentage":19,"resets_at":1786802400}}}' \
    >/dev/null 2>&1

  assert_exit 0 _pu_home "$TMPDIR_TEST" --json --db "$_db" || return 1
  printf '%s' "$_CAPTURED_STDOUT" | jq -e . >/dev/null 2>&1 || {
    _fail "json_valido" "saida --json nao e JSON parseavel"
    return 1
  }
  _fh_used=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.five_hour.used_percentage')
  _sd_used=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.seven_day.used_percentage')
  # SQLite armazena a coluna REAL (7 -> 7.0, 19 -> 19.0); jq preserva a
  # representacao textual vinda da query (tonumber de "7.0"/"19.0").
  [ "$_fh_used" = "7.0" ] || { _fail "five_hour_used" "esperado 7.0, obtido $_fh_used"; return 1; }
  [ "$_sd_used" = "19.0" ] || { _fail "seven_day_used" "esperado 19.0, obtido $_sd_used"; return 1; }
}

# =========================================================================
# Cenario 5 — knowledge.db ausente -> aviso stderr + "nao medido" nos 2
# escopos, exit 0 (4.1.5)
# =========================================================================
scenario_05_db_ausente() {
  _have_deps || return 0
  _db="$TMPDIR_TEST/nunca-existiu-5/k.db"
  assert_exit 0 _pu_home "$TMPDIR_TEST" --db "$_db" || return 1
  assert_stderr_contains "ausente" || return 1
  assert_stdout_contains "five_hour: nao medido" || return 1
  assert_stdout_contains "seven_day: nao medido" || return 1
}

# =========================================================================
# Cenario 6 — tabela plan_usage vazia (DB existe, sem linhas) -> mensagem
# dedicada, exit 0 (4.1.6)
# =========================================================================
scenario_06_tabela_vazia() {
  _have_deps || return 0
  _db="$TMPDIR_TEST/k6.db"
  _pu_touch_empty_db "$_db"
  [ -f "$_db" ] || { _error "seed_db" "nao consegui criar DB vazio de fixture"; return 2; }

  assert_exit 0 _pu_home "$TMPDIR_TEST" --db "$_db" || return 1
  assert_stdout_contains "nao medido — nenhuma captura registrada ainda" || return 1
}

# =========================================================================
# Cenario 7 — sqlite3 ausente -> aviso stderr, exit 1 (4.1.7)
# =========================================================================
scenario_07_sem_sqlite3() {
  _bin="$TMPDIR_TEST/bin7"
  mkdir -p "$_bin"
  for _t in tr wc printf sed grep awk basename dirname date find mkdir rm cat head sleep cp jq stat mktemp sh env; do
    _p=$(command -v "$_t" 2>/dev/null) && ln -sf "$_p" "$_bin/$_t"
  done
  # (sqlite3 deliberadamente ausente do PATH)
  assert_exit 1 env PATH="$_bin" HOME="$TMPDIR_TEST" sh -c \
    '. "'"$CSTK_LIB"'/plan-usage.sh"; plan_usage_main --db "'"$TMPDIR_TEST"'/k7.db"' || return 1
  assert_stderr_contains "sqlite3" || return 1
}

# =========================================================================
# Cenario 8 — flag desconhecida -> uso em stderr, exit 2 (4.1.8)
# =========================================================================
scenario_08_flag_desconhecida() {
  assert_exit 2 _pu_home "$TMPDIR_TEST" --bogus || return 1
}

# =========================================================================
# Cenario 9 — 3 capturas crescentes -> historico em ordem cronologica,
# --scope filtra (paridade quickstart.md Cenario 4) (4.2.1/4.2.2/4.2.5)
# =========================================================================
scenario_09_historico_ordem_cronologica() {
  _have_deps || return 0
  _db="$TMPDIR_TEST/k9.db"
  _pu_ingest "$TMPDIR_TEST" "$_db" "$(_pu_fixture_scope five_hour 5.0 1786372200)" >/dev/null 2>&1
  sleep 1
  _pu_ingest "$TMPDIR_TEST" "$_db" "$(_pu_fixture_scope five_hour 12.0 1786372200)" >/dev/null 2>&1
  sleep 1
  _pu_ingest "$TMPDIR_TEST" "$_db" "$(_pu_fixture_scope five_hour 20.0 1786372200)" >/dev/null 2>&1

  assert_exit 0 _pu_home "$TMPDIR_TEST" history --scope five_hour --db "$_db" || return 1
  assert_stdout_contains "== five_hour ==" || return 1
  assert_stdout_not_contains "seven_day" || return 1

  # ordem cronologica: 5.0 aparece ANTES de 12.0, que aparece ANTES de 20.0.
  _pos5=$(printf '%s' "$_CAPTURED_STDOUT" | grep -n "5.0%" | head -1 | cut -d: -f1)
  _pos12=$(printf '%s' "$_CAPTURED_STDOUT" | grep -n "12.0%" | head -1 | cut -d: -f1)
  _pos20=$(printf '%s' "$_CAPTURED_STDOUT" | grep -n "20.0%" | head -1 | cut -d: -f1)
  [ -n "$_pos5" ] && [ -n "$_pos12" ] && [ -n "$_pos20" ] || { _fail "3_linhas_presentes" "esperado 3 valores no historico"; return 1; }
  [ "$_pos5" -lt "$_pos12" ] && [ "$_pos12" -lt "$_pos20" ] || {
    _fail "ordem_cronologica" "esperado 5.0 < 12.0 < 20.0 na saida (linhas $_pos5/$_pos12/$_pos20)"
    return 1
  }
}

# =========================================================================
# Cenario 10 — --json: chave so do escopo pedido, array vazio (nao null)
# sem captura no filtro (4.2.3)
# =========================================================================
scenario_10_json_chave_escopo_array_vazio() {
  _have_deps || return 0
  _db="$TMPDIR_TEST/k10.db"
  _pu_touch_empty_db "$_db"

  assert_exit 0 _pu_home "$TMPDIR_TEST" history --scope five_hour --json --db "$_db" || return 1
  printf '%s' "$_CAPTURED_STDOUT" | jq -e . >/dev/null 2>&1 || {
    _fail "json_valido" "saida --json de history nao e JSON parseavel"
    return 1
  }
  assert_stdout_not_contains "seven_day" || return 1
  _arr=$(printf '%s' "$_CAPTURED_STDOUT" | jq -c '.five_hour')
  [ "$_arr" = "[]" ] || { _fail "array_vazio" "esperado [], obtido $_arr"; return 1; }
}

# =========================================================================
# Cenario 11 — --since filtra identico a `cstk usage --since` (4.2.1/4.2.6)
# =========================================================================
scenario_11_since_filtra() {
  _have_deps || return 0
  _db="$TMPDIR_TEST/k11.db"
  _pu_ingest "$TMPDIR_TEST" "$_db" "$(_pu_fixture_scope five_hour 5.0 1786372200)" >/dev/null 2>&1
  sleep 1
  _pu_ingest "$TMPDIR_TEST" "$_db" "$(_pu_fixture_scope five_hour 12.0 1786372200)" >/dev/null 2>&1
  sleep 1
  _pu_ingest "$TMPDIR_TEST" "$_db" "$(_pu_fixture_scope five_hour 20.0 1786372200)" >/dev/null 2>&1

  assert_exit 0 _pu_home "$TMPDIR_TEST" history --scope five_hour --json --db "$_db" || return 1
  _since=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.five_hour[1].captured_at')
  [ -n "$_since" ] && [ "$_since" != "null" ] || { _fail "since_seed" "nao consegui extrair captured_at do 2o registro"; return 1; }

  assert_exit 0 _pu_home "$TMPDIR_TEST" history --scope five_hour --since "$_since" --json --db "$_db" || return 1
  _n=$(printf '%s' "$_CAPTURED_STDOUT" | jq '.five_hour | length')
  [ "$_n" = "2" ] || { _fail "since_filtra" "esperado 2 linhas (>= 2o registro), obtido $_n"; return 1; }
  assert_stdout_not_contains '"used_percentage": 5.0' || return 1
}

# =========================================================================
# Cenario 12 — --limit filtra e mantem ordem cronologica (4.2.1/4.2.6)
# =========================================================================
scenario_12_limit_filtra() {
  _have_deps || return 0
  _db="$TMPDIR_TEST/k12.db"
  _pu_ingest "$TMPDIR_TEST" "$_db" "$(_pu_fixture_scope five_hour 5.0 1786372200)" >/dev/null 2>&1
  sleep 1
  _pu_ingest "$TMPDIR_TEST" "$_db" "$(_pu_fixture_scope five_hour 12.0 1786372200)" >/dev/null 2>&1
  sleep 1
  _pu_ingest "$TMPDIR_TEST" "$_db" "$(_pu_fixture_scope five_hour 20.0 1786372200)" >/dev/null 2>&1

  assert_exit 0 _pu_home "$TMPDIR_TEST" history --scope five_hour --limit 2 --json --db "$_db" || return 1
  _n=$(printf '%s' "$_CAPTURED_STDOUT" | jq '.five_hour | length')
  [ "$_n" = "2" ] || { _fail "limit_2" "esperado 2 linhas, obtido $_n"; return 1; }
  # --limit 2 mantem as 2 MAIS RECENTES (12.0, 20.0), nao as 2 mais antigas.
  _first=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.five_hour[0].used_percentage')
  [ "$_first" = "12.0" ] || { _fail "limit_mais_recentes" "esperado 12.0 como primeiro apos --limit 2, obtido $_first"; return 1; }
}

# =========================================================================
# Cenario 13 — --scope invalido -> exit 2 (4.2.1)
# =========================================================================
scenario_13_scope_invalido() {
  assert_exit 2 _pu_home "$TMPDIR_TEST" history --scope bogus --db "$TMPDIR_TEST/k13.db" || return 1
}

# =========================================================================
# Cenario 14 — knowledge.db ausente -> "nao medido" por escopo, exit 0 (4.2.4)
# =========================================================================
scenario_14_history_db_ausente() {
  _have_deps || return 0
  _db="$TMPDIR_TEST/nunca-existiu-14/k.db"
  assert_exit 0 _pu_home "$TMPDIR_TEST" history --db "$_db" || return 1
  assert_stderr_contains "ausente" || return 1
  assert_stdout_contains "== five_hour ==" || return 1
  assert_stdout_contains "== seven_day ==" || return 1
  assert_stdout_contains "nao medido" || return 1
}

run_all_scenarios
