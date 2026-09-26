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
