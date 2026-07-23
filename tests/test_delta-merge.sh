#!/bin/sh
# test_delta-merge.sh —
# cobre global/skills/review-features/scripts/delta-merge.sh.
#
# Contrato: docs/specs/living-specs/contracts/delta-merge-cli.md
#   delta-merge.sh SPEC_MD --feature NAME [--corpus-dir DIR]
#     [--date YYYY-MM-DD] [--dry-run]
#     Emite FINDING|<severity>|<code>|<mensagem> e um
#     RESULT|<spec>|delta=<applied|skip|blocked>|added=<N>|modified=<N>|
#     removed=<N>|renamed=<N>.
#     Exit: 0 aplicado (ou dry-run valido, ou skip); 1 bloqueado; 2 uso incorreto.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/global/skills/review-features/scripts/delta-merge.sh"

_write_spec() {
  _dest="$TMPDIR_TEST/spec.md"
  printf '%s\n' "$1" > "$_dest"
  printf '%s' "$_dest"
}

_corpus_dir() {
  printf '%s/current' "$TMPDIR_TEST"
}

_write_corpus_file() {
  _cd=$(_corpus_dir)
  mkdir -p "$_cd"
  printf '%s\n' "$2" > "$_cd/$1.md"
}

_BASE_CORPUS='# Capability: sample-cap

## Requirements

### FR-001

Texto do requisito 1.

*Introduzida por: feat-orig (2026-01-01)*

### FR-002

Texto do requisito 2.

*Introduzida por: feat-orig (2026-01-01)*'

# ==== 3.9.1 happy path ADDED: corpus inexistente => criado ====

scenario_added_cria_corpus_com_provenencia() {
  _spec=$(_write_spec '# Feature Spec: fixture

## Delta Requirements

### Capability: sample-cap

#### ADDED

- **FR-001**: Requisito inaugural.')

  assert_exit 0 sh "$SCRIPT" "$_spec" --feature feat-x --corpus-dir "$(_corpus_dir)" --date 2026-07-22 || return 1
  assert_stdout_contains "delta=applied|added=1|modified=0|removed=0|renamed=0" || return 1

  _corpus_file="$(_corpus_dir)/sample-cap.md"
  [ -f "$_corpus_file" ] || { _fail "arquivo_nao_criado" "$_corpus_file ausente"; return 1; }
  case "$(cat "$_corpus_file")" in
    *"### FR-001"*"Requisito inaugural."*"Introduzida por: feat-x (2026-07-22)"*) : ;;
    *) _fail "conteudo_incorreto" "arquivo criado sem os campos esperados"; return 1 ;;
  esac
}

# ==== 3.9.2 MODIFIED/REMOVED sobre corpus existente ====

scenario_modified_preserva_id_atualiza_texto() {
  _write_corpus_file "sample-cap" "$_BASE_CORPUS"
  _spec=$(_write_spec '# Feature Spec: fixture

## Delta Requirements

### Capability: sample-cap

#### MODIFIED

- **FR-001**: Texto atualizado.')

  assert_exit 0 sh "$SCRIPT" "$_spec" --feature feat-y --corpus-dir "$(_corpus_dir)" --date 2026-07-23 || return 1
  assert_stdout_contains "delta=applied|added=0|modified=1|removed=0|renamed=0" || return 1

  _content=$(cat "$(_corpus_dir)/sample-cap.md")
  case "$_content" in
    *"### FR-001"*"Texto atualizado."*"Introduzida por: feat-orig (2026-01-01)"*"Ultima modificacao: feat-y (2026-07-23)"*) : ;;
    *) _fail "modified_incorreto" "id/provenencia nao preservados corretamente: $_content"; return 1 ;;
  esac
}

scenario_removed_move_para_removed_requirements_com_motivo() {
  _write_corpus_file "sample-cap" "$_BASE_CORPUS"
  _spec=$(_write_spec '# Feature Spec: fixture

## Delta Requirements

### Capability: sample-cap

#### REMOVED

- **FR-002**: nao e mais necessario.')

  assert_exit 0 sh "$SCRIPT" "$_spec" --feature feat-z --corpus-dir "$(_corpus_dir)" --date 2026-07-24 || return 1
  assert_stdout_contains "delta=applied|added=0|modified=0|removed=1|renamed=0" || return 1

  _content=$(cat "$(_corpus_dir)/sample-cap.md")
  case "$_content" in
    *"## Removed Requirements"*"### FR-002 [REMOVED]"*"Removida por: feat-z (2026-07-24)"*"— nao e mais necessario."*) : ;;
    *) _fail "removed_incorreto" "entrada nao movida corretamente: $_content"; return 1 ;;
  esac
  case "$_content" in
    *"### FR-002"$'\n'*)
      if printf '%s\n' "$_content" | grep -q '^## Requirements$'; then
        _reqsec=$(printf '%s\n' "$_content" | awk '/^## Requirements$/,/^## Removed Requirements$/')
        case "$_reqsec" in
          *"### FR-002"*) _fail "removed_ainda_ativo" "FR-002 ainda aparece em Requirements"; return 1 ;;
        esac
      fi
      ;;
  esac
}

# ==== 3.9.3 skip: no-op declarado ====

scenario_skip_no_op_corpus_intacto() {
  _write_corpus_file "sample-cap" "$_BASE_CORPUS"
  _corpus_file="$(_corpus_dir)/sample-cap.md"
  _before=$(cksum "$_corpus_file")

  _spec=$(_write_spec '# Feature Spec: fixture

## Delta Requirements

**Skip**: feature pure-doc — Jot, 2026-07-22')

  assert_exit 0 sh "$SCRIPT" "$_spec" --feature feat-skip --corpus-dir "$(_corpus_dir)" || return 1
  assert_stdout_contains "delta=skip|added=0|modified=0|removed=0|renamed=0" || return 1

  _after=$(cksum "$_corpus_file")
  [ "$_before" = "$_after" ] || { _fail "corpus_mudou" "skip deveria ser no-op"; return 1; }
}

# ==== 3.9.4 atomicidade: erro na 2a capability bloqueia TUDO ====

scenario_atomicidade_erro_2a_capability_bloqueia_tudo() {
  _write_corpus_file "cap-a" "# Capability: cap-a

## Requirements

### FR-001

Texto A.

*Introduzida por: orig (2026-01-01)*"
  _cap_a_file="$(_corpus_dir)/cap-a.md"
  _before_a=$(cksum "$_cap_a_file")

  _spec=$(_write_spec '# Feature Spec: multi

## Delta Requirements

### Capability: cap-a

#### MODIFIED

- **FR-001**: Texto A atualizado.

### Capability: cap-b

#### MODIFIED

- **FR-999**: id inexistente, deve bloquear tudo.')

  assert_exit 1 sh "$SCRIPT" "$_spec" --feature multi-feat --corpus-dir "$(_corpus_dir)" || return 1
  assert_stdout_contains "delta=blocked|added=0|modified=0|removed=0|renamed=0" || return 1

  _after_a=$(cksum "$_cap_a_file")
  [ "$_before_a" = "$_after_a" ] || { _fail "cap_a_mudou" "cap-a deveria permanecer intocado (atomicidade multi-capability)"; return 1; }
  [ -f "$(_corpus_dir)/cap-b.md" ] && { _fail "cap_b_criado" "cap-b.md nao deveria ter sido criado"; return 1; }
  return 0
}

# ==== 3.9.5 --dry-run: contagens corretas, zero escrita ====

scenario_dry_run_reporta_contagens_sem_escrever() {
  _write_corpus_file "sample-cap" "$_BASE_CORPUS"
  _corpus_file="$(_corpus_dir)/sample-cap.md"
  _before=$(cksum "$_corpus_file")

  _spec=$(_write_spec '# Feature Spec: fixture

## Delta Requirements

### Capability: sample-cap

#### ADDED

- **FR-010**: novo requisito dry-run.')

  assert_exit 0 sh "$SCRIPT" "$_spec" --feature feat-dry --corpus-dir "$(_corpus_dir)" --dry-run || return 1
  assert_stdout_contains "delta=applied|added=1|modified=0|removed=0|renamed=0" || return 1

  _after=$(cksum "$_corpus_file")
  [ "$_before" = "$_after" ] || { _fail "dry_run_escreveu" "dry-run nao deveria alterar o corpus"; return 1; }
}

# ==== 3.9.6 corpus-malformed bloqueia o merge (nao so o gate) ====

scenario_corpus_malformed_bloqueia_merge() {
  _write_corpus_file "broken" '# Capability: broken

## Requirements

### FR-001

texto

### FR-001

duplicado (corpus editado a mao)'
  _broken_file="$(_corpus_dir)/broken.md"
  _before=$(cksum "$_broken_file")

  _spec=$(_write_spec '# Feature Spec: fixture

## Delta Requirements

### Capability: broken

#### MODIFIED

- **FR-001**: novo texto.')

  assert_exit 1 sh "$SCRIPT" "$_spec" --feature feat-broken --corpus-dir "$(_corpus_dir)" || return 1
  assert_stdout_contains "FINDING|error|corpus-malformed|" || return 1

  _after=$(cksum "$_broken_file")
  [ "$_before" = "$_after" ] || { _fail "corpus_malformed_mudou" "corpus malformado deveria permanecer intacto"; return 1; }
}

# ==== 3.9.7 determinismo: mesmos inputs => corpus resultante byte-identico ====

scenario_determinismo_dois_merges_mesmo_resultado() {
  _spec=$(_write_spec '# Feature Spec: fixture

## Delta Requirements

### Capability: det-cap

#### ADDED

- **FR-001**: um.

#### ADDED

- **FR-002**: dois.')

  _dir1="$TMPDIR_TEST/run1"
  _dir2="$TMPDIR_TEST/run2"
  mkdir -p "$_dir1" "$_dir2"

  assert_exit 0 sh "$SCRIPT" "$_spec" --feature feat-det --corpus-dir "$_dir1" --date 2026-07-22 || return 1
  assert_exit 0 sh "$SCRIPT" "$_spec" --feature feat-det --corpus-dir "$_dir2" --date 2026-07-22 || return 1

  cmp -s "$_dir1/det-cap.md" "$_dir2/det-cap.md" || { _fail "nao_deterministico" "corpus resultante divergiu entre duas execucoes"; return 1; }
}

# ==== RENAMED: heading migra, tabela ganha linha ====

scenario_renamed_migra_heading_e_registra_tabela() {
  _write_corpus_file "sample-cap" "$_BASE_CORPUS"
  _spec=$(_write_spec '# Feature Spec: fixture

## Delta Requirements

### Capability: sample-cap

#### RENAMED

- **FR-001 -> FR-100**')

  assert_exit 0 sh "$SCRIPT" "$_spec" --feature feat-ren --corpus-dir "$(_corpus_dir)" --date 2026-07-25 || return 1
  assert_stdout_contains "delta=applied|added=0|modified=0|removed=0|renamed=1" || return 1

  _content=$(cat "$(_corpus_dir)/sample-cap.md")
  case "$_content" in
    *"### FR-100"*"## Renamed Identifiers"*"| FR-001 | FR-100 | feat-ren | 2026-07-25 |"*) : ;;
    *) _fail "renamed_incorreto" "heading/tabela nao migrados corretamente: $_content"; return 1 ;;
  esac
  case "$_content" in
    *"### FR-001"$'\n'*) _fail "old_id_ainda_presente" "FR-001 nao deveria mais existir como heading ativo"; return 1 ;;
  esac
}

# ==== uso incorreto ====

scenario_feature_ausente() {
  _spec=$(_write_spec '# Feature Spec: fixture

## Delta Requirements

**Skip**: x — Jot, 2026-07-22')

  assert_exit 2 sh "$SCRIPT" "$_spec" --corpus-dir "$(_corpus_dir)" || return 1
  assert_stderr_contains "DIAG|error|feature-missing|" || return 1
}

scenario_spec_md_inexistente() {
  assert_exit 2 sh "$SCRIPT" "$TMPDIR_TEST/nao-existe/spec.md" --feature x || return 1
  assert_stderr_contains "DIAG|error|spec-not-found|" || return 1
}

run_all_scenarios
