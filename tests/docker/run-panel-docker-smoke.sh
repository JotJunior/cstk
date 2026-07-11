#!/bin/sh
# run-panel-docker-smoke.sh — regressao continua OPT-IN para RISCO #1
# (data-model.md::wal_readonly_verified) e para CHK017/US2 Acceptance
# Scenario 3 (escrita concorrente) e US2 Acceptance Scenario 2 (indice
# ausente). NAO faz parte de ./tests/run.sh (requer daemon Docker real +
# uma imagem cstk-panel ja construida localmente) -- mesma convencao de
# tests/docker/run-smoke.sh (ver README desta pasta / CLAUDE.md
# "Como testar scripts shell"): opt-in, invocado manualmente pelo
# mantenedor, nunca um hard dependency de CI.
#
# Ref: docs/specs/panel-docker/tasks.md FASE 5 (5.1.7, 5.2.2, 5.3.3)
#      docs/specs/panel-docker/quickstart.md Scenario 4/5/11
#      docs/specs/panel-docker/data-model.md::wal_readonly_verified
#
# Uso:
#   tests/docker/run-panel-docker-smoke.sh [IMAGE_TAG]
#
# Pre-requisito: a imagem local do painel ja construida
# (docker images | grep cstk-panel). Construa com:
#   cstk serve --docker            # builda + sobe (Ctrl+C depois de subir)
# Sem IMAGE_TAG explicito, detecta automaticamente se houver exatamente
# uma imagem "cstk-panel:*" local.
#
# O que valida (3 cenarios independentes, cada um cria seu proprio
# knowledge.db REAL isolado — sqlite3 de verdade, journal_mode=wal,
# sidecars -shm/-wal — nunca mock/fixture do dado em si; so o CONTEUDO
# e sintetico/minimo para tornar o teste deterministico e repetivel):
#
#   1. scenario_data_parity_wal_readonly (RISCO #1 / Scenario 4):
#      leitura readonly better-sqlite3 (sem immutable=1) sobre mount
#      :ro do WAL abre sem erro e retorna contagem identica ao sqlite3
#      nativo do host para o MESMO arquivo.
#   2. scenario_concurrent_write_visible_without_restart (CHK017 /
#      Scenario 11 / US2 Acceptance Scenario 3): com o container JA
#      rodando, um INSERT feito pelo host fica visivel na PROXIMA
#      requisicao do painel containerizado, SEM restart.
#   3. scenario_missing_index_graceful (Scenario 5 / US2 Acceptance
#      Scenario 2): dir de dados vazio (knowledge.db ausente) -> painel
#      sobe e inicializa normalmente, sem falha, reportando o mesmo
#      estado degradado "db-missing" que o modo nativo reportaria.
#
# Sempre remove o container ao final de cada cenario (trap), mesmo em
# falha -- nunca deixa residuo Docker (containers/imagens temporarias de
# teste; a IMAGEM cstk-panel:<tag> em si e reaproveitada, nao removida).

set -eu

REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
CSTK_LIB="$REPO_ROOT/cli/lib"
export CSTK_LIB

# shellcheck source=/dev/null
. "$CSTK_LIB/serve-docker.sh"

PASS=0
FAIL=0

_section() {
  printf '\n========== %s ==========\n' "$1" >&2
}

_pass() {
  printf '  [PASS] %s\n' "$1" >&2
  PASS=$((PASS + 1))
}

_fail() {
  printf '  [FAIL] %s\n' "$1" >&2
  if [ -n "${2:-}" ]; then
    printf '         %s\n' "$2" >&2
  fi
  FAIL=$((FAIL + 1))
}

# ==== 0. Resolver IMAGE_TAG + pre-requisitos ====

_section "0. Pre-requisitos"

if ! command -v docker >/dev/null 2>&1; then
  printf 'run-panel-docker-smoke: erro: docker nao encontrado no PATH\n' >&2
  exit 1
fi
if ! docker info >/dev/null 2>&1; then
  printf 'run-panel-docker-smoke: erro: daemon Docker inacessivel (parado/sem permissao)\n' >&2
  exit 1
fi

IMAGE_TAG="${1:-}"
if [ -z "$IMAGE_TAG" ]; then
  _candidates=$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep '^cstk-panel:' || true)
  _n=$(printf '%s\n' "$_candidates" | grep -c . || true)
  if [ "$_n" = "1" ]; then
    IMAGE_TAG="$_candidates"
  else
    printf 'run-panel-docker-smoke: erro: nenhuma (ou mais de uma) imagem cstk-panel:* local; passe a tag explicitamente\n' >&2
    printf 'Construa uma imagem com: cstk serve --docker (builda + sobe; Ctrl+C depois)\n' >&2
    printf 'Imagens locais encontradas:\n%s\n' "${_candidates:-<nenhuma>}" >&2
    exit 1
  fi
fi

if ! docker image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
  printf 'run-panel-docker-smoke: erro: imagem "%s" nao encontrada localmente\n' "$IMAGE_TAG" >&2
  exit 1
fi
_pass "imagem local presente: $IMAGE_TAG"

_SMOKE_HOST="127.0.0.1"
_SMOKE_PORT="${CSTK_SMOKE_PORT:-15177}"
_SMOKE_CONTAINER="cstk-panel-smoke-test"

# _smoke_teardown: best-effort, idempotente -- roda em EXIT/INT/TERM.
# shellcheck disable=SC2329 # invocada indiretamente via trap abaixo
_smoke_teardown() {
  docker rm -f "$_SMOKE_CONTAINER" >/dev/null 2>&1 || :
}
trap '_smoke_teardown' EXIT INT TERM

# _smoke_run KDB_HOST_DIR
# Sobe o container com o MESMO hardening de producao
# (_serve_docker_main linhas 712-724), apontando para KDB_HOST_DIR.
_smoke_run() {
  _sr_kdb_dir="$1"
  docker rm -f "$_SMOKE_CONTAINER" >/dev/null 2>&1 || :
  docker run -d \
    --init \
    --rm \
    --name "$_SMOKE_CONTAINER" \
    --label "$_SD_MANAGEMENT_LABEL" \
    -p "${_SMOKE_HOST}:${_SMOKE_PORT}:${_SD_FORWARDER_PORT}" \
    -v "${_sr_kdb_dir}:${_SD_KDB_CONTAINER_DIR}:ro" \
    -e "CSTK_KNOWLEDGE_DB=${_SD_KDB_CONTAINER_DIR}/knowledge.db" \
    --cap-drop ALL \
    --security-opt no-new-privileges \
    --read-only \
    --tmpfs /tmp:rw,noexec,nosuid,size=64m \
    "$IMAGE_TAG" >/dev/null
}

# _smoke_wait_ready: poll bounded (nunca sleep-loop infinito) ate
# /api/v1/health responder 200, ou falha apos N tentativas.
_smoke_wait_ready() {
  _swr_i=0
  while [ "$_swr_i" -lt 30 ]; do
    if curl -s -o /dev/null -w '%{http_code}' --max-time 2 \
         "http://${_SMOKE_HOST}:${_SMOKE_PORT}/api/v1/health" 2>/dev/null \
         | grep -q '^200$'; then
      return 0
    fi
    _swr_i=$((_swr_i + 1))
    sleep 0.5
  done
  return 1
}

# _smoke_health: imprime o body de /api/v1/health.
_smoke_health() {
  curl -s --max-time 5 "http://${_SMOKE_HOST}:${_SMOKE_PORT}/api/v1/health"
}

# ==== 1. scenario_data_parity_wal_readonly (RISCO #1 / Scenario 4) ====

scenario_data_parity_wal_readonly() {
  _section "1. Paridade de dados + leitura WAL readonly sobre mount :ro (RISCO #1)"

  _kdb_dir=$(mktemp -d)
  _kdb_file="$_kdb_dir/knowledge.db"

  sqlite3 "$_kdb_file" >/dev/null <<SQL
PRAGMA journal_mode=WAL;
CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT);
INSERT INTO schema_meta(key, value) VALUES('schema_version', '8');
CREATE TABLE executions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project TEXT NOT NULL,
  feature TEXT NOT NULL,
  wave TEXT NOT NULL,
  execution_id TEXT NOT NULL,
  source_ts TEXT NOT NULL,
  source_id TEXT NOT NULL,
  status TEXT,
  ingested_at TEXT NOT NULL,
  UNIQUE(project, feature, wave, source_id)
);
INSERT INTO executions (project, feature, wave, execution_id, source_ts, source_id, status, ingested_at)
  VALUES ('smoke-project', 'smoke-feature', 'wave-1', 'exec-1', '2026-01-01T00:00:00Z', 'src-1', 'concluida', '2026-01-01T00:00:00Z');
INSERT INTO executions (project, feature, wave, execution_id, source_ts, source_id, status, ingested_at)
  VALUES ('smoke-project', 'smoke-feature', 'wave-2', 'exec-2', '2026-01-01T00:01:00Z', 'src-2', 'concluida', '2026-01-01T00:01:00Z');
SQL

  if [ ! -f "$_kdb_dir/knowledge.db-shm" ] || [ ! -f "$_kdb_dir/knowledge.db-wal" ]; then
    _fail "sidecars -shm/-wal ausentes apos setup (pre-condicao 5.1.1 nao satisfeita)"
    rm -rf -- "$_kdb_dir"
    return
  fi
  _pass "knowledge.db sintetico REAL criado (journal_mode=wal, sidecars presentes)"

  _host_count=$(sqlite3 "$_kdb_file" "SELECT count(*) FROM executions;")

  _smoke_run "$_kdb_dir"
  if ! _smoke_wait_ready; then
    _fail "painel containerizado nao respondeu 200 em /api/v1/health a tempo"
    docker logs "$_SMOKE_CONTAINER" >&2 2>&1 || :
    rm -rf -- "$_kdb_dir"
    return
  fi

  _body=$(_smoke_health)
  _db_reachable=$(printf '%s' "$_body" | jq -r '.data.dbReachable')
  _quick_check=$(printf '%s' "$_body" | jq -r '.data.quickCheck')
  _container_count=$(printf '%s' "$_body" | jq -r '.data.counts.executions')

  if [ "$_db_reachable" = "true" ] && [ "$_quick_check" = "true" ]; then
    _pass "readonly better-sqlite3 (sem immutable=1) abriu o WAL db sobre mount :ro SEM erro"
  else
    _fail "dbReachable/quickCheck != true -- RISCO #1 NAO confirmado" "body: $_body"
  fi

  if [ "$_container_count" = "$_host_count" ]; then
    _pass "paridade EXATA: host=$_host_count container=$_container_count"
  else
    _fail "divergencia de paridade" "host=$_host_count container=$_container_count"
  fi

  docker rm -f "$_SMOKE_CONTAINER" >/dev/null 2>&1 || :
  rm -rf -- "$_kdb_dir"
}

# ==== 2. scenario_concurrent_write_visible_without_restart (CHK017/Scenario 11) ====

scenario_concurrent_write_visible_without_restart() {
  _section "2. Escrita concorrente: visibilidade ao vivo SEM restart (CHK017/Scenario 11)"

  _kdb_dir=$(mktemp -d)
  _kdb_file="$_kdb_dir/knowledge.db"

  sqlite3 "$_kdb_file" >/dev/null <<SQL
PRAGMA journal_mode=WAL;
CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT);
INSERT INTO schema_meta(key, value) VALUES('schema_version', '8');
CREATE TABLE executions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project TEXT NOT NULL,
  feature TEXT NOT NULL,
  wave TEXT NOT NULL,
  execution_id TEXT NOT NULL,
  source_ts TEXT NOT NULL,
  source_id TEXT NOT NULL,
  status TEXT,
  ingested_at TEXT NOT NULL,
  UNIQUE(project, feature, wave, source_id)
);
INSERT INTO executions (project, feature, wave, execution_id, source_ts, source_id, status, ingested_at)
  VALUES ('smoke-project', 'smoke-feature', 'wave-1', 'exec-1', '2026-01-01T00:00:00Z', 'src-1', 'concluida', '2026-01-01T00:00:00Z');
SQL

  _smoke_run "$_kdb_dir"
  if ! _smoke_wait_ready; then
    _fail "painel containerizado nao respondeu 200 em /api/v1/health a tempo"
    docker logs "$_SMOKE_CONTAINER" >&2 2>&1 || :
    rm -rf -- "$_kdb_dir"
    return
  fi

  _before=$(_smoke_health | jq -r '.data.counts.executions')
  if [ "$_before" = "1" ]; then
    _pass "baseline pre-escrita: container ve 1 execucao"
  else
    _fail "baseline inesperado antes da escrita concorrente" "esperado=1 obtido=$_before"
  fi

  # Escrita do HOST enquanto o container ja esta 'running' -- SEM restart.
  sqlite3 "$_kdb_file" \
    "INSERT INTO executions (project, feature, wave, execution_id, source_ts, source_id, status, ingested_at) VALUES ('smoke-project', 'smoke-feature', 'wave-2', 'exec-2', '2026-01-01T00:01:00Z', 'src-2', 'concluida', '2026-01-01T00:01:00Z');"

  _after=$(_smoke_health | jq -r '.data.counts.executions')
  if [ "$_after" = "2" ]; then
    _pass "escrita concorrente do host VISIVEL na proxima requisicao, SEM restart (1 -> 2)"
  else
    _fail "escrita concorrente NAO visivel sem restart (comportamento observado != esperado)" \
      "antes=$_before depois=$_after (esperado depois=2)"
  fi

  # DELETE tambem deve ficar visivel de imediato (fecha o roundtrip).
  sqlite3 "$_kdb_file" "DELETE FROM executions WHERE source_id = 'src-2';"
  _after_delete=$(_smoke_health | jq -r '.data.counts.executions')
  if [ "$_after_delete" = "1" ]; then
    _pass "DELETE concorrente tambem visivel sem restart (2 -> 1)"
  else
    _fail "DELETE concorrente nao refletido" "obtido=$_after_delete (esperado=1)"
  fi

  docker rm -f "$_SMOKE_CONTAINER" >/dev/null 2>&1 || :
  rm -rf -- "$_kdb_dir"
}

# ==== 3. scenario_missing_index_graceful (Scenario 5 / US2 Acceptance 2) ====

scenario_missing_index_graceful() {
  _section "3. Indice ausente -> painel inicia normalmente, sem falha (Scenario 5)"

  _kdb_dir=$(mktemp -d)
  # Deliberadamente VAZIO -- nenhum knowledge.db criado (instalacao nova).

  _smoke_run "$_kdb_dir"
  if ! _smoke_wait_ready; then
    _fail "painel NAO iniciou com indice ausente (deveria iniciar normalmente)"
    docker logs "$_SMOKE_CONTAINER" >&2 2>&1 || :
    rm -rf -- "$_kdb_dir"
    return
  fi
  _pass "painel respondeu 200 em /api/v1/health mesmo com knowledge.db ausente"

  _body=$(_smoke_health)
  _db_reachable=$(printf '%s' "$_body" | jq -r '.data.dbReachable')
  _reason=$(printf '%s' "$_body" | jq -r '.meta.reason')

  if [ "$_db_reachable" = "false" ]; then
    _pass "dbReachable=false reportado de forma graciosa (sem crash/500)"
  else
    _fail "dbReachable inesperado com indice ausente" "obtido=$_db_reachable body=$_body"
  fi

  if [ "$_reason" = "db-missing" ]; then
    _pass "reason=db-missing (degradacao correta, paridade com modo nativo)"
  else
    _fail "reason inesperado" "esperado=db-missing obtido=$_reason"
  fi

  docker rm -f "$_SMOKE_CONTAINER" >/dev/null 2>&1 || :
  rm -rf -- "$_kdb_dir"
}

# ==== Execucao ====

scenario_data_parity_wal_readonly
scenario_concurrent_write_visible_without_restart
scenario_missing_index_graceful

_section "Resumo"
printf 'PASS=%d  FAIL=%d\n' "$PASS" "$FAIL" >&2

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
