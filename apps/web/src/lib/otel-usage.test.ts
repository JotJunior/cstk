/**
 * Helpers de apresentacao do custo real medido por telemetria OTel (v11).
 *
 * Todo caso aqui defende a mesma regra do bloco v10, adaptada ao unico numero
 * monetario do painel: onda sem telemetria NUNCA vira "$0" (indistinguivel de
 * "onda que nao custou nada"), e nenhum total aparece sem a cobertura da
 * amostra quando parte das ondas nao foi instrumentada.
 */
import { describe, it, expect } from 'vitest';
import {
  otelUsageState, isPartialOtelSample, otelCoverageLabel, fmtUsd,
  subagentCostShare, sumOtelUsage, waveOtelUsage,
} from '@/components/OtelUsage.js';
import { waveCostLabel, waveCostTip } from '@/screens/ExecutionDetail.js';
import type { WaveDTO, OtelUsageRollup } from '@cstk-panel/shared-types';

/** Onda sem nenhuma medicao — base v<11 ou telemetria desligada. */
const BASE_WAVE: WaveDTO = {
  wave: 'onda-002',
  executionId: 'exec-otel-panel',
  stages: 'execute-task',
  startedAt: '2026-07-26T11:00:00Z',
  finishedAt: '2026-07-26T11:04:00Z',
  wallclockSeconds: 240,
  toolCalls: 40,
  terminationReason: '',
  nStages: 1,
  nSkills: 0,
  session: null,
  agentSpawnsTotal: null,
  agentSpawnsWithUsage: null,
  agentTotalTokens: null,
  agentInputTokens: null,
  agentOutputTokens: null,
  agentCacheReadTokens: null,
  agentCacheCreationTokens: null,
  agentToolUseCount: null,
  agentDurationMs: null,
  otelCostUsd: null,
  otelCostMainUsd: null,
  otelCostSubagentUsd: null,
  otelTotalTokens: null,
  otelSubagentTokens: null,
};

/** Valores reais de uma onda ingerida por `cstk recall --ingest` (5.30.0). */
const MEASURED: WaveDTO = {
  ...BASE_WAVE,
  wave: 'onda-001',
  stages: 'plan',
  otelCostUsd: 0.229038,
  otelCostMainUsd: 0.130553,
  otelCostSubagentUsd: 0.098485,
  otelTotalTokens: 648,
  otelSubagentTokens: 648,
};

describe('otelUsageState', () => {
  it('null/undefined => uncollected', () => {
    expect(otelUsageState(null)).toBe('uncollected');
    expect(otelUsageState(undefined)).toBe('uncollected');
  });

  it('rollup com todos os campos null => uncollected (nao "medido zero")', () => {
    expect(otelUsageState(waveOtelUsage(BASE_WAVE))).toBe('uncollected');
  });

  it('rollup com custo => measured', () => {
    expect(otelUsageState(waveOtelUsage(MEASURED))).toBe('measured');
  });
});

describe('fmtUsd', () => {
  it('null vira "—", nunca "$0"', () => {
    expect(fmtUsd(null)).toBe('—');
    expect(fmtUsd(undefined)).toBe('—');
  });

  it('preserva ordem de grandeza abaixo de 1 centavo', () => {
    // Arredondar 0.000577 para 2 casas daria "$0.00" — visualmente igual a
    // "nao custou nada", que e exatamente o que nao pode acontecer.
    expect(fmtUsd(0.000577)).toBe('$0.0006');
    expect(fmtUsd(0.0012)).toBe('$0.0012');
  });

  it('a partir de 1 centavo, 2 casas bastam', () => {
    expect(fmtUsd(0.098485)).toBe('$0.10');
    expect(fmtUsd(0.229038)).toBe('$0.23');
    expect(fmtUsd(12.5)).toBe('$12.50');
  });

  it('zero MEDIDO e exibido como $0 (distinto de ausente)', () => {
    expect(fmtUsd(0)).toBe('$0');
  });
});

describe('subagentCostShare', () => {
  it('calcula a fatia de subagente sobre o total', () => {
    const share = subagentCostShare(waveOtelUsage(MEASURED));
    expect(share).not.toBeNull();
    expect(share!).toBeCloseTo(0.098485 / 0.229038, 6);
  });

  it('sem custo total nao inventa fatia', () => {
    expect(subagentCostShare(waveOtelUsage(BASE_WAVE))).toBeNull();
  });

  it('custo total zero nao divide por zero', () => {
    const zeroed: OtelUsageRollup = {
      costUsd: 0, costMainUsd: 0, costSubagentUsd: 0,
      totalTokens: 0, subagentTokens: 0, wavesWithOtel: 1, wavesTotal: 1,
    };
    expect(subagentCostShare(zeroed)).toBeNull();
  });
});

describe('sumOtelUsage', () => {
  it('preserva null quando nenhuma onda foi medida', () => {
    const total = sumOtelUsage([BASE_WAVE, { ...BASE_WAVE, wave: 'onda-003' }]);
    expect(total.costUsd).toBeNull();
    expect(total.totalTokens).toBeNull();
    // as ondas existem no recorte; so nao ha medicao
    expect(total.wavesTotal).toBe(2);
    expect(total.wavesWithOtel).toBeNull();
  });

  it('soma so o que foi medido e reporta a cobertura', () => {
    const total = sumOtelUsage([MEASURED, BASE_WAVE]);
    expect(total.costUsd).toBeCloseTo(0.229038, 6);
    expect(total.costSubagentUsd).toBeCloseTo(0.098485, 6);
    expect(total.wavesWithOtel).toBe(1);
    expect(total.wavesTotal).toBe(2);
    expect(isPartialOtelSample(total)).toBe(true);
    expect(otelCoverageLabel(total)).toBe('1 de 2 ondas medidas');
  });

  it('cobertura integral nao e marcada como parcial', () => {
    const total = sumOtelUsage([MEASURED, { ...MEASURED, wave: 'onda-004' }]);
    expect(isPartialOtelSample(total)).toBe(false);
    expect(total.costUsd).toBeCloseTo(0.458076, 6);
  });
});

describe('celula de custo da onda (ExecutionDetail)', () => {
  it('onda medida mostra o valor; onda sem coleta mostra "—"', () => {
    expect(waveCostLabel(MEASURED)).toBe('$0.23');
    expect(waveCostLabel(BASE_WAVE)).toBe('—');
  });

  it('o tooltip diz por que nao ha numero, em vez de sugerir zero', () => {
    expect(waveCostTip(BASE_WAVE)).toContain('nao coletado');
    expect(waveCostTip(MEASURED)).toContain('subagentes');
  });
});
