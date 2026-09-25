# Research: cstk-jira

Documento do Phase 0 do `/plan` (execucao autonoma feature-00c, onda-003).
Resolve os unknowns tecnicos de FR-006 e FR-019-INFRA-REFRESH com **fontes
oficiais citaveis** (Principio VI) e isola as decisoes de **classe
estrutural** que NAO sao resolvidas por inferencia (ver secao 3) — elas
ficaram como `NEEDS CLARIFICATION` ate o consentimento do operador (resolvidas na onda-004, secao 3).

**Metodo e ressalvas de fonte**

- Pesquisa por WebSearch/WebFetch restrita a paginas oficiais da Atlassian
  (developer.atlassian.com, support.atlassian.com, atlassian.com,
  confluence.atlassian.com, community.developer.atlassian.com em posts de
  staff da Atlassian, github.com/atlassian). Data de acesso: 2026-09-24.
- As paginas de referencia `/cloud/jira/platform/rest/v3/api-group-*` e o
  swagger JSON **nao renderizaram** via WebFetch (conteudo vazio/truncado).
  Por isso varios endpoints REST v3 abaixo sao citados por avisos de
  mudanca/KBs oficiais, nao pela pagina de referencia. **Todo path/campo
  que entrar num contrato na Phase 1 MUST ser reconferido contra a pagina de
  referencia (ou uma chamada observada) na implementacao.**
- Citacoes vem do extrator do WebFetch; sao majoritariamente literais, mas
  devem ser reconferidas antes de virar contrato.
- Itens marcados `INFERENCIA` nao estao escritos literalmente na fonte.
  Itens marcados `NAO ENCONTRADO` nao tem fonte e NAO podem ser usados como
  dado factual.

Fatos locais observados (nao-web):

| Fato | Fonte |
|------|-------|
| Existe descritor MCP local `atlassian` tipo `http` em `https://mcp.atlassian.com/v1/mcp` | `.mcp.json` de um plugin de dados sincronizado em `~/.claude/plugins/synced/.../data~g2/.mcp.json` (lido nesta onda) |
| Nesta sessao, desse servidor so estao visiveis `authenticate` e `complete_authentication` (nao autenticado) | observacao da sessao, relatada pelo command pai |
| `marketplace.json` tem hoje 2 plugins (`cstk`, `cstk-language-go`) e o gate `MP-2` exige **exatamente 2** entradas | `.claude-plugin/marketplace.json`; `scripts/validate-plugin-manifests.sh` L11, L95-98 |
| Unico servidor MCP do repo e `plugins/cstk/mcp/state-server` (TypeScript/Node >=22, deps `@modelcontextprotocol/sdk` + `zod`), confinado por decisao do operador | `plugins/cstk/mcp/state-server/package.json`; `docs/specs/_archived/2026-08-03-state-mcp-server/plan.md` L34-35, L145, L218 |
| O allowlist de tools do orquestrador feature-00c e FECHADO no frontmatter (so `mcp__cstk-state__*` / `mcp__plugin_cstk_cstk-state__*`) | `plugins/cstk/agents/agente-00c-feature-orchestrator.md` L4 |
| `bash-guard` bloqueia comando de rede sem URL identificavel ou com URL fora do whitelist da execucao | `plugins/cstk/skills/agente-00c-runtime/scripts/bash-guard.sh` L15-17, L320-370 (observado nesta onda: bloqueou ate um `grep` e um heredoc que so continham a palavra do cliente HTTP ou uma URL fora do whitelist) |
| `cli/lib/http.sh` ja usa um cliente HTTP de linha de comando com allowlist de hosts por salto (`trusted-hosts.sh`) | `cli/lib/http.sh` cabecalho |

## Decision 1: Existe um MCP de Jira generico que cobre as operacoes? (FR-006, FR-010)

**Decision**: Sim — o **Atlassian Rovo MCP Server** (remoto, oficial) expoe
as operacoes necessarias. Consequencia para FR-010: um servidor MCP
dedicado do cstk-jira que so reembrulhe criar/editar/transicionar seria
**redundante** e fica vedado pelo proprio FR-010 (MUST NOT), salvo se a
decisao estrutural de arquitetura (secao 3, D-A) concluir o contrario com
justificativa.

**Evidencias (fonte oficial)**:

- Endpoint recomendado `https://mcp.atlassian.com/v2/mcp`; `v1/mcp` segue
  suportado e passa a expor tools v2 —
  https://raw.githubusercontent.com/atlassian/atlassian-mcp-server/main/README.md
  ("the recommended endpoint for all clients is: `https://mcp.atlassian.com/v2/mcp`").
  A data da migracao automatica v1->v2 conflita entre o README (sem data) e
  https://support.atlassian.com/atlassian-rovo-mcp-server/docs/getting-started-with-the-atlassian-remote-mcp-server/
  ("On March 1, 2027 ..."). `INFERENCIA`: o descritor local (`v1/mcp`)
  deveria migrar para `v2/mcp`.
- Os nomes de tool abaixo existem **somente no MCP v2** —
  https://support.atlassian.com/atlassian-rovo-mcp-server/docs/supported-tools/
  ("The tools listed on this page are only available with Atlassian MCP v2."),
  confirmado em https://developer.atlassian.com/cloud/rovo-mcp/guides/supported-tools/.

| Necessidade da spec | Tool Rovo MCP |
|---|---|
| criar issue (FR-001) | `createJiraIssue` |
| editar issue (FR-003) | `editJiraIssue` |
| ler issue | `getJiraIssue` |
| transicoes disponiveis (FR-004) | `listJiraIssueTransitions` |
| transicionar (FR-004) | `transitionJiraIssue` |
| busca JQL (FR-013) | `searchJiraIssuesUsingJql` |
| tipos de issue do projeto | `listJiraProjectIssueTypesMetadata` |
| metadados de campos | `getJiraIssueTypeMetaWithFields` |
| historico de mudancas (FR-011) | `listJiraIssueChangelogs` |
| ler/gravar propriedade da issue (marcador de sync) | `getJiraEntityProperty` / `editJiraEntityProperty` |
| boards/filtros/projetos (FR-002) | `listJiraBoards`, `listJiraFilters`, `listJiraProjects`, `createJiraBoard` ("Create a company-managed board from an existing filter."), `createJiraProject` |
| **proibido pelo FR-012** | `deleteJiraIssue` ("Permanently delete an issue. Cannot be undone.") |

- Catalogo diferido: tools secundarias via "discover" + `executeRead` /
  `executeWrite` / `executeDestructive`; lista plana em
  `https://mcp.atlassian.com/v2/mcp?tools=all` (mesmas paginas de supported-tools).
- `INFERENCIA` (FR-012): como o servidor expoe `deleteJiraIssue` e
  `executeDestructive`, o plugin precisa de uma deny-list explicita dessas
  tools — o MCP generico nao impede exclusao por si so.

**Restricao critica para US3 (sincronizacao autonoma)**: o orquestrador
feature-00c/agente-00c roda com allowlist de tools FECHADA no frontmatter
(fato local acima). As tools do Rovo MCP so estariam visiveis a ele se o
frontmatter fosse ampliado — e o prefixo do nome depende de como cada
usuario instalou o servidor (`mcp__plugin_<plugin>_<server>__<tool>` quando
vem de plugin — convencao ja registrada na feature `claude-plugin-packaging`).
Alem disso, hooks de linha de comando nao chamam tools MCP. Isso e insumo
direto da decisao estrutural D-A.

**Alternatives considered**: MCPs de Jira de terceiros — fora da pesquisa
(Principio VI: nenhum foi lido de fato; nao ha base para afirmar
capacidades).

## Decision 2: Autenticacao e renovacao (FR-016, FR-019-INFRA-REFRESH)

**Decision (CONFIRMADA com A1 na onda-004 — dec-020)**: API token do Atlassian
account (Basic auth `email:api_token`) como mecanismo padrao para os dois
caminhos, porque e o unico com fonte que funciona **sem tela de
consentimento** (requisito de execucao autonoma). Renovacao automatica NAO e
possivel para API token (o token tem data de expiracao fixa e so o usuario
gera outro): portanto FR-019 se resolve pelo seu proprio ramo "quando nao for
possivel, tratar como credencial invalida (FR-016)" — rejeicao de
autenticacao => suspender a sincronizacao com diagnostico explicito de
reconfiguracao, nunca retry silencioso.

**Evidencias**:

- Rovo MCP: OAuth 2.1 por padrao; headless via API token, **se o admin da
  organizacao habilitar** —
  https://developer.atlassian.com/cloud/rovo-mcp/guides/configuring-authentication-via-api-token/
  ("Authentication via API token lets MCP clients send credentials directly in the request header, without an interactive OAuth consent screen." /
  "must be enabled by your organization admin. If it is disabled, MCP clients must use OAuth 2.1 instead.").
  Headers: `Authorization: Basic <base64(email:api_token)>` ou
  `Authorization: Bearer <api_key>` (service account) — README oficial acima.
- REST Cloud Basic auth —
  https://developer.atlassian.com/cloud/jira/platform/basic-auth-for-rest-apis/
  ("Supply an `Authorization` header with content `Basic` followed by the encoded string."; "Authentication using passwords has been deprecated.").
- Expiracao de API token —
  https://support.atlassian.com/atlassian-account/docs/manage-api-tokens-for-your-atlassian-account/
  ("After December 15, 2024, we set new API tokens to expire in one year by default." / "from one day up to one year").
  Tokens com escopo exigem chamar a API via `api.atlassian.com` (mesma
  pagina; `INFERENCIA` sobre o host exato).
- OAuth 2.0 3LO (alternativa): token endpoint `https://auth.atlassian.com/oauth/token`;
  refresh tokens rotativos com expiracao por inatividade de 90 dias;
  `offline_access` no scope; chamadas via
  `https://api.atlassian.com/ex/jira/{cloudid}/rest/api/3/...` —
  https://developer.atlassian.com/cloud/jira/platform/oauth-2-3lo-apps/ ,
  https://developer.atlassian.com/cloud/oauth/getting-started/refresh-tokens/ .
  Scopes classicos: `read:jira-work`, `write:jira-work` (inclui "delete issues"),
  `manage:jira-project`, `manage:jira-configuration` —
  https://developer.atlassian.com/cloud/jira/platform/scopes-for-oauth-2-3LO-and-forge-apps/ .
  `NAO ENCONTRADO`: tempo de vida fixo do access token (so `expires_in` na
  resposta) e expiracao absoluta do refresh token.

**Rationale**: 3LO exige um app registrado (client id/secret) por
distribuicao e um fluxo de navegador — incompativel com "sem confirmacao
manual a cada sincronizacao" (FR-005) sem infraestrutura adicional; o API
token cobre REST e Rovo MCP headless com a mesma credencial.

**Alternatives considered**: OAuth 3LO (renovavel, mas exige app registrado
+ consentimento); service account API key (Bearer) — valida para o Rovo MCP,
fica como opcao de configuracao.

**Seguranca (insumo para o gate owasp da Phase 1)**: a credencial NUNCA vai
para artefato versionado, state, log ou relatorio; `write:jira-work` inclui
exclusao, entao o menor privilegio de escopo nao impede delete — a garantia
de FR-012 e do codigo (deny-list), nao do escopo.

## Decision 3: Endpoints REST do fallback (FR-006 fallback universal)

**Decision**: o caminho REST usa apenas os endpoints abaixo, todos com fonte;
itens sem fonte ficam FORA do contrato ate reconferencia.

| Operacao | Metodo + path | Fonte |
|---|---|---|
| criar issue | `POST /rest/api/3/issue` | https://community.developer.atlassian.com/t/deprecation-of-the-epic-link-parent-link-and-other-related-fields-in-rest-apis-and-webhooks/54048 (staff Atlassian) |
| criar em lote (<=50) | `POST /rest/api/3/issue/bulk` | https://community.developer.atlassian.com/t/change-on-number-of-issues-can-be-created-in-a-single-bulk-create-issues-request/54083 ("allow creation of up to 50 issues in a single request") |
| editar issue | `PUT /rest/api/3/issue/{issueIdOrKey}` | post de epic-link acima |
| ler issue | `GET /rest/api/3/issue/{issueIdOrKey}` | https://support.atlassian.com/jira/kb/retrieve-data-with-jira-rest-api-in-automation-to-update-issue-fields/ |
| transicionar | `POST /rest/api/3/issue/{issueIdOrKey}/transitions` | https://developer.atlassian.com/cloud/jira/platform/change-notice-update-in-simultaneous-transitions-issue-api/ |
| listar transicoes | `GET .../issue/{issueIdOrKey}/transitions` | so citacao **v2** encontrada (KB de JWM); v3 = `INFERENCIA` a reconferir |
| propriedade de issue | `PUT/GET /rest/api/3/issue/{issueIdOrKey}/properties/{propertyKey}` (max 32 KB) | https://developer.atlassian.com/cloud/jira/platform/jira-entity-properties/ |
| busca JQL | `GET/POST /rest/api/3/search/jql` (paginacao `nextPageToken`); `/rest/api/3/search` **removido** | https://confluence.atlassian.com/jirakb/run-jql-search-query-using-jira-cloud-rest-api-1289424308.html |
| tipos de issue p/ criacao | `GET /rest/api/3/issue/createmeta/{projectIdOrKey}/issuetypes[/{issueTypeId}]` | https://community.developer.atlassian.com/t/create-issue-meta-endpoint-deprecation/75413 (staff Atlassian) |
| hierarquia Epic->filho | campo `parent` (Epic Link `customfield_10014` descontinuado); `hierarchyLevel` -1/0/1 | post de epic-link acima |
| criar filtro | `POST /rest/api/3/filter` (`name`, `jql`) | https://support.atlassian.com/jira/kb/creating-and-granting-edit-permission-for-filters-in-team-managed-projects-via-rest-api/ |
| criar board | `POST /rest/agile/1.0/board` (`name`, `type` scrum/kanban, `filterId`, `location`) | https://developer.atlassian.com/cloud/jira/software/rest/api-group-board/ |
| boards do projeto | `GET /rest/agile/1.0/board?projectKeyOrId=...` | mesma pagina |

`NAO ENCONTRADO` (nao entram em contrato sem nova fonte): endpoint REST de
changelog da issue; citacao literal do campo `updated`; citacao de que
Subtask usa `parent`; path v3 de criacao de projeto e sua permissao atual
(so ha v2 de 2019: `POST /rest/api/2/project`, "Administer Jira global
permission").

**Consequencias de design (operacionais)**:

- Concorrencia de transicao: requisicoes simultaneas na mesma issue — so uma
  vence, as demais retornam 400 (mudanca planejada para 409) — mesma pagina
  de change-notice. A sincronizacao MUST serializar escritas por issue.
- Rate limit — https://developer.atlassian.com/cloud/jira/platform/rate-limiting/ :
  HTTP 429 + `Retry-After`; limite por issue ("20 write operations per 2
  seconds"). Rovo MCP tem cota por hora por plano
  (https://www.atlassian.com/platform/rovo-mcp: "Free 500 calls per hour").
  Politica (default de design, nao dado externo): respeitar `Retry-After`,
  backoff limitado, e ao estourar o orcamento **adiar** a sincronizacao sem
  parar a execucao da feature (edge case da spec).
- Conflito manual (FR-011): marcador de sync gravado como entity property
  (hash do ultimo estado sincronizado) + comparacao com o estado atual da
  issue antes de escrever. `INFERENCIA`: JQL por entity property exige
  indice Connect/Forge — um cliente REST puro NAO consegue localizar issues
  pela propriedade; por isso o mapeamento local (FR-014) e a fonte primaria
  de localizacao. Aviso oficial: nao guardar dado sensivel/config em entity
  property (pagina de entity properties).

## Decision 4: Data Center / Server

**Decision**: somente Jira Cloud (D1, dec-023 / block-004) — eixo estrutural `ambiente-alvo`
(D-D, secao 3).

**Evidencias**: Rovo MCP e oferecido a clientes Cloud
(https://www.atlassian.com/platform/rovo-mcp: "All Atlassian Cloud customers
have access to the Atlassian Rovo MCP server."); declaracao explicita de
"DC nao suportado" = `NAO ENCONTRADO`. DC usa Personal Access Token com
`Authorization: Bearer` (Jira 8.14+) —
https://confluence.atlassian.com/enterprise/using-personal-access-tokens-1026032365.html ;
endpoints DC divergem do Cloud (ex.: criacao de projeto por template "Data
Center Only").

## 3. Decisoes de classe estrutural (RESOLVIDAS pelo operador na onda-004)

> **Resolucao (onda-004)**: o operador respondeu os 4 bloqueios; as Decisoes
> foram reapresentadas com consentimento vinculado ao eixo:
> D-A = **A1** (dec-020 / block-001), D-B = **B1** (dec-021 / block-002),
> D-C = **C1** (dec-022 / block-003), D-D = **D1** (dec-023 / block-004).
> Nenhum `NEEDS CLARIFICATION` estrutural permanece. O texto abaixo e o
> registro historico das opcoes apresentadas.

### Registro original (onda-003)

Por FR-009 (skill plan, modo autonomo) e pela trava de classe estrutural do
runtime, os itens abaixo NAO sao resolvidos por inferencia. Cada um virou
Decisao `--classe estrutural` + BloqueioHumano (`subject_key axis:<eixo>`).
A Phase 1 (data-model, contracts, quickstart, plan.md) so e produzida apos
as respostas.

### D-A — `arquitetura`: como o plugin fala com o Jira e como a sincronizacao autonoma e disparada

- **A1 (recomendada)**: plugin `plugins/cstk-jira/` com skills (conversao,
  sync, setup) que usam o Rovo MCP quando suas tools estao visiveis na
  sessao interativa, e um **helper REST local** para o resto; a
  sincronizacao autonoma (US3/FR-018) e disparada por **hook do proprio
  plugin** nos pontos de ciclo de vida ja existentes (registro de outcome de
  task / fechamento de onda) e usa o helper REST — sem servidor MCP dedicado
  (FR-010) e sem mexer no allowlist fechado dos orquestradores. Custo: no
  caminho autonomo o REST vira o caminho efetivo (MCP so no interativo) —
  tensao com a Clarification "MCP preferencial".
- **A2**: servidor MCP dedicado `cstk-jira` (Node, como o state-server) que
  encapsula REST e e allowlistado nos orquestradores. Contra: redundante com
  o Rovo MCP (FR-010 MUST NOT), segunda arvore Node.
- **A3**: orquestradores chamam o Rovo MCP diretamente. Contra: nome das
  tools varia por instalacao; exige ampliar allowlist fechado; MCP headless
  depende de o admin habilitar API token.

### D-B — `linguagem-runtime`: implementacao do helper REST (se A1/A3)

- **B1 (recomendada)**: POSIX sh + cliente HTTP de linha de comando (o mesmo
  de `cli/lib/http.sh`), com `jq` para JSON sob o carve-out 1.1.0 do
  Principio II (deps confinadas em UM arquivo, declaradas no plan, fallback =
  caminho Rovo MCP interativo; sem as deps o sync autonomo falha com
  diagnostico explicito, nunca silencioso). Tensao: a condicao (a) do
  carve-out ("funciona sem a ferramenta") e discutivel para o caminho
  autonomo — exige confirmacao explicita do operador.
- **B2**: Node/TS zero-dependencia (fetch nativo, `node:test`) confinado em
  `plugins/cstk-jira/`, mesmo regime do state-server. Contra: briefing
  "Markdown + POSIX sh"; segunda arvore Node.

### D-C — `persistencia`: onde vive o mapeamento local <-> Jira (FR-014)

- **C1 (recomendada)**: arquivo versionado por feature em
  `docs/specs/<feature>/` (formato texto tabular, POSIX-friendly) como fonte
  primaria + entity property no Jira como marcador secundario de conflito.
  Sobrevive entre execucoes e ao uso manual fora do 00c.
- **C2**: `state.db` da execucao 00c. Contra: nao existe fora de execucao
  autonoma; conversao manual (US1) ficaria sem mapeamento.
- **C3**: so entity property no Jira. Contra: sem busca por propriedade via
  REST puro (INFERENCIA acima) => nao localiza issues.

### D-D — `ambiente-alvo`: Jira Cloud apenas, ou Cloud + Data Center

- **D1 (recomendada)**: somente Jira Cloud no escopo desta feature; DC
  declarado fora de escopo (Rovo MCP e Cloud; endpoints/auth divergem).
- **D2**: Cloud + DC (PAT Bearer, endpoints proprios). Contra: dobra a
  matriz de contrato/teste e o caminho MCP nao existe para DC.

## Impactos ja identificados para a Phase 1 (operacionais)

- Adicionar o 3o plugin ao marketplace exige mudar o invariante `MP-2`
  ("exatamente 2") de `scripts/validate-plugin-manifests.sh` e respeitar o
  lockstep de versao (`MP-5`).
- FR-015 (so o dominio Jira configurado): comandos de rede do caminho
  autonomo passam pelo `bash-guard` — o dominio configurado precisa entrar no
  whitelist da execucao; o helper deve validar o host por salto como
  `cli/lib/http.sh`.
- FR-017: hooks do plugin devem ser no-op total quando nao ha configuracao
  Jira no projeto.
