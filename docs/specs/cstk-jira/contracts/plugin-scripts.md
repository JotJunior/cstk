# Contract: scripts internos do plugin (`plugins/cstk-jira/scripts/`)

Interface de linha de comando PROJETADA por este plano (nao e contrato de
sistema externo — Principio VI nao exige fonte para interface nova; os pontos
em que ela toca o Jira remetem a `jira-rest.md`/`rovo-mcp.md`).

Convencoes comuns (Principio II):

- `#!/bin/sh`, `set -eu`, sem bash-isms; dados em stdout, diagnostico em stderr.
- Exit codes: `0` sucesso; `1` erro geral (inclui `classification=deferred`
  — candidato a retry pelo chamador); `2` uso incorreto; `3` plugin
  inativo/nao configurado (FR-017 — chamador trata como no-op);
  `4` credencial ausente/rejeitada (FR-016) OU `classification=auth_failed`
  (`jira-io.sh request` apos `401`/`403` fora de R1/R2 — dec-073, nunca
  retry automatico); `5` dependencia ausente (`jq`/cliente HTTP — carve-out
  1.1.0, condicao a); `6` conflito detectado (FR-011) ou orfao (FR-012) —
  nada foi sobrescrito; `7` `classification=permission_denied` (so
  `jira-io.sh request` — `403` em `--op R1`/`--op R2`, dec-073: credencial
  valida, permissao insuficiente no projeto/tipo, NUNCA reconfiguracao de
  credencial).
- Nenhum script aceita URL, host ou credencial por argumento: host vem de
  `ProjectConfig.site_host`, credencial de `Credential` (`data-model.md`).
- Instalado o plugin, SO a subarvore `plugins/cstk-jira/` existe no disco do
  usuario: nenhum script referencia `cli/lib/` nem o plugin `cstk` por caminho
  relativo do repositorio.

## `jira-io.sh` — UNICO arquivo com `jq` e cliente HTTP (carve-out 1.1.0 b)

| Subcomando | Entrada | Saida | Notas |
|------------|---------|-------|-------|
| `deps-check` | — | nada | exit 5 + instrucao de instalacao se faltar `jq` ou o cliente HTTP |
| `request METHOD PATH [--body-file F] [--op OP]` | METHOD em `GET`/`POST`/`PUT` (allowlist fechada — nao existe `DELETE`, FR-012); PATH relativo iniciado em `/rest/`; `OP` opcional em `R1`..`R11` (contracts/jira-rest.md) — informa qual operacao esta sendo servida, so usado para classificar `403`/`400`/`409` (dec-073) | corpo da resposta em stdout SO no caminho de sucesso; status HTTP + classificacao estruturada (`http_status=`/`classification=`/`retry_after=`) em stderr | monta `https://<site_host><PATH>` com `site_host` de `ProjectConfig`; valida host por IGUALDADE exata (sem userinfo, sem porta) antes de cada requisicao; NAO segue redirect para host diferente (FR-015); credencial passada ao cliente HTTP por arquivo de config temporario `0600` removido em `trap`, nunca em argv; SEC-1: PATH recusado (exit 2, sem requisicao) se contiver `..`, `//`, `\`, `@`, `#`, espaco, CR/LF ou qualquer outro byte de controle; FASE 12 tarefa 12.9.1 (FR-015): recusa exit 4 (`classification=auth_failed`), SEM disparar a requisicao, quando o `site_host` gravado na propria Credential (global, fora do repo) diverge — byte a byte — do `site_host` de `ProjectConfig` (versionado) — evita que trocar `site_host` no config versionado desvie silenciosamente uma credencial de outro site; ver "Mapeamento de status HTTP" abaixo para a classificacao de falha (3.4) |
| `validate-segment VALUE [VALUE...]` | 1+ VALUE (ex.: `jira_id`/`jira_key`/`project_key`) | nada (so exit code) | SEC-1: valida cada VALUE contra a allowlist fechada de charset `[A-Za-z0-9_-]`, nao-vazio; exit 2 no primeiro que falhar. O motor (`jira-sync.sh`/`jira-map.sh`, FASE 4+) MUST chamar isto para cada segmento ANTES de interpolar PATH ou JQL — nao exige `jq`/cliente HTTP |
| `json-get FILTER` | JSON em stdin | valor em stdout | wrapper de leitura (restringe `jq` a este arquivo); `jq -r FILTER`; filtro/entrada invalidos => exit 2; so exige `jq` (nao exige cliente HTTP/ProjectConfig/credencial) |
| `json-build issue --project-id ID --issuetype-id ID --summary TEXT [--parent-key KEY] [--description TEXT]` | ids/keys (SEC-1: mesma allowlist `[A-Za-z0-9_-]` de `validate-segment`); summary/description texto livre | JSON em stdout | monta o corpo de R1 (`contracts/jira-rest.md`): `fields.project.id`, `fields.issuetype.id`, `fields.summary`, `fields.parent.key` (opcional), `fields.description` em ADF (opcional); summary/description via `jq --arg` (nunca concatenacao de string); id/key fora da allowlist => exit 2 sem montar corpo |
| `json-build filter --name TEXT --project-key KEY` | `--project-key` (SEC-1); `--name` texto livre | JSON em stdout | monta o corpo de R9 (`contracts/jira-rest.md`): `{"name":..., "jql":"project = \"KEY\""}`; SEC-3: `--project-key` MUST passar pela allowlist SEC-1 ANTES de entrar na JQL — recusado (exit 2) sem montar JQL alguma; `--name` nunca e interpolado em `jql`; base da JQL do filtro do board (FR-013) |
| `json-build issue-update --summary TEXT [--description TEXT]` | summary/description texto livre | JSON em stdout | monta o corpo de R2 (`contracts/jira-rest.md`, feature cstk-jira FASE 10 tarefa 10.2/FR-003): `{"fields":{"summary":...}}` (+ `description` em ADF, opcional) — SEM `project`/`issuetype`/`parent` (imutaveis numa edicao); summary/description via `jq --arg` |
| `json-build board --name TEXT --filter-id ID --project-key KEY` | ID/KEY (SEC-1); `--name` texto livre | JSON em stdout | monta o corpo de R10 (criar board kanban): `{"name":...,"type":"kanban","filterId":<numero>,"location":{"type":"project","projectKeyOrId":...}}`; `--filter-id` MUST ser so digitos (emitido como numero JSON, nunca string — schema oficial da Agile API exige integer/int64); `--project-key` passa pela allowlist SEC-1 |
| `json-build transition --transition-id ID` | ID (SEC-1) | JSON em stdout | monta o corpo de R4 (executar transicao): `{"transition":{"id":ID}}` |
| `json-build marker --local-key K --feature F --written-summary-sha256 H --written-status S --written-at T [--written-description-sha256 H2]` | todos texto livre (podem conter pontos/espacos, ex. `"4.2.1"`/`"In Progress"`) | JSON em stdout | monta o VALOR CRU do SyncMarker (R6 PUT, sem envelope `{key,value}` — a chave ja vai na URL): `{"schema":1,"local_key":K,"feature":F,"written_summary_sha256":H,"written_status":S,"written_at":T}`; `--written-description-sha256` OPCIONAL (FASE 12 tarefa 12.5.1) acrescenta `"written_description_sha256":H2` — omitido, a chave nao aparece (Epic/Sub-task e Task sem descricao composta nunca gravam este campo) |
| `sha256-stdin` | dados brutos em stdin | SHA-256 hex em stdout | usa `sha256sum` ou `shasum -a 256` (o que estiver no PATH); usado pelo motor (`jira-sync.sh`) para comparar titulo/descricao ATUAIS da issue contra `written_summary_sha256`/`written_description_sha256` do SyncMarker — so o hash e comparado/gravado, nunca o texto em si |

Mapeamento de status HTTP (politica de design; **corrigido na tarefa 3.4/
dec-073** — a versao anterior desta tabela tratava `401`/`403` uniformemente
como `auth_failed`, mesmo conflito ja identificado e corrigido em `plan.md`
por CHK009/dec-038; a tabela abaixo e a versao final, implementada em
`jira-io.sh`):

| Resposta | Tratamento |
|----------|-----------|
| 2xx | sucesso — corpo em stdout, `http_status=<codigo>` em stderr |
| 401 (qualquer operacao) | exit 4, `classification=auth_failed` — nunca retry (FR-016/FR-019) |
| 403 em `--op R1`/`--op R2` (criar/editar issue) | exit 7, `classification=permission_denied` — credencial valida, permissao insuficiente no projeto/tipo; NUNCA reconfiguracao de credencial (`contracts/jira-rest.md` "Validacao de credencial") |
| 403 fora de R1/R2 (ou `--op` omitido — default conservador) | exit 4, `classification=auth_failed` ate nova fonte que os distinga |
| 429 | exit 1, `classification=deferred`, `retry_after=<s>` em stderr quando o header `Retry-After` vier (research Decision 3) — `jira-io.sh` NAO retenta sozinho; quem decide quando reenviar e o chamador (drain) |
| 5xx / erro de rede / timeout | ate 3 tentativas com backoff (`sleep`, `JIRA_IO_BACKOFF_SECONDS` overridable) DENTRO da mesma chamada de `request`; esgotadas, exit 1 `classification=deferred` |
| 400/409 em `--op R4` (transicao concorrente) | exit 1, `classification=deferred` (research Decision 3 / change-notice: requisicoes simultaneas na mesma issue) |
| Demais codigos (400/409 fora de R4, 404, 422, etc.) | fora do escopo de classificacao desta tarefa — passthrough como sucesso (comportamento pre-3.4 preservado; nao inventar classificacao alem do exigido) |

## `jira-config.sh`

| Subcomando | Descricao |
|------------|-----------|
| `get KEY` | le `ProjectConfig`; exit 3 se arquivo ausente |
| `validate` | valida campos obrigatorios, `site_host` como hostname puro e `status_fail != status_pass` |
| `credential-check` | confere existencia e permissao `0600` do arquivo de credencial para `site_host` (sem imprimir valores) |

## `jira-tasks.sh` (POSIX, `awk`)

| Subcomando | Saida (TSV) |
|------------|-------------|
| `items --feature F [--outcomes-file FILE] [--stage STAGE]` | `local_key  kind  phase  criticality  local_state  title` para Epic + tasks + subtasks de `docs/specs/F/tasks.md` (+ titulo do Epic de `docs/specs/F/spec.md`), regras de `data-model.md` §LocalWorkItem. `--outcomes-file FILE`: TSV `task_id<TAB>outcome` (`pass`/`fail`) — fonte do outcome de `record_task`/`record-task` que tem precedencia sobre os checkboxes na derivacao da task (quem grava esse arquivo fica a cargo de `jira-sync.sh`/hooks, fora desta tarefa). `--stage STAGE`: consulta `jira-config.sh get "stage_status.STAGE"` para o `local_state` do Epic; config/chave ausente = cai na agregacao por tasks |
| `phase-deps --feature F --phase PHASE` | uma linha por FASE da qual `PHASE` depende (rotulo completo, ex.: `FASE 1 - Fundacao`), extraida da secao `## Matriz de Dependencias` de `docs/specs/F/tasks.md` (grafo mermaid FASE-a-FASE — UNICA fonte real e extraivel de dependencia deste backlog; FR-001, feature cstk-jira FASE 10 tarefa 10.1). `PHASE` e a coluna `phase` de `items` (so preenchida para `kind=task`). Sem numero de FASE reconhecivel na 2a palavra de `PHASE`, sem a secao Matriz, ou sem aresta apontando para essa FASE: stdout vazio, exit 0 (dependencia "quando existir", nunca erro) |

## `jira-map.sh` (POSIX)

| Subcomando | Descricao |
|------------|-----------|
| `get --feature F --local-key K` | linha do mapeamento ou exit 1 |
| `put --feature F --local-key K --kind KIND --jira-id ID --jira-key KEY` | insere de forma atomica (tmp + `mv`); recusa `local_key` ja existente em qualquer estado, `active` ou `orphan` (FR-013; data-model.md: criacao so para `local_key` ausente do arquivo) |
| `mark-orphans --feature F` | marca `orphan` as chaves `active` ausentes de `jira-tasks.sh items`; imprime todos os orfaos; exit 6 se houver ao menos 1 (FR-012) |
| `relink --feature F --local-key K --jira-key KEY [--new-local-key NK]` | religa um orfao por decisao humana; exige que `KEY` confira com o `jira_key` ja armazenado (confirmacao explicita de qual card). Sem `--new-local-key`, reativa `K` no lugar. Com `--new-local-key NK` (renumeracao, ex.: 2.3->2.4 — FASE 12 tarefa 12.10.1): MOVE a linha para `NK` (recusa, exit 1, se `NK` ja existir no mapeamento em qualquer estado — mesma disciplina de `put`), evitando o card duplicado que o proximo `convert` criaria. Em ambos os casos, fecha (best-effort, silencioso se ausente) o `ConflictRecord` PENDENTE `reason=orphan` do par em `runtime/conflicts.tsv` como `resolution=relinked` |

## `jira-sync.sh` — motor

| Subcomando | Descricao |
|------------|-----------|
| `plan --feature F` | dry-run: lista criacoes, atualizacoes, transicoes, orfaos e conflitos previstos, sem rede de escrita |
| `convert --feature F` | US1: cria Epic, depois Tasks (filhas do Epic), depois Sub-tasks, gravando o mapeamento item a item; pre-condicao: `deps-check`, `validate`, `credential-check` e validacao de credencial remota — qualquer falha aborta ANTES da 1a criacao (US1 cenario 3: sem artefato parcial por credencial invalida). Para Task (nunca Epic/Sub-task), compoe `fields.description` (FR-001, `_js_build_task_description`) com criticidade (coluna `criticality` de `items`) e dependencias (`jira-tasks.sh phase-deps`), quando existirem; nenhum dos dois presente = `--description` omitido do `json-build issue`. Apos CADA issue recem-criada (R1), grava o SyncMarker INICIAL (FASE 11 tarefa 11.1.1, FR-011: `_js_write_initial_marker`) — le o status atual via R3 dedicado (R1 so devolve `id`/`key`/`self`, nunca `status`; o summary ja e conhecido, e o mesmo enviado no corpo de R1) e faz R6 PUT com `written_summary_sha256`/`written_status`(+`written_description_sha256` quando ha descricao composta); sem isto, o 1o `drain`/reconcile dessa issue leria R6=404 e abriria `marker_missing` a toa. Falha nesse PUT so loga (stderr) e retorna — NUNCA desfaz a criacao/mapeamento ja gravados; a proxima `drain` detecta o marker ausente e reporta `marker_missing` (mesmo efeito de conflito, nada silencioso). Item JA mapeado (`active`) NUNCA e recriado — `_js_maybe_update_mapped_issue` (FR-003, feature cstk-jira FASE 10 tarefa 10.2; description estendida na FASE 12 tarefa 12.5.1) checa se o summary E/OU a description compostos AGORA divergem do summary/description atuais da issue (R3 `fields=summary,status[,description]` — description so lida quando o item carrega uma, kind=task com criticidade/dependencias); se sim, le o SyncMarker (R6) e SO escreve (R2 + regrava o SyncMarker, preservando `written_status`) quando `sha256(summary atual) == written_summary_sha256` E `status_atual == written_status` (FASE 11 tarefa 11.3.1 — antes so o summary era comparado) E (sem componente de description OU sem baseline de description no marker OU `sha256(description atual) == written_description_sha256`) — nenhuma edicao manual desde a ultima sync, nem de titulo, status ou descricao; marker ausente ou qualquer uma dessas divergencias => `ConflictRecord` (`marker_missing`/`manual_edit`), NUNCA sobrescreve (FR-011, mesma logica de deteccao de `_js_process_one_event`/drain; esta funcao nunca ESCREVE status, so detecta divergencia). Uma mudanca SO de criticidade/dependencias (summary inalterado) agora tambem dispara o R2 (achado 12.5 — antes ficava presa por um early-exit que so olhava o summary). `orphan` no mapeamento nunca e tocado (nem criado, nem atualizado) — so `relink` humano (FASE 4.3/4.4) |
| `enqueue --feature F --local-key K --state S --source SRC` | append no outbox; quando `S` e `pass`/`fail` e `K` != `*`, tambem persiste `K/S` no sidecar `runtime/task-outcomes.tsv` (FASE 12 tarefa 12.4.1) — fonte que `_js_process_reconcile_event` filtra por feature e repassa via `jira-tasks.sh items --outcomes-file` na reconciliacao seguinte, dando ao outcome de `record_task` precedencia sobre os checkboxes (data-model.md LocalWorkItem outcome precedence) |
| `drain --feature F` | processa o outbox com lock `runtime/.drain.lock/`; para cada item: le issue + SyncMarker, detecta conflito, transiciona para o status mapeado, regrava SyncMarker — o R6 PUT de regravacao CARREGA ADIANTE `written_description_sha256` do marker lido (quando presente), tanto para evento direto quanto para reconciliacao `local_key=*` (task 13.2.1; ver data-model.md §SyncMarker "Preservacao de `written_description_sha256` nas transicoes do `drain`"). Evento `local_key=*` (`desired_state=reconcile`, feature cstk-jira FASE 10 tarefa 10.3, FR-004) e expandido via `jira-tasks.sh items --feature F --outcomes-file ... --stage ...` (`_js_process_reconcile_event`; `--stage` = `current_stage` READ-ONLY da execucao ativa via `_js_resolve_stage`, FASE 12 tarefa 12.8.1 — ver data-model.md §LocalWorkItem) num item por Epic/Task/Sub-task ja mapeado (`active`), cada um passando pelo MESMO fluxo de deteccao de conflito/transicao; conflito em um item nunca bloqueia os demais (ConflictRecord por item); `auth_failed` em qualquer item interrompe a reconciliacao inteira; sem `auth_failed`/`deferred`, o evento `*` fecha `done`. Ordem interna sob o lock (FASE 12 tarefa 12.3.1): (1) compacta eventos `done`; (2) `jira-map.sh mark-orphans` (pura leitura/rewrite local, roda mesmo se o gate de auth_failed abaixo bloquearia); (3) gate FR-016 (evento `auth_failed` presente da feature bloqueia toda chamada nova); (4) seleciona elegiveis — `queued` SEMPRE, OU `deferred` cujo `available_at_epoch` no sidecar `runtime/deferred-retry.tsv` ja passou (ou sem linha nesse sidecar — elegivel de imediato); nada elegivel = exit 0 sem tocar `jira-io.sh`; (5) **`jira-io.sh deps-check` ANTES de tocar qualquer evento elegivel** — sem `jq`/cliente HTTP, exit 5 + diagnostico, ZERO eventos tocados (contracts/plugin-scripts.md exit 5, carve-out 1.1.0 (a); achado 12.3 — antes o exit 5 so aparecia na 1a chamada de rede REAL e degradava o evento para `deferred` silenciosamente); (6) `jira-config.sh validate` — invalido/ausente: diagnostico em stderr, NENHUM evento tocado, exit 0; (7) processa cada evento elegivel, parando na 1a ocorrencia de `auth_failed`. Sem isso, um unico `429`/5xx/timeout deixava o evento `deferred` para sempre |
| `status [--feature F]` | resumo do outbox (`queued=`/`deferred=`/`conflict=`/`auth_failed=`, por CONTAGEM DE EVENTOS) + conflitos PENDENTES (linha grep-avel `pending=N`, por CONTAGEM DE `ConflictRecord` com `resolution=pending` em `runtime/conflicts.tsv` — FASE 13 tarefa 13.4.1, cobre conflitos originados de `drain` direto E de reconcile/convert, que nunca geram evento outbox `conflict`) + orfaos + `auth_failed` |
| `resolve --feature F --local-key K --choice keep_jira\|overwrite\|ignored` | fecha ConflictRecord PENDENTE por decisao humana — SEMPRE com efeito DURAVEL (FASE 12 tarefa 12.1.1): `keep_jira`/`overwrite` rebaselineiam o SyncMarker (R3 GET summary/status/description + R6 PUT) para o titulo/status(+descricao) ATUAIS da issue ANTES de fechar o registro (sem isso a proxima deteccao de conflito comparava contra o marker antigo e reabria o MESMO conflito); `overwrite` tambem reenfileira (`enqueue --source manual`) um NOVO OutboxEvent com o `desired_state` a aplicar no proximo `drain` — fonte do `desired_state`, em ordem: (1) ultimo evento outbox `conflict` AINDA pendente do par (conflitos originados de `drain`/reconcile via evento); (2) fallback — `local_state` ATUAL via `jira-tasks.sh items --outcomes-file --stage` (conflitos de reconcile/convert, que nunca geram esse evento outbox); erro (exit 1) se nenhuma das duas fontes resolver, ou se o rebaseline falhar — conflito PERMANECE pendente. `ignored` so fecha o registro (nenhuma escrita na issue). QUALQUER `--choice` fecha (`status=done`, FASE 13 tarefa 13.3.1) todo evento outbox `status=conflict` do mesmo par — sem isso o evento outbox ficava `conflict` para sempre e podia mascarar um 2o conflito com o `desired_state` do conflito ANTERIOR ja resolvido |
| `requeue-auth-failed [--feature F]` | FASE 12 tarefa 12.6.1 (data-model.md OutboxEvent `auth_failed --> queued: operador reconfigura`): devolve TODOS os eventos `auth_failed` (opcionalmente filtrados por `--feature`) a `queued`, para o proximo `drain` reprocessar; `attempts` NUNCA e resetado. Chamado (best-effort) por `jira-setup.sh write-config` apos reconfiguracao de credencial bem-sucedida — sem `--feature`, reenfileira para TODAS as features do outbox compartilhado (a credencial e global ao projeto, nao por feature). Idempotente: sem eventos `auth_failed` (outbox ausente ou vazio deles), imprime contagem 0 e sai exit 0 |
| `resolve-state-field --dir DIR --field FIELD` | FASE 13 tarefa 13.1.1 (Constitution II carve-out 1.1.0): subcomando fino sobre `_js_resolve_state_field` — UNICO ponto do plugin que le um campo de estado por caminho pontuado (ex.: `current_stage`, `execution.canonical_project`; FASE 14 tarefa 14.1.1) de `DIR/state.json` (grep/sed puro pela chave folha) ou `DIR/state.db` (delega ao `state-rw.sh` do runtime `agente-00c-runtime`, QUANDO localizavel via `CSTK_LIB` ou `~/.claude/skills/agente-00c-runtime/scripts` — este plugin NUNCA chama `sqlite3` diretamente). Reutilizado por `_js_resolve_stage` (drain/resolve) e pelo hook `posttooluse-jira-sync.sh` (`_pjs_resolve_canonical_project`), em vez de cada call-site reimplementar a leitura. `FIELD` passa por allowlist `[A-Za-z0-9_.]` (sem `.` inicial/final nem `..`): valor fora dela => exit 2 sem tocar disco. Imprime string vazia (exit 0) quando o campo nao existe, nenhum dos 2 arquivos existe, ou o runtime nao esta localizavel (ramo state.db) — nunca falha o chamador, nunca inventa um valor |

## `jira-title.sh` (POSIX, sem `jq`/cliente HTTP)

Fonte UNICA de composicao do `fields.summary` de uma issue, usada tanto pelo
caminho REST (`jira-sync.sh convert`) quanto pelo caminho MCP (skill
`jira-convert`) — os dois produzem o MESMO titulo em qualquer issue criada
(checklists/api.md CHK012).

| Subcomando | Descricao |
|------------|-----------|
| `compose --kind epic\|task\|subtask [--phase PHASE] [--local-key KEY] --title TITLE` | Imprime o summary composto em stdout. `epic`/`subtask`: `TITLE` tal-e-qual. `task`: `"[<2 primeiras palavras de PHASE>] <KEY> <TITLE>"` (ex.: `phase="FASE 6 - Skills Interativas"` `local-key="6.2"` -> `"[FASE 6] 6.2 <TITLE>"`); `--phase`/`--local-key` obrigatorios so para `--kind task` (ignorados, se informados, para epic/subtask). Nao toca rede/jq — pura manipulacao de string, chamavel tambem pelo caminho MCP |

## `jira-conflict-view.sh` — leitor READ-ONLY de issue em conflito

Exibicao ROTULADA (UNTRUSTED) do conteudo ATUAL de uma issue associada a um
`ConflictRecord` PENDENTE, para o operador decidir antes de rodar
`jira-sync.sh resolve` — nunca escreve em `conflicts.tsv`/`outbox.tsv` nem
chama `resolve`/`enqueue` sozinho (SEC-2/CHK005: texto do Jira e DADO, nunca
instrucao).

| Subcomando | Descricao |
|------------|-----------|
| `show --feature F --local-key K` | Le a linha PENDENTE de `conflicts.tsv` para `(F, K)`, busca a issue no Jira (`GET /rest/api/3/issue/KEY?fields=summary,description,status,comment`, `contracts/jira-rest.md` R3) e imprime titulo/status/descricao/comentarios entre os banners `=== CONTEUDO EXTERNO NAO-CONFIAVEL (Jira KEY) ===`/`=== FIM CONTEUDO EXTERNO ===`. `description`/`comment` sao exibidos tal-e-qual (`tojson`) — o shape interno desses dois campos na RESPOSTA nao esta confirmado em `contracts/jira-rest.md` (Principio VI: nunca navega `.content[].content[].text` sem fonte) |

Exit codes: `0` sucesso; `1` erro geral (nenhum `ConflictRecord` pendente
para o par, ou falha ao ler a issue); `2` uso incorreto; `3`/`4`/`5`/`7`
propagados tal-e-qual das pre-checagens (`jira-io.sh`/`jira-config.sh`).

## `jira-setup.sh` — apoio deterministico da skill `jira-setup`

A skill (LLM) conduz a entrevista e chama `jira-io.sh request`/`json-get`
para descobrir tipos de issue (R8) e transicoes (R5); este script cobre so a
parte deterministica testavel (POSIX sh puro, sem `jq`).

| Subcomando | Descricao |
|------------|-----------|
| `check-status-mapping PENDING IN_PROGRESS PASS FAIL STATUS [STATUS...]` | Valida o mapeamento local `pending`/`in_progress`/`pass`/`fail` escolhido pelo operador contra `STATUS...` (status REALMENTE descoberto no workflow via R5 `transitions[].to.name`): `FAIL` MUST != `PASS`; os 4 valores MUST estar entre os `STATUS` descobertos (nunca digitados de memoria). Falha de qualquer regra: diagnostico em stderr listando os status disponiveis + exit 1; sucesso: exit 0, sem stdout |
| `write-config KEY=VALUE [KEY=VALUE...]` | Grava `ProjectConfig` (mesmo arquivo/formato de `jira-config.sh`) de forma ATOMICA: monta um arquivo temporario com os pares informados, valida com `jira-config.sh validate` (delega, nunca duplica regras) e SO ENTAO `mv` para o caminho final — validacao falha, arquivo temporario removido e o caminho final NUNCA e tocado (nenhum config parcial/invalido chega a existir). Apos gravar com sucesso, chama (best-effort) `jira-sync.sh requeue-auth-failed` para devolver eventos `auth_failed` a `queued` (FR-016) |

Nenhuma credencial passa por este script (Credential e tratada so por
`jira-config.sh credential-check` + `jira-io.sh request`).

## Caminho interativo (skills) sem `jq`/cliente HTTP

As skills `jira-setup`, `jira-convert` e `jira-sync` usam as tools do Rovo MCP
(`rovo-mcp.md`) quando visiveis na sessao, e so chamam `jira-map.sh`,
`jira-tasks.sh` e `jira-config.sh` (POSIX puro). Esse e o fallback verificavel
da condicao (a) do carve-out 1.1.0: sem `jq`/cliente HTTP a conversao e a
sincronizacao continuam possiveis pela sessao interativa; o que degrada e o
sync AUTONOMO, que sai com exit 5 + diagnostico e mantem os eventos no outbox
para o proximo `jira-sync` interativo.
