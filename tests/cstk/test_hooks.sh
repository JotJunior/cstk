#!/bin/sh
# test_hooks.sh — cobre cli/lib/hooks.sh (FASE 7.1).
#
# Cobre Scenarios 4 (jq presente) e 5 (jq ausente, settings.json
# pre-existente intocado). Usa PATH controlado via `env -i` para forcar
# ausencia de jq sem precisar desinstalar.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CSTK_LIB="$REPO_ROOT/cli/lib"
export CSTK_LIB

# _has_jq: checa se o ambiente tem jq disponivel (necessario para os
# cenarios "com jq"; sem jq, escapamos com ERROR para nao falsear PASS).
_has_jq() {
  command -v jq >/dev/null 2>&1
}

# _make_shim_path: cria dir em $TMPDIR_TEST/shimbin com symlinks para
# binarios POSIX essenciais (sh, mktemp, awk, etc.) EXCETO jq. Resolve
# o problema do approach antigo (filtrar dirs do PATH) que em ambientes
# CI Linux remove /usr/bin junto com jq, perdendo sh/awk/etc. Tambem
# usado em test_hooks-integration.sh — manter listas de binarios em sync.
_make_shim_path() {
  _shim="$TMPDIR_TEST/shimbin"
  mkdir -p "$_shim"
  for _cmd in sh mktemp awk sed grep find head printf cp mv rm mkdir \
              chmod ls dirname basename tr cut wc env command sort \
              uniq date cat tar gzip gunzip xz bzip2 curl shasum sha256sum; do
    _src=$(command -v "$_cmd" 2>/dev/null) || continue
    [ -n "$_src" ] || continue
    ln -sf "$_src" "$_shim/$_cmd" 2>/dev/null || :
  done
  printf '%s' "$_shim"
}

# ==== detect_jq ====

scenario_detect_jq_presente() {
  if ! _has_jq; then
    _error "no_jq" "jq nao disponivel — pulando cenario com-jq"
    return 2
  fi
  capture sh -c ". $CSTK_LIB/hooks.sh && detect_jq"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "detect com jq" "$_CAPTURED_EXIT"
    return 1
  fi
}

scenario_detect_jq_ausente() {
  _path_clean=$(_make_shim_path)
  # Normaliza exit via if/exit. Em dash + Ubuntu CI o pattern `cmd && detect_jq`
  # ocasionalmente exit 127 (causa nao-clara — possivelmente lookup de
  # `command` builtin via PATH sob env -i quando shim nao tem todos os
  # binarios resolvidos). if/exit forca exit 0 ou 1 deterministicamente.
  capture env -i PATH="$_path_clean" CSTK_LIB="$CSTK_LIB" sh -c '
    . "$CSTK_LIB/hooks.sh"
    if detect_jq; then exit 0; else exit 1; fi
  '
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "detect sem jq" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

# ==== merge_settings (Scenario 4: jq presente) ====

scenario_merge_target_inexistente_copia() {
  if ! _has_jq; then _error "no_jq" "skip"; return 2; fi
  printf '{"foo":1}\n' > "$TMPDIR_TEST/source.json"
  capture sh -c ". $CSTK_LIB/hooks.sh && merge_settings $TMPDIR_TEST/target.json $TMPDIR_TEST/source.json"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "merge cria target" "$_CAPTURED_STDERR"; return 1; }
  [ -f "$TMPDIR_TEST/target.json" ] || { _fail "target nao criado" ""; return 1; }
  # Conteudo == source
  diff -q "$TMPDIR_TEST/target.json" "$TMPDIR_TEST/source.json" >/dev/null \
    || { _fail "target != source" ""; return 1; }
}

scenario_merge_target_existe_target_vence() {
  if ! _has_jq; then _error "no_jq" "skip"; return 2; fi
  printf '{"existing":"keep","conflict":"OLD"}\n' > "$TMPDIR_TEST/target.json"
  printf '{"new":"add","conflict":"NEW","nested":{"x":1}}\n' > "$TMPDIR_TEST/source.json"
  capture sh -c ". $CSTK_LIB/hooks.sh && merge_settings $TMPDIR_TEST/target.json $TMPDIR_TEST/source.json"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "merge exit" "$_CAPTURED_STDERR"; return 1; }

  # Target deve ter: existing (preservado), new (adicionado), nested (adicionado),
  # e conflict deve ser OLD (target vence).
  jq -e '.existing == "keep"' "$TMPDIR_TEST/target.json" >/dev/null \
    || { _fail "existing perdido" ""; return 1; }
  jq -e '.new == "add"' "$TMPDIR_TEST/target.json" >/dev/null \
    || { _fail "new nao adicionado" ""; return 1; }
  jq -e '.nested.x == 1' "$TMPDIR_TEST/target.json" >/dev/null \
    || { _fail "nested nao adicionado" ""; return 1; }
  jq -e '.conflict == "OLD"' "$TMPDIR_TEST/target.json" >/dev/null \
    || { _fail "target nao venceu conflito" "$(cat $TMPDIR_TEST/target.json)"; return 1; }
  # Backup criado
  [ -f "$TMPDIR_TEST/target.json.bak" ] || { _fail "backup ausente" ""; return 1; }
}

# ==== merge_settings rejeita JSON invalido ====

scenario_merge_source_invalido_aborta() {
  if ! _has_jq; then _error "no_jq" "skip"; return 2; fi
  printf '{"target":1}\n' > "$TMPDIR_TEST/target.json"
  printf 'not json\n' > "$TMPDIR_TEST/bad.json"
  capture sh -c ". $CSTK_LIB/hooks.sh && merge_settings $TMPDIR_TEST/target.json $TMPDIR_TEST/bad.json"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "JSON ruim exit" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  # Target intacto
  jq -e '.target == 1' "$TMPDIR_TEST/target.json" >/dev/null \
    || { _fail "target alterado em falha" ""; return 1; }
}

# ==== merge_settings sem jq aborta (Scenario 5 — guarda defensiva FR-009d) ====

scenario_merge_sem_jq_aborta() {
  printf '{"x":1}\n' > "$TMPDIR_TEST/target.json"
  printf '{"y":2}\n' > "$TMPDIR_TEST/source.json"
  _path_clean=$(_make_shim_path)
  capture env -i PATH="$_path_clean" CSTK_LIB="$CSTK_LIB" sh -c '
    . "$CSTK_LIB/hooks.sh"
    merge_settings "$1" "$2"
  ' merge_test "$TMPDIR_TEST/target.json" "$TMPDIR_TEST/source.json"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "sem jq exit" "esperado 1, obtido $_CAPTURED_EXIT; $_CAPTURED_STDERR"
    return 1
  fi
  assert_stderr_contains "exige jq" || return 1
  # Target intacto
  if ! grep -q '"x":1' "$TMPDIR_TEST/target.json"; then
    _fail "target alterado sem jq" ""
    return 1
  fi
}

# ==== print_paste_block: imprime sem escrever ====

scenario_print_paste_block_emite_e_nao_escreve() {
  printf '{"hooks":{"x":1}}\n' > "$TMPDIR_TEST/source.json"
  printf '{"untouched":true}\n' > "$TMPDIR_TEST/target.json"
  _target_sha_before=$(shasum -a 256 "$TMPDIR_TEST/target.json" 2>/dev/null \
    || sha256sum "$TMPDIR_TEST/target.json")

  capture sh -c ". $CSTK_LIB/hooks.sh && print_paste_block $TMPDIR_TEST/target.json $TMPDIR_TEST/source.json"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "paste-block exit" "$_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "Hooks to merge manually" || return 1
  assert_stderr_contains "BEGIN PAYLOAD" || return 1
  assert_stderr_contains '"hooks":{"x":1}' || return 1
  # Target intacto
  _target_sha_after=$(shasum -a 256 "$TMPDIR_TEST/target.json" 2>/dev/null \
    || sha256sum "$TMPDIR_TEST/target.json")
  if [ "$_target_sha_before" != "$_target_sha_after" ]; then
    _fail "paste-block alterou target (FR-009d violado)" ""
    return 1
  fi
}

# ==== Args invalidos ====

scenario_merge_args_invalidos() {
  capture sh -c ". $CSTK_LIB/hooks.sh && merge_settings only-one"
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "merge 1 arg exit" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_paste_args_invalidos() {
  capture sh -c ". $CSTK_LIB/hooks.sh && print_paste_block"
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "paste 0 args exit" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

# ==== Source ausente ====

scenario_merge_source_ausente() {
  if ! _has_jq; then _error "no_jq" "skip"; return 2; fi
  capture sh -c ". $CSTK_LIB/hooks.sh && merge_settings $TMPDIR_TEST/t.json $TMPDIR_TEST/nao-existe.json"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "source ausente exit" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "nao encontrado" || return 1
}

# ==== apply_guard_hooks (enforced-guards US1, task 2.4.4) ====

# _guard_src_fixture: monta um src_dir minimo com pretooluse-bash-guard.sh +
# posttooluse-tool-call-tick.sh + posttooluse-agent-usage.sh (conteudo
# trivial, so precisa existir p/ cp) + settings.snippet.json (PreToolUse +
# PostToolUse, como o catalogo real).
_guard_src_fixture() {
  _gsf_dir="$TMPDIR_TEST/guard-src"
  mkdir -p "$_gsf_dir"
  printf '#!/bin/sh\nexit 0\n' > "$_gsf_dir/pretooluse-bash-guard.sh"
  chmod +x "$_gsf_dir/pretooluse-bash-guard.sh"
  printf '#!/bin/sh\nexit 0\n' > "$_gsf_dir/posttooluse-tool-call-tick.sh"
  chmod +x "$_gsf_dir/posttooluse-tool-call-tick.sh"
  printf '#!/bin/sh\nexit 0\n' > "$_gsf_dir/posttooluse-agent-usage.sh"
  chmod +x "$_gsf_dir/posttooluse-agent-usage.sh"
  printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"x","timeout":5}]}],"PostToolUse":[{"matcher":"*","hooks":[{"type":"command","command":"y","timeout":5}]},{"matcher":"Agent","hooks":[{"type":"command","command":"z","timeout":5}]}]}}\n' \
    > "$_gsf_dir/settings.snippet.json"
  printf '%s' "$_gsf_dir"
}

scenario_apply_guard_hooks_merged_com_jq() {
  if ! _has_jq; then _error "no_jq" "skip"; return 2; fi
  _src=$(_guard_src_fixture)
  _dest="$TMPDIR_TEST/claude-root"
  capture sh -c ". $CSTK_LIB/hooks.sh && apply_guard_hooks '$_src' '$_dest' 0"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "apply exit" "$_CAPTURED_EXIT / $_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "merged" || return 1
  [ -x "$_dest/hooks/pretooluse-bash-guard.sh" ] || { _fail "hook nao copiado/executavel" ""; return 1; }
  jq -e '.hooks.PreToolUse[0].matcher == "Bash"' "$_dest/settings.json" >/dev/null \
    || { _fail "settings.json nao mesclado" "$(cat "$_dest/settings.json" 2>/dev/null)"; return 1; }
}

scenario_apply_guard_hooks_sem_jq_paste_instructed() {
  _src=$(_guard_src_fixture)
  _dest="$TMPDIR_TEST/claude-root"
  _path_clean=$(_make_shim_path)
  capture env -i PATH="$_path_clean" CSTK_LIB="$CSTK_LIB" sh -c '
    . "$CSTK_LIB/hooks.sh"
    apply_guard_hooks "$1" "$2" 0
  ' guard_test "$_src" "$_dest"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "apply exit" "$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "paste-instructed" || return 1
  assert_stderr_contains "BEGIN PAYLOAD" || return 1
  [ -x "$_dest/hooks/pretooluse-bash-guard.sh" ] || { _fail "hook nao copiado sem jq" ""; return 1; }
  [ -f "$_dest/settings.json" ] && { _fail "settings.json nao deveria existir sem jq" ""; return 1; }
  return 0
}

scenario_apply_guard_hooks_dry_run_nao_escreve() {
  _src=$(_guard_src_fixture)
  _dest="$TMPDIR_TEST/claude-root"
  capture sh -c ". $CSTK_LIB/hooks.sh && apply_guard_hooks '$_src' '$_dest' 1"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "apply exit" "$_CAPTURED_EXIT"; return 1; }
  [ -e "$_dest" ] && { _fail "dry-run escreveu em disco" "$(find "$_dest" 2>/dev/null)"; return 1; }
  return 0
}

scenario_apply_guard_hooks_src_ausente_not_applicable() {
  capture sh -c ". $CSTK_LIB/hooks.sh && apply_guard_hooks '$TMPDIR_TEST/nao-existe' '$TMPDIR_TEST/dest' 0"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "apply exit" "$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "not-applicable" || return 1
}

scenario_apply_guard_hooks_script_ausente_not_applicable() {
  _src="$TMPDIR_TEST/guard-src-empty"
  mkdir -p "$_src"
  capture sh -c ". $CSTK_LIB/hooks.sh && apply_guard_hooks '$_src' '$TMPDIR_TEST/dest' 0"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "apply exit" "$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "not-applicable" || return 1
}

scenario_apply_guard_hooks_sem_snippet_hooks_only() {
  _src="$TMPDIR_TEST/guard-src-nosnippet"
  mkdir -p "$_src"
  printf '#!/bin/sh\nexit 0\n' > "$_src/pretooluse-bash-guard.sh"
  chmod +x "$_src/pretooluse-bash-guard.sh"
  _dest="$TMPDIR_TEST/claude-root"
  capture sh -c ". $CSTK_LIB/hooks.sh && apply_guard_hooks '$_src' '$_dest' 0"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "apply exit" "$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "hooks-only" || return 1
  [ -x "$_dest/hooks/pretooluse-bash-guard.sh" ] || { _fail "hook nao copiado" ""; return 1; }
}

scenario_apply_guard_hooks_idempotente() {
  if ! _has_jq; then _error "no_jq" "skip"; return 2; fi
  _src=$(_guard_src_fixture)
  _dest="$TMPDIR_TEST/claude-root"
  capture sh -c ". $CSTK_LIB/hooks.sh && apply_guard_hooks '$_src' '$_dest' 0"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "1a chamada exit" "$_CAPTURED_EXIT"; return 1; }
  capture sh -c ". $CSTK_LIB/hooks.sh && apply_guard_hooks '$_src' '$_dest' 0"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "2a chamada (resume) exit" "$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "merged" || return 1
  jq -e '.hooks.PreToolUse[0].matcher == "Bash"' "$_dest/settings.json" >/dev/null \
    || { _fail "settings.json corrompido apos 2a chamada" "$(cat "$_dest/settings.json")"; return 1; }
}

scenario_apply_guard_hooks_args_invalidos() {
  capture sh -c ". $CSTK_LIB/hooks.sh && apply_guard_hooks only-one-arg"
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "args invalidos exit" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stdout_contains "error" || return 1
}

scenario_apply_guard_hooks_copia_posttooluse_tick() {
  if ! _has_jq; then _error "no_jq" "skip"; return 2; fi
  _src=$(_guard_src_fixture)
  _dest="$TMPDIR_TEST/claude-root"
  capture sh -c ". $CSTK_LIB/hooks.sh && apply_guard_hooks '$_src' '$_dest' 0"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "apply exit" "$_CAPTURED_EXIT / $_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "merged" || return 1
  [ -x "$_dest/hooks/posttooluse-tool-call-tick.sh" ] \
    || { _fail "tick hook nao copiado/executavel" ""; return 1; }
  jq -e '.hooks.PostToolUse[0].matcher == "*"' "$_dest/settings.json" >/dev/null \
    || { _fail "settings.json sem bloco PostToolUse" "$(cat "$_dest/settings.json" 2>/dev/null)"; return 1; }
}

# Provisionamento do hook de metrica de uso de tokens por spawn
# (wave-token-metrics FASE 2, tarefa 2.2.4) — mesmo padrao do tick acima.
scenario_apply_guard_hooks_copia_posttooluse_agent_usage() {
  if ! _has_jq; then _error "no_jq" "skip"; return 2; fi
  _src=$(_guard_src_fixture)
  _dest="$TMPDIR_TEST/claude-root"
  capture sh -c ". $CSTK_LIB/hooks.sh && apply_guard_hooks '$_src' '$_dest' 0"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "apply exit" "$_CAPTURED_EXIT / $_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "merged" || return 1
  [ -x "$_dest/hooks/posttooluse-agent-usage.sh" ] \
    || { _fail "agent-usage hook nao copiado/executavel" ""; return 1; }
  jq -e '[.hooks.PostToolUse[] | select(.matcher == "Agent")] | length == 1' "$_dest/settings.json" >/dev/null \
    || { _fail "settings.json sem entrada PostToolUse/Agent" "$(cat "$_dest/settings.json" 2>/dev/null)"; return 1; }
}

# Catalogo ANTIGO (skill sem o hook de metrica): provisionamento do guard
# segue integral — o tick e best-effort e sua ausencia nao e erro.
scenario_apply_guard_hooks_catalogo_antigo_sem_tick() {
  if ! _has_jq; then _error "no_jq" "skip"; return 2; fi
  _src="$TMPDIR_TEST/guard-src-old"
  mkdir -p "$_src"
  printf '#!/bin/sh\nexit 0\n' > "$_src/pretooluse-bash-guard.sh"
  chmod +x "$_src/pretooluse-bash-guard.sh"
  printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"x","timeout":5}]}]}}\n' \
    > "$_src/settings.snippet.json"
  _dest="$TMPDIR_TEST/claude-root-old"
  capture sh -c ". $CSTK_LIB/hooks.sh && apply_guard_hooks '$_src' '$_dest' 0"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "apply exit" "$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "merged" || return 1
  [ -x "$_dest/hooks/pretooluse-bash-guard.sh" ] || { _fail "guard nao copiado" ""; return 1; }
  [ -f "$_dest/hooks/posttooluse-tool-call-tick.sh" ] \
    && { _fail "tick fantasma" "catalogo antigo nao traz o tick; nada a copiar"; return 1; }
  [ -f "$_dest/hooks/posttooluse-agent-usage.sh" ] \
    && { _fail "agent-usage fantasma" "catalogo antigo nao traz o hook de uso; nada a copiar"; return 1; }
  return 0
}

# ==== hooks_main — comando `cstk hooks install` (5.27.0) ====
#
# Motivacao: ate 5.26.0 o unico caminho para provisionar os hooks 00c era
# `cstk install --scope project agente-00c-runtime`, que tambem copiava
# skill+6 commands+7 agents para dentro do repo-alvo. `cstk hooks install`
# faz SO os hooks — delegando integralmente a apply_guard_hooks(), sem
# regra nova.

# _hooks_catalog_fixture: catalogo minimo no layout que hooks_main espera
# (<catalog>/skills/agente-00c-runtime/hooks/), reusando _guard_src_fixture.
_hooks_catalog_fixture() {
  _hcf_cat="$TMPDIR_TEST/catalog"
  _hcf_hooks="$_hcf_cat/skills/agente-00c-runtime/hooks"
  mkdir -p "$_hcf_hooks"
  _hcf_src=$(_guard_src_fixture)
  cp "$_hcf_src"/* "$_hcf_hooks/" 2>/dev/null || :
  chmod +x "$_hcf_hooks"/*.sh 2>/dev/null || :
  printf '%s' "$_hcf_cat"
}

# Aspas SIMPLES no -c: o "$@" tem de ser expandido pelo sh INTERNO (a partir
# dos posicionais depois do `_`), nao interpolado aqui — interpolar quebra
# qualquer argumento com espaco e desbalanceia as aspas.
_hooks_main_run() {
  capture sh -c '. "$CSTK_LIB/hooks.sh" && hooks_main "$@"' _ "$@"
}

scenario_hooks_main_install_provisiona_so_hooks() {
  if ! _has_jq; then _error "no_jq" "skip"; return 2; fi
  _cat=$(_hooks_catalog_fixture)
  _proj="$TMPDIR_TEST/proj-hooks-main"
  mkdir -p "$_proj"
  _hooks_main_run install --project-path "$_proj" --catalog "$_cat"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT / $_CAPTURED_STDERR"; return 1; }
  for _h in pretooluse-bash-guard.sh posttooluse-tool-call-tick.sh posttooluse-agent-usage.sh; do
    [ -x "$_proj/.claude/hooks/$_h" ] || { _fail "hook ausente" "$_h"; return 1; }
  done
  jq -e '.hooks.PreToolUse[0].matcher == "Bash"' "$_proj/.claude/settings.json" >/dev/null \
    || { _fail "settings.json nao mesclado" ""; return 1; }
  # A diferenca para `cstk install --scope project`: NAO duplica catalogo.
  for _d in skills commands agents; do
    [ -d "$_proj/.claude/$_d" ] \
      && { _fail "duplicou catalogo" "$_d nao deveria existir — hooks install toca so hooks+settings"; return 1; }
  done
  return 0
}

scenario_hooks_main_dry_run_nao_escreve() {
  _cat=$(_hooks_catalog_fixture)
  _proj="$TMPDIR_TEST/proj-hooks-dry"
  mkdir -p "$_proj"
  _hooks_main_run install --project-path "$_proj" --catalog "$_cat" --dry-run
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -e "$_proj/.claude" ] \
    && { _fail "dry-run escreveu" ".claude nao deveria existir"; return 1; }
  return 0
}

# Escopo de PROJETO por construcao (FR-009c): apontar para $HOME e recusado.
scenario_hooks_main_recusa_home() {
  _cat=$(_hooks_catalog_fixture)
  _hooks_main_run install --project-path "$HOME" --catalog "$_cat"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "escopo PROJETO" || return 1
  return 0
}

scenario_hooks_main_catalogo_sem_hooks_exit1() {
  _proj="$TMPDIR_TEST/proj-nocat"
  mkdir -p "$_proj" "$TMPDIR_TEST/catalog-vazio"
  _hooks_main_run install --project-path "$_proj" --catalog "$TMPDIR_TEST/catalog-vazio"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "catalogo sem hooks" || return 1
  return 0
}

scenario_hooks_main_project_path_inexistente_exit1() {
  _cat=$(_hooks_catalog_fixture)
  _hooks_main_run install --project-path "$TMPDIR_TEST/nao-existe" --catalog "$_cat"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  return 0
}

scenario_hooks_main_sem_subcomando_exit2() {
  _hooks_main_run
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
  return 0
}

scenario_hooks_main_subcomando_invalido_exit2() {
  _hooks_main_run nao-existe
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
  return 0
}

scenario_hooks_main_flag_desconhecida_exit2() {
  _cat=$(_hooks_catalog_fixture)
  _proj="$TMPDIR_TEST/proj-flag"
  mkdir -p "$_proj"
  _hooks_main_run install --project-path "$_proj" --catalog "$_cat" --nao-existe
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
  return 0
}

# Idempotencia: rodar 2x nao duplica entradas no settings.json.
scenario_hooks_main_idempotente() {
  if ! _has_jq; then _error "no_jq" "skip"; return 2; fi
  _cat=$(_hooks_catalog_fixture)
  _proj="$TMPDIR_TEST/proj-idem"
  mkdir -p "$_proj"
  _hooks_main_run install --project-path "$_proj" --catalog "$_cat"
  _n1=$(jq '.hooks.PostToolUse | length' "$_proj/.claude/settings.json")
  _hooks_main_run install --project-path "$_proj" --catalog "$_cat"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "2a run exit" "$_CAPTURED_EXIT"; return 1; }
  _n2=$(jq '.hooks.PostToolUse | length' "$_proj/.claude/settings.json")
  [ "$_n1" = "$_n2" ] \
    || { _fail "idempotencia" "PostToolUse foi de $_n1 para $_n2 entradas"; return 1; }
  return 0
}

run_all_scenarios
