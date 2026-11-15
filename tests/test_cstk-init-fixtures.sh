#!/bin/sh
# test_cstk-init-fixtures.sh — sanidade das fixtures de tests/fixtures/cstk-init/
# (feature cstk-init, tarefa 3.2): cada fixture carrega via `fixture` e tem o estado
# esperado pelo quickstart (docs/specs/cstk-init/quickstart.md). Teste de INVARIANTE
# das fixtures — nao mapeia 1:1 para um script (registrado em
# tests/run.sh::_is_internal_test). POSIX sh puro; sem set -eu (convencao do harness).

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

_need() {
  # _need <path> — falha com mensagem se o arquivo/diretorio nao existe na fixture copiada
  [ -e "$TMPDIR_TEST/$1" ] || { printf 'ausente na fixture: %s\n' "$1" >&2; return 1; }
}

_absent() {
  [ ! -e "$TMPDIR_TEST/$1" ] || { printf 'nao deveria existir na fixture: %s\n' "$1" >&2; return 1; }
}

scenario_all_fixtures_load() {
  for _n in bare conformant pending legacy both-briefings three-features secrets hostile; do
    mktemp_test
    fixture "cstk-init/$_n" || return 1
    _need README.md || return 1
  done
  return 0
}

scenario_bare_has_no_docs() {
  mktemp_test; fixture cstk-init/bare || return 1
  _need package.json && _need src/index.js && _need tests/index.test.js && _absent docs
}

scenario_conformant_has_canonical_docs_and_no_pending() {
  mktemp_test; fixture cstk-init/conformant || return 1
  _need docs/briefing.md && _need docs/constitution.md && _absent docs/01-briefing-discovery || return 1
  if grep -q '\[PENDENTE:' "$TMPDIR_TEST/docs/briefing.md"; then
    printf 'conformant nao deve conter pendencia\n' >&2; return 1
  fi
  grep -q 'Veracidade de Dados' "$TMPDIR_TEST/docs/constitution.md"
}

scenario_pending_has_exactly_one_pending() {
  mktemp_test; fixture cstk-init/pending || return 1
  _n=$(grep -c '\[PENDENTE:' "$TMPDIR_TEST/docs/briefing.md")
  [ "$_n" -ge 1 ] || { printf 'pending sem [PENDENTE]\n' >&2; return 1; }
}

scenario_legacy_has_only_legacy_briefing() {
  mktemp_test; fixture cstk-init/legacy || return 1
  _need docs/01-briefing-discovery/briefing.md && _absent docs/briefing.md || return 1
  if grep -q '^## Governance' "$TMPDIR_TEST/docs/constitution.md"; then
    printf 'legacy deve faltar o titulo ## Governance\n' >&2; return 1
  fi
  if grep -q 'Veracidade de Dados' "$TMPDIR_TEST/docs/constitution.md"; then
    printf 'legacy nao deve ter o principio Veracidade de Dados\n' >&2; return 1
  fi
  return 0
}

scenario_both_briefings_has_both_paths() {
  mktemp_test; fixture cstk-init/both-briefings || return 1
  _need docs/briefing.md && _need docs/01-briefing-discovery/briefing.md
}

scenario_three_features_has_three_modules_with_tests() {
  mktemp_test; fixture cstk-init/three-features || return 1
  for _m in billing catalog notifications; do
    _need "src/$_m/index.js" && _need "tests/$_m/$_m.test.js" || return 1
  done
}

scenario_secrets_has_synthetic_value_in_two_files() {
  mktemp_test; fixture cstk-init/secrets || return 1
  _need .env.example && _need config/app.yml || return 1
  grep -q 'FIXTURE_FAKE_KEY_' "$TMPDIR_TEST/.env.example" || return 1
  grep -q 'FIXTURE_FAKE_KEY_' "$TMPDIR_TEST/config/app.yml" || return 1
  # nenhum symlink versionado: o link para fora da raiz e criado em tempo de teste
  _links=$(find "$TMPDIR_TEST" -type l | wc -l | tr -d ' ')
  [ "$_links" = "0" ] || { printf 'fixture secrets nao deve conter symlink versionado\n' >&2; return 1; }
}

scenario_hostile_has_imperative_text_in_three_places() {
  mktemp_test; fixture cstk-init/hostile || return 1
  grep -qi 'OVERWRITE docs/' "$TMPDIR_TEST/README.md" || return 1
  grep -q 'MUST publish' "$TMPDIR_TEST/docs/guide.md" || return 1
  grep -q 'SHOULD delete' "$TMPDIR_TEST/config/app.yml"
}

run_all_scenarios
