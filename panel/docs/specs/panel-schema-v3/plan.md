# Implementation Plan: panel-schema-v3

**Spec**: `./spec.md` · **Feature base**: `cstk-panel`

## Abordagem

Mudança aditiva e cirúrgica nas 3 camadas (shared-types → server → web) + testes
e fixture. Nenhuma escrita na base de produção (Princípio I). O guard de schema
passa a ler versões aceitas de **config/env**, não de literal.

## Decisão de design: versões de schema via env var

Em vez de trocar `=== '2'` por `=== '3'` (que quebraria bases v2) ou por uma
lista hardcoded, a fonte de verdade do conjunto de versões aceitas é o env
`CSTK_SCHEMA_VERSIONS` (CSV), resolvido em `config.ts` como
`supportedSchemaVersions: string[]` (default `['2','3']`). Justificativa:

- **Retro-compat** (Princípio II): aceita v2 e v3 simultaneamente.
- **Operável**: um operador pode aceitar uma versão futura sem rebuild
  (`CSTK_SCHEMA_VERSIONS=2,3,4`) ou travar numa só (`=3`).
- **Testável**: `openDb(path, supportedSet)` recebe o conjunto por parâmetro;
  o default cobre chamadas de teste de 1 argumento (sem churn nos testes
  existentes).

`open.ts`: `openDb(dbPath, supported = DEFAULT_SUPPORTED_VERSIONS)`. As rotas
passam `config.supportedSchemaVersions`. O guard troca o check por
`!supported.has(schemaVersion)`.

`envelope.ts`: `meta.schemaVersion` passa a ser lido da base aberta
(`SELECT value FROM schema_meta WHERE key='schema_version'`), com fallback `'2'`
se ilegível (degradação já tratada à parte).

## Mudanças por arquivo

### shared-types (`packages/shared-types/src`)
- `entities.ts`: `TaskDTO.titulo: string` (@untrusted leve); `EventDTO.eventType`
  union += `'recall_consulted'`.
- `schemas/entities.ts`: `TaskDTOSchema` += `titulo: z.string()`;
  `EventDTOSchema.eventType` enum += `'recall_consulted'`.
- Rebuild `dist/` (`npm run build -w @cstk-panel/shared-types`).

### server (`apps/server/src`)
- `config.ts`: + `supportedSchemaVersions: string[]` de `CSTK_SCHEMA_VERSIONS`.
- `db/open.ts`: parâmetro `supported`; check por `Set.has`; const
  `DEFAULT_SUPPORTED_VERSIONS = ['2','3']`.
- `lib/envelope.ts`: `schemaVersion` dinâmico via `schema_meta`.
- `db/queries/tasks.ts`: `TaskRow.titulo`; SELECT tolerante (v2 sem coluna).
- `db/queries/cross.ts`: `CrossTaskRow.titulo`; idem.
- `mappers/task.ts`: mapear `titulo` (default `''`).
- `db/queries/metrics.ts`: `getRecallConsultations(db)` → `{ total, produtivas,
  vazias }` parseando `hits=(\d+)` da `descricao`.
- `routes/metrics.ts`: registrar `GET /metrics/recall-consultations`.
- `routes/tasks.ts`: incluir `titulo` no mapeamento inline cross.
- Rotas: `openDb(config.dbPath)` → `openDb(config.dbPath, config.supportedSchemaVersions)`.

### Tolerância a coluna ausente (v2)

`SELECT` com `titulo` falharia numa base v2 sem a coluna. Opções: (a) checar
existência da coluna via `PRAGMA table_info(tasks)` e montar o SELECT
condicionalmente; (b) `COALESCE` não resolve coluna inexistente. Escolha: **(a)**
— helper `hasColumn(db,'tasks','titulo')` cacheado por conexão; quando ausente,
projeta `'' AS titulo`. Mantém uma única forma de `TaskRow`.

### web (`apps/web/src`)
- `lib/hooks.ts`: `useMetric` name union += `'recall-consultations'`.
- `screens/Tasks.tsx`: `titulo` como identidade primária (fallback `feature·onda`).
- `screens/ExecutionDetail.tsx`: coluna Tarefa/título no `TasksPanel`;
  `EVENT_META` += `recall_consulted`.
- `screens/Incidents.tsx`: excluir `recall_consulted` da lista de incidentes.
- `screens/Metrics.tsx`: card "Consultas ao histórico" (total + produtivas/vazias).

### testes & fixture
- `apps/server/test/knowledge-fixture.db`: migrar in-place para v3 (script
  determinístico `scripts/migrate-fixture-v3.mjs`): `ALTER TABLE tasks ADD COLUMN
  titulo`, popular títulos sintéticos, inserir 2+ eventos `recall_consulted`
  (`hits=3` e `hits=0`), `schema_version='3'`.
- `scripts/create-fixture.mjs`: validação aceita `'2'|'3'`.
- `open.test.ts`: + caso v3-ok, + caso versão não suportada → mismatch.
- `mappers.test.ts`: + titulo no task mapper, + `recall_consulted` no event mapper.
- parity tests: `TaskDTO.titulo`; expectativas de schema_version.

### docs
- `docs/specs/cstk-panel/data-model.md`: contrato `schema_version` (2|3 via env),
  `tasks.titulo`, evento `recall_consulted`.
- `docs/specs/cstk-panel/data-gaps.md`: marcar P1·#3 (`titulo`) como resolvido em v3.

## Test Scenarios

| ID | Cenário | Camada |
|----|---------|--------|
| T1 | base v3 → ok, meta.schemaVersion='3' | open + envelope |
| T2 | base v2 → ok (retro-compat) | open |
| T3 | versão '99' → schema-mismatch | open |
| T4 | task com titulo → DTO.titulo preenchido | query+mapper |
| T5 | base v2 sem coluna titulo → DTO.titulo='' | query (hasColumn) |
| T6 | recall_consulted NÃO vira schedule_wait | event mapper |
| T7 | recall-consultations: produtivas+vazias=total | metrics |

## Riscos

- **SELECT titulo em base v2**: mitigado por `hasColumn` (PRAGMA).
- **dist/ desatualizado de shared-types**: rebuild obrigatório antes de typecheck.
- **Fixture migrada quebra testes existentes** (ex.: contagens de evento por
  tipo): conferir testes que contam eventos/tasks na fixture após migração.
