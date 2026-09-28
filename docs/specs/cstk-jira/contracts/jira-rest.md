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
| R3 | ler issue | `GET /rest/api/3/issue/{issueIdOrKey}` | https://support.atlassian.com/jira/kb/retrieve-data-with-jira-rest-api-in-automation-to-update-issue-fields/ + OpenAPI v3 (secao onda-005) | citado (`fields.status`/`fields.issuetype`/`fields.updated` CONFIRMADO roundtrip onda-011) |
| R4 | transicionar | `POST /rest/api/3/issue/{issueIdOrKey}/transitions` | https://developer.atlassian.com/cloud/jira/platform/change-notice-update-in-simultaneous-transitions-issue-api/ + OpenAPI v3 (secao onda-005) | citado |
| R5 | listar transicoes | `GET /rest/api/3/issue/{issueIdOrKey}/transitions` | OpenAPI v3 (secao onda-005) | citado |
| R6 | gravar/ler propriedade de issue | `PUT` / `GET /rest/api/3/issue/{issueIdOrKey}/properties/{propertyKey}` (max 32 KB) | https://developer.atlassian.com/cloud/jira/platform/jira-entity-properties/ | citado |
| R7 | busca JQL | `GET`/`POST /rest/api/3/search/jql`, paginacao `nextPageToken`; `/rest/api/3/search` removido | https://confluence.atlassian.com/jirakb/run-jql-search-query-using-jira-cloud-rest-api-1289424308.html | citado |
| R8 | tipos de issue para criacao | `GET /rest/api/3/issue/createmeta/{projectIdOrKey}/issuetypes[/{issueTypeId}]` | https://community.developer.atlassian.com/t/create-issue-meta-endpoint-deprecation/75413 + OpenAPI v3 (secao onda-005) | citado |
| R9 | criar filtro | `POST /rest/api/3/filter` com `name`, `jql` | https://support.atlassian.com/jira/kb/creating-and-granting-edit-permission-for-filters-in-team-managed-projects-via-rest-api/ | campos confirmados (OpenAPI onda-029, secao abaixo) |
| R10 | criar board | `POST /rest/agile/1.0/board` com `name`, `type` (`scrum`/`kanban`), `filterId`, `location` | https://developer.atlassian.com/cloud/jira/software/rest/api-group-board/ | campos confirmados (OpenAPI onda-029, secao abaixo) |
| R11 | boards do projeto | `GET /rest/agile/1.0/board?projectKeyOrId=...` | mesma pagina de R10 | campos confirmados (OpenAPI onda-029, secao abaixo) |

Hierarquia (R1): campo `parent` liga filho ao Epic; Epic Link
(`customfield_10014`) descontinuado; `hierarchyLevel` -1/0/1 (post de R1).

**Fora do contrato (`NAO ENCONTRADO` em research)**: endpoint de changelog da
issue; citacao literal do campo `updated`; citacao de que Sub-task usa
`parent`; path v3 de criacao de projeto (SUPERADO no plan r02 — ver R18).

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
| `fields.project` | `{"id": "<string>"}` **CONFIRMADO (roundtrip onda-011)** — `{"id": "10000"}` aceito, `201` (issue `SCRUM-5`, projeto `SCRUM`/"CSTK Playground"); forma por `key` continua NAO TESTADA | `P:./rest/api/3/issue.post.requestBody.content.application/json.example.fields.project` |
| `fields.issuetype` | `{"id": "<string>"}` **CONFIRMADO (roundtrip onda-011)** — `{"id": "10001"}` (Epic) e `{"id": "10004"}` (Story) aceitos | `...example.fields.issuetype` |
| `fields.summary` | string **CONFIRMADO (roundtrip onda-011)** | `...example.fields.summary` |
| `fields.parent` | `{"key": "<chave>"}` **CONFIRMADO (roundtrip onda-011)** — `{"key": "SCRUM-5"}` aceito ao criar a Story `SCRUM-6` (Epic→Story em projeto next-gen); descricao: "`parent` must contain the ID or key of the parent issue." (subtask); "In a next-gen project any issue may be made a child providing that the parent and child are members of the same project." | `...example.fields.parent`; `P:./rest/api/3/issue.post.description` |
| `fields.description` | Atlassian Document Format: `{"type":"doc","version":1,"content":[{"type":"paragraph","content":[{"type":"text","text":"..."}]}]}` **CONFIRMADO (roundtrip onda-011)** — aceito tal-e-qual nas duas issues de teste; descricao: "the `description`, `environment`, and any `textarea` type custom fields (multi-line text fields) take Atlassian Document Format content." | `...example.fields.description`; `P:./rest/api/3/issue.post.description` |
| sub-task | "`issueType` must be set to a subtask issue type" + `parent` com ID ou key (SUPERA o `NAO ENCONTRADO` de "Sub-task usa `parent`"); o roundtrip onda-011 confirmou `parent` para Epic→Story — issuetype `subtask=true` dedicado (`Subtask`, id `10002`, `hierarchyLevel -1`) NAO foi exercitado nesta onda | `P:./rest/api/3/issue.post.description` |
| query | `updateHistory` (boolean, default `false`) — nao usado pelo motor | `P:./rest/api/3/issue.post.parameters` |
| sucesso | `201` → `CreatedIssue` com `id` (string), `key` (string), `self` (string) — **CONFIRMADO (roundtrip onda-011)**: resposta real `{"id":"10004","key":"SCRUM-5","self":"https://cstk.atlassian.net/rest/api/3/issue/10004"}` bate exatamente com o schema | `P:./rest/api/3/issue.post.responses.201` → `S:.CreatedIssue.properties` |
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
| `fields.status` | `StatusDetails`: `id`, `name`, `statusCategory` (`StatusCategory`: `id` integer, `key` string, `name` string) — **CONFIRMADO (roundtrip onda-011)**: `SCRUM-6` retornou `{"id":"10000","name":"To Do","statusCategory":{"id":2,"key":"new","colorName":"blue-gray","name":"To Do"}, ...}` (shape bate; `colorName` extra nao documentado no schema mas presente na resposta real) | `S:.Fields.properties.status` → `S:.StatusDetails`, `S:.StatusCategory` |
| `fields.issuetype` | `IssueTypeDetails` (`S:.Fields.properties.issuetype`) — **CONFIRMADO (roundtrip onda-011)**: `SCRUM-6` retornou `{"id":"10004","name":"Story","subtask":false,"hierarchyLevel":0, ...}` | idem |
| `fields.updated` | nome presente no exemplo de `200` (valor de exemplo `1`, tipo NAO determinavel) **CONFIRMADO (roundtrip onda-011)** — tipo `string`, formato Jira datetime com milissegundos e offset de fuso: valor real observado `"2026-09-25T22:42:39.399-0300"` (`SCRUM-6`) | `...get.responses.200.content.application/json.example.fields.updated` |
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
| elemento | `id` (string), `name` (string), `to` (`StatusDetails`: `id`, `name`, `statusCategory`), `isAvailable` (boolean), `hasScreen` (boolean), `isConditional`, `isGlobal`, `isInitial`, **`isLooped`** (CORRIGIDO — ver nota abaixo) | `S:.IssueTransition.properties` (SUPERA o `NAO ENCONTRADO` do elemento) — **CONFIRMADO (roundtrip onda-011)** contra `GET /rest/api/3/issue/SCRUM-6/transitions` |
| query | `transitionId`, `expand`, `includeUnavailableTransitions` (default `false`), `skipRemoteOnlyCondition`, `sortByOpsBarAndStatus` | `...transitions.get.parameters` |
| erros | `401`, `404` | `...transitions.get.responses` |

**CONTRADITO pelo roundtrip onda-011 (Principio VI, `--score 3`, ver Decisao
dec-057 do state da execucao)**: o schema `S:.IssueTransition.properties`
citado no OpenAPI (onda-005) foi lido como campo `looped`; a resposta REAL de
`GET /rest/api/3/issue/SCRUM-6/transitions` traz o campo como `isLooped`
(evidencia literal: `"isLooped": false` em todos os 4 elementos do array
`transitions`, id `11`/`21`/`31`/`41`). O nome correto e `isLooped` — corrigido
acima; o motor MUST usar `isLooped`, nunca `looped`.

Valores de `statusCategory.key`: o schema NAO define enum
(`S:.StatusCategory.properties.key` = string, "The key of the status
category."). Os exemplos oficiais trazem `in-flight`, `completed` e `DONE`
(inconsistentes entre si) — NAO sao lista normativa. O motor NAO decide por
categoria: mapeia por status alvo configurado (`status_*` em ProjectConfig,
comparado a `to.name`/`to.id`). Valores de categoria seguem **NAO ENCONTRADO**.

### R6 — propriedade de issue (SyncMarker): `GET`/`PUT /rest/api/3/issue/{issueIdOrKey}/properties/{propertyKey}` (operationId `getIssueProperty`/`setIssueProperty`) — CONFIRMADO (OpenAPI onda-005 + roundtrip onda-022, resolve dec-079)

| Elemento | Valor | Path JSON |
|----------|-------|-----------|
| GET sucesso | `200` → schema `EntityProperty`: `key` (string), `value` (tipo livre — "Required on create and update", sem schema fixo) | `S:.EntityProperty.properties` — **CONFIRMADO por roundtrip** |
| GET erros | `401`, `404` | `...properties/{propertyKey}.get.responses` |
| PUT corpo | o corpo da requisicao E o `value` CRU (schema `{}` — nenhum envelope; nao e `{key,value}`), max 32768 bytes | `...properties/{propertyKey}.put.requestBody` |
| PUT sucesso | `200` (propriedade atualizada) OU `201` (propriedade criada) — ambos com corpo VAZIO (schema `{}` sem `example`) | `...properties/{propertyKey}.put.responses` |
| PUT erros | `400`, `401`, `403`, `404` | `...properties/{propertyKey}.put.responses` |

**CONFIRMADO por roundtrip real (onda-022, resolve dec-079)**: `PUT
/rest/api/3/issue/SCRUM-5/properties/cstk-jira.sync` com corpo
`{"synced_at":"2026-09-26T00:00:00Z","checksum":"r6-roundtrip-test"}` (Epic de
teste `SCRUM-5`, mesmo criado no roundtrip onda-011) devolveu `201` com corpo
vazio (primeira gravacao — propriedade nao existia). Uma segunda `PUT` na
mesma chave com valor diferente devolveu `200` com corpo vazio (atualizacao) —
confirma a distincao `200`=update/`201`=create do OpenAPI, ambos sem payload
util. Em seguida, `GET
/rest/api/3/issue/SCRUM-5/properties/cstk-jira.sync` devolveu `200` com corpo
`{"key":"cstk-jira.sync","value":{"synced_at":"2026-09-26T00:05:00Z","checksum":"r6-roundtrip-test-2"}}`
— confirma o envelope `EntityProperty` (`key`+`value`) do OpenAPI, com `value`
igual ao ultimo corpo gravado via PUT (nao ao primeiro), ou seja PUT faz
overwrite total do `value`, nao merge. O motor (SyncMarker) MUST: (a) ler o
marker via `GET`, desembrulhar `.value` (nunca tratar a resposta inteira como
o marker); (b) gravar via `PUT` enviando SOMENTE o `value` cru (sem envelope
`{key,value}` — a chave ja vai na URL); (c) tratar `200`/`201` do PUT como
sucesso equivalente (ambos corpo vazio, nenhuma info adicional a extrair); (d)
tratar `404` do GET como "marker inexistente" (SyncMarker nunca gravado para
esta issue), nao como erro fatal.

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
na resposta real NAO e determinavel pelo schema — nesta onda a chamada real
preencheu `issueTypes` (`createMetaIssueType` ausente do payload) => o motor
le a que vier nao-vazia (comportamento confirmado no roundtrip onda-011,
projeto `SCRUM`). Identificacao de Epic/Task/Sub-task no setup: `subtask=true`
=> candidato a Sub-task (descricao do schema).

**`hierarchyLevel` de Epic — CONFIRMADO (roundtrip onda-011)**: `GET
/rest/api/3/issue/createmeta/SCRUM/issuetypes` no site de teste
`cstk.atlassian.net` (projeto `SCRUM`/"CSTK Playground", esquema padrao de
hierarquia do Jira Software Cloud) retornou 4 tipos com `hierarchyLevel`:
`Epic`=`1`, `Subtask`=`-1`, `Task`=`0`, `Story`=`0` — bate com o intervalo
-1/0/1 ja citado do post de R1, e neste site `hierarchyLevel=1` identificou
exclusivamente o Epic. Este e o UNICO site testado; a PROPOSTA de o setup
listar os tipos e o OPERADOR confirmar qual e Epic/Task/Sub-task antes de
gravar `issue_type_*` permanece de pe (nao revogada por esta unica evidencia)
— sites com esquemas de hierarquia customizados (planos Enterprise/Premium
permitem niveis adicionais) podem nao seguir este mapeamento 1:1; a decisao de
tornar a correspondencia determinista ou manter confirmacao manual e do
`plan.md`/`data-model.md`, fora do escopo desta tarefa (0.1.4 so confere se o
campo aparece na resposta real).

### Validacao de credencial (SUPERA `NAO ENCONTRADO`)

`GET /rest/api/3/myself` (operationId `getCurrentUser`) → `200` schema
`User`; `401` "Returned if the authentication credentials are incorrect or
missing." (`P:./rest/api/3/myself.get.responses`) — `401` => `auth_failed`.
`403` em R1/R2 = "does not have the necessary permission" => erro de
permissao, NAO de credencial. **CONFIRMADO end-to-end (roundtrip onda-011)**:
Basic auth com email + API token classico contra `cstk.atlassian.net`
retornou `200` com corpo `User` real (`accountId`, `accountType`,
`emailAddress`, `displayName`, `active`, `timeZone`, `locale`, `groups`,
`applicationRoles`); nas ondas anteriores (block-008) o mesmo endpoint
retornara `401` duas vezes com um token que se revelou invalido — resolvido
apos o operador gerar um novo token classico.

### Continua fora do contrato apos a onda-005

Endpoint de changelog; valores de `statusCategory.key` (a resposta real
os revela em runtime — `new`/`indeterminate`/`done` observados no roundtrip
onda-011 — mas o schema nao define enum normativo e o motor NAO decide por
categoria, ver R5 acima); forma `fields.project.key` em R1 (so `id` foi
testado); path v3 de criacao de projeto (nao exercitado — o roundtrip onda-011
usou o projeto de teste ja existente `SCRUM`, ver secao seguinte).

`tipo/formato de fields.updated` SAIU desta lista — CONFIRMADO na secao R3
acima pelo roundtrip onda-011.

## Campos de request/response de R9-R11 a partir do OpenAPI oficial (onda-029)

**Fontes desta secao** (cstk-jira FASE 7 tarefa 7.1, dec-099): (a) OpenAPI
oficial do Jira Cloud REST v3 (platform), MESMO arquivo ja citado na secao
"Campos de request/response a partir do OpenAPI oficial (onda-005)" acima —
re-baixado nesta onda para conferir R9 (`filter`); sha256
`6ecc461bb85e92a46331a4316b6c63c91c16ed6baf5f06b03ab616da3f1ab3d7` (IDENTICO
ao ja citado, confirma estabilidade da fonte); (b) OpenAPI oficial da Agile
API, `https://developer.atlassian.com/cloud/jira/software/swagger.v3.json`
(baixado 2026-09-26 via `curl`, HTTP 200, 658314 bytes, `openapi: 3.0.1`,
`info.version: 1001.0.0`, sha256
`4e108d54b99064475c6ba0f986cce46dcace81336e034b58a5400b93174b927a`) — para
R10/R11 (`board`). Ambos os hosts ja constam na whitelist (block-005).

### R9 — criar filtro: `POST /rest/api/3/filter` (operationId `createFilter`)

| Elemento | Valor | Path JSON |
|----------|-------|-----------|
| corpo | schema `Filter` (`$ref`); UNICO campo `required`: `name` | `P:./rest/api/3/filter.post.requestBody.content.application/json.schema` → `S:.Filter.required` |
| `name` | string (`example`: `"All Open Bugs"`) | `...requestBody...example.name` |
| `jql` | string, OPCIONAL no schema — o motor sempre envia (SEC-3, `json-build filter`) | `...requestBody...example.jql` |
| sucesso | `200` (nao `201`) → `Filter`: `id` (string, ex. `"10000"`), `name`, `jql`, `self` (string), demais campos (`owner`, `favourite`, `sharePermissions`, ...) fora do uso do motor | `P:./rest/api/3/filter.post.responses.200` → `S:.Filter.properties` |
| erros | `400`, `401` | `...filter.post.responses` |

Confirma o corpo ja implementado por `jira-io.sh json-build filter`
(`{"name":...,"jql":...}`) — nenhuma mudanca de codigo necessaria, so
fechamento do gap de fonte (o contrato antes so citava a pagina de suporte,
nao o schema OpenAPI).

### R10 — criar board: `POST /rest/agile/1.0/board` (operationId `createBoard`)

| Elemento | Valor | Path JSON |
|----------|-------|-----------|
| corpo | `additionalProperties: false` — SOMENTE os 4 campos abaixo | `P:./rest/agile/1.0/board.post.requestBody.content.application/json.schema` |
| `name` | string | `...schema.properties.name` |
| `type` | enum `kanban`/`scrum`/`agility` — o motor SEMPRE envia `kanban` (US2 so preve board kanban por projeto) | `...schema.properties.type` |
| `filterId` | integer, `format: int64` — **NUNCA string** (`jira-io.sh json-build board --filter-id` valida `[0-9]` e emite via `--argjson`) | `...schema.properties.filterId` |
| `location` | objeto `{type: "project"\|"user", projectKeyOrId: string}`; description: "If choosing 'project', then a project must be specified by a `projectKeyOrId` property"; "If choosing 'user', ... `projectKeyOrId` should not be provided" — o motor SEMPRE usa `type=project` (nunca board pessoal) | `...schema.properties.location` |
| exemplo oficial | `{"filterId":10040,"location":{"projectKeyOrId":"10000","type":"project"},"name":"scrum board","type":"scrum"}` | `...requestBody.content.application/json.example` |
| sucesso | `201` → `Board`: `id` (integer, `format: int64`), `name`, `self` (string), `type` — exemplo `{"id":84,"name":"scrum board","self":"https://your-domain.atlassian.net/rest/agile/1.0/board/84","type":"scrum"}` | `P:./rest/agile/1.0/board.post.responses.201` |
| descricao (nota) | "If you want to create a new project with an associated board, use the Jira platform REST API" / "You can create a filter using the Jira REST API" — CONFIRMA que `filterId` precisa vir de uma chamada R9 PREVIA (nao ha criacao implicita de filtro) | `...post.description` |

### R11 — boards do projeto: `GET /rest/agile/1.0/board` (operationId `getAllBoards`)

| Elemento | Valor | Path JSON |
|----------|-------|-----------|
| query `projectKeyOrId` | string — "Filters results to boards that are relevant to a project." | `P:./rest/agile/1.0/board.get.parameters[name=projectKeyOrId]` |
| query `type` | "Filters results to boards of the specified types. Valid values: scrum, kanban, simple." — o motor usa `type=kanban` na checagem de existencia (7.1.2) para nunca confundir um board scrum pre-existente com o board do cstk-jira | `...parameters[name=type]` |
| sucesso | `200` → `{isLast, maxResults, startAt, total, values: [Board...]}`; elemento `values[]` = MESMO shape do sucesso de R10 (`id`, `name`, `self`, `type`) | `P:./rest/agile/1.0/board.get.responses.200` |
| exemplo oficial | `{"isLast":false,"maxResults":2,"startAt":1,"total":5,"values":[{"id":84,"name":"scrum board","self":"...","type":"scrum"},{"id":92,"name":"kanban board","self":"...","type":"kanban"}]}` | `...responses.200.content.application/json.example` |

**Decisao de reuso (US2 cenario 2, tasks.md 7.1.2)**: a checagem de
existencia usa SOMENTE `projectKeyOrId`+`type=kanban` (nao compara `name`) —
`values` nao-vazio ⇒ reusa `values[0].id`; vazio ⇒ cria filtro (R9) e board
(R10) na sequencia, usando o `id` da resposta de R9 como `filterId` de R10.
Evita depender de o operador (ou uma reexecucao do setup) escolher
exatamente o mesmo texto de `name` duas vezes — o par projeto+tipo ja e
suficiente para a garantia de nao-duplicacao exigida pela spec.

## Roundtrip real onda-011 (FASE 0 task 0.1 — resolve block-008)

Executado apos o operador gerar um novo API token classico (resposta ao
block-008/dec-053). Site: `https://cstk.atlassian.net`. Credencial: Basic
auth `jot@jot.com.br` + token novo (carregado via `.env`, nunca impresso).

- `GET /rest/api/3/myself` → `200` (antes `401` x2 com o token antigo).
- `GET /rest/api/3/project/search` → 1 projeto existente e adequado:
  `key=SCRUM`, `name="CSTK Playground"`, `projectTypeKey=software`,
  `style=next-gen` (`id=10000`) — reutilizado como projeto de teste (Decisao
  dec-056 do state da execucao); nenhum projeto novo foi criado.
- `POST /rest/api/3/issue` (Epic) → `201` `{"id":"10004","key":"SCRUM-5", ...}`.
- `POST /rest/api/3/issue` (Story, `fields.parent={"key":"SCRUM-5"}`) → `201`
  `{"id":"10005","key":"SCRUM-6", ...}`.
- `GET /rest/api/3/issue/SCRUM-6?fields=summary,status,issuetype,updated,parent`
  → `200` (evidencia usada nas linhas de R3 acima).
- `GET /rest/api/3/issue/SCRUM-6/transitions` → `200`, 4 transicoes
  (`To Do`/`In Progress`/`In Review`/`Done`) — evidencia usada em R5 acima
  (achou o campo real `isLooped`, corrigindo o `looped` citado do OpenAPI).
- `GET /rest/api/3/issue/createmeta/SCRUM/issuetypes` → `200`, 4 tipos
  (evidencia usada em R8 acima).

**Pendente (0.1.6, fora do escopo de execucao autonoma)**: as issues de teste
`SCRUM-5` (Epic) e `SCRUM-6` (Story) NAO foram arquivadas/deletadas — FR-012
proibe `DELETE` pelo motor, e arquivar exige a UI do Jira (este orquestrador
nao tem ferramenta de navegador). Acao manual do operador: arquivar `SCRUM-5`
e `SCRUM-6` no projeto `SCRUM` via UI do Jira quando conveniente; nenhuma
credencial nem dado sensivel fica exposto por deixa-las como estao (issues de
teste vazias, sem dados reais, em projeto de sandbox).

## Roundtrip real onda-022 (FASE 4 task 4.2 — resolve dec-079, gap R6)

Executado com a mesma credencial (`.env`, Basic auth, nunca impressa) contra
`https://cstk.atlassian.net`, reusando a Epic de teste `SCRUM-5` (criada no
roundtrip onda-011, ainda nao arquivada — ver nota 0.1.6 acima).

- `PUT /rest/api/3/issue/SCRUM-5/properties/cstk-jira.sync` com corpo
  `{"synced_at":"2026-09-26T00:00:00Z","checksum":"r6-roundtrip-test"}` →
  `201`, corpo vazio (propriedade nao existia).
- `GET /rest/api/3/issue/SCRUM-5/properties/cstk-jira.sync` → `200`
  `{"key":"cstk-jira.sync","value":{"synced_at":"2026-09-26T00:00:00Z","checksum":"r6-roundtrip-test"}}`
  — confirma o envelope `EntityProperty` do OpenAPI.
- `PUT` na mesma chave com corpo
  `{"synced_at":"2026-09-26T00:05:00Z","checksum":"r6-roundtrip-test-2"}` →
  `200`, corpo vazio (atualizacao, distinta do `201` de criacao).
- Nenhum `DELETE` foi executado (FR-012); a propriedade de teste
  `cstk-jira.sync` permanece gravada em `SCRUM-5` — mesmo criterio de risco
  aceito da nota 0.1.6 (issue de teste vazia, sem dados reais, em projeto de
  sandbox).

## Operacoes do round r02 (R12-R18) a partir do OpenAPI oficial (plan r02, onda-003)

**Fonte unica desta secao**: o MESMO OpenAPI oficial do Jira Cloud REST v3 ja
citado na secao onda-005 (`https://developer.atlassian.com/cloud/jira/platform/swagger-v3.v3.json`,
host na whitelist por block-005), re-baixado em 2026-09-26 pela onda-001 do
round r02 e reconferido nesta onda: sha256
`6ecc461bb85e92a46331a4316b6c63c91c16ed6baf5f06b03ab616da3f1ab3d7` (IDENTICO
ao das ondas 005/029 do r01), `openapi: 3.0.1`, `info.version:
1001.0.0-SNAPSHOT-44cdd07c042959317ed5591bf79dbcd9369f3610`, 423 paths.
Abreviacoes `P:`/`S:` como na secao onda-005. Nenhuma linha abaixo foi
exercitada contra um site real nesta onda (sem roundtrip no plan): o que o
schema/exemplo nao determina esta marcado **a confirmar por roundtrip no
execute-task** e MUST NOT ser tratado como fato pelo motor antes disso
(quickstart cenario 12).

| ID | Operacao | Metodo + path | operationId | Requisito |
|----|----------|---------------|-------------|-----------|
| R12 | criar Fix Version | `POST /rest/api/3/version` | `createVersion` | FR-020 |
| R13 | listar versoes do projeto (idempotencia) | `GET /rest/api/3/project/{projectIdOrKey}/versions` | `getProjectVersions` | FR-021 |
| R14 | `fixVersions`/`labels` na criacao/edicao | extensao do corpo de R1/R2 | `createIssue`/`editIssue` | FR-020, FR-022 |
| R15 | ler `labels`/`fixVersions`/`issuelinks` de issue mapeada | extensao de R3 (`?fields=...`) | `getIssue` | FR-021, FR-022, FR-025 |
| R16 | listar tipos de link | `GET /rest/api/3/issueLinkType` | `getIssueLinkTypes` | FR-025 |
| R17 | criar link entre issues | `POST /rest/api/3/issueLink` | `linkIssues` | FR-025 |
| R18 | criar projeto (SO com gate humano) | `POST /rest/api/3/project` | `createProject` | FR-024 |

Todas com `deprecated: false` no arquivo. Metodos continuam fechados em
`GET`/`POST`/`PUT`: as operacoes `DELETE` e as de remocao/troca de versao
(`POST /rest/api/3/version/{id}/removeAndSwap`, `deleteAndReplaceVersion`;
`PUT /rest/api/3/version/{id}/mergeto/{moveIssuesTo}`, `mergeVersions`) e de
exclusao de projeto (`POST /rest/api/3/project/{projectIdOrKey}/delete`,
`deleteProjectAsynchronously`) existem no arquivo e ficam **fora do
contrato** por FR-012 (nunca apagar/fundir artefato do Jira).

### R12 — criar Fix Version: `POST /rest/api/3/version` (operationId `createVersion`)

| Elemento | Valor | Path JSON |
|----------|-------|-----------|
| corpo | schema `Version` (`$ref`); o schema NAO tem lista `required` — obrigatoriedade vem das descricoes dos campos | `P:./rest/api/3/version.post.requestBody.content.application/json.schema` → `S:.Version` |
| `name` | string — "The unique name of the version. Required when creating a version. Optional when updating a version. The maximum length is 255 characters." | `S:.Version.properties.name.description` |
| `projectId` | integer — "The ID of the project to which this version is attached. Required when creating a version." (o motor converte o `id` string de `getProject` para numero JSON, validando so digitos, mesmo padrao de `filterId` em R10) | `S:.Version.properties.projectId` |
| `description` | string opcional, "maximum size is 16,384 bytes" — o motor envia texto FIXO do plugin (ex.: rotulo do marco), nunca texto lido do Jira | `S:.Version.properties.description` |
| `released`/`archived`/`releaseDate`/`startDate` | opcionais — o motor NAO os envia (versao nasce nao-liberada; liberar e decisao humana na UI) | `S:.Version.properties` |
| `project` | "Deprecated. Use `projectId`." — NUNCA enviado | `S:.Version.properties.project.description` |
| exemplo oficial | `{"archived":false,"description":"An excellent version","name":"New Version 1","projectId":10000,"releaseDate":"2010-07-06","released":true}` | `...requestBody.content.application/json.example` |
| sucesso | `201` → `Version` (`id` string readOnly, `name`, `self` string readOnly, ...) | `P:./rest/api/3/version.post.responses.201`; `S:.Version.properties.id` |
| erros | `400` "request is invalid"; `401` credencial; `404` "the project is not found" **ou** "the user does not have the required permissions"; `422` `LimitExceededResponseBean` | `P:./rest/api/3/version.post.responses` |
| permissao | "*Administer Jira* global permission or *Administer Projects* project permission for the project the version is added to." | `P:./rest/api/3/version.post.description` |

**Divergencia com a Clarification r02 (Principio VI)**: a spec fala em
"HTTP 403" para permissao insuficiente na criacao da Fix Version, mas o
OpenAPI de `createVersion` NAO documenta `403` — a falta de permissao aparece
como `404` (junto com "projeto nao encontrado"). Tratamento de desenho
(plan.md r02, Decisao R2-4): `--op R12` classifica `403` (se vier, nao
documentado) E `404` como `permission_denied` (exit 7), porque o
`project_key` ja foi resolvido por `getProject` na mesma execucao (o ramo
"projeto nao encontrado" ja teria falhado antes); o motor suspende a
sincronizacao daquele marco (FR-020).

**Status real de permissao negada — FECHADO SEM ROUNDTRIP (decisao humana,
block-001/dec-039, onda-006/r02 FASE 15 task 15.1.2)**: o operador optou
pela opcao (b) do bloqueio — "aceitar sem roundtrip. Manter o contrato pela
OpenAPI (404 documentado; 403 tratado por equivalencia como
permission_denied). CHK022 marcado aceito-sem-verificacao. Nenhuma segunda
credencial sera fornecida." Nenhuma 2a credencial de teste sem *Administer
Projects*/*Administer Jira* foi ou sera fornecida nesta feature; o status
HTTP real de `createVersion` sem permissao **continua NAO exercitado
empiricamente**. A classificacao aplicada permanece a de desenho (`403` OU
`404` → `permission_denied`, exit 7), agora como risco aceito e documentado
— nao mais como pendencia de roundtrip.

**Nome duplicado (corrida entre execucoes paralelas, FR-023) — CONFIRMADO
(roundtrip onda-006, r02 FASE 15 task 15.1.1)**: `POST /rest/api/3/version`
com o MESMO `name` de uma versao ja existente no projeto `SCRUM` devolveu
`400` com corpo
`{"errorMessages":[],"errors":{"name":"A version with this name already exists in this project."}}`
— bate com o tratamento de desenho ja descrito (refazer R13, reusar `id`
por nome EXATO, nunca repetir R12); nenhuma correcao de contrato necessaria
aqui.

### R13 — listar versoes: `GET /rest/api/3/project/{projectIdOrKey}/versions` (operationId `getProjectVersions`)

| Elemento | Valor | Path JSON |
|----------|-------|-----------|
| path | `projectIdOrKey` — "The project ID or project key (case sensitive)." (SEC-1: `project_key` passa por `validate-segment`) | `...versions.get.parameters[name=projectIdOrKey]` |
| query | so `expand` (opcional; o motor NAO usa) | `...versions.get.parameters` |
| paginacao | NENHUMA — "Returns all versions in a project. The response is not paginated." | `...versions.get.description` |
| sucesso | `200` → array de `Version` (`id`, `name`, `released`, `archived`, ...) | `...versions.get.responses.200.content.application/json.schema` |
| erros | `404` | `...versions.get.responses` |

**Por que esta rota e nao a paginada**: `GET /rest/api/3/project/{projectIdOrKey}/version`
(operationId `getProjectVersionsPaginated`, `PageBeanVersion`: `isLast`,
`maxResults`, `nextPage`, `startAt`, `total`, `values`) aceita `query`
("Versions with matching `name` or `description` are returned (case
insensitive)") — casamento aproximado e case-insensitive, que NAO serve como
teste de identidade, e exigiria interpolar o nome do marco numa querystring.
A rota nao-paginada devolve tudo e o motor casa o `name` por IGUALDADE EXATA
(byte a byte) localmente via `jira-io.sh json-get` — nenhum texto do marco
entra em URL. Projeto com volume de versoes que torne isso caro e cenario nao
observado; reabrir via `/clarify` se aparecer.

### R14 — `fixVersions` e `labels` no corpo de R1/R2

| Elemento | Valor | Situacao | Path JSON |
|----------|-------|----------|-----------|
| criar com versao | `fields.fixVersions`: array de `{"id": "<id da versao>"}` (exemplo oficial `"fixVersions":[{"id":"10001"}]`) | **CONFIRMADO (roundtrip onda-006, task 15.2.1)** — `POST /rest/api/3/issue` com `fields.fixVersions:[{"id":"10000"}]` criou `SCRUM-7` (`201`) | `P:./rest/api/3/issue.post.requestBody.content.application/json.example.fields.fixVersions` |
| criar com label | `fields.labels`: array de string (exemplo oficial `"labels":["bugfix","blitz_test"]`) | **CONFIRMADO (roundtrip onda-006, task 15.2.1)** — `fields.labels:["cstk-jira-roundtrip"]` no mesmo `POST` | `...example.fields.labels` |
| editar label sem clobber | `update.labels`: lista de operacoes `{"add": "<label>"}` / `{"remove": "<label>"}` (exemplo oficial `"labels":[{"add":"triaged"},{"remove":"blocker"}]`) | **CONFIRMADO (roundtrip onda-006, task 15.2.2)** — `update.labels:[{"add":"cstk-jira-roundtrip-2"},{"remove":"cstk-jira-roundtrip"}]` devolveu `204` e a releitura mostrou SO `["cstk-jira-roundtrip-2"]` | `P:./rest/api/3/issue/{issueIdOrKey}.put.requestBody.content.application/json.example.update.labels` |
| editar versao sem clobber | `update.fixVersions` com `{"add": {"id": "<id>"}}` / `{"remove": {"id": "<id>"}}` | **CONFIRMADO (roundtrip onda-006, r02 FASE 15 task 15.2.2)** — `PUT /rest/api/3/issue/SCRUM-7` com `update.fixVersions:[{"remove":{"id":"10000"}},{"add":{"id":"10001"}}]` devolveu `204` e a releitura via R15 mostrou SO a versao `10001` (a `10000` foi removida sem clobber de nenhum outro valor) | `S:.IssueUpdateDetails.properties.update.description` |
| exclusividade `fields` x `update` | "Fields included in here cannot be included in `update`." / "Note that fields included in here cannot be included in `fields`." — o motor NUNCA manda o mesmo campo nos dois | citado | `S:.IssueUpdateDetails.properties.fields.description`, `...update.description` |
| operacoes suportadas por campo | `FieldCreateMetadata.operations` (obrigatorio no schema) em R8 `GET .../issuetypes/{issueTypeId}` — o setup confere, POR TIPO de issue, se `fixVersions`/`labels` estao na tela de criacao e quais operacoes aceitam | citado (R8) | `S:.FieldCreateMetadata.required` |

Por que `update` (add/remove) e nao `fields.labels`/`fields.fixVersions` na
edicao: `fields` SUBSTITUI a lista inteira e apagaria labels/versoes postas a
mao por humanos no Jira — o plugin so remove o valor que ELE PROPRIO gravou
(rastreado no SyncMarker, `data-model.md`). Na CRIACAO (R1) nao ha valor
humano a preservar, entao `fields.*` e usado. Se o roundtrip reprovar
`update.fixVersions`, a edicao de marco numa issue existente degrada para
"sinalizar e nao escrever" (nunca para `fields.fixVersions` com clobber).

### R15 — ler `labels`/`fixVersions`/`issuelinks` (extensao de R3)

`GET /rest/api/3/issue/{issueIdOrKey}?fields=labels,fixVersions,issuelinks`
(parametro `fields` ja citado em R3: "accepts a comma-separated list").

| Campo | Fonte | Situacao |
|-------|-------|----------|
| `issuelinks` | exemplo de `200` de `getIssue`: elemento `{"id":"10001","outwardIssue":{"id":...,"key":"PR-2","self":...,"fields":{...}},"type":{"id":"10000","inward":"depends on","name":"Dependent","outward":"is depended by"}}`; schema `S:.IssueLink` (`required`: `inwardIssue`, `outwardIssue`, `type`; props `id`, `self`) | citado (exemplo + schema) |
| `labels`, `fixVersions` | nomes como id de campo so no exemplo de CRIACAO (R14); NAO aparecem em `S:.Fields` nem no exemplo de `200` de `getIssue` | **CONFIRMADO (roundtrip onda-006, task 15.2.1)** — `GET /rest/api/3/issue/SCRUM-7?fields=labels,fixVersions,issuelinks` devolveu `fields.labels` como array de STRING pura (`["cstk-jira-roundtrip"]`, mesmo shape do corpo de criacao) e `fields.fixVersions` como array do objeto `Version` COMPLETO (`{"self","id","description","name","archived","released"}`, mais rico que o `{"id":...}` enviado na escrita) |

Uso: conferir, antes de escrever, se a versao/label/link que o plugin
pretende aplicar ja esta la (idempotencia FR-021/FR-022/FR-025) e achar o
`id` de um link recem-criado (R17 nao devolve corpo).

### R16 — tipos de link: `GET /rest/api/3/issueLinkType` (operationId `getIssueLinkTypes`)

| Elemento | Valor | Path JSON |
|----------|-------|-----------|
| sucesso | `200` → `IssueLinkTypes` com `issueLinkTypes` (array readOnly de `IssueLinkType`) | `...issueLinkType.get.responses.200` → `S:.IssueLinkTypes.properties` |
| elemento | `id` (string), `name` (string), `inward` (string, "description of the issue link type inward link"), `outward` (string), `self` (string) | `S:.IssueLinkType.properties` |
| exemplo oficial | `{"issueLinkTypes":[{"id":"1000","inward":"Duplicated by","name":"Duplicate","outward":"Duplicates",...},{"id":"1010","inward":"Blocked by","name":"Blocks","outward":"Blocks",...}]}` | `...responses.200.content.application/json.example` |
| erros | `401`; `404` "Returned if issue linking is disabled." | `...issueLinkType.get.responses` |

`404` aqui = linking desligado no site => TODAS as dependencias da feature
ficam `unrepresentable` (FR-025), sem erro fatal. Os valores `name`/`inward`/
`outward` do exemplo sao ILUSTRATIVOS (sao dados configurados por site): a
escolha do tipo segue a regra dinamica de `data-model.md` §IssueLink, nunca um
literal destes exemplos.

**Valores reais do site de teste — CONFIRMADO (roundtrip onda-006, task
15.3.1)**: `GET /rest/api/3/issueLinkType` em `cstk.atlassian.net` devolveu
4 tipos, TODOS diferentes do exemplo ilustrativo do OpenAPI (confirma que
os nomes/frases sao configuracao por site, nao literal fixo): `id=10000
name="Blocks" inward="is blocked by" outward="blocks"`; `id=10001
name="Cloners" inward="is cloned by" outward="clones"`; `id=10002
name="Duplicate" inward="is duplicated by" outward="duplicates"`; `id=10003
name="Relates" inward="relates to" outward="relates to"`. O tipo `Blocks`
(`id=10000`) foi usado no roundtrip de R17 abaixo.

### R17 — criar link: `POST /rest/api/3/issueLink` (operationId `linkIssues`)

| Elemento | Valor | Path JSON |
|----------|-------|-----------|
| corpo | `LinkIssueRequestJsonBean`, `additionalProperties: false`, `required`: `inwardIssue`, `outwardIssue`, `type`; `comment` opcional (o motor NUNCA envia) | `S:.LinkIssueRequestJsonBean` |
| `inwardIssue`/`outwardIssue` | `LinkedIssue`: `key` ("Required if `id` isn't provided") ou `id` | `S:.LinkedIssue.properties` |
| `type` | `IssueLinkType`: `id` ("Required on create when `name` isn't provided") ou `name` — o motor envia SEMPRE `{"id": "<link_type_id>"}`, nunca `name` (FR-025: nada hardcoded) | `S:.IssueLinkType.properties.id.description` |
| exemplo oficial | `{"inwardIssue":{"key":"HSP-1"},"outwardIssue":{"key":"MKY-1"},"type":{"name":"Duplicate"},"comment":{...}}` | `...issueLink.post.requestBody.content.application/json.example` |
| sucesso | `201`, SEM corpo util: "This resource returns nothing on the creation of an issue link. To obtain the ID of the issue link, use `.../rest/api/3/issue/[linked issue key]?fields=issuelinks`." | `...issueLink.post.description`; `...responses.201` |
| duplicata | "If the link request duplicates a link, the response indicates that the issue link was created." — reenviar o mesmo link e seguro (base da idempotencia de FR-025 junto com o sidecar local) | `...issueLink.post.description` |
| erros | `400` (comentario nao criado), `401`, `404` ("issue linking is disabled" ou usuario sem ver uma das issues), `413` "per-issue limit for issue links has been breached" | `...issueLink.post.responses` |
| permissao | *Browse project* nos projetos das duas issues + *Link issues* "on the project containing the from (outward) issue" | `...issueLink.post.description` |

**Direcao — CONFIRMADO (roundtrip onda-006, tasks 15.3.2/15.3.3), desenho
VALIDADO sem inversao**: `POST /rest/api/3/issueLink` com
`{"type":{"id":"10000"},"outwardIssue":{"key":"SCRUM-5"},"inwardIssue":{"key":"SCRUM-6"}}`
(SCRUM-5 = bloqueador, SCRUM-6 = bloqueado, exatamente o desenho do
contrato) devolveu `201` sem corpo. A releitura via R15 confirmou: em
`SCRUM-5` (enviado como `outwardIssue`) o link aparece com `inwardIssue`
apontando para `SCRUM-6` e a frase aplicavel a `SCRUM-5` e a `outward`
(`"blocks"`); em `SCRUM-6` (enviado como `inwardIssue`) o link aparece com
`outwardIssue` apontando para `SCRUM-5` e a frase aplicavel a `SCRUM-6` e a
`inward` (`"is blocked by"`) — bate byte-a-byte com o desenho ("bloqueador
exibe outward, bloqueado exibe inward"); NENHUMA inversao foi necessaria no
contrato. Repetir o MESMO `POST` (mesmo par, mesmo tipo) devolveu `201` de
novo (sem corpo) e o `issuelinks` de `SCRUM-5` continuou com exatamente 1
elemento (`id=10000`) — confirma "duplicata nao cria 2o link" sem exigir
verificacao previa do motor.

`413`: classificado como `permission_denied`-like por item (o link vira
`unrepresentable` com motivo `limit`), nunca retry.

### R18 — criar projeto: `POST /rest/api/3/project` (operationId `createProject`) — SO com gate humano (FR-024)

SUPERA o `NAO ENCONTRADO` "path v3 de criacao de projeto" de research.md
Decision 3 e da secao "Continua fora do contrato apos a onda-005".

| Elemento | Valor | Path JSON |
|----------|-------|-----------|
| corpo | `CreateProjectDetails`, `required`: `key`, `name` | `S:.CreateProjectDetails.required` |
| `key` | "Project keys must be unique and start with an uppercase letter followed by one or more uppercase alphanumeric characters. The maximum length is 10 characters." | `S:.CreateProjectDetails.properties.key.description` |
| `name` | "The name of the project." | `...properties.name` |
| `leadAccountId` | "Either `lead` or `leadAccountId` must be set when creating a project. Cannot be provided with `lead`." — `lead` e deprecated; o motor usa `leadAccountId` = `accountId` do usuario autenticado (`GET /rest/api/3/myself`, schema `User`, campo `accountId` — presente na resposta real do roundtrip onda-011) | `...properties.leadAccountId.description`; `S:.User.properties.accountId` |
| `projectTypeKey` | enum `software`, `service_desk`, `business`, `customer_service` — "If you don't specify the project template you have to specify the project type." O plugin usa `software` (o board kanban de US2 e da Agile API do Jira Software, R10) | `...properties.projectTypeKey` |
| `projectTemplateKey` | enum; "The type of the `projectTemplateKey` must match with the type of the `projectTypeKey`." Para `software` a tabela da descricao lista `com.pyxis.greenhopper.jira:gh-simplified-agility-kanban`, `...:gh-simplified-agility-scrum`, `...:gh-simplified-basic`, `...:gh-simplified-kanban-classic`, `...:gh-simplified-scrum-classic` | `...properties.projectTemplateKey`; `P:./rest/api/3/project.post.description` |
| outros | `assigneeType` (enum `PROJECT_LEAD`/`UNASSIGNED`), `description`, `avatarId`, `categoryId`, esquemas (`permissionScheme`, `workflowScheme`, ...) — o motor NAO envia (defaults do template) | `S:.CreateProjectDetails.properties` |
| sucesso | `201` → `ProjectIdentifiers` (`additionalProperties: false`, `required`: `id` integer int64, `key` string, `self` string uri) | `...project.post.responses.201` → `S:.ProjectIdentifiers` |
| erros | `400` "request is not valid and the project could not be created"; `401`; `403` "the user does not have permission to create projects" | `...project.post.responses` |
| permissao | "*Administer Jira* global permission" | `P:./rest/api/3/project.post.description` |

**Template padrao proposto**: `com.pyxis.greenhopper.jira:gh-simplified-agility-kanban`
(kanban, alinhado a US2) — a lista vem do OpenAPI, mas a ESCOLHA e do
operador no gate (confirmacao explicita de `name`/`key`/tipo/template); o
default e so a opcao pre-selecionada. Se o template ja cria um board
kanban, o reuso de R11 (`projectKeyOrId`+`type=kanban`) o encontra e o setup
NAO cria um segundo.

**Se o template cria board automaticamente — FECHADO COMO MOOT (decisao
humana, block-002/dec-040, onda-006/r02 FASE 15 task 15.4.2)**: o operador
optou pela opcao (a) do bloqueio — "aceitar como moot. O setup reusa/cria o
board via R11/R9/R10 apos o projeto existir, entao a existencia de board
automatico no template de R18 nao altera o comportamento. Registrar a
decisao no contrato; nenhum roundtrip de createProject." O OpenAPI NAO
documenta se `gh-simplified-agility-kanban` cria um board na criacao do
projeto, e essa lacuna permanece **NAO exercitada empiricamente** — nenhum
roundtrip real de `createProject` foi ou sera executado fora do gate
humano de FASE 19. A decisao e operacional (nao fixa eixo estrutural): o
comportamento do motor (checar R11 antes de criar) e identico nos dois
casos possiveis (template cria board ou nao), entao a lacuna nao bloqueia
codigo nem release.

`403` em R18 => `permission_denied` (exit 7) e o setup cai no ramo "orientar
criacao manual" de FR-024 (UI do Jira ou tool `createJiraProject` do Rovo MCP
por um admin) — NUNCA e tratado como credencial invalida (a credencial e
valida; falta *Administer Jira*).

**Checagem previa de existencia**: `GET /rest/api/3/project/{projectIdOrKey}`
(`getProject`, ja citado em R1 "Resolucao do project.id") com a `key`
proposta — `200` => projeto ja existe, reusar (nunca criar); `404` => livre
para o gate. `GET /rest/api/3/project/search` (`searchProjects`, query
`keys`, `query`, ...) continua disponivel para LISTAR projetos ao operador
(rota ja exercitada no roundtrip onda-011).

## Roundtrip real onda-006 (FASE 15 tasks 15.1.1/15.2.1-2/15.3.1-3 — round
r02, resolve CHK021/CHK023/CHK024/CHK025)

Executado contra o MESMO site de teste (`cstk.atlassian.net`, projeto
`SCRUM`), credencial classica via `.env` (`ATLASIAN_TOKEN`, Basic auth
`jot@jot.com.br`, nunca impressa/logada), sem `jira-io.sh` (o mecanismo de
credencial global do script — `jira-config.sh credential-check` +
`ProjectConfig.site_host` — nao esta provisionado nesta worktree; chamado
direto via `curl -K` com as mesmas protecoes SEC-4/SEC-5: arquivo `-K`
temporario `umask 077` + `trap` de remocao, host unico, sem `-L`, `DELETE`
nunca usado). Resumo dos 5 pontos fechados nesta onda (detalhe inline nas
secoes R12/R14/R15/R16/R17 acima):

- R12 nome duplicado: `400` confirmado, corpo
  `{"errorMessages":[],"errors":{"name":"A version with this name already exists in this project."}}`.
- R14 `update.fixVersions` add/remove: `204`, efeito confirmado sem clobber.
- R15 `labels`/`fixVersions` na resposta: `labels` = array de string;
  `fixVersions` = array do objeto `Version` completo.
- R16 tipos de link reais do site: `Blocks`/`Cloners`/`Duplicate`/`Relates`
  (ids `10000`-`10003`), todos diferentes do exemplo ilustrativo do OpenAPI.
- R17 direcao inward/outward: desenho do contrato (bloqueador=`outwardIssue`
  exibe `outward`, bloqueado=`inwardIssue` exibe `inward`) CONFIRMADO sem
  necessidade de inversao; duplicata do MESMO par devolveu `201` de novo sem
  criar 2o link.

Issues/versoes de teste criadas nesta onda (nenhum `DELETE`, FR-012 —
arquivamento manual do operador, mesma nota de risco aceito 0.1.6 do
roundtrip onda-011): Fix Version `id=10000`
(`cstk-jira-r02-roundtrip-20260927T005619Z`), Fix Version `id=10001`
(`cstk-jira-r02-roundtrip-b-20260927T005659Z`), Task `SCRUM-7` (`id=10006`,
labels/fixVersions de teste), issueLink `id=10000` (tipo `Blocks` entre
`SCRUM-5`→`SCRUM-6`, ja existentes do roundtrip onda-011).

**Fechado por decisao humana nesta onda (sem roundtrip empirico)**: status
real de falta de permissao em R12 (`403` vs `404` documentado) — CHK022
fechado como aceito-sem-verificacao (block-001/dec-039, r02 FASE 15 task
15.1.2); se o template de R18 cria board — CHK026 fechado como moot
(block-002/dec-040, r02 FASE 15 task 15.4.2). Nenhum dos dois foi exercitado
por roundtrip real; ambos permanecem risco aceito e documentado, nao fato
observado.

### Continua fora do contrato apos o plan r02

Nenhum ponto pendente. Os 6 pontos originais desta secao foram todos
fechados na FASE 15 (r02): nome duplicado em R12, forma `update.fixVersions`,
nome/shape de `labels`/`fixVersions` na resposta de R3/R15 e direcao
inward/outward de R17 foram CONFIRMADOS por roundtrip real (onda-006, tasks
15.1.1/15.2/15.3); status de permissao negada em R12 (CHK022) e
comportamento de board no template de R18 (CHK026) foram fechados por
decisao humana explicita SEM roundtrip (ver secoes R12/R18 acima) — risco
aceito e documentado, nao fato observado empiricamente.
