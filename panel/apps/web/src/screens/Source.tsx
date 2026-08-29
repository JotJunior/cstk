/**
 * Source — tela "Fonte de Dados" (prototipo screens_aux.jsx · SourceScreen).
 * CARD-SC-01 (metadados do banco) + CARD-SC-02 (contagens por tabela).
 * Consome /health (useHealth): caminho, schema_version (meta), frescor, estado,
 * tamanho e contagem por tabela. Read-only e best-effort (Principio II).
 */
import { useHealth } from '@/lib/hooks.js';
import { useApiState } from '@/hooks/useApiState.js';
import { LoadingState, ErrorState, DegradedBanner } from '@/states/index.js';
import { Icon, MiniStat } from '@/components/index.js';
import { fmtNum, fmtRelative } from '@/lib/format.js';

/** Formata bytes em B/KB/MB. */
function fmtBytes(bytes: number | null): string {
  if (bytes == null) return '—';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

export function Source() {
  const query = useHealth();
  const { isLoading, isError, errorMessage, isDegraded } = useApiState(query);

  if (isLoading) return <LoadingState variant="kpi" />;
  if (isError) return <ErrorState message={errorMessage ?? 'Erro ao consultar a fonte de dados.'} />;

  const data = query.data?.data;
  const meta = query.data?.meta;
  const counts = data?.counts;
  const fresh = meta?.freshness;
  const freshLabel = fmtRelative(fresh?.maxIngestedAt || fresh?.mtime);
  const ok = !isDegraded && (data?.ok ?? false);

  // Linhas da tabela de contagens (CARD-SC-02)
  const tableRows: { table: string; rows: number | null }[] = [
    { table: 'executions', rows: counts?.executions ?? null },
    { table: 'waves', rows: counts?.waves ?? null },
    { table: 'decisions', rows: counts?.decisions ?? null },
    { table: 'tasks', rows: counts?.tasks ?? null },
    { table: 'events', rows: counts?.events ?? null },
    { table: 'alert_signals', rows: counts?.alertSignals ?? null },
    { table: 'bloqueios', rows: counts?.bloqueios ?? null },
    { table: 'skills', rows: counts?.skills ?? null },
    { table: 'retros', rows: counts?.retros ?? null },
    { table: 'memories (v4)', rows: counts?.memories ?? null },
    { table: 'fts_decisoes (FTS5)', rows: counts?.ftsDecisoes ?? null },
    { table: 'fts_retros (FTS5)', rows: counts?.ftsRetros ?? null },
  ];

  return (
    <div className="col gap-4">
      <div className="page-head">
        <div>
          <h1>Fonte de dados</h1>
          <div className="sub">knowledge.db · schema v{meta?.schemaVersion ?? '—'} · read-only e best-effort</div>
        </div>
      </div>

      {isDegraded && meta && <DegradedBanner meta={meta} />}

      <div className="grid-2">
        {/* CARD-SC-01 — metadados */}
        <div className="card">
          <div className="card-head"><h3>Fonte de dados</h3></div>
          <div className="card-pad col" style={{ gap: 14 }}>
            <MiniStat
              label="Caminho do banco"
              value={<span className="mono" style={{ fontSize: 12.5 }}>{data?.path ?? '—'}</span>}
            />
            <div className="grid-3">
              <MiniStat label="schema_version" value={meta?.schemaVersion ?? '—'} />
              <MiniStat label="tipo" value="SQLite + FTS5" />
              <MiniStat label="acesso" value="read-only" />
            </div>
            <div className="divider" />
            <div className="row" style={{ justifyContent: 'space-between' }}>
              <MiniStat label="frescor" value={freshLabel} />
              <MiniStat
                label="estado"
                value={<span style={{ color: ok ? 'var(--success)' : 'var(--warning)' }}>{ok ? 'ok' : 'degradado'}</span>}
              />
              <MiniStat label="tamanho" value={fmtBytes(data?.sizeBytes ?? null)} />
            </div>
            <div
              className="degraded-banner"
              style={{ margin: 0, background: 'var(--info-soft)', borderColor: 'rgba(96,165,250,0.2)', color: 'var(--info)' }}
            >
              <Icon name="database" size={14} aria-hidden />
              <span>
                Índice é <strong>derivado e best-effort</strong> a partir das execuções dos
                orquestradores. Pode ser reconstruído a qualquer momento via{' '}
                <span className="mono" style={{ background: 'rgba(0,0,0,0.2)', padding: '1px 6px', borderRadius: 3, fontSize: 11 }}>cstk --reindex</span>.
              </span>
            </div>
          </div>
        </div>

        {/* CARD-SC-02 — contagens por tabela */}
        <div className="card">
          <div className="card-head"><h3>Contagens por tabela</h3></div>
          <div style={{ overflowX: 'auto' }}>
            <table className="tbl">
              <thead>
                <tr><th>Tabela</th><th className="num">Linhas</th></tr>
              </thead>
              <tbody>
                {tableRows.map((r) => (
                  <tr key={r.table}>
                    <td className="mono" style={{ fontSize: 12 }}>{r.table}</td>
                    <td className="num">{r.rows == null ? '—' : fmtNum(r.rows)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  );
}
