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
| R1 | criar issue | `POST /rest/api/3/issue` | https://community.developer.atlassian.com/t/deprecation-of-the-epic-link-parent-link-and-other-related-fields-in-rest-apis-and-webhooks/54048 | RECONFERIR |
| R2 | editar issue | `PUT /rest/api/3/issue/{issueIdOrKey}` | mesmo post | RECONFERIR |
| R3 | ler issue | `GET /rest/api/3/issue/{issueIdOrKey}` | https://support.atlassian.com/jira/kb/retrieve-data-with-jira-rest-api-in-automation-to-update-issue-fields/ | RECONFERIR |
| R4 | transicionar | `POST /rest/api/3/issue/{issueIdOrKey}/transitions` | https://developer.atlassian.com/cloud/jira/platform/change-notice-update-in-simultaneous-transitions-issue-api/ | RECONFERIR |
| R5 | listar transicoes | `GET /rest/api/3/issue/{issueIdOrKey}/transitions` | so citacao v2 (KB de JWM) | RECONFERIR (path v3 = INFERENCIA em research) |
| R6 | gravar/ler propriedade de issue | `PUT` / `GET /rest/api/3/issue/{issueIdOrKey}/properties/{propertyKey}` (max 32 KB) | https://developer.atlassian.com/cloud/jira/platform/jira-entity-properties/ | citado |
| R7 | busca JQL | `GET`/`POST /rest/api/3/search/jql`, paginacao `nextPageToken`; `/rest/api/3/search` removido | https://confluence.atlassian.com/jirakb/run-jql-search-query-using-jira-cloud-rest-api-1289424308.html | citado |
| R8 | tipos de issue para criacao | `GET /rest/api/3/issue/createmeta/{projectIdOrKey}/issuetypes[/{issueTypeId}]` | https://community.developer.atlassian.com/t/create-issue-meta-endpoint-deprecation/75413 | RECONFERIR |
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

**Consequencia (Principio VI)**: os nomes de campo de corpo/resposta de R1,
R3, R4, R5 e R8 — necessarios para o motor REST — NAO estao neste contrato.
A fonte existe (OpenAPI oficial do Jira Cloud v3), mas extrai-la exige acao
humana (liberar o host de documentacao na allowlist da execucao ou fornecer o
arquivo do spec localmente). Registrado como bloqueio humano na onda-004; o
contrato de campos sera completado a partir do spec oficial antes de
`create-tasks`.
