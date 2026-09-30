#!/bin/sh
# test_orchestrator-slim-parity.sh — paridade deterministica dos prompts dos
# orquestradores (agente-00c-orchestrator e agente-00c-feature-orchestrator)
# contra o baseline 9f97e99, antes e depois de mover secoes para referencias.
#
# Ref: docs/specs/orchestrator-slim/spec.md FR-004, FR-006, FR-007, FR-016
#      docs/specs/orchestrator-slim/research.md Decision 8
#      docs/specs/orchestrator-slim/quickstart.md Cenarios 3 e 6
#
# Cobre (sobre o CORPUS = prompt-base + referencias existentes, por
# orquestrador):
#   1. preservacao de linhas: todo linha nao-vazia do baseline esta no corpus,
#      salvo as listadas em rewritten-lines.tsv (referencias internas
#      reescritas — FR-004 ii);
#   2. blocos de comando: invocacoes `<script>.sh <subcomando>` do baseline ==
#      corpus (unica adicao permitida: as do novo helper orchestrator-refs.sh);
#   3. literais contratuais (contract-literals.tsv) casam no baseline e no
#      corpus; padroes negativos (contract-negatives.tsv) ausentes de ambos;
#   4. sincronia de blocos FRAGMENT entre as referencias do MESMO orquestrador;
#   5. bloco MCP-VS-BASH byte-identico entre os dois prompts-base;
#   6. bloco `commit-mode.sh finalize` presente no prompt-base de O e de F
#      (decisao 1.2 / CHK021: a onda terminal nao le referencia de fase);
#   7. o proprio teste falha quando deve (mutantes em tmpdir).

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"
. "$TESTS_ROOT/lib/orchestrator-corpus.sh"

FIX="$REPO_ROOT/tests/fixtures/orchestrator-slim"

_need_baseline() {
  orch_have_baseline || {
    _error "baseline ausente" "commit $ORCH_BASELINE_REF nao encontrado neste clone (fetch completo necessario)"
    return 2
  }
}

# ---- helpers de verificacao (usados no corpus real E nos mutantes) ----

# _check_preservation <orq>: exit 0 se 0 linhas faltantes; imprime as faltantes
_check_preservation() {
  _cp_out=$(orch_missing_lines "$1")
  _cp_rc=$?
  [ "$_cp_rc" -eq 2 ] && return 2
  if [ "$_cp_rc" -ne 0 ]; then
    printf '%s\n' "$_cp_out" | head -n 20
    return 1
  fi
  return 0
}

# ==== 1. Preservacao de linhas ====

scenario_preservacao_de_linhas_root() {
  _need_baseline || return 2
  capture _check_preservation root
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "linhas faltantes (root)" "linhas do baseline ausentes do corpus e fora de rewritten-lines.tsv"; return 1; }
}

scenario_preservacao_de_linhas_feature() {
  _need_baseline || return 2
  capture _check_preservation feature
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "linhas faltantes (feature)" "linhas do baseline ausentes do corpus e fora de rewritten-lines.tsv"; return 1; }
}

# ==== 2. Blocos de comando ====

# _check_cmd_blocks <orq>: baseline == corpus (adicoes permitidas: orchestrator-refs.sh path|list)
_check_cmd_blocks() {
  _cb_tmp=$(mktemp -d -t 'orch-cmd.XXXXXX') || return 2
  awk -F '\t' -v o="$1" '$1 == o { print $2 }' "$FIX/command-blocks.baseline.txt" | LC_ALL=C sort -u > "$_cb_tmp/base"
  orch_corpus "$1" | orch_cmd_blocks | grep -vxE 'orchestrator-refs\.sh (path|list)' > "$_cb_tmp/corpus" || :
  _cb_rc=0
  if ! cmp -s "$_cb_tmp/base" "$_cb_tmp/corpus"; then
    diff "$_cb_tmp/base" "$_cb_tmp/corpus" | head -n 30
    _cb_rc=1
  fi
  rm -rf "$_cb_tmp"
  return "$_cb_rc"
}

scenario_inventario_de_blocos_de_comando_bate_com_baseline_extraido_agora() {
  # sanidade do proprio inventario: o arquivo versionado == extracao do baseline
  _need_baseline || return 2
  for _o in root feature; do
    _exp=$(orch_baseline "$_o" | orch_cmd_blocks)
    _got=$(awk -F '\t' -v o="$_o" '$1 == o { print $2 }' "$FIX/command-blocks.baseline.txt" | LC_ALL=C sort -u)
    [ "$_exp" = "$_got" ] || { _fail "command-blocks.baseline.txt ($_o)" "inventario versionado difere da extracao do baseline"; return 1; }
  done
}

scenario_blocos_de_comando_root() {
  capture _check_cmd_blocks root
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "blocos de comando (root)" "diferenca entre baseline e corpus"; return 1; }
}

scenario_blocos_de_comando_feature() {
  capture _check_cmd_blocks feature
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "blocos de comando (feature)" "diferenca entre baseline e corpus"; return 1; }
}

# ==== 3. Literais contratuais e padroes negativos ====

# _check_literals <tsv> <polaridade pos|neg> <fonte corpus|baseline>
_check_literals() {
  _cl_bad=0
  _cl_n=0
  while IFS='	' read -r _cl_o _cl_fl _cl_pat _cl_src; do
    case "$_cl_o" in ''|'#'*) continue ;; esac
    _cl_n=$((_cl_n + 1))
    if [ "$3" = corpus ]; then
      _cl_hit=$(orch_corpus "$_cl_o" | grep "$_cl_fl" -e "$_cl_pat" >/dev/null 2>&1 && echo y || echo n)
    else
      _cl_hit=$(orch_baseline "$_cl_o" | grep "$_cl_fl" -e "$_cl_pat" >/dev/null 2>&1 && echo y || echo n)
    fi
    if [ "$2" = pos ] && [ "$_cl_hit" != y ]; then
      printf 'AUSENTE (%s, %s): %s [%s]\n' "$3" "$_cl_o" "$_cl_pat" "$_cl_src"
      _cl_bad=$((_cl_bad + 1))
    elif [ "$2" = neg ] && [ "$_cl_hit" = y ]; then
      printf 'PRESENTE (%s, %s): %s [%s]\n' "$3" "$_cl_o" "$_cl_pat" "$_cl_src"
      _cl_bad=$((_cl_bad + 1))
    fi
  done < "$1"
  [ "$_cl_n" -gt 0 ] || { printf 'inventario vazio: %s\n' "$1"; return 1; }
  [ "$_cl_bad" -eq 0 ]
}

scenario_literais_contratuais_casam_no_baseline() {
  _need_baseline || return 2
  capture _check_literals "$FIX/contract-literals.tsv" pos baseline
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "literais no baseline" "padrao do inventario nao casa no baseline"; return 1; }
}

scenario_literais_contratuais_casam_no_corpus() {
  capture _check_literals "$FIX/contract-literals.tsv" pos corpus
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "literais no corpus" "padrao do inventario nao casa no corpus"; return 1; }
}

scenario_padroes_negativos_ausentes_do_baseline() {
  _need_baseline || return 2
  capture _check_literals "$FIX/contract-negatives.tsv" neg baseline
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "negativos no baseline" "padrao negativo presente no baseline"; return 1; }
}

scenario_padroes_negativos_ausentes_do_corpus_inteiro() {
  capture _check_literals "$FIX/contract-negatives.tsv" neg corpus
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "negativos no corpus" "padrao negativo presente no corpus (prompt-base + referencias)"; return 1; }
}

# ==== 4. Sincronia de FRAGMENT ====

scenario_fragmentos_sincronizados_root() {
  capture orch_fragments_check "$(orch_refs_dir root)"
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "fragmentos (root)" "copias de FRAGMENT nao byte-identicas"; return 1; }
}

scenario_fragmentos_sincronizados_feature() {
  capture orch_fragments_check "$(orch_refs_dir feature)"
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "fragmentos (feature)" "copias de FRAGMENT nao byte-identicas"; return 1; }
}

# ==== 5. MCP-VS-BASH byte-identico entre O e F ====

scenario_bloco_mcp_vs_bash_identico_entre_os_dois_prompts_base() {
  mktemp_test || return 2
  orch_mcp_block "$(orch_base_path root)" > "$TMPDIR_TEST/mcp-root"
  orch_mcp_block "$(orch_base_path feature)" > "$TMPDIR_TEST/mcp-feature"
  [ -s "$TMPDIR_TEST/mcp-root" ] || { _fail "bloco MCP-VS-BASH ausente" "root sem bloco"; return 1; }
  [ -s "$TMPDIR_TEST/mcp-feature" ] || { _fail "bloco MCP-VS-BASH ausente" "feature sem bloco"; return 1; }
  cmp -s "$TMPDIR_TEST/mcp-root" "$TMPDIR_TEST/mcp-feature" \
    || { _fail "MCP-VS-BASH divergente" "blocos de O e F nao sao byte-identicos"; return 1; }
}

# ==== 6. Finalize terminal no prompt-base (decisao 1.2 / CHK021) ====

scenario_commit_mode_finalize_no_prompt_base_de_root_e_feature() {
  for _o in root feature; do
    _b=$(orch_base_path "$_o")
    assert_exit 0 grep -Fq 'commit-mode.sh finalize' "$_b" || return 1
  done
}

# ==== 7. O teste falha quando deve (Cenarios 3 e 6, error case) ====

scenario_mutante_sem_linha_regra_dura_falha_citando_a_linha() {
  _need_baseline || return 2
  mktemp_test || return 2
  mkdir -p "$TMPDIR_TEST/agents"
  _n=$(orch_baseline root | grep -c 'REGRA DURA' || true)
  [ "${_n:-0}" -ge 1 ] || { _error "premissa" "baseline sem linha REGRA DURA"; return 2; }
  # remove todas as ocorrencias exatas da 1a linha REGRA DURA na copia
  orch_baseline root | grep -vxF -e "$(orch_baseline root | grep -m1 'REGRA DURA')" > "$TMPDIR_TEST/agents/agente-00c-orchestrator.md"
  orch_baseline feature > "$TMPDIR_TEST/agents/agente-00c-feature-orchestrator.md"
  capture env ORCH_AGENTS_DIR="$TMPDIR_TEST/agents" ORCH_REFS_DIR="$TMPDIR_TEST/refs" \
    REPO_ROOT="$REPO_ROOT" sh -c '. "$1/tests/lib/orchestrator-corpus.sh"; orch_missing_lines root' _ "$REPO_ROOT"
  [ "$_CAPTURED_EXIT" -ne 0 ] || { _fail "mutante" "linha REGRA DURA removida nao foi detectada"; return 1; }
  assert_stdout_contains "REGRA DURA" || return 1
}

scenario_mutante_de_fragmento_com_1_byte_falha_nomeando_fragmento_e_arquivos() {
  mktemp_test || return 2
  mkdir -p "$TMPDIR_TEST/refs/root"
  _blk='<!-- FRAGMENT:readback-loop:BEGIN -->
linha um do fragmento
linha dois do fragmento
<!-- FRAGMENT:readback-loop:END -->'
  printf 'cabecalho A\n%s\nrodape A\n' "$_blk" > "$TMPDIR_TEST/refs/root/specify.md"
  printf 'cabecalho B\n%s\nrodape B\n' "$_blk" > "$TMPDIR_TEST/refs/root/plan.md"
  assert_exit 0 orch_fragments_check "$TMPDIR_TEST/refs/root" || return 1
  # altera 1 byte na copia de plan.md
  sed 's/linha dois/linha dOis/' "$TMPDIR_TEST/refs/root/plan.md" > "$TMPDIR_TEST/plan.mut" && mv "$TMPDIR_TEST/plan.mut" "$TMPDIR_TEST/refs/root/plan.md"
  capture orch_fragments_check "$TMPDIR_TEST/refs/root"
  [ "$_CAPTURED_EXIT" -eq 1 ] || { _fail "mutante de fragmento" "1 byte alterado nao foi detectado (exit=$_CAPTURED_EXIT)"; return 1; }
  assert_stdout_contains "readback-loop" || return 1
  assert_stdout_contains "plan.md" || return 1
  assert_stdout_contains "specify.md" || return 1
}

scenario_fragmento_sem_end_e_violacao() {
  mktemp_test || return 2
  mkdir -p "$TMPDIR_TEST/refs/feature"
  printf '<!-- FRAGMENT:quality-gates:BEGIN -->\nsem fim\n' > "$TMPDIR_TEST/refs/feature/plan.md"
  capture orch_fragments_check "$TMPDIR_TEST/refs/feature"
  [ "$_CAPTURED_EXIT" -eq 1 ] || { _fail "fragmento sem END" "nao detectado"; return 1; }
  assert_stdout_contains "quality-gates" || return 1
}

run_all_scenarios "$@"
