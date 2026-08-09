#!/bin/sh
# _resolve-root.sh — helper sourceable de resolucao dual-path da raiz de
# `agente-00c-runtime`, agnostico ao caminho de distribuicao (classico via
# `~/.claude/skills` OU plugin nativo do Claude Code via
# `${CLAUDE_PLUGIN_ROOT}`). Feature `claude-plugin-packaging`.
#
# Ref: docs/specs/_archived/2026-08-08-claude-plugin-packaging/contracts/plugin-artifacts.md
#      Artefato 5 (interface, ordens de precedencia, politica de falha)
#      docs/specs/_archived/2026-08-08-claude-plugin-packaging/research.md Decision 3
#      spec.md FR-009, FR-012
#
# NAO e executavel diretamente. Consumidores sourceiam este arquivo e
# chamam `resolve_runtime_root [strict]`:
#
#   . "$_helper"
#   _root=$(resolve_runtime_root) || { <tratar falha>; }
#
# Interface (contrato, Artefato 5):
#   resolve_runtime_root [strict] -> stdout = path absoluto da raiz de
#     `agente-00c-runtime`; exit 0.
#   Falha -> stdout vazio; stderr = diagnostico listando os candidatos
#     tentados (FR-012); exit 1.
#
# Candidato so e aceito se o diretorio EXISTIR e conter `scripts/`
# (contrato do Artefato 5) — evita aceitar uma raiz incompleta/parcial.
#
# Duas ordens de precedencia, por criticidade do consumidor (Artefato 5):
#
#   Ordem A (default, consumidores gerais — hooks de metrica, CLIs do
#   runtime): ${CLAUDE_PLUGIN_ROOT}/skills/agente-00c-runtime ->
#   diretorio-irmao de $0 -> $HOME/.claude/skills/agente-00c-runtime ->
#   erro diagnostico.
#
#   Ordem B (`strict`, consumidor fail-CLOSED — pretooluse-bash-guard.sh):
#   diretorio-irmao de $0 PRIMEIRO (ancora mais forte: o proprio processo
#   foi lancado pelo harness a partir de um path ja resolvido) ->
#   ${CLAUDE_PLUGIN_ROOT}/... -> $HOME/.claude/skills/... -> erro. A
#   inversao evita que uma variavel de ambiente exportada por um processo
#   pai (fora do controle do harness) redirecione o guard para um
#   `bash-guard.sh` permissivo sem disparar erro (achado de seguranca F3,
#   MEDIUM, dec-027) — ver Artefato 5 para o detalhamento da ameaca.
#
# "Diretorio-irmao de $0": os consumidores deste helper (hooks) residem em
# `agente-00c-runtime/hooks/<script>.sh`; a raiz do runtime e o diretorio
# PAI de `hooks/` — logo `dirname "$0"/..` aponta exatamente para a raiz
# de `agente-00c-runtime`, seja ela `plugins/cstk/skills/agente-00c-runtime`
# (hoje) ou `plugins/cstk/skills/agente-00c-runtime` (apos a relocacao da
# FASE 4 desta feature — o `git mv` de todo `plugins/cstk/skills/` carrega este
# arquivo junto, sem exigir nenhuma edicao).
#
# `$0` funciona aqui porque este arquivo e SEMPRE sourceado (nunca
# executado como script proprio) por um consumidor POSIX sh puro
# (`#!/bin/sh`) — em `sh`/`dash` (ao contrario de `bash`), `$0` dentro de
# um arquivo sourceado continua sendo o `$0` do processo CHAMADOR, nao
# deste arquivo. Isso e o proprio mecanismo que torna a deteccao de
# "diretorio-irmao do script chamador" possivel sem um segundo parametro.

# _rr_valid_root DIR -> 0 se DIR existe e contem `scripts/` (contrato do
# Artefato 5); 1 caso contrario. Nunca falha por DIR vazio (retorna 1).
_rr_valid_root() {
  [ -n "$1" ] || return 1
  [ -d "$1" ] || return 1
  [ -d "$1/scripts" ] || return 1
  return 0
}

# _rr_normalize DIR -> stdout = path absoluto normalizado de DIR (via
# `cd`+`pwd`). So chamado apos `_rr_valid_root` confirmar que DIR existe —
# `cd` nao deve falhar aqui, mas o resultado e ignorado silenciosamente
# (stdout vazio) se falhar por qualquer razao externa (permissao, etc).
_rr_normalize() {
  (cd "$1" 2>/dev/null && pwd)
}

# _rr_sibling_root SCRIPT_PATH -> stdout = path absoluto do diretorio-irmao
# (pai de `dirname SCRIPT_PATH`) se existir; vazio caso contrario. Nunca
# aplica `_rr_valid_root` aqui — a validacao de conteudo (`scripts/`)
# acontece no chamador, uniformemente para todos os candidatos.
_rr_sibling_root() {
  _rr_sr_script="$1"
  [ -n "$_rr_sr_script" ] || return 0
  _rr_sr_hooks_dir=$(dirname "$_rr_sr_script" 2>/dev/null) || return 0
  [ -n "$_rr_sr_hooks_dir" ] || return 0
  _rr_sr_candidate="$_rr_sr_hooks_dir/.."
  [ -d "$_rr_sr_candidate" ] || return 0
  _rr_normalize "$_rr_sr_candidate"
}

# resolve_runtime_root [strict] -> ver contrato no cabecalho deste arquivo.
resolve_runtime_root() {
  _rr_mode="${1:-}"
  _rr_tried=""

  if [ "$_rr_mode" = "strict" ]; then
    _rr_order="sibling plugin classic"
  else
    _rr_order="plugin sibling classic"
  fi

  for _rr_cand in $_rr_order; do
    case "$_rr_cand" in
      plugin)
        if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
          _rr_dir="${CLAUDE_PLUGIN_ROOT}/skills/agente-00c-runtime"
          if _rr_valid_root "$_rr_dir"; then
            _rr_normalize "$_rr_dir"
            return 0
          fi
          _rr_tried="${_rr_tried}  - \${CLAUDE_PLUGIN_ROOT}/skills/agente-00c-runtime -> ${_rr_dir} (invalido: ausente ou sem scripts/)
"
        else
          _rr_tried="${_rr_tried}  - \${CLAUDE_PLUGIN_ROOT}/skills/agente-00c-runtime -> CLAUDE_PLUGIN_ROOT indefinida
"
        fi
        ;;
      sibling)
        _rr_dir=$(_rr_sibling_root "$0")
        if [ -n "$_rr_dir" ] && _rr_valid_root "$_rr_dir"; then
          _rr_normalize "$_rr_dir"
          return 0
        fi
        if [ -n "$_rr_dir" ]; then
          _rr_tried="${_rr_tried}  - diretorio-irmao de \$0 -> ${_rr_dir} (invalido: sem scripts/)
"
        else
          _rr_tried="${_rr_tried}  - diretorio-irmao de \$0 -> nao resolvido (\$0=${0:-<vazio>})
"
        fi
        ;;
      classic)
        if [ -n "${HOME:-}" ]; then
          _rr_dir="$HOME/.claude/skills/agente-00c-runtime"
          if _rr_valid_root "$_rr_dir"; then
            _rr_normalize "$_rr_dir"
            return 0
          fi
          _rr_tried="${_rr_tried}  - \$HOME/.claude/skills/agente-00c-runtime -> ${_rr_dir} (invalido: ausente ou sem scripts/)
"
        else
          _rr_tried="${_rr_tried}  - \$HOME/.claude/skills/agente-00c-runtime -> HOME indefinida
"
        fi
        ;;
    esac
  done

  printf 'resolve_runtime_root: nenhum candidato resolveu a raiz de agente-00c-runtime (modo=%s). Candidatos tentados:\n%s' \
    "${_rr_mode:-normal}" "$_rr_tried" >&2
  return 1
}
