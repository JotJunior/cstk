/**
 * loose-usage-select — regras puras do view-model do consumo avulso
 * (schema v13, `loose_usage`). Os 3 estados nunca colapsam:
 * `degraded` (tabela ausente) != `empty` (captura opt-in sem linhas) !=
 * `measured` — e null nunca vira 0 na renderizacao (Principio III).
 */
import { describe, it, expect } from 'vitest';
import {
  selectLooseUsage,
  looseUsageCoverageLabel,
  fmtBlendedPerMtok,
} from './loose-usage-select.js';
import type { LooseUsageResult } from '@cstk-panel/shared-types';

const DEGRADED: LooseUsageResult = {
  byProject: [],
  byModel: [],
  comparison: {
    loose: { costUsd: null, totalTokens: null, blendedCostPerMtok: null },
    pipeline: { costUsd: null, totalTokens: null, blendedCostPerMtok: null },
  },
  coverage: {
    rowsTotal: null, segmentsTotal: null, segmentsOpen: null,
    processes: null, projects: null, lastCapturedAt: null,
  },
};

const MEASURED: LooseUsageResult = {
  byProject: [{
    project: 'cstk-panel', projectPath: '/tmp/cstk-panel', costUsd: 1.25,
    totalTokens: 500_000, processes: 1, segments: 2, openSegments: 1,
    lastCapturedAt: '2026-08-07T10:00:00Z',
  }],
  byModel: [{ model: 'claude-fable-5', costUsd: 1.25, totalTokens: 500_000, segments: 2 }],
  comparison: {
    loose: { costUsd: 1.25, totalTokens: 500_000, blendedCostPerMtok: 2.5 },
    pipeline: { costUsd: null, totalTokens: null, blendedCostPerMtok: null },
  },
  coverage: {
    rowsTotal: 2, segmentsTotal: 2, segmentsOpen: 1,
    processes: 1, projects: 1, lastCapturedAt: '2026-08-07T10:00:00Z',
  },
};

describe('selectLooseUsage — derivacao de estado pela FORMA do data', () => {
  it('coverage.rowsTotal null (tabela ausente) => degraded', () => {
    expect(selectLooseUsage(DEGRADED).state).toBe('degraded');
  });

  it('tabela presente e vazia (rowsTotal 0) => empty, nunca degraded', () => {
    const raw: LooseUsageResult = {
      ...DEGRADED,
      coverage: { ...DEGRADED.coverage, rowsTotal: 0, segmentsTotal: 0, segmentsOpen: 0, processes: 0, projects: 0 },
    };
    expect(selectLooseUsage(raw).state).toBe('empty');
  });

  it('com linhas => measured, preservando os recortes', () => {
    const vm = selectLooseUsage(MEASURED);
    expect(vm.state).toBe('measured');
    expect(vm.byProject).toHaveLength(1);
    expect(vm.byModel[0]?.model).toBe('claude-fable-5');
    expect(vm.comparison.pipeline.costUsd).toBeNull();
  });

  it('data null/undefined (envelope degradado sem corpo) => degraded', () => {
    expect(selectLooseUsage(null).state).toBe('degraded');
    expect(selectLooseUsage(undefined).state).toBe('degraded');
  });
});

describe('looseUsageCoverageLabel', () => {
  it('degradado: "dado não coletado nesta base"', () => {
    expect(looseUsageCoverageLabel(DEGRADED.coverage)).toBe('dado não coletado nesta base');
  });

  it('sinaliza segmentos em captura quando ha abertos', () => {
    expect(looseUsageCoverageLabel(MEASURED.coverage)).toBe('2 segmentos · 1 processo · 1 em captura');
  });

  it('sem abertos: omite o sufixo de captura', () => {
    expect(looseUsageCoverageLabel({ ...MEASURED.coverage, segmentsOpen: 0 })).toBe('2 segmentos · 1 processo');
  });
});

describe('fmtBlendedPerMtok — null nunca vira $0', () => {
  it('null => "não medido"', () => {
    expect(fmtBlendedPerMtok(null)).toBe('não medido');
    expect(fmtBlendedPerMtok(undefined)).toBe('não medido');
  });

  it('valor medido => $X.XX/Mtok', () => {
    expect(fmtBlendedPerMtok(2.5)).toBe('$2.50/Mtok');
  });
});
