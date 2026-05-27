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

# ==== Mix de roteamento de modelos: delegacao, NUNCA reimplementacao ====
#
# (knowledge-db-metrics, task 2.4 / FR-017 / contract §6) A MetricaDerivada
# "mix de roteamento de modelos" NAO e ingerida nesta knowledge.db nem
# agregada aqui. Fonte UNICA e canonica e o agregador ja existente do runtime
# (model-routing-report.sh, subcomando aggregate, flag --json). O painel/
# consumidor o invoca diretamente. recall.sh deliberadamente NAO contem
# nenhum programa jq/SQL que agregue escolhas de modelo por subagente. Isto
# garante SC-006 (0 divergencias com a ferramenta existente): so ha 0
# divergencia se a MESMA logica for a unica fonte. Duplicar a agregacao aqui
# violaria FR-017. Auditoria: nenhuma LINHA DE CODIGO (nao-comentario) de
# recall.sh referencia os nomes de modelo ou as chaves de agregacao do mix —
# ver scenario_m63_model_mix_delegado em tests/cstk/test_recall.sh.

# ==== Constantes de schema/DB ====
# v2 (knowledge-db-metrics): + tabelas relacionais executions, waves,
# alert_signals (camada A) e tasks, events (camada B). Bump idempotente:
# CREATE TABLE IF NOT EXISTS + INSERT ... ON CONFLICT no schema_meta — DB v1
# pre-existente ganha as tabelas novas sem perda de dado (FR-007).
RECALL_SCHEMA_VERSION=3
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
  cstk recall --context "<termos>" [--limit N] [--exclude-feature NAME]
              [--type T] [--project P] [--max-bytes N] [--db PATH]
  cstk recall --ingest --state-dir DIR [--db PATH]
  cstk recall --reindex [--states-root DIR] [--db PATH]

MODO BUSCA (default):
  <query>            termo(s) de busca full-text (obrigatorio)
  --project P        filtra por projeto de origem
  --type T           decision|bloqueio|retro|skill
  --limit N          maximo de resultados (default 20; inteiro positivo)
  --db PATH          indice (default $CSTK_KNOWLEDGE_DB ou ~/.claude/cstk/knowledge.db)

MODO CONTEXT (--context): leitura-para-contexto (read-back loop). Retorna um
  bloco markdown enxuto pronto para injecao em prompt. Read-only, best-effort:
  toda degradacao = no-op (stdout vazio + exit 0). Composicao OR entre termos.
  "<termos>"            termos de consulta (obrigatorio; OR entre tokens)
  --limit N            maximo de achados (default 4; faixa recomendada 3-5)
  --exclude-feature N   anti-eco: omite achados da feature N (no SQL)
  --type T             decision|bloqueio|retro|skill
  --project P          filtra por projeto de origem
  --max-bytes N        teto de bytes do bloco (default 2000; corta por achado inteiro)
  --db PATH            indice
  Exemplo:
    cstk recall --context "cache fts query" --limit 4 \
      --exclude-feature recall-autoconsume --max-bytes 2000

MODO INGESTAO (--ingest):
  --state-dir DIR    diretorio de state da feature (contem state.json)
  --db PATH          indice destino

MODO RECONSTRUCAO (--reindex):
  --states-root DIR  raiz para varrer state.json/state-history (default: descoberta)
  --db PATH          indice destino

Indice derivado e reconstruivel via --reindex. Read-only sobre o state
transacional. Degradacao graciosa: ausencia de sqlite3/jq nunca aborta.
Documentacao: docs/specs/_archived/cstk-knowledge-db/contracts/cstk-recall.md
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

# fts_query_escape_or QUERY -> identico a fts_query_escape, mas junta os tokens
# escapados com ` OR ` em vez do AND-implicito (espaco). Usado SOMENTE pelo modo
# --context (recall_mode_context): keywords kebab da feature corrente raramente
# coocorrem todas no mesmo documento (AND => 0 matches), entao OR maximiza o
# recall do read-back loop (research Decision 1: AND 0 -> OR 43). Helper NOVO e
# separado (em vez de parametro de juncao em fts_query_escape) para isolar o
# blast radius: o caminho de busca testado NAO e tocado. Cada token continua
# escapado por fts_phrase_escape (neutraliza sintaxe FTS5 *,(,),:,^,-,booleanos)
# e o resultado AINDA precisa passar por sql_escape() (camada SQL cumulativa).
# Subshell isola `set -f` (sem glob de tokens *,?,[) e `unset IFS` (split por
# whitespace POSIX). Query degenerada (so-whitespace) => frase vazia => zero
# match (mesma politica de fts_query_escape; nunca erro).
fts_query_escape_or() {
  (
    set -f
    unset IFS
    _ftqo_out=''
    for _ftqo_tok in $1; do
      _ftqo_p=$(fts_phrase_escape "$_ftqo_tok")
      if [ -z "$_ftqo_out" ]; then
        _ftqo_out=$_ftqo_p
      else
        _ftqo_out="$_ftqo_out OR $_ftqo_p"
      fi
    done
    [ -n "$_ftqo_out" ] || _ftqo_out=$(fts_phrase_escape "")
    printf '%s' "$_ftqo_out"
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
  decisao_id TEXT,
  disparado_em TEXT,
  respondido_em TEXT,
  latencia_segundos INTEGER,
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
CREATE TABLE IF NOT EXISTS executions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project TEXT NOT NULL,
  feature TEXT NOT NULL,
  wave TEXT NOT NULL,
  execucao_id TEXT NOT NULL,
  source_ts TEXT NOT NULL,
  source_id TEXT NOT NULL,
  status TEXT,
  motivo_termino TEXT,
  etapa_corrente TEXT,
  iniciada_em TEXT,
  terminada_em TEXT,
  duracao_segundos INTEGER,
  stack_sugerida TEXT,
  ondas_total INTEGER,
  tool_calls_total INTEGER,
  wallclock_total_segundos INTEGER,
  subagentes_spawned INTEGER,
  profundidade_max INTEGER,
  decisoes_total INTEGER,
  bloqueios_humanos_total INTEGER,
  sugestoes_skills_total INTEGER,
  issues_toolkit_abertas INTEGER,
  ingested_at TEXT NOT NULL,
  UNIQUE(project, feature, wave, source_id)
);
CREATE TABLE IF NOT EXISTS waves (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project TEXT NOT NULL,
  feature TEXT NOT NULL,
  wave TEXT NOT NULL,
  execucao_id TEXT NOT NULL,
  source_ts TEXT NOT NULL,
  source_id TEXT NOT NULL,
  etapas TEXT,
  inicio TEXT,
  fim TEXT,
  wallclock_seconds INTEGER,
  tool_calls INTEGER,
  motivo_termino TEXT,
  n_etapas INTEGER,
  n_skills INTEGER,
  ingested_at TEXT NOT NULL,
  UNIQUE(project, feature, wave, source_id)
);
CREATE TABLE IF NOT EXISTS alert_signals (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project TEXT NOT NULL,
  feature TEXT NOT NULL,
  wave TEXT NOT NULL,
  execucao_id TEXT NOT NULL,
  source_ts TEXT NOT NULL,
  source_id TEXT NOT NULL,
  tipo TEXT NOT NULL,
  subtipo TEXT,
  valor_consumido INTEGER,
  valor_threshold INTEGER,
  descricao TEXT,
  ingested_at TEXT NOT NULL,
  UNIQUE(project, feature, wave, source_id)
);
CREATE TABLE IF NOT EXISTS tasks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project TEXT NOT NULL,
  feature TEXT NOT NULL,
  wave TEXT NOT NULL,
  execucao_id TEXT NOT NULL,
  source_ts TEXT NOT NULL,
  source_id TEXT NOT NULL,
  titulo TEXT,
  outcome TEXT,
  testes_rodados INTEGER,
  testes_passados INTEGER,
  lint_ok INTEGER,
  arquivos_tocados INTEGER,
  ingested_at TEXT NOT NULL,
  UNIQUE(project, feature, wave, source_id)
);
CREATE TABLE IF NOT EXISTS events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project TEXT NOT NULL,
  feature TEXT NOT NULL,
  wave TEXT NOT NULL,
  execucao_id TEXT NOT NULL,
  source_ts TEXT NOT NULL,
  source_id TEXT NOT NULL,
  event_type TEXT NOT NULL,
  timestamp TEXT NOT NULL,
  descricao TEXT,
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
  # Migracao idempotente v2->v3: tasks.titulo. CREATE TABLE IF NOT EXISTS NAO
  # altera uma tabela ja criada, entao indices v2 pre-existentes nao ganhariam
  # a coluna pelo DDL — o INSERT seguinte falharia ("no such column"). Em db
  # fresco (reindex faz rm -f antes) o arquivo nem existe aqui: o DDL ja cria
  # tasks com titulo e o check pula. SQLite nao tem ADD COLUMN IF NOT EXISTS,
  # logo inspecionamos PRAGMA table_info e so emitimos o ALTER quando a coluna
  # falta. Vai no mesmo SQL do DDL para herdar o retry/backoff (FR-016).
  _as_extra=""
  if [ -f "$1" ]; then
    _as_cols=$(printf 'PRAGMA table_info(tasks);\n' | sqlite3 -- "$1" 2>/dev/null) || _as_cols=""
    case "$_as_cols" in
      ''|*'|titulo|'*) : ;;  # tabela inexistente (DDL cria) ou ja migrada
      *) _as_extra='
ALTER TABLE tasks ADD COLUMN titulo TEXT;' ;;
    esac
  fi
  recall_apply_sql_with_retry "$1" "$(recall_schema_ddl)$_as_extra"
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
  # Precedencia explicita (--ingest/--reindex/--context sao mutuamente
  # exclusivos por uso): a ULTIMA flag de modo encontrada na varredura vence.
  # Em uso normal so uma aparece; default permanece search.
  _mode="search"
  for _arg in "$@"; do
    case "$_arg" in
      --ingest) _mode="ingest" ;;
      --reindex) _mode="reindex" ;;
      --context) _mode="context" ;;
    esac
  done

  case "$_mode" in
    ingest)  recall_mode_ingest "$@" ;;
    reindex) recall_mode_reindex "$@" ;;
    context) recall_mode_context "$@" ;;
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

# recall_int_or_null VALUE -> imprime o literal SQL para uma coluna INTEGER:
# o proprio inteiro se VALUE for digitos (com sinal opcional), senao 'NULL'.
# Cobre "" (campo ausente), "null" textual do jq tostring e qualquer nao-numero
# — evita injetar texto cru numa coluna numerica (FR-006: estruturado sem
# filtro, mas validado). Espelha o case inline usado em decisions.score.
recall_int_or_null() {
  case "$1" in
    ''|*[!0-9-]*) printf 'NULL' ;;
    -|-*[!0-9]*)  printf 'NULL' ;;
    *)            printf '%s' "$1" ;;
  esac
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
  # Feature: prefere .short_name (top-level, layout corrente no disco);
  # tolera .execucao.short_name (local canonico do data-model). Leitura dupla
  # cobre a divergencia historica de onde o campo foi gravado.
  _isj_feature=$(jq -r '.short_name // .execucao.short_name // ""' "$_isj_state" 2>/dev/null) || _isj_feature=""
  # Fallback de proveniencia quando .short_name esta ausente, por layout:
  #  - feature-00c-state/<short-name>/: short-name vem do diretorio-pai (states
  #    legados gravados antes de o init versionar short_name).
  #  - agente-00c-state/ (orquestrador de PROJETO, que NAO grava short_name):
  #    usa o NOME DO DIR DO PROJETO (= _isj_project) como feature, em vez de
  #    'unknown'. O anti-eco do agente-00c (FR-011) exclui essa mesma feature —
  #    ver paridade em agente-00c-orchestrator (EXCLUDE_FEATURE = basename do
  #    projeto_alvo_path).
  if [ -z "$_isj_feature" ]; then
    # Checagem por componente (nao por glob): robusta p/ caminhos relativos E
    # absolutos (glob `*/.claude/...` falharia em path relativo iniciado por
    # `.claude/`).
    _isj_parent=$(dirname -- "$_isj_state" 2>/dev/null) || _isj_parent=""
    _isj_grandp=$(dirname -- "$_isj_parent" 2>/dev/null) || _isj_grandp=""
    if [ "$(basename -- "$_isj_grandp" 2>/dev/null)" = "feature-00c-state" ]; then
      # feature-00c: short-name = diretorio-pai do state.json.
      _isj_feature=$(basename -- "$_isj_parent" 2>/dev/null) || _isj_feature=""
    elif [ "$(basename -- "$_isj_parent" 2>/dev/null)" = "agente-00c-state" ]; then
      # agente-00c (projeto): feature = nome do dir do projeto.
      _isj_feature="$_isj_project"
    fi
  fi
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

  # ---- executions (grao = execucao; 1 linha; wave='-' source_id=execucao_id) ----
  # Deriva de .execucao + .metricas_acumuladas + .etapa_corrente. duracao_segundos
  # computada via fromdateiso8601 quando iniciada_em E terminada_em presentes
  # (NULL para execucao aberta — Acceptance US1.3). So motivo_termino e texto
  # livre (filtrado); demais campos estruturados/numericos sem filtro (FR-006).
  _isj_n_exec=0
  _isj_exec_b64=$(jq -r '
    (.execucao // {}) as $e
    | (.metricas_acumuladas // {}) as $m
    | (if (($e.iniciada_em // "") != "" and ($e.terminada_em // "") != "")
       then (($e.terminada_em|fromdateiso8601) - ($e.iniciada_em|fromdateiso8601) | tostring)
       else "" end) as $dur
    | [($e.id // ""),
       ($e.status // ""),
       ($e.motivo_termino // ""),
       (.etapa_corrente // ""),
       ($e.iniciada_em // ""),
       ($e.terminada_em // ""),
       $dur,
       ($e.stack_sugerida // ""),
       (($m.ondas_total // "")|tostring),
       (($m.tool_calls_total // "")|tostring),
       (($m.tempo_wallclock_total_segundos // "")|tostring),
       (($m.subagentes_spawned // "")|tostring),
       (($m.profundidade_max_atingida // "")|tostring),
       (($m.decisoes_total // "")|tostring),
       (($m.bloqueios_humanos_total // "")|tostring),
       (($m.sugestoes_skills_globais_total // "")|tostring),
       (($m.issues_toolkit_abertas // "")|tostring)]
    | @base64' "$_isj_state" 2>/dev/null) || _isj_exec_b64=""
  # Ingere somente se houver execucao_id (chave natural estavel).
  if [ -n "$_isj_exec_b64" ] && [ -n "$_isj_exec_id" ]; then
    _isj_decoded=$(printf '%s' "$_isj_exec_b64" | base64 -d 2>/dev/null) || _isj_decoded=""
    if [ -n "$_isj_decoded" ]; then
      _f_eid=$(printf '%s' "$_isj_decoded" | jq -r '.[0]' 2>/dev/null | strip_nul)
      _f_st=$(printf '%s' "$_isj_decoded" | jq -r '.[1]' 2>/dev/null | strip_nul)
      _f_mt=$(printf '%s' "$_isj_decoded" | jq -r '.[2]' 2>/dev/null | strip_nul)
      _f_ec=$(printf '%s' "$_isj_decoded" | jq -r '.[3]' 2>/dev/null | strip_nul)
      _f_ini=$(printf '%s' "$_isj_decoded" | jq -r '.[4]' 2>/dev/null | strip_nul)
      _f_ter=$(printf '%s' "$_isj_decoded" | jq -r '.[5]' 2>/dev/null | strip_nul)
      _f_dur=$(printf '%s' "$_isj_decoded" | jq -r '.[6]' 2>/dev/null | strip_nul)
      _f_stk=$(printf '%s' "$_isj_decoded" | jq -r '.[7]' 2>/dev/null | strip_nul)
      _f_ot=$(printf '%s' "$_isj_decoded" | jq -r '.[8]' 2>/dev/null | strip_nul)
      _f_tc=$(printf '%s' "$_isj_decoded" | jq -r '.[9]' 2>/dev/null | strip_nul)
      _f_wt=$(printf '%s' "$_isj_decoded" | jq -r '.[10]' 2>/dev/null | strip_nul)
      _f_ss=$(printf '%s' "$_isj_decoded" | jq -r '.[11]' 2>/dev/null | strip_nul)
      _f_pm=$(printf '%s' "$_isj_decoded" | jq -r '.[12]' 2>/dev/null | strip_nul)
      _f_dt=$(printf '%s' "$_isj_decoded" | jq -r '.[13]' 2>/dev/null | strip_nul)
      _f_bt=$(printf '%s' "$_isj_decoded" | jq -r '.[14]' 2>/dev/null | strip_nul)
      _f_sg=$(printf '%s' "$_isj_decoded" | jq -r '.[15]' 2>/dev/null | strip_nul)
      _f_it=$(printf '%s' "$_isj_decoded" | jq -r '.[16]' 2>/dev/null | strip_nul)
      # Texto livre filtrado; demais estruturados.
      _f_mt=$(recall_scrub "$_f_mt")
      # Inteiros: valor valido ou NULL (cobre "" e "null" textual).
      _isj_dur_sql=$(recall_int_or_null "$_f_dur")
      _isj_ot_sql=$(recall_int_or_null "$_f_ot")
      _isj_tc_sql=$(recall_int_or_null "$_f_tc")
      _isj_wt_sql=$(recall_int_or_null "$_f_wt")
      _isj_ss_sql=$(recall_int_or_null "$_f_ss")
      _isj_pm_sql=$(recall_int_or_null "$_f_pm")
      _isj_dt_sql=$(recall_int_or_null "$_f_dt")
      _isj_bt_sql=$(recall_int_or_null "$_f_bt")
      _isj_sg_sql=$(recall_int_or_null "$_f_sg")
      _isj_it_sql=$(recall_int_or_null "$_f_it")
      _isj_sql="$_isj_sql
INSERT INTO executions(project,feature,wave,execucao_id,source_ts,source_id,status,motivo_termino,etapa_corrente,iniciada_em,terminada_em,duracao_segundos,stack_sugerida,ondas_total,tool_calls_total,wallclock_total_segundos,subagentes_spawned,profundidade_max,decisoes_total,bloqueios_humanos_total,sugestoes_skills_total,issues_toolkit_abertas,ingested_at)
VALUES('$(sql_escape "$_isj_project")','$(sql_escape "$_isj_feature")','-','$(sql_escape "$_f_eid")','$(sql_escape "$_f_ini")','$(sql_escape "$_f_eid")','$(sql_escape "$_f_st")','$(sql_escape "$_f_mt")','$(sql_escape "$_f_ec")','$(sql_escape "$_f_ini")','$(sql_escape "$_f_ter")',$_isj_dur_sql,'$(sql_escape "$_f_stk")',$_isj_ot_sql,$_isj_tc_sql,$_isj_wt_sql,$_isj_ss_sql,$_isj_pm_sql,$_isj_dt_sql,$_isj_bt_sql,$_isj_sg_sql,$_isj_it_sql,'$(sql_escape "$_isj_now")')
ON CONFLICT(project,feature,wave,source_id) DO UPDATE SET source_ts=excluded.source_ts,status=excluded.status,motivo_termino=excluded.motivo_termino,etapa_corrente=excluded.etapa_corrente,iniciada_em=excluded.iniciada_em,terminada_em=excluded.terminada_em,duracao_segundos=excluded.duracao_segundos,stack_sugerida=excluded.stack_sugerida,ondas_total=excluded.ondas_total,tool_calls_total=excluded.tool_calls_total,wallclock_total_segundos=excluded.wallclock_total_segundos,subagentes_spawned=excluded.subagentes_spawned,profundidade_max=excluded.profundidade_max,decisoes_total=excluded.decisoes_total,bloqueios_humanos_total=excluded.bloqueios_humanos_total,sugestoes_skills_total=excluded.sugestoes_skills_total,issues_toolkit_abertas=excluded.issues_toolkit_abertas,ingested_at=excluded.ingested_at;"
      _isj_n_exec=1
    fi
  fi

  # ---- waves (grao = onda; 1 linha por .ondas[]; wave=source_id=wave_id) ----
  # Deriva etapas (join ","), inicio/fim, wallclock_seconds, tool_calls,
  # motivo_termino (texto livre filtrado), n_etapas, n_skills (derivados via
  # length). Onda aberta (fim null) -> fim vazio, sem erro (1.3.5).
  _isj_n_wave=0
  _isj_wave_lines=$(jq -r '
    (.ondas // [])
    | to_entries[]
    | .key as $wi
    | .value as $w
    | [($w.id // "onda-\($wi)"),
       (($w.etapas_executadas // []) | join(",")),
       ($w.inicio // ""),
       ($w.fim // ""),
       (($w.wallclock_seconds // "")|tostring),
       (($w.tool_calls // "")|tostring),
       ($w.motivo_termino // ""),
       (($w.etapas_executadas // []) | length | tostring),
       (($w.skills_invoked // []) | length | tostring)]
    | @base64' "$_isj_state" 2>/dev/null) || _isj_wave_lines=""
  if [ -n "$_isj_wave_lines" ]; then
    _isj_OLDIFS="$IFS"; IFS='
'
    for _isj_row in $_isj_wave_lines; do
      _isj_decoded=$(printf '%s' "$_isj_row" | base64 -d 2>/dev/null) || continue
      _f_wid=$(printf '%s' "$_isj_decoded" | jq -r '.[0]' 2>/dev/null | strip_nul)
      _f_etp=$(printf '%s' "$_isj_decoded" | jq -r '.[1]' 2>/dev/null | strip_nul)
      _f_ini=$(printf '%s' "$_isj_decoded" | jq -r '.[2]' 2>/dev/null | strip_nul)
      _f_fim=$(printf '%s' "$_isj_decoded" | jq -r '.[3]' 2>/dev/null | strip_nul)
      _f_wc=$(printf '%s' "$_isj_decoded" | jq -r '.[4]' 2>/dev/null | strip_nul)
      _f_tc=$(printf '%s' "$_isj_decoded" | jq -r '.[5]' 2>/dev/null | strip_nul)
      _f_mt=$(printf '%s' "$_isj_decoded" | jq -r '.[6]' 2>/dev/null | strip_nul)
      _f_ne=$(printf '%s' "$_isj_decoded" | jq -r '.[7]' 2>/dev/null | strip_nul)
      _f_ns=$(printf '%s' "$_isj_decoded" | jq -r '.[8]' 2>/dev/null | strip_nul)
      [ -n "$_f_wid" ] || continue
      _f_mt=$(recall_scrub "$_f_mt")
      _isj_wc_sql=$(recall_int_or_null "$_f_wc")
      _isj_tc_sql=$(recall_int_or_null "$_f_tc")
      _isj_ne_sql=$(recall_int_or_null "$_f_ne")
      _isj_ns_sql=$(recall_int_or_null "$_f_ns")
      _isj_sql="$_isj_sql
INSERT INTO waves(project,feature,wave,execucao_id,source_ts,source_id,etapas,inicio,fim,wallclock_seconds,tool_calls,motivo_termino,n_etapas,n_skills,ingested_at)
VALUES('$(sql_escape "$_isj_project")','$(sql_escape "$_isj_feature")','$(sql_escape "$_f_wid")','$(sql_escape "$_isj_exec_id")','$(sql_escape "$_f_ini")','$(sql_escape "$_f_wid")','$(sql_escape "$_f_etp")','$(sql_escape "$_f_ini")','$(sql_escape "$_f_fim")',$_isj_wc_sql,$_isj_tc_sql,'$(sql_escape "$_f_mt")',$_isj_ne_sql,$_isj_ns_sql,'$(sql_escape "$_isj_now")')
ON CONFLICT(project,feature,wave,source_id) DO UPDATE SET source_ts=excluded.source_ts,etapas=excluded.etapas,inicio=excluded.inicio,fim=excluded.fim,wallclock_seconds=excluded.wallclock_seconds,tool_calls=excluded.tool_calls,motivo_termino=excluded.motivo_termino,n_etapas=excluded.n_etapas,n_skills=excluded.n_skills,ingested_at=excluded.ingested_at;"
      _isj_n_wave=$((_isj_n_wave + 1))
    done
    IFS="$_isj_OLDIFS"
  fi

  # ---- alert_signals: movimento circular (tipo='circular') ----
  # 1 linha por entrada de .historico_movimento_circular[]. As entradas sao
  # hashes (problema_hash/solucao_hash/timestamp) — descricao sintetizada e
  # ainda filtrada (FR-006, campo marcado como texto livre no data-model).
  # source_id = circular:<wave_id|->:<ordinal>; circular nao tem wave_id,
  # usa-se '-' como wave (grao = execucao). valor_consumido/threshold NULL.
  _isj_n_alert=0
  _isj_circ_lines=$(jq -r '
    (.historico_movimento_circular // [])
    | to_entries[]
    | [(.key|tostring),
       (.value.timestamp // ""),
       ("repeticao problema=\(.value.problema_hash // "?") solucao=\(.value.solucao_hash // "?")")]
    | @base64' "$_isj_state" 2>/dev/null) || _isj_circ_lines=""
  if [ -n "$_isj_circ_lines" ]; then
    _isj_OLDIFS="$IFS"; IFS='
'
    for _isj_row in $_isj_circ_lines; do
      _isj_decoded=$(printf '%s' "$_isj_row" | base64 -d 2>/dev/null) || continue
      _f_ord=$(printf '%s' "$_isj_decoded" | jq -r '.[0]' 2>/dev/null | strip_nul)
      _f_ts=$(printf '%s' "$_isj_decoded" | jq -r '.[1]' 2>/dev/null | strip_nul)
      _f_desc=$(printf '%s' "$_isj_decoded" | jq -r '.[2]' 2>/dev/null | strip_nul)
      _f_desc=$(recall_scrub "$_f_desc")
      _f_sid="circular:-:$_f_ord"
      _isj_sql="$_isj_sql
INSERT INTO alert_signals(project,feature,wave,execucao_id,source_ts,source_id,tipo,subtipo,valor_consumido,valor_threshold,descricao,ingested_at)
VALUES('$(sql_escape "$_isj_project")','$(sql_escape "$_isj_feature")','-','$(sql_escape "$_isj_exec_id")','$(sql_escape "$_f_ts")','$(sql_escape "$_f_sid")','circular',NULL,NULL,NULL,'$(sql_escape "$_f_desc")','$(sql_escape "$_isj_now")')
ON CONFLICT(project,feature,wave,source_id) DO UPDATE SET source_ts=excluded.source_ts,tipo=excluded.tipo,subtipo=excluded.subtipo,valor_consumido=excluded.valor_consumido,valor_threshold=excluded.valor_threshold,descricao=excluded.descricao,ingested_at=excluded.ingested_at;"
      _isj_n_alert=$((_isj_n_alert + 1))
    done
    IFS="$_isj_OLDIFS"
  fi

  # ---- alert_signals: breach de orcamento (tipo='budget_breach') ----
  # Cruza .orcamentos (top-level) com consumo (FR-014, data-model §SinalDeAlerta
  # L139-144). Per-onda: tool_calls > tool_calls_threshold_onda, wallclock_seconds
  # > wallclock_threshold_segundos. Per-execucao (wave='-'):
  # ciclos_consumidos_etapa_corrente > ciclos_max_por_etapa,
  # profundidade_corrente_subagentes >= recursividade_max, tamanho do state.json
  # > estado_size_threshold_bytes. Cada cruzamento excedido gera 1 sinal.
  # source_id = budget_breach:<wave_id|->:<ordinal> (ordinal = indice do breach
  # DENTRO do seu grupo de fonte, estavel por construcao do jq). Sem texto livre
  # (FR-006: subtipo/valores sao estruturados, descricao NULL para breach).
  # Tamanho do state.json (estado_size) e medido em shell (jq nao faz stat) e
  # injetado via --argjson. Best-effort: falha de wc -> -1 (nunca dispara breach).
  _isj_state_size=$(wc -c < "$_isj_state" 2>/dev/null | tr -d ' ') || _isj_state_size=-1
  case "$_isj_state_size" in ''|*[!0-9-]*) _isj_state_size=-1 ;; esac
  _isj_breach_lines=$(jq -r --argjson sz "$_isj_state_size" '
    (.orcamentos // {}) as $o
    # Per-onda: linhas {wave, sub, consumido, threshold} para cada excedido.
    | [ (.ondas // [])
        | to_entries[]
        | .value as $w
        | ($w.id // "onda-\(.key)") as $wid
        | (
            (if (($o.tool_calls_threshold_onda // null) != null
                 and ($w.tool_calls // null) != null
                 and ($w.tool_calls > $o.tool_calls_threshold_onda))
             then [{wave:$wid, sub:"tool_calls", c:$w.tool_calls, t:$o.tool_calls_threshold_onda}]
             else [] end)
          + (if (($o.wallclock_threshold_segundos // null) != null
                 and ($w.wallclock_seconds // null) != null
                 and ($w.wallclock_seconds > $o.wallclock_threshold_segundos))
             then [{wave:$wid, sub:"wallclock", c:$w.wallclock_seconds, t:$o.wallclock_threshold_segundos}]
             else [] end)
          )
        | .[]
      ]
    # Per-execucao (wave="-"): ciclos, profundidade, estado_size.
    + (
        (if (($o.ciclos_max_por_etapa // null) != null
             and ($o.ciclos_consumidos_etapa_corrente // null) != null
             and ($o.ciclos_consumidos_etapa_corrente > $o.ciclos_max_por_etapa))
         then [{wave:"-", sub:"ciclos", c:$o.ciclos_consumidos_etapa_corrente, t:$o.ciclos_max_por_etapa}]
         else [] end)
      + (if (($o.recursividade_max // null) != null
             and ($o.profundidade_corrente_subagentes // null) != null
             and ($o.profundidade_corrente_subagentes >= $o.recursividade_max))
         then [{wave:"-", sub:"profundidade", c:$o.profundidade_corrente_subagentes, t:$o.recursividade_max}]
         else [] end)
      + (if (($o.estado_size_threshold_bytes // null) != null
             and ($sz != null) and ($sz >= 0)
             and ($sz > $o.estado_size_threshold_bytes))
         then [{wave:"-", sub:"estado_size", c:$sz, t:$o.estado_size_threshold_bytes}]
         else [] end)
      )
    # Ordinal estavel POR grupo de fonte (wave): group_by preserva ordem de
    # entrada; enumera dentro de cada grupo. Emite tupla codificada b64.
    | group_by(.wave)
    | map(to_entries | map(.value + {ord: .key}))
    | flatten
    | .[]
    | [.wave, .sub, (.c|tostring), (.t|tostring), (.ord|tostring)]
    | @base64' "$_isj_state" 2>/dev/null) || _isj_breach_lines=""
  if [ -n "$_isj_breach_lines" ]; then
    _isj_OLDIFS="$IFS"; IFS='
'
    for _isj_row in $_isj_breach_lines; do
      _isj_decoded=$(printf '%s' "$_isj_row" | base64 -d 2>/dev/null) || continue
      _f_bw=$(printf '%s' "$_isj_decoded" | jq -r '.[0]' 2>/dev/null | strip_nul)
      _f_bsub=$(printf '%s' "$_isj_decoded" | jq -r '.[1]' 2>/dev/null | strip_nul)
      _f_bc=$(printf '%s' "$_isj_decoded" | jq -r '.[2]' 2>/dev/null | strip_nul)
      _f_bt=$(printf '%s' "$_isj_decoded" | jq -r '.[3]' 2>/dev/null | strip_nul)
      _f_bord=$(printf '%s' "$_isj_decoded" | jq -r '.[4]' 2>/dev/null | strip_nul)
      [ -n "$_f_bsub" ] || continue
      _isj_bc_sql=$(recall_int_or_null "$_f_bc")
      _isj_bt_sql=$(recall_int_or_null "$_f_bt")
      _f_bsid="budget_breach:$_f_bw:$_f_bord"
      _isj_sql="$_isj_sql
INSERT INTO alert_signals(project,feature,wave,execucao_id,source_ts,source_id,tipo,subtipo,valor_consumido,valor_threshold,descricao,ingested_at)
VALUES('$(sql_escape "$_isj_project")','$(sql_escape "$_isj_feature")','$(sql_escape "$_f_bw")','$(sql_escape "$_isj_exec_id")','$(sql_escape "$_isj_now")','$(sql_escape "$_f_bsid")','budget_breach','$(sql_escape "$_f_bsub")',$_isj_bc_sql,$_isj_bt_sql,NULL,'$(sql_escape "$_isj_now")')
ON CONFLICT(project,feature,wave,source_id) DO UPDATE SET source_ts=excluded.source_ts,tipo=excluded.tipo,subtipo=excluded.subtipo,valor_consumido=excluded.valor_consumido,valor_threshold=excluded.valor_threshold,descricao=excluded.descricao,ingested_at=excluded.ingested_at;"
      _isj_n_alert=$((_isj_n_alert + 1))
    done
    IFS="$_isj_OLDIFS"
  fi

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
  # Campos reais: id, decisao_id, status, pergunta, contexto_para_resposta,
  # resposta_humana (resposta), disparado_em, respondido_em, onda_id (quando
  # presente). Bloqueios sao feature-level; wave default 'bloq' se onda_id
  # ausente, garantindo chave de upsert estavel.
  # source_ts mantem o coalesce historico (respondido_em||disparado_em). As
  # colunas disparado_em/respondido_em sao preservadas SEPARADAS (FR-015) para
  # derivar latencia humana = respondido_em - disparado_em (NULL para bloqueio
  # aberto). decisao_id permite JOIN com decisions.etapa para a taxa de
  # auto-resolucao de clarify (FR-016). latencia_segundos materializada no
  # ingest (computavel sem nova tabela; data-model L175-186).
  _isj_n_bloq=0
  _isj_bloq_lines=$(jq -r '
    (.bloqueios_humanos // [])
    | to_entries[]
    | .value as $b
    | (if (($b.disparado_em // "") != "" and ($b.respondido_em // "") != "")
       then (($b.respondido_em|fromdateiso8601) - ($b.disparado_em|fromdateiso8601) | tostring)
       else "" end) as $lat
    | [($b.id // "bloq-\(.key)"),
       ($b.onda_id // "bloq"),
       ($b.respondido_em // $b.disparado_em // $b.timestamp // ""),
       ($b.status // ""),
       ($b.pergunta // ""),
       ($b.contexto_para_resposta // ""),
       ($b.resposta_humana // $b.resposta // ""),
       ($b.decisao_id // ""),
       ($b.disparado_em // ""),
       ($b.respondido_em // ""),
       $lat]
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
      _f_decid=$(printf '%s' "$_isj_decoded" | jq -r '.[7]' 2>/dev/null | strip_nul)
      _f_disp=$(printf '%s' "$_isj_decoded" | jq -r '.[8]' 2>/dev/null | strip_nul)
      _f_respat=$(printf '%s' "$_isj_decoded" | jq -r '.[9]' 2>/dev/null | strip_nul)
      _f_lat=$(printf '%s' "$_isj_decoded" | jq -r '.[10]' 2>/dev/null | strip_nul)
      _f_perg=$(recall_scrub "$_f_perg")
      _f_cpr=$(recall_scrub "$_f_cpr")
      _f_resp=$(recall_scrub "$_f_resp")
      # decisao_id / timestamps sao estruturados (sem filtro). latencia numerica.
      _isj_lat_sql=$(recall_int_or_null "$_f_lat")
      _isj_sql="$_isj_sql
INSERT INTO bloqueios(project,feature,wave,execucao_id,source_ts,source_id,status,pergunta,contexto_para_resposta,resposta,decisao_id,disparado_em,respondido_em,latencia_segundos,ingested_at)
VALUES('$(sql_escape "$_isj_project")','$(sql_escape "$_isj_feature")','$(sql_escape "$_f_wave")','$(sql_escape "$_isj_exec_id")','$(sql_escape "$_f_ts")','$(sql_escape "$_f_sid")','$(sql_escape "$_f_st")','$(sql_escape "$_f_perg")','$(sql_escape "$_f_cpr")','$(sql_escape "$_f_resp")','$(sql_escape "$_f_decid")','$(sql_escape "$_f_disp")','$(sql_escape "$_f_respat")',$_isj_lat_sql,'$(sql_escape "$_isj_now")')
ON CONFLICT(project,feature,wave,source_id) DO UPDATE SET source_ts=excluded.source_ts,status=excluded.status,pergunta=excluded.pergunta,contexto_para_resposta=excluded.contexto_para_resposta,resposta=excluded.resposta,decisao_id=excluded.decisao_id,disparado_em=excluded.disparado_em,respondido_em=excluded.respondido_em,latencia_segundos=excluded.latencia_segundos,ingested_at=excluded.ingested_at;
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

  # ---- tasks (camada B; grao = task por execucao) ----
  # Campos do state.json: task_id, wave_id, titulo, outcome, testes_rodados,
  # testes_passados, lint_ok (bool -> 0/1), arquivos_tocados (array -> length).
  # Chave natural: wave=<wave_id da task>, source_id=task_id. So `titulo` e
  # texto livre (UX do painel) e passa por secrets-filter (FR-017); os demais
  # campos sao estruturados/numericos. Tasks NAO alimentam knowledge_fts
  # (metrica, nao corpo pesquisavel).
  # Retro-compat (FR-022/SC-009): .tasks ausente -> .tasks[]? // empty -> 0 linhas;
  # .titulo ausente -> "" (indices v2 e states antigos seguem ingeridos).
  _isj_n_task=0
  _isj_task_lines=$(jq -r '
    (.tasks[]? // empty)
    | [(.task_id // ""),
       (.wave_id // ""),
       (.outcome // ""),
       ((.testes_rodados // "")|tostring),
       ((.testes_passados // "")|tostring),
       (if (.lint_ok == true) then "1"
        elif (.lint_ok == false) then "0"
        else "" end),
       (((.arquivos_tocados // []) | length)|tostring),
       (.titulo // "")]
    | @base64' "$_isj_state" 2>/dev/null) || _isj_task_lines=""
  if [ -n "$_isj_task_lines" ]; then
    _isj_OLDIFS="$IFS"; IFS='
'
    for _isj_row in $_isj_task_lines; do
      _isj_decoded=$(printf '%s' "$_isj_row" | base64 -d 2>/dev/null) || continue
      _f_tid=$(printf '%s' "$_isj_decoded" | jq -r '.[0]' 2>/dev/null | strip_nul)
      _f_twid=$(printf '%s' "$_isj_decoded" | jq -r '.[1]' 2>/dev/null | strip_nul)
      _f_toc=$(printf '%s' "$_isj_decoded" | jq -r '.[2]' 2>/dev/null | strip_nul)
      _f_tr=$(printf '%s' "$_isj_decoded" | jq -r '.[3]' 2>/dev/null | strip_nul)
      _f_tp=$(printf '%s' "$_isj_decoded" | jq -r '.[4]' 2>/dev/null | strip_nul)
      _f_tlo=$(printf '%s' "$_isj_decoded" | jq -r '.[5]' 2>/dev/null | strip_nul)
      _f_tat=$(printf '%s' "$_isj_decoded" | jq -r '.[6]' 2>/dev/null | strip_nul)
      _f_ttit=$(printf '%s' "$_isj_decoded" | jq -r '.[7]' 2>/dev/null | strip_nul)
      # task_id e a chave natural; sem id -> pula (FR-019).
      [ -n "$_f_tid" ] || continue
      _f_ttit=$(recall_scrub "$_f_ttit")  # unico campo texto livre (FR-017)
      _isj_tr_sql=$(recall_int_or_null "$_f_tr")
      _isj_tp_sql=$(recall_int_or_null "$_f_tp")
      _isj_tlo_sql=$(recall_int_or_null "$_f_tlo")
      _isj_tat_sql=$(recall_int_or_null "$_f_tat")
      _isj_sql="$_isj_sql
INSERT INTO tasks(project,feature,wave,execucao_id,source_ts,source_id,titulo,outcome,testes_rodados,testes_passados,lint_ok,arquivos_tocados,ingested_at)
VALUES('$(sql_escape "$_isj_project")','$(sql_escape "$_isj_feature")','$(sql_escape "$_f_twid")','$(sql_escape "$_isj_exec_id")','','$(sql_escape "$_f_tid")','$(sql_escape "$_f_ttit")','$(sql_escape "$_f_toc")',$_isj_tr_sql,$_isj_tp_sql,$_isj_tlo_sql,$_isj_tat_sql,'$(sql_escape "$_isj_now")')
ON CONFLICT(project,feature,wave,source_id) DO UPDATE SET source_ts=excluded.source_ts,titulo=excluded.titulo,outcome=excluded.outcome,testes_rodados=excluded.testes_rodados,testes_passados=excluded.testes_passados,lint_ok=excluded.lint_ok,arquivos_tocados=excluded.arquivos_tocados,ingested_at=excluded.ingested_at;"
      _isj_n_task=$((_isj_n_task + 1))
    done
    IFS="$_isj_OLDIFS"
  fi

  # ---- events (camada B; grao = evento; timeline cronologica) ----
  # Campos NOVOS: event_type (texto livre por convencao — SEM allowlist aqui;
  # MVP {lock_contention,validation_failed,wave_retry,schedule_wait} +
  # recall_consulted do read-back loop), timestamp (ISO),
  # descricao (texto livre OPCIONAL -> scrubbed FR-006). wave='-' (timeline
  # e grao de execucao), source_id=<event_type>:<timestamp> (chave natural),
  # source_ts=timestamp (ordem cronologica consultavel via ORDER BY source_ts).
  # Events NAO alimentam knowledge_fts. Retro-compat: .eventos[]? // empty.
  _isj_n_event=0
  _isj_event_lines=$(jq -r '
    (.eventos[]? // empty)
    | [(.event_type // ""),
       (.timestamp // ""),
       (.descricao // "")]
    | @base64' "$_isj_state" 2>/dev/null) || _isj_event_lines=""
  if [ -n "$_isj_event_lines" ]; then
    _isj_OLDIFS="$IFS"; IFS='
'
    for _isj_row in $_isj_event_lines; do
      _isj_decoded=$(printf '%s' "$_isj_row" | base64 -d 2>/dev/null) || continue
      _f_evt=$(printf '%s' "$_isj_decoded" | jq -r '.[0]' 2>/dev/null | strip_nul)
      _f_ets=$(printf '%s' "$_isj_decoded" | jq -r '.[1]' 2>/dev/null | strip_nul)
      _f_edsc=$(printf '%s' "$_isj_decoded" | jq -r '.[2]' 2>/dev/null | strip_nul)
      # event_type + timestamp formam a chave natural; sem ambos -> pula.
      [ -n "$_f_evt" ] && [ -n "$_f_ets" ] || continue
      # descricao e texto livre -> filtro de segredo (FR-006); event_type e
      # timestamp sao estruturados e NAO passam pelo filtro.
      _f_edsc=$(recall_scrub "$_f_edsc")
      _f_esid="$_f_evt:$_f_ets"
      _isj_sql="$_isj_sql
INSERT INTO events(project,feature,wave,execucao_id,source_ts,source_id,event_type,timestamp,descricao,ingested_at)
VALUES('$(sql_escape "$_isj_project")','$(sql_escape "$_isj_feature")','-','$(sql_escape "$_isj_exec_id")','$(sql_escape "$_f_ets")','$(sql_escape "$_f_esid")','$(sql_escape "$_f_evt")','$(sql_escape "$_f_ets")','$(sql_escape "$_f_edsc")','$(sql_escape "$_isj_now")')
ON CONFLICT(project,feature,wave,source_id) DO UPDATE SET source_ts=excluded.source_ts,event_type=excluded.event_type,timestamp=excluded.timestamp,descricao=excluded.descricao,ingested_at=excluded.ingested_at;"
      _isj_n_event=$((_isj_n_event + 1))
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
  RECALL_TOTAL_EXEC=$((${RECALL_TOTAL_EXEC:-0} + _isj_n_exec))
  RECALL_TOTAL_WAVE=$((${RECALL_TOTAL_WAVE:-0} + _isj_n_wave))
  RECALL_TOTAL_ALERT=$((${RECALL_TOTAL_ALERT:-0} + _isj_n_alert))
  RECALL_TOTAL_TASK=$((${RECALL_TOTAL_TASK:-0} + _isj_n_task))
  RECALL_TOTAL_EVENT=$((${RECALL_TOTAL_EVENT:-0} + _isj_n_event))
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
  RECALL_TOTAL_EXEC=0; RECALL_TOTAL_WAVE=0; RECALL_TOTAL_ALERT=0
  RECALL_TOTAL_TASK=0; RECALL_TOTAL_EVENT=0
  recall_ingest_state_json "$_ing_state_dir/state.json" "$_ing_db"

  printf 'ingested: %d decisions, %d bloqueios, %d retros, %d skills, %d executions, %d waves, %d alerts, %d tasks, %d events\n' \
    "${RECALL_TOTAL_DEC:-0}" "${RECALL_TOTAL_BLOQ:-0}" "${RECALL_TOTAL_RETRO:-0}" "${RECALL_TOTAL_SKILL:-0}" \
    "${RECALL_TOTAL_EXEC:-0}" "${RECALL_TOTAL_WAVE:-0}" "${RECALL_TOTAL_ALERT:-0}" \
    "${RECALL_TOTAL_TASK:-0}" "${RECALL_TOTAL_EVENT:-0}"
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
# FASE 4.bis — Leitura-para-contexto (cstk recall --context)
# Modo NOVO (recall-autoconsume), distinto de busca/--ingest/--reindex. Retorna
# achados do indice como bloco markdown enxuto, pronto para injecao em prompt
# (read-back loop). Read-only, best-effort: toda degradacao = no-op (stdout
# vazio + exit 0). Difere do modo busca em: (a) composicao OR (fts_query_escape_or)
# em vez de AND; (b) anti-eco --exclude-feature no SQL; (c) --max-bytes (teto duro
# de bytes); (d) render markdown 1-linha/achado; (e) defaults --limit 4.
# Contrato: docs/specs/_archived/recall-autoconsume/contracts/cstk-recall-context.md
# ==========================================================================

recall_mode_context() {
  _cx_query=""
  _cx_project=""
  _cx_type=""
  _cx_exclude=""
  _cx_limit="4"
  _cx_max_bytes="2000"
  _cx_db_flag=""
  _cx_have_query=0

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --context) ;;
      --project) shift; _cx_project="${1:-}" ;;
      --type) shift; _cx_type="${1:-}" ;;
      --exclude-feature) shift; _cx_exclude="${1:-}" ;;
      --limit) shift; _cx_limit="${1:-}" ;;
      --max-bytes) shift; _cx_max_bytes="${1:-}" ;;
      --db) shift; _cx_db_flag="${1:-}" ;;
      -h|--help) recall_usage; return "$RECALL_EXIT_OK" ;;
      --*) log_error "recall --context: flag invalida: $1"; return "$RECALL_EXIT_USAGE" ;;
      *)
        if [ "$_cx_have_query" -eq 0 ]; then
          _cx_query="$1"; _cx_have_query=1
        else
          log_error "recall --context: termos extras inesperados: $1"
          return "$RECALL_EXIT_USAGE"
        fi
        ;;
    esac
    shift || break
  done

  # Termos ausentes => USAGE (alinhado a tabela de exit codes do contrato).
  if [ "$_cx_have_query" -eq 0 ]; then
    log_error "recall --context: termos obrigatorios"
    return "$RECALL_EXIT_USAGE"
  fi

  # Rejeicao de NUL em TODOS os inputs do usuario ANTES de qualquer
  # escaping/validacao/interpolacao (consistente com modo busca; CHK009).
  for _cx_in in "$_cx_query" "$_cx_project" "$_cx_type" "$_cx_exclude" "$_cx_db_flag"; do
    if value_has_nul "$_cx_in"; then
      log_error "recall --context: byte NUL em input rejeitado"
      return "$RECALL_EXIT_USAGE"
    fi
  done

  # --limit e --max-bytes integer-validados (nao escaping); rejeita com exit 2.
  if ! validate_limit "$_cx_limit"; then
    log_error "recall --context: --limit deve ser inteiro positivo (recebido: '$_cx_limit')"
    return "$RECALL_EXIT_USAGE"
  fi
  if ! validate_limit "$_cx_max_bytes"; then
    log_error "recall --context: --max-bytes deve ser inteiro positivo (recebido: '$_cx_max_bytes')"
    return "$RECALL_EXIT_USAGE"
  fi

  # --type validado contra enum (se fornecido).
  if [ -n "$_cx_type" ] && ! validate_type "$_cx_type"; then
    log_error "recall --context: --type fora do enum (decision|bloqueio|retro|skill): '$_cx_type'"
    return "$RECALL_EXIT_USAGE"
  fi

  # ---- Gates de degradacao graciosa (no-op silencioso, exit 0) ----
  # FR-012: NENHUM caminho de degradacao retorna codigo != 0; stdout fica vazio.

  # Gate sqlite3 ausente => no-op. log_warn em stderr (diagnostico, sem vazar
  # conteudo do indice — CHK012).
  if ! recall_have_sqlite3; then
    log_warn "recall --context: sqlite3 indisponivel; no-op (read-back pulado)"
    return "$RECALL_EXIT_OK"
  fi

  _cx_db=$(recall_resolve_db "$_cx_db_flag")

  # Gate DB ausente => no-op (stdout vazio).
  if [ ! -f "$_cx_db" ]; then
    log_warn "recall --context: indice ausente ($_cx_db); no-op"
    return "$RECALL_EXIT_OK"
  fi

  # Gate DB corrompido => no-op. quick_check via leitura (read-only).
  _cx_ok=$(printf 'PRAGMA quick_check;\n' | sqlite3 -- "$_cx_db" 2>/dev/null | head -n 1) || _cx_ok=""
  if [ "$_cx_ok" != "ok" ]; then
    log_warn "recall --context: indice ilegivel/corrompido ($_cx_db); no-op"
    return "$RECALL_EXIT_OK"
  fi

  # ---- Montagem da query (OR + anti-eco + filtros), read-only ----
  # Duas camadas de escape (FTS5 por-token via fts_query_escape_or + SQL via
  # sql_escape), identico ao modo busca mas com composicao OR.
  _cx_match=$(sql_escape "$(fts_query_escape_or "$_cx_query")")
  _cx_where="WHERE knowledge_fts MATCH '$_cx_match'"
  # Anti-eco (FR-005): omite a feature corrente NO SQL (nao pos-filtro textual
  # fragil) usando sql_escape — valores manipulados de feature nao contornam.
  if [ -n "$_cx_exclude" ]; then
    _cx_where="$_cx_where AND feature != '$(sql_escape "$_cx_exclude")'"
  fi
  if [ -n "$_cx_type" ]; then
    _cx_where="$_cx_where AND type = '$(sql_escape "$_cx_type")'"
  fi
  if [ -n "$_cx_project" ]; then
    _cx_where="$_cx_where AND project = '$(sql_escape "$_cx_project")'"
  fi
  # SEM piso de bm25 (FR-007). bm25 ASC (mais relevante primeiro), LIMIT N.
  _cx_sql="SELECT type, project, feature, wave, source_ts, source_id, body
FROM knowledge_fts $_cx_where
ORDER BY bm25(knowledge_fts) LIMIT $_cx_limit;"

  # Executa SOMENTE via recall_query_sql (leitura). NUNCA recall_run_sql /
  # recall_apply_schema (escrita) — read-only (FR-014). database is locked
  # durante ingestao concorrente => .timeout 5000 (em recall_query_sql); se
  # ainda falhar, resultado vazio => no-op (nunca propaga erro).
  _cx_out=$(recall_query_sql "$_cx_db" ".mode list
.separator |@|
$_cx_sql") || _cx_out=""

  # ---- Render do ContextBlock (markdown enxuto, teto duro de bytes) ----
  # K=0 (zero rows apos anti-eco/filtros) => stdout VAZIO (FR-017 distingue
  # K=0 de K>0; sem cabecalho, sem erro).
  if [ -z "$_cx_out" ]; then
    return "$RECALL_EXIT_OK"
  fi

  # Monta as linhas de achado primeiro (cada uma <=280 chars no body), depois
  # aplica o teto de bytes cortando pelo ULTIMO achado inteiro que cabe. O
  # cabecalho blockquote (2 linhas) entra no orcamento de bytes.
  _cx_header="> Aprendizado recuperado (read-back loop) — K achados de execucoes passadas."
  _cx_body_acc=""
  _cx_k=0
  # Tamanho corrente do bloco = header + linha em branco + linhas acumuladas.
  # Recomputado a cada achado candidato antes de aceitar.
  _cx_lines_tmp=$(printf '%s' "$_cx_out")
  _cx_OLDIFS="$IFS"
  IFS='
'
  for _cx_line in $_cx_lines_tmp; do
    [ -n "$_cx_line" ] || continue
    _r_type=$(printf '%s' "$_cx_line" | awk -F '\\|@\\|' '{print $1}')
    _r_proj=$(printf '%s' "$_cx_line" | awk -F '\\|@\\|' '{print $2}')
    _r_feat=$(printf '%s' "$_cx_line" | awk -F '\\|@\\|' '{print $3}')
    _r_wave=$(printf '%s' "$_cx_line" | awk -F '\\|@\\|' '{print $4}')
    _r_ts=$(printf '%s' "$_cx_line" | awk -F '\\|@\\|' '{print $5}')
    _r_body=$(printf '%s' "$_cx_line" | awk -F '\\|@\\|' '{print $7}')
    # Trunca body por achado (280 chars + sufixo "..." quando cortado) para um
    # achado gigante nao estourar sozinho o orcamento.
    _r_body_short=$(printf '%s' "$_r_body" | cut -c1-280)
    if [ "$(printf '%s' "$_r_body" | wc -c | tr -d ' ')" -gt 280 ]; then
      _r_body_short="$_r_body_short..."
    fi
    _cx_entry="- **[$_r_type]** $_r_proj/$_r_feat/$_r_wave ($_r_ts): $_r_body_short"
    # Candidato a bloco com este achado adicionado.
    if [ -z "$_cx_body_acc" ]; then
      _cx_cand="$_cx_header

$_cx_entry"
    else
      _cx_cand="$_cx_header

$_cx_body_acc
$_cx_entry"
    fi
    # Teto duro: se este achado estoura --max-bytes, para (nunca corta no meio).
    _cx_cand_bytes=$(printf '%s\n' "$_cx_cand" | wc -c | tr -d ' ')
    if [ "$_cx_cand_bytes" -gt "$_cx_max_bytes" ]; then
      # Se nem o PRIMEIRO achado cabe, emite no-op (bloco vazio): preferir
      # silencio a um cabecalho orfao sem achados.
      break
    fi
    if [ -z "$_cx_body_acc" ]; then
      _cx_body_acc="$_cx_entry"
    else
      _cx_body_acc="$_cx_body_acc
$_cx_entry"
    fi
    _cx_k=$((_cx_k + 1))
  done
  IFS="$_cx_OLDIFS"

  # Se nenhum achado coube (primeiro ja estourava o teto) => no-op.
  if [ "$_cx_k" -eq 0 ]; then
    return "$RECALL_EXIT_OK"
  fi

  # Emite o bloco final. K>=1 garantido aqui.
  printf '%s\n\n%s\n' "$_cx_header" "$_cx_body_acc"
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
  RECALL_TOTAL_EXEC=0; RECALL_TOTAL_WAVE=0; RECALL_TOTAL_ALERT=0
  RECALL_TOTAL_TASK=0; RECALL_TOTAL_EVENT=0
  _rx_count=0
  # Varre feature-00c-state/*/state.json e agente-00c-state/state.json.
  # find e portavel; -path com globs simples.
  # IMPORTANTE: `find` sobre uma raiz ampla (ex: HOME default) sai com status
  # !=0 ao bater em diretorios sem permissao, MESMO tendo impresso matches
  # validos no stdout. Usar `|| _rx_states=""` aqui descartava esses matches —
  # e como o reindex apaga o db ANTES de repopular, o indice terminava VAZIO
  # (perda de dados). `|| :` preserva o stdout ja capturado pela command-subst.
  _rx_states=$(find "$_rx_states_root" \
      -type f -name 'state.json' \
      \( -path '*/.claude/feature-00c-state/*/state.json' \
         -o -path '*/.claude/agente-00c-state/state.json' \) \
      2>/dev/null) || :
  if [ -n "$_rx_states" ]; then
    _rx_OLDIFS="$IFS"; IFS='
'
    for _rx_sj in $_rx_states; do
      recall_ingest_state_json "$_rx_sj" "$_rx_db"
      _rx_count=$((_rx_count + 1))
    done
    IFS="$_rx_OLDIFS"
  fi

  printf 'reindexed: %d state files (%d decisions, %d bloqueios, %d retros, %d skills, %d executions, %d waves, %d alerts, %d tasks, %d events)\n' \
    "$_rx_count" "${RECALL_TOTAL_DEC:-0}" "${RECALL_TOTAL_BLOQ:-0}" "${RECALL_TOTAL_RETRO:-0}" "${RECALL_TOTAL_SKILL:-0}" \
    "${RECALL_TOTAL_EXEC:-0}" "${RECALL_TOTAL_WAVE:-0}" "${RECALL_TOTAL_ALERT:-0}" \
    "${RECALL_TOTAL_TASK:-0}" "${RECALL_TOTAL_EVENT:-0}"
  return "$RECALL_EXIT_OK"
}
