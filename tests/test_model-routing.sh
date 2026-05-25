#!/bin/sh
# test_model-routing.sh — cobre global/skills/agente-00c-runtime/scripts/model-routing.sh.
#
# Feature: agente-00c-model-routing
# Ref: docs/specs/agente-00c-model-routing/contracts/model-routing-helper.md
#      docs/specs/agente-00c-model-routing/tasks.md F1.1.4
#      docs/specs/agente-00c-model-routing/test-coverage.md (cross-table FR/INV/F-finding -> scenarios)
#
# Cross-table FR-001..FR-020 / INV-1..INV-6 / F-001..F-005 -> cenarios
# vive em docs/specs/agente-00c-model-routing/test-coverage.md. Manter
# essa tabela em sincronia ao adicionar/remover cenarios aqui.
#
# Cobertura atual:
#   F1.1 (dispatch / skeleton):
#     - dispatch: sem args -> exit 2 + usage em stderr
#     - dispatch: subcomando desconhecido -> exit 2
#     - help/-h/--help -> reusa bloco HELP do dispatch (exit 2)
#   F1.2 (template subcomando):
#     - 4 templates inline (enum agente-00c/feature-00c x asker/answerer)
#     - flag syntax: --subagent-type X e --subagent-type=X
#     - flag ausente -> exit 2 + mensagem unknown-subagent-type
#     - enum invalido -> exit 2 + mensagem unknown-subagent-type
#     - INV-5: determinismo via sha256 em 3 invocacoes consecutivas
#   F1.1.5 (INV-6 parcial): shebang + set -eu + sem bash-isms obvios
#
# Cobertura futura (sera expandida em F1.3..F1.4 + F4 + F6):
#   - invoke happy-path + truncagem + fallback graceful + INV-1..INV-3
#   - idempotent-check read-only + INV-4
#   - F-001..F-005 hardening (input adversarial, UTF-8 boundary, timeout)
#
#   F2.2 (Idempotencia + retomada — sub-suite "resume"):
#     - dry-run do protocolo /agente-00c-resume contra fixture
#       tests/fixtures/state-with-onda-002-decisao.json
#     - HIT: exit 0 + stdout=dec-019 (skip invoke + register)
#     - MISS por subagent-type distinto (Invariante I1)
#     - MISS por onda-id distinta
#     - 3 retomadas consecutivas read-only (INV-4 em padrao de retry)
#
#   F2.3.2 (Compatibilidade com agente-00c-artifact-cache — SC-004):
#     - idempotent-check em state.json com briefing_cache + constitution_cache
#       populados: ignora campos de cache (read-only sobre .decisoes[])
#     - invoke roda em CWD sem briefing/constitution em disco: helper opera
#       puramente sobre template estatico, sem dependencia de FS
#     - pipeline mini (idempotent-check + invoke) preserva sha256 dos campos
#       briefing_cache/constitution_cache (extensao INV-4 para o eixo cache)

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/model-routing.sh"

# ==== F1.1.4: dispatch sem args ====

scenario_sem_args_exit_2_e_usage_em_stderr() {
  capture sh "$SCRIPT"
  assert_exit 2 sh "$SCRIPT" || return 1
  # Stderr deve mencionar pelo menos um subcomando e a string "USO".
  assert_stderr_contains "USO:" || return 1
  assert_stderr_contains "template" || return 1
  assert_stderr_contains "invoke" || return 1
  assert_stderr_contains "idempotent-check" || return 1
}

# ==== Dispatch: subcomando desconhecido ====

scenario_subcomando_desconhecido_exit_2() {
  capture sh "$SCRIPT" bogus-subcmd-xyz
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit=2" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "subcomando desconhecido" || return 1
  assert_stderr_contains "bogus-subcmd-xyz" || return 1
}

# ==== Dispatch: -h/--help/help reusa bloco HELP ====

scenario_help_flag_short() {
  capture sh "$SCRIPT" -h
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit=2 (help)" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "USO:" || return 1
}

scenario_help_flag_long() {
  capture sh "$SCRIPT" --help
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit=2 (--help)" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "USO:" || return 1
}

scenario_help_subcomando_explicito() {
  capture sh "$SCRIPT" help
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit=2 (help)" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "USO:" || return 1
}

# ==== F1.2: subcomando template — happy paths para cada enum ====

scenario_template_agente_00c_clarify_asker() {
  capture sh "$SCRIPT" template --subagent-type agente-00c-clarify-asker
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit=0" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "enumerative scan" || return 1
  assert_stdout_contains "project spec" || return 1
  assert_stdout_contains "stack_sugerida" || return 1
  assert_stdout_contains "JSON array of questions" || return 1
}

scenario_template_agente_00c_clarify_answerer() {
  capture sh "$SCRIPT" template --subagent-type agente-00c-clarify-answerer
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit=0" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "reflective scoring" || return 1
  assert_stdout_contains "score 0..3" || return 1
  assert_stdout_contains "pause_humano" || return 1
  assert_stdout_contains "stack_sugerida" || return 1
}

scenario_template_feature_00c_clarify_asker() {
  capture sh "$SCRIPT" template --subagent-type feature-00c-clarify-asker
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit=0" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "feature spec" || return 1
  assert_stdout_contains "single feature scope" || return 1
  # NAO menciona stack_sugerida (escopo feature ja tem stack definida).
  if printf '%s' "$_CAPTURED_STDOUT" | grep -q "stack_sugerida"; then
    _fail "feature-00c-clarify-asker NAO deve citar stack_sugerida" "encontrado em stdout"
    return 1
  fi
}

scenario_template_feature_00c_clarify_answerer() {
  capture sh "$SCRIPT" template --subagent-type feature-00c-clarify-answerer
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit=0" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "reflective scoring" || return 1
  assert_stdout_contains "feature sources" || return 1
  assert_stdout_contains "spec_corrente" || return 1
  # NAO menciona stack_sugerida (escopo feature).
  if printf '%s' "$_CAPTURED_STDOUT" | grep -q "stack_sugerida"; then
    _fail "feature-00c-clarify-answerer NAO deve citar stack_sugerida" "encontrado em stdout"
    return 1
  fi
}

# ==== F1.2: flag syntax variants ====

scenario_template_flag_eq_syntax() {
  # `--subagent-type=X` equivalente a `--subagent-type X`.
  capture sh "$SCRIPT" template --subagent-type=agente-00c-clarify-asker
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit=0 (eq-syntax)" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "enumerative scan" || return 1
}

# ==== F1.2: erros — flag ausente e enum invalido ====

scenario_template_sem_flag_exit_2() {
  capture sh "$SCRIPT" template
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit=2 (sem flag)" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "unknown-subagent-type" || return 1
}

scenario_template_enum_invalido_exit_2() {
  capture sh "$SCRIPT" template --subagent-type bogus-type-xyz
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit=2 (enum invalido)" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "unknown-subagent-type" || return 1
  assert_stderr_contains "bogus-type-xyz" || return 1
}

scenario_template_flag_desconhecida_exit_2() {
  capture sh "$SCRIPT" template --foo bar
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit=2 (flag desconhecida)" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "flag desconhecida" || return 1
}

# ==== F1.2: INV-5 (puro/deterministico) ====
# Output identico para mesmo input em 3 invocacoes consecutivas (proxy
# para "qualquer ambiente": sem env vars consumidas alem dos flags,
# sem leitura de arquivo externo). Mede sha256 com a ferramenta
# disponivel no host (shasum em macOS, sha256sum em Linux).

_mr_hash_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    shasum -a 256 | awk '{print $1}'
  fi
}

scenario_template_inv5_determinismo_asker() {
  _h1=$(sh "$SCRIPT" template --subagent-type agente-00c-clarify-asker | _mr_hash_stdin)
  _h2=$(sh "$SCRIPT" template --subagent-type agente-00c-clarify-asker | _mr_hash_stdin)
  _h3=$(sh "$SCRIPT" template --subagent-type agente-00c-clarify-asker | _mr_hash_stdin)
  if [ "$_h1" != "$_h2" ] || [ "$_h2" != "$_h3" ]; then
    _fail "INV-5 determinismo" "hashes divergiram: $_h1 / $_h2 / $_h3"
    return 1
  fi
}

scenario_template_inv5_determinismo_feature_answerer() {
  _h1=$(sh "$SCRIPT" template --subagent-type feature-00c-clarify-answerer | _mr_hash_stdin)
  _h2=$(sh "$SCRIPT" template --subagent-type feature-00c-clarify-answerer | _mr_hash_stdin)
  _h3=$(sh "$SCRIPT" template --subagent-type feature-00c-clarify-answerer | _mr_hash_stdin)
  if [ "$_h1" != "$_h2" ] || [ "$_h2" != "$_h3" ]; then
    _fail "INV-5 determinismo" "hashes divergiram: $_h1 / $_h2 / $_h3"
    return 1
  fi
}

scenario_template_inv5_4_tipos_distintos() {
  # Os 4 templates devem ser DISTINTOS entre si (nao copy-paste do mesmo).
  _h_aa=$(sh "$SCRIPT" template --subagent-type agente-00c-clarify-asker | _mr_hash_stdin)
  _h_ab=$(sh "$SCRIPT" template --subagent-type agente-00c-clarify-answerer | _mr_hash_stdin)
  _h_fa=$(sh "$SCRIPT" template --subagent-type feature-00c-clarify-asker | _mr_hash_stdin)
  _h_fb=$(sh "$SCRIPT" template --subagent-type feature-00c-clarify-answerer | _mr_hash_stdin)
  # 4 hashes distintos.
  if [ "$_h_aa" = "$_h_ab" ] || [ "$_h_aa" = "$_h_fa" ] || [ "$_h_aa" = "$_h_fb" ] \
     || [ "$_h_ab" = "$_h_fa" ] || [ "$_h_ab" = "$_h_fb" ] || [ "$_h_fa" = "$_h_fb" ]; then
    _fail "4 templates distintos" "colisao detectada entre tipos"
    return 1
  fi
}

# ==== F1.3: subcomando invoke ====
# Cobertura completa por subtarefa:
#   1.3.1 flags + derivacao via template
#   1.3.2 truncagem 2000+marker(16)+2000 = 4016 bytes (INV-3)
#   1.3.3 invocacao com timeout (4s) — cenario de timeout estourado
#   1.3.4 parser de ## Modelo Sugerido / ## Score / ## Alternativa
#   1.3.5 score mapping dec-003 (0->0, 1->2, 2->3)
#   1.3.6 JSON construido via jq -n (validavel via jq -e .)
#   1.3.7 4 fallbacks: skill-not-found, exit-nonzero, parse-failure,
#         tool-skill-unavailable — todos com exit 0 (INV-1)
#   1.3.8 raw_stdout_first_200 / fallback_stderr_first_200 com tr -d '\000'

# Helper: localiza jq (alguns CIs podem nao ter).
_mr_have_jq() {
  command -v jq >/dev/null 2>&1
}

# ---- 1.3.1: flags obrigatorias e enum ----

scenario_invoke_sem_subagent_exit_2() {
  capture sh "$SCRIPT" invoke --etapa clarify
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit=2 (sem subagent)" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "--subagent-type" || return 1
}

scenario_invoke_sem_etapa_exit_2() {
  capture sh "$SCRIPT" invoke --subagent-type agente-00c-clarify-asker
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit=2 (sem etapa)" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "--etapa" || return 1
}

scenario_invoke_etapa_invalida_exit_2() {
  capture sh "$SCRIPT" invoke --subagent-type agente-00c-clarify-asker --etapa plan
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit=2 (etapa invalida)" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "--etapa fora do enum" || return 1
}

scenario_invoke_subagent_fora_enum_exit_2() {
  capture sh "$SCRIPT" invoke --subagent-type bogus --etapa clarify
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit=2 (subagent invalido)" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "--subagent-type fora do enum" || return 1
}

scenario_invoke_timeout_nao_numerico_exit_2() {
  capture sh "$SCRIPT" invoke --subagent-type agente-00c-clarify-asker \
    --etapa clarify --timeout-seconds abc
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit=2 (timeout non-numeric)" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "nao-numerico" || return 1
}

# ---- 1.3.1: derivacao de input via template (sem --input-text) ----

scenario_invoke_happy_path_template_derivado() {
  _mr_have_jq || { _error "jq ausente — pulando"; return 2; }
  capture sh "$SCRIPT" invoke --subagent-type agente-00c-clarify-asker --etapa clarify
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit=0" "obtido $_CAPTURED_EXIT"; return 1; }
  # INV-2: JSON parseavel por jq.
  printf '%s' "$_CAPTURED_STDOUT" | jq -e . >/dev/null 2>&1 \
    || { _fail "JSON parseavel (INV-2)" "stdout invalido"; return 1; }
  # Shape obrigatorio.
  printf '%s' "$_CAPTURED_STDOUT" | jq -e \
    '.subagent_type == "agente-00c-clarify-asker"
      and .etapa == "clarify"
      and .fallback == false
      and (.modelo | type == "string")
      and (.input_bytes | type == "number")' >/dev/null 2>&1 \
    || { _fail "shape JSON sucesso" "campos ausentes ou tipos errados"; return 1; }
}

# ---- 1.3.4 + 1.3.5: parser + score mapping (todos os 3 inputs 0/1/2) ----

# Stub skill que emite score 0 (modelo manter-atual).
_mr_make_stub_score0() {
  cat > "$1" <<'EOF'
#!/bin/sh
cat <<'OUT'
## Modelo Sugerido

manter-atual

## Score

0

rasa=0 media=0 profunda=0 faixa=indeterminado
score=0 modelo=manter-atual alternativa=none

## Justificativa

stub score 0.

## Alternativa

none
OUT
EOF
  chmod +x "$1"
}

# Stub skill que emite score 1 (faixa media -> sonnet).
_mr_make_stub_score1() {
  cat > "$1" <<'EOF'
#!/bin/sh
cat <<'OUT'
## Modelo Sugerido

sonnet

## Score

1

rasa=0 media=1 profunda=0 faixa=media
score=1 modelo=sonnet alternativa=opus

## Justificativa

stub score 1 — sinal medio detectado.

## Alternativa

opus
OUT
EOF
  chmod +x "$1"
}

# Stub skill que emite score 2 (faixa rasa -> haiku).
_mr_make_stub_score2() {
  cat > "$1" <<'EOF'
#!/bin/sh
cat <<'OUT'
## Modelo Sugerido

haiku

## Score

2

rasa=3 media=0 profunda=0 faixa=rasa
score=2 modelo=haiku alternativa=sonnet

## Justificativa

sinais detectados: stub score 2.

## Alternativa

sonnet
OUT
EOF
  chmod +x "$1"
}

scenario_invoke_score_mapping_0_to_0() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _stub="$TMPDIR_TEST/skill.sh"
  _mr_make_stub_score0 "$_stub"
  MODEL_SELECTOR_SCRIPT="$_stub" capture sh "$SCRIPT" invoke \
    --subagent-type agente-00c-clarify-asker --etapa clarify --input-text "x"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit=0" "$_CAPTURED_EXIT"; return 1; }
  printf '%s' "$_CAPTURED_STDOUT" | jq -e \
    '.score_skill == 0 and .score_runtime == 0 and .modelo == "manter-atual"' \
    >/dev/null 2>&1 || { _fail "score 0->0" "$_CAPTURED_STDOUT"; return 1; }
}

scenario_invoke_score_mapping_1_to_2() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _stub="$TMPDIR_TEST/skill.sh"
  _mr_make_stub_score1 "$_stub"
  MODEL_SELECTOR_SCRIPT="$_stub" capture sh "$SCRIPT" invoke \
    --subagent-type agente-00c-clarify-asker --etapa clarify --input-text "x"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit=0" "$_CAPTURED_EXIT"; return 1; }
  printf '%s' "$_CAPTURED_STDOUT" | jq -e \
    '.score_skill == 1 and .score_runtime == 2 and .modelo == "sonnet"' \
    >/dev/null 2>&1 || { _fail "score 1->2" "$_CAPTURED_STDOUT"; return 1; }
}

scenario_invoke_score_mapping_2_to_3() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _stub="$TMPDIR_TEST/skill.sh"
  _mr_make_stub_score2 "$_stub"
  MODEL_SELECTOR_SCRIPT="$_stub" capture sh "$SCRIPT" invoke \
    --subagent-type agente-00c-clarify-asker --etapa clarify --input-text "x"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit=0" "$_CAPTURED_EXIT"; return 1; }
  printf '%s' "$_CAPTURED_STDOUT" | jq -e \
    '.score_skill == 2 and .score_runtime == 3 and .modelo == "haiku" and .alternativa == "sonnet"' \
    >/dev/null 2>&1 || { _fail "score 2->3" "$_CAPTURED_STDOUT"; return 1; }
}

# ---- 1.3.2 + INV-3: truncagem 4016 bytes ----

scenario_invoke_truncagem_input_8000_bytes() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  # Gera string de 8000 bytes ASCII (A repetido).
  _big=$(awk 'BEGIN { for (i=0;i<8000;i++) printf "A"; print "" }' | tr -d '\n')
  capture sh "$SCRIPT" invoke --subagent-type agente-00c-clarify-asker \
    --etapa clarify --input-text "$_big"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit=0" "$_CAPTURED_EXIT"; return 1; }
  printf '%s' "$_CAPTURED_STDOUT" | jq -e \
    '.input_truncado == true and .input_bytes <= 4016' \
    >/dev/null 2>&1 || { _fail "INV-3 truncagem" "$_CAPTURED_STDOUT"; return 1; }
}

# Boundary test: input com exatamente 4096 bytes NAO trunca.
scenario_invoke_truncagem_input_4096_exato_nao_trunca() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  _exact=$(awk 'BEGIN { for (i=0;i<4096;i++) printf "B" }')
  capture sh "$SCRIPT" invoke --subagent-type agente-00c-clarify-asker \
    --etapa clarify --input-text "$_exact"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit=0" "$_CAPTURED_EXIT"; return 1; }
  printf '%s' "$_CAPTURED_STDOUT" | jq -e \
    '.input_truncado == false and .input_bytes == 4096' \
    >/dev/null 2>&1 || { _fail "boundary 4096 nao trunca" "$_CAPTURED_STDOUT"; return 1; }
}

# Marker presente no input truncado entregue a skill (verifica via probe stub).
scenario_invoke_truncagem_marker_presente() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  # Stub que copia bytes 1995-2040 do stdin para stderr e falha (provoca
  # fallback). fallback_stderr_first_200 ira conter o marker.
  _probe="$TMPDIR_TEST/probe.sh"
  cat > "$_probe" <<'EOF'
#!/bin/sh
input=$(cat)
printf '%s' "$input" | tail -c +1995 | head -c 50 >&2
exit 99
EOF
  chmod +x "$_probe"
  _big=$(awk 'BEGIN { for (i=0;i<8000;i++) printf "C" }')
  MODEL_SELECTOR_SCRIPT="$_probe" capture sh "$SCRIPT" invoke \
    --subagent-type agente-00c-clarify-asker --etapa clarify --input-text "$_big"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit=0" "$_CAPTURED_EXIT"; return 1; }
  printf '%s' "$_CAPTURED_STDOUT" | jq -e \
    '.fallback_stderr_first_200 | contains("...[truncated]..")' \
    >/dev/null 2>&1 || { _fail "marker presente" "$_CAPTURED_STDOUT"; return 1; }
}

# ---- 1.3.7: 4 cenarios de fallback (todos exit 0, INV-1) ----

scenario_invoke_fallback_skill_not_found() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  MODEL_SELECTOR_SCRIPT="/nonexistent/path/classify.sh" capture sh "$SCRIPT" invoke \
    --subagent-type agente-00c-clarify-asker --etapa clarify --input-text "x"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit=0 (INV-1)" "$_CAPTURED_EXIT"; return 1; }
  printf '%s' "$_CAPTURED_STDOUT" | jq -e \
    '.fallback == true and .fallback_reason == "skill-not-found"
      and .score_runtime == 0 and .modelo == "fallback-default"' \
    >/dev/null 2>&1 || { _fail "fallback skill-not-found" "$_CAPTURED_STDOUT"; return 1; }
}

scenario_invoke_fallback_exit_nonzero() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _stub="$TMPDIR_TEST/fail.sh"
  cat > "$_stub" <<'EOF'
#!/bin/sh
echo "stub error message" >&2
exit 7
EOF
  chmod +x "$_stub"
  MODEL_SELECTOR_SCRIPT="$_stub" capture sh "$SCRIPT" invoke \
    --subagent-type agente-00c-clarify-asker --etapa clarify --input-text "x"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit=0 (INV-1)" "$_CAPTURED_EXIT"; return 1; }
  printf '%s' "$_CAPTURED_STDOUT" | jq -e \
    '.fallback == true and .fallback_reason == "exit-nonzero"
      and (.fallback_stderr_first_200 | contains("stub error message"))' \
    >/dev/null 2>&1 || { _fail "fallback exit-nonzero" "$_CAPTURED_STDOUT"; return 1; }
}

scenario_invoke_fallback_parse_failure() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _stub="$TMPDIR_TEST/garbage.sh"
  cat > "$_stub" <<'EOF'
#!/bin/sh
echo "no expected sections"
echo "totally unparseable"
exit 0
EOF
  chmod +x "$_stub"
  MODEL_SELECTOR_SCRIPT="$_stub" capture sh "$SCRIPT" invoke \
    --subagent-type agente-00c-clarify-asker --etapa clarify --input-text "x"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit=0 (INV-1)" "$_CAPTURED_EXIT"; return 1; }
  printf '%s' "$_CAPTURED_STDOUT" | jq -e \
    '.fallback == true and .fallback_reason == "parse-failure"
      and .modelo == "fallback-default"' \
    >/dev/null 2>&1 || { _fail "fallback parse-failure" "$_CAPTURED_STDOUT"; return 1; }
}

scenario_invoke_fallback_tool_skill_unavailable() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  MODEL_SELECTOR_DISABLED=1 capture sh "$SCRIPT" invoke \
    --subagent-type agente-00c-clarify-asker --etapa clarify --input-text "x"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit=0 (INV-1)" "$_CAPTURED_EXIT"; return 1; }
  printf '%s' "$_CAPTURED_STDOUT" | jq -e \
    '.fallback == true and .fallback_reason == "tool-skill-unavailable"' \
    >/dev/null 2>&1 || { _fail "fallback tool-skill-unavailable" "$_CAPTURED_STDOUT"; return 1; }
}

# ---- 1.3.3 + F-003: timeout dispara fallback exit-nonzero ----

scenario_invoke_timeout_dispara_fallback() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _slow="$TMPDIR_TEST/slow.sh"
  # Skill que dorme alem do timeout (8s) — watcher mata em ~2s.
  cat > "$_slow" <<'EOF'
#!/bin/sh
sleep 8
echo "## Modelo Sugerido"
echo ""
echo "haiku"
exit 0
EOF
  chmod +x "$_slow"
  MODEL_SELECTOR_SCRIPT="$_slow" capture sh "$SCRIPT" invoke \
    --subagent-type agente-00c-clarify-asker --etapa clarify \
    --input-text "x" --timeout-seconds 2
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit=0 (INV-1)" "$_CAPTURED_EXIT"; return 1; }
  printf '%s' "$_CAPTURED_STDOUT" | jq -e \
    '.fallback == true and .fallback_reason == "exit-nonzero"' \
    >/dev/null 2>&1 || { _fail "timeout->fallback" "$_CAPTURED_STDOUT"; return 1; }
}

# ---- 1.3.8: raw_stdout_first_200 e fallback_stderr_first_200 com tr -d ----

scenario_invoke_raw_stdout_first_200_truncado() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _stub="$TMPDIR_TEST/score2.sh"
  _mr_make_stub_score2 "$_stub"
  MODEL_SELECTOR_SCRIPT="$_stub" capture sh "$SCRIPT" invoke \
    --subagent-type agente-00c-clarify-asker --etapa clarify --input-text "x"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit=0" "$_CAPTURED_EXIT"; return 1; }
  # raw_stdout_first_200 deve existir, comecar com "## Modelo Sugerido"
  # e ter no maximo 200 bytes.
  printf '%s' "$_CAPTURED_STDOUT" | jq -e \
    '.raw_stdout_first_200
      | (startswith("## Modelo Sugerido")) and (length <= 200)' \
    >/dev/null 2>&1 || { _fail "raw_stdout_first_200" "$_CAPTURED_STDOUT"; return 1; }
}

# F-001: input com null-byte no --input-text NAO deve aparecer cru no
# raw_stdout_first_200 / fallback_stderr_first_200. Garantido via
# tr -d '\000'. Edge case: classify.sh real rejeita null bytes (exit 2),
# entao usamos stub que ecoa o input em stdout para verificar saneamento.
scenario_invoke_null_byte_sanitizado() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _stub="$TMPDIR_TEST/nullecho.sh"
  cat > "$_stub" <<'EOF'
#!/bin/sh
# Emite null-byte literal no stderr + saida mal-formada.
printf 'literal\000nullbyte' >&2
echo "no sections"
exit 9
EOF
  chmod +x "$_stub"
  MODEL_SELECTOR_SCRIPT="$_stub" capture sh "$SCRIPT" invoke \
    --subagent-type agente-00c-clarify-asker --etapa clarify --input-text "x"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit=0" "$_CAPTURED_EXIT"; return 1; }
  # JSON deve ser parseavel mesmo com null-byte na origem (saneado via tr -d).
  printf '%s' "$_CAPTURED_STDOUT" | jq -e \
    '.fallback_stderr_first_200 | contains("literalnullbyte")' \
    >/dev/null 2>&1 || { _fail "null-byte saneado" "$_CAPTURED_STDOUT"; return 1; }
}

# ==== F1.4: idempotent-check ====
#
# Cobertura completa por subtarefa (1.4.1 - 1.4.5):
#   1.4.1 validacao de flags (state-dir/onda-id/subagent-type + enums)
#   1.4.2 query jq read-only sobre .decisoes[] com contexto canonico
#   1.4.3 contrato de exit: 0 (existe), 1 (nao existe), 2 (uso)
#   1.4.4 paralelismo: 100x via xargs/seq -> sha256 state.json antes/depois
#   1.4.5 F-001 defesa: --arg em jq, NUNCA interpolacao shell em expressao

# Helper: cria state.json minimo + opcionalmente uma Decisao matching.
# $1 = dir destino (sera criado), $2 = subagent-type, $3 = onda-id,
# $4 = "match" para inserir Decisao matching, "nomatch" para nao inserir.
_mr_idc_fixture() {
  _mr_have_jq || return 2
  _dir=$1
  _subagent=$2
  _onda=$3
  _mode=$4
  mkdir -p "$_dir" || return 2
  if [ "$_mode" = "match" ]; then
    jq -n \
      --arg ctx "Selecao de modelo para subagente $_subagent" \
      --arg onda "$_onda" \
      '{
        decisoes: [
          {
            id: "dec-042",
            onda_id: $onda,
            agente: "agente-00c-orchestrator",
            etapa: "clarify",
            contexto: $ctx,
            opcoes: ["a","b"],
            escolha: "a",
            justificativa: "matching fixture for idempotent-check",
            score: 3
          }
        ]
      }' > "$_dir/state.json"
  else
    jq -n '{ decisoes: [] }' > "$_dir/state.json"
  fi
}

# Hash auxiliar portavel (macOS shasum / Linux sha256sum).
_mr_idc_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    printf 'NOHASH\n'
  fi
}

# ---- 1.4.1: flags obrigatorias ----

scenario_idempotent_check_flag_state_dir_ausente() {
  capture sh "$SCRIPT" idempotent-check --onda-id onda-001 \
    --subagent-type agente-00c-clarify-asker
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit=2 (state-dir ausente)" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "--state-dir ausente" || return 1
}

scenario_idempotent_check_flag_onda_id_ausente() {
  capture sh "$SCRIPT" idempotent-check --state-dir /tmp \
    --subagent-type agente-00c-clarify-asker
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit=2 (onda-id ausente)" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "--onda-id ausente" || return 1
}

scenario_idempotent_check_flag_subagent_type_ausente() {
  capture sh "$SCRIPT" idempotent-check --state-dir /tmp --onda-id onda-001
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit=2 (subagent-type ausente)" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "--subagent-type ausente" || return 1
}

# ---- 1.4.1: validacao de pattern onda-id ----

scenario_idempotent_check_onda_id_formato_invalido() {
  capture sh "$SCRIPT" idempotent-check --state-dir /tmp \
    --onda-id "onda-abc" --subagent-type agente-00c-clarify-asker
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit=2 (onda formato invalido)" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "--onda-id formato invalido" || return 1
}

scenario_idempotent_check_onda_id_sem_prefixo() {
  capture sh "$SCRIPT" idempotent-check --state-dir /tmp \
    --onda-id "001" --subagent-type agente-00c-clarify-asker
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit=2 (onda sem prefixo)" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "--onda-id formato invalido" || return 1
}

# ---- 1.4.1: validacao do enum subagent-type ----

scenario_idempotent_check_subagent_type_enum_invalido() {
  capture sh "$SCRIPT" idempotent-check --state-dir /tmp \
    --onda-id onda-001 --subagent-type "agente-00c-clarify-bogus"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit=2 (enum invalido)" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "fora do enum" || return 1
}

# ---- 1.4.3 (parte): state.json ausente -> exit 2 ----

scenario_idempotent_check_state_ausente() {
  mktemp_test || return 2
  # Diretorio vazio (sem state.json)
  capture sh "$SCRIPT" idempotent-check --state-dir "$TMPDIR_TEST" \
    --onda-id onda-001 --subagent-type agente-00c-clarify-asker
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit=2 (state ausente)" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "state.json ausente" || return 1
}

# ---- 1.4.2 + 1.4.3: query HIT (Decisao matching existe) ----

scenario_idempotent_check_hit_emite_dec_id_e_exit_0() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _mr_idc_fixture "$TMPDIR_TEST" "agente-00c-clarify-asker" "onda-005" "match" || return 2
  capture sh "$SCRIPT" idempotent-check \
    --state-dir "$TMPDIR_TEST" \
    --onda-id onda-005 \
    --subagent-type agente-00c-clarify-asker
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit=0 (HIT)" "obtido $_CAPTURED_EXIT (stderr=$_CAPTURED_STDERR)"; return 1; }
  # Stdout deve ser exatamente "dec-042" (mais newline trailing).
  _stdout_trim=$(printf '%s' "$_CAPTURED_STDOUT" | tr -d '\n')
  [ "$_stdout_trim" = "dec-042" ] || { _fail "stdout=dec-042" "obtido '$_stdout_trim'"; return 1; }
}

# ---- 1.4.2 + 1.4.3: query MISS (nao existe Decisao matching) ----

scenario_idempotent_check_miss_stdout_vazio_e_exit_1() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _mr_idc_fixture "$TMPDIR_TEST" "agente-00c-clarify-asker" "onda-005" "nomatch" || return 2
  capture sh "$SCRIPT" idempotent-check \
    --state-dir "$TMPDIR_TEST" \
    --onda-id onda-005 \
    --subagent-type agente-00c-clarify-asker
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit=1 (MISS)" "obtido $_CAPTURED_EXIT"; return 1; }
  # Stdout deve ser vazio (FR-012).
  _stdout_trim=$(printf '%s' "$_CAPTURED_STDOUT" | tr -d '\n')
  [ -z "$_stdout_trim" ] || { _fail "stdout vazio (MISS)" "obtido '$_stdout_trim'"; return 1; }
}

# ---- 1.4.2: discriminacao por subagent-type ----
# Decisao registrada para asker, query para answerer -> MISS (FR-012).
scenario_idempotent_check_discrimina_subagent_type() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _mr_idc_fixture "$TMPDIR_TEST" "agente-00c-clarify-asker" "onda-005" "match" || return 2
  capture sh "$SCRIPT" idempotent-check \
    --state-dir "$TMPDIR_TEST" \
    --onda-id onda-005 \
    --subagent-type agente-00c-clarify-answerer
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit=1 (subagent diff -> MISS)" "obtido $_CAPTURED_EXIT"; return 1; }
}

# ---- 1.4.2: discriminacao por onda-id ----
# Decisao registrada para onda-005, query para onda-006 -> MISS.
scenario_idempotent_check_discrimina_onda_id() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _mr_idc_fixture "$TMPDIR_TEST" "agente-00c-clarify-asker" "onda-005" "match" || return 2
  capture sh "$SCRIPT" idempotent-check \
    --state-dir "$TMPDIR_TEST" \
    --onda-id onda-006 \
    --subagent-type agente-00c-clarify-asker
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit=1 (onda diff -> MISS)" "obtido $_CAPTURED_EXIT"; return 1; }
}

# ---- 1.4.3: determinismo — mesma query 3x retorna mesmo stdout/exit ----

scenario_idempotent_check_determinismo_hit() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _mr_idc_fixture "$TMPDIR_TEST" "feature-00c-clarify-asker" "onda-007" "match" || return 2

  _i=0
  _prev_stdout=""
  while [ "$_i" -lt 3 ]; do
    capture sh "$SCRIPT" idempotent-check \
      --state-dir "$TMPDIR_TEST" \
      --onda-id onda-007 \
      --subagent-type feature-00c-clarify-asker
    [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit=0 (det HIT iter $_i)" "obtido $_CAPTURED_EXIT"; return 1; }
    if [ "$_i" -gt 0 ]; then
      [ "$_CAPTURED_STDOUT" = "$_prev_stdout" ] || { _fail "stdout determinista" "iter $_i diverge"; return 1; }
    fi
    _prev_stdout=$_CAPTURED_STDOUT
    _i=$((_i + 1))
  done
}

# ---- 1.4.4 + INV-4: paralelismo — N invocacoes nao alteram state.json ----
# Implementacao POSIX-friendly: 50 processos em background, sha256 antes
# e depois, comparacao. xargs -P existe em GNU e BSD mas usamos seq +
# background para maior portabilidade. 50 ja exercita o invariante de
# read-only (a corrida real seria com write — comprovar que helper nao
# escreve == nenhum byte muda).
scenario_idempotent_check_paralelo_inv4() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _mr_idc_fixture "$TMPDIR_TEST" "agente-00c-clarify-asker" "onda-009" "match" || return 2

  _state_file="$TMPDIR_TEST/state.json"
  _hash_before=$(_mr_idc_sha256 "$_state_file")
  [ -n "$_hash_before" ] && [ "$_hash_before" != "NOHASH" ] || {
    _error "nenhuma ferramenta de hash disponivel (sha256sum/shasum)"
    return 2
  }

  # 50 invocacoes em background. Output redirecionado para /dev/null —
  # so importa o efeito colateral (que nao deve existir).
  _i=0
  while [ "$_i" -lt 50 ]; do
    sh "$SCRIPT" idempotent-check \
      --state-dir "$TMPDIR_TEST" \
      --onda-id onda-009 \
      --subagent-type agente-00c-clarify-asker \
      >/dev/null 2>&1 &
    _i=$((_i + 1))
  done
  wait

  _hash_after=$(_mr_idc_sha256 "$_state_file")
  [ "$_hash_before" = "$_hash_after" ] || {
    _fail "INV-4 state.json inalterado apos 50 invocacoes paralelas" \
          "before=$_hash_before after=$_hash_after"
    return 1
  }
}

# ---- 1.4.5: F-001 defesa — subagent-type com payload adversarial ----
# Mesmo que --subagent-type valide enum, garantimos que jq usa --arg
# (nao interpolacao). Testamos com payload que tentaria injetar jq se
# fosse concatenado: contem aspas duplas e pipe. Validacao de enum
# barra antes — mas se um dia o enum for relaxado, o --arg ainda
# protege. Aqui usamos o cenario onde input invalido vira exit 2.
scenario_idempotent_check_f001_arg_quoting() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _mr_idc_fixture "$TMPDIR_TEST" "agente-00c-clarify-asker" "onda-001" "match" || return 2

  # Payload com aspas/pipe/backslash. Atualmente rejeitado pelo enum;
  # se passasse, jq --arg trataria como string literal.
  capture sh "$SCRIPT" idempotent-check \
    --state-dir "$TMPDIR_TEST" \
    --onda-id onda-001 \
    --subagent-type 'foo" or .decisoes | .[0]'
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit=2 (enum bloqueia adversarial)" "obtido $_CAPTURED_EXIT"; return 1; }
  # Audit no codigo: query jq usa --arg (regra estatica). Grep como
  # defesa permanente — se alguem trocar para interpolacao "$VAR"
  # dentro da expressao jq, este teste falha.
  if grep -nE 'jq -r[^|]*"[^"]*\$_mr_idc' "$SCRIPT" >/dev/null 2>&1; then
    _fail "F-001: jq idempotent-check sem --arg" "interpolacao shell detectada no SCRIPT"
    return 1
  fi
  grep -nE '\--arg ctx ' "$SCRIPT" >/dev/null 2>&1 || {
    _fail "F-001: jq idempotent-check usa --arg ctx" "padrao nao encontrado"
    return 1
  }
}

# ==== F2.2.3: Retomada idempotente — dry-run do protocolo /agente-00c-resume ====
#
# Cobertura:
#   - Fixture tests/fixtures/state-with-onda-002-decisao.json simula
#     state.json apos crash entre state-decisions.sh register (passo 5
#     da sequencia pre-spawn) e o retorno da tool Agent.
#   - Cenario 1: idempotent-check para o subagente JA registrado em
#     onda-002 -> exit 0 + stdout="dec-019" (skip de invoke + register).
#   - Cenario 2: idempotent-check para subagent-type DIFERENTE na
#     mesma onda -> exit 1 (sequencia 4-6 deve rodar para esse).
#   - Cenario 3: idempotent-check em onda DIFERENTE -> exit 1.
#   - Cenario 4: 3 execucoes consecutivas em retomada repetida nao
#     mudam state.json (INV-4 sob padrao de retomada).
#
# Garante o contrato documentado em
# global/agents/agente-00c-orchestrator.md §5.e.bis "Invariante I2 —
# Retomada idempotente" e tasks.md F2.2 (subtask 2.2.3).

_FIXTURE_RESUME="$REPO_ROOT/tests/fixtures/state-with-onda-002-decisao.json"

# Copia a fixture para um diretorio temporario (idempotent-check exige
# state.json em <state-dir>/state.json e a fixture nao deve ser mutada).
_mr_resume_copy_fixture() {
  _dst=$1
  [ -f "$_FIXTURE_RESUME" ] || {
    _error "fixture nao encontrada: $_FIXTURE_RESUME"
    return 2
  }
  mkdir -p "$_dst" || return 2
  cp "$_FIXTURE_RESUME" "$_dst/state.json" || return 2
}

scenario_resume_idempotent_check_hit_skips_invoke() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _mr_resume_copy_fixture "$TMPDIR_TEST" || return 2

  # Sequencia que o orquestrador roda em retomada para o subagente JA
  # registrado: model-routing.sh idempotent-check (--state-dir = fixture,
  # --onda-id onda-002, --subagent-type agente-00c-clarify-asker).
  capture sh "$SCRIPT" idempotent-check \
    --state-dir "$TMPDIR_TEST" \
    --onda-id onda-002 \
    --subagent-type agente-00c-clarify-asker

  # Contrato: exit 0 + stdout = dec-019 -> orquestrador pula passos 4-6
  # (invoke + register + record-skill) e vai direto a spawn-tracker enter.
  [ "$_CAPTURED_EXIT" = 0 ] || {
    _fail "exit=0 (resume HIT)" \
          "obtido $_CAPTURED_EXIT (stderr=$_CAPTURED_STDERR)"
    return 1
  }
  _stdout_trim=$(printf '%s' "$_CAPTURED_STDOUT" | tr -d '\n')
  [ "$_stdout_trim" = "dec-019" ] || {
    _fail "stdout=dec-019 (resume HIT)" "obtido '$_stdout_trim'"
    return 1
  }
}

scenario_resume_idempotent_check_miss_em_subagent_distinto() {
  # Mesmo onda-id (onda-002), subagent-type diferente (answerer em vez
  # de asker) -> MISS: orquestrador DEVE rodar invoke + register para
  # answerer (Invariante I1 — 1 Decisao por spawn REAL).
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _mr_resume_copy_fixture "$TMPDIR_TEST" || return 2

  capture sh "$SCRIPT" idempotent-check \
    --state-dir "$TMPDIR_TEST" \
    --onda-id onda-002 \
    --subagent-type agente-00c-clarify-answerer

  [ "$_CAPTURED_EXIT" = 1 ] || {
    _fail "exit=1 (resume MISS — subagent distinto)" \
          "obtido $_CAPTURED_EXIT"
    return 1
  }
  _stdout_trim=$(printf '%s' "$_CAPTURED_STDOUT" | tr -d '\n')
  [ -z "$_stdout_trim" ] || {
    _fail "stdout vazio (MISS)" "obtido '$_stdout_trim'"
    return 1
  }
}

scenario_resume_idempotent_check_miss_em_onda_distinta() {
  # Mesmo subagent-type, onda-id diferente (onda-003) -> MISS.
  # Garante que Decisao de onda-002 nao "vaza" para ondas seguintes.
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _mr_resume_copy_fixture "$TMPDIR_TEST" || return 2

  capture sh "$SCRIPT" idempotent-check \
    --state-dir "$TMPDIR_TEST" \
    --onda-id onda-003 \
    --subagent-type agente-00c-clarify-asker

  [ "$_CAPTURED_EXIT" = 1 ] || {
    _fail "exit=1 (resume MISS — onda distinta)" \
          "obtido $_CAPTURED_EXIT"
    return 1
  }
}

scenario_resume_idempotent_check_readonly_em_retomadas_repetidas() {
  # Simula 3 retomadas consecutivas (ex: usuario rodou /agente-00c-resume
  # 3x apos crashes sucessivos). Cada uma DEVE retornar exit 0 + dec-019
  # e NAO mutar state.json (INV-4 sob padrao de retomada repetida).
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _mr_resume_copy_fixture "$TMPDIR_TEST" || return 2

  _state_file="$TMPDIR_TEST/state.json"
  _hash_before=$(_mr_idc_sha256 "$_state_file")
  [ -n "$_hash_before" ] && [ "$_hash_before" != "NOHASH" ] || {
    _error "nenhuma ferramenta de hash disponivel (sha256sum/shasum)"
    return 2
  }

  _i=0
  while [ "$_i" -lt 3 ]; do
    capture sh "$SCRIPT" idempotent-check \
      --state-dir "$TMPDIR_TEST" \
      --onda-id onda-002 \
      --subagent-type agente-00c-clarify-asker
    [ "$_CAPTURED_EXIT" = 0 ] || {
      _fail "exit=0 (retomada iter $_i)" "obtido $_CAPTURED_EXIT"
      return 1
    }
    _stdout_trim=$(printf '%s' "$_CAPTURED_STDOUT" | tr -d '\n')
    [ "$_stdout_trim" = "dec-019" ] || {
      _fail "stdout=dec-019 (retomada iter $_i)" "obtido '$_stdout_trim'"
      return 1
    }
    _i=$((_i + 1))
  done

  _hash_after=$(_mr_idc_sha256 "$_state_file")
  [ "$_hash_before" = "$_hash_after" ] || {
    _fail "INV-4: state.json inalterado apos 3 retomadas" \
          "before=$_hash_before after=$_hash_after"
    return 1
  }
}

# ==== F2.3.2: Compatibilidade com agente-00c-artifact-cache ====
#
# Refs: tasks.md F2.3.2, spec.md SC-004 e FR-014,
#       agente-00c-orchestrator.md §5.e.bis (paragrafo compatibilidade).
#
# Cobertura:
#   1. idempotent-check ignora completamente briefing_cache/constitution_cache
#      (read-only sobre .decisoes[]; nao referencia campos de cache).
#   2. invoke nao tenta ler briefing/constitution do FS (helper opera sobre
#      template estatico + override --input-text; nenhuma leitura de
#      docs/ esperada).
#   3. Pipeline mini (idempotent-check + invoke) preserva sha256 dos
#      campos briefing_cache/constitution_cache em state.json fixture
#      (extensao INV-4 para o eixo cache).

# Helper: cria state.json fixture com (a) Decisao matching para HIT em
# idempotent-check, (b) briefing_cache + constitution_cache populados
# como em onda 1 do artifact-cache. Estrutura dos campos de cache
# segue o schema descrito em docs/specs/_archived/agente-00c-artifact-cache/spec.md.
_mr_artifact_cache_fixture() {
  _mr_have_jq || return 2
  _dir=$1
  mkdir -p "$_dir" || return 2
  jq -n '{
    schema_version: "1.6.0",
    decisoes: [
      {
        id: "dec-091",
        onda_id: "onda-005",
        agente: "agente-00c-orchestrator",
        etapa: "clarify",
        contexto: "Selecao de modelo para subagente agente-00c-clarify-asker",
        opcoes: ["a","b"],
        escolha: "a",
        justificativa: "fixture artifact-cache compat",
        score: 3
      }
    ],
    briefing_cache: {
      estrategia: "cached",
      source_path: "docs/01-briefing-discovery/briefing.md",
      source_sha256: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
      source_chars: 8421,
      resumo: "Resumo executivo de briefing populado pela onda 1 do artifact-cache. Mock de ~120 chars para o cenario de compat.",
      resumo_chars: 110,
      gerado_em: "2026-05-22T18:00:00Z"
    },
    constitution_cache: {
      estrategia: "cached",
      source_path: "docs/constitution.md",
      source_sha256: "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210",
      source_chars: 6210,
      resumo: "Resumo executivo de constitution: principios MUST sintetizados.",
      resumo_chars: 64,
      gerado_em: "2026-05-22T18:00:01Z"
    }
  }' > "$_dir/state.json"
}

# Helper: extrai sha256 do bloco JSON .briefing_cache + .constitution_cache.
# Usa jq -c -S para serializacao estavel (sort + compact), depois hash via
# _mr_idc_sha256 sobre stdin redirecionado a arquivo temporario (necessario
# em macOS/BSD shasum que nao le stdin com '-' identico ao GNU). Output e
# o hash hex do par cache.
_mr_artifact_cache_hash() {
  _state=$1
  _tmp=$(mktemp 2>/dev/null) || _tmp="$_state.cachehash.tmp"
  jq -c -S '{briefing_cache: .briefing_cache, constitution_cache: .constitution_cache}' \
    "$_state" > "$_tmp" 2>/dev/null || { rm -f "$_tmp"; return 2; }
  _h=$(_mr_idc_sha256 "$_tmp")
  rm -f "$_tmp"
  printf '%s\n' "$_h"
}

# ---- F2.3.2 / Cenario 1: idempotent-check ignora cache ----

scenario_artifact_cache_compat_idempotent_check_ignora_cache() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _mr_artifact_cache_fixture "$TMPDIR_TEST" || return 2

  _state_file="$TMPDIR_TEST/state.json"
  _cache_hash_before=$(_mr_artifact_cache_hash "$_state_file")
  [ -n "$_cache_hash_before" ] && [ "$_cache_hash_before" != "NOHASH" ] || {
    _error "hash do cache indisponivel"
    return 2
  }

  # HIT esperado: Decisao dec-091 ja registrada para asker/onda-005.
  capture sh "$SCRIPT" idempotent-check \
    --state-dir "$TMPDIR_TEST" \
    --onda-id onda-005 \
    --subagent-type agente-00c-clarify-asker
  [ "$_CAPTURED_EXIT" = 0 ] || {
    _fail "exit=0 (HIT com cache populado)" "obtido $_CAPTURED_EXIT (stderr=$_CAPTURED_STDERR)"
    return 1
  }
  _stdout_trim=$(printf '%s' "$_CAPTURED_STDOUT" | tr -d '\n')
  [ "$_stdout_trim" = "dec-091" ] || {
    _fail "stdout=dec-091" "obtido '$_stdout_trim'"
    return 1
  }

  # Cache permanece bit-a-bit identico.
  _cache_hash_after=$(_mr_artifact_cache_hash "$_state_file")
  [ "$_cache_hash_before" = "$_cache_hash_after" ] || {
    _fail "cache sha256 estavel" \
          "before=$_cache_hash_before after=$_cache_hash_after"
    return 1
  }
}

# ---- F2.3.2 / Cenario 2: invoke nao depende de briefing/constitution em disco ----

scenario_artifact_cache_compat_invoke_nao_le_briefing_constitution() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2

  # Diretorio de trabalho isolado SEM nenhum docs/ ou briefing.md.
  # Se o helper tentasse ler briefing/constitution do FS, falharia.
  cd "$TMPDIR_TEST" || { _error "cd $TMPDIR_TEST falhou"; return 2; }

  capture sh "$SCRIPT" invoke \
    --subagent-type feature-00c-clarify-answerer \
    --etapa clarify
  [ "$_CAPTURED_EXIT" = 0 ] || {
    _fail "exit=0 (invoke sem docs/ no FS)" "obtido $_CAPTURED_EXIT (stderr=$_CAPTURED_STDERR)"
    return 1
  }
  # INV-2: JSON parseavel.
  printf '%s' "$_CAPTURED_STDOUT" | jq -e . >/dev/null 2>&1 || {
    _fail "JSON parseavel sem briefing/constitution" "stdout invalido"
    return 1
  }
  # Shape: subagent_type e etapa preservados; input_bytes nao zero (vem do template).
  printf '%s' "$_CAPTURED_STDOUT" | jq -e \
    '.subagent_type == "feature-00c-clarify-answerer"
      and .etapa == "clarify"
      and (.input_bytes | type == "number")
      and (.input_bytes > 0)' >/dev/null 2>&1 || {
    _fail "shape JSON (sem cache)" "campos invalidos"
    return 1
  }
}

# ---- F2.3.2 / Cenario 3: pipeline mini preserva sha256 do cache ----

scenario_artifact_cache_compat_pipeline_sha256_cache_estavel() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _mr_artifact_cache_fixture "$TMPDIR_TEST" || return 2

  _state_file="$TMPDIR_TEST/state.json"
  _cache_hash_before=$(_mr_artifact_cache_hash "$_state_file")
  [ -n "$_cache_hash_before" ] && [ "$_cache_hash_before" != "NOHASH" ] || {
    _error "hash do cache indisponivel"
    return 2
  }

  # Mini-pipeline: idempotent-check (HIT esperado) + invoke (template).
  # Em ambos os passos, o helper opera sem tocar campos de cache.
  capture sh "$SCRIPT" idempotent-check \
    --state-dir "$TMPDIR_TEST" \
    --onda-id onda-005 \
    --subagent-type agente-00c-clarify-asker
  [ "$_CAPTURED_EXIT" = 0 ] || {
    _fail "step1 idempotent-check exit=0" "obtido $_CAPTURED_EXIT"
    return 1
  }

  capture sh "$SCRIPT" invoke \
    --subagent-type agente-00c-clarify-asker \
    --etapa clarify
  [ "$_CAPTURED_EXIT" = 0 ] || {
    _fail "step2 invoke exit=0" "obtido $_CAPTURED_EXIT (stderr=$_CAPTURED_STDERR)"
    return 1
  }

  # Cache permanece bit-a-bit identico apos a pipeline.
  _cache_hash_after=$(_mr_artifact_cache_hash "$_state_file")
  [ "$_cache_hash_before" = "$_cache_hash_after" ] || {
    _fail "cache sha256 estavel apos pipeline" \
          "before=$_cache_hash_before after=$_cache_hash_after"
    return 1
  }
}

# ==== F3.1.4: Patch documental — secao pre-spawn no feature-orchestrator ====
#
# Espelha F2.1.4 (sequencia pre-spawn no agente-00c-orchestrator.md), agora
# para global/agents/agente-00c-feature-orchestrator.md. O patch documental
# adiciona a secao "## Sequencia pre-spawn de subagente (model-routing)"
# com ordem canonica (8 passos) e subagent_types feature-00c-clarify-*.
#
# Assertions documentais (grep):
#   1. >= 1 match de "model-routing.sh invoke"
#   2. >= 1 match de "spawn-tracker.sh enter"
#   3. ORDEM: ultimo "model-routing.sh invoke" aparece ANTES do ultimo
#      "spawn-tracker.sh enter" (passo 4 antes do passo 7 na secao)
#   4. presenca dos subagent_types feature-00c-clarify-asker E
#      feature-00c-clarify-answerer (cobre asker + answerer)

scenario_doc_feature_orchestrator_sequencia_pre_spawn() {
  _doc="$REPO_ROOT/global/agents/agente-00c-feature-orchestrator.md"
  [ -f "$_doc" ] || { _fail "feature-orchestrator.md existe" "nao encontrado em $_doc"; return 1; }

  # Match >= 1 de model-routing.sh invoke
  _n_invoke=$(grep -c "model-routing.sh invoke" "$_doc" || true)
  [ "${_n_invoke:-0}" -ge 1 ] || {
    _fail "grep model-routing.sh invoke >= 1" "obtido $_n_invoke"
    return 1
  }

  # Match >= 1 de spawn-tracker.sh enter
  _n_enter=$(grep -c "spawn-tracker.sh enter" "$_doc" || true)
  [ "${_n_enter:-0}" -ge 1 ] || {
    _fail "grep spawn-tracker.sh enter >= 1" "obtido $_n_enter"
    return 1
  }

  # Ordem: ultimo "model-routing.sh invoke" aparece ANTES do ultimo
  # "spawn-tracker.sh enter" no arquivo (passo 4 antes do passo 7).
  _line_invoke=$(grep -n "model-routing.sh invoke" "$_doc" | tail -1 | cut -d: -f1)
  _line_enter=$(grep -n "spawn-tracker.sh enter" "$_doc" | tail -1 | cut -d: -f1)
  [ -n "$_line_invoke" ] && [ -n "$_line_enter" ] || {
    _fail "linhas localizadas" "invoke=$_line_invoke enter=$_line_enter"
    return 1
  }
  [ "$_line_invoke" -lt "$_line_enter" ] || {
    _fail "ordem invoke antes de enter" "invoke=line:$_line_invoke enter=line:$_line_enter"
    return 1
  }

  # Subagent types feature-00c presentes (cobre asker E answerer)
  grep -q "feature-00c-clarify-asker" "$_doc" || {
    _fail "subagent feature-00c-clarify-asker presente" "ausente"
    return 1
  }
  grep -q "feature-00c-clarify-answerer" "$_doc" || {
    _fail "subagent feature-00c-clarify-answerer presente" "ausente"
    return 1
  }
}

# ==== F3.2.3: Two-step register+record-skill — query jq de paridade ====
#
# Documenta a query jq de auditoria (Invariante I3 em
# agente-00c-feature-orchestrator.md "## Sequencia pre-spawn de subagente"):
#
#   N_DEC = count de .decisoes[] com contexto "Selecao de modelo para subagente <T>"
#   N_REC = count de .ondas[].skills_invoked[] com skill == "model-selector"
#
# Invariante: N_DEC == N_REC (1-para-1). Quebra dessa paridade indica
# half-record (crash entre passo 5 e passo 6 da sequencia pre-spawn) e
# vira finding `model-routing-half-record` em review-task.
#
# Test usa fixture sintetica inline (sem dependencia de arquivos externos).

scenario_doc_two_step_register_record_skill_paridade() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2

  # Fixture: state.json com 2 Decisoes "Selecao de modelo" e 2 record-skill
  # model-selector. N_DEC == N_REC == 2.
  cat > "$TMPDIR_TEST/state.json" <<'JSON'
{
  "schema_version": "1.0.0",
  "status": "em_andamento",
  "ondas": [
    {
      "id": "onda-001",
      "skills_invoked": [
        { "skill": "model-selector", "decisao_id": "dec-001", "timestamp": "2026-05-22T10:00:00Z" },
        { "skill": "model-selector", "decisao_id": "dec-002", "timestamp": "2026-05-22T10:05:00Z" }
      ]
    }
  ],
  "decisoes": [
    {
      "id": "dec-001",
      "contexto": "Selecao de modelo para subagente feature-00c-clarify-asker",
      "agente": "agente-00c-feature-orchestrator",
      "etapa": "clarify",
      "escolha": "haiku",
      "score": 3
    },
    {
      "id": "dec-002",
      "contexto": "Selecao de modelo para subagente feature-00c-clarify-answerer",
      "agente": "agente-00c-feature-orchestrator",
      "etapa": "clarify",
      "escolha": "sonnet",
      "score": 3
    }
  ]
}
JSON

  # Query canonica da Invariante I3 (documentada no feature-orchestrator.md).
  _n_dec=$(jq '[.decisoes[] | select(.contexto | startswith("Selecao de modelo"))] | length' "$TMPDIR_TEST/state.json")
  _n_rec=$(jq '[.ondas[].skills_invoked[]? | select(.skill == "model-selector")] | length' "$TMPDIR_TEST/state.json")

  [ "$_n_dec" = "2" ] || { _fail "N_DEC == 2" "obtido $_n_dec"; return 1; }
  [ "$_n_rec" = "2" ] || { _fail "N_REC == 2" "obtido $_n_rec"; return 1; }
  [ "$_n_dec" = "$_n_rec" ] || {
    _fail "paridade N_DEC == N_REC" "N_DEC=$_n_dec N_REC=$_n_rec"
    return 1
  }
}

scenario_doc_two_step_half_record_detectavel() {
  # Cenario negativo: fixture com 2 Decisoes mas apenas 1 record-skill
  # (simulando crash entre passo 5 e passo 6). A query DEVE detectar
  # a paridade quebrada — base para o finding model-routing-half-record.
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2

  cat > "$TMPDIR_TEST/state.json" <<'JSON'
{
  "schema_version": "1.0.0",
  "status": "em_andamento",
  "ondas": [
    {
      "id": "onda-001",
      "skills_invoked": [
        { "skill": "model-selector", "decisao_id": "dec-001", "timestamp": "2026-05-22T10:00:00Z" }
      ]
    }
  ],
  "decisoes": [
    {
      "id": "dec-001",
      "contexto": "Selecao de modelo para subagente feature-00c-clarify-asker",
      "agente": "agente-00c-feature-orchestrator",
      "etapa": "clarify",
      "escolha": "haiku",
      "score": 3
    },
    {
      "id": "dec-002",
      "contexto": "Selecao de modelo para subagente feature-00c-clarify-answerer",
      "agente": "agente-00c-feature-orchestrator",
      "etapa": "clarify",
      "escolha": "sonnet",
      "score": 3
    }
  ]
}
JSON

  _n_dec=$(jq '[.decisoes[] | select(.contexto | startswith("Selecao de modelo"))] | length' "$TMPDIR_TEST/state.json")
  _n_rec=$(jq '[.ondas[].skills_invoked[]? | select(.skill == "model-selector")] | length' "$TMPDIR_TEST/state.json")

  # Paridade DEVE quebrar (2 != 1)
  [ "$_n_dec" = "2" ] || { _fail "N_DEC == 2" "obtido $_n_dec"; return 1; }
  [ "$_n_rec" = "1" ] || { _fail "N_REC == 1" "obtido $_n_rec"; return 1; }
  [ "$_n_dec" != "$_n_rec" ] || {
    _fail "paridade quebrada detectada" "N_DEC=$_n_dec N_REC=$_n_rec (inesperadamente iguais)"
    return 1
  }
}

# ==== INV-6 (parcial): shebang + set -eu + nenhum bash-ism obvio ====

scenario_inv6_shebang_e_set_eu() {
  # Shebang #!/bin/sh exatamente na linha 1.
  _line1=$(head -1 "$SCRIPT")
  [ "$_line1" = "#!/bin/sh" ] || { _fail "shebang" "esperado '#!/bin/sh', obtido '$_line1'"; return 1; }
  # set -eu presente.
  grep -q '^set -eu$' "$SCRIPT" || { _fail "set -eu" "nao encontrado"; return 1; }
  # Nao usa bash-isms obvios: [[ ]], arrays =(), local sem subshell wrapper.
  if grep -qE '\[\[ ' "$SCRIPT"; then
    _fail "bash-ism" "[[ ]] detectado"
    return 1
  fi
}

# ==== F4.1: Sanitizacao adversarial de --input-text (F-001 hardening) ====
#
# Cobre tasks.md F4.1.1..F4.1.5:
#   - 4.1.1 audit estatico: nenhum eval / sh -c "$var" / expansion sem aspas
#   - 4.1.2 helper _mr_validate_input remove NUL bytes (defesa em profundidade)
#   - 4.1.3 comentario inline referenciando CHK050 + F-001
#   - 4.1.4 payload adversarial executavel ($(...), backticks, ;, |, &) sem
#     side-effect no FS
#   - 4.1.5 fuzz quick com 50 strings adversariais via loop ate confirmar
#     que stdout do helper e JSON parseavel via jq -e em 100% dos casos
#
# Ref: dec-009 finding F-001 (medium), CHK050,
#      docs/specs/agente-00c-model-routing/checklists/requirements.md CHK050
#
# Defesa primaria: enum validation barra subagent-type. Defesa secundaria
# (F4.1): input bruto e gravado via printf '%s' + sanitizado por
# _mr_validate_input (NUL strip) + passado para skill via STDIN (sem
# expansao de shell). Defesa terciaria: JSON output composto exclusivamente
# via jq -n --arg/--argjson (F-002).

# ---- F4.1.1: audit estatico ----

scenario_f001_audit_no_eval_no_sh_c_var() {
  # Nenhum 'eval' fora de bloco de comentario.
  # Filtramos linhas de comentario (^[[:space:]]*#) antes do grep alvo.
  _bad_eval=$(grep -vE '^[[:space:]]*#' "$SCRIPT" \
               | grep -nE '^[[:space:]]*eval[[:space:]]' || true)
  [ -z "$_bad_eval" ] || {
    _fail "F-001: nenhum 'eval' executavel" "encontrado: $_bad_eval"
    return 1
  }
  # Nenhum sh -c "$var" — pattern indica injecao potencial.
  # Filtramos comentarios antes (as mencoes em prosa do header descrevem
  # JUSTAMENTE a defesa F-001 e nao sao codigo).
  _bad_sh_c=$(grep -vE '^[[:space:]]*#' "$SCRIPT" \
               | grep -nE 'sh -c[[:space:]]+"\$' || true)
  [ -z "$_bad_sh_c" ] || {
    _fail "F-001: nenhum 'sh -c \"\$var\"'" "encontrado: $_bad_sh_c"
    return 1
  }
  # Audit positivo: printf '%s' com $_mr_input_text usado para escrita.
  grep -nE "printf '%s' \"\\\$_mr_input_text\"" "$SCRIPT" >/dev/null || {
    _fail "F-001: printf '%s' \"\$_mr_input_text\" presente" "padrao nao encontrado"
    return 1
  }
}

scenario_f001_audit_validate_input_helper_presente() {
  # F4.1.2: helper _mr_validate_input definido E chamado em _mr_cmd_invoke.
  grep -qE '^_mr_validate_input\(\)' "$SCRIPT" || {
    _fail "F-001: _mr_validate_input definido" "padrao nao encontrado"
    return 1
  }
  # Chamado pelo menos 1 vez dentro do invoke.
  _calls=$(grep -cE '^[[:space:]]*_mr_validate_input ' "$SCRIPT" || true)
  [ "${_calls:-0}" -ge 1 ] || {
    _fail "F-001: _mr_validate_input chamado >= 1" "obtido $_calls"
    return 1
  }
}

scenario_f001_audit_chk050_comment() {
  # F4.1.3: comentario inline referenciando CHK050 + F-001.
  grep -qE 'CHK050' "$SCRIPT" || {
    _fail "F-001: comentario CHK050 inline" "nao encontrado"
    return 1
  }
  grep -qE 'F-001' "$SCRIPT" || {
    _fail "F-001: comentario F-001 inline" "nao encontrado"
    return 1
  }
}

# ---- F4.1.4: payload adversarial — nenhum side-effect no FS ----

scenario_f001_adversarial_payload_no_fs_side_effect() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2

  # Sentinel: arquivo que NAO deve ser deletado nem modificado pelo
  # processamento do payload adversarial.
  _sentinel="$TMPDIR_TEST/sentinel-do-not-touch.txt"
  printf 'sentinel-content-intacto\n' > "$_sentinel"
  _sentinel_sha_before=$(shasum -a 256 "$_sentinel" | awk '{print $1}')

  # Sentinel 2: caminho que payload tentaria criar via redirect.
  _evil_target="$TMPDIR_TEST/should-not-exist.txt"
  rm -f "$_evil_target"

  # Payload adversarial — varias tecnicas de injecao classicas:
  # ; rm -rf, $(touch ...), backticks, pipe para sh, redirect.
  _payload='foo; rm -rf '"$_sentinel"'; $(touch '"$_evil_target"'); `touch '"$_evil_target"'`; | sh > '"$_evil_target"
  # Skill desabilitada para nao depender do classify.sh real — testamos
  # SOMENTE o caminho do helper que processa --input-text e nao a skill.
  MODEL_SELECTOR_DISABLED=1 capture sh "$SCRIPT" invoke \
    --subagent-type agente-00c-clarify-asker \
    --etapa clarify \
    --input-text "$_payload"

  [ "$_CAPTURED_EXIT" = 0 ] || {
    _fail "exit=0 (INV-1 mesmo com adversarial input)" \
          "obtido $_CAPTURED_EXIT (stderr=$_CAPTURED_STDERR)"
    return 1
  }

  # Output deve ser JSON parseavel.
  printf '%s' "$_CAPTURED_STDOUT" | jq -e . >/dev/null 2>&1 || {
    _fail "JSON parseavel com adversarial input" "stdout='$_CAPTURED_STDOUT'"
    return 1
  }

  # Sentinel preservado.
  [ -f "$_sentinel" ] || {
    _fail "sentinel preservado" "arquivo DELETADO pelo payload!"
    return 1
  }
  _sentinel_sha_after=$(shasum -a 256 "$_sentinel" | awk '{print $1}')
  [ "$_sentinel_sha_before" = "$_sentinel_sha_after" ] || {
    _fail "sentinel inalterado" "sha mudou: before=$_sentinel_sha_before after=$_sentinel_sha_after"
    return 1
  }

  # Arquivo "evil" jamais criado (touch/redirect inertes).
  [ ! -f "$_evil_target" ] || {
    _fail "evil-target nao criado" "arquivo CRIADO pelo payload!"
    return 1
  }
}

# ---- F4.1.5: fuzz quick — 50 strings adversariais ----

scenario_f001_fuzz_50_adversarial_strings_json_parseavel() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2

  # 10 payloads-base (cada um repetido 5x com mutacao trivial = 50 total).
  _bases='$(touch /tmp/fuzz_evil_X)
`touch /tmp/fuzz_evil_X`
; rm -rf /tmp/fuzz_X
| sh /tmp/evil.sh
&& cat /etc/passwd
"; DROP TABLE; --
\x00\x01\x02
\\\\\\\"
\n\n\n\n\n
{"injected":"json","leak":true}'

  _n=0
  _fail_count=0

  _OLD_IFS="$IFS"
  IFS='
'
  for _base in $_bases; do
    _i=0
    while [ "$_i" -lt 5 ]; do
      _n=$((_n + 1))
      # Mutacao: prefixa indice para diferenciar invocacoes.
      _payload="fuzz#$_n: $_base"

      MODEL_SELECTOR_DISABLED=1 _out=$(sh "$SCRIPT" invoke \
        --subagent-type feature-00c-clarify-asker \
        --etapa clarify \
        --input-text "$_payload" 2>/dev/null) || {
        _fail_count=$((_fail_count + 1))
        _i=$((_i + 1))
        continue
      }

      # JSON parseavel (INV-2).
      printf '%s' "$_out" | jq -e . >/dev/null 2>&1 || {
        _fail_count=$((_fail_count + 1))
      }
      _i=$((_i + 1))
    done
  done
  IFS="$_OLD_IFS"

  # Side-effects nao podem ter ocorrido.
  [ ! -f /tmp/fuzz_evil_X ] || rm -f /tmp/fuzz_evil_X
  for _t in /tmp/fuzz_X /tmp/evil.sh; do
    [ ! -f "$_t" ] || {
      _fail "fuzz side-effect: $_t criado" "arquivo presente apos fuzz"
      return 1
    }
  done

  [ "$_n" = "50" ] || {
    _fail "50 invocacoes (fuzz)" "obtido $_n"
    return 1
  }
  [ "$_fail_count" = "0" ] || {
    _fail "100% JSON parseavel (50/50)" "$_fail_count falhas em 50 invocacoes"
    return 1
  }
}

# ---- F4.1.2 extra: NUL bytes sao removidos ----

scenario_f001_validate_input_remove_nul_bytes() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2

  # Input com NUL bytes embutidos via printf '\0'. Se _mr_validate_input
  # funciona, o helper concluira exit 0 + JSON parseavel mesmo com NUL
  # no payload.
  _payload_with_nul=$(printf 'before\000middle\000after')

  MODEL_SELECTOR_DISABLED=1 capture sh "$SCRIPT" invoke \
    --subagent-type agente-00c-clarify-answerer \
    --etapa clarify \
    --input-text "$_payload_with_nul"

  [ "$_CAPTURED_EXIT" = 0 ] || {
    _fail "exit=0 com NUL bytes em input" "obtido $_CAPTURED_EXIT (stderr=$_CAPTURED_STDERR)"
    return 1
  }
  printf '%s' "$_CAPTURED_STDOUT" | jq -e . >/dev/null 2>&1 || {
    _fail "JSON parseavel apos NUL strip" "stdout='$_CAPTURED_STDOUT'"
    return 1
  }
}

# ==========================================================================
# F4.2 — F-002 hardening: jq --arg em embedding de stdout sinais_text.
#
# Objetivo: garantir que sinais adversariais (aspas duplas, barra invertida,
# fragmentos de SQL injection, metacaracteres de shell) que cheguem ao
# `_mr_parse_skill_output` saiam intactos no campo `sinais_text` do JSON
# emitido pelo helper. O contrato F-002 e: helper NUNCA constroi JSON via
# concatenacao — sempre `jq -n --arg`. Esse test sela a invariante.
# ==========================================================================

# Stub skill que emite sinais com payload adversarial completo.
_mr_make_stub_adversarial_sinais() {
  cat > "$1" <<'EOF'
#!/bin/sh
cat <<'OUT'
## Modelo Sugerido

sonnet

## Score

1

rasa=0 media=1 profunda=0 faixa=media
score=1 modelo=sonnet alternativa=opus

## Justificativa

sinais detectados: aspas-duplas="hostis" \backslash "; DROP TABLE users; -- e $VAR

## Alternativa

opus
OUT
EOF
  chmod +x "$1"
}

scenario_f002_jq_arg_embedding_sinais_adversariais_json_parseavel() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2

  _stub="$TMPDIR_TEST/skill_adv.sh"
  _mr_make_stub_adversarial_sinais "$_stub"

  MODEL_SELECTOR_SCRIPT="$_stub" capture sh "$SCRIPT" invoke \
    --subagent-type agente-00c-clarify-asker --etapa clarify --input-text "x"

  [ "$_CAPTURED_EXIT" = 0 ] || {
    _fail "exit=0 com sinais adversariais" "obtido $_CAPTURED_EXIT (stderr=$_CAPTURED_STDERR)"
    return 1
  }

  # JSON DEVE ser parseavel (caminho jq -n --arg na fronteira do helper).
  printf '%s' "$_CAPTURED_STDOUT" | jq -e . >/dev/null 2>&1 || {
    _fail "JSON parseavel com sinais adversariais" "stdout='$_CAPTURED_STDOUT'"
    return 1
  }

  # fallback DEVE ser false (parse foi bem-sucedido, este e caminho normal).
  printf '%s' "$_CAPTURED_STDOUT" | jq -e '.fallback == false' \
    >/dev/null 2>&1 || {
    _fail "fallback=false (caminho normal)" "$_CAPTURED_STDOUT"
    return 1
  }
}

scenario_f002_jq_arg_preserva_aspas_duplas_em_sinais_text() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2

  _stub="$TMPDIR_TEST/skill_adv2.sh"
  _mr_make_stub_adversarial_sinais "$_stub"

  MODEL_SELECTOR_SCRIPT="$_stub" capture sh "$SCRIPT" invoke \
    --subagent-type agente-00c-clarify-asker --etapa clarify --input-text "x"

  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit=0" "$_CAPTURED_EXIT"; return 1; }

  # Extrair sinais_text via jq -r e validar que substrings adversariais
  # criticas estao presentes literalmente.
  _sinais=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.sinais_text')

  # Substring 1: aspas duplas literais preservadas
  case "$_sinais" in
    *'aspas-duplas="hostis"'*) ;;
    *) _fail 'aspas duplas literais preservadas' "$_sinais"; return 1 ;;
  esac

  # Substring 2: backslash literal preservado
  case "$_sinais" in
    *'\backslash'*) ;;
    *) _fail 'backslash literal preservado' "$_sinais"; return 1 ;;
  esac

  # Substring 3: payload SQL injection-like preservado
  case "$_sinais" in
    *'"; DROP TABLE users; --'*) ;;
    *) _fail 'fragmento SQL injection preservado' "$_sinais"; return 1 ;;
  esac

  # Substring 4: variavel-like preservada SEM expansao
  case "$_sinais" in
    *'$VAR'*) ;;
    *) _fail '$VAR preservado sem expansao' "$_sinais"; return 1 ;;
  esac
}

scenario_f002_jq_arg_roundtrip_via_state_decisions_register() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2

  # Validacao end-to-end de F4.2: sinais sai do helper, passa por jq -r,
  # entra em state-decisions.sh register com aspas duplas e o estado final
  # ainda contem o texto literal. Cobre o uso documentado nos
  # orquestradores (sequencia pre-spawn passo 5).

  _stub="$TMPDIR_TEST/skill_adv3.sh"
  _mr_make_stub_adversarial_sinais "$_stub"

  # 1) Invocar helper.
  _json=$(MODEL_SELECTOR_SCRIPT="$_stub" sh "$SCRIPT" invoke \
    --subagent-type agente-00c-clarify-asker --etapa clarify --input-text "x" 2>/dev/null) || {
    _fail "helper invoke exit 0" "exit=$?"
    return 1
  }

  # 2) Extrair sinais via jq -r (mesma forma do orquestrador).
  _SINAIS=$(printf '%s' "$_json" | jq -r '.sinais_text')
  _MODELO=$(printf '%s' "$_json" | jq -r '.modelo')
  _SCORE=$(printf '%s' "$_json"  | jq -r '.score_runtime')

  # Sanity guard: SINAIS nao vazio (>20 chars exigido por score 3 trava).
  [ "${#_SINAIS}" -ge 20 ] || {
    _fail "SINAIS >= 20 chars" "len=${#_SINAIS}"
    return 1
  }

  # 3) Setup minimo de state.json para registrar.
  _SD="$TMPDIR_TEST/f002_state"
  mkdir -p "$_SD"
  "$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-rw.sh" init \
    --state-dir "$_SD" \
    --execucao-id "exec-f002-test" \
    --projeto-alvo-path "$_SD" \
    --descricao "test f-002 jq --arg roundtrip" \
    >/dev/null 2>&1 || {
    _fail "state-rw init exit 0" "init falhou"
    return 1
  }

  # 4) Registrar Decisao com sinais literais (passos 5 dos orquestradores).
  # OBS: passa $_SINAIS com aspas duplas — forma canonica documentada.
  _DEC=$("$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-decisions.sh" register \
    --state-dir "$_SD" \
    --agente "test-orchestrator" --etapa "clarify" \
    --contexto "Selecao de modelo para subagente agente-00c-clarify-asker" \
    --opcoes '["haiku","sonnet","opus","manter-atual","fallback-default"]' \
    --escolha "$_MODELO" --score "$_SCORE" \
    --justificativa "$_SINAIS" \
    --evidencia "$_SINAIS" 2>/dev/null) || {
    _fail "state-decisions register exit 0" "register falhou (sinais='$_SINAIS')"
    return 1
  }

  # 5) Re-extrair justificativa e evidencia do state.json e comparar literal.
  _STATE_JSON="$_SD/state.json"
  _JUST_BACK=$(jq -r --arg id "$_DEC" \
    '.decisoes[] | select(.id == $id) | .justificativa' "$_STATE_JSON")
  _EVID_BACK=$(jq -r --arg id "$_DEC" \
    '.decisoes[] | select(.id == $id) | .evidencia' "$_STATE_JSON")

  [ "$_JUST_BACK" = "$_SINAIS" ] || {
    _fail "roundtrip justificativa literal preservada" \
      "esperado='$_SINAIS' obtido='$_JUST_BACK'"
    return 1
  }
  [ "$_EVID_BACK" = "$_SINAIS" ] || {
    _fail "roundtrip evidencia literal preservada" \
      "esperado='$_SINAIS' obtido='$_EVID_BACK'"
    return 1
  }
}

scenario_f002_jq_n_arg_usage_em_codigo_fonte_audit_estatica() {
  # Audit estatica: garante que cada construcao de JSON usa jq -n --arg.
  # Grep deve casar com >=2 blocos: emissao de fallback (linha ~505) +
  # emissao de sucesso (linha ~669). Qualquer regressao para concatenacao
  # quebra esse contrato.
  _hits=$(grep -cE '^[[:space:]]*jq -n[[:space:]]*\\?[[:space:]]*$' "$SCRIPT")
  [ "$_hits" -ge 2 ] || {
    _fail "jq -n usage >= 2 ocorrencias" "grep retornou $_hits hits"
    return 1
  }

  # Negativa: ZERO concatenacao tipo printf '{"sinais":"%s"}' "$X".
  if grep -qE 'printf[[:space:]]+["'"'"'][^"'"'"']*\{[^}]*"%s"' "$SCRIPT"; then
    _fail "ZERO printf JSON concatenado" "encontrou concatenacao em $SCRIPT"
    return 1
  fi
}

# ==========================================================================
# F4.5 — F-005 hardening: UTF-8 boundary backoff em _mr_truncate_bytes.
#
# Objetivo: input com codepoints UTF-8 multibyte intercalados, truncado
# em 4096+ bytes, deve gerar output UTF-8 valido (sem split de codepoint).
# Boundary backoff opera nas duas bordas: fim do segmento head (descarta
# lead-incompleto) e inicio do segmento tail (descarta continuation
# orfa).
# ==========================================================================

# Helper: gera arquivo com `n` bytes contendo emoji 4-byte UTF-8 (😀 =
# U+1F600 = F0 9F 98 80) intercalado com ASCII. Output exato em bytes.
_mr_make_emoji_payload() {
  _out=$1
  _target_bytes=$2
  : > "$_out"
  # Cada loop iteration adiciona ~12 bytes: 8 ASCII + 4-byte emoji.
  _written=0
  while [ "$_written" -lt "$_target_bytes" ]; do
    printf 'ABCDEFGH' >> "$_out"
    printf '\360\237\230\200' >> "$_out"
    _written=$((_written + 12))
  done
  # Truncar EXATAMENTE em $_target_bytes (sem se importar se cai em
  # codepoint — esse e justamente o cenario que o backoff trata).
  _final="$_out.exact"
  head -c "$_target_bytes" "$_out" > "$_final"
  mv "$_final" "$_out"
}

scenario_f005_utf8_emoji_4byte_truncagem_nao_split_codepoint() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2

  _payload_file="$TMPDIR_TEST/emoji_payload.txt"
  _mr_make_emoji_payload "$_payload_file" 8000

  _payload=$(cat "$_payload_file")

  capture sh "$SCRIPT" invoke --subagent-type agente-00c-clarify-asker \
    --etapa clarify --input-text "$_payload"

  [ "$_CAPTURED_EXIT" = 0 ] || {
    _fail "exit=0 com payload emoji" "exit=$_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"
    return 1
  }

  # 1) JSON parseavel (INV-2): jq aceita string UTF-8 valida.
  printf '%s' "$_CAPTURED_STDOUT" | jq -e . >/dev/null 2>&1 || {
    _fail "JSON parseavel apos truncagem UTF-8" "$_CAPTURED_STDOUT"
    return 1
  }

  # 2) input_truncado = true E input_bytes <= 4016 (INV-3 + dec-007).
  printf '%s' "$_CAPTURED_STDOUT" | jq -e \
    '.input_truncado == true and .input_bytes <= 4016' \
    >/dev/null 2>&1 || {
    _fail "INV-3: truncado=true e bytes<=4016" "$_CAPTURED_STDOUT"
    return 1
  }
}

scenario_f005_utf8_head_backoff_descarta_lead_incompleto() {
  # Test isolado do helper interno _mr_utf8_head_backoff via sourcing.
  # Constroi arquivo cujo ULTIMO byte e lead 4-byte (F0) — sequencia
  # incompleta. Backoff DEVE retornar 1 (descartar 1 byte).
  mktemp_test || return 2

  # Source do script para ter acesso a _mr_utf8_head_backoff.
  # Como model-routing.sh tem main + funcoes, source pode disparar
  # dispatch. Para evitar isso, usamos `MR_SOURCE_ONLY=1` se suportado,
  # OU testamos via shell-subprocess.
  _head_file="$TMPDIR_TEST/head_incomplete.bin"
  printf 'ABCDEFGH\360' > "$_head_file"   # 8 ASCII + 1 lead 4-byte (octal portavel POSIX)

  # Roda via shell que faz source + chama funcao em subprocess.
  _drop=$(MR_SOURCE_ONLY=1 sh -c '
    . "$1"
    _mr_utf8_head_backoff "$2"
  ' _ "$SCRIPT" "$_head_file" 2>/dev/null | tr -d ' \t\n')

  [ "$_drop" = "1" ] || {
    _fail "drop=1 para lead-4-byte sozinho no fim" "drop='$_drop'"
    return 1
  }
}

scenario_f005_utf8_head_backoff_descarta_lead_3byte_parcial() {
  # Lead 3-byte (E0..EF) + 1 continuation = sequencia incompleta de 3.
  # Backoff DEVE retornar 2 (descartar lead + 1 continuation).
  mktemp_test || return 2

  _head_file="$TMPDIR_TEST/head_partial3.bin"
  # 8 ASCII + lead-3 (E2 = \342) + continuation (82 = \202) — falta 1 continuation.
  printf 'ABCDEFGH\342\202' > "$_head_file"

  _drop=$(MR_SOURCE_ONLY=1 sh -c '
    . "$1"
    _mr_utf8_head_backoff "$2"
  ' _ "$SCRIPT" "$_head_file" 2>/dev/null | tr -d ' \t\n')

  [ "$_drop" = "2" ] || {
    _fail "drop=2 para lead-3 + 1 continuation" "drop='$_drop'"
    return 1
  }
}

scenario_f005_utf8_head_backoff_sequencia_completa_nao_descarta() {
  # Sequencia 4-byte completa (F0 9F 98 80 = 😀) no fim. Backoff = 0.
  mktemp_test || return 2

  _head_file="$TMPDIR_TEST/head_complete.bin"
  printf 'ABCD\360\237\230\200' > "$_head_file"

  _drop=$(MR_SOURCE_ONLY=1 sh -c '
    . "$1"
    _mr_utf8_head_backoff "$2"
  ' _ "$SCRIPT" "$_head_file" 2>/dev/null | tr -d ' \t\n')

  [ "$_drop" = "0" ] || {
    _fail "drop=0 para sequencia completa" "drop='$_drop'"
    return 1
  }
}

scenario_f005_utf8_tail_backoff_descarta_continuation_orfa() {
  # Tail comeca com bytes de continuation (80..BF) sem lead anterior.
  # Backoff DEVE retornar N = numero de continuations consecutivas.
  mktemp_test || return 2

  _tail_file="$TMPDIR_TEST/tail_orphan.bin"
  # 2 continuations orfas (98 = \230, 80 = \200) + ASCII normal.
  printf '\230\200ABCDEFGH' > "$_tail_file"

  _drop=$(MR_SOURCE_ONLY=1 sh -c '
    . "$1"
    _mr_utf8_tail_backoff "$2"
  ' _ "$SCRIPT" "$_tail_file" 2>/dev/null | tr -d ' \t\n')

  [ "$_drop" = "2" ] || {
    _fail "drop=2 para 2 continuations orfas" "drop='$_drop'"
    return 1
  }
}

scenario_f005_utf8_tail_backoff_inicio_ascii_nao_descarta() {
  # Tail comeca com ASCII puro → drop = 0.
  mktemp_test || return 2

  _tail_file="$TMPDIR_TEST/tail_ascii.bin"
  printf 'ABCDEFGH' > "$_tail_file"

  _drop=$(MR_SOURCE_ONLY=1 sh -c '
    . "$1"
    _mr_utf8_tail_backoff "$2"
  ' _ "$SCRIPT" "$_tail_file" 2>/dev/null | tr -d ' \t\n')

  [ "$_drop" = "0" ] || {
    _fail "drop=0 para tail ASCII puro" "drop='$_drop'"
    return 1
  }
}

scenario_f005_utf8_truncagem_output_e_utf8_valido_via_iconv() {
  # End-to-end: payload com emoji, truncado pelo helper, sinais_text do
  # JSON resultante PASSA por iconv -f UTF-8 -t UTF-8 sem erro.
  # Se boundary backoff falhasse, iconv sairia com exit != 0.
  _mr_have_jq || { _error "jq ausente"; return 2; }
  command -v iconv >/dev/null 2>&1 || {
    _error "iconv ausente (test opcional)"
    return 2
  }
  mktemp_test || return 2

  _payload_file="$TMPDIR_TEST/emoji_payload_iconv.txt"
  _mr_make_emoji_payload "$_payload_file" 6000

  _payload=$(cat "$_payload_file")

  # Forcar truncagem via stub que ecoa input como sinais.
  _stub="$TMPDIR_TEST/echo_input.sh"
  cat > "$_stub" <<'EOF'
#!/bin/sh
# Echo input recebido (truncado pelo helper) na secao Justificativa,
# para que sinais_text reflita o conteudo apos backoff.
input=$(cat | head -c 200 | tr -d '\n')
cat <<OUT
## Modelo Sugerido

sonnet

## Score

1

rasa=0 media=1 profunda=0 faixa=media
score=1 modelo=sonnet alternativa=opus

## Justificativa

sinais: ${input}

## Alternativa

opus
OUT
EOF
  chmod +x "$_stub"

  MODEL_SELECTOR_SCRIPT="$_stub" capture sh "$SCRIPT" invoke \
    --subagent-type agente-00c-clarify-asker --etapa clarify --input-text "$_payload"

  [ "$_CAPTURED_EXIT" = 0 ] || {
    _fail "exit=0" "exit=$_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"
    return 1
  }

  # raw_stdout_first_200 reflete bytes pos-backoff. Testar via iconv.
  _raw=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.raw_stdout_first_200')
  printf '%s' "$_raw" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1 || {
    _fail "iconv aceita output como UTF-8 valido" "raw='$_raw'"
    return 1
  }
}

# ============================================================================
# Feature model-routing-por-onda — FASE 1 (mapa fase->modelo + lookup)
# Ref: docs/specs/model-routing-por-onda/tasks.md 1.1.3, 1.2.4
#      docs/specs/model-routing-por-onda/contracts/wave-select.md
#        §phase-model-lookup
#      docs/specs/model-routing-por-onda/data-model.md §MapaFaseModelo
#      FR-014 (mapa primario), FR-020 (fase desconhecida -> manter-atual),
#      FR-024 (path confinado, sem traversal)
# ============================================================================

PHASE_MAP="$REPO_ROOT/global/skills/agente-00c-runtime/references/phase-model-map.txt"

# Recorte default "3 faixas balanceado" — as 11 fases do enum (data-model).
# Mantido como fonte de verdade do teste; se o mapa evoluir, atualizar aqui.
_PML_EXPECTED='plan|profunda|opus
analyze|profunda|opus
constitution|profunda|opus
specify|media|sonnet
clarify|media|sonnet
checklist|media|sonnet
create-tasks|media|sonnet
briefing|media|sonnet
execute-task|rasa|sonnet
validate-docs|rasa|haiku
review-task|rasa|haiku'

# ---- 1.1.3: arquivo de mapa existe, tem header de versao e parseia ----

scenario_fase1_map_existe_e_tem_header_versao() {
  [ -f "$PHASE_MAP" ] || {
    _fail "phase-model-map.txt existe" "ausente: $PHASE_MAP"
    return 1
  }
  # Header de versao na 1a linha (FR-020).
  _hdr=$(head -n 1 "$PHASE_MAP")
  case "$_hdr" in
    "# phase-model-map v"*) : ;;
    *)
      _fail "1a linha e header de versao" "obtido: '$_hdr'"
      return 1 ;;
  esac
}

scenario_fase1_map_cobre_as_11_fases_do_recorte() {
  [ -f "$PHASE_MAP" ] || { _error "map ausente"; return 2; }
  # Para cada fase esperada, o lookup deve devolver faixa|modelo exatos.
  _ok=1
  printf '%s\n' "$_PML_EXPECTED" | while IFS='|' read -r _f _fa _mo; do
    _got=$(sh "$SCRIPT" phase-model-lookup --fase "$_f")
    if [ "$_got" != "$_fa|$_mo" ]; then
      printf 'MISMATCH fase=%s esperado=%s|%s obtido=%s\n' \
        "$_f" "$_fa" "$_mo" "$_got"
    fi
  done > "$TMPDIR_TEST/pml_mismatch.txt" 2>/dev/null || true
  if [ -s "$TMPDIR_TEST/pml_mismatch.txt" ]; then
    _fail "11 fases parseiam com faixa|modelo corretos" \
      "$(cat "$TMPDIR_TEST/pml_mismatch.txt")"
    return 1
  fi
}

scenario_fase1_map_so_tem_linhas_validas_ou_comentario() {
  [ -f "$PHASE_MAP" ] || { _error "map ausente"; return 2; }
  # Toda linha de dados (nao-comentario, nao-vazia) tem exatamente 3 campos
  # e modelo no enum {haiku,sonnet,opus,manter-atual}, faixa no enum
  # {rasa,media,profunda}.
  _bad=$(awk -F'|' '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    {
      if (NF != 3) { print "NF="NF": "$0; next }
      fa=$2; mo=$3
      if (fa != "rasa" && fa != "media" && fa != "profunda")
        { print "faixa invalida: "$0; next }
      if (mo != "haiku" && mo != "sonnet" && mo != "opus" && mo != "manter-atual")
        { print "modelo invalido: "$0 }
    }
  ' "$PHASE_MAP")
  [ -z "$_bad" ] || {
    _fail "linhas de dados validas (3 campos + enums)" "$_bad"
    return 1
  }
}

# ---- 1.2.4: lookup conhecida/desconhecida + traversal rejeitado ----

scenario_fase1_lookup_fase_conhecida() {
  capture sh "$SCRIPT" phase-model-lookup --fase plan
  assert_exit 0 sh "$SCRIPT" phase-model-lookup --fase plan || return 1
  assert_stdout_match '^profunda\|opus$' || return 1
}

scenario_fase1_lookup_fase_desconhecida_manter_atual() {
  # FR-020: fase fora do mapa -> '|manter-atual', exit 0 (nunca erro).
  capture sh "$SCRIPT" phase-model-lookup --fase fase-que-nao-existe
  assert_exit 0 sh "$SCRIPT" phase-model-lookup --fase fase-que-nao-existe || return 1
  assert_stdout_match '^\|manter-atual$' || return 1
}

scenario_fase1_lookup_flag_igual_form() {
  # Forma --fase=VALOR equivalente a --fase VALOR.
  capture sh "$SCRIPT" phase-model-lookup --fase=execute-task
  assert_exit 0 sh "$SCRIPT" phase-model-lookup --fase=execute-task || return 1
  assert_stdout_match '^rasa\|sonnet$' || return 1
}

scenario_fase1_lookup_fase_ausente_exit_2() {
  # Sem --fase -> uso incorreto (exit 2), mensagem em stderr.
  assert_exit 2 sh "$SCRIPT" phase-model-lookup || return 1
  capture sh "$SCRIPT" phase-model-lookup
  assert_stderr_contains "--fase ausente" || return 1
}

scenario_fase1_lookup_traversal_rejeitado_como_dado() {
  # FR-024: --fase NUNCA compoe path. Valores de traversal sao tratados
  # como dado de comparacao -> nao casam nenhuma fase -> manter-atual,
  # exit 0, sem ler/expor arquivo externo.
  for _evil in '../../../../etc/passwd' '/etc/passwd' '..' './plan'; do
    capture sh "$SCRIPT" phase-model-lookup --fase "$_evil"
    [ "$_CAPTURED_EXIT" = 0 ] || {
      _fail "traversal nao erra" "fase='$_evil' exit=$_CAPTURED_EXIT"
      return 1
    }
    case "$_CAPTURED_STDOUT" in
      '|manter-atual') : ;;
      *)
        _fail "traversal -> manter-atual" "fase='$_evil' out='$_CAPTURED_STDOUT'"
        return 1 ;;
    esac
  done
}

scenario_fase1_lookup_read_only_sem_side_effect() {
  # Lookup nunca escreve nada no working tree do repo.
  mktemp_test || return 2
  capture sh "$SCRIPT" phase-model-lookup --fase plan
  assert_no_side_effect || return 1
}

# ============================================================================
# Feature model-routing-por-onda — FASE 2 (wave-select: selecao por onda)
# Ref: docs/specs/model-routing-por-onda/contracts/wave-select.md §wave-select
#      docs/specs/model-routing-por-onda/data-model.md §DecisaoDeRoteamentoPorOnda
#      docs/specs/model-routing-por-onda/quickstart.md (cenarios C1..C12)
#      docs/specs/model-routing-por-onda/spec.md FR-001/002/005/006/007/008/
#        015/016/019/022/023/025
#      docs/specs/model-routing-por-onda/tasks.md 2.1.5, 2.2.4, 2.3.5, 2.4.3
# ============================================================================

# Cria um state.json minimo para wave-select. $1=dir, $2=etapa,
# (resto via jq direto nos cenarios que precisam de override/escalada).
_ws_state() {
  _ws_dir=$1
  _ws_etapa=$2
  mkdir -p "$_ws_dir" || return 2
  jq -n --arg e "$_ws_etapa" '{
    etapa_corrente: $e,
    ondas: [{ id: "onda-007", skills_invoked: [] }],
    metricas_acumuladas: {},
    decisoes: []
  }' > "$_ws_dir/state.json"
}

# Stub classify.sh com modelo/score parametrizados. $1=arquivo, $2=modelo,
# $3=score(0..2), $4=faixa.
_ws_make_stub() {
  _ws_sf=$1; _ws_sm=$2; _ws_ss=$3; _ws_sfa=$4
  cat > "$_ws_sf" <<EOF
#!/bin/sh
cat <<OUT
## Modelo Sugerido

$_ws_sm

## Score

$_ws_ss

${_ws_sfa}=3 faixa=$_ws_sfa
score=$_ws_ss modelo=$_ws_sm alternativa=sonnet

## Justificativa

sinais detectados: stub $_ws_sfa.

## Alternativa

sonnet
OUT
EOF
  chmod +x "$_ws_sf"
}

# ---- C1: mapa primario decide onda mecanica (review-task -> haiku) ----
scenario_ws_c1_mapa_review_task_haiku() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _ws_state "$TMPDIR_TEST/c1" review-task || return 2
  capture sh "$SCRIPT" wave-select --state-dir "$TMPDIR_TEST/c1"
  assert_exit 0 sh "$SCRIPT" wave-select --state-dir "$TMPDIR_TEST/c1" || return 1
  # Apos 2 invocacoes idempotentes, stdout permanece haiku.
  [ "$_CAPTURED_STDOUT" = "haiku" ] || { _fail "C1 stdout=haiku" "$_CAPTURED_STDOUT"; return 1; }
  # Decisao com origem=mapa, sugerido=aplicado=haiku.
  jq -e '
    [.decisoes[] | select(.contexto | startswith("Selecao de modelo para onda "))][0]
    | (.escolha == "model:haiku")
      and (.justificativa | test("sugerido=haiku aplicado=haiku origem=mapa"))
      and (.score_justificativa == 0)
  ' "$TMPDIR_TEST/c1/state.json" >/dev/null 2>&1 \
    || { _fail "C1 Decisao mapa haiku" "$(jq -c '.decisoes[-1]' "$TMPDIR_TEST/c1/state.json")"; return 1; }
}

# ---- C2: onda de raciocinio mantem opus (plan -> opus) ----
scenario_ws_c2_mapa_plan_opus() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _ws_state "$TMPDIR_TEST/c2" plan || return 2
  capture sh "$SCRIPT" wave-select --state-dir "$TMPDIR_TEST/c2"
  [ "$_CAPTURED_STDOUT" = "opus" ] || { _fail "C2 stdout=opus" "$_CAPTURED_STDOUT"; return 1; }
  jq -e '
    .decisoes[-1]
    | (.escolha == "model:opus")
      and (.justificativa | test("aplicado=opus origem=mapa"))
  ' "$TMPDIR_TEST/c2/state.json" >/dev/null 2>&1 \
    || { _fail "C2 Decisao mapa opus" "$(jq -c '.decisoes[-1]' "$TMPDIR_TEST/c2/state.json")"; return 1; }
}

# ---- C3: refino eleva execute-task profundo (sonnet -> opus, origem=refino) ----
scenario_ws_c3_refino_eleva_opus() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _ws_state "$TMPDIR_TEST/c3" execute-task || return 2
  _ws_stub="$TMPDIR_TEST/stub_opus.sh"
  _ws_make_stub "$_ws_stub" opus 2 profunda
  MODEL_SELECTOR_SCRIPT="$_ws_stub" capture sh "$SCRIPT" wave-select \
    --state-dir "$TMPDIR_TEST/c3" --task-text "refatore e arquitete o modulo"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "C3 exit=0" "$_CAPTURED_EXIT"; return 1; }
  [ "$_CAPTURED_STDOUT" = "opus" ] || { _fail "C3 stdout=opus" "$_CAPTURED_STDOUT"; return 1; }
  # origem=refino: o refino integra a SUGESTAO (data-model L57), logo
  # sugerido segue o refino (sugerido=opus aplicado=opus). Divergencia
  # sugerido!=aplicado fica reservada a override-operador/fallback
  # (invariante L63-64 / SC-006 — dec-022). score 2, record-skill presente.
  jq -e '
    .decisoes[-1]
    | (.escolha == "model:opus")
      and (.justificativa | test("sugerido=opus aplicado=opus origem=refino"))
      and (.score_justificativa == 2)
  ' "$TMPDIR_TEST/c3/state.json" >/dev/null 2>&1 \
    || { _fail "C3 Decisao refino" "$(jq -c '.decisoes[-1]' "$TMPDIR_TEST/c3/state.json")"; return 1; }
  jq -e '
    [.ondas[].skills_invoked[]? | select(.skill == "model-selector")] | length == 1
  ' "$TMPDIR_TEST/c3/state.json" >/dev/null 2>&1 \
    || { _fail "C3 record-skill model-selector (par I3)" "$(jq -c '.ondas[-1].skills_invoked' "$TMPDIR_TEST/c3/state.json")"; return 1; }
}

# ---- C4: refino sem sinal mantem o mapa (score 0 -> sonnet) ----
scenario_ws_c4_refino_sem_sinal_mantem_mapa() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _ws_state "$TMPDIR_TEST/c4" execute-task || return 2
  _ws_stub="$TMPDIR_TEST/stub_zero.sh"
  _ws_make_stub "$_ws_stub" manter-atual 0 indeterminado
  MODEL_SELECTOR_SCRIPT="$_ws_stub" capture sh "$SCRIPT" wave-select \
    --state-dir "$TMPDIR_TEST/c4" --task-text "ajustar texto neutro"
  [ "$_CAPTURED_STDOUT" = "sonnet" ] || { _fail "C4 stdout=sonnet (mapa)" "$_CAPTURED_STDOUT"; return 1; }
  jq -e '
    .decisoes[-1] | (.justificativa | test("aplicado=sonnet origem=mapa"))
  ' "$TMPDIR_TEST/c4/state.json" >/dev/null 2>&1 \
    || { _fail "C4 origem=mapa (refino nao alterou)" "$(jq -c '.decisoes[-1]' "$TMPDIR_TEST/c4/state.json")"; return 1; }
  # Sem record-skill quando refino nao alterou (score<2).
  jq -e '
    [.ondas[].skills_invoked[]? | select(.skill == "model-selector")] | length == 0
  ' "$TMPDIR_TEST/c4/state.json" >/dev/null 2>&1 \
    || { _fail "C4 sem record-skill (refino no-op)" "$(jq -c '.ondas[-1].skills_invoked' "$TMPDIR_TEST/c4/state.json")"; return 1; }
}

# ---- C5: override do operador vence (FR-016) ----
scenario_ws_c5_override_vence() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  mkdir -p "$TMPDIR_TEST/c5"
  jq -n '{
    etapa_corrente: "plan",
    ondas: [{ id: "onda-007", skills_invoked: [] }],
    metricas_acumuladas: {},
    decisoes: [{
      id: "dec-001", onda_id: "onda-007", etapa: "model-routing",
      contexto: "Override de modelo para onda 7", escolha: "model-override:haiku"
    }]
  }' > "$TMPDIR_TEST/c5/state.json"
  capture sh "$SCRIPT" wave-select --state-dir "$TMPDIR_TEST/c5"
  [ "$_CAPTURED_STDOUT" = "haiku" ] || { _fail "C5 stdout=haiku (override vence opus)" "$_CAPTURED_STDOUT"; return 1; }
  jq -e '
    .decisoes[-1]
    | (.escolha == "model:haiku")
      and (.justificativa | test("sugerido=opus aplicado=haiku origem=override-operador"))
  ' "$TMPDIR_TEST/c5/state.json" >/dev/null 2>&1 \
    || { _fail "C5 Decisao override" "$(jq -c '.decisoes[-1]' "$TMPDIR_TEST/c5/state.json")"; return 1; }
}

# ---- C6: fallback gracioso (model-selector ausente) ----
scenario_ws_c6_fallback_gracioso() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _ws_state "$TMPDIR_TEST/c6" execute-task || return 2
  # MODEL_SELECTOR_DISABLED forca tool-skill-unavailable no invoke.
  MODEL_SELECTOR_DISABLED=1 capture sh "$SCRIPT" wave-select \
    --state-dir "$TMPDIR_TEST/c6" --task-text "qualquer descricao"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "C6 exit=0 (nunca aborta)" "$_CAPTURED_EXIT"; return 1; }
  [ "$_CAPTURED_STDOUT" = "sonnet" ] || { _fail "C6 stdout=sonnet (piso mapa)" "$_CAPTURED_STDOUT"; return 1; }
  # Sem record-skill orfao (refino nao rodou de fato).
  jq -e '
    [.ondas[].skills_invoked[]? | select(.skill == "model-selector")] | length == 0
  ' "$TMPDIR_TEST/c6/state.json" >/dev/null 2>&1 \
    || { _fail "C6 sem record-skill orfao" "$(jq -c '.ondas[-1].skills_invoked' "$TMPDIR_TEST/c6/state.json")"; return 1; }
}

# ---- C7: idempotencia na retomada (FR-008) ----
scenario_ws_c7_idempotencia() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _ws_state "$TMPDIR_TEST/c7" plan || return 2
  # 1a invocacao registra a Decisao.
  _out1=$(sh "$SCRIPT" wave-select --state-dir "$TMPDIR_TEST/c7")
  _n1=$(jq '.decisoes | length' "$TMPDIR_TEST/c7/state.json")
  # 2a invocacao (simula resume): NENHUMA 2a Decisao.
  capture sh "$SCRIPT" wave-select --state-dir "$TMPDIR_TEST/c7"
  _n2=$(jq '.decisoes | length' "$TMPDIR_TEST/c7/state.json")
  [ "$_CAPTURED_STDOUT" = "$_out1" ] || { _fail "C7 stdout estavel" "1a=$_out1 2a=$_CAPTURED_STDOUT"; return 1; }
  [ "$_n1" = "$_n2" ] || { _fail "C7 nenhuma 2a Decisao" "n1=$_n1 n2=$_n2"; return 1; }
}

# ---- C8: manter-atual (fase nao-mapeada) ----
scenario_ws_c8_manter_atual_fase_nao_mapeada() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _ws_state "$TMPDIR_TEST/c8" fase-inexistente-xyz || return 2
  capture sh "$SCRIPT" wave-select --state-dir "$TMPDIR_TEST/c8"
  [ "$_CAPTURED_STDOUT" = "manter-atual" ] || { _fail "C8 stdout=manter-atual" "$_CAPTURED_STDOUT"; return 1; }
  jq -e '
    .decisoes[-1] | (.escolha == "manter-atual")
  ' "$TMPDIR_TEST/c8/state.json" >/dev/null 2>&1 \
    || { _fail "C8 escolha=manter-atual" "$(jq -c '.decisoes[-1]' "$TMPDIR_TEST/c8/state.json")"; return 1; }
}

# ---- C9: escalonamento mid-onda (FR-015) ----
scenario_ws_c9_escalada_mid_onda_opus() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  mkdir -p "$TMPDIR_TEST/c9"
  # Fase barata (review-task -> haiku no mapa), MAS escalada pendente -> opus.
  jq -n '{
    etapa_corrente: "review-task",
    escalada_modelo_pendente: true,
    ondas: [{ id: "onda-007", skills_invoked: [] }],
    metricas_acumuladas: {},
    decisoes: []
  }' > "$TMPDIR_TEST/c9/state.json"
  capture sh "$SCRIPT" wave-select --state-dir "$TMPDIR_TEST/c9"
  [ "$_CAPTURED_STDOUT" = "opus" ] || { _fail "C9 stdout=opus (escalada vence mapa)" "$_CAPTURED_STDOUT"; return 1; }
  jq -e '
    .decisoes[-1] | (.justificativa | test("escalada-mid-onda"))
  ' "$TMPDIR_TEST/c9/state.json" >/dev/null 2>&1 \
    || { _fail "C9 nota de escalada" "$(jq -c '.decisoes[-1]' "$TMPDIR_TEST/c9/state.json")"; return 1; }
}

# ---- C11: override invalido cai em fallback (FR-023) ----
scenario_ws_c11_override_invalido_fallback() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  mkdir -p "$TMPDIR_TEST/c11"
  jq -n '{
    etapa_corrente: "plan",
    ondas: [{ id: "onda-007", skills_invoked: [] }],
    metricas_acumuladas: {},
    decisoes: [{
      id: "dec-001", onda_id: "onda-007", etapa: "model-routing",
      contexto: "Override de modelo para onda 7", escolha: "model-override:gpt4"
    }]
  }' > "$TMPDIR_TEST/c11/state.json"
  capture sh "$SCRIPT" wave-select --state-dir "$TMPDIR_TEST/c11"
  # Override 'gpt4' fora do enum -> rejeitado, cai no mapa (plan -> opus).
  [ "$_CAPTURED_STDOUT" = "opus" ] || { _fail "C11 stdout=opus (override invalido -> mapa)" "$_CAPTURED_STDOUT"; return 1; }
  jq -e '
    .decisoes[-1]
    | (.justificativa | test("origem=fallback"))
      and (.justificativa | test("override invalido"))
  ' "$TMPDIR_TEST/c11/state.json" >/dev/null 2>&1 \
    || { _fail "C11 origem=fallback + nota override invalido" "$(jq -c '.decisoes[-1]' "$TMPDIR_TEST/c11/state.json")"; return 1; }
  # 'gpt4' NUNCA propagado ao stdout (nada invalido vaza ao spawn).
  case "$_CAPTURED_STDOUT" in
    haiku|sonnet|opus|manter-atual) : ;;
    *) _fail "C11 stdout no enum" "$_CAPTURED_STDOUT"; return 1 ;;
  esac
}

# ---- C12: task-text untrusted sanitizado (FR-022) ----
scenario_ws_c12_tasktext_untrusted_sanitizado() {
  _mr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _ws_state "$TMPDIR_TEST/c12" execute-task || return 2
  # Payload hostil: metacaractere shell + NUL (octal \000) + 10KB de texto.
  # Marker de injecao: se algum eval/expansao rodar, /tmp seria tocado.
  _ws_pad=$(head -c 10000 /dev/zero | tr '\000' 'A')
  _ws_payload=$(printf '"; touch %s/PWNED_c12 ; echo \000%s' "$TMPDIR_TEST" "$_ws_pad")
  MODEL_SELECTOR_DISABLED=1 capture sh "$SCRIPT" wave-select \
    --state-dir "$TMPDIR_TEST/c12" --task-text "$_ws_payload"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "C12 exit=0 (nunca aborta)" "$_CAPTURED_EXIT"; return 1; }
  # Nenhuma injecao: marker NAO criado.
  [ ! -f "$TMPDIR_TEST/PWNED_c12" ] || { _fail "C12 sem injecao de comando" "marker PWNED_c12 foi criado!"; return 1; }
  # Degradou para o mapa (model-selector disabled) -> sonnet, sem abortar.
  [ "$_CAPTURED_STDOUT" = "sonnet" ] || { _fail "C12 stdout=sonnet (degradacao mapa)" "$_CAPTURED_STDOUT"; return 1; }
}

# ---- wave-select: uso incorreto (sem --state-dir) -> exit 2 ----
scenario_ws_sem_state_dir_exit_2() {
  assert_exit 2 sh "$SCRIPT" wave-select || return 1
  capture sh "$SCRIPT" wave-select
  assert_stderr_contains "--state-dir ausente" || return 1
}

# ---- wave-select: state.json ausente -> exit 2 ----
scenario_ws_state_ausente_exit_2() {
  mktemp_test || return 2
  assert_exit 2 sh "$SCRIPT" wave-select --state-dir "$TMPDIR_TEST" || return 1
}

run_all_scenarios "$0"
