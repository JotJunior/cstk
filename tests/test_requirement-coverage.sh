#!/bin/sh
# test_requirement-coverage.sh —
# cobre plugins/cstk/skills/checklist/scripts/requirement-coverage.sh.
#
# Contrato: docs/specs/openspec-hygiene/contracts/requirement-coverage-cli.md
#   requirement-coverage.sh FILE [--min-match N]
#     Emite FINDING|error|fr-no-scenario|<ID> ... e um
#     RESULT|<FILE>|requirements=<T>|covered=<C>|errors=<N>.
#     Exit: 0 zero gaps; 1 >=1 gap; 2 uso incorreto/arquivo/--min-match.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/checklist/scripts/requirement-coverage.sh"

# Escreve uma fixture minima de spec.md em $TMPDIR_TEST/$1 com o corpo dado
# em $2 (Functional Requirements) e $3 (Acceptance Scenarios + Edge Cases).
_write_spec() {
  _dest="$TMPDIR_TEST/$1"
  cat > "$_dest" <<EOF
# Feature Specification: Fixture

## User Scenarios & Testing

### User Story 1 - Exemplo (Priority: P1)

**Acceptance Scenarios**:

$3

## Requirements

### Functional Requirements

$2
EOF
}

# ==== gap unico citando ID exato (Cenario 1 do quickstart) ====

scenario_gap_unico_reporta_id_exato() {
  _write_spec "gap.md" \
"- **FR-001**: O sistema MUST registrar toda transacao de pagamento processada com sucesso.
- **FR-002**: O sistema MUST rejeitar pagamentos com assinatura criptografica invalida imediatamente." \
"1. **Given** um usuario autenticado, **When** ele envia um pagamento valido, **Then** o sistema registra a transacao com sucesso."

  assert_exit 1 sh "$SCRIPT" "$TMPDIR_TEST/gap.md" || return 1
  assert_stdout_contains "FINDING|error|fr-no-scenario|FR-002 sem cenario associado" || return 1
  assert_stdout_not_contains "fr-no-scenario|FR-001" || return 1
  assert_stdout_contains "RESULT|$TMPDIR_TEST/gap.md|requirements=2|covered=1|errors=1" || return 1
}

# ==== spec integralmente coberta (fast-path + heuristica) -> exit 0 ====

scenario_spec_integralmente_coberta() {
  _write_spec "full.md" \
"- **FR-001**: O sistema MUST registrar toda transacao de pagamento processada com sucesso.
- **FR-002**: O sistema MUST rejeitar pagamentos com assinatura criptografica invalida imediatamente." \
"1. **Given** um usuario autenticado, **When** ele envia um pagamento valido, **Then** o sistema registra a transacao com sucesso (FR-001).
2. **Given** um pagamento com assinatura criptografica invalida, **When** o sistema processa a requisicao, **Then** ele rejeita imediatamente por assinatura invalida."

  assert_exit 0 sh "$SCRIPT" "$TMPDIR_TEST/full.md" || return 1
  assert_stdout_not_contains "FINDING|" || return 1
  assert_stdout_contains "RESULT|$TMPDIR_TEST/full.md|requirements=2|covered=2|errors=0" || return 1
}

# ==== spec sem Functional Requirements -> exit 0 trivial ====

scenario_spec_sem_frs_passa_trivial() {
  _write_spec "no-fr.md" "" \
"1. **Given** algo, **When** acao, **Then** resultado."

  assert_exit 0 sh "$SCRIPT" "$TMPDIR_TEST/no-fr.md" || return 1
  assert_stdout_contains "RESULT|$TMPDIR_TEST/no-fr.md|requirements=0|covered=0|errors=0" || return 1
}

# ==== fast-path: cobertura por citacao literal do ID, sem termos em comum ====

scenario_fast_path_por_id_literal() {
  _write_spec "fastpath.md" \
"- **FR-001**: Zebra quokka wombat xyzzy plugh." \
"1. **Given** situacao, **When** acao qualquer, **Then** confirma cobertura de FR-001 explicitamente."

  assert_exit 0 sh "$SCRIPT" "$TMPDIR_TEST/fastpath.md" || return 1
  assert_stdout_contains "requirements=1|covered=1|errors=0" || return 1
}

# ==== cobertura via heuristica textual, sem citar o ID ====

scenario_cobertura_via_heuristica_sem_id() {
  _write_spec "heuristic.md" \
"- **FR-001**: O sistema MUST enviar notificacao assincrona ao concluir o processamento do relatorio." \
"1. **Given** o processamento do relatorio concluido, **When** o sistema termina, **Then** uma notificacao assincrona e enviada ao usuario."

  assert_exit 0 sh "$SCRIPT" "$TMPDIR_TEST/heuristic.md" || return 1
  assert_stdout_contains "requirements=1|covered=1|errors=0" || return 1
}

# ==== --min-match eleva a barra: 1 termo em comum nao basta com min-match=2 ====

scenario_min_match_eleva_barra() {
  _write_spec "minmatch.md" \
"- **FR-001**: O sistema MUST enviar notificacao assincrona ao concluir o processamento do relatorio." \
"1. **Given** qualquer coisa, **When** acao, **Then** apenas notificacao aparece aqui, nada mais relacionado."

  # Com default (min-match=2, so 1 termo em comum: "notificacao") -> gap.
  assert_exit 1 sh "$SCRIPT" "$TMPDIR_TEST/minmatch.md" || return 1
  assert_stdout_contains "FINDING|error|fr-no-scenario|FR-001" || return 1

  # Com --min-match 1, 1 termo em comum ja basta -> cobre.
  assert_exit 0 sh "$SCRIPT" "$TMPDIR_TEST/minmatch.md" --min-match 1 || return 1
}

# ==== FRs subagrupados sob heading #### dentro de Functional Requirements
# nao fecham a secao (regressao real: docs/specs/enforced-guards/spec.md
# agrupa FRs sob "#### <titulo> (USn)") ====

scenario_subheading_nivel4_nao_fecha_secao() {
  cat > "$TMPDIR_TEST/subgroup.md" <<'EOF'
# Feature Specification: Fixture Subgroup

## User Scenarios & Testing

### User Story 1 - Exemplo (Priority: P1)

**Acceptance Scenarios**:

1. **Given** um usuario autenticado, **When** ele envia um pagamento valido, **Then** o sistema registra a transacao com sucesso (FR-001).

## Requirements

### Functional Requirements

#### Subgrupo qualquer (US1)

- **FR-001**: O sistema MUST registrar toda transacao de pagamento processada com sucesso.
EOF

  assert_exit 0 sh "$SCRIPT" "$TMPDIR_TEST/subgroup.md" || return 1
  assert_stdout_contains "requirements=1|covered=1|errors=0" || return 1
}

# ==== --min-match invalido -> exit 2 ====

scenario_min_match_invalido() {
  _write_spec "any.md" "- **FR-001**: Qualquer coisa." "1. **Given** a, **When** b, **Then** c."

  assert_exit 2 sh "$SCRIPT" "$TMPDIR_TEST/any.md" --min-match 0 || return 1
  assert_stderr_contains "min-match" || return 1
  assert_exit 2 sh "$SCRIPT" "$TMPDIR_TEST/any.md" --min-match abc || return 1
  assert_stderr_contains "min-match" || return 1
}

# ==== FILE ausente -> exit 2 ====

scenario_file_ausente() {
  assert_exit 2 sh "$SCRIPT" || return 1
  assert_stderr_contains "Uso:" || return 1
  assert_exit 2 sh "$SCRIPT" "$TMPDIR_TEST/nao-existe.md" || return 1
  assert_stderr_contains "nao encontrado" || return 1
}

# ==== fixture real do repo: esta propria spec.md (anti-regressao da heuristica) ====

scenario_fixture_real_spec_openspec_hygiene() {
  _real="$REPO_ROOT/docs/specs/_archived/2026-07-28-openspec-hygiene/spec.md"
  if [ ! -f "$_real" ]; then
    _error "fixture_real_ausente" "spec.md real nao encontrado: $_real"
    return 2
  fi
  assert_exit 0 sh "$SCRIPT" "$_real" || return 1
  assert_stdout_not_contains "FINDING|" || return 1
  assert_stdout_match "RESULT\\|.*\\|requirements=17\\|covered=17\\|errors=0" || return 1
}

# ==== read-only: nao toca o working tree ====

scenario_sem_efeito_colateral() {
  _real="$REPO_ROOT/docs/specs/_archived/2026-07-28-openspec-hygiene/spec.md"
  sh "$SCRIPT" "$_real" >/dev/null 2>&1 || true
  assert_no_side_effect || return 1
}

run_all_scenarios
