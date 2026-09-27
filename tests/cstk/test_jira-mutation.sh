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
  printf 'site_host=%s\nemail=%s\napi_token=%s\n' \
    "${3:-example.atlassian.net}" "${1:-tester@example.com}" "${2:-tok-FAKE-000}" \
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

# ==== 16.1.5 (r02): allowlist de validate-version-name (SEC-6) — 16.1.4 ====

scenario_mutation_16_1_5_validate_version_name_allowlist() {
  # -- controle: original rejeita nome vazio (exit 2) --
  assert_exit 2 "$ORIG_PLUGIN_DIR/scripts/jira-io.sh" validate-version-name "" || return 1

  # -- mutante: neutraliza a checagem "deve comecar com alfanumerico",
  # aceitando qualquer string (inclusive vazia) na 1a guarda do case --
  _mp=$(_mut_copy_plugin)
  _io="$_mp/scripts/jira-io.sh"
  grep -q '\[A-Za-z0-9\]\*) : ;;' "$_io" \
    || { _fail "mutant_stale" "guarda [A-Za-z0-9]*) : ;; nao encontrada — repo mudou"; return 1; }
  sed 's/\[A-Za-z0-9\]\*) : ;;/*) : ;;/' "$_io" > "$_io.mut" && mv "$_io.mut" "$_io"
  grep -q '^    \*) : ;;$' "$_io" \
    || { _fail "mutant_apply" "sed nao aplicou a mutacao da allowlist"; return 1; }
  chmod +x "$_io"

  capture "$_io" validate-version-name ""
  [ "$_CAPTURED_EXIT" != "2" ] \
    || { _fail "mutant_exit" "esperado exit != 2 (regressao: nome vazio aceito pela allowlist mutada), obtido $_CAPTURED_EXIT"; return 1; }
  return 0
}

# ==== 16.2.5 (r02): checagem de divergencia rounds/rNN em milestone resolve ====

_write_full_config_mut() {
  mkdir -p "$TMPDIR_TEST/.claude/cstk-jira"
  cat > "$TMPDIR_TEST/.claude/cstk-jira/config" <<'EOF'
config_version=1
site_host=example.atlassian.net
project_key=DEMO
board_id=1
issue_type_epic=10001
issue_type_task=10004
issue_type_subtask=10002
status_pending=To Do
status_in_progress=In Progress
status_pass=Done
status_fail=Failed
sync_autonomous=on
EOF
}

scenario_mutation_16_2_5_milestone_round_divergence_check() {
  cd "$TMPDIR_TEST" || return 1
  _write_full_config_mut
  mkdir -p "$TMPDIR_TEST/.claude/feature-00c-state/demo/rounds/r01"
  cat > "$TMPDIR_TEST/.claude/feature-00c-state/demo/state.json" <<'EOF'
{"previous_round":{"round":"r03"}}
EOF

  # -- controle: original detecta divergencia (r03 vs 1 dir) -> unresolved --
  _out=$("$ORIG_PLUGIN_DIR/scripts/jira-sync.sh" milestone resolve --feature demo) \
    || { _fail "controle_exit" "milestone resolve deveria sair exit 0 no original"; return 1; }
  printf '%s\n' "$_out" | grep -qx "status=unresolved" \
    || { _fail "controle_unresolved" "esperado status=unresolved no original, obtido: $_out"; return 1; }

  # -- mutante: neutraliza a checagem de divergencia (sempre "bate") --
  _mp=$(_mut_copy_plugin)
  _sy="$_mp/scripts/jira-sync.sh"
  grep -q 'if \[ "\$_jsmr_prev_num_dec" -eq "\$_jsmr_dircount" \]; then' "$_sy" \
    || { _fail "mutant_stale" "checagem de divergencia nao encontrada — repo mudou"; return 1; }
  sed 's/if \[ "\$_jsmr_prev_num_dec" -eq "\$_jsmr_dircount" \]; then/if [ "$_jsmr_prev_num_dec" -eq "$_jsmr_prev_num_dec" ]; then/' \
    "$_sy" > "$_sy.mut" && mv "$_sy.mut" "$_sy"
  grep -q 'if \[ "\$_jsmr_prev_num_dec" -eq "\$_jsmr_prev_num_dec" \]; then' "$_sy" \
    || { _fail "mutant_apply" "sed nao aplicou a mutacao"; return 1; }
  chmod +x "$_sy"

  _out_mut=$("$_sy" milestone resolve --feature demo) \
    || { _fail "mutant_run" "mutante deveria sair exit 0"; return 1; }
  if printf '%s\n' "$_out_mut" | grep -qx "status=unresolved"; then
    _fail "mutant_divergence" "esperado NAO unresolved (regressao: divergencia rounds/rNN nunca detectada), obtido: $_out_mut"
    return 1
  fi
  return 0
}

# scenario_mutation_16_3_7_milestone_put_current_downgrade — r02 FASE 16
# task 16.3.7 (data-model.md Entity Milestone: "no maximo 1 current por
# arquivo"; jira-map.sh milestone-put, task 16.3.4). Alvo diferente do
# `_mut_copy_plugin` (mira jira-map.sh diretamente, chamado sem rede) —
# mesmo metodo de controle-depois-mutante das demais.
scenario_mutation_16_3_7_milestone_put_current_downgrade() {
  cd "$TMPDIR_TEST" || return 1
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"

  # -- controle: original rebaixa a current anterior -> exatamente 1 current --
  "$ORIG_PLUGIN_DIR/scripts/jira-map.sh" milestone-put --feature demo \
    --name demo-r02 --kind round --version-id 30001 --project-key DEMO \
    --state current >/dev/null \
    || { _fail "controle_put1" "1o milestone-put falhou no original"; return 1; }
  "$ORIG_PLUGIN_DIR/scripts/jira-map.sh" milestone-put --feature demo \
    --name demo-r03 --kind round --version-id 30002 --project-key DEMO \
    --state current >/dev/null \
    || { _fail "controle_put2" "2o milestone-put falhou no original"; return 1; }
  _mf="$TMPDIR_TEST/docs/specs/demo/jira-milestones.tsv"
  _ncur=$(awk -F '\t' 'NR>1 && $5=="current"' "$_mf" | wc -l | tr -d ' ')
  [ "$_ncur" = "1" ] \
    || { _fail "controle_single_current" "esperado 1 current no original, obtido $_ncur"; return 1; }

  # -- mutante: neutraliza o rebaixamento (nunca desce current->superseded) --
  _mp=$(_mut_copy_plugin)
  _jm="$_mp/scripts/jira-map.sh"
  grep -q 'if (newstate == "current" && \$5 == "current") { \$5 = "superseded" }' "$_jm" \
    || { _fail "mutant_stale" "linha de rebaixamento nao encontrada — repo mudou"; return 1; }
  sed 's/if (newstate == "current" \&\& \$5 == "current") { \$5 = "superseded" }/if (newstate == "current" \&\& \$5 == "__never__") { \$5 = "superseded" }/' \
    "$_jm" > "$_jm.mut" && mv "$_jm.mut" "$_jm"
  grep -q '\$5 == "__never__"' "$_jm" \
    || { _fail "mutant_apply" "sed nao aplicou a mutacao"; return 1; }
  chmod +x "$_jm"

  rm -rf "$TMPDIR_TEST/docs/specs/demo"
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  "$_jm" milestone-put --feature demo --name demo-r02 --kind round \
    --version-id 30001 --project-key DEMO --state current >/dev/null \
    || { _fail "mutant_put1" "1o milestone-put falhou no mutante"; return 1; }
  "$_jm" milestone-put --feature demo --name demo-r03 --kind round \
    --version-id 30002 --project-key DEMO --state current >/dev/null \
    || { _fail "mutant_put2" "2o milestone-put falhou no mutante"; return 1; }
  _ncur_mut=$(awk -F '\t' 'NR>1 && $5=="current"' "$_mf" | wc -l | tr -d ' ')
  if [ "$_ncur_mut" = "1" ]; then
    _fail "mutant_downgrade" "esperado 2 linhas current (regressao: rebaixamento nunca acontece), obtido $_ncur_mut"
    return 1
  fi
  return 0
}

# scenario_mutation_16_4_7_milestone_id_known_sec10 — r02 FASE 16 task 16.4.7
# (plan.md SEC-10; jira-map.sh milestone-id-known, task 16.4.3): mira
# DIRETAMENTE a guarda que `_js_reconcile_epic_milestone` consulta ANTES de
# emitir `update.fixVersions` `remove` — "so remove se o id antigo AINDA
# constar no sidecar (current/superseded)". Alvo sem rede (mesmo metodo de
# 16.3.7): reverter essa guarda faz `milestone-id-known` responder "sim,
# conhecido" para QUALQUER id, o que levaria `_js_reconcile_epic_milestone`
# a remover uma versao que o sidecar da feature nunca reconheceu — exatamente
# o cenario que SY-81 (scenario_drain_reconcile_epic_milestone_drift_gera_conflito_sem_update,
# tests/cstk/test_jira-sync.sh) prova que NAO acontece no original.
scenario_mutation_16_4_7_milestone_id_known_sec10() {
  cd "$TMPDIR_TEST" || return 1
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  _mf="$TMPDIR_TEST/docs/specs/demo/jira-milestones.tsv"
  printf 'milestone_name\tmilestone_kind\tjira_version_id\tproject_key\tstate\n' > "$_mf"
  printf 'demo-r02\tround\t30002\tDEMO\tcurrent\n' >> "$_mf"

  # -- controle: original NAO reconhece um id ausente do sidecar (30001
  # nunca foi gravado) -> exit 1 (SEC-10 bloqueia o remove) --
  assert_exit 1 "$ORIG_PLUGIN_DIR/scripts/jira-map.sh" milestone-id-known \
    --feature demo --project-key DEMO --version-id 30001 || return 1
  # controle positivo: um id que DE FATO consta como current -> exit 0.
  assert_exit 0 "$ORIG_PLUGIN_DIR/scripts/jira-map.sh" milestone-id-known \
    --feature demo --project-key DEMO --version-id 30002 || return 1

  # -- mutante: neutraliza a condicao do awk (aceita qualquer id, ignora
  # project_key/state) — equivalente a "remover sem checar o sidecar" --
  _mp=$(_mut_copy_plugin)
  _jm="$_mp/scripts/jira-map.sh"
  grep -q 'NR > 1 && \$4 == pk && \$3 == vid && (\$5 == "current" || \$5 == "superseded") { f = 1; exit }' "$_jm" \
    || { _fail "mutant_stale" "condicao de milestone-id-known nao encontrada — repo mudou"; return 1; }
  sed 's/NR > 1 && \$4 == pk && \$3 == vid && (\$5 == "current" || \$5 == "superseded") { f = 1; exit }/NR > 1 { f = 1; exit }/' \
    "$_jm" > "$_jm.mut" && mv "$_jm.mut" "$_jm"
  grep -q 'NR > 1 { f = 1; exit }' "$_jm" \
    || { _fail "mutant_apply" "sed nao aplicou a mutacao"; return 1; }
  chmod +x "$_jm"

  capture "$_jm" milestone-id-known --feature demo --project-key DEMO --version-id 30001
  [ "$_CAPTURED_EXIT" != "1" ] \
    || { _fail "mutant_exit" "esperado exit != 1 (regressao: SEC-10 nunca bloqueia — removeria uma versao/id que o sidecar nao reconhece), obtido $_CAPTURED_EXIT"; return 1; }
  return 0
}

# scenario_mutation_17_1_4_label_allowlist — r02 FASE 17 task 17.1.4
# (plan.md SEC-1 extensao `phase-<N>`): mira DIRETAMENTE a guarda de
# `_ji_cmd_json_build_issue` que valida `--label` via `_ji_charset_ok`
# ANTES de montar o corpo (task 17.1.1). Reverter essa guarda (aceitar
# qualquer string) faz o teste negativo de 17.1.3
# (scenario_json_build_issue_label_invalido_exit2, tests/cstk/test_jira-io.sh)
# falhar — um label com espaco/caractere fora da allowlist deixaria de ser
# recusado e entraria no corpo `fields.labels`.
scenario_mutation_17_1_4_label_allowlist() {
  # -- controle: original recusa --label com espaco (exit 2, SEC-1) --
  assert_exit 2 "$ORIG_PLUGIN_DIR/scripts/jira-io.sh" json-build issue \
    --project-id 1 --issuetype-id 1 --summary x --label "phase 3" || return 1

  # -- mutante: neutraliza a checagem de --label em json-build issue,
  # aceitando qualquer string (equivalente a "reverter a validacao de
  # 17.1.1") --
  _mp=$(_mut_copy_plugin)
  _io="$_mp/scripts/jira-io.sh"
  grep -q '_ji_charset_ok "\$_jbi_label"' "$_io" \
    || { _fail "mutant_stale" "guarda --label de json-build issue nao encontrada — repo mudou"; return 1; }
  sed 's/_ji_charset_ok "\$_jbi_label" \\/true \\/' "$_io" > "$_io.mut" && mv "$_io.mut" "$_io"
  grep -q '^    true \\$' "$_io" \
    || { _fail "mutant_apply" "sed nao aplicou a mutacao da allowlist de --label"; return 1; }
  chmod +x "$_io"

  capture "$_io" json-build issue \
    --project-id 1 --issuetype-id 1 --summary x --label "phase 3"
  [ "$_CAPTURED_EXIT" != "2" ] \
    || { _fail "mutant_exit" "esperado exit != 2 (regressao: --label com espaco aceito pela allowlist mutada), obtido $_CAPTURED_EXIT"; return 1; }
  return 0
}

# scenario_mutation_17_3_6_phase_label_sec10 — r02 FASE 17 task 17.3.6
# (plan.md SEC-10, task 17.3.2): mira DIRETAMENTE a guarda default do case
# em `_js_reconcile_phase_label` (jira-sync.sh) que so autoriza
# `_jrpl_do_remove="yes"` quando `written_phase_label` casa
# `^phase-[0-9]+$` — "remove SO se o valor casar o padrao, nunca um label
# humano mesmo que (por acidente) coincida com o marker". Alvo via
# `drain` fim-a-fim (a guarda vive numa funcao interna, sem subcomando
# proprio como `jira-map.sh milestone-id-known` em 16.4.7): o marker da
# Task 1.1 guarda `written_phase_label="prioridade alta"` (valor que NUNCA
# seria escrito pelo proprio motor — so `phase-<N>` — mas defesa em
# profundidade contra um estado corrompido) e a issue REAL (R15) confirma
# esse mesmo valor presente. No original, `_jrpl_do_remove` fica "no"
# (fora do padrao) -> so `--add-label phase-5` entra no corpo (charset
# ok) -> `drain` conclui normalmente. No mutante, `_jrpl_do_remove` vira
# "yes" incondicional -> `--remove-label "prioridade alta"` (espaco,
# fora da allowlist SEC-1 de `_ji_charset_ok`) faz `json-build
# issue-update` morrer com exit 2 DENTRO da substituicao de comando que
# monta o corpo — sob `set -eu` (jira-sync.sh) isso aborta o processo
# INTEIRO de `drain` (exit != 0), uma divergencia bem observavel do
# `exit 0` do original.
scenario_mutation_17_3_6_phase_label_sec10() {
  cd "$TMPDIR_TEST" || return 1
  _write_full_config_mut
  _write_credential
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cat > "$TMPDIR_TEST/docs/specs/demo/tasks.md" <<'EOF'
## FASE 5 - Sincronizacao `[A]`

### 1.1 Titulo da tarefa `[A]`

- [x] 1.1.1 Sub um
EOF
  printf 'local_key\tkind\tjira_id\tjira_key\tstate\n' > "$TMPDIR_TEST/docs/specs/demo/jira-map.tsv"
  printf 'demo\tepic\t20001\tDEMO-1\tactive\n' >> "$TMPDIR_TEST/docs/specs/demo/jira-map.tsv"
  printf '1.1\ttask\t20002\tDEMO-2\tactive\n' >> "$TMPDIR_TEST/docs/specs/demo/jira-map.tsv"

  mkdir -p "$TMPDIR_TEST/.claude/cstk-jira/runtime"
  cat > "$TMPDIR_TEST/.claude/cstk-jira/runtime/outbox.tsv" <<'EOF2'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	*	reconcile	hook-close-wave	0	queued
EOF2

  _sha_epic=$(printf '%s' "demo" | "$ORIG_PLUGIN_DIR/scripts/jira-io.sh" sha256-stdin)
  _sha_task=$(printf '%s' "Titulo da tarefa" | "$ORIG_PLUGIN_DIR/scripts/jira-io.sh" sha256-stdin)
  _mapa="https://example.atlassian.net/rest/api/3/issue/DEMO-1?fields=summary,status|200|{\"fields\":{\"summary\":\"demo\",\"status\":{\"name\":\"Done\"}}}
https://example.atlassian.net/rest/api/3/issue/DEMO-1/properties/cstk-jira.sync|200|{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_epic\",\"written_status\":\"Done\"}}
https://example.atlassian.net/rest/api/3/issue/DEMO-2?fields=summary,status|200|{\"fields\":{\"summary\":\"Titulo da tarefa\",\"status\":{\"name\":\"Done\"}}}
https://example.atlassian.net/rest/api/3/issue/DEMO-2/properties/cstk-jira.sync|200|{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_task\",\"written_status\":\"Done\",\"written_phase_label\":\"prioridade alta\"}}
https://example.atlassian.net/rest/api/3/issue/DEMO-2?fields=labels|200|{\"fields\":{\"labels\":[\"prioridade alta\"]}}
https://example.atlassian.net/rest/api/3/issue/DEMO-2|204|
https://example.atlassian.net/rest/api/3/issue/DEMO-2/properties/cstk-jira.sync|200|"

  # -- controle: written_phase_label fora do padrao phase-N -> do_remove=no
  # -> so --add-label phase-5 (charset ok) -> drain conclui exit 0 --
  _bin=$(_make_curl_stub "$_mapa")
  assert_exit 0 env PATH="$_bin:$PATH" XDG_CONFIG_HOME="$TMPDIR_TEST/xdg" \
    "$ORIG_PLUGIN_DIR/scripts/jira-sync.sh" drain --feature demo || return 1

  # -- mutante: neutraliza a guarda SEC-10 (17.3.2) — aceita remover
  # QUALQUER written_phase_label, mesmo fora do padrao phase-N --
  _mp=$(_mut_copy_plugin)
  _sy="$_mp/scripts/jira-sync.sh"
  grep -qF '        *) _jrpl_do_remove="no" ;;' "$_sy" \
    || { _fail "mutant_stale" "guarda SEC-10 (default do_remove=no) nao encontrada — repo mudou"; return 1; }
  sed 's/        \*) _jrpl_do_remove="no" ;;/        *) _jrpl_do_remove="yes" ;;/' "$_sy" > "$_sy.mut" && mv "$_sy.mut" "$_sy"
  grep -qF '        *) _jrpl_do_remove="yes" ;;' "$_sy" \
    || { _fail "mutant_apply" "sed nao aplicou a mutacao SEC-10"; return 1; }
  chmod +x "$_sy"

  # outbox precisa ser reenfileirado (o controle ja marcou o evento done).
  cat > "$TMPDIR_TEST/.claude/cstk-jira/runtime/outbox.tsv" <<'EOF2'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	*	reconcile	hook-close-wave	0	queued
EOF2

  _bin2=$(_make_curl_stub "$_mapa")
  capture env PATH="$_bin2:$PATH" XDG_CONFIG_HOME="$TMPDIR_TEST/xdg" \
    "$_sy" drain --feature demo
  [ "$_CAPTURED_EXIT" != "0" ] \
    || { _fail "mutant_exit" "esperado exit != 0 (regressao: SEC-10 tenta remover \"prioridade alta\", label fora do padrao phase-N), obtido $_CAPTURED_EXIT"; return 1; }
  return 0
}

# scenario_mutation_18_1_4_check_link_type_membership — r02 FASE 18 tarefa
# 18.1.4 (SEC-13): mira DIRETAMENTE a guarda de `jira-setup.sh
# check-link-type` que so aceita `ID` se estiver entre os `CANDIDATE_ID...`
# devolvidos por R16 nesta execucao (18.1.1). Reverter essa guarda
# (aceitar qualquer ID) faz o teste negativo de 18.1.3
# (scenario_check_link_type_id_ausente_exit1_lista_candidatos,
# tests/cstk/test_jira-setup.sh) falhar — um id digitado de memoria/nao
# devolvido por R16 deixaria de ser recusado.
scenario_mutation_18_1_4_check_link_type_membership() {
  # -- controle: original recusa id fora da lista de candidatos (exit 1) --
  assert_exit 1 "$ORIG_PLUGIN_DIR/scripts/jira-setup.sh" check-link-type \
    99999 10000 10001 10002 10003 || return 1

  # -- mutante: neutraliza a checagem de membership em check-link-type,
  # aceitando qualquer ID (equivalente a "reverter a validacao de 18.1.1") --
  _mp=$(_mut_copy_plugin)
  _su="$_mp/scripts/jira-setup.sh"
  grep -qF '_js_contains "$_jsclt_id" "$@"' "$_su" \
    || { _fail "mutant_stale" "guarda de membership de check-link-type nao encontrada — repo mudou"; return 1; }
  sed 's/_js_contains "\$_jsclt_id" "\$@"/true/' "$_su" > "$_su.mut" && mv "$_su.mut" "$_su"
  grep -qF '_js_contains "$_jsclt_id"' "$_su" \
    && { _fail "mutant_apply" "sed nao aplicou a mutacao de check-link-type"; return 1; }
  chmod +x "$_su"

  capture "$_su" check-link-type 99999 10000 10001 10002 10003
  [ "$_CAPTURED_EXIT" != "1" ] \
    || { _fail "mutant_exit" "esperado exit != 1 (regressao: id fora da lista de candidatos R16 aceito), obtido $_CAPTURED_EXIT"; return 1; }
  return 0
}

# scenario_mutation_18_2_4_resolve_link_type_ambiguity_picks_first — r02
# FASE 18 tarefa 18.2.4: mira a guarda de `jira-setup.sh resolve-link-type`
# que recusa (unrepresentable reason=ambiguous_link_type) quando 2+
# candidatos casam a raiz "block" em inward E outward (18.2.1). Reverter
# essa guarda para "escolher o primeiro candidato em caso de ambiguidade"
# faz o teste negativo de 18.2.3
# (scenario_resolve_link_type_ambiguo_nao_escolhe_primeiro,
# tests/cstk/test_jira-setup.sh) falhar — a escolha automatica passaria a
# decidir arbitrariamente em vez de recusar.
scenario_mutation_18_2_4_resolve_link_type_ambiguity_picks_first() {
  # -- controle: original recusa ambiguidade (exit 1, unrepresentable) --
  _ctrl_out=$(printf '10000\tis blocked by\tblocks\n10005\tBlockage\tblocking\n' | \
    "$ORIG_PLUGIN_DIR/scripts/jira-setup.sh" resolve-link-type 2>&1)
  _ctrl_rc=$?
  [ "$_ctrl_rc" = "1" ] || { _fail "control_exit" "esperado exit 1 no original, obtido $_ctrl_rc"; return 1; }
  case "$_ctrl_out" in
    *"unrepresentable reason=ambiguous_link_type"*) : ;;
    *) _fail "control_msg" "original nao reportou ambiguidade: $_ctrl_out"; return 1 ;;
  esac

  # -- mutante: reverte 18.2.1 para escolher o PRIMEIRO candidato em caso
  # de ambiguidade (em vez de unrepresentable) --
  _mp=$(_mut_copy_plugin)
  _su="$_mp/scripts/jira-setup.sh"
  grep -qF 'reason=ambiguous_link_type:' "$_su" \
    || { _fail "mutant_stale" "diagnostico de ambiguidade nao encontrado — repo mudou"; return 1; }
  sed "s#.*reason=ambiguous_link_type:.*#      printf %s \"\${_jsrlt_matched_list%%,*}\"#" \
    "$_su" > "$_su.mut" && mv "$_su.mut" "$_su"
  grep -qF 'reason=ambiguous_link_type:' "$_su" \
    && { _fail "mutant_apply" "sed nao aplicou a mutacao de ambiguidade"; return 1; }
  chmod +x "$_su"

  capture sh -c "printf '10000\tis blocked by\tblocks\n10005\tBlockage\tblocking\n' | \"$_su\" resolve-link-type"
  [ "$_CAPTURED_EXIT" != "1" ] \
    || { _fail "mutant_exit" "esperado exit != 1 (regressao: ambiguidade escolhe o primeiro candidato em vez de unrepresentable), obtido $_CAPTURED_EXIT"; return 1; }
  [ "$_CAPTURED_STDOUT" = "10000" ] \
    || { _fail "mutant_picks_first" "esperado stdout='10000' (primeiro candidato escolhido arbitrariamente), obtido '$_CAPTURED_STDOUT'"; return 1; }
  return 0
}

# scenario_mutation_18_3_5_link_put_stale_never_disappears — r02 FASE 18
# tarefa 18.3.5: mira o upsert atomico de `jira-map.sh link-put` (18.3.2)
# que NUNCA remove uma linha ja gravada (transicoes para `stale` apenas
# atualizam a linha in-place, FR-012). Reverter a guarda para permitir que
# a linha casada "desapareca" do arquivo (deixa de ser reescrita) faz um
# teste "linha stale nunca desaparece do arquivo" falhar.
scenario_mutation_18_3_5_link_put_stale_never_disappears() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cd "$TMPDIR_TEST" || return 1
  _lf="$TMPDIR_TEST/docs/specs/demo/jira-links.tsv"

  # -- controle: original preserva a linha ao transicionar para stale --
  "$ORIG_PLUGIN_DIR/scripts/jira-map.sh" link-put --feature demo --from 1 --to 2 \
    --blocker-key DEMO-1 --blocked-key DEMO-2 --type-id 10000 --state active >/dev/null || return 1
  "$ORIG_PLUGIN_DIR/scripts/jira-map.sh" link-put --feature demo --from 1 --to 2 \
    --blocker-key DEMO-1 --blocked-key DEMO-2 --type-id 10000 --state stale \
    --reason anchor_changed >/dev/null || return 1
  grep -q '^1	2	DEMO-1	DEMO-2	10000	stale	anchor_changed$' "$_lf" \
    || { _fail "control_row_present" "linha stale ausente no original — controle invalido"; return 1; }
  rm -f "$_lf"

  # -- mutante: reverte 18.3.2 para nao reescrever (efetivamente remover)
  # a linha casada pela chave natural --
  _mp=$(_mut_copy_plugin)
  _jm="$_mp/scripts/jira-map.sh"
  grep -qF '          print a, b, bk, bd, tid, st, rs' "$_jm" \
    || { _fail "mutant_stale" "linha de upsert do link-put nao encontrada — repo mudou"; return 1; }
  sed 's/^          print a, b, bk, bd, tid, st, rs$/          # mutated-removed/' \
    "$_jm" > "$_jm.mut" && mv "$_jm.mut" "$_jm"
  grep -qF '          print a, b, bk, bd, tid, st, rs' "$_jm" \
    && { _fail "mutant_apply" "sed nao aplicou a mutacao de link-put"; return 1; }
  chmod +x "$_jm"

  "$_jm" link-put --feature demo --from 1 --to 2 --blocker-key DEMO-1 \
    --blocked-key DEMO-2 --type-id 10000 --state active >/dev/null || return 1
  capture "$_jm" link-put --feature demo --from 1 --to 2 --blocker-key DEMO-1 \
    --blocked-key DEMO-2 --type-id 10000 --state stale --reason anchor_changed
  [ "$_CAPTURED_EXIT" = "0" ] \
    || { _fail "mutant_put_exit" "link-put mutante deveria continuar exit 0, obtido $_CAPTURED_EXIT"; return 1; }

  if grep -q '^1	2	DEMO-1	DEMO-2	10000	stale	anchor_changed$' "$_lf"; then
    _fail "mutant_row_still_present" "esperado a linha DESAPARECER com a mutacao (regressao nao detectada)"
    return 1
  fi
  return 0
}

run_all_scenarios
