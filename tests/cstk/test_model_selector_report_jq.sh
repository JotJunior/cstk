#!/bin/sh
# test_model_selector_report_jq.sh
#
# Cobre subtarefas 4.2.1-4.2.3 da feature `model-selector` (Ref:
# docs/specs/model-selector/tasks.md L218-L220, FR-010a (a), Decision 5
# do research.md). Valida o caminho jq happy-path do report.sh:
#
#   4.2.1  bloco `if HAS_JQ=1` agrega `metricas_acumuladas.model_selector`
#          via expressao jq compacta — uma linha por arquivo de input.
#   4.2.2  tabela markdown com colunas FIXAS:
#          feature | sugestoes_total | aceitas | rejeitadas | modelo_final_predominante
#   4.2.3  documentacao inline declarando este como caminho PREFERIDO,
#          com awk como fallback equivalente em 4.3.
#
# Pre-requisito: este teste so e SIGNIFICATIVO quando `jq` esta no PATH
#   (caminho 4.2). Em ambientes sem jq, os scenarios sao marcados como
#   ERROR (status 2) — nao FAIL — para nao mascarar o gap. O teste de
#   equivalencia byte-identical com fallback awk vive em 4.4.1.
#
# Cenarios cobertos:
#   1 state.json com mode haiku       -> linha unica, predominante=haiku
#   2 state.json (haiku + sonnet)     -> 2 linhas, mode por feature
#   state.json sem model_selector     -> linha "(sem dados)" + zeros
#   state.json sem short_name          -> feature = basename do arquivo
#   tabela tem header markdown fixo   -> 5 colunas exatas, ordem fixa
#   leitura permanece read-only        -> sha256 dos inputs imutavel
#   tie alfabetico em por_modelo_sugerido -> menor chave vence

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

REPORT="$REPO_ROOT/global/skills/model-selector/scripts/report.sh"
export REPORT

# ----------------------------------------------------------------------
# Helpers locais (escrita de fixtures inline para isolar cenarios)
# ----------------------------------------------------------------------

_skip_if_no_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    printf 'harness: jq ausente no PATH — cenario do caminho 4.2 nao avaliavel\n' >&2
    return 2
  fi
  return 0
}

_write_state_full() {
  # _write_state_full <path> <short_name> <h> <s> <o> <m> <aceitas> <rejeitadas>
  # NB: usamos prefixo `_ws_` em TODAS as variaveis locais para evitar
  # colisao com vars do caller (especialmente `_s` que muitos scenarios
  # usam como path do state.json — colisao causou exit=2 silencioso).
  _ws_p=$1; _ws_name=$2; _ws_h=$3; _ws_s=$4; _ws_o=$5; _ws_m=$6
  _ws_ac=$7; _ws_re=$8
  _ws_total=$((_ws_h + _ws_s + _ws_o + _ws_m))
  cat > "$_ws_p" <<EOF
{
  "execucao": { "short_name": "$_ws_name" },
  "metricas_acumuladas": {
    "model_selector": {
      "sugestoes_total": $_ws_total,
      "por_modelo_sugerido": {
        "haiku": $_ws_h, "sonnet": $_ws_s, "opus": $_ws_o, "manter-atual": $_ws_m
      },
      "por_resultado": {
        "aceitas": $_ws_ac, "rejeitadas": $_ws_re, "no_op_ja_no_modelo": 0
      },
      "ultima_invocacao_iso": "2026-05-21T10:00:00Z"
    }
  }
}
EOF
}

# ----------------------------------------------------------------------
# 4.2.1.a: 1 state.json populado -> linha unica, mode haiku
# ----------------------------------------------------------------------
scenario_4_2_1_uma_feature_mode_haiku() {
  _skip_if_no_jq || return 2
  mktemp_test || return 2
  _s="$TMPDIR_TEST/sA.json"
  _write_state_full "$_s" "alpha-feat" 3 1 1 0 4 1
  capture sh "$REPORT" "$_s"
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "uma_feature_exit" "esperado 0, obtido: $_CAPTURED_EXIT"
    return 1
  fi
  case "$_CAPTURED_STDOUT" in
    *"| alpha-feat | 5 | 4 | 1 | haiku |"*) ;;
    *)
      _fail "uma_feature_linha" \
        "stdout nao contem linha esperada de alpha-feat: $_CAPTURED_STDOUT"
      return 1
      ;;
  esac
  return 0
}

# ----------------------------------------------------------------------
# 4.2.1.b: 2 state.json agregados, modes distintos por feature
# ----------------------------------------------------------------------
scenario_4_2_1_duas_features_modes_distintos() {
  _skip_if_no_jq || return 2
  mktemp_test || return 2
  _a="$TMPDIR_TEST/a.json"
  _b="$TMPDIR_TEST/b.json"
  _write_state_full "$_a" "alpha-feat" 3 1 1 0 4 1
  _write_state_full "$_b" "bravo-feat" 1 2 1 0 2 2
  capture sh "$REPORT" "$_a" "$_b"
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "duas_features_exit" "esperado 0, obtido: $_CAPTURED_EXIT"
    return 1
  fi
  case "$_CAPTURED_STDOUT" in
    *"| alpha-feat | 5 | 4 | 1 | haiku |"*) ;;
    *)
      _fail "duas_features_alpha" \
        "linha alpha-feat ausente: $_CAPTURED_STDOUT"
      return 1
      ;;
  esac
  case "$_CAPTURED_STDOUT" in
    *"| bravo-feat | 4 | 2 | 2 | sonnet |"*) ;;
    *)
      _fail "duas_features_bravo" \
        "linha bravo-feat ausente: $_CAPTURED_STDOUT"
      return 1
      ;;
  esac
  return 0
}

# ----------------------------------------------------------------------
# 4.2.1.c: state.json SEM metricas_acumuladas.model_selector (lazy null)
# -> deve emitir linha com zeros + "(sem dados)" (tratamento gracioso,
#    nao quebrar relatorio para os demais inputs).
# ----------------------------------------------------------------------
scenario_4_2_1_lazy_null_sem_dados() {
  _skip_if_no_jq || return 2
  mktemp_test || return 2
  _s="$TMPDIR_TEST/lazy.json"
  cat > "$_s" <<'EOF'
{ "execucao": { "short_name": "charlie-feat" }, "metricas_acumuladas": { "ondas_total": 2 } }
EOF
  capture sh "$REPORT" "$_s"
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "lazy_exit" "esperado 0, obtido: $_CAPTURED_EXIT (stderr=$_CAPTURED_STDERR)"
    return 1
  fi
  case "$_CAPTURED_STDOUT" in
    *"| charlie-feat | 0 | 0 | 0 | (sem dados) |"*) ;;
    *)
      _fail "lazy_linha" \
        "stdout nao contem linha lazy esperada: $_CAPTURED_STDOUT"
      return 1
      ;;
  esac
  return 0
}

# ----------------------------------------------------------------------
# 4.2.1.d: state.json SEM execucao.short_name -> feature = basename
# ----------------------------------------------------------------------
scenario_4_2_1_fallback_basename_sem_short_name() {
  _skip_if_no_jq || return 2
  mktemp_test || return 2
  _s="$TMPDIR_TEST/orphan-feature.json"
  cat > "$_s" <<'EOF'
{ "metricas_acumuladas": { "model_selector": { "sugestoes_total": 2, "por_modelo_sugerido": {"haiku":2,"sonnet":0,"opus":0,"manter-atual":0}, "por_resultado": {"aceitas":2,"rejeitadas":0,"no_op_ja_no_modelo":0} } } }
EOF
  capture sh "$REPORT" "$_s"
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "fallback_exit" "esperado 0, obtido: $_CAPTURED_EXIT"
    return 1
  fi
  case "$_CAPTURED_STDOUT" in
    *"| orphan-feature | 2 | 2 | 0 | haiku |"*) ;;
    *)
      _fail "fallback_linha" \
        "stdout nao contem linha com basename de fallback: $_CAPTURED_STDOUT"
      return 1
      ;;
  esac
  return 0
}

# ----------------------------------------------------------------------
# 4.2.2.a: tabela markdown tem header com 5 colunas FIXAS na ordem
# correta + linha de separador
# ----------------------------------------------------------------------
scenario_4_2_2_header_5_colunas_ordem_fixa() {
  _skip_if_no_jq || return 2
  mktemp_test || return 2
  _s="$TMPDIR_TEST/h.json"
  _write_state_full "$_s" "feat-h" 1 0 0 0 1 0
  capture sh "$REPORT" "$_s"
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "header_exit" "esperado 0, obtido: $_CAPTURED_EXIT"
    return 1
  fi
  case "$_CAPTURED_STDOUT" in
    *"| feature | sugestoes_total | aceitas | rejeitadas | modelo_final_predominante |"*) ;;
    *)
      _fail "header_5_colunas" \
        "header markdown nao tem 5 colunas exatas na ordem fixa: $_CAPTURED_STDOUT"
      return 1
      ;;
  esac
  case "$_CAPTURED_STDOUT" in
    *"|---|---:|---:|---:|---|"*) ;;
    *)
      _fail "header_separador" \
        "linha de separador markdown ausente: $_CAPTURED_STDOUT"
      return 1
      ;;
  esac
  return 0
}

# ----------------------------------------------------------------------
# 4.2.1.e: read-only enforcement — sha256 dos inputs IMUTAVEL pos
# invocacao do caminho jq (regressao guard alinhada com 4.1.3)
# ----------------------------------------------------------------------
scenario_4_2_1_read_only_sha256_imutavel() {
  _skip_if_no_jq || return 2
  mktemp_test || return 2
  _a="$TMPDIR_TEST/ro_a.json"
  _b="$TMPDIR_TEST/ro_b.json"
  _write_state_full "$_a" "ro-alpha" 2 1 0 0 3 0
  _write_state_full "$_b" "ro-bravo" 0 2 1 0 3 0

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
  capture sh "$REPORT" "$_a" "$_b"
  _sa_post=$($_hash_cmd "$_a" | awk '{print $1}')
  _sb_post=$($_hash_cmd "$_b" | awk '{print $1}')

  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "ro_exit" "esperado 0, obtido: $_CAPTURED_EXIT"
    return 1
  fi
  if [ "$_sa_pre" != "$_sa_post" ]; then
    _fail "ro_mutated_a" "sha256 mudou em ro_a: $_sa_pre -> $_sa_post"
    return 1
  fi
  if [ "$_sb_pre" != "$_sb_post" ]; then
    _fail "ro_mutated_b" "sha256 mudou em ro_b: $_sb_pre -> $_sb_post"
    return 1
  fi
  return 0
}

# ----------------------------------------------------------------------
# 4.2.1.f: tie-break determinista no mode de por_modelo_sugerido —
# quando 2 chaves empatam no maior valor, vence a MENOR alfabetica
# (ordem do enum: haiku < manter-atual < opus < sonnet).
# ----------------------------------------------------------------------
scenario_4_2_1_tie_break_alfabetico() {
  _skip_if_no_jq || return 2
  mktemp_test || return 2
  _s="$TMPDIR_TEST/tie.json"
  # haiku=2, sonnet=2 — empate; tie-break -> haiku.
  _write_state_full "$_s" "tie-feat" 2 2 0 0 4 0
  capture sh "$REPORT" "$_s"
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "tie_exit" "esperado 0, obtido: $_CAPTURED_EXIT"
    return 1
  fi
  case "$_CAPTURED_STDOUT" in
    *"| tie-feat | 4 | 4 | 0 | haiku |"*) ;;
    *)
      _fail "tie_break" \
        "tie-break alfabetico nao escolheu 'haiku': $_CAPTURED_STDOUT"
      return 1
      ;;
  esac
  return 0
}

run_all_scenarios
