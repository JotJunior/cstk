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
#   INV-6: 3a dimensao `current|stale|unknown` — copia do projeto que
#          diverge do catalogo reprova (exit 1). Foi o 2o modo de falha de
#          campo: apos o cutover state.json->state.db os projetos ficaram
#          com a copia de jul/2026 do tick-hook (que so le state.json),
#          `check` dizia "3/3 ativos" e tool_calls zerou em todas as ondas.
#          "unknown" (hook ausente, catalogo irresolvivel, `cmp` ausente)
#          NUNCA reprova — na duvida nao se acusa drift.
#   INV-7: tick-mode rebaixa para "manual" no par exato
#          (copia cega a backend + projeto com state.db). Copia cega sobre
#          backend JSON SEGUE "hook" — rebaixar ali daria contagem DUPLA.

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

# Catalogo de referencia dos cenarios: `_put_hook` materializa a MESMA
# copia no projeto e no catalogo, entao o default de todo cenario e
# "current". Cenarios de drift divergem uma das duas pontas de proposito.
# Sem este override o catalogo resolveria para o sibling do script (os
# hooks reais do repo) e todo stub viraria "stale".
# Define e EXPORTA CSTK_HOOKS_CATALOG_DIR, deixando o path em $_CATALOG.
# Nao pode ecoar via $(...): o export morreria no subshell e o catalogo
# cairia no sibling (hooks reais do repo), tornando todo stub "stale".
_catalog_dir() {
  _CATALOG="$TMPDIR_TEST/catalog-hooks"
  mkdir -p "$_CATALOG"
  CSTK_HOOKS_CATALOG_DIR="$_CATALOG"
  export CSTK_HOOKS_CATALOG_DIR
}

# _put_hook PAP HOOK [BODY] -> materializa o arquivo do hook (executavel)
# no projeto E no catalogo, com o mesmo conteudo.
_put_hook() {
  _ph_body=${3:-'#!/bin/sh
exit 0'}
  _catalog_dir
  mkdir -p "$1/.claude/hooks"
  printf '%s\n' "$_ph_body" > "$1/.claude/hooks/$2"
  chmod +x "$1/.claude/hooks/$2"
  printf '%s\n' "$_ph_body" > "$_CATALOG/$2"
}

# _put_hook_stale PAP HOOK -> copia do projeto DIVERGE da do catalogo.
_put_hook_stale() {
  _catalog_dir
  mkdir -p "$1/.claude/hooks"
  printf '#!/bin/sh\n# versao antiga (so le state.json)\nexit 0\n' > "$1/.claude/hooks/$2"
  chmod +x "$1/.claude/hooks/$2"
  printf '#!/bin/sh\n# versao nova\n. _hook-active-exec.sh\nexit 0\n' > "$_CATALOG/$2"
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
    printf '%s\n' "$_CAPTURED_STDOUT" | grep -q "^$_h	present	registered	current$" \
      || { _fail "TSV" "esperado '$_h present registered current'"; return 1; }
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
  printf '%s\n' "$_CAPTURED_STDOUT" | grep -q '^posttooluse-tool-call-tick.sh	present	registered	current$' \
    || { _fail "TSV" "tick-hook ativo deveria aparecer como present/registered/current"; return 1; }
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

# ==== INV-6: copia stale (o 2o modo de falha de campo) ====

# Reproduz o bug de 03/ago/2026: os 3 hooks present+registered, mas a copia
# do projeto e a de jul/2026. Antes desta dimensao, `check` dizia 3/3 ativos
# e tool_calls zerava em silencio.
scenario_check_stale_exit1() {
  _p=$(_mkproj proj-stale)
  for _h in $_HOOKS; do _put_hook_stale "$_p" "$_h"; done
  # shellcheck disable=SC2086
  _register "$_p" $_HOOKS
  capture sh "$SCRIPT" check --projeto-alvo-path "$_p"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit" "copia stale deve reprovar (esperado 1, obtido $_CAPTURED_EXIT)"; return 1; }
  _n=$(printf '%s\n' "$_CAPTURED_STDOUT" | grep -c '	present	registered	stale$')
  [ "$_n" = 3 ] || { _fail "TSV" "esperado 3 linhas present/registered/stale, obtido $_n"; return 1; }
  printf '%s\n' "$_CAPTURED_STDERR" | grep -q 'STALE' \
    || { _fail "stderr" "faltou diagnostico de stale"; return 1; }
  return 0
}

# A guarda stale e o item grave (roda com regras de versao anterior) —
# precisa de alerta destacado, paridade com o alerta de guarda inativa.
scenario_check_stale_da_guarda_tem_alerta_destacado() {
  _p=$(_mkproj proj-stale-guarda)
  _fully_provisioned "$_p"
  _put_hook_stale "$_p" "pretooluse-bash-guard.sh"
  capture sh "$SCRIPT" check --projeto-alvo-path "$_p"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  printf '%s\n' "$_CAPTURED_STDERR" | grep -q 'pretooluse-bash-guard.sh STALE' \
    || { _fail "stderr" "faltou alerta destacado da guarda stale"; return 1; }
  return 0
}

# INV-6: catalogo irresolvivel => "unknown", nunca "stale" (nao se acusa
# drift sem ter com que comparar).
scenario_check_catalogo_ausente_da_unknown_e_nao_reprova() {
  _p=$(_mkproj proj-sem-catalogo)
  _fully_provisioned "$_p"
  _vazio="$TMPDIR_TEST/catalogo-vazio"
  mkdir -p "$_vazio"
  # As TRES pontas da cadeia precisam falhar para valer como "irresolvivel":
  # override vazio, script copiado para fora do catalogo (sem sibling
  # ../hooks) e HOME falso. Neutralizar so o override deixaria o sibling do
  # repo responder — e o veredito seria "stale", nao "unknown".
  _solto="$TMPDIR_TEST/script-solto"
  mkdir -p "$_solto"
  cp "$SCRIPT" "$_solto/guard-hooks-status.sh"
  capture env HOME="$_vazio" CSTK_HOOKS_CATALOG_DIR="$_vazio" \
    sh "$_solto/guard-hooks-status.sh" check --projeto-alvo-path "$_p"
  [ "$_CAPTURED_EXIT" = 0 ] \
    || { _fail "exit" "catalogo irresolvivel nao pode reprovar (obtido $_CAPTURED_EXIT)"; return 1; }
  _n=$(printf '%s\n' "$_CAPTURED_STDOUT" | grep -c '	unknown$')
  [ "$_n" = 3 ] || { _fail "TSV" "esperado 3 linhas unknown, obtido $_n"; return 1; }
  return 0
}

# Hook ausente => freshness "unknown" (nao ha copia do projeto p/ comparar);
# o que reprova ali e o missing, nao o drift.
scenario_check_hook_ausente_da_unknown() {
  _p=$(_mkproj proj-unknown-missing)
  capture sh "$SCRIPT" check --projeto-alvo-path "$_p"
  _n=$(printf '%s\n' "$_CAPTURED_STDOUT" | grep -c '	missing	unregistered	unknown$')
  [ "$_n" = 3 ] || { _fail "TSV" "hook ausente deve dar freshness unknown, obtido $_n linhas"; return 1; }
  return 0
}

# ==== INV-7: rebaixamento do tick-mode por cegueira de backend ====

# Copia cega (pre hooks-db-parity) + state.db no projeto = o par exato em
# que o hook nunca ticka. Sem o rebaixamento, tool_calls fica 0.
scenario_tick_mode_manual_com_copia_cega_e_state_db() {
  _p=$(_mkproj proj-cego-sqlite)
  _fully_provisioned "$_p"
  mkdir -p "$_p/.claude/feature-00c-state/demo"
  : > "$_p/.claude/feature-00c-state/demo/state.db"
  capture sh "$SCRIPT" tick-mode --projeto-alvo-path "$_p"
  [ "$_CAPTURED_STDOUT" = "manual" ] \
    || { _fail "stdout" "copia cega + state.db deve dar 'manual', obtido '$_CAPTURED_STDOUT'"; return 1; }
  return 0
}

# Mesma cegueira em agente-00c-state/ (nao so feature-00c-state/*/).
scenario_tick_mode_manual_com_copia_cega_e_state_db_agente() {
  _p=$(_mkproj proj-cego-sqlite-agente)
  _fully_provisioned "$_p"
  mkdir -p "$_p/.claude/agente-00c-state"
  : > "$_p/.claude/agente-00c-state/state.db"
  capture sh "$SCRIPT" tick-mode --projeto-alvo-path "$_p"
  [ "$_CAPTURED_STDOUT" = "manual" ] \
    || { _fail "stdout" "copia cega + state.db (agente) deve dar 'manual', obtido '$_CAPTURED_STDOUT'"; return 1; }
  return 0
}

# ANTI-CONTAGEM-DUPLA: copia cega sobre backend JSON SEGUE funcionando —
# devolver "manual" ali somaria tick do hook + tick manual.
scenario_tick_mode_hook_com_copia_cega_e_backend_json() {
  _p=$(_mkproj proj-cego-json)
  _fully_provisioned "$_p"
  mkdir -p "$_p/.claude/feature-00c-state/demo"
  printf '{}\n' > "$_p/.claude/feature-00c-state/demo/state.json"
  capture sh "$SCRIPT" tick-mode --projeto-alvo-path "$_p"
  [ "$_CAPTURED_STDOUT" = "hook" ] \
    || { _fail "stdout" "copia cega + backend JSON deve seguir 'hook', obtido '$_CAPTURED_STDOUT'"; return 1; }
  return 0
}

# Copia ATUAL (referencia _hook-active-exec.sh) + state.db => "hook":
# o rebaixamento e por cegueira, nao pela mera presenca de sqlite.
scenario_tick_mode_hook_com_copia_atual_e_state_db() {
  _p=$(_mkproj proj-atual-sqlite)
  _fully_provisioned "$_p"
  _put_hook "$_p" "posttooluse-tool-call-tick.sh" '#!/bin/sh
# versao pos hooks-db-parity
. _hook-active-exec.sh
exit 0'
  mkdir -p "$_p/.claude/feature-00c-state/demo"
  : > "$_p/.claude/feature-00c-state/demo/state.db"
  capture sh "$SCRIPT" tick-mode --projeto-alvo-path "$_p"
  [ "$_CAPTURED_STDOUT" = "hook" ] \
    || { _fail "stdout" "copia atual + state.db deve dar 'hook', obtido '$_CAPTURED_STDOUT'"; return 1; }
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
