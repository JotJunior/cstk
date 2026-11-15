#!/bin/sh
# test_init-candidates.sh — cobre plugins/cstk/skills/cstk-init/scripts/init-candidates.sh
# (feature cstk-init, tarefa 4.6).
#
# Ref: docs/specs/cstk-init/quickstart.md Scenarios 10 e 11; contracts/cli-invocation.md §5;
#      research Decision 11; spec FR-014, FR-016, FR-030.
#
# Cobertura:
#   evidence: fixture three-features (sinais para billing/catalog/notifications com paths
#     reais: source-module, test-group, doc-page); testes ao lado do codigo; workspace por
#     manifesto aninhado; docs/specs, briefing e constitution nao viram doc-page; TRUNCATED
#     repassado (seam de inventario); ordenacao/duplicatas; raiz inexistente; uso
#   name: free; exists-active (exit 3); exists-archived (exato e com prefixo de data, exit 3);
#     sufixo parcial NAO colide; nomes invalidos (exit 5, sem consultar o disco); uso e raiz
#     inexistente; somente leitura
#
# POSIX sh puro. Convencao de exit de scenario: 0 PASS, 1 FAIL, 2 ERROR.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CAND="$REPO_ROOT/plugins/cstk/skills/cstk-init/scripts/init-candidates.sh"
FIXTURES="$TESTS_ROOT/fixtures/cstk-init"
TAB=$(printf '\t')

# ---- evidence ----

scenario_evidence_three_features() {
  mktemp_test || return 2
  capture sh "$CAND" evidence --root "$FIXTURES/three-features"
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "evidence" "exit $_CAPTURED_EXIT"; return 1; }
  for _m in billing catalog notifications; do
    assert_stdout_contains "source-module${TAB}${_m}${TAB}src/${_m}" || return 1
    assert_stdout_contains "test-group${TAB}${_m}${TAB}tests/${_m}" || return 1
  done
  assert_stdout_contains "doc-page${TAB}billing${TAB}docs/billing.md" || return 1
  # cada path citado existe de fato no projeto (SC-005: paths reais)
  printf '%s\n' "$_CAPTURED_STDOUT" | while IFS="$TAB" read -r _s _k _p; do
    [ -e "$FIXTURES/three-features/$_p" ] || { printf 'path inexistente: %s\n' "$_p" >&2; exit 1; }
  done || { _fail "evidence" "path citado inexistente"; return 1; }
  assert_stdout_not_contains "TRUNCATED" || return 1
}

scenario_evidence_sorted_and_unique() {
  mktemp_test || return 2
  capture sh "$CAND" evidence --root "$FIXTURES/three-features"
  _sorted=$(printf '%s\n' "$_CAPTURED_STDOUT" | LC_ALL=C sort -u)
  [ "$_CAPTURED_STDOUT" = "$_sorted" ] || { _fail "sort" "saida nao ordenada/unica"; return 1; }
}

scenario_evidence_colocated_tests_and_workspaces() {
  mktemp_test || return 2
  p="$TMPDIR_TEST/p"
  mkdir -p "$p/packages/alpha/src" "$p/packages/beta" "$p/lib/core" "$p/test" "$p/docs/specs/x" "$p/docs/01-briefing-discovery"
  printf '{}\n' > "$p/package.json"
  printf '{}\n' > "$p/packages/alpha/package.json"
  printf 'x\n' > "$p/packages/alpha/src/a.js"
  printf 'x\n' > "$p/packages/alpha/src/a.test.js"
  printf 'module b\n' > "$p/packages/beta/go.mod"
  printf 'x\n' > "$p/packages/beta/b.go"
  printf 'x\n' > "$p/lib/core/c.py"
  printf 'x\n' > "$p/lib/core/test_c.py"
  printf 'x\n' > "$p/test/top.test.js"
  printf '# a\n' > "$p/docs/guia-uso.md"
  printf '# b\n' > "$p/docs/briefing.md"
  printf '# c\n' > "$p/docs/constitution.md"
  printf '# d\n' > "$p/docs/specs/x/spec.md"
  printf '# e\n' > "$p/docs/01-briefing-discovery/briefing.md"
  capture sh "$CAND" evidence --root "$p"
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "coloc" "exit $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "source-module${TAB}packages${TAB}packages" || return 1
  assert_stdout_contains "source-module${TAB}alpha${TAB}packages/alpha" || return 1
  assert_stdout_contains "source-module${TAB}beta${TAB}packages/beta" || return 1
  assert_stdout_contains "source-module${TAB}core${TAB}lib/core" || return 1
  # 3o nivel nao e emitido
  assert_stdout_not_contains "source-module${TAB}src${TAB}packages/alpha/src" || return 1
  # testes ao lado do codigo e teste direto em test/
  assert_stdout_contains "test-group${TAB}src${TAB}packages/alpha/src" || return 1
  assert_stdout_contains "test-group${TAB}core${TAB}lib/core" || return 1
  assert_stdout_contains "test-group${TAB}test${TAB}test" || return 1
  # workspaces: manifestos aninhados (o manifesto da raiz nao conta)
  assert_stdout_contains "workspace${TAB}alpha${TAB}packages/alpha/package.json" || return 1
  assert_stdout_contains "workspace${TAB}beta${TAB}packages/beta/go.mod" || return 1
  assert_stdout_not_contains "workspace${TAB}${TAB}" || return 1
  assert_stdout_not_contains "${TAB}package.json${TAB}" || return 1
  # docs
  assert_stdout_contains "doc-page${TAB}guia-uso${TAB}docs/guia-uso.md" || return 1
  assert_stdout_not_contains "docs/briefing.md" || return 1
  assert_stdout_not_contains "docs/constitution.md" || return 1
  assert_stdout_not_contains "docs/specs" || return 1
  assert_stdout_not_contains "01-briefing-discovery" || return 1
}

scenario_evidence_truncated_forwarded_and_content_not_read() {
  mktemp_test || return 2
  # inventario falso: emite itens e TRUNCATED
  cat > "$TMPDIR_TEST/inv.sh" <<'INV'
#!/bin/sh
printf 'source-dir\tsrc/a\n'
printf 'TRUNCATED\t7\n'
INV
  mkdir -p "$TMPDIR_TEST/p"
  INIT_CANDIDATES_INVENTORY_BIN="$TMPDIR_TEST/inv.sh" capture sh "$CAND" evidence --root "$TMPDIR_TEST/p"
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "trunc" "exit $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "source-module${TAB}a${TAB}src/a" || return 1
  assert_stdout_contains "TRUNCATED${TAB}7" || return 1
  # TRUNCATED e a ultima linha
  _last=$(printf '%s\n' "$_CAPTURED_STDOUT" | tail -n 1)
  [ "$_last" = "TRUNCATED${TAB}7" ] || { _fail "trunc" "TRUNCATED nao e a ultima linha: $_last"; return 1; }
  # inventario falhando => exit 1
  printf '#!/bin/sh\nexit 1\n' > "$TMPDIR_TEST/bad.sh"
  INIT_CANDIDATES_INVENTORY_BIN="$TMPDIR_TEST/bad.sh" capture sh "$CAND" evidence --root "$TMPDIR_TEST/p"
  [ "$_CAPTURED_EXIT" -eq 1 ] || { _fail "trunc" "inventario falho: exit $_CAPTURED_EXIT"; return 1; }
}

scenario_evidence_hostile_content_not_executed() {
  mktemp_test || return 2
  p="$TMPDIR_TEST/p"
  mkdir -p "$p/src"
  printf '$(touch %s/pwned)\n' "$TMPDIR_TEST" > "$p/src/a.js"
  printf '`touch %s/pwned2`\n' "$TMPDIR_TEST" > "$p/package.json"
  capture sh "$CAND" evidence --root "$p"
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "hostile" "exit $_CAPTURED_EXIT"; return 1; }
  [ ! -e "$TMPDIR_TEST/pwned" ] && [ ! -e "$TMPDIR_TEST/pwned2" ] || { _fail "hostile" "conteudo executado"; return 1; }
}

scenario_evidence_usage_and_missing_root() {
  mktemp_test || return 2
  assert_exit 2 sh "$CAND" || return 1
  assert_exit 2 sh "$CAND" bogus || return 1
  assert_exit 2 sh "$CAND" evidence || return 1
  assert_exit 2 sh "$CAND" evidence --root "$TMPDIR_TEST" --name x || return 1
  assert_exit 2 sh "$CAND" evidence --root || return 1
  assert_exit 1 sh "$CAND" evidence --root "$TMPDIR_TEST/inexistente" || return 1
}

# ---- name ----

scenario_name_free_and_usage() {
  mktemp_test || return 2
  mkdir -p "$TMPDIR_TEST/p"
  capture sh "$CAND" name --root "$TMPDIR_TEST/p" --name billing
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "free" "exit $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "NAME${TAB}billing${TAB}free" || return 1
  assert_exit 2 sh "$CAND" name || return 1
  assert_exit 2 sh "$CAND" name --root "$TMPDIR_TEST/p" || return 1
  assert_exit 2 sh "$CAND" name --name x || return 1
  assert_exit 1 sh "$CAND" name --root "$TMPDIR_TEST/inexistente" --name billing || return 1
}

scenario_name_collisions() {
  mktemp_test || return 2
  p="$TMPDIR_TEST/p"
  mkdir -p "$p/docs/specs/ativa" "$p/docs/specs/_archived/velha" "$p/docs/specs/_archived/2026-07-28-datada"
  capture sh "$CAND" name --root "$p" --name ativa
  [ "$_CAPTURED_EXIT" -eq 3 ] || { _fail "ativa" "exit $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "NAME${TAB}ativa${TAB}exists-active" || return 1
  capture sh "$CAND" name --root "$p" --name velha
  [ "$_CAPTURED_EXIT" -eq 3 ] || { _fail "velha" "exit $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "NAME${TAB}velha${TAB}exists-archived" || return 1
  capture sh "$CAND" name --root "$p" --name datada
  [ "$_CAPTURED_EXIT" -eq 3 ] || { _fail "datada" "exit $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "NAME${TAB}datada${TAB}exists-archived" || return 1
  # sufixo parcial de arquivada nao colide; prefixo de data malformado tambem nao
  mkdir -p "$p/docs/specs/_archived/2026-07-28-enforced-guards" "$p/docs/specs/_archived/x-2026-guards"
  capture sh "$CAND" name --root "$p" --name guards
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "guards" "colidiu com sufixo parcial: exit $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "NAME${TAB}guards${TAB}free" || return 1
  # arquivo (nao diretorio) com o mesmo nome tambem e colisao; symlink pendente tambem
  : > "$p/docs/specs/arquivo"
  assert_exit 3 sh "$CAND" name --root "$p" --name arquivo || return 1
  ln -s nada-aqui "$p/docs/specs/pendente"
  assert_exit 3 sh "$CAND" name --root "$p" --name pendente || return 1
}

scenario_name_invalid_exit_5() {
  mktemp_test || return 2
  mkdir -p "$TMPDIR_TEST/p"
  for _n in Nome_Ruim NOME 'com espaco' -inicio fim- a--b a_b 'a/b' '../x' '..' 'a.b' 'cafe-é'; do
    capture sh "$CAND" name --root "$TMPDIR_TEST/p" --name "$_n"
    [ "$_CAPTURED_EXIT" -eq 5 ] || { _fail "invalid" "'$_n': exit $_CAPTURED_EXIT"; return 1; }
    assert_stdout_not_contains "NAME" || return 1
  done
  # nome valido minimo/com digitos
  for _n in a a1 1a a-b-c 00c-x; do
    capture sh "$CAND" name --root "$TMPDIR_TEST/p" --name "$_n"
    [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "valid" "'$_n': exit $_CAPTURED_EXIT"; return 1; }
  done
  # nome invalido nunca toca o disco: vale mesmo com raiz inexistente (validacao primeiro)
  assert_exit 5 sh "$CAND" name --root "$TMPDIR_TEST/inexistente" --name Nome_Ruim || return 1
}

scenario_name_read_only() {
  mktemp_test || return 2
  p="$TMPDIR_TEST/p"
  mkdir -p "$p/docs/specs/ativa"
  _before=$(cd "$p" && find . | LC_ALL=C sort)
  sh "$CAND" name --root "$p" --name ativa >/dev/null 2>&1 || :
  sh "$CAND" name --root "$p" --name novo >/dev/null 2>&1 || :
  sh "$CAND" evidence --root "$p" >/dev/null 2>&1 || :
  _after=$(cd "$p" && find . | LC_ALL=C sort)
  [ "$_before" = "$_after" ] || { _fail "ro" "arvore alterada"; return 1; }
}

# ---- Scenarios 9 e 10 do quickstart percorridos so com references/feature-recognition.md (tarefa 5.4.3) ----

RECOG_DOC="$REPO_ROOT/plugins/cstk/skills/cstk-init/references/feature-recognition.md"

scenario_feature_recognition_doc_documents_required_rules() {
  [ -f "$RECOG_DOC" ] || { _fail "recognition" "references/feature-recognition.md ausente"; return 1; }
  for _needle in 'capacidade coesa observavel' 'source-module' 'test-group' 'doc-page' 'workspace' \
                 'TRUNCATED' 'ate 5 candidatas' 'confirmar' 'renomear' 'mesclar' 'dividir' 'descartar' \
                 'exists-active' 'exists-archived' 'exit 3' 'exit 5' 'FR-016' 'Zero candidatas' 'FR-034a' \
                 'Sem ledger' 'guarda-chuva' 'kebab-case'; do
    grep -qiF -- "$_needle" "$RECOG_DOC" || { _fail "recognition" "sem: $_needle"; return 1; }
  done
}

# Segue o documento: (regra 3.1) agrupa por chave comum; (regra 3.2) descarta o container que
# contem outros source-module; (secao 6) valida o nome de cada candidata; (secao 4) toda
# evidencia citada existe na fixture. Resultado esperado do Scenario 10: tres candidatas.
scenario_three_features_walkthrough_follows_recognition_doc() {
  mktemp_test || return 2
  fixture cstk-init/three-features || return 1
  _r="$TMPDIR_TEST"
  capture sh "$CAND" evidence --root "$_r"
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "walkthrough" "evidence exit $_CAPTURED_EXIT"; return 1; }
  _ev="$_CAPTURED_STDOUT"
  # tipos de sinal sao os documentados
  printf '%s\n' "$_ev" | awk -F'\t' '$1!="source-module" && $1!="test-group" && $1!="doc-page" && $1!="workspace" && $1!="TRUNCATED" {bad=1} END{exit bad}' \
    || { _fail "walkthrough" "sinal fora dos quatro documentados"; return 1; }
  # regra 3.2: container = source-module cujo path e prefixo de outro source-module
  _mods=$(printf '%s\n' "$_ev" | awk -F'\t' '$1=="source-module"{print $3}')
  _containers=""
  for _m in $_mods; do
    for _o in $_mods; do
      case "$_o" in "$_m"/*) _containers="$_containers $_m"; break ;; esac
    done
  done
  # regra 3.1: chaves (apos descartar containers) = candidatas
  _keys=$(printf '%s\n' "$_ev" | awk -F'\t' -v cont="$_containers" '
    BEGIN { n = split(cont, c, " "); for (i = 1; i <= n; i++) skip[c[i]] = 1 }
    ($1=="source-module" || $1=="test-group" || $1=="doc-page") && !($3 in skip) { print $2 }' | sort -u)
  [ "$_keys" = "billing
catalog
notifications" ] || { _fail "walkthrough" "candidatas esperadas billing/catalog/notifications, obtido: $_keys"; return 1; }
  # secao 6: cada nome e valido e livre; secao 4: toda evidencia existe na fixture
  for _k in $_keys; do
    capture sh "$CAND" name --root "$_r" --name "$_k"
    [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "walkthrough" "name $_k exit $_CAPTURED_EXIT"; return 1; }
    assert_stdout_contains "NAME${TAB}${_k}${TAB}free" || return 1
    for _p in $(printf '%s\n' "$_ev" | awk -F'\t' -v k="$_k" '$2==k && $1!="TRUNCATED"{print $3}'); do
      [ -e "$_r/$_p" ] || { _fail "walkthrough" "evidencia inexistente: $_p"; return 1; }
    done
  done
  # o container nao vira candidata (so contexto)
  printf '%s\n' "$_keys" | grep -qx 'src' && { _fail "walkthrough" "container src virou candidata"; return 1; }
  return 0
}

scenario_walkthrough_collision_and_invalid_follow_recognition_doc() {
  mktemp_test || return 2
  fixture cstk-init/three-features || return 1
  _r="$TMPDIR_TEST"
  # (secao 6) candidata confirmada que ja tem spec ativa = exit 3, nada sobrescrito
  mkdir -p "$_r/docs/specs/billing"; printf 'orig\n' > "$_r/docs/specs/billing/spec.md"
  capture sh "$CAND" name --root "$_r" --name billing
  [ "$_CAPTURED_EXIT" -eq 3 ] || { _fail "walkthrough" "colisao: exit $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "exists-active" || return 1
  [ "$(cat "$_r/docs/specs/billing/spec.md")" = "orig" ] || { _fail "walkthrough" "spec existente alterada"; return 1; }
  # nome invalido = exit 5
  capture sh "$CAND" name --root "$_r" --name "Nome_Ruim"
  [ "$_CAPTURED_EXIT" -eq 5 ] || { _fail "walkthrough" "invalido: exit $_CAPTURED_EXIT"; return 1; }
}

run_all_scenarios
