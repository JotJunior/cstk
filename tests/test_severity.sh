#!/bin/sh
# test_severity.sh — cobre plugins/cstk/skills/converge/scripts/severity.sh.
#
# Ref: docs/specs/skill-converge/tasks.md tarefa 2.4.3
#      docs/specs/skill-converge/contracts/converge-interfaces.md §5
#      docs/specs/skill-converge/research.md Decision 3 (tabela)
#      docs/specs/skill-converge/data-model.md §Derivação origin→story_priority

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/converge/scripts/severity.sh"

# ---------- Tabela completa: must-violated=false (research.md §Decision 3) ----------
# type|priority|must-violated|esperado

_SV_TABLE_MUST_FALSE='missing|P1|false|HIGH
missing|P2|false|MEDIUM
missing|P3|false|MEDIUM
missing|none|false|MEDIUM
contradicts|P1|false|HIGH
contradicts|P2|false|MEDIUM
contradicts|P3|false|MEDIUM
contradicts|none|false|MEDIUM
partial|P1|false|HIGH
partial|P2|false|MEDIUM
partial|P3|false|MEDIUM
partial|none|false|MEDIUM
unrequested|P1|false|LOW
unrequested|P2|false|LOW
unrequested|P3|false|LOW
unrequested|none|false|LOW'

scenario_tabela_completa_must_violated_false() {
  printf '%s\n' "$_SV_TABLE_MUST_FALSE" | while IFS='|' read -r _t _p _m _exp; do
    [ -n "$_t" ] || continue
    _got=$(sh "$SCRIPT" --type "$_t" --priority "$_p" --must-violated "$_m" 2>/dev/null)
    if [ "$_got" != "$_exp" ]; then
      printf 'MISMATCH type=%s priority=%s must=%s esperado=%s obtido=%s\n' \
        "$_t" "$_p" "$_m" "$_exp" "$_got"
    fi
  done > "$TMPDIR_TEST/sv_mismatch.txt" 2>/dev/null || true
  if [ -s "$TMPDIR_TEST/sv_mismatch.txt" ]; then
    _fail "tabela completa (must-violated=false) bate research.md Decision 3" \
      "$(cat "$TMPDIR_TEST/sv_mismatch.txt")"
    return 1
  fi
}

# ---------- must-violated=true domina TUDO -> sempre CRITICAL ----------
# Inclui explicitamente unrequested (CHK023): a regra "MUST vence tudo" NAO
# pode degradar para a linha unrequested->LOW so porque o tipo casa nela.

scenario_must_violated_true_sempre_critical_qualquer_combo() {
  _types="missing partial contradicts unrequested"
  _priorities="P1 P2 P3 none"
  : > "$TMPDIR_TEST/sv_mismatch.txt"
  for _t in $_types; do
    for _p in $_priorities; do
      _got=$(sh "$SCRIPT" --type "$_t" --priority "$_p" --must-violated true 2>/dev/null)
      if [ "$_got" != "CRITICAL" ]; then
        printf 'MISMATCH type=%s priority=%s must=true esperado=CRITICAL obtido=%s\n' \
          "$_t" "$_p" "$_got" >> "$TMPDIR_TEST/sv_mismatch.txt"
      fi
    done
  done
  if [ -s "$TMPDIR_TEST/sv_mismatch.txt" ]; then
    _fail "must-violated=true domina tudo (CRITICAL incondicional)" \
      "$(cat "$TMPDIR_TEST/sv_mismatch.txt")"
    return 1
  fi
}

# ---------- CHK023 dedicado: unrequested + MUST-violado -> CRITICAL ----------
# tasks.md 2.4.3: "a regra 'MUST vence tudo, avaliada em ordem' nao deve
# degradar para a linha unrequested->LOW". Redundante com o scenario acima
# por design — mantido separado para rastreabilidade direta ao CHK023.

scenario_chk023_unrequested_com_must_violado_e_critical_nao_low() {
  capture "$SCRIPT" --type unrequested --priority P3 --must-violated true
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ "$_CAPTURED_STDOUT" = "CRITICAL" ] || {
    _fail "CHK023" "esperado CRITICAL (MUST domina unrequested), obtido: $_CAPTURED_STDOUT"
    return 1
  }
}

# ---------- priority=none nunca escala para HIGH por omissao (data-model.md) ----------

scenario_priority_none_cai_em_medium_nunca_high() {
  for _t in missing partial contradicts; do
    capture "$SCRIPT" --type "$_t" --priority none --must-violated false
    [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit ($_t)" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
    [ "$_CAPTURED_STDOUT" = "MEDIUM" ] || {
      _fail "priority=none nao escala para HIGH ($_t)" "obtido: $_CAPTURED_STDOUT"
      return 1
    }
  done
}

# ---------- partial recebe a MESMA severidade que missing/contradicts ----------

scenario_partial_mesma_severidade_que_missing_na_mesma_prioridade() {
  for _p in P1 P2 P3 none; do
    _missing=$(sh "$SCRIPT" --type missing --priority "$_p" --must-violated false)
    _partial=$(sh "$SCRIPT" --type partial --priority "$_p" --must-violated false)
    [ "$_missing" = "$_partial" ] || {
      _fail "partial == missing na prioridade $_p" "missing=$_missing partial=$_partial"
      return 1
    }
  done
}

# ---------- Erros de uso: enum fechado ----------

scenario_type_fora_do_enum_exit2() {
  capture "$SCRIPT" --type bogus --priority P1 --must-violated false
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_priority_fora_do_enum_exit2() {
  capture "$SCRIPT" --type missing --priority P9 --must-violated false
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_must_violated_fora_do_enum_exit2() {
  capture "$SCRIPT" --type missing --priority P1 --must-violated maybe
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_flag_type_ausente_exit2() {
  capture "$SCRIPT" --priority P1 --must-violated false
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_flag_priority_ausente_exit2() {
  capture "$SCRIPT" --type missing --must-violated false
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_flag_must_violated_ausente_exit2() {
  capture "$SCRIPT" --type missing --priority P1
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_sem_argumentos_exit2() {
  capture "$SCRIPT"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_flag_desconhecida_exit2() {
  capture "$SCRIPT" --type missing --priority P1 --must-violated false --bogus x
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_help_exit0() {
  capture "$SCRIPT" --help
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "Uso:" || return 1
}

# ---------- Determinismo (funcao pura) ----------

scenario_saida_deterministica() {
  capture "$SCRIPT" --type partial --priority P2 --must-violated false
  _first="$_CAPTURED_STDOUT"
  capture "$SCRIPT" --type partial --priority P2 --must-violated false
  _second="$_CAPTURED_STDOUT"
  [ "$_first" = "$_second" ] || {
    _fail "determinismo" "duas execucoes com mesma entrada produziram saidas diferentes"
    return 1
  }
}

# ---------- Zero I/O de arquivo / zero side-effect ----------

scenario_sem_side_effect_no_repo() {
  capture "$SCRIPT" --type missing --priority P1 --must-violated false
  assert_no_side_effect || return 1
}

run_all_scenarios
