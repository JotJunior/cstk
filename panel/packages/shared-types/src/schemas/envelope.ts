/**
 * Schemas Zod para envelope padrao.
 * Ref: contracts/envelope.md; spec.md FR-023
 */
import { z } from 'zod';

export const FreshnessSchema = z.object({
  mtime: z.string(),         // ISO 8601
  maxIngestedAt: z.string(), // ISO 8601
});

export const MetaSchema = z.object({
  degraded: z.boolean(),           // obrigatorio — nunca omitido
  reason: z.string().nullable(),   // null se nao degradado
  freshness: FreshnessSchema,      // obrigatorio — FR-014
  schemaVersion: z.string(),       // '2'
  approximate: z.boolean().optional(),
});

export function ApiEnvelopeSchema<T extends z.ZodTypeAny>(dataSchema: T) {
  return z.object({
    data: dataSchema.nullable(),
    meta: MetaSchema,
  });
}

// Schema conveniente para respostas que nao precisam validar data profundamente
export const RawApiEnvelopeSchema = ApiEnvelopeSchema(z.unknown());

export type Freshness = z.infer<typeof FreshnessSchema>;
export type Meta = z.infer<typeof MetaSchema>;
export type RawApiEnvelope = z.infer<typeof RawApiEnvelopeSchema>;
