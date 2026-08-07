#!/bin/sh
# test_usage.sh — cobre cli/lib/usage.sh (feature loose-usage-capture, task 4.5.3)
#
# Cenarios:
#   1  listagem com dados (texto) + participacao
#   2  listagem sem dados ("nao medido — sem cobertura de captura")
#   3  --json (objeto {project, category, models[]})
#   4  compare (loose vs pipeline, blended_cost_per_mtok)
#   5  compare --json
#   6  prune --dry-run (nao remove nada)
#   7  prune real (remove segmento fechado + linha de indice)
#   8  prune: segmento ABERTO nunca e elegivel, mesmo antigo
#   9  flag desconhecida -> exit 2
#   10 subcomando desconhecido -> exit 2
#   11 --limit invalido -> exit 2
#   12 --older-than-days nao-numerico -> exit 2
#   13 degradacao sem sqlite3 (exit 1, listagem e prune)
#   14 prune sem sidecar -> "nada a podar", exit 0
#   15 ingest-on-read idempotente (UPSERT, sem duplicar linhas)
#
# DB de teste sempre via --db em $TMPDIR_TEST; sidecar sempre sob HOME
# isolado (nunca ~/.claude real). otel-usage.sh e um STUB determinístico
# (le fixture-delta.json do proprio segmento) — nao depende de telemetria
# real nem de rede.
#
# Convencao do harness (assert_exit EXPECTED CMD [ARGS...]): assert_exit faz
# a PROPRIA captura internamente — nao chamar `capture` antes (duplicaria a
# execucao e a segunda capture, sem args, sobrescreveria _CAPTURED_EXIT com
# o resultado de rodar nada). Ver tests/lib/harness.sh linhas 138-146.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CSTK_LIB="$REPO_ROOT/cli/lib"
export CSTK_LIB

_have_deps() {
  command -v sqlite3 >/dev/null 2>&1 && command -v jq >/dev/null 2>&1
}

# _uc_home HOME_DIR CMD... -> roda usage_main com HOME=HOME_DIR isolado. Quando
# o stub de otel-usage.sh foi instalado (_install_otel_stub), antepoe
# $TMPDIR_TEST/stubbin ao PATH -- _usage_runtime_script_path resolve por PATH
# (camada 1) ANTES do layout de repo relativo a CSTK_LIB (camada 2), entao sem
# isso o mapper acharia o otel-usage.sh REAL da arvore do repo (CSTK_LIB
# aponta pro repo em dev) em vez do stub deterministico.
_uc_home() {
  _uch_home="$1"; shift
  env PATH="$TMPDIR_TEST/stubbin:$PATH" HOME="$_uch_home" \
    sh -c '. "$CSTK_LIB/common.sh"; . "$CSTK_LIB/usage.sh"; usage_main "$@"' _ "$@"
}

# _install_otel_stub -> instala o stub deterministico de otel-usage.sh em
# $TMPDIR_TEST/stubbin (resolvido via PATH, camada 1 de
# _usage_runtime_script_path -- precisa vencer a camada 2/repo). O stub le
# <state-dir>/fixture-delta.json (JSON literal, inclusive "null") e o ecoa;
# ausencia de fixture -> "null".
_install_otel_stub() {
  mkdir -p "$TMPDIR_TEST/stubbin"
  cat > "$TMPDIR_TEST/stubbin/otel-usage.sh" <<'STUB'
#!/bin/sh
case "$1" in
  delta)
    shift
    _sd=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --state-dir) shift; _sd="$1" ;;
      esac
      shift || break
    done
    if [ -n "$_sd" ] && [ -f "$_sd/fixture-delta.json" ]; then
      cat "$_sd/fixture-delta.json"
    else
      printf 'null\n'
    fi
    ;;
  *) printf 'null\n' ;;
esac
STUB
  chmod +x "$TMPDIR_TEST/stubbin/otel-usage.sh"
}

# _write_meta PROC_DIR PROJECT_PATH CUR_SEG -> meta.tsv sintetico (formato
# real do hook posttooluse-loose-usage.sh: chave<TAB>valor).
_write_meta() {
  _wm_dir="$1"; _wm_proj="$2"; _wm_seg="$3"
  mkdir -p "$_wm_dir"
  {
    printf 'schema\t1\n'
    printf 'project_path\t%s\n' "$_wm_proj"
    printf 'endpoint\thttp://127.0.0.1:9464\n'
    printf 'owner_pid\tunknown\n'
    printf 'created_at\t2026-01-01T00:00:00Z\n'
    printf 'updated_at\t2026-01-01T00:05:00Z\n'
    printf 'current_segment\t%s\n' "$_wm_seg"
  } > "$_wm_dir/meta.tsv"
}

# _write_segment PROC_DIR SEG_ID CLOSED(0|1) MODEL COST TOKENS -> cria o
# diretorio do segmento com otel-start.tsv, closed opcional e
# fixture-delta.json (consumido pelo stub). MODEL vazio -> fixture "null"
# (segmento sem medicao, nao gera linha em loose_usage).
_write_segment() {
  _ws_proc="$1"; _ws_seg="$2"; _ws_closed="$3"; _ws_model="$4"; _ws_cost="$5"; _ws_tok="$6"
  _ws_dir="$_ws_proc/$_ws_seg"
  mkdir -p "$_ws_dir"
  : > "$_ws_dir/otel-start.tsv"
  if [ "$_ws_closed" = "1" ]; then
    : > "$_ws_dir/closed"
  else
    : > "$_ws_dir/otel-end.tsv"
  fi
  if [ -n "$_ws_model" ]; then
    printf '{"session_id":"s1","total_cost_usd":%s,"total_tokens":%s,"by_model":{"%s":{"cost_usd":%s,"total_tokens":%s}}}\n' \
      "$_ws_cost" "$_ws_tok" "$_ws_model" "$_ws_cost" "$_ws_tok" > "$_ws_dir/fixture-delta.json"
  else
    printf 'null\n' > "$_ws_dir/fixture-delta.json"
  fi
}

# _seed_pipeline DB PROJECT MODEL COST TOKENS -> insere uma linha sintetica
# em wave_model_usage (schema ja existente, alimentada normalmente pela
# ingestao de state.json/db — aqui semeada direto via sqlite3 por SER
# FIXTURE DE TESTE, nao codigo de producao; usage.sh continua proibido de
# chamar sqlite3, essa chamada vive so no arquivo de teste).
_seed_pipeline() {
  _sp_db="$1"; _sp_proj="$2"; _sp_model="$3"; _sp_cost="$4"; _sp_tok="$5"
  sqlite3 -- "$_sp_db" "INSERT INTO wave_model_usage(project,feature,wave,execution_id,source_ts,source_id,model,cost_usd,total_tokens,ingested_at) VALUES('$_sp_proj','featX','onda-001','exec-1','2026-01-01T00:00:00Z','onda-001|$_sp_model','$_sp_model',$_sp_cost,$_sp_tok,'2026-01-01T00:00:00Z');" \
    >/dev/null 2>&1
}

# =========================================================================
# Cenario 1 — Listagem com dados (texto) + participacao
# =========================================================================
scenario_01_listagem_com_dados() {
  _have_deps || return 0
  _install_otel_stub
  _proc="$TMPDIR_TEST/.claude/cstk/loose-usage/proj1-abc"
  _write_meta "$_proc" "/home/dev/proj1" "seg-001"
  _write_segment "$_proc" "seg-001" 0 "claude-sonnet-5" "0.10" "2000"

  assert_exit 0 _uc_home "$TMPDIR_TEST" --project proj1 --db "$TMPDIR_TEST/k1.db" || return 1
  assert_stdout_contains "projeto: proj1" || return 1
  assert_stdout_contains "claude-sonnet-5" || return 1
  assert_stdout_contains "tokens=2000" || return 1
  assert_stdout_contains "participacao=100.0%" || return 1
}

# =========================================================================
# Cenario 2 — Listagem sem dados (cobertura ausente)
# =========================================================================
scenario_02_listagem_sem_dados() {
  _have_deps || return 0
  _install_otel_stub
  assert_exit 0 _uc_home "$TMPDIR_TEST" --project projeto-fantasma --db "$TMPDIR_TEST/k2.db" || return 1
  assert_stdout_contains "nao medido" || return 1
}

# =========================================================================
# Cenario 3 — --json
# =========================================================================
scenario_03_json() {
  _have_deps || return 0
  _install_otel_stub
  _proc="$TMPDIR_TEST/.claude/cstk/loose-usage/proj3-abc"
  _write_meta "$_proc" "/home/dev/proj3" "seg-001"
  _write_segment "$_proc" "seg-001" 0 "claude-opus-4" "0.25" "5000"

  assert_exit 0 _uc_home "$TMPDIR_TEST" --project proj3 --json --db "$TMPDIR_TEST/k3.db" || return 1
  assert_stdout_contains '"category": "loose"' || return 1
  assert_stdout_contains '"model": "claude-opus-4"' || return 1
  assert_stdout_contains '"total_tokens": 5000' || return 1
  printf '%s' "$_CAPTURED_STDOUT" | jq -e . >/dev/null 2>&1 || {
    _fail "json_valido" "saida --json nao e JSON parseavel"
    return 1
  }
}

# =========================================================================
# Cenario 4 — compare (loose vs pipeline)
# =========================================================================
scenario_04_compare() {
  _have_deps || return 0
  _install_otel_stub
  _proc="$TMPDIR_TEST/.claude/cstk/loose-usage/proj4-abc"
  _write_meta "$_proc" "/home/dev/proj4" "seg-001"
  _write_segment "$_proc" "seg-001" 0 "claude-sonnet-5" "0.10" "1000000"

  _db="$TMPDIR_TEST/k4.db"
  # Primeiro roda a listagem para o ingest-on-read aplicar o schema + popular
  # loose_usage; so entao semeamos a linha de pipeline no mesmo DB.
  assert_exit 0 _uc_home "$TMPDIR_TEST" --project proj4 --db "$_db" || return 1
  _seed_pipeline "$_db" "proj4" "claude-sonnet-5" "0.20" "2000000"

  assert_exit 0 _uc_home "$TMPDIR_TEST" compare --project proj4 --db "$_db" || return 1
  assert_stdout_contains "== loose ==" || return 1
  assert_stdout_contains "== pipeline ==" || return 1
  # cost=0.10 / tokens=1_000_000 * 1e6 = 0.10 (mesma proporcao no pipeline:
  # 0.20 / 2_000_000 * 1e6 = 0.10) -- as duas categorias tem o MESMO blended.
  assert_stdout_contains "blended_cost_per_mtok=0.100000" || return 1
}

# =========================================================================
# Cenario 5 — compare --json
# =========================================================================
scenario_05_compare_json() {
  _have_deps || return 0
  _install_otel_stub
  _proc="$TMPDIR_TEST/.claude/cstk/loose-usage/proj5-abc"
  _write_meta "$_proc" "/home/dev/proj5" "seg-001"
  _write_segment "$_proc" "seg-001" 0 "claude-haiku" "0.01" "100000"

  _db="$TMPDIR_TEST/k5.db"
  assert_exit 0 _uc_home "$TMPDIR_TEST" --project proj5 --db "$_db" || return 1

  assert_exit 0 _uc_home "$TMPDIR_TEST" compare --project proj5 --json --db "$_db" || return 1
  assert_stdout_contains '"category": "loose"' || return 1
  assert_stdout_contains '"category": "pipeline"' || return 1
  printf '%s' "$_CAPTURED_STDOUT" | jq -e . >/dev/null 2>&1 || {
    _fail "compare_json_valido" "saida --json de compare nao e JSON parseavel"
    return 1
  }
}

# =========================================================================
# Cenario 6 — prune --dry-run (nao remove nada)
# =========================================================================
scenario_06_prune_dry_run() {
  _have_deps || return 0
  _proc="$TMPDIR_TEST/.claude/cstk/loose-usage/proj6-old"
  _write_meta "$_proc" "/home/dev/proj6" "seg-001"
  _write_segment "$_proc" "seg-001" 1 "claude-sonnet-5" "0.05" "500"
  # Envelhece os arquivos do segmento (closed + otel-start) alem do TTL.
  touch -t 202401010000 "$_proc/seg-001/closed" "$_proc/seg-001/otel-start.tsv"

  assert_exit 0 _uc_home "$TMPDIR_TEST" prune --dry-run --older-than-days 1 --db "$TMPDIR_TEST/k6.db" || return 1
  assert_stdout_contains "action=would-remove process_key=proj6-old segment=seg-001" || return 1

  if [ ! -d "$_proc/seg-001" ]; then
    _fail "dry_run_nao_remove" "dry-run removeu o segmento do sidecar"
    return 1
  fi
}

# =========================================================================
# Cenario 7 — prune real (remove segmento + linha de indice)
# =========================================================================
scenario_07_prune_real() {
  _have_deps || return 0
  _install_otel_stub
  _proc="$TMPDIR_TEST/.claude/cstk/loose-usage/proj7-old"
  _write_meta "$_proc" "/home/dev/proj7" "seg-001"
  _write_segment "$_proc" "seg-001" 1 "claude-sonnet-5" "0.05" "500"
  touch -t 202401010000 "$_proc/seg-001/closed" "$_proc/seg-001/otel-start.tsv"

  _db="$TMPDIR_TEST/k7.db"
  # Popula loose_usage via ingest-on-read (usa o mtime ANTIGO ja carimbado
  # acima como captured_at) antes de podar.
  assert_exit 0 _uc_home "$TMPDIR_TEST" --project proj7 --db "$_db" || return 1
  _n_before=$(sqlite3 -- "$_db" "SELECT count(*) FROM loose_usage WHERE process_key='proj7-old';" 2>/dev/null)
  [ "$_n_before" = "1" ] || { _fail "seed_loose_usage" "esperado 1 linha antes da poda, obtido $_n_before"; return 1; }

  assert_exit 0 _uc_home "$TMPDIR_TEST" prune --older-than-days 1 --db "$_db" || return 1
  assert_stdout_contains "action=removed process_key=proj7-old segment=seg-001" || return 1

  if [ -d "$_proc/seg-001" ]; then
    _fail "prune_real_remove_fs" "segmento nao foi removido do sidecar"
    return 1
  fi
  _n_after=$(sqlite3 -- "$_db" "SELECT count(*) FROM loose_usage WHERE process_key='proj7-old';" 2>/dev/null)
  [ "$_n_after" = "0" ] || { _fail "prune_real_remove_db" "esperado 0 linhas apos poda, obtido $_n_after"; return 1; }
}

# =========================================================================
# Cenario 8 — segmento ABERTO nunca e elegivel para poda, mesmo antigo
# =========================================================================
scenario_08_prune_segmento_aberto_nao_elegivel() {
  _have_deps || return 0
  _proc="$TMPDIR_TEST/.claude/cstk/loose-usage/proj8-open"
  _write_meta "$_proc" "/home/dev/proj8" "seg-001"
  _write_segment "$_proc" "seg-001" 0 "claude-sonnet-5" "0.05" "500"
  touch -t 202401010000 "$_proc/seg-001/otel-start.tsv" "$_proc/seg-001/otel-end.tsv"

  assert_exit 0 _uc_home "$TMPDIR_TEST" prune --dry-run --older-than-days 1 --db "$TMPDIR_TEST/k8.db" || return 1
  assert_stdout_contains "nada a podar" || return 1
}

# =========================================================================
# Cenario 9 — flag desconhecida -> exit 2
# =========================================================================
scenario_09_flag_desconhecida() {
  assert_exit 2 _uc_home "$TMPDIR_TEST" --bogus || return 1
}

# =========================================================================
# Cenario 10 — subcomando desconhecido -> exit 2
# =========================================================================
scenario_10_subcomando_desconhecido() {
  assert_exit 2 _uc_home "$TMPDIR_TEST" frobnicate || return 1
}

# =========================================================================
# Cenario 11 — --limit invalido -> exit 2
# =========================================================================
scenario_11_limit_invalido() {
  assert_exit 2 _uc_home "$TMPDIR_TEST" --limit abc || return 1
}

# =========================================================================
# Cenario 12 — --older-than-days nao-numerico -> exit 2
# =========================================================================
scenario_12_older_than_days_invalido() {
  assert_exit 2 _uc_home "$TMPDIR_TEST" prune --older-than-days abc || return 1
}

# =========================================================================
# Cenario 13 — Degradacao sem sqlite3 (exit 1)
# =========================================================================
scenario_13_sem_sqlite3() {
  _bin="$TMPDIR_TEST/bin13"
  mkdir -p "$_bin"
  for _t in tr wc printf sed grep awk basename dirname date find mkdir rm cat head sleep cp jq stat mktemp sh; do
    _p=$(command -v "$_t" 2>/dev/null) && ln -sf "$_p" "$_bin/$_t"
  done
  # (sqlite3 deliberadamente ausente)
  assert_exit 1 env PATH="$_bin" HOME="$TMPDIR_TEST" sh -c \
    '. "'"$CSTK_LIB"'/common.sh"; . "'"$CSTK_LIB"'/usage.sh"; usage_main --project x' || return 1
  assert_stderr_contains "sqlite3" || return 1

  assert_exit 1 env PATH="$_bin" HOME="$TMPDIR_TEST" sh -c \
    '. "'"$CSTK_LIB"'/common.sh"; . "'"$CSTK_LIB"'/usage.sh"; usage_main prune' || return 1
  assert_stderr_contains "sqlite3" || return 1
}

# =========================================================================
# Cenario 14 — prune sem sidecar -> "nada a podar", exit 0
# =========================================================================
scenario_14_prune_sem_sidecar() {
  _have_deps || return 0
  _home_vazio="$TMPDIR_TEST/home-vazio"
  mkdir -p "$_home_vazio"
  assert_exit 0 _uc_home "$_home_vazio" prune --db "$TMPDIR_TEST/k14.db" || return 1
  assert_stdout_contains "nada a podar" || return 1
}

# =========================================================================
# Cenario 15 — ingest-on-read idempotente (sem duplicar linhas)
# =========================================================================
scenario_15_ingest_idempotente() {
  _have_deps || return 0
  _install_otel_stub
  _proc="$TMPDIR_TEST/.claude/cstk/loose-usage/proj15-abc"
  _write_meta "$_proc" "/home/dev/proj15" "seg-001"
  _write_segment "$_proc" "seg-001" 0 "claude-sonnet-5" "0.10" "2000"

  _db="$TMPDIR_TEST/k15.db"
  assert_exit 0 _uc_home "$TMPDIR_TEST" --project proj15 --db "$_db" || return 1
  assert_exit 0 _uc_home "$TMPDIR_TEST" --project proj15 --db "$_db" || return 1

  _n=$(sqlite3 -- "$_db" "SELECT count(*) FROM loose_usage WHERE process_key='proj15-abc';" 2>/dev/null)
  [ "$_n" = "1" ] || { _fail "ingest_idempotente" "esperado 1 linha apos 2 ingest-on-read, obtido $_n"; return 1; }
}

run_all_scenarios
