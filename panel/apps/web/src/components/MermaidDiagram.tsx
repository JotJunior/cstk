/**
 * MermaidDiagram — renderizacao segura de diagramas Mermaid vindos de blocos
 * ```mermaid em artefatos de documentacao SDD (conteudo de agente, UNTRUSTED —
 * Principio V, mesma postura de MarkdownView.tsx / TextRaw.tsx).
 *
 * Defesa em profundidade (3 camadas independentes):
 *
 *  1. `securityLevel: 'strict'` (default da lib, reafirmado explicitamente):
 *     a propria mermaid sanitiza texto de labels e desabilita interacoes de
 *     click/link declaradas no diagrama.
 *  2. `htmlLabels: false` (config de raiz; as versoes por-diagrama estao
 *     deprecated — node_modules/mermaid/dist/config.type.d.ts): labels viram
 *     <text>/<tspan> SVG puro, o SVG final nao carrega <foreignObject> com
 *     HTML embutido. Isso permite a camada 3 operar com allowlist SVG-only.
 *  3. DOMPurify sobre o SVG gerado, profile svg+svgFilters (sem profile html:
 *     qualquer HTML que escapasse das camadas 1-2 e REMOVIDO — pior caso e
 *     label ausente, nunca HTML ativo). `RETURN_DOM_FRAGMENT: true` devolve
 *     um DocumentFragment ja sanitizado, inserido via `replaceChildren` —
 *     JAMAIS innerHTML/dangerouslySetInnerHTML (regras eslint
 *     no-restricted-properties / no-restricted-syntax, Principio V).
 *
 * A lib mermaid (~2 MB) entra por import() dinamico: vira chunk proprio do
 * Vite e so e baixada quando um documento de fato contem um diagrama.
 *
 * Erro de parse (diagrama invalido) NAO derruba o doc-viewer: fallback exibe
 * o codigo-fonte original em <pre><code> + aviso (mesma degradacao graciosa
 * dos demais estados do painel).
 */
import { useEffect, useRef, useState } from 'react';

/**
 * Mapeia o tema do painel (`data-theme` no <html>, ver Sidebar.tsx) para um
 * tema mermaid: dark-first como o resto do app; 'neutral' (grayscale) no tema
 * claro — combina com a paleta cinza/ambar dos tokens.
 * Exportada para teste unitario direto (vitest environment 'node', sem DOM).
 */
export function mermaidThemeFor(datasetTheme: string | undefined): 'dark' | 'neutral' {
  return datasetTheme === 'light' ? 'neutral' : 'dark';
}

/** Tema corrente do documento, reativo a mudancas de `data-theme` no <html>. */
function useDocumentTheme(): string | undefined {
  // Guard `typeof document`: os testes exercitam o componente via
  // renderToStaticMarkup em vitest environment 'node' (sem DOM) — o
  // initializer roda no primeiro render, ANTES de qualquer useEffect.
  const [theme, setTheme] = useState<string | undefined>(() =>
    typeof document === 'undefined' ? undefined : document.documentElement.dataset['theme'],
  );
  useEffect(() => {
    const observer = new MutationObserver(() => {
      setTheme(document.documentElement.dataset['theme']);
    });
    observer.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ['data-theme'],
    });
    return () => observer.disconnect();
  }, []);
  return theme;
}

/**
 * Sequencial de ids de render — `mermaid.render` exige id unico por chamada
 * (usa-o em elemento temporario no DOM e nos seletores do <style> interno).
 */
let renderSeq = 0;

export interface MermaidDiagramProps {
  /** Codigo-fonte mermaid BRUTO do bloco ```mermaid — UNTRUSTED (Principio V). */
  code: string;
}

export function MermaidDiagram({ code }: MermaidDiagramProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [error, setError] = useState<string | null>(null);
  const docTheme = useDocumentTheme();

  useEffect(() => {
    let cancelled = false;
    const id = `mermaid-diagram-${++renderSeq}`;

    (async () => {
      // import() dinamico dos dois modulos em paralelo (chunk lazy do Vite).
      const [{ default: mermaid }, { default: DOMPurify }] = await Promise.all([
        import('mermaid'),
        import('dompurify'),
      ]);
      if (cancelled) return;

      // initialize e config GLOBAL da lib; re-executar a cada render mantem o
      // tema sincronizado com o toggle do painel (custo: atribuicao de config).
      mermaid.initialize({
        startOnLoad: false,
        securityLevel: 'strict',
        htmlLabels: false,
        theme: mermaidThemeFor(docTheme),
        fontFamily: 'Inter, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
      });

      try {
        const { svg } = await mermaid.render(id, code);
        if (cancelled) return;
        const fragment = DOMPurify.sanitize(svg, {
          USE_PROFILES: { svg: true, svgFilters: true },
          RETURN_DOM_FRAGMENT: true,
        });
        // replaceChildren move os nodes SANITIZADOS para o container — unico
        // ponto de insercao de DOM do componente (nunca innerHTML).
        containerRef.current?.replaceChildren(fragment);
        setError(null);
      } catch (err) {
        // mermaid.render pode deixar node temporario orfao no <body> quando o
        // parse falha (comportamento observado em versoes 10/11) — limpeza
        // defensiva e idempotente.
        document.getElementById(id)?.remove();
        document.getElementById(`d${id}`)?.remove();
        if (cancelled) return;
        containerRef.current?.replaceChildren();
        setError(err instanceof Error ? err.message : String(err));
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [code, docTheme]);

  if (error != null) {
    return (
      <div className="mermaid-diagram mermaid-diagram--error">
        <div className="mermaid-error-note" role="note">
          Diagrama Mermaid inválido — exibindo código-fonte.
        </div>
        {/* Codigo e mensagem de erro (que ecoa trechos do diagrama) rendem
            como TEXT NODE JSX — inerte por construcao. */}
        <pre>
          <code>{code}</code>
        </pre>
        <div className="mermaid-error-detail">{error}</div>
      </div>
    );
  }

  return <div ref={containerRef} className="mermaid-diagram" role="img" aria-label="Diagrama Mermaid" />;
}
