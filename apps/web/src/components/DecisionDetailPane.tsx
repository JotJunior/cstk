/**
 * DecisionDetailPane — painel lateral de detalhe de uma decisão.
 *
 * Exibe todos os campos disponíveis de um DecisionDTO selecionado.
 * Conteúdo UNTRUSTED renderizado exclusivamente via TextRaw.
 * NUNCA usa innerHTML ou dangerouslySetInnerHTML (spec §FR-007).
 *
 * Ref: tasks 2.3.1–2.3.12; spec §FR-006, FR-007, US2, US4 SC3;
 *      plan §DecisionDetailPane; data-model §DecisionDTO
 */

import React, { useEffect, useRef } from 'react';
import type { DecisionDTO } from '@cstk-panel/shared-types';
import { TextRaw } from './TextRaw.js';
import { ScoreChip } from './ScoreChip.js';
import { Icon } from './Icon.js';
import { decisionOptions, chosenOptionIndex } from '@/lib/decision-options.js';

// ---------------------------------------------------------------------------
// Props
// ---------------------------------------------------------------------------

interface DecisionDetailPaneProps {
  /** Decisão selecionada para exibir. */
  decision: DecisionDTO;
  /** Chave da decisão anterior no array flat (null = primeira). */
  prevKey: string | null;
  /** Chave da próxima decisão no array flat (null = última). */
  nextKey: string | null;
  /** Navegar para decisão anterior. */
  onPrev: () => void;
  /** Navegar para próxima decisão. */
  onNext: () => void;
  /** Fechar o painel lateral. */
  onClose: () => void;
}

// ---------------------------------------------------------------------------
// Sub-componente: rótulo de seção
// ---------------------------------------------------------------------------

function SectionLabel({ children }: { children: React.ReactNode }) {
  return (
    <div
      style={{
        fontSize: 10.5,
        color: 'var(--text-3, #64748b)',
        textTransform: 'uppercase',
        letterSpacing: '0.08em',
        marginBottom: 4,
        fontFamily: 'var(--font-mono, monospace)',
      }}
    >
      {children}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Componente principal
// ---------------------------------------------------------------------------

export function DecisionDetailPane({
  decision,
  prevKey,
  nextKey,
  onPrev,
  onNext,
  onClose,
}: DecisionDetailPaneProps) {
  const closeButtonRef = useRef<HTMLButtonElement>(null);

  // 2.3.11: fechar por Escape
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        onClose();
      }
    };
    document.addEventListener('keydown', handler);
    return () => document.removeEventListener('keydown', handler);
  }, [onClose]);

  // Focar o botão de fechar ao montar (acessibilidade — painel como região)
  useEffect(() => {
    closeButtonRef.current?.focus();
  }, []);

  // Opções de decisão (chips)
  const opts = decisionOptions(decision.options);
  const chosenIdx = chosenOptionIndex(opts, decision.choice);

  return (
    <div
      role="region"
      aria-label="Detalhe da decisão"
      style={{
        display: 'flex',
        flexDirection: 'column',
        height: '100%',
        background: 'var(--bg-1, #0f172a)',
        borderLeft: '1px solid var(--border-1, #1e293b)',
        overflow: 'hidden',
      }}
    >
      {/* Header: título + botões de navegação e fechar */}
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: 8,
          padding: '10px 14px',
          borderBottom: '1px solid var(--border-1, #1e293b)',
          flexShrink: 0,
        }}
      >
        {/* Título: escolha (UNTRUSTED) — 2.3.2 */}
        <span
          style={{
            flex: 1,
            fontSize: 13,
            fontWeight: 600,
            color: 'var(--text-1, #f1f5f9)',
            overflow: 'hidden',
            textOverflow: 'ellipsis',
            whiteSpace: 'nowrap',
          }}
        >
          <TextRaw value={decision.choice} maxLength={60} />
        </span>

        {/* Navegação prev/next — 2.3.8 / 2.3.9 (disabled nos extremos) */}
        <button
          disabled={prevKey === null}
          onClick={onPrev}
          aria-label="Decisão anterior"
          title="Decisão anterior"
          style={{
            background: 'none',
            border: '1px solid var(--border-2, #374151)',
            borderRadius: 4,
            padding: '2px 6px',
            color: prevKey === null ? 'var(--text-3, #64748b)' : 'var(--text-2, #94a3b8)',
            cursor: prevKey === null ? 'default' : 'pointer',
            fontSize: 12,
          }}
        >
          <Icon name="chevron-left" size={14} />
        </button>
        <button
          disabled={nextKey === null}
          onClick={onNext}
          aria-label="Próxima decisão"
          title="Próxima decisão"
          style={{
            background: 'none',
            border: '1px solid var(--border-2, #374151)',
            borderRadius: 4,
            padding: '2px 6px',
            color: nextKey === null ? 'var(--text-3, #64748b)' : 'var(--text-2, #94a3b8)',
            cursor: nextKey === null ? 'default' : 'pointer',
            fontSize: 12,
          }}
        >
          <Icon name="chevron-right" size={14} />
        </button>

        {/* Botão fechar (X) — 2.3.12 */}
        <button
          ref={closeButtonRef}
          onClick={onClose}
          aria-label="Fechar painel"
          title="Fechar painel (Escape)"
          style={{
            background: 'none',
            border: '1px solid var(--border-2, #374151)',
            borderRadius: 4,
            padding: '2px 6px',
            color: 'var(--text-2, #94a3b8)',
            cursor: 'pointer',
            fontSize: 12,
          }}
        >
          <Icon name="x" size={14} />
        </button>
      </div>

      {/* Metadados rápidos: onda + etapa + agente + score */}
      <div
        style={{
          display: 'flex',
          flexWrap: 'wrap',
          gap: 8,
          padding: '8px 14px',
          borderBottom: '1px solid var(--border-1, #1e293b)',
          flexShrink: 0,
        }}
      >
        {/* Onda — 2.3.6 */}
        <span
          style={{
            fontFamily: 'var(--font-mono, monospace)',
            fontSize: 11,
            color: 'var(--text-3, #64748b)',
            background: 'var(--bg-2, #1e293b)',
            padding: '2px 6px',
            borderRadius: 4,
          }}
        >
          {decision.wave}
        </span>

        {/* Etapa — somente se presente */}
        {decision.stage && (
          <span
            style={{
              fontFamily: 'var(--font-mono, monospace)',
              fontSize: 11,
              color: 'var(--text-2, #94a3b8)',
              background: 'var(--bg-2, #1e293b)',
              padding: '2px 6px',
              borderRadius: 4,
            }}
          >
            {decision.stage}
          </span>
        )}

        {/* Score — 2.3.6 */}
        <ScoreChip score={decision.score} />

        {/* Classe da decisão (schema v15) — estrutural destacada; ausente = não declarada */}
        {decision.decisionClass && (
          <span
            title="classe da decisão (gate estrutural)"
            style={{
              fontFamily: 'var(--font-mono, monospace)',
              fontSize: 11,
              padding: '2px 6px',
              borderRadius: 4,
              background:
                decision.decisionClass === 'estrutural'
                  ? 'var(--warning-soft, rgba(245,158,11,0.12))'
                  : 'var(--bg-2, #1e293b)',
              color:
                decision.decisionClass === 'estrutural'
                  ? 'var(--warning, #f59e0b)'
                  : 'var(--text-2, #94a3b8)',
            }}
          >
            <TextRaw value={decision.decisionClass} maxLength={24} />
          </span>
        )}

        {/* Eixo estrutural (schema v15) — somente se presente */}
        {decision.structuralAxis && (
          <span
            title="eixo estrutural"
            style={{
              fontFamily: 'var(--font-mono, monospace)',
              fontSize: 11,
              color: 'var(--text-2, #94a3b8)',
              background: 'var(--bg-2, #1e293b)',
              padding: '2px 6px',
              borderRadius: 4,
            }}
          >
            <TextRaw value={decision.structuralAxis} maxLength={32} />
          </span>
        )}

        {/* Agente — UNTRUSTED, somente se presente — 2.3.6 */}
        {decision.agent && (
          <span
            style={{
              fontFamily: 'var(--font-mono, monospace)',
              fontSize: 11,
              color: 'var(--text-3, #64748b)',
              overflow: 'hidden',
              textOverflow: 'ellipsis',
              whiteSpace: 'nowrap',
              maxWidth: 180,
            }}
          >
            <TextRaw value={decision.agent} maxLength={40} />
          </span>
        )}
      </div>

      {/* Corpo rolável */}
      <div
        style={{
          flex: 1,
          overflowY: 'auto',
          padding: '12px 14px',
          display: 'flex',
          flexDirection: 'column',
          gap: 12,
        }}
      >
        {/* Opções consideradas — 2.3.3 */}
        {opts.length > 0 && (
          <div>
            <SectionLabel>opcoes consideradas</SectionLabel>
            <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
              {opts.map((opt, i) => {
                const chosen = i === chosenIdx;
                return (
                  <span
                    key={`${opt}-${i}`}
                    title={chosen ? 'opcao escolhida' : undefined}
                    style={{
                      display: 'inline-flex',
                      alignItems: 'center',
                      gap: 4,
                      padding: '2px 8px',
                      borderRadius: 8,
                      fontSize: 11,
                      fontFamily: 'var(--font-mono, monospace)',
                      background: chosen
                        ? 'var(--accent-soft, rgba(59,130,246,0.1))'
                        : 'var(--bg-2, #1e293b)',
                      color: chosen
                        ? 'var(--accent, #3b82f6)'
                        : 'var(--text-2, #94a3b8)',
                      border: `1px solid ${chosen ? 'var(--accent-line, rgba(59,130,246,0.3))' : 'var(--border, #1e293b)'}`,
                      fontWeight: chosen ? 600 : 400,
                    }}
                  >
                    {chosen && <Icon name="check" size={11} />}
                    {/* opt é campo UNTRUSTED — renderizado via TextRaw */}
                    <TextRaw value={opt} maxLength={48} />
                  </span>
                );
              })}
            </div>
          </div>
        )}

        {/* Contexto — 2.3.4 (somente se presente — 2.3.7) */}
        {decision.context && (
          <div>
            <SectionLabel>contexto</SectionLabel>
            <TextRaw value={decision.context} />
          </div>
        )}

        {/* Justificativa — 2.3.4 (somente se presente — 2.3.7) */}
        {decision.rationale && (
          <div>
            <SectionLabel>justificativa</SectionLabel>
            <TextRaw value={decision.rationale} />
          </div>
        )}

        {/* Evidência — 2.3.5 mono em bloco (somente se presente — 2.3.7) */}
        {decision.evidencia && (
          <div>
            <SectionLabel>evidencia (empirica)</SectionLabel>
            <div
              style={{
                background: 'var(--bg-0, #020617)',
                border: '1px solid var(--border, #1e293b)',
                borderRadius: 4,
                padding: '8px 10px',
              }}
            >
              <TextRaw value={decision.evidencia} mono />
            </div>
          </div>
        )}

        {/* Consentimento humano (schema v15) — id do BloqueioHumano respondido */}
        {decision.humanConsentBlockId && (
          <div>
            <SectionLabel>consentimento humano</SectionLabel>
            <TextRaw value={decision.humanConsentBlockId} mono />
          </div>
        )}
      </div>
    </div>
  );
}
