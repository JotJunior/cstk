/**
 * DecisionMapPanel — componente orquestrador do mapa de decisões.
 *
 * Integra query (useDecisions), engine de layout (computeLayout),
 * renderização SVG (DecisionMapSvg) e painel lateral (DecisionDetailPane).
 * Implementa os 4 estados obrigatórios: loading, vazio, erro, degradado.
 *
 * Estado mapVisible gerenciado externamente (ExecutionDetail.tsx) — dec-012.
 * Este componente gerencia apenas selectedKey.
 *
 * Ref: tasks 3.1.1–3.1.12; spec §FR-002, FR-006, FR-008, FR-009, FR-010;
 *      plan §DecisionMapPanel; data-model §DecisionMapState
 */

import React, { useEffect, useRef, useCallback } from 'react';
import { useDecisions } from '@/lib/hooks.js';
import { computeLayout, prevKey, nextKey } from '@/lib/decision-map-layout.js';
import { DecisionMapSvg } from './DecisionMapSvg.js';
import { DecisionDetailPane } from './DecisionDetailPane.js';
import { DegradedBanner } from '@/states/DegradedBanner.js';
import { LoadingState } from '@/states/LoadingState.js';
import { EmptyState } from '@/states/EmptyState.js';
import { ErrorState } from '@/states/ErrorState.js';

// ---------------------------------------------------------------------------
// Props
// ---------------------------------------------------------------------------

interface DecisionMapPanelProps {
  /** ID da execução para carregar decisões. */
  execucaoId: string;
  /** Filtro de onda ativo na tela pai (null = todas as ondas). */
  waveFilter: string | null;
  /** Visibilidade do mapa (controlada pelo ExecutionDetail). */
  mapVisible: boolean;
  /** Callback para toggle do mapa (fechar). */
  onToggle: () => void;
}

// ---------------------------------------------------------------------------
// Componente
// ---------------------------------------------------------------------------

export function DecisionMapPanel({
  execucaoId,
  waveFilter,
  mapVisible,
}: DecisionMapPanelProps) {
  // 3.1.2: selectedKey — único state local
  const [selectedKey, setSelectedKey] = React.useState<string | null>(null);

  // 3.1.3: query com limit=100 (teto máximo do backend)
  const { data, isLoading, isError, error, refetch } = useDecisions(execucaoId, {
    limit: 100,
    ...(waveFilter ? { wave: waveFilter } : {}),
  });

  // Refs de nós para foco programático
  const nodeRefs = useRef<Map<string, SVGGElement>>(new Map());

  // Layout derivado dos dados
  const items = data?.data?.decisions ?? [];
  const layout = computeLayout(items);

  // 3.1.12: foco inicial ao abrir o mapa (dec-015 / CHK021)
  useEffect(() => {
    if (mapVisible && layout.nodes.length > 0) {
      // Focar primeiro nó após render
      const firstNode = layout.nodes[0];
      if (firstNode) {
        const el = nodeRefs.current.get(firstNode.key);
        if (el) {
          // Pequeno delay para garantir que o DOM está montado
          requestAnimationFrame(() => el.focus());
        }
      }
    }
  }, [mapVisible, layout.nodes.length]);

  // 3.1.11: prevKey/nextKey para navegação no painel
  const selectedPrevKey = selectedKey ? prevKey(layout.nodes, selectedKey) : null;
  const selectedNextKey = selectedKey ? nextKey(layout.nodes, selectedKey) : null;

  // Fechar painel e retornar foco ao nó selecionado (dec-016 / CHK022)
  const handleClosePane = useCallback(() => {
    const key = selectedKey;
    setSelectedKey(null);
    if (key) {
      requestAnimationFrame(() => {
        const el = nodeRefs.current.get(key);
        el?.focus();
      });
    }
  }, [selectedKey]);

  // Navegar para decisão anterior
  const handlePrev = useCallback(() => {
    if (selectedPrevKey) setSelectedKey(selectedPrevKey);
  }, [selectedPrevKey]);

  // Navegar para próxima decisão
  const handleNext = useCallback(() => {
    if (selectedNextKey) setSelectedKey(selectedNextKey);
  }, [selectedNextKey]);

  // Decisão selecionada
  const selectedNode = layout.nodes.find(n => n.key === selectedKey);
  const selectedDecision = selectedNode?.decision ?? null;

  // Metadados da resposta
  const meta = data?.meta;
  const pagination = data?.data?.pagination;

  // Se mapa fechado: não renderizar nada
  if (!mapVisible) {
    return null;
  }

  // 3.1.5: estado loading
  if (isLoading) {
    return (
      <div style={{ padding: '24px' }}>
        <LoadingState variant="kpi" />
      </div>
    );
  }

  // 3.1.7: estado erro com botão de retry explícito (dec-013 / CHK054)
  if (isError) {
    const errorMessage =
      error instanceof Error ? error.message : 'Erro ao carregar decisões.';
    return (
      <div style={{ padding: '24px', display: 'flex', flexDirection: 'column', gap: 12, alignItems: 'flex-start' }}>
        <ErrorState
          message="Erro ao carregar o mapa de decisões."
          detail={errorMessage}
        />
        <button
          onClick={() => void refetch()}
          style={{
            background: 'var(--bg-2, #1e293b)',
            border: '1px solid var(--border-2, #374151)',
            borderRadius: 6,
            padding: '6px 14px',
            color: 'var(--text-1, #f1f5f9)',
            cursor: 'pointer',
            fontSize: 13,
          }}
        >
          Tentar novamente
        </button>
      </div>
    );
  }

  // 3.1.6: estado vazio
  if (items.length === 0) {
    return (
      <EmptyState
        title="Nenhuma decisão registrada para esta execução."
        subtitle="Execute o orquestrador para gerar decisões auditáveis."
      />
    );
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
      {/* 3.1.8: banner degradado (meta.degraded = true) */}
      {meta && meta.degraded && <DegradedBanner meta={meta} />}

      {/* 3.1.9: banner de corte quando pagination.hasMore = true */}
      {pagination?.hasMore && (
        <div
          role="alert"
          style={{
            background: 'var(--bg-2, #1e293b)',
            border: '1px solid var(--border-2, #374151)',
            borderRadius: 6,
            padding: '6px 12px',
            fontSize: 12,
            color: 'var(--text-2, #94a3b8)',
          }}
        >
          Exibindo as primeiras 100 decisões. A execução possui mais decisões
          registradas — use o filtro de onda para visualizar por onda.
        </div>
      )}

      {/* 3.1.10: layout split — mapa + painel lateral */}
      <div
        style={{
          display: 'grid',
          gridTemplateColumns: selectedKey && selectedDecision ? '3fr 2fr' : '1fr',
          gap: 8,
          minHeight: 0,
        }}
      >
        {/* Mapa SVG */}
        <DecisionMapSvg
          nodes={layout.nodes}
          edges={layout.edges}
          svgWidth={layout.svgWidth}
          svgHeight={layout.svgHeight}
          selectedKey={selectedKey}
          onNodeSelect={setSelectedKey}
          nodeRefs={nodeRefs}
        />

        {/* Painel lateral de detalhe — sticky abaixo da topbar (52px) para
            permanecer visível ao rolar a árvore (clicar num nó lá no fim não
            exige rolar de volta ao topo). */}
        {selectedKey && selectedDecision && (
          <div style={{ position: 'sticky', top: 60, alignSelf: 'start', maxHeight: 'calc(100vh - 72px)', overflow: 'auto' }}>
            <DecisionDetailPane
              decision={selectedDecision}
              prevKey={selectedPrevKey}
              nextKey={selectedNextKey}
              onPrev={handlePrev}
              onNext={handleNext}
              onClose={handleClosePane}
            />
          </div>
        )}
      </div>
    </div>
  );
}
