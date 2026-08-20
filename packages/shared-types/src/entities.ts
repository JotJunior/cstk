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

  // --- Consumo medido por telemetria OTel (schema v11 — cstk 5.30.0) --------
  // Fonte DISTINTA dos campos `agent*` acima, nao um refinamento deles:
  //   - `agent*` vem do hook de spawn e so enxerga o que cada subagente
  //     devolve — o consumo do PROPRIO orquestrador nunca aparece la;
  //   - `otel*` vem dos contadores do Claude Code, incrementados a cada API
  //     request, entao cobrem main + subagente.
  // Os dois NAO se somam e nao se substituem em auditoria: a UI prefere o
  // OTel quando presente por ser mais completo, e mantem `agent*` como fonte
  // de detalhe por spawn. null = onda sem coleta OTel (telemetria desligada,
  // execucao anterior a 5.28.0 ou base v<11) — nunca zero.
  /** custo total da onda em USD; fracionario (ex: 0.098485) */
  otelCostUsd: number | null;
  /** fatia do custo atribuida ao loop principal (query_source=main) */
  otelCostMainUsd: number | null;
  /** fatia do custo atribuida a subagentes (query_source=subagent) */
  otelCostSubagentUsd: number | null;
  /** tokens totais da onda (input+output+cache), todas as origens */
  otelTotalTokens: number | null;
  /** tokens atribuidos a subagentes */
  otelSubagentTokens: number | null;

  // --- Breakdown de tokens por FONTE x TIPO (schema v12 — cstk 5.33.0) ------
  // Origem: `otel_usage.by_source.{main,subagent}.{input,output,cache_read,
  // cache_creation}`. Refina (nao substitui) `otelTotalTokens`/
  // `otelSubagentTokens`: responde quanto do consumo foi contexto RELIDO de
  // cache e quanto foi token novo — a diferenca entre uma onda cara e uma onda
  // longa. Os lados main e subagente sao coletados de forma INDEPENDENTE: onda
  // com subagente preenchido e main null e caso real da base, nao anomalia.
  otelMainInputTokens: number | null;
  otelMainOutputTokens: number | null;
  otelMainCacheReadTokens: number | null;
  otelMainCacheCreationTokens: number | null;
  otelSubagentInputTokens: number | null;
  otelSubagentOutputTokens: number | null;
  otelSubagentCacheReadTokens: number | null;
  otelSubagentCacheCreationTokens: number | null;
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

/**
 * Agregado de consumo medido por telemetria OTel (schema v11) usado nos
 * rollups de projeto/feature, no /overview e nas metricas.
 *
 * Diferente de `AgentUsageRollup`, aqui HA valor monetario: o custo em USD e
 * calculado pelo proprio Claude Code e apenas somado pelo painel — nao ha
 * tabela de preco embutida nem estimativa local. Todos os campos sao `null`
 * quando nada foi coletado no recorte; `wavesWithOtel/wavesTotal` dao a
 * cobertura para que um total parcial nunca seja apresentado como completo.
 */
export interface OtelUsageRollup {
  /** custo total em USD no recorte; null = nao coletado */
  costUsd: number | null;
  costMainUsd: number | null;
  /** fatia de subagente — a parte que `AgentUsageRollup` nao enxerga */
  costSubagentUsd: number | null;
  totalTokens: number | null;
  subagentTokens: number | null;
  /** ondas com metrica OTel coletada (denominador de cobertura) */
  wavesWithOtel: number | null;
  /** ondas consideradas no recorte (com ou sem metrica coletada) */
  wavesTotal: number | null;

  // --- Breakdown por fonte x tipo (schema v12) ------------------------------
  // Soma das 8 colunas `otel_{main,subagent}_*` das ondas do recorte.
  mainInputTokens: number | null;
  mainOutputTokens: number | null;
  mainCacheReadTokens: number | null;
  mainCacheCreationTokens: number | null;
  subagentInputTokens: number | null;
  subagentOutputTokens: number | null;
  subagentCacheReadTokens: number | null;
  subagentCacheCreationTokens: number | null;
  /**
   * DOIS denominadores separados, um por lado do breakdown — main e subagente
   * sao coletas independentes e divergem na base real. Um unico numero de
   * cobertura apresentaria como medido um lado que nunca foi coletado.
   */
  wavesWithMainBreakdown: number | null;
  wavesWithSubagentBreakdown: number | null;
}

// ---------------------------------------------------------------------------
// ModelUsage DTOs — custo/tokens REAIS por modelo (schema v12,
// `wave_model_usage`, cstk 5.33.0). Grao onda x modelo — distinto de
// `OtelUsageRollup` (grao onda) e de `model-mix` (DERIVADO de
// `decisions.choice`, sem custo/tokens).
// Ref: contracts/model-usage-endpoint.md; data-model.md Parte B.
// ---------------------------------------------------------------------------

/**
 * Uma linha do breakdown por modelo, ja agregada no recorte pedido.
 *
 * `model` e a string BRUTA do OTel (ex.: `claude-sonnet-5`, `claude-opus-5[1m]`),
 * sem normalizacao — dominio distinto de `MODEL_COLOR`/`MODEL_ORDER` do painel,
 * que chaveiam por `decisions.choice`. Linhas com `model IS NULL` na origem
 * chegam aqui com o rotulo literal `'(desconhecido)'`, nunca sao descartadas.
 * Acima do limite de cardinalidade (10), os excedentes sao agregados na linha
 * `'(outros)'` (FR-003(c)).
 */
export interface ModelUsageEntry {
  model: string;
  /** `sum(cost_usd)`. MEDIDO. null = nao medido; 0 = medido e deu zero */
  costUsd: number | null;
  /** `sum(total_tokens)`. MEDIDO */
  totalTokens: number | null;
  /** ondas distintas que contribuiram para este modelo */
  waves: number;
}

/**
 * Recorte adicional por etapa do pipeline (correlacao `wave_model_usage` x
 * `waves`). `[]` quando a correlacao nao resolve dado confiavel — nunca um
 * valor derivado por suposicao.
 */
export interface ModelUsageByStage {
  stage: string;
  model: string;
  costUsd: number | null;
  totalTokens: number | null;
}

/**
 * Cobertura da amostra — 3 denominadores INDEPENDENTES, nunca fundidos
 * (research.md Decision 3): o custo por onda (`otel_cost_usd`) e o breakdown
 * por modelo (`wave_model_usage`) divergem no banco real. No estado
 * degradado (tabela ausente), os 3 campos sao `null`, nunca `0`.
 */
export interface ModelUsageCoverage {
  wavesTotal: number | null;
  wavesWithModelUsage: number | null;
  wavesWithOtelCost: number | null;
}

/** Corpo de `data` de `GET /api/v1/metrics/model-usage`. */
export interface ModelUsageResult {
  /** ordenado por `costUsd` desc, `null` por ultimo (SC-001) */
  byModel: ModelUsageEntry[];
  byStage: ModelUsageByStage[];
  coverage: ModelUsageCoverage;
}

// ---------------------------------------------------------------------------
// LooseUsage DTOs — consumo AVULSO (schema v13, tabela `loose_usage`,
// cstk 6.6.0): tokens/custo de sessoes interativas comuns do Claude Code,
// FORA de qualquer execucao agente-00c/feature-00c. Grao processo x segmento
// x modelo — sem `feature`/`wave`/`execution_id` por construcao (preencher
// seria fabricar dado). Captura e OPT-IN (hook posttooluse-loose-usage):
// ausencia de linhas NAO significa ausencia de consumo.
// Ref: ../cstk/docs/specs/loose-usage-capture/data-model.md.
// ---------------------------------------------------------------------------

/** Uma linha do rollup por projeto do consumo avulso. */
export interface LooseUsageProjectEntry {
  project: string;
  /** paridade com `executions.target_project_path`; null quando nao capturado */
  projectPath: string | null;
  /** `sum(cost_usd)`. MEDIDO. null = nao medido; 0 = medido e deu zero */
  costUsd: number | null;
  totalTokens: number | null;
  /** processos (janelas/terminais) distintos observados */
  processes: number;
  /** segmentos avulsos distintos que contribuiram */
  segments: number;
  /** segmentos ainda ABERTOS — valores desses ainda em captura (parciais) */
  openSegments: number;
  lastCapturedAt: string | null;
}

/** Uma linha do rollup por modelo do consumo avulso (rotulo BRUTO do OTel). */
export interface LooseUsageModelEntry {
  model: string;
  costUsd: number | null;
  totalTokens: number | null;
  segments: number;
}

/**
 * Um lado da comparacao avulso x pipeline (FR-009 do cstk): agregacao lado a
 * lado por categoria, nunca JOIN linha a linha (granularidades diferentes).
 */
export interface LooseUsageComparisonSide {
  costUsd: number | null;
  totalTokens: number | null;
  /** `SUM(cost_usd)/SUM(total_tokens)*1e6`; null quando a soma de tokens e 0/NULL */
  blendedCostPerMtok: number | null;
}

export interface LooseUsageComparison {
  /** consumo avulso (`loose_usage`) */
  loose: LooseUsageComparisonSide;
  /** consumo de pipeline (`wave_model_usage`, v12); 3x null em base sem a tabela */
  pipeline: LooseUsageComparisonSide;
}

/**
 * Cobertura da amostra avulsa. No estado degradado (tabela `loose_usage`
 * ausente, base v2-v12) TODOS os campos sao null, nunca 0. Tabela presente e
 * vazia => contagens 0 legitimas (captura opt-in desligada ou sem uso).
 */
export interface LooseUsageCoverage {
  rowsTotal: number | null;
  segmentsTotal: number | null;
  /** segmentos abertos = medicao ainda em andamento (parcial, nao final) */
  segmentsOpen: number | null;
  processes: number | null;
  projects: number | null;
  lastCapturedAt: string | null;
}

/** Corpo de `data` de `GET /api/v1/metrics/loose-usage`. */
export interface LooseUsageResult {
  /** ordenado por `costUsd` desc, `null` por ultimo */
  byProject: LooseUsageProjectEntry[];
  byModel: LooseUsageModelEntry[];
  comparison: LooseUsageComparison;
  coverage: LooseUsageCoverage;
}

// ---------------------------------------------------------------------------
// PlanUsage DTOs — gauge `rate_limits` da CONTA (schema v14, tabela
// `plan_usage`, cstk 7.2.0).
//
// Dimensao NOVA no painel: nao e custo (USD) nem consumo (tokens), e quanto do
// PLANO ja foi gasto em duas janelas independentes. Um projeto pode custar
// pouco em USD e ainda assim esgotar a janela de 5h — sao eixos diferentes.
// Origem: hook `statusLine.command` (`cstk statusline install`), append-only,
// fora de qualquer execucao 00c: sem feature/wave/execution_id por construcao.
// Ref: ../cstk/docs/specs/plan-usage-capture/data-model.md.
// ---------------------------------------------------------------------------

/**
 * Estado corrente de UMA janela do plano + extremos do recorte.
 *
 * `scope` chega como a string bruta da origem (`five_hour` | `seven_day`,
 * garantidos pelo CHECK da tabela). As duas janelas sao series DISTINTAS:
 * somar ou mediar uma com a outra nao produz numero com significado.
 */
export interface PlanUsageScopeState {
  scope: string;
  /** percentual (0..100) na captura mais recente; null = escopo sem valor */
  usedPercentage: number | null;
  /** epoch em SEGUNDOS do reset da janela (nao milissegundos, nao ISO) */
  resetsAt: number | null;
  /** ISO 8601 da captura mais recente */
  capturedAt: string | null;
  /** maior percentual observado no recorte; null se nenhuma captura tem valor */
  peakUsedPercentage: number | null;
  /** capturas no recorte — ja pos-throttle, entao conta MUDANCAS, nao renders */
  captures: number;
}

/** Um ponto da serie temporal de um escopo. */
export interface PlanUsagePoint {
  scope: string;
  capturedAt: string;
  usedPercentage: number | null;
}

/**
 * Cobertura da amostra. Tabela ausente (base v2-v13): TODOS os campos null,
 * nunca 0. Tabela presente e vazia: contagens 0 legitimas — a captura e opt-in
 * e "sem linha" significa sem medicao, jamais "plano em 0%".
 */
export interface PlanUsageCoverage {
  rowsTotal: number | null;
  scopes: number | null;
  sessions: number | null;
  projects: number | null;
  firstCapturedAt: string | null;
  lastCapturedAt: string | null;
}

/** Corpo de `data` de `GET /api/v1/metrics/plan-usage`. */
export interface PlanUsageResult {
  byScope: PlanUsageScopeState[];
  /** ordenada por escopo e depois por `capturedAt` asc (ordem de plotagem) */
  series: PlanUsagePoint[];
  coverage: PlanUsageCoverage;
  /** true quando a serie foi cortada no teto por escopo (mais recentes) */
  seriesTruncated: boolean;
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
  /**
   * Decision class (schema v15 — structural-decision-human-gate, cstk 8.6.0).
   * Closed enum `estrutural` | `operacional`; `null` = not declared (legacy
   * rows and bases v<15). Rendered defensively via textContent anyway.
   */
  decisionClass: string | null;
  /**
   * Structural axis (schema v15). Closed enum of structural axes (language/
   * runtime, stack, architecture, persistence, target environment, tier);
   * `null` when the decision is not structural or in bases v<15.
   */
  structuralAxis: string | null;
  /**
   * Id (`block-NNN`) of the answered human block that consents a structural
   * decision taken by an automated agent (schema v15); `null` otherwise.
   */
  humanConsentBlockId: string | null;
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
  /** consumo medido por telemetria OTel (schema v11); ausente/null em v<11 */
  otelUsage?: OtelUsageRollup | null;
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
  /** consumo medido por telemetria OTel (schema v11); ausente/null em v<11 */
  otelUsage?: OtelUsageRollup | null;
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
