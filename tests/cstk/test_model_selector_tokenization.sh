#!/bin/sh
# test_model_selector_tokenization.sh
#
# Cobre subtarefas 2.2.1 a 2.2.6 da feature `model-selector` (FASE 2,
# task 2.2). Valida o pipeline de tokenizacao adicionado em
# global/skills/model-selector/scripts/classify.sh.
#
# Contratos testados:
#   2.2.1  tokenizacao via tr+tr+sed produz tokens [a-z0-9]+ apos
#          lowercase + strip non-alnum.
#   2.2.2  tokens vazios sao filtrados (grep -v '^$').
#   2.2.3  input com null-byte via stdin -> exit 2 + stderr citando
#          "null-byte (rejeitado)".
#   2.2.4  fail-safe <3 tokens -> exit 0 com `manter-atual` score 0,
#          sem warning em stderr.
#   2.2.5  input >4096 chars -> warning estruturado em stderr +
#          truncamento para 4096 antes da tokenizacao.
#   2.2.6  metacaracteres do shell ($, backtick, ;, &&) sao tratados
#          como bytes literais — sem eval, sem expansao.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CLASSIFY="$REPO_ROOT/global/skills/model-selector/scripts/classify.sh"
export CLASSIFY

scenario_classify_existe_e_executavel() {
  if [ ! -x "$CLASSIFY" ]; then
    _fail "classify.sh ausente ou nao-executavel" "esperado $CLASSIFY +x"
    return 1
  fi
}

scenario_2_2_1_tokenizacao_basica_strip_non_alnum() {
  # Input "Rode, o GREP!" -> tokens: rode, o, grep. Tres tokens (>=3
  # entao nao ativa fail-safe). Como "rode" e "grep" estao no catalogo
  # (faixa rasa), output final usa esses sinais — assercao via rotulo
  # `haiku` + rasa>=2. Se tokenizacao quebrasse (e.g. nao
  # lowercase-asse "GREP" ou nao removesse pontuacao de "Rode,"),
  # nenhum match aconteceria.
  _out=$(sh "$CLASSIFY" "Rode, o GREP!" 2>/dev/null) || {
    _fail "exit-code != 0" "esperado 0 para input bem-formado"
    return 1
  }
  if ! printf '%s' "$_out" | grep -qE '^rasa=2 '; then
    _fail "tokenizacao nao casou rode+grep" "$(printf '%s' "$_out" | head -10)"
    return 1
  fi
}

scenario_2_2_2_tokens_vazios_filtrados() {
  # Input "a    b    c" (4 espacos entre) -> 3 tokens, sem entradas
  # vazias. Nenhum desses bate no catalogo, mas a justificativa cita
  # "nos 3 tokens validos do input" — se filtro nao funcionasse e
  # tokens vazios contassem, justificativa citaria N>3.
  _out=$(sh "$CLASSIFY" "a    b    c" 2>/dev/null) || {
    _fail "exit != 0 em input com multiplos espacos" ""
    return 1
  }
  if ! printf '%s' "$_out" | grep -q 'nos 3 tokens validos'; then
    _fail "filtro de tokens vazios falhou" "esperado '3 tokens validos', obtido: $(printf '%s' "$_out" | grep tokens)"
    return 1
  fi
}

scenario_2_2_3_null_byte_via_stdin_rejeitado() {
  # NUL via stdin: $(cat) preserva via tmpfile; deteccao via byte-count
  # comparativo. Esperado exit 2 + mensagem especifica.
  _stderr_file=$(mktemp -t classify-test.XXXXXX) || { _error "mktemp falhou"; return 2; }
  _ec=0
  printf 'rode\0o\0grep' | sh "$CLASSIFY" >/dev/null 2>"$_stderr_file" || _ec=$?
  _stderr=$(cat "$_stderr_file")
  rm -f -- "$_stderr_file"

  if [ "$_ec" != "2" ]; then
    _fail "exit-code esperado 2, obtido $_ec" "stderr: $_stderr"
    return 1
  fi
  if ! printf '%s' "$_stderr" | grep -q 'null-byte (rejeitado)'; then
    _fail "stderr nao cita null-byte (rejeitado)" "stderr: $_stderr"
    return 1
  fi
}

scenario_2_2_4_fail_safe_menos_de_3_tokens() {
  # Input "rode" -> 1 token -> fail-safe. exit 0, sem warning em
  # stderr, output cita "manter-atual" score 0 e fail-safe.
  _stderr_file=$(mktemp -t classify-test.XXXXXX) || { _error "mktemp falhou"; return 2; }
  _out=$(sh "$CLASSIFY" "rode" 2>"$_stderr_file")
  _ec=$?
  _stderr=$(cat "$_stderr_file")
  rm -f -- "$_stderr_file"

  if [ "$_ec" != "0" ]; then
    _fail "fail-safe deveria exit 0, obtido $_ec" "stderr: $_stderr"
    return 1
  fi
  # Output final (2.5.1) usa secao "## Modelo Sugerido" com rotulo
  # abstrato. Linha grep-able `... modelo=manter-atual ...` esta
  # dentro de "## Score". Ambas atestam o branch fail-safe.
  if ! printf '%s' "$_out" | grep -q 'modelo=manter-atual'; then
    _fail "output sem 'manter-atual'" "$(printf '%s' "$_out" | head -10)"
    return 1
  fi
  # Justificativa de fail-safe cita "<3 = limite minimo" e
  # "classificador requer >=3 tokens validos". Substitui assercao
  # antiga "fail-safe ativado" (texto intermediario da 2.2).
  if ! printf '%s' "$_out" | grep -q '<3 = limite minimo'; then
    _fail "justificativa sem citacao da regra fail-safe" "$(printf '%s' "$_out" | head -20)"
    return 1
  fi
  # Fail-safe NAO deve gerar warning em stderr (regra: ruido zero).
  if [ -n "$_stderr" ]; then
    _fail "fail-safe gerou stderr (esperado vazio)" "stderr: $_stderr"
    return 1
  fi
}

scenario_2_2_5_truncamento_acima_4096_chars() {
  # Gera input com ~5500 chars. Esperado: warning em stderr citando
  # "4096" e exit 0 (truncamento e nao-fatal).
  _long=""
  _i=0
  # 1100 * 5 = 5500 chars (cada "rode " = 5 chars com espaco).
  while [ "$_i" -lt 1100 ]; do
    _long="${_long}rode "
    _i=$((_i + 1))
  done

  _stderr_file=$(mktemp -t classify-test.XXXXXX) || { _error "mktemp falhou"; return 2; }
  _ec=0
  sh "$CLASSIFY" "$_long" >/dev/null 2>"$_stderr_file" || _ec=$?
  _stderr=$(cat "$_stderr_file")
  rm -f -- "$_stderr_file"

  if [ "$_ec" != "0" ]; then
    _fail "truncamento deveria exit 0, obtido $_ec" "stderr: $_stderr"
    return 1
  fi
  if ! printf '%s' "$_stderr" | grep -q '4096'; then
    _fail "warning de truncamento nao cita 4096" "stderr: $_stderr"
    return 1
  fi
  if ! printf '%s' "$_stderr" | grep -q 'warning'; then
    _fail "stderr nao usa prefixo 'warning'" "stderr: $_stderr"
    return 1
  fi
}

scenario_2_2_6_metacaracteres_sem_eval() {
  # Input contem $, backtick, ;, && — se houvesse eval, $(whoami)
  # expandiria. Tokenizacao trata como string literal: os tokens
  # finais sao apenas as palavras alfanumericas remanescentes apos
  # strip de non-alnum.
  _out=$(sh "$CLASSIFY" 'echo $(whoami) ; rm -rf /' 2>/dev/null) || {
    _fail "exit != 0 em input com metacaracteres" ""
    return 1
  }
  # Output NUNCA deve conter o username real (assercao defensiva
  # contra eval). `whoami` no host = `jot`; se aparecesse em output
  # da skill, sinal de expansao indevida.
  _user=$(whoami)
  if printf '%s' "$_out" | grep -q "user.*$_user\|hostname"; then
    _fail "metacaracter expandido (sinal de eval!)" "$(printf '%s' "$_out" | head -10)"
    return 1
  fi
  # Tokens esperados apos strip: echo, whoami, rm, rf -> 4 tokens
  # (`$()` -> vazio, `/` -> vazio, `-` -> vazio apos sed). Nenhum bate
  # no catalogo MVP (echo/whoami/rm/rf nao listados), entao
  # justificativa cita "nos 4 tokens validos do input".
  if ! printf '%s' "$_out" | grep -q 'nos 4 tokens validos'; then
    _fail "tokenizacao de metacaracteres falhou" "esperado '4 tokens validos', obtido: $(printf '%s' "$_out" | grep tokens)"
    return 1
  fi
}

scenario_smoke_input_normal_ainda_funciona() {
  # Regressao: garantir que comportamento da onda anterior (task 2.1)
  # nao quebrou. Input bem-formado normal deve exit 0 com output
  # markdown valido.
  _out=$(sh "$CLASSIFY" "rode o grep no arquivo" 2>/dev/null) || {
    _fail "regressao em smoke" ""
    return 1
  }
  # Output final (subtarefa 2.5.1) renomeou "## Sugestao" -> 4 secoes
  # fixas comecando por "## Modelo Sugerido". Smoke test verifica
  # presenca do novo cabecalho.
  if ! printf '%s' "$_out" | grep -q '## Modelo Sugerido'; then
    _fail "output sem secao '## Modelo Sugerido'" ""
    return 1
  fi
}

run_all_scenarios
