#!/bin/sh
# pretooluse-jira-deny-destructive.sh — hook PreToolUse do plugin cstk-jira:
# guarda de exclusao via Rovo MCP (FR-012).
#
# Ref: docs/specs/cstk-jira/contracts/hooks.md "Comportamento de
#      pretooluse-jira-deny-destructive.sh"; contracts/rovo-mcp.md
#      "Tools proibidas"; tasks.md 5.2.
#
# Politica INVERSA a posttooluse-jira-sync.sh (guarda, nao metrica): casou
# o matcher => mensagem em stderr citando FR-012 e `exit 2` (o UNICO exit
# code que bloqueia a tool por si so — hooks-guide, ver contracts/hooks.md
# linha "Fontes"). Sem `<cwd>/.claude/cstk-jira/config` a guarda e no-op
# (exit 0): quem instalou o plugin mas nunca o configurou pode estar usando
# o Rovo MCP para outros fins fora do escopo do plugin, e bloquear exclusao
# ali seria mudanca de comportamento vedada por FR-017/SC-006.
#
# hooks.json ja restringe a invocacao deste script ao matcher
# `mcp__.*__(deleteJiraIssue|executeDestructive)` (harness casa a regex
# contra tool_name antes de rodar QUALQUER hook do array). A checagem de
# tool_name feita aqui dentro (secao 2) e defesa redundante — mesmo idioma
# de "erros do proprio contrato" usado por
# plugins/cstk/skills/agente-00c-runtime/hooks/pretooluse-bash-guard.sh —
# nunca confia sozinha no matcher externo.
#
# Defesa em profundidade complementar (5.2.4, CHK010): mesmo que este hook
# falhe ou seja removido, plugins/cstk-jira/scripts/jira-io.sh nao tem
# metodo DELETE — allowlist FECHADA GET/POST/PUT (_ji_method_allowed).
# Dois pontos de enforcement independentes para o mesmo requisito.
#
# POSIX sh, SEM jq/cliente HTTP neste arquivo (carve-out 1.1.0 do Principio
# II, condicao b: so plugins/cstk-jira/scripts/jira-io.sh referencia essas
# ferramentas). Extracao de campos JSON via grep/sed puros, mesmo idioma de
# posttooluse-jira-sync.sh::_pjs_json_str.
#
# NAO-EXFILTRACAO: tool_input de deleteJiraIssue/executeDestructive pode
# carregar identificadores da issue-alvo; este script NUNCA loga o
# tool_input inteiro — a mensagem de stderr e um texto FIXO citando FR-012,
# nunca eco do payload recebido.

set -u

# _pjd_json_str JSON KEY -> valor de um campo string simples
# ("key":"value"), 1a ocorrencia. Mesmo idioma de
# posttooluse-jira-sync.sh::_pjs_json_str.
_pjd_json_str() {
  printf '%s\n' "$1" | tr -d '\n' \
    | sed -n 's/.*"'"$2"'"[ 	]*:[ 	]*"\([^"]*\)".*/\1/p' | head -n 1
}

_PJD_INPUT=$(cat 2>/dev/null) || exit 0
[ -n "$_PJD_INPUT" ] || exit 0

# ==== 1. Ler tool_name + cwd (contrato do harness) ====

_PJD_TOOL_NAME=$(_pjd_json_str "$_PJD_INPUT" tool_name)
_PJD_CWD=$(_pjd_json_str "$_PJD_INPUT" cwd)
[ -n "$_PJD_CWD" ] || exit 0
[ -d "$_PJD_CWD" ] || exit 0

# ==== 2. Defesa redundante do matcher (5.2.1) ====
# Casa qualquer prefixo de instalacao do Rovo MCP (research Decision 1) —
# mcp__<QUALQUER-COISA>__deleteJiraIssue ou mcp__<QUALQUER-COISA>__executeDestructive.

case "$_PJD_TOOL_NAME" in
  mcp__*__deleteJiraIssue | mcp__*__executeDestructive) ;;
  *) exit 0 ;;
esac

# ==== 3. No-op de inatividade (5.2.3, FR-017/SC-006) ====
# Sem config, o Rovo MCP pode estar em uso fora do escopo do plugin — nao
# mudar comportamento para quem nunca configurou a integracao.

_PJD_CONFIG="$_PJD_CWD/.claude/cstk-jira/config"
[ -f "$_PJD_CONFIG" ] || exit 0

# ==== 4. Bloqueio (5.2.2) ====

printf 'cstk-jira: exclusao via Rovo MCP bloqueada (FR-012) — tool "%s" nao e permitida. O sistema nao apaga automaticamente cards do Jira; divergencias (card orfao) exigem decisao humana em vez de exclusao.\n' \
  "$_PJD_TOOL_NAME" >&2
exit 2
