# Feature Specification: Gate de Convergência Recusa Cobertura Zero de MUST

**Feature**: `converge-must-coverage-fail-closed`
**Created**: 2026-08-29
**Status**: Draft

## Contexto (background, não normativo)

Origem: issue #173 do repositório `cstk` (OPEN). Após a issue #171, o script
`extract-must.sh` da skill `converge` só reconhece uma linha de regra `MUST`
quando ela aparece como **rótulo** no início da linha (`**MUST:**`, `- MUST:`,
`* MUST NOT:` — ver `plugins/cstk/skills/converge/scripts/extract-must.sh`,
comentário linhas 82-83: exigir os dois-pontos é deliberado, para manter
"MUST" em prosa corrida fora do sinal de reconhecimento). A skill
`constitution` deste toolkit, hoje, produz regras em **prosa RFC 2119**
("MUST" como verbo no meio da frase), formato que o parser não reconhece.

Medido pelo autor da issue em 4 `constitution.md` reais geradas pela própria
skill: `M == 0` (linhas de regra reconhecidas) nas quatro, com `N` (contagem
independente da palavra MUST) em 7, 7, 5 e 30 respectivamente. Nesse estado,
a skill `converge` (`plugins/cstk/skills/converge/SKILL.md`, ETAPA 3, linhas
~183-191) hoje **só instrui o agente via prosa** a "tratar a verificação de
MUST como indisponível" — não existe nenhum achado estruturado/determinístico
gravado no `ConvergenceReport`, e a contagem `N` (actionable) da ETAPA 7 não é
afetada. Resultado observável: o relatório pode reportar `outcome=clean`
mesmo quando a constituição do projeto declara obrigações `MUST` que o gate
nunca verificou — ausência de cobertura aparecendo como sucesso.

Esta feature cobre as **duas primeiras** das três sugestões da issue #173:

1. `converge` passa a recusar (fail-closed) a cobertura zero, transformando-a
   em achado estruturado e acionável.
2. `constitution` passa a orientar/exemplificar o formato de marcação que o
   gate já reconhece, resolvendo a causa na origem para constituições
   futuras.

A terceira sugestão da issue (o parser de `extract-must.sh` passar a aceitar
também prosa restrita a bullet) está **fora de escopo** desta feature — não
foi solicitada pelo operador; se a análise técnica em `/plan` indicar que ela
é necessária para atender a algum requisito abaixo, isso deve voltar como
bloqueio humano, não ser decidido unilateralmente.

> Decisões de infraestrutura: N/A (feature sem scheduling, sem dados
> persistidos com TTL/criptografia, sem refresh de token externo, sem lock
> multi-pod, sem backup/restore novo, sem chave de idempotência de request —
> altera apenas o comportamento determinístico de duas skills de
> documentação/auditoria estático).

## Clarifications

### Session 2026-09-01

- Q: FR-010 exige um veredito distinto de `ok`/`zero-reconhecida`/
  `sem-must-declarado`, mas não fixa o token literal exposto na linha
  `cobertura de MUST: <veredito>`. Qual token nomeia esse veredito? → A:
  `cobertura-parcial` — mantém a mesma convenção kebab-case/pt-BR dos
  vereditos existentes e reflete o conceito já usado na prosa desta
  especificação ("cobertura mista (ou cobertura só-de-heading)"): pelo
  menos um princípio elegível não teve sua regra `MUST` confirmada, mesmo
  quando outros princípios (ou nenhum outro) já tiveram.
- Q: FR-011 exige um exit code novo, distinto dos já usados por
  `extract-must.sh --coverage` (0, 1, 2, 3), mas não fixa o número. Qual
  valor? → A: `4` — confirmado por leitura de
  `plugins/cstk/skills/converge/scripts/extract-must.sh`: os exit codes 0
  (sucesso/`ok`/`sem-must-declarado`), 1 (`--constitution` ausente ou
  contagem corrompida), 2 (erro de uso) e 3 (`zero-reconhecida`) já estão
  em uso; nenhum outro script da skill `converge` reserva o valor 4.

## User Scenarios & Testing

### User Story 1 - Gate de convergência não aprova silenciosamente uma constituição não coberta (Priority: P1)

Um operador roda a etapa de convergência (`converge`) de uma feature cujo
projeto-alvo tem uma `constitution.md` com obrigações `MUST` escritas em
prosa corrida (formato que o gate de cobertura não reconhece nenhuma linha).
Hoje o relatório final pode reportar a feature como convergida sem qualquer
sinal de que a verificação de princípios obrigatórios nunca rodou de fato.
Com esta feature, o mesmo relatório aponta explicitamente que a cobertura de
`MUST` está zerada, como um item que precisa de atenção — o operador nunca é
levado a acreditar que a conformidade com a constituição foi verificada
quando na prática não foi.

**Why this priority**: é o núcleo da issue (#173) e a classe de defeito que
motivou a feature — "ausência aparecendo como sucesso" é, por definição, o
pior tipo de falso-positivo de um gate de qualidade: ele reduz confiança
justamente onde deveria aumentá-la.

**Independent Test**: pode ser testada isoladamente rodando o gate de
convergência contra um projeto-alvo cuja `constitution.md` contenha a
palavra MUST em prosa (sem nenhum rótulo reconhecido) e verificando que o
relatório resultante não é mais "tudo certo" silencioso.

**Acceptance Scenarios**:

1. **Given** uma `constitution.md` que contém a palavra `MUST` em pelo menos
   uma frase mas nenhuma linha no formato de rótulo reconhecido pelo gate de
   cobertura, **When** a etapa de convergência roda até o fim, **Then** o
   relatório final contém pelo menos um achado indicando que a cobertura de
   `MUST` está indisponível/zerada para aquela constituição, com severidade
   alta o suficiente para não passar despercebido.
2. **Given** o mesmo cenário do item 1, **When** o relatório é consultado
   para decidir se a feature está pronta ("convergida"), **Then** o
   resultado nunca indica "convergida sem pendências" só por causa dessa
   lacuna — ela conta como pendência acionável.
3. **Given** uma `constitution.md` que não contém a palavra `MUST` em lugar
   nenhum (projeto sem obrigações declaradas nesse formato), **When** a
   etapa de convergência roda, **Then** nenhum achado desse tipo é gerado —
   a ausência total de MUST não é, por si só, um sinal de lacuna de
   cobertura (não há o que cobrir).
4. **Given** uma `constitution.md` em que pelo menos uma regra `MUST` já é
   reconhecida pelo gate (mesmo que outras estejam em prosa e não sejam
   reconhecidas), **When** a etapa de convergência roda, **Then** o
   comportamento observável de hoje é preservado — nenhum achado novo desta
   feature é introduzido só por essa cobertura parcial (limitação conhecida,
   documentada como fora de escopo).

---

### User Story 2 - Constituições geradas a partir de agora já nascem no formato que o gate reconhece (Priority: P2)

Um usuário roda a skill de criação/atualização de constituição do projeto
para gerar ou revisar `docs/constitution.md`. A orientação e os exemplos que
essa skill segue hoje resultam em regras `MUST` escritas como prosa corrida,
o que faz a nova constituição já nascer no estado que a User Story 1 precisa
sinalizar como pendência. Com esta feature, a orientação passa a apontar (e
exemplificar) o formato que o gate de cobertura já sabe reconhecer, para que
constituições novas ou revisadas não caiam nessa armadilha desde o início.

**Why this priority**: resolve a causa na origem, mas depende de uma nova
geração/edição de constituição para ter efeito prático — não corrige
constituições já existentes (isso ficaria a cargo de uma edição manual ou de
uma feature separada). Por isso vem depois da User Story 1, que já protege
qualquer constituição, nova ou antiga.

**Independent Test**: pode ser testada isoladamente gerando/atualizando uma
constituição de exemplo com a skill e conferindo que as regras `MUST`
resultantes usam o formato reconhecido pelo gate de cobertura, sem depender
de rodar o gate de convergência em si.

**Acceptance Scenarios**:

1. **Given** um usuário pedindo a criação de uma nova constituição de
   projeto, **When** a skill gera o(s) princípio(s), **Then** a orientação e
   os exemplos que a skill segue apresentam o formato de regra `MUST`
   reconhecido pelo gate de cobertura como a forma esperada de escrever uma
   obrigação, em vez de somente prosa corrida.
2. **Given** o princípio-base obrigatório de Veracidade de Dados que a skill
   sempre inclui (mesmo sem o usuário pedir), **When** esse texto-semente é
   gerado, **Then** ele próprio segue o formato reconhecido pelo gate de
   cobertura, servindo como exemplo vivo da convenção.
3. **Given** uma constituição já existente, gerada antes desta feature,
   **When** esta feature é entregue, **Then** nenhuma constituição existente
   é reescrita ou invalidada automaticamente — o efeito é apenas sobre
   orientação para gerações/edições futuras.

---

### Edge Cases

- Constituição ausente (o arquivo `constitution.md` não existe no
  projeto-alvo): esse já é um caso hoje tratado como "verificação de MUST
  indisponível" pelo gate — esta feature não altera esse comportamento, que
  continua distinto do caso "arquivo existe mas cobertura é zero".
- Constituição contém MUST misturando formato reconhecido e prosa corrida no
  mesmo arquivo (M > 0 mas menor que a contagem real de obrigações
  pretendidas): fora de escopo desta feature (equivale à 3ª sugestão da
  issue #173, deferida) — o achado desta feature só dispara quando a
  cobertura reconhecida é exatamente zero.
- Projeto-alvo cuja constituição nunca menciona a palavra MUST (usa outro
  vocabulário de obrigatoriedade, ou não tem seção de princípios
  obrigatórios): não deve gerar o achado desta feature — não há intenção de
  MUST declarada para o gate falhar em cobrir.

## Requirements

### Functional Requirements

- **FR-001**: Quando a verificação de cobertura de `MUST` da etapa de
  convergência reportar que a constituição do projeto-alvo contém pelo menos
  uma ocorrência da palavra MUST e nenhuma linha de regra reconhecida, o
  sistema MUST registrar isso como um achado estruturado no relatório de
  convergência (não apenas como observação textual para o agente seguir).
- **FR-002**: O achado descrito na FR-001 MUST ser classificado com o mesmo
  tipo usado hoje para "comportamento existente que contradiz o que foi
  pedido" e com a severidade mais alta reservada a esse tipo de achado
  quando associado a uma prioridade alta — refletindo que uma verificação de
  obrigatoriedade que não rodou de fato é, na prática, uma contradição entre
  o que a constituição exige e o que o gate confirma.
- **FR-003**: O achado da FR-001 MUST citar a constituição do projeto-alvo
  como o artefato afetado e identificar como origem a própria verificação de
  cobertura de MUST (não uma tarefa/requisito pré-existente do backlog da
  feature em convergência), para que fique rastreável de onde o achado veio.
- **FR-004**: O achado da FR-001 MUST contar na contagem de pendências
  acionáveis usada para decidir se a feature está convergida — o resultado
  "convergido, sem pendências" MUST NOT ser produzido enquanto essa condição
  de cobertura zero persistir.
- **FR-005**: O sistema MUST NOT gerar o achado da FR-001 quando a
  constituição do projeto-alvo não contiver a palavra MUST em lugar nenhum
  (nenhuma obrigação declarada nesse vocabulário) — ausência total de MUST
  não é tratada como lacuna de cobertura.
- **FR-006**: O sistema MUST NOT gerar o achado da FR-001 quando pelo menos
  uma linha de regra MUST já for reconhecida na constituição do
  projeto-alvo — o comportamento de hoje para cobertura parcial é preservado
  sem mudança (ver Edge Cases).
- **FR-007**: A orientação seguida pela skill de criação/atualização de
  constituição MUST apresentar, como forma esperada de escrever uma
  obrigação de princípio, o formato de regra reconhecido pela verificação de
  cobertura de MUST — substituindo ou complementando a orientação atual, que
  hoje resulta em prosa corrida não reconhecida.
- **FR-008**: O texto-semente do princípio-base obrigatório de Veracidade de
  Dados que a skill de constituição sempre inclui MUST, ele próprio, seguir
  o formato de regra reconhecido pela verificação de cobertura de MUST —
  servindo de exemplo vivo já na primeira constituição gerada por qualquer
  projeto.
- **FR-009**: Esta feature MUST NOT alterar nem exigir alteração de
  constituições de projetos já existentes — o efeito da FR-007/FR-008 é
  sobre orientação consumida em gerações/edições futuras da constituição,
  nunca uma migração automática de arquivos já ratificados.

**Revisão de escopo (issue #188, incremento pós-round-1)**: as FRs abaixo
revogam/emendam deliberadamente a FR-006 desta mesma especificação e o Edge
Case "Constituição contém MUST misturando formato reconhecido e prosa
corrida no mesmo arquivo... fora de escopo desta feature (equivale à 3ª
sugestão da issue #173, deferida)". Medição adicional feita neste
incremento mostrou que a guarda original também deixava passar, sem achado,
uma constituição com um único princípio anunciado só pelo rótulo do heading
(`(NON-NEGOTIABLE)`) e corpo sem nenhuma regra MUST — caso que caía no
veredito `sem-must-declarado`, também suprimido. Isto não é correção de
defeito de implementação do round anterior: é revisão deliberada de escopo,
autorizada pelo operador ao reabrir esta feature.

- **FR-010**: Quando a verificação de cobertura de `MUST` identificar pelo
  menos um princípio emitido sem nenhuma regra `MUST` legível (hoje
  contabilizado como "emitido só por rótulo de heading"), o sistema MUST
  classificar esse resultado com um veredito distinto de `ok`, de
  `zero-reconhecida` e de `sem-must-declarado` — mesmo quando outras regras
  `MUST` da mesma constituição já tiverem sido reconhecidas, e mesmo quando
  nenhuma outra regra `MUST` tiver sido reconhecida em lugar nenhum. Este
  requisito substitui, para este cenário específico, a preservação de
  comportamento afirmada pela FR-006 e pelo Edge Case citado acima:
  cobertura mista (ou cobertura só-de-heading) deixa de ser tratada como
  "sem achado". O token literal deste veredito (exposto na linha
  `cobertura de MUST: <veredito>`) MUST ser `cobertura-parcial` (ver
  Clarifications, sessão 2026-09-01).
- **FR-011**: O veredito descrito na FR-010 MUST ser exposto por um sinal de
  saída (exit code) que um consumidor automatizado da verificação de
  cobertura consiga distinguir, sem inspecionar texto, dos sinais já usados
  para `ok`, `zero-reconhecida` e `sem-must-declarado`. Este exit code MUST
  ser `4` (ver Clarifications, sessão 2026-09-01).
- **FR-012**: Quando a etapa de convergência observar o veredito descrito na
  FR-010, o sistema MUST registrar um achado estruturado no relatório de
  convergência com os mesmos campos fixos (artefato afetado = constituição
  do projeto-alvo; origem = a própria verificação de cobertura de `MUST`;
  classificação e severidade calculadas pela mesma regra determinística já
  usada hoje para o veredito `zero-reconhecida`, conforme FR-002/FR-003
  desta especificação) usados para aquele veredito. O achado desta FR-012
  MUST também contar na contagem de pendências acionáveis referida pela
  FR-004 — o resultado "convergido, sem pendências" MUST NOT ser produzido
  enquanto essa condição persistir.
- **FR-013**: Quando houver pelo menos um princípio classificado conforme a
  FR-010, a verificação de cobertura de `MUST` MUST identificar
  nominalmente, na sua saída, qual(is) princípio(s) da constituição do
  projeto-alvo carecem de uma regra `MUST` legível — hoje a saída informa
  apenas a contagem, sem nomear os princípios afetados. A forma exata de
  onde essa identificação nominal aparece na saída (por exemplo: linhas
  adicionais de um relatório já existente, ou um canal de saída separado)
  é uma decisão técnica **deferida para `/plan`**, não fixada por esta
  especificação — existe um contrato de saída já validado (ver FR-014) que
  a decisão técnica precisa respeitar.
- **FR-014**: Quando NÃO houver nenhum princípio classificado conforme a
  FR-010 (contagem zero), a saída da verificação de cobertura de `MUST`
  MUST permanecer byte-idêntica ao formato hoje validado para esse caso,
  sem nenhum conteúdo adicional — a identificação nominal da FR-013 só se
  aplica quando há pelo menos um princípio a nomear.

### Key Entities

- **Achado de Convergência (achado estruturado no relatório da etapa de
  convergência)**: item existente do relatório de convergência; esta feature
  passa a produzir um achado desse tipo especificamente para o cenário
  "cobertura de MUST zerada", com path (constituição do projeto-alvo),
  origem (a própria verificação de cobertura) e classificação/severidade
  conforme FR-002.
- **Orientação de Formato de Princípio (skill de constituição)**: a
  instrução e os exemplos que guiam como uma regra de princípio obrigatório
  deve ser escrita; esta feature adiciona a esse conjunto o formato
  reconhecido pela verificação de cobertura de MUST.

## Success Criteria

### Measurable Outcomes

- **SC-001**: 100% das execuções da etapa de convergência contra uma
  constituição de projeto-alvo com pelo menos uma ocorrência da palavra MUST
  e zero linhas de regra reconhecidas resultam em pelo menos um item
  acionável no relatório — nunca em "convergido, sem pendências".
- **SC-002**: 0% das execuções da etapa de convergência contra uma
  constituição sem nenhuma ocorrência da palavra MUST, ou com pelo menos uma
  regra MUST já reconhecida, geram o novo achado desta feature (nenhum
  falso-positivo introduzido nesses dois casos).
- **SC-003**: Uma constituição gerada do zero pela skill de constituição,
  sem nenhuma edição manual adicional, ao ser auditada pela verificação de
  cobertura de MUST, apresenta pelo menos uma regra reconhecida (nunca
  cobertura zero) — cobrindo, no mínimo, o princípio-base obrigatório que a
  skill sempre inclui.

## Delta Requirements

### Capability: converge-must-coverage-fail-closed

#### ADDED

- **FR-010**: Quando a verificação de cobertura de `MUST` identificar pelo
  menos um princípio emitido sem nenhuma regra `MUST` legível (hoje
  contabilizado como "emitido só por rótulo de heading"), o sistema MUST
  classificar esse resultado com um veredito distinto de `ok`, de
  `zero-reconhecida` e de `sem-must-declarado` — mesmo quando outras regras
  `MUST` da mesma constituição já tiverem sido reconhecidas, e mesmo quando
  nenhuma outra regra `MUST` tiver sido reconhecida em lugar nenhum. Este
  requisito substitui, para este cenário específico, a preservação de
  comportamento afirmada pela FR-006 e pelo Edge Case citado acima:
  cobertura mista (ou cobertura só-de-heading) deixa de ser tratada como
  "sem achado". O token literal deste veredito (exposto na linha
  `cobertura de MUST: <veredito>`) MUST ser `cobertura-parcial` (ver
  Clarifications, sessão 2026-09-01).
- **FR-011**: O veredito descrito na FR-010 MUST ser exposto por um sinal de
  saída (exit code) que um consumidor automatizado da verificação de
  cobertura consiga distinguir, sem inspecionar texto, dos sinais já usados
  para `ok`, `zero-reconhecida` e `sem-must-declarado`. Este exit code MUST
  ser `4` (ver Clarifications, sessão 2026-09-01).
- **FR-012**: Quando a etapa de convergência observar o veredito descrito na
  FR-010, o sistema MUST registrar um achado estruturado no relatório de
  convergência com os mesmos campos fixos (artefato afetado = constituição
  do projeto-alvo; origem = a própria verificação de cobertura de `MUST`;
  classificação e severidade calculadas pela mesma regra determinística já
  usada hoje para o veredito `zero-reconhecida`, conforme FR-002/FR-003
  desta especificação) usados para aquele veredito. O achado desta FR-012
  MUST também contar na contagem de pendências acionáveis referida pela
  FR-004 — o resultado "convergido, sem pendências" MUST NOT ser produzido
  enquanto essa condição persistir.
- **FR-013**: Quando houver pelo menos um princípio classificado conforme a
  FR-010, a verificação de cobertura de `MUST` MUST identificar
  nominalmente, na sua saída, qual(is) princípio(s) da constituição do
  projeto-alvo carecem de uma regra `MUST` legível — hoje a saída informa
  apenas a contagem, sem nomear os princípios afetados. A forma exata de
  onde essa identificação nominal aparece na saída (por exemplo: linhas
  adicionais de um relatório já existente, ou um canal de saída separado)
  é uma decisão técnica **deferida para `/plan`**, não fixada por esta
  especificação — existe um contrato de saída já validado (ver FR-014) que
  a decisão técnica precisa respeitar.
- **FR-014**: Quando NÃO houver nenhum princípio classificado conforme a
  FR-010 (contagem zero), a saída da verificação de cobertura de `MUST`
  MUST permanecer byte-idêntica ao formato hoje validado para esse caso,
  sem nenhum conteúdo adicional — a identificação nominal da FR-013 só se
  aplica quando há pelo menos um princípio a nomear.
