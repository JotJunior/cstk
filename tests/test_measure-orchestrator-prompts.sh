#!/bin/sh
# test_measure-orchestrator-prompts.sh — testes de scripts/measure-orchestrator-prompts.sh
#
# Ref: docs/specs/orchestrator-slim/contracts/measure-cli.md
#      docs/specs/orchestrator-slim/spec.md FR-011, FR-012, FR-013, FR-017
#
# Cobre: medicao deterministica contra o baseline (9f97e99), tokens
# `indisponivel` sem ORCH_TOKEN_COUNTER e com contador, --db inexistente
# (exit 0), data invalida/injecao (exit 2), ref inexistente (exit 1), e a
# secao --observed sobre um banco sintetico (n, cobertura, mediana so sobre
# nao-nulos, nota fixa de cache_creation).

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

MEASURE="$REPO_ROOT/scripts/measure-orchestrator-prompts.sh"
BASELINE="9f97e994d5cde46d1447744c68c9def8da14e6e3"
PB_ROOT="plugins/cstk/agents/agente-00c-orchestrator.md"
PB_FEAT="plugins/cstk/agents/agente-00c-feature-orchestrator.md"

_need_baseline() {
  git -C "$REPO_ROOT" cat-file -e "$BASELINE^{commit}" 2>/dev/null || {
    _error "baseline ausente" "commit $BASELINE nao encontrado neste clone (fetch completo necessario)"
    return 2
  }
}

# Corpo da medicao sem a linha de data (varia a cada execucao).
_strip_date() {
  grep -v 'data UTC da medicao'
}

# ==== Determinismo e valores do baseline ====

scenario_baseline_bytes_batem_com_wc() {
  _need_baseline || return 2
  _exp_root=$(git -C "$REPO_ROOT" show "$BASELINE:$PB_ROOT" | wc -c | tr -d ' ')
  _exp_feat=$(git -C "$REPO_ROOT" show "$BASELINE:$PB_FEAT" | wc -c | tr -d ' ')
  [ "$_exp_root" = "146014" ] || { _error "baseline" "root=$_exp_root (esperado 146014)"; return 2; }
  [ "$_exp_feat" = "104702" ] || { _error "baseline" "feature=$_exp_feat (esperado 104702)"; return 2; }
  assert_exit 0 sh "$MEASURE" --ref "$BASELINE" || return 1
  assert_stdout_contains "| root | 146014 | indisponivel |" || return 1
  assert_stdout_contains "| feature | 104702 | indisponivel |" || return 1
  # baseline sem referencias: ref_bytes = 0 e loaded = base em toda fase
  assert_stdout_contains "| root | clarify | 146014 | 0 | 146014 | indisponivel |" || return 1
  assert_stdout_contains "| feature | toolkit-issue | 104702 | 0 | 104702 | indisponivel |" || return 1
}

scenario_medicao_e_deterministica() {
  _need_baseline || return 2
  sh "$MEASURE" --ref "$BASELINE" | _strip_date > "$TMPDIR_TEST/a.md"
  sh "$MEASURE" --ref "$BASELINE" | _strip_date > "$TMPDIR_TEST/b.md"
  assert_exit 0 cmp -s "$TMPDIR_TEST/a.md" "$TMPDIR_TEST/b.md" || return 1
}

scenario_le_do_ref_e_nao_da_arvore_de_trabalho() {
  _need_baseline || return 2
  # O cabecalho registra o sha completo do ref medido.
  assert_exit 0 sh "$MEASURE" --ref "$BASELINE" || return 1
  assert_stdout_contains "$BASELINE" || return 1
  assert_stdout_contains "baseline oficial" || return 1
}

# ==== Tokens (FR-011 / dec-010) ====

scenario_sem_contador_declara_gate_em_bytes() {
  _need_baseline || return 2
  assert_exit 0 env -u ORCH_TOKEN_COUNTER sh "$MEASURE" --ref "$BASELINE" || return 1
  assert_stdout_contains "Gate de FR-018 avaliado em bytes (dec-010)" || return 1
  assert_stdout_contains "Tokens NUNCA derivados de bytes" || return 1
}

scenario_com_contador_registra_comando_e_usa_saida() {
  _need_baseline || return 2
  # Contador sintetico: conta LINHAS (nao bytes), provando que tokens nao sao
  # derivados de bytes.
  _lines=$(git -C "$REPO_ROOT" show "$BASELINE:$PB_ROOT" | wc -l | tr -d ' ')
  assert_exit 0 env ORCH_TOKEN_COUNTER='wc -l' sh "$MEASURE" --ref "$BASELINE" || return 1
  assert_stdout_contains "comando externo \`wc -l\`" || return 1
  assert_stdout_contains "| root | 146014 | $_lines |" || return 1
}

scenario_contador_nao_numerico_vira_indisponivel() {
  _need_baseline || return 2
  assert_exit 0 env ORCH_TOKEN_COUNTER='echo abc' sh "$MEASURE" --ref "$BASELINE" || return 1
  assert_stdout_contains "| root | 146014 | indisponivel |" || return 1
}

# ==== Uso incorreto e erros ====

scenario_sem_ref_e_uso_incorreto() {
  assert_exit 2 sh "$MEASURE" || return 1
}

scenario_ref_inexistente_sai_1() {
  assert_exit 1 sh "$MEASURE" --ref refs/heads/nao-existe-orchestrator-slim || return 1
}

scenario_data_invalida_sai_2() {
  _need_baseline || return 2
  assert_exit 2 sh "$MEASURE" --ref "$BASELINE" --observed --until "2026-13-xx" || return 1
  assert_exit 2 sh "$MEASURE" --ref "$BASELINE" --observed --since "ontem" || return 1
}

scenario_data_com_injecao_sql_sai_2() {
  _need_baseline || return 2
  assert_exit 2 sh "$MEASURE" --ref "$BASELINE" --observed --since "2026-01-01' OR '1'='1" || return 1
}

# ==== Secao observada (FR-012 / FR-017) ====

scenario_db_inexistente_sai_0_com_indisponivel() {
  _need_baseline || return 2
  assert_exit 0 sh "$MEASURE" --ref "$BASELINE" --observed --db "$TMPDIR_TEST/nao-existe.db" || return 1
  assert_stdout_contains "## Consumo observado (knowledge.db)" || return 1
  assert_stdout_contains "indisponivel: banco nao encontrado" || return 1
}

scenario_sem_observed_nao_emite_secao_observada() {
  _need_baseline || return 2
  assert_exit 0 sh "$MEASURE" --ref "$BASELINE" || return 1
  assert_stdout_not_contains "Consumo observado" || return 1
}

_make_synthetic_db() {
  command -v sqlite3 >/dev/null 2>&1 || { _error "sqlite3 ausente" "scenario exige sqlite3"; return 2; }
  _db="$TMPDIR_TEST/kdb.sqlite"
  sqlite3 "$_db" "
    CREATE TABLE waves (
      id INTEGER PRIMARY KEY, execution_id TEXT, stages TEXT, started_at TEXT,
      otel_total_tokens INTEGER, otel_subagent_cache_creation_tokens INTEGER,
      otel_main_cache_creation_tokens INTEGER);
    INSERT INTO waves (execution_id, stages, started_at, otel_total_tokens, otel_subagent_cache_creation_tokens, otel_main_cache_creation_tokens) VALUES
      ('feat-x-1','plan','2020-01-01T10:00:00Z',100,10,NULL),
      ('feat-x-1','plan','2020-01-02T10:00:00Z',300,NULL,NULL),
      ('feat-x-2','plan','2020-01-03T10:00:00Z',NULL,NULL,NULL),
      ('feat-x-2','plan','2020-01-04T10:00:00Z',200,30,7),
      ('exec-2020-agente-00c-y','clarify','2020-01-05T10:00:00Z',50,5,NULL),
      ('feat-x-3','plan,clarify','2020-01-06T10:00:00Z',900,90,NULL),
      ('feat-x-4','plan','2021-06-01T10:00:00Z',999999,999999,999999),
      ('outro-1','plan','2020-01-07T10:00:00Z',777,77,7);
  "
  printf '%s' "$_db"
}

scenario_observado_traz_n_cobertura_e_mediana_so_de_nao_nulos() {
  _need_baseline || return 2
  _db=$(_make_synthetic_db) || return 2
  assert_exit 0 sh "$MEASURE" --ref "$BASELINE" --observed --db "$_db" \
    --since 2020-01-01 --until 2020-02-01 || return 1
  # feature-00c/plan: 4 ondas na janela; total_tokens presente em 3 (100,300,200
  # => mediana 200); subagent_cache em 2 (10,30 => mediana 20, par); main em 1.
  assert_stdout_contains "| feature-00c | plan | 4 | 3/4; 200 | 2/4; 20 | 1/4; 7 |" || return 1
  # agente-00c/clarify: main_cache sem valor => indisponivel (0/1)
  assert_stdout_contains "| agente-00c | clarify | 1 | 1/1; 50 | 1/1; 5 | indisponivel (0/1) |" || return 1
  # multi-etapa isolada; execucao fora dos dois grupos e onda fora da janela
  # nao entram.
  assert_stdout_contains "| feature-00c | (multi-etapa ou vazio) | 1 | 1/1; 900 | 1/1; 90 | indisponivel (0/1) |" || return 1
  assert_stdout_not_contains "999999" || return 1
  assert_stdout_not_contains "777" || return 1
}

scenario_observado_traz_nota_fixa_de_cache_creation() {
  _need_baseline || return 2
  _db=$(_make_synthetic_db) || return 2
  assert_exit 0 sh "$MEASURE" --ref "$BASELINE" --observed --db "$_db" \
    --since 2020-01-01 --until 2020-02-01 || return 1
  assert_stdout_contains "cache_creation inclui resultados de tool e turnos; nao isola o prompt-base" || return 1
}

scenario_observado_janela_vazia_e_indisponivel() {
  _need_baseline || return 2
  _db=$(_make_synthetic_db) || return 2
  assert_exit 0 sh "$MEASURE" --ref "$BASELINE" --observed --db "$_db" \
    --since 2030-01-01 --until 2030-02-01 || return 1
  assert_stdout_contains "indisponivel: nenhuma onda na janela informada (n = 0)" || return 1
}

run_all_scenarios "$0"
