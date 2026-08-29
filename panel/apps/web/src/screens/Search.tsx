/**
 * Search — Busca de Conhecimento FTS5 (US3).
 * Campo de busca com debounce 300ms, filtros type/project/feature,
 * resultados paginados com rank bm25.
 *
 * Conteudo UNTRUSTED (body, highlight) via TextRaw — nunca innerHTML.
 * Payloads hostis (aspas, parenteses, SQL) sao tratados pelo backend FTS5;
 * o frontend apenas renderiza como texto literal via TextRaw.
 *
 * Ref: spec.md §User Story 3; tasks.md §6.3
 */
import { useState, useEffect, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import { useSearch } from '@/lib/hooks.js';
import { useApiState } from '@/hooks/useApiState.js';
import { LoadingState, EmptyState, ErrorState } from '@/states/index.js';
import { TextRaw, Icon } from '@/components/index.js';
import type { FtsHitDTO } from '@cstk-panel/shared-types';

const TYPE_OPTIONS = [
  { value: '',          label: 'Todos os tipos' },
  { value: 'decision',  label: 'Decisoes' },
  { value: 'bloqueio',  label: 'Bloqueios' },
  { value: 'retro',     label: 'Retrospectivas' },
  { value: 'skill',     label: 'Skills' },
];

const TYPE_COLOR: Record<string, string> = {
  decision:  'var(--accent)',
  bloqueio:  'var(--warning)',
  retro:     'var(--info)',
  skill:     'var(--success)',
};

function TypeBadge({ type }: { type: string }) {
  return (
    <span style={{
      padding: '2px 7px',
      borderRadius: 8,
      fontSize: 10.5,
      fontWeight: 600,
      fontFamily: 'var(--font-mono)',
      background: `${TYPE_COLOR[type] ?? 'var(--text-3)'}22`,
      color: TYPE_COLOR[type] ?? 'var(--text-3)',
    }}>
      {type}
    </span>
  );
}

export function Search() {
  const navigate = useNavigate();
  const [input, setInput] = useState('');
  const [q, setQ] = useState('');
  const [filterType, setFilterType] = useState('');
  const [page, setPage] = useState(0);
  const limit = 20;
  const debounceRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);

  // Debounce 300ms
  useEffect(() => {
    if (debounceRef.current != null) clearTimeout(debounceRef.current);
    if (input.length < 2) {
      setQ('');
      setPage(0);
      return;
    }
    debounceRef.current = setTimeout(() => {
      setQ(input);
      setPage(0);
    }, 300);
    return () => { if (debounceRef.current != null) clearTimeout(debounceRef.current); };
  }, [input]);

  const searchOpts: Parameters<typeof useSearch>[1] = { limit, offset: page * limit };
  if (filterType) searchOpts.type = filterType;
  const query = useSearch(q, searchOpts);
  const { isLoading, isError, errorMessage } = useApiState(query);
  const items: FtsHitDTO[] = query.data?.data?.results ?? [];

  // Distinguir entre "digitando" e "sem resultados"
  const isEmpty = !isLoading && !isError && q.length >= 2 && items.length === 0;
  const isIdle  = q.length < 2;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      {/* Campo de busca */}
      <div className="card">
        <div className="card-body">
          <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
            {/* Input principal */}
            <div style={{
              display: 'flex', alignItems: 'center', gap: 10,
              background: 'var(--bg-2)', border: '1px solid var(--border)',
              borderRadius: 'var(--r-md)', padding: '10px 14px',
            }}>
              <Icon name="search" size={16} style={{ color: 'var(--text-2)', flexShrink: 0 }} />
              <input
                type="text"
                value={input}
                onChange={e => setInput(e.target.value)}
                placeholder="Buscar decisoes, bloqueios, retrospectivas, skills…"
                autoFocus
                style={{
                  background: 'transparent', border: 'none', outline: 'none',
                  color: 'var(--text-0)', fontSize: 14, flex: 1,
                }}
              />
              {input && (
                <button
                  onClick={() => { setInput(''); setQ(''); }}
                  style={{
                    background: 'transparent', border: 'none',
                    color: 'var(--text-3)', cursor: 'pointer', padding: 4,
                  }}
                >
                  <Icon name="x" size={14} />
                </button>
              )}
            </div>

            {/* Filtros */}
            <div className="row gap-2">
              <select
                className="select"
                value={filterType}
                onChange={e => { setFilterType(e.target.value); setPage(0); }}
              >
                {TYPE_OPTIONS.map(o => (
                  <option key={o.value} value={o.value}>{o.label}</option>
                ))}
              </select>
              {q.length >= 2 && !isLoading && (
                <span style={{ fontSize: 11.5, color: 'var(--text-2)', fontFamily: 'var(--font-mono)' }}>
                  {items.length} resultado{items.length !== 1 ? 's' : ''} para "{q}"
                </span>
              )}
            </div>
          </div>
        </div>
      </div>

      {/* Resultados */}
      {isIdle && (
        <div className="card">
          <div style={{ padding: '48px 24px', textAlign: 'center', color: 'var(--text-3)' }}>
            <Icon name="search" size={32} style={{ marginBottom: 12 }} />
            <div style={{ fontSize: 14, fontWeight: 600, color: 'var(--text-2)', marginBottom: 4 }}>
              Busca FTS5 ranqueada por bm25
            </div>
            <div style={{ fontSize: 12, color: 'var(--text-3)' }}>
              Digite ao menos 2 caracteres para buscar decisoes, bloqueios, retros e skills.
            </div>
          </div>
        </div>
      )}

      {!isIdle && isLoading && <LoadingState />}

      {!isIdle && isError && (
        <ErrorState message={errorMessage ?? 'Erro na busca. Tente novamente.'} />
      )}

      {!isIdle && isEmpty && (
        <EmptyState
          title="Nenhum resultado encontrado"
          subtitle={`Nenhum registro encontrado para "${q}". Tente termos mais simples.`}
        />
      )}

      {!isIdle && !isLoading && !isError && items.length > 0 && (
        <div className="card">
          <div style={{ display: 'flex', flexDirection: 'column' }}>
            {items.map((hit, idx) => {
              // So navega quando ha execucao de origem resolvida pelo backend
              const target = hit.executionId
                ? `/executions/${encodeURIComponent(hit.executionId)}${hit.wave && hit.wave !== 'unknown' ? `?wave=${encodeURIComponent(hit.wave)}` : ''}`
                : null;
              return (
              <div
                key={idx}
                style={{
                  padding: '14px 18px',
                  borderBottom: '1px solid var(--border-soft)',
                  cursor: target ? 'pointer' : 'default',
                }}
                onClick={() => { if (target) navigate(target); }}
              >
                <div className="row" style={{ justifyContent: 'space-between', marginBottom: 6 }}>
                  <div className="row gap-2">
                    <TypeBadge type={hit.type} />
                    <span style={{ fontFamily: 'var(--font-mono)', fontSize: 11, color: 'var(--text-2)' }}>
                      {hit.project}
                      {hit.feature ? <><span style={{ color: 'var(--text-3)', margin: '0 4px' }}>/</span>{hit.feature}</> : null}
                    </span>
                  </div>
                  <div className="row gap-2">
                    {hit.wave && hit.wave !== 'unknown' && (
                      <span style={{ fontFamily: 'var(--font-mono)', fontSize: 10.5, color: 'var(--inprogress)' }}>
                        {hit.wave}
                      </span>
                    )}
                    <span style={{ fontFamily: 'var(--font-mono)', fontSize: 10, color: 'var(--text-3)' }}>
                      rank {hit.rank.toFixed(2)}
                    </span>
                  </div>
                </div>
                {/* Body UNTRUSTED — renderizado como textContent via TextRaw */}
                <div style={{ fontSize: 12.5, color: 'var(--text-1)', lineHeight: 1.5 }}>
                  <TextRaw value={hit.body} maxLength={300} />
                </div>
              </div>
              );
            })}
          </div>

          {/* Paginacao */}
          <div style={{
            display: 'flex', justifyContent: 'space-between', padding: '10px 18px',
            borderTop: '1px solid var(--border)', fontSize: 12,
          }}>
            <button
              disabled={page === 0}
              onClick={() => setPage(p => p - 1)}
              style={{
                background: 'var(--bg-2)', border: '1px solid var(--border)',
                borderRadius: 'var(--r-xs)', padding: '4px 12px',
                color: page === 0 ? 'var(--text-3)' : 'var(--text-1)',
                cursor: page === 0 ? 'default' : 'pointer',
              }}
            >
              anterior
            </button>
            <span style={{ fontFamily: 'var(--font-mono)', fontSize: 11, color: 'var(--text-2)' }}>
              pagina {page + 1} · {items.length} resultados
            </span>
            <button
              disabled={items.length < limit}
              onClick={() => setPage(p => p + 1)}
              style={{
                background: 'var(--bg-2)', border: '1px solid var(--border)',
                borderRadius: 'var(--r-xs)', padding: '4px 12px',
                color: items.length < limit ? 'var(--text-3)' : 'var(--text-1)',
                cursor: items.length < limit ? 'default' : 'pointer',
              }}
            >
              proxima
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
