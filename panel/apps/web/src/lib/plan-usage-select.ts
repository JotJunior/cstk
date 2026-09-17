/**
 * plan-usage-select — normaliza a resposta do endpoint `/metrics/plan-usage`
 * (schema v14, `plan_usage`, cstk 7.2.0) no view-model do card do gauge de
 * plano. Funcao PURA (sem React/DOM), mesmo precedente de
 * `loose-usage-select.ts` / `model-usage-select.ts`.
 *
 * Dimensao NOVA no painel: nao e custo (USD) nem consumo (tokens), e quanto do
 * PLANO ja foi gasto em duas janelas independentes (`five_hour`, `seven_day`).
 * Um projeto pode gastar pouco em USD e ainda assim esgotar a janela de 5h.
 *
 * A captura e OPT-IN (`cstk statusline install`): tabela presente e vazia
 * significa "sem medicao", NUNCA "plano em 0%" — os dois estados nao podem
 * colapsar (Principio III).
 */
import type { PlanUsageResult, PlanUsageCoverage, PlanUsagePoint, PlanUsageScopeState } from '@cstk-panel/shared-types';

export type PlanUsageState =
  /** tabela `plan_usage` ausente na base (schema v2-v13) — meta.reason='table-empty' */
  | 'degraded'
  /** tabela presente, zero capturas no recorte (hook de statusline nao instalado) */
  | 'empty'
  /** ha gauge capturado no recorte */
  | 'measured';

export interface PlanUsageVM {
  state: PlanUsageState;
  /** um por janela, na ordem canonica (5h antes de 7d) */
  byScope: PlanUsageScopeState[];
  series: PlanUsagePoint[];
  coverage: PlanUsageCoverage;
  seriesTruncated: boolean;
}

const EMPTY_COVERAGE: PlanUsageCoverage = {
  rowsTotal: null,
  scopes: null,
  sessions: null,
  projects: null,
  firstCapturedAt: null,
  lastCapturedAt: null,
};

/**
 * Ordem canonica de exibicao — janela curta primeiro, que e a que costuma
 * estourar antes. Escopo desconhecido (o cstk pode adicionar outro) vai para o
 * fim em vez de sumir da tela.
 */
const SCOPE_ORDER = ['five_hour', 'seven_day'];

/** Rotulo humano da janela; escopo novo cai no proprio identificador bruto. */
export const SCOPE_LABEL: Record<string, string> = {
  five_hour: 'Janela de 5 horas',
  seven_day: 'Janela de 7 dias',
};

export function scopeLabel(scope: string): string {
  return SCOPE_LABEL[scope] ?? scope;
}

/**
 * Deriva o estado da FORMA do `data` (mesmo padrao dos irmaos):
 * `coverage.rowsTotal == null` so acontece no caminho degradado `table-empty`;
 * tabela presente e vazia preserva `rowsTotal` como numero (`0`).
 */
function deriveState(byScope: PlanUsageScopeState[], coverage: PlanUsageCoverage): PlanUsageState {
  if (coverage.rowsTotal == null) return 'degraded';
  if (byScope.length === 0) return 'empty';
  return 'measured';
}

export function selectPlanUsage(raw: PlanUsageResult | null | undefined): PlanUsageVM {
  const coverage = raw?.coverage ?? EMPTY_COVERAGE;
  const byScope = [...(raw?.byScope ?? [])].sort((a, b) => {
    const ia = SCOPE_ORDER.indexOf(a.scope);
    const ib = SCOPE_ORDER.indexOf(b.scope);
    return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib) || a.scope.localeCompare(b.scope);
  });
  return {
    state: deriveState(byScope, coverage),
    byScope,
    series: raw?.series ?? [],
    coverage,
    seriesTruncated: raw?.seriesTruncated ?? false,
  };
}

/** Pontos de UMA janela, na ordem em que devem ser plotados. */
export function seriesForScope(series: PlanUsagePoint[], scope: string): PlanUsagePoint[] {
  return series.filter(p => p.scope === scope);
}

/**
 * A janela mais APERTADA do recorte — a de maior percentual consumido.
 *
 * Existe para o KPI compacto do Overview, onde so cabe um numero. NAO e uma
 * fusao dos escopos (proibida pela constituicao 1.3.0, §III): e a SELECAO de
 * uma das series, e quem exibe MUST rotular qual janela e essa. Media entre
 * `five_hour` e `seven_day` nao descreveria nada.
 *
 * Janelas sem leitura (`usedPercentage` null) sao ignoradas na comparacao;
 * `null` quando nenhuma janela tem valor — nunca a primeira por default.
 */
export function tightestScope(byScope: PlanUsageScopeState[]): PlanUsageScopeState | null {
  const measured = byScope.filter(s => s.usedPercentage != null);
  if (measured.length === 0) return null;
  return measured.reduce((worst, s) =>
    (s.usedPercentage as number) > (worst.usedPercentage as number) ? s : worst,
  );
}

/**
 * Rotulo CURTO da janela, para o KPI compacto onde as DUAS precisam caber na
 * mesma linha. Escopo desconhecido cai no identificador bruto, como o rotulo
 * longo.
 */
export const SHORT_SCOPE_LABEL: Record<string, string> = {
  five_hour: '5h',
  seven_day: '7d',
};

export function shortScopeLabel(scope: string): string {
  return SHORT_SCOPE_LABEL[scope] ?? scope;
}

/**
 * Frescor da captura de UMA janela.
 *
 * Existe por causa de uma ambiguidade real do lado do toolkit: a captura e
 * throttled (`_pu_throttle_discard` em `cli/lib/plan-usage.sh` descarta
 * captura de valor identico a anterior), entao `capturedAt` antigo tanto pode
 * significar "valor estavel" quanto "nenhuma sessao capturou ha horas" — e o
 * card era o mesmo nos dois casos (issue #208).
 *
 * O intervalo tipico NAO e um numero arbitrado: e a mediana dos intervalos
 * REALMENTE observados entre capturas daquela janela no recorte. Com menos de
 * dois pontos nao ha base de comparacao e o estado e `unknown` — a idade
 * continua sendo exibida, mas nenhuma suspeita e afirmada.
 */
export type PlanUsageCaptureState = 'unknown' | 'fresh' | 'aging';

export interface PlanUsageCapture {
  capturedAt: string | null;
  /** idade da captura mais recente, em segundos; null sem captura ou data invalida */
  ageSec: number | null;
  /** mediana dos intervalos observados entre capturas, em segundos; null com < 2 pontos */
  typicalIntervalSec: number | null;
  state: PlanUsageCaptureState;
}

/**
 * Quantas vezes o intervalo tipico a captura precisa passar para virar
 * `aging`. Fator, nao limite absoluto: uma base que captura de 30 em 30s e
 * outra que captura de hora em hora nao podem dividir o mesmo corte fixo.
 */
export const CAPTURE_AGING_FACTOR = 3;

function medianOf(values: number[]): number | null {
  if (values.length === 0) return null;
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 1
    ? (sorted[mid] as number)
    : (((sorted[mid - 1] as number) + (sorted[mid] as number)) / 2);
}

export function planUsageCapture(
  scope: PlanUsageScopeState | null | undefined,
  series: PlanUsagePoint[],
  nowMs: number,
): PlanUsageCapture {
  const capturedAt = scope?.capturedAt ?? null;
  const capturedMs = capturedAt != null ? Date.parse(capturedAt) : NaN;
  const ageSec = Number.isNaN(capturedMs)
    ? null
    : Math.max(0, Math.round((nowMs - capturedMs) / 1000));

  const stamps = series
    .filter(p => scope != null && p.scope === scope.scope)
    .map(p => Date.parse(p.capturedAt))
    .filter(ms => !Number.isNaN(ms))
    .sort((a, b) => a - b);

  const gaps: number[] = [];
  for (let i = 1; i < stamps.length; i += 1) {
    gaps.push(((stamps[i] as number) - (stamps[i - 1] as number)) / 1000);
  }
  const median = medianOf(gaps);
  // Mediana <= 0 (duas capturas no mesmo segundo) nao e base de comparacao:
  // qualquer idade passaria do corte e TUDO viraria suspeita.
  const typicalIntervalSec = median != null && median > 0 ? median : null;

  let state: PlanUsageCaptureState = 'unknown';
  if (ageSec != null && typicalIntervalSec != null) {
    state = ageSec > typicalIntervalSec * CAPTURE_AGING_FACTOR ? 'aging' : 'fresh';
  }

  return { capturedAt, ageSec, typicalIntervalSec, state };
}

/**
 * Idade relativa da captura ("agora", "ha 4m", "ha 2h", "ha 3d"), a partir de
 * segundos ja calculados — o relogio fica no chamador (funcao pura, mesmo
 * contrato de `fmtResetsIn`). Ausencia continua sendo "—", nunca "agora".
 */
export function fmtCaptureAge(ageSec: number | null | undefined): string {
  if (ageSec == null) return '—';
  if (ageSec < 60) return 'agora';
  if (ageSec < 3600) return `ha ${Math.floor(ageSec / 60)}m`;
  if (ageSec < 86400) return `ha ${Math.floor(ageSec / 3600)}h`;
  return `ha ${Math.floor(ageSec / 86400)}d`;
}

/**
 * Formata o percentual do plano. `null` vira "não medido", NUNCA "0%" —
 * um gauge sem leitura e um plano intocado sao afirmacoes diferentes.
 * O valor vem sem arredondamento da origem (inclusive com ruido de float, ex.
 * `7.000000000000001`); o arredondamento para exibicao acontece so aqui.
 */
export function fmtPlanPct(v: number | null | undefined): string {
  if (v == null) return 'não medido';
  return `${v.toFixed(1)}%`;
}

/**
 * Formata o reset da janela como tempo restante, a partir de um `now` INJETADO
 * (a funcao e pura — nao le o relogio). `resetsAt` e epoch em SEGUNDOS.
 * Reset ja no passado devolve "expirado": o proximo render de statusline vai
 * capturar a janela nova, e inventar "0%" enquanto isso seria fabricar dado.
 */
export function fmtResetsIn(resetsAt: number | null | undefined, nowMs: number): string {
  if (resetsAt == null) return '—';
  const deltaSec = resetsAt - Math.floor(nowMs / 1000);
  if (deltaSec <= 0) return 'expirado';
  const h = Math.floor(deltaSec / 3600);
  const m = Math.floor((deltaSec % 3600) / 60);
  if (h >= 24) {
    const d = Math.floor(h / 24);
    return `em ${d}d ${h % 24}h`;
  }
  return h > 0 ? `em ${h}h ${m}m` : `em ${m}m`;
}

/**
 * Faixa de severidade do gauge — usada so para COR, nunca para alterar o
 * numero. `null` nao tem faixa (nao existe "verde por falta de medicao").
 */
export type PlanUsageBand = 'none' | 'ok' | 'warn' | 'critical';

export function planUsageBand(v: number | null | undefined): PlanUsageBand {
  if (v == null) return 'none';
  if (v >= 90) return 'critical';
  if (v >= 70) return 'warn';
  return 'ok';
}

/** Texto curto de cobertura da amostra — mesmo padrao dos irmaos. */
export function planUsageCoverageLabel(coverage: PlanUsageCoverage): string {
  if (coverage.rowsTotal == null) return 'dado não coletado nesta base';
  const rows = coverage.rowsTotal;
  const sessions = coverage.sessions ?? 0;
  return `${rows} captura${rows === 1 ? '' : 's'} · ${sessions} ${sessions === 1 ? 'sessão' : 'sessões'}`;
}
