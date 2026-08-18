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
#   plugins/cstk/skills/<skill>/scripts/<n>.sh  ->  tests/test_<n>.sh
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
# Limpeza do loop de execucao: tmpfile de captura + sandbox HOME (este
# ultimo SOMENTE quando criado por nos — nunca remove o HOME real).
_rw_cleanup() {
  rm -f "${_TMPOUT:-}" 2>/dev/null || :
  if [ -n "${_SANDBOX_HOME:-}" ] && [ "$_SANDBOX_HOME" != "${HOME:-}" ]; then
    rm -rf "$_SANDBOX_HOME" 2>/dev/null || :
  fi
}

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
#   - plugins/cstk/skills/<any>/scripts/*.sh  (existente desde a v1)
#   - cli/lib/*.sh                       (FASE 9.3 — extensao da CLI cstk)
_find_scripts() {
  {
    find "$REPO_ROOT/plugins/cstk/skills" -type f -path '*/scripts/*.sh' 2>/dev/null
    find "$REPO_ROOT/cli/lib" -maxdepth 1 -type f -name '*.sh' 2>/dev/null
  } | sort
}

# _expected_test_for_script SCRIPT_PATH
# Imprime o path absoluto do test esperado para o script, conforme convencao.
_expected_test_for_script() {
  _ets_script=$1
  _ets_base=$(_script_basename "$_ets_script")
  case "$_ets_script" in
    */plugins/cstk/skills/*/scripts/*) printf '%s\n' "$TESTS_ROOT/test_$_ets_base.sh" ;;
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
# (cli/lib/ ou plugins/cstk/skills/<X>/scripts/). Esses tests rodam normalmente,
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
    test_validate-plugin-manifests.sh)
      # Cobre scripts/validate-plugin-manifests.sh (top-level scripts/, fora
      # da convencao cli/lib | skills/*/scripts — mesmo tratamento de
      # test_build-release.sh). FASE 5.1.3/5.1.4 de claude-plugin-packaging.
      return 0 ;;
    test_plugin-hooks-manifest.sh)
      # Cobre plugins/cstk/hooks/hooks.json — manifesto de dados estatico,
      # sem script .sh "dono" sob a convencao de FASE 9.3. FASE 5.3.4 de
      # claude-plugin-packaging.
      return 0 ;;
    test_doc-counts.sh)
      # Guarda numeros derivados (skills/scenarios) na doc de entrada vs repo.
      # Teste de invariante do repositorio — nao mapeia 1:1 para um script.
      return 0 ;;
    test_doc-subcommands.sh)
      # Lint: refs `<helper>.sh <subcomando>` nos docs apontam p/ subcomando
      # real (case-label no dispatch). Invariante do repo — nao mapeia 1:1.
      return 0 ;;
    test_specify-reopen-shortcut.sh)
      # Guarda estrutural sobre plugins/cstk/skills/specify/SKILL.md
      # §0.0/§0.4/§0.5 (feature-reopen FASE 6.1 / dec-058) — SKILL.md e
      # prosa LLM, sem script .sh "dono" sob a convencao de FASE 9.3.
      # Existence-guarded ao proprio SKILL.md; se a fonte sumir, volta a
      # ser orfao real.
      [ -f "$REPO_ROOT/plugins/cstk/skills/specify/SKILL.md" ] && return 0
      return 1 ;;
    test_create-tasks-reopen-append.sh)
      # Guarda estrutural sobre plugins/cstk/skills/create-tasks/SKILL.md
      # §Deteccao de reabertura (feature-reopen FASE 6.2) — SKILL.md e
      # prosa LLM, sem script .sh "dono" sob a convencao de FASE 9.3.
      # Existence-guarded ao proprio SKILL.md; se a fonte sumir, volta a
      # ser orfao real.
      [ -f "$REPO_ROOT/plugins/cstk/skills/create-tasks/SKILL.md" ] && return 0
      return 1 ;;
    test_install-extra-kinds.sh)
      # Cobre interacao install.sh + manifest.sh + doctor.sh para os kinds
      # commands/agents (nao mapeia 1:1 para um unico script sob a convencao).
      return 0 ;;
    test_00c-state-backend-contract.sh)
      # Smoke textual sobre resume/abort dos 2 escopos: aceitacao de
      # state.db (paridade de backend) + semantica correta do lock no
      # resume da feature. Assert no .md, nao em um unico script —
      # existence-guarded ao command portador das duas regras. Se a fonte
      # sumir, volta a ser orfao real.
      [ -f "$REPO_ROOT/plugins/cstk/commands/feature-00c-resume.md" ] && return 0
      return 1 ;;
    test_command-spawn-model-routing.sh)
      # Smoke textual sobre os 4 commands de spawn/resume (model-routing
      # por onda, FASE 3 de model-routing-por-onda). Assert no .md, nao em
      # um unico script — existence-guarded ao command portador da instrucao
      # wave-select. Se a fonte sumir, volta a ser orfao real.
      [ -f "$REPO_ROOT/plugins/cstk/commands/feature-00c.md" ] && return 0
      return 1 ;;
    test_command-spawn-mcp-lifecycle.sh)
      # Smoke textual sobre os 4 commands de spawn/resume (ciclo de vida do
      # servidor MCP: status/start/stop, FASE 6 task 6.2 de
      # state-mcp-server). Assert no .md, nao em um unico script —
      # existence-guarded ao command portador da instrucao `cstk mcp`. Se a
      # fonte sumir, volta a ser orfao real.
      [ -f "$REPO_ROOT/plugins/cstk/commands/feature-00c.md" ] && return 0
      return 1 ;;
    test_command-spawn-roadmap-mode.sh)
      # Smoke textual sobre o prompt opt-in do modo roadmap (FASE 6 task
      # 6.2.2 de roadmap-mode). Assert no .md, nao em um unico script —
      # existence-guarded ao command portador do prompt
      # (plugins/cstk/commands/agente-00c.md). Se a fonte sumir, volta a
      # ser orfao real.
      [ -f "$REPO_ROOT/plugins/cstk/commands/agente-00c.md" ] && return 0
      return 1 ;;
    test_command-spawn-parallel-launch.sh)
      # Smoke textual sobre a oferta de leva paralela pos-roadmap (FASE 2
      # tasks 2.8/2.9 de roadmap-parallel-launch) embutida em
      # agente-00c.md §6.ter / agente-00c-resume.md §9.ter. Assert no .md,
      # nao em um unico script — existence-guarded aos 2 commands
      # portadores da oferta. Se a fonte sumir, volta a ser orfao real.
      [ -f "$REPO_ROOT/plugins/cstk/commands/agente-00c.md" ] && return 0
      return 1 ;;
    test_command-spawn-delivery-tier.sh)
      # Smoke textual sobre o prompt de finalidade (tier de entrega) em
      # plugins/cstk/commands/agente-00c.md + leitura sem re-prompt em
      # agente-00c-resume.md (FASE 4 task 4.3 de delivery-tier). Assert no
      # .md, nao em um unico script — existence-guarded ao command
      # portador do prompt. Se a fonte sumir, volta a ser orfao real.
      [ -f "$REPO_ROOT/plugins/cstk/commands/agente-00c.md" ] && return 0
      return 1 ;;
    test_command-spawn-optin-degradation.sh)
      # Smoke textual sobre a FASE 6 (fallback integral para prosa) de
      # mcp-elicitation-optins: convergencia legado x degradacao mid-call
      # nos 2 commands + 2 agents de spawn. Assert no .md, nao em um unico
      # script — existence-guarded ao command portador do ramo legado
      # (plugins/cstk/commands/agente-00c.md). Se a fonte sumir, volta a
      # ser orfao real.
      [ -f "$REPO_ROOT/plugins/cstk/commands/agente-00c.md" ] && return 0
      return 1 ;;
    test_command-spawn-optin-elicitation.sh)
      # Smoke textual sobre a FASE 10 (task 10.1) de mcp-elicitation-optins:
      # ordem do ramo estruturado, preservacao do ramo legado, correcao dos
      # comentarios stale sobre mode=bash-fallback, condicionalidade de
      # --allow-downgrade e escopo negativo feature-00c*. Assert sobre os 4
      # commands + 2 agents + mcp/state-server/src/tools/collect_optins.ts —
      # nao em um unico script sob a convencao de FASE 9.3 —
      # existence-guarded ao command portador do ramo estruturado
      # (plugins/cstk/commands/agente-00c.md). Se a fonte sumir, volta a
      # ser orfao real.
      [ -f "$REPO_ROOT/plugins/cstk/commands/agente-00c.md" ] && return 0
      return 1 ;;
    test_command-prompt-noninteractive-lint.sh)
      # LINT DE CLASSE: varre plugins/cstk/commands/*.md exigindo clausula
      # de nao-interatividade em todo prompt ao operador. Assert textual
      # sobre um DIRETORIO — nao ha script unico sob teste.
      # Existence-guarded ao diretorio de commands.
      [ -d "$REPO_ROOT/plugins/cstk/commands" ] && return 0
      return 1 ;;
    test_command-warmup-noninteractive.sh)
      # Smoke textual sobre a clausula de execucao nao-interativa do
      # warm-up de permissoes, nos DOIS commands portadores
      # (agente-00c.md + feature-00c.md). Assert no .md, nao em um unico
      # script — existence-guarded a ambos. Se as fontes sumirem, volta a
      # ser orfao real.
      [ -f "$REPO_ROOT/plugins/cstk/commands/agente-00c.md" ] \
        && [ -f "$REPO_ROOT/plugins/cstk/commands/feature-00c.md" ] && return 0
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
      [ -f "$REPO_ROOT/plugins/cstk/agents/agente-00c-feature-orchestrator.md" ] && return 0
      return 1 ;;
    test_orchestrator-spawn-model-apply.sh)
      # Smoke textual sobre os 2 orquestradores (model-routing por onda,
      # FASE 5 de model-routing-por-onda). Assert no .md (passo 8 da
      # §5.e.bis / secao model-routing), nao em um unico script —
      # existence-guarded ao orquestrador portador da instrucao de aplicar
      # model no spawn de clarify. Se a fonte sumir, volta a ser orfao real.
      [ -f "$REPO_ROOT/plugins/cstk/agents/agente-00c-feature-orchestrator.md" ] && return 0
      return 1 ;;
    test_orchestrator-turn-completion.sh)
      # Smoke textual sobre os 2 orquestradores (trava do "Contrato de
      # conclusao de turno" — anti-parada-cedo apos Skill retornar). Assert
      # no .md, nao em um unico script — existence-guarded ao orquestrador
      # portador do contrato. Se a fonte sumir, volta a ser orfao real.
      [ -f "$REPO_ROOT/plugins/cstk/agents/agente-00c-feature-orchestrator.md" ] && return 0
      return 1 ;;
    test_orchestrator-evidence-grounding.sh)
      # Smoke textual sobre os 2 orquestradores + 2 resume (regra "aterramento
      # de evidencia em escalada de seguranca" — anti-confabulacao). Assert no
      # .md/.command, nao em um unico script — existence-guarded. Se a regra
      # sumir do prompt, o bug (escalar ameaca fabricada) volta silenciosamente.
      [ -f "$REPO_ROOT/plugins/cstk/agents/agente-00c-feature-orchestrator.md" ] && return 0
      return 1 ;;
    test_data-veracity-verifier.sh)
      # Smoke textual sobre o agente data-veracity-verifier + a fiacao nos 2
      # orquestradores (Principio VI — Veracidade de Dados / Zero Fabricacao).
      # Assert no .md do agente, nao em um unico script — existence-guarded. Se
      # o contrato sumir, o "double check" anti-fabricacao some silenciosamente.
      [ -f "$REPO_ROOT/plugins/cstk/agents/data-veracity-verifier.md" ] && return 0
      return 1 ;;
    test_orchestrator-allowlist-guard.sh)
      # Guard de composicao de allowlist dos orquestradores (feature
      # orchestrator-mcp-allowlist, FASE 1 task 1.1/1.2, FR-002/FR-003/
      # FR-004/FR-012): parseia frontmatter (forma inline + forma lista)
      # dos alvos casados por `plugins/cstk/agents/*-orchestrator.md` e
      # garante allowlist nunca vazia/nunca-so-MCP. Assert sobre um
      # DIRETORIO via glob dinamico, nao em um unico script — existence-
      # guarded ao diretorio de agentes. Se ele sumir, volta a ser orfao
      # real. Ver contracts/orchestrator-allowlist-guard.md secao
      # "Integracao com o harness".
      [ -d "$REPO_ROOT/plugins/cstk/agents" ] && return 0
      return 1 ;;
    test_converge-orchestrator-gate.sh)
      # Smoke textual sobre os 2 orquestradores (gate incondicional
      # `convergence` na fronteira execute-task -> review-task, feature
      # skill-converge FASE 4 — US5/FR-015/FR-019). Assert no .md, nao em um
      # unico script — existence-guarded ao orquestrador portador do gate. Se
      # a secao sumir, a regressao (converge nunca invocada antes de
      # review-task) volta silenciosamente.
      [ -f "$REPO_ROOT/plugins/cstk/agents/agente-00c-feature-orchestrator.md" ] && return 0
      return 1 ;;
    test_e2e_model_routing.sh)
      # Cobre fluxo end-to-end model-routing.sh + model-routing-report.sh +
      # state-rw.sh + state-decisions.sh + state-ondas.sh (composicao de
      # 5 scripts da agente-00c-runtime — nao mapeia 1:1 para um unico
      # script sob a convencao de FASE 9.3). Equivalente ao
      # test_quickstart-e2e.sh para o pipeline do agente-00c.
      return 0 ;;
    test_state-parity-sweep.sh)
      # Varredura anti-regressao da paridade runtime x backend SQLite
      # (feature state-db-runtime-parity, FR-009, FASE 6.1): camada dinamica
      # roda o MANIFEST dos 15 leitores contra state-dir sqlite populado;
      # camada estatica grep de acesso direto a state.json com allowlist
      # literal (CHK016). Composicao de N scripts — nao mapeia 1:1.
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
      # caminho do runtime (plugins/cstk/skills/agente-00c-runtime/scripts/
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
      [ -f "$REPO_ROOT/plugins/cstk/skills/model-selector/scripts/classify.sh" ] && return 0
      return 1 ;;
    test_report_jq_confinement.sh|test_report_performance.sh|test_report_read_only.sh|test_report_without_jq.sh)
      # cobrem model-selector/scripts/report.sh (geracao do relatorio)
      [ -f "$REPO_ROOT/plugins/cstk/skills/model-selector/scripts/report.sh" ] && return 0
      return 1 ;;
    test_update-extra-kinds.sh)
      # aspecto extra de cli/lib/update.sh (primario: tests/cstk/test_update.sh)
      [ -f "$REPO_ROOT/cli/lib/update.sh" ] && return 0
      return 1 ;;
    test_runtime-log-redaction.sh)
      # cobre agente-00c-runtime/scripts/_log.sh (redacao de log)
      [ -f "$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/_log.sh" ] && return 0
      return 1 ;;
    test_secrets-filter-backup.sh)
      # aspecto backup de secrets-filter.sh (primario: tests/test_secrets-filter.sh)
      [ -f "$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/secrets-filter.sh" ] && return 0
      return 1 ;;
    test_skills-cache-protocol.sh)
      # cobre state-cache.sh (protocolo de cache; primario: tests/test_state-cache.sh)
      [ -f "$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/state-cache.sh" ] && return 0
      return 1 ;;
    test_state-dir-parametrization.sh)
      # cobre agente-00c-runtime/scripts/_state-dir.sh (parametrizacao do state dir)
      [ -f "$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/_state-dir.sh" ] && return 0
      return 1 ;;
    test_pretooluse-bash-guard.sh)
      # cobre plugins/cstk/skills/agente-00c-runtime/hooks/pretooluse-bash-guard.sh
      # (US1, enforced-guards). _find_scripts so escaneia */scripts/*.sh e
      # cli/lib/*.sh por convencao (FASE 9.3) — hooks/ e um diretorio novo
      # (harness-invoked, nao skill/cli-invoked, ver plan.md §Project
      # Structure de enforced-guards) fora desse escopo, entao o mapeamento
      # 1:1 nao enxerga o script mesmo com nome de teste identico. Existence-
      # guarded: se o hook sumir, volta a ser orfao real.
      [ -f "$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/hooks/pretooluse-bash-guard.sh" ] && return 0
      return 1 ;;
    test_posttooluse-tool-call-tick.sh)
      # cobre plugins/cstk/skills/agente-00c-runtime/hooks/posttooluse-tool-call-tick.sh
      # (hook PostToolUse de metrica de tool calls por onda) — mesma razao
      # do test_pretooluse-bash-guard.sh acima: hooks/ esta fora do escaneio
      # por convencao. Existence-guarded.
      [ -f "$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/hooks/posttooluse-tool-call-tick.sh" ] && return 0
      return 1 ;;
    test_posttooluse-agent-usage.sh)
      # cobre plugins/cstk/skills/agente-00c-runtime/hooks/posttooluse-agent-usage.sh
      # (hook PostToolUse/matcher "Agent" de metrica de uso de tokens por
      # spawn de subagente — wave-token-metrics FASE 2) — mesma razao dos
      # dois casos acima: hooks/ esta fora do escaneio por convencao.
      # Existence-guarded.
      [ -f "$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/hooks/posttooluse-agent-usage.sh" ] && return 0
      return 1 ;;
    test_posttooluse-loose-usage.sh)
      # cobre plugins/cstk/skills/agente-00c-runtime/hooks/posttooluse-loose-usage.sh
      # (hook PostToolUse OPT-IN de captura de consumo avulso — feature
      # loose-usage-capture FASE 3) — mesma razao dos 3 casos acima: hooks/
      # esta fora do escaneio por convencao. Existence-guarded.
      [ -f "$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/hooks/posttooluse-loose-usage.sh" ] && return 0
      return 1 ;;
    test_statusline-plan-usage.sh)
      # cobre plugins/cstk/skills/agente-00c-runtime/hooks/statusline-plan-usage.sh
      # (entry-point de statusLine.command que captura o gauge de plano —
      # feature plan-usage-capture FASE 2) — mesma razao dos 4 casos acima:
      # hooks/ esta fora do escaneio por convencao. Existence-guarded.
      [ -f "$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/hooks/statusline-plan-usage.sh" ] && return 0
      return 1 ;;
    *) return 1 ;;
  esac
}

# _is_slow_test PATH -> exit 0 se o test e "lento", 1 caso contrario.
# "Lento" = tempo de parede medido > ~5s (corte limpo no perfil). Allowlist
# DERIVADA DE MEDICAO (nao de categoria): rodada `for f in tests/**/test_*.sh;
# do time sh "$f"; done` em 2026-05-24 (11 entradas originais, ~177s dos
# ~260s da suite). test_pretooluse-bash-guard.sh entrou depois (feature
# hooks-db-parity FASE 6, gate de latencia) apos medicao dedicada — `--fast`
# os pula e roda em fracao do tempo. Reavaliar se o perfil mudar (ver
# tests/README.md "Suite rapida vs completa"). Mesmo estilo de
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
    test_pretooluse-bash-guard.sh)               return 0 ;;  # ~7s (gate de latencia N=20+warmup, hooks-db-parity FASE 6)
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
  # categoria (plugins/cstk/skills/.../scripts/ -> tests/, cli/lib/ -> tests/cstk/).
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

  printf 'Cobertura de testes para scripts em plugins/cstk/skills/**/scripts/ + cli/lib/\n\n'

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

  # Hermeticidade / CI-parity: cada test file roda com HOME sandbox VAZIO —
  # a config global do operador (ex.: ~/.claude/cstk/config com
  # state_backend=sqlite) nao pode vazar para os cenarios. Caso real
  # (2026-08-02): com a config sqlite presente, `state-rw.sh init` cria
  # state.db em vez de state.json e 191 cenarios pre-existentes falham
  # localmente enquanto o CI (HOME limpo) fica verde. O sandbox torna
  # local == CI por construcao. Escape hatch para depurar interacao com o
  # HOME real: CSTK_TESTS_REAL_HOME=1.
  if [ "${CSTK_TESTS_REAL_HOME:-0}" = "1" ]; then
    _SANDBOX_HOME="$HOME"
  else
    _SANDBOX_HOME=$(mktemp -d 2>/dev/null) || {
      printf 'run.sh: mktemp -d indisponivel (sandbox HOME)\n' >&2
      return 2
    }
    # Canonicaliza (pwd -P): no macOS o mktemp devolve /var/folders/... que
    # e symlink de /private/var/... — sem isso, cenarios que comparam paths
    # contra "$HOME" resolvido falham por divergencia literal-vs-fisico.
    _SANDBOX_HOME=$(cd "$_SANDBOX_HOME" && pwd -P) || {
      printf 'run.sh: falha ao canonicalizar sandbox HOME\n' >&2
      return 2
    }
  fi

  # Limpeza por trap cobre ctrl+c / term (sandbox so e removido se criado).
  trap '_rw_cleanup' EXIT INT TERM

  _OLD_IFS="$IFS"
  IFS='
'
  for _test in $_tests; do
    [ -z "$_test" ] && continue
    _test_name=$(basename "$_test")
    printf '# %s\n' "$_test_name"

    # Executa test em subshell, capturando stdout+stderr num tmpfile.
    # Nao abortamos se test falha (por design — _e_ o que estamos medindo).
    HOME="$_SANDBOX_HOME" sh "$_test" > "$_TMPOUT" 2>&1 || :
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
