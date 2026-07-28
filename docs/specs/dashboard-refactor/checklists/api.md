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
- [x] CHK003 - É especificado, com limite numérico, o comportamento de
  cardinalidade do `byModel` quando houver muitos modelos distintos na
  fonte (análogo ao truncamento top-10 + "Outros" definido para etapas em
  FR-006/007/008)? [Completude, Gap] {auto}
  Resolvido (FASE 1, tasks.md 1.1.1): FR-003(c) fixa limite de 10 modelos
  nomeados + bucket `'(outros)'`, mesmo padrão numérico de FR-006/007/008.

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
- [x] CHK007 - O contrato deixa claro que `costUsd`/`totalTokens` usam
  `NULL` (não medido) distinto de `0` (medido e zerado) — e essa distinção
  de três estados (sem dado / zero real / não aplicável) está refletida em
  algum requisito do spec.md, não apenas no contrato de plano? [Clareza,
  Ambiguity] {humano}
  Resolvido (FASE 1, tasks.md 1.1.2, dec-037): mantido no nível de
  abstração atual — spec.md §Premissas e Notas de Escopo confirma que a
  intenção (Edge Cases + FR-005, "nunca zero") já rastreia o requisito de
  produto; o detalhe de tipo `NULL`≠`0` permanece no contrato (Invariante
  1), artefato correto para esse nível de detalhe.

## Consistência entre Rotas

- [x] CHK008 - Os endpoints usados para o card de mix de modelos por etapa
  (`model-mix-by-stage`, sem `project`/`period`) e para o card de uso por
  modelo (`model-usage`, com `project`/`period`) produzem experiência
  consistente de filtro entre os dois cards da mesma tela de Métricas —
  ou o spec.md assume, sem declarar, que apenas o card novo é filtrável?
  [Ambiguity, Spec §SC-005, FR-009] {humano}
  Resolvido (FASE 1, tasks.md 1.1.3, dec-037): assimetria aceita como
  está — spec.md §Premissas e Notas de Escopo declara que FR-009 só exige
  contexto de etapa, não paridade de filtro; estender
  `model-mix-by-stage` fica fora do escopo desta feature.
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

- [x] CHK012 - O escopo de segurança do endpoint (sem autenticação, sem
  rate-limit, uso local single-user) é uma decisão de produto documentada
  no próprio spec.md — ou só existe como "risco aceito" no plano de
  implementação, fora do artefato rastreável de requisitos? [Ambiguity,
  Gap] {humano}
  Resolvido (FASE 1, tasks.md 1.1.4, dec-037): spec.md §Premissas e Notas
  de Escopo formaliza a herança da premissa já ratificada em
  `docs/constitution.md` §Padrões de Segurança e Qualidade (localhost,
  sem auth real, sem RBAC/multi-tenant no MVP).
- [x] CHK013 - O requisito de somente-leitura (FR-011) é inequívoco o
  suficiente para vedar qualquer verbo HTTP além de `GET` no endpoint
  novo, sem margem para interpretação de "leitura" incluir upsert de
  cache/log? [Clareza, Spec §FR-011] {auto}
  Satisfeito: FR-011 é MUST literal ("nenhuma mudança ... introduz
  escrita, edição ou mutação de dados na fonte"); o contrato reforça com
  Invariante 2 e o gate `lint:readonly-check`.

## Rastreabilidade de Nomenclatura (pt/en)

- [x] CHK014 - O spec.md declara, como requisito ou ao menos como nota de
  escopo, que o payload legado com campo `modelo` (pt-BR, em
  `model-mix`/`model-mix-by-stage`) permanece inalterado por esta feature
  — para não ser confundido com uma inconsistência a corrigir aqui?
  [Consistência, Gap] {auto}
  Resolvido (FASE 1, tasks.md 1.1.5): spec.md §Premissas e Notas de
  Escopo espelha `contracts/existing-endpoints.md` — campo `modelo`
  permanece inalterado por esta feature.

## Notes

- Items `{auto}` já vêm resolvidos pelo agente (`[x]` com citação, ou
  marcador `[Gap]`/`[Ambiguity]` quando a evidência aponta lacuna real).
- Items `{humano}` ficam `[ ]` aguardando decisão do dono do produto —
  nenhum deles bloqueia a implementação; são refinamentos de rastreio.
- Marcar items concluídos com `[x]` conforme forem endereçados.
- Gate determinístico `requirement-coverage.sh` sobre `spec.md`: 11/11
  FRs com cenário associado, 0 findings (rodado 2026-07-28).
