/**
 * useApiState — hook que resolve { isLoading, isEmpty, isError, isDegraded }
 * a partir do resultado de uma query TanStack Query com ApiEnvelope<T>.
 *
 * Ref: spec.md FR-006, FR-005; quickstart §Cenario 6
 */
import type { UseQueryResult } from '@tanstack/react-query';
import type { ApiEnvelope } from '@cstk-panel/shared-types';

export interface ApiState {
  isLoading: boolean;
  isEmpty: boolean;
  isError: boolean;
  isDegraded: boolean;
  errorMessage: string | null;
}

/**
 * Determina se o dado e "vazio":
 * - null ou undefined
 * - array com length === 0
 * - objeto sem chaves enumeraveis
 */
function isDataEmpty(data: unknown): boolean {
  if (data == null) return true;
  if (Array.isArray(data)) return data.length === 0;
  if (typeof data === 'object') return Object.keys(data as object).length === 0;
  return false;
}

export function useApiState<T>(
  query: UseQueryResult<ApiEnvelope<T>, Error>
): ApiState {
  const { isLoading, isFetching, isError, error, data } = query;

  return {
    isLoading: isLoading || (isFetching && !data),
    isEmpty: !isLoading && !isError && isDataEmpty(data?.data),
    isError,
    isDegraded: data?.meta.degraded ?? false,
    errorMessage: isError
      ? (error?.message ?? 'Erro desconhecido')
      : null,
  };
}
