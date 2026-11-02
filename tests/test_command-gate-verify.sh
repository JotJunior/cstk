#!/bin/sh
# test_command-gate-verify.sh — smoke textual da integracao do gate de
# testes (issue #242) nos commands pai e nos orquestradores.
#
# Cobertura:
#   - nos 4 commands pai, `gate-verify.sh run` aparece ANTES do
#     `reconcile-wave --state-dir` (o reconcile avanca de execute-task/
#     converge, e o end --advance interno recusa sem run verde da onda)
#   - o fechamento de gate vermelho usa threshold_proxy_atingido (SEM
#     --advance) nos 4 commands
#   - os 2 commands de inicio oferecem o opt-in (`--gate-command` +
#     `gate-verify.sh set-command`) e proibem derivar o comando de docs
#   - os 2 orquestradores mandam rodar `gate-verify.sh run` antes do
#     `end --advance` saindo de execute-task/converge

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CMDS="$REPO_ROOT/plugins/cstk/commands"
AGENTS="$REPO_ROOT/plugins/cstk/agents"

_line_of() {
  grep -nE "$2" "$1" 2>/dev/null | head -n1 | cut -d: -f1
}

scenario_gate_run_antes_do_reconcile_nos_4_commands() {
  for _f in feature-00c feature-00c-resume agente-00c agente-00c-resume; do
    _p="$CMDS/$_f.md"
    _g=$(_line_of "$_p" 'gate-verify\.sh run --state-dir')
    _r=$(_line_of "$_p" '^state-ondas\.sh reconcile-wave --state-dir')
    [ -n "$_g" ] || { _fail "$_f: gate-verify.sh run ausente" ""; return 1; }
    [ -n "$_r" ] || { _fail "$_f: reconcile-wave ausente" ""; return 1; }
    [ "$_g" -lt "$_r" ] || { _fail "$_f: gate (l.$_g) deveria vir antes do reconcile (l.$_r)" ""; return 1; }
  done
}

scenario_gate_vermelho_fecha_sem_advance_nos_4_commands() {
  for _f in feature-00c feature-00c-resume agente-00c agente-00c-resume; do
    grep -q 'if \[ "\$GV_RC" = 3 \]' "$CMDS/$_f.md" \
      || { _fail "$_f: tratamento de GV_RC=3 ausente" ""; return 1; }
    grep -q -- '--motivo-termino threshold_proxy_atingido \\$' "$CMDS/$_f.md" \
      || { _fail "$_f: fechamento sem avanco ausente" ""; return 1; }
  done
}

scenario_optin_nos_commands_de_inicio() {
  for _f in feature-00c agente-00c; do
    _p="$CMDS/$_f.md"
    grep -q -- '--gate-command' "$_p" || { _fail "$_f: flag --gate-command ausente" ""; return 1; }
    grep -q 'gate-verify\.sh set-command' "$_p" || { _fail "$_f: set-command ausente" ""; return 1; }
    grep -q 'NUNCA derive o comando' "$_p" || { _fail "$_f: proibicao de derivar comando ausente (Principio VI)" ""; return 1; }
  done
}

scenario_orquestradores_rodam_gate_antes_do_advance() {
  for _f in agente-00c-orchestrator agente-00c-feature-orchestrator; do
    grep -q 'gate-verify\.sh run --state-dir' "$AGENTS/$_f.md" \
      || { _fail "$_f: instrucao do gate ausente" ""; return 1; }
  done
}

run_all_scenarios
