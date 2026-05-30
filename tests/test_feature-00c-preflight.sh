#!/bin/sh
# test_feature-00c-preflight.sh — cobre feature-00c-preflight.sh
# (FR-010A, FR-PRE-004).
#
# Ref: docs/specs/_archived/feature-00c/tasks.md FASE 2 task 2.1.6

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/feature-00c-preflight.sh"

# Helper: cria fixture de projeto-alvo + state.json com hashes corretos.
# Imprime path do state-dir em stdout.
_setup_fixture() {
  _proj="$TMPDIR_TEST/proj"
  _sdir="$_proj/.claude/feature-00c-state/test-feature"
  mkdir -p "$_proj/docs/01-briefing-discovery" "$_proj/docs" "$_sdir"

  # Briefing
  cat > "$_proj/docs/01-briefing-discovery/briefing.md" <<'BR'
# Briefing
## Visao
Conteudo.
## Usuarios
Conteudo.
BR
  _br_sha=$(sha256sum "$_proj/docs/01-briefing-discovery/briefing.md" | awk '{print $1}')

  # Constitution
  cat > "$_proj/docs/constitution.md" <<'CT'
# Constitution
## Core Principles
### I. Principio Um
Corpo.
**Version**: 1.2.0
CT
  _ct_sha=$(sha256sum "$_proj/docs/constitution.md" | awk '{print $1}')

  # State.json (chaves EN — schema-en-migration)
  cat > "$_sdir/state.json" <<JSON
{
  "schema_version": "1.0.0",
  "execution": {
    "short_name": "test-feature",
    "target_project_path": "$_proj"
  },
  "prerequisites": {
    "briefing": {
      "path": "docs/01-briefing-discovery/briefing.md",
      "sha256": "$_br_sha"
    },
    "constitution": {
      "path": "docs/constitution.md",
      "sha256": "$_ct_sha",
      "version": "1.2.0"
    }
  }
}
JSON
  printf '%s' "$_sdir"
}

# Variante pt-BR do mesmo fixture: prova o reader-fallback (.en // .pt).
# Mantida apos a migracao schema-en (back-compat de states vivos pt-BR).
_setup_fixture_pt() {
  _proj="$TMPDIR_TEST/proj-pt"
  _sdir="$_proj/.claude/feature-00c-state/test-feature"
  mkdir -p "$_proj/docs/01-briefing-discovery" "$_proj/docs" "$_sdir"

  cat > "$_proj/docs/01-briefing-discovery/briefing.md" <<'BR'
# Briefing
## Visao
Conteudo.
## Usuarios
Conteudo.
BR
  _br_sha=$(sha256sum "$_proj/docs/01-briefing-discovery/briefing.md" | awk '{print $1}')

  cat > "$_proj/docs/constitution.md" <<'CT'
# Constitution
## Core Principles
### I. Principio Um
Corpo.
**Version**: 1.2.0
CT
  _ct_sha=$(sha256sum "$_proj/docs/constitution.md" | awk '{print $1}')

  cat > "$_sdir/state.json" <<JSON
{
  "schema_version": "1.0.0",
  "execucao": {
    "short_name": "test-feature",
    "projeto_alvo_path": "$_proj"
  },
  "pre_requisitos": {
    "briefing": {
      "path": "docs/01-briefing-discovery/briefing.md",
      "sha256": "$_br_sha"
    },
    "constitution": {
      "path": "docs/constitution.md",
      "sha256": "$_ct_sha",
      "version": "1.2.0"
    }
  }
}
JSON
  printf '%s' "$_sdir"
}

scenario_check_sem_drift_passa() {
  _sdir=$(_setup_fixture)
  capture "$SCRIPT" check --state-dir "$_sdir"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT; $_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains '"ok": true' || return 1
}

# Reader-fallback: state.json com chaves pt-BR (state vivo legado) ainda valida.
scenario_check_state_pt_br_fallback_passa() {
  _sdir=$(_setup_fixture_pt)
  capture "$SCRIPT" check --state-dir "$_sdir"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT; $_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains '"ok": true' || return 1
}

scenario_check_briefing_modificado_falha() {
  _sdir=$(_setup_fixture)
  _proj=$(dirname -- "$(dirname -- "$(dirname -- "$_sdir")")")
  # Modificar briefing apos hash gravado
  printf '\nLinha adicionada apos hash.\n' >> "$_proj/docs/01-briefing-discovery/briefing.md"
  capture "$SCRIPT" check --state-dir "$_sdir"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stdout_contains 'briefing_hash_drift' || return 1
  assert_stdout_contains '"ok": false' || return 1
}

scenario_check_constitution_minor_bump_warn() {
  _sdir=$(_setup_fixture)
  _proj=$(dirname -- "$(dirname -- "$(dirname -- "$_sdir")")")
  # Mudar constitution mantendo MAJOR=1 mas bumping MINOR
  cat > "$_proj/docs/constitution.md" <<'CT'
# Constitution
## Core Principles
### I. Principio Um
Corpo atualizado.
**Version**: 1.3.0
CT
  capture "$SCRIPT" check --state-dir "$_sdir"
  # MINOR drift = warn, mas _ok continua true... espera, releia spec.
  # Spec FR-PRE-004: "MAJOR = bloqueio obrigatorio; MINOR ou PATCH = aviso registrado".
  # No script: warn nao quebra ok=true.
  assert_stdout_contains 'constitution_hash_drift' || return 1
  assert_stdout_contains '"severity": "warn"' || return 1
  # MINOR = warn = ok deve ser true (apenas aviso)
  assert_stdout_contains '"ok": true' || return 1
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit MINOR" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_check_constitution_major_bump_error() {
  _sdir=$(_setup_fixture)
  _proj=$(dirname -- "$(dirname -- "$(dirname -- "$_sdir")")")
  # MAJOR bump = de 1.2.0 para 2.0.0
  cat > "$_proj/docs/constitution.md" <<'CT'
# Constitution
## Core Principles
### I. Principio Um
Corpo reescrito.
**Version**: 2.0.0
CT
  capture "$SCRIPT" check --state-dir "$_sdir"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "exit MAJOR" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stdout_contains 'constitution_major_drift' || return 1
  assert_stdout_contains '"severity": "error"' || return 1
  assert_stdout_contains '"ok": false' || return 1
}

scenario_check_state_dir_inexistente_falha() {
  capture "$SCRIPT" check --state-dir "/path/que/nao/existe"
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "nao existe" || return 1
}

scenario_check_sem_state_json_falha() {
  _sdir="$TMPDIR_TEST/empty-state-dir"
  mkdir -p "$_sdir"
  capture "$SCRIPT" check --state-dir "$_sdir"
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "state.json ausente" || return 1
}

scenario_uso_sem_argumentos() {
  capture "$SCRIPT"
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "USO" || return 1
}

run_all_scenarios
