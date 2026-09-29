#!/bin/sh
# test_jira-convert-parity.sh — prova a paridade exigida por CHK012 entre o
# caminho REST (`jira-sync.sh convert`, ja coberto por test_jira-sync.sh
# SY-10/SY-11/SY-12) e o caminho MCP descrito na skill `jira-convert`
# (cstk-jira, FASE 6 tarefa 6.2.8).
#
# Ref: docs/specs/cstk-jira/checklists/api.md CHK012 ("os dois produzem o
#      MESMO efeito observavel — mesmo mapeamento, mesmo SyncMarker");
#      tasks.md 6.2.3/6.2.4/6.2.8; plugins/cstk-jira/skills/jira-convert/
#      SKILL.md secao "CAMINHO MCP".
#
# Nao existe sessao MCP real em ambiente de teste de shell (as tools Rovo sao
# invocadas pelo MODELO, nao por um binario chamavel via PATH) — por isso
# este teste NAO finge invocar `createJiraIssue`. Em vez disso, ele PROVA a
# paridade no unico lugar onde ela pode divergir de fato: os DOIS scripts
# deterministicos que os dois caminhos MUST compartilhar (`jira-title.sh`
# para o `fields.summary`/summary da issue, `jira-map.sh` para o formato de
# `jira-map.tsv`) — exatamente o mecanismo que a skill usa para NAO
# reimplementar a logica de composicao/gravacao a mao no caminho MCP
# (SKILL.md Gotcha "Os dois caminhos convergem no mesmo par de scripts").
#
# Invariantes cobertos:
#   JCP-1 Para o mesmo backlog local (1 task + 1 sub-task), o `fields.summary`
#         que o caminho REST de fato envia ao Jira (corpo capturado do POST
#         /rest/api/3/issue) e IDENTICO ao summary que `jira-title.sh
#         compose` produziria para o MESMO item — ou seja, o texto que a
#         skill MCP enviaria a `createJiraIssue` bate byte-a-byte com o que
#         o motor REST envia, para epic/task/sub-task.
#   JCP-2 Simulando o algoritmo do caminho MCP (mesma ordem de
#         `jira-tasks.sh items`, mesma checagem de idempotencia via
#         `jira-map.sh get`, mesma gravacao via `jira-map.sh put`) com os
#         MESMOS ids/keys que o Jira devolveria, o `jira-map.tsv` resultante
#         e estruturalmente IDENTICO ao produzido pelo caminho REST (mesmas
#         3 linhas kind/jira_id/jira_key/state, so o local_key do Epic muda
#         — e sempre o nome da feature, nao uma constante compartilhavel).
#   JCP-3 Idempotencia: repetir a simulacao MCP sobre um jira-map.tsv ja
#         populado nao acrescenta nenhuma linha nova (mesmo criterio de
#         SY-11 do caminho REST — presenca no mapeamento, nunca JQL/titulo).
#   JCP-4 (FASE 11 tarefa 11.2.1, FR-011): o SyncMarker inicial que o
#         caminho MCP grava (SKILL.md ETAPA 2b passo 7b — REST puro via
#         `jira-io.sh`, mesma formula de `_js_write_initial_marker` em
#         `jira-sync.sh`) e estruturalmente IDENTICO (mesmo
#         written_summary_sha256, mesmo written_status) ao que o caminho
#         REST grava para o MESMO summary/status — provado simulando os 2
#         chamadas REST (R3 status + R6 PUT) que o passo 7b descreve, contra
#         um stub de fila dedicado.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SYNC_SCRIPT="$REPO_ROOT/plugins/cstk-jira/scripts/jira-sync.sh"
IO_SCRIPT="$REPO_ROOT/plugins/cstk-jira/scripts/jira-io.sh"
MAP_SCRIPT="$REPO_ROOT/plugins/cstk-jira/scripts/jira-map.sh"
TASKS_SCRIPT="$REPO_ROOT/plugins/cstk-jira/scripts/jira-tasks.sh"
TITLE_SCRIPT="$REPO_ROOT/plugins/cstk-jira/scripts/jira-title.sh"

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

_write_credential() {
  mkdir -p "$TMPDIR_TEST/xdg/cstk-jira"
  printf 'site_host=cstk-test.atlassian.net\nemail=%s\napi_token=%s\n' "tester@example.com" "tok-FAKE-000" \
    > "$TMPDIR_TEST/xdg/cstk-jira/credentials"
  chmod 600 "$TMPDIR_TEST/xdg/cstk-jira/credentials"
}

# _write_tasks_md FEATURE — mesmo backlog (1 task + 1 sub-task) usado por
# test_jira-sync.sh SY-10, gravado sob a feature informada. Grava tambem um
# spec.md com titulo FIXO (mesmo texto independente do nome da feature) para
# que o titulo do Epic nao dependa do short-name — sem isso, o fallback
# "sem spec.md -> titulo do Epic = proprio short-name" faria os dois
# cenarios (features "demo"/"demo2") produzirem summaries do Epic
# DIFERENTES por construcao, mascarando uma divergencia real de CHK012 sob
# um artefato do fixture.
_write_tasks_md() {
  mkdir -p "$TMPDIR_TEST/docs/specs/$1"
  cat > "$TMPDIR_TEST/docs/specs/$1/tasks.md" <<'EOF'
## FASE 1 - Sincronizacao `[A]`

### 1.1 Titulo da tarefa `[A]`

- [ ] 1.1.1 Sub um
EOF
  cat > "$TMPDIR_TEST/docs/specs/$1/spec.md" <<'EOF'
# Feature Specification: Titulo do Epic

Corpo irrelevante para este teste.
EOF
}

# --- stub de rede por FILA (identico ao mecanismo de test_jira-sync.sh,
# necessario so para exercitar o caminho REST real e capturar o corpo
# efetivamente enviado — o caminho MCP nunca usa este stub).
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

# _mcp_write_marker IO JIRA_KEY FEATURE LOCAL_KEY SUMMARY — mesma formula de
# SKILL.md ETAPA 2b passo 7b (REST puro via jira-io.sh, identica a
# `_js_write_initial_marker` em jira-sync.sh): GET status (R3), sha256 do
# summary ENVIADO (nunca lido de volta), json-build marker, PUT (R6). Usada
# so por `_mcp_simulate` para provar JCP-4 — a skill real faria a mesma
# sequencia apos `createJiraIssue`.
_mcp_write_marker() {
  _mwm_io="$1"
  _mwm_jkey="$2"
  _mwm_feature="$3"
  _mwm_lkey="$4"
  _mwm_summary="$5"

  _mwm_status_resp=$("$_mwm_io" request GET "/rest/api/3/issue/$_mwm_jkey?fields=status" --op R3 2>/dev/null) || return 1
  _mwm_status=$(printf '%s' "$_mwm_status_resp" | "$_mwm_io" json-get '.fields.status.name')
  _mwm_sha=$(printf '%s' "$_mwm_summary" | "$_mwm_io" sha256-stdin)
  _mwm_marker=$("$_mwm_io" json-build marker --local-key "$_mwm_lkey" --feature "$_mwm_feature" \
    --written-summary-sha256 "$_mwm_sha" --written-status "$_mwm_status" \
    --written-at "2026-01-01T00:00:00Z")
  _mwm_body_file=$(mktemp "${TMPDIR:-/tmp}/jcp-marker.XXXXXX") || return 1
  printf '%s' "$_mwm_marker" > "$_mwm_body_file"
  "$_mwm_io" request PUT "/rest/api/3/issue/$_mwm_jkey/properties/cstk-jira.sync" \
    --body-file "$_mwm_body_file" --op R6 >/dev/null 2>/dev/null
  _mwm_ec=$?
  rm -f "$_mwm_body_file"
  return "$_mwm_ec"
}

# _mcp_simulate FEATURE [--with-marker] — algoritmo do caminho MCP TAL COMO
# documentado em SKILL.md (jira-convert, secao "CAMINHO MCP"): para cada
# item de `jira-tasks.sh items`, pula se ja mapeado (jira-map.sh get), senao
# compoe o summary via jira-title.sh e grava via jira-map.sh put — usando os
# MESMOS ids/keys sinteticos que o stub REST devolveu (20001/DEMO-1 epic,
# 20002/DEMO-2 task, 20003/DEMO-3 sub-task), para permitir comparacao
# byte-a-byte com o jira-map.tsv do caminho REST. Com `--with-marker`
# (JCP-4, requer stub de rede ativo via PATH), tambem grava o SyncMarker
# inicial via `_mcp_write_marker` (passo 7b da SKILL.md) apos cada
# `jira-map.sh put`. Imprime em stdout, uma linha por item CRIADO nesta
# chamada: "local_key<TAB>summary_composto" (usado pelas asserções
# JCP-1/JCP-3 sem precisar reabrir o TSV).
_mcp_simulate() {
  _msf_feature="$1"
  _msf_with_marker="no"
  [ "${2:-}" = "--with-marker" ] && _msf_with_marker="yes"
  _msf_items=$("$TASKS_SCRIPT" items --feature "$_msf_feature") || return 1
  printf '%s\n' "$_msf_items" | while IFS= read -r _msf_line; do
    [ -n "$_msf_line" ] || continue
    _msf_key=$(printf '%s' "$_msf_line" | cut -f1)
    _msf_kind=$(printf '%s' "$_msf_line" | cut -f2)
    _msf_phase=$(printf '%s' "$_msf_line" | cut -f3)
    _msf_title=$(printf '%s' "$_msf_line" | cut -f6)

    if "$MAP_SCRIPT" get --feature "$_msf_feature" --local-key "$_msf_key" >/dev/null 2>&1; then
      continue
    fi

    case "$_msf_kind" in
      epic)
        _msf_summary=$("$TITLE_SCRIPT" compose --kind epic --title "$_msf_title")
        _msf_id=20001; _msf_jkey="DEMO-1" ;;
      task)
        _msf_summary=$("$TITLE_SCRIPT" compose --kind task --phase "$_msf_phase" \
          --local-key "$_msf_key" --title "$_msf_title")
        _msf_id=20002; _msf_jkey="DEMO-2" ;;
      subtask)
        _msf_summary=$("$TITLE_SCRIPT" compose --kind subtask --title "$_msf_title")
        _msf_id=20003; _msf_jkey="DEMO-3" ;;
      *)
        return 1 ;;
    esac

    "$MAP_SCRIPT" put --feature "$_msf_feature" --local-key "$_msf_key" \
      --kind "$_msf_kind" --jira-id "$_msf_id" --jira-key "$_msf_jkey" >/dev/null || return 1
    if [ "$_msf_with_marker" = "yes" ]; then
      _mcp_write_marker "$IO_SCRIPT" "$_msf_jkey" "$_msf_feature" "$_msf_key" "$_msf_summary" \
        || return 1
    fi
    printf '%s\t%s\n' "$_msf_key" "$_msf_summary"
  done
}

# _normalized_map_rows FEATURE — imprime jira-map.tsv (sem cabecalho, sem a
# coluna local_key do Epic, que e sempre o nome da feature e por isso varia
# entre os dois cenarios deste teste) ordenado por kind, para comparacao
# estrutural entre os dois caminhos.
_normalized_map_rows() {
  _nmr_file="$TMPDIR_TEST/docs/specs/$1/jira-map.tsv"
  awk -F'\t' 'NR>1 { if ($2=="epic") $1="EPIC"; print }' OFS='\t' "$_nmr_file" | sort
}

scenario_rest_e_mcp_produzem_mesmo_summary_e_mesmo_jira_map() {
  # --- caminho REST: jira-sync.sh convert real, contra stub de rede -------
  _write_full_config
  _write_tasks_md "demo"
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
  PATH="$_bin:$PATH" assert_exit 0 "$SYNC_SCRIPT" convert --feature demo || return 1

  _rest_epic_summary=$("$IO_SCRIPT" json-get '.fields.summary' < "$TMPDIR_TEST/queue-curl-body-3.json")
  # chamada 6 = R1 da task (3=R1 epic,4=R3 epic,5=R6 epic, 11.1.1)
  _rest_task_summary=$("$IO_SCRIPT" json-get '.fields.summary' < "$TMPDIR_TEST/queue-curl-body-6.json")
  # chamada 9 = R1 da sub-task (6=R1 task,7=R3 task,8=R6 task)
  _rest_sub_summary=$("$IO_SCRIPT" json-get '.fields.summary' < "$TMPDIR_TEST/queue-curl-body-9.json")

  # SyncMarker inicial gravado pelo REST (bodies 5/8/11 = R6 PUT de
  # epic/task/sub-task respectivamente)
  _rest_epic_marker_sha=$("$IO_SCRIPT" json-get '.written_summary_sha256' < "$TMPDIR_TEST/queue-curl-body-5.json")
  _rest_epic_marker_status=$("$IO_SCRIPT" json-get '.written_status' < "$TMPDIR_TEST/queue-curl-body-5.json")

  # --- caminho MCP: simulacao do algoritmo da skill, feature separada -----
  _write_tasks_md "demo2"
  _mcp_out=$(_mcp_simulate "demo2") || { _fail "mcp_simulate_falhou" "algoritmo MCP simulado retornou erro"; return 1; }

  _mcp_epic_summary=$(printf '%s\n' "$_mcp_out" | awk -F'\t' -v k="demo2" '$1==k{print $2}')
  _mcp_task_summary=$(printf '%s\n' "$_mcp_out" | awk -F'\t' -v k="1.1" '$1==k{print $2}')
  _mcp_sub_summary=$(printf '%s\n' "$_mcp_out" | awk -F'\t' -v k="1.1.1" '$1==k{print $2}')

  [ "$_rest_epic_summary" = "$_mcp_epic_summary" ] \
    || { _fail "JCP-1_epic" "REST='$_rest_epic_summary' MCP='$_mcp_epic_summary'"; return 1; }
  [ "$_rest_task_summary" = "$_mcp_task_summary" ] \
    || { _fail "JCP-1_task" "REST='$_rest_task_summary' MCP='$_mcp_task_summary'"; return 1; }
  [ "$_rest_sub_summary" = "$_mcp_sub_summary" ] \
    || { _fail "JCP-1_subtask" "REST='$_rest_sub_summary' MCP='$_mcp_sub_summary'"; return 1; }

  # --- JCP-2: jira-map.tsv estruturalmente identico (kind/id/key/state) ---
  _rest_rows=$(_normalized_map_rows "demo")
  _mcp_rows=$(_normalized_map_rows "demo2")
  [ "$_rest_rows" = "$_mcp_rows" ] \
    || { _fail "JCP-2_map_identico" "REST=[$_rest_rows] MCP=[$_mcp_rows]"; return 1; }

  # --- JCP-3: reexecucao da simulacao MCP nao acrescenta linha nova -------
  _mcp_out_2=$(_mcp_simulate "demo2") || { _fail "mcp_simulate_2a_falhou" "2a chamada retornou erro"; return 1; }
  [ -z "$_mcp_out_2" ] \
    || { _fail "JCP-3_idempotente" "2a simulacao deveria criar 0 itens, saida: $_mcp_out_2"; return 1; }
  return 0
}

# JCP-4 (FASE 11 tarefa 11.2.1): SyncMarker inicial estruturalmente
# identico nos dois caminhos, para o MESMO summary/status.
scenario_rest_e_mcp_gravam_mesmo_syncmarker_inicial() {
  _write_full_config
  _write_tasks_md "demo"
  _write_credential
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  _bin="$(_init_queue_stub)"
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
  PATH="$_bin:$PATH" assert_exit 0 "$SYNC_SCRIPT" convert --feature demo || return 1
  _rest_epic_marker_sha=$("$IO_SCRIPT" json-get '.written_summary_sha256' < "$TMPDIR_TEST/queue-curl-body-5.json")
  _rest_epic_marker_status=$("$IO_SCRIPT" json-get '.written_status' < "$TMPDIR_TEST/queue-curl-body-5.json")

  # --- MCP simulado (SKILL.md ETAPA 2b passo 7b), feature/stub separados --
  _write_tasks_md "demo3"
  _bin2="$(_init_queue_stub)"
  _queue_push 200 '{"fields":{"status":{"name":"To Do"}}}'
  _queue_push 201 ''
  _queue_push 200 '{"fields":{"status":{"name":"To Do"}}}'
  _queue_push 201 ''
  _queue_push 200 '{"fields":{"status":{"name":"To Do"}}}'
  _queue_push 201 ''
  _mcp_out=$(PATH="$_bin2:$PATH" _mcp_simulate "demo3" --with-marker) \
    || { _fail "jcp4_mcp_simulate_falhou" "simulacao MCP com marker retornou erro"; return 1; }
  [ -n "$_mcp_out" ] || { _fail "jcp4_mcp_simulate_vazio" "esperava 3 itens criados"; return 1; }

  # call 2 da fila do MCP = R6 PUT do marker do Epic (1=R3 epic,2=R6 epic)
  _mcp_epic_marker_sha=$("$IO_SCRIPT" json-get '.written_summary_sha256' < "$TMPDIR_TEST/queue-curl-body-2.json")
  _mcp_epic_marker_status=$("$IO_SCRIPT" json-get '.written_status' < "$TMPDIR_TEST/queue-curl-body-2.json")

  [ "$_rest_epic_marker_sha" = "$_mcp_epic_marker_sha" ] \
    || { _fail "JCP-4_marker_sha" "REST='$_rest_epic_marker_sha' MCP='$_mcp_epic_marker_sha'"; return 1; }
  [ "$_rest_epic_marker_status" = "$_mcp_epic_marker_status" ] \
    || { _fail "JCP-4_marker_status" "REST='$_rest_epic_marker_status' MCP='$_mcp_epic_marker_status'"; return 1; }
  return 0
}

run_all_scenarios
