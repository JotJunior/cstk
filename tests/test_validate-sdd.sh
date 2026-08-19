#!/bin/sh
# test_validate-sdd.sh — cobre plugins/cstk/skills/validate-documentation/scripts/validate-sdd.sh
#
# Os 12 cenarios de docs/specs/validate-docs-sdd-profile/quickstart.md sao o
# oraculo. Fixtures "boas" apontam para os artefatos REAIS e versionados de
# docs/specs/enforced-guards/ (spec.md com as 3 secoes obrigatorias, plan.md
# com as 4 — verificado por leitura, research.md Decision 5). Fixtures
# "ruins" sao copias mutadas no $TMPDIR_TEST (fixtures reais permanecem
# read-only, convencao do harness).

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/validate-documentation/scripts/validate-sdd.sh"
EG="$REPO_ROOT/docs/specs/_archived/2026-07-28-enforced-guards"

# ==== Cenario 1 — spec.md conformante (spec-profile, 0 erros) ====

scenario_c01_spec_conformante() {
  assert_exit 0 sh "$SCRIPT" "$EG/spec.md" || return 1
  assert_stdout_not_contains 'FINDING|error|' || return 1
  assert_stdout_contains 'RESULT|' || return 1
  assert_stdout_contains 'profile=spec|errors=0|warnings=0' || return 1
}

# ==== Cenario 2 — spec.md com secao obrigatoria ausente ====

scenario_c02_spec_secao_ausente() {
  grep -v '^## Success Criteria$' "$EG/spec.md" > "$TMPDIR_TEST/broken.md"
  assert_exit 1 sh "$SCRIPT" "$TMPDIR_TEST/broken.md" --sdd-spec || return 1
  assert_stdout_contains 'FINDING|error|missing-section|' || return 1
  assert_stdout_contains 'Success Criteria' || return 1
}

# ==== Cenario 3 — spec.md com termo de stack em Success Criteria ====

# NOTA: o payload antigo era "API response time under 200ms". "API" saiu da
# regex de sc-not-measurable — e termo generico de dominio, e o SKILL.md
# sempre prometeu que nao dispararia (ver
# scenario_sc_com_api_nao_dispara_falso_positivo). O cenario continua
# valendo com um termo de stack de verdade.
scenario_c03_spec_termo_stack_em_sc() {
  cp "$EG/spec.md" "$TMPDIR_TEST/broken.md"
  printf -- '- **SC-099**: React components render with <50ms paint time\n' >> "$TMPDIR_TEST/broken.md"
  assert_exit 1 sh "$SCRIPT" "$TMPDIR_TEST/broken.md" --sdd-spec || return 1
  case "${_CAPTURED_STDOUT:-}" in
    *'FINDING|error|sc-not-measurable|'*|*'FINDING|error|impl-detail-in-spec|'*) : ;;
    *) _fail "assert_stdout_contains" "esperado sc-not-measurable ou impl-detail-in-spec"; return 1 ;;
  esac
}

# ==== Cenario 4 — spec.md com > 3 [NEEDS CLARIFICATION] ====

scenario_c04_spec_excesso_clarifications() {
  cp "$EG/spec.md" "$TMPDIR_TEST/broken.md"
  printf '[NEEDS CLARIFICATION: um]\n[NEEDS CLARIFICATION: dois]\n[NEEDS CLARIFICATION: tres]\n[NEEDS CLARIFICATION: quatro]\n' >> "$TMPDIR_TEST/broken.md"
  assert_exit 1 sh "$SCRIPT" "$TMPDIR_TEST/broken.md" --sdd-spec || return 1
  assert_stdout_contains 'FINDING|error|too-many-clarifications|' || return 1
  assert_stdout_contains 'contagem=4' || return 1
  assert_stdout_contains 'limite=3' || return 1
}

# ==== Cenario 5 — spec.md com ID duplicado ====

scenario_c05_spec_id_duplicado() {
  # Corta a secao "## Delta Requirements" (ultima do fixture) antes de
  # duplicar: ela repete FR-NNN por contrato e fica FORA da varredura de
  # duplicate-id — o duplicado do teste precisa estar no corpo da spec.
  awk '/^## Delta Requirements[[:space:]]*$/ {exit} {print}' "$EG/spec.md" \
    > "$TMPDIR_TEST/broken.md"
  printf -- '- **FR-001**: Duplicado deliberadamente para o teste.\n' >> "$TMPDIR_TEST/broken.md"
  assert_exit 1 sh "$SCRIPT" "$TMPDIR_TEST/broken.md" --sdd-spec || return 1
  assert_stdout_contains 'FINDING|error|duplicate-id|' || return 1
  assert_stdout_contains 'FR-001' || return 1
}

# ==== Cenario 5b — secao Delta Requirements repete FR-NNN sem falso positivo ====

scenario_c05b_delta_section_nao_gera_duplicate_id() {
  # O fixture real (enforced-guards) tem "## Delta Requirements" preenchida
  # com entradas ADDED que REPETEM os 17 FR-NNN da secao Functional
  # Requirements (delta-section-format.md regra 4). Isso NAO pode acusar
  # duplicate-id (regressao do fix pos-living-specs).
  grep -q '^## Delta Requirements' "$EG/spec.md" || {
    _error "fixture_sem_delta" "fixture $EG/spec.md nao tem secao Delta Requirements"
    return 2
  }
  assert_exit 0 sh "$SCRIPT" "$EG/spec.md" --sdd-spec || return 1
  assert_stdout_not_contains 'duplicate-id' || return 1
}

# ==== Cenario 6 — avisos nao bloqueiam ====

scenario_c06_spec_avisos_nao_bloqueiam() {
  cp "$EG/spec.md" "$TMPDIR_TEST/broken.md"
  printf '\nN/A\n' >> "$TMPDIR_TEST/broken.md"
  printf -- '- **FR-098**: O sistema MUST be robust em todos os cenarios.\n' >> "$TMPDIR_TEST/broken.md"
  assert_exit 0 sh "$SCRIPT" "$TMPDIR_TEST/broken.md" --sdd-spec || return 1
  assert_stdout_not_contains 'FINDING|error|' || return 1
  assert_stdout_contains 'FINDING|warning|na-placeholder-section|' || return 1
  assert_stdout_contains 'FINDING|warning|vague-adjective|' || return 1
  assert_stdout_contains 'errors=0' || return 1
}

# ==== Cenario 7 — plan.md conformante (plan-profile, 0 erros) ====

scenario_c07_plan_conformante() {
  assert_exit 0 sh "$SCRIPT" "$EG/plan.md" || return 1
  assert_stdout_not_contains 'FINDING|error|' || return 1
  # 0 erros continua o oraculo do cenario 7 (12 cenarios de
  # quickstart.md). warnings deixou de ser 0 apos structural-decision-
  # human-gate (task 5.1): o Target Platform deste plan.md arquivado nao
  # cita briefing/constitution/dec-NNN por perto, entao dispara
  # target-platform-unsourced (warning, INV-V3 — nunca error). Fixture
  # arquivada, fora de escopo para editar; exit continua 0 (so warning).
  assert_stdout_contains 'profile=plan|errors=0|' || return 1
  assert_stdout_contains 'FINDING|warning|target-platform-unsourced|' || return 1
}

# ==== Cenario 8 — plan.md com placeholder de template residual ====

scenario_c08_plan_placeholder_residual() {
  cp "$EG/plan.md" "$TMPDIR_TEST/broken.md"
  printf '\nTexto com [FEATURE] literal nao preenchido.\n' >> "$TMPDIR_TEST/broken.md"
  assert_exit 1 sh "$SCRIPT" "$TMPDIR_TEST/broken.md" --sdd-plan || return 1
  assert_stdout_contains 'FINDING|error|template-placeholder|' || return 1
  assert_stdout_contains '[FEATURE]' || return 1
}

# ==== Cenario 9 — plan.md cita FR/SC inexistente na spec ====

scenario_c09_plan_ref_inexistente() {
  mkdir -p "$TMPDIR_TEST/c9"
  cp "$EG/plan.md" "$TMPDIR_TEST/c9/plan.md"
  printf '\nVer FR-099 para detalhes (nao existe na spec).\n' >> "$TMPDIR_TEST/c9/plan.md"
  assert_exit 1 sh "$SCRIPT" "$TMPDIR_TEST/c9/plan.md" --sdd-plan --spec "$EG/spec.md" || return 1
  assert_stdout_contains 'FINDING|error|dangling-fr-sc-ref|' || return 1
  assert_stdout_contains 'FR-099' || return 1
  # Nao-Expected (fronteira FR-013): nenhum achado de link/anchor quebrado.
  assert_stdout_not_contains 'Link' || return 1
  assert_stdout_not_contains 'anchor' || return 1
}

# ==== Cenario 10 — contracts/*.md sem rotulo real-vs-proposto ====

scenario_c10_contrato_sem_rotulo() {
  mkdir -p "$TMPDIR_TEST/c10/contracts"
  cat > "$TMPDIR_TEST/c10/contracts/foo.md" <<'EOF'
# Contract: Foo

## Command: `foo.sh`

Descricao do comando foo, sem rotulo real-vs-proposto.
EOF
  assert_exit 1 sh "$SCRIPT" "$TMPDIR_TEST/c10/contracts/foo.md" --sdd-plan || return 1
  assert_stdout_contains 'FINDING|error|unlabeled-contract|' || return 1
}

scenario_c10b_contrato_com_rotulo_passa() {
  mkdir -p "$TMPDIR_TEST/c10b/contracts"
  cat > "$TMPDIR_TEST/c10b/contracts/foo.md" <<'EOF'
# Contract: Foo

> [PROPOSTA — a validar na implementacao] Contrato novo.

## Command: `foo.sh`

Descricao do comando foo.
EOF
  assert_exit 0 sh "$SCRIPT" "$TMPDIR_TEST/c10b/contracts/foo.md" --sdd-plan || return 1
  assert_stdout_not_contains 'FINDING|error|' || return 1
}

# ==== Cenario 11 — perfil indeterminado fora da convencao ====

scenario_c11_perfil_indeterminado() {
  mkdir -p "$TMPDIR_TEST/fora-da-convencao"
  printf '# spec\n' > "$TMPDIR_TEST/fora-da-convencao/spec.md"
  assert_exit 2 sh "$SCRIPT" "$TMPDIR_TEST/fora-da-convencao/spec.md" || return 1
  assert_stderr_contains 'Perfil nao determinado' || return 1
  assert_stderr_contains '--sdd-spec' || return 1
}

# ==== Cenario 12 — deteccao automatica por path (sem flag) ====

scenario_c12_auto_deteccao_spec() {
  assert_exit 0 sh "$SCRIPT" "$EG/spec.md" || return 1
  assert_stdout_contains 'profile=spec' || return 1
}

scenario_c12_auto_deteccao_plan() {
  assert_exit 0 sh "$SCRIPT" "$EG/research.md" || return 1
  assert_stdout_contains 'profile=plan' || return 1
}

# ==== Cobertura adicional: uso incorreto (exit 2) ====

scenario_sem_argumento() {
  assert_exit 2 sh "$SCRIPT" || return 1
  assert_stderr_contains 'Uso:' || return 1
}

scenario_arquivo_inexistente() {
  assert_exit 2 sh "$SCRIPT" "$TMPDIR_TEST/nao-existe.md" --sdd-spec || return 1
  assert_stderr_contains 'nao encontrado' || return 1
}

scenario_flags_conflitantes() {
  assert_exit 2 sh "$SCRIPT" "$EG/spec.md" --sdd-spec --sdd-plan || return 1
  assert_stderr_contains 'mutuamente exclusivas' || return 1
}

# ==== CHK014 — --spec explicito aceita path fora da convencao docs/specs/ ====

scenario_spec_explicito_fora_da_convencao() {
  mkdir -p "$TMPDIR_TEST/outside"
  cat > "$TMPDIR_TEST/outside/spec.md" <<'EOF'
# Feature Specification: outside

## User Scenarios & Testing

Texto.

## Requirements

### Functional Requirements

- **FR-001**: O sistema MUST fazer algo.

## Success Criteria

### Measurable Outcomes

- **SC-001**: 100% dos casos passam.
EOF
  cat > "$TMPDIR_TEST/outside/plan.md" <<'EOF'
# Implementation Plan: outside

## Summary

Cita FR-001 (existe) e FR-777 (nao existe).

## Technical Context

Texto.

## Constitution Check

OK.

## Project Structure

Texto.
EOF
  assert_exit 1 sh "$SCRIPT" "$TMPDIR_TEST/outside/plan.md" --sdd-plan --spec "$TMPDIR_TEST/outside/spec.md" || return 1
  assert_stdout_contains 'FINDING|error|dangling-fr-sc-ref|' || return 1
  assert_stdout_contains 'FR-777' || return 1
}

# ==== Calibragem SC-002: 6 anti-padroes de specify/examples/spec-bad.md ====

scenario_calibragem_spec_bad_100pc() {
  cat > "$TMPDIR_TEST/calib.md" <<'EOF'
# Feature Specification: calib

## User Scenarios & Testing

### User Story P1 - Usuario cria conta (Priority: P1)

Texto.

### User Story P2 - Usuario configura perfil (requer Story P1 completa) (Priority: P2)

Texto.

## Requirements

### Functional Requirements

- **FR-001**: System MUST hash passwords with bcrypt (cost factor 12) and store in PostgreSQL `users.password_hash` column.
- **FR-005**: System MUST be fast and responsive
- **FR-006**: System MUST be secure
- **FR-007**: UI MUST be intuitive

## Key Entities

N/A

## Success Criteria

### Measurable Outcomes

- **SC-001**: API response time under 200ms
- **SC-002**: Database handles 1000 TPS
- **SC-003**: React components render efficiently with <50ms paint time
EOF
  assert_exit 1 sh "$SCRIPT" "$TMPDIR_TEST/calib.md" --sdd-spec || return 1
  # Anti-padrao 1: detalhe de implementacao
  assert_stdout_contains 'FINDING|error|impl-detail-in-spec|' || return 1
  # Anti-padrao 2: SC com jargao tecnico
  assert_stdout_contains 'FINDING|error|sc-not-measurable|' || return 1
  # Anti-padrao 3: stories acopladas
  assert_stdout_contains 'FINDING|warning|coupled-user-story|' || return 1
  # Anti-padrao 4: adjetivos vagos
  assert_stdout_contains 'FINDING|warning|vague-adjective|' || return 1
  # Anti-padrao 6: N/A residual
  assert_stdout_contains 'FINDING|warning|na-placeholder-section|' || return 1
}

# ==== Regressao de campo: "API" NAO e jargao de implementacao ====
# O SKILL.md de validate-documentation promete que termos genericos de
# dominio (API/CLI/JSON) nao geram falso-positivo em specs de ferramentas
# de dev — mas a regex de sc-not-measurable incluia "API" e rejeitava
# SC-002 de uma spec real ("servicos Go que expoem API HTTP"); so passou
# depois de reescrever para "endpoints HTTP". Script e promessa agora
# concordam: sobram apenas termos de performance de implementacao.

scenario_sc_com_api_nao_dispara_falso_positivo() {
  cat > "$TMPDIR_TEST/sc-api.md" <<'EOF'
# Feature Specification: sc-api

## User Scenarios & Testing

### User Story P1 - Operador instrumenta servico (Priority: P1)

Texto.

## Requirements

### Functional Requirements

- **FR-001**: System MUST registrar cada requisicao recebida.

## Key Entities

- **Servico**: unidade instrumentada.

## Success Criteria

### Measurable Outcomes

- **SC-001**: 100% dos 12 servicos Go que expoem API HTTP ficam instrumentados
- **SC-002**: 3 dos 3 clientes CLI reportam status em ate 5 segundos
- **SC-003**: 100% das respostas JSON validam contra o schema publicado
EOF
  capture sh "$SCRIPT" "$TMPDIR_TEST/sc-api.md" --sdd-spec
  assert_stdout_not_contains 'sc-not-measurable' || return 1
}

# Termos de performance de implementacao seguem sendo Erro.
scenario_sc_com_tps_e_paint_time_ainda_dispara() {
  cat > "$TMPDIR_TEST/sc-perf.md" <<'EOF'
# Feature Specification: sc-perf

## Success Criteria

### Measurable Outcomes

- **SC-001**: Database handles 1000 TPS
- **SC-002**: Components render with <50ms paint time
EOF
  capture sh "$SCRIPT" "$TMPDIR_TEST/sc-perf.md" --sdd-spec
  assert_stdout_contains 'FINDING|error|sc-not-measurable|' || return 1
}

# ==== structural-decision-human-gate FASE 5 (task 5.1.5, FR-010) ====
# target-platform-unresolved (error) / target-platform-unsourced (warning),
# so em plan.md (INV-V2 — guarda _is_plan_md pelo basename literal).

_tp_minimal_sections() {
  printf '## Summary\n\ntexto\n\n## Technical Context\n\ntexto\n\n## Constitution Check\n\ntexto\n\n## Project Structure\n\ntexto\n'
}

scenario_tp_ausente_dispara_unresolved_error() {
  mkdir -p "$TMPDIR_TEST/tp_ausente"
  _tp_minimal_sections > "$TMPDIR_TEST/tp_ausente/plan.md"
  assert_exit 1 sh "$SCRIPT" "$TMPDIR_TEST/tp_ausente/plan.md" --sdd-plan || return 1
  assert_stdout_contains 'FINDING|error|target-platform-unresolved|' || return 1
}

scenario_tp_needs_clarification_dispara_unresolved_error() {
  mkdir -p "$TMPDIR_TEST/tp_needs"
  { _tp_minimal_sections; printf '\n**Target Platform**: NEEDS CLARIFICATION\n'; } \
    > "$TMPDIR_TEST/tp_needs/plan.md"
  assert_exit 1 sh "$SCRIPT" "$TMPDIR_TEST/tp_needs/plan.md" --sdd-plan || return 1
  assert_stdout_contains 'FINDING|error|target-platform-unresolved|' || return 1
}

scenario_tp_preenchido_sem_fonte_dispara_unsourced_warning_sem_error() {
  mkdir -p "$TMPDIR_TEST/tp_unsourced"
  { _tp_minimal_sections; printf '\n**Target Platform**: Kubernetes\n'; } \
    > "$TMPDIR_TEST/tp_unsourced/plan.md"
  assert_exit 0 sh "$SCRIPT" "$TMPDIR_TEST/tp_unsourced/plan.md" --sdd-plan || return 1
  assert_stdout_not_contains 'FINDING|error|target-platform' || return 1
  assert_stdout_contains 'FINDING|warning|target-platform-unsourced|' || return 1
}

scenario_tp_preenchido_com_fonte_sem_nenhum_finding_novo() {
  mkdir -p "$TMPDIR_TEST/tp_sourced"
  { _tp_minimal_sections; printf '\n**Target Platform**: Kubernetes. Fonte: briefing.\n'; } \
    > "$TMPDIR_TEST/tp_sourced/plan.md"
  assert_exit 0 sh "$SCRIPT" "$TMPDIR_TEST/tp_sourced/plan.md" --sdd-plan || return 1
  assert_stdout_not_contains 'target-platform' || return 1
}

scenario_tp_fonte_em_dec_id_na_linha_adjacente_nao_dispara_warning() {
  mkdir -p "$TMPDIR_TEST/tp_dec"
  {
    _tp_minimal_sections
    printf '\n**Target Platform**: Kubernetes.\n'
    printf 'Decisao dec-042 fixou este eixo apos bloqueio humano.\n'
  } > "$TMPDIR_TEST/tp_dec/plan.md"
  assert_exit 0 sh "$SCRIPT" "$TMPDIR_TEST/tp_dec/plan.md" --sdd-plan || return 1
  assert_stdout_not_contains 'target-platform-unsourced' || return 1
}

# INV-V2: os dois checks novos so rodam quando o arquivo se chama
# literalmente plan.md — nao afetam research.md/data-model.md/quickstart.md.
scenario_tp_nao_dispara_fora_de_plan_md() {
  mkdir -p "$TMPDIR_TEST/tp_naoplan"
  _tp_minimal_sections > "$TMPDIR_TEST/tp_naoplan/research.md"
  capture sh "$SCRIPT" "$TMPDIR_TEST/tp_naoplan/research.md" --sdd-plan
  case "$_CAPTURED_STDOUT" in
    *target-platform*) _fail "INV-V2" "target-platform disparou fora de plan.md: $_CAPTURED_STDOUT"; return 1 ;;
  esac
}

run_all_scenarios
