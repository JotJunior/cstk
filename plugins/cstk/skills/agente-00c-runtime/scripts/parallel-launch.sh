#!/bin/sh
# parallel-launch.sh — compoe (nunca executa) os comandos de lancamento de
# uma leva paralela de sessoes-filha em worktrees dedicadas (FR-005, FR-006).
#
# Feature: roadmap-parallel-launch
# Ref: docs/specs/roadmap-parallel-launch/contracts/parallel-launch.md §4
#      docs/specs/roadmap-parallel-launch/spec.md FR-005, FR-006, FR-007,
#      FR-011, FR-017, FR-018
#
# Uso:
#   parallel-launch.sh emit --repo PATH --feature SHORT [--feature SHORT ...]
#                            [--coordinator-name NAME]
#   parallel-launch.sh check-tmux
#   parallel-launch.sh -h | --help
#
# Decisao de desenho (contract §4): `emit` SOMENTE compoe e imprime os
# comandos — NUNCA executa. Quem executa e o command pai (/agente-00c,
# /agente-00c-resume), que ja tem Bash e ja e o dono da interacao com o
# operador. Isso torna o caminho automatico (com tmux) e o degradado (sem
# tmux) comparaveis byte a byte na parte `claude --name ... "..."` — mesma
# composicao, so envolvida de forma diferente (§4, decisao de desenho).
# INALTERADO por este script: cli/lib/session.sh.
#
# --coordinator-name NAME: aceito e validado por allowlist
# (^cstk-coord/[A-Za-z0-9._-]{1,64}$, <=64 chars) como defesa em
# profundidade (contract §4.1), mas NAO e injetado na composicao emitida —
# a composicao literal do contrato §4.1 nao referencia a coordenadora; o
# encaminhamento do nome da coordenadora ate a sessao-filha para fins de
# notificacao (contract §6) e escopo da prosa de /feature-00c (fase
# posterior desta feature), nao deste helper.
#
# Guarda anti-duplicidade (FR-011): NAO vive aqui — `roadmap-frontier.sh
# --exclude-active-from-repo PATH` (contract roadmap-frontier.md §5) e a
# fonte da guarda, executada ANTES da oferta ao operador. Este script so
# revalida cada --feature (defesa em profundidade, contract §4.2) no
# momento do emit — camada independente da fronteira, custo zero.
#
# POSIX sh puro, sem `jq` (Principio II).
#
# Exit codes:
#   0  sucesso
#   2  uso incorreto (subcomando desconhecido, flag sem valor, --repo
#      ausente, nenhum --feature, --feature ou --coordinator-name
#      mal-formado)
#   3  check-tmux: tmux ausente

set -eu

_PL_NAME="parallel-launch"
_PL_DIR=$(cd "$(dirname "$0")" && pwd)

_PL_SHORT_RE='^[a-z][a-z0-9-]*$'
_PL_CHILD_RE='^cstk-feature/[a-z][a-z0-9-]*$'
_PL_COORD_RE='^cstk-coord/[A-Za-z0-9._-]{1,64}$'

print_usage() {
  cat <<'EOF'
Uso: parallel-launch.sh emit --repo PATH --feature SHORT [--feature SHORT ...]
                              [--coordinator-name NAME]
     parallel-launch.sh check-tmux
     parallel-launch.sh -h | --help

`emit` compoe e IMPRIME (nunca executa) o par de comandos de lancamento de
cada --feature: `cstk session start <SHORT>` + `tmux new-window ...` (ou a
forma degradada `cd ... && claude ...` quando tmux esta ausente). Quem
executa e o chamador (command pai) — este script nunca invoca cli/lib/
session.sh nem qualquer outro comando de efeito colateral.

Opcoes de `emit`:
  --repo PATH             Repositorio coordenador (obrigatorio; deriva
                           <WORKTREE> = <pai-do-repo>/<nome-do-repo>-<SHORT>,
                           mesma derivacao de cli/lib/session.sh:243)
  --feature SHORT         Short-name a lancar (repetivel; >=1 obrigatorio).
                           Revalidado contra ^[a-z][a-z0-9-]*$ (<=64 chars)
                           no momento do emit — defesa em profundidade
                           (exit 2 se nao casar).
  --coordinator-name NAME Nome da sessao coordenadora (opcional), validado
                           contra ^cstk-coord/[A-Za-z0-9._-]{1,64}$ se
                           informado (exit 2 se mal-formado). Nao altera a
                           composicao emitida (ver cabecalho do script).

Guarda anti-duplicidade (FR-011): `emit` recomputa `git -C PATH worktree
list --porcelain` sobre --repo IMEDIATAMENTE antes de compor (janela
TOCTOU, contract §4.2) e PULA (nao compoe, nao imprime) qualquer --feature
que ja tenha worktree ativa, registrando outcome=blocked-duplicate. Isso e
a SEGUNDA camada — a primeira e `roadmap-frontier.sh --exclude-active-from-repo`
(contract roadmap-frontier.md §5), que filtra ANTES da interacao com o
operador. Ausencia de git ou repo sem worktrees => nenhuma exclusao.

`check-tmux`: exit 0 se `tmux` esta disponivel no PATH; exit 3 se ausente.
Nunca aguarda, nunca falha em silencio.

Cada lancamento (ou recusa por --feature invalido) e registrado em
<PATH>/.claude/enforcement-log.jsonl (source: "parallel-launch"), com o
campo `command` filtrado por secrets-filter.sh scrub — best-effort, falha
de log NUNCA aborta o emit.

Exit codes: 0 sucesso; 2 uso incorreto; 3 (check-tmux) tmux ausente.
EOF
}

[ $# -ge 1 ] || { print_usage >&2; exit 2; }

_PL_SUBCOMMAND=$1
shift

# ==== check-tmux ====

_pl_cmd_check_tmux() {
  if command -v tmux >/dev/null 2>&1; then
    exit 0
  fi
  exit 3
}

# ==== helpers de validacao (defesa em profundidade, contract §4.1/§4.2) ====

# _pl_len STRING -> comprimento em chars (via wc -c, normalizado para o \n
# do printf) — mesma tecnica ja usada por roadmap-status.sh.
_pl_len() {
  _pl_l=$(printf '%s' "$1" | wc -c | tr -d ' ')
  printf '%s' "$_pl_l"
}

# _pl_valid_short SHORT -> exit 0 se casa ^[a-z][a-z0-9-]*$ e <=64 chars.
_pl_valid_short() {
  [ "$(_pl_len "$1")" -le 64 ] || return 1
  printf '%s' "$1" | grep -Eq "$_PL_SHORT_RE"
}

# _pl_valid_coordinator NAME -> exit 0 se casa ^cstk-coord/[A-Za-z0-9._-]{1,64}$.
_pl_valid_coordinator() {
  printf '%s' "$1" | grep -Eq "$_PL_COORD_RE"
}

# _pl_valid_child NAME -> exit 0 se casa ^cstk-feature/[a-z][a-z0-9-]*$.
_pl_valid_child() {
  printf '%s' "$1" | grep -Eq "$_PL_CHILD_RE"
}

# ==== TOCTOU-recompute da guarda anti-duplicidade (contract §4.2/2.6.4) ====
#
# `roadmap-frontier.sh --exclude-active-from-repo` ja filtra a oferta ANTES
# da interacao com o operador (contract roadmap-frontier.md §5) — mas essa
# interacao tem duracao ilimitada. `emit` roda imediatamente antes da
# execucao de fato, entao recomputa a MESMA checagem aqui como segunda
# camada (backstop final continua sendo o exit 6 de `cstk session start`,
# cli/lib/session.sh). Mesmo parsing de `git worktree list --porcelain`
# (linha `branch refs/heads/<name>`), independente do de roadmap-frontier.sh
# (scripts distintos, sem dependencia cruzada).
_PL_ACTIVE_BRANCHES=""
_pl_load_active_branches() {
  _pl_lab_repo=$1
  command -v git >/dev/null 2>&1 || return 0
  _pl_lab_out=$(git -C "$_pl_lab_repo" worktree list --porcelain 2>/dev/null) || return 0
  [ -n "$_pl_lab_out" ] || return 0
  _PL_ACTIVE_BRANCHES=$(printf '%s\n' "$_pl_lab_out" | sed -n 's/^branch refs\/heads\///p')
}

# _pl_is_duplicate SHORT -> exit 0 se SHORT ja tem worktree ativa.
# Sentinela nao-newline (".") apos a ultima newline: `$(...)` sempre remove
# newlines finais, o que quebraria o match do ultimo item sem o sentinela
# (mesmo achado documentado em roadmap-frontier.sh).
_pl_is_duplicate() {
  [ -n "$_PL_ACTIVE_BRANCHES" ] || return 1
  _pl_id_target=$1
  case "$(printf '\n%s\n.' "$_PL_ACTIVE_BRANCHES")" in
    *"
$_pl_id_target
"*) return 0 ;;
  esac
  return 1
}

# ==== JSON escaping (paridade com json_escape de roadmap-status.sh, mais
# newline: o campo `command` do enforcement-log e multi-linha) ====
#
# awk (nao sed `:a;N;$!ba`) deliberadamente: o idiolma sed de juntar linhas
# via `N` FALHA silenciosamente (sem imprimir nada) em input de UMA linha
# so no BSD/macOS sed — `N` sem proxima linha disponivel aborta o ciclo sem
# auto-print (comportamento POSIX-estrito, diferente do GNU sed). Achado
# empirico ao testar `--feature` de token unico (sem newline embutido).
# awk processa por registro (linha) sem essa armadilha, em qualquer awk.
_pl_json_escape() {
  printf '%s' "$1" | awk '
    {
      gsub(/\\/, "\\\\");
      gsub(/"/, "\\\"");
      out = out (NR > 1 ? "\\n" : "") $0
    }
    END { printf "%s", out }
  '
}

# ==== enforcement-log.jsonl (contract §4.2, schema CHK125) ====
#
# Best-effort: falha de resolucao de secrets-filter.sh, falha de escrita,
# ou --repo invalido NUNCA abortam o emit (efeito colateral de auditoria,
# nao gate — mesma politica do hook pretooluse-bash-guard.sh).
_pl_write_log() {
  _pl_repo_path=$1
  _pl_wl_short=$2
  _pl_wl_repo_name=$3
  _pl_wl_worktree=$4
  _pl_wl_outcome=$5
  _pl_wl_command=$6

  _pl_sf="$_PL_DIR/secrets-filter.sh"
  if [ -x "$_pl_sf" ]; then
    _pl_wl_cmd_safe=$(printf '%s' "$_pl_wl_command" | "$_pl_sf" scrub 2>/dev/null | cut -c1-2000) \
      || _pl_wl_cmd_safe="[secrets-filter-falhou]"
  else
    _pl_wl_cmd_safe="[secrets-filter indisponivel - comando omitido por seguranca]"
  fi

  _pl_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || _pl_ts=""

  _pl_line=$(printf '{"source":"parallel-launch","timestamp":"%s","short_name":"%s","repo":"%s","worktree_path":"%s","outcome":"%s","command":"%s"}' \
    "$(_pl_json_escape "$_pl_ts")" \
    "$(_pl_json_escape "$_pl_wl_short")" \
    "$(_pl_json_escape "$_pl_wl_repo_name")" \
    "$(_pl_json_escape "$_pl_wl_worktree")" \
    "$(_pl_json_escape "$_pl_wl_outcome")" \
    "$(_pl_json_escape "$_pl_wl_cmd_safe")")

  mkdir -p "$_pl_repo_path/.claude" 2>/dev/null || return 0
  printf '%s\n' "$_pl_line" >>"$_pl_repo_path/.claude/enforcement-log.jsonl" 2>/dev/null || :
  return 0
}

# ==== emit ====

_pl_cmd_emit() {
  _pl_repo=""
  _pl_coordinator=""
  _pl_features=""
  _pl_n_features=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --repo)
        [ $# -ge 2 ] || { printf '%s: --repo exige valor\n' "$_PL_NAME" >&2; exit 2; }
        _pl_repo=$2; shift 2 ;;
      --feature)
        [ $# -ge 2 ] || { printf '%s: --feature exige valor\n' "$_PL_NAME" >&2; exit 2; }
        _pl_features="${_pl_features}${2}
"
        _pl_n_features=$((_pl_n_features + 1))
        shift 2 ;;
      --coordinator-name)
        [ $# -ge 2 ] || { printf '%s: --coordinator-name exige valor\n' "$_PL_NAME" >&2; exit 2; }
        _pl_coordinator=$2; shift 2 ;;
      *)
        printf '%s: flag desconhecida: %s\n' "$_PL_NAME" "$1" >&2
        exit 2 ;;
    esac
  done

  [ -n "$_pl_repo" ] || { printf '%s: --repo obrigatorio\n' "$_PL_NAME" >&2; exit 2; }
  [ "$_pl_n_features" -ge 1 ] || { printf '%s: pelo menos um --feature obrigatorio\n' "$_PL_NAME" >&2; exit 2; }

  if [ -n "$_pl_coordinator" ] && ! _pl_valid_coordinator "$_pl_coordinator"; then
    printf '%s: --coordinator-name invalido (esperado ^cstk-coord/[A-Za-z0-9._-]{1,64}$): %s\n' \
      "$_PL_NAME" "$_pl_coordinator" >&2
    exit 2
  fi

  # Derivacao de <WORKTREE> = <pai-do-repo>/<nome-do-repo>-<SHORT>, mesma
  # derivacao literal de cli/lib/session.sh:243. dirname/basename sao
  # puramente sintaticos — nao exige que --repo exista no disco.
  _pl_parent=$(dirname -- "$_pl_repo")
  _pl_repo_name=$(basename -- "$_pl_repo")

  _pl_have_tmux=false
  if command -v tmux >/dev/null 2>&1; then
    _pl_have_tmux=true
  fi

  # TOCTOU-recompute (contract §4.2/2.6.4) — segunda camada da guarda
  # anti-duplicidade, independente de roadmap-frontier.sh, no momento mais
  # proximo possivel da execucao de fato.
  _pl_load_active_branches "$_pl_repo"

  IFS='
'
  for _pl_short in $_pl_features; do
    unset IFS
    [ -n "$_pl_short" ] || continue

    if ! _pl_valid_short "$_pl_short"; then
      printf '%s: --feature invalido (esperado ^[a-z][a-z0-9-]*$, <=64 chars): %s\n' \
        "$_PL_NAME" "$_pl_short" >&2
      _pl_write_log "$_pl_repo" "$_pl_short" "$_pl_repo_name" "" \
        "blocked-invalid-feature" "" || :
      exit 2
    fi

    _pl_worktree="$_pl_parent/$_pl_repo_name-$_pl_short"
    _pl_child="cstk-feature/$_pl_short"

    if _pl_is_duplicate "$_pl_short"; then
      printf '%s: %s ja tem worktree ativa em %s — lancamento bloqueado (guarda anti-duplicidade)\n' \
        "$_PL_NAME" "$_pl_short" "$_pl_repo" >&2
      _pl_write_log "$_pl_repo" "$_pl_short" "$_pl_repo_name" "$_pl_worktree" \
        "blocked-duplicate" "" || :
      continue
    fi

    if ! _pl_valid_child "$_pl_child"; then
      # Nao deveria ocorrer (SHORT ja validado acima constroi um valor que
      # sempre casa) — defesa em profundidade contra regressao futura no
      # padrao de composicao.
      printf '%s: <CHILD_NAME> composto invalido (bug interno): %s\n' \
        "$_PL_NAME" "$_pl_child" >&2
      exit 2
    fi

    # Composicao compartilhada (byte a byte identica nos dois caminhos —
    # contract §4, decisao de desenho: US1 automatico e US3 degradado
    # comparaveis).
    _pl_claude_argv=$(printf 'claude --name "%s" "/feature-00c %s"' "$_pl_child" "$_pl_short")

    _pl_line1=$(printf 'cstk session start %s' "$_pl_short")
    if $_pl_have_tmux; then
      _pl_line2=$(printf 'tmux new-window -c "%s" -n "%s" -P -F '"'"'#{pane_id}'"'"' \\\n  %s' \
        "$_pl_worktree" "$_pl_short" "$_pl_claude_argv")
    else
      _pl_line2=$(printf 'cd "%s" && %s' "$_pl_worktree" "$_pl_claude_argv")
    fi

    printf '%s\n%s\n' "$_pl_line1" "$_pl_line2"

    _pl_write_log "$_pl_repo" "$_pl_short" "$_pl_repo_name" "$_pl_worktree" \
      "launched" "$(printf '%s\n%s' "$_pl_line1" "$_pl_line2")" || :
  done
}

case "$_PL_SUBCOMMAND" in
  emit)
    _pl_cmd_emit "$@" ;;
  check-tmux)
    _pl_cmd_check_tmux ;;
  -h|--help)
    print_usage; exit 0 ;;
  *)
    printf '%s: subcomando desconhecido: %s\n' "$_PL_NAME" "$_PL_SUBCOMMAND" >&2
    print_usage >&2
    exit 2 ;;
esac
