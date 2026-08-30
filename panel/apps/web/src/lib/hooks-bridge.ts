/**
 * Hooks TanStack Query da Ponte de intervencao humana (feature human-bridge).
 * Ref: docs/specs/human-bridge/contracts/panel-bridge-api.md §6/§7/§8/§9;
 *      docs/specs/human-bridge/spec.md FR-001/FR-013/FR-014/FR-015; tasks 4.2.
 *
 * Arquivo IRMAO de `hooks.ts` (nao dentro dele): a Ponte e a PRIMEIRA
 * superficie de mutacao do painel (constitution do painel, Principio I,
 * "A excecao da Ponte") — mante-la em modulo proprio deixa explicito que
 * `useAnswerIntervention()` usa `mutateApi()` (sem ETag/cache), nunca
 * `fetchApi()` (contrato §8).
 */
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { fetchApi, mutateApi } from './api.js';
import { AUTO_REFRESH_MS } from './query.js';
import {
  InterventionsQueueResultDTOSchema,
  PollInterventionResponseDTOSchema,
  type InterventionExecutionKind,
  type InterventionKind,
  type InterventionState,
} from '@cstk-panel/shared-types';

// ---------------------------------------------------------------------------
// GET /bridge/interventions — fila (US1, FR-013/FR-014).
// ---------------------------------------------------------------------------

/**
 * Path de `GET /bridge/interventions` — extraido como funcao pura (mesmo
 * padrao de `sessionsListPath`/`sessionTailPath` em `hooks.ts`) para teste
 * direto do encoding de `project`.
 *
 * `state` nao e exposto aqui: a fila da tela e SEMPRE a fila em aberto
 * (`open`, default do servidor — contrato §6); o historico resolvido nao
 * faz parte do escopo da tarefa 4.3.
 */
export function interventionsQueuePath(project?: string): string {
  if (!project) return '/bridge/interventions';
  return `/bridge/interventions?project=${encodeURIComponent(project)}`;
}

/**
 * Opcoes de `useQuery` para a fila da Ponte — extraidas (task 6.1.3/4.2.4
 * do mesmo padrao) para teste direto de `refetchInterval`/`queryKey`/
 * `queryFn` sem precisar renderizar (sem jsdom neste repo).
 *
 * `refetchInterval` reusa `AUTO_REFRESH_MS` (contrato §9) — SEM SSE/WebSocket
 * (decisao do operador, FR-019); `refetchIntervalInBackground: false` pausa
 * o polling com a aba oculta, mesmo padrao de `queryClient`/`sessionsQueryOptions`.
 */
export function interventionsQueryOptions(project?: string) {
  return {
    queryKey: ['bridge-interventions', project ?? null] as const,
    queryFn: () => fetchApi(interventionsQueuePath(project), InterventionsQueueResultDTOSchema),
    refetchInterval: AUTO_REFRESH_MS,
    refetchIntervalInBackground: false,
  };
}

/** Fila cross-projeto de intervencoes pendentes (US1/SC-001). */
export function useInterventions(project?: string) {
  return useQuery(interventionsQueryOptions(project));
}

// ---------------------------------------------------------------------------
// POST /bridge/interventions/:questionId/answer — responder (US2, FR-015).
// ---------------------------------------------------------------------------

/** Path de `POST /bridge/interventions/:questionId/answer` — encoding do id. */
export function answerInterventionPath(questionId: string): string {
  return `/bridge/interventions/${encodeURIComponent(questionId)}/answer`;
}

export interface AnswerInterventionInput {
  questionId: string;
  resolution: 'answered' | 'declined';
  /** obrigatorio sse `resolution==='answered'` (regra de SERVIDOR, FR-005). */
  value: string | null;
  /** so permitido quando `kind==='text'`. */
  text: string | null;
}

/**
 * `mutationFn` extraida como funcao pura (mesmo motivo de
 * `interventionsQueryOptions`) — task 4.2.4 testa esta funcao diretamente
 * com `fetch` mockado, sem precisar de `renderHook`.
 *
 * Contrato §8: usa `mutateApi()` (NUNCA `fetchApi()`) e invalida
 * explicitamente o path da fila padrao (`/bridge/interventions`, sem
 * filtro de projeto) apos sucesso — a UI sempre le a fila sem filtro
 * (task 4.2.1); um filtro por projeto futuro precisaria invalidar tambem
 * o path filtrado, fora do escopo desta tarefa.
 */
export function answerInterventionMutationFn(input: AnswerInterventionInput) {
  return mutateApi(
    answerInterventionPath(input.questionId),
    'POST',
    { resolution: input.resolution, value: input.value, text: input.text },
    PollInterventionResponseDTOSchema,
    [interventionsQueuePath()]
  );
}

/**
 * Mutation hook de resposta a uma intervencao. Sobre a invalidacao de
 * ETag (contrato §8) empilha `queryClient.invalidateQueries()` — refresh
 * imediato na UI, sem esperar o proximo tick de `AUTO_REFRESH_MS`.
 *
 * NUNCA persiste nada no corpus a partir do painel (Principio I do painel,
 * "a Ponte MUST NOT gravar decisao/bloqueio/onda no corpus") — o registro
 * canonico continua sendo `.operator_answers[]`, escrito pelo servidor MCP.
 */
export function useAnswerIntervention() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: answerInterventionMutationFn,
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ['bridge-interventions'] });
    },
  });
}

export type { InterventionExecutionKind, InterventionKind, InterventionState };
