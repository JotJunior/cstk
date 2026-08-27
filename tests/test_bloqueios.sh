#!/bin/sh
# test_bloqueios.sh — cobre plugins/cstk/skills/agente-00c-runtime/scripts/bloqueios.sh.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/bloqueios.sh"
RW="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/state-rw.sh"
DEC="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/state-decisions.sh"
SCHEMA_SCRIPT="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/state-db-schema.sh"

if ! command -v jq >/dev/null 2>&1; then
  printf '# test_bloqueios.sh: jq ausente — pulando suite\n'
  exit 0
fi

# ==== helpers ====

# _setup_with_decisao DIR -> init state + registra dec-001 valida
_setup_with_decisao() {
  capture "$RW" init --state-dir "$1" \
    --execucao-id "exec-block-test" \
    --projeto-alvo-path "/tmp/p" \
    --descricao "POC bloqueios test"
  [ "$_CAPTURED_EXIT" = 0 ] || return 1
  capture "$DEC" register --state-dir "$1" \
    --agente "clarify-answerer" --etapa "clarify" \
    --contexto "Pergunta sobre stack — nao decidida" \
    --opcoes '["Go","Node"]' --escolha "pause-humano" \
    --justificativa "Score 0 — nenhuma fonte suporta as opcoes" \
    --score 0
  [ "$_CAPTURED_EXIT" = 0 ] || return 1
}

_register_block_default() {
  capture "$SCRIPT" register --state-dir "$1" \
    --decisao-id "${2:-dec-001}" \
    --pergunta "Qual stack escolher para a feature, Go ou Node?" \
    --contexto-para-resposta "Briefing nao define; stack-sugerida vazia"
}

# ==== Scenarios ====

scenario_register_basico_gera_block_001() {
  _sd="$TMPDIR_TEST/state"
  _setup_with_decisao "$_sd" || { _error "fixture" ""; return 2; }
  _register_block_default "$_sd"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "register" "$_CAPTURED_EXIT; $_CAPTURED_STDERR"
    return 1
  fi
  assert_stdout_contains "block-001" || return 1
}

scenario_register_atualiza_status_para_aguardando_humano() {
  _sd="$TMPDIR_TEST/state"
  _setup_with_decisao "$_sd" || { _error "fixture" ""; return 2; }
  _register_block_default "$_sd"
  capture "$RW" get --state-dir "$_sd" --field '.execution.status'
  assert_stdout_contains "aguardando_humano" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.accumulated_metrics.human_blocks_total'
  assert_stdout_contains "1" || return 1
}

scenario_register_decisao_inexistente_falha_fk() {
  _sd="$TMPDIR_TEST/state"
  capture "$RW" init --state-dir "$_sd" --execucao-id "x" --projeto-alvo-path "/tmp/p" --descricao "x x x x x x x x x x"
  capture "$SCRIPT" register --state-dir "$_sd" \
    --decisao-id "dec-fantasma" \
    --pergunta "Pergunta longa o suficiente para passar (>=20 chars)" \
    --contexto-para-resposta "ctx"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "FK violation" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "decisao_id nao existe" || return 1
}

scenario_register_pergunta_curta_falha() {
  _sd="$TMPDIR_TEST/state"
  _setup_with_decisao "$_sd" || { _error "fixture" ""; return 2; }
  capture "$SCRIPT" register --state-dir "$_sd" \
    --decisao-id "dec-001" --pergunta "curta?" \
    --contexto-para-resposta "ctx"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "pergunta curta" "esperado 1"
    return 1
  fi
  assert_stderr_contains "pergunta muito curta" || return 1
}

scenario_register_opcoes_invalidas_falha() {
  _sd="$TMPDIR_TEST/state"
  _setup_with_decisao "$_sd" || { _error "fixture" ""; return 2; }
  capture "$SCRIPT" register --state-dir "$_sd" \
    --decisao-id "dec-001" \
    --pergunta "Pergunta longa o suficiente para passar (>=20 chars)" \
    --contexto-para-resposta "ctx" \
    --opcoes-recomendadas '"not-array"'
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "opcoes invalidas" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_respond_marca_respondido_e_volta_status() {
  _sd="$TMPDIR_TEST/state"
  _setup_with_decisao "$_sd" || { _error "fixture" ""; return 2; }
  _register_block_default "$_sd"
  capture "$SCRIPT" respond --state-dir "$_sd" --block-id "block-001" --resposta "Go"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "respond" "$_CAPTURED_EXIT; $_CAPTURED_STDERR"
    return 1
  fi
  capture "$RW" get --state-dir "$_sd" --field '.human_blocks[0].status'
  assert_stdout_contains "respondido" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.human_blocks[0].human_answer'
  assert_stdout_contains "Go" || return 1
  # Sem mais bloqueios pendentes -> status volta para em_andamento
  capture "$RW" get --state-dir "$_sd" --field '.execution.status'
  assert_stdout_contains "em_andamento" || return 1
}

scenario_respond_inexistente_falha() {
  _sd="$TMPDIR_TEST/state"
  _setup_with_decisao "$_sd" || { _error "fixture" ""; return 2; }
  capture "$SCRIPT" respond --state-dir "$_sd" --block-id "block-fantasma" --resposta "x"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "respond inexistente" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  # Mensagem legada permanece byte-a-byte identica (SC-006, openspec-hygiene).
  assert_stderr_contains "nao encontrado" || return 1
  # Envelope diagnostico aditivo (openspec-hygiene FR-012/FR-015).
  assert_stderr_contains "DIAG|error|bloqueio-not-found|" || return 1
}

scenario_respond_ja_respondido_falha() {
  _sd="$TMPDIR_TEST/state"
  _setup_with_decisao "$_sd" || { _error "fixture" ""; return 2; }
  _register_block_default "$_sd"
  capture "$SCRIPT" respond --state-dir "$_sd" --block-id "block-001" --resposta "Go"
  capture "$SCRIPT" respond --state-dir "$_sd" --block-id "block-001" --resposta "Node"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "respond duplicado" "esperado 1"
    return 1
  fi
  assert_stderr_contains "nao esta em status aguardando" || return 1
}

scenario_status_so_volta_quando_todos_pendentes_resolvidos() {
  _sd="$TMPDIR_TEST/state"
  _setup_with_decisao "$_sd" || { _error "fixture" ""; return 2; }
  # Cria 2 decisoes + 2 bloqueios
  capture "$DEC" register --state-dir "$_sd" \
    --agente "clarify-answerer" --etapa "clarify" \
    --contexto "Outra pergunta sem resposta clara" \
    --opcoes '["X","Y"]' --escolha "pause-humano" \
    --justificativa "Score 0 outra vez aqui" --score 0
  _register_block_default "$_sd" "dec-001"
  _register_block_default "$_sd" "dec-002"
  # Responde apenas o primeiro
  capture "$SCRIPT" respond --state-dir "$_sd" --block-id "block-001" --resposta "Go"
  capture "$RW" get --state-dir "$_sd" --field '.execution.status'
  # Ainda 1 pendente -> mantem aguardando_humano
  assert_stdout_contains "aguardando_humano" || return 1
  # Responde o segundo
  capture "$SCRIPT" respond --state-dir "$_sd" --block-id "block-002" --resposta "X"
  capture "$RW" get --state-dir "$_sd" --field '.execution.status'
  assert_stdout_contains "em_andamento" || return 1
}

scenario_count_e_count_pending() {
  _sd="$TMPDIR_TEST/state"
  _setup_with_decisao "$_sd" || { _error "fixture" ""; return 2; }
  capture "$DEC" register --state-dir "$_sd" \
    --agente "x" --etapa "clarify" \
    --contexto "outra decisao para FK" \
    --opcoes '["A"]' --escolha "A" \
    --justificativa "justificativa de tamanho ok aqui" --score 1
  _register_block_default "$_sd" "dec-001"
  _register_block_default "$_sd" "dec-002"
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "2" || return 1
  capture "$SCRIPT" count --state-dir "$_sd" --pending-only
  assert_stdout_contains "2" || return 1
  capture "$SCRIPT" respond --state-dir "$_sd" --block-id "block-001" --resposta "x"
  capture "$SCRIPT" count --state-dir "$_sd" --pending-only
  assert_stdout_contains "1" || return 1
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "2" || return 1
}

scenario_list_imprime_tsv_e_filtra_por_status() {
  _sd="$TMPDIR_TEST/state"
  _setup_with_decisao "$_sd" || { _error "fixture" ""; return 2; }
  _register_block_default "$_sd"
  capture "$SCRIPT" list --state-dir "$_sd"
  assert_stdout_contains "block-001	dec-001	aguardando" || return 1
  capture "$SCRIPT" respond --state-dir "$_sd" --block-id "block-001" --resposta "Go"
  capture "$SCRIPT" list --state-dir "$_sd" --status aguardando
  if [ -n "$_CAPTURED_STDOUT" ]; then
    _fail "list filtrada por aguardando" "esperado vazio (todos respondidos)"
    return 1
  fi
  capture "$SCRIPT" list --state-dir "$_sd" --status respondido
  assert_stdout_contains "block-001" || return 1
}

scenario_get_imprime_json_do_bloqueio() {
  _sd="$TMPDIR_TEST/state"
  _setup_with_decisao "$_sd" || { _error "fixture" ""; return 2; }
  _register_block_default "$_sd"
  capture "$SCRIPT" get --state-dir "$_sd" --block-id "block-001"
  assert_stdout_contains '"id": "block-001"' || return 1
  assert_stdout_contains '"status": "aguardando"' || return 1
  # Writer emite chaves EN (schema-en-migration §3.6)
  assert_stdout_contains '"decision_id": "dec-001"' || return 1
  assert_stdout_contains '"question":' || return 1
}

scenario_get_inexistente_falha() {
  _sd="$TMPDIR_TEST/state"
  _setup_with_decisao "$_sd" || { _error "fixture" ""; return 2; }
  capture "$SCRIPT" get --state-dir "$_sd" --block-id "block-fantasma"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "get inexistente" "esperado 1"
    return 1
  fi
}

scenario_next_id_sequencial() {
  _sd="$TMPDIR_TEST/state"
  _setup_with_decisao "$_sd" || { _error "fixture" ""; return 2; }
  capture "$SCRIPT" next-id --state-dir "$_sd"
  assert_stdout_contains "block-001" || return 1
  _register_block_default "$_sd"
  capture "$SCRIPT" next-id --state-dir "$_sd"
  assert_stdout_contains "block-002" || return 1
}

# _write_legacy_pt_state DIR — escreve um state.json com chaves pt-BR LEGADAS
# DIRETAMENTE no disco (sem passar por state-rw.sh, que canonicalizaria p/ EN).
# Prova que os readers do bloqueios.sh ainda leem via fallback (.en // .pt).
_write_legacy_pt_state() {
  mkdir -p -- "$1"
  cat > "$1/state.json" <<'PT'
{
  "schema_version": 6,
  "execucao": { "id": "exec-legacy", "status": "aguardando_humano" },
  "ondas": [ { "id": "wave-001" } ],
  "decisoes": [ { "id": "dec-001" } ],
  "metricas_acumuladas": { "bloqueios_humanos_total": 1 },
  "bloqueios_humanos": [
    {
      "id": "block-001",
      "decisao_id": "dec-001",
      "pergunta": "Pergunta legada longa o suficiente (>=20 chars)?",
      "contexto_para_resposta": "ctx legado",
      "opcoes_recomendadas": null,
      "status": "aguardando",
      "resposta_humana": null,
      "respondido_em": null,
      "disparado_em": "2024-01-01T00:00:00Z"
    }
  ]
}
PT
}

# Back-compat (schema-en-migration §6): readers leem state pt-BR vivo via fallback.
scenario_backcompat_readers_leem_state_pt_legado() {
  _sd="$TMPDIR_TEST/state"
  _write_legacy_pt_state "$_sd"

  # count le .bloqueios_humanos via fallback
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "1" || return 1
  capture "$SCRIPT" count --state-dir "$_sd" --pending-only
  assert_stdout_contains "1" || return 1

  # list le container + campos decisao_id/disparado_em/pergunta via fallback
  capture "$SCRIPT" list --state-dir "$_sd"
  assert_stdout_contains "block-001	dec-001	aguardando" || return 1

  # get le o bloqueio via fallback
  capture "$SCRIPT" get --state-dir "$_sd" --block-id "block-001"
  assert_stdout_contains '"id": "block-001"' || return 1

  # next-id le ids existentes via fallback -> proximo e block-002
  capture "$SCRIPT" next-id --state-dir "$_sd"
  assert_stdout_contains "block-002" || return 1
}

# Fluxo de runtime real (schema-en-migration §1/§4): o command-pai chama
# `state-rw.sh migrate` no inicio de CADA onda, ANTES de spawnar o
# orquestrador, garantindo EN-on-disk antes de qualquer direct-writer rodar.
# Apos migrate, register/respond (writers rename-only) operam sem doc-split.
scenario_backcompat_migrate_entao_register_respond() {
  _sd="$TMPDIR_TEST/state"
  _write_legacy_pt_state "$_sd"

  # Passo do command-pai: canonicaliza pt-BR -> EN no lugar.
  capture "$RW" migrate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "migrate" "$_CAPTURED_STDERR"; return 1; }

  # Disco agora e EN: container e campos internos canonicalizados.
  capture jq -e '
    (.bloqueios_humanos == null) and ((.human_blocks | type) == "array")
    and (.human_blocks[0].decision_id == "dec-001")
    and (.decisoes == null) and ((.decisions | type) == "array")
  ' "$_sd/state.json"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "migrate nao produziu EN" "doc nao canonico"; return 1; }

  # register (writer rename-only) sobre EN: anexa block-002 sem split.
  capture "$SCRIPT" register --state-dir "$_sd" \
    --decisao-id "dec-001" \
    --pergunta "Outra pergunta longa o suficiente para passar?" \
    --contexto-para-resposta "ctx novo"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "register pos-migrate" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "block-002" || return 1
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "2" || return 1
  capture jq -e '.bloqueios_humanos == null' "$_sd/state.json"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "register criou doc-split" "chave pt-BR ressurgiu"; return 1; }

  # respond (writer rename-only) sobre EN: marca respondido em chaves EN.
  capture "$SCRIPT" respond --state-dir "$_sd" --block-id "block-001" --resposta "Sim"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "respond pos-migrate" "$_CAPTURED_STDERR"; return 1; }
  capture "$RW" get --state-dir "$_sd" --field '.human_blocks[0].human_answer'
  assert_stdout_contains "Sim" || return 1
}

# ==== Backend SQLite (feature state-db-foundation, FASE 3 task 3.5) ====
#
# Ref: docs/specs/state-db-foundation/tasks.md FASE 3, task 3.5
#      docs/specs/state-db-foundation/contracts/primitives.md §C1 (paridade)
#      §C2 (selecao de backend) §C3 (FK) §C4 (transacao) §C6 (concorrencia)
#      §C8 (escape)
#
# Mesmo padrao de tests/test_state-decisions.sh (task 3.4): aplica o DDL via
# state-db-schema.sh e semeia uma execution + decision minimas via sqlite3
# diretamente (init nunca cria state.db — isso e a migracao, FASE 6, ainda
# nao implementada).

if ! command -v sqlite3 >/dev/null 2>&1; then
  printf '# test_bloqueios.sh: sqlite3 ausente — pulando cenarios de backend SQLite\n'
else

# _seed_sqlite_backend DIR -> cria state.db com execution (id=exec-1) e
# decision (id=dec-001) minimas, prontas para bloqueios.sh register.
_seed_sqlite_backend() {
  _ssb_dir=$1
  mkdir -p "$_ssb_dir"
  "$SCHEMA_SCRIPT" create --db "$_ssb_dir/state.db" >/dev/null 2>&1 \
    || { _fail "seed: schema create falhou" ""; return 1; }
  sqlite3 "$_ssb_dir/state.db" "
    PRAGMA foreign_keys=ON;
    INSERT INTO execution (id,schema_version,target_project_path,target_project_description,status,started_at,current_stage,next_instruction,external_urls_whitelist,circular_movement_history,initial_key_aspects,atomic_commit_enabled)
    VALUES ('exec-1','1.0.0','/tmp/p','desc de teste com detalhe','em_andamento','2026-07-30T00:00:00Z','execute-task','faca algo','[]','[]','[]',0);
    INSERT INTO decision (id,execution_id,timestamp,agent,stage,context,options_considered,choice,rationale)
    VALUES ('dec-001','exec-1','2026-07-30T00:00:00Z','x','clarify','contexto de teste com detalhe suficiente','[\"a\"]','a','justificativa de teste com detalhe suficiente');
  " || { _fail "seed: insert execution/decision falhou" ""; return 1; }
}

_register_sqlite_default() {
  capture "$SCRIPT" register --state-dir "$1" \
    --decisao-id "dec-001" \
    --pergunta "Qual stack escolher para a feature, Go ou Node?" \
    --contexto-para-resposta "Briefing nao define; stack-sugerida vazia"
}

scenario_sqlite_register_gera_block_001() {
  _sd="$TMPDIR_TEST/sqlite-register-001"
  _seed_sqlite_backend "$_sd" || return 1
  _register_sqlite_default "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sqlite register" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "block-001" || return 1
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "1" || return 1
}

scenario_sqlite_register_atualiza_status_para_aguardando_humano() {
  # C4: register grava o bloqueio E muda .execution.status na MESMA
  # transacao.
  _sd="$TMPDIR_TEST/sqlite-register-status"
  _seed_sqlite_backend "$_sd" || return 1
  _register_sqlite_default "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sqlite register" "$_CAPTURED_STDERR"; return 1; }
  capture "$RW" get --state-dir "$_sd" --field '.execution.status'
  assert_stdout_contains "aguardando_humano" || return 1
  # accumulated_metrics.human_blocks_total e DERIVADO por agregacao SQL sob
  # o backend sqlite (paridade de state-ondas.sh task 3.3.1) — nao um
  # contador mantido em sincronia.
  capture "$RW" get --state-dir "$_sd" --field '.accumulated_metrics.human_blocks_total'
  assert_stdout_contains "1" || return 1
}

scenario_sqlite_register_sequencial_gera_block_002() {
  _sd="$TMPDIR_TEST/sqlite-register-seq"
  _seed_sqlite_backend "$_sd" || return 1
  _register_sqlite_default "$_sd"
  _register_sqlite_default "$_sd"
  assert_stdout_contains "block-002" || return 1
  capture "$SCRIPT" next-id --state-dir "$_sd"
  assert_stdout_contains "block-003" || return 1
}

# C3: decisao_id inexistente dispara a FK REAL do schema
# (human_block.decision_id REFERENCES decision(id)) — a transacao inteira
# reverte (nenhum bloqueio persistido, execution.status intocado) e o erro
# e mapeado para a mesma mensagem/exit 1 do path JSON (US1 AS-4).
scenario_sqlite_register_decisao_inexistente_falha_fk() {
  _sd="$TMPDIR_TEST/sqlite-register-fk"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" register --state-dir "$_sd" \
    --decisao-id "dec-fantasma" \
    --pergunta "Pergunta longa o suficiente para passar (>=20 chars)" \
    --contexto-para-resposta "ctx"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "sqlite FK violation" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "decisao_id nao existe" || return 1
  # Nada persistido — a transacao reverteu por inteiro (C4).
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "0" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.execution.status'
  assert_stdout_contains "em_andamento" || return 1
}

scenario_sqlite_list_imprime_tsv() {
  _sd="$TMPDIR_TEST/sqlite-list-tsv"
  _seed_sqlite_backend "$_sd" || return 1
  _register_sqlite_default "$_sd"
  capture "$SCRIPT" list --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sqlite list" "$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "block-001	dec-001	aguardando	" || return 1
  assert_stdout_contains "Qual stack escolher" || return 1
}

scenario_sqlite_list_filtra_por_status() {
  _sd="$TMPDIR_TEST/sqlite-list-status"
  _seed_sqlite_backend "$_sd" || return 1
  _register_sqlite_default "$_sd"
  capture "$SCRIPT" respond --state-dir "$_sd" --block-id "block-001" --resposta "Go"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sqlite respond" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" list --state-dir "$_sd" --status "respondido"
  assert_stdout_contains "block-001	" || return 1
  capture "$SCRIPT" list --state-dir "$_sd" --status "aguardando"
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "sqlite list filtrado" "esperava vazio, obtido '$_CAPTURED_STDOUT'"; return 1; }
}

scenario_sqlite_get_imprime_json() {
  _sd="$TMPDIR_TEST/sqlite-get"
  _seed_sqlite_backend "$_sd" || return 1
  _register_sqlite_default "$_sd"
  capture "$SCRIPT" get --state-dir "$_sd" --block-id "block-001"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sqlite get" "$_CAPTURED_STDERR"; return 1; }
  capture jq -e '.id == "block-001" and .decision_id == "dec-001" and .status == "aguardando" and .recommended_options == null' <<EOF
$_CAPTURED_STDOUT
EOF
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sqlite get json" "campos incorretos: $_CAPTURED_STDOUT"; return 1; }
}

scenario_sqlite_get_inexistente_falha() {
  _sd="$TMPDIR_TEST/sqlite-get-ausente"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" get --state-dir "$_sd" --block-id "block-999"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "sqlite get ausente" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
}

# C4: respond fecha o bloqueio E, se nao restar nenhum outro aguardando,
# promove execution.status de volta a "em_andamento" — mesma transacao.
scenario_sqlite_respond_marca_respondido_e_volta_status() {
  _sd="$TMPDIR_TEST/sqlite-respond"
  _seed_sqlite_backend "$_sd" || return 1
  _register_sqlite_default "$_sd"
  capture "$SCRIPT" respond --state-dir "$_sd" --block-id "block-001" --resposta "Vamos de Go"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sqlite respond" "$_CAPTURED_STDERR"; return 1; }
  capture "$RW" get --state-dir "$_sd" --field '.execution.status'
  assert_stdout_contains "em_andamento" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.human_blocks[0].human_answer'
  assert_stdout_contains "Vamos de Go" || return 1
  capture "$SCRIPT" count --state-dir "$_sd" --pending-only
  assert_stdout_contains "0" || return 1
}

scenario_sqlite_respond_status_so_volta_quando_todos_resolvidos() {
  _sd="$TMPDIR_TEST/sqlite-respond-parcial"
  _seed_sqlite_backend "$_sd" || return 1
  # segunda decisao + segundo bloqueio pendente
  capture "$DEC" register --state-dir "$_sd" \
    --agente "x" --etapa "clarify" \
    --contexto "Outra decisao de teste com 20+ chars aqui" \
    --opcoes '["a","b"]' --escolha "a" \
    --justificativa "Justificativa generica com 20+ chars aqui"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sqlite dec-002" "$_CAPTURED_STDERR"; return 1; }
  _register_sqlite_default "$_sd"
  capture "$SCRIPT" register --state-dir "$_sd" \
    --decisao-id "dec-002" \
    --pergunta "Segunda pergunta longa o suficiente para passar?" \
    --contexto-para-resposta "ctx2"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sqlite block-002" "$_CAPTURED_STDERR"; return 1; }

  capture "$SCRIPT" respond --state-dir "$_sd" --block-id "block-001" --resposta "resp1"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sqlite respond 1" "$_CAPTURED_STDERR"; return 1; }
  capture "$RW" get --state-dir "$_sd" --field '.execution.status'
  assert_stdout_contains "aguardando_humano" || return 1

  capture "$SCRIPT" respond --state-dir "$_sd" --block-id "block-002" --resposta "resp2"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sqlite respond 2" "$_CAPTURED_STDERR"; return 1; }
  capture "$RW" get --state-dir "$_sd" --field '.execution.status'
  assert_stdout_contains "em_andamento" || return 1
}

scenario_sqlite_respond_ja_respondido_falha() {
  _sd="$TMPDIR_TEST/sqlite-respond-duplo"
  _seed_sqlite_backend "$_sd" || return 1
  _register_sqlite_default "$_sd"
  capture "$SCRIPT" respond --state-dir "$_sd" --block-id "block-001" --resposta "primeira"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sqlite respond 1" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" respond --state-dir "$_sd" --block-id "block-001" --resposta "segunda"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "sqlite respond duplo" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "nao esta em status aguardando" || return 1
}

scenario_sqlite_respond_inexistente_falha() {
  _sd="$TMPDIR_TEST/sqlite-respond-ausente"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" respond --state-dir "$_sd" --block-id "block-999" --resposta "x"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "sqlite respond ausente" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "bloqueio nao encontrado" || return 1
}

# C8: payload hostil (apostrofo + tentativa de injecao) persistido literal,
# tabela human_block sobrevive, integrity_check continua ok.
scenario_sqlite_payload_hostil_preservado_literal_tabela_sobrevive() {
  _sd="$TMPDIR_TEST/sqlite-hostil"
  _seed_sqlite_backend "$_sd" || return 1
  _hostil="'; DROP TABLE human_block; -- e apostrofo simples it's here"
  capture "$SCRIPT" register --state-dir "$_sd" \
    --decisao-id "dec-001" \
    --pergunta "$_hostil (pergunta hostil, 20+ chars)" \
    --contexto-para-resposta "$_hostil"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sqlite payload hostil" "$_CAPTURED_STDERR"; return 1; }
  capture "$RW" get --state-dir "$_sd" --field '.human_blocks[-1].question'
  assert_stdout_contains "DROP TABLE human_block" || return 1
  capture "$RW" sha256-verify --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "integrity apos payload hostil" "$_CAPTURED_STDERR"; return 1; }
}

# Teste de concorrencia (task 3.5, paridade com 3.4.3): N registers
# simultaneos, cada um referenciando uma decisao DISTINTA (FK 1:1 por
# design do schema nao impede reuso do MESMO decision_id por varios
# human_blocks — mas exercitamos IDs unicos por worker para simular o caso
# real de varios bloqueios concorrentes na mesma execucao), nao perde
# nenhum bloqueio e nao colide em block-NNN.
scenario_sqlite_register_concorrente_sem_colisao() {
  _sd="$TMPDIR_TEST/sqlite-concorrencia"
  _seed_sqlite_backend "$_sd" || return 1
  _n=15
  _i=1
  while [ "$_i" -le "$_n" ]; do
    ( "$SCRIPT" register --state-dir "$_sd" \
        --decisao-id "dec-001" \
        --pergunta "Pergunta concorrente numero $_i com 20+ chars" \
        --contexto-para-resposta "ctx concorrente $_i" \
        > "$TMPDIR_TEST/sqlite-concorrencia-out-$_i.txt" \
        2> "$TMPDIR_TEST/sqlite-concorrencia-err-$_i.txt" ) &
    _i=$((_i + 1))
  done
  wait

  _i=1
  while [ "$_i" -le "$_n" ]; do
    if [ -s "$TMPDIR_TEST/sqlite-concorrencia-err-$_i.txt" ]; then
      _fail "worker $_i emitiu stderr" "$(cat "$TMPDIR_TEST/sqlite-concorrencia-err-$_i.txt")"
      return 1
    fi
    _i=$((_i + 1))
  done

  _unique=$(cat "$TMPDIR_TEST"/sqlite-concorrencia-out-*.txt | sort -u | wc -l | tr -d ' ')
  [ "$_unique" = "$_n" ] || { _fail "ids unicos" "esperado $_n, obtido $_unique"; return 1; }

  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "$_n" || return 1
}

# Paridade cross-backend (C1): mesmos inputs, mesmo formato de stdout
# (block-001) para o primeiro register em cada backend.
scenario_sqlite_paridade_register_primeiro_id_json() {
  _sd_json="$TMPDIR_TEST/paridade-bloqueios-json"
  _setup_with_decisao "$_sd_json" || { _error "fixture" ""; return 2; }
  _register_block_default "$_sd_json"
  _json_id="$_CAPTURED_STDOUT"

  _sd_db="$TMPDIR_TEST/paridade-bloqueios-sqlite"
  _seed_sqlite_backend "$_sd_db" || return 1
  _register_sqlite_default "$_sd_db"
  _db_id="$_CAPTURED_STDOUT"

  [ "$_json_id" = "$_db_id" ] || { _fail "paridade register id" "json='$_json_id' sqlite='$_db_id'"; return 1; }
}

scenario_sqlite_register_state_db_ausente_falha() {
  _sd="$TMPDIR_TEST/sqlite-ausente"
  mkdir -p "$_sd"
  # sem state.db -> backend json (C2); sem state.json tambem -> falha 1
  _register_sqlite_default "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "sqlite state ausente" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

# Task 4.1.1/4.2.2 (FASE 4): branch de selecao de backend explicito por C2 —
# um state.json coexistente e export/legado, NUNCA consultado como fonte.
# Prova positiva: 1 bloqueio registrado no state.db, state.json divergente
# com 3 bloqueios falsos — count --pending-only deve refletir sempre o
# state.db (1).
scenario_c2_state_json_coexistente_ignorado_quando_state_db_presente() {
  _sd="$TMPDIR_TEST/c2-coexist-bloqueios"
  _seed_sqlite_backend "$_sd" || return 1
  _register_sqlite_default "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "c2: register sqlite" "$_CAPTURED_STDERR"; return 1; }

  # state.json divergente no MESMO diretorio (3 bloqueios pendentes falsos).
  printf '{"human_blocks":[{"status":"aguardando"},{"status":"aguardando"},{"status":"aguardando"}]}\n' > "$_sd/state.json"

  capture "$SCRIPT" count --state-dir "$_sd" --pending-only
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "c2 count exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "1" \
    || { _fail "c2: count deveria refletir state.db (1), nao o state.json coexistente (3)" "obtido $_CAPTURED_STDOUT"; return 1; }
  case "$_CAPTURED_STDOUT" in
    3*) _fail "c2: count leu o state.json coexistente" "obtido $_CAPTURED_STDOUT"; return 1 ;;
  esac

  # state.json coexistente permanece intocado.
  case "$(cat "$_sd/state.json")" in
    *aguardando*) : ;;
    *) _fail "c2: state.json coexistente foi modificado" "obtido: $(cat "$_sd/state.json")"; return 1 ;;
  esac
}

fi # sqlite3 disponivel

# Issues #122/#123: jq nativo do Windows emite CRLF; o antigo padrao
# `jq | { read -r _max; ... }` preservava o \r residual e quebrava a
# aritmetica do next-id ('invalid arithmetic operator'). Simula com um stub
# de jq que reemite a saida do jq real com terminador CRLF.
scenario_next_id_tolera_jq_com_saida_crlf() {
  _sd="$TMPDIR_TEST/state-crlf"
  mkdir -p -- "$_sd"
  printf '%s\n' '{"execution":{"id":"exec-1"},"human_blocks":[{"id":"block-002","status":"aguardando"}]}' \
    > "$_sd/state.json"
  _bin="$TMPDIR_TEST/crlf-bin"
  mkdir -p -- "$_bin"
  _realjq=$(command -v jq) || { _error "jq ausente" ""; return 2; }
  printf '#!/bin/sh\n%s "$@" | while IFS= read -r _l; do printf "%%s\\r\\n" "$_l"; done\n' \
    "$_realjq" > "$_bin/jq"
  chmod +x "$_bin/jq"
  capture env PATH="$_bin:$PATH" "$SCRIPT" next-id --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "next-id com jq CRLF" "exit $_CAPTURED_EXIT; $_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "block-003" || return 1
}

# ==== structural-decision-human-gate (FASE 2, task 2.4.5): --chave-assunto ====
#
# Ref: docs/specs/structural-decision-human-gate/data-model.md §Enum de
#      prefixo de subject_key; contracts/cli-structural-class.md §bloqueios.sh
#      register/list (extensao)

scenario_sdhg_register_com_chave_assunto_briefing_item() {
  _sd="$TMPDIR_TEST/sdhg-chave-briefing"
  _setup_with_decisao "$_sd" || { _error "fixture" ""; return 2; }
  capture "$SCRIPT" register --state-dir "$_sd" --decisao-id dec-001 \
    --pergunta "Qual stack escolher para a feature, Go ou Node?" \
    --contexto-para-resposta "Briefing nao define; stack-sugerida vazia" \
    --chave-assunto "briefing-item:linguagem-e-runtime-do-backend-abc123"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "register com chave-assunto" "$_CAPTURED_STDERR"; return 1; }
  capture "$RW" get --state-dir "$_sd" --field '.human_blocks[0].subject_key'
  [ "$_CAPTURED_STDOUT" = "briefing-item:linguagem-e-runtime-do-backend-abc123" ] \
    || { _fail "subject_key persistido" "obtido $_CAPTURED_STDOUT"; return 1; }
}

scenario_sdhg_register_sem_chave_assunto_fica_null() {
  _sd="$TMPDIR_TEST/sdhg-chave-null"
  _setup_with_decisao "$_sd" || { _error "fixture" ""; return 2; }
  _register_block_default "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "register sem chave-assunto" "$_CAPTURED_STDERR"; return 1; }
  capture "$RW" get --state-dir "$_sd" --field '.human_blocks[0].subject_key'
  [ "$_CAPTURED_STDOUT" = "null" ] || { _fail "subject_key deveria ser null" "obtido $_CAPTURED_STDOUT"; return 1; }
}

scenario_sdhg_register_chave_assunto_prefixo_invalido_falha() {
  _sd="$TMPDIR_TEST/sdhg-chave-prefixo-invalido"
  _setup_with_decisao "$_sd" || { _error "fixture" ""; return 2; }
  capture "$SCRIPT" register --state-dir "$_sd" --decisao-id dec-001 \
    --pergunta "Qual stack escolher para a feature, Go ou Node?" \
    --contexto-para-resposta "Briefing nao define; stack-sugerida vazia" \
    --chave-assunto "milestone:retro-25-ondas"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "prefixo invalido" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "0" || return 1
}

scenario_sdhg_register_chave_assunto_sufixo_vazio_falha() {
  _sd="$TMPDIR_TEST/sdhg-chave-sufixo-vazio"
  _setup_with_decisao "$_sd" || { _error "fixture" ""; return 2; }
  capture "$SCRIPT" register --state-dir "$_sd" --decisao-id dec-001 \
    --pergunta "Qual stack escolher para a feature, Go ou Node?" \
    --contexto-para-resposta "Briefing nao define; stack-sugerida vazia" \
    --chave-assunto "axis:"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "sufixo vazio" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_sdhg_list_chave_assunto_filtra_por_igualdade_exata() {
  _sd="$TMPDIR_TEST/sdhg-list-filtro"
  _setup_with_decisao "$_sd" || { _error "fixture" ""; return 2; }
  capture "$SCRIPT" register --state-dir "$_sd" --decisao-id dec-001 \
    --pergunta "Qual linguagem/runtime devemos usar no backend?" \
    --contexto-para-resposta "Ver plan.md" \
    --chave-assunto "axis:linguagem-runtime"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "seed bloqueio 1" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" register --state-dir "$_sd" --decisao-id dec-001 \
    --pergunta "Qual banco de dados devemos usar?" \
    --contexto-para-resposta "Ver plan.md" \
    --chave-assunto "axis:persistencia"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "seed bloqueio 2" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" list --state-dir "$_sd" --chave-assunto "axis:linguagem-runtime"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "list --chave-assunto" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "block-001" || return 1
  assert_stdout_not_contains "block-002" || return 1
  # TSV nao ganha coluna nova (5 campos: id/decision_id/status/triggered_at/pergunta)
  _ncols=$(printf '%s' "$_CAPTURED_STDOUT" | head -1 | awk -F'\t' '{print NF}')
  [ "$_ncols" = "5" ] || { _fail "TSV mudou de colunas" "obtido $_ncols campos"; return 1; }
}

scenario_sdhg_dedup_fr008_vazio_significa_nao_decidido() {
  _sd="$TMPDIR_TEST/sdhg-dedup"
  _setup_with_decisao "$_sd" || { _error "fixture" ""; return 2; }
  capture "$SCRIPT" register --state-dir "$_sd" --decisao-id dec-001 \
    --pergunta "Qual linguagem/runtime devemos usar no backend?" \
    --contexto-para-resposta "Ver plan.md" \
    --chave-assunto "axis:linguagem-runtime"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "seed bloqueio" "$_CAPTURED_STDERR"; return 1; }
  # Ainda aguardando -> dedup (status=respondido) nao encontra nada.
  capture "$SCRIPT" list --state-dir "$_sd" --status respondido --chave-assunto "axis:linguagem-runtime"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "dedup query" "$_CAPTURED_STDERR"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "deveria estar vazio (ainda nao decidido)" "obtido '$_CAPTURED_STDOUT'"; return 1; }
  capture "$SCRIPT" respond --state-dir "$_sd" --block-id block-001 --resposta "Go 1.22"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "respond" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" list --state-dir "$_sd" --status respondido --chave-assunto "axis:linguagem-runtime"
  assert_stdout_contains "block-001" || return 1
}

scenario_sdhg_bloqueios_legados_subject_key_null_nunca_casa() {
  # INV-K1: bloqueios anteriores a esta feature tem subject_key NULL e nunca
  # casam com chave alguma, nem para dedup nem para consentimento.
  _sd="$TMPDIR_TEST/sdhg-legado"
  _setup_with_decisao "$_sd" || { _error "fixture" ""; return 2; }
  _register_block_default "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "register legado (sem chave)" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" respond --state-dir "$_sd" --block-id block-001 --resposta "Go 1.22"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "respond" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" list --state-dir "$_sd" --status respondido --chave-assunto "axis:linguagem-runtime"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "list filtro legado" "$_CAPTURED_STDERR"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "bloqueio legado nao deveria casar com chave alguma" "obtido '$_CAPTURED_STDOUT'"; return 1; }
}

if command -v sqlite3 >/dev/null 2>&1; then

scenario_sdhg_sqlite_register_com_chave_assunto_persiste_coluna() {
  _sd="$TMPDIR_TEST/sdhg-sqlite-chave"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" register --state-dir "$_sd" --decisao-id dec-001 \
    --pergunta "Qual linguagem/runtime devemos usar no backend?" \
    --contexto-para-resposta "Ver plan.md" \
    --chave-assunto "axis:linguagem-runtime"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sqlite register com chave" "$_CAPTURED_STDERR"; return 1; }
  _val=$(sqlite3 "$_sd/state.db" "SELECT subject_key FROM human_block WHERE id='block-001';")
  [ "$_val" = "axis:linguagem-runtime" ] || { _fail "coluna subject_key" "obtido '$_val'"; return 1; }
}

scenario_sdhg_sqlite_register_chave_assunto_prefixo_invalido_falha() {
  _sd="$TMPDIR_TEST/sdhg-sqlite-chave-invalida"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" register --state-dir "$_sd" --decisao-id dec-001 \
    --pergunta "Qual linguagem/runtime devemos usar no backend?" \
    --contexto-para-resposta "Ver plan.md" \
    --chave-assunto "nao-e-um-prefixo-valido"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "sqlite prefixo invalido" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "0" || return 1
}

scenario_sdhg_sqlite_list_chave_assunto_filtra() {
  _sd="$TMPDIR_TEST/sdhg-sqlite-list-filtro"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" register --state-dir "$_sd" --decisao-id dec-001 \
    --pergunta "Qual linguagem/runtime devemos usar no backend?" \
    --contexto-para-resposta "Ver plan.md" \
    --chave-assunto "axis:linguagem-runtime"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sqlite seed bloqueio" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" list --state-dir "$_sd" --chave-assunto "axis:persistencia"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sqlite list filtro (sem match)" "$_CAPTURED_STDERR"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "nao deveria casar com axis:persistencia" "obtido '$_CAPTURED_STDOUT'"; return 1; }
  capture "$SCRIPT" list --state-dir "$_sd" --chave-assunto "axis:linguagem-runtime"
  assert_stdout_contains "block-001" || return 1
}

# Banco pre-feature (sem `ensure` aplicado): list --chave-assunto NUNCA
# invoca `ensure` (INV-E3, caminho de leitura) — resolve via table_info e
# trata coluna ausente como "nenhuma linha casa", sem erro "no such column".
scenario_sdhg_sqlite_list_chave_assunto_banco_legado_sem_coluna_nao_falha() {
  _sd="$TMPDIR_TEST/sdhg-sqlite-legado-sem-coluna"
  mkdir -p "$_sd"
  "$SCHEMA_SCRIPT" create --db "$_sd/state.db" >/dev/null 2>&1 \
    || { _fail "seed: schema create" ""; return 1; }
  sqlite3 "$_sd/state.db" "
    PRAGMA foreign_keys=ON;
    INSERT INTO execution (id,schema_version,target_project_path,target_project_description,status,started_at,current_stage,next_instruction,external_urls_whitelist,circular_movement_history,initial_key_aspects,atomic_commit_enabled)
    VALUES ('exec-1','1.0.0','/tmp/p','desc de teste com detalhe','em_andamento','2026-07-30T00:00:00Z','execute-task','faca algo','[]','[]','[]',0);
    INSERT INTO decision (id,execution_id,timestamp,agent,stage,context,options_considered,choice,rationale)
    VALUES ('dec-001','exec-1','2026-07-30T00:00:00Z','x','clarify','contexto de teste com detalhe suficiente','[\"a\"]','a','justificativa de teste com detalhe suficiente');
    ALTER TABLE human_block DROP COLUMN subject_key;
  " || { _fail "seed: insert + drop coluna" ""; return 1; }
  capture "$SCRIPT" list --state-dir "$_sd" --chave-assunto "axis:linguagem-runtime"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "list em banco legado nao deveria falhar" "$_CAPTURED_STDERR"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "banco legado nunca deveria casar" "obtido '$_CAPTURED_STDOUT'"; return 1; }
}

fi # sqlite3 disponivel

# ==== issue #170: sufixo de axis: validado contra o enum fechado ====

scenario_register_axis_fora_do_enum_falha_alto() {
  # Regressao issue #170: `axis:<qualquer-coisa>` passava o register limpo e
  # NUNCA casava no vinculo de consentimento (report.sh itera o mapa) —
  # bloqueio, resposta e decisao existiam sem nada os ligar. Degradava em
  # silencio em vez de falhar.
  _sd="$TMPDIR_TEST/state"
  _setup_with_decisao "$_sd" || { _error "fixture" ""; return 2; }
  capture "$SCRIPT" register --state-dir "$_sd" \
    --decisao-id "dec-001" \
    --pergunta "Pergunta longa o suficiente para passar (>=20 chars)" \
    --contexto-para-resposta "ctx" \
    --chave-assunto "axis:exposicao-transcript-sem-scrub"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "axis fora do enum deveria sair 2" "exit=$_CAPTURED_EXIT stdout=$_CAPTURED_STDOUT"; return 1; }
  assert_stderr_contains "eixo-invalido" || return 1
  # Nada foi gravado.
  capture "$RW" get --state-dir "$_sd" --field '.accumulated_metrics.human_blocks_total'
  assert_stdout_contains "0" || return 1
}

scenario_register_axis_erro_lista_eixos_do_mapa() {
  # A mensagem cita os eixos validos LENDO o mapa (nunca lista hardcoded).
  _sd="$TMPDIR_TEST/state"
  _setup_with_decisao "$_sd" || { _error "fixture" ""; return 2; }
  capture "$SCRIPT" register --state-dir "$_sd" \
    --decisao-id "dec-001" \
    --pergunta "Pergunta longa o suficiente para passar (>=20 chars)" \
    --contexto-para-resposta "ctx" \
    --chave-assunto "axis:eixo-que-nao-existe"
  assert_stderr_contains "linguagem-runtime" || return 1
  assert_stderr_contains "tier-entrega" || return 1
}

scenario_register_todos_os_eixos_do_mapa_sao_aceitos() {
  # Paridade produtor-consumidor: TODO eixo do mapa passa no register.
  _sd="$TMPDIR_TEST/state"
  _setup_with_decisao "$_sd" || { _error "fixture" ""; return 2; }
  _map="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/references/structural-axis-map.txt"
  [ -f "$_map" ] || { _error "mapa ausente: $_map" ""; return 2; }
  _n=0
  while IFS='|' read -r _eixo _rot; do
    case "$_eixo" in ''|\#*) continue ;; esac
    capture "$SCRIPT" register --state-dir "$_sd" \
      --decisao-id "dec-001" \
      --pergunta "Pergunta longa o suficiente para passar (>=20 chars)" \
      --contexto-para-resposta "ctx" \
      --chave-assunto "axis:$_eixo"
    [ "$_CAPTURED_EXIT" = 0 ] || { _fail "eixo do mapa rejeitado: $_eixo" "$_CAPTURED_STDERR"; return 1; }
    _n=$((_n + 1))
  done < "$_map"
  [ "$_n" -ge 6 ] || { _fail "mapa com menos eixos que o esperado" "n=$_n"; return 1; }
}

scenario_register_briefing_item_sufixo_segue_aberto() {
  # `briefing-item:` NAO tem enum fechado (sufixo e id de item do briefing) —
  # a trava de #170 vale so para `axis:`.
  _sd="$TMPDIR_TEST/state"
  _setup_with_decisao "$_sd" || { _error "fixture" ""; return 2; }
  capture "$SCRIPT" register --state-dir "$_sd" \
    --decisao-id "dec-001" \
    --pergunta "Pergunta longa o suficiente para passar (>=20 chars)" \
    --contexto-para-resposta "ctx" \
    --chave-assunto "briefing-item:um-item-qualquer-do-briefing-abc123"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "briefing-item deveria seguir aberto" "$_CAPTURED_STDERR"; return 1; }
}

scenario_list_chave_assunto_nao_valida_enum() {
  # `list --chave-assunto` e QUERY, nao registro: filtrar por chave fora do
  # enum precisa seguir valido (retorna vazio), nunca virar erro.
  _sd="$TMPDIR_TEST/state"
  _setup_with_decisao "$_sd" || { _error "fixture" ""; return 2; }
  capture "$SCRIPT" list --state-dir "$_sd" --chave-assunto "axis:nao-existe-no-mapa"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "list nao deve validar enum" "exit=$_CAPTURED_EXIT $_CAPTURED_STDERR"; return 1; }
}

run_all_scenarios
