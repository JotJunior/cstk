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

Esta especificação foi reaberta uma vez (round 2, issue #188) para ampliar
deliberadamente o escopo do round 1. O texto abaixo já está consolidado: na
seção `## Requirements`, cada requisito enuncia a regra vigente por inteiro,
sem depender de emendas posteriores para ser lido corretamente. A seção
`## Delta Requirements` re-enuncia esses mesmos requisitos por exigência da
ferramenta que aplica o delta ao corpus — é repetição deliberada, não uma
segunda fonte normativa; em caso de divergência, prevalece
`## Requirements`. O registro do que o round 1 garantia, e por que deixou de
valer, está no Apêndice A ao fim deste documento (histórico, não normativo).

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
  *Nota posterior a esta sessão*: o enunciado da pergunta acima listava
  `zero-reconhecida` entre os vereditos que a FR-010 nunca produziria. A
  regra de precedência da FR-010, ratificada depois desta sessão
  (`research.md` Decision 11), abriu a única exceção: quando `M == 0` e
  `N > 0`, um insumo com `Q > 0` emite `zero-reconhecida`, não
  `cobertura-parcial`. A resposta acima (o token é `cobertura-parcial`)
  segue válida para todos os demais insumos com `Q > 0`.
- Q: FR-011 exige um exit code novo, distinto dos já usados por
  `extract-must.sh --coverage` (0, 1, 2, 3), mas não fixa o número. Qual
  valor? → A: `4` — confirmado por leitura de
  `plugins/cstk/skills/converge/scripts/extract-must.sh`: os exit codes 0
  (sucesso/`ok`/`sem-must-declarado`), 1 (`--constitution` ausente ou
  contagem corrompida), 2 (erro de uso) e 3 (`zero-reconhecida`) já estão
  em uso; nenhum outro script da skill `converge` reserva o valor 4.

## Notação de contagens (N, M, Q)

Três contagens, todas produzidas pela mesma verificação de cobertura de
`MUST` sobre um único arquivo de constituição, são usadas ao longo desta
especificação. Elas seguem a legenda do modo `--coverage` de
`plugins/cstk/skills/converge/scripts/extract-must.sh`:

- **N** — ocorrências da palavra `MUST` no arquivo, contadas de forma
  independente do parser (inclui `MUST` em prosa corrida).
- **M** — linhas de regra `MUST` efetivamente reconhecidas pelo parser
  (formato de rótulo no início da linha).
- **Q** — princípios emitidos **só pelo rótulo do heading** (por exemplo
  `(NON-NEGOTIABLE)`), sem nenhuma regra `MUST` legível no corpo do
  princípio.

Toda condição de **cobertura** enunciada nesta especificação é expressa em
termos dessas três contagens, e nenhuma delas depende de contagem definida em
outro documento. Requisitos que não versam sobre cobertura (FR-007, FR-008 e
FR-009, que tratam da orientação da skill de constituição) e o Edge Case da
constituição ausente não usam `N`, `M` nem `Q` — a condição deles não é uma
contagem.

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
   cobertura (`N > 0` e `M == 0`), **When** a etapa de convergência roda até
   o fim, **Then** o relatório final contém pelo menos um achado indicando
   que a cobertura de `MUST` está indisponível/zerada para aquela
   constituição, com severidade alta o suficiente para não passar
   despercebido.
2. **Given** o mesmo cenário do item 1, **When** o relatório é consultado
   para decidir se a feature está pronta ("convergida"), **Then** o
   resultado nunca indica "convergida sem pendências" só por causa dessa
   lacuna — ela conta como pendência acionável.
3. **Given** uma `constitution.md` que não contém a palavra `MUST` em lugar
   nenhum e em que nenhum princípio foi emitido só pelo rótulo do heading
   (`N == 0` e `Q == 0`), **When** a etapa de convergência roda, **Then**
   nenhum achado desse tipo é gerado — não há obrigação declarada para o
   gate falhar em cobrir.
4. **Given** uma `constitution.md` em que pelo menos uma regra `MUST` já é
   reconhecida pelo gate e em que nenhum princípio foi emitido só pelo
   rótulo do heading (`M > 0` e `Q == 0`), **When** a etapa de convergência
   roda, **Then** o comportamento observável anterior a esta feature é
   preservado — nenhum achado novo é introduzido só porque outras
   obrigações estão em prosa não reconhecida (limitação conhecida,
   documentada como fora de escopo nos Edge Cases).
5. **Given** uma `constitution.md` com pelo menos um princípio emitido só
   pelo rótulo do heading, sem nenhuma regra `MUST` legível no corpo desse
   princípio (`Q > 0`), **When** a etapa de convergência roda, **Then** o
   relatório final contém o achado de cobertura e ele conta como pendência
   acionável — nas três combinações possíveis de `Q > 0`: com outras regras
   `MUST` da mesma constituição já reconhecidas (`M > 0`); com a palavra
   `MUST` ausente do arquivo inteiro (`N == 0` e `M == 0`); e com a palavra
   `MUST` presente mas nenhuma regra reconhecida (`N > 0` e `M == 0`), caso
   em que a regra de precedência da FR-010 mantém o veredito
   `zero-reconhecida` sem suprimir o achado. Este cenário é o espelho
   verificacional das FR-010/FR-012 no nível do achado, não uma obrigação
   adicional — quem fixa o veredito de cada combinação é a FR-010.

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

- **Constituição ausente** (o arquivo `constitution.md` não existe no
  projeto-alvo): esse já é um caso hoje tratado como "verificação de MUST
  indisponível" pelo gate — esta feature não altera esse comportamento, que
  continua distinto do caso "arquivo existe mas cobertura é zero".
- **Cobertura mista de formato dentro do corpo dos princípios** (`M > 0`
  junto de outras obrigações escritas em prosa corrida que o parser não lê,
  com `Q == 0`): fora de escopo desta feature — equivale à 3ª sugestão da
  issue #173, deferida. Com `Q == 0`, o achado desta feature só dispara
  quando `N > 0` **e** `M == 0` (FR-001) — ter `M > 0` basta para suprimi-lo
  (FR-006). Quando `Q > 0`, o caso deixa de ser este Edge Case e passa a ser
  regido pela FR-010.
- **Constituição que nunca menciona a palavra MUST** (`N == 0` — usa outro
  vocabulário de obrigatoriedade, ou não tem seção de princípios
  obrigatórios), **com `Q == 0`**: não gera o achado desta feature — não há
  intenção de `MUST` declarada para o gate falhar em cobrir (ver FR-005).
  Quando `Q > 0`, a FR-010 se aplica e o achado É gerado, ainda que a
  palavra `MUST` não apareça em lugar nenhum do arquivo — este é o
  caso-bandeira da issue #188.

## Requirements

### Functional Requirements

- **FR-001**: Quando a verificação de cobertura de `MUST` da etapa de
  convergência reportar que a constituição do projeto-alvo contém pelo menos
  uma ocorrência da palavra MUST e nenhuma linha de regra reconhecida
  (`N > 0` e `M == 0`), o sistema MUST registrar isso como um achado
  estruturado no relatório de convergência (não apenas como observação
  textual para o agente seguir).
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
  **e** não houver nenhum princípio emitido só por rótulo de heading
  (`N == 0` **e** `Q == 0`) — nessa combinação não há obrigação declarada, em
  nenhum dos dois vocabulários, e a ausência total não é tratada como lacuna
  de cobertura. Quando `Q > 0`, esta garantia não se aplica: prevalece a
  FR-010, e o achado É gerado por desenho, ainda que `N == 0` — esse é
  precisamente o caso-bandeira da issue #188 (medido: `N = 0`, `M = 0`,
  `Q = 1` → `cobertura de MUST: cobertura-parcial`, `exit=4`).
- **FR-006**: O sistema MUST NOT gerar o achado da FR-001 quando pelo menos
  uma linha de regra MUST já for reconhecida na constituição do projeto-alvo
  **e** não houver nenhum princípio emitido só por rótulo de heading
  (`M > 0` **e** `Q == 0`) — nessa combinação o comportamento anterior a esta
  feature é preservado sem mudança, e a cobertura mista de formato dentro do
  corpo dos princípios permanece fora de escopo (ver Edge Cases). Quando
  `Q > 0`, esta garantia não se aplica: prevalece a FR-010, e o achado É
  gerado por desenho, ainda que `M > 0`.
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
- **FR-010**: Quando a verificação de cobertura de `MUST` identificar pelo
  menos um princípio emitido sem nenhuma regra `MUST` legível — isto é,
  emitido só pelo rótulo do heading (`Q > 0`) — o sistema MUST classificar
  esse resultado com um veredito distinto de `ok` e de `sem-must-declarado`,
  mesmo quando outras regras `MUST` da mesma constituição já tiverem sido
  reconhecidas (`M > 0`) e mesmo quando a palavra `MUST` não ocorrer em
  lugar nenhum do arquivo (`N == 0`). O token literal desse veredito
  (exposto na linha `cobertura de MUST: <veredito>`) MUST ser
  `cobertura-parcial` (ver Clarifications, sessão 2026-09-01), com a única
  exceção da regra de precedência do parágrafo seguinte.

  **Precedência de `zero-reconhecida` (deliberada, ratificada —
  `research.md` Decision 11)**: quando os DOIS conjuntivos valerem ao mesmo
  tempo — (a) nenhuma regra `MUST` reconhecida pelo parser em lugar nenhum
  da constituição (`M == 0`) **e** (b) a palavra `MUST` ocorrendo em pelo
  menos um ponto do arquivo, ainda que fora do formato reconhecido
  (`N > 0`) — a guarda de `zero-reconhecida` tem precedência sobre esta
  FR-010: o veredito emitido MUST permanecer `zero-reconhecida` (exit 3),
  não `cobertura-parcial`, resolvendo o empate entre os dois sinais a favor
  do mais forte. Basta faltar UM dos dois conjuntivos para a precedência não
  entrar em jogo, e nesse caso prevalece o corpo desta FR-010: o veredito
  MUST ser `cobertura-parcial` (exit 4) sempre que `Q > 0`. Os dois ramos
  complementares são: falta (b), isto é `M == 0` **e** `N == 0` — o
  caso-bandeira da issue #188, constituição sem nenhuma regra `MUST` legível
  e sem nenhuma ocorrência da palavra `MUST`; e falta (a), isto é `M > 0` —
  pelo menos uma regra já reconhecida convivendo com um princípio
  só-de-heading.

  A precedência não reduz a acionabilidade: o achado estruturado emitido
  pela FR-012 é o mesmo `Gap` nos dois vereditos
  (`contracts/must-coverage-finding.md` §3.2). O comportamento aqui descrito
  já está validado por `tests/test_extract-must.sh ::
  scenario_coverage_r02_precedencia_zero_reconhecida_vence` — esse teste e a
  ordem das guardas em `extract-must.sh` MUST NOT ser alterados por esta
  feature.
- **FR-011**: O veredito `cobertura-parcial` — o que o corpo da FR-010 fixa,
  não o `zero-reconhecida` do ramo de precedência — MUST ser exposto por um
  sinal de saída (exit code) que um consumidor automatizado da verificação de
  cobertura consiga distinguir, sem inspecionar texto, dos sinais já usados
  para `ok`, `zero-reconhecida` e `sem-must-declarado`. Este exit code MUST
  ser `4` (ver Clarifications, sessão 2026-09-01). No ramo de precedência da
  FR-010 o sinal de saída permanece o já usado por `zero-reconhecida`.
- **FR-012**: Quando a etapa de convergência observar o veredito descrito na
  FR-010, o sistema MUST registrar um achado estruturado no relatório de
  convergência com os mesmos campos fixos (artefato afetado = constituição
  do projeto-alvo; origem = a própria verificação de cobertura de `MUST`;
  classificação e severidade calculadas pela mesma regra determinística que
  esta especificação define para o veredito `zero-reconhecida` nas
  FR-002/FR-003) usados para aquele veredito. O achado desta FR-012
  MUST também contar na contagem de pendências acionáveis referida pela
  FR-004 — o resultado "convergido, sem pendências" MUST NOT ser produzido
  enquanto essa condição persistir.
- **FR-013**: Quando houver pelo menos um princípio classificado conforme a
  FR-010 (`Q > 0`), a verificação de cobertura de `MUST` MUST identificar
  nominalmente, na sua saída, qual(is) princípio(s) da constituição do
  projeto-alvo carecem de uma regra `MUST` legível — hoje a saída informa
  apenas a contagem, sem nomear os princípios afetados. A forma exata de
  onde essa identificação nominal aparece na saída (por exemplo: linhas
  adicionais de um relatório já existente, ou um canal de saída separado)
  é uma decisão técnica **deferida para `/plan`**, não fixada por esta
  especificação. A liberdade dessa decisão é delimitada pela FR-014: seja
  qual for a forma escolhida, ela MUST NOT alterar a saída no caso
  `Q == 0`.
- **FR-014**: Quando NÃO houver nenhum princípio classificado conforme a
  FR-010 (`Q == 0`), a saída da verificação de cobertura de `MUST` MUST
  permanecer byte-idêntica ao formato hoje validado para esse caso, sem
  nenhum conteúdo adicional — a identificação nominal da FR-013 só se
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
  e zero linhas de regra reconhecidas (`N > 0` e `M == 0`) resultam em pelo
  menos um item acionável no relatório — nunca em "convergido, sem
  pendências".
- **SC-002**: 0% das execuções da etapa de convergência contra uma
  constituição sem nenhuma ocorrência da palavra MUST e sem nenhum princípio
  emitido só por rótulo de heading (`N == 0` e `Q == 0`), ou com pelo menos
  uma regra MUST já reconhecida e sem nenhum princípio emitido só por rótulo
  de heading (`M > 0` e `Q == 0`), geram o novo achado desta feature —
  nenhum falso-positivo introduzido nesses dois casos. Execuções com
  `Q > 0` estão fora do universo medido por este critério: nelas o achado é
  gerado por desenho (FR-010), e isso não é falso-positivo.
- **SC-003**: Uma constituição gerada do zero pela skill de constituição,
  sem nenhuma edição manual adicional, ao ser auditada pela verificação de
  cobertura de MUST, apresenta pelo menos uma regra reconhecida (nunca
  cobertura zero) — cobrindo, no mínimo, o princípio-base obrigatório que a
  skill sempre inclui.

## Delta Requirements

### Capability: converge-must-coverage-fail-closed

#### ADDED

- **FR-010**: Quando a verificação de cobertura de `MUST` identificar pelo
  menos um princípio emitido sem nenhuma regra `MUST` legível — isto é,
  emitido só pelo rótulo do heading (`Q > 0`, na notação de contagens desta
  capability: `N` = ocorrências da palavra `MUST` no arquivo, `M` = linhas
  de regra `MUST` reconhecidas pelo parser, `Q` = princípios emitidos só por
  rótulo de heading) — o sistema MUST classificar esse resultado com um
  veredito distinto de `ok` e de `sem-must-declarado`, mesmo quando outras
  regras `MUST` da mesma constituição já tiverem sido reconhecidas
  (`M > 0`) e mesmo quando a palavra `MUST` não ocorrer em lugar nenhum do
  arquivo (`N == 0`). O token literal desse veredito (exposto na linha
  `cobertura de MUST: <veredito>`) MUST ser `cobertura-parcial`, com a única
  exceção da regra de precedência a seguir. Precedência de
  `zero-reconhecida` (deliberada, ratificada — `research.md` Decision 11):
  quando os DOIS conjuntivos valerem ao mesmo tempo — (a) `M == 0` **e**
  (b) `N > 0` — a guarda de `zero-reconhecida` tem precedência sobre esta
  FR-010 e o veredito emitido MUST permanecer `zero-reconhecida` (exit 3),
  não `cobertura-parcial`. Basta faltar UM dos dois conjuntivos para a
  precedência não entrar em jogo, e nesse caso o veredito MUST ser
  `cobertura-parcial` (exit 4) sempre que `Q > 0`; os dois ramos
  complementares são `M == 0` **e** `N == 0` (falta (b)) e `M > 0` (falta
  (a)). A precedência não reduz a acionabilidade: o achado estruturado
  emitido pela FR-012 é o mesmo `Gap` nos dois vereditos
  (`contracts/must-coverage-finding.md` §3.2). O comportamento aqui descrito
  já está validado por `tests/test_extract-must.sh ::
  scenario_coverage_r02_precedencia_zero_reconhecida_vence` — esse teste e a
  ordem das guardas em `extract-must.sh` MUST NOT ser alterados por esta
  feature.
- **FR-011**: O veredito `cobertura-parcial` — o que o corpo da FR-010 fixa,
  não o `zero-reconhecida` do ramo de precedência — MUST ser exposto por um
  sinal de saída (exit code) que um consumidor automatizado da verificação de
  cobertura consiga distinguir, sem inspecionar texto, dos sinais já usados
  para `ok`, `zero-reconhecida` e `sem-must-declarado`. Este exit code MUST
  ser `4`. No ramo de precedência da FR-010 o sinal de saída permanece o já
  usado por `zero-reconhecida`.
- **FR-012**: Quando a etapa de convergência observar o veredito descrito na
  FR-010, o sistema MUST registrar um achado estruturado no relatório de
  convergência com os mesmos campos fixos (artefato afetado = constituição
  do projeto-alvo; origem = a própria verificação de cobertura de `MUST`;
  classificação e severidade calculadas pela mesma regra determinística já
  usada para o veredito `zero-reconhecida`) usados para aquele veredito. O
  achado desta FR-012 MUST também contar na contagem de pendências
  acionáveis usada para decidir se a feature está convergida — o resultado
  "convergido, sem pendências" MUST NOT ser produzido enquanto essa condição
  persistir.
- **FR-013**: Quando houver pelo menos um princípio classificado conforme a
  FR-010 (`Q > 0`), a verificação de cobertura de `MUST` MUST identificar
  nominalmente, na sua saída, qual(is) princípio(s) da constituição do
  projeto-alvo carecem de uma regra `MUST` legível — hoje a saída informa
  apenas a contagem, sem nomear os princípios afetados. A forma exata de
  onde essa identificação nominal aparece na saída (por exemplo: linhas
  adicionais de um relatório já existente, ou um canal de saída separado) é
  uma decisão técnica deferida para o plano técnico, não fixada por esta
  especificação; seja qual for a forma escolhida, ela MUST NOT alterar a
  saída no caso `Q == 0` (FR-014).
- **FR-014**: Quando NÃO houver nenhum princípio classificado conforme a
  FR-010 (`Q == 0`), a saída da verificação de cobertura de `MUST` MUST
  permanecer byte-idêntica ao formato hoje validado para esse caso, sem
  nenhum conteúdo adicional — a identificação nominal da FR-013 só se aplica
  quando há pelo menos um princípio a nomear.

## Apêndice A — Histórico de revisão de escopo (round 1 → round 2, issue #188)

Apêndice **não normativo**: registro de proveniência. Nada aqui cria,
revoga ou qualifica obrigação — a regra vigente é integralmente a que está
nas seções acima.

O round 1 desta feature (issue #173) foi escrito sob a premissa de que só
dois insumos mereciam achado: cobertura zero com a palavra `MUST` presente
(`N > 0` e `M == 0`). Naquele desenho, `N == 0` e `M > 0` eram ambos
"sem achado", incondicionalmente. O operador reabriu a feature (round 2,
issue #188) e ampliou deliberadamente o escopo para também cobrir o
princípio emitido **só pelo rótulo do heading** (`Q > 0`), medido em campo:
uma constituição com um princípio `(NON-NEGOTIABLE)` e corpo sem nenhuma
regra `MUST` passava pelo gate sem qualquer sinal, caindo em
`sem-must-declarado`.

Isto não foi correção de defeito de implementação do round 1: foi revisão
deliberada de escopo, autorizada pelo operador ao reabrir a feature.

Trechos cuja redação de round 1 deixou de valer como estava, e o que passou
a valer (já consolidado no corpo deste documento):

| Trecho | Round 1 garantia | Round 2 (vigente) |
|---|---|---|
| `FR-005` | Nunca gerar o achado quando `N == 0`, incondicionalmente. | Só quando `N == 0` **e** `Q == 0`; com `Q > 0` o achado é gerado (FR-010). |
| `FR-006` | Nunca gerar o achado quando `M > 0`, incondicionalmente. | Só quando `M > 0` **e** `Q == 0`; com `Q > 0` o achado é gerado (FR-010). |
| US1, Acceptance Scenario 3 | Espelhava `FR-005` sem o conjuntivo `Q == 0`. | Qualificado com `Q == 0`; o caso `Q > 0` é coberto pelo novo Scenario 5. |
| US1, Acceptance Scenario 4 | Espelhava `FR-006` sem o conjuntivo `Q == 0`. | Qualificado com `Q == 0`; o caso `Q > 0` é coberto pelo novo Scenario 5. |
| `SC-002` | Media as duas cláusulas sem o conjuntivo `Q == 0`, declarando falso-positivo o comportamento que a feature entrega. | As duas cláusulas exigem `Q == 0`; execuções com `Q > 0` ficam fora do universo medido. |
| Edge Case "cobertura mista de formato" | Fora de escopo, incondicionalmente (3ª sugestão da issue #173, deferida). | Fora de escopo apenas com `Q == 0`; com `Q > 0`, regido pela FR-010. |
| Edge Case "constituição nunca menciona MUST" | Nenhum achado, incondicionalmente. | Nenhum achado apenas com `Q == 0`; com `Q > 0`, achado gerado (caso-bandeira #188). |

A 3ª sugestão da issue #173 (parser aceitar prosa restrita a bullet)
permanece **fora de escopo** nos dois rounds: `Q` conta princípio sem
nenhuma regra legível, não obrigação escrita em prosa dentro de um
princípio que já tem regra rotulada.
