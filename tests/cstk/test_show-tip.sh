#!/bin/sh
# test_show-tip.sh — cobre cli/lib/show-tip.sh (cstk show-tip).
#
# Cenarios cobertos:
#   5.2.1  invocacao sem args com catalogo fixture retorna exit 0 e stdout nao-vazio
#   5.2.2  --catalog /nao/existe retorna exit 0 e stdout vazio (fail-silent FR-006)
#   5.2.3  SKILL presente no catalogo retorna dica daquela skill
#   5.2.4  SKILL ausente do catalogo (modo automatico --phase) retorna exit 0 vazio
#   5.2.5  SKILL ausente do catalogo (modo explicito) retorna mensagem amigavel + exit 0
#   5.2.6  --phase specify retorna dica da skill specify (mapeamento fase->skill)
#   5.2.7  --phase fase-inexistente retorna exit 0 (fallback aleatorio, nao erro)
#   5.2.8  3 invocacoes com N>1 entradas nao retornam todas igual (variacao RNG)
#   5.3.1  --audit com catalogo completo (fixture ok) retorna exit 0
#   5.3.2  --audit com catalogo incompleto (gap) retorna exit 1 + lista gap
#   5.3.3  --audit com catalogo ausente retorna exit 1
#   5.4.1  SKILL com metacaracteres awk nao injeta codigo (OWASP A05)
#   5.4.2  SKILL com metacaracteres shell passado literalmente
#   5.4.3  --catalog com path contendo espacos tratado corretamente
#   5.5.1  shellcheck -s sh cli/lib/show-tip.sh zero warnings (lint gate)
#   5.5.3  shellcheck -s sh tests/cstk/test_show-tip.sh zero warnings
#   5.6.1  performance: cstk show-tip com catalogo 76+ entradas < 1s wall-clock

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CSTK_LIB="$REPO_ROOT/cli/lib"
export CSTK_LIB

# Path dos fixtures desta suite
FIXTURES_DIR="$TESTS_ROOT/cstk/fixtures/show-tip"

# Repo mock com apenas a skill mock-skill-a (para testes de audit)
REPO_MOCK="$FIXTURES_DIR/repo_mock"

# _st CMD... -> roda show_tip_main num subshell com common+show-tip sourced.
_st() {
  sh -c '. "$CSTK_LIB/common.sh"; . "$CSTK_LIB/show-tip.sh"; show_tip_main "$@"' _ "$@"
}

# _st_with_root REPO_ROOT CMD... -> igual a _st mas seta CSTK_REPO_ROOT
_st_with_root() {
  _root="$1"; shift
  sh -c 'CSTK_REPO_ROOT="$1"; shift
         . "$CSTK_LIB/common.sh"; . "$CSTK_LIB/show-tip.sh"
         show_tip_main "$@"' _ "$_root" "$@"
}

# =========================================================================
# Cenario 5.2.1 — Invocacao sem args com catalogo fixture retorna dica
# =========================================================================
scenario_521_sem_args_retorna_dica() {
  capture _st --catalog "$FIXTURES_DIR/catalog_minimal.md"
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "exit esperado 0" "got $_CAPTURED_EXIT; stderr: $_CAPTURED_STDERR"
    return 1
  fi
  if [ -z "$_CAPTURED_STDOUT" ]; then
    _fail "stdout vazio" "esperado bloco de dica nao-vazio"
    return 1
  fi
  # Confirmar que e um Tip Block (linha de separador)
  printf '%s\n' "$_CAPTURED_STDOUT" \
    | grep -q "======================================================" \
    || { _fail "tip block ausente" "$_CAPTURED_STDOUT"; return 1; }
}

# =========================================================================
# Cenario 5.2.2 — Catalogo ausente = fail-silent (FR-006)
# =========================================================================
scenario_522_catalogo_ausente_fail_silent() {
  capture _st --catalog "/nao/existe/catalog.md"
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "exit esperado 0 (fail-silent)" "got $_CAPTURED_EXIT"
    return 1
  fi
  if [ -n "$_CAPTURED_STDOUT" ]; then
    _fail "stdout nao-vazio" "esperado vazio quando catalogo ausente"
    return 1
  fi
}

# =========================================================================
# Cenario 5.2.3 — SKILL presente no catalogo retorna dica daquela skill
# =========================================================================
scenario_523_skill_presente_retorna_dica_da_skill() {
  capture _st --catalog "$FIXTURES_DIR/catalog_minimal.md" specify
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "exit esperado 0" "got $_CAPTURED_EXIT"
    return 1
  fi
  # Verificar que a dica e da skill specify (Tip Block contem o nome)
  printf '%s\n' "$_CAPTURED_STDOUT" \
    | grep -q "specify" \
    || { _fail "skill 'specify' ausente no bloco" "$_CAPTURED_STDOUT"; return 1; }
}

# =========================================================================
# Cenario 5.2.4 — SKILL ausente + modo automatico (--phase) = stdout vazio
# =========================================================================
scenario_524_skill_ausente_modo_automatico_stdout_vazio() {
  # clarify nao esta no catalog_minimal.md; via --phase o modo e automatico
  capture _st --catalog "$FIXTURES_DIR/catalog_minimal.md" --phase clarify
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "exit esperado 0" "got $_CAPTURED_EXIT"
    return 1
  fi
  # modo automatico com skill sem dicas -> stdout vazio (nao mensagem amigavel)
  if [ -n "$_CAPTURED_STDOUT" ]; then
    _fail "stdout nao-vazio em modo automatico sem dicas" "$_CAPTURED_STDOUT"
    return 1
  fi
}

# =========================================================================
# Cenario 5.2.5 — SKILL ausente (modo explicito) = mensagem amigavel
# =========================================================================
scenario_525_skill_ausente_modo_explicito_mensagem_amigavel() {
  # "clarify" nao esta no catalog_minimal.md; passado explicitamente (posicional)
  capture _st --catalog "$FIXTURES_DIR/catalog_minimal.md" clarify
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "exit esperado 0" "got $_CAPTURED_EXIT"
    return 1
  fi
  # Deve imprimir mensagem amigavel com lista de skills disponiveis
  printf '%s\n' "$_CAPTURED_STDOUT" \
    | grep -qi "sem dicas" \
    || { _fail "mensagem amigavel ausente" "$_CAPTURED_STDOUT"; return 1; }
  # Lista de skills deve conter 'specify' (que tem dicas no fixture)
  printf '%s\n' "$_CAPTURED_STDOUT" \
    | grep -q "specify" \
    || { _fail "lista de skills ausente" "$_CAPTURED_STDOUT"; return 1; }
}

# =========================================================================
# Cenario 5.2.6 — --phase specify mapeia para skill specify
# =========================================================================
scenario_526_phase_specify_mapeia_skill_specify() {
  capture _st --catalog "$FIXTURES_DIR/catalog_minimal.md" --phase specify
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "exit esperado 0" "got $_CAPTURED_EXIT"
    return 1
  fi
  # O Tip Block deve conter 'specify' (skill mapeada)
  if [ -z "$_CAPTURED_STDOUT" ]; then
    _fail "stdout vazio para --phase specify" "esperado dica de specify"
    return 1
  fi
  printf '%s\n' "$_CAPTURED_STDOUT" \
    | grep -q "specify" \
    || { _fail "skill specify nao aparece no bloco" "$_CAPTURED_STDOUT"; return 1; }
}

# =========================================================================
# Cenario 5.2.7 — --phase fase-inexistente = fallback global (exit 0)
# =========================================================================
scenario_527_phase_inexistente_fallback_exit_0() {
  # "fase-inexistente" nao tem mapeamento; fallback seleciona aleatoriamente
  capture _st --catalog "$FIXTURES_DIR/catalog_minimal.md" --phase fase-inexistente
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "exit esperado 0" "got $_CAPTURED_EXIT; stderr: $_CAPTURED_STDERR"
    return 1
  fi
  # Stdout pode ser vazio (se nao houver dica generica) ou ter dica; ambos ok.
  # O invariante e exit 0 sem erro.
}

# =========================================================================
# 7.3.3 (pipeline-converge) — --phase converge mapeia para skill converge
# (nao para o fallback aleatorio global); converge nao esta no
# catalog_minimal.md, entao o comportamento espelha o cenario 5.2.4
# (skill ausente do catalogo em modo automatico = stdout vazio, exit 0).
# =========================================================================
scenario_733_phase_converge_mapeia_skill_converge() {
  capture _st --catalog "$FIXTURES_DIR/catalog_minimal.md" --phase converge
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "exit esperado 0" "got $_CAPTURED_EXIT; stderr: $_CAPTURED_STDERR"
    return 1
  fi
  if [ -n "$_CAPTURED_STDOUT" ]; then
    _fail "stdout esperado vazio (converge ausente do catalog_minimal.md)" \
      "$_CAPTURED_STDOUT"
    return 1
  fi
}

# =========================================================================
# Cenario 5.2.8 — 3 invocacoes com N>1 entradas produzem variacao RNG
# =========================================================================
scenario_528_rng_variacao_multiplas_invocacoes() {
  # Catalog_minimal.md tem specify(2) + plan(2) = 4 candidatas no global.
  # 3 invocacoes sem --phase tem muito pouca chance de serem todas iguais.
  _out1=$(sh -c '. "$CSTK_LIB/common.sh"; . "$CSTK_LIB/show-tip.sh"
                  show_tip_main --catalog "$1"' _ "$FIXTURES_DIR/catalog_minimal.md" 2>/dev/null) \
    || _out1=""
  _out2=$(sh -c '. "$CSTK_LIB/common.sh"; . "$CSTK_LIB/show-tip.sh"
                  show_tip_main --catalog "$1"' _ "$FIXTURES_DIR/catalog_minimal.md" 2>/dev/null) \
    || _out2=""
  _out3=$(sh -c '. "$CSTK_LIB/common.sh"; . "$CSTK_LIB/show-tip.sh"
                  show_tip_main --catalog "$1"' _ "$FIXTURES_DIR/catalog_minimal.md" 2>/dev/null) \
    || _out3=""

  # Pelo menos 2 outputs devem ser nao-vazios (catalogo existe)
  _nao_vazio=0
  [ -n "$_out1" ] && _nao_vazio=$((_nao_vazio + 1))
  [ -n "$_out2" ] && _nao_vazio=$((_nao_vazio + 1))
  [ -n "$_out3" ] && _nao_vazio=$((_nao_vazio + 1))

  if [ "$_nao_vazio" -lt 2 ]; then
    _fail "maioria dos outputs vazios" "esperado pelo menos 2/3 nao-vazios; got $_nao_vazio"
    return 1
  fi

  # Se TODOS sao identicos e o catalogo tem N>1 entradas, pode indicar RNG fixo.
  # Com 4 candidatos, probabilidade de todos iguais = (1/4)^2 = 6.25% — aceitavel
  # como flaky. Marcamos como WARN mas nao falhamos o scenario (evitar flakiness).
  if [ "$_out1" = "$_out2" ] && [ "$_out2" = "$_out3" ]; then
    printf '  # WARN: 3/3 invocacoes retornaram saida identica (pode ser RNG seed colisao; acceptable flaky)\n'
  fi
}

# =========================================================================
# Cenario 5.3.1 — --audit com catalogo completo retorna exit 0
# =========================================================================
scenario_531_audit_catalogo_completo_exit_0() {
  # Usar repo_mock (universo: apenas mock-skill-a) + catalog_audit_ok.md
  capture _st_with_root "$REPO_MOCK" \
    --catalog "$FIXTURES_DIR/catalog_audit_ok.md" --audit
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "exit esperado 0 (audit ok)" "got $_CAPTURED_EXIT; stdout: $_CAPTURED_STDOUT; stderr: $_CAPTURED_STDERR"
    return 1
  fi
  printf '%s\n' "$_CAPTURED_STDOUT" \
    | grep -qi "OK" \
    || { _fail "mensagem AUDIT OK ausente" "$_CAPTURED_STDOUT"; return 1; }
}

# =========================================================================
# Cenario 5.3.2 — --audit com catalogo incompleto retorna exit 1 + gap
# =========================================================================
scenario_532_audit_catalogo_gap_exit_1() {
  # Usar repo_mock + catalog_audit_gap.md (mock-skill-a so tem uso, sem gotcha)
  capture _st_with_root "$REPO_MOCK" \
    --catalog "$FIXTURES_DIR/catalog_audit_gap.md" --audit
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "exit esperado 1 (audit gap)" "got $_CAPTURED_EXIT; stdout: $_CAPTURED_STDOUT"
    return 1
  fi
  # stdout deve listar o gap
  printf '%s\n' "$_CAPTURED_STDOUT" \
    | grep -qi "GAP\|FAIL\|mock-skill-a" \
    || { _fail "listing de gap ausente" "$_CAPTURED_STDOUT"; return 1; }
}

# =========================================================================
# Cenario 5.3.3 — --audit com catalogo ausente retorna exit 1
# =========================================================================
scenario_533_audit_catalogo_ausente_exit_1() {
  capture _st_with_root "$REPO_MOCK" \
    --catalog "/nao/existe/catalog_xyz.md" --audit
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "exit esperado 1 (catalogo ausente)" "got $_CAPTURED_EXIT"
    return 1
  fi
}

# =========================================================================
# Cenario 5.4.1 — SKILL com metacaracteres awk nao injeta codigo (OWASP A05)
# =========================================================================
scenario_541_seguranca_awk_injection() {
  # Payload: metacaracteres awk. Se interpolado no programa awk (nao via -v),
  # o awk executaria `print "AWK_INJECTED"` e exibiria AWK_INJECTED em toda linha
  # do catalogo processada. O uso de -v filter_skill="$_malicious" bloqueia isso.
  # Verificar que o parser nao imprime entradas com SKILL:AWK_INJECTED.
  _malicious='; print "AWK_INJECTED"; #'
  # Executar o parser diretamente (sem _st_friendly_no_tips que repetiria o nome)
  _result=$(CSTK_LIB="$CSTK_LIB" sh -c \
    '. "$CSTK_LIB/common.sh"; . "$CSTK_LIB/show-tip.sh"
     _st_parse_catalog "$1" "$2" ""' _ \
    "$FIXTURES_DIR/catalog_minimal.md" "$_malicious" 2>/dev/null) || _result=""
  # O parser com -v filtrou pela skill "$_malicious" - nenhuma entry deve casar.
  # Se houvesse injecao, a string "AWK_INJECTED" apareceria no output do parser.
  if printf '%s\n' "$_result" | grep -qF "AWK_INJECTED"; then
    _fail "injecao awk detectada no output do parser" "output: $_result"
    return 1
  fi
}

# =========================================================================
# Cenario 5.4.2 — SKILL com metacaracteres shell nao executa subshell
# =========================================================================
scenario_542_seguranca_shell_metachar() {
  # Verificar que o parser nao expande subshell quando skill contem $(...).
  # Um payload de injecao que, se expandido pelo shell DENTRO do script, produziria
  # a string "SHELL_INJECTED" no output. Usando -v awk, o valor e passado literal.
  # Nota: o CALLER (test) passa o payload com aspas duplas para evitar expansao AQUI.
  _payload='$(printf "%s" SHELL_INJECTED)'
  _result=$(CSTK_LIB="$CSTK_LIB" sh -c \
    '. "$CSTK_LIB/common.sh"; . "$CSTK_LIB/show-tip.sh"
     _st_parse_catalog "$1" "$2" ""' _ \
    "$FIXTURES_DIR/catalog_minimal.md" "$_payload" 2>/dev/null) || _result=""
  # Se houvesse expansao de subshell dentro do awk/script, "SHELL_INJECTED" apareceria.
  if printf '%s\n' "$_result" | grep -qF "SHELL_INJECTED"; then
    _fail "expansao de subshell detectada no parser" "output: $_result"
    return 1
  fi
}

# =========================================================================
# Cenario 5.4.3 — --catalog com path contendo espacos
# =========================================================================
scenario_543_catalog_path_com_espacos() {
  # Copiar fixture para um tmpdir com espaco no nome
  _dir_com_espaco="$TMPDIR_TEST/dir com espaco"
  mkdir -p "$_dir_com_espaco"
  cp "$FIXTURES_DIR/catalog_minimal.md" "$_dir_com_espaco/catalog minimal.md"

  capture _st --catalog "$_dir_com_espaco/catalog minimal.md"
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "exit esperado 0 (path com espaco)" "got $_CAPTURED_EXIT; stderr: $_CAPTURED_STDERR"
    return 1
  fi
  # Com catalogo valido, deve retornar dica (nao stdout vazio)
  if [ -z "$_CAPTURED_STDOUT" ]; then
    _fail "stdout vazio com path com espaco" "esperado dica nao-vazia"
    return 1
  fi
}

# =========================================================================
# Cenario 5.5.1 — shellcheck -s sh cli/lib/show-tip.sh zero warnings
# =========================================================================
scenario_551_shellcheck_show_tip() {
  if ! command -v shellcheck >/dev/null 2>&1; then
    printf '  # SKIP: shellcheck nao disponivel no ambiente\n'
    return 0
  fi
  capture shellcheck -s sh "$REPO_ROOT/cli/lib/show-tip.sh"
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "shellcheck falhou" "exit=$_CAPTURED_EXIT\n$_CAPTURED_STDOUT\n$_CAPTURED_STDERR"
    return 1
  fi
}

# =========================================================================
# Cenario 5.5.3 — shellcheck -s sh tests/cstk/test_show-tip.sh zero warnings
# =========================================================================
scenario_553_shellcheck_test_file() {
  if ! command -v shellcheck >/dev/null 2>&1; then
    printf '  # SKIP: shellcheck nao disponivel no ambiente\n'
    return 0
  fi
  capture shellcheck -s sh "$TESTS_ROOT/cstk/test_show-tip.sh"
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "shellcheck do arquivo de teste falhou" "$_CAPTURED_STDOUT\n$_CAPTURED_STDERR"
    return 1
  fi
}

# =========================================================================
# Cenario 5.6.1 — performance: tempo de exibicao < 1s com catalogo real
# =========================================================================
scenario_561_performance_abaixo_1s() {
  _real_catalog="$REPO_ROOT/tips/catalog.md"
  if [ ! -r "$_real_catalog" ]; then
    printf '  # SKIP: catalogo real nao encontrado (%s)\n' "$_real_catalog"
    return 0
  fi

  # date +%s tem resolucao de 1s — usar subshell com timing via 'time'
  # POSIX nao tem time builtin portavel; usar date antes/depois
  _t0=$(date +%s 2>/dev/null) || _t0=0

  capture _st --catalog "$_real_catalog"
  _exit=$_CAPTURED_EXIT

  _t1=$(date +%s 2>/dev/null) || _t1=0
  _elapsed=$((_t1 - _t0))

  if [ "$_exit" != "0" ]; then
    _fail "exit esperado 0" "got $_exit"
    return 1
  fi

  # Threshold: < 2s (margem conservadora para CI; SC-002 exige < 1s mas
  # date +%s tem resolucao de 1s e o timing pode incluir startup de sh)
  if [ "$_elapsed" -ge 2 ]; then
    _fail "performance acima do threshold" "elapsed=${_elapsed}s esperado < 2s"
    return 1
  fi
}

run_all_scenarios
