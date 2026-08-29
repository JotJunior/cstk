/**
 * Breadcrumb — derivado da URL corrente, hierarquia navegavel.
 * Rotas de detalhe seguem a hierarquia cstk-panel / projeto / feature /
 * execucao. A rota de execucao nao carrega projeto/feature na URL, entao
 * esses crumbs vem do DTO da propria execucao (mesma queryKey da tela de
 * detalhe — o cache do TanStack Query deduplica, sem fetch extra).
 * Ref: spec.md FR-022; plan.md §drill-down <= 4 cliques
 */
import { useLocation, useNavigate } from 'react-router-dom';
import { useExecution } from '@/lib/hooks.js';
import type { ExecutionDTO } from '@cstk-panel/shared-types';

interface Crumb {
  label: string;
  path?: string;
  mono?: boolean;
  current?: boolean;
}

/** decodeURIComponent tolerante — segmento malformado volta como veio. */
function safeDecode(seg: string): string {
  try {
    return decodeURIComponent(seg);
  } catch {
    return seg;
  }
}

const LABELS: Record<string, string> = {
  projects: 'Projetos',
  features: 'Features',
  executions: 'Execuções',
  alerts: 'Alertas',
  metrics: 'Métricas',
  tasks: 'Tarefas',
  incidents: 'Incidentes',
  search: 'Busca de Conhecimento',
};

type ExecCrumbSource = Pick<ExecutionDTO, 'project' | 'feature'>;

export function buildCrumbs(pathname: string, exec: ExecCrumbSource | null): Crumb[] {
  const crumbs: Crumb[] = [{ label: 'cstk-panel', path: '/' }];
  const segments = pathname.split('/').filter(Boolean);

  if (segments.length === 0) {
    crumbs.push({ label: 'Visão Geral', current: true });
    return crumbs;
  }

  // Detalhe de execucao: cstk-panel / projeto / feature / execucao.
  // Enquanto a query da execucao nao resolve, cai no caminho generico
  // (Execuções / <id>).
  if (segments[0] === 'executions' && segments[1] && exec) {
    const isDecisionMap = segments[2] === 'decision-map';
    crumbs.push({
      label: exec.project,
      path: `/projects/${encodeURIComponent(exec.project)}`,
      mono: true,
    });
    if (exec.feature) {
      crumbs.push({
        label: exec.feature,
        path: `/features/${encodeURIComponent(exec.project)}/${encodeURIComponent(exec.feature)}`,
        mono: true,
      });
    }
    const execCrumb: Crumb = { label: safeDecode(segments[1]), mono: true };
    if (isDecisionMap) execCrumb.path = `/executions/${segments[1]}`;
    else execCrumb.current = true;
    crumbs.push(execCrumb);
    if (isDecisionMap) crumbs.push({ label: 'Árvore de decisões', current: true });
    return crumbs;
  }

  // Detalhe de feature: cstk-panel / projeto / feature. O crumb do projeto
  // leva a /projects/<id> — /features/<id> nao e uma rota valida.
  if (segments[0] === 'features' && segments[1] && segments[2]) {
    crumbs.push({
      label: safeDecode(segments[1]),
      path: `/projects/${segments[1]}`,
      mono: true,
    });
    crumbs.push({ label: safeDecode(segments[2]), mono: true, current: true });
    return crumbs;
  }

  // Demais rotas: crumbs derivados segmento a segmento
  let accumulated = '';
  for (let i = 0; i < segments.length; i++) {
    const seg = segments[i];
    if (!seg) continue;
    accumulated += '/' + seg;
    const label = LABELS[seg] ?? safeDecode(seg);
    const isLast = i === segments.length - 1;
    const isMono = !(seg in LABELS); // ID segments are mono

    const crumb: Crumb = {
      label,
      mono: isMono,
      current: isLast,
    };
    if (!isLast) crumb.path = accumulated;
    crumbs.push(crumb);
  }

  return crumbs;
}

export function Breadcrumb() {
  const location = useLocation();
  const navigate = useNavigate();

  const segments = location.pathname.split('/').filter(Boolean);
  const execId = segments[0] === 'executions' && segments[1] ? safeDecode(segments[1]) : '';
  const execQuery = useExecution(execId);
  const exec = execId ? (execQuery.data?.data ?? null) : null;

  const crumbs = buildCrumbs(location.pathname, exec);

  return (
    <nav className="crumbs" aria-label="Caminho de navegacao">
      {crumbs.map((crumb, i) => (
        <span
          key={i}
          className="row"
          // Crumb-raiz nunca trunca (curto); demais encolhem com ellipsis
          style={{ alignItems: 'center', gap: 8, minWidth: 0, ...(i === 0 ? { flexShrink: 0 } : {}) }}
        >
          {i > 0 && <span className="sep" aria-hidden>/</span>}
          <span
            className={`crumb${crumb.mono ? ' mono-text' : ''}${crumb.current ? ' current' : ''}${crumb.path ? ' clickable' : ''}`}
            onClick={crumb.path ? () => navigate(crumb.path!) : undefined}
            title={crumb.label}
          >
            {crumb.label}
          </span>
        </span>
      ))}
    </nav>
  );
}
