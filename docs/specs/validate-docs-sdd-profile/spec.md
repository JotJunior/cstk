# Feature Specification: validate-docs-sdd-profile

**Feature**: `validate-docs-sdd-profile`
**Created**: 2026-07-10
**Status**: Draft

## Visao geral

A skill `validate-documentation` hoje conhece apenas dois perfis de artefato:
o perfil UC (default, casos de uso `UC-*.md`) e o perfil `--runbook`
(`RB-\d{3}-*.md`). Nenhum dos dois cobre os artefatos gerados pelo proprio
pipeline SDD deste toolkit — `spec.md` (gerado por `specify`) nem a familia de
artefatos gerados por `plan` (`plan.md`, `research.md`, `data-model.md`,
`quickstart.md`, `contracts/*.md`). Como resultado, quando um orquestrador
(`agente-00c`/`feature-00c`) ou um operador precisa checar a qualidade
estrutural de um `spec.md` ou de um `plan.md` isolado, a unica opcao hoje e
grep ad-hoc — sem checklist nativo, sem relatorio consistente com o resto da
skill, sem reuso dos criterios de qualidade que ja estao documentados na
prosa de `specify` e `plan`.

Esta feature adiciona dois novos perfis a `validate-documentation` —
spec-profile e plan-profile — que aplicam, de forma nativa e reusavel, os
criterios de qualidade que `specify` e `plan` ja definem para seus proprios
artefatos (ausencia de detalhes de implementacao, success criteria
mensuraveis, limite de `[NEEDS CLARIFICATION]`, rotulagem de contrato
real-vs-proposto, ausencia de placeholders de template). Os dois perfis
novos NAO substituem nem duplicam `analyze` (consistencia cross-artifact
profunda) nem `validate-docs-rendered` (validacao de renderizacao) — cobrem
exclusivamente a qualidade estrutural de UM artefato isolado, no mesmo
espirito dos perfis UC e `--runbook` ja existentes.

> Decisoes de infraestrutura: **N/A** — a feature nao introduz scheduling,
> sessao persistente, refresh de token externo, rotacao de chaves ou mutex
> multi-processo. E uma extensao de checklist de validacao textual, sincrona
> e local.

## Clarifications

### Session 2026-07-10

- Q: O plan-profile deve incluir uma checagem de que links internos entre
  artefatos da familia `/plan` (ex.: `plan.md` referenciando
  `contracts/algo.md`) apontam para arquivos existentes, ou essa
  responsabilidade fica 100% com `validate-docs-rendered`? → A: fica 100%
  delegada a `validate-docs-rendered` (secao 2.2 "Links internos" do seu
  SKILL.md ja verifica que o arquivo apontado existe e que o anchor
  corresponde a um header valido, com severidade erro para quebrados). O
  plan-profile NAO faz resolucao de link/anchor no disco; sua unica
  checagem de referencia cruzada e semantica — validar que IDs `FR-`/`SC-`
  citados em `plan.md` existem de fato na `spec.md` correspondente
  (ja coberto por FR-012), nao que um path aponta para um arquivo real.

## User Scenarios & Testing

### User Story 1 - Validar um spec.md isolado contra checklist nativo (Priority: P1)

Como orquestrador (`agente-00c`/`feature-00c`) ou operador, eu quero validar
um `spec.md` recem-gerado contra um checklist nativo da skill
`validate-documentation` — que reaproveita os criterios ja documentados em
`specify` (zero detalhes de implementacao, success criteria mensuraveis e
tech-agnostic, no maximo 3 `[NEEDS CLARIFICATION]`, secoes obrigatorias
presentes) — em vez de depender de grep ad-hoc escrito na hora, para que a
qualidade estrutural de um `spec.md` seja checada de forma consistente e
auditavel antes de avancar para `clarify`/`plan`.

**Why this priority**: e o artefato mais cedo no pipeline SDD (gerado por
`specify`, primeira etapa apos briefing/constitution) e o que hoje sofre mais
com a ausencia de checklist nativo — o gap descrito na Visao Geral. Sem esta
story, as demais nao tem MVP: e o caso de uso mais frequente.

**Independent Test**: rodar a validacao contra um `spec.md` conhecido (ex.:
`docs/specs/enforced-guards/spec.md`, ja existente no projeto) e confirmar
que o relatorio gerado aponta zero erros estruturais; em seguida rodar contra
uma copia deliberadamente quebrada (uma secao obrigatoria removida, um jargao
tecnico inserido em Success Criteria, um quarto marcador
`[NEEDS CLARIFICATION]` adicionado) e confirmar que cada quebra e detectada e
classificada com a severidade correta. Testavel isoladamente de US2 e US3.

**Acceptance Scenarios**:

1. **Given** um `spec.md` com as tres secoes obrigatorias presentes
   (`User Scenarios & Testing`, `Requirements`, `Success Criteria`) e
   conteudo consistente com os criterios de `specify`, **When** a validacao
   roda com o spec-profile, **Then** o relatorio reporta zero erros.
2. **Given** um `spec.md` faltando uma secao obrigatoria, **When** a
   validacao roda, **Then** o relatorio reporta um erro (bloqueante)
   identificando a secao ausente.
3. **Given** um `spec.md` com mais de 3 marcadores
   `[NEEDS CLARIFICATION]`, **When** a validacao roda, **Then** o relatorio
   reporta um erro citando a contagem encontrada e o limite excedido.
4. **Given** um `spec.md` com uma Success Criteria redigida em termos
   tecnicos (ex.: menciona um framework ou tempo de resposta de API em vez
   de uma metrica orientada ao usuario), **When** a validacao roda,
   **Then** o relatorio reporta um erro apontando o anti-padrao.

---

### User Story 2 - Validar artefatos da familia /plan contra checklist nativo (Priority: P2)

Como orquestrador ou operador, eu quero validar `plan.md` e os artefatos
associados (`research.md`, `data-model.md`, `quickstart.md`,
`contracts/*.md`) contra um checklist nativo que reaproveita os criterios ja
documentados em `plan` (secoes obrigatorias presentes, rotulagem explicita
de contrato real-vs-proposto, referencias a FR/SC que de fato existem na
spec correspondente, ausencia de placeholder de template residual), para que
a qualidade estrutural de um plano tecnico seja checada de forma consistente
antes de avancar para `create-tasks`.

**Why this priority**: depende do mesmo mecanismo de perfil que US1
introduz, mas atua na etapa seguinte do pipeline (`plan`) — tem valor
proprio e independente (um operador pode rodar `/plan` sem nunca ter usado
o novo perfil de US1), mas naturalmente vem depois porque `plan.md` so
existe apos `spec.md`.

**Independent Test**: rodar a validacao contra os artefatos de
`docs/specs/enforced-guards/` (`plan.md`, `research.md`, `data-model.md`,
`quickstart.md`, `contracts/`), ja existentes no projeto, e confirmar
relatorio limpo; em seguida rodar contra copias deliberadamente quebradas
(um placeholder de template `[FEATURE]` esquecido, uma citacao a `FR-099`
inexistente na spec, uma entrada de contrato sem rotulo real-vs-proposto) e
confirmar deteccao com severidade correta. Testavel isoladamente de US1 e
US3 (basta apontar a validacao diretamente para os artefatos, sem depender
do mecanismo de deteccao automatica de US3).

**Acceptance Scenarios**:

1. **Given** um `plan.md` com as secoes obrigatorias presentes (`Summary`,
   `Technical Context`, `Constitution Check`, `Project Structure`) e sem
   placeholders de template residuais, **When** a validacao roda com o
   plan-profile, **Then** o relatorio reporta zero erros.
2. **Given** um `plan.md` que cita um `FR-NNN` ou `SC-NNN` inexistente na
   `spec.md` correspondente, **When** a validacao roda, **Then** o
   relatorio reporta um erro identificando a citacao invalida.
3. **Given** uma entrada em `contracts/*.md` que documenta um
   endpoint/evento sem indicar claramente se e um contrato real (extraido
   de fonte verificavel) ou uma proposta ainda nao validada, **When** a
   validacao roda, **Then** o relatorio reporta um erro apontando a
   ambiguidade.
4. **Given** qualquer artefato da familia `/plan` contendo um placeholder de
   template nao preenchido (ex.: `[FEATURE]`, `[Topico]`,
   `[Endpoint/Command/Event]` copiados literalmente do template), **When**
   a validacao roda, **Then** o relatorio reporta um erro.

---

### User Story 3 - Deteccao automatica de perfil por convencao de path (Priority: P3)

Como orquestrador ou operador, eu quero que a skill reconheca
automaticamente qual perfil aplicar (spec-profile ou plan-profile) quando o
caminho do artefato segue a convencao padrao do pipeline SDD
(`docs/specs/<feature>/spec.md`, `docs/specs/<feature>/plan.md`, etc.), para
nao precisar informar explicitamente qual perfil usar toda vez que valido um
artefato gerado pelo proprio pipeline.

**Why this priority**: e uma melhoria de ergonomia sobre US1/US2 — reduz
atrito de adocao (nenhum orquestrador precisa "lembrar" de passar uma opcao
extra), mas o valor central (checklist nativo existir) ja esta entregue por
US1/US2 mesmo sem deteccao automatica. Por isso vem depois.

**Independent Test**: apontar a validacao para um caminho que segue a
convencao padrao (ex.: `docs/specs/qualquer-feature/spec.md`) sem informar
qual perfil usar, e confirmar que o spec-profile e aplicado automaticamente;
repetir para `plan.md` e confirmar plan-profile. Em seguida, apontar para um
caminho fora da convencao (ex.: um arquivo chamado `spec.md` fora de
`docs/specs/`) e confirmar que o sistema nao aplica um perfil por engano —
pede desambiguacao explicita em vez de adivinhar. Testavel isoladamente de
US1/US2 (assume que os perfis ja existem; testa apenas o mecanismo de
selecao).

**Acceptance Scenarios**:

1. **Given** um caminho de artefato que segue a convencao padrao do
   pipeline SDD para `spec.md`, **When** a validacao roda sem selecao
   explicita de perfil, **Then** o spec-profile e aplicado
   automaticamente.
2. **Given** um caminho de artefato que segue a convencao padrao do
   pipeline SDD para qualquer arquivo da familia `/plan` (`plan.md`,
   `research.md`, `data-model.md`, `quickstart.md`, `contracts/*.md`),
   **When** a validacao roda sem selecao explicita de perfil, **Then** o
   plan-profile e aplicado automaticamente.
3. **Given** um arquivo cujo caminho nao segue nenhuma convencao
   reconhecida (nem UC, nem runbook, nem spec/plan), **When** a validacao
   roda sem selecao explicita de perfil, **Then** o sistema reporta que o
   perfil nao pode ser determinado automaticamente e pede selecao
   explicita, em vez de aplicar silenciosamente um perfil incorreto
   (comportamento atual do perfil UC como default implicito NAO se estende
   aos artefatos desta feature).

### Edge Cases

- O que acontece quando um artefato nao casa nenhum perfil conhecido (nem
  UC, nem runbook, nem spec-profile, nem plan-profile)? O sistema reporta
  erro claro de "perfil nao determinado" — ver Acceptance Scenario 3 de
  US3.
- O que acontece com `tasks.md`, que vive no mesmo diretorio
  `docs/specs/<feature>/` mas nao e nem spec nem artefato de `/plan`? Fica
  fora do escopo dos dois novos perfis — nenhum perfil "tasks" e definido
  por esta feature.
- O que acontece quando `spec.md` tem mais de 3 `[NEEDS CLARIFICATION]`?
  Erro bloqueante — mesma regra hard-limit ja aplicada por `specify` (ver
  Acceptance Scenario 3 de US1).
- O que acontece quando `plan.md` referencia um `FR-`/`SC-` inexistente na
  `spec.md` correspondente? Erro — ver Acceptance Scenario 2 de US2. Este
  check e de integridade referencial de UM documento (o `plan.md` citando
  IDs que devem existir alhures), no mesmo espirito do que o perfil UC ja
  faz hoje ao exigir que `Dependencias` referenciem UCs existentes — nao e
  a analise de cobertura cross-artifact profunda que `analyze` ja realiza
  (duplicacao, gaps, drift de terminologia entre spec/tasks/constitution).
- O que acontece com um `contracts/*.md` que documenta um endpoint de
  sistema externo sem indicar claramente se e real ou proposto? Erro — a
  ambiguidade entre contrato real e hipotese e exatamente o risco que o
  Principio VI (Veracidade de Dados) do toolkit existe para evitar.

## Requirements

### Functional Requirements

#### Perfil spec-profile (US1)

- **FR-001**: O sistema MUST validar a presenca das tres secoes obrigatorias
  de um `spec.md` (`User Scenarios & Testing`, `Requirements`,
  `Success Criteria`); ausencia de qualquer uma delas MUST ser reportada com
  severidade erro.
- **FR-002**: O sistema MUST detectar linguagem de detalhe de implementacao
  (nomes de linguagem, framework, biblioteca ou API especifica) dentro de um
  `spec.md`, reportando com severidade erro — espelha o anti-padrao "Detalhes
  de implementacao na spec" catalogado em `specify` (`examples/spec-bad.md`).
- **FR-003**: O sistema MUST detectar Success Criteria que nao sejam
  mensuraveis (sem metrica quantificavel: tempo, percentual, contagem, taxa)
  ou que usem jargao tecnico especifico de implementacao, reportando com
  severidade erro — espelha o anti-padrao "Success criteria com jargao
  tecnico".
- **FR-004**: O sistema MUST detectar mais de 3 marcadores
  `[NEEDS CLARIFICATION]` no total de um `spec.md`, reportando com
  severidade erro — mesma regra hard-limit ja imposta por `specify`.
- **FR-005**: O sistema SHOULD detectar secoes deixadas com placeholder
  "N/A" em vez de removidas, reportando com severidade aviso — espelha o
  anti-padrao "Secoes vazias com N/A".
- **FR-006**: O sistema SHOULD detectar adjetivos vagos sem quantificacao em
  Requirements/Success Criteria (ex.: "rapido", "simples", "robusto" sem
  metrica associada), reportando com severidade aviso — espelha o
  anti-padrao "Adjetivos vagos sem quantificacao".
- **FR-007**: O sistema SHOULD detectar user stories que dependem umas das
  outras para serem testadas isoladamente (nao independentemente
  testaveis), reportando com severidade aviso — espelha o anti-padrao "User
  stories que dependem umas das outras". Classificado como aviso (nao erro)
  porque a deteccao de acoplamento entre stories e uma checagem semantica,
  nao puramente estrutural.

#### Perfil plan-profile (US2)

- **FR-008**: O sistema MUST validar a presenca das secoes obrigatorias de
  `plan.md` (`Summary`, `Technical Context`, `Constitution Check`,
  `Project Structure`); ausencia de qualquer uma delas MUST ser reportada
  com severidade erro.
- **FR-009**: O sistema MUST detectar, em qualquer artefato da familia
  `/plan` (`plan.md`, `research.md`, `data-model.md`, `quickstart.md`,
  `contracts/*.md`), placeholders de template nao preenchidos (tokens entre
  colchetes copiados literalmente dos templates da skill `plan`, ex.:
  `[FEATURE]`, `[Topico]`, `[Endpoint/Command/Event]`), reportando com
  severidade erro.
- **FR-010**: O sistema MUST validar que toda entrada em `contracts/*.md`
  esta rotulada de forma inequivoca como contrato real (extraido de fonte
  verificavel) ou como proposta ainda nao validada (convencao
  `[PROPOSTA — a validar na implementacao]` ja usada por `plan`); ausencia
  de rotulagem clara MUST ser reportada com severidade erro — aplica o
  Principio VI (Veracidade de Dados) do toolkit ao artefato de contrato.
- **FR-011**: O sistema MUST validar que `plan.md` nao contem marcadores
  `[NEEDS CLARIFICATION]` residuais (devem ter sido resolvidos no Phase 0,
  conforme `plan`); presenca MUST ser reportada com severidade erro.
- **FR-012**: O sistema MUST validar que referencias a `FR-`/`SC-` citadas
  em `plan.md` correspondem a IDs de fato presentes na `spec.md` da mesma
  feature; citacao de um ID inexistente MUST ser reportada com severidade
  erro. Este check e de integridade referencial de UM documento (mesmo
  espirito da checagem "Dependencias devem referenciar UCs existentes" que
  o perfil UC ja aplica hoje) — nao substitui a analise de cobertura
  cross-artifact que `analyze` realiza.
- **FR-013**: O sistema MUST NOT verificar, no plan-profile, se um link
  interno entre artefatos da familia `/plan` resolve no disco (arquivo
  apontado existe, anchor corresponde a um header) — essa checagem
  permanece 100% de responsabilidade de `validate-docs-rendered` (secao
  2.2 "Links internos" do seu SKILL.md). A unica checagem de referencia
  cruzada do plan-profile e semantica: validar que IDs `FR-`/`SC-` citados
  em `plan.md` existem na `spec.md` correspondente (ver FR-012) — nao
  resolucao de path/anchor no disco (ver Clarifications, 2026-07-10).

#### Acionamento e deteccao de perfil (US3)

- **FR-014**: O sistema MUST oferecer uma forma de o operador/orquestrador
  selecionar explicitamente qual perfil aplicar (spec-profile ou
  plan-profile), adicionalmente aos perfis UC e `--runbook` ja existentes.
- **FR-015**: O sistema MUST reconhecer automaticamente o perfil aplicavel
  quando o caminho do artefato segue a convencao padrao do pipeline SDD
  deste toolkit (`docs/specs/<feature>/spec.md` para spec-profile;
  `docs/specs/<feature>/{plan,research,data-model,quickstart}.md` ou
  `docs/specs/<feature>/contracts/*.md` para plan-profile), sem exigir
  selecao explicita nesses casos.
- **FR-016**: Quando um artefato nao casa nenhuma convencao reconhecida
  (nem UC, nem runbook, nem spec-profile, nem plan-profile) e nenhuma
  selecao explicita de perfil foi informada, o sistema MUST reportar que o
  perfil nao pode ser determinado, em vez de aplicar silenciosamente um
  perfil default incorreto.

#### Severidade e nao-duplicacao (transversal)

- **FR-017**: Todo achado dos perfis spec-profile e plan-profile MUST ser
  classificado usando o mesmo modelo de severidade ja existente na skill
  (Erro bloqueia aprovacao / Aviso recomenda correcao / Info e sugestao
  opcional) — o sistema MUST NOT introduzir uma taxonomia de severidade
  divergente.
- **FR-018**: Os perfis spec-profile e plan-profile MUST NOT reimplementar
  checagens ja de responsabilidade de `analyze` (consistencia cross-artifact
  profunda: duplicacao de requisitos, gaps de cobertura entre spec/tasks,
  drift de terminologia, alinhamento com constitution) nem de
  `validate-docs-rendered` (validacao de renderizacao: sintaxe Mermaid,
  parse de frontmatter YAML, resolucao de links internos no disco —
  arquivo apontado existe e anchor corresponde a header — e validade de
  anchors) — o escopo dos dois novos perfis MUST se limitar a qualidade
  estrutural de UM artefato isolado, no mesmo espirito dos perfis UC e
  `--runbook` ja existentes. Fronteira explicita para o caso de referencia
  cruzada de IDs: FR-012/FR-013 cobrem apenas se um ID `FR-`/`SC-` citado
  existe na spec (checagem semantica, dono: plan-profile); se um path de
  arquivo/anchor citado resolve no disco e checagem de renderizacao (dono:
  `validate-docs-rendered`, secao 2.2).

### Key Entities

- **SddSpecArtifact**: um `spec.md` gerado pela skill `specify`, validado
  pelo spec-profile — extensao do escopo hoje limitado a UC/runbook.
- **SddPlanArtifact**: qualquer artefato da familia gerada pela skill
  `plan` (`plan.md`, `research.md`, `data-model.md`, `quickstart.md`,
  `contracts/*.md`), validado pelo plan-profile.
- **SddValidationProfile**: o conjunto de checks aplicavel a um tipo de
  artefato — extensao do modelo ja existente (perfil UC e perfil
  `--runbook`) para incluir spec-profile e plan-profile.
- **ValidationFinding**: um achado individual produzido por um check,
  com severidade (erro/aviso/info) e localizacao — reaproveita o formato de
  relatorio ja existente na skill.

## Success Criteria

### Measurable Outcomes

- **SC-001**: O spec-profile cobre as 3 secoes obrigatorias de um `spec.md`
  em 100% das execucoes, sem falso-negativo para artefato com secao
  obrigatoria ausente, em um conjunto de teste controlado.
- **SC-002**: O spec-profile detecta 100% dos 6 anti-padroes catalogados em
  `specify` (`examples/spec-bad.md`) que sao estruturalmente detectaveis
  (implementacao vazando na spec, success criteria com jargao tecnico,
  stories acopladas, adjetivos vagos, excesso de
  `[NEEDS CLARIFICATION]`, secoes vazias com N/A), em um conjunto de teste
  controlado construido a partir desses exemplos.
- **SC-003**: O plan-profile cobre as 4 secoes obrigatorias de um `plan.md`
  em 100% das execucoes, sem falso-negativo, em um conjunto de teste
  controlado.
- **SC-004**: O plan-profile detecta 100% das entradas de `contracts/*.md`
  sem rotulagem explicita real-vs-proposto, em um conjunto de teste
  controlado.
- **SC-005**: Para qualquer execucao dos dois novos perfis, zero achados tem
  categoria que se sobreponha a uma categoria ja coberta por `analyze` ou
  `validate-docs-rendered` — verificado por checklist documentado de
  fronteira de responsabilidade entre as tres skills.
- **SC-006**: Apos a adocao desta feature, os orquestradores
  `agente-00c`/`feature-00c` deixam de depender de grep ad-hoc para checar
  a qualidade estrutural de `spec.md`/artefatos de `plan` — 100% dos pontos
  onde essa checagem ad-hoc ocorre hoje passam a invocar um dos dois novos
  perfis dentro de um ciclo de release do toolkit.

## Out of Scope

- Deteccao de drift de convencao de case (`snake_case` vs `camelCase`)
  entre camadas — ja coberta pelo Pass G ("Convencoes de Borda") de
  `analyze`.
- Validacao de sintaxe Mermaid, parse de frontmatter YAML, resolucao de
  links internos no disco (arquivo apontado existe) ou validade de anchors
  de renderizacao — permanece 100% com `validate-docs-rendered` (ver
  Clarifications, 2026-07-10, para a resolucao de FR-013).
- Analise de cobertura cross-artifact profunda (mapeamento tasks vs
  requisitos, duplicacao de requisitos, gaps, drift de terminologia entre
  spec/tasks/constitution) — permanece 100% com `analyze`.
- Escolha de implementacao (script dedicado em `scripts/` vs. checklist
  guiado por prosa, como os perfis UC/`--runbook` ja fazem hoje) — decisao
  de `/plan`.
- Nomeacao exata de flags/opcoes de acionamento explicito — decisao de
  `/plan`.
- Mudanca nos perfis UC e `--runbook` ja existentes — permanecem
  inalterados; esta feature apenas adiciona dois perfis novos.

## Dependencies & Assumptions

- **Depende de** a infraestrutura de relatorio e o modelo de severidade
  (Erro/Aviso/Info) ja existentes em `validate-documentation` — os dois
  perfis novos reutilizam esse formato, nao criam um paralelo.
- **Depende de** os criterios de qualidade ja documentados na prosa de
  `specify` (`SKILL.md` + `examples/spec-bad.md`) e `plan` (`SKILL.md` +
  `templates/*.md`) como fonte dos checks — esta feature nao inventa novos
  criterios de qualidade, apenas os torna nativamente verificaveis via
  `validate-documentation`.
- **Assume** que `analyze` permanece responsavel por consistencia
  cross-artifact profunda e `validate-docs-rendered` permanece responsavel
  por checks de renderizacao — os dois perfis novos NAO assumem nenhuma
  dessas responsabilidades (ver FR-018 e Out of Scope).
- **Assume** que a convencao de diretorio `docs/specs/<feature>/{spec.md,
  plan.md,research.md,data-model.md,quickstart.md,contracts/}` (ja em uso
  neste projeto, ex.: `docs/specs/enforced-guards/`) e estavel o bastante
  para servir de base a deteccao automatica de perfil (US3/FR-015). Se essa
  convencao mudar, a deteccao automatica precisa ser revisada.
