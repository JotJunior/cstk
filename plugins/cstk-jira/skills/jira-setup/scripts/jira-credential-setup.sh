#!/bin/sh
# jira-credential-setup.sh — comando concreto que a skill `jira-setup`
# EXIBE (nunca executa) para o operador rodar em um TERMINAL PROPRIO,
# fora do chat do Claude Code (data-model.md Entity Credential: "Nunca e
# digitado no chat... entraria no transcript"; quickstart.md Cenario 3
# passo 2; checklists/ux.md CHK003).
#
# Ref: docs/specs/cstk-jira/data-model.md Entity Credential; contracts/
#      plugin-scripts.md `jira-config.sh credential-check`; tasks.md
#      6.1.2/6.1.6.
#
# Uso:
#   sh jira-credential-setup.sh <site_host>
#
# <site_host> e o MESMO valor ja gravado como ProjectConfig.site_host
# (ex.: minhaempresa.atlassian.net) — passado como argumento porque NAO e
# segredo. Email e API token sao pedidos interativamente (eco desligado
# para o token) e NUNCA aceitos por argumento de linha de comando (SEC-4 /
# data-model.md: credencial nunca em argv de processo).
#
# Grava ${XDG_CONFIG_HOME:-$HOME/.config}/cstk-jira/credentials no formato
# key=value (mesmo parser de jira-config.sh): site_host, email, api_token.
# Diretorio criado com 0700, arquivo com 0600 (data-model.md "MUST").
# Escrita atomica (temp file + mv na mesma particao) — uma falha a meio do
# processo nunca deixa um arquivo de credencial parcialmente escrito no
# caminho final.
#
# Este script NAO faz nenhuma chamada de rede — so grava o arquivo local.
# A validacao remota (GET /rest/api/3/myself) e feita pela skill, depois,
# via `jira-io.sh request GET /rest/api/3/myself`.
#
# POSIX sh, sem bash-isms (`read -s` NAO e POSIX — eco desligado via `stty`,
# portavel em qualquer terminal real; `stty` ausente/nao-tty faz fallback
# silencioso para leitura visivel, avisado ao operador).

set -eu

_JCS_NAME="jira-credential-setup"

_jcs_die() { printf '%s: %s\n' "$_JCS_NAME" "$1" >&2; exit 1; }

[ "$#" -eq 1 ] || _jcs_die "uso: sh jira-credential-setup.sh <site_host>"
_JCS_SITE_HOST="$1"

case "$_JCS_SITE_HOST" in
  *[!A-Za-z0-9.-]*|'')
    _jcs_die "site_host invalido (esperado hostname puro, ex.: minhaempresa.atlassian.net): $_JCS_SITE_HOST"
    ;;
esac

_JCS_CRED_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/cstk-jira"
_JCS_CRED_FILE="$_JCS_CRED_DIR/credentials"

printf 'cstk-jira — configuracao de credencial (site: %s)\n' "$_JCS_SITE_HOST"
printf 'O token NUNCA e mostrado na tela. Gere um API token classico em:\n'
printf '  https://id.atlassian.com/manage-profile/security/api-tokens\n\n'

printf 'Email da conta Atlassian: '
IFS= read -r _jcs_email
[ -n "$_jcs_email" ] || _jcs_die "email vazio"

# Eco desligado so para o token (stty -echo). Sem tty (pipe/CI) ou sem
# `stty`, cai em leitura visivel — aviso explicito, nunca falha silenciosa.
if [ -t 0 ] && command -v stty >/dev/null 2>&1; then
  _jcs_saved_stty=$(stty -g 2>/dev/null) || _jcs_saved_stty=""
  printf 'API token (nao sera exibido): '
  stty -echo 2>/dev/null || :
  IFS= read -r _jcs_token
  [ -n "$_jcs_saved_stty" ] && stty "$_jcs_saved_stty" 2>/dev/null || stty echo 2>/dev/null || :
  printf '\n'
else
  printf 'AVISO: terminal sem suporte a eco desligado — o token ficara visivel ao digitar.\n'
  printf 'API token: '
  IFS= read -r _jcs_token
fi
[ -n "$_jcs_token" ] || _jcs_die "api_token vazio"

umask 077
mkdir -p "$_JCS_CRED_DIR"
chmod 700 "$_JCS_CRED_DIR"

_jcs_tmp="$_JCS_CRED_DIR/.credentials.tmp.$$"
trap 'rm -f "$_jcs_tmp" 2>/dev/null || :' EXIT INT TERM
: > "$_jcs_tmp"
chmod 600 "$_jcs_tmp"
{
  printf 'site_host=%s\n' "$_JCS_SITE_HOST"
  printf 'email=%s\n' "$_jcs_email"
  printf 'api_token=%s\n' "$_jcs_token"
} > "$_jcs_tmp"
mv "$_jcs_tmp" "$_JCS_CRED_FILE"
trap - EXIT INT TERM

printf '\nCredencial gravada em %s (modo 0600).\n' "$_JCS_CRED_FILE"
printf 'Volte para a sessao do Claude Code e diga que a credencial foi configurada\n'
printf 'para a skill continuar (ela roda "jira-config.sh credential-check" para confirmar).\n'
