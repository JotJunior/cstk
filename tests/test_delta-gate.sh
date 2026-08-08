#!/bin/sh
# test_delta-gate.sh —
# cobre plugins/cstk/skills/review-features/scripts/delta-gate.sh.
#
# Contrato: docs/specs/living-specs/contracts/delta-gate-cli.md
#   delta-gate.sh SPEC_MD [--corpus-dir DIR]
#     Emite FINDING|<severity>|<code>|<mensagem> e um
#     RESULT|<spec>|delta=<present|skip|missing>|errors=<N>|warnings=<M>.
#     Exit: 0 liberado (delta valida ou skip valido); 1 bloqueado (>=1 erro);
#     2 uso incorreto / SPEC_MD inexistente / corpus-dir irresoluvel.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/review-features/scripts/delta-gate.sh"

# Escreve $1 em $TMPDIR_TEST/spec.md e retorna o path via stdout.
_write_spec() {
  _dest="$TMPDIR_TEST/spec.md"
  printf '%s\n' "$1" > "$_dest"
  printf '%s' "$_dest"
}

_corpus_dir() {
  printf '%s/current' "$TMPDIR_TEST"
}

_write_corpus_file() {
  # $1 = slug, $2 = conteudo
  _cd=$(_corpus_dir)
  mkdir -p "$_cd"
  printf '%s\n' "$2" > "$_cd/$1.md"
}

_BASE_CORPUS='# Capability: sample-cap

> Comportamento ATUAL do sistema para esta capability.

## Requirements

### FR-001

Texto do requisito 1.

*Introduzida por: feat-orig (2026-01-01)*

### FR-002

Texto do requisito 2.

*Introduzida por: feat-orig (2026-01-01)*

## Removed Requirements

### FR-003 [REMOVED]

Texto antigo.

*Introduzida por: feat-orig (2026-01-01)*
*Removida por: feat-y (2026-02-01)* — obsoleto

## Renamed Identifiers

| Antigo | Novo | Feature | Data |
|--------|------|---------|------|
| FR-004 | FR-005 | feat-z | 2026-03-01 |'

# ==== 3.5.1 happy-path ====

scenario_added_corpus_ausente_info_exit0() {
  _spec=$(_write_spec '# Feature Spec: fixture

## Delta Requirements

### Capability: sample-cap

#### ADDED

- **FR-010**: Novo requisito.')

  assert_exit 0 sh "$SCRIPT" "$_spec" --corpus-dir "$(_corpus_dir)" || return 1
  assert_stdout_contains "FINDING|info|corpus-missing|sample-cap" || return 1
  assert_stdout_contains "delta=present|errors=0" || return 1
}

scenario_modified_removed_sobre_corpus_existente() {
  _write_corpus_file "sample-cap" "$_BASE_CORPUS"
  _spec=$(_write_spec '# Feature Spec: fixture

## Delta Requirements

### Capability: sample-cap

#### MODIFIED

- **FR-001**: Novo texto do requisito 1.

#### REMOVED

- **FR-002**: motivo da remocao.')

  assert_exit 0 sh "$SCRIPT" "$_spec" --corpus-dir "$(_corpus_dir)" || return 1
  assert_stdout_not_contains "FINDING|error" || return 1
  assert_stdout_contains "delta=present|errors=0" || return 1
}

scenario_removed_only_valida() {
  _write_corpus_file "sample-cap" "$_BASE_CORPUS"
  _spec=$(_write_spec '# Feature Spec: fixture

## Delta Requirements

### Capability: sample-cap

#### REMOVED

- **FR-002**: motivo qualquer.')

  assert_exit 0 sh "$SCRIPT" "$_spec" --corpus-dir "$(_corpus_dir)" || return 1
  assert_stdout_contains "delta=present|errors=0" || return 1
}

# ==== 3.5.2 bloqueio ====

scenario_sem_secao_delta_missing() {
  _spec=$(_write_spec '# Feature Spec: fixture

## Success Criteria
Nada aqui.')

  assert_exit 1 sh "$SCRIPT" "$_spec" --corpus-dir "$(_corpus_dir)" || return 1
  assert_stdout_contains "FINDING|error|delta-missing|" || return 1
  assert_stdout_contains "delta=missing|errors=1" || return 1
}

scenario_skip_invalido() {
  _spec=$(_write_spec '# Feature Spec: fixture

## Delta Requirements

**Skip**: sem autor nem data')

  assert_exit 1 sh "$SCRIPT" "$_spec" --corpus-dir "$(_corpus_dir)" || return 1
  assert_stdout_contains "FINDING|error|skip-invalid|" || return 1
}

scenario_skip_com_delta_simultaneo() {
  _spec=$(_write_spec '# Feature Spec: fixture

## Delta Requirements

**Skip**: justificativa valida — Jot, 2026-07-22

### Capability: sample-cap

#### ADDED

- **FR-010**: Novo requisito.')

  assert_exit 1 sh "$SCRIPT" "$_spec" --corpus-dir "$(_corpus_dir)" || return 1
  assert_stdout_contains "FINDING|error|skip-with-delta|" || return 1
}

scenario_secao_vazia_delta_empty() {
  _spec=$(_write_spec '# Feature Spec: fixture

## Delta Requirements

## Success Criteria
Nada aqui.')

  assert_exit 1 sh "$SCRIPT" "$_spec" --corpus-dir "$(_corpus_dir)" || return 1
  assert_stdout_contains "FINDING|error|delta-empty|" || return 1
}

scenario_entrada_malformada() {
  _spec=$(_write_spec '# Feature Spec: fixture

## Delta Requirements

### Capability: sample-cap

#### ADDED

texto solto sem marcador de entrada')

  assert_exit 1 sh "$SCRIPT" "$_spec" --corpus-dir "$(_corpus_dir)" || return 1
  assert_stdout_contains "FINDING|error|entry-malformed|" || return 1
}

# ==== 3.5.1 skip valido isolado (complementa happy-path) ====

scenario_skip_valido_isolado_exit0() {
  _spec=$(_write_spec '# Feature Spec: fixture

## Delta Requirements

**Skip**: feature pure-doc sem capability tocada — Jot, 2026-07-22')

  assert_exit 0 sh "$SCRIPT" "$_spec" --corpus-dir "$(_corpus_dir)" || return 1
  assert_stdout_not_contains "FINDING|" || return 1
  assert_stdout_contains "delta=skip|errors=0" || return 1
}

# ==== 3.5.3 referencial ====

scenario_ref_not_found_modified() {
  _write_corpus_file "sample-cap" "$_BASE_CORPUS"
  _spec=$(_write_spec '# Feature Spec: fixture

## Delta Requirements

### Capability: sample-cap

#### MODIFIED

- **FR-999**: texto.')

  assert_exit 1 sh "$SCRIPT" "$_spec" --corpus-dir "$(_corpus_dir)" || return 1
  assert_stdout_contains "FINDING|error|ref-not-found|" || return 1
}

scenario_ref_not_found_removed() {
  _write_corpus_file "sample-cap" "$_BASE_CORPUS"
  _spec=$(_write_spec '# Feature Spec: fixture

## Delta Requirements

### Capability: sample-cap

#### REMOVED

- **FR-999**: motivo.')

  assert_exit 1 sh "$SCRIPT" "$_spec" --corpus-dir "$(_corpus_dir)" || return 1
  assert_stdout_contains "FINDING|error|ref-not-found|" || return 1
}

scenario_ref_not_found_renamed() {
  _write_corpus_file "sample-cap" "$_BASE_CORPUS"
  _spec=$(_write_spec '# Feature Spec: fixture

## Delta Requirements

### Capability: sample-cap

#### RENAMED

- **FR-999 -> FR-020**')

  assert_exit 1 sh "$SCRIPT" "$_spec" --corpus-dir "$(_corpus_dir)" || return 1
  assert_stdout_contains "FINDING|error|ref-not-found|" || return 1
}

scenario_added_collision() {
  _write_corpus_file "sample-cap" "$_BASE_CORPUS"
  _spec=$(_write_spec '# Feature Spec: fixture

## Delta Requirements

### Capability: sample-cap

#### ADDED

- **FR-001**: duplicado.')

  assert_exit 1 sh "$SCRIPT" "$_spec" --corpus-dir "$(_corpus_dir)" || return 1
  assert_stdout_contains "FINDING|error|added-collision|" || return 1
}

scenario_renamed_target_exists() {
  _write_corpus_file "sample-cap" "$_BASE_CORPUS"
  _spec=$(_write_spec '# Feature Spec: fixture

## Delta Requirements

### Capability: sample-cap

#### RENAMED

- **FR-002 -> FR-003**')

  assert_exit 1 sh "$SCRIPT" "$_spec" --corpus-dir "$(_corpus_dir)" || return 1
  assert_stdout_contains "FINDING|error|renamed-target-exists|" || return 1
}

# ==== 3.5.4 corpus-malformed (CHK034: bloqueia antes de checar referencias) ====

scenario_corpus_malformed_bloqueia_antes_de_referencial() {
  _write_corpus_file "sample-cap" '# Capability: sample-cap

## Requirements

### FR-001

texto

### FR-001

texto duplicado (heading repetido — corpus editado a mao)'

  _spec=$(_write_spec '# Feature Spec: fixture

## Delta Requirements

### Capability: sample-cap

#### MODIFIED

- **FR-999**: id que tambem seria ref-not-found se a checagem referencial rodasse.')

  assert_exit 1 sh "$SCRIPT" "$_spec" --corpus-dir "$(_corpus_dir)" || return 1
  assert_stdout_contains "FINDING|error|corpus-malformed|" || return 1
  assert_stdout_not_contains "ref-not-found" || return 1
}

# ==== 3.5.5 seguranca: slug hostil ====

scenario_slug_hostil_path_traversal() {
  _spec=$(_write_spec '# Feature Spec: fixture

## Delta Requirements

### Capability: ../escape

#### ADDED

- **FR-001**: x')

  assert_exit 1 sh "$SCRIPT" "$_spec" --corpus-dir "$(_corpus_dir)" || return 1
  assert_stdout_contains "FINDING|error|capability-slug-invalid|" || return 1
  # Nenhum path fora do corpus-dir foi tocado/lido — o teste antecipa que
  # o arquivo ../current/escape.md (fora de TMPDIR_TEST) jamais e referenciado
  # verificando ausencia de qualquer FINDING de corpus (malformed/missing)
  # para o slug hostil.
  assert_stdout_not_contains "corpus-missing" || return 1
}

scenario_slug_hostil_path_absoluto() {
  _spec=$(_write_spec '# Feature Spec: fixture

## Delta Requirements

### Capability: /etc/passwd

#### ADDED

- **FR-001**: x')

  assert_exit 1 sh "$SCRIPT" "$_spec" --corpus-dir "$(_corpus_dir)" || return 1
  assert_stdout_contains "FINDING|error|capability-slug-invalid|" || return 1
}

scenario_slug_hostil_com_espaco() {
  _spec=$(_write_spec '# Feature Spec: fixture

## Delta Requirements

### Capability: has space

#### ADDED

- **FR-001**: x')

  assert_exit 1 sh "$SCRIPT" "$_spec" --corpus-dir "$(_corpus_dir)" || return 1
  assert_stdout_contains "FINDING|error|capability-slug-invalid|" || return 1
}

# ==== 3.5.6 determinismo ====

scenario_determinismo_stdout_identico() {
  _write_corpus_file "sample-cap" "$_BASE_CORPUS"
  _spec=$(_write_spec '# Feature Spec: fixture

## Delta Requirements

### Capability: sample-cap

#### MODIFIED

- **FR-001**: Novo texto.

#### ADDED

- **FR-011**: Requisito novo.')

  capture sh "$SCRIPT" "$_spec" --corpus-dir "$(_corpus_dir)" || return 1
  _out1="$_CAPTURED_STDOUT"
  capture sh "$SCRIPT" "$_spec" --corpus-dir "$(_corpus_dir)" || return 1
  _out2="$_CAPTURED_STDOUT"
  if [ "$_out1" != "$_out2" ]; then
    _fail "determinismo" "stdout divergiu entre duas execucoes do mesmo input"
    return 1
  fi
  return 0
}

# ==== 3.5.7 uso incorreto ====

scenario_spec_md_inexistente() {
  assert_exit 2 sh "$SCRIPT" "$TMPDIR_TEST/nao-existe/spec.md" || return 1
  assert_stderr_contains "nao encontrado" || return 1
  assert_stderr_contains "DIAG|error|spec-not-found|" || return 1
}

scenario_corpus_dir_irresoluvel_sem_convencao() {
  _dest="$TMPDIR_TEST/random-name.md"
  printf '# Feature Spec: fixture\n' > "$_dest"

  assert_exit 2 sh "$SCRIPT" "$_dest" || return 1
  assert_stderr_contains "DIAG|error|corpus-dir-unresolvable|" || return 1
}

scenario_sem_argumentos() {
  assert_exit 2 sh "$SCRIPT" || return 1
  assert_stderr_contains "Uso:" || return 1
}

run_all_scenarios
