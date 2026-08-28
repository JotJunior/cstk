/**
 * Helpers de apresentacao do consumo de subagentes (schema v10).
 *
 * Todo caso aqui defende a mesma regra: o painel NUNCA mostra 0 onde a fonte
 * disse "sem numero", e NUNCA mostra um total sem a cobertura da amostra
 * quando parte dos spawns nao reportou uso.
 */
import { describe, it, expect } from 'vitest';
import {
  agentUsageState, isPartialSample, coverageLabel, sumAgentUsage, waveAgentUsage,
} from '@/components/AgentUsage.js';
import { waveUsageLabel, waveUsageTip } from '@/screens/ExecutionDetail.js';
import { fmtTokens, fmtMs } from '@/lib/format.js';
import type { WaveDTO, AgentUsageRollup } from '@cstk-panel/shared-types';

const BASE_WAVE: WaveDTO = {
  wave: 'onda-001',
  executionId: 'exec-1',
  stages: 'specify',
  startedAt: '2026-07-26T09:00:00Z',
  finishedAt: '2026-07-26T10:00:00Z',
  wallclockSeconds: 3600,
  toolCalls: 90,
  terminationReason: 'concluido',
  nStages: 1,
  nSkills: 1,
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
  // schema v12 — breakdown por fonte ausente nesta onda
  otelMainInputTokens: null,
  otelMainOutputTokens: null,
  otelMainCacheReadTokens: null,
  otelMainCacheCreationTokens: null,
  otelSubagentInputTokens: null,
  otelSubagentOutputTokens: null,
  otelSubagentCacheReadTokens: null,
  otelSubagentCacheCreationTokens: null,
};

/** Onda medida, cobertura parcial (3 de 4 spawns) — o caso mais comum. */
const MEASURED: WaveDTO = {
  ...BASE_WAVE,
  agentSpawnsTotal: 4,
  agentSpawnsWithUsage: 3,
  agentTotalTokens: 248500,
  agentInputTokens: 9800,
  agentOutputTokens: 21400,
  agentCacheReadTokens: 198300,
  agentCacheCreationTokens: 19000,
  agentToolUseCount: 41,
  agentDurationMs: 512000,
};

/** Onda com spawns observados, nenhum com dado de uso. */
const COLLECTED_NO_DATA: WaveDTO = {
  ...BASE_WAVE, wave: 'onda-002', agentSpawnsTotal: 2, agentSpawnsWithUsage: 0,
};

describe('agentUsageState — tres estados, nunca colapsados', () => {
  it('sem contagem de spawn => nao coletado', () => {
    expect(agentUsageState(waveAgentUsage(BASE_WAVE))).toBe('uncollected');
  });

  it('spawns observados sem dado de uso => coletado sem dado', () => {
    expect(agentUsageState(waveAgentUsage(COLLECTED_NO_DATA))).toBe('collected-no-data');
  });

  it('com tokens => medido', () => {
    expect(agentUsageState(waveAgentUsage(MEASURED))).toBe('measured');
  });

  it('spawnsTotal=0 legitimo (onda sem subagente) nao vira "nao coletado"', () => {
    const zero: AgentUsageRollup = { ...waveAgentUsage(BASE_WAVE), spawnsTotal: 0, spawnsWithUsage: 0 };
    expect(agentUsageState(zero)).toBe('collected-no-data');
  });
});

describe('cobertura da amostra', () => {
  it('detecta amostra parcial', () => {
    expect(isPartialSample(waveAgentUsage(MEASURED))).toBe(true);
  });

  it('cobertura integral nao e parcial', () => {
    expect(isPartialSample({ ...waveAgentUsage(MEASURED), spawnsWithUsage: 4 })).toBe(false);
  });

  it('rotulo sempre carrega o denominador', () => {
    expect(coverageLabel(waveAgentUsage(MEASURED))).toBe('3 de 4 spawns medidos');
  });

  it('sem coleta o rotulo diz isso — nao "0 de 0"', () => {
    expect(coverageLabel(waveAgentUsage(BASE_WAVE))).toBe('métrica não coletada');
  });
});

describe('sumAgentUsage — soma preservando ausencia', () => {
  it('mistura de ondas medidas e nao medidas soma so o observado', () => {
    const total = sumAgentUsage([MEASURED, COLLECTED_NO_DATA, BASE_WAVE]);
    expect(total.totalTokens).toBe(248500);
    expect(total.spawnsTotal).toBe(6);      // 4 + 2 (BASE nao contribui)
    expect(total.spawnsWithUsage).toBe(3);
    expect(total.wavesWithUsage).toBe(2);
    expect(total.wavesTotal).toBe(3);
  });

  it('so ondas sem medicao => null, nunca 0', () => {
    const total = sumAgentUsage([BASE_WAVE, { ...BASE_WAVE, wave: 'onda-x' }]);
    expect(total.totalTokens).toBeNull();
    expect(total.spawnsTotal).toBeNull();
    expect(agentUsageState(total)).toBe('uncollected');
  });

  it('lista vazia nao inventa consumo', () => {
    expect(sumAgentUsage([]).totalTokens).toBeNull();
  });
});

describe('celula de token da onda', () => {
  it('medida parcial ganha marcador de amostra', () => {
    expect(waveUsageLabel(MEASURED)).toBe('248.5k *');
  });

  it('medida integral nao ganha marcador', () => {
    expect(waveUsageLabel({ ...MEASURED, agentSpawnsWithUsage: 4 })).toBe('248.5k');
  });

  it('coletado sem dado nao vira 0', () => {
    expect(waveUsageLabel(COLLECTED_NO_DATA)).toBe('s/ dado');
    expect(waveUsageTip(COLLECTED_NO_DATA)).toContain('nenhum reportou uso');
  });

  it('nao coletado exibe travessao', () => {
    expect(waveUsageLabel(BASE_WAVE)).toBe('—');
    expect(waveUsageTip(BASE_WAVE)).toContain('nao coletado');
  });
});

describe('formatadores', () => {
  it('fmtTokens compacta sem perder ordem de grandeza', () => {
    expect(fmtTokens(812)).toBe('812');
    expect(fmtTokens(12_340)).toBe('12.3k');
    expect(fmtTokens(4_060_000)).toBe('4.06M');
  });

  it('fmtTokens(null) e travessao — nao "0"', () => {
    expect(fmtTokens(null)).toBe('—');
    expect(fmtTokens(0)).toBe('0');   // zero medido continua sendo zero
  });

  it('fmtMs converte para a mesma escala de duracao', () => {
    expect(fmtMs(512_000)).toBe('8m 32s');
    expect(fmtMs(null)).toBe('—');
  });
});
