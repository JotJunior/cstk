/**
 * ProjectDetail — KPIs do projeto + tabela de features.
 * Layout do prototipo (screens_main.jsx · ProjectDetailScreen).
 */
import { useParams } from 'react-router-dom';
import { useProject } from '@/lib/hooks.js';
import { useApiState } from '@/hooks/useApiState.js';
import { LoadingState, EmptyState, ErrorState } from '@/states/index.js';
import { KpiCard, AgentUsagePanel, agentUsageState, coverageLabel } from '@/components/index.js';
import { FeaturesTable, type FeatureRow } from '@/components/FeaturesTable.js';
import { fmtNum, fmtDur, fmtTokens } from '@/lib/format.js';
import type { AgentUsageRollup } from '@cstk-panel/shared-types';

interface ProjectRollupShape {
  totalExecutions: number;
  activeExecutions: number;
  totalDecisions: number;
  totalToolCalls: number | null;
  totalWallclock: number | null;
  openAlerts: number;
  /** consumo medido de subagentes (schema v10); null/ausente em bases v<10 */
  agentUsage?: AgentUsageRollup | null;
}

export function ProjectDetail() {
  const { project = '' } = useParams();
  const query = useProject(project);
  const { isLoading, isError, errorMessage } = useApiState(query);

  if (isLoading) return <LoadingState variant="kpi" />;
  if (isError) return <ErrorState message={errorMessage ?? 'Erro ao carregar projeto.'} />;

  const data = query.data?.data as { rollup?: ProjectRollupShape; features?: FeatureRow[] } | null;
  if (!data) return <EmptyState title="Projeto não encontrado" subtitle={project} />;

  const rollup = data.rollup;
  const features = data.features ?? [];
  const usage = rollup?.agentUsage ?? null;
  const hasUsage = agentUsageState(usage) === 'measured';

  return (
    <div className="col gap-4">
      <div className="page-head">
        <div>
          <h1>{project}</h1>
          <div className="sub">{features.length} features · rollup de execuções</div>
        </div>
      </div>

      <div className="grid-6">
        <KpiCard label="Features" value={features.length} icon="git-branch" />
        <KpiCard label="Em andamento" value={rollup?.activeExecutions ?? 0} icon="activity" accent={rollup && rollup.activeExecutions > 0 ? 'accent' : undefined} />
        <KpiCard label="Tool calls · proxy" value={fmtNum(rollup?.totalToolCalls)} icon="bolt" tip="Chamadas de ferramenta do orquestrador — proxy de esforço, não token." />
        <KpiCard
          label="Tokens · subagentes"
          value={hasUsage ? fmtTokens(usage?.totalTokens) : '—'}
          icon="cpu"
          footnote={hasUsage ? coverageLabel(usage) : 'não coletado nesta fonte'}
          tip="Medição real do harness, agregada por onda (schema v10). Parcial: spawns em background não reportam uso."
        />
        <KpiCard label="Wallclock" value={fmtDur(rollup?.totalWallclock)} icon="clock" />
        <KpiCard label="Alertas abertos" value={rollup?.openAlerts ?? 0} icon="alert" accent={rollup && rollup.openAlerts > 0 ? 'critical' : undefined} />
      </div>

      {/* Breakdown do consumo — input/output/cache e cobertura da amostra */}
      <div className="card">
        <div className="card-head">
          <h3>Consumo de subagentes · medido</h3>
          <span className="mono muted" style={{ fontSize: 11 }}>
            {usage?.wavesWithUsage != null && usage.wavesTotal != null
              ? `${usage.wavesWithUsage} de ${usage.wavesTotal} ondas com medição`
              : 'schema v10'}
          </span>
        </div>
        <div style={{ padding: 14 }}>
          <AgentUsagePanel usage={usage} columns={4} />
        </div>
      </div>

      <div className="card">
        <div className="card-head">
          <h3>Features de {project}</h3>
          <span className="mono muted" style={{ fontSize: 11 }}>{features.length} features</span>
        </div>
        <FeaturesTable features={features.map(f => ({ ...f, project }))} showProject={false} />
      </div>
    </div>
  );
}
