/**
 * Escolha da fonte de token exibida (OTel v11 > hook de spawn v10).
 *
 * O caso que originou o helper esta em `defende o caso de producao`: onda com
 * `otel_cost_usd = 3.14` e `otel_total_tokens = 7.228.603`, mas `agent_*`
 * inteiramente NULL porque o hook agent-usage nunca foi provisionado naquele
 * projeto. A UI antiga lia so a v10 e exibia "—" no token ao lado de um custo
 * medido — dois numeros da mesma onda contando historias diferentes.
 */
import { describe, it, expect } from 'vitest';
import { pickTokens, tokenCoverageLabel, tokenSourceTip } from '@/lib/token-source.js';
import type { AgentUsageRollup, OtelUsageRollup } from '@cstk-panel/shared-types';

const NO_OTEL: OtelUsageRollup = {
  costUsd: null, costMainUsd: null, costSubagentUsd: null,
  totalTokens: null, subagentTokens: null,
  wavesWithOtel: null, wavesTotal: 1,
};

/** Valores reais da onda-022 de mcp-project-scafold (knowledge.db v11). */
const OTEL: OtelUsageRollup = {
  costUsd: 3.14147, costMainUsd: 0, costSubagentUsd: 3.14147,
  totalTokens: 7_228_603, subagentTokens: 7_224_500,
  wavesWithOtel: 1, wavesTotal: 1,
};

const NO_AGENT: AgentUsageRollup = {
  spawnsTotal: null, spawnsWithUsage: null, totalTokens: null,
  inputTokens: null, outputTokens: null, cacheReadTokens: null,
  cacheCreationTokens: null, toolUseCount: null, durationMs: null,
  wavesWithUsage: null, wavesTotal: 1,
};

const AGENT_PARTIAL: AgentUsageRollup = {
  ...NO_AGENT,
  spawnsTotal: 4, spawnsWithUsage: 3, totalTokens: 248_500,
  wavesWithUsage: 1,
};

const AGENT_NO_DATA: AgentUsageRollup = {
  ...NO_AGENT, spawnsTotal: 2, spawnsWithUsage: 0, wavesWithUsage: 1,
};

describe('pickTokens', () => {
  it('defende o caso de producao: OTel medido + v10 ausente exibe o numero', () => {
    const pick = pickTokens(OTEL, NO_AGENT);
    expect(pick.tokens).toBe(7_228_603);
    expect(pick.source).toBe('otel');
    // OTel cobre a onda inteira: nao ha amostra parcial a sinalizar
    expect(pick.partial).toBe(false);
  });

  it('OTel vence a v10 quando as duas mediram (cobre main + subagentes)', () => {
    const pick = pickTokens(OTEL, AGENT_PARTIAL);
    expect(pick.tokens).toBe(7_228_603);
    expect(pick.source).toBe('otel');
  });

  it('sem telemetria, cai para a v10 preservando o marcador de amostra', () => {
    const pick = pickTokens(NO_OTEL, AGENT_PARTIAL);
    expect(pick.tokens).toBe(248_500);
    expect(pick.source).toBe('agent');
    expect(pick.partial).toBe(true);
  });

  it('amostra v10 integral nao vira parcial', () => {
    const pick = pickTokens(NO_OTEL, { ...AGENT_PARTIAL, spawnsWithUsage: 4 });
    expect(pick.partial).toBe(false);
  });

  it('nenhuma fonte mediu => null, nunca 0', () => {
    const pick = pickTokens(NO_OTEL, NO_AGENT);
    expect(pick.tokens).toBeNull();
    expect(pick.source).toBeNull();
  });

  it('rollups ausentes nao inventam consumo', () => {
    expect(pickTokens(null, null).tokens).toBeNull();
    expect(pickTokens(undefined, undefined).source).toBeNull();
  });

  it('custo medido sem token medido nao empresta o custo como token', () => {
    const pick = pickTokens({ ...OTEL, totalTokens: null }, NO_AGENT);
    expect(pick.tokens).toBeNull();
  });
});

describe('tokenCoverageLabel', () => {
  it('reporta a cobertura da fonte que venceu', () => {
    const otelPick = pickTokens(OTEL, AGENT_PARTIAL);
    expect(tokenCoverageLabel(otelPick, OTEL, AGENT_PARTIAL)).toBe('1 de 1 ondas medidas');

    const agentPick = pickTokens(NO_OTEL, AGENT_PARTIAL);
    expect(tokenCoverageLabel(agentPick, NO_OTEL, AGENT_PARTIAL)).toBe('3 de 4 spawns medidos');
  });

  it('distingue "houve spawn e ninguem reportou" de "nao houve coleta"', () => {
    const noData = pickTokens(NO_OTEL, AGENT_NO_DATA);
    expect(tokenCoverageLabel(noData, NO_OTEL, AGENT_NO_DATA)).toContain('não é consumo zero');

    const none = pickTokens(NO_OTEL, NO_AGENT);
    expect(tokenCoverageLabel(none, NO_OTEL, NO_AGENT)).toBe('não coletado nesta fonte');
  });
});

describe('tokenSourceTip', () => {
  it('diz o que o numero abrange em cada fonte', () => {
    expect(tokenSourceTip(pickTokens(OTEL, NO_AGENT))).toContain('subagentes');
    expect(tokenSourceTip(pickTokens(NO_OTEL, AGENT_PARTIAL))).toContain('não inclui o orquestrador');
    expect(tokenSourceTip(pickTokens(NO_OTEL, NO_AGENT))).toContain('não coletado');
  });
});
