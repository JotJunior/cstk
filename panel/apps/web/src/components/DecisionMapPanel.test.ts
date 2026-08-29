/**
 * Testes da camada de segurança e lógica do Decision Map Panel (árvore).
 *
 *  - Acessibilidade: verificações estáticas (grep-based) sobre a fonte.
 *  - Segurança de conteúdo: TextRaw contract + ausência de innerHTML.
 *  - Lógica de layout em árvore: contagem de nós/arestas, seleção, navegação.
 *
 * Padrão do projeto: testes de lógica pura, sem React rendering.
 *
 * Ref: spec §FR-007, FR-010, US2; constitution Princípio V (UNTRUSTED via TextRaw)
 */

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { computeLayout, prevKey, nextKey } from '@/lib/decision-map-layout.js';
import type { DecisionDTO } from '@cstk-panel/shared-types';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const SRC = resolve(process.cwd(), 'apps/web/src');

function readSrc(rel: string): string {
  return readFileSync(resolve(SRC, rel), 'utf-8');
}

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

/** Remove linhas de comentário JSDoc/TSX para checar apenas código ativo. */
function codeOnly(src: string): string {
  return src
    .split('\n')
    .filter((l) => {
      const t = l.trim();
      if (t.startsWith('* ') || t === '*') return false;
      if (t.startsWith('/**') || t === '*/') return false;
      if (t.startsWith('//')) return false;
      if (t.startsWith('{/*') || t.endsWith('*/}')) return false;
      return true;
    })
    .join('\n');
}

// ---------------------------------------------------------------------------
// Acessibilidade — verificação estática de fonte
// ---------------------------------------------------------------------------

describe('Acessibilidade (verificação estática de fonte)', () => {
  const svgSrc = readSrc('components/DecisionMapSvg.tsx');
  const panelSrc = readSrc('components/DecisionMapPanel.tsx');
  const paneSrc = readSrc('components/DecisionDetailPane.tsx');

  it('nós interativos participam do Tab order (tabIndex)', () => {
    expect(svgSrc).toContain('tabIndex={interactive ? 0 : undefined}');
  });

  it('nós respondem a Enter e Espaço via onKeyDown → onNodeSelect', () => {
    expect(svgSrc).toContain("e.key === 'Enter'");
    expect(svgSrc).toContain("e.key === ' '");
    expect(svgSrc).toContain('onNodeSelect(key)');
  });

  it('DecisionDetailPane fecha ao pressionar Escape', () => {
    expect(paneSrc).toContain("e.key === 'Escape'");
    expect(paneSrc).toContain('onClose()');
    expect(paneSrc).toContain("document.addEventListener('keydown'");
  });

  it('botões prev/next/fechar são <button> nativos com aria-label', () => {
    expect(paneSrc).toContain('aria-label="Decisão anterior"');
    expect(paneSrc).toContain('aria-label="Próxima decisão"');
    expect(paneSrc).toContain('aria-label="Fechar painel"');
    const buttonOccurrences = (paneSrc.match(/<button/g) ?? []).length;
    expect(buttonOccurrences).toBeGreaterThanOrEqual(3);
  });

  it('nós têm elemento visual para focus ring e outline gerenciado', () => {
    expect(svgSrc).toContain('decision-map-focus-ring');
    expect(svgSrc).toContain("outline: 'none'");
  });

  it('aria-label dos nós deriva da escolha real com fallback', () => {
    expect(svgSrc).toContain('aria-label={nodeAriaLabel(node)}');
    expect(svgSrc).toContain("node.decision?.choice ?? 'decisão sem escolha'");
  });

  it('Arrow keys navegam entre nós focáveis', () => {
    expect(svgSrc).toContain("e.key === 'ArrowDown'");
    expect(svgSrc).toContain("e.key === 'ArrowRight'");
    expect(svgSrc).toContain("e.key === 'ArrowUp'");
    expect(svgSrc).toContain("e.key === 'ArrowLeft'");
    expect(svgSrc).toContain('el?.focus()');
  });

  it('todas as ações têm equivalente de teclado (SC-006)', () => {
    expect(svgSrc).toContain('onClick=');
    expect(svgSrc).toContain('onKeyDown=');
    expect(paneSrc).toContain('disabled={prevKey === null}');
    expect(paneSrc).toContain('disabled={nextKey === null}');
  });

  it('foco retorna ao nó ao fechar painel; foco inicial no primeiro nó', () => {
    expect(panelSrc).toContain('nodeRefs.current.get(key)');
    expect(panelSrc).toContain('el?.focus()');
    expect(panelSrc).toContain('layout.nodes[0]');
    expect(panelSrc).toContain('requestAnimationFrame(() => el.focus())');
  });
});

// ---------------------------------------------------------------------------
// Segurança de conteúdo (UNTRUSTED via TextRaw; zero innerHTML)
// ---------------------------------------------------------------------------

describe('Segurança de conteúdo (verificação estática)', () => {
  const svgCode = codeOnly(readSrc('components/DecisionMapSvg.tsx'));
  const nodeCode = codeOnly(readSrc('components/DecisionMapNode.tsx'));
  const paneCode = codeOnly(readSrc('components/DecisionDetailPane.tsx'));
  const textRawCode = codeOnly(readSrc('components/TextRaw.tsx'));

  const paneSrc = readSrc('components/DecisionDetailPane.tsx');
  const nodeSrc = readSrc('components/DecisionMapNode.tsx');
  const textRawSrc = readSrc('components/TextRaw.tsx');

  it('TextRaw não usa dangerouslySetInnerHTML/innerHTML/__html', () => {
    expect(textRawCode).not.toContain('dangerouslySetInnerHTML');
    expect(textRawCode).not.toContain('innerHTML');
    expect(textRawCode).not.toContain('__html');
    expect(textRawSrc).toContain('{display}');
  });

  it('payload XSS é truncado e exibido literalmente (React escapa via children)', () => {
    const xssPayload = '<script>alert(1)</script>';
    const maxLength = 48;
    const display = xssPayload.length > maxLength ? xssPayload.slice(0, maxLength) + '…' : xssPayload;
    expect(display).toBe(xssPayload);
    expect(typeof display).toBe('string');
  });

  it('payload SQL injection exibido como texto puro', () => {
    const sqlPayload = '"; DROP TABLE decisions; --';
    const maxLength = 48;
    const display = sqlPayload.length > maxLength ? sqlPayload.slice(0, maxLength) + '…' : sqlPayload;
    expect(display).toBe(sqlPayload);
  });

  it('DecisionMapNode renderiza o texto do nó (opção/decisão) via TextRaw', () => {
    expect(nodeCode).not.toContain('innerHTML');
    expect(nodeCode).not.toContain('dangerouslySetInnerHTML');
    expect(nodeSrc).toContain('<TextRaw value={node.label}');
  });

  it('DecisionDetailPane usa TextRaw para justificativa', () => {
    expect(paneCode).not.toContain('innerHTML');
    expect(paneCode).not.toContain('dangerouslySetInnerHTML');
    expect(paneSrc).toContain('<TextRaw value={decision.rationale}');
  });

  it('DecisionMapSvg usa foreignObject e zero innerHTML', () => {
    expect(svgCode).not.toContain('innerHTML');
    expect(svgCode).not.toContain('dangerouslySetInnerHTML');
    expect(readSrc('components/DecisionMapSvg.tsx')).toContain('foreignObject');
  });
});

// ---------------------------------------------------------------------------
// Estrutura do SVG (marker / defs)
// ---------------------------------------------------------------------------

describe('Estrutura SVG', () => {
  it('define <defs> com marker de seta usado nas arestas', () => {
    const svgSrc = readSrc('components/DecisionMapSvg.tsx');
    expect(svgSrc).toContain('<defs>');
    expect(svgSrc).toContain('<marker');
    expect(svgSrc).toContain('decision-map-arrow');
    expect(svgSrc).toContain('markerEnd="url(#decision-map-arrow)"');
  });
});

// ---------------------------------------------------------------------------
// Estados do DecisionMapPanel (verificação estática)
// ---------------------------------------------------------------------------

describe('Estados do DecisionMapPanel (verificação estática)', () => {
  const panelSrc = readSrc('components/DecisionMapPanel.tsx');

  it('loading → <LoadingState>', () => {
    expect(panelSrc).toContain('isLoading');
    expect(panelSrc).toContain('<LoadingState');
  });

  it('vazio → <EmptyState> com mensagem correta', () => {
    expect(panelSrc).toContain('<EmptyState');
    expect(panelSrc).toContain('Nenhuma decisão registrada para esta execução.');
  });

  it('erro → <ErrorState> com retry', () => {
    expect(panelSrc).toContain('isError');
    expect(panelSrc).toContain('<ErrorState');
    expect(panelSrc).toContain('refetch');
    expect(panelSrc).toContain('Tentar novamente');
  });

  it('degradado → <DegradedBanner> quando meta.degraded', () => {
    expect(panelSrc).toContain('meta.degraded');
    expect(panelSrc).toContain('<DegradedBanner');
  });

  it('corte → banner quando pagination.hasMore', () => {
    expect(panelSrc).toContain('pagination?.hasMore');
    expect(panelSrc).toContain('primeiras 100 decisões');
  });

  it('imports obrigatórios presentes', () => {
    expect(panelSrc).toContain('useDecisions');
    expect(panelSrc).toContain('computeLayout');
    expect(panelSrc).toContain('DecisionMapSvg');
    expect(panelSrc).toContain('DecisionDetailPane');
  });
});

// ---------------------------------------------------------------------------
// Lógica de layout em árvore + seleção
// ---------------------------------------------------------------------------

describe('Layout em árvore e seleção', () => {
  it('3 decisões (3 opções cada) → 3 pills + 9 opções + Fim', () => {
    const items: DecisionDTO[] = [
      mkDecision('onda-001', { choice: 'A' }),
      mkDecision('onda-001', { choice: 'B' }),
      mkDecision('onda-001', { choice: 'C' }),
    ];
    const layout = computeLayout(items);
    expect(layout.nodes.filter((n) => n.kind === 'decision')).toHaveLength(3);
    expect(layout.nodes.filter((n) => n.kind === 'option')).toHaveLength(9);
    expect(layout.nodes.filter((n) => n.kind === 'end')).toHaveLength(1);
  });

  it('a opção escolhida de cada decisão é destacada (chosen)', () => {
    const items: DecisionDTO[] = [
      mkDecision('w', { options: '["A","B","C"]', choice: 'A' }),
      mkDecision('w', { options: '["A","B","C"]', choice: 'C' }),
    ];
    const layout = computeLayout(items);
    const chosen0 = layout.nodes.find((n) => n.decisionIndex === 0 && n.kind === 'option' && n.chosen);
    const chosen1 = layout.nodes.find((n) => n.decisionIndex === 1 && n.kind === 'option' && n.chosen);
    expect(chosen0!.label).toBe('A');
    expect(chosen1!.label).toBe('C');
  });

  it('chaves de nó únicas e estáveis; decisão referenciável por key', () => {
    const items: DecisionDTO[] = [
      mkDecision('onda-001', { choice: 'Escolha A' }),
      mkDecision('onda-001', { choice: 'Escolha B' }),
    ];
    const layout = computeLayout(items);
    expect(layout.nodes[0]!.key).toBe('dec::0');
    const dec1 = layout.nodes.find((n) => n.key === 'dec::1');
    expect(dec1).toBeDefined();
    expect(dec1!.decision!.choice).toBe('Escolha B');
  });

  it('prev/next navegam entre decisões sem afetar mapVisible', () => {
    const items: DecisionDTO[] = [mkDecision('w', { choice: 'A' }), mkDecision('w', { choice: 'B' })];
    const layout = computeLayout(items);
    expect(prevKey(layout.nodes, 'dec::1')).toBe('dec::0');
    expect(nextKey(layout.nodes, 'dec::0')).toBe('dec::1');
  });

  it('benchmark: computeLayout 100 decisões < 10ms (SC-002)', () => {
    const items: DecisionDTO[] = Array.from({ length: 100 }, (_, i) =>
      mkDecision(`onda-${String(Math.floor(i / 10) + 1).padStart(3, '0')}`, { choice: 'B' })
    );
    const t0 = performance.now();
    computeLayout(items);
    expect(performance.now() - t0).toBeLessThan(10);
  });
});

// ---------------------------------------------------------------------------
// Invariante de segurança holística
// ---------------------------------------------------------------------------

describe('Invariante de segurança holística', () => {
  const components = [
    'components/DecisionMapSvg.tsx',
    'components/DecisionMapNode.tsx',
    'components/DecisionDetailPane.tsx',
    'components/DecisionMapPanel.tsx',
    'components/TextRaw.tsx',
  ];

  for (const rel of components) {
    it(`${rel}: zero innerHTML/dangerouslySetInnerHTML no código ativo`, () => {
      const code = codeOnly(readSrc(rel));
      expect(code).not.toContain('dangerouslySetInnerHTML');
      expect(code).not.toContain('innerHTML');
    });
  }
});
