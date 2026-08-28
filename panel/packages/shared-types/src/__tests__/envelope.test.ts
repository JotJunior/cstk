/**
 * Testes unitarios — ApiEnvelope e MetaSchema.
 * Task 2.1.5: parse(payload_valido) passa; parse(sem_degraded) falha com ZodError.
 * Ref: spec.md FR-023; contracts/envelope.md
 */
import { describe, it, expect } from 'vitest';
import { ApiEnvelopeSchema, MetaSchema } from '../schemas/envelope.js';
import { z } from 'zod';

const validFreshness = {
  mtime: '2025-01-15T10:00:00.000Z',
  maxIngestedAt: '2025-01-15T09:59:00.000Z',
};

const validMeta = {
  degraded: false,
  reason: null,
  freshness: validFreshness,
  schemaVersion: '2',
};

describe('MetaSchema', () => {
  it('parse(meta_valido) passa', () => {
    const result = MetaSchema.safeParse(validMeta);
    expect(result.success).toBe(true);
  });

  it('parse(meta sem degraded) falha com ZodError', () => {
    const { degraded: _d, ...withoutDegraded } = validMeta;
    const result = MetaSchema.safeParse(withoutDegraded);
    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error).toBeInstanceOf(z.ZodError);
    }
  });

  it('parse(meta sem freshness) falha com ZodError', () => {
    const { freshness: _f, ...withoutFreshness } = validMeta;
    const result = MetaSchema.safeParse(withoutFreshness);
    expect(result.success).toBe(false);
  });

  it('meta com degraded=true e reason=string passa', () => {
    const degradedMeta = {
      ...validMeta,
      degraded: true,
      reason: 'db-missing',
    };
    const result = MetaSchema.safeParse(degradedMeta);
    expect(result.success).toBe(true);
  });

  it('meta com approximate=true passa', () => {
    const approxMeta = { ...validMeta, approximate: true };
    const result = MetaSchema.safeParse(approxMeta);
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.approximate).toBe(true);
    }
  });
});

describe('ApiEnvelopeSchema', () => {
  it('parse(envelope com data string) passa', () => {
    const envelope = {
      data: 'hello',
      meta: validMeta,
    };
    const result = ApiEnvelopeSchema(z.string()).safeParse(envelope);
    expect(result.success).toBe(true);
  });

  it('parse(envelope com data null + degraded=true) passa', () => {
    const envelope = {
      data: null,
      meta: { ...validMeta, degraded: true, reason: 'db-missing' },
    };
    // data: null e valido porque ApiEnvelopeSchema aplica .nullable() no dataSchema
    const result = ApiEnvelopeSchema(z.string()).safeParse(envelope);
    expect(result.success).toBe(true);
  });

  it('parse(envelope sem meta) falha', () => {
    const envelope = { data: 'hello' };
    const result = ApiEnvelopeSchema(z.string()).safeParse(envelope);
    expect(result.success).toBe(false);
  });

  it('parse(envelope sem degraded em meta) falha com ZodError', () => {
    const { degraded: _d, ...metaWithoutDegraded } = validMeta;
    const envelope = { data: null, meta: metaWithoutDegraded };
    // z.string() + .nullable() aplicado internamente — data: null e ok;
    // o problema e o meta sem degraded
    const result = ApiEnvelopeSchema(z.string()).safeParse(envelope);
    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error).toBeInstanceOf(z.ZodError);
    }
  });
});
