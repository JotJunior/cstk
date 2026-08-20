/**
 * Testes unitários do engine de layout (árvore) do Decision Map Panel.
 *
 * Modelo: cada decisão é um pill; suas opcoes viram retângulos-opção; a opção
 * escolhida liga à próxima decisão (espinha). Nó terminal "Fim" ao final.
 *
 * Ref: spec §FR-002..FR-005, §SC-002
 * Execução: vitest run apps/web/src/lib/decision-map-layout.test.ts
 */

import { describe, it, expect } from 'vitest';
import {
  computeLayout,
  deriveOptions,
  parseOpcoes,
  prevKey,
  nextKey,
  PADDING,
  PILL_W,
  OPT_W,
} from './decision-map-layout.js';
import type { DecisionDTO } from '@cstk-panel/shared-types';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function mkDecision(wave: string, overrides: Partial<DecisionDTO> = {}): DecisionDTO {
  return {
    wave,
    executionId: 'exec-test',
    stage: 'plan',
    agent: null,
    choice: 'B',
    options: JSON.stringify(['A', 'B', 'C']),
    score: null,
    context: null,
    rationale: null,
    evidencia: null,
    decisionClass: null,
    structuralAxis: null,
    humanConsentBlockId: null,
    ...overrides,
  };
}

// ---------------------------------------------------------------------------
// parseOpcoes / deriveOptions
// ---------------------------------------------------------------------------

describe('parseOpcoes', () => {
  it('parseia JSON array', () => {
    expect(parseOpcoes('["a","b"]')).toEqual(['a', 'b']);
  });
  it('null → []', () => {
    expect(parseOpcoes(null)).toEqual([]);
  });
  it('JSON inválido → [] (degradação graciosa)', () => {
    expect(parseOpcoes('{nope')).toEqual([]);
  });
  it('não-array → []', () => {
    expect(parseOpcoes('"x"')).toEqual([]);
  });
});

describe('deriveOptions', () => {
  it('marca a opção escolhida pelo match com escolha', () => {
    const { opts, chosenIdx } = deriveOptions(mkDecision('w', { options: '["A","B","C"]', choice: 'B' }));
    expect(opts).toEqual(['A', 'B', 'C']);
    expect(chosenIdx).toBe(1);
  });

  it('match é tolerante a espaços/caixa', () => {
    const { chosenIdx } = deriveOptions(mkDecision('w', { options: '["Haiku","Sonnet"]', choice: '  sonnet ' }));
    expect(chosenIdx).toBe(1);
  });

  it('escolha com prefixo de namespace casa com a opção (não anexa fantasma)', () => {
    const { opts, chosenIdx } = deriveOptions(
      mkDecision('w', {
        options: '["haiku","sonnet","opus","manter-atual"]',
        choice: 'model:sonnet',
      }),
    );
    expect(opts).toEqual(['haiku', 'sonnet', 'opus', 'manter-atual']);
    expect(chosenIdx).toBe(1);
  });

  it('escolha ausente das opcoes é anexada como escolhida', () => {
    const { opts, chosenIdx } = deriveOptions(mkDecision('w', { options: '["A","B"]', choice: 'Z' }));
    expect(opts).toEqual(['A', 'B', 'Z']);
    expect(chosenIdx).toBe(2);
  });

  it('sem opcoes mas com escolha → escolha vira a única opção', () => {
    const { opts, chosenIdx } = deriveOptions(mkDecision('w', { options: null, choice: 'X' }));
    expect(opts).toEqual(['X']);
    expect(chosenIdx).toBe(0);
  });

  it('escolha nula → chosenIdx -1', () => {
    const { opts, chosenIdx } = deriveOptions(mkDecision('w', { options: '["A","B"]', choice: null }));
    expect(opts).toEqual(['A', 'B']);
    expect(chosenIdx).toBe(-1);
  });
});

// ---------------------------------------------------------------------------
// computeLayout — casos base
// ---------------------------------------------------------------------------

describe('computeLayout — array vazio', () => {
  it('retorna layout vazio', () => {
    const layout = computeLayout([]);
    expect(layout.nodes).toEqual([]);
    expect(layout.edges).toEqual([]);
    expect(layout.svgWidth).toBe(0);
    expect(layout.svgHeight).toBe(0);
  });
});

describe('computeLayout — 1 decisão com 3 opções (escolha = B)', () => {
  const items = [mkDecision('onda-001', { options: '["A","B","C"]', choice: 'B' })];
  const layout = computeLayout(items);

  it('produz 1 pill + 3 opções + Fim = 5 nós', () => {
    expect(layout.nodes).toHaveLength(5);
    expect(layout.nodes.filter((n) => n.kind === 'decision')).toHaveLength(1);
    expect(layout.nodes.filter((n) => n.kind === 'option')).toHaveLength(3);
    expect(layout.nodes.filter((n) => n.kind === 'end')).toHaveLength(1);
  });

  it('3 arestas de galho + 1 de espinha (escolhida → Fim)', () => {
    const branch = layout.edges.filter((e) => e.kind === 'branch');
    const spine = layout.edges.filter((e) => e.kind === 'spine');
    expect(branch).toHaveLength(3);
    expect(spine).toHaveLength(1);
    expect(spine[0]!.from).toBe('opt::0::1'); // B escolhida
    expect(spine[0]!.to).toBe('end');
  });

  it('a opção escolhida é a de índice 1 (B)', () => {
    const chosen = layout.nodes.filter((n) => n.kind === 'option' && n.chosen);
    expect(chosen).toHaveLength(1);
    expect(chosen[0]!.key).toBe('opt::0::1');
    expect(chosen[0]!.label).toBe('B');
  });

  it('chaves estáveis dec::/opt::/end', () => {
    expect(layout.nodes[0]!.key).toBe('dec::0');
    expect(layout.nodes.some((n) => n.key === 'opt::0::0')).toBe(true);
    expect(layout.nodes.some((n) => n.key === 'end')).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// computeLayout — cadeia de várias decisões (galhos)
// ---------------------------------------------------------------------------

describe('computeLayout — cadeia de 3 decisões', () => {
  const items = [
    mkDecision('onda-001', { stage: 'specify', options: '["A","B","C"]', choice: 'B' }),
    mkDecision('onda-002', { stage: 'plan', options: '["D","E","F"]', choice: 'D' }),
    mkDecision('onda-003', { stage: 'tasks', options: '["G","H","I"]', choice: 'I' }),
  ];
  const layout = computeLayout(items);

  it('3 pills + 9 opções + Fim = 13 nós', () => {
    expect(layout.nodes.filter((n) => n.kind === 'decision')).toHaveLength(3);
    expect(layout.nodes.filter((n) => n.kind === 'option')).toHaveLength(9);
    expect(layout.nodes.filter((n) => n.kind === 'end')).toHaveLength(1);
  });

  it('espinha liga a opção escolhida de cada decisão à próxima decisão', () => {
    const spine = layout.edges.filter((e) => e.kind === 'spine');
    expect(spine).toHaveLength(3); // dec0→dec1, dec1→dec2, dec2→end
    expect(spine[0]!.from).toBe('opt::0::1'); // B
    expect(spine[0]!.to).toBe('dec::1');
    expect(spine[1]!.from).toBe('opt::1::0'); // D
    expect(spine[1]!.to).toBe('dec::2');
    expect(spine[2]!.from).toBe('opt::2::2'); // I
    expect(spine[2]!.to).toBe('end');
  });

  it('cada decisão tem 3 arestas de galho', () => {
    expect(layout.edges.filter((e) => e.kind === 'branch')).toHaveLength(9);
  });

  it('a próxima decisão nasce centralizada sob a opção escolhida da anterior', () => {
    const optChosen0 = layout.nodes.find((n) => n.key === 'opt::0::1')!;
    const pill1 = layout.nodes.find((n) => n.key === 'dec::1')!;
    const optCenter = optChosen0.x + OPT_W / 2;
    const pillCenter = pill1.x + PILL_W / 2;
    expect(Math.abs(optCenter - pillCenter)).toBeLessThan(0.5);
  });

  it('a próxima decisão fica ABAIXO das opções da anterior', () => {
    const opt0 = layout.nodes.find((n) => n.key === 'opt::0::0')!;
    const pill1 = layout.nodes.find((n) => n.key === 'dec::1')!;
    expect(pill1.y).toBeGreaterThan(opt0.y + opt0.h);
  });
});

// ---------------------------------------------------------------------------
// Normalização de coordenadas
// ---------------------------------------------------------------------------

describe('computeLayout — normalização', () => {
  it('nenhum x é negativo; menor x === PADDING', () => {
    // Escolhas à esquerda forçam a espinha a derivar — exige normalização.
    const items = [
      mkDecision('w', { options: '["A","B","C"]', choice: 'A' }),
      mkDecision('w', { options: '["D","E","F"]', choice: 'D' }),
      mkDecision('w', { options: '["G","H","I"]', choice: 'G' }),
    ];
    const layout = computeLayout(items);
    const minX = Math.min(...layout.nodes.map((n) => n.x));
    expect(minX).toBe(PADDING);
    expect(layout.nodes.every((n) => n.x >= 0)).toBe(true);
  });

  it('svgWidth e svgHeight encapsulam todos os nós com PADDING', () => {
    const items = [mkDecision('w', { options: '["A","B","C"]', choice: 'B' })];
    const layout = computeLayout(items);
    const maxRight = Math.max(...layout.nodes.map((n) => n.x + n.w));
    const maxBottom = Math.max(...layout.nodes.map((n) => n.y + n.h));
    expect(layout.svgWidth).toBeGreaterThanOrEqual(maxRight + PADDING);
    expect(layout.svgHeight).toBeGreaterThanOrEqual(maxBottom);
  });
});

// ---------------------------------------------------------------------------
// Casos defensivos
// ---------------------------------------------------------------------------

describe('computeLayout — decisão sem opções nem escolha', () => {
  const items = [mkDecision('w', { options: null, choice: null })];
  const layout = computeLayout(items);

  it('produz só o pill + Fim (sem opções)', () => {
    expect(layout.nodes.filter((n) => n.kind === 'option')).toHaveLength(0);
    expect(layout.nodes.filter((n) => n.kind === 'decision')).toHaveLength(1);
    expect(layout.nodes.filter((n) => n.kind === 'end')).toHaveLength(1);
  });

  it('espinha parte da própria decisão para o Fim', () => {
    const spine = layout.edges.filter((e) => e.kind === 'spine');
    expect(spine).toHaveLength(1);
    expect(spine[0]!.from).toBe('dec::0');
    expect(spine[0]!.to).toBe('end');
  });
});

describe('computeLayout — escolha null com opções (nenhuma escolhida)', () => {
  const items = [mkDecision('w', { options: '["A","B"]', choice: null })];
  const layout = computeLayout(items);

  it('renderiza as opções mas nenhuma é chosen', () => {
    const opts = layout.nodes.filter((n) => n.kind === 'option');
    expect(opts).toHaveLength(2);
    expect(opts.every((o) => !o.chosen)).toBe(true);
  });

  it('espinha parte da decisão (sem opção escolhida)', () => {
    const spine = layout.edges.filter((e) => e.kind === 'spine');
    expect(spine[0]!.from).toBe('dec::0');
  });
});

// ---------------------------------------------------------------------------
// Benchmark (SC-002)
// ---------------------------------------------------------------------------

describe('computeLayout — performance', () => {
  it('< 10ms para 100 decisões', () => {
    const items: DecisionDTO[] = Array.from({ length: 100 }, (_, i) =>
      mkDecision(`onda-${String(Math.floor(i / 10) + 1).padStart(3, '0')}`, {
        options: '["A","B","C"]',
        choice: 'B',
      })
    );
    const t0 = performance.now();
    for (let i = 0; i < 10; i++) computeLayout(items);
    const avg = (performance.now() - t0) / 10;
    expect(avg).toBeLessThan(10);
  });
});

// ---------------------------------------------------------------------------
// Navegação prev/next (entre DECISÕES)
// ---------------------------------------------------------------------------

describe('prevKey / nextKey — navegam entre decisões', () => {
  const items = [
    mkDecision('w', { choice: 'B' }),
    mkDecision('w', { choice: 'B' }),
    mkDecision('w', { choice: 'B' }),
  ];
  const { nodes } = computeLayout(items);

  it('prevKey da primeira decisão é null', () => {
    expect(prevKey(nodes, 'dec::0')).toBeNull();
  });

  it('nextKey da última decisão é null (Fim não conta)', () => {
    expect(nextKey(nodes, 'dec::2')).toBeNull();
  });

  it('prev/next da decisão do meio', () => {
    expect(prevKey(nodes, 'dec::1')).toBe('dec::0');
    expect(nextKey(nodes, 'dec::1')).toBe('dec::2');
  });

  it('a partir de uma OPÇÃO, navega para a decisão vizinha', () => {
    expect(prevKey(nodes, 'opt::1::0')).toBe('dec::0');
    expect(nextKey(nodes, 'opt::1::0')).toBe('dec::2');
  });

  it('chave inexistente → null', () => {
    expect(prevKey(nodes, 'nao-existe')).toBeNull();
    expect(nextKey(nodes, 'nao-existe')).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// Pureza / determinismo
// ---------------------------------------------------------------------------

describe('computeLayout — pureza e determinismo', () => {
  it('não modifica o array de entrada', () => {
    const items = [mkDecision('w'), mkDecision('w')];
    const original = JSON.stringify(items);
    computeLayout(items);
    expect(JSON.stringify(items)).toBe(original);
  });

  it('mesmo input → mesmo output', () => {
    const items = [mkDecision('w', { choice: 'A' }), mkDecision('w', { choice: 'C' })];
    const l1 = computeLayout(items);
    const l2 = computeLayout(items);
    expect(JSON.stringify(l1)).toBe(JSON.stringify(l2));
  });
});
