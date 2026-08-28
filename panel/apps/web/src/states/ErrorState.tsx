/**
 * ErrorState — mensagem de erro amigavel, sem stack trace (FR-006).
 */
interface ErrorStateProps {
  message?: string | undefined;
  /** Detalhe tecnico opcional — nunca exibe stack trace */
  detail?: string | undefined;
}

export function ErrorState({
  message = 'Ocorreu um erro ao carregar os dados.',
  detail,
}: ErrorStateProps) {
  return (
    <div className="error-state" role="alert">
      <svg
        width={32}
        height={32}
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth={1.5}
        strokeLinecap="round"
        strokeLinejoin="round"
        aria-hidden
        style={{ color: 'var(--critical)' }}
      >
        <circle cx="12" cy="12" r="9" />
        <line x1="12" y1="8" x2="12" y2="12" />
        <line x1="12" y1="16" x2="12.01" y2="16" />
      </svg>
      <div className="err-title">{message}</div>
      {detail && (
        <div className="err-sub" style={{ fontFamily: 'var(--font-mono)', fontSize: 11 }}>
          {/* detail e texto controlado pelo app, nao input do usuario */}
          {detail}
        </div>
      )}
    </div>
  );
}
