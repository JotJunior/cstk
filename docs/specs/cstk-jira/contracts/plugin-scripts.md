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
| `request METHOD PATH [--body-file F] [--op OP]` | METHOD em `GET`/`POST`/`PUT` (allowlist fechada — nao existe `DELETE`, FR-012); PATH relativo iniciado em `/rest/`; `OP` opcional em `R1`..`R11` (contracts/jira-rest.md) — informa qual operacao esta sendo servida, so usado para classificar `403`/`400`/`409` (dec-073) | corpo da resposta em stdout SO no caminho de sucesso; status HTTP + classificacao estruturada (`http_status=`/`classification=`/`retry_after=`) em stderr | monta `https://<site_host><PATH>`; valida host por IGUALDADE exata (sem userinfo, sem porta) antes de cada requisicao; NAO segue redirect para host diferente (FR-015); credencial passada ao cliente HTTP por arquivo de config temporario `0600` removido em `trap`, nunca em argv; SEC-1: PATH recusado (exit 2, sem requisicao) se contiver `..`, `//`, `\`, `@`, `#`, espaco, CR/LF ou qualquer outro byte de controle; ver "Mapeamento de status HTTP" abaixo para a classificacao de falha (3.4) |
| `validate-segment VALUE [VALUE...]` | 1+ VALUE (ex.: `jira_id`/`jira_key`/`project_key`) | nada (so exit code) | SEC-1: valida cada VALUE contra a allowlist fechada de charset `[A-Za-z0-9_-]`, nao-vazio; exit 2 no primeiro que falhar. O motor (`jira-sync.sh`/`jira-map.sh`, FASE 4+) MUST chamar isto para cada segmento ANTES de interpolar PATH ou JQL — nao exige `jq`/cliente HTTP |
| `json-get FILTER` | JSON em stdin | valor em stdout | wrapper de leitura (restringe `jq` a este arquivo); `jq -r FILTER`; filtro/entrada invalidos => exit 2; so exige `jq` (nao exige cliente HTTP/ProjectConfig/credencial) |
| `json-build issue --project-id ID --issuetype-id ID --summary TEXT [--parent-key KEY] [--description TEXT]` | ids/keys (SEC-1: mesma allowlist `[A-Za-z0-9_-]` de `validate-segment`); summary/description texto livre | JSON em stdout | monta o corpo de R1 (`contracts/jira-rest.md`): `fields.project.id`, `fields.issuetype.id`, `fields.summary`, `fields.parent.key` (opcional), `fields.description` em ADF (opcional); summary/description via `jq --arg` (nunca concatenacao de string); id/key fora da allowlist => exit 2 sem montar corpo |
| `json-build filter --name TEXT --project-key KEY` | `--project-key` (SEC-1); `--name` texto livre | JSON em stdout | monta o corpo de R9 (`contracts/jira-rest.md`): `{"name":..., "jql":"project = \"KEY\""}`; SEC-3: `--project-key` MUST passar pela allowlist SEC-1 ANTES de entrar na JQL — recusado (exit 2) sem montar JQL alguma; `--name` nunca e interpolado em `jql`; base da JQL do filtro do board (FR-013) |
| `json-build issue-update --summary TEXT [--description TEXT]` | summary/description texto livre | JSON em stdout | monta o corpo de R2 (`contracts/jira-rest.md`, feature cstk-jira FASE 10 tarefa 10.2/FR-003): `{"fields":{"summary":...}}` (+ `description` em ADF, opcional) — SEM `project`/`issuetype`/`parent` (imutaveis numa edicao); summary/description via `jq --arg` |

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
| `relink --feature F --local-key K --jira-key KEY` | religa um orfao por decisao humana; exige que `KEY` confira com o `jira_key` ja armazenado (confirmacao explicita de qual card) |

## `jira-sync.sh` — motor

| Subcomando | Descricao |
|------------|-----------|
| `plan --feature F` | dry-run: lista criacoes, atualizacoes, transicoes, orfaos e conflitos previstos, sem rede de escrita |
| `convert --feature F` | US1: cria Epic, depois Tasks (filhas do Epic), depois Sub-tasks, gravando o mapeamento item a item; pre-condicao: `deps-check`, `validate`, `credential-check` e validacao de credencial remota — qualquer falha aborta ANTES da 1a criacao (US1 cenario 3: sem artefato parcial por credencial invalida). Para Task (nunca Epic/Sub-task), compoe `fields.description` (FR-001, `_js_build_task_description`) com criticidade (coluna `criticality` de `items`) e dependencias (`jira-tasks.sh phase-deps`), quando existirem; nenhum dos dois presente = `--description` omitido do `json-build issue`. Item JA mapeado (`active`) NUNCA e recriado — `_js_maybe_update_mapped_issue` (FR-003, feature cstk-jira FASE 10 tarefa 10.2; description estendida na FASE 12 tarefa 12.5.1) checa se o summary E/OU a description compostos AGORA divergem do summary/description atuais da issue (R3 `fields=summary,status[,description]` — description so lida quando o item carrega uma, kind=task com criticidade/dependencias); se sim, le o SyncMarker (R6) e SO escreve (R2 + regrava o SyncMarker) quando `sha256(summary atual) == written_summary_sha256` E (sem componente de description OU sem baseline de description no marker OU `sha256(description atual) == written_description_sha256`) — nenhuma edicao manual desde a ultima sync, nem de titulo nem de descricao; marker ausente ou qualquer um desses hashes divergente => `ConflictRecord` (`marker_missing`/`manual_edit`), NUNCA sobrescreve (FR-011, mesma logica de deteccao de `_js_process_one_event`/drain). Uma mudanca SO de criticidade/dependencias (summary inalterado) agora tambem dispara o R2 (achado 12.5 — antes ficava presa por um early-exit que so olhava o summary). `orphan` no mapeamento nunca e tocado (nem criado, nem atualizado) — so `relink` humano (FASE 4.3/4.4) |
| `enqueue --feature F --local-key K --state S --source SRC` | append no outbox; quando `S` e `pass`/`fail` e `K` != `*`, tambem persiste `K/S` no sidecar `runtime/task-outcomes.tsv` (FASE 12 tarefa 12.4.1) — fonte que `_js_process_reconcile_event` filtra por feature e repassa via `jira-tasks.sh items --outcomes-file` na reconciliacao seguinte, dando ao outcome de `record_task` precedencia sobre os checkboxes (data-model.md LocalWorkItem outcome precedence) |
| `drain --feature F` | processa o outbox com lock `runtime/.drain.lock/`; para cada item: le issue + SyncMarker, detecta conflito, transiciona para o status mapeado, regrava SyncMarker. Evento `local_key=*` (`desired_state=reconcile`, feature cstk-jira FASE 10 tarefa 10.3, FR-004) e expandido via `jira-tasks.sh items --feature F` (`_js_process_reconcile_event`) num item por Epic/Task/Sub-task ja mapeado (`active`), cada um passando pelo MESMO fluxo de deteccao de conflito/transicao; conflito em um item nunca bloqueia os demais (ConflictRecord por item); `auth_failed` em qualquer item interrompe a reconciliacao inteira; sem `auth_failed`/`deferred`, o evento `*` fecha `done` |
| `status [--feature F]` | resumo do outbox + conflitos + orfaos + `auth_failed` |
| `resolve --feature F --local-key K --choice keep_jira\|overwrite\|ignored` | fecha ConflictRecord por decisao humana |

## Caminho interativo (skills) sem `jq`/cliente HTTP

As skills `jira-setup`, `jira-convert` e `jira-sync` usam as tools do Rovo MCP
(`rovo-mcp.md`) quando visiveis na sessao, e so chamam `jira-map.sh`,
`jira-tasks.sh` e `jira-config.sh` (POSIX puro). Esse e o fallback verificavel
da condicao (a) do carve-out 1.1.0: sem `jq`/cliente HTTP a conversao e a
sincronizacao continuam possiveis pela sessao interativa; o que degrada e o
sync AUTONOMO, que sai com exit 5 + diagnostico e mantem os eventos no outbox
para o proximo `jira-sync` interativo.
