# Contract: tools do Atlassian Rovo MCP usadas pelo cstk-jira

Caminho INTERATIVO das skills (arquitetura A1 / dec-020). O plugin nao
empacota nem configura o servidor: usa as tools se estiverem visiveis na
sessao; senao cai no motor REST (`plugin-scripts.md`).

## Fontes

- Lista de tools (MCP v2): https://support.atlassian.com/atlassian-rovo-mcp-server/docs/supported-tools/
  ("The tools listed on this page are only available with Atlassian MCP v2."),
  confirmada em https://developer.atlassian.com/cloud/rovo-mcp/guides/supported-tools/
  — research.md Decision 1.
- Endpoint recomendado `https://mcp.atlassian.com/v2/mcp`:
  https://raw.githubusercontent.com/atlassian/atlassian-mcp-server/main/README.md
- Autenticacao headless por API token (depende de habilitacao pelo admin da
  organizacao): https://developer.atlassian.com/cloud/rovo-mcp/guides/configuring-authentication-via-api-token/
- Nome da tool no Claude Code: `mcp__<server>__<tool>`, com o `<server>`
  definido pela instalacao do usuario; vindo de plugin,
  `mcp__plugin_<plugin>_<server>__<tool>` (research Decision 1). Por isso o
  plugin identifica as tools por SUFIXO (`__<tool>`), nunca por nome completo.

## Tools permitidas (allowlist da skill)

| Uso no plugin | Tool | Requisito da spec |
|---------------|------|-------------------|
| criar Epic/Task/Sub-task | `createJiraIssue` | FR-001 |
| atualizar titulo/descricao | `editJiraIssue` | FR-003 |
| ler issue (status, titulo) | `getJiraIssue` | FR-011 |
| transicoes disponiveis | `listJiraIssueTransitions` | FR-004, setup |
| mover card | `transitionJiraIssue` | FR-004 |
| verificar existencia por JQL | `searchJiraIssuesUsingJql` | FR-013 (so conferencia; localizacao e pelo mapeamento) |
| tipos de issue do projeto | `listJiraProjectIssueTypesMetadata` | setup |
| campos por tipo | `getJiraIssueTypeMetaWithFields` | setup |
| ler/gravar SyncMarker | `getJiraEntityProperty` / `editJiraEntityProperty` | FR-011 |
| board/filtro/projeto | `listJiraBoards`, `listJiraFilters`, `listJiraProjects`, `createJiraBoard`, `createJiraProject` | FR-002, US2 |

## Tools proibidas (deny-list — FR-012)

| Tool | Motivo | Enforcement |
|------|--------|-------------|
| `deleteJiraIssue` | "Permanently delete an issue. Cannot be undone." (supported-tools) | hook `PreToolUse` exit 2 (`hooks.md`) + Gotcha nas 3 skills |
| `executeDestructive` | executor generico de operacoes destrutivas do catalogo diferido (research Decision 1) | idem |

O escopo `write:jira-work` inclui exclusao (research Decision 2): o menor
privilegio de escopo NAO impede delete — a garantia de FR-012 e do codigo.

## Parametros de entrada das tools

Os NOMES de parametro de cada tool NAO fazem parte deste contrato estatico:
o cliente MCP recebe o `inputSchema` de cada tool do proprio servidor em tempo
de execucao, e a skill MUST montar a chamada a partir desse schema exibido na
sessao — nunca de memoria. Qualquer parametro citado nas skills (ex.:
identificador de site/cloud, chave de projeto) so pode ser escrito depois de
lido do schema real ou de pagina oficial citada, conforme a secao
"Complemento de fontes" abaixo.

## Complemento de fontes (onda-004)

Pesquisa dirigida da onda-004 (acesso 2026-09-24):

| Item | Status | Fonte / citacao |
|------|--------|-----------------|
| `cloudId` obrigatorio em toda chamada; obtido via `getAccessibleAtlassianResources` | CONFIRMADO | supported-tools: "Required first call for any tool because every tool call needs a `cloudId`." |
| URL do site aceita como `cloudId` | CONFIRMADO | README oficial: `* **cloudId** = "https://yoursite.atlassian.net" (do NOT call getAccessibleAtlassianResources)` |
| API token nao e vinculado a um `cloudId` | CONFIRMADO | https://support.atlassian.com/atlassian-rovo-mcp-server/docs/configuring-authentication-via-api-token/: "Tokens are not bound to a specific `cloudId`. Clients and tools must explicitly pass the `cloudId` where needed." |
| exemplo oficial de `createJiraIssue` com `cloudId`, `projectKey`, `issueType`, `summary`, `description`, `parent` (Epic key) | EXEMPLO de skill oficial, NAO schema | https://raw.githubusercontent.com/atlassian/atlassian-mcp-server/main/skills/spec-to-backlog/SKILL.md; issue de usuario (nao-staff) mostra `issueTypeName` — conflito => a skill MUST ler o `inputSchema` real |
| `cloudId` sempre argumento de topo, nunca dentro de `inputs` | CONFIRMADO (skill oficial) | spec-to-backlog: "`cloudId` is always a top-level argument, never inside `inputs`." |
| tools secundarias via `executeRead(name=..., cloudId=..., inputs={...})` | EXEMPLO de skill oficial | https://raw.githubusercontent.com/atlassian/atlassian-mcp-server/main/skills/triage-issue/SKILL.md |
| parametros de `transitionJiraIssue`, `editJiraIssue`, `getJiraIssue`, `listJiraIssueTransitions` | **NAO ENCONTRADO** | schema so via `tools/list` autenticado |

Regra mantida: a skill monta a chamada a partir do `inputSchema` exibido na
sessao; os exemplos acima servem de orientacao, nao de contrato.

## Round r02 (2026-09-26) — escopo MCP do incremento FR-020..FR-025

- Nenhuma tool nova entra na allowlist: este contrato NAO cita (e o plan r02
  nao pesquisou) tool do Rovo MCP para Fix Version, labels ou issue links.
  Marco (R12/R13), labels em edicao (R14) e links (R16/R17) usam SEMPRE o
  helper REST (`jira-io.sh`), inclusive no caminho interativo. Sem
  `jq`/cliente HTTP, a conversao interativa via MCP segue criando Epic/Task/
  Sub-task e o `status` sinaliza `milestone=off`/links nao reconciliados
  (degradacao declarada, carve-out 1.1.0 condicao a) — nunca parametro de
  tool suposto.
- `createJiraProject` (ja na allowlist do r01 para "board/filtro/projeto")
  passa a ser usavel SO depois da confirmacao explicita do gate de FR-024 na
  sessao interativa, e e negada pela guarda `PreToolUse` quando ha execucao
  00c ativa (`hooks.md` r02).
