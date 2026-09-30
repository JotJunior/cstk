#!/bin/sh
# test_orchestrator-refs-distribution.sh — distribuicao das referencias de fase
# dos orquestradores nos dois canais (tarball/`cstk install` e plugin nativo).
#
# Ref: docs/specs/orchestrator-slim/spec.md FR-008, FR-009, SC-004, US4
#      docs/specs/orchestrator-slim/quickstart.md Cenario 4
#      docs/specs/orchestrator-slim/research.md Decision 1
#
# Cobre: (1) o tarball de release (`scripts/build-release.sh`) contem
# catalog/skills/agente-00c-runtime/references/orchestrators/<o>/<p>.md para
# CADA marcador ORCH-REF dos dois prompts-base; (2) o skill dir extraido do
# tarball, copiado (`cp -R`) para um $HOME temporario, resolve todos os
# marcadores via o `orchestrator-refs.sh` COPIADO (nunca o do repositorio nem
# o ~/.claude real); (3) error case: referencia apagada na copia => `path`
# sai com exit 1 e stdout vazio.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

BUILD_SCRIPT="$REPO_ROOT/scripts/build-release.sh"
AGENTS_DIR="$REPO_ROOT/plugins/cstk/agents"

# _markers: lista `<o>/<p>` unica dos marcadores ORCH-REF dos dois prompts-base.
_markers() {
  for _f in "$AGENTS_DIR/agente-00c-orchestrator.md" \
            "$AGENTS_DIR/agente-00c-feature-orchestrator.md"; do
    [ -f "$_f" ] || return 1
    grep -oE '<!-- ORCH-REF: (root|feature)/[a-z0-9-]+ -->' "$_f" \
      | sed -e 's/<!-- ORCH-REF: //' -e 's/ -->//'
  done | sort -u
}

# _build_and_extract <out-dir>: gera o tarball e extrai; imprime o dir raiz
# extraido (cstk-<version>/). Retorna != 0 em falha.
_build_and_extract() {
  _bd="$1"
  mkdir -p "$_bd/out" "$_bd/x"
  sh "$BUILD_SCRIPT" v0.0.0-refs --out "$_bd/out" >/dev/null 2>&1 || return 1
  tar -xzf "$_bd/out/cstk-0.0.0-refs.tar.gz" -C "$_bd/x" || return 1
  [ -d "$_bd/x/cstk-0.0.0-refs" ] || return 1
  printf '%s' "$_bd/x/cstk-0.0.0-refs"
}

# ==== Canal 1: tarball ====

scenario_tarball_contem_toda_referencia_dos_marcadores() {
  _root=$(_build_and_extract "$TMPDIR_TEST") \
    || { _fail "build/extract do tarball" "scripts/build-release.sh falhou"; return 1; }
  _list=$(_markers) || { _error "prompt-base ausente" "$AGENTS_DIR"; return 2; }
  [ -n "$_list" ] || { _fail "sem marcadores" "prompts-base"; return 1; }
  for _m in $_list; do
    _ref="$_root/catalog/skills/agente-00c-runtime/references/orchestrators/$_m.md"
    [ -f "$_ref" ] || { _fail "referencia ausente no tarball" "$_m -> $_ref"; return 1; }
    _last=$(tail -n 1 "$_ref")
    [ "$_last" = '<!-- ORCH-REF-END -->' ] \
      || { _fail "referencia truncada no tarball" "$_m termina em '$_last'"; return 1; }
  done
}

scenario_tarball_tem_o_script_de_resolucao() {
  _root=$(_build_and_extract "$TMPDIR_TEST") \
    || { _fail "build/extract do tarball" "scripts/build-release.sh falhou"; return 1; }
  _sc="$_root/catalog/skills/agente-00c-runtime/scripts"
  [ -f "$_sc/orchestrator-refs.sh" ] || { _fail "orchestrator-refs.sh ausente no tarball" "$_sc"; return 1; }
  [ -f "$_sc/_resolve-root.sh" ] || { _fail "_resolve-root.sh ausente no tarball" "$_sc"; return 1; }
}

# ==== Canal 1 (instalado): cp -R do skill dir do tarball em $HOME temporario ====

scenario_copia_instalada_resolve_todos_os_marcadores() {
  _root=$(_build_and_extract "$TMPDIR_TEST") \
    || { _fail "build/extract do tarball" "scripts/build-release.sh falhou"; return 1; }
  _home="$TMPDIR_TEST/home"
  mkdir -p "$_home/.claude/skills"
  cp -R "$_root/catalog/skills/agente-00c-runtime" "$_home/.claude/skills/agente-00c-runtime"
  _copy="$_home/.claude/skills/agente-00c-runtime/scripts/orchestrator-refs.sh"
  _real=$(cd "$_home/.claude/skills/agente-00c-runtime" && pwd)
  _n=0
  for _m in $(_markers); do
    _o=${_m%%/*}
    _p=${_m#*/}
    capture env -u CLAUDE_PLUGIN_ROOT HOME="$_home" sh "$_copy" path --orchestrator "$_o" --phase "$_p"
    [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "path $_m na copia instalada" "exit=$_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"; return 1; }
    [ "$_CAPTURED_STDOUT" = "$_real/references/orchestrators/$_m.md" ] \
      || { _fail "path $_m na copia instalada" "obtido $_CAPTURED_STDOUT (esperado sob a copia, nao o repositorio)"; return 1; }
    _n=$((_n + 1))
  done
  [ "$_n" -gt 0 ] || { _fail "nenhum marcador verificado" "copia instalada"; return 1; }
}

scenario_referencia_apagada_na_copia_exit_1_stdout_vazio() {
  _root=$(_build_and_extract "$TMPDIR_TEST") \
    || { _fail "build/extract do tarball" "scripts/build-release.sh falhou"; return 1; }
  _home="$TMPDIR_TEST/home"
  mkdir -p "$_home/.claude/skills"
  cp -R "$_root/catalog/skills/agente-00c-runtime" "$_home/.claude/skills/agente-00c-runtime"
  _copy="$_home/.claude/skills/agente-00c-runtime/scripts/orchestrator-refs.sh"
  _first=$(_markers | sed -n '1p')
  _o=${_first%%/*}
  _p=${_first#*/}
  rm -f "$_home/.claude/skills/agente-00c-runtime/references/orchestrators/$_first.md"
  capture env -u CLAUDE_PLUGIN_ROOT HOME="$_home" sh "$_copy" path --orchestrator "$_o" --phase "$_p"
  [ "$_CAPTURED_EXIT" -eq 1 ] || { _fail "exit com referencia apagada ($_first)" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout deveria ser vazio" "$_CAPTURED_STDOUT"; return 1; }
  # as demais referencias da copia continuam resolvendo (falha e por fase)
  _second=$(_markers | sed -n '2p')
  capture env -u CLAUDE_PLUGIN_ROOT HOME="$_home" sh "$_copy" path --orchestrator "${_second%%/*}" --phase "${_second#*/}"
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "outra referencia da copia" "exit=$_CAPTURED_EXIT ($_second)"; return 1; }
}

# ==== Canal 1 (instalador real): `cstk install --from file://<tarball>` ====

scenario_cstk_install_do_tarball_entrega_as_referencias() {
  _root=$(_build_and_extract "$TMPDIR_TEST") \
    || { _fail "build/extract do tarball" "scripts/build-release.sh falhou"; return 1; }
  _home="$TMPDIR_TEST/inst-home"
  mkdir -p "$_home"
  _url="file://$TMPDIR_TEST/out/cstk-0.0.0-refs.tar.gz"
  # CSTK_LIB do repositorio (nunca ~/.claude); HOME temporario isola o alvo.
  capture env HOME="$_home" CSTK_LIB="$REPO_ROOT/cli/lib" sh -c '
    . "$CSTK_LIB/install.sh"
    install_main "$@"
  ' install_test --from "$_url" agente-00c-runtime
  [ "$_CAPTURED_EXIT" -eq 0 ] \
    || { _fail "cstk install do tarball" "exit=$_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"; return 1; }
  _copy="$_home/.claude/skills/agente-00c-runtime/scripts/orchestrator-refs.sh"
  [ -f "$_copy" ] || { _fail "runtime nao instalado" "$_copy"; return 1; }
  _n=0
  for _m in $(_markers); do
    capture env -u CLAUDE_PLUGIN_ROOT HOME="$_home" sh "$_copy" path --orchestrator "${_m%%/*}" --phase "${_m#*/}"
    [ "$_CAPTURED_EXIT" -eq 0 ] \
      || { _fail "path $_m apos cstk install" "exit=$_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"; return 1; }
    case "$_CAPTURED_STDOUT" in
      "$_home"/.claude/skills/agente-00c-runtime/references/orchestrators/*) ;;
      *) _fail "path $_m fora do skill dir instalado" "$_CAPTURED_STDOUT"; return 1 ;;
    esac
    _n=$((_n + 1))
  done
  [ "$_n" -gt 0 ] || { _fail "nenhum marcador verificado" "cstk install"; return 1; }
}

# ==== Canal 2: plugin nativo (subtree plugins/cstk) ====

scenario_plugin_subtree_e_autocontido_para_o_resolvedor() {
  # O plugin instalado e SO o subtree plugins/cstk (nada da raiz do repo):
  # copiar o subtree para um dir isolado e resolver por CLAUDE_PLUGIN_ROOT.
  _plug="$TMPDIR_TEST/plugin-root"
  mkdir -p "$_plug"
  cp -R "$REPO_ROOT/plugins/cstk/." "$_plug/"
  _script="$_plug/skills/agente-00c-runtime/scripts/orchestrator-refs.sh"
  _real=$(cd "$_plug/skills/agente-00c-runtime" && pwd)
  _n=0
  for _m in $(_markers); do
    capture env CLAUDE_PLUGIN_ROOT="$_plug" HOME="$TMPDIR_TEST/nohome" sh "$_script" path --orchestrator "${_m%%/*}" --phase "${_m#*/}"
    [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "path $_m no subtree isolado" "exit=$_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"; return 1; }
    [ "$_CAPTURED_STDOUT" = "$_real/references/orchestrators/$_m.md" ] \
      || { _fail "path $_m no subtree isolado" "obtido $_CAPTURED_STDOUT"; return 1; }
    _n=$((_n + 1))
  done
  [ "$_n" -gt 0 ] || { _fail "nenhum marcador verificado" "subtree"; return 1; }
}

run_all_scenarios "$@"
