#!/bin/sh
# _state-read.sh — sibling sourceable de materializacao de estado legivel
# (feature state-db-runtime-parity, FASE 1 task 1.2).
#
# Ref: docs/specs/state-db-runtime-parity/contracts/runtime-interfaces.md §4
#      docs/specs/state-db-runtime-parity/research.md Decision 1
#      spec FR-001/FR-003/FR-004/FR-012
#
# NAO e executavel diretamente. Sourced pelos leitores do runtime que hoje
# constroem o path `state.json` na mao (budget.sh, drift.sh, cycles.sh, ...):
#
#   . "$(dirname -- "$0")/_state-read.sh"
#   sf=$(state_read_materialize "$STATE_DIR")   # imprime path legivel por jq
#   trap state_read_cleanup EXIT INT TERM        # remove tmps materializados
#
# Garantias (contract §4):
#   - state-dir JSON: devolve o path do proprio `state.json` (FR-004, zero
#     mudanca — NAO checa existencia; cada consumidor preserva seu proprio
#     tratamento de "state.json ausente").
#   - state-dir SQLite (state.db presente): materializa o documento via
#     `state-rw.sh read` num mktemp 0600 FORA do state-dir (LOW/A04 do
#     plan) e imprime o path do tmp.
#   - NUNCA cria arquivo dentro do state-dir (FR-003, anti-mirror).
#   - Falha do `state-rw.sh read` (ex.: `sqlite3` ausente no host, state.db
#     corrompido): propaga exit code e stderr do read — nunca degrada mudo
#     (FR-012); nenhum tmp orfao sobra.
#
# Resolucao do state-rw.sh: sibling de `$0` (todos os consumidores vivem no
# MESMO diretorio de scripts do runtime — research Decision 6). Callers
# fora do diretorio (ex.: testes) podem sobrescrever via STATE_READ_RW.
#
# Rastreio de tmps por PID (nao por variavel de shell): o uso canonico e
# `sf=$(state_read_materialize ...)` — command substitution roda em
# SUBSHELL, logo estado de variavel setado la nunca chegaria ao shell que
# executa o trap. `$$` em subshell POSIX preserva o PID do shell principal,
# entao o template `state-read.$$.XXXXXX` permite ao cleanup (no trap do
# shell principal, mesmo `$$`) remover exatamente os tmps desta sessao.

_state_read_rw_bin() {
  if [ -n "${STATE_READ_RW:-}" ]; then
    printf '%s\n' "$STATE_READ_RW"
    return 0
  fi
  printf '%s/state-rw.sh\n' "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
}

# state_read_materialize DIR -> imprime em stdout um path legivel por jq.
# Exit: 0 sucesso; 2 uso (DIR vazio); exit do `state-rw.sh read` em falha
# de materializacao sob SQLite (propagacao FR-012).
state_read_materialize() {
  _srm_sd=$1
  if [ -z "$_srm_sd" ]; then
    printf 'state-read: state-dir obrigatorio\n' >&2
    return 2
  fi
  # Selecao de backend em paridade com _sr_backend (state.db presente =>
  # sqlite; senao json).
  if [ ! -f "$_srm_sd/state.db" ]; then
    printf '%s/state.json\n' "$_srm_sd"
    return 0
  fi
  # Backend SQLite: materializa FORA do state-dir (mktemp em TMPDIR do
  # sistema; mktemp cria 0600 — chmod defensivo para hosts com umask
  # exotica). Anti-mirror por construcao: nenhum path dentro do state-dir.
  # Template com path completo (nao `-t`): portavel GNU/BSD — o mktemp do
  # macOS trata o arg de -t como prefixo literal sem substituir os X.
  _srm_tmp=$(mktemp "${TMPDIR:-/tmp}/state-read.$$.XXXXXX" 2>/dev/null) || {
    printf 'state-read: mktemp falhou (TMPDIR indisponivel?)\n' >&2
    return 1
  }
  chmod 600 "$_srm_tmp" 2>/dev/null || :
  _srm_rw=$(_state_read_rw_bin)
  _srm_rc=0
  "$_srm_rw" read --state-dir "$_srm_sd" > "$_srm_tmp" || _srm_rc=$?
  if [ "$_srm_rc" -ne 0 ]; then
    # Propaga a falha rapida do read (FR-012 — sqlite3 ausente, state.db
    # corrompido...): stderr do read ja foi emitido; remove o tmp parcial.
    rm -f -- "$_srm_tmp" 2>/dev/null || :
    return "$_srm_rc"
  fi
  printf '%s\n' "$_srm_tmp"
}

# state_read_cleanup — remove todos os tmps materializados nesta sessao
# (processo corrente, inclusive os criados dentro de $(...) — ver nota de
# rastreio por PID no header). Idempotente; seguro como handler de
# `trap ... EXIT INT TERM`. Exit 0 sempre (cleanup nunca mascara o exit
# code do caller no trap EXIT).
state_read_cleanup() {
  rm -f -- "${TMPDIR:-/tmp}/state-read.$$."* 2>/dev/null || :
  return 0
}
