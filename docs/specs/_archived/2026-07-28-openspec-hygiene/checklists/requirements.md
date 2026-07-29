# Requirements Checklist: openspec-hygiene

**Purpose**: Validar a qualidade dos requisitos (completude, clareza,
consistencia, mensurabilidade, cobertura de cenarios/edge cases) da spec
"Higiene OpenSpec — Gate de Cenarios, Guia de Triagem, Archive Datado,
Envelope Diagnostico" — nao valida a implementacao.
**Created**: 2026-07-23
**Feature**: [spec.md](../spec.md)

## Completude de Requisitos

- [x] CHK001 - O gate de cobertura de cenario (US1) define claramente o que
  conta como "cenario associado" a um FR (Acceptance Scenario ou Edge
  Case)? [Completude, Spec §FR-001] {auto} — satisfeito: FR-001 enumera
  explicitamente os dois tipos de cenario aceitos.
- [x] CHK002 - E especificado em que momento do fluxo de `specify` e de
  `checklist` o gate deve rodar (antes de reportar sucesso, nao depois)?
  [Completude, Spec §FR-002] {auto} — satisfeito: "antes de qualquer uma
  delas reportar conclusao bem-sucedida".
- [x] CHK003 - O comportamento do gate no caso degenerado (spec sem nenhum
  FR) esta definido? [Completude, Spec §FR-004, Edge Cases] {auto} —
  satisfeito: FR-004 + Edge Case #1 + Acceptance Scenario 3 da US1
  convergem no mesmo comportamento (passa trivialmente).
- [x] CHK004 - A triagem "atualizar spec vs feature nova" (US2) cobre os
  tres casos de borda: refinamento, expansao de escopo, e nenhuma spec
  relacionada? [Completude, Spec §FR-006..FR-008] {auto} — satisfeito:
  Acceptance Scenarios 1-3 da US2 cobrem os tres casos.
- [x] CHK005 - A convencao de nomenclatura do archive datado define
  explicitamente o que acontece com diretorios ja arquivados sem
  prefixo? [Completude, Spec §FR-010] {auto} — satisfeito: FR-010 e Edge
  Case correspondente sao explicitos (MUST NOT migrar).
- [x] CHK006 - O envelope diagnostico define todos os campos obrigatorios
  e suas constraints minimas (nao apenas o nome do campo)? [Completude,
  Spec §FR-012..FR-014] {auto} — satisfeito: FR-012 lista os 4 campos;
  FR-013 restringe `fix` != `message`; FR-014 exige `code` estavel e
  distinguivel sem parsing de texto livre.
- [ ] CHK007 - O escopo exato de scripts POSIX cobertos pela migracao do
  envelope diagnostico (FR-012/FR-015) esta fixado na spec, ou delegado
  ao plano? [Completude, Spec §FR-012, Plan §Project Structure] {humano}
  — a spec deliberadamente delega o escopo exato ao `/plan` ("escopo
  determinado pelo plano desta feature", FR-012); o plano fixou 4
  scripts-piloto sem justificar por que esses e nao outros de maior
  volume de chamadas. Decisao de priorizacao de risco/impacto — dono do
  produto confirma se a amostra-piloto e representativa o suficiente.

## Clareza de Requisitos

- [x] CHK008 - "Cenario associado" (US1) e definido de forma verificavel
  (fast-path por ID + heuristica textual), sem depender de julgamento
  subjetivo do leitor? [Clareza, Spec §FR-005] {auto} — satisfeito: FR-005
  especifica o mecanismo de correspondencia (termos-chave centrais do
  requisito vs corpus de cenarios) e explicitamente NAO exige citacao
  literal de ID.
- [x] CHK009 - "Mensagem acionavel de correcao" (FR-003, FR-013) e
  diferenciada de forma nao-ambigua de uma mensagem generica de erro?
  [Clareza, Spec §FR-003, FR-013] {auto} — satisfeito: FR-013 e explicito
  ("MUST NOT ser repeticao do campo message"); FR-003 da exemplo concreto
  ("adicionar um cenario que referencie aquele requisito").
- [x] CHK010 - "Escopo aditivo" da migracao do envelope diagnostico
  (FR-015) e quantificado de forma a nao ser interpretado como rewrite
  parcial disfarcado? [Clareza, Spec §FR-015, Edge Cases] {auto} —
  satisfeito: FR-015 + Edge Case correspondente sao explicitos que
  scripts fora do escopo do plano MUST manter formato atual inalterado.
- [x] CHK011 - "Intencao muda/escopo expande" (criterio de triagem da
  US2) tem exemplo concreto que ancore o julgamento, evitando
  subjetividade pura? [Clareza, Spec §AS2 US2] {auto} — satisfeito:
  Acceptance Scenario 2 da US2 da exemplo concreto ("novos atores,
  capacidade nao relacionada ao objetivo original").

## Consistencia de Requisitos

- [x] CHK012 - FR-002 (gate invocado por `specify` e `checklist`) e
  consistente com a Ordem de implementacao sugerida no plan (item 1:
  integracao na prosa de ambas as skills)? [Consistencia, Spec §FR-002,
  Plan §Ordem de implementacao] {auto} — satisfeito, mesma cobertura nos
  dois artefatos.
- [x] CHK013 - O comportamento fail-fast do envelope diagnostico (Edge
  Case: "apenas o primeiro erro fatal") e consistente com o Principio II
  da constitution (`set -eu`, POSIX puro) citado na propria spec?
  [Consistencia, Spec Edge Cases, Constitution II] {auto} — satisfeito: a
  spec cita explicitamente essa consistencia ("consistente com a
  disciplina fail-fast... ja exigida pelo Principio II da constitution").
- [x] CHK014 - FR-016 (envelope nao pode exigir `jq` para EMITIR) e
  consistente com FR-012 (campos do envelope) sem introduzir dependencia
  implicita de `jq` em nenhum dos dois? [Consistencia, Spec §FR-012,
  FR-016] {auto} — satisfeito: nenhum dos dois FRs menciona `jq` como
  dependencia de emissao; FR-016 e explicito no MUST NOT.
- [x] CHK015 - A visao geral (linha 25-29) declara o item estrutural mais
  caro do benchmark (specs vivas) como fora de escopo — os 17 FRs
  respeitam esse limite sem reintroduzir esse escopo por uma porta
  lateral? [Consistencia, Spec §Visao geral] {auto} — satisfeito:
  nenhum FR trata de specs vivas/delta-specs/merge no archive; FR-009..
  FR-011 tratam apenas de nomenclatura do archive, escopo estritamente
  menor.

## Qualidade de Criterios de Aceite

- [x] CHK016 - SC-001 e mensuravel automaticamente sem revisao manual,
  conforme a propria SC declara? [Mensurabilidade, Spec §SC-001] {auto}
  — satisfeito: "verificavel automaticamente sem revisao manual" e o
  proprio gate da US1 (FR-001..FR-005) e o instrumento de verificacao.
- [x] CHK017 - SC-002 e verificavel sem ambiguidade (o autor identifica o
  requisito exato e a acao corretiva lendo so a mensagem de erro)?
  [Mensurabilidade, Spec §SC-002] {auto} — satisfeito: criterio testavel
  via Independent Test da US1 ja descrito na propria spec.
- [x] CHK018 - SC-003 cobre os dois lados da migracao (arquivados
  depois vs arquivados antes) de forma simetrica e mensuravel? [Mensura-
  bilidade, Spec §SC-003] {auto} — satisfeito: "100%... depois" e
  "100%... antes permanecem sem alteracao" sao ambos verificaveis por
  inspecao de nome de diretorio.
- [x] CHK019 - SC-005 e SC-006 sao mensuraveis por checagem automatizada
  (nao dependem de julgamento humano subjetivo)? [Mensurabilidade,
  Spec §SC-005, SC-006] {auto} — satisfeito: ambos ancorados em "veri-
  ficavel por checagem automatizada" / "zero regressao observavel em
  testes automatizados existentes".

## Cobertura de Cenarios

- [x] CHK020 - Cada uma das 4 User Stories tem pelo menos um Acceptance
  Scenario cobrindo o caso de sucesso e um cobrindo o caso de borda/
  degenerado? [Cobertura, Spec §US1-US4] {auto} — satisfeito: US1 tem 3
  scenarios (falha, sucesso, degenerado); US2 tem 3 (refina, expande,
  sem relacao); US3 tem 3 (arquiva, preserva antigo, ordena); US4 tem 3
  (emite envelope, codes distintos, fora-de-escopo inalterado).
- [x] CHK021 - Os FRs de cada User Story tem rastreabilidade cruzada
  verificavel com os Acceptance Scenarios da mesma US (fast-path ou
  heuristica do proprio gate desta feature aplicado reflexivamente)?
  [Cobertura, Spec §Functional Requirements] {auto} — satisfeito por
  inspecao: FR-001..FR-005 ↔ US1 AS1-3; FR-006..FR-008 ↔ US2 AS1-3;
  FR-009..FR-011 ↔ US3 AS1-3; FR-012..FR-017 ↔ US4 AS1-3 (FR-017 e
  transversal, coberto pela obrigacao de teste que acompanha cada
  script novo das 4 USs).

## Cobertura de Edge Cases

- [x] CHK022 - O Edge Case de spec sem FR (US1) e coberto por um
  Acceptance Scenario dedicado, nao apenas mencionado em prosa? [Edge
  Case, Spec §Edge Cases, AS3 US1] {auto} — satisfeito: Edge Case remete
  explicitamente ao Acceptance Scenario 3 da US1.
- [x] CHK023 - O Edge Case de gate retroativo bloqueando specs legadas
  (sem cenario de exclusao) esta resolvido de forma explicita, sem
  deixar ambiguidade sobre se ha excecao? [Edge Case, Spec §Edge Cases]
  {auto} — satisfeito: "nao ha excecao retroativa" e texto MUST literal,
  zero ambiguidade.
- [x] CHK024 - O Edge Case de falha dupla simultanea no envelope
  diagnostico (duas condicoes de erro na mesma invocacao) define
  comportamento deterministico (nao arbitrario)? [Edge Case, Spec §Edge
  Cases] {auto} — satisfeito: "reporta apenas o primeiro erro fatal
  encontrado", ancorado no fail-fast do Principio II.
- [x] CHK025 - O Edge Case de script fora do escopo de migracao do
  envelope diagnostico tem comportamento simetrico ao FR correspondente
  (FR-015), sem contradicao entre os dois trechos? [Edge Case, Spec
  §Edge Cases, FR-015] {auto} — satisfeito: ambos dizem a mesma coisa
  (formato atual mantido).

## Requisitos Nao-Funcionais

- [x] CHK026 - A restricao de performance do gate (US1) e explicita e
  mensuravel (nao apenas "deve ser rapido")? [Nao-Funcional, Plan
  §Technical Context] {auto} — satisfeito: Plan define "< 1s sobre spec
  tipica (puro grep/awk local)" — quantificado, nao vago.
- [x] CHK027 - A constraint de zero dependencia externa nao-POSIX
  (Constitution II) e refletida como requisito explicito, e nao apenas
  uma suposicao implicita do implementador? [Nao-Funcional, Spec
  §FR-016, Plan §Constitution Check] {auto} — satisfeito: FR-016 e MUST
  NOT explicito; Constitution Check do plan reafirma PASS para
  Principio II.
- [ ] CHK028 - A priorizacao P1 > P2 > P3 > P4 das quatro User Stories
  reflete o apetite de risco/valor do produto — em particular, US4
  (envelope diagnostico, maior superficie de call-sites) ficar em ultimo
  e aceitavel mesmo com risco de quebrar testes que verificam mensagem
  literal? [Risco, Spec §Why this priority de cada US] {humano} —
  julgamento de prioridade de produto; a spec justifica com "esforco/
  impacto" mas a aceitacao final do trade-off e do dono do produto.

## Dependencias e Premissas

- [x] CHK029 - A spec declara explicitamente que nenhum item introduz
  infraestrutura nova (scheduling, sessao persistente, mutex
  multi-processo)? [Dependencias, Spec §Decisoes de infraestrutura]
  {auto} — satisfeito: bloco "Decisoes de infraestrutura: N/A" e
  explicito e justificado (mecanismos deterministicos e sincronos).
- [x] CHK030 - Os arquivos/scripts explicitamente fora de escopo (`cli/`,
  `templates/feature-spec.md`, `validate-sdd.sh`,
  `validate-tasks-template.sh`) tem premissa registrada de por que ficam
  de fora (nao apenas omissao silenciosa)? [Dependencias, Plan §Project
  Structure] {auto} — satisfeito: plan lista o motivo de cada exclusao
  ("proibido pelo clarify FR-005", "padrao apenas seguido, nao tocado").

## Ambiguidades e Conflitos

- [x] CHK031 - Ha algum conflito entre a Session de Clarifications
  (FR-005, correspondencia heuristica sem exigir mudanca de template) e
  o texto final de FR-005 na secao Requirements? [Ambiguity/Conflict,
  Spec §Clarifications, §FR-005] {auto} — satisfeito: nenhum conflito;
  FR-005 reproduz literalmente a decisao da Clarification (heuristica
  textual, MUST NOT mudanca de template).
- [x] CHK032 - Ha algum requisito que dependa implicitamente de outro
  ainda nao declarado (ex.: FR-002 invocar um gate que so e definido
  depois, em FR-001)? [Ambiguity/Conflict, Spec §Functional
  Requirements] {auto} — satisfeito: ordem de declaracao dos FRs segue
  dependencia logica correta (FR-001 define o gate antes de FR-002
  exigir sua invocacao automatica).

## Notes

- Items `{auto}` ja vem resolvidos pelo agente (`[x]` com citacao); items
  `{humano}` ficam `[ ]` aguardando decisao do dono do produto.
- Marcar items concluidos com `[x]`.
- Items numerados sequencialmente para referencia.

### Resolucao

- **{auto} resolvidos**: 30 (`[x]` com evidencia citada)
- **{humano} aguardando decisao**: 2 (CHK007, CHK028)
- **Gaps abertos** (`[Gap]`/`[Ambiguity]`/`[Conflict]`): 0 — nenhuma
  ambiguidade ou conflito real encontrado; a spec ja passou por
  `clarify` (Session 2026-07-23) e chegou a este checklist com zero
  NEEDS CLARIFICATION (plan.md linha de Input).

### Follow-up dos items `{humano}`

| Item | Destino |
|------|---------|
| CHK007 — escopo-piloto de 4 scripts do envelope diagnostico | decisao do dono do produto antes de `/execute-task` da(s) task(s) de US4; se aprovado, nenhuma mudanca de artefato necessaria (plan.md ja registra a escolha) |
| CHK028 — priorizacao P1>P2>P3>P4 das quatro User Stories | decisao do dono do produto antes de `/create-tasks` sequenciar as fases; se aprovado, `/create-tasks` segue a Ordem de implementacao sugerida do plan.md sem alteracao |
