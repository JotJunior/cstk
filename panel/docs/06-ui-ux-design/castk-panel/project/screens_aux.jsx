// cstk-panel — auxiliary screens: Alerts, Metrics, Tasks, Incidents, Search, Source

const { useState: useStateS2, useMemo: useMemoS2 } = React;
const Dx = window.CSTKData;

// ============================================================
// ALERTS
// ============================================================
function AlertsScreen({ navigate }) {
  const [filterTipo, setFilterTipo] = useStateS2('all');
  const [filterProj, setFilterProj] = useStateS2('all');

  const items = Dx.ALERTS.filter(a =>
    (filterTipo === 'all' || a.tipo === filterTipo) &&
    (filterProj === 'all' || a.project === filterProj)
  );

  const byTipo = {
    circular: Dx.ALERTS.filter(a => a.tipo === 'circular').length,
    budget_breach: Dx.ALERTS.filter(a => a.tipo === 'budget_breach').length,
  };
  const bySev = {
    critical: Dx.ALERTS.filter(a => a.severity === 'critical').length,
    warning: Dx.ALERTS.filter(a => a.severity === 'warning').length,
    info: Dx.ALERTS.filter(a => a.severity === 'info').length,
  };

  // Trend sparkline data (last 7d) — synthetic
  const trend7d = [
    {v:1},{v:0},{v:2},{v:1},{v:3},{v:2},{v:Dx.ALERTS.length}
  ];

  return (
    <div className="col gap-4">
      <div className="grid-4">
        <KpiCard label="Total · 7d" value={Dx.ALERTS.length} icon="alert" critical={bySev.critical > 0} spark={trend7d} sparkColor="var(--critical)"/>
        <KpiCard label="Movimento circular" value={byTipo.circular} icon="retry" critical={byTipo.circular > 0}
          footnote="loop detectado em clarify/plan"/>
        <KpiCard label="Breach de orçamento" value={byTipo.budget_breach} icon="flame" warning
          footnote="tool_calls · wallclock · ciclos · recursão · estado"/>
        <KpiCard label="Severidades" value={`${bySev.critical}·${bySev.warning}·${bySev.info}`}
          footnote="crítico · atenção · info" icon="bar"/>
      </div>

      <div className="card">
        <div className="card-head">
          <div className="row gap-2">
            <h3>Central de alertas</h3>
            <span className="sub mono">{items.length} resultados</span>
          </div>
          <div className="row gap-2">
            <select className="select" value={filterTipo} onChange={e => setFilterTipo(e.target.value)}>
              <option value="all">Todos os tipos</option>
              <option value="circular">movimento circular</option>
              <option value="budget_breach">budget_breach</option>
            </select>
            <select className="select" value={filterProj} onChange={e => setFilterProj(e.target.value)}>
              <option value="all">Todos os projetos</option>
              {Dx.PROJECTS.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}
            </select>
            <button className="tb-btn"><Icon name="filter" size={12}/>mais filtros</button>
          </div>
        </div>

        <table className="tbl">
          <thead>
            <tr>
              <th>Tipo</th>
              <th>Proveniência</th>
              <th>Descrição</th>
              <th>Consumido / Threshold</th>
              <th>Severidade</th>
              <th>Quando</th>
            </tr>
          </thead>
          <tbody>
            {items.map(a => (
              <tr key={a.id} className="clickable" onClick={() => navigate(`#/executions/${a.feature}?wave=${a.wave}&tab=alerts`)}>
                <td>
                  <div className="row gap-2">
                    <Icon name={a.tipo === 'circular' ? 'retry' : 'flame'} size={13} style={{color: a.severity === 'critical' ? 'var(--critical)' : 'var(--warning)'}}/>
                    <span className="mono" style={{fontSize:12, fontWeight:600, color:'var(--text-0)'}}>
                      {a.tipo === 'circular' ? 'circular' : `breach·${a.subtipo}`}
                    </span>
                  </div>
                </td>
                <td>
                  <div className="prov">
                    <a>{a.project}</a><span className="sep">/</span>
                    <a>{a.feature}</a><span className="sep">/</span>
                    <a>{a.wave}</a>
                  </div>
                </td>
                <td style={{maxWidth: 380, color:'var(--text-1)'}}>{a.descricao}</td>
                <td><BudgetMini value={a.valor_consumido} threshold={a.valor_threshold} unit={a.subtipo === 'wallclock' ? 's' : ''}/></td>
                <td><SeverityBadge severity={a.severity}/></td>
                <td className="mono muted" style={{fontSize:11.5}}>{fmtTimestamp(a.timestamp)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

// ============================================================
// MÉTRICAS (Analytics)
// ============================================================
function MetricsScreen() {
  const passRatePct = (() => {
    const p = Dx.FEATURES.reduce((a, f) => a + f.test_pass, 0);
    const t = Dx.FEATURES.reduce((a, f) => a + f.test_total, 0);
    return t ? p/t : 0;
  })();

  const mix = Dx.MODEL_MIX.total;
  const modelDonut = [
    { label: 'haiku', value: mix.haiku, color: 'var(--model-haiku)' },
    { label: 'sonnet', value: mix.sonnet, color: 'var(--model-sonnet)' },
    { label: 'opus', value: mix.opus, color: 'var(--model-opus)' },
    { label: 'manter-atual', value: mix['manter-atual'], color: 'var(--model-fallback)' },
  ];

  // Throughput per stage = sum tool_calls per stage in waves (use knowledge-db-metrics)
  const stageAgg = {};
  Object.values(Dx.WAVES_DETAIL).flat().forEach(w => {
    stageAgg[w.etapa] = (stageAgg[w.etapa] || 0) + w.tool_calls;
  });
  const stageData = Dx.SDD_STAGES.map(s => ({ label: s, value: stageAgg[s] || 0, color: 'var(--accent)' }));

  // Clarify auto-resolution = decisions w/ score>=2 in clarify vs bloqueios
  const clarifyDec = Dx.DECISIONS.filter(d => d.etapa === 'clarify');
  const autoResolved = clarifyDec.filter(d => d.score >= 2).length;
  const escalated = Dx.BLOQUEIOS.length; // proxy
  const clarifyRate = (autoResolved + escalated) ? autoResolved / (autoResolved + escalated) : 0;

  // Mix by stage (stacked) — top 4 stages
  const stackedKeys = ['haiku','sonnet','opus','manter-atual'];
  const stackedColors = ['var(--model-haiku)','var(--model-sonnet)','var(--model-opus)','var(--model-fallback)'];
  const stackedData = Dx.SDD_STAGES.map(s => {
    const v = Dx.MODEL_MIX.by_etapa[s] || {};
    return { d: s.slice(0, 6), haiku: v.haiku*100, sonnet: v.sonnet*100, opus: v.opus*100, 'manter-atual': v['manter-atual']*100 };
  });

  // Subagents / depth scatter
  const scatter = Dx.FEATURES.map(f => ({ x: f.profundidade_max, y: f.subagentes_spawned, label: f.title, status: f.status }));

  return (
    <div className="col gap-4">
      <div className="grid-4">
        <KpiCard label="Test pass rate" value={fmtPct(passRatePct, 1)} icon="check" footnote={`${Dx.FEATURES.reduce((a,f)=>a+f.test_pass,0)} / ${Dx.FEATURES.reduce((a,f)=>a+f.test_total,0)} testes`} accent/>
        <KpiCard label="Auto-resolve · clarify" value={fmtPct(clarifyRate, 0)}
          footnote={`${autoResolved} auto · ${escalated} escalado a humano`} icon="users"
          tip="Decisões na etapa clarify com score≥2 versus bloqueios escalados a humano." />
        <KpiCard label="Taxa de fallback" value={fmtPct(Dx.MODEL_MIX.fallback_rate)} icon="retry" warning footnote="manter-atual quando modelo alvo indisponível"/>
        <KpiCard label="Latência humana p50" value={fmtDur(median(Dx.HUMAN_LATENCY))}
          footnote={`p95 ${fmtDur(quantile(Dx.HUMAN_LATENCY, 0.95))}`} icon="clock"/>
      </div>

      <div className="grid-2">
        <div className="card">
          <div className="card-head"><h3>Custo no tempo · proxy</h3><span className="sub mono">tool_calls por dia · 14d</span></div>
          <div className="card-pad"><AreaChart data={Dx.COST_TIMESERIES} color="var(--accent)" height={200}/></div>
        </div>
        <div className="card">
          <div className="card-head"><h3>Test pass rate · 14d</h3><span className="sub mono">% por dia</span></div>
          <div className="card-pad"><AreaChart data={Dx.PASS_RATE_SERIES.map(d => ({d:d.d, v: d.v*100}))} color="var(--success)" height={200} yFmt={v => v.toFixed(0)+'%'}/></div>
        </div>
      </div>

      <div className="grid-2">
        <div className="card">
          <div className="card-head"><h3>Throughput por etapa</h3><span className="sub mono">Σ tool_calls</span></div>
          <div className="card-pad"><BarH data={stageData} maxLabel={120}/></div>
        </div>
        <div className="card">
          <div className="card-head"><h3>Mix de modelos por etapa</h3>
            <Legend items={[
              { color:'var(--model-haiku)', label:'haiku' },
              { color:'var(--model-sonnet)', label:'sonnet' },
              { color:'var(--model-opus)', label:'opus' },
              { color:'var(--model-fallback)', label:'manter-atual' },
            ]}/>
          </div>
          <div className="card-pad">
            <StackedBars data={stackedData} keys={stackedKeys} colors={stackedColors} height={180}/>
          </div>
        </div>
      </div>

      <div className="grid-3">
        <div className="card">
          <div className="card-head"><h3>Latência humana</h3><span className="sub mono">histograma · 15 amostras</span></div>
          <div className="card-pad">
            <Histogram values={Dx.HUMAN_LATENCY} bins={8} color="var(--info)"/>
            <div className="row" style={{justifyContent:'space-around', marginTop: 8, fontSize:11.5}}>
              <div className="mstat" style={{alignItems:'center'}}><span className="label">p50</span><span className="value">{fmtDur(median(Dx.HUMAN_LATENCY))}</span></div>
              <div className="mstat" style={{alignItems:'center'}}><span className="label">p95</span><span className="value">{fmtDur(quantile(Dx.HUMAN_LATENCY, 0.95))}</span></div>
              <div className="mstat" style={{alignItems:'center'}}><span className="label">max</span><span className="value">{fmtDur(Math.max(...Dx.HUMAN_LATENCY))}</span></div>
            </div>
          </div>
        </div>
        <div className="card">
          <div className="card-head"><h3>Mix de modelos · total</h3></div>
          <div className="card-pad row" style={{gap: 14}}>
            <Donut data={modelDonut} size={130} thickness={20} centerLabel="seleções" centerValue={Math.round(modelDonut.reduce((a,d)=>a+d.value*100,0))}/>
            <div className="col" style={{flex:1, gap:6}}>
              {modelDonut.map(m => (
                <div key={m.label} className="row" style={{justifyContent:'space-between'}}>
                  <div className="row gap-2"><span style={{width:8,height:8,borderRadius:2,background:m.color}}/><span className="mono" style={{fontSize:11.5}}>{m.label}</span></div>
                  <span className="mono" style={{fontSize:12}}>{fmtPct(m.value)}</span>
                </div>
              ))}
            </div>
          </div>
        </div>
        <div className="card">
          <div className="card-head"><h3>Profundidade · subagentes</h3><span className="sub mono">scatter por execução</span></div>
          <div className="card-pad">
            <ScatterChart data={scatter}/>
          </div>
        </div>
      </div>

      <div className="card">
        <div className="card-head"><h3>Decisões por score · todas execuções</h3><span className="sub">{Object.values(Dx.SCORE_DIST).reduce((a,b)=>a+b,0)} decisões</span></div>
        <div className="card-pad">
          <BarH
            data={[
              { label: 'score 0 · pausa / humano',     value: Dx.SCORE_DIST[0], color: 'var(--score-0)' },
              { label: 'score 1 · pausa',              value: Dx.SCORE_DIST[1], color: 'var(--score-1)' },
              { label: 'score 2 · decide por contexto', value: Dx.SCORE_DIST[2], color: 'var(--score-2)' },
              { label: 'score 3 · decide com evidência',value: Dx.SCORE_DIST[3], color: 'var(--score-3)' },
            ]}
            maxLabel={220}
          />
        </div>
      </div>
    </div>
  );
}

function ScatterChart({ data }) {
  const W = 360, H = 180, padT = 14, padB = 28, padL = 30, padR = 14;
  const innerW = W - padL - padR;
  const innerH = H - padT - padB;
  const xs = data.map(d => d.x);
  const ys = data.map(d => d.y);
  const xMax = Math.max(...xs, 5);
  const yMax = Math.max(...ys, 12);
  const xAt = v => padL + (v / xMax) * innerW;
  const yAt = v => padT + innerH - (v / yMax) * innerH;
  const colorOf = s => s === 'concluida' ? 'var(--success)' : s === 'em_andamento' ? 'var(--inprogress)' : s === 'abortada' ? 'var(--critical)' : 'var(--warning)';
  return (
    <svg width="100%" height={H} viewBox={`0 0 ${W} ${H}`}>
      {[0, 0.5, 1].map((f, i) => (
        <line key={i} x1={padL} x2={W-padR} y1={padT + innerH*(1-f)} y2={padT + innerH*(1-f)} stroke="var(--border)" strokeWidth="0.5"/>
      ))}
      {data.map((d, i) => (
        <g key={i}>
          <circle cx={xAt(d.x)} cy={yAt(d.y)} r="5" fill={colorOf(d.status)} opacity="0.85"/>
        </g>
      ))}
      <text x={padL} y={H - 8} fontSize="9.5" fill="var(--text-3)" fontFamily="var(--font-mono)">profundidade →</text>
      <text x={4} y={padT + 6} fontSize="9.5" fill="var(--text-3)" fontFamily="var(--font-mono)">subagentes</text>
    </svg>
  );
}

function median(arr) { const s = [...arr].sort((a,b)=>a-b); return s[Math.floor(s.length/2)]; }
function quantile(arr, q) { const s = [...arr].sort((a,b)=>a-b); return s[Math.floor(s.length*q)]; }

// ============================================================
// TAREFAS (cross-execução)
// ============================================================
function TasksScreen({ navigate }) {
  // Build cross-execution task list by fanning out
  const allTasks = [
    ...Dx.TASKS.map(t => ({ ...t, feature: 'knowledge-db-metrics', project: 'claude-ai-tips' })),
    { id:'t-301', wave:'onda-005', feature:'agente-00c-model-routing', project:'cstk-orquestra',
      titulo:'router: selecionar modelo por disponibilidade + custo proxy', outcome:'pass', testes_rodados:42, testes_passados:42, lint_ok:1, arquivos_tocados:3 },
    { id:'t-302', wave:'onda-006', feature:'agente-00c-model-routing', project:'cstk-orquestra',
      titulo:'fallback de modelo: aplicar manter-atual quando opus indisponível', outcome:'pass', testes_rodados:36, testes_passados:35, lint_ok:1, arquivos_tocados:2 },
    { id:'t-303', wave:'onda-002', feature:'cstk-cli-watch', project:'cstk-recall',
      titulo:'parsing de inotify events em python 3.12', outcome:'fail', testes_rodados:14, testes_passados:9, lint_ok:0, arquivos_tocados:4 },
    { id:'t-304', wave:'onda-003', feature:'recall-fts-rerank', project:'cstk-recall',
      titulo:'rerank de resultados bm25 por proveniência', outcome:'pass', testes_rodados:18, testes_passados:18, lint_ok:1, arquivos_tocados:2 },
    { id:'t-305', wave:'onda-004', feature:'recall-autoconsume', project:'claude-ai-tips',
      titulo:'autoconsume: versionar stop-words no schema', outcome:'pass', testes_rodados:22, testes_passados:22, lint_ok:1, arquivos_tocados:3 },
    { id:'t-306', wave:'onda-008', feature:'cstk-knowledge-db', project:'claude-ai-tips',
      titulo:'definir índices FTS5 para fts_decisoes e fts_retros', outcome:'pass', testes_rodados:48, testes_passados:48, lint_ok:1, arquivos_tocados:4 },
  ];

  const [outcomeFilter, setOutcomeFilter] = useStateS2('all');
  const filtered = outcomeFilter === 'all' ? allTasks : allTasks.filter(t => t.outcome === outcomeFilter);

  const total = allTasks.length;
  const passes = allTasks.filter(t => t.outcome === 'pass').length;
  const fails = allTasks.filter(t => t.outcome === 'fail').length;
  const tr = allTasks.reduce((a, t) => a + t.testes_rodados, 0);
  const tp = allTasks.reduce((a, t) => a + t.testes_passados, 0);
  const avgFiles = (allTasks.reduce((a, t) => a + t.arquivos_tocados, 0) / total).toFixed(1);
  const lintPct = allTasks.filter(t => t.lint_ok).length / total;

  // Pass/fail over time — synthesize
  const ptSeries = [
    { d:'05-11', pass:2, fail:0 },
    { d:'05-12', pass:4, fail:0 },
    { d:'05-14', pass:3, fail:1 },
    { d:'05-15', pass:5, fail:0 },
    { d:'05-17', pass:2, fail:0 },
    { d:'05-19', pass:1, fail:1 },
    { d:'05-21', pass:4, fail:0 },
    { d:'05-23', pass:3, fail:0 },
    { d:'05-24', pass:8, fail:1 },
  ];

  return (
    <div className="col gap-4">
      <div className="grid-5">
        <KpiCard label="Tasks · total" value={total} icon="check"/>
        <KpiCard label="Pass rate · testes" value={`${(tp/tr*100).toFixed(1)}%`} accent={tp===tr} footnote={`${tp} / ${tr}`}/>
        <KpiCard label="Fails" value={fails} critical={fails>0} icon="cancel"/>
        <KpiCard label="Lint OK" value={fmtPct(lintPct)} icon="check"/>
        <KpiCard label="Arquivos tocados · média" value={avgFiles} icon="doc"/>
      </div>

      <div className="grid-2">
        <div className="card">
          <div className="card-head"><h3>Pass / fail no tempo</h3></div>
          <div className="card-pad">
            <StackedBars
              data={ptSeries}
              keys={['pass','fail']}
              colors={['var(--success)','var(--critical)']}
              height={160}
            />
            <Legend items={[
              { color:'var(--success)', label:'pass' },
              { color:'var(--critical)', label:'fail' },
            ]}/>
          </div>
        </div>
        <div className="card">
          <div className="card-head"><h3>Test pass rate · 14d</h3></div>
          <div className="card-pad">
            <AreaChart data={Dx.PASS_RATE_SERIES.map(d => ({d:d.d, v: d.v*100}))} color="var(--success)" height={160} yFmt={v=>v.toFixed(0)+'%'}/>
          </div>
        </div>
      </div>

      <div className="card">
        <div className="card-head">
          <h3>Tarefas</h3>
          <div className="row gap-2">
            <div className="period-tabs">
              <button className={outcomeFilter==='all'?'active':''} onClick={()=>setOutcomeFilter('all')}>todas</button>
              <button className={outcomeFilter==='pass'?'active':''} onClick={()=>setOutcomeFilter('pass')}>pass</button>
              <button className={outcomeFilter==='fail'?'active':''} onClick={()=>setOutcomeFilter('fail')}>fail</button>
            </div>
            <select className="select"><option>Todos os projetos</option>{Dx.PROJECTS.map(p=><option key={p.id}>{p.name}</option>)}</select>
          </div>
        </div>
        <table className="tbl">
          <thead><tr><th>Tarefa</th><th>Proveniência</th><th>Outcome</th><th className="num">Testes</th><th>Lint</th><th className="num">Arquivos</th></tr></thead>
          <tbody>
            {filtered.map(t => (
              <tr key={t.id} className="clickable" onClick={() => navigate(`#/executions/${t.feature}?wave=${t.wave}&tab=tasks`)}>
                <td>
                  <div style={{color:'var(--text-0)'}}>{t.titulo}</div>
                  <div className="mono muted-2" style={{fontSize:10.5}}>{t.id}</div>
                </td>
                <td>
                  <div className="prov">
                    <a>{t.project}</a><span className="sep">/</span>
                    <a>{t.feature}</a><span className="sep">/</span>
                    <a>{t.wave}</a>
                  </div>
                </td>
                <td><OutcomePill outcome={t.outcome}/></td>
                <td className="num">{t.testes_passados}/{t.testes_rodados}</td>
                <td>{t.lint_ok ? <span className="pill pass">✓ ok</span> : <span className="pill fail">✕ falhou</span>}</td>
                <td className="num">{t.arquivos_tocados}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

// ============================================================
// INCIDENTES — global events timeline
// ============================================================
function IncidentsScreen({ navigate }) {
  // Build global incidents (use EVENTS + a couple cross-execution)
  const allEvents = [
    ...Dx.EVENTS.map(e => ({ ...e, date: '2026-05-24', feature: 'knowledge-db-metrics', project: 'claude-ai-tips' })),
    { id:'e-401', date:'2026-05-23', wave:'onda-002', event_type:'lock_contention', timestamp:'23:08:12', descricao:'lock breve em WAL — panel-auth-shim', feature:'panel-auth-shim', project:'cstk-orquestra' },
    { id:'e-402', date:'2026-05-22', wave:'onda-006', event_type:'schedule_wait',  timestamp:'19:01:14', descricao:'recall-autoconsume aguardou 22s por agendamento', feature:'recall-autoconsume', project:'claude-ai-tips' },
    { id:'e-403', date:'2026-05-19', wave:'onda-002', event_type:'validation_failed', timestamp:'09:18:20', descricao:'cstk-cli-watch — validação de schema falhou', feature:'cstk-cli-watch', project:'cstk-recall' },
    { id:'e-404', date:'2026-05-15', wave:'onda-005', event_type:'wave_retry',     timestamp:'15:12:48', descricao:'agente-00c-model-routing — retry após indisponibilidade opus', feature:'agente-00c-model-routing', project:'cstk-orquestra' },
  ];

  const [typeFilter, setTypeFilter] = useStateS2('all');
  const filtered = typeFilter === 'all' ? allEvents : allEvents.filter(e => e.event_type === typeFilter);

  // Group by date
  const groups = {};
  filtered.forEach(e => { (groups[e.date] = groups[e.date] || []).push(e); });
  const sortedDates = Object.keys(groups).sort().reverse();

  const counts = {
    lock_contention: allEvents.filter(e => e.event_type === 'lock_contention').length,
    validation_failed: allEvents.filter(e => e.event_type === 'validation_failed').length,
    wave_retry: allEvents.filter(e => e.event_type === 'wave_retry').length,
    schedule_wait: allEvents.filter(e => e.event_type === 'schedule_wait').length,
  };

  return (
    <div className="col gap-4">
      <div className="grid-4">
        <KpiCard label="lock_contention · 7d" value={counts.lock_contention} icon="lock" critical={counts.lock_contention > 1}/>
        <KpiCard label="validation_failed · 7d" value={counts.validation_failed} icon="cancel" warning={counts.validation_failed > 0}/>
        <KpiCard label="wave_retry · 7d" value={counts.wave_retry} icon="retry"/>
        <KpiCard label="schedule_wait · 7d" value={counts.schedule_wait} icon="wait"/>
      </div>

      <div className="card">
        <div className="card-head">
          <h3>Incidentes ao longo do tempo</h3>
          <Legend items={[
            { color:'var(--critical)', label:'lock_contention' },
            { color:'var(--warning)', label:'validation_failed' },
            { color:'var(--info)', label:'wave_retry' },
            { color:'var(--text-2)', label:'schedule_wait' },
          ]}/>
        </div>
        <div className="card-pad">
          <StackedBars
            data={Dx.INCIDENT_SERIES}
            keys={['lock_contention','validation_failed','wave_retry','schedule_wait']}
            colors={['var(--critical)','var(--warning)','var(--info)','var(--text-2)']}
            height={180}
          />
        </div>
      </div>

      <div className="card">
        <div className="card-head">
          <h3>Timeline global</h3>
          <div className="row gap-2">
            <select className="select" value={typeFilter} onChange={e => setTypeFilter(e.target.value)}>
              <option value="all">Todos os tipos</option>
              <option value="lock_contention">lock_contention</option>
              <option value="validation_failed">validation_failed</option>
              <option value="wave_retry">wave_retry</option>
              <option value="schedule_wait">schedule_wait</option>
            </select>
          </div>
        </div>
        <div className="card-pad">
          {sortedDates.map(date => (
            <div key={date} style={{marginBottom: 24}}>
              <div className="row" style={{justifyContent:'space-between', marginBottom: 10}}>
                <div style={{fontWeight:600, fontSize: 13, color:'var(--text-0)'}}>{date}</div>
                <span className="mono muted" style={{fontSize:11}}>{groups[date].length} eventos</span>
              </div>
              <div className="events">
                {groups[date].map(e => {
                  const m = EVENT_META[e.event_type];
                  return (
                    <div key={e.id} className={`event ${e.event_type}`} style={{cursor:'pointer'}} onClick={() => navigate(`#/executions/${e.feature}?wave=${e.wave}&tab=events`)}>
                      <span className="time">{e.timestamp}</span>
                      <div>
                        <div className="row gap-2" style={{marginBottom: 2}}>
                          <Icon name={m.icon} size={12} style={{color: m.color}}/>
                          <span className="mono" style={{fontSize:11.5, color: m.color, fontWeight: 600}}>{m.label}</span>
                          <span className="prov" style={{fontSize:10.5}}>
                            <span>{e.project}</span><span className="sep">/</span>
                            <span>{e.feature}</span><span className="sep">/</span>
                            <span>{e.wave}</span>
                          </span>
                        </div>
                        <div className="body">{e.descricao}</div>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

// ============================================================
// BUSCA DE CONHECIMENTO
// ============================================================
function SearchScreen({ navigate, openDecision }) {
  const [query, setQuery] = useStateS2('lock contention');
  const [typeFilter, setTypeFilter] = useStateS2('all');

  const allResults = [
    ...Dx.SEARCH_RESULTS,
    { type:'retro', id:'r-602', project:'claude-ai-tips', feature:'knowledge-db-metrics', wave:'onda-009', when:'2026-05-24',
      title:'lock contention em WAL é raro mas caro',
      snippet:'documentar backoff exponential. lock contention em WAL é raro mas caro; vale revisitar a duração entre retries ...' },
    { type:'decisao', id:'d-107', project:'claude-ai-tips', feature:'knowledge-db-metrics', wave:'onda-009', when:'2026-05-24',
      title:'aplicar migração schema v2 com fallback para v1',
      snippet:'usuários em produção rodam v1; manter compat reduz superfície de breakage. Migração inclui mitigação de lock contention ...' },
    { type:'bloqueio', id:'b-504', project:'claude-ai-tips', feature:'cstk-knowledge-db', wave:'onda-007', when:'2026-04-12',
      title:'expor schema_version pela CLI?',
      snippet:'cstk db info retorna schema_version e contagem por tabela. Útil para diagnóstico de lock contention ...' },
  ];

  const filtered = allResults.filter(r => typeFilter === 'all' || r.type === typeFilter);

  const TYPE_META = {
    decisao:  { color:'var(--accent)',  label:'decisão',  icon:'tree' },
    bloqueio: { color:'var(--warning)', label:'bloqueio', icon:'users' },
    retro:    { color:'var(--success)', label:'retro',    icon:'doc' },
    skill:    { color:'var(--info)',    label:'skill',    icon:'package' },
  };

  const counts = {
    all: allResults.length,
    decisao: allResults.filter(r => r.type === 'decisao').length,
    bloqueio: allResults.filter(r => r.type === 'bloqueio').length,
    retro: allResults.filter(r => r.type === 'retro').length,
  };

  const highlight = (text, q) => {
    if (!q) return text;
    const re = new RegExp(`(${q.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')})`, 'gi');
    const parts = text.split(re);
    return parts.map((p, i) => re.test(p) ? <mark key={i}>{p}</mark> : <React.Fragment key={i}>{p}</React.Fragment>);
  };

  return (
    <div className="col gap-4">
      <div className="card">
        <div className="card-pad">
          <div className="row gap-2" style={{alignItems:'center'}}>
            <div className="row gap-2" style={{flex:1, padding:'8px 12px', background:'var(--bg-2)', border:'1px solid var(--border-strong)', borderRadius:'var(--r-md)'}}>
              <Icon name="search" size={16} style={{color:'var(--text-2)'}}/>
              <input
                value={query}
                onChange={e => setQuery(e.target.value)}
                placeholder="Buscar em decisões, bloqueios, retros, skills…"
                style={{flex:1, background:'transparent', border:0, outline:0, color:'var(--text-0)', fontSize: 14, fontFamily:'var(--font-mono)'}}/>
              <span className="kbd">bm25</span>
            </div>
            <button className="tb-btn primary"><Icon name="search" size={13}/>buscar</button>
          </div>
          <div className="row gap-2" style={{marginTop: 12}}>
            <button className={`tag ${typeFilter==='all'?'accent':''}`} onClick={() => setTypeFilter('all')} style={{cursor:'pointer'}}>todos · {counts.all}</button>
            <button className={`tag ${typeFilter==='decisao'?'accent':''}`} onClick={() => setTypeFilter('decisao')} style={{cursor:'pointer'}}>decisões · {counts.decisao}</button>
            <button className={`tag ${typeFilter==='bloqueio'?'accent':''}`} onClick={() => setTypeFilter('bloqueio')} style={{cursor:'pointer'}}>bloqueios · {counts.bloqueio}</button>
            <button className={`tag ${typeFilter==='retro'?'accent':''}`} onClick={() => setTypeFilter('retro')} style={{cursor:'pointer'}}>retros · {counts.retro}</button>
            <span className="muted" style={{marginLeft:'auto', fontSize:11.5}}>rankeado por bm25</span>
          </div>
        </div>
      </div>

      <div className="card">
        <div className="card-head">
          <div className="row gap-2">
            <h3>Resultados</h3>
            <span className="sub mono">{filtered.length} hits para "<span style={{color:'var(--accent)'}}>{query}</span>"</span>
          </div>
        </div>
        <div style={{padding: 4}}>
          {filtered.length === 0 ? (
            <EmptyState
              title="Nenhum resultado"
              icon="search"
              hint="Tente termos como 'lock contention', 'cache', 'snake_case', 'sonnet'."
            />
          ) : filtered.map((r, idx) => {
            const m = TYPE_META[r.type];
            return (
              <div key={r.id} style={{padding: '12px 16px', borderBottom:'1px solid var(--border-soft)', cursor:'pointer'}}
                   onMouseEnter={e => e.currentTarget.style.background='var(--bg-hover)'}
                   onMouseLeave={e => e.currentTarget.style.background=''}
                   onClick={() => r.type === 'decisao' ? openDecision({ id: r.id, escolha: r.title }) : navigate(`#/executions/${r.feature}?wave=${r.wave}`)}>
                <div className="row" style={{justifyContent:'space-between', marginBottom: 4}}>
                  <div className="row gap-2">
                    <span className="tag" style={{background:`${m.color}22`, color:m.color, borderColor:'transparent'}}>
                      <Icon name={m.icon} size={11}/>&nbsp;{m.label}
                    </span>
                    <span className="mono muted-2" style={{fontSize:11}}>#{idx+1}</span>
                  </div>
                  <span className="mono muted" style={{fontSize:11}}>{r.when}</span>
                </div>
                <div style={{fontWeight: 500, color:'var(--text-0)', fontSize: 14, marginBottom: 4}}>{highlight(r.title, query)}</div>
                <div style={{color:'var(--text-1)', fontSize: 12.5, marginBottom: 6, lineHeight: 1.5}}>{highlight(r.snippet, query)}</div>
                <div className="prov">
                  <a>{r.project}</a><span className="sep">/</span>
                  <a>{r.feature}</a><span className="sep">/</span>
                  <a>{r.wave}</a>
                  <span className="sep">·</span>
                  <span className="mono">{r.id}</span>
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}

// ============================================================
// DECISION MODAL
// ============================================================
function DecisionModal({ decision, onClose, navigate }) {
  if (!decision) return null;
  // If we have the full record use that, else look up
  const full = Dx.DECISIONS.find(d => d.id === decision.id) || decision;
  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={e => e.stopPropagation()}>
        <div className="modal-head">
          <div>
            <div className="row gap-2" style={{marginBottom: 4}}>
              <span className="tag accent"><Icon name="tree" size={10}/>&nbsp;decisão</span>
              <span className="mono" style={{fontSize:11.5, color:'var(--text-2)'}}>{full.id}</span>
            </div>
            <div style={{fontSize: 16, fontWeight: 600, color:'var(--text-0)'}}>{full.escolha}</div>
          </div>
          <button className="close-btn" onClick={onClose}><Icon name="x" size={14}/></button>
        </div>
        <div className="modal-body col" style={{gap: 14}}>
          <div className="grid-4">
            <div className="mstat"><span className="label">Score</span><div className="row gap-2" style={{marginTop:2}}><ScoreChip score={full.score}/><span className="muted" style={{fontSize:11.5}}>{['pausa/humano','pausa','contexto','evidência'][full.score]}</span></div></div>
            <div className="mstat"><span className="label">Etapa</span><span className="value mono">{full.etapa}</span></div>
            <div className="mstat"><span className="label">Agente</span><span className="value mono" style={{fontSize:12}}>{full.agente}</span></div>
            <div className="mstat"><span className="label">Onda</span><span className="value mono">{full.wave}</span></div>
          </div>
          {full.contexto && (<>
            <div>
              <div className="mono muted-2" style={{fontSize:10.5, textTransform:'uppercase', letterSpacing:'0.08em', marginBottom: 4}}>contexto</div>
              <div style={{fontSize: 13.5, color:'var(--text-1)', lineHeight: 1.55}}>{full.contexto}</div>
            </div>
            <div>
              <div className="mono muted-2" style={{fontSize:10.5, textTransform:'uppercase', letterSpacing:'0.08em', marginBottom: 4}}>justificativa</div>
              <div style={{fontSize: 13.5, color:'var(--text-1)', lineHeight: 1.55}}>{full.justificativa}</div>
            </div>
            <div>
              <div className="mono muted-2" style={{fontSize:10.5, textTransform:'uppercase', letterSpacing:'0.08em', marginBottom: 4}}>evidência</div>
              <pre style={{margin: 0, padding: '10px 14px', background:'var(--bg-2)', border:'1px solid var(--border)', borderRadius: 4, fontFamily:'var(--font-mono)', fontSize: 12, color:'var(--accent)', whiteSpace:'pre-wrap'}}>{full.evidencia}</pre>
            </div>
          </>)}
          <div className="row" style={{justifyContent:'flex-end', paddingTop: 8}}>
            <button className="tb-btn"><Icon name="tree" size={12}/>ver na árvore de decisões</button>
          </div>
        </div>
      </div>
    </div>
  );
}

// ============================================================
// SOBRE / FONTE DE DADOS
// ============================================================
function SourceScreen() {
  return (
    <div className="grid-2">
      <div className="card">
        <div className="card-head"><h3>Fonte de dados</h3></div>
        <div className="card-pad col" style={{gap: 14}}>
          <div className="mstat">
            <span className="label">Caminho do banco</span>
            <span className="value mono" style={{fontSize:12.5}}>~/.claude/cstk/knowledge.db</span>
          </div>
          <div className="grid-3">
            <div className="mstat"><span className="label">schema_version</span><span className="value">2</span></div>
            <div className="mstat"><span className="label">tipo</span><span className="value">SQLite + FTS5</span></div>
            <div className="mstat"><span className="label">acesso</span><span className="value">read-only</span></div>
          </div>
          <div className="divider"/>
          <div className="row" style={{justifyContent:'space-between'}}>
            <div className="mstat"><span className="label">frescor</span><span className="value">há 3m</span></div>
            <div className="mstat"><span className="label">estado</span><span className="value" style={{color:'var(--success)'}}>ok</span></div>
            <div className="mstat"><span className="label">tamanho</span><span className="value">8.4 MB</span></div>
          </div>
          <div className="degraded-banner" style={{margin: 0, background:'var(--info-soft)', borderColor:'rgba(96,165,250,0.2)', color: 'var(--info)'}}>
            <Icon name="database" size={14}/>
            <span>Índice é <strong>derivado e best-effort</strong> a partir das execuções dos orquestradores. Pode ser reconstruído a qualquer momento via <span className="mono" style={{background:'rgba(0,0,0,0.2)', padding:'1px 6px', borderRadius:3, fontSize:11}}>cstk --reindex</span>.</span>
          </div>
        </div>
      </div>
      <div className="card">
        <div className="card-head"><h3>Contagens por tabela</h3></div>
        <table className="tbl">
          <thead><tr><th>Tabela</th><th className="num">Linhas</th><th className="num">Tamanho</th></tr></thead>
          <tbody>
            {[
              ['executions', 7, '12 KB'],
              ['waves', 46, '38 KB'],
              ['decisions', 143, '210 KB'],
              ['tasks', 28, '64 KB'],
              ['events', 18, '32 KB'],
              ['alert_signals', 6, '8 KB'],
              ['bloqueios', 4, '24 KB'],
              ['skills', 92, '46 KB'],
              ['retros', 12, '38 KB'],
              ['fts_decisoes (FTS5)', 143, '320 KB'],
              ['fts_retros (FTS5)', 12, '42 KB'],
            ].map((r, i) => (
              <tr key={i}>
                <td className="mono" style={{fontSize:12}}>{r[0]}</td>
                <td className="num">{fmtNum(r[1])}</td>
                <td className="num mono">{r[2]}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

Object.assign(window, {
  AlertsScreen, MetricsScreen, TasksScreen, IncidentsScreen, SearchScreen, DecisionModal, SourceScreen,
});
