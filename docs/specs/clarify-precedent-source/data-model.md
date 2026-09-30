# Data Model: clarify-precedent-source

Nenhuma tabela, coluna ou arquivo de estado novo. A feature le entidades
existentes da `knowledge.db` e acrescenta um tipo de evento e campos
opcionais em contratos JSON trocados entre orquestrador e answerer.

## Entity: Precedent (somente leitura, derivado da `knowledge.db`)

Projecao de `blocks` (schema lido de `~/.claude/cstk/knowledge.db`) +
etapa via `decisions`. Nunca escrito pela feature.

| Campo (saida) | Origem | Notas |
|---|---|---|
| `ref` | `blocks.project` + `/` + `blocks.feature` + `/` + `blocks.source_id` | Identificador rastreavel do bloqueio de origem (FR-007) |
| `project` | `blocks.project` | Rotulo de origem obrigatorio (FR-013) |
| `feature` | `blocks.feature` | Rotulo de origem obrigatorio (FR-013) |
| `stage` | `decisions.stage` via join em `blocks.decision_id` | `-` se o join nao resolver (FR-016) |
| `answered_at` | `blocks.answered_at` | Base da regra de recencia (FR-006/FR-014) |
| `similarity` | Jaccard calculado (research Decision 1) | 3 casas decimais |
| `question` | `blocks.question` (scrubbed na ingestao) | Truncado a 300 bytes |
| `answer` | `blocks.answer` (scrubbed na ingestao) | Truncado a 300 bytes |

**Elegibilidade** (FR-002): `blocks.status = 'respondido'` (valor gravado por
`bloqueios.sh respond`, L361) E `coalesce(answer,'') <> ''`. Sem filtro de
idade (FR-014) nem de projeto (FR-013).

**Validacoes**: `similarity >= min_similarity` (default 0.55); dedup por
`(question, answer, answered_at)`; no maximo `limit` (default 3) entradas e
`max_bytes` (default 2400) por pergunta.

### Relationships

- `blocks.decision_id` → `decisions.source_id` (mesmo `project`, `feature`,
  `execution_id`) — fornece `stage`.
- `knowledge_fts` (`type='block'`) → `blocks` pela chave natural
  `(project, feature, wave, source_id)` — prefiltro.

## Entity: CurrentQuestion (existente — contrato do asker)

Pergunta do asker (`pergunta_id`, `pergunta`, `opcoes_recomendadas`). O
texto `pergunta` e a UNICA entrada da consulta de precedentes (a calibracao
foi feita sobre o texto da pergunta).

## Entity: PrecedentReference (novo item em `referencias[]` do answerer)

| Campo | Tipo | Obrigatorio | Notas |
|---|---|---|---|
| `fonte` | string | sim | Valor `"precedent"` (chave legada `fonte` mantida) |
| `block_ref` | string | sim | `ref` do precedente |
| `project` | string | sim | |
| `feature` | string | sim | |
| `stage` | string | sim | |
| `answered_at` | string | sim | |
| `supports_option` | string ou null | sim | Rotulo da opcao; `null` se texto livre sem correspondencia |
| `scored` | boolean | sim | `true` so para o precedente que efetivamente deu o +1; `false` quando a opcao nao tem suporte positivo de `briefing`/terceira fonte (dec-027), perdeu na divergencia ou e dado factual |
| `applicability` | string | sim | Justificativa de aplicabilidade (FR-015 b), >= 20 chars |

## Entity: PrecedentOutcome (novos campos opcionais na resposta do answerer)

| Campo | Tipo | Quando presente |
|---|---|---|
| `precedent_divergence` | boolean | Sempre que houve precedente aplicavel |
| `divergent_precedents` | array de `{block_ref, project, feature, answered_at, answer_excerpt, supports_option}` | So com `precedent_divergence: true`; TODOS os divergentes recebidos; `answer_excerpt` <= 120 bytes (plan S-2) |
| `recommended_precedent` | `{block_ref, project, feature, supports_option}` | So com `pause_humano: true`, sem divergencia e com >= 1 precedente aplicavel com `supports_option` nao nulo |

Invariante: `divergent_precedents` e `recommended_precedent` sao mutuamente
exclusivos (FR-009).

## Entity: PrecedentConsultedEvent (novo `event_type` em `.events[]`)

| Campo | Valor |
|---|---|
| `event_type` | `precedent_consulted` |
| `timestamp` | ISO 8601 UTC |
| `description` | `stage=clarify question=<Qn> hits=<K>` ou `stage=clarify question=<Qn> hits=0 skipped=short-query` |

Sem corpo recuperado (FR-012). Um evento por pergunta consultada, inclusive
K=0.

### State Transitions (if applicable)

Nenhuma nova. O ciclo de vida do bloqueio humano (`aguardando` →
`respondido`) e o existente de `bloqueios.sh`.
