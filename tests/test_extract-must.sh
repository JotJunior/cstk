#!/bin/sh
# test_extract-must.sh — cobre global/skills/converge/scripts/extract-must.sh.
#
# Ref: docs/specs/skill-converge/tasks.md tarefa 2.3.4
#      docs/specs/skill-converge/contracts/converge-interfaces.md §3

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/global/skills/converge/scripts/extract-must.sh"

_write_const() {
  cat > "$TMPDIR_TEST/constitution.md"
}

# ---------- Extracao basica: multiplos MUST/NON-NEGOTIABLE ----------

scenario_multiplos_principios_non_negotiable() {
  _write_const <<'EOF'
### I. Primeiro Principio (NON-NEGOTIABLE)

**MUST:**

- Regra A.

### II. Segundo Principio (NON-NEGOTIABLE)

**MUST:**

- Regra B.

### III. Terceiro So Should

**SHOULD:**

- Recomendacao C.
EOF
  capture "$SCRIPT" --constitution "$TMPDIR_TEST/constitution.md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "$(printf 'I\tPrimeiro Principio')" || return 1
  assert_stdout_contains "$(printf 'II\tSegundo Principio')" || return 1
  assert_stdout_not_contains "Terceiro So Should" || return 1
  _n=$(printf '%s\n' "$_CAPTURED_STDOUT" | grep -c .)
  [ "$_n" = 2 ] || { _fail "contagem" "esperado 2 linhas, obtido $_n"; return 1; }
}

scenario_numeral_arabico_tambem_reconhecido() {
  _write_const <<'EOF'
### 1. Principio Numerado (NON-NEGOTIABLE)

**MUST:**

- Regra.
EOF
  capture "$SCRIPT" --constitution "$TMPDIR_TEST/constitution.md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "$(printf '1\tPrincipio Numerado')" || return 1
}

# ---------- Dois sinais independentes: NON-NEGOTIABLE OU MUST-bullet ----------

scenario_non_negotiable_sem_bullet_must_ainda_capturado() {
  # Sinal (a) sozinho: heading termina em "(NON-NEGOTIABLE)" mas o corpo
  # nao tem uma linha "**MUST:**" propriamente (texto livre so).
  _write_const <<'EOF'
### Principio Sem Bullet MUST (NON-NEGOTIABLE)

Texto livre sem bullet formal de MUST.
EOF
  capture "$SCRIPT" --constitution "$TMPDIR_TEST/constitution.md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "Principio Sem Bullet MUST" || return 1
}

scenario_must_bullet_sem_sufixo_non_negotiable_ainda_capturado() {
  # Sinal (b) sozinho: heading SEM sufixo "(NON-NEGOTIABLE)" mas corpo TEM
  # bullet "**MUST:**" — replica o caso real do Principio III deste repo.
  _write_const <<'EOF'
### III. Formato Canonico Sem Sufixo

**MUST:**

- Regra concreta mesmo sem o heading dizer NON-NEGOTIABLE.
EOF
  capture "$SCRIPT" --constitution "$TMPDIR_TEST/constitution.md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "$(printf 'III\tFormato Canonico Sem Sufixo')" || return 1
}

scenario_should_puro_excluido() {
  _write_const <<'EOF'
### V. So Should

**SHOULD:**

- Recomendacao, nao obrigacao.
EOF
  capture "$SCRIPT" --constitution "$TMPDIR_TEST/constitution.md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "esperado vazio (principio SHOULD nao deve aparecer), obtido: $_CAPTURED_STDOUT"; return 1; }
}

# ---------- Constitution generica (template sem numeracao) ----------

scenario_principio_sem_numeral_usa_titulo_como_identificador() {
  # Replica o principio-base obrigatorio semeado pela propria skill
  # `constitution` (SKILL.md) — sem prefixo de numeral algum.
  _write_const <<'EOF'
### Veracidade de Dados — Zero Fabricacao (NON-NEGOTIABLE)

Nenhum artefato pode conter dado factual inventado.

**MUST:**

- Fonte rastreavel obrigatoria.
EOF
  capture "$SCRIPT" --constitution "$TMPDIR_TEST/constitution.md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "$(printf 'Veracidade de Dados — Zero Fabricacao\tVeracidade de Dados — Zero Fabricacao')" || return 1
}

# ---------- constitution ausente (Scenario 15, tarefa 1.4.3) ----------

scenario_constitution_ausente_exit1() {
  capture "$SCRIPT" --constitution "$TMPDIR_TEST/nao-existe.md"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_constitution_vazio_exit0_zero_linhas() {
  : > "$TMPDIR_TEST/constitution.md"
  capture "$SCRIPT" --constitution "$TMPDIR_TEST/constitution.md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "esperado vazio, obtido: $_CAPTURED_STDOUT"; return 1; }
}

# ---------- Conteudo adversarial (SEC-1) ----------

scenario_conteudo_adversarial_nao_executa() {
  _write_const <<'EOF'
### Ataque `$(whoami)` (NON-NEGOTIABLE)

**MUST:**

- Regra com `; rm -rf /tmp/should-not-exist-extract-must-marker` embutido como texto.
EOF
  capture "$SCRIPT" --constitution "$TMPDIR_TEST/constitution.md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  if [ -e "/tmp/should-not-exist-extract-must-marker" ]; then
    _fail "side-effect" "conteudo adversarial foi executado"
    return 1
  fi
  assert_no_side_effect || return 1
}

# ---------- Erros de uso ----------

scenario_sem_argumentos_exit2() {
  capture "$SCRIPT"
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_flag_constitution_ausente_exit2() {
  capture "$SCRIPT" --bogus x
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_flag_desconhecida_exit2() {
  _write_const <<'EOF'
### I. Principio (NON-NEGOTIABLE)
**MUST:**
- Regra.
EOF
  capture "$SCRIPT" --constitution "$TMPDIR_TEST/constitution.md" --bogus
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_help_exit0() {
  capture "$SCRIPT" --help
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "Uso:" || return 1
}

# ---------- Determinismo ----------

scenario_saida_deterministica() {
  _write_const <<'EOF'
### I. Um (NON-NEGOTIABLE)
**MUST:**
- A.
### II. Dois (NON-NEGOTIABLE)
**MUST:**
- B.
EOF
  capture "$SCRIPT" --constitution "$TMPDIR_TEST/constitution.md"
  _first="$_CAPTURED_STDOUT"
  capture "$SCRIPT" --constitution "$TMPDIR_TEST/constitution.md"
  _second="$_CAPTURED_STDOUT"
  if [ "$_first" != "$_second" ]; then
    _fail "determinismo" "duas execucoes com mesma entrada produziram saidas diferentes"
    return 1
  fi
}

run_all_scenarios
