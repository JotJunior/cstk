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
# Deteccao de execucao ativa (feature hooks-db-parity, FASE 5): delegada ao
# helper agnostico a backend `_hook-active-exec.sh`
# (docs/specs/hooks-db-parity/contracts/hook-active-exec.md), substituindo a
# antiga leitura inline de `state.json` (unico backend suportado ate entao).
# Mesmo padrao ja portado em posttooluse-tool-call-tick.sh (FASE 4): pre-check
# inline (SEC-H1/spec.md FR-008) com builtins puros, seguido de
# `_resolve_dep_hae` com ORDEM INVERTIDA (dec-026): `$HOME` antes de
# `<cwd>`. Precedencia dentro do helper: agente-00c vence; entre
# feature-00c, menor short-name lexicografico byte-wise; status
# em_andamento|aguardando_humano. Fora de execucao ativa: exit 0, zero
# interferencia na sessao manual.
#
# Politica de exit codes do helper — fail-OPEN (metrica, nao guarda),
# identica ao hook de ticks: `0` (ativa) grava a linha; `1` (inativa) e
# `2`/`127` (indeterminada/helper irresolvivel) sao NO-OP silencioso, exit 0.
# busy_timeout diferenciado (SEC-M2/task 1.6/CHK027): 50ms
# (HAE_BUSY_TIMEOUT_MS=50), nao os 200ms tolerados pelo guard.
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

_PAU_SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd) || _PAU_SELF_DIR=""
# Raiz do projeto-alvo, resolvida por _pau_precheck_active_scope a partir
# do `.cwd` do payload (que pode estar num subdiretorio).
_PAU_SCOPE=""

# Bootstrap: localizar+sourcear `_resolve-root.sh` (feature
# claude-plugin-packaging, task 3.2.3). Ordem A (fail-open, consumidor
# geral) — ver mesmo bootstrap em posttooluse-loose-usage.sh. Falha aqui
# deixa `resolve_runtime_root` indefinida; tratado como candidato
# nao-resolvido pelos chamadores (fail-open, nunca aborta o hook).
_pau_rr_helper=""
if [ -n "$_PAU_SELF_DIR" ] && [ -r "$_PAU_SELF_DIR/../scripts/_resolve-root.sh" ]; then
  _pau_rr_helper="$_PAU_SELF_DIR/../scripts/_resolve-root.sh"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -r "${CLAUDE_PLUGIN_ROOT}/skills/agente-00c-runtime/scripts/_resolve-root.sh" ]; then
  _pau_rr_helper="${CLAUDE_PLUGIN_ROOT}/skills/agente-00c-runtime/scripts/_resolve-root.sh"
elif [ -n "${HOME:-}" ] && [ -r "$HOME/.claude/skills/agente-00c-runtime/scripts/_resolve-root.sh" ]; then
  _pau_rr_helper="$HOME/.claude/skills/agente-00c-runtime/scripts/_resolve-root.sh"
fi
if [ -n "$_pau_rr_helper" ]; then
  # shellcheck disable=SC1090 # caminho resolvido dinamicamente pela cadeia de candidatos acima
  . "$_pau_rr_helper"
fi

command -v jq >/dev/null 2>&1 || exit 0

_PAU_INPUT=$(cat 2>/dev/null) || exit 0
[ -n "$_PAU_INPUT" ] || exit 0

_PAU_CWD=$(printf '%s' "$_PAU_INPUT" | jq -r '.cwd // ""' 2>/dev/null) || exit 0
_PAU_TOOL_NAME=$(printf '%s' "$_PAU_INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || exit 0

[ -n "$_PAU_CWD" ] || exit 0
# Guarda defensiva mesmo com matcher "Agent" no settings.snippet.json
# (contracts/hook-posttooluse-agent-usage.md §1.2).
[ "$_PAU_TOOL_NAME" = "Agent" ] || exit 0

# _pau_scope_has_state DIR -> 0 se DIR abriga o state de uma execucao 00c
# (`state.json` OU `state.db` sob `agente-00c-state/` ou
# `feature-00c-state/*/`). Usa EXCLUSIVAMENTE builtins do shell — nenhuma
# resolucao de dependencia nem sourcing acontece dentro nem antes desta
# checagem (SEC-H1, spec.md FR-008).
_pau_scope_has_state() {
  _pau_sh_dir=$1
  [ -n "$_pau_sh_dir" ] || return 1

  _pau_sh_agente="$_pau_sh_dir/.claude/agente-00c-state"
  if [ -f "$_pau_sh_agente/state.json" ] || [ -f "$_pau_sh_agente/state.db" ]; then
    return 0
  fi

  _pau_sh_froot="$_pau_sh_dir/.claude/feature-00c-state"
  if [ -d "$_pau_sh_froot" ]; then
    for _pau_sh_d in "$_pau_sh_froot"/*/; do
      [ -d "$_pau_sh_d" ] || continue
      if [ -f "${_pau_sh_d}state.json" ] || [ -f "${_pau_sh_d}state.db" ]; then
        return 0
      fi
    done
  fi
  return 1
}

# _pau_precheck_active_scope -> 0 assinalando `_PAU_SCOPE` com a RAIZ do
# projeto-alvo; 1 se nenhum candidato abriga state.
#
# MOTIVO (deriva de cwd): o `.cwd` do payload gruda em subdiretorios apos
# um `cd sub && ...` do agente (o cwd do Bash persiste entre tool calls) e
# nao volta sozinho. Enquanto durar a deriva, o spawn de subagente nao e
# contabilizado e a onda perde a metrica de tokens por spawn. Cadeia
# identica a do pretooluse-bash-guard.sh — ver o cabecalho de
# `_pbg_precheck_active_scope` para o racional de seguranca de manter
# `$CLAUDE_PROJECT_DIR` como ULTIMO candidato.
_pau_precheck_active_scope() {
  if _pau_scope_has_state "$_PAU_CWD"; then
    _PAU_SCOPE="$_PAU_CWD"
    return 0
  fi

  _pau_pa_cur="$_PAU_CWD"
  _pau_pa_depth=0
  while [ "$_pau_pa_depth" -lt 16 ]; do
    if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ "$_pau_pa_cur" = "$CLAUDE_PROJECT_DIR" ]; then
      break
    fi

    _pau_pa_parent="${_pau_pa_cur%/*}"
    [ -n "$_pau_pa_parent" ] || _pau_pa_parent="/"
    [ "$_pau_pa_parent" = "$_pau_pa_cur" ] && break
    _pau_pa_cur="$_pau_pa_parent"

    if _pau_scope_has_state "$_pau_pa_cur"; then
      _PAU_SCOPE="$_pau_pa_cur"
      return 0
    fi

    [ -e "$_pau_pa_cur/.git" ] && break
    [ "$_pau_pa_cur" = "/" ] && break
    _pau_pa_depth=$((_pau_pa_depth + 1))
  done

  if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && _pau_scope_has_state "$CLAUDE_PROJECT_DIR"; then
    _PAU_SCOPE="$CLAUDE_PROJECT_DIR"
    return 0
  fi

  return 1
}

# Pre-check inline: sem NENHUM state.json/state.db sob agente-00c-state/ ou
# feature-00c-state/*/, o hook sai 0 sem resolver nem sourcear coisa alguma
# (FR-006, 100% das sessoes manuais).
_pau_precheck_active_scope || exit 0

# _pau_resolve_dep_hae REL_PATH -> cadeia de resolucao para
# _hook-active-exec.sh com a ORDEM MODIFICADA exigida pelo contrato
# (contracts/hook-active-exec.md §"Ordem MODIFICADA para o helper (SEC-H1)
# [APROVADA — dec-026]"): $HOME (escopo global) ANTES de <cwd> (escopo
# project); teste `-r` (legivel), nao `-x` (helpers `_*.sh` do runtime nao
# sao executaveis). Paridade com _pbg_resolve_dep_hae/_ptt_resolve_dep_hae.
_pau_resolve_dep_hae() {
  _pau_rel=$1
  if [ -n "$_PAU_SELF_DIR" ] && [ -r "$_PAU_SELF_DIR/../$_pau_rel" ]; then
    printf '%s' "$_PAU_SELF_DIR/../$_pau_rel"
    return 0
  fi
  # Plugin/classico (Ordem A, dec-006/fail-open) via helper compartilhado
  # (feature claude-plugin-packaging, task 3.2.3).
  if _pau_root=$(resolve_runtime_root 2>/dev/null) && [ -n "$_pau_root" ] \
     && [ -r "$_pau_root/$_pau_rel" ]; then
    printf '%s' "$_pau_root/$_pau_rel"
    return 0
  fi
  if [ -n "${_PAU_SCOPE:-}" ] && [ -r "$_PAU_SCOPE/.claude/skills/agente-00c-runtime/$_pau_rel" ]; then
    printf '%s' "$_PAU_SCOPE/.claude/skills/agente-00c-runtime/$_pau_rel"
    return 0
  fi
  return 1
}

_PAU_HAE_HELPER=$(_pau_resolve_dep_hae "scripts/_hook-active-exec.sh") || exit 0

# shellcheck disable=SC1090 # caminho resolvido dinamicamente pela cadeia de candidatos acima
. "$_PAU_HAE_HELPER"

# SEC-M2: hook de metrica tolera so 50ms de contencao (orcamento de ~30ms) —
# diferente dos 200ms tolerados pelo guard (task 1.6/contracts §SEC-M2).
HAE_BUSY_TIMEOUT_MS=50
export HAE_BUSY_TIMEOUT_MS

if _PAU_HAE_OUT=$(hook_active_exec "$_PAU_SCOPE"); then
  _PAU_HAE_RC=0
else
  _PAU_HAE_RC=$?
fi

# Fail-open: so o caso `0` (ativa) grava a linha. Inativa (1), indeterminada
# (2) e helper irresolvivel (convencao 127, ja tratado acima via `exit 0`)
# sao TODOS no-op silencioso — nunca stderr, nunca sidecar criado.
[ "$_PAU_HAE_RC" -eq 0 ] || exit 0

_PAU_STATE_DIR=$(printf '%s' "$_PAU_HAE_OUT" | cut -f2)
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
