# Requirements Checklist: loose-usage-capture

**Purpose**: validar a QUALIDADE dos requisitos de `spec.md` (completude,
clareza, consistencia, mensurabilidade, cobertura de cenarios) antes de
`create-tasks` — nao valida implementacao (ainda nao existe codigo desta
feature).
**Created**: 2026-08-06
**Feature**: [spec.md](../spec.md) | [plan.md](../plan.md) | [research.md](../research.md)
**Numeracao**: CHK001–CHK018 (IDs unicos por feature; continuam em `security.md`)

## Completude

- [x] CHK001 - O requisito de opt-in (FR-006) amarra a captura avulsa a um
  mecanismo de configuracao ja existente, sem introduzir um segundo opt-in
  paralelo e potencialmente inconsistente? [Completude, Spec §FR-006] {auto}
  — FR-006: "habilitada pela mesma configuracao nativa de telemetria local
  do Claude Code".
- [ ] CHK002 - Existe requisito de retencao/expurgo para os artefatos
  persistidos (sidecar TSV por processo/segmento + linhas em
  `loose_usage`), dado que a captura e continua e sem limite superior de
  volume declarado? [Completude, Gap] {auto} — nao encontrado: `grep -rniE
  "retenc|limpeza|expira|cleanup|purge|ttl|delete"
  docs/specs/loose-usage-capture/` so retorna spec.md linha 215, que trata
  apenas de "TTL de token externo" como N/A ("a feature ... nao depende de
  token externo com TTL") — nao aborda o ciclo de vida dos proprios dados
  de consumo capturados. `plan.md` §Scale/Scope estima "dezenas por dia"
  mas nao projeta acumulo de longo prazo nem define poda.
- [x] CHK003 - O requisito de nao-degradacao da sessao do operador (NFR de
  performance/resiliencia) esta coberto explicitamente, e nao apenas
  implicito no design? [Completude, Spec §FR-007] {auto} — FR-007: "MUST
  NUNCA interromper, atrasar ou degradar a sessao avulsa do operador — a
  captura e estritamente melhor-esforco".
- [x] CHK004 - O fora-de-escopo (exposicao da comparacao no painel web) esta
  declarado explicitamente, evitando expansao implicita de escopo?
  [Completude, Spec §Clarifications Q3] {auto} — "exposicao no painel web
  fica fora do escopo desta feature", tambem repetido em FR-009.

## Clareza

- [x] CHK005 - A unidade de atribuicao "processo" (FR-002) tem definicao
  operacional citavel, ou fica so como rotulo sem criterio? [Clareza, Spec
  §FR-002 + research.md Decision 2] {auto} — a spec define o CONTRATO
  ("processo e projeto, nunca session_id"); o algoritmo de identidade
  (`process_key` = endpoint + project_path + owner_pid opcional) e
  deliberadamente deferido a `data-model.md` (`[PROPOSTA]`, "detalhe de
  implementacao") — divisao de camada SDD apropriada (spec = WHAT, plan/
  data-model = HOW), nao uma lacuna de clareza da spec.
- [x] CHK006 - O valor concreto do intervalo de captura periodica (FR-003)
  e deixado deliberadamente fora da spec (nao e dado factual, e policy de
  implementacao), em vez de ser uma omissao nao-intencional? [Clareza,
  Spec §FR-003 + research.md Decision 4] {auto} — research.md Decision 4:
  "O default de 300 s e **politica de design**, nao dado factual ...
  Ajustavel sem mudanca de contrato" — FR-003 exige a CAPACIDADE
  (capturar em intervalos periodicos), nao o valor.
- [x] CHK007 - "Melhor-esforco"/"nunca interromper" (FR-007) tem criterio
  operacional verificavel, em vez de ser um adjetivo vago sem contraparte
  testavel? [Clareza, Spec §FR-007] {auto} — o Independent Test/Acceptance
  Scenario da User Story 1 e a propria Edge Case "porta fechada, processo
  reiniciado" (linha 146-150: "a captura falha de forma silenciosa ...
  nunca bloqueia a sessao") tornam o criterio verificavel: falha =
  no-op silencioso, sessao sempre segue.

## Consistencia

- [x] CHK008 - O termo "consumo avulso" e usado de forma consistente em
  todo o `spec.md`, sem sinonimos concorrentes que fragmentem a
  terminologia? [Consistencia] {auto} — termo usado uniformemente nas 3
  User Stories, Edge Cases, FRs e Success Criteria; nenhuma ocorrencia de
  termo alternativo ("uso solto", "uso livre" etc.) encontrada na leitura
  integral do documento.
- [x] CHK009 - Os requisitos de nunca-fabricar-dado (FR-005 + Edge Case 1)
  sao consistentes entre si e com o Principio VI da constitution do
  projeto? [Constitution Alignment, Spec §FR-005 + Edge Cases item 1]
  {auto} — FR-005: "MUST reportar 'consumo nao medido' (nunca um valor
  zero)"; Edge Case 1 repete o mesmo criterio para o caso de opt-in
  ausente ("nunca um valor zero fabricado (Principio VI)") — mesma regra,
  duas superficies, sem contradicao.
- [x] CHK010 - Ha conflito entre a proibicao de usar `session_id` como
  identidade (FR-002) e alguma outra parte da spec que reintroduza
  `session_id` como chave de agregacao? [Conflict check, Spec §FR-002 +
  §Key Entities] {auto} — nenhuma das 3 Key Entities ("Registro de
  Consumo Avulso", "Janela de Consumo de Pipeline", "Comparativo de Uso
  do Projeto") referencia `session_id`; sem conflito dentro do proprio
  `spec.md`.

## Mensurabilidade (Success Criteria)

- [x] CHK011 - SC-002 e SC-004 usam threshold quantificado (100%) em vez
  de linguagem qualitativa ("a maioria", "quase todo")? [Mensurabilidade,
  Spec §SC-002, §SC-004] {auto} — ambos literalmente "100%".
- [x] CHK012 - SC-005 (comparacao avulso vs pipeline) e objetivamente
  verificavel apesar de nao ter um numero-alvo, por depender de uma
  condicao binaria testavel? [Mensurabilidade, Spec §SC-005] {auto} —
  criterio e "sem precisar cruzar manualmente dados de fontes separadas":
  testavel como pass/fail (existe um unico comando que apresenta as duas
  categorias lado a lado, ou nao existe).

## Cobertura de Cenarios

- [x] CHK013 - O gate deterministico de cobertura de requisitos confirma
  que TODAS as FRs tem pelo menos um cenario associado? [Gap-check via
  script] {auto} — `requirement-coverage.sh docs/specs/loose-usage-capture/spec.md`
  retornou `RESULT|docs/specs/loose-usage-capture/spec.md|requirements=10|covered=10|errors=0`
  (exit 0, zero `FINDING`).
- [x] CHK014 - O Edge Case de concorrencia (duas sessoes avulsas
  simultaneas no mesmo projeto) esta coberto, incluindo a regra de
  desambiguacao? [Cobertura, Spec §Edge Cases item 2] {auto} — "Cada
  processo e atribuido e contabilizado separadamente; a agregacao do
  projeto soma os processos, sem misturar identificadores de sessao".
- [x] CHK015 - Ha cenario cobrindo a transicao avulso→pipeline→avulso no
  MESMO processo (FR-010), nao apenas o caso avulso-puro ou
  pipeline-puro? [Cobertura, Spec §User Story 2 Acceptance Scenario 2]
  {auto} — Acceptance Scenario 2 da US2 cobre exatamente esse ciclo:
  "sessao avulsa que, no meio de sua execucao, da origem a uma execucao
  de pipeline ... quando a onda se encerra e a sessao avulsa continua,
  somente a janela fora da onda ativa volta a contar".

## Dependencias e Premissas

- [x] CHK016 - As premissas de ambiente (telemetria nativa habilitada,
  hooks provisionados) estao explicitadas como pre-condicao verificavel,
  em vez de implicitas? [Completude, Spec §FR-005 + Edge Cases itens 1 e
  3] {auto} — Edge Case 3 cobre explicitamente "hooks de captura nao
  estao provisionados no projeto (escopo `project` nunca instalado)" como
  premissa de cobertura distinta da premissa de opt-in (Edge Case 1).

## Itens de julgamento humano

- [ ] CHK017 - A janela de perda tolerada em encerramentos abruptos
  (implicita no intervalo de captura periodica — default proposto 300s em
  research.md Decision 4, nao fixado na spec) reflete o apetite de risco
  aceitavel do produto para consumo nao-capturado, ou deveria ser um
  requisito explicito de spec (ex.: "perda maxima tolerada de N minutos")
  antes de seguir para `create-tasks`? [Risco, Spec §SC-003 + research.md
  Decision 4] {humano}
- [ ] CHK018 - A ausencia de politica de retencao/expurgo (CHK002) e
  aceitavel como decisao consciente de escopo desta feature (ficando para
  uma iteracao futura), ou deve virar requisito obrigatorio nesta rodada
  antes de `create-tasks`? [Risco, CHK002] {humano}

## Notes

- Items `{auto}` ja vem resolvidos pelo agente (`[x]` com citacao, ou
  marcador `[Gap]` quando a checagem em si e verificavel mas revela
  ausencia).
- Items `{humano}` ficam `[ ]` aguardando decisao do dono do produto.
- CHK002 (retencao) e CHK017 (janela de perda tolerada) sao achados
  centrais desta rodada — ver `## Follow-up` no relatorio da onda.
