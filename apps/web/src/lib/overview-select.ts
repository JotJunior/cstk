/**
 * overview-select — normaliza a resposta do endpoint /overview no view-model
 * consumido pela tela Overview.
 *
 * Funcao PURA (sem React/DOM) para ser testavel em node-env. Existe para
 * travar o CONTRATO de borda: o backend entrega kpis/arrays em camelCase
 * ingles (ver apps/server/src/routes/overview.ts); qualquer regressao
 * para snake_case/portugues zera o dashboard e e pega pelo teste irmao.
 *
 * Ref: bug pos-entrega (KPIs zerados) — drift snake_case vs camelCase no
 * consumo do payload. Spec §User Story 1.
 */
import type { AgentUsageRollup } from '@cstk-panel/shared-types';

export interface OverviewKpisRaw {
  totalProjects?: number | null;
  totalFeatures?: number | null;
  totalExecutions?: number | null;
  activeExecutions?: number | null;
  completedExecutions?: number | null;
  abortedExecutions?: number | null;
  totalWaves?: number | null;
  totalDecisions?: number | null;
  toolCallsTotal?: number | null;
  wallclockTotal?: number | null;
  testsPassed?: number | null;
  testsTotal?: number | null;
  /** consumo MEDIDO de subagentes (schema v10); ausente em bases v<10 */
  agentUsage?: AgentUsageRollup | null;
  otelUsage?: OtelUsageRollup | null;
}

export interface ModelMixRaw { model?: string | null; n?: number | null; }
export interface ActivityRaw {
  executionId?: string | null;
  project?: string | null;
  feature?: string | null;
  wave?: string | null;
  eventType?: string | null;
  timestamp?: string | null;
  description?: string | null;
}

export interface OverviewRaw {
  kpis?: OverviewKpisRaw | null;
  inProgress?: Array<Record<string, unknown>> | null;
  recentAlerts?: Array<Record<string, unknown>> | null;
  leaderboard?: Array<Record<string, unknown>> | null;
  funnel?: Array<{ stage?: string | null; count?: number | null }> | null;
  modelMix?: ModelMixRaw[] | null;
  recentActivity?: ActivityRaw[] | null;
  costSeries?: number[] | null;
  /** serie diaria de tokens medidos; dias sem medicao nao aparecem */
  tokenSeries?: number[] | null;
}


/** Consumo REAL da onda medido pela telemetria OTel (knowledge.db v11).
 *  Fonte independente de agentUsage: cobre tambem o gasto do proprio
 *  orquestrador. null em todo campo = nao coletado (nunca zero fabricado). */
export interface OtelUsageRollup {
  costUsd: number | null;
  costMainUsd: number | null;
  costSubagentUsd: number | null;
  totalTokens: number | null;
  subagentTokens: number | null;
  wavesWithOtel: number | null;
  wavesTotal: number | null;
}

export interface OverviewVM {
  totalProjects: number;
  totalFeatures: number;
  emAndamento: number;
  aguardando: number;
  totalToolCalls: number;
  totalWallclock: number | null;
  testsPassed: number | null;
  testsTotal: number | null;
  totalWaves: number | null;
  totalDecisoes: number | null;
  totalExecucoes: number | null;
  concluidas: number;
  abortadas: number;
  totalAlertas: number;
  execucoes: Array<Record<string, unknown>>;
  alertas: Array<Record<string, unknown>>;
  leaderboard: Array<Record<string, unknown>>;
  funnel: Array<{ stage?: string | null; count?: number | null }>;
  modelMix: ModelMixRaw[];
  recentActivity: ActivityRaw[];
  costSeries: number[];
  /** null (nao 0) quando a base nao tem medicao — Principio III */
  agentUsage: AgentUsageRollup | null;
  /** null quando a base e < v11 ou a telemetria nao estava ligada */
  otelUsage: OtelUsageRollup | null;
  tokenSeries: number[];
  maxToolCalls: number;
  maxFunnel: number;
}

export function selectOverview(raw: OverviewRaw | null | undefined): OverviewVM {
  const kpis = raw?.kpis ?? {};
  const execucoes = raw?.inProgress ?? [];
  const alertas = raw?.recentAlerts ?? [];
  const leaderboard = raw?.leaderboard ?? [];
  const funnel = raw?.funnel ?? [];
  const modelMix = raw?.modelMix ?? [];
  const recentActivity = raw?.recentActivity ?? [];
  const costSeries = raw?.costSeries ?? [];
  const tokenSeries = raw?.tokenSeries ?? [];

  return {
    totalProjects: kpis.totalProjects ?? 0,
    totalFeatures: kpis.totalFeatures ?? 0,
    emAndamento: kpis.activeExecutions ?? 0,
    // 'aguardando humano' nao vem em kpis — derivar das execucoes em andamento.
    aguardando: execucoes.filter(e => e['status'] === 'aguardando_humano').length,
    totalToolCalls: kpis.toolCallsTotal ?? 0,
    totalWallclock: kpis.wallclockTotal ?? null,
    testsPassed: kpis.testsPassed ?? null,
    testsTotal: kpis.testsTotal ?? null,
    totalWaves: kpis.totalWaves ?? null,
    totalDecisoes: kpis.totalDecisions ?? null,
    totalExecucoes: kpis.totalExecutions ?? null,
    concluidas: kpis.completedExecutions ?? 0,
    abortadas: kpis.abortedExecutions ?? 0,
    totalAlertas: alertas.length,
    execucoes,
    alertas,
    leaderboard,
    funnel,
    modelMix,
    recentActivity,
    costSeries,
    // NAO coalescer para um objeto zerado: ausencia de medicao precisa chegar
    // como null na UI para virar "—" em vez de "0 tokens".
    agentUsage: kpis.agentUsage ?? null,
    otelUsage: kpis.otelUsage ?? null,
    tokenSeries,
    maxToolCalls: leaderboard.reduce(
      (m, row) => Math.max(m, (row['toolCallsTotal'] as number | null) ?? 0), 0,
    ),
    maxFunnel: funnel.reduce((m, row) => Math.max(m, row.count ?? 0), 0),
  };
}
