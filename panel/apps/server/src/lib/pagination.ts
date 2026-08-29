/**
 * Parser e validador de parametros de paginacao.
 * Ref: contracts/envelope.md; spec.md FR-012; SC-008 (teto de paginacao)
 * Task 3.5.2
 *
 * Defaults: limit=20, offset=0
 * Teto: limit max 100 (SC-008 — previne queries grandes)
 * Minimo: limit min 1
 */
import { z } from 'zod';

export const PAGINATION_DEFAULT_LIMIT = 20;
export const PAGINATION_MAX_LIMIT = 100;

export const PaginationQuerySchema = z.object({
  limit: z
    .string()
    .optional()
    .transform((v) => (v !== undefined ? parseInt(v, 10) : PAGINATION_DEFAULT_LIMIT))
    .pipe(z.number().int().min(1).max(PAGINATION_MAX_LIMIT)),
  offset: z
    .string()
    .optional()
    .transform((v) => (v !== undefined ? parseInt(v, 10) : 0))
    .pipe(z.number().int().min(0)),
});

export interface PaginationParams {
  limit: number;
  offset: number;
}

/**
 * Parseia query params de paginacao com defaults e teto.
 * Retorna PaginationParams valido ou lanca ZodError.
 */
export function parsePagination(query: Record<string, string | undefined>): PaginationParams {
  return PaginationQuerySchema.parse(query);
}

/**
 * Versao safe (nao lanca).
 */
export function safeParsePagination(
  query: Record<string, string | undefined>
): PaginationParams {
  const result = PaginationQuerySchema.safeParse(query);
  if (result.success) return result.data;
  return { limit: PAGINATION_DEFAULT_LIMIT, offset: 0 };
}
