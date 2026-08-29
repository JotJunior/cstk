/**
 * Normalizacao do status de execucao no limite de leitura (fonte unica).
 *
 * A knowledge.db e populada a partir do state dos orquestradores (agente-00c/
 * feature-00c), cujo status e parcialmente escrito por um LLM — logo pode
 * conter variantes fora do contrato (ex.: 'concluido' no lugar de 'concluida').
 * Como o painel e read-only (Principio I) e nunca pode quebrar (Invariante II),
 * normalizamos AQUI antes de emitir: aliases conhecidos viram o valor canonico
 * (preservando a informacao) e qualquer valor desconhecido degrada para null —
 * nunca um enum invalido que estoura a validacao Zod no cliente e derruba a
 * lista inteira.
 *
 * Usado por mappers/execution.ts (campo `status`) e pelas rotas de rollup
 * (features/projects/overview, campo `latestStatus`).
 */
export type ExecutionStatus =
  | 'em_andamento'
  | 'aguardando_humano'
  | 'concluida'
  | 'abortada';

const VALID_STATUSES: ReadonlySet<string> = new Set<string>([
  'em_andamento', 'aguardando_humano', 'concluida', 'abortada',
]);

/**
 * Variantes conhecidas (typo de genero do orquestrador) → valor canonico.
 * Preserva a informacao em vez de degradar para null. Estende aqui quando uma
 * nova variante recorrente for observada na base.
 */
const STATUS_ALIASES: Readonly<Record<string, ExecutionStatus>> = {
  concluido: 'concluida',
  abortado: 'abortada',
};

/**
 * Coage um status cru (coluna `status`/`latest_status` da knowledge.db) ao
 * enum canonico do contrato. Aliases conhecidos sao remapeados; valores
 * vazios/nulos/desconhecidos viram null.
 */
export function normalizeStatus(raw: string | null | undefined): ExecutionStatus | null {
  if (!raw) return null;
  const canonical = STATUS_ALIASES[raw] ?? raw;
  return VALID_STATUSES.has(canonical) ? (canonical as ExecutionStatus) : null;
}
