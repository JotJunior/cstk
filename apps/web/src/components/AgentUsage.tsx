/**
 * AgentUsage — apresentacao do consumo REAL de subagentes (schema v10 da
 * knowledge.db, feature cstk `wave-token-metrics`).
 *
 * Principio III (Honestidade de Metrica), na forma que o dado exige:
 * - token aqui e MEDIDO pelo harness (nao e proxy nem estimativa), entao NAO
 *   leva rotulo "aproximado";
 * - mas e AMOSTRA: spawns em background nao reportam uso. Sempre que
 *   `spawnsWithUsage < spawnsTotal` o denominador aparece junto do total —
 *   invariante SC-004 do cstk;
 * - `null` NUNCA vira 0. Sao tres estados distintos e visualmente distintos:
 *   nao coletado / coletado sem dado / medido.
 * - nada de "$"/USD: o painel nao conhece preco de token.
 */
import type { AgentUsageRollup, WaveDTO } from '@cstk-panel/shared-types';
import { fmtNum, fmtTokens, fmtMs } from '@/lib/format.js';
import { Icon } from './Icon.js';

// ---------------------------------------------------------------------------
// Helpers puros (testados em lib/agent-usage.test.ts)
// ---------------------------------------------------------------------------

export type AgentUsageState =
  /** base v<10 ou onda anterior a feature: nao existe medicao */
  | 'uncollected'
  /** houve coleta, mas nenhum spawn reportou uso (tipicamente background) */
  | 'collected-no-data'
  /** ha token medido */
  | 'measured';

export function agentUsageState(u: AgentUsageRollup | null | undefined): AgentUsageState {
  if (!u || u.spawnsTotal == null) return 'uncollected';
  if (u.totalTokens == null) return 'collected-no-data';
  return 'measured';
}

/** True quando o total exibido cobre apenas parte dos spawns observados. */
export function isPartialSample(u: AgentUsageRollup | null | undefined): boolean {
  if (!u || u.spawnsTotal == null || u.spawnsWithUsage == null) return false;
  return u.spawnsWithUsage < u.spawnsTotal;
}

/** Texto curto de cobertura — "5 de 9 spawns medidos". */
export function coverageLabel(u: AgentUsageRollup | null | undefined): string {
  if (!u || u.spawnsTotal == null) return 'métrica não coletada';
  const withUsage = u.spawnsWithUsage ?? 0;
  return `${fmtNum(withUsage)} de ${fmtNum(u.spawnsTotal)} spawns medidos`;
}

/** Converte os campos achatados de uma onda no formato do rollup. */
export function waveAgentUsage(w: WaveDTO): AgentUsageRollup {
  return {
    spawnsTotal: w.agentSpawnsTotal,
    spawnsWithUsage: w.agentSpawnsWithUsage,
    totalTokens: w.agentTotalTokens,
    inputTokens: w.agentInputTokens,
    outputTokens: w.agentOutputTokens,
    cacheReadTokens: w.agentCacheReadTokens,
    cacheCreationTokens: w.agentCacheCreationTokens,
    toolUseCount: w.agentToolUseCount,
    durationMs: w.agentDurationMs,
    wavesWithUsage: w.agentSpawnsTotal == null ? null : 1,
    wavesTotal: 1,
  };
}

/** Soma ondas preservando null: so vira numero se ao menos uma onda mediu. */
export function sumAgentUsage(waves: WaveDTO[]): AgentUsageRollup {
  const add = (acc: number | null, v: number | null): number | null =>
    v == null ? acc : (acc ?? 0) + v;
  return waves.reduce<AgentUsageRollup>((acc, w) => ({
    spawnsTotal: add(acc.spawnsTotal, w.agentSpawnsTotal),
    spawnsWithUsage: add(acc.spawnsWithUsage, w.agentSpawnsWithUsage),
    totalTokens: add(acc.totalTokens, w.agentTotalTokens),
    inputTokens: add(acc.inputTokens, w.agentInputTokens),
    outputTokens: add(acc.outputTokens, w.agentOutputTokens),
    cacheReadTokens: add(acc.cacheReadTokens, w.agentCacheReadTokens),
    cacheCreationTokens: add(acc.cacheCreationTokens, w.agentCacheCreationTokens),
    toolUseCount: add(acc.toolUseCount, w.agentToolUseCount),
    durationMs: add(acc.durationMs, w.agentDurationMs),
    wavesWithUsage: add(acc.wavesWithUsage, w.agentSpawnsTotal == null ? null : 1),
    wavesTotal: (acc.wavesTotal ?? 0) + 1,
  }), {
    spawnsTotal: null, spawnsWithUsage: null, totalTokens: null,
    inputTokens: null, outputTokens: null, cacheReadTokens: null,
    cacheCreationTokens: null, toolUseCount: null, durationMs: null,
    wavesWithUsage: null, wavesTotal: 0,
  });
}

// ---------------------------------------------------------------------------
// Componentes
// ---------------------------------------------------------------------------

/**
 * Selo de cobertura da amostra. Renderizado SEMPRE que ha total exibido —
 * neutro quando a cobertura e integral, de alerta quando e parcial.
 */
export function CoverageBadge({ usage }: { usage: AgentUsageRollup | null | undefined }) {
  const partial = isPartialSample(usage);
  return (
    <span
      title={partial
        ? 'Spawns sem dado de uso (tipicamente subagentes em background) entram no total de spawns mas não no de tokens.'
        : 'Todos os spawns observados reportaram uso.'}
      style={{
        padding: '1px 7px', borderRadius: 8, fontSize: 10, fontWeight: 600,
        fontFamily: 'var(--font-mono)', whiteSpace: 'nowrap',
        background: partial ? 'var(--warning-soft)' : 'var(--bg-3)',
        color: partial ? 'var(--warning)' : 'var(--text-2)',
      }}
    >
      {coverageLabel(usage)}
    </span>
  );
}

/** Estado vazio honesto — distingue "não coletado" de "sem dado de uso". */
export function AgentUsageEmpty({ usage }: { usage: AgentUsageRollup | null | undefined }) {
  const state = agentUsageState(usage);
  const uncollected = state === 'uncollected';
  return (
    <div className="col gap-2" style={{ padding: '10px 0' }}>
      <div className="row gap-2" style={{ color: 'var(--text-2)', fontSize: 12 }}>
        <Icon name="alert" size={12} aria-hidden />
        {uncollected
          ? 'Consumo de subagentes não coletado nesta fonte.'
          : 'Coletado, mas nenhum spawn reportou uso.'}
      </div>
      <div style={{ fontSize: 11, color: 'var(--text-3)', lineHeight: 1.5 }}>
        {uncollected
          ? 'Exige knowledge.db em schema v10 (cstk ≥ 5.25.0) e execução com o hook de uso ativo. Execuções anteriores não são retroalimentadas.'
          : `${fmtNum(usage?.spawnsTotal ?? 0)} spawn(s) observado(s) sem dado de uso — subagentes em background não reportam consumo. Zero não seria verdade, por isso nada é somado.`}
      </div>
    </div>
  );
}

interface StatItem { label: string; value: string; color?: string | undefined; tip?: string | undefined }

/** Grade de breakdown de tokens/uso. Não renderiza nada quando não há medição. */
export function AgentUsageBreakdown({
  usage, columns = 4,
}: {
  usage: AgentUsageRollup | null | undefined;
  columns?: number;
}) {
  if (agentUsageState(usage) !== 'measured' || !usage) return null;
  const cached = usage.cacheReadTokens;
  const total = usage.totalTokens;
  const cacheShare = cached != null && total != null && total > 0 ? cached / total : null;

  const stats: StatItem[] = [
    { label: 'Tokens medidos', value: fmtTokens(usage.totalTokens), color: 'var(--text-0)' },
    { label: 'Input', value: fmtTokens(usage.inputTokens) },
    { label: 'Output', value: fmtTokens(usage.outputTokens) },
    {
      label: 'Cache read',
      value: fmtTokens(usage.cacheReadTokens),
      color: 'var(--success)',
      tip: cacheShare != null ? `${(cacheShare * 100).toFixed(1)}% do total veio de cache` : undefined,
    },
    { label: 'Cache creation', value: fmtTokens(usage.cacheCreationTokens) },
    { label: 'Tool uses', value: fmtNum(usage.toolUseCount), tip: 'chamadas de ferramenta DENTRO dos subagentes' },
    { label: 'Tempo de subagente', value: fmtMs(usage.durationMs) },
    { label: 'Spawns', value: `${fmtNum(usage.spawnsWithUsage)} / ${fmtNum(usage.spawnsTotal)}` },
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

/**
 * Bloco completo (breakdown + cobertura + estados vazios) — usado nas telas de
 * projeto, feature e execucao.
 */
export function AgentUsagePanel({
  usage, columns = 4,
}: {
  usage: AgentUsageRollup | null | undefined;
  columns?: number;
}) {
  if (agentUsageState(usage) !== 'measured') return <AgentUsageEmpty usage={usage} />;
  return (
    <div className="col gap-3">
      <AgentUsageBreakdown usage={usage} columns={columns} />
      <div className="row gap-2" style={{ justifyContent: 'flex-end' }}>
        <CoverageBadge usage={usage} />
      </div>
    </div>
  );
}
