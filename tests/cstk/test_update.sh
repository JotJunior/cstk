#!/bin/sh
# test_update.sh — cobre cli/lib/update.sh
#
# Cobre Scenario 2 (idempotencia SC-002, mtime preservado), Scenario 3
# (edit local + --force), --keep silencioso, --prune (renomeada/removida no
# catalog), exit 4 quando skip-by-edit, --force + --keep mutuamente exclusivos,
# subset por args, nada instalado, dry-run.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CSTK_LIB="$REPO_ROOT/cli/lib"
export CSTK_LIB

# _make_release: monta tarball mock. Args: dir tag list-de-skills extras-profile.
# Cada skill criada com SKILL.md contendo "# <skill> <tag>" para variar hash.
# `list-de-skills`: nomes separados por espaco. Profile sdd inclui todas.
_make_release() {
  _mr_dir=$1
  _mr_tag=$2
  _mr_skills=$3
  _mr_root="$_mr_dir/cstk-$_mr_tag"
  mkdir -p "$_mr_root/catalog/skills"
  printf '%s\n' "$_mr_tag" > "$_mr_root/catalog/VERSION"
  : > "$_mr_root/catalog/profiles.txt"
  for _s in $_mr_skills; do
    mkdir -p "$_mr_root/catalog/skills/$_s"
    printf '# %s %s\n' "$_s" "$_mr_tag" > "$_mr_root/catalog/skills/$_s/SKILL.md"
    printf 'sdd:%s\n' "$_s" >> "$_mr_root/catalog/profiles.txt"
  done
  (cd "$_mr_dir" && tar -czf "cstk-$_mr_tag.tar.gz" "cstk-$_mr_tag") || return 1
  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$_mr_dir" && sha256sum "cstk-$_mr_tag.tar.gz" > "cstk-$_mr_tag.tar.gz.sha256") || return 1
  else
    (cd "$_mr_dir" && shasum -a 256 "cstk-$_mr_tag.tar.gz" > "cstk-$_mr_tag.tar.gz.sha256") || return 1
  fi
  return 0
}

_install_release() {
  _ir_home=$1
  _ir_url=$2
  capture env HOME="$_ir_home" CSTK_LIB="$CSTK_LIB" sh -c '
    . "$CSTK_LIB/install.sh"; install_main --from "$1"
  ' install_test "$_ir_url"
}

_run_update() {
  _ru_home=$1; shift
  capture env HOME="$_ru_home" CSTK_LIB="$CSTK_LIB" sh -c '
    . "$CSTK_LIB/update.sh"; update_main "$@"
  ' update_test "$@"
}

_mtime() {
  # Linux/GNU stat (-c %Y) PRIMEIRO. Em macOS/BSD cai no fallback BSD (-f %m).
  # Ordem inversa quebra racy no Linux: stat -f %m exit 0 mas imprime info
  # do filesystem (Block size, Inodes Free, etc.) que varia entre chamadas
  # devido a atividade FS de fundo — comparacao falha intermitentemente.
  # Mesmo bug em test_self-update.sh + test_quickstart-e2e.sh.
  if stat -c %Y -- "$1" 2>/dev/null; then return 0; fi
  stat -f %m -- "$1" 2>/dev/null
}

# ==== Scenario 2: idempotencia (SC-002) — zero writes, mtime preservado ====

scenario_update_idempotente_sem_mudancas() {
  _h="$TMPDIR_TEST/h"
  _r="$TMPDIR_TEST/r"
  _make_release "$_r" v1.0 "foo bar" || { _error "fixture" ""; return 2; }
  _url="file://$_r/cstk-v1.0.tar.gz"
  _install_release "$_h" "$_url"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "install setup" "$_CAPTURED_STDERR"; return 1; }

  _mfst="$_h/.claude/skills/.cstk-manifest"
  _foo="$_h/.claude/skills/foo/SKILL.md"
  _m_before=$(_mtime "$_mfst")
  _f_before=$(_mtime "$_foo")
  # Sleep > 1s para diferenciar mtime caso haja write
  sleep 1.1

  _run_update "$_h" --from "$_url"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "idempotent exit" "$_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
  assert_stderr_contains "already up-to-date: 2" || return 1
  assert_stderr_contains "updated: 0" || return 1

  _m_after=$(_mtime "$_mfst")
  _f_after=$(_mtime "$_foo")
  if [ "$_m_before" != "$_m_after" ]; then
    _fail "manifest mtime mudou (SC-002)" "$_m_before -> $_m_after"
    return 1
  fi
  if [ "$_f_before" != "$_f_after" ]; then
    _fail "skill file mtime mudou (SC-002)" "$_f_before -> $_f_after"
    return 1
  fi
}

# ==== Scenario 3: edicao local sem flag -> exit 4, conteudo preservado ====

scenario_update_edit_local_sem_force_exit4() {
  _h="$TMPDIR_TEST/h"
  _r1="$TMPDIR_TEST/r1"
  _r2="$TMPDIR_TEST/r2"
  _make_release "$_r1" v1.0 "foo bar" || { _error "fixture v1" ""; return 2; }
  _make_release "$_r2" v2.0 "foo bar" || { _error "fixture v2" ""; return 2; }
  _install_release "$_h" "file://$_r1/cstk-v1.0.tar.gz"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "install" ""; return 1; }

  # Edita foo localmente
  printf '\nLINHA DO USUARIO\n' >> "$_h/.claude/skills/foo/SKILL.md"

  _run_update "$_h" --from "file://$_r2/cstk-v2.0.tar.gz"
  if [ "$_CAPTURED_EXIT" != 4 ]; then
    _fail "edit local exit" "esperado 4 (FR-008), obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "skipped (local edits): 1" || return 1
  assert_stderr_contains "    - foo" || return 1
  assert_stderr_contains "next: cstk update --force" || return 1
  # foo intocada
  grep -q 'LINHA DO USUARIO' "$_h/.claude/skills/foo/SKILL.md" \
    || { _fail "edit foo perdida" ""; return 1; }
  # bar deve ter sido atualizada (clean -> release diff)
  grep -q 'v2.0' "$_h/.claude/skills/bar/SKILL.md" \
    || { _fail "bar nao atualizada" ""; return 1; }
}

# ==== --force sobrescreve edits locais ====

scenario_update_force_sobrescreve_edit() {
  _h="$TMPDIR_TEST/h"
  _r1="$TMPDIR_TEST/r1"
  _r2="$TMPDIR_TEST/r2"
  _make_release "$_r1" v1.0 "foo" || { _error "fixture v1" ""; return 2; }
  _make_release "$_r2" v2.0 "foo" || { _error "fixture v2" ""; return 2; }
  _install_release "$_h" "file://$_r1/cstk-v1.0.tar.gz"
  printf '\nUSUARIO MEXEU\n' >> "$_h/.claude/skills/foo/SKILL.md"

  _run_update "$_h" --force --from "file://$_r2/cstk-v2.0.tar.gz"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "force exit" "$_CAPTURED_EXIT; $_CAPTURED_STDERR"
    return 1
  fi
  assert_stderr_contains "updated: 1" || return 1
  grep -q 'USUARIO MEXEU' "$_h/.claude/skills/foo/SKILL.md" \
    && { _fail "edit nao sobrescrita" ""; return 1; }
  grep -q '# foo v2.0' "$_h/.claude/skills/foo/SKILL.md" \
    || { _fail "release nao escrita" ""; return 1; }
  return 0
}

# ==== --keep silencia mas nao da exit 4 ====

scenario_update_keep_silencia_edit() {
  _h="$TMPDIR_TEST/h"
  _r1="$TMPDIR_TEST/r1"
  _r2="$TMPDIR_TEST/r2"
  _make_release "$_r1" v1.0 "foo bar" || { _error "fixture" ""; return 2; }
  _make_release "$_r2" v2.0 "foo bar" || { _error "fixture" ""; return 2; }
  _install_release "$_h" "file://$_r1/cstk-v1.0.tar.gz"
  printf '\nKEEP-ME\n' >> "$_h/.claude/skills/foo/SKILL.md"

  _run_update "$_h" --keep --from "file://$_r2/cstk-v2.0.tar.gz"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "keep exit" "esperado 0 (--keep silencia exit 4), obtido $_CAPTURED_EXIT; $_CAPTURED_STDERR"
    return 1
  fi
  assert_stderr_contains "kept (--keep): 1" || return 1
  case "$_CAPTURED_STDERR" in
    *"edicao local em foo"*)
      _fail "keep nao silenciou" "warning per-skill apareceu mas --keep deveria suprimir"
      return 1
      ;;
  esac
  # foo edit preservada
  grep -q 'KEEP-ME' "$_h/.claude/skills/foo/SKILL.md" \
    || { _fail "edit foo perdida" ""; return 1; }
}

# ==== --force + --keep => exit 2 ====

scenario_update_force_keep_mutex_exit2() {
  _run_update "$TMPDIR_TEST/h" --force --keep --from "file:///tmp/x"
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "force+keep exit" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "mutuamente exclusivos" || return 1
}

# ==== --prune remove orfaos (skill no manifest mas removida do catalog) ====

scenario_update_prune_remove_orfao() {
  _h="$TMPDIR_TEST/h"
  _r1="$TMPDIR_TEST/r1"
  _r2="$TMPDIR_TEST/r2"
  _make_release "$_r1" v1.0 "foo bar" || { _error "fixture" ""; return 2; }
  # v2 nao tem mais bar (removida do catalog)
  _make_release "$_r2" v2.0 "foo" || { _error "fixture" ""; return 2; }
  _install_release "$_h" "file://$_r1/cstk-v1.0.tar.gz"
  [ -d "$_h/.claude/skills/bar" ] || { _fail "bar nao instalada" ""; return 1; }

  _run_update "$_h" --prune --yes --from "file://$_r2/cstk-v2.0.tar.gz"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "prune exit" "$_CAPTURED_EXIT; $_CAPTURED_STDERR"
    return 1
  fi
  assert_stderr_contains "removed (pruned): 1" || return 1
  [ -d "$_h/.claude/skills/bar" ] && { _fail "bar nao removida" ""; return 1; }
  # bar removida do manifest
  grep -q '^bar	' "$_h/.claude/skills/.cstk-manifest" \
    && { _fail "bar manifest entry resta" ""; return 1; }
  return 0
}

# ==== Sem --prune: orfao gera warning mas nao remove (exit 0) ====

scenario_update_orfao_sem_prune_apenas_warn() {
  _h="$TMPDIR_TEST/h"
  _r1="$TMPDIR_TEST/r1"
  _r2="$TMPDIR_TEST/r2"
  _make_release "$_r1" v1.0 "foo bar" || { _error "fixture" ""; return 2; }
  _make_release "$_r2" v2.0 "foo" || { _error "fixture" ""; return 2; }
  _install_release "$_h" "file://$_r1/cstk-v1.0.tar.gz"
  _run_update "$_h" --from "file://$_r2/cstk-v2.0.tar.gz"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "orfao sem prune exit" "esperado 0, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "removida do catalog: bar" || return 1
  assert_stderr_contains "use --prune para remover" || return 1
  [ -d "$_h/.claude/skills/bar" ] || { _fail "bar removida sem --prune" ""; return 1; }
}

# ==== Subset por arg: update apenas uma skill ====

scenario_update_subset_por_arg() {
  _h="$TMPDIR_TEST/h"
  _r1="$TMPDIR_TEST/r1"
  _r2="$TMPDIR_TEST/r2"
  _make_release "$_r1" v1.0 "foo bar" || { _error "fixture" ""; return 2; }
  _make_release "$_r2" v2.0 "foo bar" || { _error "fixture" ""; return 2; }
  _install_release "$_h" "file://$_r1/cstk-v1.0.tar.gz"
  _run_update "$_h" foo --from "file://$_r2/cstk-v2.0.tar.gz"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "subset exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains "updated: 1" || return 1
  # foo atualizada
  grep -q 'foo v2.0' "$_h/.claude/skills/foo/SKILL.md" || { _fail "foo nao atualizada" ""; return 1; }
  # bar inalterada (continua v1.0)
  grep -q 'bar v1.0' "$_h/.claude/skills/bar/SKILL.md" || { _fail "bar foi atualizada por engano" ""; return 1; }
}

# ==== Subset por arg com skill nao instalada => exit 2 ====

scenario_update_subset_skill_inexistente_exit2() {
  _h="$TMPDIR_TEST/h"
  _r="$TMPDIR_TEST/r"
  _make_release "$_r" v1.0 "foo" || { _error "fixture" ""; return 2; }
  _install_release "$_h" "file://$_r/cstk-v1.0.tar.gz"
  _run_update "$_h" foo nao-existe --from "file://$_r/cstk-v1.0.tar.gz"
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "subset inexistente exit" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "nao instalada" || return 1
}

# ==== Manifest ausente: aviso + exit 0 ====

scenario_update_sem_manifest_warn_exit0() {
  _h="$TMPDIR_TEST/h"
  mkdir -p "$_h/.claude/skills"
  _r="$TMPDIR_TEST/r"
  _make_release "$_r" v1.0 "foo" || { _error "fixture" ""; return 2; }
  _run_update "$_h" --from "file://$_r/cstk-v1.0.tar.gz"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "sem manifest exit" "esperado 0, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "manifest ausente" || return 1
}

# ==== Dry-run nao escreve mas reporta plano ====

scenario_update_dry_run_zero_writes() {
  _h="$TMPDIR_TEST/h"
  _r1="$TMPDIR_TEST/r1"
  _r2="$TMPDIR_TEST/r2"
  _make_release "$_r1" v1.0 "foo" || { _error "fixture" ""; return 2; }
  _make_release "$_r2" v2.0 "foo" || { _error "fixture" ""; return 2; }
  _install_release "$_h" "file://$_r1/cstk-v1.0.tar.gz"
  _foo="$_h/.claude/skills/foo/SKILL.md"
  _before=$(_mtime "$_foo")
  sleep 1.1
  _run_update "$_h" --dry-run --from "file://$_r2/cstk-v2.0.tar.gz"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "dry exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains "(dry-run)" || return 1
  assert_stderr_contains "updated: 1" || return 1
  _after=$(_mtime "$_foo")
  if [ "$_before" != "$_after" ]; then
    _fail "dry-run alterou foo" "$_before -> $_after"
    return 1
  fi
  # foo content ainda v1.0
  grep -q 'foo v1.0' "$_foo" || { _fail "dry-run mudou conteudo" ""; return 1; }
}

# ==== Help ====

scenario_update_help_exit0() {
  _run_update "$TMPDIR_TEST/h" --help
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "help exit" "$_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "cstk update" || return 1
}

# ==== mcp/state-server: update espelha e substitui a fonte (fix pos-6.2.1) ====

scenario_update_espelha_mcp_state_server() {
  _h="$TMPDIR_TEST/home-mcpup"
  _r1="$TMPDIR_TEST/rel-mcpup-1"
  _r2="$TMPDIR_TEST/rel-mcpup-2"
  _make_release "$_r1" "v1.0" "alpha" || return 2
  _install_release "$_h" "file://$_r1/cstk-v1.0.tar.gz"
  [ "$_CAPTURED_EXIT" = 0 ] || { _error "seed install" "$_CAPTURED_STDERR"; return 2; }

  # v2.0 traz catalog/mcp/state-server; o update deve espelhar no HOME.
  _make_release "$_r2" "v2.0" "alpha" || return 2
  _root2="$_r2/cstk-v2.0"
  mkdir -p "$_root2/catalog/mcp/state-server/src"
  printf '{"version":"0.9.9"}\n' > "$_root2/catalog/mcp/state-server/package.json"
  printf '// v2 index\n' > "$_root2/catalog/mcp/state-server/src/index.ts"
  (cd "$_r2" && tar -czf cstk-v2.0.tar.gz cstk-v2.0) || return 2
  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$_r2" && sha256sum cstk-v2.0.tar.gz > cstk-v2.0.tar.gz.sha256) || return 2
  else
    (cd "$_r2" && shasum -a 256 cstk-v2.0.tar.gz > cstk-v2.0.tar.gz.sha256) || return 2
  fi

  # Sujeira pre-existente no destino prova o replace atomico (rm+cp).
  mkdir -p "$_h/.claude/mcp/state-server"
  printf 'stale\n' > "$_h/.claude/mcp/state-server/stale-file.txt"

  _run_update "$_h" --from "file://$_r2/cstk-v2.0.tar.gz"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "update exit" "obtido $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  grep -q '"version":"0.9.9"' "$_h/.claude/mcp/state-server/package.json" 2>/dev/null \
    || { _fail "fonte do state-server nao atualizada" ""; return 1; }
  [ ! -e "$_h/.claude/mcp/state-server/stale-file.txt" ] \
    || { _fail "replace nao removeu conteudo stale" ""; return 1; }
}

run_all_scenarios
