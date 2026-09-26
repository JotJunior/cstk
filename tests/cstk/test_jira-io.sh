#!/bin/sh
# test_jira-io.sh — cobre plugins/cstk-jira/scripts/jira-io.sh, tarefas
# 3.1-3.5 (cstk-jira, FASE 3 "Cliente REST Seguro").
#
# Ref: docs/specs/cstk-jira/plan.md SEC-1, SEC-3, SEC-4, SEC-5, Test Strategy
#      "Falha"; docs/specs/cstk-jira/contracts/plugin-scripts.md `jira-io.sh`;
#      contracts/jira-rest.md (R1/R2/R4/R9); checklists/api.md CHK009;
#      checklists/security.md CHK002/CHK003; tasks.md 3.1.1-3.1.7,
#      3.2.1-3.2.5, 3.3.1-3.3.5, 3.4.1-3.4.7, 3.5.1-3.5.5; dec-073.
#
# Escopo desta suite (mesmo escopo do script ate esta tarefa): `deps-check`
# + `request` (host unico, allowlist de METHOD, recusa de redirect, allowlist
# de charset em PATH/SEC-1, credencial temporaria segura/SEC-4, e desde a
# tarefa 3.4 tambem classificacao fina de status HTTP: `401`/`403`(`--op`
# R1/R2 vs demais)/`429`(`Retry-After`)/`5xx`-e-rede-com-backoff/`400`-`409`-
# em-R4) + `validate-segment` + (desde a tarefa 3.5) `json-get`/`json-build`
# (issue/filter) e a recusa de JQL com texto livre (SEC-3).
#
# JI-33..JI-47 (tarefa 3.4): ver bloco de comentarios proprio logo antes dos
# cenarios correspondentes, mais abaixo neste arquivo.
#
# A partir da tarefa 3.3, TODO cenario que alcanca o disparo real de `curl`
# (JI-5, JI-6, JI-12 e os novos JI-27+) precisa de uma credencial valida —
# `request` agora recusa (exit 4) ANTES de montar a URL/disparar a
# requisicao se `jira-config.sh credential-check` falhar. `_write_credential`
# (abaixo) cria essa credencial isolada via `XDG_CONFIG_HOME=$TMPDIR_TEST/xdg`
# — NUNCA toca `~/.config/cstk-jira/credentials` do operador. Os cenarios que
# falham ANTES da resolucao de credencial (JI-1..4, 7-11, 13-26) permanecem
# sem essa fixture, porque nunca alcancam aquele ponto do fluxo.
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
#
# JI-13..JI-21 (tarefa 3.2, SEC-1): cada byte/sequencia proibida no PATH de
# `request`, ISOLADAMENTE, causa exit 2 SEM disparar nenhuma requisicao
# (mutation-test mental: remover `_ji_path_has_forbidden_bytes` da tarefa
# 3.2 faz TODOS estes cenarios falhar, porque a chamada chegaria ao stub e
# ganharia exit 0/1 em vez de 2 com zero chamadas):
#   JI-13 PATH com `..`             -> exit 2, 0 chamadas
#   JI-14 PATH com `//`             -> exit 2, 0 chamadas
#   JI-15 PATH com `\`              -> exit 2, 0 chamadas
#   JI-16 PATH com `@`              -> exit 2, 0 chamadas
#   JI-17 PATH com `#`              -> exit 2, 0 chamadas
#   JI-18 PATH com espaco           -> exit 2, 0 chamadas
#   JI-19 PATH com CR               -> exit 2, 0 chamadas
#   JI-20 PATH com LF               -> exit 2, 0 chamadas
#   JI-21 PATH com byte de controle generico (TAB) -> exit 2, 0 chamadas
#
# JI-22..JI-26 (tarefa 3.2, SEC-1): subcomando `validate-segment`:
#   JI-22 VALUE valido (`[A-Za-z0-9_-]`, ex. jira_key/jira_id/project_key)
#         -> exit 0, para 1 ou varios VALUE de uma vez
#   JI-23 VALUE com espaco          -> exit 2
#   JI-24 VALUE com `/`             -> exit 2
#   JI-25 2 VALUE, o 2o fora do charset -> exit 2 (recusa mesmo quando so
#         um dos varios segmentos e invalido)
#   JI-26 chamada sem nenhum VALUE  -> exit 2 (uso incorreto)
#
# JI-27..JI-32 (tarefa 3.3, SEC-4): credencial temporaria segura:
#   JI-27 sem arquivo de credencial            -> exit 4, 0 chamadas
#   JI-28 credencial incompleta (so `email`, falta `api_token`) -> exit 4,
#         0 chamadas
#   JI-29 credencial completa: sucesso normal; `api_token`/`email` NUNCA
#         aparecem na linha de log do stub (argv observavel), so no
#         conteudo do arquivo `-K`
#   JI-30 modo do arquivo de config temporario e EXATAMENTE 0600 enquanto
#         a chamada esta em andamento (stub lento + checagem externa)
#   JI-31 mutation: SIGTERM a meio da chamada -> arquivo/diretorio de
#         credencial removidos mesmo assim (prova de que o `trap` limpa)
#   JI-32 mutation: SIGINT a meio da chamada  -> mesma prova, outro sinal

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

# _write_credential [EMAIL] [TOKEN] — cria a credencial GLOBAL isolada em
# $TMPDIR_TEST/xdg/cstk-jira/credentials (0600). SEMPRE combinar com
# `XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"` na invocacao do script sob teste —
# sem isso, jira-io.sh cairia no fallback `$HOME/.config` e poderia ler (ou
# recusar por causa de) uma credencial REAL do operador.
_write_credential() {
  mkdir -p "$TMPDIR_TEST/xdg/cstk-jira"
  printf 'email=%s\napi_token=%s\n' "${1:-tester@example.com}" "${2:-tok-FAKE-000}" \
    > "$TMPDIR_TEST/xdg/cstk-jira/credentials"
  chmod 600 "$TMPDIR_TEST/xdg/cstk-jira/credentials"
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

# _make_tracking_curl_stub MAPA — como _make_curl_stub (mesmo formato de
# MAPA, mesmo io-curl-calls.log), mas TAMBEM grava o argv completo (um
# token por linha) em io-curl-argv.log e uma COPIA do conteudo do arquivo
# `-K` em io-curl-kfile-snapshot — feita no MOMENTO da chamada, porque o
# proprio jira-io.sh remove esse arquivo via trap assim que a chamada
# termina (o snapshot e a unica forma de inspecionar o conteudo depois).
# Deliberadamente um stub SEPARADO de _make_curl_stub (nao estende o
# helper existente) para nao arriscar nenhum efeito colateral nos 26
# cenarios ja verdes das tarefas 3.1/3.2.
_make_tracking_curl_stub() {
  _stub_dir="$TMPDIR_TEST/bin-track"
  mkdir -p "$_stub_dir"
  printf '%s\n' "$1" > "$TMPDIR_TEST/io-curl-track-map"
  : > "$TMPDIR_TEST/io-curl-calls.log"
  : > "$TMPDIR_TEST/io-curl-argv.log"
  cat > "$_stub_dir/curl" <<STUB
#!/bin/sh
_url=""
_out=""
_method="GET"
_kfile=""
_prev=""
for _a in "\$@"; do
  case "\$_prev" in
    -o) _out="\$_a" ;;
    -X) _method="\$_a" ;;
    -K) _kfile="\$_a" ;;
  esac
  case "\$_a" in
    https://*) _url="\$_a" ;;
  esac
  printf '%s\n' "\$_a" >> "$TMPDIR_TEST/io-curl-argv.log"
  _prev="\$_a"
done
if [ -n "\$_kfile" ]; then
  cat -- "\$_kfile" > "$TMPDIR_TEST/io-curl-kfile-snapshot" 2>/dev/null
fi
printf '%s %s\n' "\$_method" "\$_url" >> "$TMPDIR_TEST/io-curl-calls.log"
while IFS='|' read -r _pat _code _body; do
  [ -n "\$_pat" ] || continue
  if [ "\$_url" = "\$_pat" ]; then
    [ -n "\$_out" ] && printf '%s' "\$_body" > "\$_out"
    printf '%s' "\$_code"
    exit 0
  fi
done < "$TMPDIR_TEST/io-curl-track-map"
exit 22
STUB
  chmod +x "$_stub_dir/curl"
  printf '%s' "$_stub_dir"
}

# _make_modecheck_curl_stub — stub que, ao receber `-K PATH`, mede o modo
# de PATH NA HORA (enquanto a "requisicao" esta em andamento — e o
# equivalente a "durante a execucao" da tarefa 3.3.4, ja que este processo
# E a execucao do cliente HTTP) e grava em io-curl-kfile-mode; responde
# 200 normalmente em seguida (a chamada de `request` termina com sucesso).
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

# _make_selfkill_curl_stub SIGNAL — stub que grava o path de `-K` em
# io-curl-kfile-path e entao se auto-envia (via kill -SIGNAL $PPID) o
# sinal indicado para o PROPRIO jira-io.sh (seu processo pai — a
# substituicao de comando `$(curl ...)` executa o cliente HTTP como exec
# direto do subshell de substituicao, entao $PPID aqui E o processo
# jira-io.sh que esta bloqueado esperando esta chamada). Simula "sinal a
# meio de uma chamada" (tarefa 3.3.5) de forma determinista, SEM precisar
# background+poll+kill externo — o que evitaria a pegadinha POSIX ja
# documentada no repo (test_00c-bootstrap.sh): jobs assincronos (`&`)
# herdam SIGINT como SIG_IGN, entao um `kill -INT` externo a um processo
# backgrounded pelo TESTE nao teria efeito algum. Aqui a chamada a
# jira-io.sh permanece em FOREGROUND (via `capture`), entao nenhum sinal
# fica pre-ignorado.
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

# _make_headers_curl_stub CODE [HEADERS] [BODY] — 3.4.4: stub que, ao
# receber `-D PATH`, grava HEADERS (conteudo literal, ex.: uma linha
# `Retry-After: 30`) nesse arquivo — simulando os headers de resposta reais
# — e responde CODE/BODY normalmente. Usado para JI-38/JI-39 (429 sem/com
# `Retry-After`).
_make_headers_curl_stub() {
  _stub_dir="$TMPDIR_TEST/bin-headers"
  mkdir -p "$_stub_dir"
  _code="$1"
  printf '%s' "${2:-}" > "$TMPDIR_TEST/io-curl-headers-content"
  printf '%s' "${3:-}" > "$TMPDIR_TEST/io-curl-headers-body"
  : > "$TMPDIR_TEST/io-curl-calls.log"
  cat > "$_stub_dir/curl" <<STUB
#!/bin/sh
_out=""
_dfile=""
_prev=""
for _a in "\$@"; do
  case "\$_prev" in
    -o) _out="\$_a" ;;
    -D) _dfile="\$_a" ;;
  esac
  _prev="\$_a"
done
printf 'CALL\n' >> "$TMPDIR_TEST/io-curl-calls.log"
[ -n "\$_dfile" ] && cat -- "$TMPDIR_TEST/io-curl-headers-content" > "\$_dfile"
[ -n "\$_out" ] && cat -- "$TMPDIR_TEST/io-curl-headers-body" > "\$_out"
printf '%s' "$_code"
exit 0
STUB
  chmod +x "$_stub_dir/curl"
  printf '%s' "$_stub_dir"
}

# _make_flaky_curl_stub CODES [BODY] — 3.4.5: stub cujo status varia por
# TENTATIVA (nao por URL): a Na chamada recebe o Na token de CODES
# (separado por espaco); esgotados os tokens, repete o ULTIMO. BODY
# (opcional) e sempre escrito em `-o` (so importa quando o attempt final
# classificar como sucesso). Loga cada chamada em io-curl-calls.log (mesma
# convencao de `_curl_call_count`) — a PROVA do numero de tentativas.
_make_flaky_curl_stub() {
  _stub_dir="$TMPDIR_TEST/bin-flaky"
  mkdir -p "$_stub_dir"
  : > "$TMPDIR_TEST/io-curl-calls.log"
  : > "$TMPDIR_TEST/io-curl-flaky-count"
  printf '%s\n' "$1" | tr ' ' '\n' > "$TMPDIR_TEST/io-curl-flaky-codes"
  printf '%s' "${2:-}" > "$TMPDIR_TEST/io-curl-flaky-body"
  cat > "$_stub_dir/curl" <<STUB
#!/bin/sh
_out=""
_prev=""
for _a in "\$@"; do
  case "\$_prev" in
    -o) _out="\$_a" ;;
  esac
  _prev="\$_a"
done
printf 'CALL\n' >> "$TMPDIR_TEST/io-curl-calls.log"
_n=\$(( \$(wc -l < "$TMPDIR_TEST/io-curl-flaky-count" | tr -d ' ') + 1 ))
printf 'x\n' >> "$TMPDIR_TEST/io-curl-flaky-count"
_total=\$(wc -l < "$TMPDIR_TEST/io-curl-flaky-codes" | tr -d ' ')
[ "\$_n" -le "\$_total" ] || _n="\$_total"
_code=\$(sed -n "\${_n}p" "$TMPDIR_TEST/io-curl-flaky-codes")
[ -n "\$_out" ] && cat -- "$TMPDIR_TEST/io-curl-flaky-body" > "\$_out"
printf '%s' "\$_code"
exit 0
STUB
  chmod +x "$_stub_dir/curl"
  printf '%s' "$_stub_dir"
}

# _make_networkfail_curl_stub — 3.4.5: stub que SEMPRE falha como o cliente
# HTTP falharia por erro de rede real (sem tocar rede) — `exit 7` e o codigo
# real de curl para "Failed to connect to host". Usado para JI-45 (erro de
# rede esgota as tentativas).
_make_networkfail_curl_stub() {
  _stub_dir="$TMPDIR_TEST/bin-netfail"
  mkdir -p "$_stub_dir"
  : > "$TMPDIR_TEST/io-curl-calls.log"
  cat > "$_stub_dir/curl" <<STUB
#!/bin/sh
printf 'CALL\n' >> "$TMPDIR_TEST/io-curl-calls.log"
exit 7
STUB
  chmod +x "$_stub_dir/curl"
  printf '%s' "$_stub_dir"
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
  _write_credential
  _bin=$(_make_curl_stub 'https://example.atlassian.net/rest/api/3/issue/CSTK-1|200|{"key":"CSTK-1"}')
  assert_exit 0 env PATH="$_bin:$PATH" XDG_CONFIG_HOME="$TMPDIR_TEST/xdg" "$SCRIPT" request GET /rest/api/3/issue/CSTK-1 || return 1
  assert_stdout_contains '"key":"CSTK-1"' || return 1
  assert_stderr_contains "http_status=200" || return 1
  [ "$(_curl_call_count)" = "1" ] || { _fail "request get calls" "esperado 1 chamada, obtido $(_curl_call_count)"; return 1; }
  grep -q '^GET https://example.atlassian.net/rest/api/3/issue/CSTK-1$' "$TMPDIR_TEST/io-curl-calls.log" \
    || { _fail "request get url" "URL/metodo montados incorretamente: $(cat "$TMPDIR_TEST/io-curl-calls.log")"; return 1; }
}

scenario_request_post_com_body_file_sucesso() {
  cd "$TMPDIR_TEST" || return 1
  _write_site_host_config "example.atlassian.net"
  _write_credential
  printf '{"fields":{"summary":"x"}}' > "$TMPDIR_TEST/body.json"
  _bin=$(_make_curl_stub 'https://example.atlassian.net/rest/api/3/issue|201|{"id":"10001","key":"CSTK-9"}')
  assert_exit 0 env PATH="$_bin:$PATH" XDG_CONFIG_HOME="$TMPDIR_TEST/xdg" "$SCRIPT" request POST /rest/api/3/issue --body-file "$TMPDIR_TEST/body.json" || return 1
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
  _write_credential
  _bin=$(_make_curl_stub 'https://example.atlassian.net/rest/api/3/issue/CSTK-1|302|')
  assert_exit 1 env PATH="$_bin:$PATH" XDG_CONFIG_HOME="$TMPDIR_TEST/xdg" "$SCRIPT" request GET /rest/api/3/issue/CSTK-1 || return 1
  assert_stderr_contains "302" || return 1
  assert_stderr_contains "SEC-5" || return 1
  [ "$(_curl_call_count)" = "1" ] \
    || { _fail "redirect calls" "esperado exatamente 1 chamada (sem nova requisicao), obtido $(_curl_call_count)"; return 1; }
}

# ==== JI-13..JI-21: request PATH com byte/sequencia proibida (SEC-1) ====

# _assert_path_recusado_sem_requisicao PATH — helper comum: monta stub de
# curl que responderia 200 se fosse chamado, dispara `request GET PATH`,
# confere exit 2 + zero chamadas ao cliente HTTP.
_assert_path_recusado_sem_requisicao() {
  cd "$TMPDIR_TEST" || return 1
  _write_site_host_config "example.atlassian.net"
  _bin=$(_make_curl_stub 'https://example.atlassian.net/rest/api/3/issue/CSTK-1|200|{}')
  assert_exit 2 env PATH="$_bin:$PATH" "$SCRIPT" request GET "$1" || return 1
  assert_stderr_contains "SEC-1" || return 1
  [ "$(_curl_call_count)" = "0" ] \
    || { _fail "path forbidden calls" "PATH proibido nao deve disparar nenhuma requisicao: $(cat "$TMPDIR_TEST/io-curl-calls.log")"; return 1; }
}

scenario_request_path_com_dotdot_exit2_sem_requisicao() {
  _assert_path_recusado_sem_requisicao "/rest/api/3/../secret"
}

scenario_request_path_com_barra_dupla_exit2_sem_requisicao() {
  _assert_path_recusado_sem_requisicao "/rest/api//3/issue"
}

scenario_request_path_com_barra_invertida_exit2_sem_requisicao() {
  _assert_path_recusado_sem_requisicao "/rest/api/3/issue$(printf '\134')CSTK-1"
}

scenario_request_path_com_arroba_exit2_sem_requisicao() {
  _assert_path_recusado_sem_requisicao "/rest/api/3/issue/CSTK-1@evil"
}

scenario_request_path_com_hash_exit2_sem_requisicao() {
  _assert_path_recusado_sem_requisicao "/rest/api/3/issue/CSTK-1#frag"
}

scenario_request_path_com_espaco_exit2_sem_requisicao() {
  _assert_path_recusado_sem_requisicao "/rest/api/3/issue/CSTK 1"
}

scenario_request_path_com_cr_exit2_sem_requisicao() {
  _assert_path_recusado_sem_requisicao "$(printf '/rest/api/3/issue/CSTK-1\r')"
}

scenario_request_path_com_lf_exit2_sem_requisicao() {
  _assert_path_recusado_sem_requisicao "$(printf '/rest/api/3/issue/CSTK-1\ntail')"
}

scenario_request_path_com_controle_generico_exit2_sem_requisicao() {
  _assert_path_recusado_sem_requisicao "$(printf '/rest/api/3/issue/CSTK\t1')"
}

# ==== JI-22..JI-26: validate-segment (SEC-1) ====

scenario_validate_segment_valores_validos_exit0() {
  assert_exit 0 "$SCRIPT" validate-segment "CSTK-123" || return 1
  assert_exit 0 "$SCRIPT" validate-segment "CSTK-1" "10001" "abc_def" "PROJ" || return 1
}

scenario_validate_segment_com_espaco_exit2() {
  assert_exit 2 "$SCRIPT" validate-segment "CSTK 1" || return 1
  assert_stderr_contains "SEC-1" || return 1
}

scenario_validate_segment_com_barra_exit2() {
  assert_exit 2 "$SCRIPT" validate-segment "CSTK/1" || return 1
  assert_stderr_contains "SEC-1" || return 1
}

scenario_validate_segment_segundo_valor_invalido_exit2() {
  assert_exit 2 "$SCRIPT" validate-segment "CSTK-1" "invalido com espaco" || return 1
}

scenario_validate_segment_sem_argumentos_exit2() {
  assert_exit 2 "$SCRIPT" validate-segment || return 1
}

# ==== JI-27..JI-32: credencial temporaria segura (SEC-4, tarefa 3.3) ====

scenario_request_sem_credencial_exit4_sem_requisicao() {
  cd "$TMPDIR_TEST" || return 1
  _write_site_host_config "example.atlassian.net"
  # Credencial deliberadamente ausente (nao chama _write_credential).
  _bin=$(_make_curl_stub 'https://example.atlassian.net/rest/api/3/issue/CSTK-1|200|{}')
  assert_exit 4 env PATH="$_bin:$PATH" XDG_CONFIG_HOME="$TMPDIR_TEST/xdg" "$SCRIPT" request GET /rest/api/3/issue/CSTK-1 || return 1
  [ "$(_curl_call_count)" = "0" ] \
    || { _fail "sem_credencial_calls" "credencial ausente nao deve disparar nenhuma requisicao"; return 1; }
}

scenario_request_credencial_incompleta_exit4_sem_requisicao() {
  cd "$TMPDIR_TEST" || return 1
  _write_site_host_config "example.atlassian.net"
  mkdir -p "$TMPDIR_TEST/xdg/cstk-jira"
  printf 'email=tester@example.com\n' > "$TMPDIR_TEST/xdg/cstk-jira/credentials"
  chmod 600 "$TMPDIR_TEST/xdg/cstk-jira/credentials"
  _bin=$(_make_curl_stub 'https://example.atlassian.net/rest/api/3/issue/CSTK-1|200|{}')
  assert_exit 4 env PATH="$_bin:$PATH" XDG_CONFIG_HOME="$TMPDIR_TEST/xdg" "$SCRIPT" request GET /rest/api/3/issue/CSTK-1 || return 1
  assert_stderr_contains "api_token" || return 1
  [ "$(_curl_call_count)" = "0" ] \
    || { _fail "credencial_incompleta_calls" "api_token ausente nao deve disparar nenhuma requisicao"; return 1; }
}

scenario_request_credencial_sucesso_token_fora_do_argv() {
  cd "$TMPDIR_TEST" || return 1
  _write_site_host_config "example.atlassian.net"
  _write_credential "ji29@example.com" "tok-JI29-SECRET"
  _bin=$(_make_tracking_curl_stub 'https://example.atlassian.net/rest/api/3/issue/CSTK-1|200|{"key":"CSTK-1"}')
  assert_exit 0 env PATH="$_bin:$PATH" XDG_CONFIG_HOME="$TMPDIR_TEST/xdg" "$SCRIPT" request GET /rest/api/3/issue/CSTK-1 || return 1
  assert_stdout_contains '"key":"CSTK-1"' || return 1

  # SEC-4/3.3.3: api_token/email NUNCA aparecem em nenhum token de argv do
  # cliente HTTP (mutation mental: trocar `-K` por `-u email:token` na
  # linha de comando faria este grep casar e o cenario falhar).
  if grep -qF "tok-JI29-SECRET" "$TMPDIR_TEST/io-curl-argv.log"; then
    _fail "cred_in_argv" "api_token vazou para argv do cliente HTTP"
    return 1
  fi
  if grep -qF "ji29@example.com" "$TMPDIR_TEST/io-curl-argv.log"; then
    _fail "email_in_argv" "email vazou para argv do cliente HTTP"
    return 1
  fi

  # Mas a credencial DEVE ter sido de fato entregue — via arquivo -K.
  [ -f "$TMPDIR_TEST/io-curl-kfile-snapshot" ] \
    || { _fail "no_kfile_snapshot" "-K nao foi passado ao cliente HTTP"; return 1; }
  grep -qF "tok-JI29-SECRET" "$TMPDIR_TEST/io-curl-kfile-snapshot" \
    || { _fail "kfile_missing_token" "arquivo -K nao continha o api_token esperado"; return 1; }
  grep -qF "ji29@example.com" "$TMPDIR_TEST/io-curl-kfile-snapshot" \
    || { _fail "kfile_missing_email" "arquivo -K nao continha o email esperado"; return 1; }
}

scenario_request_credencial_arquivo_modo_0600_durante_execucao() {
  cd "$TMPDIR_TEST" || return 1
  _write_site_host_config "example.atlassian.net"
  _write_credential
  _bin=$(_make_modecheck_curl_stub)
  assert_exit 0 env PATH="$_bin:$PATH" XDG_CONFIG_HOME="$TMPDIR_TEST/xdg" "$SCRIPT" request GET /rest/api/3/issue/CSTK-1 || return 1
  _modo=$(cat "$TMPDIR_TEST/io-curl-kfile-mode" 2>/dev/null)
  [ "$_modo" = "600" ] || { _fail "modo" "esperado 600, obtido '$_modo'"; return 1; }
}

# _assert_mutation_signal_remove_credencial SIGNAL EXIT_ESPERADO — helper
# comum de JI-31/JI-32: o stub de curl se auto-sinaliza (ver
# _make_selfkill_curl_stub) simulando um sinal fatal a MEIO da chamada;
# confere que jira-io.sh saiu com o exit code do trap correspondente E que
# o arquivo/diretorio temporario de credencial foram removidos mesmo assim
# (prova de que o `trap` de limpeza roda mesmo sob sinal, nao so no caso
# feliz de saida normal).
_assert_mutation_signal_remove_credencial() {
  _sig="$1"
  _exit_esperado="$2"
  cd "$TMPDIR_TEST" || return 1
  _write_site_host_config "example.atlassian.net"
  _write_credential
  _bin=$(_make_selfkill_curl_stub "$_sig")
  capture env PATH="$_bin:$PATH" XDG_CONFIG_HOME="$TMPDIR_TEST/xdg" \
    "$SCRIPT" request GET /rest/api/3/issue/CSTK-1
  [ "$_CAPTURED_EXIT" = "$_exit_esperado" ] \
    || { _fail "exit" "esperado $_exit_esperado (trap $_sig), obtido $_CAPTURED_EXIT"; return 1; }

  [ -s "$TMPDIR_TEST/io-curl-kfile-path" ] \
    || { _fail "no_kfile_path" "stub nao chegou a rodar (sem -K registrado)"; return 1; }
  _kfile=$(cat "$TMPDIR_TEST/io-curl-kfile-path")
  [ -n "$_kfile" ] || { _fail "kfile_vazio" "-K nao foi passado ao cliente HTTP"; return 1; }

  if [ -e "$_kfile" ]; then
    _fail "kfile_nao_removido" "arquivo de credencial temporario sobreviveu ao sinal $_sig: $_kfile"
    return 1
  fi
  _kdir=$(dirname "$_kfile")
  if [ -d "$_kdir" ]; then
    _fail "kdir_nao_removido" "diretorio privado de credencial sobreviveu ao sinal $_sig: $_kdir"
    return 1
  fi
}

scenario_request_mutation_sigterm_remove_credencial_temp() {
  _assert_mutation_signal_remove_credencial TERM 143
}

scenario_request_mutation_sigint_remove_credencial_temp() {
  _assert_mutation_signal_remove_credencial INT 130
}

# ==== JI-33..JI-47 (tarefa 3.4, dec-073): classificacao de status HTTP ====
#
# Todos os cenarios abaixo exportam `JIRA_IO_BACKOFF_SECONDS=0` (override de
# 3.4.5) para o backoff entre tentativas nao atrasar a suite — o VALOR do
# backoff nao e o que estes testes verificam, so a CONTAGEM de tentativas.
#
#   JI-33 401 (sem --op)              -> exit 4, classification=auth_failed
#   JI-34 403 --op R1                 -> exit 7, classification=permission_denied
#   JI-35 403 --op R2                 -> exit 7, classification=permission_denied
#   JI-36 403 sem --op                -> exit 4, classification=auth_failed (default conservador)
#   JI-37 403 --op R3 (fora de R1/R2) -> exit 4, classification=auth_failed
#   JI-38 429 sem header Retry-After  -> exit 1, classification=deferred, SEM retry_after=
#   JI-39 429 com header Retry-After  -> exit 1, classification=deferred, retry_after=<n> correto
#   JI-40 400 --op R4                 -> exit 1, classification=deferred
#   JI-41 409 --op R4                 -> exit 1, classification=deferred
#   JI-42 400 sem --op R4 (fora do escopo 3.4) -> exit 0, passthrough (comportamento pre-3.4 preservado)
#   JI-43 5xx esgota as 3 tentativas   -> exit 1, classification=deferred, EXATAMENTE 3 chamadas
#   JI-44 5xx then 200 (recupera na 2a tentativa) -> exit 0, corpo relayed, EXATAMENTE 2 chamadas
#   JI-45 erro de rede esgota as 3 tentativas -> exit 1, classification=deferred, EXATAMENTE 3 chamadas
#   JI-46 --op invalido               -> exit 2 (uso incorreto), 0 chamadas
#   JI-47 teste de contrato dedicado (3.4.7): 401 vs 403 R1/R2 vs 403 demais
#         vs 429 — os 4 casos SEM colisao no mesmo tratamento (CHK009)

scenario_request_401_auth_failed() {
  cd "$TMPDIR_TEST" || return 1
  _write_site_host_config "example.atlassian.net"
  _write_credential
  _bin=$(_make_curl_stub 'https://example.atlassian.net/rest/api/3/issue/CSTK-1|401|{}')
  assert_exit 4 env PATH="$_bin:$PATH" XDG_CONFIG_HOME="$TMPDIR_TEST/xdg" JIRA_IO_BACKOFF_SECONDS=0 \
    "$SCRIPT" request GET /rest/api/3/issue/CSTK-1 || return 1
  assert_stderr_contains "http_status=401" || return 1
  assert_stderr_contains "classification=auth_failed" || return 1
  [ "$(_curl_call_count)" = "1" ] || { _fail "401 calls" "esperado 1, obtido $(_curl_call_count)"; return 1; }
}

scenario_request_403_op_r1_permission_denied() {
  cd "$TMPDIR_TEST" || return 1
  _write_site_host_config "example.atlassian.net"
  _write_credential
  _bin=$(_make_curl_stub 'https://example.atlassian.net/rest/api/3/issue|403|{}')
  assert_exit 7 env PATH="$_bin:$PATH" XDG_CONFIG_HOME="$TMPDIR_TEST/xdg" JIRA_IO_BACKOFF_SECONDS=0 \
    "$SCRIPT" request POST /rest/api/3/issue --op R1 || return 1
  assert_stderr_contains "classification=permission_denied" || return 1
}

scenario_request_403_op_r2_permission_denied() {
  cd "$TMPDIR_TEST" || return 1
  _write_site_host_config "example.atlassian.net"
  _write_credential
  _bin=$(_make_curl_stub 'https://example.atlassian.net/rest/api/3/issue/CSTK-1|403|{}')
  assert_exit 7 env PATH="$_bin:$PATH" XDG_CONFIG_HOME="$TMPDIR_TEST/xdg" JIRA_IO_BACKOFF_SECONDS=0 \
    "$SCRIPT" request PUT /rest/api/3/issue/CSTK-1 --op R2 || return 1
  assert_stderr_contains "classification=permission_denied" || return 1
}

scenario_request_403_sem_op_auth_failed_default() {
  cd "$TMPDIR_TEST" || return 1
  _write_site_host_config "example.atlassian.net"
  _write_credential
  _bin=$(_make_curl_stub 'https://example.atlassian.net/rest/api/3/issue/CSTK-1|403|{}')
  assert_exit 4 env PATH="$_bin:$PATH" XDG_CONFIG_HOME="$TMPDIR_TEST/xdg" JIRA_IO_BACKOFF_SECONDS=0 \
    "$SCRIPT" request GET /rest/api/3/issue/CSTK-1 || return 1
  assert_stderr_contains "classification=auth_failed" || return 1
}

scenario_request_403_op_fora_de_r1_r2_auth_failed() {
  cd "$TMPDIR_TEST" || return 1
  _write_site_host_config "example.atlassian.net"
  _write_credential
  _bin=$(_make_curl_stub 'https://example.atlassian.net/rest/api/3/issue/CSTK-1/transitions|403|{}')
  assert_exit 4 env PATH="$_bin:$PATH" XDG_CONFIG_HOME="$TMPDIR_TEST/xdg" JIRA_IO_BACKOFF_SECONDS=0 \
    "$SCRIPT" request POST /rest/api/3/issue/CSTK-1/transitions --op R4 || return 1
  assert_stderr_contains "classification=auth_failed" || return 1
}

scenario_request_429_sem_retry_after() {
  cd "$TMPDIR_TEST" || return 1
  _write_site_host_config "example.atlassian.net"
  _write_credential
  _bin=$(_make_headers_curl_stub 429)
  assert_exit 1 env PATH="$_bin:$PATH" XDG_CONFIG_HOME="$TMPDIR_TEST/xdg" JIRA_IO_BACKOFF_SECONDS=0 \
    "$SCRIPT" request GET /rest/api/3/issue/CSTK-1 || return 1
  assert_stderr_contains "classification=deferred" || return 1
  case "${_CAPTURED_STDERR:-}" in
    *retry_after=*)
      _fail "retry_after_indevido" "429 sem header Retry-After nao deveria emitir retry_after="
      return 1
      ;;
  esac
}

scenario_request_429_com_retry_after() {
  cd "$TMPDIR_TEST" || return 1
  _write_site_host_config "example.atlassian.net"
  _write_credential
  _bin=$(_make_headers_curl_stub 429 "$(printf 'HTTP/1.1 429 Too Many Requests\r\nRetry-After: 30\r\n')")
  assert_exit 1 env PATH="$_bin:$PATH" XDG_CONFIG_HOME="$TMPDIR_TEST/xdg" JIRA_IO_BACKOFF_SECONDS=0 \
    "$SCRIPT" request GET /rest/api/3/issue/CSTK-1 || return 1
  assert_stderr_contains "classification=deferred" || return 1
  assert_stderr_contains "retry_after=30" || return 1
}

scenario_request_400_op_r4_deferred() {
  cd "$TMPDIR_TEST" || return 1
  _write_site_host_config "example.atlassian.net"
  _write_credential
  _bin=$(_make_curl_stub 'https://example.atlassian.net/rest/api/3/issue/CSTK-1/transitions|400|{}')
  assert_exit 1 env PATH="$_bin:$PATH" XDG_CONFIG_HOME="$TMPDIR_TEST/xdg" JIRA_IO_BACKOFF_SECONDS=0 \
    "$SCRIPT" request POST /rest/api/3/issue/CSTK-1/transitions --op R4 || return 1
  assert_stderr_contains "classification=deferred" || return 1
}

scenario_request_409_op_r4_deferred() {
  cd "$TMPDIR_TEST" || return 1
  _write_site_host_config "example.atlassian.net"
  _write_credential
  _bin=$(_make_curl_stub 'https://example.atlassian.net/rest/api/3/issue/CSTK-1/transitions|409|{}')
  assert_exit 1 env PATH="$_bin:$PATH" XDG_CONFIG_HOME="$TMPDIR_TEST/xdg" JIRA_IO_BACKOFF_SECONDS=0 \
    "$SCRIPT" request POST /rest/api/3/issue/CSTK-1/transitions --op R4 || return 1
  assert_stderr_contains "classification=deferred" || return 1
}

scenario_request_400_sem_op_r4_passthrough_sucesso() {
  cd "$TMPDIR_TEST" || return 1
  _write_site_host_config "example.atlassian.net"
  _write_credential
  _bin=$(_make_curl_stub 'https://example.atlassian.net/rest/api/3/issue|400|{"errorMessages":["campo obrigatorio ausente"]}')
  # Fora do escopo 3.4 (sem --op R4): comportamento pre-3.4 preservado —
  # passthrough como sucesso (exit 0, corpo relayed) — nao inventar
  # classificacao alem do que plan.md/contracts/jira-rest.md exigem.
  assert_exit 0 env PATH="$_bin:$PATH" XDG_CONFIG_HOME="$TMPDIR_TEST/xdg" JIRA_IO_BACKOFF_SECONDS=0 \
    "$SCRIPT" request POST /rest/api/3/issue || return 1
  assert_stdout_contains "campo obrigatorio ausente" || return 1
}

scenario_request_5xx_esgota_tentativas_deferred() {
  cd "$TMPDIR_TEST" || return 1
  _write_site_host_config "example.atlassian.net"
  _write_credential
  _bin=$(_make_flaky_curl_stub "500 502 503")
  assert_exit 1 env PATH="$_bin:$PATH" XDG_CONFIG_HOME="$TMPDIR_TEST/xdg" JIRA_IO_BACKOFF_SECONDS=0 \
    "$SCRIPT" request GET /rest/api/3/issue/CSTK-1 || return 1
  assert_stderr_contains "classification=deferred" || return 1
  [ "$(_curl_call_count)" = "3" ] \
    || { _fail "5xx tentativas" "esperado exatamente 3 tentativas, obtido $(_curl_call_count)"; return 1; }
}

scenario_request_5xx_recupera_na_segunda_tentativa() {
  cd "$TMPDIR_TEST" || return 1
  _write_site_host_config "example.atlassian.net"
  _write_credential
  _bin=$(_make_flaky_curl_stub "500 200" '{"key":"CSTK-1"}')
  assert_exit 0 env PATH="$_bin:$PATH" XDG_CONFIG_HOME="$TMPDIR_TEST/xdg" JIRA_IO_BACKOFF_SECONDS=0 \
    "$SCRIPT" request GET /rest/api/3/issue/CSTK-1 || return 1
  assert_stdout_contains '"key":"CSTK-1"' || return 1
  [ "$(_curl_call_count)" = "2" ] \
    || { _fail "5xx recupera tentativas" "esperado exatamente 2 tentativas, obtido $(_curl_call_count)"; return 1; }
}

scenario_request_erro_rede_esgota_tentativas_deferred() {
  cd "$TMPDIR_TEST" || return 1
  _write_site_host_config "example.atlassian.net"
  _write_credential
  _bin=$(_make_networkfail_curl_stub)
  assert_exit 1 env PATH="$_bin:$PATH" XDG_CONFIG_HOME="$TMPDIR_TEST/xdg" JIRA_IO_BACKOFF_SECONDS=0 \
    "$SCRIPT" request GET /rest/api/3/issue/CSTK-1 || return 1
  assert_stderr_contains "classification=deferred" || return 1
  [ "$(_curl_call_count)" = "3" ] \
    || { _fail "rede tentativas" "esperado exatamente 3 tentativas, obtido $(_curl_call_count)"; return 1; }
}

scenario_request_op_invalido_exit2() {
  cd "$TMPDIR_TEST" || return 1
  _write_site_host_config "example.atlassian.net"
  _bin=$(_make_curl_stub 'https://example.atlassian.net/rest/api/3/issue/CSTK-1|200|{}')
  assert_exit 2 env PATH="$_bin:$PATH" "$SCRIPT" request GET /rest/api/3/issue/CSTK-1 --op R99 || return 1
  [ "$(_curl_call_count)" = "0" ] \
    || { _fail "op invalido calls" "--op invalido nao deve disparar nenhuma requisicao"; return 1; }
}

# JI-47 (3.4.7): teste de contrato dedicado — 401 vs 403 R1/R2 vs 403 demais
# vs 429 SEM colisao no mesmo tratamento (CHK009). Cada sub-chamada usa seu
# proprio stub/diretorio (evita reuso de estado entre invocacoes na mesma
# funcao de cenario).
scenario_contrato_401_403_429_sem_colisao() {
  cd "$TMPDIR_TEST" || return 1
  _write_site_host_config "example.atlassian.net"
  _write_credential

  _bin401=$(_make_curl_stub 'https://example.atlassian.net/rest/api/3/issue/CSTK-1|401|{}')
  capture env PATH="$_bin401:$PATH" XDG_CONFIG_HOME="$TMPDIR_TEST/xdg" JIRA_IO_BACKOFF_SECONDS=0 \
    "$SCRIPT" request GET /rest/api/3/issue/CSTK-1
  [ "$_CAPTURED_EXIT" = "4" ] || { _fail "401 exit" "esperado 4, obtido $_CAPTURED_EXIT"; return 1; }
  case "$_CAPTURED_STDERR" in
    *classification=auth_failed*) : ;;
    *) _fail "401 classification" "esperado auth_failed: $_CAPTURED_STDERR"; return 1 ;;
  esac

  _bin403r1=$(_make_curl_stub 'https://example.atlassian.net/rest/api/3/issue|403|{}')
  capture env PATH="$_bin403r1:$PATH" XDG_CONFIG_HOME="$TMPDIR_TEST/xdg" JIRA_IO_BACKOFF_SECONDS=0 \
    "$SCRIPT" request POST /rest/api/3/issue --op R1
  [ "$_CAPTURED_EXIT" = "7" ] || { _fail "403 R1 exit" "esperado 7, obtido $_CAPTURED_EXIT"; return 1; }
  case "$_CAPTURED_STDERR" in
    *classification=permission_denied*) : ;;
    *) _fail "403 R1 classification" "esperado permission_denied: $_CAPTURED_STDERR"; return 1 ;;
  esac

  _bin403outros=$(_make_curl_stub 'https://example.atlassian.net/rest/api/3/issue/CSTK-1/transitions|403|{}')
  capture env PATH="$_bin403outros:$PATH" XDG_CONFIG_HOME="$TMPDIR_TEST/xdg" JIRA_IO_BACKOFF_SECONDS=0 \
    "$SCRIPT" request POST /rest/api/3/issue/CSTK-1/transitions --op R4
  [ "$_CAPTURED_EXIT" = "4" ] || { _fail "403 R4 exit" "esperado 4, obtido $_CAPTURED_EXIT"; return 1; }
  case "$_CAPTURED_STDERR" in
    *classification=auth_failed*) : ;;
    *) _fail "403 R4 classification" "esperado auth_failed: $_CAPTURED_STDERR"; return 1 ;;
  esac

  _bin429=$(_make_headers_curl_stub 429)
  capture env PATH="$_bin429:$PATH" XDG_CONFIG_HOME="$TMPDIR_TEST/xdg" JIRA_IO_BACKOFF_SECONDS=0 \
    "$SCRIPT" request GET /rest/api/3/issue/CSTK-1
  [ "$_CAPTURED_EXIT" = "1" ] || { _fail "429 exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  case "$_CAPTURED_STDERR" in
    *classification=deferred*) : ;;
    *) _fail "429 classification" "esperado deferred: $_CAPTURED_STDERR"; return 1 ;;
  esac

  # Os 4 exit codes observados (4, 7, 4, 1) e as 3 classificacoes distintas
  # (auth_failed, permission_denied, deferred) provam que nao ha colisao:
  # 401 e "403 demais" COMPARTILHAM auth_failed de proposito (mesmo
  # tratamento, plan.md), mas 403-R1/R2 e 429 sao SEMPRE distintos dos dois.
}

# JI-48..JI-62 (tarefa 3.5, SEC-3): `json-get`/`json-build` + JQL segura.
# Nenhum destes cenarios toca rede (json-get/json-build nunca chamam
# jira-config.sh nem o cliente HTTP) — so precisam de `jq` no PATH.
#   JI-48 json-get: filtro valido sobre JSON de stdin -> valor em stdout
#   JI-49 json-get: entrada em stdin NAO e JSON valido -> exit 2
#   JI-50 json-get: filtro jq invalido -> exit 2
#   JI-51 json-get: numero errado de argumentos -> exit 2 (uso incorreto)
#   JI-52 json-get: jq ausente do PATH -> exit 5
#   JI-53 json-build issue: contrato R1 completo (project/issuetype/summary/
#         parent/description ADF) bate campo a campo com
#         contracts/jira-rest.md (3.5.4)
#   JI-54 json-build issue: so os 3 campos obrigatorios (sem parent/description)
#   JI-55 json-build issue: falta --project-id -> exit 2
#   JI-56 json-build issue: falta --issuetype-id -> exit 2
#   JI-57 json-build issue: falta --summary -> exit 2
#   JI-58 json-build issue: --project-id fora da allowlist [A-Za-z0-9_-] -> exit 2
#   JI-59 json-build issue: --parent-key fora da allowlist -> exit 2
#   JI-60 json-build issue: --summary/--description com aspas, barra invertida
#         e quebra de linha -> JSON de saida ainda e valido (round-trip via
#         `jq -e .`) e preserva o conteudo literal (teste negativo obrigatorio)
#   JI-61 json-build filter: --name + --project-key validos -> corpo R9
#         {"name":..., "jql":"project = \"KEY\""}
#   JI-62 json-build filter: --project-key com texto livre/tentativa de
#         injecao JQL (espaco, aspas, operador OR) -> exit 2, RECUSADA antes
#         de montar qualquer JQL (SEC-3, teste negativo obrigatorio 3.5.5) —
#         --name (texto livre) tambem nunca e interpolado em jql
#   JI-63 json-build: MODE desconhecido -> exit 2
#   JI-64 json-build: subcomando sem MODE -> exit 2

# NOTA: `printf ... | assert_exit ...` NAO funciona neste harness — o lado
# direito de um pipe roda em subshell (POSIX puro, sem `lastpipe`), entao
# _CAPTURED_* setadas dentro de `capture`/`assert_exit` seriam perdidas ao
# sair do subshell. Usar heredoc (`<<EOF`), que e redirecionamento de
# argumento (mesmo shell), nunca pipe — mesmo padrao ja usado alhures no
# repo (ex.: tests/test_bloqueios.sh `capture jq -e '...' <<EOF`).
scenario_json_get_filtro_valido() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 0 "$SCRIPT" json-get '.fields.status.name' <<'EOF' || return 1
{"fields":{"status":{"name":"To Do"}}}
EOF
  assert_stdout_contains "To Do" || return 1
}

scenario_json_get_entrada_nao_json_exit2() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 2 "$SCRIPT" json-get '.' <<'EOF' || return 1
nao e json
EOF
}

scenario_json_get_filtro_invalido_exit2() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 2 "$SCRIPT" json-get '.[[[' <<'EOF' || return 1
{}
EOF
}

scenario_json_get_argumentos_errados_exit2() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 2 "$SCRIPT" json-get || return 1
}

scenario_json_get_jq_ausente_exit5() {
  cd "$TMPDIR_TEST" || return 1
  _bin="$TMPDIR_TEST/bin-none"
  mkdir -p "$_bin"
  assert_exit 5 env PATH="$_bin" "$SCRIPT" json-get '.' <<'EOF' || return 1
{}
EOF
  assert_stderr_contains "jq" || return 1
}

scenario_json_build_issue_contrato_r1_completo() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 0 "$SCRIPT" json-build issue \
    --project-id 10000 --issuetype-id 10004 --summary "Story de teste" \
    --parent-key SCRUM-5 --description "corpo da descricao" || return 1
  _got=$(printf '%s' "$_CAPTURED_STDOUT" | jq -S -c .)
  _want=$(jq -S -c -n \
    '{fields:{project:{id:"10000"},issuetype:{id:"10004"},summary:"Story de teste",parent:{key:"SCRUM-5"},description:{type:"doc",version:1,content:[{type:"paragraph",content:[{type:"text",text:"corpo da descricao"}]}]}}}')
  [ "$_got" = "$_want" ] \
    || { _fail "json_build_issue_r1" "corpo nao bate com contracts/jira-rest.md R1: obtido=$_got want=$_want"; return 1; }
}

scenario_json_build_issue_so_campos_obrigatorios() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 0 "$SCRIPT" json-build issue \
    --project-id 10000 --issuetype-id 10001 --summary "Epic minimo" || return 1
  _got=$(printf '%s' "$_CAPTURED_STDOUT" | jq -S -c .)
  _want=$(jq -S -c -n '{fields:{project:{id:"10000"},issuetype:{id:"10001"},summary:"Epic minimo"}}')
  [ "$_got" = "$_want" ] \
    || { _fail "json_build_issue_minimo" "corpo inesperado: $_got"; return 1; }
}

scenario_json_build_issue_falta_project_id_exit2() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 2 "$SCRIPT" json-build issue --issuetype-id 1 --summary x || return 1
}

scenario_json_build_issue_falta_issuetype_id_exit2() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 2 "$SCRIPT" json-build issue --project-id 1 --summary x || return 1
}

scenario_json_build_issue_falta_summary_exit2() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 2 "$SCRIPT" json-build issue --project-id 1 --issuetype-id 1 || return 1
}

scenario_json_build_issue_project_id_fora_allowlist_exit2() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 2 "$SCRIPT" json-build issue \
    --project-id "10000; DROP" --issuetype-id 1 --summary x || return 1
}

scenario_json_build_issue_parent_key_fora_allowlist_exit2() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 2 "$SCRIPT" json-build issue \
    --project-id 1 --issuetype-id 1 --summary x --parent-key "SCRUM 5" || return 1
}

# JI-60 (teste negativo obrigatorio): valor com aspas/barra/quebra de linha
# em --summary/--description continua produzindo JSON VALIDO (round-trip via
# `jq -e .`) e preserva o conteudo literal — prova de que a montagem usa
# `jq --arg` (escaping correto), nunca concatenacao de string.
scenario_json_build_issue_summary_com_aspas_barra_e_quebra_de_linha() {
  cd "$TMPDIR_TEST" || return 1
  _summary='titulo com "aspas", \barra\ e
quebra de linha'
  assert_exit 0 "$SCRIPT" json-build issue \
    --project-id 1 --issuetype-id 1 --summary "$_summary" \
    --description "$_summary" || return 1
  printf '%s' "$_CAPTURED_STDOUT" | jq -e . >/dev/null 2>&1 \
    || { _fail "json_build_issue_json_valido" "saida nao e JSON valido: $_CAPTURED_STDOUT"; return 1; }
  _roundtrip_summary=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.fields.summary')
  [ "$_roundtrip_summary" = "$_summary" ] \
    || { _fail "json_build_issue_summary_preservado" "esperado='$_summary' obtido='$_roundtrip_summary'"; return 1; }
  _roundtrip_desc=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.fields.description.content[0].content[0].text')
  [ "$_roundtrip_desc" = "$_summary" ] \
    || { _fail "json_build_issue_description_preservado" "esperado='$_summary' obtido='$_roundtrip_desc'"; return 1; }
}

scenario_json_build_filter_valido() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 0 "$SCRIPT" json-build filter \
    --name "Board do projeto SCRUM" --project-key SCRUM || return 1
  _got=$(printf '%s' "$_CAPTURED_STDOUT" | jq -S -c .)
  _want=$(jq -S -c -n '{name:"Board do projeto SCRUM", jql:"project = \"SCRUM\""}')
  [ "$_got" = "$_want" ] \
    || { _fail "json_build_filter_r9" "corpo nao bate com contracts/jira-rest.md R9: obtido=$_got want=$_want"; return 1; }
}

# JI-62 (teste negativo obrigatorio, SEC-3/3.5.5): tentativa de montar JQL
# com texto livre (aqui simulado via --project-key contendo espaco/aspas/
# operador JQL) e RECUSADA (exit 2) ANTES de qualquer interpolacao — nenhuma
# JQL e impressa em stdout.
scenario_json_build_filter_project_key_texto_livre_recusado_antes_de_montar_jql() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 2 "$SCRIPT" json-build filter \
    --name "x" --project-key 'SCRUM" OR 1=1 --' || return 1
  assert_stdout_not_contains "jql" || return 1
  assert_stdout_not_contains "OR 1=1" || return 1
}

scenario_json_build_mode_desconhecido_exit2() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 2 "$SCRIPT" json-build bogus --whatever x || return 1
}

scenario_json_build_sem_mode_exit2() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 2 "$SCRIPT" json-build || return 1
}

# --- json-build transition (FASE 4.2.5, dec-081) ---------------------------

scenario_json_build_transition_valido() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 0 "$SCRIPT" json-build transition --transition-id 31 || return 1
  _got=$(printf '%s' "$_CAPTURED_STDOUT" | jq -S -c .)
  _want=$(jq -S -c -n '{transition:{id:"31"}}')
  [ "$_got" = "$_want" ] \
    || { _fail "json_build_transition_r4" "corpo nao bate com contracts/jira-rest.md R4: obtido=$_got want=$_want"; return 1; }
}

scenario_json_build_transition_falta_id_exit2() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 2 "$SCRIPT" json-build transition || return 1
}

scenario_json_build_transition_id_fora_allowlist_exit2() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 2 "$SCRIPT" json-build transition --transition-id '31; DROP TABLE' || return 1
}

# --- json-build marker (FASE 4.2.5, dec-081/dec-082 — SyncMarker via R6) ---

scenario_json_build_marker_valido() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 0 "$SCRIPT" json-build marker --local-key "4.2.1" --feature "cstk-jira" \
    --written-summary-sha256 "abc123" --written-status "In Progress" \
    --written-at "2026-09-26T00:00:00Z" || return 1
  _got=$(printf '%s' "$_CAPTURED_STDOUT" | jq -S -c .)
  _want=$(jq -S -c -n '{schema:1, local_key:"4.2.1", feature:"cstk-jira", written_summary_sha256:"abc123", written_status:"In Progress", written_at:"2026-09-26T00:00:00Z"}')
  [ "$_got" = "$_want" ] \
    || { _fail "json_build_marker_r6" "corpo nao bate com data-model.md Entity SyncMarker: obtido=$_got want=$_want"; return 1; }
}

# JI-marker-2 (teste negativo, SEC-3): texto livre com aspas/barra invertida
# em local_key/written_status e escapado via jq --arg, nunca corrompe o JSON
# de saida (nem produz JSON invalido).
scenario_json_build_marker_campos_com_aspas_e_barra() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 0 "$SCRIPT" json-build marker --local-key '4."2"\1' --feature "cstk-jira" \
    --written-summary-sha256 "abc123" --written-status 'In "Review"' \
    --written-at "2026-09-26T00:00:00Z" || return 1
  printf '%s' "$_CAPTURED_STDOUT" | jq -e . >/dev/null \
    || { _fail "json_build_marker_quotes_valid_json" "saida nao e JSON valido: $_CAPTURED_STDOUT"; return 1; }
  _lkey=$(printf '%s' "$_CAPTURED_STDOUT" | "$SCRIPT" json-get '.local_key')
  [ "$_lkey" = '4."2"\1' ] || { _fail "json_build_marker_quotes_local_key" "local_key corrompido: $_lkey"; return 1; }
}

scenario_json_build_marker_falta_campo_exit2() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 2 "$SCRIPT" json-build marker --local-key "4.2.1" --feature "cstk-jira" \
    --written-summary-sha256 "abc123" --written-status "In Progress" || return 1
}

# --- sha256-stdin (FASE 4.2.3, dec-081/dec-082) -----------------------------

scenario_sha256_stdin_bate_com_sha256sum_do_sistema() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 0 "$SCRIPT" sha256-stdin <<'EOF'
Titulo de teste
EOF
  _got="$_CAPTURED_STDOUT"
  if command -v sha256sum >/dev/null 2>&1; then
    _want=$(printf '%s\n' "Titulo de teste" | sha256sum | awk '{print $1}')
  else
    _want=$(printf '%s\n' "Titulo de teste" | shasum -a 256 | awk '{print $1}')
  fi
  [ "$_got" = "$_want" ] \
    || { _fail "sha256_stdin_matches_system" "esperado $_want, obtido $_got"; return 1; }
}

scenario_sha256_stdin_deterministico_mesma_entrada() {
  cd "$TMPDIR_TEST" || return 1
  _h1=$(printf '%s' "mesmo titulo" | "$SCRIPT" sha256-stdin)
  _h2=$(printf '%s' "mesmo titulo" | "$SCRIPT" sha256-stdin)
  [ "$_h1" = "$_h2" ] || { _fail "sha256_stdin_deterministic" "hashes diferentes para a mesma entrada"; return 1; }
  _h3=$(printf '%s' "titulo diferente" | "$SCRIPT" sha256-stdin)
  [ "$_h1" != "$_h3" ] || { _fail "sha256_stdin_differs" "hashes iguais para entradas diferentes"; return 1; }
}

run_all_scenarios
