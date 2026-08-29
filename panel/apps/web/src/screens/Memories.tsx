/**
 * Memorias — auto-memorias do Claude Code, separadas por projeto (schema v4).
 *
 * Espelho READ-ONLY dos arquivos `.md` de memoria (tabela `memories`, feature
 * recall-memory-mirror do cstk/claude-ai-tips). O painel apenas exibe; a fonte
 * canonica sao os `.md` no disco do harness. Filtro por projeto (server-side) +
 * tipo e busca textual (client-side).
 *
 * Principio V (UNTRUSTED): `description`/`body` vem de `.md` autorados pelo
 * operador (ja scrubbed na ingestao). Renderizados via children de React
 * (textContent — React escapa), NUNCA via dangerouslySetInnerHTML.
 */
import { useMemo, useState } from 'react';
import { useMemories } from '@/lib/hooks.js';
import { useApiState } from '@/hooks/useApiState.js';
import { LoadingState, EmptyState, ErrorState, DegradedBanner } from '@/states/index.js';
import { Icon } from '@/components/index.js';
import { TextRaw } from '@/components/TextRaw.js';
import { fmtRelative } from '@/lib/format.js';
import { memoryDisplayDescription } from '@/lib/memory-display.js';
import type { MemoryDTO, MemoryType } from '@cstk-panel/shared-types';

type TypeFilter = 'all' | MemoryType;

const TYPE_LABEL: Record<MemoryType, string> = {
  index: 'índice',
  feedback: 'feedback',
  project: 'projeto',
  reference: 'referência',
  user: 'usuário',
};

/** Cor de acento por tipo (decorativo). Usa tokens de cor existentes. */
const TYPE_COLOR: Record<MemoryType, string> = {
  index: 'var(--text-3)',
  feedback: 'var(--warning)',
  project: 'var(--info)',
  reference: 'var(--accent, var(--info))',
  user: 'var(--success)',
};

export function Memories() {
  const [projectFilter, setProjectFilter] = useState('');
  const [typeFilter, setTypeFilter] = useState<TypeFilter>('all');
  const [q, setQ] = useState('');
  const [expanded, setExpanded] = useState<Set<string>>(new Set());

  // Filtro de projeto e server-side (refaz a query); tipo e texto sao client-side.
  const query = useMemories(projectFilter || undefined);
  const { isLoading, isError, errorMessage, isEmpty, isDegraded } = useApiState(query);

  const payload = query.data?.data as
    | { memories?: MemoryDTO[]; projects?: string[]; pagination?: { total: number; hasMore: boolean } }
    | null
    | undefined;
  const all = payload?.memories ?? [];
  const projects = payload?.projects ?? [];
  const total = payload?.pagination?.total ?? all.length;
  const truncated = payload?.pagination?.hasMore ?? false;

  const needle = q.trim().toLowerCase();
  const filtered = useMemo(
    () =>
      all.filter(
        (m) =>
          (typeFilter === 'all' || m.type === typeFilter) &&
          (needle === '' ||
            m.slug.toLowerCase().includes(needle) ||
            (m.description ?? '').toLowerCase().includes(needle) ||
            (m.body ?? '').toLowerCase().includes(needle)),
      ),
    [all, typeFilter, needle],
  );

  function toggle(key: string) {
    setExpanded((prev) => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  }

  if (isLoading) return <LoadingState variant="rows" />;
  if (isError) return <ErrorState message={errorMessage ?? 'Erro ao carregar memórias.'} />;

  const meta = query.data?.meta;

  return (
    <div className="col gap-4">
      <div className="page-head">
        <div>
          <h1>Memórias</h1>
          <div className="sub">
            {total} memória{total === 1 ? '' : 's'} · espelho read-only dos arquivos de
            auto-memória do Claude Code, por projeto
          </div>
        </div>
      </div>

      {isDegraded && meta && <DegradedBanner meta={meta} />}

      {isEmpty ? (
        <EmptyState
          title="Nenhuma memória indexada"
          subtitle="Bases sem schema v4 (ou sem auto-memórias) não têm memórias. Rode cstk recall --reindex para reconstruir o índice a partir dos .md."
        />
      ) : (
        <>
          {/* Barra de filtros */}
          <div className="card">
            <div className="card-head">
              <h3>Filtros</h3>
              <div className="row gap-2">
                <div className="period-tabs" role="tablist" aria-label="Filtrar por tipo">
                  {(['all', 'index', 'feedback', 'project', 'reference', 'user'] as TypeFilter[]).map(
                    (t) => (
                      <button
                        key={t}
                        className={typeFilter === t ? 'active' : ''}
                        onClick={() => setTypeFilter(t)}
                      >
                        {t === 'all' ? 'todas' : TYPE_LABEL[t]}
                      </button>
                    ),
                  )}
                </div>
                <select
                  className="select"
                  aria-label="Filtrar por projeto"
                  value={projectFilter}
                  onChange={(e) => setProjectFilter(e.target.value)}
                >
                  <option value="">Todos os projetos</option>
                  {projects.map((p) => (
                    <option key={p} value={p}>
                      {p}
                    </option>
                  ))}
                </select>
                <input
                  className="select"
                  type="search"
                  placeholder="buscar no slug/conteúdo…"
                  aria-label="Buscar nas memórias"
                  value={q}
                  onChange={(e) => setQ(e.target.value)}
                  style={{ minWidth: 200 }}
                />
              </div>
            </div>
          </div>

          {/* Lista de memórias */}
          <div className="col gap-3">
            {filtered.length === 0 ? (
              <div className="card">
                <div
                  className="card-pad"
                  style={{ textAlign: 'center', color: 'var(--text-3)', padding: 24 }}
                >
                  Nenhuma memória corresponde aos filtros.
                </div>
              </div>
            ) : (
              filtered.map((m) => {
                const key = `${m.project}/${m.slug}`;
                const isOpen = expanded.has(key);
                return (
                  <div key={key} className="card">
                    <div
                      className="card-head clickable"
                      onClick={() => toggle(key)}
                      role="button"
                      tabIndex={0}
                      onKeyDown={(e) => (e.key === 'Enter' || e.key === ' ') && toggle(key)}
                      aria-expanded={isOpen}
                    >
                      <div className="row gap-2" style={{ alignItems: 'center', minWidth: 0 }}>
                        <span
                          className="badge"
                          style={{ color: TYPE_COLOR[m.type], borderColor: 'currentColor' }}
                        >
                          {TYPE_LABEL[m.type]}
                        </span>
                        <span className="mono" style={{ color: 'var(--text-0)', fontWeight: 600 }}>
                          {m.slug}
                        </span>
                      </div>
                      <div className="row gap-2" style={{ alignItems: 'center' }}>
                        <span className="prov">
                          <Icon name="folder" size={12} aria-hidden />
                          <span>{m.project}</span>
                        </span>
                        <span className="mono muted" style={{ fontSize: 10.5 }}>
                          {m.indexedAt ? fmtRelative(m.indexedAt) : '—'}
                        </span>
                        <Icon name={isOpen ? 'chevron-up' : 'chevron-down'} size={14} aria-hidden />
                      </div>
                    </div>
                    <div className="card-pad col" style={{ gap: 10 }}>
                      {/* descricao — UNTRUSTED, renderizada via textContent.
                          memoryDisplayDescription contorna o ruido de frontmatter
                          do produtor (description='---') sem reescrever o indice. */}
                      <TextRaw value={memoryDisplayDescription(m)} className="muted" />

                      {isOpen && (
                        <>
                          {/* corpo .md — UNTRUSTED; React escapa os children (textContent) */}
                          <pre
                            className="mono"
                            style={{
                              whiteSpace: 'pre-wrap',
                              wordBreak: 'break-word',
                              maxHeight: 420,
                              overflow: 'auto',
                              margin: 0,
                              padding: 12,
                              background: 'var(--bg-2, rgba(0,0,0,0.18))',
                              borderRadius: 6,
                              fontSize: 12,
                              lineHeight: 1.5,
                              color: 'var(--text-1)',
                            }}
                          >
                            {m.body && m.body.trim() !== '' ? m.body : '(arquivo vazio)'}
                          </pre>
                          {m.path && (
                            <div className="mono muted" style={{ fontSize: 10.5 }}>
                              {m.path}
                            </div>
                          )}
                        </>
                      )}
                    </div>
                  </div>
                );
              })
            )}
          </div>

          {truncated && (
            <div className="mono muted" style={{ fontSize: 11, textAlign: 'center' }}>
              Exibindo as primeiras {all.length} de {total} memórias. Use o filtro de projeto
              para refinar.
            </div>
          )}
        </>
      )}
    </div>
  );
}
