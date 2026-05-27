# Feature Specification: Show Tips

**Feature**: `show-tips`
**Created**: 2026-05-27
**Status**: Draft

## Clarifications

### Session 2026-05-26

- Q: Qual o formato exato do catalogo em disco? (FR-007 era ambiguo: "texto plano ou Markdown estruturado") → A: Markdown com frontmatter YAML. Cada entrada e um documento Markdown com bloco YAML delimitado por `---` contendo `skill`, `category`, `text`; exemplos no corpo. Arquivo unico `tips/catalog.md` com entradas separadas por `---`. Legivel por humanos sem ferramenta especial; parseavel por `awk`/`grep` em shell POSIX.
- Q: Como o mecanismo de variacao entre execucoes funciona sem estado persistente? (tensao FR-003 vs Edge Case) → A: Selecao pseudoaleatoria via `/dev/urandom` + `awk srand` (POSIX puro — substituicao de `$RANDOM % N` ratificada no plan dec-012 para conformidade com Principio II da constitution). Sem historico persistido entre sessoes. Unicidade absoluta nao e garantida — aceita repeticao eventual.
- Q: Onde no filesystem do toolkit vive o script POSIX de exibicao? (FR-005 nao especificava path) → A: `cli/lib/show-tip.sh`, paralelo a `cli/lib/recall.sh`. Invocavel pelos orquestradores via caminho absoluto ou via wrapper `cstk show-tip`.

## User Scenarios & Testing

### User Story 1 - Tip Displayed at Wave Start (Priority: P1)

Como desenvolvedor usando o pipeline SDD, quero ver uma dica relevante destacada no
inicio de cada onda (quando o orquestrador comecar uma nova fase), para descobrir
funcionalidades das skills que talvez eu nao saiba que existem.

**Why this priority**: E o ponto de maior visibilidade — toda execucao do pipeline
passa por pelo menos uma onda. E a entrega minima viavel: sem o gatilho de exibicao,
a biblioteca de dicas nao tem valor.

**Independent Test**: Executar qualquer skill que gera ondas (`/agente-00c`, `/feature-00c`)
e verificar que, antes ou logo apos o inicio da primeira fase, aparece um bloco
destacado com uma dica. A dica deve ser diferente de outra execucao recente
(variacao de selecao).

**Acceptance Scenarios**:

1. **Given** uma execucao do pipeline inicia uma nova onda, **When** a onda comeca,
   **Then** um bloco visualmente destacado e exibido com: nome da skill referenciada,
   uma frase de dica, e pelo menos um exemplo de uso.

2. **Given** o sistema tem mais de uma dica cadastrada para a skill referenciada,
   **When** a onda comeca, **Then** a dica exibida varia entre execucoes (nao e sempre
   a mesma dica para a mesma skill).

3. **Given** a biblioteca de dicas esta vazia ou inacessivel, **When** a onda comeca,
   **Then** a onda prossegue normalmente sem bloco de dica (fail-silent).

---

### User Story 2 - Rich Tip Library Covering All Skills (Priority: P2)

Como mantenedor do toolkit, quero uma biblioteca com pelo menos 2 dicas e 2 exemplos
por skill (cobrindo todas as skills do projeto), para que os usuarios sempre vejam
conteudo variado e util em cada execucao.

**Why this priority**: Sem conteudo rico, o mecanismo de exibicao tem valor limitado.
A biblioteca e o insumo que torna a feature util a longo prazo. E P2 (nao P1) porque
o mecanismo de exibicao deve funcionar primeiro, mesmo com poucas dicas iniciais.

**Independent Test**: Verificar que o catalogo contem entradas para cada skill listada
no projeto, com pelo menos 2 dicas distintas e pelo menos 2 exemplos por skill.
Verificavel por script que percorre o catalogo e conta entradas por skill.

**Acceptance Scenarios**:

1. **Given** a lista de skills do projeto (global + language-related), **When** o
   catalogo e auditado, **Then** cada skill tem pelo menos 2 entradas de dica
   distintas, cada uma com pelo menos 1 exemplo de uso concreto.

2. **Given** uma nova skill e adicionada ao toolkit, **When** o mantenedor quer
   adicionar dicas para ela, **Then** ha um formato documentado e simples para
   adicionar entradas ao catalogo sem modificar o mecanismo de exibicao.

3. **Given** uma skill tem dicas de diferentes categorias (caso de uso, gotcha,
   exemplo avancado), **When** o catalogo e consultado, **Then** as categorias
   sao distinguiveis e permitem filtro por tipo.

---

### User Story 3 - Tip on Demand (Priority: P3)

Como desenvolvedor, quero poder solicitar uma dica de uma skill especifica a qualquer
momento (fora do contexto de onda do pipeline), para tirar duvidas rapidas sobre como
usar uma skill sem precisar iniciar uma execucao completa.

**Why this priority**: Complementa P1 sem depender de ele. E opcional — P1 e P2
entregam o valor principal; P3 adiciona acessibilidade sob demanda.

**Independent Test**: Invocar o mecanismo de dica para uma skill especifica (ex:
`/show-tip review-task`) e verificar que uma dica com exemplo e exibida, sem iniciar
nenhuma outra skill.

**Acceptance Scenarios**:

1. **Given** o usuario solicita dica de uma skill valida, **When** o pedido e
   processado, **Then** e exibido um bloco destacado com: nome da skill, categoria
   da dica, texto da dica e pelo menos 1 exemplo concreto.

2. **Given** o usuario solicita dica de uma skill que nao existe no catalogo, **When**
   o pedido e processado, **Then** uma mensagem amigavel informa que nao ha dicas
   cadastradas para aquela skill, e sugere skills com dicas disponiveis.

3. **Given** o usuario solicita dica sem especificar skill, **When** o pedido e
   processado, **Then** uma dica aleatoria de qualquer skill e exibida (surpresa util).

---

### User Story 4 - Tips Integrated into Orchestrator Waves (Priority: P4)

Como operador do pipeline autonomo (agente-00c / feature-00c), quero que o sistema
de dicas seja invocavel pelos orquestradores de forma declarativa (um script ou
mecanismo simples), para que a integracao seja estavel e nao quebre quando o catalogo
cresce.

**Why this priority**: E a integracao tecnica que conecta P1 e P3 ao catalogo P2.
E P4 porque e um detalhe de contrato de integracao — o usuario final nao a percebe
diretamente, mas ela garante que tudo funcione junto.

**Independent Test**: O orquestrador invoca o mecanismo de exibicao com parametros
(fase corrente, skill alvo opcional) e recebe de volta o bloco de texto formatado
para exibir, sem precisar conhecer a estrutura interna do catalogo.

**Acceptance Scenarios**:

1. **Given** o orquestrador inicia uma fase, **When** invoca o mecanismo de dicas
   com a fase como parametro, **Then** recebe um bloco de texto pronto para exibicao
   (sem decisoes adicionais por parte do orquestrador).

2. **Given** o mecanismo de dicas e invocado com fase desconhecida ou catalogo
   inacessivel, **When** o resultado e retornado, **Then** retorna string vazia ou
   sinal de "sem dica disponivel" — nunca erro que interrompa a onda.

---

### Edge Cases

- O que acontece quando o mesmo usuario ve a mesma dica duas vezes seguidas? O sistema
  deve evitar repeticao imediata mas nao garantir unicidade absoluta (sem estado
  persistente entre sessoes).
- Como o sistema se comporta se o catalogo tem apenas 1 dica para uma skill? Exibe
  sempre a mesma (sem rotacao necessaria).
- O que acontece se a skill referenciada na dica foi removida do toolkit? A dica
  deve continuar sendo exibida (o catalogo e autonomo e nao valida existencia da skill
  em tempo real).
- Dicas com exemplos que contem caracteres especiais de Markdown (backticks, asteriscos)
  devem ser renderizadas corretamente no formato de destaque.

## Requirements

### Functional Requirements

- **FR-001**: O sistema DEVE manter um catalogo de dicas onde cada entrada contem:
  skill-alvo, categoria (uso / gotcha / avancado), texto da dica (max 2 frases) e
  pelo menos 1 exemplo de uso concreto.

- **FR-002**: O catalogo DEVE ter pelo menos 2 entradas por skill para todas as skills
  do projeto (global + language-related), cobrindo ao minimo as categorias `uso` e
  `gotcha`.

- **FR-003**: O mecanismo de exibicao DEVE selecionar uma dica usando variacao entre
  execucoes via selecao pseudoaleatoria POSIX (`/dev/urandom` + `awk srand` — sem
  bash-isms). Unicidade absoluta entre sessoes NAO e garantida (sem estado
  persistente). Repeticao eventual e aceita.
  > Nota: a Clarification Session 2026-05-26 (Q2) registrou `$RANDOM % N` como
  > resposta provisoria. O plan.md (dec-012, research.md Decision 1) substituiu
  > por `/dev/urandom + awk srand` para conformidade com o Principio II da
  > constitution (POSIX sh puro, zero bash-isms). Esta versao e a fonte de verdade.

- **FR-004**: O bloco de exibicao DEVE ser visualmente destacado em relacao ao texto
  corrente da onda (delimitadores visuais claros, por exemplo caixas ou separadores
  em Markdown).

- **FR-005**: O mecanismo de exibicao DEVE ser invocavel por script POSIX localizado
  em `cli/lib/show-tip.sh`, com no minimo dois parametros: `skill-alvo` (opcional)
  e `fase-corrente` (opcional). Disponivel tambem via wrapper `cstk show-tip`.

- **FR-006**: A invocacao do mecanismo de dicas NUNCA deve bloquear, lancer erro
  fatal ou interromper a execucao da onda — qualquer falha de leitura do catalogo
  resulta em saida silenciosa (string vazia).

- **FR-007**: O formato do catalogo DEVE ser Markdown com frontmatter YAML: arquivo
  unico `tips/catalog.md` onde cada entrada e delimitada por `---`, com campos YAML
  `skill`, `category`, `text` no bloco frontmatter e exemplos no corpo Markdown.
  Parseavel por `awk`/`grep` em shell POSIX sem dependencias adicionais.

- **FR-008**: O catalogo DEVE ser extensivel: adicionar uma nova skill ou nova dica
  a uma skill existente nao deve exigir modificacao do mecanismo de exibicao.

- **FR-009**: O sistema DEVE suportar exibicao de dica sob demanda para uma skill
  especifica, alem do modo automatico por onda.

- **FR-010**: Quando invocado sem parametro de skill, o mecanismo DEVE retornar uma
  dica de qualquer skill do catalogo (selecao variada).

### Key Entities

- **Tip (Dica)**: unidade atomica do catalogo. Atributos: `skill` (nome da skill alvo),
  `category` (enum: `uso` | `gotcha` | `avancado`), `text` (texto da dica, max 2
  frases), `examples` (lista de exemplos de uso, cada um com texto e comando/resultado
  opcional).

- **Tip Catalog**: colecao de todas as dicas do projeto. Organizada por skill.
  Formato em disco: arquivo unico `tips/catalog.md` com entradas em Markdown +
  frontmatter YAML (campos: `skill`, `category`, `text`; corpo: exemplos Markdown).
  Entradas separadas por `---`. Unica fonte de verdade para o mecanismo de exibicao.

- **Tip Block**: representacao formatada de uma dica para exibicao. Contem o
  bloco visual com destaque, skill referenciada, texto e exemplos. Saida do
  mecanismo de exibicao.

- **Display Trigger**: o ponto de invocacao do mecanismo. Pode ser: inicio de onda
  (automatico) ou pedido explicito do usuario/orquestrador (sob demanda).

> Decisoes de infraestrutura: N/A (feature stateless, sem scheduling, sem persistencia
> de estado entre sessoes, sem autenticacao, sem chamadas remotas).

## Success Criteria

### Measurable Outcomes

- **SC-001**: 100% das skills do projeto (global + language-related, conforme listagem
  em `global/skills/` e `language-related/`) tem pelo menos 2 dicas no catalogo ao
  final da implementacao.

- **SC-002**: O mecanismo de exibicao invocado por script retorna resultado (bloco
  ou string vazia) em menos de 1 segundo em qualquer ambiente POSIX, sem dependencia
  de rede.

- **SC-003**: Nenhuma execucao de onda do pipeline (agente-00c / feature-00c) falha
  por causa do mecanismo de dicas — a taxa de interrupcao de onda atribuivel ao
  show-tips e 0%.

- **SC-004**: O catalogo e auditavel por um script automatizado que verifica cobertura
  (todas as skills com >= 2 dicas) e retorna exit 0 quando completo, exit 1 com lista
  de gaps quando incompleto.

- **SC-005**: Um mantenedor consegue adicionar uma nova dica ao catalogo em menos de
  5 minutos, apenas editando o arquivo do catalogo (sem modificar codigo do mecanismo).
