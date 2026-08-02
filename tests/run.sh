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
#   test_doc-counts.sh                       — invariante de doc (skills/scenarios)
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
SPEED="all"   # all | fast | slow (selecao por velocidade; --fast/--slow)

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
  --stats             Agrega contagem de scenarios por arquivo (desc) + total
                      e sai 0. Respeita PATTERN e --fast/--slow.
  --check-coverage    Detecta scripts sem teste e testes sem script;
                      exit 1 se houver qualquer orfao, 0 caso contrario.
  --fast              Seleciona apenas os tests rapidos (exclui a allowlist
                      lenta: integration/e2e/binario). Compoe com PATTERN.
  --slow              Seleciona apenas os tests lentos (so a allowlist).
                      Mutuamente exclusivo com --fast (exit 2 se ambos).

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
    --stats) MODE="stats" ;;
    --check-coverage) MODE="check-coverage" ;;
    --fast)
      if [ "$SPEED" = "slow" ]; then
        printf 'run.sh: --fast e --slow sao mutuamente exclusivos.\n' >&2
        exit 2
      fi
      SPEED="fast" ;;
    --slow)
      if [ "$SPEED" = "fast" ]; then
        printf 'run.sh: --fast e --slow sao mutuamente exclusivos.\n' >&2
        exit 2
      fi
      SPEED="slow" ;;
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
    test_run-modes.sh)
      # Exercita o proprio runner (modos --fast/--slow/--stats) — nao mapeia
      # 1:1 para um script sob a convencao de FASE 9.3.
      return 0 ;;
    test_cstk-main.sh|test_bootstrap.sh|test_build-release.sh|test_hooks-integration.sh|test_quickstart-e2e.sh)
      return 0 ;;
    test_doc-counts.sh)
      # Guarda numeros derivados (skills/scenarios) na doc de entrada vs repo.
      # Teste de invariante do repositorio — nao mapeia 1:1 para um script.
      return 0 ;;
    test_doc-subcommands.sh)
      # Lint: refs `<helper>.sh <subcomando>` nos docs apontam p/ subcomando
      # real (case-label no dispatch). Invariante do repo — nao mapeia 1:1.
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
    test_command-spawn-mcp-lifecycle.sh)
      # Smoke textual sobre os 4 commands de spawn/resume (ciclo de vida do
      # servidor MCP: status/start/stop, FASE 6 task 6.2 de
      # state-mcp-server). Assert no .md, nao em um unico script —
      # existence-guarded ao command portador da instrucao `cstk mcp`. Se a
      # fonte sumir, volta a ser orfao real.
      [ -f "$REPO_ROOT/global/commands/feature-00c.md" ] && return 0
      return 1 ;;
    test_orchestrator-mcp-fallback.sh)
      # Hibrido textual+funcional (FASE 6 task 6.3 de state-mcp-server,
      # SC-004): confirma que os 2 agentes orquestradores nao dependem de
      # tools mcp__* (zero regressao por construcao) e que uma execucao
      # headless/cron completa via Bash puro mesmo com `cstk mcp start`
      # falhando por docker ausente. Composicao de multiplos scripts do
      # runtime (state-rw.sh + state-ondas.sh + state-decisions.sh +
      # cli/lib/mcp.sh) — nao mapeia 1:1 para um unico script sob a
      # convencao de FASE 9.3.
      [ -f "$REPO_ROOT/global/agents/agente-00c-feature-orchestrator.md" ] && return 0
      return 1 ;;
    test_orchestrator-spawn-model-apply.sh)
      # Smoke textual sobre os 2 orquestradores (model-routing por onda,
      # FASE 5 de model-routing-por-onda). Assert no .md (passo 8 da
      # §5.e.bis / secao model-routing), nao em um unico script —
      # existence-guarded ao orquestrador portador da instrucao de aplicar
      # model no spawn de clarify. Se a fonte sumir, volta a ser orfao real.
      [ -f "$REPO_ROOT/global/agents/agente-00c-feature-orchestrator.md" ] && return 0
      return 1 ;;
    test_orchestrator-turn-completion.sh)
      # Smoke textual sobre os 2 orquestradores (trava do "Contrato de
      # conclusao de turno" — anti-parada-cedo apos Skill retornar). Assert
      # no .md, nao em um unico script — existence-guarded ao orquestrador
      # portador do contrato. Se a fonte sumir, volta a ser orfao real.
      [ -f "$REPO_ROOT/global/agents/agente-00c-feature-orchestrator.md" ] && return 0
      return 1 ;;
    test_orchestrator-evidence-grounding.sh)
      # Smoke textual sobre os 2 orquestradores + 2 resume (regra "aterramento
      # de evidencia em escalada de seguranca" — anti-confabulacao). Assert no
      # .md/.command, nao em um unico script — existence-guarded. Se a regra
      # sumir do prompt, o bug (escalar ameaca fabricada) volta silenciosamente.
      [ -f "$REPO_ROOT/global/agents/agente-00c-feature-orchestrator.md" ] && return 0
      return 1 ;;
    test_data-veracity-verifier.sh)
      # Smoke textual sobre o agente data-veracity-verifier + a fiacao nos 2
      # orquestradores (Principio VI — Veracidade de Dados / Zero Fabricacao).
      # Assert no .md do agente, nao em um unico script — existence-guarded. Se
      # o contrato sumir, o "double check" anti-fabricacao some silenciosamente.
      [ -f "$REPO_ROOT/global/agents/data-veracity-verifier.md" ] && return 0
      return 1 ;;
    test_converge-orchestrator-gate.sh)
      # Smoke textual sobre os 2 orquestradores (gate incondicional
      # `convergence` na fronteira execute-task -> review-task, feature
      # skill-converge FASE 4 — US5/FR-015/FR-019). Assert no .md, nao em um
      # unico script — existence-guarded ao orquestrador portador do gate. Se
      # a secao sumir, a regressao (converge nunca invocada antes de
      # review-task) volta silenciosamente.
      [ -f "$REPO_ROOT/global/agents/agente-00c-feature-orchestrator.md" ] && return 0
      return 1 ;;
    test_e2e_model_routing.sh)
      # Cobre fluxo end-to-end model-routing.sh + model-routing-report.sh +
      # state-rw.sh + state-decisions.sh + state-ondas.sh (composicao de
      # 5 scripts da agente-00c-runtime — nao mapeia 1:1 para um unico
      # script sob a convencao de FASE 9.3). Equivalente ao
      # test_quickstart-e2e.sh para o pipeline do agente-00c.
      return 0 ;;
    test_state-db-concurrency.sh)
      # Testes de atomicidade/concorrencia do backend SQLite (feature
      # state-db-foundation, FASE 3 task 3.7, SC-002) — exercita a
      # COMPOSICAO de state-decisions.sh + bloqueios.sh + state-ondas.sh
      # sobre o mesmo state.db (mutacoes concorrentes distintas, kill -9
      # em transacao aberta, leitura concorrente sob WAL). Nao mapeia 1:1
      # para um unico script sob a convencao de FASE 9.3.
      return 0 ;;
    test_config-roundtrip.sh)
      # SC-004 (feature state-backend-config, FASE 6, task 6.1.1): compara
      # EMPIRICAMENTE o backend resolvido pelo caminho do binario
      # (cli/lib/doctor.sh + cli/lib/config.sh) contra o arquivo criado pelo
      # caminho do runtime (global/skills/agente-00c-runtime/scripts/
      # state-rw.sh init) — composicao cross-cutting de 2+ scripts, nao
      # mapeia 1:1 para um unico script sob a convencao de FASE 9.3.
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
    test_pretooluse-bash-guard.sh)
      # cobre global/skills/agente-00c-runtime/hooks/pretooluse-bash-guard.sh
      # (US1, enforced-guards). _find_scripts so escaneia */scripts/*.sh e
      # cli/lib/*.sh por convencao (FASE 9.3) — hooks/ e um diretorio novo
      # (harness-invoked, nao skill/cli-invoked, ver plan.md §Project
      # Structure de enforced-guards) fora desse escopo, entao o mapeamento
      # 1:1 nao enxerga o script mesmo com nome de teste identico. Existence-
      # guarded: se o hook sumir, volta a ser orfao real.
      [ -f "$REPO_ROOT/global/skills/agente-00c-runtime/hooks/pretooluse-bash-guard.sh" ] && return 0
      return 1 ;;
    test_posttooluse-tool-call-tick.sh)
      # cobre global/skills/agente-00c-runtime/hooks/posttooluse-tool-call-tick.sh
      # (hook PostToolUse de metrica de tool calls por onda) — mesma razao
      # do test_pretooluse-bash-guard.sh acima: hooks/ esta fora do escaneio
      # por convencao. Existence-guarded.
      [ -f "$REPO_ROOT/global/skills/agente-00c-runtime/hooks/posttooluse-tool-call-tick.sh" ] && return 0
      return 1 ;;
    test_posttooluse-agent-usage.sh)
      # cobre global/skills/agente-00c-runtime/hooks/posttooluse-agent-usage.sh
      # (hook PostToolUse/matcher "Agent" de metrica de uso de tokens por
      # spawn de subagente — wave-token-metrics FASE 2) — mesma razao dos
      # dois casos acima: hooks/ esta fora do escaneio por convencao.
      # Existence-guarded.
      [ -f "$REPO_ROOT/global/skills/agente-00c-runtime/hooks/posttooluse-agent-usage.sh" ] && return 0
      return 1 ;;
    *) return 1 ;;
  esac
}

# _is_slow_test PATH -> exit 0 se o test e "lento", 1 caso contrario.
# "Lento" = tempo de parede medido > ~5s (corte limpo no perfil). Allowlist
# DERIVADA DE MEDICAO (nao de categoria): rodada `for f in tests/**/test_*.sh;
# do time sh "$f"; done` em 2026-05-24. Os 11 abaixo somam ~177s dos ~260s da
# suite — `--fast` os pula e roda em ~1/3 do tempo. Reavaliar se o perfil mudar
# (ver tests/README.md "Suite rapida vs completa"). Mesmo estilo de
# _is_internal_test; consumida por _select_tests p/ servir --fast/--slow.
_is_slow_test() {
  _slow_name=$(basename "$1")
  case "$_slow_name" in
    test_recall.sh|test_session.sh)              return 0 ;;  # ~82s, ~18s (sqlite/worktree)
    test_model-routing.sh|test_drift.sh)         return 0 ;;  # ~16s, ~13s (muitos scenarios)
    test_self-update.sh|test_00c-bootstrap.sh)   return 0 ;;  # ~11s, ~8s (binario/tarball)
    test_quickstart-e2e.sh|test_e2e_model_routing.sh) return 0 ;;  # ~9s, ~5s (e2e)
    test_update.sh|test_update-extra-kinds.sh)   return 0 ;;  # ~5s, ~6s (manifest/doctor)
    test_model_selector_corpus.sh)               return 0 ;;  # ~5s (corpus 45 entradas)
    *) return 1 ;;
  esac
}

# _select_tests -> lista de test files apos aplicar PATTERN e o filtro de
# velocidade (SPEED). all=todos; fast=exclui lentos; slow=so lentos. Substitui
# _find_test_files "$PATTERN" nos modos que respeitam --fast/--slow (list, stats,
# run). check-coverage NAO usa isto (cobertura precisa enxergar todos).
_select_tests() {
  _st_all=$(_find_test_files "$PATTERN")
  if [ "$SPEED" = "all" ]; then
    printf '%s\n' "$_st_all"
    return 0
  fi
  _OLD_IFS="$IFS"
  IFS='
'
  for _st_t in $_st_all; do
    [ -z "$_st_t" ] && continue
    if _is_slow_test "$_st_t"; then
      [ "$SPEED" = "slow" ] && printf '%s\n' "$_st_t"
    else
      [ "$SPEED" = "fast" ] && printf '%s\n' "$_st_t"
    fi
  done
  IFS="$_OLD_IFS"
}

# ==== 4. Modos: --list e --stats ====

# _emit_scenarios -> emite uma linha 'arquivo.sh :: scenario_nome' por scenario,
# sobre os tests selecionados por _select_tests (PATTERN + SPEED). Base comum de
# --list e --stats. Retorna 2 se PATTERN nao casa nenhum test.
_emit_scenarios() {
  _es_tests=$(_select_tests)
  if [ -z "$_es_tests" ]; then
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
  for _test in $_es_tests; do
    [ -z "$_test" ] && continue
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

mode_list() {
  _emit_scenarios
}

# mode_stats — agrega contagem de scenarios por arquivo (desc) + total. Util
# para enxergar a distribuicao de cobertura por script (alem do binario
# tem/nao-tem de --check-coverage). Nota: conta apenas scenarios DEFINIDOS
# estaticamente como funcoes scenario_*(); scenarios gerados dinamicamente
# (ex: corpus via _SCENARIOS) nao aparecem aqui.
mode_stats() {
  _stats_out=$(_emit_scenarios) || return $?
  if [ -z "$_stats_out" ]; then
    printf '# nenhum scenario encontrado.\n'
    return 0
  fi
  # Contagem por arquivo, ordenada desc.
  printf '%s\n' "$_stats_out" \
    | awk -F ' :: ' 'NF==2 { c[$1]++ } END { for (f in c) printf "%5d  %s\n", c[f], f }' \
    | sort -rn
  # Totais (computados a parte para nao colidir com o sort -rn acima).
  _total=$(printf '%s\n' "$_stats_out" | grep -c ' :: ') || _total=0
  _nfiles=$(printf '%s\n' "$_stats_out" | awk -F ' :: ' 'NF==2 { print $1 }' | sort -u | grep -c .) || _nfiles=0
  printf '%s\n' '-----'
  printf 'TOTAL: %d scenarios em %d arquivo(s)\n' "$_total" "$_nfiles"
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
  _tests=$(_select_tests)
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
  stats) mode_stats ;;
  check-coverage) mode_check_coverage ;;
  run) mode_run ;;
esac
