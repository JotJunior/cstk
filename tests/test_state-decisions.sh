#!/bin/sh
# test_state-decisions.sh — cobre global/skills/agente-00c-runtime/scripts/state-decisions.sh.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-decisions.sh"
RW="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-rw.sh"

if ! command -v jq >/dev/null 2>&1; then
  printf '# test_state-decisions.sh: jq ausente — pulando suite\n'
  exit 0
fi

_init_state() {
  capture "$RW" init --state-dir "$1" \
    --execucao-id "exec-test-3" --projeto-alvo-path "/tmp/p" --descricao "POC FASE 3"
}

# Wrapper para registro com defaults validos
_register_default() {
  capture "$SCRIPT" register --state-dir "$1" \
    --agente "${2:-orquestrador-00c}" \
    --etapa "${3:-briefing}" \
    --contexto "Pergunta sobre stakeholders do projeto-alvo" \
    --opcoes '["Operador unico","Time pequeno"]' \
    --escolha "Operador unico" \
    --justificativa "Briefing do 00C marca uso pessoal sem stakeholders externos"
}

scenario_register_basico_gera_dec_001() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "init" ""; return 1; }
  _register_default "$_sd"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "register" "$_CAPTURED_EXIT; $_CAPTURED_STDERR"
    return 1
  fi
  assert_stdout_contains "dec-001" || return 1
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "1" || return 1
}

scenario_register_sequencial_gera_dec_002() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  _register_default "$_sd"
  _register_default "$_sd"
  capture "$SCRIPT" next-id --state-dir "$_sd"
  assert_stdout_contains "dec-003" || return 1
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "2" || return 1
}

scenario_contexto_curto_violacao_principio_i() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" register --state-dir "$_sd" \
    --agente "x" --etapa "briefing" \
    --contexto "curto" \
    --opcoes '["A"]' --escolha "A" \
    --justificativa "justificativa de tamanho ok aqui sim"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "contexto curto" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "violacao Principio I" || return 1
  assert_stderr_contains "contexto" || return 1
}

scenario_justificativa_curta_violacao_principio_i() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" register --state-dir "$_sd" \
    --agente "x" --etapa "briefing" \
    --contexto "contexto longo o suficiente — 20+ chars" \
    --opcoes '["A"]' --escolha "A" \
    --justificativa "curta"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "justif curta" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "justificativa" || return 1
}

scenario_opcoes_vazias_violacao_principio_i() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" register --state-dir "$_sd" \
    --agente "x" --etapa "briefing" \
    --contexto "contexto longo o suficiente — 20+ chars" \
    --opcoes '[]' --escolha "A" \
    --justificativa "justificativa de tamanho ok aqui sim"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "opcoes vazias" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "opcoes_consideradas" || return 1
}

scenario_opcoes_nao_array_falha() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" register --state-dir "$_sd" \
    --agente "x" --etapa "briefing" \
    --contexto "contexto longo o suficiente — 20+ chars" \
    --opcoes '"notarray"' --escolha "A" \
    --justificativa "justificativa de tamanho ok aqui sim"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "opcoes nao-array" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_score_invalido_falha() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" register --state-dir "$_sd" \
    --agente "x" --etapa "briefing" \
    --contexto "contexto longo o suficiente — 20+ chars" \
    --opcoes '["A","B"]' --escolha "A" \
    --justificativa "justificativa de tamanho ok aqui sim" \
    --score 7
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "score 7" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_score_valido_persiste() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" register --state-dir "$_sd" \
    --agente "clarify-answerer" --etapa "clarify" \
    --contexto "Q1: stack-sugerida — Go ou Node?" \
    --opcoes '["Go","Node"]' --escolha "Go" \
    --justificativa "Briefing menciona Go; stack-sugerida tambem" \
    --score 3 \
    --evidencia "grep -r 'go.mod' . | head: ./services/auth/go.mod confirma Go"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "register" "$_CAPTURED_STDERR"; return 1; }
  capture "$RW" get --state-dir "$_sd" --field '.decisions[-1].justification_score'
  assert_stdout_contains "3" || return 1
}

scenario_score_3_sem_evidencia_rejeita() {
  # FR-EVI-001: score=3 EXIGE --evidencia (>=20 chars). Sem evidencia, exit 1
  # com mensagem clara. Razao: 3 falsos positivos `score=3` historicos onde
  # agente afirmou premissa tecnica falsa sem rodar tsc/test/grep.
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" register --state-dir "$_sd" \
    --agente "x" --etapa "execute-task" \
    --contexto "Afirmar que Express 5 embute tipos nativos" \
    --opcoes '["Sim","Nao"]' --escolha "Sim" \
    --justificativa "Conviccao baseada em changelog recente da v5" \
    --score 3
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "score=3 sem evidencia" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "score=3" || return 1
  assert_stderr_contains "evidencia" || return 1
}

scenario_score_3_evidencia_curta_rejeita() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" register --state-dir "$_sd" \
    --agente "x" --etapa "execute-task" \
    --contexto "Afirmar comportamento de runtime sem rodar" \
    --opcoes '["A","B"]' --escolha "A" \
    --justificativa "Conviccao baseada em leitura previa do codigo" \
    --score 3 --evidencia "rodei tsc"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "evidencia curta" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "evidencia" || return 1
}

scenario_score_2_sem_evidencia_ainda_aceita() {
  # Score 2 nao exige evidencia — apenas score 3 e cobrado.
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" register --state-dir "$_sd" \
    --agente "x" --etapa "clarify" \
    --contexto "Decisao informada por briefing + stack" \
    --opcoes '["A","B"]' --escolha "A" \
    --justificativa "Briefing menciona explicitamente preferencia A" \
    --score 2
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "score=2 sem evi" "$_CAPTURED_STDERR"; return 1; }
}

# --- Travas FR-CONST-PREFLIGHT (regressao do bypass dec-004) --------------

scenario_preflight_constitution_score2_rejeita() {
  # As 3 opcoes canonicas do BloqueioHumano pre-flight + score!=0 = exit 1.
  # Reproduz exatamente o bypass de dec-004 no projeto github-pages-cstk-manual.
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" register --state-dir "$_sd" \
    --agente "orquestrador-00c" --etapa "constitution" \
    --contexto "Detectada constitution global; alerta pre-skill exit=2" \
    --opcoes '["atualizar-global-via-bump-SemVer","criar-feature-delta-com-sync-impact-report","abortar-feature-sem-principios-proprios"]' \
    --escolha "criar-feature-delta-com-sync-impact-report" \
    --justificativa "Auto Mode — feature e doc-scoped, delta razoavel" \
    --score 2
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "preflight score=2 deveria rejeitar" "exit=$_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
  assert_stderr_contains "violacao protocolo constitution-conflict" || return 1
  assert_stderr_contains "EXIGE --score 0" || return 1
}

scenario_preflight_constitution_score0_aceita() {
  # Mesmas 3 opcoes canonicas com --score 0 + escolha "pause-humano" = OK.
  # Caminho correto: registrar pre-flight como pause antes do BloqueioHumano.
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" register --state-dir "$_sd" \
    --agente "orquestrador-00c" --etapa "constitution" \
    --contexto "Detectada constitution global; alerta pre-skill exit=2" \
    --opcoes '["atualizar-global-via-bump-SemVer","criar-feature-delta-com-sync-impact-report","abortar-feature-sem-principios-proprios"]' \
    --escolha "pause-humano" \
    --justificativa "Exit=2 detectado, registrando para BloqueioHumano" \
    --score 0
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "preflight score=0" "$_CAPTURED_STDERR"; return 1; }
}

scenario_preflight_ordem_opcoes_irrelevante() {
  # As 3 strings canonicas em ordem diferente ainda dispara a trava.
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" register --state-dir "$_sd" \
    --agente "orquestrador-00c" --etapa "constitution" \
    --contexto "Detectada constitution global; alerta pre-skill exit=2" \
    --opcoes '["abortar-feature-sem-principios-proprios","atualizar-global-via-bump-SemVer","criar-feature-delta-com-sync-impact-report"]' \
    --escolha "atualizar-global-via-bump-SemVer" \
    --justificativa "Tentativa de bypass com ordem trocada" \
    --score 2
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "preflight ordem trocada deveria rejeitar" "exit=$_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "violacao protocolo constitution-conflict" || return 1
}

scenario_etapa_constitution_sem_opcoes_canonicas_passa() {
  # etapa=constitution com opcoes diferentes (ex: ratificacao tipo dec-005)
  # + score=2 deve PASSAR — backward-compat para decisoes pos-flight.
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" register --state-dir "$_sd" \
    --agente "orquestrador-00c" --etapa "constitution" \
    --contexto "Skill constitution materializou feature-delta com 6 principios" \
    --opcoes '["aceitar-delta-como-criado","retrabalhar-principios","fundir-com-global"]' \
    --escolha "aceitar-delta-como-criado" \
    --justificativa "Delta cobre 6 dominios; Sync Impact Report populado" \
    --score 2
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "ratificacao posterior" "$_CAPTURED_STDERR"; return 1; }
}

scenario_preflight_apenas_2_opcoes_canonicas_passa() {
  # Trava so dispara com TODAS as 3 strings canonicas. Decisao com apenas
  # 2 delas (improvavel mas possivel) cai no fluxo normal.
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" register --state-dir "$_sd" \
    --agente "orquestrador-00c" --etapa "constitution" \
    --contexto "Cenario hipotetico com 2 opcoes canonicas + 1 alternativa" \
    --opcoes '["atualizar-global-via-bump-SemVer","criar-feature-delta-com-sync-impact-report","outra-opcao"]' \
    --escolha "outra-opcao" \
    --justificativa "Decisao com perfil parcial das 3 strings canonicas" \
    --score 2
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "2 de 3 canonicas" "$_CAPTURED_STDERR"; return 1; }
}

scenario_score_3_persiste_evidencia_no_estado() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  _evi='npx tsc --noEmit: error TS2322 em src/foo.ts:12 confirma tipo nao bate'
  capture "$SCRIPT" register --state-dir "$_sd" \
    --agente "x" --etapa "execute-task" \
    --contexto "Decisao tecnica empiricamente validada por TS" \
    --opcoes '["Manter","Trocar"]' --escolha "Trocar" \
    --justificativa "Output de tsc indica incompatibilidade real" \
    --score 3 --evidencia "$_evi"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "register" "$_CAPTURED_STDERR"; return 1; }
  capture "$RW" get --state-dir "$_sd" --field '.decisions[-1].evidence'
  assert_stdout_contains "tsc" || return 1
  assert_stdout_contains "TS2322" || return 1
}

scenario_score_baixo_evidencia_null_no_estado() {
  # Score 0/1/2/null sem --evidencia -> campo evidence=null no objeto.
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  _register_default "$_sd"
  capture "$RW" get --state-dir "$_sd" --field '.decisions[-1].evidence'
  assert_stdout_contains "null" || return 1
}

scenario_count_filtra_por_agente() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  _register_default "$_sd" "orquestrador-00c"
  _register_default "$_sd" "clarify-asker"
  _register_default "$_sd" "clarify-asker"
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "3" || return 1
  capture "$SCRIPT" count --state-dir "$_sd" --agente "clarify-asker"
  assert_stdout_contains "2" || return 1
}

scenario_list_imprime_tsv() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  _register_default "$_sd"
  capture "$SCRIPT" list --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "list" "$_CAPTURED_EXIT"; return 1; }
  # Formato: id\tonda_id\tagente\tetapa\tescolha
  assert_stdout_contains "dec-001	" || return 1
  assert_stdout_contains "	orquestrador-00c	" || return 1
  assert_stdout_contains "	briefing	" || return 1
  assert_stdout_contains "	Operador unico" || return 1
}

scenario_metricas_acumuladas_decisoes_total_incrementa() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  _register_default "$_sd"
  capture "$RW" get --state-dir "$_sd" --field '.accumulated_metrics.decisions_total'
  assert_stdout_contains "1" || return 1
  _register_default "$_sd"
  capture "$RW" get --state-dir "$_sd" --field '.accumulated_metrics.decisions_total'
  assert_stdout_contains "2" || return 1
}

scenario_register_state_ausente_falha() {
  _sd="$TMPDIR_TEST/empty"
  mkdir -p "$_sd"
  _register_default "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "state ausente" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

# --- Back-compat: fixture pt-BR legada lida via reader-fallback (.en // .pt) ---
# schema-en-migration: os readers (count/list/next-id) usam paths EN com
# fallback pt-BR, e register faz append EN sobre o doc pt-BR vivo. Prova que
# um state.json legado (escrito antes da migracao, com chaves .decisoes/.ondas/
# .agente/.escolha/.metricas_acumuladas) continua legivel sem migrate previo.
_write_legacy_ptbr_state() {
  # $1 = state-dir. Escreve um state.json minimo com chaves pt-BR legadas.
  mkdir -p "$1"
  cat > "$1/state.json" <<'PTBR'
{
  "schema_version": 1,
  "ondas": [{ "id": "onda-001" }],
  "decisoes": [
    {
      "id": "dec-001",
      "onda_id": "onda-001",
      "timestamp": "2024-01-01T00:00:00Z",
      "etapa": "briefing",
      "agente": "orquestrador-00c",
      "contexto": "Decisao legada pt-BR para back-compat",
      "opcoes_consideradas": ["A", "B"],
      "escolha": "Opcao legada A",
      "justificativa": "Registro pre-migracao em chaves pt-BR",
      "score_justificativa": 2
    }
  ],
  "metricas_acumuladas": { "decisoes_total": 1 }
}
PTBR
}

scenario_ptbr_legado_readers_via_fallback() {
  # count/list/next-id leem o doc pt-BR via fallback (.decisoes // ...),
  # (.agente // ...), (.escolha // ...), .decisoes[].id.
  _sd="$TMPDIR_TEST/legacy"
  _write_legacy_ptbr_state "$_sd"

  capture "$SCRIPT" count --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "count pt-BR" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "1" || return 1

  capture "$SCRIPT" count --state-dir "$_sd" --agente "orquestrador-00c"
  assert_stdout_contains "1" || return 1

  # next-id deriva de max(.decisoes[].id) = dec-001 -> dec-002.
  capture "$SCRIPT" next-id --state-dir "$_sd"
  assert_stdout_contains "dec-002" || return 1

  # list emite a escolha legada via (.choice // .escolha).
  capture "$SCRIPT" list --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "list pt-BR" "$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "dec-001	" || return 1
  assert_stdout_contains "	onda-001	" || return 1
  assert_stdout_contains "	Opcao legada A" || return 1
}

scenario_ptbr_legado_register_helpers_via_fallback() {
  # Os helpers internos do register (_sd_next_dec_id, _sd_current_onda_id) leem
  # as chaves pt-BR legadas via fallback ANTES de construir a decisao EN:
  #   - next-id deriva de max(.decisoes[].id) = dec-001 -> dec-002;
  #   - wave_id da decisao nova liga a (.waves // .ondas)[-1].id = onda-001.
  # O writer em si grava chaves EN sem fallback (contrato: confia em EN-on-disk;
  # o command-pai roda `state-rw.sh migrate` antes dos direct-writers). Logo este
  # cenario prova so o lado READER do register sobre um doc pt-BR.
  _sd="$TMPDIR_TEST/legacy2"
  _write_legacy_ptbr_state "$_sd"

  _register_default "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "register sobre pt-BR" "$_CAPTURED_STDERR"; return 1; }
  # id sequencial computado sobre as decisoes pt-BR legadas (.decisoes[].id).
  assert_stdout_contains "dec-002" || return 1

  # A decisao nova foi gravada com chave EN (.wave_id) ligada a onda legada.
  # Lemos via state-rw get (canonicaliza o doc misto -> EN antes do jq).
  capture "$RW" get --state-dir "$_sd" --field '.decisions[-1].wave_id'
  assert_stdout_contains "onda-001" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.decisions[-1].id'
  assert_stdout_contains "dec-002" || return 1
}

# ==== Backend dual SQLite (feature state-db-foundation, FASE 3 task 3.4) ====
#
# Ref: docs/specs/state-db-foundation/contracts/primitives.md §C1 (paridade)
#      §C2 (selecao de backend) §C4 (transacao) §C6 (concorrencia) §C8 (escape)
#
# Mesmo padrao de tests/test_state-ondas.sh (task 3.3): aplica o DDL via
# state-db-schema.sh e semeia uma execution minima via sqlite3 diretamente
# (init nunca cria state.db — isso e a migracao, FASE 6, ainda nao
# implementada).

SCHEMA_SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-db-schema.sh"
SO="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-ondas.sh"

if ! command -v sqlite3 >/dev/null 2>&1; then
  printf '# test_state-decisions.sh: sqlite3 ausente — pulando cenarios de backend SQLite\n'
else

# _seed_sqlite_backend DIR -> cria state.db com uma execution minima
# (id=exec-1), pronta para register/count/next-id/list.
_seed_sqlite_backend() {
  _ssb_dir=$1
  mkdir -p "$_ssb_dir"
  "$SCHEMA_SCRIPT" create --db "$_ssb_dir/state.db" >/dev/null 2>&1 \
    || { _fail "seed: schema create falhou" ""; return 1; }
  sqlite3 "$_ssb_dir/state.db" "
    PRAGMA foreign_keys=ON;
    INSERT INTO execution (id,schema_version,target_project_path,target_project_description,status,started_at,current_stage,next_instruction,external_urls_whitelist,circular_movement_history,initial_key_aspects,atomic_commit_enabled)
    VALUES ('exec-1','1.0.0','/tmp/p','desc de teste com detalhe','em_andamento','2026-07-30T00:00:00Z','execute-task','faca algo','[]','[]','[]',0);
  " || { _fail "seed: insert execution falhou" ""; return 1; }
}

scenario_sqlite_register_gera_dec_001() {
  _sd="$TMPDIR_TEST/sqlite-register-001"
  _seed_sqlite_backend "$_sd" || return 1
  _register_default "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sqlite register" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "dec-001" || return 1
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "1" || return 1
}

scenario_sqlite_register_sequencial_gera_dec_002() {
  _sd="$TMPDIR_TEST/sqlite-register-seq"
  _seed_sqlite_backend "$_sd" || return 1
  _register_default "$_sd"
  _register_default "$_sd"
  assert_stdout_contains "dec-002" || return 1
  capture "$SCRIPT" next-id --state-dir "$_sd"
  assert_stdout_contains "dec-003" || return 1
}

scenario_sqlite_wave_id_null_sem_onda_vira_init_no_list() {
  # data-model.md: wave_id NULL representa "init" (nenhuma onda ainda).
  # list normaliza para "init" na saida textual (mesma convencao do JSON).
  _sd="$TMPDIR_TEST/sqlite-wave-id-init"
  _seed_sqlite_backend "$_sd" || return 1
  _register_default "$_sd"
  capture "$SCRIPT" list --state-dir "$_sd"
  assert_stdout_contains "	init	" || return 1
}

scenario_sqlite_wave_id_liga_onda_aberta() {
  _sd="$TMPDIR_TEST/sqlite-wave-id-open"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SO" start --state-dir "$_sd"
  _register_default "$_sd"
  capture "$SCRIPT" list --state-dir "$_sd"
  assert_stdout_contains "	onda-001	" || return 1
}

scenario_sqlite_count_filtra_por_agente() {
  _sd="$TMPDIR_TEST/sqlite-count-agente"
  _seed_sqlite_backend "$_sd" || return 1
  _register_default "$_sd" "orquestrador-00c"
  _register_default "$_sd" "clarify-asker"
  _register_default "$_sd" "clarify-asker"
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "3" || return 1
  capture "$SCRIPT" count --state-dir "$_sd" --agente "clarify-asker"
  assert_stdout_contains "2" || return 1
}

scenario_sqlite_list_imprime_tsv() {
  _sd="$TMPDIR_TEST/sqlite-list-tsv"
  _seed_sqlite_backend "$_sd" || return 1
  _register_default "$_sd"
  capture "$SCRIPT" list --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sqlite list" "$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "dec-001	" || return 1
  assert_stdout_contains "	orquestrador-00c	" || return 1
  assert_stdout_contains "	briefing	" || return 1
  assert_stdout_contains "	Operador unico" || return 1
}

scenario_sqlite_score_3_sem_evidencia_rejeita() {
  # Validacao Principio I (FR-EVI-001) roda ANTES do dispatch de backend —
  # paridade de comportamento com o path JSON.
  _sd="$TMPDIR_TEST/sqlite-score3-sem-evi"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" register --state-dir "$_sd" \
    --agente "x" --etapa "execute-task" \
    --contexto "Afirmar comportamento de runtime sem rodar sonda" \
    --opcoes '["A","B"]' --escolha "A" \
    --justificativa "Conviccao baseada em leitura previa do codigo" \
    --score 3
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "sqlite score=3 sem evidencia" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "evidencia" || return 1
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "0" || return 1
}

scenario_sqlite_score_3_com_evidencia_persiste() {
  _sd="$TMPDIR_TEST/sqlite-score3-com-evi"
  _seed_sqlite_backend "$_sd" || return 1
  _evi='npx tsc --noEmit: error TS2322 em src/foo.ts:12 confirma tipo nao bate'
  capture "$SCRIPT" register --state-dir "$_sd" \
    --agente "x" --etapa "execute-task" \
    --contexto "Decisao tecnica empiricamente validada por TS" \
    --opcoes '["Manter","Trocar"]' --escolha "Trocar" \
    --justificativa "Output de tsc indica incompatibilidade real" \
    --score 3 --evidencia "$_evi"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sqlite score=3" "$_CAPTURED_STDERR"; return 1; }
  capture "$RW" get --state-dir "$_sd" --field '.decisions[-1].evidence'
  assert_stdout_contains "TS2322" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.decisions[-1].justification_score'
  assert_stdout_contains "3" || return 1
}

# C8: payload hostil (apostrofo + tentativa de injecao) persistido literal,
# tabela decision sobrevive, integrity_check continua ok. Paridade com
# tests/test__state-db.sh scenario_state_db_exec_persiste_payload_hostil_*.
scenario_sqlite_payload_hostil_preservado_literal_tabela_sobrevive() {
  _sd="$TMPDIR_TEST/sqlite-hostil"
  _seed_sqlite_backend "$_sd" || return 1
  _hostil="'; DROP TABLE decision; -- e apostrofo simples it's here"
  capture "$SCRIPT" register --state-dir "$_sd" \
    --agente "x" --etapa "specify" \
    --contexto "$_hostil (20+ chars de contexto)" \
    --opcoes '["a","b"]' --escolha "$_hostil" \
    --justificativa "justificativa com o mesmo payload hostil $_hostil"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sqlite payload hostil" "$_CAPTURED_STDERR"; return 1; }
  capture "$RW" get --state-dir "$_sd" --field '.decisions[-1].choice'
  assert_stdout_contains "DROP TABLE decision" || return 1
  capture "$RW" sha256-verify --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "integrity apos payload hostil" "$_CAPTURED_STDERR"; return 1; }
}

scenario_sqlite_register_state_db_ausente_falha() {
  _sd="$TMPDIR_TEST/sqlite-ausente"
  mkdir -p "$_sd"
  # sem state.db -> backend json (C2); sem state.json tambem -> falha 1
  _register_default "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "sqlite state ausente" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

# Teste de concorrencia (task 3.4.3): N invocacoes simultaneas de `register`
# nao perdem nenhuma decisao e nao colidem em next-id — cada uma recebe um
# dec-NNN unico, e o total persistido bate com N.
scenario_sqlite_register_concorrente_sem_colisao() {
  _sd="$TMPDIR_TEST/sqlite-concorrencia"
  _seed_sqlite_backend "$_sd" || return 1
  _n=15
  _i=1
  while [ "$_i" -le "$_n" ]; do
    ( "$SCRIPT" register --state-dir "$_sd" \
        --agente "worker-$_i" --etapa "specify" \
        --contexto "contexto concorrente numero $_i com 20+ chars" \
        --opcoes '["a","b"]' --escolha "a" \
        --justificativa "justificativa concorrente numero $_i com 20+chars" \
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
# (dec-001) para o primeiro register em cada backend.
scenario_sqlite_paridade_register_primeiro_id_json() {
  _sd_json="$TMPDIR_TEST/paridade-decisions-json"
  _init_state "$_sd_json"
  _register_default "$_sd_json"
  _json_id="$_CAPTURED_STDOUT"

  _sd_db="$TMPDIR_TEST/paridade-decisions-sqlite"
  _seed_sqlite_backend "$_sd_db" || return 1
  _register_default "$_sd_db"
  _db_id="$_CAPTURED_STDOUT"

  [ "$_json_id" = "$_db_id" ] || { _fail "paridade register id" "json='$_json_id' sqlite='$_db_id'"; return 1; }
}

fi # sqlite3 disponivel

run_all_scenarios
