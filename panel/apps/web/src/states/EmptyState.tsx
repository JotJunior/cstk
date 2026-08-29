/**
 * EmptyState — "Nenhum dado disponivel" sem erro (FR-006).
 * Distinto de ErrorState.
 */
interface EmptyStateProps {
  title?: string;
  subtitle?: string;
}

export function EmptyState({
  title = 'Nenhum dado disponivel',
  subtitle = 'Nao ha registros para exibir.',
}: EmptyStateProps) {
  return (
    <div className="empty-state" role="status">
      <svg
        className="empty-icon"
        width={32}
        height={32}
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth={1.5}
        strokeLinecap="round"
        strokeLinejoin="round"
        aria-hidden
        style={{ color: 'var(--text-3)' }}
      >
        <circle cx="12" cy="12" r="9" />
        <line x1="9" y1="12" x2="15" y2="12" />
      </svg>
      <div className="empty-title">{title}</div>
      <div className="empty-sub">{subtitle}</div>
    </div>
  );
}
