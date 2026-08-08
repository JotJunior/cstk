#!/bin/sh
# test_posttooluse-loose-usage.sh — cobre
# global/skills/agente-00c-runtime/hooks/posttooluse-loose-usage.sh
# (hook PostToolUse OPT-IN de captura de consumo avulso).
#
# Contrato sob teste: docs/specs/loose-usage-capture/contracts/hook-loose-usage.md
#
# Fail-OPEN absoluto (mesma politica do molde posttooluse-tool-call-tick.sh):
# o hook NUNCA sai com exit != 0, NUNCA emite stdout/stderr, e o UNICO efeito
# permitido e escrita sob $HOME/.claude/cstk/loose-usage/. POLARIDADE
# INVERTIDA (dec-006) frente ao molde: aqui a captura acontece quando NAO ha
# execucao 00c ativa; quando ha, o hook so FECHA o segmento aberto.
#
# CRITICO: toda invocacao do hook nesta suite isola HOME em $TMPDIR_TEST —
# o script escreve sob $HOME/.claude/cstk/loose-usage/ e sem isolamento
# poluiria o home real da maquina.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/hooks/posttooluse-loose-usage.sh"

# Endpoint que falha rapido (nada escuta) — nunca precisa de exporter real;
# curl --max-time 3 contra porta fechada retorna connection-refused quase
# instantaneo (nao espera o teto).
_FAKE_ENDPOINT="http://127.0.0.1:19999/metrics"

# _run_hook JSON -> invoca o script com JSON via stdin, HOME isolado em
# $TMPDIR_TEST; herda o restante do ambiente (inclusive vars exportadas
# pelo scenario, ex: CSTK_OTEL_ENDPOINT/CSTK_LOOSE_USAGE_INTERVAL_S).
_run_hook() {
  capture env HOME="$TMPDIR_TEST" sh -c 'printf "%s" "$1" | "$2"' _ "$1" "$SCRIPT"
}

# _json_for CWD TOOL -> payload PostToolUse minimo do harness.
_json_for() {
  printf '{"cwd":"%s","hook_event_name":"PostToolUse","tool_name":"%s","tool_input":{}}' "$1" "$2"
}

# _require_jq -> ERROR (skip) se jq indisponivel neste ambiente de teste.
_require_jq() {
  command -v jq >/dev/null 2>&1 && return 0
  _error "no_jq" "jq indisponivel neste ambiente de teste"
  return 1
}

# _require_sqlite3 -> ERROR (skip) se sqlite3 indisponivel.
_require_sqlite3() {
  command -v sqlite3 >/dev/null 2>&1 && return 0
  _error "no_sqlite3" "sqlite3 indisponivel neste ambiente de teste"
  return 1
}

# _make_shim_path_no_jq: PATH controlado com POSIX essenciais + lsof/curl,
# SEM jq. Espelha o padrao de test_posttooluse-tool-call-tick.sh
# (_make_shim_path) com o binario extra que este hook usa (cksum).
_make_shim_path_no_jq() {
  _shim="$TMPDIR_TEST/shimbin"
  mkdir -p "$_shim"
  for _cmd in sh mktemp awk sed grep find head printf cp mv rm mkdir \
              chmod ls dirname basename tr cut wc env command sort \
              uniq date cat cksum lsof curl; do
    _src=$(command -v "$_cmd" 2>/dev/null) || continue
    [ -n "$_src" ] || continue
    ln -sf "$_src" "$_shim/$_cmd" 2>/dev/null || :
  done
  printf '%s' "$_shim"
}

# _loose_usage_root -> path do diretorio raiz do sidecar dentro do HOME
# isolado desta scenario.
_loose_usage_root() { printf '%s/.claude/cstk/loose-usage' "$TMPDIR_TEST"; }

# _find_meta_files -> lista meta.tsv sob a raiz isolada (0 ou mais linhas).
_find_meta_files() {
  find "$(_loose_usage_root)" -name 'meta.tsv' 2>/dev/null
}

# _file_mode PATH -> modo octal, portavel BSD/GNU (paridade tests/cstk/test_recall.sh).
_file_mode() {
  stat -c '%a' -- "$1" 2>/dev/null || stat -f '%Lp' -- "$1" 2>/dev/null
}

# _meta_get FILE FIELD -> valor da chave em meta.tsv.
_meta_get() {
  awk -F '\t' -v k="$2" '$1==k {print $2}' "$1" 2>/dev/null
}

# _active_agente_json CWD STATUS -> fixture agente-00c-state (backend JSON).
_active_agente_json() {
  mkdir -p "$1/.claude/agente-00c-state"
  printf '{"execution":{"status":"%s"}}' "$2" > "$1/.claude/agente-00c-state/state.json"
}

# ==== Cenario 1 (3.1.7): CSTK_OTEL_ENDPOINT ausente -> no-op total ====

scenario_endpoint_ausente_no_op() {
  unset CSTK_OTEL_ENDPOINT 2>/dev/null || :
  _run_hook "$(_json_for "$TMPDIR_TEST" "Bash")"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "esperado vazio: $_CAPTURED_STDOUT"; return 1; }
  [ -z "$_CAPTURED_STDERR" ] || { _fail "stderr" "esperado vazio: $_CAPTURED_STDERR"; return 1; }
  [ -d "$(_loose_usage_root)" ] && { _fail "sidecar" "sem endpoint NAO deveria criar diretorio algum"; return 1; }
  return 0
}

# ==== Cenario 2 (3.1.7): jq ausente -> no-op (fail-open, dep opcional) ====

scenario_jq_ausente_no_op() {
  export CSTK_OTEL_ENDPOINT="$_FAKE_ENDPOINT"
  _shim=$(_make_shim_path_no_jq)
  _json=$(_json_for "$TMPDIR_TEST" "Bash")
  capture env -i PATH="$_shim" HOME="$TMPDIR_TEST" CSTK_OTEL_ENDPOINT="$_FAKE_ENDPOINT" \
    sh -c 'printf "%s" "$1" | "$2"' _ "$_json" "$SCRIPT"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "fail-open exige exit 0 sem jq, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "esperado vazio: $_CAPTURED_STDOUT"; return 1; }
  [ -d "$(_loose_usage_root)" ] && { _fail "sidecar" "sem jq nao ha parse seguro -> sem captura"; return 1; }
  return 0
}

# ==== Cenario 3 (3.1.7): payload sem .cwd -> no-op ====

scenario_payload_sem_cwd_no_op() {
  _require_jq || return 2
  export CSTK_OTEL_ENDPOINT="$_FAKE_ENDPOINT"
  _run_hook '{"hook_event_name":"PostToolUse","tool_name":"Bash"}'
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -d "$(_loose_usage_root)" ] && { _fail "sidecar" "payload sem cwd nao pode gerar captura"; return 1; }
  return 0
}

# ==== Cenario 3b (3.1.7): payload sem .tool_name -> no-op ====

scenario_payload_sem_tool_name_no_op() {
  _require_jq || return 2
  export CSTK_OTEL_ENDPOINT="$_FAKE_ENDPOINT"
  _run_hook "{\"cwd\":\"$TMPDIR_TEST\",\"hook_event_name\":\"PostToolUse\"}"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -d "$(_loose_usage_root)" ] && { _fail "sidecar" "payload sem tool_name nao pode gerar captura"; return 1; }
  return 0
}

# ==== Cenario 4 (3.1.7): execucao INATIVA -> captura (processo novo) ====

scenario_execucao_inativa_captura_processo_novo() {
  _require_jq || return 2
  export CSTK_OTEL_ENDPOINT="$_FAKE_ENDPOINT"
  _proj="$TMPDIR_TEST/proj"
  mkdir -p "$_proj"
  _run_hook "$(_json_for "$_proj" "Bash")"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "esperado vazio: $_CAPTURED_STDOUT"; return 1; }
  [ -z "$_CAPTURED_STDERR" ] || { _fail "stderr" "esperado vazio: $_CAPTURED_STDERR"; return 1; }
  _meta=$(_find_meta_files)
  [ -n "$_meta" ] || { _fail "sidecar" "esperado meta.tsv criado sob $(_loose_usage_root)"; return 1; }
  [ "$(printf '%s\n' "$_meta" | wc -l | tr -d ' ')" = 1 ] || { _fail "sidecar" "esperado exatamente 1 meta.tsv, obtido: $_meta"; return 1; }
  _seg=$(_meta_get "$_meta" current_segment)
  [ "$_seg" = "seg-001" ] || { _fail "segmento" "esperado current_segment=seg-001, obtido: $_seg"; return 1; }
  _procdir=$(dirname "$_meta")
  [ -d "$_procdir/seg-001" ] || { _fail "segmento" "diretorio seg-001 nao foi criado"; return 1; }
  _owner=$(_meta_get "$_meta" owner_pid)
  [ -n "$_owner" ] || { _fail "owner_pid" "campo owner_pid ausente (deveria ser PID ou 'unknown', nunca vazio)"; return 1; }
  return 0
}

# ==== Cenario 5 (3.1.7): throttle nao vencido -> no-op (updated_at intacto) ====

scenario_throttle_nao_vencido_no_op() {
  _require_jq || return 2
  export CSTK_OTEL_ENDPOINT="$_FAKE_ENDPOINT"
  _proj="$TMPDIR_TEST/proj"
  mkdir -p "$_proj"
  # Primeira captura, sem throttle (interval=0 forca passagem imediata).
  export CSTK_LOOSE_USAGE_INTERVAL_S=0
  _run_hook "$(_json_for "$_proj" "Bash")"
  _meta=$(_find_meta_files)
  [ -n "$_meta" ] || { _error "fixture" "primeira captura nao produziu meta.tsv"; return 2; }
  _updated_before=$(_meta_get "$_meta" updated_at)

  # Segunda invocacao: interval default (300s) reimposto -> throttle ativo.
  unset CSTK_LOOSE_USAGE_INTERVAL_S 2>/dev/null || :
  _run_hook "$(_json_for "$_proj" "Read")"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  _updated_after=$(_meta_get "$_meta" updated_at)
  [ "$_updated_before" = "$_updated_after" ] || { _fail "throttle" "updated_at mudou apesar do throttle (antes=$_updated_before depois=$_updated_after)"; return 1; }
  [ ! -d "$(dirname "$_meta")/seg-002" ] || { _fail "throttle" "novo segmento nao deveria ter sido criado sob throttle"; return 1; }
  return 0
}

# ==== Cenario 6 (3.1.7): execucao ATIVA -> fecha segmento, nao captura ====

scenario_execucao_ativa_fecha_segmento() {
  _require_jq || return 2
  export CSTK_OTEL_ENDPOINT="$_FAKE_ENDPOINT"
  _proj="$TMPDIR_TEST/proj"
  mkdir -p "$_proj"

  # Abre um segmento primeiro (execucao inativa, throttle desarmado).
  export CSTK_LOOSE_USAGE_INTERVAL_S=0
  _run_hook "$(_json_for "$_proj" "Bash")"
  _meta=$(_find_meta_files)
  [ -n "$_meta" ] || { _error "fixture" "captura inicial nao produziu meta.tsv"; return 2; }
  _procdir=$(dirname "$_meta")
  [ ! -f "$_procdir/seg-001/closed" ] || { _error "fixture" "segmento ja nasceu fechado (inesperado)"; return 2; }
  _updated_before=$(_meta_get "$_meta" updated_at)

  # Agora marca execucao 00c ATIVA no mesmo cwd e dispara novo tick.
  _active_agente_json "$_proj" "em_andamento"
  _run_hook "$(_json_for "$_proj" "Bash")"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "esperado vazio: $_CAPTURED_STDOUT"; return 1; }
  [ -f "$_procdir/seg-001/closed" ] || { _fail "fechamento" "esperado marcador 'closed' em seg-001 apos tick ativo"; return 1; }
  [ ! -d "$_procdir/seg-002" ] || { _fail "fechamento" "execucao ativa NAO deveria abrir seg-002 (so fecha, nao captura)"; return 1; }
  _updated_after=$(_meta_get "$_meta" updated_at)
  [ "$_updated_before" = "$_updated_after" ] || { _fail "fechamento" "updated_at NAO deveria mudar ao fechar (fechar nao e captura)"; return 1; }
  return 0
}

# ==== Cenario 7 (3.1.7): fechado + INATIVA -> abre novo segmento ====

scenario_segmento_fechado_reabre_novo() {
  _require_jq || return 2
  export CSTK_OTEL_ENDPOINT="$_FAKE_ENDPOINT"
  _proj="$TMPDIR_TEST/proj"
  mkdir -p "$_proj"

  export CSTK_LOOSE_USAGE_INTERVAL_S=0
  _run_hook "$(_json_for "$_proj" "Bash")"
  _meta=$(_find_meta_files)
  [ -n "$_meta" ] || { _error "fixture" "captura inicial nao produziu meta.tsv"; return 2; }
  _procdir=$(dirname "$_meta")

  _active_agente_json "$_proj" "em_andamento"
  _run_hook "$(_json_for "$_proj" "Bash")"
  [ -f "$_procdir/seg-001/closed" ] || { _error "fixture" "fechamento do seg-001 nao ocorreu"; return 2; }

  # Remove a fixture de execucao ativa -> volta a inativa.
  rm -rf "$_proj/.claude/agente-00c-state"
  _run_hook "$(_json_for "$_proj" "Write")"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -d "$_procdir/seg-002" ] || { _fail "reabertura" "esperado novo segmento seg-002 apos fechamento"; return 1; }
  _seg=$(_meta_get "$_meta" current_segment)
  [ "$_seg" = "seg-002" ] || { _fail "reabertura" "esperado current_segment=seg-002, obtido: $_seg"; return 1; }
  return 0
}

# ==== Cenario 8 (3.1.7): estado indeterminada (state.db corrompido) -> no-op ====

scenario_indeterminada_state_db_corrompido_no_op() {
  _require_jq || return 2
  _require_sqlite3 || return 2
  export CSTK_OTEL_ENDPOINT="$_FAKE_ENDPOINT"
  _proj="$TMPDIR_TEST/proj"
  mkdir -p "$_proj/.claude/agente-00c-state"
  printf 'not a database' > "$_proj/.claude/agente-00c-state/state.db"
  _run_hook "$(_json_for "$_proj" "Bash")"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "esperado vazio: $_CAPTURED_STDOUT"; return 1; }
  [ -z "$_CAPTURED_STDERR" ] || { _fail "stderr" "esperado vazio: $_CAPTURED_STDERR"; return 1; }
  [ -d "$(_loose_usage_root)" ] && { _fail "sidecar" "state indeterminado NUNCA vira captura (Constitution VI)"; return 1; }
  return 0
}

# ==== 3.2.3: permissoes restritivas apos captura bem-sucedida (CHK021) ====

scenario_permissoes_apos_captura() {
  _require_jq || return 2
  export CSTK_OTEL_ENDPOINT="$_FAKE_ENDPOINT"
  _proj="$TMPDIR_TEST/proj"
  mkdir -p "$_proj"
  _run_hook "$(_json_for "$_proj" "Bash")"
  _meta=$(_find_meta_files)
  [ -n "$_meta" ] || { _error "fixture" "captura nao produziu meta.tsv"; return 2; }
  _procdir=$(dirname "$_meta")
  _root=$(_loose_usage_root)

  [ "$(_file_mode "$_root")" = "700" ] || { _fail "modo raiz" "esperado 700, obtido $(_file_mode "$_root")"; return 1; }
  [ "$(_file_mode "$_procdir")" = "700" ] || { _fail "modo processo" "esperado 700, obtido $(_file_mode "$_procdir")"; return 1; }
  [ "$(_file_mode "$_procdir/seg-001")" = "700" ] || { _fail "modo segmento" "esperado 700, obtido $(_file_mode "$_procdir/seg-001")"; return 1; }
  [ "$(_file_mode "$_meta")" = "600" ] || { _fail "modo meta.tsv" "esperado 600, obtido $(_file_mode "$_meta")"; return 1; }
  return 0
}

# ==== FASE 3.2 (claude-plugin-packaging) — candidato ${CLAUDE_PLUGIN_ROOT} ====
#
# Task 3.2.2: adotar `_resolve-root.sh` (Ordem A, fail-open). Isola o hook
# num diretorio SEM sibling scripts/ algum, com ${CLAUDE_PLUGIN_ROOT}
# apontando para uma raiz fake contendo o bootstrap (_resolve-root.sh) +
# otel-usage.sh reais — confirma que a captura funciona mesmo quando o
# runtime so e alcancavel via plugin.

scenario_plugin_root_resolve_otel_usage_via_claude_plugin_root() {
  _require_jq || return 2
  _isolated="$TMPDIR_TEST/isolated-plugin/hooks"
  mkdir -p "$_isolated"
  cp "$SCRIPT" "$_isolated/posttooluse-loose-usage.sh"
  chmod +x "$_isolated/posttooluse-loose-usage.sh"

  _plugin_root="$TMPDIR_TEST/fake-plugin/skills/agente-00c-runtime/scripts"
  mkdir -p "$_plugin_root"
  cp "$REPO_ROOT/global/skills/agente-00c-runtime/scripts/_resolve-root.sh" "$_plugin_root/_resolve-root.sh"
  cp "$REPO_ROOT/global/skills/agente-00c-runtime/scripts/otel-usage.sh" "$_plugin_root/otel-usage.sh"
  chmod +x "$_plugin_root/otel-usage.sh"

  export CSTK_OTEL_ENDPOINT="$_FAKE_ENDPOINT"
  _proj="$TMPDIR_TEST/proj-plugin"
  mkdir -p "$_proj"
  _json=$(_json_for "$_proj" "Bash")
  capture env HOME="$TMPDIR_TEST" CLAUDE_PLUGIN_ROOT="$TMPDIR_TEST/fake-plugin" \
    sh -c 'printf "%s" "$1" | "$2"' _ "$_json" "$_isolated/posttooluse-loose-usage.sh"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "esperado vazio: $_CAPTURED_STDOUT"; return 1; }
  [ -z "$_CAPTURED_STDERR" ] || { _fail "stderr" "esperado vazio: $_CAPTURED_STDERR"; return 1; }
  _meta=$(_find_meta_files)
  [ -n "$_meta" ] || { _fail "sidecar" "esperado meta.tsv (otel-usage.sh resolvido via plugin root)"; return 1; }
}

run_all_scenarios
exit $?
