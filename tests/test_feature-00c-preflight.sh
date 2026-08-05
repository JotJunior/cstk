#!/bin/sh
# test_feature-00c-preflight.sh — cobre feature-00c-preflight.sh
# (FR-010A, FR-PRE-004).
#
# Ref: docs/specs/_archived/feature-00c/tasks.md FASE 2 task 2.1.6

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/feature-00c-preflight.sh"
SCRIPTS_DIR="$REPO_ROOT/global/skills/agente-00c-runtime/scripts"

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

# ==== issue #77: path Windows drive-letter tratado como ABSOLUTO ====
# Execucao sob Git Bash grava prerequisites.*.path como "C:/Users/...".
# O case pattern antigo (/*) nao reconhecia esse formato como absoluto e
# concatenava com target_project_path ("<proj>/C:/Users/..."), gerando
# false-positive briefing_missing/constitution_missing que bloqueia o gate
# FR-010A em toda execucao. O path drive-letter nao existe no runner (o
# arquivo segue missing), mas o finding DEVE citar o path original SEM o
# prefixo do projeto — prova de que nao houve concatenacao.
scenario_check_path_windows_drive_letter_nao_concatena() {
  _sdir=$(_setup_fixture)
  _proj=$(dirname -- "$(dirname -- "$(dirname -- "$_sdir")")")
  _tmp=$(mktemp)
  jq '.prerequisites.briefing.path = "C:/Users/Op/proj/docs/01-briefing-discovery/briefing.md"
      | .prerequisites.constitution.path = "C:/Users/Op/proj/docs/constitution.md"' \
    "$_sdir/state.json" > "$_tmp" && mv "$_tmp" "$_sdir/state.json"
  capture "$SCRIPT" check --state-dir "$_sdir"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit" "esperado 1 (missing), obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains 'briefing_missing' || return 1
  assert_stdout_contains 'C:/Users/Op/proj' || return 1
  assert_stdout_not_contains "$_proj/C:" || return 1
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
  assert_stderr_contains "estado ausente" || return 1
}

# ==== backend sqlite (fix pos-6.2.1): check NAO pode ser inerte ====
# Bug de campo (meta-gob-ms): com state.db o preflight reportava
# "state.json ausente" e a validacao de drift FR-PRE-004 nunca rodava.

_fp_make_sqlite_state() {
  # $1=home sandbox  $2=state-dir  $3=projeto (com briefing/constitution)
  mkdir -p "$1/.claude/cstk"
  printf 'state_backend=sqlite\n' > "$1/.claude/cstk/config"
  mkdir -p "$3/docs/01-briefing-discovery"
  printf '# briefing de teste com conteudo suficiente\n' > "$3/docs/01-briefing-discovery/briefing.md"
  printf '# constitution de teste\n\n**Version**: 1.0.0\n' > "$3/docs/constitution.md"
  if command -v sha256sum >/dev/null 2>&1; then
    _fpms_br=$(sha256sum "$3/docs/01-briefing-discovery/briefing.md" | awk '{print $1}')
    _fpms_ct=$(sha256sum "$3/docs/constitution.md" | awk '{print $1}')
  else
    _fpms_br=$(shasum -a 256 "$3/docs/01-briefing-discovery/briefing.md" | awk '{print $1}')
    _fpms_ct=$(shasum -a 256 "$3/docs/constitution.md" | awk '{print $1}')
  fi
  env HOME="$1" sh "$SCRIPTS_DIR/state-rw.sh" init --state-dir "$2" \
    --short-name "sqlite-preflight" \
    --projeto-alvo-path "$3" \
    --descricao "descricao de teste com tamanho suficiente para validacao" \
    --briefing-path "$3/docs/01-briefing-discovery/briefing.md" --briefing-sha256 "$_fpms_br" \
    --constitution-path "$3/docs/constitution.md" --constitution-sha256 "$_fpms_ct" \
    --constitution-version "1.0.0" >/dev/null 2>&1
}

scenario_check_backend_sqlite_valida_ok() {
  command -v sqlite3 >/dev/null 2>&1 || { printf '# skip: sqlite3 indisponivel\n'; return 0; }
  _h="$TMPDIR_TEST/home-sq1"
  _sd="$TMPDIR_TEST/sq1-state"
  _pj="$TMPDIR_TEST/sq1-proj"
  _fp_make_sqlite_state "$_h" "$_sd" "$_pj" || { _error "fixture" "init sqlite falhou"; return 2; }
  [ -f "$_sd/state.db" ] || { _error "fixture" "state.db nao criado (config nao aplicou?)"; return 2; }
  [ ! -f "$_sd/state.json" ] || { _error "fixture" "state.json presente — cenario invalido"; return 2; }
  capture env HOME="$_h" "$SCRIPT" check --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit sqlite ok" "esperado 0, obtido $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains '"ok": true' || return 1
}

scenario_check_backend_sqlite_detecta_drift() {
  command -v sqlite3 >/dev/null 2>&1 || { printf '# skip: sqlite3 indisponivel\n'; return 0; }
  _h="$TMPDIR_TEST/home-sq2"
  _sd="$TMPDIR_TEST/sq2-state"
  _pj="$TMPDIR_TEST/sq2-proj"
  _fp_make_sqlite_state "$_h" "$_sd" "$_pj" || { _error "fixture" "init sqlite falhou"; return 2; }
  # Muta o briefing DEPOIS do init: o check deve reportar drift (a prova de
  # que a validacao deixou de ser inerte sob sqlite).
  printf '\nconteudo novo pos-init\n' >> "$_pj/docs/01-briefing-discovery/briefing.md"
  capture env HOME="$_h" "$SCRIPT" check --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit sqlite drift" "esperado 1 (findings), obtido $_CAPTURED_EXIT: $_CAPTURED_STDOUT"; return 1; }
  assert_stdout_contains 'briefing' || return 1
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
