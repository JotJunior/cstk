# Requirements Checklist: delivery-tier

**Purpose**: Unit tests for English — valida completude, clareza,
consistencia e mensurabilidade dos requisitos funcionais de
`delivery-tier` antes de `/create-tasks`.
**Created**: 2026-08-15
**Feature**: [spec.md](../spec.md)

## Completude de Requisitos

- [x] CHK001 - Sao os 4 tokens canonicos do tier definidos de forma
  estavel e enumerada (nao aberta a interpretacao)? [Completude, Spec
  §FR-001] {auto} — Satisfeito: FR-001 lista "tokens estaveis `local`,
  `internal-network`, `cloud-internal` e `cloud-public`".
- [x] CHK002 - E definido o comportamento de persistencia do tier tanto
  no init quanto na releitura pelo resume, sem re-prompt? [Completude,
  Spec §FR-002] {auto} — Satisfeito: FR-002 "gravado no init... retomadas
  MUST reler o campo sem re-promptar".
- [x] CHK003 - O default para ausencia de resposta/entrada
  invalida/execucao nao-interativa esta definido de forma unica?
  [Completude, Spec §FR-003] {auto} — Satisfeito: FR-003 "MUST resultar
  no default `cloud-public`" cobre os 3 casos na mesma clausula.
- [x] CHK004 - Estao definidos todos os consumidores do tier na
  pipeline (briefing/specify/plan, quality gates, create-tasks)?
  [Completude, Spec §FR-004, FR-005, FR-006] {auto} — Satisfeito: os
  3 FRs cobrem, respectivamente, propagacao de contexto, matriz de
  gates e backlog.
- [x] CHK005 - O requisito de auditoria da escolha do tier especifica o
  padrao de Decisao (5 campos) ja usado no toolkit? [Completude, Spec
  §FR-008] {auto} — Satisfeito: FR-008 "Decisao auditavel (5 campos)".
- [x] CHK006 - Elevacao e rebaixamento mid-execucao tem regras
  diferenciadas e explicitas para cada direcao? [Completude, Spec
  §FR-009] {auto} — Satisfeito: FR-009 distingue "Elevacao... MUST ser
  suportada via decisao manual" de "rebaixamento... MUST NOT ser
  aplicado sem decisao manual explicita e MUST NOT reduzir
  retroativamente".
- [x] CHK007 - O tratamento de estado legado (sem campo `delivery_tier`)
  cobre TODOS os leitores, nao so o init/resume? [Completude, Spec
  §FR-010] {auto} — Satisfeito: FR-010 "MUST ser tratado como
  `cloud-public` em qualquer leitor (orquestrador, resume, report)".
- [x] CHK008 - Os Success Criteria cobrem tanto o caso base (zero
  regressao) quanto o caso de economia (tier `local`)? [Completude, Spec
  §SC-002, SC-003] {auto} — Satisfeito: SC-002 fixa o caso base, SC-003
  fixa o caso de economia comparando `local` vs `cloud-public`.

## Clareza de Requisitos

- [x] CHK009 - E 'profundidade e escopo' (FR-007) delimitado com o que
  NUNCA muda, evitando leitura extensiva do termo? [Clareza, Spec
  §FR-007] {auto} — Satisfeito: FR-007 enumera negativamente "MUST NOT
  alterar, relaxar ou desativar o Principio VI... as guardas enforced
  (bash-guard, path-guard, secrets-filter) nem qualquer invariante de
  seguranca do runtime".
- [x] CHK010 - 'Versao leve' do gate `owasp-security` (FR-005) e
  quantificada com escopo especifico, nao deixada vaga? [Clareza, Spec
  §FR-005] {auto} — Satisfeito: FR-005 "versao leve (checagens
  essenciais: auth, secrets, input) em `internal-network`".
- [x] CHK011 - As fases omitidas na divisao binaria (FR-006) sao
  enumeradas explicitamente, nao apenas nomeadas genericamente?
  [Clareza, Spec §FR-006] {auto} — Satisfeito: FR-006 "deploy em nuvem,
  escalabilidade e observabilidade de producao".
- [x] CHK012 - 'Decisao manual explicita' para elevacao (FR-009)
  especifica QUEM a registra e QUANDO passa a valer? [Clareza, Spec
  §FR-009, User Story 3] {auto} — Satisfeito: User Story 3 "ele ELEVA o
  tier via decisao manual pre-onda — a mudanca fica registrada e vale
  das ondas seguintes em diante" fixa autor (operador) e momento
  (ondas seguintes).

## Consistencia de Requisitos

- [x] CHK013 - O escopo declarado da matriz (exclusivamente
  `owasp-security`) e consistente entre FR-005 e a Key Entity "Matriz
  tier×gate"? [Consistencia, Spec §FR-005, Key Entities] {auto} —
  Satisfeito: ambos os trechos restringem a matriz a
  `owasp-security`/quality gates complementares, sem contradicao.
- [x] CHK014 - As exclusoes de escopo declaradas no Contexto
  (model-routing, `/feature-00c`) NAO reaparecem, mesmo implicitamente,
  em nenhum dos 10 FRs? [Consistencia, Spec §Contexto, FR-001..FR-010]
  {auto} — Satisfeito: nenhum FR menciona model-routing nem
  `/feature-00c`; a restricao permanece so em prosa de Contexto.
- [x] CHK015 - As 3 respostas de Clarifications (dec-011, dec-012,
  dec-013) estao propagadas literalmente para os FRs correspondentes,
  sem ficarem orfas na secao de perguntas? [Consistencia, Spec
  §Clarifications] {auto} — Satisfeito: dec-011 → Contexto/escopo
  (FR-001/FR-002 "restrito ao `/agente-00c`"); dec-012 → FR-005
  ("cobre EXCLUSIVAMENTE o gate `owasp-security`"); dec-013 → FR-006
  ("divisao BINARIA nuvem/nao-nuvem").

## Qualidade de Criterios de Aceite

- [x] CHK016 - SC-003 e mensuravel objetivamente (contagem comparavel
  de tarefas/fases/ondas entre duas execucoes do mesmo
  produto-exemplo)? [Mensurabilidade, Spec §SC-003] {auto} —
  Satisfeito: SC-003 e formulado como comparacao relativa entre duas
  execucoes do mesmo produto-exemplo ("menos tarefas e menos fases...
  conclui em menos ondas"), testavel via o Independent Test da US2.
- [x] CHK017 - SC-004 (100% das execucoes/gates) tem mecanismo
  auditavel que permita a verificacao automatica desse percentual?
  [Mensurabilidade, Spec §SC-004, FR-008] {auto} — Satisfeito: FR-008
  exige Decisao auditavel para toda escolha/skip, dado consultavel
  para calcular o 100% de SC-004.
- [ ] CHK018 - Existe success criterion (ou Acceptance Scenario) que
  meça especificamente a calibracao de profundidade nas etapas
  briefing/specify/plan (FR-004) — independente da contagem de fases do
  backlog, que e o que SC-003 mede (FR-006)? [Gap, Spec §FR-004,
  SC-003] {auto} — **Nao satisfeito**: SC-003 mede apenas o efeito de
  FR-006 no backlog (tarefas/fases/ondas). Nenhum SC ou Acceptance
  Scenario mede o efeito de FR-004 no CONTEUDO de `spec.md`/`plan.md`
  (ex.: menos secoes de arquitetura, menos NFRs detalhados para tier
  `local`). Confirmado por varredura dos 23 cenarios de
  `quickstart.md` (`grep -n 'Cenario'`): nenhum cobre profundidade de
  artefato specify/plan, apenas estado/gates/backlog/seguranca.

## Cobertura de Edge Cases

- [x] CHK019 - O rebaixamento mid-execucao esta coberto com regra
  explicita (nao apenas a elevacao)? [Cobertura, Spec §Edge Cases,
  FR-009] {auto} — Satisfeito: Edge Cases item 2 cobre rebaixamento
  explicitamente, com o mesmo rigor da elevacao.
- [x] CHK020 - O caso de tier `local` combinado com consumo de API
  externa com dados sensiveis esta coberto, reforcando que o Principio
  VI nao e afetado? [Cobertura, Spec §Edge Cases, FR-007] {auto} —
  Satisfeito: Edge Cases item 3 cobre exatamente esse cenario.
- [x] CHK021 - O caso de execucao nao-interativa (sem operador
  presente) esta coberto sem bloquear o init? [Cobertura, Spec §Edge
  Cases, FR-003] {auto} — Satisfeito: Edge Cases item 4 "aplicar o
  default `cloud-public` sem bloquear o init".

## Ambiguidades, Conflitos e Riscos

- [ ] CHK022 - Os itens CHK001-CHK021 acima apontam para um unico Gap
  real (CHK018: SC-003 nao mede profundidade de specify/plan, so
  backlog). Vale a pena o dono do produto exigir um SC/cenario
  dedicado para FR-004 antes de `/create-tasks`, ou o efeito agregado
  (menos ondas totais em SC-003) e aceito como proxy suficiente?
  [Assumption, Risco] {humano} — depende de apetite de rigor de
  medicao, nao decidivel so com os artefatos.

## Notes

- Items `{auto}` ja vem resolvidos pelo agente (`[x]` com evidencia
  citada, ou `[Gap]` quando a spec nao cobre).
- Items `{humano}` ficam `[ ]` aguardando decisao do dono do produto.
- Rastreabilidade: 22/22 items (100%) citam `[Spec §X.Y]` e/ou
  `[Gap]`/`[Assumption]` — acima do minimo de 80%.
