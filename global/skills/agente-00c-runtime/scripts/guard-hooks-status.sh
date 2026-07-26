#!/bin/sh
# guard-hooks-status.sh — verifica se os hooks 00c estao provisionados no
# projeto-alvo (READ-ONLY, nunca escreve nada).
#
# PROBLEMA QUE ISTO RESOLVE
# -------------------------
# Os tres hooks do runtime 00c so chegam a um projeto-alvo via
# `apply_guard_hooks()` (cli/lib/hooks.sh), que roda EXCLUSIVAMENTE quando
# `cstk install`/`cstk update` e invocado com `--scope project` E com
# `agente-00c-runtime` na selecao. O default de ambos os comandos e
# `--scope global`, que pula o provisionamento por FR-009c.
#
# Consequencia observada em campo: projeto com 35 ondas 00c executadas e
# ZERO hooks em .claude/hooks/ —
#   - pretooluse-bash-guard.sh ausente  => a guarda fail-closed de Bash
#     (enforced-guards US1) nunca foi enforced; a execucao inteira rodou
#     sem a protecao que a doc afirma estar ativa. E o item GRAVE.
#   - posttooluse-tool-call-tick.sh ausente => tool_calls fica 0 em todas
#     as ondas (proxy de orcamento inutilizado).
#   - posttooluse-agent-usage.sh ausente => agent_usage/tokens ficam null.
#
# Como o `cstk install` roda no repo do cstk e nao no projeto-alvo, nao ha
# momento natural para avisar o operador la. O ponto de checagem correto e
# o inicio da execucao 00c, que ja esta DENTRO do projeto-alvo — dai este
# script, consumido pelos commands /agente-00c e /feature-00c.
#
# Subcomandos:
#   guard-hooks-status.sh check --projeto-alvo-path PATH [--quiet]
#       — stdout: uma linha TSV por hook:
#             <arquivo>\t<present|missing>\t<registered|unregistered>
#         "registered" = o basename aparece em <PAP>/.claude/settings.json
#         (o hook so roda de fato se estiver copiado E registrado).
#       — stderr: diagnostico + comando de remediacao (suprimido por --quiet).
#       — exit 0 se os 3 estao present+registered; 1 caso contrario.
#
#   guard-hooks-status.sh tick-mode --projeto-alvo-path PATH
#       — stdout: "hook" se posttooluse-tool-call-tick.sh esta ativo
#         (present+registered), senao "manual".
#         Consumido pelo orquestrador para decidir se chama
#         `state-ondas.sh tool-call-tick` na mao. A regra "NAO tickar
#         manualmente" so vale quando o hook existe — sem esta checagem o
#         default virava "nao ticka" e a metrica zerava em silencio.
#       — exit 0 sempre (0 = consulta respondida, nao veredito).
#
# Exit codes:
#   0  check: tudo provisionado | tick-mode: consulta respondida
#   1  check: pelo menos um hook ausente ou nao-registrado
#   2  uso incorreto
#
# READ-ONLY por construcao: nao copia hook, nao edita settings.json, nao
# toca state.json. Provisionar e trabalho do `cstk install --scope project`
# (unica fonte da regra); reimplementar a copia aqui duplicaria a regra em
# dois lugares — mesmo motivo pelo qual o hook PreToolUse delega a decisao
# a bash-guard.sh em vez de reimplementa-la.
#
# POSIX sh puro. Sem jq, sem sqlite3, sem rede.

set -eu

_GH_NAME="guard-hooks-status"

_gh_die_usage() { printf '%s: %s\n' "$_GH_NAME" "$1" >&2; exit 2; }
_gh_err()       { printf '%s: %s\n' "$_GH_NAME" "$1" >&2; }

# Os 3 hooks provisionados por apply_guard_hooks(). Ordem = a do
# settings.snippet.json (guard primeiro, metricas depois).
_GH_HOOKS='pretooluse-bash-guard.sh
posttooluse-tool-call-tick.sh
posttooluse-agent-usage.sh'

# _gh_present PAP HOOK -> 0 se o arquivo existe e e executavel
_gh_present() {
  [ -f "$1/.claude/hooks/$2" ] && [ -x "$1/.claude/hooks/$2" ]
}

# _gh_registered PAP HOOK -> 0 se o basename aparece no settings.json.
# Busca textual (grep -F) em vez de parse: o hook e registrado como
# fragmento de linha de comando ("$CLAUDE_PROJECT_DIR"/.claude/hooks/X.sh),
# entao a presenca do basename e condicao necessaria e suficiente na
# pratica — e mantem o script sem dependencia de jq (que pode faltar
# justamente no projeto-alvo mal provisionado que estamos diagnosticando).
_gh_registered() {
  _gh_settings="$1/.claude/settings.json"
  [ -f "$_gh_settings" ] || return 1
  grep -Fq -- "$2" "$_gh_settings" 2>/dev/null
}

_gh_cmd_check() {
  _pap=""
  _quiet=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --projeto-alvo-path) _pap=$2; shift 2 ;;
      --quiet)             _quiet=1; shift ;;
      *) _gh_die_usage "check: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_pap" ] || _gh_die_usage "check: --projeto-alvo-path obrigatorio"
  [ -d "$_pap" ] || _gh_die_usage "check: --projeto-alvo-path nao e diretorio: $_pap"

  _missing=0
  _guard_missing=0
  for _h in $_GH_HOOKS; do
    if _gh_present "$_pap" "$_h"; then
      _st_file="present"
    else
      _st_file="missing"
    fi
    if _gh_registered "$_pap" "$_h"; then
      _st_reg="registered"
    else
      _st_reg="unregistered"
    fi
    printf '%s\t%s\t%s\n' "$_h" "$_st_file" "$_st_reg"
    if [ "$_st_file" != "present" ] || [ "$_st_reg" != "registered" ]; then
      _missing=$((_missing + 1))
      [ "$_h" = "pretooluse-bash-guard.sh" ] && _guard_missing=1
    fi
  done

  [ "$_missing" -eq 0 ] && return 0

  if [ "$_quiet" = 0 ]; then
    _gh_err "$_missing de 3 hooks 00c NAO estao ativos em $_pap/.claude/"
    if [ "$_guard_missing" = 1 ]; then
      _gh_err "ATENCAO: pretooluse-bash-guard.sh inativo — a guarda fail-closed de Bash NAO esta enforced nesta execucao."
    fi
    _gh_err "Remediacao (rode NO PROJETO-ALVO, uma vez):"
    _gh_err "  cd $_pap && cstk install --scope project agente-00c-runtime"
    _gh_err "Sem isso: tool_calls fica 0 e agent_usage fica null em todas as ondas."
  fi
  return 1
}

_gh_cmd_tick_mode() {
  _pap=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --projeto-alvo-path) _pap=$2; shift 2 ;;
      *) _gh_die_usage "tick-mode: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_pap" ] || _gh_die_usage "tick-mode: --projeto-alvo-path obrigatorio"

  if _gh_present "$_pap" "posttooluse-tool-call-tick.sh" \
     && _gh_registered "$_pap" "posttooluse-tool-call-tick.sh"; then
    printf 'hook\n'
  else
    printf 'manual\n'
  fi
  return 0
}

# ---------- dispatch ----------

[ "$#" -gt 0 ] || _gh_die_usage "subcomando obrigatorio: check|tick-mode"

_gh_sub=$1
shift
case "$_gh_sub" in
  check)     _gh_cmd_check "$@" ;;
  tick-mode) _gh_cmd_tick_mode "$@" ;;
  -h|--help)
    cat >&2 <<'HELP'
guard-hooks-status.sh — hooks 00c provisionados no projeto-alvo? (READ-ONLY)

USO:
  guard-hooks-status.sh check     --projeto-alvo-path PATH [--quiet]
  guard-hooks-status.sh tick-mode --projeto-alvo-path PATH

check     TSV <hook>\t<present|missing>\t<registered|unregistered>;
          exit 0 se os 3 ativos, 1 caso contrario.
tick-mode "hook" ou "manual" — o orquestrador so ticka na mao em "manual".

Remediacao quando faltam: rodar NO PROJETO-ALVO
  cstk install --scope project agente-00c-runtime
HELP
    exit 2
    ;;
  *) _gh_die_usage "subcomando desconhecido: $_gh_sub" ;;
esac
