/**
 * Teste de integração (FASE 3.4.1) — SC-005: o mesmo período/projeto
 * selecionado nas duas telas (Overview.tsx e Metrics.tsx) produz exatamente
 * os mesmos valores de `costUsd`/`totalTokens` por modelo.
 *
 * Overview.tsx e Metrics.tsx consomem o MESMO payload bruto do endpoint
 * `/metrics/model-usage` (mesmo período/projeto -> mesma resposta de rede,
 * `useMetric('model-usage', period)` em ambos os arquivos) através do MESMO
 * módulo puro de seleção (`selectModelUsage`, FASE 3.1). Este teste simula os
 * dois pontos de consumo — cada tela chama `selectModelUsage(raw)`
 * independentemente sobre o payload idêntico, exatamente como
 * `Overview.tsx:143` e `Metrics.tsx:445` fazem — e verifica que:
 *
 *   1. As duas chamadas produzem view-models deep-equal (determinismo: a
 *      seleção não depende de estado externo/ordem de invocação);
 *   2. Os valores de `costUsd`/`totalTokens` exibidos no resumo compacto do
 *      Overview (`vm.top`, via `ModelUsageMiniList`) batem, modelo a modelo,
 *      com os valores exibidos no detalhe completo de Metrics (`vm.entries`,
 *      via `ModelUsageDetailPanel`) — nenhuma tela reagrega/reordena o dado
 *      de forma divergente da outra.
 *
 * Sem harness de render DOM neste repo (`environment: node`, sem jsdom/
 * @testing-library) — mesmo precedente de `components/ModelUsage.test.ts`:
 * invoca os componentes funcionais diretamente e inspeciona a árvore de
 * `ReactElement` retornada.
 */
import { describe, it, expect } from 'vitest';
import type { ReactNode } from 'react';
import { selectModelUsage, groupModelUsageByStage } from '../lib/model-usage-select.js';
import { ModelUsageMiniList, ModelUsageDetailPanel } from '../components/ModelUsage.js';
import type { ModelUsageResult } from '@cstk-panel/shared-types';

/** Mesmo extrator de texto de `components/ModelUsage.test.ts` (sem duplicar
 * a lógica de percorrer a árvore de ReactElement sem DOM). */
function extractText(node: ReactNode): string[] {
  if (node == null || typeof node === 'boolean') return [];
  if (typeof node === 'string' || typeof node === 'number') return [String(node)];
  if (Array.isArray(node)) return node.flatMap(extractText);
  if (typeof node === 'object' && 'type' in node) {
    const el = node as { type: unknown; props: Record<string, unknown> };
    if (typeof el.type === 'function') {
      const rendered = (el.type as (props: unknown) => ReactNode)(el.props);
      return extractText(rendered);
    }
    const children = (el.props as { children?: ReactNode } | undefined)?.children;
    return extractText(children);
  }
  return [];
}

/** Payload sintético — mesmo período/projeto, tal como o backend retornaria
 * para uma única chamada de `GET /api/v1/metrics/model-usage`. */
const RAW: ModelUsageResult = {
  byModel: [
    { model: 'claude-sonnet-5', costUsd: 905.39, totalTokens: 2189357933, waves: 41 },
    { model: 'claude-fable-5', costUsd: 23.59, totalTokens: 13884110, waves: 7 },
    { model: 'claude-opus-5[1m]', costUsd: 6.14, totalTokens: 6864604, waves: 1 },
  ],
  byStage: [
    { stage: 'execute-task', model: 'claude-sonnet-5', costUsd: 601.11, totalTokens: 1400000000 },
    { stage: 'plan', model: 'claude-opus-5[1m]', costUsd: 6.14, totalTokens: 6864604 },
  ],
  coverage: { wavesTotal: 920, wavesWithModelUsage: 36, wavesWithOtelCost: 46 },
};

describe('Consistência Overview x Metrics (SC-005, 3.4.1)', () => {
  it('selectModelUsage(raw) e determinístico entre as duas chamadas independentes (Overview e Metrics)', () => {
    // Overview.tsx:143 e Metrics.tsx:445 chamam selectModelUsage() de forma
    // totalmente independente, uma em cada arquivo — simulado aqui por duas
    // invocações separadas sobre o MESMO raw (mesmo período/projeto).
    const vmOverview = selectModelUsage(RAW);
    const vmMetrics = selectModelUsage(RAW);
    expect(vmOverview).toEqual(vmMetrics);
  });

  it('o custo/tokens por modelo exibido no KPI compacto (Overview) bate com o detalhe completo (Metrics)', () => {
    const vmOverview = selectModelUsage(RAW);
    const vmMetrics = selectModelUsage(RAW);
    const stageGroups = groupModelUsageByStage(RAW.byStage);

    const overviewText = extractText(ModelUsageMiniList({ vm: vmOverview })).join(' ');
    const metricsText = extractText(
      ModelUsageDetailPanel({ vm: vmMetrics, stageGroups })
    ).join(' ');

    // Cada modelo presente no resumo compacto (top-3) deve aparecer com o
    // MESMO valor formatado de costUsd no detalhe completo — nenhuma das
    // duas telas reagrega/arredonda o valor de forma diferente.
    for (const entry of vmOverview.top) {
      const formattedCost = entry.costUsd == null ? '—' : `$${entry.costUsd.toFixed(2)}`;
      expect(overviewText).toContain(entry.model);
      expect(overviewText).toContain(formattedCost);
      expect(metricsText).toContain(entry.model);
      expect(metricsText).toContain(formattedCost);
    }
  });

  it('entries (Metrics) e um superset determinístico de top (Overview) — mesma ordenação por costUsd desc', () => {
    const vm = selectModelUsage(RAW);
    expect(vm.entries.slice(0, vm.top.length)).toEqual(vm.top);
  });
});
