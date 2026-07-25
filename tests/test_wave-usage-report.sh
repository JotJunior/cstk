#!/bin/sh
# test_wave-usage-report.sh — cobre
# global/skills/agente-00c-runtime/scripts/wave-usage-report.sh.
#
# Feature: wave-token-metrics
# Ref: docs/specs/wave-token-metrics/contracts/wave-usage-report.md §2
#      docs/specs/wave-token-metrics/tasks.md FASE 4 (4.1.4)
#
# Cobertura:
#   Dispatch:
#     - sem args -> exit 2 + USO em stderr
#     - subcomando desconhecido (inclusive "backfill", ainda nao
#       implementado — FASE 7) -> exit 2
#     - -h/--help/help -> exit 2 + USO
#   aggregate — uso invalido:
#     - sem --state-dir -> exit 2
#     - --state-dir inexistente (sem state.json) -> exit 1
#   aggregate — agregacao correta (fixture espelhando o exemplo do
#     contrato §2.1, validada byte-a-byte contra a Markdown do contrato):
#     - tabela com 2 ondas, contagens de spawns/tokens/tool-uses/duracao
#     - formatacao "k" (>=10000 -> N.Nk truncado; abaixo disso, cru)
#     - Sumario com "Ondas com metrica: 1 de 2", cobertura 40.0%
#     - JSON com todos os campos do contrato §2.2 + por_modelo
#   null vs 0 (Principio VI / FR-009):
#     - onda com spawns todos indisponivel -> total_tokens null, NUNCA 0
#     - onda sem nenhum spawn (agent_usage null) -> omitida da tabela
#   "metrica nao coletada" (research Decision 10):
#     - todas as ondas com agent_usage null -> Markdown com frase
#       explicita, sem tabela; JSON com metric_collected=false
#     - state.json sem campo .waves -> mesmo comportamento (retro-compat)
#   Distribuicao por modelo (US2):
#     - por_modelo agrega por .model, incluindo balde "nao-aplicavel"
#       para spawns indisponivel
#   Estabilidade da saida (IR-2):
#     - 3 invocacoes consecutivas -> stdout identico byte-a-byte (JSON e MD)
#     - read-only: sha256 do state.json inalterado apos aggregate
#   IR-3 (Principio II POSIX):
#     - shebang #!/bin/sh + set -eu
#
# Convencao de exit code de scenario (interpretada pelo runner):
#   0 PASS, 1 FAIL, 2 ERROR (pre-req faltando — jq ausente, mktemp falhou)

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/wave-usage-report.sh"

# ---------- helpers locais ----------

_wur_have_jq() {
  command -v jq >/dev/null 2>&1
}

# Fixture canonica: espelha ao pe da letra o exemplo do contrato §2.1/2.2
# (onda-004 com 3 spawns/2 com uso, onda-005 com 2 spawns/0 com uso, onda-006
# sem nenhum spawn -> agent_usage null, omitida da tabela).
_wur_write_fixture_contrato() {
  cat > "$TMPDIR_TEST/state.json" <<'JSON'
{
  "schema_version": 1,
  "waves": [
    {
      "id": "onda-004",
      "agent_usage": {
        "spawns_total": 3,
        "spawns_with_usage": 2,
        "spawns_unavailable": 1,
        "total_tokens": 254000,
        "input_tokens": 4,
        "output_tokens": 1975,
        "cache_read_input_tokens": 250900,
        "cache_creation_input_tokens": 1049,
        "tool_use_count": 72,
        "duration_ms": 923000
      },
      "agent_spawns": [
        {"agent_id":"a1","agent_type":"t1","status":"completo","model":"sonnet","models_used":null,"total_tokens":200000,"input_tokens":2,"output_tokens":1000,"cache_read_input_tokens":198000,"cache_creation_input_tokens":998,"tool_use_count":50,"duration_ms":600000,"source":"live","observed_at":"t"},
        {"agent_id":"a2","agent_type":"t2","status":"completo","model":"opus","models_used":null,"total_tokens":54000,"input_tokens":2,"output_tokens":975,"cache_read_input_tokens":52900,"cache_creation_input_tokens":51,"tool_use_count":22,"duration_ms":323000,"source":"live","observed_at":"t"},
        {"agent_id":"a3","agent_type":"t3","status":"indisponivel","model":"nao-aplicavel","models_used":null,"total_tokens":null,"input_tokens":null,"output_tokens":null,"cache_read_input_tokens":null,"cache_creation_input_tokens":null,"tool_use_count":null,"duration_ms":null,"source":"live","observed_at":"t"}
      ]
    },
    {
      "id": "onda-005",
      "agent_usage": {
        "spawns_total": 2,
        "spawns_with_usage": 0,
        "spawns_unavailable": 2,
        "total_tokens": null,
        "input_tokens": null,
        "output_tokens": null,
        "cache_read_input_tokens": null,
        "cache_creation_input_tokens": null,
        "tool_use_count": null,
        "duration_ms": null
      },
      "agent_spawns": [
        {"agent_id":"b1","agent_type":"t1","status":"indisponivel","model":"nao-aplicavel","models_used":null,"total_tokens":null,"input_tokens":null,"output_tokens":null,"cache_read_input_tokens":null,"cache_creation_input_tokens":null,"tool_use_count":null,"duration_ms":null,"source":"live","observed_at":"t"},
        {"agent_id":"b2","agent_type":"t2","status":"indisponivel","model":"nao-aplicavel","models_used":null,"total_tokens":null,"input_tokens":null,"output_tokens":null,"cache_read_input_tokens":null,"cache_creation_input_tokens":null,"tool_use_count":null,"duration_ms":null,"source":"live","observed_at":"t"}
      ]
    },
    {
      "id": "onda-006",
      "agent_usage": null,
      "agent_spawns": []
    }
  ]
}
JSON
}

# ==== Dispatch ====

scenario_sem_args_exit_2_e_usage_em_stderr() {
  capture sh "$SCRIPT"
  assert_exit 2 sh "$SCRIPT" || return 1
  assert_stderr_contains "USO:" || return 1
  assert_stderr_contains "aggregate" || return 1
}

scenario_subcomando_desconhecido_exit_2() {
  capture sh "$SCRIPT" bogus-subcmd-xyz
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit=2" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "subcomando desconhecido" || return 1
  assert_stderr_contains "bogus-subcmd-xyz" || return 1
}

# backfill (contract §3) e trabalho da FASE 7 (tasks.md 7.1.*) — nesta FASE
# 4 o dispatch ainda NAO conhece o subcomando; cai no branch generico.
scenario_backfill_ainda_nao_implementado_exit_2() {
  capture sh "$SCRIPT" backfill --state-dir /nao/importa --transcript /nao/importa
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit=2 (backfill nao implementado)" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "subcomando desconhecido" || return 1
}

scenario_help_flag_short_long_e_help_subcmd() {
  capture sh "$SCRIPT" -h
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit=2 (-h)" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "USO:" || return 1

  capture sh "$SCRIPT" --help
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit=2 (--help)" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "USO:" || return 1

  capture sh "$SCRIPT" help
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit=2 (help)" "obtido $_CAPTURED_EXIT"; return 1; }
}

# ==== aggregate: uso invalido ====

scenario_aggregate_sem_state_dir_exit_2() {
  capture sh "$SCRIPT" aggregate
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit=2 (sem --state-dir)" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "--state-dir obrigatorio" || return 1
}

scenario_aggregate_state_dir_inexistente_exit_1() {
  mktemp_test || return 2
  capture sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST/nope"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit=1 (sem state.json)" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "state.json nao encontrado" || return 1
}

scenario_aggregate_argumento_desconhecido_exit_2() {
  mktemp_test || return 2
  capture sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST" --bogus-flag
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit=2 (flag desconhecida)" "obtido $_CAPTURED_EXIT"; return 1; }
}

# ==== aggregate: fixture do contrato — Markdown byte-a-byte ====

scenario_aggregate_markdown_bate_com_exemplo_do_contrato() {
  _wur_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _wur_write_fixture_contrato

  capture sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit=0" "$_CAPTURED_STDERR"; return 1; }

  _expected='## Consumo por onda (tokens / tool-uses / duracao)

| onda | spawns | com uso | tokens | input | output | cache-read | cache-creation | tool-uses | duracao |
|------|--------|---------|--------|-------|--------|------------|----------------|-----------|---------|
| onda-004 | 3 | 2 | 254.0k | 4 | 1975 | 250.9k | 1049 | 72 | 923s |
| onda-005 | 2 | 0 | indisponivel | indisponivel | indisponivel | indisponivel | indisponivel | indisponivel | indisponivel |

**Sumario**:
- Ondas com metrica: 1 de 2
- Spawns observados: 5 (com uso: 2; indisponiveis: 3)
- Tokens totais: 254.0k (input 4 / output 1975 / cache-read 250.9k / cache-creation 1049)
- Cobertura da metrica: 40.0% dos spawns'

  [ "$_CAPTURED_STDOUT" = "$_expected" ] || {
    _fail "Markdown identico ao exemplo do contrato" \
      "diff:
$(diff <(printf '%s' "$_expected") <(printf '%s' "$_CAPTURED_STDOUT"))"
    return 1
  }

  # onda-006 (sem nenhum spawn) NAO aparece na tabela.
  assert_stdout_not_contains "onda-006" || return 1
}

scenario_aggregate_json_bate_com_contrato() {
  _wur_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _wur_write_fixture_contrato

  capture sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST" --json
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit=0" "$_CAPTURED_STDERR"; return 1; }

  _get() { printf '%s' "$_CAPTURED_STDOUT" | jq -r "$1"; }

  [ "$(_get '.waves_total')" = "2" ]         || { _fail "waves_total=2" "obtido $(_get '.waves_total')"; return 1; }
  [ "$(_get '.waves_with_usage')" = "1" ]    || { _fail "waves_with_usage=1" "obtido $(_get '.waves_with_usage')"; return 1; }
  [ "$(_get '.spawns_total')" = "5" ]        || { _fail "spawns_total=5" "obtido $(_get '.spawns_total')"; return 1; }
  [ "$(_get '.spawns_with_usage')" = "2" ]   || { _fail "spawns_with_usage=2" "obtido $(_get '.spawns_with_usage')"; return 1; }
  [ "$(_get '.spawns_unavailable')" = "3" ]  || { _fail "spawns_unavailable=3" "obtido $(_get '.spawns_unavailable')"; return 1; }
  [ "$(_get '.coverage_pct')" = "40.0%" ]    || { _fail "coverage_pct=40.0%" "obtido $(_get '.coverage_pct')"; return 1; }
  [ "$(_get '.total_tokens')" = "254000" ]   || { _fail "total_tokens=254000" "obtido $(_get '.total_tokens')"; return 1; }
  [ "$(_get '.input_tokens')" = "4" ]        || { _fail "input_tokens=4" "obtido $(_get '.input_tokens')"; return 1; }
  [ "$(_get '.output_tokens')" = "1975" ]    || { _fail "output_tokens=1975" "obtido $(_get '.output_tokens')"; return 1; }
  [ "$(_get '.cache_read_input_tokens')" = "250900" ]     || { _fail "cache_read=250900" "obtido $(_get '.cache_read_input_tokens')"; return 1; }
  [ "$(_get '.cache_creation_input_tokens')" = "1049" ]   || { _fail "cache_creation=1049" "obtido $(_get '.cache_creation_input_tokens')"; return 1; }
  [ "$(_get '.tool_use_count')" = "72" ]     || { _fail "tool_use_count=72" "obtido $(_get '.tool_use_count')"; return 1; }
  [ "$(_get '.duration_ms')" = "923000" ]    || { _fail "duration_ms=923000" "obtido $(_get '.duration_ms')"; return 1; }
  [ "$(_get '.metric_collected')" = "true" ] || { _fail "metric_collected=true" "obtido $(_get '.metric_collected')"; return 1; }
  [ "$(_get '.por_onda | length')" = "2" ]   || { _fail "por_onda tem 2 entradas" "obtido $(_get '.por_onda | length')"; return 1; }
}

# ==== null vs 0 (Principio VI / FR-009) ====

scenario_onda_todos_indisponivel_total_tokens_null_nao_zero() {
  _wur_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _wur_write_fixture_contrato

  capture sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST" --json
  _tt=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.por_onda[] | select(.onda == "onda-005") | .total_tokens')
  [ "$_tt" = "null" ] || { _fail "onda-005.total_tokens=null" "obtido $_tt (fabricacao de 0 proibida)"; return 1; }
}

scenario_onda_sem_spawns_omitida_da_tabela_json() {
  _wur_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _wur_write_fixture_contrato

  capture sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST" --json
  _n=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '[.por_onda[] | select(.onda == "onda-006")] | length')
  [ "$_n" = "0" ] || { _fail "onda-006 ausente de por_onda" "obtido $_n entradas"; return 1; }
}

# ==== "metrica nao coletada" (research Decision 10) ====

scenario_todas_ondas_sem_usage_metrica_nao_coletada() {
  _wur_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  cat > "$TMPDIR_TEST/state.json" <<'JSON'
{ "schema_version": 1, "waves": [
  { "id": "onda-001", "agent_usage": null, "agent_spawns": [] },
  { "id": "onda-002", "agent_usage": null, "agent_spawns": [] }
] }
JSON

  capture sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit=0" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "nao foi coletada" || return 1
  assert_stdout_not_contains "| onda" || return 1
  assert_stdout_not_contains "0 tokens totais" || return 1

  capture sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST" --json
  _mc=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.metric_collected')
  [ "$_mc" = "false" ] || { _fail "metric_collected=false" "obtido $_mc"; return 1; }
  _tt=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.total_tokens')
  [ "$_tt" = "null" ] || { _fail "total_tokens=null (nao 0)" "obtido $_tt"; return 1; }
}

scenario_state_sem_campo_waves_retro_compat() {
  _wur_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  printf '{"schema_version":1}' > "$TMPDIR_TEST/state.json"

  capture sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit=0 (state pre-feature sem .waves)" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "nao foi coletada" || return 1

  capture sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST" --json
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit=0 --json" "$_CAPTURED_STDERR"; return 1; }
  _wt=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.waves_total')
  [ "$_wt" = "0" ] || { _fail "waves_total=0" "obtido $_wt"; return 1; }
}

# ==== Distribuicao por modelo (US2) ====

scenario_por_modelo_agrupa_incluindo_nao_aplicavel() {
  _wur_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _wur_write_fixture_contrato

  capture sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST" --json
  _get() { printf '%s' "$_CAPTURED_STDOUT" | jq -r "$1"; }

  [ "$(_get '.por_modelo.sonnet.total_tokens')" = "200000" ] || { _fail "sonnet.total_tokens=200000" "obtido $(_get '.por_modelo.sonnet.total_tokens')"; return 1; }
  [ "$(_get '.por_modelo.opus.total_tokens')" = "54000" ]    || { _fail "opus.total_tokens=54000" "obtido $(_get '.por_modelo.opus.total_tokens')"; return 1; }
  # nao-aplicavel: 3 spawns indisponivel (a3 de onda-004 + b1/b2 de onda-005),
  # todos com uso zero -> total_tokens null (nunca 0).
  [ "$(_get '.por_modelo["nao-aplicavel"].spawns')" = "3" ]  || { _fail "nao-aplicavel.spawns=3" "obtido $(_get '.por_modelo["nao-aplicavel"].spawns')"; return 1; }
  [ "$(_get '.por_modelo["nao-aplicavel"].total_tokens')" = "null" ] || { _fail "nao-aplicavel.total_tokens=null" "obtido $(_get '.por_modelo["nao-aplicavel"].total_tokens')"; return 1; }
}

# ==== Estabilidade / read-only (IR-1, IR-2) ====

scenario_idempotente_json_e_markdown() {
  _wur_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _wur_write_fixture_contrato

  _j1=$(sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST" --json)
  _j2=$(sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST" --json)
  _j3=$(sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST" --json)
  [ "$_j1" = "$_j2" ] && [ "$_j2" = "$_j3" ] || { _fail "JSON identico em 3 invocacoes" "diferem"; return 1; }

  _m1=$(sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST")
  _m2=$(sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST")
  [ "$_m1" = "$_m2" ] || { _fail "Markdown identico em 2 invocacoes" "diferem"; return 1; }
}

scenario_read_only_state_json_inalterado() {
  _wur_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _wur_write_fixture_contrato

  _before=$(_sha256_of "$TMPDIR_TEST/state.json")
  sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST" >/dev/null
  sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST" --json >/dev/null
  _after=$(_sha256_of "$TMPDIR_TEST/state.json")
  [ "$_before" = "$_after" ] || { _fail "state.json inalterado (read-only)" "sha256 mudou"; return 1; }
}

_sha256_of() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

# ==== IR-3: Principio II POSIX ====

scenario_shebang_posix_e_set_eu() {
  _head1=$(head -n1 "$SCRIPT")
  [ "$_head1" = "#!/bin/sh" ] || { _fail "shebang #!/bin/sh" "obtido: $_head1"; return 1; }
  grep -q '^set -eu$' "$SCRIPT" || { _fail "set -eu presente" "nao encontrado"; return 1; }
}

run_all_scenarios "$0"
