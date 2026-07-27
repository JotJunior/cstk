/**
 * token-source — qual das duas fontes de token o painel exibe.
 *
 * A knowledge.db grava consumo por dois caminhos independentes, e nenhum
 * substitui o outro (ver o cabecalho de `components/OtelUsage.tsx`):
 *   - `otel_*` (schema v11): contadores de API request. Cobre main +
 *     subagentes da onda inteira, mas nao abre por spawn;
 *   - `agent_*` (schema v10): hook de spawn. Abre por subagente, mas so
 *     existe onde o hook `agent-usage` foi provisionado no projeto-alvo — e
 *     nunca enxerga o consumo do proprio orquestrador.
 *
 * Para TOTAL, a UI prefere OTel e so cai para v10 quando nao ha telemetria.
 * Sem essa preferencia aparece o caso observado em producao: onda com custo
 * medido ($3.14, fonte OTel) exibindo token "—" na celula ao lado, porque o
 * hook v10 nunca rodou naquele projeto — dois numeros da mesma onda contando
 * historias diferentes.
 *
 * Principio III (Honestidade de Metrica) intacto: ausencia continua sendo
 * ausencia. `tokens: null` nunca vira 0, e a cobertura acompanha o numero.
 */
import type { AgentUsageRollup, OtelUsageRollup } from '@cstk-panel/shared-types';
import { agentUsageState, coverageLabel, isPartialSample } from '@/components/AgentUsage.js';
import { otelCoverageLabel } from '@/components/OtelUsage.js';

export interface TokenPick {
  /** Total a exibir. `null` quando nenhuma fonte mediu — nunca 0 por ausencia. */
  tokens: number | null;
  /** Fonte escolhida; `null` quando nao ha medicao em nenhuma das duas. */
  source: 'otel' | 'agent' | null;
  /** So a fonte v10 e amostral: true quando parte dos spawns nao reportou uso. */
  partial: boolean;
}

/** Escolhe a fonte mais completa disponivel, preservando ausencia. */
export function pickTokens(
  otel: OtelUsageRollup | null | undefined,
  agent: AgentUsageRollup | null | undefined,
): TokenPick {
  if (otel?.totalTokens != null) {
    return { tokens: otel.totalTokens, source: 'otel', partial: false };
  }
  if (agent?.totalTokens != null) {
    return { tokens: agent.totalTokens, source: 'agent', partial: isPartialSample(agent) };
  }
  return { tokens: null, source: null, partial: false };
}

/**
 * Cobertura da fonte efetivamente escolhida — para rodape e tooltip. Sem
 * medicao, explica qual dos dois "vazios" e: houve spawn e ninguem reportou,
 * ou nao houve coleta nenhuma.
 */
export function tokenCoverageLabel(
  pick: TokenPick,
  otel: OtelUsageRollup | null | undefined,
  agent: AgentUsageRollup | null | undefined,
): string {
  if (pick.source === 'otel') return otelCoverageLabel(otel);
  if (pick.source === 'agent') return coverageLabel(agent);
  if (agentUsageState(agent) === 'collected-no-data') {
    return 'spawns observados, nenhum reportou uso — não é consumo zero';
  }
  return 'não coletado nesta fonte';
}

/** Texto de origem para tooltip — deixa explicito o que o numero abrange. */
export function tokenSourceTip(pick: TokenPick): string {
  if (pick.source === 'otel') {
    return 'telemetria OTel da onda: loop principal + subagentes (schema v11)';
  }
  if (pick.source === 'agent') {
    return 'medição por spawn do hook agent-usage — não inclui o orquestrador (schema v10)';
  }
  return 'consumo não coletado em nenhuma das duas fontes';
}
