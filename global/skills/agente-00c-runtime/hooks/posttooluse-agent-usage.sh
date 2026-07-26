#!/bin/sh
# posttooluse-agent-usage.sh — hook PostToolUse (matcher "Agent"): captura
# metrica de uso de tokens/tool-uses/duracao de cada spawn de subagente
# durante execucoes ativas agente-00c/feature-00c.
#
# Gap que fecha: hoje nenhum mecanismo automatico registra quanto cada
# spawn (Skill(execute-task)/Agent) custou em tokens — a unica proxy de
# custo existente e `tool_calls` (posttooluse-tool-call-tick.sh), que nao
# distingue spawns caros de baratos. Este hook fecha esse gap com dado real
# do proprio harness (tool_response de PostToolUse/Agent), nunca estimado.
#
# POLITICA: mesma familia de posttooluse-tool-call-tick.sh — isto e
# METRICA, nao guarda. Fail-OPEN absoluto: qualquer falha (jq ausente,
# stdin invalido/vazio, state ilegivel, append negado) = exit 0 silencioso,
# stdout SEMPRE vazio. Este hook NUNCA bloqueia, atrasa ou interfere numa
# tool call. Por isso NAO usa `set -e` — cada passo trata a propria falha
# com no-op (contracts/hook-posttooluse-agent-usage.md §3).
#
# REGRA DURA — NAO tocar o state.json: mesma justificativa de
# posttooluse-tool-call-tick.sh:28-37 (PostToolUse dispara CONCORRENTE as
# tool calls do orquestrador; um read-modify-write aqui poderia clobberar
# um write transacional gravado entre o read e o `mv`). O dado vai num
# SIDECAR append-only:
#
#   <state-dir>/wave-agent-usage.jsonl  — 1 linha JSON (SpawnUsage) por spawn
#
# Append com O_APPEND e atomico para linhas curtas (< PIPE_BUF) — por isso
# a linha NUNCA inclui `content`/`prompt`/`description` (texto livre,
# tambem proibido por vazamento de segredo). Agregacao acontece em
# `state-ondas.sh end` (FASE 3); `start`/`end` resetam o sidecar (janela de
# contagem = start->end, mesmo ciclo do sidecar de ticks).
#
# Deteccao de execucao ativa: mesmo algoritmo e precedencia de
# pretooluse-bash-guard.sh / posttooluse-tool-call-tick.sh (agente-00c
# vence; entre feature-00c, menor short-name lexicografico byte-wise;
# status em_andamento|aguardando_humano). Fora de execucao ativa: exit 0,
# zero interferencia na sessao manual.
#
# Permissao do sidecar (CHK017, data-model.md §Sidecar): `umask 077` MUST
# ser aplicado antes do primeiro append de cada arquivo (a criacao so
# acontece no primeiro append; umask nao afeta arquivo ja existente). Um
# `chmod 600` best-effort apos cada append reforca a politica mesmo se o
# arquivo ja existia com permissao mais aberta (defesa em profundidade,
# nao falha nunca).
#
# Teto de linhas (CHK020, data-model.md §Teto de linhas): 500 linhas por
# onda (research.md Decision 5, numero magico deliberado). Ao atingir o
# teto, o append desta linha e pulado (fail-open, spawn nunca bloqueado) e
# um aviso e emitido em stderr **uma unica vez por onda**, guardado pelo
# arquivo-sentinela `<state-dir>/.wave-agent-usage-cap-warned` (criado
# aqui; removido no ciclo start/end de `state-ondas.sh`, FASE 3). Contrato
# §3 diz "MUST NOT escrever em stdout" — o aviso vai para stderr, nunca
# stdout (stdout permanece SEMPRE vazio, igual ao hook irmao).
#
# jq: mesma dependencia OPCIONAL confinada dos demais hooks (Constitution
# 1.1.0 Principio II carve-out). Sem jq nao ha parsing seguro do stdin ->
# no-op (fail-open).

set -u

_PAU_CAP_LINES=500

command -v jq >/dev/null 2>&1 || exit 0

_PAU_INPUT=$(cat 2>/dev/null) || exit 0
[ -n "$_PAU_INPUT" ] || exit 0

_PAU_CWD=$(printf '%s' "$_PAU_INPUT" | jq -r '.cwd // ""' 2>/dev/null) || exit 0
_PAU_TOOL_NAME=$(printf '%s' "$_PAU_INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || exit 0

[ -n "$_PAU_CWD" ] || exit 0
# Guarda defensiva mesmo com matcher "Agent" no settings.snippet.json
# (contracts/hook-posttooluse-agent-usage.md §1.2).
[ "$_PAU_TOOL_NAME" = "Agent" ] || exit 0

_pau_is_active_status() {
  case "$1" in
    em_andamento | aguardando_humano) return 0 ;;
    *) return 1 ;;
  esac
}

# Deteccao de execucao ativa (precedencia identica ao pretooluse-bash-guard.sh
# e ao posttooluse-tool-call-tick.sh — contrato §4, REUSO nao reimplementacao).
_PAU_STATE_DIR=""

_pau_agente_state="$_PAU_CWD/.claude/agente-00c-state/state.json"
if [ -f "$_pau_agente_state" ]; then
  _pau_status=$(jq -r '.execution.status // ""' "$_pau_agente_state" 2>/dev/null) || _pau_status=""
  if _pau_is_active_status "$_pau_status"; then
    _PAU_STATE_DIR="$_PAU_CWD/.claude/agente-00c-state"
  fi
fi

if [ -z "$_PAU_STATE_DIR" ]; then
  _pau_feat_root="$_PAU_CWD/.claude/feature-00c-state"
  if [ -d "$_pau_feat_root" ]; then
    _pau_active_shorts=""
    for _pau_d in "$_pau_feat_root"/*/; do
      [ -d "$_pau_d" ] || continue
      [ -f "${_pau_d}state.json" ] || continue
      _pau_status=$(jq -r '.execution.status // ""' "${_pau_d}state.json" 2>/dev/null) || continue
      _pau_is_active_status "$_pau_status" || continue
      _pau_active_shorts="${_pau_active_shorts}$(basename "$_pau_d")
"
    done
    if [ -n "$_pau_active_shorts" ]; then
      # Ordem lexicografica byte-wise (C locale), deterministica — mesma
      # regra do guard e do hook de ticks.
      _pau_first=$(printf '%s' "$_pau_active_shorts" | LC_ALL=C sort | sed -n '1p')
      _PAU_STATE_DIR="$_pau_feat_root/$_pau_first"
    fi
  fi
fi

# Fora de escopo: nenhuma execucao ativa -> zero interferencia.
[ -n "$_PAU_STATE_DIR" ] || exit 0

_PAU_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || _PAU_TS="unknown"

# Monta a linha SpawnUsage inteira num unico jq (contracts/
# hook-posttooluse-agent-usage.md §2). `empty` quando nao ha `agentId`
# (tool_response ausente/malformado sem chave minima) -> sem linha
# (contrato §3: "exit 0 se nem agentId houver"). `status=indisponivel`
# MUST zerar (== null) todos os campos numericos, nunca 0 (FR-009).
_PAU_LINE=$(
  printf '%s' "$_PAU_INPUT" | jq -c --arg ts "$_PAU_TS" '
    (.tool_response // null) as $tr |
    (.tool_input // null) as $ti |
    (if $tr == null then null else ($tr.agentId // null) end) as $agent_id |
    if $agent_id == null then empty else
      (($tr.status // "")) as $status_raw |
      (if $status_raw == "completed" and ($tr.totalTokens != null) then "completo"
       elif $status_raw == "completed" then "parcial"
       else "indisponivel" end) as $derived |
      {
        agent_id: $agent_id,
        agent_type: (if $ti == null then null else ($ti.subagent_type // null) end),
        status: $derived,
        model: ($tr.resolvedModel // "nao-aplicavel"),
        models_used: ($tr.modelsUsed // null),
        total_tokens: (if $derived == "indisponivel" then null else ($tr.totalTokens // null) end),
        input_tokens: (if $derived == "indisponivel" then null else ($tr.usage.input_tokens // null) end),
        output_tokens: (if $derived == "indisponivel" then null else ($tr.usage.output_tokens // null) end),
        cache_read_input_tokens: (if $derived == "indisponivel" then null else ($tr.usage.cache_read_input_tokens // null) end),
        cache_creation_input_tokens: (if $derived == "indisponivel" then null else ($tr.usage.cache_creation_input_tokens // null) end),
        tool_use_count: (if $derived == "indisponivel" then null else ($tr.totalToolUseCount // null) end),
        duration_ms: (if $derived == "indisponivel" then null else ($tr.totalDurationMs // null) end),
        source: "live",
        observed_at: $ts
      }
    end
  ' 2>/dev/null
) || _PAU_LINE=""

[ -n "$_PAU_LINE" ] || exit 0

_PAU_SIDECAR="$_PAU_STATE_DIR/wave-agent-usage.jsonl"
_PAU_CAP_SENTINEL="$_PAU_STATE_DIR/.wave-agent-usage-cap-warned"

_pau_line_count() {
  [ -f "$1" ] || { printf '0'; return 0; }
  wc -l < "$1" 2>/dev/null | tr -d '[:space:]'
}

_pau_current_count=$(_pau_line_count "$_PAU_SIDECAR")
case "$_pau_current_count" in
  '' | *[!0-9]*) _pau_current_count=0 ;;
esac

if [ "$_pau_current_count" -ge "$_PAU_CAP_LINES" ]; then
  if [ ! -f "$_PAU_CAP_SENTINEL" ]; then
    : > "$_PAU_CAP_SENTINEL" 2>/dev/null || :
    printf 'posttooluse-agent-usage: cap de %s linhas atingido em %s; spawns adicionais desta onda ficam fora do agregado (undercounting silencioso documentado)\n' \
      "$_PAU_CAP_LINES" "$_PAU_SIDECAR" >&2
  fi
  exit 0
fi

# umask 077 antes do primeiro append -> arquivo criado com 0600 (CHK017).
# So afeta CRIACAO; se o sidecar ja existia mais aberto, o chmod abaixo
# corrige best-effort apos o append.
(
  umask 077
  printf '%s\n' "$_PAU_LINE" >> "$_PAU_SIDECAR" 2>/dev/null
) || :
chmod 600 -- "$_PAU_SIDECAR" 2>/dev/null || :

exit 0
