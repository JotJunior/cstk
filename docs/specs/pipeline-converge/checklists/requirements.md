# Requirements Checklist: pipeline-converge

**Purpose**: Validar a qualidade dos requisitos (completude, clareza,
consistência, mensurabilidade) de `spec.md` — não a corretude da
implementação proposta em `plan.md`/`research.md`/`data-model.md`/
`contracts/`, usados aqui apenas como evidência de resolução.
**Created**: 2026-08-22
**Feature**: [spec.md](../spec.md)

## Completude de Requisitos

- [x] CHK001 - O gatilho "backlog esgotado" (FR-002) tem critério objetivo e
  único para disparar a orientação à convergência? [Completude, Spec §FR-002]
  {auto}
  Evidência: FR-002 define "todas as tarefas concluídas"; o contrato
  `pipeline-stage-machine.md` §D2 opera esse critério de forma unívoca
  (`tasks.md` sem linha `- [ ]`/`- [~]` pendente) — sem espaço para
  interpretação concorrente.

- [x] CHK002 - O que conta como "divergência acionável" (FR-003/FR-004) está
  definido na spec, inclusive o tratamento de achados classificados como
  `unrequested`? [Completude, Ambiguity, Spec §FR-003, FR-004] {auto}
  Evidência (fechado na tarefa 1.1): `data-model.md` campo `actionable` do
  `ConvergenceStatusRecord` e `contracts/converge-status-cli.md` §`record`
  agora declaram explicitamente que achados classificados **só** como
  `unrequested` NÃO contam em `actionable` nem impedem `outcome=clean` —
  `unrequested` é achado de revisão (SKILL.md ETAPA 6: "MUST virar tarefa
  `kind=revisar`"), nunca "implementar", distinto por natureza de
  `missing`/`partial`/`contradicts`, os únicos tipos que compõem
  `actionable`.

- [x] CHK003 - Estão delimitadas as superfícies de documentação que precisam
  refletir a etapa nova (FR-001/FR-009), evitando lista incompleta que
  deixaria pontos desatualizados? [Completude, Spec §FR-001, FR-009] {auto}
  Evidência: `plan.md` §Project Structure enumera >10 arquivos afetados
  (docs, docs-site, README, CONTRIBUTING, CLAUDE.md, CHANGELOG) e
  `research.md` Decision 11 justifica cada superfície individualmente.

- [x] CHK004 - FR-005 ("fluxo que nunca passou por criação/execução de
  tarefas") delimita precisamente os casos-fronteira — `tasks.md` ausente
  vs. `tasks.md` presente porém vazio (0 tarefas)? [Completude, Gap, Spec
  §FR-005] {auto}
  Evidência (fechado na tarefa 1.2): `contracts/pipeline-stage-machine.md`
  §D2 e `contracts/converge-status-cli.md` §`check` agora declaram
  explicitamente que `tasks.md` presente mas sem nenhuma linha de tarefa é
  tratado **igual** a `tasks.md` ausente — mesmo veredito `not-applicable`/
  exit 0 nos dois casos, paridade mantida entre os dois contratos.

- [x] CHK005 - FR-010 (proveniência) define um conjunto fechado de valores
  possíveis para o rótulo, sem terceiro caso ambíguo? [Completude, Spec
  §FR-010] {auto}
  Evidência: "etapa obrigatória do gate `execute-task → review-task` ou
  invocação avulsa pelo operador" — dois valores, mutuamente exclusivos;
  `data-model.md` operacionaliza como enum `gate`\|`standalone`.

- [x] CHK006 - FR-007 (reabertura) define o que torna um round "encerrado" de
  forma testável, não apenas por negação ("não pode ser considerado
  encerrado")? [Completude, Spec §FR-007, Edge Cases] {auto}
  Evidência: FR-007 + Edge Case correspondente + `data-model.md` (aceite
  vale só para o digest corrente do `tasks.md`) definem "encerrado" como
  "convergência sem divergências acionáveis pendentes (ou aceite explícito)
  para o backlog do round reaberto" — critério verificável via
  `converge-status.sh check`.

## Clareza de Requisitos

- [x] CHK007 - "Divergências acionáveis pendentes" (FR-004) é quantificável
  de forma automatizável (contagem, não só booleano subjetivo)? [Clareza,
  Spec §FR-004] {auto}
  Evidência: `data-model.md` campo `actionable` (inteiro `>= 0`)
  operacionaliza a contagem.

- [x] CHK008 - "Fase de tarefas residual" (FR-003) referencia um mecanismo já
  definido, em vez de introduzir um conceito novo sem especificação?
  [Clareza, Spec §FR-003] {auto}
  Evidência: `plan.md`/`research.md` remetem ao apêndice de fase já
  existente na skill `converge` (`converge-tasks.sh append-phase`, ETAPA 6)
  — reuso de mecanismo, não conceito novo carente de definição.

- [x] CHK009 - "Soft gate" (Clarifications, sessão 2026-08-21) está definido
  operacionalmente (o que acontece de fato quando pendente)? [Clareza, Spec
  §Clarifications] {auto}
  Evidência: "a revisão de tarefas reporta as divergências pendentes como
  finding e exige uma decisão auditável de aceite de risco para prosseguir;
  nunca bloqueia a execução por si só" — comportamento explícito, sem termo
  vago remanescente.

- [ ] CHK010 - "Mesmo nível de rastreabilidade/auditoria das demais etapas"
  (FR-006) é comparável objetivamente, ou depende de julgamento sobre o que
  conta como paridade suficiente? [Clareza, Spec §FR-006] {humano}
  Reclassificado para `{humano}`: o requisito é inerentemente comparativo
  ("mesmo nível que as demais etapas") sem uma lista fechada, na própria
  spec, do que as demais etapas registram. `plan.md` dá evidência forte de
  que os MESMOS mecanismos (`record-skill`, histórico de decisões) serão
  reusados — mas decidir se isso satisfaz "mesmo nível" é julgamento de
  revisor, não checagem mecânica.

## Consistência de Requisitos

- [x] CHK011 - É consistente a convergência ser soft gate obrigatório
  (FR-004) e, ao mesmo tempo, permanecer invocável avulsamente a qualquer
  momento (FR-008), sem conflito de precedência entre as duas regras?
  [Consistência, Spec §FR-004, FR-008] {auto}
  Evidência: FR-008 é explícito quanto ao escopo ("independente da fronteira
  execute-task → review-task") e FR-010 fornece o mecanismo de distinção
  (proveniência) — as duas regras operam em domínios declarados
  separadamente, sem sobreposição.

- [x] CHK012 - É consistente a orientação universal de FR-002 (autônomo e
  manual) com a exceção declarada em FR-005 (features sem backlog)?
  [Consistência, Spec §FR-002, FR-005] {auto}
  Evidência: FR-005 é enunciado como exceção explícita e delimitada ("sem
  exigir convergência artificialmente"), não contradiz FR-002 — apenas
  restringe seu domínio de aplicação.

- [x] CHK013 - O vocabulário de estado do `data-model.md`
  (`clean`/`actionable`/`risk-accepted`) mapeia 1:1 com a linguagem usada
  pela spec ("divergências acionáveis", "aceite de risco")? [Consistência,
  Spec vs. Data Model] {auto}
  Evidência: correspondência direta e sem termo extra não-explicado em
  nenhum dos dois lados.

- [x] CHK014 - A posição declarada da etapa na sequência oficial (FR-001:
  "entre `execute-task` e `review-task`") é idêntica, sem desvio, ao delta
  concreto de máquina de etapas (`contracts/pipeline-stage-machine.md` §D1)?
  [Consistência, Spec §FR-001, Contract D1] {auto}
  Evidência: ambas as fontes descrevem a mesma posição ordinal; `D1` lista
  literalmente `... execute-task converge review-task ...`.

## Qualidade de Critérios de Aceite (Success Criteria)

- [ ] CHK015 - SC-001 ("identifica, numa única leitura... que o próximo
  passo é a convergência") é mensurável objetivamente, ou é um critério de
  UX qualitativo sem métrica de tempo/esforço? [Mensurabilidade, Spec
  §SC-001] {humano}
  Reclassificado para `{humano}`: "numa única leitura" é proxy de clareza
  de UX, não uma métrica automatizável (não há teste A/B, tempo de leitura
  ou contagem de re-leituras definidos). Julgamento do dono do produto
  sobre se o texto de próximos passos gerado é suficientemente inequívoco.

- [x] CHK016 - Existe mecanismo de auditoria declarado (ex.: query
  cross-execução) que permita comprovar objetivamente os "100%" de
  SC-002/SC-003, ou a métrica é aspiracional sem instrumento de medição?
  [Mensurabilidade, Gap, Spec §SC-002, SC-003] {auto}
  Evidência (fechado na tarefa 1.3): `contracts/converge-status-cli.md`
  §`audit` especifica `converge-status.sh audit --specs-root DIR [--json]`
  — para cada feature com backlog esgotado, verifica se o último registro é
  `outcome=clean|risk-accepted` com `tasks-digest` batendo o atual; agrega
  conforme/não-conforme e sai `1` havendo ao menos um não-conforme. Mecanismo
  objetivo e automatizável, exercitado em `quickstart.md` Cenário 21 sobre um
  conjunto sintético de 4+1 features.

- [x] CHK017 - SC-004 ("lista idêntica em todos os pontos") é verificável por
  meio automatizável, não apenas por inspeção manual? [Mensurabilidade, Spec
  §SC-004] {auto}
  Evidência: `research.md` Decision 11 declara explicitamente "verificável
  por `grep`" — critério objetivo com mecanismo de checagem citado.

## Cobertura de Cenários / Edge Cases

- [x] CHK018 - O Edge Case "feature sem caminho de código associado
  (documental pura)" define o comportamento esperado sem deixar
  implementação em aberto? [Cobertura, Spec §Edge Cases] {auto}
  Evidência: "A convergência deve concluir sem achados acionáveis e sem
  bloquear a progressão" — comportamento explícito e mensurável (achados=0).

- [ ] CHK019 - Esse Edge Case (feature com backlog mas sem caminhos de
  código) tem cenário de validação dedicado em `quickstart.md`, distinto do
  Cenário 9 (que cobre ausência TOTAL do artefato de backlog, um caso
  diferente — FR-005)? [Cobertura, Spec §Edge Cases] {humano}
  Reclassificado para `{humano}`: o requisito textual está claro (CHK018),
  mas não há evidência de cenário de teste dedicado que force esse caminho
  (backlog concluído + zero paths de código declarados) — decisão do dono
  do produto se vale a pena adicionar um Cenário 21 ao `quickstart.md` antes
  de `/create-tasks`, ou se o comportamento já está implicitamente coberto
  pelos Cenários 4/9.

- [x] CHK020 - O Edge Case "reabertura de feature já concluída" tem
  mecanismo de verificação citado (não apenas afirmação textual)?
  [Cobertura, Spec §Edge Cases, FR-007] {auto}
  Evidência: Cenário 8 do `quickstart.md` exercita exatamente esse caminho
  via invalidação por digest do `tasks.md`.

- [x] CHK021 - O Edge Case "convergência avulsa fora da fronteira
  execute-task→review-task" define claramente que permanece permitida sem
  restrição adicional? [Cobertura, Spec §Edge Cases, FR-008] {auto}
  Evidência: "Continua permitido e útil a qualquer momento... não restringe
  uso avulso" — sem condição adicional; Cenário 12 do `quickstart.md`
  valida.

## Requisitos Não-Funcionais

- [x] CHK022 - A spec impõe requisito de auditabilidade (registro auditável)
  para toda decisão de aceite de risco, evitando aceite "mudo"? [Não
  funcional, Spec §Clarifications, FR-004] {auto}
  Evidência: clarificação de sessão substitui explicitamente "campo flag
  simples" por "decisão auditável no histórico de execução" —
  `data-model.md` reforça com a regra `outcome=risk-accepted exige note OU
  decision-id`.

- [x] CHK023 - A spec restringe, mesmo que implicitamente, o aceite de risco
  a uma decisão do OPERADOR (não uma execução autônoma se auto-liberando do
  gate)? [Não funcional, Spec §FR-004] {auto}
  Evidência: FR-004 diz literalmente "quando **o operador** tiver registrado
  explicitamente... a decisão de aceitar o risco" — o sujeito da ação é
  fixado na própria spec, não deixado para a camada de implementação
  decidir sozinha (reforçado no plano por F8: "orquestrador NÃO invoca
  `accept-risk` por conta própria").

## Dependências e Premissas

- [ ] CHK024 - A spec (ou o plano correlato) confirma que TODOS os
  consumidores que hoje enumeram as etapas da pipeline derivam de uma única
  fonte, ou alguns são prosa hardcoded sujeita a drift futuro sem detecção
  automática? [Dependências, Assumption, Spec §FR-001, SC-004] {auto}
  `[Assumption]` parcialmente não verificada: `plan.md` (linha "SC-004 falha
  por divergência pré-existente do `analyze`") e `research.md` Decision 15
  já registram que ao menos UM ponto (`analyze`) diverge hoje da lista
  canônica por razão alheia a esta feature. Isso confirma que nem toda
  superfície deriva de `_PL_STAGES_LIST` automaticamente — algumas são
  prosa mantida manualmente, com risco de drift futuro não coberto por um
  mecanismo de verificação contínua (só grep pontual em SC-004, não CI
  gate).

- [x] CHK025 - A spec declara a premissa de que a feature não introduz
  schema/estado transacional novo, evitando exigir infraestrutura fora do
  escopo POSIX? [Dependências, Spec §Delta Requirements] {auto}
  Evidência: `spec.md` §Delta Requirements + `data-model.md`: "Nenhum campo
  novo em `state.json`/`state.db`"; `Technical Context` do plano confirma
  ausência de nova dependência externa.

- [x] CHK026 - A spec identifica a feature preexistente cuja decisão
  arquitetural está sendo revogada (evitando revogação implícita/silenciosa
  de uma decisão já registrada)? [Dependências, Spec vs. `skill-converge`]
  {auto}
  Evidência: `research.md` Decision 13 nomeia explicitamente a Decision 5 da
  feature `skill-converge` como revogada, com rationale — não é uma
  reversão silenciosa.

## Notes

- Items `{auto}` já vêm resolvidos pelo agente (`[x]` com citação, ou
  marcador `[Gap]`/`[Ambiguity]`/`[Assumption]`).
- Items `{humano}` ficam `[ ]` aguardando decisão do dono do produto.
- Gate determinístico `requirement-coverage.sh` executado sobre `spec.md`
  (ver relatório da onda) — achados incorporados como itens `[Gap]`
  adicionais quando aplicável.
