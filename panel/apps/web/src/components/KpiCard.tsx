/**
 * KpiCard — cartao de metrica rico, alinhado ao prototipo (.kpi).
 * Ref: spec.md FR-021; docs/06-ui-ux-design/castk-panel/project/components.jsx
 *
 * Retrocompativel com o uso atual ({label, value, trend, accent}); adiciona
 * unit/footnote/icon/tip/spark do prototipo. `trend` e alias de `footnote`.
 */
import { Icon } from './Icon.js';
import { Sparkline } from './charts.js';

type Accent = 'accent' | 'success' | 'warning' | 'critical';

interface KpiCardProps {
  label: string;
  value: string | number;
  /** Alias historico de footnote. */
  trend?: string;
  footnote?: string;
  unit?: string;
  accent?: Accent | undefined;
  icon?: string;
  /** Tooltip (ex: explicar proxy de custo). */
  tip?: string;
  /** Serie para sparkline (ex: custo ao longo do tempo). */
  spark?: number[];
  sparkColor?: string;
}

/** accent → classe de cartao (apenas accent/warning/critical tem variante). */
const CARD_CLASS: Partial<Record<Accent, string>> = {
  accent: 'accent',
  warning: 'warning',
  critical: 'critical',
};
/** accent → cor do valor (success/critical colorem o numero). */
const VALUE_COLOR: Partial<Record<Accent, string>> = {
  success: 'var(--success)',
  critical: 'var(--critical)',
};

export function KpiCard({
  label, value, trend, footnote, unit, accent, icon, tip, spark, sparkColor,
}: KpiCardProps) {
  const cardVariant = accent ? CARD_CLASS[accent] : undefined;
  const valueColor = accent ? VALUE_COLOR[accent] : undefined;
  const foot = footnote ?? trend;

  return (
    <div className={`kpi${cardVariant ? ' ' + cardVariant : ''}`}>
      <div className="label">
        {icon && <Icon name={icon} size={12} aria-hidden />}
        {label}
        {tip && (
          <span className="tooltip" data-tip={tip} style={{ color: 'var(--text-3)' }}>
            <Icon name="help" size={11} aria-hidden />
          </span>
        )}
      </div>
      <div className="value tnum" style={valueColor ? { color: valueColor } : undefined}>
        {value}{unit && <span className="unit">{unit}</span>}
      </div>
      {foot && (
        <div className="row" style={{ justifyContent: 'space-between' }}>
          <span className="footnote">{foot}</span>
        </div>
      )}
      {spark && spark.length > 1 && (
        <div className="spark"><Sparkline data={spark} color={sparkColor || 'var(--accent)'} width={96} height={28} /></div>
      )}
    </div>
  );
}
