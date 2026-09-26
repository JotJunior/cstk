#!/bin/sh
# test_jira-mutation.sh — suite de mutation tests (defesa em profundidade)
# do plugin cstk-jira. Cobre tasks.md 8.4.1-8.4.5.
#
# Ref: docs/specs/cstk-jira/plan.md Test Strategy "Mutation"; tasks.md
#      8.4.1-8.4.5; plugins/cstk-jira/scripts/jira-io.sh;
#      plugins/cstk-jira/hooks/pretooluse-jira-deny-destructive.sh;
#      plugins/cstk-jira/hooks/posttooluse-jira-sync.sh.
#
# _find_scripts (tests/run.sh) so escaneia plugins/cstk-jira/scripts/*.sh —
# esta suite exercita 3 arquivos (jira-io.sh + os 2 hooks) via COPIAS
# mutadas, nao um unico script "dono" sob a convencao de FASE 9.3. Por isso
# esta na allowlist de _is_internal_test em tests/run.sh (existence-guarded
# a plugins/cstk-jira/scripts/jira-io.sh — mesmo idioma de
# test_jira-contract.sh).
#
# Metodo: cada scenario (a) copia plugins/cstk-jira/scripts/ + hooks/
# INTEIROS para $TMPDIR_TEST/mut-plugin (jira-io.sh resolve jira-config.sh
# por dirname($0); posttooluse-jira-sync.sh resolve ../scripts/jira-sync.sh
# — copiar so o arquivo-alvo quebraria a resolucao de irmaos); (b) roda o
# cenario de teste real (tests/cstk/test_jira-io.sh /
# tests/test_pretooluse-jira-deny-destructive.sh /
# tests/test_posttooluse-jira-sync.sh) contra o ORIGINAL primeiro, provando
# que a guarda protege; (c) aplica a mutacao via `sed` (NUNCA `sed -i` —
# GNU-only) escrevendo em arquivo novo + `mv` (mesmo idioma de
# test_session-scope.sh); (d) roda o MESMO cenario contra a copia mutada,
# provando que a regressao introduzida e detectada (exit/efeito colateral
# diverge do original). Cada mutacao falha ruidosamente (_fail
# "mutant_stale") se o `sed` nao encontrar o padrao — protege contra este
# arquivo ficar obsoleto silenciosamente se o codigo-fonte mudar.
#
# Nenhuma rede real: todos os cenarios usam stub de `curl` local (mesmo
# idioma de test_jira-io.sh). `.env` do operador jamais e tocado; credencial
# de teste sempre isolada via XDG_CONFIG_HOME apontando para $TMPDIR_TEST.
#
# Nota tecnica (8.4.1): tasks.md descreve 8.4.1 como "quebrar a checagem de
# host unico (3.1.3)". O codigo de jira-io.sh tem DUAS guardas distintas
# para o mesmo requisito (defesa em profundidade real, nao redundancia
# acidental): (1) uma asserção ESTATICA de auto-consistencia (linhas
# proximas a "host divergente detectado antes da requisicao") que compara
# o host extraido da URL contra site_host — como a URL e sempre montada a
# partir do proprio site_host, essa comparacao nunca diverge sob nenhuma
# entrada externa hoje (e "defesa contra regressao futura na montagem da
# URL", conforme o proprio comentario do script); e (2) a guarda FUNCIONAL
# que de fato barra host-divergente-por-redirect: a classificacao de
# resposta `3xx` (`case "$_jir_status" in 3??) ... `), que 3.1.6/8.3.4
# (scenario_request_redirect_3xx_recusado_sem_nova_requisicao) exercita
# de fato. Verificado empiricamente nesta onda: mutar (1) sozinha NAO
# muda o resultado de nenhum teste existente (guarda morta sob as
# entradas possiveis); mutar (2) FAZ 3.1.6/8.3.4 falharem (exit 0 em vez
# de exit 1, resposta 302 tratada como sucesso). Por isso a mutacao
# automatizada abaixo mira (2) — a guarda que realmente sustenta o
# comportamento coberto por 3.1.6/8.3.4.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

ORIG_PLUGIN_DIR="$REPO_ROOT/plugins/cstk-jira"

# ==== helpers de copia/mutacao ====

# _mut_copy_plugin -> copia scripts/+hooks/ do plugin inteiros para
# $TMPDIR_TEST/mut-plugin (preserva layout relativo). Imprime o path em
# stdout.
_mut_copy_plugin() {
  _mp_dst="$TMPDIR_TEST/mut-plugin"
  rm -rf "$_mp_dst"
  mkdir -p "$_mp_dst"
  cp -R "$ORIG_PLUGIN_DIR/scripts" "$_mp_dst/scripts"
  cp -R "$ORIG_PLUGIN_DIR/hooks" "$_mp_dst/hooks"
  printf '%s' "$_mp_dst"
}

# ==== helpers de fixture (mesmo idioma de tests/cstk/test_jira-io.sh) ====

_write_site_host_config() {
  mkdir -p "$TMPDIR_TEST/.claude/cstk-jira"
  printf 'site_host=%s\n' "$1" > "$TMPDIR_TEST/.claude/cstk-jira/config"
}

_write_credential() {
  mkdir -p "$TMPDIR_TEST/xdg/cstk-jira"
  printf 'email=%s\napi_token=%s\n' "${1:-tester@example.com}" "${2:-tok-FAKE-000}" \
    > "$TMPDIR_TEST/xdg/cstk-jira/credentials"
  chmod 600 "$TMPDIR_TEST/xdg/cstk-jira/credentials"
}

# _make_curl_stub MAPA — mesmo idioma de test_jira-io.sh::_make_curl_stub.
_make_curl_stub() {
  _stub_dir="$TMPDIR_TEST/bin"
  mkdir -p "$_stub_dir"
  printf '%s\n' "$1" > "$TMPDIR_TEST/io-curl-map"
  : > "$TMPDIR_TEST/io-curl-calls.log"
  cat > "$_stub_dir/curl" <<STUB
#!/bin/sh
_url=""
_out=""
_method="GET"
_prev=""
for _a in "\$@"; do
  case "\$_prev" in
    -o) _out="\$_a" ;;
    -X) _method="\$_a" ;;
  esac
  case "\$_a" in
    https://*) _url="\$_a" ;;
  esac
  _prev="\$_a"
done
printf '%s %s\n' "\$_method" "\$_url" >> "$TMPDIR_TEST/io-curl-calls.log"
while IFS='|' read -r _pat _code _body; do
  [ -n "\$_pat" ] || continue
  if [ "\$_url" = "\$_pat" ]; then
    [ -n "\$_out" ] && printf '%s' "\$_body" > "\$_out"
    printf '%s' "\$_code"
    exit 0
  fi
done < "$TMPDIR_TEST/io-curl-map"
exit 22
STUB
  chmod +x "$_stub_dir/curl"
  printf '%s' "$_stub_dir"
}

_curl_call_count() {
  [ -f "$TMPDIR_TEST/io-curl-calls.log" ] || { printf '0'; return; }
  wc -l < "$TMPDIR_TEST/io-curl-calls.log" | tr -d ' '
}

# _make_modecheck_curl_stub — mesmo idioma de
# test_jira-io.sh::_make_modecheck_curl_stub.
_make_modecheck_curl_stub() {
  _stub_dir="$TMPDIR_TEST/bin-modecheck"
  mkdir -p "$_stub_dir"
  cat > "$_stub_dir/curl" <<STUB
#!/bin/sh
_kfile=""
_out=""
_prev=""
for _a in "\$@"; do
  case "\$_prev" in
    -K) _kfile="\$_a" ;;
    -o) _out="\$_a" ;;
  esac
  _prev="\$_a"
done
_mode=\$(stat -c '%a' -- "\$_kfile" 2>/dev/null) || _mode=\$(stat -f '%Lp' -- "\$_kfile" 2>/dev/null) || _mode=""
printf '%s' "\$_mode" > "$TMPDIR_TEST/io-curl-kfile-mode"
[ -n "\$_out" ] && printf '{}' > "\$_out"
printf '200'
exit 0
STUB
  chmod +x "$_stub_dir/curl"
  printf '%s' "$_stub_dir"
}

# _make_selfkill_curl_stub SIGNAL — mesmo idioma de
# test_jira-io.sh::_make_selfkill_curl_stub.
_make_selfkill_curl_stub() {
  _stub_dir="$TMPDIR_TEST/bin-selfkill"
  mkdir -p "$_stub_dir"
  _sig="$1"
  cat > "$_stub_dir/curl" <<STUB
#!/bin/sh
_kfile=""
_prev=""
for _a in "\$@"; do
  case "\$_prev" in
    -K) _kfile="\$_a" ;;
  esac
  _prev="\$_a"
done
printf '%s' "\$_kfile" > "$TMPDIR_TEST/io-curl-kfile-path"
kill -$_sig \$PPID
exit 0
STUB
  chmod +x "$_stub_dir/curl"
  printf '%s' "$_stub_dir"
}

# _hook_config_on DIR -> config com sync_autonomous=on (formato comum aos
# 2 hooks).
_hook_config_on() {
  mkdir -p "$1/.claude/cstk-jira"
  printf 'config_version=1\nsync_autonomous=on\n' > "$1/.claude/cstk-jira/config"
}

_json_pretooluse() {
  # $1 cwd, $2 tool_name
  printf '{"cwd":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"issueIdOrKey":"DEMO-1"}}' \
    "$1" "$2"
}

_json_task() {
  # $1 cwd, $2 task_id, $3 outcome
  printf '{"cwd":"%s","hook_event_name":"PostToolUse","tool_name":"mcp__cstk-state__record_task","tool_input":{"session_id":"sess-000","task_id":"%s","outcome":"%s"}}' \
    "$1" "$2" "$3"
}

# ==== 8.4.1: guarda SEC-5 (recusa 3xx sem nova requisicao) — 3.1.6/8.3.4 ====

scenario_mutation_8_4_1_sec5_redirect_guard() {
  cd "$TMPDIR_TEST" || return 1
  _write_site_host_config "example.atlassian.net"
  _write_credential

  # -- controle: original recusa 302 (exit 1, SEC-5, 1 unica chamada) --
  _bin=$(_make_curl_stub 'https://example.atlassian.net/rest/api/3/issue/CSTK-1|302|')
  assert_exit 1 env PATH="$_bin:$PATH" XDG_CONFIG_HOME="$TMPDIR_TEST/xdg" \
    "$ORIG_PLUGIN_DIR/scripts/jira-io.sh" request GET /rest/api/3/issue/CSTK-1 || return 1
  assert_stderr_contains "SEC-5" || return 1
  [ "$(_curl_call_count)" = "1" ] \
    || { _fail "controle_calls" "esperado 1 chamada no original, obtido $(_curl_call_count)"; return 1; }

  # -- mutante: neutraliza o case "3??)" que classifica 3xx como recusa --
  _mp=$(_mut_copy_plugin)
  _io="$_mp/scripts/jira-io.sh"
  grep -q '    3??)' "$_io" || { _fail "mutant_stale" "padrao '3??)' nao encontrado em jira-io.sh — repo mudou"; return 1; }
  sed 's/    3??)/    9999)/' "$_io" > "$_io.mut" && mv "$_io.mut" "$_io"
  grep -q '    9999)' "$_io" || { _fail "mutant_apply" "sed nao aplicou a mutacao"; return 1; }
  chmod +x "$_io"

  _bin2=$(_make_curl_stub 'https://example.atlassian.net/rest/api/3/issue/CSTK-1|302|')
  capture env PATH="$_bin2:$PATH" XDG_CONFIG_HOME="$TMPDIR_TEST/xdg" \
    "$_io" request GET /rest/api/3/issue/CSTK-1
  [ "$_CAPTURED_EXIT" = "0" ] \
    || { _fail "mutant_exit" "esperado exit 0 (regressao: 302 tratado como sucesso), obtido $_CAPTURED_EXIT"; return 1; }
  return 0
}

# ==== 8.4.2: allowlist fechada de METHOD (sem DELETE) — 3.1.7/4.4.3 ====

scenario_mutation_8_4_2_delete_allowlist() {
  cd "$TMPDIR_TEST" || return 1
  _write_site_host_config "example.atlassian.net"

  # -- controle: original recusa DELETE (exit 2, uso incorreto, 0 chamadas) --
  _bin=$(_make_curl_stub 'https://example.atlassian.net/rest/api/3/issue/CSTK-1|200|{}')
  assert_exit 2 env PATH="$_bin:$PATH" XDG_CONFIG_HOME="$TMPDIR_TEST/xdg-empty" \
    "$ORIG_PLUGIN_DIR/scripts/jira-io.sh" request DELETE /rest/api/3/issue/CSTK-1 || return 1
  assert_stderr_contains "DELETE" || return 1
  [ "$(_curl_call_count)" = "0" ] \
    || { _fail "controle_calls" "DELETE nao deveria disparar requisicao no original"; return 1; }

  # -- mutante: adiciona DELETE na allowlist fechada de _ji_method_allowed --
  _mp=$(_mut_copy_plugin)
  _io="$_mp/scripts/jira-io.sh"
  grep -q 'GET|POST|PUT) return 0 ;;' "$_io" || { _fail "mutant_stale" "allowlist de METHOD nao encontrada — repo mudou"; return 1; }
  sed 's/GET|POST|PUT) return 0 ;;/GET|POST|PUT|DELETE) return 0 ;;/' "$_io" > "$_io.mut" && mv "$_io.mut" "$_io"
  grep -q 'GET|POST|PUT|DELETE) return 0 ;;' "$_io" || { _fail "mutant_apply" "sed nao aplicou a mutacao"; return 1; }
  chmod +x "$_io"

  # XDG_CONFIG_HOME isolado e SEM credencial: qualquer exit != 2 prova que a
  # allowlist deixou de recusar DELETE por uso incorreto (o mutante avanca
  # ate a checagem de credencial e falha la, com exit 4 — nunca 2).
  mkdir -p "$TMPDIR_TEST/xdg-empty"
  _bin2=$(_make_curl_stub 'https://example.atlassian.net/rest/api/3/issue/CSTK-1|200|{}')
  capture env PATH="$_bin2:$PATH" XDG_CONFIG_HOME="$TMPDIR_TEST/xdg-empty" \
    "$_io" request DELETE /rest/api/3/issue/CSTK-1
  [ "$_CAPTURED_EXIT" != "2" ] \
    || { _fail "mutant_exit" "esperado exit != 2 (regressao: DELETE aceito pela allowlist), obtido $_CAPTURED_EXIT"; return 1; }
  return 0
}

# ==== 8.4.3: matcher do hook de exclusao via Rovo MCP — 5.2.5 ====

scenario_mutation_8_4_3_pretooluse_matcher() {
  _hook_config_on "$TMPDIR_TEST"
  _J=$(_json_pretooluse "$TMPDIR_TEST" "mcp__atlassian__deleteJiraIssue")

  # -- controle: original bloqueia (exit 2, FR-012) --
  assert_exit 2 sh -c 'printf "%s" "$1" | "$2"' _ "$_J" "$ORIG_PLUGIN_DIR/hooks/pretooluse-jira-deny-destructive.sh" || return 1
  assert_stderr_contains "FR-012" || return 1

  # -- mutante: substitui o matcher por um padrao que nunca casa --
  _mp=$(_mut_copy_plugin)
  _hook="$_mp/hooks/pretooluse-jira-deny-destructive.sh"
  grep -q 'mcp__\*__deleteJiraIssue | mcp__\*__executeDestructive) ;;' "$_hook" \
    || { _fail "mutant_stale" "matcher nao encontrado no hook — repo mudou"; return 1; }
  sed 's/mcp__\*__deleteJiraIssue | mcp__\*__executeDestructive) ;;/mcp__nunca-casa__x) ;;/' "$_hook" > "$_hook.mut" && mv "$_hook.mut" "$_hook"
  grep -q 'mcp__nunca-casa__x) ;;' "$_hook" || { _fail "mutant_apply" "sed nao aplicou a mutacao"; return 1; }
  chmod +x "$_hook"

  capture sh -c 'printf "%s" "$1" | "$2"' _ "$_J" "$_hook"
  [ "$_CAPTURED_EXIT" = "0" ] \
    || { _fail "mutant_exit" "esperado exit 0 (regressao: matcher quebrado nunca bloqueia), obtido $_CAPTURED_EXIT"; return 1; }
  return 0
}

# ==== 8.4.4: no-op de inatividade dos 2 hooks — 5.1.8/5.2.6 ====

scenario_mutation_8_4_4_hooks_inatividade_noop() {
  # -- parte A: posttooluse-jira-sync.sh (config ausente -> no-op total) --
  # controle: original nao cria nada sob .claude/cstk-jira sem config previo
  _Jtask=$(_json_task "$TMPDIR_TEST" 1.1 pass)
  assert_exit 0 sh -c 'printf "%s" "$1" | "$2" "$3"' _ "$_Jtask" \
    "$ORIG_PLUGIN_DIR/hooks/posttooluse-jira-sync.sh" task || return 1
  [ -d "$TMPDIR_TEST/.claude/cstk-jira" ] \
    && { _fail "controle_posttooluse" ".claude/cstk-jira criado sem config no original"; return 1; }

  _mp=$(_mut_copy_plugin)
  _post="$_mp/hooks/posttooluse-jira-sync.sh"
  grep -qF '[ -f "$_PJS_CONFIG" ] || exit 0' "$_post" \
    || { _fail "mutant_stale" "no-op de config ausente nao encontrado em posttooluse-jira-sync.sh"; return 1; }
  sed "s/\[ -f \"\$_PJS_CONFIG\" \] || exit 0/: /" "$_post" > "$_post.mut" && mv "$_post.mut" "$_post"
  grep -qF '[ -f "$_PJS_CONFIG" ] || exit 0' "$_post" \
    && { _fail "mutant_apply" "sed nao aplicou a mutacao em posttooluse-jira-sync.sh"; return 1; }
  chmod +x "$_post"

  rm -rf "$TMPDIR_TEST/mut-cwd-a"
  mkdir -p "$TMPDIR_TEST/mut-cwd-a"
  _Jtask2=$(_json_task "$TMPDIR_TEST/mut-cwd-a" 1.1 pass)
  sh -c 'printf "%s" "$1" | "$2" "$3"' _ "$_Jtask2" "$_post" task >/dev/null 2>&1 || :
  [ -d "$TMPDIR_TEST/mut-cwd-a/.claude/cstk-jira" ] \
    || { _fail "mutant_posttooluse" "esperado regressao: .claude/cstk-jira criado mesmo sem config, mas nao foi"; return 1; }

  # -- parte B: pretooluse-jira-deny-destructive.sh (config ausente -> no-op) --
  # controle: original e no-op (exit 0) sem config, mesmo com tool_name casando.
  rm -rf "$TMPDIR_TEST/mut-cwd-b"
  mkdir -p "$TMPDIR_TEST/mut-cwd-b"
  _Jpre=$(_json_pretooluse "$TMPDIR_TEST/mut-cwd-b" "mcp__atlassian__deleteJiraIssue")
  assert_exit 0 sh -c 'printf "%s" "$1" | "$2"' _ "$_Jpre" \
    "$ORIG_PLUGIN_DIR/hooks/pretooluse-jira-deny-destructive.sh" || return 1

  _pre="$_mp/hooks/pretooluse-jira-deny-destructive.sh"
  grep -qF '[ -f "$_PJD_CONFIG" ] || exit 0' "$_pre" \
    || { _fail "mutant_stale" "no-op de config ausente nao encontrado em pretooluse-jira-deny-destructive.sh"; return 1; }
  sed "s/\[ -f \"\$_PJD_CONFIG\" \] || exit 0/: /" "$_pre" > "$_pre.mut" && mv "$_pre.mut" "$_pre"
  grep -qF '[ -f "$_PJD_CONFIG" ] || exit 0' "$_pre" \
    && { _fail "mutant_apply" "sed nao aplicou a mutacao em pretooluse-jira-deny-destructive.sh"; return 1; }
  chmod +x "$_pre"

  capture sh -c 'printf "%s" "$1" | "$2"' _ "$_Jpre" "$_pre"
  [ "$_CAPTURED_EXIT" = "2" ] \
    || { _fail "mutant_pretooluse" "esperado exit 2 (regressao: bloqueia mesmo sem config), obtido $_CAPTURED_EXIT"; return 1; }
  return 0
}

# ==== 8.4.5: umask/trap da credencial temporaria — 3.3.4/3.3.5 ====

scenario_mutation_8_4_5_umask_trap_credencial() {
  cd "$TMPDIR_TEST" || return 1
  _write_site_host_config "example.atlassian.net"
  _write_credential

  # -- controle A (umask): original produz modo 0600 durante a chamada --
  _bin=$(_make_modecheck_curl_stub)
  assert_exit 0 env PATH="$_bin:$PATH" XDG_CONFIG_HOME="$TMPDIR_TEST/xdg" \
    "$ORIG_PLUGIN_DIR/scripts/jira-io.sh" request GET /rest/api/3/issue/CSTK-1 || return 1
  _modo=$(cat "$TMPDIR_TEST/io-curl-kfile-mode" 2>/dev/null)
  [ "$_modo" = "600" ] || { _fail "controle_umask" "esperado 600 no original, obtido '$_modo'"; return 1; }

  # -- controle B (trap): original remove credencial mesmo sob SIGTERM --
  _bin2=$(_make_selfkill_curl_stub TERM)
  capture env PATH="$_bin2:$PATH" XDG_CONFIG_HOME="$TMPDIR_TEST/xdg" \
    "$ORIG_PLUGIN_DIR/scripts/jira-io.sh" request GET /rest/api/3/issue/CSTK-1
  [ "$_CAPTURED_EXIT" = "143" ] || { _fail "controle_trap_exit" "esperado 143, obtido $_CAPTURED_EXIT"; return 1; }
  _kfile_ctrl=$(cat "$TMPDIR_TEST/io-curl-kfile-path")
  [ -n "$_kfile_ctrl" ] || { _fail "controle_trap_kfile" "stub nao rodou"; return 1; }
  [ -e "$_kfile_ctrl" ] && { _fail "controle_trap_survives" "credencial sobreviveu no original (SIGTERM)"; return 1; }

  # -- mutante: remove `umask 077` (subshell do scenario isola o efeito) --
  # nao restaurar apos: run_all_scenarios roda cada scenario em subshell
  # proprio (harness.sh linha ~272), entao umask nao vaza para outros
  # scenarios.
  umask 022
  _mp=$(_mut_copy_plugin)
  _io="$_mp/scripts/jira-io.sh"
  grep -q '^  umask 077$' "$_io" || { _fail "mutant_stale" "linha 'umask 077' nao encontrada em jira-io.sh"; return 1; }
  sed 's/^  umask 077$/  : umask-neutralizada-mutacao-8-4-5/' "$_io" > "$_io.mut" && mv "$_io.mut" "$_io"
  grep -q 'umask-neutralizada-mutacao-8-4-5' "$_io" || { _fail "mutant_apply" "sed nao aplicou a mutacao (umask)"; return 1; }
  chmod +x "$_io"

  _bin3=$(_make_modecheck_curl_stub)
  env PATH="$_bin3:$PATH" XDG_CONFIG_HOME="$TMPDIR_TEST/xdg" \
    "$_io" request GET /rest/api/3/issue/CSTK-1 >/dev/null 2>&1
  _modo_mut=$(cat "$TMPDIR_TEST/io-curl-kfile-mode" 2>/dev/null)
  [ "$_modo_mut" != "600" ] \
    || { _fail "mutant_umask" "esperado modo != 600 (regressao: umask 077 removida sob umask ambiente 022), obtido '$_modo_mut'"; return 1; }

  # -- mutante: remove o trap de EXIT (credencial sobrevive a SIGTERM) --
  _io2="$_mp/scripts/jira-io.sh"
  cp "$ORIG_PLUGIN_DIR/scripts/jira-io.sh" "$_io2"
  grep -qF "trap '_ji_cred_cleanup' EXIT" "$_io2" || { _fail "mutant_stale" "trap EXIT nao encontrado em jira-io.sh"; return 1; }
  sed "s/trap '_ji_cred_cleanup' EXIT/: trap-exit-removido-mutacao-8-4-5/" "$_io2" > "$_io2.mut" && mv "$_io2.mut" "$_io2"
  grep -qF "trap '_ji_cred_cleanup' EXIT" "$_io2" && { _fail "mutant_apply" "sed nao removeu o trap EXIT"; return 1; }
  chmod +x "$_io2"

  _bin4=$(_make_selfkill_curl_stub TERM)
  env PATH="$_bin4:$PATH" XDG_CONFIG_HOME="$TMPDIR_TEST/xdg" \
    "$_io2" request GET /rest/api/3/issue/CSTK-1 >/dev/null 2>&1
  _kfile_mut=$(cat "$TMPDIR_TEST/io-curl-kfile-path")
  [ -n "$_kfile_mut" ] || { _fail "mutant_trap_kfile" "stub mutante nao rodou"; return 1; }
  [ -e "$_kfile_mut" ] \
    || { _fail "mutant_trap" "esperado credencial sobrevivendo (regressao: trap EXIT removido), mas foi removida"; return 1; }
  rm -f "$_kfile_mut"
  return 0
}

run_all_scenarios
