#!/bin/sh
# test_guard-hooks-status.sh — cobre
# global/skills/agente-00c-runtime/scripts/guard-hooks-status.sh
#
# Invariantes sob teste:
#   INV-1: READ-ONLY — nenhuma invocacao cria/edita arquivo no projeto-alvo.
#   INV-2: um hook so conta como ativo se estiver PRESENTE (arquivo +x) E
#          REGISTRADO (basename citado em .claude/settings.json). Cada
#          metade sozinha e insuficiente — foi exatamente o modo de falha
#          de campo (arquivo la, settings.json ausente => hook nunca roda).
#   INV-3: check -> exit 0 so com os 3 ativos; 1 caso contrario.
#   INV-4: tick-mode -> "manual" sempre que o tick-hook nao estiver ativo
#          (default seguro: na duvida, ticka na mao em vez de zerar a
#          metrica em silencio).
#   INV-5: remediacao citada em stderr aponta `--scope project` (a causa
#          raiz e o default `--scope global` do cstk install/update).

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/guard-hooks-status.sh"

_HOOKS='pretooluse-bash-guard.sh
posttooluse-tool-call-tick.sh
posttooluse-agent-usage.sh'

# _mkproj NAME -> cria projeto-alvo vazio (com .claude/) e ecoa o path.
_mkproj() {
  _p="$TMPDIR_TEST/$1"
  mkdir -p "$_p/.claude"
  printf '%s' "$_p"
}

# _put_hook PAP HOOK -> materializa o arquivo do hook, executavel.
_put_hook() {
  mkdir -p "$1/.claude/hooks"
  printf '#!/bin/sh\nexit 0\n' > "$1/.claude/hooks/$2"
  chmod +x "$1/.claude/hooks/$2"
}

# _register PAP HOOK... -> settings.json citando os hooks passados.
_register() {
  _rp=$1
  shift
  {
    printf '{"hooks":{"PostToolUse":['
    _first=1
    for _h in "$@"; do
      [ "$_first" = 1 ] || printf ','
      _first=0
      printf '{"hooks":[{"type":"command","command":"$CLAUDE_PROJECT_DIR/.claude/hooks/%s"}]}' "$_h"
    done
    printf ']}}'
  } > "$_rp/.claude/settings.json"
}

# _fully_provisioned PAP -> os 3 hooks presentes E registrados.
_fully_provisioned() {
  for _h in $_HOOKS; do _put_hook "$1" "$_h"; done
  # shellcheck disable=SC2086
  _register "$1" $_HOOKS
}

# ==== INV-3 + INV-2: projeto totalmente provisionado ====

scenario_check_completo_exit0() {
  _p=$(_mkproj proj-ok)
  _fully_provisioned "$_p"
  capture sh "$SCRIPT" check --projeto-alvo-path "$_p"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  for _h in $_HOOKS; do
    printf '%s\n' "$_CAPTURED_STDOUT" | grep -q "^$_h	present	registered$" \
      || { _fail "TSV" "esperado '$_h present registered'"; return 1; }
  done
  return 0
}

# ==== INV-3: projeto virgem (o caso real: 35 ondas, zero hooks) ====

scenario_check_nenhum_hook_exit1() {
  _p=$(_mkproj proj-virgem)
  capture sh "$SCRIPT" check --projeto-alvo-path "$_p"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  _n=$(printf '%s\n' "$_CAPTURED_STDOUT" | grep -c 'missing	unregistered')
  [ "$_n" = 3 ] || { _fail "TSV" "esperado 3 linhas missing/unregistered, obtido $_n"; return 1; }
  return 0
}

# ==== INV-2: arquivo presente mas NAO registrado => nao conta ====

scenario_check_presente_sem_registro_exit1() {
  _p=$(_mkproj proj-sem-settings)
  for _h in $_HOOKS; do _put_hook "$_p" "$_h"; done
  # settings.json deliberadamente ausente
  capture sh "$SCRIPT" check --projeto-alvo-path "$_p"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  printf '%s\n' "$_CAPTURED_STDOUT" | grep -q 'present	unregistered' \
    || { _fail "TSV" "esperado present+unregistered"; return 1; }
  return 0
}

# ==== INV-2: registrado mas arquivo ausente => nao conta ====

scenario_check_registrado_sem_arquivo_exit1() {
  _p=$(_mkproj proj-so-settings)
  # shellcheck disable=SC2086
  _register "$_p" $_HOOKS
  capture sh "$SCRIPT" check --projeto-alvo-path "$_p"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  printf '%s\n' "$_CAPTURED_STDOUT" | grep -q 'missing	registered' \
    || { _fail "TSV" "esperado missing+registered"; return 1; }
  return 0
}

# ==== INV-2: arquivo sem bit de execucao => nao conta ====

scenario_check_hook_sem_exec_bit_nao_conta() {
  _p=$(_mkproj proj-noexec)
  _fully_provisioned "$_p"
  chmod -x "$_p/.claude/hooks/pretooluse-bash-guard.sh"
  capture sh "$SCRIPT" check --projeto-alvo-path "$_p"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  printf '%s\n' "$_CAPTURED_STDOUT" | grep -q '^pretooluse-bash-guard.sh	missing' \
    || { _fail "TSV" "hook sem +x deve contar como missing"; return 1; }
  return 0
}

# ==== INV-3: provisionamento parcial (so as metricas, sem a guarda) ====

scenario_check_parcial_exit1_com_alerta_da_guarda() {
  _p=$(_mkproj proj-parcial)
  _put_hook "$_p" "posttooluse-tool-call-tick.sh"
  _register "$_p" "posttooluse-tool-call-tick.sh"
  capture sh "$SCRIPT" check --projeto-alvo-path "$_p"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  printf '%s\n' "$_CAPTURED_STDOUT" | grep -q '^posttooluse-tool-call-tick.sh	present	registered$' \
    || { _fail "TSV" "tick-hook ativo deveria aparecer como present/registered"; return 1; }
  # A ausencia da guarda e o item grave: precisa vir destacada em stderr.
  printf '%s\n' "$_CAPTURED_STDERR" | grep -q 'pretooluse-bash-guard.sh inativo' \
    || { _fail "stderr" "faltou alerta destacado da guarda inativa"; return 1; }
  return 0
}

# ==== INV-5: remediacao aponta --scope project ====

scenario_check_stderr_cita_scope_project() {
  _p=$(_mkproj proj-remediacao)
  capture sh "$SCRIPT" check --projeto-alvo-path "$_p"
  printf '%s\n' "$_CAPTURED_STDERR" | grep -q -- '--scope project' \
    || { _fail "stderr" "remediacao deve citar 'cstk install --scope project'"; return 1; }
  return 0
}

# ==== --quiet suprime stderr mas mantem TSV + exit ====

scenario_check_quiet_sem_stderr() {
  _p=$(_mkproj proj-quiet)
  capture sh "$SCRIPT" check --projeto-alvo-path "$_p" --quiet
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDERR" ] || { _fail "stderr" "--quiet nao pode emitir stderr"; return 1; }
  [ -n "$_CAPTURED_STDOUT" ] || { _fail "stdout" "--quiet nao pode suprimir o TSV"; return 1; }
  return 0
}

# ==== INV-1: READ-ONLY ====

scenario_read_only_nao_cria_nada() {
  _p=$(_mkproj proj-readonly)
  _before=$(find "$_p" | sort)
  capture sh "$SCRIPT" check --projeto-alvo-path "$_p"
  capture sh "$SCRIPT" tick-mode --projeto-alvo-path "$_p"
  _after=$(find "$_p" | sort)
  [ "$_before" = "$_after" ] \
    || { _fail "read-only" "arvore do projeto-alvo mudou apos as consultas"; return 1; }
  return 0
}

# ==== INV-4: tick-mode ====

scenario_tick_mode_hook_quando_ativo() {
  _p=$(_mkproj proj-tick-hook)
  _fully_provisioned "$_p"
  capture sh "$SCRIPT" tick-mode --projeto-alvo-path "$_p"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ "$_CAPTURED_STDOUT" = "hook" ] \
    || { _fail "stdout" "esperado 'hook', obtido '$_CAPTURED_STDOUT'"; return 1; }
  return 0
}

scenario_tick_mode_manual_quando_ausente() {
  _p=$(_mkproj proj-tick-manual)
  capture sh "$SCRIPT" tick-mode --projeto-alvo-path "$_p"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ "$_CAPTURED_STDOUT" = "manual" ] \
    || { _fail "stdout" "esperado 'manual', obtido '$_CAPTURED_STDOUT'"; return 1; }
  return 0
}

# tick-mode e consulta, nao veredito: exit 0 mesmo com tudo ausente.
scenario_tick_mode_exit0_mesmo_sem_hooks() {
  _p=$(_mkproj proj-tick-exit)
  assert_exit 0 sh "$SCRIPT" tick-mode --projeto-alvo-path "$_p" || return 1
  return 0
}

# Hook presente mas NAO registrado => "manual" (INV-2 aplicado ao tick-mode).
scenario_tick_mode_manual_sem_registro() {
  _p=$(_mkproj proj-tick-noreg)
  _put_hook "$_p" "posttooluse-tool-call-tick.sh"
  capture sh "$SCRIPT" tick-mode --projeto-alvo-path "$_p"
  [ "$_CAPTURED_STDOUT" = "manual" ] \
    || { _fail "stdout" "hook nao-registrado deve dar 'manual'"; return 1; }
  return 0
}

# ==== Uso incorreto -> exit 2 ====

scenario_sem_subcomando_exit2() {
  assert_exit 2 sh "$SCRIPT" || return 1
  return 0
}

scenario_subcomando_desconhecido_exit2() {
  assert_exit 2 sh "$SCRIPT" nao-existe --projeto-alvo-path /tmp || return 1
  return 0
}

scenario_check_sem_pap_exit2() {
  assert_exit 2 sh "$SCRIPT" check || return 1
  return 0
}

scenario_check_flag_desconhecida_exit2() {
  _p=$(_mkproj proj-flag)
  assert_exit 2 sh "$SCRIPT" check --projeto-alvo-path "$_p" --nao-existe || return 1
  return 0
}

scenario_check_pap_inexistente_exit2() {
  assert_exit 2 sh "$SCRIPT" check --projeto-alvo-path "$TMPDIR_TEST/nao-existe-mesmo" || return 1
  return 0
}

scenario_tick_mode_sem_pap_exit2() {
  assert_exit 2 sh "$SCRIPT" tick-mode || return 1
  return 0
}

# ==== Sem jq no PATH: o script nao pode depender dele ====
# O projeto-alvo mal provisionado e justamente onde jq pode faltar.

scenario_funciona_sem_jq() {
  _p=$(_mkproj proj-sem-jq)
  _fully_provisioned "$_p"
  _shim="$TMPDIR_TEST/shimbin-nojq"
  mkdir -p "$_shim"
  for _cmd in sh grep printf find sort chmod mkdir cat rm ls; do
    _src=$(command -v "$_cmd" 2>/dev/null) || continue
    ln -sf "$_src" "$_shim/$_cmd" 2>/dev/null || :
  done
  capture env PATH="$_shim" sh "$SCRIPT" check --projeto-alvo-path "$_p"
  [ "$_CAPTURED_EXIT" = 0 ] \
    || { _fail "exit" "sem jq deveria continuar exit 0, obtido $_CAPTURED_EXIT"; return 1; }
  return 0
}

run_all_scenarios
exit $?
