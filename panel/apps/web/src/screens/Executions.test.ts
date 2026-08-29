/**
 * Regressão: `execution_id` não é único globalmente na knowledge.db — o mesmo id
 * aparece em projetos distintos (ex.: `personal-do-zero` e
 * `personal-do-zero-dynamic-forms`). Usar só o id como React key gerava o aviso
 * "Encountered two children with the same key" e arriscava linhas duplicadas/
 * omitidas. A chave passa a ser o par `(project, execution_id)`.
 */
import { describe, it, expect } from 'vitest';
import { executionRowKey } from './Executions.js';

describe('executionRowKey', () => {
  it('distingue execucoes com mesmo executionId em projetos diferentes', () => {
    const a = { project: 'personal-do-zero', executionId: 'feat-dynamic-forms-20260605T134535Z' };
    const b = { project: 'personal-do-zero-dynamic-forms', executionId: 'feat-dynamic-forms-20260605T134535Z' };
    expect(executionRowKey(a, 0)).not.toBe(executionRowKey(b, 1));
  });

  it('e estavel: independe do indice quando ha executionId', () => {
    const e = { project: 'p', executionId: 'feat-x-20260101T000000Z' };
    expect(executionRowKey(e, 0)).toBe(executionRowKey(e, 7));
  });

  it('cai para o indice quando executionId esta ausente (base degradada)', () => {
    expect(executionRowKey({ project: 'p', executionId: '' }, 3)).toBe('exec-3');
  });
});
