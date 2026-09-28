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
#   JM-17 relink --new-local-key: renumeracao move a linha (novo local_key
#         active, antigo desaparece do arquivo, jira_id/jira_key mantidos)
#   JM-18 relink --new-local-key ja existente no mapeamento -> exit 1,
#         RECUSA (nada escrito)
#   JM-19 relink fecha ConflictRecord PENDENTE reason=orphan do par como
#         resolution=relinked em runtime/conflicts.tsv (FR-012)
#   JM-20 relink sem runtime/conflicts.tsv -> sucesso normal (best-effort,
#         nada a fechar)
#   JM-21 milestone-put: primeira insercao (state=current) -> header +
#         linha gravados (r02 FASE 16 task 16.3.4, data-model.md Entity
#         Milestone)
#   JM-22 milestone-put: 2a chamada com nome DIFERENTE e state=current
#         rebaixa a current anterior para superseded no MESMO write —
#         no maximo 1 current no arquivo (16.3.4/16.3.7)
#   JM-23 milestone-put: --state blocked SEM --version-id -> exit 0,
#         linha gravada com jira_version_id vazio (nada foi criado no R12)
#   JM-24 milestone-put: --state current SEM --version-id -> exit 2 (uso
#         incorreto), nada escrito
#   JM-25 milestone-put: --state blocked NUNCA rebaixa a current existente
#         de OUTRO nome (marco vigente do Epic nao muda so por falha de
#         criacao de um marco novo)
#   JM-26 milestone-get: (project_key, name) existente -> linha TSV;
#         ausente -> exit 1
#
# ============ link-get/link-put/anchor (r02 FASE 18 tarefa 18.3.2/18.3.3) ===
#
#   JM-27 link-put: 1a insercao (state=active) -> header + linha gravados
#   JM-28 link-get: aresta existente -> linha TSV; ausente -> exit 1
#   JM-29 link-put: 2a chamada com a MESMA chave natural e state=active NAO
#         duplica linha (upsert in-place) — 18.3.4
#   JM-30 link-put: mesma chave, state=stale -> linha ATUALIZADA (nunca
#         removida) — FR-012
#   JM-31 link-put: --state unrepresentable aceita blocker/blocked/type-id
#         vazios, mas EXIGE --reason
#   JM-32 link-put: --state active sem --reason grava reason vazio
#   JM-33 link-put: --state invalido -> exit 2
#   JM-34 link-put: --reason invalido (fora do enum) -> exit 2
#   JM-35 link-put: --state active SEM --blocker-key -> exit 2 (uso
#         incorreto — campos obrigatorios para active/stale)
#   JM-36 link-get: jira-links.tsv ausente -> exit 1
#   JM-37 anchor: Task de menor local_key ACTIVE da FASE -> local_key+jira_key
#   JM-38 anchor: FASE sem nenhuma task -> exit 1 reason=no_anchor
#   JM-39 anchor: FASE com task mas SEM linha active mapeada -> exit 1
#         reason=no_anchor
#   JM-40 anchor: --phase nao-numerico -> exit 2

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

scenario_relink_new_local_key_move_linha() {
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
  assert_exit 0 "$SCRIPT" relink --feature demo --local-key 1.1 --jira-key DEMO-1 \
    --new-local-key 1.2 || return 1
  grep -q '^1\.2	task	10001	DEMO-1	active$' "$(_map_file)" \
    || { _fail "relink_new_key_active" "1.2 nao foi gravado active com os mesmos dados"; return 1; }
  if grep -q '^1\.1	' "$(_map_file)"; then
    _fail "relink_old_key_gone" "1.1 ainda presente no mapeamento apos renumeracao"
    return 1
  fi
}

scenario_relink_new_local_key_ja_existe_exit1() {
  _write_tasks_md
  cd "$TMPDIR_TEST" || return 1
  "$SCRIPT" put --feature demo --local-key 1.1 --kind task \
    --jira-id 10001 --jira-key DEMO-1 >/dev/null || return 1
  "$SCRIPT" put --feature demo --local-key 1.2 --kind task \
    --jira-id 10002 --jira-key DEMO-2 >/dev/null || return 1
  cat > "$TMPDIR_TEST/docs/specs/demo/tasks.md" <<'EOF'
## FASE 1 - Teste `[A]`

### 1.2 Titulo `[A]`

- [ ] 1.2.1 Sub um
EOF
  "$SCRIPT" mark-orphans --feature demo >/dev/null || :
  assert_exit 1 "$SCRIPT" relink --feature demo --local-key 1.1 --jira-key DEMO-1 \
    --new-local-key 1.2 || return 1
  assert_stderr_contains "ja existe no mapeamento" || return 1
  grep -q '^1\.1	task	10001	DEMO-1	orphan$' "$(_map_file)" \
    || { _fail "relink_new_key_conflict_untouched" "1.1 nao deveria ter sido alterado (recusa)"; return 1; }
}

# _write_pending_orphan_conflict FEATURE LOCAL_KEY JIRA_KEY: cria
# runtime/conflicts.tsv com um ConflictRecord PENDENTE reason=orphan (mesmo
# schema/path de `_JS_CONFLICTS_FILE`/`_JS_CONFLICTS_HEADER` em
# jira-sync.sh).
_write_pending_orphan_conflict() {
  mkdir -p "$TMPDIR_TEST/.claude/cstk-jira/runtime"
  {
    printf 'detected_at\tfeature\tlocal_key\tjira_key\treason\tresolution\n'
    printf '2026-01-01T00:00:00Z\t%s\t%s\t%s\torphan\tpending\n' "$1" "$2" "$3"
  } > "$TMPDIR_TEST/.claude/cstk-jira/runtime/conflicts.tsv"
}

scenario_relink_fecha_conflict_record_orphan_como_relinked() {
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
  _write_pending_orphan_conflict demo 1.1 DEMO-1
  assert_exit 0 "$SCRIPT" relink --feature demo --local-key 1.1 --jira-key DEMO-1 \
    --new-local-key 1.2 || return 1
  grep -q '	demo	1\.1	DEMO-1	orphan	relinked$' \
    "$TMPDIR_TEST/.claude/cstk-jira/runtime/conflicts.tsv" \
    || { _fail "conflict_closed_relinked" "ConflictRecord nao foi fechado como relinked"; return 1; }
}

scenario_relink_sem_conflicts_tsv_sucesso_normal() {
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
  # Deliberadamente NAO cria runtime/conflicts.tsv.
  assert_exit 0 "$SCRIPT" relink --feature demo --local-key 1.1 --jira-key DEMO-1 || return 1
  [ ! -e "$TMPDIR_TEST/.claude/cstk-jira/runtime/conflicts.tsv" ] \
    || { _fail "no_conflicts_file_created" "relink nao deveria criar conflicts.tsv do nada"; return 1; }
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

_milestone_file() {
  printf '%s\n' "$TMPDIR_TEST/docs/specs/demo/jira-milestones.tsv"
}

scenario_milestone_put_primeira_insercao_current() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cd "$TMPDIR_TEST" || return 1
  assert_exit 0 "$SCRIPT" milestone-put --feature demo --name demo-r02 \
    --kind round --version-id 30001 --project-key DEMO --state current || return 1
  _mf=$(_milestone_file)
  [ -f "$_mf" ] || { _fail "milestone_put_creates_file" "arquivo nao foi criado"; return 1; }
  head -n1 "$_mf" | grep -q '^milestone_name	milestone_kind	jira_version_id	project_key	state$' \
    || { _fail "milestone_put_header" "cabecalho ausente/incorreto"; return 1; }
  grep -q '^demo-r02	round	30001	DEMO	current$' "$_mf" \
    || { _fail "milestone_put_row" "linha current ausente/incorreta"; return 1; }
}

scenario_milestone_put_novo_current_rebaixa_anterior_a_superseded() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cd "$TMPDIR_TEST" || return 1
  "$SCRIPT" milestone-put --feature demo --name demo-r02 \
    --kind round --version-id 30001 --project-key DEMO --state current >/dev/null || return 1
  assert_exit 0 "$SCRIPT" milestone-put --feature demo --name demo-r03 \
    --kind round --version-id 30002 --project-key DEMO --state current || return 1
  _mf=$(_milestone_file)
  grep -q '^demo-r02	round	30001	DEMO	superseded$' "$_mf" \
    || { _fail "milestone_put_downgrade" "current anterior nao foi rebaixado a superseded"; return 1; }
  grep -q '^demo-r03	round	30002	DEMO	current$' "$_mf" \
    || { _fail "milestone_put_new_current" "novo current ausente/incorreto"; return 1; }
  _ncur=$(awk -F'\t' 'NR>1 && $5=="current"' "$_mf" | wc -l | tr -d ' ')
  [ "$_ncur" = "1" ] || { _fail "milestone_put_single_current" "esperado exatamente 1 linha current, obtido $_ncur"; return 1; }
}

scenario_milestone_put_blocked_sem_version_id_ok() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cd "$TMPDIR_TEST" || return 1
  assert_exit 0 "$SCRIPT" milestone-put --feature demo --name demo-r02 \
    --kind round --project-key DEMO --state blocked || return 1
  grep -q '^demo-r02	round		DEMO	blocked$' "$(_milestone_file)" \
    || { _fail "milestone_put_blocked_row" "linha blocked com jira_version_id vazio ausente/incorreta"; return 1; }
}

scenario_milestone_put_current_sem_version_id_exit2() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cd "$TMPDIR_TEST" || return 1
  assert_exit 2 "$SCRIPT" milestone-put --feature demo --name demo-r02 \
    --kind round --project-key DEMO --state current || return 1
  [ -f "$(_milestone_file)" ] && { _fail "milestone_put_current_no_version_no_write" "arquivo foi criado apesar de --version-id ausente"; return 1; }
  return 0
}

scenario_milestone_put_blocked_nunca_rebaixa_current_de_outro_nome() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cd "$TMPDIR_TEST" || return 1
  "$SCRIPT" milestone-put --feature demo --name demo-r02 \
    --kind round --version-id 30001 --project-key DEMO --state current >/dev/null || return 1
  assert_exit 0 "$SCRIPT" milestone-put --feature demo --name demo-r03 \
    --kind round --project-key DEMO --state blocked || return 1
  _mf=$(_milestone_file)
  grep -q '^demo-r02	round	30001	DEMO	current$' "$_mf" \
    || { _fail "milestone_put_blocked_preserves_current" "current de outro nome foi alterado por um write blocked"; return 1; }
  grep -q '^demo-r03	round		DEMO	blocked$' "$_mf" \
    || { _fail "milestone_put_blocked_row2" "linha blocked ausente/incorreta"; return 1; }
}

scenario_milestone_get_existente_e_ausente() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cd "$TMPDIR_TEST" || return 1
  "$SCRIPT" milestone-put --feature demo --name demo-r02 \
    --kind round --version-id 30001 --project-key DEMO --state current >/dev/null || return 1
  assert_exit 0 "$SCRIPT" milestone-get --feature demo --name demo-r02 --project-key DEMO || return 1
  assert_stdout_contains "demo-r02	round	30001	DEMO	current" || return 1
  assert_exit 1 "$SCRIPT" milestone-get --feature demo --name demo-r99 --project-key DEMO || return 1
}

# ==== milestone-clear-blocked (r02 FASE 22 tarefa 22.1.2, achado 22.1) ====

scenario_milestone_clear_blocked_remove_linha_e_conta() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cd "$TMPDIR_TEST" || return 1
  "$SCRIPT" milestone-put --feature demo --name demo-r02 \
    --kind round --project-key DEMO --state blocked >/dev/null || return 1
  assert_exit 0 "$SCRIPT" milestone-clear-blocked --feature demo || return 1
  assert_stdout_contains "1" || return 1
  grep -q 'blocked' "$(_milestone_file)" \
    && { _fail "milestone_clear_blocked_removed" "linha blocked deveria ter sido removida: $(cat "$(_milestone_file)")"; return 1; }
  return 0
}

scenario_milestone_clear_blocked_preserva_current() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cd "$TMPDIR_TEST" || return 1
  "$SCRIPT" milestone-put --feature demo --name demo-r02 \
    --kind round --version-id 30001 --project-key DEMO --state current >/dev/null || return 1
  "$SCRIPT" milestone-put --feature demo --name demo-r03 \
    --kind round --project-key DEMO --state blocked >/dev/null || return 1
  assert_exit 0 "$SCRIPT" milestone-clear-blocked --feature demo || return 1
  assert_stdout_contains "1" || return 1
  _mf=$(_milestone_file)
  grep -q '^demo-r02	round	30001	DEMO	current$' "$_mf" \
    || { _fail "milestone_clear_blocked_keeps_current" "linha current de outro nome foi alterada"; return 1; }
  grep -q 'demo-r03' "$_mf" \
    && { _fail "milestone_clear_blocked_removed_r03" "linha blocked deveria ter sido removida"; return 1; }
  return 0
}

scenario_milestone_clear_blocked_idempotente_sem_blocked() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cd "$TMPDIR_TEST" || return 1
  assert_exit 0 "$SCRIPT" milestone-clear-blocked --feature demo || return 1
  assert_stdout_contains "0" || return 1
}

# ==== link-get / link-put (r02 FASE 18 tarefa 18.3.2) ====

_link_file() {
  printf '%s\n' "$TMPDIR_TEST/docs/specs/demo/jira-links.tsv"
}

scenario_link_put_primeira_insercao_active() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cd "$TMPDIR_TEST" || return 1
  assert_exit 0 "$SCRIPT" link-put --feature demo --from 1 --to 2 \
    --blocker-key DEMO-1 --blocked-key DEMO-2 --type-id 10000 --state active || return 1
  _lf=$(_link_file)
  [ -f "$_lf" ] || { _fail "link_put_creates_file" "arquivo nao foi criado"; return 1; }
  head -n1 "$_lf" | grep -q '^from_phase	to_phase	blocker_key	blocked_key	link_type_id	state	reason$' \
    || { _fail "link_put_header" "cabecalho ausente/incorreto"; return 1; }
  grep -q '^1	2	DEMO-1	DEMO-2	10000	active	$' "$_lf" \
    || { _fail "link_put_row" "linha active ausente/incorreta"; return 1; }
}

scenario_link_get_existente_e_ausente() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cd "$TMPDIR_TEST" || return 1
  "$SCRIPT" link-put --feature demo --from 1 --to 2 --blocker-key DEMO-1 \
    --blocked-key DEMO-2 --type-id 10000 --state active >/dev/null || return 1
  assert_exit 0 "$SCRIPT" link-get --feature demo --from 1 --to 2 || return 1
  assert_stdout_contains "1	2	DEMO-1	DEMO-2	10000	active" || return 1
  assert_exit 1 "$SCRIPT" link-get --feature demo --from 9 --to 9 || return 1
}

scenario_link_get_arquivo_ausente_exit1() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cd "$TMPDIR_TEST" || return 1
  assert_exit 1 "$SCRIPT" link-get --feature demo --from 1 --to 2 || return 1
}

scenario_link_put_mesma_chave_active_nao_duplica() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cd "$TMPDIR_TEST" || return 1
  "$SCRIPT" link-put --feature demo --from 1 --to 2 --blocker-key DEMO-1 \
    --blocked-key DEMO-2 --type-id 10000 --state active >/dev/null || return 1
  assert_exit 0 "$SCRIPT" link-put --feature demo --from 1 --to 2 \
    --blocker-key DEMO-1 --blocked-key DEMO-2 --type-id 10000 --state active || return 1
  _n=$(awk -F '\t' 'NR>1 && $1=="1" && $2=="2"' "$(_link_file)" | wc -l | tr -d ' ')
  [ "$_n" = "1" ] || { _fail "link_put_no_dup" "esperado 1 linha para (1,2), obtido $_n"; return 1; }
}

scenario_link_put_stale_atualiza_nunca_remove() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cd "$TMPDIR_TEST" || return 1
  "$SCRIPT" link-put --feature demo --from 1 --to 2 --blocker-key DEMO-1 \
    --blocked-key DEMO-2 --type-id 10000 --state active >/dev/null || return 1
  assert_exit 0 "$SCRIPT" link-put --feature demo --from 1 --to 2 \
    --blocker-key DEMO-1 --blocked-key DEMO-2 --type-id 10000 --state stale \
    --reason anchor_changed || return 1
  _lf=$(_link_file)
  grep -q '^1	2	DEMO-1	DEMO-2	10000	stale	anchor_changed$' "$_lf" \
    || { _fail "link_put_stale_row" "linha stale ausente/incorreta"; return 1; }
  _n=$(awk -F '\t' 'NR>1 && $1=="1" && $2=="2"' "$_lf" | wc -l | tr -d ' ')
  [ "$_n" = "1" ] || { _fail "link_put_stale_never_removed_but_no_dup" "esperado 1 linha, obtido $_n"; return 1; }
}

scenario_link_put_unrepresentable_campos_vazios_exige_reason() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cd "$TMPDIR_TEST" || return 1
  assert_exit 0 "$SCRIPT" link-put --feature demo --from 3 --to 4 \
    --blocker-key "" --blocked-key "" --type-id "" --state unrepresentable \
    --reason no_anchor || return 1
  awk -F '\t' 'NR>1 && $1=="3" && $2=="4" && $3=="" && $4=="" && $5=="" && $6=="unrepresentable" && $7=="no_anchor" { f=1 } END { exit(f?0:1) }' \
    "$(_link_file)" \
    || { _fail "link_put_unrepresentable_row" "linha unrepresentable ausente/incorreta"; return 1; }

  assert_exit 2 "$SCRIPT" link-put --feature demo --from 5 --to 6 \
    --blocker-key "" --blocked-key "" --type-id "" --state unrepresentable || return 1
}

scenario_link_put_active_sem_reason_grava_vazio() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cd "$TMPDIR_TEST" || return 1
  assert_exit 0 "$SCRIPT" link-put --feature demo --from 1 --to 2 \
    --blocker-key DEMO-1 --blocked-key DEMO-2 --type-id 10000 --state active || return 1
  grep -q '^1	2	DEMO-1	DEMO-2	10000	active	$' "$(_link_file)" \
    || { _fail "link_put_active_empty_reason" "reason deveria ficar vazio"; return 1; }
}

scenario_link_put_state_invalido_exit2() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cd "$TMPDIR_TEST" || return 1
  assert_exit 2 "$SCRIPT" link-put --feature demo --from 1 --to 2 \
    --blocker-key DEMO-1 --blocked-key DEMO-2 --type-id 10000 --state bogus || return 1
}

scenario_link_put_reason_invalido_exit2() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cd "$TMPDIR_TEST" || return 1
  assert_exit 2 "$SCRIPT" link-put --feature demo --from 1 --to 2 \
    --blocker-key "" --blocked-key "" --type-id "" --state unrepresentable \
    --reason bogus_reason || return 1
}

scenario_link_put_active_sem_blocker_key_exit2() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cd "$TMPDIR_TEST" || return 1
  assert_exit 2 "$SCRIPT" link-put --feature demo --from 1 --to 2 \
    --blocker-key "" --blocked-key DEMO-2 --type-id 10000 --state active || return 1
}

# ==== anchor (r02 FASE 18 tarefa 18.3.3) ====

_write_tasks_md_fase2() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cat > "$TMPDIR_TEST/docs/specs/demo/tasks.md" <<'EOF'
## FASE 1 - Um `[A]`

### 1.1 Primeira `[A]`

- [x] 1.1.1 sub

### 1.2 Segunda `[A]`

- [x] 1.2.1 sub

## FASE 2 - Dois `[A]`

### 2.1 Terceira `[A]`

- [x] 2.1.1 sub
EOF
}

scenario_anchor_menor_local_key_active() {
  _write_tasks_md_fase2
  cd "$TMPDIR_TEST" || return 1
  # so 1.2 esta active (1.1 permanece nao mapeada) -> ancora deve ser 1.2,
  # nao a "menor" absoluta e sim a menor DENTRE AS ACTIVE.
  "$SCRIPT" put --feature demo --local-key 1.2 --kind task \
    --jira-id 20 --jira-key DEMO-20 >/dev/null || return 1
  assert_exit 0 "$SCRIPT" anchor --feature demo --phase 1 || return 1
  assert_stdout_contains "1.2	DEMO-20" || return 1
}

scenario_anchor_prefere_menor_quando_ambas_active() {
  _write_tasks_md_fase2
  cd "$TMPDIR_TEST" || return 1
  "$SCRIPT" put --feature demo --local-key 1.2 --kind task \
    --jira-id 20 --jira-key DEMO-20 >/dev/null || return 1
  "$SCRIPT" put --feature demo --local-key 1.1 --kind task \
    --jira-id 10 --jira-key DEMO-10 >/dev/null || return 1
  assert_exit 0 "$SCRIPT" anchor --feature demo --phase 1 || return 1
  assert_stdout_contains "1.1	DEMO-10" || return 1
}

scenario_anchor_fase_sem_task_exit1() {
  _write_tasks_md_fase2
  cd "$TMPDIR_TEST" || return 1
  assert_exit 1 "$SCRIPT" anchor --feature demo --phase 9 || return 1
  assert_stderr_contains "unrepresentable reason=no_anchor" || return 1
}

scenario_anchor_fase_sem_mapeamento_active_exit1() {
  _write_tasks_md_fase2
  cd "$TMPDIR_TEST" || return 1
  assert_exit 1 "$SCRIPT" anchor --feature demo --phase 2 || return 1
  assert_stderr_contains "unrepresentable reason=no_anchor" || return 1
}

scenario_anchor_phase_nao_numerico_exit2() {
  _write_tasks_md_fase2
  cd "$TMPDIR_TEST" || return 1
  assert_exit 2 "$SCRIPT" anchor --feature demo --phase "FASE 1" || return 1
}

run_all_scenarios
