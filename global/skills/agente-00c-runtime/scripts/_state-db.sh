#!/bin/sh
# _state-db.sh — helpers sourceaveis compartilhados do backend SQLite do
# state.db (FASE 3 task 3.1).
#
# Ref: docs/specs/state-db-foundation/tasks.md FASE 3, task 3.1
#      docs/specs/state-db-foundation/contracts/primitives.md §C5 (PRAGMAs),
#      §C6 (concorrencia), §C8 (escape de texto livre), §C9 (permissoes)
#
# NAO e executavel diretamente. Use:
#   . "$(dirname -- "$0")/_state-db.sh"
#
# Funcoes expostas:
#   sql_escape VALUE                    -> imprime VALUE com ' duplicado
#   strip_nul                           -> le stdin, imprime sem bytes NUL
#   _state_db_pragmas [BUSY_MS]         -> imprime "PRAGMA foreign_keys=ON;"
#                                          + "PRAGMA busy_timeout=<BUSY_MS>;"
#                                          (default 5000)
#   _state_db_exec DB SQL [BUSY_MS]     -> invoca sqlite3 com os PRAGMAs de
#                                          C5 SEMPRE prefixados ao SQL da
#                                          mutacao (stdin -> sqlite3 -- DB)
#   _state_db_exec_with_retry DB SQL [BUSY_MS]
#                                        -> _state_db_exec com retry/backoff
#                                          sob "database is locked"/"is
#                                          busy"/"locking protocol" (ate 4
#                                          tentativas, backoff com jitter
#                                          por-PID). CONTRATO DE FALHA
#                                          DIFERENTE de
#                                          recall_apply_sql_with_retry
#                                          (cli/lib/recall.sh): lock
#                                          persistente apos as 4 tentativas
#                                          MUST sair nao-zero — callers desta
#                                          funcao NUNCA devem engolir esse
#                                          retorno (C6). recall.sh degrada
#                                          silenciosamente porque seu indice
#                                          e derivado/best-effort; o state.db
#                                          e fonte de verdade transacional e
#                                          NAO pode.
#   _state_db_secure_perms DB           -> chmod 600 em DB + sidecars WAL
#                                          (-wal/-shm), best-effort (C9)
#
# Nota de deploy (por que sql_escape/strip_nul sao uma copia, nao um source
# cross-boundary de cli/lib/recall.sh): cli/lib/ (runtime `cstk`, atualizado
# via `cstk self-update`, instalado em ~/.local) e global/skills/ (catalogo
# de skills, atualizado via `cstk install`/`cstk update`, instalado em
# ~/.claude) sao duas unidades de deploy INDEPENDENTES — ver CLAUDE.md "cstk
# install vs self-update". `source`-ar um arquivo do catalogo de skills a
# partir de cli/lib (ou vice-versa) acopla runtimes que podem estar em
# versoes diferentes num dado momento (um `self-update` sem `update`
# correspondente, ou vice-versa), quebrando silenciosamente se o outro lado
# nao existir no ambiente (ex.: `cstk` standalone sem catalogo de skills
# instalado). recall.sh ja segue este principio: consome secrets-filter.sh
# (agente-00c-runtime/scripts) como SUBPROCESSO resolvido em runtime, nunca
# via `source`. Por isso sql_escape/strip_nul permanecem definidas nos dois
# lados com o MESMO algoritmo (nao uma reimplementacao alternativa) —
# paridade garantida por tests/test__state-db.sh (compara byte-a-byte a saida
# das duas copias para o mesmo conjunto de payloads, incluindo o payload
# hostil de C8) em vez de acoplamento em tempo de execucao.

# sql_escape VALUE -> imprime VALUE com aspas simples duplicadas (' -> '').
# Copia identica ao algoritmo de cli/lib/recall.sh:215-218 (ver nota acima).
sql_escape() {
  printf '%s' "$1" | sed "s/'/''/g"
}

# strip_nul reads stdin -> imprime stdin sem bytes NUL.
# Copia identica ao algoritmo de cli/lib/recall.sh:347-349 (ver nota acima).
strip_nul() {
  tr -d '\000'
}

# _state_db_pragmas [BUSY_MS] -> imprime os PRAGMAs obrigatorios de C5.
# Diferente de recall_pragmas (cli/lib/recall.sh): aqui foreign_keys=ON
# (state.db e fonte de verdade transacional com FKs reais entre as 9
# entidades) em vez de OFF (recall.sh e um indice derivado sem FK).
_state_db_pragmas() {
  _sdb_ms="${1:-5000}"
  printf 'PRAGMA foreign_keys=ON;\n'
  printf 'PRAGMA busy_timeout=%s;\n' "$_sdb_ms"
}

# _state_db_exec DB SQL [BUSY_MS] -> aplica SQL sobre DB com os PRAGMAs de
# C5 sempre prefixados. stdin/stdout/stderr do sqlite3 sao preservados
# (caller decide se quer capturar). Exit: o do sqlite3 (0 sucesso).
_state_db_exec() {
  _sde_db="$1"
  _sde_sql="$2"
  _sde_ms="${3:-5000}"
  { _state_db_pragmas "$_sde_ms"; printf '%s\n' "$_sde_sql"; } | sqlite3 -- "$_sde_db"
}

# _state_db_backoff_sleep TRY -> dorme ~TRY segundos + jitter fracionario
# [0,1)s derivado do PID (evita thundering herd entre escritores que
# colidiram no mesmo instante). Mesmo algoritmo de recall_backoff_sleep
# (cli/lib/recall.sh) — duplicado pela mesma razao de fronteira de deploy
# documentada no cabecalho deste arquivo.
_state_db_backoff_sleep() {
  _sdbo_base="$1"
  _sdbo_frac=$(awk -v p="$$" -v t="$_sdbo_base" 'BEGIN{srand(p*7+t); printf "%02d", int(rand()*100)}' 2>/dev/null)
  [ -n "$_sdbo_frac" ] || _sdbo_frac="00"
  sleep "${_sdbo_base}.${_sdbo_frac}" 2>/dev/null || sleep "$_sdbo_base"
}

# _state_db_exec_with_retry DB SQL [BUSY_MS] -> _state_db_exec com retry sob
# lock (ate 4 tentativas). CONTRATO DE FALHA: retorna 1 se esgotar as
# tentativas (lock persistente) OU se o erro nao for de lock — em AMBOS os
# casos o stderr da ultima tentativa e ecoado em stderr desta funcao para
# diagnostico. Callers MUST propagar esse retorno como falha dura (exit
# nao-zero do script), nunca best-effort/silencioso — diferenca deliberada
# face a recall_apply_sql_with_retry (ver nota do cabecalho, C6).
_state_db_exec_with_retry() {
  _sder_db="$1"
  _sder_sql="$2"
  _sder_ms="${3:-5000}"
  _sder_try=1
  while [ "$_sder_try" -le 4 ]; do
    _sder_err=$(_state_db_exec "$_sder_db" "$_sder_sql" "$_sder_ms" 2>&1 >/dev/null) && return 0
    case "$_sder_err" in
      *"database is locked"*|*"database is busy"*|*"locking protocol"*)
        _state_db_backoff_sleep "$_sder_try"
        _sder_try=$((_sder_try + 1))
        ;;
      *)
        [ -n "$_sder_err" ] && printf '%s\n' "$_sder_err" >&2
        return 1
        ;;
    esac
  done
  [ -n "${_sder_err:-}" ] && printf '%s\n' "$_sder_err" >&2
  return 1
}

# _state_db_secure_perms DB -> chmod 600 em DB e nos sidecars WAL
# (-wal/-shm), best-effort (sidecar pode nao existir ainda). Padrao ja usado
# em otel-usage.sh:262 e state-db-schema.sh — C9, finding S3.
_state_db_secure_perms() {
  _sdsp_db="$1"
  chmod 600 -- "$_sdsp_db" 2>/dev/null || :
  chmod 600 -- "$_sdsp_db-wal" 2>/dev/null || :
  chmod 600 -- "$_sdsp_db-shm" 2>/dev/null || :
}
