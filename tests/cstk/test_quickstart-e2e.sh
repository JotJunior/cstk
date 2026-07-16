#!/bin/sh
# test_quickstart-e2e.sh — testes end-to-end do quickstart usando fixtures reais.
#
# Ref: docs/specs/cstk-cli/quickstart.md (Scenarios 1-13)
#      docs/specs/cstk-cli/spec.md SC-003 (byte-a-byte)
#      docs/specs/cstk-cli/tasks.md FASE 10.2
#
# Cobertura:
#   - SC-003 byte-a-byte: apos install/update bem-sucedidos, conteudo
#     instalado === conteudo do catalog (`diff -r`); este e o gap real
#     nao coberto por testes unitarios.
#   - Lifecycle smoke: install v0.1.0 -> list -> doctor -> update v0.2.0
#     -> verify mudanca em specify, demais clean. Valida composicao das
#     libs (install/update/list/doctor) e nao apenas cada uma isolada.
#   - Idempotencia (SC-002) end-to-end: 2x install do mesmo tarball nao
#     escreve no manifest na 2a vez (mtime preservado).
#
# Outras Scenarios do quickstart sao cobertos por testes per-lib — ver
# tasks.md §10.2 para mapeamento. Este arquivo e o complemento e2e que
# valida a composicao das libs com fixtures realistas (200KB vs 3-skill
# synthetic mocks dos outros testes).
#
# Pre-requisitos: tests/cstk/fixtures/regen.sh tem que ter rodado (ou
# fixtures pre-existentes). _ensure_fixtures regenera se ausentes.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CSTK_LIB="$REPO_ROOT/cli/lib"
FIXTURES_DIR="$TESTS_ROOT/cstk/fixtures"
V1_TARBALL="$FIXTURES_DIR/releases/v0.1.0/cstk-0.1.0.tar.gz"
V2_TARBALL="$FIXTURES_DIR/releases/v0.2.0/cstk-0.2.0.tar.gz"
export CSTK_LIB

# _ensure_fixtures: regenera se ausentes (CI fresh checkout).
_ensure_fixtures() {
  if [ -f "$V1_TARBALL" ] && [ -f "$V2_TARBALL" ]; then
    return 0
  fi
  if ! sh "$FIXTURES_DIR/regen.sh" >/dev/null 2>&1; then
    _error "fixtures" "regen.sh falhou — fixtures nao podem ser preparadas"
    return 2
  fi
  return 0
}

_run_cstk() {
  _rh="$1"; shift
  _libname="$1"; shift  # install | update | list | doctor
  capture env HOME="$_rh" CSTK_LIB="$CSTK_LIB" sh -c "
    . \"\$CSTK_LIB/${_libname}.sh\"
    ${_libname}_main \"\$@\"
  " "${_libname}_e2e" "$@"
}

# ==== Scenario 13 / SC-003: byte-a-byte ====
#
# Apos install (e apos update), cada skill clean (hash_dir == source_sha256
# armazenado) tem que ser BIT-IDENTICA ao staged catalog que veio na release.
# Tests per-lib comparam via hash; este teste roda diff -r literal.

scenario_e2e_install_byte_a_byte_match_catalog() {
  _ensure_fixtures || return 2

  _h="$TMPDIR_TEST/home"
  _stage="$TMPDIR_TEST/stage"
  mkdir -p "$_h" "$_stage"

  # Install
  _run_cstk "$_h" install --from "file://$V1_TARBALL" --profile sdd
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "install" "exit=$_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"
    return 1
  fi

  # Extrai o tarball para staging para diff -r
  tar -xzf "$V1_TARBALL" -C "$_stage"
  _catalog="$_stage/cstk-0.1.0/catalog/skills"

  # Para cada skill instalada, diff -r contra o catalog staged
  _failed=0
  _diffs=""
  for _sk_dir in "$_h/.claude/skills/"*/; do
    [ -d "$_sk_dir" ] || continue
    _sk=$(basename "${_sk_dir%/}")
    _src="$_catalog/$_sk"
    if [ ! -d "$_src" ]; then
      # Pode ser language-* skill, procurar sob language/
      _src=$(find "$_stage/cstk-0.1.0/catalog/language" -type d -name "$_sk" 2>/dev/null | head -1)
    fi
    if [ ! -d "$_src" ]; then
      _diffs="$_diffs\n  - $_sk: nao encontrada no catalog (orfa?)"
      _failed=$((_failed + 1))
      continue
    fi
    if ! _diff_out=$(diff -r "$_src" "${_sk_dir%/}" 2>&1); then
      _diffs="$_diffs\n  - $_sk: $_diff_out"
      _failed=$((_failed + 1))
    fi
  done

  if [ "$_failed" -gt 0 ]; then
    _fail "byte-a-byte SC-003" "$(printf '%b' "$_diffs")"
    return 1
  fi
}

# ==== Lifecycle smoke: install v0.1.0 -> update v0.2.0 ====

scenario_e2e_lifecycle_install_then_update_v0_2_0() {
  _ensure_fixtures || return 2

  _h="$TMPDIR_TEST/home"
  mkdir -p "$_h"

  # 1. Install v0.1.0
  _run_cstk "$_h" install --from "file://$V1_TARBALL" --profile sdd
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "install v1" "$_CAPTURED_STDERR"; return 1; }

  _mf="$_h/.claude/skills/.cstk-manifest"
  [ -f "$_mf" ] || { _fail "manifest ausente" ""; return 1; }

  # Confirma versao 0.1.0 no manifest (3a coluna nao, version e 2a)
  if ! awk -F'\t' '$2=="0.1.0"' "$_mf" | grep -q .; then
    _fail "manifest version v1" "$(cat "$_mf")"
    return 1
  fi

  # specify deve ter conteudo SEM o sentinel marker
  if grep -q 'v0.2.0-fixture-sentinel' "$_h/.claude/skills/specify/SKILL.md"; then
    _fail "specify v1 contem sentinel" "v0.1.0 nao deveria ter o marker"
    return 1
  fi

  # 2. Update para v0.2.0 — apenas specify deve ser updated
  _run_cstk "$_h" update --from "file://$V2_TARBALL"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "update v2" "$_CAPTURED_STDERR"; return 1; }

  # specify agora COM sentinel
  if ! grep -q 'v0.2.0-fixture-sentinel' "$_h/.claude/skills/specify/SKILL.md"; then
    _fail "specify v2 sem sentinel" "update nao aplicou conteudo novo"
    return 1
  fi

  # Manifest version atualizada para 0.2.0 (pelo menos para specify)
  if ! awk -F'\t' '$1=="specify" && $2=="0.2.0"' "$_mf" | grep -q .; then
    _fail "manifest specify v2" "$(grep '^specify' "$_mf")"
    return 1
  fi

  # Summary deve indicar pelo menos 1 updated
  case "$_CAPTURED_STDERR" in
    *"updated: 0"*) _fail "summary updated=0" "esperava >0"; return 1 ;;
  esac
}

# ==== Idempotencia (SC-002) end-to-end ====

scenario_e2e_install_2x_idempotent_no_writes() {
  _ensure_fixtures || return 2

  _h="$TMPDIR_TEST/home"
  mkdir -p "$_h"

  # 1st install
  _run_cstk "$_h" install --from "file://$V1_TARBALL" --profile sdd
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "1st install" "$_CAPTURED_STDERR"; return 1; }

  # Snapshot de mtime do manifest
  _mf="$_h/.claude/skills/.cstk-manifest"
  if command -v stat >/dev/null 2>&1; then
    _mtime_before=$(stat -c %Y "$_mf" 2>/dev/null || stat -f %m "$_mf")
  else
    _mtime_before=$(ls -l "$_mf" | awk '{print $6, $7, $8}')
  fi

  # Update sem mudanca: zero writes esperados (SC-002)
  sleep 1   # garantir que mtime mudaria se houvesse escrita
  _run_cstk "$_h" update --from "file://$V1_TARBALL"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "update idempotente" "$_CAPTURED_STDERR"; return 1; }

  if command -v stat >/dev/null 2>&1; then
    _mtime_after=$(stat -c %Y "$_mf" 2>/dev/null || stat -f %m "$_mf")
  else
    _mtime_after=$(ls -l "$_mf" | awk '{print $6, $7, $8}')
  fi

  if [ "$_mtime_before" != "$_mtime_after" ]; then
    _fail "SC-002 idempotencia" "manifest mtime mudou: $_mtime_before -> $_mtime_after"
    return 1
  fi

  # Summary deve confirmar zero updates
  case "$_CAPTURED_STDERR" in
    *"updated: 0"*) ;;
    *) _fail "summary nao reporta zero updates" "$_CAPTURED_STDERR"; return 1 ;;
  esac
}

# ==== Lifecycle: install -> list -> doctor (composicao das libs) ====

scenario_e2e_install_list_doctor_composition() {
  _ensure_fixtures || return 2

  _h="$TMPDIR_TEST/home"
  mkdir -p "$_h"

  # Install
  _run_cstk "$_h" install --from "file://$V1_TARBALL" --profile sdd
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "install" "$_CAPTURED_STDERR"; return 1; }

  # list deve enumerar as 17 skills do profile sdd (10 pipeline +
  # agente-00c-runtime infra + model-selector + review-features + 4
  # skills-gate; clean status). Count atrelado ao profile sdd em
  # scripts/profiles.txt.in — model-selector entrou em 7eecdb7 (11 -> 12);
  # review-features + gates (deps duras dos orquestradores) na revisao
  # 5.15.0 (12 -> 16); converge (gate incondicional, feature
  # skill-converge) na 5.20.0 (16 -> 17).
  _run_cstk "$_h" list --format tsv
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "list" "$_CAPTURED_STDERR"; return 1; }
  _count=$(printf '%s\n' "$_CAPTURED_STDOUT" | awk 'NF>0' | wc -l | awk '{print $1}')
  if [ "$_count" != 17 ]; then
    _fail "list count" "esperado 17, obtido $_count: $_CAPTURED_STDOUT"
    return 1
  fi
  # Todas devem estar clean
  if printf '%s\n' "$_CAPTURED_STDOUT" | awk -F'\t' '$3 != "clean" {print}' | grep -q .; then
    _fail "list nem todas clean" "$_CAPTURED_STDOUT"
    return 1
  fi

  # doctor sem drift -> exit 0
  _run_cstk "$_h" doctor
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "doctor sem drift" "exit=$_CAPTURED_EXIT $_CAPTURED_STDERR"; return 1; }

  # Sabotar uma skill (Scenario 10 mini) e re-rodar doctor -> exit 1 com EDITED
  echo '<!-- e2e edit sabotage -->' >> "$_h/.claude/skills/specify/SKILL.md"
  _run_cstk "$_h" doctor
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "doctor com edit local" "esperado exit 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  case "$_CAPTURED_STDOUT$_CAPTURED_STDERR" in
    *EDITED*) ;;
    *) _fail "doctor sem EDITED" "$_CAPTURED_STDOUT$_CAPTURED_STDERR"; return 1 ;;
  esac
}

# ==== Bootstrap script existe e e executavel ====

scenario_e2e_install_sh_e_executavel_no_fixture() {
  _ensure_fixtures || return 2
  for _v in v0.1.0 v0.2.0; do
    _is="$FIXTURES_DIR/releases/$_v/install.sh"
    [ -x "$_is" ] || { _fail "install.sh exec" "$_is nao executavel"; return 1; }
    # Smoke: --help nao implementado, mas o script deve ter shebang e nao
    # falhar em sintaxe.
    if ! sh -n "$_is" >/dev/null 2>&1; then
      _fail "install.sh syntax" "$_is"
      return 1
    fi
  done
}

run_all_scenarios
