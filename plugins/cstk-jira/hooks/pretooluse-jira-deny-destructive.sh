#!/bin/sh
# pretooluse-jira-deny-destructive.sh — hook PreToolUse do plugin cstk-jira:
# guarda de exclusao via Rovo MCP (FR-012) + guarda de criacao de projeto
# via Rovo MCP em execucao autonoma (r02 FASE 19 tarefa 19.2, FR-024).
#
# Ref: docs/specs/cstk-jira/contracts/hooks.md "Comportamento de
#      pretooluse-jira-deny-destructive.sh"; contracts/rovo-mcp.md
#      "Tools proibidas"; tasks.md 5.2, 19.2; plan.md SEC-7.
#
# Dois MODOS, escolhidos pelo tool_name casado (secao 2):
#
#   destructive (deleteJiraIssue/executeDestructive, FR-012): casou o
#   matcher E o plugin esta configurado => mensagem em stderr citando
#   FR-012 e `exit 2` (o UNICO exit code que bloqueia a tool por si so —
#   hooks-guide, ver contracts/hooks.md linha "Fontes"), SEMPRE — nao
#   depende de execucao 00c ativa (o Rovo MCP nunca deve apagar issue,
#   nem em sessao interativa).
#
#   project-create (createJiraProject, r02 FASE 19, FR-024): SO nega
#   (exit 2) quando HA execucao 00c ATIVA no cwd (mesma deteccao de
#   `.lock` de hooks/posttooluse-jira-sync.sh secao 2) E o plugin esta
#   configurado — sessao interativa PURA (sem execucao ativa) NUNCA e
#   bloqueada aqui: o gate e o prompt de permissao do Claude Code + a
#   confirmacao da propria skill `jira-setup` (--confirm-key). Isto e
#   uma DUPLA condicao deliberada (nunca uma unica variavel combinada) —
#   ver mutation test 19.2.4.
#
# Sem `<cwd>/.claude/cstk-jira/config` os DOIS modos sao no-op (exit 0):
# quem instalou o plugin mas nunca o configurou pode estar usando o Rovo
# MCP para outros fins fora do escopo do plugin, e mudar o comportamento
# para essas pessoas seria vedado por FR-017/SC-006.
#
# hooks.json ja restringe a invocacao deste script aos matchers
# `mcp__.*__(deleteJiraIssue|executeDestructive)` e
# `mcp__.*__createJiraProject` (harness casa a regex contra tool_name
# antes de rodar QUALQUER hook do array). A checagem de tool_name feita
# aqui dentro (secao 2) e defesa redundante — mesmo idioma de "erros do
# proprio contrato" usado por
# plugins/cstk/skills/agente-00c-runtime/hooks/pretooluse-bash-guard.sh —
# nunca confia sozinha no matcher externo.
#
# Defesa em profundidade complementar (5.2.4, CHK010): mesmo que este hook
# falhe ou seja removido, plugins/cstk-jira/scripts/jira-io.sh nao tem
# metodo DELETE — allowlist FECHADA GET/POST/PUT (_ji_method_allowed); e
# `jira-setup.sh create-project` (r02 FASE 19) exige consentimento
# verificavel (SEC-9) para R18 independente deste hook. Multiplos pontos
# de enforcement independentes para o mesmo requisito.
#
# POSIX sh, SEM jq/cliente HTTP neste arquivo (carve-out 1.1.0 do Principio
# II, condicao b: so plugins/cstk-jira/scripts/jira-io.sh referencia essas
# ferramentas). Extracao de campos JSON via grep/sed puros, mesmo idioma de
# posttooluse-jira-sync.sh::_pjs_json_str.
#
# NAO-EXFILTRACAO: tool_input de deleteJiraIssue/executeDestructive/
# createJiraProject pode carregar identificadores/nome do projeto-alvo;
# este script NUNCA loga o tool_input inteiro — a mensagem de stderr e um
# texto FIXO citando FR-012/FR-024, nunca eco do payload recebido.

set -u

# _pjd_json_str JSON KEY -> valor de um campo string simples
# ("key":"value"), 1a ocorrencia. Mesmo idioma de
# posttooluse-jira-sync.sh::_pjs_json_str.
_pjd_json_str() {
  printf '%s\n' "$1" | tr -d '\n' \
    | sed -n 's/.*"'"$2"'"[ 	]*:[ 	]*"\([^"]*\)".*/\1/p' | head -n 1
}

# _pjd_00c_active CWD -> exit 0 se ha PELO MENOS 1 execucao 00c ativa no
# cwd (r02 FASE 19 tarefa 19.2.2): mesma deteccao de `.lock` de
# hooks/posttooluse-jira-sync.sh secao 2 — `.claude/feature-00c-state/
# <short>/.lock` (qualquer feature) OU `.claude/agente-00c-state/.lock`.
# Diferente do hook de sync, aqui NAO precisamos resolver a feature nem
# exigir exatamente 1 candidato (a guarda so precisa saber SE ha execucao
# ativa, nao QUAL) — 1+ candidatos conta como "ativa".
_pjd_00c_active() {
  _pjda_cwd="$1"
  if [ -d "$_pjda_cwd/.claude/feature-00c-state" ]; then
    for _pjda_d in "$_pjda_cwd"/.claude/feature-00c-state/*/; do
      [ -d "$_pjda_d" ] || continue
      [ -d "${_pjda_d}.lock" ] && return 0
    done
  fi
  [ -d "$_pjda_cwd/.claude/agente-00c-state/.lock" ] && return 0
  return 1
}

_PJD_INPUT=$(cat 2>/dev/null) || exit 0
[ -n "$_PJD_INPUT" ] || exit 0

# ==== 1. Ler tool_name + cwd (contrato do harness) ====

_PJD_TOOL_NAME=$(_pjd_json_str "$_PJD_INPUT" tool_name)
_PJD_CWD=$(_pjd_json_str "$_PJD_INPUT" cwd)
[ -n "$_PJD_CWD" ] || exit 0
[ -d "$_PJD_CWD" ] || exit 0

# ==== 2. Defesa redundante do matcher (5.2.1) — decide o MODO ====
# Casa qualquer prefixo de instalacao do Rovo MCP (research Decision 1) —
# mcp__<QUALQUER-COISA>__<tool>.

case "$_PJD_TOOL_NAME" in
  mcp__*__deleteJiraIssue | mcp__*__executeDestructive) _PJD_MODE="destructive" ;;
  mcp__*__createJiraProject) _PJD_MODE="project-create" ;;
  *) exit 0 ;;
esac

# ==== 3. No-op de inatividade (5.2.3/19.2.2, FR-017/SC-006) ====
# Sem config, o Rovo MCP pode estar em uso fora do escopo do plugin — nao
# mudar comportamento para quem nunca configurou a integracao. Aplicavel
# aos DOIS modos.

_PJD_CONFIG="$_PJD_CWD/.claude/cstk-jira/config"
[ -f "$_PJD_CONFIG" ] || exit 0

# ==== 4. Bloqueio, por modo ====

if [ "$_PJD_MODE" = "project-create" ]; then
  # r02 FASE 19 tarefa 19.2.2 (FR-024, SEC-7): DUPLA condicao explicita
  # (execucao ativa E config presente, secao 3 acima) — nega SO quando as
  # DUAS se sustentam; mutation test 19.2.4 confirma que remover a
  # combinacao (negar so por execucao ativa) faz o cenario "execucao
  # ativa sem config" falhar.
  if _pjd_00c_active "$_PJD_CWD"; then
    printf 'cstk-jira: criacao de projeto via Rovo MCP bloqueada (FR-024) — tool "%s" nao e permitida durante execucao 00c ativa. Use "jira-setup.sh create-project --consent-block block-NNN" (gate humano verificavel, SEC-9) em vez do Rovo MCP direto.\n' \
      "$_PJD_TOOL_NAME" >&2
    exit 2
  fi
  exit 0
fi

# modo destructive (5.2.2)
printf 'cstk-jira: exclusao via Rovo MCP bloqueada (FR-012) — tool "%s" nao e permitida. O sistema nao apaga automaticamente cards do Jira; divergencias (card orfao) exigem decisao humana em vez de exclusao.\n' \
  "$_PJD_TOOL_NAME" >&2
exit 2
