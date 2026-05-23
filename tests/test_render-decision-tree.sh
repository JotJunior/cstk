#!/bin/sh
# test_render-decision-tree.sh — cobre
# global/skills/decision-tree/scripts/render-decision-tree.sh.
#
# Convencao: cada scenario retorna 1 apos assert falho (harness sinaliza
# falha via exit code). Sem 'set -eu' aqui (o harness gerencia status).

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/global/skills/decision-tree/scripts/render-decision-tree.sh"

# ==== helpers locais ====

# _state_path: caminho do state.json da fixture, copiado para o TMPDIR.
_state_path() {
  printf '%s/state.json' "$TMPDIR_TEST"
}

# ==== uso / dispatch ====

scenario_sem_args_exit2_e_usage() {
  assert_exit 2 sh "$SCRIPT" || return 1
  assert_stderr_contains "USO:" || return 1
}

scenario_subcomando_desconhecido_exit2() {
  assert_exit 2 sh "$SCRIPT" foobar || return 1
  assert_stderr_contains "subcomando desconhecido" || return 1
}

scenario_help_exit2_usage_em_stderr() {
  assert_exit 2 sh "$SCRIPT" --help || return 1
  assert_stderr_contains "render --state" || return 1
}

scenario_render_sem_state_exit2() {
  assert_exit 2 sh "$SCRIPT" render || return 1
  assert_stderr_contains "--state e obrigatorio" || return 1
}

scenario_render_flag_state_sem_valor_exit2() {
  assert_exit 2 sh "$SCRIPT" render --state || return 1
}

scenario_render_state_inexistente_exit1() {
  assert_exit 1 sh "$SCRIPT" render --state "$TMPDIR_TEST/nao-existe.json" || return 1
  assert_stderr_contains "nao encontrado" || return 1
}

scenario_render_state_json_invalido_exit1() {
  printf 'isto nao e json {{{\n' > "$(_state_path)"
  assert_exit 1 sh "$SCRIPT" render --state "$(_state_path)" || return 1
  assert_stderr_contains "invalido" || return 1
}

scenario_render_decisoes_vazio_exit1() {
  printf '{"execucao":{"id":"x"},"decisoes":[]}\n' > "$(_state_path)"
  assert_exit 1 sh "$SCRIPT" render --state "$(_state_path)" || return 1
  assert_stderr_contains "nenhuma decisao" || return 1
}

# ==== render valido (fixture) ====

scenario_render_fixture_exit0_html() {
  fixture decision-tree-state || return 2
  assert_exit 0 sh "$SCRIPT" render --state "$(_state_path)" || return 1
  assert_stdout_contains "<!DOCTYPE html>" || return 1
  assert_stdout_contains "const PAYLOAD =" || return 1
  assert_stdout_contains "</html>" || return 1
}

scenario_render_inclui_todos_os_ids() {
  fixture decision-tree-state || return 2
  capture sh "$SCRIPT" render --state "$(_state_path)" || return 2
  assert_stdout_contains "dec-001" || return 1
  assert_stdout_contains "dec-002" || return 1
  assert_stdout_contains "dec-003" || return 1
}

scenario_render_total_3_no_payload() {
  fixture decision-tree-state || return 2
  capture sh "$SCRIPT" render --state "$(_state_path)" || return 2
  # payload compacto traz "total":3
  assert_stdout_match '"total":3' || return 1
}

# Escaping defensivo: a sequencia </script> da fixture nao pode aparecer
# literal no HTML (deve virar <\/script>), senao fecharia a tag <script>.
scenario_render_escapa_fechamento_de_script() {
  fixture decision-tree-state || return 2
  capture sh "$SCRIPT" render --state "$(_state_path)" || return 2
  # Forma escapada presente...
  assert_stdout_contains '<\/script>' || return 1
  # ...e a forma perigosa nao aparece DENTRO do payload (apenas o </script>
  # legitimo de fechamento da tag existe; a versao adversarial foi escapada).
  _count=$(printf '%s\n' "$_CAPTURED_STDOUT" | grep -c '</script>')
  if [ "$_count" -ne 1 ]; then
    _fail "escaping" "esperado exatamente 1 </script> legitimo, obtido $_count"
    return 1
  fi
}

# Escolha fora das opcoes (dec-003) nao deve quebrar a geracao.
scenario_render_escolha_fora_das_opcoes_ok() {
  fixture decision-tree-state || return 2
  assert_exit 0 sh "$SCRIPT" render --state "$(_state_path)" || return 1
  assert_stdout_contains "fazer-z-nao-listada" || return 1
}

# ==== --output ====

scenario_render_output_grava_arquivo() {
  fixture decision-tree-state || return 2
  _out="$TMPDIR_TEST/arvore.html"
  assert_exit 0 sh "$SCRIPT" render --state "$(_state_path)" --output "$_out" || return 1
  if [ ! -s "$_out" ]; then
    _fail "output" "arquivo de saida nao foi criado ou esta vazio: $_out"
    return 1
  fi
  if ! head -1 "$_out" | grep -q '<!DOCTYPE html>'; then
    _fail "output" "arquivo de saida nao comeca com <!DOCTYPE html>"
    return 1
  fi
}

scenario_render_output_mensagem_em_stderr() {
  fixture decision-tree-state || return 2
  _out="$TMPDIR_TEST/arvore.html"
  capture sh "$SCRIPT" render --state "$(_state_path)" --output "$_out" || return 2
  assert_stderr_contains "HTML gerado em" || return 1
}

# ==== IDT-2 determinismo ====

scenario_render_deterministico_byte_a_byte() {
  fixture decision-tree-state || return 2
  _a="$TMPDIR_TEST/a.html"; _b="$TMPDIR_TEST/b.html"
  sh "$SCRIPT" render --state "$(_state_path)" > "$_a" 2>/dev/null || return 2
  sh "$SCRIPT" render --state "$(_state_path)" > "$_b" 2>/dev/null || return 2
  if ! cmp -s "$_a" "$_b"; then
    _fail "determinismo" "duas execucoes produziram HTML diferente (IDT-2 violada)"
    return 1
  fi
}

# ==== IDT-1 read-only ====

scenario_render_nao_modifica_state() {
  fixture decision-tree-state || return 2
  _before=$(cksum "$(_state_path)" | cut -d' ' -f1-2)
  sh "$SCRIPT" render --state "$(_state_path)" > "$TMPDIR_TEST/out.html" 2>/dev/null || return 2
  _after=$(cksum "$(_state_path)" | cut -d' ' -f1-2)
  if [ "$_before" != "$_after" ]; then
    _fail "read-only" "state.json foi modificado durante render (IDT-1 violada)"
    return 1
  fi
}

# ==== IDT-3 POSIX ====

scenario_script_shebang_e_set_eu() {
  # Shebang #!/bin/sh exatamente na linha 1.
  _line1=$(head -1 "$SCRIPT")
  [ "$_line1" = "#!/bin/sh" ] || { _fail "shebang" "esperado '#!/bin/sh', obtido '$_line1'"; return 1; }
  grep -q '^set -eu$' "$SCRIPT" || { _fail "set -eu" "falta 'set -eu'"; return 1; }
  # Bash-ism obvio: [[ ]]. (Mesma checagem minima do INV-6 de model-routing —
  # nao grepar 'function'/'local' porque casam o JS embutido no template HTML.)
  if grep -qE '\[\[ ' "$SCRIPT"; then
    _fail "bash-ism" "[[ ]] detectado"
    return 1
  fi
}

run_all_scenarios
