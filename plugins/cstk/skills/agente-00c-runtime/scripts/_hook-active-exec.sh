#!/bin/sh
# _hook-active-exec.sh — helper sourceable de deteccao tri-estado de
# execucao ativa (agente-00c/feature-00c), agnostico ao backend de
# persistencia (`state.json` / `state.db`). Feature `hooks-db-parity`.
#
# Ref: docs/specs/hooks-db-parity/contracts/hook-active-exec.md
#      docs/specs/hooks-db-parity/research.md Decision 1/1.a/2
#      docs/specs/hooks-db-parity/spec.md FR-001..FR-008
#
# NAO e executavel diretamente. Os 3 hooks do runtime 00C (task 3.1/4.1/5.1,
# FASES 3-5) sourceiam este arquivo apos o pre-check inline (SEC-H1) e a
# cadeia de resolucao com ordem invertida (contract §"Ordem MODIFICADA"):
#
#   . "$_helper"
#   _out=$(hook_active_exec "$CWD"); _rc=$?
#
# Uso do parametro OPCIONAL de busy_timeout (SEC-M2 — politica DIFERENCIADA
# por hook, task 1.6/CHK027): a assinatura documentada no contrato e
# `hook_active_exec <cwd>` (1 parametro). Este helper e sourceado por 3
# hooks com politicas de contencao DISTINTAS (guarda: 200ms tolera a espera
# plena; metricas: 50ms, sob risco de estourar sozinhas o teto do gate de
# 150ms). Para nao inflar a assinatura documentada nem duplicar o arquivo
# por hook, o valor e passado por variavel de ambiente opcional definida
# PELO CALLER antes de invocar a funcao:
#
#   HAE_BUSY_TIMEOUT_MS=50 _out=$(hook_active_exec "$CWD"); _rc=$?
#
# Default se omitido: 200 (o valor do hook fail-closed — mais conservador
# na ausencia de indicacao explicita do caller).
#
# Exit codes (contract):
#   0 = ativa        stdout: "<execution_kind>\t<state_dir>\t<backend>"
#   1 = inativa      stdout vazio (inclui G4: nenhum state presente)
#   2 = indeterminada stdout vazio
#   3 = uso incorreto (cwd vazio) stdout vazio
# stderr: SEMPRE vazio (erros de sqlite3/jq suprimidos com 2>/dev/null e
# traduzidos para exit 2 — requisito duro do contrato).
#
# Garantias G1-G10 do contrato: ver docs/specs/hooks-db-parity/contracts/
# hook-active-exec.md. G7 (nenhuma escrita/criacao de arquivo pelo HELPER):
# o fallback de abertura do sqlite3 (path direto) pode legitimamente criar
# `state.db-shm`/`state.db-wal` — artefatos internos do proprio motor SQLite
# (research.md Decision 1.a, "Nota de escopo"), NAO uma copia espelhada do
# estado; G7 continua satisfeita.
#
# G10 (Constitution II carve-out 1.1.0(b)): esta e a UNICA mencao a
# `sqlite3` fora da camada de estado transacional (`_state-db.sh`,
# `state-rw.sh` e afins) — confinamento deliberado (research.md Decision 5).

# SEC-M3: teto defensivo de state-dirs sondados por invocacao. Task 1.4:
# medicao empirica real neste repositorio (23 dirs organicos hoje, ~5.2
# ms/dir, ~119ms total) -> 100 da ~4x de margem antes de acionar o teto.
# Estourar o teto ANTES de confirmar `ativa` produz o mesmo outcome de um
# `state.db` ilegivel: `indeterminada` (exit 2), nunca `inativa` (FR-003).
_HAE_MAX_DIRS=100

# _hae_status_active STATUS -> 0 se em_andamento/aguardando_humano (G3).
_hae_status_active() {
  case "$1" in
    em_andamento | aguardando_humano) return 0 ;;
    *) return 1 ;;
  esac
}

# _hae_escape_uri_path PATH -> imprime PATH com `%`, `?`, `#` percent-
# encoded (SEC-M1 — nunca interpolar o path cru numa URI `file:...`).
# Ordem importa: escapar `%` PRIMEIRO evita re-escapar os `%XX` recem
# inseridos pelas duas regras seguintes.
_hae_escape_uri_path() {
  printf '%s' "$1" | sed -e 's/%/%25/g' -e 's/?/%3F/g' -e 's/#/%23/g'
}

# _hae_sqlite_query DB BUSY_MS -> imprime o resultado de
# "SELECT status FROM execution LIMIT 1;" em stdout; exit 0 sucesso
# (inclusive result-set vazio), exit != 0 se o DB nao pode ser aberto/lido.
# stderr sempre suprimido pelo caller (2>/dev/null).
#
# Ordem de abertura (research Decision 1.a): 1) `file:<db>?mode=ro` (zero
# efeito colateral, mas falha se -shm/-wal ainda nao existirem); 2)
# fallback path direto (sempre funciona; pode criar -shm/-wal, artefatos
# legitimos do motor — ver nota de escopo no cabecalho, G7).
#
# Supressao do eco do PRAGMA busy_timeout (gotcha documentado em
# _state-db.sh: `.output /dev/null` ... `.output stdout` em volta do
# PRAGMA, senao o valor do busy_timeout aparece como primeira linha do
# resultado, corrompendo silenciosamente a leitura do status).
_hae_sqlite_query() {
  _hae_sq_db="$1"
  _hae_sq_busy="$2"
  _hae_sq_sql=$(
    printf '.output /dev/null\n'
    printf 'PRAGMA busy_timeout=%s;\n' "$_hae_sq_busy"
    printf '.output stdout\n'
    printf 'SELECT status FROM execution LIMIT 1;\n'
  )
  _hae_sq_uri="file:$(_hae_escape_uri_path "$_hae_sq_db")?mode=ro"
  if _hae_sq_out=$(printf '%s' "$_hae_sq_sql" | sqlite3 "$_hae_sq_uri" 2>/dev/null); then
    printf '%s' "$_hae_sq_out"
    return 0
  fi
  if _hae_sq_out=$(printf '%s' "$_hae_sq_sql" | sqlite3 -- "$_hae_sq_db" 2>/dev/null); then
    printf '%s' "$_hae_sq_out"
    return 0
  fi
  return 1
}

# _hae_resolve_dir_status DIR -> assinala globais _HAE_WORD (active |
# inactive | indeterminate | absent) e _HAE_BACKEND (sqlite | json | "").
# G2: dentro de um mesmo state-dir, state.db vence sobre state.json.
# G5: state.db presente + sqlite3 ausente/DB ilegivel => indeterminate,
# jamais inactive. G4: nem state.db nem state.json presentes => absent
# (o caller trata absent como "nao conta para o teto, nao seta indet").
_hae_resolve_dir_status() {
  _hae_rd_dir="$1"
  _hae_rd_busy="$2"

  if [ -f "$_hae_rd_dir/state.db" ]; then
    _HAE_BACKEND="sqlite"
    if ! command -v sqlite3 >/dev/null 2>&1; then
      _HAE_WORD="indeterminate"
      return 0
    fi
    if _hae_rd_status=$(_hae_sqlite_query "$_hae_rd_dir/state.db" "$_hae_rd_busy"); then
      _hae_rd_status=$(printf '%s' "$_hae_rd_status" | tr -d '[:space:]')
      if _hae_status_active "$_hae_rd_status"; then
        _HAE_WORD="active"
      else
        _HAE_WORD="inactive"
      fi
    else
      _HAE_WORD="indeterminate"
    fi
    return 0
  fi

  if [ -f "$_hae_rd_dir/state.json" ]; then
    _HAE_BACKEND="json"
    if ! command -v jq >/dev/null 2>&1; then
      _HAE_WORD="indeterminate"
      return 0
    fi
    if _hae_rd_status=$(jq -r '.execution.status // ""' "$_hae_rd_dir/state.json" 2>/dev/null); then
      if _hae_status_active "$_hae_rd_status"; then
        _HAE_WORD="active"
      else
        _HAE_WORD="inactive"
      fi
    else
      _HAE_WORD="indeterminate"
    fi
    return 0
  fi

  _HAE_WORD="absent"
  _HAE_BACKEND=""
  return 0
}

# hook_active_exec CWD -> ver contrato no cabecalho deste arquivo.
hook_active_exec() {
  _hae_cwd="${1:-}"
  if [ -z "$_hae_cwd" ]; then
    return 3
  fi
  _hae_busy="${HAE_BUSY_TIMEOUT_MS:-200}"

  _hae_had_indet=0
  _hae_probed=0

  # ---- G1: agente-00c-state vence sobre qualquer feature-00c ----
  _hae_a_dir="$_hae_cwd/.claude/agente-00c-state"
  if [ -f "$_hae_a_dir/state.db" ] || [ -f "$_hae_a_dir/state.json" ]; then
    _hae_probed=$((_hae_probed + 1))
    _hae_resolve_dir_status "$_hae_a_dir" "$_hae_busy"
    case "$_HAE_WORD" in
      active)
        printf 'agente-00c\t%s\t%s\n' "$_hae_a_dir" "$_HAE_BACKEND"
        return 0
        ;;
      indeterminate)
        _hae_had_indet=1
        ;;
    esac
  fi

  # ---- G1: entre feature-00c, menor short-name (LC_ALL=C) vence ----
  # SEC-M3: ordenar os nomes ANTES de sondar, parar no primeiro ativo.
  # Ordenar primeiro e depois varrer em ordem crescente ate o primeiro
  # `ativo` produz o mesmo resultado que "coletar todos os ativos e
  # ordenar no fim" (Decision 2) porque so o menor short-name ATIVO
  # importa — mas com early-exit, sem sondar alem do necessario.
  _hae_feat_root="$_hae_cwd/.claude/feature-00c-state"
  _hae_names=""
  if [ -d "$_hae_feat_root" ]; then
    for _hae_d in "$_hae_feat_root"/*/; do
      [ -d "$_hae_d" ] || continue
      _hae_names="${_hae_names}$(basename "$_hae_d")
"
    done
  fi

  if [ -n "$_hae_names" ]; then
    _hae_sorted=$(printf '%s' "$_hae_names" | LC_ALL=C sort)
    _hae_oldifs=$IFS
    IFS='
'
    set -f
    # shellcheck disable=SC2086 # split deliberado por linha, IFS=newline acima; set -f desliga globbing
    set -- $_hae_sorted
    set +f
    IFS=$_hae_oldifs

    for _hae_short in "$@"; do
      [ -n "$_hae_short" ] || continue
      _hae_d="$_hae_feat_root/$_hae_short"
      if [ ! -f "$_hae_d/state.db" ] && [ ! -f "$_hae_d/state.json" ]; then
        continue
      fi
      _hae_probed=$((_hae_probed + 1))
      if [ "$_hae_probed" -gt "$_HAE_MAX_DIRS" ]; then
        # SEC-M3: estouro do teto ANTES de confirmar ativa -> indeterminada,
        # nunca inativa (mesmo tratamento de state.db ilegivel).
        return 2
      fi
      _hae_resolve_dir_status "$_hae_d" "$_hae_busy"
      case "$_HAE_WORD" in
        active)
          printf 'feature-00c\t%s\t%s\n' "$_hae_d" "$_HAE_BACKEND"
          return 0
          ;;
        indeterminate)
          _hae_had_indet=1
          ;;
      esac
    done
  fi

  # G6: um candidato indeterminado nao interrompe a varredura dos demais;
  # `ativa` sempre venceria (ja teria retornado acima). Se nao houver
  # `ativa` confirmada e ao menos um `indeterminado` foi visto, o resultado
  # agregado e `indeterminada` (G5) — nunca `inativa` por omissao.
  if [ "$_hae_had_indet" -eq 1 ]; then
    return 2
  fi
  return 1
}
