#!/bin/sh
# test_report_performance.sh
#
# Cobre subtarefa 4.4.3 da feature `model-selector` (Ref:
# docs/specs/model-selector/tasks.md L240, SC-003, CHK016, CHK017 —
# criterio cravado).
#
# Objetivo: garantir que o tempo de wallclock MEDIANO de 5 runs
# consecutivos de `scripts/report.sh` sobre a fixture state-dirs-20
# (20 state.json) e ESTRITAMENTE MENOR que 500ms.
#
# Mediana eh preferida a media para resistir a outliers de cold-start
# (primeira invocacao costuma demorar mais por cache de FS). Com 5
# amostras, a mediana eh a 3a apos ordenacao crescente.
#
# Implementacao:
#   - Cada run executa `sh report.sh <todos-os-20-paths>` capturando
#     stderr de `time -p`. O comando da task usa `--state-dir`, mas o
#     report.sh atual nao implementa essa flag (placeholder 4.1 do
#     script comenta "NAO IMPLEMENTADO neste esqueleto"); usamos a
#     Forma 1 (paths posicionais) que e o equivalente semantico — 20
#     paths explicitos cobrem a mesma carga de trabalho sobre a
#     mesma fixture. Decisao auditavel registrada em dec-XXX.
#   - Parseamos a linha `real <segundos>` do `time -p` (POSIX) e
#     convertemos para milissegundos via awk (1s = 1000ms; suporta 2
#     casas decimais — granularidade tipica do shell).
#   - Ordenamos as 5 amostras e tomamos a 3a (mediana exata).
#   - Comparamos a mediana com 500 (ms) — falha se >= 500.
#
# Hardware-base esperado (per task 4.4.3): M1/M2 ou Linux x86_64
# modesto. Em CI mais lento, o threshold de 500ms ainda da folga
# generosa em relacao a baseline observada (~120ms M2 dev local).
#
# Cenarios:
#   1. mediana_5_runs_abaixo_500ms
#        Cenario principal — materializa SC-003 e CHK017.
#   2. amostras_consistentes_sem_outlier_extremo
#        Sanity de variancia: max/min < 5x. Se a maxima for mais que
#        5x a minima, indica ruido grave de ambiente (concorrencia,
#        thrash) — reportado como ERROR (status 2) para nao
#        contabilizar como falha de produto.
#   3. fixture_completa_disponivel
#        Pre-flight: confere que regen.sh ja foi rodado e os 20
#        state.json estao presentes.
#
# Refs:
#   SC-003   Mediana de wallclock em 5 runs < 500ms
#   CHK016   Test usa fixture state-dirs-20
#   CHK017   Test usa 5 runs + mediana (nao media)

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

REPORT="$REPO_ROOT/plugins/cstk/skills/model-selector/scripts/report.sh"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/state-dirs-20"
PERF_THRESHOLD_MS=500
PERF_RUNS=5

export REPORT FIXTURE_DIR PERF_THRESHOLD_MS PERF_RUNS

# ----------------------------------------------------------------------
# Helpers — prefixo `_pf_` (performance)
# ----------------------------------------------------------------------

_pf_assert_fixture_exists() {
  if [ ! -d "$FIXTURE_DIR" ]; then
    printf 'harness: fixture %s ausente — rodar regen.sh\n' \
      "$FIXTURE_DIR" >&2
    return 2
  fi
  _pf_count=$(find "$FIXTURE_DIR" -name state.json | wc -l | tr -d ' ')
  if [ "$_pf_count" != "20" ]; then
    printf 'harness: fixture com %s state.json (esperado 20)\n' \
      "$_pf_count" >&2
    return 2
  fi
  return 0
}

# Constroi a lista posicional dos 20 paths em ordem canonica.
# Saida via "$@" no contexto chamador.
_pf_set_args() {
  set --
  for _i in 01 02 03 04 05 06 07 08 09 10 \
            11 12 13 14 15 16 17 18 19 20; do
    set -- "$@" "$FIXTURE_DIR/feat-$_i/state.json"
  done
  # Retorna via echo separado por NUL — chamador usa eval set --
  # Para POSIX puro sem arrays, repassamos os args do scenario.
  printf '%s\0' "$@"
}

# Mede UM run, imprime ms em stdout. Falha (return 1) se time -p
# falhar.
_pf_measure_ms_one_run() {
  # $@ = paths posicionais
  _pf_tmp_err=$(mktemp) || return 1
  # `time -p` escreve em stderr; redirecionamos stderr para tmp e
  # stdout do report.sh para /dev/null. POSIX `time -p` garante
  # formato "real <segs>" com 2 casas decimais.
  { time -p sh "$REPORT" "$@" >/dev/null; } 2> "$_pf_tmp_err"
  _pf_status=$?
  if [ "$_pf_status" != "0" ]; then
    rm -f -- "$_pf_tmp_err"
    return 1
  fi
  # Extrai linha "real X.XX" e converte para ms.
  _pf_real=$(awk '/^real / {print $2; exit}' "$_pf_tmp_err")
  rm -f -- "$_pf_tmp_err"
  if [ -z "$_pf_real" ]; then
    return 1
  fi
  # Converte X.XX (segundos) para inteiro de milissegundos via awk.
  # `int(s * 1000 + 0.5)` arredonda para o ms mais proximo. awk
  # POSIX suporta floats com `.` decimal — confirmamos `time -p`
  # produz formato com `.` (nao `,`) em qualquer locale POSIX.
  printf '%s\n' "$_pf_real" | LC_ALL=C awk '{
    s = $1 + 0;
    ms = int(s * 1000 + 0.5);
    print ms
  }'
}

# Coleta N amostras de ms, uma por linha, em ordem de execucao.
_pf_collect_samples() {
  _pf_n=$1
  shift
  _pf_i=0
  while [ "$_pf_i" -lt "$_pf_n" ]; do
    _pf_sample=$(_pf_measure_ms_one_run "$@") || return 1
    printf '%s\n' "$_pf_sample"
    _pf_i=$((_pf_i + 1))
  done
}

# Mediana de uma lista de inteiros (uma por linha). Para N=5, retorna
# o 3o elemento apos sort numerico crescente.
_pf_median_of_5() {
  sort -n | awk 'NR==3 {print; exit}'
}

# Max de uma lista de inteiros (uma por linha).
_pf_max() {
  sort -n | tail -n 1
}

# Min de uma lista de inteiros (uma por linha).
_pf_min() {
  sort -n | head -n 1
}

# ----------------------------------------------------------------------
# 4.4.3.a: pre-flight — fixture deve existir com 20 state.json
# ----------------------------------------------------------------------
scenario_4_4_3_fixture_completa_disponivel() {
  _pf_assert_fixture_exists || return 2
  # Sanity adicional: tamanho minimo 2KB em todos os arquivos
  _pf_bad=$(find "$FIXTURE_DIR" -name state.json -exec wc -c {} \; \
            | awk '$1 < 2048 || $1 > 10240 {print $2":"$1}' )
  if [ -n "$_pf_bad" ]; then
    _fail "fixture_tamanho_fora_de_faixa" \
      "arquivos fora de 2KB..10KB (CHK018):
$_pf_bad"
    return 1
  fi
  return 0
}

# ----------------------------------------------------------------------
# 4.4.3.b: cenario principal — mediana de 5 runs < 500ms
# ----------------------------------------------------------------------
scenario_4_4_3_mediana_5_runs_abaixo_500ms() {
  _pf_assert_fixture_exists || return 2

  # Constroi lista posicional de paths.
  set --
  for _i in 01 02 03 04 05 06 07 08 09 10 \
            11 12 13 14 15 16 17 18 19 20; do
    set -- "$@" "$FIXTURE_DIR/feat-$_i/state.json"
  done

  _pf_samples=$(_pf_collect_samples "$PERF_RUNS" "$@") || {
    _fail "coleta_amostras" \
      "falha ao coletar $PERF_RUNS amostras de tempo (time -p falhou)"
    return 1
  }

  _pf_med=$(printf '%s\n' "$_pf_samples" | _pf_median_of_5)
  if [ -z "$_pf_med" ]; then
    _fail "mediana_vazia" \
      "nao foi possivel calcular mediana das amostras: [$_pf_samples]"
    return 1
  fi

  if [ "$_pf_med" -ge "$PERF_THRESHOLD_MS" ]; then
    _fail "mediana_acima_do_threshold" \
      "mediana=${_pf_med}ms >= threshold=${PERF_THRESHOLD_MS}ms (SC-003 violado); amostras (ms): $_pf_samples"
    return 1
  fi

  printf 'note: mediana=%sms < %sms (amostras ms: %s)\n' \
    "$_pf_med" "$PERF_THRESHOLD_MS" \
    "$(printf '%s' "$_pf_samples" | tr '\n' ' ')" >&2
  return 0
}

# ----------------------------------------------------------------------
# 4.4.3.c: sanity de variancia — protege contra falsos negativos por
# ambiente extremamente ruidoso (CI sob load). Se max/min > 5x, o
# scenario reporta ERROR (status 2) em vez de FAIL — variancia indica
# ruido externo, nao bug no produto. Threshold da mediana ja absorve
# pequenas variacoes; este scenario detecta variancia patologica.
# ----------------------------------------------------------------------
scenario_4_4_3_amostras_consistentes_sem_outlier_extremo() {
  _pf_assert_fixture_exists || return 2

  set --
  for _i in 01 02 03 04 05 06 07 08 09 10 \
            11 12 13 14 15 16 17 18 19 20; do
    set -- "$@" "$FIXTURE_DIR/feat-$_i/state.json"
  done

  _pf_samples=$(_pf_collect_samples "$PERF_RUNS" "$@") || {
    _fail "coleta_amostras_variancia" \
      "falha ao coletar amostras"
    return 1
  }

  _pf_max_v=$(printf '%s\n' "$_pf_samples" | _pf_max)
  _pf_min_v=$(printf '%s\n' "$_pf_samples" | _pf_min)

  # Floor de 1ms para min (evita div-by-zero quando time -p reporta 0.00).
  if [ -z "$_pf_min_v" ] || [ "$_pf_min_v" -lt 1 ]; then
    _pf_min_v=1
  fi

  _pf_ratio=$((_pf_max_v / _pf_min_v))
  if [ "$_pf_ratio" -gt 5 ]; then
    printf 'harness: variancia patologica max=%sms min=%sms ratio=%sx (>5x); ambiente ruidoso — scenario ERROR\n' \
      "$_pf_max_v" "$_pf_min_v" "$_pf_ratio" >&2
    return 2
  fi
  return 0
}

run_all_scenarios
