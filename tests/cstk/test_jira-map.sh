#!/bin/sh
# test_jira-map.sh — cobre plugins/cstk-jira/scripts/jira-map.sh
# (cstk-jira, FASE 2 tarefa 2.3).
#
# Ref: docs/specs/cstk-jira/data-model.md Entity SyncMapping (jira-map.tsv,
#      FR-013/FR-014); docs/specs/cstk-jira/contracts/plugin-scripts.md
#      `jira-map.sh`; tasks.md 2.3.1-2.3.6.
#
# Invariantes cobertos:
#   JM-1  get: mapeamento ausente -> exit 1
#   JM-2  get: local_key ausente do mapeamento -> exit 1
#   JM-3  get: local_key existente -> exit 0 + linha TSV completa em stdout
#   JM-4  put: primeira insercao -> exit 0, linha active gravada com header
#   JM-5  put: --kind invalido -> exit 2 (uso incorreto), nada escrito
#   JM-6  put: local_key ja active -> exit 1, RECUSA (arquivo inalterado)
#   JM-7  put: local_key ja orphan -> exit 1, RECUSA (data-model: criacao
#         so para local_key ausente do arquivo; relink e quem reativa)
#   JM-8  put: --feature com charset invalido -> exit 2
#   JM-9  mark-orphans: mapeamento ausente -> exit 1
#   JM-10 mark-orphans: nenhuma chave orfa -> exit 0, arquivo inalterado
#   JM-11 mark-orphans: local_key removido do tasks.md -> vira orphan,
#         exit 6, linha original nunca apagada, orfaos impressos em stdout
#   JM-12 relink: local_key nao encontrado -> exit 1
#   JM-13 relink: local_key nao esta orphan (ja active) -> exit 1
#   JM-14 relink: --jira-key nao confere com o armazenado -> exit 1
#   JM-15 relink: sucesso -> exit 0, state volta a active, linha preservada
#   JM-16 idempotencia (SC-002): 10 chamadas de put para o mesmo local_key
#         resultam em 0 linhas novas apos a 1a

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk-jira/scripts/jira-map.sh"

# _write_tasks_md: cria docs/specs/demo/tasks.md com 1 task (1.1) + 1 subtask,
# suficiente para jira-tasks.sh items enumerar local_key "demo" (epic) e "1.1"
# (task) — usado pelos scenarios de mark-orphans.
_write_tasks_md() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cat > "$TMPDIR_TEST/docs/specs/demo/tasks.md" <<'EOF'
## FASE 1 - Teste `[A]`

### 1.1 Titulo da tarefa `[A]`

- [x] 1.1.1 Sub um
EOF
}

_map_file() {
  printf '%s\n' "$TMPDIR_TEST/docs/specs/demo/jira-map.tsv"
}

scenario_get_mapeamento_ausente_exit1() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cd "$TMPDIR_TEST" || return 1
  assert_exit 1 "$SCRIPT" get --feature demo --local-key 1.1 || return 1
}

scenario_get_local_key_ausente_exit1() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cd "$TMPDIR_TEST" || return 1
  assert_exit 0 "$SCRIPT" put --feature demo --local-key 1.1 --kind task \
    --jira-id 10001 --jira-key DEMO-1 || return 1
  assert_exit 1 "$SCRIPT" get --feature demo --local-key 9.9 || return 1
}

scenario_get_local_key_existente_retorna_linha() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cd "$TMPDIR_TEST" || return 1
  "$SCRIPT" put --feature demo --local-key 1.1 --kind task \
    --jira-id 10001 --jira-key DEMO-1 >/dev/null || return 1
  assert_exit 0 "$SCRIPT" get --feature demo --local-key 1.1 || return 1
  assert_stdout_contains "1.1	task	10001	DEMO-1	active" || return 1
}

scenario_put_primeira_insercao_grava_header_e_linha() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cd "$TMPDIR_TEST" || return 1
  assert_exit 0 "$SCRIPT" put --feature demo --local-key 1.1 --kind task \
    --jira-id 10001 --jira-key DEMO-1 || return 1
  _map=$(_map_file)
  [ -f "$_map" ] || { _fail "put_creates_file" "arquivo nao foi criado"; return 1; }
  head -n1 "$_map" | grep -q '^local_key	kind	jira_id	jira_key	state$' \
    || { _fail "put_header" "cabecalho ausente/incorreto"; return 1; }
  grep -q '^1\.1	task	10001	DEMO-1	active$' "$_map" \
    || { _fail "put_row" "linha active ausente/incorreta"; return 1; }
}

scenario_put_kind_invalido_exit2_nada_escrito() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cd "$TMPDIR_TEST" || return 1
  assert_exit 2 "$SCRIPT" put --feature demo --local-key 1.1 --kind bogus \
    --jira-id 10001 --jira-key DEMO-1 || return 1
  [ -f "$(_map_file)" ] && { _fail "put_kind_invalid_no_write" "arquivo foi criado apesar do --kind invalido"; return 1; }
  return 0
}

scenario_put_local_key_ja_active_recusado() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cd "$TMPDIR_TEST" || return 1
  "$SCRIPT" put --feature demo --local-key 1.1 --kind task \
    --jira-id 10001 --jira-key DEMO-1 >/dev/null || return 1
  assert_exit 1 "$SCRIPT" put --feature demo --local-key 1.1 --kind task \
    --jira-id 99999 --jira-key DEMO-99 || return 1
  assert_stderr_contains "insercao recusada" || return 1
  grep -q 'DEMO-99' "$(_map_file)" && { _fail "put_no_overwrite" "arquivo foi sobrescrito pelo put recusado"; return 1; }
  return 0
}

scenario_put_local_key_ja_orphan_tambem_recusado() {
  _write_tasks_md
  cd "$TMPDIR_TEST" || return 1
  "$SCRIPT" put --feature demo --local-key 1.1 --kind task \
    --jira-id 10001 --jira-key DEMO-1 >/dev/null || return 1
  cat > "$TMPDIR_TEST/docs/specs/demo/tasks.md" <<'EOF'
## FASE 1 - Teste `[A]`

### 1.2 Renumerada `[A]`

- [ ] 1.2.1 Sub um
EOF
  "$SCRIPT" mark-orphans --feature demo >/dev/null || :
  assert_exit 1 "$SCRIPT" put --feature demo --local-key 1.1 --kind task \
    --jira-id 20000 --jira-key DEMO-2 || return 1
  assert_stderr_contains "insercao recusada" || return 1
}

scenario_put_feature_charset_invalido_exit2() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 2 "$SCRIPT" put --feature "../evil" --local-key 1.1 --kind task \
    --jira-id 10001 --jira-key DEMO-1 || return 1
}

scenario_mark_orphans_mapeamento_ausente_exit1() {
  _write_tasks_md
  cd "$TMPDIR_TEST" || return 1
  assert_exit 1 "$SCRIPT" mark-orphans --feature demo || return 1
}

scenario_mark_orphans_nenhuma_chave_orfa_exit0() {
  _write_tasks_md
  cd "$TMPDIR_TEST" || return 1
  "$SCRIPT" put --feature demo --local-key 1.1 --kind task \
    --jira-id 10001 --jira-key DEMO-1 >/dev/null || return 1
  assert_exit 0 "$SCRIPT" mark-orphans --feature demo || return 1
  grep -q '	active$' "$(_map_file)" || { _fail "still_active" "linha deveria continuar active"; return 1; }
}

scenario_mark_orphans_marca_e_nunca_apaga() {
  _write_tasks_md
  cd "$TMPDIR_TEST" || return 1
  "$SCRIPT" put --feature demo --local-key 1.1 --kind task \
    --jira-id 10001 --jira-key DEMO-1 >/dev/null || return 1
  # Renumera: 1.1 some do tasks.md.
  cat > "$TMPDIR_TEST/docs/specs/demo/tasks.md" <<'EOF'
## FASE 1 - Teste `[A]`

### 1.2 Renumerada `[A]`

- [ ] 1.2.1 Sub um
EOF
  assert_exit 6 "$SCRIPT" mark-orphans --feature demo || return 1
  assert_stdout_contains "1.1	task	10001	DEMO-1	orphan" || return 1
  grep -q '^1\.1	task	10001	DEMO-1	orphan$' "$(_map_file)" \
    || { _fail "orphan_row_present" "linha 1.1 nao foi preservada como orphan"; return 1; }
}

scenario_relink_local_key_nao_encontrado_exit1() {
  _write_tasks_md
  cd "$TMPDIR_TEST" || return 1
  "$SCRIPT" put --feature demo --local-key 1.1 --kind task \
    --jira-id 10001 --jira-key DEMO-1 >/dev/null || return 1
  assert_exit 1 "$SCRIPT" relink --feature demo --local-key 9.9 --jira-key DEMO-1 || return 1
}

scenario_relink_nao_esta_orphan_exit1() {
  _write_tasks_md
  cd "$TMPDIR_TEST" || return 1
  "$SCRIPT" put --feature demo --local-key 1.1 --kind task \
    --jira-id 10001 --jira-key DEMO-1 >/dev/null || return 1
  assert_exit 1 "$SCRIPT" relink --feature demo --local-key 1.1 --jira-key DEMO-1 || return 1
  assert_stderr_contains "nao esta orphan" || return 1
}

scenario_relink_jira_key_nao_confere_exit1() {
  _write_tasks_md
  cd "$TMPDIR_TEST" || return 1
  "$SCRIPT" put --feature demo --local-key 1.1 --kind task \
    --jira-id 10001 --jira-key DEMO-1 >/dev/null || return 1
  cat > "$TMPDIR_TEST/docs/specs/demo/tasks.md" <<'EOF'
## FASE 1 - Teste `[A]`

### 1.2 Renumerada `[A]`

- [ ] 1.2.1 Sub um
EOF
  "$SCRIPT" mark-orphans --feature demo >/dev/null || :
  assert_exit 1 "$SCRIPT" relink --feature demo --local-key 1.1 --jira-key DEMO-ERRADO || return 1
  assert_stderr_contains "nao confere" || return 1
}

scenario_relink_sucesso_reativa_sem_apagar() {
  _write_tasks_md
  cd "$TMPDIR_TEST" || return 1
  "$SCRIPT" put --feature demo --local-key 1.1 --kind task \
    --jira-id 10001 --jira-key DEMO-1 >/dev/null || return 1
  cat > "$TMPDIR_TEST/docs/specs/demo/tasks.md" <<'EOF'
## FASE 1 - Teste `[A]`

### 1.2 Renumerada `[A]`

- [ ] 1.2.1 Sub um
EOF
  "$SCRIPT" mark-orphans --feature demo >/dev/null || :
  assert_exit 0 "$SCRIPT" relink --feature demo --local-key 1.1 --jira-key DEMO-1 || return 1
  grep -q '^1\.1	task	10001	DEMO-1	active$' "$(_map_file)" \
    || { _fail "relink_restores_active" "linha 1.1 nao voltou a active com os mesmos dados"; return 1; }
}

scenario_idempotencia_10x_put_mesma_chave_zero_linhas_novas() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cd "$TMPDIR_TEST" || return 1
  "$SCRIPT" put --feature demo --local-key 1.1 --kind task \
    --jira-id 10001 --jira-key DEMO-1 >/dev/null || return 1
  _before=$(wc -l < "$(_map_file)")
  _i=1
  while [ "$_i" -le 9 ]; do
    "$SCRIPT" put --feature demo --local-key 1.1 --kind task \
      --jira-id 99999 --jira-key DEMO-99 >/dev/null 2>&1 || :
    _i=$((_i + 1))
  done
  _after=$(wc -l < "$(_map_file)")
  if [ "$_before" -ne "$_after" ]; then
    _fail "idempotent_put" "linhas mudaram: before=$_before after=$_after"
    return 1
  fi
  grep -q '^1\.1	task	10001	DEMO-1	active$' "$(_map_file)" \
    || { _fail "idempotent_put_data_intact" "dados originais foram alterados"; return 1; }
}

run_all_scenarios
