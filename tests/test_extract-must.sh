#!/bin/sh
# test_extract-must.sh — cobre plugins/cstk/skills/converge/scripts/extract-must.sh.
#
# Ref: docs/specs/skill-converge/tasks.md tarefa 2.3.4
#      docs/specs/skill-converge/contracts/converge-interfaces.md §3

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/converge/scripts/extract-must.sh"

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

# ---------- issue #171: convencao de MUST em bullet ----------

scenario_must_em_bullet_simples() {
  # Regressao issue #171: `- MUST:` era ignorado; um principio SEM sufixo
  # (NON-NEGOTIABLE) e com regras MUST em bullet nao era emitido de forma
  # alguma, e o gate reportava sucesso.
  _write_const <<'EOF'
### I. Primeiro (NON-NEGOTIABLE)
- MUST: regra a.
### II. Segundo
- MUST: regra b.
- MUST: regra c.
EOF
  capture "$SCRIPT" --constitution "$TMPDIR_TEST/constitution.md"
  assert_stdout_contains "II	Segundo" || return 1
}

scenario_must_bullet_variantes_de_marcacao() {
  # `- MUST:`, `* MUST:`, `+ MUST:`, `- **MUST:**`, `MUST:` cru, `MUST NOT:`,
  # e indentacao — todas sao regra MUST.
  for _mark in "- MUST:" "* MUST:" "+ MUST:" "- **MUST:**" "MUST:" "- MUST NOT:" "  - MUST:"; do
    printf '### I. Sem sufixo\n%s regra.\n' "$_mark" > "$TMPDIR_TEST/constitution.md"
    capture "$SCRIPT" --constitution "$TMPDIR_TEST/constitution.md"
    assert_stdout_contains "Sem sufixo" || { _fail "marcacao nao reconhecida: $_mark" "$_CAPTURED_STDOUT"; return 1; }
  done
}

scenario_must_em_prosa_corrida_nao_conta() {
  # Exigir os dois-pontos e deliberado: `MUST` em prosa nao vira sinal.
  _write_const <<'EOF'
### I. Sem sufixo
Este principio diz que o time MUST agir com cuidado.
EOF
  capture "$SCRIPT" --constitution "$TMPDIR_TEST/constitution.md"
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "prosa com MUST virou principio" "$_CAPTURED_STDOUT"; return 1; }
}

scenario_should_bullet_continua_excluido() {
  _write_const <<'EOF'
### I. Sem sufixo
- SHOULD: recomendacao.
EOF
  capture "$SCRIPT" --constitution "$TMPDIR_TEST/constitution.md"
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "SHOULD virou MUST" "$_CAPTURED_STDOUT"; return 1; }
}

# ---------- issue #171: relatorio de cobertura ----------

scenario_coverage_reporta_numeros_reais() {
  _write_const <<'EOF'
### I. Primeiro (NON-NEGOTIABLE)
- MUST: regra a.
- MUST: regra b.
### II. Segundo
- MUST: regra c.
EOF
  capture "$SCRIPT" --constitution "$TMPDIR_TEST/constitution.md" --coverage
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "coverage exit" "$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "ocorrencias da palavra MUST no arquivo (contagem independente): 3" || return 1
  assert_stdout_contains "linhas de regra MUST reconhecidas pelo parser: 3" || return 1
  assert_stdout_contains "principios emitidos: 2" || return 1
}

scenario_coverage_expoe_principio_so_por_rotulo_de_heading() {
  # O caso exato de #171: o principio entra pelo rotulo (NON-NEGOTIABLE) do
  # heading, sem NENHUMA regra lida. O relatorio precisa dizer isso.
  #
  # Estendido no r02 (tasks.md 7.2.1, quickstart.md Scenario 16 ultima linha):
  # este insumo revoga `sem-must-declarado`/exit 0 do round 1 para
  # `cobertura-parcial`/exit 4 — fixar explicitamente o novo veredito, o
  # novo exit e a 7a linha, para a mudanca de semantica nao ficar sem rede
  # de teste.
  _write_const <<'EOF'
### I. Primeiro (NON-NEGOTIABLE)
Texto sem marcacao de regra.
EOF
  capture "$SCRIPT" --constitution "$TMPDIR_TEST/constitution.md" --coverage
  assert_stdout_contains "principios emitidos: 1" || return 1
  assert_stdout_contains "principios emitidos so por rotulo de heading (sem regra MUST lida): 1" || return 1
  assert_stdout_contains "cobertura de MUST: cobertura-parcial" || return 1
  [ "$_CAPTURED_EXIT" = 4 ] || { _fail "exit" "esperado 4, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "$(printf 'principio sem regra MUST legivel: I. Primeiro (NON-NEGOTIABLE)')" || return 1
}

scenario_coverage_avisa_quando_convencao_nao_e_reconhecida() {
  # Sintoma de #171: arquivo fala de MUST, parser reconhece 0 regras.
  _write_const <<'EOF'
### I. Primeiro
- MUST — regra sem dois-pontos.
EOF
  capture "$SCRIPT" --constitution "$TMPDIR_TEST/constitution.md" --coverage
  assert_stdout_contains "linhas de regra MUST reconhecidas pelo parser: 0" || return 1
  assert_stderr_contains "NAO cobre as regras MUST deste arquivo" || return 1
}

scenario_coverage_contagem_independente_nao_ecoa_o_parser() {
  # A 2a linha usa gramatica diferente da do parser: um arquivo onde o
  # parser le 0 e a contagem independente le >0 e o sinal util. Se as duas
  # compartilhassem gramatica, ambas dariam 0 e a metrica seria inutil.
  _write_const <<'EOF'
### I. Primeiro
Nota: o time MUST revisar. Outra linha: MUST ser auditado.
EOF
  capture "$SCRIPT" --constitution "$TMPDIR_TEST/constitution.md" --coverage
  assert_stdout_contains "ocorrencias da palavra MUST no arquivo (contagem independente): 1" || return 1
  assert_stdout_contains "linhas de regra MUST reconhecidas pelo parser: 0" || return 1
}

scenario_coverage_constitution_ausente_exit_1() {
  capture "$SCRIPT" --constitution "$TMPDIR_TEST/nao-existe.md" --coverage
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "coverage com arquivo ausente" "exit=$_CAPTURED_EXIT"; return 1; }
}

scenario_default_permanece_tsv_sem_coverage() {
  # --coverage e ADITIVO: a saida default nao pode mudar de forma.
  _write_const <<'EOF'
### I. Primeiro (NON-NEGOTIABLE)
**MUST:**
- A.
EOF
  capture "$SCRIPT" --constitution "$TMPDIR_TEST/constitution.md"
  assert_stdout_contains "I	Primeiro" || return 1
  case "$_CAPTURED_STDOUT" in
    *"fontes declaradas"*) _fail "default vazou relatorio de cobertura" "$_CAPTURED_STDOUT"; return 1 ;;
  esac
}

# ---------- converge-must-coverage-fail-closed: veredito + exit 3 ----------
# Ref: docs/specs/converge-must-coverage-fail-closed/tasks.md 2.1.1-2.1.5
#      docs/specs/converge-must-coverage-fail-closed/quickstart.md Cenarios 1-5

scenario_coverage_veredito_zero_reconhecida_exit3() {
  # Quickstart Scenario 1: MUST so em prosa -> zero-reconhecida, exit 3.
  _write_const <<'EOF'
### I. Primeiro
Nota: o time MUST revisar cada release antes de publicar.
EOF
  capture "$SCRIPT" --constitution "$TMPDIR_TEST/constitution.md" --coverage
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "exit" "esperado 3, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "ocorrencias da palavra MUST no arquivo (contagem independente): 1" || return 1
  assert_stdout_contains "linhas de regra MUST reconhecidas pelo parser: 0" || return 1
  assert_stdout_contains "cobertura de MUST: zero-reconhecida" || return 1
  assert_stderr_contains "NAO cobre as regras MUST deste arquivo" || return 1
}

scenario_coverage_veredito_ok_exit0() {
  # Quickstart Scenario 2: pelo menos 1 linha rotulada + MUST em prosa -> ok.
  _write_const <<'EOF'
### I. Primeiro (NON-NEGOTIABLE)
**MUST:** toda escrita e atomica.
Nota: o time MUST revisar.
EOF
  capture "$SCRIPT" --constitution "$TMPDIR_TEST/constitution.md" --coverage
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  _n=$(printf '%s\n' "$_CAPTURED_STDOUT" | grep -oE 'linhas de regra MUST reconhecidas pelo parser: [0-9]+' | grep -oE '[0-9]+$')
  [ "$_n" -ge 1 ] || { _fail "linhas reconhecidas" "esperado >= 1, obtido $_n"; return 1; }
  assert_stdout_contains "cobertura de MUST: ok" || return 1
}

scenario_coverage_veredito_sem_must_declarado_exit0_sem_aviso() {
  # Quickstart Scenario 3: nenhuma ocorrencia de MUST -> sem-must-declarado.
  _write_const <<'EOF'
### I. Primeiro
Preferimos simplicidade a abstracao prematura.
EOF
  capture "$SCRIPT" --constitution "$TMPDIR_TEST/constitution.md" --coverage
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "ocorrencias da palavra MUST no arquivo (contagem independente): 0" || return 1
  assert_stdout_contains "cobertura de MUST: sem-must-declarado" || return 1
  [ -z "$_CAPTURED_STDERR" ] || { _fail "stderr" "esperado vazio (nenhum aviso), obtido: $_CAPTURED_STDERR"; return 1; }
}

scenario_coverage_constitution_ausente_permanece_exit1_sem_veredito() {
  # Quickstart Scenario 4: erro (constitution ausente) e estado distinto de
  # sem-must-declarado (INV-3, data-model.md) — nenhuma linha de veredito.
  capture "$SCRIPT" --constitution "$TMPDIR_TEST/nao-existe.md" --coverage
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "esperado vazio (sem linha de veredito), obtido: $_CAPTURED_STDOUT"; return 1; }
  assert_stderr_contains "constitution.md ausente" || return 1
}

scenario_coverage_aditividade_5_linhas_byte_identicas_mais_6a() {
  # Quickstart Scenario 5: modo default sem linha de cobertura; --coverage
  # preserva as 5 linhas existentes byte-identicas com a 6a estritamente nova.
  _write_const <<'EOF'
### I. Primeiro (NON-NEGOTIABLE)
**MUST:** toda escrita e atomica.
Nota: o time MUST revisar.
EOF
  capture "$SCRIPT" --constitution "$TMPDIR_TEST/constitution.md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit default" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  case "$_CAPTURED_STDOUT" in
    *"cobertura de MUST"*) _fail "default vazou linha de cobertura" "$_CAPTURED_STDOUT"; return 1 ;;
  esac

  capture "$SCRIPT" --constitution "$TMPDIR_TEST/constitution.md" --coverage
  _nlines=$(printf '%s\n' "$_CAPTURED_STDOUT" | grep -c .)
  [ "$_nlines" = 6 ] || { _fail "contagem de linhas" "esperado 6, obtido $_nlines"; return 1; }
  _line6=$(printf '%s\n' "$_CAPTURED_STDOUT" | sed -n '6p')
  case "$_line6" in
    "cobertura de MUST: "*) : ;;
    *) _fail "6a linha" "esperado prefixo 'cobertura de MUST: ', obtido: $_line6"; return 1 ;;
  esac
  _first5=$(printf '%s\n' "$_CAPTURED_STDOUT" | sed -n '1,5p')
  case "$_first5" in
    *"fontes declaradas"*) : ;;
    *) _fail "1a linha ausente" "$_first5"; return 1 ;;
  esac
  case "$_first5" in
    *"principios emitidos so por rotulo de heading"*) : ;;
    *) _fail "5a linha ausente" "$_first5"; return 1 ;;
  esac
}

# ---------- converge-must-coverage-fail-closed r02: cobertura-parcial + linhas 7..N ----------
# Ref: docs/specs/converge-must-coverage-fail-closed/tasks.md 7.1.1-7.1.6
#      docs/specs/converge-must-coverage-fail-closed/quickstart.md Scenarios 10-15

scenario_coverage_r02_cobertura_mista_exit4() {
  # Quickstart Scenario 10: 1 principio rotulado + 1 so-por-heading ->
  # cobertura-parcial, exit 4 (revoga o `ok` do round 1 para este insumo).
  _write_const <<'EOF'
### I. Primeiro (NON-NEGOTIABLE)
**MUST:** toda escrita e atomica.

### II. Segundo (NON-NEGOTIABLE)
Nada aqui esta rotulado, so prosa solta.
EOF
  capture "$SCRIPT" --constitution "$TMPDIR_TEST/constitution.md" --coverage
  [ "$_CAPTURED_EXIT" = 4 ] || { _fail "exit" "esperado 4, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "linhas de regra MUST reconhecidas pelo parser: 1" || return 1
  assert_stdout_contains "principios emitidos: 2" || return 1
  assert_stdout_contains "principios emitidos so por rotulo de heading (sem regra MUST lida): 1" || return 1
  assert_stdout_contains "cobertura de MUST: cobertura-parcial" || return 1
}

scenario_coverage_r02_so_de_heading_exit4() {
  # Quickstart Scenario 11: lines==0 e words==0 -> hoje cairia em
  # sem-must-declarado; r02 revoga para cobertura-parcial, exit 4.
  _write_const <<'EOF'
### I. Primeiro (NON-NEGOTIABLE)
Prosa livre, sem rotulo algum.
EOF
  capture "$SCRIPT" --constitution "$TMPDIR_TEST/constitution.md" --coverage
  [ "$_CAPTURED_EXIT" = 4 ] || { _fail "exit" "esperado 4, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "ocorrencias da palavra MUST no arquivo (contagem independente): 0" || return 1
  assert_stdout_contains "linhas de regra MUST reconhecidas pelo parser: 0" || return 1
  assert_stdout_contains "principios emitidos so por rotulo de heading (sem regra MUST lida): 1" || return 1
  assert_stdout_contains "cobertura de MUST: cobertura-parcial" || return 1
}

scenario_coverage_r02_precedencia_zero_reconhecida_vence() {
  # Quickstart Scenario 12: coocorrencia das guardas 1 e 2 — words>0,
  # lines==0, heading_only>0 -> zero-reconhecida vence, exit 3 (nao 4).
  # As linhas 7..N aparecem tambem aqui (INV-r02-D): guardadas por Q, nao
  # pelo veredito.
  _write_const <<'EOF'
### I. Primeiro (NON-NEGOTIABLE)
Nota: o time MUST revisar cada release.
EOF
  capture "$SCRIPT" --constitution "$TMPDIR_TEST/constitution.md" --coverage
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "exit" "esperado 3, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "ocorrencias da palavra MUST no arquivo (contagem independente): 1" || return 1
  assert_stdout_contains "linhas de regra MUST reconhecidas pelo parser: 0" || return 1
  assert_stdout_contains "principios emitidos so por rotulo de heading (sem regra MUST lida): 1" || return 1
  assert_stdout_contains "cobertura de MUST: zero-reconhecida" || return 1
  assert_stderr_contains "NAO cobre as regras MUST deste arquivo" || return 1
  _n=$(printf '%s\n' "$_CAPTURED_STDOUT" | grep -c .)
  [ "$_n" = 7 ] || { _fail "contagem de linhas" "esperado 7, obtido $_n"; return 1; }
  _line7=$(printf '%s\n' "$_CAPTURED_STDOUT" | sed -n '7p')
  [ "$_line7" = "principio sem regra MUST legivel: I. Primeiro (NON-NEGOTIABLE)" ] || { _fail "7a linha" "obtido: $_line7"; return 1; }
}

scenario_coverage_r02_identificacao_nominal_linhas_7n() {
  # Quickstart Scenario 13: FR-013 — mesmo insumo do Scenario 10 (Q=1),
  # 7 linhas, 6a intacta (leitura posicional), 7a exatamente o nome
  # verbatim.
  _write_const <<'EOF'
### I. Primeiro (NON-NEGOTIABLE)
**MUST:** toda escrita e atomica.

### II. Segundo (NON-NEGOTIABLE)
Nada aqui esta rotulado, so prosa solta.
EOF
  capture "$SCRIPT" --constitution "$TMPDIR_TEST/constitution.md" --coverage
  _n=$(printf '%s\n' "$_CAPTURED_STDOUT" | grep -c .)
  [ "$_n" = 7 ] || { _fail "contagem de linhas" "esperado 7, obtido $_n"; return 1; }
  _line6=$(printf '%s\n' "$_CAPTURED_STDOUT" | sed -n '6p')
  [ "$_line6" = "cobertura de MUST: cobertura-parcial" ] || { _fail "6a linha" "obtido: $_line6"; return 1; }
  _line7=$(printf '%s\n' "$_CAPTURED_STDOUT" | sed -n '7p')
  [ "$_line7" = "principio sem regra MUST legivel: II. Segundo (NON-NEGOTIABLE)" ] || { _fail "7a linha" "obtido: $_line7"; return 1; }

  # Variante com 2 principios so-por-heading -> 8 linhas, ordem de aparicao.
  _write_const <<'EOF'
### I. Primeiro (NON-NEGOTIABLE)
**MUST:** toda escrita e atomica.

### II. Segundo (NON-NEGOTIABLE)
Sem rotulo.

### III. Terceiro (NON-NEGOTIABLE)
Tambem sem rotulo.
EOF
  capture "$SCRIPT" --constitution "$TMPDIR_TEST/constitution.md" --coverage
  _n=$(printf '%s\n' "$_CAPTURED_STDOUT" | grep -c .)
  [ "$_n" = 8 ] || { _fail "contagem variante" "esperado 8, obtido $_n"; return 1; }
  _line7=$(printf '%s\n' "$_CAPTURED_STDOUT" | sed -n '7p')
  [ "$_line7" = "principio sem regra MUST legivel: II. Segundo (NON-NEGOTIABLE)" ] || { _fail "7a linha variante" "obtido: $_line7"; return 1; }
  _line8=$(printf '%s\n' "$_CAPTURED_STDOUT" | sed -n '8p')
  [ "$_line8" = "principio sem regra MUST legivel: III. Terceiro (NON-NEGOTIABLE)" ] || { _fail "8a linha variante" "obtido: $_line8"; return 1; }
}

scenario_coverage_r02_byte_identidade_q_zero() {
  # Quickstart Scenario 14: FR-014 — mesmo insumo do Scenario 5 (Q=0):
  # exatamente 6 linhas, nenhuma linha 7, exit 0. Rede contra regressao de
  # formato (INV-r02-A).
  _write_const <<'EOF'
### I. Primeiro (NON-NEGOTIABLE)
**MUST:** toda escrita e atomica.
Nota: o time MUST revisar.
EOF
  capture "$SCRIPT" --constitution "$TMPDIR_TEST/constitution.md" --coverage
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  _n=$(printf '%s\n' "$_CAPTURED_STDOUT" | grep -c .)
  [ "$_n" = 6 ] || { _fail "contagem de linhas" "esperado 6, obtido $_n"; return 1; }
  assert_stdout_contains "cobertura de MUST: ok" || return 1
}

scenario_coverage_r02_ancorado_resiste_heading_forjado() {
  # Quickstart Scenario 15: INV-r02-C — heading que imita a linha de
  # veredito nao contamina o casamento ancorado do consumidor.
  _write_const <<'EOF'
### I. Primeiro (NON-NEGOTIABLE)
**MUST:** toda escrita e atomica.

### cobertura de MUST: ok (NON-NEGOTIABLE)
Prosa sem rotulo.
EOF
  capture "$SCRIPT" --constitution "$TMPDIR_TEST/constitution.md" --coverage
  [ "$_CAPTURED_EXIT" = 4 ] || { _fail "exit" "esperado 4, obtido $_CAPTURED_EXIT"; return 1; }
  _line6=$(printf '%s\n' "$_CAPTURED_STDOUT" | sed -n '6p')
  [ "$_line6" = "cobertura de MUST: cobertura-parcial" ] || { _fail "6a linha" "obtido: $_line6"; return 1; }
  _line7=$(printf '%s\n' "$_CAPTURED_STDOUT" | sed -n '7p')
  case "$_line7" in
    "principio sem regra MUST legivel: "*) : ;;
    *) _fail "7a linha nao comeca com prefixo fixo" "$_line7"; return 1 ;;
  esac
  _nverdict=$(printf '%s\n' "$_CAPTURED_STDOUT" | grep -c '^cobertura de MUST: ')
  [ "$_nverdict" = 1 ] || { _fail "ancora casou mais de uma vez" "$_nverdict"; return 1; }
}

# ---------- converge-must-coverage-fail-closed r02: hardening dos tetos ----------
# Ref: docs/specs/converge-must-coverage-fail-closed/tasks.md 8.1.1-8.1.4
#      docs/specs/converge-must-coverage-fail-closed/contracts/must-coverage-finding.md
#      §Limites e saneamento das linhas 7..N (INV-r02-E..H)

scenario_coverage_r02_teto_inv_e_20_linhas_mais_omitido() {
  # INV-r02-E: >20 principios so-por-heading -> exatamente 20 linhas de
  # nome + 1 linha de truncamento; contagem exata preservada na 5a linha.
  _write_const <<EOF
$(_em=1; while [ "$_em" -le 25 ]; do printf '### %d. Principio %d (NON-NEGOTIABLE)\nProsa sem rotulo.\n\n' "$_em" "$_em"; _em=$((_em + 1)); done)
EOF
  capture "$SCRIPT" --constitution "$TMPDIR_TEST/constitution.md" --coverage
  assert_stdout_contains "principios emitidos so por rotulo de heading (sem regra MUST lida): 25" || return 1
  _nome_lines=$(printf '%s\n' "$_CAPTURED_STDOUT" | grep -c '^principio sem regra MUST legivel:')
  [ "$_nome_lines" = 21 ] || { _fail "contagem de linhas de nome" "esperado 21 (20 + 1 omissao), obtido $_nome_lines"; return 1; }
  assert_stdout_contains "principio sem regra MUST legivel: (... mais 5 principio(s) omitido(s))" || return 1
}

scenario_coverage_r02_teto_inv_f_200_chars_truncado() {
  # INV-r02-F: nome > 200 caracteres -> truncado em 200 chars + sufixo "...".
  _longname=$(printf 'X%.0s' $(seq 1 250))
  printf '### %s (NON-NEGOTIABLE)\nProsa sem rotulo.\n' "$_longname" > "$TMPDIR_TEST/constitution.md"
  capture "$SCRIPT" --constitution "$TMPDIR_TEST/constitution.md" --coverage
  _line=$(printf '%s\n' "$_CAPTURED_STDOUT" | grep '^principio sem regra MUST legivel:')
  _expected="principio sem regra MUST legivel: $(printf 'X%.0s' $(seq 1 200))..."
  [ "$_line" = "$_expected" ] || { _fail "truncamento 200 chars" "obtido: $_line"; return 1; }
}

scenario_coverage_r02_teto_inv_g_saneamento_controle_c0() {
  # INV-r02-G: TAB e escape ANSI (ESC) substituidos por espaco; texto
  # imprimivel preservado verbatim.
  printf '### Nome\tcom\033[31mansi (NON-NEGOTIABLE)\nProsa sem rotulo.\n' > "$TMPDIR_TEST/constitution.md"
  capture "$SCRIPT" --constitution "$TMPDIR_TEST/constitution.md" --coverage
  _line=$(printf '%s\n' "$_CAPTURED_STDOUT" | grep '^principio sem regra MUST legivel:')
  [ "$_line" = "principio sem regra MUST legivel: Nome com [31mansi (NON-NEGOTIABLE)" ] || { _fail "saneamento C0" "obtido: $_line"; return 1; }
  case "$_line" in
    *"$(printf '\033')"*) _fail "byte ESC atravessou verbatim" "$_line"; return 1 ;;
  esac
  case "$_line" in
    *"$(printf '\t')"*) _fail "byte TAB atravessou verbatim" "$_line"; return 1 ;;
  esac
}

scenario_coverage_r02_teto_inv_h_tab_no_meio_nao_corrompe() {
  # INV-r02-H: nome contendo TAB no meio permanece integro como ultimo
  # campo do formato intermediario classe<TAB>nome, sem corromper parsing
  # (o nome sanado ainda contem o texto de ambos os lados do TAB).
  printf '### Antes\tDepois (NON-NEGOTIABLE)\nProsa sem rotulo.\n' > "$TMPDIR_TEST/constitution.md"
  capture "$SCRIPT" --constitution "$TMPDIR_TEST/constitution.md" --coverage
  [ "$_CAPTURED_EXIT" = 4 ] || { _fail "exit" "esperado 4, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "principio sem regra MUST legivel: Antes Depois (NON-NEGOTIABLE)" || return 1
  _n=$(printf '%s\n' "$_CAPTURED_STDOUT" | grep -c '^principio sem regra MUST legivel:')
  [ "$_n" = 1 ] || { _fail "TAB corrompeu parsing (linha extra)" "$_n"; return 1; }
}

run_all_scenarios
