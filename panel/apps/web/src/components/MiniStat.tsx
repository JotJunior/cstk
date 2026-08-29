/**
 * MiniStat — par rotulo/valor compacto (.mstat do prototipo).
 */
import type { CSSProperties, ReactNode } from 'react';

interface MiniStatProps {
  label: string;
  value: ReactNode;
  valueColor?: string;
  align?: 'start' | 'end';
}

export function MiniStat({ label, value, valueColor, align = 'start' }: MiniStatProps) {
  const style: CSSProperties = { alignItems: align === 'end' ? 'flex-end' : 'flex-start' };
  return (
    <div className="mstat" style={style}>
      <span className="label">{label}</span>
      <span className="value" style={valueColor ? { color: valueColor } : undefined}>{value}</span>
    </div>
  );
}
