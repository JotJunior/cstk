/**
 * Metrics — Metricas Agregadas (US5).
 * 8 metricas via endpoints /metrics/<name>.
 * Principio III: eixo-y de custo rotulado "proxy: tool calls" (SC-002).
 * dec-020: "mix de modelos" indisponivel nesta fonte — card especial.
 * clarify-resolution: badge "derivada/aproximada" quando meta.approximate=true.
 *
 * Ref: spec.md §User Story 5; tasks.md §6.5; dec-020
 */
import { useMetric } from '@/lib/hooks.js';
import { useApiState } from '@/hooks/useApiState.js';
import { LoadingState, EmptyState, ErrorState, DegradedBanner } from '@/states/index.js';
import {
  KpiCard, Icon, Histogram, ScatterChart, Donut, StackedBarsH, Legend,
  AgentUsagePanel, AgentUsageEmpty,
  OtelUsagePanel, OtelUsageEmpty, otelUsageState, otelCoverageLabel, fmtUsd,
  ModelUsageDetailPanel, LooseUsageDetailPanel, TruncatedBarH,
  PlanUsageDetailPanel, PlanUsageEmpty,
} from '@/components/index.js';
import type { ScatterDatum, DonutDatum } from '@/components/index.js';
import { fmtTokens } from '@/lib/format.js';
import { pickTokens, tokenCoverageLabel } from '@/lib/token-source.js';
import { selectModelUsage, groupModelUsageByStage } from '@/lib/model-usage-select.js';
import { selectLooseUsage } from '@/lib/loose-usage-select.js';
import { selectPlanUsage } from '@/lib/plan-usage-select.js';
import { buildStageBars } from '@/lib/model-mix-by-stage-select.js';
import { truncateBars } from '@/lib/truncate-bars.js';
import type { PeriodParam, AgentUsageRollup, OtelUsageRollup, ModelUsageResult, LooseUsageResult, PlanUsageResult } from '@cstk-panel/shared-types';

// Cores por modelo (alinhado ao Overview)
const MODEL_COLOR: Record<string, string> = {
  haiku: 'var(--model-haiku)', sonnet: 'var(--model-sonnet)', opus: 'var(--model-opus)',
};
const modelColor = (m: string): string => MODEL_COLOR[m] ?? 'var(--model-fallback)';
// Ordem preferida das séries no empilhado
const MODEL_ORDER = ['haiku', 'sonnet', 'opus', 'manter-atual'];
const sortModels = (models: string[]): string[] =>
  [...models].sort((a, b) => {
    const ia = MODEL_ORDER.indexOf(a); const ib = MODEL_ORDER.indexOf(b);
    return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib) || a.localeCompare(b);
  });

interface MetricsProps {
  period: PeriodParam;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function fmtDur(secs: number | null | undefined): string {
  if (secs == null) return '—';
  if (secs < 60) return `${secs}s`;
  if (secs < 3600) return `${Math.floor(secs / 60)}m ${secs % 60}s`;
  return `${Math.floor(secs / 3600)}h ${Math.floor((secs % 3600) / 60)}m`;
}

function fmtPct(n: number | null | undefined, digits = 1): string {
  if (n == null) return '—';
  const v = n > 1 ? n : n * 100; // aceita 0..1 ou 0..100
  return `${v.toFixed(digits)}%`;
}

// Agregacao client-side: os endpoints /metrics retornam ARRAYS de linhas
// cruas (camelCase) — ver apps/server/src/db/queries/metrics.ts. As tabelas
// de p50/p95/media sao derivadas aqui, nao vem prontas do backend.
function nums(arr: unknown, key: string): number[] {
  return Array.isArray(arr)
    ? (arr as Record<string, unknown>[])
        .map(r => r[key])
        .filter((x): x is number => typeof x === 'number')
    : [];
}
function sum(values: number[]): number { return values.reduce((a, b) => a + b, 0); }
function mean(values: number[]): number | null {
  return values.length ? sum(values) / values.length : null;
}
function percentile(values: number[], p: number): number | null {
  if (!values.length) return null;
  const v = [...values].sort((a, b) => a - b);
  const idx = Math.min(v.length - 1, Math.floor((p / 100) * v.length));
  return v[idx] ?? null;
}
function maxOf(values: number[]): number | null {
  return values.length ? Math.max(...values) : null;
}

// ---------------------------------------------------------------------------
// Mini charts (SVG simples — sem dep externa)
// ---------------------------------------------------------------------------

interface TimeSeriesPoint { d?: string; date?: string; value?: number; v?: number; count?: number }

function AreaChart({ data, height = 120, color = 'var(--accent)', label = '' }: {
  data: TimeSeriesPoint[];
  height?: number;
  color?: string;
  label?: string;
}) {
  if (!data || data.length < 2) {
    return (
      <div style={{ height, display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--text-3)', fontSize: 12 }}>
        Sem dados suficientes
      </div>
    );
  }

  const values = data.map(d => d.value ?? d.v ?? d.count ?? 0);
  const maxV = Math.max(...values) || 1;
  const w = 400;
  const h = height - 20;
  const step = w / (values.length - 1);

  const pts = values.map((v, i) => ({ x: i * step, y: h - (v / maxV) * h }));
  const pathD = pts.map((p, i) => `${i === 0 ? 'M' : 'L'}${p.x.toFixed(1)},${p.y.toFixed(1)}`).join(' ');
  const areaD = `${pathD} L${(values.length - 1) * step},${h} L0,${h} Z`;

  return (
    <div>
      {label && (
        <div style={{ fontSize: 10.5, color: 'var(--text-3)', textAlign: 'right', fontFamily: 'var(--font-mono)', marginBottom: 4 }}>
          {label}
        </div>
      )}
      <svg viewBox={`0 0 ${w} ${height}`} style={{ width: '100%', height, overflow: 'visible' }}>
        <defs>
          <linearGradient id={`grad-${color.replace(/[^a-z]/gi, '')}`} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor={color} stopOpacity={0.25} />
            <stop offset="100%" stopColor={color} stopOpacity={0.02} />
          </linearGradient>
        </defs>
        <path d={areaD} fill={`url(#grad-${color.replace(/[^a-z]/gi, '')})`} />
        <path d={pathD} fill="none" stroke={color} strokeWidth={1.5} />
        {pts.map((p, i) => (
          <circle key={i} cx={p.x} cy={p.y} r={2.5} fill={color} />
        ))}
      </svg>
    </div>
  );
}


// ---------------------------------------------------------------------------
// Cartao de metrica generico com hook
// ---------------------------------------------------------------------------
function MetricCard({
  name, title, subtitle, period, renderContent, span = 1, emptyFallback,
}: {
  name: Parameters<typeof useMetric>[0];
  title: string;
  subtitle?: string;
  period?: PeriodParam;
  renderContent: (data: unknown, meta: { approximate?: boolean }) => React.ReactNode;
  span?: number;
  /**
   * Estado vazio proprio. Existe porque "sem dado no periodo" e "metrica nao
   * coletada nesta fonte" nao sao a mesma coisa: o EmptyState generico
   * sugeriria que basta trocar o periodo, quando na verdade a base nao tem a
   * coluna (schema v<10). Ver AgentUsageEmpty.
   */
  emptyFallback?: React.ReactNode;
}) {
  const query = useMetric(name, period);
  const { isLoading, isError, errorMessage } = useApiState(query);
  const raw = query.data?.data;
  const metaRaw = query.data?.meta;
  const metaRecord = metaRaw as unknown as Record<string, unknown> | null;
  const approximate = (metaRecord?.approximate as boolean | undefined) ?? false;

  return (
    <div className="card" style={{ gridColumn: span > 1 ? `span ${span}` : undefined }}>
      <div className="card-head">
        <div>
          <h3 style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            {title}
            {approximate && (
              <span style={{
                padding: '1px 6px', borderRadius: 8, fontSize: 10, fontWeight: 600,
                fontFamily: 'var(--font-mono)', background: 'var(--warning-soft)', color: 'var(--warning)',
              }}>
                derivada/aproximada
              </span>
            )}
          </h3>
          {subtitle && <div style={{ fontSize: 10.5, color: 'var(--text-2)', fontFamily: 'var(--font-mono)', marginTop: 2 }}>{subtitle}</div>}
        </div>
      </div>
      <div className="card-body">
        {isLoading && <LoadingState />}
        {isError && <ErrorState message={errorMessage ?? 'Erro ao carregar metrica.'} />}
        {!isLoading && !isError && (raw == null || (Array.isArray(raw) && raw.length === 0))
          ? (emptyFallback ?? <EmptyState title="Sem dados" subtitle="Nenhum dado para este periodo." />)
          : null}
        {!isLoading && !isError && raw != null && (
          !Array.isArray(raw) || (raw as unknown[]).length > 0
            ? renderContent(raw, { approximate })
            : null
        )}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Metrics principal
// ---------------------------------------------------------------------------
export function Metrics({ period }: MetricsProps) {
  // Buscar KPI summary de custo e test-pass para o topo
  const costQuery = useMetric('cost-over-time', period);
  const testQuery = useMetric('test-pass-rate', period);
  const latencyQuery = useMetric('human-latency', period);
  const clarifyQuery = useMetric('clarify-resolution', period);
  // schema v10 — consumo MEDIDO de subagentes (nao proxy, mas amostra)
  const usageQuery = useMetric('agent-usage', period);
  const agentUsage = (usageQuery.data?.data as AgentUsageRollup | null) ?? null;
  // schema v11 — consumo medido por telemetria OTel. Unica fonte de USD do
  // painel, e o valor vem calculado pelo Claude Code (nao ha preco embutido).
  const otelQuery = useMetric('otel-usage', period);
  const otelUsage = (otelQuery.data?.data as OtelUsageRollup | null) ?? null;
  const hasOtel = otelUsageState(otelUsage) === 'measured';
  const tokens = pickTokens(otelUsage, agentUsage);

  const { isDegraded } = useApiState(costQuery);
  const meta = costQuery.data?.meta;

  // cost-over-time e human-latency sao ARRAYS de linhas; test/clarify sao OBJETOS.
  const costData = costQuery.data?.data as unknown;            // array {day, toolCalls}
  const testData = testQuery.data?.data as Record<string, unknown> | null;   // {pass, fail, rate}
  const latData  = latencyQuery.data?.data as unknown;         // array {execucaoId, latencySeconds}
  const clarData = clarifyQuery.data?.data as Record<string, unknown> | null; // {total..., rate}
  const clarMetaRaw = clarifyQuery.data?.meta;
  const clarMetaApprox = (clarMetaRaw as unknown as Record<string, unknown> | null);

  // KPIs summary — derivados dos arrays/objetos reais
  const totalToolCalls = Array.isArray(costData) ? sum(nums(costData, 'toolCalls')) : null;
  const passRate       = (testData?.rate as number | null) ?? null;
  const latP50         = percentile(nums(latData, 'latencySeconds'), 50);
  const autoResolve    = (clarData?.rate as number | null) ?? null;
  const isApproximate  = (clarMetaApprox?.approximate as boolean | undefined) ?? false;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      {isDegraded && meta && <DegradedBanner meta={meta} />}

      {/* KPI row */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(170px, 1fr))', gap: 12 }}>
        <KpiCard
          label="Custo total · proxy"
          value={totalToolCalls != null ? String(totalToolCalls) : '—'}
          trend="tool_calls do orquestrador"
        />
        {/* Custo REAL (schema v11). Convive com o proxy acima em vez de
            substitui-lo: um mede esforco do orquestrador, o outro dinheiro. */}
        <KpiCard
          label="Custo total · real"
          value={hasOtel ? fmtUsd(otelUsage?.costUsd) : '—'}
          trend={hasOtel ? otelCoverageLabel(otelUsage) : 'telemetria não coletada'}
          accent={hasOtel ? 'accent' : undefined}
        />
        {/* Token MEDIDO — convive com o proxy: um conta chamadas do
            orquestrador, o outro consumo real. Nao se somam. A fonte e a
            mais completa disponivel (OTel > hook de spawn). */}
        <KpiCard
          label={tokens.source === 'agent' ? 'Tokens de subagente' : 'Tokens medidos'}
          value={tokens.tokens != null ? fmtTokens(tokens.tokens) : '—'}
          trend={tokenCoverageLabel(tokens, otelUsage, agentUsage)}
          accent={tokens.tokens != null ? 'accent' : undefined}
        />
        {passRate != null && passRate >= 0.8 ? (
          <KpiCard label="Test pass rate" value={fmtPct(passRate)} trend="media do periodo" accent="success" />
        ) : passRate != null ? (
          <KpiCard label="Test pass rate" value={fmtPct(passRate)} trend="media do periodo" accent="warning" />
        ) : (
          <KpiCard label="Test pass rate" value={fmtPct(passRate)} trend="media do periodo" />
        )}
        <KpiCard
          label="Latencia humana p50"
          value={fmtDur(latP50)}
          trend="tempo de resposta a bloqueios"
        />
        {autoResolve != null && autoResolve >= 0.7 ? (
          <KpiCard label="Auto-resolve clarify" value={fmtPct(autoResolve)} trend={isApproximate ? 'derivada/aproximada' : 'score>=2 vs escalados'} accent="success" />
        ) : (
          <KpiCard label="Auto-resolve clarify" value={fmtPct(autoResolve)} trend={isApproximate ? 'derivada/aproximada' : 'score>=2 vs escalados'} />
        )}
      </div>

      {/* ─── Consumo de subagentes (schema v10 — wave-token-metrics) ───────
          Diferente de todo o resto desta tela: nao e proxy nem derivacao. O
          harness mede o uso de cada spawn, o hook do cstk grava e o ingest
          agrega por onda. O que continua sendo honestidade obrigatoria e a
          COBERTURA: spawns em background nao reportam uso, entao todo total
          aparece com "N de M spawns medidos". */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: 16 }}>
        <MetricCard
          name="agent-usage"
          title="Consumo de subagentes · medido"
          subtitle="tokens reportados pelo harness · não é proxy"
          period={period}
          renderContent={(raw) => (
            <AgentUsagePanel usage={raw as AgentUsageRollup | null} columns={4} />
          )}
        />

        <MetricCard
          name="otel-usage"
          title="Custo real · telemetria OTel"
          subtitle="USD medido pelo Claude Code · cobre main + subagente"
          period={period}
          emptyFallback={<OtelUsageEmpty />}
          renderContent={(raw) => (
            <OtelUsagePanel usage={raw as OtelUsageRollup | null} columns={4} />
          )}
        />

        <MetricCard
          name="otel-cost-over-time"
          title="Custo no tempo · real"
          subtitle="soma diária em USD · dias sem telemetria não aparecem"
          period={period}
          emptyFallback={<OtelUsageEmpty />}
          renderContent={(raw) => {
            const rows = Array.isArray(raw) ? (raw as Record<string, unknown>[]) : [];
            if (rows.length === 0) return <OtelUsageEmpty />;
            const series: TimeSeriesPoint[] = rows.map(r => ({
              d: (r.day as string | null) ?? '',
              value: (r.costUsd as number | null) ?? 0,
            }));
            const totalUsd = sum(nums(raw, 'costUsd'));
            const subUsd = sum(nums(raw, 'costSubagentUsd'));
            const share = totalUsd > 0 ? subUsd / totalUsd : null;
            return (
              <>
                <AreaChart data={series} color="var(--info)" height={140} label="USD / dia" />
                <div style={{ fontSize: 10.5, color: 'var(--text-3)', fontFamily: 'var(--font-mono)', marginTop: 4 }}>
                  {series.length} dia(s) com telemetria · {fmtUsd(totalUsd)} no período
                  {share != null && ` · ${fmtPct(share)} em subagentes`}
                </div>
              </>
            );
          }}
        />

        <MetricCard
          name="tokens-over-time"
          title="Tokens no tempo · medido"
          subtitle="soma diária dos spawns com dado de uso"
          period={period}
          emptyFallback={<AgentUsageEmpty usage={agentUsage} />}
          renderContent={(raw) => {
            const rows = Array.isArray(raw) ? (raw as Record<string, unknown>[]) : [];
            if (rows.length === 0) return <AgentUsageEmpty usage={agentUsage} />;
            const series: TimeSeriesPoint[] = rows.map(r => ({
              d: (r.day as string | null) ?? '',
              value: (r.totalTokens as number | null) ?? 0,
            }));
            const totalCache = sum(nums(raw, 'cacheReadTokens'));
            const totalTokens = sum(nums(raw, 'totalTokens'));
            const cacheShare = totalTokens > 0 ? totalCache / totalTokens : null;
            return (
              <>
                <AreaChart data={series} color="var(--accent)" height={140} label="tokens / dia" />
                <div style={{ fontSize: 10.5, color: 'var(--text-3)', fontFamily: 'var(--font-mono)', marginTop: 4 }}>
                  {series.length} dia(s) com medição · dias sem medição não entram como zero
                  {cacheShare != null && ` · ${fmtPct(cacheShare)} de cache read`}
                </div>
              </>
            );
          }}
        />
      </div>

      {/* Ondas mais caras em token medido */}
      <div style={{ display: 'grid', gridTemplateColumns: '1fr', gap: 16 }}>
        <MetricCard
          name="tokens-by-wave"
          title="Ondas mais caras · tokens medidos"
          subtitle="top 20 por consumo de subagente"
          period={period}
          emptyFallback={<AgentUsageEmpty usage={agentUsage} />}
          renderContent={(raw) => {
            const rows = Array.isArray(raw) ? (raw as Record<string, unknown>[]) : [];
            if (rows.length === 0) return <AgentUsageEmpty usage={agentUsage} />;
            const max = Math.max(...rows.map(r => (r.totalTokens as number | null) ?? 0), 1);
            return (
              <div className="col gap-2">
                {rows.map((r, i) => {
                  const tokens = (r.totalTokens as number | null) ?? 0;
                  const spawnsTotal = r.spawnsTotal as number | null;
                  const spawnsWithUsage = r.spawnsWithUsage as number | null;
                  const partial = spawnsTotal != null && spawnsWithUsage != null && spawnsWithUsage < spawnsTotal;
                  return (
                    <div key={`${String(r.executionId)}-${String(r.wave)}-${i}`} style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                      <div style={{ width: 170, fontSize: 10.5, color: 'var(--text-2)', fontFamily: 'var(--font-mono)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', flexShrink: 0 }}>
                        {String(r.feature ?? '?')} · {String(r.wave ?? '?')}
                      </div>
                      <div style={{ flex: 1, height: 8, background: 'var(--bg-3)', borderRadius: 3, overflow: 'hidden' }}>
                        <div style={{ width: `${(tokens / max) * 100}%`, height: '100%', background: 'var(--accent)', borderRadius: 3 }} />
                      </div>
                      <span
                        title={partial ? `${spawnsWithUsage} de ${spawnsTotal} spawns reportaram uso` : undefined}
                        style={{ width: 96, textAlign: 'right', fontFamily: 'var(--font-mono)', fontSize: 11, color: 'var(--text-1)', flexShrink: 0 }}
                      >
                        {fmtTokens(tokens)}{partial ? ' *' : ''}
                      </span>
                    </div>
                  );
                })}
                <div style={{ fontSize: 10.5, color: 'var(--text-3)', fontFamily: 'var(--font-mono)' }}>
                  * total parcial — parte dos spawns da onda não reportou uso
                </div>
              </div>
            );
          }}
        />
      </div>

      {/* Custo/tokens por modelo — detalhe completo (schema v12, wave_model_usage).
          Consome o MESMO modulo puro (lib/model-usage-select.ts) do KPI compacto
          do Overview — garante SC-005 (mesmos valores nas duas telas). */}
      <div style={{ display: 'grid', gridTemplateColumns: '1fr', gap: 16 }}>
        <MetricCard
          name="model-usage"
          title="Custo por modelo · detalhe"
          subtitle="medido (wave_model_usage) · por modelo e por etapa"
          period={period}
          renderContent={(raw) => {
            const result = raw as ModelUsageResult | null;
            const vm = selectModelUsage(result);
            const stageGroups = groupModelUsageByStage(result?.byStage);
            return <ModelUsageDetailPanel vm={vm} stageGroups={stageGroups} />;
          }}
        />
      </div>

      {/* Consumo avulso — sessões interativas fora do pipeline (schema v13,
          loose_usage, cstk 6.6.0). Captura opt-in: "sem linhas" = sem medição,
          nunca "sem consumo". Inclui comparação avulso × pipeline. */}
      <div style={{ display: 'grid', gridTemplateColumns: '1fr', gap: 16 }}>
        <MetricCard
          name="loose-usage"
          title="Consumo avulso · fora do pipeline"
          subtitle="medido (loose_usage) · sessões interativas comuns · avulso × pipeline"
          period={period}
          renderContent={(raw) => {
            const vm = selectLooseUsage(raw as LooseUsageResult | null);
            return <LooseUsageDetailPanel vm={vm} />;
          }}
        />
      </div>

      {/* Cota do plano (schema v14, plan_usage, cstk 7.2.0). Eixo distinto de
          todo o resto desta tela: não é esforço, dinheiro nem token — é quanto
          da cota da CONTA já foi gasto em cada janela. Captura opt-in via
          `cstk statusline install`: sem hook não há medição, e ausência de
          captura nunca é renderizada como 0%. */}
      <div style={{ display: 'grid', gridTemplateColumns: '1fr', gap: 16 }}>
        <MetricCard
          name="plan-usage"
          title="Cota do plano · por janela"
          subtitle="medido (plan_usage) · janelas de 5h e 7d · gauge da conta, não do projeto"
          period={period}
          emptyFallback={<PlanUsageEmpty reason="degraded" />}
          renderContent={(raw) => {
            const vm = selectPlanUsage(raw as PlanUsageResult | null);
            // `nowMs` injetado aqui (e nao lido dentro do modulo puro) para que
            // o calculo de "reseta em" continue testavel sem mockar relogio.
            return <PlanUsageDetailPanel vm={vm} nowMs={Date.now()} />;
          }}
        />
      </div>

      {/* Grid de metricas 2x4 */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: 16 }}>

        {/* 1. cost-over-time */}
        <MetricCard
          name="cost-over-time"
          title="Custo no tempo · proxy"
          subtitle="proxy: tool calls por dia"
          period={period}
          renderContent={(raw) => {
            const data: TimeSeriesPoint[] = Array.isArray(raw)
              ? (raw as Record<string, unknown>[]).map(r => ({
                  value: (r.toolCalls as number | null) ?? 0,
                }))
              : [];
            return (
              <>
                <AreaChart data={data} color="var(--accent)" height={140} label="tool_calls / dia (proxy — nao tokens)" />
                <div style={{ fontSize: 10.5, color: 'var(--text-3)', fontFamily: 'var(--font-mono)', marginTop: 4 }}>
                  {data.length} pontos · eixo-y = proxy: tool calls · nao $ / tokens
                </div>
              </>
            );
          }}
        />

        {/* 2. test-pass-rate-series — area 14d (CARD-MT-03) */}
        <MetricCard
          name="test-pass-rate-series"
          title="Test pass rate · 14d"
          subtitle="% de testes passando por dia"
          period={period}
          renderContent={(raw) => {
            const rows = Array.isArray(raw) ? (raw as Record<string, unknown>[]) : [];
            const series: TimeSeriesPoint[] = rows.map(r => ({
              d: (r.day as string | null) ?? '',
              value: ((r.rate as number | null) ?? 0) * 100,
            }));
            const totalPass = sum(nums(raw, 'pass'));
            const totalFail = sum(nums(raw, 'fail'));
            return (
              <>
                <AreaChart data={series} color="var(--success)" height={160} label="% por dia" />
                <div style={{ fontSize: 10.5, color: 'var(--text-3)', fontFamily: 'var(--font-mono)', marginTop: 4 }}>
                  {series.length} dias · {totalPass} pass · {totalFail} fail
                </div>
              </>
            );
          }}
        />

        {/* 3. throughput-by-stage — top-10 + "Outros" (FASE 5, FR-006/007/008, SC-002) */}
        <MetricCard
          name="throughput-by-stage"
          title="Throughput por etapa"
          subtitle="contagem de decisoes por etapa SDD"
          renderContent={(raw) => {
            // getThroughputByStage (apps/server/src/db/queries/metrics.ts) ja
            // retorna { stage, count }[] ordenado por count DESC.
            const arr = Array.isArray(raw)
              ? (raw as Record<string, unknown>[]).map(r => ({
                  label: (r.stage as string | null) ?? '?',
                  value: (r.count as number | null) ?? 0,
                }))
              : [];
            const { bars, othersLabel, othersMembers } = truncateBars(arr);
            return <TruncatedBarH bars={bars} othersLabel={othersLabel} othersMembers={othersMembers} />;
          }}
        />

        {/* 4. human-latency */}
        <MetricCard
          name="human-latency"
          title="Latencia humana"
          subtitle="tempo de resposta a bloqueios"
          period={period}
          renderContent={(raw) => {
            const lat = nums(raw, 'latencySeconds');
            if (!lat.length) return null;
            return (
              <>
                <Histogram values={lat} bins={8} height={140} color="var(--info)" unit="s" />
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 12, marginTop: 8 }}>
                  {[
                    { label: 'p50', value: fmtDur(percentile(lat, 50)) },
                    { label: 'p95', value: fmtDur(percentile(lat, 95)) },
                    { label: 'max', value: fmtDur(maxOf(lat)) },
                  ].map(s => (
                    <div key={s.label} style={{ textAlign: 'center' }}>
                      <div style={{ fontSize: 10, color: 'var(--text-3)', textTransform: 'uppercase', letterSpacing: '0.07em', marginBottom: 2 }}>{s.label}</div>
                      <div style={{ fontFamily: 'var(--font-mono)', fontSize: 16, fontWeight: 700, color: 'var(--text-0)' }}>{s.value}</div>
                    </div>
                  ))}
                </div>
              </>
            );
          }}
        />

        {/* 5. clarify-resolution — com badge "derivada/aproximada" */}
        <MetricCard
          name="clarify-resolution"
          title="Clarify auto-resolution"
          subtitle="score>=2 vs escalados a humano"
          period={period}
          renderContent={(raw, { approximate }) => {
            const d = raw as Record<string, unknown> | null;
            if (!d) return null;
            const autoRate = (d.rate as number | null);
            return (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
                {approximate && (
                  <div style={{ display: 'flex', alignItems: 'center', gap: 6, padding: '6px 10px', background: 'var(--warning-soft)', borderRadius: 'var(--r-xs)', border: '1px solid rgba(245,158,11,0.25)' }}>
                    <Icon name="alert" size={12} style={{ color: 'var(--warning)' }} />
                    <span style={{ fontSize: 11.5, color: 'var(--warning)', fontFamily: 'var(--font-mono)' }}>
                      metrica derivada/aproximada
                    </span>
                  </div>
                )}
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: 12 }}>
                  {[
                    { label: 'Auto-resolvidas', value: String(d.autonomouslyResolved ?? '—'), color: 'var(--success)' },
                    { label: 'Escaladas', value: String(d.humanPaused ?? '—'), color: 'var(--warning)' },
                    { label: 'Taxa auto', value: fmtPct(autoRate), color: autoRate != null && autoRate >= 0.7 ? 'var(--success)' : 'var(--warning)' },
                    { label: 'Total clarify', value: String(d.totalClarifyDecisions ?? '—') },
                  ].map(s => (
                    <div key={s.label}>
                      <div style={{ fontSize: 10, color: 'var(--text-3)', textTransform: 'uppercase', letterSpacing: '0.07em', marginBottom: 2 }}>{s.label}</div>
                      <div style={{ fontFamily: 'var(--font-mono)', fontSize: 18, fontWeight: 700, color: s.color ?? 'var(--text-0)' }}>{s.value}</div>
                    </div>
                  ))}
                </div>
              </div>
            );
          }}
        />

        {/* 6. decisions-by-score */}
        <MetricCard
          name="decisions-by-score"
          title="Decisoes por score"
          subtitle="distribuicao 0..3 de autonomia"
          period={period}
          renderContent={(raw) => {
            const arr = Array.isArray(raw)
              ? (raw as Record<string, unknown>[])
              : Object.entries(raw as Record<string, unknown>).map(([k, v]) => ({ score: parseInt(k), count: v, value: v }));
            const max = Math.max(...arr.map(d => ((d.count ?? d.value ?? 0) as number)), 1);
            const COLORS = ['var(--score-0)', 'var(--score-1)', 'var(--score-2)', 'var(--score-3)'];
            return (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                {arr.map((d) => {
                  const rawScore = d.score as number | null;
                  const hasScore = rawScore != null && !Number.isNaN(rawScore);
                  const count = ((d.count ?? (d as Record<string, unknown>).value) as number | null) ?? 0;
                  const color = (hasScore ? COLORS[rawScore] : undefined) ?? 'var(--text-2)';
                  return (
                    <div key={hasScore ? rawScore : 'sem-score'} style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                      <span style={{
                        width: 20, height: 20, borderRadius: 4, fontSize: 11, fontWeight: 700,
                        display: 'flex', alignItems: 'center', justifyContent: 'center',
                        fontFamily: 'var(--font-mono)', background: `${color}22`, color,
                        flexShrink: 0,
                      }}>
                        {hasScore ? rawScore : '—'}
                      </span>
                      <div style={{ flex: 1, height: 8, background: 'var(--bg-3)', borderRadius: 3, overflow: 'hidden' }}>
                        <div style={{ width: `${(count / max) * 100}%`, height: '100%', background: color, borderRadius: 3 }} />
                      </div>
                      <span style={{ width: 30, textAlign: 'right', fontFamily: 'var(--font-mono)', fontSize: 12, color: 'var(--text-0)', fontWeight: 600, flexShrink: 0 }}>
                        {count}
                      </span>
                    </div>
                  );
                })}
              </div>
            );
          }}
        />

        {/* 7. execution-duration */}
        <MetricCard
          name="execution-duration"
          title="Duracao das execucoes"
          subtitle="distribuicao de wallclock_segundos"
          period={period}
          renderContent={(raw) => {
            const dur = nums(raw, 'durationSeconds');
            if (!dur.length) return null;
            const m = mean(dur);
            return (
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 12 }}>
                {[
                  { label: 'p50', value: fmtDur(percentile(dur, 50)) },
                  { label: 'p95', value: fmtDur(percentile(dur, 95)) },
                  { label: 'max', value: fmtDur(maxOf(dur)) },
                  { label: 'media', value: fmtDur(m != null ? Math.round(m) : null) },
                  { label: 'execucoes', value: String(dur.length) },
                ].map(s => (
                  <div key={s.label}>
                    <div style={{ fontSize: 10, color: 'var(--text-3)', textTransform: 'uppercase', letterSpacing: '0.07em', marginBottom: 2 }}>{s.label}</div>
                    <div style={{ fontFamily: 'var(--font-mono)', fontSize: 15, fontWeight: 700, color: 'var(--text-0)' }}>{s.value}</div>
                  </div>
                ))}
              </div>
            );
          }}
        />

        {/* 8. depth-subagents — disponivel */}
        <MetricCard
          name="depth-subagents"
          title="Profundidade de subagentes"
          subtitle="distribuicao de profundidade_max e subagentes_spawned"
          period={period}
          renderContent={(raw) => {
            const rows = Array.isArray(raw) ? (raw as Record<string, unknown>[]) : [];
            const points: ScatterDatum[] = rows
              .map(r => ({
                x: (r.maxDepth as number | null) ?? 0,
                y: (r.subagentsSpawned as number | null) ?? 0,
                color: 'var(--accent)',
              }))
              .filter(p => p.x > 0 || p.y > 0);
            const depth = nums(raw, 'maxDepth');
            const spawned = nums(raw, 'subagentsSpawned');
            if (!points.length) return null;
            const avgDepth = mean(depth);
            const avgSpawned = mean(spawned);
            return (
              <>
                <ScatterChart data={points} height={180} xLabel="profundidade" yLabel="subagentes" />
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: 12, marginTop: 8 }}>
                  {[
                    { label: 'Prof. media', value: avgDepth != null ? avgDepth.toFixed(1) : '—' },
                    { label: 'Prof. maxima', value: String(maxOf(depth) ?? '—') },
                    { label: 'Spawns media', value: avgSpawned != null ? avgSpawned.toFixed(1) : '—' },
                    { label: 'Spawns total', value: String(sum(spawned)) },
                  ].map(s => (
                    <div key={s.label}>
                      <div style={{ fontSize: 10, color: 'var(--text-3)', textTransform: 'uppercase', letterSpacing: '0.07em', marginBottom: 2 }}>{s.label}</div>
                      <div style={{ fontFamily: 'var(--font-mono)', fontSize: 18, fontWeight: 700, color: 'var(--text-0)' }}>{s.value}</div>
                    </div>
                  ))}
                </div>
              </>
            );
          }}
        />
      </div>

      {/* Mix de modelos — DERIVADO das decisoes de roteamento (D3 revisado 2026-05-25) */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: 16 }}>
        {/* Mix total (donut) */}
        <MetricCard
          name="model-mix"
          title="Mix de modelos · total"
          subtitle="intenção do roteador · derivado · canônico: model-routing-report.sh"
          renderContent={(raw) => {
            const rows = Array.isArray(raw) ? (raw as Record<string, unknown>[]) : [];
            const donut: DonutDatum[] = rows.map(r => ({
              label: (r.modelo as string | null) ?? '?',
              value: (r.n as number | null) ?? 0,
              color: modelColor((r.modelo as string | null) ?? ''),
            }));
            const total = donut.reduce((a, d) => a + d.value, 0);
            if (total === 0) return null;
            return (
              <div className="row" style={{ gap: 16, alignItems: 'center' }}>
                <Donut data={donut} size={130} thickness={20} centerLabel="decisões" centerValue={String(total)} />
                <div className="col" style={{ flex: 1, gap: 6 }}>
                  {donut.map(m => (
                    <div key={m.label} className="row" style={{ justifyContent: 'space-between' }}>
                      <div className="row gap-2">
                        <span style={{ width: 8, height: 8, borderRadius: 2, background: m.color }} />
                        <span className="mono" style={{ fontSize: 11.5 }}>{m.label}</span>
                      </div>
                      <span className="mono" style={{ fontSize: 12, color: 'var(--text-0)' }}>{fmtPct(m.value / total)}</span>
                    </div>
                  ))}
                </div>
              </div>
            );
          }}
        />

        {/* Mix por etapa (empilhado) */}
        <MetricCard
          name="model-mix-by-stage"
          title="Mix de modelos por etapa"
          subtitle="intenção do roteador · derivado"
          renderContent={(raw) => {
            const rows = Array.isArray(raw) ? (raw as Record<string, unknown>[]) : [];
            if (rows.length === 0) return null;
            const models = sortModels(Array.from(new Set(rows.map(r => (r.modelo as string | null) ?? '?'))));
            // FASE 6 (US4/FR-009): agrupa por `r.stage` (campo real do payload —
            // `r.etapa` nunca existiu, ver model-mix-by-stage-select.ts) e ordena
            // pela ordem canonica de SDD_STAGES, nao por volume.
            const data = buildStageBars(rows);
            const colors = models.map(modelColor);
            return (
              <>
                <Legend items={models.map((m, i) => ({ color: colors[i] ?? 'var(--model-fallback)', label: m }))} />
                <div style={{ marginTop: 8 }}>
                  {/* Horizontal: a categoria aqui e o nome da etapa (texto), nao
                      tempo — cabe inteiro na coluna de rotulos e sobrevive ao
                      caso em que uma etapa domina toda a escala. */}
                  <StackedBarsH data={data} keys={models} colors={colors} />
                </div>
              </>
            );
          }}
        />
      </div>

      {/* Consultas ao histórico — read-back loop (schema v3, evento recall_consulted) */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: 16 }}>
        <MetricCard
          name="recall-consultations"
          title="Consultas ao histórico"
          subtitle="read-back loop · contagem exata (não proxy)"
          renderContent={(raw) => {
            const d = raw as Record<string, unknown> | null;
            if (!d) return null;
            const total = (d.total as number | null) ?? 0;
            const produtivas = (d.produtivas as number | null) ?? 0;
            const vazias = (d.vazias as number | null) ?? 0;
            const taxa = total > 0 ? produtivas / total : null;
            return (
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: 12 }}>
                {[
                  { label: 'Total', value: String(total) },
                  { label: 'Taxa produtiva', value: fmtPct(taxa), color: taxa != null && taxa >= 0.5 ? 'var(--success)' : 'var(--warning)' },
                  { label: 'Produtivas · hits>0', value: String(produtivas), color: 'var(--success)' },
                  { label: 'Vazias · hits=0', value: String(vazias), color: vazias > 0 ? 'var(--text-2)' : undefined },
                ].map(s => (
                  <div key={s.label}>
                    <div style={{ fontSize: 10, color: 'var(--text-3)', textTransform: 'uppercase', letterSpacing: '0.07em', marginBottom: 2 }}>{s.label}</div>
                    <div style={{ fontFamily: 'var(--font-mono)', fontSize: 18, fontWeight: 700, color: s.color ?? 'var(--text-0)' }}>{s.value}</div>
                  </div>
                ))}
              </div>
            );
          }}
        />
      </div>
    </div>
  );
}
