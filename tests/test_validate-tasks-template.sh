#!/bin/sh
# test_validate-tasks-template.sh —
# cobre plugins/cstk/skills/create-tasks/scripts/validate-tasks-template.sh.
#
# Contrato:
#   validate-tasks-template.sh FILE [--phase-prefix PREFIX] [--config CONFIG_JSON]
#     Emite linhas FINDING|<severity>|<code>|<msg> e um RESULT|<file>|critical=N|warning=M.
#     severity ∈ {critical, warning}.
#     Exit: 0 conformante; 1 drift (>=1 finding); 2 uso/arquivo.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/create-tasks/scripts/validate-tasks-template.sh"

# ==== documento conformante -> exit 0, sem findings ====

scenario_conformante_passa_limpo() {
  fixture "tasks-md" || return 2
  assert_exit 0 sh "$SCRIPT" "$TMPDIR_TEST/conformant.md" || return 1
  assert_stdout_contains "critical=0|warning=0" || return 1
  assert_stdout_not_contains "FINDING|" || return 1
}

# ==== documento vazio -> 3 critical + 6 warning, exit 1 ====

scenario_vazio_dispara_tudo() {
  fixture "tasks-md" || return 2
  assert_exit 1 sh "$SCRIPT" "$TMPDIR_TEST/empty.md" || return 1
  assert_stdout_contains "FINDING|critical|no-phase|" || return 1
  assert_stdout_contains "FINDING|critical|no-checkbox|" || return 1
  assert_stdout_contains "FINDING|critical|no-criticality|" || return 1
  assert_stdout_contains "critical=3|warning=6" || return 1
}

# ==== sem checkbox -> critical no-checkbox ====

scenario_sem_checkbox_e_critical() {
  fixture "tasks-md" || return 2
  # Remove os checkboxes do conformant, preservando o resto.
  grep -v '^- \[' "$TMPDIR_TEST/conformant.md" > "$TMPDIR_TEST/sem-cb.md"
  assert_exit 1 sh "$SCRIPT" "$TMPDIR_TEST/sem-cb.md" || return 1
  assert_stdout_contains "FINDING|critical|no-checkbox|" || return 1
}

# ==== sem prefixo de fase -> critical no-phase ====

scenario_sem_fase_e_critical() {
  fixture "tasks-md" || return 2
  # Troca "## FASE" por "## Etapa" — o prefixo default (FASE) deixa de casar.
  sed 's/^## FASE/## Etapa/' "$TMPDIR_TEST/conformant.md" > "$TMPDIR_TEST/sem-fase.md"
  assert_exit 1 sh "$SCRIPT" "$TMPDIR_TEST/sem-fase.md" || return 1
  assert_stdout_contains "FINDING|critical|no-phase|" || return 1
}

# ==== sem tag de criticidade -> critical no-criticality ====

scenario_sem_criticidade_e_critical() {
  fixture "tasks-md" || return 2
  # Remove as tags `[A]`/`[C]` dos headings de tarefa.
  sed -E 's/ `\[[A-Z]+\]`//' "$TMPDIR_TEST/conformant.md" > "$TMPDIR_TEST/sem-crit.md"
  assert_exit 1 sh "$SCRIPT" "$TMPDIR_TEST/sem-crit.md" || return 1
  assert_stdout_contains "FINDING|critical|no-criticality|" || return 1
}

# ==== so secoes de metadados ausentes -> warning, nunca critical ====

scenario_secoes_ausentes_sao_warning() {
  fixture "tasks-md" || return 2
  # with-phases tem FASE + checkbox + criticidade, mas sem legendas/matriz/escopo.
  assert_exit 1 sh "$SCRIPT" "$TMPDIR_TEST/with-phases-tasks.md" || return 1
  assert_stdout_contains "critical=0|warning=6" || return 1
  assert_stdout_contains "FINDING|warning|no-dependency-matrix|" || return 1
  assert_stdout_contains "FINDING|warning|no-scope-excluded|" || return 1
  assert_stdout_not_contains "FINDING|critical|" || return 1
}

# ==== prefixo de fase customizado via --phase-prefix ====

scenario_prefixo_customizado_flag() {
  fixture "tasks-md" || return 2
  sed 's/^## FASE/## ETAPA/' "$TMPDIR_TEST/conformant.md" > "$TMPDIR_TEST/etapa.md"
  # Sem o override, "## ETAPA" nao casa o default FASE -> no-phase.
  assert_exit 1 sh "$SCRIPT" "$TMPDIR_TEST/etapa.md" || return 1
  assert_stdout_contains "FINDING|critical|no-phase|" || return 1
  # Com o override, passa a casar -> sem no-phase.
  assert_exit 0 sh "$SCRIPT" "$TMPDIR_TEST/etapa.md" --phase-prefix ETAPA || return 1
  assert_stdout_not_contains "no-phase" || return 1
}

# ==== prefixo de fase lido do --config (sem jq) ====

scenario_prefixo_via_config() {
  fixture "tasks-md" || return 2
  sed 's/^## FASE/## ETAPA/' "$TMPDIR_TEST/conformant.md" > "$TMPDIR_TEST/etapa.md"
  printf '{\n  "phase_prefix": "ETAPA"\n}\n' > "$TMPDIR_TEST/cfg.json"
  assert_exit 0 sh "$SCRIPT" "$TMPDIR_TEST/etapa.md" --config "$TMPDIR_TEST/cfg.json" || return 1
  assert_stdout_not_contains "no-phase" || return 1
}

# ==== uso incorreto e arquivo inexistente -> exit 2 ====

scenario_uso_e_arquivo() {
  assert_exit 2 sh "$SCRIPT" || return 1
  assert_stderr_contains "Uso:" || return 1
  assert_exit 2 sh "$SCRIPT" "/caminho/inexistente.md" || return 1
  assert_stderr_contains "nao encontrado" || return 1
  assert_exit 2 sh "$SCRIPT" "$TMPDIR_TEST/x" --opcao-invalida || return 1
}

# ==== read-only: nao toca o working tree ====

scenario_sem_efeito_colateral() {
  fixture "tasks-md" || return 2
  sh "$SCRIPT" "$TMPDIR_TEST/conformant.md" >/dev/null 2>&1 || true
  assert_no_side_effect || return 1
}

run_all_scenarios
