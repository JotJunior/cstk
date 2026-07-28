# API Checklist: Reorganização do Dashboard Principal e Página de Métricas

**Purpose**: Validar a qualidade dos requisitos de API desta feature — o
endpoint novo `GET /api/v1/metrics/model-usage` (proposto em
`contracts/model-usage-endpoint.md`) e o consumo corrigido dos endpoints
existentes (`contracts/existing-endpoints.md`). Não testa implementação.
**Created**: 2026-07-28
**Feature**: [spec.md](../spec.md)

## Contratos e Schemas

- [x] CHK001 - São os requisitos de request/response definidos para o novo
  endpoint de uso por modelo (query params, shape de `byModel`/`byStage`/
  `coverage`)? [Completude, Spec §FR-003] {auto}
  Satisfeito: `contracts/model-usage-endpoint.md` documenta request e
  response 200/degradado completos, rotulado `[PROPOSTA]` onde inventado.
- [x] CHK002 - O endpoint novo reusa o parser de query já estabelecido
  (`parseUsageQuery`) em vez de introduzir um parser ad-hoc, mantendo
  consistência com os demais endpoints `otel-*`/`tokens-*`? [Consistência,
  Spec §FR-003, SC-005] {auto}
  Satisfeito: `model-usage-endpoint.md` §Request declara reuso explícito de
  `parseUsageQuery` (`metrics.ts:209`) e justifica a escolha por SC-005.
- [ ] CHK003 - É especificado, com limite numérico, o comportamento de
  cardinalidade do `byModel` quando houver muitos modelos distintos na
  fonte (análogo ao truncamento top-10 + "Outros" definido para etapas em
  FR-006/007/008)? [Completude, Gap] {auto}
  Gap: nenhum FR do spec.md limita a quantidade de modelos distintos
  exibidos em `byModel`. O gate de segurança do plano (Invariante 9,
  LOW — API4/LLM10) recomenda `LIMIT` + bucket `'(outros)'`, mas isso é
  uma mitigação de plano, não um requisito rastreável no spec.md.

## Rotulagem da Natureza do Dado

- [x] CHK004 - É a fonte do valor monetário (medido vs. estimado)
  explicitamente qualificada no requisito, evitando ambiguidade entre
  "custo por modelo" e o proxy de chamadas de ferramenta já existente?
  [Clareza, Spec §FR-003, FR-004] {auto}
  Satisfeito: FR-003(a) qualifica `otel_cost_usd` como "MEDIDO (não
  estimado, não inventado)"; FR-004 exige rótulo explícito de natureza.
- [x] CHK005 - O requisito de rotulagem de natureza (medido/proxy/derivado)
  se aplica a TODOS os valores exibidos, sem exceção documentada?
  [Completude, Spec §FR-004, SC-004] {auto}
  Satisfeito: SC-004 declara "100% dos valores ... sem exceção".
- [x] CHK006 - O requisito de não somar custo medido com o proxy de
  chamadas de ferramenta é suficientemente específico para impedir soma
  acidental entre grandezas distintas na implementação? [Consistência,
  Spec §FR-004] {auto}
  Satisfeito: FR-004 nomeia as duas grandezas explicitamente ("esforço do
  orquestrador vs. uso dos modelos"); Invariante 3 do contrato reforça.
- [ ] CHK007 - O contrato deixa claro que `costUsd`/`totalTokens` usam
  `NULL` (não medido) distinto de `0` (medido e zerado) — e essa distinção
  de três estados (sem dado / zero real / não aplicável) está refletida em
  algum requisito do spec.md, não apenas no contrato de plano? [Clareza,
  Ambiguity] {humano}
  O spec.md (Edge Cases, FR-005) fala em "sem dado" vs. dado presente, mas
  não formaliza a distinção `NULL`≠`0` como requisito — hoje ela só existe
  em `model-usage-endpoint.md` (Invariante 1). Decisão de produto: vale a
  pena elevar essa distinção para um FR explícito, ou o nível de
  abstração do spec.md (sem detalhe de tipo) já é suficiente?

## Consistência entre Rotas

- [ ] CHK008 - Os endpoints usados para o card de mix de modelos por etapa
  (`model-mix-by-stage`, sem `project`/`period`) e para o card de uso por
  modelo (`model-usage`, com `project`/`period`) produzem experiência
  consistente de filtro entre os dois cards da mesma tela de Métricas —
  ou o spec.md assume, sem declarar, que apenas o card novo é filtrável?
  [Ambiguity, Spec §SC-005, FR-009] {humano}
  `existing-endpoints.md` confirma que `model-mix-by-stage` "não aceita
  `period` nem `project`" — o spec.md não resolve explicitamente se essa
  assimetria de filtro entre os dois cards da mesma página é aceitável.
- [x] CHK009 - A ordenação de `byModel` (maior custo primeiro, `null` por
  último) é suficiente para satisfazer SC-001 (identificar o modelo de
  maior custo em menos de 10s) de forma objetivamente verificável?
  [Mensurabilidade, Spec §SC-001] {auto}
  Satisfeito: `model-usage-endpoint.md` §Campos declara a ordenação
  exigida; SC-001 é testável a partir dela sem ambiguidade adicional.

## Degradação e Error Handling

- [x] CHK010 - O requisito de degradação (FR-010, "Degradar, Nunca
  Quebrar") cobre tanto ausência da fonte na abertura do banco quanto
  exceção durante a leitura em query-time, sem deixar nenhum dos dois
  casos implícito? [Completude, Spec §FR-010] {auto}
  Satisfeito: FR-010 fala genericamente em "ausência OU erro na fonte de
  dados", cobrindo os dois casos; o detalhamento por caso concreto
  (tabela ausente, exceção mid-query, banco ausente, zero linhas) vive no
  contrato como refinamento, não como requisito adicional.
- [x] CHK011 - Existe distinção de requisito entre "métrica não coletada
  na fonte" (schema antigo) e "sem dado no período" (schema atual, filtro
  vazio) — ambos degradam sem erro, mas são estados semanticamente
  diferentes? [Cobertura, Spec §Edge Cases, FR-005] {auto}
  Satisfeito: Edge Cases distingue "execução anterior à coleta" de
  cobertura parcial (FR-005); o contrato formaliza os dois como linhas
  distintas da tabela de degradação, sem introduzir requisito não coberto
  pelo spec.

## Segurança e Superfície

- [ ] CHK012 - O escopo de segurança do endpoint (sem autenticação, sem
  rate-limit, uso local single-user) é uma decisão de produto documentada
  no próprio spec.md — ou só existe como "risco aceito" no plano de
  implementação, fora do artefato rastreável de requisitos? [Ambiguity,
  Gap] {humano}
  O spec.md não tem uma seção de escopo de segurança; a nota "Decisões de
  infraestrutura: N/A" cobre scheduling/criptografia/mutex, mas não
  menciona auth/rate-limit. O aceite de risco vive apenas em
  `model-usage-endpoint.md` (nota final) e no gate `owasp-security`
  (dec-025). Decisão de produto: formalizar essa premissa no spec.md
  evita redescoberta futura como "novo risco".
- [x] CHK013 - O requisito de somente-leitura (FR-011) é inequívoco o
  suficiente para vedar qualquer verbo HTTP além de `GET` no endpoint
  novo, sem margem para interpretação de "leitura" incluir upsert de
  cache/log? [Clareza, Spec §FR-011] {auto}
  Satisfeito: FR-011 é MUST literal ("nenhuma mudança ... introduz
  escrita, edição ou mutação de dados na fonte"); o contrato reforça com
  Invariante 2 e o gate `lint:readonly-check`.

## Rastreabilidade de Nomenclatura (pt/en)

- [ ] CHK014 - O spec.md declara, como requisito ou ao menos como nota de
  escopo, que o payload legado com campo `modelo` (pt-BR, em
  `model-mix`/`model-mix-by-stage`) permanece inalterado por esta feature
  — para não ser confundido com uma inconsistência a corrigir aqui?
  [Consistência, Gap] {auto}
  Gap parcial: o spec.md não menciona a divergência de nomenclatura
  `modelo`/`model`; ela só é documentada em
  `contracts/existing-endpoints.md` como "não alterada por esta feature".
  Risco baixo (é nota de escopo, não requisito funcional), mas ausente do
  artefato de requisitos rastreável.

## Notes

- Items `{auto}` já vêm resolvidos pelo agente (`[x]` com citação, ou
  marcador `[Gap]`/`[Ambiguity]` quando a evidência aponta lacuna real).
- Items `{humano}` ficam `[ ]` aguardando decisão do dono do produto —
  nenhum deles bloqueia a implementação; são refinamentos de rastreio.
- Marcar items concluídos com `[x]` conforme forem endereçados.
- Gate determinístico `requirement-coverage.sh` sobre `spec.md`: 11/11
  FRs com cenário associado, 0 findings (rodado 2026-07-28).
