#!/bin/sh
# test_otel-usage.sh — cobre
# plugins/cstk/skills/agente-00c-runtime/scripts/otel-usage.sh
#
# Invariantes sob teste:
#   INV-1: PRIVACIDADE — nenhum label de PII (user_email, user_id,
#          user_account_*, organization_id) alcanca o snapshot em disco.
#   INV-2: o label `type` e extraido ANCORADO. Sem ancoragem, `type="`
#          casa antes com `terminal_type="ghostty"` (substring) e o
#          breakdown por tipo vira o nome do terminal — bug observado em
#          dados reais antes do fix.
#   INV-3: metrica AUSENTE e `null`, nunca zero fabricado (Principio VI).
#          Vale para snapshot faltando, endpoint fora do ar, sessao do
#          start sumida no end (processo do exporter trocou), mais de uma
#          sessao ativa entre os snapshots (atribuicao ambigua) e
#          snapshot em formato antigo (4 colunas, pre-fix).
#   INV-4: degradacao best-effort — endpoint indisponivel sai 0 e nao
#          derruba a onda.
#   INV-5: `available` exige as metricas que o script consome
#          (cost/token), nao um `claude_code_` qualquer — no cold start o
#          exporter ja responde com session_count e o snapshot sairia sem
#          session_id, descartando a onda inteira.
#   INV-6: duplicatas da mesma chave (session, source, model, type) sao
#          SOMADAS nos dois lados do join, nunca sobrescritas. O exporter
#          emite linhas separadas por agent_name/skill_name/effort; o awk
#          antigo fazia s[k]=$4 (ultima vence) e imprimia CADA duplicata
#          do end contra essa base unica — o "delta" virava ~acumulado
#          congelado. Bug real 2026-07-28 (feature-00c dashboard-refactor):
#          14 ondas bit-identicas de 212.447.680 tokens / $88.
#   INV-7: linhas de OUTRAS sessoes do mesmo exporter (processo claude -c
#          longevo expoe mais de uma sessao) nao contaminam o delta: a
#          sessao congelada e ignorada e o resultado e atribuido a UNICA
#          sessao que cresceu entre os snapshots.
#
# As fixtures reproduzem o formato REAL do exporter Prometheus do Claude
# Code 2.1.220 (ordem dos labels inclusive — `terminal_type` antes de
# `type` e o que dispara INV-2). Os valores de identidade sao anonimizados
# de proposito: fixture de teste nao carrega PII de ninguem.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/otel-usage.sh"

if ! command -v jq >/dev/null 2>&1; then
  printf '# test_otel-usage.sh: jq ausente — pulando suite\n'
  exit 0
fi
if ! command -v curl >/dev/null 2>&1; then
  printf '# test_otel-usage.sh: curl ausente — pulando suite\n'
  exit 0
fi

# _labels SESSION QSOURCE MODEL [EXTRA] -> bloco de labels na ORDEM REAL do
# exporter. `terminal_type` vem antes de `type` de proposito (INV-2).
_labels() {
  printf 'user_id="anon-hash",session_id="%s",organization_id="anon-org",' "$1"
  printf 'user_email="anon@example.invalid",user_account_uuid="anon-uuid",'
  printf 'user_account_id="anon-acct",terminal_type="ghostty",'
  printf 'model="%s",query_source="%s"%s' "$3" "$2" "${4:-}"
  printf ',otel_scope_name="com.anthropic.claude_code",otel_scope_version="2.1.220"'
}

# _fixture FILE SESSION COST_MAIN COST_SUB IN_MAIN OUT_MAIN
_fixture() {
  _fx=$1; _sid=$2; _cm=$3; _cs=$4; _im=$5; _om=$6
  {
    printf 'claude_code_cost_usage_total{%s} %s\n'  "$(_labels "$_sid" main     "claude-opus-5[1m]")" "$_cm"
    printf 'claude_code_cost_usage_total{%s} %s\n'  "$(_labels "$_sid" subagent "claude-opus-5[1m]")" "$_cs"
    printf 'claude_code_token_usage_total{%s} %s\n' "$(_labels "$_sid" main "claude-opus-5[1m]" ',type="input"')"  "$_im"
    printf 'claude_code_token_usage_total{%s} %s\n' "$(_labels "$_sid" main "claude-opus-5[1m]" ',type="output"')" "$_om"
  } > "$_fx"
}

_snap() {
  # $1=state-dir $2=phase $3=fixture-file
  capture sh "$SCRIPT" snapshot --state-dir "$1" --phase "$2" --endpoint "file://$3"
}

# Linhas avulsas para fixtures multi-sessao / com duplicata de chave.
# _cost_line SID SOURCE MODEL VALUE [EXTRA_LABELS]
_cost_line() {
  printf 'claude_code_cost_usage_total{%s} %s\n' \
    "$(_labels "$1" "$2" "$3" "${5:-}")" "$4"
}
# _tok_line SID SOURCE MODEL TYPE VALUE [EXTRA_LABELS]
_tok_line() {
  printf 'claude_code_token_usage_total{%s} %s\n' \
    "$(_labels "$1" "$2" "$3" ",type=\"$4\"${6:-}")" "$5"
}

# ==== INV-2: ancoragem do label `type` ====

scenario_type_nao_colide_com_terminal_type() {
  _sd="$TMPDIR_TEST/anchor"; mkdir -p "$_sd"
  _fx="$TMPDIR_TEST/anchor.txt"
  _fixture "$_fx" "sess-1" 1.0 0.5 100 20
  _snap "$_sd" end "$_fx"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "snapshot exit" "$_CAPTURED_EXIT / $_CAPTURED_STDERR"; return 1; }
  grep -q "	input	100$" "$_sd/otel-end.tsv" \
    || { _fail "type=input" "esperado linha com type input; obtido: $(cat "$_sd/otel-end.tsv")"; return 1; }
  grep -q "	output	20$" "$_sd/otel-end.tsv" \
    || { _fail "type=output" "esperado linha com type output"; return 1; }
  # O valor do terminal JAMAIS pode aparecer como tipo de token.
  grep -q "ghostty" "$_sd/otel-end.tsv" \
    && { _fail "colisao terminal_type" "'ghostty' vazou para o campo type"; return 1; }
  return 0
}

# ==== INV-1: privacidade ====

scenario_pii_nunca_alcanca_o_snapshot() {
  _sd="$TMPDIR_TEST/pii"; mkdir -p "$_sd"
  _fx="$TMPDIR_TEST/pii.txt"
  _fixture "$_fx" "sess-pii" 1.0 0.5 100 20
  _snap "$_sd" end "$_fx"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "snapshot exit" "$_CAPTURED_EXIT"; return 1; }
  for _lbl in user_id user_email user_account_uuid user_account_id organization_id anon@example.invalid anon-hash anon-org; do
    grep -q "$_lbl" "$_sd/otel-end.tsv" \
      && { _fail "PII" "'$_lbl' vazou para o snapshot"; return 1; }
  done
  return 0
}

# ==== delta: aritmetica ====

scenario_delta_subtrai_contadores_cumulativos() {
  _sd="$TMPDIR_TEST/delta"; mkdir -p "$_sd"
  _fs="$TMPDIR_TEST/d-start.txt"; _fe="$TMPDIR_TEST/d-end.txt"
  _fixture "$_fs" "sess-d" 1.0 0.5 100 20
  _fixture "$_fe" "sess-d" 3.0 2.0 400 60
  _snap "$_sd" start "$_fs"
  _snap "$_sd" end   "$_fe"
  capture sh "$SCRIPT" delta --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "delta exit" "$_CAPTURED_EXIT / $_CAPTURED_STDERR"; return 1; }
  _main=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.by_source.main.cost_usd')
  _sub=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.by_source.subagent.cost_usd')
  _in=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.by_source.main.input')
  [ "$_main" = "2" ] || { _fail "delta main cost" "esperado 2 (3.0-1.0), obtido $_main"; return 1; }
  [ "$_sub" = "1.5" ] || { _fail "delta subagent cost" "esperado 1.5 (2.0-0.5), obtido $_sub"; return 1; }
  [ "$_in" = "300" ] || { _fail "delta main input" "esperado 300 (400-100), obtido $_in"; return 1; }
  return 0
}

# Subagente e o recorte que motivou a feature — precisa vir separado.
scenario_delta_separa_subagente_de_main() {
  _sd="$TMPDIR_TEST/split"; mkdir -p "$_sd"
  _fs="$TMPDIR_TEST/s-start.txt"; _fe="$TMPDIR_TEST/s-end.txt"
  _fixture "$_fs" "sess-s" 0 0 0 0
  _fixture "$_fe" "sess-s" 1.0 9.0 10 5
  _snap "$_sd" start "$_fs"
  _snap "$_sd" end   "$_fe"
  capture sh "$SCRIPT" delta --state-dir "$_sd"
  _keys=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.by_source | keys | join(",")')
  case "$_keys" in
    *subagent*) : ;;
    *) _fail "by_source" "esperado recorte subagent; obtido '$_keys'"; return 1 ;;
  esac
  _sub=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.by_source.subagent.cost_usd')
  [ "$_sub" = "9" ] || { _fail "subagent cost" "esperado 9, obtido $_sub"; return 1; }
  return 0
}

# Contador reiniciado nao pode virar delta negativo.
scenario_delta_negativo_e_clampado() {
  _sd="$TMPDIR_TEST/neg"; mkdir -p "$_sd"
  _fs="$TMPDIR_TEST/n-start.txt"; _fe="$TMPDIR_TEST/n-end.txt"
  _fixture "$_fs" "sess-n" 5.0 5.0 500 50
  _fixture "$_fe" "sess-n" 1.0 1.0 100 10
  _snap "$_sd" start "$_fs"
  _snap "$_sd" end   "$_fe"
  capture sh "$SCRIPT" delta --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "delta exit" "$_CAPTURED_EXIT"; return 1; }
  # Todos os deltas <= 0 sao descartados => nada sobra => null.
  [ "$(printf '%s' "$_CAPTURED_STDOUT" | tr -d '[:space:]')" = "null" ] \
    || { _fail "clamp" "esperado null (nenhum delta positivo), obtido '$_CAPTURED_STDOUT'"; return 1; }
  return 0
}

# ==== INV-6: duplicatas da mesma chave sao somadas, nunca sobrescritas ====

scenario_delta_soma_duplicatas_da_mesma_chave() {
  _sd="$TMPDIR_TEST/dup"; mkdir -p "$_sd"
  _fs="$TMPDIR_TEST/dup-s.txt"; _fe="$TMPDIR_TEST/dup-e.txt"
  # Mesma chave (sess, subagent, sonnet, cacheRead) em DUAS linhas que so
  # diferem no agent_name — exatamente o que o exporter real emite.
  {
    _tok_line sess-dup subagent "claude-sonnet-5" cacheRead 100 ',agent_name="general-purpose"'
    _tok_line sess-dup subagent "claude-sonnet-5" cacheRead 200 ',agent_name="custom"'
  } > "$_fs"
  {
    _tok_line sess-dup subagent "claude-sonnet-5" cacheRead 150 ',agent_name="general-purpose"'
    _tok_line sess-dup subagent "claude-sonnet-5" cacheRead 400 ',agent_name="custom"'
  } > "$_fe"
  _snap "$_sd" start "$_fs"
  _snap "$_sd" end   "$_fe"
  capture sh "$SCRIPT" delta --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "delta exit" "$_CAPTURED_EXIT / $_CAPTURED_STDERR"; return 1; }
  _tot=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.total_tokens')
  # (150+400) - (100+200) = 250. Com sobrescrita, sairia 200 (400-200,
  # com a duplicata de 150 clampada contra base errada de 200).
  [ "$_tot" = "250" ] || { _fail "soma duplicatas" "esperado 250, obtido '$_tot'"; return 1; }
  _cr=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.by_source.subagent.cache_read')
  [ "$_cr" = "250" ] || { _fail "cache_read" "esperado 250, obtido '$_cr'"; return 1; }
  return 0
}

# ==== INV-7: isolamento por sessao dentro do mesmo exporter ====

# Reproducao do bug real (2026-07-28): exporter de um processo claude -c
# longevo expoe uma sessao antiga CONGELADA com acumulado gigante ao lado
# da sessao corrente. O acumulado nao pode vazar para o delta da onda.
scenario_delta_ignora_sessao_congelada_de_outro_processo() {
  _sd="$TMPDIR_TEST/frozen"; mkdir -p "$_sd"
  _fs="$TMPDIR_TEST/fz-s.txt"; _fe="$TMPDIR_TEST/fz-e.txt"
  {
    _tok_line sess-old main "claude-opus-5[1m]" input 212000000
    _cost_line sess-old main "claude-opus-5[1m]" 88.0
    _tok_line sess-cur main "claude-opus-5[1m]" input 100
    _cost_line sess-cur main "claude-opus-5[1m]" 1.0
  } > "$_fs"
  {
    _tok_line sess-old main "claude-opus-5[1m]" input 212000000
    _cost_line sess-old main "claude-opus-5[1m]" 88.0
    _tok_line sess-cur main "claude-opus-5[1m]" input 400
    _cost_line sess-cur main "claude-opus-5[1m]" 2.5
  } > "$_fe"
  _snap "$_sd" start "$_fs"
  _snap "$_sd" end   "$_fe"
  capture sh "$SCRIPT" delta --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "delta exit" "$_CAPTURED_EXIT / $_CAPTURED_STDERR"; return 1; }
  _tot=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.total_tokens')
  [ "$_tot" = "300" ] || { _fail "tokens da onda" "esperado 300 (so a sessao corrente), obtido '$_tot'"; return 1; }
  _cost=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.total_cost_usd')
  [ "$_cost" = "1.5" ] || { _fail "custo da onda" "esperado 1.5, obtido '$_cost'"; return 1; }
  _sid=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.session_id')
  [ "$_sid" = "sess-cur" ] || { _fail "atribuicao" "esperado sess-cur, obtido '$_sid'"; return 1; }
  return 0
}

# Duas sessoes crescendo ao mesmo tempo: impossivel atribuir a onda a uma
# delas — melhor ausente que errado (Principio VI).
scenario_delta_duas_sessoes_ativas_e_null() {
  _sd="$TMPDIR_TEST/ambig"; mkdir -p "$_sd"
  _fs="$TMPDIR_TEST/am-s.txt"; _fe="$TMPDIR_TEST/am-e.txt"
  {
    _tok_line sess-a main "claude-opus-5[1m]" input 100
    _tok_line sess-b main "claude-opus-5[1m]" input 500
  } > "$_fs"
  {
    _tok_line sess-a main "claude-opus-5[1m]" input 300
    _tok_line sess-b main "claude-opus-5[1m]" input 900
  } > "$_fe"
  _snap "$_sd" start "$_fs"
  _snap "$_sd" end   "$_fe"
  capture sh "$SCRIPT" delta --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT"; return 1; }
  [ "$(printf '%s' "$_CAPTURED_STDOUT" | tr -d '[:space:]')" = "null" ] \
    || { _fail "null" "duas sessoes ativas deve dar null, obtido '$_CAPTURED_STDOUT'"; return 1; }
  printf '%s' "$_CAPTURED_STDERR" | grep -q "ambigua" \
    || { _fail "stderr" "faltou aviso de atribuicao ambigua"; return 1; }
  return 0
}

# Sessao que nasce DEPOIS do snapshot inicial (ex.: nova conversa no mesmo
# processo): todo o consumo dela aconteceu dentro da janela da onda, entao
# conta a partir de base 0 — desde que seja a unica que cresceu.
scenario_delta_sessao_nova_no_end_atribuida_do_zero() {
  _sd="$TMPDIR_TEST/newsess"; mkdir -p "$_sd"
  _fs="$TMPDIR_TEST/nw-s.txt"; _fe="$TMPDIR_TEST/nw-e.txt"
  _tok_line sess-a main "claude-opus-5[1m]" input 100 > "$_fs"
  {
    _tok_line sess-a main "claude-opus-5[1m]" input 100
    _tok_line sess-b main "claude-opus-5[1m]" input 50
  } > "$_fe"
  _snap "$_sd" start "$_fs"
  _snap "$_sd" end   "$_fe"
  capture sh "$SCRIPT" delta --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT"; return 1; }
  _tot=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.total_tokens')
  [ "$_tot" = "50" ] || { _fail "sessao nova" "esperado 50, obtido '$_tot'"; return 1; }
  _sid=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.session_id')
  [ "$_sid" = "sess-b" ] || { _fail "atribuicao" "esperado sess-b, obtido '$_sid'"; return 1; }
  return 0
}

# Transicao de upgrade: snapshot start gravado pela versao antiga (4
# colunas, sem session_id por linha) nao permite delta confiavel.
scenario_delta_snapshot_legado_4col_vira_null() {
  _sd="$TMPDIR_TEST/legacy"; mkdir -p "$_sd"
  printf '# session_id\tsess-l\nmain\tclaude-opus-5[1m]\tinput\t100\n' > "$_sd/otel-start.tsv"
  _fe="$TMPDIR_TEST/lg-e.txt"
  _tok_line sess-l main "claude-opus-5[1m]" input 400 > "$_fe"
  _snap "$_sd" end "$_fe"
  capture sh "$SCRIPT" delta --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT"; return 1; }
  [ "$(printf '%s' "$_CAPTURED_STDOUT" | tr -d '[:space:]')" = "null" ] \
    || { _fail "null" "snapshot legado deve dar null, obtido '$_CAPTURED_STDOUT'"; return 1; }
  printf '%s' "$_CAPTURED_STDERR" | grep -q "formato antigo" \
    || { _fail "stderr" "faltou aviso de formato antigo"; return 1; }
  return 0
}

# ==== INV-3: ausente e null, nunca zero ====

scenario_delta_sem_snapshot_start_e_null() {
  _sd="$TMPDIR_TEST/nostart"; mkdir -p "$_sd"
  _fe="$TMPDIR_TEST/ns-end.txt"
  _fixture "$_fe" "sess-x" 1.0 1.0 10 5
  _snap "$_sd" end "$_fe"
  capture sh "$SCRIPT" delta --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT"; return 1; }
  [ "$(printf '%s' "$_CAPTURED_STDOUT" | tr -d '[:space:]')" = "null" ] \
    || { _fail "null" "sem start deve ser null, obtido '$_CAPTURED_STDOUT'"; return 1; }
  return 0
}

# Sessao inteira do start ausente no end = o processo dono do exporter
# trocou no meio da onda (num exporter vivo, sessao nunca desaparece do
# /metrics — contadores sao cumulativos por processo).
scenario_delta_sessao_do_start_sumida_e_null() {
  _sd="$TMPDIR_TEST/divsess"; mkdir -p "$_sd"
  _fs="$TMPDIR_TEST/v-start.txt"; _fe="$TMPDIR_TEST/v-end.txt"
  _fixture "$_fs" "sess-AAA" 1.0 1.0 10 5
  _fixture "$_fe" "sess-BBB" 9.0 9.0 90 50
  _snap "$_sd" start "$_fs"
  _snap "$_sd" end   "$_fe"
  capture sh "$SCRIPT" delta --state-dir "$_sd"
  [ "$(printf '%s' "$_CAPTURED_STDOUT" | tr -d '[:space:]')" = "null" ] \
    || { _fail "null" "sessao do start sumida deve dar null (processo trocou)"; return 1; }
  printf '%s' "$_CAPTURED_STDERR" | grep -q "ausente no snapshot final" \
    || { _fail "stderr" "faltou aviso de sessao ausente no snapshot final"; return 1; }
  return 0
}

# ==== INV-4: degradacao best-effort ====

scenario_snapshot_endpoint_indisponivel_exit0() {
  _sd="$TMPDIR_TEST/down"; mkdir -p "$_sd"
  capture sh "$SCRIPT" snapshot --state-dir "$_sd" --phase start \
    --endpoint "file://$TMPDIR_TEST/nao-existe-mesmo.txt"
  [ "$_CAPTURED_EXIT" = 0 ] \
    || { _fail "exit" "endpoint fora do ar deve degradar com exit 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -f "$_sd/otel-start.tsv" ] \
    && { _fail "arquivo" "nao deve escrever snapshot sem dados"; return 1; }
  return 0
}

# ==== INV-5: available exige cost/token, nao qualquer claude_code_ ====

scenario_available_exige_metricas_consumidas() {
  # Cold start: o exporter ja responde com session_count mas ainda nao
  # emitiu cost/token. Aceitar isso produzia snapshot sem session_id.
  _fx="$TMPDIR_TEST/coldstart.txt"
  printf 'claude_code_session_count_total{session_id="s"} 1\n' > "$_fx"
  capture sh "$SCRIPT" available --endpoint "file://$_fx"
  [ "$_CAPTURED_EXIT" = 1 ] \
    || { _fail "cold start" "so session_count deve dar exit 1, obtido $_CAPTURED_EXIT"; return 1; }
  return 0
}

scenario_available_ok_com_metricas_reais() {
  _fx="$TMPDIR_TEST/warm.txt"
  _fixture "$_fx" "sess-w" 1.0 1.0 10 5
  capture sh "$SCRIPT" available --endpoint "file://$_fx"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  return 0
}

scenario_available_endpoint_morto_exit1() {
  capture sh "$SCRIPT" available --endpoint "file://$TMPDIR_TEST/vazio-inexistente.txt"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  return 0
}

# ==== uso incorreto ====

scenario_sem_subcomando_exit2() {
  assert_exit 2 sh "$SCRIPT" || return 1
  return 0
}

scenario_subcomando_desconhecido_exit2() {
  assert_exit 2 sh "$SCRIPT" nao-existe || return 1
  return 0
}

scenario_snapshot_phase_invalida_exit2() {
  _sd="$TMPDIR_TEST/badphase"; mkdir -p "$_sd"
  assert_exit 2 sh "$SCRIPT" snapshot --state-dir "$_sd" --phase meio || return 1
  return 0
}

scenario_snapshot_sem_state_dir_exit2() {
  assert_exit 2 sh "$SCRIPT" snapshot --phase start || return 1
  return 0
}

scenario_delta_sem_state_dir_exit2() {
  assert_exit 2 sh "$SCRIPT" delta || return 1
  return 0
}

scenario_flag_desconhecida_exit2() {
  _sd="$TMPDIR_TEST/badflag"; mkdir -p "$_sd"
  assert_exit 2 sh "$SCRIPT" snapshot --state-dir "$_sd" --phase start --nao-existe || return 1
  return 0
}

# ==== preflight: a telemetria DESTA sessao vai ser medida? ====
#
# O dono da porta e detectado via lsof e comparado com a cadeia de
# ancestrais do processo (ps -o ppid=). Nos cenarios, lsof e STUBADO no
# PATH (nunca escondido — ver feedback PATH-stub): o stub responde as duas
# invocacoes que o script faz (-tiTCP:... para o PID dono; -d cwd -Fn para
# o diretorio). Dono "ancestral" usa $$ do proprio test (que E ancestral
# do SUT); dono "estranho" usa PID 1 (launchd/init: existe sempre e nunca
# e ancestral — o walk para em pid > 1).

# _pf_stub_lsof DIR OWNER_PID CWD_PATH — stub de lsof que devolve um dono
# fixo para a porta e um cwd fixo para esse dono. OWNER_PID vazio simula
# porta livre (nada em LISTEN).
_pf_stub_lsof() {
  mkdir -p "$1"
  cat > "$1/lsof" <<EOF
#!/bin/sh
case "\$*" in
  *-tiTCP:*)  [ -n '$2' ] && printf '%s\n' '$2'; exit 0 ;;
  *"-d cwd"*) [ -n '$3' ] && printf 'n%s\n' '$3'; exit 0 ;;
esac
exit 1
EOF
  chmod +x "$1/lsof"
}

_pf_run() {
  # $1=stub-dir(ou "-" p/ PATH real) $2=endpoint; telemetria LIGADA.
  if [ "$1" = "-" ]; then
    capture env CLAUDE_CODE_ENABLE_TELEMETRY=1 OTEL_METRICS_EXPORTER=prometheus \
      sh "$SCRIPT" preflight --endpoint "$2"
  else
    capture env CLAUDE_CODE_ENABLE_TELEMETRY=1 OTEL_METRICS_EXPORTER=prometheus \
      PATH="$1:$PATH" sh "$SCRIPT" preflight --endpoint "$2"
  fi
}

scenario_preflight_disabled_sem_optin() {
  # Env vazio (nao unset: o script exige exatamente "1"/"prometheus").
  capture env CLAUDE_CODE_ENABLE_TELEMETRY= OTEL_METRICS_EXPORTER= \
    sh "$SCRIPT" preflight --endpoint "http://127.0.0.1:29464/metrics"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  case "$_CAPTURED_STDOUT" in
    status=disabled*) : ;;
    *) _fail "stdout" "esperado status=disabled, obtido: $_CAPTURED_STDOUT"; return 1 ;;
  esac
  return 0
}

scenario_preflight_ok_dono_ancestral() {
  _stub="$TMPDIR_TEST/pf-anc"
  _pf_stub_lsof "$_stub" "$$" "/qualquer/cwd"
  _pf_run "$_stub" "http://127.0.0.1:29464/metrics"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT / $_CAPTURED_STDERR"; return 1; }
  case "$_CAPTURED_STDOUT" in
    status=ok*owner_pid=$$*) : ;;
    *) _fail "stdout" "esperado status=ok owner_pid=$$, obtido: $_CAPTURED_STDOUT"; return 1 ;;
  esac
  return 0
}

scenario_preflight_conflito_dono_nao_ancestral_exit3() {
  _stub="$TMPDIR_TEST/pf-conf"
  _pf_stub_lsof "$_stub" "1" "/Users/outro/projeto-alheio"
  _pf_run "$_stub" "http://127.0.0.1:29464/metrics"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "exit" "esperado 3, obtido $_CAPTURED_EXIT"; return 1; }
  case "$_CAPTURED_STDOUT" in
    status=port-conflict*owner_pid=1*owner_cwd=/Users/outro/projeto-alheio*) : ;;
    *) _fail "stdout" "esperado port-conflict com dono+cwd, obtido: $_CAPTURED_STDOUT"; return 1 ;;
  esac
  case "$_CAPTURED_STDERR" in
    *AVISO*) : ;;
    *) _fail "stderr" "esperado AVISO de conflito em stderr, obtido: $_CAPTURED_STDERR"; return 1 ;;
  esac
  return 0
}

scenario_preflight_exporter_down_porta_livre_exit4() {
  # Stub devolve porta livre (sem dono); endpoint local sem ninguem
  # escutando (porta 9 / discard) -> scrape falha -> exporter-down.
  _stub="$TMPDIR_TEST/pf-down"
  _pf_stub_lsof "$_stub" "" ""
  _pf_run "$_stub" "http://127.0.0.1:9/metrics"
  [ "$_CAPTURED_EXIT" = 4 ] || { _fail "exit" "esperado 4, obtido $_CAPTURED_EXIT"; return 1; }
  case "$_CAPTURED_STDOUT" in
    status=exporter-down*) : ;;
    *) _fail "stdout" "esperado status=exporter-down, obtido: $_CAPTURED_STDOUT"; return 1 ;;
  esac
  return 0
}

scenario_preflight_unverified_endpoint_arquivo() {
  # Endpoint nao-local (file://): sem dono verificavel; scrape com as
  # metricas presentes -> unverified, exit 0, sem aviso.
  _fx="$TMPDIR_TEST/pf-file.txt"
  _fixture "$_fx" "sess-pf" 1.0 0.5 100 20
  _pf_run "-" "file://$_fx"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  case "$_CAPTURED_STDOUT" in
    status=unverified*) : ;;
    *) _fail "stdout" "esperado status=unverified, obtido: $_CAPTURED_STDOUT"; return 1 ;;
  esac
  return 0
}

scenario_preflight_flag_desconhecida_exit2() {
  assert_exit 2 sh "$SCRIPT" preflight --nao-existe || return 1
  return 0
}

# ==== --reason-file: motivo da ausencia deixa de ser perdido ====
#
# O motivo do `null` sempre foi conhecido aqui e sempre morreu no aviso em
# prosa (o chamador invoca este script com `2>/dev/null`). Cada caminho de
# `null` MUST depositar seu slug; onda medida MUST NOT deixar motivo.

# _reason_of FILE -> conteudo do reason-file, sem espacos (vazio se nao ha).
_reason_of() {
  [ -s "$1" ] || { printf ''; return 0; }
  tr -d '[:space:]' < "$1"
}

scenario_reason_exporter_trocou() {
  _sd="$TMPDIR_TEST/r-troca"; mkdir -p "$_sd"
  _fs="$TMPDIR_TEST/r1-start.txt"; _fe="$TMPDIR_TEST/r1-end.txt"
  _fixture "$_fs" "sess-AAA" 1.0 1.0 10 5
  _fixture "$_fe" "sess-BBB" 9.0 9.0 90 50
  _snap "$_sd" start "$_fs"
  _snap "$_sd" end   "$_fe"
  _rf="$TMPDIR_TEST/r1.reason"
  capture sh "$SCRIPT" delta --state-dir "$_sd" --reason-file "$_rf"
  [ "$(printf '%s' "$_CAPTURED_STDOUT" | tr -d '[:space:]')" = "null" ] \
    || { _fail "null" "esperado null"; return 1; }
  [ "$(_reason_of "$_rf")" = "exporter-trocou" ] \
    || { _fail "reason" "esperado exporter-trocou, obtido: $(_reason_of "$_rf")"; return 1; }
  return 0
}

scenario_reason_sem_snapshot() {
  _sd="$TMPDIR_TEST/r-sem"; mkdir -p "$_sd"
  _fe="$TMPDIR_TEST/r2-end.txt"
  _fixture "$_fe" "sess-AAA" 1.0 1.0 10 5
  _snap "$_sd" end "$_fe"
  _rf="$TMPDIR_TEST/r2.reason"
  capture sh "$SCRIPT" delta --state-dir "$_sd" --reason-file "$_rf"
  [ "$(_reason_of "$_rf")" = "sem-snapshot" ] \
    || { _fail "reason" "esperado sem-snapshot, obtido: $(_reason_of "$_rf")"; return 1; }
  return 0
}

scenario_reason_sessoes_ambiguas() {
  _sd="$TMPDIR_TEST/r-amb"; mkdir -p "$_sd"
  _fs="$TMPDIR_TEST/r3-start.txt"; _fe="$TMPDIR_TEST/r3-end.txt"
  { _cost_line "sess-A" main "claude-opus-5[1m]" 1.0
    _cost_line "sess-B" main "claude-opus-5[1m]" 1.0; } > "$_fs"
  { _cost_line "sess-A" main "claude-opus-5[1m]" 5.0
    _cost_line "sess-B" main "claude-opus-5[1m]" 7.0; } > "$_fe"
  _snap "$_sd" start "$_fs"
  _snap "$_sd" end   "$_fe"
  _rf="$TMPDIR_TEST/r3.reason"
  capture sh "$SCRIPT" delta --state-dir "$_sd" --reason-file "$_rf"
  [ "$(_reason_of "$_rf")" = "sessoes-ambiguas" ] \
    || { _fail "reason" "esperado sessoes-ambiguas, obtido: $(_reason_of "$_rf")"; return 1; }
  return 0
}

scenario_reason_sem_crescimento() {
  _sd="$TMPDIR_TEST/r-parado"; mkdir -p "$_sd"
  _fs="$TMPDIR_TEST/r4.txt"
  _fixture "$_fs" "sess-AAA" 1.0 1.0 10 5
  _snap "$_sd" start "$_fs"
  _snap "$_sd" end   "$_fs"
  _rf="$TMPDIR_TEST/r4.reason"
  capture sh "$SCRIPT" delta --state-dir "$_sd" --reason-file "$_rf"
  [ "$(_reason_of "$_rf")" = "sem-crescimento" ] \
    || { _fail "reason" "esperado sem-crescimento, obtido: $(_reason_of "$_rf")"; return 1; }
  return 0
}

scenario_reason_formato_antigo() {
  _sd="$TMPDIR_TEST/r-legado"; mkdir -p "$_sd"
  # Snapshot legado: 4 colunas (sem session_id por linha).
  printf 'main\tclaude-opus-5[1m]\tcost\t1.0\n' > "$_sd/otel-start.tsv"
  printf 'main\tclaude-opus-5[1m]\tcost\t9.0\n' > "$_sd/otel-end.tsv"
  _rf="$TMPDIR_TEST/r5.reason"
  capture sh "$SCRIPT" delta --state-dir "$_sd" --reason-file "$_rf"
  [ "$(_reason_of "$_rf")" = "formato-antigo" ] \
    || { _fail "reason" "esperado formato-antigo, obtido: $(_reason_of "$_rf")"; return 1; }
  return 0
}

scenario_reason_vazio_quando_medido() {
  _sd="$TMPDIR_TEST/r-ok"; mkdir -p "$_sd"
  _fs="$TMPDIR_TEST/r6-start.txt"; _fe="$TMPDIR_TEST/r6-end.txt"
  _fixture "$_fs" "sess-AAA" 1.0 1.0 10 5
  _fixture "$_fe" "sess-AAA" 3.0 3.0 40 25
  _snap "$_sd" start "$_fs"
  _snap "$_sd" end   "$_fe"
  _rf="$TMPDIR_TEST/r6.reason"
  capture sh "$SCRIPT" delta --state-dir "$_sd" --reason-file "$_rf"
  printf '%s' "$_CAPTURED_STDOUT" | jq -e '.total_tokens > 0' >/dev/null 2>&1 \
    || { _fail "delta" "esperado delta medido, obtido: $_CAPTURED_STDOUT"; return 1; }
  [ -z "$(_reason_of "$_rf")" ] \
    || { _fail "reason" "onda medida NAO deve deixar motivo, obtido: $(_reason_of "$_rf")"; return 1; }
  return 0
}

# Sem a flag, byte-a-byte o comportamento antigo (nenhum chamador legado
# muda de contrato so porque a capacidade passou a existir).
scenario_reason_file_ausente_nao_altera_saida() {
  _sd="$TMPDIR_TEST/r-compat"; mkdir -p "$_sd"
  _fs="$TMPDIR_TEST/r7-start.txt"; _fe="$TMPDIR_TEST/r7-end.txt"
  _fixture "$_fs" "sess-AAA" 1.0 1.0 10 5
  _fixture "$_fe" "sess-BBB" 9.0 9.0 90 50
  _snap "$_sd" start "$_fs"
  _snap "$_sd" end   "$_fe"
  capture sh "$SCRIPT" delta --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ "$(printf '%s' "$_CAPTURED_STDOUT" | tr -d '[:space:]')" = "null" ] \
    || { _fail "stdout" "esperado null sem a flag"; return 1; }
  return 0
}

run_all_scenarios
exit $?
