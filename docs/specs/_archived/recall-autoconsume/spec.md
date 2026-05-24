# Feature Specification: recall-autoconsume

**Short name**: `recall-autoconsume`
**Status**: Clarified
**Created**: 2026-05-23
**Pipeline**: feature-00c (execucao autonoma `feat-recall-autoconsume-20260523-204733`)

## Visao geral

Fechar o **loop de aprendizado** da memoria de conhecimento cross-feature
(`cstk-knowledge-db`, v3.17.0, arquivada em
[`docs/specs/_archived/cstk-knowledge-db/spec.md`](../_archived/cstk-knowledge-db/spec.md)).

Hoje o ciclo e assimetrico: os orquestradores autonomos (`agente-00c`,
`feature-00c`) **ESCREVEM** no indice ao fim de cada onda (hook
`cstk recall --ingest`), e existe **leitura manual interativa**
(`cstk recall <query>`). O que falta — e o que a User Story 1 da spec
arquivada antecipou com "Como operador (ou ORQUESTRADOR AUTONOMO)..." — e o
**consumo autonomo**: o orquestrador nunca LE o indice antes de decidir. O
conhecimento acumulado de execucoes passadas (decisoes, bloqueios) fica
escrito sem leitor automatico.

Esta feature adiciona um **passo PRE-DECISAO** (read-back loop): nas fases
relevantes, o orquestrador deriva termos da feature corrente, consulta o
indice, e injeta os top-N achados mais relevantes (com proveniencia) no seu
proprio contexto **antes** de tomar decisoes — de modo que erros e escolhas
passadas informem a onda atual.

> **Camada ADITIVA, best-effort**: assim como a ingestao da spec arquivada
> (FR-018), o consumo NUNCA gateia, aborta ou atrasa uma onda. Sem `sqlite3`/
> `jq`, com indice vazio ou zero resultados relevantes, degrada para no-op
> silencioso. Read-only sobre o indice; sem qualquer acoplamento ao
> `state.json` transacional do runtime. Reaproveita o caminho FTS5+bm25 +
> `fts_query_escape` ja existente em `cli/lib/recall.sh` — NAO duplica.

> **Decisoes de infraestrutura**: N/A para scheduling/key-rotation/backup —
> o consumo e disparado inline no loop da onda (sincrono, sem job periodico),
> read-only, e nao persiste estado proprio. O unico estado tocado e o registro
> auditavel da Decisao "consumo de conhecimento" no `state.json` (que ja e
> gerenciado pelo runtime transacional existente, nao por esta feature).

## Clarifications

### Session 2026-05-23

- Q: FR-010 — em quais fases do pipeline o passo PRE-DECISAO de read-back
  agrega valor real vs ruido/custo? → A: APENAS `specify` e `plan` (as fases
  onde decisoes de design acontecem). NAO em `clarify` (ambiguidades ja
  delimitadas), NAO em `execute-task` (mecanico/recorrente — recall vira
  ruido + custo por task, contra SC-006 e Principio V), NAO em ondas de
  gate/review (nao decidem). Custo previsivel: <=2 leituras por feature.
- Q: FR-009 — fonte dos termos da query de recall (aspectos-chave,
  descricao, ou ambos) e como limitar/combinar? → A: Fonte PRIMARIA =
  `aspectos_chave_iniciais` (keywords semanticas destiladas, alto sinal).
  FALLBACK = `descricao_curta` apenas quando aspectos-chave esta
  vazio/degenerado. NAO concatenar ambos por padrao (AND implicito sobre
  muitos tokens de descricao tende a zero match => query degenerada).
  Teto de termos <=8. Query vazia/degenerada => zero resultados => no-op.
  Reaproveita `fts_query_escape`. O COMO combinar (OR vs AND) e detalhe do
  `/plan`.
- Q: FR-007 — aplicar piso de score bm25 para descartar achados fracos, ou
  confiar apenas no teto N? → A: NAO aplicar piso de bm25 absoluto. Confiar
  no teto N pequeno (3-5) + ordenacao `bm25 ASC` ja existente. bm25 do FTS5
  e adimensional e dependente do corpus (magnitudes ~1e-6, sem escala
  estavel nem zero natural) => corte absoluto nao-portavel quebraria SC-005
  e introduziria degradacao agressiva (fere SC-001/best-effort). O teto N ja
  limita ruido por construcao. PODE (nao MUST) considerar corte
  relativo-ao-topo no `/plan` se ruido aparecer na pratica; default = SEM piso.

## User Scenarios & Testing

### User Story 1 - Orquestrador recupera aprendizado passado antes de decidir (Priority: P1)

Como **orquestrador autonomo** (`agente-00c` / `feature-00c`), no inicio de uma
fase relevante (ex: `specify`, `plan`), quero consultar o indice de
conhecimento com termos derivados da feature corrente e receber um bloco
enxuto com os achados mais relevantes de execucoes PASSADAS — decisoes e
bloqueios, com proveniencia (projeto / feature / onda / data) — para que eu
nao repita erros ja documentados e reaproveite escolhas validadas.

**Why this priority**: e o coracao da feature — sem o read-back, a ingestao
(ja existente) escreve para um leitor que nunca le. Entrega o MVP: mesmo so
com esta story, o loop de aprendizado fecha.

**Independent Test**: com um indice populado por execucoes anteriores (de
OUTRAS features), invocar o modo de consumo com termos de uma feature nova e
confirmar que (a) retorna um bloco markdown com top-N achados ordenados por
relevancia; (b) cada achado exibe proveniencia completa; (c) achados da
PROPRIA feature corrente nao aparecem (sem eco).

**Acceptance Scenarios**:

1. **Given** um indice com decisoes/bloqueios de features passadas relevantes
   aos termos da feature corrente, **When** o orquestrador roda o passo
   PRE-DECISAO, **Then** recebe um bloco markdown com ate N achados, cada um
   com conteudo + proveniencia (projeto, feature, onda, data), ordenados por
   relevancia (bm25).
2. **Given** o indice contem registros que a PROPRIA feature corrente acabou
   de ingerir, **When** o consumo roda, **Then** esses registros sao excluidos
   do resultado (sem auto-eco).
3. **Given** zero achados relevantes (indice vazio ou nenhum match), **When** o
   consumo roda, **Then** retorna no-op silencioso (sem bloco, sem erro) e a
   onda prossegue normalmente.
4. **Given** achados recuperados, **When** o bloco e montado, **Then** seu
   tamanho respeita um teto configuravel (nunca infla o contexto da onda
   alem do limite).

### User Story 2 - Modo de leitura-para-contexto formatado para injecao (Priority: P1)

Como **operador ou orquestrador**, quero um novo modo em `cstk recall` que,
distinto do modo busca interativo, retorne os achados ja formatados como um
bloco markdown enxuto pronto para injecao em prompt (proveniencia compacta,
sem cabecalhos verbosos do modo interativo), para que o resultado possa ser
consumido programaticamente sem pos-processamento.

**Why this priority**: e o substrato tecnico da US1 — o passo PRE-DECISAO
(US1) precisa de uma saida estavel e parseavel/injetavel. Reaproveita o
caminho FTS5+bm25 existente (mesmo `fts_query_escape`, mesma resolucao de db),
mudando apenas a FORMATACAO de saida e os FILTROS (exclusao de feature, teto).

**Independent Test**: invocar o novo modo com uma query e `--limit N` contra
um indice de fixture; confirmar que o stdout e um bloco markdown coeso,
diferente do formato do modo busca, e que `--limit`/exclusao de feature/teto
de tamanho sao respeitados. Testar TAMBEM com `HOME` falso (CI-like).

**Acceptance Scenarios**:

1. **Given** um indice de fixture com registros, **When** invoco o novo modo
   com termos e `--limit N`, **Then** recebo um bloco markdown com no maximo N
   achados, formato distinto do modo busca, cada achado com proveniencia
   compacta.
2. **Given** o flag de exclusao de feature corrente, **When** o modo roda,
   **Then** registros daquela feature sao omitidos.
3. **Given** `sqlite3` ou `jq` ausente, **When** o modo roda, **Then** sai com
   no-op silencioso (codigo de sucesso, stdout vazio), sem stack trace.
4. **Given** `HOME` apontando para diretorio sem `~/.claude` (fresh-checkout
   CI), **When** o modo roda com `CSTK_LIB` apontando para `cli/lib`, **Then**
   resolve helpers via `CSTK_LIB` e funciona — nao depende de `~/.claude`.

### User Story 3 - Consumo nunca compromete a onda (degradacao graciosa) (Priority: P1)

Como **mantenedor do runtime**, quero garantir que o passo PRE-DECISAO seja
estritamente best-effort: qualquer falha (sem deps, indice corrompido, db
ausente, timeout) resulta em no-op silencioso e a onda continua, para que o
read-back jamais introduza um novo modo de falha no orquestrador.

**Why this priority**: e a invariante de seguranca operacional herdada da
spec arquivada (FR-018/FR-019). Um loop de aprendizado que pode QUEBRAR a onda
e pior do que nenhum loop.

**Independent Test**: rodar o passo PRE-DECISAO num ambiente sem `sqlite3` e
confirmar que emite no maximo um aviso, nao falha, e o orquestrador avanca a
fase normalmente; repetir com db corrompido/ausente.

**Acceptance Scenarios**:

1. **Given** `sqlite3` indisponivel, **When** o passo PRE-DECISAO roda, **Then**
   ele degrada para no-op (sem bloco injetado), opcionalmente emite aviso em
   stderr, e a onda prossegue sem alteracao de status.
2. **Given** o arquivo do indice ausente ou corrompido, **When** o consumo
   roda, **Then** nenhum erro propaga ao orquestrador e a fase avanca.
3. **Given** o consumo excede um teto de tempo razoavel, **When** o limite e
   atingido, **Then** o consumo e abandonado como no-op (nunca trava a onda).

### User Story 4 - Consumo auditavel por review-task (Priority: P2)

Como **auditor** (via `review-task`), quero que cada ocorrencia de consumo de
conhecimento seja registrada (quantos achados injetados, quais termos, em qual
onda/fase) no `state.json`, para que a eficacia do read-back loop seja
mensuravel e o comportamento seja rastreavel.

**Why this priority**: auditabilidade e Principio I do toolkit. Importante,
mas o loop funciona sem ela — por isso P2.

**Independent Test**: apos uma onda que consumiu o indice, inspecionar o
`state.json` e confirmar que existe uma Decisao (ou entrada equivalente)
documentando o consumo: termos derivados, contagem de achados injetados, fase.

**Acceptance Scenarios**:

1. **Given** o passo PRE-DECISAO injetou K achados, **When** a onda registra
   suas decisoes, **Then** existe um registro auditavel com K e os termos
   usados.
2. **Given** o consumo foi no-op (zero achados), **When** a onda registra,
   **Then** o registro reflete consumo=0 (ou ausencia explicita), sem inflar
   ruido.

### Edge Cases

- **Auto-eco**: a feature corrente acabou de ingerir seus proprios registros
  numa onda anterior; sem exclusao, o consumo re-injetaria o que ela mesma
  produziu. Resolvido por exclusao da feature corrente (FR-005).
- **Indice frio**: primeira feature de um projeto novo — indice vazio. Consumo
  = no-op silencioso, sem aviso ruidoso.
- **Termos degenerados**: aspectos-chave/descricao produzem so stopwords ou
  termos vazios apos derivacao → query degenerada. Tratar como zero resultados.
- **Bloco gigante**: muitos achados longos estourariam o teto de tamanho. O
  teto (FR-006) trunca pelo numero N e por tamanho total.
- **Ruido vs sinal**: achados de baixa relevancia (bm25 fraco) poluiriam o
  contexto. Mitigado exclusivamente por teto N pequeno (3-5) + ordenacao bm25;
  sem piso de score absoluto (resolvido em clarify — FR-007).
- **Concorrencia de leitura durante ingestao**: outra sessao escreve no indice
  enquanto esta le. WAL (ja configurado pela ingestao) permite leitura
  concorrente; leitura best-effort tolera "database is locked" como no-op.
- **Custo de onda**: cada consumo adiciona ~1 chamada de ferramenta +
  wallclock. Pago apenas em `specify` e `plan` (fases de decisao de design);
  excluido de clarify/execute-task/gate/review (resolvido em clarify — FR-010).

## Requirements

### Functional Requirements

#### Modo de consumo (leitura-para-contexto)

- **FR-001**: O sistema MUST oferecer um novo modo de leitura em
  `cli/lib/recall.sh` (despachado por `cstk recall`), distinto do modo busca
  interativo e do modo `--ingest`, que aceita termos de consulta e retorna os
  achados mais relevantes formatados como **bloco markdown enxuto** pronto para
  injecao em prompt.
- **FR-002**: O modo de consumo MUST reaproveitar o caminho de busca
  full-text existente (FTS5 + ordenacao bm25 + `fts_query_escape`) e a
  resolucao de db (`recall_resolve_db`) — MUST NOT duplicar logica de
  escaping ou de query.
- **FR-003**: Cada achado retornado MUST exibir **proveniencia completa**
  (projeto, feature, onda, data) em forma compacta, alinhada com FR-011 da
  spec arquivada.
- **FR-004**: O modo de consumo MUST suportar limite de resultados (`--limit
  N`) com **default pequeno** (entre 3 e 5) e filtro por tipo (`--type`) e por
  projeto, reaproveitando os filtros ja existentes (FR-012 da spec arquivada).
- **FR-005**: O modo de consumo MUST suportar **exclusao da feature corrente**
  (anti-eco): registros cuja proveniencia bate com a feature em execucao MUST
  ser omitidos do resultado, para nao re-injetar o que a propria feature
  ingeriu.
- **FR-006**: O bloco markdown injetado MUST respeitar um **teto de tamanho**
  (por numero de achados E por tamanho total), para nao inflar o contexto da
  onda. O teto MUST ter default razoavel e ser observavel.
- **FR-007**: A relevancia MUST ser ordenada por bm25 (ja existente, `bm25
  ASC` — mais relevante primeiro). O modo MUST NOT aplicar um piso de bm25
  absoluto para descartar achados fracos: o bm25 do FTS5 e adimensional e
  dependente do corpus (sem escala estavel nem zero natural), de modo que um
  corte numerico fixo nao seria portavel (quebraria SC-005) e introduziria um
  novo modo de degradacao agressiva (zero achados mesmo havendo sinal, ferindo
  SC-001/best-effort). O controle de ruido MUST ser feito exclusivamente pelo
  teto N pequeno (FR-004/FR-006). O modo PODE (mas NAO MUST) oferecer no futuro
  um corte relativo-ao-topo (ex: descartar achados com score muito pior que o
  melhor da pagina) — decisao deferida ao `/plan` e somente se ruido aparecer
  na pratica; o default permanece SEM piso.

#### Integracao com o loop da onda dos orquestradores

- **FR-008**: Os orquestradores (`agente-00c-feature-orchestrator` e
  `agente-00c-orchestrator`) MUST executar um **passo PRE-DECISAO** que, no
  inicio das fases relevantes, deriva termos da feature corrente, invoca o
  modo de consumo, e injeta os achados no contexto ANTES de decidir.
- **FR-009**: O passo PRE-DECISAO MUST derivar os termos de consulta usando
  `aspectos_chave_iniciais` da feature corrente como fonte **primaria**
  (keywords semanticas ja destiladas, alto sinal). `descricao_curta` MUST ser
  usada apenas como **fallback**, quando `aspectos_chave_iniciais` estiver
  vazio ou degenerado (so stopwords/termos vazios apos derivacao). O sistema
  MUST NOT concatenar ambas as fontes por padrao — a composicao por AND
  implicito (caminho FTS5 existente) sobre os muitos tokens da descricao tende
  a uma query super-restritiva (zero match). O conjunto de termos MUST ser
  limitado a um teto (<=8 termos) e MUST passar por `fts_query_escape`
  (reaproveitado, FR-002). Query vazia/degenerada MUST ser tratada como zero
  resultados (no-op). A estrategia exata de composicao dos termos (OR vs AND)
  e detalhe de implementacao a ser fixado no `/plan`.
- **FR-010**: O passo PRE-DECISAO MUST rodar **apenas** nas fases `specify` e
  `plan` — as fases onde decisoes de design/arquitetura sao tomadas e onde
  reaproveitar decisoes/bloqueios passados evita repetir erros. O passo MUST
  NOT rodar em `clarify` (opera sobre ambiguidades ja delimitadas — recall
  traria contexto generico de baixo sinal), em `execute-task` (mecanico e
  recorrente; uma leitura por task violaria o espirito de SC-006 e o Principio
  V de custo) nem em ondas de gate/review (nao tomam decisoes de design). Esse
  escopo mantem o custo previsivel em <=2 invocacoes de leitura por feature.
- **FR-011**: O passo PRE-DECISAO MUST passar a feature corrente para o modo de
  consumo de modo que a exclusao anti-eco (FR-005) seja efetiva.

#### Degradacao graciosa (invariante de seguranca operacional)

- **FR-012**: A ausencia de qualquer dependencia opcional (`sqlite3`, `jq`), o
  indice ausente/vazio/corrompido, ou qualquer falha de leitura MUST resultar
  em **no-op silencioso** — sem bloco injetado, sem erro propagado — e MUST
  NUNCA gatear, abortar ou atrasar uma onda do orquestrador (herda FR-018 da
  spec arquivada).
- **FR-013**: O comportamento de degradacao graciosa do modo de consumo
  (ausencia de dep, db ausente, zero resultados) MUST ser coberto por teste
  automatizado (herda FR-019 da spec arquivada).
- **FR-014**: O modo de consumo MUST ser **read-only**: nao modifica o indice,
  nem o `state.json`, nem qualquer artefato transacional do runtime.

#### Privacidade e seguranca (Principio IV)

- **FR-015**: O conteudo lido do indice ja foi tratado por `secrets-filter.sh
  scrub` na fronteira de **ingestao** (FR-017 da spec arquivada). O modo de
  consumo MUST documentar essa premissa e MUST NOT re-introduzir conteudo
  sensivel — a leitura e segura por construcao porque o scrub ocorre na
  escrita. O consumo MUST permanecer estritamente local (Principio IV).

#### Auditabilidade (Principio I)

- **FR-016**: Quando o passo PRE-DECISAO injeta um ou mais achados, o
  orquestrador MUST registrar um evento auditavel (Decisao e/ou marcacao na
  onda) contendo, no minimo, os termos derivados e a contagem de achados
  injetados, de modo que `review-task` consiga medir o uso do read-back loop.
- **FR-017**: O registro auditavel de consumo MUST distinguir consumo efetivo
  (K>0 achados) de no-op (K=0), sem gerar ruido quando nao ha o que injetar.

#### Conformidade constitucional (governam o COMO no /plan)

- **FR-018**: Toda dependencia nao-POSIX usada pelo modo de consumo (`sqlite3`,
  `jq`) MUST entrar pela carve-out de **deps opcionais** da constituicao
  (Principio II, amendment 1.1.0): (a) fallback graceful testado, (b)
  referencias confinadas a um unico arquivo identificavel (`cli/lib/recall.sh`,
  ja o caso), (c) dep declarada com justificativa, caminho e fallback no
  `plan.md`. Reaproveita FR-020 da spec arquivada.
- **FR-019**: Todo codigo entregue MUST ser POSIX sh puro (shebang `#!/bin/sh`,
  `set -eu`, sem bash-isms), com codigo/identificadores em **ingles** e
  comentarios/mensagens admitindo pt-br. O modo de consumo MUST estender
  `cli/lib/recall.sh` sem quebrar os modos busca e `--ingest` existentes
  (camada aditiva).
- **FR-020**: O novo codigo MUST ter teste automatizado segundo a convencao do
  repo: alteracoes em `cli/lib/recall.sh` mapeiam para
  `tests/cstk/test_recall.sh`. Fixtures de bytes crus usam escapes octais
  `\NNN` (nunca hex). LICAO v3.17.0: helpers (`secrets-filter.sh`) MUST ser
  resolvidos via `CSTK_LIB`, NAO so `~/.claude` — senao false-pass local e
  quebra CI fresh-checkout. O modo de consumo MUST ser testado tambem com
  `HOME` falso (cenario CI-like).
- **FR-021**: A feature MUST manter o **escopo auto-contido** do indice
  (FR-023 da spec arquivada): consome exclusivamente conhecimento estruturado
  derivado dos `state.json` do proprio runtime; MUST NOT importar de ou
  interoperar com qualquer memoria externa ao toolkit.

### Key Entities

- **ContextBlock**: o artefato de saida do modo de consumo — um bloco markdown
  enxuto e auto-contido, contendo ate N KnowledgeRecords formatados com
  proveniencia compacta, dimensionado para injecao em prompt sob um teto de
  tamanho.
- **QueryTerms**: o conjunto de termos derivados da feature corrente
  (aspectos-chave e/ou descricao) usado como entrada do consumo, apos a mesma
  neutralizacao de sintaxe FTS5 (`fts_query_escape`) usada na busca.
- **ConsumptionRecord**: o evento auditavel registrado no `state.json` quando o
  consumo ocorre — termos usados, fase, contagem de achados injetados —
  consumido por `review-task`.

> KnowledgeRecord, Provenance e KnowledgeIndex sao herdados da spec arquivada
> `cstk-knowledge-db` — esta feature LE essas entidades, nao as redefine.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Com um indice populado por features anteriores, ao iniciar uma
  fase relevante de uma feature nova com termos sobrepostos, o passo
  PRE-DECISAO injeta pelo menos 1 achado relevante com proveniencia completa em
  100% dos casos onde existe ao menos 1 registro relevante de OUTRA feature.
- **SC-002**: Registros da propria feature corrente aparecem em 0% dos blocos
  injetados (zero auto-eco).
- **SC-003**: Em ambiente sem `sqlite3` ou `jq`, o passo PRE-DECISAO completa
  como no-op em 100% das execucoes, sem nenhuma falha propagada ao
  orquestrador e sem alterar o status da onda.
- **SC-004**: O bloco injetado nunca excede o teto de tamanho configurado em
  100% das execucoes (verificavel por teste com fixture de muitos achados
  longos).
- **SC-005**: O modo de consumo funciona identicamente com `HOME` real e com
  `HOME` falso (resolvendo helpers via `CSTK_LIB`), comprovado por teste que
  roda ambos os cenarios.
- **SC-006**: O custo adicional por onda atribuivel ao consumo e de no maximo 1
  invocacao de ferramenta de leitura por fase consumidora, sem rede e sem
  escrita no indice (read-only verificavel).
- **SC-007**: Apos uma onda que consumiu o indice, 100% das ocorrencias de
  consumo efetivo (K>0) ficam rastreaveis no `state.json` para `review-task`.

## Out of Scope

- Reindex / ingestao: ja entregues pela `cstk-knowledge-db` arquivada; esta
  feature apenas LE.
- Mudanca no schema do indice ou na proveniencia armazenada.
- Re-scrub de secrets na leitura (o scrub ja ocorre na ingestao — FR-015).
- Interop com memoria externa ao toolkit (proibido por FR-021).
- Ranking semantico/embeddings — relevancia permanece bm25 (full-text).

## Dependencies & Assumptions

- **Depende de** `cstk-knowledge-db` (v3.17.0): indice
  `~/.claude/cstk/knowledge.db`, FTS5+bm25, `fts_query_escape`,
  `recall_resolve_db`, scrub na ingestao (FR-017). Codigo em
  `cli/lib/recall.sh`.
- **Assume** que o indice e populado pela ingestao pos-onda ja existente; com
  indice frio, o consumo e legitimamente no-op.
- **Assume** que `aspectos_chave_iniciais` e `descricao_curta` estao
  disponiveis no `state.json` da feature corrente (gerados na pre-flight do
  orquestrador).

## Open Questions (RESOLVIDAS na fase clarify — Session 2026-05-23)

As tres ambiguidades marcadas para clarificacao foram resolvidas em clarify
(ver secao `## Clarifications`). Resumo:

1. **Fases consumidoras** (FR-010): RESOLVIDO — apenas `specify` e `plan`.
2. **Derivacao de termos** (FR-009): RESOLVIDO — `aspectos_chave_iniciais`
   primario, `descricao_curta` so como fallback; teto <=8 termos; sem
   concatenacao por padrao.
3. **Score minimo de relevancia** (FR-007): RESOLVIDO — sem piso de bm25
   absoluto; confiar no teto N + ordenacao bm25.

> Demais itens considerados (opt-out configuravel; interacao com degradacao
> graciosa existente) foram resolvidos com defaults: opt-out e desejavel mas
> nao bloqueante (default = ligado, best-effort); a degradacao reusa
> exatamente o mecanismo da ingestao (FR-012).
