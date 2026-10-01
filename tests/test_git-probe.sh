#!/bin/sh
# test_git-probe.sh — cobre
# plugins/cstk/skills/reconcile-docs/scripts/git-probe.sh (carve-out 1.1.0).
#
# Ref: docs/specs/code-reconciliation/contracts/cli-invocation.md §7
#      docs/specs/code-reconciliation/quickstart.md Scenario 9; FR-016

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"
. "$TESTS_ROOT/lib/reconcile-fixture.sh"

SKILL_SCRIPTS="$REPO_ROOT/plugins/cstk/skills/reconcile-docs/scripts"
SCRIPT="$SKILL_SCRIPTS/git-probe.sh"
TAB=$(printf '\t')
GITC="git -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false"

_gp_setup() {
  _GP_D=$(rd_make_fixture "${1:-git}") || return 2
  trap 'rm -rf "$_GP_D"; _cleanup_tmpdir' EXIT INT TERM
}
_gp_exit() { [ "$_CAPTURED_EXIT" = "$1" ] || { _fail "exit" "esperado $1, obtido $_CAPTURED_EXIT"; return 1; }; }
_gp_last() { printf '%s\n' "$_CAPTURED_STDOUT" | sed -n '$p'; }

scenario_status_limpo_termina_com_status_ok() {
  _gp_setup || return 2
  capture sh "$SCRIPT" status --root "$_GP_D"
  _gp_exit 0 || return 1
  [ "$_CAPTURED_STDOUT" = "STATUS${TAB}ok" ] || { _fail "stdout" "esperado so STATUS ok"; return 1; }
}

scenario_status_lista_alterados_e_untracked_ordenados() {
  _gp_setup || return 2
  printf 'x\n' >> "$_GP_D/cli/lib/run.sh"
  mkdir -p "$_GP_D/novo"; printf 'a\n' > "$_GP_D/novo/b.md"; printf 'a\n' > "$_GP_D/novo/a.md"
  capture sh "$SCRIPT" status --root "$_GP_D"
  _gp_exit 0 || return 1
  assert_stdout_contains " M cli/lib/run.sh" || return 1
  assert_stdout_contains "?? novo/a.md" || return 1
  [ "$(_gp_last)" = "STATUS${TAB}ok" ] || { _fail "status" "ultima linha deve ser STATUS ok"; return 1; }
  _a=$(printf '%s\n' "$_CAPTURED_STDOUT" | grep -n 'novo/a.md' | cut -d: -f1)
  _b=$(printf '%s\n' "$_CAPTURED_STDOUT" | grep -n 'novo/b.md' | cut -d: -f1)
  [ "$_a" -lt "$_b" ] || { _fail "ordem" "saida deve ser ordenada"; return 1; }
}

scenario_status_nao_altera_o_repositorio() {
  _gp_setup || return 2
  printf 'x\n' >> "$_GP_D/cli/lib/run.sh"
  _b=$(cd "$_GP_D" && find .git -type f | LC_ALL=C sort | cksum)
  capture sh "$SCRIPT" status --root "$_GP_D"
  _a=$(cd "$_GP_D" && find .git -type f | LC_ALL=C sort | cksum)
  [ "$_b" = "$_a" ] || { _fail "read-only" "arquivos de .git mudaram"; return 1; }
}

scenario_changed_since_caminhos_apos_ultimo_commit_da_feature() {
  _gp_setup || return 2
  printf 'x\n' >> "$_GP_D/cli/lib/run.sh"
  printf 'y\n' > "$_GP_D/cli/lib/novo.sh"
  (cd "$_GP_D" && git add cli && $GITC commit -q -m "codigo") >/dev/null 2>&1
  capture sh "$SCRIPT" changed-since --root "$_GP_D" --feature-dir docs/specs/alpha
  _gp_exit 0 || return 1
  assert_stdout_contains "cli/lib/run.sh" || return 1
  assert_stdout_contains "cli/lib/novo.sh" || return 1
  [ "$(_gp_last)" = "STATUS${TAB}ok" ] || { _fail "status" "ultima linha deve ser STATUS ok"; return 1; }
}

scenario_changed_since_vazio_quando_nada_mudou() {
  _gp_setup || return 2
  capture sh "$SCRIPT" changed-since --root "$_GP_D" --feature-dir docs/specs/alpha
  _gp_exit 0 || return 1
  [ "$_CAPTURED_STDOUT" = "STATUS${TAB}ok" ] || { _fail "stdout" "esperado so STATUS ok"; return 1; }
}

scenario_changed_since_nao_lista_mudancas_anteriores_ao_commit_dos_docs() {
  _gp_setup || return 2
  printf 'antes\n' >> "$_GP_D/cli/lib/run.sh"
  (cd "$_GP_D" && $GITC commit -qam "codigo antes") >/dev/null 2>&1
  printf 'doc\n' >> "$_GP_D/docs/specs/alpha/spec.md"
  (cd "$_GP_D" && $GITC commit -qam "doc depois") >/dev/null 2>&1
  capture sh "$SCRIPT" changed-since --root "$_GP_D" --feature-dir docs/specs/alpha
  assert_stdout_not_contains "cli/lib/run.sh" || return 1
}

scenario_repo_sem_commits_so_status_ok() {
  _gp_setup nogit || return 2
  (cd "$_GP_D" && git init -q .) >/dev/null 2>&1
  capture sh "$SCRIPT" changed-since --root "$_GP_D" --feature-dir docs/specs/alpha
  _gp_exit 0 || return 1
  [ "$_CAPTURED_STDOUT" = "STATUS${TAB}ok" ] || { _fail "stdout" "esperado so STATUS ok"; return 1; }
}

scenario_fora_de_repositorio_status_no_git() {
  _gp_setup nogit || return 2
  capture sh "$SCRIPT" status --root "$_GP_D"
  _gp_exit 0 || return 1
  [ "$_CAPTURED_STDOUT" = "STATUS${TAB}no-git" ] || { _fail "stdout" "esperado so STATUS no-git, obtido: $_CAPTURED_STDOUT"; return 1; }
  capture sh "$SCRIPT" changed-since --root "$_GP_D" --feature-dir docs/specs/alpha
  _gp_exit 0 || return 1
  [ "$_CAPTURED_STDOUT" = "STATUS${TAB}no-git" ] || { _fail "stdout" "esperado so STATUS no-git"; return 1; }
}

scenario_path_sem_git_status_no_git() {
  _gp_setup || return 2
  # PATH so com os utilitarios POSIX necessarios, sem git.
  _bin="$_GP_D/.nogit-bin"; mkdir -p "$_bin"
  for _t in sh cat tr sed sort grep awk cut wc head tail dirname pwd; do
    _p=$(command -v "$_t" 2>/dev/null || true)
    case "$_p" in /*) ln -s "$_p" "$_bin/$_t" ;; esac
  done
  _shbin=$(command -v sh)
  capture env -i PATH="$_bin" "$_shbin" "$SCRIPT" status --root "$_GP_D"
  _gp_exit 0 || return 1
  [ "$_CAPTURED_STDOUT" = "STATUS${TAB}no-git" ] || { _fail "stdout" "esperado so STATUS no-git, obtido: $_CAPTURED_STDOUT"; return 1; }
}

scenario_uso_incorreto_e_raiz_inexistente() {
  _gp_setup || return 2
  capture sh "$SCRIPT"; _gp_exit 2 || return 1
  capture sh "$SCRIPT" nope --root "$_GP_D"; _gp_exit 2 || return 1
  capture sh "$SCRIPT" status; _gp_exit 2 || return 1
  capture sh "$SCRIPT" changed-since --root "$_GP_D"; _gp_exit 2 || return 1
  capture sh "$SCRIPT" status --root "$_GP_D/nao-existe"; _gp_exit 1 || return 1
  capture sh "$SCRIPT" changed-since --root "$_GP_D" --feature-dir ../fora; _gp_exit 2 || return 1
}

# dec-035 (1.5): em projeto SEM git a skill recusa gravar — `can-write` e a
# pre-condicao deterministica; o chamador trata exit != 0 como recusa (dry-run forcado).
scenario_can_write_em_repositorio_git_permite() {
  _gp_setup || return 2
  capture sh "$SCRIPT" can-write --root "$_GP_D"
  _gp_exit 0 || return 1
  [ "$_CAPTURED_STDOUT" = "WRITE${TAB}allowed" ] || { _fail "stdout" "esperado WRITE allowed, obtido: $_CAPTURED_STDOUT"; return 1; }
}

scenario_can_write_fora_de_repositorio_recusa() {
  _gp_setup nogit || return 2
  capture sh "$SCRIPT" can-write --root "$_GP_D"
  _gp_exit 3 || return 1
  [ "$_CAPTURED_STDOUT" = "WRITE${TAB}denied-no-git" ] || { _fail "stdout" "esperado WRITE denied-no-git, obtido: $_CAPTURED_STDOUT"; return 1; }
}

scenario_can_write_sem_git_no_path_recusa() {
  _gp_setup || return 2
  _bin="$_GP_D/.nogit-bin"; mkdir -p "$_bin"
  for _t in sh cat tr sed sort grep awk cut wc head tail dirname pwd; do
    _p=$(command -v "$_t" 2>/dev/null || true)
    case "$_p" in /*) ln -s "$_p" "$_bin/$_t" ;; esac
  done
  _shbin=$(command -v sh)
  capture env -i PATH="$_bin" "$_shbin" "$SCRIPT" can-write --root "$_GP_D"
  _gp_exit 3 || return 1
  [ "$_CAPTURED_STDOUT" = "WRITE${TAB}denied-no-git" ] || { _fail "stdout" "esperado WRITE denied-no-git, obtido: $_CAPTURED_STDOUT"; return 1; }
}

scenario_can_write_nao_altera_o_repositorio_e_valida_uso() {
  _gp_setup || return 2
  _b=$(cd "$_GP_D" && find .git -type f | LC_ALL=C sort | cksum)
  capture sh "$SCRIPT" can-write --root "$_GP_D"
  _a=$(cd "$_GP_D" && find .git -type f | LC_ALL=C sort | cksum)
  [ "$_b" = "$_a" ] || { _fail "read-only" "arquivos de .git mudaram"; return 1; }
  capture sh "$SCRIPT" can-write; _gp_exit 2 || return 1
  capture sh "$SCRIPT" can-write --root "$_GP_D/nao-existe"; _gp_exit 1 || return 1
}

# 3.4.2/3.4.5 — `git` confinado a git-probe.sh; so subcomandos de leitura; fsmonitor off.
scenario_git_confinado_a_este_arquivo() {
  for _f in "$SKILL_SCRIPTS"/*.sh; do
    [ "$_f" = "$SCRIPT" ] && continue
    if grep -vE '^[[:space:]]*#' "$_f" | grep -Eq '(^|[^[:alnum:]_-])git([^[:alnum:]_-]|$)'; then
      _fail "confinamento" "$(basename "$_f") invoca git fora de git-probe.sh"
      return 1
    fi
  done
}

scenario_git_so_subcomandos_de_leitura_com_fsmonitor_off() {
  _code=$(grep -vE '^[[:space:]]*#' "$SCRIPT")
  printf '%s\n' "$_code" | grep -q 'core.fsmonitor=false' || { _fail "fsmonitor" "core.fsmonitor=false ausente"; return 1; }
  # Toda invocacao passa por _gp_git; subcomandos permitidos: rev-parse, status, log.
  printf '%s\n' "$_code" | grep -E '_gp_git ' | grep -vE '_gp_git \(\)|_gp_git (rev-parse|status|log)( |$)' \
    | grep -q . && { _fail "subcomandos" "subcomando fora de rev-parse/status/log"; return 1; }
  if printf '%s\n' "$_code" | grep -Eq '(^|[^[:alnum:]_])git +(add|commit|checkout|reset|restore|clean|stash|push|pull|fetch|config|hook|rm|mv|tag|branch|merge|rebase|apply|am|cherry-pick|revert|init|clone)( |$)'; then
    _fail "subcomandos" "subcomando de escrita encontrado"; return 1
  fi
  return 0
}

scenario_sem_bashismos() {
  capture sh -n "$SCRIPT"; _gp_exit 0 || return 1
  if command -v dash >/dev/null 2>&1; then capture dash -n "$SCRIPT"; _gp_exit 0 || return 1; fi
  if command -v checkbashisms >/dev/null 2>&1; then capture checkbashisms "$SCRIPT"; _gp_exit 0 || return 1; fi
}

run_all_scenarios
