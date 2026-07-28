/**
 * Overview — tela Visao Geral (US1). Layout pixel-perfect do prototipo
 * (docs/06-ui-ux-design/castk-panel/project/screens_main.jsx · OverviewScreen).
 *
 * Consome useOverview(period) — dados reais da knowledge.db.
 * 4 estados: loading/empty/error/degraded (US6, FR-006).
 *
 * Principio III (Honestidade de Metrica): o custo do ORQUESTRADOR continua
 * sendo o proxy "tool calls" — nunca "$". Desde o schema v10 existe tambem o
 * consumo MEDIDO dos subagentes (tokens), exibido com a cobertura da amostra
 * ("N de M spawns medidos"); as duas metricas convivem e NAO se somam.
 * Nenhuma delas vira valor monetario. Mix de modelos e DERIVADO de decisoes
 * de roteamento logadas (FR-010) — rotulado como tal.
 *
 * Ref: spec.md §User Story 1; constitution §III, §IV
 */
import { useNavigate } from 'react-router-dom';
import { useOverview, useMetric } from '@/lib/hooks.js';
import { useApiState } from '@/hooks/useApiState.js';
import { LoadingState, EmptyState, ErrorState, DegradedBanner } from '@/states/index.js';
import {
  KpiCard, StatusBadge, SeverityBadge, BudgetMini, PipelineProgress,
  Donut, Icon, MiniStat,
  agentUsageState, coverageLabel, fmtUsd, subagentCostShare,
  ModelUsageMiniList,
} from '@/components/index.js';
import type { DonutDatum } from '@/components/index.js';
import { selectOverview, type OverviewRaw } from '@/lib/overview-select.js';
import { selectModelUsage } from '@/lib/model-usage-select.js';
import type { ModelUsageResult } from '@cstk-panel/shared-types';
import { fmtNum, fmtDur, fmtPct, fmtRelative, fmtTokens } from '@/lib/format.js';
import type { PeriodParam } from '@cstk-panel/shared-types';

interface OverviewProps {
  period: PeriodParam;
  /** Filtro global de projeto ('' = todos). Escopa todas as métricas. */
  project?: string;
}

// ---------------------------------------------------------------------------
// Helpers locais
// ---------------------------------------------------------------------------
/** Rotulo de feature; cai para id curto da execucao quando 'unknown'/ausente. */
function featureLabel(feature: unknown, execId: unknown): string {
  const f = feature as string | null;
  if (f && f !== 'unknown') return f;
  const e = execId as string | null;
  return e ? e.slice(0, 22) + '…' : '—';
}

const MODEL_COLOR: Record<string, string> = {
  haiku: 'var(--model-haiku)',
  sonnet: 'var(--model-sonnet)',
  opus: 'var(--model-opus)',
};
function modelColor(m: string): string {
  return MODEL_COLOR[m] ?? 'var(--model-fallback)';
}

/** Severidade derivada (rotulada): breach acima do teto = critico; senao atencao. */
function deriveSeverity(a: Record<string, unknown>): 'critical' | 'warning' {
  const consumido = a.consumedValue as number | null;
  const threshold = a.thresholdValue as number | null;
  if (a.type === 'budget_breach' && consumido != null && threshold != null && consumido > threshold) {
    return 'critical';
  }
  return 'warning';
}

const EVENT_COLOR: Record<string, string> = {
  lock_contention: 'var(--critical)',
  validation_failed: 'var(--warning)',
  wave_retry: 'var(--info)',
  schedule_wait: 'var(--inprogress)',
};

// ---------------------------------------------------------------------------
export function Overview({ period, project = '' }: OverviewProps) {
  const navigate = useNavigate();
  const query = useOverview(period, project);
  // Custo/tokens REAIS por modelo (schema v12, wave_model_usage) — endpoint
  // dedicado (FASE 2), fora do payload de /overview. Hook chamado
  // incondicionalmente (regra dos hooks do React), antes dos retornos
  // antecipados de loading/error/empty abaixo.
  const modelUsageQuery = useMetric('model-usage', period);
  const { isLoading, isEmpty, isError, errorMessage, isDegraded } = useApiState(query);

  if (isLoading) return <LoadingState variant="kpi" />;
  if (isError) return <ErrorState message={errorMessage ?? 'Erro ao carregar dados.'} />;
  if (isEmpty) return <EmptyState title="Nenhuma execucao registrada" subtitle="Execute o orquestrador para ver dados aqui." />;

  const raw = query.data?.data as Record<string, unknown> | null;
  const meta = query.data?.meta;

  const vm = selectOverview(raw as OverviewRaw | null);
  const {
    totalProjects, totalFeatures, emAndamento, aguardando, totalToolCalls,
    totalWallclock, testsPassed, testsTotal, totalAlertas,
    execucoes, alertas, modelMix, recentActivity,
    costSeries, agentUsage, tokenSeries, otelUsage, otelCostSeries,
  } = vm;
  const hasMeasuredTokens = agentUsageState(agentUsage) === 'measured';
  // Telemetria OTel (schema v11): fonte independente e mais completa — cobre
  // o gasto do proprio orquestrador, que o hook de spawn nunca enxerga.
  // Preferida quando presente; agentUsage vira fallback.
  const hasOtel = otelUsage != null && otelUsage.costUsd != null;
  const otelCoverage = hasOtel && otelUsage.wavesTotal
    ? `${otelUsage.wavesWithOtel ?? 0}/${otelUsage.wavesTotal} ondas medidas`
    : null;
  const share = subagentCostShare(otelUsage);
  const subagentShare = share != null ? Math.round(share * 100) : null;

  // KPIs derivados
  const nCriticos = (alertas as Record<string, unknown>[]).filter(a => deriveSeverity(a) === 'critical').length;
  const passRate = testsTotal && testsTotal > 0 ? (testsPassed ?? 0) / testsTotal : null;

  // Mix de modelos (derivado)
  const mixTotal = modelMix.reduce((a, m) => a + (m.n ?? 0), 0);
  const donutData: DonutDatum[] = modelMix.map(m => ({
    label: m.model ?? '?', value: m.n ?? 0, color: modelColor(m.model ?? ''),
  }));

  // Resumo compacto de custo por modelo (US1; dec-038/CHK005 — top-3 por
  // costUsd). View-model unico (lib/model-usage-select.ts) compartilhado com
  // o detalhe completo de Metricas (FASE 3.3, ainda nao implementada) —
  // garante SC-005 (mesmos valores nas duas telas).
  const modelUsageRaw = modelUsageQuery.data?.data as ModelUsageResult | null | undefined;
  const modelUsageVm = selectModelUsage(modelUsageRaw);

  return (
    <div className="col gap-4">
      {isDegraded && meta && <DegradedBanner meta={meta} />}

      {/* Cabecalho da pagina */}
      <div className="page-head">
        <div>
          <h1>Visão Geral</h1>
          <div className="sub">panorama do orquestrador · execuções, custo, alertas e qualidade</div>
        </div>
      </div>

      {/* KPI row — 7 cards (o de tokens entrou com o schema v10) */}
      <div className="grid-7">
        <KpiCard label="Projetos ativos" value={totalProjects} icon="folder" footnote={`${totalFeatures} features`} />
        <KpiCard
          label="Em andamento"
          value={emAndamento}
          icon="activity"
          footnote={`${aguardando} aguardando humano`}
          accent="accent"
        />
        <KpiCard
          label="Alertas críticos"
          value={totalAlertas}
          icon="alert"
          footnote={`${nCriticos} crítico${nCriticos !== 1 ? 's' : ''}`}
          accent={nCriticos > 0 ? 'critical' : totalAlertas > 0 ? 'warning' : undefined}
        />
        {/* Custo. Com telemetria OTel (schema v11) o card exibe o valor REAL em
            USD — calculado pelo Claude Code, apenas somado aqui. Sem ela, cai
            para o proxy de tool_calls, e o rótulo muda junto: "$" e "proxy"
            nunca aparecem no mesmo card (Princípio III). */}
        {hasOtel ? (
          <KpiCard
            label="Custo · real"
            value={fmtUsd(otelUsage.costUsd)}
            icon="bolt"
            footnote={subagentShare != null
              ? `${fmtUsd(otelUsage.costSubagentUsd)} em subagentes (${subagentShare}%)`
              : (otelCoverage ?? 'telemetria OTel')}
            tip={`Custo medido pela telemetria OTel do Claude Code, somado por onda. Loop principal ${fmtUsd(otelUsage.costMainUsd)} · subagentes ${fmtUsd(otelUsage.costSubagentUsd)}. Cobertura: ${otelCoverage ?? 'não informada'} — ondas sem telemetria não somam.`}
            spark={otelCostSeries}
            sparkColor="var(--accent)"
          />
        ) : (
          <KpiCard
            label="Custo · proxy"
            value={fmtNum(totalToolCalls)}
            icon="bolt"
            footnote="tool_calls totais"
            tip="Chamadas de ferramenta do orquestrador — proxy auditável de esforço. Não é token nem custo monetário. Custo real em USD exige knowledge.db v11 (cstk ≥ 5.30.0) com telemetria ligada."
            spark={costSeries}
            sparkColor="var(--accent)"
          />
        )}
        {/* Consumo MEDIDO dos subagentes (schema v10). Amostra: spawns em
            background não reportam uso, por isso o rodapé traz a cobertura. */}
        <KpiCard
          label="Tokens · subagentes"
          value={hasOtel
            ? fmtTokens(otelUsage.subagentTokens)
            : hasMeasuredTokens ? fmtTokens(agentUsage?.totalTokens) : '—'}
          icon="cpu"
          footnote={hasOtel
            ? (otelCoverage ?? 'telemetria OTel')
            : hasMeasuredTokens ? coverageLabel(agentUsage) : 'não coletado nesta fonte'}
          tip={hasOtel
            ? 'Tokens de subagentes medidos pela telemetria OTel do Claude Code (label query_source=subagent). Contadores incrementados a cada requisição, então cobrem também o consumo do próprio orquestrador.'
            : hasMeasuredTokens
              ? 'Tokens reportados pelo harness para cada subagente e agregados por onda. Medição real, mas parcial: spawns em background não reportam uso.'
              : 'Exige knowledge.db em schema v11 (cstk ≥ 5.30.0 para a ingestão) e telemetria ligada durante a execução: CLAUDE_CODE_ENABLE_TELEMETRY=1 + OTEL_METRICS_EXPORTER=prometheus.'}
          spark={tokenSeries}
          sparkColor="var(--info)"
        />
        <KpiCard
          label="Tempo de parede"
          value={fmtDur(totalWallclock)}
          icon="clock"
          footnote="wallclock acumulado"
        />
        <KpiCard
          label="Test pass rate"
          value={passRate != null ? fmtPct(passRate, 1) : '—'}
          icon="check"
          footnote={testsTotal != null ? `${fmtNum(testsPassed)} / ${fmtNum(testsTotal)} testes` : 'sem testes'}
          accent={passRate != null && passRate >= 0.99 ? 'success' : passRate != null && passRate < 0.9 ? 'warning' : undefined}
        />
      </div>

      {/* Grid principal 2fr / 1fr */}
      <div className="grid-overview">
        {/* Coluna esquerda */}
        <div className="col gap-4" style={{ minWidth: 0 }}>

          {/* Execucoes em andamento */}
          <div className="card">
            <div className="card-head">
              <div className="row gap-2">
                <h3>Execuções em andamento</h3>
                <span className="tag">{execucoes.length}</span>
              </div>
              <span className="muted hover-link" style={{ cursor: 'pointer', fontSize: 11.5 }} onClick={() => navigate('/executions')}>ver todas →</span>
            </div>
            <div className="col" style={{ padding: 12, gap: 10 }}>
              {execucoes.length === 0 ? (
                <div style={{ padding: '16px 0', textAlign: 'center', color: 'var(--text-3)', fontSize: 12 }}>
                  O orquestrador está ocioso.
                </div>
              ) : (
                (execucoes as Record<string, unknown>[]).map((f, idx) => {
                  const execId = (f.executionId as string | null) ?? '';
                  const status = f.status as 'em_andamento' | 'aguardando_humano' | 'concluida' | 'abortada' | null;
                  const etapa = f.currentStage as string | null;
                  const project = f.project as string | null;
                  const feature = f.feature as string | null;
                  const title = featureLabel(feature, execId);
                  return (
                    <div
                      key={execId || idx}
                      style={{ background: 'var(--bg-2)', borderRadius: 'var(--r-sm)', border: '1px solid var(--border)', padding: '10px 12px', cursor: 'pointer' }}
                      onClick={() => navigate(`/executions/${encodeURIComponent(execId)}`)}
                    >
                      <div className="row" style={{ justifyContent: 'space-between', marginBottom: 8 }}>
                        <div style={{ minWidth: 0 }}>
                          <div className="row gap-2" style={{ marginBottom: 2 }}>
                            <StatusBadge status={status} />
                            <span style={{ fontWeight: 600, fontSize: 13 }}>{title}</span>
                          </div>
                          <div className="prov">
                            <span>{project ?? '—'}</span>
                            <span className="sep">·</span>
                            <span>{execId.slice(0, 38)}…</span>
                          </div>
                        </div>
                        <div className="row gap-3" style={{ flexShrink: 0 }}>
                          <MiniStat label="tool_calls" value={fmtNum(f.toolCallsTotal as number | null)} align="end" />
                          <MiniStat label="wallclock" value={fmtDur(f.wallclockTotalSeconds as number | null)} align="end" />
                          <MiniStat label="ondas" value={String(f.wavesTotal ?? '—')} align="end" />
                        </div>
                      </div>
                      <PipelineProgress etapa={etapa} status={status} />
                      <div className="row" style={{ justifyContent: 'space-between', marginTop: 6 }}>
                        <span className="muted" style={{ fontSize: 11 }}>
                          etapa corrente · <span className="mono" style={{ color: 'var(--inprogress)' }}>{etapa ?? '—'}</span>
                        </span>
                        <span className="muted" style={{ fontSize: 11 }}>iniciada {fmtRelative(f.startedAt as string | null)}</span>
                      </div>
                    </div>
                  );
                })
              )}
            </div>
          </div>

          {/* Alertas criticos recentes */}
          <div className="card">
            <div className="card-head">
              <div className="row gap-2">
                <h3>Alertas críticos recentes</h3>
                {alertas.length > 0 && (
                  <span className="tag" style={{ background: 'var(--critical-soft)', color: 'var(--critical)', borderColor: 'transparent' }}>{alertas.length}</span>
                )}
              </div>
              <span className="muted hover-link" style={{ cursor: 'pointer', fontSize: 11.5 }} onClick={() => navigate('/alerts')}>ver todos →</span>
            </div>
            <div style={{ overflowX: 'auto' }}>
              <table className="tbl">
                <thead>
                  <tr>
                    <th>Tipo</th>
                    <th>Proveniência</th>
                    <th>Onda</th>
                    <th>Consumido / Threshold</th>
                    <th>Severidade</th>
                  </tr>
                </thead>
                <tbody>
                  {alertas.length === 0 ? (
                    <tr><td colSpan={5} style={{ textAlign: 'center', color: 'var(--text-3)', padding: 24 }}>Nenhum alerta recente.</td></tr>
                  ) : (
                    (alertas as Record<string, unknown>[]).slice(0, 5).map((a, idx) => {
                      const tipo = a.type as string | null;
                      const subtipo = a.subtype as string | null;
                      const execId = a.executionId as string | null;
                      const wave = a.wave as string | null;
                      const consumido = a.consumedValue as number | null;
                      const threshold = a.thresholdValue as number | null;
                      const severity = deriveSeverity(a);
                      const isCircular = tipo === 'circular';
                      const validWave = wave && wave !== '-' ? wave : null;
                      return (
                        <tr key={idx} className="clickable" onClick={() => navigate(`/executions/${encodeURIComponent(execId ?? '')}?tab=alerts`)}>
                          <td>
                            <div className="row gap-2">
                              <Icon name={isCircular ? 'retry' : 'flame'} size={13} style={{ color: severity === 'critical' ? 'var(--critical)' : 'var(--warning)' }} />
                              <span className="mono" style={{ fontSize: 12, color: 'var(--text-0)' }}>
                                {isCircular ? 'movimento circular' : `breach · ${subtipo ?? '?'}`}
                              </span>
                            </div>
                          </td>
                          <td>
                            <span className="prov">
                              <span>{execId?.slice(0, 24) ?? '—'}…</span>
                            </span>
                          </td>
                          <td className="mono" style={{ fontSize: 11.5, color: validWave ? 'var(--inprogress)' : 'var(--text-3)' }}>{validWave ?? '—'}</td>
                          <td><BudgetMini value={consumido} threshold={threshold} unit={subtipo === 'wallclock' ? 's' : ''} /></td>
                          <td><SeverityBadge severity={severity} /></td>
                        </tr>
                      );
                    })
                  )}
                </tbody>
              </table>
            </div>
          </div>
        </div>

        {/* Coluna direita */}
        <div className="col gap-4">
          {/* Mix de modelos (derivado) */}
          <div className="card">
            <div className="card-head">
              <h3>Mix de modelos</h3>
              <span className="mono muted" style={{ fontSize: 11 }}>derivado · decisões</span>
            </div>
            <div className="card-pad">
              {mixTotal === 0 ? (
                <div style={{ color: 'var(--text-3)', fontSize: 12, textAlign: 'center', padding: '12px 0' }}>
                  indisponível nesta fonte · ver <span className="mono">model-routing-report.sh</span>
                </div>
              ) : (
                <div className="row" style={{ gap: 18 }}>
                  <Donut data={donutData} size={132} thickness={20} centerLabel="decisões" centerValue={String(mixTotal)} />
                  <div className="col" style={{ flex: 1, gap: 6 }}>
                    {donutData.map(m => (
                      <div key={m.label} className="row" style={{ justifyContent: 'space-between' }}>
                        <div className="row gap-2">
                          <span style={{ width: 8, height: 8, borderRadius: 2, background: m.color }} />
                          <span className="mono" style={{ fontSize: 11.5 }}>{m.label}</span>
                        </div>
                        <span className="mono" style={{ fontSize: 12, color: 'var(--text-0)' }}>{fmtPct(m.value / mixTotal)}</span>
                      </div>
                    ))}
                  </div>
                </div>
              )}
            </div>
          </div>

          {/* Custo por modelo — medido (schema v12, wave_model_usage) */}
          <div className="card">
            <div className="card-head">
              <h3>Custo por modelo</h3>
              <span className="mono muted" style={{ fontSize: 11 }}>medido · top-3</span>
            </div>
            <div className="card-pad">
              <ModelUsageMiniList vm={modelUsageVm} />
            </div>
          </div>

          {/* Atividade recente */}
          <div className="card">
            <div className="card-head">
              <h3>Atividade recente</h3>
              <span className="muted" style={{ fontSize: 11 }}>eventos</span>
            </div>
            <div className="card-pad col" style={{ gap: 10 }}>
              {recentActivity.length === 0 ? (
                <div style={{ color: 'var(--text-3)', fontSize: 12, textAlign: 'center', padding: '12px 0' }}>Sem eventos recentes.</div>
              ) : (
                recentActivity.slice(0, 8).map((a, i) => (
                  <div key={i} className="row" style={{ alignItems: 'flex-start', gap: 10 }}>
                    <div className="feed-dot" style={{ background: EVENT_COLOR[a.eventType ?? ''] ?? 'var(--text-3)' }} />
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ color: 'var(--text-1)', fontSize: 12.5, overflow: 'hidden', textOverflow: 'ellipsis' }}>
                        {a.description ?? a.eventType ?? '—'}
                      </div>
                      <div className="mono" style={{ color: 'var(--text-3)', fontSize: 10.5 }}>
                        {a.eventType} · {fmtRelative(a.timestamp)}
                      </div>
                    </div>
                  </div>
                ))
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
