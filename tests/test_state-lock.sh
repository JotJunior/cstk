#!/bin/sh
# test_state-lock.sh — cobre plugins/cstk/skills/agente-00c-runtime/scripts/state-lock.sh.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/state-lock.sh"
RW="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/state-rw.sh"

if ! command -v jq >/dev/null 2>&1; then
  printf '# test_state-lock.sh: jq ausente — pulando suite\n'
  exit 0
fi

scenario_acquire_release_basico() {
  _sd="$TMPDIR_TEST/state"
  capture "$SCRIPT" acquire --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "acquire" "$_CAPTURED_EXIT; $_CAPTURED_STDERR"
    return 1
  fi
  [ -d "$_sd/.lock" ] || { _fail ".lock dir ausente apos acquire" ""; return 1; }
  capture "$SCRIPT" release --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "release" "$_CAPTURED_EXIT"
    return 1
  fi
  [ -d "$_sd/.lock" ] && { _fail ".lock dir presente apos release" ""; return 1; }
  return 0
}

scenario_acquire_semeia_gitignore_no_state_dir() {
  # acquire roda ANTES do state-rw init no fluxo do command pai e pode criar
  # o state-dir: deve semear .gitignore "*" desde o primeiro toque (paridade
  # com _sr_ensure_state_dir). Lock release (rmdir .lock) segue intacto.
  _sd="$TMPDIR_TEST/state-gi"
  capture "$SCRIPT" acquire --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "acquire" "$_CAPTURED_STDERR"; return 1; }
  [ -f "$_sd/.gitignore" ] || { _fail ".gitignore ausente" "acquire criou state-dir sem .gitignore"; return 1; }
  _gi=$(cat "$_sd/.gitignore")
  [ "$_gi" = "*" ] || { _fail ".gitignore conteudo" "esperado '*', obtido '$_gi'"; return 1; }
  capture "$SCRIPT" release --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "release" "$_CAPTURED_EXIT"; return 1; }
  return 0
}

scenario_acquire_duplicado_exit_3() {
  _sd="$TMPDIR_TEST/state"
  capture "$SCRIPT" acquire --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "acquire 1" ""; return 1; }
  capture "$SCRIPT" acquire --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 3 ]; then
    _fail "acquire duplicado exit" "esperado 3, obtido $_CAPTURED_EXIT"
    return 1
  fi
  # Mensagem legada permanece byte-a-byte identica (SC-006, openspec-hygiene).
  assert_stderr_contains "lock ja detido" || return 1
  # Envelope diagnostico aditivo (openspec-hygiene FR-012/FR-015).
  assert_stderr_contains "DIAG|error|lock-contention|" || return 1
}

scenario_release_idempotente() {
  _sd="$TMPDIR_TEST/state"
  mkdir -p "$_sd"
  capture "$SCRIPT" release --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "release sem lock" "esperado 0 (idempotente), obtido $_CAPTURED_EXIT"
    return 1
  fi
  capture "$SCRIPT" release --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "release 2" ""; return 1; }
}

scenario_check_livre_exit_0() {
  _sd="$TMPDIR_TEST/state"
  mkdir -p "$_sd"
  capture "$SCRIPT" check --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "check livre" "$_CAPTURED_EXIT"; return 1; }
}

scenario_check_detido_exit_3() {
  _sd="$TMPDIR_TEST/state"
  capture "$SCRIPT" acquire --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "acquire" ""; return 1; }
  capture "$SCRIPT" check --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 3 ]; then
    _fail "check detido" "esperado 3, obtido $_CAPTURED_EXIT"
    return 1
  fi
  # Mensagem legada permanece byte-a-byte identica (SC-006, openspec-hygiene).
  assert_stderr_contains "lock detido" || return 1
  # Envelope diagnostico aditivo (openspec-hygiene FR-012/FR-015).
  assert_stderr_contains "DIAG|error|lock-contention|" || return 1
}

scenario_locks_independentes_por_state_dir() {
  # Permite invocacoes simultaneas em projetos distintos (2.5.3)
  _sd1="$TMPDIR_TEST/state1"
  _sd2="$TMPDIR_TEST/state2"
  capture "$SCRIPT" acquire --state-dir "$_sd1"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "acquire 1" ""; return 1; }
  capture "$SCRIPT" acquire --state-dir "$_sd2"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "acquire em outro state-dir" "esperado 0 (independente), obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_check_execution_busy_state_ausente_passa() {
  _sd="$TMPDIR_TEST/state"
  mkdir -p "$_sd"
  capture "$SCRIPT" check-execution-busy --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "busy sem state" "esperado 0, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_check_execution_busy_em_andamento_exit_3() {
  _sd="$TMPDIR_TEST/state"
  capture "$RW" init --state-dir "$_sd" --execucao-id "exec-1" \
    --projeto-alvo-path "/tmp/p" --descricao "POC teste"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "init" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" check-execution-busy --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 3 ]; then
    _fail "busy em_andamento" "esperado 3, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "/agente-00c-resume" || return 1
  assert_stderr_contains "/agente-00c-abort" || return 1
}

scenario_check_execution_busy_terminal_passa() {
  _sd="$TMPDIR_TEST/state"
  capture "$RW" init --state-dir "$_sd" --execucao-id "exec-1" \
    --projeto-alvo-path "/tmp/p" --descricao "POC teste"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "init" ""; return 1; }
  # Marca como concluida + terminada_em
  capture "$RW" set --state-dir "$_sd" --field '.execucao.status' --value '"concluida"'
  capture "$RW" set --state-dir "$_sd" --field '.execucao.terminada_em' --value '"2026-05-05T15:00:00Z"'
  capture "$SCRIPT" check-execution-busy --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "busy terminal" "esperado 0, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_check_execution_busy_json_caminho_inalterado() {
  # 2.5.3 (FR-004): sob backend JSON o comportamento e identico ao legado —
  # exit 3 e mensagem apontando o proprio state.json (nunca tmp materializado).
  _sd="$TMPDIR_TEST/state-json-path"
  capture "$RW" init --state-dir "$_sd" --execucao-id "exec-1" \
    --projeto-alvo-path "/tmp/p" --descricao "POC teste"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "init" "$_CAPTURED_STDERR"; return 1; }
  [ -f "$_sd/state.json" ] || { _fail "fixture json" "harness deveria ter backend json (HOME sandbox)"; return 1; }
  capture "$SCRIPT" check-execution-busy --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "busy json" "esperado 3, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "$_sd/state.json" || return 1
}

# --- Cenarios sqlite (state-db-runtime-parity FASE 2 lote 2.5) ------------
# Fixture: init sob config global state_backend=sqlite em HOME proprio
# (padrao test_retro.sh). Requer sqlite3 >= piso do state-db-foundation.

_sqlite3_adequate() {
  command -v sqlite3 >/dev/null 2>&1 || return 1
  _v=$(sqlite3 --version 2>/dev/null | cut -d' ' -f1) || return 1
  [ -n "$_v" ]
}

_init_sqlite() {
  _is_home="$TMPDIR_TEST/home-sqlite"
  mkdir -p "$_is_home/.claude/cstk"
  printf 'state_backend=sqlite\n' > "$_is_home/.claude/cstk/config"
  env HOME="$_is_home" "$RW" init --state-dir "$1" \
    --execucao-id "x-sqlite" --projeto-alvo-path "/tmp/p" \
    --descricao "POC lock sqlite" >/dev/null 2>&1 || return 1
  [ -f "$1/state.db" ] || return 1
}

scenario_sqlite_busy_em_andamento_exit_3() {
  # FR-010: sob state.db com execucao ativa, busy NAO pode degradar para
  # exit 0 (comportamento pre-porte). Mensagem aponta o state.db real.
  _sqlite3_adequate || { printf "# skip: sqlite3 indisponivel\n"; return 0; }
  _sd="$TMPDIR_TEST/state-sqlite"
  _init_sqlite "$_sd" || { _fail "fixture sqlite" "init nao gerou state.db"; return 1; }
  capture "$SCRIPT" check-execution-busy --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "busy sqlite em_andamento" "esperado 3, obtido $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains "/agente-00c-resume" || return 1
  assert_stderr_contains "$_sd/state.db" || return 1
}

scenario_sqlite_busy_terminal_passa() {
  _sqlite3_adequate || { printf "# skip: sqlite3 indisponivel\n"; return 0; }
  _sd="$TMPDIR_TEST/state-sqlite-term"
  _init_sqlite "$_sd" || { _fail "fixture sqlite" "init nao gerou state.db"; return 1; }
  # Status terminal direto no schema (CHECK exige finished_at junto — o set
  # multi-campo atomico e escopo da FASE 3; fixture manipula via sqlite3,
  # padrao test_state-db-schema.sh).
  capture sqlite3 "$_sd/state.db" \
    "UPDATE execution SET status='concluida', finished_at='2026-08-03T00:00:00Z';"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "fixture UPDATE" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" check-execution-busy --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "busy sqlite terminal" "esperado 0, obtido $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
}

scenario_sqlite_busy_anti_mirror_state_dir_intacto() {
  # FR-003: a materializacao NUNCA cria arquivo dentro do state-dir (nem
  # state.json espelho, nem tmp).
  _sqlite3_adequate || { printf "# skip: sqlite3 indisponivel\n"; return 0; }
  _sd="$TMPDIR_TEST/state-sqlite-mirror"
  _init_sqlite "$_sd" || { _fail "fixture sqlite" "init nao gerou state.db"; return 1; }
  _antes=$(ls -a "$_sd" | sort)
  capture "$SCRIPT" check-execution-busy --state-dir "$_sd"
  _depois=$(ls -a "$_sd" | sort)
  [ "$_antes" = "$_depois" ] || { _fail "anti-mirror" "conteudo do state-dir mudou: antes[$_antes] depois[$_depois]"; return 1; }
  [ ! -f "$_sd/state.json" ] || { _fail "anti-mirror" "state.json espelho criado no state-dir"; return 1; }
}

scenario_help_exit_zero() {
  capture "$SCRIPT" --help
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "help exit" "$_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "state-lock.sh" || return 1
}

scenario_subcomando_invalido_exit_2() {
  capture "$SCRIPT" frobnicate --state-dir "$TMPDIR_TEST/x"
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "subcmd invalido" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

# --- FR-007a (dec-059): owner-PID no lock + acquire --force ---

scenario_acquire_grava_owner_pid_timestamp() {
  # 4.1.bis.1: acquire grava .lock/owner com pid= numerico + acquired_at=.
  _sd="$TMPDIR_TEST/owner-basic"
  capture "$SCRIPT" acquire --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "acquire" "$_CAPTURED_STDERR"; return 1; }
  [ -f "$_sd/.lock/owner" ] || { _fail "arquivo owner ausente" ""; return 1; }
  _pid=$(sed -n 's/^pid=\([0-9][0-9]*\)$/\1/p' "$_sd/.lock/owner")
  [ -n "$_pid" ] || { _fail "linha pid= invalida" "$(cat "$_sd/.lock/owner")"; return 1; }
  grep -q '^acquired_at=....-..-..T' "$_sd/.lock/owner" \
    || { _fail "linha acquired_at ausente" "$(cat "$_sd/.lock/owner")"; return 1; }
  capture "$SCRIPT" release --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "release com owner dentro" "$_CAPTURED_EXIT"; return 1; }
  [ -d "$_sd/.lock" ] && { _fail ".lock presente apos release" ""; return 1; }
  return 0
}

scenario_acquire_owner_pid_override() {
  # --owner-pid sobrepoe o PPID default gravado no owner.
  _sd="$TMPDIR_TEST/owner-override"
  capture "$SCRIPT" acquire --state-dir "$_sd" --owner-pid 99999
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "acquire --owner-pid" "$_CAPTURED_STDERR"; return 1; }
  grep -q '^pid=99999$' "$_sd/.lock/owner" \
    || { _fail "owner nao respeitou --owner-pid" "$(cat "$_sd/.lock/owner")"; return 1; }
  # --owner-pid nao-numerico = uso incorreto (exit 2)
  capture "$SCRIPT" acquire --state-dir "$TMPDIR_TEST/owner-bad" --owner-pid abc
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "--owner-pid abc" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_check_reporta_dono() {
  # 4.1.bis.2: check em lock detido reporta pid + estado (vivo/morto) do dono.
  _sd="$TMPDIR_TEST/owner-check"
  capture "$SCRIPT" acquire --state-dir "$_sd" --owner-pid "$$"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "acquire" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" check --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "check detido" "esperado 3, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "dono do lock: pid=$$" || return 1
  assert_stderr_contains "(vivo)" || return 1
}

scenario_force_lock_ausente_identico_acquire() {
  # 4.2.1: --force com lock ausente = acquire normal (exit 0, owner gravado).
  _sd="$TMPDIR_TEST/force-free"
  capture "$SCRIPT" acquire --state-dir "$_sd" --force
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "force em lock livre" "$_CAPTURED_STDERR"; return 1; }
  [ -f "$_sd/.lock/owner" ] || { _fail "owner ausente" ""; return 1; }
  # Sem lock detido: NAO deve emitir lock-force-acquired.
  case "$_CAPTURED_STDERR" in
    *lock-force-acquired*) _fail "diag indevido em lock livre" "$_CAPTURED_STDERR"; return 1 ;;
  esac
  return 0
}

scenario_force_dono_morto_consuma_com_diag() {
  # 4.2.1b + 4.2.2: dono comprovadamente morto => force passa + diag com pids.
  _sd="$TMPDIR_TEST/force-dead"
  sh -c 'exit 0' &
  _dead=$!
  wait "$_dead" 2>/dev/null || :
  capture "$SCRIPT" acquire --state-dir "$_sd" --owner-pid "$_dead"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "acquire dono-morto" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" acquire --state-dir "$_sd" --force
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "force dono morto" "esperado 0, obtido $_CAPTURED_EXIT; $_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains "DIAG|warning|lock-force-acquired|" || return 1
  assert_stderr_contains "pid antigo=$_dead" || return 1
  [ -f "$_sd/.lock/owner" ] || { _fail "owner novo ausente pos-force" ""; return 1; }
}

scenario_force_dono_vivo_recusa_exit_3() {
  # 4.2.1a (dec-059): dono VIVO => force RECUSADO, lock e owner intactos.
  _sd="$TMPDIR_TEST/force-alive"
  capture "$SCRIPT" acquire --state-dir "$_sd" --owner-pid "$$"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "acquire" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" acquire --state-dir "$_sd" --force
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "force dono vivo" "esperado 3, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "DIAG|error|lock-force-denied-owner-alive|" || return 1
  assert_stderr_contains "dono do lock esta VIVO (pid=$$" || return 1
  # NAO pode ter consumado nem trocado o dono.
  case "$_CAPTURED_STDERR" in
    *lock-force-acquired*) _fail "force consumou com dono vivo" "$_CAPTURED_STDERR"; return 1 ;;
  esac
  grep -q "^pid=$$\$" "$_sd/.lock/owner" \
    || { _fail "owner alterado apos recusa" "$(cat "$_sd/.lock/owner")"; return 1; }
}

scenario_force_lock_legado_sem_owner_aviso() {
  # 4.1.bis.3 + 4.2.1b: lock legado SEM owner = dono-desconhecido; force
  # consuma com aviso explicito + diag citando pid antigo=desconhecido.
  _sd="$TMPDIR_TEST/force-legacy"
  mkdir -p "$_sd/.lock"
  capture "$SCRIPT" acquire --state-dir "$_sd" --force
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "force legado" "esperado 0, obtido $_CAPTURED_EXIT; $_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains "lock legado sem arquivo owner (dono-desconhecido)" || return 1
  assert_stderr_contains "DIAG|warning|lock-force-acquired|" || return 1
  assert_stderr_contains "pid antigo=desconhecido" || return 1
  [ -f "$_sd/.lock/owner" ] || { _fail "owner novo ausente pos-force" ""; return 1; }
}

scenario_force_falha_remocao_exit_nao_zero() {
  # contract §2: falha de rmdir/mkdir => exit != 0 com diagnostico.
  _sd="$TMPDIR_TEST/force-rofail"
  mkdir -p "$_sd/.lock"
  chmod 555 "$_sd"
  capture "$SCRIPT" acquire --state-dir "$_sd" --force
  _got=$_CAPTURED_EXIT
  chmod 755 "$_sd"
  [ "$_got" != 0 ] || { _fail "force com FS read-only" "esperado exit != 0, obtido 0"; return 1; }
  assert_stderr_contains "DIAG|error|lock-force-remove-failed|" || return 1
}

scenario_force_flag_invalida_fora_do_acquire() {
  # --force/--owner-pid so valem para acquire; demais subcomandos = exit 2.
  _sd="$TMPDIR_TEST/force-usage"
  mkdir -p "$_sd"
  capture "$SCRIPT" release --state-dir "$_sd" --force
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "release --force" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
  capture "$SCRIPT" check --state-dir "$_sd" --owner-pid 123
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "check --owner-pid" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
  capture "$SCRIPT" release --state-dir "$_sd" --force-abandoned
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "release --force-abandoned" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
}

# --- Guarda de onda aberta no --force (issue #182) ------------------------
# O dono do lock e um shell EFEMERO do command pai: "pid morto" e o estado
# NORMAL enquanto o subagente orquestrador trabalha. Quem distingue pausa
# entre ondas de onda em voo e o estado, nao o pid.

# Prepara state-dir com lock detido por pid morto + state.json com uma onda
# no estado pedido ("aberta" | "fechada").
_mk_lock_com_onda() {
  _mlo_sd=$1
  _mlo_estado=$2
  mkdir -p "$_mlo_sd/.lock"
  printf 'pid=%s\nacquired_at=2026-08-29T20:39:13Z\n' "$_MLO_DEAD_PID" > "$_mlo_sd/.lock/owner"
  if [ "$_mlo_estado" = "aberta" ]; then
    printf '{"waves":[{"id":"onda-009","started_at":"2026-08-29T20:40:29Z","finished_at":null}]}\n' \
      > "$_mlo_sd/state.json"
  else
    printf '{"waves":[{"id":"onda-009","started_at":"2026-08-29T20:40:29Z","finished_at":"2026-08-29T21:00:00Z"}]}\n' \
      > "$_mlo_sd/state.json"
  fi
}

# PID comprovadamente morto, reaproveitado pelos cenarios abaixo.
_MLO_DEAD_PID=""
_mlo_dead_pid() {
  if [ -z "$_MLO_DEAD_PID" ]; then
    sh -c 'exit 0' &
    _MLO_DEAD_PID=$!
    wait "$_MLO_DEAD_PID" 2>/dev/null || :
  fi
}

scenario_force_onda_aberta_recusa_exit_3() {
  _mlo_dead_pid
  _sd="$TMPDIR_TEST/force-wave-open"
  _mk_lock_com_onda "$_sd" aberta
  capture "$SCRIPT" acquire --state-dir "$_sd" --force
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "force com onda aberta" "esperado 3, obtido $_CAPTURED_EXIT; $_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains "DIAG|error|lock-force-denied-wave-open|" || return 1
  assert_stderr_contains "onda-009" || return 1
  # NAO pode ter consumado: owner antigo intacto.
  case "$_CAPTURED_STDERR" in
    *lock-force-acquired*) _fail "force consumou com onda aberta" "$_CAPTURED_STDERR"; return 1 ;;
  esac
  grep -q "^pid=$_MLO_DEAD_PID\$" "$_sd/.lock/owner" \
    || { _fail "owner alterado apos recusa" "$(cat "$_sd/.lock/owner")"; return 1; }
}

scenario_force_onda_fechada_readquire() {
  # Lock orfao COM a ultima onda fechada e o caso normal entre ondas.
  _mlo_dead_pid
  _sd="$TMPDIR_TEST/force-wave-closed"
  _mk_lock_com_onda "$_sd" fechada
  capture "$SCRIPT" acquire --state-dir "$_sd" --force
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "force com onda fechada" "esperado 0, obtido $_CAPTURED_EXIT; $_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains "DIAG|warning|lock-force-acquired|" || return 1
}

scenario_force_abandoned_passa_por_cima_de_onda_aberta() {
  # Caminho do abort e da retomada deliberada de onda abandonada.
  _mlo_dead_pid
  _sd="$TMPDIR_TEST/force-wave-abandoned"
  _mk_lock_com_onda "$_sd" aberta
  capture "$SCRIPT" acquire --state-dir "$_sd" --force-abandoned
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "force-abandoned com onda aberta" "esperado 0, obtido $_CAPTURED_EXIT; $_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains "DIAG|warning|lock-force-abandoned-override|" || return 1
  assert_stderr_contains "DIAG|warning|lock-force-acquired|" || return 1
}

scenario_force_estado_ilegivel_recusa_fail_closed() {
  # Estado presente mas ilegivel: nao da para AFIRMAR que nao ha onda em
  # voo => recusa (nunca tratar "nao consegui ler" como "nao ha onda").
  _mlo_dead_pid
  _sd="$TMPDIR_TEST/force-state-broken"
  mkdir -p "$_sd/.lock"
  printf 'pid=%s\nacquired_at=2026-08-29T20:39:13Z\n' "$_MLO_DEAD_PID" > "$_sd/.lock/owner"
  printf '{"waves": [ISTO NAO E JSON\n' > "$_sd/state.json"
  capture "$SCRIPT" acquire --state-dir "$_sd" --force
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "force com estado ilegivel" "esperado 3, obtido $_CAPTURED_EXIT; $_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains "DIAG|error|lock-force-denied-state-unreadable|" || return 1
  # --force-abandoned continua sendo a saida explicita.
  capture "$SCRIPT" acquire --state-dir "$_sd" --force-abandoned
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "force-abandoned com estado ilegivel" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_sqlite_force_onda_aberta_recusa() {
  # Paridade de backend: a guarda le o estado via _state-read.sh, entao vale
  # igual sob state.db (nenhum leitor novo de state.json direto).
  _sqlite3_adequate || { printf "# skip: sqlite3 indisponivel\n"; return 0; }
  _mlo_dead_pid
  _sd="$TMPDIR_TEST/state-sqlite-force"
  _init_sqlite "$_sd" || { _fail "fixture sqlite" "init nao gerou state.db"; return 1; }
  _ondas="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/state-ondas.sh"
  capture "$_ondas" start --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "fixture onda sqlite" "$_CAPTURED_STDERR"; return 1; }
  mkdir -p "$_sd/.lock"
  printf 'pid=%s\nacquired_at=2026-08-29T20:39:13Z\n' "$_MLO_DEAD_PID" > "$_sd/.lock/owner"
  capture "$SCRIPT" acquire --state-dir "$_sd" --force
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "force sqlite onda aberta" "esperado 3, obtido $_CAPTURED_EXIT; $_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains "DIAG|error|lock-force-denied-wave-open|" || return 1
  # A materializacao nao pode deixar espelho no state-dir (FR-003).
  [ ! -f "$_sd/state.json" ] || { _fail "anti-mirror" "state.json espelho criado no state-dir"; return 1; }
}

run_all_scenarios
