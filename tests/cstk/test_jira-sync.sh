#!/bin/sh
# test_jira-sync.sh — cobre plugins/cstk-jira/scripts/jira-sync.sh
# (cstk-jira, FASE 4 tarefa 4.1 "plan/convert").
#
# Ref: docs/specs/cstk-jira/spec.md US1; docs/specs/cstk-jira/plan.md fluxo 2
#      "Convert"; docs/specs/cstk-jira/contracts/plugin-scripts.md
#      `jira-sync.sh`; docs/specs/cstk-jira/contracts/jira-rest.md R1;
#      data-model.md Entity LocalWorkItem/SyncMapping; tasks.md 4.1.1-4.1.7.
#
# Estrategia (mesma disciplina de test_jira-io.sh): NENHUM cenario toca rede.
# `convert` fala com o Jira exclusivamente via jira-io.sh, que so fala com
# `curl` — os cenarios de `convert` instalam um `curl` STUB por FILA
# (queue-curl-queue.tsv: 1 linha "http_code|body" por chamada esperada, NA
# ORDEM); o stub consome a linha correspondente ao NUMERO da chamada corrente
# (contagem de linhas ja gravadas em queue-curl-calls.log), preservando corpo
# de request (`--data-binary @file`) em queue-curl-body-<n>.json para
# inspecao posterior via `jira-io.sh json-get` (evita fragilidade de grep
# sobre JSON pretty-printed). Cenarios de `plan` nunca tocam jira-io.sh (so
# jira-config.sh/jira-tasks.sh/jira-map.sh, POSIX puro) — nenhum stub de rede
# e necessario para eles.
#
# Invariantes cobertos:
#
# plan:
#   SY-1  plan: ProjectConfig ausente -> exit 3 (propagado)
#   SY-2  plan: sem jira-map.tsv -> todo item vira "create" (epic+task+sub)
#   SY-3  plan: local_key mapeado active -> "update" com target_status
#         projetado do local_state via ProjectConfig (nao consulta o Jira)
#   SY-4  plan: local_key ja marcado orphan no mapeamento -> reportado como
#         "orphan", jira-map.tsv NUNCA reescrito (byte a byte identico)
#   SY-5  plan: local_key active no mapeamento mas ausente de tasks.md ->
#         "orphan" (leitura pura — jira-map.sh mark-orphans NUNCA invocado,
#         arquivo permanece com state=active)
#   SY-6  plan: ultima linha e sempre "conflicts n-a ..." (deteccao completa
#         e responsabilidade de drain/FASE 4.2, plan nunca inventa veredito)
#
# convert (pre-condicoes, US1 cenario 3):
#   SY-7  convert: ProjectConfig ausente -> exit 3, ZERO chamadas de rede,
#         jira-map.tsv nunca criado
#   SY-8  convert: credencial ausente -> exit 4, ZERO chamadas de rede,
#         jira-map.tsv nunca criado
#   SY-9  convert: credencial rejeitada (GET /myself -> 401) -> exit 4
#         (4.1.6), EXATAMENTE 1 chamada de rede (myself), zero criacoes,
#         jira-map.tsv nunca criado
#
# convert (fluxo principal, 4.1.3):
#   SY-10 convert: feature com 1 task + 1 sub-task -> cria Epic, Task
#         (parent=Epic), Sub-task (parent=Task), gravando jira-map.tsv com
#         as 3 linhas active; fields.parent.key de cada corpo de request
#         confere com a key da issue pai recem-criada; Epic nao envia
#         fields.parent; fields.summary da Task usa "[FASE N] N.M <titulo>"
#
# convert (idempotencia/incrementalidade):
#   SY-11 convert (SC-002): 10 execucoes seguidas da MESMA feature -> exatas
#         3 chamadas POST /rest/api/3/issue no total (todas na 1a execucao);
#         das 9 reexecucoes seguintes, 0 criacoes (jira-map.tsv inalterado)
#   SY-30 convert (SC-002, 8.2.1/8.2.2): fixture com 2 FEATURES e multiplas
#         tasks/sub-tasks cada, stub com ESTADO PERSISTENTE (aloca id/key de
#         issue incrementalmente a cada POST, em vez de fila pre-roteirizada
#         por indice de chamada — mais fiel a um servidor Jira real e escala
#         sem precisar pre-computar N respostas por chamada) -> 10 execucoes
#         de `convert` por feature resultam em exatamente 1 POST/issue por
#         item local (8 no total: 4+4), zero criacoes nas 9 reexecucoes
#         seguintes de cada feature
#   SY-12 convert (US1 cenario 2): task nova acrescentada ao tasks.md apos
#         conversao anterior -> convert cria SOMENTE a task nova associada
#         ao Epic ja existente (nenhuma chamada para os itens ja mapeados)
#
# convert/drain (falha, 8.3 — end-to-end; classificacao fina 401/403/429 ja
# exaustivamente coberta em test_jira-io.sh JI-33..JI-47; aqui so a
# PROPAGACAO ate jira-sync.sh e verificada, sem duplicar a classificacao):
#   SY-31 drain: 401 em R3 (qualquer operacao) -> evento vira `auth_failed`
#         com EXATAMENTE 1 chamada de rede (sem retry; drain interrompe o
#         processamento do evento, `_JSPE_BREAK`)
#   SY-32 convert: 403 na criacao de issue (--op R1) -> exit 7
#         (permission_denied, jira-io.sh JI-34), EXATAMENTE 3 chamadas
#         (myself+project+create, a que falha, sem retry), jira-map.tsv
#         NUNCA ganha a linha do item que falhou
#   SY-33 drain: 403 em R3 (fora de R1/R2, "demais operacoes") -> mesma
#         classificacao de SY-31 (`auth_failed`, default conservador
#         JI-36/JI-37), EXATAMENTE 1 chamada
#   SY-34 drain: 429 com header `Retry-After` em R3 -> evento vira
#         `deferred` (nunca `auth_failed`/`conflict`/`done`), EXATAMENTE 1
#         chamada (sem retry — 429 nao entra no loop de backoff de 5xx/rede)
#   SY-35 convert: dependencias ausentes (jq E cliente HTTP) -> exit 5,
#         PATH minimo explicito controlado NA CHAMADA INTEIRA do script sob
#         teste (substituicao total contendo so `dirname`, o UNICO binario
#         externo exercitado antes de `jira-io.sh deps-check` abortar —
#         "Verificar" 8.3.5), mensagem cita jq e curl
#
# enqueue/drain (FASE 4.2 COMPLETA — 4.2.1-4.2.8/4.2.10/4.2.11; deteccao de
# conflito/transicao real via R4/R6 fechada na onda-022, dec-081):
#   SY-13 enqueue: 1a chamada cria outbox.tsv com cabecalho + 1 linha
#         (status=queued, attempts=0); --state/--source fora do enum -> exit
#         2, outbox.tsv nunca criado
#   SY-14 drain: lock (`runtime/.drain.lock/`) ja ocupado -> exit 0
#         imediato, outbox.tsv NAO tocado (simula 2 chamadas concorrentes,
#         4.2.9 — a que "chega depois" sai sem processar nem erro)
#   SY-15 drain: compactacao remove eventos `done`, preserva `queued`
#         (4.2.8); lock e sempre liberado ao final (rmdir)
#   SY-16 drain: evento `auth_failed` presente para a feature -> nenhum
#         evento `queued` da MESMA feature e alterado, diagnostico em
#         stderr citando FR-016 (4.2.6)
#   SY-17 drain: evento `auth_failed` de OUTRA feature nao bloqueia o drain
#         da feature corrente (gate e por feature, nao global)
#   SY-18 drain (4.2.5): sem conflito -> resolve transition.id via R5,
#         executa R4, regrava o SyncMarker via R6 PUT, marca `done` (5
#         chamadas de rede na ordem R3/R6-GET/R5/R4/R6-PUT)
#   SY-19 drain (4.2.3/4.2.4/4.2.10): titulo atual diverge do sha256
#         gravado no SyncMarker -> ConflictRecord reason=manual_edit,
#         evento vira `conflict`, NENHUMA chamada de transicao/escrita
#         (so R3+R6-GET, 2 chamadas)
#   SY-20 drain (4.2.3): SyncMarker ausente (R6 GET -> 404) -> ConflictRecord
#         reason=marker_missing (nunca tratado como issue nova)
#   SY-21 drain (4.4.1): `jira-map.sh mark-orphans` roda como parte do
#         drain (pura leitura local, sem rede) — local_key ausente de
#         tasks.md vira `orphan`; NENHUMA linha e removida (4.4.2)
#   SY-28 drain (7.2.3, mapeamento coluna<->status, ux CHK008): desired_state
#         `in_progress` -> R5/R4 resolvem e executam SOMENTE a transicao cujo
#         `to.name` bate `status_in_progress` do ProjectConfig, mesmo com
#         outra transicao disponivel para um status diferente na resposta
#   SY-29 drain (7.2.3, idem SY-28 para `fail`): desired_state `fail` ->
#         R5/R4 resolvem e executam SOMENTE a transicao cujo `to.name` bate
#         `status_fail` — nenhuma coluna/nome de coluna e lido ou inferido
#         pelo cstk-jira; a issue so muda de STATUS (a coluna e resultado da
#         configuracao NATIVA do board no Jira, fora do escopo do plugin)
#
# status/resolve (FASE 4.3, resolucao SEMPRE humana, nenhum cenario toca
# rede — status/resolve nunca invocam jira-io.sh):
#   SY-22 status: outbox+conflicts+jira-map.tsv populados -> contagem
#         correta por status do outbox (queued/deferred/conflict/
#         auth_failed), linha auth_failed detalhada, conflitos pendentes
#         listados com dica de `resolve`, orfaos listados com dica de
#         `jira-map.sh relink`
#   SY-23 status --feature: filtra por feature (outra feature nao aparece)
#   SY-24 resolve: nenhum ConflictRecord pendente para (F, K) -> exit 1,
#         conflicts.tsv/outbox.tsv NUNCA tocados
#   SY-25 resolve --choice keep_jira: fecha o registro (resolution=
#         keep_jira), outbox.tsv INALTERADO (nenhum evento novo)
#   SY-26 resolve --choice ignored: fecha o registro (resolution=ignored),
#         outbox.tsv INALTERADO
#   SY-27 resolve --choice overwrite: fecha o registro (resolution=
#         overwrite) E reenfileira (novo OutboxEvent status=queued) com o
#         MESMO desired_state do evento `conflict` original

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk-jira/scripts/jira-sync.sh"
IO_SCRIPT="$REPO_ROOT/plugins/cstk-jira/scripts/jira-io.sh"

# _write_full_config: ProjectConfig completo e valido (jira-config.sh
# validate exit 0) para a feature "demo".
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

# _write_credential: credencial GLOBAL isolada (mesmo padrao de
# test_jira-io.sh) — SEMPRE combinar com XDG_CONFIG_HOME="$TMPDIR_TEST/xdg".
_write_credential() {
  mkdir -p "$TMPDIR_TEST/xdg/cstk-jira"
  printf 'email=%s\napi_token=%s\n' "tester@example.com" "tok-FAKE-000" \
    > "$TMPDIR_TEST/xdg/cstk-jira/credentials"
  chmod 600 "$TMPDIR_TEST/xdg/cstk-jira/credentials"
}

# _write_tasks_1task_1sub: docs/specs/demo/tasks.md com FASE 1 / task 1.1 /
# sub-task 1.1.1 (sem spec.md -> titulo do Epic cai para "demo").
_write_tasks_1task_1sub() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cat > "$TMPDIR_TEST/docs/specs/demo/tasks.md" <<'EOF'
## FASE 1 - Sincronizacao `[A]`

### 1.1 Titulo da tarefa `[A]`

- [ ] 1.1.1 Sub um
EOF
}

# _append_task_1_2: acrescenta uma 2a task (sem sub-task) ao tasks.md ja
# escrito por _write_tasks_1task_1sub (US1 cenario 2 / SY-12).
_append_task_1_2() {
  cat >> "$TMPDIR_TEST/docs/specs/demo/tasks.md" <<'EOF'

### 1.2 Segunda tarefa `[A]`
EOF
}

_map_file() {
  printf '%s\n' "$TMPDIR_TEST/docs/specs/demo/jira-map.tsv"
}

# _write_map_row LOCAL_KEY KIND JIRA_ID JIRA_KEY STATE — grava
# docs/specs/demo/jira-map.tsv com cabecalho + 1 linha (cria o arquivo se
# ausente, ACRESCENTA se ja existir — usado pelos cenarios de drain 4.2.3-
# 4.2.5/4.4 que precisam de um mapeamento `active`/`orphan` pre-existente).
_write_map_row() {
  _wmr_file="$(_map_file)"
  mkdir -p "$(dirname "$_wmr_file")"
  [ -f "$_wmr_file" ] || printf '%s\n' 'local_key	kind	jira_id	jira_key	state' > "$_wmr_file"
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >> "$_wmr_file"
}

# --- stub de rede por FILA (so usado pelos cenarios de convert) -----------

# _init_queue_stub: instala curl fake em $TMPDIR_TEST/bin-queue que consome,
# em ORDEM, uma linha "http_code|body" de queue-curl-queue.tsv por chamada
# (a linha N corresponde a chamada N — arquivo NUNCA reescrito, so lido por
# indice via `sed -n Np`, o que evita bugs classicos de truncamento ao
# tentar "consumir" um arquivo com `> ` no mesmo comando que o le). Registra
# "METHOD URL" de cada chamada em queue-curl-calls.log e uma COPIA do corpo
# enviado (`--data-binary @file`) em queue-curl-body-<n>.json, quando houver.
# Fila esgotada (sem linha N) -> exit 22 (erro de rede simulado).
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
_dfile=""
_prev=""
for _a in "\$@"; do
  case "\$_prev" in
    -o) _out="\$_a" ;;
    -X) _method="\$_a" ;;
    -D) _dfile="\$_a" ;;
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
if [ -n "\$_dfile" ]; then
  _hfile="$TMPDIR_TEST/queue-curl-headers-\$_n.txt"
  if [ -f "\$_hfile" ]; then
    cat -- "\$_hfile" > "\$_dfile"
  else
    : > "\$_dfile"
  fi
fi
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

# _queue_set_headers N CONTENT -> grava CONTENT (ex.: 'Retry-After: 30') no
# arquivo que o stub de _init_queue_stub copia para o destino de `-D` na
# chamada de numero N (1-based) — simula headers de resposta reais (mesmo
# padrao de _make_headers_curl_stub em test_jira-io.sh, adaptado a fila).
_queue_set_headers() {
  printf '%s\n' "$2" > "$TMPDIR_TEST/queue-curl-headers-$1.txt"
}

# _queue_push CODE BODY -> acrescenta uma resposta ao fim da fila.
_queue_push() {
  printf '%s|%s\n' "$1" "$2" >> "$TMPDIR_TEST/queue-curl-queue.tsv"
}

_queue_calls_count() {
  [ -f "$TMPDIR_TEST/queue-curl-calls.log" ] || { printf '0'; return; }
  wc -l < "$TMPDIR_TEST/queue-curl-calls.log" | tr -d ' '
}

_queue_post_issue_calls_count() {
  [ -f "$TMPDIR_TEST/queue-curl-calls.log" ] || { printf '0'; return; }
  # `grep -c` sai 1 quando NAO acha nenhuma linha (mesmo tendo impresso "0"
  # legitimamente) — capturar em variavel ANTES de decidir o fallback evita
  # o double-print "00" que `grep -c ... || printf '0'` produzia direto no
  # caso zero-matches (bug latente exposto pela 1a asserção de 0 criacoes,
  # feature cstk-jira FASE 10 tarefa 10.2/SY-39).
  _qpicc_n=$(grep -c 'POST .*api/3/issue$' "$TMPDIR_TEST/queue-curl-calls.log" 2>/dev/null) || _qpicc_n=0
  printf '%s' "$_qpicc_n"
}

# =========================== plan ==========================================

scenario_plan_config_ausente_exit3() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cd "$TMPDIR_TEST" || return 1
  assert_exit 3 "$SCRIPT" plan --feature demo || return 1
}

scenario_plan_sem_mapeamento_lista_creates() {
  _write_full_config
  _write_tasks_1task_1sub
  cd "$TMPDIR_TEST" || return 1
  assert_exit 0 "$SCRIPT" plan --feature demo || return 1
  assert_stdout_contains "create	epic	demo" || return 1
  assert_stdout_contains "create	task	1.1" || return 1
  assert_stdout_contains "create	subtask	1.1.1" || return 1
}

scenario_plan_mapeado_active_lista_update_com_target_status() {
  _write_full_config
  _write_tasks_1task_1sub
  cd "$TMPDIR_TEST" || return 1
  "$REPO_ROOT/plugins/cstk-jira/scripts/jira-map.sh" put --feature demo \
    --local-key 1.1 --kind task --jira-id 20002 --jira-key DEMO-2 >/dev/null || return 1
  assert_exit 0 "$SCRIPT" plan --feature demo || return 1
  # 1.1 sem sub-task marcada [x] -> local_state=pending -> status_pending="To Do"
  assert_stdout_contains "update	task	1.1	DEMO-2	target_status=To Do" || return 1
}

scenario_plan_orphan_ja_marcado_nao_reescreve_arquivo() {
  _write_full_config
  _write_tasks_1task_1sub
  cd "$TMPDIR_TEST" || return 1
  _map="$(_map_file)"
  mkdir -p "$(dirname "$_map")"
  printf 'local_key\tkind\tjira_id\tjira_key\tstate\n9.9\ttask\t30001\tDEMO-9\torphan\n' > "$_map"
  _before=$(cat "$_map")
  assert_exit 0 "$SCRIPT" plan --feature demo || return 1
  assert_stdout_contains "orphan	task	9.9	DEMO-9" || return 1
  _after=$(cat "$_map")
  [ "$_before" = "$_after" ] || { _fail "plan_orphan_readonly" "jira-map.tsv foi reescrito por plan"; return 1; }
}

scenario_plan_active_ausente_de_tasks_vira_orphan_sem_mutar_arquivo() {
  _write_full_config
  _write_tasks_1task_1sub
  cd "$TMPDIR_TEST" || return 1
  "$REPO_ROOT/plugins/cstk-jira/scripts/jira-map.sh" put --feature demo \
    --local-key 9.9 --kind task --jira-id 30001 --jira-key DEMO-9 >/dev/null || return 1
  _before=$(cat "$(_map_file)")
  assert_exit 0 "$SCRIPT" plan --feature demo || return 1
  assert_stdout_contains "orphan	task	9.9	DEMO-9" || return 1
  _after=$(cat "$(_map_file)")
  # plan NUNCA invoca mark-orphans: o arquivo continua com state=active para 9.9
  [ "$_before" = "$_after" ] || { _fail "plan_orphan_detection_readonly" "jira-map.tsv foi mutado por plan (deveria ser leitura pura)"; return 1; }
  grep -q '^9\.9	task	30001	DEMO-9	active$' "$(_map_file)" \
    || { _fail "plan_orphan_state_untouched" "state de 9.9 nao deveria ter sido alterado por plan"; return 1; }
}

scenario_plan_termina_com_linha_conflicts_n_a() {
  _write_full_config
  _write_tasks_1task_1sub
  cd "$TMPDIR_TEST" || return 1
  assert_exit 0 "$SCRIPT" plan --feature demo || return 1
  assert_stdout_contains "conflicts	n-a" || return 1
}

# =========================== convert: pre-condicoes =========================

scenario_convert_config_ausente_exit3_zero_chamadas() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  _bin="$(_init_queue_stub)"
  PATH="$_bin:$PATH" assert_exit 3 "$SCRIPT" convert --feature demo || return 1
  [ "$(_queue_calls_count)" = "0" ] || { _fail "convert_no_config_zero_calls" "houve chamada de rede sem ProjectConfig"; return 1; }
  [ -f "$(_map_file)" ] && { _fail "convert_no_config_no_map" "jira-map.tsv foi criado sem ProjectConfig"; return 1; }
  return 0
}

scenario_convert_credencial_ausente_exit4_zero_chamadas() {
  _write_full_config
  _write_tasks_1task_1sub
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg-vazio"
  _bin="$(_init_queue_stub)"
  PATH="$_bin:$PATH" assert_exit 4 "$SCRIPT" convert --feature demo || return 1
  [ "$(_queue_calls_count)" = "0" ] || { _fail "convert_no_cred_zero_calls" "houve chamada de rede sem credencial"; return 1; }
  [ -f "$(_map_file)" ] && { _fail "convert_no_cred_no_map" "jira-map.tsv foi criado sem credencial"; return 1; }
  return 0
}

scenario_convert_credencial_rejeitada_myself_401_exit4() {
  _write_full_config
  _write_tasks_1task_1sub
  _write_credential
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  _bin="$(_init_queue_stub)"
  _queue_push 401 '{"errorMessages":["auth rejected"]}'
  PATH="$_bin:$PATH" assert_exit 4 "$SCRIPT" convert --feature demo || return 1
  [ "$(_queue_calls_count)" = "1" ] || { _fail "convert_401_exactly_one_call" "esperado 1 chamada (myself), obtido $(_queue_calls_count)"; return 1; }
  [ -f "$(_map_file)" ] && { _fail "convert_401_no_map" "jira-map.tsv foi criado apos credencial rejeitada"; return 1; }
  return 0
}

# =========================== convert: fluxo principal =======================

scenario_convert_sucesso_cria_epic_task_subtask_com_parent_correto() {
  _write_full_config
  _write_tasks_1task_1sub
  _write_credential
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"accountId":"acc-1"}'
  _queue_push 200 '{"id":"10000","key":"DEMO"}'
  _queue_push 201 '{"id":"20001","key":"DEMO-1"}'
  _queue_push 201 '{"id":"20002","key":"DEMO-2"}'
  _queue_push 201 '{"id":"20003","key":"DEMO-3"}'
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" convert --feature demo || return 1

  [ "$(_queue_post_issue_calls_count)" = "3" ] \
    || { _fail "convert_creates_3_issues" "esperado 3 POST /issue, obtido $(_queue_post_issue_calls_count)"; return 1; }

  grep -q '^demo	epic	20001	DEMO-1	active$' "$(_map_file)" \
    || { _fail "convert_map_epic" "linha do epic ausente/incorreta"; return 1; }
  grep -q '^1\.1	task	20002	DEMO-2	active$' "$(_map_file)" \
    || { _fail "convert_map_task" "linha da task ausente/incorreta"; return 1; }
  grep -q '^1\.1\.1	subtask	20003	DEMO-3	active$' "$(_map_file)" \
    || { _fail "convert_map_subtask" "linha da sub-task ausente/incorreta"; return 1; }

  # corpo da 3a chamada (epic, call index 3) NAO tem fields.parent
  _epic_parent=$("$IO_SCRIPT" json-get '.fields.parent.key? // "none"' < "$TMPDIR_TEST/queue-curl-body-3.json")
  [ "$_epic_parent" = "none" ] || { _fail "convert_epic_no_parent" "epic nao deveria ter fields.parent (obtido $_epic_parent)"; return 1; }

  # corpo da 4a chamada (task, call index 4): parent = key do epic recem-criado
  _task_parent=$("$IO_SCRIPT" json-get '.fields.parent.key? // "none"' < "$TMPDIR_TEST/queue-curl-body-4.json")
  [ "$_task_parent" = "DEMO-1" ] || { _fail "convert_task_parent_is_epic" "esperado parent=DEMO-1, obtido $_task_parent"; return 1; }
  _task_summary=$("$IO_SCRIPT" json-get '.fields.summary' < "$TMPDIR_TEST/queue-curl-body-4.json")
  [ "$_task_summary" = "[FASE 1] 1.1 Titulo da tarefa" ] \
    || { _fail "convert_task_summary_format" "esperado '[FASE 1] 1.1 Titulo da tarefa', obtido '$_task_summary'"; return 1; }

  # corpo da 5a chamada (sub-task, call index 5): parent = key da task recem-criada
  _sub_parent=$("$IO_SCRIPT" json-get '.fields.parent.key? // "none"' < "$TMPDIR_TEST/queue-curl-body-5.json")
  [ "$_sub_parent" = "DEMO-2" ] || { _fail "convert_subtask_parent_is_task" "esperado parent=DEMO-2, obtido $_sub_parent"; return 1; }
  return 0
}

# =========================== convert: idempotencia/incrementalidade ========

scenario_convert_idempotente_10x_3_criacoes_no_total() {
  _write_full_config
  _write_tasks_1task_1sub
  _write_credential
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  _bin="$(_init_queue_stub)"
  # 1a execucao: myself + project + 3 creates
  _queue_push 200 '{"accountId":"acc-1"}'
  _queue_push 200 '{"id":"10000","key":"DEMO"}'
  _queue_push 201 '{"id":"20001","key":"DEMO-1"}'
  _queue_push 201 '{"id":"20002","key":"DEMO-2"}'
  _queue_push 201 '{"id":"20003","key":"DEMO-3"}'
  # execucoes 2-10: myself + project + 1 GET R3 por item ja mapeado (FR-003,
  # feature cstk-jira FASE 10 tarefa 10.2 — _js_maybe_update_mapped_issue
  # checa divergencia antes de decidir nao-criar); summary devolvido IDENTICO
  # ao composto na criacao -> no-op imediato, SEM leitura do SyncMarker (R6) e
  # SEM nenhuma criacao.
  _i=2
  while [ "$_i" -le 10 ]; do
    _queue_push 200 '{"accountId":"acc-1"}'
    _queue_push 200 '{"id":"10000","key":"DEMO"}'
    _queue_push 200 '{"fields":{"summary":"demo"}}'
    _queue_push 200 '{"fields":{"summary":"[FASE 1] 1.1 Titulo da tarefa"}}'
    _queue_push 200 '{"fields":{"summary":"Sub um"}}'
    _i=$((_i + 1))
  done

  _i=1
  while [ "$_i" -le 10 ]; do
    PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" convert --feature demo || return 1
    _i=$((_i + 1))
  done

  [ "$(_queue_post_issue_calls_count)" = "3" ] \
    || { _fail "convert_idempotent_3_total" "esperado 3 POST /issue no total apos 10 execucoes, obtido $(_queue_post_issue_calls_count)"; return 1; }
  _rows=$(awk -F '\t' 'NR>1' "$(_map_file)" | wc -l | tr -d ' ')
  [ "$_rows" = "3" ] || { _fail "convert_idempotent_3_rows" "esperado 3 linhas em jira-map.tsv, obtido $_rows"; return 1; }
  return 0
}

scenario_convert_task_nova_cria_somente_a_nova() {
  _write_full_config
  _write_tasks_1task_1sub
  _write_credential
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"accountId":"acc-1"}'
  _queue_push 200 '{"id":"10000","key":"DEMO"}'
  _queue_push 201 '{"id":"20001","key":"DEMO-1"}'
  _queue_push 201 '{"id":"20002","key":"DEMO-2"}'
  _queue_push 201 '{"id":"20003","key":"DEMO-3"}'
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" convert --feature demo || return 1

  _append_task_1_2
  _queue_push 200 '{"accountId":"acc-1"}'
  _queue_push 200 '{"id":"10000","key":"DEMO"}'
  # FR-003 (feature cstk-jira FASE 10 tarefa 10.2): epic/task 1.1/sub 1.1.1 ja
  # mapeados -> _js_maybe_update_mapped_issue checa cada um (1 GET R3, summary
  # devolvido identico ao composto -> no-op) ANTES da task 1.2 (nova) ser criada.
  _queue_push 200 '{"fields":{"summary":"demo"}}'
  _queue_push 200 '{"fields":{"summary":"[FASE 1] 1.1 Titulo da tarefa"}}'
  _queue_push 200 '{"fields":{"summary":"Sub um"}}'
  _queue_push 201 '{"id":"20004","key":"DEMO-4"}'
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" convert --feature demo || return 1

  [ "$(_queue_post_issue_calls_count)" = "4" ] \
    || { _fail "convert_new_task_total_creates" "esperado 4 POST /issue no total, obtido $(_queue_post_issue_calls_count)"; return 1; }
  grep -q '^1\.2	task	20004	DEMO-4	active$' "$(_map_file)" \
    || { _fail "convert_new_task_mapped" "task nova (1.2) nao foi mapeada corretamente"; return 1; }
  # a nova task usa o Epic ja existente como parent (call index 11: 6=myself,
  # 7=project, 8/9/10=R3 dos 3 itens ja mapeados (FR-003), 11=create)
  _new_task_parent=$("$IO_SCRIPT" json-get '.fields.parent.key? // "none"' < "$TMPDIR_TEST/queue-curl-body-11.json")
  [ "$_new_task_parent" = "DEMO-1" ] \
    || { _fail "convert_new_task_parent_is_existing_epic" "esperado parent=DEMO-1 (epic existente), obtido $_new_task_parent"; return 1; }
  return 0
}

# =========================== enqueue/drain ==================================

_outbox_file() {
  printf '%s\n' "$TMPDIR_TEST/.claude/cstk-jira/runtime/outbox.tsv"
}

_conflicts_file() {
  printf '%s\n' "$TMPDIR_TEST/.claude/cstk-jira/runtime/conflicts.tsv"
}

_drain_lock_dir() {
  printf '%s\n' "$TMPDIR_TEST/.claude/cstk-jira/runtime/.drain.lock"
}

scenario_enqueue_cria_outbox_com_cabecalho_e_linha_queued() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 0 "$SCRIPT" enqueue --feature demo --local-key 1.1 --state pass --source manual || return 1
  [ -f "$(_outbox_file)" ] || { _fail "enqueue_creates_outbox" "outbox.tsv nao foi criado"; return 1; }
  head -n1 "$(_outbox_file)" | grep -q '^event_id	created_at	feature	local_key	desired_state	source	attempts	status$' \
    || { _fail "enqueue_header" "cabecalho do outbox.tsv incorreto"; return 1; }
  _line=$(awk -F '\t' 'NR==2' "$(_outbox_file)")
  printf '%s' "$_line" | grep -q '	demo	1.1	pass	manual	0	queued$' \
    || { _fail "enqueue_line" "linha gravada incorreta: $_line"; return 1; }
  return 0
}

scenario_enqueue_state_invalido_exit2_sem_criar_outbox() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 2 "$SCRIPT" enqueue --feature demo --local-key 1.1 --state bogus --source manual || return 1
  [ -f "$(_outbox_file)" ] && { _fail "enqueue_bad_state_no_outbox" "outbox.tsv foi criado com --state invalido"; return 1; }
  return 0
}

scenario_enqueue_source_invalido_exit2_sem_criar_outbox() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 2 "$SCRIPT" enqueue --feature demo --local-key 1.1 --state pending --source bogus || return 1
  [ -f "$(_outbox_file)" ] && { _fail "enqueue_bad_source_no_outbox" "outbox.tsv foi criado com --source invalido"; return 1; }
  return 0
}

scenario_drain_lock_ocupado_sai_exit0_sem_tocar_outbox() {
  cd "$TMPDIR_TEST" || return 1
  "$SCRIPT" enqueue --feature demo --local-key 1.1 --state pending --source manual >/dev/null || return 1
  _before=$(cat "$(_outbox_file)")
  mkdir -p "$(_drain_lock_dir)"
  assert_exit 0 "$SCRIPT" drain --feature demo || return 1
  _after=$(cat "$(_outbox_file)")
  [ "$_before" = "$_after" ] \
    || { _fail "drain_lock_busy_no_touch" "outbox.tsv foi alterado mesmo com lock ocupado"; return 1; }
  [ -d "$(_drain_lock_dir)" ] \
    || { _fail "drain_lock_busy_keeps_dir" "drain removeu o lock de OUTRO dono ao sair"; return 1; }
  return 0
}

scenario_drain_compacta_done_preserva_queued_e_libera_lock() {
  cd "$TMPDIR_TEST" || return 1
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	1.1	pass	manual	0	done
e2	2026-01-01T00:00:01Z	demo	1.2	pending	manual	0	queued
EOF
  assert_exit 0 "$SCRIPT" drain --feature demo || return 1
  grep -q '^e1	' "$(_outbox_file)" && { _fail "drain_compaction_removes_done" "evento done nao foi removido"; return 1; }
  grep -q '^e2	' "$(_outbox_file)" || { _fail "drain_compaction_keeps_queued" "evento queued foi removido indevidamente"; return 1; }
  [ -d "$(_drain_lock_dir)" ] && { _fail "drain_releases_lock" "lock nao foi liberado apos drain"; return 1; }
  return 0
}

scenario_drain_auth_failed_bloqueia_e_nao_altera_queued_da_mesma_feature() {
  cd "$TMPDIR_TEST" || return 1
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	1.1	pass	manual	0	auth_failed
e2	2026-01-01T00:00:01Z	demo	1.2	pending	manual	0	queued
EOF
  _before_e2=$(awk -F '\t' '$1=="e2"' "$(_outbox_file)")
  assert_exit 0 "$SCRIPT" drain --feature demo || return 1
  assert_stderr_contains "FR-016" || return 1
  _after_e2=$(awk -F '\t' '$1=="e2"' "$(_outbox_file)")
  [ "$_before_e2" = "$_after_e2" ] \
    || { _fail "drain_auth_failed_no_touch" "evento queued da mesma feature foi alterado apesar do gate auth_failed"; return 1; }
  return 0
}

scenario_drain_auth_failed_de_outra_feature_nao_bloqueia() {
  cd "$TMPDIR_TEST" || return 1
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	outra-feature	9.9	pass	manual	0	auth_failed
e2	2026-01-01T00:00:01Z	demo	1.2	pending	manual	0	queued
EOF
  assert_exit 0 "$SCRIPT" drain --feature demo || return 1
  case "${_CAPTURED_STDERR:-}" in
    *FR-016*) _fail "drain_cross_feature_gate" "gate auth_failed vazou de outra feature"; return 1 ;;
  esac
  grep -q '^e2	' "$(_outbox_file)" || { _fail "drain_cross_feature_queued_kept" "evento queued da feature corrente sumiu"; return 1; }
  return 0
}

# =========================== drain: 4.2.3-4.2.5 (deteccao de conflito/transicao real) ====

# SY-18 drain: sem conflito (sha256(titulo) e status atuais batem com o
# SyncMarker) -> resolve transition.id via R5, executa R4, regrava o
# SyncMarker via R6 PUT, marca o evento `done`. Exatamente 5 chamadas de
# rede na ordem R3/R6-GET/R5/R4/R6-PUT.
scenario_drain_sem_conflito_transiciona_e_grava_marker() {
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

  [ "$(_queue_calls_count)" = "5" ] \
    || { _fail "drain_ok_calls_count" "esperado 5 chamadas, obtido $(_queue_calls_count)"; return 1; }
  awk -F '\t' '$1=="e1"' "$(_outbox_file)" | grep -q 'done$' \
    || { _fail "drain_ok_marks_done" "evento e1 nao foi marcado done: $(awk -F '\t' '$1==\"e1\"' "$(_outbox_file)")"; return 1; }

  _trans_id=$("$IO_SCRIPT" json-get '.transition.id' < "$TMPDIR_TEST/queue-curl-body-4.json")
  [ "$_trans_id" = "31" ] || { _fail "drain_ok_transition_id" "esperado transition.id=31, obtido $_trans_id"; return 1; }

  _marker_status=$("$IO_SCRIPT" json-get '.written_status' < "$TMPDIR_TEST/queue-curl-body-5.json")
  [ "$_marker_status" = "Done" ] || { _fail "drain_ok_marker_status" "esperado written_status=Done, obtido $_marker_status"; return 1; }
  _marker_lkey=$("$IO_SCRIPT" json-get '.local_key' < "$TMPDIR_TEST/queue-curl-body-5.json")
  [ "$_marker_lkey" = "1.1" ] || { _fail "drain_ok_marker_local_key" "esperado local_key=1.1, obtido $_marker_lkey"; return 1; }
  return 0
}

# SY-28 drain (tasks.md 7.2.1/7.2.3, ux CHK008): desired_state=in_progress
# com status atual "To Do" (status_pending) e DUAS transicoes disponiveis na
# resposta de R5 (uma para "Failed", outra para "In Progress") -> R4 MUST
# escolher exatamente a transicao cujo `to.name` bate `status_in_progress`
# do ProjectConfig ("In Progress"), nunca a primeira da lista nem a de
# `status_fail`. Prova que a "coluna" (derivada pelo Jira a partir do
# STATUS) segue o mapeamento configurado, sem nenhuma inferencia de nome de
# coluna pelo cstk-jira (nenhum literal "coluna" aparece no motor).
scenario_drain_transicao_in_progress_usa_status_mapeado() {
  _write_full_config
  _write_credential
  _write_map_row "1.2" task 20004 DEMO-4 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	1.2	in_progress	manual	0	queued
EOF
  _sha=$(printf '%s' "Titulo Atual" | "$IO_SCRIPT" sha256-stdin)
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"fields":{"summary":"Titulo Atual","status":{"name":"To Do"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha\",\"written_status\":\"To Do\"}}"
  _queue_push 200 '{"transitions":[{"id":"41","to":{"name":"Failed"}},{"id":"5","to":{"name":"In Progress"}}]}'
  _queue_push 204 ''
  _queue_push 200 ''
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" drain --feature demo || return 1

  awk -F '\t' '$1=="e1"' "$(_outbox_file)" | grep -q 'done$' \
    || { _fail "drain_in_progress_marks_done" "evento e1 nao foi marcado done: $(awk -F '\t' '$1==\"e1\"' "$(_outbox_file)")"; return 1; }
  _trans_id=$("$IO_SCRIPT" json-get '.transition.id' < "$TMPDIR_TEST/queue-curl-body-4.json")
  [ "$_trans_id" = "5" ] || { _fail "drain_in_progress_transition_id" "esperado transition.id=5 (In Progress), obtido $_trans_id"; return 1; }
  _marker_status=$("$IO_SCRIPT" json-get '.written_status' < "$TMPDIR_TEST/queue-curl-body-5.json")
  [ "$_marker_status" = "In Progress" ] || { _fail "drain_in_progress_marker_status" "esperado written_status='In Progress', obtido $_marker_status"; return 1; }
  return 0
}

# SY-29 drain (tasks.md 7.2.1/7.2.3, ux CHK008): desired_state=fail, status
# atual "In Progress", com transicoes disponiveis para "Done" e "Failed" ->
# R4 MUST escolher a transicao cujo `to.name` bate `status_fail` ("Failed"),
# nunca `status_pass` ("Done"). Mesmo par (pass/fail) que SY-18 ja cobre em
# ordem inversa — aqui fecha a combinacao restante (fail com pass presente
# na mesma resposta de R5).
scenario_drain_transicao_fail_usa_status_mapeado() {
  _write_full_config
  _write_credential
  _write_map_row "1.3" task 20005 DEMO-5 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	1.3	fail	manual	0	queued
EOF
  _sha=$(printf '%s' "Titulo Atual" | "$IO_SCRIPT" sha256-stdin)
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"fields":{"summary":"Titulo Atual","status":{"name":"In Progress"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha\",\"written_status\":\"In Progress\"}}"
  _queue_push 200 '{"transitions":[{"id":"11","to":{"name":"Done"}},{"id":"61","to":{"name":"Failed"}}]}'
  _queue_push 204 ''
  _queue_push 200 ''
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" drain --feature demo || return 1

  awk -F '\t' '$1=="e1"' "$(_outbox_file)" | grep -q 'done$' \
    || { _fail "drain_fail_marks_done" "evento e1 nao foi marcado done: $(awk -F '\t' '$1==\"e1\"' "$(_outbox_file)")"; return 1; }
  _trans_id=$("$IO_SCRIPT" json-get '.transition.id' < "$TMPDIR_TEST/queue-curl-body-4.json")
  [ "$_trans_id" = "61" ] || { _fail "drain_fail_transition_id" "esperado transition.id=61 (Failed), obtido $_trans_id"; return 1; }
  _marker_status=$("$IO_SCRIPT" json-get '.written_status' < "$TMPDIR_TEST/queue-curl-body-5.json")
  [ "$_marker_status" = "Failed" ] || { _fail "drain_fail_marker_status" "esperado written_status=Failed, obtido $_marker_status"; return 1; }
  return 0
}

# SY-19 drain: titulo atual diverge do sha256 gravado no SyncMarker ->
# ConflictRecord (reason=manual_edit), evento vira `conflict`, NUNCA
# sobrescreve (FR-011) — so 2 chamadas de rede (R3 + R6-GET), nenhuma
# transicao/escrita.
scenario_drain_conflito_manual_edit_gera_conflict_record_sem_sobrescrever() {
  _write_full_config
  _write_credential
  _write_map_row "1.1" task 20002 DEMO-2 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	1.1	pending	manual	0	queued
EOF
  _sha_original=$(printf '%s' "Titulo Original" | "$IO_SCRIPT" sha256-stdin)
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"fields":{"summary":"Titulo Mudou Manualmente","status":{"name":"To Do"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_original\",\"written_status\":\"To Do\"}}"
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" drain --feature demo || return 1

  [ "$(_queue_calls_count)" = "2" ] \
    || { _fail "drain_conflict_calls_count" "esperado 2 chamadas (R3+R6-GET), obtido $(_queue_calls_count)"; return 1; }
  awk -F '\t' '$1=="e1"' "$(_outbox_file)" | grep -q 'conflict$' \
    || { _fail "drain_conflict_marks_conflict" "evento e1 nao foi marcado conflict"; return 1; }
  [ -f "$TMPDIR_TEST/.claude/cstk-jira/runtime/conflicts.tsv" ] \
    || { _fail "drain_conflict_writes_file" "conflicts.tsv nao foi criado"; return 1; }
  grep -q 'demo	1\.1	DEMO-2	manual_edit	pending$' "$TMPDIR_TEST/.claude/cstk-jira/runtime/conflicts.tsv" \
    || { _fail "drain_conflict_record_reason" "ConflictRecord ausente/incorreto: $(cat "$TMPDIR_TEST/.claude/cstk-jira/runtime/conflicts.tsv")"; return 1; }
  return 0
}

# SY-20 drain: SyncMarker ausente (GET .../properties -> 404) -> tratado
# como conflito (reason=marker_missing), NUNCA como issue nova a sincronizar
# do zero (data-model.md Entity SyncMarker).
scenario_drain_marker_ausente_404_vira_conflict_marker_missing() {
  _write_full_config
  _write_credential
  _write_map_row "1.1" task 20002 DEMO-2 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	1.1	pending	manual	0	queued
EOF
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"fields":{"summary":"Qualquer Titulo","status":{"name":"To Do"}}}'
  _queue_push 404 '{"errorMessages":["Property not found."]}'
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" drain --feature demo || return 1

  awk -F '\t' '$1=="e1"' "$(_outbox_file)" | grep -q 'conflict$' \
    || { _fail "drain_marker_missing_marks_conflict" "evento e1 nao foi marcado conflict"; return 1; }
  grep -q 'demo	1\.1	DEMO-2	marker_missing	pending$' "$TMPDIR_TEST/.claude/cstk-jira/runtime/conflicts.tsv" \
    || { _fail "drain_marker_missing_reason" "ConflictRecord ausente/incorreto: $(cat "$TMPDIR_TEST/.claude/cstk-jira/runtime/conflicts.tsv" 2>/dev/null)"; return 1; }
  return 0
}

# SY-21 drain: `jira-map.sh mark-orphans` (4.4.1) roda como parte do drain
# (pura leitura/rewrite LOCAL, sem rede) — local_key ausente de tasks.md
# vira `orphan`; local_keys presentes permanecem `active`; NENHUMA linha e
# removida (4.4.2 — card orfao nunca e apagado).
scenario_drain_marca_orfaos_como_parte_do_processo() {
  _write_tasks_1task_1sub
  _write_map_row "1.1" task 20002 DEMO-2 active
  _write_map_row "1.1.1" subtask 20003 DEMO-3 active
  _write_map_row "9.9" task 20099 DEMO-9 active
  cd "$TMPDIR_TEST" || return 1
  assert_exit 0 "$SCRIPT" drain --feature demo || return 1

  grep -q '^9\.9	task	20099	DEMO-9	orphan$' "$(_map_file)" \
    || { _fail "drain_mark_orphans_flags_9_9" "9.9 nao foi marcado orphan: $(cat "$(_map_file)")"; return 1; }
  grep -q '^1\.1	task	20002	DEMO-2	active$' "$(_map_file)" \
    || { _fail "drain_mark_orphans_keeps_1_1" "1.1 deveria continuar active"; return 1; }
  [ "$(wc -l < "$(_map_file)" | tr -d ' ')" = "4" ] \
    || { _fail "drain_mark_orphans_never_deletes" "linha(s) desaparecida(s) do jira-map.tsv (4.4.2)"; return 1; }
  return 0
}

# =========================== status/resolve (FASE 4.3) ======================

# SY-22 status: agrega outbox (contagem por status + detalhe auth_failed),
# conflitos pendentes e orfaos, com as dicas de proximo comando.
scenario_status_agrega_outbox_conflitos_e_orfaos() {
  cd "$TMPDIR_TEST" || return 1
  mkdir -p "$(dirname "$(_outbox_file)")" "$TMPDIR_TEST/docs/specs/demo"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	1.1	pending	manual	0	conflict
e2	2026-01-01T00:00:01Z	demo	5.5	pass	manual	1	auth_failed
EOF
  cat > "$(_conflicts_file)" <<'EOF'
detected_at	feature	local_key	jira_key	reason	resolution
2026-01-01T00:00:00Z	demo	1.1	DEMO-2	manual_edit	pending
EOF
  cat > "$TMPDIR_TEST/docs/specs/demo/jira-map.tsv" <<'EOF'
local_key	kind	jira_id	jira_key	state
9.9	task	20099	DEMO-9	orphan
EOF
  assert_exit 0 "$SCRIPT" status || return 1
  assert_stdout_contains "queued=0 deferred=0 conflict=1 auth_failed=1" || return 1
  assert_stdout_contains "demo	5.5	e2	1" || return 1
  assert_stdout_contains "demo	1.1	DEMO-2	manual_edit" || return 1
  assert_stdout_contains "jira-sync.sh resolve --feature F --local-key K" || return 1
  assert_stdout_contains "demo	9.9	DEMO-9" || return 1
  assert_stdout_contains "jira-map.sh relink --feature F --local-key K --jira-key KEY" || return 1
  return 0
}

# SY-23 status --feature: filtra por feature — outra feature nao aparece na
# saida (nem no outbox, nem nos conflitos, nem nos orfaos).
scenario_status_filtra_por_feature() {
  cd "$TMPDIR_TEST" || return 1
  mkdir -p "$(dirname "$(_outbox_file)")" \
    "$TMPDIR_TEST/docs/specs/demo" "$TMPDIR_TEST/docs/specs/outra"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	1.1	pending	manual	0	conflict
e2	2026-01-01T00:00:01Z	outra	2.2	pass	manual	0	auth_failed
EOF
  cat > "$(_conflicts_file)" <<'EOF'
detected_at	feature	local_key	jira_key	reason	resolution
2026-01-01T00:00:00Z	demo	1.1	DEMO-2	manual_edit	pending
2026-01-01T00:00:01Z	outra	2.2	OUT-2	manual_edit	pending
EOF
  cat > "$TMPDIR_TEST/docs/specs/outra/jira-map.tsv" <<'EOF'
local_key	kind	jira_id	jira_key	state
3.3	task	30003	OUT-3	orphan
EOF
  assert_exit 0 "$SCRIPT" status --feature demo || return 1
  assert_stdout_contains "queued=0 deferred=0 conflict=1 auth_failed=0" || return 1
  assert_stdout_contains "demo	1.1	DEMO-2" || return 1
  assert_stdout_not_contains "outra" || return 1
  assert_stdout_not_contains "OUT-2" || return 1
  assert_stdout_not_contains "OUT-3" || return 1
  return 0
}

# SY-24 resolve: nenhum ConflictRecord pendente para (F, K) -> exit 1,
# nenhum arquivo tocado.
scenario_resolve_sem_conflito_pendente_exit1() {
  cd "$TMPDIR_TEST" || return 1
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_conflicts_file)" <<'EOF'
detected_at	feature	local_key	jira_key	reason	resolution
2026-01-01T00:00:00Z	demo	1.1	DEMO-2	manual_edit	keep_jira
EOF
  _before=$(cat "$(_conflicts_file)")
  assert_exit 1 "$SCRIPT" resolve --feature demo --local-key 1.1 --choice keep_jira || return 1
  _after=$(cat "$(_conflicts_file)")
  [ "$_before" = "$_after" ] \
    || { _fail "resolve_no_pending_untouched" "conflicts.tsv foi alterado mesmo sem registro pendente"; return 1; }
  [ -f "$(_outbox_file)" ] \
    && { _fail "resolve_no_pending_no_outbox" "outbox.tsv foi criado mesmo sem registro pendente"; return 1; }
  return 0
}

# SY-25 resolve --choice keep_jira: fecha o registro sem tocar o outbox.
scenario_resolve_keep_jira_fecha_registro_sem_tocar_outbox() {
  cd "$TMPDIR_TEST" || return 1
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	1.1	pending	manual	0	conflict
EOF
  cat > "$(_conflicts_file)" <<'EOF'
detected_at	feature	local_key	jira_key	reason	resolution
2026-01-01T00:00:00Z	demo	1.1	DEMO-2	manual_edit	pending
EOF
  _before_outbox=$(cat "$(_outbox_file)")
  assert_exit 0 "$SCRIPT" resolve --feature demo --local-key 1.1 --choice keep_jira || return 1
  assert_stdout_contains "escolha=keep_jira" || return 1
  grep -q 'demo	1\.1	DEMO-2	manual_edit	keep_jira$' "$(_conflicts_file)" \
    || { _fail "resolve_keep_jira_resolution" "resolution nao virou keep_jira: $(cat "$(_conflicts_file)")"; return 1; }
  _after_outbox=$(cat "$(_outbox_file)")
  [ "$_before_outbox" = "$_after_outbox" ] \
    || { _fail "resolve_keep_jira_outbox_untouched" "outbox.tsv foi alterado por keep_jira"; return 1; }
  return 0
}

# SY-26 resolve --choice ignored: fecha o registro sem tocar o outbox.
scenario_resolve_ignored_fecha_registro_sem_tocar_outbox() {
  cd "$TMPDIR_TEST" || return 1
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	9.9	pass	manual	0	conflict
EOF
  cat > "$(_conflicts_file)" <<'EOF'
detected_at	feature	local_key	jira_key	reason	resolution
2026-01-01T00:00:00Z	demo	9.9	DEMO-9	orphan	pending
EOF
  _before_outbox=$(cat "$(_outbox_file)")
  assert_exit 0 "$SCRIPT" resolve --feature demo --local-key 9.9 --choice ignored || return 1
  assert_stdout_contains "escolha=ignored" || return 1
  grep -q 'demo	9\.9	DEMO-9	orphan	ignored$' "$(_conflicts_file)" \
    || { _fail "resolve_ignored_resolution" "resolution nao virou ignored: $(cat "$(_conflicts_file)")"; return 1; }
  _after_outbox=$(cat "$(_outbox_file)")
  [ "$_before_outbox" = "$_after_outbox" ] \
    || { _fail "resolve_ignored_outbox_untouched" "outbox.tsv foi alterado por ignored"; return 1; }
  return 0
}

# SY-27 resolve --choice overwrite: fecha o registro E reenfileira um NOVO
# OutboxEvent (status=queued) com o MESMO desired_state do evento `conflict`
# original — para o proximo drain sobrescrever o Jira.
scenario_resolve_overwrite_fecha_registro_e_reenfileira() {
  cd "$TMPDIR_TEST" || return 1
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	1.1	fail	manual	0	conflict
EOF
  cat > "$(_conflicts_file)" <<'EOF'
detected_at	feature	local_key	jira_key	reason	resolution
2026-01-01T00:00:00Z	demo	1.1	DEMO-2	manual_edit	pending
EOF
  assert_exit 0 "$SCRIPT" resolve --feature demo --local-key 1.1 --choice overwrite || return 1
  assert_stdout_contains "escolha=overwrite" || return 1
  grep -q 'demo	1\.1	DEMO-2	manual_edit	overwrite$' "$(_conflicts_file)" \
    || { _fail "resolve_overwrite_resolution" "resolution nao virou overwrite: $(cat "$(_conflicts_file)")"; return 1; }
  _novo=$(awk -F '\t' '$1 != "e1" && NR > 1 { print }' "$(_outbox_file)")
  [ -n "$_novo" ] \
    || { _fail "resolve_overwrite_new_event" "nenhum evento novo foi enfileirado: $(cat "$(_outbox_file)")"; return 1; }
  printf '%s\n' "$_novo" | grep -q '	demo	1\.1	fail	manual	0	queued$' \
    || { _fail "resolve_overwrite_new_event_fields" "evento novo com campos inesperados: $_novo"; return 1; }
  return 0
}

# =========================== convert: idempotencia (8.2, estado) ===========

# _init_stateful_stub: curl fake com ESTADO PERSISTENTE entre chamadas
# (8.2.1) — em vez de consumir uma fila pre-roteirizada por indice (como
# _init_queue_stub), aloca id/key de issue de forma incremental a cada POST
# /issue (contador em arquivo), simulando um servidor Jira real que atribui
# numeracao sequencial. GET /myself e GET /project/{KEY} respondem de forma
# estavel e determinada pela URL (nao pela ordem de chamada), o que permite
# rodar fixtures ricas (multiplas features/tasks) e repeticoes (10x) sem
# precisar pre-computar N respostas manualmente. Loga "METHOD URL" em
# stateful-calls.log e preserva o corpo de cada POST /issue em
# stateful-body-<id>.json para inspecao posterior.
_init_stateful_stub() {
  _stst_dir="$TMPDIR_TEST/bin-stateful"
  mkdir -p "$_stst_dir"
  : > "$TMPDIR_TEST/stateful-calls.log"
  printf '20000' > "$TMPDIR_TEST/stateful-next-id"
  cat > "$_stst_dir/curl" <<STUB
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
printf '%s %s\n' "\$_method" "\$_url" >> "$TMPDIR_TEST/stateful-calls.log"
case "\$_url" in
  */rest/api/3/myself)
    _code=200
    _resp='{"accountId":"acc-1"}'
    ;;
  */rest/api/3/project/*)
    _key=\${_url##*/rest/api/3/project/}
    _code=200
    _resp="{\\"id\\":\\"10000\\",\\"key\\":\\"\$_key\\"}"
    ;;
  */rest/api/3/issue)
    _idfile="$TMPDIR_TEST/stateful-next-id"
    _cur=\$(cat "\$_idfile")
    _cur=\$((_cur + 1))
    printf '%s' "\$_cur" > "\$_idfile"
    _off=\$((_cur - 20000))
    _code=201
    _resp="{\\"id\\":\\"\$_cur\\",\\"key\\":\\"DEMO-\$_off\\"}"
    if [ -n "\$_bodyfile" ] && [ -f "\$_bodyfile" ]; then
      cp -- "\$_bodyfile" "$TMPDIR_TEST/stateful-body-\$_cur.json" 2>/dev/null
    fi
    ;;
  *)
    _code=404
    _resp='{}'
    ;;
esac
[ -n "\$_out" ] && printf '%s' "\$_resp" > "\$_out"
printf '%s' "\$_code"
exit 0
STUB
  chmod +x "$_stst_dir/curl"
  printf '%s' "$_stst_dir"
}

_stateful_post_issue_calls_count() {
  [ -f "$TMPDIR_TEST/stateful-calls.log" ] || { printf '0'; return; }
  grep -c 'POST .*api/3/issue$' "$TMPDIR_TEST/stateful-calls.log" 2>/dev/null || printf '0'
}

# _write_tasks_rich FEATURE: docs/specs/<FEATURE>/tasks.md com 2 tasks na
# FASE 1 (1.1 com 1 sub-task, 1.2 sem sub-task) — fixture mais rica que
# _write_tasks_1task_1sub (usada por SY-11/SY-12), para exercitar 8.2.2 com
# multiplos itens locais por feature.
_write_tasks_rich() {
  mkdir -p "$TMPDIR_TEST/docs/specs/$1"
  cat > "$TMPDIR_TEST/docs/specs/$1/tasks.md" <<EOF
## FASE 1 - Sincronizacao \`[A]\`

### 1.1 Primeira tarefa \`[A]\`

- [ ] 1.1.1 Sub um

### 1.2 Segunda tarefa \`[A]\`
EOF
}

# scenario_convert_idempotente_10x_multi_feature_stub_com_estado — SY-30
# (8.2.1 stub com estado + 8.2.2 fixture rica multi-feature). Duas features
# ("alpha", "beta"), 3 itens locais cada (epic+2 tasks+1 sub-task = 4 itens
# por feature via _write_tasks_rich). Convert roda 10x POR feature; total de
# POST /issue esperado = 8 (4+4), estavel apos a 1a rodada de cada uma.
scenario_convert_idempotente_10x_multi_feature_stub_com_estado() {
  _write_full_config
  _write_tasks_rich alpha
  _write_tasks_rich beta
  _write_credential
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  _bin="$(_init_stateful_stub)"

  for _feature in alpha beta; do
    _i=1
    while [ "$_i" -le 10 ]; do
      PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" convert --feature "$_feature" || return 1
      _i=$((_i + 1))
    done
  done

  [ "$(_stateful_post_issue_calls_count)" = "8" ] \
    || { _fail "convert_multi_feature_idempotent_8_total" "esperado 8 POST /issue no total (4 alpha + 4 beta) apos 10x cada, obtido $(_stateful_post_issue_calls_count)"; return 1; }

  _rows_alpha=$(awk -F '\t' 'NR>1' "$TMPDIR_TEST/docs/specs/alpha/jira-map.tsv" | wc -l | tr -d ' ')
  [ "$_rows_alpha" = "4" ] || { _fail "convert_multi_feature_alpha_rows" "esperado 4 linhas em jira-map.tsv de alpha, obtido $_rows_alpha"; return 1; }
  _rows_beta=$(awk -F '\t' 'NR>1' "$TMPDIR_TEST/docs/specs/beta/jira-map.tsv" | wc -l | tr -d ' ')
  [ "$_rows_beta" = "4" ] || { _fail "convert_multi_feature_beta_rows" "esperado 4 linhas em jira-map.tsv de beta, obtido $_rows_beta"; return 1; }
  return 0
}

# =========================== falha (8.3, end-to-end) ========================
#
# Classificacao fina de status HTTP (401/403 R1-R2-vs-demais/429/5xx/rede) ja
# e exaustivamente coberta em test_jira-io.sh (JI-33..JI-47) no nivel de
# `jira-io.sh request`. Os cenarios abaixo verificam so a PROPAGACAO dessa
# classificacao ATE jira-sync.sh (convert/drain) — nao duplicam a bateria de
# classificacao, so confirmam que o motor de sincronizacao reage certo a
# cada exit code que jira-io.sh pode devolver.

# SY-31: drain, 401 na 1a chamada de rede do evento (R3) -> `auth_failed`
# (jira-io.sh exit 4), EXATAMENTE 1 chamada (sem retry — 401 nao entra no
# loop de backoff de 5xx/rede).
scenario_drain_401_em_r3_vira_auth_failed_sem_retry() {
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
  _bin="$(_init_queue_stub)"
  _queue_push 401 '{"errorMessages":["not authenticated"]}'
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" drain --feature demo || return 1

  [ "$(_queue_calls_count)" = "1" ] \
    || { _fail "drain_401_calls" "esperado exatamente 1 chamada (sem retry), obtido $(_queue_calls_count)"; return 1; }
  awk -F '\t' '$1=="e1"' "$(_outbox_file)" | grep -q 'auth_failed$' \
    || { _fail "drain_401_auth_failed" "evento e1 nao virou auth_failed: $(awk -F '\t' '$1==\"e1\"' "$(_outbox_file)")"; return 1; }
  return 0
}

# SY-32: convert, 403 na criacao da issue (--op R1) -> exit 7
# (permission_denied, JI-34), EXATAMENTE 3 chamadas no total (myself +
# project + create — a que falha, sem retry), jira-map.tsv NUNCA ganha a
# linha do item que falhou.
scenario_convert_403_na_criacao_vira_permission_denied_exit7() {
  _write_full_config
  _write_tasks_1task_1sub
  _write_credential
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"accountId":"acc-1"}'
  _queue_push 200 '{"id":"10000","key":"DEMO"}'
  _queue_push 403 '{"errorMessages":["permission denied"]}'
  PATH="$_bin:$PATH" assert_exit 7 "$SCRIPT" convert --feature demo || return 1

  [ "$(_queue_calls_count)" = "3" ] \
    || { _fail "convert_403_calls" "esperado exatamente 3 chamadas (sem retry), obtido $(_queue_calls_count)"; return 1; }
  if [ -f "$(_map_file)" ] && grep -q '^demo	epic' "$(_map_file)"; then
    _fail "convert_403_no_map_row" "jira-map.tsv nao deveria ganhar linha para o item que falhou"
    return 1
  fi
  return 0
}

# SY-33: drain, 403 em R3 (fora de R1/R2 — "demais operacoes") -> mesma
# classificacao de SY-31 (`auth_failed`, default conservador JI-36/JI-37),
# EXATAMENTE 1 chamada.
scenario_drain_403_fora_de_r1_r2_vira_auth_failed() {
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
  _bin="$(_init_queue_stub)"
  _queue_push 403 '{"errorMessages":["forbidden"]}'
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" drain --feature demo || return 1

  [ "$(_queue_calls_count)" = "1" ] \
    || { _fail "drain_403_calls" "esperado exatamente 1 chamada (sem retry), obtido $(_queue_calls_count)"; return 1; }
  awk -F '\t' '$1=="e1"' "$(_outbox_file)" | grep -q 'auth_failed$' \
    || { _fail "drain_403_auth_failed" "evento e1 nao virou auth_failed: $(awk -F '\t' '$1==\"e1\"' "$(_outbox_file)")"; return 1; }
  return 0
}

# SY-34: drain, 429 com header Retry-After em R3 -> `deferred` (nunca
# `auth_failed`/`conflict`/`done`), EXATAMENTE 1 chamada (429 nao entra no
# loop de backoff de 5xx/rede). `_queue_set_headers` simula o header real.
scenario_drain_429_vira_deferred_respeitando_retry_after() {
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
  _bin="$(_init_queue_stub)"
  _queue_push 429 '{"errorMessages":["rate limit"]}'
  _queue_set_headers 1 'Retry-After: 30'
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" drain --feature demo || return 1

  [ "$(_queue_calls_count)" = "1" ] \
    || { _fail "drain_429_calls" "esperado exatamente 1 chamada (sem retry), obtido $(_queue_calls_count)"; return 1; }
  awk -F '\t' '$1=="e1"' "$(_outbox_file)" | grep -q 'deferred$' \
    || { _fail "drain_429_deferred" "evento e1 nao virou deferred: $(awk -F '\t' '$1==\"e1\"' "$(_outbox_file)")"; return 1; }
  return 0
}

# SY-35: convert, dependencias ausentes (jq E cliente HTTP) -> exit 5
# (jira-io.sh JI-1), PATH minimo explicito EM TODA a chamada do script sob
# teste (substituicao total — nunca prefixo, mesma licao ja registrada no
# repo de que um stub prefixado nao esconde um binario real em /usr/bin).
# So `dirname` entra no PATH: e o UNICO binario externo que `jira-sync.sh
# convert` invoca (via `_js_script_dir`) antes de `jira-io.sh deps-check`
# abortar — deps-check em si so usa `command -v` (builtin do `sh`).
scenario_convert_deps_ausentes_exit5_path_minimo() {
  cd "$TMPDIR_TEST" || return 1
  _dn=$(command -v dirname 2>/dev/null) || { _error "sem_dirname_no_host" "dirname indisponivel no ambiente de teste"; return 2; }
  _bin="$TMPDIR_TEST/bin-nodeps"
  mkdir -p "$_bin"
  ln -sf "$_dn" "$_bin/dirname"
  assert_exit 5 env PATH="$_bin" "$SCRIPT" convert --feature demo || return 1
  assert_stderr_contains "jq" || return 1
  assert_stderr_contains "curl" || return 1
  return 0
}

# =========================== convert: descricao FR-001 (FASE 10 t. 10.1) ====
#
#   SY-36 convert: task com tag de criticidade (`[A]`) e SEM secao "Matriz
#         de Dependencias" -> fields.description da Task = "Criticidade: A";
#         Epic e Sub-task NUNCA ganham fields.description (data-model.md:
#         so a Task carrega criticidade/dependencia no LocalWorkItem)
#   SY-37 convert: 2 fases com "## Matriz de Dependencias" apontando
#         F1-->F2 -> Task da FASE 2 ganha "Criticidade: A | Depende de: FASE
#         1 - Fundacao"; Task da FASE 1 (sem aresta de entrada) ganha SO
#         "Criticidade: A" (sem "Depende de")
#   SY-38 convert: task SEM tag de criticidade e SEM "Matriz de
#         Dependencias" -> nenhum trecho para compor -> fields.description
#         OMITIDO do corpo (nunca uma chave vazia/nula)

# _write_tasks_2fases_com_matriz: FASE 1 (task 1.1 `[A]` + sub) e FASE 2
# (task 2.1 `[A]` + sub), com "## Matriz de Dependencias" (F1 --> F2) —
# fixture dedicada de SY-37 (fonte real e extraivel de dependencia, nunca
# inventada por-task; FR-001).
_write_tasks_2fases_com_matriz() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cat > "$TMPDIR_TEST/docs/specs/demo/tasks.md" <<'EOF'
## FASE 1 - Fundacao `[A]`

### 1.1 Titulo um `[A]`

- [ ] 1.1.1 Sub um

## FASE 2 - Sincronizacao `[A]`

### 2.1 Titulo dois `[A]`

- [ ] 2.1.1 Sub dois

## Matriz de Dependencias

```mermaid
flowchart TD
    F1[FASE 1 - Fundacao]
    F2[FASE 2 - Sincronizacao]

    F1 --> F2
```
EOF
}

# _write_tasks_1task_1sub_sem_crit: mesma forma de _write_tasks_1task_1sub,
# mas SEM a tag `` `[A]` `` no heading da task (SY-38 — sem criticidade e sem
# Matriz, description nunca deve ser passada ao json-build).
_write_tasks_1task_1sub_sem_crit() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cat > "$TMPDIR_TEST/docs/specs/demo/tasks.md" <<'EOF'
## FASE 1 - Sincronizacao `[A]`

### 1.1 Titulo da tarefa

- [ ] 1.1.1 Sub um
EOF
}

scenario_convert_description_com_criticidade_sem_matriz() {
  _write_full_config
  _write_tasks_1task_1sub
  _write_credential
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"accountId":"acc-1"}'
  _queue_push 200 '{"id":"10000","key":"DEMO"}'
  _queue_push 201 '{"id":"20001","key":"DEMO-1"}'
  _queue_push 201 '{"id":"20002","key":"DEMO-2"}'
  _queue_push 201 '{"id":"20003","key":"DEMO-3"}'
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" convert --feature demo || return 1

  _epic_desc=$("$IO_SCRIPT" json-get '.fields.description? // "none"' < "$TMPDIR_TEST/queue-curl-body-3.json")
  [ "$_epic_desc" = "none" ] || { _fail "sy36_epic_no_description" "Epic nao deveria ter fields.description (obtido $_epic_desc)"; return 1; }

  _task_desc_text=$("$IO_SCRIPT" json-get '.fields.description.content[0].content[0].text' < "$TMPDIR_TEST/queue-curl-body-4.json")
  [ "$_task_desc_text" = "Criticidade: A" ] \
    || { _fail "sy36_task_description" "esperado 'Criticidade: A', obtido '$_task_desc_text'"; return 1; }

  _sub_desc=$("$IO_SCRIPT" json-get '.fields.description? // "none"' < "$TMPDIR_TEST/queue-curl-body-5.json")
  [ "$_sub_desc" = "none" ] || { _fail "sy36_subtask_no_description" "Sub-task nao deveria ter fields.description (obtido $_sub_desc)"; return 1; }
  return 0
}

scenario_convert_description_com_criticidade_e_dependencia_da_matriz() {
  _write_full_config
  _write_tasks_2fases_com_matriz
  _write_credential
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  _bin="$(_init_queue_stub)"
  # myself + project + 5 creates (epic, task1.1, sub1.1.1, task2.1, sub2.1.1)
  _queue_push 200 '{"accountId":"acc-1"}'
  _queue_push 200 '{"id":"10000","key":"DEMO"}'
  _queue_push 201 '{"id":"20001","key":"DEMO-1"}'
  _queue_push 201 '{"id":"20002","key":"DEMO-2"}'
  _queue_push 201 '{"id":"20003","key":"DEMO-3"}'
  _queue_push 201 '{"id":"20004","key":"DEMO-4"}'
  _queue_push 201 '{"id":"20005","key":"DEMO-5"}'
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" convert --feature demo || return 1

  # chamada 4 = task 1.1 (FASE 1, sem aresta de entrada na Matriz)
  _t1_desc=$("$IO_SCRIPT" json-get '.fields.description.content[0].content[0].text' < "$TMPDIR_TEST/queue-curl-body-4.json")
  [ "$_t1_desc" = "Criticidade: A" ] \
    || { _fail "sy37_fase1_sem_dependencia" "esperado 'Criticidade: A', obtido '$_t1_desc'"; return 1; }

  # chamada 6 = task 2.1 (FASE 2, aresta F1-->F2 na Matriz)
  _t2_desc=$("$IO_SCRIPT" json-get '.fields.description.content[0].content[0].text' < "$TMPDIR_TEST/queue-curl-body-6.json")
  [ "$_t2_desc" = "Criticidade: A | Depende de: FASE 1 - Fundacao" ] \
    || { _fail "sy37_fase2_com_dependencia" "esperado 'Criticidade: A | Depende de: FASE 1 - Fundacao', obtido '$_t2_desc'"; return 1; }
  return 0
}

scenario_convert_description_omitida_sem_criticidade_e_sem_dependencia() {
  _write_full_config
  _write_tasks_1task_1sub_sem_crit
  _write_credential
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"accountId":"acc-1"}'
  _queue_push 200 '{"id":"10000","key":"DEMO"}'
  _queue_push 201 '{"id":"20001","key":"DEMO-1"}'
  _queue_push 201 '{"id":"20002","key":"DEMO-2"}'
  _queue_push 201 '{"id":"20003","key":"DEMO-3"}'
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" convert --feature demo || return 1

  _task_fields=$("$IO_SCRIPT" json-get '.fields | keys_unsorted | sort | .[]' < "$TMPDIR_TEST/queue-curl-body-4.json" | tr '\n' ',')
  [ "$_task_fields" = "issuetype,parent,project,summary," ] \
    || { _fail "sy38_task_sem_description" "esperado issuetype,parent,project,summary (sem description) — obtido $_task_fields"; return 1; }
  return 0
}

# =========================== convert: atualizar issue mapeada (FR-003, FASE 10 t. 10.2) ====
#
#   SY-39 convert: item ja mapeado (`active`) com titulo local mudado e SEM
#         divergencia no Jira (summary atual == SyncMarker) -> R2 PUT com o
#         NOVO summary/description + regrava o SyncMarker (novo hash,
#         written_status PRESERVADO); ZERO POST /issue (nada criado);
#         jira-map.tsv NUNCA reescrito por uma atualizacao de conteudo
#   SY-40 convert: item ja mapeado com SyncMarker AUSENTE (404) -> NUNCA
#         escreve (FR-011); gera ConflictRecord `marker_missing`; ZERO
#         PUT/POST de escrita
#   SY-41 convert: item ja mapeado cujo summary ATUAL no Jira ja diverge do
#         SyncMarker (edicao manual desde a ultima sync) -> NUNCA sobrescreve
#         (FR-011), mesmo com o titulo local tambem tendo mudado; gera
#         ConflictRecord `manual_edit`; ZERO PUT/POST de escrita

# _write_tasks_titulo_mudado: FASE 1 / task 1.1 com titulo "Novo titulo"
# (SEM sub-task, para manter a fila de rede pequena) — usada pelas 3
# cenarios SY-39/40/41, que pre-existem o mapeamento (epic+task `active`)
# ANTES de rodar convert, simulando uma re-conversao apos editar o titulo
# local.
_write_tasks_titulo_mudado() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cat > "$TMPDIR_TEST/docs/specs/demo/tasks.md" <<'EOF'
## FASE 1 - Sincronizacao `[A]`

### 1.1 Novo titulo `[A]`
EOF
}

scenario_convert_atualiza_summary_via_r2_sem_conflito() {
  _write_full_config
  _write_tasks_titulo_mudado
  _write_credential
  _write_map_row "demo" epic 20001 DEMO-1 active
  _write_map_row "1.1" task 20002 DEMO-2 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  _sha_antigo=$(printf '%s' "[FASE 1] 1.1 Titulo antigo" | "$IO_SCRIPT" sha256-stdin)
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"accountId":"acc-1"}'
  _queue_push 200 '{"id":"10000","key":"DEMO"}'
  _queue_push 200 '{"fields":{"summary":"demo"}}'
  _queue_push 200 '{"fields":{"summary":"[FASE 1] 1.1 Titulo antigo"}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_antigo\",\"written_status\":\"To Do\"}}"
  _queue_push 204 ''
  _queue_push 200 ''
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" convert --feature demo || return 1

  [ "$(_queue_post_issue_calls_count)" = "0" ] \
    || { _fail "sy39_zero_creates" "esperado 0 POST /issue, obtido $(_queue_post_issue_calls_count)"; return 1; }
  [ "$(_queue_calls_count)" = "7" ] \
    || { _fail "sy39_calls_count" "esperado 7 chamadas (myself+project+R3epic+R3task+R6get+R2put+R6put), obtido $(_queue_calls_count)"; return 1; }

  # call 6 = PUT R2 (novo summary + description)
  _r2_summary=$("$IO_SCRIPT" json-get '.fields.summary' < "$TMPDIR_TEST/queue-curl-body-6.json")
  [ "$_r2_summary" = "[FASE 1] 1.1 Novo titulo" ] \
    || { _fail "sy39_r2_summary" "esperado '[FASE 1] 1.1 Novo titulo', obtido '$_r2_summary'"; return 1; }
  _r2_desc=$("$IO_SCRIPT" json-get '.fields.description.content[0].content[0].text' < "$TMPDIR_TEST/queue-curl-body-6.json")
  [ "$_r2_desc" = "Criticidade: A" ] \
    || { _fail "sy39_r2_description" "esperado 'Criticidade: A', obtido '$_r2_desc'"; return 1; }

  # call 7 = PUT R6 (marker regravado: novo hash, written_status preservado)
  _sha_novo=$(printf '%s' "[FASE 1] 1.1 Novo titulo" | "$IO_SCRIPT" sha256-stdin)
  _marker_sha=$("$IO_SCRIPT" json-get '.written_summary_sha256' < "$TMPDIR_TEST/queue-curl-body-7.json")
  [ "$_marker_sha" = "$_sha_novo" ] \
    || { _fail "sy39_marker_sha" "esperado hash do novo summary, obtido '$_marker_sha'"; return 1; }
  _marker_status=$("$IO_SCRIPT" json-get '.written_status' < "$TMPDIR_TEST/queue-curl-body-7.json")
  [ "$_marker_status" = "To Do" ] \
    || { _fail "sy39_marker_status_preservado" "esperado written_status preservado 'To Do', obtido '$_marker_status'"; return 1; }

  _rows=$(awk -F '\t' 'NR>1' "$(_map_file)" | wc -l | tr -d ' ')
  [ "$_rows" = "2" ] || { _fail "sy39_map_inalterado" "jira-map.tsv nao deveria mudar de linha (obtido $_rows linhas)"; return 1; }
  return 0
}

scenario_convert_marker_ausente_vira_conflict_sem_escrever() {
  _write_full_config
  _write_tasks_titulo_mudado
  _write_credential
  _write_map_row "demo" epic 20001 DEMO-1 active
  _write_map_row "1.1" task 20002 DEMO-2 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"accountId":"acc-1"}'
  _queue_push 200 '{"id":"10000","key":"DEMO"}'
  _queue_push 200 '{"fields":{"summary":"demo"}}'
  _queue_push 200 '{"fields":{"summary":"[FASE 1] 1.1 Titulo antigo"}}'
  _queue_push 404 '{"errorMessages":["not found"]}'
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" convert --feature demo || return 1

  [ "$(_queue_calls_count)" = "5" ] \
    || { _fail "sy40_calls_count" "esperado 5 chamadas (nenhuma escrita apos o R6-get 404), obtido $(_queue_calls_count)"; return 1; }
  grep -q 'demo	1\.1	DEMO-2	marker_missing	pending$' "$(_conflicts_file)" \
    || { _fail "sy40_conflict_record" "ConflictRecord marker_missing ausente/incorreto: $(cat "$(_conflicts_file)" 2>/dev/null)"; return 1; }
  return 0
}

scenario_convert_manual_edit_vira_conflict_sem_sobrescrever() {
  _write_full_config
  _write_tasks_titulo_mudado
  _write_credential
  _write_map_row "demo" epic 20001 DEMO-1 active
  _write_map_row "1.1" task 20002 DEMO-2 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  # SyncMarker aponta para um hash que NAO bate com o summary atual da issue
  # (edicao manual no Jira desde a ultima sync do plugin).
  _sha_divergente=$(printf '%s' "Outro titulo qualquer" | "$IO_SCRIPT" sha256-stdin)
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"accountId":"acc-1"}'
  _queue_push 200 '{"id":"10000","key":"DEMO"}'
  _queue_push 200 '{"fields":{"summary":"demo"}}'
  _queue_push 200 '{"fields":{"summary":"[FASE 1] 1.1 Titulo editado manualmente"}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_divergente\",\"written_status\":\"To Do\"}}"
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" convert --feature demo || return 1

  [ "$(_queue_calls_count)" = "5" ] \
    || { _fail "sy41_calls_count" "esperado 5 chamadas (nenhuma escrita apos detectar manual_edit), obtido $(_queue_calls_count)"; return 1; }
  grep -q 'demo	1\.1	DEMO-2	manual_edit	pending$' "$(_conflicts_file)" \
    || { _fail "sy41_conflict_record" "ConflictRecord manual_edit ausente/incorreto: $(cat "$(_conflicts_file)" 2>/dev/null)"; return 1; }
  return 0
}

run_all_scenarios
