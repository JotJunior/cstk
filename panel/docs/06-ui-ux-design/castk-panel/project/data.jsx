// Sample data for cstk-panel prototype
// All values grounded in the v2 schema described in the brief.

const SDD_STAGES = ['briefing','constitution','specify','clarify','plan','checklist','create-tasks','execute-task','review-task'];

const PROJECTS = [
  { id: 'claude-ai-tips', name: 'claude-ai-tips', description: 'Fonte da verdade do ecossistema cstk', repo: 'github.com/cstk/claude-ai-tips' },
  { id: 'cstk-orquestra', name: 'cstk-orquestra', description: 'Harness de orquestração + skills', repo: 'github.com/cstk/orquestra' },
  { id: 'cstk-recall', name: 'cstk-recall', description: 'CLI de busca sobre o knowledge.db', repo: 'github.com/cstk/recall' },
];

// Feature-level rollups: status + simple aggregates
const FEATURES = [
  {
    id: 'knowledge-db-metrics',
    project: 'claude-ai-tips',
    title: 'knowledge-db-metrics',
    status: 'concluida',
    etapa_corrente: 'review-task',
    ondas_total: 10,
    decisoes_total: 43,
    bloqueios_humanos_total: 0,
    sugestoes_skills_total: 4,
    issues_toolkit_abertas: 1,
    tool_calls_total: 612,
    wallclock_total_segundos: 8430,
    duracao_segundos: 9120,
    subagentes_spawned: 7,
    profundidade_max: 3,
    stack_sugerida: ['sqlite','fts5','python','pytest'],
    iniciada_em: '2026-05-24T02:27:52Z',
    terminada_em: '2026-05-24T04:59:48Z',
    motivo_termino: 'concluido',
    test_pass: 1043, test_total: 1043,
    retros: 3,
  },
  {
    id: 'recall-autoconsume',
    project: 'claude-ai-tips',
    title: 'recall-autoconsume',
    status: 'concluida',
    etapa_corrente: 'review-task',
    ondas_total: 7,
    decisoes_total: 28,
    bloqueios_humanos_total: 1,
    sugestoes_skills_total: 2,
    issues_toolkit_abertas: 0,
    tool_calls_total: 384,
    wallclock_total_segundos: 5210,
    duracao_segundos: 6240,
    subagentes_spawned: 4,
    profundidade_max: 2,
    stack_sugerida: ['python','bm25','cli'],
    iniciada_em: '2026-05-22T18:10:00Z',
    terminada_em: '2026-05-22T19:54:00Z',
    motivo_termino: 'concluido',
    test_pass: 218, test_total: 220,
    retros: 2,
  },
  {
    id: 'cstk-knowledge-db',
    project: 'claude-ai-tips',
    title: 'cstk-knowledge-db',
    status: 'concluida',
    archived: true,
    etapa_corrente: 'review-task',
    ondas_total: 12,
    decisoes_total: 71,
    bloqueios_humanos_total: 2,
    sugestoes_skills_total: 6,
    issues_toolkit_abertas: 0,
    tool_calls_total: 890,
    wallclock_total_segundos: 11820,
    duracao_segundos: 13900,
    subagentes_spawned: 11,
    profundidade_max: 4,
    stack_sugerida: ['sqlite','python','schema-design'],
    iniciada_em: '2026-04-12T10:00:00Z',
    terminada_em: '2026-04-12T13:51:40Z',
    motivo_termino: 'concluido',
    test_pass: 312, test_total: 312,
    retros: 5,
  },
  {
    id: 'agente-00c-model-routing',
    project: 'cstk-orquestra',
    title: 'agente-00c-model-routing',
    status: 'concluida',
    etapa_corrente: 'review-task',
    ondas_total: 8,
    decisoes_total: 56,
    bloqueios_humanos_total: 1,
    sugestoes_skills_total: 3,
    issues_toolkit_abertas: 2,
    tool_calls_total: 524,
    wallclock_total_segundos: 7340,
    duracao_segundos: 8600,
    subagentes_spawned: 9,
    profundidade_max: 3,
    stack_sugerida: ['python','model-selection','router'],
    iniciada_em: '2026-05-15T14:20:00Z',
    terminada_em: '2026-05-15T16:43:20Z',
    motivo_termino: 'concluido',
    test_pass: 412, test_total: 414,
    retros: 4,
  },
  {
    id: 'recall-fts-rerank',
    project: 'cstk-recall',
    title: 'recall-fts-rerank',
    status: 'em_andamento',
    etapa_corrente: 'plan',
    ondas_total: 4,
    decisoes_total: 12,
    bloqueios_humanos_total: 0,
    sugestoes_skills_total: 1,
    issues_toolkit_abertas: 0,
    tool_calls_total: 188,
    wallclock_total_segundos: 2740,
    duracao_segundos: 2740,
    subagentes_spawned: 2,
    profundidade_max: 2,
    stack_sugerida: ['python','bm25','rerank'],
    iniciada_em: '2026-05-24T01:10:00Z',
    terminada_em: null,
    motivo_termino: null,
    test_pass: 0, test_total: 0,
    retros: 0,
  },
  {
    id: 'panel-auth-shim',
    project: 'cstk-orquestra',
    title: 'panel-auth-shim',
    status: 'aguardando_humano',
    etapa_corrente: 'clarify',
    ondas_total: 2,
    decisoes_total: 6,
    bloqueios_humanos_total: 1,
    sugestoes_skills_total: 0,
    issues_toolkit_abertas: 0,
    tool_calls_total: 74,
    wallclock_total_segundos: 980,
    duracao_segundos: 980,
    subagentes_spawned: 1,
    profundidade_max: 1,
    stack_sugerida: ['oauth','jwt'],
    iniciada_em: '2026-05-23T22:00:00Z',
    terminada_em: null,
    motivo_termino: null,
    test_pass: 0, test_total: 0,
    retros: 0,
  },
  {
    id: 'cstk-cli-watch',
    project: 'cstk-recall',
    title: 'cstk-cli-watch',
    status: 'abortada',
    etapa_corrente: 'specify',
    ondas_total: 3,
    decisoes_total: 11,
    bloqueios_humanos_total: 0,
    sugestoes_skills_total: 0,
    issues_toolkit_abertas: 4,
    tool_calls_total: 142,
    wallclock_total_segundos: 1840,
    duracao_segundos: 1840,
    subagentes_spawned: 2,
    profundidade_max: 2,
    stack_sugerida: ['python','inotify'],
    iniciada_em: '2026-05-19T09:00:00Z',
    terminada_em: '2026-05-19T09:30:40Z',
    motivo_termino: 'aborto',
    test_pass: 0, test_total: 0,
    retros: 1,
  },
];

// Per-feature execution id helpers
const execId = (f) => {
  const ts = (f.iniciada_em || '').replace(/[-:T]/g,'').slice(0,15) || '20260524-022752';
  return `feat-${f.id}-${ts.slice(0,8)}-${ts.slice(8,14) || '022752'}`;
};

// Detailed waves (used for knowledge-db-metrics deep-dive)
const WAVES_DETAIL = {
  'knowledge-db-metrics': [
    { wave: 'onda-001', etapa: 'briefing',     inicio: '02:27:52', fim: '02:33:10', wallclock_seconds: 318, tool_calls: 38,  motivo_termino: 'etapa_concluida_avancando', n_etapas: 1, n_skills: 2 },
    { wave: 'onda-002', etapa: 'constitution', inicio: '02:33:10', fim: '02:36:42', wallclock_seconds: 212, tool_calls: 24,  motivo_termino: 'etapa_concluida_avancando', n_etapas: 1, n_skills: 1 },
    { wave: 'onda-003', etapa: 'specify',      inicio: '02:36:42', fim: '02:54:14', wallclock_seconds: 1052,tool_calls: 86,  motivo_termino: 'etapa_concluida_avancando', n_etapas: 1, n_skills: 3 },
    { wave: 'onda-004', etapa: 'clarify',      inicio: '02:54:14', fim: '03:04:01', wallclock_seconds: 587, tool_calls: 51,  motivo_termino: 'etapa_concluida_avancando', n_etapas: 1, n_skills: 2 },
    { wave: 'onda-005', etapa: 'plan',         inicio: '03:04:01', fim: '03:21:40', wallclock_seconds: 1059,tool_calls: 96,  motivo_termino: 'threshold_proxy_atingido', n_etapas: 1, n_skills: 4 },
    { wave: 'onda-006', etapa: 'plan',         inicio: '03:21:40', fim: '03:29:54', wallclock_seconds: 494, tool_calls: 42,  motivo_termino: 'etapa_concluida_avancando', n_etapas: 1, n_skills: 1 },
    { wave: 'onda-007', etapa: 'checklist',    inicio: '03:29:54', fim: '03:38:18', wallclock_seconds: 504, tool_calls: 47,  motivo_termino: 'etapa_concluida_avancando', n_etapas: 1, n_skills: 2 },
    { wave: 'onda-008', etapa: 'create-tasks', inicio: '03:38:18', fim: '03:51:02', wallclock_seconds: 764, tool_calls: 68,  motivo_termino: 'etapa_concluida_avancando', n_etapas: 1, n_skills: 3 },
    { wave: 'onda-009', etapa: 'execute-task', inicio: '03:51:02', fim: '04:42:36', wallclock_seconds: 3094,tool_calls: 124, motivo_termino: 'etapa_concluida_avancando', n_etapas: 6, n_skills: 5 },
    { wave: 'onda-010', etapa: 'review-task',  inicio: '04:42:36', fim: '04:59:48', wallclock_seconds: 1032,tool_calls: 36,  motivo_termino: 'concluido', n_etapas: 1, n_skills: 2 },
  ],
};

const DECISIONS = [
  { id:'d-101', wave:'onda-003', etapa:'specify', agente:'specify-agent',  escolha:'usar SQLite + FTS5 com schema v2',                       score:3, contexto:'precisamos de full-text + filtros estruturados sobre dados derivados das execuções', justificativa:'benchmark mostrou bm25 do FTS5 atende latência alvo (<80ms) com 50k docs', evidencia:'bench/recall_p95=72ms n=53412' },
  { id:'d-102', wave:'onda-004', etapa:'clarify', agente:'clarify-agent',  escolha:'tool_calls como proxy de custo (não tokens)',           score:3, contexto:'harness não expõe tokens; precisamos de proxy auditável', justificativa:'tool_calls é determinístico e já registrado em events', evidencia:'cstk-harness 3.19/docs/observability.md#proxy' },
  { id:'d-103', wave:'onda-004', etapa:'clarify', agente:'clarify-agent',  escolha:'auto-resolver ambiguidade de naming snake_case vs kebab-case', score:2, contexto:'inconsistência entre wave/onda nos campos', justificativa:'convenção do repositório usa snake_case em colunas; aplicar de forma consistente', evidencia:'grep -E "wave|onda" schema.sql' },
  { id:'d-104', wave:'onda-005', etapa:'plan',    agente:'plan-agent',     escolha:'particionar execute-task em sub-ondas por skill',       score:3, contexto:'plan estourou threshold proxy', justificativa:'reduz exposição a lock_contention e permite retry granular', evidencia:'onda-005 tool_calls=96/threshold=80' },
  { id:'d-105', wave:'onda-005', etapa:'plan',    agente:'plan-agent',     escolha:'manter modelo sonnet para create-tasks',                score:2, contexto:'opus indisponível na faixa de horário', justificativa:'sonnet entrega qualidade aceitável para geração de tasks', evidencia:'router/availability.log' },
  { id:'d-106', wave:'onda-007', etapa:'checklist',agente:'checklist-agent', escolha:'incluir gate de lint antes de execute-task',          score:3, contexto:'tasks anteriores falharam por lint depois de testes verdes', justificativa:'gate prévio reduz custo de retry em 38%', evidencia:'retros/wave-checklist-2026-04.md' },
  { id:'d-107', wave:'onda-009', etapa:'execute-task',agente:'execute-agent',escolha:'aplicar migração schema v2 com fallback para v1',     score:3, contexto:'usuários em produção rodam v1', justificativa:'manter compat reduz superfície de breakage', evidencia:'schema.sql v2 diff' },
  { id:'d-108', wave:'onda-009', etapa:'execute-task',agente:'execute-agent',escolha:'retry de wave após validation_failed em escala 0.5x', score:2, contexto:'validação falhou por jitter de schedule_wait', justificativa:'retry idempotente com backoff resolve em >90% dos casos', evidencia:'events#wave_retry' },
  { id:'d-109', wave:'onda-009', etapa:'execute-task',agente:'execute-agent',escolha:'aguardar humano em conflito de naming público',       score:0, contexto:'campo exposto na CLI muda contrato', justificativa:'mudança breaking precisa de chancela humana', evidencia:'cli/api.md#stability' },
  { id:'d-110', wave:'onda-010', etapa:'review-task',agente:'review-agent', escolha:'aprovar review-task sem rework',                       score:3, contexto:'todos os testes passam, lint ok, cobertura 87%', justificativa:'critérios de aceitação atendidos', evidencia:'pytest 1043 passed; ruff clean' },
];

const TASKS = [
  { id:'t-201', wave:'onda-009', titulo:'inicializar schema v2 com índices FTS5',           outcome:'pass', testes_rodados:142, testes_passados:142, lint_ok:1, arquivos_tocados:4 },
  { id:'t-202', wave:'onda-009', titulo:'migrar derivação de waves para batch SQL',         outcome:'pass', testes_rodados:88,  testes_passados:88,  lint_ok:1, arquivos_tocados:3 },
  { id:'t-203', wave:'onda-009', titulo:'expor agregações por execução em view materializada', outcome:'pass', testes_rodados:54, testes_passados:54, lint_ok:1, arquivos_tocados:2 },
  { id:'t-204', wave:'onda-009', titulo:'normalizar event_type em conjunto fechado',        outcome:'fail', testes_rodados:36,  testes_passados:34,  lint_ok:0, arquivos_tocados:5 },
  { id:'t-205', wave:'onda-009', titulo:'reindex CLI: --reindex e --vacuum',                outcome:'pass', testes_rodados:72,  testes_passados:72,  lint_ok:1, arquivos_tocados:3 },
  { id:'t-206', wave:'onda-009', titulo:'corrigir lock_contention em WAL com retry exponential', outcome:'pass', testes_rodados:48, testes_passados:48, lint_ok:1, arquivos_tocados:2 },
  { id:'t-207', wave:'onda-010', titulo:'documentar schema v2 em docs/schema/v2.md',        outcome:'pass', testes_rodados:0,   testes_passados:0,   lint_ok:1, arquivos_tocados:1 },
  { id:'t-208', wave:'onda-010', titulo:'snapshot fixture para regressão futura',           outcome:'pass', testes_rodados:603, testes_passados:603, lint_ok:1, arquivos_tocados:6 },
];

const EVENTS = [
  { id:'e-301', wave:'onda-003', event_type:'schedule_wait',     timestamp:'02:41:18', descricao:'aguardando janela do orquestrador (jitter=42s)' },
  { id:'e-302', wave:'onda-005', event_type:'wave_retry',         timestamp:'03:12:08', descricao:'retry após threshold_proxy_atingido (tool_calls 80→96)' },
  { id:'e-303', wave:'onda-009', event_type:'lock_contention',    timestamp:'04:02:33', descricao:'lock em knowledge.db (WAL) durante migração FTS5' },
  { id:'e-304', wave:'onda-009', event_type:'validation_failed',  timestamp:'04:18:47', descricao:'falha de validação em normalize event_type — task t-204' },
  { id:'e-305', wave:'onda-009', event_type:'wave_retry',         timestamp:'04:19:22', descricao:'retry de wave após validation_failed (backoff 0.5x)' },
  { id:'e-306', wave:'onda-009', event_type:'lock_contention',    timestamp:'04:30:11', descricao:'segundo lock breve em WAL — resolvido em 1.8s' },
  { id:'e-307', wave:'onda-010', event_type:'schedule_wait',      timestamp:'04:42:36', descricao:'janela de review-task — schedule_wait 12s' },
];

// Alerts — across executions
const ALERTS = [
  { id:'a-401', execucao_id: execId(FEATURES[0]), feature:'knowledge-db-metrics', project:'claude-ai-tips', wave:'onda-005',
    tipo:'budget_breach', subtipo:'tool_calls', valor_consumido:96, valor_threshold:80,
    descricao:'plan estourou orçamento de tool_calls em +20%', severity:'warning', timestamp:'2026-05-24T03:17:40Z' },
  { id:'a-402', execucao_id: execId(FEATURES[3]), feature:'agente-00c-model-routing', project:'cstk-orquestra', wave:'onda-006',
    tipo:'budget_breach', subtipo:'wallclock', valor_consumido:5600, valor_threshold:5400,
    descricao:'wallclock acima do limite por +3.7%', severity:'info', timestamp:'2026-05-15T16:20:00Z' },
  { id:'a-403', execucao_id: execId(FEATURES[5]), feature:'panel-auth-shim', project:'cstk-orquestra', wave:'onda-002',
    tipo:'circular', subtipo:'clarify_loop', valor_consumido:5, valor_threshold:3,
    descricao:'movimento circular detectado em clarify — mesma pergunta ressurge', severity:'critical', timestamp:'2026-05-23T23:14:08Z' },
  { id:'a-404', execucao_id: execId(FEATURES[6]), feature:'cstk-cli-watch', project:'cstk-recall', wave:'onda-002',
    tipo:'budget_breach', subtipo:'recursao', valor_consumido:6, valor_threshold:4,
    descricao:'profundidade de recursão acima do limite', severity:'critical', timestamp:'2026-05-19T09:18:20Z' },
  { id:'a-405', execucao_id: execId(FEATURES[2]), feature:'cstk-knowledge-db', project:'claude-ai-tips', wave:'onda-008',
    tipo:'budget_breach', subtipo:'ciclos', valor_consumido:14, valor_threshold:12,
    descricao:'ciclos por etapa acima do limite — review-task', severity:'warning', timestamp:'2026-04-12T13:11:00Z' },
  { id:'a-406', execucao_id: execId(FEATURES[4]), feature:'recall-fts-rerank', project:'cstk-recall', wave:'onda-003',
    tipo:'budget_breach', subtipo:'tool_calls', valor_consumido:88, valor_threshold:80,
    descricao:'plan próximo do orçamento — +10%', severity:'warning', timestamp:'2026-05-24T01:48:00Z' },
];

const BLOQUEIOS = [
  { id:'b-501', execucao_id: execId(FEATURES[3]), feature:'agente-00c-model-routing', wave:'onda-005', status:'respondido',
    pergunta:'manter sonnet como default para create-tasks ou promover opus quando disponível?',
    contexto_para_resposta:'opus tem ~22% melhor qualidade em geração de tasks mas custa ~3x em tool_calls equivalentes',
    resposta:'manter sonnet como default; promover opus apenas quando feature.priority=high',
    decisao_id:'d-105', disparado_em:'2026-05-15T15:02:00Z', respondido_em:'2026-05-15T15:18:40Z', latencia_segundos: 1000 },
  { id:'b-502', execucao_id: execId(FEATURES[5]), feature:'panel-auth-shim', wave:'onda-002', status:'aberto',
    pergunta:'OAuth provider: usar Auth0 ou rolar shim local?',
    contexto_para_resposta:'shim local mantém zero-deps mas exige manutenção de tokens; Auth0 acelera mas adiciona vendor lock-in',
    resposta:null, decisao_id:null, disparado_em:'2026-05-23T23:31:00Z', respondido_em:null, latencia_segundos: null },
  { id:'b-503', execucao_id: execId(FEATURES[1]), feature:'recall-autoconsume', wave:'onda-006', status:'respondido',
    pergunta:'invalidar cache em mudança de stop-words?',
    contexto_para_resposta:'mudança de stop-words afeta ranking bm25 retroativo',
    resposta:'sim — versionar stop-words como parte do schema; cache key inclui hash da lista',
    decisao_id:'d-203', disparado_em:'2026-05-22T19:01:00Z', respondido_em:'2026-05-22T19:09:30Z', latencia_segundos: 510 },
  { id:'b-504', execucao_id: execId(FEATURES[2]), feature:'cstk-knowledge-db', wave:'onda-007', status:'respondido',
    pergunta:'expor schema_version pela CLI?',
    contexto_para_resposta:'usuários precisam saber qual versão estão consumindo após migração',
    resposta:'sim — `cstk db info` retorna schema_version e contagem por tabela',
    decisao_id:'d-309', disparado_em:'2026-04-12T12:40:00Z', respondido_em:'2026-04-12T12:52:08Z', latencia_segundos: 728 },
];

const SKILLS_INVOCATIONS = [
  { skill_name:'specify',       count: 24 },
  { skill_name:'clarify',       count: 19 },
  { skill_name:'plan',          count: 17 },
  { skill_name:'checklist',     count: 12 },
  { skill_name:'create-tasks',  count: 28 },
  { skill_name:'execute-task',  count: 41 },
  { skill_name:'review-task',   count: 22 },
  { skill_name:'recall',        count: 8 },
  { skill_name:'retro',         count: 6 },
];

const RETROS = [
  { id:'r-601', wave:'onda-010', feature:'knowledge-db-metrics', texto:'gate de lint antes de execute-task reduziu retry em ~38%. Manter como padrão.' },
  { id:'r-602', wave:'onda-009', feature:'knowledge-db-metrics', texto:'lock_contention em WAL é raro mas caro; vale documentar backoff exponential.' },
  { id:'r-603', wave:'onda-006', feature:'recall-autoconsume',  texto:'stop-words versionadas evitaram inconsistência silenciosa entre execuções.' },
];

// Model mix — by execution (subagent-level aggregate)
const MODEL_MIX = {
  total: { haiku: 0.40, sonnet: 0.35, opus: 0.15, 'manter-atual': 0.10 },
  fallback_rate: 0.10,
  by_etapa: {
    'briefing':     { haiku: 0.80, sonnet: 0.15, opus: 0.00, 'manter-atual': 0.05 },
    'constitution': { haiku: 0.70, sonnet: 0.20, opus: 0.00, 'manter-atual': 0.10 },
    'specify':      { haiku: 0.30, sonnet: 0.50, opus: 0.10, 'manter-atual': 0.10 },
    'clarify':      { haiku: 0.40, sonnet: 0.40, opus: 0.10, 'manter-atual': 0.10 },
    'plan':         { haiku: 0.15, sonnet: 0.50, opus: 0.25, 'manter-atual': 0.10 },
    'checklist':    { haiku: 0.55, sonnet: 0.35, opus: 0.00, 'manter-atual': 0.10 },
    'create-tasks': { haiku: 0.20, sonnet: 0.45, opus: 0.25, 'manter-atual': 0.10 },
    'execute-task': { haiku: 0.30, sonnet: 0.35, opus: 0.25, 'manter-atual': 0.10 },
    'review-task':  { haiku: 0.40, sonnet: 0.30, opus: 0.20, 'manter-atual': 0.10 },
  },
};

// Cost-over-time series (tool_calls per day) for last 14 days
const COST_TIMESERIES = [
  { d: '05-11', v: 142 }, { d: '05-12', v: 218 }, { d: '05-13', v: 96 },
  { d: '05-14', v: 304 }, { d: '05-15', v: 524 }, { d: '05-16', v: 188 },
  { d: '05-17', v: 64 },  { d: '05-18', v: 102 }, { d: '05-19', v: 142 },
  { d: '05-20', v: 256 }, { d: '05-21', v: 318 }, { d: '05-22', v: 384 },
  { d: '05-23', v: 74 },  { d: '05-24', v: 800 },
];

const PASS_RATE_SERIES = [
  { d: '05-11', v: 0.98 }, { d: '05-12', v: 0.99 }, { d: '05-13', v: 1.00 },
  { d: '05-14', v: 0.97 }, { d: '05-15', v: 0.99 }, { d: '05-16', v: 1.00 },
  { d: '05-17', v: 1.00 }, { d: '05-18', v: 0.98 }, { d: '05-19', v: 0.95 },
  { d: '05-20', v: 1.00 }, { d: '05-21', v: 0.99 }, { d: '05-22', v: 0.99 },
  { d: '05-23', v: 1.00 }, { d: '05-24', v: 1.00 },
];

const INCIDENT_SERIES = [
  { d: '05-11', lock_contention: 0, validation_failed: 0, wave_retry: 1, schedule_wait: 3 },
  { d: '05-12', lock_contention: 1, validation_failed: 0, wave_retry: 0, schedule_wait: 4 },
  { d: '05-13', lock_contention: 0, validation_failed: 1, wave_retry: 1, schedule_wait: 2 },
  { d: '05-14', lock_contention: 0, validation_failed: 0, wave_retry: 2, schedule_wait: 5 },
  { d: '05-15', lock_contention: 0, validation_failed: 0, wave_retry: 0, schedule_wait: 3 },
  { d: '05-16', lock_contention: 0, validation_failed: 0, wave_retry: 0, schedule_wait: 1 },
  { d: '05-17', lock_contention: 1, validation_failed: 0, wave_retry: 1, schedule_wait: 0 },
  { d: '05-18', lock_contention: 0, validation_failed: 1, wave_retry: 0, schedule_wait: 2 },
  { d: '05-19', lock_contention: 0, validation_failed: 2, wave_retry: 1, schedule_wait: 4 },
  { d: '05-20', lock_contention: 0, validation_failed: 0, wave_retry: 0, schedule_wait: 2 },
  { d: '05-21', lock_contention: 1, validation_failed: 0, wave_retry: 1, schedule_wait: 3 },
  { d: '05-22', lock_contention: 0, validation_failed: 0, wave_retry: 1, schedule_wait: 2 },
  { d: '05-23', lock_contention: 0, validation_failed: 0, wave_retry: 0, schedule_wait: 1 },
  { d: '05-24', lock_contention: 2, validation_failed: 1, wave_retry: 2, schedule_wait: 4 },
];

// Human latency samples (seconds) — for histogram
const HUMAN_LATENCY = [510, 728, 1000, 240, 1850, 420, 660, 1200, 90, 2400, 320, 880, 540, 1620, 720];

// Activity feed (mixed)
const ACTIVITY = [
  { t:'há 4m',  type:'iniciada',    text:'execução iniciada · recall-fts-rerank · onda-004 → plan', ref:'recall-fts-rerank' },
  { t:'há 22m', type:'alerta',      text:'breach de tool_calls · plan · recall-fts-rerank (88/80)', ref:'a-406' },
  { t:'há 1h',  type:'bloqueio',    text:'bloqueio humano aberto · panel-auth-shim · OAuth provider?', ref:'b-502' },
  { t:'há 2h',  type:'alerta',      text:'movimento circular detectado · clarify · panel-auth-shim', ref:'a-403' },
  { t:'há 3h',  type:'concluida',   text:'execução concluída · knowledge-db-metrics · 1043/1043 testes', ref:'knowledge-db-metrics' },
  { t:'há 1d',  type:'concluida',   text:'execução concluída · recall-autoconsume', ref:'recall-autoconsume' },
];

// Knowledge search results sample
const SEARCH_RESULTS = [
  { type:'decisao',  id:'d-105', project:'cstk-orquestra', feature:'agente-00c-model-routing', wave:'onda-005', when:'2026-05-15',
    title:'manter modelo sonnet para create-tasks',
    snippet:'opus indisponível na faixa de horário; sonnet entrega qualidade aceitável para geração de tasks ...' },
  { type:'bloqueio', id:'b-501', project:'cstk-orquestra', feature:'agente-00c-model-routing', wave:'onda-005', when:'2026-05-15',
    title:'manter sonnet como default para create-tasks?',
    snippet:'opus tem ~22% melhor qualidade em geração de tasks mas custa ~3x em tool_calls equivalentes ...' },
  { type:'retro',    id:'r-601', project:'claude-ai-tips', feature:'knowledge-db-metrics', wave:'onda-010', when:'2026-05-24',
    title:'gate de lint antes de execute-task',
    snippet:'gate de lint antes de execute-task reduziu retry em ~38%. Manter como padrão ...' },
  { type:'decisao',  id:'d-104', project:'claude-ai-tips', feature:'knowledge-db-metrics', wave:'onda-005', when:'2026-05-24',
    title:'particionar execute-task em sub-ondas por skill',
    snippet:'plan estourou threshold proxy; particionar reduz exposição a lock_contention e permite retry granular ...' },
];

// Helper: rollup project metrics
function rollupProject(projectId) {
  const fs = FEATURES.filter(f => f.project === projectId);
  return {
    project: projectId,
    features: fs.length,
    em_andamento: fs.filter(f => f.status === 'em_andamento').length,
    aguardando_humano: fs.filter(f => f.status === 'aguardando_humano').length,
    concluidas: fs.filter(f => f.status === 'concluida').length,
    abortadas: fs.filter(f => f.status === 'abortada').length,
    tool_calls: fs.reduce((a, f) => a + f.tool_calls_total, 0),
    wallclock: fs.reduce((a, f) => a + f.wallclock_total_segundos, 0),
    decisoes: fs.reduce((a, f) => a + f.decisoes_total, 0),
    alertas_abertos: ALERTS.filter(a => a.project === projectId).length,
    last_activity: fs.map(f => f.terminada_em || f.iniciada_em).sort().reverse()[0],
  };
}

// Decision score distribution
const SCORE_DIST = { 0: 4, 1: 9, 2: 38, 3: 92 };

window.CSTKData = {
  SDD_STAGES,
  PROJECTS,
  FEATURES,
  WAVES_DETAIL,
  DECISIONS,
  TASKS,
  EVENTS,
  ALERTS,
  BLOQUEIOS,
  SKILLS_INVOCATIONS,
  RETROS,
  MODEL_MIX,
  COST_TIMESERIES,
  PASS_RATE_SERIES,
  INCIDENT_SERIES,
  HUMAN_LATENCY,
  ACTIVITY,
  SEARCH_RESULTS,
  SCORE_DIST,
  execId,
  rollupProject,
};
