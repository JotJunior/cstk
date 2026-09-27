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
#         chamada (sem retry — 429 nao entra no loop de backoff de 5xx/rede);
#         retry_after=30 persistido no sidecar deferred-retry.tsv (12.2.1)
#   SY-51 drain (FASE 12 tarefa 12.2.1, achado 12.2): evento `deferred` cujo
#         retry_after AINDA nao decorreu (sidecar available_at_epoch no
#         futuro) -> NAO e selecionado (ZERO chamadas novas)
#   SY-52 drain (12.2.1): evento `deferred` cujo retry_after JA decorreu
#         (available_at_epoch no passado) -> RETENTADO e transiciona
#         normalmente; sidecar limpo apos a transicao
#   SY-53 drain (12.2.1): evento `deferred` SEM linha no sidecar (rede/
#         timeout generico, sem Retry-After) -> elegivel IMEDIATAMENTE
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
#   SY-55 requeue-auth-failed: outbox ausente ou sem eventos auth_failed ->
#         exit 0, stdout "0 evento(s)... reenfileirado(s)", nada alterado
#         (FASE 12 tarefa 12.6.1, data-model.md OutboxEvent
#         auth_failed->queued)
#   SY-56 requeue-auth-failed sem --feature: reenfileira eventos
#         auth_failed de TODAS as features (credencial e global ao
#         projeto), preserva demais colunas (attempts NUNCA resetado)
#   SY-57 requeue-auth-failed --feature F: reenfileira SOMENTE os eventos
#         auth_failed da feature F; auth_failed de outra feature permanece
#         intacto
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
#   SY-54 drain (FASE 12 tarefa 12.3.1, achado 12.3, contracts/
#         plugin-scripts.md exit 5 carve-out 1.1.0 (a)): PATH sem `jq` com
#         evento `queued` presente -> exit 5 (diagnostico cita jq/curl),
#         ZERO chamadas de rede, evento permanece EXATAMENTE `queued`
#         (nunca degrada para `deferred`)
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
# status/resolve (FASE 4.3, resolucao SEMPRE humana; `status` nunca toca
# rede; `resolve` toca rede SOMENTE em `keep_jira`/`overwrite`, desde FASE
# 12 tarefa 12.1.1 — rebaseline do SyncMarker, ver SY-25/27/47-50):
#   SY-22 status: outbox+conflicts+jira-map.tsv populados -> contagem
#         correta por status do outbox (queued/deferred/conflict/
#         auth_failed), linha auth_failed detalhada, conflitos pendentes
#         listados com dica de `resolve`, orfaos listados com dica de
#         `jira-map.sh relink`
#   SY-23 status --feature: filtra por feature (outra feature nao aparece)
#   SY-24 resolve: nenhum ConflictRecord pendente para (F, K) -> exit 1,
#         conflicts.tsv/outbox.tsv NUNCA tocados (ZERO chamadas de rede —
#         a checagem de pendencia acontece ANTES de qualquer rebaseline)
#   SY-25 resolve --choice keep_jira: fecha o registro (resolution=
#         keep_jira), outbox.tsv INALTERADO (nenhum evento novo), MAS
#         rebaselineia o SyncMarker (R3 GET + R6 PUT, 2 chamadas) para o
#         titulo+status ATUAIS da issue — efeito DURAVEL (12.1.1)
#   SY-26 resolve --choice ignored: fecha o registro (resolution=ignored),
#         outbox.tsv INALTERADO, ZERO chamadas de rede (unico choice que
#         permanece network-free)
#   SY-27 resolve --choice overwrite: fecha o registro (resolution=
#         overwrite), rebaselineia o SyncMarker (R3+R6 PUT, 2 chamadas)
#         E reenfileira (novo OutboxEvent status=queued) com o MESMO
#         desired_state do evento `conflict` original
#   SY-47 resolve --choice keep_jira -> drain (end-to-end, 12.1.1): apos o
#         rebaseline, um evento SUBSEQUENTE contra a MESMA issue (ainda com
#         a edicao manual) NAO reabre o conflito (fecha `done` direto)
#   SY-48 resolve --choice overwrite -> drain (end-to-end, 12.1.1): o
#         evento reenfileirado TRANSICIONA de fato no drain seguinte, sem
#         reabrir conflito, mesmo com a edicao manual ainda "presente"
#   SY-49 resolve --choice overwrite: conflito SEM evento outbox 'conflict'
#         (origem reconcile/convert, achado 12.1) -> fallback de
#         desired_state via `local_state` ATUAL de `jira-tasks.sh items`
#   SY-50 resolve --choice overwrite: nem evento outbox 'conflict' nem
#         local_state resolvivel -> exit 1, ConflictRecord PERMANECE
#         pending (Principio VI — nunca fabrica um desired_state)
#
# drain (FASE 10 tarefa 10.3, FR-004 — reconciliacao local_key=*):
#   SY-42 drain: evento `reconcile`/local_key=* expandido via
#         `jira-tasks.sh items` em Epic + Task + Sub-task -> Epic e Sub-task
#         (status atual diverge do alvo) transicionam via R5/R4/R6-PUT; Task
#         (ja no status alvo, SyncMarker batendo) fica idempotente (SOMENTE
#         R3+R6-GET, sem R5/R4) — evento `*` fecha `done`; 2a chamada de
#         `drain` compacta o evento (some do outbox.tsv)
#   SY-43 drain: reconciliacao com 2 itens, Epic com conflito (manual_edit,
#         ConflictRecord gravado) e Task transicionando normalmente -> o
#         conflito de UM item NUNCA impede o outro (FR-011 por item); evento
#         `*` fecha `done` (nao `conflict` — o veredito e por item)
#   SY-44 drain: 401 na 1a chamada de rede (R3 do 1o item, Epic) -> evento
#         `*` vira `auth_failed` (mesmo gate FR-016 de um evento direto) e a
#         reconciliacao para IMEDIATAMENTE — o 2o item (Task) nunca e
#         tocado (exatamente 1 chamada de rede)
#   SY-58 drain reconcile (FASE 12 tarefa 12.8.1, data-model.md
#         ProjectConfig stage_status.<stage> / US2 cenario 1): execucao
#         feature-00c ativa com current_stage=execute-task + config
#         stage_status.execute-task=<status> -> Epic transiciona para o
#         status DIRETO do override, NAO para o que a agregacao por tasks
#         produziria
#   SY-59 drain reconcile: sem execucao ativa legivel -> `--stage` nunca e
#         passado a `jira-tasks.sh items` -> stage_status.* configurado e
#         IGNORADO, Epic segue a agregacao normal por tasks (Principio VI —
#         nunca inventa uma etapa)

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

# _write_full_config_labels_off: mesma config de _write_full_config, com
# `labels_enabled=off` explicito (r02 FASE 17 task 17.2.3 — setup grava
# `off` quando `labels` nao esta na tela de criacao, R8).
_write_full_config_labels_off() {
  _write_full_config
  printf 'labels_enabled=off\n' >> "$TMPDIR_TEST/.claude/cstk-jira/config"
}

# _write_credential: credencial GLOBAL isolada (mesmo padrao de
# test_jira-io.sh) — SEMPRE combinar com XDG_CONFIG_HOME="$TMPDIR_TEST/xdg".
_write_credential() {
  mkdir -p "$TMPDIR_TEST/xdg/cstk-jira"
  printf 'site_host=cstk-test.atlassian.net\nemail=%s\napi_token=%s\n' "tester@example.com" "tok-FAKE-000" \
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

# _milestone_file — r02 FASE 16 task 16.3 (jira-milestones.tsv, data-model.md
# Entity Milestone). Arquivo irmao de jira-map.tsv, mesmo diretorio.
_milestone_file() {
  printf '%s\n' "$TMPDIR_TEST/docs/specs/demo/jira-milestones.tsv"
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

# _make_path_sans_jq -> instala em $TMPDIR_TEST/bin-nojq um symlink para
# cada coreutil REAL exercitado pelo caminho pre-deps-check de `jira-sync.sh
# drain` (compactacao/mark-orphans/selecao de elegiveis, tudo POSIX puro,
# NUNCA jq/curl) mais `curl` (presente — so `jq` falta, FASE 12 tarefa
# 12.3.1/achado 12.3, "PATH sem jq"), e OMITE `jq` de proposito. `PATH`
# passa a ser SO este diretorio (substituicao total, mesmo padrao de
# `_init_queue_stub`/JI-2 em test_jira-io.sh) — garante que `jq` nao seja
# encontrado por NENHUM outro dir do PATH real.
_make_path_sans_jq() {
  _bin="$TMPDIR_TEST/bin-nojq"
  mkdir -p "$_bin"
  for _tool in sh awk sed grep cut tr wc date mkdir mv cp rm cat dirname \
               basename mktemp sort head tail chmod ln touch printf curl \
               env expr true false stat; do
    _path=$(command -v "$_tool" 2>/dev/null) || continue
    ln -sf "$_path" "$_bin/$_tool"
  done
  printf '%s' "$_bin"
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

# _queue_post_version_calls_count / _queue_get_versions_calls_count — r02
# FASE 16 task 16.3.5/16.3.6 (milestone ensure, R12/R13). Mesmo idioma de
# _queue_post_issue_calls_count acima (grep -c pode sair 1 em zero-matches).
_queue_post_version_calls_count() {
  [ -f "$TMPDIR_TEST/queue-curl-calls.log" ] || { printf '0'; return; }
  _qpvcc_n=$(grep -c 'POST .*api/3/version$' "$TMPDIR_TEST/queue-curl-calls.log" 2>/dev/null) || _qpvcc_n=0
  printf '%s' "$_qpvcc_n"
}

_queue_get_versions_calls_count() {
  [ -f "$TMPDIR_TEST/queue-curl-calls.log" ] || { printf '0'; return; }
  _qgvcc_n=$(grep -c 'GET .*api/3/project/.*/versions$' "$TMPDIR_TEST/queue-curl-calls.log" 2>/dev/null) || _qgvcc_n=0
  printf '%s' "$_qgvcc_n"
}

# _write_round_demo_r01: mesmo fixture de scenario_milestone_resolve_round_
# ativo_consistente — `milestone resolve --feature demo` passa a devolver
# name=demo-r02/kind=round (usado pelos cenarios de `milestone ensure`, que
# precisam de um marco RESOLVIDO para exercitar o caminho de rede).
_write_round_demo_r01() {
  mkdir -p "$TMPDIR_TEST/.claude/feature-00c-state/demo/rounds/r01"
  cat > "$TMPDIR_TEST/.claude/feature-00c-state/demo/state.json" <<'EOF'
{"previous_round":{"round":"r01"}}
EOF
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
  # Epic: R1 create + R3 (status inicial, 11.1.1) + R6 PUT (SyncMarker inicial)
  _queue_push 201 '{"id":"20001","key":"DEMO-1"}'
  _queue_push 200 '{"fields":{"status":{"name":"To Do"}}}'
  _queue_push 201 ''
  # Task: idem
  _queue_push 201 '{"id":"20002","key":"DEMO-2"}'
  _queue_push 200 '{"fields":{"status":{"name":"To Do"}}}'
  _queue_push 201 ''
  # Sub-task: idem
  _queue_push 201 '{"id":"20003","key":"DEMO-3"}'
  _queue_push 200 '{"fields":{"status":{"name":"To Do"}}}'
  _queue_push 201 ''
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

  # corpo da 6a chamada (task create, call index 6: 3=R1 epic,4=R3 epic,5=R6
  # epic): parent = key do epic recem-criado
  _task_parent=$("$IO_SCRIPT" json-get '.fields.parent.key? // "none"' < "$TMPDIR_TEST/queue-curl-body-6.json")
  [ "$_task_parent" = "DEMO-1" ] || { _fail "convert_task_parent_is_epic" "esperado parent=DEMO-1, obtido $_task_parent"; return 1; }
  _task_summary=$("$IO_SCRIPT" json-get '.fields.summary' < "$TMPDIR_TEST/queue-curl-body-6.json")
  [ "$_task_summary" = "[FASE 1] 1.1 Titulo da tarefa" ] \
    || { _fail "convert_task_summary_format" "esperado '[FASE 1] 1.1 Titulo da tarefa', obtido '$_task_summary'"; return 1; }

  # corpo da 9a chamada (sub-task create, call index 9: 6=R1 task,7=R3
  # task,8=R6 task): parent = key da task recem-criada
  _sub_parent=$("$IO_SCRIPT" json-get '.fields.parent.key? // "none"' < "$TMPDIR_TEST/queue-curl-body-9.json")
  [ "$_sub_parent" = "DEMO-2" ] || { _fail "convert_subtask_parent_is_task" "esperado parent=DEMO-2, obtido $_sub_parent"; return 1; }

  # corpo da 5a chamada (R6 PUT do marker inicial do epic): hash do summary
  # enviado no R1 + status lido via R3 (11.1.1 — nunca suposto).
  _epic_marker_sha=$("$IO_SCRIPT" json-get '.written_summary_sha256' < "$TMPDIR_TEST/queue-curl-body-5.json")
  _epic_sha_esperado=$(printf '%s' "demo" | "$IO_SCRIPT" sha256-stdin)
  [ "$_epic_marker_sha" = "$_epic_sha_esperado" ] \
    || { _fail "convert_epic_marker_sha" "esperado hash de 'demo', obtido '$_epic_marker_sha'"; return 1; }
  _epic_marker_status=$("$IO_SCRIPT" json-get '.written_status' < "$TMPDIR_TEST/queue-curl-body-5.json")
  [ "$_epic_marker_status" = "To Do" ] \
    || { _fail "convert_epic_marker_status" "esperado written_status='To Do', obtido '$_epic_marker_status'"; return 1; }
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
  # 1a execucao: myself + project + 3x (create + R3 status + R6 PUT marker
  # inicial, 11.1.1)
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
  # execucoes 2-10: myself + project + 1 GET R3 por item ja mapeado (FR-003,
  # feature cstk-jira FASE 10 tarefa 10.2 — _js_maybe_update_mapped_issue
  # checa divergencia antes de decidir nao-criar); summary devolvido IDENTICO
  # ao composto na criacao -> no-op imediato, SEM leitura do SyncMarker (R6) e
  # SEM nenhuma criacao. Task 1.1 (criticidade `[A]`) tambem devolve a
  # description IDENTICA a composta ("Criticidade: A", FASE 12 tarefa
  # 12.5.1) — sem isso, `_js_maybe_update_mapped_issue` veria a description
  # atual como ausente (stub sem o campo) e detectaria drift falso a cada
  # re-conversao, quebrando a idempotencia deste cenario.
  _i=2
  while [ "$_i" -le 10 ]; do
    _queue_push 200 '{"accountId":"acc-1"}'
    _queue_push 200 '{"id":"10000","key":"DEMO"}'
    _queue_push 200 '{"fields":{"summary":"demo"}}'
    _queue_push 200 '{"fields":{"summary":"[FASE 1] 1.1 Titulo da tarefa","description":{"type":"doc","version":1,"content":[{"type":"paragraph","content":[{"type":"text","text":"Criticidade: A"}]}]}}}'
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
  _queue_push 200 '{"fields":{"status":{"name":"To Do"}}}'
  _queue_push 201 ''
  _queue_push 201 '{"id":"20002","key":"DEMO-2"}'
  _queue_push 200 '{"fields":{"status":{"name":"To Do"}}}'
  _queue_push 201 ''
  _queue_push 201 '{"id":"20003","key":"DEMO-3"}'
  _queue_push 200 '{"fields":{"status":{"name":"To Do"}}}'
  _queue_push 201 ''
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" convert --feature demo || return 1

  _append_task_1_2
  _queue_push 200 '{"accountId":"acc-1"}'
  _queue_push 200 '{"id":"10000","key":"DEMO"}'
  # FR-003 (feature cstk-jira FASE 10 tarefa 10.2): epic/task 1.1/sub 1.1.1 ja
  # mapeados -> _js_maybe_update_mapped_issue checa cada um (1 GET R3, summary
  # devolvido identico ao composto -> no-op) ANTES da task 1.2 (nova) ser criada.
  # Task 1.1 tambem devolve a description IDENTICA a composta (FASE 12
  # tarefa 12.5.1 — ver mesma nota em scenario_convert_idempotente_10x).
  _queue_push 200 '{"fields":{"summary":"demo"}}'
  _queue_push 200 '{"fields":{"summary":"[FASE 1] 1.1 Titulo da tarefa","description":{"type":"doc","version":1,"content":[{"type":"paragraph","content":[{"type":"text","text":"Criticidade: A"}]}]}}}'
  _queue_push 200 '{"fields":{"summary":"Sub um"}}'
  # task 1.2 (nova): create + R3 status + R6 PUT marker inicial (11.1.1)
  _queue_push 201 '{"id":"20004","key":"DEMO-4"}'
  _queue_push 200 '{"fields":{"status":{"name":"To Do"}}}'
  _queue_push 201 ''
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" convert --feature demo || return 1

  [ "$(_queue_post_issue_calls_count)" = "4" ] \
    || { _fail "convert_new_task_total_creates" "esperado 4 POST /issue no total, obtido $(_queue_post_issue_calls_count)"; return 1; }
  grep -q '^1\.2	task	20004	DEMO-4	active$' "$(_map_file)" \
    || { _fail "convert_new_task_mapped" "task nova (1.2) nao foi mapeada corretamente"; return 1; }
  # a nova task usa o Epic ja existente como parent (2a execucao comeca na
  # call 12: 12=myself, 13=project, 14/15/16=R3 dos 3 itens ja mapeados
  # (FR-003, no-op), 17=create da task 1.2)
  _new_task_parent=$("$IO_SCRIPT" json-get '.fields.parent.key? // "none"' < "$TMPDIR_TEST/queue-curl-body-17.json")
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

# _deferred_file: sidecar de retry_after (FASE 12 tarefa 12.2.1) —
# `event_id\tavailable_at_epoch`, NUNCA um campo novo de OutboxEvent.
_deferred_file() {
  printf '%s\n' "$TMPDIR_TEST/.claude/cstk-jira/runtime/deferred-retry.tsv"
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

# SY-65 (task 13.3.1, data-model.md LocalWorkItem outcome precedence):
# `enqueue --source manual --state pass|fail` NUNCA grava o sidecar de
# outcomes (`runtime/task-outcomes.tsv`) — SOMENTE `--source
# hook-record-task` carrega um outcome REAL de `record_task` (o UNICO
# caller que o hook `posttooluse-jira-sync.sh` usa para esse source). Antes
# desta tarefa, QUALQUER enqueue com --state pass/fail (inclusive o
# reenfileiramento de `resolve --choice overwrite`, que usa `--source
# manual`) sobrepunha em silencio o outcome REAL da ultima `record_task`.
scenario_enqueue_source_manual_nao_grava_sidecar_outcomes() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 0 "$SCRIPT" enqueue --feature demo --local-key 1.1 --state pass --source manual >/dev/null || return 1
  [ -f "$TMPDIR_TEST/.claude/cstk-jira/runtime/task-outcomes.tsv" ] \
    && { _fail "sy65_sidecar_created" "enqueue --source manual nao deveria criar task-outcomes.tsv: $(cat "$TMPDIR_TEST/.claude/cstk-jira/runtime/task-outcomes.tsv")"; return 1; }
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

# =========================== requeue-auth-failed (12.6.1) ===================

scenario_requeue_auth_failed_sem_outbox_exit0_zero() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 0 "$SCRIPT" requeue-auth-failed || return 1
  assert_stdout_contains "0 evento(s) auth_failed reenfileirado(s)" || return 1
  [ -f "$(_outbox_file)" ] && { _fail "requeue_no_outbox_created" "outbox.tsv foi criado por requeue-auth-failed sem eventos"; return 1; }
  return 0
}

scenario_requeue_auth_failed_sem_eventos_exit0_zero() {
  cd "$TMPDIR_TEST" || return 1
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	1.1	pass	manual	0	queued
EOF
  assert_exit 0 "$SCRIPT" requeue-auth-failed || return 1
  assert_stdout_contains "0 evento(s) auth_failed reenfileirado(s)" || return 1
  grep -q '	queued$' "$(_outbox_file)" \
    || { _fail "requeue_none_untouched" "evento queued foi alterado sem nenhum auth_failed presente"; return 1; }
  return 0
}

scenario_requeue_auth_failed_sem_feature_reenfileira_todas() {
  cd "$TMPDIR_TEST" || return 1
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	1.1	pass	manual	2	auth_failed
e2	2026-01-01T00:00:01Z	outra	9.9	fail	manual	1	auth_failed
e3	2026-01-01T00:00:02Z	demo	1.2	pending	manual	0	queued
EOF
  assert_exit 0 "$SCRIPT" requeue-auth-failed || return 1
  assert_stdout_contains "2 evento(s) auth_failed reenfileirado(s) para queued" || return 1
  awk -F '\t' '$1=="e1"' "$(_outbox_file)" | grep -q '^e1	2026-01-01T00:00:00Z	demo	1.1	pass	manual	2	queued$' \
    || { _fail "requeue_all_e1" "e1 nao foi reenfileirado preservando attempts/demais colunas: $(awk -F '\t' '$1==\"e1\"' "$(_outbox_file)")"; return 1; }
  awk -F '\t' '$1=="e2"' "$(_outbox_file)" | grep -q '^e2	2026-01-01T00:00:01Z	outra	9.9	fail	manual	1	queued$' \
    || { _fail "requeue_all_e2" "e2 (outra feature) nao foi reenfileirado: $(awk -F '\t' '$1==\"e2\"' "$(_outbox_file)")"; return 1; }
  return 0
}

scenario_requeue_auth_failed_com_feature_filtra() {
  cd "$TMPDIR_TEST" || return 1
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	1.1	pass	manual	0	auth_failed
e2	2026-01-01T00:00:01Z	outra	9.9	fail	manual	0	auth_failed
EOF
  assert_exit 0 "$SCRIPT" requeue-auth-failed --feature demo || return 1
  assert_stdout_contains "1 evento(s) auth_failed reenfileirado(s) para queued" || return 1
  awk -F '\t' '$1=="e1"' "$(_outbox_file)" | grep -q '	queued$' \
    || { _fail "requeue_filter_e1_queued" "e1 (feature filtrada) nao foi reenfileirado"; return 1; }
  awk -F '\t' '$1=="e2"' "$(_outbox_file)" | grep -q '	auth_failed$' \
    || { _fail "requeue_filter_e2_untouched" "e2 (outra feature) foi alterado apesar do filtro --feature"; return 1; }
  return 0
}

# ===================== milestone-unblock (r02 FASE 22 tarefa 22.1.2) ========

scenario_milestone_unblock_sem_feature_todas_zero() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 0 "$SCRIPT" milestone-unblock || return 1
  assert_stdout_contains "milestone-unblock: 0 marco(s) desbloqueado(s)" || return 1
}

scenario_milestone_unblock_sem_feature_varre_todas() {
  cd "$TMPDIR_TEST" || return 1
  mkdir -p "$TMPDIR_TEST/docs/specs/demo" "$TMPDIR_TEST/docs/specs/outra"
  "$REPO_ROOT/plugins/cstk-jira/scripts/jira-map.sh" milestone-put --feature demo --name demo-r02 \
    --kind round --project-key DEMO --state blocked >/dev/null || return 1
  "$REPO_ROOT/plugins/cstk-jira/scripts/jira-map.sh" milestone-put --feature outra --name outra-r02 \
    --kind round --project-key OUTRA --state blocked >/dev/null || return 1
  assert_exit 0 "$SCRIPT" milestone-unblock || return 1
  assert_stdout_contains "milestone-unblock: 2 marco(s) desbloqueado(s)" || return 1
  grep -q 'blocked' "$TMPDIR_TEST/docs/specs/demo/jira-milestones.tsv" \
    && { _fail "milestone_unblock_demo_left" "linha blocked de demo nao foi removida"; return 1; }
  grep -q 'blocked' "$TMPDIR_TEST/docs/specs/outra/jira-milestones.tsv" \
    && { _fail "milestone_unblock_outra_left" "linha blocked de outra nao foi removida"; return 1; }
  return 0
}

scenario_milestone_unblock_com_feature_filtra() {
  cd "$TMPDIR_TEST" || return 1
  mkdir -p "$TMPDIR_TEST/docs/specs/demo" "$TMPDIR_TEST/docs/specs/outra"
  "$REPO_ROOT/plugins/cstk-jira/scripts/jira-map.sh" milestone-put --feature demo --name demo-r02 \
    --kind round --project-key DEMO --state blocked >/dev/null || return 1
  "$REPO_ROOT/plugins/cstk-jira/scripts/jira-map.sh" milestone-put --feature outra --name outra-r02 \
    --kind round --project-key OUTRA --state blocked >/dev/null || return 1
  assert_exit 0 "$SCRIPT" milestone-unblock --feature demo || return 1
  assert_stdout_contains "milestone-unblock: 1 marco(s) desbloqueado(s)" || return 1
  grep -q 'blocked' "$TMPDIR_TEST/docs/specs/demo/jira-milestones.tsv" \
    && { _fail "milestone_unblock_filter_demo_left" "linha blocked de demo (alvo do filtro) nao foi removida"; return 1; }
  grep -q 'blocked' "$TMPDIR_TEST/docs/specs/outra/jira-milestones.tsv" \
    || { _fail "milestone_unblock_filter_outra_touched" "linha blocked de outra (fora do filtro) foi removida indevidamente"; return 1; }
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

# SY-62 (task 13.2.1, FR-011 / data-model SyncMarker written_description_sha256
# / task 12.5.1): drain (transicao de status via `_js_process_one_event`)
# PRESERVA `written_description_sha256` do marker lido no R6 PUT que
# regrava o marker — a proxima `convert` da MESMA feature, com a descricao
# REAL da issue tendo sido editada manualmente no Jira nesse meio-tempo,
# detecta `manual_edit` (NUNCA sobrescreve a edicao em silencio via R2).
# Antes de 13.2.1, o R6 PUT da transicao (que substitui o valor INTEIRO da
# entity property) omitia a chave — a convert seguinte tratava a ausencia
# de baseline como "nada a proteger" e sobrescrevia a descricao editada.
scenario_drain_transicao_preserva_baseline_descricao_convert_seguinte_detecta_manual_edit() {
  _write_full_config
  _write_credential
  _write_map_row "1.1" task 20002 DEMO-2 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"

  _summary="[FASE 1] 1.1 Titulo da tarefa"
  _sha_summary=$(printf '%s' "$_summary" | "$IO_SCRIPT" sha256-stdin)
  _sha_desc=$(printf '%s' "Criticidade: A" | "$IO_SCRIPT" sha256-stdin)

  # Fase 1: transicao pending->pass via drain (evento local_key=1.1,
  # _js_process_one_event). O marker LIDO (R6 GET) ja carrega
  # written_description_sha256 (baseline de uma convert anterior, 12.5.1).
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<EOF
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	1.1	pass	manual	0	queued
EOF
  _bin="$(_init_queue_stub)"
  _queue_push 200 "{\"fields\":{\"summary\":\"$_summary\",\"status\":{\"name\":\"To Do\"}}}"
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_summary\",\"written_status\":\"To Do\",\"written_description_sha256\":\"$_sha_desc\"}}"
  _queue_push 200 '{"transitions":[{"id":"31","to":{"name":"Done"}}]}'
  _queue_push 204 ''
  _queue_push 200 ''
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" drain --feature demo || return 1

  [ "$(_queue_calls_count)" = "5" ] \
    || { _fail "sy62_drain_calls_count" "esperado 5 chamadas, obtido $(_queue_calls_count)"; return 1; }
  _put_desc_sha=$("$IO_SCRIPT" json-get '.written_description_sha256? // "AUSENTE"' < "$TMPDIR_TEST/queue-curl-body-5.json")
  [ "$_put_desc_sha" = "$_sha_desc" ] \
    || { _fail "sy62_marker_preserva_descricao" "R6 PUT da transicao deveria preservar written_description_sha256=$_sha_desc, obtido '$_put_desc_sha'"; return 1; }

  # Fase 2: convert da MESMA feature — titulo/status da issue batem com o
  # marker ja atualizado pela fase 1 (Done), mas a DESCRICAO atual foi
  # editada manualmente no Jira (diverge de "Criticidade: A", a composta
  # local). MUST detectar manual_edit e NUNCA chamar R2 (issue-update).
  _write_tasks_1task_1sub
  _write_map_row "demo" epic 20001 DEMO-1 active
  _write_map_row "1.1.1" subtask 20003 DEMO-3 active
  _queue_push 200 '{"accountId":"acc-1"}'
  _queue_push 200 '{"id":"10000","key":"DEMO"}'
  _queue_push 200 '{"fields":{"summary":"demo"}}'
  _queue_push 200 "{\"fields\":{\"summary\":\"$_summary\",\"status\":{\"name\":\"Done\"},\"description\":{\"type\":\"doc\",\"version\":1,\"content\":[{\"type\":\"paragraph\",\"content\":[{\"type\":\"text\",\"text\":\"Descricao editada manualmente no Jira\"}]}]}}}"
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_summary\",\"written_status\":\"Done\",\"written_description_sha256\":\"$_sha_desc\"}}"
  _queue_push 200 '{"fields":{"summary":"Sub um"}}'
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" convert --feature demo || return 1

  [ "$(_queue_post_issue_calls_count)" = "0" ] \
    || { _fail "sy62_convert_sem_create" "convert nao deveria criar nenhuma issue (todas ja mapeadas), obtido $(_queue_post_issue_calls_count) POST /issue"; return 1; }
  grep -q 'demo	1\.1	DEMO-2	manual_edit	pending$' "$(_conflicts_file)" \
    || { _fail "sy62_conflict_record" "ConflictRecord manual_edit ausente/incorreto: $(cat "$(_conflicts_file)" 2>/dev/null)"; return 1; }
  return 0
}

# r02 FASE 24 tarefa 24.2.1/24.2.2 (achado 24.2): mesmo mecanismo de
# `sy62` acima (o R6 PUT de `_js_process_one_event` substitui o valor
# INTEIRO da entity property), agora para `written_phase_label`/
# `written_fix_version_id` — sem carregar as duas adiante (lidas do MESMO
# R6 GET que ja fornece written_description_sha256), a PRIMEIRA transicao
# de status por evento (fluxo normal da US3) apagava os dois campos do
# marker, desligando a reconciliacao de troca de FASE
# (`_js_reconcile_phase_label`, so roda com o campo nao-vazio) e de marco
# do Epic (o proximo `_js_reconcile_epic_milestone` so faria `add`, sem
# `remove`, acumulando 2 Fix Versions). Mutation (remover o carry-forward
# de qualquer um dos dois campos) MUST falhar este teste.
scenario_drain_transicao_preserva_phase_label_e_fix_version_no_marker() {
  _write_full_config
  _write_credential
  _write_map_row "1.1" task 20002 DEMO-2 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"

  _summary="[FASE 1] 1.1 Titulo da tarefa"
  _sha_summary=$(printf '%s' "$_summary" | "$IO_SCRIPT" sha256-stdin)

  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<EOF
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	1.1	pass	manual	0	queued
EOF
  _bin="$(_init_queue_stub)"
  # R6 GET do marker atual JA carrega written_phase_label (Task, reaplicado
  # por reconcile em ondas anteriores) e written_fix_version_id (residual
  # improvavel numa Task real, mas prova que o carry-forward do R6 PUT nao
  # discrimina por kind — ambos os campos sao repassados tal-e-qual).
  _queue_push 200 "{\"fields\":{\"summary\":\"$_summary\",\"status\":{\"name\":\"To Do\"}}}"
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_summary\",\"written_status\":\"To Do\",\"written_phase_label\":\"phase-1\",\"written_fix_version_id\":\"30001\"}}"
  _queue_push 200 '{"transitions":[{"id":"31","to":{"name":"Done"}}]}'
  _queue_push 204 ''
  _queue_push 200 ''
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" drain --feature demo || return 1

  [ "$(_queue_calls_count)" = "5" ] \
    || { _fail "sy_carryfwd_calls" "esperado 5 chamadas, obtido $(_queue_calls_count)"; return 1; }
  _put_phase=$("$IO_SCRIPT" json-get '.written_phase_label? // "AUSENTE"' < "$TMPDIR_TEST/queue-curl-body-5.json")
  [ "$_put_phase" = "phase-1" ] \
    || { _fail "sy_carryfwd_phase_label" "R6 PUT da transicao deveria preservar written_phase_label=phase-1, obtido '$_put_phase'"; return 1; }
  _put_fixver=$("$IO_SCRIPT" json-get '.written_fix_version_id? // "AUSENTE"' < "$TMPDIR_TEST/queue-curl-body-5.json")
  [ "$_put_fixver" = "30001" ] \
    || { _fail "sy_carryfwd_fix_version" "R6 PUT da transicao deveria preservar written_fix_version_id=30001, obtido '$_put_fixver'"; return 1; }
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

# SY-54 drain (FASE 12 tarefa 12.3.1, achado 12.3): PATH SEM `jq` (curl
# presente) com 1 evento `queued` -> exit 5 com diagnostico citando jq/curl
# (contracts/plugin-scripts.md exit 5 carve-out 1.1.0 (a) — "o que degrada
# e o sync AUTONOMO"), ZERO chamadas de rede, evento permanece EXATAMENTE
# `queued` (NUNCA degrada para `deferred`, achado 12.3: antes desta tarefa
# o exit 5 de `jira-io.sh request` caia no ramo generico e o evento virava
# `deferred` com drain saindo exit 0). deps-check roda ANTES de qualquer
# config/credencial — fixture nao precisa de ProjectConfig/jira-map.tsv.
scenario_drain_sem_jq_exit5_sem_tocar_eventos() {
  cd "$TMPDIR_TEST" || return 1
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	1.1	pass	manual	0	queued
EOF
  _before=$(cat "$(_outbox_file)")
  _bin="$(_make_path_sans_jq)"
  assert_exit 5 env PATH="$_bin" "$SCRIPT" drain --feature demo || return 1
  assert_stderr_contains "jq" || return 1
  assert_stderr_contains "curl" || return 1
  _after=$(cat "$(_outbox_file)")
  [ "$_before" = "$_after" ] \
    || { _fail "sy54_outbox_untouched" "outbox.tsv foi alterado apesar do exit 5: antes=[$_before] depois=[$_after]"; return 1; }
  [ -f "$(_deferred_file)" ] \
    && { _fail "sy54_no_deferred_sidecar" "sidecar deferred-retry.tsv nao deveria existir (evento nunca virou deferred)"; return 1; }
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

# SY-25 resolve --choice keep_jira (FASE 12 tarefa 12.1.1 — efeito
# DURAVEL): fecha o registro e rebaselineia o SyncMarker (R3 GET + R6 GET +
# R6 PUT) para o titulo+status ATUAIS da issue — antes da 12.1.1 nenhuma
# chamada de rede era feita e o marker antigo permanecia, reabrindo o MESMO
# conflito no proximo drain (achado 12.1). task 13.3.1 (data-model.md
# OutboxEvent "conflict --> [*]"): o evento outbox `conflict` do MESMO par
# (F, K) MUST ser encerrado (status vira `done`) — antes desta tarefa ele
# ficava `conflict` para sempre, e `_js_last_conflict_desired_state`
# (usado por `overwrite`) continuava enxergando-o mesmo depois do conflito
# ja fechado. task 21.1.1/21.1.2 (plan.md SEC-10, achado 21.1): o R6 GET
# extra le o marker ATUAL (que ja carrega `written_fix_version_id`/
# `written_phase_label` de uma sincronizacao r02 anterior) ANTES do R6 PUT
# — o rebaseline de um conflito `manual_edit` (nada a ver com marco/label)
# MUST preservar as 2 chaves tal-e-qual no corpo do PUT, nunca apaga-las
# (mutation: remover o carry-forward faz este teste falhar).
scenario_resolve_keep_jira_fecha_registro_e_encerra_evento_conflict_do_outbox() {
  _write_full_config
  _write_credential
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	1.1	pending	manual	0	conflict
EOF
  cat > "$(_conflicts_file)" <<'EOF'
detected_at	feature	local_key	jira_key	reason	resolution
2026-01-01T00:00:00Z	demo	1.1	DEMO-2	manual_edit	pending
EOF
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"fields":{"summary":"Titulo editado a mao no Jira","status":{"name":"In Progress"}}}'
  _queue_push 200 '{"key":"cstk-jira.sync","value":{"written_summary_sha256":"old","written_status":"To Do","written_fix_version_id":"10099","written_phase_label":"phase-3"}}'
  _queue_push 200 ''
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" resolve --feature demo --local-key 1.1 --choice keep_jira || return 1
  assert_stdout_contains "escolha=keep_jira" || return 1
  grep -q 'demo	1\.1	DEMO-2	manual_edit	keep_jira$' "$(_conflicts_file)" \
    || { _fail "resolve_keep_jira_resolution" "resolution nao virou keep_jira: $(cat "$(_conflicts_file)")"; return 1; }
  awk -F '\t' '$1=="e1"' "$(_outbox_file)" | grep -q 'done$' \
    || { _fail "sy63_keep_jira_outbox_conflict_closed" "evento e1 (conflict) deveria virar done apos resolve: $(awk -F '\t' '$1==\"e1\"' "$(_outbox_file)")"; return 1; }
  [ "$(_queue_calls_count)" = "3" ] \
    || { _fail "resolve_keep_jira_calls" "esperado 3 chamadas (R3 + R6 GET + R6 PUT), obtido $(_queue_calls_count)"; return 1; }
  _marker_status=$("$IO_SCRIPT" json-get '.written_status' < "$TMPDIR_TEST/queue-curl-body-3.json")
  [ "$_marker_status" = "In Progress" ] \
    || { _fail "resolve_keep_jira_marker_status" "SyncMarker nao rebaselinado para o status atual: $_marker_status"; return 1; }
  _expect_sha=$(printf '%s' "Titulo editado a mao no Jira" | "$IO_SCRIPT" sha256-stdin)
  _marker_sha=$("$IO_SCRIPT" json-get '.written_summary_sha256' < "$TMPDIR_TEST/queue-curl-body-3.json")
  [ "$_marker_sha" = "$_expect_sha" ] \
    || { _fail "resolve_keep_jira_marker_sha" "SyncMarker nao rebaselinado para o titulo atual"; return 1; }
  # task 21.1.1: written_fix_version_id/written_phase_label do marker ANTIGO
  # (lido acima via R6 GET) MUST sobreviver ao PUT — reason=manual_edit nao
  # e milestone_drift/label_drift, entao preserva tal-e-qual (nunca apaga).
  _marker_fixver=$("$IO_SCRIPT" json-get '.written_fix_version_id? // ""' < "$TMPDIR_TEST/queue-curl-body-3.json")
  [ "$_marker_fixver" = "10099" ] \
    || { _fail "resolve_keep_jira_marker_fixver_preserved" "written_fix_version_id nao foi preservado no rebaseline (achado 21.1): '$_marker_fixver'"; return 1; }
  _marker_phase=$("$IO_SCRIPT" json-get '.written_phase_label? // ""' < "$TMPDIR_TEST/queue-curl-body-3.json")
  [ "$_marker_phase" = "phase-3" ] \
    || { _fail "resolve_keep_jira_marker_phase_preserved" "written_phase_label nao foi preservado no rebaseline (achado 21.1): '$_marker_phase'"; return 1; }
  return 0
}

# SY-26 resolve --choice ignored: fecha o registro; nenhuma escrita de
# rede. task 13.3.1: o evento outbox `conflict` do MESMO par MUST ser
# encerrado (status vira `done`) mesmo em `ignored` — TODA resolucao
# encerra o(s) evento(s) conflict do par, nao so keep_jira/overwrite.
scenario_resolve_ignored_fecha_registro_e_encerra_evento_conflict_do_outbox() {
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
  assert_exit 0 "$SCRIPT" resolve --feature demo --local-key 9.9 --choice ignored || return 1
  assert_stdout_contains "escolha=ignored" || return 1
  grep -q 'demo	9\.9	DEMO-9	orphan	ignored$' "$(_conflicts_file)" \
    || { _fail "resolve_ignored_resolution" "resolution nao virou ignored: $(cat "$(_conflicts_file)")"; return 1; }
  awk -F '\t' '$1=="e1"' "$(_outbox_file)" | grep -q 'done$' \
    || { _fail "sy63_ignored_outbox_conflict_closed" "evento e1 (conflict) deveria virar done apos resolve --choice ignored: $(awk -F '\t' '$1==\"e1\"' "$(_outbox_file)")"; return 1; }
  return 0
}

# SY-27 resolve --choice overwrite (FASE 12 tarefa 12.1.1 — efeito
# DURAVEL): fecha o registro E reenfileira um NOVO OutboxEvent (status=
# queued) com o MESMO desired_state do evento `conflict` original — mas
# AGORA rebaselineia o SyncMarker (R3 + R6 GET + R6 PUT) ANTES de
# reenfileirar, senao o proximo drain repetiria a MESMA comparacao contra o
# marker antigo e reabriria o conflito em vez de transicionar (achado
# 12.1). task 21.1.1: o R6 GET extra le o marker atual para preservar
# `written_fix_version_id`/`written_phase_label` (aqui ausentes/vazios —
# marker r01) no PUT.
scenario_resolve_overwrite_fecha_registro_e_reenfileira() {
  _write_full_config
  _write_credential
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	1.1	fail	manual	0	conflict
EOF
  cat > "$(_conflicts_file)" <<'EOF'
detected_at	feature	local_key	jira_key	reason	resolution
2026-01-01T00:00:00Z	demo	1.1	DEMO-2	manual_edit	pending
EOF
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"fields":{"summary":"Titulo editado a mao","status":{"name":"To Do"}}}'
  _queue_push 404 '{"errorMessages":["not found"]}'
  _queue_push 200 ''
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" resolve --feature demo --local-key 1.1 --choice overwrite || return 1
  assert_stdout_contains "escolha=overwrite" || return 1
  grep -q 'demo	1\.1	DEMO-2	manual_edit	overwrite$' "$(_conflicts_file)" \
    || { _fail "resolve_overwrite_resolution" "resolution nao virou overwrite: $(cat "$(_conflicts_file)")"; return 1; }
  [ "$(_queue_calls_count)" = "3" ] \
    || { _fail "resolve_overwrite_calls" "esperado 3 chamadas (R3 + R6 GET + R6 PUT de rebaseline), obtido $(_queue_calls_count)"; return 1; }
  _novo=$(awk -F '\t' '$1 != "e1" && NR > 1 { print }' "$(_outbox_file)")
  [ -n "$_novo" ] \
    || { _fail "resolve_overwrite_new_event" "nenhum evento novo foi enfileirado: $(cat "$(_outbox_file)")"; return 1; }
  printf '%s\n' "$_novo" | grep -q '	demo	1\.1	fail	manual	0	queued$' \
    || { _fail "resolve_overwrite_new_event_fields" "evento novo com campos inesperados: $_novo"; return 1; }
  return 0
}

# SY-64 (task 13.3.1): DOIS conflitos SUCESSIVOS no MESMO par (feature,
# local_key). O 1o e resolvido (`ignored`) primeiro — fecha o evento
# outbox `conflict` dele (e1, desired_state=fail) para `done`. Um 2o
# conflito NOVO surge depois (e2, desired_state=pass, NOVO ConflictRecord
# pending). `resolve --choice overwrite` do 2o conflito MUST reenfileirar
# o desired_state do 2o conflito (`pass`), NUNCA o do 1o ja resolvido
# (`fail`) — antes de 13.3.1, o evento e1 ficava `conflict` para sempre no
# outbox e podia ser confundido com o conflito atual.
scenario_resolve_overwrite_2_conflitos_sucessivos_usa_desired_state_do_conflito_atual() {
  _write_full_config
  _write_credential
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  mkdir -p "$(dirname "$(_outbox_file)")"

  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	1.1	fail	manual	0	conflict
EOF
  cat > "$(_conflicts_file)" <<'EOF'
detected_at	feature	local_key	jira_key	reason	resolution
2026-01-01T00:00:00Z	demo	1.1	DEMO-2	manual_edit	pending
EOF
  assert_exit 0 "$SCRIPT" resolve --feature demo --local-key 1.1 --choice ignored || return 1
  awk -F '\t' '$1=="e1"' "$(_outbox_file)" | grep -q 'done$' \
    || { _fail "sy64_e1_closed" "evento e1 (1o conflito) deveria estar done apos o 1o resolve: $(awk -F '\t' '$1==\"e1\"' "$(_outbox_file)")"; return 1; }

  cat >> "$(_outbox_file)" <<'EOF'
e2	2026-01-01T00:02:00Z	demo	1.1	pass	manual	0	conflict
EOF
  cat >> "$(_conflicts_file)" <<'EOF'
2026-01-01T00:02:00Z	demo	1.1	DEMO-2	manual_edit	pending
EOF
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"fields":{"summary":"Titulo editado a mao 2","status":{"name":"To Do"}}}'
  _queue_push 404 '{"errorMessages":["not found"]}'
  _queue_push 200 ''
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" resolve --feature demo --local-key 1.1 --choice overwrite || return 1

  _novo=$(awk -F '\t' '$1 != "e1" && $1 != "e2" && NR > 1 { print }' "$(_outbox_file)")
  [ -n "$_novo" ] \
    || { _fail "sy64_new_event_missing" "nenhum evento novo foi enfileirado pelo overwrite: $(cat "$(_outbox_file)")"; return 1; }
  printf '%s\n' "$_novo" | grep -q '	demo	1\.1	pass	manual	0	queued$' \
    || { _fail "sy64_new_event_wrong_desired_state" "overwrite deveria reenfileirar desired_state=pass (2o conflito, ainda pendente), obtido: $_novo"; return 1; }
  awk -F '\t' '$1=="e2"' "$(_outbox_file)" | grep -q 'done$' \
    || { _fail "sy64_e2_closed" "evento e2 (2o conflito) deveria virar done apos o 2o resolve: $(awk -F '\t' '$1==\"e2\"' "$(_outbox_file)")"; return 1; }
  return 0
}

# SY-47 resolve --choice keep_jira -> drain (end-to-end, 12.1.1): apos o
# rebaseline, um evento SUBSEQUENTE contra a MESMA issue (titulo/status
# ainda "editados a mao") NAO reabre o conflito — a proxima comparacao bate
# exatamente o que keep_jira acabou de gravar no SyncMarker.
scenario_resolve_keep_jira_drain_seguinte_nao_reabre_conflito() {
  _write_full_config
  _write_credential
  _write_map_row "1.1" task 20002 DEMO-2 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	1.1	pending	manual	0	conflict
EOF
  cat > "$(_conflicts_file)" <<'EOF'
detected_at	feature	local_key	jira_key	reason	resolution
2026-01-01T00:00:00Z	demo	1.1	DEMO-2	manual_edit	pending
EOF
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"fields":{"summary":"Titulo editado a mao no Jira","status":{"name":"In Progress"}}}'
  _queue_push 404 '{"errorMessages":["not found"]}'
  _queue_push 200 ''
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" resolve --feature demo --local-key 1.1 --choice keep_jira || return 1

  # Novo evento (ex.: outra mudanca local que gera enqueue de novo) contra
  # a MESMA issue, ainda sem tocar o Jira de fato — R3/R6-GET devem bater
  # exatamente o marker que keep_jira acabou de gravar.
  cat >> "$(_outbox_file)" <<'EOF'
e2	2026-01-01T00:01:00Z	demo	1.1	in_progress	manual	0	queued
EOF
  _sha47=$(printf '%s' "Titulo editado a mao no Jira" | "$IO_SCRIPT" sha256-stdin)
  _queue_push 200 '{"fields":{"summary":"Titulo editado a mao no Jira","status":{"name":"In Progress"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha47\",\"written_status\":\"In Progress\"}}"
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" drain --feature demo || return 1

  awk -F '\t' '$1=="e2"' "$(_outbox_file)" | grep -q 'done$' \
    || { _fail "sy47_e2_done" "e2 deveria fechar done (ja no status alvo, sem novo conflito): $(awk -F '\t' '$1==\"e2\"' "$(_outbox_file)")"; return 1; }
  _pending_count=$(awk -F '\t' 'NR>1 && $2=="demo" && $3=="1.1" && $6=="pending"' "$(_conflicts_file)" | wc -l | tr -d ' ')
  [ "$_pending_count" = "0" ] \
    || { _fail "sy47_no_new_conflict" "um NOVO ConflictRecord pending foi criado apos keep_jira: $(cat "$(_conflicts_file)")"; return 1; }
  return 0
}

# SY-48 resolve --choice overwrite -> drain (end-to-end, 12.1.1): o evento
# REENFILEIRADO transiciona de fato no drain seguinte (sem novo conflito),
# mesmo com a edicao manual ainda presente no titulo/status "atuais".
scenario_resolve_overwrite_drain_seguinte_transiciona() {
  _write_full_config
  _write_credential
  _write_map_row "1.1" task 20002 DEMO-2 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	1.1	pass	manual	0	conflict
EOF
  cat > "$(_conflicts_file)" <<'EOF'
detected_at	feature	local_key	jira_key	reason	resolution
2026-01-01T00:00:00Z	demo	1.1	DEMO-2	manual_edit	pending
EOF
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"fields":{"summary":"Titulo editado a mao","status":{"name":"To Do"}}}'
  _queue_push 404 '{"errorMessages":["not found"]}'
  _queue_push 200 ''
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" resolve --feature demo --local-key 1.1 --choice overwrite || return 1

  # drain do evento reenfileirado: R3 (mesmo titulo/status "atuais", agora
  # identicos ao marker rebaselinado) + R6-GET (marker) + R5 + R4 + R6-PUT.
  _queue_push 200 '{"fields":{"summary":"Titulo editado a mao","status":{"name":"To Do"}}}'
  _sha=$(printf '%s' "Titulo editado a mao" | "$IO_SCRIPT" sha256-stdin)
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha\",\"written_status\":\"To Do\"}}"
  _queue_push 200 '{"transitions":[{"id":"41","to":{"name":"Done"}}]}'
  _queue_push 204 ''
  _queue_push 200 ''
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" drain --feature demo || return 1

  _novo_eid=$(awk -F '\t' '$1 != "e1" && NR > 1 { print $1; exit }' "$(_outbox_file)")
  awk -F '\t' -v id="$_novo_eid" '$1==id' "$(_outbox_file)" | grep -q 'done$' \
    || { _fail "sy48_new_event_done" "evento reenfileirado nao transicionou (done): $(cat "$(_outbox_file)")"; return 1; }
  _pending_count=$(awk -F '\t' 'NR>1 && $2=="demo" && $3=="1.1" && $6=="pending"' "$(_conflicts_file)" | wc -l | tr -d ' ')
  [ "$_pending_count" = "0" ] \
    || { _fail "sy48_no_new_conflict" "overwrite deveria transicionar sem reabrir conflito: $(cat "$(_conflicts_file)")"; return 1; }
  return 0
}

# SY-49 resolve --choice overwrite: conflito SEM evento outbox 'conflict'
# correspondente (originado de reconcile/`_js_maybe_update_mapped_issue`,
# achado 12.1 "overwrite nunca funciona para conflitos vindos de reconcile/
# convert") -> usa o FALLBACK de local_state ATUAL (jira-tasks.sh items)
# como desired_state, nunca fabricando um valor.
scenario_resolve_overwrite_fallback_local_state_sem_evento_outbox() {
  _write_full_config
  _write_credential
  _write_tasks_1task_1sub
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  mkdir -p "$(dirname "$(_outbox_file)")"
  # ConflictRecord sem NENHUM evento outbox 'conflict' associado (simula
  # origem reconcile/convert — _js_append_conflict direto, sem outbox).
  cat > "$(_conflicts_file)" <<'EOF'
detected_at	feature	local_key	jira_key	reason	resolution
2026-01-01T00:00:00Z	demo	1.1	DEMO-2	marker_missing	pending
EOF
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"fields":{"summary":"Titulo atual no Jira","status":{"name":"To Do"}}}'
  # reason=marker_missing: o R6 GET do rebaseline (task 21.1.1) tambem
  # encontra 404 de verdade — mesma causa raiz do conflito.
  _queue_push 404 '{"errorMessages":["not found"]}'
  _queue_push 200 ''
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" resolve --feature demo --local-key 1.1 --choice overwrite || return 1
  grep -q 'demo	1\.1	DEMO-2	marker_missing	overwrite$' "$(_conflicts_file)" \
    || { _fail "sy49_resolution" "resolution nao virou overwrite: $(cat "$(_conflicts_file)")"; return 1; }
  # tasks.md (_write_tasks_1task_1sub) so tem checkboxes '[ ]' -> local_state
  # da task 1.1 e 'pending' (fonte real via jira-tasks.sh items).
  _novo=$(awk -F '\t' 'NR > 1 { print }' "$(_outbox_file)")
  printf '%s\n' "$_novo" | grep -q '	demo	1\.1	pending	manual	0	queued$' \
    || { _fail "sy49_new_event" "evento reenfileirado com desired_state incorreto (esperado pending via fallback): $_novo"; return 1; }
  return 0
}

# SY-50 resolve --choice overwrite: sem evento outbox 'conflict' E sem
# local_key resolvivel via jira-tasks.sh items (ex.: item renumerado/
# removido de tasks.md) -> exit 1, ConflictRecord PERMANECE pending (nunca
# fabrica um desired_state, Principio VI).
scenario_resolve_overwrite_sem_fonte_desired_state_exit1() {
  _write_full_config
  _write_credential
  # tasks.md SEM a task 1.1 (fonte de local_state indisponivel).
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cat > "$TMPDIR_TEST/docs/specs/demo/tasks.md" <<'EOF'
## FASE 1 - Sincronizacao `[A]`
EOF
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_conflicts_file)" <<'EOF'
detected_at	feature	local_key	jira_key	reason	resolution
2026-01-01T00:00:00Z	demo	1.1	DEMO-2	marker_missing	pending
EOF
  assert_exit 1 "$SCRIPT" resolve --feature demo --local-key 1.1 --choice overwrite || return 1
  grep -q 'demo	1\.1	DEMO-2	marker_missing	pending$' "$(_conflicts_file)" \
    || { _fail "sy50_conflict_untouched" "ConflictRecord nao deveria ter sido fechado sem fonte de desired_state: $(cat "$(_conflicts_file)")"; return 1; }
  [ -f "$(_outbox_file)" ] \
    && { _fail "sy50_no_outbox" "outbox.tsv foi criado mesmo sem desired_state resolvivel"; return 1; }
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

# r02 FASE 24 tarefa 24.5.1/24.5.2 (achado 24.5): `_js_process_reconcile_
# event` faz `_jspr_items=$("$_jsd_tasks" items ...); _jspr_items_ok=$?` —
# ANTES do fix, essa era uma atribuicao NUA sob `set -eu` (linha 148), fora
# de qualquer contexto `if`/`||` — uma falha de `jira-tasks.sh items`
# (aqui, `tasks.md` ausente) abortava o `drain` INTEIRO antes de `$?` ser
# lido, tornando o ramo de diagnostico "evento X permanece na fila" codigo
# morto: o evento `e2` (outro local_key, na MESMA fila) nunca chegava a
# ser processado. Com a guarda (`if var=$(...); then ...; else ec=$?; fi`),
# o evento `e1` (reconcile, `local_key=*`) MUST permanecer `queued`
# (nao consumido pela falha) e o diagnostico MUST aparecer em stderr, MAS
# o `drain` MUST continuar e processar `e2` normalmente ate `done`.
scenario_drain_reconcile_items_falha_tasks_md_ausente_outros_eventos_processados() {
  _write_full_config
  _write_credential
  _write_map_row "1.1" task 20002 DEMO-2 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  # tasks.md AUSENTE de proposito (nem docs/specs/demo/tasks.md existe) —
  # jira-tasks.sh items falha (exit 1) para o evento reconcile e1.
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	*	reconcile	hook-close-wave	0	queued
e2	2026-01-01T00:00:01Z	demo	1.1	pass	manual	0	queued
EOF
  _summary="Titulo da tarefa"
  _sha_summary=$(printf '%s' "$_summary" | "$IO_SCRIPT" sha256-stdin)
  _bin="$(_init_queue_stub)"
  # e2 (1.1, processado por _js_process_one_event — nao depende de
  # jira-tasks.sh items): ja no status alvo com marker batendo, idempotente
  # (so R3+R6-GET, prova que o item foi de fato alcancado e lido).
  _queue_push 200 "{\"fields\":{\"summary\":\"$_summary\",\"status\":{\"name\":\"Done\"}}}"
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_summary\",\"written_status\":\"Done\"}}"

  _out=$(PATH="$_bin:$PATH" "$SCRIPT" drain --feature demo 2>&1) \
    || { _fail "sy_reconcile_items_fail_exit" "drain deveria sair exit 0, saida: $_out"; return 1; }
  printf '%s\n' "$_out" | grep -q "jira-tasks.sh items falhou para demo — evento e1 permanece na fila" \
    || { _fail "sy_reconcile_items_fail_diag" "diagnostico esperado ausente, obtido: $_out"; return 1; }

  [ "$(_queue_calls_count)" = "2" ] \
    || { _fail "sy_reconcile_items_fail_calls" "esperado exatamente 2 chamadas (so o evento e2 chega a rede), obtido $(_queue_calls_count)"; return 1; }

  awk -F '\t' '$1=="e1"' "$(_outbox_file)" | grep -q 'queued$' \
    || { _fail "sy_reconcile_items_fail_e1_still_queued" "evento e1 deveria permanecer queued (nao consumido pela falha)"; return 1; }
  awk -F '\t' '$1=="e2"' "$(_outbox_file)" | grep -q 'done$' \
    || { _fail "sy_reconcile_items_fail_e2_done" "evento e2 deveria ter sido processado e fechado done"; return 1; }
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
  # 12.2.1: retry_after=30 (do header Retry-After) persistido no sidecar —
  # available_at_epoch DEVE ser estritamente maior que "agora" (nao 0/vazio).
  _avail=$(awk -F '\t' '$1=="e1"{print $2}' "$(_deferred_file)")
  [ -n "$_avail" ] \
    || { _fail "drain_429_retry_after_persisted" "sidecar deferred-retry.tsv sem linha para e1: $(cat "$(_deferred_file)" 2>/dev/null)"; return 1; }
  _now=$(date -u +%s)
  [ "$_avail" -gt "$_now" ] \
    || { _fail "drain_429_retry_after_future" "available_at_epoch ($_avail) deveria ser futuro (now=$_now)"; return 1; }
  return 0
}

# SY-51 drain (12.2.1): evento `deferred` com retry_after AINDA nao
# decorrido (sidecar available_at_epoch no futuro) -> NAO e selecionado
# pelo drain seguinte (ZERO chamadas novas, status permanece deferred).
scenario_drain_deferred_ainda_nao_elegivel_nao_e_retentado() {
  _write_full_config
  _write_credential
  _write_map_row "1.1" task 20002 DEMO-2 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	1.1	pass	manual	1	deferred
EOF
  _future=$(( $(date -u +%s) + 3600 ))
  printf 'event_id\tavailable_at_epoch\ne1\t%s\n' "$_future" > "$(_deferred_file)"
  _bin="$(_init_queue_stub)"
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" drain --feature demo || return 1

  [ "$(_queue_calls_count)" = "0" ] \
    || { _fail "sy51_no_calls" "esperado ZERO chamadas (retry_after nao decorrido), obtido $(_queue_calls_count)"; return 1; }
  awk -F '\t' '$1=="e1"' "$(_outbox_file)" | grep -q 'deferred$' \
    || { _fail "sy51_still_deferred" "evento e1 nao deveria ter mudado de status: $(awk -F '\t' '$1==\"e1\"' "$(_outbox_file)")"; return 1; }
  return 0
}

# SY-52 drain (12.2.1): evento `deferred` cujo retry_after JA decorreu
# (available_at_epoch no passado) -> drain o RETENTA e, sem novo conflito,
# transiciona normalmente (mesmo fluxo de 5 chamadas de SY-18).
scenario_drain_deferred_elegivel_e_retentado_ate_done() {
  _write_full_config
  _write_credential
  _write_map_row "1.1" task 20002 DEMO-2 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	1.1	pass	manual	1	deferred
EOF
  _past=$(( $(date -u +%s) - 60 ))
  printf 'event_id\tavailable_at_epoch\ne1\t%s\n' "$_past" > "$(_deferred_file)"
  _sha=$(printf '%s' "Titulo Atual" | "$IO_SCRIPT" sha256-stdin)
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"fields":{"summary":"Titulo Atual","status":{"name":"In Progress"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha\",\"written_status\":\"In Progress\"}}"
  _queue_push 200 '{"transitions":[{"id":"31","to":{"name":"Done"}}]}'
  _queue_push 204 ''
  _queue_push 200 ''
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" drain --feature demo || return 1

  [ "$(_queue_calls_count)" = "5" ] \
    || { _fail "sy52_calls" "esperado 5 chamadas (retomou a transicao inteira), obtido $(_queue_calls_count)"; return 1; }
  awk -F '\t' '$1=="e1"' "$(_outbox_file)" | grep -q 'done$' \
    || { _fail "sy52_done" "evento e1 nao fechou done apos retry elegivel: $(awk -F '\t' '$1==\"e1\"' "$(_outbox_file)")"; return 1; }
  # 12.2.1: transicao bem-sucedida (done) DEVE limpar a linha do sidecar
  # (_js_set_event_status limpa retry_after em toda transicao de status).
  grep -q '^e1	' "$(_deferred_file)" \
    && { _fail "sy52_sidecar_cleared" "sidecar deferred-retry.tsv ainda tem linha para e1 apos done: $(cat "$(_deferred_file)")"; return 1; }
  return 0
}

# SY-53 drain (12.2.1): evento `deferred` SEM linha no sidecar (rede/timeout
# generico, sem header Retry-After) -> elegivel IMEDIATAMENTE no proximo
# drain (nunca inventa um retry_after quando o Jira nao informou um).
scenario_drain_deferred_sem_retry_after_elegivel_de_imediato() {
  _write_full_config
  _write_credential
  _write_map_row "1.1" task 20002 DEMO-2 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	1.1	pending	manual	1	deferred
EOF
  # Sidecar AUSENTE (nunca escrito — rede/timeout generico, sem Retry-After).
  # R3 + R6-GET (SyncMarker, SEMPRE consultado antes do check "ja no alvo")
  # com titulo/status batendo -> sem conflito -> done direto, sem R5/R4/R6-PUT.
  _sha=$(printf '%s' "Titulo Atual" | "$IO_SCRIPT" sha256-stdin)
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"fields":{"summary":"Titulo Atual","status":{"name":"To Do"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha\",\"written_status\":\"To Do\"}}"
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" drain --feature demo || return 1

  [ "$(_queue_calls_count)" = "2" ] \
    || { _fail "sy53_calls" "esperado 2 chamadas (R3+R6-GET, ja no status alvo -> done sem R5/R4/R6-PUT): $(_queue_calls_count)"; return 1; }
  awk -F '\t' '$1=="e1"' "$(_outbox_file)" | grep -q 'done$' \
    || { _fail "sy53_done" "evento e1 deveria ter sido retentado e fechado done: $(awk -F '\t' '$1==\"e1\"' "$(_outbox_file)")"; return 1; }
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
  _queue_push 200 '{"fields":{"status":{"name":"To Do"}}}'
  _queue_push 201 ''
  _queue_push 201 '{"id":"20002","key":"DEMO-2"}'
  _queue_push 200 '{"fields":{"status":{"name":"To Do"}}}'
  _queue_push 201 ''
  _queue_push 201 '{"id":"20003","key":"DEMO-3"}'
  _queue_push 200 '{"fields":{"status":{"name":"To Do"}}}'
  _queue_push 201 ''
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" convert --feature demo || return 1

  _epic_desc=$("$IO_SCRIPT" json-get '.fields.description? // "none"' < "$TMPDIR_TEST/queue-curl-body-3.json")
  [ "$_epic_desc" = "none" ] || { _fail "sy36_epic_no_description" "Epic nao deveria ter fields.description (obtido $_epic_desc)"; return 1; }

  # chamada 6 = R1 da task (3=R1 epic,4=R3 epic,5=R6 epic, 11.1.1)
  _task_desc_text=$("$IO_SCRIPT" json-get '.fields.description.content[0].content[0].text' < "$TMPDIR_TEST/queue-curl-body-6.json")
  [ "$_task_desc_text" = "Criticidade: A" ] \
    || { _fail "sy36_task_description" "esperado 'Criticidade: A', obtido '$_task_desc_text'"; return 1; }

  # chamada 9 = R1 da sub-task (6=R1 task,7=R3 task,8=R6 task)
  _sub_desc=$("$IO_SCRIPT" json-get '.fields.description? // "none"' < "$TMPDIR_TEST/queue-curl-body-9.json")
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
  # myself + project + 5x (create + R3 status + R6 PUT, 11.1.1) — epic,
  # task1.1, sub1.1.1, task2.1, sub2.1.1
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
  _queue_push 201 '{"id":"20004","key":"DEMO-4"}'
  _queue_push 200 '{"fields":{"status":{"name":"To Do"}}}'
  _queue_push 201 ''
  _queue_push 201 '{"id":"20005","key":"DEMO-5"}'
  _queue_push 200 '{"fields":{"status":{"name":"To Do"}}}'
  _queue_push 201 ''
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" convert --feature demo || return 1

  # chamada 6 = R1 da task 1.1 (FASE 1, sem aresta de entrada na Matriz;
  # 3=R1 epic,4=R3 epic,5=R6 epic)
  _t1_desc=$("$IO_SCRIPT" json-get '.fields.description.content[0].content[0].text' < "$TMPDIR_TEST/queue-curl-body-6.json")
  [ "$_t1_desc" = "Criticidade: A" ] \
    || { _fail "sy37_fase1_sem_dependencia" "esperado 'Criticidade: A', obtido '$_t1_desc'"; return 1; }

  # chamada 12 = R1 da task 2.1 (FASE 2, aresta F1-->F2 na Matriz; 6/7/8=
  # task1.1, 9/10/11=sub1.1.1)
  _t2_desc=$("$IO_SCRIPT" json-get '.fields.description.content[0].content[0].text' < "$TMPDIR_TEST/queue-curl-body-12.json")
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
  _queue_push 200 '{"fields":{"status":{"name":"To Do"}}}'
  _queue_push 201 ''
  _queue_push 201 '{"id":"20002","key":"DEMO-2"}'
  _queue_push 200 '{"fields":{"status":{"name":"To Do"}}}'
  _queue_push 201 ''
  _queue_push 201 '{"id":"20003","key":"DEMO-3"}'
  _queue_push 200 '{"fields":{"status":{"name":"To Do"}}}'
  _queue_push 201 ''
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" convert --feature demo || return 1

  # chamada 6 = R1 da task (3=R1 epic,4=R3 epic,5=R6 epic, 11.1.1).
  # r02 FASE 17 (labels_enabled default "on"): a task ganha
  # fields.labels:["phase-1"] alem dos campos de sempre — sem
  # description (SY-38 continua provando isso).
  _task_fields=$("$IO_SCRIPT" json-get '.fields | keys_unsorted | sort | .[]' < "$TMPDIR_TEST/queue-curl-body-6.json" | tr '\n' ',')
  [ "$_task_fields" = "issuetype,labels,parent,project,summary," ] \
    || { _fail "sy38_task_sem_description" "esperado issuetype,labels,parent,project,summary (sem description) — obtido $_task_fields"; return 1; }
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
  _queue_push 200 '{"fields":{"summary":"[FASE 1] 1.1 Titulo antigo","status":{"name":"To Do"}}}'
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

# SY-45 (FASE 11 tarefa 11.3.1, FR-011): titulo local mudou (R2 seria
# tentado), o summary ATUAL no Jira bate com o hash do SyncMarker (sem
# edicao manual de TITULO), mas o STATUS atual da issue diverge do
# written_status do SyncMarker (transicao manual via UI desde a ultima
# sync) -> `_js_maybe_update_mapped_issue` MUST tratar isso como
# `manual_edit` e NUNCA disparar o PUT R2 — mesmo que o hash do titulo
# sozinho batesse. Antes de 11.3.1 esta funcao lia so `fields=summary` e
# ignorava `status`, deixando esse caso passar como "seguro" (achado
# converge FASE 11 11.3).
scenario_convert_status_divergente_vira_conflict_mesmo_com_titulo_batendo() {
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
  # summary atual = EXATAMENTE o que o SyncMarker gravou (sha vai bater),
  # mas status atual = "In Progress" != written_status = "To Do".
  _queue_push 200 '{"fields":{"summary":"[FASE 1] 1.1 Titulo antigo","status":{"name":"In Progress"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_antigo\",\"written_status\":\"To Do\"}}"
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" convert --feature demo || return 1

  [ "$(_queue_calls_count)" = "5" ] \
    || { _fail "sy45_calls_count" "esperado 5 chamadas (nenhuma escrita apos detectar status divergente), obtido $(_queue_calls_count)"; return 1; }
  grep -q 'demo	1\.1	DEMO-2	manual_edit	pending$' "$(_conflicts_file)" \
    || { _fail "sy45_conflict_record" "ConflictRecord manual_edit ausente/incorreto (status divergente): $(cat "$(_conflicts_file)" 2>/dev/null)"; return 1; }
  return 0
}

# _write_tasks_criticidade_mudada: FASE 1 / task 1.1 com o MESMO titulo de
# `_write_tasks_1task_1sub` ("Titulo da tarefa") mas criticidade `[C]` em
# vez de `[A]` — summary composto fica IDENTICO (a letra de criticidade
# nunca entra no summary, so na description), so a description muda
# ("Criticidade: C" em vez de "Criticidade: A"). Usada por SY-51 (FASE 12
# tarefa 12.5.1, achado 12.5): mudanca SO de criticidade/dependencias.
_write_tasks_criticidade_mudada() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cat > "$TMPDIR_TEST/docs/specs/demo/tasks.md" <<'EOF'
## FASE 1 - Sincronizacao `[A]`

### 1.1 Titulo da tarefa `[C]`
EOF
}

# SY-51 (FASE 12 tarefa 12.5.1, achado 12.5, FR-003/FR-011): item ja
# mapeado cujo summary NAO mudou mas a criticidade mudou (`[A]` -> `[C]`)
# -> ANTES de 12.5.1, `_js_maybe_update_mapped_issue` retornava cedo (early
# exit so olhava summary) e a description nunca era atualizada. Com
# 12.5.1, a Task e lida com `fields=summary,status,description`; a
# description atual ("Criticidade: A") diverge da composta agora
# ("Criticidade: C") -> content_changed=yes mesmo com summary identico. O
# SyncMarker ja tem `written_description_sha256` da baseline anterior
# (simula uma sync bem-sucedida previa) e bate com a description atual ->
# sem conflito -> R2 PUT (summary reenviado + NOVA description) e o
# SyncMarker e regravado com o novo `written_description_sha256`,
# `written_summary_sha256`/`written_status` preservados/reconfirmados.
scenario_convert_criticidade_mudada_atualiza_description_via_r2_sem_conflito() {
  _write_full_config
  _write_tasks_criticidade_mudada
  _write_credential
  _write_map_row "demo" epic 20001 DEMO-1 active
  _write_map_row "1.1" task 20002 DEMO-2 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  _sha_summary=$(printf '%s' "[FASE 1] 1.1 Titulo da tarefa" | "$IO_SCRIPT" sha256-stdin)
  _sha_desc_antiga=$(printf '%s' "Criticidade: A" | "$IO_SCRIPT" sha256-stdin)
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"accountId":"acc-1"}'
  _queue_push 200 '{"id":"10000","key":"DEMO"}'
  # Epic: sem componente de descricao -> summary inalterado -> no-op imediato.
  _queue_push 200 '{"fields":{"summary":"demo"}}'
  # Task 1.1: summary IGUAL, status "To Do", description ANTIGA "Criticidade: A".
  _queue_push 200 "{\"fields\":{\"summary\":\"[FASE 1] 1.1 Titulo da tarefa\",\"status\":{\"name\":\"To Do\"},\"description\":{\"type\":\"doc\",\"version\":1,\"content\":[{\"type\":\"paragraph\",\"content\":[{\"type\":\"text\",\"text\":\"Criticidade: A\"}]}]}}}"
  # SyncMarker: baseline completa (summary+status+description) bate com o
  # atual -> sem conflito.
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_summary\",\"written_status\":\"To Do\",\"written_description_sha256\":\"$_sha_desc_antiga\"}}"
  _queue_push 204 ''
  _queue_push 200 ''
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" convert --feature demo || return 1

  [ "$(_queue_post_issue_calls_count)" = "0" ] \
    || { _fail "sy51_zero_creates" "esperado 0 POST /issue, obtido $(_queue_post_issue_calls_count)"; return 1; }
  [ "$(_queue_calls_count)" = "7" ] \
    || { _fail "sy51_calls_count" "esperado 7 chamadas (myself+project+R3epic+R3task+R6get+R2put+R6put), obtido $(_queue_calls_count)"; return 1; }

  _r2_summary=$("$IO_SCRIPT" json-get '.fields.summary' < "$TMPDIR_TEST/queue-curl-body-6.json")
  [ "$_r2_summary" = "[FASE 1] 1.1 Titulo da tarefa" ] \
    || { _fail "sy51_r2_summary" "esperado summary inalterado, obtido '$_r2_summary'"; return 1; }
  _r2_desc=$("$IO_SCRIPT" json-get '.fields.description.content[0].content[0].text' < "$TMPDIR_TEST/queue-curl-body-6.json")
  [ "$_r2_desc" = "Criticidade: C" ] \
    || { _fail "sy51_r2_description" "esperado 'Criticidade: C' (mudanca so de criticidade deveria propagar), obtido '$_r2_desc'"; return 1; }

  _sha_desc_nova=$(printf '%s' "Criticidade: C" | "$IO_SCRIPT" sha256-stdin)
  _marker_desc_sha=$("$IO_SCRIPT" json-get '.written_description_sha256' < "$TMPDIR_TEST/queue-curl-body-7.json")
  [ "$_marker_desc_sha" = "$_sha_desc_nova" ] \
    || { _fail "sy51_marker_desc_sha" "esperado hash da nova description no SyncMarker, obtido '$_marker_desc_sha'"; return 1; }
  _marker_status=$("$IO_SCRIPT" json-get '.written_status' < "$TMPDIR_TEST/queue-curl-body-7.json")
  [ "$_marker_status" = "To Do" ] \
    || { _fail "sy51_marker_status_preservado" "esperado written_status preservado 'To Do', obtido '$_marker_status'"; return 1; }
  return 0
}

# r02 FASE 24 tarefa 24.3.1/24.3.3 (achado 24.3): R2 PUT de summary de
# `_js_maybe_update_mapped_issue` responde 400 — `--op R2` so classifica
# 401/403/429/5xx (jira-io.sh); 400/404/409/422 ficam em passthrough (exit
# 0, contracts/jira-rest.md:121) — sem checar `http_status`, o 400 seria
# tratado como sucesso e o SyncMarker regravado com o hash do summary NOVO
# sem ele ter sido de fato aplicado (baseline falsa). MUST: ZERO R6 PUT do
# marker apos o 400 (fase 1), e a proxima `convert` da MESMA feature —
# summary real AINDA o antigo (R2 nunca aplicou), SyncMarker AINDA com o
# hash antigo (R6 PUT nunca ocorreu) — NUNCA abre `manual_edit` espurio
# (fase 2), apenas retenta o R2.
scenario_convert_r2_400_nao_grava_baseline_falsa_nem_abre_manual_edit() {
  _write_full_config
  _write_tasks_titulo_mudado
  _write_credential
  _write_map_row "demo" epic 20001 DEMO-1 active
  _write_map_row "1.1" task 20002 DEMO-2 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  _sha_antigo=$(printf '%s' "[FASE 1] 1.1 Titulo antigo" | "$IO_SCRIPT" sha256-stdin)
  _bin="$(_init_queue_stub)"

  # Fase 1: R2 falha com 400 -> ZERO R6 PUT.
  _queue_push 200 '{"accountId":"acc-1"}'
  _queue_push 200 '{"id":"10000","key":"DEMO"}'
  _queue_push 200 '{"fields":{"summary":"demo"}}'
  _queue_push 200 '{"fields":{"summary":"[FASE 1] 1.1 Titulo antigo","status":{"name":"To Do"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_antigo\",\"written_status\":\"To Do\"}}"
  _queue_push 400 '{"errorMessages":["invalid body"]}'
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" convert --feature demo || return 1

  [ "$(_queue_calls_count)" = "6" ] \
    || { _fail "sy24_3_1_calls" "esperado 6 chamadas (myself+project+R3epic+R3task+R6get+R2put[400]), obtido $(_queue_calls_count)"; return 1; }
  grep -qE '^PUT .*issue/DEMO-2/properties' "$TMPDIR_TEST/queue-curl-calls.log" \
    && { _fail "sy24_3_1_no_marker_put" "R6 PUT do marker NAO deveria ocorrer apos R2 400 (baseline falsa)"; return 1; }
  [ -f "$(_conflicts_file)" ] && grep -q 'manual_edit' "$(_conflicts_file)" \
    && { _fail "sy24_3_1_no_manual_edit_fase1" "fase 1 nao deveria abrir manual_edit"; return 1; }

  # Fase 2: 2a convert da MESMA feature (mesma fila, continuacao) — o
  # summary real permanece "Titulo antigo" (R2 nunca aplicou) e o
  # SyncMarker ainda tem o hash antigo (R6 PUT nunca ocorreu) -> sha bate,
  # ZERO manual_edit, apenas retenta o R2.
  _queue_push 200 '{"accountId":"acc-1"}'
  _queue_push 200 '{"id":"10000","key":"DEMO"}'
  _queue_push 200 '{"fields":{"summary":"demo"}}'
  _queue_push 200 '{"fields":{"summary":"[FASE 1] 1.1 Titulo antigo","status":{"name":"To Do"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_antigo\",\"written_status\":\"To Do\"}}"
  _queue_push 400 '{"errorMessages":["invalid body"]}'
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" convert --feature demo || return 1

  [ -f "$(_conflicts_file)" ] && grep -q 'manual_edit' "$(_conflicts_file)" \
    && { _fail "sy24_3_1_no_manual_edit_fase2" "a proxima checagem NUNCA deveria abrir manual_edit apos R2 400 (baseline preservada): $(cat "$(_conflicts_file)" 2>/dev/null)"; return 1; }
  _r2_calls=$(grep -cE '^PUT .*api/3/issue/DEMO-2$' "$TMPDIR_TEST/queue-curl-calls.log" 2>/dev/null) || _r2_calls=0
  [ "$_r2_calls" -ge "2" ] \
    || { _fail "sy24_3_1_retry" "esperado pelo menos 2 tentativas de R2 PUT (retry), obtido $_r2_calls: $(cat "$TMPDIR_TEST/queue-curl-calls.log" 2>/dev/null)"; return 1; }
  return 0
}

# r02 FASE 24 tarefa 24.3.2/24.3.3 (achado 24.3): o R6 PUT de
# `_js_maybe_update_mapped_issue` substitui o valor INTEIRO da entity
# property (mesma disciplina de `_js_process_one_event` 24.2.1). MUST:
# `written_phase_label` lido do marker atual e carregado adiante no R6 PUT
# regravado apos um R2 (summary) bem-sucedido — sem isto, todo `convert`
# que mude o titulo apagaria o label de fase da Task.
scenario_convert_titulo_mudado_preserva_written_phase_label_no_r6() {
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
  _queue_push 200 '{"fields":{"summary":"[FASE 1] 1.1 Titulo antigo","status":{"name":"To Do"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_antigo\",\"written_status\":\"To Do\",\"written_phase_label\":\"phase-1\"}}"
  _queue_push 204 ''
  _queue_push 200 ''
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" convert --feature demo || return 1

  [ "$(_queue_calls_count)" = "7" ] \
    || { _fail "sy24_3_2_calls" "esperado 7 chamadas (myself+project+R3epic+R3task+R6get+R2put+R6put), obtido $(_queue_calls_count)"; return 1; }
  _marker_label=$("$IO_SCRIPT" json-get '.written_phase_label? // "AUSENTE"' < "$TMPDIR_TEST/queue-curl-body-7.json")
  [ "$_marker_label" = "phase-1" ] \
    || { _fail "sy24_3_2_phase_label" "esperado written_phase_label preservado 'phase-1' no R6 PUT, obtido '$_marker_label'"; return 1; }
  return 0
}

# SY-46 (FASE 11 tarefa 11.1.1, FR-011): end-to-end convert -> drain. Antes
# de 11.1.1, `convert` nunca gravava o SyncMarker inicial das issues criadas
# -> o 1o `drain` de qualquer issue recem-criada lia R6=404 e virava
# `marker_missing` (achado converge FASE 11 11.1). O stub de fila nao
# persiste o que `convert` de fato enviou no R6 PUT — o cenario simula a
# persistencia respondendo ao R3/R6-GET do `drain` com os MESMOS
# summary/status/hash que `convert` compos (mesma `jira-title.sh compose` +
# `jira-io.sh sha256-stdin`), provando que os dois lados usam a MESMA
# composicao e que, com o marker de fato persistido, `drain` NUNCA reporta
# marker_missing e transiciona normalmente.
scenario_convert_depois_drain_end_to_end_sem_marker_missing() {
  _write_full_config
  _write_tasks_1task_1sub
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
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" convert --feature demo || return 1

  assert_exit 0 "$SCRIPT" enqueue --feature demo --local-key 1.1 --state pass --source manual >/dev/null || return 1

  # drain: titulo/status atuais IDENTICOS ao que convert gravaria via R6 PUT
  # (mesma composicao "[FASE N] N.M <titulo>" + hash do summary) -> SyncMarker
  # BATE -> nenhum ConflictRecord, transiciona normalmente.
  _task_summary="[FASE 1] 1.1 Titulo da tarefa"
  _sha_task=$(printf '%s' "$_task_summary" | "$IO_SCRIPT" sha256-stdin)
  _queue_push 200 "{\"fields\":{\"summary\":\"$_task_summary\",\"status\":{\"name\":\"To Do\"}}}"
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_task\",\"written_status\":\"To Do\"}}"
  _queue_push 200 '{"transitions":[{"id":"31","to":{"name":"Done"}}]}'
  _queue_push 204 ''
  _queue_push 200 ''
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" drain --feature demo || return 1

  if [ -f "$(_conflicts_file)" ] && grep -q 'marker_missing' "$(_conflicts_file)"; then
    _fail "sy46_no_marker_missing" "drain reportou marker_missing apos convert ja ter gravado o SyncMarker inicial (11.1.1): $(cat "$(_conflicts_file)")"
    return 1
  fi
  _outbox_row=$(awk -F '\t' '$4=="1.1"' "$(_outbox_file)")
  printf '%s' "$_outbox_row" | grep -q 'done$' \
    || { _fail "sy46_drain_done" "evento 1.1 nao foi marcado done: $_outbox_row"; return 1; }
  return 0
}

# =============== drain: reconciliacao local_key=* (FASE 10 tarefa 10.3) ====

# _write_tasks_epic_task_sub_todos_pass: Epic > Task 1.1 > Sub-task 1.1.1,
# sub-task `[x]` (pass) -> Task 1.1 tambem projeta pass (unico sub-item, 100%
# pass) -> Epic tambem projeta pass (unica task, 100% pass). Os 3 itens tem
# o MESMO desired_state (pass) para simplificar a fixture; SY-42 varia o
# status ATUAL de cada issue no Jira (via stub) para cobrir transicao E
# idempotencia com um unico tasks.md.
_write_tasks_epic_task_sub_todos_pass() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cat > "$TMPDIR_TEST/docs/specs/demo/tasks.md" <<'EOF'
## FASE 1 - Sincronizacao `[A]`

### 1.1 Titulo da tarefa `[A]`

- [x] 1.1.1 Sub um
EOF
}

# SY-42 drain (FR-004, US3 cenario 1/US2 cenario 1): evento local_key=*
# expandido em 3 itens (Epic/Task/Sub-task, todos desired_state=pass) —
# Epic e Sub-task tem status ATUAL divergente do alvo (transicionam via
# R5/R4/R6-PUT); Task ja esta no status alvo COM SyncMarker batendo
# (idempotente: SOMENTE R3+R6-GET, nenhuma chamada de escrita/transicao).
# Evento `*` fecha `done`; uma 2a chamada de `drain` compacta o evento (some
# do outbox.tsv, 4.2.8).
scenario_drain_reconcile_expande_itens_transiciona_e_idempotente() {
  _write_full_config
  _write_credential
  _write_tasks_epic_task_sub_todos_pass
  _write_map_row "demo" epic 20001 DEMO-1 active
  _write_map_row "1.1" task 20002 DEMO-2 active
  _write_map_row "1.1.1" subtask 20003 DEMO-3 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	*	reconcile	hook-close-wave	0	queued
EOF
  _sha_epic=$(printf '%s' "demo" | "$IO_SCRIPT" sha256-stdin)
  _sha_task=$(printf '%s' "Titulo Qualquer" | "$IO_SCRIPT" sha256-stdin)
  _sha_sub=$(printf '%s' "Sub Titulo" | "$IO_SCRIPT" sha256-stdin)
  _bin="$(_init_queue_stub)"
  # Epic (DEMO-1): "To Do" -> "Done" (transiciona: R3,R6get,R5,R4,R6put).
  _queue_push 200 '{"fields":{"summary":"demo","status":{"name":"To Do"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_epic\",\"written_status\":\"To Do\"}}"
  _queue_push 200 '{"transitions":[{"id":"21","to":{"name":"To Do"}},{"id":"31","to":{"name":"Done"}}]}'
  _queue_push 204 ''
  _queue_push 200 ''
  # Task 1.1 (DEMO-2): ja "Done" com marker batendo -> idempotente (R3,R6get).
  _queue_push 200 '{"fields":{"summary":"Titulo Qualquer","status":{"name":"Done"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_task\",\"written_status\":\"Done\"}}"
  # Sub-task 1.1.1 (DEMO-3): "In Progress" -> "Done" (transiciona).
  _queue_push 200 '{"fields":{"summary":"Sub Titulo","status":{"name":"In Progress"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_sub\",\"written_status\":\"In Progress\"}}"
  _queue_push 200 '{"transitions":[{"id":"55","to":{"name":"In Progress"}},{"id":"66","to":{"name":"Done"}}]}'
  _queue_push 204 ''
  _queue_push 200 ''
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" drain --feature demo || return 1

  [ "$(_queue_calls_count)" = "12" ] \
    || { _fail "sy42_calls_count" "esperado 12 chamadas (5 epic + 2 task idempotente + 5 subtask), obtido $(_queue_calls_count)"; return 1; }
  awk -F '\t' '$1=="e1"' "$(_outbox_file)" | grep -q 'done$' \
    || { _fail "sy42_event_done" "evento e1 (*) nao foi marcado done: $(awk -F '\t' '$1==\"e1\"' "$(_outbox_file)")"; return 1; }

  _epic_trans=$("$IO_SCRIPT" json-get '.transition.id' < "$TMPDIR_TEST/queue-curl-body-4.json")
  [ "$_epic_trans" = "31" ] || { _fail "sy42_epic_transition" "esperado transition.id=31 para o Epic, obtido $_epic_trans"; return 1; }
  _epic_marker_lkey=$("$IO_SCRIPT" json-get '.local_key' < "$TMPDIR_TEST/queue-curl-body-5.json")
  [ "$_epic_marker_lkey" = "demo" ] || { _fail "sy42_epic_marker_lkey" "esperado local_key=demo no marker do Epic, obtido $_epic_marker_lkey"; return 1; }

  [ -f "$TMPDIR_TEST/queue-curl-body-6.json" ] \
    && { _fail "sy42_task_no_write" "Task 1.1 (idempotente) NAO deveria gerar nenhum corpo de escrita entre as chamadas 6-7"; return 1; }

  _sub_trans=$("$IO_SCRIPT" json-get '.transition.id' < "$TMPDIR_TEST/queue-curl-body-11.json")
  [ "$_sub_trans" = "66" ] || { _fail "sy42_sub_transition" "esperado transition.id=66 para a Sub-task, obtido $_sub_trans"; return 1; }
  _sub_marker_lkey=$("$IO_SCRIPT" json-get '.local_key' < "$TMPDIR_TEST/queue-curl-body-12.json")
  [ "$_sub_marker_lkey" = "1.1.1" ] || { _fail "sy42_sub_marker_lkey" "esperado local_key=1.1.1 no marker da Sub-task, obtido $_sub_marker_lkey"; return 1; }

  # 2a chamada de drain: sem eventos queued novos, so compactacao (4.2.8) —
  # o evento `*` (agora done) deve sumir do outbox.tsv.
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" drain --feature demo || return 1
  awk -F '\t' '$1=="e1"' "$(_outbox_file)" | grep -q . \
    && { _fail "sy42_compacted" "evento e1 deveria ter sido compactado (removido) na 2a chamada de drain"; return 1; }
  return 0
}

# SY-58 drain reconcile (FASE 12 tarefa 12.8.1, data-model.md ProjectConfig
# `stage_status.<stage>` / US2 cenario 1): com `stage_status.execute-task`
# configurado e uma execucao feature-00c ativa (`.claude/feature-00c-state/
# demo/state.json` `current_stage=execute-task`), o Epic transiciona para o
# status DIRETO do override ("In Review"), NAO para o alvo que a agregacao
# por tasks produziria (unica task 100% pass -> "Done", `status_pass` do
# ProjectConfig). So o Epic e mapeado (Task/Sub-task ficam fora do
# jira-map.tsv de proposito — sem mapeamento, item e ignorado — reduz o
# cenario a 5 chamadas: R3/R6-GET/R5/R4/R6-PUT).
scenario_drain_reconcile_epic_usa_stage_status_do_stage_ativo() {
  _write_full_config
  printf 'stage_status.execute-task=In Review\n' >> "$TMPDIR_TEST/.claude/cstk-jira/config"
  _write_credential
  _write_tasks_epic_task_sub_todos_pass
  _write_map_row "demo" epic 20001 DEMO-1 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  mkdir -p "$TMPDIR_TEST/.claude/feature-00c-state/demo"
  printf '{"current_stage":"execute-task"}' > "$TMPDIR_TEST/.claude/feature-00c-state/demo/state.json"
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	*	reconcile	hook-close-wave	0	queued
EOF
  _sha_epic=$(printf '%s' "demo" | "$IO_SCRIPT" sha256-stdin)
  _bin="$(_init_queue_stub)"
  # Epic (DEMO-1): "To Do" atual. Sem stage_status seria "pass" -> "Done"
  # (unica task 100% pass); com o override o alvo passa a ser "In Review"
  # diretamente (nao passa pelo mapeamento status_pass).
  _queue_push 200 '{"fields":{"summary":"demo","status":{"name":"To Do"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_epic\",\"written_status\":\"To Do\"}}"
  _queue_push 200 '{"transitions":[{"id":"21","to":{"name":"Done"}},{"id":"31","to":{"name":"In Review"}}]}'
  _queue_push 204 ''
  _queue_push 200 ''
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" drain --feature demo || return 1

  [ "$(_queue_calls_count)" = "5" ] \
    || { _fail "sy58_calls_count" "esperado 5 chamadas (R3,R6get,R5,R4,R6put), obtido $(_queue_calls_count)"; return 1; }
  _epic_trans=$("$IO_SCRIPT" json-get '.transition.id' < "$TMPDIR_TEST/queue-curl-body-4.json")
  [ "$_epic_trans" = "31" ] \
    || { _fail "sy58_transition" "esperado transition.id=31 (In Review, via stage_status), obtido $_epic_trans"; return 1; }
  _marker_status=$("$IO_SCRIPT" json-get '.written_status' < "$TMPDIR_TEST/queue-curl-body-5.json")
  [ "$_marker_status" = "In Review" ] \
    || { _fail "sy58_marker_status" "esperado written_status=In Review no SyncMarker, obtido '$_marker_status'"; return 1; }
  return 0
}

# SY-59 drain reconcile (mesmo achado 12.8.1): SEM execucao ativa legivel
# (nem feature-00c nem agente-00c) `_js_resolve_stage` retorna vazio ->
# `--stage` nunca e passado a `jira-tasks.sh items` -> `stage_status.*`
# configurado no ProjectConfig e IGNORADO -> Epic segue a agregacao normal
# por tasks (unica task 100% pass -> "Done", `status_pass`). Prova que o
# override so se aplica quando a etapa corrente e de fato resolvivel
# (Principio VI: nunca inventar uma etapa).
scenario_drain_reconcile_sem_execucao_ativa_ignora_stage_status() {
  _write_full_config
  printf 'stage_status.execute-task=In Review\n' >> "$TMPDIR_TEST/.claude/cstk-jira/config"
  _write_credential
  _write_tasks_epic_task_sub_todos_pass
  _write_map_row "demo" epic 20001 DEMO-1 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	*	reconcile	hook-close-wave	0	queued
EOF
  _sha_epic=$(printf '%s' "demo" | "$IO_SCRIPT" sha256-stdin)
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"fields":{"summary":"demo","status":{"name":"To Do"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_epic\",\"written_status\":\"To Do\"}}"
  _queue_push 200 '{"transitions":[{"id":"21","to":{"name":"Done"}},{"id":"31","to":{"name":"In Review"}}]}'
  _queue_push 204 ''
  _queue_push 200 ''
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" drain --feature demo || return 1

  _epic_trans=$("$IO_SCRIPT" json-get '.transition.id' < "$TMPDIR_TEST/queue-curl-body-4.json")
  [ "$_epic_trans" = "21" ] \
    || { _fail "sy59_transition" "sem execucao ativa, esperado transition.id=21 (Done, agregacao normal), obtido $_epic_trans"; return 1; }
  return 0
}

# Instala um stub de `state-rw.sh` (runtime agente-00c-runtime) sob
# CSTK_LIB/../skills/agente-00c-runtime/scripts, para os cenarios SY-60/
# SY-61 provarem que `_js_resolve_state_field` (task 13.1.1) delega o ramo
# state.db a este helper via `get --state-dir D --field .campo`, NUNCA a
# `sqlite3` diretamente. `$1` = valor a devolver para `.current_stage`
# (vazio -> stub falha, simulando "campo nao encontrado").
_install_state_rw_stub() {
  _isrs_val="$1"
  _isrs_scripts_dir="$TMPDIR_TEST/stubroot/skills/agente-00c-runtime/scripts"
  mkdir -p "$TMPDIR_TEST/stubroot/lib" "$_isrs_scripts_dir"
  cat > "$_isrs_scripts_dir/state-rw.sh" <<EOF
#!/bin/sh
[ "\$1" = "get" ] || exit 2
shift
_dir=""
_field=""
while [ "\$#" -gt 0 ]; do
  case "\$1" in
    --state-dir) _dir=\$2; shift 2 ;;
    --field) _field=\$2; shift 2 ;;
    *) shift ;;
  esac
done
[ -f "\$_dir/state.db" ] || exit 1
[ "\$_field" = ".current_stage" ] || exit 1
[ -n "$_isrs_val" ] || exit 1
printf '%s\n' "$_isrs_val"
EOF
  chmod +x "$_isrs_scripts_dir/state-rw.sh"
  export CSTK_LIB="$TMPDIR_TEST/stubroot/lib"
}

# SY-60 drain reconcile (task 13.1.1, ramo state.db de `_js_resolve_stage`
# via `_js_resolve_state_field`/`_js_runtime_state_rw`): com
# `.claude/feature-00c-state/demo/state.db` (backend SQLite; conteudo
# irrelevante — jira-sync.sh NUNCA abre o arquivo, so checa presenca e
# delega ao runtime) e um `state-rw.sh` stub (via CSTK_LIB) devolvendo
# `execute-task`, o Epic transiciona para o status DIRETO do override
# (`stage_status.execute-task=In Review`) — mesmo resultado de SY-58
# (branch state.json), provando que a delegacao ao runtime funciona sem
# jamais invocar `sqlite3`.
scenario_drain_reconcile_state_db_via_runtime_stub_usa_stage_status() {
  _write_full_config
  printf 'stage_status.execute-task=In Review\n' >> "$TMPDIR_TEST/.claude/cstk-jira/config"
  _write_credential
  _write_tasks_epic_task_sub_todos_pass
  _write_map_row "demo" epic 20001 DEMO-1 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  mkdir -p "$TMPDIR_TEST/.claude/feature-00c-state/demo"
  : > "$TMPDIR_TEST/.claude/feature-00c-state/demo/state.db"
  _install_state_rw_stub "execute-task"
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	*	reconcile	hook-close-wave	0	queued
EOF
  _sha_epic=$(printf '%s' "demo" | "$IO_SCRIPT" sha256-stdin)
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"fields":{"summary":"demo","status":{"name":"To Do"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_epic\",\"written_status\":\"To Do\"}}"
  _queue_push 200 '{"transitions":[{"id":"21","to":{"name":"Done"}},{"id":"31","to":{"name":"In Review"}}]}'
  _queue_push 204 ''
  _queue_push 200 ''
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" drain --feature demo || return 1

  _epic_trans=$("$IO_SCRIPT" json-get '.transition.id' < "$TMPDIR_TEST/queue-curl-body-4.json")
  [ "$_epic_trans" = "31" ] \
    || { _fail "sy60_transition" "esperado transition.id=31 (In Review, via stage_status/state.db+stub), obtido $_epic_trans"; return 1; }
  return 0
}

# SY-61 drain reconcile (task 13.1.1): com `state.db` presente mas SEM
# runtime localizavel (CSTK_LIB unset e HOME redirecionado para um
# diretorio sem `.claude/skills/agente-00c-runtime`), `_js_resolve_stage`
# devolve vazio -> `--stage` nunca e passado -> `stage_status.*` e
# IGNORADO -> Epic segue a agregacao normal por tasks (mesmo veredito de
# SY-59, agora provado para o ramo state.db). Confirma que a ausencia do
# runtime nunca inventa uma etapa nem tenta `sqlite3` como fallback.
scenario_drain_reconcile_state_db_sem_runtime_localizavel_ignora_stage_status() {
  _write_full_config
  printf 'stage_status.execute-task=In Review\n' >> "$TMPDIR_TEST/.claude/cstk-jira/config"
  _write_credential
  _write_tasks_epic_task_sub_todos_pass
  _write_map_row "demo" epic 20001 DEMO-1 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  mkdir -p "$TMPDIR_TEST/.claude/feature-00c-state/demo"
  : > "$TMPDIR_TEST/.claude/feature-00c-state/demo/state.db"
  unset CSTK_LIB
  export HOME="$TMPDIR_TEST/fake-home-sem-runtime"
  mkdir -p "$HOME"
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	*	reconcile	hook-close-wave	0	queued
EOF
  _sha_epic=$(printf '%s' "demo" | "$IO_SCRIPT" sha256-stdin)
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"fields":{"summary":"demo","status":{"name":"To Do"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_epic\",\"written_status\":\"To Do\"}}"
  _queue_push 200 '{"transitions":[{"id":"21","to":{"name":"Done"}},{"id":"31","to":{"name":"In Review"}}]}'
  _queue_push 204 ''
  _queue_push 200 ''
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" drain --feature demo || return 1

  _epic_trans=$("$IO_SCRIPT" json-get '.transition.id' < "$TMPDIR_TEST/queue-curl-body-4.json")
  [ "$_epic_trans" = "21" ] \
    || { _fail "sy61_transition" "sem runtime localizavel, esperado transition.id=21 (Done, agregacao normal), obtido $_epic_trans"; return 1; }
  return 0
}

# SY-43 drain (FR-011/FR-004): reconciliacao com 2 itens — Epic com
# conflito (manual_edit, ConflictRecord gravado) e Task transicionando
# normalmente. O conflito de UM item NUNCA impede o processamento dos
# demais; o evento `*` fecha `done` (o veredito de conflito e por-item via
# ConflictRecord, nao propagado ao status do evento de reconciliacao).
scenario_drain_reconcile_conflito_em_um_item_nao_bloqueia_os_demais() {
  _write_full_config
  _write_credential
  _write_tasks_1task_1sub
  _write_map_row "demo" epic 20001 DEMO-1 active
  _write_map_row "1.1" task 20002 DEMO-2 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	*	reconcile	hook-close-wave	0	queued
EOF
  # tasks.md so tem 1.1 sem sub-task marcada -> Task 1.1 = pending (0 subs),
  # Epic = pending (nenhuma task pass/ativa) -> ambos desired_state=pending.
  _sha_epic_original=$(printf '%s' "Titulo Original" | "$IO_SCRIPT" sha256-stdin)
  _sha_task=$(printf '%s' "Task Titulo" | "$IO_SCRIPT" sha256-stdin)
  _bin="$(_init_queue_stub)"
  # Epic (DEMO-1): titulo atual diverge do sha256 gravado -> manual_edit.
  _queue_push 200 '{"fields":{"summary":"Titulo Mudou Manualmente","status":{"name":"To Do"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_epic_original\",\"written_status\":\"To Do\"}}"
  # Task 1.1 (DEMO-2): sem conflito, transiciona normalmente para "To Do".
  _queue_push 200 '{"fields":{"summary":"Task Titulo","status":{"name":"In Progress"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_task\",\"written_status\":\"In Progress\"}}"
  _queue_push 200 '{"transitions":[{"id":"71","to":{"name":"To Do"}},{"id":"81","to":{"name":"In Progress"}}]}'
  _queue_push 204 ''
  _queue_push 200 ''
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" drain --feature demo || return 1

  [ "$(_queue_calls_count)" = "7" ] \
    || { _fail "sy43_calls_count" "esperado 7 chamadas (2 epic conflito + 5 task transicao), obtido $(_queue_calls_count)"; return 1; }
  awk -F '\t' '$1=="e1"' "$(_outbox_file)" | grep -q 'done$' \
    || { _fail "sy43_event_done" "evento e1 (*) deveria fechar done mesmo com conflito num item: $(awk -F '\t' '$1==\"e1\"' "$(_outbox_file)")"; return 1; }
  grep -q 'demo	demo	DEMO-1	manual_edit	pending$' "$(_conflicts_file)" \
    || { _fail "sy43_conflict_record" "ConflictRecord do Epic ausente/incorreto: $(cat "$(_conflicts_file)" 2>/dev/null)"; return 1; }
  _task_trans=$("$IO_SCRIPT" json-get '.transition.id' < "$TMPDIR_TEST/queue-curl-body-6.json")
  [ "$_task_trans" = "71" ] || { _fail "sy43_task_transition" "esperado transition.id=71 (To Do) para a Task, obtido $_task_trans"; return 1; }
  return 0
}

# SY-44 drain (FR-016): 401 na 1a chamada de rede (R3 do 1o item, Epic) ->
# evento `*` vira `auth_failed` (mesmo gate de um evento direto) e a
# reconciliacao para IMEDIATAMENTE — a Task (2o item) nunca e tocada.
scenario_drain_reconcile_401_no_primeiro_item_aborta_e_vira_auth_failed() {
  _write_full_config
  _write_credential
  _write_tasks_1task_1sub
  _write_map_row "demo" epic 20001 DEMO-1 active
  _write_map_row "1.1" task 20002 DEMO-2 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	*	reconcile	hook-close-wave	0	queued
EOF
  _bin="$(_init_queue_stub)"
  _queue_push 401 '{"errorMessages":["not authenticated"]}'
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" drain --feature demo || return 1

  [ "$(_queue_calls_count)" = "1" ] \
    || { _fail "sy44_calls_count" "esperado exatamente 1 chamada (sem tocar a Task), obtido $(_queue_calls_count)"; return 1; }
  awk -F '\t' '$1=="e1"' "$(_outbox_file)" | grep -q 'auth_failed$' \
    || { _fail "sy44_auth_failed" "evento e1 (*) nao virou auth_failed: $(awk -F '\t' '$1==\"e1\"' "$(_outbox_file)")"; return 1; }
  return 0
}

# SY-50 (FASE 12 tarefa 12.4.1, data-model.md LocalWorkItem outcome
# precedence / US3 cenarios 2-3): outcome `fail` de um `record_task`
# persistido via `enqueue` MUST ter precedencia sobre os checkboxes
# `[x]` (que sozinhos derivariam `pass`) na reconciliacao `local_key=*`
# seguinte — sem `--outcomes-file` em `_js_process_reconcile_event`
# (achado 12.4), a Task 1.1 (unico sub-item `[x]`) seria projetada `pass`
# e transicionada para "Done" mesmo com o outcome `fail` ja registrado
# pelo motor. O outbox gerado pelo `enqueue` de setup e sobrescrito na
# sequencia (so o evento de reconciliacao) para isolar o teste ao
# comportamento de `_js_process_reconcile_event`; o sidecar de outcomes
# (`runtime/task-outcomes.tsv`) persiste independente do outbox. Sub-task
# 1.1.1 fica deliberadamente SEM mapeamento (jira-map.tsv) para reduzir a
# fila de rede — item nao mapeado e ignorado silenciosamente pela
# reconciliacao. `--source hook-record-task` (task 13.3.1: e o UNICO source
# que grava o sidecar de outcomes — o hook real de `record_task` sempre usa
# este source, `posttooluse-jira-sync.sh` linha ~157/172).
scenario_drain_reconcile_outcome_record_task_tem_precedencia_sobre_checkboxes() {
  _write_full_config
  _write_credential
  _write_tasks_epic_task_sub_todos_pass
  _write_map_row "demo" epic 20001 DEMO-1 active
  _write_map_row "1.1" task 20002 DEMO-2 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"

  assert_exit 0 "$SCRIPT" enqueue --feature demo --local-key 1.1 --state fail --source hook-record-task >/dev/null || return 1
  [ -f "$TMPDIR_TEST/.claude/cstk-jira/runtime/task-outcomes.tsv" ] \
    || { _fail "sy50_outcomes_file_missing" "enqueue --state fail nao gravou o sidecar de outcomes"; return 1; }
  grep -q 'demo	1\.1	fail$' "$TMPDIR_TEST/.claude/cstk-jira/runtime/task-outcomes.tsv" \
    || { _fail "sy50_outcome_not_persisted" "outcome demo/1.1/fail ausente do sidecar: $(cat "$TMPDIR_TEST/.claude/cstk-jira/runtime/task-outcomes.tsv")"; return 1; }

  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	*	reconcile	hook-close-wave	0	queued
EOF

  _sha_epic=$(printf '%s' "demo" | "$IO_SCRIPT" sha256-stdin)
  _sha_task=$(printf '%s' "Titulo Qualquer" | "$IO_SCRIPT" sha256-stdin)
  _bin="$(_init_queue_stub)"
  # Epic (DEMO-1): sem a precedencia de outcome seria "pass" (unica task
  # 100% pass); COM a precedencia, a Task vira "fail" -> Epic cai para
  # "pending" (nenhuma task pass/ativa) -> ja "To Do" -> idempotente.
  _queue_push 200 '{"fields":{"summary":"demo","status":{"name":"To Do"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_epic\",\"written_status\":\"To Do\"}}"
  # Task 1.1 (DEMO-2): outcome fail -> alvo "Failed" (status_fail) -> "To
  # Do" atual diverge -> transiciona (R5/R4/R6put).
  _queue_push 200 '{"fields":{"summary":"Titulo Qualquer","status":{"name":"To Do"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_task\",\"written_status\":\"To Do\"}}"
  _queue_push 200 '{"transitions":[{"id":"31","to":{"name":"Failed"}}]}'
  _queue_push 204 ''
  _queue_push 200 ''
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" drain --feature demo || return 1

  [ "$(_queue_calls_count)" = "7" ] \
    || { _fail "sy50_calls_count" "esperado 7 chamadas (2 epic idempotente + 5 task transicao), obtido $(_queue_calls_count)"; return 1; }
  awk -F '\t' '$1=="e1"' "$(_outbox_file)" | grep -q 'done$' \
    || { _fail "sy50_event_done" "evento e1 (*) nao foi marcado done: $(awk -F '\t' '$1==\"e1\"' "$(_outbox_file)")"; return 1; }
  _task_trans=$("$IO_SCRIPT" json-get '.transition.id' < "$TMPDIR_TEST/queue-curl-body-6.json")
  [ "$_task_trans" = "31" ] \
    || { _fail "sy50_task_transition" "esperado transition.id=31 (Failed) para a Task, obtido $_task_trans — outcome fail nao teve precedencia sobre o checkbox pass"; return 1; }
  _task_marker_status=$("$IO_SCRIPT" json-get '.written_status' < "$TMPDIR_TEST/queue-curl-body-7.json")
  [ "$_task_marker_status" = "Failed" ] \
    || { _fail "sy50_task_marker_status" "esperado written_status=Failed no SyncMarker regravado da Task, obtido '$_task_marker_status'"; return 1; }
  return 0
}

# SY-66 (task 14.1.1, regressao da 13.1.1): subcomando `resolve-state-field`
# no ramo state.json aceita caminho pontuado (`execution.canonical_project`)
# — a leitura grep/sed nao rastreia nesting, entao a chave FOLHA basta para
# achar o valor no schema real (canonical_project vive sob `.execution`,
# nunca top-level). A allowlist dedicada de `--field`
# (`_js_is_valid_field_path`) recusa charset fora de `[A-Za-z0-9_.]`, `.`
# inicial/final e `..` consecutivo com exit 2, SEM tocar disco (--dir nem
# precisa existir para os casos de recusa).
scenario_resolve_state_field_json_caminho_pontuado_e_allowlist() {
  mkdir -p "$TMPDIR_TEST/statedir"
  cat > "$TMPDIR_TEST/statedir/state.json" <<'EOF'
{"schema_version":"1.0.0","execution":{"id":"x","canonical_project":"cstk"}}
EOF
  _out=$("$SCRIPT" resolve-state-field --dir "$TMPDIR_TEST/statedir" --field execution.canonical_project)
  [ "$_out" = "cstk" ] \
    || { _fail "sy66_json_dotted" "esperado 'cstk' via caminho pontuado no state.json, obtido '$_out'"; return 1; }

  assert_exit 2 "$SCRIPT" resolve-state-field --dir "$TMPDIR_TEST/statedir" --field 'execution;rm' || return 1
  assert_exit 2 "$SCRIPT" resolve-state-field --dir "$TMPDIR_TEST/statedir" --field 'execution..canonical_project' || return 1
  assert_exit 2 "$SCRIPT" resolve-state-field --dir "$TMPDIR_TEST/statedir" --field 'has space' || return 1
  assert_exit 2 "$SCRIPT" resolve-state-field --dir "$TMPDIR_TEST/statedir" --field '.execution' || return 1
  assert_exit 2 "$SCRIPT" resolve-state-field --dir "$TMPDIR_TEST/statedir" --field 'execution.' || return 1
  return 0
}

# _install_state_rw_stub_field FIELD_DOTTED VALUE -> stub de `state-rw.sh`
# que so responde ao caminho pontuado EXATO `.FIELD_DOTTED` (task 14.1.1):
# distinto de `_install_state_rw_stub` (que so casa `.current_stage`),
# prova que `_js_resolve_state_field` delega ao runtime o caminho INTEIRO
# (nao so o ultimo segmento) no ramo state.db — um stub tolerante a
# qualquer --field mascararia a regressao 13.1.1 (campo top-level errado
# `.canonical_project` continuaria "funcionando" por acidente).
_install_state_rw_stub_field() {
  _isrsf_field="$1"
  _isrsf_val="$2"
  _isrsf_scripts_dir="$TMPDIR_TEST/stubroot-field/skills/agente-00c-runtime/scripts"
  mkdir -p "$TMPDIR_TEST/stubroot-field/lib" "$_isrsf_scripts_dir"
  cat > "$_isrsf_scripts_dir/state-rw.sh" <<EOF
#!/bin/sh
[ "\$1" = "get" ] || exit 2
shift
_dir=""
_field=""
while [ "\$#" -gt 0 ]; do
  case "\$1" in
    --state-dir) _dir=\$2; shift 2 ;;
    --field) _field=\$2; shift 2 ;;
    *) shift ;;
  esac
done
[ -f "\$_dir/state.db" ] || exit 1
[ "\$_field" = ".$_isrsf_field" ] || exit 1
printf '%s\n' "$_isrsf_val"
EOF
  chmod +x "$_isrsf_scripts_dir/state-rw.sh"
  export CSTK_LIB="$TMPDIR_TEST/stubroot-field/lib"
}

# SY-67 (task 14.1.1, regressao da 13.1.1): subcomando `resolve-state-field`
# no ramo state.db delega o caminho pontuado INTEIRO ao `state-rw.sh` do
# runtime — com um stub que so responde a ".execution.canonical_project",
# pedir esse campo devolve o valor real; pedir o campo TOP-LEVEL
# ".canonical_project" (o que o hook fazia antes da 14.1.1) nao casa com o
# stub e devolve vazio, nunca um fallback inventado (Principio VI).
scenario_resolve_state_field_state_db_caminho_pontuado_via_stub() {
  mkdir -p "$TMPDIR_TEST/statedir"
  : > "$TMPDIR_TEST/statedir/state.db"
  _install_state_rw_stub_field "execution.canonical_project" "cstk"

  _out=$("$SCRIPT" resolve-state-field --dir "$TMPDIR_TEST/statedir" --field execution.canonical_project)
  [ "$_out" = "cstk" ] \
    || { _fail "sy67_db_dotted" "esperado 'cstk' via stub restrito ao caminho pontuado, obtido '$_out'"; return 1; }

  _out2=$("$SCRIPT" resolve-state-field --dir "$TMPDIR_TEST/statedir" --field canonical_project)
  [ -z "$_out2" ] \
    || { _fail "sy67_db_toplevel_empty" "campo top-level (regressao 13.1.1) deveria ser vazio — stub so responde ao pontuado — obtido '$_out2'"; return 1; }
  return 0
}

# ==== milestone resolve (r02 FASE 16 task 16.2, research.md Decision R2-1) ====
#
# SY-68 milestone_mode=off -> status=off, name= vazio
# SY-69 round ativo consistente (rounds/r01 + previous_round.round=r01)
#       -> name=<feature>-r02, kind=round
# SY-70 round divergente (previous_round.round=r03, so rounds/r01 existe)
#       -> status=unresolved (nunca chute)
# SY-71 sem round ativo, milestone_release definido (SemVer valido) ->
#       name=<release>, kind=release
# SY-72 sem round, sem milestone_release: 1o heading `## [X.Y.Z]` do
#       CHANGELOG.md -> name=<versao>, kind=release
# SY-73 sem round, sem milestone_release, CHANGELOG com `[Unreleased]` no
#       topo -> status=unresolved (nunca inventa proxima versao)
# SY-76 milestone ensure: idempotencia 10x (16.3.5) — so a 1a chamada faz
#       R12; as demais reusam o id via R13
# SY-77 milestone ensure: 400 em R12 refaz R13 UMA vez e reusa o id se
#       achar (corrida entre worktrees, 16.3.2/16.3.5)
# SY-78 milestone ensure: 403 em R12 grava state=blocked e sai exit 7, sem
#       chamada subsequente (16.3.6)
# SY-74 token de round fora do formato SEC-6 (^r[0-9]{2,}$) ->
#       status=unresolved, nunca fallback silencioso para release
# SY-75 milestone_release fora do formato SemVer -> status=unresolved

# _append_config_line KEY=VALUE -> acrescenta uma linha ao config ja escrito
# por _write_full_config (milestone_mode/milestone_release sao opcionais,
# ausentes do fixture base).
_append_config_line() {
  printf '%s\n' "$1" >> "$TMPDIR_TEST/.claude/cstk-jira/config"
}

scenario_milestone_resolve_mode_off() {
  _write_full_config
  _append_config_line "milestone_mode=off"
  cd "$TMPDIR_TEST" || return 1
  _out=$("$SCRIPT" milestone resolve --feature demo) \
    || { _fail "sy68_exit" "milestone resolve deveria sair exit 0"; return 1; }
  printf '%s\n' "$_out" | grep -qx "name=" \
    || { _fail "sy68_name" "esperado name= vazio, obtido: $_out"; return 1; }
  printf '%s\n' "$_out" | grep -qx "status=off" \
    || { _fail "sy68_status" "esperado status=off, obtido: $_out"; return 1; }
}

scenario_milestone_resolve_round_ativo_consistente() {
  _write_full_config
  cd "$TMPDIR_TEST" || return 1
  mkdir -p "$TMPDIR_TEST/.claude/feature-00c-state/demo/rounds/r01"
  cat > "$TMPDIR_TEST/.claude/feature-00c-state/demo/state.json" <<'EOF'
{"previous_round":{"round":"r01"}}
EOF
  _out=$("$SCRIPT" milestone resolve --feature demo) || { _fail "sy69_exit" "falhou"; return 1; }
  printf '%s\n' "$_out" | grep -qx "name=demo-r02" \
    || { _fail "sy69_name" "esperado name=demo-r02, obtido: $_out"; return 1; }
  printf '%s\n' "$_out" | grep -qx "kind=round" \
    || { _fail "sy69_kind" "esperado kind=round, obtido: $_out"; return 1; }
}

scenario_milestone_resolve_round_divergente_unresolved() {
  _write_full_config
  cd "$TMPDIR_TEST" || return 1
  mkdir -p "$TMPDIR_TEST/.claude/feature-00c-state/demo/rounds/r01"
  cat > "$TMPDIR_TEST/.claude/feature-00c-state/demo/state.json" <<'EOF'
{"previous_round":{"round":"r03"}}
EOF
  _out=$("$SCRIPT" milestone resolve --feature demo) || { _fail "sy70_exit" "falhou"; return 1; }
  printf '%s\n' "$_out" | grep -qx "status=unresolved" \
    || { _fail "sy70_status" "esperado status=unresolved (divergencia r03 vs 1 dir), obtido: $_out"; return 1; }
}

scenario_milestone_resolve_sem_round_release_definida() {
  _write_full_config
  _append_config_line "milestone_release=10.8.0"
  cd "$TMPDIR_TEST" || return 1
  _out=$("$SCRIPT" milestone resolve --feature demo) || { _fail "sy71_exit" "falhou"; return 1; }
  printf '%s\n' "$_out" | grep -qx "name=10.8.0" \
    || { _fail "sy71_name" "esperado name=10.8.0, obtido: $_out"; return 1; }
  printf '%s\n' "$_out" | grep -qx "kind=release" \
    || { _fail "sy71_kind" "esperado kind=release, obtido: $_out"; return 1; }
}

scenario_milestone_resolve_sem_round_changelog_heading() {
  _write_full_config
  cd "$TMPDIR_TEST" || return 1
  cat > "$TMPDIR_TEST/CHANGELOG.md" <<'EOF'
# Changelog

## [1.2.3]

- x
EOF
  _out=$("$SCRIPT" milestone resolve --feature demo) || { _fail "sy72_exit" "falhou"; return 1; }
  printf '%s\n' "$_out" | grep -qx "name=1.2.3" \
    || { _fail "sy72_name" "esperado name=1.2.3, obtido: $_out"; return 1; }
  printf '%s\n' "$_out" | grep -qx "kind=release" \
    || { _fail "sy72_kind" "esperado kind=release, obtido: $_out"; return 1; }
}

scenario_milestone_resolve_changelog_unreleased_no_topo_unresolved() {
  _write_full_config
  cd "$TMPDIR_TEST" || return 1
  cat > "$TMPDIR_TEST/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

- x

## [1.2.3]

- x
EOF
  _out=$("$SCRIPT" milestone resolve --feature demo) || { _fail "sy73_exit" "falhou"; return 1; }
  printf '%s\n' "$_out" | grep -qx "status=unresolved" \
    || { _fail "sy73_status" "esperado status=unresolved ([Unreleased] no topo nunca vira nome inventado), obtido: $_out"; return 1; }
}

scenario_milestone_resolve_round_token_fora_do_formato_unresolved() {
  _write_full_config
  cd "$TMPDIR_TEST" || return 1
  mkdir -p "$TMPDIR_TEST/.claude/feature-00c-state/demo/rounds/r01"
  cat > "$TMPDIR_TEST/.claude/feature-00c-state/demo/state.json" <<'EOF'
{"previous_round":{"round":"r1"}}
EOF
  # "r1" tem so 1 digito -> fora de ^r[0-9]{2,}$ (SEC-11) -> unresolved,
  # NUNCA cai para a regra de release (sem fallback silencioso).
  _out=$("$SCRIPT" milestone resolve --feature demo) || { _fail "sy74_exit" "falhou"; return 1; }
  printf '%s\n' "$_out" | grep -qx "status=unresolved" \
    || { _fail "sy74_status" "esperado status=unresolved (token r1 fora do formato SEC-11), obtido: $_out"; return 1; }
}

scenario_milestone_resolve_release_fora_do_semver_unresolved() {
  _write_full_config
  _append_config_line "milestone_release=nao-e-semver"
  cd "$TMPDIR_TEST" || return 1
  _out=$("$SCRIPT" milestone resolve --feature demo) || { _fail "sy75_exit" "falhou"; return 1; }
  printf '%s\n' "$_out" | grep -qx "status=unresolved" \
    || { _fail "sy75_status" "esperado status=unresolved (milestone_release fora de SemVer), obtido: $_out"; return 1; }
}

# ==== milestone ensure (r02 FASE 16 task 16.3, research.md Decision R2-3/R2-4) ====

scenario_milestone_ensure_idempotente_10x_zero_r12_apos_primeira() {
  _write_full_config
  _write_credential
  _write_round_demo_r01
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"id":"10000","key":"DEMO"}'
  _queue_push 200 '[]'
  _queue_push 201 '{"id":"30001","name":"demo-r02"}'
  _i=1
  while [ "$_i" -le 9 ]; do
    _queue_push 200 '{"id":"10000","key":"DEMO"}'
    _queue_push 200 '[{"id":"30001","name":"demo-r02"}]'
    _i=$((_i + 1))
  done

  _i=1
  while [ "$_i" -le 10 ]; do
    _out=$(PATH="$_bin:$PATH" "$SCRIPT" milestone ensure --feature demo) \
      || { _fail "sy76_exit_$_i" "milestone ensure deveria sair exit 0 na chamada $_i"; return 1; }
    printf '%s\n' "$_out" | grep -qx "status=current" \
      || { _fail "sy76_status_$_i" "esperado status=current na chamada $_i, obtido: $_out"; return 1; }
    _i=$((_i + 1))
  done

  [ "$(_queue_post_version_calls_count)" = "1" ] \
    || { _fail "sy76_r12_once" "esperado exatamente 1 chamada R12, obtido $(_queue_post_version_calls_count)"; return 1; }
  [ "$(_queue_get_versions_calls_count)" = "10" ] \
    || { _fail "sy76_r13_ten" "esperado 10 chamadas R13, obtido $(_queue_get_versions_calls_count)"; return 1; }

  _mf=$(_milestone_file)
  _ncur=$(awk -F '\t' 'NR>1 && $5=="current"' "$_mf" | wc -l | tr -d ' ')
  [ "$_ncur" = "1" ] || { _fail "sy76_single_current" "esperado 1 linha current, obtido $_ncur"; return 1; }
  grep -q '^demo-r02	round	30001	DEMO	current$' "$_mf" \
    || { _fail "sy76_row" "linha current ausente/incorreta em jira-milestones.tsv"; return 1; }
}

scenario_milestone_ensure_400_em_r12_refaz_r13_reusa_id() {
  _write_full_config
  _write_credential
  _write_round_demo_r01
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"id":"10000","key":"DEMO"}'
  _queue_push 200 '[]'
  _queue_push 400 '{"errors":{"name":"A version with this name already exists in this project."}}'
  _queue_push 200 '[{"id":"30002","name":"demo-r02"}]'

  _out=$(PATH="$_bin:$PATH" "$SCRIPT" milestone ensure --feature demo) \
    || { _fail "sy77_exit" "milestone ensure deveria sair exit 0 (corrida resolvida via releitura de R13)"; return 1; }
  printf '%s\n' "$_out" | grep -qx "status=current" \
    || { _fail "sy77_status" "esperado status=current, obtido: $_out"; return 1; }

  [ "$(_queue_post_version_calls_count)" = "1" ] \
    || { _fail "sy77_r12_once" "esperado exatamente 1 R12 (nunca repetido sem reler R13 antes), obtido $(_queue_post_version_calls_count)"; return 1; }
  [ "$(_queue_get_versions_calls_count)" = "2" ] \
    || { _fail "sy77_r13_twice" "esperado 2 chamadas R13 (inicial + releitura pos-400), obtido $(_queue_get_versions_calls_count)"; return 1; }

  grep -q '^demo-r02	round	30002	DEMO	current$' "$(_milestone_file)" \
    || { _fail "sy77_row" "linha current com id reaproveitado da releitura ausente/incorreta"; return 1; }
}

scenario_milestone_ensure_403_grava_blocked_exit7() {
  _write_full_config
  _write_credential
  _write_round_demo_r01
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"id":"10000","key":"DEMO"}'
  _queue_push 200 '[]'
  _queue_push 403 '{"errorMessages":["Forbidden"]}'

  PATH="$_bin:$PATH" assert_exit 7 "$SCRIPT" milestone ensure --feature demo || return 1
  assert_stderr_contains "Administer" || return 1

  [ "$(_queue_calls_count)" = "3" ] \
    || { _fail "sy78_no_further_calls" "esperado exatamente 3 chamadas (project+R13+R12), obtido $(_queue_calls_count)"; return 1; }

  grep -q '^demo-r02	round		DEMO	blocked$' "$(_milestone_file)" \
    || { _fail "sy78_row" "linha blocked (sem jira_version_id) ausente/incorreta"; return 1; }
}

# SY-92 (r02 FASE 22 tarefa 22.1.1/22.1.3, achado 22.1): 2a chamada de
# `ensure` apos o marco JA gravado state=blocked (mesma sequencia de sy78)
# NAO repete R13/R12 — guard local puramente sobre jira-milestones.tsv, sem
# nenhuma requisicao nova (nem sequer o GET de project.id). Mutation: remover
# o guard (22.1.1) faz esta asercao falhar (a 2a chamada voltaria a bater a
# fila da 1a e sairia do stub por fila esgotada, exit 22, nao exit 7).
scenario_milestone_ensure_blocked_repetido_zero_chamadas() {
  _write_full_config
  _write_credential
  _write_round_demo_r01
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"id":"10000","key":"DEMO"}'
  _queue_push 200 '[]'
  _queue_push 403 '{"errorMessages":["Forbidden"]}'

  PATH="$_bin:$PATH" assert_exit 7 "$SCRIPT" milestone ensure --feature demo || return 1
  [ "$(_queue_calls_count)" = "3" ] \
    || { _fail "sy92_first_calls" "esperado 3 chamadas na 1a tentativa (project+R13+R12), obtido $(_queue_calls_count)"; return 1; }

  PATH="$_bin:$PATH" assert_exit 7 "$SCRIPT" milestone ensure --feature demo || return 1
  assert_stdout_contains "status=blocked" || return 1
  assert_stderr_contains "blocked" || return 1

  [ "$(_queue_calls_count)" = "3" ] \
    || { _fail "sy92_no_new_calls" "esperado ZERO chamadas novas na 2a tentativa (total continua 3), obtido $(_queue_calls_count)"; return 1; }
}

scenario_milestone_ensure_off_e_unresolved_sem_rede() {
  _write_full_config
  _append_config_line "milestone_mode=off"
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg-inexistente"
  _bin="$(_init_queue_stub)"
  _out=$(PATH="$_bin:$PATH" "$SCRIPT" milestone ensure --feature demo) \
    || { _fail "sy79_off_exit" "milestone ensure deveria sair exit 0 (off)"; return 1; }
  printf '%s\n' "$_out" | grep -qx "status=off" \
    || { _fail "sy79_off_status" "esperado status=off, obtido: $_out"; return 1; }
  [ "$(_queue_calls_count)" = "0" ] \
    || { _fail "sy79_off_no_network" "milestone_mode=off nao deveria fazer chamadas de rede"; return 1; }
}

# ==== reconcile de marco no Epic (r02 FASE 16 task 16.4.2/16.4.3, R2-2/SEC-10) ====

# SY-80 (16.4.5): Epic criado com marco A (demo-r01, id 30001, ja `current`
# no sidecar) e reaberto com marco B (demo-r02, round seguinte via
# `_write_round_demo_r01`) — `drain` (evento reconcile) reaplica o marco via
# `update.fixVersions` add=B/remove=A (nunca acumula os dois); a Task 1.1
# (marco A gravado na criacao, NUNCA remarcada) nao recebe nenhuma chamada
# de fixVersions — so o Epic e alvo de `_js_reconcile_epic_milestone`.
scenario_drain_reconcile_epic_marco_a_para_b_update_add_remove() {
  _write_full_config
  _write_credential
  _write_round_demo_r01
  _write_tasks_epic_task_sub_todos_pass
  _write_map_row "demo" epic 20001 DEMO-1 active
  _write_map_row "1.1" task 20002 DEMO-2 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"

  # Sidecar pre-existente: marco A (demo-r01) e o `current` de uma convert
  # anterior (round r01). `milestone ensure`, ao resolver demo-r02, rebaixa
  # esta linha para `superseded` no MESMO write (jira-map.sh milestone-put) —
  # e essa transicao para `superseded` que autoriza o `remove` via SEC-10.
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  printf 'milestone_name\tmilestone_kind\tjira_version_id\tproject_key\tstate\n' \
    > "$(_milestone_file)"
  printf 'demo-r01\tround\t30001\tDEMO\tcurrent\n' >> "$(_milestone_file)"

  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	*	reconcile	hook-close-wave	0	queued
EOF

  _sha_epic=$(printf '%s' "demo" | "$IO_SCRIPT" sha256-stdin)
  _sha_task=$(printf '%s' "Titulo Qualquer" | "$IO_SCRIPT" sha256-stdin)
  _bin="$(_init_queue_stub)"
  # Epic (DEMO-1): R3, R6-GET (written_fix_version_id=30001), milestone
  # ensure (project + R13 casa demo-r02=30002 por igualdade exata, sem R12),
  # R2 update.fixVersions (remove 30001/add 30002), R5, R4, R6-PUT final.
  _queue_push 200 '{"fields":{"summary":"demo","status":{"name":"To Do"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_epic\",\"written_status\":\"To Do\",\"written_fix_version_id\":\"30001\"}}"
  _queue_push 200 '{"id":"10000","key":"DEMO"}'
  _queue_push 200 '[{"id":"30001","name":"demo-r01"},{"id":"30002","name":"demo-r02"}]'
  _queue_push 204 ''
  _queue_push 200 '{"transitions":[{"id":"21","to":{"name":"To Do"}},{"id":"31","to":{"name":"Done"}}]}'
  _queue_push 204 ''
  _queue_push 200 ''
  # Task 1.1 (DEMO-2): ja "Done" com marker batendo -> idempotente, SEM
  # nenhuma chamada de fixVersions (so o Epic e alvo de reconcile de marco).
  _queue_push 200 '{"fields":{"summary":"Titulo Qualquer","status":{"name":"Done"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_task\",\"written_status\":\"Done\"}}"

  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" drain --feature demo || return 1

  [ "$(_queue_calls_count)" = "10" ] \
    || { _fail "sy80_calls_count" "esperado 10 chamadas (8 epic com marco + 2 task idempotente), obtido $(_queue_calls_count)"; return 1; }

  _fv_ops=$("$IO_SCRIPT" json-get '.update.fixVersions | tostring' < "$TMPDIR_TEST/queue-curl-body-5.json")
  [ "$_fv_ops" = '[{"remove":{"id":"30001"}},{"add":{"id":"30002"}}]' ] \
    || { _fail "sy80_fixversions_ops" "esperado remove 30001/add 30002 (nunca os dois na fields), obtido: $_fv_ops"; return 1; }

  _final_marker_fv=$("$IO_SCRIPT" json-get '.written_fix_version_id? // "AUSENTE"' < "$TMPDIR_TEST/queue-curl-body-8.json")
  [ "$_final_marker_fv" = "30002" ] \
    || { _fail "sy80_marker_fixver" "esperado written_fix_version_id=30002 no R6 PUT final do Epic, obtido: $_final_marker_fv"; return 1; }

  # Task nunca gera corpo de escrita (idempotente, sem fixVersions).
  [ -f "$TMPDIR_TEST/queue-curl-body-9.json" ] \
    && { _fail "sy80_task_no_write" "Task 1.1 (idempotente) NAO deveria gerar corpo de escrita"; return 1; }

  grep -q '^demo-r01	round	30001	DEMO	superseded$' "$(_milestone_file)" \
    || { _fail "sy80_sidecar_superseded" "demo-r01 deveria estar superseded apos milestone ensure resolver demo-r02: $(cat "$(_milestone_file)")"; return 1; }
  grep -q '^demo-r02	round	30002	DEMO	current$' "$(_milestone_file)" \
    || { _fail "sy80_sidecar_current" "demo-r02 deveria estar current: $(cat "$(_milestone_file)")"; return 1; }
  return 0
}

# SY-81 (16.4.6, plan.md SEC-10): written_fix_version_id do marker do Epic
# (30001) NAO consta em jira-milestones.tsv (nem current nem superseded) —
# divergencia -> ConflictRecord milestone_drift e ZERO chamadas de
# update.fixVersions (nunca remocao forcada de um id que o sidecar da
# feature nao reconhece).
scenario_drain_reconcile_epic_milestone_drift_gera_conflito_sem_update() {
  _write_full_config
  _write_credential
  _write_round_demo_r01
  _write_tasks_epic_task_sub_todos_pass
  _write_map_row "demo" epic 20001 DEMO-1 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"

  # Sidecar SEM nenhuma linha para o id 30001 (marker aponta um id que o
  # sidecar da feature nunca registrou/ja esqueceu) — SEC-10 exige tratar
  # como divergencia, nunca como "pode remover".
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  printf 'milestone_name\tmilestone_kind\tjira_version_id\tproject_key\tstate\n' \
    > "$(_milestone_file)"

  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	*	reconcile	hook-close-wave	0	queued
EOF

  _sha_epic=$(printf '%s' "demo" | "$IO_SCRIPT" sha256-stdin)
  _bin="$(_init_queue_stub)"
  # Epic (DEMO-1) idempotente por STATUS (To Do local == "Done" agregado? Nao
  # — mantemos o alvo == atual para isolar a dimensao "marco" da dimensao
  # "status": aggregada pass -> status_pass=Done, entao current=Done.
  _queue_push 200 '{"fields":{"summary":"demo","status":{"name":"Done"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_epic\",\"written_status\":\"Done\",\"written_fix_version_id\":\"30001\"}}"
  _queue_push 200 '{"id":"10000","key":"DEMO"}'
  _queue_push 200 '[{"id":"30002","name":"demo-r02"}]'

  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" drain --feature demo || return 1

  [ "$(_queue_calls_count)" = "4" ] \
    || { _fail "sy81_calls_count" "esperado exatamente 4 chamadas (R3+R6GET+project+R13, ZERO update.fixVersions), obtido $(_queue_calls_count)"; return 1; }
  grep -qE '^PUT ' "$TMPDIR_TEST/queue-curl-calls.log" \
    && { _fail "sy81_no_put" "nenhuma chamada PUT deveria ocorrer (0 update.fixVersions, SEC-10)"; return 1; }

  grep -q 'demo	demo	DEMO-1	milestone_drift	pending$' "$(_conflicts_file)" \
    || { _fail "sy81_conflict_record" "ConflictRecord milestone_drift ausente/incorreto: $(cat "$(_conflicts_file)" 2>/dev/null)"; return 1; }

  # Sidecar so ganhou a linha demo-r02 (via milestone ensure) — nenhuma
  # linha para 30001 foi criada/alterada pela reconciliacao de marco.
  grep -q '^demo-r02	round	30002	DEMO	current$' "$(_milestone_file)" \
    || { _fail "sy81_sidecar_current" "demo-r02 deveria estar current: $(cat "$(_milestone_file)")"; return 1; }
  grep -q '30001' "$(_milestone_file)" \
    && { _fail "sy81_sidecar_no_30001" "sidecar nao deveria ter ganhado uma linha para 30001: $(cat "$(_milestone_file)")"; return 1; }
  return 0
}

# r02 FASE 24 tarefa 24.1.1/24.1.3 (achado 24.1): R2 PUT de
# `update.fixVersions` (marker sem written_fix_version_id, add-only)
# responde 400 — `--op R2` so classifica 401/403/429/5xx (jira-io.sh);
# 400/404/409/422 ficam em passthrough (exit 0, contracts/jira-rest.md:121)
# — sem checar `http_status`, o 400 seria tratado como sucesso e
# `written_fix_version_id=30002` gravado no marker do Epic sem o marco ter
# sido de fato aplicado (baseline falsa). Drain MUST propagar a falha (ZERO
# R6 PUT do marker do Epic) e o evento `reconcile` MUST ficar `deferred`
# (nunca `done`) enquanto o marco continua pendente.
scenario_drain_reconcile_epic_milestone_r2_400_nao_grava_baseline_falsa() {
  _write_full_config
  _write_credential
  _write_round_demo_r01
  _write_tasks_epic_task_sub_todos_pass
  _write_map_row "demo" epic 20001 DEMO-1 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	*	reconcile	hook-close-wave	0	queued
EOF
  _sha_epic=$(printf '%s' "demo" | "$IO_SCRIPT" sha256-stdin)
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"fields":{"summary":"demo","status":{"name":"Done"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_epic\",\"written_status\":\"Done\"}}"
  _queue_push 200 '{"id":"10000","key":"DEMO"}'
  _queue_push 200 '[{"id":"30002","name":"demo-r02"}]'
  _queue_push 400 '{"errorMessages":["invalid body"]}'

  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" drain --feature demo || return 1

  [ "$(_queue_calls_count)" = "5" ] \
    || { _fail "sy_milestone_400_calls" "esperado exatamente 5 chamadas (R3+R6get+R1project+R13+R2 400), obtido $(_queue_calls_count)"; return 1; }
  grep -qE '^PUT .*properties' "$TMPDIR_TEST/queue-curl-calls.log" \
    && { _fail "sy_milestone_400_no_marker_put" "R6 PUT do marker do Epic NAO deveria ocorrer (falha do R2 propagada, milestone_changed=no)"; return 1; }
  awk -F '\t' '$1=="e1"' "$(_outbox_file)" | grep -q 'deferred$' \
    || { _fail "sy_milestone_400_deferred" "evento e1 deveria ficar deferred (marco ainda pendente), obtido: $(awk -F '\t' '$1==\"e1\"' "$(_outbox_file)")"; return 1; }
  return 0
}

# r02 FASE 24 tarefa 24.1.2/24.1.3 (achado 24.1): R2 PUT de
# `update.fixVersions` do Epic falha com 403 (permission_denied, exit 7 —
# NUNCA exit 4/auth_failed, contracts/jira-rest.md). Antes de 24.1.2, o
# chamador do drain (`_jspr_new_fixver=$(_js_reconcile_epic_milestone
# ...)`) era uma atribuicao NUA sob `set -eu` — a falha do R2 abortava o
# `drain` INTEIRO no Epic, e a Task 1.1 (mapeada, precisando de uma
# transicao de status REAL) nunca chegava a ser processada. Com a guarda
# (`if ...; then :; else ec=$?; fi`), exit 7 (nao-4) so marca
# `_jspr_had_deferred=yes` — a reconciliacao de status dos DEMAIS itens
# continua normalmente (Task 1.1 transiciona de "To Do" para "Done" via
# R5/R4/R6-PUT), e SO o evento fica `deferred` (o marco do Epic, nao a
# Task, e o que ficou pendente).
scenario_drain_reconcile_epic_milestone_r2_403_preserva_reconciliacao_demais_itens() {
  _write_full_config
  _write_credential
  _write_round_demo_r01
  _write_tasks_epic_task_sub_todos_pass
  _write_map_row "demo" epic 20001 DEMO-1 active
  _write_map_row "1.1" task 20002 DEMO-2 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	*	reconcile	hook-close-wave	0	queued
EOF
  _sha_epic=$(printf '%s' "demo" | "$IO_SCRIPT" sha256-stdin)
  _sha_task=$(printf '%s' "Titulo da tarefa" | "$IO_SCRIPT" sha256-stdin)
  _bin="$(_init_queue_stub)"
  # -- Epic: R3, R6get, R1 project, R13 versions, R2 PUT (403) --
  _queue_push 200 '{"fields":{"summary":"demo","status":{"name":"Done"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_epic\",\"written_status\":\"Done\"}}"
  _queue_push 200 '{"id":"10000","key":"DEMO"}'
  _queue_push 200 '[{"id":"30002","name":"demo-r02"}]'
  _queue_push 403 '{"errorMessages":["forbidden"]}'
  # -- Task 1.1: R3 (status atual "To Do", diverge do alvo "Done"), R6get
  # marker (bate com o estado atual, sem manual_edit), R5 transitions, R4
  # executa transicao, R6 PUT regrava marker --
  _queue_push 200 '{"fields":{"summary":"Titulo da tarefa","status":{"name":"To Do"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_task\",\"written_status\":\"To Do\"}}"
  _queue_push 200 '{"transitions":[{"id":"31","to":{"name":"Done"}}]}'
  _queue_push 200 ''
  _queue_push 200 ''

  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" drain --feature demo || return 1

  [ "$(_queue_calls_count)" = "10" ] \
    || { _fail "sy_milestone_403_calls" "esperado exatamente 10 chamadas (Epic 5 + Task 5), obtido $(_queue_calls_count)"; return 1; }
  grep -qE '^PUT .*issue/DEMO-1/properties' "$TMPDIR_TEST/queue-curl-calls.log" \
    && { _fail "sy_milestone_403_epic_no_marker_put" "R6 PUT do marker do Epic NAO deveria ocorrer (falha do R2 propagada)"; return 1; }
  grep -qE '^PUT .*issue/DEMO-2/properties' "$TMPDIR_TEST/queue-curl-calls.log" \
    || { _fail "sy_milestone_403_task_marker_put" "R6 PUT do marker da Task 1.1 deveria ocorrer (reconciliacao de status preservada apesar da falha do Epic)"; return 1; }
  grep -qE '^POST .*issue/DEMO-2/transitions' "$TMPDIR_TEST/queue-curl-calls.log" \
    || { _fail "sy_milestone_403_task_transition" "R4 (transicao) da Task 1.1 deveria ocorrer (status reconciliado apesar da falha do Epic)"; return 1; }
  awk -F '\t' '$1=="e1"' "$(_outbox_file)" | grep -q 'deferred$' \
    || { _fail "sy_milestone_403_deferred" "evento e1 deveria ficar deferred (marco do Epic pendente), obtido: $(awk -F '\t' '$1==\"e1\"' "$(_outbox_file)")"; return 1; }
  return 0
}

# r02 FASE 24 tarefa 24.1.1/24.1.3 (achado 24.1): R2 PUT de
# `update.fixVersions` do Epic falha com 401 (auth_failed, exit 4
# incondicional — jira-io.sh nao distingue por `--op`). O contrato do
# cabecalho de `_js_reconcile_epic_milestone` (~1614-1633) exige repassar
# o exit code para o chamador decidir `auth_failed`; 24.1.2 honra isso:
# exit 4 => `_JSPE_BREAK=yes` => o evento vira `auth_failed` (gate FR-016,
# mesma disciplina do resto do arquivo — NENHUMA chamada nova ate
# reconfiguracao de credencial).
scenario_drain_reconcile_epic_milestone_r2_401_vira_auth_failed() {
  _write_full_config
  _write_credential
  _write_round_demo_r01
  _write_tasks_epic_task_sub_todos_pass
  _write_map_row "demo" epic 20001 DEMO-1 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	*	reconcile	hook-close-wave	0	queued
EOF
  _sha_epic=$(printf '%s' "demo" | "$IO_SCRIPT" sha256-stdin)
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"fields":{"summary":"demo","status":{"name":"Done"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_epic\",\"written_status\":\"Done\"}}"
  _queue_push 200 '{"id":"10000","key":"DEMO"}'
  _queue_push 200 '[{"id":"30002","name":"demo-r02"}]'
  _queue_push 401 '{"errorMessages":["unauthorized"]}'

  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" drain --feature demo || return 1

  [ "$(_queue_calls_count)" = "5" ] \
    || { _fail "sy_milestone_401_calls" "esperado exatamente 5 chamadas (sem retry, sem links apos auth_failed), obtido $(_queue_calls_count)"; return 1; }
  awk -F '\t' '$1=="e1"' "$(_outbox_file)" | grep -q 'auth_failed$' \
    || { _fail "sy_milestone_401_auth_failed" "evento e1 nao virou auth_failed: $(awk -F '\t' '$1==\"e1\"' "$(_outbox_file)")"; return 1; }
  return 0
}

# task 21.1.1/21.1.2 (plan.md SEC-10, achado 21.1): resolve --choice
# keep_jira de um ConflictRecord milestone_drift RE-DERIVA
# written_fix_version_id do estado REAL do Epic (fixVersions), restrito ao
# id que o sidecar reconhece (current/superseded) — nunca preserva o id
# antigo (30001, que o proprio conflito ja provou desconhecido) nem adota
# um id qualquer as cegas. Mutation (preservar o valor antigo em vez de
# re-derivar) MUST falhar este teste.
scenario_resolve_keep_jira_milestone_drift_rederiva_baseline_reconhecida() {
  _write_full_config
  _write_credential
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  printf 'milestone_name\tmilestone_kind\tjira_version_id\tproject_key\tstate\n' \
    > "$(_milestone_file)"
  printf 'demo-r02\tround\t30002\tDEMO\tcurrent\n' >> "$(_milestone_file)"
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_conflicts_file)" <<'EOF'
detected_at	feature	local_key	jira_key	reason	resolution
2026-01-01T00:00:00Z	demo	demo	DEMO-1	milestone_drift	pending
EOF
  _sha_epic=$(printf '%s' "demo" | "$IO_SCRIPT" sha256-stdin)
  _bin="$(_init_queue_stub)"
  # R3 (fields agora inclui fixVersions,labels — task 21.1.1): o Epic JA
  # tem fixVersions=30002 aplicado de fato no Jira — o drift era so no
  # MARKER (ainda apontando 30001, id que o sidecar nao reconhece mais).
  _queue_push 200 '{"fields":{"summary":"demo","status":{"name":"Done"},"fixVersions":[{"id":"30002","name":"demo-r02"}]}}'
  # R6 GET (marker atual, task 21.1.1): aponta o id antigo/desconhecido.
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_epic\",\"written_status\":\"Done\",\"written_fix_version_id\":\"30001\"}}"
  _queue_push 200 ''
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" resolve --feature demo --local-key demo --choice keep_jira || return 1
  grep -q 'demo	demo	DEMO-1	milestone_drift	keep_jira$' "$(_conflicts_file)" \
    || { _fail "sy_msdrift_resolution" "resolution nao virou keep_jira: $(cat "$(_conflicts_file)")"; return 1; }
  _final_fv=$("$IO_SCRIPT" json-get '.written_fix_version_id? // "AUSENTE"' < "$TMPDIR_TEST/queue-curl-body-3.json")
  [ "$_final_fv" = "30002" ] \
    || { _fail "sy_msdrift_rederiva" "written_fix_version_id deveria ser re-derivado para 30002 (id reconhecido pelo sidecar como current), obtido: $_final_fv"; return 1; }
  return 0
}

# task 21.1.1/21.1.2: apos keep_jira re-derivar a baseline (teste
# anterior), o PROXIMO drain (evento reconcile) NAO reabre o
# milestone_drift nem emite update.fixVersions algum — o marker agora bate
# exatamente o unico marco `current` do sidecar (idempotente). Mutation
# (nao preservar/re-derivar corretamente) reabriria o conflito ou geraria
# um `add` sem o `remove` correspondente (SEC-10) — este teste MUST falhar
# nesse caso.
scenario_resolve_keep_jira_milestone_drift_drain_seguinte_idempotente_sem_reabrir() {
  _write_full_config
  _write_credential
  _write_round_demo_r01
  _write_tasks_epic_task_sub_todos_pass
  _write_map_row "demo" epic 20001 DEMO-1 active
  _write_map_row "1.1" task 20002 DEMO-2 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  printf 'milestone_name\tmilestone_kind\tjira_version_id\tproject_key\tstate\n' \
    > "$(_milestone_file)"
  printf 'demo-r02\tround\t30002\tDEMO\tcurrent\n' >> "$(_milestone_file)"
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_conflicts_file)" <<'EOF'
detected_at	feature	local_key	jira_key	reason	resolution
2026-01-01T00:00:00Z	demo	demo	DEMO-1	milestone_drift	pending
EOF
  _sha_epic=$(printf '%s' "demo" | "$IO_SCRIPT" sha256-stdin)
  _sha_task=$(printf '%s' "Titulo Qualquer" | "$IO_SCRIPT" sha256-stdin)
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"fields":{"summary":"demo","status":{"name":"Done"},"fixVersions":[{"id":"30002","name":"demo-r02"}]}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_epic\",\"written_status\":\"Done\",\"written_fix_version_id\":\"30001\"}}"
  _queue_push 200 ''
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" resolve --feature demo --local-key demo --choice keep_jira || return 1

  # Le de VOLTA o que o resolve de fato gravou no R6 PUT (body-3.json) —
  # NUNCA hardcoded — para que uma mutation que quebre a re-derivacao
  # (ex.: voltar a preservar o 30001 antigo) se propague ao marker "atual"
  # do proximo drain e este teste FALHE (mutation: preservar em vez de
  # re-derivar MUST falhar este teste via _pending_count abaixo).
  _fv_apos_resolve=$("$IO_SCRIPT" json-get '.written_fix_version_id? // ""' < "$TMPDIR_TEST/queue-curl-body-3.json")

  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:01:00Z	demo	*	reconcile	hook-close-wave	0	queued
EOF
  # Proximo drain: Epic com written_fix_version_id = o que o resolve
  # realmente gravou. Com o codigo correto (30002, re-derivado e
  # reconhecido) a reconciliacao e idempotente (ZERO update.fixVersions).
  _queue_push 200 '{"fields":{"summary":"demo","status":{"name":"Done"},"fixVersions":[{"id":"30002","name":"demo-r02"}]}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_epic\",\"written_status\":\"Done\",\"written_fix_version_id\":\"$_fv_apos_resolve\"}}"
  _queue_push 200 '{"id":"10000","key":"DEMO"}'
  _queue_push 200 '[{"id":"30002","name":"demo-r02"}]'
  # Task 1.1 idempotente (ja Done, marker batendo, sem written_phase_label).
  _queue_push 200 '{"fields":{"summary":"Titulo Qualquer","status":{"name":"Done"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_task\",\"written_status\":\"Done\"}}"

  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" drain --feature demo || return 1

  [ "$(_queue_calls_count)" = "9" ] \
    || { _fail "sy_msdrift_drain_calls" "esperado 9 chamadas (3 resolve + 4 epic idempotente + 2 task idempotente), obtido $(_queue_calls_count)"; return 1; }
  for _n in 4 5 6 7 8 9; do
    [ -f "$TMPDIR_TEST/queue-curl-body-$_n.json" ] \
      && { _fail "sy_msdrift_drain_no_write" "chamada #$_n do drain gerou corpo de escrita — deveria ser idempotente (so GET), obtido: $(cat "$TMPDIR_TEST/queue-curl-body-$_n.json")"; return 1; }
  done
  _pending_count=$(awk -F '\t' 'NR>1 && $2=="demo" && $3=="demo" && $6=="pending"' "$(_conflicts_file)" | wc -l | tr -d ' ')
  [ "$_pending_count" = "0" ] \
    || { _fail "sy_msdrift_no_new_conflict" "milestone_drift nao deveria reabrir apos a baseline re-derivada: $(cat "$(_conflicts_file)")"; return 1; }
  return 0
}

# =========================== convert: labels de FASE (r02 FASE 17 task 17.2) ====
#
# SY-82 convert (labels_enabled=on, default): task da FASE 1 recebe
#       fields.labels:["phase-1"]; sub-task herda o mesmo label da task-pai
#       (mesmo phase_number); Epic NUNCA recebe fields.labels; o marker
#       inicial (R6 PUT) da task/sub-task grava written_phase_label.
# SY-83 convert (labels_enabled=off): nenhuma chamada de criacao (Epic/
#       Task/Sub-task) tem a chave fields.labels; marker inicial NUNCA
#       grava written_phase_label.

scenario_convert_labels_enabled_task_e_subtask_recebem_phase_label() {
  _write_full_config
  _write_tasks_1task_1sub_sem_crit
  _write_credential
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"accountId":"acc-1"}'
  _queue_push 200 '{"id":"10000","key":"DEMO"}'
  # Epic: R1 create + R3 + R6 PUT marker inicial
  _queue_push 201 '{"id":"20001","key":"DEMO-1"}'
  _queue_push 200 '{"fields":{"status":{"name":"To Do"}}}'
  _queue_push 201 ''
  # Task: idem
  _queue_push 201 '{"id":"20002","key":"DEMO-2"}'
  _queue_push 200 '{"fields":{"status":{"name":"To Do"}}}'
  _queue_push 201 ''
  # Sub-task: idem
  _queue_push 201 '{"id":"20003","key":"DEMO-3"}'
  _queue_push 200 '{"fields":{"status":{"name":"To Do"}}}'
  _queue_push 201 ''
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" convert --feature demo || return 1

  # chamada 3 = R1 do Epic: NUNCA tem fields.labels
  _epic_has_labels=$("$IO_SCRIPT" json-get '.fields | has("labels")' < "$TMPDIR_TEST/queue-curl-body-3.json")
  [ "$_epic_has_labels" = "false" ] \
    || { _fail "sy82_epic_sem_labels" "Epic NUNCA deveria receber fields.labels"; return 1; }

  # chamada 6 = R1 da task: fields.labels == ["phase-1"] (FASE 1)
  _task_labels=$("$IO_SCRIPT" json-get '.fields.labels | join(",")' < "$TMPDIR_TEST/queue-curl-body-6.json")
  [ "$_task_labels" = "phase-1" ] \
    || { _fail "sy82_task_label" "esperado phase-1, obtido $_task_labels"; return 1; }
  _task_labels_n=$("$IO_SCRIPT" json-get '.fields.labels | length' < "$TMPDIR_TEST/queue-curl-body-6.json")
  [ "$_task_labels_n" = "1" ] \
    || { _fail "sy82_task_label_n" "esperado 1 label, obtido $_task_labels_n"; return 1; }

  # chamada 9 = R1 da sub-task: mesma label (herdada da task-pai)
  _sub_labels=$("$IO_SCRIPT" json-get '.fields.labels | join(",")' < "$TMPDIR_TEST/queue-curl-body-9.json")
  [ "$_sub_labels" = "phase-1" ] \
    || { _fail "sy82_sub_label" "esperado phase-1 (herdado da task-pai), obtido $_sub_labels"; return 1; }

  # chamada 8 = R6 PUT do marker inicial da task: written_phase_label
  _task_marker_label=$("$IO_SCRIPT" json-get '.written_phase_label' < "$TMPDIR_TEST/queue-curl-body-8.json")
  [ "$_task_marker_label" = "phase-1" ] \
    || { _fail "sy82_task_marker_label" "esperado written_phase_label=phase-1, obtido $_task_marker_label"; return 1; }
  return 0
}

scenario_convert_labels_enabled_off_nenhuma_chamada_com_label() {
  _write_full_config_labels_off
  _write_tasks_1task_1sub_sem_crit
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
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" convert --feature demo || return 1

  for _n in 3 6 9; do
    _has=$("$IO_SCRIPT" json-get '.fields | has("labels")' < "$TMPDIR_TEST/queue-curl-body-$_n.json")
    [ "$_has" = "false" ] \
      || { _fail "sy83_sem_labels_$_n" "chamada $_n nao deveria ter fields.labels (labels_enabled=off)"; return 1; }
  done

  # chamada 8 = R6 PUT do marker inicial da task: NUNCA written_phase_label
  _task_marker_has_label=$("$IO_SCRIPT" json-get 'has("written_phase_label")' < "$TMPDIR_TEST/queue-curl-body-8.json")
  [ "$_task_marker_has_label" = "false" ] \
    || { _fail "sy83_marker_sem_label" "marker nao deveria ter written_phase_label (labels_enabled=off)"; return 1; }
  return 0
}

# _write_tasks_fase5_1task_1sub_pass: task 1.1 vive sob "## FASE 5" (nao
# FASE 1) — usado pelos cenarios de reconciliacao de troca de fase (r02
# FASE 17 task 17.3). O `written_phase_label` "antigo" (ex.: phase-3) e
# controlado pela fixture do MARKER de cada cenario, nao pelo heading —
# aqui so se fixa o phase_number LOCAL atual (5).
_write_tasks_fase5_1task_1sub_pass() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cat > "$TMPDIR_TEST/docs/specs/demo/tasks.md" <<'EOF'
## FASE 5 - Sincronizacao `[A]`

### 1.1 Titulo da tarefa `[A]`

- [x] 1.1.1 Sub um
EOF
}

# SY-84 drain reconcile (r02 FASE 17 task 17.3.1/17.3.4, plan.md SEC-10):
# task 1.1 tem written_phase_label=phase-3 no marker (fase anterior) mas
# vive agora sob FASE 5 (phase_number local=5) -> update.labels
# remove=phase-3/add=phase-5; o label humano extra (prioridade-alta) SEGUE
# na issue (a operacao so referencia os 2 valores phase-N, nunca substitui
# o array inteiro) — a leitura via R15 (extensao de R3) confirma que
# phase-3 AINDA esta la antes de remover (17.3.3). Epic (sem phase_label,
# 17.2.1) fica idempotente (status bate, marco `auto` sem round ->
# unresolved, zero chamadas extras) — so a Task gera trafego de label.
scenario_drain_reconcile_phase_label_troca_de_fase_update_add_remove() {
  _write_full_config
  _write_credential
  _write_tasks_fase5_1task_1sub_pass
  _write_map_row "demo" epic 20001 DEMO-1 active
  _write_map_row "1.1" task 20002 DEMO-2 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"

  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	*	reconcile	hook-close-wave	0	queued
EOF

  _sha_epic=$(printf '%s' "demo" | "$IO_SCRIPT" sha256-stdin)
  _sha_task=$(printf '%s' "Titulo da tarefa" | "$IO_SCRIPT" sha256-stdin)
  _bin="$(_init_queue_stub)"
  # Epic (DEMO-1): R3 + R6-GET, ja "Done" com marker batendo, marco `auto`
  # sem round -> unresolved (0 chamadas) -> idempotente puro.
  _queue_push 200 '{"fields":{"summary":"demo","status":{"name":"Done"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_epic\",\"written_status\":\"Done\"}}"
  # Task (DEMO-2): R3 + R6-GET (written_phase_label=phase-3), R15 (labels
  # atuais: phase-3 + humano prioridade-alta), R2 (update.labels
  # remove/add), R6-PUT final (written_phase_label=phase-5).
  _queue_push 200 '{"fields":{"summary":"Titulo da tarefa","status":{"name":"Done"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_task\",\"written_status\":\"Done\",\"written_phase_label\":\"phase-3\"}}"
  _queue_push 200 '{"fields":{"labels":["phase-3","prioridade-alta"]}}'
  _queue_push 204 ''
  _queue_push 200 ''

  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" drain --feature demo || return 1

  [ "$(_queue_calls_count)" = "7" ] \
    || { _fail "sy84_calls_count" "esperado 7 chamadas (2 epic idempotente + 5 task: R3/R6get/R15/R2/R6put), obtido $(_queue_calls_count)"; return 1; }

  _lbl_ops=$("$IO_SCRIPT" json-get '.update.labels | tostring' < "$TMPDIR_TEST/queue-curl-body-6.json")
  [ "$_lbl_ops" = '[{"remove":"phase-3"},{"add":"phase-5"}]' ] \
    || { _fail "sy84_label_ops" "esperado remove phase-3/add phase-5, obtido: $_lbl_ops"; return 1; }

  _lbl_ops_has_human=$("$IO_SCRIPT" json-get '.update.labels | tostring | contains("prioridade-alta")' < "$TMPDIR_TEST/queue-curl-body-6.json")
  [ "$_lbl_ops_has_human" = "false" ] \
    || { _fail "sy84_human_label_intocado" "update.labels NUNCA deveria referenciar o label humano prioridade-alta"; return 1; }

  _final_marker_label=$("$IO_SCRIPT" json-get '.written_phase_label? // "AUSENTE"' < "$TMPDIR_TEST/queue-curl-body-7.json")
  [ "$_final_marker_label" = "phase-5" ] \
    || { _fail "sy84_marker_label" "esperado written_phase_label=phase-5 no R6 PUT final, obtido: $_final_marker_label"; return 1; }
  return 0
}

# r02 FASE 23 tarefa 23.1.1 (achado 23.1 + regressao correlata, script roda
# sob `set -eu`): mesmo cenario de troca de fase de sy84 acima, mas o R2 PUT
# (update.labels) falha com 403. Antes desta tarefa, `_js_reconcile_phase_
# label` sempre devolvia exit 0 (o proprio bug 23.1) — o chamador do drain
# (`_jspr_new_phase_label=$(_js_reconcile_phase_label ...)`, SEM guarda)
# nunca via uma falha genuina. Corrigido o exit code na propria funcao
# (23.1.1), esta atribuicao NUA sob `set -eu` abortaria o `drain` INTEIRO
# ao primeiro R2 que falhasse (medido: `sh -c 'set -eu; f(){ return 7; };
# x=$(f); echo sobrevivi'` nunca imprime "sobrevivi") — uma regressao BEM
# pior que o bug original. Este teste MUST continuar vendo `drain` sair 0
# (a falha e absorvida, o item so nao muda de fase nesta passada, sem
# nenhum R6 PUT do marker) — mutation (remover o guard `if cmd; then :;
# else ...; fi` ao redor da chamada, voltando a atribuicao nua) MUST falhar
# este teste (drain sairia com o exit code do R2, 7, em vez de 0).
#
# r02 FASE 25 tarefa 25.1.1/25.1.2 (achado 25.1): ate aqui o `else` so
# restaurava WRITTEN e nao classificava o exit code — o evento `e1` fechava
# `done` mesmo com o R2 de labels tendo falhado com 403 (permissao
# insuficiente), quando deveria ficar `deferred` (mesma convencao do marco
# do Epic, task 24.1). A asserção de status abaixo cobre a correcao;
# mutation (voltar o `else` a so restaurar WRITTEN, sem classificar) MUST
# falhar esta asercao.
scenario_drain_reconcile_phase_label_r2_403_nao_aborta_drain_inteiro() {
  _write_full_config
  _write_credential
  _write_tasks_fase5_1task_1sub_pass
  _write_map_row "demo" epic 20001 DEMO-1 active
  _write_map_row "1.1" task 20002 DEMO-2 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"

  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	*	reconcile	hook-close-wave	0	queued
EOF

  _sha_epic=$(printf '%s' "demo" | "$IO_SCRIPT" sha256-stdin)
  _sha_task=$(printf '%s' "Titulo da tarefa" | "$IO_SCRIPT" sha256-stdin)
  _bin="$(_init_queue_stub)"
  # Epic (DEMO-1): idempotente puro (2 chamadas), igual a sy84.
  _queue_push 200 '{"fields":{"summary":"demo","status":{"name":"Done"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_epic\",\"written_status\":\"Done\"}}"
  # Task (DEMO-2): R3 + R6-GET (written_phase_label=phase-3) + R15 (labels
  # atuais: phase-3 + humano) -- ate aqui identico a sy84.
  _queue_push 200 '{"fields":{"summary":"Titulo da tarefa","status":{"name":"Done"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_task\",\"written_status\":\"Done\",\"written_phase_label\":\"phase-3\"}}"
  _queue_push 200 '{"fields":{"labels":["phase-3","prioridade-alta"]}}'
  # R2 (update.labels remove/add) falha com 403 -- permissao insuficiente.
  _queue_push 403 '{"errorMessages":["forbidden"]}'

  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" drain --feature demo || return 1

  [ "$(_queue_calls_count)" = "6" ] \
    || { _fail "sy_drain_r2_403_calls" "esperado 6 chamadas (2 epic idempotente + 4 task: R3/R6get/R15/R2-403, SEM R6-PUT), obtido $(_queue_calls_count)"; return 1; }
  grep -qE '^PUT .*properties' "$TMPDIR_TEST/queue-curl-calls.log" \
    && { _fail "sy_drain_r2_403_no_marker_put" "R6 PUT do marker NAO deveria ocorrer apos falha do R2 (fase nao mudou nesta passada)"; return 1; }
  awk -F '\t' '$1=="e1"' "$(_outbox_file)" | grep -q 'deferred$' \
    || { _fail "sy_drain_r2_403_deferred" "evento e1 deveria ficar deferred (label pendente, achado 25.1), obtido: $(awk -F '\t' '$1==\"e1\"' "$(_outbox_file)")"; return 1; }
  return 0
}

# r02 FASE 25 tarefa 25.1.1/25.1.2 (achado 25.1): mesmo cenario acima, mas o
# R2 PUT (update.labels) falha com 401 — credencial rejeitada. Antes da
# 25.1.1, o `else` do chamador nunca via o exit code: o evento `e1` fechava
# `done` com a credencial invalida ja descartada silenciosamente (FR-016
# violado). Corrigido, exit 4 => `_JSPE_BREAK=yes` + `break` (mesma
# convencao do marco do Epic, task 24.1.2): nenhuma chamada nova ocorre
# apos o R2, e o evento vira `auth_failed`. Mutation (remover a
# classificacao do `else`, deixando so o fallback de WRITTEN) MUST falhar
# este teste (evento fecharia `done` em vez de `auth_failed`).
scenario_drain_reconcile_phase_label_r2_401_vira_auth_failed() {
  _write_full_config
  _write_credential
  _write_tasks_fase5_1task_1sub_pass
  _write_map_row "demo" epic 20001 DEMO-1 active
  _write_map_row "1.1" task 20002 DEMO-2 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"

  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	*	reconcile	hook-close-wave	0	queued
EOF

  _sha_epic=$(printf '%s' "demo" | "$IO_SCRIPT" sha256-stdin)
  _sha_task=$(printf '%s' "Titulo da tarefa" | "$IO_SCRIPT" sha256-stdin)
  _bin="$(_init_queue_stub)"
  # Epic (DEMO-1): idempotente puro (2 chamadas), igual ao cenario 403.
  _queue_push 200 '{"fields":{"summary":"demo","status":{"name":"Done"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_epic\",\"written_status\":\"Done\"}}"
  # Task (DEMO-2): R3 + R6-GET (written_phase_label=phase-3) + R15 (labels
  # atuais: phase-3 + humano) -- ate aqui identico ao cenario 403.
  _queue_push 200 '{"fields":{"summary":"Titulo da tarefa","status":{"name":"Done"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_task\",\"written_status\":\"Done\",\"written_phase_label\":\"phase-3\"}}"
  _queue_push 200 '{"fields":{"labels":["phase-3","prioridade-alta"]}}'
  # R2 (update.labels remove/add) falha com 401 -- credencial rejeitada.
  _queue_push 401 '{"errorMessages":["unauthorized"]}'

  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" drain --feature demo || return 1

  [ "$(_queue_calls_count)" = "6" ] \
    || { _fail "sy_drain_r2_401_calls" "esperado exatamente 6 chamadas (sem retry, sem links apos auth_failed), obtido $(_queue_calls_count)"; return 1; }
  grep -qE '^PUT .*properties' "$TMPDIR_TEST/queue-curl-calls.log" \
    && { _fail "sy_drain_r2_401_no_marker_put" "R6 PUT do marker NAO deveria ocorrer apos falha do R2 (auth_failed)"; return 1; }
  awk -F '\t' '$1=="e1"' "$(_outbox_file)" | grep -q 'auth_failed$' \
    || { _fail "sy_drain_r2_401_auth_failed" "evento e1 nao virou auth_failed: $(awk -F '\t' '$1==\"e1\"' "$(_outbox_file)")"; return 1; }
  return 0
}

# SY-85 drain reconcile (r02 FASE 17 task 17.3.3, plan.md SEC-10):
# written_phase_label do marker (phase-3) NAO consta mais nos labels REAIS
# da issue (R15 devolve so phase-9 — alguem removeu/trocou manualmente) ->
# ConflictRecord reason=label_drift e ZERO chamadas de update.labels (nunca
# reaplicacao forcada por cima de um drift nao detectado).
scenario_drain_reconcile_phase_label_drift_gera_conflito_sem_update() {
  _write_full_config
  _write_credential
  _write_tasks_fase5_1task_1sub_pass
  _write_map_row "demo" epic 20001 DEMO-1 active
  _write_map_row "1.1" task 20002 DEMO-2 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"

  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:00:00Z	demo	*	reconcile	hook-close-wave	0	queued
EOF

  _sha_epic=$(printf '%s' "demo" | "$IO_SCRIPT" sha256-stdin)
  _sha_task=$(printf '%s' "Titulo da tarefa" | "$IO_SCRIPT" sha256-stdin)
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"fields":{"summary":"demo","status":{"name":"Done"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_epic\",\"written_status\":\"Done\"}}"
  _queue_push 200 '{"fields":{"summary":"Titulo da tarefa","status":{"name":"Done"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_task\",\"written_status\":\"Done\",\"written_phase_label\":\"phase-3\"}}"
  _queue_push 200 '{"fields":{"labels":["phase-9"]}}'

  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" drain --feature demo || return 1

  [ "$(_queue_calls_count)" = "5" ] \
    || { _fail "sy85_calls_count" "esperado 5 chamadas (2 epic + 3 task: R3/R6get/R15, ZERO update.labels), obtido $(_queue_calls_count)"; return 1; }
  grep -qE '^PUT ' "$TMPDIR_TEST/queue-curl-calls.log" \
    && { _fail "sy85_no_put" "nenhuma chamada PUT deveria ocorrer (0 update.labels, SEC-10/17.3.3)"; return 1; }

  grep -q 'demo	1.1	DEMO-2	label_drift	pending$' "$(_conflicts_file)" \
    || { _fail "sy85_conflict_record" "ConflictRecord label_drift ausente/incorreto: $(cat "$(_conflicts_file)" 2>/dev/null)"; return 1; }
  return 0
}

# task 21.1.1/21.1.2 (plan.md SEC-10, achado 21.1): resolve --choice
# keep_jira de um ConflictRecord label_drift RE-DERIVA written_phase_label
# do estado REAL da issue (labels atuais), restrito a um label casando
# `^phase-[0-9]+$` — nunca preserva o label antigo (phase-3, que o proprio
# conflito ja provou ausente da issue). Com a baseline corrigida, a
# reconciliacao de troca de FASE (R2-5) volta a funcionar no PROXIMO
# drain — antes do fix (achado 21.1), written_phase_label ficava vazio
# para sempre apos QUALQUER resolve, desligando R2-5 em silencio.
# Mutation (apagar/nao re-derivar written_phase_label) MUST falhar este
# teste.
scenario_resolve_keep_jira_label_drift_rederiva_e_drain_seguinte_reconcilia_fase() {
  _write_full_config
  _write_credential
  _write_tasks_fase5_1task_1sub_pass
  _write_map_row "demo" epic 20001 DEMO-1 active
  _write_map_row "1.1" task 20002 DEMO-2 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_conflicts_file)" <<'EOF'
detected_at	feature	local_key	jira_key	reason	resolution
2026-01-01T00:00:00Z	demo	1.1	DEMO-2	label_drift	pending
EOF
  _sha_task=$(printf '%s' "Titulo da tarefa" | "$IO_SCRIPT" sha256-stdin)
  _bin="$(_init_queue_stub)"
  # R3 (fields agora inclui fixVersions,labels — task 21.1.1): labels REAIS
  # da issue ja mudaram para phase-9 (a propria causa do drift original).
  _queue_push 200 '{"fields":{"summary":"Titulo da tarefa","status":{"name":"Done"},"labels":["phase-9"]}}'
  # R6 GET (marker atual, task 21.1.1): ainda aponta o label antigo (phase-3).
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_task\",\"written_status\":\"Done\",\"written_phase_label\":\"phase-3\"}}"
  _queue_push 200 ''
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" resolve --feature demo --local-key 1.1 --choice keep_jira || return 1
  grep -q 'demo	1.1	DEMO-2	label_drift	keep_jira$' "$(_conflicts_file)" \
    || { _fail "sy_labeldrift_resolution" "resolution nao virou keep_jira: $(cat "$(_conflicts_file)")"; return 1; }
  _final_label=$("$IO_SCRIPT" json-get '.written_phase_label? // "AUSENTE"' < "$TMPDIR_TEST/queue-curl-body-3.json")
  [ "$_final_label" = "phase-9" ] \
    || { _fail "sy_labeldrift_rederiva" "written_phase_label deveria ser re-derivado para phase-9 (label atual da issue, casando ^phase-N), obtido: $_final_label"; return 1; }

  # Proximo drain: a task continua sob FASE 5 (target=phase-5) — com a
  # baseline corrigida (phase-9), R2-5 volta a reconciliar: remove
  # phase-9/add phase-5.
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:01:00Z	demo	*	reconcile	hook-close-wave	0	queued
EOF
  _sha_epic=$(printf '%s' "demo" | "$IO_SCRIPT" sha256-stdin)
  # Epic: marco `auto` sem round -> unresolved, idempotente puro (2 chamadas).
  _queue_push 200 '{"fields":{"summary":"demo","status":{"name":"Done"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_epic\",\"written_status\":\"Done\"}}"
  # Task: R3 + R6-GET (written_phase_label=phase-9, ja rebaselinado) + R15
  # (labels atuais: phase-9) + R2 (update.labels remove/add) + R6-PUT final.
  _queue_push 200 '{"fields":{"summary":"Titulo da tarefa","status":{"name":"Done"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_task\",\"written_status\":\"Done\",\"written_phase_label\":\"phase-9\"}}"
  _queue_push 200 '{"fields":{"labels":["phase-9"]}}'
  _queue_push 204 ''
  _queue_push 200 ''
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" drain --feature demo || return 1

  [ "$(_queue_calls_count)" = "10" ] \
    || { _fail "sy_labeldrift_drain_calls" "esperado 10 chamadas (3 resolve + 2 epic idempotente + 5 task: R3/R6get/R15/R2/R6put), obtido $(_queue_calls_count)"; return 1; }
  _lbl_ops=$("$IO_SCRIPT" json-get '.update.labels | tostring' < "$TMPDIR_TEST/queue-curl-body-9.json")
  [ "$_lbl_ops" = '[{"remove":"phase-9"},{"add":"phase-5"}]' ] \
    || { _fail "sy_labeldrift_reconcile" "esperado remove phase-9/add phase-5 (reconciliacao de fase reativada apos o fix), obtido: $_lbl_ops"; return 1; }
  _final_label2=$("$IO_SCRIPT" json-get '.written_phase_label? // "AUSENTE"' < "$TMPDIR_TEST/queue-curl-body-10.json")
  [ "$_final_label2" = "phase-5" ] \
    || { _fail "sy_labeldrift_marker_final" "esperado written_phase_label=phase-5 no R6 PUT final, obtido: $_final_label2"; return 1; }
  return 0
}

# r02 FASE 22 tarefa 22.2.1/22.2.2 (achado 22.2, ciclo 2): resolve --choice
# overwrite de um ConflictRecord label_drift onde a issue NAO tem NENHUM
# label phase-* (o humano removeu phase-<N> sem substituir por outro) MUST
# reaplicar phase-<N> da FASE LOCAL ATUAL (FASE 5,
# _write_tasks_fase5_1task_1sub_pass) via update.labels SO `add` — nunca
# ficar com baseline vazia (isso deixaria overwrite com o MESMO efeito de
# keep_jira, o proprio achado 22.2). O R3 do rebaseline aqui NUNCA e
# reaproveitado para o label (WRITTEN="" faz `_js_reconcile_phase_label`
# pular seu proprio R3/R15 e ir direto ao R2 PUT de `add`). Mutation
# (voltar a re-derivar do estado real da issue, como keep_jira) MUST falhar
# esta asercao (nenhuma chamada R2 ocorreria, written_phase_label ficaria
# vazio).
scenario_resolve_overwrite_label_drift_sem_phase_reaplica_fase_local() {
  _write_full_config
  _write_credential
  _write_tasks_fase5_1task_1sub_pass
  _write_map_row "demo" epic 20001 DEMO-1 active
  _write_map_row "1.1" task 20002 DEMO-2 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_conflicts_file)" <<'EOF'
detected_at	feature	local_key	jira_key	reason	resolution
2026-01-01T00:00:00Z	demo	1.1	DEMO-2	label_drift	pending
EOF
  _sha_task=$(printf '%s' "Titulo da tarefa" | "$IO_SCRIPT" sha256-stdin)
  _bin="$(_init_queue_stub)"
  # R3 do rebaseline: issue SEM nenhum label phase-* (so um label humano).
  _queue_push 200 '{"fields":{"summary":"Titulo da tarefa","status":{"name":"Done"},"labels":["prioridade-alta"]}}'
  # R6 GET (marker atual, sempre lido ANTES do PUT — task 21.1.1); o
  # written_phase_label antigo (phase-3) e irrelevante aqui: REASON=
  # label_drift + choice=overwrite forca WRITTEN="" incondicionalmente.
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_task\",\"written_status\":\"Done\",\"written_phase_label\":\"phase-3\"}}"
  # R2 (update.labels, so add — via _js_reconcile_phase_label com WRITTEN="").
  _queue_push 204 ''
  # R6 PUT do marker rebaselinado.
  _queue_push 200 ''
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" resolve --feature demo --local-key 1.1 --choice overwrite || return 1

  grep -q 'demo	1\.1	DEMO-2	label_drift	overwrite$' "$(_conflicts_file)" \
    || { _fail "sy93_resolution" "resolution nao virou overwrite: $(cat "$(_conflicts_file)")"; return 1; }

  [ "$(_queue_calls_count)" = "4" ] \
    || { _fail "sy93_calls" "esperado 4 chamadas (R3 + R6get marker + R2 label add + R6 marker), obtido $(_queue_calls_count)"; return 1; }

  _lbl_ops=$("$IO_SCRIPT" json-get '.update.labels | tostring' < "$TMPDIR_TEST/queue-curl-body-3.json")
  [ "$_lbl_ops" = '[{"add":"phase-5"}]' ] \
    || { _fail "sy93_label_add_only" "esperado SO add phase-5 (sem remove, label humano intocado), obtido: $_lbl_ops"; return 1; }

  _final_label=$("$IO_SCRIPT" json-get '.written_phase_label? // "AUSENTE"' < "$TMPDIR_TEST/queue-curl-body-4.json")
  [ "$_final_label" = "phase-5" ] \
    || { _fail "sy93_marker_label" "esperado written_phase_label=phase-5 no marker rebaselinado, obtido: $_final_label"; return 1; }

  # drain seguinte: item ja com written_phase_label=phase-5 e phase_num
  # alvo=5 -> reconciliacao no-op idempotente (0 R15/R2/R6put novos); status
  # ja "Done" (local_state=pass) -> nem R6-PUT de status.
  cat > "$(_outbox_file)" <<'EOF'
event_id	created_at	feature	local_key	desired_state	source	attempts	status
e1	2026-01-01T00:01:00Z	demo	*	reconcile	hook-close-wave	0	queued
EOF
  _sha_epic=$(printf '%s' "demo" | "$IO_SCRIPT" sha256-stdin)
  _queue_push 200 '{"fields":{"summary":"demo","status":{"name":"Done"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_epic\",\"written_status\":\"Done\"}}"
  _queue_push 200 '{"fields":{"summary":"Titulo da tarefa","status":{"name":"Done"}}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_task\",\"written_status\":\"Done\",\"written_phase_label\":\"phase-5\"}}"
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" drain --feature demo || return 1

  [ "$(_queue_calls_count)" = "8" ] \
    || { _fail "sy93_drain_idempotent" "drain seguinte deveria ser idempotente (2 epic + 2 task: so R3/R6get, sem R15/R2/R6put), obtido $(_queue_calls_count)"; return 1; }
  return 0
}

# task 21.1.1 (achado 21.1, ciclo 1 desta FASE — regressao): resolve
# --choice keep_jira do MESMO cenario (issue sem nenhum phase-*) continua
# com baseline VAZIA (re-derivacao do estado real, nunca reaplicacao) —
# so `overwrite` (acima) ganhou o comportamento novo de 22.2.1.
scenario_resolve_keep_jira_label_drift_sem_phase_baseline_vazia() {
  _write_full_config
  _write_credential
  _write_tasks_fase5_1task_1sub_pass
  _write_map_row "demo" epic 20001 DEMO-1 active
  _write_map_row "1.1" task 20002 DEMO-2 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_conflicts_file)" <<'EOF'
detected_at	feature	local_key	jira_key	reason	resolution
2026-01-01T00:00:00Z	demo	1.1	DEMO-2	label_drift	pending
EOF
  _sha_task=$(printf '%s' "Titulo da tarefa" | "$IO_SCRIPT" sha256-stdin)
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"fields":{"summary":"Titulo da tarefa","status":{"name":"Done"},"labels":["prioridade-alta"]}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_task\",\"written_status\":\"Done\",\"written_phase_label\":\"phase-3\"}}"
  _queue_push 200 ''
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" resolve --feature demo --local-key 1.1 --choice keep_jira || return 1
  [ "$(_queue_calls_count)" = "3" ] \
    || { _fail "sy94_calls" "keep_jira NUNCA chama R2 (so R3 + R6get marker + R6 marker), obtido $(_queue_calls_count)"; return 1; }
  _final_label=$("$IO_SCRIPT" json-get '.written_phase_label? // "AUSENTE"' < "$TMPDIR_TEST/queue-curl-body-3.json")
  [ "$_final_label" = "AUSENTE" ] \
    || { _fail "sy94_baseline_vazia" "keep_jira deveria manter baseline vazia (nenhum phase-* na issue), obtido: $_final_label"; return 1; }
  return 0
}

# r02 FASE 23 tarefa 23.1.1/23.1.3 (achado 23.1, converge-report Round r02
# Ciclo 3 — regressao de 22.2.1): `overwrite` de `label_drift` reaplicando
# phase-<N> local (mesmo cenario de sy93, issue SEM nenhum phase-*) quando o
# R2 PUT (update.labels) falha com 403 (permission_denied) MUST propagar a
# falha — NUNCA fechar o conflito como sucesso. Antes do fix, `_jrpl_ec=$?`
# era lido DEPOIS de um `if...fi` sem `else` (sempre 0 por definicao POSIX
# quando a condicao falha), mascarando o 403 e fazendo `overwrite` voltar a
# ter o efeito de `keep_jira` (baseline vazia, conflito fechado igual).
#
# r02 FASE 24 tarefa 24.1.4 (correcao de oraculo falso): reintroduzir SO a
# leitura de "$?" apos o `fi` sem `else` (sem tocar a checagem de
# `http_status` adicionada na MESMA tarefa 23.1.1) e um mutante EQUIVALENTE
# para ESTE teste — medido nesta tarefa: os 3 cenarios 23.1 (este, o 400
# logo abaixo e o labels_enabled=off) continuam TODOS passando com esse
# mutante, porque a checagem de `http_status` em `_js_reconcile_phase_label`
# (jira-sync.sh, `case "$_jrpl_status" in 2??) : ;; *) [ "$_jrpl_ec" -eq 0 ]
# && _jrpl_ec=1 ;; esac`) ja converte qualquer `http_status` nao-2xx (403
# incluso) em `_jrpl_ec` nao-zero, independente do valor (correto ou
# mascarado-em-0) que a captura de "$?" produziu. O mutante que de fato
# discrimina um teste desta familia e remover a checagem de `http_status`
# (medido: o cenario 400 logo abaixo falha com esse mutante) — coberto em
# tests/cstk/test_jira-mutation.sh
# scenario_mutation_24_1_4_reconcile_phase_label_http_status.
scenario_resolve_overwrite_label_drift_r2_403_nao_fecha_como_sucesso() {
  _write_full_config
  _write_credential
  _write_tasks_fase5_1task_1sub_pass
  _write_map_row "demo" epic 20001 DEMO-1 active
  _write_map_row "1.1" task 20002 DEMO-2 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_conflicts_file)" <<'EOF'
detected_at	feature	local_key	jira_key	reason	resolution
2026-01-01T00:00:00Z	demo	1.1	DEMO-2	label_drift	pending
EOF
  _sha_task=$(printf '%s' "Titulo da tarefa" | "$IO_SCRIPT" sha256-stdin)
  _bin="$(_init_queue_stub)"
  # R3 do rebaseline: issue SEM nenhum label phase-* (so um label humano).
  _queue_push 200 '{"fields":{"summary":"Titulo da tarefa","status":{"name":"Done"},"labels":["prioridade-alta"]}}'
  # R6 GET (marker atual).
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_task\",\"written_status\":\"Done\",\"written_phase_label\":\"phase-3\"}}"
  # R2 (update.labels add phase-5) falha com 403 -- permissao insuficiente.
  _queue_push 403 '{"errorMessages":["forbidden"]}'
  PATH="$_bin:$PATH" assert_exit 1 "$SCRIPT" resolve --feature demo --local-key 1.1 --choice overwrite || return 1

  grep -q 'demo	1.1	DEMO-2	label_drift	pending$' "$(_conflicts_file)" \
    || { _fail "sy_r2_403_conflict_still_pending" "ConflictRecord deveria continuar pending apos falha do R2 (403): $(cat "$(_conflicts_file)")"; return 1; }

  [ "$(_queue_calls_count)" = "3" ] \
    || { _fail "sy_r2_403_calls" "esperado 3 chamadas (R3 rebaseline + R6get marker + R2 PUT 403), obtido $(_queue_calls_count)"; return 1; }
  grep -qE '^PUT .*properties' "$TMPDIR_TEST/queue-curl-calls.log" \
    && { _fail "sy_r2_403_no_marker_put" "R6 PUT do marker NAO deveria ocorrer apos falha do R2 (conflito nao fechado)"; return 1; }
  return 0
}

# r02 FASE 23 tarefa 23.1.1/23.1.3 (achado 23.1): mesmo cenario acima, mas
# o R2 PUT falha com 400 (corpo invalido) — `jira-io.sh` classifica 400 so
# para `--op R4`/`--op R12` (contracts/plugin-scripts.md 3.4); para `--op
# R2` fica em passthrough (exit 0). Sem checar `http_status` no chamador,
# o 400 era tratado como sucesso e `written_phase_label=phase-5` era
# gravado no marker SEM o label ter sido de fato aplicado (baseline
# falsa que o drain nunca corrige, pois WRITTEN==TARGET vira no-op
# imediato). Mutation (remover a checagem de `http_status` nao-2xx) MUST
# falhar este teste (resolve voltaria a sair 0 e gravaria a baseline).
scenario_resolve_overwrite_label_drift_r2_400_nao_grava_baseline_falsa() {
  _write_full_config
  _write_credential
  _write_tasks_fase5_1task_1sub_pass
  _write_map_row "demo" epic 20001 DEMO-1 active
  _write_map_row "1.1" task 20002 DEMO-2 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_conflicts_file)" <<'EOF'
detected_at	feature	local_key	jira_key	reason	resolution
2026-01-01T00:00:00Z	demo	1.1	DEMO-2	label_drift	pending
EOF
  _sha_task=$(printf '%s' "Titulo da tarefa" | "$IO_SCRIPT" sha256-stdin)
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"fields":{"summary":"Titulo da tarefa","status":{"name":"Done"},"labels":["prioridade-alta"]}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_task\",\"written_status\":\"Done\",\"written_phase_label\":\"phase-3\"}}"
  # R2 (update.labels add phase-5) responde 400 -- passthrough exit 0 em
  # jira-io.sh; so o http_status na 1a linha de stderr denuncia a falha.
  _queue_push 400 '{"errorMessages":["invalid label value"]}'
  PATH="$_bin:$PATH" assert_exit 1 "$SCRIPT" resolve --feature demo --local-key 1.1 --choice overwrite || return 1

  grep -q 'demo	1.1	DEMO-2	label_drift	pending$' "$(_conflicts_file)" \
    || { _fail "sy_r2_400_conflict_still_pending" "ConflictRecord deveria continuar pending apos falha do R2 (400): $(cat "$(_conflicts_file)")"; return 1; }

  [ "$(_queue_calls_count)" = "3" ] \
    || { _fail "sy_r2_400_calls" "esperado 3 chamadas (R3 rebaseline + R6get marker + R2 PUT 400), obtido $(_queue_calls_count)"; return 1; }
  grep -qE '^PUT .*properties' "$TMPDIR_TEST/queue-curl-calls.log" \
    && { _fail "sy_r2_400_no_marker_put" "R6 PUT do marker (baseline falsa) NAO deveria ocorrer apos 400 em R2"; return 1; }
  return 0
}

# r02 FASE 23 tarefa 23.1.2/23.1.3 (achado 23.1, data-model.md:406 "phase_
# label vazio para Epic ou labels_enabled=off"): `overwrite` de `label_
# drift` com `labels_enabled=off` MUST NUNCA emitir `update.labels` — o
# ramo `overwrite` ignorava esta flag (so `convert`/`drain` a liam antes
# desta tarefa). Baseline fica vazia (mesmo resultado de Epic/coluna
# `phase` irreconhecivel), ZERO chamadas R2. Mutation (remover a guarda de
# `labels_enabled`) MUST falhar este teste (uma chamada R2 extra apareceria
# no lugar do R6 PUT final, e o grep de PUT plano em /issue/DEMO-2 casaria).
scenario_resolve_overwrite_label_drift_labels_enabled_off_zero_r2() {
  _write_full_config_labels_off
  _write_credential
  _write_tasks_fase5_1task_1sub_pass
  _write_map_row "demo" epic 20001 DEMO-1 active
  _write_map_row "1.1" task 20002 DEMO-2 active
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  mkdir -p "$(dirname "$(_outbox_file)")"
  cat > "$(_conflicts_file)" <<'EOF'
detected_at	feature	local_key	jira_key	reason	resolution
2026-01-01T00:00:00Z	demo	1.1	DEMO-2	label_drift	pending
EOF
  _sha_task=$(printf '%s' "Titulo da tarefa" | "$IO_SCRIPT" sha256-stdin)
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"fields":{"summary":"Titulo da tarefa","status":{"name":"Done"},"labels":["prioridade-alta"]}}'
  _queue_push 200 "{\"key\":\"cstk-jira.sync\",\"value\":{\"written_summary_sha256\":\"$_sha_task\",\"written_status\":\"Done\",\"written_phase_label\":\"phase-3\"}}"
  # R6 PUT do marker rebaselinado (SEM nenhum R2 antes, labels_enabled=off).
  _queue_push 200 ''
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" resolve --feature demo --local-key 1.1 --choice overwrite || return 1

  grep -q 'demo	1\.1	DEMO-2	label_drift	overwrite$' "$(_conflicts_file)" \
    || { _fail "sy_labeloff_resolution" "resolution nao virou overwrite: $(cat "$(_conflicts_file)")"; return 1; }

  [ "$(_queue_calls_count)" = "3" ] \
    || { _fail "sy_labeloff_calls" "esperado 3 chamadas (R3 + R6get marker + R6 marker, ZERO R2), obtido $(_queue_calls_count)"; return 1; }
  grep -qE '^PUT .*api/3/issue/DEMO-2$' "$TMPDIR_TEST/queue-curl-calls.log" \
    && { _fail "sy_labeloff_no_r2" "R2 (update.labels) NAO deveria ocorrer com labels_enabled=off"; return 1; }

  _final_label=$("$IO_SCRIPT" json-get '.written_phase_label? // "AUSENTE"' < "$TMPDIR_TEST/queue-curl-body-3.json")
  [ "$_final_label" = "AUSENTE" ] \
    || { _fail "sy_labeloff_baseline_vazia" "written_phase_label deveria ficar vazio com labels_enabled=off, obtido: $_final_label"; return 1; }
  return 0
}

# ==== links (r02 FASE 18 task 18.4, FR-025, research.md Decision R2-6) =====
#
#   SY-86 links: links_enabled=off -> linking=disabled, ZERO chamadas de
#         rede (nem R16 nem R17)
#   SY-87 links: idempotencia 10x (18.4.6) — link_type_id ja confirmado em
#         ProjectConfig (sem R16): 1a chamada cria via R17 (links_active=1),
#         as 9 seguintes SAO idempotentes (0 R17 adicional)
#   SY-88 links: link_type_id vazio + R16 com 2 candidatos ambiguos (nenhum
#         bate "block") -> unrepresentable reason=ambiguous_link_type, ZERO
#         chamadas R17
#   SY-89 links: 404 em R17 (linking_disabled de negocio) cascata para a
#         2a aresta pendente SEM tentar R17 de novo (so 1 R17 na fila)
#   SY-90 links: 413 em R17 -> unrepresentable reason=limit (so a aresta),
#         linking permanece "enabled"

_links_file() {
  printf '%s\n' "$TMPDIR_TEST/docs/specs/demo/jira-links.tsv"
}

# _write_two_phase_deps: tasks.md com FASE 1 -> FASE 2 (Matriz de
# Dependencias) + 1 task ativa mapeada em cada fase (ancoras resolviveis
# por `jira-map.sh anchor`).
_write_two_phase_deps() {
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cat > "$TMPDIR_TEST/docs/specs/demo/tasks.md" <<'EOF'
## FASE 1 - Primeira `[A]`

### 1.1 Tarefa um `[A]`

- [x] 1.1.1 Sub um

## FASE 2 - Segunda `[A]`

### 2.1 Tarefa dois `[A]`

- [ ] 2.1.1 Sub dois

## Matriz de Dependencias

```mermaid
flowchart TD
    F1[FASE 1 - Primeira]
    F2[FASE 2 - Segunda]
    F1 --> F2
```
EOF
  _write_map_row "1.1" "task" "10010" "DEMO-10" "active"
  _write_map_row "2.1" "task" "10020" "DEMO-20" "active"
}

scenario_links_disabled_zero_chamadas() {
  _write_full_config
  _append_config_line "links_enabled=off"
  _write_credential
  _write_two_phase_deps
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  _bin="$(_init_queue_stub)"
  _out=$(PATH="$_bin:$PATH" "$SCRIPT" links --feature demo) \
    || { _fail "sy86_exit" "links deveria sair exit 0"; return 1; }
  printf '%s\n' "$_out" | grep -qx "linking=disabled" \
    || { _fail "sy86_linking" "esperado linking=disabled, obtido: $_out"; return 1; }
  [ "$(_queue_calls_count)" = "0" ] \
    || { _fail "sy86_zero_calls" "esperado 0 chamadas de rede, obtido $(_queue_calls_count)"; return 1; }
}

scenario_links_idempotente_10x_zero_r17_apos_primeira() {
  _write_full_config
  _append_config_line "link_type_id=10000"
  _write_credential
  _write_two_phase_deps
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  _bin="$(_init_queue_stub)"
  _queue_push 201 ''

  _i=1
  while [ "$_i" -le 10 ]; do
    _out=$(PATH="$_bin:$PATH" "$SCRIPT" links --feature demo) \
      || { _fail "sy87_exit_$_i" "links deveria sair exit 0 na chamada $_i"; return 1; }
    printf '%s\n' "$_out" | grep -qx "links_active=1" \
      || { _fail "sy87_active_$_i" "esperado links_active=1 na chamada $_i, obtido: $_out"; return 1; }
    _i=$((_i + 1))
  done

  _r17_calls=$(grep -c 'POST .*api/3/issueLink$' "$TMPDIR_TEST/queue-curl-calls.log" 2>/dev/null) || _r17_calls=0
  [ "$_r17_calls" = "1" ] \
    || { _fail "sy87_r17_once" "esperado exatamente 1 R17 em 10 chamadas, obtido $_r17_calls"; return 1; }

  grep -q '^1	2	DEMO-10	DEMO-20	10000	active	$' "$(_links_file)" \
    || { _fail "sy87_row" "linha active ausente/incorreta em jira-links.tsv: $(cat "$(_links_file)" 2>/dev/null)"; return 1; }
}

scenario_links_ambiguous_link_type_zero_r17() {
  _write_full_config
  _write_credential
  _write_two_phase_deps
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"issueLinkTypes":[{"id":"10000","name":"Blocks","inward":"is blocked by","outward":"blocks"},{"id":"10005","name":"BlockedAlt","inward":"is blocked alt by","outward":"blocks alt"}]}'

  _out=$(PATH="$_bin:$PATH" "$SCRIPT" links --feature demo) \
    || { _fail "sy88_exit" "links deveria sair exit 0"; return 1; }
  printf '%s\n' "$_out" | grep -qx "links_unrepresentable=1" \
    || { _fail "sy88_unrep" "esperado links_unrepresentable=1 (ambiguous_link_type), obtido: $_out"; return 1; }
  awk -F '\t' 'NR>1 && $7=="ambiguous_link_type" { f=1 } END { exit(f?0:1) }' "$(_links_file)" \
    || { _fail "sy88_row" "reason ambiguous_link_type ausente em jira-links.tsv: $(cat "$(_links_file)" 2>/dev/null)"; return 1; }
  _r17_calls=$(grep -c 'POST .*api/3/issueLink$' "$TMPDIR_TEST/queue-curl-calls.log" 2>/dev/null) || _r17_calls=0
  [ "$_r17_calls" = "0" ] \
    || { _fail "sy88_zero_r17" "ambiguidade de tipo NUNCA deveria tentar R17, obtido $_r17_calls"; return 1; }
}

# task 21.2.1/21.2.2 (contracts/jira-rest.md R17 + plan.md Riscos, achado
# 21.2): 404 ISOLADO em R17 (sem R16 confirmar linking desligado no site —
# aqui nem sequer roda, `link_type_id` vem do ProjectConfig) vira
# `unrepresentable reason=visibility_or_disabled` SO da aresta que
# respondeu 404 — as demais arestas da MESMA chamada seguem tentando R17
# normalmente (sem cascata). Antes da correcao (achado 21.2), a 1a aresta
# 404 desligava `_jsl_linking_disabled` e as 2 arestas seguintes eram
# marcadas `unrepresentable reason=linking_disabled` SEM sequer tentar
# R17 — mutation (reintroduzir `_jsl_linking_disabled="yes"` neste ramo)
# MUST falhar este teste (3 R17 attempts vira 1, reason muda).
scenario_links_404_r17_isolado_vira_unrepresentable_por_aresta_sem_cascata() {
  _write_full_config
  _append_config_line "link_type_id=10000"
  _write_credential
  mkdir -p "$TMPDIR_TEST/docs/specs/demo"
  cat > "$TMPDIR_TEST/docs/specs/demo/tasks.md" <<'EOF'
## FASE 1 - Primeira `[A]`

### 1.1 Tarefa um `[A]`

- [x] 1.1.1 Sub um

## FASE 2 - Segunda `[A]`

### 2.1 Tarefa dois `[A]`

- [ ] 2.1.1 Sub dois

## FASE 3 - Terceira `[A]`

### 3.1 Tarefa tres `[A]`

- [ ] 3.1.1 Sub tres

## Matriz de Dependencias

```mermaid
flowchart TD
    F1[FASE 1 - Primeira]
    F2[FASE 2 - Segunda]
    F3[FASE 3 - Terceira]
    F1 --> F2
    F1 --> F3
    F2 --> F3
```
EOF
  _write_map_row "1.1" "task" "10010" "DEMO-10" "active"
  _write_map_row "2.1" "task" "10020" "DEMO-20" "active"
  _write_map_row "3.1" "task" "10030" "DEMO-30" "active"
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  _bin="$(_init_queue_stub)"
  # 3 arestas (F1->F2, F1->F3, F2->F3, nesta ordem — `jira-tasks.sh
  # phase-edges` preserva a ordem de declaracao do mermaid): a 1a R17
  # responde 404 (visibilidade/desligado ambiguo, SO desta aresta); as
  # demais 2 respondem 201 (linking segue ligado — nunca deveriam ter sido
  # puladas por cascata).
  _queue_push 404 '{}'
  _queue_push 201 ''
  _queue_push 201 ''

  _out=$(PATH="$_bin:$PATH" "$SCRIPT" links --feature demo) \
    || { _fail "sy89_exit" "links deveria sair exit 0"; return 1; }
  printf '%s\n' "$_out" | grep -qx "linking=enabled" \
    || { _fail "sy89_linking" "404 isolado em R17 NUNCA prova linking desligado no site — esperado linking=enabled, obtido: $_out"; return 1; }
  printf '%s\n' "$_out" | grep -qx "links_active=2" \
    || { _fail "sy89_active" "esperado links_active=2 (as 2 arestas seguintes NUNCA deveriam ser puladas por cascata), obtido: $_out"; return 1; }
  printf '%s\n' "$_out" | grep -qx "links_unrepresentable=1" \
    || { _fail "sy89_unrep" "esperado links_unrepresentable=1 (SO a aresta que respondeu 404), obtido: $_out"; return 1; }
  _r17_calls=$(grep -c 'POST .*api/3/issueLink$' "$TMPDIR_TEST/queue-curl-calls.log" 2>/dev/null) || _r17_calls=0
  [ "$_r17_calls" = "3" ] \
    || { _fail "sy89_r17_tres" "esperado 3 tentativas de R17 (sem cascata pulando nenhuma), obtido $_r17_calls"; return 1; }
  awk -F '\t' 'NR>1 && $7=="linking_disabled"' "$(_links_file)" | grep -q . \
    && { _fail "sy89_no_linking_disabled" "404 isolado em R17 NUNCA deveria gravar reason=linking_disabled (achado 21.2): $(cat "$(_links_file)" 2>/dev/null)"; return 1; }
  _nvisib=$(awk -F '\t' 'NR>1 && $7=="visibility_or_disabled"' "$(_links_file)" | wc -l | tr -d ' ')
  [ "$_nvisib" = "1" ] \
    || { _fail "sy89_reason" "esperado exatamente 1 linha reason=visibility_or_disabled, obtido $_nvisib: $(cat "$(_links_file)" 2>/dev/null)"; return 1; }
}

# Regressao preservada (achado 21.2 so muda o ramo de 404 ISOLADO em
# R17): 404 no proprio R16 continua provando linking desligado no site e
# cascateando reason=linking_disabled para TODAS as arestas pendentes,
# ZERO tentativas de R17 — ja coberto por SY-91
# (`scenario_links_404_r16_linking_disabled_sem_link_type`, abaixo),
# reexecutada sem mudanca nesta onda para confirmar a nao-regressao.

scenario_links_413_r17_reason_limit() {
  _write_full_config
  _append_config_line "link_type_id=10000"
  _write_credential
  _write_two_phase_deps
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  _bin="$(_init_queue_stub)"
  _queue_push 413 '{}'

  _out=$(PATH="$_bin:$PATH" "$SCRIPT" links --feature demo) \
    || { _fail "sy90_exit" "links deveria sair exit 0"; return 1; }
  printf '%s\n' "$_out" | grep -qx "linking=enabled" \
    || { _fail "sy90_linking" "413 e por-aresta, linking deveria seguir enabled, obtido: $_out"; return 1; }
  printf '%s\n' "$_out" | grep -qx "links_unrepresentable=1" \
    || { _fail "sy90_unrep" "esperado links_unrepresentable=1, obtido: $_out"; return 1; }
  awk -F '\t' 'NR>1 && $7=="limit" { f=1 } END { exit(f?0:1) }' "$(_links_file)" \
    || { _fail "sy90_row" "reason=limit ausente em jira-links.tsv: $(cat "$(_links_file)" 2>/dev/null)"; return 1; }
}

# r02 FASE 24 tarefa 24.4.1/24.4.2 (achado 24.4): R17 POST responde 400 —
# `jira-io.sh` so classifica 404/413 de R17 (exit 7); 400
# (contracts/jira-rest.md:548) chega em passthrough (exit 0) — sem checar
# `http_status` no ramo de sucesso, a aresta seria gravada `active` sem o
# link ter sido de fato criado no Jira (FR-025 violada em silencio,
# nenhuma prova de 404/413 para justificar `unrepresentable`). MUST:
# `links_active=0`, ZERO linha na aresta em jira-links.tsv (nem `active`
# nem `unrepresentable` — falha generica, mesmo tratamento de
# auth_failed/deferred), e a 2a execucao TENTA o R17 de novo (nada
# persistido que a impeca).
scenario_links_r17_400_passthrough_nao_grava_active_retenta() {
  _write_full_config
  _append_config_line "link_type_id=10000"
  _write_credential
  _write_two_phase_deps
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  _bin="$(_init_queue_stub)"
  _queue_push 400 '{"errorMessages":["invalid link"]}'

  _out=$(PATH="$_bin:$PATH" "$SCRIPT" links --feature demo) \
    || { _fail "sy24_4_1_exit" "links deveria sair exit 0"; return 1; }
  printf '%s\n' "$_out" | grep -qx "links_active=0" \
    || { _fail "sy24_4_1_active" "esperado links_active=0 (400 em passthrough NUNCA conta como active), obtido: $_out"; return 1; }
  _rows=$(awk -F '\t' 'NR>1' "$(_links_file)" 2>/dev/null | wc -l | tr -d ' ') || _rows=0
  [ "$_rows" = "0" ] \
    || { _fail "sy24_4_1_no_row" "esperado ZERO linhas em jira-links.tsv (nem active nem unrepresentable), obtido $_rows: $(cat "$(_links_file)" 2>/dev/null)"; return 1; }

  # 2a execucao: nada foi persistido -> a aresta e tratada como NOVA de
  # novo -> R17 tentado outra vez. Desta vez responde 201 (sucesso real).
  _queue_push 201 ''
  _out2=$(PATH="$_bin:$PATH" "$SCRIPT" links --feature demo) \
    || { _fail "sy24_4_1_exit2" "2a execucao de links deveria sair exit 0"; return 1; }
  printf '%s\n' "$_out2" | grep -qx "links_active=1" \
    || { _fail "sy24_4_1_retry" "esperado links_active=1 na 2a execucao (retry do R17 apos 400 na 1a), obtido: $_out2"; return 1; }
  _r17_calls=$(grep -c 'POST .*api/3/issueLink$' "$TMPDIR_TEST/queue-curl-calls.log" 2>/dev/null) || _r17_calls=0
  [ "$_r17_calls" = "2" ] \
    || { _fail "sy24_4_1_r17_twice" "esperado exatamente 2 tentativas de R17 (1a=400, 2a=201), obtido $_r17_calls"; return 1; }
  return 0
}

# SY-91 links: 404 simulado em R16 (link_type_id vazio) -> TODAS as
# dependencias da feature ficam unrepresentable reason=linking_disabled,
# ZERO chamadas R17 (nem sequer tentadas — jira-io.sh ja classifica exit 7
# linking_disabled direto na propria R16).
scenario_links_404_r16_linking_disabled_sem_link_type() {
  _write_full_config
  _write_credential
  _write_two_phase_deps
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  _bin="$(_init_queue_stub)"
  _queue_push 404 '{}'

  _out=$(PATH="$_bin:$PATH" "$SCRIPT" links --feature demo) \
    || { _fail "sy91_exit" "links deveria sair exit 0"; return 1; }
  printf '%s\n' "$_out" | grep -qx "linking=disabled" \
    || { _fail "sy91_linking" "esperado linking=disabled apos 404 em R16, obtido: $_out"; return 1; }
  printf '%s\n' "$_out" | grep -qx "links_unrepresentable=1" \
    || { _fail "sy91_unrep" "esperado links_unrepresentable=1, obtido: $_out"; return 1; }
  awk -F '\t' 'NR>1 && $7=="linking_disabled" { f=1 } END { exit(f?0:1) }' "$(_links_file)" \
    || { _fail "sy91_row" "reason=linking_disabled ausente em jira-links.tsv: $(cat "$(_links_file)" 2>/dev/null)"; return 1; }
  _r17_calls=$(grep -c 'POST .*api/3/issueLink$' "$TMPDIR_TEST/queue-curl-calls.log" 2>/dev/null) || _r17_calls=0
  [ "$_r17_calls" = "0" ] \
    || { _fail "sy91_zero_r17" "404 em R16 NUNCA deveria tentar R17, obtido $_r17_calls"; return 1; }
}

run_all_scenarios
