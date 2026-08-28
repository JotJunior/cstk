/**
 * LooseUsage — apresentacao do consumo AVULSO (schema v13, `loose_usage`,
 * cstk >= 6.6.0): tokens/custo das sessoes interativas comuns do Claude Code,
 * fora de qualquer execucao agente-00c/feature-00c, mais a comparacao
 * avulso x pipeline (`wave_model_usage`).
 *
 * Consome o view-model puro de `lib/loose-usage-select.ts` (selectLooseUsage),
 * que ja resolve estado (`degraded`/`empty`/`measured`). Este arquivo so
 * apresenta — mesmo precedente de `ModelUsage.tsx`/`OtelUsage.tsx`.
 *
 * Principio III (Honestidade de Metrica): custo/tokens aqui sao MEDIDOS
 * (telemetria OTel via hook opt-in) — rotulo "medido" sempre visivel.
 * Segmentos ABERTOS ainda estao em captura: o valor e parcial e recebe o
 * marcador `*`, nunca apresentado como final. Campo sem medicao renderiza
 * "—"/"não medido", jamais 0 fabricado.
 */
import type { LooseUsageVM } from '@/lib/loose-usage-select.js';
import { looseUsageCoverageLabel, fmtBlendedPerMtok, LOOSE_USAGE_NATURE_LABEL } from '@/lib/loose-usage-select.js';
import type { LooseUsageComparison, LooseUsageCoverage, LooseUsageProjectEntry } from '@cstk-panel/shared-types';
import { fmtUsd } from './OtelUsage.js';
import { modelUsageColor } from './ModelUsage.js';
import { fmtTokens } from '@/lib/format.js';
import { Icon } from './Icon.js';

/**
 * Estado "sem dado" — distingue "fonte nao coleta" (schema v2-v12, tabela
 * ausente) de "captura sem linhas" (tabela presente; hook opt-in desligado ou
 * nenhum consumo avulso no recorte). Nunca aparece como zero.
 */
export function LooseUsageEmpty({ reason }: { reason: 'empty' | 'degraded' }) {
  if (reason === 'degraded') {
    return (
      <div className="col gap-2" style={{ padding: '10px 0' }}>
        <div className="row gap-2" style={{ color: 'var(--text-2)', fontSize: 12 }}>
          <Icon name="alert" size={12} aria-hidden />
          Consumo avulso não coletado nesta fonte.
        </div>
        <div style={{ fontSize: 11, color: 'var(--text-3)', lineHeight: 1.5 }}>
          Exige knowledge.db em schema v13 (cstk ≥ 6.6.0) com a tabela{' '}
          <span style={{ fontFamily: 'var(--font-mono)' }}>loose_usage</span>.
        </div>
      </div>
    );
  }
  return (
    <div className="col gap-1" style={{ textAlign: 'center', padding: '12px 0' }}>
      <div style={{ color: 'var(--text-3)', fontSize: 12 }}>
        Nenhum consumo avulso registrado neste recorte.
      </div>
      <div style={{ color: 'var(--text-3)', fontSize: 11 }}>
        A captura é opt-in:{' '}
        <span style={{ fontFamily: 'var(--font-mono)' }}>cstk hooks install --with-loose-usage</span>.
        Sem o hook, sessões interativas não são medidas — ausência de linhas não significa ausência de consumo.
      </div>
    </div>
  );
}

/** Uma linha do rollup por projeto: projeto · tokens · custo (com `*` se houver segmento aberto). */
function LooseUsageProjectRow({ entry }: { entry: LooseUsageProjectEntry }) {
  const partial = entry.openSegments > 0;
  return (
    <div className="row" style={{ justifyContent: 'space-between', alignItems: 'center' }}>
      <div className="row gap-2" style={{ minWidth: 0 }}>
        <span
          className="mono"
          style={{ fontSize: 12, color: 'var(--text-0)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}
          title={entry.projectPath ?? undefined}
        >
          {entry.project}
        </span>
        <span style={{ fontSize: 10.5, color: 'var(--text-3)', fontFamily: 'var(--font-mono)', flexShrink: 0 }}>
          {entry.segments} seg · {entry.processes} proc
        </span>
      </div>
      <div className="row gap-3" style={{ flexShrink: 0 }}>
        <span className="mono tnum" style={{ fontSize: 11, color: 'var(--text-2)' }}>{fmtTokens(entry.totalTokens)}</span>
        <span
          className="mono tnum"
          title={partial ? `${entry.openSegments} segmento(s) ainda em captura — valor parcial` : undefined}
          style={{ fontSize: 12, color: 'var(--text-0)', minWidth: 68, textAlign: 'right' }}
        >
          {fmtUsd(entry.costUsd)}{partial ? ' *' : ''}
        </span>
      </div>
    </div>
  );
}

/**
 * Comparacao avulso x pipeline — agregada por categoria, nunca linha a linha
 * (granularidades diferentes por construcao; FR-009 do cstk). Lado sem
 * nenhuma medicao mostra "não medido" (null), nunca "$0".
 */
export function LooseUsageComparisonTable({ comparison }: { comparison: LooseUsageComparison }) {
  const rows = [
    { label: 'avulso (sessões interativas)', side: comparison.loose },
    { label: 'pipeline (execuções 00c)', side: comparison.pipeline },
  ];
  return (
    <div className="col gap-1">
      {rows.map((r) => (
        <div key={r.label} className="row" style={{ justifyContent: 'space-between', alignItems: 'center' }}>
          <span style={{ fontSize: 11.5, color: 'var(--text-1)', minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
            {r.label}
          </span>
          <div className="row gap-3" style={{ flexShrink: 0 }}>
            <span className="mono tnum" style={{ fontSize: 11, color: 'var(--text-2)' }}>{fmtTokens(r.side.totalTokens)}</span>
            <span className="mono tnum" style={{ fontSize: 11, color: 'var(--text-2)', minWidth: 92, textAlign: 'right' }}>
              {fmtBlendedPerMtok(r.side.blendedCostPerMtok)}
            </span>
            <span className="mono tnum" style={{ fontSize: 12, color: 'var(--text-0)', minWidth: 68, textAlign: 'right' }}>
              {fmtUsd(r.side.costUsd)}
            </span>
          </div>
        </div>
      ))}
    </div>
  );
}

/** Rodape de cobertura da amostra avulsa — contadores medidos, nunca fundidos. */
function LooseUsageCoverageDetail({ coverage }: { coverage: LooseUsageCoverage }) {
  if (coverage.rowsTotal == null) return null;
  return (
    <div className="col gap-1" style={{ fontSize: 10.5, color: 'var(--text-3)', fontFamily: 'var(--font-mono)' }}>
      <div>{looseUsageCoverageLabel(coverage)} · {coverage.projects ?? 0} projeto(s)</div>
      {(coverage.segmentsOpen ?? 0) > 0 && (
        <div>* valores com segmento aberto ainda em captura — total parcial, não final</div>
      )}
      {coverage.lastCapturedAt && <div>última captura: {coverage.lastCapturedAt}</div>}
    </div>
  );
}

/**
 * Painel completo do card de consumo avulso (Métricas): por projeto, por
 * modelo e comparação avulso x pipeline. Os 3 estados (`measured`/`empty`/
 * `degraded`) nunca colapsam visualmente.
 */
export function LooseUsageDetailPanel({ vm }: { vm: LooseUsageVM }) {
  if (vm.state !== 'measured') return <LooseUsageEmpty reason={vm.state} />;
  return (
    <div className="col gap-4">
      <div className="col gap-2">
        <div
          className="mono"
          style={{ fontSize: 10.5, color: 'var(--text-2)', textTransform: 'uppercase', letterSpacing: '0.05em' }}
        >
          Por projeto · {LOOSE_USAGE_NATURE_LABEL}
        </div>
        {vm.byProject.map((entry) => (
          <LooseUsageProjectRow key={entry.project} entry={entry} />
        ))}
      </div>
      <div className="col gap-2">
        <div
          className="mono"
          style={{ fontSize: 10.5, color: 'var(--text-2)', textTransform: 'uppercase', letterSpacing: '0.05em' }}
        >
          Por modelo
        </div>
        {vm.byModel.map((e) => (
          <div key={e.model} className="row" style={{ justifyContent: 'space-between' }}>
            <div className="row gap-2" style={{ minWidth: 0 }}>
              <span
                aria-hidden
                style={{ width: 8, height: 8, borderRadius: 2, background: modelUsageColor(e.model), flexShrink: 0 }}
              />
              <span
                className="mono"
                style={{ fontSize: 11.5, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}
              >
                {e.model}
              </span>
            </div>
            <div className="row gap-3" style={{ flexShrink: 0 }}>
              <span className="mono tnum" style={{ fontSize: 11, color: 'var(--text-2)' }}>{fmtTokens(e.totalTokens)}</span>
              <span className="mono tnum" style={{ fontSize: 12, color: 'var(--text-0)', minWidth: 68, textAlign: 'right' }}>
                {fmtUsd(e.costUsd)}
              </span>
            </div>
          </div>
        ))}
      </div>
      <div className="col gap-2">
        <div
          className="mono"
          style={{ fontSize: 10.5, color: 'var(--text-2)', textTransform: 'uppercase', letterSpacing: '0.05em' }}
        >
          Avulso × pipeline · tokens / custo blended / custo
        </div>
        <LooseUsageComparisonTable comparison={vm.comparison} />
      </div>
      <LooseUsageCoverageDetail coverage={vm.coverage} />
    </div>
  );
}
