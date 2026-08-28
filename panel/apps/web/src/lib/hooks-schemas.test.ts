import { describe, it, expect } from 'vitest';
import {
  DecisionsPageSchema,
  TasksResultSchema,
  AlertsPageSchema,
  SearchPageSchema,
  ExecutionsPageSchema,
} from './hooks.js';

// Guarda de contrato de borda: endpoints paginados retornam
// `data: { <chave>: [...], pagination }` (objeto), NAO array puro.
// Regressao real: o frontend usava z.array(...) e quebrava com Zod
// "expected array, received object". Estes testes travam o shape.

const pag = { total: 0, limit: 20, offset: 0, hasMore: false };

describe('schemas paginados aceitam objeto embrulhado e rejeitam array puro', () => {
  it('DecisionsPageSchema: {decisions, pagination}', () => {
    expect(DecisionsPageSchema.safeParse({ decisions: [], pagination: pag }).success).toBe(true);
    // Regressao: array puro deve FALHAR (era o bug da aba Decisoes)
    expect(DecisionsPageSchema.safeParse([]).success).toBe(false);
  });

  it('TasksResultSchema: {passRate, tasks}', () => {
    expect(TasksResultSchema.safeParse({ passRate: null, tasks: [] }).success).toBe(true);
    expect(TasksResultSchema.safeParse({ passRate: 1, tasks: [] }).success).toBe(true);
    expect(TasksResultSchema.safeParse([]).success).toBe(false);
  });

  it('AlertsPageSchema: {alerts, pagination}', () => {
    expect(AlertsPageSchema.safeParse({ alerts: [], pagination: pag }).success).toBe(true);
    expect(AlertsPageSchema.safeParse([]).success).toBe(false);
  });

  it('SearchPageSchema: {results, pagination}', () => {
    expect(SearchPageSchema.safeParse({ results: [], pagination: pag }).success).toBe(true);
    expect(SearchPageSchema.safeParse([]).success).toBe(false);
  });

  it('ExecutionsPageSchema: {executions, pagination}', () => {
    expect(ExecutionsPageSchema.safeParse({ executions: [], pagination: pag }).success).toBe(true);
    expect(ExecutionsPageSchema.safeParse([]).success).toBe(false);
  });

  it('pagination exige total/limit/offset/hasMore', () => {
    expect(DecisionsPageSchema.safeParse({ decisions: [], pagination: { total: 0 } }).success).toBe(false);
  });
});
