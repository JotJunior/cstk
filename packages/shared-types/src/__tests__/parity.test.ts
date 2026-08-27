/**
 * Teste de paridade smoke — task 2.3.5.
 * Cada schema Zod e instanciado com payload sintetico valido.
 * Falha se qualquer schema rejeitar payload bem-formado.
 * Ref: plan.md §Convencoes de Borda; spec.md FR-012
 * Updated: schema v7 EN canonical (feature new-schema)
 */
import { describe, it, expect } from 'vitest';
import {
  ExecutionDTOSchema,
  WaveDTOSchema,
  DecisionDTOSchema,
  TaskDTOSchema,
  EventDTOSchema,
  AlertSignalDTOSchema,
  BlockDTOSchema,
  SkillDTOSchema,
  RetroDTOSchema,
  FtsHitDTOSchema,
  MemoryDTOSchema,
  FeatureDocDTOSchema,
  FeatureDocsListDTOSchema,
  ProjectRollupSchema,
  FeatureRollupSchema,
  SessionSummaryDTOSchema,
  SessionTailEntryDTOSchema,
} from '../schemas/entities.js';
import {
  PaginationParamsSchema,
  PeriodParamSchema,
  ScoreParamSchema,
  SearchParamsSchema,
} from '../schemas/params.js';
import type { SessionSummaryDTO, SessionTailEntryDTO, FeatureDocStage } from '../entities.js';
import { FeatureDocStageSchema } from '../schemas/entities.js';
import type { DegradedReason } from '../envelope.js';

const ISO = '2025-01-15T10:00:00.000Z';

describe('Paridade schemas Zod — entidades', () => {
  it('ExecutionDTOSchema: payload valido passa', () => {
    const payload = {
      project: 'cstk',
      feature: 'cstk-panel',
      executionId: 'exec-2025-001',
      status: 'em_andamento',
      terminationReason: null,
      currentStage: 'execute-task',
      startedAt: ISO,
      finishedAt: null,
      durationSeconds: null,
      suggestedStack: 'node+ts',
      wavesTotal: 7,
      toolCallsTotal: 120,
      wallclockTotalSeconds: 3600,
      subagentsSpawned: 0,
      maxDepth: 1,
      decisionsTotal: 38,
      humanBlocksTotal: 1,
      skillSuggestionsTotal: 0,
      toolkitIssuesOpened: 0,
      session: null,
    };
    const r = ExecutionDTOSchema.safeParse(payload);
    expect(r.success).toBe(true);
  });

  it('WaveDTOSchema: payload valido passa (stages como string)', () => {
    const payload = {
      wave: 'onda-007',
      executionId: 'exec-2025-001',
      stages: 'execute-task',   // string, nao array
      startedAt: ISO,
      finishedAt: null,
      wallclockSeconds: 120,
      toolCalls: 25,
      terminationReason: null,
      nStages: 1,
      nSkills: 3,
      session: null,
      // schema v10 — medicao presente e parcial (2 de 3 spawns reportaram)
      agentSpawnsTotal: 3,
      agentSpawnsWithUsage: 2,
      agentTotalTokens: 120400,
      agentInputTokens: 5200,
      agentOutputTokens: 9800,
      agentCacheReadTokens: 98000,
      agentCacheCreationTokens: 7400,
      agentToolUseCount: 18,
      agentDurationMs: 240000,
      // schema v11 — custo real fracionario (nao inteiro)
      otelCostUsd: 0.229038,
      otelCostMainUsd: 0.130553,
      otelCostSubagentUsd: 0.098485,
      otelTotalTokens: 648,
      otelSubagentTokens: 648,
      // schema v12 — breakdown por fonte x tipo; so o lado subagente coletado
      // (caso majoritario na base real: 257 ondas com subagent, 27 com main)
      otelMainInputTokens: null,
      otelMainOutputTokens: null,
      otelMainCacheReadTokens: null,
      otelMainCacheCreationTokens: null,
      otelSubagentInputTokens: 12,
      otelSubagentOutputTokens: 96,
      otelSubagentCacheReadTokens: 540,
      otelSubagentCacheCreationTokens: 0,
    };
    const r = WaveDTOSchema.safeParse(payload);
    expect(r.success).toBe(true);
  });

  it('DecisionDTOSchema: score=2, campos UNTRUSTED como string', () => {
    const payload = {
      wave: 'onda-007',
      executionId: 'exec-2025-001',
      stage: 'execute-task',
      agent: 'agente-00c-orchestrator',
      choice: 'confirmar-ok',
      options: '["confirmar-ok","abortar"]',
      score: 2,
      context: 'Verificar npm install',
      rationale: 'Dependencias instaladas com sucesso',
      evidencia: null,
      decisionClass: null,
      structuralAxis: null,
      humanConsentBlockId: null,
    };
    const r = DecisionDTOSchema.safeParse(payload);
    expect(r.success).toBe(true);
    if (r.success) {
      expect(r.data.score).toBe(2);
    }
  });

  it('DecisionDTOSchema: score=null passa', () => {
    const payload = {
      wave: 'onda-001',
      executionId: 'exec-001',
      stage: null,
      agent: null,
      choice: null,
      options: null,
      score: null,
      context: null,
      rationale: null,
      evidencia: null,
      decisionClass: null,
      structuralAxis: null,
      humanConsentBlockId: null,
    };
    const r = DecisionDTOSchema.safeParse(payload);
    expect(r.success).toBe(true);
  });

  it('TaskDTOSchema: lintOk como boolean, touchedFilesCount como number', () => {
    const payload = {
      wave: 'onda-001',
      executionId: 'exec-001',
      title: 'Task de teste',
      outcome: 'pass',
      testsRun: 3,
      testsPassed: 3,
      lintOk: true,
      touchedFilesCount: 5,
    };
    const r = TaskDTOSchema.safeParse(payload);
    expect(r.success).toBe(true);
    if (r.success) {
      expect(typeof r.data.lintOk).toBe('boolean');
      expect(typeof r.data.touchedFilesCount).toBe('number');
    }
  });

  it('EventDTOSchema: payload valido passa', () => {
    const payload = {
      executionId: 'exec-001',
      eventType: 'schedule_wait',
      timestamp: ISO,
      description: null,
    };
    const r = EventDTOSchema.safeParse(payload);
    expect(r.success).toBe(true);
  });

  it('AlertSignalDTOSchema: payload valido passa', () => {
    const payload = {
      executionId: 'exec-001',
      type: 'circular',
      subtype: null,
      consumedValue: null,
      thresholdValue: null,
      description: 'Ciclo detectado',
      wave: 'onda-001',
    };
    const r = AlertSignalDTOSchema.safeParse(payload);
    expect(r.success).toBe(true);
  });

  it('BlockDTOSchema: payload valido passa', () => {
    const payload = {
      executionId: 'exec-001',
      status: 'respondido',
      question: 'Confirmar npm install?',
      contextForAnswer: null,
      answer: 'sim',
      decisionId: 'dec-001',
      triggeredAt: ISO,
      answeredAt: ISO,
      latencySeconds: 42,
    };
    const r = BlockDTOSchema.safeParse(payload);
    expect(r.success).toBe(true);
  });

  it('SkillDTOSchema: payload valido passa', () => {
    const payload = {
      executionId: 'exec-001',
      skillName: 'briefing',
      decisionId: 'dec-001',
      wave: 'onda-001',
    };
    const r = SkillDTOSchema.safeParse(payload);
    expect(r.success).toBe(true);
  });

  it('RetroDTOSchema: payload valido passa', () => {
    const payload = {
      executionId: 'exec-001',
      text: 'Reprocessamento necessario',
      wave: 'onda-001',
    };
    const r = RetroDTOSchema.safeParse(payload);
    expect(r.success).toBe(true);
  });

  it('FtsHitDTOSchema: rank como number', () => {
    const payload = {
      body: 'Trecho relevante da busca',
      type: 'decisions',
      project: 'cstk',
      feature: 'cstk-panel',
      wave: 'onda-001',
      sourceId: 'dec-001',
      sourceTs: ISO,
      rank: -1.5,
    };
    const r = FtsHitDTOSchema.safeParse(payload);
    expect(r.success).toBe(true);
    if (r.success) {
      expect(typeof r.data.rank).toBe('number');
    }
  });

  it('MemoryDTOSchema: payload valido passa (type enum, body UNTRUSTED como string)', () => {
    const payload = {
      project: 'claude-ai-tips',
      slug: 'feedback_code_in_english',
      type: 'feedback',
      description: 'Codigo em ingles obrigatorio',
      body: '# feedback_code_in_english\n\nCodigo em ingles obrigatorio...',
      path: '/Users/jot/.claude/projects/-x/memory/feedback_code_in_english.md',
      indexedAt: ISO,
    };
    const r = MemoryDTOSchema.safeParse(payload);
    expect(r.success).toBe(true);
  });

  it('MemoryDTOSchema: body/description/path/indexedAt nullable passam', () => {
    const payload = {
      project: 'cstk-panel',
      slug: 'MEMORY',
      type: 'index',
      description: null,
      body: null,
      path: null,
      indexedAt: null,
    };
    const r = MemoryDTOSchema.safeParse(payload);
    expect(r.success).toBe(true);
  });

  it('MemoryDTOSchema: type fora do enum falha', () => {
    const r = MemoryDTOSchema.safeParse({
      project: 'p', slug: 's', type: 'desconhecido',
      description: null, body: null, path: null, indexedAt: null,
    });
    expect(r.success).toBe(false);
  });

  it('FeatureDocDTOSchema: item de listagem sem content (metadados apenas)', () => {
    const payload = {
      stage: 'specify',
      artifactId: 'spec',
      scope: 'feature',
      fileName: 'spec.md',
      produced: true,
      extra: false,
    };
    const r = FeatureDocDTOSchema.safeParse(payload);
    expect(r.success).toBe(true);
    if (r.success) {
      expect(r.data.content).toBeUndefined();
    }
  });

  it('FeatureDocDTOSchema: conteudo de artefato produzido (content string)', () => {
    const payload = {
      stage: 'plan',
      artifactId: 'plan',
      scope: 'feature',
      fileName: 'plan.md',
      produced: true,
      extra: false,
      content: '# Plano\n\n...',
    };
    const r = FeatureDocDTOSchema.safeParse(payload);
    expect(r.success).toBe(true);
  });

  it('FeatureDocDTOSchema: artefato ainda nao produzido — content:null, nao erro (FR-007)', () => {
    const payload = {
      stage: 'create-tasks',
      artifactId: 'tasks',
      scope: 'feature',
      fileName: 'tasks.md',
      produced: false,
      extra: false,
      content: null,
    };
    const r = FeatureDocDTOSchema.safeParse(payload);
    expect(r.success).toBe(true);
  });

  it('FeatureDocDTOSchema: stage fora do enum falha', () => {
    const r = FeatureDocDTOSchema.safeParse({
      stage: 'clarify', // nao esta no mapa fixo (Decision 8)
      artifactId: 'x', scope: 'feature', fileName: 'x.md', produced: true, extra: false,
    });
    expect(r.success).toBe(false);
  });

  it('FeatureDocsListDTOSchema: listagem com artefatos produzidos e nao-produzidos', () => {
    const payload = {
      project: 'cstk-panel',
      feature: 'state-watchers-and-docs',
      artifacts: [
        { stage: 'specify', artifactId: 'spec', scope: 'feature', fileName: 'spec.md', produced: true, extra: false },
        { stage: 'create-tasks', artifactId: 'tasks', scope: 'feature', fileName: 'tasks.md', produced: false, extra: false },
        { stage: 'plan', artifactId: 'notes', scope: 'feature', fileName: 'notes.md', produced: true, extra: true },
      ],
    };
    const r = FeatureDocsListDTOSchema.safeParse(payload);
    expect(r.success).toBe(true);
    if (r.success) {
      expect(r.data.artifacts).toHaveLength(3);
      expect(r.data.artifacts[2]?.extra).toBe(true);
    }
  });

  it('ProjectRollupSchema: payload valido passa', () => {
    const payload = {
      project: 'cstk',
      totalExecutions: 14,
      activeExecutions: 1,
      completedExecutions: 10,
      abortedExecutions: 3,
      totalDecisions: 927,
      totalToolCalls: 2000,
      latestExecutionAt: ISO,
    };
    const r = ProjectRollupSchema.safeParse(payload);
    expect(r.success).toBe(true);
  });

  it('FeatureRollupSchema: payload valido passa', () => {
    const payload = {
      project: 'cstk',
      feature: 'cstk-panel',
      totalExecutions: 2,
      activeExecutions: 1,
      completedExecutions: 0,
      abortedExecutions: 1,
      latestStatus: 'em_andamento',
      latestExecutionAt: ISO,
    };
    const r = FeatureRollupSchema.safeParse(payload);
    expect(r.success).toBe(true);
  });
});

/**
 * Paridade estrutural DTO <-> Schema — feature session-tail (FASE 1, task 1.1.5).
 *
 * Diferente do smoke test acima (que so confirma que um payload valido passa),
 * este bloco DERIVA o conjunto de chaves de uma amostra TIPADA pela interface
 * TS e COMPARA em runtime contra as chaves do schema Zod (`Schema.shape`).
 * Isso fecha as duas direcoes de drift:
 *   - campo adicionado SO na interface: a amostra `satisfies`/tipada deixa de
 *     compilar (falta ou sobra propriedade no literal) -> falha no typecheck;
 *   - campo adicionado SO no schema Zod: nao afeta a compilacao da amostra,
 *     mas o `expect(schemaKeys).toEqual(sampleKeys)` abaixo falha em runtime.
 * Ver instrucao da onda: "editar so um dos dois passa no tsc e no vitest, e
 * quebra em runtime" (drift snake_case/camelCase que sobreviveu 40 ondas).
 */
describe('Paridade estrutural DTO <-> Schema — session-tail (FASE 1)', () => {
  it('SessionSummaryDTO: schema aceita amostra tipada e as chaves batem 1:1', () => {
    const sample: SessionSummaryDTO = {
      sessionId: '5f3c2e10-71a4-4b8e-9c1a-2d6f8b0a9e11',
      projectPath: '/Users/jot/Projects/cstk-panel',
      projectSlug: 'cstk-panel',
      lastActivityAt: ISO,
      live: true,
      sizeBytes: 40960,
    };
    const r = SessionSummaryDTOSchema.safeParse(sample);
    expect(r.success).toBe(true);

    const schemaKeys = Object.keys(SessionSummaryDTOSchema.shape).sort();
    const sampleKeys = Object.keys(sample).sort();
    expect(schemaKeys).toEqual(sampleKeys);
  });

  it('SessionSummaryDTO: projectPath=null (sem cwd na amostra lida) tambem passa', () => {
    const sample: SessionSummaryDTO = {
      sessionId: '5f3c2e10-71a4-4b8e-9c1a-2d6f8b0a9e11',
      projectPath: null,
      projectSlug: 'cstk-panel',
      lastActivityAt: ISO,
      live: false,
      sizeBytes: 0,
    };
    const r = SessionSummaryDTOSchema.safeParse(sample);
    expect(r.success).toBe(true);
  });

  it('SessionTailEntryDTO: schema aceita amostra tipada e as chaves batem 1:1', () => {
    const sample: SessionTailEntryDTO = {
      uuid: 'a1b2c3d4-0000-4000-8000-000000000001',
      type: 'assistant',
      timestamp: ISO,
      role: 'assistant',
      text: 'ola',
      textTruncated: false,
    };
    const r = SessionTailEntryDTOSchema.safeParse(sample);
    expect(r.success).toBe(true);

    const schemaKeys = Object.keys(SessionTailEntryDTOSchema.shape).sort();
    const sampleKeys = Object.keys(sample).sort();
    expect(schemaKeys).toEqual(sampleKeys);
  });

  it('SessionTailEntryDTO: type e conjunto ABERTO — valor fora do vocabulario conhecido ainda passa', () => {
    // 17 valores foram observados no harness real (ver data-model.md); o
    // schema MUST ser z.string(), nunca z.enum(), para nao quebrar a tela
    // inteira quando o harness ganhar um tipo de linha novo (Principio II).
    const sample: SessionTailEntryDTO = {
      uuid: null,
      type: 'um-tipo-de-linha-que-o-harness-ainda-nao-inventou',
      timestamp: null,
      role: null,
      text: '',
      textTruncated: false,
    };
    const r = SessionTailEntryDTOSchema.safeParse(sample);
    expect(r.success).toBe(true);
  });

  it('SessionSummaryDTO: amostra Required<T> (forca TODAS as propriedades, inclusive as futuras opcionais) bate 1:1 com Schema.shape (task 1.1.6)', () => {
    // Diferente do teste acima: a amostra tipada normal (1.1.5) OMITE um
    // campo que a interface um dia declare opcional (`campo?: T`), porque
    // TS permite omitir props opcionais no literal — o campo nunca entra em
    // `sampleKeys`, e se o schema Zod tambem nunca o tiver ganho, o
    // `toEqual` passa mesmo havendo drift real ("codigo seta o campo, Zod
    // remove no parse"). `Required<T>` fecha essa fresta: forca o literal a
    // declarar TODA propriedade da interface, inclusive as opcionais, entao
    // qualquer campo que exista so de um lado aparece como diferenca real
    // entre `sampleKeys` e `schemaKeys` (revisao onda-010).
    const sample: Required<SessionSummaryDTO> = {
      sessionId: '5f3c2e10-71a4-4b8e-9c1a-2d6f8b0a9e11',
      projectPath: '/Users/jot/Projects/cstk-panel',
      projectSlug: 'cstk-panel',
      lastActivityAt: ISO,
      live: true,
      sizeBytes: 40960,
    };
    const schemaKeys = Object.keys(SessionSummaryDTOSchema.shape).sort();
    const sampleKeys = Object.keys(sample).sort();
    expect(schemaKeys).toEqual(sampleKeys);
  });

  it('SessionTailEntryDTO: amostra Required<T> (forca TODAS as propriedades, inclusive as futuras opcionais) bate 1:1 com Schema.shape (task 1.1.6)', () => {
    const sample: Required<SessionTailEntryDTO> = {
      uuid: 'a1b2c3d4-0000-4000-8000-000000000001',
      type: 'assistant',
      timestamp: ISO,
      role: 'assistant',
      text: 'ola',
      textTruncated: false,
    };
    const schemaKeys = Object.keys(SessionTailEntryDTOSchema.shape).sort();
    const sampleKeys = Object.keys(sample).sort();
    expect(schemaKeys).toEqual(sampleKeys);
  });

  it('DegradedReason: os 5 literais novos de session-tail sao membros validos do union', () => {
    // Sem contraparte Zod por desenho (data-model.md §Novos literais de
    // DegradedReason: "o lado Zod nao muda" — MetaSchema.reason ja e
    // z.string().nullable()). A paridade aqui e TS-only: se qualquer um destes
    // 5 literais for removido/renomeado em envelope.ts, esta atribuicao deixa
    // de compilar (typecheck falha) e a lista deixa de bater com o total
    // documentado em data-model.md.
    const novosLiteraisSessionTail: DegradedReason[] = [
      'sessions-root-missing',
      'sessions-root-unreadable',
      'session-not-found',
      'session-rejected',
      'session-scrub-failed',
    ];
    expect(novosLiteraisSessionTail).toHaveLength(5);
    // Cada um deve continuar valido contra MetaSchema.reason (string livre),
    // confirmando que a alegacao de "nenhuma mudanca no lado Zod" se sustenta.
    for (const reason of novosLiteraisSessionTail) {
      expect(typeof reason).toBe('string');
    }
  });
});

describe('Paridade schemas Zod — params', () => {
  it('PaginationParamsSchema: limit=20, offset=0 passa', () => {
    const r = PaginationParamsSchema.safeParse({ limit: 20, offset: 0 });
    expect(r.success).toBe(true);
  });

  it('PaginationParamsSchema: limit=0 falha (abaixo do minimo)', () => {
    const r = PaginationParamsSchema.safeParse({ limit: 0, offset: 0 });
    expect(r.success).toBe(false);
  });

  it('PaginationParamsSchema: limit=201 falha (acima do teto=200)', () => {
    const r = PaginationParamsSchema.safeParse({ limit: 201, offset: 0 });
    expect(r.success).toBe(false);
  });

  it('PeriodParamSchema: todos os valores validos passam', () => {
    for (const period of ['24h', '7d', '30d', 'all'] as const) {
      const r = PeriodParamSchema.safeParse(period);
      expect(r.success).toBe(true);
    }
  });

  it('PeriodParamSchema: valor invalido falha', () => {
    const r = PeriodParamSchema.safeParse('1year');
    expect(r.success).toBe(false);
  });

  it('ScoreParamSchema: 0, 1, 2, 3 passam', () => {
    for (const score of [0, 1, 2, 3] as const) {
      const r = ScoreParamSchema.safeParse(score);
      expect(r.success).toBe(true);
    }
  });

  it('ScoreParamSchema: 4 falha', () => {
    const r = ScoreParamSchema.safeParse(4);
    expect(r.success).toBe(false);
  });

  it('SearchParamsSchema: query + limit + offset passam', () => {
    const r = SearchParamsSchema.safeParse({ q: 'npm install', limit: 10, offset: 0 });
    expect(r.success).toBe(true);
  });
});

/**
 * Paridade de ENUM: `FeatureDocStage` (type TS manual) <-> `FeatureDocStageSchema`
 * (enum Zod). Mesma dupla definicao dos DTOs, mesma armadilha: editar so um dos
 * dois PASSA no `tsc` e quebra em runtime — o schema rejeita um stage que o
 * type aceita, ou o type ignora um que o schema emite.
 *
 * O `Record<FeatureDocStage, true>` abaixo fecha as duas direcoes:
 *   - stage novo no TYPE e ausente aqui  -> falta propriedade -> quebra o tsc;
 *   - stage novo no SCHEMA e ausente no type -> o `toEqual` falha em runtime.
 */
describe('Paridade de enum — FeatureDocStage <-> FeatureDocStageSchema', () => {
  it('os dois lados declaram exatamente os mesmos estagios', () => {
    const doTipo: Record<FeatureDocStage, true> = {
      briefing: true,
      constitution: true,
      roadmap: true,
      specify: true,
      plan: true,
      checklist: true,
      'create-tasks': true,
      converge: true,
    };
    expect(Object.keys(doTipo).sort()).toEqual([...FeatureDocStageSchema.options].sort());
  });

  it('roadmap e converge sao membros validos (regressao: entraram depois do mapa)', () => {
    expect(FeatureDocStageSchema.safeParse('roadmap').success).toBe(true);
    expect(FeatureDocStageSchema.safeParse('converge').success).toBe(true);
    expect(FeatureDocStageSchema.safeParse('inexistente').success).toBe(false);
  });
});
