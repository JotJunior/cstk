#!/bin/sh
# test_statusline-plan-usage.sh — cobre
# plugins/cstk/skills/agente-00c-runtime/hooks/statusline-plan-usage.sh
# (entry-point de statusLine.command, feature plan-usage-capture) e o
# subcomando interno `cstk plan-usage ingest --stdin` (cli/lib/plan-usage.sh,
# task 4.3) que ele invoca via subprocesso.
#
# Contrato sob teste: docs/specs/plan-usage-capture/contracts/statusline-hook.md
# Cenarios: docs/specs/plan-usage-capture/quickstart.md
#
# Fail-open absoluto: o hook NUNCA sai com exit != 0, NUNCA imprime erro de
# diagnostico em stdout (so pass-through/fallback), e NUNCA toca sqlite3
# diretamente (persistencia delegada via subprocesso a `cstk plan-usage
# ingest --stdin`, research.md Decision 6).
#
# Sem sessao `claude` real (GOTCHA: statusline nao dispara em `claude -p`) —
# todo teste alimenta fixture via stdin (FR-012).

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/hooks/statusline-plan-usage.sh"

# _require_jq -> ERROR (skip) se jq indisponivel.
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

# _fixture_full -> payload com rate_limits.five_hour + seven_day completos
# (paridade literal com o schema OBSERVADO na memoria
# reference_statusline_usage_payload.md).
_fixture_full() {
  printf '{"session_id":"sess-1","workspace":{"current_dir":"%s"},"model":{"display_name":"Claude Opus 5"},"rate_limits":{"five_hour":{"used_percentage":7.000000000000001,"resets_at":1786372200},"seven_day":{"used_percentage":19,"resets_at":1786802400}}}' "$1"
}

# _fixture_no_rl PROJECT_PATH -> payload SEM a chave rate_limits (sessao
# sem nenhuma resposta de API completa ainda).
_fixture_no_rl() {
  printf '{"session_id":"sess-2","workspace":{"current_dir":"%s"},"model":{"display_name":"Claude"}}' "$1"
}

# _fixture_scope PROJECT_PATH USED RESETS -> payload so com five_hour.
_fixture_scope() {
  printf '{"session_id":"s","workspace":{"current_dir":"%s"},"rate_limits":{"five_hour":{"used_percentage":%s,"resets_at":%s}}}' "$1" "$2" "$3"
}

# _make_shim_with_cstk -> PATH shim contendo POSIX essenciais + jq/sqlite3
# (se disponiveis no ambiente real) + um wrapper `cstk` que exec's
# $REPO_ROOT/cli/cstk (layout de dev, CSTK_LIB auto-resolvido relativo a
# si mesmo — cli/cstk:_resolve_lib_dir).
_make_shim_with_cstk() {
  _shim="$TMPDIR_TEST/shimbin"
  mkdir -p "$_shim"
  for _cmd in sh mktemp awk sed grep find head printf cp mv rm mkdir \
              chmod ls dirname basename tr cut wc env command sort \
              uniq date cat cksum jq sqlite3; do
    _src=$(command -v "$_cmd" 2>/dev/null) || continue
    [ -n "$_src" ] || continue
    ln -sf "$_src" "$_shim/$_cmd" 2>/dev/null || :
  done
  cat > "$_shim/cstk" <<EOF
#!/bin/sh
exec "$REPO_ROOT/cli/cstk" "\$@"
EOF
  chmod +x "$_shim/cstk"
  printf '%s' "$_shim"
}

# _run_hook JSON [ENV...] -> invoca o script com JSON via stdin.
_run_hook() {
  _rh_json="$1"
  shift
  capture env "$@" sh -c 'printf "%s" "$1" | "$2"' _ "$_rh_json" "$SCRIPT"
}

# ---------------------------------------------------------------------------
# Task 2.1 — parse do payload e extracao de rate_limits
# ---------------------------------------------------------------------------

# Task 2.1.5: fixture com rate_limits completo extrai os 4 valores +
# session_id + project_path corretamente (introspeccao via CSTK_STATUSLINE_DEBUG).
scenario_extract_4_valores() {
  _require_jq || return 0
  mktemp_test
  _run_hook "$(_fixture_full /tmp/proj-x)" CSTK_STATUSLINE_DEBUG=1
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado exit=0, obtido $_CAPTURED_EXIT"; return 1; }
  case "$_CAPTURED_STDERR" in
    *"session_id=sess-1"*) ;;
    *) _fail "extract session_id" "obtido: $_CAPTURED_STDERR"; return 1 ;;
  esac
  case "$_CAPTURED_STDERR" in
    *"project_path=/tmp/proj-x"*) ;;
    *) _fail "extract project_path" "obtido: $_CAPTURED_STDERR"; return 1 ;;
  esac
  case "$_CAPTURED_STDERR" in
    *"five_hour.used=7.000000000000001"*) ;;
    *) _fail "extract five_hour.used" "obtido: $_CAPTURED_STDERR"; return 1 ;;
  esac
  case "$_CAPTURED_STDERR" in
    *"five_hour.resets=1786372200"*) ;;
    *) _fail "extract five_hour.resets" "obtido: $_CAPTURED_STDERR"; return 1 ;;
  esac
  case "$_CAPTURED_STDERR" in
    *"seven_day.used=19"*) ;;
    *) _fail "extract seven_day.used" "obtido: $_CAPTURED_STDERR"; return 1 ;;
  esac
  case "$_CAPTURED_STDERR" in
    *"seven_day.resets=1786802400"*) ;;
    *) _fail "extract seven_day.resets" "obtido: $_CAPTURED_STDERR"; return 1 ;;
  esac
  # Debug NUNCA vaza para stdout (2.4.3 — nao contamina a UI).
  case "$_CAPTURED_STDOUT" in
    *session_id=*) _fail "debug vazou p/ stdout" "obtido: $_CAPTURED_STDOUT"; return 1 ;;
  esac
  return 0
}

# Task 2.1.4: payload malformado -> pass-through best-effort, exit 0.
scenario_payload_malformado() {
  _require_jq || return 0
  mktemp_test
  capture sh -c 'printf "not json{{{" | "$1"' _ "$SCRIPT"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado exit=0, obtido $_CAPTURED_EXIT"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# Task 2.2 — semantica de ausencia (dec-029, core da feature)
# ---------------------------------------------------------------------------

# Task 2.2.4: fixture SEM rate_limits -> zero linhas novas em plan_usage.
scenario_ausencia_total_zero_linhas() {
  _require_jq || return 0
  _require_sqlite3 || return 0
  mktemp_test
  _shim=$(_make_shim_with_cstk)
  _db="$TMPDIR_TEST/k.db"
  _run_hook "$(_fixture_no_rl /tmp/p)" "PATH=$_shim:$PATH" "CSTK_KNOWLEDGE_DB=$_db"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado exit=0, obtido $_CAPTURED_EXIT"; return 1; }
  if [ -f "$_db" ]; then
    _n=$(sqlite3 "$_db" "SELECT count(*) FROM plan_usage;" 2>/dev/null) || _n=0
  else
    _n=0
  fi
  [ "$_n" = "0" ] || { _fail "ausencia total" "esperado 0 linhas, obtido $_n"; return 1; }
  return 0
}

# Task 2.2.1/2.2.5: rate_limits presente com os 2 escopos -> 2 linhas
# novas, valores batem com o fixture (Cenario 1 do quickstart).
scenario_captura_basica_2_linhas() {
  _require_jq || return 0
  _require_sqlite3 || return 0
  mktemp_test
  _shim=$(_make_shim_with_cstk)
  _db="$TMPDIR_TEST/k.db"
  _run_hook "$(_fixture_full /tmp/proj-y)" "PATH=$_shim:$PATH" "CSTK_KNOWLEDGE_DB=$_db"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado exit=0, obtido $_CAPTURED_EXIT"; return 1; }
  _n=$(sqlite3 "$_db" "SELECT count(*) FROM plan_usage;" 2>/dev/null) || _n=0
  [ "$_n" = "2" ] || { _fail "captura basica" "esperado 2 linhas, obtido $_n"; return 1; }
  _fh=$(sqlite3 "$_db" "SELECT used_percentage FROM plan_usage WHERE scope='five_hour';" 2>/dev/null)
  [ "$_fh" = "7.0" ] || { _fail "five_hour valor" "esperado 7.0 (exibicao CLI), obtido $_fh"; return 1; }
  _eq=$(sqlite3 "$_db" "SELECT used_percentage = 7.000000000000001 FROM plan_usage WHERE scope='five_hour';" 2>/dev/null)
  [ "$_eq" = "1" ] || { _fail "five_hour precisao" "used_percentage != 7.000000000000001 (ruido perdido)"; return 1; }
  return 0
}

# Task 2.2.2/2.2.3: escopo presente mas campos ausentes dentro dele ->
# NULL real, NUNCA 0 fabricado (Constitution VI).
scenario_ausencia_parcial_null_nunca_zero() {
  _require_jq || return 0
  _require_sqlite3 || return 0
  mktemp_test
  _shim=$(_make_shim_with_cstk)
  _db="$TMPDIR_TEST/k.db"
  _payload='{"session_id":"s","workspace":{"current_dir":"/tmp/p"},"rate_limits":{"five_hour":{}}}'
  _run_hook "$_payload" "PATH=$_shim:$PATH" "CSTK_KNOWLEDGE_DB=$_db"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado exit=0, obtido $_CAPTURED_EXIT"; return 1; }
  _row=$(sqlite3 "$_db" "SELECT (used_percentage IS NULL)||'|'||(resets_at IS NULL) FROM plan_usage WHERE scope='five_hour';" 2>/dev/null)
  [ "$_row" = "1|1" ] || { _fail "ausencia parcial NULL" "esperado 1|1, obtido $_row"; return 1; }
  _zero=$(sqlite3 "$_db" "SELECT count(*) FROM plan_usage WHERE used_percentage = 0;" 2>/dev/null)
  [ "$_zero" = "0" ] || { _fail "0 fabricado" "encontrada linha com used_percentage=0 (Constitution VI violada)"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# Task 2.3 — throttle (FR-010, dec-029/CHK010, dec-050)
# ---------------------------------------------------------------------------

# Task 2.3.5: 2 capturas identicas -> so 1 linha; 3a com mudanca so na 3a
# casa decimal -> ainda descartada; 4a com mudanca na 2a casa -> nova linha
# (paridade literal quickstart.md Cenario 3).
scenario_throttle_quickstart_cenario3() {
  _require_jq || return 0
  _require_sqlite3 || return 0
  mktemp_test
  _shim=$(_make_shim_with_cstk)
  _db="$TMPDIR_TEST/k.db"
  _run_hook "$(_fixture_scope /tmp/p 7.001 111)" "PATH=$_shim:$PATH" "CSTK_KNOWLEDGE_DB=$_db"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado exit=0, obtido $_CAPTURED_EXIT"; return 1; }
  _run_hook "$(_fixture_scope /tmp/p 7.001 111)" "PATH=$_shim:$PATH" "CSTK_KNOWLEDGE_DB=$_db"
  _run_hook "$(_fixture_scope /tmp/p 7.009 111)" "PATH=$_shim:$PATH" "CSTK_KNOWLEDGE_DB=$_db"
  _n1=$(sqlite3 "$_db" "SELECT count(*) FROM plan_usage;" 2>/dev/null)
  [ "$_n1" = "1" ] || { _fail "throttle passos 1-3" "esperado 1 linha, obtido $_n1"; return 1; }
  _run_hook "$(_fixture_scope /tmp/p 7.05 111)" "PATH=$_shim:$PATH" "CSTK_KNOWLEDGE_DB=$_db"
  _n2=$(sqlite3 "$_db" "SELECT count(*) FROM plan_usage;" 2>/dev/null)
  [ "$_n2" = "2" ] || { _fail "throttle passo 4" "esperado 2 linhas apos mudanca 2a casa, obtido $_n2"; return 1; }
  return 0
}

# dec-050 (residual CHK010/tasks.md 2.3.4): ULTIMO registro NULL/NULL e
# NOVA captura do MESMO escopo TAMBEM NULL/NULL -> conta como identico,
# descartada pelo throttle.
scenario_throttle_null_vs_null_dec050() {
  _require_jq || return 0
  _require_sqlite3 || return 0
  mktemp_test
  _shim=$(_make_shim_with_cstk)
  _db="$TMPDIR_TEST/k.db"
  _payload='{"session_id":"s","workspace":{"current_dir":"/tmp/p"},"rate_limits":{"five_hour":{}}}'
  _run_hook "$_payload" "PATH=$_shim:$PATH" "CSTK_KNOWLEDGE_DB=$_db"
  _n1=$(sqlite3 "$_db" "SELECT count(*) FROM plan_usage;" 2>/dev/null)
  _run_hook "$_payload" "PATH=$_shim:$PATH" "CSTK_KNOWLEDGE_DB=$_db"
  _n2=$(sqlite3 "$_db" "SELECT count(*) FROM plan_usage;" 2>/dev/null)
  [ "$_n1" = "$_n2" ] || { _fail "NULL-vs-NULL dec-050" "esperado throttle descartar (n1=$_n1 n2=$_n2)"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# Task 2.4 — pass-through obrigatorio do stdout
# ---------------------------------------------------------------------------

# Task 2.4.1: CSTK_STATUSLINE_INNER_COMMAND definida -> stdout do comando
# interno repassado verbatim, payload original intacto no stdin dele.
scenario_pass_through_inner_command() {
  _require_jq || return 0
  mktemp_test
  capture sh -c 'printf "%s" "$1" | CSTK_STATUSLINE_INNER_COMMAND="cat" "$2"' \
    _ "$(_fixture_full /tmp/p)" "$SCRIPT"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado exit=0, obtido $_CAPTURED_EXIT"; return 1; }
  case "$_CAPTURED_STDOUT" in
    *'"session_id":"sess-1"'*) ;;
    *) _fail "inner command verbatim" "obtido: $_CAPTURED_STDOUT"; return 1 ;;
  esac
  return 0
}

# Task 2.4.2: sem inner command -> fallback minimo de 1 linha, NUNCA vazio,
# construido so de model.display_name + five_hour.used_percentage.
scenario_pass_through_fallback_minimo() {
  _require_jq || return 0
  mktemp_test
  _run_hook "$(_fixture_full /tmp/p)"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado exit=0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -n "$_CAPTURED_STDOUT" ] || { _fail "fallback vazio" "stdout vazio"; return 1; }
  assert_stdout_contains "Claude Opus 5" || return 1
  assert_stdout_contains "7.000000000000001" || return 1
  return 0
}

# Task 2.4.4: em NENHUM cenario (dep ausente, malformado, throttle,
# insert ok) o script sai != 0 nem imprime erro de diagnostico em stdout.
scenario_nunca_erro_em_stdout() {
  mktemp_test
  capture sh -c 'printf "not json" | "$1"' _ "$SCRIPT"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado exit=0, obtido $_CAPTURED_EXIT"; return 1; }
  case "$_CAPTURED_STDOUT" in
    *rror*|*RROR*|*fail*|*FAIL*) _fail "erro vazou p/ stdout" "obtido: $_CAPTURED_STDOUT"; return 1 ;;
  esac
  return 0
}

# ---------------------------------------------------------------------------
# Task 2.5 — sqlite3/knowledge.db/jq indisponivel (Cenario 7 quickstart)
# ---------------------------------------------------------------------------

# Task 2.5.1/2.5.3: jq ausente -> pass-through normal, captura pulada, exit 0.
scenario_jq_ausente() {
  mktemp_test
  _shim="$TMPDIR_TEST/shim_no_jq"
  mkdir -p "$_shim"
  for _cmd in sh mktemp awk sed grep find head printf cp mv rm mkdir \
              chmod ls dirname basename tr cut wc env command sort \
              uniq date cat cksum sqlite3; do
    _src=$(command -v "$_cmd" 2>/dev/null) || continue
    [ -n "$_src" ] || continue
    ln -sf "$_src" "$_shim/$_cmd" 2>/dev/null || :
  done
  _run_hook "$(_fixture_full /tmp/p)" "PATH=$_shim"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado exit=0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -n "$_CAPTURED_STDOUT" ] || { _fail "sem fallback c/ jq ausente" "stdout vazio"; return 1; }
  return 0
}

# Task 2.5.1/2.5.3: cstk ausente do PATH (nao instalado) -> statusline
# segue funcionando normalmente (persistencia so pulada, pass-through
# intacto) — o hook NUNCA falha por causa do subprocesso de persistencia.
scenario_cstk_ausente() {
  _require_jq || return 0
  mktemp_test
  _shim="$TMPDIR_TEST/shim_no_cstk"
  mkdir -p "$_shim"
  for _cmd in sh mktemp awk sed grep find head printf cp mv rm mkdir \
              chmod ls dirname basename tr cut wc env command sort \
              uniq date cat cksum jq; do
    _src=$(command -v "$_cmd" 2>/dev/null) || continue
    [ -n "$_src" ] || continue
    ln -sf "$_src" "$_shim/$_cmd" 2>/dev/null || :
  done
  _run_hook "$(_fixture_full /tmp/p)" "PATH=$_shim"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado exit=0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "Claude Opus 5" || return 1
  return 0
}

run_all_scenarios
