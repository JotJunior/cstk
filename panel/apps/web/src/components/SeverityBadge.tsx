/**
 * SeverityBadge — severidade de alerta (critical/warning/info).
 * Portado do prototipo; reusa as cores semanticas de badge.
 */
type Severity = 'critical' | 'warning' | 'info' | string | null;

const INFO = { cls: 'em_andamento', label: 'info' };
const MAP: Record<string, { cls: string; label: string }> = {
  critical: { cls: 'abortada', label: 'critico' },
  warning: { cls: 'aguardando_humano', label: 'atencao' },
  info: INFO,
};

export function SeverityBadge({ severity }: { severity: Severity }) {
  if (!severity) return <span style={{ color: 'var(--text-3)' }}>—</span>;
  const m = MAP[severity] ?? INFO;
  return (
    <span className={`badge ${m.cls}`}>
      <span className="dot" aria-hidden />
      {m.label}
    </span>
  );
}
