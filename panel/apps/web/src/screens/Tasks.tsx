/**
 * Tasks — tarefas cross-execucao (tela Tarefas, prototipo screens_aux.jsx).
 * KPIs + tabela com filtro de outcome. Dados reais de /tasks.
 *
 * Schema v3: a tabela `tasks` passa a ter `title` (heading do tasks.md). Quando
 * presente, e a identidade primaria da linha; em bases v2 (ou title vazio) cai
 * no fallback feature/onda. Series temporais de pass/fail vivem em Metricas.
 */
import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useTasksList } from '@/lib/hooks.js';
import { useApiState } from '@/hooks/useApiState.js';
import { LoadingState, EmptyState, ErrorState } from '@/states/index.js';
import { KpiCard, OutcomePill } from '@/components/index.js';
import { fmtNum, fmtPct } from '@/lib/format.js';

type Outcome = 'all' | 'pass' | 'fail';

interface TaskRow {
  wave: string;
  executionId: string;
  project: string;
  feature: string;
  title?: string;
  outcome: 'pass' | 'fail' | null;
  testsRun: number | null;
  testsPassed: number | null;
  lintOk: boolean | null;
  arquivosTocadosCount: number | null;
}

export function Tasks() {
  const navigate = useNavigate();
  const [filter, setFilter] = useState<Outcome>('all');
  const [projectFilter, setProjectFilter] = useState('');
  const query = useTasksList();
  const { isLoading, isError, errorMessage, isEmpty } = useApiState(query);

  if (isLoading) return <LoadingState variant="kpi" />;
  if (isError) return <ErrorState message={errorMessage ?? 'Erro ao carregar tarefas.'} />;
  if (isEmpty) return <EmptyState title="Nenhuma tarefa" subtitle="Execute o orquestrador para ver dados aqui." />;

  const all = ((query.data?.data as { tasks?: TaskRow[] } | null)?.tasks ?? []);
  const projects = Array.from(new Set(all.map(t => t.project))).sort();
  const filtered = all.filter(t =>
    (filter === 'all' || t.outcome === filter) &&
    (projectFilter === '' || t.project === projectFilter),
  );

  const total = all.length;
  const fails = all.filter(t => t.outcome === 'fail').length;
  const tr = all.reduce((a, t) => a + (t.testsRun ?? 0), 0);
  const tp = all.reduce((a, t) => a + (t.testsPassed ?? 0), 0);
  const withLint = all.filter(t => t.lintOk != null);
  const lintPct = withLint.length > 0 ? withLint.filter(t => t.lintOk).length / withLint.length : null;
  const avgFiles = total > 0 ? (all.reduce((a, t) => a + (t.arquivosTocadosCount ?? 0), 0) / total).toFixed(1) : '—';
  const passRate = tr > 0 ? tp / tr : null;

  return (
    <div className="col gap-4">
      <div className="page-head">
        <div>
          <h1>Tarefas</h1>
          <div className="sub">{total} tarefas executadas · testes, lint e arquivos tocados</div>
        </div>
      </div>

      <div className="grid-5">
        <KpiCard label="Tasks · total" value={total} icon="check" />
        <KpiCard label="Pass rate · testes" value={passRate != null ? fmtPct(passRate, 1) : '—'} accent={passRate === 1 ? 'success' : undefined} footnote={`${fmtNum(tp)} / ${fmtNum(tr)}`} />
        <KpiCard label="Fails" value={fails} icon="cancel" accent={fails > 0 ? 'critical' : undefined} />
        <KpiCard label="Lint OK" value={lintPct != null ? fmtPct(lintPct) : '—'} icon="check" />
        <KpiCard label="Arquivos tocados · média" value={avgFiles} icon="doc" />
      </div>

      <div className="card">
        <div className="card-head">
          <h3>Tarefas</h3>
          <div className="row gap-2">
            <div className="period-tabs" role="tablist">
              {(['all', 'pass', 'fail'] as Outcome[]).map(o => (
                <button key={o} className={filter === o ? 'active' : ''} onClick={() => setFilter(o)}>
                  {o === 'all' ? 'todas' : o}
                </button>
              ))}
            </div>
            <select
              className="select"
              aria-label="Filtrar por projeto"
              value={projectFilter}
              onChange={e => setProjectFilter(e.target.value)}
            >
              <option value="">Todos os projetos</option>
              {projects.map(p => <option key={p} value={p}>{p}</option>)}
            </select>
          </div>
        </div>
        <div style={{ overflowX: 'auto' }}>
          <table className="tbl">
            <thead>
              <tr>
                <th>Tarefa</th>
                <th>Proveniência</th>
                <th>Outcome</th>
                <th className="num">Testes</th>
                <th>Lint</th>
                <th className="num">Arquivos</th>
              </tr>
            </thead>
            <tbody>
              {filtered.length === 0 ? (
                <tr><td colSpan={6} style={{ textAlign: 'center', color: 'var(--text-3)', padding: 24 }}>Nenhuma tarefa.</td></tr>
              ) : filtered.map((t, idx) => (
                <tr key={`${t.executionId}/${t.wave}/${idx}`} className="clickable" onClick={() => navigate(`/executions/${encodeURIComponent(t.executionId)}?tab=tasks`)}>
                  <td>
                    {/* title (v3) e untrusted — React escapa via textContent por padrao */}
                    <div style={{ color: 'var(--text-0)' }}>{t.title?.trim() ? t.title : `${t.feature} · ${t.wave}`}</div>
                    <div className="mono muted-2" style={{ fontSize: 10.5 }}>{t.title?.trim() ? `${t.feature} · ${t.wave}` : t.executionId.slice(0, 40)}</div>
                  </td>
                  <td>
                    <span className="prov">
                      <span>{t.project}</span><span className="sep">/</span><span>{t.feature}</span><span className="sep">/</span><span>{t.wave}</span>
                    </span>
                  </td>
                  <td>{t.outcome ? <OutcomePill outcome={t.outcome} /> : <span className="muted">—</span>}</td>
                  <td className="num">{t.testsPassed ?? '—'}/{t.testsRun ?? '—'}</td>
                  <td>{t.lintOk == null ? <span className="muted">—</span> : t.lintOk ? <span className="pill pass">✓ ok</span> : <span className="pill fail">✕ falhou</span>}</td>
                  <td className="num">{t.arquivosTocadosCount ?? '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
