/**
 * Testes de seguranca do MarkdownView (task 4.1.3; quickstart Cenario 8;
 * research.md Decision 6; gate owasp-security finding HIGH).
 *
 * Sem jsdom/@testing-library configurados neste repo (vitest.config.ts usa
 * `environment: 'node'` e so inclui `*.test.ts`, nao `*.test.tsx` — ver
 * padrao identico em PipelineProgress.test.ts). Duas camadas de evidencia:
 *
 *  1. `isSafeUrl` — funcao pura exportada, testada em isolamento (allowlist
 *     de esquema + classes de bypass conhecidas).
 *  2. `renderToStaticMarkup` (react-dom/server, ja e dependencia transitiva
 *     de react-dom — nenhuma dep nova) — prova EMPIRICA (ETAPA 0) de que o
 *     componente de fato neutraliza `<script>` embutido e esquemas de URL
 *     perigosos NO HTML REALMENTE PRODUZIDO, nao so na funcao isolada.
 */
import { describe, it, expect } from 'vitest';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { extractMermaidCode, isSafeUrl, MarkdownView } from './MarkdownView.js';

describe('isSafeUrl', () => {
  it('permite esquemas da allowlist (http, https, mailto)', () => {
    expect(isSafeUrl('http://example.com')).toBe(true);
    expect(isSafeUrl('https://example.com/a/b?c=1')).toBe(true);
    expect(isSafeUrl('mailto:a@b.com')).toBe(true);
  });

  it('permite URLs relativas/ancoras (sem esquema explicito)', () => {
    expect(isSafeUrl('./spec.md')).toBe(true);
    expect(isSafeUrl('/docs/specs/foo')).toBe(true);
    expect(isSafeUrl('#section')).toBe(true);
    expect(isSafeUrl('')).toBe(true);
    expect(isSafeUrl('research.md')).toBe(true);
  });

  it('rejeita esquemas perigosos (javascript:, data:, vbscript:)', () => {
    expect(isSafeUrl('javascript:alert(1)')).toBe(false);
    expect(isSafeUrl('JAVASCRIPT:alert(1)')).toBe(false);
    expect(isSafeUrl('data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==')).toBe(false);
    expect(isSafeUrl('vbscript:msgbox(1)')).toBe(false);
  });

  it('rejeita esquemas fora da allowlist ratificada mesmo sem serem classicamente perigosos', () => {
    // defaultUrlTransform da lib permite irc(s)/xmpp; Decision 6 e mais estrita
    // (so http/https/mailto/relativo) — validamos que NAO herdamos a lib default.
    expect(isSafeUrl('ftp://example.com/file')).toBe(false);
    expect(isSafeUrl('xmpp:user@example.com')).toBe(false);
  });

  it('neutraliza bypass classico via caractere de controle no meio do esquema', () => {
    // WHATWG URL Standard remove tab/LF/CR do meio da URL antes de resolver
    // o esquema — um filtro ingenuo que nao normaliza cai nesse bypass.
    expect(isSafeUrl('java\tscript:alert(1)')).toBe(false);
    expect(isSafeUrl('java\nscript:alert(1)')).toBe(false);
    expect(isSafeUrl('java\rscript:alert(1)')).toBe(false);
  });

  it('normaliza case e espacos nas bordas antes de comparar', () => {
    expect(isSafeUrl('  javascript:alert(1)  ')).toBe(false);
    expect(isSafeUrl('  https://example.com  ')).toBe(true);
  });
});

describe('MarkdownView — render seguro (renderToStaticMarkup, prova empirica ETAPA 0)', () => {
  function render(content: string): string {
    return renderToStaticMarkup(createElement(MarkdownView, { content }));
  }

  it('formata headings/listas/enfase (FR-006 — nao e texto bruto)', () => {
    const html = render('# Titulo\n\n- item um\n- item dois\n\n**negrito**');
    expect(html).toContain('<h1>');
    expect(html).toContain('<li>');
    expect(html).toContain('<strong>');
  });

  it('renderiza tabela GFM como <table> real (bugfix: sem remark-gfm os pipes viravam texto corrido)', () => {
    const html = render('| Regra | Como |\n|-------|------|\n| a | b |');
    expect(html).toContain('<table>');
    expect(html).toContain('<th>Regra</th>');
    expect(html).toContain('<td>a</td>');
    // sanitize (schema default) preserva a estrutura tabular inteira
    expect(html).toContain('<thead>');
    expect(html).toContain('<tbody>');
  });

  it('GFM nao afrouxa a seguranca: link perigoso dentro de celula segue bloqueado', () => {
    const html = render('| x |\n|---|\n| [clique](javascript:alert(1)) |');
    expect(html).toContain('<table>');
    expect(html).not.toContain('javascript:');
  });

  it('demais extensoes GFM ativas: strikethrough e task list', () => {
    const html = render('~~riscado~~\n\n- [x] feito\n- [ ] pendente');
    expect(html).toContain('<del>');
    expect(html).toContain('checkbox');
  });

  it('neutraliza <script> embutido no markdown — nunca vira tag executavel', () => {
    const html = render('conteudo\n\n<script>alert(1)</script>\n\nfim');
    expect(html).not.toContain('<script');
    expect(html).not.toContain('alert(1)');
  });

  it('neutraliza handler inline (onerror) embutido como HTML bruto', () => {
    const html = render('<img src=x onerror="alert(1)">');
    expect(html).not.toContain('onerror');
  });

  it('link [x](javascript:alert(1)) nao produz href navegavel perigoso', () => {
    const html = render('[clique aqui](javascript:alert(1))');
    expect(html).not.toContain('javascript:');
    expect(html).toContain('<a'); // o link existe, so o href foi neutralizado
  });

  it('imagem com data:text/html nao produz src perigoso', () => {
    const html = render('![img](data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==)');
    expect(html).not.toContain('data:text/html');
  });

  it('link http(s) legitimo permanece navegavel (allowlist nao super-bloqueia)', () => {
    const html = render('[docs](https://example.com/spec)');
    expect(html).toContain('href="https://example.com/spec"');
  });

  it('link relativo a outro artefato permanece navegavel', () => {
    const html = render('[ver plano](./plan.md)');
    expect(html).toContain('href="./plan.md"');
  });
});

describe('extractMermaidCode — deteccao de bloco ```mermaid no children de <pre>', () => {
  const codeEl = (className: string | undefined, children: unknown) =>
    createElement('code', { className }, children as string);

  it('extrai o codigo de <code class="language-mermaid"> (filho unico ou array unitario)', () => {
    expect(extractMermaidCode(codeEl('language-mermaid', 'graph TD;\nA-->B;\n'))).toBe(
      'graph TD;\nA-->B;\n',
    );
    expect(extractMermaidCode([codeEl('language-mermaid', 'graph TD;')])).toBe('graph TD;');
  });

  it('ignora blocos de outras linguagens e code sem className', () => {
    expect(extractMermaidCode(codeEl('language-ts', 'const a = 1;'))).toBeNull();
    expect(extractMermaidCode(codeEl(undefined, 'graph TD;'))).toBeNull();
  });

  it('nao confunde prefixo de classe: language-mermaidjs nao e mermaid', () => {
    expect(extractMermaidCode(codeEl('language-mermaidjs', 'x'))).toBeNull();
  });

  it('ignora children nao-elemento, arrays multiplos e conteudo vazio', () => {
    expect(extractMermaidCode('texto solto')).toBeNull();
    expect(extractMermaidCode(null)).toBeNull();
    expect(extractMermaidCode([codeEl('language-mermaid', 'a'), codeEl('language-mermaid', 'b')])).toBeNull();
    expect(extractMermaidCode(codeEl('language-mermaid', '   \n  '))).toBeNull();
  });

  it('conteudo nao-string (ex.: elemento aninhado pos-sanitize) nao e tratado como mermaid', () => {
    const nested = createElement('code', { className: 'language-mermaid' }, createElement('span', null, 'x'));
    expect(extractMermaidCode(nested)).toBeNull();
  });
});

describe('MarkdownView — bloco ```mermaid vira container de diagrama (prova empirica SSR)', () => {
  function render(content: string): string {
    return renderToStaticMarkup(createElement(MarkdownView, { content }));
  }

  it('```mermaid renderiza o container do MermaidDiagram no lugar de <pre>', () => {
    const html = render('```mermaid\ngraph TD;\nA-->B;\n```');
    // Em SSR o useEffect nao roda (o SVG e desenhado so no browser) — o que
    // se prova aqui e a ROTA de render: container do diagrama, nao <pre>.
    expect(html).toContain('mermaid-diagram');
    expect(html).not.toContain('<pre>');
  });

  it('bloco de codigo comum continua renderizando <pre><code> intacto', () => {
    const html = render('```ts\nconst a = 1;\n```');
    expect(html).toContain('<pre>');
    expect(html).toContain('const a = 1;');
    expect(html).not.toContain('mermaid-diagram');
  });

  it('mermaid convive com o resto do documento (heading + tabela GFM seguem ok)', () => {
    const html = render('# T\n\n```mermaid\ngraph TD;\nA-->B;\n```\n\n| a |\n|---|\n| b |');
    expect(html).toContain('<h1>');
    expect(html).toContain('<table>');
    expect(html).toContain('mermaid-diagram');
  });
});

// ---------------------------------------------------------------------------
// Auditoria de fonte (task 5.3.3, quickstart Cenario 8) — confirma por
// grep-based scan (mesmo padrao de DecisionMapPanel.test.ts) a ausencia de
// dangerouslySetInnerHTML nos arquivos que compoem o doc-viewer, alem do
// gate de lint (eslint.config.mjs regra no-restricted-syntax) e da prova
// empirica de render acima. Defesa em profundidade: 3 camadas independentes.
// ---------------------------------------------------------------------------

describe('Auditoria de fonte — ausencia de dangerouslySetInnerHTML (task 5.3.3)', () => {
  const WEB_SRC = resolve(process.cwd(), 'apps/web/src');
  function readSrc(rel: string): string {
    return readFileSync(resolve(WEB_SRC, rel), 'utf-8');
  }

  // Uso REAL (JSX attribute `dangerouslySetInnerHTML={...}` ou object key
  // `dangerouslySetInnerHTML:`), nao menção em comentario/prosa — o proprio
  // MarkdownView.tsx documenta em comentario que NUNCA usa a prop, o que
  // quebraria um `.not.toContain('dangerouslySetInnerHTML')` ingenuo.
  const USAGE_RE = /dangerouslySetInnerHTML\s*[:=]/;

  it('MarkdownView.tsx nao usa dangerouslySetInnerHTML como prop/atributo', () => {
    expect(readSrc('components/MarkdownView.tsx')).not.toMatch(USAGE_RE);
  });

  it('MermaidDiagram.tsx nao usa dangerouslySetInnerHTML nem atribuicao a innerHTML', () => {
    const src = readSrc('components/MermaidDiagram.tsx');
    expect(src).not.toMatch(USAGE_RE);
    // Insercao de DOM permitida SO via replaceChildren(fragment sanitizado)
    expect(src).not.toMatch(/\.innerHTML\s*=/);
    expect(src).toContain('replaceChildren');
  });

  it('FeatureDetail.tsx (consumidor do doc-viewer, DocumentationPanel) nao usa dangerouslySetInnerHTML', () => {
    expect(readSrc('screens/FeatureDetail.tsx')).not.toMatch(USAGE_RE);
  });

  it('hooks.ts (camada de dados useFeatureDocs/useFeatureDocContent) nao usa dangerouslySetInnerHTML', () => {
    expect(readSrc('lib/hooks.ts')).not.toMatch(USAGE_RE);
  });
});
