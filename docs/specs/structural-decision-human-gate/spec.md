# Feature Specification: Decisoes estruturais exigem gate humano (structural-decision-human-gate)

**Feature**: `structural-decision-human-gate`
**Created**: 2026-08-19
**Status**: Draft
**Origem**: issue #146 (caso real em execucao `/agente-00c` modo roadmap → `/feature-00c`)

## Contexto

Em 2026-08-19 um operador relatou (#146) que o `agente-00c-feature-orchestrator`
resolveu **sozinho** a escolha de linguagem/runtime de um projeto: na onda-005
(etapa `plan`) registrou a Decisao `dec-020` escolhendo reusar um motor Python,
com score 3 e evidencia empirica real, tendo `bloqueio-humano` **entre as proprias
opcoes consideradas** e com o item marcado no briefing como `[NEEDS CLARIFICATION]`
de impacto **Alto** na tabela "Itens a Definir". Consequencias observadas:

- stack hibrida adotada sem decisao de ninguem (motor numa linguagem, resto do
  projeto numa stack de frontend distinta);
- `plan.md` sem declarar **onde** o entregavel roda; artefato de dependencias
  pinado para a maquina do operador (macOS arm64 / Python 3.14) quando o ambiente
  de producao era Windows — entregavel nao-instalavel no alvo real;
- 7h depois, um "gate humano de dependencias" (aprovar 3 bibliotecas Python) foi
  tratado como consentimento de stack: o operador aprovou bibliotecas, nao a
  linguagem — a decisao chegou a ele ja consumada;
- retrabalho de roadmap, briefing e constitution apos o veto do operador.

Nao foi alucinacao nem falta de evidencia: **o orquestrador seguiu a regua que
existe**. A analise do codigo confirmou quatro lacunas, todas de governanca:

1. A unica regra do runtime que forca `score 0` e a dos 3 tokens canonicos de
   constitution-conflict (`state-decisions.sh register`, espelhada no MCP
   `record_decision`). Ter `bloqueio-humano` em `options_considered` **nao
   significa nada** para o runtime — e so mais uma string.
2. A skill `plan` (Phase 0) e desenhada para resolver `NEEDS CLARIFICATION` por
   inferencia/pesquisa ("devem morrer no Phase 0"). Em uso interativo o humano
   esta na sessao; em modo autonomo isso vira decisao de stack sem humano.
3. A coluna **Impacto (Alto/Medio/Baixo)** da tabela "Itens a Definir" do template
   de briefing **nao e consumida por nenhuma skill ou agente a jusante** — e
   decorativa.
4. O campo **Target Platform** do template de `plan` aceita `NEEDS CLARIFICATION`
   e nenhum gate exige que seja resolvido com fonte antes de fixar runtime.

Esta feature fecha as quatro no mesmo espirito do INV-4 do `delivery-tier`
(auto-escalada de escopo proibida ao agente): **decisoes de classe estrutural
nao sao elegiveis a resolucao autonoma**.

### Definicao: classe estrutural

Decisao **estrutural** e a que fixa, para o projeto-alvo ou para a feature, um
destes eixos (lista fechada nesta versao):

| Eixo | Exemplos |
|------|----------|
| Linguagem / runtime | Python vs Node vs Go; versao minima de runtime |
| Stack / frameworks principais | reuso de codigo legado vs reescrita; framework web/UI |
| Arquitetura de alto nivel | monolito vs hibrido vs servicos; processo unico vs pipeline |
| Persistencia principal | SQLite vs banco relacional externo vs arquivos; banco novo vs existente |
| Ambiente de execucao alvo | SO/plataforma onde o entregavel roda (Windows/Linux/macOS, cloud, on-prem, mobile) |
| Tier de entrega | ja coberto por `delivery-tier` (INV-4); citado para completude |

Decisao **operacional** e qualquer outra (nome de modulo, ordem de tarefas, detalhe
de implementacao, escolha entre bibliotecas DENTRO de uma stack ja decidida por
humano, etc.). A regua de score atual permanece integral para elas.

## User Scenarios & Testing

### User Story 1 - Operador nunca descobre uma stack "ja decidida" (Priority: P1)

Como operador de uma execucao autonoma (`/agente-00c` ou `/feature-00c`), quando
o orquestrador chega a uma decisao de classe estrutural, eu sou **sempre**
consultado antes — a execucao pausa com um bloqueio humano que apresenta as
opcoes e a recomendacao do agente, e so continua depois da minha resposta. O
runtime impede que o orquestrador "decida e registre" uma decisao estrutural
como se fosse operacional.

**Why this priority**: e o defeito central da #146 — a decisao mais cara do
projeto (stack) foi tomada sem o dono; tudo o mais (ambiente alvo, gate de
dependencias) decorre dela.

**Independent Test**: num projeto-alvo de teste, o orquestrador tenta registrar
uma Decisao declarada estrutural com escolha diferente do bloqueio humano; o
registro e recusado, um bloqueio humano e registrado, a onda termina em
`bloqueio_humano`, e o `plan.md` NAO e escrito ate a resposta.

**Acceptance Scenarios**:

1. **Given** uma execucao autonoma na etapa `plan` e uma decisao que fixa a
   linguagem/runtime, **When** o orquestrador tenta registra-la com qualquer
   escolha que nao seja o bloqueio humano (independentemente de score ou
   evidencia), **Then** o registro e recusado com mensagem que cita a classe
   estrutural e o caminho correto (bloqueio humano), e nada e gravado.
2. **Given** a mesma situacao, **When** o orquestrador registra a decisao como
   estrutural com escolha = bloqueio humano e score 0 e abre o bloqueio,
   **Then** a onda encerra em `bloqueio_humano` e o sumario de retorno informa
   ao operador o eixo estrutural pendente, as opcoes e a recomendacao do
   agente (com evidencia, se houver).
3. **Given** um bloqueio estrutural respondido pelo operador via resume,
   **When** a proxima onda roda, **Then** a decisao do operador e a fonte da
   stack (Decisao com agente humano rastreavel) e o orquestrador **nao** volta a
   perguntar o mesmo eixo nesta execucao.
4. **Given** uma decisao operacional (ex.: nome de um modulo, ordem de duas
   tasks), **When** o orquestrador a registra com score >= 2 sem bloqueio,
   **Then** nada muda em relacao ao comportamento atual (sem classe exigida,
   sem pausa).
5. **Given** uma decisao cujas opcoes incluem um token da familia de bloqueio
   humano, **When** o orquestrador omite a declaracao de classe, **Then** o
   registro e recusado por uso incorreto (a classe e obrigatoria nesse caso) —
   tanto pelo helper de linha de comando quanto pela tool MCP equivalente.

---

### User Story 2 - Item "a definir" de impacto Alto do briefing vira bloqueio, nao pesquisa (Priority: P2)

Como operador, os itens que o proprio briefing marcou como **Itens a Definir**
com impacto **Alto** sao decididos por mim: quando a pipeline autonoma chega a
`specify` ou `plan` com um desses itens ainda sem decisao humana, ela pausa e me
pergunta, em vez de resolver por inferencia no Phase 0 do `plan`.

**Why this priority**: a tabela de impacto ja existe e o operador ja confia nela;
hoje ela nao tem efeito. Fecha a causa 3 e a porta de entrada da causa 2.

**Independent Test**: briefing de teste com um item Alto ("linguagem do motor de
extracao") e nenhum item Medio/Baixo bloqueante; `/feature-00c` pausa antes de
produzir `plan.md`, citando o item; apos resposta, prossegue e o `plan.md`
reflete a resposta.

**Acceptance Scenarios**:

1. **Given** `docs/briefing.md` com tabela "Itens a Definir" contendo >= 1 item
   de impacto Alto sem Decisao humana correspondente na execucao, **When** o
   orquestrador inicia a etapa `plan` (ou `specify`, quando o item afeta o
   escopo), **Then** registra um bloqueio humano por item Alto pendente
   (pergunta = o item; contexto = a dimensao e por que e estrutural) e encerra a
   onda sem invocar a skill `plan`.
2. **Given** o mesmo briefing, **When** todos os itens Alto ja tem Decisao humana
   rastreavel na execucao (bloqueio respondido ou Decisao registrada por
   operador), **Then** a etapa segue normalmente, sem nova pergunta.
3. **Given** briefing sem a tabela, ou com tabela vazia, ou so itens
   Medio/Baixo, **When** a etapa inicia, **Then** comportamento identico ao
   atual (zero pergunta nova) — a regra e estritamente aditiva.
4. **Given** a skill `plan` invocada em modo autonomo com um `NEEDS
   CLARIFICATION` de classe estrutural ainda aberto no Technical Context,
   **When** o Phase 0 roda, **Then** ela NAO o resolve por inferencia — o
   deixa explicito para o orquestrador transformar em bloqueio (o gate da US3
   barra o artefato se isso falhar).
5. **Given** a skill `plan` invocada interativamente (sem execucao autonoma
   ativa), **When** o Phase 0 roda, **Then** comportamento atual preservado (o
   humano esta na sessao).

---

### User Story 3 - Ambiente de execucao alvo declarado com fonte antes de fixar runtime (Priority: P3)

Como operador, nenhum `plan.md` passa o gate de qualidade com o **ambiente de
execucao alvo** ausente ou marcado como pendente: o plano precisa dizer onde o
entregavel roda e de onde veio essa informacao (briefing, constitution, resposta
minha), antes de qualquer artefato de dependencias ser gerado.

**Why this priority**: e o que teria barrado o `requirements.txt` pinado para a
plataforma errada; depende da US1/US2 para a informacao existir, mas e um gate
independente e deterministico.

**Independent Test**: `plan.md` com `Target Platform: NEEDS CLARIFICATION` (ou
campo ausente) reprovado pelo validador de plano com finding critico; o mesmo
plano com o campo preenchido e fonte citada aprovado.

**Acceptance Scenarios**:

1. **Given** um `plan.md` cujo Technical Context nao declara Target Platform ou o
   declara como pendente, **When** o gate de qualidade pos-plan roda, **Then**
   emite finding **critico** nomeado (ambiente alvo nao resolvido) e, em modo
   autonomo, isso vira bloqueio humano pela tabela de gates ja existente.
2. **Given** Target Platform preenchido mas sem fonte rastreavel (nenhuma
   referencia a briefing/constitution/Decisao humana), **When** o gate roda,
   **Then** emite finding de aviso (nao critico) pedindo a fonte — nunca fabrica
   uma.
3. **Given** Target Platform preenchido com fonte, **When** o gate roda,
   **Then** nenhum finding novo; saida identica a atual nos demais checks.

---

### User Story 4 - Aprovar uma dependencia nao e aprovar a stack (Priority: P4)

Como operador, um gate humano de dependencias so me e apresentado **depois** de a
stack ter sido decidida por mim (quando a execucao tem uma decisao estrutural de
stack pendente ou registrada); e o relatorio de auditoria destaca as decisoes
estruturais e quem as tomou, para que eu veja de relance se alguma foi fechada
sem consentimento.

**Why this priority**: fecha o agravante da #146 (proxy de consentimento) e da
visibilidade pos-fato; menor risco se ficar para depois, por isso P4.

**Independent Test**: backlog gerado para uma feature com decisao de stack
pendente coloca a task de gate de dependencias DEPOIS da resolucao da stack;
`review-task`/relatorio listam as decisoes estruturais com o agente decisor.

**Acceptance Scenarios**:

1. **Given** `create-tasks` rodando com uma decisao estrutural de stack
   registrada (humana) ou pendente, **When** o backlog inclui um gate humano de
   dependencias, **Then** esse gate depende da task/decisao de stack (nunca
   antes dela).
2. **Given** uma execucao com >= 1 Decisao de classe estrutural, **When** o
   relatorio final e gerado, **Then** a secao de decisoes identifica cada uma
   como estrutural e mostra o agente decisor; uma estrutural com escolha
   diferente do bloqueio humano e sem agente humano e marcada como **anomalia
   de governanca** (nunca deveria existir — so por estado legado ou bypass).
3. **Given** `review-task`, **When** agrega a execucao, **Then** reporta a
   contagem de decisoes estruturais e a contagem de anomalias (esperado 0).

---

### Edge Cases

- **Orquestrador omite o token de bloqueio para escapar da regra**: a classe
  estrutural pode (e deve, pela prosa) ser declarada mesmo sem token de
  bloqueio nas opcoes; quando declarada, forca a pausa. A deteccao de uma
  decisao estrutural registrada como operacional e parcialmente dependente da
  honestidade do agente — por isso US2 (itens Alto) e US3 (ambiente alvo) sao
  deterministicas e independentes, e US4 marca anomalias a posteriori.
- **Item Alto do briefing ambiguo** (texto nao casa claramente com um eixo
  estrutural): ainda assim e bloqueio — o criterio e o impacto declarado pelo
  briefing, nao a classificacao do agente.
- **Briefing legado** (`docs/01-briefing-discovery/briefing.md`) ou tabela com
  cabecalho ligeiramente diferente: parser tolerante a whitespace/maiusculas
  nas 3 colunas; tabela irreconhecivel = "sem itens" (comportamento atual),
  com aviso no sumario — nunca falha a onda por parse.
- **Execucao ja em andamento quando a feature e instalada**: nao retroativa;
  decisoes estruturais ja registradas sem consentimento aparecem como anomalia
  no relatorio (US4), nao sao reabertas automaticamente.
- **Modo MCP**: a tool `record_decision` aplica a mesma regra (classe
  obrigatoria quando ha token de bloqueio; estrutural => score 0 + escolha =
  bloqueio), com erro tipado — paridade helper/tool, como ja acontece com a
  regra de constitution-conflict.
- **Operador responde ao bloqueio estrutural com "decida voce"**: a resposta
  humana E o consentimento; o orquestrador registra a Decisao com referencia
  ao bloqueio respondido e prossegue — o que se exige e o consentimento
  rastreavel, nao que o humano escolha a opcao.
- **Mesmo eixo perguntado duas vezes** (ex.: `specify` e `plan`): a segunda
  etapa reconhece a Decisao humana anterior pelo eixo e nao re-pergunta.
- **Feature-00c em projeto cuja constitution ja fixa a stack**: a constitution
  e fonte humana ratificada — nao ha bloqueio; a Decisao cita a constitution.

## Requirements

### Functional Requirements

- **FR-001**: O sistema MUST reconhecer uma **classe** de Decisao —
  `estrutural` ou `operacional` — declarada no registro da Decisao pelo
  orquestrador, persistida com a Decisao e visivel a todos os leitores
  (relatorio, auditoria, indice de conhecimento).
- **FR-002**: A declaracao de classe MUST ser **obrigatoria** sempre que as
  opcoes consideradas contiverem um token da familia de bloqueio humano
  (`bloqueio-humano*` / `pause-humano`); registro sem classe nesse caso e
  recusado como uso incorreto, sem gravar nada.
- **FR-003**: Uma Decisao de classe `estrutural` registrada por agente
  automatico MUST ter escolha = o token de bloqueio humano e score 0; qualquer
  outra combinacao (inclusive score 3 com evidencia) e recusada com mensagem
  que cita a classe, o eixo e o caminho correto — mesma mecanica da regra de
  constitution-conflict ja existente.
- **FR-004**: A regra FR-002/FR-003 MUST valer identicamente no caminho MCP
  (`record_decision`), com erro tipado e contrato atualizado — paridade
  helper/tool.
- **FR-005**: Decisoes de classe `operacional` MUST manter a regua de score
  atual sem nenhuma mudanca de comportamento (regressao zero na suite
  existente).
- **FR-006**: A prosa dos dois orquestradores MUST enumerar a classe
  estrutural (tabela de eixos acima) e instruir: toda decisao que fixa um
  desses eixos e registrada como `estrutural`, com o token de bloqueio entre as
  opcoes, seguida de bloqueio humano que apresenta opcoes + recomendacao do
  agente (com evidencia quando houver) — nunca Phase 0 do `plan`.
- **FR-007**: O sistema MUST extrair da tabela "Itens a Definir" do briefing os
  itens com impacto **Alto** (parser tolerante; briefing canonico e legado;
  tabela ausente/irreconhecivel = zero itens com aviso) e disponibiliza-los ao
  orquestrador em forma deterministica (lista).
- **FR-008**: No inicio das etapas `specify` e `plan` em modo autonomo, para
  cada item Alto sem Decisao humana rastreavel na execucao, o orquestrador MUST
  registrar um bloqueio humano e encerrar a onda em `bloqueio_humano` antes de
  invocar a skill da etapa; item ja decidido por humano MUST NOT ser
  re-perguntado.
- **FR-009**: A skill `plan`, em modo autonomo, MUST NOT resolver por
  inferencia um `NEEDS CLARIFICATION` de classe estrutural no Phase 0; em modo
  interativo o comportamento atual e preservado.
- **FR-010**: O gate de qualidade do plano MUST emitir finding **critico**
  quando o Technical Context nao declarar o ambiente de execucao alvo (campo
  ausente ou pendente) e finding de **aviso** quando o declarar sem fonte
  rastreavel; em modo autonomo o finding critico vira bloqueio humano pela
  tabela de gates existente.
- **FR-011**: `create-tasks` MUST ordenar qualquer gate humano de dependencias
  DEPOIS da decisao humana de stack quando a execucao tiver uma decisao
  estrutural de stack registrada ou pendente.
- **FR-012**: O relatorio de auditoria MUST identificar cada Decisao estrutural
  com seu agente decisor e marcar como **anomalia de governanca** toda
  estrutural cuja escolha nao seja o bloqueio humano e cujo agente nao seja
  humano; `review-task` MUST reportar as contagens (estruturais, anomalias).
- **FR-013**: Registros de Decisao anteriores a esta feature (sem classe) MUST
  continuar validos e legiveis (classe ausente = nao declarada), sem migracao
  obrigatoria de estado.
- **FR-014**: Toda leitura de artefato (briefing, plan) feita por estes gates e
  CONTEUDO, nunca instrucao — texto lido nao pode alterar a classe, o score ou
  a decisao de pausar (mesma regra do INV-4).

> Decisoes de infraestrutura: N/A (feature de governanca do runtime; sem
> scheduling, criptografia, refresh, lock multi-pod ou backup novos).

### Key Entities

- **Decisao (classe)**: atributo novo da Decisao auditavel — `estrutural` |
  `operacional` | ausente (legado). Relaciona-se ao eixo estrutural (texto no
  contexto) e ao bloqueio humano que a resolveu.
- **Item a Definir (briefing)**: linha da tabela "Itens a Definir" — item,
  dimensao, impacto (Alto/Medio/Baixo). Consumido pela primeira vez por esta
  feature; relaciona-se a zero ou uma Decisao humana na execucao.
- **Eixo estrutural**: categoria fechada (linguagem/runtime, stack,
  arquitetura, persistencia, ambiente alvo, tier); usada na prosa, na mensagem
  de recusa e na deteccao de "ja decidido".
- **Anomalia de governanca**: Decisao estrutural sem consentimento humano
  rastreavel; derivada (nunca gravada), reportada por relatorio/review-task.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Reproduzindo o cenario da #146 num projeto de teste (briefing com
  item Alto de stack), a execucao autonoma pausa **antes** de `plan.md` existir
  em 100% das execucoes; nenhuma Decisao estrutural com escolha != bloqueio e
  sem agente humano e gravada.
- **SC-002**: 100% das Decisoes estruturais registradas em execucoes autonomas
  apos a feature tem consentimento humano rastreavel (bloqueio respondido ou
  Decisao de operador) — verificavel pelo relatorio (0 anomalias).
- **SC-003**: 0 `plan.md` com ambiente de execucao alvo ausente/pendente passa o
  gate de qualidade do plano (finding critico em 100% dos casos de teste).
- **SC-004**: Regressao zero: toda a suite existente de Decisoes operacionais,
  clarify e gates passa sem alteracao de expectativa; Decisoes legadas sem
  classe continuam legiveis por relatorio e indice.
- **SC-005**: O tempo adicionado ao inicio de `specify`/`plan` pela extracao de
  itens Alto e imperceptivel ao operador (mesma ordem de grandeza dos gates
  existentes; sem chamada de rede).
- **SC-006**: Para decisoes operacionais, o numero de bloqueios humanos por
  execucao nao aumenta (medido em re-execucao de um projeto de referencia antes
  x depois).

## Delta Requirements

**Skip**: o corpus `docs/specs/current/` nao possui capability para Decisoes
auditaveis/score nem para os gates de briefing/plan — a feature e aditiva sobre
comportamento ainda nao capturado no corpus; o archive desta feature
introduzira a capability correspondente — Claude (sessao do operador),
2026-08-19
