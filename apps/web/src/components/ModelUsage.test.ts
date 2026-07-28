/**
 * Teste do KPI compacto de custo por modelo (FASE 3.2.4 — Overview).
 *
 * Segue o mesmo precedente de `lib/otel-usage.test.ts`: nao ha harness de
 * render DOM (jsdom/@testing-library) neste repositorio — `environment: node`
 * no vitest raiz. Como `ModelUsageMiniList`/`ModelUsageEmpty` sao funcoes
 * React puras (`(props) => ReactElement`), chama-las diretamente ja produz a
 * arvore de elementos (objetos simples, via `react/jsx-runtime`) sem exigir
 * um DOM — o suficiente para verificar que os 3 estados (`measured`/`empty`/
 * `degraded`) nunca colapsam visualmente (US1 Acceptance Scenario 2).
 */
import { describe, it, expect } from 'vitest';
import type { ReactNode } from 'react';
import {
  ModelUsageMiniList, ModelUsageEmpty, modelUsageColor,
  ModelUsageDetailPanel, ModelUsageStageBreakdown,
} from './ModelUsage.js';
import { MODEL_USAGE_NATURE_LABEL, type ModelUsageVM, type ModelUsageByStageGroup } from '@/lib/model-usage-select.js';

/**
 * Extrai todo texto (string/number) de uma arvore de ReactElement, em ordem.
 * Sem renderer (jsdom/@testing-library, ausentes deste repo — ver cabecalho),
 * um elemento de COMPONENTE (`type` = funcao, ex. `ModelUsageMiniRow`) nao
 * expande sozinho: `props.children` so existe em elementos DOM (`div`/`span`).
 * Por isso invocamos a funcao do componente diretamente para obter sua arvore
 * renderizada antes de recursar — seguro aqui porque nenhum destes
 * componentes usa hooks (sao presentational puros).
 */
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

/**
 * Achata `children` UM nivel de logica de renderizacao (sem descer para
 * dentro de cada elemento) — necessario porque `{arr.map(...)}` seguido de
 * outro filho produz `children = [mapArrayResult, outroElemento]`, uma
 * arvore aninhada que um filtro raso nao enxerga corretamente.
 */
function flattenChildren(node: unknown): unknown[] {
  if (node == null || typeof node === 'boolean') return [];
  if (Array.isArray(node)) return node.flatMap(flattenChildren);
  return [node];
}

const MEASURED_VM: ModelUsageVM = {
  state: 'measured',
  entries: [
    { model: 'claude-sonnet-5', costUsd: 905.39, totalTokens: 2189357933, waves: 41 },
    { model: 'claude-fable-5', costUsd: 23.59, totalTokens: 13884110, waves: 7 },
    { model: 'claude-opus-5[1m]', costUsd: 6.14, totalTokens: 6864604, waves: 1 },
  ],
  top: [
    { model: 'claude-sonnet-5', costUsd: 905.39, totalTokens: 2189357933, waves: 41 },
    { model: 'claude-fable-5', costUsd: 23.59, totalTokens: 13884110, waves: 7 },
    { model: 'claude-opus-5[1m]', costUsd: 6.14, totalTokens: 6864604, waves: 1 },
  ],
  coverage: { wavesTotal: 920, wavesWithModelUsage: 36, wavesWithOtelCost: 46 },
};

const EMPTY_VM: ModelUsageVM = {
  state: 'empty',
  entries: [],
  top: [],
  coverage: { wavesTotal: 12, wavesWithModelUsage: 0, wavesWithOtelCost: 0 },
};

const DEGRADED_VM: ModelUsageVM = {
  state: 'degraded',
  entries: [],
  top: [],
  coverage: { wavesTotal: null, wavesWithModelUsage: null, wavesWithOtelCost: null },
};

describe('ModelUsageMiniList — estado measured', () => {
  it('mostra o modelo de maior custo primeiro, com rotulo "medido"', () => {
    const text = extractText(ModelUsageMiniList({ vm: MEASURED_VM })).join(' ');
    expect(text).toContain('claude-sonnet-5');
    expect(text).toContain('$905.39');
    expect(text).toContain(MODEL_USAGE_NATURE_LABEL);
  });

  it('respeita o limite de 1.2.2/dec-038: no maximo top-3 modelos', () => {
    const el = ModelUsageMiniList({ vm: MEASURED_VM });
    const children = flattenChildren(el.props.children).filter(
      (c) => typeof c === 'object' && c !== null && 'type' in c
    );
    // 3 linhas de modelo (ModelUsageMiniRow) + 1 linha de rotulo de cobertura = 4
    expect(children.length).toBe(MEASURED_VM.top.length + 1);
  });

  it('nunca soma costUsd de modelos distintos — cada linha mostra o proprio valor', () => {
    const text = extractText(ModelUsageMiniList({ vm: MEASURED_VM })).join(' ');
    expect(text).toContain('$23.59');
    expect(text).toContain('$6.14');
  });
});

describe('ModelUsageMiniList — estado empty (sem dado no periodo)', () => {
  it('nao mostra "$0" nem qualquer costUsd — mensagem de ausencia explicita', () => {
    const text = extractText(ModelUsageMiniList({ vm: EMPTY_VM })).join(' ');
    expect(text).not.toContain('$0');
    expect(text.toLowerCase()).toContain('nenhum modelo');
  });
});

describe('ModelUsageMiniList — estado degraded (fonte nao coleta o dado)', () => {
  it('mensagem distingue "nao coletado" de "sem dado no periodo"', () => {
    const text = extractText(ModelUsageMiniList({ vm: DEGRADED_VM })).join(' ');
    expect(text.toLowerCase()).toContain('não coletado');
    expect(text).toContain('wave_model_usage');
    expect(text.toLowerCase()).not.toContain('nenhum modelo');
  });
});

describe('ModelUsageEmpty', () => {
  it('estado "empty" e "degraded" produzem textos distintos', () => {
    const emptyText = extractText(ModelUsageEmpty({ reason: 'empty' })).join(' ');
    const degradedText = extractText(ModelUsageEmpty({ reason: 'degraded' })).join(' ');
    expect(emptyText).not.toBe(degradedText);
  });
});

describe('modelUsageColor', () => {
  it('resolve cor conhecida para haiku/sonnet/opus', () => {
    expect(modelUsageColor('sonnet')).toBe('var(--model-sonnet)');
    expect(modelUsageColor('haiku')).toBe('var(--model-haiku)');
  });

  it('cai para a cor fallback em modelo desconhecido (string bruta de telemetria)', () => {
    expect(modelUsageColor('claude-sonnet-5')).toBe('var(--model-fallback)');
  });

  it('nao e vulneravel a poluicao de prototipo via chave externa bruta', () => {
    expect(modelUsageColor('constructor')).toBe('var(--model-fallback)');
    expect(modelUsageColor('toString')).toBe('var(--model-fallback)');
    expect(modelUsageColor('__proto__')).toBe('var(--model-fallback)');
  });
});

// ---------------------------------------------------------------------------
// ModelUsageDetailPanel — detalhe completo (FASE 3.3.6, Metrics.tsx)
// ---------------------------------------------------------------------------

const STAGE_GROUPS: ModelUsageByStageGroup[] = [
  {
    stage: 'execute-task',
    entries: [
      { stage: 'execute-task', model: 'claude-sonnet-5', costUsd: 246.87, totalTokens: 601627942 },
    ],
  },
];

const MEASURED_WITH_ZERO_VM: ModelUsageVM = {
  state: 'measured',
  entries: [
    { model: 'claude-sonnet-5', costUsd: 905.39, totalTokens: 2189357933, waves: 41 },
    { model: 'claude-haiku-5', costUsd: 0, totalTokens: 0, waves: 2 },
  ],
  top: [
    { model: 'claude-sonnet-5', costUsd: 905.39, totalTokens: 2189357933, waves: 41 },
  ],
  coverage: { wavesTotal: 920, wavesWithModelUsage: 36, wavesWithOtelCost: 46 },
};

describe('ModelUsageDetailPanel — estado measured', () => {
  it('mostra modelo, tokens, custo por modelo e os 3 denominadores de cobertura', () => {
    const text = extractText(ModelUsageDetailPanel({ vm: MEASURED_VM, stageGroups: STAGE_GROUPS })).join(' ');
    expect(text).toContain('claude-sonnet-5');
    expect(text).toContain('$905.39');
    // 3 denominadores independentes (3.3.2): wavesTotal, wavesWithModelUsage, wavesWithOtelCost
    expect(text).toContain('36');
    expect(text).toContain('46');
    expect(text).toContain('920');
    // recorte por etapa (byStage)
    expect(text).toContain('execute-task');
    expect(text).toContain('$246.87');
  });

  it('nao soma custoUsd entre modelos distintos — cada linha mantem seu proprio valor (3.3.3)', () => {
    const text = extractText(ModelUsageDetailPanel({ vm: MEASURED_VM, stageGroups: STAGE_GROUPS })).join(' ');
    expect(text).toContain('$23.59');
    expect(text).toContain('$6.14');
  });
});

describe('ModelUsageDetailPanel — custo medido igual a zero (3c)', () => {
  it('exibe "$0" distinto de "—" (null) e nunca colapsa com o estado empty/degraded', () => {
    const text = extractText(ModelUsageDetailPanel({ vm: MEASURED_WITH_ZERO_VM, stageGroups: [] })).join(' ');
    expect(text).toContain('$0');
    expect(text).toContain('claude-haiku-5');
    expect(text.toLowerCase()).not.toContain('nenhum modelo');
    expect(text.toLowerCase()).not.toContain('não coletado');
  });
});

describe('ModelUsageDetailPanel — estado empty (sem dado no periodo)', () => {
  it('cai no ModelUsageEmpty (reason=empty), sem "$0" nem tabela de modelos', () => {
    const text = extractText(ModelUsageDetailPanel({ vm: EMPTY_VM, stageGroups: [] })).join(' ');
    expect(text).not.toContain('$0');
    expect(text.toLowerCase()).toContain('nenhum modelo');
  });
});

describe('ModelUsageDetailPanel — estado degraded (fonte nao coleta o dado)', () => {
  it('cai no ModelUsageEmpty (reason=degraded), texto distinto do estado empty', () => {
    const emptyText = extractText(ModelUsageDetailPanel({ vm: EMPTY_VM, stageGroups: [] })).join(' ');
    const degradedText = extractText(ModelUsageDetailPanel({ vm: DEGRADED_VM, stageGroups: [] })).join(' ');
    expect(degradedText).not.toBe(emptyText);
    expect(degradedText.toLowerCase()).toContain('não coletado');
  });
});

describe('ModelUsageStageBreakdown', () => {
  it('groups=[] (correlacao onda x etapa nao resolvel) mostra mensagem propria, nao dado inventado', () => {
    const text = extractText(ModelUsageStageBreakdown({ groups: [] })).join(' ');
    expect(text.toLowerCase()).toContain('sem correlação');
  });

  it('renderiza cada etapa com seus modelos, sem somar custo entre etapas', () => {
    const text = extractText(ModelUsageStageBreakdown({ groups: STAGE_GROUPS })).join(' ');
    expect(text).toContain('execute-task');
    expect(text).toContain('claude-sonnet-5');
    expect(text).toContain('$246.87');
  });
});
