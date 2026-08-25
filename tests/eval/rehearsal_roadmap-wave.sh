#!/bin/sh
# rehearsal_roadmap-wave.sh — ensaio geral SUPERVISIONADO da leva paralela
# (Camada D do plano de e2e; fora do gate, fora do runner).
#
# O fluxo completo com filhas REAIS: /roadmap-wave --yes lanca janelas
# tmux com `claude` de verdade rodando /feature-00c em worktrees; as
# filhas percorrem a pipeline SDD inteira; o operador media merges e
# fechamentos. Este script NAO invoca modelo algum — ele e o par de
# bookends mecanicos em volta do ensaio:
#
#   setup  [--dir DIR]   monta o projeto de brinquedo (briefing +
#                        constitution ratificada + roadmap com 2 features
#                        triviais e independentes) e imprime o runbook
#   status --dir DIR     snapshot mecanico mid-flight (worktrees, branches,
#                        roadmap-status, states das filhas, janelas tmux)
#   verify --dir DIR     assercoes finais: exit 0 so se worktrees zeradas,
#                        branches removidas, roadmap 100% concluido, state
#                        00c de CADA feature preservado no principal e
#                        working tree limpa
#
# Ref: CLAUDE.md §"Modo roadmap + leva paralela de features"
#      plugins/cstk/commands/roadmap-wave.md
#      tests/test_e2e_roadmap_wave.sh (Camada B — plumbing deterministico)
#      tests/eval/eval_roadmap-wave-frontier.sh (Camada C — obediencia headless)
#
# Custa tokens reais e horas de parede (cada filha roda a pipeline SDD
# completa). Rodar 1x por release que toque orquestracao paralela.
# Exit (status/verify): 0 ok · 1 divergencia · 2 nao avaliavel/uso.

set -u

REH_ROOT=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$REH_ROOT/../.." && pwd)
RSTATUS="$REPO_ROOT/plugins/cstk/skills/review-features/scripts/roadmap-status.sh"

_say()  { printf '%s\n' "$*"; }
_err()  { printf 'rehearsal: %s\n' "$*" >&2; }
_usage() {
  cat >&2 <<'EOF'
Uso: rehearsal_roadmap-wave.sh setup  [--dir DIR]
     rehearsal_roadmap-wave.sh status --dir DIR
     rehearsal_roadmap-wave.sh verify --dir DIR
EOF
  exit 2
}

[ $# -ge 1 ] || _usage
_CMD=$1; shift

_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) [ $# -ge 2 ] || _usage; _DIR=$2; shift 2 ;;
    *) _usage ;;
  esac
done

# _roadmap_shorts DIR: short-names das entradas do roadmap, um por linha
# (via roadmap-status.sh --json do REPO — mesma fonte da fronteira).
_roadmap_shorts() {
  sh "$RSTATUS" --roadmap "$1/docs/roadmap.md" --specs-dir "$1/docs/specs" --json 2>/dev/null \
    | sed -n 's/.*"short_name":"\([^"]*\)".*/\1/p'
}

# ==== setup ====

_cmd_setup() {
  if [ -z "$_DIR" ]; then
    _DIR=$(mktemp -d -t 'cstk-rehearsal.XXXXXX') || { _err "mktemp falhou"; exit 2; }
  fi
  command -v git >/dev/null 2>&1 || { _err "git indisponivel"; exit 2; }
  mkdir -p "$_DIR/docs"
  ( cd "$_DIR" && git init -q -b main \
    && git config user.email rehearsal@local && git config user.name rehearsal ) \
    || { _err "git init falhou em $_DIR"; exit 2; }

  printf '.claude/\n' > "$_DIR/.gitignore"

  cat > "$_DIR/docs/briefing.md" <<'EOF'
# Project Briefing: Toolbox de Terminal

## 1. Visao e Proposito
Par de utilitarios POSIX triviais para o terminal, usados como projeto de
ensaio da leva paralela do cstk. Uso pessoal, offline, sem rede.

## 2. Usuarios e Stakeholders
Um unico usuario: o proprio operador do ensaio.

## 3. Escopo
Dois scripts independentes entre si: um que cumprimenta (`greet.sh`) e um
que imprime a versao do toolbox (`version.sh`). Sem interface grafica,
sem API, sem persistencia.

## 4. Prioridades e Trade-offs
Simplicidade e rapidez de entrega acima de tudo — cada feature deve caber
em poucas tasks triviais.

## 5. Restricoes
POSIX shell puro, sem dependencias externas.

## 6. Stack Tecnica
Shell script POSIX.

## 7. Qualidade e Padroes
Um teste simples por script.

## 8. Visao de Futuro
Nenhuma.
EOF

  cat > "$_DIR/docs/constitution.md" <<'EOF'
# Constitution: Toolbox de Terminal

## Core Principles

### I. Simplicidade
Cada feature MUST caber em um unico script POSIX.

### II. Veracidade de Dados
Nenhum valor factual pode ser inventado.

**Version**: 1.0.0 | **Ratified**: 2026-08-25 | **Last Amended**: 2026-08-25
EOF

  cat > "$_DIR/docs/roadmap.md" <<'EOF'
# Roadmap

### 1. greet-cli
- **depende-de**: -

Script `greet.sh` que imprime uma saudacao com o nome recebido como
argumento (default: "mundo").

### 2. version-cli
- **depende-de**: -

Script `version.sh` que imprime a versao do toolbox lida de um arquivo
`VERSION` na raiz.
EOF

  ( cd "$_DIR" && git add -A && git commit -qm "seed ensaio leva paralela" ) \
    || { _err "commit seed falhou"; exit 2; }

  cat <<EOF

Projeto de ensaio pronto em:

    $_DIR

RUNBOOK (operador no comando; cada passo abaixo e manual de proposito):

 1. Dentro de uma sessao tmux, abra o claude coordenador no projeto:
        cd $_DIR && claude
 2. No coordenador, lance a leva:
        /roadmap-wave --yes --max 2
    Esperado: 2 janelas tmux (greet-cli, version-cli), cada uma com uma
    filha /feature-00c rodando em worktree propria.
 3. Acompanhe quando quiser (daqui, fora do tmux):
        $0 status --dir $_DIR
    As filhas notificam o coordenador via SendMessage ao terminar
    ([cstk-parallel] feature=.. outcome=..).
 4. Para CADA filha concluida: merge da branch no main (ou PR, se criou
    remote) e fechamento SEMPRE via
        cd $_DIR && cstk session end <short>
    (nunca git worktree remove cru — o end preserva o state 00c).
 5. Bookend final (mecanico, exit 0/1):
        $0 verify --dir $_DIR

Kill switch de uma filha: tmux kill-window -t <janela> +
cstk session end <short>.
EOF
}

# ==== status ====

_cmd_status() {
  [ -n "$_DIR" ] || _usage
  [ -d "$_DIR/.git" ] || { _err "nao e um repo git: $_DIR"; exit 2; }

  _say "== worktrees =="
  git -C "$_DIR" worktree list 2>/dev/null || :
  _say ""
  _say "== branches =="
  git -C "$_DIR" branch --list 2>/dev/null || :
  _say ""
  _say "== roadmap-status (derivado de docs/specs/ do MAIN) =="
  sh "$RSTATUS" --roadmap "$_DIR/docs/roadmap.md" --specs-dir "$_DIR/docs/specs" 2>&1 || :
  _say ""
  _say "== states 00c das filhas (worktrees ativas) =="
  _found=0
  for _wt in "$(dirname -- "$_DIR")/$(basename -- "$_DIR")"-*; do
    [ -d "$_wt" ] || continue
    _found=1
    for _sd in "$_wt/.claude/feature-00c-state"/*; do
      [ -d "$_sd" ] || continue
      _short=$(basename -- "$_sd")
      if [ -f "$_sd/state.json" ] && command -v jq >/dev/null 2>&1; then
        _st=$(jq -r '.execution.status // .status // "?"' "$_sd/state.json" 2>/dev/null)
      elif [ -f "$_sd/state.db" ]; then
        _st="state.db presente (use state-rw.sh get para detalhe)"
      else
        _st="sem state"
      fi
      _say "  $_short: $_st  ($_wt)"
    done
  done
  [ "$_found" = 1 ] || _say "  (nenhuma worktree ativa)"
  _say ""
  _say "== janelas tmux (best-effort) =="
  tmux list-windows -a -F '#{session_name}:#{window_name}' 2>/dev/null || _say "  (sem servidor tmux acessivel)"
}

# ==== verify ====

_cmd_verify() {
  [ -n "$_DIR" ] || _usage
  [ -d "$_DIR/.git" ] || { _err "nao e um repo git: $_DIR"; exit 2; }
  _v_fail=0

  _shorts=$(_roadmap_shorts "$_DIR")
  if [ -z "$_shorts" ]; then
    _err "roadmap sem entradas legiveis em $_DIR/docs/roadmap.md"
    exit 2
  fi

  # 1. Nenhuma worktree alem do checkout principal.
  _wt=$(git -C "$_DIR" worktree list --porcelain 2>/dev/null | grep -c '^worktree ')
  if [ "$_wt" = 1 ]; then
    _say "PASS worktrees: so o checkout principal"
  else
    _say "FAIL worktrees: $_wt ativas (esperado 1) — feche com cstk session end"
    _v_fail=1
  fi

  # 2. Branches das features removidas (end fecha branch apos merge).
  for _s in $_shorts; do
    if git -C "$_DIR" show-ref --verify -q "refs/heads/$_s"; then
      _say "FAIL branch: $_s ainda existe — merge + cstk session end pendentes"
      _v_fail=1
    else
      _say "PASS branch: $_s removida"
    fi
  done

  # 3. Roadmap 100% concluido (derivado de docs/specs/ no MAIN).
  _pend=$(sh "$RSTATUS" --roadmap "$_DIR/docs/roadmap.md" \
      --specs-dir "$_DIR/docs/specs" --json 2>/dev/null \
    | grep -cv '"status":"concluida"')
  if [ "$_pend" = 0 ]; then
    _say "PASS roadmap: todas as entradas concluida"
  else
    _say "FAIL roadmap: $_pend entrada(s) nao-concluida no main"
    _v_fail=1
  fi

  # 4. State 00c de CADA feature preservado no checkout principal
  #    (session-end-state-preservation).
  for _s in $_shorts; do
    if [ -f "$_DIR/.claude/feature-00c-state/$_s/state.json" ] \
      || [ -f "$_DIR/.claude/feature-00c-state/$_s/state.db" ]; then
      _say "PASS state: feature-00c-state/$_s preservado no principal"
    elif [ -d "$_DIR/.claude/session-state-backup/$_s" ]; then
      _say "PASS state: $_s preservado em session-state-backup/ (houve colisao)"
    else
      _say "FAIL state: nenhum state 00c de $_s no principal — end rodou com --discard-state ou worktree foi removida crua?"
      _v_fail=1
    fi
  done

  # 5. Working tree do principal limpa.
  if [ -z "$(git -C "$_DIR" status --porcelain 2>/dev/null)" ]; then
    _say "PASS git: working tree do principal limpa"
  else
    _say "FAIL git: working tree do principal suja"
    _v_fail=1
  fi

  if [ "$_v_fail" = 0 ]; then
    _say ""
    _say "RESULT|rehearsal_roadmap-wave|conforme"
    exit 0
  fi
  _say ""
  _say "RESULT|rehearsal_roadmap-wave|divergente"
  exit 1
}

case "$_CMD" in
  setup)  _cmd_setup ;;
  status) _cmd_status ;;
  verify) _cmd_verify ;;
  -h|--help) _usage ;;
  *) _err "subcomando desconhecido: $_CMD"; _usage ;;
esac
