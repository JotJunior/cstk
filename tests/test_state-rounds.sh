#!/bin/sh
# test_state-rounds.sh — cobre plugins/cstk/skills/agente-00c-runtime/scripts/state-rounds.sh
#
# Ref: docs/specs/feature-reopen/contracts/state-rounds.md
#      docs/specs/feature-reopen/tasks.md FASE 2, task 2.5 (T-01..T-16)

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/state-rounds.sh"
RW="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/state-rw.sh"
LOCK="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/state-lock.sh"

if ! command -v jq >/dev/null 2>&1; then
  printf '# test_state-rounds.sh: jq ausente — pulando suite\n'
  exit 0
fi

# ---------------------------------------------------------------------------
# _mk_state_dir SD BACKEND STATUS -> cria SD via state-rw.sh init sob um HOME
# isolado (config state_backend=BACKEND explicita — NUNCA depende do config
# global da maquina, mesmo padrao de _mk_populated_sqlite_sd em
# tests/test_state-parity-sweep.sh), depois ajusta .execution.status se
# diferente do default (em_andamento). Retorno: 0 sucesso, 1 falha de fixture.
# ---------------------------------------------------------------------------
_mk_state_dir() {
  _msd_sd="$1"
  _msd_backend="$2"
  _msd_status="$3"
  _msd_home="$TMPDIR_TEST/home-$(basename "$_msd_sd")"
  mkdir -p "$_msd_home/.claude/cstk" || return 1
  printf 'state_backend=%s\n' "$_msd_backend" > "$_msd_home/.claude/cstk/config"
  env HOME="$_msd_home" "$RW" init --state-dir "$_msd_sd" \
    --execucao-id "exec-test" --projeto-alvo-path "/tmp/proj-test" \
    --descricao "descricao de teste com tamanho suficiente para passar a validacao minima" \
    --key-aspects '["a","b","c"]' >/dev/null 2>&1 || return 1
  if [ "$_msd_backend" = "sqlite" ]; then
    [ -f "$_msd_sd/state.db" ] || return 1
  else
    [ -f "$_msd_sd/state.json" ] || return 1
  fi
  if [ "$_msd_status" != "em_andamento" ]; then
    # Sob backend sqlite ha CHECK constraint: status terminal exige
    # finished_at no MESMO lote (set multi-campo atomico) — ver CLAUDE.md
    # §state-db-runtime-parity. Passa os dois pares tambem sob json (efeito
    # identico, so mais explicito).
    "$RW" set --state-dir "$_msd_sd" \
      --field '.execution.status' --value "\"$_msd_status\"" \
      --field '.execution.finished_at' --value '"2026-01-01T00:00:00Z"' \
      >/dev/null 2>&1 || return 1
  fi
  return 0
}

# _acquire_lock SD -> G6 exige lock detido antes de rotate real (nao-dry-run).
_acquire_lock() {
  "$LOCK" acquire --state-dir "$1" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# T-01 — rotate sobre state-dir sem estado ⇒ exit 3, disco intacto
# ---------------------------------------------------------------------------
scenario_T01_sem_estado_exit3_disco_intacto() {
  _sd="$TMPDIR_TEST/t01-sd"
  capture "$SCRIPT" rotate --state-dir "_sd_never_created_$_sd"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "T-01" "esperado exit=3, obtido $_CAPTURED_EXIT"; return 1; }
  [ ! -e "$_sd" ] || { _fail "T-01" "state-dir foi criado como efeito colateral"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# T-02 — rotate com status em_andamento ⇒ exit 3, estado vivo intocado
# ---------------------------------------------------------------------------
scenario_T02_em_andamento_exit3_estado_intocado() {
  _sd="$TMPDIR_TEST/t02-sd"
  _mk_state_dir "$_sd" json em_andamento || { _error "fixture" "_mk_state_dir falhou"; return 2; }
  _before=$(cat "$_sd/state.json")
  capture "$SCRIPT" rotate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "T-02" "esperado exit=3, obtido $_CAPTURED_EXIT"; return 1; }
  _after=$(cat "$_sd/state.json")
  [ "$_before" = "$_after" ] || { _fail "T-02" "state.json mudou apos rotate recusado"; return 1; }
  [ ! -d "$_sd/rounds" ] || { _fail "T-02" "rounds/ foi criado apesar da recusa"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# T-03 — rotate com status abortada ⇒ exit 0 (terminal legitimo)
# ---------------------------------------------------------------------------
scenario_T03_abortada_exit0_terminal_legitimo() {
  _sd="$TMPDIR_TEST/t03-sd"
  _mk_state_dir "$_sd" json abortada || { _error "fixture" "_mk_state_dir falhou"; return 2; }
  _acquire_lock "$_sd" || { _error "fixture" "acquire lock falhou"; return 2; }
  capture "$SCRIPT" rotate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "T-03" "esperado exit=0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  assert_stdout_match '^ROUND\|r01\|json\|state\.json\|' || return 1
  [ -f "$_sd/rounds/r01/state.json" ] || { _fail "T-03" "round r01/state.json ausente"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# T-04 — round preservado byte a byte identico ao estado pre-rotacao (cmp),
# backend json
# ---------------------------------------------------------------------------
scenario_T04_round_identico_backend_json() {
  _sd="$TMPDIR_TEST/t04-sd"
  _mk_state_dir "$_sd" json concluida || { _error "fixture" "_mk_state_dir falhou"; return 2; }
  _acquire_lock "$_sd" || { _error "fixture" "acquire lock falhou"; return 2; }
  cp "$_sd/state.json" "$TMPDIR_TEST/t04-snapshot.json"
  cp "$_sd/state.json.sha256" "$TMPDIR_TEST/t04-snapshot.sha256" 2>/dev/null || :
  capture "$SCRIPT" rotate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "T-04" "rotate falhou: $_CAPTURED_STDERR"; return 1; }
  cmp -s "$TMPDIR_TEST/t04-snapshot.json" "$_sd/rounds/r01/state.json" \
    || { _fail "T-04" "round diverge byte a byte do estado pre-rotacao"; return 1; }
  if [ -f "$TMPDIR_TEST/t04-snapshot.sha256" ]; then
    cmp -s "$TMPDIR_TEST/t04-snapshot.sha256" "$_sd/rounds/r01/state.json.sha256" \
      || { _fail "T-04" "sha256 do round diverge do pre-rotacao"; return 1; }
  fi
  return 0
}

# ---------------------------------------------------------------------------
# T-05 — idem backend sqlite, apos checkpoint
# ---------------------------------------------------------------------------
scenario_T05_round_identico_backend_sqlite_apos_checkpoint() {
  command -v sqlite3 >/dev/null 2>&1 || { printf '# T-05: sqlite3 ausente — pulando\n'; return 0; }
  _sd="$TMPDIR_TEST/t05-sd"
  _mk_state_dir "$_sd" sqlite concluida || { _error "fixture" "_mk_state_dir falhou"; return 2; }
  _acquire_lock "$_sd" || { _error "fixture" "acquire lock falhou"; return 2; }
  # checkpoint manual identico ao que rotate fara -- bytes canonicos de referencia
  sqlite3 "$_sd/state.db" "PRAGMA wal_checkpoint(TRUNCATE);" >/dev/null 2>&1
  cp "$_sd/state.db" "$TMPDIR_TEST/t05-snapshot.db"
  capture "$SCRIPT" rotate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "T-05" "rotate falhou: $_CAPTURED_STDERR"; return 1; }
  cmp -s "$TMPDIR_TEST/t05-snapshot.db" "$_sd/rounds/r01/state.db" \
    || { _fail "T-05" "round sqlite diverge byte a byte do checkpoint de referencia"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# T-06 — apos rotate sqlite, rounds/<l>/ contem SO state.db (nenhum -wal/-shm)
# ---------------------------------------------------------------------------
scenario_T06_round_sqlite_sem_sidecars() {
  command -v sqlite3 >/dev/null 2>&1 || { printf '# T-06: sqlite3 ausente — pulando\n'; return 0; }
  _sd="$TMPDIR_TEST/t06-sd"
  _mk_state_dir "$_sd" sqlite abortada || { _error "fixture" "_mk_state_dir falhou"; return 2; }
  _acquire_lock "$_sd" || { _error "fixture" "acquire lock falhou"; return 2; }
  capture "$SCRIPT" rotate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "T-06" "rotate falhou: $_CAPTURED_STDERR"; return 1; }
  [ -f "$_sd/rounds/r01/state.db" ] || { _fail "T-06" "state.db ausente no round"; return 1; }
  [ ! -e "$_sd/rounds/r01/state.db-wal" ] || { _fail "T-06" "state.db-wal vazou para o round"; return 1; }
  [ ! -e "$_sd/rounds/r01/state.db-shm" ] || { _fail "T-06" "state.db-shm vazou para o round"; return 1; }
  _cnt=$(find "$_sd/rounds/r01" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')
  [ "$_cnt" = "1" ] || { _fail "T-06" "round contem $_cnt arquivos, esperado 1 (so state.db)"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# T-07 — rotate 2x ⇒ r01 e r02 coexistem; r01 inalterado
# ---------------------------------------------------------------------------
scenario_T07_rotate_2x_coexistem_r01_inalterado() {
  _sd="$TMPDIR_TEST/t07-sd"
  _mk_state_dir "$_sd" json abortada || { _error "fixture" "_mk_state_dir falhou"; return 2; }
  _acquire_lock "$_sd" || { _error "fixture" "acquire lock falhou"; return 2; }
  capture "$SCRIPT" rotate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "T-07" "1a rotate falhou: $_CAPTURED_STDERR"; return 1; }
  cp "$_sd/rounds/r01/state.json" "$TMPDIR_TEST/t07-r01-snapshot.json"
  # Nova execucao terminal na raiz (lock ja detido, permanece detido).
  _mk_state_dir "$_sd" json abortada || { _error "fixture" "2a _mk_state_dir falhou"; return 2; }
  capture "$SCRIPT" rotate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "T-07" "2a rotate falhou: $_CAPTURED_STDERR"; return 1; }
  assert_stdout_match '^ROUND\|r02\|' || return 1
  [ -d "$_sd/rounds/r01" ] || { _fail "T-07" "r01 desapareceu apos 2a rotacao"; return 1; }
  [ -d "$_sd/rounds/r02" ] || { _fail "T-07" "r02 nao foi criado"; return 1; }
  cmp -s "$TMPDIR_TEST/t07-r01-snapshot.json" "$_sd/rounds/r01/state.json" \
    || { _fail "T-07" "r01 foi alterado pela 2a rotacao"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# T-08 — interrupcao apos staging (staging completo, journal presente,
# target ainda nao criado) ⇒ recover roll-forward, 1 tentativa
# ---------------------------------------------------------------------------
scenario_T08_recover_roll_forward_staging_completo() {
  _sd="$TMPDIR_TEST/t08-sd"
  mkdir -p "$_sd/rounds/.r01.staging"
  # arquivos "ja movidos" para staging (raiz ficou vazia de estado, como
  # aconteceria apos o passo f do sequenciamento do contrato).
  printf '{"execution":{"id":"exec-t08","status":"abortada"}}' > "$_sd/rounds/.r01.staging/state.json"
  {
    printf 'label=r01\n'
    printf 'backend=json\n'
    printf 'files=state.json\n'
    printf 'staging=rounds/.r01.staging\n'
    printf 'phase=moving\n'
    printf 'started_at=2026-01-01T00:00:00Z\n'
  } > "$_sd/rounds/.rotate-journal"
  capture "$SCRIPT" recover --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "T-08" "recover falhou: $_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "RECOVER|forward|r01" || return 1
  [ -f "$_sd/rounds/r01/state.json" ] || { _fail "T-08" "roll-forward nao commitou o round" ; return 1; }
  [ ! -e "$_sd/rounds/.r01.staging" ] || { _fail "T-08" "staging remanescente apos roll-forward"; return 1; }
  [ ! -f "$_sd/rounds/.rotate-journal" ] || { _fail "T-08" "journal remanescente apos roll-forward"; return 1; }
  # 1 tentativa -- idempotente, segunda chamada e no-op (sem journal).
  capture "$SCRIPT" recover --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "T-08" "segunda recover (idempotente) falhou"; return 1; }
  assert_stdout_contains "RECOVER|none|-" || return 1
  return 0
}

# ---------------------------------------------------------------------------
# T-09 — interrupcao no meio dos mv (staging incompleto) ⇒ recover roll-back,
# state-dir volta ao original
# ---------------------------------------------------------------------------
scenario_T09_recover_roll_back_staging_incompleto() {
  _sd="$TMPDIR_TEST/t09-sd"
  mkdir -p "$_sd/rounds/.r01.staging"
  # Simula interrupcao ENTRE mover state.json (ja em staging) e mover
  # state.json.sha256 (ainda na raiz) -- staging incompleto.
  printf '{"execution":{"id":"exec-t09","status":"abortada"}}' > "$_sd/rounds/.r01.staging/state.json"
  printf 'sha256-fake-content\n' > "$_sd/state.json.sha256"
  {
    printf 'label=r01\n'
    printf 'backend=json\n'
    printf 'files=state.json,state.json.sha256\n'
    printf 'staging=rounds/.r01.staging\n'
    printf 'phase=moving\n'
    printf 'started_at=2026-01-01T00:00:00Z\n'
  } > "$_sd/rounds/.rotate-journal"
  capture "$SCRIPT" recover --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "T-09" "recover falhou: $_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "RECOVER|rollback|r01" || return 1
  [ -f "$_sd/state.json" ] || { _fail "T-09" "state.json nao voltou para a raiz"; return 1; }
  [ -f "$_sd/state.json.sha256" ] || { _fail "T-09" "state.json.sha256 nao permaneceu na raiz"; return 1; }
  [ ! -e "$_sd/rounds/.r01.staging" ] || { _fail "T-09" "staging remanescente apos roll-back"; return 1; }
  [ ! -f "$_sd/rounds/.rotate-journal" ] || { _fail "T-09" "journal remanescente apos roll-back"; return 1; }
  [ ! -d "$_sd/rounds/r01" ] || { _fail "T-09" "round r01 foi criado indevidamente no roll-back"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# T-10 — recover sem journal ⇒ no-op exit 0 (idempotente)
# ---------------------------------------------------------------------------
scenario_T10_recover_sem_journal_noop() {
  _sd="$TMPDIR_TEST/t10-sd"
  _mk_state_dir "$_sd" json em_andamento || { _error "fixture" "_mk_state_dir falhou"; return 2; }
  capture "$SCRIPT" recover --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "T-10" "esperado exit=0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "RECOVER|none|-" || return 1
  [ -f "$_sd/state.json" ] || { _fail "T-10" "state.json na raiz foi afetado"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# T-11 — rotate com journal pendente ⇒ exit 3, nao inicia segunda rotacao
# ---------------------------------------------------------------------------
scenario_T11_rotate_com_journal_pendente_exit3() {
  _sd="$TMPDIR_TEST/t11-sd"
  _mk_state_dir "$_sd" json abortada || { _error "fixture" "_mk_state_dir falhou"; return 2; }
  _acquire_lock "$_sd" || { _error "fixture" "acquire lock falhou"; return 2; }
  mkdir -p "$_sd/rounds"
  printf 'label=r99\nbackend=json\nfiles=state.json\nstaging=rounds/.r99.staging\nphase=staged\nstarted_at=2026-01-01T00:00:00Z\n' \
    > "$_sd/rounds/.rotate-journal"
  capture "$SCRIPT" rotate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "T-11" "esperado exit=3, obtido $_CAPTURED_EXIT"; return 1; }
  [ ! -d "$_sd/rounds/r99" ] || { _fail "T-11" "rotacao nova foi iniciada apesar do journal pendente"; return 1; }
  [ -f "$_sd/rounds/.rotate-journal" ] || { _fail "T-11" "journal pendente foi removido indevidamente"; return 1; }
  [ -f "$_sd/state.json" ] || { _fail "T-11" "estado da raiz foi movido apesar da recusa"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# T-12 — --dry-run nao cria journal/staging nem move arquivo
# ---------------------------------------------------------------------------
scenario_T12_dry_run_sem_efeitos_colaterais() {
  _sd="$TMPDIR_TEST/t12-sd"
  _mk_state_dir "$_sd" json concluida || { _error "fixture" "_mk_state_dir falhou"; return 2; }
  _acquire_lock "$_sd" || { _error "fixture" "acquire lock falhou"; return 2; }
  capture "$SCRIPT" rotate --state-dir "$_sd" --dry-run
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "T-12" "dry-run falhou: $_CAPTURED_STDERR"; return 1; }
  assert_stdout_match '^ROUND\|r01\|json\|state\.json\|' || return 1
  [ ! -e "$_sd/rounds" ] || { _fail "T-12" "rounds/ foi criado por dry-run"; return 1; }
  [ -f "$_sd/state.json" ] || { _fail "T-12" "state.json foi movido por dry-run"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# T-13 — integrity_check != ok ⇒ exit 1 sem mover nada
# ---------------------------------------------------------------------------
scenario_T13_integrity_check_falho_exit1_nada_movido() {
  command -v sqlite3 >/dev/null 2>&1 || { printf '# T-13: sqlite3 ausente — pulando\n'; return 0; }
  _sd="$TMPDIR_TEST/t13-sd"
  _mk_state_dir "$_sd" sqlite abortada || { _error "fixture" "_mk_state_dir falhou"; return 2; }
  _acquire_lock "$_sd" || { _error "fixture" "acquire lock falhou"; return 2; }
  _sz=$(wc -c < "$_sd/state.db" | tr -d ' ')
  _newsz=$((_sz * 6 / 10))
  dd if="$_sd/state.db" of="$TMPDIR_TEST/t13-trunc.db" bs=1 count="$_newsz" 2>/dev/null
  mv "$TMPDIR_TEST/t13-trunc.db" "$_sd/state.db"
  capture "$SCRIPT" rotate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "T-13" "esperado exit=1, obtido $_CAPTURED_EXIT"; return 1; }
  [ ! -e "$_sd/rounds" ] || { _fail "T-13" "rounds/ foi criado apesar do integrity_check falho"; return 1; }
  [ -f "$_sd/state.db" ] || { _fail "T-13" "state.db (corrompido) foi movido/removido"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# T-14 — next-label com r01..r09 ⇒ r10; ordenacao lexicografica preservada
# ---------------------------------------------------------------------------
scenario_T14_next_label_r09_para_r10() {
  _sd="$TMPDIR_TEST/t14-sd"
  mkdir -p "$_sd/rounds"
  for _n in 01 02 03 04 05 06 07 08 09; do
    mkdir -p "$_sd/rounds/r$_n"
  done
  capture "$SCRIPT" next-label --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "T-14" "next-label falhou: $_CAPTURED_STDERR"; return 1; }
  [ "$_CAPTURED_STDOUT" = "r10" ] || { _fail "T-14" "esperado r10, obtido '$_CAPTURED_STDOUT'"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# T-15 — artefatos nao-transacionais permanecem na raiz apos rotate
# ---------------------------------------------------------------------------
scenario_T15_artefatos_nao_transacionais_permanecem() {
  _sd="$TMPDIR_TEST/t15-sd"
  _mk_state_dir "$_sd" json abortada || { _error "fixture" "_mk_state_dir falhou"; return 2; }
  _acquire_lock "$_sd" || { _error "fixture" "acquire lock falhou"; return 2; }
  printf 'linha de log\n' > "$_sd/enforcement-log.jsonl"
  printf 'commit-baseline\n' > "$_sd/commit-baseline.txt"
  mkdir -p "$_sd/backups"
  printf '{}' > "$_sd/backups/wave-001.json"
  capture "$SCRIPT" rotate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "T-15" "rotate falhou: $_CAPTURED_STDERR"; return 1; }
  [ -f "$_sd/enforcement-log.jsonl" ] || { _fail "T-15" "enforcement-log.jsonl foi movido"; return 1; }
  [ -f "$_sd/commit-baseline.txt" ] || { _fail "T-15" "commit-baseline.txt foi movido"; return 1; }
  [ -f "$_sd/backups/wave-001.json" ] || { _fail "T-15" "backups/ foi movido"; return 1; }
  [ -d "$_sd/state-history" ] || { _fail "T-15" "state-history/ foi movido"; return 1; }
  [ -d "$_sd/.lock" ] || { _fail "T-15" ".lock/ foi movido"; return 1; }
  [ ! -f "$_sd/rounds/r01/enforcement-log.jsonl" ] || { _fail "T-15" "enforcement-log.jsonl vazou para o round"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# T-16 — shellcheck -s sh sem erro; ausencia de bashismo
# ---------------------------------------------------------------------------
scenario_T16_shellcheck_limpo() {
  command -v shellcheck >/dev/null 2>&1 || { printf '# T-16: shellcheck ausente — pulando\n'; return 0; }
  capture shellcheck -s sh "$SCRIPT"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "T-16" "shellcheck reportou erro: $_CAPTURED_STDOUT"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# Bonus (nao-T, cobertura de uso) — flags obrigatorias/desconhecidas ⇒ exit 2
# ---------------------------------------------------------------------------
scenario_bonus_uso_incorreto_exit2() {
  capture "$SCRIPT" rotate
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "uso" "rotate sem --state-dir: esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
  capture "$SCRIPT" bogus-subcommand --state-dir "$TMPDIR_TEST/x"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "uso" "subcomando desconhecido: esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
  capture "$SCRIPT" next-label --state-dir "$TMPDIR_TEST/x" --flag-fantasma
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "uso" "flag desconhecida: esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# Bonus (nao-T) — list: sem rounds/ ⇒ stdout vazio exit 0
# ---------------------------------------------------------------------------
scenario_bonus_list_sem_rounds_stdout_vazio() {
  _sd="$TMPDIR_TEST/bonus-list-sd"
  mkdir -p "$_sd"
  capture "$SCRIPT" list --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "list" "esperado exit=0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "list" "stdout deveria ser vazio, obtido: $_CAPTURED_STDOUT"; return 1; }
  return 0
}

run_all_scenarios
