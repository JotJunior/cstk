# Feature Specification: Ranking Composto no cstk recall

**Feature**: `recall-ranking`
**Created**: 2026-08-20
**Status**: Draft

## Clarifications

### Session 2026-08-20

- Q: Em que nivel de autoridade de ranking o tipo "memoria" (memory) deve entrar na hierarquia composta de FR-001/FR-010? A) mesmo nivel de alta autoridade de decisao/bloqueio; B) mesmo nivel de baixa autoridade de retro/skill; C) nivel intermediario proprio, entre decisao/bloqueio e retro/skill. → A: C — tier intermediario proprio: type=memory entra entre decision/block (alta autoridade) e retro/skill (baixa autoridade) na hierarquia do ranking composto (dec-012).

## User Scenarios & Testing

### User Story 1 - Achados de alta autoridade nao ficam soterrados (Priority: P1)

Como operador consultando `cstk recall` sobre um topico ja tratado em execucoes
passadas, quero que decisoes auditadas e bloqueios humanos apareçam antes de
retrospectivas e registros de invocacao de skill quando a relevancia textual da
busca for comparavel entre eles, para nao perder o achado mais importante em meio
a ruido de baixa autoridade.

**Why this priority**: E o nucleo da feature — sem isso, o restante (recencia,
`--explain`) e apenas afinamento sobre um ranking que ja falha em priorizar o que
mais importa.

**Independent Test**: Rodar uma busca cujo indice contenha, para o mesmo termo,
pelo menos um resultado de type=decision (ou bloqueio) e um de type=retro (ou
skill) com relevancia textual comparavel; verificar que o resultado de maior
autoridade aparece antes.

**Acceptance Scenarios**:

1. **Given** o indice tem uma decisao e um registro de skill igualmente
   relevantes para o termo buscado, **When** o operador executa a busca,
   **Then** a decisao aparece antes do registro de skill no resultado.
2. **Given** o indice tem um bloqueio humano e uma retrospectiva igualmente
   relevantes para o termo buscado, **When** o operador executa a busca,
   **Then** o bloqueio humano aparece antes da retrospectiva.

---

### User Story 2 - Contexto mais recente vem primeiro quando a relevancia empata (Priority: P2)

Como operador ou orquestrador consumindo `cstk recall` (busca ou modo
`--context`), quero que, entre achados igualmente relevantes e de mesma
autoridade, os mais recentes fiquem a frente dos mais antigos, para que o
contexto injetado reflita o estado de conhecimento mais atual do projeto.

**Why this priority**: Complementa a autoridade por tipo — sem desconto de
recencia, um achado desatualizado de alta relevancia textual pode permanecer
no topo indefinidamente mesmo depois de superado por decisoes mais recentes do
mesmo tipo.

**Independent Test**: Rodar uma busca cujo indice contenha dois resultados do
mesmo tipo e relevancia textual comparavel, diferindo apenas na data de
criacao/ingestao; verificar que o mais recente aparece primeiro.

**Acceptance Scenarios**:

1. **Given** duas decisoes igualmente relevantes para o termo buscado, uma
   registrada ha poucos dias e outra ha varios meses, **When** o operador
   executa a busca, **Then** a decisao mais recente aparece primeiro.
2. **Given** um achado indexado antes de o sistema comecar a rastrear a data
   de criacao/ingestao (achado legado sem esse dado), **When** o operador
   executa uma busca que o retorna, **Then** o achado aparece no resultado
   sem erro, tratado com a prioridade de recencia mais baixa possivel.

---

### User Story 3 - Entender por que um resultado ficou naquela posicao (Priority: P3)

Como operador ou desenvolvedor investigando a qualidade do ranking, quero pedir
explicitamente a explicacao de como cada resultado da busca foi pontuado
(relevancia textual, peso de autoridade aplicado, sinal de recencia aplicado),
para poder auditar e ajustar minha confianca no ranking sem adivinhar o motivo
da ordem apresentada.

**Why this priority**: E uma capacidade de auditoria/depuracao aditiva — util
para confiar no ranking das Stories 1-2, mas o sistema entrega valor completo
mesmo sem ela.

**Independent Test**: Rodar uma busca com a flag de explicacao ativada e
verificar que cada resultado retornado exibe os componentes individuais que
formaram sua posicao final.

**Acceptance Scenarios**:

1. **Given** uma busca normal retorna resultados, **When** o operador repete a
   mesma busca pedindo a explicacao do ranking, **Then** cada resultado exibe
   sua relevancia textual, o peso de autoridade aplicado e o sinal de
   recencia aplicado.
2. **Given** o operador nao pede a explicacao, **When** executa a busca
   normalmente, **Then** o formato de saida e identico ao comportamento atual
   (sem os componentes de explicacao).

---

### Edge Cases

- O que acontece quando um achado nao tem sinal de recencia utilizavel
  (indexado antes do rastreio de data existir)? Deve ser ranqueado mesmo
  assim, com o sinal de recencia mais baixo possivel (nunca excluido, nunca
  erro) — coberto no Acceptance Scenario 2 da Story 2.
- Como o sistema lida com empate total (mesma relevancia textual, mesmo tipo,
  mesma data)? A ordem entre esses resultados deve ser deterministica e
  reproduzivel entre execucoes identicas (FR-009).
- O que acontece se o operador pedir explicacao (Story 3) junto do modo
  `--context` (consumido por outro sistema, nao por um humano)? A explicacao
  e uma capacidade de busca interativa; o modo `--context` preserva seu
  formato e teto de bytes documentados inalterados (FR-004) — a explicacao
  nao se aplica a esse modo.
- O que acontece se um operador pedir para o ranking considerar links entre
  achados (grafo) ou combinar multiplas listas via reciprocal-rank-fusion
  (RRF)? Esta feature nao implementa nenhum dos dois mecanismos — ambos
  ficam explicitamente fora de escopo e deferidos a uma feature futura
  (`recall-hybrid-rrf`); o ranking composto aqui usa apenas relevancia
  textual, autoridade de tipo e recencia (FR-011).

## Requirements

### Functional Requirements

- **FR-001**: O modo de busca (`cstk recall <query>`) MUST aplicar um reforco
  de ranking por autoridade de tipo, de modo que resultados de decisao e de
  bloqueio humano fiquem a frente de resultados de retrospectiva e de
  invocacao de skill quando a relevancia textual for comparavel.
- **FR-002**: O modo `--context` MUST aplicar o mesmo reforco de autoridade por
  tipo descrito em FR-001.
- **FR-003**: Ambos os modos (busca e `--context`) MUST aplicar um desconto de
  ranking baseado em recencia, favorecendo resultados mais recentes sobre mais
  antigos quando relevancia textual e autoridade de tipo forem comparaveis.
- **FR-004**: O formato de saida e o teto de tamanho ja documentados do modo
  `--context` MUST permanecer inalterados; apenas a ordem dos resultados pode
  mudar.
- **FR-005**: O modo de busca MUST suportar uma flag aditiva de explicacao
  que, quando presente, expoe para cada resultado retornado os componentes
  individuais que formaram seu ranking final (relevancia textual, peso de
  autoridade aplicado, sinal de recencia aplicado).
- **FR-006**: O formato de saida padrao do modo de busca (sem a flag de
  explicacao) MUST permanecer identico ao comportamento atual quando a flag
  nao for informada.
- **FR-007**: O novo ranking MUST funcionar imediatamente sobre os dados ja
  indexados hoje, sem exigir reindexacao ou migracao pelo operador.
- **FR-008**: Resultados sem sinal de recencia utilizavel (ex.: achados
  indexados antes de o rastreio de data existir) MUST continuar sendo
  retornados e ranqueados — nunca excluidos nem causando erro — recebendo o
  sinal de recencia mais baixo possivel.
- **FR-009**: A ordem do ranking MUST ser deterministica: para um conjunto de
  dados e uma consulta fixos, execucoes repetidas MUST retornar os resultados
  na mesma ordem.
- **FR-010**: O nivel de autoridade do tipo "memoria" (registro de
  conhecimento de longo prazo, distinto de decisao/bloqueio e de
  retro/skill) MUST ocupar um tier intermediario proprio na hierarquia de
  autoridade do ranking composto: abaixo de decisao/bloqueio (alta
  autoridade) e acima de retro/skill (baixa autoridade) — ver
  Clarifications, Session 2026-08-20.
- **FR-011**: O sistema MUST NOT implementar, como parte desta feature,
  fusao por reciprocal-rank (RRF) nem ranking baseado em grafo de links entre
  achados — esse escopo fica explicitamente deferido a uma feature futura.
- **FR-012**: O sistema MUST NOT expor a nova capacidade de ranking nem a
  flag de explicacao atraves de nenhuma ferramenta MCP — fora do escopo desta
  feature.

> Decisoes de infraestrutura: N/A (feature e computacao stateless sobre um
> indice ja existente; nao introduz scheduling, rotacao de chaves, refresh
> de token externo, lock cross-processo ou backup/restore novos).

### Key Entities

- **Resultado de Busca**: um achado retornado por uma consulta, carregando seu
  tipo (decisao, bloqueio, retrospectiva, skill ou memoria), sua relevancia
  textual em relacao a consulta e sua data de criacao/ingestao.
- **Explicacao de Ranking**: detalhamento por resultado dos componentes
  (relevancia textual, peso de autoridade, sinal de recencia) que produziram
  sua posicao final — exposta apenas quando a flag de explicacao e usada.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Em consultas com resultados de tipos diferentes e relevancia
  textual comparavel, resultados de decisao e de bloqueio humano ficam a
  frente de resultados de retrospectiva/skill em pelo menos 95% dos cenarios
  de teste com relevancia comparavel.
- **SC-002**: Todos os consumidores atuais do modo `--context` observam zero
  mudanca no formato de saida ou no teto de tamanho apos esta feature (a
  suite de regressao do contrato existente passa sem alteracao nas
  asercoes de formato).
- **SC-003**: Dados dois resultados do mesmo tipo e relevancia textual
  comparavel mas datas de criacao diferentes, o mais recente fica em
  primeiro lugar em pelo menos 90% dos cenarios de teste.
- **SC-004**: Quando a flag de explicacao e usada, 100% dos resultados
  retornados exibem visivelmente o detalhamento dos componentes que
  formaram sua posicao.
- **SC-005**: O novo ranking entra em vigor sobre os dados historicos ja
  existentes com zero passos manuais de migracao/reindexacao pelo operador.
- **SC-006**: A feature nao introduz nenhuma mudanca quebradora para
  consumidores existentes do recall — a suite de testes existente continua
  passando sem exigir mudanca de comportamento fora das asercoes que tratam
  especificamente de ordem de resultados.

## Delta Requirements

**Skip**: o comportamento de ranking de `cstk recall` nao esta documentado
como capability ativa no corpus `docs/specs/current/` (nenhum arquivo la
trata do recall) — nao ha entrada existente para gerar delta contra; esta
feature introduz comportamento novo sem capability correspondente no corpus
de living-specs — agente-00c-feature-orchestrator, 2026-08-20.
