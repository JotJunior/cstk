#!/bin/sh
# test__state-ondas-db.sh — cobre global/skills/agente-00c-runtime/scripts/_state-ondas-db.sh
# (implementacao do backend SQLite de state-ondas.sh — feature state-db-foundation,
# FASE 3 task 3.3).
#
# Ref: docs/specs/state-db-foundation/tasks.md FASE 3, task 3.3
#      docs/specs/state-db-foundation/contracts/primitives.md §C1 C2 C3 C4
#
# Cobertura desta unit suite: helpers de baixo nivel (_so_db_aggregate_agent_usage,
# _so_tasks_md_titlemap, _so_tasks_md_missing). O comportamento observavel via
# CLI (start/end/record-*/wave-status/current-id/reconcile-*) e coberto em
# tests/test_state-ondas.sh, que e o oraculo de paridade C1.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

if ! command -v jq >/dev/null 2>&1; then
  printf '# test__state-ondas-db.sh: jq ausente — pulando suite\n'
  exit 0
fi

_R="$REPO_ROOT/global/skills/agente-00c-runtime/scripts"
# shellcheck source=../global/skills/agente-00c-runtime/scripts/_diag.sh
. "$_R/_diag.sh"
# shellcheck source=../global/skills/agente-00c-runtime/scripts/_state-db.sh
. "$_R/_state-db.sh"
# shellcheck source=../global/skills/agente-00c-runtime/scripts/_state-rw-db.sh
. "$_R/_state-rw-db.sh"
# shellcheck source=../global/skills/agente-00c-runtime/scripts/_state-ondas-db.sh
. "$_R/_state-ondas-db.sh"

# _sr_die/_so_die/_so_log: normalmente definidos por state-ondas.sh antes de
# sourcear estas libs. Fornecemos equivalentes minimos para exercitar as
# funcoes isoladas, sem depender do CLI completo.
_sr_die() { printf 'state-ondas: %s\n' "$1" >&2; exit "${2:-1}"; }
_so_die() { printf 'state-ondas: %s\n' "$1" >&2; exit "${2:-1}"; }
_so_log() { printf 'state-ondas: %s\n' "$1" >&2; }

# ==== _so_db_aggregate_agent_usage ====

scenario_aggregate_agent_usage_vazio_vira_null() {
  _out=$(_so_db_aggregate_agent_usage '[]')
  [ "$_out" = "null" ] || { _fail "aggregate vazio" "obtido '$_out'"; return 1; }
}

scenario_aggregate_agent_usage_soma_campos_observados() {
  _spawns='[{"status":"ok","total_tokens":100,"tool_use_count":3,"duration_ms":500},{"status":"ok","total_tokens":50,"tool_use_count":1,"duration_ms":200}]'
  _out=$(_so_db_aggregate_agent_usage "$_spawns")
  _total=$(printf '%s' "$_out" | jq -r '.spawns_total')
  [ "$_total" = "2" ] || { _fail "aggregate total" "obtido '$_total'"; return 1; }
  _tok=$(printf '%s' "$_out" | jq -r '.total_tokens')
  [ "$_tok" = "150" ] || { _fail "aggregate tokens" "obtido '$_tok'"; return 1; }
}

scenario_aggregate_agent_usage_indisponivel_nao_conta_com_usage() {
  _spawns='[{"status":"indisponivel"},{"status":"ok","total_tokens":10}]'
  _out=$(_so_db_aggregate_agent_usage "$_spawns")
  _with_usage=$(printf '%s' "$_out" | jq -r '.spawns_with_usage')
  [ "$_with_usage" = "1" ] || { _fail "aggregate with_usage" "obtido '$_with_usage'"; return 1; }
  _unavail=$(printf '%s' "$_out" | jq -r '.spawns_unavailable')
  [ "$_unavail" = "1" ] || { _fail "aggregate unavailable" "obtido '$_unavail'"; return 1; }
}

scenario_aggregate_agent_usage_campo_ausente_vira_null_nunca_zero() {
  # Principio VI: campo nunca observado em NENHUM spawn -> null, nao 0
  # fabricado.
  _spawns='[{"status":"ok"}]'
  _out=$(_so_db_aggregate_agent_usage "$_spawns")
  _tok=$(printf '%s' "$_out" | jq -c '.total_tokens')
  [ "$_tok" = "null" ] || { _fail "aggregate campo ausente" "obtido '$_tok'"; return 1; }
}

# ==== _so_tasks_md_titlemap ====

_write_titlemap_md() {
  cat > "$1" <<'TASKS'
# Tarefas

### 1.1 Setup do Projeto `[A]`

- [x] 1.1.1 Criar repo

### 1.2 Dominio `[C]`

- [x] 1.2.1 Entidades
TASKS
}

scenario_titlemap_extrai_heading_sem_criticidade() {
  _md="$TMPDIR_TEST/titlemap.md"
  _write_titlemap_md "$_md"
  _out=$(_so_tasks_md_titlemap "$_md")
  case "$_out" in
    *"1.1	Setup do Projeto"*) : ;;
    *) _fail "titlemap 1.1" "obtido: $_out"; return 1 ;;
  esac
  case "$_out" in
    *'[A]'*) _fail "titlemap carregou criticidade" "obtido: $_out"; return 1 ;;
    *) : ;;
  esac
}

scenario_titlemap_vazio_quando_sem_headings() {
  _md="$TMPDIR_TEST/titlemap-vazio.md"
  printf '# Sem tasks\n\ntexto qualquer\n' > "$_md"
  _out=$(_so_tasks_md_titlemap "$_md")
  [ -z "$_out" ] || { _fail "titlemap vazio" "obtido: $_out"; return 1; }
}

# ==== _so_tasks_md_missing ====

scenario_missing_lista_concluida_ausente_do_existing() {
  _md="$TMPDIR_TEST/missing.md"
  _write_titlemap_md "$_md"
  _exf="$TMPDIR_TEST/existing-empty"
  : > "$_exf"
  _out=$(_so_tasks_md_missing "$_md" "$_exf")
  case "$_out" in
    *"1.1	Setup do Projeto"*) : ;;
    *) _fail "missing 1.1" "obtido: $_out"; return 1 ;;
  esac
  case "$_out" in
    *"1.2	Dominio"*) : ;;
    *) _fail "missing 1.2" "obtido: $_out"; return 1 ;;
  esac
}

scenario_missing_exclui_ja_existentes() {
  _md="$TMPDIR_TEST/missing-excl.md"
  _write_titlemap_md "$_md"
  _exf="$TMPDIR_TEST/existing-1.1"
  printf '1.1\n' > "$_exf"
  _out=$(_so_tasks_md_missing "$_md" "$_exf")
  case "$_out" in
    *"1.1"*) _fail "missing nao deveria incluir 1.1" "obtido: $_out"; return 1 ;;
    *) : ;;
  esac
  case "$_out" in
    *"1.2"*) : ;;
    *) _fail "missing deveria incluir 1.2" "obtido: $_out"; return 1 ;;
  esac
}

scenario_missing_ignora_task_parcial() {
  _md="$TMPDIR_TEST/missing-parcial.md"
  cat > "$_md" <<'TASKS'
# Tarefas

### 2.1 Parcial `[A]`

- [x] 2.1.1 Feito
- [ ] 2.1.2 Nao feito
TASKS
  _exf="$TMPDIR_TEST/existing-parcial-empty"
  : > "$_exf"
  _out=$(_so_tasks_md_missing "$_md" "$_exf")
  [ -z "$_out" ] || { _fail "missing parcial deveria ser vazio" "obtido: $_out"; return 1; }
}

run_all_scenarios
