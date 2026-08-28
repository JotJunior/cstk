/**
 * BudgetMini — barra compacta consumido/threshold com overflow visual.
 * Portado do prototipo. Quando valor/threshold ausentes (ex: alerta circular),
 * renderiza "—" (honestidade de metrica — sem inventar dado).
 */
import { fmtNum } from '@/lib/format.js';

interface BudgetMiniProps {
  value: number | null | undefined;
  threshold: number | null | undefined;
  unit?: string;
}

export function BudgetMini({ value, threshold, unit = '' }: BudgetMiniProps) {
  if (value == null || threshold == null || threshold <= 0) {
    return <span style={{ color: 'var(--text-3)' }}>—</span>;
  }
  const pct = (value / threshold) * 100;
  const over = value > threshold;
  return (
    <div style={{ minWidth: 120 }}>
      <div className="row" style={{ justifyContent: 'space-between', fontSize: 11.5 }}>
        <span className="mono" style={{ color: over ? 'var(--critical)' : 'var(--text-0)' }}>{fmtNum(value)}{unit}</span>
        <span className="mono muted">/ {fmtNum(threshold)}{unit}</span>
      </div>
      <div style={{ height: 5, background: 'var(--bg-3)', borderRadius: 3, marginTop: 4, overflow: 'hidden', position: 'relative' }}>
        <div style={{ position: 'absolute', inset: 0, width: `${Math.min(pct, 100)}%`, background: over ? 'var(--critical)' : 'var(--warning)', borderRadius: 3 }} />
      </div>
      <div className="row" style={{ justifyContent: 'space-between', marginTop: 4, fontSize: 10.5 }}>
        <span className="muted-2">consumido</span>
        <span className="mono" style={{ color: over ? 'var(--critical)' : 'var(--text-1)' }}>{over ? '+' : ''}{(pct - 100) | 0}%</span>
      </div>
    </div>
  );
}
