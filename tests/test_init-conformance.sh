#!/bin/sh
# test_init-conformance.sh — cobre plugins/cstk/skills/cstk-init/scripts/init-conformance.sh
# (feature cstk-init, tarefa 4.5).
#
# Ref: docs/specs/cstk-init/quickstart.md Scenarios 5 e 6; contracts/cli-invocation.md §4;
#      contracts/conformance-catalog.md; spec FR-009, FR-010, FR-023.
#
# Cobertura:
#   fixtures: conformant/pending/bare/three-features -> conformant; legacy -> CR-001 +
#     missing-section + CR-005; both-briefings -> CR-002
#   regras: CR-003 (cabecalho), CR-004 (rodape), CR-005, CR-006, CR-007, missing-section de
#     spec; titulos DERIVADOS do template instalado (template alterado -> nova secao exigida)
#   mecanismo: irma ausente (3 templates) -> exit 4 citando caminho e `cstk install`; uso
#     (exit 2); raiz inexistente (exit 1); somente leitura (arvore byte a byte igual);
#     symlink que escapa ignorado; conteudo hostil nunca executado
#
# POSIX sh puro. Convencao de exit de scenario: 0 PASS, 1 FAIL, 2 ERROR.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CONF="$REPO_ROOT/plugins/cstk/skills/cstk-init/scripts/init-conformance.sh"
CATALOG="$REPO_ROOT/plugins/cstk/skills"
FIXTURES="$TESTS_ROOT/fixtures/cstk-init"
TAB=$(printf '\t')

# _check <root> [catalog] — roda `check`.
_check() {
  capture sh "$CONF" check --root "$1" --catalog-root "${2:-$CATALOG}"
}

# _fake_catalog <dir> — copia so os tres templates (permite alterar/remover).
_fake_catalog() {
  mkdir -p "$1/briefing/templates" "$1/constitution/templates" "$1/specify/templates"
  cp "$CATALOG/briefing/templates/briefing.md" "$1/briefing/templates/briefing.md"
  cp "$CATALOG/constitution/templates/constitution.md" "$1/constitution/templates/constitution.md"
  cp "$CATALOG/specify/templates/feature-spec.md" "$1/specify/templates/feature-spec.md"
}

# _tree_sum <dir> — assinatura (nomes + cksum) da arvore.
_tree_sum() {
  (cd "$1" && find . | LC_ALL=C sort | while IFS= read -r _f; do
    if [ -f "$_f" ]; then cksum < "$_f"; fi
    printf '%s\n' "$_f"
  done)
}

scenario_usage_and_missing_root() {
  mktemp_test || return 2
  assert_exit 2 sh "$CONF" || return 1
  assert_exit 2 sh "$CONF" bogus || return 1
  assert_exit 2 sh "$CONF" check || return 1
  assert_exit 2 sh "$CONF" check --root "$TMPDIR_TEST" || return 1
  assert_exit 2 sh "$CONF" check --root "$TMPDIR_TEST" --catalog-root "$CATALOG" --bogus || return 1
  assert_exit 1 sh "$CONF" check --root "$TMPDIR_TEST/inexistente" --catalog-root "$CATALOG" || return 1
}

scenario_conformant_pending_bare_three_features() {
  mktemp_test || return 2
  for _f in conformant pending bare three-features; do
    _check "$FIXTURES/$_f"
    [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "$_f" "exit $_CAPTURED_EXIT"; return 1; }
    assert_stdout_contains "STATUS${TAB}conformant" || return 1
  done
}

scenario_legacy_fixture() {
  mktemp_test || return 2
  _check "$FIXTURES/legacy"
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "legacy" "exit $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "docs/01-briefing-discovery/briefing.md${TAB}CR-001${TAB}" || return 1
  assert_stdout_contains "${TAB}migrate-path" || return 1
  assert_stdout_contains "docs/constitution.md${TAB}missing-section${TAB}## Governance${TAB}add-section" || return 1
  assert_stdout_contains "docs/constitution.md${TAB}CR-005${TAB}" || return 1
  assert_stdout_contains "STATUS${TAB}divergent" || return 1
}

scenario_both_briefings_fixture() {
  mktemp_test || return 2
  _check "$FIXTURES/both-briefings"
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "both" "exit $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "docs/briefing.md${TAB}CR-002${TAB}" || return 1
  assert_stdout_contains "${TAB}manual" || return 1
  assert_stdout_not_contains "CR-001" || return 1
  assert_stdout_contains "STATUS${TAB}divergent" || return 1
}

scenario_missing_sister_template_exit_4() {
  mktemp_test || return 2
  for _t in briefing/templates/briefing.md constitution/templates/constitution.md specify/templates/feature-spec.md; do
    rm -rf "$TMPDIR_TEST/cat"
    _fake_catalog "$TMPDIR_TEST/cat"
    rm -f "$TMPDIR_TEST/cat/$_t"
    _check "$FIXTURES/conformant" "$TMPDIR_TEST/cat"
    [ "$_CAPTURED_EXIT" -eq 4 ] || { _fail "irma" "$_t: exit $_CAPTURED_EXIT"; return 1; }
    assert_stderr_contains "$_t" || return 1
    assert_stderr_contains "cstk install" || return 1
    assert_stdout_not_contains "STATUS" || return 1
  done
  # catalogo inexistente
  _check "$FIXTURES/conformant" "$TMPDIR_TEST/nao-existe"
  [ "$_CAPTURED_EXIT" -eq 4 ] || { _fail "irma" "catalogo inexistente: exit $_CAPTURED_EXIT"; return 1; }
}

scenario_titles_derived_from_installed_template() {
  mktemp_test || return 2
  _fake_catalog "$TMPDIR_TEST/cat"
  printf '\n## 9. Secao Nova do Template\n\ntexto\n' >> "$TMPDIR_TEST/cat/briefing/templates/briefing.md"
  _check "$FIXTURES/conformant" "$TMPDIR_TEST/cat"
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "derive" "exit $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "docs/briefing.md${TAB}missing-section${TAB}## 9. Secao Nova do Template${TAB}add-section" || return 1
  assert_stdout_contains "STATUS${TAB}divergent" || return 1
  # placeholder em titulo (`[...]`) nao vira secao exigida
  _fake_catalog "$TMPDIR_TEST/cat"
  printf '\n## [SECAO_LIVRE]\n' >> "$TMPDIR_TEST/cat/briefing/templates/briefing.md"
  _check "$FIXTURES/conformant" "$TMPDIR_TEST/cat"
  assert_stdout_contains "STATUS${TAB}conformant" || return 1
}

scenario_briefing_header_cr003() {
  mktemp_test || return 2
  cp -R "$FIXTURES/conformant" "$TMPDIR_TEST/p"
  grep -v '^\*\*Versao\*\*' "$FIXTURES/conformant/docs/briefing.md" > "$TMPDIR_TEST/p/docs/briefing.md"
  _check "$TMPDIR_TEST/p"
  assert_stdout_contains "docs/briefing.md${TAB}CR-003${TAB}**Versao**" || return 1
  assert_stdout_not_contains "CR-003${TAB}**Data**" || return 1
  assert_stdout_contains "STATUS${TAB}divergent" || return 1
}

scenario_constitution_rules_cr004_cr006() {
  mktemp_test || return 2
  cp -R "$FIXTURES/conformant" "$TMPDIR_TEST/p"
  # rodape malformado (sem Last Amended)
  sed 's/ | \*\*Last Amended\*\*: .*//' "$FIXTURES/conformant/docs/constitution.md" > "$TMPDIR_TEST/p/docs/constitution.md"
  _check "$TMPDIR_TEST/p"
  assert_stdout_contains "docs/constitution.md${TAB}CR-004${TAB}" || return 1
  assert_stdout_contains "${TAB}fix-footer" || return 1
  # rodape com valor vazio
  sed 's/\*\*Ratified\*\*: [0-9-]*/**Ratified**: /' "$FIXTURES/conformant/docs/constitution.md" > "$TMPDIR_TEST/p/docs/constitution.md"
  _check "$TMPDIR_TEST/p"
  assert_stdout_contains "CR-004" || return 1
  # principio II sem **MUST:**
  awk 'BEGIN{n=0} /^\*\*MUST:\*\*/{n++; if(n==2) next} {print}' "$FIXTURES/conformant/docs/constitution.md" > "$TMPDIR_TEST/p/docs/constitution.md"
  _check "$TMPDIR_TEST/p"
  assert_stdout_contains "CR-006${TAB}principio sem linha **MUST:**: II. Veracidade de Dados" || return 1
  assert_stdout_not_contains "CR-006${TAB}principio sem linha **MUST:**: I. Testes" || return 1
  assert_stdout_not_contains "CR-004" || return 1
}

scenario_spec_rules_cr007_and_missing_section() {
  mktemp_test || return 2
  cp -R "$FIXTURES/conformant" "$TMPDIR_TEST/p"
  mkdir -p "$TMPDIR_TEST/p/docs/specs/demo" "$TMPDIR_TEST/p/docs/specs/_archived/velha" "$TMPDIR_TEST/p/docs/specs/current"
  # spec completa, sem Delta Requirements
  cat > "$TMPDIR_TEST/p/docs/specs/demo/spec.md" <<'SPEC'
# Feature Specification: demo

## User Scenarios & Testing

### Edge Cases

## Requirements

### Functional Requirements

## Success Criteria

### Measurable Outcomes
SPEC
  # specs arquivadas/current nao entram
  printf '# velha\n' > "$TMPDIR_TEST/p/docs/specs/_archived/velha/spec.md"
  printf '# atual\n' > "$TMPDIR_TEST/p/docs/specs/current/spec.md"
  _check "$TMPDIR_TEST/p"
  assert_stdout_contains "docs/specs/demo/spec.md${TAB}CR-007${TAB}" || return 1
  assert_stdout_contains "${TAB}add-delta-section" || return 1
  assert_stdout_not_contains "missing-section${TAB}## User Scenarios" || return 1
  assert_stdout_not_contains "_archived" || return 1
  assert_stdout_not_contains "specs/current" || return 1
  # secoes faltando
  printf '# Feature Specification: demo\n\n## Delta Requirements\n' > "$TMPDIR_TEST/p/docs/specs/demo/spec.md"
  _check "$TMPDIR_TEST/p"
  assert_stdout_contains "docs/specs/demo/spec.md${TAB}missing-section${TAB}## User Scenarios & Testing${TAB}add-section" || return 1
  assert_stdout_contains "missing-section${TAB}### Measurable Outcomes" || return 1
  assert_stdout_not_contains "CR-007" || return 1
  assert_stdout_not_contains "Key Entities" || return 1
}

scenario_read_only_tree_unchanged() {
  mktemp_test || return 2
  cp -R "$FIXTURES/legacy" "$TMPDIR_TEST/p"
  _before=$(_tree_sum "$TMPDIR_TEST/p")
  _check "$TMPDIR_TEST/p"
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "ro" "exit $_CAPTURED_EXIT"; return 1; }
  _after=$(_tree_sum "$TMPDIR_TEST/p")
  [ "$_before" = "$_after" ] || { _fail "ro" "arvore alterada pelo check"; return 1; }
}

scenario_symlink_artifact_outside_root_ignored() {
  mktemp_test || return 2
  mkdir -p "$TMPDIR_TEST/p/docs" "$TMPDIR_TEST/fora"
  printf '# Externo\n' > "$TMPDIR_TEST/fora/constitution.md"
  ln -s "$TMPDIR_TEST/fora/constitution.md" "$TMPDIR_TEST/p/docs/constitution.md"
  _check "$TMPDIR_TEST/p"
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "symlink" "exit $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "symlink que escapa" || return 1
  # conteudo externo nunca lido; o artefato pulado vira CR-008 e o STATUS NAO e conformant (7.5.2)
  assert_stdout_not_contains "Externo" || return 1
  assert_stdout_contains "docs/constitution.md${TAB}CR-008${TAB}" || return 1
  assert_stdout_contains "STATUS${TAB}divergent" || return 1
  assert_stdout_not_contains "STATUS${TAB}conformant" || return 1
}

# 7.5.2 — todo artefato existente que nao foi avaliado e CR-008 (nunca "conformant"):
# briefing canonico e legado com symlink que escapa, diretorio de spec symlink, docs/specs symlink,
# artefato que existe mas nao e arquivo regular legivel (diretorio no lugar do arquivo).
scenario_skipped_artifacts_are_cr008_not_conformant() {
  mktemp_test || return 2
  _p="$TMPDIR_TEST/p"
  mkdir -p "$_p/docs/01-briefing-discovery" "$_p/docs/specs/feat" "$TMPDIR_TEST/fora/specdir"
  printf '# Externo\n' > "$TMPDIR_TEST/fora/b.md"
  ln -s "$TMPDIR_TEST/fora/b.md" "$_p/docs/briefing.md"
  ln -s "$TMPDIR_TEST/fora/b.md" "$_p/docs/01-briefing-discovery/briefing.md"
  ln -s "$TMPDIR_TEST/fora/specdir" "$_p/docs/specs/linked"
  mkdir -p "$_p/docs/constitution.md"
  _check "$_p"
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "cr008" "exit $_CAPTURED_EXIT"; return 1; }
  for _a in docs/briefing.md docs/01-briefing-discovery/briefing.md docs/specs/linked docs/constitution.md; do
    assert_stdout_contains "$_a${TAB}CR-008${TAB}" || return 1
  done
  assert_stdout_contains "STATUS${TAB}divergent" || return 1
  assert_stdout_not_contains "STATUS${TAB}conformant" || return 1
  assert_stdout_not_contains "Externo" || return 1
  # docs/specs inteiro symlink
  mktemp_test || return 2
  _p="$TMPDIR_TEST/p2"
  mkdir -p "$_p/docs" "$TMPDIR_TEST/fora2"
  ln -s "$TMPDIR_TEST/fora2" "$_p/docs/specs"
  _check "$_p"
  assert_stdout_contains "docs/specs${TAB}CR-008${TAB}" || return 1
  assert_stdout_contains "STATUS${TAB}divergent" || return 1
}

# Sem artefato nenhum (nada pulado) continua conformant: o novo estado nao muda o caso limpo.
scenario_nothing_skipped_stays_conformant() {
  mktemp_test || return 2
  mkdir -p "$TMPDIR_TEST/p/docs"
  _check "$TMPDIR_TEST/p"
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "limpo" "exit $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "STATUS${TAB}conformant" || return 1
  assert_stdout_not_contains "CR-008" || return 1
}

scenario_hostile_content_never_executed() {
  mktemp_test || return 2
  mkdir -p "$TMPDIR_TEST/p/docs"
  printf '# T\n\n## Core Principles\n\n### $(touch %s/pwned)\n\n`touch %s/pwned2`\n' "$TMPDIR_TEST" "$TMPDIR_TEST" > "$TMPDIR_TEST/p/docs/constitution.md"
  _check "$TMPDIR_TEST/p"
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "hostile" "exit $_CAPTURED_EXIT"; return 1; }
  [ ! -e "$TMPDIR_TEST/pwned" ] && [ ! -e "$TMPDIR_TEST/pwned2" ] || { _fail "hostile" "conteudo executado"; return 1; }
  assert_stdout_contains "CR-006" || return 1
}

# ---- 1:1 entre os IDs CR-NNN do script e de references/conformance-rules.md (tarefa 5.3.2/5.3.3) ----

RULES_DOC="$REPO_ROOT/plugins/cstk/skills/cstk-init/references/conformance-rules.md"

scenario_every_emitted_cr_id_exists_in_conformance_rules_doc() {
  [ -f "$RULES_DOC" ] || { _fail "rules-doc" "references/conformance-rules.md ausente"; return 1; }
  # (a) estatico: todo CR-NNN passado a _div no script
  _ids=$(grep '_div ' "$CONF" | grep -o 'CR-[0-9][0-9][0-9]' | sort -u)
  [ -n "$_ids" ] || { _fail "rules-doc" "nenhum CR-NNN encontrado no script"; return 1; }
  for _i in $_ids; do
    grep -q "^### $_i " "$RULES_DOC" || { _fail "rules-doc" "$_i emitido pelo script mas sem secao em conformance-rules.md"; return 1; }
  done
  # (b) dinamico: o que sai de verdade nas fixtures legacy e both-briefings
  for _f in legacy both-briefings; do
    mktemp_test || return 2
    fixture "cstk-init/$_f" || return 1
    _check "$TMPDIR_TEST"
    for _i in $(printf '%s\n' "$_CAPTURED_STDOUT" | grep -o 'CR-[0-9][0-9][0-9]' | sort -u); do
      grep -q "^### $_i " "$RULES_DOC" || { _fail "rules-doc" "$_i emitido em $_f sem secao no documento"; return 1; }
    done
  done
  # missing-section tambem documentado
  grep -q 'missing-section' "$RULES_DOC" || { _fail "rules-doc" "missing-section nao documentado"; return 1; }
}

scenario_conformance_rules_doc_has_no_orphan_cr_id() {
  [ -f "$RULES_DOC" ] || { _fail "rules-doc" "references/conformance-rules.md ausente"; return 1; }
  _script_ids=$(grep '_div ' "$CONF" | grep -o 'CR-[0-9][0-9][0-9]' | sort -u)
  for _i in $(grep -o '^### CR-[0-9][0-9][0-9]' "$RULES_DOC" | sed 's/^### //' | sort -u); do
    printf '%s\n' "$_script_ids" | grep -qx "$_i" || { _fail "rules-doc" "$_i documentado mas nunca emitido pelo script"; return 1; }
  done
  # cada regra documenta proposta e operacao
  for _i in $_script_ids; do
    _blk=$(sed -n "/^### $_i /,/^### CR-\|^## 3/p" "$RULES_DOC")
    printf '%s\n' "$_blk" | grep -q 'Proposta' || { _fail "rules-doc" "$_i sem Proposta"; return 1; }
    printf '%s\n' "$_blk" | grep -q 'Operacao' || { _fail "rules-doc" "$_i sem Operacao"; return 1; }
  done
}

# ---- hardening 7.4 (owasp-security pos-implementacao) ----

scenario_principle_title_glob_is_not_expanded() {
  mktemp_test || return 2
  mkdir -p "$TMPDIR_TEST/p/docs" "$TMPDIR_TEST/g"
  : > "$TMPDIR_TEST/g/FIXTURE_LEAK_NAME_1"
  : > "$TMPDIR_TEST/g/FIXTURE_LEAK_NAME_2"
  cat > "$TMPDIR_TEST/p/docs/constitution.md" <<EOF
# C
## Core Principles
### $TMPDIR_TEST/g/*
sem must
## Governance
**Version**: 1.0.0 | **Ratified**: 2026-01-01 | **Last Amended**: 2026-01-01
EOF
  _check "$TMPDIR_TEST/p" || true
  assert_stdout_not_contains "FIXTURE_LEAK_NAME" || return 1
  assert_stdout_contains "/g/*" || return 1
}

run_all_scenarios
