#!/bin/sh
# test_00c-state-backend-contract.sh — smoke textual: trava de regressao de
# dois defeitos no TEXTO dos commands 00c (resume/abort), descobertos ao
# conduzir a pipeline da feature `feature-reopen` com state_backend=sqlite.
#
# Defeito 1 — semantica do lock INVERTIDA (so em feature-00c-resume.md):
#   o passo 1 mandava `if state-lock.sh check ...; then abortar`, mas o
#   script sai 0 quando o lock esta LIVRE e 3 quando esta DETIDO. Seguir o
#   texto abortava toda retomada com lock livre e prosseguia com lock
#   ocupado. O `check` tambem NAO distingue dono vivo de morto — quem
#   distingue e `acquire --force` (recusa se o dono estiver VIVO).
#
# Defeito 2 — exigencia de state.json (resume + os 2 aborts): sob backend
#   SQLite nao existe state.json, o estado e state.db. O texto recusava
#   com exit 6 (resume) / exit 1 (abort) toda execucao iniciada apos
#   `cstk state enable-sqlite` — checagem obsoleta desde a paridade de
#   runtime (state-db-runtime-parity, v6.3). O feature-00c.md inicial ja
#   aceitava os dois backends; resume e abort ficaram para tras.
#
# Natureza: assert TEXTUAL no .md (contrato consumido como prompt). NAO
# mapeia 1:1 a um .sh — interno em tests/run.sh::_is_internal_test
# (orphan-check), existence-guarded. Se a regra sumir do texto, o bug volta
# silenciosamente — por isso a presenca e travada aqui.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CMD_DIR="$REPO_ROOT/plugins/cstk/commands"
RES_FEAT="$CMD_DIR/feature-00c-resume.md"
ABORT_FEAT="$CMD_DIR/feature-00c-abort.md"
ABORT_AGENTE="$CMD_DIR/agente-00c-abort.md"

# ==== Defeito 2: os 3 commands aceitam state.db, nao so state.json ====

_assert_aceita_state_db() {
  [ -f "$1" ] || { _error "arquivo ausente" "$1"; return 2; }
  assert_exit 0 grep -Fq 'state.db' "$1" || return 1
}

scenario_resume_feature_aceita_state_db() { _assert_aceita_state_db "$RES_FEAT"; }
scenario_abort_feature_aceita_state_db()  { _assert_aceita_state_db "$ABORT_FEAT"; }
scenario_abort_agente_aceita_state_db()   { _assert_aceita_state_db "$ABORT_AGENTE"; }

# A forma exata importa: a checagem so e correta se a AUSENCIA de state.json
# for combinada com a ausencia de state.db (E logico), nunca sozinha.
scenario_resume_feature_checa_ambos_backends() {
  [ -f "$RES_FEAT" ] || { _error "arquivo ausente" "$RES_FEAT"; return 2; }
  assert_exit 0 grep -Fq '! -f "$AGENTE_00C_STATE_DIR/state.db"' "$RES_FEAT" || return 1
}

scenario_abort_feature_checa_ambos_backends() {
  [ -f "$ABORT_FEAT" ] || { _error "arquivo ausente" "$ABORT_FEAT"; return 2; }
  assert_exit 0 grep -Fq '! -f "$AGENTE_00C_STATE_DIR/state.db"' "$ABORT_FEAT" || return 1
}

# ==== Defeito 1: semantica do lock no resume da feature ====

# O idioma invertido `if state-lock.sh check ...; then` NAO pode reaparecer.
scenario_resume_sem_idioma_de_check_invertido() {
  [ -f "$RES_FEAT" ] || { _error "arquivo ausente" "$RES_FEAT"; return 2; }
  if grep -Eq '^[[:space:]]*if[[:space:]]+state-lock\.sh[[:space:]]+check' "$RES_FEAT"; then
    _fail "idioma invertido de lock reapareceu em feature-00c-resume.md" \
      "'if state-lock.sh check ...; then abortar' aborta com lock LIVRE (check sai 0 quando livre, 3 quando detido)"
    return 1
  fi
  return 0
}

# A semantica correta tem de estar escrita, nao apenas o idioma removido.
scenario_resume_documenta_semantica_do_check() {
  [ -f "$RES_FEAT" ] || { _error "arquivo ausente" "$RES_FEAT"; return 2; }
  assert_exit 0 grep -Eq 'LIVRE' "$RES_FEAT" || return 1
  assert_exit 0 grep -Eq 'DETIDO' "$RES_FEAT" || return 1
}

# Lock orfao (dono morto) e o caso normal entre ondas: o caminho de saida
# (`acquire --force`) precisa estar no texto, senao a retomada trava.
scenario_resume_documenta_force_para_lock_orfao() {
  [ -f "$RES_FEAT" ] || { _error "arquivo ausente" "$RES_FEAT"; return 2; }
  assert_exit 0 grep -Fq 'acquire' "$RES_FEAT" || return 1
  assert_exit 0 grep -Fq -- '--force' "$RES_FEAT" || return 1
  assert_exit 0 grep -Fq 'lock-force-acquired' "$RES_FEAT" || return 1
}

# ==== Nota de integridade sob SQLite ====

# sha256-verify e no-op sob SQLite; sem essa nota, exit 0 no passo 3 e lido
# como "hash conferido" quando nada foi conferido.
scenario_resume_nota_sha256_noop_sob_sqlite() {
  [ -f "$RES_FEAT" ] || { _error "arquivo ausente" "$RES_FEAT"; return 2; }
  assert_exit 0 grep -Fq 'integrity_check' "$RES_FEAT" || return 1
}

run_all_scenarios "$0"
