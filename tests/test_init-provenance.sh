#!/bin/sh
# test_init-provenance.sh — cobre plugins/cstk/skills/cstk-init/scripts/init-provenance.sh
# (feature cstk-init, tarefa 4.4).
#
# Ref: docs/specs/cstk-init/contracts/cli-invocation.md §7; contracts/markers.md §1 a §3;
#      spec FR-006, FR-007, FR-015, FR-023, FR-028; quickstart Scenarios 2, 5 e 14.
#
# Cobertura:
#   gerais: ok, pending (PENDING com pergunta), dangling (caminho e linha inexistente),
#     BAD-MARKER (.., absoluto, symlink que escapa, citacao sem crases, sem fechamento,
#     linha 0, [PENDENTE] vazio/sem fechamento), `(informado pelo operador)` valido,
#     symlink interno valido, fixtures conformant/pending
#   spec reconstituida: marcador ausente/tardio, MUST/SHOULD sob Inferido (inclusive
#     minusculo), Inferido limpo, FR sem origem, SC numerico sem origem (e com origem /
#     PENDENTE), prioridade sem origem, cenario sem origem (por label e por Given/When)
#   mecanismo: uso (exit 2), raiz/arquivo inexistente, --file fora da raiz (exit 1),
#     somente leitura (arvore byte a byte igual)
#
# POSIX sh puro. Convencao de exit de scenario: 0 PASS, 1 FAIL, 2 ERROR.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

PROV="$REPO_ROOT/plugins/cstk/skills/cstk-init/scripts/init-provenance.sh"
FIXTURES="$TESTS_ROOT/fixtures/cstk-init"
TAB=$(printf '\t')
NL='
'

# _proj — cria $TMPDIR_TEST/p com um arquivo-fonte existente (src/a.js, 3 linhas).
_proj() {
  mkdir -p "$TMPDIR_TEST/p/src" "$TMPDIR_TEST/p/docs/specs/demo"
  printf 'l1\nl2\nl3\n' > "$TMPDIR_TEST/p/src/a.js"
}

# _lint <rel> — roda o lint sobre $TMPDIR_TEST/p.
_lint() {
  capture sh "$PROV" lint --root "$TMPDIR_TEST/p" --file "$1"
}

# _doc <rel> — grava o stdin em $TMPDIR_TEST/p/<rel>.
_doc() {
  cat > "$TMPDIR_TEST/p/$1"
}

# ---- uso e mecanismo ----

scenario_usage_errors_exit_2() {
  mktemp_test || return 2
  assert_exit 2 sh "$PROV" || return 1
  assert_exit 2 sh "$PROV" bogus || return 1
  assert_exit 2 sh "$PROV" lint || return 1
  assert_exit 2 sh "$PROV" lint --root "$TMPDIR_TEST" || return 1
  assert_exit 2 sh "$PROV" lint --root "$TMPDIR_TEST" --file x.md --bogus || return 1
  assert_exit 2 sh "$PROV" lint --root || return 1
}

scenario_missing_root_and_file_exit_1() {
  mktemp_test || return 2
  _proj
  assert_exit 1 sh "$PROV" lint --root "$TMPDIR_TEST/inexistente" --file docs/briefing.md || return 1
  assert_exit 1 sh "$PROV" lint --root "$TMPDIR_TEST/p" --file docs/briefing.md || return 1
  assert_exit 1 sh "$PROV" lint --root "$TMPDIR_TEST/p" --file docs || return 1
}

scenario_file_outside_root_exit_1() {
  mktemp_test || return 2
  _proj
  printf 'x\n' > "$TMPDIR_TEST/fora.md"
  assert_exit 1 sh "$PROV" lint --root "$TMPDIR_TEST/p" --file ../fora.md || return 1
  assert_exit 1 sh "$PROV" lint --root "$TMPDIR_TEST/p" --file "$TMPDIR_TEST/fora.md" || return 1
  ln -s "$TMPDIR_TEST/fora.md" "$TMPDIR_TEST/p/docs/link.md"
  assert_exit 1 sh "$PROV" lint --root "$TMPDIR_TEST/p" --file docs/link.md || return 1
}

# ---- regras gerais ----

scenario_ok_document() {
  mktemp_test || return 2
  _proj
  _doc docs/briefing.md <<'EOF'
# Briefing

Visao: servico demo. (fonte: `src/a.js`)
Linha citada. (fonte: `src/a.js:2`)
Usuarios: devs. (informado pelo operador)
Texto sem fato citavel (fonte de dados) nao e marcador.
EOF
  _lint docs/briefing.md
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "ok" "exit $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "STATUS${TAB}ok" || return 1
  assert_stdout_not_contains "BAD-MARKER" || return 1
  assert_stdout_not_contains "DANGLING" || return 1
}

scenario_pending_lists_question_and_exits_0() {
  mktemp_test || return 2
  _proj
  _doc docs/briefing.md <<'EOF'
# Briefing

Valor: [PENDENTE: qual o valor para quem usa?]
Outro: [PENDENTE: quem e o publico?] e fim.
EOF
  _lint docs/briefing.md
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "pending" "exit $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "PENDING${TAB}3${TAB}qual o valor para quem usa?" || return 1
  assert_stdout_contains "PENDING${TAB}4${TAB}quem e o publico?" || return 1
  assert_stdout_contains "STATUS${TAB}pending" || return 1
}

scenario_dangling_path_and_line_exit_3() {
  mktemp_test || return 2
  _proj
  _doc docs/briefing.md <<'EOF'
# Briefing

Inexistente. (fonte: `src/nao-existe.js`)
Linha alem do fim. (fonte: `src/a.js:99`)
Diretorio com linha. (fonte: `src:1`)
EOF
  _lint docs/briefing.md
  [ "$_CAPTURED_EXIT" -eq 3 ] || { _fail "dangling" "exit $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "DANGLING${TAB}3${TAB}src/nao-existe.js" || return 1
  assert_stdout_contains "DANGLING${TAB}4${TAB}src/a.js:99" || return 1
  assert_stdout_contains "DANGLING${TAB}5${TAB}src:1" || return 1
  assert_stdout_contains "STATUS${TAB}invalid" || return 1
}

scenario_bad_marker_dotdot_absolute_and_malformed() {
  mktemp_test || return 2
  _proj
  printf 'segredo\n' > "$TMPDIR_TEST/fora.txt"
  _doc docs/briefing.md <<EOF
# Briefing

Escapa. (fonte: \`../fora.txt\`)
Escapa no meio. (fonte: \`src/../../fora.txt\`)
Absoluto. (fonte: \`$TMPDIR_TEST/fora.txt\`)
Sem crases. (fonte: src/a.js)
Sem fechamento. (fonte: \`src/a.js
Linha zero. (fonte: \`src/a.js:0\`)
Vazio. (fonte: \`\`)
Pendente vazio: [PENDENTE: ]
Pendente aberto: [PENDENTE: sem fim
Pendente sem pergunta: [PENDENTE]
EOF
  _lint docs/briefing.md
  [ "$_CAPTURED_EXIT" -eq 3 ] || { _fail "bad" "exit $_CAPTURED_EXIT"; return 1; }
  for _n in 3 4 5 6 7 8 9 10 11 12; do
    assert_stdout_contains "BAD-MARKER${TAB}${_n}${TAB}" || return 1
  done
  assert_stdout_contains "STATUS${TAB}invalid" || return 1
  assert_stdout_not_contains "DANGLING" || return 1
}

scenario_bad_marker_symlink_escape_but_internal_symlink_ok() {
  mktemp_test || return 2
  _proj
  printf 'segredo\n' > "$TMPDIR_TEST/fora.txt"
  mkdir -p "$TMPDIR_TEST/foradir"
  printf 'x\n' > "$TMPDIR_TEST/foradir/y.txt"
  ln -s "$TMPDIR_TEST/fora.txt" "$TMPDIR_TEST/p/src/escapa.txt"
  ln -s "$TMPDIR_TEST/foradir" "$TMPDIR_TEST/p/src/escapadir"
  ln -s a.js "$TMPDIR_TEST/p/src/interno.js"
  ln -s "$TMPDIR_TEST/nada-aqui" "$TMPDIR_TEST/p/src/pendente.js"
  _doc docs/briefing.md <<'EOF'
# Briefing

Link para arquivo fora. (fonte: `src/escapa.txt`)
Link para dir fora. (fonte: `src/escapadir/y.txt`)
Link interno valido. (fonte: `src/interno.js`)
Link pendente fora. (fonte: `src/pendente.js`)
EOF
  _lint docs/briefing.md
  [ "$_CAPTURED_EXIT" -eq 3 ] || { _fail "symlink" "exit $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "BAD-MARKER${TAB}3${TAB}" || return 1
  assert_stdout_contains "BAD-MARKER${TAB}4${TAB}" || return 1
  assert_stdout_not_contains "BAD-MARKER${TAB}5${TAB}" || return 1
  assert_stdout_contains "BAD-MARKER${TAB}6${TAB}" || return 1
  # o conteudo do arquivo externo nunca aparece
  assert_stdout_not_contains "segredo" || return 1
}

scenario_fixtures_conformant_and_pending() {
  mktemp_test || return 2
  capture sh "$PROV" lint --root "$FIXTURES/conformant" --file docs/briefing.md
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "fx" "conformant briefing exit $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "STATUS${TAB}ok" || return 1
  capture sh "$PROV" lint --root "$FIXTURES/conformant" --file docs/constitution.md
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "fx" "conformant constitution exit $_CAPTURED_EXIT"; return 1; }
  capture sh "$PROV" lint --root "$FIXTURES/pending" --file docs/briefing.md
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "fx" "pending exit $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "PENDING${TAB}15${TAB}" || return 1
  assert_stdout_contains "STATUS${TAB}pending" || return 1
}

scenario_crlf_document() {
  mktemp_test || return 2
  _proj
  printf '# Briefing\r\n\r\nFato. (fonte: `src/a.js`)\r\nPend: [PENDENTE: como?]\r\n' > "$TMPDIR_TEST/p/docs/briefing.md"
  _lint docs/briefing.md
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "crlf" "exit $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "PENDING${TAB}4${TAB}como?" || return 1
}

# ---- spec reconstituida ----

# _good_spec — spec reconstituida valida (stdout).
_good_spec() {
  cat <<'EOF'
# Feature Specification: demo

<!-- cstk-init:reconstructed -->
> **Origem**: spec reconstituida.

## User Scenarios & Testing

### User Story 1 - Somar (Priority: P1) (fonte: `src/a.js`)

**Acceptance Scenarios**:

1. **Given** dois numeros, **When** somar, **Then** retorna a soma (fonte: `src/a.js:1`)
2. **Given** entrada vazia, **When** somar, **Then** [PENDENTE: qual o resultado esperado?]

### User Story 2 - Listar (Priority: [PENDENTE: qual a prioridade?])

**Acceptance Scenarios**:

1. **Given** lista, **When** listar, **Then** [PENDENTE: o que mostra?]

## Requirements

### Functional Requirements

- **FR-001**: O sistema soma dois numeros. (fonte: `src/a.js:2`)
- **FR-002**: O sistema lista itens. [PENDENTE: onde esta implementado?]

### Inferido (nao confirmado)

- **INF-001**: O sistema provavelmente valida entradas.

## Success Criteria

### Measurable Outcomes

- **SC-001**: A soma responde em ate 10 ms. (fonte: `src/a.js:3`)
- **SC-002**: A listagem e correta. [PENDENTE: qual a meta de 95%?]
- **SC-003**: O servico e simples de usar.

## Delta Requirements

**Skip**: spec reconstituida de comportamento ja existente.
EOF
}

scenario_reconstructed_spec_ok() {
  mktemp_test || return 2
  _proj
  _good_spec > "$TMPDIR_TEST/p/docs/specs/demo/spec.md"
  _lint docs/specs/demo/spec.md
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "spec-ok" "exit $_CAPTURED_EXIT: $_CAPTURED_STDOUT"; return 1; }
  assert_stdout_contains "STATUS${TAB}pending" || return 1
  assert_stdout_not_contains "BAD-MARKER" || return 1
}

scenario_reconstructed_marker_missing_or_late() {
  mktemp_test || return 2
  _proj
  _good_spec | grep -v 'cstk-init:reconstructed' > "$TMPDIR_TEST/p/docs/specs/demo/spec.md"
  _lint docs/specs/demo/spec.md
  [ "$_CAPTURED_EXIT" -eq 3 ] || { _fail "marker-missing" "exit $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "BAD-MARKER${TAB}0${TAB}" || return 1
  # marcador depois do primeiro '## '
  _good_spec | grep -v 'cstk-init:reconstructed' | sed '/^## Requirements/i\
<!-- cstk-init:reconstructed -->' > "$TMPDIR_TEST/p/docs/specs/demo/spec.md"
  _lint docs/specs/demo/spec.md
  [ "$_CAPTURED_EXIT" -eq 3 ] || { _fail "marker-late" "exit $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "apos o primeiro" || return 1
}

scenario_reconstructed_marker_applies_outside_spec_path() {
  mktemp_test || return 2
  _proj
  # marcador presente em arquivo que nao esta em docs/specs/*/spec.md: regras valem tambem
  printf '# T\n\n<!-- cstk-init:reconstructed -->\n\n## SC\n\n## Success Criteria\n\n- **SC-001**: 99%% de acerto.\n' > "$TMPDIR_TEST/p/docs/outro.md"
  _lint docs/outro.md
  [ "$_CAPTURED_EXIT" -eq 3 ] || { _fail "marker-anywhere" "exit $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "BAD-MARKER${TAB}9${TAB}" || return 1
}

scenario_reconstructed_inferido_with_must_should() {
  mktemp_test || return 2
  _proj
  _good_spec | sed 's/provavelmente valida entradas\./MUST validar entradas./' > "$TMPDIR_TEST/p/docs/specs/demo/spec.md"
  _lint docs/specs/demo/spec.md
  [ "$_CAPTURED_EXIT" -eq 3 ] || { _fail "inf-must" "exit $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "BAD-MARKER${TAB}30${TAB}MUST/SHOULD sob" || return 1
  _good_spec | sed 's/provavelmente valida entradas\./deveria validar (should) entradas./' > "$TMPDIR_TEST/p/docs/specs/demo/spec.md"
  _lint docs/specs/demo/spec.md
  [ "$_CAPTURED_EXIT" -eq 3 ] || { _fail "inf-should-lower" "exit $_CAPTURED_EXIT"; return 1; }
  # MUST fora de Inferido e fora das regras desta checagem (no Observado nao e proibido)
  _good_spec | sed 's/O sistema soma dois numeros\./O sistema MUST somar dois numeros./' > "$TMPDIR_TEST/p/docs/specs/demo/spec.md"
  _lint docs/specs/demo/spec.md
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "must-outside-inf" "exit $_CAPTURED_EXIT"; return 1; }
}

scenario_reconstructed_fr_without_origin() {
  mktemp_test || return 2
  _proj
  _good_spec | sed 's/ (fonte: `src\/a.js:2`)//' > "$TMPDIR_TEST/p/docs/specs/demo/spec.md"
  _lint docs/specs/demo/spec.md
  [ "$_CAPTURED_EXIT" -eq 3 ] || { _fail "fr-sem-fonte" "exit $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "requisito observado sem origem" || return 1
}

scenario_reconstructed_sc_numeric_without_source() {
  mktemp_test || return 2
  _proj
  # numerico sem origem
  _good_spec | sed 's/ em ate 10 ms\. (fonte: `src\/a.js:3`)/ em ate 10 ms./' > "$TMPDIR_TEST/p/docs/specs/demo/spec.md"
  _lint docs/specs/demo/spec.md
  [ "$_CAPTURED_EXIT" -eq 3 ] || { _fail "sc-num" "exit $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "Success Criterion com meta numerica sem origem" || return 1
  # numerico so com [PENDENTE] contendo digito na pergunta: valor ausente, aprovado (SC-002 do _good_spec)
  # numerico + PENDENTE mas valor presumido junto: reprovado
  _good_spec | sed 's/A listagem e correta\. \[PENDENTE/A listagem acerta 99%. [PENDENTE/' > "$TMPDIR_TEST/p/docs/specs/demo/spec.md"
  _lint docs/specs/demo/spec.md
  [ "$_CAPTURED_EXIT" -eq 3 ] || { _fail "sc-num-pend" "exit $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "Success Criterion com meta numerica sem origem" || return 1
  # SC com origem do operador e aceito
  _good_spec | sed 's/ em ate 10 ms\. (fonte: `src\/a.js:3`)/ em ate 10 ms. (informado pelo operador)/' > "$TMPDIR_TEST/p/docs/specs/demo/spec.md"
  _lint docs/specs/demo/spec.md
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "sc-num-op" "exit $_CAPTURED_EXIT"; return 1; }
}

scenario_reconstructed_priority_and_scenario_without_origin() {
  mktemp_test || return 2
  _proj
  _good_spec | sed 's/ (Priority: P1) (fonte: `src\/a.js`)/ (Priority: P1)/' > "$TMPDIR_TEST/p/docs/specs/demo/spec.md"
  _lint docs/specs/demo/spec.md
  [ "$_CAPTURED_EXIT" -eq 3 ] || { _fail "prio" "exit $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "prioridade de user story sem origem" || return 1
  # cenario sem origem (por label Acceptance Scenarios)
  _good_spec | sed 's/ retorna a soma (fonte: `src\/a.js:1`)/ retorna a soma/' > "$TMPDIR_TEST/p/docs/specs/demo/spec.md"
  _lint docs/specs/demo/spec.md
  [ "$_CAPTURED_EXIT" -eq 3 ] || { _fail "scn" "exit $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "cenario de aceite sem origem" || return 1
  # cenario fora do label, detectado por Given/When
  _good_spec | sed 's/^\*\*Acceptance Scenarios\*\*:/Cenarios:/' | sed 's/ retorna a soma (fonte: `src\/a.js:1`)/ retorna a soma/' > "$TMPDIR_TEST/p/docs/specs/demo/spec.md"
  _lint docs/specs/demo/spec.md
  [ "$_CAPTURED_EXIT" -eq 3 ] || { _fail "scn-given" "exit $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "cenario de aceite sem origem" || return 1
}

scenario_reconstructed_dangling_cite_in_spec() {
  mktemp_test || return 2
  _proj
  _good_spec | sed 's/`src\/a.js:2`/`src\/nada.js:2`/' > "$TMPDIR_TEST/p/docs/specs/demo/spec.md"
  _lint docs/specs/demo/spec.md
  [ "$_CAPTURED_EXIT" -eq 3 ] || { _fail "spec-dangling" "exit $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "DANGLING" || return 1
}

# ---- somente leitura ----

scenario_read_only_tree_unchanged() {
  mktemp_test || return 2
  _proj
  _good_spec > "$TMPDIR_TEST/p/docs/specs/demo/spec.md"
  _before=$(cd "$TMPDIR_TEST/p" && find . -type f | LC_ALL=C sort | while IFS= read -r _f; do cksum < "$_f"; printf '%s\n' "$_f"; done)
  _lint docs/specs/demo/spec.md
  _after=$(cd "$TMPDIR_TEST/p" && find . -type f | LC_ALL=C sort | while IFS= read -r _f; do cksum < "$_f"; printf '%s\n' "$_f"; done)
  [ "$_before" = "$_after" ] || { _fail "read-only" "arvore alterada pelo lint"; return 1; }
}

# ---- templates/reconstructed-spec-addendum.md (tarefa 5.5.3) ----

ADDENDUM="$REPO_ROOT/plugins/cstk/skills/cstk-init/templates/reconstructed-spec-addendum.md"
REQCOV="$REPO_ROOT/plugins/cstk/skills/checklist/scripts/requirement-coverage.sh"
CONFORMANCE="$REPO_ROOT/plugins/cstk/skills/cstk-init/scripts/init-conformance.sh"

# _addendum_skeleton — imprime o esqueleto (1o bloco ```markdown) com os placeholders trocados
# por valores reais da fixture three-features.
_addendum_skeleton() {
  awk '/^```markdown$/ && !done { inb = 1; next } inb && /^```$/ { inb = 0; done = 1; next } inb { print }' "$ADDENDUM" \
    | sed -e 's|<NOME DA FEATURE>|Billing|' -e 's|<short-name>|billing|g' -e 's|<AAAA-MM-DD>|2026-11-14|g' \
          -e 's|<caminho-do-teste>|tests/billing/billing.test.js|g' -e 's|<caminho-do-codigo>|src/billing/index.js|g'
}

scenario_addendum_skeleton_passes_lint_and_requirement_coverage() {
  [ -f "$ADDENDUM" ] || { _fail "addendum" "templates/reconstructed-spec-addendum.md ausente"; return 1; }
  mktemp_test || return 2
  fixture cstk-init/three-features || return 1
  mkdir -p "$TMPDIR_TEST/docs/specs/billing"
  _addendum_skeleton > "$TMPDIR_TEST/docs/specs/billing/spec.md"
  [ -s "$TMPDIR_TEST/docs/specs/billing/spec.md" ] || { _fail "addendum" "esqueleto vazio (bloco markdown nao encontrado)"; return 1; }
  # (a) lint da spec montada: sem BAD-MARKER/DANGLING; pendencias abertas = pending (exit 0)
  capture sh "$PROV" lint --root "$TMPDIR_TEST" --file docs/specs/billing/spec.md
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "addendum" "lint exit $_CAPTURED_EXIT: $_CAPTURED_STDOUT"; return 1; }
  assert_stdout_contains "STATUS${TAB}pending" || return 1
  assert_stdout_not_contains "BAD-MARKER" || return 1
  assert_stdout_not_contains "DANGLING" || return 1
  # (b) requirement-coverage.sh: todo FR tem cenario associado
  capture sh "$REQCOV" "$TMPDIR_TEST/docs/specs/billing/spec.md"
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "addendum" "requirement-coverage exit $_CAPTURED_EXIT: $_CAPTURED_STDOUT"; return 1; }
  # (c) formato canonico preservado: nenhuma divergencia de template na spec montada
  capture sh "$CONFORMANCE" check --root "$TMPDIR_TEST" --catalog-root "$REPO_ROOT/plugins/cstk/skills"
  printf '%s\n' "$_CAPTURED_STDOUT" | grep 'docs/specs/billing/spec.md' | grep -q 'missing-section' \
    && { _fail "addendum" "esqueleto diverge do template de spec: $_CAPTURED_STDOUT"; return 1; }
  return 0
}

scenario_addendum_skeleton_breaks_lint_when_rules_are_violated() {
  [ -f "$ADDENDUM" ] || { _fail "addendum" "templates/reconstructed-spec-addendum.md ausente"; return 1; }
  mktemp_test || return 2
  fixture cstk-init/three-features || return 1
  mkdir -p "$TMPDIR_TEST/docs/specs/billing"
  # meta numerica sem fonte e MUST sob Inferido => BAD-MARKER (FR-028, FR-015)
  _addendum_skeleton | sed -e 's|^- \*\*SC-001\*\*: .*|- **SC-001**: Responde em ate 200 ms.|' \
                           -e 's|^- \*\*INF-001\*\*: .*|- **INF-001**: O sistema MUST validar entradas.|' \
    > "$TMPDIR_TEST/docs/specs/billing/spec.md"
  capture sh "$PROV" lint --root "$TMPDIR_TEST" --file docs/specs/billing/spec.md
  [ "$_CAPTURED_EXIT" -eq 3 ] || { _fail "addendum" "violacao deveria dar exit 3, deu $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "STATUS${TAB}invalid" || return 1
}

scenario_addendum_documents_origin_rules() {
  [ -f "$ADDENDUM" ] || { _fail "addendum" "templates/reconstructed-spec-addendum.md ausente"; return 1; }
  for _needle in '<!-- cstk-init:reconstructed -->' '### Inferido (nao confirmado)' '## Delta Requirements' \
                 '**Skip**' '(fonte:' '[PENDENTE:' 'MUST NOT' 'Priority' 'meta numerica' 'FR-028'; do
    grep -qF -- "$_needle" "$ADDENDUM" || { _fail "addendum" "sem: $_needle"; return 1; }
  done
}

# ---- hardening 7.4 (owasp-security pos-implementacao) ----

scenario_cite_to_fifo_does_not_hang() {
  mktemp_test || return 2
  mkdir -p "$TMPDIR_TEST/p/docs"
  mkfifo "$TMPDIR_TEST/p/fifo" || return 2
  printf '# T\n(fonte: `fifo:3`)\n' > "$TMPDIR_TEST/p/docs/s.md"
  sh "$PROV" lint --root "$TMPDIR_TEST/p" --file docs/s.md > "$TMPDIR_TEST/out" 2>&1 &
  _pid=$!
  _i=0
  while kill -0 "$_pid" 2>/dev/null && [ "$_i" -lt 50 ]; do
    sleep 0.1
    _i=$((_i + 1))
  done
  if kill -0 "$_pid" 2>/dev/null; then
    kill "$_pid" 2>/dev/null
    pkill -P "$_pid" 2>/dev/null
    _fail "fifo" "lint travou lendo FIFO citado"
    return 1
  fi
  wait "$_pid" 2>/dev/null
  grep -q 'DANGLING' "$TMPDIR_TEST/out" || { _fail "fifo" "esperava DANGLING para destino nao regular"; return 1; }
}

scenario_bad_marker_does_not_echo_line_content() {
  mktemp_test || return 2
  mkdir -p "$TMPDIR_TEST/p/docs"
  cat > "$TMPDIR_TEST/p/docs/spec.md" <<'EOF'
<!-- cstk-init:reconstructed -->
# S
## Requirements
- **FR-001** O sistema usa password: FIXTURE_FAKE_ECHO_0123456789 para conectar
- **FR-002** Outro (fonte: sem-crases FIXTURE_FAKE_ECHO_9876543210
EOF
  capture sh "$PROV" lint --root "$TMPDIR_TEST/p" --file docs/spec.md
  [ "$_CAPTURED_EXIT" -eq 3 ] || { _fail "echo" "exit $_CAPTURED_EXIT (esperado 3)"; return 1; }
  assert_stdout_contains "BAD-MARKER${TAB}4${TAB}" || return 1
  assert_stdout_contains "BAD-MARKER${TAB}5${TAB}" || return 1
  assert_stdout_not_contains "FIXTURE_FAKE_ECHO" || return 1
}

run_all_scenarios
