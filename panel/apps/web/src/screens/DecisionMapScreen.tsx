/**
 * DecisionMapScreen — página dedicada à árvore de decisões de uma execução.
 *
 * Rota: /executions/:execucaoId/decision-map[?wave=<onda>]
 *
 * Diferente do comportamento anterior (mapa substituía a tabela na aba
 * Decisões), a árvore agora tem página própria, acessada pelo botão
 * "árvore de decisões" no detalhe da execução. Mantém o filtro de onda
 * opcional via query param `wave`.
 *
 * Read-only; campos UNTRUSTED renderizados via TextRaw nos componentes filhos.
 */

import { useParams, useSearchParams, useNavigate } from 'react-router-dom';
import { useExecution } from '@/lib/hooks.js';
import { useApiState } from '@/hooks/useApiState.js';
import { LoadingState, EmptyState, ErrorState } from '@/states/index.js';
import { Icon } from '@/components/index.js';
import { DecisionMapPanel } from '@/components/DecisionMapPanel.js';
import type { ExecutionDTO } from '@cstk-panel/shared-types';

export function DecisionMapScreen() {
  const { execucaoId } = useParams<{ execucaoId: string }>();
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();

  const waveFilter = searchParams.get('wave');
  const execQuery = useExecution(execucaoId ?? '');
  const { isLoading, isError, errorMessage } = useApiState(execQuery);

  const id = execucaoId ?? '';
  const backTo = `/executions/${encodeURIComponent(id)}?tab=decisions${waveFilter ? `&wave=${encodeURIComponent(waveFilter)}` : ''}`;

  if (isLoading) return <LoadingState />;
  if (isError) return <ErrorState message={errorMessage ?? 'Erro ao carregar execucao.'} />;

  const exec: ExecutionDTO | null = execQuery.data?.data ?? null;
  if (!exec) {
    return (
      <EmptyState
        title="Execucao nao encontrada"
        subtitle="O execucao_id informado nao existe na base."
      />
    );
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      {/* Header da página dedicada */}
      <div className="card">
        <div className="card-body">
          <div className="row" style={{ justifyContent: 'space-between', flexWrap: 'wrap', gap: 12 }}>
            <div style={{ minWidth: 0 }}>
              <div className="row gap-2" style={{ marginBottom: 4 }}>
                <Icon name="tree" size={14} aria-hidden />
                <span style={{ fontSize: 16, fontWeight: 700 }}>Árvore de decisões</span>
                {waveFilter && (
                  <span
                    style={{
                      padding: '2px 7px',
                      borderRadius: 8,
                      fontSize: 11,
                      background: 'var(--bg-3)',
                      color: 'var(--text-1)',
                      border: '1px solid var(--border)',
                      fontFamily: 'var(--font-mono)',
                    }}
                  >
                    {waveFilter}
                  </span>
                )}
              </div>
              <div className="row gap-2" style={{ fontSize: 11.5, color: 'var(--text-2)' }}>
                <span style={{ fontFamily: 'var(--font-mono)', color: 'var(--accent)' }}>{exec.executionId}</span>
                <span style={{ color: 'var(--text-3)' }}>·</span>
                <span>{exec.decisionsTotal ?? 0} decisões</span>
              </div>
            </div>
            <div className="row gap-2" style={{ flexShrink: 0 }}>
              <button className="tb-btn" onClick={() => navigate(backTo)} title="Voltar ao detalhe da execução">
                <Icon name="chevron-left" size={13} aria-hidden />voltar à execução
              </button>
            </div>
          </div>
        </div>
      </div>

      {/* Árvore (página inteira) — overflow visível para o painel de detalhe
          (position: sticky) não ser clipado pelo `.card { overflow: hidden }`. */}
      <div className="card" style={{ overflow: 'visible' }}>
        <div className="card-body">
          <DecisionMapPanel
            execucaoId={id}
            waveFilter={waveFilter}
            mapVisible={true}
            onToggle={() => navigate(backTo)}
          />
        </div>
      </div>
    </div>
  );
}
