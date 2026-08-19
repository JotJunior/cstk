#!/bin/sh
# test_state-decisions.sh — cobre plugins/cstk/skills/agente-00c-runtime/scripts/state-decisions.sh.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/state-decisions.sh"
RW="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/state-rw.sh"
BL="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/bloqueios.sh"

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

SCHEMA_SCRIPT="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/state-db-schema.sh"
SO="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/state-ondas.sh"

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

# Task 4.1.1/4.2.2 (FASE 4): branch de selecao de backend explicito por C2 —
# um state.json coexistente e export/legado, NUNCA consultado como fonte.
# Prova positiva: 1 decisao registrada no state.db, state.json divergente
# com 5 decisoes falsas — count deve refletir sempre o state.db (1).
scenario_c2_state_json_coexistente_ignorado_quando_state_db_presente() {
  _sd="$TMPDIR_TEST/c2-coexist-decisions"
  _seed_sqlite_backend "$_sd" || return 1
  _register_default "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "c2: register sqlite" "$_CAPTURED_STDERR"; return 1; }

  # state.json divergente no MESMO diretorio (5 decisoes falsas).
  printf '{"decisions":[1,2,3,4,5]}\n' > "$_sd/state.json"

  capture "$SCRIPT" count --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "c2 count exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "1" \
    || { _fail "c2: count deveria refletir state.db (1), nao o state.json coexistente (5)" "obtido $_CAPTURED_STDOUT"; return 1; }
  case "$_CAPTURED_STDOUT" in
    5*) _fail "c2: count leu o state.json coexistente" "obtido $_CAPTURED_STDOUT"; return 1 ;;
  esac

  # state.json coexistente permanece intocado.
  _stale_now=$(cat "$_sd/state.json")
  [ "$_stale_now" = '{"decisions":[1,2,3,4,5]}' ] \
    || { _fail "c2: state.json coexistente foi modificado" "obtido: $_stale_now"; return 1; }
}

fi # sqlite3 disponivel

# Paridade com o fix das issues #122/#123 (bloqueios.sh): _sd_next_dec_id ja
# usava command substitution, mas sem strip de \r — jq Windows com CRLF
# corromperia a aritmetica do mesmo jeito. Cobre o hardening (tr -d '\r' +
# guard numerico) com um stub de jq que emite CRLF.
scenario_next_id_tolera_jq_com_saida_crlf() {
  _sd="$TMPDIR_TEST/state-crlf"
  mkdir -p -- "$_sd"
  printf '%s\n' '{"execution":{"id":"exec-1"},"decisions":[{"id":"dec-007"}]}' \
    > "$_sd/state.json"
  _bin="$TMPDIR_TEST/crlf-bin"
  mkdir -p -- "$_bin"
  _realjq=$(command -v jq) || { _error "jq ausente" ""; return 2; }
  printf '#!/bin/sh\n%s "$@" | while IFS= read -r _l; do printf "%%s\\r\\n" "$_l"; done\n' \
    "$_realjq" > "$_bin/jq"
  chmod +x "$_bin/jq"
  capture env PATH="$_bin:$PATH" "$SCRIPT" next-id --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "next-id com jq CRLF" "exit $_CAPTURED_EXIT; $_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "dec-008" || return 1
}

# ==== issue #141: forma dos itens de --opcoes / --referencias ====
scenario_issue141_register_aceita_opcoes_objeto_com_rotulo() {
  _sd="$TMPDIR_TEST/state-141-ok"
  _init_state "$_sd"
  capture "$SCRIPT" register --state-dir "$_sd" \
    --agente "clarify-answerer" --etapa "clarify" \
    --contexto "Pergunta sobre stakeholders do projeto-alvo" \
    --opcoes '[{"rotulo":"A","descricao":"opcao A","default_sugerido":true},{"label":"B"},"C"]' \
    --escolha "A" \
    --justificativa "Briefing do 00C marca uso pessoal sem stakeholders externos" --score 2
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "register" "esperado 0, obtido $_CAPTURED_EXIT; $_CAPTURED_STDERR"; return 1; }
  capture "$RW" get --state-dir "$_sd" --field '.decisions[0].options_considered[0].rotulo'
  [ "$_CAPTURED_STDOUT" = "A" ] || { _fail "objeto preservado no state" "obtido '$_CAPTURED_STDOUT'"; return 1; }
}

scenario_issue141_register_rejeita_forma_invalida_em_opcoes() {
  _sd="$TMPDIR_TEST/state-141-bad"
  _init_state "$_sd"
  for _bad in '[1]' '[null]' '[""]' '[{"descricao":"sem rotulo"}]' '[{"rotulo":""}]' '[["A"]]'; do
    capture "$SCRIPT" register --state-dir "$_sd" \
      --agente "x" --etapa "clarify" \
      --contexto "Pergunta sobre stakeholders do projeto-alvo" \
      --opcoes "$_bad" --escolha "A" \
      --justificativa "Briefing do 00C marca uso pessoal sem stakeholders externos"
    [ "$_CAPTURED_EXIT" = 1 ] || { _fail "deveria rejeitar $_bad com exit 1" "obtido $_CAPTURED_EXIT"; return 1; }
    assert_stderr_contains "cada item de --opcoes" || return 1
  done
  capture "$RW" get --state-dir "$_sd" --field '.decisions | length'
  [ "$_CAPTURED_STDOUT" = "0" ] || { _fail "nenhuma decisao deveria ter sido gravada" "obtido $_CAPTURED_STDOUT"; return 1; }
}

scenario_issue141_register_rejeita_forma_invalida_em_referencias() {
  _sd="$TMPDIR_TEST/state-141-refs"
  _init_state "$_sd"
  capture "$SCRIPT" register --state-dir "$_sd" \
    --agente "x" --etapa "clarify" \
    --contexto "Pergunta sobre stakeholders do projeto-alvo" \
    --opcoes '["A"]' --escolha "A" \
    --justificativa "Briefing do 00C marca uso pessoal sem stakeholders externos" \
    --referencias '[1, null]'
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "referencias invalidas deveriam dar exit 2" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "cada item de --referencias" || return 1
  # string e objeto chave=valor continuam aceitos (report.sh ja renderiza os dois).
  capture "$SCRIPT" register --state-dir "$_sd" \
    --agente "x" --etapa "clarify" \
    --contexto "Pergunta sobre stakeholders do projeto-alvo" \
    --opcoes '["A"]' --escolha "A" \
    --justificativa "Briefing do 00C marca uso pessoal sem stakeholders externos" \
    --referencias '["docs/spec.md", {"arquivo":"spec.md","linha":"12"}]'
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "referencias validas" "$_CAPTURED_STDERR"; return 1; }
}

# ==== issue #144: mark-invalid (invalidacao append-only) ====
scenario_issue144_mark_invalid_registra_nova_decisao_e_preserva_original() {
  _sd="$TMPDIR_TEST/state-144"
  _init_state "$_sd"
  _register_default "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "register" "$_CAPTURED_STDERR"; return 1; }
  _orig_before=$(capture "$RW" get --state-dir "$_sd" --field '.decisions[0]'; printf '%s' "$_CAPTURED_STDOUT")

  capture "$SCRIPT" mark-invalid --state-dir "$_sd" --decisao-id dec-001 \
    --motivo "escolha registrada com typo, decisao real foi Time pequeno"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "mark-invalid" "$_CAPTURED_STDERR"; return 1; }
  [ "$_CAPTURED_STDOUT" = "dec-002" ] || { _fail "stdout" "esperado dec-002, obtido '$_CAPTURED_STDOUT'"; return 1; }

  # Original INTACTA (append-only — Principio I).
  capture "$RW" get --state-dir "$_sd" --field '.decisions[0]'
  [ "$_CAPTURED_STDOUT" = "$_orig_before" ] || { _fail "dec-001 foi alterada" "$_CAPTURED_STDOUT"; return 1; }
  # Nova Decisao com a convencao deterministica.
  capture "$RW" get --state-dir "$_sd" --field '.decisions[1] | [.choice, .originating_artifact, .stage, .agent, (.options_considered|join(","))] | join("|")'
  [ "$_CAPTURED_STDOUT" = "invalidar-dec-001|dec-001|briefing|operador|manter-dec-001,invalidar-dec-001" ] \
    || { _fail "convencao da invalidacao" "obtido '$_CAPTURED_STDOUT'"; return 1; }
  capture "$RW" get --state-dir "$_sd" --field '.decisions[1].context'
  case "$_CAPTURED_STDOUT" in "INVALIDACAO de dec-001: escolha registrada"*) ;; *) _fail "contexto" "$_CAPTURED_STDOUT"; return 1 ;; esac
  capture "$RW" get --state-dir "$_sd" --field '.accumulated_metrics.decisions_total'
  [ "$_CAPTURED_STDOUT" = "2" ] || { _fail "decisions_total" "obtido $_CAPTURED_STDOUT"; return 1; }
}

scenario_issue144_mark_invalid_recusa_inexistente_duplicada_encadeada_e_motivo_curto() {
  _sd="$TMPDIR_TEST/state-144-bad"
  _init_state "$_sd"
  _register_default "$_sd"
  capture "$SCRIPT" mark-invalid --state-dir "$_sd" --decisao-id dec-077 --motivo "decisao que nao existe para testar erro"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "inexistente" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "nao encontrada" || return 1
  capture "$SCRIPT" mark-invalid --state-dir "$_sd" --decisao-id dec-001 --motivo "curto"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "motivo curto" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "< 20 chars" || return 1
  capture "$SCRIPT" mark-invalid --state-dir "$_sd" --decisao-id dec-001 --motivo "primeira invalidacao valida com motivo longo"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "1a invalidacao" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" mark-invalid --state-dir "$_sd" --decisao-id dec-001 --motivo "segunda tentativa de invalidar a mesma decisao"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "duplicada" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "ja invalidada por dec-002" || return 1
  # Invalidar a propria invalidacao nao se encadeia.
  capture "$SCRIPT" mark-invalid --state-dir "$_sd" --decisao-id dec-002 --motivo "tentando invalidar a invalidacao dec-002"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "encadeada" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "ela mesma uma invalidacao" || return 1
  capture "$SCRIPT" mark-invalid --state-dir "$_sd" --decisao-id dec-001
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "sem --motivo" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
  capture "$RW" get --state-dir "$_sd" --field '.decisions | length'
  [ "$_CAPTURED_STDOUT" = "2" ] || { _fail "so 2 decisoes deveriam existir" "obtido $_CAPTURED_STDOUT"; return 1; }
}

scenario_issue144_sqlite_mark_invalid_backend_agnostico() {
  _sd="$TMPDIR_TEST/state-144-sqlite"
  _seed_sqlite_backend "$_sd" || return 1
  sqlite3 "$_sd/state.db" "INSERT INTO wave (id,execution_id,seq,started_at) VALUES ('onda-001','exec-1',1,'2026-07-30T00:00:00Z');" \
    || { _fail "seed wave" ""; return 1; }
  _register_default "$_sd" "orquestrador-00c" "plan"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "register sqlite" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" mark-invalid --state-dir "$_sd" --decisao-id dec-001 \
    --motivo "invalidacao sob backend sqlite para teste de paridade" --agente "revisor"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "mark-invalid sqlite" "$_CAPTURED_STDERR"; return 1; }
  [ "$_CAPTURED_STDOUT" = "dec-002" ] || { _fail "id" "obtido '$_CAPTURED_STDOUT'"; return 1; }
  _row=$(sqlite3 "$_sd/state.db" "SELECT choice||'|'||originating_artifact||'|'||stage||'|'||agent FROM decision WHERE id='dec-002';")
  [ "$_row" = "invalidar-dec-001|dec-001|plan|revisor" ] || { _fail "linha sqlite" "obtido '$_row'"; return 1; }
  [ -e "$_sd/state.json" ] && { _fail "anti-mirror" "mark-invalid criou state.json no state-dir sqlite"; return 1; }
  return 0
}

# ==== structural-decision-human-gate (FASE 2, task 2.1.10): trava R1..R3, R6 ====
#
# Ref: docs/specs/structural-decision-human-gate/data-model.md §Regras de
#      integridade; contracts/cli-structural-class.md §state-decisions.sh
#      register (extensao)

# _patch_human_block_subject_key_json STATE_DIR BLOCK_ID SUBJECT -> fixture
# helper (nao passa por bloqueios.sh — --chave-assunto e FASE 2.4, ainda nao
# implementada nesta onda). Mesma logica de fixture direta ja usada por
# _seed_sqlite_backend para o backend SQLite.
_patch_human_block_subject_key_json() {
  _phb_sd="$1"; _phb_id="$2"; _phb_subj="$3"
  _phb_tmp=$(mktemp) || return 1
  jq --arg id "$_phb_id" --arg subj "$_phb_subj" '
    .human_blocks |= map(if .id == $id then .subject_key = $subj else . end)
  ' "$_phb_sd/state.json" > "$_phb_tmp" && mv "$_phb_tmp" "$_phb_sd/state.json"
}

scenario_sdhg_r1_opcoes_bloqueio_sem_classe_falha() {
  _sd="$TMPDIR_TEST/sdhg-r1"
  _init_state "$_sd"
  capture "$SCRIPT" register --state-dir "$_sd" \
    --agente "x" --etapa "plan" \
    --contexto "Escolher linguagem e runtime do backend do projeto" \
    --opcoes '["bloqueio-humano-linguagem-runtime","manter-atual"]' \
    --escolha "bloqueio-humano-linguagem-runtime" \
    --justificativa "Sem consenso sobre linguagem, precisa de decisao humana" \
    --score 0
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "R1 sem --classe" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "classe-obrigatoria" || return 1
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "0" || return 1
}

scenario_sdhg_r1_opcoes_bloqueio_via_rotulo_objeto_sem_classe_falha() {
  # Familia avaliada pelo `rotulo`/`label` quando o item de --opcoes e objeto.
  _sd="$TMPDIR_TEST/sdhg-r1-objeto"
  _init_state "$_sd"
  capture "$SCRIPT" register --state-dir "$_sd" \
    --agente "x" --etapa "plan" \
    --contexto "Escolher persistencia principal do sistema" \
    --opcoes '[{"rotulo":"pause-humano","descricao":"aguardar decisao"},"seguir"]' \
    --escolha "pause-humano" \
    --justificativa "Persistencia ainda nao decidida pelo dono do produto" \
    --score 0
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "R1 objeto sem --classe" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "classe-obrigatoria" || return 1
}

scenario_sdhg_classe_invalida_falha() {
  _sd="$TMPDIR_TEST/sdhg-classe-invalida"
  _init_state "$_sd"
  capture "$SCRIPT" register --state-dir "$_sd" \
    --agente "x" --etapa "plan" \
    --contexto "Decisao operacional qualquer, so pra testar --classe" \
    --opcoes '["A","B"]' --escolha "A" \
    --justificativa "Justificativa generica com 20+ chars aqui" \
    --classe "invalida-mesmo"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "classe invalida" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "classe-invalida" || return 1
}

scenario_sdhg_r3_eixo_ausente_falha() {
  _sd="$TMPDIR_TEST/sdhg-r3-ausente"
  _init_state "$_sd"
  capture "$SCRIPT" register --state-dir "$_sd" \
    --agente "x" --etapa "plan" \
    --contexto "Escolher linguagem e runtime do backend do projeto" \
    --opcoes '["bloqueio-humano-linguagem-runtime"]' \
    --escolha "bloqueio-humano-linguagem-runtime" \
    --justificativa "Sem consenso sobre linguagem, precisa de decisao humana" \
    --score 0 --classe estrutural
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "R3 eixo ausente" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "eixo-invalido" || return 1
}

scenario_sdhg_r3_eixo_fora_do_enum_falha() {
  _sd="$TMPDIR_TEST/sdhg-r3-fora"
  _init_state "$_sd"
  capture "$SCRIPT" register --state-dir "$_sd" \
    --agente "x" --etapa "plan" \
    --contexto "Escolher linguagem e runtime do backend do projeto" \
    --opcoes '["bloqueio-humano-linguagem-runtime"]' \
    --escolha "bloqueio-humano-linguagem-runtime" \
    --justificativa "Sem consenso sobre linguagem, precisa de decisao humana" \
    --score 0 --classe estrutural --eixo "cor-do-logo"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "R3 eixo fora do enum" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "eixo-invalido" || return 1
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "0" || return 1
}

scenario_sdhg_r2_escolha_concreta_sem_consentimento_falha() {
  _sd="$TMPDIR_TEST/sdhg-r2-escolha"
  _init_state "$_sd"
  capture "$SCRIPT" register --state-dir "$_sd" \
    --agente "x" --etapa "plan" \
    --contexto "Decidir a linguagem/runtime sozinho, sem gate" \
    --opcoes '["Go 1.22","Node 22"]' --escolha "Go 1.22" \
    --justificativa "Acho que Go e melhor pra esse caso de uso" \
    --score 0 --classe estrutural --eixo linguagem-runtime
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "R2 escolha concreta" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "estrutural-exige-bloqueio" || return 1
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "0" || return 1
}

scenario_sdhg_r2_score_nao_zero_sem_consentimento_falha() {
  _sd="$TMPDIR_TEST/sdhg-r2-score"
  _init_state "$_sd"
  capture "$SCRIPT" register --state-dir "$_sd" \
    --agente "x" --etapa "plan" \
    --contexto "Escolher linguagem e runtime do backend do projeto" \
    --opcoes '["bloqueio-humano-linguagem-runtime"]' \
    --escolha "bloqueio-humano-linguagem-runtime" \
    --justificativa "Sem consenso sobre linguagem, precisa de decisao humana" \
    --score 2 --classe estrutural --eixo linguagem-runtime
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "R2 score != 0" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "estrutural-exige-bloqueio" || return 1
}

scenario_sdhg_estrutural_sem_consentimento_pausa_humano_persiste() {
  _sd="$TMPDIR_TEST/sdhg-pausa-ok"
  _init_state "$_sd"
  capture "$SCRIPT" register --state-dir "$_sd" \
    --agente "x" --etapa "plan" \
    --contexto "Escolher linguagem e runtime do backend do projeto" \
    --opcoes '["bloqueio-humano-linguagem-runtime","manter-atual"]' \
    --escolha "bloqueio-humano-linguagem-runtime" \
    --justificativa "Sem consenso sobre linguagem, precisa de decisao humana" \
    --score 0 --classe estrutural --eixo linguagem-runtime
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "pausa estrutural" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "dec-001" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.decisions[0].decision_class'
  [ "$_CAPTURED_STDOUT" = "estrutural" ] || { _fail "decision_class" "obtido $_CAPTURED_STDOUT"; return 1; }
  capture "$RW" get --state-dir "$_sd" --field '.decisions[0].structural_axis'
  [ "$_CAPTURED_STDOUT" = "linguagem-runtime" ] || { _fail "structural_axis" "obtido $_CAPTURED_STDOUT"; return 1; }
  capture "$RW" get --state-dir "$_sd" --field '.decisions[0].human_consent_block_id'
  [ "$_CAPTURED_STDOUT" = "null" ] || { _fail "human_consent_block_id deveria ser null" "obtido $_CAPTURED_STDOUT"; return 1; }
}

# Fixture comum aos cenarios de R6: registra a decisao de pausa (dec-001),
# abre o bloqueio (block-001), responde e injeta subject_key='axis:<eixo>'
# (fixture direta — --chave-assunto e FASE 2.4).
_sdhg_seed_consent_json() {
  _ssc_sd="$1"; _ssc_eixo="${2:-linguagem-runtime}"
  _init_state "$_ssc_sd"
  capture "$SCRIPT" register --state-dir "$_ssc_sd" \
    --agente "x" --etapa "plan" \
    --contexto "Escolher linguagem e runtime do backend do projeto" \
    --opcoes '["bloqueio-humano-linguagem-runtime","manter-atual"]' \
    --escolha "bloqueio-humano-linguagem-runtime" \
    --justificativa "Sem consenso sobre linguagem, precisa de decisao humana" \
    --score 0 --classe estrutural --eixo "$_ssc_eixo"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "seed: register pausa" "$_CAPTURED_STDERR"; return 1; }
  capture "$BL" register --state-dir "$_ssc_sd" --decisao-id dec-001 \
    --pergunta "Qual linguagem/runtime devemos usar no backend?" \
    --contexto-para-resposta "Ver opcoes tecnicas avaliadas no plan.md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "seed: bloqueio register" "$_CAPTURED_STDERR"; return 1; }
  capture "$BL" respond --state-dir "$_ssc_sd" --block-id block-001 --resposta "Decidido: Go 1.22"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "seed: bloqueio respond" "$_CAPTURED_STDERR"; return 1; }
  _patch_human_block_subject_key_json "$_ssc_sd" block-001 "axis:$_ssc_eixo" \
    || { _fail "seed: patch subject_key" ""; return 1; }
}

scenario_sdhg_r6_consentimento_valido_libera_escolha_concreta() {
  _sd="$TMPDIR_TEST/sdhg-r6-ok"
  _sdhg_seed_consent_json "$_sd" linguagem-runtime || return 1
  capture "$SCRIPT" register --state-dir "$_sd" \
    --agente "operador" --etapa "plan" \
    --contexto "Registrar a decisao final de linguagem/runtime" \
    --opcoes '["Go 1.22","Node 22"]' --escolha "Go 1.22" \
    --justificativa "Bloqueio humano respondido autoriza esta escolha" \
    --score 2 --classe estrutural --eixo linguagem-runtime --consentimento block-001
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "R6 valido" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "dec-002" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.decisions[1] | [.choice, .decision_class, .structural_axis, .human_consent_block_id, (.justification_score|tostring)] | join("|")'
  [ "$_CAPTURED_STDOUT" = "Go 1.22|estrutural|linguagem-runtime|block-001|2" ] \
    || { _fail "campos persistidos" "obtido '$_CAPTURED_STDOUT'"; return 1; }
}

scenario_sdhg_r6_consentimento_inexistente_falha() {
  _sd="$TMPDIR_TEST/sdhg-r6-inexistente"
  _sdhg_seed_consent_json "$_sd" linguagem-runtime || return 1
  capture "$SCRIPT" register --state-dir "$_sd" \
    --agente "operador" --etapa "plan" \
    --contexto "Registrar a decisao final de linguagem/runtime" \
    --opcoes '["Go 1.22","Node 22"]' --escolha "Go 1.22" \
    --justificativa "Tentando citar um bloqueio que nao existe" \
    --score 2 --classe estrutural --eixo linguagem-runtime --consentimento block-999
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "R6 inexistente" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "consentimento-invalido" || return 1
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "1" || return 1
}

scenario_sdhg_r6_consentimento_aguardando_falha() {
  _sd="$TMPDIR_TEST/sdhg-r6-aguardando"
  _init_state "$_sd"
  capture "$SCRIPT" register --state-dir "$_sd" \
    --agente "x" --etapa "plan" \
    --contexto "Escolher linguagem e runtime do backend do projeto" \
    --opcoes '["bloqueio-humano-linguagem-runtime"]' \
    --escolha "bloqueio-humano-linguagem-runtime" \
    --justificativa "Sem consenso sobre linguagem, precisa de decisao humana" \
    --score 0 --classe estrutural --eixo linguagem-runtime
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "seed register" "$_CAPTURED_STDERR"; return 1; }
  capture "$BL" register --state-dir "$_sd" --decisao-id dec-001 \
    --pergunta "Qual linguagem/runtime devemos usar no backend?" \
    --contexto-para-resposta "Ver opcoes tecnicas avaliadas no plan.md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "seed bloqueio" "$_CAPTURED_STDERR"; return 1; }
  # Nao responde — permanece 'aguardando'.
  capture "$SCRIPT" register --state-dir "$_sd" \
    --agente "operador" --etapa "plan" \
    --contexto "Registrar a decisao final de linguagem/runtime" \
    --opcoes '["Go 1.22","Node 22"]' --escolha "Go 1.22" \
    --justificativa "Tentando usar consentimento ainda pendente" \
    --score 2 --classe estrutural --eixo linguagem-runtime --consentimento block-001
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "R6 aguardando" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "consentimento-invalido" || return 1
}

scenario_sdhg_r6_consentimento_outro_assunto_falha() {
  _sd="$TMPDIR_TEST/sdhg-r6-outro-assunto"
  _sdhg_seed_consent_json "$_sd" persistencia || return 1
  capture "$SCRIPT" register --state-dir "$_sd" \
    --agente "operador" --etapa "plan" \
    --contexto "Registrar a decisao final de linguagem/runtime" \
    --opcoes '["Go 1.22","Node 22"]' --escolha "Go 1.22" \
    --justificativa "Consentimento e de outro eixo (persistencia), nao linguagem" \
    --score 2 --classe estrutural --eixo linguagem-runtime --consentimento block-001
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "R6 outro assunto" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "consentimento-de-outro-assunto" || return 1
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "1" || return 1
}

scenario_sdhg_inv_c5_agente_nao_participa_da_regra() {
  _sd_a="$TMPDIR_TEST/sdhg-invc5-a"
  _sd_b="$TMPDIR_TEST/sdhg-invc5-b"
  _init_state "$_sd_a"
  _init_state "$_sd_b"
  capture "$SCRIPT" register --state-dir "$_sd_a" \
    --agente "agente-00c-orchestrator" --etapa "plan" \
    --contexto "Escolher linguagem e runtime do backend do projeto" \
    --opcoes '["bloqueio-humano-linguagem-runtime"]' \
    --escolha "bloqueio-humano-linguagem-runtime" \
    --justificativa "Sem consenso sobre linguagem, precisa de decisao humana" \
    --score 0 --classe estrutural --eixo "cor-do-logo"
  _exit_a="$_CAPTURED_EXIT"; _err_a="$_CAPTURED_STDERR"
  capture "$SCRIPT" register --state-dir "$_sd_b" \
    --agente "operador" --etapa "plan" \
    --contexto "Escolher linguagem e runtime do backend do projeto" \
    --opcoes '["bloqueio-humano-linguagem-runtime"]' \
    --escolha "bloqueio-humano-linguagem-runtime" \
    --justificativa "Sem consenso sobre linguagem, precisa de decisao humana" \
    --score 0 --classe estrutural --eixo "cor-do-logo"
  _exit_b="$_CAPTURED_EXIT"; _err_b="$_CAPTURED_STDERR"
  [ "$_exit_a" = "$_exit_b" ] || { _fail "INV-C5 exit diverge" "a=$_exit_a b=$_exit_b"; return 1; }
  [ "$_err_a" = "$_err_b" ] || { _fail "INV-C5 mensagem diverge" "a='$_err_a' b='$_err_b'"; return 1; }
}

scenario_sdhg_inv_c1_sem_classe_comportamento_identico() {
  # Ausencia de --classe e byte-a-byte o comportamento atual — mesmo quando
  # a Decisao teria sido estrutural (nenhum caminho novo dispara sem a flag,
  # exceto R1, que exige a flag so quando --opcoes contem o token de
  # bloqueio humano — nao e o caso aqui).
  _sd="$TMPDIR_TEST/sdhg-invc1"
  _init_state "$_sd"
  capture "$SCRIPT" register --state-dir "$_sd" \
    --agente "x" --etapa "plan" \
    --contexto "Escolher linguagem e runtime do backend do projeto" \
    --opcoes '["Go 1.22","Node 22"]' --escolha "Go 1.22" \
    --justificativa "Decisao sem classe declarada, comportamento legado" \
    --score 2
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sem --classe deveria passar" "$_CAPTURED_STDERR"; return 1; }
  capture "$RW" get --state-dir "$_sd" --field '.decisions[0].decision_class'
  [ "$_CAPTURED_STDOUT" = "null" ] || { _fail "decision_class deveria ser null" "obtido $_CAPTURED_STDOUT"; return 1; }
}

if command -v sqlite3 >/dev/null 2>&1; then

# _patch_human_block_subject_key_sqlite DIR BLOCK_ID SUBJECT -> fixture
# helper equivalente ao patch JSON, para o backend SQLite.
_patch_human_block_subject_key_sqlite() {
  sqlite3 "$1/state.db" \
    "UPDATE human_block SET subject_key='$3' WHERE id='$2';"
}

_sdhg_seed_consent_sqlite() {
  _ssc_sd="$1"; _ssc_eixo="${2:-linguagem-runtime}"
  _seed_sqlite_backend "$_ssc_sd" || return 1
  capture "$SCRIPT" register --state-dir "$_ssc_sd" \
    --agente "x" --etapa "plan" \
    --contexto "Escolher linguagem e runtime do backend do projeto" \
    --opcoes '["bloqueio-humano-linguagem-runtime","manter-atual"]' \
    --escolha "bloqueio-humano-linguagem-runtime" \
    --justificativa "Sem consenso sobre linguagem, precisa de decisao humana" \
    --score 0 --classe estrutural --eixo "$_ssc_eixo"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "seed sqlite: register pausa" "$_CAPTURED_STDERR"; return 1; }
  capture "$BL" register --state-dir "$_ssc_sd" --decisao-id dec-001 \
    --pergunta "Qual linguagem/runtime devemos usar no backend?" \
    --contexto-para-resposta "Ver opcoes tecnicas avaliadas no plan.md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "seed sqlite: bloqueio register" "$_CAPTURED_STDERR"; return 1; }
  capture "$BL" respond --state-dir "$_ssc_sd" --block-id block-001 --resposta "Decidido: Go 1.22"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "seed sqlite: bloqueio respond" "$_CAPTURED_STDERR"; return 1; }
  _patch_human_block_subject_key_sqlite "$_ssc_sd" block-001 "axis:$_ssc_eixo"
}

scenario_sdhg_sqlite_r1_opcoes_bloqueio_sem_classe_falha() {
  _sd="$TMPDIR_TEST/sdhg-sqlite-r1"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" register --state-dir "$_sd" \
    --agente "x" --etapa "plan" \
    --contexto "Escolher linguagem e runtime do backend do projeto" \
    --opcoes '["bloqueio-humano-linguagem-runtime"]' \
    --escolha "bloqueio-humano-linguagem-runtime" \
    --justificativa "Sem consenso sobre linguagem, precisa de decisao humana" \
    --score 0
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "sqlite R1" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "classe-obrigatoria" || return 1
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "0" || return 1
}

scenario_sdhg_sqlite_r3_eixo_invalido_falha() {
  _sd="$TMPDIR_TEST/sdhg-sqlite-r3"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" register --state-dir "$_sd" \
    --agente "x" --etapa "plan" \
    --contexto "Escolher linguagem e runtime do backend do projeto" \
    --opcoes '["bloqueio-humano-linguagem-runtime"]' \
    --escolha "bloqueio-humano-linguagem-runtime" \
    --justificativa "Sem consenso sobre linguagem, precisa de decisao humana" \
    --score 0 --classe estrutural --eixo "cor-do-logo"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "sqlite R3" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "eixo-invalido" || return 1
}

scenario_sdhg_sqlite_r2_estrutural_sem_consentimento_falha() {
  _sd="$TMPDIR_TEST/sdhg-sqlite-r2"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" register --state-dir "$_sd" \
    --agente "x" --etapa "plan" \
    --contexto "Decidir a linguagem/runtime sozinho, sem gate" \
    --opcoes '["Go 1.22","Node 22"]' --escolha "Go 1.22" \
    --justificativa "Acho que Go e melhor pra esse caso de uso" \
    --score 0 --classe estrutural --eixo linguagem-runtime
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "sqlite R2" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "estrutural-exige-bloqueio" || return 1
}

# Task 2.2.3: SELECT direto confirma as 3 colunas novas persistidas.
scenario_sdhg_sqlite_2_2_3_colunas_novas_persistidas() {
  _sd="$TMPDIR_TEST/sdhg-sqlite-cols"
  _sdhg_seed_consent_sqlite "$_sd" linguagem-runtime || return 1
  capture "$SCRIPT" register --state-dir "$_sd" \
    --agente "operador" --etapa "plan" \
    --contexto "Registrar a decisao final de linguagem/runtime" \
    --opcoes '["Go 1.22","Node 22"]' --escolha "Go 1.22" \
    --justificativa "Bloqueio humano respondido autoriza esta escolha" \
    --score 2 --classe estrutural --eixo linguagem-runtime --consentimento block-001
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sqlite R6 valido" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "dec-002" || return 1
  _row=$(sqlite3 "$_sd/state.db" \
    "SELECT decision_class||'|'||structural_axis||'|'||human_consent_block_id FROM decision WHERE id='dec-002';")
  [ "$_row" = "estrutural|linguagem-runtime|block-001" ] \
    || { _fail "colunas novas" "obtido '$_row'"; return 1; }
}

scenario_sdhg_sqlite_r6_consentimento_outro_assunto_falha() {
  _sd="$TMPDIR_TEST/sdhg-sqlite-r6-outro"
  _sdhg_seed_consent_sqlite "$_sd" persistencia || return 1
  capture "$SCRIPT" register --state-dir "$_sd" \
    --agente "operador" --etapa "plan" \
    --contexto "Registrar a decisao final de linguagem/runtime" \
    --opcoes '["Go 1.22","Node 22"]' --escolha "Go 1.22" \
    --justificativa "Consentimento e de outro eixo (persistencia), nao linguagem" \
    --score 2 --classe estrutural --eixo linguagem-runtime --consentimento block-001
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "sqlite R6 outro assunto" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "consentimento-de-outro-assunto" || return 1
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "1" || return 1
}

fi # sqlite3 disponivel

run_all_scenarios
