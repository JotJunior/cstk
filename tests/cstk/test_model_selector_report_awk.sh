#!/bin/sh
# test_model_selector_report_awk.sh
#
# Cobre subtarefas 4.3.1-4.3.3 da feature `model-selector` (Ref:
# docs/specs/model-selector/tasks.md L224-L230, FR-010a (a), CHK012,
# CHK014, Decision 5 do research.md). Valida o caminho `awk` puro de
# `scripts/report.sh` (HAS_JQ=0):
#
#   4.3.1  bloco `else` parsing linha-a-linha do state.json via awk
#          puro, sem invocar jq.
#   4.3.2  output BYTE-IDENTICAL ao caminho jq da task 4.2 (whitespace,
#          ordem de colunas, casas decimais identicas) — verificado via
#          `diff` exit 0 e/ou sha256 igual sobre a tabela markdown.
#   4.3.3  limitacoes conhecidas do fallback documentadas no proprio
#          script (bloco de comentarios 4.3.3 + comportamento testado
#          aqui para os casos cobertos: state.json multi-linha, lazy
#          null, total=0).
#
# Estrategia para forcar HAS_JQ=0:
#   Criamos um diretorio `fake-bin/` em $TMPDIR_TEST com symlinks
#   APENAS para as ferramentas POSIX que o script precisa (sh, awk,
#   tr, cat, printf, basename, etc.) — DELIBERADAMENTE OMITINDO `jq`.
#   Quando rodamos `report.sh` com `PATH="$fake_bin"`, o
#   `command -v jq` interno retorna falso, HAS_JQ=0, e o ramo awk
#   eh exercitado.
#
#   Esse mecanismo eh equivalente ao plano do test 4.4.1 (esse teste
#   adicional faz a mesma coisa em modo isolado, cobrindo paridade
#   POR-CENARIO). O test 4.4.1 emergira depois com confinamento
#   adicional + performance.
#
# Pre-requisito: jq DEVE estar no PATH default — sem jq, nao temos
# baseline para comparar. Cenarios marcam ERROR (status 2) nesse caso.
#
# Cenarios cobertos:
#   1. uma_feature: 1 state.json populado, parser awk emite linha valida
#   2. byte_identical_alpha: paridade byte-a-byte da TABELA entre jq e awk
#   3. byte_identical_lazy_null: paridade no caso "(sem dados)" por ausencia
#   4. byte_identical_total_zero: paridade no caso "(sem dados)" por bag=0
#   5. byte_identical_tie_break: paridade no tie-break alfabetico
#   6. byte_identical_basename_fallback: paridade quando short_name ausente
#   7. byte_identical_multi_files: paridade com 3 inputs agregados
#   8. byte_identical_compact_json: paridade com state.json single-line
#   9. read_only_sha256_imutavel: caminho awk nao escreve no input
#  10. fallback_emits_jq_detectado_zero: tag de auditoria indica ramo

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

REPORT="$REPO_ROOT/plugins/cstk/skills/model-selector/scripts/report.sh"
export REPORT

# ----------------------------------------------------------------------
# Helpers locais — prefixo `_aw_` para evitar colisao com outros tests.
# ----------------------------------------------------------------------

_aw_skip_if_no_jq() {
  # Precisamos de jq no PATH DEFAULT para gerar o baseline contra o
  # qual comparamos a saida awk. Sem jq, nao ha contrato byte-identical
  # observavel.
  if ! command -v jq >/dev/null 2>&1; then
    printf 'harness: jq ausente no PATH — baseline para paridade nao gerado\n' >&2
    return 2
  fi
  return 0
}

# Cria um diretorio $TMPDIR_TEST/fake-bin com TODAS as ferramentas POSIX
# que report.sh precisa, EXCETO jq. PATH=$fake_bin -> command -v jq falso
# -> ramo HAS_JQ=0 exercitado.
_aw_setup_fake_bin() {
  _aw_fb="$TMPDIR_TEST/fake-bin"
  mkdir -p "$_aw_fb" || return 2
  # Tools listados aqui sao TODOS os comandos invocados por report.sh
  # + os que harness/scenario podem precisar para inspecao.
  for _tool in sh awk tr cat printf basename grep sed mktemp rm chmod \
               diff sha256sum shasum od; do
    _aw_real=$(command -v "$_tool" 2>/dev/null) || continue
    ln -sf "$_aw_real" "$_aw_fb/$_tool" 2>/dev/null || :
  done
  # Confirma que jq NAO ficou exposto (sanity-check).
  if PATH="$_aw_fb" command -v jq >/dev/null 2>&1; then
    printf 'harness: fake-bin vazou jq — abortando paridade\n' >&2
    return 2
  fi
  export _aw_fb
  return 0
}

_aw_write_state_full() {
  # _aw_write_state_full <path> <short_name> <h> <s> <o> <m> <aceitas> <rejeitadas>
  _aw_p=$1; _aw_name=$2; _aw_h=$3; _aw_s=$4; _aw_o=$5; _aw_m=$6
  _aw_ac=$7; _aw_re=$8
  _aw_total=$((_aw_h + _aw_s + _aw_o + _aw_m))
  cat > "$_aw_p" <<EOF
{
  "execucao": { "short_name": "$_aw_name" },
  "metricas_acumuladas": {
    "model_selector": {
      "sugestoes_total": $_aw_total,
      "por_modelo_sugerido": {
        "haiku": $_aw_h, "sonnet": $_aw_s, "opus": $_aw_o, "manter-atual": $_aw_m
      },
      "por_resultado": {
        "aceitas": $_aw_ac, "rejeitadas": $_aw_re, "no_op_ja_no_modelo": 0
      },
      "ultima_invocacao_iso": "2026-05-21T10:00:00Z"
    }
  }
}
EOF
}

# Extrai apenas a porcao "tabela" do relatorio (do cabecalho `| feature `
# em diante). O comentario `<!-- jq_detectado=N ... -->` legitimamente
# difere entre os dois ramos (tag de auditoria) e nao faz parte do
# contrato byte-identical da subtarefa 4.3.2.
_aw_table_portion() {
  sed -n '/^| feature /,$p'
}

# ----------------------------------------------------------------------
# 4.3.1.a: parsing awk emite linha valida para 1 state.json populado
# ----------------------------------------------------------------------
scenario_4_3_1_uma_feature_awk_funciona() {
  _aw_skip_if_no_jq || return 2
  mktemp_test || return 2
  _aw_setup_fake_bin || return 2
  _s="$TMPDIR_TEST/sA.json"
  _aw_write_state_full "$_s" "alpha-feat" 3 1 1 0 4 1
  capture env PATH="$_aw_fb" sh "$REPORT" "$_s"
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "uma_feature_awk_exit" "esperado 0, obtido: $_CAPTURED_EXIT (stderr=$_CAPTURED_STDERR)"
    return 1
  fi
  case "$_CAPTURED_STDOUT" in
    *"| alpha-feat | 5 | 4 | 1 | haiku |"*) ;;
    *)
      _fail "uma_feature_awk_linha" \
        "stdout awk nao contem linha esperada de alpha-feat: $_CAPTURED_STDOUT"
      return 1
      ;;
  esac
  return 0
}

# ----------------------------------------------------------------------
# 4.3.2.a: paridade BYTE-A-BYTE da TABELA — caso happy-path haiku.
# ----------------------------------------------------------------------
scenario_4_3_2_byte_identical_alpha() {
  _aw_skip_if_no_jq || return 2
  mktemp_test || return 2
  _aw_setup_fake_bin || return 2
  _s="$TMPDIR_TEST/alpha.json"
  _aw_write_state_full "$_s" "alpha-feat" 3 1 1 0 4 1
  _aw_out_jq=$(sh "$REPORT" "$_s" | _aw_table_portion)
  _aw_out_awk=$(env PATH="$_aw_fb" sh "$REPORT" "$_s" | _aw_table_portion)
  if [ "$_aw_out_jq" != "$_aw_out_awk" ]; then
    _fail "byte_identical_alpha" \
      "tabela diverge entre jq e awk; jq=[$_aw_out_jq] awk=[$_aw_out_awk]"
    return 1
  fi
  return 0
}

# ----------------------------------------------------------------------
# 4.3.2.b: paridade no caso lazy null (sem metricas_acumuladas.model_selector)
# ----------------------------------------------------------------------
scenario_4_3_2_byte_identical_lazy_null() {
  _aw_skip_if_no_jq || return 2
  mktemp_test || return 2
  _aw_setup_fake_bin || return 2
  _s="$TMPDIR_TEST/lazy.json"
  cat > "$_s" <<'EOF'
{ "execucao": { "short_name": "charlie-feat" }, "metricas_acumuladas": { "ondas_total": 2 } }
EOF
  _aw_out_jq=$(sh "$REPORT" "$_s" | _aw_table_portion)
  _aw_out_awk=$(env PATH="$_aw_fb" sh "$REPORT" "$_s" | _aw_table_portion)
  if [ "$_aw_out_jq" != "$_aw_out_awk" ]; then
    _fail "byte_identical_lazy_null" \
      "tabela diverge no lazy null; jq=[$_aw_out_jq] awk=[$_aw_out_awk]"
    return 1
  fi
  case "$_aw_out_awk" in
    *"| charlie-feat | 0 | 0 | 0 | (sem dados) |"*) ;;
    *)
      _fail "byte_identical_lazy_null_linha" \
        "linha (sem dados) ausente em awk: $_aw_out_awk"
      return 1
      ;;
  esac
  return 0
}

# ----------------------------------------------------------------------
# 4.3.2.c: paridade no caso total>0 mas por_modelo_sugerido tudo-zero
# (mode = "(sem dados)" mesmo com sugestoes_total > 0)
# ----------------------------------------------------------------------
scenario_4_3_2_byte_identical_total_zero_mode_zero() {
  _aw_skip_if_no_jq || return 2
  mktemp_test || return 2
  _aw_setup_fake_bin || return 2
  _s="$TMPDIR_TEST/weird.json"
  _aw_write_state_full "$_s" "weird-feat" 0 0 0 0 3 2
  # Re-escreve com sugestoes_total != 0 mas bag zerado manualmente
  cat > "$_s" <<'EOF'
{
  "execucao": { "short_name": "weird-feat" },
  "metricas_acumuladas": {
    "model_selector": {
      "sugestoes_total": 5,
      "por_modelo_sugerido": { "haiku": 0, "sonnet": 0, "opus": 0, "manter-atual": 0 },
      "por_resultado": { "aceitas": 3, "rejeitadas": 2, "no_op_ja_no_modelo": 0 }
    }
  }
}
EOF
  _aw_out_jq=$(sh "$REPORT" "$_s" | _aw_table_portion)
  _aw_out_awk=$(env PATH="$_aw_fb" sh "$REPORT" "$_s" | _aw_table_portion)
  if [ "$_aw_out_jq" != "$_aw_out_awk" ]; then
    _fail "byte_identical_total_zero_mode_zero" \
      "tabela diverge em bag-zero; jq=[$_aw_out_jq] awk=[$_aw_out_awk]"
    return 1
  fi
  case "$_aw_out_awk" in
    *"| weird-feat | 5 | 3 | 2 | (sem dados) |"*) ;;
    *)
      _fail "byte_identical_total_zero_mode_zero_linha" \
        "linha esperada ausente: $_aw_out_awk"
      return 1
      ;;
  esac
  return 0
}

# ----------------------------------------------------------------------
# 4.3.2.d: paridade no tie-break alfabetico (haiku < manter-atual <
# opus < sonnet). Empate haiku=2 sonnet=2 -> haiku vence.
# ----------------------------------------------------------------------
scenario_4_3_2_byte_identical_tie_break_alfabetico() {
  _aw_skip_if_no_jq || return 2
  mktemp_test || return 2
  _aw_setup_fake_bin || return 2
  _s="$TMPDIR_TEST/tie.json"
  _aw_write_state_full "$_s" "tie-feat" 2 2 0 0 4 0
  _aw_out_jq=$(sh "$REPORT" "$_s" | _aw_table_portion)
  _aw_out_awk=$(env PATH="$_aw_fb" sh "$REPORT" "$_s" | _aw_table_portion)
  if [ "$_aw_out_jq" != "$_aw_out_awk" ]; then
    _fail "byte_identical_tie_break" \
      "tabela diverge em tie-break; jq=[$_aw_out_jq] awk=[$_aw_out_awk]"
    return 1
  fi
  case "$_aw_out_awk" in
    *"| tie-feat | 4 | 4 | 0 | haiku |"*) ;;
    *)
      _fail "byte_identical_tie_break_linha" \
        "tie-break nao escolheu haiku: $_aw_out_awk"
      return 1
      ;;
  esac
  return 0
}

# ----------------------------------------------------------------------
# 4.3.2.e: paridade quando short_name ausente — feature = basename
# ----------------------------------------------------------------------
scenario_4_3_2_byte_identical_basename_fallback() {
  _aw_skip_if_no_jq || return 2
  mktemp_test || return 2
  _aw_setup_fake_bin || return 2
  _s="$TMPDIR_TEST/orphan-feature.json"
  cat > "$_s" <<'EOF'
{ "metricas_acumuladas": { "model_selector": { "sugestoes_total": 2, "por_modelo_sugerido": {"haiku":2,"sonnet":0,"opus":0,"manter-atual":0}, "por_resultado": {"aceitas":2,"rejeitadas":0,"no_op_ja_no_modelo":0} } } }
EOF
  _aw_out_jq=$(sh "$REPORT" "$_s" | _aw_table_portion)
  _aw_out_awk=$(env PATH="$_aw_fb" sh "$REPORT" "$_s" | _aw_table_portion)
  if [ "$_aw_out_jq" != "$_aw_out_awk" ]; then
    _fail "byte_identical_basename_fallback" \
      "tabela diverge em basename fallback; jq=[$_aw_out_jq] awk=[$_aw_out_awk]"
    return 1
  fi
  case "$_aw_out_awk" in
    *"| orphan-feature | 2 | 2 | 0 | haiku |"*) ;;
    *)
      _fail "byte_identical_basename_fallback_linha" \
        "linha com basename ausente: $_aw_out_awk"
      return 1
      ;;
  esac
  return 0
}

# ----------------------------------------------------------------------
# 4.3.2.f: paridade com MULTIPLOS state.json passados (3 inputs)
# Garante que a ordem de linhas eh preservada e que cada feature
# eh agregada independentemente entre os dois ramos.
# ----------------------------------------------------------------------
scenario_4_3_2_byte_identical_multi_files() {
  _aw_skip_if_no_jq || return 2
  mktemp_test || return 2
  _aw_setup_fake_bin || return 2
  _a="$TMPDIR_TEST/a.json"
  _b="$TMPDIR_TEST/b.json"
  _c="$TMPDIR_TEST/c.json"
  _aw_write_state_full "$_a" "alpha-feat" 3 1 1 0 4 1
  _aw_write_state_full "$_b" "bravo-feat" 1 2 1 0 2 2
  _aw_write_state_full "$_c" "delta-feat" 0 0 3 0 2 1
  _aw_out_jq=$(sh "$REPORT" "$_a" "$_b" "$_c" | _aw_table_portion)
  _aw_out_awk=$(env PATH="$_aw_fb" sh "$REPORT" "$_a" "$_b" "$_c" | _aw_table_portion)
  if [ "$_aw_out_jq" != "$_aw_out_awk" ]; then
    _fail "byte_identical_multi_files" \
      "tabela diverge em multi-files; jq=[$_aw_out_jq] awk=[$_aw_out_awk]"
    return 1
  fi
  return 0
}

# ----------------------------------------------------------------------
# 4.3.2.g: paridade com state.json compact (single-line, sem jq pretty)
# Cobre a limitacao documentada L1: parser awk normaliza via tr -d '\n'
# antes do match, entao compact e jq-pretty produzem o mesmo resultado.
# ----------------------------------------------------------------------
scenario_4_3_2_byte_identical_compact_json() {
  _aw_skip_if_no_jq || return 2
  mktemp_test || return 2
  _aw_setup_fake_bin || return 2
  _s="$TMPDIR_TEST/compact.json"
  printf '%s' \
    '{"execucao":{"short_name":"compact-feat"},"metricas_acumuladas":{"model_selector":{"sugestoes_total":3,"por_modelo_sugerido":{"haiku":1,"sonnet":2,"opus":0,"manter-atual":0},"por_resultado":{"aceitas":2,"rejeitadas":1,"no_op_ja_no_modelo":0}}}}' \
    > "$_s"
  _aw_out_jq=$(sh "$REPORT" "$_s" | _aw_table_portion)
  _aw_out_awk=$(env PATH="$_aw_fb" sh "$REPORT" "$_s" | _aw_table_portion)
  if [ "$_aw_out_jq" != "$_aw_out_awk" ]; then
    _fail "byte_identical_compact_json" \
      "tabela diverge em compact json; jq=[$_aw_out_jq] awk=[$_aw_out_awk]"
    return 1
  fi
  case "$_aw_out_awk" in
    *"| compact-feat | 3 | 2 | 1 | sonnet |"*) ;;
    *)
      _fail "byte_identical_compact_json_linha" \
        "linha compact-feat ausente: $_aw_out_awk"
      return 1
      ;;
  esac
  return 0
}

# ----------------------------------------------------------------------
# 4.3.1.b: caminho awk preserva read-only do(s) input(s) — sha256
# imutavel pos invocacao. Mesma garantia testada para o caminho jq em
# scenario_4_2_1_read_only_sha256_imutavel.
# ----------------------------------------------------------------------
scenario_4_3_1_read_only_sha256_imutavel() {
  _aw_skip_if_no_jq || return 2
  mktemp_test || return 2
  _aw_setup_fake_bin || return 2
  _a="$TMPDIR_TEST/ro_a.json"
  _b="$TMPDIR_TEST/ro_b.json"
  _aw_write_state_full "$_a" "ro-alpha" 2 1 0 0 3 0
  _aw_write_state_full "$_b" "ro-bravo" 0 2 1 0 3 0

  _hash_cmd=""
  if command -v shasum >/dev/null 2>&1; then
    _hash_cmd="shasum -a 256"
  elif command -v sha256sum >/dev/null 2>&1; then
    _hash_cmd="sha256sum"
  else
    printf 'harness: nenhum shasum/sha256sum disponivel\n' >&2
    return 2
  fi

  _sa_pre=$($_hash_cmd "$_a" | awk '{print $1}')
  _sb_pre=$($_hash_cmd "$_b" | awk '{print $1}')
  capture env PATH="$_aw_fb" sh "$REPORT" "$_a" "$_b"
  _sa_post=$($_hash_cmd "$_a" | awk '{print $1}')
  _sb_post=$($_hash_cmd "$_b" | awk '{print $1}')

  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "ro_awk_exit" "esperado 0, obtido: $_CAPTURED_EXIT"
    return 1
  fi
  if [ "$_sa_pre" != "$_sa_post" ]; then
    _fail "ro_awk_mutated_a" "sha256 mudou em ro_a: $_sa_pre -> $_sa_post"
    return 1
  fi
  if [ "$_sb_pre" != "$_sb_post" ]; then
    _fail "ro_awk_mutated_b" "sha256 mudou em ro_b: $_sb_pre -> $_sb_post"
    return 1
  fi
  return 0
}

# ----------------------------------------------------------------------
# 4.3.1.c: tag de auditoria `jq_detectado=0` emitida no header quando
# o ramo awk eh tomado. Garante que operador consegue distinguir qual
# ramo gerou o relatorio sem inspecionar timing/perf.
# ----------------------------------------------------------------------
scenario_4_3_1_fallback_emits_jq_detectado_zero() {
  _aw_skip_if_no_jq || return 2
  mktemp_test || return 2
  _aw_setup_fake_bin || return 2
  _s="$TMPDIR_TEST/audit.json"
  _aw_write_state_full "$_s" "audit-feat" 1 0 0 0 1 0
  capture env PATH="$_aw_fb" sh "$REPORT" "$_s"
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "audit_exit" "esperado 0, obtido: $_CAPTURED_EXIT"
    return 1
  fi
  case "$_CAPTURED_STDOUT" in
    *"<!-- jq_detectado=0 "*) ;;
    *)
      _fail "audit_tag" \
        "tag de auditoria jq_detectado=0 ausente: $_CAPTURED_STDOUT"
      return 1
      ;;
  esac
  return 0
}

run_all_scenarios
