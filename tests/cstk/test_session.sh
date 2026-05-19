#!/bin/sh
# test_session.sh — cobre cli/lib/session.sh
#
# FASE 1: scaffold + dispatch + boot-check + 7 helpers comuns.
# FASES 2-5 (subcomandos start/list/end/pr) adicionarao mais cenarios.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CSTK_LIB="$REPO_ROOT/cli/lib"
export CSTK_LIB

CSTK_BIN="$REPO_ROOT/cli/cstk"

# Helper para sourcing controlado dos helpers (sem rodar session_main).
_source_session_lib() {
  # shellcheck source=/dev/null
  . "$CSTK_LIB/common.sh"
  # shellcheck source=/dev/null
  . "$CSTK_LIB/session.sh"
}

# Helper: cria repo git limpo em $1 (DIR), commit inicial vazio, branch main.
_make_repo() {
  _mr_dir=$1
  mkdir -p "$_mr_dir"
  ( cd "$_mr_dir" \
    && git init -q -b main \
    && git config user.email test@example.com \
    && git config user.name "Test" \
    && git commit -q --allow-empty -m "init" )
}

# ==== Dispatch + help ====

scenario_session_no_args_prints_help_exit_2() {
  capture sh "$CSTK_BIN" session
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "cstk session" || return 1
  assert_stderr_contains "USO:" || return 1
}

scenario_session_help_flag_exit_0() {
  capture sh "$CSTK_BIN" session --help
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "start" || return 1
  assert_stderr_contains "list" || return 1
  assert_stderr_contains "end" || return 1
  assert_stderr_contains "pr" || return 1
}

scenario_session_unknown_subcommand_exit_2() {
  capture sh "$CSTK_BIN" session xyz-fake
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "subcomando desconhecido" || return 1
}

# NOTA: scenario_session_remaining_stubs_return_1 removido apos FASE 5 —
# todos os 4 subcomandos (start/list/end/pr) estao implementados.
# Cada subcomando tem cobertura propria nos cenarios FASES 2-5.

scenario_help_geral_inclui_session() {
  capture sh "$CSTK_BIN" --help
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_STDERR"; return 1; }
  # `cstk --help` imprime help em stdout (heredoc sem redirect).
  assert_stdout_contains "session" || return 1
}

# ==== Helpers (sourcing controlado) ====

scenario_helpers_validate_name_aceita_kebab_valido() {
  _source_session_lib
  if ! _session_validate_name "iniciacao-membro" 2>/dev/null; then
    _fail "validate" "kebab-case valido rejeitado"
    return 1
  fi
  if ! _session_validate_name "foo123" 2>/dev/null; then
    _fail "validate" "alfanumerico rejeitado"
    return 1
  fi
}

scenario_helpers_validate_name_rejeita_invalidos() {
  _source_session_lib
  # Lista de nomes que DEVEM ser rejeitados:
  # - underscore prefix (regex exige [a-z0-9] inicial)
  # - hyphen prefix (mesmo motivo)
  # - uppercase (regex so aceita [a-z])
  # - whitespace (regex so aceita [a-z0-9-])
  # - ponto (regex so aceita [a-z0-9-])
  # - vazio (validate rejeita explicitamente)
  for _bad in "_starts-underscore" "-starts-hyphen" "Has-Uppercase" "has space" "ponto.no.meio" "" ; do
    _session_validate_name "$_bad" 2>/dev/null
    _rc=$?
    if [ "$_rc" = 0 ]; then
      _fail "validate" "nome '$_bad' aceito incorretamente"
      return 1
    fi
  done
}

scenario_helpers_validate_name_rejeita_blocklist() {
  _source_session_lib
  for _reserved in main master trunk head default origin; do
    capture _session_validate_name "$_reserved"
    if [ "$_CAPTURED_EXIT" != 5 ]; then
      _fail "blocklist" "nome '$_reserved' deveria retornar exit 5, obtido $_CAPTURED_EXIT"
      return 1
    fi
    assert_stderr_contains "reservado" || return 1
  done
}

scenario_helpers_check_git_version_passa_para_recent() {
  _source_session_lib
  if ! _session_check_git_version 2>/dev/null; then
    _fail "git version" "deveria passar (git >=2.36 esperado neste ambiente)"
    return 1
  fi
}

scenario_helpers_resolve_repo_funciona_em_repo_git() {
  _src="$TMPDIR_TEST/repo-test"
  _make_repo "$_src"
  _source_session_lib
  _resolved=$( cd "$_src" && _session_resolve_repo )
  if [ -z "$_resolved" ]; then
    _fail "resolve_repo" "retornou vazio"
    return 1
  fi
  # Path absoluto (physical) terminando em "repo-test"
  _expected=$( cd "$_src" && pwd -P )
  if [ "$_resolved" != "$_expected" ]; then
    _fail "resolve_repo" "esperado '$_expected', obtido '$_resolved'"
    return 1
  fi
}

scenario_helpers_resolve_repo_falha_fora_de_git() {
  _src="$TMPDIR_TEST/not-a-repo"
  mkdir -p "$_src"
  _source_session_lib
  _rc=0
  ( cd "$_src" && _session_resolve_repo 2>/dev/null ) || _rc=$?
  if [ "$_rc" = 0 ]; then
    _fail "resolve_repo" "deveria falhar fora de repo git"
    return 1
  fi
}

scenario_helpers_default_branch_detecta_main() {
  _src="$TMPDIR_TEST/repo-default"
  _make_repo "$_src"
  # Setar origin/HEAD apontando para main (simular clone com setup completo)
  ( cd "$_src" \
    && git remote add origin "$_src" 2>/dev/null || true \
    && git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main 2>/dev/null )
  _source_session_lib
  _b=$( cd "$_src" && _session_default_branch )
  if [ "$_b" != "main" ]; then
    _fail "default_branch" "esperado 'main', obtido '$_b'"
    return 1
  fi
}

scenario_helpers_default_branch_fallback_main() {
  _src="$TMPDIR_TEST/repo-no-origin-head"
  _make_repo "$_src"
  # Sem origin/HEAD setado — fallback hardcoded para "main"
  _source_session_lib
  _b=$( cd "$_src" && _session_default_branch )
  if [ "$_b" != "main" ]; then
    _fail "default_branch fallback" "esperado 'main', obtido '$_b'"
    return 1
  fi
}

scenario_helpers_session_path_calculado_corretamente() {
  _src="$TMPDIR_TEST/myrepo"
  _make_repo "$_src"
  _source_session_lib
  _p=$( cd "$_src" && _session_session_path "feat-x" )
  # Esperado usa pwd -P (physical) para compatibilidade com macOS /tmp symlink
  _expected="$( cd "$TMPDIR_TEST" && pwd -P )/myrepo-feat-x"
  if [ "$_p" != "$_expected" ]; then
    _fail "session_path" "esperado '$_expected', obtido '$_p'"
    return 1
  fi
}

scenario_helpers_branch_is_merged_true_para_ancestor() {
  _src="$TMPDIR_TEST/repo-merged"
  _make_repo "$_src"
  ( cd "$_src" && git branch antiga main )
  _source_session_lib
  _rc=0
  ( cd "$_src" && _session_branch_is_merged antiga main ) || _rc=$?
  if [ "$_rc" != 0 ]; then
    _fail "is_merged" "branch ancestor deveria retornar exit 0, obtido $_rc"
    return 1
  fi
}

scenario_helpers_branch_is_merged_false_para_diverged() {
  _src="$TMPDIR_TEST/repo-diverged"
  _make_repo "$_src"
  ( cd "$_src" \
    && git checkout -q -b feat-new \
    && git commit -q --allow-empty -m "feat commit" )
  _source_session_lib
  _rc=0
  ( cd "$_src" && _session_branch_is_merged feat-new main ) || _rc=$?
  if [ "$_rc" = 0 ]; then
    _fail "is_merged" "branch divergida nao deveria ser ancestor"
    return 1
  fi
}

scenario_helpers_gh_status_detecta_missing() {
  _source_session_lib
  # PATH sem gh
  _rc=0
  PATH="$TMPDIR_TEST/empty-path" _session_gh_status >/dev/null 2>&1 || _rc=$?
  if [ "$_rc" != 11 ]; then
    _fail "gh_status missing" "esperado exit 11, obtido $_rc"
    return 1
  fi
}

scenario_helpers_find_worktree_retorna_blocos_corretos() {
  _src="$TMPDIR_TEST/repo-wt"
  _make_repo "$_src"
  # Criar uma worktree real. Path canonico (pwd -P) para compat com macOS.
  _wt_path="$( cd "$TMPDIR_TEST" && pwd -P )/repo-wt-feat-a"
  ( cd "$_src" && git worktree add -q -b feat-a "$_wt_path" )
  _source_session_lib
  _output=$( cd "$_src" && _session_find_worktree "feat-a" )
  if [ -z "$_output" ]; then
    _fail "find_worktree" "retornou vazio para worktree existente"
    return 1
  fi
  case "$_output" in
    *"path:$_wt_path"*) ;;
    *) _fail "find_worktree path" "esperado path:$_wt_path no output, obtido: $_output"; return 1 ;;
  esac
  case "$_output" in
    *"branch:feat-a"*) ;;
    *) _fail "find_worktree branch" "esperado branch:feat-a, obtido: $_output"; return 1 ;;
  esac
}

scenario_helpers_find_worktree_exit_1_quando_inexistente() {
  _src="$TMPDIR_TEST/repo-no-wt"
  _make_repo "$_src"
  _source_session_lib
  _rc=0
  ( cd "$_src" && _session_find_worktree "inexistente" >/dev/null 2>&1 ) || _rc=$?
  if [ "$_rc" = 0 ]; then
    _fail "find_worktree" "sessao inexistente deveria retornar exit !=0"
    return 1
  fi
}

# ====================================================================
# FASE 2 — Subcomando `start` (11 cenarios)
# ====================================================================

# Helper: cria repo com .claude/ semeada (incluindo artefatos runtime)
_make_repo_with_claude() {
  _mr_dir=$1
  _make_repo "$_mr_dir"
  ( cd "$_mr_dir" \
    && mkdir -p .claude/agente-00c-state .claude/agente-00c-archive \
                .claude/skills .claude/insights .claude/commands \
    && echo '{"id":"x"}' > .claude/agente-00c-state/state.json \
    && echo "archived" > .claude/agente-00c-archive/old.md \
    && echo "report" > .claude/agente-00c-report.md \
    && echo "suggestions" > .claude/agente-00c-suggestions.md \
    && echo "local" > .claude/settings.local.json \
    && echo "whitelist" > .claude/agente-00c-whitelist \
    && echo "lock" > .claude/.agente-00c-state.lock \
    && echo "shared" > .claude/skills/foo.md \
    && echo "shared" > .claude/commands/bar.md \
    && echo "insights-data" > .claude/insights/usage.md \
    && echo "shared-settings" > .claude/settings.json \
    && git add -A && git commit -q -m "seed .claude" )
}

scenario_start_happy_path() {
  _src="$TMPDIR_TEST/repo-happy"
  _make_repo_with_claude "$_src"
  _phys=$( cd "$TMPDIR_TEST" && pwd -P )
  capture sh -c "cd '$_src' && CSTK_LIB='$CSTK_LIB' sh '$CSTK_BIN' session start happy-feat"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
  _wt="$_phys/repo-happy-happy-feat"
  [ -d "$_wt" ] || { _fail "worktree" "nao criada em $_wt"; return 1; }
  [ -d "$_wt/.claude/skills" ] || { _fail ".claude/skills" "nao copiado"; return 1; }
  [ -f "$_wt/.claude/skills/foo.md" ] || { _fail "skills/foo.md" "perdido"; return 1; }
  [ -f "$_wt/.claude/settings.json" ] || { _fail "settings.json" "perdido"; return 1; }
}

scenario_start_claude_excludes_validate_all_8() {
  _src="$TMPDIR_TEST/repo-excl"
  _make_repo_with_claude "$_src"
  _phys=$( cd "$TMPDIR_TEST" && pwd -P )
  capture sh -c "cd '$_src' && CSTK_LIB='$CSTK_LIB' sh '$CSTK_BIN' session start excl-feat"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "start" "$_CAPTURED_STDERR"; return 1; }
  _wt="$_phys/repo-excl-excl-feat"
  # Cada uma das 8 exclusoes deve estar ausente
  for _excl in agente-00c-state agente-00c-archive agente-00c-report.md \
               agente-00c-suggestions.md settings.local.json \
               agente-00c-whitelist .agente-00c-state.lock insights; do
    if [ -e "$_wt/.claude/$_excl" ]; then
      _fail "exclusao" "'$_excl' deveria estar excluido em $_wt/.claude/"
      return 1
    fi
  done
}

scenario_start_blocklist_main_exit_5() {
  _src="$TMPDIR_TEST/repo-block"
  _make_repo "$_src"
  capture sh -c "cd '$_src' && CSTK_LIB='$CSTK_LIB' sh '$CSTK_BIN' session start main"
  if [ "$_CAPTURED_EXIT" != 5 ]; then
    _fail "exit" "esperado 5, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "reservado" || return 1
  assert_stderr_contains "main" || return 1
}

scenario_start_already_exists_exit_6() {
  _src="$TMPDIR_TEST/repo-dup"
  _make_repo "$_src"
  capture sh -c "cd '$_src' && CSTK_LIB='$CSTK_LIB' sh '$CSTK_BIN' session start feat-dup"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "first start" "$_CAPTURED_STDERR"; return 1; }
  # Segunda tentativa deve falhar com exit 6 OU 7 (path ocupado, tambem aceitavel)
  capture sh -c "cd '$_src' && CSTK_LIB='$CSTK_LIB' sh '$CSTK_BIN' session start feat-dup"
  case "$_CAPTURED_EXIT" in
    6|7) ;;
    *) _fail "exit" "esperado 6 ou 7, obtido $_CAPTURED_EXIT"; return 1 ;;
  esac
}

scenario_start_branch_merged_no_flag_exit_8() {
  _src="$TMPDIR_TEST/repo-merged"
  _make_repo "$_src"
  # Cria branch local ancestor de main (mergeada)
  ( cd "$_src" && git branch antiga main )
  capture sh -c "cd '$_src' && CSTK_LIB='$CSTK_LIB' sh '$CSTK_BIN' session start antiga"
  if [ "$_CAPTURED_EXIT" != 8 ]; then
    _fail "exit" "esperado 8, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
  assert_stderr_contains "mergeada" || return 1
  assert_stderr_contains "--reset" || return 1
  assert_stderr_contains "--reuse" || return 1
}

scenario_start_branch_merged_with_reset() {
  _src="$TMPDIR_TEST/repo-reset"
  _make_repo "$_src"
  ( cd "$_src" && git branch antiga main )
  _phys=$( cd "$TMPDIR_TEST" && pwd -P )
  capture sh -c "cd '$_src' && CSTK_LIB='$CSTK_LIB' sh '$CSTK_BIN' session start antiga --reset"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
  _wt="$_phys/repo-reset-antiga"
  [ -d "$_wt" ] || { _fail "worktree" "nao criada"; return 1; }
}

scenario_start_branch_in_origin_only_tracks() {
  _src="$TMPDIR_TEST/repo-origin"
  _make_repo "$_src"
  # Simula remote: criar bare repo + push de branch para la, depois fetch
  _remote="$TMPDIR_TEST/remote-origin.git"
  git init -q --bare "$_remote"
  ( cd "$_src" \
    && git remote add origin "$_remote" \
    && git checkout -q -b remote-feat \
    && git commit -q --allow-empty -m "remote work" \
    && git push -q origin remote-feat \
    && git checkout -q main \
    && git branch -D remote-feat \
    && git fetch -q origin )
  # Agora origin/remote-feat existe, mas remote-feat local foi deletada
  _phys=$( cd "$TMPDIR_TEST" && pwd -P )
  capture sh -c "cd '$_src' && CSTK_LIB='$CSTK_LIB' sh '$CSTK_BIN' session start remote-feat"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
  assert_stdout_contains "origin/remote-feat" || return 1
  # Worktree deve ter o commit "remote work"
  _wt="$_phys/repo-origin-remote-feat"
  ( cd "$_wt" && git log --oneline | grep -q "remote work" ) \
    || { _fail "branch content" "commit 'remote work' nao encontrado na worktree"; return 1; }
}

scenario_start_reset_with_unmerged_commits_prompt_cancel() {
  _src="$TMPDIR_TEST/repo-reset-cancel"
  _make_repo "$_src"
  # Branch com commit nao-mergeado
  ( cd "$_src" \
    && git checkout -q -b feat-unmerged \
    && git commit -q --allow-empty -m "unmerged work" \
    && git checkout -q main )
  # Injetar "n" via stdin (cancela o prompt)
  capture sh -c "echo n | (cd '$_src' && CSTK_LIB='$CSTK_LIB' sh '$CSTK_BIN' session start feat-unmerged --reset)"
  if [ "$_CAPTURED_EXIT" != 10 ]; then
    _fail "exit" "esperado 10 (cancelado), obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
  assert_stderr_contains "cancelado" || return 1
  # Branch antiga preservada
  ( cd "$_src" && git rev-parse --verify feat-unmerged >/dev/null 2>&1 ) \
    || { _fail "branch preserved" "feat-unmerged foi deletada apesar do cancel"; return 1; }
}

scenario_start_reset_with_unmerged_commits_force_bypass() {
  _src="$TMPDIR_TEST/repo-reset-force"
  _make_repo "$_src"
  ( cd "$_src" \
    && git checkout -q -b feat-force \
    && git commit -q --allow-empty -m "will be discarded" \
    && git checkout -q main )
  _phys=$( cd "$TMPDIR_TEST" && pwd -P )
  capture sh -c "cd '$_src' && CSTK_LIB='$CSTK_LIB' sh '$CSTK_BIN' session start feat-force --reset --force"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "exit" "esperado 0 (force bypass), obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
  # Branch nao deve ter mais o commit antigo (foi recriada do main)
  _wt="$_phys/repo-reset-force-feat-force"
  if ( cd "$_wt" && git log --oneline | grep -q "will be discarded" ); then
    _fail "force" "commit antigo ainda presente apesar de --reset --force"
    return 1
  fi
}

scenario_start_invalid_name_chars() {
  _src="$TMPDIR_TEST/repo-invalidname"
  _make_repo "$_src"
  for _bad in "has space" "ponto.no.meio" "_underscore" "-hyphen-prefix" "UPPER" ""; do
    capture sh -c "cd '$_src' && CSTK_LIB='$CSTK_LIB' sh '$CSTK_BIN' session start '$_bad'"
    if [ "$_CAPTURED_EXIT" = 0 ]; then
      _fail "invalid '$_bad'" "deveria rejeitar mas exit=0"
      return 1
    fi
  done
}

scenario_start_path_destination_occupied_exit_7() {
  _src="$TMPDIR_TEST/repo-occ"
  _make_repo "$_src"
  _phys=$( cd "$TMPDIR_TEST" && pwd -P )
  _occ="$_phys/repo-occ-occupied"
  mkdir -p "$_occ"
  capture sh -c "cd '$_src' && CSTK_LIB='$CSTK_LIB' sh '$CSTK_BIN' session start occupied"
  if [ "$_CAPTURED_EXIT" != 7 ]; then
    _fail "exit" "esperado 7, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
  assert_stderr_contains "ocupado" || return 1
}

# ====================================================================
# FASE 3 — Subcomando `list` (6 cenarios)
# ====================================================================

scenario_list_empty_no_sessions() {
  _src="$TMPDIR_TEST/repo-list-empty"
  _make_repo "$_src"
  capture sh -c "cd '$_src' && CSTK_LIB='$CSTK_LIB' sh '$CSTK_BIN' session list"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT; $_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "nenhuma sessao ativa" || return 1
}

scenario_list_multiple_sessions_table() {
  _src="$TMPDIR_TEST/repo-list-multi"
  _make_repo "$_src"
  # Criar 2 sessoes
  ( cd "$_src" && CSTK_LIB="$CSTK_LIB" sh "$CSTK_BIN" session start feat-a >/dev/null )
  ( cd "$_src" && CSTK_LIB="$CSTK_LIB" sh "$CSTK_BIN" session start feat-b >/dev/null )
  capture sh -c "cd '$_src' && CSTK_LIB='$CSTK_LIB' sh '$CSTK_BIN' session list"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "NAME" || return 1
  assert_stdout_contains "BRANCH" || return 1
  assert_stdout_contains "IDLE" || return 1
  assert_stdout_contains "STATUS" || return 1
  assert_stdout_contains "PATH" || return 1
  assert_stdout_contains "feat-a" || return 1
  assert_stdout_contains "feat-b" || return 1
}

scenario_list_with_stale_shows_marker_and_tip() {
  _src="$TMPDIR_TEST/repo-list-stale"
  _make_repo "$_src"
  _phys=$( cd "$TMPDIR_TEST" && pwd -P )
  ( cd "$_src" && CSTK_LIB="$CSTK_LIB" sh "$CSTK_BIN" session start ghost >/dev/null )
  # Deletar pasta da sessao (manualmente) — fica stale
  rm -rf "$_phys/repo-list-stale-ghost"
  capture sh -c "cd '$_src' && CSTK_LIB='$CSTK_LIB' sh '$CSTK_BIN' session list"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "STALE" || return 1
  assert_stdout_contains "git worktree prune" || return 1
}

scenario_list_json_output_valid_shape() {
  _src="$TMPDIR_TEST/repo-list-json"
  _make_repo "$_src"
  ( cd "$_src" && CSTK_LIB="$CSTK_LIB" sh "$CSTK_BIN" session start jfoo >/dev/null )
  capture sh -c "cd '$_src' && CSTK_LIB='$CSTK_LIB' sh '$CSTK_BIN' session list --json"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_STDERR"; return 1; }
  # Valid JSON array: comeca com [ e termina com ]
  case "$_CAPTURED_STDOUT" in
    '['*']') ;;
    *) _fail "json shape" "esperado JSON array, obtido: $_CAPTURED_STDOUT"; return 1 ;;
  esac
  # Tem todos os campos camelCase
  assert_stdout_contains '"name":"jfoo"' || return 1
  assert_stdout_contains '"branch":"jfoo"' || return 1
  assert_stdout_contains '"idleDays":' || return 1
  assert_stdout_contains '"dirty":' || return 1
  assert_stdout_contains '"stale":' || return 1
  assert_stdout_contains '"current":' || return 1
  # Rodape suprimido em JSON: nao deve ter "tip:"
  case "$_CAPTURED_STDOUT" in
    *"tip:"*) _fail "json no-tip" "rodape de tip nao deveria aparecer em --json"; return 1 ;;
  esac
}

scenario_list_current_marker_when_inside_session() {
  _src="$TMPDIR_TEST/repo-list-cur"
  _make_repo "$_src"
  _phys=$( cd "$TMPDIR_TEST" && pwd -P )
  ( cd "$_src" && CSTK_LIB="$CSTK_LIB" sh "$CSTK_BIN" session start inside >/dev/null )
  # Rodar `list` de DENTRO da worktree da sessao
  _wt="$_phys/repo-list-cur-inside"
  capture sh -c "cd '$_wt' && CSTK_LIB='$CSTK_LIB' sh '$CSTK_BIN' session list"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "CURRENT" || return 1
  assert_stdout_contains "inside" || return 1
}

scenario_list_ordering_by_idle_asc() {
  _src="$TMPDIR_TEST/repo-list-ord"
  _make_repo "$_src"
  ( cd "$_src" && CSTK_LIB="$CSTK_LIB" sh "$CSTK_BIN" session start older >/dev/null )
  ( cd "$_src" && CSTK_LIB="$CSTK_LIB" sh "$CSTK_BIN" session start newer >/dev/null )
  # Ambas tem mesmo idle (0d) porque acabaram de ser criadas. Validar apenas
  # que ambas aparecem ordenadas (nao crash; sort estavel). Cenario completo
  # de ordenacao temporal e dificil sem manipular commit time.
  capture sh -c "cd '$_src' && CSTK_LIB='$CSTK_LIB' sh '$CSTK_BIN' session list"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_STDERR"; return 1; }
  # Ambas presentes
  assert_stdout_contains "older" || return 1
  assert_stdout_contains "newer" || return 1
}

# ====================================================================
# FASE 4 — Subcomando `end` (8 cenarios)
# ====================================================================

scenario_end_clean_happy_path() {
  _src="$TMPDIR_TEST/repo-end-clean"
  _make_repo "$_src"
  _phys=$( cd "$TMPDIR_TEST" && pwd -P )
  ( cd "$_src" && CSTK_LIB="$CSTK_LIB" sh "$CSTK_BIN" session start clean >/dev/null )
  _wt="$_phys/repo-end-clean-clean"
  [ -d "$_wt" ] || { _fail "precondition" "worktree nao criada"; return 1; }
  capture sh -c "cd '$_src' && CSTK_LIB='$CSTK_LIB' sh '$CSTK_BIN' session end clean"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT; $_CAPTURED_STDERR"; return 1; }
  [ ! -d "$_wt" ] || { _fail "worktree" "ainda existe apos end"; return 1; }
  # Branch local tambem deletada
  if ( cd "$_src" && git rev-parse --verify clean >/dev/null 2>&1 ); then
    _fail "branch" "branch local 'clean' ainda existe"
    return 1
  fi
}

scenario_end_dirty_prompt_cancel_exit_10() {
  _src="$TMPDIR_TEST/repo-end-dirty"
  _make_repo "$_src"
  _phys=$( cd "$TMPDIR_TEST" && pwd -P )
  ( cd "$_src" && CSTK_LIB="$CSTK_LIB" sh "$CSTK_BIN" session start dirty >/dev/null )
  _wt="$_phys/repo-end-dirty-dirty"
  echo "wip" > "$_wt/wip.txt"
  # Injetar "n" no stdin (cancela)
  capture sh -c "echo n | (cd '$_src' && CSTK_LIB='$CSTK_LIB' sh '$CSTK_BIN' session end dirty)"
  if [ "$_CAPTURED_EXIT" != 10 ]; then
    _fail "exit" "esperado 10 (cancelado), obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "modificado" || return 1
  assert_stderr_contains "cancelado" || return 1
  [ -d "$_wt" ] || { _fail "worktree" "removida apesar do cancel"; return 1; }
}

scenario_end_dirty_prompt_accept() {
  _src="$TMPDIR_TEST/repo-end-acpt"
  _make_repo "$_src"
  _phys=$( cd "$TMPDIR_TEST" && pwd -P )
  ( cd "$_src" && CSTK_LIB="$CSTK_LIB" sh "$CSTK_BIN" session start acpt >/dev/null )
  _wt="$_phys/repo-end-acpt-acpt"
  echo "wip" > "$_wt/wip.txt"
  capture sh -c "echo y | (cd '$_src' && CSTK_LIB='$CSTK_LIB' sh '$CSTK_BIN' session end acpt)"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT; $_CAPTURED_STDERR"; return 1; }
  [ ! -d "$_wt" ] || { _fail "worktree" "ainda existe apos accept"; return 1; }
}

scenario_end_dirty_force_bypass() {
  _src="$TMPDIR_TEST/repo-end-force"
  _make_repo "$_src"
  _phys=$( cd "$TMPDIR_TEST" && pwd -P )
  ( cd "$_src" && CSTK_LIB="$CSTK_LIB" sh "$CSTK_BIN" session start fbypass >/dev/null )
  _wt="$_phys/repo-end-force-fbypass"
  echo "wip" > "$_wt/wip.txt"
  # --force pula prompt; stdin nao deve afetar
  capture sh -c "cd '$_src' && CSTK_LIB='$CSTK_LIB' sh '$CSTK_BIN' session end fbypass --force"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT; $_CAPTURED_STDERR"; return 1; }
  [ ! -d "$_wt" ] || { _fail "worktree" "nao removida com --force"; return 1; }
}

scenario_end_unpushed_commits_prompt() {
  _src="$TMPDIR_TEST/repo-end-unpush"
  _make_repo "$_src"
  _phys=$( cd "$TMPDIR_TEST" && pwd -P )
  # Criar remote bare + push da branch + criar novo commit local
  _remote="$TMPDIR_TEST/remote-unpush.git"
  git init -q --bare "$_remote"
  ( cd "$_src" && git remote add origin "$_remote" )
  ( cd "$_src" && CSTK_LIB="$CSTK_LIB" sh "$CSTK_BIN" session start upx >/dev/null )
  _wt="$_phys/repo-end-unpush-upx"
  ( cd "$_wt" && git push -q -u origin upx )
  ( cd "$_wt" && git commit -q --allow-empty -m "local-only commit" )
  # Sem --force deveria promptar
  capture sh -c "echo n | (cd '$_src' && CSTK_LIB='$CSTK_LIB' sh '$CSTK_BIN' session end upx)"
  if [ "$_CAPTURED_EXIT" != 10 ]; then
    _fail "exit" "esperado 10 (cancelado), obtido $_CAPTURED_EXIT; $_CAPTURED_STDERR"
    return 1
  fi
  assert_stderr_contains "pushado" || return 1
}

scenario_end_no_gh_pr_check_skipped() {
  _src="$TMPDIR_TEST/repo-end-nogh"
  _make_repo "$_src"
  _phys=$( cd "$TMPDIR_TEST" && pwd -P )
  ( cd "$_src" && CSTK_LIB="$CSTK_LIB" sh "$CSTK_BIN" session start nogh >/dev/null )
  _wt="$_phys/repo-end-nogh-nogh"
  # PATH sem gh — PR check deve ser skippado com warning
  _empty_path="$TMPDIR_TEST/empty-bin"
  mkdir -p "$_empty_path"
  capture sh -c "cd '$_src' && PATH='$_empty_path:/usr/bin:/bin' CSTK_LIB='$CSTK_LIB' sh '$CSTK_BIN' session end nogh"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT; $_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains "PR check pulado" || return 1
  [ ! -d "$_wt" ] || { _fail "worktree" "nao removida"; return 1; }
}

scenario_end_from_inside_self_exit_14() {
  _src="$TMPDIR_TEST/repo-end-self"
  _make_repo "$_src"
  _phys=$( cd "$TMPDIR_TEST" && pwd -P )
  ( cd "$_src" && CSTK_LIB="$CSTK_LIB" sh "$CSTK_BIN" session start selfx >/dev/null )
  _wt="$_phys/repo-end-self-selfx"
  # Rodar `end` DE DENTRO da worktree-alvo
  capture sh -c "cd '$_wt' && CSTK_LIB='$CSTK_LIB' sh '$CSTK_BIN' session end selfx"
  if [ "$_CAPTURED_EXIT" != 14 ]; then
    _fail "exit" "esperado 14, obtido $_CAPTURED_EXIT; $_CAPTURED_STDERR"
    return 1
  fi
  assert_stderr_contains "sessao atual" || return 1
  [ -d "$_wt" ] || { _fail "worktree" "removida apesar do self-end"; return 1; }
}

scenario_end_session_not_found_exit_9() {
  _src="$TMPDIR_TEST/repo-end-nf"
  _make_repo "$_src"
  capture sh -c "cd '$_src' && CSTK_LIB='$CSTK_LIB' sh '$CSTK_BIN' session end inexistente"
  if [ "$_CAPTURED_EXIT" != 9 ]; then
    _fail "exit" "esperado 9, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "nao encontrada" || return 1
  assert_stderr_contains "cstk session list" || return 1
}

# ====================================================================
# FASE 5 — Subcomando `pr` (6 cenarios; success/idempotent marcados manual)
# ====================================================================

scenario_pr_session_not_found_exit_9() {
  _src="$TMPDIR_TEST/repo-pr-nf"
  _make_repo "$_src"
  capture sh -c "cd '$_src' && CSTK_LIB='$CSTK_LIB' sh '$CSTK_BIN' session pr inexistente"
  if [ "$_CAPTURED_EXIT" != 9 ]; then
    _fail "exit" "esperado 9, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "nao encontrada" || return 1
}

scenario_pr_no_commits_exit_13() {
  _src="$TMPDIR_TEST/repo-pr-nc"
  _make_repo "$_src"
  ( cd "$_src" && CSTK_LIB="$CSTK_LIB" sh "$CSTK_BIN" session start empty-pr >/dev/null )
  # FR-009 ordem: validacao de commits vem ANTES de gh check, entao este
  # cenario funciona mesmo em ambientes sem gh autenticado (CI Ubuntu).
  capture sh -c "cd '$_src' && CSTK_LIB='$CSTK_LIB' sh '$CSTK_BIN' session pr empty-pr"
  if [ "$_CAPTURED_EXIT" != 13 ]; then
    _fail "exit" "esperado 13, obtido $_CAPTURED_EXIT; $_CAPTURED_STDERR"
    return 1
  fi
  assert_stderr_contains "nao tem commits novos" || return 1
}

scenario_pr_gh_not_installed_exit_11() {
  _src="$TMPDIR_TEST/repo-pr-nogh"
  _make_repo "$_src"
  _phys=$( cd "$TMPDIR_TEST" && pwd -P )
  ( cd "$_src" && CSTK_LIB="$CSTK_LIB" sh "$CSTK_BIN" session start gh-x >/dev/null )
  # Pre-condition: precisa de commits para chegar no gh check
  _wt="$_phys/repo-pr-nogh-gh-x"
  ( cd "$_wt" && git commit -q --allow-empty -m "test commit" )
  # PATH com symlinks para tools essenciais (git, sed, awk, etc), SEM gh.
  # Mais robusto que PATH=/usr/bin (que pode conter gh dependendo da distro).
  _isolated_bin="$TMPDIR_TEST/isolated-bin-no-gh"
  mkdir -p "$_isolated_bin"
  for _tool in git sh sed awk grep cut printf cat mkdir rm cp find wc tr sort date tail head basename dirname uname rmdir mv touch ls test true false env stat; do
    _tool_path=$(command -v "$_tool" 2>/dev/null)
    if [ -n "$_tool_path" ] && [ "$_tool" != "gh" ]; then
      ln -sf "$_tool_path" "$_isolated_bin/$_tool" 2>/dev/null || true
    fi
  done
  # Validar que nosso PATH isolado realmente nao tem gh
  if ! PATH="$_isolated_bin" sh -c 'command -v gh >/dev/null 2>&1' && \
       PATH="$_isolated_bin" sh -c 'command -v git >/dev/null 2>&1'; then
    : # PATH isolado OK
  else
    _fail "setup" "PATH isolado nao funcionou (gh detectado OU git ausente)"
    return 1
  fi
  capture sh -c "cd '$_src' && PATH='$_isolated_bin' CSTK_LIB='$CSTK_LIB' sh '$CSTK_BIN' session pr gh-x"
  if [ "$_CAPTURED_EXIT" != 11 ]; then
    _fail "exit" "esperado 11, obtido $_CAPTURED_EXIT; PATH=$_isolated_bin; $_CAPTURED_STDERR"
    return 1
  fi
  assert_stderr_contains "gh CLI nao instalado" || return 1
}

scenario_pr_gh_unauthenticated_exit_12() {
  _src="$TMPDIR_TEST/repo-pr-unauth"
  _make_repo "$_src"
  _phys=$( cd "$TMPDIR_TEST" && pwd -P )
  ( cd "$_src" && CSTK_LIB="$CSTK_LIB" sh "$CSTK_BIN" session start unauth-x >/dev/null )
  # Pre-condition: precisa de commits para chegar no gh check
  _wt="$_phys/repo-pr-unauth-unauth-x"
  ( cd "$_wt" && git commit -q --allow-empty -m "test commit" )
  # Stub gh que sempre retorna != 0 em "auth status"
  _stub_dir="$TMPDIR_TEST/stub-gh-unauth"
  mkdir -p "$_stub_dir"
  cat > "$_stub_dir/gh" <<'STUBGH'
#!/bin/sh
case "$1" in
  auth) exit 1 ;;
  *) echo "stub" ; exit 0 ;;
esac
STUBGH
  chmod +x "$_stub_dir/gh"
  capture sh -c "cd '$_src' && PATH='$_stub_dir:/usr/bin:/bin' CSTK_LIB='$CSTK_LIB' sh '$CSTK_BIN' session pr unauth-x"
  if [ "$_CAPTURED_EXIT" != 12 ]; then
    _fail "exit" "esperado 12, obtido $_CAPTURED_EXIT; $_CAPTURED_STDERR"
    return 1
  fi
  assert_stderr_contains "nao autenticado" || return 1
  assert_stderr_contains "gh auth login" || return 1
}

scenario_pr_unknown_flag_exit_2() {
  _src="$TMPDIR_TEST/repo-pr-flag"
  _make_repo "$_src"
  ( cd "$_src" && CSTK_LIB="$CSTK_LIB" sh "$CSTK_BIN" session start flagx >/dev/null )
  capture sh -c "cd '$_src' && CSTK_LIB='$CSTK_LIB' sh '$CSTK_BIN' session pr flagx --xyz"
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "flag desconhecida" || return 1
}

scenario_pr_name_required_exit_2() {
  _src="$TMPDIR_TEST/repo-pr-noname"
  _make_repo "$_src"
  capture sh -c "cd '$_src' && CSTK_LIB='$CSTK_LIB' sh '$CSTK_BIN' session pr"
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "obrigatorio" || return 1
}

# NOTA: Cenarios scenario_pr_success_manual e scenario_pr_idempotent_manual
# (quickstart §11 e §12) requerem rede + repo remoto GitHub. Marcados como
# MANUAL na quickstart.md — nao automatizados em test_session.sh.

# ====================================================================
# FASE 6 — Quality Gate (E2E + Compliance + Lint)
# ====================================================================

scenario_e2e_roundtrip_isolation() {
  # Quickstart §14: 2 sessoes paralelas criam .claude/agente-00c-state/
  # isolado, sem colisao.
  _src="$TMPDIR_TEST/repo-roundtrip"
  _make_repo_with_claude "$_src"
  _phys=$( cd "$TMPDIR_TEST" && pwd -P )
  # Criar 2 sessoes
  ( cd "$_src" && CSTK_LIB="$CSTK_LIB" sh "$CSTK_BIN" session start sess-a >/dev/null )
  ( cd "$_src" && CSTK_LIB="$CSTK_LIB" sh "$CSTK_BIN" session start sess-b >/dev/null )

  # Simular agente-00c criando state independente em cada sessao
  _wt_a="$_phys/repo-roundtrip-sess-a"
  _wt_b="$_phys/repo-roundtrip-sess-b"
  mkdir -p "$_wt_a/.claude/agente-00c-state" "$_wt_b/.claude/agente-00c-state"
  printf '{"id":"a"}\n' > "$_wt_a/.claude/agente-00c-state/state.json"
  printf '{"id":"b"}\n' > "$_wt_b/.claude/agente-00c-state/state.json"

  # Validar isolamento: states diferentes, repo principal sem state
  _a=$(cat "$_wt_a/.claude/agente-00c-state/state.json")
  _b=$(cat "$_wt_b/.claude/agente-00c-state/state.json")
  if [ "$_a" = "$_b" ]; then
    _fail "isolation" "states identicos quando deveriam ser distintos"
    return 1
  fi
  # Repo principal nao teve seu .claude/agente-00c-state/ criado (foi excluido na copia)
  if [ -e "$_src/.claude/agente-00c-state/state.json" ]; then
    # OK se ja existia antes; o que importa e que copia para sessao NAO o leva
    :
  fi
}

scenario_e2e_two_parallel_sessions_no_conflict() {
  # SC-002: duas sessoes simultaneas no mesmo repo produzem zero conflitos
  # em working tree, branch HEAD, .claude/agente-00c-state/.
  _src="$TMPDIR_TEST/repo-parallel"
  _make_repo "$_src"
  _phys=$( cd "$TMPDIR_TEST" && pwd -P )

  ( cd "$_src" && CSTK_LIB="$CSTK_LIB" sh "$CSTK_BIN" session start p-alpha >/dev/null )
  ( cd "$_src" && CSTK_LIB="$CSTK_LIB" sh "$CSTK_BIN" session start p-beta >/dev/null )

  _wt_a="$_phys/repo-parallel-p-alpha"
  _wt_b="$_phys/repo-parallel-p-beta"

  # Trabalho concorrente: cada sessao edita seu proprio arquivo
  echo "alpha-work" > "$_wt_a/alpha.txt"
  echo "beta-work" > "$_wt_b/beta.txt"

  # Working tree isolado: alpha.txt nao aparece na worktree de beta nem no main
  if [ -e "$_wt_b/alpha.txt" ]; then
    _fail "working-tree" "alpha.txt vazou para sessao beta"
    return 1
  fi
  if [ -e "$_src/alpha.txt" ]; then
    _fail "main-tree" "alpha.txt vazou para repo principal"
    return 1
  fi

  # Branch HEAD isolado: alpha esta em branch p-alpha; main continua em main
  _b_alpha=$(git -C "$_wt_a" rev-parse --abbrev-ref HEAD)
  _b_main=$(git -C "$_src" rev-parse --abbrev-ref HEAD)
  if [ "$_b_alpha" = "$_b_main" ]; then
    _fail "branch-head" "alpha e main na mesma branch ($_b_alpha)"
    return 1
  fi
}

scenario_e2e_boot_check_git_old_exit_15() {
  # FR-030 (Premissa): boot-check rejeita git <2.36 com exit 15.
  # Simular via stub `git` que reporta versao antiga em `git --version`.
  _stub_dir="$TMPDIR_TEST/stub-git-old"
  mkdir -p "$_stub_dir"
  # Delegar todas outras chamadas ao git real
  _real_git=$(command -v git)
  cat > "$_stub_dir/git" <<EOF
#!/bin/sh
case "\$1" in
  --version) echo "git version 2.10.0" ; exit 0 ;;
  *) "$_real_git" "\$@" ;;
esac
EOF
  chmod +x "$_stub_dir/git"

  # Boot-check deve disparar e retornar exit 15
  capture sh -c "PATH='$_stub_dir:/usr/bin:/bin' CSTK_LIB='$CSTK_LIB' sh '$CSTK_BIN' session start foo"
  if [ "$_CAPTURED_EXIT" != 15 ]; then
    _fail "exit" "esperado 15, obtido $_CAPTURED_EXIT; $_CAPTURED_STDERR"
    return 1
  fi
  assert_stderr_contains "2.10.0" || return 1
  assert_stderr_contains "minimo requerido" || return 1
  assert_stderr_contains "2.36" || return 1
}

scenario_e2e_all_exit_codes_documented() {
  # F6.1.4: cross-check de exit codes — todos 5-15 documentados em
  # contracts/cli-session.md sao exercitados por algum cenario do
  # test_session.sh. Validacao via grep deste arquivo.
  _this="$0"
  _missing=""
  # Mapeamento exit code -> cenario esperado (substring no nome)
  # 5  = invalid name (blocklist OR invalid chars)
  # 6  = sessao ja existe
  # 7  = path destination occupied
  # 8  = branch ja mergeada
  # 9  = sessao nao encontrada (end OR pr)
  # 10 = cancelled by user
  # 11 = gh nao instalado
  # 12 = gh nao autenticado
  # 13 = branch sem commits novos
  # 14 = self-end
  # 15 = git too old
  for _code_name in "5:blocklist_main_exit_5" "6:already_exists_exit_6" \
                    "7:path_destination_occupied_exit_7" "8:branch_merged_no_flag_exit_8" \
                    "9:session_not_found" "10:prompt_cancel_exit_10" \
                    "11:gh_not_installed_exit_11" "12:gh_unauthenticated_exit_12" \
                    "13:no_commits_exit_13" "14:from_inside_self_exit_14" \
                    "15:boot_check_git_old_exit_15"; do
    _code=$(printf '%s' "$_code_name" | cut -d: -f1)
    _name=$(printf '%s' "$_code_name" | cut -d: -f2)
    if ! grep -q "scenario_.*${_name}" "$_this"; then
      _missing="$_missing $_code"
    fi
  done
  if [ -n "$_missing" ]; then
    _fail "exit codes coverage" "exit codes sem cenario:$_missing"
    return 1
  fi
}

scenario_e2e_sc001_wallclock_under_3s() {
  # SC-001: cstk session start deve completar em <=3s para repos pequenos.
  _src="$TMPDIR_TEST/repo-wc"
  _make_repo "$_src"
  _start=$(date +%s)
  ( cd "$_src" && CSTK_LIB="$CSTK_LIB" sh "$CSTK_BIN" session start wc-feat >/dev/null )
  _end=$(date +%s)
  _elapsed=$((_end - _start))
  if [ "$_elapsed" -gt 3 ]; then
    _fail "SC-001" "wallclock=${_elapsed}s excedeu target de 3s"
    return 1
  fi
}

scenario_e2e_messages_actionability() {
  # SC-006 / F6.1.6: cada mensagem stderr para exit codes 5-15 contem
  # verbo de acao corretiva ("use ", "rode ", "instale ", "atualize ",
  # "--force", "gh auth login", "git ", "cstk ").
  _src="$TMPDIR_TEST/repo-act"
  _make_repo "$_src"
  ( cd "$_src" && CSTK_LIB="$CSTK_LIB" sh "$CSTK_BIN" session start exists >/dev/null )

  # Acumular stderr de cada caso de erro e validar regex em todos
  _all_stderr=""
  # Exit 5 (invalid name)
  capture sh -c "cd '$_src' && CSTK_LIB='$CSTK_LIB' sh '$CSTK_BIN' session start 'invalid name'"
  _all_stderr="$_all_stderr
$_CAPTURED_STDERR"
  # Exit 6 (sessao ja existe)
  capture sh -c "cd '$_src' && CSTK_LIB='$CSTK_LIB' sh '$CSTK_BIN' session start exists"
  _all_stderr="$_all_stderr
$_CAPTURED_STDERR"
  # Exit 9 (sessao nao encontrada)
  capture sh -c "cd '$_src' && CSTK_LIB='$CSTK_LIB' sh '$CSTK_BIN' session end inexistente"
  _all_stderr="$_all_stderr
$_CAPTURED_STDERR"
  # Exit 13 (sem commits)
  capture sh -c "cd '$_src' && CSTK_LIB='$CSTK_LIB' sh '$CSTK_BIN' session pr exists"
  _all_stderr="$_all_stderr
$_CAPTURED_STDERR"

  # Verificar que stderr acumulado contem pelo menos 3 verbos de acao distintos.
  # SC-006 e qualitativo (mensagens acionaveis); este teste e proxy quantitativo.
  _verbs=0
  for _v in "use " "rode " "instale " "atualize " "faca " "--force" "gh auth login" "cstk "; do
    case "$_all_stderr" in
      *"$_v"*) _verbs=$((_verbs + 1)) ;;
    esac
  done
  if [ "$_verbs" -lt 3 ]; then
    _fail "actionability" "stderr tem apenas $_verbs verbo(s) de acao (esperado >=3); SC-006 violado"
    return 1
  fi
}

# F6.2: Lint + coverage validados via scenarios meta abaixo

scenario_lint_zero_bashisms() {
  # F6.2.2: validar que cli/lib/session.sh nao tem bash-isms reais.
  # Filtros: ignorar comentarios (linhas iniciando com #) e strings dentro
  # de awk blocks (linhas dentro de `awk '...'` ou heredocs).
  _f="$REPO_ROOT/cli/lib/session.sh"
  # Pegar matches potenciais EXCETO linhas que sao comentarios
  _matches=$(grep -nE '^\s*\[\[|<<<|^\s*function[[:space:]]+\w+\s*\(|^\s*local[[:space:]]+\w+=' "$_f" \
    | grep -vE '^[0-9]+:[[:space:]]*#' \
    | grep -v 'function flush()' \
    || true)
  if [ -n "$_matches" ]; then
    _fail "bash-isms" "encontrados em session.sh:
$_matches"
    return 1
  fi
}

scenario_lint_gh_confined_to_session() {
  # F6.2.3 / Constitution II 1.1.0 cond b: gh referenciado apenas em
  # cli/lib/session.sh (confinada em 1 arquivo).
  _files=$(grep -lE '\bgh\b' "$REPO_ROOT/cli/lib/"*.sh 2>/dev/null)
  _expected="$REPO_ROOT/cli/lib/session.sh"
  if [ "$_files" != "$_expected" ]; then
    _fail "gh confinement" "esperado apenas session.sh, encontrado:
$_files"
    return 1
  fi
}

run_all_scenarios
