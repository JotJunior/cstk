// cstk-panel — main screens: Overview, Projects, Features list/detail, Execution detail

const { useState: useStateS1, useEffect: useEffectS1, useMemo: useMemoS1 } = React;
const D = window.CSTKData;

// ============================================================
// OVERVIEW
// ============================================================
function OverviewScreen({ navigate, period }) {
  const totalProjects = D.PROJECTS.length;
  const totalFeatures = D.FEATURES.length;
  const byStatus = {
    em_andamento: D.FEATURES.filter(f => f.status === 'em_andamento').length,
    aguardando_humano: D.FEATURES.filter(f => f.status === 'aguardando_humano').length,
    concluida: D.FEATURES.filter(f => f.status === 'concluida').length,
    abortada: D.FEATURES.filter(f => f.status === 'abortada').length,
  };
  const totalToolCalls = D.FEATURES.reduce((a, f) => a + f.tool_calls_total, 0);
  const totalWallclock = D.FEATURES.reduce((a, f) => a + f.wallclock_total_segundos, 0);
  const openAlerts = D.ALERTS.length;
  const critAlerts = D.ALERTS.filter(a => a.severity === 'critical').length;

  const inProgress = D.FEATURES.filter(f => f.status === 'em_andamento' || f.status === 'aguardando_humano');

  // Funnel: features by etapa_corrente
  const stageBuckets = {};
  D.SDD_STAGES.forEach(s => stageBuckets[s] = 0);
  D.FEATURES.forEach(f => { if (stageBuckets[f.etapa_corrente] != null) stageBuckets[f.etapa_corrente] += 1; });
  // Inflate the funnel a bit for visual interest by adding pseudo-historic features
  stageBuckets['specify'] += 5; stageBuckets['clarify'] += 3; stageBuckets['plan'] += 4;
  stageBuckets['checklist'] += 2; stageBuckets['create-tasks'] += 3; stageBuckets['execute-task'] += 6;
  stageBuckets['review-task'] += 4; stageBuckets['briefing'] += 7; stageBuckets['constitution'] += 6;
  const funnel = D.SDD_STAGES.map(s => ({ label: s, count: stageBuckets[s] }));

  // Cost leaderboard
  const leaderboard = [...D.FEATURES]
    .sort((a, b) => b.tool_calls_total - a.tool_calls_total)
    .slice(0, 6)
    .map(f => ({ label: f.title, value: f.tool_calls_total, color: 'var(--accent)' }));

  // Model mix donut data
  const mix = D.MODEL_MIX.total;
  const modelDonut = [
    { label: 'haiku', value: mix.haiku, color: 'var(--model-haiku)' },
    { label: 'sonnet', value: mix.sonnet, color: 'var(--model-sonnet)' },
    { label: 'opus', value: mix.opus, color: 'var(--model-opus)' },
    { label: 'manter-atual', value: mix['manter-atual'], color: 'var(--model-fallback)' },
  ];

  return (
    <div className="col gap-4">
      <DegradedBannerHidden/>

      {/* KPI row */}
      <div className="grid-6">
        <KpiCard label="Projetos ativos" value={totalProjects} icon="folder" footnote={`${totalFeatures} features`}/>
        <KpiCard
          label="Em andamento"
          value={byStatus.em_andamento}
          unit={` / ${totalFeatures}`}
          icon="activity"
          footnote={`${byStatus.aguardando_humano} aguardando humano`}
          accent
        />
        <KpiCard
          label="Alertas críticos"
          value={openAlerts}
          icon="alert"
          footnote={`${critAlerts} crítico${critAlerts!==1?'s':''}`}
          critical={critAlerts > 0}
          warning={critAlerts === 0 && openAlerts > 0}
        />
        <KpiCard
          label="Custo · proxy"
          value={fmtNum(totalToolCalls)}
          footnote="tool_calls totais"
          icon="bolt"
          tip="O harness não expõe tokens — usamos tool_calls como proxy auditável."
          spark={D.COST_TIMESERIES}
          sparkColor="var(--accent)"
        />
        <KpiCard
          label="Tempo de parede"
          value={fmtDur(totalWallclock)}
          footnote="wallclock acumulado"
          icon="clock"
        />
        <KpiCard
          label="Test pass rate"
          value={(() => {
            const p = D.FEATURES.reduce((a, f) => a + f.test_pass, 0);
            const t = D.FEATURES.reduce((a, f) => a + f.test_total, 0);
            return t ? `${(p/t*100).toFixed(1)}%` : '—';
          })()}
          icon="check"
          footnote={`${D.FEATURES.reduce((a,f)=>a+f.test_pass,0)} / ${D.FEATURES.reduce((a,f)=>a+f.test_total,0)} testes`}
        />
      </div>

      <div className="grid-overview">
        {/* Left column */}
        <div className="col gap-4">
          {/* In-progress executions */}
          <div className="card">
            <div className="card-head">
              <div className="row gap-2">
                <h3>Execuções em andamento</h3>
                <span className="tag">{inProgress.length}</span>
              </div>
              <a className="muted" onClick={() => navigate('#/executions')} style={{cursor:'pointer', fontSize:11.5}}>ver todas →</a>
            </div>
            <div className="col" style={{padding: 12}}>
              {inProgress.length === 0 ? <EmptyState icon="activity" title="Nenhuma execução em andamento" hint="O orquestrador está ocioso."/> :
                inProgress.map(f => (
                  <div key={f.id} className="card-pad" style={{background:'var(--bg-2)', borderRadius: 'var(--r-sm)', border:'1px solid var(--border)', cursor:'pointer'}}
                       onClick={() => navigate(`#/executions/${f.id}`)}>
                    <div className="row" style={{justifyContent:'space-between', marginBottom: 8}}>
                      <div>
                        <div className="row gap-2">
                          <StatusBadge status={f.status}/>
                          <span style={{fontWeight: 600, fontSize: 13}}>{f.title}</span>
                        </div>
                        <div className="prov" style={{marginTop: 2}}>
                          <span>{f.project}</span><span className="sep">·</span>
                          <span className="mono">{D.execId(f).slice(0, 38)}…</span>
                        </div>
                      </div>
                      <div className="row gap-3">
                        <div className="mstat" style={{textAlign:'right'}}>
                          <span className="label">tool_calls</span>
                          <span className="value">{fmtNum(f.tool_calls_total)}</span>
                        </div>
                        <div className="mstat" style={{textAlign:'right'}}>
                          <span className="label">wallclock</span>
                          <span className="value">{fmtDur(f.wallclock_total_segundos)}</span>
                        </div>
                        <div className="mstat" style={{textAlign:'right'}}>
                          <span className="label">ondas</span>
                          <span className="value">{f.ondas_total}</span>
                        </div>
                      </div>
                    </div>
                    <PipelineProgress etapa={f.etapa_corrente} status={f.status}/>
                    <div className="row" style={{justifyContent:'space-between', marginTop: 6}}>
                      <span className="muted" style={{fontSize: 11}}>etapa corrente · <span className="mono" style={{color:'var(--inprogress)'}}>{f.etapa_corrente}</span></span>
                      <span className="muted" style={{fontSize: 11}}>iniciada {fmtRelative(f.iniciada_em)}</span>
                    </div>
                  </div>
                ))
              }
            </div>
          </div>

          {/* Critical alerts */}
          <div className="card">
            <div className="card-head">
              <div className="row gap-2">
                <h3>Alertas críticos recentes</h3>
                <span className="tag" style={{background:'var(--critical-soft)', color:'var(--critical)', borderColor:'transparent'}}>{D.ALERTS.length}</span>
              </div>
              <a className="muted" onClick={() => navigate('#/alerts')} style={{cursor:'pointer', fontSize:11.5}}>ver todos →</a>
            </div>
            <table className="tbl">
              <thead>
                <tr>
                  <th>Tipo</th><th>Proveniência</th><th>Onda</th>
                  <th>Consumido / Threshold</th><th>Severidade</th>
                </tr>
              </thead>
              <tbody>
                {D.ALERTS.slice(0, 5).map(a => (
                  <tr key={a.id} className="clickable" onClick={() => navigate(`#/executions/${a.feature}?wave=${a.wave}&tab=alerts`)}>
                    <td>
                      <div className="row gap-2">
                        <Icon name={a.tipo === 'circular' ? 'retry' : 'flame'} size={13} style={{color: a.severity === 'critical' ? 'var(--critical)' : 'var(--warning)'}}/>
                        <span className="mono" style={{fontSize:12}}>{a.tipo === 'circular' ? 'movimento circular' : `breach · ${a.subtipo}`}</span>
                      </div>
                    </td>
                    <td>
                      <div className="prov">
                        <a>{a.feature}</a><span className="sep">·</span><span className="mono">{a.wave}</span>
                      </div>
                    </td>
                    <td className="mono" style={{fontSize:11.5}}>{a.wave}</td>
                    <td>
                      <BudgetMini value={a.valor_consumido} threshold={a.valor_threshold} unit={a.subtipo === 'wallclock' ? 's' : ''}/>
                    </td>
                    <td><SeverityBadge severity={a.severity}/></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {/* Pipeline funnel */}
          <div className="card">
            <div className="card-head">
              <h3>Funil do pipeline · features por etapa corrente</h3>
              <span className="sub mono">SDD · 9 etapas</span>
            </div>
            <div className="card-pad">
              <FunnelChart data={funnel}/>
            </div>
          </div>
        </div>

        {/* Right column */}
        <div className="col gap-4">
          {/* Model mix */}
          <div className="card">
            <div className="card-head">
              <h3>Mix de modelos</h3>
              <span className="sub mono">fallback {fmtPct(D.MODEL_MIX.fallback_rate)}</span>
            </div>
            <div className="card-pad row" style={{gap:18}}>
              <Donut data={modelDonut} size={132} thickness={20} centerLabel="total" centerValue={`${(D.FEATURES.length * 6)}`}/>
              <div className="col" style={{flex:1, gap: 6}}>
                {modelDonut.map(m => (
                  <div key={m.label} className="row" style={{justifyContent:'space-between'}}>
                    <div className="row gap-2">
                      <span style={{width:8, height:8, borderRadius:2, background: m.color}}/>
                      <span className="mono" style={{fontSize:11.5}}>{m.label}</span>
                    </div>
                    <span className="mono" style={{fontSize:12, color:'var(--text-0)'}}>{fmtPct(m.value)}</span>
                  </div>
                ))}
              </div>
            </div>
          </div>

          {/* Leaderboard */}
          <div className="card">
            <div className="card-head">
              <h3>Custo por feature · proxy</h3>
              <span className="sub mono">tool_calls</span>
            </div>
            <div className="card-pad">
              <BarH data={leaderboard} maxLabel={170}/>
            </div>
          </div>

          {/* Activity feed */}
          <div className="card">
            <div className="card-head">
              <h3>Atividade recente</h3>
              <span className="sub">24h</span>
            </div>
            <div className="card-pad col" style={{gap: 10}}>
              {D.ACTIVITY.map((a, i) => (
                <div key={i} className="row" style={{alignItems:'flex-start', gap: 10}}>
                  <div className="feed-dot" style={{background:
                    a.type === 'alerta' ? 'var(--critical)' :
                    a.type === 'bloqueio' ? 'var(--warning)' :
                    a.type === 'concluida' ? 'var(--success)' :
                    'var(--inprogress)'}}/>
                  <div style={{flex:1}}>
                    <div style={{color:'var(--text-1)', fontSize:12.5}}>{a.text}</div>
                    <div className="mono" style={{color:'var(--text-3)', fontSize:10.5}}>{a.t}</div>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

function DegradedBannerHidden() {
  const [show, setShow] = useStateS1(false);
  if (!show) return null;
  return <DegradedBanner onClose={() => setShow(false)}/>;
}

// ============================================================
// PROJECTS
// ============================================================
function ProjectsScreen({ navigate }) {
  const rollups = D.PROJECTS.map(p => ({ ...p, ...D.rollupProject(p.id) }));
  return (
    <div className="col gap-4">
      <div className="grid-3">
        {rollups.map(p => (
          <div key={p.id} className="card" style={{cursor:'pointer', transition: 'border-color .15s'}}
               onClick={() => navigate(`#/projects/${p.id}`)}
               onMouseEnter={e => e.currentTarget.style.borderColor = 'var(--accent-line)'}
               onMouseLeave={e => e.currentTarget.style.borderColor = ''}>
            <div className="card-pad">
              <div className="row" style={{justifyContent:'space-between'}}>
                <div>
                  <div style={{fontSize:14.5, fontWeight:600, color:'var(--text-0)'}}>{p.name}</div>
                  <div className="muted" style={{fontSize:11.5, marginTop:2}}>{p.description}</div>
                </div>
                {p.alertas_abertos > 0 && (
                  <span className="tag" style={{background:'var(--critical-soft)', color:'var(--critical)', borderColor:'transparent'}}>{p.alertas_abertos} alerta{p.alertas_abertos!==1?'s':''}</span>
                )}
              </div>

              <div className="divider"/>

              <div className="grid-4" style={{gap: 8}}>
                <div className="mstat"><span className="label">features</span><span className="value">{p.features}</span></div>
                <div className="mstat"><span className="label">concluídas</span><span className="value" style={{color:'var(--success)'}}>{p.concluidas}</span></div>
                <div className="mstat"><span className="label">em andamento</span><span className="value" style={{color:'var(--inprogress)'}}>{p.em_andamento}</span></div>
                <div className="mstat"><span className="label">abortadas</span><span className="value" style={{color:'var(--text-2)'}}>{p.abortadas}</span></div>
              </div>

              <div className="divider"/>

              <div className="row" style={{justifyContent:'space-between'}}>
                <div className="mstat"><span className="label">tool_calls</span><span className="value">{fmtNum(p.tool_calls)}</span></div>
                <div className="mstat"><span className="label">wallclock</span><span className="value">{fmtDur(p.wallclock)}</span></div>
                <div className="mstat"><span className="label">decisões</span><span className="value">{p.decisoes}</span></div>
              </div>

              <div className="row" style={{justifyContent:'space-between', marginTop: 12}}>
                <span className="mono muted-2" style={{fontSize:10.5}}>{p.repo}</span>
                <span className="muted" style={{fontSize:11}}>última atividade {fmtRelative(p.last_activity)}</span>
              </div>
            </div>
          </div>
        ))}
      </div>

      <div className="card">
        <div className="card-head">
          <h3>Todas as features</h3>
          <div className="row gap-2">
            <input className="input" placeholder="Buscar feature…" style={{width: 200}}/>
            <select className="select"><option>Todos os projetos</option>{D.PROJECTS.map(p=><option key={p.id}>{p.name}</option>)}</select>
            <select className="select"><option>Todos os status</option><option>em_andamento</option><option>concluida</option><option>aguardando_humano</option><option>abortada</option></select>
          </div>
        </div>
        <FeaturesTable navigate={navigate}/>
      </div>
    </div>
  );
}

// Project detail
function ProjectDetailScreen({ projectId, navigate }) {
  const p = D.PROJECTS.find(x => x.id === projectId);
  if (!p) return <EmptyState title="Projeto não encontrado" icon="folder"/>;
  const fs = D.FEATURES.filter(f => f.project === projectId);
  const r = D.rollupProject(projectId);

  return (
    <div className="col gap-4">
      <div className="grid-5">
        <KpiCard label="Features" value={r.features} icon="git-branch" footnote={`${r.concluidas} concluídas`}/>
        <KpiCard label="Em andamento" value={r.em_andamento} icon="activity" accent={r.em_andamento > 0}/>
        <KpiCard label="Tool calls · proxy" value={fmtNum(r.tool_calls)} icon="bolt" tip="Proxy de custo (tokens não expostos)"/>
        <KpiCard label="Wallclock" value={fmtDur(r.wallclock)} icon="clock"/>
        <KpiCard label="Alertas abertos" value={r.alertas_abertos} icon="alert" critical={r.alertas_abertos > 0}/>
      </div>

      <div className="card">
        <div className="card-head">
          <h3>Features de {p.name}</h3>
          <span className="sub mono">{r.features} features</span>
        </div>
        <FeaturesTable filter={f => f.project === projectId} navigate={navigate}/>
      </div>
    </div>
  );
}

// ============================================================
// FEATURES — list + detail
// ============================================================
function FeaturesTable({ filter, navigate }) {
  const items = (filter ? D.FEATURES.filter(filter) : D.FEATURES);
  return (
    <div style={{overflow:'auto'}}>
      <table className="tbl">
        <thead>
          <tr>
            <th>Feature</th>
            <th>Projeto</th>
            <th>Status</th>
            <th style={{minWidth:220}}>Pipeline</th>
            <th className="num">Ondas</th>
            <th className="num">Tool calls</th>
            <th className="num">Wallclock</th>
            <th className="num">Decisões</th>
            <th className="num">Bloqueios</th>
            <th className="num">Alertas</th>
          </tr>
        </thead>
        <tbody>
          {items.map(f => {
            const aCount = D.ALERTS.filter(a => a.feature === f.id).length;
            return (
              <tr key={f.id} className="clickable" onClick={() => navigate(`#/features/${f.id}`)}>
                <td>
                  <div style={{fontWeight:500, color:'var(--text-0)'}}>{f.title}</div>
                  <div className="mono muted-2" style={{fontSize:10.5}}>{D.execId(f).slice(0, 42)}…</div>
                </td>
                <td className="mono" style={{fontSize:11.5}}>{f.project}</td>
                <td><StatusBadge status={f.status}/></td>
                <td><PipelineProgress etapa={f.etapa_corrente} status={f.status}/></td>
                <td className="num">{f.ondas_total}</td>
                <td className="num">{fmtNum(f.tool_calls_total)}</td>
                <td className="num">{fmtDur(f.wallclock_total_segundos)}</td>
                <td className="num">{f.decisoes_total}</td>
                <td className="num">{f.bloqueios_humanos_total}</td>
                <td className="num">{aCount > 0 ? <span style={{color:'var(--critical)', fontWeight: 600}}>{aCount}</span> : <span className="muted">—</span>}</td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

function FeaturesListScreen({ navigate }) {
  return (
    <div className="card">
      <div className="card-head">
        <h3>Features · todas</h3>
        <div className="row gap-2">
          <input className="input" placeholder="Buscar…" style={{width:200}}/>
          <select className="select"><option>Todos os projetos</option>{D.PROJECTS.map(p=><option key={p.id}>{p.name}</option>)}</select>
          <select className="select"><option>Todos os status</option></select>
        </div>
      </div>
      <FeaturesTable navigate={navigate}/>
    </div>
  );
}

function FeatureDetailScreen({ featureId, navigate }) {
  const f = D.FEATURES.find(x => x.id === featureId);
  if (!f) return <EmptyState title="Feature não encontrada" icon="git-branch"/>;
  const exec = D.execId(f);
  const featRetros = D.RETROS.filter(r => r.feature === featureId);

  return (
    <div className="col gap-4">
      {/* Header */}
      <div className="card">
        <div className="card-pad">
          <div className="row" style={{justifyContent:'space-between', flexWrap:'wrap', gap: 12}}>
            <div>
              <div className="row gap-2">
                <StatusBadge status={f.status}/>
                <h2 style={{margin: 0, fontSize: 20, fontWeight: 600}}>{f.title}</h2>
              </div>
              <div className="prov" style={{marginTop: 6}}>
                <a onClick={() => navigate(`#/projects/${f.project}`)}>{f.project}</a>
                <span className="sep">/</span>
                <span>{f.title}</span>
              </div>
              <div className="chip-list" style={{marginTop: 10}}>
                {f.stack_sugerida.map(s => <span key={s} className="tag">{s}</span>)}
              </div>
            </div>
            <div className="row gap-2" style={{alignItems:'flex-start'}}>
              <button className="tb-btn" onClick={() => navigate(`#/executions/${f.id}`)}>
                <Icon name="activity" size={13}/>Ver execução
              </button>
              <button className="tb-btn">
                <Icon name="tree" size={13}/>Árvore de decisões
              </button>
            </div>
          </div>

          <div className="divider"/>

          <div className="grid-6">
            <div className="mstat"><span className="label">Etapa corrente</span><span className="value mono" style={{color: f.status === 'em_andamento' ? 'var(--inprogress)' : 'var(--text-0)'}}>{f.etapa_corrente}</span></div>
            <div className="mstat"><span className="label">Ondas</span><span className="value">{f.ondas_total}</span></div>
            <div className="mstat"><span className="label">Tool calls</span><span className="value">{fmtNum(f.tool_calls_total)}</span></div>
            <div className="mstat"><span className="label">Wallclock</span><span className="value">{fmtDur(f.wallclock_total_segundos)}</span></div>
            <div className="mstat"><span className="label">Subagentes</span><span className="value">{f.subagentes_spawned}</span></div>
            <div className="mstat"><span className="label">Decisões</span><span className="value">{f.decisoes_total}</span></div>
          </div>
        </div>
      </div>

      {/* Executions list */}
      <div className="card">
        <div className="card-head"><h3>Execuções</h3><span className="sub">1 registro</span></div>
        <table className="tbl">
          <thead><tr><th>execucao_id</th><th>Status</th><th>Iniciada</th><th>Terminada</th><th className="num">Duração</th><th className="num">Ondas</th><th className="num">Tool calls</th><th>Motivo</th></tr></thead>
          <tbody>
            <tr className="clickable" onClick={() => navigate(`#/executions/${f.id}`)}>
              <td className="mono" style={{color:'var(--accent)', fontSize:11.5}}>{exec}</td>
              <td><StatusBadge status={f.status}/></td>
              <td className="mono" style={{fontSize:11.5}}>{fmtTimestamp(f.iniciada_em)}</td>
              <td className="mono" style={{fontSize:11.5}}>{fmtTimestamp(f.terminada_em)}</td>
              <td className="num">{fmtDur(f.duracao_segundos)}</td>
              <td className="num">{f.ondas_total}</td>
              <td className="num">{fmtNum(f.tool_calls_total)}</td>
              <td className="mono muted" style={{fontSize:11.5}}>{f.motivo_termino || '—'}</td>
            </tr>
          </tbody>
        </table>
      </div>

      {/* Retros */}
      <div className="card">
        <div className="card-head"><h3>Retrospectivas</h3><span className="sub">{featRetros.length} entradas</span></div>
        <div className="card-pad col" style={{gap: 8}}>
          {featRetros.length === 0 ? <EmptyState title="Sem retros ainda" hint="Retros são geradas ao final das ondas relevantes." icon="doc"/> :
            featRetros.map(r => (
              <div key={r.id} style={{background:'var(--bg-2)', padding:12, borderRadius:'var(--r-sm)', border:'1px solid var(--border)'}}>
                <div className="row gap-2" style={{marginBottom:6}}>
                  <span className="tag accent">retro</span>
                  <span className="mono muted" style={{fontSize:11.5}}>{r.wave}</span>
                </div>
                <div style={{color:'var(--text-1)', fontSize: 12.5}}>{r.texto}</div>
              </div>
            ))
          }
        </div>
      </div>
    </div>
  );
}

// ============================================================
// EXECUTION DETAIL — the rich one
// ============================================================
function ExecutionScreen({ featureId, queryParams, navigate, openDecision }) {
  const f = D.FEATURES.find(x => x.id === featureId);
  if (!f) return <EmptyState title="Execução não encontrada" icon="activity"/>;

  const initialWave = queryParams.get('wave');
  const initialTab = queryParams.get('tab') || 'decisions';

  const [selectedWave, setSelectedWave] = useStateS1(initialWave);
  const [tab, setTab] = useStateS1(initialTab);

  const waves = D.WAVES_DETAIL[featureId] || synthWaves(f);
  const decisions = featureId === 'knowledge-db-metrics' ? D.DECISIONS : D.DECISIONS.slice(0, Math.min(D.DECISIONS.length, Math.max(2, Math.floor(f.decisoes_total/5))));
  const tasks = featureId === 'knowledge-db-metrics' ? D.TASKS : D.TASKS.slice(0, Math.max(2, Math.floor(f.ondas_total/2)));
  const events = featureId === 'knowledge-db-metrics' ? D.EVENTS : D.EVENTS.slice(0, Math.max(1, f.ondas_total - 4));
  const featAlerts = D.ALERTS.filter(a => a.feature === featureId);
  const featBlocks = D.BLOQUEIOS.filter(b => b.feature === featureId);

  const filteredDecisions = selectedWave ? decisions.filter(d => d.wave === selectedWave) : decisions;
  const filteredTasks = selectedWave ? tasks.filter(t => t.wave === selectedWave) : tasks;
  const filteredEvents = selectedWave ? events.filter(e => e.wave === selectedWave) : events;
  const filteredAlerts = selectedWave ? featAlerts.filter(a => a.wave === selectedWave) : featAlerts;

  const totalTC = waves.reduce((a, w) => a + w.tool_calls, 0);
  const totalWS = waves.reduce((a, w) => a + w.wallclock_seconds, 0);
  const maxWaveTC = Math.max(...waves.map(w => w.tool_calls)) || 1;

  // Score distribution for this execution
  const scoreDist = [0,1,2,3].map(s => decisions.filter(d => d.score === s).length);

  // Skill invocations (use global sample, scaled down)
  const topSkills = D.SKILLS_INVOCATIONS.slice(0, 6);

  const tabs = [
    { value:'decisions', label:'Decisões', count: filteredDecisions.length },
    { value:'tasks',     label:'Tarefas',  count: filteredTasks.length },
    { value:'events',    label:'Eventos',  count: filteredEvents.length },
    { value:'alerts',    label:'Alertas',  count: filteredAlerts.length },
    { value:'blocks',    label:'Bloqueios',count: featBlocks.length },
  ];

  return (
    <div className="col gap-4">
      {/* Header */}
      <div className="card">
        <div className="card-pad">
          <div className="row" style={{justifyContent:'space-between', flexWrap:'wrap', gap: 12}}>
            <div style={{minWidth:0}}>
              <div className="row gap-2">
                <StatusBadge status={f.status}/>
                <span className="mono" style={{color:'var(--text-3)', fontSize: 11}}>execução</span>
                <span className="mono" style={{color:'var(--accent)', fontSize: 12, fontWeight: 600}}>{D.execId(f)}</span>
              </div>
              <h2 style={{margin: '4px 0 6px 0', fontSize: 20, fontWeight: 600}}>{f.title}</h2>
              <div className="prov">
                <a onClick={() => navigate(`#/projects/${f.project}`)}>{f.project}</a>
                <span className="sep">·</span>
                <a onClick={() => navigate(`#/features/${f.id}`)}>{f.title}</a>
                <span className="sep">·</span>
                <span>iniciada {fmtTimestamp(f.iniciada_em)}</span>
              </div>
            </div>
            <div className="row gap-2">
              <button className="tb-btn"><Icon name="tree" size={13}/>árvore de decisões</button>
              <button className="tb-btn primary"><Icon name="external" size={13}/>abrir no recall</button>
            </div>
          </div>

          <div className="divider"/>

          <div className="grid-6">
            <div className="mstat"><span className="label">Etapa corrente</span><span className="value mono" style={{color: f.status === 'em_andamento' ? 'var(--inprogress)' : 'var(--text-0)'}}>{f.etapa_corrente}</span></div>
            <div className="mstat"><span className="label">Duração</span><span className="value">{fmtDur(f.duracao_segundos)}</span></div>
            <div className="mstat"><span className="label">Tool calls</span><span className="value">{fmtNum(f.tool_calls_total)}</span></div>
            <div className="mstat"><span className="label">Ondas</span><span className="value">{f.ondas_total}</span></div>
            <div className="mstat"><span className="label">Subagentes</span><span className="value">{f.subagentes_spawned}</span></div>
            <div className="mstat"><span className="label">Profundidade máx</span><span className="value">{f.profundidade_max}</span></div>
          </div>

          <div style={{marginTop: 14}}>
            <PipelineProgress etapa={f.etapa_corrente} status={f.status} labeled/>
          </div>
        </div>
      </div>

      {/* Two-column: Waves timeline (left, big) + side stats (right) */}
      <div style={{display:'grid', gridTemplateColumns:'1fr 280px', gap: 14}}>
        <div className="card">
          <div className="card-head">
            <h3>Linha do tempo de ondas · gantt</h3>
            <div className="row gap-2">
              <Legend items={[
                { color: 'var(--success)', label: 'avançou etapa' },
                { color: 'var(--warning)', label: 'threshold proxy' },
                { color: 'var(--info)',    label: 'bloqueio humano' },
                { color: 'var(--critical)',label: 'aborto' },
              ]}/>
              {selectedWave && (
                <button className="ico-btn" onClick={() => setSelectedWave(null)} title="limpar seleção">
                  <Icon name="x" size={12}/>
                </button>
              )}
            </div>
          </div>
          <div className="card-pad waves">
            <div className="wave-row" style={{color:'var(--text-3)', textTransform:'uppercase', fontSize: 10, letterSpacing:'0.08em', cursor:'default', fontWeight:600}}>
              <span>onda</span>
              <span>etapa</span>
              <span>tool_calls · barra</span>
              <span style={{textAlign:'right'}}>skills</span>
              <span style={{textAlign:'right'}}>wallclock</span>
            </div>
            {waves.map(w => {
              const widthPct = Math.max(8, (w.tool_calls / maxWaveTC) * 100);
              const selected = selectedWave === w.wave;
              return (
                <div key={w.wave} className={`wave-row ${selected ? 'selected' : ''}`} onClick={() => setSelectedWave(selected ? null : w.wave)}>
                  <span className="wave-id">{w.wave}</span>
                  <span className="wave-etapa">{w.etapa}</span>
                  <div className="wave-bar-wrap">
                    <div className={`wave-bar ${w.motivo_termino}`} style={{width: `${widthPct}%`}}>
                      <span style={{whiteSpace:'nowrap'}}>{w.tool_calls} · {fmtDur(w.wallclock_seconds)}</span>
                    </div>
                  </div>
                  <span className="mono" style={{textAlign:'right', color:'var(--text-1)', fontSize:11.5}}>{w.n_skills}</span>
                  <span className="mono" style={{textAlign:'right', color:'var(--text-1)', fontSize:11.5}}>{fmtDur(w.wallclock_seconds)}</span>
                </div>
              );
            })}
            <div className="row" style={{justifyContent:'space-between', marginTop:8, padding: '8px 12px', borderTop:'1px solid var(--border)', color:'var(--text-2)', fontSize:11.5}}>
              <span>{waves.length} ondas</span>
              <span className="mono">Σ {totalTC} tool_calls · {fmtDur(totalWS)} wallclock</span>
            </div>
          </div>
        </div>

        <div className="col gap-3">
          {/* Decisions by score */}
          <div className="card">
            <div className="card-head"><h3>Decisões por score</h3></div>
            <div className="card-pad col" style={{gap: 8}}>
              {scoreDist.map((c, i) => {
                const max = Math.max(...scoreDist) || 1;
                return (
                  <div key={i} className="row" style={{gap: 8, alignItems:'center'}}>
                    <ScoreChip score={i}/>
                    <div style={{flex:1, height:6, background:'var(--bg-3)', borderRadius:3, overflow:'hidden'}}>
                      <div style={{width: `${(c/max)*100}%`, height:'100%', background: ['var(--score-0)','var(--score-1)','var(--score-2)','var(--score-3)'][i]}}/>
                    </div>
                    <span className="mono" style={{width: 20, textAlign:'right', fontSize:11.5}}>{c}</span>
                  </div>
                );
              })}
            </div>
          </div>

          {/* Top skills */}
          <div className="card">
            <div className="card-head"><h3>Skills mais invocadas</h3></div>
            <div className="card-pad">
              <BarH
                data={topSkills.map(s => ({ label: s.skill_name, value: s.count, color: 'var(--info)' }))}
                maxLabel={110}
              />
            </div>
          </div>

          {/* Suggestions + issues */}
          <div className="card">
            <div className="card-pad">
              <div className="row" style={{justifyContent:'space-between'}}>
                <div className="mstat"><span className="label">Sugestões ao toolkit</span><span className="value">{f.sugestoes_skills_total}</span></div>
                <div className="mstat"><span className="label">Issues abertas</span><span className="value" style={{color: f.issues_toolkit_abertas > 0 ? 'var(--warning)' : 'var(--text-0)'}}>{f.issues_toolkit_abertas}</span></div>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Tabs */}
      <div className="card">
        <Tabs items={tabs} value={tab} onChange={setTab}/>
        <div>
          {tab === 'decisions' && (
            <DecisionsTable items={filteredDecisions} openDecision={openDecision}/>
          )}
          {tab === 'tasks' && (
            <TasksPanel items={filteredTasks}/>
          )}
          {tab === 'events' && (
            <EventsPanel items={filteredEvents}/>
          )}
          {tab === 'alerts' && (
            <AlertsPanel items={filteredAlerts}/>
          )}
          {tab === 'blocks' && (
            <BlocksPanel items={featBlocks} openDecision={openDecision}/>
          )}
        </div>
      </div>
    </div>
  );
}

// Synthesize waves for features that don't have detail data
function synthWaves(f) {
  const stages = D.SDD_STAGES;
  const ondas = Math.max(2, f.ondas_total);
  const waves = [];
  const perWaveTC = Math.max(20, Math.floor(f.tool_calls_total / ondas));
  const perWaveWS = Math.max(60, Math.floor(f.wallclock_total_segundos / ondas));
  for (let i = 0; i < ondas; i++) {
    const stage = stages[Math.min(i, stages.length - 1)];
    const motivo = (i === ondas - 1)
      ? (f.status === 'concluida' ? 'concluido' : (f.status === 'abortada' ? 'aborto' : (f.status === 'aguardando_humano' ? 'bloqueio_humano' : 'etapa_concluida_avancando')))
      : 'etapa_concluida_avancando';
    waves.push({
      wave: `onda-${String(i+1).padStart(3,'0')}`,
      etapa: stage,
      wallclock_seconds: Math.floor(perWaveWS * (0.6 + Math.random() * 0.8)),
      tool_calls: Math.floor(perWaveTC * (0.5 + Math.random() * 1.0)),
      motivo_termino: motivo,
      n_etapas: 1,
      n_skills: 1 + Math.floor(Math.random() * 4),
    });
  }
  return waves;
}

// ---------- Decisions table (with row expand) ----------
function DecisionsTable({ items, openDecision }) {
  const [expanded, setExpanded] = useStateS1(null);
  if (!items.length) return <EmptyState title="Sem decisões nesta onda" hint="Selecione outra onda no gantt." icon="tree"/>;
  return (
    <table className="tbl">
      <thead>
        <tr>
          <th style={{width: 40}}></th>
          <th>Escolha</th>
          <th>Etapa</th>
          <th>Agente</th>
          <th>Onda</th>
          <th>Score</th>
          <th></th>
        </tr>
      </thead>
      <tbody>
        {items.map(d => (
          <React.Fragment key={d.id}>
            <tr className="clickable" onClick={() => setExpanded(expanded === d.id ? null : d.id)}>
              <td><Icon name={expanded === d.id ? 'chevron-down' : 'chevron-right'} size={12} style={{color:'var(--text-3)'}}/></td>
              <td><span style={{color:'var(--text-0)'}}>{d.escolha}</span></td>
              <td className="mono" style={{fontSize:11.5}}>{d.etapa}</td>
              <td className="mono muted" style={{fontSize:11.5}}>{d.agente}</td>
              <td className="mono" style={{fontSize:11.5}}>{d.wave}</td>
              <td><ScoreChip score={d.score}/></td>
              <td className="text-right"><button className="tb-btn" onClick={e => { e.stopPropagation(); openDecision(d); }}><Icon name="eye" size={12}/>detalhe</button></td>
            </tr>
            {expanded === d.id && (
              <tr>
                <td colSpan="7" style={{background:'var(--bg-2)', padding: 16}}>
                  <div className="col" style={{gap: 8}}>
                    <DecisionField label="contexto" value={d.contexto}/>
                    <DecisionField label="justificativa" value={d.justificativa}/>
                    <DecisionField label="evidencia" value={d.evidencia} mono/>
                  </div>
                </td>
              </tr>
            )}
          </React.Fragment>
        ))}
      </tbody>
    </table>
  );
}

function DecisionField({ label, value, mono }) {
  return (
    <div>
      <div className="mono" style={{fontSize:10.5, color:'var(--text-3)', textTransform:'uppercase', letterSpacing:'0.08em', marginBottom: 2}}>{label}</div>
      <div className={mono ? 'mono' : ''} style={{fontSize: mono ? 11.5 : 12.5, color: mono ? 'var(--accent)' : 'var(--text-1)', background: mono ? 'var(--bg-1)' : 'transparent', padding: mono ? '6px 10px' : 0, borderRadius: 4, border: mono ? '1px solid var(--border)' : 'none'}}>{value}</div>
    </div>
  );
}

function TasksPanel({ items }) {
  if (!items.length) return <EmptyState title="Sem tarefas nesta onda" icon="check"/>;
  const total = items.length;
  const tr = items.reduce((a, t) => a + t.testes_rodados, 0);
  const tp = items.reduce((a, t) => a + t.testes_passados, 0);
  const lint = items.filter(t => t.lint_ok).length;
  const failing = items.filter(t => t.outcome === 'fail').length;

  return (
    <div>
      <div style={{padding: 14, borderBottom:'1px solid var(--border)'}}>
        <div className="grid-4" style={{gap: 12}}>
          <div className="mstat"><span className="label">Tarefas</span><span className="value">{total}</span></div>
          <div className="mstat"><span className="label">Pass rate</span><span className="value" style={{color: failing > 0 ? 'var(--warning)' : 'var(--success)'}}>{tr ? `${(tp/tr*100).toFixed(1)}%` : '—'}</span></div>
          <div className="mstat"><span className="label">Lint OK</span><span className="value">{lint}/{total}</span></div>
          <div className="mstat"><span className="label">Fails</span><span className="value" style={{color: failing > 0 ? 'var(--critical)' : 'var(--success)'}}>{failing}</span></div>
        </div>
      </div>
      <table className="tbl">
        <thead><tr><th>Task</th><th>Onda</th><th>Outcome</th><th className="num">Testes</th><th>Lint</th><th className="num">Arquivos</th></tr></thead>
        <tbody>
          {items.map(t => (
            <tr key={t.id}>
              <td>
                <div style={{color:'var(--text-0)'}}>{t.titulo}</div>
                <div className="mono muted-2" style={{fontSize:10.5}}>{t.id}</div>
              </td>
              <td className="mono" style={{fontSize:11.5}}>{t.wave}</td>
              <td><OutcomePill outcome={t.outcome}/></td>
              <td className="num">{t.testes_passados}/{t.testes_rodados}</td>
              <td>{t.lint_ok ? <span className="pill pass">✓ ok</span> : <span className="pill fail">✕ falhou</span>}</td>
              <td className="num">{t.arquivos_tocados}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function EventsPanel({ items }) {
  if (!items.length) return <EmptyState title="Sem eventos" icon="zap"/>;
  return (
    <div className="card-pad">
      <div className="events">
        {items.map(e => {
          const m = EVENT_META[e.event_type] || { icon: 'zap', color: 'var(--text-2)', label: e.event_type };
          return (
            <div key={e.id} className={`event ${e.event_type}`}>
              <span className="time">{e.timestamp}</span>
              <div>
                <div className="row gap-2" style={{marginBottom: 2}}>
                  <Icon name={m.icon} size={12} style={{color: m.color}}/>
                  <span className="mono" style={{fontSize:11.5, color: m.color, fontWeight: 600}}>{m.label}</span>
                  <span className="muted mono" style={{fontSize:11}}>· {e.wave}</span>
                </div>
                <div className="body">{e.descricao}</div>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function AlertsPanel({ items }) {
  if (!items.length) return <EmptyState title="Sem alertas" hint="Tudo sob controle." icon="alert"/>;
  return (
    <div className="card-pad grid-2" style={{gap: 12}}>
      {items.map(a => (
        <div key={a.id} style={{background:'var(--bg-2)', padding:14, borderRadius:'var(--r-md)', border:'1px solid var(--border)'}}>
          <div className="row" style={{justifyContent:'space-between', marginBottom:10}}>
            <div className="row gap-2">
              <Icon name={a.tipo === 'circular' ? 'retry' : 'flame'} size={14} style={{color: a.severity === 'critical' ? 'var(--critical)' : 'var(--warning)'}}/>
              <span className="mono" style={{color:'var(--text-0)', fontSize:12, fontWeight:600}}>
                {a.tipo === 'circular' ? 'movimento circular' : `budget_breach · ${a.subtipo}`}
              </span>
            </div>
            <SeverityBadge severity={a.severity}/>
          </div>
          <div style={{color:'var(--text-1)', fontSize:12.5, marginBottom: 12}}>{a.descricao}</div>
          <BudgetMini value={a.valor_consumido} threshold={a.valor_threshold} unit={a.subtipo === 'wallclock' ? 's' : ''}/>
          <div className="row" style={{justifyContent:'space-between', marginTop: 10, fontSize:11}}>
            <span className="muted">{a.wave}</span>
            <span className="mono muted">{fmtTimestamp(a.timestamp)}</span>
          </div>
        </div>
      ))}
    </div>
  );
}

function BlocksPanel({ items, openDecision }) {
  if (!items.length) return <EmptyState title="Sem bloqueios humanos" hint="Nenhuma pergunta escalada nesta execução." icon="users"/>;
  return (
    <div className="card-pad col" style={{gap: 10}}>
      {items.map(b => (
        <div key={b.id} style={{background:'var(--bg-2)', padding:14, borderRadius:'var(--r-md)', border:'1px solid var(--border)'}}>
          <div className="row" style={{justifyContent:'space-between', marginBottom: 10}}>
            <div className="row gap-2">
              <Icon name="users" size={14} style={{color: b.status === 'aberto' ? 'var(--warning)' : 'var(--success)'}}/>
              <span className="mono" style={{fontSize:12, fontWeight:600, color:'var(--text-0)'}}>{b.id}</span>
              <span className={`badge ${b.status === 'aberto' ? 'aguardando_humano' : 'concluida'}`}><span className="dot"/>{b.status}</span>
            </div>
            <div className="row gap-2">
              {b.latencia_segundos != null && (
                <div className="mstat" style={{alignItems:'flex-end'}}>
                  <span className="label">latência humana</span>
                  <span className="value" style={{color: b.latencia_segundos > 1500 ? 'var(--warning)' : 'var(--text-0)'}}>{fmtDur(b.latencia_segundos)}</span>
                </div>
              )}
            </div>
          </div>
          <div style={{marginBottom: 10}}>
            <div className="mono muted-2" style={{fontSize:10.5, textTransform:'uppercase', letterSpacing:'0.08em'}}>pergunta</div>
            <div style={{fontSize: 13, color:'var(--text-0)', marginTop:2}}>{b.pergunta}</div>
          </div>
          <div style={{marginBottom: 10}}>
            <div className="mono muted-2" style={{fontSize:10.5, textTransform:'uppercase', letterSpacing:'0.08em'}}>contexto</div>
            <div style={{fontSize:12, color:'var(--text-1)', marginTop:2}}>{b.contexto_para_resposta}</div>
          </div>
          {b.resposta && (
            <div style={{padding: 10, background:'var(--bg-1)', border:'1px solid var(--border)', borderLeft:'2px solid var(--success)', borderRadius:4}}>
              <div className="mono muted-2" style={{fontSize:10.5, textTransform:'uppercase', letterSpacing:'0.08em'}}>resposta</div>
              <div style={{fontSize:12.5, color:'var(--text-0)', marginTop:2}}>{b.resposta}</div>
            </div>
          )}
          <div className="row" style={{justifyContent:'space-between', marginTop: 10, fontSize:11}}>
            <span className="muted mono">{b.wave} · {fmtTimestamp(b.disparado_em)}</span>
            {b.decisao_id && (
              <a className="hover-link" style={{color:'var(--accent)', cursor:'pointer', fontSize:11.5}} onClick={() => openDecision({ id: b.decisao_id, escolha:'(ver detalhe)' })}>
                → decisão {b.decisao_id}
              </a>
            )}
          </div>
        </div>
      ))}
    </div>
  );
}

Object.assign(window, {
  OverviewScreen, ProjectsScreen, ProjectDetailScreen,
  FeaturesListScreen, FeatureDetailScreen,
  ExecutionScreen, DecisionsTable, TasksPanel, EventsPanel, AlertsPanel, BlocksPanel,
});
