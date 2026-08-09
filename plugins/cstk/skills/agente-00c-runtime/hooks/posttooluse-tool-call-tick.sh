#!/bin/sh
# posttooluse-tool-call-tick.sh — hook PostToolUse (todas as tools): registra
# 1 tick de metrica de tool call por invocacao durante execucoes ativas
# agente-00c/feature-00c.
#
# Gap que fecha: `.budgets.tool_calls_current_wave` so avancava via
# `state-ondas.sh tool-call-tick`, que nenhum mecanismo automatico invocava —
# ondas fechavam com `tool_calls=0` apesar de dezenas de calls reais, e o
# proxy de custo do budget.sh (threshold tool_calls_threshold_wave) nunca
# tinha numero real para comparar. Prosa mandando o orquestrador tickar
# manualmente e mecanismo advisory — mesma classe de falha que motivou o
# pretooluse-bash-guard.sh (enforced-guards).
#
# POLITICA INVERSA ao pretooluse-bash-guard.sh: isto e METRICA, nao guarda.
# Fail-OPEN absoluto — qualquer falha (jq ausente, stdin invalido/vazio,
# state ilegivel, backend indeterminado, append negado) = exit 0 silencioso,
# stdout vazio. Este hook NUNCA bloqueia, atrasa ou interfere numa tool call.
# Por isso NAO usa `set -e` (um erro nao tratado viraria exit != 0 e o
# harness exporia stderr ao usuario); cada passo trata a propria falha com
# no-op.
#
# REGRA DURA — NAO tocar o state.json/state.db: PostToolUse dispara
# CONCORRENTE as tool calls do orquestrador (batches paralelos do harness).
# Um read-modify-write do state aqui (como faz `tool-call-tick`) poderia
# clobberar um write transacional (Decisao/bloqueio/onda) gravado entre o
# read e o `mv`/commit do tick. O state e a fonte de verdade transacional;
# a metrica e derivada. O tick vai num SIDECAR append-only:
#
#   <state-dir>/tool-call-ticks.log   — 1 linha (timestamp ISO) por tick
#
# Append com O_APPEND e atomico para linhas curtas (< PIPE_BUF). Agregacao:
# `state-ondas.sh end` soma `wc -l` do sidecar ao campo do state no
# fechamento da onda; `budget.sh check|status` soma mid-onda. `start` e
# `end` resetam o sidecar (janela de contagem = start→end). Ticks na
# fronteira start/end podem se perder — aceitavel para proxy de custo.
#
# Deteccao de execucao ativa (feature hooks-db-parity, FASE 4): delegada ao
# helper agnostico a backend `_hook-active-exec.sh`
# (docs/specs/hooks-db-parity/contracts/hook-active-exec.md), substituindo a
# antiga leitura inline de `state.json` (unico backend suportado ate entao).
# Precondicionada por um pre-check inline com builtins puros (SEC-H1/
# spec.md FR-008) — mesma mitigacao do pretooluse-bash-guard.sh (task
# 3.1.1). So DEPOIS do pre-check o helper e resolvido com a ORDEM INVERTIDA
# (dec-026): `$HOME` antes de `<cwd>`.
#
# Politica de exit codes do helper — DIFERENTE do guard (fail-closed):
#   0 (ativa)        -> grava o tick no sidecar do state-dir resolvido.
#   1 (inativa)       -> no-op silencioso, exit 0 (paridade FR-006).
#   2/127 (indeterminada/helper irresolvivel) -> no-op silencioso, exit 0
#     (FR-004: aqui e METRICA, nunca guarda — a falta de certeza NUNCA vira
#     bloqueio, so subconta o proxy de custo).
#
# busy_timeout diferenciado (SEC-M2/task 1.6/CHK027): este hook usa 50ms
# (HAE_BUSY_TIMEOUT_MS=50), nao os 200ms tolerados pelo guard — orcamento de
# ~30ms deste hook de metrica nao pode ser consumido esperando contencao do
# SQLite; sob contencao, o helper retorna indeterminada e o tick e pulado
# (fail-open, nunca bloqueia).
#
# jq: mesma dependencia OPCIONAL confinada dos hooks (Constitution 1.1.0
# Principio II carve-out). Sem jq nao ha parsing seguro do stdin -> no-op
# (fail-open; no guard e fail-closed — la a falta de validacao bloqueia,
# aqui a falta de metrica so subconta).

set -u

_PTT_SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd) || _PTT_SELF_DIR=""
# Raiz do projeto-alvo, resolvida por _ptt_precheck_active_scope a partir
# do `.cwd` do payload (que pode estar num subdiretorio).
_PTT_SCOPE=""

# Bootstrap: localizar+sourcear `_resolve-root.sh` (feature
# claude-plugin-packaging, task 3.2.4). Ordem A (fail-open, consumidor
# geral) — ver mesmo bootstrap em posttooluse-loose-usage.sh. Falha aqui
# deixa `resolve_runtime_root` indefinida; tratado como candidato
# nao-resolvido pelos chamadores (fail-open, nunca aborta o hook).
_ptt_rr_helper=""
if [ -n "$_PTT_SELF_DIR" ] && [ -r "$_PTT_SELF_DIR/../scripts/_resolve-root.sh" ]; then
  _ptt_rr_helper="$_PTT_SELF_DIR/../scripts/_resolve-root.sh"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -r "${CLAUDE_PLUGIN_ROOT}/skills/agente-00c-runtime/scripts/_resolve-root.sh" ]; then
  _ptt_rr_helper="${CLAUDE_PLUGIN_ROOT}/skills/agente-00c-runtime/scripts/_resolve-root.sh"
elif [ -n "${HOME:-}" ] && [ -r "$HOME/.claude/skills/agente-00c-runtime/scripts/_resolve-root.sh" ]; then
  _ptt_rr_helper="$HOME/.claude/skills/agente-00c-runtime/scripts/_resolve-root.sh"
fi
if [ -n "$_ptt_rr_helper" ]; then
  # shellcheck disable=SC1090 # caminho resolvido dinamicamente pela cadeia de candidatos acima
  . "$_ptt_rr_helper"
fi

command -v jq >/dev/null 2>&1 || exit 0

_PTT_INPUT=$(cat 2>/dev/null) || exit 0
[ -n "$_PTT_INPUT" ] || exit 0

_PTT_CWD=$(printf '%s' "$_PTT_INPUT" | jq -r '.cwd // ""' 2>/dev/null) || exit 0
_PTT_TOOL_NAME=$(printf '%s' "$_PTT_INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || exit 0

[ -n "$_PTT_CWD" ] || exit 0
# tool_name vazio = payload anomalo do harness; nao inventa tick.
[ -n "$_PTT_TOOL_NAME" ] || exit 0

# _ptt_scope_has_state DIR -> 0 se DIR abriga o state de uma execucao 00c
# (`state.json` OU `state.db` sob `agente-00c-state/` ou
# `feature-00c-state/*/`). Usa EXCLUSIVAMENTE builtins do shell — nenhuma
# resolucao de dependencia nem sourcing acontece dentro nem antes desta
# checagem (SEC-H1, spec.md FR-008).
_ptt_scope_has_state() {
  _ptt_sh_dir=$1
  [ -n "$_ptt_sh_dir" ] || return 1

  _ptt_sh_agente="$_ptt_sh_dir/.claude/agente-00c-state"
  if [ -f "$_ptt_sh_agente/state.json" ] || [ -f "$_ptt_sh_agente/state.db" ]; then
    return 0
  fi

  _ptt_sh_froot="$_ptt_sh_dir/.claude/feature-00c-state"
  if [ -d "$_ptt_sh_froot" ]; then
    for _ptt_sh_d in "$_ptt_sh_froot"/*/; do
      [ -d "$_ptt_sh_d" ] || continue
      if [ -f "${_ptt_sh_d}state.json" ] || [ -f "${_ptt_sh_d}state.db" ]; then
        return 0
      fi
    done
  fi
  return 1
}

# _ptt_precheck_active_scope -> 0 assinalando `_PTT_SCOPE` com a RAIZ do
# projeto-alvo; 1 se nenhum candidato abriga state.
#
# MOTIVO (deriva de cwd): o `.cwd` do payload e o diretorio corrente do
# shell da sessao, nao a raiz do projeto — e ele gruda em qualquer
# subdiretorio assim que o agente roda `cd sub && ...` (o cwd do Bash
# persiste entre tool calls). Enquanto durar a deriva, TODO tick e
# descartado e a onda fecha com `tool_calls=0` apesar de dezenas de calls
# reais. Cadeia identica a do pretooluse-bash-guard.sh (mesma primitiva,
# mesma ordem, mesmas fronteiras) — ver o cabecalho de
# `_pbg_precheck_active_scope` para o racional de seguranca de manter
# `$CLAUDE_PROJECT_DIR` como ULTIMO candidato.
_ptt_precheck_active_scope() {
  if _ptt_scope_has_state "$_PTT_CWD"; then
    _PTT_SCOPE="$_PTT_CWD"
    return 0
  fi

  _ptt_pa_cur="$_PTT_CWD"
  _ptt_pa_depth=0
  while [ "$_ptt_pa_depth" -lt 16 ]; do
    if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ "$_ptt_pa_cur" = "$CLAUDE_PROJECT_DIR" ]; then
      break
    fi

    _ptt_pa_parent="${_ptt_pa_cur%/*}"
    [ -n "$_ptt_pa_parent" ] || _ptt_pa_parent="/"
    [ "$_ptt_pa_parent" = "$_ptt_pa_cur" ] && break
    _ptt_pa_cur="$_ptt_pa_parent"

    if _ptt_scope_has_state "$_ptt_pa_cur"; then
      _PTT_SCOPE="$_ptt_pa_cur"
      return 0
    fi

    [ -e "$_ptt_pa_cur/.git" ] && break
    [ "$_ptt_pa_cur" = "/" ] && break
    _ptt_pa_depth=$((_ptt_pa_depth + 1))
  done

  if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && _ptt_scope_has_state "$CLAUDE_PROJECT_DIR"; then
    _PTT_SCOPE="$CLAUDE_PROJECT_DIR"
    return 0
  fi

  return 1
}

# Pre-check inline: sem NENHUM state.json/state.db sob agente-00c-state/ ou
# feature-00c-state/*/, o hook sai 0 sem resolver nem sourcear coisa alguma
# (FR-006, 100% das sessoes manuais).
_ptt_precheck_active_scope || exit 0

# _ptt_resolve_dep_hae REL_PATH -> cadeia de resolucao para
# _hook-active-exec.sh com a ORDEM MODIFICADA exigida pelo contrato
# (contracts/hook-active-exec.md §"Ordem MODIFICADA para o helper (SEC-H1)
# [APROVADA — dec-026]"): $HOME (escopo global) ANTES de <cwd> (escopo
# project); teste `-r` (legivel), nao `-x` (helpers `_*.sh` do runtime nao
# sao executaveis). Paridade com _pbg_resolve_dep_hae do
# pretooluse-bash-guard.sh (task 3.1.1).
_ptt_resolve_dep_hae() {
  _ptt_rel=$1
  if [ -n "$_PTT_SELF_DIR" ] && [ -r "$_PTT_SELF_DIR/../$_ptt_rel" ]; then
    printf '%s' "$_PTT_SELF_DIR/../$_ptt_rel"
    return 0
  fi
  # Plugin/classico (Ordem A, dec-006/fail-open) via helper compartilhado
  # (feature claude-plugin-packaging, task 3.2.4).
  if _ptt_root=$(resolve_runtime_root 2>/dev/null) && [ -n "$_ptt_root" ] \
     && [ -r "$_ptt_root/$_ptt_rel" ]; then
    printf '%s' "$_ptt_root/$_ptt_rel"
    return 0
  fi
  if [ -n "${_PTT_SCOPE:-}" ] && [ -r "$_PTT_SCOPE/.claude/skills/agente-00c-runtime/$_ptt_rel" ]; then
    printf '%s' "$_PTT_SCOPE/.claude/skills/agente-00c-runtime/$_ptt_rel"
    return 0
  fi
  return 1
}

_PTT_HAE_HELPER=$(_ptt_resolve_dep_hae "scripts/_hook-active-exec.sh") || exit 0

# shellcheck disable=SC1090 # caminho resolvido dinamicamente pela cadeia de candidatos acima
. "$_PTT_HAE_HELPER"

# SEC-M2: hook de metrica tolera so 50ms de contencao (orcamento de ~30ms) —
# diferente dos 200ms tolerados pelo guard (task 1.6/contracts §SEC-M2).
HAE_BUSY_TIMEOUT_MS=50
export HAE_BUSY_TIMEOUT_MS

if _PTT_HAE_OUT=$(hook_active_exec "$_PTT_SCOPE"); then
  _PTT_HAE_RC=0
else
  _PTT_HAE_RC=$?
fi

# Fail-open: so o caso `0` (ativa) grava o tick. Inativa (1), indeterminada
# (2) e helper irresolvivel (convencao 127, ja tratado acima via `exit 0`)
# sao TODOS no-op silencioso — nunca stderr, nunca sidecar criado.
[ "$_PTT_HAE_RC" -eq 0 ] || exit 0

_PTT_STATE_DIR=$(printf '%s' "$_PTT_HAE_OUT" | cut -f2)
[ -n "$_PTT_STATE_DIR" ] || exit 0

_ptt_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || _ptt_ts="tick"
printf '%s\n' "$_ptt_ts" >> "$_PTT_STATE_DIR/tool-call-ticks.log" 2>/dev/null || :

exit 0
