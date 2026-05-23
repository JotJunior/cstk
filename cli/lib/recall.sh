#!/bin/sh
# recall.sh — camada aditiva de memoria de conhecimento cross-feature.
#
# Arquivo unico (carve-out condicao (b) do Principio II) que concentra TODA
# referencia a sqlite3, jq e secrets-filter.sh. Implementa:
#   - busca full-text cross-projeto/feature  (cstk recall <query> [flags])
#   - ingestao pos-onda best-effort           (cstk recall --ingest --state-dir DIR)
#   - reconstrucao do indice                  (cstk recall --reindex [--states-root DIR])
#
# O indice (~/.claude/cstk/knowledge.db, SQLite + FTS5) e DERIVADO e
# reconstruivel — nunca fonte de verdade. Toda interacao com o state.json
# transacional e READ-ONLY (jq). Toda falha operacional degrada gracioso
# (aviso em stderr + exit 0); exit 2 e reservado a erro de USO (flags).
#
# Despachado por cli/cstk: `cstk recall ...` -> recall_main "$@".
#
# POSIX sh puro. Sem bash-isms. Deps OPCIONAIS: sqlite3, jq, secrets-filter.sh
# (ausencia degrada gracioso, nunca aborta a onda). Deps base: printf, grep,
# sed, command, mkdir, tr, find.

# ==== Sourcing de logging compartilhado (sem reimplementar) ====
#
# Quando despachado por cli/cstk, common.sh ja foi sourced. Em invocacao
# direta (testes), sourcing idempotente garante log_info/warn/error.
if [ -z "${_CSTK_COMMON_LOADED:-}" ]; then
  _recall_self_dir=$(unset CDPATH; cd -- "$(dirname -- "$0")" && pwd 2>/dev/null) || _recall_self_dir=""
  if [ -n "${CSTK_LIB:-}" ] && [ -f "$CSTK_LIB/common.sh" ]; then
    # shellcheck source=/dev/null
    . "$CSTK_LIB/common.sh"
  elif [ -n "$_recall_self_dir" ] && [ -f "$_recall_self_dir/common.sh" ]; then
    # shellcheck source=/dev/null
    . "$_recall_self_dir/common.sh"
  fi
fi

# Fallback minimo de logging caso common.sh nao esteja disponivel (defensivo;
# nunca deve acontecer em uso normal pois cli/cstk sempre carrega common.sh).
if ! command -v log_warn >/dev/null 2>&1; then
  log_info() { printf '[info] %s\n' "$*" >&2; }
  log_warn() { printf '[warn] %s\n' "$*" >&2; }
  log_error() { printf '[error] %s\n' "$*" >&2; }
fi

# ==== Exit codes ====
#
# 0 = sucesso OU degradacao graciosa (dep ausente, fonte ausente, lock,
#     dir nao-gravavel, DB corrompido, sem resultados).
# 2 = uso incorreto (flag invalida, --type fora do enum, --limit nao-inteiro,
#     NUL byte em input no modo busca).
RECALL_EXIT_OK=0
RECALL_EXIT_USAGE=2

# ==== Constantes de schema/DB ====
RECALL_SCHEMA_VERSION=1
RECALL_TYPE_ENUM="decision bloqueio retro skill"

# ==== Resolucao do caminho do DB ====
#
# Prioridade: flag --db > env $CSTK_KNOWLEDGE_DB > default ~/.claude/cstk/knowledge.db
recall_resolve_db() {
  # $1 = valor de --db (vazio se nao passado)
  if [ -n "${1:-}" ]; then
    printf '%s\n' "$1"
    return 0
  fi
  if [ -n "${CSTK_KNOWLEDGE_DB:-}" ]; then
    printf '%s\n' "$CSTK_KNOWLEDGE_DB"
    return 0
  fi
  printf '%s/.claude/cstk/knowledge.db\n' "${HOME:-/tmp}"
}

# ==== Usage ====
recall_usage() {
  cat <<'USAGE'
cstk recall — memoria de conhecimento cross-feature (SQLite + FTS5)

USO:
  cstk recall <query> [--project P] [--type T] [--limit N] [--db PATH]
  cstk recall --ingest --state-dir DIR [--db PATH]
  cstk recall --reindex [--states-root DIR] [--db PATH]

MODO BUSCA (default):
  <query>            termo(s) de busca full-text (obrigatorio)
  --project P        filtra por projeto de origem
  --type T           decision|bloqueio|retro|skill
  --limit N          maximo de resultados (default 20; inteiro positivo)
  --db PATH          indice (default $CSTK_KNOWLEDGE_DB ou ~/.claude/cstk/knowledge.db)

MODO INGESTAO (--ingest):
  --state-dir DIR    diretorio de state da feature (contem state.json)
  --db PATH          indice destino

MODO RECONSTRUCAO (--reindex):
  --states-root DIR  raiz para varrer state.json/state-history (default: descoberta)
  --db PATH          indice destino

Indice derivado e reconstruivel via --reindex. Read-only sobre o state
transacional. Degradacao graciosa: ausencia de sqlite3/jq nunca aborta.
Documentacao: docs/specs/cstk-knowledge-db/contracts/cstk-recall.md
USAGE
}

# ==========================================================================
# FASE 2 — Seguranca de entrada (escaping + validacao)
# Vem ANTES de ingestao/recall porque ambas dependem destes helpers por
# construcao (prevencao, nao runtime-degradado).
# ==========================================================================

# sql_escape VALUE -> imprime VALUE com aspas simples duplicadas (' -> '').
# Camada SQL: neutraliza o vetor classico de SQLi ao compor string literal.
# Aplica-se a TODO valor (texto livre E proveniencia) — o sqlite3 CLI nao
# oferece bind via argv, entao o escaping e a defesa primaria (dec-014).
sql_escape() {
  # printf '%s' evita interpretacao de barras; sed duplica cada aspa simples.
  printf '%s' "$1" | sed "s/'/''/g"
}

# fts_phrase_escape VALUE -> imprime a query como frase FTS5 literal:
# envolve em aspas duplas e duplica cada " interno (" -> "").
# Trata *, (, ), :, ^, -, booleanos como TEXTO, nunca sintaxe FTS5.
# O resultado AINDA precisa passar por sql_escape() pois entra numa string
# literal SQL (camada cumulativa: FTS5 + SQL).
fts_phrase_escape() {
  _fts_inner=$(printf '%s' "$1" | sed 's/"/""/g')
  printf '"%s"' "$_fts_inner"
}

# fts_query_escape QUERY -> tokeniza a query em whitespace e escapa CADA token
# como frase FTS5 (via fts_phrase_escape), juntando com espaco = AND implicito
# do FTS5. Assim "escaping FTS5" vira `"escaping" "FTS5"`: ambos os termos
# precisam aparecer, em QUALQUER posicao (busca multi-palavra util), sem abrir
# mao da neutralizacao de sintaxe FTS5 (cada token e uma frase entre aspas, com
# " interno duplicado — *, (, ), :, ^, -, booleanos viram TEXTO por token).
# Subshell isola `set -f` (impede glob de tokens como *, ?, [) e `unset IFS`
# (split por whitespace padrao POSIX). O resultado ainda passa por sql_escape().
fts_query_escape() {
  (
    set -f
    unset IFS
    _ftq_out=''
    for _ftq_tok in $1; do
      _ftq_p=$(fts_phrase_escape "$_ftq_tok")
      if [ -z "$_ftq_out" ]; then
        _ftq_out=$_ftq_p
      else
        _ftq_out="$_ftq_out $_ftq_p"
      fi
    done
    # Query so-whitespace (degenerada): frase vazia casa nada (exit 0, sem erro).
    [ -n "$_ftq_out" ] || _ftq_out=$(fts_phrase_escape "")
    printf '%s' "$_ftq_out"
  )
}

# validate_limit VALUE -> exit 0 se VALUE casa ^[1-9][0-9]*$ (inteiro positivo).
# Caso contrario exit 1 (o caller traduz para exit 2 de uso). Integer-validacao,
# NAO escaping: LIMIT recebe inteiro sintatico (dec-015, block-001).
validate_limit() {
  case "$1" in
    '' ) return 1 ;;
    *[!0-9]* ) return 1 ;;   # contem nao-digito
    0* )
      # rejeita "0", "01", etc — primeiro digito deve ser 1-9
      return 1
      ;;
    * ) return 0 ;;
  esac
}

# validate_type VALUE -> exit 0 se VALUE pertence ao enum, 1 caso contrario.
validate_type() {
  for _vt in $RECALL_TYPE_ENUM; do
    [ "$1" = "$_vt" ] && return 0
  done
  return 1
}

# has_nul reads stdin -> exit 0 se detectar byte NUL, 1 caso contrario.
# NUL trunca strings em C (sqlite3 CLI e jq), podendo corromper a query ou
# contornar filtros. grep -q com classe de controle: usamos LC_ALL=C + od
# fallback. Implementacao portavel: tr -d remove tudo menos NUL e conta bytes.
has_nul() {
  # Le stdin; se restar algum byte apos remover tudo exceto \000, ha NUL.
  # tr com \000 e portavel; wc -c conta bytes restantes.
  _hn_count=$(tr -dc '\000' | wc -c | tr -d ' ')
  [ "$_hn_count" != "0" ]
}

# value_has_nul VALUE -> exit 0 se VALUE (argumento) contem byte NUL.
# Argumentos de shell nunca podem conter NUL (o kernel trunca em argv), mas
# inputs vindos de arquivos/jq podem. Esta checagem opera sobre o valor ja
# em variavel — defensiva para o caminho de ingestao.
value_has_nul() {
  printf '%s' "$1" | has_nul
}

# strip_nul reads stdin -> imprime stdin sem bytes NUL (strip silencioso).
# Politica de ingestao (best-effort): NUL e removido antes de persistir.
strip_nul() {
  tr -d '\000'
}

# ==========================================================================
# FASE 1.3 — Camada de conexao, pragmas e degradacao por dep ausente
# ==========================================================================

# recall_have_sqlite3 -> exit 0 se sqlite3 disponivel.
recall_have_sqlite3() { command -v sqlite3 >/dev/null 2>&1; }

# recall_have_jq -> exit 0 se jq disponivel.
recall_have_jq() { command -v jq >/dev/null 2>&1; }

# recall_have_secrets_filter -> exit 0 se secrets-filter.sh resolvivel.
# Procura, em ordem: (1) PATH; (2) layout repo/CLI relativo a CSTK_LIB
# (cli/lib -> ../../global/skills/agente-00c-runtime/scripts); (3) layout
# instalado em ~/.claude/skills/agente-00c-runtime/scripts.
#
# A camada (2) e essencial fora de uma instalacao: testes e CI rodam recall.sh
# da arvore do repo (CSTK_LIB=cli/lib) SEM ter o runtime em ~/.claude. Sem ela,
# a ingestao degradava silenciosamente (DB nunca criado) — passava local (onde
# ~/.claude tem o runtime instalado) e falhava no CI fresh-checkout.
recall_secrets_filter_path() {
  if command -v secrets-filter.sh >/dev/null 2>&1; then
    command -v secrets-filter.sh
    return 0
  fi
  if [ -n "${CSTK_LIB:-}" ]; then
    _sf_repo="$CSTK_LIB/../../global/skills/agente-00c-runtime/scripts/secrets-filter.sh"
    if [ -f "$_sf_repo" ]; then
      printf '%s\n' "$_sf_repo"
      return 0
    fi
  fi
  _sf_default="${HOME:-/tmp}/.claude/skills/agente-00c-runtime/scripts/secrets-filter.sh"
  if [ -f "$_sf_default" ]; then
    printf '%s\n' "$_sf_default"
    return 0
  fi
  return 1
}

# recall_pragmas -> imprime o bloco de pragmas aplicado em TODA conexao.
# busy_timeout + WAL + foreign_keys=OFF (FR-016; sem state-lock.sh).
# ORDEM CRITICA: busy_timeout DEVE vir ANTES de journal_mode=WAL. A conversao
# para WAL exige lock exclusivo momentaneo; se busy_timeout ainda for 0 (default)
# quando ela roda, dois writers concorrentes num DB fresco falham NA HORA com
# "database is locked (5)" em vez de esperar. Com busy_timeout setado primeiro,
# a conversao WAL (e o DDL seguinte) aguardam ate 5s pelo lock.
recall_pragmas() {
  printf 'PRAGMA busy_timeout=5000;\n'
  printf 'PRAGMA journal_mode=WAL;\n'
  printf 'PRAGMA foreign_keys=OFF;\n'
}

# recall_schema_ddl -> imprime o DDL idempotente completo do indice.
# 4 tabelas-fonte + knowledge_fts (FTS5 standalone) + schema_meta.
# Todo CREATE e IF NOT EXISTS — aplicavel em qualquer abertura do DB.
#
# body por tipo (concatenacao textual pesquisavel):
#   decision = escolha + contexto + justificativa + evidencia
#   bloqueio = pergunta + contexto_para_resposta + resposta
#   retro    = texto
#   skill    = skill_name
recall_schema_ddl() {
  cat <<DDL
CREATE TABLE IF NOT EXISTS decisions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project TEXT NOT NULL,
  feature TEXT NOT NULL,
  wave TEXT NOT NULL,
  execucao_id TEXT NOT NULL,
  source_ts TEXT NOT NULL,
  source_id TEXT NOT NULL,
  agente TEXT,
  etapa TEXT,
  escolha TEXT,
  score INTEGER,
  contexto TEXT,
  justificativa TEXT,
  evidencia TEXT,
  ingested_at TEXT NOT NULL,
  UNIQUE(project, feature, wave, source_id)
);
CREATE TABLE IF NOT EXISTS bloqueios (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project TEXT NOT NULL,
  feature TEXT NOT NULL,
  wave TEXT NOT NULL,
  execucao_id TEXT NOT NULL,
  source_ts TEXT NOT NULL,
  source_id TEXT NOT NULL,
  status TEXT,
  pergunta TEXT,
  contexto_para_resposta TEXT,
  resposta TEXT,
  ingested_at TEXT NOT NULL,
  UNIQUE(project, feature, wave, source_id)
);
CREATE TABLE IF NOT EXISTS retros (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project TEXT NOT NULL,
  feature TEXT NOT NULL,
  wave TEXT NOT NULL,
  execucao_id TEXT NOT NULL,
  source_ts TEXT NOT NULL,
  source_id TEXT NOT NULL,
  texto TEXT,
  ingested_at TEXT NOT NULL,
  UNIQUE(project, feature, wave, source_id)
);
CREATE TABLE IF NOT EXISTS skills (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project TEXT NOT NULL,
  feature TEXT NOT NULL,
  wave TEXT NOT NULL,
  execucao_id TEXT NOT NULL,
  source_ts TEXT NOT NULL,
  source_id TEXT NOT NULL,
  skill_name TEXT NOT NULL,
  decisao_id TEXT,
  ingested_at TEXT NOT NULL,
  UNIQUE(project, feature, wave, source_id)
);
CREATE VIRTUAL TABLE IF NOT EXISTS knowledge_fts USING fts5 (
  body,
  type UNINDEXED,
  project UNINDEXED,
  feature UNINDEXED,
  wave UNINDEXED,
  source_id UNINDEXED,
  source_ts UNINDEXED
);
CREATE TABLE IF NOT EXISTS schema_meta (
  key TEXT PRIMARY KEY,
  value TEXT
);
INSERT INTO schema_meta(key, value) VALUES('schema_version', '$RECALL_SCHEMA_VERSION')
  ON CONFLICT(key) DO UPDATE SET value=excluded.value;
DDL
}

# recall_ensure_db_dir DB_PATH -> garante o diretorio do DB.
# exit 0 se diretorio existe/foi criado; exit 1 se nao-gravavel (caller degrada).
recall_ensure_db_dir() {
  _edd_dir=$(dirname -- "$1")
  if [ -d "$_edd_dir" ]; then
    [ -w "$_edd_dir" ] && return 0
    return 1
  fi
  mkdir -p -- "$_edd_dir" 2>/dev/null || return 1
  return 0
}

# recall_apply_schema DB_PATH -> aplica pragmas + DDL idempotente.
# Roteado pelo retry/backoff (FR-016) porque CREATE TABLE/VIRTUAL TABLE sao
# escritas e podem contender com outra ingestao concorrente no mesmo DB
# fresco. Retorna 0 em sucesso, 1 se esgotou retries (caller degrada).
recall_apply_schema() {
  recall_apply_sql_with_retry "$1" "$(recall_schema_ddl)"
}

# recall_run_sql DB_PATH SQL_TEXT -> aplica pragmas + SQL via sqlite3 (escrita).
# stdout descartado (ruido de pragma). Retorna o exit do sqlite3.
recall_run_sql() {
  { recall_pragmas; printf '%s\n' "$2"; } | sqlite3 -- "$1" >/dev/null 2>&1
}

# recall_query_sql DB_PATH SQL_TEXT -> executa SQL de LEITURA e EMITE stdout.
# Usado pelo modo busca (precisa do resultado). busy_timeout e aplicado via
# `-cmd` ANTES de ler stdin, sem que seu valor seja ecoado no mesmo stream do
# resultado (um PRAGMA value-returning no corpo do script poluiria a saida com
# uma linha "5000"). WAL ja e propriedade persistida do arquivo apos a 1a
# escrita, entao nao precisa ser reaplicado no caminho de leitura.
recall_query_sql() {
  printf '%s\n' "$2" | sqlite3 -cmd '.timeout 5000' -- "$1" 2>/dev/null
}

# ==========================================================================
# Dispatcher de modos (parsing de argv: busca | --ingest | --reindex)
# ==========================================================================

# recall_main: entrypoint despachado por cli/cstk. Distingue 3 modos pela
# presenca de --ingest / --reindex; default = busca.
recall_main() {
  case "${1:-}" in
    -h|--help)
      recall_usage
      return "$RECALL_EXIT_OK"
      ;;
  esac

  # Detecta o modo varrendo argv (sem consumir — cada modo reparseia).
  _mode="search"
  for _arg in "$@"; do
    case "$_arg" in
      --ingest) _mode="ingest" ;;
      --reindex) _mode="reindex" ;;
    esac
  done

  case "$_mode" in
    ingest)  recall_mode_ingest "$@" ;;
    reindex) recall_mode_reindex "$@" ;;
    search)  recall_mode_search "$@" ;;
  esac
}

# ==========================================================================
# FASE 3 — Ingestao pos-onda (--ingest)
# Extrai conhecimento estruturado de um state.json e grava no indice com
# upsert idempotente. Efeito colateral aditivo, best-effort; NUNCA escreve
# no state transacional (so jq de leitura).
# ==========================================================================

# recall_scrub VALUE -> imprime VALUE filtrado por secrets-filter.sh (so
# texto livre, FR-017). Se o filtro estiver ausente, o caller decide pular
# a ingestao (melhor pular do que vazar). Aqui assumimos que o caller ja
# validou a disponibilidade (recall_secrets_filter_path). NUL ja foi
# stripado a montante. O resultado AINDA precisa de sql_escape() antes do SQL.
recall_scrub() {
  printf '%s' "$1" | "$RECALL_SF" scrub 2>/dev/null
}

# recall_ingest_state_json STATE_JSON DB -> ingere um unico state.json no DB.
# Best-effort: qualquer falha de extracao degrada gracioso (aviso + exit 0).
# Reusado por --ingest (1 arquivo) e --reindex (N arquivos).
# Imprime em stdout (via variaveis globais de contagem) os totais por tipo.
recall_ingest_state_json() {
  _isj_state="$1"
  _isj_db="$2"

  if [ ! -r "$_isj_state" ]; then
    log_warn "recall: state.json ausente ou ilegivel: $_isj_state (ingestao pulada)"
    return "$RECALL_EXIT_OK"
  fi

  # Proveniencia comum (read-only via jq). project = BASENAME do
  # projeto_alvo_path (mitigacao S2/A02 — reduz captura de segredo em path).
  _isj_proj_path=$(jq -r '.execucao.projeto_alvo_path // ""' "$_isj_state" 2>/dev/null) || _isj_proj_path=""
  _isj_project=$(basename -- "$_isj_proj_path" 2>/dev/null) || _isj_project=""
  [ -n "$_isj_project" ] || _isj_project="unknown"
  _isj_feature=$(jq -r '.short_name // ""' "$_isj_state" 2>/dev/null) || _isj_feature=""
  [ -n "$_isj_feature" ] || _isj_feature="unknown"
  _isj_exec_id=$(jq -r '.execucao.id // ""' "$_isj_state" 2>/dev/null) || _isj_exec_id=""
  _isj_now=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || _isj_now="1970-01-01T00:00:00Z"

  # NUL strip aplicado a proveniencia (best-effort). Argumentos de shell nao
  # carregam NUL, mas valores vindos de jq podem; strip defensivo.
  _isj_project=$(printf '%s' "$_isj_project" | strip_nul)
  _isj_feature=$(printf '%s' "$_isj_feature" | strip_nul)
  _isj_exec_id=$(printf '%s' "$_isj_exec_id" | strip_nul)

  # Acumula SQL num heredoc-string e aplica numa unica transacao por arquivo.
  _isj_sql="BEGIN;"

  # ---- decisions ----
  # Campos reais do state.json: id, onda_id (wave), timestamp, etapa, agente,
  # escolha, score_justificativa (score), contexto, justificativa, evidencia.
  _isj_n_dec=0
  _isj_dec_lines=$(jq -r '
    (.decisoes // [])
    | to_entries[]
    | [(.value.id // "dec-\(.key)"),
       (.value.onda_id // "onda"),
       (.value.timestamp // .value.data // ""),
       (.value.agente // ""),
       (.value.etapa // ""),
       (.value.escolha // ""),
       ((.value.score // .value.score_justificativa // "")|tostring),
       (.value.contexto // ""),
       (.value.justificativa // ""),
       (.value.evidencia // "")]
    | @base64' "$_isj_state" 2>/dev/null) || _isj_dec_lines=""
  if [ -n "$_isj_dec_lines" ]; then
    _isj_OLDIFS="$IFS"; IFS='
'
    for _isj_row in $_isj_dec_lines; do
      _isj_decoded=$(printf '%s' "$_isj_row" | base64 -d 2>/dev/null) || continue
      # decoded e um array JSON; extrai cada campo via jq de novo (robusto a \n internos)
      _f_sid=$(printf '%s' "$_isj_decoded" | jq -r '.[0]' 2>/dev/null | strip_nul)
      _f_wave=$(printf '%s' "$_isj_decoded" | jq -r '.[1]' 2>/dev/null | strip_nul)
      _f_ts=$(printf '%s' "$_isj_decoded" | jq -r '.[2]' 2>/dev/null | strip_nul)
      _f_ag=$(printf '%s' "$_isj_decoded" | jq -r '.[3]' 2>/dev/null | strip_nul)
      _f_et=$(printf '%s' "$_isj_decoded" | jq -r '.[4]' 2>/dev/null | strip_nul)
      _f_esc=$(printf '%s' "$_isj_decoded" | jq -r '.[5]' 2>/dev/null | strip_nul)
      _f_sc=$(printf '%s' "$_isj_decoded" | jq -r '.[6]' 2>/dev/null | strip_nul)
      _f_ctx=$(printf '%s' "$_isj_decoded" | jq -r '.[7]' 2>/dev/null | strip_nul)
      _f_just=$(printf '%s' "$_isj_decoded" | jq -r '.[8]' 2>/dev/null | strip_nul)
      _f_ev=$(printf '%s' "$_isj_decoded" | jq -r '.[9]' 2>/dev/null | strip_nul)
      # Texto livre passa por secrets-filter (FR-017); estruturado nao.
      _f_ctx=$(recall_scrub "$_f_ctx")
      _f_just=$(recall_scrub "$_f_just")
      _f_ev=$(recall_scrub "$_f_ev")
      # score so entra como inteiro se valido; senao NULL. ("null" textual do
      # jq tostring tambem cai em NULL via o glob de nao-digito.)
      case "$_f_sc" in
        ''|*[!0-9]*) _isj_score_sql="NULL" ;;
        *) _isj_score_sql="$_f_sc" ;;
      esac
      _isj_sql="$_isj_sql
INSERT INTO decisions(project,feature,wave,execucao_id,source_ts,source_id,agente,etapa,escolha,score,contexto,justificativa,evidencia,ingested_at)
VALUES('$(sql_escape "$_isj_project")','$(sql_escape "$_isj_feature")','$(sql_escape "$_f_wave")','$(sql_escape "$_isj_exec_id")','$(sql_escape "$_f_ts")','$(sql_escape "$_f_sid")','$(sql_escape "$_f_ag")','$(sql_escape "$_f_et")','$(sql_escape "$_f_esc")',$_isj_score_sql,'$(sql_escape "$_f_ctx")','$(sql_escape "$_f_just")','$(sql_escape "$_f_ev")','$(sql_escape "$_isj_now")')
ON CONFLICT(project,feature,wave,source_id) DO UPDATE SET source_ts=excluded.source_ts,agente=excluded.agente,etapa=excluded.etapa,escolha=excluded.escolha,score=excluded.score,contexto=excluded.contexto,justificativa=excluded.justificativa,evidencia=excluded.evidencia,ingested_at=excluded.ingested_at;
DELETE FROM knowledge_fts WHERE type='decision' AND project='$(sql_escape "$_isj_project")' AND feature='$(sql_escape "$_isj_feature")' AND wave='$(sql_escape "$_f_wave")' AND source_id='$(sql_escape "$_f_sid")';
INSERT INTO knowledge_fts(body,type,project,feature,wave,source_id,source_ts)
VALUES('$(sql_escape "$_f_esc $_f_ctx $_f_just $_f_ev")','decision','$(sql_escape "$_isj_project")','$(sql_escape "$_isj_feature")','$(sql_escape "$_f_wave")','$(sql_escape "$_f_sid")','$(sql_escape "$_f_ts")');"
      _isj_n_dec=$((_isj_n_dec + 1))
    done
    IFS="$_isj_OLDIFS"
  fi

  # ---- bloqueios ----
  # Campos reais: id, status, pergunta, contexto_para_resposta,
  # resposta_humana (resposta), respondido_em/disparado_em (timestamp),
  # onda_id (quando presente). Bloqueios sao feature-level; wave default 'bloq'
  # se onda_id ausente, garantindo chave de upsert estavel.
  _isj_n_bloq=0
  _isj_bloq_lines=$(jq -r '
    (.bloqueios_humanos // [])
    | to_entries[]
    | [(.value.id // "bloq-\(.key)"),
       (.value.onda_id // "bloq"),
       (.value.respondido_em // .value.disparado_em // .value.timestamp // ""),
       (.value.status // ""),
       (.value.pergunta // ""),
       (.value.contexto_para_resposta // ""),
       (.value.resposta_humana // .value.resposta // "")]
    | @base64' "$_isj_state" 2>/dev/null) || _isj_bloq_lines=""
  if [ -n "$_isj_bloq_lines" ]; then
    _isj_OLDIFS="$IFS"; IFS='
'
    for _isj_row in $_isj_bloq_lines; do
      _isj_decoded=$(printf '%s' "$_isj_row" | base64 -d 2>/dev/null) || continue
      _f_sid=$(printf '%s' "$_isj_decoded" | jq -r '.[0]' 2>/dev/null | strip_nul)
      _f_wave=$(printf '%s' "$_isj_decoded" | jq -r '.[1]' 2>/dev/null | strip_nul)
      _f_ts=$(printf '%s' "$_isj_decoded" | jq -r '.[2]' 2>/dev/null | strip_nul)
      _f_st=$(printf '%s' "$_isj_decoded" | jq -r '.[3]' 2>/dev/null | strip_nul)
      _f_perg=$(printf '%s' "$_isj_decoded" | jq -r '.[4]' 2>/dev/null | strip_nul)
      _f_cpr=$(printf '%s' "$_isj_decoded" | jq -r '.[5]' 2>/dev/null | strip_nul)
      _f_resp=$(printf '%s' "$_isj_decoded" | jq -r '.[6]' 2>/dev/null | strip_nul)
      _f_perg=$(recall_scrub "$_f_perg")
      _f_cpr=$(recall_scrub "$_f_cpr")
      _f_resp=$(recall_scrub "$_f_resp")
      _isj_sql="$_isj_sql
INSERT INTO bloqueios(project,feature,wave,execucao_id,source_ts,source_id,status,pergunta,contexto_para_resposta,resposta,ingested_at)
VALUES('$(sql_escape "$_isj_project")','$(sql_escape "$_isj_feature")','$(sql_escape "$_f_wave")','$(sql_escape "$_isj_exec_id")','$(sql_escape "$_f_ts")','$(sql_escape "$_f_sid")','$(sql_escape "$_f_st")','$(sql_escape "$_f_perg")','$(sql_escape "$_f_cpr")','$(sql_escape "$_f_resp")','$(sql_escape "$_isj_now")')
ON CONFLICT(project,feature,wave,source_id) DO UPDATE SET source_ts=excluded.source_ts,status=excluded.status,pergunta=excluded.pergunta,contexto_para_resposta=excluded.contexto_para_resposta,resposta=excluded.resposta,ingested_at=excluded.ingested_at;
DELETE FROM knowledge_fts WHERE type='bloqueio' AND project='$(sql_escape "$_isj_project")' AND feature='$(sql_escape "$_isj_feature")' AND wave='$(sql_escape "$_f_wave")' AND source_id='$(sql_escape "$_f_sid")';
INSERT INTO knowledge_fts(body,type,project,feature,wave,source_id,source_ts)
VALUES('$(sql_escape "$_f_perg $_f_cpr $_f_resp")','bloqueio','$(sql_escape "$_isj_project")','$(sql_escape "$_isj_feature")','$(sql_escape "$_f_wave")','$(sql_escape "$_f_sid")','$(sql_escape "$_f_ts")');"
      _isj_n_bloq=$((_isj_n_bloq + 1))
    done
    IFS="$_isj_OLDIFS"
  fi

  # ---- retros (texto livre; source_id sintetizado retro-<wave>-<idx>) ----
  # Suporta tanto .retro (objeto/array) quanto .retros[]. Trata ambos como
  # array de textos; se ausente, nenhum registro.
  _isj_n_retro=0
  _isj_retro_lines=$(jq -r '
    ((.retros // .retro // []) | (if type=="array" then . else [.] end))
    | to_entries[]
    | [(.key|tostring),
       ((.value.texto // .value.text // (if (.value|type)=="string" then .value else "" end)) // ""),
       ((.value.timestamp // .value.data // "") // "")]
    | @base64' "$_isj_state" 2>/dev/null) || _isj_retro_lines=""
  if [ -n "$_isj_retro_lines" ]; then
    _isj_OLDIFS="$IFS"; IFS='
'
    for _isj_row in $_isj_retro_lines; do
      _isj_decoded=$(printf '%s' "$_isj_row" | base64 -d 2>/dev/null) || continue
      _f_idx=$(printf '%s' "$_isj_decoded" | jq -r '.[0]' 2>/dev/null | strip_nul)
      _f_txt=$(printf '%s' "$_isj_decoded" | jq -r '.[1]' 2>/dev/null | strip_nul)
      _f_ts=$(printf '%s' "$_isj_decoded" | jq -r '.[2]' 2>/dev/null | strip_nul)
      # Pula entradas vazias (sem texto util).
      [ -n "$_f_txt" ] || continue
      _f_txt=$(recall_scrub "$_f_txt")
      _f_sid="retro-onda-$_f_idx"
      _isj_sql="$_isj_sql
INSERT INTO retros(project,feature,wave,execucao_id,source_ts,source_id,texto,ingested_at)
VALUES('$(sql_escape "$_isj_project")','$(sql_escape "$_isj_feature")','onda','$(sql_escape "$_isj_exec_id")','$(sql_escape "$_f_ts")','$(sql_escape "$_f_sid")','$(sql_escape "$_f_txt")','$(sql_escape "$_isj_now")')
ON CONFLICT(project,feature,wave,source_id) DO UPDATE SET source_ts=excluded.source_ts,texto=excluded.texto,ingested_at=excluded.ingested_at;
DELETE FROM knowledge_fts WHERE type='retro' AND project='$(sql_escape "$_isj_project")' AND feature='$(sql_escape "$_isj_feature")' AND wave='onda' AND source_id='$(sql_escape "$_f_sid")';
INSERT INTO knowledge_fts(body,type,project,feature,wave,source_id,source_ts)
VALUES('$(sql_escape "$_f_txt")','retro','$(sql_escape "$_isj_project")','$(sql_escape "$_isj_feature")','onda','$(sql_escape "$_f_sid")','$(sql_escape "$_f_ts")');"
      _isj_n_retro=$((_isj_n_retro + 1))
    done
    IFS="$_isj_OLDIFS"
  fi

  # ---- skills (ondas[].skills_invoked[]; source_id skill-<wave>-<idx>) ----
  # skill_name NAO passa pelo filtro (estruturado, FR-017/INV-DM-3).
  _isj_n_skill=0
  _isj_skill_lines=$(jq -r '
    (.ondas // [])
    | to_entries[]
    | .key as $wi
    | (.value.id // "onda-\($wi)") as $wid
    | ((.value.skills_invoked // []) | to_entries[]
       | [$wid,
          (.key|tostring),
          (.value.skill // .value.skill_name // ""),
          (.value.decisao_id // ""),
          (.value.timestamp // "")])
    | @base64' "$_isj_state" 2>/dev/null) || _isj_skill_lines=""
  if [ -n "$_isj_skill_lines" ]; then
    _isj_OLDIFS="$IFS"; IFS='
'
    for _isj_row in $_isj_skill_lines; do
      _isj_decoded=$(printf '%s' "$_isj_row" | base64 -d 2>/dev/null) || continue
      _f_wid=$(printf '%s' "$_isj_decoded" | jq -r '.[0]' 2>/dev/null | strip_nul)
      _f_sidx=$(printf '%s' "$_isj_decoded" | jq -r '.[1]' 2>/dev/null | strip_nul)
      _f_skn=$(printf '%s' "$_isj_decoded" | jq -r '.[2]' 2>/dev/null | strip_nul)
      _f_did=$(printf '%s' "$_isj_decoded" | jq -r '.[3]' 2>/dev/null | strip_nul)
      _f_ts=$(printf '%s' "$_isj_decoded" | jq -r '.[4]' 2>/dev/null | strip_nul)
      [ -n "$_f_skn" ] || continue
      _f_sid="skill-$_f_wid-$_f_sidx"
      _isj_sql="$_isj_sql
INSERT INTO skills(project,feature,wave,execucao_id,source_ts,source_id,skill_name,decisao_id,ingested_at)
VALUES('$(sql_escape "$_isj_project")','$(sql_escape "$_isj_feature")','$(sql_escape "$_f_wid")','$(sql_escape "$_isj_exec_id")','$(sql_escape "$_f_ts")','$(sql_escape "$_f_sid")','$(sql_escape "$_f_skn")','$(sql_escape "$_f_did")','$(sql_escape "$_isj_now")')
ON CONFLICT(project,feature,wave,source_id) DO UPDATE SET source_ts=excluded.source_ts,skill_name=excluded.skill_name,decisao_id=excluded.decisao_id,ingested_at=excluded.ingested_at;
DELETE FROM knowledge_fts WHERE type='skill' AND project='$(sql_escape "$_isj_project")' AND feature='$(sql_escape "$_isj_feature")' AND wave='$(sql_escape "$_f_wid")' AND source_id='$(sql_escape "$_f_sid")';
INSERT INTO knowledge_fts(body,type,project,feature,wave,source_id,source_ts)
VALUES('$(sql_escape "$_f_skn")','skill','$(sql_escape "$_isj_project")','$(sql_escape "$_isj_feature")','$(sql_escape "$_f_wid")','$(sql_escape "$_f_sid")','$(sql_escape "$_f_ts")');"
      _isj_n_skill=$((_isj_n_skill + 1))
    done
    IFS="$_isj_OLDIFS"
  fi

  _isj_sql="$_isj_sql
COMMIT;"

  # Aplica com retry/backoff em "database is locked" (FR-016).
  recall_apply_sql_with_retry "$_isj_db" "$_isj_sql" || {
    log_warn "recall: ingestao de $_isj_state degradou (lock persistente apos retries); pulada"
    return "$RECALL_EXIT_OK"
  }

  # Acumula contagens globais (usadas pelo resumo de --ingest).
  RECALL_TOTAL_DEC=$((${RECALL_TOTAL_DEC:-0} + _isj_n_dec))
  RECALL_TOTAL_BLOQ=$((${RECALL_TOTAL_BLOQ:-0} + _isj_n_bloq))
  RECALL_TOTAL_RETRO=$((${RECALL_TOTAL_RETRO:-0} + _isj_n_retro))
  RECALL_TOTAL_SKILL=$((${RECALL_TOTAL_SKILL:-0} + _isj_n_skill))
  return "$RECALL_EXIT_OK"
}

# recall_backoff_sleep TRY -> dorme ~TRY segundos + jitter fracionario [0,1)s
# derivado do PID. Sem jitter, dois writers que colidiram dormem o MESMO tempo
# e re-colidem em lockstep (thundering herd) ate esgotar retries; o jitter
# dessincroniza. Fallback para sleep inteiro se fracionario nao suportado.
recall_backoff_sleep() {
  _bs_base="$1"
  _bs_frac=$(awk -v p="$$" -v t="$_bs_base" 'BEGIN{srand(p*7+t); printf "%02d", int(rand()*100)}' 2>/dev/null)
  [ -n "$_bs_frac" ] || _bs_frac="00"
  sleep "${_bs_base}.${_bs_frac}" 2>/dev/null || sleep "$_bs_base"
}

# recall_apply_sql_with_retry DB SQL -> aplica SQL com retry/backoff em
# "database is locked" (FR-016). Ate 4 tentativas, backoff com jitter por-PID.
# NUNCA usa state-lock.sh. Retorna 0 em sucesso, 1 se esgotou retries.
recall_apply_sql_with_retry() {
  _ar_db="$1"
  _ar_sql="$2"
  _ar_try=1
  while [ "$_ar_try" -le 4 ]; do
    _ar_err=$({ recall_pragmas; printf '%s\n' "$_ar_sql"; } | sqlite3 -- "$_ar_db" 2>&1 >/dev/null) && return 0
    case "$_ar_err" in
      *"database is locked"*|*"database is busy"*|*"locking protocol"*)
        recall_backoff_sleep "$_ar_try"
        _ar_try=$((_ar_try + 1))
        ;;
      *)
        # Erro nao relacionado a lock: aviso e desiste (best-effort).
        [ -n "$_ar_err" ] && log_warn "recall: erro sqlite na ingestao: $_ar_err"
        return 1
        ;;
    esac
  done
  return 1
}

# recall_mode_ingest: porta de CLI do modo ingestao.
recall_mode_ingest() {
  _ing_state_dir=""
  _ing_db_flag=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --ingest) ;;
      --state-dir) shift; _ing_state_dir="${1:-}" ;;
      --db) shift; _ing_db_flag="${1:-}" ;;
      -h|--help) recall_usage; return "$RECALL_EXIT_OK" ;;
      *) log_error "recall --ingest: flag invalida: $1"; return "$RECALL_EXIT_USAGE" ;;
    esac
    shift || break
  done

  if [ -z "$_ing_state_dir" ]; then
    log_error "recall --ingest: --state-dir obrigatorio"
    return "$RECALL_EXIT_USAGE"
  fi

  # Deps (best-effort): ausencia degrada gracioso (exit 0) SEM tocar o indice.
  if ! recall_have_sqlite3; then
    log_warn "recall: memoria de conhecimento indisponivel (sqlite3 nao instalado); ingestao pulada"
    return "$RECALL_EXIT_OK"
  fi
  if ! recall_have_jq; then
    log_warn "recall: jq nao instalado; ingestao pulada"
    return "$RECALL_EXIT_OK"
  fi
  RECALL_SF=$(recall_secrets_filter_path) || {
    log_warn "recall: secrets-filter.sh ausente; ingestao pulada (melhor pular do que vazar)"
    return "$RECALL_EXIT_OK"
  }

  _ing_db=$(recall_resolve_db "$_ing_db_flag")
  if ! recall_ensure_db_dir "$_ing_db"; then
    log_warn "recall: diretorio do indice nao-gravavel ($_ing_db); ingestao pulada"
    return "$RECALL_EXIT_OK"
  fi
  recall_apply_schema "$_ing_db" || {
    log_warn "recall: falha ao aplicar schema em $_ing_db; ingestao pulada"
    return "$RECALL_EXIT_OK"
  }

  RECALL_TOTAL_DEC=0; RECALL_TOTAL_BLOQ=0; RECALL_TOTAL_RETRO=0; RECALL_TOTAL_SKILL=0
  recall_ingest_state_json "$_ing_state_dir/state.json" "$_ing_db"

  printf 'ingested: %d decisions, %d bloqueios, %d retros, %d skills\n' \
    "${RECALL_TOTAL_DEC:-0}" "${RECALL_TOTAL_BLOQ:-0}" "${RECALL_TOTAL_RETRO:-0}" "${RECALL_TOTAL_SKILL:-0}"
  return "$RECALL_EXIT_OK"
}

# ==========================================================================
# FASE 4 — Recuperacao (cstk recall <query>)
# ==========================================================================

recall_mode_search() {
  _se_query=""
  _se_project=""
  _se_type=""
  _se_limit="20"
  _se_db_flag=""
  _se_have_query=0

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --project) shift; _se_project="${1:-}" ;;
      --type) shift; _se_type="${1:-}" ;;
      --limit) shift; _se_limit="${1:-}" ;;
      --db) shift; _se_db_flag="${1:-}" ;;
      -h|--help) recall_usage; return "$RECALL_EXIT_OK" ;;
      --*) log_error "recall: flag invalida: $1"; return "$RECALL_EXIT_USAGE" ;;
      *)
        if [ "$_se_have_query" -eq 0 ]; then
          _se_query="$1"; _se_have_query=1
        else
          log_error "recall: query extra inesperada: $1"
          return "$RECALL_EXIT_USAGE"
        fi
        ;;
    esac
    shift || break
  done

  if [ "$_se_have_query" -eq 0 ]; then
    log_error "recall: query obrigatoria"
    recall_usage
    return "$RECALL_EXIT_USAGE"
  fi

  # Rejeicao de NUL em TODOS os inputs do usuario ANTES de qualquer
  # escaping/validacao/interpolacao (dec-015, block-001). Politica busca =
  # rejeitar com exit 2.
  for _se_in in "$_se_query" "$_se_project" "$_se_type" "$_se_db_flag"; do
    if value_has_nul "$_se_in"; then
      log_error "recall: byte NUL em input rejeitado (busca)"
      return "$RECALL_EXIT_USAGE"
    fi
  done

  # --limit integer-validado (nao escaping); rejeita nao-inteiro com exit 2.
  if ! validate_limit "$_se_limit"; then
    log_error "recall: --limit deve ser inteiro positivo (recebido: '$_se_limit')"
    return "$RECALL_EXIT_USAGE"
  fi

  # --type validado contra enum (se fornecido).
  if [ -n "$_se_type" ] && ! validate_type "$_se_type"; then
    log_error "recall: --type fora do enum (decision|bloqueio|retro|skill): '$_se_type'"
    return "$RECALL_EXIT_USAGE"
  fi

  # Degradacao graciosa: sqlite3 ausente.
  if ! recall_have_sqlite3; then
    log_warn "recall: memoria de conhecimento indisponivel (sqlite3 nao instalado)"
    return "$RECALL_EXIT_OK"
  fi

  _se_db=$(recall_resolve_db "$_se_db_flag")
  if [ ! -f "$_se_db" ]; then
    log_warn "recall: indice vazio/ausente; rode \`cstk recall --reindex\` para popular"
    return "$RECALL_EXIT_OK"
  fi

  # Integridade rapida: DB corrompido/ilegivel -> aviso + sugestao + exit 0.
  _se_ok=$(printf 'PRAGMA quick_check;\n' | sqlite3 -- "$_se_db" 2>/dev/null | head -n 1) || _se_ok=""
  if [ "$_se_ok" != "ok" ]; then
    log_warn "recall: indice ilegivel/corrompido ($_se_db); rode \`cstk recall --reindex\` para reconstruir"
    return "$RECALL_EXIT_OK"
  fi

  # Compoe a query. Escaping de duas camadas (FTS5 por-token + SQL): cada
  # termo vira uma frase FTS5 entre aspas, juntados por AND implicito.
  _se_match=$(sql_escape "$(fts_query_escape "$_se_query")")
  _se_where="WHERE knowledge_fts MATCH '$_se_match'"
  if [ -n "$_se_project" ]; then
    _se_where="$_se_where AND project = '$(sql_escape "$_se_project")'"
  fi
  if [ -n "$_se_type" ]; then
    _se_where="$_se_where AND type = '$(sql_escape "$_se_type")'"
  fi
  # Separador 0x1F (unit separator) entre colunas: improvavel no conteudo.
  _se_sql="SELECT type, project, feature, wave, source_ts, source_id, body
FROM knowledge_fts $_se_where
ORDER BY bm25(knowledge_fts) LIMIT $_se_limit;"

  _se_out=$(recall_query_sql "$_se_db" ".mode list
.separator |@|
$_se_sql") || _se_out=""

  if [ -z "$_se_out" ]; then
    printf "nenhum resultado para '%s'\n" "$_se_query"
    return "$RECALL_EXIT_OK"
  fi

  # Renderiza cada linha com proveniencia (FR-011).
  printf '%s\n' "$_se_out" | while IFS= read -r _se_line; do
    [ -n "$_se_line" ] || continue
    _r_type=$(printf '%s' "$_se_line" | awk -F '\\|@\\|' '{print $1}')
    _r_proj=$(printf '%s' "$_se_line" | awk -F '\\|@\\|' '{print $2}')
    _r_feat=$(printf '%s' "$_se_line" | awk -F '\\|@\\|' '{print $3}')
    _r_wave=$(printf '%s' "$_se_line" | awk -F '\\|@\\|' '{print $4}')
    _r_ts=$(printf '%s' "$_se_line" | awk -F '\\|@\\|' '{print $5}')
    _r_sid=$(printf '%s' "$_se_line" | awk -F '\\|@\\|' '{print $6}')
    _r_body=$(printf '%s' "$_se_line" | awk -F '\\|@\\|' '{print $7}')
    printf '[%s] %s / %s / %s / %s (%s)\n' \
      "$_r_type" "$_r_proj" "$_r_feat" "$_r_wave" "$_r_ts" "$_r_sid"
    printf '  %s\n\n' "$_r_body"
  done
  return "$RECALL_EXIT_OK"
}

# ==========================================================================
# FASE 5 — Reconstrucao (--reindex)
# Recria o indice do zero a partir dos state.json descobertos. Reusa o MESMO
# caminho de ingestao (upsert idempotente) — rede de seguranca (indice
# descartavel). Idempotente: rodar de novo nao muda a contagem.
# ==========================================================================

recall_mode_reindex() {
  _rx_states_root=""
  _rx_db_flag=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --reindex) ;;
      --states-root) shift; _rx_states_root="${1:-}" ;;
      --db) shift; _rx_db_flag="${1:-}" ;;
      -h|--help) recall_usage; return "$RECALL_EXIT_OK" ;;
      *) log_error "recall --reindex: flag invalida: $1"; return "$RECALL_EXIT_USAGE" ;;
    esac
    shift || break
  done

  if ! recall_have_sqlite3; then
    log_warn "recall: sqlite3 nao instalado; reindex pulado"
    return "$RECALL_EXIT_OK"
  fi
  if ! recall_have_jq; then
    log_warn "recall: jq nao instalado; reindex pulado"
    return "$RECALL_EXIT_OK"
  fi
  RECALL_SF=$(recall_secrets_filter_path) || {
    log_warn "recall: secrets-filter.sh ausente; reindex pulado"
    return "$RECALL_EXIT_OK"
  }

  _rx_db=$(recall_resolve_db "$_rx_db_flag")
  if ! recall_ensure_db_dir "$_rx_db"; then
    log_warn "recall: diretorio do indice nao-gravavel ($_rx_db); reindex pulado"
    return "$RECALL_EXIT_OK"
  fi

  # Recria do zero (indice descartavel): apaga o arquivo e re-aplica schema.
  rm -f -- "$_rx_db" "$_rx_db-wal" "$_rx_db-shm" 2>/dev/null || :
  recall_apply_schema "$_rx_db" || {
    log_warn "recall: falha ao recriar schema em $_rx_db; reindex pulado"
    return "$RECALL_EXIT_OK"
  }

  # Raiz de varredura: --states-root ou descoberta padrao (HOME + cwd).
  if [ -z "$_rx_states_root" ]; then
    _rx_states_root="${HOME:-/tmp}"
  fi

  RECALL_TOTAL_DEC=0; RECALL_TOTAL_BLOQ=0; RECALL_TOTAL_RETRO=0; RECALL_TOTAL_SKILL=0
  _rx_count=0
  # Varre feature-00c-state/*/state.json e agente-00c-state/state.json.
  # find e portavel; -path com globs simples.
  _rx_states=$(find "$_rx_states_root" \
      -type f -name 'state.json' \
      \( -path '*/.claude/feature-00c-state/*/state.json' \
         -o -path '*/.claude/agente-00c-state/state.json' \) \
      2>/dev/null) || _rx_states=""
  if [ -n "$_rx_states" ]; then
    _rx_OLDIFS="$IFS"; IFS='
'
    for _rx_sj in $_rx_states; do
      recall_ingest_state_json "$_rx_sj" "$_rx_db"
      _rx_count=$((_rx_count + 1))
    done
    IFS="$_rx_OLDIFS"
  fi

  printf 'reindexed: %d state files (%d decisions, %d bloqueios, %d retros, %d skills)\n' \
    "$_rx_count" "${RECALL_TOTAL_DEC:-0}" "${RECALL_TOTAL_BLOQ:-0}" "${RECALL_TOTAL_RETRO:-0}" "${RECALL_TOTAL_SKILL:-0}"
  return "$RECALL_EXIT_OK"
}
