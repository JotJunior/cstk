// Reusable UI primitives + small charts/components for cstk-panel

const { useState, useEffect, useMemo, useRef } = React;

// ---------- Icons (inline SVG, feather-style, current-color) ----------
const Icon = ({ name, size = 16, ...rest }) => {
  const s = size;
  const props = { width: s, height: s, viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', strokeWidth: 1.8, strokeLinecap: 'round', strokeLinejoin: 'round', ...rest };
  switch (name) {
    case 'home':         return <svg {...props}><path d="M3 12 12 3l9 9"/><path d="M5 10v10h14V10"/></svg>;
    case 'folder':       return <svg {...props}><path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/></svg>;
    case 'git-branch':   return <svg {...props}><circle cx="6" cy="3" r="2"/><circle cx="6" cy="18" r="2"/><circle cx="18" cy="6" r="2"/><path d="M6 5v8a4 4 0 0 0 4 4h2"/><path d="M18 8v2a4 4 0 0 1-4 4h-4"/></svg>;
    case 'activity':     return <svg {...props}><path d="M22 12h-4l-3 9-6-18-3 9H2"/></svg>;
    case 'alert':        return <svg {...props}><path d="M10.3 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>;
    case 'bar':          return <svg {...props}><line x1="4" y1="20" x2="4" y2="10"/><line x1="10" y1="20" x2="10" y2="4"/><line x1="16" y1="20" x2="16" y2="14"/><line x1="22" y1="20" x2="2" y2="20"/></svg>;
    case 'check':        return <svg {...props}><rect x="3" y="3" width="18" height="18" rx="3"/><path d="m8 12 3 3 5-6"/></svg>;
    case 'zap':          return <svg {...props}><polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/></svg>;
    case 'search':       return <svg {...props}><circle cx="11" cy="11" r="7"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>;
    case 'sun':          return <svg {...props}><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41"/></svg>;
    case 'moon':         return <svg {...props}><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>;
    case 'chevron-down': return <svg {...props}><polyline points="6 9 12 15 18 9"/></svg>;
    case 'chevron-right':return <svg {...props}><polyline points="9 6 15 12 9 18"/></svg>;
    case 'chevron-up':   return <svg {...props}><polyline points="6 15 12 9 18 15"/></svg>;
    case 'external':     return <svg {...props}><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/><polyline points="15 3 21 3 21 9"/><line x1="10" y1="14" x2="21" y2="3"/></svg>;
    case 'filter':       return <svg {...props}><polygon points="22 3 2 3 10 12.46 10 19 14 21 14 12.46 22 3"/></svg>;
    case 'plus':         return <svg {...props}><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>;
    case 'x':            return <svg {...props}><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>;
    case 'database':     return <svg {...props}><ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M3 5v6c0 1.66 4 3 9 3s9-1.34 9-3V5"/><path d="M3 11v6c0 1.66 4 3 9 3s9-1.34 9-3v-6"/></svg>;
    case 'clock':        return <svg {...props}><circle cx="12" cy="12" r="9"/><polyline points="12 7 12 12 16 14"/></svg>;
    case 'lock':         return <svg {...props}><rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/></svg>;
    case 'retry':        return <svg {...props}><polyline points="23 4 23 10 17 10"/><path d="M20.49 15A9 9 0 1 1 18 5.3L23 10"/></svg>;
    case 'cancel':       return <svg {...props}><circle cx="12" cy="12" r="9"/><line x1="15" y1="9" x2="9" y2="15"/><line x1="9" y1="9" x2="15" y2="15"/></svg>;
    case 'pause':        return <svg {...props}><rect x="6" y="4" width="4" height="16"/><rect x="14" y="4" width="4" height="16"/></svg>;
    case 'wait':         return <svg {...props}><circle cx="12" cy="12" r="9"/><polyline points="12 6 12 12 16 14"/></svg>;
    case 'cpu':          return <svg {...props}><rect x="4" y="4" width="16" height="16" rx="2"/><rect x="9" y="9" width="6" height="6"/><line x1="9" y1="1" x2="9" y2="4"/><line x1="15" y1="1" x2="15" y2="4"/><line x1="9" y1="20" x2="9" y2="23"/><line x1="15" y1="20" x2="15" y2="23"/><line x1="20" y1="9" x2="23" y2="9"/><line x1="20" y1="14" x2="23" y2="14"/><line x1="1" y1="9" x2="4" y2="9"/><line x1="1" y1="14" x2="4" y2="14"/></svg>;
    case 'spark':        return <svg {...props}><path d="M3 12c3 0 3-6 6-6s3 6 6 6 3-4 6-4"/></svg>;
    case 'users':        return <svg {...props}><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>;
    case 'tree':         return <svg {...props}><circle cx="12" cy="4" r="2"/><circle cx="5" cy="20" r="2"/><circle cx="19" cy="20" r="2"/><circle cx="12" cy="12" r="2"/><path d="M12 6v4M12 14l-6 4M12 14l6 4"/></svg>;
    case 'eye':          return <svg {...props}><path d="M1 12s4-7 11-7 11 7 11 7-4 7-11 7S1 12 1 12z"/><circle cx="12" cy="12" r="3"/></svg>;
    case 'doc':          return <svg {...props}><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="9" y1="13" x2="15" y2="13"/><line x1="9" y1="17" x2="15" y2="17"/></svg>;
    case 'bolt':         return <svg {...props}><polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/></svg>;
    case 'arrow-up':     return <svg {...props}><line x1="12" y1="19" x2="12" y2="5"/><polyline points="5 12 12 5 19 12"/></svg>;
    case 'arrow-down':   return <svg {...props}><line x1="12" y1="5" x2="12" y2="19"/><polyline points="19 12 12 19 5 12"/></svg>;
    case 'flame':        return <svg {...props}><path d="M8.5 14.5A2.5 2.5 0 0 0 11 17h2a4 4 0 0 0 4-4 6 6 0 0 0-6-6c-3.31 0-6 2.69-6 6 0 1.66.67 3.16 1.76 4.24"/><path d="M12 2c1 3 4 5 4 9"/></svg>;
    case 'package':      return <svg {...props}><path d="m12 2 8 4v12l-8 4-8-4V6z"/><path d="M4 6l8 4 8-4"/><line x1="12" y1="10" x2="12" y2="22"/></svg>;
    case 'menu':         return <svg {...props}><line x1="3" y1="12" x2="21" y2="12"/><line x1="3" y1="6" x2="21" y2="6"/><line x1="3" y1="18" x2="21" y2="18"/></svg>;
    case 'sort':         return <svg {...props}><polyline points="8 4 8 20"/><polyline points="5 17 8 20 11 17"/><polyline points="16 20 16 4"/><polyline points="13 7 16 4 19 7"/></svg>;
    case 'help':         return <svg {...props}><circle cx="12" cy="12" r="9"/><path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>;
    case 'globe':        return <svg {...props}><circle cx="12" cy="12" r="9"/><line x1="3" y1="12" x2="21" y2="12"/><path d="M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/></svg>;
    default: return <svg {...props}><circle cx="12" cy="12" r="9"/></svg>;
  }
};

// ---------- Format helpers ----------
const fmtNum = (n) => {
  if (n == null) return '—';
  if (n >= 10000) return (n/1000).toFixed(1).replace('.0','') + 'k';
  return new Intl.NumberFormat('pt-BR').format(n);
};
const fmtDur = (sec) => {
  if (sec == null || sec < 0) return '—';
  if (sec < 60) return `${sec}s`;
  const m = Math.floor(sec / 60);
  const s = sec % 60;
  if (m < 60) return s ? `${m}m ${String(s).padStart(2,'0')}s` : `${m}m`;
  const h = Math.floor(m / 60);
  const rm = m % 60;
  return `${h}h ${String(rm).padStart(2,'0')}m`;
};
const fmtPct = (v, digits=0) => `${(v*100).toFixed(digits)}%`;
const fmtTimestamp = (iso) => {
  if (!iso) return '—';
  const d = new Date(iso);
  return d.toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });
};
const fmtRelative = (iso) => {
  if (!iso) return '—';
  const diff = (Date.now() - new Date(iso).getTime()) / 1000;
  if (diff < 60) return 'agora';
  if (diff < 3600) return `há ${Math.floor(diff/60)}m`;
  if (diff < 86400) return `há ${Math.floor(diff/3600)}h`;
  return `há ${Math.floor(diff/86400)}d`;
};

// ---------- Badges ----------
const STATUS_LABEL = {
  em_andamento: 'em andamento',
  aguardando_humano: 'aguardando humano',
  concluida: 'concluída',
  abortada: 'abortada',
};
const StatusBadge = ({ status }) => (
  <span className={`badge ${status}`}><span className="dot"/>{STATUS_LABEL[status] || status}</span>
);

const ScoreChip = ({ score }) => (
  <span className={`score s${score}`} title={`score ${score} — ${['pausa/humano','pausa','decide por contexto','decide com evidência'][score]}`}>{score}</span>
);

const OutcomePill = ({ outcome }) => (
  <span className={`pill ${outcome}`}>
    {outcome === 'pass' ? '✓ pass' : '✕ fail'}
  </span>
);

const SeverityBadge = ({ severity }) => {
  const map = { critical: { c:'critical', t:'crítico' }, warning: { c:'aguardando_humano', t:'atenção' }, info: { c:'em_andamento', t:'info' } };
  const m = map[severity] || map.info;
  return <span className={`badge ${m.c}`}><span className="dot"/>{m.t}</span>;
};

// ---------- Pipeline progress ----------
const PipelineProgress = ({ etapa, status, labeled = false }) => {
  const stages = window.CSTKData.SDD_STAGES;
  const idx = stages.indexOf(etapa);
  if (labeled) {
    return (
      <div className="pipeline-labeled">
        {stages.map((st, i) => (
          <div key={st} className={`stage ${i < idx ? 'done' : ''} ${i === idx && status !== 'concluida' && status !== 'abortada' ? 'current' : ''} ${i === idx && status === 'concluida' ? 'done' : ''}`}>
            <div className="bar"/>
            <div className="label" style={{whiteSpace:'nowrap',overflow:'hidden',textOverflow:'ellipsis'}}>{st}</div>
          </div>
        ))}
      </div>
    );
  }
  return (
    <div className="pipeline">
      {stages.map((st, i) => {
        let cls = '';
        if (status === 'abortada' && i >= idx) cls = 'aborted';
        else if (status === 'concluida') cls = 'done';
        else if (i < idx) cls = 'done';
        else if (i === idx) cls = 'current';
        return <div key={st} className={`step ${cls}`} title={st}/>;
      })}
    </div>
  );
};

// ---------- Sparkline ----------
const Sparkline = ({ data, width = 96, height = 28, color = 'currentColor', fill = true }) => {
  if (!data || !data.length) return null;
  const values = data.map(d => typeof d === 'number' ? d : d.v);
  const max = Math.max(...values);
  const min = Math.min(...values);
  const rng = (max - min) || 1;
  const pts = values.map((v, i) => {
    const x = (i / (values.length - 1)) * (width - 2) + 1;
    const y = height - 2 - ((v - min) / rng) * (height - 4);
    return [x, y];
  });
  const path = pts.map((p, i) => (i === 0 ? `M${p[0]},${p[1]}` : `L${p[0]},${p[1]}`)).join(' ');
  const area = `${path} L${width-1},${height-1} L1,${height-1} Z`;
  return (
    <svg width={width} height={height} style={{color}}>
      {fill && <path className="spark-fill" d={area}/>}
      <path className="spark-path" d={path}/>
    </svg>
  );
};

// ---------- KPI card ----------
const KpiCard = ({ label, value, unit, delta, deltaDir, footnote, spark, sparkColor, accent, critical, warning, icon, tip }) => {
  let cls = 'kpi';
  if (accent) cls += ' accent';
  if (critical) cls += ' critical';
  if (warning) cls += ' warning';
  return (
    <div className={cls}>
      <div className="label">
        {icon && <Icon name={icon} size={12}/>}
        {label}
        {tip && <span className="tooltip" data-tip={tip} style={{color:'var(--text-3)'}}><Icon name="help" size={11}/></span>}
      </div>
      <div className="value tnum">{value}{unit && <span className="unit">{unit}</span>}</div>
      <div className="row" style={{justifyContent:'space-between'}}>
        {delta != null ? (
          <div className={`delta ${deltaDir === 'down' ? 'down' : 'up'}`}>
            <Icon name={deltaDir === 'down' ? 'arrow-down' : 'arrow-up'} size={11} style={{verticalAlign:'middle'}}/>{' '}{delta}
          </div>
        ) : <div/>}
        {footnote && <span className="footnote">{footnote}</span>}
      </div>
      {spark && <div className="spark"><Sparkline data={spark} color={sparkColor || 'var(--accent)'} width={96} height={28}/></div>}
    </div>
  );
};

// ---------- Donut ----------
const Donut = ({ data, size = 140, thickness = 18, centerLabel, centerValue }) => {
  const total = data.reduce((a, d) => a + d.value, 0) || 1;
  const r = (size - thickness) / 2;
  const c = 2 * Math.PI * r;
  let acc = 0;
  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`}>
      <circle cx={size/2} cy={size/2} r={r} fill="none" stroke="var(--bg-3)" strokeWidth={thickness}/>
      {data.map((d, i) => {
        const frac = d.value / total;
        const dash = `${frac * c} ${c}`;
        const offset = -acc * c;
        acc += frac;
        return (
          <circle
            key={i}
            cx={size/2} cy={size/2} r={r}
            fill="none"
            stroke={d.color}
            strokeWidth={thickness}
            strokeDasharray={dash}
            strokeDashoffset={offset}
            transform={`rotate(-90 ${size/2} ${size/2})`}
            strokeLinecap="butt"
          />
        );
      })}
      {centerValue && (
        <>
          <text x={size/2} y={size/2 - 2} textAnchor="middle" fill="var(--text-0)" fontSize="20" fontWeight="600" fontFamily="var(--font-mono)">{centerValue}</text>
          <text x={size/2} y={size/2 + 16} textAnchor="middle" fill="var(--text-2)" fontSize="11">{centerLabel}</text>
        </>
      )}
    </svg>
  );
};

// ---------- Horizontal Bars ----------
const BarH = ({ data, maxLabel = 160, valueFmt = fmtNum, height = 'auto' }) => {
  const max = Math.max(...data.map(d => d.value)) || 1;
  return (
    <div style={{display:'flex', flexDirection:'column', gap: 8}}>
      {data.map((d, i) => (
        <div key={i} style={{display:'grid', gridTemplateColumns:`${maxLabel}px 1fr 48px`, gap: 10, alignItems:'center'}}>
          <div style={{color:'var(--text-1)', fontSize:12, whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'}} title={d.label}>{d.label}</div>
          <div style={{height: 14, background:'var(--bg-2)', borderRadius:4, position:'relative', overflow:'hidden'}}>
            <div style={{position:'absolute', inset: 0, width: `${(d.value/max)*100}%`, background: d.color || 'var(--accent)', borderRadius:4, opacity: 0.9}}/>
          </div>
          <div className="mono" style={{textAlign:'right', fontSize:12, color:'var(--text-0)'}}>{valueFmt(d.value)}</div>
        </div>
      ))}
    </div>
  );
};

// ---------- Vertical bars / column chart ----------
const Columns = ({ data, height = 140, color = 'var(--accent)', yFmt = fmtNum, accentLast }) => {
  const max = Math.max(...data.map(d => d.v)) || 1;
  const W = 600;
  const H = height;
  const padT = 10, padB = 22, padL = 8, padR = 8;
  const innerW = W - padL - padR;
  const innerH = H - padT - padB;
  const bw = innerW / data.length;
  return (
    <svg width="100%" height={H} viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none">
      {[0.25, 0.5, 0.75, 1].map((f, i) => (
        <line key={i} x1={padL} x2={W-padR} y1={padT + innerH * (1-f)} y2={padT + innerH * (1-f)} stroke="var(--border)" strokeWidth="0.5"/>
      ))}
      {data.map((d, i) => {
        const h = (d.v / max) * innerH;
        const x = padL + i * bw + 2;
        const y = padT + innerH - h;
        const fill = accentLast && i === data.length - 1 ? 'var(--accent)' : (color || 'var(--info)');
        return (
          <g key={i}>
            <rect x={x} y={y} width={bw - 4} height={h} fill={fill} opacity={accentLast && i === data.length-1 ? 1 : 0.7} rx="2"/>
            <text x={x + (bw-4)/2} y={H-6} fontSize="9.5" textAnchor="middle" fill="var(--text-3)" fontFamily="var(--font-mono)">{d.d}</text>
          </g>
        );
      })}
    </svg>
  );
};

// ---------- Line/Area chart ----------
const AreaChart = ({ data, height = 180, color = 'var(--accent)', yFmt = fmtNum, hoverable = true }) => {
  const W = 800;
  const H = height;
  const padT = 14, padB = 26, padL = 36, padR = 14;
  const innerW = W - padL - padR;
  const innerH = H - padT - padB;
  const vals = data.map(d => d.v);
  const max = Math.max(...vals) || 1;
  const min = 0;
  const xAt = i => padL + (i / (data.length - 1)) * innerW;
  const yAt = v => padT + innerH - ((v - min) / (max - min)) * innerH;
  const path = data.map((d, i) => `${i === 0 ? 'M' : 'L'}${xAt(i)},${yAt(d.v)}`).join(' ');
  const area = `${path} L${xAt(data.length-1)},${padT+innerH} L${padL},${padT+innerH} Z`;
  const yTicks = [0, 0.25, 0.5, 0.75, 1].map(f => Math.round(max * f));
  return (
    <svg width="100%" height={H} viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none">
      {yTicks.map((t, i) => (
        <g key={i}>
          <line x1={padL} x2={W-padR} y1={yAt(t)} y2={yAt(t)} stroke="var(--border)" strokeWidth="0.5"/>
          <text x={padL - 6} y={yAt(t) + 3} fontSize="10" textAnchor="end" fill="var(--text-3)" fontFamily="var(--font-mono)">{yFmt(t)}</text>
        </g>
      ))}
      <path d={area} fill={color} opacity="0.16"/>
      <path d={path} fill="none" stroke={color} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"/>
      {data.map((d, i) => (
        <circle key={i} cx={xAt(i)} cy={yAt(d.v)} r="2.5" fill={color}/>
      ))}
      {data.map((d, i) => i % Math.ceil(data.length / 7) === 0 && (
        <text key={`x${i}`} x={xAt(i)} y={H - 8} fontSize="10" textAnchor="middle" fill="var(--text-3)" fontFamily="var(--font-mono)">{d.d}</text>
      ))}
    </svg>
  );
};

// ---------- Stacked bars (incidents over time) ----------
const StackedBars = ({ data, keys, colors, height = 160 }) => {
  const W = 800;
  const H = height;
  const padT = 10, padB = 24, padL = 28, padR = 12;
  const innerW = W - padL - padR;
  const innerH = H - padT - padB;
  const max = Math.max(...data.map(d => keys.reduce((a, k) => a + (d[k] || 0), 0))) || 1;
  const bw = innerW / data.length;
  const yAt = v => padT + innerH - (v / max) * innerH;
  return (
    <svg width="100%" height={H} viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none">
      {[0, 0.25, 0.5, 0.75, 1].map((f, i) => (
        <line key={i} x1={padL} x2={W-padR} y1={padT + innerH*(1-f)} y2={padT + innerH*(1-f)} stroke="var(--border)" strokeWidth="0.5"/>
      ))}
      {data.map((d, i) => {
        let acc = 0;
        const x = padL + i*bw + 2;
        return (
          <g key={i}>
            {keys.map((k, ki) => {
              const v = d[k] || 0;
              if (!v) return null;
              const y0 = yAt(acc);
              const y1 = yAt(acc + v);
              acc += v;
              return <rect key={k} x={x} y={y1} width={bw-4} height={y0 - y1} fill={colors[ki]} rx="1"/>;
            })}
            {i % 2 === 0 && <text x={x + (bw-4)/2} y={H-6} fontSize="9.5" textAnchor="middle" fill="var(--text-3)" fontFamily="var(--font-mono)">{d.d}</text>}
          </g>
        );
      })}
    </svg>
  );
};

// ---------- Histogram ----------
const Histogram = ({ values, bins = 8, height = 140, color = 'var(--info)' }) => {
  const max = Math.max(...values);
  const min = Math.min(...values);
  const rng = max - min || 1;
  const step = rng / bins;
  const counts = new Array(bins).fill(0);
  values.forEach(v => {
    let i = Math.floor((v - min) / step);
    if (i >= bins) i = bins - 1;
    counts[i]++;
  });
  const cmax = Math.max(...counts) || 1;
  const W = 600;
  const H = height;
  const padT = 8, padB = 22, padL = 8, padR = 8;
  const innerW = W - padL - padR;
  const innerH = H - padT - padB;
  const bw = innerW / bins;
  return (
    <svg width="100%" height={H} viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none">
      {counts.map((c, i) => {
        const h = (c / cmax) * innerH;
        return (
          <g key={i}>
            <rect x={padL + i*bw + 1} y={padT + innerH - h} width={bw-2} height={h} fill={color} opacity="0.7" rx="1"/>
          </g>
        );
      })}
      {counts.map((c, i) => i % 2 === 0 && (
        <text key={`x${i}`} x={padL + i*bw + bw/2} y={H-6} fontSize="9.5" textAnchor="middle" fill="var(--text-3)" fontFamily="var(--font-mono)">
          {Math.round(min + i*step)}s
        </text>
      ))}
    </svg>
  );
};

// ---------- Gauge ----------
const Gauge = ({ value, max, color, label, suffix = '' }) => {
  const pct = Math.min(value / max, 1.4);
  const over = value > max;
  const size = 100;
  const r = 40;
  const c = Math.PI * r; // half circle
  const dashWarn = `${Math.min(1, pct) * c} ${c}`;
  const dashOver = over ? `${Math.min(1, (pct - 1) * 2.5) * c} ${c}` : '';
  return (
    <div style={{display:'flex', flexDirection:'column', alignItems:'center'}}>
      <svg width={size} height={size/2 + 16} viewBox={`0 0 ${size} ${size/2 + 16}`}>
        <path d={`M 10 ${size/2} A ${r} ${r} 0 0 1 ${size-10} ${size/2}`}
          fill="none" stroke="var(--bg-3)" strokeWidth="8" strokeLinecap="round"/>
        <path d={`M 10 ${size/2} A ${r} ${r} 0 0 1 ${size-10} ${size/2}`}
          fill="none" stroke={over ? 'var(--critical)' : (color || 'var(--accent)')} strokeWidth="8"
          strokeLinecap="round" strokeDasharray={dashWarn} pathLength={c}/>
        <text x={size/2} y={size/2 + 2} textAnchor="middle" fill="var(--text-0)" fontSize="14" fontFamily="var(--font-mono)" fontWeight="600">
          {fmtNum(value)}{suffix}
        </text>
        <text x={size/2} y={size/2 + 16} textAnchor="middle" fill="var(--text-3)" fontSize="9" fontFamily="var(--font-mono)">/ {fmtNum(max)}{suffix}</text>
      </svg>
      {label && <div style={{fontSize:11, color:'var(--text-2)', marginTop:-2}}>{label}</div>}
    </div>
  );
};

// ---------- Funnel ----------
const FunnelChart = ({ data }) => {
  const max = Math.max(...data.map(d => d.count)) || 1;
  return (
    <div className="funnel">
      {data.map((d, i) => (
        <div className="funnel-row" key={i}>
          <span className="label">{d.label}</span>
          <div className="bar"><div className="bar-fill" style={{width: `${(d.count/max)*100}%`, opacity: 0.4 + (d.count/max)*0.6}}/></div>
          <span className="count">{d.count}</span>
        </div>
      ))}
    </div>
  );
};

// ---------- Legend ----------
const Legend = ({ items }) => (
  <div className="legend">
    {items.map((it, i) => (
      <span key={i} className="item">
        <span className="sw" style={{background: it.color}}/>{it.label}
      </span>
    ))}
  </div>
);

// ---------- Empty/error states ----------
const EmptyState = ({ icon = 'database', title, hint, action }) => (
  <div style={{padding: 40, textAlign: 'center', color: 'var(--text-2)', display:'flex', flexDirection:'column', alignItems:'center', gap:8}}>
    <div style={{color:'var(--text-3)', background:'var(--bg-2)', width:42, height:42, borderRadius:'50%', display:'grid', placeItems:'center', marginBottom: 6}}>
      <Icon name={icon} size={18}/>
    </div>
    <div style={{color:'var(--text-1)', fontSize: 13.5, fontWeight: 500}}>{title}</div>
    {hint && <div style={{fontSize:12, maxWidth: 360}}>{hint}</div>}
    {action}
  </div>
);

const DegradedBanner = ({ onClose }) => (
  <div className="degraded-banner">
    <Icon name="alert" size={14}/>
    <span>Índice de conhecimento <strong>parcialmente disponível</strong> — algumas execuções podem estar incompletas. Reconstrua com <span className="mono" style={{background:'rgba(0,0,0,0.2)', padding:'1px 6px', borderRadius:3, fontSize:11}}>cstk --reindex</span>.</span>
    <button className="close" onClick={onClose}><Icon name="x" size={14}/></button>
  </div>
);

// ---------- Provenance crumb ----------
const Provenance = ({ project, feature, execucao_id, wave, navigate }) => (
  <span className="prov">
    <a onClick={() => navigate(`#/projects/${project}`)}>{project}</a>
    <span className="sep">/</span>
    <a onClick={() => navigate(`#/features/${feature}`)}>{feature}</a>
    {execucao_id && (<><span className="sep">/</span><a onClick={() => navigate(`#/executions/${feature}`)}>{execucao_id.slice(0, 24)}…</a></>)}
    {wave && (<><span className="sep">/</span><a onClick={() => navigate(`#/executions/${feature}?wave=${wave}`)}>{wave}</a></>)}
  </span>
);

// ---------- Budget gauge (compact) ----------
const BudgetMini = ({ value, threshold, unit }) => {
  const pct = (value / threshold) * 100;
  const over = value > threshold;
  return (
    <div style={{minWidth: 120}}>
      <div className="row" style={{justifyContent:'space-between', fontSize:11.5}}>
        <span className="mono" style={{color: over ? 'var(--critical)' : 'var(--text-0)'}}>{fmtNum(value)}{unit}</span>
        <span className="mono muted">/ {fmtNum(threshold)}{unit}</span>
      </div>
      <div style={{height:5, background:'var(--bg-3)', borderRadius:3, marginTop: 4, overflow:'hidden', position:'relative'}}>
        <div style={{position:'absolute', inset:0, width: `${Math.min(pct, 100)}%`, background: over ? 'var(--critical)' : 'var(--warning)', borderRadius:3}}/>
        {over && <div style={{position:'absolute', left: '100%', top: 0, bottom:0, width: `${Math.min((pct-100)*0.4, 18)}%`, background: 'var(--critical)', opacity: 0.55, transform: 'translateX(-1px)'}}/>}
      </div>
      <div className="row" style={{justifyContent:'space-between', marginTop: 4, fontSize:10.5}}>
        <span className="muted-2">consumido</span>
        <span className="mono" style={{color: over ? 'var(--critical)' : 'var(--text-1)'}}>{over ? '+' : ''}{((pct-100)|0)}%</span>
      </div>
    </div>
  );
};

// ---------- Event icon helper ----------
const EVENT_META = {
  lock_contention: { icon: 'lock',  color: 'var(--critical)', label: 'lock contention' },
  validation_failed: { icon: 'cancel', color: 'var(--warning)', label: 'validation failed' },
  wave_retry: { icon: 'retry', color: 'var(--info)', label: 'wave retry' },
  schedule_wait: { icon: 'wait', color: 'var(--text-2)', label: 'schedule wait' },
};

// ---------- Tabs ----------
const Tabs = ({ items, value, onChange }) => (
  <div className="tabs">
    {items.map(it => (
      <button key={it.value} className={value === it.value ? 'active' : ''} onClick={() => onChange(it.value)}>
        {it.label}
        {it.count != null && <span className="count">{it.count}</span>}
      </button>
    ))}
  </div>
);

// Export everything
Object.assign(window, {
  Icon, fmtNum, fmtDur, fmtPct, fmtTimestamp, fmtRelative,
  StatusBadge, ScoreChip, OutcomePill, SeverityBadge, STATUS_LABEL,
  PipelineProgress, Sparkline, KpiCard,
  Donut, BarH, Columns, AreaChart, StackedBars, Histogram, Gauge, FunnelChart, Legend,
  EmptyState, DegradedBanner, Provenance, BudgetMini, EVENT_META, Tabs,
});
