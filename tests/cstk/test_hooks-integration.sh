#!/bin/sh
# test_hooks-integration.sh — cobre integracao hooks <-> install/update
# (FASE 7.2 + enforced-guards US1 task 2.5.4).
#
# Cobre:
#   Scenario 4: --scope=project + --profile=language-go + jq presente
#               => settings.json criado/mesclado, hooks/ copiado, summary
#                  reporta "merged"
#   Scenario 5: --scope=project + jq AUSENTE + ./.claude/settings.json existente
#               => settings.json INTOCADO, paste-block emitido, summary
#                  reporta "paste-instructed"
#   FR-009c:    --scope=global + --profile=language-* => hooks omitidos com
#               warning, summary reporta "omitted"
#
# enforced-guards (task 2.5.4 — guard-hook PreToolUse/Bash de US1, extensao
# de install.sh/update.sh independente do profile language-*):
#   - install --scope project + skill agente-00c-runtime => guard-hook
#     provisionado em .claude/hooks/, settings.json mesclado, summary
#     reporta "guard-hooks: merged"
#   - install --scope global => guard-hook omitido (Decision 9/FR-009c)
#   - install profile=language-go + skill agente-00c-runtime juntos =>
#     coexistencia sem clobber (ambos os hooks provisionados, settings.json
#     com ambas as chaves)
#   - update: reprovisiona o guard-hook quando agente-00c-runtime esta entre
#     os alvos (achado da research.md — update.sh historicamente nao tocava
#     hooks em nenhum caso; FR-004/SC-006 exige cobertura tambem no update)

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CSTK_LIB="$REPO_ROOT/cli/lib"
export CSTK_LIB

_has_jq() { command -v jq >/dev/null 2>&1; }

_path_sem_jq() {
  _orig=$PATH; _new=""
  IFS=:
  for _d in $_orig; do
    [ -n "$_d" ] || continue
    if [ ! -x "$_d/jq" ]; then
      if [ -z "$_new" ]; then _new=$_d; else _new="$_new:$_d"; fi
    fi
  done
  unset IFS
  printf '%s' "$_new"
}

# _make_shim_path: cria um dir em $TMPDIR_TEST/shimbin com symlinks para
# binarios essenciais (mktemp, tar, sha*, cat, sed, awk, etc.) exceto jq.
# Isso resolve o problema de filtrar /usr/bin (onde fica jq E mktemp em
# macOS) sem perder mktemp etc. Ecoa o path do shimbin.
_make_shim_path() {
  _shim="$TMPDIR_TEST/shimbin"
  mkdir -p "$_shim"
  # gzip/gunzip/xz/bzip2: tar -xzf invoca um descompressor externo (no Linux
  # geralmente gzip). Sem ele no PATH, "tar: falha ao extrair" mesmo com
  # tar presente. xz/bzip2 incluidos defensivamente para outros formatos.
  for _cmd in sh mktemp tar gzip gunzip xz bzip2 curl shasum sha256sum cat \
              awk sed grep find head printf cp mv rm mkdir chmod ls dirname \
              basename tr cut wc env command sort uniq date; do
    _src=$(command -v "$_cmd" 2>/dev/null) || continue
    [ -n "$_src" ] || continue
    ln -sf "$_src" "$_shim/$_cmd" 2>/dev/null || :
  done
  printf '%s' "$_shim"
}

# Fixture: catalog com skill regular + language-go (skills/+hooks/+settings.json)
_make_lang_release() {
  _r=$1
  _root="$_r/cstk-v1"
  mkdir -p "$_root/catalog/skills/regular" \
           "$_root/catalog/language/go/skills/golang-helper" \
           "$_root/catalog/language/go/hooks" || return 1
  printf 'v1\n' > "$_root/catalog/VERSION"
  {
    printf 'sdd:regular\n'
    printf 'language-go:golang-helper\n'
  } > "$_root/catalog/profiles.txt"
  printf '# regular\n' > "$_root/catalog/skills/regular/SKILL.md"
  printf '# golang helper\n' > "$_root/catalog/language/go/skills/golang-helper/SKILL.md"
  printf '#!/bin/sh\necho pre-commit\n' > "$_root/catalog/language/go/hooks/pre-commit.sh"
  printf '{"hooks":{"go":{"vet":"go vet ./..."}}}\n' > "$_root/catalog/language/go/settings.json"
  (cd "$_r" && tar -czf cstk-v1.tar.gz cstk-v1) || return 1
  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$_r" && sha256sum cstk-v1.tar.gz > cstk-v1.tar.gz.sha256) || return 1
  else
    (cd "$_r" && shasum -a 256 cstk-v1.tar.gz > cstk-v1.tar.gz.sha256) || return 1
  fi
  return 0
}

# _run_install_in: roda install_main com CWD = $1, HOME = $2, args restantes.
# Usa pattern single-quote-body + positionals para evitar quoting hell.
_run_install_in() {
  _ri_cwd=$1; _ri_home=$2; shift 2
  capture env HOME="$_ri_home" CSTK_LIB="$CSTK_LIB" CWD="$_ri_cwd" sh -c '
    cd "$CWD" || exit 1
    . "$CSTK_LIB/install.sh"
    install_main "$@"
  ' install_test "$@"
}

# _run_install_in_no_jq: idem, mas com PATH limpo de jq.
_run_install_in_no_jq() {
  _ri_cwd=$1; _ri_home=$2; shift 2
  _shim=$(_make_shim_path)
  # PATH = APENAS o shim (sem jq); TMPDIR para mktemp funcionar.
  capture env -i \
    HOME="$_ri_home" \
    CSTK_LIB="$CSTK_LIB" \
    CWD="$_ri_cwd" \
    PATH="$_shim" \
    TMPDIR="${TMPDIR:-/tmp}" \
    sh -c '
      cd "$CWD" || exit 1
      . "$CSTK_LIB/install.sh"
      install_main "$@"
    ' install_test "$@"
}

# ==== Scenario 4: project + language-go + jq presente => merged ====

scenario_install_project_lang_com_jq_merged() {
  if ! _has_jq; then _error "no_jq" "jq necessario"; return 2; fi
  _r="$TMPDIR_TEST/r"
  _proj="$TMPDIR_TEST/proj"
  _make_lang_release "$_r" || { _error "fixture" ""; return 2; }
  mkdir -p "$_proj"
  : > "$_proj/package.json"

  _run_install_in "$_proj" "$TMPDIR_TEST/h" \
    --scope project --profile language-go \
    --from "file://$_r/cstk-v1.tar.gz"

  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "install exit" "$_CAPTURED_EXIT; $_CAPTURED_STDERR"
    return 1
  fi
  [ -f "$_proj/.claude/skills/golang-helper/SKILL.md" ] \
    || { _fail "skill golang-helper ausente" ""; return 1; }
  [ -f "$_proj/.claude/hooks/pre-commit.sh" ] \
    || { _fail "hooks/pre-commit.sh nao copiado" ""; return 1; }
  [ -f "$_proj/.claude/settings.json" ] \
    || { _fail "settings.json nao criado" ""; return 1; }
  jq -e '.hooks.go.vet == "go vet ./..."' "$_proj/.claude/settings.json" >/dev/null \
    || { _fail "settings sem hooks.go.vet" ""; return 1; }
  assert_stderr_contains "hooks: merged" || return 1
}

# ==== Scenario 4b: settings PRE-EXISTENTE + jq => target vence em conflitos ====

scenario_install_project_lang_settings_existente_target_vence() {
  if ! _has_jq; then _error "no_jq" "skip"; return 2; fi
  _r="$TMPDIR_TEST/r"
  _proj="$TMPDIR_TEST/proj"
  _make_lang_release "$_r" || { _error "fixture" ""; return 2; }
  mkdir -p "$_proj/.claude"
  : > "$_proj/package.json"
  printf '{"user_pref":"keep","hooks":{"go":{"vet":"USER_OVERRIDE"}}}\n' > "$_proj/.claude/settings.json"

  _run_install_in "$_proj" "$TMPDIR_TEST/h" \
    --scope project --profile language-go \
    --from "file://$_r/cstk-v1.tar.gz"

  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "install exit" "$_CAPTURED_STDERR"; return 1; }
  jq -e '.user_pref == "keep"' "$_proj/.claude/settings.json" >/dev/null \
    || { _fail "user_pref perdido" ""; return 1; }
  jq -e '.hooks.go.vet == "USER_OVERRIDE"' "$_proj/.claude/settings.json" >/dev/null \
    || { _fail "merge nao preservou target" "$(cat "$_proj/.claude/settings.json")"; return 1; }
  [ -f "$_proj/.claude/settings.json.bak" ] \
    || { _fail "backup ausente" ""; return 1; }
}

# ==== Scenario 5: project + language-go + jq AUSENTE => paste-block, settings intocado ====

scenario_install_project_lang_sem_jq_paste_instructed() {
  _r="$TMPDIR_TEST/r"
  _proj="$TMPDIR_TEST/proj"
  _make_lang_release "$_r" || { _error "fixture" ""; return 2; }
  mkdir -p "$_proj/.claude"
  : > "$_proj/package.json"
  printf '{"intacto":"sim"}\n' > "$_proj/.claude/settings.json"
  _settings_sha_before=$(shasum -a 256 "$_proj/.claude/settings.json" 2>/dev/null \
    || sha256sum "$_proj/.claude/settings.json")

  _run_install_in_no_jq "$_proj" "$TMPDIR_TEST/h" \
    --scope project --profile language-go \
    --from "file://$_r/cstk-v1.tar.gz"

  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "install sem jq exit" "$_CAPTURED_EXIT; $_CAPTURED_STDERR"
    return 1
  fi
  [ -f "$_proj/.claude/skills/golang-helper/SKILL.md" ] \
    || { _fail "skill nao instalada" ""; return 1; }
  [ -f "$_proj/.claude/hooks/pre-commit.sh" ] \
    || { _fail "hooks nao copiados" ""; return 1; }
  _settings_sha_after=$(shasum -a 256 "$_proj/.claude/settings.json" 2>/dev/null \
    || sha256sum "$_proj/.claude/settings.json")
  if [ "$_settings_sha_before" != "$_settings_sha_after" ]; then
    _fail "settings.json modificado sem jq (FR-009d violado)" \
      "$_settings_sha_before -> $_settings_sha_after"
    return 1
  fi
  assert_stderr_contains "Hooks to merge manually" || return 1
  assert_stderr_contains "BEGIN PAYLOAD" || return 1
  assert_stderr_contains "hooks: paste-instructed" || return 1
}

# ==== FR-009c: --scope=global + language-* => omitido ====

scenario_install_global_lang_omitido() {
  _r="$TMPDIR_TEST/r"
  _h="$TMPDIR_TEST/h"
  _make_lang_release "$_r" || { _error "fixture" ""; return 2; }

  _run_install_in "$TMPDIR_TEST" "$_h" \
    --scope global --profile language-go \
    --from "file://$_r/cstk-v1.tar.gz"

  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "install global exit" "$_CAPTURED_EXIT; $_CAPTURED_STDERR"
    return 1
  fi
  [ -f "$_h/.claude/skills/golang-helper/SKILL.md" ] \
    || { _fail "skill nao instalada" ""; return 1; }
  [ -e "$_h/.claude/hooks" ] && { _fail "hooks/ criados em global (FR-009c violado)" ""; return 1; }
  [ -e "$_h/.claude/settings.json" ] && { _fail "settings.json criado em global" ""; return 1; }
  assert_stderr_contains "omitidos em scope=global" || return 1
  assert_stderr_contains "hooks: omitted" || return 1
  return 0
}

# ==== Profile != language-*: hooks line ausente do summary ====

scenario_install_profile_nao_language_sem_hooks_no_summary() {
  _r="$TMPDIR_TEST/r"
  _h="$TMPDIR_TEST/h"
  _make_lang_release "$_r" || { _error "fixture" ""; return 2; }

  _run_install_in "$TMPDIR_TEST" "$_h" \
    --profile sdd --from "file://$_r/cstk-v1.tar.gz"

  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "install" "$_CAPTURED_STDERR"; return 1; }
  case "$_CAPTURED_STDERR" in
    *"hooks:"*)
      _fail "summary com 'hooks:' em profile nao-language" "$_CAPTURED_STDERR"
      return 1
      ;;
  esac
}

# ==== enforced-guards (task 2.5.4): fixtures + helpers ====

# _make_guard_release: catalog com language-go (regressao/coexistencia) +
# agente-00c-runtime com hooks/ (pretooluse-bash-guard.sh + settings.snippet.json)
# — espelha o que scripts/build-release.sh produz de fato (cp -R da skill
# inteira, hooks/ incluido, ver CLAUDE.md §Installed vs Source Drift).
_make_guard_release() {
  _r=$1
  _root="$_r/cstk-v1"
  mkdir -p "$_root/catalog/skills/agente-00c-runtime/hooks" \
           "$_root/catalog/skills/agente-00c-runtime/scripts" \
           "$_root/catalog/language/go/skills/golang-helper" \
           "$_root/catalog/language/go/hooks" || return 1
  printf 'v1\n' > "$_root/catalog/VERSION"
  {
    printf 'sdd:agente-00c-runtime\n'
    printf 'language-go:golang-helper\n'
  } > "$_root/catalog/profiles.txt"
  printf '# agente-00c-runtime\n' > "$_root/catalog/skills/agente-00c-runtime/SKILL.md"
  printf '#!/bin/sh\nexit 0\n' > "$_root/catalog/skills/agente-00c-runtime/hooks/pretooluse-bash-guard.sh"
  chmod +x "$_root/catalog/skills/agente-00c-runtime/hooks/pretooluse-bash-guard.sh"
  printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"guard","timeout":5}]}]}}\n' \
    > "$_root/catalog/skills/agente-00c-runtime/hooks/settings.snippet.json"
  printf '#!/bin/sh\nexit 0\n' > "$_root/catalog/skills/agente-00c-runtime/scripts/bash-guard.sh"
  printf '# golang helper\n' > "$_root/catalog/language/go/skills/golang-helper/SKILL.md"
  printf '#!/bin/sh\necho pre-commit\n' > "$_root/catalog/language/go/hooks/pre-commit.sh"
  printf '{"hooks":{"go":{"vet":"go vet ./..."}}}\n' > "$_root/catalog/language/go/settings.json"
  (cd "$_r" && tar -czf cstk-v1.tar.gz cstk-v1) || return 1
  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$_r" && sha256sum cstk-v1.tar.gz > cstk-v1.tar.gz.sha256) || return 1
  else
    (cd "$_r" && shasum -a 256 cstk-v1.tar.gz > cstk-v1.tar.gz.sha256) || return 1
  fi
  return 0
}

# _run_update_in: roda update_main com CWD = $1, HOME = $2, args restantes.
_run_update_in() {
  _ru_cwd=$1; _ru_home=$2; shift 2
  capture env HOME="$_ru_home" CSTK_LIB="$CSTK_LIB" CWD="$_ru_cwd" sh -c '
    cd "$CWD" || exit 1
    . "$CSTK_LIB/update.sh"
    update_main "$@"
  ' update_test "$@"
}

# ==== install --scope project + skill agente-00c-runtime => guard-hook merged ====

scenario_install_project_guard_hook_merged() {
  if ! _has_jq; then _error "no_jq" "jq necessario"; return 2; fi
  _r="$TMPDIR_TEST/r"
  _proj="$TMPDIR_TEST/proj"
  _make_guard_release "$_r" || { _error "fixture" ""; return 2; }
  mkdir -p "$_proj"
  : > "$_proj/package.json"

  _run_install_in "$_proj" "$TMPDIR_TEST/h" \
    --scope project agente-00c-runtime \
    --from "file://$_r/cstk-v1.tar.gz"

  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "install exit" "$_CAPTURED_EXIT; $_CAPTURED_STDERR"; return 1; }
  [ -f "$_proj/.claude/skills/agente-00c-runtime/SKILL.md" ] \
    || { _fail "skill agente-00c-runtime ausente" ""; return 1; }
  [ -x "$_proj/.claude/hooks/pretooluse-bash-guard.sh" ] \
    || { _fail "guard-hook nao provisionado em .claude/hooks/" ""; return 1; }
  jq -e '.hooks.PreToolUse[0].matcher == "Bash"' "$_proj/.claude/settings.json" >/dev/null \
    || { _fail "settings.json sem guard-hook mesclado" "$(cat "$_proj/.claude/settings.json" 2>/dev/null)"; return 1; }
  assert_stderr_contains "guard-hooks: merged" || return 1
}

# ==== install --scope global => guard-hook omitido (Decision 9/FR-009c) ====

scenario_install_global_guard_hook_omitido() {
  _r="$TMPDIR_TEST/r"
  _h="$TMPDIR_TEST/h"
  _make_guard_release "$_r" || { _error "fixture" ""; return 2; }

  _run_install_in "$TMPDIR_TEST" "$_h" \
    --scope global agente-00c-runtime \
    --from "file://$_r/cstk-v1.tar.gz"

  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "install global exit" "$_CAPTURED_EXIT; $_CAPTURED_STDERR"; return 1; }
  [ -f "$_h/.claude/skills/agente-00c-runtime/SKILL.md" ] \
    || { _fail "skill nao instalada" ""; return 1; }
  [ -e "$_h/.claude/hooks/pretooluse-bash-guard.sh" ] \
    && { _fail "guard-hook criado em global (FR-009c/Decision 9 violado)" ""; return 1; }
  assert_stderr_contains "guard-hooks (enforced-guards) omitidos em scope=global" || return 1
  return 0
}

# ==== Coexistencia: profile=language-go + skill agente-00c-runtime juntos ====

scenario_install_coexistencia_language_e_guard_hook() {
  if ! _has_jq; then _error "no_jq" "jq necessario"; return 2; fi
  _r="$TMPDIR_TEST/r"
  _proj="$TMPDIR_TEST/proj"
  _make_guard_release "$_r" || { _error "fixture" ""; return 2; }
  mkdir -p "$_proj"
  : > "$_proj/package.json"

  _run_install_in "$_proj" "$TMPDIR_TEST/h" \
    --scope project --profile language-go agente-00c-runtime \
    --from "file://$_r/cstk-v1.tar.gz"

  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "install exit" "$_CAPTURED_EXIT; $_CAPTURED_STDERR"; return 1; }
  [ -f "$_proj/.claude/hooks/pre-commit.sh" ] \
    || { _fail "hook de language-go ausente (regressao)" ""; return 1; }
  [ -x "$_proj/.claude/hooks/pretooluse-bash-guard.sh" ] \
    || { _fail "guard-hook ausente (coexistencia quebrada)" ""; return 1; }
  jq -e '.hooks.go.vet == "go vet ./..."' "$_proj/.claude/settings.json" >/dev/null \
    || { _fail "settings.json perdeu hooks.go (merge language)" "$(cat "$_proj/.claude/settings.json")"; return 1; }
  jq -e '.hooks.PreToolUse[0].matcher == "Bash"' "$_proj/.claude/settings.json" >/dev/null \
    || { _fail "settings.json perdeu hooks.PreToolUse (merge guard)" "$(cat "$_proj/.claude/settings.json")"; return 1; }
  assert_stderr_contains "hooks: merged" || return 1
  assert_stderr_contains "guard-hooks: merged" || return 1
}

# ==== update: reprovisiona guard-hook quando agente-00c-runtime e alvo ====

scenario_update_project_guard_hook_reprovisionado() {
  if ! _has_jq; then _error "no_jq" "jq necessario"; return 2; fi
  _r="$TMPDIR_TEST/r"
  _proj="$TMPDIR_TEST/proj"
  _make_guard_release "$_r" || { _error "fixture" ""; return 2; }
  mkdir -p "$_proj"
  : > "$_proj/package.json"

  _run_install_in "$_proj" "$TMPDIR_TEST/h" \
    --scope project agente-00c-runtime \
    --from "file://$_r/cstk-v1.tar.gz"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "install previo exit" "$_CAPTURED_STDERR"; return 1; }

  # Simula drift: hook provisionado e apagado do disco (ex: usuario limpou
  # .claude/hooks/ manualmente); update deve REPROVISIONAR.
  rm -f "$_proj/.claude/hooks/pretooluse-bash-guard.sh"

  _run_update_in "$_proj" "$TMPDIR_TEST/h" --scope project \
    --from "file://$_r/cstk-v1.tar.gz"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "update exit" "$_CAPTURED_EXIT; $_CAPTURED_STDERR"; return 1; }
  [ -x "$_proj/.claude/hooks/pretooluse-bash-guard.sh" ] \
    || { _fail "update nao reprovisionou o guard-hook (achado da research.md)" ""; return 1; }
  assert_stderr_contains "guard-hooks: merged" || return 1
}

# ==== update --scope global => guard-hook omitido (mesma regra do install) ====

scenario_update_global_guard_hook_omitido() {
  _r="$TMPDIR_TEST/r"
  _h="$TMPDIR_TEST/h"
  _make_guard_release "$_r" || { _error "fixture" ""; return 2; }

  _run_install_in "$TMPDIR_TEST" "$_h" \
    --scope global agente-00c-runtime \
    --from "file://$_r/cstk-v1.tar.gz"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "install previo exit" "$_CAPTURED_STDERR"; return 1; }

  _run_update_in "$TMPDIR_TEST" "$_h" --scope global \
    --from "file://$_r/cstk-v1.tar.gz"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "update exit" "$_CAPTURED_EXIT; $_CAPTURED_STDERR"; return 1; }
  [ -e "$_h/.claude/hooks/pretooluse-bash-guard.sh" ] \
    && { _fail "guard-hook criado em global via update (Decision 9 violado)" ""; return 1; }
  assert_stderr_contains "guard-hooks (enforced-guards) omitidos em scope=global" || return 1
  return 0
}

# ==== Dry-run: nada e escrito mas plano e reportado ====

scenario_install_project_lang_dry_run_zero_writes() {
  if ! _has_jq; then _error "no_jq" "skip"; return 2; fi
  _r="$TMPDIR_TEST/r"
  _proj="$TMPDIR_TEST/proj"
  _make_lang_release "$_r" || { _error "fixture" ""; return 2; }
  mkdir -p "$_proj"
  : > "$_proj/package.json"

  _run_install_in "$_proj" "$TMPDIR_TEST/h" \
    --scope project --profile language-go --dry-run \
    --from "file://$_r/cstk-v1.tar.gz"

  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "dry-run exit" "$_CAPTURED_STDERR"; return 1; }
  [ -d "$_proj/.claude" ] && { _fail "dry-run criou .claude/" ""; return 1; }
  assert_stderr_contains "[dry-run]" || return 1
  assert_stderr_contains "hooks: merged" || return 1
}

run_all_scenarios
