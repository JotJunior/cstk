/**
 * DecisionMapSvg — SVG da árvore de decisões.
 *
 * Renderiza nós via <foreignObject> + DecisionMapNode, com geometria por nó
 * (pills de decisão, retângulos de opção, terminal "Fim"). Arestas:
 *   - branch (decisão → opção): curva de Bézier suave.
 *   - spine  (opção escolhida → próxima decisão / Fim): linha reta com seta.
 *
 * NUNCA usa innerHTML/dangerouslySetInnerHTML (data-model §Invariantes).
 * Campos textuais UNTRUSTED — delegados ao DecisionMapNode/TextRaw.
 *
 * Ref: spec §FR-002, FR-005, FR-010; data-model §Invariantes
 */

import React, { useCallback, useRef } from 'react';
import type { MapNode, MapEdge } from '@/lib/decision-map-layout.js';
import { DecisionMapNode } from './DecisionMapNode.js';

// ---------------------------------------------------------------------------
// Props
// ---------------------------------------------------------------------------

interface DecisionMapSvgProps {
  nodes: MapNode[];
  edges: MapEdge[];
  svgWidth: number;
  svgHeight: number;
  selectedKey: string | null;
  onNodeSelect: (key: string) => void;
  /** Ref para devolver foco ao nó ao fechar painel. */
  nodeRefs?: React.MutableRefObject<Map<string, SVGGElement>>;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** aria-label de cada nó conforme o tipo (escolha real ou fallback). */
function nodeAriaLabel(node: MapNode): string {
  if (node.kind === 'end') return 'Fim da cadeia de decisões';
  if (node.kind === 'option') {
    return node.chosen
      ? `Opção escolhida: ${node.label ?? 'sem texto'}`
      : `Opção considerada: ${node.label ?? 'sem texto'}`;
  }
  // decisão — usa a escolha real ou um fallback explícito quando null
  return node.decision?.choice ?? 'decisão sem escolha';
}

// ---------------------------------------------------------------------------
// Componente
// ---------------------------------------------------------------------------

export function DecisionMapSvg({
  nodes,
  edges,
  svgWidth,
  svgHeight,
  selectedKey,
  onNodeSelect,
  nodeRefs,
}: DecisionMapSvgProps) {
  const internalRefs = useRef<Map<string, SVGGElement>>(new Map());
  const refs = nodeRefs ?? internalRefs;

  // Apenas nós interativos (decisão/opção) participam do Tab/Arrow order.
  const focusable = nodes.filter((n) => n.kind !== 'end');

  const setNodeRef = useCallback(
    (key: string) => (el: SVGGElement | null) => {
      if (el) {
        refs.current.set(key, el);
      } else {
        refs.current.delete(key);
      }
    },
    [refs]
  );

  // Manipulador de teclado por nó (Enter/Espaço seleciona; Arrow navega).
  const handleKeyDown = useCallback(
    (key: string, focusIndex: number) => (e: React.KeyboardEvent<SVGGElement>) => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        onNodeSelect(key);
      }
      if (e.key === 'ArrowDown' || e.key === 'ArrowRight') {
        e.preventDefault();
        const nextNode = focusable[focusIndex + 1];
        if (nextNode) {
          const el = refs.current.get(nextNode.key);
          el?.focus();
        }
      }
      if (e.key === 'ArrowUp' || e.key === 'ArrowLeft') {
        e.preventDefault();
        const prevNode = focusable[focusIndex - 1];
        if (prevNode) {
          const el = refs.current.get(prevNode.key);
          el?.focus();
        }
      }
    },
    [focusable, onNodeSelect, refs]
  );

  // Índice de cada chave dentro da lista focável (para Arrow nav).
  const focusIndexByKey = new Map<string, number>();
  focusable.forEach((n, i) => focusIndexByKey.set(n.key, i));

  // Lookup rápido de nós por chave (para arestas).
  const byKey = new Map<string, MapNode>();
  for (const n of nodes) byKey.set(n.key, n);

  return (
    <div
      style={{
        // Ocupa a largura do container de conteúdo; a altura cresce com a
        // árvore e quem rola verticalmente é a própria página (sem box fixo).
        // Só há scroll horizontal interno quando a árvore é mais larga que o
        // container.
        width: '100%',
        overflowX: 'auto',
        overflowY: 'visible',
        borderRadius: 8,
        border: '1px solid var(--border-1, #1e293b)',
        background: 'var(--bg-0, #020617)',
      }}
    >
      <svg
        width={svgWidth}
        height={svgHeight}
        role="img"
        aria-label="Árvore de decisões"
        style={{ display: 'block' }}
        xmlns="http://www.w3.org/2000/svg"
      >
        <defs>
          <marker
            id="decision-map-arrow"
            viewBox="0 0 10 10"
            refX={9}
            refY={5}
            markerWidth={7}
            markerHeight={7}
            orient="auto-start-reverse"
          >
            <path d="M 0 0 L 10 5 L 0 10 z" fill="var(--border-3, #475569)" />
          </marker>
        </defs>

        {/* Arestas ANTES dos nós (z-order). */}
        {edges.map((edge) => {
          const from = byKey.get(edge.from);
          const to = byKey.get(edge.to);
          if (!from || !to) return null;

          const x1 = from.x + from.w / 2;
          const y1 = from.y + from.h;
          const x2 = to.x + to.w / 2;
          const y2 = to.y;

          let d: string;
          if (edge.kind === 'branch') {
            // Curva suave da decisão até cada opção (galho).
            const my = (y1 + y2) / 2;
            d = `M ${x1} ${y1} C ${x1} ${my}, ${x2} ${my}, ${x2} ${y2}`;
          } else {
            // Espinha: opção escolhida desce reta para a próxima decisão.
            // x1≈x2 (próxima decisão nasce sob a opção escolhida); curva leve
            // de segurança caso haja pequeno desalinhamento.
            const my = (y1 + y2) / 2;
            d = `M ${x1} ${y1} C ${x1} ${my}, ${x2} ${my}, ${x2} ${y2}`;
          }

          const isSpine = edge.kind === 'spine';
          return (
            <path
              key={`edge-${edge.from}-${edge.to}`}
              d={d}
              stroke={isSpine ? 'var(--border-3, #475569)' : 'var(--border-2, #374151)'}
              strokeWidth={isSpine ? 2 : 1.5}
              fill="none"
              markerEnd="url(#decision-map-arrow)"
            />
          );
        })}

        {/* Nós via <g> + <foreignObject> + DecisionMapNode. */}
        {nodes.map((node) => {
          const isEnd = node.kind === 'end';
          const focusIndex = focusIndexByKey.get(node.key) ?? -1;
          const interactive = !isEnd;

          return (
            <g
              key={node.key}
              ref={setNodeRef(node.key)}
              transform={`translate(${node.x}, ${node.y})`}
              tabIndex={interactive ? 0 : undefined}
              role={interactive ? 'button' : 'img'}
              aria-label={nodeAriaLabel(node)}
              aria-pressed={interactive ? node.key === selectedKey : undefined}
              onClick={interactive ? () => onNodeSelect(node.key) : undefined}
              onKeyDown={interactive ? handleKeyDown(node.key, focusIndex) : undefined}
              style={{ outline: 'none', cursor: interactive ? 'pointer' : 'default' }}
            >
              {/* Ring de foco visível via CSS (:focus-visible no <g> global). */}
              <rect
                x={0}
                y={0}
                width={node.w}
                height={node.h}
                rx={node.kind === 'option' ? 4 : 999}
                ry={node.kind === 'option' ? 4 : 999}
                fill="transparent"
                stroke="transparent"
                className="decision-map-focus-ring"
              />
              <foreignObject width={node.w} height={node.h} x={0} y={0}>
                <div style={{ height: '100%' }}>
                  <DecisionMapNode node={node} selected={node.key === selectedKey} />
                </div>
              </foreignObject>
            </g>
          );
        })}
      </svg>
    </div>
  );
}
