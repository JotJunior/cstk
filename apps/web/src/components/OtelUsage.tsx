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

// ---------------------------------------------------------------------------
// Breakdown por FONTE x TIPO (schema v12)
// ---------------------------------------------------------------------------

/** Um lado do breakdown (main ou subagente), ja somado no recorte. */
export interface OtelSourceTokens {
  inputTokens: number | null;
  outputTokens: number | null;
  cacheReadTokens: number | null;
  cacheCreationTokens: number | null;
  /** ondas com ESTE lado coletado — denominador proprio, nao compartilhado */
  wavesWithBreakdown: number | null;
}

/** Extrai o lado `main` do rollup. */
export function otelMainTokens(u: OtelUsageRollup | null | undefined): OtelSourceTokens {
  return {
    inputTokens: u?.mainInputTokens ?? null,
    outputTokens: u?.mainOutputTokens ?? null,
    cacheReadTokens: u?.mainCacheReadTokens ?? null,
    cacheCreationTokens: u?.mainCacheCreationTokens ?? null,
    wavesWithBreakdown: u?.wavesWithMainBreakdown ?? null,
  };
}

/** Extrai o lado `subagent` do rollup. */
export function otelSubagentTokens(u: OtelUsageRollup | null | undefined): OtelSourceTokens {
  return {
    inputTokens: u?.subagentInputTokens ?? null,
    outputTokens: u?.subagentOutputTokens ?? null,
    cacheReadTokens: u?.subagentCacheReadTokens ?? null,
    cacheCreationTokens: u?.subagentCacheCreationTokens ?? null,
    wavesWithBreakdown: u?.wavesWithSubagentBreakdown ?? null,
  };
}

/** True quando ao menos UM lado do breakdown foi coletado no recorte. */
export function hasOtelBreakdown(u: OtelUsageRollup | null | undefined): boolean {
  if (!u) return false;
  const main = otelMainTokens(u);
  const sub = otelSubagentTokens(u);
  return [main, sub].some(s =>
    s.inputTokens != null || s.outputTokens != null ||
    s.cacheReadTokens != null || s.cacheCreationTokens != null,
  );
}

/** Soma dos 4 tipos de um lado; null quando nenhum tipo foi coletado. */
export function otelSourceTotal(s: OtelSourceTokens): number | null {
  const parts = [s.inputTokens, s.outputTokens, s.cacheReadTokens, s.cacheCreationTokens]
    .filter((v): v is number => v != null);
  return parts.length === 0 ? null : parts.reduce((a, b) => a + b, 0);
}

/**
 * Fatia do consumo que foi contexto RELIDO de cache, em 0..1.
 *
 * E a leitura que os totais de v11 nao davam: uma onda de 8,7M tokens sendo
 * 95% cache read e uma onda longa, nao uma onda cara. Denominador = a soma dos
 * 4 tipos DESTE lado (nunca `otelTotalTokens`, que mistura as fontes e existe
 * mesmo quando o breakdown do lado nao foi coletado).
 */
export function cacheReadShare(s: OtelSourceTokens): number | null {
  const total = otelSourceTotal(s);
  if (total == null || total === 0 || s.cacheReadTokens == null) return null;
  return s.cacheReadTokens / total;
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
    mainInputTokens: w.otelMainInputTokens,
    mainOutputTokens: w.otelMainOutputTokens,
    mainCacheReadTokens: w.otelMainCacheReadTokens,
    mainCacheCreationTokens: w.otelMainCacheCreationTokens,
    subagentInputTokens: w.otelSubagentInputTokens,
    subagentOutputTokens: w.otelSubagentOutputTokens,
    subagentCacheReadTokens: w.otelSubagentCacheReadTokens,
    subagentCacheCreationTokens: w.otelSubagentCacheCreationTokens,
    // Denominador por LADO: a onda so conta para o lado que de fato mediu.
    wavesWithMainBreakdown: w.otelMainInputTokens == null ? 0 : 1,
    wavesWithSubagentBreakdown: w.otelSubagentInputTokens == null ? 0 : 1,
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
    mainInputTokens: add(acc.mainInputTokens, w.otelMainInputTokens),
    mainOutputTokens: add(acc.mainOutputTokens, w.otelMainOutputTokens),
    mainCacheReadTokens: add(acc.mainCacheReadTokens, w.otelMainCacheReadTokens),
    mainCacheCreationTokens: add(acc.mainCacheCreationTokens, w.otelMainCacheCreationTokens),
    subagentInputTokens: add(acc.subagentInputTokens, w.otelSubagentInputTokens),
    subagentOutputTokens: add(acc.subagentOutputTokens, w.otelSubagentOutputTokens),
    subagentCacheReadTokens: add(acc.subagentCacheReadTokens, w.otelSubagentCacheReadTokens),
    subagentCacheCreationTokens: add(acc.subagentCacheCreationTokens, w.otelSubagentCacheCreationTokens),
    // Cada lado conta so as ondas que mediram AQUELE lado (main e subagente
    // sao coletas independentes — ver waves.ts no server).
    wavesWithMainBreakdown: add(acc.wavesWithMainBreakdown, w.otelMainInputTokens == null ? null : 1),
    wavesWithSubagentBreakdown: add(acc.wavesWithSubagentBreakdown, w.otelSubagentInputTokens == null ? null : 1),
  }), {
    costUsd: null, costMainUsd: null, costSubagentUsd: null,
    totalTokens: null, subagentTokens: null,
    wavesWithOtel: null, wavesTotal: 0,
    mainInputTokens: null, mainOutputTokens: null,
    mainCacheReadTokens: null, mainCacheCreationTokens: null,
    subagentInputTokens: null, subagentOutputTokens: null,
    subagentCacheReadTokens: null, subagentCacheCreationTokens: null,
    wavesWithMainBreakdown: null, wavesWithSubagentBreakdown: null,
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

/**
 * Barra de composicao de um lado (input / output / cache read / cache creation).
 *
 * Renderiza apenas os tipos MEDIDOS: um tipo null nao vira fatia de largura 0,
 * some da barra e some da legenda. Lado inteiro nao coletado nao renderiza —
 * quem informa isso e a linha de cobertura, nao uma barra vazia.
 */
function OtelSourceBar({ label, tokens, hint }: {
  label: string;
  tokens: OtelSourceTokens;
  hint: string;
}) {
  const total = otelSourceTotal(tokens);
  if (total == null || total === 0) {
    return (
      <div className="col gap-1">
        <div className="row gap-2" style={{ justifyContent: 'space-between', alignItems: 'baseline' }}>
          <span style={{ fontSize: 11, fontWeight: 600, color: 'var(--text-1)' }}>{label}</span>
          <span style={{ fontSize: 10.5, color: 'var(--text-3)', fontFamily: 'var(--font-mono)' }}>
            não coletado
          </span>
        </div>
      </div>
    );
  }

  const slices = [
    { key: 'cache read', value: tokens.cacheReadTokens, color: 'var(--info)' },
    { key: 'cache write', value: tokens.cacheCreationTokens, color: 'var(--model-sonnet)' },
    { key: 'input', value: tokens.inputTokens, color: 'var(--accent)' },
    { key: 'output', value: tokens.outputTokens, color: 'var(--warning)' },
  ].filter((s): s is { key: string; value: number; color: string } => s.value != null);

  const share = cacheReadShare(tokens);

  return (
    <div className="col gap-1" title={hint}>
      <div className="row gap-2" style={{ justifyContent: 'space-between', alignItems: 'baseline' }}>
        <span style={{ fontSize: 11, fontWeight: 600, color: 'var(--text-1)' }}>{label}</span>
        <span className="tnum" style={{ fontSize: 10.5, color: 'var(--text-2)', fontFamily: 'var(--font-mono)' }}>
          {fmtTokens(total)}
          {share != null && ` · ${(share * 100).toFixed(0)}% cache read`}
        </span>
      </div>
      <div style={{ display: 'flex', height: 10, borderRadius: 3, overflow: 'hidden', background: 'var(--bg-3)' }}>
        {slices.map(s => (
          <div
            key={s.key}
            title={`${s.key}: ${fmtTokens(s.value)}`}
            style={{ width: `${(s.value / total) * 100}%`, background: s.color }}
          />
        ))}
      </div>
      <div className="row gap-2" style={{ flexWrap: 'wrap', fontSize: 10, color: 'var(--text-3)', fontFamily: 'var(--font-mono)' }}>
        {slices.map(s => (
          <span key={s.key} className="row gap-1" style={{ alignItems: 'center' }}>
            <span style={{ width: 7, height: 7, borderRadius: 2, background: s.color, display: 'inline-block' }} />
            {s.key} {fmtTokens(s.value)}
          </span>
        ))}
      </div>
    </div>
  );
}

/**
 * Breakdown por fonte (schema v12) — main e subagente lado a lado.
 *
 * Cada lado carrega o PROPRIO denominador de cobertura. Na base real os dois
 * divergem muito (27 ondas com main contra 257 com subagente); um unico rotulo
 * de cobertura faria o lado do orquestrador parecer medido quando nao esta.
 */
export function OtelSourceBreakdown({ usage }: { usage: OtelUsageRollup | null | undefined }) {
  if (!hasOtelBreakdown(usage)) return null;
  const main = otelMainTokens(usage);
  const sub = otelSubagentTokens(usage);
  const cov = (s: OtelSourceTokens): string => {
    if (s.wavesWithBreakdown == null) return 'sem cobertura informada';
    const total = usage?.wavesTotal;
    return total == null
      ? `${fmtNum(s.wavesWithBreakdown)} onda(s) medida(s)`
      : `${fmtNum(s.wavesWithBreakdown)} de ${fmtNum(total)} ondas medidas`;
  };

  return (
    <div className="col gap-2">
      <div style={{ fontSize: 10, color: 'var(--text-3)', textTransform: 'uppercase', letterSpacing: '0.07em' }}>
        Tokens por fonte e tipo
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))', gap: 14 }}>
        <div className="col gap-1">
          <OtelSourceBar
            label="Loop principal"
            tokens={main}
            hint="query_source=main — o consumo do próprio orquestrador"
          />
          <div style={{ fontSize: 10, color: 'var(--text-3)', fontFamily: 'var(--font-mono)' }}>{cov(main)}</div>
        </div>
        <div className="col gap-1">
          <OtelSourceBar
            label="Subagentes"
            tokens={sub}
            hint="query_source=subagent — tudo que rodou dentro de spawns"
          />
          <div style={{ fontSize: 10, color: 'var(--text-3)', fontFamily: 'var(--font-mono)' }}>{cov(sub)}</div>
        </div>
      </div>
      <div style={{ fontSize: 10.5, color: 'var(--text-3)', lineHeight: 1.5 }}>
        Cache read é contexto <em>relido</em>, não token novo — uma onda pode somar milhões
        de tokens sem ter gerado quase nada. As duas fontes têm coberturas independentes:
        uma delas pode estar sem coleta enquanto a outra mede.
      </div>
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
      <OtelSourceBreakdown usage={usage} />
      <div className="row gap-2" style={{ justifyContent: 'flex-end' }}>
        <OtelCoverageBadge usage={usage} />
      </div>
    </div>
  );
}
