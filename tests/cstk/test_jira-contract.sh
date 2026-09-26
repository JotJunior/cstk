#!/bin/sh
# test_jira-contract.sh — suite cross-cutting de CONTRATO REST do plugin
# cstk-jira (cstk-jira FASE 8 tarefa 8.1 "Suite de contrato REST").
#
# Ref: docs/specs/cstk-jira/plan.md Test Strategy "Contrato";
#      docs/specs/cstk-jira/contracts/jira-rest.md (fonte UNICA do
#      "esperado" de cada assert — R1-R11, secoes "Campos de request/
#      response a partir do OpenAPI oficial" onda-005/onda-029 e "Roundtrip
#      real" onda-011/022); docs/specs/cstk-jira/data-model.md Entity
#      SyncMarker (campos do valor de R6, que NAO sao padronizados pelo
#      Jira — sao do nosso proprio modelo, ver nota no scenario CHK002);
#      checklists/api.md CHK001/CHK002; tasks.md 8.1.1-8.1.3.
#
# Diferenca de escopo em relacao as suites ja existentes (test_jira-io.sh
# 82 cenarios, test_jira-sync.sh 31, test_jira-convert-parity.sh): aquelas
# provam COMPORTAMENTO (idempotencia, classificacao de erro, parity MCP/REST)
# cenario a cenario. Esta suite e uma comparacao UNICA e CROSS-CUTTING de
# metodo+path+corpo de CADA uma das 11 operacoes documentadas contra o que o
# plugin de fato emite — nenhum cenario aqui duplica uma asserção
# comportamental ja coberta, so a conformidade estrutural com o contrato.
#
# Motor real (jira-sync.sh) SO emite R1 (convert) e R3/R5/R4/R6 (drain) —
# exercitados abaixo end-to-end via o MESMO stub em fila de
# test_jira-sync.sh (`_init_queue_stub`: registra METHOD+URL e uma copia do
# corpo de cada chamada; copiado aqui porque os arquivos-irmaos terminam em
# `run_all_scenarios` e nao podem ser `sourced` como biblioteca sem
# disparar a execucao deles). R9/R10/R11 (board) nao tem script "motor"
# dedicado — sao emitidos pela skill interativa `jira-setup` (LLM) via
# `jira-io.sh` direto; exercitados abaixo reproduzindo EXATAMENTE o
# algoritmo de referencia documentado em plugins/cstk-jira/skills/
# jira-setup/references/board-setup.md (mesma funcao `_run_board_setup` ja
# usada por test_jira-io.sh JI-71..74, copiada aqui pelo mesmo motivo
# acima). R8 idem, literal de plugins/cstk-jira/skills/jira-setup/
# references/api-discovery.md secao 1. R2 (editar issue) e R7 (busca JQL)
# NAO tem NENHUM ponto de chamada no codigo hoje (grep no repo inteiro,
# onda-031) — documentados em contracts/jira-rest.md e ja aceitos pelo
# classificador de `--op` de jira-io.sh (dec-073), mas sem consumidor;
# exercitados aqui SOMENTE na camada `jira-io.sh` (o UNICO ponto por onde
# qualquer chamada R1-R11 de fato dispara, por desenho do proprio script —
# jira-io.sh cabecalho linha 136), provando que o classificador aceita e
# despacha essas 2 operacoes corretamente. NENHUMA alegacao e feita aqui
# sobre uso em producao de R2/R7 (Principio VI — nao fabricar consumo
# inexistente).
#
# Convencao "COVERS: Rn" (comentario proprio, uma linha, imediatamente
# acima de cada `scenario_ct_*`): usada pelo proprio scenario CHK001
# abaixo para provar que as 11 operacoes tem scenario dedicado — remover
# uma tag sem remover a operacao real do contrato faz CHK001 falhar.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk-jira/scripts/jira-sync.sh"
IO_SCRIPT="$REPO_ROOT/plugins/cstk-jira/scripts/jira-io.sh"
CONFIG_SCRIPT="$REPO_ROOT/plugins/cstk-jira/scripts/jira-config.sh"
CONTRACT_DOC="$REPO_ROOT/docs/specs/cstk-jira/contracts/jira-rest.md"
DATA_MODEL_DOC="$REPO_ROOT/docs/specs/cstk-jira/data-model.md"
SELF="$TESTS_ROOT/cstk/test_jira-contract.sh"

# ---------------------------------------------------------------------------
# Setup (identico a test_jira-sync.sh / test_jira-io.sh — reproduzido aqui,
# nao sourced: ver nota acima).
# ---------------------------------------------------------------------------

_write_full_config() {
  mkdir -p "$TMPDIR_TEST/.claude/cstk-jira"
  cat > "$TMPDIR_TEST/.claude/cstk-jira/config" <<'EOF'
config_version=1
site_host=cstk-test.atlassian.net
project_key=DEMO
board_id=1
issue_type_epic=10001
issue_type_task=10004
issue_type_subtask=10002
status_pending=To Do
status_in_progress=In Progress
status_pass=Done
status_fail=Failed
sync_autonomous=on
EOF
}

# _write_credential [SITE_HOST] — default = "cstk-test.atlassian.net"
# (mesmo host de `_write_full_config`); os cenarios de board-setup passam
# "example.atlassian.net" explicitamente (mesmo host de
# `_write_board_setup_config`) — FR-015 exige igualdade exata com o
# site_host de ProjectConfig.
_write_credential() {
  mkdir -p "$TMPDIR_TEST/xdg/cstk-jira"
  printf 'site_host=%s\nemail=%s\napi_token=%s\n' \
    "${1:-cstk-test.atlassian.net}" "tester@example.com" "tok-FAKE-000" \
    > "$TMPDIR_TEST/xdg/cstk-jira/credentials"
  chmod 600 "$TMPDIR_TEST/xdg/cstk-jira/credentials"
}

_write_tasks_1task_1sub() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cat > "$TMPDIR_TEST/docs/specs/demo/tasks.md" <<'EOF'
## FASE 1 - Sincronizacao `[A]`

### 1.1 Titulo da tarefa `[A]`

- [ ] 1.1.1 Sub um
EOF
}

_map_file() {
  printf '%s\n' "$TMPDIR_TEST/docs/specs/demo/jira-map.tsv"
}

_write_map_row() {
  _wmr_file="$(_map_file)"
  mkdir -p "$(dirname "$_wmr_file")"
  [ -f "$_wmr_file" ] || printf '%s\n' 'local_key	kind	jira_id	jira_key	state' > "$_wmr_file"
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >> "$_wmr_file"
}

_outbox_file() {
  printf '%s\n' "$TMPDIR_TEST/.claude/cstk-jira/runtime/outbox.tsv"
}

# _init_queue_stub — mesmo comportamento de test_jira-sync.sh: consome, em
# ordem, uma linha "http_code|body" por chamada; grava "METHOD URL" em
# queue-curl-calls.log e uma copia do corpo enviado (--data-binary @file)
# em queue-curl-body-<n>.json.
_init_queue_stub() {
  _stub_dir="$TMPDIR_TEST/bin-queue"
  mkdir -p "$_stub_dir"
  : > "$TMPDIR_TEST/queue-curl-queue.tsv"
  : > "$TMPDIR_TEST/queue-curl-calls.log"
  cat > "$_stub_dir/curl" <<STUB
#!/bin/sh
_url=""
_out=""
_method="GET"
_bodyfile=""
_prev=""
for _a in "\$@"; do
  case "\$_prev" in
    -o) _out="\$_a" ;;
    -X) _method="\$_a" ;;
  esac
  case "\$_a" in
    https://*) _url="\$_a" ;;
    @*) _bodyfile="\${_a#@}" ;;
  esac
  _prev="\$_a"
done
_qfile="$TMPDIR_TEST/queue-curl-queue.tsv"
_callsfile="$TMPDIR_TEST/queue-curl-calls.log"
_n=\$(wc -l < "\$_callsfile" 2>/dev/null | tr -d ' ')
_n=\$((_n + 1))
if [ -n "\$_bodyfile" ] && [ -f "\$_bodyfile" ]; then
  cp -- "\$_bodyfile" "$TMPDIR_TEST/queue-curl-body-\$_n.json" 2>/dev/null
fi
printf '%s %s\n' "\$_method" "\$_url" >> "\$_callsfile"
_line=\$(sed -n "\${_n}p" "\$_qfile")
if [ -z "\$_line" ]; then
  exit 22
fi
_code=\${_line%%|*}
_body=\${_line#*|}
[ -n "\$_out" ] && printf '%s' "\$_body" > "\$_out"
printf '%s' "\$_code"
exit 0
STUB
  chmod +x "$_stub_dir/curl"
  printf '%s' "$_stub_dir"
}

_queue_push() {
  printf '%s|%s\n' "$1" "$2" >> "$TMPDIR_TEST/queue-curl-queue.tsv"
}

_queue_call_line() {
  sed -n "${1}p" "$TMPDIR_TEST/queue-curl-calls.log"
}

# _queue_body_keys N -> chaves de topo nivel do corpo enviado na chamada N,
# ordenadas, uma por linha. "" se a chamada nao teve corpo.
_queue_body_keys() {
  [ -f "$TMPDIR_TEST/queue-curl-body-$1.json" ] || { printf ''; return; }
  "$IO_SCRIPT" json-get 'keys_unsorted | sort | .[]' < "$TMPDIR_TEST/queue-curl-body-$1.json" 2>/dev/null
}

# _write_board_setup_config / _run_board_setup — mesmo algoritmo de
# test_jira-io.sh (JI-71..74), reproduzindo
# plugins/cstk-jira/skills/jira-setup/references/board-setup.md.
_write_board_setup_config() {
  mkdir -p "$TMPDIR_TEST/.claude/cstk-jira"
  printf 'site_host=example.atlassian.net\nproject_key=%s\n' "$1" \
    > "$TMPDIR_TEST/.claude/cstk-jira/config"
}

_run_board_setup() {
  _rbs_name="$1"
  _rbs_project_key=$("$CONFIG_SCRIPT" get project_key) || return 1
  "$IO_SCRIPT" validate-segment "$_rbs_project_key" || return 1

  _rbs_boards=$("$IO_SCRIPT" request GET \
    "/rest/agile/1.0/board?projectKeyOrId=${_rbs_project_key}&type=kanban" --op R11) || return 1
  _rbs_board_id=$(printf '%s' "$_rbs_boards" | "$IO_SCRIPT" json-get '.values[0].id // empty')

  if [ -n "$_rbs_board_id" ]; then
    printf '%s' "$_rbs_board_id"
    return 0
  fi

  _rbs_filter_body=$("$IO_SCRIPT" json-build filter --name "$_rbs_name" --project-key "$_rbs_project_key") || return 1
  _rbs_filter_bf=$(mktemp "${TMPDIR:-/tmp}/board-setup-filter.XXXXXX") || return 1
  printf '%s' "$_rbs_filter_body" > "$_rbs_filter_bf"
  _rbs_filter_resp=$("$IO_SCRIPT" request POST /rest/api/3/filter \
    --body-file "$_rbs_filter_bf" --op R9) || { rm -f "$_rbs_filter_bf"; return 1; }
  rm -f "$_rbs_filter_bf"
  _rbs_filter_id=$(printf '%s' "$_rbs_filter_resp" | "$IO_SCRIPT" json-get '.id')

  _rbs_board_body=$("$IO_SCRIPT" json-build board --name "$_rbs_name" \
    --filter-id "$_rbs_filter_id" --project-key "$_rbs_project_key") || return 1
  _rbs_board_bf=$(mktemp "${TMPDIR:-/tmp}/board-setup-board.XXXXXX") || return 1
  printf '%s' "$_rbs_board_body" > "$_rbs_board_bf"
  _rbs_board_resp=$("$IO_SCRIPT" request POST /rest/agile/1.0/board \
    --body-file "$_rbs_board_bf" --op R10) || { rm -f "$_rbs_board_bf"; return 1; }
  rm -f "$_rbs_board_bf"
  _rbs_board_id=$(printf '%s' "$_rbs_board_resp" | "$IO_SCRIPT" json-get '.id')

  printf '%s' "$_rbs_board_id"
}

# =========================== R1 — criar issue ===============================

# COVERS: R1
scenario_ct_r1_convert_metodo_path_corpo_batem_contrato() {
  _write_full_config
  _write_tasks_1task_1sub
  _write_credential
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  _bin="$(_init_queue_stub)"
  # myself + project + 3x (create + R3 status + R6 PUT marker inicial,
  # 11.1.1) — epic, task, sub-task
  _queue_push 200 '{"accountId":"acc-1"}'
  _queue_push 200 '{"id":"10000","key":"DEMO"}'
  _queue_push 201 '{"id":"20001","key":"DEMO-1"}'
  _queue_push 200 '{"fields":{"status":{"name":"To Do"}}}'
  _queue_push 201 ''
  _queue_push 201 '{"id":"20002","key":"DEMO-2"}'
  _queue_push 200 '{"fields":{"status":{"name":"To Do"}}}'
  _queue_push 201 ''
  _queue_push 201 '{"id":"20003","key":"DEMO-3"}'
  _queue_push 200 '{"fields":{"status":{"name":"To Do"}}}'
  _queue_push 201 ''
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" convert --feature demo || return 1

  # contracts/jira-rest.md R1: "POST /rest/api/3/issue" — metodo+path
  # EXATOS, sem query, para as 3 criacoes (chamadas 3/6/9: 1=myself, 2=GET
  # project, 3=epic create, 4=R3 epic, 5=R6 epic, 6=task create, 7=R3 task,
  # 8=R6 task, 9=subtask create — 11.1.1 intercala R3/R6 apos cada create).
  _l3=$(_queue_call_line 3); _l4=$(_queue_call_line 6); _l5=$(_queue_call_line 9)
  [ "$_l3" = "POST https://cstk-test.atlassian.net/rest/api/3/issue" ] \
    || { _fail "ct_r1_epic_url" "obtido: $_l3"; return 1; }
  [ "$_l4" = "POST https://cstk-test.atlassian.net/rest/api/3/issue" ] \
    || { _fail "ct_r1_task_url" "obtido: $_l4"; return 1; }
  [ "$_l5" = "POST https://cstk-test.atlassian.net/rest/api/3/issue" ] \
    || { _fail "ct_r1_subtask_url" "obtido: $_l5"; return 1; }

  # contracts/jira-rest.md R1 "Campos de request/response": Epic (raiz, sem
  # fields.parent, e SEM fields.description — data-model.md: criticidade/
  # dependencia so entram na descricao da TASK) so tem project/issuetype/
  # summary. Task (com parent) soma fields.parent + fields.description desde
  # a feature cstk-jira FASE 10 tarefa 10.1 (FR-001): a fixture
  # `_write_tasks_1task_1sub` tem a tag `` `[A]` `` no heading da task 1.1,
  # entao a descricao composta ("Criticidade: A") sempre acompanha a
  # criacao — nenhum campo fora do contrato (`fields.description` em ADF ja
  # documentado em `contracts/jira-rest.md` R1/`plugin-scripts.md`
  # `json-build issue`).
  _epic_fields=$("$IO_SCRIPT" json-get '.fields | keys_unsorted | sort | .[]' < "$TMPDIR_TEST/queue-curl-body-3.json" | tr '\n' ',')
  [ "$_epic_fields" = "issuetype,project,summary," ] \
    || { _fail "ct_r1_epic_fields" "esperado issuetype,project,summary — obtido $_epic_fields"; return 1; }
  # corpo da chamada 6 = create da task (3=R1 epic,4=R3 epic,5=R6 epic)
  _task_fields=$("$IO_SCRIPT" json-get '.fields | keys_unsorted | sort | .[]' < "$TMPDIR_TEST/queue-curl-body-6.json" | tr '\n' ',')
  [ "$_task_fields" = "description,issuetype,parent,project,summary," ] \
    || { _fail "ct_r1_task_fields" "esperado description,issuetype,parent,project,summary — obtido $_task_fields"; return 1; }

  # fields.project.id (contracts/jira-rest.md: "{"id": "<string>"}
  # CONFIRMADO roundtrip onda-011") vem da resolucao via GET /project
  # (chamada 2), nao de um literal fixo.
  _proj_id=$("$IO_SCRIPT" json-get '.fields.project.id' < "$TMPDIR_TEST/queue-curl-body-3.json")
  [ "$_proj_id" = "10000" ] \
    || { _fail "ct_r1_project_id_shape" "fields.project.id deveria vir da resposta de GET /project (nota 'Resolucao do project.id')"; return 1; }

  # 11.1.1 (FR-011): apos R1, o motor grava o SyncMarker inicial via R6 PUT
  # (contracts/jira-rest.md R6 — "o corpo da requisicao E o value CRU").
  # Chamada 5 = R6 PUT do marker do Epic (3=R1,4=R3,5=R6).
  _l5_marker=$(_queue_call_line 5)
  [ "$_l5_marker" = "PUT https://cstk-test.atlassian.net/rest/api/3/issue/DEMO-1/properties/cstk-jira.sync" ] \
    || { _fail "ct_r1_marker_r6_url" "obtido: $_l5_marker"; return 1; }
  _epic_marker_keys=$("$IO_SCRIPT" json-get 'keys_unsorted | sort | .[]' < "$TMPDIR_TEST/queue-curl-body-5.json" | tr '\n' ',')
  [ "$_epic_marker_keys" = "feature,local_key,schema,written_at,written_status,written_summary_sha256," ] \
    || { _fail "ct_r1_marker_shape" "R6 PUT corpo (value cru, SEM envelope key/value — contracts/jira-rest.md R6) esperado com as 6 chaves do SyncMarker (data-model.md), obtido $_epic_marker_keys"; return 1; }
  return 0
}

# =========================== R3/R5/R4/R6 — drain ============================

# COVERS: R3
# COVERS: R5
# COVERS: R4
# COVERS: R6
scenario_ct_r3_r5_r4_r6_drain_metodo_path_corpo_batem_contrato() {
  _write_full_config
  _write_credential
  _write_map_row "1.1" task 20002 DEMO-2 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	1.1	pass	manual	0	queued
EOF
  _sha=$(printf '%s' "Titulo Atual" | "$IO_SCRIPT" sha256-stdin)
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"fields":{"summary":"Titulo Atual","status":{"name":"In Progress"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha\",\"written_status\":\"In Progress\"}}"
  _queue_push 200 '{"transitions":[{"id":"11","to":{"name":"In Progress"}},{"id":"31","to":{"name":"Done"}}]}'
  _queue_push 204 ''
  _queue_push 200 ''
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" drain --feature demo || return 1

  # R3: GET /rest/api/3/issue/{issueIdOrKey}?fields=... (query "fields"
  # generica, contracts/jira-rest.md: "accepts a comma-separated list").
  _l1=$(_queue_call_line 1)
  [ "$_l1" = "GET https://cstk-test.atlassian.net/rest/api/3/issue/DEMO-2?fields=summary,status" ] \
    || { _fail "ct_r3_url" "obtido: $_l1"; return 1; }

  # R6 GET: /rest/api/3/issue/{issueIdOrKey}/properties/{propertyKey}
  _l2=$(_queue_call_line 2)
  [ "$_l2" = "GET https://cstk-test.atlassian.net/rest/api/3/issue/DEMO-2/properties/cstk-jira.sync" ] \
    || { _fail "ct_r6_get_url" "obtido: $_l2"; return 1; }

  # R5: GET /rest/api/3/issue/{issueIdOrKey}/transitions
  _l3=$(_queue_call_line 3)
  [ "$_l3" = "GET https://cstk-test.atlassian.net/rest/api/3/issue/DEMO-2/transitions" ] \
    || { _fail "ct_r5_url" "obtido: $_l3"; return 1; }

  # R4: POST .../transitions, corpo SOMENTE {"transition":{"id":ID}}
  # (contracts/jira-rest.md: "o motor envia SO {"transition": {"id": ...}}")
  _l4=$(_queue_call_line 4)
  [ "$_l4" = "POST https://cstk-test.atlassian.net/rest/api/3/issue/DEMO-2/transitions" ] \
    || { _fail "ct_r4_url" "obtido: $_l4"; return 1; }
  _r4_keys=$(_queue_body_keys 4 | tr '\n' ',')
  [ "$_r4_keys" = "transition," ] || { _fail "ct_r4_body_keys" "esperado somente 'transition' — obtido $_r4_keys"; return 1; }
  _r4_trans_keys=$("$IO_SCRIPT" json-get '.transition | keys_unsorted | sort | .[]' < "$TMPDIR_TEST/queue-curl-body-4.json" | tr '\n' ',')
  [ "$_r4_trans_keys" = "id," ] || { _fail "ct_r4_transition_keys" "esperado somente 'id' — obtido $_r4_trans_keys"; return 1; }

  # R6 PUT: mesma URL de R6 GET; corpo E o value CRU, SEM envelope
  # {key,value} (contracts/jira-rest.md secao R6).
  _l5=$(_queue_call_line 5)
  [ "$_l5" = "PUT https://cstk-test.atlassian.net/rest/api/3/issue/DEMO-2/properties/cstk-jira.sync" ] \
    || { _fail "ct_r6_put_url" "obtido: $_l5"; return 1; }
  _r6_keys=$(_queue_body_keys 5 | tr '\n' ',')
  [ "$_r6_keys" = "feature,local_key,schema,written_at,written_status,written_summary_sha256," ] \
    || { _fail "ct_r6_put_body_keys" "obtido: $_r6_keys"; return 1; }
  return 0
}

# =========================== R9/R10/R11 — board ==============================

# COVERS: R9
# COVERS: R10
# COVERS: R11
scenario_ct_r9_r10_r11_board_setup_metodo_path_corpo_batem_contrato() {
  _write_board_setup_config "DEMO"
  _write_credential "example.atlassian.net"
  cd "$TMPDIR_TEST" || return 1
  _bin="$TMPDIR_TEST/bin"
  mkdir -p "$_bin"
  printf '%s\n' 'https://example.atlassian.net/rest/agile/1.0/board?projectKeyOrId=DEMO&type=kanban|200|{"isLast":true,"maxResults":50,"startAt":0,"total":0,"values":[]}
https://example.atlassian.net/rest/api/3/filter|200|{"id":"10041","name":"x","jql":"project = \"DEMO\"","self":"https://example.atlassian.net/rest/api/3/filter/10041"}
https://example.atlassian.net/rest/agile/1.0/board|201|{"id":85,"name":"x","self":"https://example.atlassian.net/rest/agile/1.0/board/85","type":"kanban"}' \
    > "$TMPDIR_TEST/board-map"
  : > "$TMPDIR_TEST/board-calls.log"
  cat > "$_bin/curl" <<STUB
#!/bin/sh
_url=""
_out=""
_method="GET"
_bodyfile=""
_prev=""
for _a in "\$@"; do
  case "\$_prev" in
    -o) _out="\$_a" ;;
    -X) _method="\$_a" ;;
  esac
  case "\$_a" in
    https://*) _url="\$_a" ;;
    @*) _bodyfile="\${_a#@}" ;;
  esac
  _prev="\$_a"
done
if [ -n "\$_bodyfile" ]; then
  case "\$_url" in
    */rest/api/3/filter) cp -- "\$_bodyfile" "$TMPDIR_TEST/board-body-r9.json" ;;
    */rest/agile/1.0/board) cp -- "\$_bodyfile" "$TMPDIR_TEST/board-body-r10.json" ;;
  esac
fi
printf '%s %s\n' "\$_method" "\$_url" >> "$TMPDIR_TEST/board-calls.log"
while IFS='|' read -r _pat _code _body; do
  [ -n "\$_pat" ] || continue
  if [ "\$_url" = "\$_pat" ]; then
    [ -n "\$_out" ] && printf '%s' "\$_body" > "\$_out"
    printf '%s' "\$_code"
    exit 0
  fi
done < "$TMPDIR_TEST/board-map"
exit 22
STUB
  chmod +x "$_bin/curl"

  _got_id=$(PATH="$_bin:$PATH" XDG_CONFIG_HOME="$TMPDIR_TEST/xdg" _run_board_setup "CSTK Board") \
    || { _fail "ct_board_setup_run" "algoritmo de referencia (board-setup.md) falhou"; return 1; }
  [ "$_got_id" = "85" ] || { _fail "ct_board_setup_id" "esperado 85, obtido $_got_id"; return 1; }

  # R11: GET /rest/agile/1.0/board?projectKeyOrId=...&type=kanban
  _l1=$(sed -n '1p' "$TMPDIR_TEST/board-calls.log")
  [ "$_l1" = "GET https://example.atlassian.net/rest/agile/1.0/board?projectKeyOrId=DEMO&type=kanban" ] \
    || { _fail "ct_r11_url" "obtido: $_l1"; return 1; }

  # R9: POST /rest/api/3/filter, corpo {"name":...,"jql":...} SOMENTE
  _l2=$(sed -n '2p' "$TMPDIR_TEST/board-calls.log")
  [ "$_l2" = "POST https://example.atlassian.net/rest/api/3/filter" ] \
    || { _fail "ct_r9_url" "obtido: $_l2"; return 1; }
  _r9_keys=$("$IO_SCRIPT" json-get 'keys_unsorted | sort | .[]' < "$TMPDIR_TEST/board-body-r9.json" | tr '\n' ',')
  [ "$_r9_keys" = "jql,name," ] || { _fail "ct_r9_body_keys" "obtido: $_r9_keys"; return 1; }
  _r9_jql=$("$IO_SCRIPT" json-get '.jql' < "$TMPDIR_TEST/board-body-r9.json")
  [ "$_r9_jql" = 'project = "DEMO"' ] || { _fail "ct_r9_jql" "obtido: $_r9_jql"; return 1; }

  # R10: POST /rest/agile/1.0/board, corpo {name,type,filterId,location}
  # SOMENTE (schema additionalProperties:false); filterId NUMERO, nunca
  # string (contracts/jira-rest.md R10).
  _l3=$(sed -n '3p' "$TMPDIR_TEST/board-calls.log")
  [ "$_l3" = "POST https://example.atlassian.net/rest/agile/1.0/board" ] \
    || { _fail "ct_r10_url" "obtido: $_l3"; return 1; }
  _r10_keys=$("$IO_SCRIPT" json-get 'keys_unsorted | sort | .[]' < "$TMPDIR_TEST/board-body-r10.json" | tr '\n' ',')
  [ "$_r10_keys" = "filterId,location,name,type," ] || { _fail "ct_r10_body_keys" "obtido: $_r10_keys"; return 1; }
  _r10_type=$("$IO_SCRIPT" json-get '.type' < "$TMPDIR_TEST/board-body-r10.json")
  [ "$_r10_type" = "kanban" ] || { _fail "ct_r10_type" "obtido: $_r10_type"; return 1; }
  _r10_filterid_type=$("$IO_SCRIPT" json-get '.filterId | type' < "$TMPDIR_TEST/board-body-r10.json")
  [ "$_r10_filterid_type" = "number" ] \
    || { _fail "ct_r10_filterid_numeric" "filterId deveria ser numero JSON, obtido tipo $_r10_filterid_type"; return 1; }
  _r10_loc_keys=$("$IO_SCRIPT" json-get '.location | keys_unsorted | sort | .[]' < "$TMPDIR_TEST/board-body-r10.json" | tr '\n' ',')
  [ "$_r10_loc_keys" = "projectKeyOrId,type," ] || { _fail "ct_r10_location_keys" "obtido: $_r10_loc_keys"; return 1; }
  return 0
}

# =========================== R8 — tipos de issue (createmeta) ===============

# COVERS: R8
scenario_ct_r8_createmeta_metodo_path_batem_referencia_da_skill() {
  _write_full_config
  _write_credential
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"issueTypes":[{"id":"10001","name":"Epic","hierarchyLevel":1,"subtask":false}]}'
  PATH="$_bin:$PATH"
  export PATH
  # Literal EXATO de plugins/cstk-jira/skills/jira-setup/references/
  # api-discovery.md secao 1 ("R8").
  _ct_resp=$("$IO_SCRIPT" request GET "/rest/api/3/issue/createmeta/DEMO/issuetypes" --op R8) \
    || { _fail "ct_r8_request" "jira-io.sh request R8 falhou"; return 1; }
  _l1=$(_queue_call_line 1)
  [ "$_l1" = "GET https://cstk-test.atlassian.net/rest/api/3/issue/createmeta/DEMO/issuetypes" ] \
    || { _fail "ct_r8_url" "obtido: $_l1"; return 1; }
  _ht=$(printf '%s' "$_ct_resp" | "$IO_SCRIPT" json-get '.issueTypes[0].hierarchyLevel')
  [ "$_ht" = "1" ] \
    || { _fail "ct_r8_hierarchy_level" "campo hierarchyLevel (S:.IssueTypeIssueCreateMetadata.properties) ausente/incorreto"; return 1; }
  return 0
}

# =========================== R2 — editar issue (sem consumidor hoje) ========

# COVERS: R2
# NOTA (Principio VI): nenhum script do plugin invoca R2 hoje (grep no
# repo inteiro, onda-031) — contracts/jira-rest.md documenta a operacao e
# jira-io.sh ja a classifica (403 em R1/R2 => permission_denied, dec-073),
# mas ela nao tem consumidor real. Este scenario exercita SOMENTE a camada
# jira-io.sh (o UNICO ponto de disparo de R1-R11) para provar que o
# classificador aceita/despacha PUT corretamente — NENHUMA alegacao de uso
# em producao.
scenario_ct_r2_editar_issue_via_jira_io_direto() {
  _write_full_config
  _write_credential
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  _bin="$(_init_queue_stub)"
  _queue_push 204 ''
  PATH="$_bin:$PATH"
  export PATH
  # Corpo IssueUpdateDetails "mesmo de R1" (contracts/jira-rest.md secao R2).
  _body=$("$IO_SCRIPT" json-build issue --project-id 10000 --issuetype-id 10004 --summary "Novo titulo") \
    || { _fail "ct_r2_build_body" "json-build issue falhou"; return 1; }
  _bf=$(mktemp "${TMPDIR:-/tmp}/ct-r2.XXXXXX") || return 1
  printf '%s' "$_body" > "$_bf"
  "$IO_SCRIPT" request PUT "/rest/api/3/issue/DEMO-2" --body-file "$_bf" --op R2 >/dev/null
  _ec=$?
  rm -f "$_bf"
  [ "$_ec" = "0" ] || { _fail "ct_r2_request" "PUT R2 falhou (exit $_ec, esperado 0/204 sucesso)"; return 1; }
  _l1=$(_queue_call_line 1)
  [ "$_l1" = "PUT https://cstk-test.atlassian.net/rest/api/3/issue/DEMO-2" ] \
    || { _fail "ct_r2_url" "obtido: $_l1"; return 1; }
  return 0
}

# =========================== R7 — busca JQL (sem consumidor hoje) ===========

# COVERS: R7
# NOTA (Principio VI): mesma situacao de R2 acima — sem consumidor real
# hoje; exercitado SOMENTE na camada jira-io.sh.
scenario_ct_r7_busca_jql_via_jira_io_direto() {
  _write_full_config
  _write_credential
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"issues":[],"nextPageToken":null,"isLast":true}'
  PATH="$_bin:$PATH"
  export PATH
  "$IO_SCRIPT" request GET "/rest/api/3/search/jql?jql=project=DEMO&maxResults=50" --op R7 >/dev/null \
    || { _fail "ct_r7_request" "GET R7 falhou"; return 1; }
  _l1=$(_queue_call_line 1)
  [ "$_l1" = "GET https://cstk-test.atlassian.net/rest/api/3/search/jql?jql=project=DEMO&maxResults=50" ] \
    || { _fail "ct_r7_url" "obtido: $_l1"; return 1; }
  return 0
}

# =========================== CHK001 — 11 endpoints exercitados ==============

# tasks.md 8.1.3 / checklists/api.md CHK001: "11 endpoints documentados e
# exercitados". Le a PROPRIA suite e confere que as 11 tags "COVERS: Rn"
# cobrem exatamente R1..R11 — se um scenario for removido/renomeado sem
# tirar a operacao do contrato, este scenario falha.
scenario_chk001_todas_as_11_operacoes_tem_scenario_dedicado() {
  _covered=$(grep -oE '^# COVERS: R[0-9]{1,2}$' "$SELF" | awk '{print $3}' | sort -u | tr '\n' ',')
  _expected="R1,R10,R11,R2,R3,R4,R5,R6,R7,R8,R9,"
  [ "$_covered" = "$_expected" ] \
    || { _fail "chk001_coverage" "operacoes com tag COVERS: $_covered (esperado as 11 de contracts/jira-rest.md: $_expected)"; return 1; }
  return 0
}

# =========================== CHK002 — campos tem fonte =======================

# checklists/api.md CHK002: "campos de corpo/resposta usados tem fonte".
# Campos padronizados do Jira (REST) MUST estar citados em
# contracts/jira-rest.md; campos do VALOR de R6 (que o proprio contrato
# declara sem schema fixo — "PUT corpo E o value CRU") sao do NOSSO
# modelo (Entity SyncMarker) e MUST estar citados em data-model.md.
# Regressao: se a fonte for removida da doc sem que o campo pare de ser
# usado, este scenario falha.
scenario_chk002_campos_de_corpo_usados_tem_citacao_no_contrato() {
  [ -f "$CONTRACT_DOC" ] || { _fail "chk002_contract_missing" "contracts/jira-rest.md ausente"; return 1; }
  for _field in 'fields.project' 'fields.issuetype' 'fields.summary' \
    'fields.parent' 'transition.id' 'filterId' 'projectKeyOrId' 'jql'; do
    grep -qF -- "$_field" "$CONTRACT_DOC" \
      || { _fail "chk002_field_no_source_rest" "campo REST '$_field' usado no motor mas sem citacao em contracts/jira-rest.md"; return 1; }
  done
  [ -f "$DATA_MODEL_DOC" ] || { _fail "chk002_data_model_missing" "data-model.md ausente"; return 1; }
  for _field in 'written_summary_sha256' 'written_status' 'written_at' 'local_key'; do
    grep -qF -- "$_field" "$DATA_MODEL_DOC" \
      || { _fail "chk002_field_no_source_entity" "campo '$_field' (valor de R6, Entity SyncMarker) sem citacao em data-model.md"; return 1; }
  done
  return 0
}

run_all_scenarios
