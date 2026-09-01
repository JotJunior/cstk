#!/bin/sh
# test_http.sh — cobre cli/lib/http.sh
#
# Contrato:
#   http_download <url> <dest>    exit 0 sucesso, 1 erro (timeout/404/offline),
#                                 2 args faltando
#   http_check_url <url>          exit 0 acessivel, 1 nao
#
# Estrategia de teste: usa file:// URLs (suportado por curl em qualquer build
# minimamente normal), que funciona 100% offline. Evita dependencia em rede
# e em servidores externos.
#
# Cadeia de redirects (issue #178): coberta com STUB de curl no PATH, que
# devolve `%{http_code} %{redirect_url}` conforme um mapa declarado pelo
# cenario e REGISTRA cada URL requisitada num log. O log e o que prova a
# propriedade central: a URL fora da allowlist nunca chega a ser requisitada
# (nao ha "baixa e descarta depois").

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CSTK_LIB="$REPO_ROOT/cli/lib"
export CSTK_LIB

# Verifica se curl suporta file:// antes de rodar cenarios que dependem disso.
# Se nao suportar, marca como ERROR (nao FAIL — ambiente inadequado).
_curl_supports_file() {
  _tmpf=$(mktemp) || return 2
  printf 'marker\n' > "$_tmpf"
  if curl -fsSL "file://$_tmpf" >/dev/null 2>&1; then
    rm -f "$_tmpf"
    return 0
  fi
  rm -f "$_tmpf"
  return 1
}

scenario_download_sucesso_via_file_url() {
  if ! _curl_supports_file; then
    _error "scenario_download_sucesso_via_file_url" "curl nao suporta file://"
    return 2
  fi
  _src="$TMPDIR_TEST/source.txt"
  _dest="$TMPDIR_TEST/dest.txt"
  printf 'payload-contents\n' > "$_src"
  capture sh -c ". $CSTK_LIB/http.sh && http_download file://$_src $_dest"
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "http_download file:// exit" "$_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
  if [ ! -f "$_dest" ]; then
    _fail "http_download arquivo destino ausente" "$_dest"
    return 1
  fi
  if ! grep -q 'payload-contents' "$_dest"; then
    _fail "http_download conteudo" "arquivo destino nao tem payload esperado"
    return 1
  fi
}

scenario_download_url_inexistente_exit1() {
  _dest="$TMPDIR_TEST/nope.txt"
  capture sh -c ". $CSTK_LIB/http.sh && http_download file:///nao/existe/jamais.bin $_dest"
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "http_download 404 exit" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  # Arquivo parcial nao deve persistir
  if [ -f "$_dest" ]; then
    _fail "http_download deixou arquivo parcial" "$_dest"
    return 1
  fi
}

scenario_download_args_faltando_exit2() {
  capture sh -c ". $CSTK_LIB/http.sh && http_download"
  if [ "$_CAPTURED_EXIT" != "2" ]; then
    _fail "http_download sem args" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_check_url_sucesso() {
  if ! _curl_supports_file; then
    _error "scenario_check_url_sucesso" "curl nao suporta file://"
    return 2
  fi
  _src="$TMPDIR_TEST/check.txt"
  printf 'x\n' > "$_src"
  capture sh -c ". $CSTK_LIB/http.sh && http_check_url file://$_src"
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "http_check_url existe" "exit esperado 0, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_check_url_inexistente() {
  capture sh -c ". $CSTK_LIB/http.sh && http_check_url file:///nao/existe/x"
  if [ "$_CAPTURED_EXIT" = "0" ]; then
    _fail "http_check_url inexistente" "exit esperado !=0, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

# ==== Cadeia de redirects revalidada salto a salto (issue #178) ====

# _make_curl_stub <mapa> — instala um stub de curl em $TMPDIR_TEST/bin.
# O mapa e uma sequencia de linhas "<url-glob>|<http_code>|<redirect_url>".
# Toda invocacao registra a URL pedida em $TMPDIR_TEST/curl-calls.log.
_make_curl_stub() {
  _stub_dir="$TMPDIR_TEST/bin"
  mkdir -p "$_stub_dir"
  printf '%s\n' "$1" > "$TMPDIR_TEST/curl-map"
  : > "$TMPDIR_TEST/curl-calls.log"
  cat > "$_stub_dir/curl" <<STUB
#!/bin/sh
# Stub curl: nao toca a rede; responde a partir de $TMPDIR_TEST/curl-map.
_url=""
_out=""
_prev=""
for _a in "\$@"; do
  case "\$_prev" in
    -o) _out="\$_a" ;;
  esac
  case "\$_a" in
    https://*|file://*|http://*) _url="\$_a" ;;
  esac
  _prev="\$_a"
done
printf '%s\n' "\$_url" >> "$TMPDIR_TEST/curl-calls.log"
while IFS='|' read -r _pat _code _next; do
  [ -n "\$_pat" ] || continue
  case "\$_url" in
    \$_pat)
      [ -n "\$_out" ] && printf 'corpo-de-%s\n' "\$_code" > "\$_out"
      printf '%s %s' "\$_code" "\$_next"
      exit 0
      ;;
  esac
done < "$TMPDIR_TEST/curl-map"
exit 22
STUB
  chmod +x "$_stub_dir/curl"
  printf '%s' "$_stub_dir"
}

# Conta quantas vezes uma URL casando o glob foi requisitada pelo stub.
_curl_calls_matching() {
  _cnt=0
  while IFS= read -r _line; do
    # shellcheck disable=SC2254  # $1 e um GLOB deliberado aqui (o chamador
    # passa 'https://evil.example.com/*'), nao um literal a ser citado.
    case "$_line" in
      $1) _cnt=$((_cnt + 1)) ;;
    esac
  done < "$TMPDIR_TEST/curl-calls.log"
  printf '%s' "$_cnt"
}

scenario_download_redirect_dentro_da_allowlist_segue() {
  # github.com -> github.com -> release-assets.githubusercontent.com (a
  # cadeia real medida de um asset de release; ver cli/lib/trusted-hosts.sh).
  _bin=$(_make_curl_stub 'https://github.com/JotJunior/cstk/releases/*|302|https://github.com/hop2
https://github.com/hop2|302|https://release-assets.githubusercontent.com/blob
https://release-assets.githubusercontent.com/*|200|')
  _dest="$TMPDIR_TEST/asset.bin"
  capture env PATH="$_bin:$PATH" sh -c ". $CSTK_LIB/http.sh && http_download https://github.com/JotJunior/cstk/releases/x.tar.gz $_dest"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "redirect allowlist exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  grep -q 'corpo-de-200' "$_dest" || { _fail "redirect allowlist corpo" "destino nao tem o corpo do salto final"; return 1; }
}

scenario_download_redirect_fora_da_allowlist_recusado() {
  # O salto final sai da allowlist: DEVE ser recusado ANTES da requisicao.
  _bin=$(_make_curl_stub 'https://github.com/JotJunior/cstk/releases/*|302|https://evil.example.com/payload.tar.gz
https://evil.example.com/*|200|')
  _dest="$TMPDIR_TEST/evil.bin"
  capture env PATH="$_bin:$PATH" sh -c ". $CSTK_LIB/http.sh && http_download https://github.com/JotJunior/cstk/releases/x.tar.gz $_dest"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "redirect fora allowlist exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "evil.example.com" || return 1
  [ ! -f "$_dest" ] || { _fail "redirect fora allowlist destino" "arquivo do salto recusado persistiu"; return 1; }
  # Propriedade central: nenhuma requisicao chegou ao host recusado.
  [ "$(_curl_calls_matching 'https://evil.example.com/*')" = 0 ] \
    || { _fail "redirect fora allowlist requisicao" "o stub foi chamado para o host fora da allowlist"; return 1; }
}

scenario_download_redirect_para_file_recusado() {
  # file:// e isento apenas como origem INICIAL (fluxo de dev); como destino
  # de redirect viraria leitura de arquivo local disfarcada de download.
  _src="$TMPDIR_TEST/segredo.txt"
  printf 'segredo\n' > "$_src"
  _bin=$(_make_curl_stub "https://github.com/*|302|file://$_src
file://*|200|")
  _dest="$TMPDIR_TEST/via-file.bin"
  capture env PATH="$_bin:$PATH" sh -c ". $CSTK_LIB/http.sh && http_download https://github.com/x.tar.gz $_dest"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "redirect file:// exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "file://" || return 1
}

scenario_download_teto_de_redirects() {
  # Loop de redirects DENTRO da allowlist: o teto interrompe a caminhada.
  _bin=$(_make_curl_stub 'https://github.com/*|302|https://github.com/loop')
  _dest="$TMPDIR_TEST/loop.bin"
  capture env PATH="$_bin:$PATH" sh -c ". $CSTK_LIB/http.sh && http_download https://github.com/start $_dest"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "teto redirects exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "redirects" || return 1
}

scenario_download_3xx_sem_location_e_erro() {
  # Nunca tratar o corpo de um 3xx sem Location como se fosse o payload.
  _bin=$(_make_curl_stub 'https://github.com/*|302|')
  _dest="$TMPDIR_TEST/sem-location.bin"
  capture env PATH="$_bin:$PATH" sh -c ". $CSTK_LIB/http.sh && http_download https://github.com/x.tar.gz $_dest"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "3xx sem location exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  [ ! -f "$_dest" ] || { _fail "3xx sem location destino" "corpo do redirect persistiu como payload"; return 1; }
}

scenario_download_host_inicial_fora_da_allowlist_nao_requisita() {
  _bin=$(_make_curl_stub 'https://evil.example.com/*|200|')
  _dest="$TMPDIR_TEST/inicial.bin"
  capture env PATH="$_bin:$PATH" sh -c ". $CSTK_LIB/http.sh && http_download https://evil.example.com/x.tar.gz $_dest"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "host inicial fora allowlist exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  [ "$(_curl_calls_matching 'https://evil.example.com/*')" = 0 ] \
    || { _fail "host inicial fora allowlist requisicao" "houve requisicao ao host recusado"; return 1; }
}

run_all_scenarios
