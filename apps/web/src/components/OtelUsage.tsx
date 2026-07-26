/**
 * OtelUsage — apresentacao do consumo medido pela telemetria OTel do Claude
 * Code (schema v11 da knowledge.db, cstk >= 5.30.0).
 *
 * Por que existe separado de AgentUsage (schema v10), e nao como substituto:
 * - `agent_*` vem do hook de spawn: enxerga o detalhe POR SUBAGENTE, mas nunca
 *   o consumo do proprio orquestrador (o spawn dele envolve a onda);
 * - `otel_*` vem dos contadores de API request: cobre main + subagente, mas
 *   nao abre por spawn.
 * As duas fontes convivem. A UI prefere OTel para totais (mais completo) e
 * mantem agent_* para o detalhe.
 *
 * Principio III (Honestidade de Metrica):
 * - o USD aqui NAO e estimado pelo painel — vem calculado pelo Claude Code e
 *   apenas somado. E o unico lugar do painel autorizado a exibir "$";
 * - `null` NUNCA vira 0: onda sem telemetria e onda que custou zero nao sao a
 *   mesma coisa;
 * - o total e AMOSTRA enquanto `wavesWithOtel < wavesTotal` — a cobertura
 *   aparece junto do numero, sempre.
 */
import type { OtelUsageRollup, WaveDTO } from '@cstk-panel/shared-types';
import { fmtNum, fmtTokens } from '@/lib/format.js';
import { Icon } from './Icon.js';

// ---------------------------------------------------------------------------
// Helpers puros (testados em lib/otel-usage.test.ts)
// ---------------------------------------------------------------------------

export type OtelUsageState =
  /** base v<11, telemetria desligada ou execucao anterior ao cstk 5.28.0 */
  | 'uncollected'
  /** ha custo/token medido no recorte */
  | 'measured';

export function otelUsageState(u: OtelUsageRollup | null | undefined): OtelUsageState {
  if (!u) return 'uncollected';
  return u.costUsd != null || u.totalTokens != null ? 'measured' : 'uncollected';
}

/** True quando o total exibido cobre apenas parte das ondas do recorte. */
export function isPartialOtelSample(u: OtelUsageRollup | null | undefined): boolean {
  if (!u || u.wavesTotal == null || u.wavesWithOtel == null) return false;
  return u.wavesWithOtel < u.wavesTotal;
}

/** Texto curto de cobertura — "7 de 12 ondas medidas". */
export function otelCoverageLabel(u: OtelUsageRollup | null | undefined): string {
  if (!u || u.wavesTotal == null) return 'telemetria não coletada';
  return `${fmtNum(u.wavesWithOtel ?? 0)} de ${fmtNum(u.wavesTotal)} ondas medidas`;
}

/**
 * Formata USD preservando ordem de grandeza pequena: onda barata custa
 * fracoes de centavo (0.0098) e arredondar para 2 casas a exibiria como
 * "$0.01" ou "$0.00" — este ultimo indistinguivel de "nao custou nada".
 */
export function fmtUsd(v: number | null | undefined): string {
  if (v == null) return '—';
  if (v === 0) return '$0';
  return v < 0.01 ? `$${v.toFixed(4)}` : `$${v.toFixed(2)}`;
}

/** Fatia do custo atribuida a subagentes, em 0..1; null quando indeterminavel. */
export function subagentCostShare(u: OtelUsageRollup | null | undefined): number | null {
  if (!u || u.costUsd == null || u.costUsd === 0 || u.costSubagentUsd == null) return null;
  return u.costSubagentUsd / u.costUsd;
}

/** Converte os campos achatados de uma onda no formato do rollup. */
export function waveOtelUsage(w: WaveDTO): OtelUsageRollup {
  return {
    costUsd: w.otelCostUsd,
    costMainUsd: w.otelCostMainUsd,
    costSubagentUsd: w.otelCostSubagentUsd,
    totalTokens: w.otelTotalTokens,
    subagentTokens: w.otelSubagentTokens,
    wavesWithOtel: w.otelCostUsd == null ? null : 1,
    wavesTotal: 1,
  };
}

/** Soma ondas preservando null: so vira numero se ao menos uma onda mediu. */
export function sumOtelUsage(waves: WaveDTO[]): OtelUsageRollup {
  const add = (acc: number | null, v: number | null): number | null =>
    v == null ? acc : (acc ?? 0) + v;
  return waves.reduce<OtelUsageRollup>((acc, w) => ({
    costUsd: add(acc.costUsd, w.otelCostUsd),
    costMainUsd: add(acc.costMainUsd, w.otelCostMainUsd),
    costSubagentUsd: add(acc.costSubagentUsd, w.otelCostSubagentUsd),
    totalTokens: add(acc.totalTokens, w.otelTotalTokens),
    subagentTokens: add(acc.subagentTokens, w.otelSubagentTokens),
    wavesWithOtel: add(acc.wavesWithOtel, w.otelCostUsd == null ? null : 1),
    wavesTotal: (acc.wavesTotal ?? 0) + 1,
  }), {
    costUsd: null, costMainUsd: null, costSubagentUsd: null,
    totalTokens: null, subagentTokens: null,
    wavesWithOtel: null, wavesTotal: 0,
  });
}

// ---------------------------------------------------------------------------
// Componentes
// ---------------------------------------------------------------------------

/** Selo de cobertura — neutro quando integral, de alerta quando parcial. */
export function OtelCoverageBadge({ usage }: { usage: OtelUsageRollup | null | undefined }) {
  const partial = isPartialOtelSample(usage);
  return (
    <span
      title={partial
        ? 'Ondas sem telemetria coletada entram no denominador mas não somam custo — o total exibido é parcial.'
        : 'Todas as ondas do recorte têm telemetria coletada.'}
      style={{
        padding: '1px 7px', borderRadius: 8, fontSize: 10, fontWeight: 600,
        fontFamily: 'var(--font-mono)', whiteSpace: 'nowrap',
        background: partial ? 'var(--warning-soft)' : 'var(--bg-3)',
        color: partial ? 'var(--warning)' : 'var(--text-2)',
      }}
    >
      {otelCoverageLabel(usage)}
    </span>
  );
}

/** Estado vazio honesto — explica o que falta ligar, sem exibir zero. */
export function OtelUsageEmpty() {
  return (
    <div className="col gap-2" style={{ padding: '10px 0' }}>
      <div className="row gap-2" style={{ color: 'var(--text-2)', fontSize: 12 }}>
        <Icon name="alert" size={12} aria-hidden />
        Custo real não coletado nesta fonte.
      </div>
      <div style={{ fontSize: 11, color: 'var(--text-3)', lineHeight: 1.5 }}>
        Exige knowledge.db em schema v11 (cstk ≥ 5.30.0 para a ingestão) e telemetria
        ligada durante a execução: <span style={{ fontFamily: 'var(--font-mono)' }}>CLAUDE_CODE_ENABLE_TELEMETRY=1</span>
        {' '}+ <span style={{ fontFamily: 'var(--font-mono)' }}>OTEL_METRICS_EXPORTER=prometheus</span>.
        Execuções anteriores não são retroalimentadas.
      </div>
    </div>
  );
}

interface StatItem { label: string; value: string; color?: string | undefined; tip?: string | undefined }

/** Grade de breakdown de custo/tokens. Nada renderiza sem medicao. */
export function OtelUsageBreakdown({
  usage, columns = 4,
}: {
  usage: OtelUsageRollup | null | undefined;
  columns?: number;
}) {
  if (otelUsageState(usage) !== 'measured' || !usage) return null;
  const share = subagentCostShare(usage);

  const stats: StatItem[] = [
    {
      label: 'Custo total',
      value: fmtUsd(usage.costUsd),
      color: 'var(--text-0)',
      tip: 'Calculado pelo Claude Code e somado pelo painel — não é estimativa local.',
    },
    { label: 'Loop principal', value: fmtUsd(usage.costMainUsd), tip: 'query_source=main' },
    {
      label: 'Subagentes',
      value: fmtUsd(usage.costSubagentUsd),
      color: 'var(--info)',
      tip: share != null ? `${(share * 100).toFixed(0)}% do custo total` : 'query_source=subagent',
    },
    {
      label: 'Fatia de subagente',
      value: share != null ? `${(share * 100).toFixed(0)}%` : '—',
      color: 'var(--info)',
    },
    { label: 'Tokens totais', value: fmtTokens(usage.totalTokens), tip: 'input + output + cache, todas as origens' },
    { label: 'Tokens de subagente', value: fmtTokens(usage.subagentTokens) },
    {
      label: 'Ondas medidas',
      value: `${fmtNum(usage.wavesWithOtel)} / ${fmtNum(usage.wavesTotal)}`,
    },
  ];

  return (
    <div style={{ display: 'grid', gridTemplateColumns: `repeat(${columns}, 1fr)`, gap: 12 }}>
      {stats.map(s => (
        <div key={s.label} title={s.tip}>
          <div style={{ fontSize: 10, color: 'var(--text-3)', textTransform: 'uppercase', letterSpacing: '0.07em', marginBottom: 2 }}>
            {s.label}
          </div>
          <div className="tnum" style={{ fontFamily: 'var(--font-mono)', fontSize: 16, fontWeight: 700, color: s.color ?? 'var(--text-1)' }}>
            {s.value}
          </div>
        </div>
      ))}
    </div>
  );
}

/** Bloco completo (breakdown + cobertura + estado vazio). */
export function OtelUsagePanel({
  usage, columns = 4,
}: {
  usage: OtelUsageRollup | null | undefined;
  columns?: number;
}) {
  if (otelUsageState(usage) !== 'measured') return <OtelUsageEmpty />;
  return (
    <div className="col gap-3">
      <OtelUsageBreakdown usage={usage} columns={columns} />
      <div className="row gap-2" style={{ justifyContent: 'flex-end' }}>
        <OtelCoverageBadge usage={usage} />
      </div>
    </div>
  );
}
