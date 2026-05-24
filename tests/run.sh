#!/bin/sh
# run.sh — entry point da suite de testes para scripts shell do repositorio.
#
# Fluxo:
#   1. Parse de flags e argumento posicional (PATTERN).
#   2. Descoberta de test_*.sh e dos scripts sob teste.
#   3. Despacho por modo: run (default), --list ou --check-coverage.
#   4. No modo run: executa cada test, parseia TAP output, agrega sumario.
#
# Convencao de cobertura (FR-009): cada script tem um test_<nome>.sh
# correspondente. Mapeamento por origem do script:
#   global/skills/<skill>/scripts/<n>.sh  ->  tests/test_<n>.sh
#   cli/lib/<n>.sh                        ->  tests/cstk/test_<n>.sh
#
# Test files internos (sem script 1:1) sao excluidos do check de orfaos:
#   test_smoke.sh, test_harness.sh           — auto-tests do harness/runner
#   test_cstk-main.sh                        — cobre cli/cstk (binary, nao lib)
#   test_bootstrap.sh                        — cobre cli/install.sh (nao lib)
#   test_build-release.sh                    — cobre scripts/build-release.sh
#   test_hooks-integration.sh                — integration test (nao 1:1)
#   test_quickstart-e2e.sh                   — e2e quickstart (composicao das libs)
#
# Alem desses, ha cobertura real sob nome NAO-1:1 (tests granulares por aspecto
# de uma skill/script): tests model-selector + report (cobrem classify.sh/
# report.sh), e tests de aspecto (runtime-log-redaction->_log.sh,
# state-dir-parametrization->_state-dir.sh, secrets-filter-backup->secrets-filter.sh,
# skills-cache-protocol->state-cache.sh, update-extra-kinds->update.sh). Esses
# sao isentados nos DOIS lados (_is_internal_test p/ tests, _is_covered_by_named_test
# p/ scripts), sempre com guarda de existencia do cobridor (anti-ponto-cego).
#
# POSIX sh puro. Sem Bash-isms. Deps: find, grep, sort, basename, dirname,
# mktemp, date, sh, printf.

set -eu

# ==== 1. Parse de argumentos ====

MODE="run"
PATTERN=""
VERBOSE=0

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      cat <<'USAGE'
Uso: tests/run.sh [OPCOES] [PATTERN]

Entry point da suite de testes para scripts shell do repositorio.

OPCOES:
  -h, --help          Imprime esta mensagem e sai 0.
  -v, --verbose       Imprime output verboso (reservado; no-op hoje).
  --list              Lista scenarios disponiveis e sai 0 (sem executar).
  --check-coverage    Detecta scripts sem teste e testes sem script;
                      exit 1 se houver qualquer orfao, 0 caso contrario.

ARGUMENTOS:
  PATTERN             Substring aplicada sobre o caminho dos test cases.
                      Ex: 'metrics' executa apenas tests/test_metrics.sh.
                      Se nao casa nenhum test, exit 2.

EXIT CODES:
  0  Todos os scenarios PASSARAM (orfaos em modo normal sao warning, nao falha).
  1  Pelo menos um FAIL ou ERROR (ou --check-coverage detectou orfao).
  2  Invocacao invalida ou PATTERN sem match.
USAGE
      exit 0
      ;;
    -v|--verbose) VERBOSE=1 ;;
    --list) MODE="list" ;;
    --check-coverage) MODE="check-coverage" ;;
    -*)
      printf 'run.sh: flag desconhecida: %s\n' "$arg" >&2
      printf 'Tente --help para ver opcoes disponiveis.\n' >&2
      exit 2
      ;;
    *)
      if [ -z "$PATTERN" ]; then
        PATTERN="$arg"
      else
        printf 'run.sh: mais de um PATTERN nao suportado: %s\n' "$arg" >&2
        exit 2
      fi
      ;;
  esac
done

# ==== 2. Paths ====

TESTS_ROOT=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$TESTS_ROOT/.." && pwd)
export TESTS_ROOT REPO_ROOT

# Test files internos — nao mapeiam a scripts de skills, sao excluidos do
# check de orfaos. (Deliberadamente como case-pattern em vez de lista para
# evitar surpresa de IFS: este flag e consultado dentro de loops que
# manipulam IFS='\n', e word-split por espaco falharia.)

# ==== 3. Helpers: descoberta ====

# _find_test_files [PATTERN]
# Imprime caminho absoluto de cada test_*.sh, filtrado por PATTERN (substring
# sobre o path) se fornecido. Cobre tests/ (toplevel) e tests/cstk/ (FASE 9.3).
# Ordena para determinismo.
_find_test_files() {
  _filter="${1:-}"
  _all=$(
    {
      find "$TESTS_ROOT" -maxdepth 1 -name 'test_*.sh' -type f 2>/dev/null
      find "$TESTS_ROOT/cstk" -maxdepth 1 -name 'test_*.sh' -type f 2>/dev/null
    } | sort
  )
  if [ -z "$_filter" ]; then
    printf '%s\n' "$_all"
    return 0
  fi
  printf '%s\n' "$_all" | grep -F "$_filter" || :
}

# _find_scripts
# Imprime caminho absoluto de cada .sh sob teste:
#   - global/skills/<any>/scripts/*.sh  (existente desde a v1)
#   - cli/lib/*.sh                       (FASE 9.3 — extensao da CLI cstk)
_find_scripts() {
  {
    find "$REPO_ROOT/global/skills" -type f -path '*/scripts/*.sh' 2>/dev/null
    find "$REPO_ROOT/cli/lib" -maxdepth 1 -type f -name '*.sh' 2>/dev/null
  } | sort
}

# _expected_test_for_script SCRIPT_PATH
# Imprime o path absoluto do test esperado para o script, conforme convencao.
_expected_test_for_script() {
  _ets_script=$1
  _ets_base=$(_script_basename "$_ets_script")
  case "$_ets_script" in
    */global/skills/*/scripts/*) printf '%s\n' "$TESTS_ROOT/test_$_ets_base.sh" ;;
    */cli/lib/*)                 printf '%s\n' "$TESTS_ROOT/cstk/test_$_ets_base.sh" ;;
    *)                           printf '\n' ;;  # categoria nao esperada
  esac
}

# _script_basename PATH -> basename sem .sh
_script_basename() {
  _b=$(basename "$1")
  printf '%s' "${_b%.sh}"
}

# _test_basename PATH -> test_foo.sh -> foo
_test_basename() {
  _b=$(basename "$1")
  _b="${_b#test_}"
  printf '%s' "${_b%.sh}"
}

# _is_internal_test PATH -> exit 0 se e interno, 1 caso contrario.
# "Interno" = nao mapeia 1:1 para um script sob a convencao de FASE 9.3
# (cli/lib/ ou global/skills/<X>/scripts/). Esses tests rodam normalmente,
# apenas sao excluidos do orphan-test check.
_is_internal_test() {
  _name=$(basename "$1")
  case "$_name" in
    test_smoke.sh|test_harness.sh) return 0 ;;
    test_cstk-main.sh|test_bootstrap.sh|test_build-release.sh|test_hooks-integration.sh|test_quickstart-e2e.sh)
      return 0 ;;
    test_install-extra-kinds.sh)
      # Cobre interacao install.sh + manifest.sh + doctor.sh para os kinds
      # commands/agents (nao mapeia 1:1 para um unico script sob a convencao).
      return 0 ;;
    test_command-spawn-model-routing.sh)
      # Smoke textual sobre os 4 commands de spawn/resume (model-routing
      # por onda, FASE 3 de model-routing-por-onda). Assert no .md, nao em
      # um unico script — existence-guarded ao command portador da instrucao
      # wave-select. Se a fonte sumir, volta a ser orfao real.
      [ -f "$REPO_ROOT/global/commands/feature-00c.md" ] && return 0
      return 1 ;;
    test_e2e_model_routing.sh)
      # Cobre fluxo end-to-end model-routing.sh + model-routing-report.sh +
      # state-rw.sh + state-decisions.sh + state-ondas.sh (composicao de
      # 5 scripts da agente-00c-runtime — nao mapeia 1:1 para um unico
      # script sob a convencao de FASE 9.3). Equivalente ao
      # test_quickstart-e2e.sh para o pipeline do agente-00c.
      return 0 ;;
    # ---- Cobertura real sob nome NAO-1:1 (existence-guarded) ----
    # Estes tests exercitam um script real, mas com nome descritivo que nao
    # casa test_<base>.sh. Cada ramo so isenta se o script cobridor EXISTE —
    # se ele sumir, o test volta a ser orfao real (anti-ponto-cego). Espelha
    # _is_covered_by_named_test, do lado dos tests.
    test_model_selector_*.sh)
      # tests granulares da skill model-selector (classify.sh + report.sh)
      [ -f "$REPO_ROOT/global/skills/model-selector/scripts/classify.sh" ] && return 0
      return 1 ;;
    test_report_jq_confinement.sh|test_report_performance.sh|test_report_read_only.sh|test_report_without_jq.sh)
      # cobrem model-selector/scripts/report.sh (geracao do relatorio)
      [ -f "$REPO_ROOT/global/skills/model-selector/scripts/report.sh" ] && return 0
      return 1 ;;
    test_update-extra-kinds.sh)
      # aspecto extra de cli/lib/update.sh (primario: tests/cstk/test_update.sh)
      [ -f "$REPO_ROOT/cli/lib/update.sh" ] && return 0
      return 1 ;;
    test_runtime-log-redaction.sh)
      # cobre agente-00c-runtime/scripts/_log.sh (redacao de log)
      [ -f "$REPO_ROOT/global/skills/agente-00c-runtime/scripts/_log.sh" ] && return 0
      return 1 ;;
    test_secrets-filter-backup.sh)
      # aspecto backup de secrets-filter.sh (primario: tests/test_secrets-filter.sh)
      [ -f "$REPO_ROOT/global/skills/agente-00c-runtime/scripts/secrets-filter.sh" ] && return 0
      return 1 ;;
    test_skills-cache-protocol.sh)
      # cobre state-cache.sh (protocolo de cache; primario: tests/test_state-cache.sh)
      [ -f "$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-cache.sh" ] && return 0
      return 1 ;;
    test_state-dir-parametrization.sh)
      # cobre agente-00c-runtime/scripts/_state-dir.sh (parametrizacao do state dir)
      [ -f "$REPO_ROOT/global/skills/agente-00c-runtime/scripts/_state-dir.sh" ] && return 0
      return 1 ;;
    *) return 1 ;;
  esac
}

# ==== 4. Modo: --list ====

mode_list() {
  _tests=$(_find_test_files "$PATTERN")
  if [ -z "$_tests" ]; then
    if [ -n "$PATTERN" ]; then
      printf 'run.sh: nenhum test case casa o padrao: %s\n' "$PATTERN" >&2
      return 2
    fi
    return 0
  fi

  # IFS=newline para iterar arquivos.
  _OLD_IFS="$IFS"
  IFS='
'
  for _test in $_tests; do
    _test_name=$(basename "$_test")
    # Grep scenarios definidos no arquivo. Mesmo padrao do _list_scenarios
    # do harness: procura definicoes 'scenario_NAME() {' ou 'scenario_NAME () {'.
    grep -E '^scenario_[A-Za-z0-9_]+ *\(\)' "$_test" \
      | sed 's/ *(.*//' \
      | sort -u \
      | while IFS= read -r _scen; do
          printf '%s :: %s\n' "$_test_name" "$_scen"
        done
  done
  IFS="$_OLD_IFS"
  return 0
}

# ==== 5. Modo: --check-coverage (e computacao de orfaos no modo run) ====

# _is_covered_by_named_test SCRIPT_PATH -> exit 0 se o script TEM cobertura,
# porem sob um teste cujo nome NAO segue a convencao 1:1 test_<base>.sh. Espelha
# _is_internal_test, do lado dos SCRIPTS: sem isto, scripts cobertos por tests
# de nome divergente viram falsos-positivos no orphan-check.
#
# Anti-ponto-cego: cada entrada exige que o teste cobridor EXISTA em disco. Se
# ele for removido/renomeado, o script volta a ser flagado como orfao — a
# isencao nunca mascara lacuna de cobertura real.
_is_covered_by_named_test() {
  _icbnt_base=$(_script_basename "$1")
  case "$_icbnt_base" in
    # _log.sh (helper de log/redacao, sourced) -> redacao testada aqui.
    _log)       _icbnt_cover="$TESTS_ROOT/test_runtime-log-redaction.sh" ;;
    # _state-dir.sh (resolucao de state dir, sourced) -> parametrizacao testada aqui.
    _state-dir) _icbnt_cover="$TESTS_ROOT/test_state-dir-parametrization.sh" ;;
    # classify.sh (core do model-selector) -> tests/cstk/test_model_selector_*.sh
    # (faixas rasa/media/profunda, input vazio, falsos-positivos, etc.).
    classify)   _icbnt_cover="$TESTS_ROOT/cstk/test_model_selector_faixa_rasa.sh" ;;
    *) return 1 ;;
  esac
  [ -f "$_icbnt_cover" ] && return 0
  return 1
}

# _compute_orphans
# Imprime duas listas em stdout, separadas por linha '---':
#   scripts sem teste correspondente
#   ---
#   tests sem script correspondente (ignora internos)
# Sempre emite duas secoes, possivelmente vazias.
_compute_orphans() {
  _orphan_scripts=""
  _orphan_tests=""

  _scripts=$(_find_scripts)
  _tests=$(_find_test_files "")

  _OLD_IFS="$IFS"
  IFS='
'
  # Scripts sem teste — usa _expected_test_for_script para roteamento por
  # categoria (global/skills/.../scripts/ -> tests/, cli/lib/ -> tests/cstk/).
  for _script in $_scripts; do
    [ -z "$_script" ] && continue
    # Isencao: script coberto por teste de nome nao-1:1 (verifica existencia).
    _is_covered_by_named_test "$_script" && continue
    _expected=$(_expected_test_for_script "$_script")
    if [ -z "$_expected" ] || [ ! -f "$_expected" ]; then
      _orphan_scripts="$_orphan_scripts
$_script"
    fi
  done

  # Tests sem script — basename do test deve casar com basename de algum
  # script discoverable (em /scripts/ OU em /cli/lib/).
  for _test in $_tests; do
    [ -z "$_test" ] && continue
    if _is_internal_test "$_test"; then
      continue
    fi
    _tb=$(_test_basename "$_test")
    _match=$(printf '%s\n' "$_scripts" | awk -v name="$_tb" '
      {
        if (index($0, "/scripts/" name ".sh") > 0) { print; exit }
        if (index($0, "/cli/lib/" name ".sh") > 0) { print; exit }
      }
    ')
    if [ -z "$_match" ]; then
      _orphan_tests="$_orphan_tests
$_test"
    fi
  done
  IFS="$_OLD_IFS"

  # Emite duas secoes separadas por '---'. Linhas vazias removidas.
  printf '%s\n' "$_orphan_scripts" | grep -v '^$' || :
  printf '%s\n' "---"
  printf '%s\n' "$_orphan_tests" | grep -v '^$' || :
}

mode_check_coverage() {
  _orph=$(_compute_orphans)
  _o_scripts=$(printf '%s\n' "$_orph" | awk '/^---$/{exit} {print}')
  _o_tests=$(printf '%s\n' "$_orph" | awk 'f{print} /^---$/{f=1}')

  _count_scripts=0
  if [ -n "$_o_scripts" ]; then
    _count_scripts=$(printf '%s\n' "$_o_scripts" | wc -l | tr -d ' ')
  fi
  _count_tests=0
  if [ -n "$_o_tests" ]; then
    _count_tests=$(printf '%s\n' "$_o_tests" | wc -l | tr -d ' ')
  fi

  printf 'Cobertura de testes para scripts em global/skills/**/scripts/ + cli/lib/\n\n'

  if [ "$_count_scripts" -gt 0 ]; then
    printf 'Scripts sem teste correspondente (%d):\n' "$_count_scripts"
    printf '%s\n' "$_o_scripts" | sed 's|^|  - |'
    printf '\n'
  fi

  if [ "$_count_tests" -gt 0 ]; then
    printf 'Tests sem script correspondente (%d) — possivel script removido:\n' "$_count_tests"
    printf '%s\n' "$_o_tests" | sed 's|^|  - |'
    printf '\n'
  fi

  if [ "$_count_scripts" -eq 0 ] && [ "$_count_tests" -eq 0 ]; then
    printf 'Cobertura completa: zero orfaos.\n'
    return 0
  fi
  return 1
}

# ==== 6. Modo: run (default) ====

mode_run() {
  _tests=$(_find_test_files "$PATTERN")
  if [ -z "$_tests" ]; then
    if [ -n "$PATTERN" ]; then
      printf 'run.sh: nenhum test case casa o padrao: %s\n' "$PATTERN" >&2
      return 2
    fi
    printf 'run.sh: nenhum test_*.sh encontrado em %s\n' "$TESTS_ROOT" >&2
    return 0
  fi

  _TOTAL_PASS=0
  _TOTAL_FAIL=0
  _TOTAL_ERROR=0
  _START_TIME=$(date +%s)

  # Tmpfile para capturar saida de cada test file (precisamos ver E parsear).
  _TMPOUT=$(mktemp 2>/dev/null) || {
    printf 'run.sh: mktemp indisponivel\n' >&2
    return 2
  }
  # Limpeza por trap cobre ctrl+c / term.
  trap 'rm -f "$_TMPOUT"' EXIT INT TERM

  _OLD_IFS="$IFS"
  IFS='
'
  for _test in $_tests; do
    [ -z "$_test" ] && continue
    _test_name=$(basename "$_test")
    printf '# %s\n' "$_test_name"

    # Executa test em subshell, capturando stdout+stderr num tmpfile.
    # Nao abortamos se test falha (por design — _e_ o que estamos medindo).
    sh "$_test" > "$_TMPOUT" 2>&1 || :
    # Reemite o output integral para o usuario (preserva TAP + diagnostico).
    cat "$_TMPOUT"

    # Parseia contagens. Padroes do harness:
    #   ok N -
    #   not ok N -              (FAIL)
    #   not ok N - ... # ERROR  (ERROR, tem precedencia sobre FAIL)
    # grep -c retorna >=1 em no-match; usamos '|| VAR=0' para evitar bug.
    _pass_this=$(grep -cE '^ok [0-9]+ ' "$_TMPOUT") || _pass_this=0
    _error_this=$(grep -cE '^not ok [0-9]+ .*# ERROR' "$_TMPOUT") || _error_this=0
    _all_fail_this=$(grep -cE '^not ok [0-9]+ ' "$_TMPOUT") || _all_fail_this=0
    _fail_this=$((_all_fail_this - _error_this))

    _TOTAL_PASS=$((_TOTAL_PASS + _pass_this))
    _TOTAL_FAIL=$((_TOTAL_FAIL + _fail_this))
    _TOTAL_ERROR=$((_TOTAL_ERROR + _error_this))
  done
  IFS="$_OLD_IFS"

  # Orfaos — reportados como warning, NAO afetam exit code neste modo.
  _orph=$(_compute_orphans)
  _o_scripts=$(printf '%s\n' "$_orph" | awk '/^---$/{exit} {print}' | grep -v '^$' || :)
  _orphan_count=0
  if [ -n "$_o_scripts" ]; then
    _orphan_count=$(printf '%s\n' "$_o_scripts" | wc -l | tr -d ' ')
  fi

  _END_TIME=$(date +%s)
  _ELAPSED=$((_END_TIME - _START_TIME))

  # Sumario final — formato estavel para parse posterior e eyeball humano.
  printf '\n'
  printf '# PASS: %d  FAIL: %d  ERROR: %d  ORPHANS: %d  TIME: %ds\n' \
    "$_TOTAL_PASS" "$_TOTAL_FAIL" "$_TOTAL_ERROR" "$_orphan_count" "$_ELAPSED"

  # Warning detalhado para orfaos (nao fatal).
  if [ "$_orphan_count" -gt 0 ]; then
    printf '\n# WARN: %d script(s) sem teste correspondente:\n' "$_orphan_count"
    printf '%s\n' "$_o_scripts" | sed 's|^|#   - |'
    printf '# (rode com --check-coverage para detalhes e exit code 1)\n'
  fi

  # Exit 0 sse FAIL=0 AND ERROR=0 (orfaos nao bloqueiam no modo normal — FR-009).
  if [ "$_TOTAL_FAIL" -eq 0 ] && [ "$_TOTAL_ERROR" -eq 0 ]; then
    return 0
  fi
  return 1
}

# ==== 7. Dispatch ====

case "$MODE" in
  list) mode_list ;;
  check-coverage) mode_check_coverage ;;
  run) mode_run ;;
esac
