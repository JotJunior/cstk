#!/bin/sh
# session-scope.sh — raiz da sessao do harness x projeto-alvo da execucao
# (issues #189/#190/#191 — mesma raiz: projeto-alvo != raiz da sessao).
#
# PROBLEMA QUE FECHA
# ------------------
# Os tres hooks de guarda (`pretooluse-bash-guard.sh` e os dois de metrica)
# e o servidor MCP `cstk-state` desta sessao sao carregados a partir da RAIZ
# DO PROJETO DA SESSAO do Claude Code (o `.claude/settings.json` e o
# `.mcp.json` lidos no boot). Ambos ancoram a pergunta "ha execucao ativa?"
# nessa raiz: o hook resolve o escopo por cwd/ancestrais/`CLAUDE_PROJECT_DIR`
# (nunca desce, nunca sai do `.git`), e o servidor MCP varre
# `<raiz>/.claude/{agente-00c-state,feature-00c-state}` (`mcp-session.sh
# resolve --project-path`). Quando `--projeto` de um command 00c aponta para
# OUTRO diretorio (caso tipico: worktree irma criada por `cstk session
# start`, comandada do checkout principal), todo diagnostico responde verde
# — hooks `present registered current`, `cstk mcp start` cunha token,
# `mcp-launch.sh preflight` = `ready` — e ainda assim a guarda fica inerte
# (`tool_calls: 0`, medido em 3 ondas reais) e toda tool MCP devolve
# `SESSION_MISMATCH`. Guarda advisory na pratica, reportada como enforced.
#
# Este helper e a UNICA implementacao da pergunta "o projeto-alvo esta sob a
# raiz desta sessao?" — commands, `guard-hooks-status.sh`, `mcp-launch.sh
# preflight` e `cstk mcp status --live` delegam a ela em vez de reimplementar
# (mesma disciplina de `state-backend.sh resolve` / `bash-guard.sh check`).
#
# RAIZ DA SESSAO (`resolve`)
# --------------------------
#   1. `$CLAUDE_PROJECT_DIR` quando definido e diretorio — e o que o harness
#      exporta para HOOKS (o proprio `pretooluse-bash-guard.sh` a usa como
#      fronteira). NAO chega ao ambiente da tool Bash (medido: ausente em
#      `env` dentro de um command), por isso o passo 2.
#   2. `pwd -P` — o cwd da tool Bash nasce na raiz da sessao e os commands 00c
#      nunca fazem `cd` persistente (so em subshell). E EXATAMENTE o mesmo
#      sinal que `mcp-launch.sh` usa (`CSTK_MCP_PROJECT_PATH:-$(pwd)`) para o
#      servidor MCP: se divergir daqui, diverge la.
#   Nao existe override por env: uma env var que redirecionasse a raiz seria
#   um bypass nao auditado (mesma razao pela qual o hook consulta
#   `CLAUDE_PROJECT_DIR` por ultimo e so como fronteira). O bypass existe, e
#   explicito e auditado (`--allow-outside`, abaixo).
#
# VEREDITO (`check`)
# ------------------
# Igualdade ESTRITA de caminhos canonicos (`cd && pwd -P` nos dois lados).
# Subdiretorio NAO e "alinhado": o hook nunca desce a partir do cwd e o
# servidor MCP so varre `<raiz>/.claude/` — um alvo abaixo da raiz e tao
# inerte quanto um irmao.
#
#   aligned          raiz == alvo                              exit 0
#   diverged         raiz != alvo, sem bypass (fail-closed)    exit 4
#   diverged-allowed raiz != alvo, bypass explicito            exit 0
#                    (`--allow-outside` ou
#                    `CSTK_ALLOW_TARGET_OUTSIDE_SESSION=1`),
#                    aviso de alta visibilidade em stderr
#
# Toda divergencia (recusada OU permitida) vira linha auditavel em
# `<projeto-alvo>/.claude/enforcement-log.jsonl` (`source:"session-scope"`,
# `outcome: refused|bypass-allowed`), mesmo arquivo e idioma do
# `serve-integrity` (`--allow-unverified`). Best-effort: falha de escrita
# nunca muda o veredito.
#
# USO
# ---
#   session-scope.sh resolve
#       stdout: session_root=<path>
#               source=claude-project-dir|cwd
#   session-scope.sh verdict --projeto-alvo-path PATH
#       Comparacao PURA (sem log, sem bypass): para consumidores que so
#       diagnosticam (`mcp-launch.sh preflight`, `guard-hooks-status.sh
#       check`, `cstk mcp status --live`) e nao devem gravar `refused`
#       no enforcement-log nem honrar o bypass — a tool MCP e o hook nao
#       passam a funcionar porque o operador aceitou o risco.
#       stdout: session_root=<path>
#               target_project_path=<path>
#               verdict=aligned|diverged
#       exit 0 aligned · 4 diverged
#   session-scope.sh check --projeto-alvo-path PATH [--allow-outside] [--quiet]
#       stdout: session_root=<path>
#               target_project_path=<path>
#               verdict=aligned|diverged|diverged-allowed
#               reason=-|<texto>
#       --quiet suprime o stdout (exit code e o log continuam).
#
# Exit codes: 0 ok/alinhado/permitido · 1 erro (path inexistente) · 2 uso
# incorreto · 4 diverged (recusado).
#
# POSIX sh puro (sem jq): o projeto-alvo pode estar mal provisionado.

set -eu

_SS_NAME="session-scope"

_ss_die() {
  printf '%s: %s\n' "$_SS_NAME" "$1" >&2
  exit "${2:-1}"
}

_ss_die_usage() {
  printf '%s: %s\n' "$_SS_NAME" "$1" >&2
  printf 'uso: session-scope.sh resolve | verdict --projeto-alvo-path PATH | check --projeto-alvo-path PATH [--allow-outside] [--quiet]\n' >&2
  exit 2
}

# _ss_canon PATH -> caminho canonico (symlinks resolvidos) ou falha.
_ss_canon() {
  [ -d "$1" ] || return 1
  (CDPATH='' cd -- "$1" 2>/dev/null && pwd -P)
}

# _ss_json_escape S — escape minimo para valor JSON (barra, aspas, newline).
_ss_json_escape() {
  printf '%s' "$1" | awk '
    {
      gsub(/\\/, "\\\\");
      gsub(/"/, "\\\"");
      out = out (NR > 1 ? "\\n" : "") $0
    }
    END { printf "%s", out }
  '
}

# _ss_session_root -> imprime "<root>\t<source>"; falha se nada resolver.
_ss_session_root() {
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "${CLAUDE_PROJECT_DIR}" ]; then
    if _r=$(_ss_canon "$CLAUDE_PROJECT_DIR"); then
      printf '%s\tclaude-project-dir\n' "$_r"
      return 0
    fi
  fi
  _r=$(pwd -P 2>/dev/null) || return 1
  printf '%s\tcwd\n' "$_r"
}

# _ss_write_log TARGET ROOT OUTCOME — linha no enforcement-log do alvo.
_ss_write_log() {
  _wl_target=$1
  _wl_root=$2
  _wl_outcome=$3
  _wl_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || _wl_ts=""
  _wl_line=$(printf '{"source":"session-scope","timestamp":"%s","outcome":"%s","session_root":"%s","target_project_path":"%s"}' \
    "$(_ss_json_escape "$_wl_ts")" \
    "$(_ss_json_escape "$_wl_outcome")" \
    "$(_ss_json_escape "$_wl_root")" \
    "$(_ss_json_escape "$_wl_target")")
  mkdir -p "$_wl_target/.claude" 2>/dev/null || return 0
  printf '%s\n' "$_wl_line" >>"$_wl_target/.claude/enforcement-log.jsonl" 2>/dev/null || :
  return 0
}

_ss_cmd_resolve() {
  [ "$#" -eq 0 ] || _ss_die_usage "resolve nao aceita argumentos"
  _rs=$(_ss_session_root) || _ss_die "nao consegui resolver a raiz da sessao (pwd falhou)" 1
  _rs_root=${_rs%	*}
  _rs_src=${_rs#*	}
  printf 'session_root=%s\n' "$_rs_root"
  printf 'source=%s\n' "$_rs_src"
}

# _ss_compare TARGET -> define _SS_ROOT/_SS_TARGET (canonicos) e retorna
# 0 (aligned) ou 4 (diverged). UNICA implementacao da comparacao — `verdict`
# e `check` so a embrulham (o mutation test em tests/test_session-scope.sh
# neutraliza exatamente esta linha).
_ss_compare() {
  _SS_TARGET=$(_ss_canon "$1") \
    || _ss_die "--projeto-alvo-path nao existe ou nao e diretorio: $1" 1
  _rs=$(_ss_session_root) || _ss_die "nao consegui resolver a raiz da sessao (pwd falhou)" 1
  _SS_ROOT=${_rs%	*}
  if [ "$_SS_ROOT" = "$_SS_TARGET" ]; then
    return 0
  fi
  return 4
}

# _ss_parse_target ARGS... -> _SS_ARG_TARGET/_SS_ARG_ALLOW/_SS_ARG_QUIET
_ss_parse_target() {
  _SS_ARG_TARGET=""
  _SS_ARG_ALLOW=""
  _SS_ARG_QUIET=""
  _pt_sub=$1; shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --projeto-alvo-path)
        [ "$#" -ge 2 ] || _ss_die_usage "--projeto-alvo-path exige valor"
        _SS_ARG_TARGET=$2; shift 2 ;;
      --allow-outside)
        [ "$_pt_sub" = "check" ] || _ss_die_usage "$_pt_sub: --allow-outside so existe em check"
        _SS_ARG_ALLOW=1; shift ;;
      --quiet)
        [ "$_pt_sub" = "check" ] || _ss_die_usage "$_pt_sub: --quiet so existe em check"
        _SS_ARG_QUIET=1; shift ;;
      *) _ss_die_usage "$_pt_sub: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_SS_ARG_TARGET" ] || _ss_die_usage "$_pt_sub: --projeto-alvo-path e obrigatorio"
}

_ss_cmd_verdict() {
  _ss_parse_target verdict "$@"
  if _ss_compare "$_SS_ARG_TARGET"; then _vd_verdict="aligned"; _vd_exit=0
  else _vd_verdict="diverged"; _vd_exit=4
  fi
  printf 'session_root=%s\n' "$_SS_ROOT"
  printf 'target_project_path=%s\n' "$_SS_TARGET"
  printf 'verdict=%s\n' "$_vd_verdict"
  exit "$_vd_exit"
}

_ss_cmd_check() {
  _ss_parse_target check "$@"
  _ck_allow=$_SS_ARG_ALLOW
  [ "${CSTK_ALLOW_TARGET_OUTSIDE_SESSION:-}" = "1" ] && _ck_allow=1

  if _ss_compare "$_SS_ARG_TARGET"; then
    _ck_verdict="aligned"
    _ck_reason="-"
    _ck_exit=0
  else
    _ck_reason="projeto-alvo fora da raiz da sessao — hooks de guarda e servidor MCP desta sessao operam sob $_SS_ROOT"
    if [ -n "$_ck_allow" ]; then
      _ck_verdict="diverged-allowed"
      _ck_exit=0
      _ss_write_log "$_SS_TARGET" "$_SS_ROOT" "bypass-allowed"
      printf '%s: AVISO -- prosseguindo com projeto-alvo FORA da raiz da sessao (bypass explicito): hooks de guarda registrados em %s NAO gateiam esta sessao e as tools mcp__cstk-state__* nao resolvem o token desta execucao\n' \
        "$_SS_NAME" "$_SS_TARGET" >&2
    else
      _ck_verdict="diverged"
      _ck_exit=4
      _ss_write_log "$_SS_TARGET" "$_SS_ROOT" "refused"
      printf '%s: recusado -- projeto-alvo %s fora da raiz da sessao %s\n' \
        "$_SS_NAME" "$_SS_TARGET" "$_SS_ROOT" >&2
      printf '%s: as guardas enforced (hooks) e o servidor MCP desta sessao so operam sob a raiz; abra a sessao no projeto-alvo (cd %s && claude) ou use --allow-outside / CSTK_ALLOW_TARGET_OUTSIDE_SESSION=1 conscientemente (auditado)\n' \
        "$_SS_NAME" "$_SS_TARGET" >&2
    fi
  fi

  if [ -z "$_SS_ARG_QUIET" ]; then
    printf 'session_root=%s\n' "$_SS_ROOT"
    printf 'target_project_path=%s\n' "$_SS_TARGET"
    printf 'verdict=%s\n' "$_ck_verdict"
    printf 'reason=%s\n' "$_ck_reason"
  fi
  exit "$_ck_exit"
}

# ---------- Dispatch ----------

if [ "$#" -lt 1 ]; then
  _ss_die_usage "subcomando ausente (resolve | verdict | check)"
fi
_ss_sub=$1
shift
case "$_ss_sub" in
  resolve) _ss_cmd_resolve "$@" ;;
  verdict) _ss_cmd_verdict "$@" ;;
  check)   _ss_cmd_check "$@" ;;
  -h|--help)
    cat <<'HELP'
Uso: session-scope.sh resolve
     session-scope.sh verdict --projeto-alvo-path PATH   (puro: sem log, sem bypass)
     session-scope.sh check --projeto-alvo-path PATH [--allow-outside] [--quiet]

Compara a raiz da sessao do harness (CLAUDE_PROJECT_DIR ou pwd -P) com o
projeto-alvo. Divergencia = hooks de guarda inertes + tools MCP em
SESSION_MISMATCH para esta execucao (issues #189/#190/#191).

Vereditos: aligned (exit 0) | diverged (exit 4, fail-closed) |
diverged-allowed (exit 0; --allow-outside ou
CSTK_ALLOW_TARGET_OUTSIDE_SESSION=1; aviso em stderr). Toda divergencia
vira linha em <alvo>/.claude/enforcement-log.jsonl (source=session-scope).
HELP
    exit 0
    ;;
  *) _ss_die_usage "subcomando desconhecido: $_ss_sub" ;;
esac
