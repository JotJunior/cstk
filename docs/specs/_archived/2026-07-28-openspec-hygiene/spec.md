# Feature Specification: Higiene OpenSpec — Gate de Cenarios, Guia de Triagem, Archive Datado, Envelope Diagnostico

**Feature**: `openspec-hygiene`
**Created**: 2026-07-23
**Status**: Draft

## Visão geral

Benchmark do concorrente [OpenSpec](https://github.com/Fission-AI/OpenSpec)
(Fission-AI, estudado 2026-07-23 — ver `reference-openspec-benchmark`)
identificou quatro praticas de higiene documental baratas e independentes
entre si, que o toolkit ainda nao pratica: (1) um gate deterministico que
garante que todo requisito funcional tenha ao menos um cenario de teste
associado — o equivalente a "unit tests para requisitos" que o `checklist`
ja faz para qualidade de linguagem, mas nao para cobertura estrutural; (2)
um formato uniforme de diagnostico de erro nos scripts POSIX do toolkit,
com um campo explicito de proximo passo acionavel; (3) uma convencao de
nomenclatura para diretorios arquivados que embute a data de arquivamento,
permitindo ordenacao cronologica sem abrir cada diretorio; e (4) uma
orientacao explicita, dentro das skills `specify`/`clarify`, para decidir
entre atualizar uma spec existente ou abrir uma feature nova, evitando
tanto duplicacao de features quanto inchaco de escopo de uma spec ja
ratificada.

O item estrutural mais caro do benchmark (specs vivas + delta specs
mergeadas no archive, substituindo o `docs/specs/_archived/` atual como
sepultura de conhecimento) e explicitamente **fora de escopo** desta
feature — sera tratado como feature separada, por ter esforco e impacto
arquitetural muito maiores que os quatro itens aqui tratados.

> **Decisões de infraestrutura**: N/A — nenhum dos quatro itens introduz
> scheduling, sessao persistente, refresh de token externo, rotacao de
> chaves ou mutex multi-processo. Todos os mecanismos sao deterministicos,
> sincronos e invocados sob demanda (pelas skills `specify`/`checklist`/
> `clarify`, ou pelo operador/agente executando a acao manual de
> arquivamento descrita em `review-features`).

## Clarifications

### Session 2026-07-23

- Q: FR-005 — qual mecanismo de rastreabilidade liga um Functional
  Requirement ao(s) seu(s) cenario(s): referencia explicita de ID
  inserida no texto do cenario (exige ajuste no template
  `feature-spec.md`), ou correspondencia heuristica textual entre o
  enunciado do requisito e os cenarios/Edge Cases ja existentes (sem
  exigir mudanca de template)? → A: correspondencia heuristica
  textual, sem exigir citacao literal do ID do requisito no texto do
  cenario e sem mudanca no template `feature-spec.md`. Motivo:
  nenhuma das specs existentes do repositorio cita FR-IDs dentro de
  blocos Given/When/Then, e o template atual nao tem essa convencao;
  exigir citacao explicita forcaria retrofit de todo o portfolio de
  specs e uma mudanca de template, contradizendo o proprio Edge Case
  desta spec ("a spec precisa ganhar os cenarios faltantes" — nao
  "citar IDs").

## User Scenarios & Testing

### User Story 1 - Bloquear specs com requisito funcional sem cenario associado (Priority: P1)

Como autor de uma spec (operador humano ou agente autonomo rodando
`specify`/`checklist`), quero que um gate deterministico verifique que
cada Functional Requirement da spec tem ao menos um cenario de teste
(Acceptance Scenario ou Edge Case) associado, e que a execucao falhe com
uma mensagem acionavel apontando exatamente qual requisito esta sem
cobertura, para eu nao avancar para `/plan`/`/create-tasks` com um
requisito que ninguem sabe como validar.

**Why this priority**: e o item de maior valor estrutural dos quatro —
fecha uma lacuna real do pipeline SDD atual (`checklist` valida qualidade
de linguagem dos requisitos, mas nada valida hoje que cada requisito
tenha cobertura de teste minima). Entrega valor sozinho, independente dos
outros tres itens.

**Independent Test**: apresentar ao gate uma spec com um Functional
Requirement sem nenhum cenario associado e confirmar que a execucao falha
citando exatamente esse requisito; apresentar uma spec onde todo
requisito tem cobertura e confirmar que o gate passa sem achados.

**Acceptance Scenarios**:

1. **Given** um `spec.md` cujo `FR-003` nao tem nenhum cenario associado
   em nenhuma Acceptance Scenario nem Edge Case da spec, **When** o gate
   roda (invocado pela validacao interna de `specify` ou por `checklist`),
   **Then** a execucao falha reportando "FR-003 sem cenario associado" e
   uma sugestao de correcao concreta (ex.: adicionar um cenario que
   referencie `FR-003`).
2. **Given** um `spec.md` onde todo Functional Requirement tem ao menos um
   cenario associado, **When** o gate roda, **Then** ele passa com zero
   achados.
3. **Given** um `spec.md` que nao declara nenhum Functional Requirement
   (caso degenerado), **When** o gate roda, **Then** ele passa trivialmente
   (nao ha requisito para falhar).

---

### User Story 2 - Orientar "atualizar spec existente vs abrir feature nova" em specify/clarify (Priority: P2)

Como operador que traz um novo pedido para `specify`/`clarify`, quero que
a skill me ajude a decidir, antes de criar qualquer artefato, se este
pedido e um refinamento de uma feature ja especificada (intencao igual ou
apenas mais detalhada — atualizar a spec existente) ou se muda de
intencao/expande o escopo original (abrir uma feature nova), para eu nao
duplicar uma feature nem inchar uma spec ja ratificada com escopo que ela
nunca pediu.

**Why this priority**: previne drift estrutural do portfolio de specs com
esforco medio; independente dos outros tres itens, mas depende de haver
specs existentes para comparar (por isso P2, nao P1 — sem gate de
cobertura minima o valor de uma boa triagem cai).

**Independent Test**: apresentar a `specify` um pedido que refina uma spec
ja existente (mesmos atores/objetivo, apenas mais detalhe) e confirmar que
a orientacao aponta para atualizar a spec existente citando o criterio
aplicado; apresentar um pedido cujo escopo diverge claramente da intencao
original de qualquer spec existente e confirmar que a orientacao aponta
para nova feature.

**Acceptance Scenarios**:

1. **Given** um `spec.md` existente cuja intencao original bate com o novo
   pedido (mesmos atores/objetivo, pedido apenas refina ou detalha),
   **When** `specify`/`clarify` e invocada, **Then** a orientacao aponta
   para atualizar o `spec.md` existente, citando o criterio aplicado
   (mesma intencao/refinamento).
2. **Given** um novo pedido cujo escopo expandiu alem da intencao original
   de qualquer spec existente (novos atores, capacidade nao relacionada ao
   objetivo original), **When** `specify`/`clarify` e invocada, **Then** a
   orientacao aponta para criar uma feature nova via `specify`, citando o
   criterio aplicado (intencao mudou/escopo explodiu).
3. **Given** nenhuma spec existente se relaciona ao pedido, **When**
   `specify` e invocada, **Then** a orientacao segue direto para criacao
   de nova feature, sem overhead de decisao (sem falso-positivo quando nao
   ha nada para comparar).

---

### User Story 3 - Prefixo de data no archive de novas features (Priority: P3)

Como operador que arquiva uma feature concluida ou abandonada (acao
manual, hoje documentada em `review-features`), quero que o diretorio de
destino carregue um prefixo de data de arquivamento (`YYYY-MM-DD`), para
que features arquivadas ao longo do tempo fiquem ordenadas
cronologicamente sem precisar abrir cada diretorio.

**Why this priority**: ganho organizacional barato e de baixo risco, mas
sem urgencia — nao bloqueia nenhum fluxo hoje. Independente dos outros tres
itens.

**Independent Test**: arquivar duas features em datas diferentes e
confirmar que os diretorios resultantes ordenam alfabeticamente na mesma
ordem das datas de arquivamento; confirmar que diretorios ja arquivados
antes desta feature permanecem com o nome antigo, sem migracao.

**Acceptance Scenarios**:

1. **Given** uma feature `foo-bar` pronta para ser arquivada hoje, **When**
   a acao de arquivamento e executada (conforme o passo ja documentado em
   `review-features`), **Then** o diretorio resultante e
   `docs/specs/_archived/<data-de-hoje>-foo-bar/`.
2. **Given** diretorios ja existentes sob `docs/specs/_archived/` sem
   prefixo de data (arquivados antes desta feature), **When** esta feature
   entra em vigor, **Then** nenhum desses diretorios e renomeado ou
   movido.
3. **Given** duas features arquivadas em datas diferentes, **When** ambos
   diretorios existem sob `_archived/`, **Then** a listagem ordenada
   alfabeticamente do diretorio produz a mesma ordem das datas de
   arquivamento.

---

### User Story 4 - Envelope diagnostico uniforme nos helpers POSIX (Priority: P4)

Como desenvolvedor ou agente que invoca um script auxiliar POSIX do
toolkit e recebe uma falha, quero que a saida de erro traga campos
estruturados de severidade, codigo, mensagem e proximo passo acionavel,
para eu (ou um orquestrador consumindo a saida) saber imediatamente o que
aconteceu, quao serio e, e o que fazer a seguir — sem reler o codigo-fonte
do script nem adivinhar.

**Why this priority**: mecanico e de valor real, mas com superficie ampla
(dezenas de call-sites entre `cli/lib/*.sh` e
`global/skills/agente-00c-runtime/scripts/*.sh`) e risco de quebrar
mensagens que testes existentes ja verificam literalmente — por isso e o
ultimo priorizado dos quatro, com escopo de migracao explicitamente
aditivo (nao um rewrite de tudo de uma vez).

**Independent Test**: invocar um script auxiliar em escopo sob uma
condicao de falha conhecida e confirmar que a saida de erro traz os
quatro campos, e que o campo de proximo passo e uma instrucao acionavel
distinta da mensagem.

**Acceptance Scenarios**:

1. **Given** um script POSIX auxiliar em escopo falha uma validacao,
   **When** ele encerra com exit code diferente de zero, **Then** sua
   saida de diagnostico (stderr) inclui severidade, um codigo estavel,
   uma mensagem legivel por humano e uma instrucao de proximo passo.
2. **Given** duas condicoes de falha distintas no mesmo script, **When**
   cada uma ocorre, **Then** cada uma tem um codigo distinto,
   diferenciavel programaticamente (por um orquestrador, por exemplo) sem
   precisar interpretar texto livre.
3. **Given** um script auxiliar fora do escopo definido durante o
   planejamento desta feature (ex.: script legado nao migrado nesta
   rodada), **When** ele falha, **Then** seu formato de erro atual
   permanece inalterado — a migracao e aditiva e com escopo explicito, nao
   um rewrite geral de todos os scripts numa unica passada.

---

### Edge Cases

- O que acontece quando a spec nao declara nenhum Functional Requirement?
  O gate da User Story 1 passa trivialmente (ver Acceptance Scenario 3).
- O que acontece quando `checklist`/`specify` roda sobre uma spec **ja
  existente**, escrita antes desta feature, que tem requisitos sem
  cenario? O gate se aplica igualmente — nao ha excecao retroativa; a
  spec precisa ganhar os cenarios faltantes para passar na proxima
  execucao do gate.
- O que acontece quando um pedido novo nao se relaciona com nenhuma spec
  existente? A triagem da User Story 2 segue direto para nova feature, sem
  falso-positivo de "atualizar existente" (ver Acceptance Scenario 3).
- O que acontece com os diretorios ja arquivados sob `docs/specs/_archived/`
  sem prefixo de data? Permanecem para sempre sem o prefixo — convivendo
  lado a lado com os novos diretorios datados; nenhuma migracao
  retroativa e feita por esta feature (risco explicito de quebrar links em
  `CLAUDE.md`, memorias e specs existentes).
- O que acontece quando um script fora do escopo de migracao do envelope
  diagnostico falha? Mantem seu formato de erro atual — a User Story 4 e
  estritamente aditiva, escopo exato definido em `/plan`.
- O que acontece quando o mesmo script falha por duas causas simultaneas
  (ex.: uso incorreto **e** arquivo de entrada ausente)? O envelope
  diagnostico reporta apenas o primeiro erro fatal encontrado — consistente
  com a disciplina fail-fast (`set -eu`) ja exigida pelo Principio II da
  constitution; nao ha agregacao de multiplos achados numa unica
  invocacao.

## Requirements

### Functional Requirements

- **FR-001**: O sistema MUST prover um script deterministico (POSIX sh)
  que, dado um `spec.md`, verifica se cada Functional Requirement listado
  possui ao menos um cenario associado (Acceptance Scenario ou Edge Case).
- **FR-002**: O gate da FR-001 MUST ser invocado automaticamente pela
  skill `specify` (etapa de validacao) e pela skill `checklist`, antes de
  qualquer uma delas reportar conclusao bem-sucedida.
- **FR-003**: Quando um Functional Requirement nao tem cenario associado,
  o gate MUST falhar reportando o ID exato do requisito e uma mensagem
  acionavel de correcao (ex.: adicionar um cenario que referencie aquele
  requisito).
- **FR-004**: O gate MUST passar com zero achados quando a spec nao
  declara nenhum Functional Requirement, ou quando todo Functional
  Requirement tem ao menos um cenario associado.
- **FR-005**: O gate da FR-001 MUST determinar a associacao entre um
  Functional Requirement e seus cenarios por correspondencia
  heuristica textual — comparando termos-chave (substantivos/verbos
  centrais) do enunciado do requisito contra o texto dos Acceptance
  Scenarios e Edge Cases da mesma spec — sem exigir que o cenario cite
  o ID do requisito literalmente, e MUST NOT exigir qualquer mudanca
  no template `feature-spec.md` para funcionar sobre specs ja
  existentes (ver Clarifications, Session 2026-07-23).
- **FR-006**: A skill `specify` MUST incluir, antes da criacao de uma nova
  spec, uma etapa de triagem que avalia se o pedido refina/mantem a
  intencao de uma feature ja especificada (recomendando atualizar a spec
  existente) ou se muda de intencao ou expande o escopo original
  (recomendando nova feature), citando o criterio aplicado na
  recomendacao.
- **FR-007**: A skill `clarify` MUST aplicar o mesmo criterio de triagem
  da FR-006 quando o pedido levantado pelo operador durante a
  clarificacao poderia, de fato, constituir uma feature nova em vez de uma
  clarificacao da spec corrente.
- **FR-008**: Quando nenhuma spec existente se relaciona ao pedido, a
  triagem das FR-006/FR-007 MUST prosseguir direto para a criacao de nova
  feature, sem overhead de decisao adicional.
- **FR-009**: Toda feature arquivada a partir da entrada em vigor desta
  feature MUST ser movida para
  `docs/specs/_archived/<YYYY-MM-DD>-<feature>/`, usando a data em que a
  acao de arquivamento de fato ocorre (nao a data de criacao da feature).
- **FR-010**: Diretorios ja existentes sob `docs/specs/_archived/` sem
  prefixo de data MUST permanecer inalterados — esta feature MUST NOT
  renomear, mover ou de outra forma migrar conteudo ja arquivado.
- **FR-011**: A documentacao da acao de arquivamento (skill
  `review-features`, secao que descreve o passo manual "mover para
  `_archived/`") MUST ser atualizada para refletir a nova convencao de
  nomenclatura com prefixo de data.
- **FR-012**: Scripts POSIX no escopo determinado pelo plano desta feature
  MUST emitir diagnosticos de falha em formato estruturado contendo os
  campos severity, code, message e fix.
- **FR-013**: O campo `fix` do envelope diagnostico (FR-012) MUST ser uma
  instrucao acionavel de proximo passo — MUST NOT ser uma repeticao do
  campo `message`.
- **FR-014**: Cada combinacao (script, condicao de falha especifica) MUST
  ter um `code` estavel e distinguivel programaticamente, sem exigir
  parsing de texto livre por quem consome a saida.
- **FR-015**: Scripts fora do escopo de migracao definido pelo plano desta
  feature MUST manter seu formato de erro atual inalterado — a migracao e
  aditiva, MUST NOT ser um rewrite geral de todos os scripts numa unica
  rodada.
- **FR-016**: O formato do envelope diagnostico (FR-012) MUST permanecer
  compativel com o Principio II da constitution (POSIX sh puro) — MUST NOT
  exigir `jq` ou outra ferramenta nao-POSIX como dependencia obrigatoria
  para EMITIR o envelope.
- **FR-017**: Todo script `.sh` novo introduzido por esta feature (em
  `global/skills/*/scripts/` ou `cli/lib/`) MUST ter teste automatizado
  correspondente em `tests/` ou `tests/cstk/`, conforme a convencao ja
  documentada no `CLAUDE.md` do projeto, sob pena de falhar
  `tests/run.sh --check-coverage`.

### Key Entities

- **RequirementScenarioGap**: um Functional Requirement sem nenhum cenario
  associado, encontrado pelo gate da User Story 1. Atributos: ID do
  requisito, path da spec, mensagem de correcao sugerida.
- **DiagnosticEnvelope**: registro estruturado emitido por um script
  auxiliar POSIX ao falhar. Campos: `severity`, `code`, `message`, `fix`.
- **ArchivedFeatureEntry**: um diretorio de feature movido para
  `docs/specs/_archived/` com prefixo de data explicito de quando o
  arquivamento ocorreu (aplica-se apenas a arquivamentos feitos apos esta
  feature entrar em vigor).

## Success Criteria

### Measurable Outcomes

- **SC-001**: 100% das specs que passam pelo gate de `checklist` (apos
  esta feature entrar em vigor) tem cada Functional Requirement
  referenciado por ao menos um cenario, verificavel automaticamente sem
  revisao manual.
- **SC-002**: Ao falhar o gate da User Story 1, o autor identifica o
  requisito exato sem cobertura e a acao corretiva necessaria lendo apenas
  a mensagem de erro reportada — sem precisar abrir o codigo-fonte do
  script de validacao.
- **SC-003**: 100% dos diretorios de feature arquivados apos esta feature
  entrar em vigor carregam prefixo de data no nome; 100% dos diretorios
  arquivados antes permanecem sem alteracao de nome.
- **SC-004**: Um operador aplicando a orientacao de triagem de
  `specify`/`clarify` decide entre "atualizar spec existente" e "nova
  feature" citando o criterio usado, sem pesquisa externa, em ambos os
  casos canonicos (refinamento de intencao e mudanca/expansao de escopo).
- **SC-005**: 100% dos scripts POSIX definidos em escopo pelo plano desta
  feature emitem os quatro campos do envelope diagnostico em toda saida
  de falha, verificavel por checagem automatizada.
- **SC-006**: Nenhum script fora do escopo de migracao desta feature tem
  seu formato de saida de erro alterado — zero regressao observavel em
  testes automatizados existentes para scripts fora de escopo.

## Delta Requirements

**Skip**: corpus docs/specs/current/ inexistente no momento do arquivamento (primeiro ciclo pos living-specs); backfill de capabilities historicas deferido pelo operador (living-specs 6.4.1/6.4.2); comportamento corrente documentado em CLAUDE.md/README — operador via review-features, 2026-07-28
