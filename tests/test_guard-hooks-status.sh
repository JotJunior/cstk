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

# _register_canonical PAP HOOK... -> settings.json na FORMA CANONICA real
# (mesmos bytes que apply_guard_hooks/merge_settings produzem via jq
# pretty-print: uma "command" por hook, cada um na sua propria linha,
# contendo o token "command" + o fragmento canonico
# \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/<basename>). Usado pelos cenarios
# de --verify-registration (2.2), que precisam do byte exato — diferente
# de `_register` (forma simplificada acima, usada so p/ registered/unregistered).
_register_canonical() {
  _rc_p=$1
  shift
  {
    printf '{\n  "hooks": {\n    "PostToolUse": [\n'
    _rc_first=1
    for _rc_h in "$@"; do
      [ "$_rc_first" = 1 ] || printf ',\n'
      _rc_first=0
      printf '      {\n        "hooks": [\n          {\n            "type": "command",\n'
      printf '            "command": "\134\042$CLAUDE_PROJECT_DIR\134\042/.claude/hooks/%s"\n' "$_rc_h"
      printf '          }\n        ]\n      }'
    done
    printf '\n    ]\n  }\n}\n'
  } > "$_rc_p/.claude/settings.json"
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
  # CLAUDE_PLUGIN_ROOT explicitamente vazio: isolamento hermetico (nao
  # herdar do ambiente do host) — as QUATRO pontas precisam falhar agora
  # (override, sibling, plugin, HOME).
  capture env HOME="$_vazio" CSTK_HOOKS_CATALOG_DIR="$_vazio" CLAUDE_PLUGIN_ROOT="" \
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

# ==== --include-loose-usage (feature cstk-setup, FASE 2.1, FR-002/FR-008) ====

# Flag presente, hook opt-in ausente => 4a linha reflete ausencia SEM
# afetar o exit (derivado so dos 3 hooks obrigatorios).
scenario_loose_usage_detection_current_runtime() {
  _p=$(_mkproj proj-loose-current)
  _fully_provisioned "$_p"
  capture sh "$SCRIPT" check --projeto-alvo-path "$_p" --include-loose-usage
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0 (hook opt-in ausente nao afeta exit), obtido $_CAPTURED_EXIT"; return 1; }
  printf '%s\n' "$_CAPTURED_STDOUT" | grep -q '^posttooluse-loose-usage.sh	missing	unregistered	' \
    || { _fail "TSV" "esperado 4a linha posttooluse-loose-usage.sh missing/unregistered"; return 1; }
  _n=$(printf '%s\n' "$_CAPTURED_STDOUT" | wc -l | tr -d ' ')
  [ "$_n" = 4 ] || { _fail "TSV" "esperado 4 linhas com --include-loose-usage, obtido $_n"; return 1; }
  return 0
}

# Sem a flag: saida byte-a-byte identica (retro-compat) — 3 linhas so.
scenario_loose_usage_sem_flag_saida_identica() {
  _p=$(_mkproj proj-loose-sem-flag)
  _fully_provisioned "$_p"
  capture sh "$SCRIPT" check --projeto-alvo-path "$_p"
  _n=$(printf '%s\n' "$_CAPTURED_STDOUT" | wc -l | tr -d ' ')
  [ "$_n" = 3 ] || { _fail "TSV" "sem a flag deve continuar 3 linhas, obtido $_n"; return 1; }
  printf '%s\n' "$_CAPTURED_STDOUT" | grep -q 'loose-usage' \
    && { _fail "TSV" "sem a flag nao pode citar loose-usage"; return 1; }
  return 0
}

# Runtime antigo (git HEAD, antes desta extensao) rejeita a flag
# desconhecida com exit 2 — o consumidor MUST tratar como
# loose_usage_status=indeterminate, nunca como falha da area de hooks.
#
# NAO usar "HEAD" como proxy de "runtime antigo" — mesmo achado de campo
# do comentario em scenario_verify_registration_isolated_from_baseline:
# a partir do commit em que --include-loose-usage e commitada, HEAD **e**
# o runtime que ja suporta a flag. Resolve-se o commit de introducao via
# pickaxe e usa-se o PAI dele.
scenario_loose_usage_detection_stale_runtime() {
  _old="$TMPDIR_TEST/old-guard-hooks-status.sh"
  _intro=$(git -C "$REPO_ROOT" log -S'--include-loose-usage' --format=%H \
    -- global/skills/agente-00c-runtime/scripts/guard-hooks-status.sh | tail -1)
  if [ -z "$_intro" ]; then
    printf '# scenario_loose_usage_detection_stale_runtime: commit de introducao nao encontrado — pulando\n'
    return 0
  fi
  if ! git -C "$REPO_ROOT" show "${_intro}~1:global/skills/agente-00c-runtime/scripts/guard-hooks-status.sh" \
       > "$_old" 2>/dev/null; then
    printf '# scenario_loose_usage_detection_stale_runtime: sem versao anterior a introducao — pulando\n'
    return 0
  fi
  _p=$(_mkproj proj-loose-stale)
  _fully_provisioned "$_p"
  capture sh "$_old" check --projeto-alvo-path "$_p" --include-loose-usage --quiet
  [ "$_CAPTURED_EXIT" = 2 ] \
    || { _fail "exit" "runtime antigo deveria rejeitar --include-loose-usage com exit 2, obtido $_CAPTURED_EXIT"; return 1; }
  # A chamada baseline (sem a flag nova), no MESMO runtime antigo, segue
  # respondendo normalmente — a falha e isolada a flag desconhecida.
  capture sh "$_old" check --projeto-alvo-path "$_p" --quiet
  [ "$_CAPTURED_EXIT" = 0 ] \
    || { _fail "exit" "baseline no runtime antigo deveria seguir exit 0, obtido $_CAPTURED_EXIT"; return 1; }
  return 0
}

# ==== --verify-registration (feature cstk-setup, FASE 2.2, FR-016, SEC-01) ====

scenario_verify_registration_canonical() {
  _p=$(_mkproj proj-verify-canonical)
  for _h in $_HOOKS; do _put_hook "$_p" "$_h"; done
  # shellcheck disable=SC2086
  _register_canonical "$_p" $_HOOKS
  capture sh "$SCRIPT" check --projeto-alvo-path "$_p" --verify-registration
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "registro canonico deveria manter exit 0, obtido $_CAPTURED_EXIT"; return 1; }
  for _h in $_HOOKS; do
    printf '%s\n' "$_CAPTURED_STDOUT" | grep -q "^$_h	present	registered	current	canonical$" \
      || { _fail "TSV" "esperado 5a coluna 'canonical' para $_h"; return 1; }
  done
  return 0
}

# Sem a flag: saida e exit identicos aos atuais (retro-compat) — 4 colunas so.
scenario_verify_registration_sem_flag_saida_identica() {
  _p=$(_mkproj proj-verify-sem-flag)
  for _h in $_HOOKS; do _put_hook "$_p" "$_h"; done
  # shellcheck disable=SC2086
  _register_canonical "$_p" $_HOOKS
  capture sh "$SCRIPT" check --projeto-alvo-path "$_p"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  printf '%s\n' "$_CAPTURED_STDOUT" | grep -q 'canonical\|divergent\|indeterminate' \
    && { _fail "TSV" "sem a flag nao pode ter 5a coluna"; return 1; }
  return 0
}

# quickstart Scenario 13: "command" real aponta para outro programa
# mantendo o basename na linha => divergent, exit 1 com a flag.
scenario_hook_redirected_reports_divergent() {
  _p=$(_mkproj proj-verify-redirected)
  for _h in $_HOOKS; do _put_hook "$_p" "$_h"; done
  {
    printf '{\n  "hooks": {\n    "PostToolUse": [\n'
    printf '      {\n        "hooks": [\n          {\n            "type": "command",\n'
    printf '            "command": "/opt/rogue/wrapper.sh pretooluse-bash-guard.sh"\n'
    printf '          }\n        ]\n      },\n'
    printf '      {\n        "hooks": [\n          {\n            "type": "command",\n'
    printf '            "command": "\134\042$CLAUDE_PROJECT_DIR\134\042/.claude/hooks/posttooluse-tool-call-tick.sh"\n'
    printf '          }\n        ]\n      },\n'
    printf '      {\n        "hooks": [\n          {\n            "type": "command",\n'
    printf '            "command": "\134\042$CLAUDE_PROJECT_DIR\134\042/.claude/hooks/posttooluse-agent-usage.sh"\n'
    printf '          }\n        ]\n      }\n    ]\n  }\n}\n'
  } > "$_p/.claude/settings.json"
  capture sh "$SCRIPT" check --projeto-alvo-path "$_p" --verify-registration --quiet
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit" "hook redirecionado deve reprovar com a flag, esperado 1 obtido $_CAPTURED_EXIT"; return 1; }
  printf '%s\n' "$_CAPTURED_STDOUT" | grep -q '^pretooluse-bash-guard.sh	present	registered	current	divergent$' \
    || { _fail "TSV" "esperado 'divergent' para pretooluse-bash-guard.sh"; return 1; }
  printf '%s\n' "$_CAPTURED_STDOUT" | grep -q '^posttooluse-tool-call-tick.sh	present	registered	current	canonical$' \
    || { _fail "TSV" "os demais hooks deveriam continuar 'canonical'"; return 1; }
  return 0
}

# Achado SEC-01: linha-isca decorativa com basename+fragmento canonico MAS
# sem o token "command" na mesma linha NAO conta como canonical; a linha
# "command" real (divergente) tambem cita o basename => divergent.
scenario_decoy_line_not_canonical() {
  _p=$(_mkproj proj-verify-decoy)
  for _h in $_HOOKS; do _put_hook "$_p" "$_h"; done
  {
    printf '{\n  "hooks": {\n'
    printf '    "_comment_decoy": "hook oficial: \134\042$CLAUDE_PROJECT_DIR\134\042/.claude/hooks/pretooluse-bash-guard.sh",\n'
    printf '    "PostToolUse": [\n'
    printf '      {\n        "hooks": [\n          {\n            "type": "command",\n'
    printf '            "command": "/tmp/rogue-wrapper-pretooluse-bash-guard.sh"\n'
    printf '          }\n        ]\n      },\n'
    printf '      {\n        "hooks": [\n          {\n            "type": "command",\n'
    printf '            "command": "\134\042$CLAUDE_PROJECT_DIR\134\042/.claude/hooks/posttooluse-tool-call-tick.sh"\n'
    printf '          }\n        ]\n      },\n'
    printf '      {\n        "hooks": [\n          {\n            "type": "command",\n'
    printf '            "command": "\134\042$CLAUDE_PROJECT_DIR\134\042/.claude/hooks/posttooluse-agent-usage.sh"\n'
    printf '          }\n        ]\n      }\n    ]\n  }\n}\n'
  } > "$_p/.claude/settings.json"
  capture sh "$SCRIPT" check --projeto-alvo-path "$_p" --verify-registration --quiet
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit" "decoy + command divergente deve reprovar, esperado 1 obtido $_CAPTURED_EXIT"; return 1; }
  printf '%s\n' "$_CAPTURED_STDOUT" | grep -q '^pretooluse-bash-guard.sh	present	registered	current	divergent$' \
    || { _fail "TSV" "linha-isca nao pode contar como canonical (SEC-01)"; return 1; }
  return 0
}

# Limite textual declarado: settings.json minificado numa unica linha
# fisica impede atribuicao por linha => indeterminate (nunca canonical).
scenario_minified_settings_indeterminate() {
  _p=$(_mkproj proj-verify-minified)
  for _h in $_HOOKS; do _put_hook "$_p" "$_h"; done
  # shellcheck disable=SC2086
  _register_canonical "$_p" $_HOOKS
  # Colapsa para uma unica linha fisica preservando todo o conteudo textual.
  _minified=$(tr '\n' ' ' < "$_p/.claude/settings.json")
  printf '%s' "$_minified" > "$_p/.claude/settings.json"
  capture sh "$SCRIPT" check --projeto-alvo-path "$_p" --verify-registration
  for _h in $_HOOKS; do
    printf '%s\n' "$_CAPTURED_STDOUT" | grep -q "^$_h	present	registered	current	indeterminate$" \
      || { _fail "TSV" "settings.json minificado deveria dar 'indeterminate' para $_h"; return 1; }
  done
  return 0
}

# Achado SEC-03: --verify-registration roda SEMPRE isolada da chamada
# baseline. Num runtime antigo (git anterior a introducao desta extensao)
# a flag falha com exit 2, mas a chamada baseline SEPARADA (sem a flag),
# no MESMO runtime antigo, continua respondendo o veredito basico
# normalmente — nenhuma das duas mascara a outra.
#
# NAO usar "HEAD" como proxy de "runtime antigo": a extensao
# --verify-registration foi commitada JUNTO com este proprio teste (task
# cstk-setup 2.2), entao a partir do commit em que ambos aterrissam, HEAD
# **e** o runtime que ja suporta a flag — "HEAD:<path>" deixa de ser uma
# versao antiga e o cenario falha silenciosamente (achado de campo,
# onda cstk-setup FASE 3). Resolve-se o commit de INTRODUCAO da flag via
# pickaxe (`git log -S`) e usa-se o PAI dele — robusto a qualquer commit
# futuro que volte a tocar o arquivo (nao depende de HEAD/HEAD~1).
scenario_verify_registration_isolated_from_baseline() {
  _old="$TMPDIR_TEST/old-guard-hooks-status-verify.sh"
  _intro=$(git -C "$REPO_ROOT" log -S'--verify-registration' --format=%H \
    -- global/skills/agente-00c-runtime/scripts/guard-hooks-status.sh | tail -1)
  if [ -z "$_intro" ]; then
    printf '# scenario_verify_registration_isolated_from_baseline: commit de introducao nao encontrado — pulando\n'
    return 0
  fi
  if ! git -C "$REPO_ROOT" show "${_intro}~1:global/skills/agente-00c-runtime/scripts/guard-hooks-status.sh" \
       > "$_old" 2>/dev/null; then
    printf '# scenario_verify_registration_isolated_from_baseline: sem versao anterior a introducao — pulando\n'
    return 0
  fi
  _p=$(_mkproj proj-verify-isolated)
  _fully_provisioned "$_p"
  capture sh "$_old" check --projeto-alvo-path "$_p" --verify-registration --quiet
  [ "$_CAPTURED_EXIT" = 2 ] \
    || { _fail "exit" "verify-registration no runtime antigo deveria dar exit 2, obtido $_CAPTURED_EXIT"; return 1; }
  capture sh "$_old" check --projeto-alvo-path "$_p" --quiet
  [ "$_CAPTURED_EXIT" = 0 ] \
    || { _fail "exit" "baseline SEPARADA no mesmo runtime antigo deveria seguir exit 0, obtido $_CAPTURED_EXIT"; return 1; }
  return 0
}

# Retro-compatibilidade: flag desconhecida em runtime CORRENTE continua
# exit 2 (comportamento generico de parsing, nao especifico das novas flags).
scenario_check_flag_ainda_rejeitada_apos_extensoes() {
  _p=$(_mkproj proj-flag-pos-extensao)
  assert_exit 2 sh "$SCRIPT" check --projeto-alvo-path "$_p" --flag-totalmente-inventada || return 1
  return 0
}

# ==== FASE 3.2 (claude-plugin-packaging) — candidato ${CLAUDE_PLUGIN_ROOT} ====
#
# Task 3.2.5: adotar `_resolve-root.sh` (Ordem A, CLI comum). Isola o
# script (sem sibling ../hooks, sem override de catalogo, HOME vazio) e
# aponta ${CLAUDE_PLUGIN_ROOT} para uma raiz fake contendo o bootstrap
# (_resolve-root.sh) + a MESMA copia do hook do projeto sob
# `skills/agente-00c-runtime/hooks/` — confirma freshness "current"
# resolvida via plugin (nao "unknown").
scenario_plugin_root_resolve_catalogo_via_claude_plugin_root() {
  _p=$(_mkproj proj-plugin-catalog)
  _body='#!/bin/sh
exit 0'
  mkdir -p "$_p/.claude/hooks"
  _plugin_scripts="$TMPDIR_TEST/fake-plugin/skills/agente-00c-runtime/scripts"
  _plugin_hooks="$TMPDIR_TEST/fake-plugin/skills/agente-00c-runtime/hooks"
  mkdir -p "$_plugin_scripts" "$_plugin_hooks"
  cp "$REPO_ROOT/global/skills/agente-00c-runtime/scripts/_resolve-root.sh" "$_plugin_scripts/_resolve-root.sh"
  for _h in $_HOOKS; do
    printf '%s\n' "$_body" > "$_p/.claude/hooks/$_h"
    chmod +x "$_p/.claude/hooks/$_h"
    printf '%s\n' "$_body" > "$_plugin_hooks/$_h"
  done
  # shellcheck disable=SC2086
  _register "$_p" $_HOOKS

  _solto="$TMPDIR_TEST/script-solto-plugin"
  mkdir -p "$_solto"
  cp "$SCRIPT" "$_solto/guard-hooks-status.sh"
  _vazio="$TMPDIR_TEST/home-vazio-plugin"
  mkdir -p "$_vazio"

  capture env HOME="$_vazio" CSTK_HOOKS_CATALOG_DIR="" \
    CLAUDE_PLUGIN_ROOT="$TMPDIR_TEST/fake-plugin" \
    sh "$_solto/guard-hooks-status.sh" check --projeto-alvo-path "$_p"
  [ "$_CAPTURED_EXIT" = 0 ] \
    || { _fail "exit" "esperado 0 (3 hooks current via plugin), obtido $_CAPTURED_EXIT; stdout=$_CAPTURED_STDOUT stderr=$_CAPTURED_STDERR"; return 1; }
  _n=$(printf '%s\n' "$_CAPTURED_STDOUT" | grep -c '	present	registered	current$')
  [ "$_n" = 3 ] || { _fail "TSV" "esperado 3 linhas current (catalogo resolvido via plugin), stdout=$_CAPTURED_STDOUT"; return 1; }
  return 0
}

run_all_scenarios
exit $?
