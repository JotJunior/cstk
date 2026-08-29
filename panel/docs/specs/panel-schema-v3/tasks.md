# Tasks: panel-schema-v3

**Spec**: `./spec.md` · **Plan**: `./plan.md`

Legenda: `[ ]` pendente · `[x]` concluída · `[~]` em andamento.

## Fase 1 — shared-types (contrato)

- [x] 1.1 `entities.ts`: `TaskDTO.titulo: string` (@untrusted); `EventDTO.eventType` += `recall_consulted`.
- [x] 1.2 `schemas/entities.ts`: `TaskDTOSchema.titulo`; `EventDTOSchema` enum += `recall_consulted`.
- [x] 1.3 Rebuild `dist/` do shared-types.

## Fase 2 — server (guard + env + queries + métrica)

- [x] 2.1 `config.ts`: `supportedSchemaVersions` de `CSTK_SCHEMA_VERSIONS` (default `2,3`). [FR-V3-001]
- [x] 2.2 `db/open.ts`: param `supported`; check `Set.has`; default `['2','3']`. [FR-V3-001/002]
- [x] 2.3 `lib/envelope.ts`: `meta.schemaVersion` dinâmico via `schema_meta`. [FR-V3-003]
- [x] 2.4 `db/queries/tasks.ts` + `cross.ts`: `titulo` com `hasColumn` tolerante a v2. [FR-V3-005]
- [x] 2.5 `mappers/task.ts`: mapear `titulo` (default `''`). [FR-V3-004]
- [x] 2.6 `mappers/event.ts`: allowlist += `recall_consulted`. [FR-V3-006]
- [x] 2.7 `db/queries/metrics.ts`: `getRecallConsultations` (total/produtivas/vazias). [FR-V3-007]
- [x] 2.8 `routes/metrics.ts`: `GET /metrics/recall-consultations`. [FR-V3-007]
- [x] 2.9 `routes/tasks.ts`: `titulo` no mapeamento cross inline.
- [x] 2.10 Rotas: passar `config.supportedSchemaVersions` ao `openDb`.

## Fase 3 — web (UI)

- [x] 3.1 `lib/hooks.ts`: `useMetric` union += `recall-consultations`.
- [x] 3.2 `screens/Tasks.tsx`: `titulo` como identidade (fallback `feature·onda`). [FR-V3-009]
- [x] 3.3 `screens/ExecutionDetail.tsx`: coluna título no `TasksPanel`; `EVENT_META` += `recall_consulted`. [FR-V3-009]
- [x] 3.4 `screens/Incidents.tsx`: excluir `recall_consulted`. [FR-V3-008]
- [x] 3.5 `screens/Metrics.tsx`: card "Consultas ao histórico". [FR-V3-007]

## Fase 4 — fixture & testes

- [x] 4.1 `scripts/migrate-fixture-v3.mjs`: migra fixture in-place p/ v3 (titulo + recall_consulted). [FR-V3-010]
- [x] 4.2 `scripts/create-fixture.mjs`: aceitar `'2'|'3'`.
- [x] 4.3 `open.test.ts`: v3-ok + versão não suportada → mismatch. [T1/T3]
- [x] 4.4 `mappers.test.ts`: titulo + recall_consulted. [T4/T6]
- [x] 4.5 parity tests: `TaskDTO.titulo`; schema_version.
- [x] 4.6 Rodar suíte completa (`npm test`) verde. [SC-V3-005]

## Fase 5 — docs

- [x] 5.1 `data-model.md`: schema_version 2|3 via env; `tasks.titulo`; `recall_consulted`.
- [x] 5.2 `data-gaps.md`: P1·#3 (`titulo`) resolvido em v3.
