// cstk-panel — main app: shell, sidebar, topbar, hash-router

const { useState: useStateA, useEffect: useEffectA, useMemo: useMemoA } = React;
const Da = window.CSTKData;

function App() {
  const [hash, setHash] = useStateA(window.location.hash || '#/');
  const [decisionModal, setDecisionModal] = useStateA(null);
  const [period, setPeriod] = useStateA('7d');
  const [theme, setTheme] = useStateA('dark');

  useEffectA(() => {
    const onHash = () => setHash(window.location.hash || '#/');
    window.addEventListener('hashchange', onHash);
    return () => window.removeEventListener('hashchange', onHash);
  }, []);

  const navigate = (h) => { window.location.hash = h.replace(/^#/, ''); };
  const openDecision = (d) => setDecisionModal(d);

  // Parse hash into route + params
  const { route, params, queryParams } = useMemoA(() => {
    const h = hash.replace(/^#\/?/, '');
    const [path, qs] = h.split('?');
    const segments = path.split('/').filter(Boolean);
    return {
      route: segments[0] || 'overview',
      params: segments.slice(1),
      queryParams: new URLSearchParams(qs || ''),
    };
  }, [hash]);

  // Map route → nav active + breadcrumbs + title
  const navItem = ROUTES.find(r => r.match(route)) || ROUTES[0];

  // Build breadcrumbs
  const crumbs = buildCrumbs(route, params, queryParams);

  // Resolve screen
  let screen;
  switch (route) {
    case 'overview':
    case '': screen = <OverviewScreen navigate={navigate} period={period}/>; break;
    case 'projects':
      screen = params[0]
        ? <ProjectDetailScreen projectId={params[0]} navigate={navigate}/>
        : <ProjectsScreen navigate={navigate}/>;
      break;
    case 'features':
      screen = params[0]
        ? <FeatureDetailScreen featureId={params[0]} navigate={navigate}/>
        : <FeaturesListScreen navigate={navigate}/>;
      break;
    case 'executions':
      screen = params[0]
        ? <ExecutionScreen featureId={params[0]} queryParams={queryParams} navigate={navigate} openDecision={openDecision}/>
        : <ExecutionsListScreen navigate={navigate}/>;
      break;
    case 'alerts':    screen = <AlertsScreen navigate={navigate}/>; break;
    case 'metrics':   screen = <MetricsScreen/>; break;
    case 'tasks':     screen = <TasksScreen navigate={navigate}/>; break;
    case 'incidents': screen = <IncidentsScreen navigate={navigate}/>; break;
    case 'search':    screen = <SearchScreen navigate={navigate} openDecision={openDecision}/>; break;
    case 'source':    screen = <SourceScreen/>; break;
    default:          screen = <OverviewScreen navigate={navigate} period={period}/>;
  }

  return (
    <div className="app">
      <Sidebar route={route} navigate={navigate} theme={theme} setTheme={setTheme}/>
      <div className="main">
        <Topbar crumbs={crumbs} navigate={navigate} period={period} setPeriod={setPeriod}/>
        <div className="content">
          <PageHead route={route} params={params}/>
          {screen}
        </div>
      </div>
      {decisionModal && <DecisionModal decision={decisionModal} onClose={() => setDecisionModal(null)} navigate={navigate}/>}
    </div>
  );
}

const ROUTES = [
  { id:'overview',  label:'Visão Geral',          icon:'home',      hash:'#/',           match: r => r === 'overview' || r === '' },
  { id:'projects',  label:'Projetos',             icon:'folder',    hash:'#/projects',   match: r => r === 'projects' },
  { id:'features',  label:'Features',             icon:'git-branch',hash:'#/features',   match: r => r === 'features' },
  { id:'executions',label:'Execuções',            icon:'activity',  hash:'#/executions', match: r => r === 'executions' },
  { id:'alerts',    label:'Alertas',              icon:'alert',     hash:'#/alerts',     match: r => r === 'alerts' },
  { id:'metrics',   label:'Métricas',             icon:'bar',       hash:'#/metrics',    match: r => r === 'metrics' },
  { id:'tasks',     label:'Tarefas',              icon:'check',     hash:'#/tasks',      match: r => r === 'tasks' },
  { id:'incidents', label:'Incidentes',           icon:'zap',       hash:'#/incidents',  match: r => r === 'incidents' },
  { id:'search',    label:'Busca de Conhecimento',icon:'search',    hash:'#/search',     match: r => r === 'search' },
];

function Sidebar({ route, navigate, theme, setTheme }) {
  const alertCount = Da.ALERTS.filter(a => a.severity === 'critical').length;
  return (
    <aside className="sidebar">
      <div className="brand">
        <div className="brand-mark">c</div>
        <div>
          <div className="brand-name">cstk-panel</div>
          <div className="brand-tag">observabilidade · v3.19</div>
        </div>
      </div>
      <div className="nav-section">
        <div className="nav-label">observar</div>
        {ROUTES.slice(0, 4).map(r => (
          <NavItem key={r.id} item={r} active={r.match(route)} navigate={navigate}/>
        ))}
        <div className="nav-label" style={{marginTop: 12}}>diagnosticar</div>
        {ROUTES.slice(4, 9).map(r => (
          <NavItem
            key={r.id}
            item={r}
            active={r.match(route)}
            navigate={navigate}
            badge={r.id === 'alerts' && alertCount > 0 ? alertCount : null}
          />
        ))}
      </div>
      <div className="sidebar-foot">
        <div className="freshness">
          <span className="fresh-dot"/>
          <div className="col" style={{gap: 0, lineHeight: 1.3, flex: 1}}>
            <span style={{color:'var(--text-1)', fontSize:11.5}}>Índice atualizado <span className="mono">há 3m</span></span>
            <span className="mono" style={{color:'var(--text-3)', fontSize:10}}>knowledge.db · schema v2 · ok</span>
          </div>
        </div>
        <div className="row" style={{justifyContent:'space-between', marginTop: 10}}>
          <a className="row gap-2" onClick={() => navigate('#/source')} style={{cursor:'pointer', color:'var(--text-2)', fontSize:11}}>
            <Icon name="database" size={12}/>fonte de dados
          </a>
          <button className="ico-btn" onClick={() => setTheme(theme === 'dark' ? 'light' : 'dark')} title="tema (decorativo)">
            <Icon name={theme === 'dark' ? 'sun' : 'moon'} size={12}/>
          </button>
        </div>
      </div>
    </aside>
  );
}

function NavItem({ item, active, navigate, badge }) {
  return (
    <div className={`nav-item ${active ? 'active' : ''}`} onClick={() => navigate(item.hash)}>
      <Icon name={item.icon} size={15} className="ico"/>
      <span>{item.label}</span>
      {badge && <span className="nav-badge">{badge}</span>}
    </div>
  );
}

function buildCrumbs(route, params, queryParams) {
  const out = [{ label:'cstk-panel', hash:'#/' }];
  if (!route || route === 'overview') {
    out.push({ label:'Visão Geral', current: true });
    return out;
  }
  const r = ROUTES.find(x => x.id === route);
  out.push({ label: r ? r.label : route, hash: r ? r.hash : '#/' });
  if (params[0]) {
    if (route === 'projects') out.push({ label: params[0], mono: true, current: true });
    else if (route === 'features') out.push({ label: params[0], mono: true, current: true });
    else if (route === 'executions') {
      const f = Da.FEATURES.find(x => x.id === params[0]);
      if (f) out.push({ label: f.title, mono: true, hash: `#/features/${f.id}` });
      out.push({ label: Da.execId(f || { id: params[0], iniciada_em: '20260524-022752' }).slice(0, 32) + '…', mono: true, current: true });
      const w = queryParams.get('wave');
      if (w) out.push({ label: w, mono: true, current: true });
    }
  }
  return out;
}

function Topbar({ crumbs, navigate, period, setPeriod }) {
  return (
    <div className="topbar">
      <div className="crumbs">
        {crumbs.map((c, i) => (
          <React.Fragment key={i}>
            {i > 0 && <span className="sep">/</span>}
            <span
              className={`crumb ${c.mono ? 'mono' : ''} ${c.current ? 'current' : ''}`}
              onClick={() => c.hash && navigate(c.hash)}
              style={c.hash ? {cursor:'pointer'} : {cursor:'default'}}>
              {c.label}
            </span>
          </React.Fragment>
        ))}
      </div>
      <div className="period-tabs">
        {['24h','7d','30d','tudo'].map(p => (
          <button key={p} className={period === p ? 'active' : ''} onClick={() => setPeriod(p)}>{p}</button>
        ))}
      </div>
      <select className="select"><option>Todos os projetos</option>{Da.PROJECTS.map(p=><option key={p.id}>{p.name}</option>)}</select>
      <div className="topbar-search">
        <Icon name="search" size={13}/>
        <input placeholder="buscar projetos, features, decisões…"/>
        <span className="kbd">/</span>
      </div>
    </div>
  );
}

function PageHead({ route, params }) {
  const titles = {
    '': { t:'Visão Geral', s:'panorama do orquestrador · execuções, custo, alertas e qualidade' },
    overview: { t:'Visão Geral', s:'panorama do orquestrador · execuções, custo, alertas e qualidade' },
    projects: { t: params[0] ? params[0] : 'Projetos', s: params[0] ? 'rollup de features · execuções · custo' : 'todos os projetos sob observação' },
    features: { t: params[0] ? params[0] : 'Features', s: params[0] ? 'detalhe da feature · execuções e retros' : 'todas as features cross-project' },
    executions: { t: params[0] ? `Execução · ${params[0]}` : 'Execuções', s: params[0] ? 'deep-dive · ondas · decisões · tarefas · eventos' : 'todas as execuções' },
    alerts: { t:'Alertas', s:'movimentos circulares e breaches de orçamento' },
    metrics: { t:'Métricas', s:'tendências e distribuições cross-execução' },
    tasks: { t:'Tarefas', s:'qualidade de entrega · pass/fail · lint · testes' },
    incidents: { t:'Incidentes', s:'timeline operacional · lock, validation, retry, schedule' },
    search: { t:'Busca de Conhecimento', s:'full-text sobre decisões, bloqueios, retros e skills · bm25' },
    source: { t:'Fonte de dados', s:'knowledge.db · schema v2 · read-only e best-effort' },
  };
  const t = titles[route] || titles.overview;
  return (
    <div className="page-head">
      <div>
        <h1>{t.t}</h1>
        <div className="sub">{t.s}</div>
      </div>
    </div>
  );
}

function ExecutionsListScreen({ navigate }) {
  return (
    <div className="card">
      <div className="card-head">
        <h3>Todas as execuções</h3>
        <span className="sub mono">{Da.FEATURES.length} execuções</span>
      </div>
      <table className="tbl">
        <thead>
          <tr>
            <th>execucao_id</th>
            <th>Feature</th>
            <th>Status</th>
            <th>Etapa</th>
            <th>Iniciada</th>
            <th className="num">Duração</th>
            <th className="num">Ondas</th>
            <th className="num">Tool calls</th>
          </tr>
        </thead>
        <tbody>
          {Da.FEATURES.map(f => (
            <tr key={f.id} className="clickable" onClick={() => navigate(`#/executions/${f.id}`)}>
              <td className="mono" style={{fontSize:11, color:'var(--accent)'}}>{Da.execId(f)}</td>
              <td>
                <div style={{color:'var(--text-0)'}}>{f.title}</div>
                <div className="mono muted-2" style={{fontSize:10.5}}>{f.project}</div>
              </td>
              <td><StatusBadge status={f.status}/></td>
              <td className="mono" style={{fontSize:11.5}}>{f.etapa_corrente}</td>
              <td className="mono" style={{fontSize:11.5}}>{fmtTimestamp(f.iniciada_em)}</td>
              <td className="num">{fmtDur(f.duracao_segundos)}</td>
              <td className="num">{f.ondas_total}</td>
              <td className="num">{fmtNum(f.tool_calls_total)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<App/>);
