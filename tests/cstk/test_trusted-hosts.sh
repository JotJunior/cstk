#!/bin/sh
# test_trusted-hosts.sh — cobre cli/lib/trusted-hosts.sh
#
# Contrato:
#   trusted_host_check <url>
#     exit 0  esquema file:// (isento, FR-014) OU https:// com host na
#             allowlist (match exato, case-insensitive)
#     exit 1  esquema diferente de https/file, OU host fora da allowlist
#
# Ref: docs/specs/enforced-guards/contracts/trusted-hosts.md
#      docs/specs/enforced-guards/data-model.md::TrustedHostAllowlist
#      docs/specs/enforced-guards/checklists/security.md CHK014/CHK015/CHK018
#
# Estrategia: source direto da lib (sem rede, sem harness real) — mesmo
# padrao de tests/cstk/test_compat.sh.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CSTK_LIB="$REPO_ROOT/cli/lib"
export CSTK_LIB

# ---------------------------------------------------------------------------
# Hosts confiaveis aceitos (os 4 da allowlist, fonte serve.sh:31)
# ---------------------------------------------------------------------------

scenario_trusted_host_github_com_aceito() {
  capture sh -c ". \"$CSTK_LIB/trusted-hosts.sh\" && trusted_host_check 'https://github.com/JotJunior/cstk/releases/download/v1.0.0/cstk-1.0.0.tar.gz'"
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "github_com_aceito" "esperado exit 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
}

scenario_trusted_host_todos_os_5_aceitos() {
  # release-assets.githubusercontent.com entrou na lista pela issue #178: e o
  # host de destino real da cadeia de redirects de um asset de release
  # (medido; ver o cabecalho de cli/lib/trusted-hosts.sh).
  for _h in github.com codeload.github.com objects.githubusercontent.com \
            release-assets.githubusercontent.com api.github.com; do
    capture sh -c ". \"$CSTK_LIB/trusted-hosts.sh\" && trusted_host_check 'https://$_h/path/to/asset.tar.gz'"
    if [ "$_CAPTURED_EXIT" != "0" ]; then
      _fail "host_${_h}_aceito" "esperado exit 0, obtido $_CAPTURED_EXIT"
      return 1
    fi
  done
}

scenario_trusted_host_case_insensitive_aceito() {
  capture sh -c ". \"$CSTK_LIB/trusted-hosts.sh\" && trusted_host_check 'https://GitHub.COM/JotJunior/cstk/releases/download/v1/cstk-1.tar.gz'"
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "case_insensitive_aceito" "esperado exit 0 (DNS e case-insensitive), obtido $_CAPTURED_EXIT"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Hosts confusable (CWE-290) rejeitados — MUST NOT ser tratado como
# substring/grep. checklists/security.md CHK014.
# ---------------------------------------------------------------------------

scenario_trusted_host_sufixo_confusable_rejeitado() {
  # github.com.evil.com NAO e github.com — sufixo confusable classico.
  capture sh -c ". \"$CSTK_LIB/trusted-hosts.sh\" && trusted_host_check 'https://github.com.evil.com/malware.tar.gz'"
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "sufixo_confusable_rejeitado" "esperado exit 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "github.com.evil.com" || return 1
}

scenario_trusted_host_query_confusable_rejeitado() {
  # querystring contendo "github.com" nao deve enganar um match substring.
  capture sh -c ". \"$CSTK_LIB/trusted-hosts.sh\" && trusted_host_check 'https://evil.com/?x=github.com'"
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "query_confusable_rejeitado" "esperado exit 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "evil.com" || return 1
}

scenario_trusted_host_userinfo_bypass_rejeitado() {
  # O HOST real de "https://github.com@evil.com/x" e evil.com (userinfo e
  # so credencial) — DEVE rejeitar, nao deixar "github.com@" enganar.
  capture sh -c ". \"$CSTK_LIB/trusted-hosts.sh\" && trusted_host_check 'https://github.com@evil.com/malware.tar.gz'"
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "userinfo_bypass_rejeitado" "esperado exit 1 (host real e evil.com), obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_trusted_host_userinfo_com_host_confiavel_aceito() {
  # Userinfo antes de um host REALMENTE confiavel deve passar (o userinfo e
  # so credencial, removido ANTES da comparacao — nao e o vetor de ataque).
  capture sh -c ". \"$CSTK_LIB/trusted-hosts.sh\" && trusted_host_check 'https://user:tok@github.com/path/asset.tar.gz'"
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "userinfo_host_confiavel_aceito" "esperado exit 0 (host real e github.com), obtido $_CAPTURED_EXIT"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Esquema (file:// isento; nao-https/file rejeitado)
# ---------------------------------------------------------------------------

scenario_trusted_host_file_scheme_isento() {
  # FR-014: file:// nunca exige host na allowlist, mesmo com path arbitrario.
  capture sh -c ". \"$CSTK_LIB/trusted-hosts.sh\" && trusted_host_check 'file:///tmp/qualquer/cstk-dev.tar.gz'"
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "file_scheme_isento" "esperado exit 0 (file:// e isento), obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_trusted_host_esquema_http_rejeitado() {
  capture sh -c ". \"$CSTK_LIB/trusted-hosts.sh\" && trusted_host_check 'http://github.com/asset.tar.gz'"
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "esquema_http_rejeitado" "esperado exit 1 (so https/file), obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_trusted_host_esquema_ftp_rejeitado() {
  capture sh -c ". \"$CSTK_LIB/trusted-hosts.sh\" && trusted_host_check 'ftp://github.com/asset.tar.gz'"
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "esquema_ftp_rejeitado" "esperado exit 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Porta explicita — tratada como host diferente (nota do contrato, fora de
# escopo v1 normalizar; e uma consequencia natural do match exato)
# ---------------------------------------------------------------------------

scenario_trusted_host_porta_explicita_rejeitada() {
  capture sh -c ". \"$CSTK_LIB/trusted-hosts.sh\" && trusted_host_check 'https://github.com:443/asset.tar.gz'"
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "porta_explicita_rejeitada" "esperado exit 1 (porta => host diferente), obtido $_CAPTURED_EXIT"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Host desconhecido generico + qualidade da mensagem (FR-013)
# ---------------------------------------------------------------------------

scenario_trusted_host_desconhecido_rejeitado() {
  capture sh -c ". \"$CSTK_LIB/trusted-hosts.sh\" && trusted_host_check 'https://evil.example.com/cstk-malware.tar.gz'"
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "desconhecido_rejeitado" "esperado exit 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_trusted_host_mensagem_cita_host_e_lista() {
  capture sh -c ". \"$CSTK_LIB/trusted-hosts.sh\" && trusted_host_check 'https://evil.example.com/x.tar.gz'"
  assert_stderr_contains "evil.example.com" || return 1
  assert_stderr_contains "github.com" || return 1
}

run_all_scenarios
