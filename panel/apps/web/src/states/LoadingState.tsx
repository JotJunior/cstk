/**
 * LoadingState — skeleton animado (FR-006).
 * Nunca tela em branco durante carregamento.
 */
interface LoadingStateProps {
  rows?: number;
  /** Mostrar skeleton de cartoes KPI em vez de linhas */
  variant?: 'rows' | 'kpi' | 'table';
}

function SkeletonRow({ width = '100%' }: { width?: string }) {
  return (
    <div className="skeleton-line" style={{ width, marginBottom: 8 }} />
  );
}

export function LoadingState({ rows = 4, variant = 'rows' }: LoadingStateProps) {
  if (variant === 'kpi') {
    return (
      <div className="kpi-grid">
        {Array.from({ length: 4 }).map((_, i) => (
          <div key={i} className="kpi-card">
            <SkeletonRow width="60%" />
            <SkeletonRow width="40%" />
          </div>
        ))}
      </div>
    );
  }

  if (variant === 'table') {
    return (
      <div className="skeleton-card">
        <SkeletonRow width="30%" />
        {Array.from({ length: rows }).map((_, i) => (
          <SkeletonRow key={i} width={`${70 + (i % 3) * 10}%`} />
        ))}
      </div>
    );
  }

  return (
    <div className="skeleton-card">
      {Array.from({ length: rows }).map((_, i) => (
        <SkeletonRow key={i} width={`${60 + (i % 4) * 10}%`} />
      ))}
    </div>
  );
}
