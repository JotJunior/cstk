# ADR-001: Fan-out nativo (Workflow) na pipeline SDD

> **Status:** Aceito (rejeição da tese ampla); adoção em sweeps read-only é **direção aprovada, a specar**.
> **Data:** 2026-05-28
> **Deciders:** jot (operador) · análise crítica via skill `advisor` (2026-05-28)
> **Contexto-gatilho:** lançamento do Claude Opus 4.8 (2026-05-28), que trouxe
> *dynamic workflows* ao Claude Code (planejar tarefa grande + centenas de
> subagentes paralelos + auto-verificação).

## Contexto

O 4.8 expôs uma primitiva nativa de orquestração paralela (a tool `Workflow`).
Surgiu a tese de **paralelizar a fase `execute-task`** dos orquestradores
`agente-00c`/`feature-00c` via fan-out nativo, em vez de manter a execução
**sequencial onda-a-onda**. A motivação inicial foi atacar o "gargalo" de
backlogs grandes.

A tese foi submetida a uma análise crítica (advisor) em 2026-05-28. Os
argumentos abaixo são auto-contidos — não dependem do diálogo que os gerou.

> **Nota de honestidade:** a janela de 1M de contexto **não** é novidade do
> 4.8 (o 4.7 já a tinha; há execução real registrada em
> `validation-runs/2026-05-11-execucao-real-sc-coverage.md` sobre "Opus 4.7
> (1M context)"). Portanto 1M **não** entra como justificativa desta decisão.

## Decisão

1. **Rejeitar** o fan-out nativo **dentro da pipeline transacional SDD** — a
   fase `execute-task` e qualquer fase que escreva no `state.json`
   permanecem **sequenciais, uma onda por vez**.

2. **Confinar** o uso de `Workflow` a **jobs one-off, read-mostly, sem estado
   transacional**, **fora** da pipeline. Candidatos: `analyze` cross-spec,
   `owasp-security` no repo inteiro, `validate-docs-rendered` em todos os docs,
   `review-features` (portfólio). Esta ADR aprova a **direção**; cada uso
   concreto ainda exige seu próprio spec/decisão.

## Justificativa

Três argumentos **bastam sozinhos** para rejeitar a tese ampla,
independentemente de qualquer medição:

- **A — Bloqueio arquitetural.** Os orquestradores rodam *como subagente*
  (spawnados pelos comandos `/agente-00c` e `/feature-00c`). Pela mesma razão
  pela qual o orquestrador-subagente não invoca a tool `Agent` (degradação de
  clarify para mediação inline já documentada), ele **presumivelmente não
  invoca `Workflow`**. Fan-out nativo só existiria no **comando top-level** —
  o que é *outra* feature, não "paralelizar a fase `execute-task`".

- **B — Invariante transacional, não dívida legada.** O cstk se apoia em um
  **`state.json` único + lock** (fronteira lock+init unificada em 6 arquivos
  00C) e existe `cstk session` com worktrees isoladas **justamente porque**
  trabalho paralelo na mesma working tree / branch / state colide. O design
  sequencial é **escolha deliberada** por estado transacional e auditável —
  não um workaround de modelo antigo a ser removido.

- **C — Eixo errado para o workload dominante.** O caso de uso central é
  execução **não-assistida** (overnight, com `ScheduleWakeup` entre ondas).
  Nesse regime **wall-clock é quase grátis** — ninguém espera. Fan-out gasta
  tokens de N subagentes + passo de verify + reconciliação de N worktrees para
  comprar latência que o workload **não valoriza**.

Dois argumentos adicionais só importam para uma eventual *ressurreição* da
tese (ver Critério de reversão):

- **D — Independência das tarefas nunca medida.** `create-tasks` gera backlog
  *"com fases e dependências"*. Paralelismo só rende em tarefas
  **independentes**; num backlog em cadeia, o ganho é zero (serializado pelo
  caminho crítico).

- **E — "execute-task para cedo" é bug de completude, não de throughput.** O
  modo de falha documentado (orquestrador retorna sem fechar a onda) é
  controle/completude. Paralelismo **não conserta** — **multiplica** (N
  agentes podendo parar cedo + reconciliação mais difícil).

## Critério de reversão (gate pré-registrado)

A rejeição da tese ampla só se reabre se um **spike** comprovar **AMBOS**:

- **(a)** um subagente consegue, de fato, invocar `Workflow` (refuta **A**); **e**
- **(b)** **≥ ~40%** das tarefas `execute-task` em backlogs reais são
  *independentes de dependência* **E** *sem escrita no `state.json`
  compartilhado* (refuta **D**).

Pré-registrar o gate torna uma futura reabertura uma decisão **por dado**, não
por opinião ou por atração da ferramenta nova.

## Consequências

**Positivas**

- Preserva o núcleo de valor do cstk — auditabilidade, resume, trilha de
  decisões, `knowledge.db`, lock transacional — intacto.
- Direciona a capacidade nova do 4.8 (dynamic workflows) para onde ela
  realmente paga aluguel: sweeps read-only fora da pipeline.
- Evita aposta de alta variância na parte mais crítica e mais bem-endurecida
  do sistema.

**Negativas / custo aceito**

- `execute-task` permanece sequencial: o wall-clock de backlogs grandes **não**
  melhora. Aceito — o workload dominante é não-assistido.
- Deixa na mesa um ganho potencial **caso** a arquitetura mude (mitigado pelo
  gate de reversão).

**Neutras**

- Os sweeps read-only via `Workflow` ainda exigem spec próprio; esta ADR
  aprova apenas a direção.

## Premissas não verificadas

Registradas explicitamente para não inflar a confiança da decisão:

- **A** (subagente não invoca `Workflow`) é **inferida** do comportamento
  análogo com a tool `Agent`, **não confirmada empiricamente** — é o item
  (a) do gate.
- Os dois números do gate (% de tarefas paralelizáveis-sem-estado; e a
  confirmação sobre `Workflow`) **não foram medidos** nesta ADR.

## Fontes

- Opus 4.8 — *What's new* (Claude API Docs):
  <https://platform.claude.com/docs/en/about-claude/models/whats-new-claude-4-8>
- *Dynamic workflow tool* (TechCrunch, 2026-05-28):
  <https://techcrunch.com/2026/05/28/anthropic-releases-opus-4-8-with-new-dynamic-workflow-tool/>
- Cross-refs internos: `CLAUDE.md` (§ fronteira lock+init, § model-routing),
  spec do `cstk session` (rationale de isolamento por worktree).
