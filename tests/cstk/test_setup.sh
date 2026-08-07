#!/bin/sh
# test_setup.sh — cobre cli/lib/setup.sh (feature cstk-setup, wizard guiado
# de configuracao: hooks, backend de estado, MCP, telemetria).
#
# Cenarios:
#   1  scenario_dispatch_setup_wiring (task 1.1.5) — wiring do dispatcher:
#      `setup` existe no case generico, no help geral, no help por
#      subcomando e nas 2 listas de "Comandos validos" das mensagens de
#      erro. Segue o precedente de `scenario_help_lista_hooks` /
#      `scenario_help_hooks_aponta_doc` em test_cstk-main.sh (5.27.0):
#      o que se testa aqui e o WIRING — o comando existe, aparece no help
#      e nao cai no ramo "comando desconhecido" — independente de
#      cli/lib/setup.sh ja ter a implementacao completa da area.
#   2  scenario_git_root_gate (task 1.2.5, quickstart Scenario 8, FR-011) —
#      diretorio sem `.git` recusa com exit 3 e zero escrita; worktree
#      (`.git` arquivo-ponteiro) e aceito.
#   3  scenario_non_interactive_no_flag_fails_fast (task 1.2.6, quickstart
#      Scenario 6, FR-007) — sem TTY e sem --dry-run/--yes, falha imediata
#      exit 3 apontando as duas flags, sem bloquear esperando input.
#   4  scenario_dry_run_precedes_yes (task 1.3.4, quickstart Scenario 5,
#      FR-006) — `--dry-run --yes` juntas => mode=preview, zero escrita.
#   5  scenario_unknown_flag_usage_error (task 1.3.5) — flag desconhecida
#      => exit 2.
#   6  scenario_catalog_flag_rejected (task 1.3.6, quickstart Scenario 16,
#      FR-018) — `cstk setup --catalog /qualquer/dir` => exit 2 (nenhuma
#      flag de override de catalogo existe neste subcomando).
#
# Ref: docs/specs/cstk-setup/tasks.md FASE 1; contracts/cli-setup.md §1.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CSTK="$REPO_ROOT/cli/cstk"
CSTK_LIB="$REPO_ROOT/cli/lib"
export CSTK_LIB

# Helper: cria repo git limpo em $1 (DIR), commit inicial vazio, branch main.
# Mesmo padrao de tests/cstk/test_session.sh::_make_repo.
_make_repo() {
  _mr_dir=$1
  mkdir -p "$_mr_dir"
  ( cd "$_mr_dir" \
    && git init -q -b main \
    && git config user.email test@example.com \
    && git config user.name "Test" \
    && git commit -q --allow-empty -m "init" )
}

# ==== 1.1.5 wiring do dispatcher ====

scenario_dispatch_setup_wiring() {
  # (a) aparece no help geral
  assert_exit 0 sh "$CSTK" --help || return 1
  assert_stdout_contains "setup" || return 1

  # (b) `cstk help setup` aponta para o contrato
  assert_exit 0 sh "$CSTK" help setup || return 1
  assert_stdout_contains "setup" || return 1
  assert_stdout_contains "cli-setup.md" || return 1

  # (c) `cstk setup --help` chega no ramo generico do dispatcher — nunca
  # "comando desconhecido" (exit 2), esteja setup.sh ja implementado ou
  # ainda no estagio de scaffold ("nao implementado ainda", exit 1).
  capture sh "$CSTK" setup --help
  if [ "$_CAPTURED_EXIT" = "2" ]; then
    _fail "scenario_dispatch_setup_wiring" \
      "cstk setup --help caiu no ramo de comando desconhecido (exit 2)"
    return 1
  fi
  case "$_CAPTURED_STDERR" in
    *"comando desconhecido"*)
      _fail "scenario_dispatch_setup_wiring" \
        "stderr contem 'comando desconhecido': $_CAPTURED_STDERR"
      return 1
      ;;
  esac

  # (d) checagem estatica dos 4 pontos de edicao em cli/cstk
  grep -q "setup.*Wizard guiado" "$CSTK" || {
    _fail "scenario_dispatch_setup_wiring" "COMANDOS: entrada de setup ausente"
    return 1
  }
  grep -qE '^ *setup\)$' "$CSTK" || {
    _fail "scenario_dispatch_setup_wiring" "case de help por subcomando: setup) ausente"
    return 1
  }
  grep -qE '\|setup\)$' "$CSTK" || {
    _fail "scenario_dispatch_setup_wiring" "case generico do dispatch: |setup) ausente"
    return 1
  }
  _n_validos=$(grep -c "usage, setup, 00c" "$CSTK") || _n_validos=0
  if [ "$_n_validos" -lt 2 ]; then
    _fail "scenario_dispatch_setup_wiring" \
      "esperava setup nas 2 listas 'Comandos validos', achou $_n_validos"
    return 1
  fi
}

# ==== 1.2.5 gate de raiz de repo git (FR-011, quickstart Scenario 8) ====

scenario_git_root_gate() {
  # (a) diretorio SEM .git -> exit 3, diagnostico claro, zero escrita
  _bare="$TMPDIR_TEST/no-git-dir"
  mkdir -p "$_bare"
  capture sh "$CSTK" setup --project-path "$_bare" --yes
  if [ "$_CAPTURED_EXIT" != "3" ]; then
    _fail "scenario_git_root_gate" \
      "esperado exit 3 sem .git, obtido $_CAPTURED_EXIT (stderr: $_CAPTURED_STDERR)"
    return 1
  fi
  _n_entries=$(find "$_bare" -mindepth 1 | wc -l | tr -d ' ')
  if [ "$_n_entries" != "0" ]; then
    _fail "scenario_git_root_gate" \
      "diretorio sem .git nao deveria receber escrita, achou $_n_entries entradas"
    return 1
  fi

  # (b) worktree real (.git e arquivo-ponteiro, nao diretorio) -> aceito,
  # ou seja, NAO recusado pela pre-condicao FR-011 (segue adiante e
  # retorna 0 — FASE 1 ainda nao implementa as areas).
  _src="$TMPDIR_TEST/repo-wt-gate"
  _make_repo "$_src"
  _wt_path="$( cd "$TMPDIR_TEST" && pwd -P )/repo-wt-gate-feat"
  ( cd "$_src" && git worktree add -q -b feat-gate "$_wt_path" ) || {
    _fail "scenario_git_root_gate" "git worktree add falhou"
    return 1
  }
  [ -f "$_wt_path/.git" ] || {
    _fail "scenario_git_root_gate" "pre-condicao do teste falhou: .git da worktree nao e arquivo"
    return 1
  }
  assert_exit 0 sh "$CSTK" setup --project-path "$_wt_path" --dry-run || return 1
}

# ==== 1.2.6 falha rapida sem TTY e sem --dry-run/--yes (FR-007, quickstart
# Scenario 6) ====

scenario_non_interactive_no_flag_fails_fast() {
  _repo="$TMPDIR_TEST/repo-no-tty"
  _make_repo "$_repo"

  # stdin de /dev/null simula ausencia de TTY sem bloquear o test runner.
  capture sh -c 'sh "$1" setup --project-path "$2" < /dev/null' _ "$CSTK" "$_repo"
  if [ "$_CAPTURED_EXIT" != "3" ]; then
    _fail "scenario_non_interactive_no_flag_fails_fast" \
      "esperado exit 3, obtido $_CAPTURED_EXIT (stderr: $_CAPTURED_STDERR)"
    return 1
  fi
  case "$_CAPTURED_STDERR" in
    *"--dry-run"*"--yes"*|*"--yes"*"--dry-run"*) : ;;
    *)
      _fail "scenario_non_interactive_no_flag_fails_fast" \
        "stderr nao aponta --dry-run/--yes: $_CAPTURED_STDERR"
      return 1
      ;;
  esac
}

# ==== 1.3.4 --dry-run precede --yes (FR-006, quickstart Scenario 5) ====

scenario_dry_run_precedes_yes() {
  _repo="$TMPDIR_TEST/repo-dryrun-yes"
  _make_repo "$_repo"
  _before=$(find "$_repo" -mindepth 1 | sort)

  assert_exit 0 sh "$CSTK" setup --project-path "$_repo" --dry-run --yes || return 1
  # Diagnosticos de modo vao para stderr (Constitution II: dados em stdout,
  # erros/avisos em stderr) — cli/lib/common.sh::log_info.
  assert_stderr_contains "mode=preview" || return 1

  _after=$(find "$_repo" -mindepth 1 | sort)
  if [ "$_before" != "$_after" ]; then
    _fail "scenario_dry_run_precedes_yes" \
      "esperava zero escrita com --dry-run --yes; arvore mudou"
    return 1
  fi

  # Ordem invertida (--yes --dry-run) deve dar o mesmo resultado —
  # precedencia e por PRESENCA da flag, nao por posicao.
  assert_exit 0 sh "$CSTK" setup --project-path "$_repo" --yes --dry-run || return 1
  assert_stderr_contains "mode=preview" || return 1
}

# ==== 1.3.5 flag desconhecida => exit 2 (uso incorreto) ====

scenario_unknown_flag_usage_error() {
  capture sh "$CSTK" setup --project-path "$PWD" --bogus-flag
  if [ "$_CAPTURED_EXIT" != "2" ]; then
    _fail "scenario_unknown_flag_usage_error" \
      "esperado exit 2, obtido $_CAPTURED_EXIT (stderr: $_CAPTURED_STDERR)"
    return 1
  fi
  case "$_CAPTURED_STDERR" in
    *"flag desconhecida"*) : ;;
    *)
      _fail "scenario_unknown_flag_usage_error" \
        "stderr nao menciona 'flag desconhecida': $_CAPTURED_STDERR"
      return 1
      ;;
  esac
}

# ==== 1.3.6 --catalog e rejeitada — FR-018, ausencia deliberada
# (quickstart Scenario 16) ====

scenario_catalog_flag_rejected() {
  # Nenhuma flag de override de catalogo existe neste subcomando (FR-018)
  # — --catalog cai no mesmo ramo generico de "flag desconhecida" que
  # qualquer outra flag nao reconhecida, exit 2.
  assert_exit 2 sh "$CSTK" setup --catalog /qualquer/dir || return 1

  # Confirmacao estatica: setup.sh nunca implementa um case-arm para
  # --catalog (mencoes em comentario explicando a ausencia deliberada,
  # como esta propria linha do header do arquivo, nao contam).
  if grep -qE -- '--catalog\)' "$CSTK_LIB/setup.sh"; then
    _fail "scenario_catalog_flag_rejected" \
      "cli/lib/setup.sh implementa um case-arm --catalog) — FR-018 exige ausencia deliberada"
    return 1
  fi
  return 0
}

run_all_scenarios
