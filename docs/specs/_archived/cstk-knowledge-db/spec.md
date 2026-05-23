# Feature Specification: cstk Knowledge DB (memoria cross-feature pesquisavel)

**Feature**: `cstk-knowledge-db`
**Created**: 2026-05-23
**Status**: Draft

## Resumo

Camada **aditiva** de memoria/aprendizado pesquisavel entre features e
projetos. Hoje cada execucao do orquestrador (`agente-00c` / `feature-00c`)
acumula decisoes auditaveis, bloqueios, retros e skills invocadas em um
`state.json` transacional por feria — mas esse conhecimento fica isolado em
silos: nada e reaproveitavel entre features ou entre projetos. Quando uma
nova feature enfrenta um problema ja resolvido (ou repete um bloqueio ja
respondido), o operador nao tem como recuperar esse aprendizado.

Esta feature introduz um indice de conhecimento consultavel que (1) ingere o
conteudo **ja estruturado** do `state.json` ao fim de cada onda e (2) permite
busca full-text cross-projeto/feature com proveniencia completa. A camada e
estritamente **read-only sobre o state transacional**: o `state.json` e os
scripts `state-*.sh` permanecem a unica fonte de verdade transacional, com
lock, sha256 e history intactos. Falha total da camada de conhecimento NUNCA
afeta o caminho critico do orquestrador.

> **Decisoes de infraestrutura**:
> - Backup/restore: o indice de conhecimento e **derivado** e totalmente
>   reconstruivel a partir dos `state.json` / state-history existentes
>   (operacao de reindex). Nao requer backup proprio — a fonte de verdade ja
>   e protegida pelo runtime transacional. Ver FR-014, FR-015.
> - Mutex multi-processo: a camada e gravada por multiplas sessoes/worktrees
>   concorrentes; politica de serializacao e tema de clarificacao (ver
>   FR-016 e Edge Cases). N/A para scheduling (ingestao e disparada por
>   evento de fim-de-onda, nao por cron).
> - Idempotencia: ingestao da mesma onda mais de uma vez NAO duplica
>   registros (FR-007) — chave de proveniencia (projeto+feature+onda+tipo+id)
>   e o discriminador de upsert.

## Clarifications

### Session 2026-05-23

- Q: o escopo do knowledge.db sobrepoe alguma ferramenta de memoria externa ao
  toolkit? → A: **Nao — escopo auto-contido e ortogonal.** knowledge.db indexa
  conhecimento estruturado-de-execucao (decisoes, bloqueios, retros e skills
  invocadas auditaveis, derivados do `state.json` do orquestrador). Nenhuma
  sobreposicao a consolidar com memoria externa; o indice e construido so a
  partir das fontes de verdade do proprio runtime (resolve FR-023).
- Q: Qual modelo de concorrencia adotar para escritas concorrentes ao indice
  global (multiplas `cstk session`/worktrees)? → A: **WAL (`journal_mode=WAL`)
  + `busy_timeout` (~5000ms) com retry/backoff limitado** em "database is
  locked". NAO reaproveitar o lock de arquivo do runtime (acoplaria a camada de
  conhecimento ao lock transacional e poderia estagnar a ingestao sob lock
  prolongado). Sob contencao persistente, a ingestao degrada graciosamente
  (FR-018): emite aviso e pula a ingestao — nunca aborta a onda. A ingestao e
  best-effort aditiva (resolve FR-016).
- Q: Reaproveitar `secrets-filter.sh` na fronteira de ingestao, e em qual
  escopo de campos? → A: **Sim, reusar `secrets-filter.sh scrub`, aplicado
  SOMENTE aos campos de texto livre** (justificativa/contexto/evidencia de
  decisoes; pergunta/contexto-para-resposta de bloqueios; texto de retros). Os
  campos estruturados/enumerados (ids, scores, timestamps, proveniencia,
  nomes de skill) NAO passam pelo filtro — evita mangling de identificadores
  usados como chave de upsert (FR-007) e mantem o filtro confinado a um unico
  arquivo (Principio II) (resolve FR-017).

## User Scenarios & Testing

### User Story 1 - Recuperar aprendizado cross-feature antes de decidir (Priority: P1)

Como operador (ou orquestrador autonomo) prestes a tomar uma decisao em uma
nova feature, quero buscar por palavra-chave decisoes, bloqueios e retros de
features/projetos anteriores, para reaproveitar o que ja foi aprendido em vez
de redescobrir o mesmo caminho.

**Why this priority**: e o valor central da feature — sem recuperacao
consultavel, a ingestao seria escrita sem leitor. Entrega o MVP: mesmo que
nada mais exista, um operador conseguir "lembrar" de um aprendizado anterior
ja justifica a feature.

**Independent Test**: popular o indice com registros de pelo menos dois
projetos/features distintos, executar uma busca por um termo presente em um
deles e confirmar que o resultado retorna o registro correto com a
proveniencia (projeto, feature, onda, data) e nao retorna ruido do outro
projeto quando filtrado.

**Acceptance Scenarios**:

1. **Given** um indice contendo decisoes de duas features distintas, **When**
   o operador busca por um termo que aparece somente na decisao da feature A,
   **Then** o resultado lista essa decisao com sua proveniencia completa
   (projeto, feature/short-name, onda, execucao_id, data) e nao inclui a
   feature B.
2. **Given** registros de tipos diferentes (decisao, bloqueio, retro) que
   casam com o termo buscado, **When** o operador restringe a busca a um tipo,
   **Then** apenas registros daquele tipo sao retornados.
3. **Given** mais resultados do que o limite pedido, **When** o operador
   define um limite, **Then** no maximo aquele numero de resultados e
   retornado, ordenado por relevancia.
4. **Given** um termo sem nenhuma correspondencia, **When** o operador busca,
   **Then** o sistema responde com uma mensagem clara de "nenhum resultado" e
   encerra com sucesso (nao com erro).

---

### User Story 2 - Acumular conhecimento automaticamente ao fim de cada onda (Priority: P1)

Como orquestrador autonomo, quero que o conhecimento estruturado produzido em
uma onda (decisoes, bloqueios, retros, skills invocadas) seja ingerido no
indice ao fim da onda, sem qualquer intervencao manual e sem risco de quebrar
a onda, para que o indice cresca organicamente a cada execucao.

**Why this priority**: sem ingestao automatica, o indice fica vazio ou exige
trabalho manual — a recuperacao (P1) nao teria substrato. A ingestao precisa
ser tao confiavel quanto invisivel: ela e um efeito colateral aditivo do fim
de onda, jamais um gate.

**Independent Test**: executar a ingestao apontando para um `state.json` que
contem decisoes/bloqueios/retros/skills, confirmar que o indice passou a
conter exatamente esses registros com proveniencia; depois executar a mesma
ingestao novamente e confirmar que a contagem de registros nao mudou
(idempotencia).

**Acceptance Scenarios**:

1. **Given** um `state.json` com N decisoes, M bloqueios, K retros e S skills
   invocadas, **When** a ingestao roda ao fim da onda, **Then** o indice passa
   a conter esses N+M+K+S registros com proveniencia correta.
2. **Given** uma onda ja ingerida, **When** a ingestao roda novamente sobre o
   mesmo `state.json`, **Then** nenhum registro e duplicado (a contagem
   permanece estavel).
3. **Given** um `state.json` que ganhou novos registros desde a ultima
   ingestao, **When** a ingestao roda, **Then** apenas os registros novos sao
   adicionados e os antigos nao sao duplicados.
4. **Given** a ingestao em curso, **When** ela termina (com sucesso ou falha),
   **Then** o `state.json` e os artefatos transacionais permanecem
   byte-a-byte inalterados.

---

### User Story 3 - Continuar a onda mesmo quando a camada de conhecimento falha (Priority: P1)

Como orquestrador autonomo, quero que qualquer falha da camada de
conhecimento (ferramenta de armazenamento ausente, indice corrompido, erro de
escrita) seja absorvida graciosamente — registrada como aviso e ignorada — de
modo que a onda do orquestrador jamais seja abortada por causa dela.

**Why this priority**: e a garantia de "zero risco no caminho critico" que
torna a feature aceitavel. Sem degradacao graciosa comprovada, a feature seria
um risco novo introduzido no orquestrador. Esta story protege o invariante
central.

**Independent Test**: simular um ambiente sem a ferramenta de armazenamento
disponivel e executar a ingestao; confirmar que ela emite um aviso e encerra
com sucesso (codigo de saida que o orquestrador trata como nao-fatal), sem
escrever no indice e sem afetar o `state.json`.

**Acceptance Scenarios**:

1. **Given** um ambiente sem a ferramenta de armazenamento instalada, **When**
   a ingestao e invocada, **Then** ela emite um aviso explicativo, nao cria
   nem altera o indice, e encerra de forma que o orquestrador siga a onda
   normalmente.
2. **Given** um indice corrompido/ilegivel, **When** a recuperacao e
   invocada, **Then** o sistema informa o problema e oferece a operacao de
   reconstrucao, sem travar.
3. **Given** o indice foi perdido ou corrompido, **When** o operador solicita
   a reconstrucao, **Then** o indice e recriado a partir dos `state.json` /
   state-history existentes, resultando no mesmo conteudo consultavel que
   havia antes.

---

### User Story 4 - Reconstruir o indice a partir da fonte de verdade (Priority: P2)

Como operador, quero reconstruir o indice de conhecimento do zero a partir dos
estados ja existentes, para recuperar de corrupcao, mudanca de schema do
indice, ou simplesmente popular o indice retroativamente apos adotar a
feature.

**Why this priority**: e a rede de seguranca que torna o indice descartavel.
Reforça a US3 mas tem valor proprio (adocao retroativa). Pode ser entregue
depois do MVP de ingestao+recuperacao.

**Independent Test**: apagar o indice, executar a reconstrucao apontando para
um conjunto de estados existentes e confirmar que uma busca posterior retorna
os mesmos registros que retornaria se cada onda tivesse sido ingerida
incrementalmente.

**Acceptance Scenarios**:

1. **Given** estados de multiplas features/projetos no disco e nenhum indice,
   **When** o operador roda a reconstrucao, **Then** o indice passa a conter
   todos os registros derivaveis desses estados com proveniencia.
2. **Given** um indice ja populado, **When** a reconstrucao roda novamente,
   **Then** o conteudo resultante e equivalente (sem duplicatas) — a
   reconstrucao e idempotente.

---

### Edge Cases

- O que acontece quando **multiplas sessoes/worktrees** (ex: `cstk session`)
  terminam ondas quase simultaneamente e tentam ingerir no mesmo indice
  global? A escrita concorrente nao pode corromper o indice nem perder
  registros. (Ver FR-016 e Clarification 2.)
- Como o sistema lida com um `state.json` **parcial ou em estado nao-terminal**
  (onda interrompida)? A ingestao deve processar apenas os registros ja
  estruturados e presentes, sem assumir completude.
- O que acontece quando um registro do `state.json` contem **dados sensiveis**
  (segredos, paths internos)? O conteudo persistido no indice nao deve vazar
  segredos. (Ver FR-017 e Clarification 3.)
- Como o sistema se comporta quando o diretorio do indice **nao existe** ou
  nao e gravavel? Deve criar o diretorio quando possivel; quando nao, degradar
  graciosamente (US3).
- O que acontece quando a busca usa **caracteres especiais** da sintaxe de
  full-text (aspas, operadores)? A consulta nao deve falhar com erro de
  sintaxe — entrada do usuario e tratada de forma segura.
- Como distinguir registros de mesma proveniencia que mudaram entre ondas
  (ex: um bloqueio que foi respondido)? O upsert deve refletir o estado mais
  recente sem criar duplicata.

## Requirements

### Functional Requirements

#### Indice e proveniencia

- **FR-001**: O sistema MUST manter um indice de conhecimento **global ao
  usuario** (compartilhado entre todos os projetos/features daquele usuario),
  localizado em area de configuracao do usuario e criado automaticamente
  quando ausente.
- **FR-002**: O sistema MUST armazenar quatro classes de conhecimento
  derivadas do `state.json`: **decisoes**, **bloqueios**, **retros** e
  **skills invocadas**.
- **FR-003**: Cada registro armazenado MUST carregar **proveniencia completa**:
  projeto de origem, feature/short-name, identificador da onda, execucao_id e
  timestamp de origem.
- **FR-004**: O sistema MUST suportar **busca full-text** sobre o conteudo
  textual dos registros (contexto/justificativa de decisoes, pergunta/resposta
  de bloqueios, texto de retros, nome de skills).

#### Ingestao

- **FR-005**: O sistema MUST oferecer uma operacao de ingestao que extrai de um
  `state.json` os campos **ja estruturados** — `decisoes[]`,
  `bloqueios_humanos[]`, `retro`, `ondas[].skills_invoked[]` — e os grava no
  indice com proveniencia.
- **FR-006**: A ingestao MUST ser invocavel ao fim de cada onda pelo
  orquestrador (efeito colateral aditivo do fechamento de onda).
- **FR-007**: A ingestao MUST ser **idempotente**: reingerir a mesma onda nao
  cria registros duplicados. O discriminador de identidade e a tupla de
  proveniencia (projeto + feature + onda + tipo + id do registro).
- **FR-008**: A ingestao MUST refletir a versao **mais recente** de um registro
  quando ele mudou entre ingestoes da mesma proveniencia (upsert, nao
  insert-only).
- **FR-009**: A ingestao MUST **nunca modificar** o `state.json` nem qualquer
  artefato transacional (`state-*.sh`, lock, sha256, history) — somente leitura
  da fonte.

#### Recuperacao

- **FR-010**: O sistema MUST oferecer um comando de recuperacao que aceita uma
  consulta textual e retorna registros relevantes cross-projeto/cross-feature,
  ordenados por relevancia.
- **FR-011**: Cada resultado de recuperacao MUST exibir a proveniencia do
  registro (projeto, feature, onda, data) junto ao conteudo.
- **FR-012**: A recuperacao MUST suportar filtros por **projeto**, por **tipo**
  de registro (decisao | bloqueio | retro) e por **limite** de resultados.
- **FR-013**: A recuperacao MUST tratar consulta sem resultados como sucesso
  (mensagem de "nenhum resultado"), nao como erro.

#### Resiliencia e reconstrucao

- **FR-014**: O sistema MUST oferecer uma operacao de **reconstrucao**
  (reindex) que recria o indice a partir dos `state.json` / state-history
  existentes.
- **FR-015**: A reconstrucao MUST ser idempotente e produzir conteudo
  equivalente ao que a ingestao incremental produziria.
- **FR-016**: O sistema MUST garantir que escritas concorrentes ao indice
  global (multiplas sessoes/worktrees) nao corrompam o indice nem percam
  registros. O modelo de concorrencia MUST ser **journaling write-ahead
  (`journal_mode=WAL`) combinado com `busy_timeout` (~5000ms) e retry/backoff
  limitado** ao encontrar "database is locked". O sistema MUST NOT reaproveitar
  o lock de arquivo do runtime transacional para esse fim (evita acoplamento ao
  lock transacional e estagnacao da ingestao sob lock prolongado). Sob contencao
  persistente alem do retry/backoff, a ingestao MUST degradar graciosamente
  (FR-018): emitir aviso e pular a ingestao da onda, jamais abortar a onda — a
  ingestao e best-effort aditiva.

#### Degradacao graciosa (invariante de seguranca operacional)

- **FR-018**: A ausencia da ferramenta de armazenamento OU qualquer falha de
  ingestao MUST resultar em degradacao graciosa — registro de aviso e
  continuacao — e MUST NUNCA abortar ou bloquear uma onda do orquestrador.
- **FR-019**: O comportamento de degradacao graciosa (ausencia de dependencia,
  indice corrompido, falha de escrita) MUST ser coberto por teste
  automatizado.

#### Privacidade (Principio IV — zero coleta remota)

- **FR-017**: O conteudo persistido no indice MUST permanecer estritamente
  local ao ambiente do usuario; nenhum dado e transmitido para fora. Conteudo
  textual sensivel MUST ser tratado antes de persistir, reaproveitando o filtro
  de segredos existente do runtime (`secrets-filter.sh scrub`) na fronteira de
  ingestao. O filtro MUST ser aplicado **somente aos campos de texto livre** —
  justificativa/contexto/evidencia de decisoes, pergunta/contexto-para-resposta
  de bloqueios e texto de retros. Campos estruturados/enumerados (ids, scores,
  timestamps, proveniencia — projeto/feature/onda/execucao_id — e nomes de
  skill) MUST NOT passar pelo filtro, para nao corromper identificadores usados
  como chave de upsert (FR-007). A integracao com `secrets-filter.sh` MUST
  permanecer confinada a um unico arquivo (Principio II / FR-020).

#### Conformidade constitucional (restricoes que governam o COMO no /plan)

- **FR-020**: Toda dependencia nao-POSIX necessaria (ferramenta de
  armazenamento full-text; processador JSON) MUST entrar pela carve-out de
  **deps opcionais** da constituicao (Principio II, amendment 1.1.0),
  satisfazendo cumulativamente: (a) fallback graceful testado, (b) referencias
  a cada dep confinadas a um unico arquivo identificavel, (c) dep declarada com
  justificativa, caminho do arquivo e descricao do fallback no `plan.md`.
- **FR-021**: Todo script entregue MUST ser POSIX sh puro (shebang `#!/bin/sh`,
  `set -eu`, sem bash-isms), com codigo/identificadores em ingles e
  comentarios/mensagens admitindo pt-br.
- **FR-022**: Cada novo script MUST ter teste automatizado correspondente
  segundo a convencao do repo (script em `cli/lib/` mapeia para
  `tests/cstk/test_<nome>.sh`; script em `global/skills/*/scripts/` mapeia para
  `tests/test_<nome>.sh`), de modo que a verificacao de cobertura do repo nao
  acuse orfaos. Fixtures de bytes crus em testes usam escapes octais `\NNN`.

#### Escopo auto-contido (sem interop com memoria externa)

- **FR-023**: O knowledge.db tem **escopo auto-contido**: indexa conhecimento
  estruturado-de-execucao (decisoes, bloqueios, retros e skills invocadas
  auditaveis derivados do `state.json` do orquestrador). A feature MUST NOT
  depender de, importar de, substituir ou interoperar com qualquer ferramenta
  de memoria externa ao toolkit; o indice e construido exclusivamente a partir
  das fontes de verdade do proprio runtime.

### Key Entities

- **KnowledgeRecord**: uma unidade de conhecimento recuperavel. Atributos
  conceituais: tipo (decisao | bloqueio | retro | skill), conteudo textual
  pesquisavel, e a proveniencia. Identidade derivada da tupla de proveniencia +
  tipo + id de origem (base da idempotencia).
- **Provenance**: origem de um registro — projeto, feature/short-name,
  identificador da onda, execucao_id, timestamp. Atravessa todos os registros e
  e exibida em toda recuperacao.
- **KnowledgeIndex**: o repositorio global, derivado e reconstruivel, que
  agrega KnowledgeRecords de todas as features/projetos do usuario e suporta
  busca full-text. Nao e fonte de verdade — e um indice secundario sobre os
  `state.json`.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Apos uma feature completar suas ondas, 100% das decisoes,
  bloqueios, retros e skills estruturadas presentes no `state.json` final
  ficam recuperaveis por busca no indice.
- **SC-002**: Reingerir a mesma onda qualquer numero de vezes nao altera a
  contagem de registros no indice (zero duplicatas).
- **SC-003**: Em 100% dos cenarios de falha da camada de conhecimento
  (dependencia ausente, indice corrompido, escrita falha), a onda do
  orquestrador conclui sem aborto causado pela camada.
- **SC-004**: Uma busca por termo presente recupera o registro correto com
  proveniencia completa, e busca filtrada por projeto/tipo exclui registros que
  nao casam com o filtro em 100% dos casos testados.
- **SC-005**: Apos apagar o indice e reconstrui-lo a partir dos estados
  existentes, uma mesma consulta retorna o mesmo conjunto de registros que
  retornava antes (conteudo equivalente, sem duplicatas).
- **SC-006**: O `state.json` e demais artefatos transacionais permanecem
  byte-a-byte inalterados em 100% das execucoes de ingestao e reconstrucao
  (verificavel por hash antes/depois).
- **SC-007**: Zero scripts novos sem teste correspondente (a verificacao de
  cobertura do repo passa sem orfaos).
