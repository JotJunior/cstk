import { describe, it, expect } from 'vitest';
import { selectOverview, type OverviewRaw } from './overview-select.js';

// Payload representativo no SHAPE REAL do endpoint /overview
// (camelCase ingles — ver apps/server/src/db/queries/overview.ts).
const realPayload: OverviewRaw = {
  kpis: {
    totalProjects: 9,
    totalFeatures: 6,
    totalExecutions: 14,
    activeExecutions: 6,
    completedExecutions: 8,
    abortedExecutions: 0,
    totalWaves: 246,
    totalDecisions: 964,
    toolCallsTotal: 194,
    wallclockTotal: 38340,
    testsPassed: 1337,
    testsTotal: 1340,
  },
  inProgress: [
    { executionId: 'exec-a', status: 'em_andamento', currentStage: 'plan', ondasTotal: 12, toolCallsTotal: 88, wallclockSegundos: 2740 },
    { executionId: 'exec-b', status: 'aguardando_humano', currentStage: 'execute-task', ondasTotal: 3, toolCallsTotal: 12, wallclockSegundos: 980 },
  ],
  recentAlerts: [{ executionId: 'exec-a', tipo: 'circular', description: 'x', wave: '-', consumedValue: null, thresholdValue: null }],
  leaderboard: [
    { feature: 'swagger-codegen', toolCallsTotal: 24 },
    { feature: 'knowledge-db', toolCallsTotal: 6 },
  ],
  funnel: [
    { stage: 'execute-task', count: 9 },
    { stage: 'review-task', count: 4 },
  ],
  modelMix: [
    { model: 'sonnet', n: 11 },
    { model: 'opus', n: 3 },
    { model: 'haiku', n: 1 },
  ],
  recentActivity: [
    { executionId: 'exec-a', eventType: 'schedule_wait', timestamp: '2026-05-24T20:00:00Z', description: 'pausando' },
  ],
  costSeries: [10, 40, 120, 24],
};

describe('selectOverview', () => {
  it('mapeia os KPIs camelCase reais para o view-model (regressao do bug de zeros)', () => {
    const vm = selectOverview(realPayload);
    expect(vm.totalProjects).toBe(9);
    expect(vm.totalFeatures).toBe(6);
    expect(vm.emAndamento).toBe(6);       // activeExecutions
    expect(vm.totalToolCalls).toBe(194);  // toolCallsTotal
    expect(vm.totalWaves).toBe(246);
    expect(vm.totalDecisoes).toBe(964);
    expect(vm.totalExecucoes).toBe(14);
    expect(vm.concluidas).toBe(8);        // completedExecutions
    expect(vm.abortadas).toBe(0);
  });

  it('deriva aguardando humano das execucoes em andamento', () => {
    expect(selectOverview(realPayload).aguardando).toBe(1);
  });

  it('le leaderboard.toolCallsTotal (nao tool_calls_total) — payload preservado no VM (contrato inalterado, FASE 4.1.2)', () => {
    const vm = selectOverview(realPayload);
    expect(vm.leaderboard.length).toBe(2);
    expect(vm.leaderboard[0]).toEqual({ feature: 'swagger-codegen', toolCallsTotal: 24 });
  });

  it('le funnel/inProgress/recentAlerts pelos nomes camelCase corretos — funnel preservado no VM (contrato inalterado, FASE 4.2.3)', () => {
    const vm = selectOverview(realPayload);
    expect(vm.funnel.length).toBe(2);
    expect(vm.funnel[0]).toEqual({ stage: 'execute-task', count: 9 });
    expect(vm.execucoes.length).toBe(2);
    expect(vm.totalAlertas).toBe(1);
  });

  it('GUARDA-CONTRA-REGRESSAO: payload snake_case/portugues NAO popula (so camelCase conta)', () => {
    const legacyWrong = {
      kpis: { total_projetos: 9, total_features: 6, em_andamento: 6, total_tool_calls: 194 },
      execucoes_em_andamento: [{ status: 'em_andamento' }],
      alertas_recentes: [{}],
    } as unknown as OverviewRaw;
    const vm = selectOverview(legacyWrong);
    // Se alguem reverter para snake_case no backend ou no select, isto falha.
    expect(vm.totalProjects).toBe(0);
    expect(vm.totalToolCalls).toBe(0);
    expect(vm.execucoes.length).toBe(0);
    expect(vm.totalAlertas).toBe(0);
  });

  it('mapeia os campos enriquecidos (wallclock, test pass, mix, atividade, serie)', () => {
    const vm = selectOverview(realPayload);
    expect(vm.totalWallclock).toBe(38340);
    expect(vm.testsPassed).toBe(1337);
    expect(vm.testsTotal).toBe(1340);
    expect(vm.modelMix.length).toBe(3);
    expect(vm.modelMix[0]).toEqual({ model: 'sonnet', n: 11 });
    expect(vm.recentActivity.length).toBe(1);
    expect(vm.costSeries).toEqual([10, 40, 120, 24]);
  });

  it('campos enriquecidos ausentes caem para null/[] (sem quebrar telas antigas)', () => {
    const vm = selectOverview({ kpis: { totalProjects: 1 } });
    expect(vm.totalWallclock).toBeNull();
    expect(vm.testsPassed).toBeNull();
    expect(vm.modelMix).toEqual([]);
    expect(vm.recentActivity).toEqual([]);
    expect(vm.costSeries).toEqual([]);
  });

  it('tolera payload vazio/null sem quebrar', () => {
    const vm = selectOverview(null);
    expect(vm.totalProjects).toBe(0);
    expect(vm.execucoes).toEqual([]);
    expect(vm.funnel).toEqual([]);
  });

  it('NAO expoe mais maxToolCalls/maxFunnel — derivados so p/ renderizacao dos cards removidos (FASE 4.1.3/4.2.4)', () => {
    const vm = selectOverview(realPayload) as unknown as Record<string, unknown>;
    expect('maxToolCalls' in vm).toBe(false);
    expect('maxFunnel' in vm).toBe(false);
  });
});
