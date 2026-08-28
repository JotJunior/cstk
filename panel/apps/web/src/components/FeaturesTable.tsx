/**
 * FeaturesTable — tabela de features com rollup, portada do prototipo
 * (screens_main.jsx · FeaturesTable). Reusada em Projetos, Detalhe de Projeto
 * e Features. Clique navega para o detalhe da feature.
 */
import { useNavigate } from 'react-router-dom';
import { StatusBadge } from './StatusBadge.js';
import { PipelineProgress } from './PipelineProgress.js';
import { fmtNum, fmtDur } from '@/lib/format.js';

type Status = 'em_andamento' | 'aguardando_humano' | 'concluida' | 'abortada' | null;

export interface FeatureRow {
  project: string;
  feature: string;
  latestStatus?: Status;
  currentStage?: string | null;
  totalWaves?: number | null;
  totalToolCalls?: number | null;
  totalWallclock?: number | null;
  totalDecisions?: number | null;
  totalBlocks?: number | null;
  openAlerts?: number | null;
}

export function FeaturesTable({ features, showProject = true }: { features: FeatureRow[]; showProject?: boolean }) {
  const navigate = useNavigate();
  return (
    <div style={{ overflowX: 'auto' }}>
      <table className="tbl">
        <thead>
          <tr>
            <th>Feature</th>
            {showProject && <th>Projeto</th>}
            <th>Status</th>
            <th style={{ minWidth: 200 }}>Pipeline</th>
            <th className="num">Ondas</th>
            <th className="num">Tool calls</th>
            <th className="num">Wallclock</th>
            <th className="num">Decisões</th>
            <th className="num">Bloqueios</th>
            <th className="num">Alertas</th>
          </tr>
        </thead>
        <tbody>
          {features.length === 0 ? (
            <tr><td colSpan={showProject ? 10 : 9} style={{ textAlign: 'center', color: 'var(--text-3)', padding: 24 }}>Nenhuma feature.</td></tr>
          ) : features.map((f, idx) => {
            const alerts = f.openAlerts ?? 0;
            return (
              <tr
                key={`${f.project}/${f.feature}/${idx}`}
                className="clickable"
                onClick={() => navigate(`/features/${encodeURIComponent(f.project)}/${encodeURIComponent(f.feature)}`)}
              >
                <td><div style={{ fontWeight: 500, color: 'var(--text-0)' }}>{f.feature}</div></td>
                {showProject && <td className="mono" style={{ fontSize: 11.5 }}>{f.project}</td>}
                <td><StatusBadge status={f.latestStatus ?? null} /></td>
                <td><PipelineProgress etapa={f.currentStage ?? null} status={f.latestStatus ?? null} /></td>
                <td className="num">{f.totalWaves ?? '—'}</td>
                <td className="num">{fmtNum(f.totalToolCalls)}</td>
                <td className="num">{fmtDur(f.totalWallclock)}</td>
                <td className="num">{f.totalDecisions ?? '—'}</td>
                <td className="num">{f.totalBlocks ?? '—'}</td>
                <td className="num">{alerts > 0 ? <span style={{ color: 'var(--critical)', fontWeight: 600 }}>{alerts}</span> : <span className="muted">—</span>}</td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
