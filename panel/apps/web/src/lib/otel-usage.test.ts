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
  hasOtelBreakdown, otelMainTokens, otelSubagentTokens,
  otelSourceTotal, cacheReadShare,
} from '@/components/OtelUsage.js';
import { waveCostLabel, waveCostTip, waveUsageLabel, waveUsageTip } from '@/screens/ExecutionDetail.js';
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
      mainInputTokens: null, mainOutputTokens: null,
      mainCacheReadTokens: null, mainCacheCreationTokens: null,
      subagentInputTokens: null, subagentOutputTokens: null,
      subagentCacheReadTokens: null, subagentCacheCreationTokens: null,
      wavesWithMainBreakdown: null, wavesWithSubagentBreakdown: null,
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

describe('celula de token da onda — fonte OTel', () => {
  // Regressao do caso de producao (mcp-project-scafold onda-022): a onda tinha
  // custo e token OTel, mas nenhuma coluna agent_* — a celula lia so a v10 e
  // exibia "—" ao lado de "$3.14".
  const OTEL_ONLY: WaveDTO = {
    ...BASE_WAVE,
    wave: 'onda-022',
    otelCostUsd: 3.14147,
    otelCostMainUsd: 0,
    otelCostSubagentUsd: 3.14147,
    otelTotalTokens: 7_228_603,
    otelSubagentTokens: 7_224_500,
  };

  it('onda com telemetria exibe o token, mesmo sem hook de spawn', () => {
    expect(waveUsageLabel(OTEL_ONLY)).toBe('7.23M');
    expect(waveUsageTip(OTEL_ONLY)).toContain('telemetria OTel');
  });

  it('OTel vence a fonte v10 quando as duas mediram', () => {
    const both: WaveDTO = { ...OTEL_ONLY, agentSpawnsTotal: 2, agentSpawnsWithUsage: 2, agentTotalTokens: 4_100 };
    expect(waveUsageLabel(both)).toBe('7.23M');
  });

  it('sem nenhuma das duas fontes continua travessao, nunca 0', () => {
    expect(waveUsageLabel(BASE_WAVE)).toBe('—');
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Breakdown por FONTE x TIPO (schema v12)
//
// As 5 colunas de v11 dizem quanto custou; estas 8 dizem de QUE TIPO era o
// token. A leitura que so elas permitem: uma onda de milhoes de tokens sendo
// quase toda cache read e uma onda LONGA, nao uma onda cara.
//
// Regra dura: main e subagente sao coletas INDEPENDENTES (na base real, 27
// ondas com main contra 257 com subagente). Um lado ausente nunca pode ser
// somado como 0 nem herdar a cobertura do outro.
// ─────────────────────────────────────────────────────────────────────────────

/** Valores reais da onda-012 de esp32-c6/wifi-standalone (knowledge.db v14). */
const WAVE_V12: WaveDTO = {
  ...BASE_WAVE,
  wave: 'onda-012',
  otelCostUsd: 4.9554576,
  otelCostMainUsd: 2.3303035,
  otelCostSubagentUsd: 2.5170876,
  otelTotalTokens: 8_782_315,
  otelSubagentTokens: 4_840_515,
  otelMainInputTokens: 34,
  otelMainOutputTokens: 11_325,
  otelMainCacheReadTokens: 3_709_177,
  otelMainCacheCreationTokens: 19_242,
  otelSubagentInputTokens: 88,
  otelSubagentOutputTokens: 25_681,
  otelSubagentCacheReadTokens: 4_615_562,
  otelSubagentCacheCreationTokens: 199_184,
};

/** Caso MAJORITARIO da base real: subagente medido, orquestrador nao. */
const WAVE_V12_SO_SUBAGENTE: WaveDTO = {
  ...WAVE_V12,
  wave: 'onda-013',
  otelMainInputTokens: null,
  otelMainOutputTokens: null,
  otelMainCacheReadTokens: null,
  otelMainCacheCreationTokens: null,
};

describe('hasOtelBreakdown', () => {
  it('onda v11 (sem as 8 colunas) nao tem breakdown', () => {
    expect(hasOtelBreakdown(waveOtelUsage(BASE_WAVE))).toBe(false);
  });

  it('basta UM lado medido para haver breakdown', () => {
    expect(hasOtelBreakdown(waveOtelUsage(WAVE_V12_SO_SUBAGENTE))).toBe(true);
  });
});

describe('otelSourceTotal / cacheReadShare', () => {
  it('lado nao coletado devolve null, nunca 0', () => {
    const main = otelMainTokens(waveOtelUsage(WAVE_V12_SO_SUBAGENTE));
    // Somar 4 nulls como 0 diria "o orquestrador nao gastou token" — falso: o
    // que houve foi ausencia de coleta.
    expect(otelSourceTotal(main)).toBeNull();
    expect(cacheReadShare(main)).toBeNull();
  });

  it('soma os 4 tipos do lado e calcula a fatia de cache read', () => {
    const sub = otelSubagentTokens(waveOtelUsage(WAVE_V12));
    const total = otelSourceTotal(sub);
    expect(total).toBe(88 + 25_681 + 4_615_562 + 199_184);
    const share = cacheReadShare(sub);
    expect(share).not.toBeNull();
    // ~95% do consumo do subagente e contexto RELIDO — o numero que muda a
    // leitura da onda.
    expect(share!).toBeGreaterThan(0.94);
  });

  it('denominador e o proprio lado, nao otelTotalTokens (que mistura fontes)', () => {
    const main = otelMainTokens(waveOtelUsage(WAVE_V12));
    const share = cacheReadShare(main);
    expect(share!).toBeCloseTo(3_709_177 / (34 + 11_325 + 3_709_177 + 19_242), 6);
    // Usar otelTotalTokens (8.78M) daria ~0.42 — subestimando pela metade.
    expect(share!).toBeGreaterThan(0.9);
  });
});

describe('sumOtelUsage — breakdown por fonte', () => {
  it('cada lado conta SO as ondas que mediram aquele lado', () => {
    const total = sumOtelUsage([WAVE_V12, WAVE_V12_SO_SUBAGENTE, BASE_WAVE]);
    // 2 ondas mediram subagente, 1 mediu main, 3 ondas no recorte.
    expect(total.wavesWithSubagentBreakdown).toBe(2);
    expect(total.wavesWithMainBreakdown).toBe(1);
    expect(total.wavesTotal).toBe(3);
  });

  it('soma preserva null quando nenhuma onda mediu o lado', () => {
    const total = sumOtelUsage([WAVE_V12_SO_SUBAGENTE]);
    expect(total.mainInputTokens).toBeNull();
    expect(total.mainCacheReadTokens).toBeNull();
    expect(total.subagentCacheReadTokens).toBe(4_615_562);
  });

  it('soma os lados medidos entre ondas', () => {
    const total = sumOtelUsage([WAVE_V12, WAVE_V12_SO_SUBAGENTE]);
    expect(total.subagentCacheReadTokens).toBe(4_615_562 * 2);
    // Somente a onda-012 mediu o main: o total do lado main e o dela.
    expect(total.mainCacheReadTokens).toBe(3_709_177);
  });
});
