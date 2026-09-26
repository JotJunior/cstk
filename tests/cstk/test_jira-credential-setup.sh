#!/bin/sh
# test_jira-credential-setup.sh — cobre
# plugins/cstk-jira/skills/jira-setup/scripts/jira-credential-setup.sh
# (cstk-jira, FASE 12 tarefa 12.12.1).
#
# Ref: docs/specs/cstk-jira/plan.md risco 5 / FR-019-INFRA-REFRESH
#      "jira-setup exibe a data de validade informada pelo operador como
#      lembrete"; docs/specs/cstk-jira/data-model.md Entity Credential;
#      tasks.md 6.1.2/6.1.6, 12.12.1.
#
# Estrategia: o script pede site_host por argv e email/api_token/
# data-de-validade por stdin (`IFS= read -r`). Sob teste, stdin nao e um
# tty (`[ -t 0 ]` falso), entao o script cai no ramo de leitura visivel do
# token (mesmo caminho do operador num terminal sem `stty`) — comportamento
# ja existente. Input via arquivo + `< FILE` (NUNCA `printf ... | assert_exit
# ...`): pipe colocaria `assert_exit`/`capture` num SUBSHELL (POSIX), e as
# variaveis `_CAPTURED_*` setadas la dentro se perderiam ao sair do pipe —
# `assert_stdout_contains`/`assert_stderr_contains` chamados DEPOIS, no
# escopo externo, veriam sempre vazio (bug medido: exit code batia por
# coincidencia — e o unico dado que sobrevive ao pipe via `$?` do ultimo
# estagio — mas stdout/stderr capturados ficavam sempre "[]"). Redirecao
# `< FILE` nao cria subshell, entao `_CAPTURED_*` ficam visiveis no
# scenario.
#
# Invariantes cobertos:
#   JCS-1 site_host invalido (charset) -> exit 1, nada escrito
#   JCS-2 numero de argumentos != 1 -> exit 1 (uso)
#   JCS-3 email vazio (1a linha em branco) -> exit 1, nada escrito
#   JCS-4 api_token vazio (2a linha em branco) -> exit 1, nada escrito
#   JCS-5 data de validade informada -> gravada como token_expires_at=...
#         no arquivo de credencial, modo 0600, E ecoada como LEMBRETE em
#         stdout
#   JCS-6 data de validade em branco (Enter) -> token_expires_at AUSENTE
#         do arquivo (chave nem aparece), sem LEMBRETE em stdout
#   JCS-7 EOF no lugar da data de validade (stdin fecha logo apos o token,
#         sem 3a linha) -> mesmo efeito de JCS-6 (opcional, nunca fatal)
#   JCS-8 token nunca aparece em texto de LEMBRETE (so a data, nunca o
#         segredo)

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk-jira/skills/jira-setup/scripts/jira-credential-setup.sh"

_cred_file() {
  printf '%s\n' "$TMPDIR_TEST/xdg/cstk-jira/credentials"
}

# _write_input EMAIL TOKEN [EXPIRES_AT] -> grava $TMPDIR_TEST/in.txt com as
# linhas de stdin que o script espera (EXPIRES_AT omitido = 2 linhas so,
# simulando EOF antes da 3a pergunta).
_write_input() {
  if [ "$#" -ge 3 ]; then
    printf '%s\n%s\n%s\n' "$1" "$2" "$3" > "$TMPDIR_TEST/in.txt"
  else
    printf '%s\n%s\n' "$1" "$2" > "$TMPDIR_TEST/in.txt"
  fi
}

scenario_site_host_invalido_exit1_nada_escrito() {
  cd "$TMPDIR_TEST" || return 1
  _write_input "tester@example.com" "tok-FAKE-000" ""
  XDG_CONFIG_HOME="$TMPDIR_TEST/xdg" assert_exit 1 "$SCRIPT" 'https://nope' \
    < "$TMPDIR_TEST/in.txt" || return 1
  [ ! -e "$(_cred_file)" ] \
    || { _fail "no_file_on_invalid_host" "credencial nao deveria ter sido gravada"; return 1; }
}

scenario_argumentos_errados_exit1() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 1 "$SCRIPT" || return 1
  assert_exit 1 "$SCRIPT" host1 host2 || return 1
}

scenario_email_vazio_exit1_nada_escrito() {
  cd "$TMPDIR_TEST" || return 1
  _write_input "" "tok-FAKE-000" ""
  XDG_CONFIG_HOME="$TMPDIR_TEST/xdg" assert_exit 1 "$SCRIPT" example.atlassian.net \
    < "$TMPDIR_TEST/in.txt" || return 1
  assert_stderr_contains "email vazio" || return 1
  [ ! -e "$(_cred_file)" ] \
    || { _fail "no_file_on_empty_email" "credencial nao deveria ter sido gravada"; return 1; }
}

scenario_api_token_vazio_exit1_nada_escrito() {
  cd "$TMPDIR_TEST" || return 1
  _write_input "tester@example.com" "" ""
  XDG_CONFIG_HOME="$TMPDIR_TEST/xdg" assert_exit 1 "$SCRIPT" example.atlassian.net \
    < "$TMPDIR_TEST/in.txt" || return 1
  assert_stderr_contains "api_token vazio" || return 1
  [ ! -e "$(_cred_file)" ] \
    || { _fail "no_file_on_empty_token" "credencial nao deveria ter sido gravada"; return 1; }
}

scenario_validade_informada_grava_e_ecoa_lembrete() {
  cd "$TMPDIR_TEST" || return 1
  _write_input "tester@example.com" "tok-FAKE-000" "2027-03-15"
  XDG_CONFIG_HOME="$TMPDIR_TEST/xdg" assert_exit 0 "$SCRIPT" example.atlassian.net \
    < "$TMPDIR_TEST/in.txt" || return 1
  assert_stdout_contains "LEMBRETE" || return 1
  assert_stdout_contains "2027-03-15" || return 1
  if printf '%s' "$_CAPTURED_STDOUT" | grep -qF "tok-FAKE-000"; then
    _fail "token_in_stdout" "api_token nao deveria aparecer em stdout"
    return 1
  fi
  [ -f "$(_cred_file)" ] \
    || { _fail "cred_file_missing" "arquivo de credencial nao foi gravado"; return 1; }
  grep -q '^token_expires_at=2027-03-15$' "$(_cred_file)" \
    || { _fail "token_expires_at_missing" "token_expires_at nao foi gravado com o valor esperado"; return 1; }
  _modo=$(stat -f '%Lp' "$(_cred_file)" 2>/dev/null || stat -c '%a' "$(_cred_file)" 2>/dev/null)
  [ "$_modo" = "600" ] || { _fail "modo" "esperado 600, obtido '$_modo'"; return 1; }
}

scenario_validade_em_branco_nao_grava_chave() {
  cd "$TMPDIR_TEST" || return 1
  _write_input "tester@example.com" "tok-FAKE-000" ""
  XDG_CONFIG_HOME="$TMPDIR_TEST/xdg" assert_exit 0 "$SCRIPT" example.atlassian.net \
    < "$TMPDIR_TEST/in.txt" || return 1
  assert_stdout_not_contains "LEMBRETE" || return 1
  if grep -q '^token_expires_at=' "$(_cred_file)"; then
    _fail "token_expires_at_present" "token_expires_at nao deveria existir sem data informada"
    return 1
  fi
  grep -q '^email=tester@example.com$' "$(_cred_file)" \
    || { _fail "email_missing" "email nao foi gravado"; return 1; }
}

scenario_validade_eof_equivale_a_branco() {
  cd "$TMPDIR_TEST" || return 1
  # Sem 3a linha (nem vazia): stdin fecha logo apos o token — EOF, nao erro.
  _write_input "tester@example.com" "tok-FAKE-000"
  XDG_CONFIG_HOME="$TMPDIR_TEST/xdg" assert_exit 0 "$SCRIPT" example.atlassian.net \
    < "$TMPDIR_TEST/in.txt" || return 1
  if grep -q '^token_expires_at=' "$(_cred_file)"; then
    _fail "token_expires_at_present_on_eof" "EOF deveria equivaler a pular o campo"
    return 1
  fi
  grep -q '^api_token=tok-FAKE-000$' "$(_cred_file)" \
    || { _fail "api_token_missing" "api_token nao foi gravado"; return 1; }
}

run_all_scenarios
