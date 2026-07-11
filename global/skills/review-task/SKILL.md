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