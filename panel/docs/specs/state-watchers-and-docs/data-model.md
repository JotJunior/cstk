# Data Model: Watchers de Execução em Andamento e Visualização de Documentação

**Feature**: `state-watchers-and-docs` | **Phase**: 1 (Design) | **Date**: 2026-07-15

> Nenhuma tabela nova na `knowledge.db` (Principio I — read-only; FR-008 proíbe coluna
> nova). As entidades abaixo são **derivadas** de dados existentes ou **efêmeras**
> (em memória, no processo do server). Campos de DTO em `camelCase` (Convenções de
> Borda). Marcas **[PROPOSTA]** = shape net-new a validar na implementação.

## Entity: Observed Execution (Execução Observada)

Projeção das execuções em andamento sobre as quais o watcher atua. **Não é tabela
nova** — é a linha de `executions` filtrada por status ativo.

| Campo | Tipo | Fonte real | Notas |
|-------|------|-----------|-------|
| `project` | string | coluna `executions.project` | chave lógica; resolvida a caminho via Decision 1 |
| `feature` | string \| null | coluna `executions.feature` | null ⇒ layout agente-00c (Decision 3) |
| `executionId` | string | coluna `executions.execution_id` | lookup atual keia por `execution_id` (`apps/server/src/db/queries/executions.ts` `getExecution`) |
| `status` | enum | coluna `executions.status` | observável só quando ∈ `{em_andamento, aguardando_humano}` (FR-003) |
| `currentStage` | string \| null | coluna `executions.current_stage` | etapa corrente exibida |
| `session` | string \| null | coluna `executions.session` (schema v8) | worktree identity; usada na derivação de state-dir [PROPOSTA] |
| freshness | `{ mtime, maxIngestedAt }` | `computeFreshness()` (`apps/server/src/db/freshness.ts`) | indicador de frescor (FR-011) já existente |

**State transitions** (governam quando o watcher observa — FR-003):

```
em_andamento ─────────────► concluida    (para de observar)
     │                       abortada     (para de observar)
     └──► aguardando_humano ──► (segue observável) ──► concluida/abortada (para)
```

- Ativa (observada): `em_andamento`, `aguardando_humano`.
- Terminal (histórico, não observada): `concluida`, `abortada`, `null`.
- Regra de canonicalização de status: `normalizeStatus()` (mappers) — reusar, não
  reimplementar.

**Chave natural**: o código de lookup atual keia por `executionId` isolado
(`getExecution(db, executionId)`, `apps/server/src/db/queries/executions.ts`). Uma nota
de projeto (memória `cstk-panel-execution-id-not-globally-unique`) observa que
`execution_id` não é único entre projetos, logo a identidade segura é
`(project, executionId)` — o que importa aqui só para derivar o state-dir
(project+feature). Esta feature **não** muda o comportamento de lookup. (A chave de
dedup de linhas FTS na ingestão — `UNIQUE(project, feature, wave, source_id)`,
`docs/specs/cstk-panel/data-model.md:29` — é outra coisa, dono `cstk recall`.)

---

## Entity: Documentation Artifact (Artefato de Documentação)

Um documento gerado pela pipeline SDD, exibível na visão da feature. **Efêmero /
derivado do filesystem** — não persiste na knowledge.db. **[PROPOSTA]** (shape novo).

| Campo | Tipo | Notas |
|-------|------|-------|
| `stage` | enum SDD | `specify\|clarify\|plan\|checklist\|create-tasks` (Decision 8) |
| `artifactId` | string | identificador estável (ex.: `spec`, `plan`, `research`, `tasks`) |
| `fileName` | string | nome real do arquivo (ex.: `spec.md`) |
| `produced` | boolean | `false` ⇒ "ainda não produzido" (FR-007), nunca erro |
| `extra` | boolean | `true` para arquivos presentes fora do mapa fixo (SC-002) |
| `content` | string \| null | conteúdo markdown bruto UNTRUSTED; render seguro no cliente (Decision 6) |

**Regras**:
- `produced=false` quando o arquivo do mapa fixo (Decision 8) não existe no
  filesystem — resposta de sucesso sinalizando ausência, não 404-erro (FR-007).
- Leitura confinada a `<projectPath>/docs/specs/<feature>/` (Decision 7, FR-009).
- `content` só é servido para artefatos existentes; nunca interpolado como HTML
  (FR-010 / Principio V).

**Relacionamento**: N artefatos ↔ 1 feature (`project` + `feature`).

---

## Entity: Project Location (Localização de Projeto)

Entrada do mapeamento operador-mantido `project` → caminho absoluto (Decision 1).
**Configuração**, não dado de execução; não persiste na knowledge.db.

| Campo | Tipo | Notas |
|-------|------|-------|
| `project` | string | chave lógica (== `executions.project`) |
| `absolutePath` | string | canonicalizado via `path.resolve()` (anti-traversal) |

**Regras**:
- Resolvido por `resolveProjectPath(project)` [PROPOSTA], espelhando `resolveDbPath()`
  (env `CSTK_PROJECT_PATHS` > default vazio — Decision 1).
- `project` ausente no mapa ⇒ retorno `null` ⇒ execução tratada como **não
  observável** (degradação sinalizada, FR-012), nunca erro.

---

## Entity: Watcher Signature Cache (efêmero — idempotência FR-014)

Cache **em memória** no processo do server; keyed por state-dir. Não persiste
(Principio I). Suporta Decision 4.

| Campo | Tipo | Notas |
|-------|------|-------|
| `stateDir` | string (key) | `<projectPath>/.claude/{feature-00c-state/<feature>\|agente-00c-state}/` |
| `signature` | string | mtime ISO ou sha256 do `state.json` (Decision 4) |
| `lastIngestAt` | string (ISO) | quando o último `cstk recall --ingest` foi disparado |

**Regra de disparo (FR-014)**: dispara ingestão apenas se `signature` mudou desde
`lastIngestAt`. Reinicia a cada restart do server (aceitável — ingestão é upsert
idempotente).

---

## Degradação (FR-012) — estados de primeira classe (Principio II)

| Condição | Sinal | Nunca |
|----------|-------|-------|
| `project` sem entrada no mapa | não observável / degradado | 5xx |
| caminho do projeto inacessível (removido/permissão) | degradado no envelope (`meta.degraded`, `meta.reason`) | 5xx / tela quebrada |
| `cstk recall --ingest` falha (stderr/timeout) | log + degradado; watcher segue no próximo tick | crash do server |
| artefato do mapa ausente | `produced=false` ("ainda não produzido") | 404-erro |
| knowledge.db ausente/corrompida | `wrapDegraded(reason, dbPath)` (padrão existente) | 5xx |
