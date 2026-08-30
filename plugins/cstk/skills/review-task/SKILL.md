---
name: review-task
description: 'Task status / backlog progress report; identifies tasks ready to start. Triggers: "revisar tarefas", "status das tarefas", "progresso do projeto", "review tasks". Skip for executing (execute-task) or creating tasks (create-tasks).'
allowed-tools:
  - Read
  - Glob
  - Grep
  - Bash
  - Agent
---

# Skill: Revisar Status das Tarefas

Analise o arquivo de tarefas do projeto e gere um relatorio de status.

> **Contrato de saida (invariante)**: esta skill e READ-ONLY de relatorio —
> emite o status **na conversa (stdout)** e **nunca cria nem escreve arquivo
> de relatorio** (`.md`, `report.*`, etc.). So persista quando o usuario pedir
> explicitamente. Marcar tarefa como concluida (editar `tasks.md`) e trabalho
> do `/execute-task`, nao do review-task.

## Pre-requisitos

**Obrigatorio**: arquivo de tasks existente em alguma das localizacoes
suportadas (`docs/specs/*/tasks.md`, `docs/tasks.md`, `docs/tasks-*.md`,
`tasks.md`, `TODO.md`).

## Proximos passos

1. `/execute-task {id}` — iniciar a proxima tarefa recomendada pelo relatorio
2. Resolver dependencias apontadas como "bloqueadoras"
3. `/analyze` — se o relatorio revelar muitas tarefas sem evidencia de conclusao

---

## Instrucoes de Revisao

### 1. Deteccao de Contexto do Projeto

Identifique o tipo de projeto para contextualizar a analise:

| Tipo | Indicadores |
|------|-------------|
| **Documentacao** | `docs/` com `.md`, ausencia de `src/`, casos de uso (UC-*) |
| **Codigo** | `src/`, `app/`, `lib/`, `package.json`, `composer.json` |
| **Misto** | Contem tanto `docs/` quanto codigo-fonte |

### 2. Localizacao do Arquivo de Tarefas

Procure na seguinte ordem:
1. `docs/tasks.md`
2. `tasks.md`
3. `TODO.md`
4. `docs/TODO.md`
5. `.github/TODO.md`
6. Issues do repositorio (se aplicavel)

### 3. Analise das Tarefas

Para cada tarefa identificada, verifique:

#### Status Possiveis
- **Pendente**: Nao iniciada (`[ ]`)
- **Em Andamento**: Parcialmente concluida (`[~]`)
- **Concluida**: Finalizada (`[x]`)
- **Bloqueada**: Aguardando dependencia (`[!]`)

#### Checklist de Analise
- [ ] Identificar todas as tarefas e subtarefas
- [ ] Verificar status marcado vs status real
- [ ] Detectar inconsistencias (feito mas nao marcado)
- [ ] Identificar dependencias entre tarefas
- [ ] Calcular progresso por categoria/prioridade

### 4. Deteccao de Inconsistencias

**CRITICO**: Procure por tarefas que foram executadas mas nao marcadas:

#### Para Projetos de Documentacao:
```
SE tarefa pede "Criar UC-XXX-NNN"
E arquivo UC-XXX-NNN.md existe
E arquivo esta completo (nao tem TODOs)
ENTAO tarefa deve ser marcada como concluida
```

#### Para Projetos de Codigo:
```
SE tarefa pede "Implementar feature X"
E codigo da feature existe
E testes passam (se existirem)
ENTAO tarefa deve ser marcada como concluida
```

#### Extracao de Metricas

Preferir o script `scripts/metrics.sh` (mesmo diretorio desta skill) para
extrair contagens de forma deterministica:

```bash
bash skills/review-task/scripts/metrics.sh docs/tasks.md
# → tabela de metricas + linha JSON para consumo programatico
```

O script conta: fases, tarefas, subtarefas, concluidas/em andamento/pendentes/
bloqueadas, e criticidade por nivel [C]/[A]/[M].

#### Verificacao via Git (para projetos com historico):
```bash
# Ver commits recentes para identificar trabalho ja feito
git log --oneline -20

# Buscar commits relacionados a uma tarefa especifica
git log --oneline --grep="task-keyword"

# Verificar se o codigo compila/build passa (comando depende do stack)
# Exemplos: `go build ./...`, `npm run build`, `cargo build`, `mvn compile`
```

#### Para Monorepos Multi-Servico:
Use Agent para verificar tarefas em paralelo quando o arquivo de tarefas
cobre multiplos servicos — cada agente pode auditar um servico independentemente.

#### Atalhos de auditoria por stack

Para complementar a auditoria de tasks.md com auditoria de codigo no stack
detectado, invoque skills especializadas via tool Skill:

| Stack | Skill | Quando |
|-------|-------|--------|
| Go (servico individual) | `go-review-service` | Auditar UM microservico Go contra todas as convencoes do projeto (arquitetura, testes, factory, layout) — bom antes de marcar marco/release |
| Go (branch/PR) | `go-review-pr` | Auditar APENAS as mudancas do branch corrente vs `main`/`master` antes de abrir PR — diff-aware, nao re-audita o repo todo |

Essas skills produzem relatorios complementares ao review-task e ajudam
a flagar tarefas marcadas como concluidas que ainda tem violacoes de
convencao do projeto.

### 4.5 Agregacao de selecao de modelo (model-routing)

Quando a feature em revisao tem um `state.json` da execucao
`feature-00c` em `<projeto>/.claude/feature-00c-state/<feature>/`,
agregue as Decisoes de selecao de modelo emitidas pelo
`agente-00c-feature-orchestrator` (FR-018 da feature
`agente-00c-model-routing`) e inclua a secao canonica no relatorio.

**Como invocar** o helper read-only:

```bash
STATE_DIR="<projeto>/.claude/feature-00c-state/<feature>"
~/.claude/skills/agente-00c-runtime/scripts/model-routing-report.sh \
  aggregate --state-dir "$STATE_DIR"
```

O helper imprime em stdout ate DUAS secoes Markdown prontas para colar
verbatim no relatorio (NAO reformate):

1. **Selecao por subagente** (mecanismo legado da feature
   `agente-00c-model-routing` — Decisoes de selecao por spawn de
   clarify; o audit-only do FR-017 foi revogado em v4.0.0, o modelo
   agora e aplicado no spawn quando acionavel): cabecalho `## Selecao de
   modelo por subagente (model-routing)` + tabela GFM (`subagent_type |
   etapa | onda | modelo | score | fallback`) + `**Sumario**:` com
   contagens por rotulo + percentual de fallback.

2. **Selecao por onda — sugerido vs aplicado** (feature
   `model-routing-por-onda`, FASE 6 — FR-012/SC-006): cabecalho
   `## Selecao de modelo por onda (sugerido vs aplicado)` + tabela GFM
   (`onda | etapa | sugerido | aplicado | origem | divergente`) +
   `**Sumario por onda**:` com: total de ondas roteadas, distribuicao
   do modelo **aplicado** (haiku/sonnet/opus/manter-atual), distribuicao
   por **origem** (mapa/refino/override-operador/fallback), **taxa de
   fallback** (manter-atual), **taxa de override do operador**, e a
   contagem de **divergencias sugerido!=aplicado** com o detalhe
   `(rotuladas: <n>, sem rotulo: <n>)`. Esta segunda secao so e emitida
   pelo helper quando ha >=1 DecisaoDeRoteamentoPorOnda (`ondas.total >
   0`); caso contrario o output e identico ao legado.

**Leitura de auditoria** (o que o revisor MUST checar na secao 2):

- **`sem rotulo` DEVE ser 0** (SC-006): toda divergencia sugerido!=
  aplicado tem de ter `origem ∈ {override-operador, fallback}`. Se
  `divergencias_sem_rotulo > 0`, o relatorio MUST escalar como finding
  `model-routing-divergencia-sem-rotulo` em "Recomendacoes" — sinaliza
  Decisao por-onda corrompida ou bug no wave-select.
- **Taxa de aplicacao** = ondas com `origem ∈ {mapa, refino}` /
  `ondas.total`: quanto o roteamento PRIMARIO (mapa+refino) prevaleceu
  sem intervencao. Alta taxa de `override-operador` sugere mapa
  desalinhado com a realidade da feature (candidato a ajuste do
  `references/phase-model-map.txt`); alta taxa de `fallback` sugere
  model-selector indisponivel/instavel.

**Quando incluir a secao** (regra binaria):

- **Incluir** quando o helper retorna exit 0 e o stdout contem >=1
  linha de tabela (legado OU por-onda).
- **Omitir** quando exit 0 com ambos totais zerados (`Total: 0` e sem
  secao por-onda) — nao emita cabecalho sozinho; evita ruido em
  features pure-doc.
- **Skip auditavel** quando exit !=0: nao inclua a secao, mas adicione
  nota em "Recomendacoes" com formato definido em
  `docs/specs/agente-00c-model-routing/contracts/review-task-aggregate.md`
  §4.

**Posicionamento**: insira as secoes **apos** "Progresso por Fase" e
**antes** de "Recomendacoes" no template (vide §"Formato do Relatorio"
abaixo).

**Half-records pendentes (FR-013 — reuso do reconciliador)**: a
auditoria de meia-gravacao (Decisao de model-routing sem `record-skill`
correspondente, ou vice-versa) NAO ganhou mecanismo novo nesta feature —
reusa o `state-decisions-reconcile.sh` ja existente. Para auditar:

```bash
~/.claude/skills/agente-00c-runtime/scripts/state-decisions-reconcile.sh \
  check --state-dir "$STATE_DIR"
# exit 0 + stdout vazio -> 0 half-records pendentes (estado saudavel).
# exit 1 + TSV (dec-id, onda-id, subagent-type) -> half-records a sanar.
```

O numero de half-records pendentes DEVE ser **0**. O subcomando real e
`check` (DETECT-ONLY — o script apenas audita; NAO existe subcomando
`repair`/`detect`). Se `check` lista entradas, reporte finding
`model-routing-half-record` em "Recomendacoes" e sinalize a meia-gravacao
para resolucao manual na retomada (`/feature-00c-resume`): inspecionar o
`state.json` e completar o `record-skill` faltante ou remover a Decisao
orfa correspondente. Read-only e idempotente — seguro de rodar dentro do
review-task.

**Path canonico do relatorio**: salvar em
`docs/specs/<feature>/review-<onda-id>.md` (onde `<onda-id>` e a string
opaca da onda corrente — convencao atual do toolkit e `onda-NNN`
zero-padded, extraida de `.ondas[-1].onda_id` do state). Path canonico
ratificado em
`docs/specs/agente-00c-model-routing/contracts/review-task-aggregate.md`
§1.

**Defesa em profundidade**: se o helper esta ausente (ex: skill
`agente-00c-runtime` nao instalada), pule a agregacao silenciosamente
— nao bloqueie o restante do review-task.

#### Cruzamento com consumo de tokens observado (wave-usage-report)

Ref: feature `wave-token-metrics`, FASE 6 (F5, US2/FR-007).

Quando a mesma `state.json` tambem tem `.waves[].agent_usage` (populado
pelo hook `posttooluse-agent-usage.sh` + `state-ondas.sh end` — ver
`docs/specs/wave-token-metrics/`), cruze a secao **por-onda** do
model-routing (`linhas_onda[]`, saida `--json` de
`model-routing-report.sh`) com o agregado do `wave-usage-report.sh`
(`por_onda[]`, saida `--json`) pela chave comum `onda`. Objetivo: por
onda, mostrar o **modelo aplicado** (model-routing) lado a lado com o
**consumo observado** (tokens/tool-uses/duracao — wave-usage),
destacando divergencias sugerido≠aplicado que tiveram alto consumo.

**Nao existe um unico script que ja produza esse cruzamento verbatim** —
e deliberado: `model-routing-report.sh` publica o invariante "le SOMENTE
`.decisions[]`, nunca `.waves`" (ver cabecalho do script); adicionar um
campo agregado de `.waves` ali quebraria esse contrato. O review-task
computa o join a partir dos DOIS `--json`, sem alterar nenhum dos dois
helpers:

```bash
STATE_DIR="<projeto>/.claude/feature-00c-state/<feature>"   # ou agente-00c-state
MR_JSON=$(~/.claude/skills/agente-00c-runtime/scripts/model-routing-report.sh \
  aggregate --state-dir "$STATE_DIR" --json 2>/dev/null) \
  || MR_JSON='{"ondas":{"total":0},"linhas_onda":[]}'
WU_JSON=$(~/.claude/skills/agente-00c-runtime/scripts/wave-usage-report.sh \
  aggregate --state-dir "$STATE_DIR" --json 2>/dev/null) \
  || WU_JSON='{"metric_collected":false,"por_onda":[]}'

jq -n --argjson mr "$MR_JSON" --argjson wu "$WU_JSON" '
  ($wu.por_onda // [] | map({(.onda): .}) | add // {}) as $wu_by_onda
  | ($mr.linhas_onda // []) as $rows
  # media de tokens (so valores nao-null) entre as ondas roteadas nesta
  # execucao — "alto consumo" e RELATIVO a esta execucao, nunca um
  # limiar fixo inventado (Principio VI: so agrega dado real observado).
  | ($rows | map($wu_by_onda[.onda].total_tokens) | map(select(. != null))) as $vals
  | (if ($vals | length) > 0 then ($vals | add / length) else null end) as $media
  | $rows
  | map(. as $r
      | ($wu_by_onda[$r.onda]) as $u
      | $r + {
          tokens:      (($u.total_tokens)     // null),
          tool_uses:   (($u.tool_use_count)    // null),
          duration_ms: (($u.duration_ms)       // null),
          alto_consumo: ($r.divergente
            and (($u.total_tokens) != null)
            and $media != null
            and (($u.total_tokens) > $media))
        })
'
```

**Renderizacao** (tabela `#### Consumo x roteamento por onda`, colunas
GFM): `onda | etapa | sugerido | aplicado | origem | tokens | tool-uses
| duracao | divergente+alto-consumo`. Marque a ultima coluna com `⚠`
quando `alto_consumo=true` — sinaliza exatamente o caso mais caro para o
operador auditar: a escalada/override divergiu do roteamento primario
**e** custou mais tokens que a media das ondas roteadas nesta execucao.

**Diferenca de §4.5 acima**: as duas tabelas de §4.5 (legado + por-onda)
sao copiadas **verbatim** do stdout de `model-routing-report.sh` — nunca
reformatadas (ver Gotcha "Agregado model-routing nao deve ser
reformatado"). Esta subsecao e **derivada** (join calculado pelo
review-task sobre dois `--json` independentes); nao ha saida canonica
unica para colar verbatim, entao a tabela acima e a UNICA
representacao — mantenha as colunas e o rotulo `⚠` estaveis para nao
quebrar comparacoes entre relatorios sucessivos.

**Quando incluir** (regra binaria, mesmo espirito de §4.5):

- **Incluir** quando AMBOS os `--json` tem dado (`mr.ondas.total > 0` E
  `wu.metric_collected == true`) E o join produz >=1 linha com
  `tokens != null`.
- **Omitir** silenciosamente quando qualquer uma dessas condicoes falha
  por AUSENCIA de dado (nao houve roteamento por-onda nesta execucao,
  ou a metrica de consumo nunca foi coletada) — nao emita cabecalho
  sozinho.
- **Skip auditavel** quando QUALQUER um dos dois helpers falha com
  `exit != 0` (script ausente, `state.json` ilegivel etc.): nao inclua a
  subsecao, mas adicione nota em "Recomendacoes" (mesmo formato de §4.5
  §4 do contrato `review-task-aggregate.md`).

**Defesa em profundidade**: identica a §4.5 — qualquer um dos dois
helpers ausente/falhando nunca bloqueia o restante do review-task.

### 4.6 Reconciliacao + completude de tasks (.tasks[] ↔ tasks.md)

Quando a feature tem `state.json` da execucao em
`<projeto>/.claude/feature-00c-state/<feature>/`, garanta que TODA task
concluida no `tasks.md` tenha entrada em `.tasks[]` (e, por consequencia,
na `knowledge.db`). Sem este gate, tasks concluidas pelo `execute-task`
mas cujo append de outcome o orquestrador pulou somem silenciosamente —
o `.tasks[]` e a fonte que a ingestao (`recall.sh`) espelha; ele NAO le o
`tasks.md`. Historicamente uma feature com 21 tasks gravou so 2.

**Por que aqui**: `tasks.md` (checkboxes mantidos pelo `execute-task`
ETAPA 9) e deterministico; `.tasks[]` (append em prosa do orquestrador) e
fragil. O `review-task` e o ponto natural de fim de fase para harvestar o
primeiro no segundo.

**1. Detectar divergencia (read-only)** — quais tasks concluidas
(`### N.M` com TODAS as subtarefas-checkbox `[x]`) faltam em `.tasks[]`:

```bash
STATE_DIR="<projeto>/.claude/feature-00c-state/<feature>"
TASKS_MD="<path resolvido na secao 2>"   # docs/specs/<feature>/tasks.md etc.
~/.claude/skills/agente-00c-runtime/scripts/state-ondas.sh \
  reconcile-tasks --state-dir "$STATE_DIR" --tasks-md "$TASKS_MD" --dry-run
# stdout vazio  -> 0 divergencias (estado saudavel)
# stdout = task_ids (1 por linha) -> tasks concluidas ausentes de .tasks[]
```

**2. Sanar (back-fill deterministico)** — idempotente; NUNCA sobrescreve
entrada real ja gravada pelo `execute-task` (usa `--if-absent`); so grava
tasks CONCLUIDAS (pendentes/bloqueadas ficam de fora — sem outcome final):

```bash
~/.claude/skills/agente-00c-runtime/scripts/state-ondas.sh \
  reconcile-tasks --state-dir "$STATE_DIR" --tasks-md "$TASKS_MD"
# stdout: nº de tasks back-filled nesta passada
```

**3. Reportar no relatorio** (secao "Recomendacoes" / "Resumo Executivo"):

- **Divergencia**: nº de tasks concluidas no `tasks.md` que NAO estavam em
  `.tasks[]` antes do back-fill (saida do passo 1). Se `> 0`, reporte
  finding `task-outcome-nao-gravado` — sinaliza que o orquestrador pulou o
  `record-task` durante o `execute-task`. O back-fill ja sanou para a
  ingestao, mas a recorrencia indica fluxo de onda interrompido cedo.
- **Completude pos-reconcile**: `count(.tasks[])` (entradas reais +
  back-filled) vs total de tasks concluidas no `tasks.md`. Devem bater.
- **Origem das entradas**: quantas `origem == "reconcile"` (back-filled)
  vs `origem == "execute-task"` (gravadas ao vivo). Alta proporcao de
  `reconcile` confirma que o caminho ao vivo esta falhando.

**Defesa em profundidade**: helper ausente (skill `agente-00c-runtime`
nao instalada) ou `tasks.md`/`state.json` nao resolvidos → pule o passo
silenciosamente, sem bloquear o resto do review-task. Read-only no passo
1, idempotente no passo 2 — seguro rodar a cada review.

### 4.7 Auditoria do tier de entrega (delivery-tier — FR-008)

> Origem: feature `delivery-tier`, Fase D item 13. Aplica-se SOMENTE a
> execucoes `/agente-00c` (`<projeto>/.claude/agente-00c-state/`) — o
> tier de entrega e restrito a esse orquestrador (dec-011); execucoes
> `feature-00c` NAO tem este campo, pule silenciosamente.

Quando `state.json`/`state.db` da execucao `/agente-00c` estiver
disponivel:

1. **Tier vigente**: leia exclusivamente via `delivery-tier.sh get
   --state-dir <SD>` (INV-5) — nunca `state-rw.sh get --field
   '.delivery_tier'` direto. Reporte na secao "Progresso por Fase" (ou
   "Resumo Executivo") como "Tier de entrega: `<token>`".
2. **Gates pulados/leves**: liste as Decisoes com
   `context` iniciando em `"Gate owasp-security resolvido pela matriz
   tier x gate"` (registradas pelo orquestrador em `5.f` de
   `agente-00c-orchestrator.md`) e cite `escolha` (`rodar-gate` /
   `rodar-leve` / `skip-com-justificativa`) + `justification` (tier +
   modo resolvido) para cada uma. Ausencia de Decisao para um gate
   `leve`/`skip` observado no comportamento da onda e o proprio finding
   abaixo.
3. **Finding `delivery-tier-unattended-change` (INV-4/F5, HIGH
   ASI01/ASI03)**: compare o `delivery_tier` vigente lido no passo 1
   contra o valor no INICIO da execucao (primeira onda que gravou o
   campo, via `state-history`/backups de onda). Se o valor mudou,
   verifique se ha consentimento correspondente do operador — satisfeito
   por QUALQUER UM dos dois (emenda dec-048/dec-053, `cli-delivery-tier.md`
   §2.2 regra 3): (a) Decisao correspondente (`state-decisions.sh` com
   `context` citando mudanca de tier, registrada em `/agente-00c-resume`);
   ou (b) entrada em `.optin_responses[]` com `channel: "structured"` e
   `outcome: "accepted"` para o campo de tier (coleta mediada de inicio de
   execucao, `mcp-elicitation-optins` FASE 5). SEM NENHUMA das duas
   evidencias — inclusive um `set` disparado pelo orquestrador por conta
   propria — reporte este finding com severidade `critical`: tier
   alterado por fora do fluxo auditado e o padrao classico de
   auto-escalada de agente (privilege abuse / goal hijack) que o INV-4
   existe para barrar. A emenda reconhece uma segunda fonte legitima de
   evidencia; NAO afrouxa a deteccao quando nenhuma das duas existe.

**Defesa em profundidade**: mesma da secao 4.6 — helper ausente ou
state-dir nao resolvido → pule silenciosamente, sem bloquear o resto do
review-task.

### 4.8 Decisoes estruturais e anomalias de governanca (structural-decision-human-gate — FR-012, SC-002)

> Origem: feature `structural-decision-human-gate`, FASE 7. Aplica-se a
> QUALQUER execucao (`agente-00c` ou `feature-00c`) cujo `state.json`/
> `state.db` contenha Decisoes com `decision_class`.

**Nao reimplemente a heuristica de anomalia aqui.** O predicado normativo
ja existe em `agente-00c-runtime/scripts/report.sh`, funcao
`_rp_render_secao_estrutural` (task 7.1.2): `decision_class == "estrutural"`
E `choice` fora da familia de token de bloqueio humano (`pause-humano` ou
prefixo `bloqueio-humano`) E sem `human_consent_block_id` referenciando um
`human_block` com `status == "respondido"` e
`subject_key == "axis:" || structural_axis`. `agent`/`agente` e so
proveniencia informativa, nunca entra no predicado.

Para reusar esse mesmo calculo sem duplicar a query jq:

1. Rode `report.sh generate --state-dir <SD>` (mesmo `<SD>` resolvido no
   passo 1 desta skill — `agente-00c-state/` ou
   `feature-00c-state/<short>/`). O relatorio gerado ja inclui a secao
   `## Decisoes Estruturais e Anomalias de Governanca` (renderizada por
   `_rp_render_secao_estrutural`, chamada tanto em `generate` quanto em
   `emit`, para os dois flavors).
2. Extraia dessa secao as duas contagens: "Total de decisoes estruturais:
   N" e o "Total: M (esperado 0 em execucao saudavel — SC-002)" da
   subsecao "Anomalias de Governanca".
3. Reporte as duas contagens no relatorio agregado do review-task (bloco
   "Decisoes Estruturais e Anomalias de Governanca" no formato abaixo).
   Zero decisoes estruturais e uma execucao normal (nao e finding); M > 0
   anomalias E finding — liste os ids das Decisoes anomalas (presentes na
   propria secao gerada) em "Recomendacoes" com severidade alta, pois
   representa decisao estrutural aplicada sem consentimento humano
   auditavel (violacao do gate desta feature).

**Defesa em profundidade**: `report.sh` ausente/nao-executavel ou
state-dir sem `decisions[].decision_class` (execucao anterior a esta
feature, ou execucoes 100% operacionais) → secao aparece com contagem "0"
(nunca omitida por `report.sh`) ou, se o proprio `report.sh` falhar, pule
esta subsecao do review-task silenciosamente sem bloquear o restante do
relatorio.

### 4.9 Convergencia pendente — soft gate (pipeline-converge — FR-004)

> Origem: feature `pipeline-converge`, FASE 5 (tarefa 5.2). Aplica-se a
> QUALQUER feature SDD (`docs/specs/<feature>/tasks.md`) que tenha
> `spec.md` E `tasks.md` — os dois pre-requisitos da skill `converge`.
> Feature sem `tasks.md` (nunca passou por `create-tasks`) esta fora do
> escopo (FR-005) — pule esta subsecao silenciosamente.

**1. Consultar o veredito** — sempre no INICIO do relatorio, antes de
priorizar tarefas pendentes (§6):

```bash
FD="$(dirname "$TASKS_MD")"   # docs/specs/<feature> — o mesmo resolvido na secao 2
~/.claude/skills/converge/scripts/converge-status.sh check --feature-dir "$FD"
# exit 0 stdout converged|risk-accepted   -> sem pendencia, siga normalmente
# exit 1 stdout "pending actionable=N"    -> pendencia acionavel
# exit 1 stdout stale                     -> aceite/limpeza anterior caducou (backlog mudou desde entao)
# exit 3 stdout never                     -> convergencia nunca rodou para esta feature
# exit 0 stdout not-applicable            -> tasks.md ausente/vazio (FR-005), pule esta subsecao
```

**2. Finding `converge-pending` — soft gate, NUNCA bloqueia (FR-004)**:
vereditos `pending`, `stale` **e** `never` (os tres agrupados como
"nao-conforme" pelo proprio `converge-status.sh audit` — contrato
`converge-status-cli.md` §audit) viram o finding `converge-pending` no
relatorio quando `tasks.md` **nao esta vazio**. O relatorio **e produzido
normalmente** e a revisao de tarefas completa sem abortar — soft gate
significa avisar, nunca travar (Cenario 6 de `quickstart.md`). `never` MUST
entrar no mesmo finding que `pending`/`stale`: e o caso mais comum na
pratica — a primeira vez que o backlog de uma feature termina, a
convergencia tipicamente ainda nao rodou nenhuma vez.

**3. Instruir o caminho correto de aceite de risco** (nunca execute
nenhum dos dois voce mesmo — esta skill e READ-ONLY, §Contrato de saida):

- **Execucao autonoma** (`state.json`/`state.db` de `feature-00c`/
  `agente-00c` presente): instrua o orquestrador a (a) registrar
  `state-decisions.sh register` descrevendo a decisao de aceitar o risco,
  e (b) so ENTAO `converge-status.sh accept-risk --feature-dir "$FD"
  --decisao-id <dec-NNN>` — nessa ordem, nunca o inverso.
- **Execucao manual** (sem `state.json` ativo): instrua o operador humano
  a rodar diretamente `converge-status.sh accept-risk --feature-dir "$FD"
  --justificativa "<motivo>"` (sem `--decisao-id`, nao ha Decisao
  auditavel a referenciar fora de execucao autonoma).
- Em ambos os casos, apos o aceite, uma nova chamada a `check` (passo 1)
  deve retornar `risk-accepted` — reexecute o `review-task` para confirmar
  que o finding `converge-pending` some do relatorio (Cenario 7).

**Gotcha F8 (herdado de `converge/SKILL.md`)**: o `review-task` — e
qualquer orquestrador que o invoque — **nunca** chama `accept-risk` por
conta propria, mesmo em modo autonomo. Um agente se auto-liberando do
soft gate que a propria feature existe para criar esvaziaria o gate
(ASI02/LLM06). O `review-task` so **reporta** e **instrui**; o aceite em
si e sempre um ato do operador (via Decisao auditavel + confirmacao
humana em execucao autonoma, ou diretamente pelo humano em execucao
manual).

**Defesa em profundidade**: `converge-status.sh` ausente (skill
`converge` nao instalada) ou `$FD` nao resolvido → pule esta subsecao
silenciosamente, sem bloquear o restante do `review-task` — mesmo padrao
das secoes 4.6/4.7/4.8.

### 4.10 Auditoria da janela efetiva de `ask_operator` (human-bridge — R-AUDIT-1)

> Origem: feature `human-bridge`, FASE 2 (task 2.5). Aplica-se a QUALQUER
> execucao (`agente-00c` ou `feature-00c`) cujo `state.json`/`state.db`
> contenha `.operator_answers[]` (a tool MCP `ask_operator` — humano
> respondendo pelo painel `cstk-panel`). Execucao que nunca chamou
> `ask_operator` nao tem este array — subsecao AUSENTE do relatorio nesse
> caso (nao e finding, e nao-aplicavel).

**Nao reimplemente o predicado aqui.** Ja existe em
`agente-00c-runtime/scripts/report.sh`, funcao
`_rp_render_secao_ask_operator`: para cada entrada de `.operator_answers[]`,
`outcome == "timeout"` **E** `effective_timeout_ms < 60000`
(`ASK_MIN_TIMEOUT_MS`, contrato `mcp-tool-ask-operator.md` R-CLOCK-7). A
CONJUNCAO das duas condicoes — nunca cada uma isoladamente: `timeout` com
janela adequada e desfecho legitimo (o operador nao estava); janela curta
com `answered` e trilha verdadeira (o humano respondeu mesmo assim).

1. Rode `report.sh generate --state-dir <SD>` (mesmo `<SD>` do passo 1
   desta skill). Quando `.operator_answers[]` existe e nao esta vazia, o
   relatorio inclui a secao `## Auditoria ask_operator — Janela Efetiva
   (human-bridge, R-AUDIT-1)`.
2. Extraia dessa secao: "Total de respostas ask_operator nesta execucao:
   N." e o "Total: M (esperado 0 ...)" da subsecao "Finding
   ask-operator-short-window".
3. Reporte as duas contagens no relatorio agregado do review-task. `M ==
   0` e uma execucao saudavel (nao e finding); `M > 0` **e** finding —
   liste os `question_id` das entradas anomalas (ja presentes na propria
   secao gerada) em "Recomendacoes" com severidade `warning` (padrao dos
   findings de governanca da skill, data-model.md §"Auditoria da janela
   efetiva").

**Defesa em profundidade**: `report.sh` ausente/nao-executavel, ou
state-dir sem `.operator_answers[]` (execucao anterior a esta feature, ou
que nunca usou `ask_operator` — a imensa maioria) → subsecao AUSENTE do
relatorio (nunca renderizada com contagem zero forcada) e pulada
silenciosamente aqui, sem bloquear o restante do `review-task` — mesmo
padrao de degradacao das secoes 4.6/4.7/4.8/4.9.

### 5. Acoes Automaticas

Ao identificar inconsistencias:

1. **Liste as evidencias** de que a tarefa foi concluida
2. **Atualize o arquivo de tarefas** marcando como [x]
3. **Documente no relatorio** as tarefas finalizadas nesta sessao

### 6. Priorizacao de Proximas Tarefas

Ordene tarefas pendentes por:
1. **Prioridade** (C > A > M)
2. **Dependencias** (sem bloqueios primeiro)
3. **Impacto** (maior valor de negocio)

---

## Formato do Relatorio

```markdown
# Relatorio de Status das Tarefas

**Data:** [YYYY-MM-DD]
**Projeto:** [nome do projeto]
**Tipo:** [Documentacao/Codigo/Misto]
**Arquivo de Tarefas:** [caminho]

---

## Resumo Executivo

| Metrica | Valor |
|---------|-------|
| Total de Tarefas | X |
| Concluidas | X (X%) |
| Finalizadas Nesta Sessao | X |
| Em Progresso | X (X%) |
| Pendentes | X (X%) |
| Bloqueadas | X (X%) |

---

## Tarefas Finalizadas Nesta Sessao

> Tarefas identificadas como completas e marcadas automaticamente

### [TASK-ID]: [Nome]
- **Evidencias:**
  - Arquivo criado: `path/to/file`
  - Conteudo completo
- **Acao:** Status atualizado

---

## Tarefas Pendentes - Prontas para Iniciar

### Top 3 Recomendadas

#### 1. [TASK-ID]: [Nome]
- **Prioridade:** [C|A|M]
- **Dependencias:** Nenhuma
- **Justificativa:** [por que comecar agora]
- **Comando:** `/execute-task [TASK-ID]`

---

## Tarefas Bloqueadas

### [TASK-ID]: [Nome]
- **Bloqueada por:** [TASK-ID da dependencia]
- **Para desbloquear:** Concluir [descricao]

---

## Progresso por Fase

| Fase | Total | Concluidas | % |
|------|-------|------------|---|
| 1 - Fundacao | X | X | X% |

---

<!-- INSERIR AQUI quando aplicavel — vide §4.5 (Agregacao de selecao de modelo) -->
## Selecao de modelo por subagente (model-routing)

| subagent_type | etapa | onda | modelo | score | fallback |
|---------------|-------|------|--------|-------|----------|
| ...           | ...   | ...  | ...    | ...   | ...      |

**Sumario**:
- Total: N
- haiku: n
- sonnet: n
- opus: n
- manter-atual: n
- fallback-default: n (pct%)

<!-- INSERIR AQUI quando aplicavel — vide §4.5 (Cruzamento com consumo de tokens observado) -->
## Consumo x roteamento por onda (wave-usage x model-routing)

| onda | etapa | sugerido | aplicado | origem | tokens | tool-uses | duracao | divergente+alto-consumo |
|------|-------|----------|----------|--------|--------|-----------|---------|--------------------------|
| ...  | ...   | ...      | ...      | ...    | ...    | ...       | ...     | ...                      |

---

<!-- INSERIR AQUI quando aplicavel — vide §4.8 (Decisoes estruturais e anomalias de governanca) -->
## Decisoes Estruturais e Anomalias de Governanca

Total de decisoes estruturais: N
Total de anomalias: M (esperado 0 — SC-002)

<!-- se M > 0, listar ids + eixo + escolha, mesmos dados da secao
     gerada por report.sh; tratar como finding de severidade alta -->

---

<!-- INSERIR AQUI quando aplicavel — vide §4.9 (Convergencia pendente) -->
## Convergencia

Veredito (`converge-status.sh check`): `<converged|risk-accepted|pending actionable=N|stale|never|not-applicable>`

<!-- se pending/stale/never (com tasks.md nao-vazio): finding
     `converge-pending` — soft gate, NUNCA bloqueia o relatorio. Instruir
     o caminho de aceite (Decisao auditavel + accept-risk --decisao-id em
     execucao autonoma; accept-risk --justificativa direto em execucao
     manual) — ver §4.9. -->

---

<!-- INSERIR AQUI quando aplicavel (so quando .operator_answers[] existe
     e nao esta vazia) — vide §4.10 (Auditoria da janela efetiva de
     ask_operator) -->
## Auditoria ask_operator (human-bridge — R-AUDIT-1)

Total de respostas ask_operator: N
Finding ask-operator-short-window: M (esperado 0 — piso ASK_MIN_TIMEOUT_MS=60000ms)

<!-- se M > 0, listar question_id + outcome + effective_timeout_ms +
     applied_value + recorded_at, mesmos dados da secao gerada por
     report.sh; severidade warning (nao bloqueia) — ver §4.10 -->

---

## Recomendacoes

### Acoes Imediatas
1. **[Acao]** - `/execute-task [ID]`
2. **[Acao]** - `/execute-task [ID]`
```

---

## Checklist de Revisao

Antes de finalizar o relatorio:

- [ ] Li completamente o arquivo de tarefas
- [ ] Identifiquei TODAS as tarefas e status
- [ ] Verifiquei evidencias de trabalho concluido
- [ ] Marquei tarefas finalizadas mas nao registradas
- [ ] Analisei dependencias entre tarefas
- [ ] Priorizei tarefas pendentes
- [ ] Forneci top 3 recomendacoes acionaveis
- [ ] Consultei o veredito de convergencia (`converge-status.sh check`,
      §4.9) quando a feature tem `spec.md` + `tasks.md`
- [ ] Relatorio esta claro e objetivo

---

**EXECUTE AGORA A REVISAO**

1. Detecte o contexto do projeto
2. Localize o arquivo de tarefas
3. Analise todas as tarefas
4. Identifique e corrija inconsistencias
5. Gere relatorio completo
6. Sugira proximos passos

---

## Gotchas

### Detectar inconsistencias e a razao de ser da skill

Tarefa feita mas nao marcada `[x]` e o erro mais frequente do fluxo. Se a skill so relata status sem cruzar com evidencias (arquivo existe, commit recente, build passa), nao agrega valor — vira `grep "[ ]"`.

### Procurar tasks em multiplas localizacoes, nao um path unico

Verificar nesta ordem: `docs/specs/*/tasks.md` (SDD), `docs/tasks.md`, `docs/tasks-*.md` (por servico/modulo), `tasks.md` raiz, `TODO.md`. Assumir apenas um path deixa fora projetos com SDD ou multi-servico.

### Marcar tarefas como [x] requer evidencia explicita no relatorio

Nunca marque silenciosamente. Cada auto-completion deve aparecer na secao "Tarefas Finalizadas Nesta Sessao" com bullet de evidencias (arquivo criado, commit X, build passa). Auditoria depende disso.

### Recomendacoes (top 3) devem respeitar criticidade e dependencias

A ordem e: `[C]` antes de `[A]` antes de `[M]`, e dentro do mesmo nivel, tarefas sem bloqueios primeiro. Recomendar uma `[M]` quando existem `[C]` pendentes desbloqueadas e erro de priorizacao.

### Monorepos multi-servico: paralelizar com Agent

Quando tasks.md cobre 5+ modulos/servicos, auditar sequencialmente multiplica o tempo. Lance agentes paralelos — cada um audita um servico, depois consolide.

### Nao confundir com execute-task

Esta skill LE e RELATA; nao executa trabalho pendente. Se o usuario pergunta "status" e recomenda uma tarefa, nao emenda `/execute-task` no mesmo turno — pergunte se quer prosseguir.

### Agregado model-routing nao deve ser reformatado

O `model-routing-report.sh aggregate` retorna Markdown ja canonicalizado (cabecalho, colunas, sumario com chaves fixas). Reformatar (mudar header, reordenar colunas, esconder rotulos com zero) quebra o INV-RT-1 do contrato `docs/specs/agente-00c-model-routing/contracts/review-task-aggregate.md` e invalida testes de integracao. Copie verbatim ou nao inclua.

Excecao deliberada: a subsecao "Cruzamento com consumo de tokens observado" de §4.5 NAO copia verbatim — e um join calculado pelo review-task sobre dois `--json` independentes (`model-routing-report.sh` + `wave-usage-report.sh`), porque nenhum dos dois scripts pode emitir esse cruzamento sem violar seu proprio invariante publicado (`model-routing-report.sh` nunca le `.waves`). Nesse caso especifico, siga o formato de tabela documentado em §4.5 em vez de "copiar verbatim".