/**
 * DecisionMapNode — nó individual do Decision Map Panel (árvore).
 *
 * Renderiza três formas conforme `node.kind`:
 *   - `decision` → pill arredondado (ponto de decisão; rótulo = etapa)
 *   - `option`   → retângulo (opção considerada; a escolhida ganha destaque + ✓)
 *   - `end`      → pill terminal "Fim"
 *
 * Renderizado dentro de um <foreignObject> no SVG.
 * NUNCA usa innerHTML/dangerouslySetInnerHTML (spec §FR-007).
 * Todo texto de conteúdo (opção/escolha/etapa) é UNTRUSTED → via <TextRaw>.
 *
 * Ref: spec §FR-003, FR-004, FR-007; data-model §Entity MapNode
 */

import React from 'react';
import type { MapNode } from '@/lib/decision-map-layout.js';
import { TextRaw } from './TextRaw.js';
import { ScoreChip } from './ScoreChip.js';

interface DecisionMapNodeProps {
  node: MapNode;
  /** Nó está selecionado (clique ou teclado). */
  selected?: boolean;
}

export function DecisionMapNode({ node, selected = false }: DecisionMapNodeProps) {
  if (node.kind === 'end') {
    return (
      <div
        className="decision-map-end"
        style={{
          width: '100%',
          height: '100%',
          boxSizing: 'border-box',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          borderRadius: 999,
          border: '1px solid var(--border-2, #374151)',
          background: 'var(--bg-1, #0f172a)',
          color: 'var(--text-2, #94a3b8)',
          fontSize: 13,
          fontWeight: 600,
        }}
      >
        Fim
      </div>
    );
  }

  if (node.kind === 'option') {
    const chosen = node.chosen;
    return (
      <div
        className={`decision-map-option${chosen ? ' chosen' : ''}${selected ? ' selected' : ''}`}
        style={{
          width: '100%',
          height: '100%',
          boxSizing: 'border-box',
          padding: '6px 10px',
          borderRadius: 4,
          // Opção escolhida: borda de acento (a "Decisão" do galho); demais: neutra.
          border: selected
            ? '2px solid var(--accent, #3b82f6)'
            : chosen
              ? '1.5px solid var(--accent, #3b82f6)'
              : '1px solid var(--border-2, #374151)',
          background: chosen ? 'var(--bg-2, #1e293b)' : 'var(--bg-1, #0f172a)',
          boxShadow: selected ? '0 0 0 3px rgba(59,130,246,0.25)' : 'none',
          display: 'flex',
          alignItems: 'center',
          gap: 6,
          overflow: 'hidden',
          cursor: 'pointer',
          transition: 'border-color 0.1s, box-shadow 0.1s',
        }}
      >
        {chosen && (
          <span
            aria-hidden
            style={{ color: 'var(--accent, #3b82f6)', fontSize: 12, flexShrink: 0, fontWeight: 700 }}
          >
            ✓
          </span>
        )}
        <span
          style={{
            fontSize: 12,
            lineHeight: 1.3,
            fontWeight: chosen ? 600 : 400,
            color: chosen ? 'var(--text-1, #f1f5f9)' : 'var(--text-2, #94a3b8)',
            overflow: 'hidden',
            textOverflow: 'ellipsis',
            display: '-webkit-box',
            WebkitLineClamp: 2,
            WebkitBoxOrient: 'vertical',
          }}
        >
          <TextRaw value={node.label} maxLength={48} />
        </span>
      </div>
    );
  }

  // kind === 'decision' → pill (ponto de decisão)
  const decision = node.decision;
  return (
    <div
      className={`decision-map-node${selected ? ' selected' : ''}`}
      style={{
        width: '100%',
        height: '100%',
        boxSizing: 'border-box',
        padding: '6px 14px',
        borderRadius: 999,
        border: selected
          ? '2px solid var(--accent, #3b82f6)'
          : '1.5px solid var(--border-3, #475569)',
        background: selected ? 'var(--bg-2, #1e293b)' : 'var(--bg-1, #0f172a)',
        boxShadow: selected ? '0 0 0 3px rgba(59,130,246,0.25)' : 'none',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        gap: 2,
        overflow: 'hidden',
        cursor: 'pointer',
        transition: 'border-color 0.1s, box-shadow 0.1s',
      }}
    >
      {/* Rótulo do ponto de decisão (etapa) — UNTRUSTED via TextRaw */}
      <span
        style={{
          fontSize: 12.5,
          fontWeight: 600,
          lineHeight: 1.2,
          color: 'var(--text-1, #f1f5f9)',
          overflow: 'hidden',
          textOverflow: 'ellipsis',
          whiteSpace: 'nowrap',
          maxWidth: '100%',
        }}
      >
        <TextRaw value={node.label} maxLength={28} />
      </span>

      {/* Linha inferior: onda (mono) + score */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, maxWidth: '100%' }}>
        <span
          style={{
            fontFamily: 'var(--font-mono, monospace)',
            fontSize: 9.5,
            color: 'var(--text-3, #64748b)',
            overflow: 'hidden',
            textOverflow: 'ellipsis',
            whiteSpace: 'nowrap',
          }}
        >
          {decision?.wave}
        </span>
        {decision && <ScoreChip score={decision.score} />}
      </div>
    </div>
  );
}
