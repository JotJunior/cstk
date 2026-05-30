#!/bin/sh
# test_state-decisions-reconcile.sh — cobre
# global/skills/agente-00c-runtime/scripts/state-decisions-reconcile.sh.
#
# Feature: agente-00c-model-routing
# Ref: docs/specs/agente-00c-model-routing/tasks.md F4.4
#      global/agents/agente-00c-feature-orchestrator.md §Invariante I3 + §Protocolo de falha
#      dec-009 finding F-004 (low) — two-step half-record
#
# Cobertura:
#   F4.4.2 (helper read-only de deteccao):
#     - dispatch sem args -> exit 2 + HELP
#     - subcomando desconhecido -> exit 2
#     - check --state-dir ausente -> exit 2
#     - check state.json ausente -> exit 2
#     - check estado balanceado (N_DEC == N_REC) -> exit 0 + stdout vazio
#     - check half-record (Decisao sem record-skill) -> exit 1 + TSV
#     - check com 0 Decisoes "Selecao de modelo" -> exit 0 (paridade trivial)
#     - check INV-4 read-only (sha256 state.json estavel antes/depois)
#     - check com .decisoes ausente (state legado) -> exit 0
#
#   F4.4.3 (cenario negativo orfo cobrindo TSV):
#     - state.json com 1 Decisao orfa + 1 par balanceado -> exit 1 + TSV
#       contendo o dec-id orfo (e nao o balanceado)
#     - validar formato TSV: 3 colunas <dec-id>\t<wave-id>\t<subagent-type>
#
#   schema-en-migration (reader-fallback EN-com-pt):
#     - fixtures primarias em chaves EN (decisions/waves/context/...)
#     - half-record EN-nativo -> exit 1 + TSV (reader EN)
#     - >=1 fixture pt-BR legada (_sdr_fixture_half_record) provando que o
#       fallback (.en // .pt) ainda detecta orfas em states antigos

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-decisions-reconcile.sh"

_sdr_have_jq() {
  command -v jq >/dev/null 2>&1
}

# Fixture: state.json balanceado (paridade 2-para-2) — chaves EN.
_sdr_fixture_balanced() {
  cat > "$1/state.json" <<'JSON'
{
  "schema_version": "1.0.0",
  "waves": [
    {
      "id": "onda-001",
      "skills_invoked": [
        {"skill": "model-selector", "decision_id": "dec-001", "timestamp": "2026-05-22T10:00:00Z"},
        {"skill": "model-selector", "decision_id": "dec-002", "timestamp": "2026-05-22T10:05:00Z"}
      ]
    }
  ],
  "decisions": [
    {"id": "dec-001", "wave_id": "onda-001",
     "context": "Selecao de modelo para subagente feature-00c-clarify-asker"},
    {"id": "dec-002", "wave_id": "onda-001",
     "context": "Selecao de modelo para subagente feature-00c-clarify-answerer"}
  ]
}
JSON
}

# Fixture: state.json com 1 orfa (dec-002 sem record-skill).
# BACK-COMPAT (schema-en-migration §6): mantida em chaves pt-BR de proposito
# para provar que o reader-fallback (.en // .pt) ainda detecta orfas em states
# legados (decisoes/ondas/onda_id/contexto/decisao_id).
_sdr_fixture_half_record() {
  cat > "$1/state.json" <<'JSON'
{
  "schema_version": "1.0.0",
  "ondas": [
    {
      "id": "onda-001",
      "skills_invoked": [
        {"skill": "model-selector", "decisao_id": "dec-001", "timestamp": "2026-05-22T10:00:00Z"}
      ]
    }
  ],
  "decisoes": [
    {"id": "dec-001", "onda_id": "onda-001",
     "contexto": "Selecao de modelo para subagente feature-00c-clarify-asker"},
    {"id": "dec-002", "onda_id": "onda-001",
     "contexto": "Selecao de modelo para subagente feature-00c-clarify-answerer"}
  ]
}
JSON
}

# Fixture: state.json com 1 orfa (dec-002 sem record-skill) — chaves EN.
# Espelho EN do fixture pt-BR para provar paridade do reader EN-nativo.
_sdr_fixture_half_record_en() {
  cat > "$1/state.json" <<'JSON'
{
  "schema_version": "1.0.0",
  "waves": [
    {
      "id": "onda-001",
      "skills_invoked": [
        {"skill": "model-selector", "decision_id": "dec-001", "timestamp": "2026-05-22T10:00:00Z"}
      ]
    }
  ],
  "decisions": [
    {"id": "dec-001", "wave_id": "onda-001",
     "context": "Selecao de modelo para subagente feature-00c-clarify-asker"},
    {"id": "dec-002", "wave_id": "onda-001",
     "context": "Selecao de modelo para subagente feature-00c-clarify-answerer"}
  ]
}
JSON
}

# Fixture: state.json sem Decisoes "Selecao de modelo" (paridade trivial 0-0).
_sdr_fixture_no_model_decisions() {
  cat > "$1/state.json" <<'JSON'
{
  "schema_version": "1.0.0",
  "waves": [
    {"id": "onda-001", "skills_invoked": []}
  ],
  "decisions": [
    {"id": "dec-001", "wave_id": "onda-001",
     "context": "Inicio de execucao"},
    {"id": "dec-002", "wave_id": "onda-001",
     "context": "Gate validate-documentation reportou: tudo ok"}
  ]
}
JSON
}

# Fixture: state.json sem campo .decisions (nem .decisoes) — array ausente.
_sdr_fixture_legacy_no_decisoes() {
  cat > "$1/state.json" <<'JSON'
{
  "schema_version": "1.0.0",
  "waves": [{"id": "onda-001", "skills_invoked": []}]
}
JSON
}

# ==== F4.4.2: dispatch / usage ====

scenario_sdr_sem_args_exit_2() {
  capture sh "$SCRIPT"
  assert_exit 2 sh "$SCRIPT" || return 1
  assert_stderr_contains "USO:" || return 1
  assert_stderr_contains "check" || return 1
}

scenario_sdr_subcomando_desconhecido_exit_2() {
  capture sh "$SCRIPT" bogus-subcmd
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit=2" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "subcomando desconhecido" || return 1
}

scenario_sdr_check_sem_state_dir_exit_2() {
  capture sh "$SCRIPT" check
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit=2" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "--state-dir ausente" || return 1
}

scenario_sdr_check_state_json_ausente_exit_2() {
  mktemp_test || return 2
  capture sh "$SCRIPT" check --state-dir "$TMPDIR_TEST"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit=2" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "state.json ausente" || return 1
}

scenario_sdr_check_help_flag() {
  capture sh "$SCRIPT" --help
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit=2 (--help)" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "USO:" || return 1
}

# ==== F4.4.2: estado balanceado -> exit 0 ====

scenario_sdr_check_balanced_exit_0() {
  _sdr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _sdr_fixture_balanced "$TMPDIR_TEST"

  capture sh "$SCRIPT" check --state-dir "$TMPDIR_TEST"
  [ "$_CAPTURED_EXIT" = 0 ] || {
    _fail "exit=0 (balanced)" "obtido $_CAPTURED_EXIT (stderr=$_CAPTURED_STDERR)"
    return 1
  }
  # stdout deve ser vazio (nenhuma orfa).
  _stdout_trim=$(printf '%s' "$_CAPTURED_STDOUT" | tr -d '\n')
  [ -z "$_stdout_trim" ] || {
    _fail "stdout vazio (balanced)" "obtido '$_stdout_trim'"
    return 1
  }
}

# ==== F4.4.3: half-record -> exit 1 + TSV ====

scenario_sdr_check_half_record_exit_1_e_tsv() {
  _sdr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _sdr_fixture_half_record "$TMPDIR_TEST"

  capture sh "$SCRIPT" check --state-dir "$TMPDIR_TEST"
  [ "$_CAPTURED_EXIT" = 1 ] || {
    _fail "exit=1 (half-record)" "obtido $_CAPTURED_EXIT (stdout=$_CAPTURED_STDOUT stderr=$_CAPTURED_STDERR)"
    return 1
  }
  # TSV deve conter dec-002 (orfa), onda-001 e o subagent-type.
  printf '%s' "$_CAPTURED_STDOUT" | grep -q "^dec-002	onda-001	feature-00c-clarify-answerer$" || {
    _fail "TSV orfa" "stdout='$_CAPTURED_STDOUT'"
    return 1
  }
  # dec-001 (balanceada) NAO deve aparecer.
  if printf '%s' "$_CAPTURED_STDOUT" | grep -q "^dec-001	"; then
    _fail "dec-001 nao deve aparecer (balanceada)" "stdout='$_CAPTURED_STDOUT'"
    return 1
  fi
  # Formato TSV: 3 campos separados por TAB, 1 linha total.
  _ntabs=$(printf '%s' "$_CAPTURED_STDOUT" | head -1 | awk -F'\t' '{print NF}')
  [ "$_ntabs" = "3" ] || {
    _fail "TSV com 3 colunas" "NF=$_ntabs em '$_CAPTURED_STDOUT'"
    return 1
  }
}

# ==== schema-en-migration: half-record EN-nativo -> exit 1 + TSV ====
#
# Espelho EN do cenario pt-BR acima. Prova que o reader EN-nativo
# (.decisions/.waves/.context/.decision_id/.wave_id) detecta a mesma orfa.
# O cenario pt-BR (scenario_sdr_check_half_record_exit_1_e_tsv) permanece
# exercitando o fallback (.en // .pt) sobre o fixture legado.

scenario_sdr_check_half_record_en_exit_1_e_tsv() {
  _sdr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _sdr_fixture_half_record_en "$TMPDIR_TEST"

  capture sh "$SCRIPT" check --state-dir "$TMPDIR_TEST"
  [ "$_CAPTURED_EXIT" = 1 ] || {
    _fail "exit=1 (half-record EN)" "obtido $_CAPTURED_EXIT (stdout=$_CAPTURED_STDOUT stderr=$_CAPTURED_STDERR)"
    return 1
  }
  printf '%s' "$_CAPTURED_STDOUT" | grep -q "^dec-002	onda-001	feature-00c-clarify-answerer$" || {
    _fail "TSV orfa (EN)" "stdout='$_CAPTURED_STDOUT'"
    return 1
  }
  if printf '%s' "$_CAPTURED_STDOUT" | grep -q "^dec-001	"; then
    _fail "dec-001 nao deve aparecer (balanceada, EN)" "stdout='$_CAPTURED_STDOUT'"
    return 1
  fi
}

# ==== Paridade trivial: 0 Decisoes "Selecao de modelo" -> exit 0 ====

scenario_sdr_check_zero_model_decisions_exit_0() {
  _sdr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _sdr_fixture_no_model_decisions "$TMPDIR_TEST"

  capture sh "$SCRIPT" check --state-dir "$TMPDIR_TEST"
  [ "$_CAPTURED_EXIT" = 0 ] || {
    _fail "exit=0 (zero model decisions)" "obtido $_CAPTURED_EXIT"
    return 1
  }
}

# ==== Legado: state.json sem .decisoes -> exit 0 ====

scenario_sdr_check_legacy_no_decisoes_exit_0() {
  _sdr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _sdr_fixture_legacy_no_decisoes "$TMPDIR_TEST"

  capture sh "$SCRIPT" check --state-dir "$TMPDIR_TEST"
  [ "$_CAPTURED_EXIT" = 0 ] || {
    _fail "exit=0 (legacy state sem .decisoes)" "obtido $_CAPTURED_EXIT (stderr=$_CAPTURED_STDERR)"
    return 1
  }
}

# ==== INV-4: read-only — sha256 do state.json estavel antes/depois ====

scenario_sdr_check_read_only_inv4() {
  _sdr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _sdr_fixture_half_record "$TMPDIR_TEST"

  _sha_before=$(shasum -a 256 "$TMPDIR_TEST/state.json" | awk '{print $1}')

  # 3 invocacoes consecutivas (varia entre exit 0 e exit 1, mas read-only
  # NUNCA muda state.json).
  sh "$SCRIPT" check --state-dir "$TMPDIR_TEST" >/dev/null 2>&1 || :
  sh "$SCRIPT" check --state-dir "$TMPDIR_TEST" >/dev/null 2>&1 || :
  sh "$SCRIPT" check --state-dir "$TMPDIR_TEST" >/dev/null 2>&1 || :

  _sha_after=$(shasum -a 256 "$TMPDIR_TEST/state.json" | awk '{print $1}')

  [ "$_sha_before" = "$_sha_after" ] || {
    _fail "INV-4 read-only — sha256 estavel" \
          "before=$_sha_before after=$_sha_after"
    return 1
  }
}

# ==== FASE 6.2.3 (feature model-routing-por-onda): reuso FR-013 ====
#
# Confirma que o reconciliador EXISTENTE (sem extensao) coexiste com a
# nova geracao DecisaoDeRoteamentoPorOnda. As Decisoes por-onda usam o
# lead "Selecao de modelo para onda <N>" (fora do filtro do detector, que
# casa apenas o lead legado "...subagente <T>"). O detector NAO produz
# falso-positivo sobre a geracao por-onda; um half-record LEGADO no mesmo
# state continua sendo detectado. Resultado p/ a geracao por-onda:
# half-records pendentes == 0 (FR-013 — reuso do mesmo mecanismo).

# Fixture: 2 Decisoes por-onda (1 refino com record-skill pareado,
# 1 mapa sem record-skill — o que e CORRETO: mapa puro nao invoca
# model-selector) + 1 half-record LEGADO (orfa subagente).
_sdr_fixture_onda_plus_legacy_orphan() {
  cat > "$1/state.json" <<'JSON'
{
  "schema_version": "1.0.0",
  "waves": [
    {
      "id": "onda-001",
      "skills_invoked": [
        {"skill": "model-selector", "decision_id": "dec-w-refino", "timestamp": "2026-05-24T10:00:00Z"}
      ]
    }
  ],
  "decisions": [
    {"id": "dec-w-mapa", "wave_id": "onda-002", "stage": "model-routing",
     "context": "Selecao de modelo para onda 2 (fase plan)",
     "choice": "model:opus",
     "rationale": "sugerido=opus aplicado=opus origem=mapa | mapa primario"},
    {"id": "dec-w-refino", "wave_id": "onda-003", "stage": "model-routing",
     "context": "Selecao de modelo para onda 3 (fase execute-task)",
     "choice": "model:sonnet",
     "rationale": "sugerido=sonnet aplicado=sonnet origem=refino | refino: sinais"},
    {"id": "dec-legado-orfa", "wave_id": "onda-001",
     "context": "Selecao de modelo para subagente feature-00c-clarify-answerer"}
  ]
}
JSON
}

scenario_sdr_check_onda_decisions_nao_falso_positivo() {
  _sdr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _sdr_fixture_onda_plus_legacy_orphan "$TMPDIR_TEST"

  capture sh "$SCRIPT" check --state-dir "$TMPDIR_TEST"
  # Ha 1 half-record LEGADO (dec-legado-orfa) -> exit 1.
  [ "$_CAPTURED_EXIT" = 1 ] || {
    _fail "exit=1 (1 orfa legada)" "obtido $_CAPTURED_EXIT (stdout=$_CAPTURED_STDOUT)"
    return 1
  }
  # A orfa detectada e SOMENTE a legada.
  printf '%s' "$_CAPTURED_STDOUT" | grep -q "^dec-legado-orfa	onda-001	feature-00c-clarify-answerer$" || {
    _fail "TSV deve conter a orfa legada" "stdout='$_CAPTURED_STDOUT'"
    return 1
  }
  # As Decisoes por-onda NAO devem aparecer como orfas (fora do filtro do
  # detector -> half-records pendentes para a geracao por-onda == 0).
  if printf '%s' "$_CAPTURED_STDOUT" | grep -q "dec-w-mapa\|dec-w-refino"; then
    _fail "Decisoes por-onda NAO devem ser flagged" "stdout='$_CAPTURED_STDOUT'"
    return 1
  fi
  # Exatamente 1 linha de orfa.
  _nlines=$(printf '%s\n' "$_CAPTURED_STDOUT" | grep -c '	' || :)
  [ "$_nlines" = "1" ] || { _fail "exatamente 1 orfa" "obtido $_nlines linhas"; return 1; }
}

# Geracao por-onda PURA (sem legado): half-records pendentes == 0 (exit 0).
_sdr_fixture_onda_pura() {
  cat > "$1/state.json" <<'JSON'
{
  "schema_version": "1.0.0",
  "waves": [
    {
      "id": "onda-001",
      "skills_invoked": [
        {"skill": "model-selector", "decision_id": "dec-w-refino", "timestamp": "2026-05-24T10:00:00Z"}
      ]
    }
  ],
  "decisions": [
    {"id": "dec-w-mapa", "wave_id": "onda-002", "stage": "model-routing",
     "context": "Selecao de modelo para onda 2 (fase plan)",
     "choice": "model:opus",
     "rationale": "sugerido=opus aplicado=opus origem=mapa"},
    {"id": "dec-w-refino", "wave_id": "onda-003", "stage": "model-routing",
     "context": "Selecao de modelo para onda 3 (fase execute-task)",
     "choice": "model:sonnet",
     "rationale": "sugerido=sonnet aplicado=sonnet origem=refino"}
  ]
}
JSON
}

scenario_sdr_check_onda_pura_pendentes_zero() {
  _sdr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _sdr_fixture_onda_pura "$TMPDIR_TEST"

  capture sh "$SCRIPT" check --state-dir "$TMPDIR_TEST"
  [ "$_CAPTURED_EXIT" = 0 ] || {
    _fail "exit=0 (geracao por-onda pura, pendentes=0)" "obtido $_CAPTURED_EXIT (stdout=$_CAPTURED_STDOUT)"
    return 1
  }
  _stdout_trim=$(printf '%s' "$_CAPTURED_STDOUT" | tr -d '\n')
  [ -z "$_stdout_trim" ] || { _fail "stdout vazio (pendentes=0)" "obtido '$_stdout_trim'"; return 1; }
}

# ==== INV-6 parcial: shebang #!/bin/sh + set -eu + sem bash-isms ====

scenario_sdr_inv6_shebang_set_eu() {
  _line1=$(head -1 "$SCRIPT")
  [ "$_line1" = "#!/bin/sh" ] || { _fail "shebang #!/bin/sh" "obtido '$_line1'"; return 1; }
  grep -q '^set -eu$' "$SCRIPT" || { _fail "set -eu" "nao encontrado"; return 1; }
  if grep -qE '\[\[ ' "$SCRIPT"; then
    _fail "bash-ism" "[[ ]] detectado"
    return 1
  fi
}

run_all_scenarios "$0"
