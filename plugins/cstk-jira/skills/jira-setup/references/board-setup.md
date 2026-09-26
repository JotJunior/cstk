# Criacao/reuso de board + filtro (R9-R11)

Detalhe tecnico de como a skill `jira-setup` verifica se ja existe um board
kanban do cstk-jira para o projeto e, so se necessario, cria filtro + board.
Carregado sob demanda pela ETAPA 6 do `SKILL.md` — nao precisa ser
memorizado antes disso.

Ref: `docs/specs/cstk-jira/spec.md` US2; `plan.md` fluxo 4 "Board";
`contracts/jira-rest.md` R9/R10/R11 (secao "Campos de request/response de
R9-R11 a partir do OpenAPI oficial"); `contracts/rovo-mcp.md`
`listJiraBoards`/`listJiraFilters`/`createJiraBoard`; tasks.md 7.1.1-7.1.5.

## 1. Checar existencia (R11 — `GET /rest/agile/1.0/board`)

```sh
jira-io.sh validate-segment "$PROJECT_KEY"
_BOARDS=$(jira-io.sh request GET \
  "/rest/agile/1.0/board?projectKeyOrId=${PROJECT_KEY}&type=kanban" --op R11)
_BOARD_ID=$(printf '%s' "$_BOARDS" | jira-io.sh json-get '.values[0].id // empty')
```

`<PROJECT_KEY>` MUST passar por `jira-io.sh validate-segment` antes de
interpolar a query — mesma disciplina de `<PROJECT_KEY>` no PATH de R8
(`references/api-discovery.md`), ainda que aqui va em querystring, nao em
segmento de path (SEC-1 cobre o PATH inteiro, incluindo a query).

**Por que `projectKeyOrId`+`type=kanban` e SUFICIENTE para a checagem de
reuso (US2 cenario 2), sem comparar `name`**: `contracts/jira-rest.md`
"Decisao de reuso" — comparar por nome exigiria que o operador (ou uma
reexecucao do setup) digitasse exatamente o mesmo texto toda vez; o par
projeto+tipo ja garante que existe NO MAXIMO um board kanban "do cstk-jira"
por projeto, que e a garantia que a spec pede. Se `_BOARD_ID` vier
NAO-vazio, reusar (pular para o passo 4); senao, criar (passos 2-3).

## 2. Criar o filtro (R9 — `POST /rest/api/3/filter`) — so se `_BOARD_ID` vazio

```sh
_FILTER_BODY=$(jira-io.sh json-build filter --name "$BOARD_NAME" --project-key "$PROJECT_KEY")
_FILTER_BODY_FILE=$(mktemp) && printf '%s' "$_FILTER_BODY" > "$_FILTER_BODY_FILE"
_FILTER_RESP=$(jira-io.sh request POST /rest/api/3/filter \
  --body-file "$_FILTER_BODY_FILE" --op R9)
_FILTER_ID=$(printf '%s' "$_FILTER_RESP" | jira-io.sh json-get '.id')
rm -f "$_FILTER_BODY_FILE"
```

`json-build filter` ja aplica SEC-3 (a JQL so interpola `--project-key`,
ja validado pela allowlist SEC-1 — nunca texto livre como `$BOARD_NAME`).
`$BOARD_NAME` e escolhido pela skill (ex.: `"CSTK - $PROJECT_KEY"`) — e
texto livre so no campo `name`, nunca na JQL.

## 3. Criar o board kanban (R10 — `POST /rest/agile/1.0/board`) — so se `_BOARD_ID` vazio

```sh
_BOARD_BODY=$(jira-io.sh json-build board \
  --name "$BOARD_NAME" --filter-id "$_FILTER_ID" --project-key "$PROJECT_KEY")
_BOARD_BODY_FILE=$(mktemp) && printf '%s' "$_BOARD_BODY" > "$_BOARD_BODY_FILE"
_BOARD_RESP=$(jira-io.sh request POST /rest/agile/1.0/board \
  --body-file "$_BOARD_BODY_FILE" --op R10)
_BOARD_ID=$(printf '%s' "$_BOARD_RESP" | jira-io.sh json-get '.id')
rm -f "$_BOARD_BODY_FILE"
```

`json-build board` recusa (`exit 2`, SEM montar corpo) se `_FILTER_ID` nao
for so digitos (`contracts/jira-rest.md` R10: `filterId` e `integer`/
`format: int64`, nunca string) — se a extracao do passo 2 vier vazia ou com
lixo, o erro aparece AQUI, antes de qualquer requisicao de criacao de
board.

## 4. Gravar `board_id` (ETAPA 7, `write-config`)

`_BOARD_ID` (do passo 1 se reusado, ou do passo 3 se criado) e o valor do
campo `board_id` de `ProjectConfig` — gravado SO na gravacao atomica final
(ETAPA 7 do `SKILL.md`), junto com todos os demais campos. Nunca gravar
`board_id` isoladamente antes disso (mesma regra do Gotcha "Nunca gravar
ProjectConfig incrementalmente").

## 5. Caminho MCP equivalente (Rovo)

Se as tools `mcp__*__listJiraBoards`/`mcp__*__listJiraFilters`/
`mcp__*__createJiraBoard` estiverem visiveis na sessao
(`contracts/rovo-mcp.md`), preferir o caminho MCP: mesma logica (checar
`listJiraBoards` para o projeto; se ausente, chamar `createJiraBoard`), mas
os NOMES de parametro vem do `inputSchema` real exibido pela tool — nunca
de memoria (`contracts/rovo-mcp.md` "Parametros de entrada das tools").
`cloudId` e sempre argumento de topo. `listJiraFilters` entra na checagem
quando o `inputSchema` de `createJiraBoard` exigir um `filterId` existente
(o allowlist de tools do plugin NAO inclui um `createJiraFilter` MCP
dedicado — `contracts/rovo-mcp.md` "Tools permitidas" lista so
`listJiraBoards`/`listJiraFilters`/`listJiraProjects`/`createJiraBoard`/
`createJiraProject`): ler o `inputSchema` de `createJiraBoard` primeiro para
decidir se ele exige um `filterId` (e, se sim, usar `listJiraFilters` para
achar/reusar um filtro do projeto antes de chamar `createJiraBoard`) ou se
ele aceita criar o filtro implicitamente — **nao assumir nenhuma das duas
formas sem ver o schema real** (mesma disciplina de `references/
api-discovery.md` §4).

## Gotchas

### Nao comparar por `name` na checagem de existencia (REST)

Ver secao 1 acima — comparar por nome fragiliza a idempotencia contra
digitacao inconsistente do operador entre execucoes. `projectKeyOrId`+
`type=kanban` e suficiente e e o que `contracts/jira-rest.md` documenta
como decisao desta tarefa.

### `filterId` de R10 e NUMERO, nunca string

`jira-io.sh json-build board --filter-id` so aceita `[0-9]` e emite via
`--argjson` (JSON number). Passar a resposta de R9 (`_FILTER_ID`, que
`json-get` sempre devolve como STRING de digitos, ex. `"10040"`) direto
funciona porque `_ji_digits_ok` aceita string de digitos — a conversao para
numero acontece dentro de `json-build board`, nao antes.

### `createJiraBoard` (MCP) pode nao ter um `createJiraFilter` correspondente

O deny-list nao proibe filtro nenhum, mas o allowlist de tools
(`contracts/rovo-mcp.md`) simplesmente nao lista uma tool MCP dedicada de
criacao de filtro. Ler o `inputSchema` real de `createJiraBoard` ANTES de
assumir que ele precisa (ou nao) de um `filterId` explicito — nunca
inventar um parametro por analogia com o corpo REST de R10 (Principio VI).
