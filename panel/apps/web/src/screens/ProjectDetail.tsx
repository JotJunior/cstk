/**
 * ProjectDetail — KPIs do projeto + tabela de features.
 * Layout do prototipo (screens_main.jsx · ProjectDetailScreen).
 */
import { useParams } from 'react-router-dom';
import { useProject } from '@/lib/hooks.js';
import { useApiState } from '@/hooks/useApiState.js';
import { LoadingState, EmptyState, ErrorState } from '@/states/index.js';
import {
  KpiCard, AgentUsagePanel,
  OtelUsagePanel, otelUsageState, otelCoverageLabel, fmtUsd,
} from '@/components/index.js';
import { FeaturesTable, type FeatureRow } from '@/components/FeaturesTable.js';
import { fmtNum, fmtDur, fmtTokens } from '@/lib/format.js';
import { pickTokens, tokenCoverageLabel, tokenSourceTip } from '@/lib/token-source.js';
import type { AgentUsageRollup, OtelUsageRollup } from '@cstk-panel/shared-types';

interface ProjectRollupShape {
  totalExecutions: number;
  activeExecutions: number;
  totalDecisions: number;
  totalToolCalls: number | null;
  totalWallclock: number | null;
  openAlerts: number;
  /** consumo medido de subagentes (schema v10); null/ausente em bases v<10 */
  agentUsage?: AgentUsageRollup | null;
  /** consumo medido por telemetria OTel (schema v11); null/ausente em v<11 */
  otelUsage?: OtelUsageRollup | null;
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
  const otel = rollup?.otelUsage ?? null;
  const hasOtel = otelUsageState(otel) === 'measured';
  const tokens = pickTokens(otel, usage);

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
        {hasOtel ? (
          <KpiCard
            label="Custo · real"
            value={fmtUsd(otel?.costUsd)}
            icon="bolt"
            footnote={otelCoverageLabel(otel)}
            tip={`Medido pela telemetria OTel e somado por onda (schema v11). Proxy de esforço do orquestrador: ${fmtNum(rollup?.totalToolCalls)} tool calls.`}
          />
        ) : (
          <KpiCard label="Tool calls · proxy" value={fmtNum(rollup?.totalToolCalls)} icon="bolt" tip="Chamadas de ferramenta do orquestrador — proxy de esforço, não token." />
        )}
        <KpiCard
          label={tokens.source === 'agent' ? 'Tokens · subagentes' : 'Tokens · medidos'}
          value={tokens.tokens != null ? fmtTokens(tokens.tokens) : '—'}
          icon="cpu"
          footnote={tokenCoverageLabel(tokens, otel, usage)}
          tip={tokenSourceTip(tokens)}
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

      {/* Custo real do projeto (schema v11) — fonte distinta do bloco acima:
          cobre main + subagente, entao os dois nao se somam. */}
      <div className="card">
        <div className="card-head">
          <h3>Custo real · telemetria OTel</h3>
          <span className="mono muted" style={{ fontSize: 11 }}>
            {hasOtel ? otelCoverageLabel(otel) : 'schema v11'}
          </span>
        </div>
        <div style={{ padding: 14 }}>
          <OtelUsagePanel usage={otel} columns={4} />
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
