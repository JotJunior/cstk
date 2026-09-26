#!/bin/sh
# test_jira-tasks.sh — cobre plugins/cstk-jira/scripts/jira-tasks.sh
# (cstk-jira, FASE 2 tarefa 2.2).
#
# Ref: docs/specs/cstk-jira/data-model.md Entity LocalWorkItem (derivado,
#      nao persistido); docs/specs/cstk-jira/contracts/plugin-scripts.md
#      `jira-tasks.sh`; tasks.md 2.2.1-2.2.6.
#
# Invariantes cobertos:
#   JT-1  items: tasks.md ausente -> exit 1
#   JT-2  items: --feature ausente -> exit 2 (uso incorreto)
#   JT-3  items: --feature com charset invalido -> exit 2
#   JT-4  items: parse do template canonico emite Epic + Task + Subtask
#         (local_key/kind/phase/criticality/title corretos, TAB-separado)
#   JT-5  items: titulo do Epic vem de "# Feature Specification: X" no
#         spec.md; spec.md ausente -> titulo cai para o proprio feature
#   JT-6  local_state de subtask: mapeamento direto dos 4 checkboxes
#         ([ ]->pending, [~]->in_progress, [x]->pass, [!]->fail)
#   JT-7  local_state de task: sem subtask -> pending
#   JT-8  local_state de task: todas subtask [x] -> pass
#   JT-9  local_state de task: mistura [x]+[ ] -> in_progress
#   JT-10 local_state de task: qualquer subtask [!] -> fail (mesmo com [x] junto)
#   JT-11 local_state de task: outcome de --outcomes-file tem precedencia
#         sobre os checkboxes
#   JT-12 local_state de epic: --stage aplica stage_status.<stage> via
#         jira-config.sh quando configurado
#   JT-13 local_state de epic: sem --stage/config, agrega por tasks (todas
#         pass -> pass; alguma ativa -> in_progress; senao pending)
#   JT-14 descricao de subtask com continuacao indentada (multi-linha) e
#         concatenada num unico title (nao truncada na 1a linha)
#   JT-15 secoes pos-tasks (Matriz de Dependencias/Resumo/Escopo, `## `
#         nao-FASE) nunca vazam para o output como item espurio
#   JT-16 items: --outcomes-file apontando para arquivo inexistente -> exit 1

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk-jira/scripts/jira-tasks.sh"

# _write_tasks_md CONTENT_HEREDOC-caller: grava docs/specs/demo/tasks.md
# a partir de stdin, no TMPDIR_TEST atual.
_write_tasks_md() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cat > "$TMPDIR_TEST/docs/specs/demo/tasks.md"
}

_write_spec_md() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cat > "$TMPDIR_TEST/docs/specs/demo/spec.md"
}

scenario_items_tasks_ausente_exit1() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 1 "$SCRIPT" items --feature naoexiste || return 1
}

scenario_items_sem_feature_exit2() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 2 "$SCRIPT" items || return 1
}

scenario_items_feature_charset_invalido_exit2() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 2 "$SCRIPT" items --feature "../etc" || return 1
}

scenario_items_outcomes_file_ausente_exit1() {
  cd "$TMPDIR_TEST" || return 1
  _write_tasks_md <<'EOF'
## FASE 1 - Fase Um `[A]`

### 1.1 Tarefa `[M]`

- [x] 1.1.1 sub um
EOF
  assert_exit 1 "$SCRIPT" items --feature demo --outcomes-file "$TMPDIR_TEST/nao-existe.tsv" || return 1
}

scenario_items_epic_task_subtask_basico() {
  cd "$TMPDIR_TEST" || return 1
  _write_spec_md <<'EOF'
# Feature Specification: Demo Feature Title

**Feature**: `demo`
EOF
  _write_tasks_md <<'EOF'
## FASE 1 - Fase Um `[A]`

### 1.1 Tarefa exemplo `[M]`

Ref: nada

- [x] 1.1.1 primeira sub
- [ ] 1.1.2 segunda sub
EOF
  assert_exit 0 "$SCRIPT" items --feature demo || return 1
  assert_stdout_match '^demo	epic			in_progress	Demo Feature Title$' || return 1
  assert_stdout_match '^1\.1	task	FASE 1 - Fase Um	M	in_progress	Tarefa exemplo$' || return 1
  assert_stdout_match '^1\.1\.1	subtask	FASE 1 - Fase Um		pass	primeira sub$' || return 1
  assert_stdout_match '^1\.1\.2	subtask	FASE 1 - Fase Um		pending	segunda sub$' || return 1
}

scenario_items_epic_titulo_sem_spec_cai_para_feature() {
  cd "$TMPDIR_TEST" || return 1
  _write_tasks_md <<'EOF'
## FASE 1 - Fase Um `[A]`

### 1.1 Tarefa `[M]`

- [x] 1.1.1 sub um
EOF
  assert_exit 0 "$SCRIPT" items --feature demo || return 1
  assert_stdout_match '^demo	epic			pass	demo$' || return 1
}

scenario_items_subtask_local_state_4_checkboxes() {
  cd "$TMPDIR_TEST" || return 1
  _write_tasks_md <<'EOF'
## FASE 1 - Fase Um `[A]`

### 1.1 Tarefa `[M]`

- [ ] 1.1.1 pendente
- [~] 1.1.2 andamento
- [x] 1.1.3 concluida
- [!] 1.1.4 bloqueada
EOF
  assert_exit 0 "$SCRIPT" items --feature demo || return 1
  assert_stdout_match '^1\.1\.1	subtask	FASE 1 - Fase Um		pending	pendente$' || return 1
  assert_stdout_match '^1\.1\.2	subtask	FASE 1 - Fase Um		in_progress	andamento$' || return 1
  assert_stdout_match '^1\.1\.3	subtask	FASE 1 - Fase Um		pass	concluida$' || return 1
  assert_stdout_match '^1\.1\.4	subtask	FASE 1 - Fase Um		fail	bloqueada$' || return 1
}

scenario_items_task_sem_subtask_pending() {
  cd "$TMPDIR_TEST" || return 1
  _write_tasks_md <<'EOF'
## FASE 1 - Fase Um `[A]`

### 1.1 Tarefa sem subtasks ainda `[M]`

Ref: nada
EOF
  assert_exit 0 "$SCRIPT" items --feature demo || return 1
  assert_stdout_match '^1\.1	task	FASE 1 - Fase Um	M	pending	Tarefa sem subtasks ainda$' || return 1
}

scenario_items_task_todas_pass_vira_pass() {
  cd "$TMPDIR_TEST" || return 1
  _write_tasks_md <<'EOF'
## FASE 1 - Fase Um `[A]`

### 1.1 Tarefa `[M]`

- [x] 1.1.1 um
- [x] 1.1.2 dois
EOF
  assert_exit 0 "$SCRIPT" items --feature demo || return 1
  assert_stdout_match '^1\.1	task	FASE 1 - Fase Um	M	pass	Tarefa$' || return 1
}

scenario_items_task_mistura_pass_pending_vira_in_progress() {
  cd "$TMPDIR_TEST" || return 1
  _write_tasks_md <<'EOF'
## FASE 1 - Fase Um `[A]`

### 1.1 Tarefa `[M]`

- [x] 1.1.1 um
- [ ] 1.1.2 dois
EOF
  assert_exit 0 "$SCRIPT" items --feature demo || return 1
  assert_stdout_match '^1\.1	task	FASE 1 - Fase Um	M	in_progress	Tarefa$' || return 1
}

scenario_items_task_qualquer_fail_vira_fail() {
  cd "$TMPDIR_TEST" || return 1
  _write_tasks_md <<'EOF'
## FASE 1 - Fase Um `[A]`

### 1.1 Tarefa `[M]`

- [x] 1.1.1 um
- [!] 1.1.2 dois
EOF
  assert_exit 0 "$SCRIPT" items --feature demo || return 1
  assert_stdout_match '^1\.1	task	FASE 1 - Fase Um	M	fail	Tarefa$' || return 1
}

scenario_items_outcome_tem_precedencia_sobre_checkboxes() {
  cd "$TMPDIR_TEST" || return 1
  _write_tasks_md <<'EOF'
## FASE 1 - Fase Um `[A]`

### 1.1 Tarefa `[M]`

- [x] 1.1.1 um
- [x] 1.1.2 dois
EOF
  printf '1.1\tfail\n' > "$TMPDIR_TEST/outcomes.tsv"
  assert_exit 0 "$SCRIPT" items --feature demo --outcomes-file "$TMPDIR_TEST/outcomes.tsv" || return 1
  assert_stdout_match '^1\.1	task	FASE 1 - Fase Um	M	fail	Tarefa$' || return 1
}

scenario_items_stage_aplica_stage_status_no_epic() {
  cd "$TMPDIR_TEST" || return 1
  _write_tasks_md <<'EOF'
## FASE 1 - Fase Um `[A]`

### 1.1 Tarefa `[M]`

- [ ] 1.1.1 um
EOF
  mkdir -p "$TMPDIR_TEST/.claude/cstk-jira"
  printf 'stage_status.plan=Done\n' > "$TMPDIR_TEST/.claude/cstk-jira/config"
  assert_exit 0 "$SCRIPT" items --feature demo --stage plan || return 1
  assert_stdout_match '^demo	epic			Done	demo$' || return 1
}

scenario_items_epic_sem_stage_agrega_por_tasks() {
  cd "$TMPDIR_TEST" || return 1
  _write_tasks_md <<'EOF'
## FASE 1 - Fase Um `[A]`

### 1.1 Tarefa um `[M]`

- [x] 1.1.1 um

### 1.2 Tarefa dois `[M]`

- [x] 1.2.1 um
EOF
  assert_exit 0 "$SCRIPT" items --feature demo || return 1
  assert_stdout_match '^demo	epic			pass	demo$' || return 1
}

scenario_items_subtask_continuacao_multilinhas_concatenada() {
  cd "$TMPDIR_TEST" || return 1
  _write_tasks_md <<'EOF'
## FASE 1 - Fase Um `[A]`

### 1.1 Tarefa `[M]`

- [x] 1.1.1 primeira linha da descricao
      segunda linha continuando
      terceira linha finalizando
- [ ] 1.1.2 sub isolada
EOF
  assert_exit 0 "$SCRIPT" items --feature demo || return 1
  assert_stdout_match '^1\.1\.1	subtask	FASE 1 - Fase Um		pass	primeira linha da descricao segunda linha continuando terceira linha finalizando$' || return 1
  assert_stdout_match '^1\.1\.2	subtask	FASE 1 - Fase Um		pending	sub isolada$' || return 1
}

scenario_items_secoes_pos_tasks_nao_vazam() {
  cd "$TMPDIR_TEST" || return 1
  _write_tasks_md <<'EOF'
## FASE 1 - Fase Um `[A]`

### 1.1 Tarefa `[M]`

- [x] 1.1.1 sub um

---

## Matriz de Dependencias

```mermaid
flowchart TD
    F1[Fase 1]
```

## Resumo Quantitativo

| Fase | Tarefas |
|------|---------|
| 1 | 1 |
EOF
  assert_exit 0 "$SCRIPT" items --feature demo || return 1
  assert_stdout_not_contains "Matriz de Dependencias" || return 1
  assert_stdout_not_contains "flowchart" || return 1
  assert_stdout_not_contains "Resumo Quantitativo" || return 1
  _nlines=$(printf '%s\n' "$_CAPTURED_STDOUT" | wc -l | tr -d ' ')
  [ "$_nlines" -eq 3 ] || { _fail "line_count" "esperado 3 linhas (epic+task+subtask), obtido $_nlines"; return 1; }
}

run_all_scenarios
