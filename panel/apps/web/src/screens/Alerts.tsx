/**
 * Alerts — Central de Alertas cross-execucao (US4).
 * Lista filtravel por tipo, project, feature, periodo.
 * Severidade derivada de valorConsumido/valorThreshold com rotulo "derivada".
 * Drill-down: clique navega para a execucao/onda de origem.
 *
 * Ref: spec.md §User Story 4; tasks.md §6.4
 */
import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAlerts, useProjects } from '@/lib/hooks.js';
import { useApiState } from '@/hooks/useApiState.js';
import { LoadingState, EmptyState, ErrorState, DegradedBanner } from '@/states/index.js';
import { KpiCard, Icon, TextRaw } from '@/components/index.js';
import type { AlertSignalDTO, PeriodParam } from '@cstk-panel/shared-types';

interface AlertsProps {
  period: PeriodParam;
}

// Gauge miniatura para budget consumption
function BudgetGauge({ value, threshold, unit = '' }: { value: number | null; threshold: number | null; unit?: string }) {
  if (value == null || threshold == null || threshold === 0) {
    return <span style={{ color: 'var(--text-3)', fontSize: 11 }}>—</span>;
  }
  const pct = Math.min(100, Math.round((value / threshold) * 100));
  const color = pct >= 100 ? 'var(--critical)' : pct >= 80 ? 'var(--warning)' : 'var(--success)';
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
      <div style={{ position: 'relative', width: 40, height: 40 }}>
        <svg width={40} height={40} viewBox="0 0 40 40">
          {/* Track */}
          <circle cx={20} cy={20} r={14} fill="none" stroke="var(--bg-3)" strokeWidth={5} />
          {/* Filled */}
          <circle
            cx={20} cy={20} r={14}
            fill="none" stroke={color} strokeWidth={5}
            strokeDasharray={`${(pct / 100) * 87.96} 87.96`}
            strokeLinecap="round"
            transform="rotate(-90 20 20)"
          />
        </svg>
        <div style={{
          position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center',
          fontSize: 9, fontWeight: 700, fontFamily: 'var(--font-mono)', color,
        }}>
          {pct}%
        </div>
      </div>
      <div style={{ fontSize: 11, color: 'var(--text-2)', fontFamily: 'var(--font-mono)' }}>
        <div>{value}{unit}</div>
        <div style={{ color: 'var(--text-3)' }}>/ {threshold}{unit}</div>
      </div>
    </div>
  );
}

// Severidade derivada com rotulo "derivada" (FR-009)
function SeverityDerived({ value, threshold }: { value: number | null; threshold: number | null }) {
  const pct = value != null && threshold != null && threshold > 0
    ? (value / threshold) * 100
    : null;
  if (pct == null) return <span style={{ color: 'var(--text-3)', fontSize: 11 }}>—</span>;

  const level = pct >= 100 ? 'critical' : pct >= 80 ? 'warning' : 'info';
  const color  = level === 'critical' ? 'var(--critical)' : level === 'warning' ? 'var(--warning)' : 'var(--info)';
  const bg     = level === 'critical' ? 'var(--critical-soft)' : level === 'warning' ? 'var(--warning-soft)' : 'var(--info-soft)';
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-start', gap: 2 }}>
      <span style={{
        padding: '2px 7px', borderRadius: 10, fontSize: 11, fontWeight: 600,
        background: bg, color,
      }}>
        {level}
      </span>
      <span style={{ fontSize: 10, color: 'var(--text-3)', fontFamily: 'var(--font-mono)' }}>derivada</span>
    </div>
  );
}

export function Alerts({ period }: AlertsProps) {
  const navigate = useNavigate();
  const [filterTipo, setFilterTipo] = useState('');
  const [filterProject, setFilterProject] = useState('');
  const [filterFeature] = useState('');

  const alertsOpts: Parameters<typeof useAlerts>[0] = { period };
  if (filterTipo) alertsOpts.type = filterTipo;
  if (filterProject) alertsOpts.project = filterProject;
  if (filterFeature) alertsOpts.feature = filterFeature;
  const query = useAlerts(alertsOpts);
  const { isLoading, isError, errorMessage, isDegraded } = useApiState(query);
  const items: AlertSignalDTO[] = query.data?.data?.alerts ?? [];
  const meta = query.data?.meta;

  // Projetos para o select (lista completa, não só os com alerta)
  const projectsQ = useProjects();
  const projectOptions = (projectsQ.data?.data ?? []).map(p => p.project);

  if (isLoading) return <LoadingState variant="kpi" />;
  if (isError) return <ErrorState message={errorMessage ?? 'Erro ao carregar alertas.'} />;

  // Contadores
  const nCircular = items.filter(a => a.type === 'circular').length;
  const nBudget   = items.filter(a => a.type === 'budget_breach').length;
  // Severidade derivada por contagem
  const nCritical = items.filter(a => {
    const pct = a.consumedValue != null && a.thresholdValue != null && a.thresholdValue > 0
      ? (a.consumedValue / a.thresholdValue)
      : null;
    return pct != null && pct >= 1;
  }).length;
  const nWarning = items.filter(a => {
    const pct = a.consumedValue != null && a.thresholdValue != null && a.thresholdValue > 0
      ? (a.consumedValue / a.thresholdValue)
      : null;
    return pct != null && pct >= 0.8 && pct < 1;
  }).length;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      {isDegraded && meta && <DegradedBanner meta={meta} />}

      {/* KPIs */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(160px, 1fr))', gap: 12 }}>
        {nCritical > 0 ? (
          <KpiCard label={`Total · ${period}`} value={items.length} trend={`${nCritical} critico(s)`} accent="critical" />
        ) : (
          <KpiCard label={`Total · ${period}`} value={items.length} trend="sem criticos" />
        )}
        {nCircular > 0 ? (
          <KpiCard label="Mov. circular" value={nCircular} trend="loop detectado" accent="critical" />
        ) : (
          <KpiCard label="Mov. circular" value={nCircular} trend="loop detectado" />
        )}
        {nBudget > 0 ? (
          <KpiCard label="Breach de orcamento" value={nBudget} trend="tool_calls · wallclock · ciclos" accent="warning" />
        ) : (
          <KpiCard label="Breach de orcamento" value={nBudget} trend="tool_calls · wallclock · ciclos" />
        )}
        <KpiCard
          label="Severidades"
          value={`${nCritical} · ${nWarning} · ${items.length - nCritical - nWarning}`}
          trend="critico · atencao · info"
        />
      </div>

      {/* Tabela de alertas */}
      <div className="card">
        <div className="card-head">
          <div className="row gap-2">
            <h3>Central de alertas</h3>
            {items.length > 0 && (
              <span style={{
                background: 'var(--bg-3)', color: 'var(--text-1)', fontSize: 10,
                fontWeight: 600, fontFamily: 'var(--font-mono)',
                padding: '1px 7px', borderRadius: 10,
              }}>
                {items.length}
              </span>
            )}
          </div>
          <div className="row gap-2">
            <select
              className="select"
              value={filterTipo}
              onChange={e => setFilterTipo(e.target.value)}
            >
              <option value="">Todos os tipos</option>
              <option value="circular">movimento circular</option>
              <option value="budget_breach">budget_breach</option>
            </select>
            <select
              className="select"
              aria-label="Filtrar por projeto"
              value={filterProject}
              onChange={e => setFilterProject(e.target.value)}
            >
              <option value="">Todos os projetos</option>
              {projectOptions.map(p => <option key={p} value={p}>{p}</option>)}
            </select>
          </div>
        </div>

        {items.length === 0 ? (
          <EmptyState title="Nenhum alerta encontrado" subtitle="Nenhum alerta corresponde aos filtros selecionados." />
        ) : (
          <div style={{ overflowX: 'auto' }}>
            <table className="tbl">
              <thead>
                <tr>
                  <th>Tipo</th>
                  <th>Proveniencia</th>
                  <th>Descricao</th>
                  <th>Consumido / Threshold</th>
                  <th>Severidade</th>
                  <th>Onda</th>
                </tr>
              </thead>
              <tbody>
                {items.map((a, idx) => {
                  const isCircular = a.type === 'circular';
                  const pct = a.consumedValue != null && a.thresholdValue != null && a.thresholdValue > 0
                    ? (a.consumedValue / a.thresholdValue)
                    : null;
                  const sevColor = pct != null && pct >= 1 ? 'var(--critical)' : 'var(--warning)';

                  return (
                    <tr
                      key={idx}
                      className="clickable"
                      onClick={() => navigate(`/executions/${encodeURIComponent(a.executionId)}?wave=${a.wave}&tab=alerts`)}
                    >
                      <td>
                        <div className="row gap-2">
                          <Icon
                            name={isCircular ? 'activity' : 'alert'}
                            size={13}
                            style={{ color: sevColor }}
                          />
                          <span style={{ fontFamily: 'var(--font-mono)', fontSize: 12, fontWeight: 600, color: 'var(--text-0)' }}>
                            {isCircular ? 'circular' : `breach·${a.subtype ?? '?'}`}
                          </span>
                        </div>
                      </td>
                      <td>
                        <div style={{ fontFamily: 'var(--font-mono)', fontSize: 11, color: 'var(--text-2)' }}>
                          <span style={{ color: 'var(--text-1)' }}>{a.executionId.slice(0, 32)}</span>
                        </div>
                      </td>
                      <td style={{ maxWidth: 320 }}>
                        <TextRaw value={a.description} maxLength={120} />
                      </td>
                      <td>
                        <BudgetGauge
                          value={a.consumedValue}
                          threshold={a.thresholdValue}
                          unit={a.subtype === 'wallclock' ? 's' : ''}
                        />
                      </td>
                      <td>
                        <SeverityDerived value={a.consumedValue} threshold={a.thresholdValue} />
                      </td>
                      <td>
                        <span style={{ fontFamily: 'var(--font-mono)', fontSize: 11, color: 'var(--inprogress)' }}>
                          {a.wave}
                        </span>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
