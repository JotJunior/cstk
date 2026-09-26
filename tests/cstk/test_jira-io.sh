#!/bin/sh
# test_jira-io.sh — cobre plugins/cstk-jira/scripts/jira-io.sh, tarefa 3.1
# (cstk-jira, FASE 3 "Cliente REST Seguro").
#
# Ref: docs/specs/cstk-jira/plan.md SEC-5; docs/specs/cstk-jira/
#      contracts/plugin-scripts.md `jira-io.sh`; tasks.md 3.1.1-3.1.7.
#
# Escopo desta suite (mesmo escopo do script nesta tarefa): so a mecanica
# `deps-check` + `request` (host unico, allowlist de METHOD, recusa de
# redirect). NAO cobre allowlist de charset (3.2), credencial (3.3),
# classificacao fina de status HTTP (3.4) nem json-get/json-build (3.5) —
# cada uma ganha sua propria suite quando a tarefa correspondente rodar.
#
# Estrategia: NENHUM cenario toca rede. O cliente HTTP e sempre um STUB
# (arquivo executavel `curl` instalado num diretorio de teste e injetado no
# PATH), que registra cada chamada em `io-curl-calls.log` — esse log e a
# prova de que uma resposta 3xx nunca dispara uma segunda requisicao
# (contracts/plugin-scripts.md "NAO segue redirect para host diferente").
#
# Licao ja registrada no repo (project_test_path_stub_cannot_hide_usrbin):
# um stub simplesmente PREPENDED ao PATH nao esconde um binario real em
# /usr/bin — por isso os cenarios de "dependencia ausente" (JI-1/JI-2/JI-3)
# usam PATH MINIMO EXPLICITO (substituicao total, nunca prefixo) apontando
# so para um diretorio de teste vazio ou com exatamente o binario desejado.
# Os demais cenarios (fluxo normal de `request`) so precisam GARANTIR que o
# cliente HTTP resolvido seja o stub — usar prefixo (`$_bin:$PATH`) e
# suficiente e mais simples, porque o objetivo ali nao e provar ausencia,
# e sim substituir o comportamento de rede.
#
# Invariantes cobertos:
#   JI-1  deps-check: jq E cliente HTTP ausentes -> exit 5, cita os dois
#   JI-2  deps-check: so jq ausente -> exit 5, cita jq
#   JI-3  deps-check: so o cliente HTTP ausente -> exit 5, cita curl
#   JI-4  deps-check: ambos presentes -> exit 0
#   JI-5  request GET valido: monta https://<site_host><PATH>, corpo da
#         resposta em stdout, `http_status=<codigo>` em stderr, EXATAMENTE
#         1 chamada ao cliente HTTP com a URL/metodo corretos
#   JI-6  request POST com --body-file: corpo repassado ao cliente HTTP,
#         sucesso
#   JI-7  request METHOD=DELETE -> exit 2 (uso incorreto), NENHUMA
#         requisicao (DELETE nunca existe como opcao valida — FR-012)
#   JI-8  request METHOD fora da allowlist (ex. PATCH) -> exit 2
#   JI-9  request PATH sem prefixo /rest/ -> exit 2
#   JI-10 request --body-file apontando para arquivo inexistente -> exit 2
#   JI-11 request sem ProjectConfig -> exit 3 (propagado de jira-config.sh)
#   JI-12 request: resposta 3xx (redirect simulado para outro dominio) ->
#         exit 1, recusada SEM disparar uma segunda requisicao (SEC-5)

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk-jira/scripts/jira-io.sh"

# _write_site_host_config HOST — cria ProjectConfig minimo (so o suficiente
# para `jira-config.sh get site_host`, que nao exige os demais campos
# obrigatorios de `validate`).
_write_site_host_config() {
  mkdir -p "$TMPDIR_TEST/.claude/cstk-jira"
  printf 'site_host=%s\n' "$1" > "$TMPDIR_TEST/.claude/cstk-jira/config"
}

# _write_dummy_bin DIR NAME — executavel que so retorna sucesso; usado nos
# cenarios de deps-check onde so a PRESENCA no PATH importa (o binario
# nunca e de fato invocado por deps-check).
_write_dummy_bin() {
  mkdir -p "$1"
  cat > "$1/$2" <<'EOF'
#!/bin/sh
exit 0
EOF
  chmod +x "$1/$2"
}

# _make_curl_stub MAPA — instala um `curl` fake em $TMPDIR_TEST/bin que:
#   - NUNCA toca rede;
#   - registra "METHOD URL" de cada chamada em io-curl-calls.log (prova de
#     quantas requisicoes de fato saíram);
#   - responde de acordo com MAPA: linhas "url-exato|http_code|corpo".
# Imprime o path do diretorio do stub em stdout.
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

# ==== JI-1..JI-4: deps-check, PATH minimo explicito (substituicao total) ===

scenario_deps_check_ambos_ausentes_exit5() {
  _bin="$TMPDIR_TEST/bin-none"
  mkdir -p "$_bin"
  assert_exit 5 env PATH="$_bin" "$SCRIPT" deps-check || return 1
  assert_stderr_contains "jq" || return 1
  assert_stderr_contains "curl" || return 1
}

scenario_deps_check_so_jq_ausente_exit5() {
  _bin="$TMPDIR_TEST/bin-nojq"
  _write_dummy_bin "$_bin" "curl"
  assert_exit 5 env PATH="$_bin" "$SCRIPT" deps-check || return 1
  assert_stderr_contains "jq" || return 1
}

scenario_deps_check_so_curl_ausente_exit5() {
  _jqbin=$(command -v jq 2>/dev/null) || { _error "sem_jq_no_host" "jq indisponivel no ambiente de teste"; return 2; }
  _bin="$TMPDIR_TEST/bin-nocurl"
  mkdir -p "$_bin"
  ln -sf "$_jqbin" "$_bin/jq"
  assert_exit 5 env PATH="$_bin" "$SCRIPT" deps-check || return 1
  assert_stderr_contains "curl" || return 1
}

scenario_deps_check_ambos_presentes_exit0() {
  _jqbin=$(command -v jq 2>/dev/null) || { _error "sem_jq_no_host" "jq indisponivel no ambiente de teste"; return 2; }
  _bin="$TMPDIR_TEST/bin-both"
  mkdir -p "$_bin"
  ln -sf "$_jqbin" "$_bin/jq"
  _write_dummy_bin "$_bin" "curl"
  assert_exit 0 env PATH="$_bin" "$SCRIPT" deps-check || return 1
}

# ==== JI-5..JI-12: request (deps reais do ambiente; curl trocado por stub
# apenas quando o fluxo de fato chega a disparar uma requisicao) ====

scenario_request_get_sucesso_monta_url_e_uma_unica_chamada() {
  cd "$TMPDIR_TEST" || return 1
  _write_site_host_config "example.atlassian.net"
  _bin=$(_make_curl_stub 'https://example.atlassian.net/rest/api/3/issue/CSTK-1|200|{"key":"CSTK-1"}')
  assert_exit 0 env PATH="$_bin:$PATH" "$SCRIPT" request GET /rest/api/3/issue/CSTK-1 || return 1
  assert_stdout_contains '"key":"CSTK-1"' || return 1
  assert_stderr_contains "http_status=200" || return 1
  [ "$(_curl_call_count)" = "1" ] || { _fail "request get calls" "esperado 1 chamada, obtido $(_curl_call_count)"; return 1; }
  grep -q '^GET https://example.atlassian.net/rest/api/3/issue/CSTK-1$' "$TMPDIR_TEST/io-curl-calls.log" \
    || { _fail "request get url" "URL/metodo montados incorretamente: $(cat "$TMPDIR_TEST/io-curl-calls.log")"; return 1; }
}

scenario_request_post_com_body_file_sucesso() {
  cd "$TMPDIR_TEST" || return 1
  _write_site_host_config "example.atlassian.net"
  printf '{"fields":{"summary":"x"}}' > "$TMPDIR_TEST/body.json"
  _bin=$(_make_curl_stub 'https://example.atlassian.net/rest/api/3/issue|201|{"id":"10001","key":"CSTK-9"}')
  assert_exit 0 env PATH="$_bin:$PATH" "$SCRIPT" request POST /rest/api/3/issue --body-file "$TMPDIR_TEST/body.json" || return 1
  assert_stdout_contains '"key":"CSTK-9"' || return 1
  assert_stderr_contains "http_status=201" || return 1
  grep -q '^POST https://example.atlassian.net/rest/api/3/issue$' "$TMPDIR_TEST/io-curl-calls.log" \
    || { _fail "request post method" "metodo POST nao encontrado no log do stub"; return 1; }
}

scenario_request_method_delete_exit2_sem_requisicao() {
  cd "$TMPDIR_TEST" || return 1
  _write_site_host_config "example.atlassian.net"
  _bin=$(_make_curl_stub 'https://example.atlassian.net/rest/api/3/issue/CSTK-1|200|{}')
  assert_exit 2 env PATH="$_bin:$PATH" "$SCRIPT" request DELETE /rest/api/3/issue/CSTK-1 || return 1
  assert_stderr_contains "DELETE" || return 1
  [ "$(_curl_call_count)" = "0" ] || { _fail "delete calls" "DELETE nao deve disparar nenhuma requisicao"; return 1; }
}

scenario_request_method_fora_da_allowlist_exit2() {
  cd "$TMPDIR_TEST" || return 1
  _write_site_host_config "example.atlassian.net"
  assert_exit 2 "$SCRIPT" request PATCH /rest/api/3/issue/CSTK-1 || return 1
}

scenario_request_path_sem_prefixo_rest_exit2() {
  cd "$TMPDIR_TEST" || return 1
  _write_site_host_config "example.atlassian.net"
  assert_exit 2 "$SCRIPT" request GET /api/3/issue/CSTK-1 || return 1
  assert_stderr_contains "/rest/" || return 1
}

scenario_request_body_file_inexistente_exit2() {
  cd "$TMPDIR_TEST" || return 1
  _write_site_host_config "example.atlassian.net"
  assert_exit 2 "$SCRIPT" request POST /rest/api/3/issue --body-file "$TMPDIR_TEST/nao-existe.json" || return 1
}

scenario_request_sem_projectconfig_exit3() {
  cd "$TMPDIR_TEST" || return 1
  # ProjectConfig deliberadamente ausente.
  assert_exit 3 "$SCRIPT" request GET /rest/api/3/issue/CSTK-1 || return 1
}

scenario_request_redirect_3xx_recusado_sem_nova_requisicao() {
  cd "$TMPDIR_TEST" || return 1
  _write_site_host_config "example.atlassian.net"
  _bin=$(_make_curl_stub 'https://example.atlassian.net/rest/api/3/issue/CSTK-1|302|')
  assert_exit 1 env PATH="$_bin:$PATH" "$SCRIPT" request GET /rest/api/3/issue/CSTK-1 || return 1
  assert_stderr_contains "302" || return 1
  assert_stderr_contains "SEC-5" || return 1
  [ "$(_curl_call_count)" = "1" ] \
    || { _fail "redirect calls" "esperado exatamente 1 chamada (sem nova requisicao), obtido $(_curl_call_count)"; return 1; }
}

run_all_scenarios
