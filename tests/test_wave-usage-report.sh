#!/bin/sh
# test_wave-usage-report.sh — cobre
# global/skills/agente-00c-runtime/scripts/wave-usage-report.sh.
#
# Feature: wave-token-metrics
# Ref: docs/specs/wave-token-metrics/contracts/wave-usage-report.md §2/§3
#      docs/specs/wave-token-metrics/tasks.md FASE 4 (4.1.4) e FASE 7 (7.1.5)
#
# Cobertura:
#   Dispatch:
#     - sem args -> exit 2 + USO em stderr
#     - subcomando desconhecido -> exit 2
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
#   backfill (US4/FR-010/FR-011, FASE 7):
#     - uso invalido: sem --state-dir / sem --transcript -> exit 2
#     - transcript ausente/ilegivel -> exit 3, mensagem nomeia a execucao
#     - transcript sem nenhum spawn dentro de janela de onda -> exit 3
#       (nao confundir com "0 novos" por dedup — ver idempotencia)
#     - happy path: spawns extraidos + atribuidos a onda por janela
#       temporal, source="backfill" sempre, status/null-vs-0 identicos as
#       regras do hook ao vivo (indisponivel -> todos os campos null)
#     - linha corrompida no meio do transcript e ignorada (nao aborta)
#     - idempotencia: reexecutar sobre o mesmo transcript -> 0 novos
#       spawns, state.json byte-identico (sha256 inalterado), sem backup
#       novo em state-history/
#     - --dry-run: reporta onda+agent_id sem escrever nada (sha256
#       inalterado, sem state-history/ novo)
#     - apos apply: state-history/ ganha snapshot, state.json.sha256
#       recomputado (sha256-verify passa), accumulated_metrics.agent_*
#       incrementados pelo delta correto
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
    # diff via arquivos temporarios — process substitution <(...) e bashism
    # e quebra no dash do CI (POSIX sh).
    _exp_f="$TMPDIR_TEST/expected.md"
    _got_f="$TMPDIR_TEST/got.md"
    printf '%s' "$_expected" > "$_exp_f"
    printf '%s' "$_CAPTURED_STDOUT" > "$_got_f"
    _fail "Markdown identico ao exemplo do contrato" \
      "diff:
$(diff "$_exp_f" "$_got_f")"
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

# ==== FASE 6 (feature wave-token-metrics): cruzamento com model-routing
# em review-task/SKILL.md §4.5 (F5, US2/FR-007) ====
#
# review-task/SKILL.md nao tem harness automatizado proprio (skill
# prose-driven, sem script dedicado) — cobertura aqui segue o mesmo
# padrao "sanity" ja usado em test_model-routing-report.sh
# (scenario_integracao_review_task_skill_md_referencia_helper): grep-based,
# falha cedo se a SKILL.md for reformatada/perder a secao.

scenario_skill_md_referencia_cruzamento_wave_usage() {
  _skill="$REPO_ROOT/global/skills/review-task/SKILL.md"
  [ -f "$_skill" ] || { _fail "SKILL.md ausente" "$_skill"; return 1; }
  grep -qF 'wave-usage-report.sh' "$_skill" \
    || { _fail "SKILL.md nao referencia wave-usage-report.sh" ""; return 1; }
  grep -qF 'Cruzamento com consumo de tokens observado' "$_skill" \
    || { _fail "subsecao de cruzamento ausente em SKILL.md §4.5" ""; return 1; }
  grep -qF 'model-routing-report.sh' "$_skill" \
    || { _fail "SKILL.md nao referencia model-routing-report.sh no cruzamento" ""; return 1; }
}

# Prova que os dois helpers compoem sem interferencia sobre a MESMA
# state.json: model-routing-report.sh continua lendo SOMENTE .decisions[]
# (nunca .waves) e wave-usage-report.sh continua lendo SOMENTE .waves[]
# (nunca .decisions) — o invariante que a subsecao de cruzamento do
# SKILL.md promete preservar (nenhum dos dois scripts foi alterado).
scenario_composicao_com_model_routing_report_preserva_invariantes() {
  _wur_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _mrr_script="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/model-routing-report.sh"
  [ -x "$_mrr_script" ] || { _error "model-routing-report.sh ausente/nao-executavel"; return 2; }

  cat > "$TMPDIR_TEST/state.json" <<'JSON'
{
  "schema_version": 1,
  "waves": [
    {
      "id": "onda-004",
      "agent_usage": {
        "spawns_total": 1, "spawns_with_usage": 1, "spawns_unavailable": 0,
        "total_tokens": 50000, "input_tokens": 100, "output_tokens": 900,
        "cache_read_input_tokens": 48900, "cache_creation_input_tokens": 100,
        "tool_use_count": 10, "duration_ms": 60000
      },
      "agent_spawns": [
        {"agent_id":"a1","agent_type":"t1","status":"completo","model":"opus","models_used":null,"total_tokens":50000,"input_tokens":100,"output_tokens":900,"cache_read_input_tokens":48900,"cache_creation_input_tokens":100,"tool_use_count":10,"duration_ms":60000,"source":"live","observed_at":"t"}
      ]
    }
  ],
  "decisions": [
    {
      "id": "dec-001",
      "wave_id": "onda-004",
      "timestamp": "2026-01-01T00:00:00Z",
      "stage": "plan",
      "agent": "agente-00c-feature-orchestrator",
      "context": "Selecao de modelo para onda onda-004 (fase plan)",
      "options_considered": ["sonnet", "opus"],
      "choice": "model:opus",
      "rationale": "sugerido=sonnet aplicado=opus origem=override-operador | operador pediu opus",
      "justification_score": 3
    }
  ]
}
JSON

  _before=$(_sha256_of "$TMPDIR_TEST/state.json")

  _wu_json=$(sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST" --json)
  _mr_json=$("$_mrr_script" aggregate --state-dir "$TMPDIR_TEST" --json)

  _after=$(_sha256_of "$TMPDIR_TEST/state.json")
  [ "$_before" = "$_after" ] || { _fail "read-only preservado" "sha256 do state.json mudou apos os dois aggregates"; return 1; }

  # wave-usage-report.sh: onda-004 presente com tokens reais.
  printf '%s' "$_wu_json" | jq -e '.por_onda[] | select(.onda == "onda-004") | .total_tokens == 50000' >/dev/null \
    || { _fail "wave-usage por_onda" "onda-004/total_tokens=50000 nao encontrado: $_wu_json"; return 1; }

  # model-routing-report.sh: onda-004 presente na secao por-onda, com
  # divergencia sugerido!=aplicado rotulada como override-operador.
  printf '%s' "$_mr_json" | jq -e '.linhas_onda[] | select(.onda == "onda-004") | .sugerido == "sonnet" and .aplicado == "opus" and .origem == "override-operador" and .divergente == true' >/dev/null \
    || { _fail "model-routing linhas_onda" "onda-004 nao bate com esperado: $_mr_json"; return 1; }

  # Join (mesma receita documentada em review-task/SKILL.md §4.5): a
  # onda diverge E tem token acima da media (unica onda com dado -> nao
  # ha "acima da media" com 1 ponto so; aqui validamos so que o join
  # produz a linha com os campos combinados, sem quebrar).
  _joined=$(jq -n --argjson mr "$_mr_json" --argjson wu "$_wu_json" '
    ($wu.por_onda // [] | map({(.onda): .}) | add // {}) as $wu_by_onda
    | ($mr.linhas_onda // []) as $rows
    | $rows | map(. as $r | ($wu_by_onda[$r.onda]) as $u | $r + {tokens: (($u.total_tokens) // null)})
  ')
  printf '%s' "$_joined" | jq -e '.[0].onda == "onda-004" and .[0].tokens == 50000 and .[0].divergente == true' >/dev/null \
    || { _fail "join model-routing x wave-usage" "resultado inesperado: $_joined"; return 1; }
}

# ==== backfill (US4/FR-010/FR-011, FASE 7) ====
#
# Fixture compartilhada: 2 ondas (onda-001 20:27:44Z-20:32:23Z, onda-002
# 20:39:08Z-20:49:16Z) + execution.id, espelhando o formato real de
# .waves[]/.execution do runtime (state-ondas.sh start/end).

_wur_write_backfill_state() {
  cat > "$TMPDIR_TEST/state.json" <<'JSON'
{
  "execution": {"id": "feat-wtm-test-exec"},
  "waves": [
    {"id":"onda-001","started_at":"2026-07-25T20:27:44Z","finished_at":"2026-07-25T20:32:23Z","agent_usage":null,"agent_spawns":[]},
    {"id":"onda-002","started_at":"2026-07-25T20:39:08Z","finished_at":"2026-07-25T20:49:16Z","agent_usage":null,"agent_spawns":[]}
  ],
  "accumulated_metrics": {"waves_total":2,"tool_calls_total":10,"wallclock_total_seconds":600,"agent_spawns_total":0,"agent_spawns_with_usage_total":0}
}
JSON
}

# Transcript valido: agent-001 (completo, onda-001), agent-002
# (indisponivel/async_launched, onda-002), agent-out (fora de toda janela).
_wur_write_transcript_valida() {
  cat > "$TMPDIR_TEST/transcript.jsonl" <<'EOF'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_A1","name":"Agent","input":{"description":"d","prompt":"p","subagent_type":"feature-00c-clarify-asker"}}]},"timestamp":"2026-07-25T20:28:00.100Z"}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_A1","content":"ok"}]},"toolUseResult":{"agentId":"agent-001","agentType":"feature-00c-clarify-asker","status":"completed","resolvedModel":"claude-sonnet-5","totalTokens":29678,"totalDurationMs":45000,"totalToolUseCount":3,"usage":{"input_tokens":100,"output_tokens":200,"cache_read_input_tokens":29000,"cache_creation_input_tokens":378}},"timestamp":"2026-07-25T20:29:00.500Z"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_A2","name":"Agent","input":{"description":"d","prompt":"p","subagent_type":"agente-00c-feature-orchestrator"}}]},"timestamp":"2026-07-25T20:40:00.000Z"}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_A2"}]},"toolUseResult":{"agentId":"agent-002","agentType":"agente-00c-feature-orchestrator","status":"async_launched"},"timestamp":"2026-07-25T20:41:00.000Z"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_OUT","name":"Agent","input":{"description":"fora","subagent_type":"x"}}]},"timestamp":"2026-07-25T19:00:00.000Z"}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_OUT"}]},"toolUseResult":{"agentId":"agent-out","status":"completed","totalTokens":1000},"timestamp":"2026-07-25T19:01:00.000Z"}
EOF
}

# Mesmo conteudo, com 1 linha corrompida inserida no meio.
_wur_write_transcript_corrompida() {
  _wur_write_transcript_valida
  _tmp_ins=$(mktemp)
  _line=0
  while IFS= read -r _l; do
    _line=$((_line + 1))
    printf '%s\n' "$_l" >> "$_tmp_ins"
    [ "$_line" -eq 2 ] && printf '%s\n' 'isto nao e json valido {{{' >> "$_tmp_ins"
  done < "$TMPDIR_TEST/transcript.jsonl"
  mv -- "$_tmp_ins" "$TMPDIR_TEST/transcript.jsonl"
}

# Transcript so com o spawn fora de qualquer janela (nao cobre a execucao).
_wur_write_transcript_sem_cobertura() {
  cat > "$TMPDIR_TEST/transcript.jsonl" <<'EOF'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_OUT","name":"Agent","input":{"description":"fora","subagent_type":"x"}}]},"timestamp":"2026-07-25T19:00:00.000Z"}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_OUT"}]},"toolUseResult":{"agentId":"agent-out","status":"completed","totalTokens":1000},"timestamp":"2026-07-25T19:01:00.000Z"}
EOF
}

scenario_backfill_sem_state_dir_exit_2() {
  capture sh "$SCRIPT" backfill --transcript /nao/importa
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit=2 (sem --state-dir)" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "--state-dir obrigatorio" || return 1
}

scenario_backfill_sem_transcript_exit_2() {
  mktemp_test || return 2
  capture sh "$SCRIPT" backfill --state-dir "$TMPDIR_TEST"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit=2 (sem --transcript)" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "--transcript obrigatorio" || return 1
}

scenario_backfill_state_json_ausente_exit_1() {
  mktemp_test || return 2
  capture sh "$SCRIPT" backfill --state-dir "$TMPDIR_TEST/nope" --transcript /nao/importa
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit=1 (sem state.json)" "obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_backfill_transcript_ausente_exit_3_nao_estima() {
  _wur_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _wur_write_backfill_state

  capture sh "$SCRIPT" backfill --state-dir "$TMPDIR_TEST" --transcript "$TMPDIR_TEST/nao-existe.jsonl"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "exit=3 (FR-011, transcript ausente)" "obtido $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains "ausente/ilegivel" || return 1
  assert_stderr_contains "feat-wtm-test-exec" || return 1

  # FR-011: nenhum campo de metrica escrito — state.json intacto.
  _tt=$(jq -r '.waves[0].agent_usage' "$TMPDIR_TEST/state.json")
  [ "$_tt" = "null" ] || { _fail "state.json inalterado" "waves[0].agent_usage nao e mais null: $_tt"; return 1; }
}

scenario_backfill_transcript_sem_cobertura_exit_3() {
  _wur_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _wur_write_backfill_state
  _wur_write_transcript_sem_cobertura

  capture sh "$SCRIPT" backfill --state-dir "$TMPDIR_TEST" --transcript "$TMPDIR_TEST/transcript.jsonl"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "exit=3 (transcript nao cobre nenhuma onda)" "obtido $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains "nao cobre nenhuma onda" || return 1
}

scenario_backfill_happy_path_atribui_por_janela_e_marca_source() {
  _wur_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _wur_write_backfill_state
  _wur_write_transcript_valida

  capture sh "$SCRIPT" backfill --state-dir "$TMPDIR_TEST" --transcript "$TMPDIR_TEST/transcript.jsonl"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit=0" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "2 spawn(s) novo(s)" || return 1

  # agent-001 -> onda-001, completo, source=backfill; agent-out (fora de
  # toda janela) NUNCA aparece em nenhuma onda.
  _src1=$(jq -r '.waves[0].agent_spawns[0].source' "$TMPDIR_TEST/state.json")
  [ "$_src1" = "backfill" ] || { _fail "onda-001 spawn source=backfill" "obtido $_src1"; return 1; }
  _aid1=$(jq -r '.waves[0].agent_spawns[0].agent_id' "$TMPDIR_TEST/state.json")
  [ "$_aid1" = "agent-001" ] || { _fail "onda-001 agent_id=agent-001" "obtido $_aid1"; return 1; }
  _tt1=$(jq -r '.waves[0].agent_usage.total_tokens' "$TMPDIR_TEST/state.json")
  [ "$_tt1" = "29678" ] || { _fail "onda-001 total_tokens=29678" "obtido $_tt1"; return 1; }

  _n_out=$(jq -r '[.waves[].agent_spawns[] | select(.agent_id == "agent-out")] | length' "$TMPDIR_TEST/state.json")
  [ "$_n_out" = "0" ] || { _fail "agent-out nunca atribuido a nenhuma onda" "obtido $_n_out ocorrencias"; return 1; }
}

scenario_backfill_status_indisponivel_campos_null_nao_zero() {
  _wur_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _wur_write_backfill_state
  _wur_write_transcript_valida

  sh "$SCRIPT" backfill --state-dir "$TMPDIR_TEST" --transcript "$TMPDIR_TEST/transcript.jsonl" >/dev/null

  # agent-002 (async_launched) -> onda-002, status=indisponivel, TODOS os
  # campos numericos null (nunca 0) — Principio VI/FR-009.
  _status2=$(jq -r '.waves[1].agent_spawns[0].status' "$TMPDIR_TEST/state.json")
  [ "$_status2" = "indisponivel" ] || { _fail "onda-002 status=indisponivel" "obtido $_status2"; return 1; }
  _tt2=$(jq -r '.waves[1].agent_spawns[0].total_tokens' "$TMPDIR_TEST/state.json")
  [ "$_tt2" = "null" ] || { _fail "onda-002 total_tokens=null (nao 0)" "obtido $_tt2"; return 1; }
  _wu2=$(jq -r '.waves[1].agent_usage.total_tokens' "$TMPDIR_TEST/state.json")
  [ "$_wu2" = "null" ] || { _fail "onda-002 agent_usage.total_tokens=null" "obtido $_wu2"; return 1; }
}

scenario_backfill_linha_corrompida_e_ignorada_sem_abortar() {
  _wur_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _wur_write_backfill_state
  _wur_write_transcript_corrompida

  capture sh "$SCRIPT" backfill --state-dir "$TMPDIR_TEST" --transcript "$TMPDIR_TEST/transcript.jsonl"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit=0 (linha corrompida nao aborta)" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "2 spawn(s) novo(s)" || return 1
}

scenario_backfill_idempotente_segunda_execucao_zero_novos() {
  _wur_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _wur_write_backfill_state
  _wur_write_transcript_valida

  sh "$SCRIPT" backfill --state-dir "$TMPDIR_TEST" --transcript "$TMPDIR_TEST/transcript.jsonl" >/dev/null
  _sha_apos_1a=$(_sha256_of "$TMPDIR_TEST/state.json")

  capture sh "$SCRIPT" backfill --state-dir "$TMPDIR_TEST" --transcript "$TMPDIR_TEST/transcript.jsonl"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit=0 (rerun idempotente)" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "0 spawns novos" || return 1
  assert_stdout_contains "idempotente" || return 1

  _sha_apos_2a=$(_sha256_of "$TMPDIR_TEST/state.json")
  [ "$_sha_apos_1a" = "$_sha_apos_2a" ] || { _fail "state.json byte-identico apos rerun" "sha256 mudou"; return 1; }
}

scenario_backfill_dry_run_nao_escreve_nada() {
  _wur_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _wur_write_backfill_state
  _wur_write_transcript_valida

  _sha_antes=$(_sha256_of "$TMPDIR_TEST/state.json")
  capture sh "$SCRIPT" backfill --state-dir "$TMPDIR_TEST" --transcript "$TMPDIR_TEST/transcript.jsonl" --dry-run
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit=0 (--dry-run)" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "onda-001" || return 1
  assert_stdout_contains "agent-001" || return 1
  assert_stdout_contains "Nenhuma escrita realizada" || return 1

  _sha_depois=$(_sha256_of "$TMPDIR_TEST/state.json")
  [ "$_sha_antes" = "$_sha_depois" ] || { _fail "state.json inalterado (--dry-run)" "sha256 mudou"; return 1; }
  [ -d "$TMPDIR_TEST/state-history" ] && { _fail "sem state-history/ apos --dry-run" "diretorio foi criado"; return 1; }
  return 0
}

scenario_backfill_apply_grava_backup_e_recomputa_sha256() {
  _wur_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _wur_write_backfill_state
  _wur_write_transcript_valida

  sh "$SCRIPT" backfill --state-dir "$TMPDIR_TEST" --transcript "$TMPDIR_TEST/transcript.jsonl" >/dev/null

  [ -d "$TMPDIR_TEST/state-history" ] || { _fail "state-history/ criado" "ausente"; return 1; }
  _n_backups=$(find "$TMPDIR_TEST/state-history" -type f -name '*.json' | wc -l | tr -d '[:space:]')
  [ "$_n_backups" -ge 1 ] || { _fail ">=1 backup em state-history/" "obtido $_n_backups"; return 1; }

  [ -f "$TMPDIR_TEST/state.json.sha256" ] || { _fail "state.json.sha256 criado" "ausente"; return 1; }
  _stored=$(head -n1 "$TMPDIR_TEST/state.json.sha256" | tr -d '[:space:]')
  _actual=$(_sha256_of "$TMPDIR_TEST/state.json")
  [ "$_stored" = "$_actual" ] || { _fail "sha256 recomputado bate com o conteudo" "stored=$_stored actual=$_actual"; return 1; }
}

scenario_backfill_accumulated_metrics_incrementado_pelo_delta() {
  _wur_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _wur_write_backfill_state
  _wur_write_transcript_valida

  sh "$SCRIPT" backfill --state-dir "$TMPDIR_TEST" --transcript "$TMPDIR_TEST/transcript.jsonl" >/dev/null

  _st=$(jq -r '.accumulated_metrics.agent_spawns_total' "$TMPDIR_TEST/state.json")
  [ "$_st" = "2" ] || { _fail "agent_spawns_total=2" "obtido $_st"; return 1; }
  _swu=$(jq -r '.accumulated_metrics.agent_spawns_with_usage_total' "$TMPDIR_TEST/state.json")
  [ "$_swu" = "1" ] || { _fail "agent_spawns_with_usage_total=1" "obtido $_swu"; return 1; }
  _tt=$(jq -r '.accumulated_metrics.agent_tokens_total' "$TMPDIR_TEST/state.json")
  [ "$_tt" = "29678" ] || { _fail "agent_tokens_total=29678" "obtido $_tt"; return 1; }
  # tool_calls_total/wallclock_total_seconds (campos EXISTENTES) intactos.
  _tct=$(jq -r '.accumulated_metrics.tool_calls_total' "$TMPDIR_TEST/state.json")
  [ "$_tct" = "10" ] || { _fail "tool_calls_total preservado=10" "obtido $_tct"; return 1; }
}

scenario_backfill_argumento_desconhecido_exit_2() {
  mktemp_test || return 2
  capture sh "$SCRIPT" backfill --state-dir "$TMPDIR_TEST" --transcript /x --bogus-flag
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit=2 (flag desconhecida)" "obtido $_CAPTURED_EXIT"; return 1; }
}

# ==== IR-3: Principio II POSIX ====

scenario_shebang_posix_e_set_eu() {
  _head1=$(head -n1 "$SCRIPT")
  [ "$_head1" = "#!/bin/sh" ] || { _fail "shebang #!/bin/sh" "obtido: $_head1"; return 1; }
  grep -q '^set -eu$' "$SCRIPT" || { _fail "set -eu presente" "nao encontrado"; return 1; }
}

# ==== Regressoes de campo: enclausuramento + toolUseResult string ====

# Topologia REAL do agente-00c: o command pai spawna o orquestrador, e e o
# orquestrador que abre e fecha a onda POR DENTRO do spawn. Logo
#   spawn_start < wave.started_at < wave.finished_at < spawn_end
# O tool_result chega DEPOIS de finished_at, na lacuna entre ondas — a regra
# antiga (contencao: started_at <= ts < finished_at) nunca casava.
# Medido em gamedev-training antes do fix: 58 spawns, 56 janelas, 0 cobertos.
_wur_write_state_enclausurado() {
  mkdir -p "$1"
  cat > "$1/state.json" <<'JSON'
{
  "execution": {"id":"exec-encl","status":"concluida"},
  "waves": [
    {"id":"onda-001","started_at":"2026-07-25T20:05:00Z","finished_at":"2026-07-25T20:10:00Z","agent_usage":null,"agent_spawns":[]}
  ],
  "accumulated_metrics": {"waves_total":1,"agent_spawns_total":0,"agent_spawns_with_usage_total":0}
}
JSON
}

# Spawn que ENVOLVE a onda: comeca antes de started_at, termina depois de
# finished_at. Sob a regra antiga isso ficava sem atribuicao.
_wur_write_transcript_enclausurado() {
  cat > "$TMPDIR_TEST/tr-encl.jsonl" <<'EOF'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_E1","name":"Agent","input":{"subagent_type":"agente-00c-orchestrator"}}]},"timestamp":"2026-07-25T20:04:00.000Z"}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_E1"}]},"toolUseResult":{"agentId":"agent-encl","status":"completed","totalTokens":5000,"totalDurationMs":300000,"totalToolUseCount":9,"usage":{"input_tokens":10,"output_tokens":20,"cache_read_input_tokens":4900,"cache_creation_input_tokens":70}},"timestamp":"2026-07-25T20:11:00.000Z"}
EOF
}

scenario_backfill_atribui_spawn_que_envolve_a_onda() {
  _wur_write_state_enclausurado "$TMPDIR_TEST/encl"
  _wur_write_transcript_enclausurado
  capture sh "$SCRIPT" backfill --state-dir "$TMPDIR_TEST/encl"     --transcript "$TMPDIR_TEST/tr-encl.jsonl" --dry-run
  # Sob a regra antiga isto era exit 3 ("nao cobre nenhuma onda").
  [ "$_CAPTURED_EXIT" = 0 ]     || { _fail "enclausuramento" "esperado exit 0, obtido $_CAPTURED_EXIT — spawn que envolve a onda nao foi atribuido"; return 1; }
  printf '%s' "$_CAPTURED_STDOUT" | grep -q "onda-001"     || { _fail "atribuicao" "esperado onda-001 no plano; obtido: $_CAPTURED_STDOUT"; return 1; }
  printf '%s' "$_CAPTURED_STDOUT" | grep -q "agent-encl"     || { _fail "agent_id" "esperado agent-encl no plano"; return 1; }
  return 0
}

# A regra antiga (contencao) tem de continuar valendo para spawns feitos de
# DENTRO de uma onda ja aberta — o fix e aditivo, nao substitutivo.
scenario_backfill_contencao_continua_valendo() {
  _wur_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _wur_write_backfill_state
  _wur_write_transcript_valida
  capture sh "$SCRIPT" backfill --state-dir "$TMPDIR_TEST" --transcript "$TMPDIR_TEST/transcript.jsonl" --dry-run
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "contencao" "exit $_CAPTURED_EXIT"; return 1; }
  printf '%s' "$_CAPTURED_STDOUT" | grep -q "agent-001"     || { _fail "contencao" "spawn contido na onda deixou de ser atribuido"; return 1; }
  return 0
}

# `toolUseResult` nem sempre e objeto: varios tools devolvem string crua.
# `.agentId` sobre string aborta o jq com "Cannot index string with string",
# derrubando o backfill do arquivo TODO (observado em financial-support).
scenario_backfill_tooluseresult_string_nao_derruba() {
  _wur_write_state_enclausurado "$TMPDIR_TEST/strres"
  {
    # linha venenosa: toolUseResult e STRING, nao objeto
    printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_S1","name":"Agent","input":{"subagent_type":"x"}}]},"timestamp":"2026-07-25T20:04:00.000Z"}'
    printf '%s\n' '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_S1"}]},"toolUseResult":"resultado em texto puro","timestamp":"2026-07-25T20:06:00.000Z"}'
    # spawn valido depois dela: se o jq abortasse, este tambem se perderia
    printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_E1","name":"Agent","input":{"subagent_type":"agente-00c-orchestrator"}}]},"timestamp":"2026-07-25T20:04:00.000Z"}'
    printf '%s\n' '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_E1"}]},"toolUseResult":{"agentId":"agent-ok","status":"completed","totalTokens":100,"usage":{"input_tokens":1,"output_tokens":2,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}},"timestamp":"2026-07-25T20:11:00.000Z"}'
  } > "$TMPDIR_TEST/tr-string.jsonl"
  capture sh "$SCRIPT" backfill --state-dir "$TMPDIR_TEST/strres"     --transcript "$TMPDIR_TEST/tr-string.jsonl" --dry-run
  [ "$_CAPTURED_EXIT" = 0 ]     || { _fail "string result" "esperado exit 0, obtido $_CAPTURED_EXIT — toolUseResult string derrubou o backfill"; return 1; }
  printf '%s' "$_CAPTURED_STDERR" | grep -qi "jq falhou"     && { _fail "crash" "jq abortou por causa de toolUseResult string"; return 1; }
  # o spawn valido tem de sobreviver a linha venenosa
  printf '%s' "$_CAPTURED_STDOUT" | grep -q "agent-ok"     || { _fail "sobrevivencia" "spawn valido perdido junto com a linha string"; return 1; }
  return 0
}

# ==== Backend SQLite (state-db-runtime-parity FASE 2.3 / FR-001 / FR-011) ====
# Leitura via _state-read.sh: aggregate/backfill materializam o documento a
# partir de state.db; a escrita do backfill ja delega a state-rw.sh write
# (db-aware). Fixture: init sob config global state_backend=sqlite (HOME
# sandbox) + injecao de .waves via read|jq|write (caminho canonico).

RW="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-rw.sh"

_sqlite3_adequate() {
  command -v sqlite3 >/dev/null 2>&1 || return 1
  _v=$(sqlite3 --version 2>/dev/null | cut -d' ' -f1) || return 1
  [ -n "$_v" ]
}

_wur_init_sqlite() {
  _wis_home="$TMPDIR_TEST/home-sqlite"
  mkdir -p "$_wis_home/.claude/cstk"
  printf 'state_backend=sqlite\n' > "$_wis_home/.claude/cstk/config"
  env HOME="$_wis_home" "$RW" init --state-dir "$1" \
    --execucao-id "x-wur-sqlite" --projeto-alvo-path "/tmp/p" \
    --descricao "POC wave-usage-report sqlite" >/dev/null 2>&1 || return 1
  [ -f "$1/state.db" ] || return 1
}

# Substitui .waves do documento persistido em state.db pelo array JSON $2,
# via caminho canonico read|jq|write (write e db-aware).
_wur_sqlite_set_waves() {
  "$RW" read --state-dir "$1" \
    | jq --argjson w "$2" '.waves = $w' \
    | "$RW" write --state-dir "$1" >/dev/null 2>&1
}

scenario_sqlite_aggregate_json_le_state_db() {
  _wur_have_jq || { _error "jq ausente"; return 2; }
  _sqlite3_adequate || { printf "# skip: sqlite3 indisponivel\n"; return 0; }
  mktemp_test || return 2
  _sd="$TMPDIR_TEST/state-sqlite"
  _wur_init_sqlite "$_sd" || { _fail "fixture sqlite" "init nao gerou state.db"; return 1; }
  # Reusa a fixture canonica do contrato: extrai .waves do state.json gerado
  # pelo helper e injeta no documento sqlite. Enriquecidas com campos de
  # fechamento: o schema sqlite exige started_at NOT NULL e permite no
  # maximo 1 onda aberta por execucao (ux_wave_single_open) — ondas da
  # fixture precisam estar FECHADAS para o import aceitar as 3.
  _wur_write_fixture_contrato
  _waves=$(jq -c '[.waves[] | . + {started_at:"2026-07-25T20:00:00Z", finished_at:"2026-07-25T20:05:00Z", termination_reason:"etapa_concluida_avancando"}]' "$TMPDIR_TEST/state.json")
  _wur_sqlite_set_waves "$_sd" "$_waves" || { _fail "fixture sqlite" "write das waves falhou"; return 1; }

  capture sh "$SCRIPT" aggregate --state-dir "$_sd" --json
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "aggregate sqlite" "exit $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  case "$_CAPTURED_STDERR" in
    *"state.json nao encontrado"*) _fail "aggregate sqlite" "degradou com 'state.json nao encontrado'"; return 1 ;;
  esac
  # Veredito equivalente ao backend JSON (SC-003): mesmos agregados.
  printf '%s' "$_CAPTURED_STDOUT" | jq -e '.spawns_total == 5 and .waves_total == 2 and .metric_collected == true' >/dev/null \
    || { _fail "aggregate sqlite" "agregado divergente do backend JSON: $_CAPTURED_STDOUT"; return 1; }
  # Anti-mirror (FR-003): leitura nao materializa state.json no state-dir.
  if [ -f "$_sd/state.json" ]; then
    _fail "anti-mirror" "aggregate criou state.json dentro do state-dir sqlite"
    return 1
  fi
}

scenario_sqlite_backfill_apply_persiste_no_state_db() {
  _wur_have_jq || { _error "jq ausente"; return 2; }
  _sqlite3_adequate || { printf "# skip: sqlite3 indisponivel\n"; return 0; }
  mktemp_test || return 2
  _sd="$TMPDIR_TEST/state-sqlite"
  _wur_init_sqlite "$_sd" || { _fail "fixture sqlite" "init nao gerou state.db"; return 1; }
  # Janelas identicas a fixture do backfill JSON (transcript valida cobre
  # onda-001 por contencao). Ondas FECHADAS (termination_reason preenchido):
  # o schema sqlite exige coerencia finished_at<->termination_reason e no
  # maximo 1 onda aberta (ux_wave_single_open).
  _wur_sqlite_set_waves "$_sd" '[
    {"id":"onda-001","started_at":"2026-07-25T20:27:44Z","finished_at":"2026-07-25T20:32:23Z","termination_reason":"etapa_concluida_avancando","agent_usage":null,"agent_spawns":[]},
    {"id":"onda-002","started_at":"2026-07-25T20:39:08Z","finished_at":"2026-07-25T20:49:16Z","termination_reason":"etapa_concluida_avancando","agent_usage":null,"agent_spawns":[]}
  ]' || { _fail "fixture sqlite" "write das waves falhou"; return 1; }
  _wur_write_transcript_valida

  capture sh "$SCRIPT" backfill --state-dir "$_sd" --transcript "$TMPDIR_TEST/transcript.jsonl"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "backfill sqlite" "exit $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  # Persistencia no state.db via state-rw.sh write (db-aware): read devolve
  # o spawn aplicado com source=backfill e agent_usage recomputado.
  _doc=$("$RW" read --state-dir "$_sd") || { _fail "read pos-backfill" "state-rw.sh read falhou"; return 1; }
  printf '%s' "$_doc" | jq -e '.waves[0].agent_spawns[0].agent_id == "agent-001" and .waves[0].agent_spawns[0].source == "backfill" and .waves[0].agent_usage.spawns_total == 1' >/dev/null \
    || { _fail "backfill sqlite" "spawn nao persistido no state.db: $(printf '%s' "$_doc" | jq -c '.waves[0]')"; return 1; }
  # Idempotencia sob sqlite: 2a execucao -> 0 novos, sem write.
  capture sh "$SCRIPT" backfill --state-dir "$_sd" --transcript "$TMPDIR_TEST/transcript.jsonl"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "backfill sqlite 2a" "exit $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "0 spawns novos" || return 1
  # Anti-mirror (FR-003).
  if [ -f "$_sd/state.json" ]; then
    _fail "anti-mirror" "backfill criou state.json dentro do state-dir sqlite"
    return 1
  fi
}

run_all_scenarios "$0"
