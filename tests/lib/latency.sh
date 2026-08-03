# latency.sh — helper sourceable de gate de latencia por mediana (N=20 +
# warm-up), usado pelos scenarios de latencia dos 3 hooks portados na
# feature hooks-db-parity (FASE 6, FR-005/SC-003).
#
# Ref: docs/specs/hooks-db-parity/research.md Decision 3
#      docs/specs/hooks-db-parity/tasks.md 6.1.1-6.1.5
#
# Sourced por tests/test_pretooluse-bash-guard.sh,
# tests/test_posttooluse-tool-call-tick.sh e
# tests/test_posttooluse-agent-usage.sh, APOS tests/lib/harness.sh (usa
# `_error` do harness). Nao define scenario_* — _list_scenarios greppa
# apenas o arquivo de teste ($0), entao este lib fica invisivel ao
# descobridor de scenarios.
#
# Design: a medicao de tempo usa `perl -MTime::HiRes=time` (POSIX puro nao
# tem relogio de alta resolucao portavel entre `date` GNU/BSD — armadilha
# conhecida do repositorio de locale/formato). O comando medido em si
# roda via array de argv ja pre-splitado pelo caller (nunca concatenado
# em string), evitando quoting aninhado dentro do `perl -e`.

# _require_perl -> ERROR/skip (padrao _require_sqlite3) se `perl` ausente.
# O gate de latencia mede desempenho, nao disponibilidade de ferramenta de
# medicao (research Decision 3) — ausencia de perl NUNCA vira FAIL.
_require_perl() {
  command -v perl >/dev/null 2>&1 && return 0
  _error "no_perl" "perl indisponivel neste ambiente de teste (gate de latencia, SC-003)"
  return 1
}

# _epoch_ms -> timestamp corrente em milissegundos (inteiro), via
# Time::HiRes. Portavel macOS/Linux (research Decision 3 rejeitou `time`
# builtin por variacao de resolucao/locale entre shells).
_epoch_ms() {
  perl -MTime::HiRes=time -e 'printf "%.0f\n", time()*1000'
}

# _median_of_file FILE -> mediana inteira (ms) de uma coluna de inteiros,
# um por linha. N par usa media dos dois centrais (arredondada para baixo).
_median_of_file() {
  sort -n "$1" | awk '
    { a[NR] = $1 }
    END {
      n = NR
      if (n == 0) { print ""; exit }
      if (n % 2 == 1) { print a[(n + 1) / 2] }
      else { print int((a[n / 2] + a[n / 2 + 1]) / 2) }
    }
  '
}

# _measure_median_ms WARMUP N CMD... -> executa CMD (argv ja pre-splitado)
# WARMUP+N vezes, descarta as WARMUP primeiras medicoes, imprime no stdout
# a mediana em ms das N restantes. stdout/stderr do CMD medido sao
# descartados (o gate mede latencia; comportamento e coberto pelos demais
# scenarios do arquivo). Retorna 2 (ERROR-like) se nao conseguir criar
# tmpfile de medicoes.
_measure_median_ms() {
  _mm_warm=$1
  shift
  _mm_n=$1
  shift
  _mm_tmp=$(mktemp 2>/dev/null) || return 2
  _mm_total=$((_mm_warm + _mm_n))
  _mm_i=1
  while [ "$_mm_i" -le "$_mm_total" ]; do
    _mm_t0=$(_epoch_ms)
    "$@" >/dev/null 2>&1
    _mm_t1=$(_epoch_ms)
    if [ "$_mm_i" -gt "$_mm_warm" ]; then
      printf '%s\n' "$((_mm_t1 - _mm_t0))" >>"$_mm_tmp"
    fi
    _mm_i=$((_mm_i + 1))
  done
  _median_of_file "$_mm_tmp"
  rm -f "$_mm_tmp"
}
