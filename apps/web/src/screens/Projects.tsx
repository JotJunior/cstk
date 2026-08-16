/**
 * Projects — lista de projetos com rollup: tabela no desktop, cards no mobile.
 * Layout do prototipo (screens_main.jsx · ProjectsScreen).
 * Ref: spec.md FR-022 (drill-down)
 *
 * Colunas agrupadas para abrir espaco a consumo (Tokens/Custo) sem alargar a
 * tabela: o mix de features (concluidas/em andamento/abortadas) vira uma celula
 * so, tool calls + decisoes viram "Atividade" e os alertas acompanham o nome do
 * projeto — mesmo tratamento que os cards do mobile ja davam.
 *
 * Principio III (Honestidade de Metrica): consumo ausente e "—", nunca 0, e a
 * cobertura/fonte da medicao acompanha o numero (sub-rotulo + tooltip).
 */
import type { ReactNode } from 'react';
import { useNavigate } from 'react-router-dom';
import { useProjects, useFeatures } from '@/lib/hooks.js';
import { useApiState } from '@/hooks/useApiState.js';
import { LoadingState, EmptyState, ErrorState } from '@/states/index.js';
import {
  MiniStat, fmtUsd, otelUsageState, isPartialOtelSample, otelCoverageLabel,
} from '@/components/index.js';
import { pickTokens, tokenCoverageLabel, tokenSourceTip } from '@/lib/token-source.js';
import { fmtNum, fmtDur, fmtTokens, fmtRelative } from '@/lib/format.js';
import type { ProjectRollup, FeatureRollup } from '@cstk-panel/shared-types';

const ACTIVE = new Set(['em_andamento', 'aguardando_humano']);

interface ProjectRow {
  rollup: ProjectRollup;
  featureCount: number;
  done: number;
  inProgress: number;
  aborted: number;
  alerts: number;
}

/** Mix de features em uma celula: total + fatias nao-zeradas, coloridas. */
function FeatureMix({ row }: { row: ProjectRow }) {
  const parts = [
    { n: row.done, color: 'var(--success)', label: 'concluídas' },
    { n: row.inProgress, color: 'var(--inprogress)', label: 'em andamento' },
    { n: row.aborted, color: 'var(--text-2)', label: 'abortadas' },
  ].filter(p => p.n > 0);

  if (row.featureCount === 0) return <span className="muted">—</span>;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 2 }}>
      <span style={{ fontWeight: 600, color: 'var(--text-0)' }}>{row.featureCount}</span>
      {parts.length > 0 && (
        <span
          style={{ display: 'flex', gap: 6, fontSize: 11, fontFamily: 'var(--font-mono)' }}
          title={parts.map(p => `${p.n} ${p.label}`).join(' · ')}
        >
          {parts.map(p => (
            <span key={p.label} style={{ color: p.color }}>{p.n}</span>
          ))}
        </span>
      )}
    </div>
  );
}

/** Valor principal + sub-rotulo discreto (fonte/cobertura da medicao). */
function StackedNum({ value, note }: { value: ReactNode; note?: string | null }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 2 }}>
      <span>{value}</span>
      {note && <span className="muted" style={{ fontSize: 10.5 }}>{note}</span>}
    </div>
  );
}

interface UsageCells {
  tokensText: string;
  /** fonte da medicao (OTel x hook de spawn) + aviso de amostra parcial */
  tokensNote: string | null;
  tokensTip: string;
  costText: string;
  costNote: string | null;
  costTip: string;
  measuredCost: boolean;
  measuredTokens: boolean;
}

/**
 * Consumo do projeto para as celulas Tokens/Custo. Tokens preferem OTel e caem
 * para o hook de spawn (v10); custo vem so de OTel — ausencia nunca vira $0.
 */
function usageOf(rollup: ProjectRollup): UsageCells {
  const otel = rollup.otelUsage;
  const pick = pickTokens(otel, rollup.agentUsage);
  const measuredCost = otelUsageState(otel) === 'measured' && otel?.costUsd != null;

  return {
    tokensText: pick.tokens == null ? '—' : fmtTokens(pick.tokens),
    tokensNote: pick.source == null
      ? null
      : `${pick.source === 'otel' ? 'OTel' : 'spawn'}${pick.partial ? ' · amostra' : ''}`,
    tokensTip: `${tokenSourceTip(pick)} · ${tokenCoverageLabel(pick, otel, rollup.agentUsage)}`,
    costText: measuredCost ? fmtUsd(otel?.costUsd) : '—',
    costNote: measuredCost && isPartialOtelSample(otel) ? 'amostra' : null,
    costTip: measuredCost
      ? `Custo medido pela telemetria OTel do Claude Code, somado por onda. Cobertura: ${otelCoverageLabel(otel)} — ondas sem telemetria não somam.`
      : 'telemetria OTel não coletada neste projeto — ausência de medição, não custo zero',
    measuredCost,
    measuredTokens: pick.tokens != null,
  };
}

export function Projects() {
  const navigate = useNavigate();
  const projectsQ = useProjects();
  const featuresQ = useFeatures();
  const { isLoading, isError, errorMessage, isEmpty } = useApiState(projectsQ);

  if (isLoading) return <LoadingState variant="kpi" />;
  if (isError) return <ErrorState message={errorMessage ?? 'Erro ao carregar projetos.'} />;
  if (isEmpty) return <EmptyState title="Nenhum projeto" subtitle="Execute o orquestrador para ver dados aqui." />;

  const projects = (projectsQ.data?.data ?? []) as ProjectRollup[];
  const features = (featuresQ.data?.data ?? []) as FeatureRollup[];

  const byProject = new Map<string, FeatureRollup[]>();
  for (const f of features) {
    const arr = byProject.get(f.project) ?? [];
    arr.push(f);
    byProject.set(f.project, arr);
  }

  const rows: ProjectRow[] = projects.map(p => {
    const fs = byProject.get(p.project) ?? [];
    return {
      rollup: p,
      featureCount: fs.length,
      done: fs.filter(f => f.latestStatus === 'concluida').length,
      inProgress: fs.filter(f => f.latestStatus && ACTIVE.has(f.latestStatus)).length,
      aborted: fs.filter(f => f.latestStatus === 'abortada').length,
      alerts: p.openAlerts ?? 0,
    };
  });

  const openProject = (project: string) => navigate(`/projects/${encodeURIComponent(project)}`);

  return (
    <div className="col gap-4">
      <div className="page-head">
        <div>
          <h1>Projetos</h1>
          <div className="sub">{projects.length} projetos · rollup de execuções, custo e qualidade</div>
        </div>
      </div>

      <div className="card projects-list">
        <div style={{ overflowX: 'auto' }}>
          <table className="tbl">
            <thead>
              <tr>
                <th>Projeto</th>
                <th className="num" title="Total de features · concluídas / em andamento / abortadas">Features</th>
                <th className="num" title="Tool calls (custo proxy) e decisões registradas">Atividade</th>
                <th className="num">Wallclock</th>
                <th className="num" title="Tokens medidos — telemetria OTel (schema v11) ou hook agent-usage (v10)">Tokens</th>
                <th className="num" title="Custo em USD calculado pelo Claude Code e somado por onda (telemetria OTel)">Custo</th>
                <th>Última atividade</th>
              </tr>
            </thead>
            <tbody>
              {rows.map(r => {
                const u = usageOf(r.rollup);
                return (
                  <tr key={r.rollup.project} className="clickable" onClick={() => openProject(r.rollup.project)}>
                    <td>
                      <div className="row" style={{ gap: 8, alignItems: 'center' }}>
                        <span style={{ fontWeight: 500, color: 'var(--text-0)' }}>{r.rollup.project}</span>
                        {r.alerts > 0 && (
                          <span
                            className="tag"
                            style={{ background: 'var(--critical-soft)', color: 'var(--critical)', borderColor: 'transparent' }}
                            title={`${r.alerts} alerta(s) aberto(s)`}
                          >
                            {r.alerts} alerta{r.alerts !== 1 ? 's' : ''}
                          </span>
                        )}
                      </div>
                    </td>
                    <td className="num"><FeatureMix row={r} /></td>
                    <td className="num">
                      <StackedNum
                        value={`${fmtNum(r.rollup.totalToolCalls)} calls`}
                        note={`${fmtNum(r.rollup.totalDecisions)} decisões`}
                      />
                    </td>
                    <td className="num">{fmtDur(r.rollup.totalWallclock)}</td>
                    <td className="num" title={u.tokensTip}>
                      <StackedNum
                        value={u.measuredTokens ? u.tokensText : <span className="muted">—</span>}
                        note={u.tokensNote}
                      />
                    </td>
                    <td className="num" title={u.costTip}>
                      <StackedNum
                        value={u.measuredCost ? u.costText : <span className="muted">—</span>}
                        note={u.costNote}
                      />
                    </td>
                    <td className="muted" style={{ fontSize: 11.5, whiteSpace: 'nowrap' }}>{fmtRelative(r.rollup.latestExecutionAt)}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>

      <div className="grid-3 projects-cards">
        {rows.map(r => {
          const u = usageOf(r.rollup);
          return (
            <div
              key={r.rollup.project}
              className="card"
              style={{ cursor: 'pointer' }}
              onClick={() => openProject(r.rollup.project)}
            >
              <div className="card-pad">
                <div className="row" style={{ justifyContent: 'space-between', alignItems: 'flex-start' }}>
                  <div style={{ fontSize: 14.5, fontWeight: 600, color: 'var(--text-0)' }}>{r.rollup.project}</div>
                  {r.alerts > 0 && (
                    <span className="tag" style={{ background: 'var(--critical-soft)', color: 'var(--critical)', borderColor: 'transparent' }}>
                      {r.alerts} alerta{r.alerts !== 1 ? 's' : ''}
                    </span>
                  )}
                </div>

                <div className="divider" />

                <div className="grid-4" style={{ gap: 8 }}>
                  <MiniStat label="features" value={r.featureCount} />
                  <MiniStat label="concluídas" value={r.done} valueColor="var(--success)" />
                  <MiniStat label="em andamento" value={r.inProgress} valueColor="var(--inprogress)" />
                  <MiniStat label="abortadas" value={r.aborted} valueColor="var(--text-2)" />
                </div>

                <div className="divider" />

                <div className="row" style={{ justifyContent: 'space-between' }}>
                  <MiniStat label="tool_calls" value={fmtNum(r.rollup.totalToolCalls)} />
                  <MiniStat label="wallclock" value={fmtDur(r.rollup.totalWallclock)} />
                  <MiniStat label="decisões" value={fmtNum(r.rollup.totalDecisions)} />
                </div>

                <div className="divider" />

                <div className="row" style={{ justifyContent: 'space-between' }}>
                  <div title={u.tokensTip}>
                    <MiniStat
                      label={u.tokensNote ? `tokens · ${u.tokensNote}` : 'tokens'}
                      value={u.tokensText}
                    />
                  </div>
                  <div title={u.costTip}>
                    <MiniStat
                      label={u.costNote ? `custo · ${u.costNote}` : 'custo'}
                      value={u.costText}
                      align="end"
                    />
                  </div>
                </div>

                <div className="row" style={{ justifyContent: 'flex-end', marginTop: 12 }}>
                  <span className="muted" style={{ fontSize: 11 }}>última atividade {fmtRelative(r.rollup.latestExecutionAt)}</span>
                </div>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
