# Descoberta de tipos de issue e status/transicoes (R8 + R5)

Detalhe tecnico de como a skill `jira-setup` chama `jira-io.sh` para
descobrir tipos de issue e o workflow de status do projeto. Carregado sob
demanda pela ETAPA 4 do `SKILL.md` — nao precisa ser memorizado antes disso.

## 1. Tipos de issue (R8 — `contracts/jira-rest.md`)

```sh
jira-io.sh request GET "/rest/api/3/issue/createmeta/<PROJECT_KEY>/issuetypes" --op R8 \
  | jira-io.sh json-get '.issueTypes[] | "\(.id)\t\(.name)\t\(.hierarchyLevel)\t\(.subtask)"'
```

`<PROJECT_KEY>` MUST passar por `jira-io.sh validate-segment` antes de
interpolar o path. A resposta traz `issueTypes` OU `createMetaIssueType`
(schema nao determina qual vem preenchida — use a que vier nao-vazia,
`contracts/jira-rest.md` R8).

Campos confirmados por roundtrip real (onda-011, projeto `SCRUM` em
`cstk.atlassian.net`): `id`, `name`, `hierarchyLevel` (inteiro), `subtask`
(booleano). Nesse projeto: `Epic`=`hierarchyLevel 1`, `Story`/`Task`=`0`,
`Subtask`=`-1`, `subtask=true` so em `Subtask`. **Isto e evidencia de UM
site apenas** — projetos com esquema de hierarquia customizado (planos
Enterprise/Premium) podem variar. Por isso a skill NUNCA infere Epic/Task/
Sub-task por `hierarchyLevel`: sempre lista os 4 campos e pede confirmacao
explicita do operador (tasks.md 6.1.3, api CHK006).

## 2. Status/transicoes do workflow (R5 — `contracts/jira-rest.md`)

`GET /rest/api/3/issue/{issueIdOrKey}/transitions` (R5) e o UNICO endpoint
de transicoes no contrato — e por-ISSUE, nao por-projeto. O contrato
(`jira-rest.md`) **nao lista** nenhum endpoint de "status do projeto"
independente de uma issue existente (secao "Continua fora do contrato apos
a onda-005"); inventar um path aqui violaria o Principio VI (Veracidade de
Dados).

**Decisao de design desta tarefa (6.1.4)**: quando o projeto ainda nao tem
NENHUMA issue (setup pela primeira vez, antes de qualquer `jira-convert`),
a skill cria UMA issue de sondagem ("probe") so para poder chamar R5:

1. Apos R8 (passo 1 acima), escolher o PRIMEIRO tipo retornado com
   `subtask=false` (nao precisa ser o tipo que o operador vai confirmar
   como Epic/Task depois — e so uma sondagem tecnica, descartavel).
2. Criar a issue: `jira-io.sh json-build issue --project-id <ID>
   --issuetype-id <ID-do-tipo-escolhido> --summary "cstk-jira setup probe
   (pode ser arquivada)"` e `jira-io.sh request POST /rest/api/3/issue
   --body-file <arquivo> --op R1`.
3. Chamar R5 na issue criada: `jira-io.sh request GET
   "/rest/api/3/issue/<KEY>/transitions" --op R5 | jira-io.sh json-get
   '.transitions[].to.name'` — lista de status descobertos.
4. Se o projeto JA tiver ao menos uma issue (ex.: reconfiguracao/re-setup),
   pedir ao operador a KEY de uma issue existente em vez de criar uma nova
   (evita lixo desnecessario).

**Custo aceito**: a issue de sondagem fica no projeto (FR-012 proibe
`DELETE` pelo motor — o mesmo trade-off ja documentado para as issues de
teste `SCRUM-5`/`SCRUM-6` do roundtrip onda-011). Informar ao operador, ao
final do setup, que pode arquiva-la manualmente pela UI do Jira se quiser
(nao e obrigatorio — nao expoe credencial nem dado sensivel).

## 3. Validando o mapeamento de status

Com a lista de status descoberta (passo 2.3), delegar a validacao
deterministica a `jira-setup.sh` (nunca reimplementar a regra na skill):

```sh
jira-setup.sh check-status-mapping "$PENDING" "$IN_PROGRESS" "$PASS" "$FAIL" $STATUS_LIST
```

Exit 1 + diagnostico em stderr (listando os status descobertos) se
`FAIL == PASS` ou se qualquer valor mapeado nao estiver na lista descoberta
(data-model.md ProjectConfig "Validation rules"; ux CHK004). Apresentar o
diagnostico ao operador tal como veio (ja lista os status disponiveis —
nao reformatar em "invalido" generico).

## 4. Caminho MCP equivalente (Rovo)

Se as tools `mcp__*__listJiraProjectIssueTypesMetadata` (ou
`getJiraIssueTypeMetaWithFields`) e `mcp__*__listJiraIssueTransitions`
estiverem visiveis na sessao (`contracts/rovo-mcp.md`), preferir o caminho
MCP: mesma logica (listar tipos -> confirmar -> sondar transicoes de uma
issue -> mapear status), mas os NOMES de parametro vem do `inputSchema`
real exibido pela tool — nunca de memoria (`contracts/rovo-mcp.md`
"Parametros de entrada das tools"). `cloudId` e sempre argumento de topo
(nunca dentro de `inputs`), obtido via `getAccessibleAtlassianResources`
OU a propria URL do site como `cloudId` (README oficial, citado no
contrato).

## 5. Gravacao final (write-config)

Somente apos: credencial validada remotamente + tipos confirmados pelo
operador + mapeamento de status validado (secao 3) + filtro/board
criados/reusados — gravar TUDO de uma vez:

```sh
jira-setup.sh write-config \
  config_version=1 site_host="$SITE_HOST" project_key="$PROJECT_KEY" \
  board_id="$BOARD_ID" \
  issue_type_epic="$EPIC_ID" issue_type_task="$TASK_ID" issue_type_subtask="$SUBTASK_ID" \
  status_pending="$PENDING" status_in_progress="$IN_PROGRESS" \
  status_pass="$PASS" status_fail="$FAIL" \
  sync_autonomous=on
```

`write-config` delega a validacao final a `jira-config.sh validate` e so
grava o arquivo (atomico) se ela passar — nenhum campo faltante ou
`status_fail == status_pass` chega a virar arquivo "final" (tasks.md
6.1.5, ux CHK006).
