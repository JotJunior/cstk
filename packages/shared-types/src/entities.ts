/**
 * DTOs de dominio — entidades core do cstk-panel.
 * Fonte de verdade: data-model.md (schema v7 EN canonical da knowledge.db).
 * Ref: spec.md §Key Entities; plan.md §Convencoes de Borda
 *
 * IMPORTANTE — Convencoes de tipos:
 * - Colunas `TEXT` ISO-8601 → `string`; FE formata para "ha Xm"
 * - `INTEGER` 0/1 (lint_ok) → `boolean` via `=== 1` no mapper
 * - `INTEGER` contagem (touched_files) → `number` — NAO e array
 * - `TEXT waves.stages` → `string` — NAO array (string unica do schema v7)
 * - `score INTEGER` → union `0|1|2|3`
 * - Campos UNTRUSTED marcados com @untrusted no JSDoc — renderizar via textContent
 */

// ---------------------------------------------------------------------------
// ExecutionDTO — grao: 1 por execucao de orquestrador
// ---------------------------------------------------------------------------
export interface ExecutionDTO {
  project: string;
  feature: string;
  /** execution_id no schema v7 EN */
  executionId: string;
  status: 'em_andamento' | 'aguardando_humano' | 'concluida' | 'abortada' | null;
  terminationReason: string | null;
  currentStage: string | null;
  startedAt: string | null;
  finishedAt: string | null;
  durationSeconds: number | null;
  suggestedStack: string | null;
  wavesTotal: number | null;
  /** @custo proxy — rotular como "proxy: tool calls" na UI (Principio III) */
  toolCallsTotal: number | null;
  wallclockTotalSeconds: number | null;
  subagentsSpawned: number | null;
  maxDepth: number | null;
  decisionsTotal: number | null;
  humanBlocksTotal: number | null;
  skillSuggestionsTotal: number | null;
  toolkitIssuesOpened: number | null;
  /** nome da sessao de worktree de origem (schema v8 — recall-worktree-identity);
   *  null fora de sessao ou em bases v<8. @untrusted leve — renderizar via textContent */
  session: string | null;
}

// ---------------------------------------------------------------------------
// WaveDTO — grao: 1 por onda
// ---------------------------------------------------------------------------
export interface WaveDTO {
  wave: string;
  executionId: string;
  /** string unica — NAO converter para array (schema v7) */
  stages: string;
  startedAt: string | null;
  finishedAt: string | null;
  wallclockSeconds: number | null;
  /** custo proxy */
  toolCalls: number | null;
  terminationReason: string | null;
  nStages: number | null;
  nSkills: number | null;
  /** nome da sessao de worktree de origem (schema v8); null fora de sessao/bases v<8.
   *  @untrusted leve — renderizar via textContent */
  session: string | null;

  // --- Consumo de subagentes (schema v10 — cstk wave-token-metrics) ---------
  // Agregado por onda de `.waves[].agent_usage` do state.json. Semantica de
  // ausencia (verificada empiricamente contra `cstk recall --ingest` 5.25.0):
  //   - onda SEM `agent_usage` (execucao pre-v10 ou orquestrador antigo):
  //     TODOS os 9 campos null — inclusive agentSpawnsTotal ⇒ "nao coletado".
  //   - onda COM `agent_usage` mas sem nenhum spawn observavel:
  //     agentSpawnsTotal/agentSpawnsWithUsage preenchidos (ex: 2 e 0) e os
  //     campos de token null ⇒ "coletado, sem dado de uso".
  // Os dois casos NAO podem ser exibidos como zero (fabricacao — FR-009 do
  // cstk / Principio III). Ver `agentSpawnsWithUsage` para a regra de amostra.
  /** spawns de subagente observados na onda; null = metrica nao coletada */
  agentSpawnsTotal: number | null;
  /**
   * Quantos desses spawns trouxeram dado de uso. `agentSpawnsTotal -
   * agentSpawnsWithUsage` = spawns sem dado (tipicamente background/async).
   * INVARIANTE DE HONESTIDADE: quando menor que `agentSpawnsTotal`, os
   * totais de token sao AMOSTRA PARCIAL e a UI MUST exibir o denominador.
   */
  agentSpawnsWithUsage: number | null;
  /** soma de tokens dos spawns com dado; null = nenhum dado observado */
  agentTotalTokens: number | null;
  agentInputTokens: number | null;
  agentOutputTokens: number | null;
  agentCacheReadTokens: number | null;
  agentCacheCreationTokens: number | null;
  /** tool calls DENTRO dos subagentes — distinto de `toolCalls` (proxy da onda) */
  agentToolUseCount: number | null;
  agentDurationMs: number | null;
}

/**
 * Agregado de consumo de subagentes (schema v10) usado nos rollups de
 * projeto/feature e nas metricas. Todos os campos sao `null` quando nada foi
 * observado — nunca 0 por default (Principio III).
 */
export interface AgentUsageRollup {
  spawnsTotal: number | null;
  spawnsWithUsage: number | null;
  totalTokens: number | null;
  inputTokens: number | null;
  outputTokens: number | null;
  cacheReadTokens: number | null;
  cacheCreationTokens: number | null;
  toolUseCount: number | null;
  durationMs: number | null;
  /** ondas com `agent_usage` gravado (denominador de cobertura da amostra) */
  wavesWithUsage: number | null;
  /** ondas consideradas no recorte (com ou sem metrica coletada) */
  wavesTotal: number | null;
}

// ---------------------------------------------------------------------------
// DecisionDTO — grao: 1 por decisao auditada — campos textuais UNTRUSTED
// ---------------------------------------------------------------------------
export interface DecisionDTO {
  wave: string;
  executionId: string;
  stage: string | null;
  agent: string | null;
  choice: string | null;
  /**
   * Options considered before the choice (schema v7 EN — decisions.options).
   * Raw JSON array (e.g. `["haiku","sonnet","opus"]`), as recorded by the
   * ingestion from `.decisions[].options_considered`. `null` in bases
   * v<6 without the column (FR-V3-005). FE derives chips defensively and renders
   * via textContent — treat as structured content, never innerHTML.
   */
  options: string | null;
  score: 0 | 1 | 2 | 3 | null;
  /** @untrusted — renderizar via textContent, nunca innerHTML */
  context: string | null;
  /** @untrusted — renderizar via textContent, nunca innerHTML */
  rationale: string | null;
  /** @untrusted — renderizar via elemento mono/pre, nunca innerHTML */
  evidencia: string | null;
}

// ---------------------------------------------------------------------------
// TaskDTO — grao: 1 por tarefa executada
// ---------------------------------------------------------------------------
export interface TaskDTO {
  wave: string;
  executionId: string;
  /** descriptive task title (schema v7 EN); '' in pre-v3 bases or when absent.
   *  @untrusted leve — texto livre (passa por secrets-filter na ingestao);
   *  renderizar via textContent. */
  title: string;
  outcome: 'pass' | 'fail' | null;
  testsRun: number | null;
  testsPassed: number | null;
  /** mapper: INTEGER 0/1 → boolean via === 1 */
  lintOk: boolean | null;
  /** contagem, NAO array (INTEGER no schema v7) */
  touchedFilesCount: number | null;
}

// ---------------------------------------------------------------------------
// EventDTO — grao: 1 por evento de timeline
// ---------------------------------------------------------------------------
export interface EventDTO {
  executionId: string;
  eventType: 'lock_contention' | 'validation_failed' | 'wave_retry' | 'schedule_wait' | 'recall_consulted';
  timestamp: string;
  /** @untrusted leve — renderizar via textContent */
  description: string | null;
}

// ---------------------------------------------------------------------------
// AlertSignalDTO — grao: 1 por alerta de orcamento/circular
// ---------------------------------------------------------------------------
export interface AlertSignalDTO {
  executionId: string;
  type: 'circular' | 'budget_breach';
  subtype: string | null;
  consumedValue: number | null;
  thresholdValue: number | null;
  /** @untrusted leve */
  description: string | null;
  wave: string;
}

// ---------------------------------------------------------------------------
// BlockDTO — grao: 1 por bloqueio humano — campos textuais UNTRUSTED
// ---------------------------------------------------------------------------
export interface BlockDTO {
  executionId: string;
  status: string | null;
  /** @untrusted — renderizar via textContent */
  question: string | null;
  /** @untrusted — renderizar via textContent */
  contextForAnswer: string | null;
  /** @untrusted — renderizar via textContent */
  answer: string | null;
  decisionId: string | null;
  triggeredAt: string | null;
  answeredAt: string | null;
  latencySeconds: number | null;
}

// ---------------------------------------------------------------------------
// SkillDTO — grao: 1 por invocacao de skill
// ---------------------------------------------------------------------------
export interface SkillDTO {
  executionId: string;
  skillName: string;
  decisionId: string | null;
  wave: string;
}

// ---------------------------------------------------------------------------
// RetroDTO — grao: 1 por retrospectiva
// ---------------------------------------------------------------------------
export interface RetroDTO {
  executionId: string;
  /** @untrusted leve */
  text: string | null;
  wave: string;
}

// ---------------------------------------------------------------------------
// FtsHitDTO — resultado de busca FTS5
// ---------------------------------------------------------------------------
export interface FtsHitDTO {
  /** @untrusted — conteudo indexado; renderizar via textContent */
  body: string;
  type: string;
  project: string;
  feature: string;
  wave: string;
  sourceId: string;
  sourceTs: string;
  /** score bm25 negativo (mais negativo = mais relevante) */
  rank: number;
  /**
   * Execucao de origem, resolvida pelo backend a partir de
   * (project, feature, wave, source_id) na tabela-fonte do tipo.
   * Ausente para tipos sem vinculo de execucao (ex.: memory).
   */
  executionId?: string | undefined;
}

// ---------------------------------------------------------------------------
// MemoryDTO — grao: 1 por arquivo .md de auto-memoria do Claude Code
// (schema v4, feature recall-memory-mirror). Tabela `memories`, chave (project, slug).
// Read-only: o painel apenas exibe; a fonte canonica sao os .md no disco.
// ---------------------------------------------------------------------------

/** Tipo derivado do prefixo do .md (FR-007 do produtor). */
export type MemoryType = 'index' | 'feedback' | 'project' | 'reference' | 'user';

export interface MemoryDTO {
  project: string;
  /** nome do .md sem extensao (ex: feedback_code_in_english) — compoe a chave natural */
  slug: string;
  type: MemoryType;
  /** @untrusted leve — 1a linha do .md (ja scrubbed na ingestao); renderizar via textContent */
  description: string | null;
  /** @untrusted — conteudo .md completo scrubbed; renderizar via textContent/pre, NUNCA innerHTML */
  body: string | null;
  /** path absoluto do .md original (rastreabilidade) */
  path: string | null;
  /** ISO 8601 UTC do momento da indexacao */
  indexedAt: string | null;
}

// ---------------------------------------------------------------------------
// SuggestionDTO — grao: 1 por sugestao de melhoria proposta pela IA
// (schema v5, feature recall-suggestions). Tabela `suggestions`, escopo por
// execucao (espelho de state.json `.sugestoes[]`). Chave natural (execucaoId,
// sourceId). Read-only: o painel apenas exibe; a fonte canonica e o state.json.
// ---------------------------------------------------------------------------

/** 3 severidades do produtor (suggestions.sh). Outro valor → null no mapper. */
export type SuggestionSeveridade = 'informativa' | 'aviso' | 'impeditiva';

export interface SuggestionDTO {
  executionId: string;
  /** id natural da sugestao (ex: sug-001) — compoe a chave (executionId, sourceId) */
  sourceId: string;
  /** skill alvo da melhoria proposta (ex: execute-task); '' quando ausente */
  affectedSkill: string | null;
  severity: SuggestionSeveridade | null;
  /** @untrusted — texto livre (scrubbed na ingestao); renderizar via textContent */
  diagnosis: string | null;
  /** @untrusted — texto livre (scrubbed na ingestao); renderizar via textContent */
  proposal: string | null;
  /** paths de referencia (scrubbed); array derivado do CSV `referencias` do DB.
   *  @untrusted leve — renderizar via textContent */
  referencias: string[];
  /** URL/numero da issue aberta no toolkit, ou null quando nao houver */
  issueOpened: string | null;
  /** ISO 8601 — `created_at` no state.json (source_ts no DB) */
  createdAt: string | null;
}

// ---------------------------------------------------------------------------
// FeatureDocDTO / FeatureDocsListDTO — doc-viewer (feature state-watchers-and-docs)
// grao: 1 por artefato de documentacao SDD visivel na pagina de uma feature —
// os da propria feature (spec/plan/tasks/...) e os de PROJETO que governam a
// feature (briefing, constitution).
// Fonte: filesystem (docs/specs/<feature>/ e raiz de docs/ do projeto), NAO a
// knowledge.db (Principio I).
// Ref: data-model.md Entity "Documentation Artifact"; contracts/docs-api.md
// ---------------------------------------------------------------------------

/** Etapa SDD que produz o artefato (mapa fixo — research.md Decision 8). */
export type FeatureDocStage =
  | 'briefing'
  | 'constitution'
  | 'specify'
  | 'plan'
  | 'checklist'
  | 'create-tasks';

/**
 * Raiz a que `fileName` e relativo — e, portanto, a que a leitura do conteudo
 * fica confinada (Decision 7):
 * - `feature`: `docs/specs/<feature>/` (artefatos da feature)
 * - `project`: raiz do projeto (briefing/constitution — governam TODAS as
 *   features, por isso aparecem em qualquer pagina de feature)
 */
export type FeatureDocScope = 'project' | 'feature';

/**
 * 1 artefato de documentacao. Usado tanto como item da listagem (sem
 * `content` — metadados apenas, FR-005/SC-002) quanto como resposta do
 * endpoint de conteudo de um artefato (`content` presente: string quando
 * `produced=true`, `null` quando `produced=false` — FR-007, nunca 404-erro).
 */
export interface FeatureDocDTO {
  stage: FeatureDocStage;
  /** identificador estavel do artefato no mapa fixo (ex: 'spec', 'plan', 'tasks'); nome de arquivo sanitizado quando `extra=true` */
  artifactId: string;
  /** raiz a que `fileName` e relativo (e a que a leitura fica confinada) */
  scope: FeatureDocScope;
  /** caminho relativo a raiz do `scope` (ex: 'spec.md', 'docs/constitution.md') */
  fileName: string;
  /** false quando o artefato do mapa fixo ainda nao foi gerado (FR-007) — nao e erro */
  produced: boolean;
  /** true quando o arquivo esta presente na arvore fora do mapa fixo (SC-002) */
  extra: boolean;
  /**
   * Markdown bruto do artefato — **UNTRUSTED** (Principio V, FR-010).
   * Ausente (`undefined`) na listagem (endpoint so retorna metadados).
   * `null` no endpoint de conteudo quando `produced=false`. Renderizar
   * exclusivamente via `MarkdownView` com HTML bruto desabilitado — nunca
   * `dangerouslySetInnerHTML` com HTML nao sanitizado.
   */
  content?: string | null;
}

export interface FeatureDocsListDTO {
  project: string;
  feature: string;
  artifacts: FeatureDocDTO[];
}

// ---------------------------------------------------------------------------
// Rollups para Overview (US1) e listas de Projects/Features (US3)
// ---------------------------------------------------------------------------

export interface ProjectRollup {
  project: string;
  totalExecutions: number;
  activeExecutions: number;
  completedExecutions: number;
  abortedExecutions: number;
  totalDecisions: number;
  /** custo proxy */
  totalToolCalls: number | null;
  totalWallclock?: number | null;
  openAlerts?: number;
  latestExecutionAt: string | null;
  /** consumo real de subagentes (schema v10); ausente/null em bases v<10 */
  agentUsage?: AgentUsageRollup | null;
}

export interface FeatureRollup {
  project: string;
  feature: string;
  totalExecutions: number;
  activeExecutions: number;
  completedExecutions: number;
  abortedExecutions: number;
  /** custo proxy */
  totalToolCalls?: number | null;
  totalWallclock?: number | null;
  totalDecisions?: number;
  totalWaves?: number | null;
  totalBlocks?: number;
  currentStage?: string | null;
  openAlerts?: number;
  latestStatus: 'em_andamento' | 'aguardando_humano' | 'concluida' | 'abortada' | null;
  latestExecutionAt: string | null;
  /** consumo real de subagentes (schema v10); ausente/null em bases v<10 */
  agentUsage?: AgentUsageRollup | null;
}

// ---------------------------------------------------------------------------
// Tipos de request/params compartilhados
// ---------------------------------------------------------------------------

export interface PaginationParams {
  limit: number;
  offset: number;
}

export type PeriodParam = '24h' | '7d' | '30d' | 'all';

export type ScoreParam = 0 | 1 | 2 | 3;

export interface SearchParams extends PaginationParams {
  q: string;
  type?: string;
  project?: string;
  feature?: string;
}
