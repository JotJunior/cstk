#!/bin/sh
# test_state-cache.sh — cobre global/skills/agente-00c-runtime/scripts/state-cache.sh.
#
# Ref: docs/specs/_archived/agente-00c-artifact-cache/tasks.md T1.5
#      docs/specs/_archived/agente-00c-artifact-cache/spec.md SC-005 (>= 15 cenarios)

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-cache.sh"
RW="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-rw.sh"

if ! command -v jq >/dev/null 2>&1; then
  printf '# test_state-cache.sh: jq ausente — pulando suite\n'
  exit 0
fi

# Helpers

_init_state() {
  # HOME sandbox SEM config global: forca backend JSON deterministico mesmo
  # em hosts com `state_backend=sqlite` em ~/.claude/cstk/config (padrao de
  # hermeticidade do test__state-read.sh; state-db-runtime-parity 2.4.4).
  _is_home="$TMPDIR_TEST/home-json"
  mkdir -p "$_is_home"
  capture env HOME="$_is_home" "$RW" init --state-dir "$1" \
    --execucao-id "exec-cache-test" \
    --projeto-alvo-path "/tmp/p" \
    --descricao "test cache"
  [ "$_CAPTURED_EXIT" = 0 ]
}

_make_small_source() {
  cat >"$1" <<'EOF'
# Briefing pequeno

## Visao
Sistema de teste.

## Usuarios
Devs.
EOF
}

_make_big_source() {
  _i=0
  {
    printf '# Briefing grande\n\n'
    while [ "$_i" -lt 60 ]; do
      printf '## Secao %d\n\nConteudo descritivo da secao %d explicando o que ela faz.\n\n' "$_i" "$_i"
      _i=$((_i + 1))
    done
  } >"$1"
}

# Ensure helper que usa $_sd e $_src
_ensure() {
  assert_exit 0 "$SCRIPT" ensure --state-dir "$1" --artifact briefing --source-path "$2"
}

# ==== Cenarios ====

scenario_ensure_passthrough_arquivo_pequeno() {
  _sd="$TMPDIR_TEST/state"
  _src="$TMPDIR_TEST/briefing.md"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  _make_small_source "$_src"
  assert_exit 0 "$SCRIPT" ensure --state-dir "$_sd" --artifact briefing --source-path "$_src" || return 1
  assert_stderr_contains "estrategia=passthrough" || return 1
}

scenario_ensure_resumo_arquivo_grande() {
  _sd="$TMPDIR_TEST/state"
  _src="$TMPDIR_TEST/briefing.md"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  _make_big_source "$_src"
  assert_exit 0 "$SCRIPT" ensure --state-dir "$_sd" --artifact briefing --source-path "$_src" || return 1
  assert_stderr_contains "estrategia=resumo" || return 1
}

scenario_ensure_source_ausente_exit_1() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  assert_exit 1 "$SCRIPT" ensure --state-dir "$_sd" --artifact briefing --source-path "/tmp/nonexistent-state-cache-$$"
}

scenario_ensure_state_dir_ausente_exit_2() {
  # source-path PRECISA existir, senao o check de source (exit 1) acontece antes do de state-dir (exit 2)
  _src="$TMPDIR_TEST/dummy-src.md"
  printf '# x\n' >"$_src"
  assert_exit 2 "$SCRIPT" ensure --state-dir "/tmp/no-such-state-$$" --artifact briefing --source-path "$_src"
}

scenario_ensure_artifact_invalido_exit_2() {
  _sd="$TMPDIR_TEST/state"
  _src="$TMPDIR_TEST/dummy-src.md"
  printf '# x\n' >"$_src"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  assert_exit 2 "$SCRIPT" ensure --state-dir "$_sd" --artifact "spec" --source-path "$_src"
}

scenario_get_resumo_hit_retorna_conteudo() {
  _sd="$TMPDIR_TEST/state"
  _src="$TMPDIR_TEST/briefing.md"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  _make_big_source "$_src"
  _ensure "$_sd" "$_src" || return 1
  assert_exit 0 "$SCRIPT" get-resumo --state-dir "$_sd" --artifact briefing || return 1
  assert_stdout_contains "## Secao" || return 1
}

scenario_get_resumo_passthrough_exit_1() {
  _sd="$TMPDIR_TEST/state"
  _src="$TMPDIR_TEST/briefing.md"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  _make_small_source "$_src"
  _ensure "$_sd" "$_src" || return 1
  assert_exit 1 "$SCRIPT" get-resumo --state-dir "$_sd" --artifact briefing
}

scenario_get_resumo_cache_vazio_exit_1() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  assert_exit 1 "$SCRIPT" get-resumo --state-dir "$_sd" --artifact briefing
}

scenario_get_resumo_drift_dispara_miss() {
  _sd="$TMPDIR_TEST/state"
  _src="$TMPDIR_TEST/briefing.md"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  _make_big_source "$_src"
  _ensure "$_sd" "$_src" || return 1
  printf '\n\n## Nova secao apos cache\n\nNovo conteudo.\n' >>"$_src"
  assert_exit 1 "$SCRIPT" get-resumo --state-dir "$_sd" --artifact briefing
}

scenario_check_drift_sem_mudanca_exit_0() {
  _sd="$TMPDIR_TEST/state"
  _src="$TMPDIR_TEST/briefing.md"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  _make_big_source "$_src"
  _ensure "$_sd" "$_src" || return 1
  assert_exit 0 "$SCRIPT" check-drift --state-dir "$_sd" --artifact briefing
}

scenario_check_drift_minor_exit_1() {
  _sd="$TMPDIR_TEST/state"
  _src="$TMPDIR_TEST/briefing.md"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  _make_big_source "$_src"
  _ensure "$_sd" "$_src" || return 1
  printf '\n\n## Mais uma\n\nTexto curto.\n' >>"$_src"
  assert_exit 1 "$SCRIPT" check-drift --state-dir "$_sd" --artifact briefing
}

scenario_check_drift_major_chars_exit_2() {
  _sd="$TMPDIR_TEST/state"
  _src="$TMPDIR_TEST/briefing.md"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  _make_big_source "$_src"
  _ensure "$_sd" "$_src" || return 1
  printf '# Briefing\n## Visao\nso isso.\n' >"$_src"
  assert_exit 2 "$SCRIPT" check-drift --state-dir "$_sd" --artifact briefing
}

scenario_check_drift_source_sumiu_exit_2() {
  _sd="$TMPDIR_TEST/state"
  _src="$TMPDIR_TEST/briefing.md"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  _make_big_source "$_src"
  _ensure "$_sd" "$_src" || return 1
  rm -f -- "$_src"
  assert_exit 2 "$SCRIPT" check-drift --state-dir "$_sd" --artifact briefing
}

scenario_check_drift_cache_vazio_exit_0() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  assert_exit 0 "$SCRIPT" check-drift --state-dir "$_sd" --artifact briefing
}

scenario_invalidate_zera_cache() {
  _sd="$TMPDIR_TEST/state"
  _src="$TMPDIR_TEST/briefing.md"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  _make_big_source "$_src"
  _ensure "$_sd" "$_src" || return 1
  assert_exit 0 "$SCRIPT" invalidate --state-dir "$_sd" --artifact briefing --razao "test" || return 1
  assert_exit 0 "$SCRIPT" status --state-dir "$_sd" --artifact briefing || return 1
  assert_stdout_contains "null" || return 1
}

scenario_invalidate_sem_razao_exit_2() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  assert_exit 2 "$SCRIPT" invalidate --state-dir "$_sd" --artifact briefing
}

scenario_metrics_bump_hit_incrementa_contador() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  assert_exit 0 "$SCRIPT" metrics-bump --state-dir "$_sd" --tipo hit --chars-economizados 2000 || return 1
  _val=$(jq -r '.accumulated_metrics.cache.tokens_cache_hits // 0' "$_sd/state.json")
  if [ "$_val" != "1" ]; then
    _fail "tokens_cache_hits esperado 1, got $_val"
    return 1
  fi
  _tok=$(jq -r '.accumulated_metrics.cache.estimated_tokens_saved // 0' "$_sd/state.json")
  if [ "$_tok" != "500" ]; then
    _fail "estimated_tokens_saved esperado 500, got $_tok"
    return 1
  fi
}

scenario_metrics_bump_miss_drift() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  assert_exit 0 "$SCRIPT" metrics-bump --state-dir "$_sd" --tipo miss-drift || return 1
  _val=$(jq -r '.accumulated_metrics.cache.tokens_cache_misses_drift // 0' "$_sd/state.json")
  if [ "$_val" != "1" ]; then
    _fail "miss-drift esperado 1, got $_val"
    return 1
  fi
}

scenario_metrics_bump_tipo_invalido_exit_2() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  assert_exit 2 "$SCRIPT" metrics-bump --state-dir "$_sd" --tipo "invalido"
}

scenario_status_cache_vazio_retorna_null() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  assert_exit 0 "$SCRIPT" status --state-dir "$_sd" --artifact briefing || return 1
  assert_stdout_contains "null" || return 1
}

scenario_ensure_resumo_chars_menor_que_source() {
  _sd="$TMPDIR_TEST/state"
  _src="$TMPDIR_TEST/briefing.md"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  _make_big_source "$_src"
  _ensure "$_sd" "$_src" || return 1
  # WRITER agora emite chaves EN (schema-en-migration §3.9d): summary_chars.
  _src_chars=$(jq -r '.briefing_cache.source_chars' "$_sd/state.json")
  _res_chars=$(jq -r '.briefing_cache.summary_chars' "$_sd/state.json")
  if [ "$_res_chars" -ge "$_src_chars" ]; then
    _fail "FR-CACHE-017: summary_chars ($_res_chars) deve ser < source_chars ($_src_chars)"
    return 1
  fi
}

# Back-compat (schema-en-migration): state.json legado pt-BR com `.ondas`
# (em vez de `.waves`). O reader de `ensure` que conta ondas deve cair no
# fallback `(.waves // .ondas)` e contar 2 ondas legadas. O WRITER, porem,
# grava a folha EN `generated_in_wave` (state-en-migration §3.9d). Prova de
# regressao: le container pt legado, escreve folha EN.
scenario_ensure_le_ondas_pt_legado_fallback() {
  _sd="$TMPDIR_TEST/state-pt"
  _src="$TMPDIR_TEST/briefing.md"
  mkdir -p "$_sd"
  cat >"$_sd/state.json" <<'EOF'
{
  "schema_version": 7,
  "ondas": [{"id": "onda-001"}, {"id": "onda-002"}],
  "metricas_acumuladas": {}
}
EOF
  _make_big_source "$_src"
  assert_exit 0 "$SCRIPT" ensure --state-dir "$_sd" --artifact briefing --source-path "$_src" || return 1
  _gon=$(jq -r '.briefing_cache.generated_in_wave' "$_sd/state.json")
  if [ "$_gon" != "2" ]; then
    _fail "fallback .ondas: generated_in_wave (EN) esperado 2 (contagem de ondas legadas pt), got $_gon"
    return 1
  fi
}

# WRITER contract (schema-en-migration §3.9d): `ensure` deve emitir AS folhas
# EN (summary, summary_chars, strategy, generated_at, generated_in_wave) e NAO
# as pt-BR. Source_* permanecem (keep). Trava o lado escritor do par.
scenario_ensure_grava_chaves_en() {
  _sd="$TMPDIR_TEST/state"
  _src="$TMPDIR_TEST/briefing.md"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  _make_big_source "$_src"
  _ensure "$_sd" "$_src" || return 1
  # Folhas EN presentes
  for _k in summary summary_chars strategy generated_at generated_in_wave \
            source_path source_sha256 source_chars; do
    _has=$(jq -r --arg k "$_k" 'if (.briefing_cache | has($k)) then "yes" else "no" end' "$_sd/state.json")
    if [ "$_has" != "yes" ]; then
      _fail "WRITER §3.9d: briefing_cache.$_k (EN) ausente apos ensure"
      return 1
    fi
  done
  # Folhas pt-BR NAO devem existir no output do writer
  for _k in resumo resumo_chars estrategia gerado_em gerado_na_onda; do
    _has=$(jq -r --arg k "$_k" 'if (.briefing_cache | has($k)) then "yes" else "no" end' "$_sd/state.json")
    if [ "$_has" != "no" ]; then
      _fail "WRITER §3.9d: briefing_cache.$_k (pt-BR) NAO deveria ser escrito"
      return 1
    fi
  done
  # VALOR de strategy permanece pt-BR (follow-up B): "resumo"
  _str=$(jq -r '.briefing_cache.strategy' "$_sd/state.json")
  if [ "$_str" != "resumo" ]; then
    _fail "VALOR de strategy deve permanecer 'resumo' (follow-up B), got $_str"
    return 1
  fi
}

# READER fallback (schema-en-migration §4.3): get-resumo deve LER um cache
# legado pt-BR (estrategia/resumo). Construimos via ensure (EN) e renomeamos
# as folhas de volta para pt-BR p/ simular state legado; o reader cai no
# fallback (.strategy // .estrategia) e (.summary // .resumo). Prova de
# regressao do lado leitor do par coordenado.
scenario_get_resumo_le_cache_pt_legado_fallback() {
  _sd="$TMPDIR_TEST/state"
  _src="$TMPDIR_TEST/briefing.md"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  _make_big_source "$_src"
  _ensure "$_sd" "$_src" || return 1
  # Renomeia folhas EN -> pt-BR no briefing_cache (simula state legado)
  _tmp="$_sd/state.json.tmp"
  jq '.briefing_cache |= (
        .estrategia = .strategy | del(.strategy)
      | .resumo = .summary | del(.summary)
      | .resumo_chars = .summary_chars | del(.summary_chars)
      | .gerado_em = .generated_at | del(.generated_at)
      | .gerado_na_onda = .generated_in_wave | del(.generated_in_wave)
      )' "$_sd/state.json" >"$_tmp" && mv -f "$_tmp" "$_sd/state.json"
  # get-resumo deve dar hit (le estrategia/resumo via fallback)
  assert_exit 0 "$SCRIPT" get-resumo --state-dir "$_sd" --artifact briefing || return 1
  assert_stdout_contains "## Secao" || return 1
}

# READ-MODIFY-WRITE fallback (schema-en-migration §3.9d): metrics-bump hit
# deve SEED o acumulador a partir do pt-BR tokens_economizados_estimados (state
# legado) e escrever no EN estimated_tokens_saved. Prova: contador legado=1000
# + 500 (deste hit) = 1500, gravado sob a chave EN.
scenario_metrics_bump_hit_seed_pt_legado_fallback() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd" || { _error "init falhou"; return 2; }
  # Injeta contador legado pt-BR
  _tmp="$_sd/state.json.tmp"
  jq '.accumulated_metrics.cache.tokens_economizados_estimados = 1000' \
    "$_sd/state.json" >"$_tmp" && mv -f "$_tmp" "$_sd/state.json"
  assert_exit 0 "$SCRIPT" metrics-bump --state-dir "$_sd" --tipo hit --chars-economizados 2000 || return 1
  _tok=$(jq -r '.accumulated_metrics.cache.estimated_tokens_saved // 0' "$_sd/state.json")
  if [ "$_tok" != "1500" ]; then
    _fail "fallback seed: estimated_tokens_saved esperado 1500 (1000 legado + 500), got $_tok"
    return 1
  fi
}

scenario_subcomando_desconhecido_exit_2() {
  assert_exit 2 "$SCRIPT" "comando-invalido"
}

scenario_sem_subcomando_exit_2() {
  assert_exit 2 "$SCRIPT"
}

# ==== Backend SQLite (state-db-runtime-parity FASE 2.4 / FR-001 / SC-003) ====
# get-resumo/status/check-drift leem via _state-read.sh; ensure grava as
# colunas json briefing_cache/constitution_cache via state-rw.sh set;
# metrics-bump grava .accumulated_metrics.cache (extra_fields.cache_metrics
# no sqlite — dec-052).

_sqlite3_adequate() {
  command -v sqlite3 >/dev/null 2>&1 || return 1
  _v=$(sqlite3 --version 2>/dev/null | cut -d' ' -f1) || return 1
  [ -n "$_v" ]
}

_init_sqlite() {
  _is_home="$TMPDIR_TEST/home-sqlite"
  mkdir -p "$_is_home/.claude/cstk"
  printf 'state_backend=sqlite\n' > "$_is_home/.claude/cstk/config"
  env HOME="$_is_home" "$RW" init --state-dir "$1" \
    --execucao-id "exec-cache-sqlite" --projeto-alvo-path "/tmp/p" \
    --descricao "POC cache sqlite" >/dev/null 2>&1 || return 1
  [ -f "$1/state.db" ] || return 1
}

scenario_sqlite_ensure_e_get_resumo_hit() {
  _sqlite3_adequate || { printf "# skip: sqlite3 indisponivel\n"; return 0; }
  _sd="$TMPDIR_TEST/state-sqlite"; _src="$TMPDIR_TEST/brief-sqlite.md"
  _init_sqlite "$_sd" || { _fail "fixture sqlite" "init nao gerou state.db"; return 1; }
  _make_big_source "$_src"
  capture "$SCRIPT" ensure --state-dir "$_sd" --artifact briefing --source-path "$_src"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "ensure sqlite" "exit $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  case "$_CAPTURED_STDERR" in
    *"state.json ausente"*) _fail "ensure sqlite" "degradou com 'state.json ausente'"; return 1 ;;
  esac
  capture "$SCRIPT" get-resumo --state-dir "$_sd" --artifact briefing
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "get-resumo sqlite" "exit $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "Secao" || return 1
  capture "$SCRIPT" status --state-dir "$_sd" --artifact briefing
  assert_stdout_contains "resumo" || return 1
}

scenario_sqlite_metrics_bump_persiste_cache_metrics() {
  _sqlite3_adequate || { printf "# skip: sqlite3 indisponivel\n"; return 0; }
  _sd="$TMPDIR_TEST/state-sqlite"
  _init_sqlite "$_sd" || { _fail "fixture sqlite" "init nao gerou state.db"; return 1; }
  capture "$SCRIPT" metrics-bump --state-dir "$_sd" --tipo hit --chars-economizados 400
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "bump hit sqlite" "exit $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" metrics-bump --state-dir "$_sd" --tipo hit --chars-economizados 400
  capture "$SCRIPT" metrics-bump --state-dir "$_sd" --tipo miss-drift
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "bump miss sqlite" "exit $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  _cache=$("$RW" read --state-dir "$_sd" | jq -c '.accumulated_metrics.cache')
  _hits=$(printf '%s' "$_cache" | jq -r '.tokens_cache_hits')
  _saved=$(printf '%s' "$_cache" | jq -r '.estimated_tokens_saved')
  _drift=$(printf '%s' "$_cache" | jq -r '.tokens_cache_misses_drift')
  [ "$_hits" = "2" ] || { _fail "hits sqlite" "esperado 2, obtido $_hits ($_cache)"; return 1; }
  [ "$_saved" = "200" ] || { _fail "saved sqlite" "esperado 200, obtido $_saved"; return 1; }
  [ "$_drift" = "1" ] || { _fail "drift sqlite" "esperado 1, obtido $_drift"; return 1; }
}

scenario_sqlite_invalidate_e_anti_mirror() {
  _sqlite3_adequate || { printf "# skip: sqlite3 indisponivel\n"; return 0; }
  _sd="$TMPDIR_TEST/state-sqlite"; _src="$TMPDIR_TEST/brief-sqlite.md"
  _init_sqlite "$_sd" || { _fail "fixture sqlite" "init nao gerou state.db"; return 1; }
  _make_small_source "$_src"
  capture "$SCRIPT" ensure --state-dir "$_sd" --artifact briefing --source-path "$_src"
  capture "$SCRIPT" invalidate --state-dir "$_sd" --artifact briefing --razao "teste sqlite"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "invalidate sqlite" "exit $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" status --state-dir "$_sd" --artifact briefing
  assert_stdout_contains "null" || return 1
  # FR-003: nenhuma operacao pode materializar state.json no state-dir.
  if [ -f "$_sd/state.json" ]; then
    _fail "anti-mirror" "state-cache criou state.json dentro do state-dir sqlite"
    return 1
  fi
}

run_all_scenarios
