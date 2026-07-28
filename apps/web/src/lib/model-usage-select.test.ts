import { describe, it, expect } from 'vitest';
import {
  selectModelUsage,
  modelUsageCoverageLabel,
  groupModelUsageByStage,
  MODEL_USAGE_SUMMARY_LIMIT,
  MODEL_USAGE_NATURE_LABEL,
} from './model-usage-select.js';
import type { ModelUsageResult, ModelUsageByStage } from '@cstk-panel/shared-types';

// Payload representativo no SHAPE REAL do endpoint (validado empiricamente
// contra ~/.claude/cstk/knowledge.db em tasks.md 2.5.1/2.5.2 — camelCase
// ingles, ver apps/server/src/routes/metrics.ts).
const realPayload: ModelUsageResult = {
  byModel: [
    { model: 'claude-sonnet-5', costUsd: 905.3943489, totalTokens: 2189357933, waves: 41 },
    { model: 'claude-fable-5', costUsd: 23.594576, totalTokens: 13884110, waves: 7 },
    { model: 'claude-opus-5[1m]', costUsd: 6.1439, totalTokens: 6864604, waves: 1 },
  ],
  byStage: [
    { stage: 'execute-task', model: 'claude-sonnet-5', costUsd: 246.8715799, totalTokens: 601627942 },
  ],
  coverage: { wavesTotal: 925, wavesWithModelUsage: 41, wavesWithOtelCost: 51 },
};

describe('selectModelUsage', () => {
  it('modelo de maior custo primeiro (SC-001) e state=measured', () => {
    const vm = selectModelUsage(realPayload);
    expect(vm.state).toBe('measured');
    expect(vm.entries[0]?.model).toBe('claude-sonnet-5');
    expect(vm.entries[0]?.costUsd).toBe(905.3943489);
    expect(vm.entries.map((e) => e.model)).toEqual([
      'claude-sonnet-5', 'claude-fable-5', 'claude-opus-5[1m]',
    ]);
  });

  it('top respeita MODEL_USAGE_SUMMARY_LIMIT (dec-038: top-3)', () => {
    expect(MODEL_USAGE_SUMMARY_LIMIT).toBe(3);
    const vm = selectModelUsage(realPayload);
    expect(vm.top.length).toBe(3);
    expect(vm.top).toEqual(vm.entries.slice(0, 3));
  });

  it('reordena com custo null sempre por ultimo, mesmo fora de ordem na entrada', () => {
    const payload: ModelUsageResult = {
      byModel: [
        { model: 'a', costUsd: null, totalTokens: null, waves: 2 },
        { model: 'b', costUsd: 10, totalTokens: 1000, waves: 5 },
        { model: 'c', costUsd: 50, totalTokens: 2000, waves: 3 },
      ],
      byStage: [],
      coverage: { wavesTotal: 10, wavesWithModelUsage: 8, wavesWithOtelCost: 8 },
    };
    const vm = selectModelUsage(payload);
    expect(vm.entries.map((e) => e.model)).toEqual(['c', 'b', 'a']);
  });

  it('estado vazio: tabela presente, zero linhas no recorte (nao degradado)', () => {
    const payload: ModelUsageResult = {
      byModel: [],
      byStage: [],
      coverage: { wavesTotal: 12, wavesWithModelUsage: 0, wavesWithOtelCost: 3 },
    };
    const vm = selectModelUsage(payload);
    expect(vm.state).toBe('empty');
    expect(vm.entries).toEqual([]);
    expect(vm.top).toEqual([]);
  });

  it('estado degradado: tabela ausente (table-empty) — coverage com os 3 campos null, nunca 0', () => {
    const payload: ModelUsageResult = {
      byModel: [],
      byStage: [],
      coverage: { wavesTotal: null, wavesWithModelUsage: null, wavesWithOtelCost: null },
    };
    const vm = selectModelUsage(payload);
    expect(vm.state).toBe('degraded');
    expect(vm.coverage.wavesTotal).toBeNull();
  });

  it('tolera payload null/undefined sem quebrar (cai em degraded, coverage vazia)', () => {
    expect(selectModelUsage(null).state).toBe('degraded');
    expect(selectModelUsage(undefined).state).toBe('degraded');
    expect(selectModelUsage(null).entries).toEqual([]);
  });

  it('rotulo de natureza e fixo "medido" (spec US1: nao proxy, nao derivado)', () => {
    expect(MODEL_USAGE_NATURE_LABEL).toBe('medido');
  });

  it('modelUsageCoverageLabel formata cobertura e trata coverage nao coletada', () => {
    expect(modelUsageCoverageLabel(realPayload.coverage)).toBe('41 de 925 ondas medidas');
    expect(modelUsageCoverageLabel({ wavesTotal: null, wavesWithModelUsage: null, wavesWithOtelCost: null }))
      .toBe('dado não coletado nesta base');
  });
});

describe('groupModelUsageByStage', () => {
  it('particiona byStage por etapa preservando ordem de primeira aparicao', () => {
    const rows: ModelUsageByStage[] = [
      { stage: 'execute-task', model: 'claude-sonnet-5', costUsd: 246.87, totalTokens: 601627942 },
      { stage: 'plan', model: 'claude-opus-5[1m]', costUsd: 5.1, totalTokens: 120000 },
      { stage: 'execute-task', model: 'claude-fable-5', costUsd: 12.3, totalTokens: 45000 },
    ];
    const groups = groupModelUsageByStage(rows);
    expect(groups.map((g) => g.stage)).toEqual(['execute-task', 'plan']);
    expect(groups[0]?.entries.map((e) => e.model)).toEqual(['claude-sonnet-5', 'claude-fable-5']);
    expect(groups[1]?.entries).toEqual([rows[1]]);
  });

  it('array vazio (correlacao onda x etapa nao resolvel) produz [] — nunca dado inventado', () => {
    expect(groupModelUsageByStage([])).toEqual([]);
    expect(groupModelUsageByStage(null)).toEqual([]);
    expect(groupModelUsageByStage(undefined)).toEqual([]);
  });

  it('nao muta nem soma costUsd entre linhas do mesmo grupo (cada linha preserva seu proprio valor)', () => {
    const rows: ModelUsageByStage[] = [
      { stage: 'clarify', model: 'a', costUsd: 1, totalTokens: 10 },
      { stage: 'clarify', model: 'b', costUsd: null, totalTokens: null },
    ];
    const groups = groupModelUsageByStage(rows);
    expect(groups).toEqual([{ stage: 'clarify', entries: rows }]);
  });
});
