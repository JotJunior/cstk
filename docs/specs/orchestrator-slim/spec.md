# Feature Specification: Enxugar os prompts dos orquestradores autonomos

**Feature**: `orchestrator-slim`
**Created**: 2026-09-29
**Status**: Draft

> Triagem 0.0: modo autonomo detectado (`AGENTE_00C_STATE_DIR`) — confirmacao
> herdada da invocacao do orquestrador; classificacao: refactor/tarefa tecnica
> (sem impacto funcional observavel) — divergencia registrada para auditoria;
> a decisao de rodar a pipeline SDD completa foi do operador.

> Decisoes de infraestrutura: N/A (feature sem scheduling proprio, sem
> criptografia, sem consumo de token externo, sem multi-replica, sem dados
> persistentes novos, sem retry de request).

## Contexto verificado (fonte: leitura real do repositorio em 2026-09-29)

- Os dois orquestradores autonomos sao arquivos unicos em
  `plugins/cstk/agents/`: `agente-00c-orchestrator.md` (146014 bytes) e
  `agente-00c-feature-orchestrator.md` (104702 bytes) — medidos com `wc -c`.
- Cada um e o prompt de sistema completo de um subagente: e carregado inteiro
  a cada spawn de onda, qualquer que seja a fase corrente.
- O orquestrador raiz concentra o corpo da secao "Loop principal de uma onda"
  em ~2000 linhas (linhas 354 a 2347 do arquivo); o orquestrador de feature
  concentra mais de 1000 linhas em secoes de fase/gate especificas (mediacao
  clarify, sequencia pre-spawn de model-routing, quality gates, retrospectiva,
  gh issue, gate de itens Alto).
- A instalacao de agentes (`cstk install`) trata "1 `.md` = 1 artefato": um
  agente nao carrega arquivos irmaos. Ja uma skill e copiada como diretorio
  inteiro. A skill interna `agente-00c-runtime` ja possui um diretorio
  `references/` (mapas `*.txt`, schema SQL) e ja e a dependencia obrigatoria
  dos dois orquestradores (scripts invocados por `~/.claude/skills/agente-00c-runtime/scripts`).
- Varios testes da suite travam contratos do comportamento por grep de
  literais nos `.md` dos orquestradores (ex.: contrato de conclusao de turno,
  guard de evidencia, aplicacao de modelo no spawn, gate do converge, secao
  MCP-vs-Bash byte-identica nos dois arquivos).
- Fontes de medicao de consumo existentes: knowledge.db (tabela `waves`, com
  colunas `otel_total_tokens`, `otel_subagent_tokens`, `agent_*_tokens`,
  `tool_calls`), `wave-usage-report.sh` e OTel. Nesta maquina, das 1912 ondas
  ingeridas, 971 tem `otel_total_tokens` e apenas 58 tem `agent_total_tokens`
  (consulta direta a knowledge.db) — a cobertura observada e parcial e
  desigual entre as colunas.

## Clarifications

### Session 2026-09-29

- Q: Qual a meta minima de reducao do prompt-base por onda (FR-018)? → A:
  40% de reducao em CADA orquestrador (fonte: resposta humana do operador ao
  block-001, registrada na dec-015, opcao A).
- Q: Qual a metrica-gate da meta de reducao (bytes vs tokens)? → A: bytes E
  tokens; sem contagem de tokens disponivel offline, cai para bytes e declara
  a limitacao (dec-010).
- Q: Qual prevalece em conflito, paridade comportamental ou meta de reducao?
  → A: a paridade (FR-002/FR-004) prevalece; se a meta so for atingivel
  violando paridade, a meta nao e atingida e a limitacao e registrada, sem
  declarar ganho nao medido (dec-011).
- Q: Qual o criterio para mover uma secao para referencia? → A: a secao NAO
  roda em 100% das ondas E o ganho liquido de tokens da onda e positivo;
  decisao secao a secao no plano (dec-012).
- Q: Qual a granularidade dos arquivos de referencia? → A: um arquivo por
  fase, mais uma referencia compartilhada para o conteudo comum aos dois
  orquestradores (dec-013).
  Reconciliacao (execute-task 1.1, CHK018): a medicao do plano (research
  Decision 2) nao achou bloco movivel byte-identico entre os dois
  orquestradores; a redacao do FR-001 passou a refletir a estrutura vigente
  (um arquivo por par orquestrador/fase; compartilhada so se houver bloco
  byte-identico; fragmentos intra-orquestrador por SC-006). Sem mudanca de
  decisao — dec-013 permanece valida como regra condicional.

## User Scenarios & Testing

### User Story 1 - Cada onda carrega so o que a fase corrente precisa (Priority: P1)

Como mantenedor do toolkit, quero que o prompt de cada orquestrador contenha
apenas o nucleo comum a todas as ondas, e que o detalhe especifico de fase
(mediacao clarify, quality gates, sequencia de model-routing, gh issue,
retrospectiva etc.) seja lido sob demanda quando a onda entra nessa fase, para
reduzir o volume de contexto pago a cada onda sem alterar o que o orquestrador
faz.

**Why this priority**: e o valor central da feature — o custo recorrente por
onda hoje inclui centenas de KB de instrucao que a fase corrente nao usa.

**Independent Test**: contar bytes/tokens do prompt-base de cada orquestrador
antes e depois; conferir que o prompt-base e estritamente menor e que cada
secao removida existe, integra, num arquivo de referencia apontado pelo
prompt-base.

**Acceptance Scenarios**:

1. **Given** o repositorio no estado pre-feature, **When** o prompt-base de
   cada orquestrador e medido apos a feature, **Then** seu tamanho e menor que
   o baseline medido antes, em pelo menos a meta do SC-001.
2. **Given** uma secao de fase movida para referencia, **When** o
   orquestrador entra na fase correspondente, **Then** o prompt-base contem
   uma instrucao inequivoca de ler a referencia (por caminho resolvivel) ANTES
   de executar os passos daquela fase.
3. **Given** uma onda que nao passa por uma fase (ex.: onda de `execute-task`
   nao passa por `clarify`), **When** a onda roda, **Then** a referencia da
   fase nao e lida.

---

### User Story 2 - Comportamento da pipeline identico (Priority: P1)

Como operador de execucoes autonomas, quero que a pipeline se comporte
exatamente como antes (mesmas Decisoes registradas, mesmo fechamento de onda,
mesmo `Schedule intent`, mesmos gates), para que o enxugamento seja invisivel
para quem usa `/agente-00c` e `/feature-00c`.

**Why this priority**: e a restricao dura do pedido; sem ela a feature vira
risco em vez de otimizacao.

**Independent Test**: suite completa de testes verde (com os testes que
verificam literais nos orquestradores atualizados para apontar tambem para as
referencias), mais uma checagem de inventario que prova que nenhum literal
contratual foi perdido.

**Acceptance Scenarios**:

1. **Given** o conjunto de literais contratuais verificados hoje por testes nos
   `.md` dos orquestradores, **When** a suite roda apos a feature, **Then**
   cada literal continua presente ou no prompt-base ou numa referencia
   declarada, e o teste correspondente continua verificando a presenca.
2. **Given** as secoes de contrato "de turno" (Contrato de conclusao de turno,
   regra de `Schedule intent`, fronteira lock/init, principios MUST,
   anti-padroes), **When** o prompt-base e inspecionado, **Then** essas
   secoes permanecem no prompt-base (nao sao movidas), pois governam TODA
   onda.
3. **Given** a secao "Orientacao MCP-vs-Bash", **When** os dois orquestradores
   sao comparados, **Then** a secao continua byte-identica nos dois arquivos
   (mesma verificacao que existe hoje).

---

### User Story 3 - Medicao de tokens por onda antes e depois, com fonte (Priority: P2)

Como mantenedor, quero um relatorio reproduzivel do consumo por onda antes e
depois, com metodo declarado e cobertura explicita, para provar (ou refutar)
o ganho sem suposicao.

**Why this priority**: o pedido exige medir; sem medicao nao ha como afirmar
ganho. Fica em P2 porque a entrega tecnica (US1/US2) independe dela.

**Independent Test**: rodar o procedimento de medicao sobre a versao anterior
e a nova do repositorio e obter dois conjuntos de numeros com rotulo de fonte.

**Acceptance Scenarios**:

1. **Given** as duas versoes dos orquestradores, **When** o procedimento de
   medicao deterministica roda, **Then** produz, por orquestrador e por fase,
   bytes e tokens do que e carregado (prompt-base + referencia da fase), com o
   metodo de contagem de tokens declarado no proprio relatorio.
2. **Given** ondas reais registradas em knowledge.db/OTel, **When** o relatorio
   consulta o consumo observado por onda, **Then** so reporta numero onde a
   coluna existe para a onda, declara o `n` usado e a cobertura, e NUNCA
   preenche lacuna com valor estimado.
3. **Given** nenhuma fonte observavel de tokens por onda disponivel para o
   periodo "depois", **When** o relatorio e gerado, **Then** ele diz
   "indisponivel" para a medicao observada e mantem so a medicao
   deterministica, sem inventar numero.

---

### User Story 4 - Empacotamento e instalacao das referencias (Priority: P2)

Como usuario do toolkit (instalacao via `cstk install` ou via plugin nativo),
quero que as referencias cheguem junto com os orquestradores e sejam
encontradas em runtime, para que o orquestrador enxuto nunca quebre por falta
de arquivo.

**Why this priority**: uma referencia nao instalada transforma o enxugamento
em regressao silenciosa.

**Independent Test**: instalar em diretorio limpo pelos dois caminhos e
resolver cada caminho de referencia citado nos prompts.

**Acceptance Scenarios**:

1. **Given** instalacao global limpa, **When** cada caminho de referencia
   citado no prompt-base e resolvido, **Then** o arquivo existe.
2. **Given** instalacao pelo plugin nativo (so o subtree `plugins/cstk`),
   **When** o mesmo e feito, **Then** o arquivo existe (as referencias vivem
   dentro do subtree do plugin).
3. **Given** a referencia ausente em runtime, **When** o orquestrador tenta le-la,
   **Then** o prompt-base instrui a NAO prosseguir com a fase e a
   registrar bloqueio humano (nunca improvisar o passo omitido).

---

### Edge Cases

- Uma secao de fase contem literal exigido por teste mas o teste faz grep so
  no `.md` do orquestrador: o teste deve ser migrado para checar prompt-base
  + referencias (nao afrouxado).
- Duas secoes sao byte-identicas por contrato nos dois orquestradores (MCP-vs-
  Bash): permanecem no prompt-base de ambos (rodam em 100% das ondas), ou, se
  movidas, permanecem byte-identicas numa referencia compartilhada unica
  (hoje nao aplicavel — a unica secao byte-identica fica no prompt-base).
- Secao referenciada por outra secao ("ver X abaixo"): links internos
  precisam ser reescritos para apontar a referencia, sem ficar dangling.
- Trecho que so o orquestrador raiz usa vs. que ambos usam: conteudo movivel
  byte-identico nos dois orquestradores viveria em UMA referencia
  compartilhada; sem bloco byte-identico (medido: nenhum), cada orquestrador
  tem suas referencias e a duplicacao restante e apenas por fragmento entre
  arquivos de fase do MESMO orquestrador (SC-006), com teste de
  byte-identidade.
- Fase que ocorre em toda onda (fechamento de onda, checks de aborto,
  budget): nao pode ser movida — o custo de um Read por onda anularia o ganho
  e aumentaria o risco de esquecimento.
- Retomada (`/feature-00c-resume`) no meio de uma fase: a referencia da fase
  corrente deve ser (re)lida na onda retomada, pois o contexto da onda
  anterior nao existe.
- Instalacao anterior (catalogo antigo + orquestrador novo, ou o inverso):
  o orquestrador novo com referencia ausente cai no comportamento seguro de
  bloqueio humano descrito na US4.
- Contagem de tokens indisponivel offline: o relatorio cai para bytes e
  declara isso.
- Identificadores novos (nomes de arquivos de referencia, chaves, funcoes,
  variaveis): todos em ingles, com prosa e comentarios em pt-BR; um nome de
  arquivo de referencia em portugues e rejeitado na revisao.

## Requirements

### Functional Requirements

- **FR-001**: O sistema MUST reduzir o prompt-base de cada um dos dois
  orquestradores movendo secoes especificas de fase (e detalhamentos de
  gates/protocolos usados so em certas fases) para arquivos de referencia
  lidos sob demanda. Uma secao so e movida se (a) NAO roda em 100% das ondas
  e (b) o ganho liquido de tokens da onda, considerando a leitura da
  referencia, e positivo (SC-006); a decisao e tomada secao a secao no plano.
  As referencias sao um arquivo por (orquestrador, fase). Uma referencia
  compartilhada entre os dois orquestradores so existe quando houver bloco
  movivel byte-identico entre eles (medido: nenhum — research Decision 2).
  Conteudo movido que o mesmo orquestrador usa em mais de uma fase e
  duplicado, entre marcadores `FRAGMENT`, nos arquivos de fase desse MESMO
  orquestrador — exigido por SC-006 (no maximo uma leitura por fase) e
  guardado por teste de byte-identidade entre as copias.
- **FR-002**: O sistema MUST manter no prompt-base todo conteudo que governa
  TODAS as ondas (contrato de conclusao de turno, regra de `Schedule intent`,
  fronteira lock/init, principios MUST, anti-padroes, disciplina de output,
  loop principal enxuto, inputs e primitivas operacionais).
- **FR-003**: Para cada secao movida, o prompt-base MUST conter um ponteiro
  explicito indicando (a) a fase/condicao em que a referencia deve ser lida,
  (b) o caminho da referencia, e (c) a instrucao de le-la antes de executar
  os passos da fase.
- **FR-004**: O conteudo movido MUST ser preservado sem alteracao semantica:
  nenhum passo, comando, flag, literal contratual ou regra "REGRA DURA"
  pode ser removido, reescrito ou enfraquecido; alteracoes permitidas se
  limitam a (i) mover o texto, (ii) reescrever referencias internas
  ("ver secao X") para apontarem ao novo local. Em conflito com a meta de
  reducao (FR-018), este requisito e o FR-002 prevalecem: a meta nunca justifica
  remover, reescrever ou enfraquecer conteudo contratual.
- **FR-005**: O sistema MUST manter a pipeline com comportamento identico:
  mesmas etapas, mesma ordem, mesmas Decisoes/bloqueios/skills registrados,
  mesmo fechamento de onda e mesma linha `Schedule intent`.
- **FR-006**: Todo literal contratual hoje verificado por teste nos `.md` dos
  orquestradores MUST continuar verificado: cada teste afetado MUST ser
  migrado para verificar o conjunto (prompt-base + referencias), sem afrouxar
  o padrao verificado, e o conjunto de literais verificados MUST ser
  inventariado antes e depois com igualdade comprovada.
- **FR-007**: A secao "Orientacao MCP-vs-Bash" MUST continuar byte-identica
  nos dois orquestradores (ou, se movida, ser uma unica referencia
  compartilhada citada pelos dois), preservando a verificacao existente.
- **FR-008**: As referencias MUST ser distribuidas pelos dois canais de
  instalacao suportados (instalacao via CLI do toolkit e plugin nativo) e MUST
  residir em local que sobrevive a ambos (dentro do subtree do plugin e como
  parte de um artefato instalavel como diretorio, dado que um agente e
  instalado como arquivo unico); o local escolhido MUST ser decidido no plano
  com base nessa restricao.
- **FR-009**: O caminho de cada referencia citado nos prompts MUST ser
  resolvivel nos dois canais de instalacao, e uma verificacao automatizada
  MUST falhar se qualquer caminho citado nao existir.
- **FR-010**: Se uma referencia exigida pela fase nao puder ser lida em
  runtime, o orquestrador MUST NOT prosseguir com os passos daquela fase de
  memoria e MUST registrar bloqueio humano. Quando a falha ocorre na
  referencia `bootstrap` ANTES de a onda-001 abrir (nenhuma onda aberta), o
  orquestrador MUST NOT chamar `state-ondas.sh start`, MUST registrar Decisao
  (`--classe operacional`) e bloqueio humano (o runtime aceita ambos sem onda
  aberta — verificado em execute-task 1.3) e MUST devolver o turno ao command
  pai sem relatorio de onda e sem `Schedule intent`; a regra geral (nao
  prosseguir de memoria + bloqueio humano) permanece integral.
- **FR-011**: O sistema MUST fornecer um procedimento reproduzivel de medicao
  deterministica que, para cada orquestrador e para cada fase, reporte bytes
  e tokens do que e carregado numa onda (prompt-base + referencias da fase),
  para as versoes anterior e nova, declarando o metodo de contagem de tokens. A meta de reducao (FR-018) e
  avaliada em bytes E em tokens; se a contagem de tokens nao estiver disponivel
  offline, o gate cai para bytes e o relatorio declara essa limitacao.
- **FR-012**: O relatorio de medicao MUST complementar a medicao
  deterministica com o consumo observado por onda (knowledge.db/OTel) quando
  disponivel, MUST declarar `n` de ondas e cobertura por coluna, e MUST NOT
  preencher com valor estimado ou suposto qualquer lacuna; onde nao ha fonte,
  MUST reportar "indisponivel".
- **FR-013**: O baseline "antes" MUST ser capturado a partir do estado do
  repositorio anterior a qualquer edicao dos orquestradores (commit de
  referencia registrado no relatorio) e MUST ser anexado como artefato
  versionado da feature, para que o "depois" seja comparavel.
- **FR-014**: Identificadores, nomes de arquivos, chaves e nomes de funcoes
  novos MUST estar em ingles; prosa e comentarios em pt-BR.
- **FR-015**: Mudancas que alterem contagens documentadas ou fixtures de
  release (contagem de artefatos em documentacao, testes de build de release,
  fixtures regeneraveis) MUST ser detectadas e atualizadas pela feature, e a
  suite completa MUST estar verde ao final.
- **FR-016**: O procedimento MUST incluir uma verificacao de paridade
  comportamental entre versao anterior e nova que nao dependa de julgamento
  manual: inventario de literais contratuais (FR-006) e inventario de blocos
  de comando (invocacoes de scripts do runtime) presentes antes e depois
  entre prompt-base e referencias, com diferenca zero.
- **FR-017**: Se nenhuma fonte observavel de tokens por onda existir para
  sustentar a comparacao, a feature MUST reportar so a medicao
  deterministica e registrar a limitacao, e NUNCA declarar reducao de tokens
  observada. O mesmo vale se a meta de FR-018 so for atingivel violando a
  paridade (FR-002/FR-004): a meta e declarada nao atingida e a limitacao
  registrada, nunca um ganho nao medido.
- **FR-018**: O prompt-base de CADA orquestrador MUST ser reduzido em pelo
  menos 40% em relacao ao baseline (FR-013) para a feature ser considerada
  bem-sucedida. Fonte do valor: resposta humana do operador ao block-001
  (Decisao dec-015, opcao A — 40% em cada orquestrador). Sujeita a precedencia
  da paridade (FR-004/FR-017) e a metrica-gate de FR-011.

### Key Entities

- **Prompt-base**: o arquivo do agente carregado inteiro a cada spawn de onda.
- **Referencia de fase**: arquivo lido sob demanda contendo secoes movidas do
  prompt-base, associado a um par (orquestrador, fase) — um arquivo por par.
  Blocos multi-fase do mesmo orquestrador aparecem como fragmentos
  byte-identicos em mais de um arquivo de fase; a referencia compartilhada
  entre os dois orquestradores so existe se houver bloco byte-identico entre
  eles (hoje nenhum).
- **Inventario contratual**: lista de literais e blocos de comando verificados
  por teste ou exigidos pelo contrato, usada para provar paridade.
- **Relatorio de medicao**: par antes/depois com metodo, fonte, `n` e
  cobertura por metrica.

## Success Criteria

### Measurable Outcomes

- **SC-001**: O prompt-base de cada orquestrador fica pelo menos 40% menor
  (em bytes e em tokens pelo metodo declarado; sem contagem de tokens, gate em
  bytes com limitacao declarada — FR-011) que o baseline de 146014 e 104702
  bytes, respectivamente (meta de FR-018, fonte: resposta humana ao block-001;
  subordinada a paridade — FR-017).
- **SC-002**: 100% dos literais contratuais inventariados antes da feature
  continuam presentes depois (prompt-base ou referencias declaradas), e 100%
  dos testes que os verificam continuam passando; diferenca zero no inventario
  de blocos de comando (FR-016).
- **SC-003**: A suite completa de testes termina verde apos a feature,
  incluindo verificacoes de contagem de documentacao e de release.
- **SC-004**: 100% dos caminhos de referencia citados nos prompts resolvem
  para arquivo existente em instalacao limpa pelos dois canais.
- **SC-005**: O relatorio de medicao traz, para 100% dos numeros de consumo
  observado, a origem da fonte e o `n`; zero numeros sem fonte.
- **SC-006**: Numa onda de fase que exige referencia, o numero de leituras
  extras de referencia por onda e no maximo 1 por fase percorrida (o ganho
  liquido de tokens da onda continua positivo comparado ao baseline).

## Delta Requirements

**Skip**: refactor de organizacao de prompt sem alteracao de comportamento ativo do sistema (FR-005), portanto nao adiciona/muda/remove requisitos do corpus canonico `docs/specs/current/` — orchestrator-slim (feature-00c), 2026-09-29
