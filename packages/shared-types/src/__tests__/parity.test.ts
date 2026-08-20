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
} from '../schemas/entities.js';
import {
  PaginationParamsSchema,
  PeriodParamSchema,
  ScoreParamSchema,
  SearchParamsSchema,
} from '../schemas/params.js';

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
