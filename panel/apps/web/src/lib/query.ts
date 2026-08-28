import { QueryClient } from '@tanstack/react-query';

/**
 * Intervalo de auto-refresh do painel (ms). As queries ativas re-buscam
 * a cada AUTO_REFRESH_MS, mantendo o conteudo da pagina atualizado sem
 * reload completo do navegador (sem flicker, sem reset de scroll).
 */
export const AUTO_REFRESH_MS = 10_000;

/**
 * QueryClient configurado para painel de observabilidade read-only.
 * - staleTime: 60s — dados de observabilidade mudam raramente; evita refetch excessivo
 * - gcTime: 5min — mantém cache quente entre navegações
 * - retry: 2 — backoff antes de mostrar erro
 * - refetchOnWindowFocus: false — painel read-only, sem mutacoes; refetch manual suficiente
 * - refetchInterval: 10s — auto-refresh periodico do conteudo das telas
 * - refetchIntervalInBackground: false — pausa o polling quando a aba esta oculta
 */
export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 60_000,
      gcTime: 5 * 60_000,
      retry: 2,
      refetchOnWindowFocus: false,
      refetchInterval: AUTO_REFRESH_MS,
      refetchIntervalInBackground: false,
    },
  },
});
