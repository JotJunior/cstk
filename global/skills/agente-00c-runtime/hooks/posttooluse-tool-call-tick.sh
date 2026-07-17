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
# state ilegivel, append negado) = exit 0 silencioso, stdout vazio. Este
# hook NUNCA bloqueia, atrasa ou interfere numa tool call. Por isso NAO usa
# `set -e` (um erro nao tratado viraria exit != 0 e o harness exporia stderr
# ao usuario); cada passo trata a propria falha com no-op.
#
# REGRA DURA — NAO tocar o state.json: PostToolUse dispara CONCORRENTE as
# tool calls do orquestrador (batches paralelos do harness). Um
# read-modify-write do state.json aqui (como faz `tool-call-tick`) poderia
# clobberar um write transacional (Decisao/bloqueio/onda) gravado entre o
# read e o `mv` do tick. O state.json e a fonte de verdade transacional;
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
# Deteccao de execucao ativa: mesmo algoritmo e precedencia do
# pretooluse-bash-guard.sh (agente-00c vence; entre feature-00c, menor
# short-name lexicografico byte-wise; status em_andamento|aguardando_humano).
# Fora de execucao ativa: exit 0, zero interferencia na sessao manual.
#
# jq: mesma dependencia OPCIONAL confinada dos hooks (Constitution 1.1.0
# Principio II carve-out). Sem jq nao ha parsing seguro do stdin -> no-op
# (fail-open; no guard e fail-closed — la a falta de validacao bloqueia,
# aqui a falta de metrica so subconta).

set -u

command -v jq >/dev/null 2>&1 || exit 0

_PTT_INPUT=$(cat 2>/dev/null) || exit 0
[ -n "$_PTT_INPUT" ] || exit 0

_PTT_CWD=$(printf '%s' "$_PTT_INPUT" | jq -r '.cwd // ""' 2>/dev/null) || exit 0
_PTT_TOOL_NAME=$(printf '%s' "$_PTT_INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || exit 0

[ -n "$_PTT_CWD" ] || exit 0
# tool_name vazio = payload anomalo do harness; nao inventa tick.
[ -n "$_PTT_TOOL_NAME" ] || exit 0

_ptt_is_active_status() {
  case "$1" in
    em_andamento | aguardando_humano) return 0 ;;
    *) return 1 ;;
  esac
}

# Deteccao de execucao ativa (precedencia identica ao pretooluse-bash-guard.sh).
_PTT_STATE_DIR=""

_ptt_agente_state="$_PTT_CWD/.claude/agente-00c-state/state.json"
if [ -f "$_ptt_agente_state" ]; then
  _ptt_status=$(jq -r '.execution.status // ""' "$_ptt_agente_state" 2>/dev/null) || _ptt_status=""
  if _ptt_is_active_status "$_ptt_status"; then
    _PTT_STATE_DIR="$_PTT_CWD/.claude/agente-00c-state"
  fi
fi

if [ -z "$_PTT_STATE_DIR" ]; then
  _ptt_feat_root="$_PTT_CWD/.claude/feature-00c-state"
  if [ -d "$_ptt_feat_root" ]; then
    _ptt_active_shorts=""
    for _ptt_d in "$_ptt_feat_root"/*/; do
      [ -d "$_ptt_d" ] || continue
      [ -f "${_ptt_d}state.json" ] || continue
      _ptt_status=$(jq -r '.execution.status // ""' "${_ptt_d}state.json" 2>/dev/null) || continue
      _ptt_is_active_status "$_ptt_status" || continue
      _ptt_active_shorts="${_ptt_active_shorts}$(basename "$_ptt_d")
"
    done
    if [ -n "$_ptt_active_shorts" ]; then
      # Ordem lexicografica byte-wise (C locale), deterministica — mesma
      # regra do guard (CHK007/enforced-guards data-model.md).
      _ptt_first=$(printf '%s' "$_ptt_active_shorts" | LC_ALL=C sort | sed -n '1p')
      _PTT_STATE_DIR="$_ptt_feat_root/$_ptt_first"
    fi
  fi
fi

# Fora de escopo: nenhuma execucao ativa -> zero interferencia.
[ -n "$_PTT_STATE_DIR" ] || exit 0

_ptt_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || _ptt_ts="tick"
printf '%s\n' "$_ptt_ts" >> "$_PTT_STATE_DIR/tool-call-ticks.log" 2>/dev/null || :

exit 0
