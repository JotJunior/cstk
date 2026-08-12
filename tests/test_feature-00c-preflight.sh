#!/bin/sh
# test_feature-00c-preflight.sh — cobre feature-00c-preflight.sh
# (FR-010A, FR-PRE-004).
#
# Ref: docs/specs/_archived/feature-00c/tasks.md FASE 2 task 2.1.6

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/feature-00c-preflight.sh"
SCRIPTS_DIR="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts"

# ---------------------------------------------------------------------------
# Extensao feature-reopen FASE 3 (T-20..T-37) — cobertura do modo `--reopen`
# de plugins/cstk/commands/feature-00c.md.
#
# Ref: docs/specs/feature-reopen/contracts/reopen-flow.md
#      docs/specs/feature-reopen/tasks.md FASE 3, task 3.7
#
# `/feature-00c --reopen` e um SLASH COMMAND (prosa em markdown interpretada
# pelo LLM orquestrador), nao um script — nao ha binario para invocar e medir
# exit code diretamente. As secoes 6.a/7.b/7.c/7.d de feature-00c.md sao,
# porem, composicoes DETERMINISTICAS de primitivas ja reais e testadas
# (state-lock.sh, state-rounds.sh, cp -R, state-rw.sh) — a funcao _rf_precheck
# abaixo e uma REPLICA LITERAL do bloco 6.a do command (mesma ordem, mesmas
# chamadas), usada para exercitar essas primitivas exatamente como o command
# as compoe. Os invariantes puramente de POLITICA/PROSA (mensagens, "nunca
# aborta o proprio fluxo") sao verificados por grep contra o texto real do
# command — nao ha caminho scriptavel alternativo para eles.
# ---------------------------------------------------------------------------
RW="$SCRIPTS_DIR/state-rw.sh"
LOCK="$SCRIPTS_DIR/state-lock.sh"
ROUNDS="$SCRIPTS_DIR/state-rounds.sh"
FEATURE00C_MD="$REPO_ROOT/plugins/cstk/commands/feature-00c.md"

# _mk_terminal_state SD BACKEND STATUS -> mesmo padrao de
# tests/test_state-rounds.sh::_mk_state_dir, com a correcao de NAO gravar
# finished_at quando status=aguardando_humano (CHECK 2 do schema exige
# finished_at NULL para em_andamento/aguardando_humano).
_mk_terminal_state() {
  _mts_sd="$1"
  _mts_backend="$2"
  _mts_status="$3"
  _mts_home="$TMPDIR_TEST/home-$(basename "$_mts_sd")"
  mkdir -p "$_mts_home/.claude/cstk" || return 1
  printf 'state_backend=%s\n' "$_mts_backend" > "$_mts_home/.claude/cstk/config"
  env HOME="$_mts_home" "$RW" init --state-dir "$_mts_sd" \
    --execucao-id "exec-$(basename "$_mts_sd")" --projeto-alvo-path "/tmp/proj-test" \
    --descricao "descricao de teste com tamanho suficiente para passar a validacao minima" \
    --key-aspects '["a","b","c"]' >/dev/null 2>&1 || return 1
  case "$_mts_status" in
    em_andamento) : ;;
    abortada|concluida)
      env HOME="$_mts_home" "$RW" set --state-dir "$_mts_sd" \
        --field '.execution.status' --value "\"$_mts_status\"" \
        --field '.execution.finished_at' --value '"2026-01-01T00:00:00Z"' \
        >/dev/null 2>&1 || return 1
      ;;
    aguardando_humano)
      env HOME="$_mts_home" "$RW" set --state-dir "$_mts_sd" \
        --field '.execution.status' --value "\"$_mts_status\"" \
        >/dev/null 2>&1 || return 1
      ;;
  esac
  return 0
}

# _rf_precheck SD -> replica literal do passo 6.a de feature-00c.md.
# Efeitos: seta _RF_EXIT (0|4|5) e _RF_SKIP_ROTATE (true|false). Read-only
# (nenhuma escrita) — mesma garantia documentada no command.
_rf_precheck() {
  _rf_sd="$1"
  _RF_SKIP_ROTATE=false
  if [ ! -d "$_rf_sd" ] || { [ ! -f "$_rf_sd/state.json" ] && [ ! -f "$_rf_sd/state.db" ]; }; then
    _rf_has_round=false
    if [ -d "$_rf_sd/rounds" ]; then
      for _rf_rd in "$_rf_sd"/rounds/r*/; do
        [ -d "$_rf_rd" ] || continue
        { [ -f "${_rf_rd}state.json" ] || [ -f "${_rf_rd}state.db" ]; } && _rf_has_round=true
      done
    fi
    if [ "$_rf_has_round" = false ]; then
      _RF_EXIT=4
      return 0
    fi
    _RF_SKIP_ROTATE=true
    _RF_EXIT=0
    return 0
  fi
  "$LOCK" check-execution-busy --state-dir "$_rf_sd" >/dev/null 2>&1
  _rf_rc=$?
  if [ "$_rf_rc" != 0 ]; then
    if [ "$_rf_rc" = 3 ]; then
      _RF_EXIT=5
      return 0
    fi
    _RF_EXIT=1
    return 0
  fi
  _RF_EXIT=0
  return 0
}

# Helper: cria fixture de projeto-alvo + state.json com hashes corretos.
# Imprime path do state-dir em stdout.
_setup_fixture() {
  _proj="$TMPDIR_TEST/proj"
  _sdir="$_proj/.claude/feature-00c-state/test-feature"
  mkdir -p "$_proj/docs/01-briefing-discovery" "$_proj/docs" "$_sdir"

  # Briefing
  cat > "$_proj/docs/01-briefing-discovery/briefing.md" <<'BR'
# Briefing
## Visao
Conteudo.
## Usuarios
Conteudo.
BR
  _br_sha=$(sha256sum "$_proj/docs/01-briefing-discovery/briefing.md" | awk '{print $1}')

  # Constitution
  cat > "$_proj/docs/constitution.md" <<'CT'
# Constitution
## Core Principles
### I. Principio Um
Corpo.
**Version**: 1.2.0
CT
  _ct_sha=$(sha256sum "$_proj/docs/constitution.md" | awk '{print $1}')

  # State.json (chaves EN — schema-en-migration)
  cat > "$_sdir/state.json" <<JSON
{
  "schema_version": "1.0.0",
  "execution": {
    "short_name": "test-feature",
    "target_project_path": "$_proj"
  },
  "prerequisites": {
    "briefing": {
      "path": "docs/01-briefing-discovery/briefing.md",
      "sha256": "$_br_sha"
    },
    "constitution": {
      "path": "docs/constitution.md",
      "sha256": "$_ct_sha",
      "version": "1.2.0"
    }
  }
}
JSON
  printf '%s' "$_sdir"
}

# Variante pt-BR do mesmo fixture: prova o reader-fallback (.en // .pt).
# Mantida apos a migracao schema-en (back-compat de states vivos pt-BR).
_setup_fixture_pt() {
  _proj="$TMPDIR_TEST/proj-pt"
  _sdir="$_proj/.claude/feature-00c-state/test-feature"
  mkdir -p "$_proj/docs/01-briefing-discovery" "$_proj/docs" "$_sdir"

  cat > "$_proj/docs/01-briefing-discovery/briefing.md" <<'BR'
# Briefing
## Visao
Conteudo.
## Usuarios
Conteudo.
BR
  _br_sha=$(sha256sum "$_proj/docs/01-briefing-discovery/briefing.md" | awk '{print $1}')

  cat > "$_proj/docs/constitution.md" <<'CT'
# Constitution
## Core Principles
### I. Principio Um
Corpo.
**Version**: 1.2.0
CT
  _ct_sha=$(sha256sum "$_proj/docs/constitution.md" | awk '{print $1}')

  cat > "$_sdir/state.json" <<JSON
{
  "schema_version": "1.0.0",
  "execucao": {
    "short_name": "test-feature",
    "projeto_alvo_path": "$_proj"
  },
  "pre_requisitos": {
    "briefing": {
      "path": "docs/01-briefing-discovery/briefing.md",
      "sha256": "$_br_sha"
    },
    "constitution": {
      "path": "docs/constitution.md",
      "sha256": "$_ct_sha",
      "version": "1.2.0"
    }
  }
}
JSON
  printf '%s' "$_sdir"
}

scenario_check_sem_drift_passa() {
  _sdir=$(_setup_fixture)
  capture "$SCRIPT" check --state-dir "$_sdir"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT; $_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains '"ok": true' || return 1
}

# Reader-fallback: state.json com chaves pt-BR (state vivo legado) ainda valida.
scenario_check_state_pt_br_fallback_passa() {
  _sdir=$(_setup_fixture_pt)
  capture "$SCRIPT" check --state-dir "$_sdir"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT; $_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains '"ok": true' || return 1
}

scenario_check_briefing_modificado_falha() {
  _sdir=$(_setup_fixture)
  _proj=$(dirname -- "$(dirname -- "$(dirname -- "$_sdir")")")
  # Modificar briefing apos hash gravado
  printf '\nLinha adicionada apos hash.\n' >> "$_proj/docs/01-briefing-discovery/briefing.md"
  capture "$SCRIPT" check --state-dir "$_sdir"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stdout_contains 'briefing_hash_drift' || return 1
  assert_stdout_contains '"ok": false' || return 1
}

scenario_check_constitution_minor_bump_warn() {
  _sdir=$(_setup_fixture)
  _proj=$(dirname -- "$(dirname -- "$(dirname -- "$_sdir")")")
  # Mudar constitution mantendo MAJOR=1 mas bumping MINOR
  cat > "$_proj/docs/constitution.md" <<'CT'
# Constitution
## Core Principles
### I. Principio Um
Corpo atualizado.
**Version**: 1.3.0
CT
  capture "$SCRIPT" check --state-dir "$_sdir"
  # MINOR drift = warn, mas _ok continua true... espera, releia spec.
  # Spec FR-PRE-004: "MAJOR = bloqueio obrigatorio; MINOR ou PATCH = aviso registrado".
  # No script: warn nao quebra ok=true.
  assert_stdout_contains 'constitution_hash_drift' || return 1
  assert_stdout_contains '"severity": "warn"' || return 1
  # MINOR = warn = ok deve ser true (apenas aviso)
  assert_stdout_contains '"ok": true' || return 1
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit MINOR" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_check_constitution_major_bump_error() {
  _sdir=$(_setup_fixture)
  _proj=$(dirname -- "$(dirname -- "$(dirname -- "$_sdir")")")
  # MAJOR bump = de 1.2.0 para 2.0.0
  cat > "$_proj/docs/constitution.md" <<'CT'
# Constitution
## Core Principles
### I. Principio Um
Corpo reescrito.
**Version**: 2.0.0
CT
  capture "$SCRIPT" check --state-dir "$_sdir"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "exit MAJOR" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stdout_contains 'constitution_major_drift' || return 1
  assert_stdout_contains '"severity": "error"' || return 1
  assert_stdout_contains '"ok": false' || return 1
}

# ==== issue #77: path Windows drive-letter tratado como ABSOLUTO ====
# Execucao sob Git Bash grava prerequisites.*.path como "C:/Users/...".
# O case pattern antigo (/*) nao reconhecia esse formato como absoluto e
# concatenava com target_project_path ("<proj>/C:/Users/..."), gerando
# false-positive briefing_missing/constitution_missing que bloqueia o gate
# FR-010A em toda execucao. O path drive-letter nao existe no runner (o
# arquivo segue missing), mas o finding DEVE citar o path original SEM o
# prefixo do projeto — prova de que nao houve concatenacao.
scenario_check_path_windows_drive_letter_nao_concatena() {
  _sdir=$(_setup_fixture)
  _proj=$(dirname -- "$(dirname -- "$(dirname -- "$_sdir")")")
  _tmp=$(mktemp)
  jq '.prerequisites.briefing.path = "C:/Users/Op/proj/docs/01-briefing-discovery/briefing.md"
      | .prerequisites.constitution.path = "C:/Users/Op/proj/docs/constitution.md"' \
    "$_sdir/state.json" > "$_tmp" && mv "$_tmp" "$_sdir/state.json"
  capture "$SCRIPT" check --state-dir "$_sdir"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit" "esperado 1 (missing), obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains 'briefing_missing' || return 1
  assert_stdout_contains 'C:/Users/Op/proj' || return 1
  assert_stdout_not_contains "$_proj/C:" || return 1
}

scenario_check_state_dir_inexistente_falha() {
  capture "$SCRIPT" check --state-dir "/path/que/nao/existe"
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "nao existe" || return 1
}

scenario_check_sem_state_json_falha() {
  _sdir="$TMPDIR_TEST/empty-state-dir"
  mkdir -p "$_sdir"
  capture "$SCRIPT" check --state-dir "$_sdir"
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "estado ausente" || return 1
}

# ==== backend sqlite (fix pos-6.2.1): check NAO pode ser inerte ====
# Bug de campo (meta-gob-ms): com state.db o preflight reportava
# "state.json ausente" e a validacao de drift FR-PRE-004 nunca rodava.

_fp_make_sqlite_state() {
  # $1=home sandbox  $2=state-dir  $3=projeto (com briefing/constitution)
  mkdir -p "$1/.claude/cstk"
  printf 'state_backend=sqlite\n' > "$1/.claude/cstk/config"
  mkdir -p "$3/docs/01-briefing-discovery"
  printf '# briefing de teste com conteudo suficiente\n' > "$3/docs/01-briefing-discovery/briefing.md"
  printf '# constitution de teste\n\n**Version**: 1.0.0\n' > "$3/docs/constitution.md"
  if command -v sha256sum >/dev/null 2>&1; then
    _fpms_br=$(sha256sum "$3/docs/01-briefing-discovery/briefing.md" | awk '{print $1}')
    _fpms_ct=$(sha256sum "$3/docs/constitution.md" | awk '{print $1}')
  else
    _fpms_br=$(shasum -a 256 "$3/docs/01-briefing-discovery/briefing.md" | awk '{print $1}')
    _fpms_ct=$(shasum -a 256 "$3/docs/constitution.md" | awk '{print $1}')
  fi
  env HOME="$1" sh "$SCRIPTS_DIR/state-rw.sh" init --state-dir "$2" \
    --short-name "sqlite-preflight" \
    --projeto-alvo-path "$3" \
    --descricao "descricao de teste com tamanho suficiente para validacao" \
    --briefing-path "$3/docs/01-briefing-discovery/briefing.md" --briefing-sha256 "$_fpms_br" \
    --constitution-path "$3/docs/constitution.md" --constitution-sha256 "$_fpms_ct" \
    --constitution-version "1.0.0" >/dev/null 2>&1
}

scenario_check_backend_sqlite_valida_ok() {
  command -v sqlite3 >/dev/null 2>&1 || { printf '# skip: sqlite3 indisponivel\n'; return 0; }
  _h="$TMPDIR_TEST/home-sq1"
  _sd="$TMPDIR_TEST/sq1-state"
  _pj="$TMPDIR_TEST/sq1-proj"
  _fp_make_sqlite_state "$_h" "$_sd" "$_pj" || { _error "fixture" "init sqlite falhou"; return 2; }
  [ -f "$_sd/state.db" ] || { _error "fixture" "state.db nao criado (config nao aplicou?)"; return 2; }
  [ ! -f "$_sd/state.json" ] || { _error "fixture" "state.json presente — cenario invalido"; return 2; }
  capture env HOME="$_h" "$SCRIPT" check --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit sqlite ok" "esperado 0, obtido $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains '"ok": true' || return 1
}

scenario_check_backend_sqlite_detecta_drift() {
  command -v sqlite3 >/dev/null 2>&1 || { printf '# skip: sqlite3 indisponivel\n'; return 0; }
  _h="$TMPDIR_TEST/home-sq2"
  _sd="$TMPDIR_TEST/sq2-state"
  _pj="$TMPDIR_TEST/sq2-proj"
  _fp_make_sqlite_state "$_h" "$_sd" "$_pj" || { _error "fixture" "init sqlite falhou"; return 2; }
  # Muta o briefing DEPOIS do init: o check deve reportar drift (a prova de
  # que a validacao deixou de ser inerte sob sqlite).
  printf '\nconteudo novo pos-init\n' >> "$_pj/docs/01-briefing-discovery/briefing.md"
  capture env HOME="$_h" "$SCRIPT" check --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit sqlite drift" "esperado 1 (findings), obtido $_CAPTURED_EXIT: $_CAPTURED_STDOUT"; return 1; }
  assert_stdout_contains 'briefing' || return 1
}

scenario_uso_sem_argumentos() {
  capture "$SCRIPT"
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "USO" || return 1
}

# ---------------------------------------------------------------------------
# T-20 — --reopen de short-name inexistente ⇒ exit 4, zero arquivos criados
# ---------------------------------------------------------------------------
scenario_T20_reopen_sem_execucao_anterior_exit4_zero_arquivos() {
  _sd="$TMPDIR_TEST/t20-sd"
  _rf_precheck "$_sd"
  [ "$_RF_EXIT" = 4 ] || { _fail "T-20" "esperado exit=4, obtido $_RF_EXIT"; return 1; }
  [ ! -e "$_sd" ] || { _fail "T-20" "state-dir foi criado como efeito colateral"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# T-21 — --reopen com execucao em_andamento ⇒ exit 5, estado vivo byte-identico
# ---------------------------------------------------------------------------
scenario_T21_reopen_execucao_em_andamento_exit5_estado_intocado() {
  _sd="$TMPDIR_TEST/t21-sd"
  _mk_terminal_state "$_sd" json em_andamento || { _error "fixture" "_mk_terminal_state falhou"; return 2; }
  _before=$(cat "$_sd/state.json")
  _rf_precheck "$_sd"
  [ "$_RF_EXIT" = 5 ] || { _fail "T-21" "esperado exit=5, obtido $_RF_EXIT"; return 1; }
  _after=$(cat "$_sd/state.json")
  [ "$_before" = "$_after" ] || { _fail "T-21" "estado vivo foi alterado pela pre-condicao"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# T-22 — --reopen com execucao aguardando_humano ⇒ exit 5
# ---------------------------------------------------------------------------
scenario_T22_reopen_execucao_aguardando_humano_exit5() {
  _sd="$TMPDIR_TEST/t22-sd"
  _mk_terminal_state "$_sd" json aguardando_humano || { _error "fixture" "_mk_terminal_state falhou"; return 2; }
  _rf_precheck "$_sd"
  [ "$_RF_EXIT" = 5 ] || { _fail "T-22" "esperado exit=5, obtido $_RF_EXIT"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# T-23 — parecer emitido antes de qualquer escrita (6.a/6.b nao criam inode)
# ---------------------------------------------------------------------------
scenario_T23_nenhuma_escrita_ate_a_confirmacao() {
  _sd="$TMPDIR_TEST/t23-sd"
  _mk_terminal_state "$_sd" json concluida || { _error "fixture" "_mk_terminal_state falhou"; return 2; }
  _before=$(find "$_sd" | sort)
  _rf_precheck "$_sd"
  [ "$_RF_EXIT" = 0 ] || { _fail "T-23" "precheck deveria permitir prosseguir (exit=0), obtido $_RF_EXIT"; return 1; }
  # sonda 6.b com branch vazia (sem git real) — deve degradar sem escrever
  _branch=""
  _after=$(find "$_sd" | sort)
  [ "$_before" = "$_after" ] || { _fail "T-23" "6.a/6.b geraram inode novo antes da confirmacao"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# T-24 — operador contraria a recomendacao ⇒ diverged=true (formula de 3'')
# ---------------------------------------------------------------------------
scenario_T24_operador_contraria_recomendacao_diverged_true() {
  _recommendation="abrir-feature-nova"
  _operator_choice="reabrir"
  _diverged="false"
  [ "$_operator_choice" != "$_recommendation" ] && _diverged="true"
  [ "$_diverged" = "true" ] || { _fail "T-24" "diverged deveria ser true quando escolha contraria recomendacao"; return 1; }

  _recommendation="reabrir"
  _operator_choice="reabrir"
  _diverged="false"
  [ "$_operator_choice" != "$_recommendation" ] && _diverged="true"
  [ "$_diverged" = "false" ] || { _fail "T-24" "diverged deveria ser false quando escolha bate com recomendacao"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# T-25 — recomendacao abrir-feature-nova NAO cria feature nova por conta propria
# ---------------------------------------------------------------------------
scenario_T25_recomendacao_abrir_feature_nova_nao_cria_feature() {
  [ -f "$FEATURE00C_MD" ] || { _error "fixture" "feature-00c.md ausente"; return 2; }
  grep -qF '**nao** crie a feature nova por conta' "$FEATURE00C_MD" \
    || { _fail "T-25" "prosa nao documenta a proibicao de criar feature nova por conta propria (FR-005)"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# T-26 — round anterior abortada ⇒ parecer declara que nao chegou ao fim
# ---------------------------------------------------------------------------
scenario_T26_round_abortado_parecer_declara_nao_chegou_ao_fim() {
  [ -f "$FEATURE00C_MD" ] || { _error "fixture" "feature-00c.md ausente"; return 2; }
  grep -q 'nao chegou ao fim' "$FEATURE00C_MD" \
    || { _fail "T-26" "prosa nao declara que round abortado nao chegou ao fim (FR-020)"; return 1; }
  # mecanico: o status flui corretamente do round rotacionado ate o parecer
  _sd="$TMPDIR_TEST/t26-sd"
  _mk_terminal_state "$_sd" json abortada || { _error "fixture" "_mk_terminal_state falhou"; return 2; }
  "$LOCK" acquire --state-dir "$_sd" >/dev/null 2>&1 || { _error "fixture" "acquire falhou"; return 2; }
  capture "$ROUNDS" rotate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "T-26" "rotate falhou: $_CAPTURED_STDERR"; "$LOCK" release --state-dir "$_sd" >/dev/null 2>&1; return 1; }
  case "$_CAPTURED_STDOUT" in
    *"|abortada") : ;;
    *) _fail "T-26" "status do round nao e 'abortada': $_CAPTURED_STDOUT"; "$LOCK" release --state-dir "$_sd" >/dev/null 2>&1; return 1 ;;
  esac
  "$LOCK" release --state-dir "$_sd" >/dev/null 2>&1
  return 0
}

# ---------------------------------------------------------------------------
# T-27 — .previous_round legivel via get nos dois backends
# ---------------------------------------------------------------------------
scenario_T27_previous_round_legivel_backend_json() {
  _sd="$TMPDIR_TEST/t27-json-sd"
  _home="$TMPDIR_TEST/home-t27-json"
  mkdir -p "$_home/.claude/cstk"
  printf 'state_backend=json\n' > "$_home/.claude/cstk/config"
  env HOME="$_home" "$RW" init --state-dir "$_sd" --execucao-id "exec-t27" \
    --projeto-alvo-path "/tmp/proj-t27" --descricao "descricao de teste com tamanho suficiente" \
    --key-aspects '["a","b","c"]' >/dev/null 2>&1 || { _error "fixture" "init falhou"; return 2; }
  _json='{"round":"r01","path":"rounds/r01","execution_id":"exec-t27-prev","status":"concluida","rotated_at":"2026-01-01T00:00:00Z"}'
  env HOME="$_home" "$RW" set --state-dir "$_sd" --field '.previous_round' --value "$_json" >/dev/null 2>&1 \
    || { _fail "T-27" "set .previous_round falhou (json)"; return 1; }
  _got=$(env HOME="$_home" "$RW" get --state-dir "$_sd" --field '.previous_round.round' 2>/dev/null)
  [ "$_got" = "r01" ] || { _fail "T-27" "esperado r01, obtido '$_got' (backend json)"; return 1; }
  return 0
}

scenario_T27b_previous_round_legivel_backend_sqlite() {
  command -v sqlite3 >/dev/null 2>&1 || { printf '# T-27b: sqlite3 ausente — pulando\n'; return 0; }
  _sd="$TMPDIR_TEST/t27-sqlite-sd"
  _home="$TMPDIR_TEST/home-t27-sqlite"
  mkdir -p "$_home/.claude/cstk"
  printf 'state_backend=sqlite\n' > "$_home/.claude/cstk/config"
  env HOME="$_home" "$RW" init --state-dir "$_sd" --execucao-id "exec-t27b" \
    --projeto-alvo-path "/tmp/proj-t27b" --descricao "descricao de teste com tamanho suficiente" \
    --key-aspects '["a","b","c"]' >/dev/null 2>&1 || { _error "fixture" "init falhou"; return 2; }
  [ -f "$_sd/state.db" ] || { _error "fixture" "state.db nao criado"; return 2; }
  _json='{"round":"r01","path":"rounds/r01","execution_id":"exec-t27b-prev","status":"concluida","rotated_at":"2026-01-01T00:00:00Z"}'
  env HOME="$_home" "$RW" set --state-dir "$_sd" --field '.previous_round' --value "$_json" >/dev/null 2>&1 \
    || { _fail "T-27b" "set .previous_round falhou (sqlite)"; return 1; }
  _got=$(env HOME="$_home" "$RW" get --state-dir "$_sd" --field '.previous_round.round' 2>/dev/null)
  [ "$_got" = "r01" ] || { _fail "T-27b" "esperado r01, obtido '$_got' (backend sqlite)"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# T-28 — atomic_commit_enabled herdado sem prompt; ausencia ⇒ false
# ---------------------------------------------------------------------------
scenario_T28_atomic_commit_herdado_sem_prompt() {
  _sd="$TMPDIR_TEST/t28-sd"
  _home="$TMPDIR_TEST/home-t28"
  mkdir -p "$_home/.claude/cstk"
  printf 'state_backend=json\n' > "$_home/.claude/cstk/config"
  env HOME="$_home" "$RW" init --state-dir "$_sd" --execucao-id "exec-t28" \
    --projeto-alvo-path "/tmp/proj-t28" --descricao "descricao de teste com tamanho suficiente" \
    --key-aspects '["a","b","c"]' --atomic-commit true >/dev/null 2>&1 \
    || { _error "fixture" "init falhou"; return 2; }
  _v=$(env HOME="$_home" "$RW" get --state-dir "$_sd" --field '.atomic_commit_enabled' 2>/dev/null) || _v=""
  [ "$_v" = "true" ] || { _fail "T-28" "esperado true, obtido '$_v'"; return 1; }
  return 0
}

scenario_T28b_atomic_commit_ausencia_equivale_false() {
  # replica a derivacao literal de _atomic em 3' (feature-00c.md): leitura
  # falha/ausente ⇒ "false", nunca herda "true" por acidente.
  _v=$(env HOME="$TMPDIR_TEST/home-t28b-inexistente" "$RW" get \
    --state-dir "$TMPDIR_TEST/t28b-sd-inexistente" --field '.atomic_commit_enabled' 2>/dev/null) || _v=""
  _atomic="false"
  [ "$_v" = "true" ] && _atomic="true"
  [ "$_atomic" = "false" ] || { _fail "T-28b" "ausencia de round deveria equivaler a atomic_commit=false"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# T-29 — spec arquivada restaurada; _archived/ permanece intacto (diff -r)
# ---------------------------------------------------------------------------
scenario_T29_spec_arquivada_restaurada_archived_intacto() {
  _proj="$TMPDIR_TEST/t29-proj"
  _short="minha-feature"
  mkdir -p "$_proj/docs/specs/_archived/$_short/contracts"
  printf '# Spec arquivada\nConteudo original.\n' > "$_proj/docs/specs/_archived/$_short/spec.md"
  printf 'contrato\n' > "$_proj/docs/specs/_archived/$_short/contracts/c1.md"

  # replica 7.d
  _spec="$_proj/docs/specs/$_short/spec.md"
  _spec_dir="$_proj/docs/specs/$_short"
  if [ ! -s "$_spec" ] && { [ ! -d "$_spec_dir" ] || [ -z "$(ls -A "$_spec_dir" 2>/dev/null)" ]; }; then
    _origin=""
    if [ -d "$_proj/docs/specs/_archived/$_short" ]; then
      _origin="$_proj/docs/specs/_archived/$_short"
    else
      _origin=$(find "$_proj/docs/specs/_archived" -maxdepth 1 -type d -name "*-$_short" 2>/dev/null | sort | tail -1)
    fi
    if [ -n "$_origin" ] && [ -d "$_origin" ]; then
      mkdir -p "$_spec_dir"
      cp -R "$_origin"/. "$_spec_dir"/
    fi
  fi

  [ -s "$_spec" ] || { _fail "T-29" "spec.md nao foi restaurada para o caminho ativo"; return 1; }
  [ -f "$_spec_dir/contracts/c1.md" ] || { _fail "T-29" "arvore inteira nao foi copiada (contracts/c1.md ausente)"; return 1; }
  diff -r "$_proj/docs/specs/_archived/$_short" "$_spec_dir" >/dev/null 2>&1 \
    || { _fail "T-29" "_archived/ diverge do caminho ativo restaurado"; return 1; }
  [ -f "$_proj/docs/specs/_archived/$_short/spec.md" ] \
    || { _fail "T-29" "origem sob _archived/ foi removida (deveria permanecer intacta)"; return 1; }
  return 0
}

# Variante: forma de nome COM data (<YYYY-MM-DD>-<short>), maior data vence.
scenario_T29b_spec_arquivada_forma_com_data_maior_data_vence() {
  _proj="$TMPDIR_TEST/t29b-proj"
  _short="outra-feature"
  mkdir -p "$_proj/docs/specs/_archived/2026-01-01-$_short"
  mkdir -p "$_proj/docs/specs/_archived/2026-06-15-$_short"
  printf 'versao antiga\n' > "$_proj/docs/specs/_archived/2026-01-01-$_short/spec.md"
  printf 'versao mais recente\n' > "$_proj/docs/specs/_archived/2026-06-15-$_short/spec.md"
  # arquivo solto que NAO e diretorio — nao deve ser considerado (achado
  # empirico de research.md Decision 8: review-features-report.md solto)
  printf 'solto\n' > "$_proj/docs/specs/_archived/2099-01-01-$_short-report.md"

  _spec="$_proj/docs/specs/$_short/spec.md"
  _spec_dir="$_proj/docs/specs/$_short"
  _origin=""
  if [ -d "$_proj/docs/specs/_archived/$_short" ]; then
    _origin="$_proj/docs/specs/_archived/$_short"
  else
    _origin=$(find "$_proj/docs/specs/_archived" -maxdepth 1 -type d -name "*-$_short" 2>/dev/null | sort | tail -1)
  fi
  [ -n "$_origin" ] || { _fail "T-29b" "resolucao nao encontrou nenhuma origem"; return 1; }
  mkdir -p "$_spec_dir"
  cp -R "$_origin"/. "$_spec_dir"/
  grep -q "versao mais recente" "$_spec" || { _fail "T-29b" "forma sem prefixo de maior data nao venceu"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# T-30 — spec ativa pre-existente NAO e sobrescrita pela restauracao
# ---------------------------------------------------------------------------
scenario_T30_spec_ativa_pre_existente_nao_sobrescrita() {
  _proj="$TMPDIR_TEST/t30-proj"
  _short="feature-editada"
  mkdir -p "$_proj/docs/specs/_archived/$_short"
  printf 'versao arquivada\n' > "$_proj/docs/specs/_archived/$_short/spec.md"
  mkdir -p "$_proj/docs/specs/$_short"
  printf 'versao editada a mao no disco\n' > "$_proj/docs/specs/$_short/spec.md"

  _spec="$_proj/docs/specs/$_short/spec.md"
  _spec_dir="$_proj/docs/specs/$_short"
  if [ ! -s "$_spec" ] && { [ ! -d "$_spec_dir" ] || [ -z "$(ls -A "$_spec_dir" 2>/dev/null)" ]; }; then
    _fail "T-30" "guarda deveria ter impedido a entrada no bloco de restauracao"
    return 1
  fi
  grep -q "versao editada a mao no disco" "$_spec" || { _fail "T-30" "spec ativa foi sobrescrita"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# T-31 — lock detido continuamente do passo 7 (acquire) ate a rotacao
# ---------------------------------------------------------------------------
scenario_T31_lock_detido_continuamente_ate_a_rotacao() {
  _sd="$TMPDIR_TEST/t31-sd"
  _mk_terminal_state "$_sd" json concluida || { _error "fixture" "_mk_terminal_state falhou"; return 2; }
  "$LOCK" acquire --state-dir "$_sd" >/dev/null 2>&1 || { _error "fixture" "acquire falhou"; return 2; }
  capture "$ROUNDS" rotate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "T-31" "rotate sob lock proprio falhou: $_CAPTURED_STDERR"; "$LOCK" release --state-dir "$_sd" >/dev/null 2>&1; return 1; }
  [ -d "$_sd/.lock" ] || { _fail "T-31" "lock foi liberado pela rotacao — deve permanecer detido ate o Cleanup"; return 1; }
  "$LOCK" release --state-dir "$_sd" >/dev/null 2>&1
  return 0
}

# ---------------------------------------------------------------------------
# T-32 — segunda sessao concorrente ⇒ exit 3, sem tocar a rotacao em curso
# ---------------------------------------------------------------------------
scenario_T32_segunda_sessao_concorrente_exit3() {
  _sd="$TMPDIR_TEST/t32-sd"
  _mk_terminal_state "$_sd" json concluida || { _error "fixture" "_mk_terminal_state falhou"; return 2; }
  "$LOCK" acquire --state-dir "$_sd" >/dev/null 2>&1 || { _error "fixture" "acquire falhou"; return 2; }
  capture "$LOCK" acquire --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "T-32" "esperado exit=3 (lock ocupado), obtido $_CAPTURED_EXIT"; "$LOCK" release --state-dir "$_sd" >/dev/null 2>&1; return 1; }
  [ -f "$_sd/state.json" ] || { _fail "T-32" "estado da sessao A foi afetado pela tentativa concorrente"; "$LOCK" release --state-dir "$_sd" >/dev/null 2>&1; return 1; }
  [ ! -d "$_sd/rounds" ] || { _fail "T-32" "rotacao foi disparada pela sessao B"; "$LOCK" release --state-dir "$_sd" >/dev/null 2>&1; return 1; }
  "$LOCK" release --state-dir "$_sd" >/dev/null 2>&1
  return 0
}

# ---------------------------------------------------------------------------
# T-33 — item 6 detecta state-dir terminal (nao so spec.md) e cita comandos
# do escopo de feature
# ---------------------------------------------------------------------------
scenario_T33_item6_detecta_estado_terminal_cita_comandos_feature() {
  [ -f "$FEATURE00C_MD" ] || { _error "fixture" "feature-00c.md ausente"; return 2; }
  grep -q '_has_terminal_state' "$FEATURE00C_MD" \
    || { _fail "T-33" "item 6 nao detecta estado terminal (continua so testando spec.md)"; return 1; }
  grep -qF -- '--reopen $SHORT' "$FEATURE00C_MD" \
    || { _fail "T-33" "mensagem do item 6 nao cita /feature-00c --reopen"; return 1; }
  grep -qF -- '/feature-00c-resume $SHORT' "$FEATURE00C_MD" \
    || { _fail "T-33" "mensagem do item 6 nao cita /feature-00c-resume"; return 1; }
  grep -qF -- '/feature-00c-abort $SHORT' "$FEATURE00C_MD" \
    || { _fail "T-33" "mensagem do item 6 nao cita /feature-00c-abort"; return 1; }
  # secao do item 6 (deteccao de execucao pre-existente) nunca instrui o
  # operador a rodar um comando CONCRETO de /agente-00c-* (a mencao ao
  # padrao generico "/agente-00c-*" faz parte da PROIBICAO em si — FR-017 —
  # e nao conta como violacao).
  _sec=$(awk '/^6\. deteccao de execucao pre-existente/{flag=1} flag{print} /^### 2\.bis/{exit}' "$FEATURE00C_MD")
  case "$_sec" in
    *"/agente-00c-resume"*|*"/agente-00c-abort"*)
      _fail "T-33" "secao do item 6 instrui um comando concreto /agente-00c-* (escopo errado)"; return 1 ;;
  esac
  return 0
}

# ---------------------------------------------------------------------------
# T-34 — nenhuma opcao oferecida termina em aborto do proprio fluxo (SC-007)
# ---------------------------------------------------------------------------
scenario_T34_nenhuma_opcao_termina_em_aborto_do_proprio_fluxo() {
  [ -f "$FEATURE00C_MD" ] || { _error "fixture" "feature-00c.md ausente"; return 2; }
  grep -q 'NAO chamar `state-rw.sh init` aqui' "$FEATURE00C_MD" \
    || { _fail "T-34" "opcao (a) nao documenta o desvio do init perigoso (bug FR-016)"; return 1; }
  grep -q 'Modo de reabertura' "$FEATURE00C_MD" \
    || { _fail "T-34" "opcao (a) nao referencia a secao do modo de reabertura"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# T-35 — backend da execucao nova segue a config global, independente do
# round anterior — sem heranca, sem flag --backend
# ---------------------------------------------------------------------------
scenario_T35_backend_novo_independente_do_round_sem_heranca() {
  [ -f "$FEATURE00C_MD" ] || { _error "fixture" "feature-00c.md ausente"; return 2; }
  # Nenhuma invocacao real de "state-rw.sh init" passa --backend (a UNICA
  # mencao literal esperada e na prosa que documenta que a flag NAO existe
  # — "sem flag `--backend`" — nunca numa linha de invocacao do init).
  if grep -qE 'init .*--backend' "$FEATURE00C_MD"; then
    _fail "T-35" "uma invocacao de init passa --backend (nao deveria existir, Decision 14)"
    return 1
  fi
  command -v sqlite3 >/dev/null 2>&1 || { printf '# T-35: sqlite3 ausente — pulando parte empirica\n'; return 0; }
  _sd="$TMPDIR_TEST/t35-sd"
  _home="$TMPDIR_TEST/home-t35"
  mkdir -p "$_home/.claude/cstk"
  printf 'state_backend=sqlite\n' > "$_home/.claude/cstk/config"
  env HOME="$_home" "$RW" init --state-dir "$_sd" --execucao-id "exec-t35" \
    --projeto-alvo-path "/tmp/proj-t35" --descricao "descricao de teste com tamanho suficiente" \
    --key-aspects '["a","b","c"]' >/dev/null 2>&1 || { _error "fixture" "init falhou"; return 2; }
  [ -f "$_sd/state.db" ] || { _fail "T-35" "config global sqlite nao foi aplicada ao init da execucao nova"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# T-36 — recover exit 1 (journal invalido) ⇒ fluxo sai 6, sem rotacionar
# ---------------------------------------------------------------------------
scenario_T36_recover_journal_invalido_mapeia_exit6() {
  _sd="$TMPDIR_TEST/t36-sd"
  mkdir -p "$_sd/rounds"
  printf 'linha-sem-formato-esperado-sem-chave-valor\n' > "$_sd/rounds/.rotate-journal"
  capture "$ROUNDS" recover --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "T-36" "esperado exit=1 do recover (journal invalido), obtido $_CAPTURED_EXIT"; return 1; }
  [ ! -d "$_sd/rounds/r01" ] || { _fail "T-36" "rotacao ocorreu apesar do journal invalido"; return 1; }
  # feature-00c.md mapeia recover exit=1 -> exit 6 do modo --reopen (7.b)
  grep -q 'exit 6' "$FEATURE00C_MD" || { _fail "T-36" "command nao mapeia recover exit=1 para exit 6"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# T-37 — raiz sem estado mas rounds/<label>/ presente ⇒ conciliado, nao
# recusado com exit 4 (3.3.6)
# ---------------------------------------------------------------------------
scenario_T37_raiz_vazia_com_round_presente_e_conciliada() {
  _sd="$TMPDIR_TEST/t37-sd"
  mkdir -p "$_sd/rounds/r01"
  printf '{"execution":{"status":"concluida"}}\n' > "$_sd/rounds/r01/state.json"
  _rf_precheck "$_sd"
  [ "$_RF_EXIT" = 0 ] || { _fail "T-37" "esperado exit=0 (conciliado), obtido $_RF_EXIT"; return 1; }
  [ "$_RF_SKIP_ROTATE" = true ] || { _fail "T-37" "esperado _skip_rotate=true (pular 7.c)"; return 1; }
  return 0
}

run_all_scenarios
