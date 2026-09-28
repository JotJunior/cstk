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

## Round r02 (2026-09-26) — decisoes do incremento FR-020..FR-025

Phase 0 do `/plan` do round r02 (onda-003 do round). Fonte factual unica das
operacoes novas: OpenAPI oficial do Jira Cloud REST v3 (mesmo arquivo e mesmo
sha256 das ondas 005/029 do r01 — ver `contracts/jira-rest.md` §"Operacoes do
round r02 (R12-R18)"). Nenhum roundtrip real nesta onda: o que o OpenAPI nao
determina esta marcado "a confirmar por roundtrip no execute-task" no contrato
e entra numa tarefa bloqueante (quickstart cenario 12).

**Classe estrutural**: nenhuma decisao abaixo reabre um dos 6 eixos fechados.
Arquitetura continua A1 (skills + hooks + helper REST; sem MCP dedicado),
runtime B1 (POSIX sh + `jq`/cliente HTTP so em `jira-io.sh`), persistencia C1
(arquivos texto versionados em `docs/specs/<feature>/` — os sidecars novos sao
mais arquivos do MESMO modelo, nao troca de mecanismo), ambiente D1 (so Jira
Cloud). Por isso sao Decisoes operacionais (score 2/3), sem bloqueio humano; a
unica politica que a spec exige humana (criacao de projeto) ja foi decidida na
Clarification r02 e aqui so ganha mecanismo.

### Decision R2-1: granularidade e nome do marco (FR-020)

**Decision**: o marco de uma sincronizacao e resolvido, nesta ordem (a
primeira regra que produzir nome vence; nunca combinadas):

1. `milestone_mode=off` em ProjectConfig => sem marco (plugin nao cria nem
   aplica Fix Version).
2. **Round ativo** — o state da feature (`.claude/feature-00c-state/<feature>/`,
   lido READ-ONLY pelo mesmo `resolve-state-field` do r01) tem
   `.previous_round.round` = `rNN` => marco = round corrente = `rNN+1`
   (conferido contra `1 + numero de diretorios rounds/r[0-9][0-9]`;
   divergencia => nome nao resolvido, nunca chute). Nome da Fix Version:
   `<feature>-r<NN>` (ex.: `cstk-jira-r02`).
3. **Release** (sem round ativo): `milestone_release` de ProjectConfig quando
   o operador o definir; senao o PRIMEIRO heading `## [X.Y.Z]` do
   `CHANGELOG.md` da raiz do projeto-alvo SE esse for o heading mais alto
   (se o mais alto for `[Unreleased]`, a versao-alvo ainda nao tem nome).
   Nome da Fix Version: a string SemVer tal-e-qual (ex.: `10.8.0`).
4. Nada resolvido => marco `unresolved`: os itens sao sincronizados SEM
   `fixVersions`, `jira-sync.sh status`/`hook.log` exibem
   `milestone=unresolved` com a instrucao (definir `milestone_release` ou
   `milestone_mode=off`), e a reconciliacao seguinte anexa o marco quando o
   nome passar a ser resolvivel.

**Rationale**: a Clarification r02 fixou "round se houver `.previous_round`,
senao release SemVer do CHANGELOG, nunca os dois no mesmo Epic". Fix Versions
sao do PROJETO Jira, compartilhado pelas features do projeto-alvo: um round
`r02` e por FEATURE (duas features reabertas teriam `r02` colidindo), dai o
prefixo `<feature>-`; uma release agrupa varias features de proposito, dai o
nome SemVer puro, compartilhado. `[Unreleased]` no topo (convencao Keep a
Changelog, adotada pelo proprio `CHANGELOG.md` deste repo) significa que o
numero da proxima versao NAO existe em nenhuma fonte — inventa-lo violaria o
Principio VI; o override `milestone_release` e a fonte explicita do operador.

**Alternatives considered**: (a) usar a ultima versao ja liberada do
CHANGELOG — rejeitada: rotula trabalho novo com a release anterior; (b)
calcular "proxima versao" por bump — rejeitada: dado inventado (Principio VI);
(c) bloquear a sincronizacao inteira enquanto o marco estiver `unresolved` —
rejeitada: o caso mais comum (primeira execucao com `[Unreleased]`) travaria
todo projeto que nao configurasse um override; a Clarification so proibe
itens sem marco no caso de FALHA de criacao (R2-4), nao no de nome ainda
inexistente; (d) nome de round sem prefixo de feature — rejeitada pela
colisao descrita acima.

### Decision R2-2: onde o marco se prende e como troca (FR-020, "nunca os dois")

**Decision**: o **Epic** carrega exatamente UM marco aplicado pelo plugin — o
CORRENTE; ao mudar (ex.: feature liberada em `10.7.0` e reaberta no round
`r02`), a edicao remove SO a versao que o proprio plugin gravou (rastreada no
SyncMarker, `written_fix_version_id`) e adiciona a nova, via `update.fixVersions`
add/remove (`contracts/jira-rest.md` R14). **Tasks/Sub-tasks** recebem o marco
vigente NA CRIACAO (R1, `fields.fixVersions`) e nao sao remarcadas depois — o
historico "esta task foi feita no round X / release Y" fica nas tasks. Versao
posta a mao por humano nunca e removida. Sub-task so recebe `fixVersions` se o
campo existir na tela de criacao do tipo Sub-task (R8 `FieldCreateMetadata`,
conferido no setup) — e o "quando aplicavel" de FR-020.

**Rationale**: satisfaz "nunca os dois simultaneamente para o mesmo Epic" sem
apagar historia; `update` add/remove evita o clobber de `fields.fixVersions`
(substitui a lista inteira).

**Alternatives considered**: (a) acumular marcos no Epic — viola a
Clarification; (b) `fields.fixVersions` na edicao — apagaria versoes humanas;
(c) remarcar todas as tasks antigas no reopen — reescreve historia e multiplica
escritas (rate limit por issue).

**Risco**: a forma `update.fixVersions` nao tem exemplo no OpenAPI. Se o
roundtrip reprovar, a troca de marco do Epic degrada para "sinalizar
`milestone_drift` e nao escrever" (nunca para clobber).

### Decision R2-3: criacao automatica e idempotencia do marco (FR-020, FR-021, FR-023)

**Decision**: antes de criar, `R13` (`getProjectVersions`, nao-paginada) e
casamento de `name` por IGUALDADE EXATA local; achou => reusa o `id`. Nao
achou => `R12` (`createVersion`) com `name`, `projectId` (numero) e
`description` fixa do plugin. Qualquer `400` em R12 => refaz R13 e reusa se o
nome exato apareceu (corrida entre execucoes paralelas em worktrees distintas,
FR-023); senao `deferred`. O par `(project_key, name) -> version_id` e
gravado no sidecar versionado `jira-milestones.tsv` da feature (rastreabilidade
SC-005 + cache), mas a AUTORIDADE de idempotencia e a lista remota (a versao e
compartilhada entre features; o sidecar de uma feature nao ve o de outra).

**Rationale**: `name` e "unique" no schema, mas o status de duplicata nao e
documentado — reler e o unico comportamento seguro sem supor codigo HTTP.
Rota nao-paginada = nenhum nome em querystring (SEC-3/SEC-6).

**Alternatives considered**: `getProjectVersionsPaginated` com `query` —
casamento aproximado case-insensitive, exige interpolar o nome em URL;
sidecar local como autoridade — cego para versoes criadas por outra feature/
worktree ou a mao.

### Decision R2-4: falha de permissao ao criar o marco (FR-020 + FR-016)

**Decision**: `jira-io.sh request --op R12` classifica `403` (se vier) e
`404` como `permission_denied` (exit 7). O motor entao: grava
`milestone=blocked:<nome>` no status/`hook.log` com diagnostico ("a
credencial precisa de Administer Projects no projeto — ou defina
`milestone_mode=off`"); SUSPENDE a criacao de issues NOVAS desta feature
(nenhum Epic/Task orfao sem marco — Clarification r02); continua as
transicoes de status de issues JA mapeadas (nao sao orfas, e SC-003 segue
valendo); nao repete R12 ate o operador reconfigurar (mesmo gate de
`requeue-auth-failed`: `jira-setup.sh write-config` limpa o bloqueio).

**Rationale**: OpenAPI de `createVersion` documenta a falta de permissao como
`404` (nao `403`) e a permissao exigida (*Administer Jira* ou *Administer
Projects*); o `project_key` ja foi resolvido por `getProject` na mesma
execucao, entao `404` aqui nao e "projeto inexistente". A divergencia com o
texto da spec ("HTTP 403") esta registrada no contrato e vai ao roundtrip.

**Alternatives considered**: tratar como `auth_failed` (exit 4) — faria o
operador trocar um token valido; seguir criando issues sem marco —
proibido pela Clarification.

### Decision R2-5: label de FASE (FR-022)

**Decision**: label `phase-<N>` (N = numero do heading `### FASE N` que
contem a task; Sub-task herda a FASE da task-pai; Epic sem label). Validado
pela allowlist de SEC-1 (`[A-Za-z0-9_-]`) antes de montar o corpo — nenhuma
allowlist nova. Criacao: `fields.labels: ["phase-<N>"]` (R14). Mudanca de
fase num round posterior (edge case da spec): `update.labels`
`[{"remove":"<label gravado antes>"},{"add":"phase-<M>"}]` — remove SO o label
que o plugin gravou (SyncMarker `written_phase_label`), preservando labels
humanos. `labels_enabled=off` desliga; o setup confere via R8 se `labels` esta
na tela de criacao de Task e Sub-task e, se nao estiver, grava `off` com
aviso. Labels NAO entram na deteccao de conflito (FR-011 continua olhando
titulo/status/descricao): label humano extra nao e conflito.

**Rationale**: forma `{"add":...}`/`{"remove":...}` tem exemplo oficial em
`editIssue`; a Clarification fixou formato e allowlist.

**Alternatives considered**: `fields.labels` na edicao (clobber de labels
humanos); label por nome completo da FASE (espacos/acentos falham SEC-1);
componente em vez de label (exige criar componente no projeto — escrita
administrativa a mais, fora do pedido).

### Decision R2-6: dependencias como issue links (FR-025)

**Decision**:

- **Granularidade** — a Matriz de Dependencias do template e FASE-a-FASE
  (`jira-tasks.sh phase-deps`, unica fonte real) e FASE nao e issue no Jira
  (e label, R2-5). Cada aresta `FASE A --> FASE B` vira **exatamente 1 link**
  entre as **ancoras** das duas fases: ancora = a Task de menor `local_key`
  (`N.M`) da FASE com linha `active` no `jira-map.tsv`. FASE sem task mapeada
  => aresta `unrepresentable` (motivo `no_anchor`).
- **Tipo** — (1) `link_type_id` em ProjectConfig, gravado no setup APOS o
  operador confirmar, sobre a lista de R16, qual tipo significa "bloqueia /
  e bloqueado por" (mesmo padrao da confirmacao de `issue_type_*` do r01);
  (2) sem `link_type_id` (sessao autonoma, setup antigo): candidato unico cujas
  frases `inward` E `outward` contem, case-insensitive, a raiz `block` (a raiz
  vem das frases do exemplo oficial de R16, e e aplicada as frases que o
  PROPRIO site devolve — nunca ao `name`); zero ou 2+ candidatos =>
  `unrepresentable` (motivo `no_link_type`/`ambiguous_link_type`), sem escolher
  arbitrariamente (Clarification r02). `404` em R16 (linking desligado) =>
  todas `unrepresentable` (motivo `linking_disabled`).
- **Direcao** — bloqueador (ancora de A) em `outwardIssue`, bloqueado (ancora
  de B) em `inwardIssue`; confirmacao por roundtrip obrigatoria (contrato R17).
- **Idempotencia** — sidecar versionado `jira-links.tsv` (1 linha por aresta);
  linha `active` => nao chama R17; alem disso o OpenAPI garante que reenviar
  um link duplicado nao cria outro. `413` => `unrepresentable` (`limit`).
- **Ancora que muda** (renumeracao/reorganizacao) => link antigo marcado
  `stale` e sinalizado; NUNCA removido (sem `DELETE`, FR-012); o link novo e
  criado para a ancora nova.

**Rationale**: "cada dependencia declarada = um link" (1:1 com as arestas),
minimo de escritas (rate limit por issue, limite de links por issue do `413`)
e deterministico. `links_enabled=off` desliga tudo.

**Alternatives considered**: (a) produto cartesiano tasks(A) x tasks(B) —
explode o numero de links e, sem `DELETE`, seria irreversivel pelo plugin;
(b) link Epic->Epic — so ha 1 Epic por feature, as arestas sao internas a
ela; (c) criar uma issue por FASE para servir de no — adiciona um nivel de
hierarquia que o r01 recusou (FASE = prefixo de titulo/label); (d) tipo por
`name` literal (ex.: "Blocks") — vedado pela Clarification.

### Decision R2-7: criacao de projeto com gate humano (FR-024)

**Decision**: o path REST agora tem fonte (R18, `createProject`) e SUPERA o
`NAO ENCONTRADO` da Decision 3. Fluxo:

- `jira-setup` SEMPRE tenta reusar primeiro (`getProject` pela key proposta,
  `searchProjects` para listar). So oferece criar quando nao ha projeto.
- **Gate**: o operador confirma explicitamente `name`, `key` (regra do
  OpenAPI: maiuscula inicial, alfanumerico maiusculo, <= 10 chars — validada
  localmente tambem por SEC-1), `projectTypeKey=software` e o template
  (default pre-selecionado `gh-simplified-agility-kanban`, lista do OpenAPI).
  `leadAccountId` = `accountId` de `GET /rest/api/3/myself`.
- **Interativo**: confirmacao explicita na propria sessao, repetindo a key
  (`jira-setup.sh create-project --confirm-key KEY` recusa sem ela).
- **Autonomo** (execucao 00c ativa): a skill NUNCA chama R18 nem a tool
  `createJiraProject`; devolve ao orquestrador um pedido de gate e o
  orquestrador registra bloqueio humano (`register_human_block`/`bloqueios.sh
  register`; ou `ask_operator` com `kind=confirm` e `default_value` = nao
  criar — timeout/recusa nunca cria). So na onda seguinte, com o bloqueio
  `respondido`, `create-project` roda com `--consent-block block-NNN`, e o
  script confere o bloqueio via runtime (`bloqueios.sh list --status
  respondido`, delegacao ao `agente-00c-runtime` como no r01 13.1.1).
- `403` => `permission_denied` => orientar criacao manual (UI do Jira ou
  `createJiraProject` por admin) — ramo "mecanismo nao suporta" de FR-024.
- Guarda mecanica: o hook `PreToolUse` do plugin passa a negar (exit 2)
  `mcp__.*__createJiraProject` quando ha execucao 00c ativa no cwd e o plugin
  esta configurado (`contracts/hooks.md`).

**Rationale**: Clarification r02 (gate obrigatorio, nunca autonomo); o
consentimento vira artefato auditavel (bloqueio respondido), nao uma flag
que o proprio agente poderia passar.

**Alternatives considered**: flag `--yes` (o agente se autoaprovaria);
criar via Rovo MCP no caminho autonomo (mesmo problema, e o allowlist dos
orquestradores e fechado); nao oferecer criacao (viola FR-024).

### Decision R2-8: um Epic por feature do roadmap (FR-023)

**Decision**: nenhuma mudanca no motor — cada execucao `feature-00c` ja
sincroniza SO a propria `short_name` (1 feature = 1 Epic, FR-001), e o
lancamento paralelo do roadmap roda cada feature numa worktree dedicada
(`parallel-launch.sh`, `<pai-do-repo>/<nome-do-repo>-<SHORT>`). O unico gap e
de CONFIGURACAO: numa worktree nova o `.claude/cstk-jira/config` pode nao
existir (arquivo de versionamento opcional) e o hook ficaria inativo. O hook e
os scripts passam a resolver ProjectConfig primeiro no cwd e, ausente, na
worktree principal (`git rev-parse --git-common-dir`, normalizado para
absoluto — o valor pode vir relativo ou absoluto conforme a versao do git),
somente leitura. `runtime/` (outbox, conflitos, lock de drain) continua POR
worktree. A corrida de criacao de Fix Version compartilhada e tratada em R2-3.

**Rationale**: a Clarification r02 fixou FR-023 como comportamento agregado
de execucoes independentes; sem roadmap, caso base FR-001.

**Alternatives considered**: um motor "multi-feature" numa execucao — nao
existe execucao que conheca N features (Clarification); outbox compartilhado
entre worktrees — lock cross-worktree sem necessidade.

### Decision R2-9: nomes de versao e SEC

**Decision**: nomes de Fix Version passam por uma allowlist propria
`^[A-Za-z0-9][A-Za-z0-9._-]{0,254}$` (SEC-6 no plan): SEC-1 + o ponto do
SemVer, teto de 255 do OpenAPI. O nome NUNCA entra em PATH, querystring ou
JQL (R13 lista tudo; o casamento e local); entra so no corpo JSON via
`jq --arg`. Labels usam SEC-1 sem mudanca.

**Rationale**: SemVer precisa de `.`, que SEC-1 recusa; afrouxar SEC-1 para
todos os segmentos de PATH seria regressao de seguranca.

**Alternatives considered**: trocar `.` por `-` no nome (`10-8-0`) — o marco
deixaria de ser reconhecivel como a release; afrouxar SEC-1 globalmente.
