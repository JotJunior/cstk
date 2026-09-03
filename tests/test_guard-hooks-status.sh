#!/bin/sh
# test_guard-hooks-status.sh — cobre
# plugins/cstk/skills/agente-00c-runtime/scripts/guard-hooks-status.sh
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
#   INV-8: hook provido pelo PLUGIN (v7+) conta como ativo, mesmo sem copia
#          em <PAP>/.claude/hooks/ nem registro em settings.json — e
#          tick-mode devolve "hook". Foi o 3o modo de falha de campo: o
#          `check` mandava rodar `cstk hooks install` (que pula por dedup,
#          "plugin vence") e o `tick-mode` dizia "manual", fazendo o
#          orquestrador tickar EM PARALELO ao hook do plugin — `end` soma
#          ticks manuais + sidecar, entao tool_calls saia em DOBRO.
#          Degradacao assimetrica: hooks.json ilegivel/ausente => "plugin
#          nao prove" (comportamento anterior), nunca o inverso.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/guard-hooks-status.sh"

# _ghs ARGS... -> invoca o SCRIPT com o ambiente NEUTRO quanto a plugin.
#
# Praticamente todos os cenarios deste arquivo simulam um projeto-alvo SEM o
# plugin cstk: os fixtures materializam (ou omitem) copias classicas em
# <PAP>/.claude/hooks/ e exigem veredito missing/stale/unregistered. Desde
# que `guard-hooks-status.sh` passou a enxergar hooks providos pelo plugin,
# o script consulta o registro NATIVO do Claude Code (~/.claude/plugins +
# ~/.claude/settings.json) — que e do DESENVOLVEDOR, nao do fixture.
#
# Sem esta neutralizacao o teste vira dependente de ambiente do pior jeito
# possivel: passa no CI (runner limpo, sem plugin) e falha so na maquina de
# quem tem o cstk instalado como plugin — exatamente o inverso do modo de
# falha que a memoria do projeto ja registra para helpers resolvidos via
# ~/.claude. Cenarios que QUEREM testar o caminho do plugin setam as vars
# explicitamente (ver scenario_check_plugin_*).
# CSTK_OTEL_ENDPOINT e pinada VAZIA por default (issue #162): a 5a coluna
# de gate le o ambiente da invocacao, entao herdar a variavel do shell de
# quem roda a suite tornaria os cenarios nao-deterministicos (verdes na
# maquina sem wrapper `claude()`, vermelhos na maquina com ele).
_ghs() {
  capture env HOME="$TMPDIR_TEST/.home-sem-plugin" CLAUDE_PLUGIN_ROOT='' \
    CSTK_HOOKS_CATALOG_DIR="${CSTK_HOOKS_CATALOG_DIR:-}" \
    CSTK_OTEL_ENDPOINT='' \
    sh "$SCRIPT" "$@"
}

# _ghs_endpoint URL ARGS... -> mesma invocacao com CSTK_OTEL_ENDPOINT setada.
_ghs_endpoint() {
  _ge_url=$1
  shift
  capture env HOME="$TMPDIR_TEST/.home-sem-plugin" CLAUDE_PLUGIN_ROOT='' \
    CSTK_HOOKS_CATALOG_DIR="${CSTK_HOOKS_CATALOG_DIR:-}" \
    CSTK_OTEL_ENDPOINT="$_ge_url" \
    sh "$SCRIPT" "$@"
}

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
  _ghs check --projeto-alvo-path "$_p"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  for _h in $_HOOKS; do
    printf '%s\n' "$_CAPTURED_STDOUT" | grep -q "^$_h	present	registered	current$" \
      || { _fail "TSV" "esperado '$_h present registered current'"; return 1; }
  done
  return 0
}

# ==== issue #189: efetividade — alvo fora da raiz da sessao ====
# `present registered current` responde sobre o alvo; a sessao carrega hooks
# da propria raiz. 3/3 verde + guarda inerte era o caso medido (tool_calls=0
# em 3 ondas). O check avisa em stderr sem mudar TSV nem exit.

# _ghs_from CWD ARGS... — check com cwd controlado (= raiz da sessao) e
# CLAUDE_PROJECT_DIR desligada.
_ghs_from() {
  _gf_cwd=$1; shift
  capture sh -c 'cd -- "$1" && shift && unset CLAUDE_PROJECT_DIR && exec env HOME="$TMPDIR_TEST/.home-sem-plugin" CLAUDE_PLUGIN_ROOT="" CSTK_OTEL_ENDPOINT="" sh "$@"' \
    _ "$_gf_cwd" "$SCRIPT" "$@"
}

scenario_check_alvo_fora_da_raiz_da_sessao_avisa_inefetivo_sem_mudar_tsv() {
  _p=$(_mkproj proj-worktree)
  _fully_provisioned "$_p"
  _root="$TMPDIR_TEST/session-root"; mkdir -p "$_root"
  _ghs_from "$_root" check --projeto-alvo-path "$_p"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0 (TSV/exit inalterados), obtido $_CAPTURED_EXIT"; return 1; }
  for _h in $_HOOKS; do
    printf '%s\n' "$_CAPTURED_STDOUT" | grep -q "^$_h	present	registered	current$" \
      || { _fail "TSV" "esperado '$_h present registered current' intacto"; return 1; }
  done
  assert_stderr_contains "NAO sao efetivos nesta sessao" || return 1
  assert_stderr_contains "issue #189" || return 1
  assert_stderr_contains "session-scope.sh check" || return 1
  # forma PURA: o diagnostico nunca grava enforcement-log no alvo
  [ ! -e "$_p/.claude/enforcement-log.jsonl" ] \
    || { _fail "log" "check nao pode gravar enforcement-log"; return 1; }
}

scenario_check_alvo_na_raiz_da_sessao_nao_avisa_inefetivo() {
  _p=$(_mkproj proj-raiz)
  _fully_provisioned "$_p"
  _ghs_from "$_p" check --projeto-alvo-path "$_p"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  case "$_CAPTURED_STDERR" in
    *"NAO sao efetivos"*) _fail "stderr" "alinhado nao deve avisar: $_CAPTURED_STDERR"; return 1 ;;
  esac
}

scenario_check_quiet_suprime_aviso_de_efetividade() {
  _p=$(_mkproj proj-quiet)
  _fully_provisioned "$_p"
  _root="$TMPDIR_TEST/session-root"; mkdir -p "$_root"
  _ghs_from "$_root" check --projeto-alvo-path "$_p" --quiet
  case "$_CAPTURED_STDERR" in
    *"NAO sao efetivos"*) _fail "stderr" "--quiet deveria suprimir o aviso"; return 1 ;;
  esac
}

# ==== INV-3: projeto virgem (o caso real: 35 ondas, zero hooks) ====

scenario_check_nenhum_hook_exit1() {
  _p=$(_mkproj proj-virgem)
  _ghs check --projeto-alvo-path "$_p"
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
  _ghs check --projeto-alvo-path "$_p"
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
  _ghs check --projeto-alvo-path "$_p"
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
  _ghs check --projeto-alvo-path "$_p"
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
  _ghs check --projeto-alvo-path "$_p"
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
  _ghs check --projeto-alvo-path "$_p"
  printf '%s\n' "$_CAPTURED_STDERR" | grep -q -- '--scope project' \
    || { _fail "stderr" "remediacao deve citar 'cstk install --scope project'"; return 1; }
  return 0
}

# ==== --quiet suprime stderr mas mantem TSV + exit ====

scenario_check_quiet_sem_stderr() {
  _p=$(_mkproj proj-quiet)
  _ghs check --projeto-alvo-path "$_p" --quiet
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDERR" ] || { _fail "stderr" "--quiet nao pode emitir stderr"; return 1; }
  [ -n "$_CAPTURED_STDOUT" ] || { _fail "stdout" "--quiet nao pode suprimir o TSV"; return 1; }
  return 0
}

# ==== INV-1: READ-ONLY ====

scenario_read_only_nao_cria_nada() {
  _p=$(_mkproj proj-readonly)
  _before=$(find "$_p" | sort)
  _ghs check --projeto-alvo-path "$_p"
  _ghs tick-mode --projeto-alvo-path "$_p"
  _after=$(find "$_p" | sort)
  [ "$_before" = "$_after" ] \
    || { _fail "read-only" "arvore do projeto-alvo mudou apos as consultas"; return 1; }
  return 0
}

# ==== INV-4: tick-mode ====

scenario_tick_mode_hook_quando_ativo() {
  _p=$(_mkproj proj-tick-hook)
  _fully_provisioned "$_p"
  _ghs tick-mode --projeto-alvo-path "$_p"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ "$_CAPTURED_STDOUT" = "hook" ] \
    || { _fail "stdout" "esperado 'hook', obtido '$_CAPTURED_STDOUT'"; return 1; }
  return 0
}

scenario_tick_mode_manual_quando_ausente() {
  _p=$(_mkproj proj-tick-manual)
  _ghs tick-mode --projeto-alvo-path "$_p"
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
  _ghs tick-mode --projeto-alvo-path "$_p"
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
  _ghs check --projeto-alvo-path "$_p"
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
  _ghs check --projeto-alvo-path "$_p"
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
  _ghs check --projeto-alvo-path "$_p"
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
  _ghs tick-mode --projeto-alvo-path "$_p"
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
  _ghs tick-mode --projeto-alvo-path "$_p"
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
  _ghs tick-mode --projeto-alvo-path "$_p"
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
  _ghs tick-mode --projeto-alvo-path "$_p"
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
  _ghs check --projeto-alvo-path "$_p" --include-loose-usage
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0 (hook opt-in ausente nao afeta exit), obtido $_CAPTURED_EXIT"; return 1; }
  printf '%s\n' "$_CAPTURED_STDOUT" | grep -q '^posttooluse-loose-usage.sh	missing	unregistered	' \
    || { _fail "TSV" "esperado 4a linha posttooluse-loose-usage.sh missing/unregistered"; return 1; }
  # 5a coluna = gate de ambiente (issue #162); _ghs pina a variavel vazia.
  printf '%s\n' "$_CAPTURED_STDOUT" | grep -q '^posttooluse-loose-usage.sh	missing	unregistered	unknown	endpoint-unset$' \
    || { _fail "TSV" "esperado 5a coluna endpoint-unset na linha loose: $_CAPTURED_STDOUT"; return 1; }
  # Hook ausente = opt-in nao exercido: NAO ha o que avisar sobre o gate.
  printf '%s\n' "$_CAPTURED_STDERR" | grep -q 'CSTK_OTEL_ENDPOINT' \
    && { _fail "stderr" "hook ausente nao deveria disparar aviso de gate"; return 1; }
  _n=$(printf '%s\n' "$_CAPTURED_STDOUT" | wc -l | tr -d ' ')
  [ "$_n" = 4 ] || { _fail "TSV" "esperado 4 linhas com --include-loose-usage, obtido $_n"; return 1; }
  return 0
}

# Sem a flag: saida byte-a-byte identica (retro-compat) — 3 linhas so.
scenario_loose_usage_sem_flag_saida_identica() {
  _p=$(_mkproj proj-loose-sem-flag)
  _fully_provisioned "$_p"
  _ghs check --projeto-alvo-path "$_p"
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
    -- plugins/cstk/skills/agente-00c-runtime/scripts/guard-hooks-status.sh | tail -1)
  if [ -z "$_intro" ]; then
    printf '# scenario_loose_usage_detection_stale_runtime: commit de introducao nao encontrado — pulando\n'
    return 0
  fi
  if ! git -C "$REPO_ROOT" show "${_intro}~1:plugins/cstk/skills/agente-00c-runtime/scripts/guard-hooks-status.sh" \
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

# ==== 5a coluna de GATE na linha de loose-usage (issue #162) ====
#
# Motivacao (issue #162): o hook gateia duro em CSTK_OTEL_ENDPOINT
# (posttooluse-loose-usage.sh, Passo 1) e sai 0 mudo sem ela. Antes desta
# coluna, present+registered+current descrevia um hook que capturava ZERO,
# sem nenhuma superficie para o operador enxergar isso — a mesma classe de
# falha silenciosa que motivou a 3a coluna (stale reportado como ativo).

# _provision_loose PAP -> hook opt-in presente E registrado (alem dos 3).
_provision_loose() {
  _pl_p=$1
  for _pl_h in $_HOOKS; do _put_hook "$_pl_p" "$_pl_h"; done
  _put_hook "$_pl_p" posttooluse-loose-usage.sh
  # shellcheck disable=SC2086
  _register "$_pl_p" $_HOOKS posttooluse-loose-usage.sh
}

# Hook provisionado + variavel AUSENTE => endpoint-unset + aviso no stderr,
# sem mexer no exit (opt-in nunca reprova a area).
scenario_loose_gate_endpoint_unset_avisa() {
  _p=$(_mkproj proj-loose-gate-unset)
  _provision_loose "$_p"
  _ghs check --projeto-alvo-path "$_p" --include-loose-usage
  [ "$_CAPTURED_EXIT" = 0 ] \
    || { _fail "exit" "gate inerte NAO pode mudar o exit (hook opt-in), obtido $_CAPTURED_EXIT"; return 1; }
  printf '%s\n' "$_CAPTURED_STDOUT" | grep -q '^posttooluse-loose-usage.sh	present	registered	current	endpoint-unset$' \
    || { _fail "TSV" "esperado endpoint-unset: $_CAPTURED_STDOUT"; return 1; }
  printf '%s\n' "$_CAPTURED_STDERR" | grep -q 'CSTK_OTEL_ENDPOINT' \
    || { _fail "stderr" "esperado aviso citando CSTK_OTEL_ENDPOINT: $_CAPTURED_STDERR"; return 1; }
  # O aviso precisa dizer o que o operador perde, nao so o nome da variavel.
  printf '%s\n' "$_CAPTURED_STDERR" | grep -q 'INERTE' \
    || { _fail "stderr" "aviso deveria explicitar que a captura fica INERTE"; return 1; }
  return 0
}

# Mesma provisao, variavel PRESENTE => endpoint-set e nenhum aviso.
scenario_loose_gate_endpoint_set_silencioso() {
  _p=$(_mkproj proj-loose-gate-set)
  _provision_loose "$_p"
  _ghs_endpoint 'http://127.0.0.1:41234/metrics' check --projeto-alvo-path "$_p" --include-loose-usage
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  printf '%s\n' "$_CAPTURED_STDOUT" | grep -q '^posttooluse-loose-usage.sh	present	registered	current	endpoint-set$' \
    || { _fail "TSV" "esperado endpoint-set: $_CAPTURED_STDOUT"; return 1; }
  printf '%s\n' "$_CAPTURED_STDERR" | grep -q 'CSTK_OTEL_ENDPOINT' \
    && { _fail "stderr" "com a variavel setada nao pode haver aviso de gate"; return 1; }
  return 0
}

# --quiet suprime o aviso (contrato geral do subcomando), mas NUNCA a coluna:
# o consumidor programatico (cli/lib/setup.sh) chama sempre com --quiet.
scenario_loose_gate_quiet_preserva_coluna() {
  _p=$(_mkproj proj-loose-gate-quiet)
  _provision_loose "$_p"
  _ghs check --projeto-alvo-path "$_p" --include-loose-usage --quiet
  printf '%s\n' "$_CAPTURED_STDOUT" | grep -q '	endpoint-unset$' \
    || { _fail "TSV" "--quiet nao pode suprimir a coluna de gate: $_CAPTURED_STDOUT"; return 1; }
  printf '%s\n' "$_CAPTURED_STDERR" | grep -q 'CSTK_OTEL_ENDPOINT' \
    && { _fail "stderr" "--quiet deveria suprimir o aviso"; return 1; }
  return 0
}

# --verify-registration continua NAO emitindo canonical/divergent para a
# linha de loose-usage: a 5a posicao dessa linha e, e segue sendo, o gate.
scenario_loose_gate_nao_vira_canonical_com_verify() {
  _p=$(_mkproj proj-loose-gate-verify)
  for _h in $_HOOKS; do _put_hook "$_p" "$_h"; done
  _put_hook "$_p" posttooluse-loose-usage.sh
  # shellcheck disable=SC2086
  _register_canonical "$_p" $_HOOKS posttooluse-loose-usage.sh
  _ghs check --projeto-alvo-path "$_p" --include-loose-usage --verify-registration
  printf '%s\n' "$_CAPTURED_STDOUT" | grep -q '^posttooluse-loose-usage.sh	present	registered	current	endpoint-unset$' \
    || { _fail "TSV" "linha loose deveria manter o gate na 5a coluna: $_CAPTURED_STDOUT"; return 1; }
  printf '%s\n' "$_CAPTURED_STDOUT" | grep -q '^posttooluse-loose-usage.sh.*canonical' \
    && { _fail "TSV" "linha loose nao pode ganhar canonical/divergent"; return 1; }
  return 0
}

# ==== --verify-registration (feature cstk-setup, FASE 2.2, FR-016, SEC-01) ====

scenario_verify_registration_canonical() {
  _p=$(_mkproj proj-verify-canonical)
  for _h in $_HOOKS; do _put_hook "$_p" "$_h"; done
  # shellcheck disable=SC2086
  _register_canonical "$_p" $_HOOKS
  _ghs check --projeto-alvo-path "$_p" --verify-registration
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
  _ghs check --projeto-alvo-path "$_p"
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
  _ghs check --projeto-alvo-path "$_p" --verify-registration --quiet
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
  _ghs check --projeto-alvo-path "$_p" --verify-registration --quiet
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
  _ghs check --projeto-alvo-path "$_p" --verify-registration
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
    -- plugins/cstk/skills/agente-00c-runtime/scripts/guard-hooks-status.sh | tail -1)
  if [ -z "$_intro" ]; then
    printf '# scenario_verify_registration_isolated_from_baseline: commit de introducao nao encontrado — pulando\n'
    return 0
  fi
  if ! git -C "$REPO_ROOT" show "${_intro}~1:plugins/cstk/skills/agente-00c-runtime/scripts/guard-hooks-status.sh" \
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
  cp "$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/_resolve-root.sh" "$_plugin_scripts/_resolve-root.sh"
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

# ==== INV-8: hooks providos pelo PLUGIN (v7+) ====
#
# Regressao do 3o modo de falha de campo: com o cstk instalado como plugin
# nativo, os 3 hooks sao registrados pelo hooks.json do plugin e NAO existe
# copia em <PAP>/.claude/hooks/ nem registro em <PAP>/.claude/settings.json.
# Antes deste fix o `check` acusava "3 de 3 NAO estao ativos" e o
# `tick-mode` devolvia "manual" — este ultimo fazendo o orquestrador tickar
# em paralelo ao hook, com `state-ondas.sh end` somando as duas fontes
# (tool_calls em DOBRO em toda onda).

# _fake_plugin_hooks_json HOOK... -> materializa um hooks.json de plugin
# citando os hooks passados e ecoa o path.
_fake_plugin_hooks_json() {
  _fpj_dir="$TMPDIR_TEST/fake-plugin-registry/hooks"
  mkdir -p "$_fpj_dir"
  {
    printf '{"hooks":{"PostToolUse":['
    _fpj_first=1
    for _fpj_h in "$@"; do
      [ "$_fpj_first" = 1 ] || printf ','
      _fpj_first=0
      printf '{"hooks":[{"type":"command","command":"sh \\"${CLAUDE_PLUGIN_ROOT}/skills/agente-00c-runtime/hooks/%s\\""}]}' "$_fpj_h"
    done
    printf ']}}'
  } > "$_fpj_dir/hooks.json"
  printf '%s' "$_fpj_dir/hooks.json"
}

# _ghs_plugin HOOKS_JSON ARGS... -> invoca o SCRIPT com plugin simulado.
_ghs_plugin() {
  _gp_json=$1
  shift
  capture env HOME="$TMPDIR_TEST/.home-sem-plugin" CLAUDE_PLUGIN_ROOT='' \
    CSTK_PLUGIN_HOOKS_JSON="$_gp_json" \
    CSTK_HOOKS_CATALOG_DIR="${CSTK_HOOKS_CATALOG_DIR:-}" \
    sh "$SCRIPT" "$@"
}

scenario_check_plugin_prove_hooks_exit0() {
  _p=$(_mkproj proj-plugin-only)
  # ZERO copia classica e ZERO settings.json — exatamente o layout v7+.
  # shellcheck disable=SC2086
  _pj=$(_fake_plugin_hooks_json $_HOOKS)
  _ghs_plugin "$_pj" check --projeto-alvo-path "$_p"
  [ "$_CAPTURED_EXIT" = 0 ] \
    || { _fail "exit" "esperado 0 (hooks providos pelo plugin), obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  _n=$(printf '%s\n' "$_CAPTURED_STDOUT" | grep -c '	present	registered	current$')
  [ "$_n" = 3 ] || { _fail "TSV" "esperado 3 linhas present/registered/current, stdout=$_CAPTURED_STDOUT"; return 1; }
  printf '%s\n' "$_CAPTURED_STDERR" | grep -q 'providos pelo PLUGIN' \
    || { _fail "stderr" "esperado aviso de origem plugin, stderr=$_CAPTURED_STDERR"; return 1; }
  # NAO pode mandar rodar `cstk hooks install` — o comando pula por dedup.
  printf '%s\n' "$_CAPTURED_STDERR" | grep -q 'cstk hooks install' \
    && { _fail "stderr" "nao deve sugerir remediacao quando o plugin ja prove"; return 1; }
  return 0
}

scenario_tick_mode_plugin_devolve_hook() {
  _p=$(_mkproj proj-plugin-tick)
  _pj=$(_fake_plugin_hooks_json posttooluse-tool-call-tick.sh)
  _ghs_plugin "$_pj" tick-mode --projeto-alvo-path "$_p"
  [ "$_CAPTURED_STDOUT" = "hook" ] \
    || { _fail "tick-mode" "esperado 'hook' (senao o orquestrador ticka em paralelo ao hook => tool_calls em dobro), obtido '$_CAPTURED_STDOUT'"; return 1; }
  return 0
}

scenario_tick_mode_sem_plugin_segue_manual() {
  # Guarda de nao-regressao do default seguro: sem plugin E sem copia
  # classica, continua "manual" (INV-4 intacto).
  _p=$(_mkproj proj-sem-nada)
  _pj="$TMPDIR_TEST/hooks-json-inexistente"
  _ghs_plugin "$_pj" tick-mode --projeto-alvo-path "$_p"
  [ "$_CAPTURED_STDOUT" = "manual" ] \
    || { _fail "tick-mode" "esperado 'manual', obtido '$_CAPTURED_STDOUT'"; return 1; }
  return 0
}

scenario_check_plugin_mais_classico_alerta_duplicidade() {
  # Plugin PROVE e a copia classica tambem esta registrada => o hook roda
  # duas vezes e cada tool call e contado em dobro.
  _p=$(_mkproj proj-dup)
  _fully_provisioned "$_p"
  # shellcheck disable=SC2086
  _pj=$(_fake_plugin_hooks_json $_HOOKS)
  _ghs_plugin "$_pj" check --projeto-alvo-path "$_p"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  printf '%s\n' "$_CAPTURED_STDERR" | grep -q 'contado em dobro' \
    || { _fail "stderr" "esperado alerta de duplicidade, stderr=$_CAPTURED_STDERR"; return 1; }
  return 0
}

scenario_check_plugin_quiet_sem_stderr() {
  # --quiet cala tambem o aviso de origem plugin (INV: quiet e quiet).
  _p=$(_mkproj proj-plugin-quiet)
  # shellcheck disable=SC2086
  _pj=$(_fake_plugin_hooks_json $_HOOKS)
  _ghs_plugin "$_pj" check --projeto-alvo-path "$_p" --quiet
  [ -z "$_CAPTURED_STDERR" ] \
    || { _fail "stderr" "esperado stderr vazio com --quiet, obtido: $_CAPTURED_STDERR"; return 1; }
  return 0
}

scenario_check_plugin_verify_registration_canonical() {
  # Com --verify-registration, hook provido pelo plugin e canonical por
  # construcao (o registro e o do proprio hooks.json do plugin).
  _p=$(_mkproj proj-plugin-vr)
  # shellcheck disable=SC2086
  _pj=$(_fake_plugin_hooks_json $_HOOKS)
  _ghs_plugin "$_pj" check --projeto-alvo-path "$_p" --verify-registration
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  _n=$(printf '%s\n' "$_CAPTURED_STDOUT" | grep -c '	canonical$')
  [ "$_n" = 3 ] || { _fail "TSV" "esperado 3 linhas canonical, stdout=$_CAPTURED_STDOUT"; return 1; }
  return 0
}

scenario_plugin_hooks_json_ilegivel_degrada() {
  # Override apontando para arquivo inexistente => "plugin nao prove",
  # comportamento anterior preservado byte-a-byte. Na duvida NUNCA se
  # afirma cobertura de plugin.
  _p=$(_mkproj proj-plugin-ilegivel)
  _ghs_plugin "$TMPDIR_TEST/nao-existe/hooks.json" check --projeto-alvo-path "$_p"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit" "esperado 1 (degrada p/ sem plugin), obtido $_CAPTURED_EXIT"; return 1; }
  _n=$(printf '%s\n' "$_CAPTURED_STDOUT" | grep -c 'missing	unregistered')
  [ "$_n" = 3 ] || { _fail "TSV" "esperado 3 missing/unregistered, stdout=$_CAPTURED_STDOUT"; return 1; }
  return 0
}

# ==== issue #135: registro em settings.local.json (`cstk hooks install --local`) ====
#
# Hooks SOMAM entre escopos no Claude Code — registro em
# <PAP>/.claude/settings.local.json ativa o hook exatamente como o
# settings.json. Se estes leitores ignorassem o arquivo local, `check`
# diria "unregistered" (falso), `tick-mode` diria "manual" e o orquestrador
# tickaria NA MAO por cima do hook ativo => contagem DUPLA de tool calls.

scenario_local_check_registrado_via_settings_local_exit0() {
  _p=$(_mkproj proj-local-ok)
  for _h in $_HOOKS; do _put_hook "$_p" "$_h"; done
  # shellcheck disable=SC2086
  _register "$_p" $_HOOKS
  mv "$_p/.claude/settings.json" "$_p/.claude/settings.local.json"
  _ghs check --projeto-alvo-path "$_p"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0 (registro local vale), obtido $_CAPTURED_EXIT"; return 1; }
  for _h in $_HOOKS; do
    printf '%s\n' "$_CAPTURED_STDOUT" | grep -q "^$_h	present	registered	current$" \
      || { _fail "TSV" "esperado '$_h present registered current' via settings.local.json"; return 1; }
  done
  return 0
}

scenario_local_tick_mode_hook_via_settings_local() {
  _p=$(_mkproj proj-local-tick)
  for _h in $_HOOKS; do _put_hook "$_p" "$_h"; done
  # shellcheck disable=SC2086
  _register "$_p" $_HOOKS
  mv "$_p/.claude/settings.json" "$_p/.claude/settings.local.json"
  _ghs tick-mode --projeto-alvo-path "$_p"
  [ "$_CAPTURED_STDOUT" = "hook" ] \
    || { _fail "stdout" "esperado 'hook' (registro local ativa o tick), obtido '$_CAPTURED_STDOUT'"; return 1; }
  return 0
}

scenario_local_verify_registration_canonical_via_settings_local() {
  _p=$(_mkproj proj-local-verify)
  for _h in $_HOOKS; do _put_hook "$_p" "$_h"; done
  # shellcheck disable=SC2086
  _register_canonical "$_p" $_HOOKS
  mv "$_p/.claude/settings.json" "$_p/.claude/settings.local.json"
  _ghs check --projeto-alvo-path "$_p" --verify-registration
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  for _h in $_HOOKS; do
    printf '%s\n' "$_CAPTURED_STDOUT" | grep -q "^$_h	present	registered	current	canonical$" \
      || { _fail "TSV" "esperado 'canonical' via settings.local.json para $_h"; return 1; }
  done
  return 0
}

# Registro divergente no arquivo LOCAL tambem reprova (a regra vale para os
# dois arquivos — um local desviando o command e a mesma linha-isca).
scenario_local_verify_registration_divergent_no_local_reprova() {
  _p=$(_mkproj proj-local-divergent)
  for _h in $_HOOKS; do _put_hook "$_p" "$_h"; done
  # shellcheck disable=SC2086
  _register_canonical "$_p" $_HOOKS
  printf '{\n  "hooks": {\n    "PreToolUse": [\n      {\n        "hooks": [\n          {\n            "type": "command",\n            "command": "/tmp/evil/pretooluse-bash-guard.sh"\n          }\n        ]\n      }\n    ]\n  }\n}\n' \
    > "$_p/.claude/settings.local.json"
  _ghs check --projeto-alvo-path "$_p" --verify-registration
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit" "esperado 1 (divergent no local), obtido $_CAPTURED_EXIT"; return 1; }
  printf '%s\n' "$_CAPTURED_STDOUT" | grep -q "^pretooluse-bash-guard.sh	present	registered	current	divergent$" \
    || { _fail "TSV" "esperado divergent para o guard: $_CAPTURED_STDOUT"; return 1; }
  return 0
}

run_all_scenarios
exit $?
