# Project Briefing: Agente-00C

**Data**: 2026-05-05
**Status**: Draft
**Versao**: 1.0

> **Nota de escopo**: este briefing descreve um *experimento meta* dentro do
> toolkit `claude-ai-tips` — uma feature chamada agente-00C, nao um projeto
> independente. Por isso varias secoes do template padrao foram adaptadas
> para o contexto de "ferramenta de orquestracao autonoma" em vez de "produto
> com usuarios finais".

---

## 1. Visao e Proposito

**O que e**: agente-00C (codinome herdado de "00 Claude", piada com 007) e um
orquestrador autonomo invocado via slash command `/agente-00c` que executa a
pipeline completa de Spec-Driven Development do toolkit
(`briefing → constitution → specify → clarify → plan → checklist → create-tasks
→ execute-task → review-task → review-features`) sem intervencao humana entre
etapas, gerando como entregavel principal um relatorio auditavel rico em
decisoes, bloqueios e licoes aprendidas.

**Problema que resolve**: o autor (joao) escreveu um conjunto de skills SDD e
quer descobrir, na pratica, (i) se a pipeline sobrevive a um agente "burro"
executando sem revisao humana — sinal de robustez; (ii) ate onde o Claude Code
suporta orquestracao autonoma como plataforma; (iii) quais melhorias as
proprias skills precisam para tomar decisoes melhores no futuro. Tambem serve
como **produtor de POC/MVP** para validar ideias e testar possibilidades no
estilo de projeto que o autor faz no dia-a-dia.

**Proposta de valor**: ao final de cada execucao, um artefato estruturado
(relatorio + sugestoes de melhoria + issues abertas no toolkit quando bug
impeditivo) alimenta a evolucao das skills do proprio toolkit. O sucesso do
experimento e medido pela qualidade desse aprendizado de volta, nao pela
quantidade de projetos entregues.

## 2. Usuarios e Stakeholders

| Ator | Papel | Acoes Principais |
|------|-------|------------------|
| joao (autor) | Operador unico | Invoca `/agente-00c` com stack sugerida + descricao curta de POC/MVP; consome relatorio final; resolve bloqueios humanos quando 00C pausa |
| Subagentes especialistas | Executores delegados pelo orquestrador | Cada um carrega skill especifica da pipeline (clarify-asker, clarify-answerer, executores de task, revisores) |
| Skills do toolkit | Capacidades invocadas | Sao consumidas pela pipeline e podem ser sugeridas para evolucao baseada nos achados |

**Stakeholders de decisao**: joao decide tudo. Sem terceiros.

## 3. Escopo

### MVP (Essencial)

1. **Slash command `/agente-00c`** que aceita parametros iniciais incluindo
   stack arquitetural sugerida (linguagem, framework, banco, cache, filas) e
   descricao curta do projeto-alvo.
2. **Agente orquestrador custom** em `.claude/agents/` com tools amplas
   (Agent, Skill, Bash, Read, Write, Edit, etc) que executa a pipeline SDD
   linear, mediando subagentes filhos.
3. **Padrao clarify de dois atores** mediado pelo orquestrador: um
   `clarify-asker` carrega a skill clarify e gera perguntas + opcoes
   recomendadas; um `clarify-answerer` recebe isso + contexto + briefing +
   stack-sugerida + constitution e decide cada uma com justificativa.
4. **Persistencia de estado em disco** (`.claude/agente-00c-state/`) com a
   etapa atual, decisoes tomadas, artefatos produzidos e proxima instrucao —
   permitindo retomada apos `clear` de contexto.
5. **Estrategia schedule/clear/continue** para autonomia cross-turno: ao
   final de cada onda, agenda proxima execucao (~5min), limpa contexto, e
   retoma a partir do estado serializado.
6. **Auto-orcamento de sessao**: parar e agendar proxima sessao ao atingir
   80% do consumo de sessao; idem para 80% da janela semanal; sem hard cap
   absoluto fora disso.
7. **Gatilhos de aborto explicitos**: impossibilidade tecnica, desvio de
   finalidade, 5+ ciclos travados na mesma etapa, movimento circular
   (fix-bug-fix-mesmo-bug), bug impeditivo confirmado em skill global.
8. **Retro-execucao orcada**: maximo 2 retro-execucoes por feature, cada uma
   registrada no estado.
9. **Relatorio final auditavel** salvo em `<projeto-alvo>/.claude/agente-00c-report.md`
   contendo resumo executivo, linha do tempo, decisoes tomadas, bloqueios
   humanos, sugestoes para skills globais, metricas (tokens, ondas, tempo,
   profundidade max de subagentes) e licoes aprendidas.
10. **Entregavel paralelo**: quando 00C identificar bug impeditivo em skill
    global, abre issue no GitHub do toolkit (`JotJunior/claude-ai-tips`) com
    diagnostico, e PARA pedindo decisao humana.
11. **Acesso a skills**: orquestrador e subagentes enxergam skills globais
    (`~/.claude/skills/`) e skills locais do projeto-alvo (`.claude/skills/`).

### Pos-MVP (Desejavel)

1. Dashboard agregador que compara relatorios de multiplas execucoes do 00C
   para identificar padroes de falha recorrentes nas skills.
2. Heuristica de auto-aprendizado: o `clarify-answerer` consulta relatorios
   anteriores antes de decidir, evitando repetir escolhas que falharam.
3. Suporte a tipos de projeto-alvo alem de microservicos Go + React + docker
   (ex: CLIs, libs, jobs batch).

### Fora de Escopo

- **Push para remotos** de qualquer tipo (codigo, container, deploy).
- **Deploy externo** (cloud, kubernetes em cluster remoto, serverless).
- **Sudo no host**, instalacao global de pacotes (`brew install`, `npm i -g`).
- **Edicao de skills globais** (`~/.claude/skills/`) — sugestoes vao para
  arquivo dedicado e/ou issue no toolkit.
- **Acesso a credenciais reais fora do `.env` do projeto-alvo** — o que esta
  no `.env` e usavel; o resto e proibido.
- **Comunicacao externa fora da whitelist** definida no inicio da execucao
  + URLs do `.env`, com excecao explicita do `gh` para abrir issues no
  proprio toolkit.
- **Multiusuario** — 00C e ferramenta pessoal de joao, sem onboarding,
  permissoes ou colaboracao.

## 4. Prioridades e Trade-offs

**Ordem de prioridade**:
**Qualidade do relatorio final > Documentacao de bloqueios humanos > Avanco da
pipeline > Entrega de projeto rodando**

**Decisoes explicitas**:

- **Cenario A vence Cenario B** (decisao do autor): execucao com 0 projetos
  entregues mas relatorio rico que explica cada bloqueio e propoe melhorias
  concretas e MAIS valiosa que execucao com 1 projeto rodando porem com
  relatorio raso. Quando 00C tiver que escolher entre "avancar sem entender
  bem" e "pausar para registrar fundo", a regra e pausar.
- **Bloqueios humanos sao aceitaveis e esperados** desde que documentados.
  Nao sao falha — sao dado para evolucao das skills.
- **Auto-evolucao restrita ao escopo local**: 00C pode editar skills de
  `.claude/` do projeto-alvo durante a execucao se isso ajudar; nunca toca
  em skills globais.
- **Ar-gapped por padrao, whitelist explicita**: comunicacao externa exige
  URL declarada no `.env` ou whitelist apresentada no inicio do projeto.

## 5. Restricoes

| Restricao | Valor | Notas |
|-----------|-------|-------|
| Prazo | Flexivel | Experimento pessoal, sem deadline externo |
| Equipe | 1 (joao) | Mais subagentes do Claude Code |
| Budget | Auto-regulado | Para em 80% sessao; agenda proxima. Para em 80% janela semanal; agenda proxima janela. Sem hard cap absoluto fora disso. |
| Plataforma | Claude Code | Skills, subagents, slash commands, schedule/cron, hooks |
| Operacional | Tudo local | Commits locais sempre; nunca push; nunca deploy externo; docker local apenas |
| Escrita em disco | Restrita ao projeto-alvo | Subdiretorios sim; `~/` fora; `~/.claude/` jamais |
| Skills globais | Read-only | Sugestoes em arquivo dedicado + issue no toolkit |
| `.env` (read-only) vs `.env.claude` (write) | Separacao explicita | 00C pode escrever no `.env.claude`; le mas nunca escreve no `.env` original |
| Sudo | Vetado no host | Inferido — combinacao "restrito ao projeto + nunca no host" implica sem sudo |
| `gh` | Local + excecao para issues no toolkit | Sem push; sem PR externo; pode abrir issues em `JotJunior/claude-ai-tips` |
| Package managers | Permitidos so dentro do docker | `npm`, `go mod`, `pip` etc — nunca executados no host |
| Recursividade de subagentes | Maximo 3 niveis | Filho, neto, bisneto. Acima disso falha explicita ou volta ao orquestrador raiz. |
| Retro-execucao | Maximo 2 por feature | Registradas no estado |
| Loop em etapa | Maximo 5 ciclos | Acima disso aborta como tendencia a loop |

## 6. Stack Tecnica

| Camada | Tecnologia | Justificativa |
|--------|-----------|---------------|
| Plataforma do orquestrador | Claude Code (Opus 4.x) | Skills, subagents (Agent tool), slash commands, ScheduleWakeup/CronCreate, hooks — primitivos necessarios para o desenho |
| Forma do 00C | Slash command + agente custom | Slash command e ponto de entrada manual; agente custom em `.claude/agents/` carrega tools amplas e orquestra subagentes |
| Persistencia de estado | JSON em disco | `.claude/agente-00c-state/` no projeto-alvo; estrutura definida no `/plan` |
| Continuacao cross-turno | ScheduleWakeup ou CronCreate | A escolher no `/plan` baseado em durabilidade vs simplicidade |
| Comunicacao subagentes | Mediada pelo pai | Padrao oficial: pai spawna A, recebe retorno, spawna B com contexto |
| Stack do projeto-alvo | Parametrizada na invocacao | Linguagem, framework, banco, cache, filas — sugeridos pelo autor, questionaveis pelo `clarify-answerer` |
| Stack tipica esperada | Microservicos Go + React + docker-compose | Estilo dia-a-dia do autor (ver CLAUDE.md raiz) |
| Versionamento | git local | Commit por etapa concluida; nunca push |

## 7. Qualidade e Padroes

**Padroes adotados**:

- **Auditabilidade total**: toda decisao do orquestrador ou de subagente
  registrada com (contexto, opcoes consideradas, escolha, justificativa,
  agente que decidiu).
- **Idempotencia de retomada**: apos clear de contexto, a proxima onda deve
  reconstruir tudo o que precisa do estado em disco — nada essencial pode
  viver so na memoria de contexto.
- **Pausar antes de chutar**: quando o `clarify-answerer` nao tiver confianca
  suficiente, ou quando 00C detectar incoerencia entre artefatos que nao
  caiba em 2 retro-execucoes, parar e registrar bloqueio humano e
  preferivel a decidir mal.
- **Whitelist explicita de comunicacao externa**: 00C nunca acessa URL fora
  da whitelist + `.env` declarados.
- **Skills globais sao tesouro** — never modify.

**Compliance**: nenhum especifico (uso pessoal, dados sinteticos, sem PII).

## 8. Visao de Futuro

**Apos 1 execucao bem sucedida**: existencia de pelo menos 1 relatorio rico
com 3+ licoes aprendidas concretas que viram melhorias commitadas em
skills do toolkit. Esse e o "valeu a pena, continuo mexendo".

**Apos 3-5 execucoes**: padroes recorrentes de falha identificados. Skills
da pipeline SDD evoluidas para tomar decisoes melhores. Eventualmente
heuristica de auto-consulta a relatorios passados (Pos-MVP).

**Sinal de abandono**: 00C nao consegue passar do `briefing → constitution
→ specify` em nenhuma execucao porque toda decisao vira bloqueio humano —
indicio de que a pipeline pressupoe contexto que skills nao conseguem
extrair sem entrevista humana de verdade.

**Riscos conhecidos**:

- **Custo descontrolado**: mitigado pelos gatilhos de 80% sessao/semana,
  mas tokens podem subir rapido com subagentes recursivos. Monitorar nas
  primeiras execucoes.
- **Loop sutil**: o gatilho de 5+ ciclos cobre loops obvios; movimento
  circular fix-bug-fix-mesmo-bug exige logica de deteccao mais fina.
- **Decisoes silenciosamente erradas**: o `clarify-answerer` decidir mal
  e a pipeline seguir sem perceber. Mitigado por retro-execucao + analyze,
  mas ainda e o risco mais perigoso.
- **Skill global com bug**: cobre via abertura de issue no toolkit + bloqueio.
- **Drift de estado em disco**: estado JSON nao pode corromper. Sera schema
  versionado com validacao a cada onda.

---

## Itens a Definir

| Item | Dimensao | Impacto |
|------|----------|---------|
| Schema exato do `.claude/agente-00c-state/index.json` (campos obrigatorios, versionamento) | Persistencia | Alto — define a interface de retomada |
| Mecanismo de continuacao cross-turno: ScheduleWakeup vs CronCreate vs `/loop` | Tecnico | Alto — cada um tem trade-off de durabilidade |
| Como o 00C "ouve" o gatilho de 80% de sessao (qual API/heuristica) | Operacional | Alto — sem isso o auto-orcamento nao funciona |
| Logica de deteccao de movimento circular (fix-bug-fix-mesmo-bug) | Confiabilidade | Medio — comeca heuristica simples, evolui |
| Formato exato da whitelist de URLs externas (sintaxe, onde declarar) | Seguranca | Medio — provavel arquivo `agente-00c.whitelist` no projeto-alvo |
| Como o `clarify-answerer` mede "confianca suficiente" para decidir vs pausar | Qualidade | Medio — defaults na constitution, refinaveis |
| Estrutura interna do relatorio final (esqueleto exato, secoes obrigatorias) | Entregavel | Baixo — esqueleto ja proposto, refinaveis no plan |
| Comportamento quando bisneto tenta spawnar tataraneto (erro? volta a raiz?) | Recursividade | Baixo — defaults na constitution |

---

**Proximo passo recomendado**: `/constitution` para cravar principios
imutaveis do 00C (autonomia, decisao, pause-or-decide, blast radius, audit)
antes de partir para `/specify`.
