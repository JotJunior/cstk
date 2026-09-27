# Quickstart / Cenarios de Teste: cstk-jira

Cenarios de validacao manual e de aceitacao. Placeholders entre `<>` sao
preenchidos pelo operador com os dados do PROPRIO site Jira Cloud — nenhum
valor abaixo e um dado real.

## Pre-requisitos

- Site Jira Cloud `https://<site>.atlassian.net` (D1: Data Center/Server fora
  de escopo) com um projeto dedicado a este projeto-alvo (FR-002).
- API token do Atlassian account (research Decision 2 — expira em ate 1 ano).
- Opcional (uso interativo): Atlassian Rovo MCP configurado na sessao; endpoint
  recomendado `https://mcp.atlassian.com/v2/mcp` (README oficial citado em
  `research.md` Decision 1).
- Opcional (sync autonomo): `jq` e o cliente HTTP de linha de comando no PATH.

## Cenario 1 — Instalacao pelo marketplace (US4 cenario 1, FR-008)

1. Adicionar o marketplace e instalar, como os demais plugins
   (padrao de `README.md` L339-342, que instala `cstk@cstk` e `cstk-language-go@cstk`): `/plugin marketplace add JotJunior/cstk` e
   `/plugin install cstk-jira@cstk` (nome do plugin = DESIGN deste plano).
2. Listar skills disponiveis.

**Expected**: `jira-setup`, `jira-convert`, `jira-sync` visiveis; hooks do
plugin ativos; nenhuma mudanca no comportamento de outras skills.

## Cenario 2 — Plugin instalado e inativo (US4 cenario 3, FR-017, SC-006)

1. Sem `.claude/cstk-jira/config`, rodar uma onda `feature-00c` qualquer que
   registre outcome de task e feche onda.

**Expected**: hooks saem em no-op (exit 0, stdout vazio); nenhum arquivo em
`.claude/cstk-jira/`; nenhuma rede; nenhuma mensagem nova.

## Cenario 3 — Setup guiado (US4 cenario 2, FR-007, SC-004)

1. Invocar a skill `jira-setup`; informar `<site>` e `<PROJECT_KEY>`.
2. Em um terminal PROPRIO (nunca no chat — o token entraria no transcript),
   rodar o comando de credencial que a skill exibe; digitar email e token com
   eco desligado.
3. A skill valida a credencial remotamente, descobre tipos de issue e
   status/transicoes e pede o mapeamento `pending/in_progress/pass/fail`.
4. A skill lista os tipos de issue descobertos (`id`, `name`,
   `hierarchyLevel`, `subtask`) e pede ao operador que confirme qual e Epic,
   qual e Task e qual e Sub-task (o valor de `hierarchyLevel` de Epic e `NAO
   ENCONTRADO` nas fontes oficiais — o sistema nunca infere sozinho).
5. A skill cria (ou reusa) filtro + board kanban do projeto.

**Expected**: `.claude/cstk-jira/config` valido (`jira-config.sh validate` exit
0); arquivo de credencial com modo `0600` fora do repo; `issue_type_epic`/
`issue_type_task`/`issue_type_subtask` gravados SOMENTE apos confirmacao
explicita do operador (passo 4); `board_id` gravado; nenhum segredo em
arquivo versionado (`git grep` pelo email/token nao acha nada).

**Error case 3a**: mapear `fail` para o mesmo status de `pass` => setup recusa
com diagnostico pedindo um status distinto no workflow.

**Error case 3b**: token invalido => diagnostico de credencial rejeitada;
nenhum `config` parcial marcado como valido.

## Cenario 4 — Conversao da feature (US1, FR-001/003/013/014, SC-001/002/005)

1. Com uma feature com `spec.md` + `tasks.md`, invocar `jira-convert <feature>`.
2. Conferir no Jira o Epic, as Tasks filhas e as Sub-tasks.
3. Rodar `jira-convert <feature>` mais 9 vezes seguidas.
4. Acrescentar uma task `### N.M` nova ao `tasks.md` e rodar de novo.

**Expected**: passo 1 cria 1 Epic + 1 issue por task/subtask, todas presentes
em `docs/specs/<feature>/jira-map.tsv` com SyncMarker gravado; passo 3 cria 0
issues (SC-002); passo 4 cria SO a task nova (US1 cenario 2).

**Error case 4a** (US1 cenario 3): credencial ausente => recusa ANTES de
qualquer criacao; `jira-map.tsv` nao e criado.

## Cenario 5 — Sync autonomo durante execucao 00c (US3, FR-004/005/018, SC-003)

1. Feature convertida; rodar `/feature-00c-resume` numa onda de execute-task.
2. Observar o board durante a onda.

**Expected**: task iniciada (`[~]`) aparece em `status_in_progress`; outcome
`pass` vai para `status_pass` e `fail` para `status_fail` ate o fim da mesma
onda (drain obrigatorio no fechamento); o orquestrador nunca espera pelo Jira.

**Correspondencia coluna<->estagio (US2, ux CHK008)**: a coluna do board em
que o card aparece e sempre a que o Jira ja associa ao `status_*`
configurado no Cenario 3 passo 3 — o cstk-jira nunca infere nem nomeia
coluna (`plugins/cstk-jira/skills/jira-setup/references/board-setup.md`
§4.bis); mover o card de coluna e so consequencia da transicao de status
feita por `jira-sync drain`.

**Error case 5a** (FR-011): mover um card manualmente no Jira e depois
registrar outcome da task => card NAO e sobrescrito; `jira-sync status` lista o
conflito.

**Error case 5b** (FR-016/FR-019): revogar o token no meio da execucao =>
evento `auth_failed`, nenhuma nova chamada ate `jira-setup`; a execucao da
feature segue normalmente.

**Error case 5c** (edge case de indisponibilidade): site inacessivel => eventos
`deferred`, drenados no gatilho seguinte; execucao nao para.

**Error case 5d** (FR-012): remover uma task do `tasks.md` => card permanece no
Jira; linha vira `orphan`; tentativa de `deleteJiraIssue` pela sessao e barrada
pela guarda (exit 2).

## Cenario 6 — Roundtrip End-to-End (conferencia de contrato)

1. Contra um site Jira Cloud de teste, rodar `jira-sync.sh plan` e depois
   `convert` de uma feature de 1 task.
2. Capturar a resposta REAL de criacao, de leitura da issue e da lista de
   transicoes.
3. Comparar metodo, path e nomes de campo contra `contracts/jira-rest.md`.

**Expected**: 100% dos campos usados pelo motor existem na resposta real com o
nome do contrato. Qualquer divergencia => corrigir o CONTRATO com a fonte
observada antes do codigo (Principio VI), nunca ajustar o codigo por
suposicao.

## Cenario 7 — Dependencias ausentes (carve-out 1.1.0, condicao a)

1. Rodar o hook de sync com PATH minimo sem `jq`/cliente HTTP.
2. Rodar `jira-convert` interativo com as tools do Rovo MCP visiveis.

**Expected**: passo 1 => exit 5 + diagnostico com instrucao de instalacao,
eventos preservados no outbox, execucao 00c inalterada; passo 2 => conversao
concluida pelo caminho MCP + scripts POSIX.

## Round r02 (2026-09-26) — cenarios do incremento FR-020..FR-025

Mesmo formato dos cenarios 1-7. Todos os automatizados rodam com o cliente
HTTP substituido por stub (nenhum teste toca rede); o cenario 12 e o unico
roundtrip real.

## Cenario 8 — Marco (Fix Version) por round e por release (FR-020, FR-021)

1. Feature SEM `.previous_round` e `CHANGELOG.md` com heading mais alto
   `## [X.Y.Z]` => `jira-sync.sh milestone resolve` imprime `name=X.Y.Z`,
   `kind=release`.
2. Mesma feature com `.previous_round.round=r01` e 1 diretorio
   `rounds/r01` => `name=<feature>-r02`, `kind=round`.
3. `convert` com stub de R13 vazio => 1 chamada R12 com `name`/`projectId`
   (numero) e depois Epic/Tasks com `fields.fixVersions=[{"id":...}]`.
4. Repetir `convert` 10 vezes (stub de R13 agora devolve a versao).

**Expected**: passo 3 => exatamente 1 R12 e `jira-milestones.tsv` com 1 linha
`current`; passo 4 => 0 chamadas R12 (FR-021, SC-002 estendido).

**Error case 8a** (heading mais alto `[Unreleased]`, sem
`milestone_release`): `name=`, `status=unresolved`; itens criados sem
`fixVersions`; `status`/`hook.log` mostram `milestone=unresolved`.

**Error case 8b** (R2-4): stub devolve `404` (e, em outra rodada, `403`) em
R12 => exit 7, `jira-milestones.tsv` `state=blocked`, NENHUM Epic/Task novo
criado, transicoes de issues ja mapeadas continuam, nenhuma nova tentativa de
R12 ate `write-config`.

**Error case 8c** (corrida FR-023): R12 devolve `400` e o R13 seguinte ja
traz o nome exato => reusa o `id`, 0 novas R12.

**Troca de marco (R2-2)**: Epic com `written_fix_version_id` do marco antigo
=> reconcile envia `update.fixVersions` com `remove` do id antigo e `add` do
novo; nenhuma versao nao-gravada-pelo-plugin aparece em `remove`; tasks antigas
nao recebem escrita.

## Cenario 9 — Label de FASE (FR-022)

1. `convert` de feature com tasks em `FASE 2` e `FASE 5`.
2. Mover no `tasks.md` uma task da FASE 2 para a FASE 5 e disparar
   `close_wave` (reconcile).

**Expected**: passo 1 => Task/Sub-task com `fields.labels=["phase-2"]`/
`["phase-5"]`, Epic sem label; passo 2 => 1 edicao com
`update.labels=[{"remove":"phase-2"},{"add":"phase-5"}]`, SyncMarker com
`written_phase_label=phase-5`; label humano pre-existente nunca aparece em
`remove`.

**Error case 9a**: `labels_enabled=off` => nenhum `labels` em corpo algum.
**Error case 9b**: FASE com numero fora de SEC-1 (impossivel no template, mas
fixture forjada) => item sem label + diagnostico, nunca corpo com valor nao
validado.

## Cenario 10 — Dependencias como links (FR-025)

1. Feature com Matriz `F1 --> F2`, `F1 --> F3`; stub de R16 com exatamente um
   tipo cujas frases contem `block` (e outros sem).
2. `jira-sync.sh links`.
3. Repetir `links`.

**Expected**: passo 2 => 2 chamadas R17, `type.id` = id do candidato (nunca
`type.name`), bloqueador (ancora de F1) em `outwardIssue`; `jira-links.tsv`
com 2 linhas `active`; passo 3 => 0 chamadas R17.

**Error case 10a**: R16 com 2 candidatos e sem `link_type_id` => 0 R17, 2
linhas `unrepresentable` `reason=ambiguous_link_type`, `status` mostra
`links_unrepresentable=2`.
**Error case 10b**: R16 `404` => todas `linking_disabled`, sem erro fatal.
**Error case 10c**: renumerar a ancora de F2 => linha antiga `stale`, link novo
criado; nenhuma requisicao `DELETE` no log do stub.

## Cenario 11 — Criacao de projeto sob gate humano (FR-024)

1. Interativo, sem projeto: `jira-setup` lista projetos (`searchProjects`),
   oferece criar; operador informa nome/key/template.
2. Rodar `create-project` SEM `--confirm-key`; depois com `--confirm-key`
   diferente da key; depois correto.
3. Autonomo (execucao 00c ativa no cwd): `create-project --confirm-key K`.
4. Autonomo com `--consent-block block-NNN` de bloqueio `pendente`; depois
   `respondido`.
5. Com plugin configurado e execucao ativa, chamar a tool
   `createJiraProject` pela sessao.

**Expected**: passo 2 => as duas primeiras recusadas (exit 2) sem nenhuma
requisicao; a terceira faz `getProject` (404) e R18 com `leadAccountId` vindo
de `/myself`; passo 3 => exit 2 sem requisicao (confirm-key nao vale em
contexto autonomo); passo 4 => pendente recusado sem requisicao, respondido
segue para R18; passo 5 => guarda `PreToolUse` exit 2.

**Error case 11a**: R18 `403` => exit 7 + texto "crie o projeto pela UI do
Jira ou peca a um admin" — nenhuma sugestao de trocar o token.
**Error case 11b**: `getProject` `200` para a key => "projeto ja existe,
reuse", 0 R18.

## Cenario 12 — Roundtrip real do round r02 (conferencia de contrato, BLOQUEANTE)

Contra o site de teste da whitelist (mesma credencial do r01, nunca
impressa), num projeto de teste JA existente (R18 fica FORA deste roundtrip:
criar projeto real exige gate humano proprio):

1. R13; R12 com nome de teste; R12 de novo com o MESMO nome (registrar o
   status real de duplicata). **Executado (onda-006, r02): `400` com corpo
   `{"errors":{"name":"A version with this name already exists in this
   project."}}`.**
   - 1.bis (CHK022, `{humano}`, **pendente**): repetir R12 com uma 2a
     credencial de teste SEM *Administer Projects*/*Administer Jira* para
     registrar o status real de permissao negada (`403` vs `404`
     documentado) — nao executado na onda-006 por falta de credencial
     restrita disponivel; bloqueio humano registrado no state da execucao.
2. R1 com `fields.fixVersions` e `fields.labels`; R3 com
   `?fields=labels,fixVersions,issuelinks` (registrar nome/shape real).
   **Executado (onda-006): `labels` = array de string; `fixVersions` =
   array do objeto `Version` completo.**
3. R2 com `update.fixVersions` add/remove e `update.labels` add/remove.
   **Executado (onda-006): `204`, efeito confirmado sem clobber nos dois
   campos.**
4. R16; R17 entre duas issues de teste; R3 `issuelinks` nas DUAS pontas
   (confirmar direcao inward/outward); R17 repetido (confirmar duplicata).
   **Executado (onda-006): tipos de link reais
   `Blocks`/`Cloners`/`Duplicate`/`Relates`; direcao do desenho
   (bloqueador=outward/bloqueado=inward) CONFIRMADA sem inversao; repeticao
   nao criou 2o link.**

**Expected**: cada item "a confirmar por roundtrip" de `contracts/jira-rest.md`
§"Continua fora do contrato apos o plan r02" e fechado com evidencia literal
ou CORRIGIDO no contrato antes do codigo (Principio VI). Nenhum `DELETE`;
issues/versoes de teste ficam para arquivamento manual (mesma nota 0.1.6 do
r01). Passos 1-4 fechados na onda-006 (ver `contracts/jira-rest.md`
"Roundtrip real onda-006"); passo 1.bis (CHK022) e R18/board (CHK026)
seguem pendentes de decisao humana.

## Cenario 13 — Execucoes paralelas do roadmap (FR-023)

1. Duas worktrees (`<repo>-<A>`, `<repo>-<B>`) de um projeto com
   ProjectConfig so na worktree principal.
2. Cada uma roda `feature-00c` e fecha uma onda.

**Expected**: cada worktree resolve o config da principal (somente leitura),
mantem `runtime/` proprio e sincroniza SO o proprio Epic; o marco de release
compartilhado e criado uma vez (a segunda execucao reusa via R13, ou via
releitura apos `400`).
