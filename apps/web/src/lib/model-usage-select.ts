/**
 * model-usage-select — normaliza a resposta do endpoint `/metrics/model-usage`
 * (schema v12, `wave_model_usage`) no view-model unico consumido tanto pelo
 * KPI compacto do dashboard principal (Overview) quanto pelo detalhe completo
 * da pagina de Metricas (Metrics) — garante SC-005 (mesmos valores nas duas
 * telas, mesma fonte de normalizacao).
 *
 * Funcao PURA (sem React/DOM), seguindo o precedente de `overview-select.ts`:
 * trava o CONTRATO de borda (camelCase ingles — ver
 * `contracts/model-usage-endpoint.md` e
 * `apps/server/src/routes/metrics.ts`), e concentra a regra `null` != `0`
 * (Principio III — Honestidade de Metrica) num unico lugar testavel.
 *
 * Ref: dec-038 (CHK005/1.2.2) — resumo compacto mostra top-3 modelos por
 * `costUsd`; detalhe completo em Metricas mostra `costUsd`+`totalTokens`+
 * `coverage`.
 */
import type { ModelUsageResult, ModelUsageEntry, ModelUsageCoverage, ModelUsageByStage } from '@cstk-panel/shared-types';

/** Limite de modelos exibidos no resumo compacto (dec-038 / CHK005). */
export const MODEL_USAGE_SUMMARY_LIMIT = 3;

export type ModelUsageState =
  /** tabela `wave_model_usage` ausente na base (schema v2-v11) — meta.reason='table-empty' */
  | 'degraded'
  /** tabela presente, zero linhas no recorte (projeto/periodo sem dado) */
  | 'empty'
  /** ha custo/tokens medidos no recorte */
  | 'measured';

export interface ModelUsageEntryVM {
  model: string;
  costUsd: number | null;
  totalTokens: number | null;
  waves: number;
}

export interface ModelUsageVM {
  state: ModelUsageState;
  /** todas as entradas, ordenadas por `costUsd` desc com `null` por ultimo (SC-001). */
  entries: ModelUsageEntryVM[];
  /** fatia `entries.slice(0, MODEL_USAGE_SUMMARY_LIMIT)` para o resumo compacto. */
  top: ModelUsageEntryVM[];
  coverage: ModelUsageCoverage;
}

const EMPTY_COVERAGE: ModelUsageCoverage = {
  wavesTotal: null,
  wavesWithModelUsage: null,
  wavesWithOtelCost: null,
};

/**
 * Ordena por `costUsd` desc, `null` sempre por ultimo — SC-001 exige que o
 * modelo de maior custo seja o primeiro item. Nao confia na ordem que o
 * servidor entrega (defensivo: o contrato exige a ordenacao, mas o
 * view-model nao deve quebrar se o backend regressar).
 */
function sortByCostDesc(entries: ModelUsageEntry[]): ModelUsageEntryVM[] {
  return [...entries]
    .map((e) => ({ model: e.model, costUsd: e.costUsd, totalTokens: e.totalTokens, waves: e.waves }))
    .sort((a, b) => {
      if (a.costUsd == null && b.costUsd == null) return 0;
      if (a.costUsd == null) return 1;
      if (b.costUsd == null) return -1;
      return b.costUsd - a.costUsd;
    });
}

/**
 * Deriva o estado (`degraded`/`empty`/`measured`) inteiramente da FORMA do
 * `data` — nao depende de `meta.degraded` ser repassado a parte (mesmo
 * padrao de `otelUsageState`). `coverage.wavesTotal == null` so acontece no
 * caminho degradado `table-empty` (contrato §Response 200 degradado,
 * invariante 1: tabela ausente -> os 3 campos de coverage vem `null`, nunca
 * `0`); zero linhas no recorte com tabela presente preserva `wavesTotal`
 * como numero (mesmo que `0`).
 */
function deriveState(entries: ModelUsageEntryVM[], coverage: ModelUsageCoverage): ModelUsageState {
  if (coverage.wavesTotal == null) return 'degraded';
  if (entries.length === 0) return 'empty';
  return 'measured';
}

export function selectModelUsage(raw: ModelUsageResult | null | undefined): ModelUsageVM {
  const byModel = raw?.byModel ?? [];
  const coverage = raw?.coverage ?? EMPTY_COVERAGE;
  const entries = sortByCostDesc(byModel);
  return {
    state: deriveState(entries, coverage),
    entries,
    top: entries.slice(0, MODEL_USAGE_SUMMARY_LIMIT),
    coverage,
  };
}

/**
 * Rotulo fixo de natureza do dado exigido pelo spec (US1: "rótulo explícito
 * da natureza do número — medido vs. proxy vs. derivado"). `costUsd`/
 * `totalTokens` aqui vem de `sum()` direto sobre telemetria real
 * (`wave_model_usage`) — MEDIDO, nunca estimado pelo painel (Principio III).
 */
export const MODEL_USAGE_NATURE_LABEL = 'medido' as const;

/** Texto curto de cobertura — mesmo padrao de `otelCoverageLabel` (OtelUsage.tsx). */
export function modelUsageCoverageLabel(coverage: ModelUsageCoverage): string {
  if (coverage.wavesTotal == null) return 'dado não coletado nesta base';
  return `${coverage.wavesWithModelUsage ?? 0} de ${coverage.wavesTotal} ondas medidas`;
}

/**
 * Um grupo de `byStage[]` particionado por etapa — grao (etapa) x [(modelo,
 * custoUsd, totalTokens)]. Consumido pelo detalhe completo de Metricas (3.3.1).
 */
export interface ModelUsageByStageGroup {
  stage: string;
  entries: ModelUsageByStage[];
}

/**
 * Particiona o array plano `byStage[]` (ja vem ordenado por `costUsd` desc,
 * `null` por ultimo — `getModelUsageByStage`, apps/server/src/db/queries/
 * metrics.ts) em grupos por `stage`, preservando a ordem de primeira
 * aparicao de cada etapa e a ordem relativa das linhas dentro do grupo. Regra
 * PURA (research.md Decision 5): nenhuma agregacao/reordenacao nova, so
 * particionamento — a soma por etapa nao e feita aqui porque o contrato ja
 * entrega uma linha por (etapa, modelo), sem duplicar `costUsd` entre grupos.
 *
 * `byStage: []` (correlacao onda x etapa nao resolvel no recorte, ou fonte
 * sem coluna `stages`) produz `[]` aqui tambem — nunca um valor inventado.
 */
export function groupModelUsageByStage(raw: ModelUsageByStage[] | null | undefined): ModelUsageByStageGroup[] {
  const rows = raw ?? [];
  const order: string[] = [];
  const byStage = new Map<string, ModelUsageByStage[]>();
  for (const r of rows) {
    if (!byStage.has(r.stage)) {
      byStage.set(r.stage, []);
      order.push(r.stage);
    }
    byStage.get(r.stage)!.push(r);
  }
  return order.map((stage) => ({ stage, entries: byStage.get(stage) ?? [] }));
}

/**
 * Rotulo usado quando `waves.stages` na origem NAO contem uma lista de etapas.
 * Observado no banco real (`~/.claude/cstk/knowledge.db` v12): uma onda gravou
 * um resumo narrativo de 2766 caracteres na coluna `stages` (as demais gravam
 * tokens como `execute-task`, `create-tasks`), e esse texto vazava inteiro como
 * cabecalho de grupo no card de custo por modelo.
 *
 * O custo da linha continua exibido (nunca descartado); so o CABECALHO passa a
 * dizer que a origem nao registrou etapa valida. Nao inventamos uma etapa para
 * a onda — Principio "jamais inventar dado".
 */
export const MODEL_USAGE_STAGE_INVALID_LABEL = 'etapa não registrada na origem';

/** Tamanho maximo plausivel de UM token de etapa (`execute-task-F3.1` = 17). */
const STAGE_TOKEN_MAX = 40;
/** Token de etapa: sem espacos, sem pontuacao de prosa. */
const STAGE_TOKEN_RE = /^[A-Za-z0-9][A-Za-z0-9._/-]*$/;

export interface ModelUsageStageLabel {
  /** Texto a exibir no cabecalho do grupo. */
  text: string;
  /** `false` quando o valor bruto nao e uma lista de etapas (dado poluido na origem). */
  valid: boolean;
  /** Valor bruto encurtado, para tooltip — nunca vai inteiro para o layout. */
  rawPreview: string;
}

const RAW_PREVIEW_MAX = 160;

/**
 * Normaliza o valor bruto de `stages` (lista separada por virgula) num rotulo
 * seguro de exibir. Aceita 1..N tokens; rejeita qualquer valor com espaco,
 * token acima de `STAGE_TOKEN_MAX` ou pontuacao de prosa — esses caem em
 * `MODEL_USAGE_STAGE_INVALID_LABEL` com o bruto preservado em `rawPreview`.
 *
 * Funcao PURA — sem React/DOM, testavel isoladamente.
 */
export function modelUsageStageLabel(stage: string): ModelUsageStageLabel {
  const raw = (stage ?? '').trim();
  const rawPreview = raw.length > RAW_PREVIEW_MAX ? `${raw.slice(0, RAW_PREVIEW_MAX)}…` : raw;
  const tokens = raw.split(',').map((t) => t.trim()).filter((t) => t.length > 0);
  const valid =
    tokens.length > 0 &&
    tokens.every((t) => t.length <= STAGE_TOKEN_MAX && STAGE_TOKEN_RE.test(t));
  return valid
    ? { text: tokens.join(', '), valid: true, rawPreview }
    : { text: MODEL_USAGE_STAGE_INVALID_LABEL, valid: false, rawPreview };
}
