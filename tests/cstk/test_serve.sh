#!/bin/sh
# test_serve.sh — cobre cli/lib/serve.sh
#
# Contrato:
#   serve_main [--port P] [--host H] [--reinstall] [--help]
#     exit 0  sucesso (painel rodando ou --help)
#     exit 1  erro geral (prereq ausente, download falhou, corrompido)
#     exit 2  uso incorreto (porta invalida, flag desconhecida)
#
# Estrategia de teste: stubs de PATH para curl/npm (sem rede real).
#   CSTK_PANEL_DIR aponta para tmpdir isolado por scenario.
#   Fixture de tarball em tests/cstk/fixtures/serve/panel-fixture.tar.gz.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CSTK_LIB="$REPO_ROOT/cli/lib"
export CSTK_LIB

SERVE_FIXTURE_DIR="$TESTS_ROOT/cstk/fixtures/serve"

# ---------------------------------------------------------------------------
# Helpers compartilhados
# ---------------------------------------------------------------------------

# _setup_serve_env: cria CSTK_PANEL_DIR em tmpdir e exporta CSTK_LIB.
# Deve ser chamado dentro do scenario (TMPDIR_TEST ja existe via harness).
_setup_serve_env() {
  CSTK_PANEL_DIR="$TMPDIR_TEST/panel"
  export CSTK_PANEL_DIR
  export CSTK_LIB
}

# _make_bin_dir: cria diretorio de stubs no tmpdir, prepende ao PATH e
# define _STUB_BIN para uso pelo caller.
# NAO usa subshell — modifica PATH e _STUB_BIN diretamente no caller.
_make_bin_dir() {
  _STUB_BIN="$TMPDIR_TEST/stubs"
  mkdir -p "$_STUB_BIN"
  PATH="$_STUB_BIN:$PATH"
  export PATH
}

# _serve_fixture_sha256 FILE -> imprime o sha256 real do FILE (sha256sum no
# Linux, shasum -a 256 no macOS — mesmo fallback de compat.sh::sha256_file e
# de todos os demais tests/cstk/test_*.sh que geram fixtures .sha256).
# Computado a partir do arquivo de fato em disco (Constitution VI) — nunca
# hardcoded, para acompanhar o fixture se ele um dia mudar.
_serve_fixture_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# _stub_curl_ok: cria stub de curl que retorna JSON da GitHub API simulada
# com tarball_url apontando para https://github.com (para passar a allowlist),
# e ao receber a URL do tarball, copia o fixture local. O asset `.sha256`
# CONFERE com o fixture (outcome verified) — este stub e o caminho FELIZ,
# usado pela maioria dos scenarios que nao testam integridade especificamente
# (US2/enforced-guards: fail-closed exige que o default nao-relacionado a
# integridade continue instalando sem exigir --allow-unverified).
# $1 = diretorio de stubs
_stub_curl_ok() {
  _sco_bin="$1"
  _sco_tarball="$SERVE_FIXTURE_DIR/panel-fixture.tar.gz"
  _sco_sha256=$(_serve_fixture_sha256 "$_sco_tarball")
  # A tarball_url usa https://github.com para passar a SSRF allowlist.
  # O stub intercepta o download e copia o fixture local.
  cat > "$_sco_bin/curl" <<STUB
#!/bin/sh
# Stub curl: intercepta chamadas de rede sem tocar a rede real.
_url=""
_output=""
while [ "\$#" -gt 0 ]; do
  case "\$1" in
    -o) shift; _output="\$1" ;;
    --) shift; _url="\$1" ;;
    https://*|http://*) _url="\$1" ;;
    *) ;;
  esac
  shift
done
case "\$_url" in
  *releases/latest*)
    # GitHub API response: tarball_url usa github.com para passar a allowlist
    _resp='{"tag_name":"v0.0.1","tarball_url":"https://github.com/JotJunior/cstk-panel/archive/v0.0.1.tar.gz","prerelease":false,"draft":false}'
    if [ -n "\$_output" ]; then
      printf '%s\n' "\$_resp" > "\$_output"
    else
      printf '%s\n' "\$_resp"
    fi
    ;;
  *github.com*.sha256*)
    # .sha256 disponivel e CONFERE com o fixture -> outcome "verified".
    if [ -n "\$_output" ]; then
      printf '%s  archive.tar.gz\n' "${_sco_sha256}" > "\$_output"
    else
      printf '%s  archive.tar.gz\n' "${_sco_sha256}"
    fi
    ;;
  *github.com*tar.gz*)
    # Tarball download: copiar fixture local em vez de baixar da rede
    if [ -n "\$_output" ]; then
      cp "${_sco_tarball}" "\$_output"
    else
      cat "${_sco_tarball}"
    fi
    ;;
  *)
    printf 'stub-curl: URL inesperada: %s\n' "\$_url" >&2
    exit 1
    ;;
esac
STUB
  chmod +x "$_sco_bin/curl"
}

# _stub_curl_no_sha256: como _stub_curl_ok, mas o asset `.sha256` do release
# NAO esta disponivel (404) — reproduz o estado real documentado do
# cstk-panel hoje (Dependencies & Assumptions da spec: nao publica .sha256 de
# forma confiavel). Outcome esperado: unverifiable-blocked (default) ou
# unverifiable-bypassed (--allow-unverified/CSTK_SERVE_ALLOW_UNVERIFIED=1).
# $1 = diretorio de stubs
_stub_curl_no_sha256() {
  _scns_bin="$1"
  _scns_tarball="$SERVE_FIXTURE_DIR/panel-fixture.tar.gz"
  cat > "$_scns_bin/curl" <<STUB
#!/bin/sh
_url=""
_output=""
while [ "\$#" -gt 0 ]; do
  case "\$1" in
    -o) shift; _output="\$1" ;;
    --) shift; _url="\$1" ;;
    https://*|http://*) _url="\$1" ;;
    *) ;;
  esac
  shift
done
case "\$_url" in
  *releases/latest*)
    _resp='{"tag_name":"v0.0.1","tarball_url":"https://github.com/JotJunior/cstk-panel/archive/v0.0.1.tar.gz","prerelease":false,"draft":false}'
    if [ -n "\$_output" ]; then
      printf '%s\n' "\$_resp" > "\$_output"
    else
      printf '%s\n' "\$_resp"
    fi
    ;;
  *github.com*.sha256*)
    # Simula ausencia do asset .sha256 no release.
    exit 1
    ;;
  *github.com*tar.gz*)
    if [ -n "\$_output" ]; then
      cp "${_scns_tarball}" "\$_output"
    else
      cat "${_scns_tarball}"
    fi
    ;;
  *)
    printf 'stub-curl: URL inesperada: %s\n' "\$_url" >&2
    exit 1
    ;;
esac
STUB
  chmod +x "$_scns_bin/curl"
}

# _stub_curl_bad_sha256: como _stub_curl_ok, mas o asset `.sha256` ESTA
# disponivel porem NAO confere com o tarball real (adulterado/corrompido em
# transito) — exercita a regressao mismatch-blocked (FR-010, task 3.4), que
# MUST permanecer bloqueando mesmo com --allow-unverified (bypass NUNCA se
# aplica a mismatch, so a "nao-verificavel").
# $1 = diretorio de stubs
_stub_curl_bad_sha256() {
  _scbs_bin="$1"
  _scbs_tarball="$SERVE_FIXTURE_DIR/panel-fixture.tar.gz"
  # 64 zeros hex: garantidamente diferente do sha256 real de qualquer
  # arquivo nao-vazio (fixture tem varios KB — CHK-R23 exige >= 1024 bytes).
  _scbs_wrong_sha=$(printf '0%.0s' $(seq 1 64))
  cat > "$_scbs_bin/curl" <<STUB
#!/bin/sh
_url=""
_output=""
while [ "\$#" -gt 0 ]; do
  case "\$1" in
    -o) shift; _output="\$1" ;;
    --) shift; _url="\$1" ;;
    https://*|http://*) _url="\$1" ;;
    *) ;;
  esac
  shift
done
case "\$_url" in
  *releases/latest*)
    _resp='{"tag_name":"v0.0.1","tarball_url":"https://github.com/JotJunior/cstk-panel/archive/v0.0.1.tar.gz","prerelease":false,"draft":false}'
    if [ -n "\$_output" ]; then
      printf '%s\n' "\$_resp" > "\$_output"
    else
      printf '%s\n' "\$_resp"
    fi
    ;;
  *github.com*.sha256*)
    if [ -n "\$_output" ]; then
      printf '%s  archive.tar.gz\n' "${_scbs_wrong_sha}" > "\$_output"
    else
      printf '%s  archive.tar.gz\n' "${_scbs_wrong_sha}"
    fi
    ;;
  *github.com*tar.gz*)
    if [ -n "\$_output" ]; then
      cp "${_scbs_tarball}" "\$_output"
    else
      cat "${_scbs_tarball}"
    fi
    ;;
  *)
    printf 'stub-curl: URL inesperada: %s\n' "\$_url" >&2
    exit 1
    ;;
esac
STUB
  chmod +x "$_scbs_bin/curl"
}

# _stub_curl_must_not_be_called: stub que falha com mensagem se curl for chamado.
# Usado para garantir que invocacoes subsequentes nao fazem chamada de rede.
_stub_curl_must_not_be_called() {
  _scno_bin="$1"
  cat > "$_scno_bin/curl" <<'STUB'
#!/bin/sh
# Coletar URL para mensagem de erro
_url=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    https://*|http://*) _url="$1" ;;
    --) shift; _url="$1" ;;
  esac
  shift
done
printf 'ERRO: curl foi chamado mas nao deveria (panel ja instalado): %s\n' "$_url" >&2
exit 1
STUB
  chmod +x "$_scno_bin/curl"
}

# _stub_curl_unreachable: curl que falha em qualquer chamada (rede indisponivel).
# Usado para exercitar o caminho best-effort de --update quando a API do GitHub
# nao responde — a versao instalada deve ser mantida e o painel ainda iniciar.
# $1 = dir de stubs
_stub_curl_unreachable() {
  _scu_bin="$1"
  cat > "$_scu_bin/curl" <<'STUB'
#!/bin/sh
printf 'curl: (7) Failed to connect\n' >&2
exit 7
STUB
  chmod +x "$_scu_bin/curl"
}

# _stub_npm_ok: npm que ignora install/run start e sai com 0
_stub_npm_ok() {
  _sno_bin="$1"
  cat > "$_sno_bin/npm" <<'STUB'
#!/bin/sh
# Stub npm: aceita install e run start silenciosamente
exit 0
STUB
  chmod +x "$_sno_bin/npm"
}

# _stub_npm_exit_code: npm que sai com o exit code especificado para `run
# <script>` (ex.: `run dev`), aceitando `install` com 0 — simula saida
# espontanea do painel.
# $1 = bin dir, $2 = exit code para `run`
_stub_npm_exit_code() {
  _snec_bin="$1"
  _snec_exit="$2"
  cat > "$_snec_bin/npm" <<STUB
#!/bin/sh
# install e \`run build\` saem 0 (o serve builda antes do dev); apenas
# \`run dev\`/\`run start\` falha com o exit code configurado — simula saida
# espontanea do painel sem que o build do launch intercepte o caminho.
case "\$1 \$2" in
  "run build") exit 0 ;;
  "run dev"|"run start") exit ${_snec_exit} ;;
  *) exit 0 ;;
esac
STUB
  chmod +x "$_snec_bin/npm"
}

# _stub_npm_build_fails: npm que aceita install e falha em `run build` (exit 2,
# mensagem em stderr) — cobre o caminho de erro do build no launch (serve deve
# sair 1 sem chegar ao `run start`).
# $1 = dir de stubs
_stub_npm_build_fails() {
  _snbf_bin="$1"
  cat > "$_snbf_bin/npm" <<'STUB'
#!/bin/sh
if [ "$1" = "run" ] && [ "$2" = "build" ]; then
  printf 'tsc: erro de compilacao simulado\n' >&2
  exit 2
fi
exit 0
STUB
  chmod +x "$_snbf_bin/npm"
}

# _stub_npm_logging: npm que LOGA cada chamada (args + PORT herdado do env) em
# $TMPDIR_TEST/npm-calls.log e sai 0. Permite assertar QUE comando foi invocado
# (ex.: `run dev`) e SE o caller exportou PORT. O caminho do log e baked
# (expansao no shell de teste) para sobreviver ao env isolado de _run_serve.
# $1 = dir de stubs
_stub_npm_logging() {
  _snl_bin="$1"
  cat > "$_snl_bin/npm" <<STUB
#!/bin/sh
printf 'cmd=[%s] PORT=[%s]\n' "\$*" "\${PORT:-}" >> "$TMPDIR_TEST/npm-calls.log"
exit 0
STUB
  chmod +x "$_snl_bin/npm"
}

# _run_serve: executa serve_main em subshell com env isolado
# Precisa de _setup_serve_env chamado antes.
# O PATH que serve_main enxerga vem de _SERVE_INNER_PATH quando definido
# (cenarios de prereq ausente), senao do PATH do shell de teste. Desacoplar
# o PATH interno do PATH do harness evita ter de clobberar o PATH global so
# para "esconder" curl/npm — clobber que nunca funcionou para curl, pois ele
# mora em /usr/bin tanto no Linux quanto no macOS.
#
# cd para $TMPDIR_TEST/cwd ANTES de sourcear serve.sh (US2/task 3.3): a
# partir de enforced-guards, serve.sh grava <cwd>/.claude/enforcement-log.jsonl
# via `pwd` no momento da chamada. Sem este isolamento, o processo herdaria o
# cwd do PROPRIO test runner (tipicamente a raiz do repo) e poluiria o
# .claude/ real do cstk com artefatos de teste — precisamente o tipo de
# vazamento que assert_no_side_effect existe para pegar. $TMPDIR_TEST/cwd e
# limpo automaticamente pelo trap de mktemp_test (harness.sh).
_run_serve() {
  _rs_cwd="$TMPDIR_TEST/cwd"
  mkdir -p "$_rs_cwd"
  capture env \
    CSTK_LIB="$CSTK_LIB" \
    CSTK_PANEL_DIR="$CSTK_PANEL_DIR" \
    PATH="${_SERVE_INNER_PATH:-$PATH}" \
    HOME="$TMPDIR_TEST" \
    sh -c "cd \"$_rs_cwd\" && . \$CSTK_LIB/serve.sh && serve_main \"\$@\"" serve_test "$@"
}

# _serve_enforcement_log: imprime conteudo de $TMPDIR_TEST/cwd/.claude/
# enforcement-log.jsonl (vazio se ausente). Espelha
# tests/test_pretooluse-bash-guard.sh::_enforcement_log para o mesmo arquivo
# (US1 e US2 escrevem no mesmo enforcement-log.jsonl — contract
# enforcement-log.md). So valido apos pelo menos uma chamada a _run_serve
# (que cria $TMPDIR_TEST/cwd).
_serve_enforcement_log() {
  cat "$TMPDIR_TEST/cwd/.claude/enforcement-log.jsonl" 2>/dev/null || :
}

# _snapshot_repo_root_log / _assert_no_repo_root_leak: rede de seguranca
# contra _run_serve escrever enforcement-log.jsonl na raiz do REPO real
# (fora do cwd isolado $TMPDIR_TEST/cwd) — o que poluiria o .claude/ real do
# operador. NAO assume que o arquivo esta ausente no REPO_ROOT (uma sessao
# real do Claude Code com o hook PreToolUse de US1 ativo PODE legitimamente
# ja ter esse arquivo por motivos nao relacionados a este teste) — compara
# conteudo ANTES/DEPOIS, so falha se _run_serve tiver MUDADO o arquivo real.
_snapshot_repo_root_log() {
  cat "$REPO_ROOT/.claude/enforcement-log.jsonl" 2>/dev/null > "$TMPDIR_TEST/.repo_log_baseline" || \
    : > "$TMPDIR_TEST/.repo_log_baseline"
}

_assert_no_repo_root_leak() {
  _anrl_current=$(cat "$REPO_ROOT/.claude/enforcement-log.jsonl" 2>/dev/null || :)
  _anrl_baseline=$(cat "$TMPDIR_TEST/.repo_log_baseline" 2>/dev/null || :)
  if [ "$_anrl_current" != "$_anrl_baseline" ]; then
    _fail "leak_repo_root" "enforcement-log.jsonl em $REPO_ROOT/.claude/ mudou durante o teste (vazamento de _run_serve para fora do cwd isolado \$TMPDIR_TEST/cwd)"
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# FASE 1 — Infra: verificar coverage (task 1.1.7)
# ---------------------------------------------------------------------------

# (Este arquivo existe = --check-coverage passa. Scenarios abaixo validam logica.)

# ---------------------------------------------------------------------------
# FASE 2.1 — Parse de flags e validacao de porta (tasks 2.1.x)
# ---------------------------------------------------------------------------

scenario_help_exit0() {
  _setup_serve_env
  _run_serve --help
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "serve --help exit" "esperado 0, obtido $_CAPTURED_EXIT"
    return 1
  fi
  # Deve mencionar --port no stdout
  if ! printf '%s' "$_CAPTURED_STDOUT" | grep -q -- '--port'; then
    _fail "serve --help conteudo" "stdout nao menciona --port"
    return 1
  fi
}

scenario_help_menciona_flags() {
  _setup_serve_env
  _run_serve --help
  for _flag in '--port' '--host' '--reinstall' '--docker'; do
    if ! printf '%s' "$_CAPTURED_STDOUT" | grep -q -- "$_flag"; then
      _fail "serve --help flag ausente" "nao encontrou $_flag no stdout"
      return 1
    fi
  done
}

scenario_porta_invalida_letras_exit2() {
  _setup_serve_env
  _run_serve --port abc
  if [ "$_CAPTURED_EXIT" != "2" ]; then
    _fail "porta_invalida_letras" "esperado exit 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_porta_zero_exit2() {
  _setup_serve_env
  _run_serve --port 0
  if [ "$_CAPTURED_EXIT" != "2" ]; then
    _fail "porta_zero" "esperado exit 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_porta_65536_exit2() {
  _setup_serve_env
  _run_serve --port 65536
  if [ "$_CAPTURED_EXIT" != "2" ]; then
    _fail "porta_65536" "esperado exit 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_porta_65535_aceita() {
  _setup_serve_env
  _make_bin_dir
  _stub_curl_ok "$_STUB_BIN"
  _stub_npm_ok "$_STUB_BIN"
  _run_serve --port 65535
  # Deve sair com 0 (npm stub retorna 0)
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "porta_65535_aceita" "esperado exit 0, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_porta_5173_aceita() {
  _setup_serve_env
  _make_bin_dir
  _stub_curl_ok "$_STUB_BIN"
  _stub_npm_ok "$_STUB_BIN"
  _run_serve --port 5173
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "porta_5173_aceita" "esperado exit 0, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_flag_desconhecida_exit2() {
  _setup_serve_env
  _run_serve --nao-existe
  if [ "$_CAPTURED_EXIT" != "2" ]; then
    _fail "flag_desconhecida" "esperado exit 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_host_nao_loopback_aviso_stdout() {
  _setup_serve_env
  _make_bin_dir
  _stub_curl_ok "$_STUB_BIN"
  _stub_npm_ok "$_STUB_BIN"
  _run_serve --host 0.0.0.0
  # Deve prosseguir (exit 0) e emitir aviso no stdout
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "host_nao_loopback_prossegue" "esperado exit 0, obtido $_CAPTURED_EXIT"
    return 1
  fi
  if ! printf '%s' "$_CAPTURED_STDOUT" | grep -qi 'aviso\|warn\|atencao\|0\.0\.0\.0'; then
    _fail "host_nao_loopback_aviso" "stdout nao contem aviso sobre host nao-loopback"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# FASE 2.2 — Pre-requisitos (tasks 2.2.x)
# ---------------------------------------------------------------------------

# _isolated_sh_dir: cria (idempotente, por scenario) um dir contendo APENAS um
# symlink para o `sh` real e ecoa seu caminho. Serve para compor o PATH interno
# de serve_main (env precisa achar `sh` para lancar o inner shell) SEM arrastar
# /usr/bin nem /bin — onde mora curl (no Ubuntu com usrmerge /bin -> /usr/bin,
# logo /bin/curl tambem existe). Resolvido enquanto o PATH global ainda e completo.
_isolated_sh_dir() {
  _ish_dir="$TMPDIR_TEST/shbin"
  if [ ! -e "$_ish_dir/sh" ]; then
    mkdir -p "$_ish_dir"
    _ish_sh=$(command -v sh)
    ln -sf "$_ish_sh" "$_ish_dir/sh"
  fi
  printf '%s' "$_ish_dir"
}

# _stub_curl_present_npm_absent: curl-stub presente, npm ausente,
# para testar prereq-check de npm sem usar npm real do sistema.
_stub_curl_present_npm_absent() {
  _stub_curl_ok "$_STUB_BIN"
  # npm ausente de forma OS-independente: o PATH que serve_main enxerga
  # (_SERVE_INNER_PATH) contem APENAS o stub-bin (curl presente) + o shbin
  # isolado (so `sh`, para o env lancar o inner shell). npm fica fora.
  # Nao clobberamos o PATH global do harness (capture/grep usam o completo).
  _SERVE_INNER_PATH="$_STUB_BIN:$(_isolated_sh_dir)"
}

_stub_npm_present_curl_absent() {
  _stub_npm_ok "$_STUB_BIN"
  # curl ausente de forma OS-independente: o PATH interno tem o stub-bin
  # (npm presente) + o shbin isolado (so `sh`); curl fica fora. O bug anterior
  # usava "PATH=stub:/usr/bin:/bin" achando que removia curl, mas curl mora em
  # /usr/bin (e /bin->/usr/bin no Ubuntu), entao o prereq check sempre o
  # encontrava e o teste falhava em CI.
  _SERVE_INNER_PATH="$_STUB_BIN:$(_isolated_sh_dir)"
}

scenario_prereq_curl_ausente_exit1() {
  _setup_serve_env
  _make_bin_dir
  # npm presente (stub), curl ausente — PATH minimo sem curl real
  _stub_npm_present_curl_absent
  _run_serve
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "prereq_curl_ausente" "esperado exit 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  if ! printf '%s' "$_CAPTURED_STDERR" | grep -qi 'curl'; then
    _fail "prereq_curl_mensagem" "stderr nao menciona curl"
    return 1
  fi
}

scenario_prereq_npm_ausente_exit1() {
  _setup_serve_env
  _make_bin_dir
  # curl presente (stub), npm ausente — PATH minimo sem npm real
  _stub_curl_present_npm_absent
  _run_serve
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "prereq_npm_ausente" "esperado exit 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  if ! printf '%s' "$_CAPTURED_STDERR" | grep -qi 'npm'; then
    _fail "prereq_npm_mensagem" "stderr nao menciona npm"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# FASE 3.3 — Porta privilegiada < 1024 (tasks 3.3.x)
# ---------------------------------------------------------------------------

scenario_porta_80_exit1_privilegio() {
  _setup_serve_env
  _run_serve --port 80
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "porta_80_privilegio" "esperado exit 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  if ! printf '%s' "$_CAPTURED_STDERR" | grep -qi 'privileg\|root\|1024'; then
    _fail "porta_80_mensagem" "stderr nao menciona privilegio/1024"
    return 1
  fi
}

scenario_porta_1_exit1_privilegio() {
  _setup_serve_env
  _run_serve --port 1
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "porta_1_privilegio" "esperado exit 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_porta_1023_exit1_privilegio() {
  _setup_serve_env
  _run_serve --port 1023
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "porta_1023_privilegio" "esperado exit 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_porta_1024_aceita() {
  _setup_serve_env
  _make_bin_dir
  _stub_curl_ok "$_STUB_BIN"
  _stub_npm_ok "$_STUB_BIN"
  _run_serve --port 1024
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "porta_1024_aceita" "esperado exit 0, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# FASE 3.1 — SSRF host-allowlist (tasks 3.1.x)
# ---------------------------------------------------------------------------

scenario_host_allowlist_url_nao_autorizada_exit1() {
  _setup_serve_env
  _make_bin_dir
  _stub_npm_ok "$_STUB_BIN"
  # Stub curl que retorna URL de host nao-autorizado na API response
  cat > "$_STUB_BIN/curl" <<'STUB'
#!/bin/sh
_output=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) shift; _output="$1" ;;
  esac
  shift
done
_resp='{"tag_name":"v0.0.1","tarball_url":"https://evil.com/malware.tar.gz","prerelease":false,"draft":false}'
if [ -n "$_output" ]; then
  printf '%s\n' "$_resp" > "$_output"
else
  printf '%s\n' "$_resp"
fi
STUB
  chmod +x "$_STUB_BIN/curl"
  _run_serve
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "allowlist_host_nao_autorizado" "esperado exit 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  if ! printf '%s' "$_CAPTURED_STDERR" | grep -qi 'evil\|host\|nao.*permit\|nao.*autorizado\|allowlist\|rejeit'; then
    _fail "allowlist_mensagem" "stderr nao menciona host rejeitado"
    return 1
  fi
}

scenario_host_allowlist_http_schema_exit1() {
  _setup_serve_env
  _make_bin_dir
  _stub_npm_ok "$_STUB_BIN"
  # Stub curl que retorna URL com schema http:// (nao https) na tarball_url
  cat > "$_STUB_BIN/curl" <<'STUB'
#!/bin/sh
_output=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) shift; _output="$1" ;;
  esac
  shift
done
_resp='{"tag_name":"v0.0.1","tarball_url":"http://github.com/tarball.tar.gz","prerelease":false,"draft":false}'
if [ -n "$_output" ]; then
  printf '%s\n' "$_resp" > "$_output"
else
  printf '%s\n' "$_resp"
fi
STUB
  chmod +x "$_STUB_BIN/curl"
  _run_serve
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "allowlist_http_schema" "esperado exit 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_host_allowlist_github_url_ok() {
  _setup_serve_env
  _make_bin_dir
  _stub_curl_ok "$_STUB_BIN"
  _stub_npm_ok "$_STUB_BIN"
  _run_serve
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "allowlist_github_ok" "URL github.com valida deve passar; exit=$_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# FASE 2.3 — Deteccao de instalacao existente (tasks 2.3.x)
# ---------------------------------------------------------------------------

scenario_instalacao_subsequente_sem_rede() {
  _setup_serve_env
  _make_bin_dir
  # Instalar o "panel" manualmente no panel_dir
  mkdir -p "$CSTK_PANEL_DIR"
  printf '{"name":"cstk-panel","version":"0.0.1"}\n' > "$CSTK_PANEL_DIR/package.json"
  # Stub de curl que FALHA se chamado (nao deve ser chamado)
  _stub_curl_must_not_be_called "$_STUB_BIN"
  _stub_npm_ok "$_STUB_BIN"
  _run_serve
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "subsequente_sem_rede" "esperado exit 0, obtido $_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"
    return 1
  fi
}

scenario_instalacao_corrompida_sem_packagejson_exit1() {
  _setup_serve_env
  _make_bin_dir
  # Panel dir existe mas sem package.json
  mkdir -p "$CSTK_PANEL_DIR"
  _stub_curl_ok "$_STUB_BIN"
  _stub_npm_ok "$_STUB_BIN"
  _run_serve
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "corrompida_sem_pkg" "esperado exit 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  if ! printf '%s' "$_CAPTURED_STDERR" | grep -qi 'reinstall\|corrompid\|incompleto'; then
    _fail "corrompida_mensagem" "stderr nao sugere --reinstall"
    return 1
  fi
}

scenario_reinstall_apaga_e_reinstala() {
  _setup_serve_env
  _make_bin_dir
  # Instalar panel dir primeiro
  mkdir -p "$CSTK_PANEL_DIR"
  printf '{"name":"cstk-panel","version":"0.0.0"}\n' > "$CSTK_PANEL_DIR/package.json"
  printf 'v0.0.0\n' > "$CSTK_PANEL_DIR/.panel-version"
  _stub_curl_ok "$_STUB_BIN"
  _stub_npm_ok "$_STUB_BIN"
  _run_serve --reinstall
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "reinstall_ok" "esperado exit 0, obtido $_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"
    return 1
  fi
  # Deve ter nova versao instalada
  if [ ! -f "$CSTK_PANEL_DIR/.panel-version" ]; then
    _fail "reinstall_version_file" ".panel-version nao gravado apos reinstall"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# FASE 2.4 — Download e instalacao (tasks 2.4.x)
# ---------------------------------------------------------------------------

scenario_primeira_exec_ok_package_json_presente() {
  _setup_serve_env
  _make_bin_dir
  _stub_curl_ok "$_STUB_BIN"
  _stub_npm_ok "$_STUB_BIN"
  _run_serve
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "primeira_exec_exit" "esperado exit 0, obtido $_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"
    return 1
  fi
  if [ ! -f "$CSTK_PANEL_DIR/package.json" ]; then
    _fail "primeira_exec_pkg" "package.json nao encontrado em CSTK_PANEL_DIR"
    return 1
  fi
}

scenario_primeira_exec_grava_panel_version() {
  _setup_serve_env
  _make_bin_dir
  _stub_curl_ok "$_STUB_BIN"
  _stub_npm_ok "$_STUB_BIN"
  _run_serve
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "version_file_exit" "esperado exit 0, obtido $_CAPTURED_EXIT"
    return 1
  fi
  if [ ! -f "$CSTK_PANEL_DIR/.panel-version" ]; then
    _fail "version_file_ausente" ".panel-version nao gravado"
    return 1
  fi
  _v=$(cat "$CSTK_PANEL_DIR/.panel-version")
  if [ -z "$_v" ]; then
    _fail "version_file_vazio" ".panel-version esta vazio"
    return 1
  fi
}

# --- Launch: serve compila e sobe o painel via `npm run build && npm run start`
# (cstk-panel >= 0.2.0: Fastify serve API + SPA na mesma porta). Exporta PORT.

scenario_serve_lanca_build_e_start() {
  _setup_serve_env
  _make_bin_dir
  _stub_curl_ok "$_STUB_BIN"
  _stub_npm_logging "$_STUB_BIN"
  _run_serve
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "launch_exit" "esperado exit 0, obtido $_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"
    return 1
  fi
  # Deve compilar (npm run build) ANTES de subir...
  if ! grep -q 'cmd=\[run build' "$TMPDIR_TEST/npm-calls.log" 2>/dev/null; then
    _fail "launch_build" "serve nao invocou 'npm run build'"
    return 1
  fi
  # ...e subir via `npm run start` (processo unico Fastify), nunca `run dev`.
  if ! grep -q 'cmd=\[run start' "$TMPDIR_TEST/npm-calls.log" 2>/dev/null; then
    _fail "launch_start" "serve nao invocou 'npm run start'"
    return 1
  fi
  if grep -q 'cmd=\[run dev' "$TMPDIR_TEST/npm-calls.log" 2>/dev/null; then
    _fail "launch_nao_dev" "serve ainda invoca 'npm run dev' (modo dev removido)"
    return 1
  fi
}

scenario_serve_build_falha_exit1() {
  _setup_serve_env
  _make_bin_dir
  _stub_curl_ok "$_STUB_BIN"
  _stub_npm_build_fails "$_STUB_BIN"
  _run_serve
  # Build falho no launch -> exit 1, sem chegar ao start.
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "build_falha_exit" "esperado exit 1, obtido $_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"
    return 1
  fi
  if ! printf '%s' "$_CAPTURED_STDERR" | grep -qi 'build'; then
    _fail "build_falha_msg" "stderr nao menciona falha de build"
    return 1
  fi
}

scenario_serve_exporta_port() {
  _setup_serve_env
  _make_bin_dir
  _stub_curl_ok "$_STUB_BIN"
  _stub_npm_logging "$_STUB_BIN"
  # --port deve ser exportado como PORT para o painel (servidor unico Fastify
  # le process.env.PORT e binda essa porta). O stub loga o PORT herdado do env.
  _run_serve --port 8080
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "exporta_port_exit" "esperado exit 0, obtido $_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"
    return 1
  fi
  if ! grep -q 'PORT=\[8080\]' "$TMPDIR_TEST/npm-calls.log" 2>/dev/null; then
    _fail "exporta_port" "serve nao exportou PORT=8080 para o painel"
    return 1
  fi
  # NAO deve haver mais o aviso de "porta ignorada" (era do modo dev).
  if printf '%s' "$_CAPTURED_STDERR" | grep -qi 'ignorad'; then
    _fail "exporta_port_sem_aviso" "stderr ainda avisa que --port sera ignorado"
    return 1
  fi
}

# --- --update: reinstala o painel SO se houver versao mais recente -----------
# O stub _stub_curl_ok reporta a latest como v0.0.1.

scenario_update_versao_nova_reinstala() {
  _setup_serve_env
  _make_bin_dir
  # Instalado v0.0.0 (mais antigo que a latest v0.0.1) + sentinela.
  mkdir -p "$CSTK_PANEL_DIR"
  printf '{"name":"cstk-panel","version":"0.0.0"}\n' > "$CSTK_PANEL_DIR/package.json"
  printf 'v0.0.0\n' > "$CSTK_PANEL_DIR/.panel-version"
  : > "$CSTK_PANEL_DIR/SENTINELA"
  _stub_curl_ok "$_STUB_BIN"
  _stub_npm_ok "$_STUB_BIN"
  _run_serve --update
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "update_novo_exit" "esperado exit 0, obtido $_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"
    return 1
  fi
  # Reinstalou: a sentinela do dir antigo sumiu (dir recriado a partir do tarball).
  if [ -f "$CSTK_PANEL_DIR/SENTINELA" ]; then
    _fail "update_novo_reinstalou" "painel nao foi reinstalado (SENTINELA antiga persiste)"
    return 1
  fi
  # .panel-version atualizada para a latest.
  if [ "$(cat "$CSTK_PANEL_DIR/.panel-version" 2>/dev/null | tr -d ' \n')" != "v0.0.1" ]; then
    _fail "update_novo_versao" ".panel-version nao foi atualizada para v0.0.1"
    return 1
  fi
}

scenario_update_ja_atualizado_nao_reinstala() {
  _setup_serve_env
  _make_bin_dir
  # Instalado ja na latest (v0.0.1) + sentinela.
  mkdir -p "$CSTK_PANEL_DIR"
  printf '{"name":"cstk-panel","version":"0.0.1"}\n' > "$CSTK_PANEL_DIR/package.json"
  printf 'v0.0.1\n' > "$CSTK_PANEL_DIR/.panel-version"
  : > "$CSTK_PANEL_DIR/SENTINELA"
  _stub_curl_ok "$_STUB_BIN"
  _stub_npm_ok "$_STUB_BIN"
  _run_serve --update
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "update_atual_exit" "esperado exit 0, obtido $_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"
    return 1
  fi
  # NAO reinstalou: a sentinela permanece.
  if [ ! -f "$CSTK_PANEL_DIR/SENTINELA" ]; then
    _fail "update_atual_nao_reinstala" "painel foi reinstalado mesmo ja estando na latest"
    return 1
  fi
  if ! printf '%s' "$_CAPTURED_STDOUT" | grep -qi 'mais recente\|ja esta'; then
    _fail "update_atual_msg" "stdout nao informa que ja esta na versao mais recente"
    return 1
  fi
}

scenario_update_check_falha_mantem_instalado() {
  _setup_serve_env
  _make_bin_dir
  # Instalado v0.0.0 + sentinela; a checagem de update falha (rede off).
  mkdir -p "$CSTK_PANEL_DIR"
  printf '{"name":"cstk-panel","version":"0.0.0"}\n' > "$CSTK_PANEL_DIR/package.json"
  printf 'v0.0.0\n' > "$CSTK_PANEL_DIR/.panel-version"
  : > "$CSTK_PANEL_DIR/SENTINELA"
  _stub_curl_unreachable "$_STUB_BIN"
  _stub_npm_ok "$_STUB_BIN"
  _run_serve --update
  # Best-effort: falha na checagem NAO aborta; painel inicia com a versao atual.
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "update_falha_exit" "esperado exit 0 (best-effort), obtido $_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"
    return 1
  fi
  if [ ! -f "$CSTK_PANEL_DIR/SENTINELA" ]; then
    _fail "update_falha_mantem" "painel foi removido/reinstalado apesar da checagem ter falhado"
    return 1
  fi
  if ! printf '%s' "$_CAPTURED_STDERR" | grep -qi 'nao foi possivel verificar\|atualiza'; then
    _fail "update_falha_aviso" "stderr nao avisa que a verificacao de update falhou"
    return 1
  fi
}

scenario_tarball_corrompido_exit1() {
  _setup_serve_env
  _make_bin_dir
  # Stub curl: retorna JSON valido para API mas arquivo corrompido para download
  cat > "$_STUB_BIN/curl" <<'STUB'
#!/bin/sh
_output=""
_url=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) shift; _output="$1" ;;
    --) shift; _url="$1" ;;
    https://*) _url="$1" ;;
  esac
  shift
done
case "$_url" in
  *releases/latest*)
    _resp='{"tag_name":"v0.0.1","tarball_url":"https://github.com/JotJunior/cstk-panel/archive/v0.0.1.tar.gz","prerelease":false,"draft":false}'
    if [ -n "$_output" ]; then printf '%s\n' "$_resp" > "$_output"; else printf '%s\n' "$_resp"; fi
    ;;
  *tar.gz*)
    # Gerar conteudo corrompido (nao eh tar valido)
    if [ -n "$_output" ]; then
      printf 'INVALIDO_NAO_EH_TARBALL_CORROMPIDO\n' > "$_output"
    fi
    ;;
esac
STUB
  chmod +x "$_STUB_BIN/curl"
  _stub_npm_ok "$_STUB_BIN"
  _run_serve
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "tarball_corrompido" "esperado exit 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_npm_install_falha_exit1() {
  _setup_serve_env
  _make_bin_dir
  _stub_curl_ok "$_STUB_BIN"
  # npm que falha em install mas ok em start
  cat > "$_STUB_BIN/npm" <<'STUB'
#!/bin/sh
case "$1" in
  install) exit 1 ;;
  *) exit 0 ;;
esac
STUB
  chmod +x "$_STUB_BIN/npm"
  _run_serve
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "npm_install_falha" "esperado exit 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# FASE 4.2 — Graceful shutdown: SIGTERM + SIGKILL fallback (task 4.2.5)
# ---------------------------------------------------------------------------

# _stub_npm_ignores_sigterm: cria stub de npm que ignora SIGTERM por alguns
# ciclos antes de sair. Testa que o grace period aciona SIGKILL.
# $1 = bin dir
_stub_npm_ignores_sigterm() {
  _snist_bin="$1"
  cat > "$_snist_bin/npm" <<'STUB'
#!/bin/sh
# install e `run build` saem 0 (o serve builda antes de subir); so `run dev`/
# `run start` (o filho de longa duracao) ignora SIGTERM por alguns ciclos.
case "$1 $2" in
  "run build") exit 0 ;;
  "run dev"|"run start")
    # Registrar handler SIGTERM que NAO encerra o processo (ignora o sinal)
    trap '' TERM
    # Aguardar com sleep em loop; o SIGKILL (enviado apos grace period) vai
    # matar este processo mesmo sem handler. Usar sleep curto para nao
    # travar o teste por muito tempo.
    _cnt=0
    while [ "$_cnt" -lt 20 ]; do
      sleep 0.2 2>/dev/null || sleep 1
      _cnt=$((_cnt + 1))
    done
    exit 0
    ;;
  *) exit 0 ;;
esac
STUB
  chmod +x "$_snist_bin/npm"
}

# scenario_sigterm_graceful_kill: verifica que _serve_shutdown envia SIGKILL
# quando o filho ignora SIGTERM apos o grace period.
# O cenario cria um panel instalado (para evitar download) e dispara
# serve_main em background via subshell, depois envia SIGTERM ao processo
# serve_main e verifica que ele encerra dentro de 8s (grace 5s + margem 3s).
scenario_sigterm_graceful_kill() {
  _setup_serve_env
  _make_bin_dir
  _stub_curl_ok "$_STUB_BIN"
  _stub_npm_ignores_sigterm "$_STUB_BIN"

  # Pre-instalar o panel para que serve_main nao tente download
  mkdir -p "$CSTK_PANEL_DIR"
  printf '{}' > "$CSTK_PANEL_DIR/package.json"
  printf 'v0.0.1\n' > "$CSTK_PANEL_DIR/.panel-version"

  # Arquivo de resultado para comunicacao entre subshell e test
  _result_file="$TMPDIR_TEST/serve_exit_code"

  # Rodar serve_main em background em subshell; gravar exit code
  (
    export CSTK_LIB CSTK_PANEL_DIR PATH HOME="$TMPDIR_TEST"
    . "$CSTK_LIB/serve.sh"
    serve_main --port 5173
    printf '%d\n' "$?" > "$_result_file"
  ) &
  _serve_pid=$!

  # Aguardar o npm stub iniciar (grace de 0.5s)
  sleep 0.5 2>/dev/null || sleep 1

  # Enviar SIGTERM ao grupo de processos do serve_main
  kill -TERM "$_serve_pid" 2>/dev/null || :

  # Aguardar encerramento com timeout de 8s (grace period 5s + margem 3s)
  _wait_max=16
  _wait_cnt=0
  while [ "$_wait_cnt" -lt "$_wait_max" ]; do
    if ! kill -0 "$_serve_pid" 2>/dev/null; then
      break
    fi
    sleep 0.5 2>/dev/null || sleep 1
    _wait_cnt=$((_wait_cnt + 1))
  done

  # Se ainda vivo apos 8s, o teste falha (SIGKILL nao funcionou)
  if kill -0 "$_serve_pid" 2>/dev/null; then
    kill -KILL "$_serve_pid" 2>/dev/null || :
    wait "$_serve_pid" 2>/dev/null || :
    _fail "sigterm_graceful_kill" "serve_main nao encerrou em 8s apos SIGTERM (SIGKILL falhou)"
    return 1
  fi

  # Aguardar finalizacao para capturar exit code
  wait "$_serve_pid" 2>/dev/null || :

  # O processo deve ter encerrado (qualquer exit code e aceitavel aqui;
  # o importante e que o processo nao ficou pendurado)
  if [ "$_wait_cnt" -ge "$_wait_max" ]; then
    _fail "sigterm_graceful_kill" "serve_main demorou demais para encerrar: $_wait_cnt ciclos"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# FASE 3.2 — POSIX puro: zero eval (tasks 3.2.x)
# ---------------------------------------------------------------------------

scenario_zero_eval_no_serve_sh() {
  # Verifica que serve.sh nao usa eval (S5/CHK-S05)
  _serve_sh="$REPO_ROOT/cli/lib/serve.sh"
  if [ ! -f "$_serve_sh" ]; then
    _error "zero_eval" "serve.sh nao existe"
    return 2
  fi
  # grep -c retorna 0 se nenhuma ocorrencia, >0 se encontrou.
  # Sucesso (exit 0 do scenario) = zero ocorrencias de eval.
  if grep -qE '\beval\b' "$_serve_sh" 2>/dev/null; then
    _count=$(grep -cE '\beval\b' "$_serve_sh" 2>/dev/null || printf '?')
    _fail "zero_eval" "serve.sh contem $_count uso(s) de eval"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# FASE 4 — Saida espontanea do filho (tasks 4.x)
# ---------------------------------------------------------------------------

scenario_saida_espontanea_filho_propaga_exit() {
  _setup_serve_env
  _make_bin_dir
  _stub_curl_ok "$_STUB_BIN"
  # npm que sai com exit 2 imediatamente
  _stub_npm_exit_code "$_STUB_BIN" 2
  _run_serve
  if [ "$_CAPTURED_EXIT" != "2" ]; then
    _fail "saida_espontanea_exit" "esperado exit 2 (propagado do filho), obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_saida_espontanea_mensagem_stderr() {
  _setup_serve_env
  _make_bin_dir
  _stub_curl_ok "$_STUB_BIN"
  _stub_npm_exit_code "$_STUB_BIN" 1
  _run_serve
  # Deve emitir mensagem de encerramento inesperado no stderr
  if ! printf '%s' "$_CAPTURED_STDERR" | grep -qi 'encerrou\|inesperado\|exit'; then
    _fail "saida_espontanea_msg" "stderr nao menciona encerramento inesperado"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# enforced-guards US2 — Integridade fail-closed no cstk serve (tasks 3.1-3.5)
#
# Ref: docs/specs/enforced-guards/{spec.md FR-008/009/010/011,
#      data-model.md::IntegrityVerificationOutcome,
#      contracts/enforcement-log.md, quickstart.md Scenarios 5-7}.
# ---------------------------------------------------------------------------

# Scenario 5 (quickstart) / task 3.1.4: sem .sha256 disponivel e sem
# bypass -> bloqueia por padrao (fail-closed), sem instalacao parcial, com
# mensagem apontando os dois caminhos conscientes de bypass, e linha
# auditavel unverifiable-blocked no enforcement-log (task 3.3.1/3.3.2).
scenario_integridade_sem_sha256_bloqueia_por_padrao() {
  _setup_serve_env
  _make_bin_dir
  _snapshot_repo_root_log
  _stub_curl_no_sha256 "$_STUB_BIN"
  _stub_npm_ok "$_STUB_BIN"
  _run_serve
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "integridade_sem_sha256_exit" "esperado exit 1 (fail-closed default), obtido $_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"
    return 1
  fi
  if [ -f "$CSTK_PANEL_DIR/package.json" ]; then
    _fail "integridade_sem_sha256_sem_instalacao_parcial" "package.json NAO deveria existir apos bloqueio de integridade"
    return 1
  fi
  if ! printf '%s' "$_CAPTURED_STDERR" | grep -qi 'integridade'; then
    _fail "integridade_sem_sha256_msg" "stderr nao menciona integridade nao confirmada: $_CAPTURED_STDERR"
    return 1
  fi
  if ! printf '%s' "$_CAPTURED_STDERR" | grep -q -- '--allow-unverified'; then
    _fail "integridade_sem_sha256_aponta_flag" "stderr nao aponta --allow-unverified como caminho consciente"
    return 1
  fi
  if ! printf '%s' "$_CAPTURED_STDERR" | grep -q 'CSTK_SERVE_ALLOW_UNVERIFIED'; then
    _fail "integridade_sem_sha256_aponta_env" "stderr nao aponta CSTK_SERVE_ALLOW_UNVERIFIED como caminho consciente"
    return 1
  fi
  _log=$(_serve_enforcement_log)
  case "$_log" in
    *'"source":"serve-integrity"'*) : ;;
    *) _fail "integridade_sem_sha256_log_source" "enforcement-log sem source=serve-integrity; log=$_log"; return 1 ;;
  esac
  case "$_log" in
    *'"outcome":"unverifiable-blocked"'*) : ;;
    *) _fail "integridade_sem_sha256_log_outcome" "esperado outcome=unverifiable-blocked; log=$_log"; return 1 ;;
  esac
  case "$_log" in
    *'"expected_sha256":null'*) : ;;
    *) _fail "integridade_sem_sha256_log_expected_null" "esperado expected_sha256=null; log=$_log"; return 1 ;;
  esac
  case "$_log" in
    *'"bypass_method":null'*) : ;;
    *) _fail "integridade_sem_sha256_log_bypass_null" "esperado bypass_method=null (sem bypass); log=$_log"; return 1 ;;
  esac
  _assert_no_repo_root_leak || return 1
}

# Scenario 6 (quickstart) / task 3.2.4, variante --allow-unverified: bypass
# explicito via flag prossegue, com aviso de ALTA VISIBILIDADE em stderr
# (research.md Decision 6 adendo/owasp-security) e outcome
# unverifiable-bypassed + bypass_method=flag no log.
scenario_integridade_allow_unverified_flag_prossegue() {
  _setup_serve_env
  _make_bin_dir
  _snapshot_repo_root_log
  _stub_curl_no_sha256 "$_STUB_BIN"
  _stub_npm_ok "$_STUB_BIN"
  _run_serve --allow-unverified
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "integridade_flag_exit" "esperado exit 0 (bypass explicito), obtido $_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"
    return 1
  fi
  if [ ! -f "$CSTK_PANEL_DIR/package.json" ]; then
    _fail "integridade_flag_instalou" "package.json esperado apos bypass explicito"
    return 1
  fi
  if ! printf '%s' "$_CAPTURED_STDERR" | grep -qi 'AVISO'; then
    _fail "integridade_flag_aviso" "stderr nao contem aviso de alta visibilidade (AVISO); stderr=$_CAPTURED_STDERR"
    return 1
  fi
  _log=$(_serve_enforcement_log)
  case "$_log" in
    *'"outcome":"unverifiable-bypassed"'*) : ;;
    *) _fail "integridade_flag_log_outcome" "esperado outcome=unverifiable-bypassed; log=$_log"; return 1 ;;
  esac
  case "$_log" in
    *'"bypass_method":"flag"'*) : ;;
    *) _fail "integridade_flag_log_bypass_method" "esperado bypass_method=flag; log=$_log"; return 1 ;;
  esac
  _assert_no_repo_root_leak || return 1
}

# Scenario 6 (quickstart) / task 3.2.4, variante CSTK_SERVE_ALLOW_UNVERIFIED=1
# (uso nao-interativo/scripts/CI): mesmo bypass, mesmo aviso obrigatorio,
# bypass_method=env no log.
scenario_integridade_allow_unverified_env_prossegue() {
  _setup_serve_env
  _make_bin_dir
  _snapshot_repo_root_log
  _stub_curl_no_sha256 "$_STUB_BIN"
  _stub_npm_ok "$_STUB_BIN"
  CSTK_SERVE_ALLOW_UNVERIFIED=1
  export CSTK_SERVE_ALLOW_UNVERIFIED
  _run_serve
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "integridade_env_exit" "esperado exit 0 (bypass via env), obtido $_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"
    return 1
  fi
  if ! printf '%s' "$_CAPTURED_STDERR" | grep -qi 'AVISO'; then
    _fail "integridade_env_aviso" "stderr nao contem aviso de alta visibilidade; stderr=$_CAPTURED_STDERR"
    return 1
  fi
  _log=$(_serve_enforcement_log)
  case "$_log" in
    *'"outcome":"unverifiable-bypassed"'*) : ;;
    *) _fail "integridade_env_log_outcome" "esperado outcome=unverifiable-bypassed; log=$_log"; return 1 ;;
  esac
  case "$_log" in
    *'"bypass_method":"env"'*) : ;;
    *) _fail "integridade_env_log_bypass_method" "esperado bypass_method=env; log=$_log"; return 1 ;;
  esac
  _assert_no_repo_root_leak || return 1
}

# Extra (nao numerado no quickstart, mas protege a regra de precedencia
# documentada no proprio serve.sh): com flag E env presentes, a flag
# explicita vence — bypass_method registrado reflete a origem que
# efetivamente decidiu.
scenario_integridade_flag_tem_precedencia_sobre_env() {
  _setup_serve_env
  _make_bin_dir
  _snapshot_repo_root_log
  _stub_curl_no_sha256 "$_STUB_BIN"
  _stub_npm_ok "$_STUB_BIN"
  CSTK_SERVE_ALLOW_UNVERIFIED=1
  export CSTK_SERVE_ALLOW_UNVERIFIED
  _run_serve --allow-unverified
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "integridade_precedencia_exit" "esperado exit 0, obtido $_CAPTURED_EXIT"
    return 1
  fi
  _log=$(_serve_enforcement_log)
  case "$_log" in
    *'"bypass_method":"flag"'*) : ;;
    *) _fail "integridade_precedencia_bypass_method" "com flag+env ambos presentes, esperado bypass_method=flag (flag vence); log=$_log"; return 1 ;;
  esac
  _assert_no_repo_root_leak || return 1
}

# Task 3.3.3/3.5.3: caminho feliz (verified) nao grava NENHUMA linha no
# enforcement-log — regressao de ruido, ja coberto pelo printf informativo
# existente.
scenario_integridade_verified_nao_grava_log() {
  _setup_serve_env
  _make_bin_dir
  _snapshot_repo_root_log
  _stub_curl_ok "$_STUB_BIN"
  _stub_npm_ok "$_STUB_BIN"
  _run_serve
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "integridade_verified_exit" "esperado exit 0, obtido $_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"
    return 1
  fi
  if ! printf '%s' "$_CAPTURED_STDOUT" | grep -qi 'integridade verificada'; then
    _fail "integridade_verified_msg" "stdout nao confirma integridade verificada; stdout=$_CAPTURED_STDOUT"
    return 1
  fi
  _log=$(_serve_enforcement_log)
  if [ -n "$_log" ]; then
    _fail "integridade_verified_sem_log" "outcome verified NAO deve gravar linha no enforcement-log (task 3.3.3); log=$_log"
    return 1
  fi
  _assert_no_repo_root_leak || return 1
}

# Scenario 7 (quickstart) / task 3.4.1/3.4.3/3.4.4, baseline sem flag:
# .sha256 disponivel mas adulterado -> bloqueia como hoje (regressao
# FR-010), com outcome mismatch-blocked e ambos os hashes registrados.
scenario_integridade_mismatch_bloqueia_sem_flag() {
  _setup_serve_env
  _make_bin_dir
  _snapshot_repo_root_log
  _stub_curl_bad_sha256 "$_STUB_BIN"
  _stub_npm_ok "$_STUB_BIN"
  _run_serve
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "integridade_mismatch_exit" "esperado exit 1 (checksum nao confere), obtido $_CAPTURED_EXIT"
    return 1
  fi
  if [ -f "$CSTK_PANEL_DIR/package.json" ]; then
    _fail "integridade_mismatch_sem_instalacao" "package.json NAO deveria existir apos mismatch"
    return 1
  fi
  if ! printf '%s' "$_CAPTURED_STDERR" | grep -qi 'nao confere\|checksum'; then
    _fail "integridade_mismatch_msg" "stderr nao menciona checksum/divergencia; stderr=$_CAPTURED_STDERR"
    return 1
  fi
  _log=$(_serve_enforcement_log)
  case "$_log" in
    *'"outcome":"mismatch-blocked"'*) : ;;
    *) _fail "integridade_mismatch_log_outcome" "esperado outcome=mismatch-blocked; log=$_log"; return 1 ;;
  esac
  case "$_log" in
    *'"bypass_method":null'*) : ;;
    *) _fail "integridade_mismatch_log_bypass_null" "esperado bypass_method=null; log=$_log"; return 1 ;;
  esac
  case "$_log" in
    *'"expected_sha256":null'*) _fail "integridade_mismatch_log_expected_nao_deveria_ser_null" "log=$_log"; return 1 ;;
  esac
  case "$_log" in
    *'"actual_sha256":null'*) _fail "integridade_mismatch_log_actual_nao_deveria_ser_null" "log=$_log"; return 1 ;;
  esac
  _assert_no_repo_root_leak || return 1
}

# Task 3.4.2/3.4.4, regressao critica: --allow-unverified NUNCA pode
# bypassar uma divergencia de checksum (so se aplica a "nao-verificavel").
scenario_integridade_mismatch_bloqueia_mesmo_com_allow_unverified() {
  _setup_serve_env
  _make_bin_dir
  _snapshot_repo_root_log
  _stub_curl_bad_sha256 "$_STUB_BIN"
  _stub_npm_ok "$_STUB_BIN"
  _run_serve --allow-unverified
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "integridade_mismatch_flag_exit" "regressao FR-010: --allow-unverified NUNCA deve bypassar mismatch; esperado exit 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  _log=$(_serve_enforcement_log)
  case "$_log" in
    *'"outcome":"mismatch-blocked"'*) : ;;
    *) _fail "integridade_mismatch_flag_log_outcome" "esperado outcome=mismatch-blocked mesmo com --allow-unverified; log=$_log"; return 1 ;;
  esac
  case "$_log" in
    *'"outcome":"unverifiable-bypassed"'*) _fail "integridade_mismatch_flag_nao_deveria_bypassar" "--allow-unverified NAO pode transformar mismatch em bypass; log=$_log"; return 1 ;;
  esac
  _assert_no_repo_root_leak || return 1
}

# Cobertura de --help (mesmo padrao de scenario_help_menciona_flags).
scenario_help_menciona_allow_unverified() {
  _setup_serve_env
  _run_serve --help
  if ! printf '%s' "$_CAPTURED_STDOUT" | grep -q -- '--allow-unverified'; then
    _fail "help_allow_unverified" "help nao menciona --allow-unverified"
    return 1
  fi
  if ! printf '%s' "$_CAPTURED_STDOUT" | grep -q 'CSTK_SERVE_ALLOW_UNVERIFIED'; then
    _fail "help_env_allow_unverified" "help nao menciona CSTK_SERVE_ALLOW_UNVERIFIED"
    return 1
  fi
}

# Cobertura de --help para --docker (task 6.1, FR-014): nao so a existencia
# da flag (ja coberta por scenario_help_menciona_flags), mas a semantica
# docker-specific de --update/--reinstall (rebuild de imagem vs
# reinstalacao de dir) exigida pelo criterio de completude do backlog.
scenario_help_menciona_docker_composition() {
  _setup_serve_env
  _run_serve --help
  # --docker documentado nas 3 secoes esperadas: Usage, Options, Examples.
  if ! printf '%s' "$_CAPTURED_STDOUT" | grep -q -- '\[--docker\]'; then
    _fail "help_docker_usage" "help nao lista [--docker] na linha de Usage"
    return 1
  fi
  if ! printf '%s' "$_CAPTURED_STDOUT" | grep -q -- 'cstk serve --docker'; then
    _fail "help_docker_example" "help nao tem exemplo de uso com --docker"
    return 1
  fi
  # Semantica docker-specific de --update/--reinstall (nao so a flag) —
  # ambas devem mencionar explicitamente o comportamento de imagem.
  if ! printf '%s' "$_CAPTURED_STDOUT" | grep -q 'rebuilds the local image'; then
    _fail "help_docker_update_semantics" "help nao explica que --docker+--update reconstroi a imagem local"
    return 1
  fi
  if ! printf '%s' "$_CAPTURED_STDOUT" | grep -q 'removes the local image'; then
    _fail "help_docker_reinstall_semantics" "help nao explica que --docker+--reinstall remove a imagem local"
    return 1
  fi
  # Pre-requisitos e paridade de dados citados na descricao da flag.
  if ! printf '%s' "$_CAPTURED_STDOUT" | grep -q 'daemon running'; then
    _fail "help_docker_daemon_prereq" "help nao menciona o pre-requisito de daemon Docker rodando"
    return 1
  fi
  if ! printf '%s' "$_CAPTURED_STDOUT" | grep -q 'CSTK_KNOWLEDGE_DB'; then
    _fail "help_docker_kdb_env" "help nao menciona CSTK_KNOWLEDGE_DB no contexto do mount --docker"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# panel-docker FASE 2 — 2.1: composicao/regressao da flag --docker
#
# Orquestracao PROFUNDA de _serve_docker_main (pre-flight, build triggers,
# docker run, reconciliacao, shutdown, mensagens) e coberta exaustivamente
# em tests/cstk/test_serve-docker.sh -- os scenarios abaixo cobrem so o que
# e responsabilidade do PARSER/DISPATCH de serve_main: (a) ausencia de
# --docker nunca toca o binario docker (FR-002); (b) presenca de --docker
# despacha ANTES do prereq de npm, que deixa de ser exigido (FR-006), mas
# curl continua exigido; (c) validacao de porta/host (compartilhada) segue
# se aplicando identicamente com --docker presente -- nao ha um segundo
# parser.
# ---------------------------------------------------------------------------

# _stub_docker_must_not_be_called: stub docker que FALHA ruidosamente se
# invocado -- prova que a AUSENCIA de --docker nunca toca docker (task
# 2.1.3/4.3.2). Mesmo espirito de _stub_curl_must_not_be_called (acima).
_stub_docker_must_not_be_called() {
  _sdmnbc_bin="$1"
  cat > "$_sdmnbc_bin/docker" <<'STUB'
#!/bin/sh
printf 'ERRO: docker foi chamado mas nao deveria (flag --docker ausente): %s\n' "$*" >&2
exit 1
STUB
  chmod +x "$_sdmnbc_bin/docker"
}

scenario_docker_absent_flag_never_probes_container_runtime() {
  _setup_serve_env
  _make_bin_dir
  _stub_curl_ok "$_STUB_BIN"
  _stub_npm_ok "$_STUB_BIN"
  _stub_docker_must_not_be_called "$_STUB_BIN"
  _run_serve
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "docker_absent_no_probe_exit" "esperado exit 0 (fluxo nativo intacto), obtido $_CAPTURED_EXIT: $_CAPTURED_STDERR"
    return 1
  fi
  if printf '%s' "$_CAPTURED_STDERR" | grep -q 'ERRO: docker foi chamado'; then
    _fail "docker_absent_no_probe" "docker foi invocado mesmo sem a flag --docker (violacao FR-002)"
    return 1
  fi
}

scenario_docker_flag_does_not_require_npm_on_host() {
  # FR-006: --docker NUNCA deve exigir npm no host. PATH interno com curl
  # stubado mas SEM npm nenhum -- se o despacho ocorrer ANTES do prereq de
  # npm (como deve), a execucao nunca reclama de npm ausente (pode falhar
  # por outro motivo -- ex. docker ausente -- mas nunca por causa de npm).
  _setup_serve_env
  _dfn_bin="$TMPDIR_TEST/stubs"
  mkdir -p "$_dfn_bin"
  _stub_curl_ok "$_dfn_bin"
  _SERVE_INNER_PATH="$_dfn_bin:$(_isolated_sh_dir)"
  _run_serve --docker
  if printf '%s' "$_CAPTURED_STDERR" | grep -qi 'npm nao encontrado'; then
    _fail "docker_flag_requires_npm" "modo --docker nao deveria exigir npm no host (FR-006): $_CAPTURED_STDERR"
    return 1
  fi
}

scenario_docker_flag_still_requires_curl_on_host() {
  # curl e exigido em AMBOS os modos (download/verificacao do painel,
  # reusado por _serve_download_verify_extract) -- PATH interno SEM curl
  # nem docker.
  _setup_serve_env
  _dfc_bin="$TMPDIR_TEST/stubs"
  mkdir -p "$_dfc_bin"
  _SERVE_INNER_PATH="$_dfc_bin:$(_isolated_sh_dir)"
  _run_serve --docker
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "docker_flag_curl_exit" "esperado exit 1 (curl ausente), obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "curl" || return 1
}

scenario_docker_flag_reaches_docker_specific_preflight_message() {
  # docker AUSENTE (mesmo com curl presente) deve produzir a mensagem
  # ESPECIFICA de serve-docker.sh (nao alguma mensagem generica do modo
  # nativo) -- confirma que o despacho de fato ocorreu (task 2.1.1/2.1.2).
  _setup_serve_env
  _dfp_bin="$TMPDIR_TEST/stubs"
  mkdir -p "$_dfp_bin"
  _stub_curl_ok "$_dfp_bin"
  _SERVE_INNER_PATH="$_dfp_bin:$(_isolated_sh_dir)"
  _run_serve --docker
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "docker_flag_preflight_exit" "esperado exit 1 (docker ausente), obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains 'cstk serve --docker: erro: docker nao encontrado' || return 1
}

scenario_docker_flag_composes_with_port_validation() {
  # Validacao de porta (compartilhada, roda ANTES do despacho) continua se
  # aplicando com --docker presente -- nao ha um segundo parser/validador
  # (research.md Decision 5: "mesma validacao 1024-65535").
  _setup_serve_env
  _run_serve --docker --port 80
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "docker_port_privilegio" "esperado exit 1 (porta privilegiada), obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains 'privileg' || return 1
}

scenario_docker_flag_invalid_port_exit2_before_dispatch() {
  _setup_serve_env
  _run_serve --docker --port abc
  if [ "$_CAPTURED_EXIT" != "2" ]; then
    _fail "docker_port_invalida" "esperado exit 2 (porta invalida), obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_docker_flag_host_nao_loopback_aviso_ainda_aplica() {
  # O aviso de --host nao-loopback (compartilhado, roda ANTES do
  # despacho) continua valendo com --docker presente.
  _setup_serve_env
  _dfh_bin="$TMPDIR_TEST/stubs"
  mkdir -p "$_dfh_bin"
  _stub_curl_ok "$_dfh_bin"
  _SERVE_INNER_PATH="$_dfh_bin:$(_isolated_sh_dir)"
  _run_serve --docker --host 0.0.0.0
  if ! printf '%s' "$_CAPTURED_STDOUT" | grep -qi 'aviso\|warn\|atencao\|0\.0\.0\.0'; then
    _fail "docker_host_aviso" "stdout nao contem aviso sobre host nao-loopback com --docker"
    return 1
  fi
}

run_all_scenarios
