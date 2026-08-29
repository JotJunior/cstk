/**
 * PlanUsage — apresentacao do gauge de PLANO (schema v14, `plan_usage`,
 * cstk >= 7.2.0): quanto da cota da CONTA ja foi consumido nas janelas de 5
 * horas e de 7 dias, capturado pelo hook de statusline a cada render.
 *
 * Eixo diferente de tudo o mais nesta tela: as outras metricas contam esforco
 * (tool calls), dinheiro (USD) ou consumo (tokens). Esta conta QUOTA — um
 * projeto pode custar pouco em USD e ainda assim esgotar a janela de 5h.
 * Por isso ela nao se soma nem se compara com custo/token de onda.
 *
 * Consome o view-model puro de `lib/plan-usage-select.ts` (selectPlanUsage),
 * que ja resolve estado (`degraded`/`empty`/`measured`). Este arquivo so
 * apresenta — mesmo precedente de `LooseUsage.tsx`/`OtelUsage.tsx`.
 *
 * Principio III: `usedPercentage` null renderiza "não medido", nunca "0%".
 * A captura e opt-in — tabela vazia significa hook desligado, nao plano livre.
 */
import type { PlanUsageVM } from '@/lib/plan-usage-select.js';
import {
  scopeLabel, fmtPlanPct, fmtResetsIn, planUsageBand,
  planUsageCoverageLabel, seriesForScope,
} from '@/lib/plan-usage-select.js';
import type { PlanUsageScopeState, PlanUsagePoint } from '@cstk-panel/shared-types';
import { Icon } from './Icon.js';

/** Cor da faixa — so colore, nunca altera o numero exibido. */
const BAND_COLOR: Record<string, string> = {
  ok: 'var(--success)',
  warn: 'var(--warning)',
  critical: 'var(--critical)',
  none: 'var(--text-3)',
};

/**
 * Estado "sem dado" — distingue "base nao tem a tabela" (schema v2-v13) de
 * "tabela presente sem capturas" (hook de statusline nao instalado). Nunca
 * aparece como 0%.
 */
export function PlanUsageEmpty({ reason }: { reason: 'empty' | 'degraded' }) {
  if (reason === 'degraded') {
    return (
      <div className="col gap-2" style={{ padding: '10px 0' }}>
        <div className="row gap-2" style={{ color: 'var(--text-2)', fontSize: 12 }}>
          <Icon name="alert" size={12} aria-hidden />
          Uso do plano não coletado nesta fonte.
        </div>
        <div style={{ fontSize: 11, color: 'var(--text-3)', lineHeight: 1.5 }}>
          Exige knowledge.db em schema v14 (cstk ≥ 7.2.0) com a tabela{' '}
          <span style={{ fontFamily: 'var(--font-mono)' }}>plan_usage</span>.
        </div>
      </div>
    );
  }
  return (
    <div className="col gap-1" style={{ textAlign: 'center', padding: '12px 0' }}>
      <div style={{ color: 'var(--text-3)', fontSize: 12 }}>
        Nenhuma captura de uso do plano neste recorte.
      </div>
      <div style={{ color: 'var(--text-3)', fontSize: 11 }}>
        A captura é opt-in:{' '}
        <span style={{ fontFamily: 'var(--font-mono)' }}>cstk statusline install</span>.
        Sem o hook, a cota não é medida — ausência de capturas não significa plano livre.
      </div>
    </div>
  );
}

/** Sparkline da janela. Ponto sem medicao e OMITIDO, nunca plotado como 0. */
function PlanUsageSparkline({ points, color }: { points: PlanUsagePoint[]; color: string }) {
  const values = points
    .map(p => p.usedPercentage)
    .filter((v): v is number => v != null);
  if (values.length < 2) return null;

  const w = 200;
  const h = 28;
  const step = w / (values.length - 1);
  // Escala fixa 0..100: o eixo e percentual de cota, nao uma serie relativa —
  // normalizar pelo maximo faria 4% e 96% desenharem a mesma curva.
  const pts = values.map((v, i) => `${(i * step).toFixed(1)},${(h - (v / 100) * h).toFixed(1)}`);

  return (
    <svg viewBox={`0 0 ${w} ${h}`} width="100%" height={h} preserveAspectRatio="none" aria-hidden>
      <polyline points={pts.join(' ')} fill="none" stroke={color} strokeWidth={1.5} vectorEffect="non-scaling-stroke" />
    </svg>
  );
}

/** Uma janela: barra de cota, pico, reset e cadencia de captura. */
function PlanUsageScopeRow({ scope, series, nowMs }: {
  scope: PlanUsageScopeState;
  series: PlanUsagePoint[];
  nowMs: number;
}) {
  const band = planUsageBand(scope.usedPercentage);
  const color = BAND_COLOR[band] ?? 'var(--text-3)';
  const pct = scope.usedPercentage;

  return (
    <div className="col gap-2" style={{ padding: '10px 0', borderTop: '1px solid var(--border)' }}>
      <div className="row gap-2" style={{ justifyContent: 'space-between', alignItems: 'baseline' }}>
        <span style={{ fontSize: 12, fontWeight: 600, color: 'var(--text-1)' }}>
          {scopeLabel(scope.scope)}
        </span>
        <span className="tnum" style={{ fontFamily: 'var(--font-mono)', fontSize: 18, fontWeight: 700, color }}>
          {fmtPlanPct(pct)}
        </span>
      </div>

      {/* Trilho sempre 0..100: sem medicao a barra fica vazia em vez de cheia
          de zero — "não medido" nao pode parecer "plano intocado". */}
      <div style={{ height: 8, borderRadius: 4, background: 'var(--bg-3)', overflow: 'hidden' }}>
        {pct != null && (
          <div style={{ width: `${Math.min(100, Math.max(0, pct))}%`, height: '100%', background: color, borderRadius: 4 }} />
        )}
      </div>

      <div
        className="row gap-3"
        style={{ flexWrap: 'wrap', fontSize: 10.5, color: 'var(--text-3)', fontFamily: 'var(--font-mono)' }}
      >
        <span title="maior percentual observado no recorte — sobrevive ao reset da janela">
          pico {fmtPlanPct(scope.peakUsedPercentage)}
        </span>
        <span title="epoch de reset informado pela origem">
          reseta {fmtResetsIn(scope.resetsAt, nowMs)}
        </span>
        <span title="a captura é throttled: conta mudanças de valor, não renders da statusline">
          {scope.captures} captura{scope.captures === 1 ? '' : 's'}
        </span>
        {scope.capturedAt && <span title="momento da captura mais recente">última {scope.capturedAt}</span>}
      </div>

      <PlanUsageSparkline points={series} color={color} />
    </div>
  );
}

/** Bloco completo do gauge de plano. */
export function PlanUsageDetailPanel({ vm, nowMs }: { vm: PlanUsageVM; nowMs: number }) {
  if (vm.state !== 'measured') return <PlanUsageEmpty reason={vm.state} />;

  return (
    <div className="col gap-2">
      <div style={{ fontSize: 10.5, color: 'var(--text-3)', lineHeight: 1.5 }}>
        Cota da <strong>conta</strong>, não do projeto: as janelas medem tudo que passou pela
        mesma credencial. Não se soma nem se compara com custo/tokens de onda — é outro eixo.
      </div>

      {vm.byScope.map(s => (
        <PlanUsageScopeRow
          key={s.scope}
          scope={s}
          series={seriesForScope(vm.series, s.scope)}
          nowMs={nowMs}
        />
      ))}

      <div
        className="row gap-2"
        style={{ justifyContent: 'space-between', flexWrap: 'wrap', fontSize: 10, color: 'var(--text-3)', fontFamily: 'var(--font-mono)' }}
      >
        <span>{planUsageCoverageLabel(vm.coverage)}</span>
        {vm.seriesTruncated && <span title="a série mostra os pontos mais recentes">série parcial (cortada no limite)</span>}
      </div>
    </div>
  );
}
