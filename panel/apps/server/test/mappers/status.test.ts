/**
 * Testes unitarios do normalizador de status (mappers/status.ts).
 *
 * Regressao: a knowledge.db (escrita por LLM) pode conter variantes fora do
 * contrato (ex.: 'concluido' no lugar de 'concluida'). O painel e read-only e
 * NUNCA pode emitir um enum invalido — isso estourava a validacao Zod no
 * cliente e derrubava a lista inteira de features.
 */
import { describe, it, expect } from 'vitest';
import { FeatureRollupSchema } from '@cstk-panel/shared-types';
import { normalizeStatus } from '../../src/mappers/status.js';
import { mapExecution } from '../../src/mappers/execution.js';

describe('normalizeStatus', () => {
  it('passa valores canonicos sem alteracao', () => {
    expect(normalizeStatus('em_andamento')).toBe('em_andamento');
    expect(normalizeStatus('aguardando_humano')).toBe('aguardando_humano');
    expect(normalizeStatus('concluida')).toBe('concluida');
    expect(normalizeStatus('abortada')).toBe('abortada');
  });

  it('remapeia variantes conhecidas (typo de genero) para o canonico', () => {
    expect(normalizeStatus('concluido')).toBe('concluida');
    expect(normalizeStatus('abortado')).toBe('abortada');
  });

  it('degrada valores desconhecidos para null (nunca enum invalido)', () => {
    expect(normalizeStatus('finalizado')).toBeNull();
    expect(normalizeStatus('CONCLUIDA')).toBeNull(); // case-sensitive de proposito
    expect(normalizeStatus('')).toBeNull();
  });

  it('trata null/undefined como null', () => {
    expect(normalizeStatus(null)).toBeNull();
    expect(normalizeStatus(undefined)).toBeNull();
  });
});

describe('FeatureRollup latestStatus — tolerante a variante upstream', () => {
  it('o enum normalizado satisfaz o contrato Zod (nao estoura como o cru)', () => {
    const rollup = {
      project: 'proj',
      feature: 'feat',
      totalExecutions: 1,
      activeExecutions: 0,
      completedExecutions: 1,
      abortedExecutions: 0,
      totalToolCalls: 10,
      totalWallclock: 100,
      totalDecisions: 2,
      totalOndas: 1,
      totalBloqueios: 0,
      etapaCorrente: 'concluida',
      openAlerts: 0,
      latestStatus: normalizeStatus('concluido'), // valor cru hostil → 'concluida'
      latestExecutionAt: '2026-05-27T00:00:00Z',
    };
    expect(rollup.latestStatus).toBe('concluida');
    expect(FeatureRollupSchema.parse(rollup).latestStatus).toBe('concluida');
  });
});

describe('mapExecution — status normalizado', () => {
  const baseRow = {
    project: 'p', feature: 'f', execucao_id: 'e1', motivo_termino: null,
    etapa_corrente: null, iniciada_em: null, terminada_em: null,
    duracao_segundos: null, stack_sugerida: null, ondas_total: null,
    tool_calls_total: null, wallclock_total_segundos: null,
    subagentes_spawned: null, profundidade_max: null, decisoes_total: null,
    bloqueios_humanos_total: null, sugestoes_skills_total: null,
    issues_toolkit_abertas: null,
  };

  it('remapeia status cru "concluido" para "concluida"', () => {
    // @ts-expect-error — linha de teste minima; campos extras irrelevantes
    expect(mapExecution({ ...baseRow, status: 'concluido' }).status).toBe('concluida');
  });

  it('degrada status desconhecido para null', () => {
    // @ts-expect-error — linha de teste minima
    expect(mapExecution({ ...baseRow, status: 'sei_la' }).status).toBeNull();
  });
});
