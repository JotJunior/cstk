/**
 * Charts SVG puros — portados do prototipo
 * (docs/06-ui-ux-design/castk-panel/project/components.jsx).
 *
 * Sem dependencia de libs de grafico; SVG inline com tokens de cor.
 */
import { useState } from 'react';
import { fmtNum } from '@/lib/format.js';

// ---------------------------------------------------------------------------
// Sparkline — mini linha de tendencia (usada em KPI de custo)
// ---------------------------------------------------------------------------
export interface SparklineProps {
  data: number[];
  width?: number;
  height?: number;
  color?: string;
  fill?: boolean;
}

export function Sparkline({ data, width = 96, height = 28, color = 'currentColor', fill = true }: SparklineProps) {
  if (!data || data.length < 2) return null;
  const max = Math.max(...data);
  const min = Math.min(...data);
  const rng = max - min || 1;
  const pts = data.map((v, i) => {
    const x = (i / (data.length - 1)) * (width - 2) + 1;
    const y = height - 2 - ((v - min) / rng) * (height - 4);
    return [x, y] as const;
  });
  const path = pts.map((p, i) => (i === 0 ? `M${p[0]},${p[1]}` : `L${p[0]},${p[1]}`)).join(' ');
  const area = `${path} L${width - 1},${height - 1} L1,${height - 1} Z`;
  return (
    <svg width={width} height={height} style={{ color }} aria-hidden>
      {fill && <path className="spark-fill" d={area} />}
      <path className="spark-path" d={path} />
    </svg>
  );
}

// ---------------------------------------------------------------------------
// Donut — distribuicao categorica (ex: mix de modelos)
// ---------------------------------------------------------------------------
export interface DonutDatum { label: string; value: number; color: string; }
export interface DonutProps {
  data: DonutDatum[];
  size?: number;
  thickness?: number;
  centerLabel?: string;
  centerValue?: string;
}

export function Donut({ data, size = 132, thickness = 20, centerLabel, centerValue }: DonutProps) {
  const total = data.reduce((a, d) => a + d.value, 0) || 1;
  const r = (size - thickness) / 2;
  const c = 2 * Math.PI * r;
  let acc = 0;
  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} aria-hidden>
      <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="var(--bg-3)" strokeWidth={thickness} />
      {data.map((d, i) => {
        const frac = d.value / total;
        const dash = `${frac * c} ${c}`;
        const offset = -acc * c;
        acc += frac;
        return (
          <circle
            key={i}
            cx={size / 2} cy={size / 2} r={r}
            fill="none"
            stroke={d.color}
            strokeWidth={thickness}
            strokeDasharray={dash}
            strokeDashoffset={offset}
            transform={`rotate(-90 ${size / 2} ${size / 2})`}
            strokeLinecap="butt"
          />
        );
      })}
      {centerValue && (
        <>
          <text x={size / 2} y={size / 2 - 2} textAnchor="middle" fill="var(--text-0)" fontSize="20" fontWeight="600" fontFamily="var(--font-mono)">{centerValue}</text>
          <text x={size / 2} y={size / 2 + 16} textAnchor="middle" fill="var(--text-2)" fontSize="11">{centerLabel}</text>
        </>
      )}
    </svg>
  );
}

// ---------------------------------------------------------------------------
// BarH — barras horizontais (ex: custo por feature, skills)
// ---------------------------------------------------------------------------
export interface BarHDatum { label: string; value: number; color?: string; }
export interface BarHProps {
  data: BarHDatum[];
  maxLabel?: number;
  valueFmt?: (n: number) => string;
  /** Escala explicita (ex: alinhar varias listas); senao usa o maior do data. */
  max?: number;
}

export function BarH({ data, maxLabel = 160, valueFmt = fmtNum, max: maxProp }: BarHProps) {
  const max = (maxProp && maxProp > 0 ? maxProp : Math.max(...data.map(d => d.value), 0)) || 1;
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
      {data.map((d, i) => (
        <div key={i} style={{ display: 'grid', gridTemplateColumns: `${maxLabel}px 1fr 48px`, gap: 10, alignItems: 'center' }}>
          <div style={{ color: 'var(--text-1)', fontSize: 12, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }} title={d.label}>{d.label}</div>
          <div style={{ height: 14, background: 'var(--bg-2)', borderRadius: 4, position: 'relative', overflow: 'hidden' }}>
            <div style={{ position: 'absolute', inset: 0, width: `${(d.value / max) * 100}%`, background: d.color || 'var(--accent)', borderRadius: 4, opacity: 0.9 }} />
          </div>
          <div className="mono" style={{ textAlign: 'right', fontSize: 12, color: 'var(--text-0)' }}>{valueFmt(d.value)}</div>
        </div>
      ))}
    </div>
  );
}

// ---------------------------------------------------------------------------
// TruncatedBarH — BarH + mecanismo de identificacao da barra "Outros"
// (dashboard-refactor FASE 5, FR-006/007/008; dec-038/1.2.4/1.2.5: clique ou
// toque, nao hover-only — tooltip nao funciona em touch; equivalente por
// teclado via foco + Enter/Espaco).
// ---------------------------------------------------------------------------
export interface TruncatedBarHProps {
  bars: BarHDatum[];
  /** `null` quando nao houve truncamento — sem afordancia de expandir. */
  othersLabel: string | null;
  /** rotulos agregados na barra "Outros" (data-model.md `TruncatedBars`). */
  othersMembers: string[];
  maxLabel?: number;
  valueFmt?: (n: number) => string;
}

export function TruncatedBarH({ bars, othersLabel, othersMembers, maxLabel = 160, valueFmt = fmtNum }: TruncatedBarHProps) {
  const [expanded, setExpanded] = useState(false);
  const toggle = () => setExpanded(v => !v);
  return (
    <div>
      <BarH data={bars} maxLabel={maxLabel} valueFmt={valueFmt} />
      {othersLabel && othersMembers.length > 0 && (
        <>
          <div
            role="button"
            tabIndex={0}
            aria-expanded={expanded}
            onClick={toggle}
            onKeyDown={(e) => {
              if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); toggle(); }
            }}
            className="hover-link"
            style={{ marginTop: 8, fontSize: 11.5, color: 'var(--text-2)', cursor: 'pointer', userSelect: 'none' }}
          >
            {expanded ? '▾' : '▸'} {othersLabel} agrega {othersMembers.length} etapa{othersMembers.length === 1 ? '' : 's'}
          </div>
          {expanded && (
            <div className="mono" style={{ fontSize: 11, color: 'var(--text-3)', marginTop: 4 }}>
              {othersMembers.join(', ')}
            </div>
          )}
        </>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Legend — chips de cor + rotulo (cabecalho de graficos empilhados)
// ---------------------------------------------------------------------------
export interface LegendItem { color: string; label: string; }

export function Legend({ items }: { items: LegendItem[] }) {
  return (
    <div className="legend">
      {items.map((it) => (
        <span className="item" key={it.label}>
          <span className="sw" style={{ background: it.color }} />
          {it.label}
        </span>
      ))}
    </div>
  );
}

// ---------------------------------------------------------------------------
// StackedBars — barras empilhadas por categoria ao longo de um eixo X
// (ex: incidentes por dia/tipo, pass/fail no tempo). Portado do prototipo.
// ---------------------------------------------------------------------------
export interface StackedBarsProps {
  /** Cada linha tem o rotulo do eixo X (xKey) + uma chave numerica por serie. */
  data: Record<string, number | string>[];
  keys: string[];
  colors: string[];
  height?: number;
  /** Chave do rotulo do eixo X em cada linha (default 'd'). */
  xKey?: string;
}

export function StackedBars({ data, keys, colors, height = 160, xKey = 'd' }: StackedBarsProps) {
  const W = 800;
  const H = height;
  const padT = 10, padB = 24, padL = 28, padR = 12;
  const innerW = W - padL - padR;
  const innerH = H - padT - padB;
  const valOf = (row: Record<string, number | string>, k: string): number =>
    typeof row[k] === 'number' ? (row[k] as number) : 0;
  const max = Math.max(...data.map(d => keys.reduce((a, k) => a + valOf(d, k), 0)), 0) || 1;
  const bw = data.length ? innerW / data.length : innerW;
  const yAt = (v: number): number => padT + innerH - (v / max) * innerH;
  return (
    <svg width="100%" height={H} viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none" aria-hidden>
      {[0, 0.25, 0.5, 0.75, 1].map((f, i) => (
        <line key={i} x1={padL} x2={W - padR} y1={padT + innerH * (1 - f)} y2={padT + innerH * (1 - f)} stroke="var(--border)" strokeWidth="0.5" />
      ))}
      {data.map((d, i) => {
        let acc = 0;
        const x = padL + i * bw + 2;
        const xLabel = String(d[xKey] ?? '');
        return (
          <g key={i}>
            {keys.map((k, ki) => {
              const v = valOf(d, k);
              if (!v) return null;
              const y0 = yAt(acc);
              const y1 = yAt(acc + v);
              acc += v;
              return <rect key={k} x={x} y={y1} width={Math.max(0, bw - 4)} height={Math.max(0, y0 - y1)} fill={colors[ki]} rx="1" />;
            })}
            {i % 2 === 0 && (
              <text x={x + (bw - 4) / 2} y={H - 6} fontSize="9.5" textAnchor="middle" fill="var(--text-3)" fontFamily="var(--font-mono)">{xLabel}</text>
            )}
          </g>
        );
      })}
    </svg>
  );
}

// ---------------------------------------------------------------------------
// Histogram — distribuicao de valores numericos em bins (ex: latencia humana)
// ---------------------------------------------------------------------------
export interface HistogramProps {
  values: number[];
  bins?: number;
  height?: number;
  color?: string;
  /** Sufixo do rotulo do eixo X (ex: 's' para segundos). */
  unit?: string;
}

export function Histogram({ values, bins = 8, height = 140, color = 'var(--info)', unit = '' }: HistogramProps) {
  if (!values.length) {
    return (
      <div style={{ height, display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--text-3)', fontSize: 12 }}>
        Sem dados suficientes
      </div>
    );
  }
  const max = Math.max(...values);
  const min = Math.min(...values);
  const rng = max - min || 1;
  const step = rng / bins;
  const counts = new Array<number>(bins).fill(0);
  values.forEach(v => {
    let i = Math.floor((v - min) / step);
    if (i >= bins) i = bins - 1;
    if (i < 0) i = 0;
    counts[i] = (counts[i] ?? 0) + 1;
  });
  const cmax = Math.max(...counts) || 1;
  const W = 600;
  const H = height;
  const padT = 8, padB = 22, padL = 8, padR = 8;
  const innerW = W - padL - padR;
  const innerH = H - padT - padB;
  const bw = innerW / bins;
  return (
    <svg width="100%" height={H} viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none" aria-hidden>
      {counts.map((c, i) => {
        const h = (c / cmax) * innerH;
        return <rect key={i} x={padL + i * bw + 1} y={padT + innerH - h} width={bw - 2} height={h} fill={color} opacity="0.7" rx="1" />;
      })}
      {counts.map((_, i) => (i % 2 === 0 ? (
        <text key={`x${i}`} x={padL + i * bw + bw / 2} y={H - 6} fontSize="9.5" textAnchor="middle" fill="var(--text-3)" fontFamily="var(--font-mono)">
          {Math.round(min + i * step)}{unit}
        </text>
      ) : null))}
    </svg>
  );
}

// ---------------------------------------------------------------------------
// ScatterChart — dispersao X×Y (ex: profundidade × subagentes por execucao)
// ---------------------------------------------------------------------------
export interface ScatterDatum { x: number; y: number; color?: string; label?: string; }
export interface ScatterChartProps {
  data: ScatterDatum[];
  height?: number;
  xLabel?: string;
  yLabel?: string;
}

export function ScatterChart({ data, height = 180, xLabel = '', yLabel = '' }: ScatterChartProps) {
  const W = 360, padT = 14, padB = 28, padL = 30, padR = 14;
  const H = height;
  const innerW = W - padL - padR;
  const innerH = H - padT - padB;
  const xMax = Math.max(...data.map(d => d.x), 5);
  const yMax = Math.max(...data.map(d => d.y), 12);
  const xAt = (v: number): number => padL + (v / xMax) * innerW;
  const yAt = (v: number): number => padT + innerH - (v / yMax) * innerH;
  return (
    <svg width="100%" height={H} viewBox={`0 0 ${W} ${H}`} aria-hidden>
      {[0, 0.5, 1].map((f, i) => (
        <line key={i} x1={padL} x2={W - padR} y1={padT + innerH * (1 - f)} y2={padT + innerH * (1 - f)} stroke="var(--border)" strokeWidth="0.5" />
      ))}
      {data.map((d, i) => (
        <circle key={i} cx={xAt(d.x)} cy={yAt(d.y)} r="5" fill={d.color ?? 'var(--accent)'} opacity="0.85" />
      ))}
      {xLabel && <text x={padL} y={H - 8} fontSize="9.5" fill="var(--text-3)" fontFamily="var(--font-mono)">{xLabel} →</text>}
      {yLabel && <text x={4} y={padT + 6} fontSize="9.5" fill="var(--text-3)" fontFamily="var(--font-mono)">{yLabel}</text>}
    </svg>
  );
}
