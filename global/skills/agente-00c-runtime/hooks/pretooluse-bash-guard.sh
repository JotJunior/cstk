#!/bin/sh
# pretooluse-bash-guard.sh — hook PreToolUse/Bash: interceptacao enforced e
# fail-closed de comandos Bash durante execucoes ativas agente-00c/feature-00c
# (US1 — enforced-guards, FR-001/FR-002/FR-006/FR-007/FR-016).
#
# Ref: docs/specs/enforced-guards/{spec.md, contracts/pretooluse-hook.md,
#      contracts/enforcement-log.md, data-model.md::GuardHookRegistration
#      /EnforcementDecisionLog, research.md Decision 1/2/3/5/8/10}.
#
# Casca fina (research.md Decision 2): so faz parsing do stdin do harness e
# deteccao de execucao ativa; a DECISAO de regra e delegada 100% ao
# bash-guard.sh JA EXISTENTE e INALTERADO (nunca reimplementa blocklist nem
# whitelist aqui).
#
# jq: dependencia OPCIONAL confinada a este arquivo (Constitution 1.1.0
# Principio II carve-out — ver research.md Decision 2). Sem jq nao da pra
# parsear o stdin do harness com seguranca -> fail-closed imediato
# (MECANISMO_FALHOU), sem linha de log (nao ha como resolver `cwd` sem jq;
# limitacao documentada, nao um gap silencioso).
#
# Contrato de I/O (fonte: doc oficial do harness, https://code.claude.com/docs/en/hooks
# — ver research.md Decision 1): stdin = JSON {cwd, tool_name, tool_input.command,
# ...}. O proprio script SEMPRE sai com exit 0 — o harness so entende
# bloqueio via o JSON de hookSpecificOutput, nao via exit code != 0
# (Decision 1 escolheu esse mecanismo em vez de `exit 2`).
#
# Caso 1 (fora de escopo OU comando permitido): exit 0, stdout vazio.
# Caso 2 (bloqueado, por regra ou por falha do mecanismo): exit 0 + stdout
#   {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"<PREFIXO>: <motivo>"}}
#
# Resolucao de bash-guard.sh/secrets-filter.sh (gap nao coberto pelos
# artefatos de /plan — resolvido aqui, task 2.1): o hook e provisionado
# standalone em <projeto>/.claude/hooks/ (data-model.md GuardHookRegistration),
# desacoplado de onde a skill agente-00c-runtime foi instalada (escopo
# project OU global). Candidatos tentados em ordem, primeiro
# existente+executavel vence:
#   1. sibling relativo ao proprio hook (.../hooks/../scripts/*) — cobre
#      invocacao direta a partir da arvore-fonte do repo (dev/testes: hooks/
#      e scripts/ sao irmaos ali tambem)
#   2. <cwd>/.claude/skills/agente-00c-runtime/scripts/* (escopo project)
#   3. $HOME/.claude/skills/agente-00c-runtime/scripts/* (escopo global)
#
# Deteccao de execucao ativa (feature hooks-db-parity, FASE 3): delegada ao
# helper agnostico a backend `_hook-active-exec.sh`
# (docs/specs/hooks-db-parity/contracts/hook-active-exec.md), substituindo a
# antiga leitura inline triplicada de `state.json`. Precondicionada por um
# pre-check inline com builtins puros (SEC-H1/spec.md FR-008) — se nao ha
# nenhum `state.json`/`state.db` sob `.claude/{agente-00c,feature-00c}-state`,
# o hook sai `0` sem resolver nem sourcear nada (FR-006, 100% das sessoes
# manuais). So DEPOIS do pre-check o helper e resolvido com a ORDEM
# INVERTIDA (dec-026): `$HOME` antes de `<cwd>` — sombrear conteudo
# plantado no repositorio-alvo com a instalacao global controlada pelo
# operador. A ordem original (cwd antes de HOME) permanece INALTERADA para
# `bash-guard.sh`/`secrets-filter.sh` abaixo (resolvidos so apos confirmar
# execucao ativa — nenhuma regressao de superficie).

set -eu

_PBG_NAME="pretooluse-bash-guard"
_PBG_SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd) || _PBG_SELF_DIR=""

_pbg_has_jq() {
  command -v jq >/dev/null 2>&1
}

# _pbg_resolve_dep REL_PATH -> imprime primeiro candidato existente+executavel
# em stdout; exit 1 se nenhum encontrado. REL_PATH ex: "scripts/bash-guard.sh".
_pbg_resolve_dep() {
  _pbg_rel=$1
  if [ -n "$_PBG_SELF_DIR" ] && [ -x "$_PBG_SELF_DIR/../$_pbg_rel" ]; then
    printf '%s' "$_PBG_SELF_DIR/../$_pbg_rel"
    return 0
  fi
  if [ -n "${_PBG_CWD:-}" ] && [ -x "$_PBG_CWD/.claude/skills/agente-00c-runtime/$_pbg_rel" ]; then
    printf '%s' "$_PBG_CWD/.claude/skills/agente-00c-runtime/$_pbg_rel"
    return 0
  fi
  if [ -n "${HOME:-}" ] && [ -x "$HOME/.claude/skills/agente-00c-runtime/$_pbg_rel" ]; then
    printf '%s' "$HOME/.claude/skills/agente-00c-runtime/$_pbg_rel"
    return 0
  fi
  return 1
}

# _pbg_resolve_dep_hae REL_PATH -> cadeia de resolucao IDENTICA a
# _pbg_resolve_dep, exceto por duas diferencas exigidas pelo contrato
# (contracts/hook-active-exec.md §"Ordem MODIFICADA para o helper (SEC-H1)
# [APROVADA — dec-026]"), aplicadas SOMENTE ao sourcing de
# _hook-active-exec.sh:
#   1. ordem invertida: $HOME (escopo global) ANTES de <cwd> (escopo
#      project) — instalacao controlada pelo operador sombreia conteudo
#      plantado no repositorio-alvo.
#   2. teste `-r` (legivel), nao `-x` (executavel) — arquivo sourceable,
#      nao executavel (helpers `_*.sh` do runtime nao tem bit +x).
_pbg_resolve_dep_hae() {
  _pbg_rel=$1
  if [ -n "$_PBG_SELF_DIR" ] && [ -r "$_PBG_SELF_DIR/../$_pbg_rel" ]; then
    printf '%s' "$_PBG_SELF_DIR/../$_pbg_rel"
    return 0
  fi
  if [ -n "${HOME:-}" ] && [ -r "$HOME/.claude/skills/agente-00c-runtime/$_pbg_rel" ]; then
    printf '%s' "$HOME/.claude/skills/agente-00c-runtime/$_pbg_rel"
    return 0
  fi
  if [ -n "${_PBG_CWD:-}" ] && [ -r "$_PBG_CWD/.claude/skills/agente-00c-runtime/$_pbg_rel" ]; then
    printf '%s' "$_PBG_CWD/.claude/skills/agente-00c-runtime/$_pbg_rel"
    return 0
  fi
  return 1
}

# _pbg_precheck_active_scope -> 0 (existe escopo a checar) se ao menos um
# `state.json` OU `state.db` existe sob
# `$_PBG_CWD/.claude/agente-00c-state/` ou
# `$_PBG_CWD/.claude/feature-00c-state/*/` (SEC-H1, spec.md FR-008).
# Usa EXCLUSIVAMENTE builtins do shell (`[ -f ]`, `[ -d ]`) — nenhuma
# resolucao de dependencia nem sourcing acontece antes desta checagem.
_pbg_precheck_active_scope() {
  _pbg_pa_agente="$_PBG_CWD/.claude/agente-00c-state"
  if [ -f "$_pbg_pa_agente/state.json" ] || [ -f "$_pbg_pa_agente/state.db" ]; then
    return 0
  fi

  _pbg_pa_froot="$_PBG_CWD/.claude/feature-00c-state"
  if [ -d "$_pbg_pa_froot" ]; then
    for _pbg_pa_d in "$_pbg_pa_froot"/*/; do
      [ -d "$_pbg_pa_d" ] || continue
      if [ -f "${_pbg_pa_d}state.json" ] || [ -f "${_pbg_pa_d}state.db" ]; then
        return 0
      fi
    done
  fi
  return 1
}

# _pbg_emit_deny PREFIXO MOTIVO -> stdout JSON de bloqueio (jq quando
# disponivel, com escaping seguro via --arg; literal fixo SO no ramo
# jq-ausente, onde o motivo e sempre um texto estatico proprio do hook,
# nunca dado interpolado). Sempre finaliza com exit 0 (Decision 1).
_pbg_emit_deny() {
  _pbg_prefix=$1
  _pbg_motivo=$2
  if _pbg_has_jq; then
    jq -n --arg reason "$_pbg_prefix: $_pbg_motivo" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}' \
      2>/dev/null
  else
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s: %s"}}\n' \
      "$_pbg_prefix" "$_pbg_motivo"
  fi
  exit 0
}

# _pbg_category_from_stderr TEXTO -> extrai a categoria emitida por
# _bg_emit_block ("categoria=<CAT> —"); fallback para casos de whitelist
# (sem tag categoria=) ou desconhecido.
_pbg_category_from_stderr() {
  _pbg_cat=$(printf '%s' "$1" | sed -n 's/.*categoria=\([^ ]*\).*/\1/p' | sed -n '1p')
  if [ -n "$_pbg_cat" ]; then
    printf '%s' "$_pbg_cat"
    return 0
  fi
  case "$1" in
    *whitelist* | *URL*) printf '%s' "network-not-whitelisted" ;;
    *) printf '%s' "unknown-rule" ;;
  esac
}

# _pbg_scrub_text TEXTO -> aplica secrets-filter.sh scrub e imprime o
# resultado. Achado empirico desta onda (task 2.3, teste adversarial): a
# mensagem de erro de `bash-guard.sh check-whitelist` embute o COMANDO CRU
# ("comando: <cru>") quando a falha e de whitelist de rede — o MUST de
# scrub (Decision 10/CHK020) vale tambem para o `reason`/`permissionDecisionReason`
# exibido ao harness/LLM e gravado no log, nao so para o campo `command` do
# EnforcementDecisionLog. Fail-closed: qualquer falha (resolucao OU scrub em
# si) => placeholder seguro, NUNCA o texto cru sem filtro.
_pbg_scrub_text() {
  if _pbg_sf_bin=$(_pbg_resolve_dep "scripts/secrets-filter.sh" 2>/dev/null); then
    if _pbg_scrubbed=$(printf '%s' "$1" | "$_pbg_sf_bin" scrub 2>/dev/null); then
      printf '%s' "$_pbg_scrubbed"
      return 0
    fi
  fi
  printf '%s' "[secrets-filter indisponivel ou falhou - motivo omitido por seguranca]"
}

# _pbg_write_log OUTCOME COMMAND REASON CATEGORY -> best-effort append em
# <cwd>/.claude/enforcement-log.jsonl (contract enforcement-log.md). Falha
# de escrita NUNCA aborta o hook (efeito colateral, nao gate) — so aviso em
# stderr. So chamada quando ha execucao ativa detectada (_PBG_DETECTED_EXEC
# setado por quem chama).
#
# Ordem OBRIGATORIA scrub-antes-de-truncar (CHK020/task 1.4/Decision 10):
# secrets-filter.sh scrub | cut -c1-500 — NUNCA a ordem inversa.
_pbg_write_log() {
  _pbg_outcome=$1
  _pbg_raw_cmd=$2
  _pbg_reason=$3
  _pbg_category=$4

  _pbg_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || _pbg_ts=""
  _pbg_sf=$(_pbg_resolve_dep "scripts/secrets-filter.sh") || _pbg_sf=""
  if [ -n "$_pbg_sf" ]; then
    _pbg_safe_cmd=$(printf '%s' "$_pbg_raw_cmd" | "$_pbg_sf" scrub 2>/dev/null | cut -c1-500) || _pbg_safe_cmd="[secrets-filter-falhou]"
  else
    _pbg_safe_cmd="[secrets-filter indisponivel - comando omitido por seguranca]"
  fi

  _pbg_line=$(jq -nc \
    --arg source "pretooluse-bash-guard" \
    --arg ts "$_pbg_ts" \
    --arg outcome "$_pbg_outcome" \
    --arg command "$_pbg_safe_cmd" \
    --arg reason "$_pbg_reason" \
    --arg category "$_pbg_category" \
    --arg dexec "$_PBG_DETECTED_EXEC" \
    --arg dpath "$_PBG_DETECTED_PATH" \
    '{source: $source, timestamp: $ts, outcome: $outcome, command: $command,
      reason: (if $reason == "" then null else $reason end),
      category: (if $category == "" then null else $category end),
      detected_execution: (if $dexec == "" then null else $dexec end),
      detected_execution_path: (if $dpath == "" then null else $dpath end)}' \
    2>/dev/null) || return 0

  mkdir -p "$_PBG_CWD/.claude" 2>/dev/null || :
  printf '%s\n' "$_pbg_line" >>"$_PBG_CWD/.claude/enforcement-log.jsonl" 2>/dev/null \
    || printf '%s: aviso - falha ao gravar enforcement-log.jsonl\n' "$_PBG_NAME" >&2
  return 0
}

# ================= corpo principal =================

# ---------- 1. jq disponivel? (Decision 2 — sem jq, sem parsing seguro) ----------

if ! _pbg_has_jq; then
  _pbg_emit_deny "MECANISMO_FALHOU" "jq ausente, comando nao pode ser validado com seguranca"
fi

# ---------- 2. Ler + parsear stdin (contrato do harness, Decision 1) ----------

_PBG_INPUT=$(cat) || _PBG_INPUT=""

if [ -z "$_PBG_INPUT" ]; then
  _pbg_emit_deny "MECANISMO_FALHOU" "stdin vazio, comando nao pode ser validado com seguranca"
fi

if ! _PBG_CWD=$(printf '%s' "$_PBG_INPUT" | jq -r '.cwd // ""' 2>/dev/null); then
  _pbg_emit_deny "MECANISMO_FALHOU" "stdin invalido (JSON malformado), comando nao pode ser validado com seguranca"
fi
_PBG_TOOL_NAME=$(printf '%s' "$_PBG_INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || _PBG_TOOL_NAME=""
_PBG_CMD=$(printf '%s' "$_PBG_INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || _PBG_CMD=""

if [ -z "$_PBG_CWD" ]; then
  _pbg_emit_deny "MECANISMO_FALHOU" "campo cwd ausente no payload do harness"
fi

# ---------- 3. Defesa redundante do matcher ("erros do proprio contrato") ----------

if [ "$_PBG_TOOL_NAME" != "Bash" ]; then
  exit 0
fi

# ---------- 4. Pre-check inline (SEC-H1) + deteccao tri-estado via helper ----------

# Pre-check inline: sem NENHUM state.json/state.db sob agente-00c-state/ ou
# feature-00c-state/*/, o hook sai 0 sem resolver nem sourcear coisa
# alguma — 100% das sessoes manuais do operador (FR-006).
if ! _pbg_precheck_active_scope; then
  exit 0
fi

_PBG_DETECTED_EXEC=""
_PBG_DETECTED_PATH=""

if ! _PBG_HAE_HELPER=$(_pbg_resolve_dep_hae "scripts/_hook-active-exec.sh"); then
  _pbg_write_log "blocked-mechanism-failure" "$_PBG_CMD" "_hook-active-exec.sh ausente ou ilegivel" "mechanism-error"
  _pbg_emit_deny "MECANISMO_FALHOU" "_hook-active-exec.sh ausente ou ilegivel"
fi

# shellcheck disable=SC1090 # caminho resolvido dinamicamente pela cadeia de candidatos acima
. "$_PBG_HAE_HELPER"

# SEC-M2: guarda tolera a espera plena do busy_timeout (200ms), ainda
# folgado dentro do teto de gate de 400ms (FR-005/task 1.6/contracts
# §SEC-M2) — diferente dos hooks de metrica (50ms).
HAE_BUSY_TIMEOUT_MS=200
export HAE_BUSY_TIMEOUT_MS

# Idioma if/else em vez de atribuicao direta de `$(...)` (paridade com o
# padrao ja usado neste arquivo em L189/L269): sob `set -e`, uma atribuicao
# simples cujo command substitution falha aborta o script inteiro — aqui
# exit 1/2 do helper sao caminhos de controle legitimos, nao erros.
if _PBG_HAE_OUT=$(hook_active_exec "$_PBG_CWD"); then
  _PBG_HAE_RC=0
else
  _PBG_HAE_RC=$?
fi

case "$_PBG_HAE_RC" in
  0)
    # ativa: <execution_kind>\t<state_dir>\t<backend> — prossegue ao fluxo
    # existente de delegacao ao bash-guard.sh, inalterado (task 3.1.2/3.1.5).
    _PBG_DETECTED_EXEC=$(printf '%s' "$_PBG_HAE_OUT" | cut -f1)
    _pbg_hae_dir=$(printf '%s' "$_PBG_HAE_OUT" | cut -f2)
    _pbg_hae_backend=$(printf '%s' "$_PBG_HAE_OUT" | cut -f3)
    # backend do helper e "sqlite"|"json" (nao a extensao do arquivo) —
    # mapear para o nome de arquivo real lido (state.db / state.json).
    case "$_pbg_hae_backend" in
      sqlite) _pbg_hae_file="state.db" ;;
      *) _pbg_hae_file="state.json" ;;
    esac
    _PBG_DETECTED_PATH="$_pbg_hae_dir/$_pbg_hae_file"
    ;;
  1)
    # inativa (inclui "nenhum state presente" e status terminal, FR-007):
    # sai 0 imediatamente, sem tocar em nenhum arquivo (paridade FR-006).
    exit 0
    ;;
  *)
    # indeterminada (exit 2) ou helper irresolvivel/uso incorreto (demais
    # exits, convencao 127) — MECANISMO_FALHOU, nunca stdout vazio
    # (task 3.1.4; SEC-H2 auto-teto interno do helper, SEC-M3, ja aplicado
    # dentro de hook_active_exec, reclassificado a defesa em profundidade
    # apos dec-039 confirmar com fonte que timeout de PreToolUse = deny).
    _pbg_write_log "blocked-mechanism-failure" "$_PBG_CMD" "hook_active_exec indeterminada (exit $_PBG_HAE_RC)" "mechanism-error"
    _pbg_emit_deny "MECANISMO_FALHOU" "deteccao de execucao ativa indeterminada"
    ;;
esac

# ---------- 5. Delegar a bash-guard.sh (task 2.1.2 — nunca reimplementar) ----------

if ! _PBG_BASH_GUARD=$(_pbg_resolve_dep "scripts/bash-guard.sh"); then
  _pbg_write_log "blocked-mechanism-failure" "$_PBG_CMD" "bash-guard.sh ausente ou nao executavel" "mechanism-error"
  _pbg_emit_deny "MECANISMO_FALHOU" "bash-guard.sh ausente ou nao executavel"
fi

# Whitelist file (Decision 8 — dois nomes legados coexistem no codebase;
# tenta ambos, primeiro que existir vence; nenhum -> bash-guard.sh trata
# como whitelist vazia, comportamento ja existente).
_pbg_wl="$_PBG_CWD/.claude/agente-00c-whitelist"
if [ ! -f "$_pbg_wl" ]; then
  _pbg_wl_alt="$_PBG_CWD/.agente-00c-whitelist.txt"
  [ -f "$_pbg_wl_alt" ] && _pbg_wl="$_pbg_wl_alt"
fi

if ! _pbg_bg_stderr=$(mktemp 2>/dev/null); then
  _pbg_write_log "blocked-mechanism-failure" "$_PBG_CMD" "mktemp indisponivel para capturar diagnostico" "mechanism-error"
  _pbg_emit_deny "MECANISMO_FALHOU" "mktemp indisponivel para capturar diagnostico do bash-guard.sh"
fi

if "$_PBG_BASH_GUARD" check --command "$_PBG_CMD" --whitelist-file "$_pbg_wl" 2>"$_pbg_bg_stderr"; then
  _pbg_bg_exit=0
else
  _pbg_bg_exit=$?
fi
_pbg_bg_msg=$(cat "$_pbg_bg_stderr" 2>/dev/null) || _pbg_bg_msg=""
rm -f "$_pbg_bg_stderr" 2>/dev/null || :

case "$_pbg_bg_exit" in
  0)
    _pbg_write_log "allowed" "$_PBG_CMD" "" ""
    exit 0
    ;;
  1)
    # Categoria extraida do texto CRU (o marcador "categoria=xxx" e sempre um
    # slug fixo sem secrets, ver bash-guard.sh::_bg_emit_block) — so DEPOIS
    # o texto e escrubado para uso em reason/motivo (nunca o cru daqui pra frente).
    _pbg_category=$(_pbg_category_from_stderr "$_pbg_bg_msg")
    _pbg_bg_msg=$(_pbg_scrub_text "$_pbg_bg_msg")
    _pbg_write_log "blocked-by-rule" "$_PBG_CMD" "$_pbg_bg_msg" "$_pbg_category"
    _pbg_emit_deny "REGRA_VIOLADA" "$_pbg_bg_msg"
    ;;
  *)
    _pbg_write_log "blocked-mechanism-failure" "$_PBG_CMD" "bash-guard.sh retornou exit $_pbg_bg_exit (uso incorreto)" "mechanism-error"
    _pbg_emit_deny "MECANISMO_FALHOU" "bash-guard.sh retornou exit $_pbg_bg_exit (uso incorreto)"
    ;;
esac
