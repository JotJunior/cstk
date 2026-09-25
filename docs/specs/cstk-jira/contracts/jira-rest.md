# Contract: subconjunto da API REST do Jira Cloud usado pelo cstk-jira

Caminho REST (sync autonomo e fallback interativo). Base:
`https://<site_host>` (ProjectConfig; D1 = so Jira Cloud). Autenticacao:
Basic auth com email + API token (research Decision 2 — fonte:
https://developer.atlassian.com/cloud/jira/platform/basic-auth-for-rest-apis/,
"Supply an `Authorization` header with content `Basic` followed by the encoded string.").

**Regra de uso (Principio VI)**: o motor so pode usar metodo, path, parametro
ou campo que esteja nesta pagina com fonte. Linhas marcadas `NAO ENCONTRADO`
estao FORA do contrato; linhas marcadas `RECONFERIR` tem fonte secundaria
(aviso de mudanca/KB) e MUST ser reconferidas contra a pagina de referencia
ou uma chamada observada (quickstart cenario 6) antes de o codigo depender
delas.

## Operacoes (research.md Decision 3)

| ID | Operacao | Metodo + path | Fonte | Situacao |
|----|----------|---------------|-------|----------|
| R1 | criar issue | `POST /rest/api/3/issue` | https://community.developer.atlassian.com/t/deprecation-of-the-epic-link-parent-link-and-other-related-fields-in-rest-apis-and-webhooks/54048 | citado (OpenAPI v3, secao onda-005) |
| R2 | editar issue | `PUT /rest/api/3/issue/{issueIdOrKey}` | mesmo post + OpenAPI v3 (secao onda-005) | citado |
| R3 | ler issue | `GET /rest/api/3/issue/{issueIdOrKey}` | https://support.atlassian.com/jira/kb/retrieve-data-with-jira-rest-api-in-automation-to-update-issue-fields/ + OpenAPI v3 (secao onda-005) | citado (`fields.status`/`fields.issuetype` RECONFERIR) |
| R4 | transicionar | `POST /rest/api/3/issue/{issueIdOrKey}/transitions` | https://developer.atlassian.com/cloud/jira/platform/change-notice-update-in-simultaneous-transitions-issue-api/ + OpenAPI v3 (secao onda-005) | citado |
| R5 | listar transicoes | `GET /rest/api/3/issue/{issueIdOrKey}/transitions` | OpenAPI v3 (secao onda-005) | citado |
| R6 | gravar/ler propriedade de issue | `PUT` / `GET /rest/api/3/issue/{issueIdOrKey}/properties/{propertyKey}` (max 32 KB) | https://developer.atlassian.com/cloud/jira/platform/jira-entity-properties/ | citado |
| R7 | busca JQL | `GET`/`POST /rest/api/3/search/jql`, paginacao `nextPageToken`; `/rest/api/3/search` removido | https://confluence.atlassian.com/jirakb/run-jql-search-query-using-jira-cloud-rest-api-1289424308.html | citado |
| R8 | tipos de issue para criacao | `GET /rest/api/3/issue/createmeta/{projectIdOrKey}/issuetypes[/{issueTypeId}]` | https://community.developer.atlassian.com/t/create-issue-meta-endpoint-deprecation/75413 + OpenAPI v3 (secao onda-005) | citado |
| R9 | criar filtro | `POST /rest/api/3/filter` com `name`, `jql` | https://support.atlassian.com/jira/kb/creating-and-granting-edit-permission-for-filters-in-team-managed-projects-via-rest-api/ | citado |
| R10 | criar board | `POST /rest/agile/1.0/board` com `name`, `type` (`scrum`/`kanban`), `filterId`, `location` | https://developer.atlassian.com/cloud/jira/software/rest/api-group-board/ | citado |
| R11 | boards do projeto | `GET /rest/agile/1.0/board?projectKeyOrId=...` | mesma pagina de R10 | citado |

Hierarquia (R1): campo `parent` liga filho ao Epic; Epic Link
(`customfield_10014`) descontinuado; `hierarchyLevel` -1/0/1 (post de R1).

**Fora do contrato (`NAO ENCONTRADO` em research)**: endpoint de changelog da
issue; citacao literal do campo `updated`; citacao de que Sub-task usa
`parent`; path v3 de criacao de projeto.

**Metodos proibidos**: qualquer `DELETE` (FR-012). `jira-io.sh` aceita so
`GET`/`POST`/`PUT`.

## Comportamentos de erro com fonte

| Situacao | Comportamento | Fonte |
|----------|---------------|-------|
| rate limit | HTTP 429 + header `Retry-After`; limite por issue de escrita | https://developer.atlassian.com/cloud/jira/platform/rate-limiting/ ("20 write operations per 2 seconds") |
| transicoes simultaneas na mesma issue | so uma vence; demais 400 (mudanca planejada para 409) | change-notice de R4 |

## Complemento de fontes (onda-004)

Pesquisa dirigida da onda-004 (acesso 2026-09-24). As paginas de referencia
`api-group-*` e o `swagger-v3.v3.json` vieram TRUNCADAS pelo WebFetch (o spec
nao chegou a `paths`); o download direto do spec pela shell foi barrado pelo
`bash-guard` (host fora de `.claude/agente-00c-whitelist`, arquivo inexistente
neste projeto). Resultado:

| Item | Status | Fonte / citacao |
|------|--------|-----------------|
| R4 path v3 `POST /rest/api/3/issue/{issueIdOrKey}/transitions` | CONFIRMADO | change-notice de R4: "transitions requested via the Transition Issue API (/POST /rest/api/3/issue/{issueIdOrKey}/transitions) are blocked ... we will soon be replacing the 400 (Bad Request) status code with 409 (Conflict)." — "it should employ a retry mechanism." |
| R5 path v3 `GET .../transitions` retorna array `transitions` | CONFIRMADO (path + nome do array) | https://community.developer.atlassian.com/t/how-to-update-jira-issue-status-using-apis/87909 (staff Atlassian): "This will return an array called `transitions`." |
| R6 limites da propriedade | CONFIRMADO | jira-entity-properties: "The maximum length of an entity property value is 32768 bytes."; "The value stored in each property must be in valid JSON format."; "The maximum length of an entity property key is 255 bytes." |
| 429 + `Retry-After` em segundos | CONFIRMADO | rate-limiting: "When any limit is exceeded, Jira returns an HTTP `429 Too Many Requests` response."; `Retry-After`: "Only returned with 429 responses. Indicates how many seconds to wait before retrying." |
| login recusado sem checar senha (CAPTCHA) | CONFIRMADO | basic-auth-for-rest-apis: "If there is an `X-Seraph-LoginReason` header with a value of `AUTHENTICATION_DENIED`, the application rejected the login without even checking the password." => tratar como `auth_failed` |
| todo status pertence a uma de 3 categorias | CONFIRMADO | https://support.atlassian.com/jira-cloud-administration/docs/what-is-a-workflow-status/: "All statuses, even custom statuses you create yourself, must belong to one of three status categories – To do, In progress, or Done." |
| base do site `https://<dominio>.atlassian.net` | CONFIRMADO | basic-auth-for-rest-apis: exemplo `https://your-domain.atlassian.net/rest/api/2/issue/createmeta` |
| **corpo de R1** (nomes de `fields.*`: projeto, titulo, tipo, `parent`, descricao em ADF) | **NAO ENCONTRADO para Cloud v3** | so ha exemplo de Server/DC API v2 (fora de D1) — nao vale como fonte |
| **corpo de R4** (identificador da transicao) e codigo de sucesso | **NAO ENCONTRADO** | — |
| **resposta de R3** (campos de status/titulo, parametro `fields`) | **NAO ENCONTRADO** | — |
| **elemento de `transitions`** (id, nome, status destino/categoria) | **NAO ENCONTRADO** | chaves de categoria `new`/`indeterminate`/`done` so em pagina Server |
| endpoint de "usuario corrente" p/ validar credencial; 401 vs 403 | **NAO ENCONTRADO** | — |
| formato final de R7 (`search/jql`) | **NAO ENCONTRADO** (so RFC-61, proposta) | — |
| Sub-task com `hierarchyLevel` -1 via `parent` em Cloud | **NAO ENCONTRADO** | — |

**Consequencia (Principio VI)**: na onda-004 os nomes de campo de
corpo/resposta de R1, R3, R4, R5 e R8 NAO estavam neste contrato (bloqueio
humano block-005). Resolvido na onda-005 — ver secao seguinte. As linhas
`NAO ENCONTRADO` acima que a secao seguinte resolve estao marcadas la como
SUPERADAS; as demais continuam fora do contrato.

## Campos de request/response a partir do OpenAPI oficial (onda-005)

**Fonte unica desta secao**: OpenAPI oficial do Jira Cloud REST v3,
`https://developer.atlassian.com/cloud/jira/platform/swagger-v3.v3.json`
(baixado em 2026-09-24 via `curl`, HTTP 200, 2473752 bytes;
`openapi: 3.0.1`; `info.version: 1001.0.0-SNAPSHOT-44cdd07c042959317ed5591bf79dbcd9369f3610`;
sha256 `6ecc461bb85e92a46331a4316b6c63c91c16ed6baf5f06b03ab616da3f1ab3d7`;
423 paths — metadados observados na saida de `curl -w`/`shasum`/`jq` desta
onda e registrados como evidencia na Decisao dec-031 do state da execucao).
O download foi autorizado pelo operador (block-005 / dec-029, no mesmo state).
Cada linha abaixo cita o path JSON no arquivo; `S:` abrevia
`components.schemas`, `P:` abrevia `paths`. Campos marcados **(exemplo)**
aparecem no `example` oficial do endpoint mas NAO no schema (o objeto
`fields` e livre no schema) — valem como fonte do NOME, e o motor MUST
reconferi-los na primeira chamada observada (quickstart cenario 6).

### R1 — criar issue: `POST /rest/api/3/issue` (operationId `createIssue`, `deprecated: false`)

| Elemento | Valor | Path JSON |
|----------|-------|-----------|
| corpo | schema `IssueUpdateDetails` (propriedades `fields` objeto, `update`, `transition`, `properties`, `historyMetadata`; nenhuma obrigatoria no schema) | `P:./rest/api/3/issue.post.requestBody.content.application/json.schema` → `S:.IssueUpdateDetails` |
| `fields.project` | `{"id": "<string>"}` **(exemplo)** — forma por `key` NAO ENCONTRADA no spec | `P:./rest/api/3/issue.post.requestBody.content.application/json.example.fields.project` |
| `fields.issuetype` | `{"id": "<string>"}` **(exemplo)** | `...example.fields.issuetype` |
| `fields.summary` | string **(exemplo)** | `...example.fields.summary` |
| `fields.parent` | `{"key": "<chave>"}` **(exemplo)**; descricao: "`parent` must contain the ID or key of the parent issue." (subtask); "In a next-gen project any issue may be made a child providing that the parent and child are members of the same project." | `...example.fields.parent`; `P:./rest/api/3/issue.post.description` |
| `fields.description` | Atlassian Document Format: `{"type":"doc","version":1,"content":[{"type":"paragraph","content":[{"type":"text","text":"..."}]}]}` **(exemplo)**; descricao: "the `description`, `environment`, and any `textarea` type custom fields (multi-line text fields) take Atlassian Document Format content." | `...example.fields.description`; `P:./rest/api/3/issue.post.description` |
| sub-task | "`issueType` must be set to a subtask issue type" + `parent` com ID ou key (SUPERA o `NAO ENCONTRADO` de "Sub-task usa `parent`") | `P:./rest/api/3/issue.post.description` |
| query | `updateHistory` (boolean, default `false`) — nao usado pelo motor | `P:./rest/api/3/issue.post.parameters` |
| sucesso | `201` → `CreatedIssue` com `id` (string), `key` (string), `self` (string) | `P:./rest/api/3/issue.post.responses.201` → `S:.CreatedIssue.properties` |
| erros | `400` (campos obrigatorios ausentes/invalidos, sem permissao, subtask em projeto diferente do pai...), `401` "authentication credentials are incorrect or missing", `403` "does not have the necessary permission", `422` "configuration problem" — corpo `ErrorCollection` (`errorMessages` string[], `errors` objeto string→string, `status` integer) | `P:./rest/api/3/issue.post.responses` ; `S:.ErrorCollection.properties` |

Resolucao do `project.id` (necessario porque o spec so exemplifica `id`):
`GET /rest/api/3/project/{projectIdOrKey}` (operationId `getProject`,
`deprecated: false`) → `200` schema `Project` com `id` (string) e `key`
(string); `401`/`404` sem corpo tipado (`P:./rest/api/3/project/{projectIdOrKey}.get`,
`S:.Project.properties.id`). Gravado no setup junto com os ids de tipo.

### R2 — editar issue: `PUT /rest/api/3/issue/{issueIdOrKey}` (operationId `editIssue`)

Corpo `IssueUpdateDetails` (mesmo de R1). Sucesso `204` ("Returned if the
request is successful."; `200` so com `returnIssue=true`). Erros
`400`/`401`/`403`/`404`/`409`/`422` (`P:./rest/api/3/issue/{issueIdOrKey}.put.responses`).
Situacao de R2 passa de RECONFERIR para citado.

### R3 — ler issue: `GET /rest/api/3/issue/{issueIdOrKey}` (operationId `getIssue`)

| Elemento | Valor | Path JSON |
|----------|-------|-----------|
| query `fields` | array; "accepts a comma-separated list"; exemplo literal "`summary,comment` Returns only the summary and comments fields." | `P:./rest/api/3/issue/{issueIdOrKey}.get.parameters[name=fields]` |
| sucesso | `200` → `IssueBean`: `id`, `key`, `self` (string), `fields` (objeto livre) | `...get.responses.200` → `S:.IssueBean.properties` |
| `fields.summary` | string — tipado em `S:.Fields.properties.summary` (campos-chave de issue ligada) e id `summary` no exemplo de `GET /rest/api/3/field` | `S:.Fields.properties.summary`; `P:./rest/api/3/field.get.responses.200...example[].id` |
| `fields.status` | `StatusDetails`: `id`, `name`, `statusCategory` (`StatusCategory`: `id` integer, `key` string, `name` string) — tipado em `S:.Fields.properties.status`; em `IssueBean.fields` o objeto e livre => RECONFERIR na 1a chamada observada | `S:.Fields.properties.status` → `S:.StatusDetails`, `S:.StatusCategory` |
| `fields.issuetype` | `IssueTypeDetails` (`S:.Fields.properties.issuetype`) — mesma ressalva | idem |
| `fields.updated` | nome presente no exemplo de `200` (valor de exemplo `1`, tipo NAO determinavel) **(exemplo)** — SUPERA o `NAO ENCONTRADO` do nome; tipo/formato continua RECONFERIR | `...get.responses.200.content.application/json.example.fields.updated` |
| erros | `401` (credencial), `404` (issue inexistente ou sem permissao de ver) | `...get.responses` |

### R4 — executar transicao: `POST /rest/api/3/issue/{issueIdOrKey}/transitions` (operationId `doTransition`)

| Elemento | Valor | Path JSON |
|----------|-------|-----------|
| corpo | `IssueUpdateDetails`; o motor envia SO `{"transition": {"id": "<id>"}}` (exemplo usa `"id": "5"`) | `...transitions.post.requestBody.content.application/json.example.transition` |
| `transition.id` | string — "The ID of the issue transition. Required when specifying a transition to undertake." | `S:.IssueTransition.properties.id` |
| sucesso | `204` "Returned if the request is successful." (sem corpo) | `...transitions.post.responses.204` |
| erros | `400` (nenhuma transicao, sem permissao, campo fora da tela...), `401`, `404`, `409` "could not be updated due to a conflicting update", `413` (limite por issue), `422` | `...transitions.post.responses` |

`409` no spec confirma o change-notice (400 → 409 em transicoes simultaneas):
o motor MUST tratar `400` e `409` desta operacao como candidatos a retry.

### R5 — listar transicoes: `GET /rest/api/3/issue/{issueIdOrKey}/transitions` (operationId `getTransitions`)

| Elemento | Valor | Path JSON |
|----------|-------|-----------|
| sucesso | `200` → `Transitions` com `transitions` (array de `IssueTransition`) | `...transitions.get.responses.200` → `S:.Transitions.properties` |
| elemento | `id` (string), `name` (string), `to` (`StatusDetails`: `id`, `name`, `statusCategory`), `isAvailable` (boolean), `hasScreen` (boolean), `isConditional`, `isGlobal`, `isInitial`, `looped` | `S:.IssueTransition.properties` (SUPERA o `NAO ENCONTRADO` do elemento) |
| query | `transitionId`, `expand`, `includeUnavailableTransitions` (default `false`), `skipRemoteOnlyCondition`, `sortByOpsBarAndStatus` | `...transitions.get.parameters` |
| erros | `401`, `404` | `...transitions.get.responses` |

Valores de `statusCategory.key`: o schema NAO define enum
(`S:.StatusCategory.properties.key` = string, "The key of the status
category."). Os exemplos oficiais trazem `in-flight`, `completed` e `DONE`
(inconsistentes entre si) — NAO sao lista normativa. O motor NAO decide por
categoria: mapeia por status alvo configurado (`status_*` em ProjectConfig,
comparado a `to.name`/`to.id`). Valores de categoria seguem **NAO ENCONTRADO**.

### R7 — busca JQL (refinamento)

`GET`/`POST /rest/api/3/search/jql` (`deprecated: false`): query `jql`,
`nextPageToken`, `maxResults` (default `50`), `fields` (array), `properties`
(`P:./rest/api/3/search/jql.get.parameters`); `200` →
`SearchAndReconcileResults` com `issues` (array de `IssueBean`),
`nextPageToken` (string), `isLast` (boolean)
(`S:.SearchAndReconcileResults.properties`) — SUPERA o `NAO ENCONTRADO` do
formato de R7. `/rest/api/3/search` (GET/POST) consta com `deprecated: true`
e descricao "Endpoint is currently being removed." — o motor NAO o usa.

### R8 — tipos de issue para criacao

| Elemento | Valor | Path JSON |
|----------|-------|-----------|
| lista | `GET /rest/api/3/issue/createmeta/{projectIdOrKey}/issuetypes` (operationId `getCreateIssueMetaIssueTypes`, `deprecated: false`); query `startAt` (default `0`), `maxResults` (default `50`) | `P:./rest/api/3/issue/createmeta/{projectIdOrKey}/issuetypes.get` |
| resposta da lista | `200` → `PageOfCreateMetaIssueTypes`: `issueTypes` e `createMetaIssueType` (ambos array de `IssueTypeIssueCreateMetadata`), `startAt`, `maxResults`, `total` | `S:.PageOfCreateMetaIssueTypes.properties` |
| elemento | `id` (string), `name` (string), `hierarchyLevel` (integer, "Hierarchy level of the issue type."), `subtask` (boolean, "Whether this issue type is used to create subtasks.") | `S:.IssueTypeIssueCreateMetadata.properties` |
| campos de um tipo | `GET .../issuetypes/{issueTypeId}` (operationId `getCreateIssueMetaIssueTypeId`) → `PageOfCreateMetaIssueTypeWithField`: `fields`/`results` (array de `FieldCreateMetadata`: obrigatorios `fieldId`, `key`, `name`, `operations`, `required`, `schema`) | `S:.PageOfCreateMetaIssueTypeWithField.properties`, `S:.FieldCreateMetadata.required` |
| erros | `400`, `401` | `...issuetypes.get.responses` |

Qual das duas listas (`issueTypes` vs `createMetaIssueType`) vem preenchida
na resposta real NAO e determinavel pelo schema => o motor le a que vier
nao-vazia e a 1a chamada observada (quickstart cenario 6) fixa o comportamento.
Identificacao de Epic/Task/Sub-task no setup: `subtask=true` => candidato a
Sub-task (descricao do schema). Qual valor de `hierarchyLevel` corresponde a
Epic NAO ENCONTRADO nas fontes (o spec nao traz exemplo com Epic; o post de R1
so cita o intervalo -1/0/1) => o setup MUST listar os tipos (`id`, `name`,
`hierarchyLevel`, `subtask`) e o OPERADOR confirma qual e Epic, Task e
Sub-task antes de gravar `issue_type_*` [PROPOSTA — a validar na implementacao].

### Validacao de credencial (SUPERA `NAO ENCONTRADO`)

`GET /rest/api/3/myself` (operationId `getCurrentUser`) → `200` schema
`User`; `401` "Returned if the authentication credentials are incorrect or
missing." (`P:./rest/api/3/myself.get.responses`) — `401` => `auth_failed`.
`403` em R1/R2 = "does not have the necessary permission" => erro de
permissao, NAO de credencial.

### Continua fora do contrato apos a onda-005

Endpoint de changelog; tipo/formato de `fields.updated`; valores de
`statusCategory.key`; forma `fields.project.key` em R1; path v3 de criacao de
projeto.
