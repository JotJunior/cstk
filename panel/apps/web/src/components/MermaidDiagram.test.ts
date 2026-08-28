/**
 * Testes puros do MermaidDiagram (vitest environment 'node', sem DOM — mesmo
 * padrao de MarkdownView.test.ts). O render real do SVG (browser-only, via
 * import() dinamico de mermaid) e coberto pela verificacao empirica no dev
 * server; aqui ficam as funcoes puras e o contrato SSR do componente.
 */
import { describe, it, expect } from 'vitest';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { MermaidDiagram, mermaidThemeFor } from './MermaidDiagram.js';

describe('mermaidThemeFor — mapeamento data-theme do painel → tema mermaid', () => {
  it('tema claro do painel usa mermaid "neutral"', () => {
    expect(mermaidThemeFor('light')).toBe('neutral');
  });

  it('dark (explicito ou ausente — painel e dark-first) usa mermaid "dark"', () => {
    expect(mermaidThemeFor('dark')).toBe('dark');
    expect(mermaidThemeFor(undefined)).toBe('dark');
    expect(mermaidThemeFor('qualquer-outro-valor')).toBe('dark');
  });
});

describe('MermaidDiagram — contrato de render inicial (SSR, antes do efeito)', () => {
  it('renderiza container vazio acessivel (role=img) — nunca o codigo cru como HTML', () => {
    const html = renderToStaticMarkup(
      createElement(MermaidDiagram, { code: 'graph TD;\nA["<script>alert(1)</script>"]-->B;' }),
    );
    expect(html).toContain('mermaid-diagram');
    expect(html).toContain('role="img"');
    // o codigo-fonte UNTRUSTED nao vaza para o HTML no primeiro render
    expect(html).not.toContain('<script');
    expect(html).not.toContain('alert(1)');
  });
});
