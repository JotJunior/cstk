#!/bin/sh
# test_doctor.sh — cobre cli/lib/doctor.sh
#
# Cobre Scenario 10 (4 tipos de drift simultaneos — SC-007), exit 1 sem
# --fix em qualquer drift, --fix remove MISSING e preserva EDITED/ORPHAN,
# tudo OK = exit 0, manifest ausente = exit 0.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CSTK_LIB="$REPO_ROOT/cli/lib"
export CSTK_LIB

_make_release() {
  _mr_dir=$1
  _mr_root="$_mr_dir/cstk-v1"
  mkdir -p "$_mr_root/catalog/skills/foo" \
           "$_mr_root/catalog/skills/bar" \
           "$_mr_root/catalog/skills/baz" || return 1
  printf 'v1\n' > "$_mr_root/catalog/VERSION"
  printf 'sdd:foo\nsdd:bar\nsdd:baz\n' > "$_mr_root/catalog/profiles.txt"
  for s in foo bar baz; do
    printf '# %s v1\n' "$s" > "$_mr_root/catalog/skills/$s/SKILL.md"
  done
  (cd "$_mr_dir" && tar -czf cstk-v1.tar.gz cstk-v1) || return 1
  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$_mr_dir" && sha256sum cstk-v1.tar.gz > cstk-v1.tar.gz.sha256) || return 1
  else
    (cd "$_mr_dir" && shasum -a 256 cstk-v1.tar.gz > cstk-v1.tar.gz.sha256) || return 1
  fi
  return 0
}

_install_v1() {
  capture env HOME="$1" CSTK_LIB="$CSTK_LIB" sh -c '
    . "$CSTK_LIB/install.sh"; install_main --from "$1"
  ' install_test "file://$2/cstk-v1.tar.gz"
}

_run_doctor() {
  _h=$1; shift
  capture env HOME="$_h" CSTK_LIB="$CSTK_LIB" sh -c '
    . "$CSTK_LIB/doctor.sh"; doctor_main "$@"
  ' doctor_test "$@"
}

# ==== Scenario 10 (SC-007): 4 tipos de drift simultaneos ====

scenario_doctor_4_tipos_drift() {
  _h="$TMPDIR_TEST/h"
  _r="$TMPDIR_TEST/r"
  _make_release "$_r" || { _error "fixture" ""; return 2; }
  _install_v1 "$_h" "$_r"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "install" ""; return 1; }

  # Estado inicial: foo, bar, baz instaladas (todas clean)
  # Cria 4 tipos de drift:
  #   - bar => MISSING (deletada do disco; entry no manifest)
  rm -rf "$_h/.claude/skills/bar"
  #   - foo => EDITED (alterada localmente; entry no manifest)
  printf '\nuser edit\n' >> "$_h/.claude/skills/foo/SKILL.md"
  #   - baz => OK (intocada; entry no manifest)
  #   - my-custom => ORPHAN (no disco, sem entry)
  mkdir -p "$_h/.claude/skills/my-custom"
  printf '# third party\n' > "$_h/.claude/skills/my-custom/SKILL.md"

  _run_doctor "$_h"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "drift exit" "esperado 1 (drift sem --fix), obtido $_CAPTURED_EXIT"
    return 1
  fi
  # Todos os 4 tipos relatados
  assert_stderr_contains "[OK]       baz" || return 1
  assert_stderr_contains "[EDITED]   foo" || return 1
  assert_stderr_contains "[MISSING]  bar" || return 1
  assert_stderr_contains "[ORPHAN]   my-custom" || return 1
  assert_stderr_contains "ok:      1" || return 1
  assert_stderr_contains "edited:  1" || return 1
  assert_stderr_contains "missing: 1" || return 1
  assert_stderr_contains "orphan:  1" || return 1
  # ORPHAN deixou de contar como drift: `~/.claude/skills/` e compartilhado
  # (plugins, skills de terceiros, skills locais) e o cstk nao pode cobrar
  # do operador algo que nunca instalou. Restam EDITED + MISSING = 2.
  assert_stderr_contains "[DRIFT] 2" || return 1
  # Exit segue 1 porque HA drift real (edited/missing) neste fixture.
}

# Skills de terceiros SOZINHAS nao podem gatear: e o caso que quebrava
# `cstk doctor || exit 1` como gate de CI assim que um plugin da Anthropic
# ou qualquer skill de terceiro aparecia em ~/.claude/skills.
scenario_doctor_apenas_orphan_nao_gateia() {
  _h="$TMPDIR_TEST/h-orphan"
  _r="$TMPDIR_TEST/r-orphan"
  _make_release "$_r" || { _error "fixture" ""; return 2; }
  _install_v1 "$_h" "$_r"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "install" ""; return 1; }

  # Nenhum drift do cstk; so skills que ele nunca instalou.
  for _n in cloudflare wrangler minha-skill-local; do
    mkdir -p "$_h/.claude/skills/$_n"
    printf '# nao e do cstk\n' > "$_h/.claude/skills/$_n/SKILL.md"
  done

  _run_doctor "$_h"
  [ "$_CAPTURED_EXIT" = 0 ] \
    || { _fail "exit" "so orphan NAO pode gatear; esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "orphan:  3" || return 1
  case "$_CAPTURED_STDERR" in
    *"[DRIFT]"*) _fail "drift" "nao deveria imprimir [DRIFT] sem drift real do cstk"; return 1 ;;
  esac
  # Some do gate, mas nao da visibilidade.
  assert_stderr_contains "[ORPHAN]   cloudflare" || return 1
  return 0
}

# --fix nunca teve reparo para ORPHAN (sempre preservou); com apenas
# orphans nao ha o que reconciliar e as pastas continuam intactas.
scenario_doctor_fix_preserva_orphan() {
  _h="$TMPDIR_TEST/h-fix-orphan"
  _r="$TMPDIR_TEST/r-fix-orphan"
  _make_release "$_r" || { _error "fixture" ""; return 2; }
  _install_v1 "$_h" "$_r"
  mkdir -p "$_h/.claude/skills/de-terceiro"
  printf '# terceiro\n' > "$_h/.claude/skills/de-terceiro/SKILL.md"

  _run_doctor "$_h" --fix
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -f "$_h/.claude/skills/de-terceiro/SKILL.md" ] \
    || { _fail "preservacao" "--fix NAO pode remover skill de terceiro"; return 1; }
  grep -q "de-terceiro" "$_h/.claude/skills/.cstk-manifest" 2>/dev/null \
    && { _fail "adocao" "--fix NAO pode adotar terceiro no manifest"; return 1; }
  return 0
}

# ==== Tudo OK => exit 0 ====

scenario_doctor_tudo_ok_exit0() {
  _h="$TMPDIR_TEST/h"
  _r="$TMPDIR_TEST/r"
  _make_release "$_r" || { _error "fixture" ""; return 2; }
  _install_v1 "$_h" "$_r"
  _run_doctor "$_h"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "tudo ok exit" "esperado 0, obtido $_CAPTURED_EXIT; $_CAPTURED_STDERR"
    return 1
  fi
  assert_stderr_contains "ok:      3" || return 1
  case "$_CAPTURED_STDERR" in
    *"[DRIFT]"*) _fail "drift relatado em estado clean" ""; return 1 ;;
  esac
}

# ==== --fix remove MISSING; preserva EDITED e ORPHAN ====

scenario_doctor_fix_remove_missing() {
  _h="$TMPDIR_TEST/h"
  _r="$TMPDIR_TEST/r"
  _make_release "$_r" || { _error "fixture" ""; return 2; }
  _install_v1 "$_h" "$_r"

  rm -rf "$_h/.claude/skills/bar"           # MISSING
  printf 'edit\n' >> "$_h/.claude/skills/foo/SKILL.md"  # EDITED
  mkdir -p "$_h/.claude/skills/orphan-skill"
  printf '\n' > "$_h/.claude/skills/orphan-skill/SKILL.md"  # ORPHAN

  _run_doctor "$_h" --fix
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "--fix exit" "esperado 0, obtido $_CAPTURED_EXIT; $_CAPTURED_STDERR"
    return 1
  fi
  assert_stderr_contains "removida entry MISSING bar" || return 1

  # Manifest: bar deve estar fora; foo e baz preservadas
  _mf="$_h/.claude/skills/.cstk-manifest"
  grep -q '^bar	' "$_mf" && { _fail "bar nao removida do manifest" ""; return 1; }
  grep -q '^foo	' "$_mf" || { _fail "foo removida indevidamente" ""; return 1; }
  grep -q '^baz	' "$_mf" || { _fail "baz removida indevidamente" ""; return 1; }
  # foo edit preservada (FR-007 / FR-008 — doctor nao toca conteudo)
  grep -q 'edit$' "$_h/.claude/skills/foo/SKILL.md" \
    || { _fail "foo edit perdida" ""; return 1; }
  # orphan preservada
  [ -d "$_h/.claude/skills/orphan-skill" ] \
    || { _fail "orphan removida (FR-007 violado)" ""; return 1; }
}

# ==== Re-rodar doctor apos --fix mostra menos drift ====

scenario_doctor_apos_fix_menos_drift() {
  _h="$TMPDIR_TEST/h"
  _r="$TMPDIR_TEST/r"
  _make_release "$_r" || { _error "fixture" ""; return 2; }
  _install_v1 "$_h" "$_r"

  rm -rf "$_h/.claude/skills/bar"
  printf 'edit\n' >> "$_h/.claude/skills/foo/SKILL.md"
  mkdir -p "$_h/.claude/skills/orphan-skill"

  _run_doctor "$_h" --fix
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "fix exit" ""; return 1; }

  _run_doctor "$_h"  # sem --fix; deve achar EDITED + ORPHAN ainda
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "post-fix re-doctor exit" "esperado 1 (EDITED+ORPHAN remanescentes), obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "missing: 0" || return 1
  assert_stderr_contains "edited:  1" || return 1
  assert_stderr_contains "orphan:  1" || return 1
}

# ==== Manifest ausente => exit 0 (nada a verificar) ====

scenario_doctor_manifest_ausente() {
  _h="$TMPDIR_TEST/h"
  _run_doctor "$_h"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "manifest ausente exit" "esperado 0, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "ok:      0" || return 1
}

# ==== Help ====

scenario_doctor_help() {
  _run_doctor "$TMPDIR_TEST/h" --help
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "help exit" "$_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "cstk doctor" || return 1
}

# ==== Args invalidos ====

scenario_doctor_arg_posicional_invalido() {
  _run_doctor "$TMPDIR_TEST/h" foo
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "arg posicional exit" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_doctor_scope_invalido() {
  _run_doctor "$TMPDIR_TEST/h" --scope outro
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "--scope invalido exit" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# `cstk doctor --deps` (feature state-backend-config, FASE 4, task 4.3.4).
# Cobre quickstart Scenario 6 (6a/6b/6c). Relatorio SEMPRE em STDOUT (nao
# stderr — diferente do relatorio de drift acima), read-only.
# ---------------------------------------------------------------------------

MIN_SQLITE_VER="3.45.1"

_dd_real_sqlite3_adequate() {
  command -v sqlite3 >/dev/null 2>&1 || return 1
  _v=$(sqlite3 --version 2>/dev/null | cut -d' ' -f1) || return 1
  _va=$(printf '%s' "$_v" | cut -d'.' -f1); _vb=$(printf '%s' "$_v" | cut -d'.' -f2); _vc=$(printf '%s' "$_v" | cut -d'.' -f3)
  _ma=$(printf '%s' "$MIN_SQLITE_VER" | cut -d'.' -f1); _mb=$(printf '%s' "$MIN_SQLITE_VER" | cut -d'.' -f2); _mc=$(printf '%s' "$MIN_SQLITE_VER" | cut -d'.' -f3)
  [ "${_va:-0}" -gt "${_ma:-0}" ] 2>/dev/null && return 0
  [ "${_va:-0}" -lt "${_ma:-0}" ] 2>/dev/null && return 1
  [ "${_vb:-0}" -gt "${_mb:-0}" ] 2>/dev/null && return 0
  [ "${_vb:-0}" -lt "${_mb:-0}" ] 2>/dev/null && return 1
  [ "${_vc:-0}" -ge "${_mc:-0}" ] 2>/dev/null
}

_run_doctor_deps() {
  _h=$1; shift
  capture env HOME="$_h" CSTK_LIB="$CSTK_LIB" sh -c '
    . "$CSTK_LIB/doctor.sh"; doctor_main "$@"
  ' doctor_deps_test --deps "$@"
}

# 6c — config global ausente ("nunca configurado"): NUNCA e anomalia,
# independente das dependencias — exit 0, motivo nunca-configurado, backend
# efetivo json (FR-008).
scenario_doctor_deps_nunca_configurado_exit0() {
  _h="$TMPDIR_TEST/h-nunca-configurado"
  mkdir -p "$_h"
  _run_doctor_deps "$_h"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "6c exit" "esperado 0, obtido $_CAPTURED_EXIT; $_CAPTURED_STDOUT / $_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "reason:            nunca-configurado" || return 1
  assert_stdout_contains "effective_backend: json" || return 1
}

# 6a — sem anomalia, com state_backend=sqlite declarado e dependencia REAL
# adequada: exit 0; stdout lista sqlite3+jq com presenca/versao, backend
# efetivo, motivo.
scenario_doctor_deps_sem_anomalia_configurado_adequado_exit0() {
  _dd_real_sqlite3_adequate || { printf '# skip: sqlite3 real >= %s indisponivel\n' "$MIN_SQLITE_VER"; return 0; }
  command -v jq >/dev/null 2>&1 || { printf '# skip: jq indisponivel\n'; return 0; }
  _h="$TMPDIR_TEST/h-adequado"
  mkdir -p "$_h/.claude/cstk"
  printf 'state_backend=sqlite\n' > "$_h/.claude/cstk/config"
  _run_doctor_deps "$_h"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "6a exit" "esperado 0, obtido $_CAPTURED_EXIT; $_CAPTURED_STDOUT / $_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "sqlite3: presente=sim" || return 1
  assert_stdout_contains "jq:      presente=sim" || return 1
  assert_stdout_contains "reason:            configurado-dependencia-adequada" || return 1
  assert_stdout_contains "effective_backend: sqlite" || return 1
  case "$_CAPTURED_STDOUT" in
    *"[ANOMALY]"*) _fail "nao deveria reportar anomalia" "$_CAPTURED_STDOUT"; return 1 ;;
  esac
}

# 6b — com anomalia: state_backend=sqlite declarado, sqlite3 abaixo do
# minimo (stub controlado) — exit NAO-ZERO, e o relatorio E EMITIDO mesmo
# assim (gate de CI precisa dizer o que falhou na mesma execucao).
scenario_doctor_deps_com_anomalia_versao_baixa_exit_nao_zero() {
  _h="$TMPDIR_TEST/h-anomalia"
  mkdir -p "$_h/.claude/cstk"
  printf 'state_backend=sqlite\n' > "$_h/.claude/cstk/config"
  _stub="$TMPDIR_TEST/stub-deps-low"
  mkdir -p "$_stub"
  cat > "$_stub/sqlite3" <<'EOF'
#!/bin/sh
printf '3.40.0 2024-01-01 00:00:00 deadbeef\n'
EOF
  chmod +x "$_stub/sqlite3"
  capture env HOME="$_h" PATH="$_stub:$PATH" CSTK_LIB="$CSTK_LIB" sh -c '
    . "$CSTK_LIB/doctor.sh"; doctor_main --deps
  '
  [ "$_CAPTURED_EXIT" != 0 ] || { _fail "6b exit" "esperado nao-zero, obtido 0; $_CAPTURED_STDOUT"; return 1; }
  assert_stdout_contains "reason:            configurado-dependencia-abaixo-do-minimo" || return 1
  assert_stdout_contains "effective_backend: json" || return 1
  assert_stdout_contains "[ANOMALY]" \
    || { _fail "relatorio deveria ser emitido mesmo com anomalia (gate de CI)" "$_CAPTURED_STDOUT"; return 1; }
}

# --deps e --fix/--scope continuam com comportamento inalterado (aditivo).
scenario_doctor_deps_nao_interfere_com_fix_scope() {
  _h="$TMPDIR_TEST/h"
  _r="$TMPDIR_TEST/r"
  _make_release "$_r" || { _error "fixture" ""; return 2; }
  _install_v1 "$_h" "$_r"
  # sem --deps: fluxo normal de drift, inalterado.
  _run_doctor "$_h"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "fluxo normal sem --deps deveria seguir igual" "exit=$_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "ok:      3" || return 1
}

# ==== Distribution Paths (feature claude-plugin-packaging FASE 6, task
# 6.3.4) — os 6 estados + nao-regressao do caso classic-only (secao
# omitida). ====

# _run_doctor_in HOME PROJDIR ARGS...: variante de _run_doctor que RODA
# doctor_main com cwd=PROJDIR (necessario p/ o check de duplicated-hooks,
# que le ./.claude/settings.json relativo ao cwd).
_run_doctor_in() {
  _rdi_home=$1; shift
  _rdi_proj=$1; shift
  capture env HOME="$_rdi_home" CSTK_LIB="$CSTK_LIB" sh -c '
    cd "$1" && shift && . "$CSTK_LIB/doctor.sh" && doctor_main "$@"
  ' doctor_test "$_rdi_proj" "$@"
}

# _dp_plugin_home HOME_DIR: registra "cstk@cstk" instalado+habilitado em
# HOME_DIR/.claude/{plugins,settings.json}; installPath aponta para
# HOME_DIR/plugin-install (sem popular skills/ — cada scenario decide).
_dp_plugin_home() {
  _dph_home=$1
  _dph_ip="$_dph_home/plugin-install"
  mkdir -p "$_dph_home/.claude/plugins" "$_dph_ip"
  cat > "$_dph_home/.claude/plugins/installed_plugins.json" <<EOF
{"version":2,"plugins":{"cstk@cstk":[{"scope":"user","installPath":"$_dph_ip","installedAt":"2026-08-01T00:00:00.000Z","lastUpdated":"2026-08-08T00:00:00.000Z"}]}}
EOF
  cat > "$_dph_home/.claude/settings.json" <<'EOF'
{"enabledPlugins": {"cstk@cstk": true}}
EOF
  printf '%s' "$_dph_ip"
}

# _dp_fill_skills DIR CONTENT_TAG: popula DIR/skills/foo/SKILL.md com
# conteudo derivado de CONTENT_TAG (mesmo tag em 2 dirs -> mesmo hash_dir).
_dp_fill_skills() {
  mkdir -p "$1/skills/foo"
  printf '# foo (%s)\n' "$2" > "$1/skills/foo/SKILL.md"
}

scenario_doctor_distribution_paths_omitida_sem_plugin() {
  _h="$TMPDIR_TEST/dp-h-none"
  mkdir -p "$_h/.claude/skills"
  _proj="$TMPDIR_TEST/dp-proj-none"
  mkdir -p "$_proj"
  _run_doctor_in "$_h" "$_proj"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sem plugin exit" "$_CAPTURED_EXIT / $_CAPTURED_STDERR"; return 1; }
  case "$_CAPTURED_STDERR" in
    *"Distribution Paths"*) _fail "secao nao deveria aparecer sem plugin" "$_CAPTURED_STDERR"; return 1 ;;
  esac
}

scenario_doctor_distribution_paths_plugin_only() {
  if ! command -v jq >/dev/null 2>&1; then _error "no_jq" "jq indisponivel"; return 2; fi
  _h="$TMPDIR_TEST/dp-h-plugin-only"
  _ip=$(_dp_plugin_home "$_h")
  _dp_fill_skills "$_ip" "v1"
  # SEM ~/.claude/skills classico.
  _proj="$TMPDIR_TEST/dp-proj-plugin-only"
  mkdir -p "$_proj"
  _run_doctor_in "$_h" "$_proj"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "plugin-only exit" "$_CAPTURED_EXIT / $_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains "[plugin-only]" || return 1
}

# _dp_mirror_classic_skills_into HOME_DIR TARGET_DIR: copia
# HOME_DIR/.claude/skills/* (foo/bar/baz instalados por _install_v1, todos
# "OK" no manifest) para TARGET_DIR/skills — usado para montar o lado
# "plugin" com conteudo IDENTICO ao classico, sem incorrer em drift de
# manifest (que geraria ORPHAN/EDITED incidental e confundiria o teste).
_dp_mirror_classic_skills_into() {
  mkdir -p "$2/skills"
  cp -R "$1/.claude/skills/." "$2/skills/" 2>/dev/null || :
}

scenario_doctor_distribution_paths_aligned() {
  if ! command -v jq >/dev/null 2>&1; then _error "no_jq" "jq indisponivel"; return 2; fi
  _h="$TMPDIR_TEST/dp-h-aligned"
  _r="$TMPDIR_TEST/dp-r-aligned"
  _make_release "$_r" || { _error "fixture" ""; return 2; }
  _install_v1 "$_h" "$_r"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "install classico" "$_CAPTURED_EXIT"; return 1; }
  _ip=$(_dp_plugin_home "$_h")
  _dp_mirror_classic_skills_into "$_h" "$_ip"
  _proj="$TMPDIR_TEST/dp-proj-aligned"
  mkdir -p "$_proj"
  _run_doctor_in "$_h" "$_proj"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "aligned exit" "esperado 0, obtido $_CAPTURED_EXIT / $_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains "[aligned]" || return 1
}

# Regressao do caso de campo: 13 skills da Cloudflare apareceram em
# ~/.claude/skills (espaco COMPARTILHADO) e o Distribution Paths passou a
# acusar `diverged` eternamente, gateando `cstk doctor` com exit 1 sem
# nenhuma acao possivel — os catalogos estavam identicos no que e do cstk.
scenario_doctor_dp_aligned_apesar_de_skills_de_terceiros() {
  if ! command -v jq >/dev/null 2>&1; then _error "no_jq" "jq indisponivel"; return 2; fi
  _h="$TMPDIR_TEST/dp-h-terceiros"
  _r="$TMPDIR_TEST/dp-r-terceiros"
  _make_release "$_r" || { _error "fixture" ""; return 2; }
  _install_v1 "$_h" "$_r"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "install classico" "$_CAPTURED_EXIT"; return 1; }
  _ip=$(_dp_plugin_home "$_h")
  _dp_mirror_classic_skills_into "$_h" "$_ip"

  # Terceiros SO no classico (foi o que o plugin da Cloudflare fez).
  for _n in cloudflare wrangler web-perf; do
    mkdir -p "$_h/.claude/skills/$_n"
    printf '# nao e do cstk\n' > "$_h/.claude/skills/$_n/SKILL.md"
  done
  # `evals/` SO no plugin (build-release.sh remove do tarball classico).
  mkdir -p "$_ip/skills/foo/evals"
  printf '# fixture dev-only\n' > "$_ip/skills/foo/evals/caso.md"

  _proj="$TMPDIR_TEST/dp-proj-terceiros"
  mkdir -p "$_proj"
  _run_doctor_in "$_h" "$_proj"
  assert_stderr_contains "[aligned]" || return 1
  [ "$_CAPTURED_EXIT" = 0 ] \
    || { _fail "exit" "terceiros + evals NAO podem gatear; obtido $_CAPTURED_EXIT / $_CAPTURED_STDERR"; return 1; }
  return 0
}

scenario_doctor_distribution_paths_diverged() {
  if ! command -v jq >/dev/null 2>&1; then _error "no_jq" "jq indisponivel"; return 2; fi
  _h="$TMPDIR_TEST/dp-h-diverged"
  _r="$TMPDIR_TEST/dp-r-diverged"
  _make_release "$_r" || { _error "fixture" ""; return 2; }
  _install_v1 "$_h" "$_r"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "install classico" "$_CAPTURED_EXIT"; return 1; }
  _ip=$(_dp_plugin_home "$_h")
  _dp_mirror_classic_skills_into "$_h" "$_ip"
  # Diverge SO o lado plugin (classico permanece "OK" no manifest).
  printf '# foo — versao diferente no plugin\n' > "$_ip/skills/foo/SKILL.md"
  _proj="$TMPDIR_TEST/dp-proj-diverged"
  mkdir -p "$_proj"
  _run_doctor_in "$_h" "$_proj"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "diverged exit" "esperado 1, obtido $_CAPTURED_EXIT / $_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains "[diverged]" || return 1
  case "$_CAPTURED_STDERR" in
    *"[ORPHAN]"*|*"[EDITED]"*|*"[MISSING]"*)
      _fail "diverged nao deveria ter drift classico incidental" "$_CAPTURED_STDERR"
      return 1
      ;;
  esac
}

scenario_doctor_distribution_paths_duplicated_hooks() {
  if ! command -v jq >/dev/null 2>&1; then _error "no_jq" "jq indisponivel"; return 2; fi
  _h="$TMPDIR_TEST/dp-h-duplicated"
  _ip=$(_dp_plugin_home "$_h")
  _dp_fill_skills "$_ip" "same"
  _dp_fill_skills "$_h/.claude" "same"
  _proj="$TMPDIR_TEST/dp-proj-duplicated"
  mkdir -p "$_proj/.claude"
  printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"pretooluse-bash-guard.sh"}]}]}}\n' \
    > "$_proj/.claude/settings.json"
  _run_doctor_in "$_h" "$_proj"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "duplicated-hooks exit" "esperado 1, obtido $_CAPTURED_EXIT / $_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains "[duplicated-hooks]" || return 1
}

scenario_doctor_distribution_paths_undetermined_installed_json_corrompido() {
  # Scenario 7 do quickstart: settings.json diz habilitado, mas
  # installed_plugins.json esta corrompido -> secao MOSTRADA (gate e o
  # sinal fraco), status=undetermined, exit 0 (aviso, nunca erro fatal).
  if ! command -v jq >/dev/null 2>&1; then _error "no_jq" "jq indisponivel"; return 2; fi
  _h="$TMPDIR_TEST/dp-h-undetermined"
  mkdir -p "$_h/.claude/plugins" "$_h/.claude/skills"
  printf '{' > "$_h/.claude/plugins/installed_plugins.json"
  cat > "$_h/.claude/settings.json" <<'EOF'
{"enabledPlugins": {"cstk@cstk": true}}
EOF
  _proj="$TMPDIR_TEST/dp-proj-undetermined"
  mkdir -p "$_proj"
  _run_doctor_in "$_h" "$_proj"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "undetermined exit" "esperado 0, obtido $_CAPTURED_EXIT / $_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains "[undetermined]" || return 1
}

run_all_scenarios
