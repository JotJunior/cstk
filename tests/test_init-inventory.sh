#!/bin/sh
# test_init-inventory.sh — cobre plugins/cstk/skills/cstk-init/scripts/init-inventory.sh
# (feature cstk-init, tarefa 4.2).
#
# Ref: docs/specs/cstk-init/quickstart.md Scenarios 8 (inventario) e 17 (symlink);
#      docs/specs/cstk-init/contracts/cli-invocation.md §3; data-model.md §InventoryItem.
#
# Cobertura:
#   Uso: sem args / subcomando desconhecido / sem --root / --max-items invalido -> exit 2;
#     --help documenta o default 1000 (stdout, exit 0); raiz inexistente -> exit 1
#   Classificacao por caminho (bare, three-features, secrets) e lista de secret-bearing
#   Valor de configuracao ausente do stdout (fixture secrets)
#   Teto: --max-items + linha TRUNCATED com a contagem de omitidos; sem TRUNCATED abaixo do teto
#   Symlink para fora (diretorio, arquivo, pendente) -> symlink-escape sem vazar conteudo;
#     symlink interno valido nao e escape; symlink para diretorio interno e omitido
#   Diretorios ignorados; raiz chamada `build` nao e podada
#   Nomes hostis: espaco e '-' inicial listados; newline/TAB omitidos
#   Arquivo ilegivel (chmod 000) e listado sem erro (nunca le conteudo); saida deterministica
#
# POSIX sh puro. Convencao de exit de scenario: 0 PASS, 1 FAIL, 2 ERROR.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

INV="$REPO_ROOT/plugins/cstk/skills/cstk-init/scripts/init-inventory.sh"
TAB=$(printf '\t')
NL='
'

# ---- uso ----

scenario_usage_errors_exit_2() {
  mktemp_test || return 2
  assert_exit 2 sh "$INV" || return 1
  assert_exit 2 sh "$INV" bogus || return 1
  assert_exit 2 sh "$INV" inventory || return 1
  assert_exit 2 sh "$INV" inventory --root || return 1
  assert_exit 2 sh "$INV" inventory --root "$TMPDIR_TEST" --bogus || return 1
  assert_exit 2 sh "$INV" inventory --root "$TMPDIR_TEST" --max-items 0 || return 1
  assert_exit 2 sh "$INV" inventory --root "$TMPDIR_TEST" --max-items abc || return 1
  assert_exit 2 sh "$INV" inventory --root "$TMPDIR_TEST" --max-items -3 || return 1
  assert_exit 2 sh "$INV" inventory --root "$TMPDIR_TEST" --max-items || return 1
}

scenario_help_documents_default_cap() {
  mktemp_test || return 2
  assert_exit 0 sh "$INV" --help || return 1
  assert_stdout_contains "default 1000" || return 1
  assert_exit 0 sh "$INV" inventory --help || return 1
  assert_stdout_contains "default 1000" || return 1
}

scenario_missing_root_exit_1() {
  mktemp_test || return 2
  assert_exit 1 sh "$INV" inventory --root "$TMPDIR_TEST/inexistente" || return 1
}

# ---- classificacao ----

scenario_bare_exact_inventory() {
  mktemp_test || return 2
  fixture cstk-init/bare || return 2
  assert_exit 0 sh "$INV" inventory --root "$TMPDIR_TEST" || return 1
  _want="readme${TAB}README.md
manifest${TAB}package.json
source-dir${TAB}src
test${TAB}tests/index.test.js"
  [ "$_CAPTURED_STDOUT" = "$_want" ] || {
    _fail "bare_exact_inventory" "stdout difere do esperado"; return 1; }
}

scenario_three_features_lists_each_module_dir() {
  mktemp_test || return 2
  fixture cstk-init/three-features || return 2
  assert_exit 0 sh "$INV" inventory --root "$TMPDIR_TEST" || return 1
  for _m in billing catalog notifications; do
    assert_stdout_contains "source-dir${TAB}src/$_m" || return 1
    assert_stdout_contains "test${TAB}tests/$_m/$_m.test.js" || return 1
  done
  assert_stdout_contains "doc${TAB}docs/billing.md" || return 1
}

scenario_secrets_fixture_classifies_and_never_echoes_value() {
  mktemp_test || return 2
  fixture cstk-init/secrets || return 2
  assert_exit 0 sh "$INV" inventory --root "$TMPDIR_TEST" || return 1
  assert_stdout_contains "secret-bearing${TAB}.env.example" || return 1
  assert_stdout_contains "config${TAB}config/app.yml" || return 1
  assert_stdout_not_contains "FIXTURE_FAKE_KEY_" || return 1
  assert_stdout_not_contains "api_key" || return 1
  assert_stdout_not_contains "SERVICE_API_KEY" || return 1
}

scenario_secret_bearing_patterns() {
  mktemp_test || return 2
  mkdir "$TMPDIR_TEST/p"
  for _f in .env .env.local a.pem k.key id_rsa id_rsa.pub x.p12 credentials.json; do
    : > "$TMPDIR_TEST/p/$_f"
  done
  assert_exit 0 sh "$INV" inventory --root "$TMPDIR_TEST/p" || return 1
  for _f in .env .env.local a.pem k.key id_rsa id_rsa.pub x.p12 credentials.json; do
    assert_stdout_contains "secret-bearing${TAB}$_f" || return 1
  done
}

scenario_other_kinds() {
  mktemp_test || return 2
  mkdir -p "$TMPDIR_TEST/p/.github/workflows"
  : > "$TMPDIR_TEST/p/.github/workflows/ci.yml"
  : > "$TMPDIR_TEST/p/LICENSE"
  : > "$TMPDIR_TEST/p/CHANGELOG.md"
  : > "$TMPDIR_TEST/p/go.mod"
  : > "$TMPDIR_TEST/p/main.go"
  : > "$TMPDIR_TEST/p/notes.txt"
  assert_exit 0 sh "$INV" inventory --root "$TMPDIR_TEST/p" || return 1
  assert_stdout_contains "ci${TAB}.github/workflows/ci.yml" || return 1
  assert_stdout_contains "license${TAB}LICENSE" || return 1
  assert_stdout_contains "changelog${TAB}CHANGELOG.md" || return 1
  assert_stdout_contains "manifest${TAB}go.mod" || return 1
  assert_stdout_contains "source-dir${TAB}." || return 1
  assert_stdout_contains "doc${TAB}notes.txt" || return 1
}

# ---- teto ----

scenario_cap_truncates_with_omitted_count() {
  mktemp_test || return 2
  mkdir -p "$TMPDIR_TEST/p/docs"
  _i=1
  while [ "$_i" -le 12 ]; do
    : > "$TMPDIR_TEST/p/docs/d$(printf '%02d' "$_i").md"
    _i=$((_i + 1))
  done
  assert_exit 0 sh "$INV" inventory --root "$TMPDIR_TEST/p" --max-items 5 || return 1
  assert_stdout_contains "TRUNCATED${TAB}7" || return 1
  _n=$(printf '%s\n' "$_CAPTURED_STDOUT" | wc -l | tr -d ' ')
  [ "$_n" -eq 6 ] || { _fail "cap" "esperado 5 itens + TRUNCATED, obtido $_n linhas"; return 1; }
  # a linha TRUNCATED e a ultima
  _last=$(printf '%s\n' "$_CAPTURED_STDOUT" | tail -n 1)
  [ "$_last" = "TRUNCATED${TAB}7" ] || { _fail "cap" "TRUNCATED nao e a ultima linha"; return 1; }
  # no teto exato e abaixo dele: sem TRUNCATED
  assert_exit 0 sh "$INV" inventory --root "$TMPDIR_TEST/p" --max-items 12 || return 1
  assert_stdout_not_contains "TRUNCATED" || return 1
  assert_exit 0 sh "$INV" inventory --root "$TMPDIR_TEST/p" || return 1
  assert_stdout_not_contains "TRUNCATED" || return 1
}

# 7.5.3 — o teto limita o TRABALHO, nao so a saida: varredura para ao passar de 50 x --max-items
# arquivos visitados; o aviso em stderr cita visitados e teto, TRUNCATED e limite inferior (>= 1).
scenario_scan_budget_limits_work_not_only_output() {
  mktemp_test || return 2
  mkdir -p "$TMPDIR_TEST/p/docs"
  _i=1
  while [ "$_i" -le 400 ]; do
    : > "$TMPDIR_TEST/p/docs/d$_i.md"
    _i=$((_i + 1))
  done
  assert_exit 0 sh "$INV" inventory --root "$TMPDIR_TEST/p" --max-items 2 || return 1
  assert_stderr_contains "teto de varredura excedido" || return 1
  assert_stdout_contains "TRUNCATED${TAB}" || return 1
  _n=$(printf '%s\n' "$_CAPTURED_STDOUT" | wc -l | tr -d ' ')
  [ "$_n" -eq 3 ] || { _fail "budget" "esperado 2 itens + TRUNCATED, obtido $_n linhas"; return 1; }
  _vis=$(printf '%s\n' "$_CAPTURED_STDERR" | sed -n 's/.*visitados \([0-9][0-9]*\),.*/\1/p' | head -n 1)
  [ -n "$_vis" ] || { _fail "budget" "stderr sem a contagem de visitados"; return 1; }
  # teto = 50 x 2 = 100; o trabalho visitado fica no teto (nao nos 400 arquivos da arvore)
  [ "$_vis" -le 100 ] || { _fail "budget" "visitados=$_vis acima do teto de varredura (100)"; return 1; }
  # abaixo do teto de varredura a saida e a mesma de antes (contagem exata de omitidos)
  assert_exit 0 sh "$INV" inventory --root "$TMPDIR_TEST/p" --max-items 100 || return 1
  assert_stdout_contains "TRUNCATED${TAB}300" || return 1
}

# 7.5.4 — erro do find (permissao negada) nao gera inventario parcial silencioso.
scenario_find_permission_error_is_visible() {
  mktemp_test || return 2
  if [ "$(id -u)" -eq 0 ]; then return 0; fi # root le tudo: cenario nao aplicavel
  mkdir -p "$TMPDIR_TEST/p/docs" "$TMPDIR_TEST/p/secret"
  : > "$TMPDIR_TEST/p/docs/a.md"
  : > "$TMPDIR_TEST/p/secret/b.md"
  chmod 000 "$TMPDIR_TEST/p/secret"
  assert_exit 0 sh "$INV" inventory --root "$TMPDIR_TEST/p"
  _rc=$?
  chmod 755 "$TMPDIR_TEST/p/secret"
  [ "$_rc" -eq 0 ] || return 1
  assert_stdout_contains "doc${TAB}docs/a.md" || return 1
  assert_stdout_contains "TRUNCATED${TAB}" || return 1
  assert_stderr_contains "varredura com erro" || return 1
}

# 7.5.4 — emissor ausente/quebrado (find -exec devolve != 0) tambem fica visivel.
scenario_emitter_failure_is_visible() {
  mktemp_test || return 2
  mkdir -p "$TMPDIR_TEST/p/docs" "$TMPDIR_TEST/stub"
  : > "$TMPDIR_TEST/p/docs/a.md"
  printf '#!/bin/sh\nexit 1\n' > "$TMPDIR_TEST/stub/sh"
  chmod +x "$TMPDIR_TEST/stub/sh"
  PATH="$TMPDIR_TEST/stub:$PATH" capture /bin/sh "$INV" inventory --root "$TMPDIR_TEST/p" || return 2
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "emitter" "exit $_CAPTURED_EXIT (esperado 0 com TRUNCATED)"; return 1; }
  assert_stdout_contains "TRUNCATED${TAB}" || return 1
  assert_stderr_contains "varredura com erro" || return 1
}

# ---- symlinks (Scenario 17) ----

scenario_symlink_escape_listed_not_followed() {
  mktemp_test || return 2
  fixture cstk-init/secrets || return 2
  _out=$(mktemp -d "${TMPDIR:-/tmp}/init-inv-out.XXXXXX") || return 2
  mkdir "$_out/sub"
  printf 'FIXTURE_FAKE_KEY_OUTSIDE\n' > "$_out/segredo.md"
  printf 'FIXTURE_FAKE_KEY_OUTSIDE\n' > "$_out/sub/inner.md"
  ln -s "$_out" "$TMPDIR_TEST/link-out"
  ln -s "$_out/segredo.md" "$TMPDIR_TEST/link-file.md"
  ln -s "../../nao-existe-fora" "$TMPDIR_TEST/link-dangling"
  ln -s "README.md" "$TMPDIR_TEST/link-inside.md"
  ln -s "src" "$TMPDIR_TEST/link-dir-inside"
  ln -s "nao-existe-dentro.md" "$TMPDIR_TEST/link-dangling-inside.md"
  capture sh "$INV" inventory --root "$TMPDIR_TEST"
  rm -rf "$_out"
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "symlink" "exit $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "symlink-escape${TAB}link-out" || return 1
  assert_stdout_contains "symlink-escape${TAB}link-file.md" || return 1
  assert_stdout_contains "symlink-escape${TAB}link-dangling" || return 1
  assert_stdout_not_contains "inner.md" || return 1
  assert_stdout_not_contains "segredo.md" || return 1
  assert_stdout_not_contains "FIXTURE_FAKE_KEY_OUTSIDE" || return 1
  # symlink interno valido: classificado pelo nome do link, nunca escape
  assert_stdout_contains "doc${TAB}link-inside.md" || return 1
  assert_stdout_not_contains "link-dir-inside" || return 1
  assert_stdout_not_contains "link-dangling-inside" || return 1
}

scenario_symlink_loop_is_escape() {
  mktemp_test || return 2
  mkdir "$TMPDIR_TEST/p"
  ln -s b "$TMPDIR_TEST/p/a"
  ln -s a "$TMPDIR_TEST/p/b"
  assert_exit 0 sh "$INV" inventory --root "$TMPDIR_TEST/p" || return 1
  assert_stdout_contains "symlink-escape${TAB}a" || return 1
}

# ---- ignorados e nomes hostis ----

scenario_ignored_dirs_and_build_root() {
  mktemp_test || return 2
  mkdir -p "$TMPDIR_TEST/build"
  for _d in .git node_modules vendor dist build .venv target .claude; do
    mkdir -p "$TMPDIR_TEST/build/sub/$_d"
    : > "$TMPDIR_TEST/build/sub/$_d/lixo.md"
    : > "$TMPDIR_TEST/build/sub/$_d/.env"
  done
  : > "$TMPDIR_TEST/build/sub/ok.md"
  assert_exit 0 sh "$INV" inventory --root "$TMPDIR_TEST/build" || return 1
  assert_stdout_contains "doc${TAB}sub/ok.md" || return 1
  assert_stdout_not_contains "lixo.md" || return 1
  assert_stdout_not_contains "secret-bearing" || return 1
}

scenario_hostile_names() {
  mktemp_test || return 2
  mkdir "$TMPDIR_TEST/p"
  : > "$TMPDIR_TEST/p/my notes.md"
  : > "$TMPDIR_TEST/p/-lead.md"
  : > "$TMPDIR_TEST/p/nl${NL}name.md"
  : > "$TMPDIR_TEST/p/tab${TAB}name.md"
  assert_exit 0 sh "$INV" inventory --root "$TMPDIR_TEST/p" || return 1
  assert_stdout_contains "doc${TAB}my notes.md" || return 1
  assert_stdout_contains "doc${TAB}-lead.md" || return 1
  assert_stdout_not_contains "name.md" || return 1
  # cada linha tem exatamente um TAB (TSV integro)
  _bad=$(printf '%s\n' "$_CAPTURED_STDOUT" | awk -F'\t' 'NF != 2' | wc -l | tr -d ' ')
  [ "$_bad" -eq 0 ] || { _fail "hostile" "linha com numero de campos != 2"; return 1; }
}

scenario_unreadable_file_listed_without_reading() {
  mktemp_test || return 2
  mkdir "$TMPDIR_TEST/p"
  printf 'FIXTURE_FAKE_KEY_X\n' > "$TMPDIR_TEST/p/.env"
  chmod 000 "$TMPDIR_TEST/p/.env"
  capture sh "$INV" inventory --root "$TMPDIR_TEST/p"
  chmod 644 "$TMPDIR_TEST/p/.env"
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "unreadable" "exit $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "secret-bearing${TAB}.env" || return 1
  assert_stdout_not_contains "FIXTURE_FAKE_KEY_X" || return 1
}

scenario_output_is_deterministic_and_sorted() {
  mktemp_test || return 2
  fixture cstk-init/three-features || return 2
  capture sh "$INV" inventory --root "$TMPDIR_TEST"
  _a=$_CAPTURED_STDOUT
  capture sh "$INV" inventory --root "$TMPDIR_TEST"
  [ "$_a" = "$_CAPTURED_STDOUT" ] || { _fail "determinism" "duas execucoes diferem"; return 1; }
  _paths=$(printf '%s\n' "$_a" | cut -f2)
  _sorted=$(printf '%s\n' "$_paths" | LC_ALL=C sort)
  [ "$_paths" = "$_sorted" ] || { _fail "sorted" "saida nao ordenada por path"; return 1; }
}

# ---- hardening 7.4 (owasp-security pos-implementacao) ----

scenario_secret_bearing_extended_patterns() {
  mktemp_test || return 2
  mkdir "$TMPDIR_TEST/p"
  for _f in secrets.yml service-account.json id_ed25519 .npmrc .netrc .envrc .pypirc db.pfx app.jks prod.tfvars .git-credentials; do
    : > "$TMPDIR_TEST/p/$_f"
  done
  assert_exit 0 sh "$INV" inventory --root "$TMPDIR_TEST/p" || return 1
  for _f in secrets.yml service-account.json id_ed25519 .npmrc .netrc .envrc .pypirc db.pfx app.jks prod.tfvars .git-credentials; do
    assert_stdout_contains "secret-bearing${TAB}$_f" || return 1
  done
}

scenario_control_chars_in_names_omitted() {
  mktemp_test || return 2
  mkdir "$TMPDIR_TEST/p"
  : > "$TMPDIR_TEST/p/ok.md"
  : > "$TMPDIR_TEST/p/$(printf 'esc\033[2Jname.md')"
  : > "$TMPDIR_TEST/p/$(printf 'cr\rname.md')"
  assert_exit 0 sh "$INV" inventory --root "$TMPDIR_TEST/p" || return 1
  assert_stdout_contains "doc${TAB}ok.md" || return 1
  assert_stdout_not_contains "name.md" || return 1
  case "$_CAPTURED_STDOUT" in
    *"$(printf '\033')"*) _fail "ctl" "ESC vazou no stdout"; return 1 ;;
  esac
}

run_all_scenarios
