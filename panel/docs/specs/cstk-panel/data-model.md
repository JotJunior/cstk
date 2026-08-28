# Data Model: cstk-panel

**Feature**: `cstk-panel`
**Fonte**: schema v2 da `knowledge.db` — verificado empiricamente via
`sqlite3 'file:~/.claude/cstk/knowledge.db?mode=ro&immutable=1'`.

> **Read-only absoluto**: este documento descreve apenas a *leitura* das tabelas
> existentes. O painel **não cria, altera nem migra** schema. As DDLs abaixo são
> as reais da base (não propostas).

## Convenção de tipos (mapper DB → DTO)

| SQLite (coluna) | DTO (TS) | Regra do mapper |
|-----------------|----------|-----------------|
| `TEXT` ISO-8601 | `string` | mantém ISO; FE formata para "há Xm" |
| `INTEGER` numérico | `number` | direto |
| `INTEGER` 0/1 (`lint_ok`) | `boolean` | `=== 1` |
| `INTEGER` contagem (`arquivos_tocados`) | `number` (`arquivosTocadosCount`) | **NÃO é array** — é contagem |
| `TEXT` lista (`waves.etapas`) | `string` | **NÃO array** — string única do schema v2 |
| `score INTEGER` | `0 \| 1 \| 2 \| 3` | union tipada |
| colunas de proveniência | omitidas dos DTOs de domínio | uso interno (freshness/dedup); só `ingested_at` agregado em `meta.freshness` |

Case style: colunas `snake_case` PT-BR → propriedades DTO `camelCase`
(`execucao_id` → `execucaoId`, `tool_calls_total` → `toolCallsTotal`). Mapeamento
**explícito** por função pura em `apps/server/src/mappers/*.ts` (sem ORM).

Colunas de proveniência presentes em **todas** as tabelas-fonte:
`project, feature, wave, execucao_id, source_ts, source_id, ingested_at`.
Chave natural de dedup: `UNIQUE(project, feature, wave, source_id)`.

---

## Entity: Execution (`executions`)

Grão: 1 por execução de orquestrador.

| Coluna | Tipo SQLite | DTO | Notas |
|--------|-------------|-----|-------|
| `project` | TEXT NOT NULL | `project: string` | proveniência (exposta — chave de navegação) |
| `feature` | TEXT NOT NULL | `feature: string` | idem |
| `execucao_id` | TEXT NOT NULL | `execucaoId: string` | id de navegação |
| `status` | TEXT | `status` | enum: `em_andamento \| aguardando_humano \| concluida \| abortada` |
| `motivo_termino` | TEXT | `motivoTermino: string \| null` | |
| `etapa_corrente` | TEXT | `etapaCorrente: string \| null` | etapa SDD |
| `iniciada_em` | TEXT | `iniciadaEm: string \| null` | ISO |
| `terminada_em` | TEXT | `terminadaEm: string \| null` | ISO |
| `duracao_segundos` | INTEGER | `duracaoSegundos: number \| null` | |
| `stack_sugerida` | TEXT | `stackSugerida: string \| null` | presente no schema real (não citado no briefing §8) |
| `ondas_total` | INTEGER | `ondasTotal: number \| null` | |
| `tool_calls_total` | INTEGER | `toolCallsTotal: number \| null` | **custo proxy** (rotular "proxy: tool calls") |
| `wallclock_total_segundos` | INTEGER | `wallclockTotalSegundos: number \| null` | |
| `subagentes_spawned` | INTEGER | `subagentesSpawned: number \| null` | |
| `profundidade_max` | INTEGER | `profundidadeMax: number \| null` | |
| `decisoes_total` | INTEGER | `decisoesTotal: number \| null` | |
| `bloqueios_humanos_total` | INTEGER | `bloqueiosHumanosTotal: number \| null` | |
| `sugestoes_skills_total` | INTEGER | `sugestoesSkillsTotal: number \| null` | |
| `issues_toolkit_abertas` | INTEGER | `issuesToolkitAbertas: number \| null` | |

Relacionamentos: 1 Execution → N Waves/Decisions/Tasks/Events/AlertSignals/
Bloqueios/Skills/Retros (via `execucao_id` + proveniência).

---

## Entity: Wave (`waves`)

Grão: 1 por onda.

| Coluna | Tipo | DTO | Notas |
|--------|------|-----|-------|
| `wave` | TEXT NOT NULL | `wave: string` | id da onda (ex: `onda-003`) |
| `etapas` | TEXT | `etapas: string` | **string única** (não array) |
| `inicio` | TEXT | `inicio: string \| null` | ISO |
| `fim` | TEXT | `fim: string \| null` | ISO |
| `wallclock_seconds` | INTEGER | `wallclockSeconds: number \| null` | |
| `tool_calls` | INTEGER | `toolCalls: number \| null` | custo proxy |
| `motivo_termino` | TEXT | `motivoTermino: string \| null` | enum de motivos de onda |
| `n_etapas` | INTEGER | `nEtapas: number \| null` | |
| `n_skills` | INTEGER | `nSkills: number \| null` | |

Alimenta `WavesTimeline` (US2).

---

## Entity: Decision (`decisions`) — UNTRUSTED

Grão: 1 por decisão auditada.

| Coluna | Tipo | DTO | Notas |
|--------|------|-----|-------|
| `wave` | TEXT | `wave: string` | |
| `etapa` | TEXT | `etapa: string \| null` | |
| `agente` | TEXT | `agente: string \| null` | |
| `escolha` | TEXT | `escolha: string \| null` | |
| `opcoes` | TEXT | `opcoes: string \| null` | **schema v6** — JSON array cru das opções consideradas; `null` em bases v<6 (FR-V3-005). Estruturado (sem scrub); FE deriva chips e destaca a escolhida |
| `score` | INTEGER | `score: 0\|1\|2\|3 \| null` | escala de cor na UI |
| `contexto` | TEXT | `contexto: string \| null` | **UNTRUSTED** — texto puro |
| `justificativa` | TEXT | `justificativa: string \| null` | **UNTRUSTED** — texto puro |
| `evidencia` | TEXT | `evidencia: string \| null` | **UNTRUSTED** — texto puro (fonte mono) |

Renderização: campos UNTRUSTED servidos crus; FE renderiza como text node (nunca
`dangerouslySetInnerHTML`). Lista paginada obrigatoriamente (FR-020, SC-008).

---

## Entity: Task (`tasks`)

Grão: 1 por tarefa.

| Coluna | Tipo | DTO | Notas |
|--------|------|-----|-------|
| `wave` | TEXT | `wave: string` | |
| `titulo` | TEXT | `titulo: string` | **schema v3**; título descritivo (heading do `tasks.md`). UNTRUSTED leve. Base v2 ou ausente → `''` (query projeta `'' AS titulo` via `hasColumn`) |
| `outcome` | TEXT | `outcome: 'pass' \| 'fail' \| null` | OutcomePill |
| `testes_rodados` | INTEGER | `testesRodados: number \| null` | |
| `testes_passados` | INTEGER | `testesPassados: number \| null` | |
| `lint_ok` | INTEGER (0/1) | `lintOk: boolean \| null` | **mapper: `=== 1`** |
| `arquivos_tocados` | INTEGER | `arquivosTocadosCount: number \| null` | **contagem, NÃO array** |

KPI pass-rate derivado de `outcome` (rotular como derivado se aproximado). A UI
usa `titulo` como identidade primária da task quando presente; senão cai em
`feature · onda`.

---

## Entity: Event (`events`)

Grão: 1 por incidente.

| Coluna | Tipo | DTO | Notas |
|--------|------|-----|-------|
| `event_type` | TEXT NOT NULL | `eventType` | enum: `lock_contention \| validation_failed \| wave_retry \| schedule_wait \| recall_consulted` |
| `timestamp` | TEXT NOT NULL | `timestamp: string` | ISO |
| `descricao` | TEXT | `descricao: string \| null` | UNTRUSTED leve; em `recall_consulted` carrega `etapa=… hits=N` |

`EventIcon` por `eventType`.

**`recall_consulted` (schema v3)**: evento informativo do read-back loop
(`cstk recall --context` no início de specify/plan), gravado **inclusive com
`hits=0`**. NÃO é incidente operacional → a tela **Incidentes o exclui**; vive
na métrica `recall-consultations` (tela Métricas). O mapper de eventos
reconhece o tipo (não cai no fallback `schedule_wait`).

---

## Entity: AlertSignal (`alert_signals`)

Grão: 1 por alerta.

| Coluna | Tipo | DTO | Notas |
|--------|------|-----|-------|
| `tipo` | TEXT NOT NULL | `tipo: 'circular' \| 'budget_breach'` | |
| `subtipo` | TEXT | `subtipo: string \| null` | |
| `valor_consumido` | INTEGER | `valorConsumido: number \| null` | BudgetGauge |
| `valor_threshold` | INTEGER | `valorThreshold: number \| null` | BudgetGauge |
| `descricao` | TEXT | `descricao: string \| null` | UNTRUSTED leve |
| `wave` | TEXT | `wave: string` | drill-down até a onda |

Severidade derivada de `valor_consumido / valor_threshold` (rotulada como derivada).

---

## Entity: Bloqueio (`bloqueios`) — UNTRUSTED

Grão: 1 por bloqueio humano.

| Coluna | Tipo | DTO | Notas |
|--------|------|-----|-------|
| `status` | TEXT | `status: string \| null` | |
| `pergunta` | TEXT | `pergunta: string \| null` | **UNTRUSTED** |
| `contexto_para_resposta` | TEXT | `contextoParaResposta: string \| null` | **UNTRUSTED** |
| `resposta` | TEXT | `resposta: string \| null` | **UNTRUSTED** |
| `decisao_id` | TEXT | `decisaoId: string \| null` | FK lógica → decisão |
| `disparado_em` | TEXT | `disparadoEm: string \| null` | ISO |
| `respondido_em` | TEXT | `respondidoEm: string \| null` | ISO |
| `latencia_segundos` | INTEGER | `latenciaSegundos: number \| null` | métrica human-latency |

---

## Entity: Skill (`skills`)

Grão: 1 por invocação.

| Coluna | Tipo | DTO | Notas |
|--------|------|-----|-------|
| `skill_name` | TEXT NOT NULL | `skillName: string` | |
| `decisao_id` | TEXT | `decisaoId: string \| null` | liga skill → decisão |
| `wave` | TEXT | `wave: string` | |

---

## Entity: Retro (`retros`)

Grão: 1 por retrospectiva. (Base atual: 0 linhas — tela deve degradar p/ vazio.)

| Coluna | Tipo | DTO | Notas |
|--------|------|-----|-------|
| `texto` | TEXT | `texto: string \| null` | UNTRUSTED leve |
| `wave` | TEXT | `wave: string` | |

---

## Entity: KnowledgeFTS (`knowledge_fts`) — UNTRUSTED

Tabela virtual FTS5. Grão: 1 espelho por item textual indexado.

| Coluna | Tipo FTS5 | DTO | Notas |
|--------|-----------|-----|-------|
| `body` | indexada | `body: string` | **UNTRUSTED** — corpo do match (texto puro) |
| `type` | UNINDEXED | `type: string` | tipo do item (ex: `decision`) |
| `project` | UNINDEXED | `project: string` | filtro/proveniência |
| `feature` | UNINDEXED | `feature: string` | filtro/proveniência |
| `wave` | UNINDEXED | `wave: string` | drill-down |
| `source_id` | UNINDEXED | `sourceId: string` | drill-down até a fonte |
| `source_ts` | UNINDEXED | `sourceTs: string` | ordenação secundária |

Busca: `MATCH ?` + `ORDER BY bm25(knowledge_fts)`. Resultado inclui `rank`
(score bm25). Sempre paginado (FR-020).

---

## Metadata: `schema_meta`

`key='schema_version' → value ∈ {'2','3'}`. O BE valida a versão contra o
**conjunto aceito** na abertura; fora do conjunto → degradação `schema-mismatch`
(não erro). O conjunto vem do env **`CSTK_SCHEMA_VERSIONS`** (CSV; default
`2,3`) — nunca hardcoded inline no guard (FR-V3-001). **Não exposto** como
entidade de domínio; surfaceia em `meta.schemaVersion` com a versão **real**
lida da base (FR-V3-003).

> **Schema v3** (cstk ≥ 4.2.0): aditivo e retro-compatível — coluna
> `tasks.titulo` + evento `recall_consulted`. Ver `docs/specs/panel-schema-v3/`.

---

## Mapeamento entidade → endpoint (resumo)

| Entidade | Endpoint(s) primário(s) |
|----------|------------------------|
| Execution | `/overview`, `/projects`, `/features`, `/executions/{id}` |
| Wave | `/executions/{id}/waves` |
| Decision | `/executions/{id}/decisions` |
| Task | `/executions/{id}/tasks`, `/tasks` |
| Event | `/executions/{id}/events`, `/events` |
| AlertSignal | `/executions/{id}/alerts`, `/alerts` |
| Bloqueio | `/executions/{id}/bloqueios`, `/metrics/human-latency` |
| Skill | `/executions/{id}/skills` |
| Retro | (agregada em detalhe de execução) |
| KnowledgeFTS | `/search` |
