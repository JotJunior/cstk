/**
 * ExecutionDetail — detalhe de execucao com WavesTimeline + tabs (US2).
 * Tabs: Ondas | Decisoes | Tarefas | Eventos | Alertas | Bloqueios | Skills
 *
 * Campos UNTRUSTED (contexto, justificativa, evidencia, pergunta, etc.)
 * renderizados via TextRaw — nunca dangerouslySetInnerHTML (FR-011, Principio V).
 *
 * Ref: spec.md §User Story 2; tasks.md §6.2
 */
import { Fragment, useState } from 'react';
import { useParams, useSearchParams, useNavigate } from 'react-router-dom';
import {
  useExecution, useWaves, useDecisions, useTasks,
  useEvents, useAlertsByExecution, useBloqueios, useSkills, useScoreDistribution,
  useSuggestions,
} from '@/lib/hooks.js';
import { useApiState } from '@/hooks/useApiState.js';
import { stackDisplayItems } from '@/lib/stack-display.js';
import { decisionOptions, chosenOptionIndex } from '@/lib/decision-options.js';
import { LoadingState, EmptyState, ErrorState, DegradedBanner } from '@/states/index.js';
import {
  StatusBadge, ScoreChip, OutcomePill, TextRaw, Icon, BarH, MiniStat, PipelineProgress,
  AgentUsagePanel, CoverageBadge, agentUsageState, sumAgentUsage, waveAgentUsage,
  OtelUsagePanel, OtelCoverageBadge, otelUsageState, sumOtelUsage, waveOtelUsage, fmtUsd,
} from '@/components/index.js';
import { fmtTokens } from '@/lib/format.js';
import { pickTokens, tokenSourceTip, type TokenPick } from '@/lib/token-source.js';
import type { ExecutionDTO, WaveDTO, DecisionDTO, TaskDTO, EventDTO, AlertSignalDTO, BlockDTO, SkillDTO, SuggestionDTO } from '@cstk-panel/shared-types';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function fmtNum(n: number | null | undefined): string {
  if (n == null) return '—';
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}k`;
  return String(n);
}

function fmtDur(secs: number | null | undefined): string {
  if (secs == null) return '—';
  if (secs < 60) return `${secs}s`;
  if (secs < 3600) return `${Math.floor(secs / 60)}m`;
  if (secs < 86400) return `${Math.floor(secs / 3600)}h ${Math.floor((secs % 3600) / 60)}m`;
  return `${Math.floor(secs / 86400)}d`;
}

function fmtTimestamp(iso: string | null | undefined): string {
  if (!iso) return '—';
  const d = new Date(iso);
  return d.toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });
}

// PipelineProgress: usa o componente compartilhado (single source of truth para a
// logica de etapas done/current/aborted). Ver components/PipelineProgress.tsx.

/**
 * Celula de token da onda. Le a fonte mais completa disponivel — OTel (v11,
 * main + subagentes) e, sem telemetria, o hook de spawn (v10). Ver
 * `lib/token-source.ts` para o porque da preferencia.
 * Os estados nao colapsam em "0":
 *   medido            -> "7.2M" (+ "*" quando a amostra v10 e parcial)
 *   coletado sem dado -> "s/ dado" (houve spawn, nenhum reportou uso)
 *   nao coletado      -> "—" (nenhuma das duas fontes coletou)
 */
export function waveTokenPick(w: WaveDTO): TokenPick {
  return pickTokens(waveOtelUsage(w), waveAgentUsage(w));
}

export function waveUsageLabel(w: WaveDTO): string {
  const pick = waveTokenPick(w);
  if (pick.tokens != null) return `${fmtTokens(pick.tokens)}${pick.partial ? ' *' : ''}`;
  return w.agentSpawnsTotal != null ? 's/ dado' : '—';
}

export function waveUsageTip(w: WaveDTO): string {
  const pick = waveTokenPick(w);
  if (pick.source === 'otel') {
    const sub = w.otelSubagentTokens;
    return `${tokenSourceTip(pick)}${sub != null ? ` · ${fmtTokens(sub)} em subagentes` : ''}`;
  }
  if (pick.source === 'agent') {
    return `${w.agentSpawnsWithUsage ?? 0} de ${w.agentSpawnsTotal ?? 0} spawns reportaram uso`;
  }
  if (w.agentSpawnsTotal != null) {
    return `${w.agentSpawnsTotal} spawn(s) observado(s), nenhum reportou uso — nao e consumo zero`;
  }
  return 'consumo da onda nao coletado (nem telemetria OTel, nem hook de spawn)';
}

/**
 * Celula de custo REAL da onda (schema v11, telemetria OTel). Dois estados,
 * sem terceiro: ou a onda foi instrumentada e ha custo, ou nao ha coleta e a
 * celula fica "—". Zero seria afirmacao falsa sobre uma onda nao medida.
 */
export function waveCostLabel(w: WaveDTO): string {
  return w.otelCostUsd == null ? '—' : fmtUsd(w.otelCostUsd);
}

export function waveCostTip(w: WaveDTO): string {
  if (w.otelCostUsd == null) {
    return 'custo real nao coletado nesta onda (telemetria OTel desligada, execucao anterior ao cstk 5.28.0 ou base v<11)';
  }
  return `custo medido: ${fmtUsd(w.otelCostMainUsd)} no loop principal + ${fmtUsd(w.otelCostSubagentUsd)} em subagentes`;
}

// ---------------------------------------------------------------------------
// WavesTimeline
// ---------------------------------------------------------------------------
function WavesTimeline({
  waves, onSelectWave, selectedWave,
}: {
  waves: WaveDTO[];
  execId: string;
  onSelectWave: (wave: string | null) => void;
  selectedWave: string | null;
}) {
  const maxTC = waves.reduce((m, w) => Math.max(m, w.toolCalls ?? 0), 0) || 1;
  const totalTC = waves.reduce((sum, w) => sum + (w.toolCalls ?? 0), 0);
  const totalWS = waves.reduce((sum, w) => sum + (w.wallclockSeconds ?? 0), 0);
  // Consumo medido dos subagentes (schema v10). A soma preserva null: se
  // nenhuma onda tem medicao, o rodape mostra "—", nao 0 (Principio III).
  const usageTotal = sumAgentUsage(waves);
  const hasUsage = agentUsageState(usageTotal) === 'measured';
  // Custo REAL medido por telemetria (schema v11). Fonte independente da
  // acima: soma tambem o que o proprio orquestrador gastou na onda.
  const otelTotal = sumOtelUsage(waves);
  const hasOtel = otelUsageState(otelTotal) === 'measured';
  // Token do rodape sai da MESMA fonte que venceu nas celulas — do contrario o
  // rodape some com o total enquanto as linhas exibem numero.
  const tokenTotal = pickTokens(otelTotal, usageTotal);
  const selectedWaveRow = selectedWave ? waves.find(w => w.wave === selectedWave) : undefined;

  const MOTIVO_COLOR: Record<string, string> = {
    etapa_concluida_avancando: 'var(--success)',
    threshold_proxy_atingido:  'var(--warning)',
    bloqueio_humano:           'var(--info)',
    aborto:                    'var(--critical)',
    concluido:                 'var(--success)',
  };

  return (
    <div className="card">
      <div className="card-head">
        <div className="row gap-2">
          <h3>Linha do tempo de ondas</h3>
          <span style={{ fontFamily: 'var(--font-mono)', fontSize: 10, color: 'var(--text-2)', padding: '1px 7px', background: 'var(--bg-3)', borderRadius: 10 }}>
            {waves.length}
          </span>
        </div>
        <div className="row gap-2">
          {selectedWave && (
            <button
              onClick={() => onSelectWave(null)}
              style={{ background: 'var(--bg-3)', border: '1px solid var(--border)', borderRadius: 'var(--r-xs)', padding: '3px 8px', fontSize: 11, color: 'var(--text-1)', cursor: 'pointer' }}
            >
              <Icon name="x" size={10} /> limpar
            </button>
          )}
          <div className="row gap-2" style={{ fontSize: 10.5 }}>
            {[
              { color: 'var(--success)',  label: 'avancou' },
              { color: 'var(--warning)',  label: 'threshold' },
              { color: 'var(--info)',     label: 'bloqueio' },
              { color: 'var(--critical)', label: 'aborto' },
            ].map(({ color, label }) => (
              <div key={label} className="row gap-2" style={{ color: 'var(--text-2)' }}>
                <div style={{ width: 8, height: 8, borderRadius: 2, background: color }} />
                {label}
              </div>
            ))}
          </div>
        </div>
      </div>
      <div style={{ overflowX: 'auto' }}>
        {/* Header row */}
        <div style={{
          display: 'grid', gridTemplateColumns: '110px 120px 1fr 50px 90px 80px 80px',
          gap: 8, padding: '8px 14px', borderBottom: '1px solid var(--border)',
          fontSize: 10, color: 'var(--text-3)', textTransform: 'uppercase', letterSpacing: '0.08em', fontWeight: 600,
        }}>
          <span>Onda</span>
          <span>Etapa</span>
          <span>Tool calls · barra</span>
          <span style={{ textAlign: 'right' }}>Skills</span>
          <span style={{ textAlign: 'right' }} title="tokens medidos da onda — telemetria OTel (v11, main + subagentes) e, sem telemetria, hook de spawn (v10)">Tokens</span>
          <span style={{ textAlign: 'right' }}>Wallclock</span>
          <span style={{ textAlign: 'right' }} title="custo real da onda em USD, medido pela telemetria OTel (schema v11)">Custo</span>
        </div>
        {waves.map(w => {
          const pct = Math.max(8, ((w.toolCalls ?? 0) / maxTC) * 100);
          const isSelected = selectedWave === w.wave;
          const barColor = MOTIVO_COLOR[w.terminationReason ?? ''] ?? 'var(--accent)';
          return (
            <div
              key={w.wave}
              onClick={() => onSelectWave(isSelected ? null : w.wave)}
              style={{
                display: 'grid', gridTemplateColumns: '110px 120px 1fr 50px 90px 80px 80px',
                gap: 8, padding: '8px 14px', cursor: 'pointer', alignItems: 'center',
                background: isSelected ? 'var(--bg-2)' : 'transparent',
                borderLeft: isSelected ? `2px solid ${barColor}` : '2px solid transparent',
              }}
            >
              <span style={{ fontFamily: 'var(--font-mono)', fontSize: 11.5, color: isSelected ? 'var(--text-0)' : 'var(--text-1)' }}>
                {w.wave}
              </span>
              {/* stages vem do orquestrador e, em casos raros de erro, traz um
                  paragrafo inteiro em vez do nome da etapa — trunca em 1 linha
                  (valor completo no title) para nao quebrar o layout da onda. */}
              <span
                title={w.stages ?? undefined}
                style={{
                  fontFamily: 'var(--font-mono)', fontSize: 11, color: 'var(--inprogress)',
                  minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
                }}
              >
                {w.stages ?? '—'}
              </span>
              <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                <div style={{ flex: 1, height: 16, background: 'var(--bg-3)', borderRadius: 3, overflow: 'hidden' }}>
                  <div style={{
                    width: `${pct}%`, height: '100%', background: barColor,
                    borderRadius: 3, display: 'flex', alignItems: 'center', paddingLeft: 6,
                  }}>
                    <span style={{ fontSize: 10, color: 'rgba(255,255,255,0.75)', whiteSpace: 'nowrap', fontFamily: 'var(--font-mono)' }}>
                      {w.toolCalls ?? 0}
                    </span>
                  </div>
                </div>
                <span style={{ fontSize: 10, color: 'var(--text-3)', fontFamily: 'var(--font-mono)', flexShrink: 0 }}>
                  {w.terminationReason?.slice(0, 12) ?? '—'}
                </span>
              </div>
              <span style={{ textAlign: 'right', fontFamily: 'var(--font-mono)', fontSize: 11.5, color: 'var(--text-1)' }}>
                {w.nSkills ?? '—'}
              </span>
              {/* Tokens medidos da onda. Tres estados distintos, nunca 0:
                  medido (numero, com "*" se amostra parcial), coletado sem
                  dado ("s/ dado") e nao coletado ("—"). */}
              <span
                title={waveUsageTip(w)}
                style={{
                  textAlign: 'right', fontFamily: 'var(--font-mono)', fontSize: 11.5,
                  color: waveTokenPick(w).tokens != null ? 'var(--text-1)' : 'var(--text-3)',
                }}
              >
                {waveUsageLabel(w)}
              </span>
              <span style={{ textAlign: 'right', fontFamily: 'var(--font-mono)', fontSize: 11.5, color: 'var(--text-1)' }}>
                {fmtDur(w.wallclockSeconds)}
              </span>
              {/* Custo real da onda. "—" quando nao houve coleta — nunca 0. */}
              <span
                title={waveCostTip(w)}
                style={{
                  textAlign: 'right', fontFamily: 'var(--font-mono)', fontSize: 11.5,
                  color: w.otelCostUsd != null ? 'var(--text-1)' : 'var(--text-3)',
                }}
              >
                {waveCostLabel(w)}
              </span>
            </div>
          );
        })}
        <div style={{
          display: 'flex', justifyContent: 'space-between',
          padding: '8px 14px', borderTop: '1px solid var(--border)',
          fontSize: 11.5, color: 'var(--text-2)',
        }}>
          <span>{waves.length} ondas</span>
          <span className="row gap-2" style={{ fontFamily: 'var(--font-mono)' }}>
            {fmtNum(totalTC)} tool_calls · {fmtDur(totalWS)} wallclock
            {tokenTotal.tokens != null && (
              <span title={tokenSourceTip(tokenTotal)}>
                {' '}· {fmtTokens(tokenTotal.tokens)} tokens{tokenTotal.partial ? ' *' : ''}
              </span>
            )}
            {hasOtel && <> · {fmtUsd(otelTotal.costUsd)} medidos</>}
            {hasUsage && <CoverageBadge usage={usageTotal} />}
            {hasOtel && <OtelCoverageBadge usage={otelTotal} />}
          </span>
        </div>
      </div>
      {/* Detalhe do consumo da onda selecionada — breakdown input/output/cache.
          Aparece so com onda selecionada para nao competir com a timeline. */}
      {selectedWaveRow && (
        <div style={{ borderTop: '1px solid var(--border)', padding: '12px 14px' }}>
          <div className="row gap-2" style={{ marginBottom: 8 }}>
            <span style={{ fontSize: 11, color: 'var(--text-2)', textTransform: 'uppercase', letterSpacing: '0.07em', fontWeight: 600 }}>
              Consumo de subagentes · {selectedWaveRow.wave}
            </span>
          </div>
          <AgentUsagePanel usage={waveAgentUsage(selectedWaveRow)} columns={4} />
          <div className="row gap-2" style={{ margin: '14px 0 8px' }}>
            <span style={{ fontSize: 11, color: 'var(--text-2)', textTransform: 'uppercase', letterSpacing: '0.07em', fontWeight: 600 }}>
              Custo real · {selectedWaveRow.wave}
            </span>
          </div>
          {/* Fonte distinta do bloco acima: cobre main + subagente, entao os
              dois nao se somam nem se conferem linha a linha. */}
          <OtelUsagePanel usage={waveOtelUsage(selectedWaveRow)} columns={4} />
        </div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Tab bar
// ---------------------------------------------------------------------------
function TabBar({
  tabs, activeTab, onChange,
}: {
  tabs: { value: string; label: string; count: number }[];
  activeTab: string;
  onChange: (v: string) => void;
}) {
  return (
    <div style={{
      display: 'flex', borderBottom: '1px solid var(--border)',
      padding: '0 4px', background: 'var(--bg-1)',
    }}>
      {tabs.map(t => (
        <button
          key={t.value}
          onClick={() => onChange(t.value)}
          style={{
            background: 'transparent',
            border: 'none',
            borderBottom: activeTab === t.value ? '2px solid var(--accent)' : '2px solid transparent',
            color: activeTab === t.value ? 'var(--text-0)' : 'var(--text-2)',
            padding: '10px 14px',
            fontSize: 12.5,
            fontWeight: activeTab === t.value ? 600 : 400,
            cursor: 'pointer',
            display: 'flex', alignItems: 'center', gap: 6,
            marginBottom: -1,
          }}
        >
          {t.label}
          {t.count > 0 && (
            <span style={{
              background: 'var(--bg-3)', color: 'var(--text-2)',
              fontSize: 10, fontWeight: 600, fontFamily: 'var(--font-mono)',
              padding: '1px 5px', borderRadius: 8,
            }}>
              {t.count}
            </span>
          )}
        </button>
      ))}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Painel de Decisoes
// ---------------------------------------------------------------------------
function DecisionsPanel({ execucaoId, waveFilter }: { execucaoId: string; waveFilter: string | null }) {
  const [expanded, setExpanded] = useState<string | null>(null);
  const [page, setPage] = useState(0);
  const limit = 20;
  const decOpts: Parameters<typeof useDecisions>[1] = { limit, offset: page * limit };
  if (waveFilter) decOpts.wave = waveFilter;
  const query = useDecisions(execucaoId, decOpts);
  const { isLoading, isError, errorMessage } = useApiState(query);
  const items: DecisionDTO[] = query.data?.data?.decisions ?? [];

  if (isLoading) return <LoadingState />;
  if (isError) return <ErrorState message={errorMessage ?? 'Erro'} />;
  if (!items.length) return <EmptyState title="Sem decisoes" subtitle="Nenhuma decisao encontrada para os filtros selecionados." />;

  return (
    <div>
      <table className="tbl">
        <thead>
          <tr>
            <th style={{ width: 28 }} />
            <th>Escolha</th>
            <th>Etapa</th>
            <th>Agente</th>
            <th>Onda</th>
            <th>Score</th>
          </tr>
        </thead>
        <tbody>
          {items.map((d, idx) => {
            const key = `${d.wave}-${idx}`;
            const isExp = expanded === key;
            return (
              <Fragment key={key}>
                <tr className="clickable" onClick={() => setExpanded(isExp ? null : key)}>
                  <td>
                    <Icon name={isExp ? 'chevron-down' : 'chevron-right'} size={12} style={{ color: 'var(--text-3)' }} />
                  </td>
                  <td><span style={{ color: 'var(--text-0)', fontWeight: 500 }}><TextRaw value={d.choice} maxLength={60} /></span></td>
                  <td><span style={{ fontFamily: 'var(--font-mono)', fontSize: 11.5 }}>{d.stage ?? '—'}</span></td>
                  <td><span style={{ fontFamily: 'var(--font-mono)', fontSize: 11, color: 'var(--text-2)' }}><TextRaw value={d.agent} maxLength={32} /></span></td>
                  <td><span style={{ fontFamily: 'var(--font-mono)', fontSize: 11.5 }}>{d.wave}</span></td>
                  <td><ScoreChip score={d.score} /></td>
                </tr>
                {isExp && (
                  <tr>
                    <td colSpan={6} style={{ background: 'var(--bg-2)', padding: '14px 16px' }}>
                      <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                        {(() => {
                          const opts = decisionOptions(d.options);
                          if (opts.length === 0) return null;
                          const chosenIdx = chosenOptionIndex(opts, d.choice);
                          return (
                          <div>
                            <div style={{ fontSize: 10.5, color: 'var(--text-3)', textTransform: 'uppercase', letterSpacing: '0.08em', marginBottom: 4, fontFamily: 'var(--font-mono)' }}>opcoes consideradas</div>
                            <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
                              {opts.map((opt, i) => {
                                const chosen = i === chosenIdx;
                                return (
                                  <span
                                    key={`${opt}-${i}`}
                                    title={chosen ? 'opcao escolhida' : undefined}
                                    style={{
                                      display: 'inline-flex', alignItems: 'center', gap: 4,
                                      padding: '2px 8px', borderRadius: 8, fontSize: 11,
                                      fontFamily: 'var(--font-mono)',
                                      background: chosen ? 'var(--accent-soft)' : 'var(--bg-1)',
                                      color: chosen ? 'var(--accent)' : 'var(--text-2)',
                                      border: `1px solid ${chosen ? 'var(--accent-line)' : 'var(--border)'}`,
                                      fontWeight: chosen ? 600 : 400,
                                    }}
                                  >
                                    {chosen && <Icon name="check" size={11} />}
                                    <TextRaw value={opt} maxLength={48} />
                                  </span>
                                );
                              })}
                            </div>
                          </div>
                          );
                        })()}
                        <div>
                          <div style={{ fontSize: 10.5, color: 'var(--text-3)', textTransform: 'uppercase', letterSpacing: '0.08em', marginBottom: 3, fontFamily: 'var(--font-mono)' }}>contexto</div>
                          <TextRaw value={d.context} />
                        </div>
                        <div>
                          <div style={{ fontSize: 10.5, color: 'var(--text-3)', textTransform: 'uppercase', letterSpacing: '0.08em', marginBottom: 3, fontFamily: 'var(--font-mono)' }}>justificativa</div>
                          <TextRaw value={d.rationale} />
                        </div>
                        {d.evidencia && (
                          <div>
                            <div style={{ fontSize: 10.5, color: 'var(--text-3)', textTransform: 'uppercase', letterSpacing: '0.08em', marginBottom: 3, fontFamily: 'var(--font-mono)' }}>evidencia (empirica)</div>
                            <div style={{ background: 'var(--bg-1)', border: '1px solid var(--border)', borderRadius: 'var(--r-xs)', padding: '8px 10px' }}>
                              <TextRaw value={d.evidencia} mono />
                            </div>
                          </div>
                        )}
                      </div>
                    </td>
                  </tr>
                )}
              </Fragment>
            );
          })}
        </tbody>
      </table>
      {/* Paginacao simples */}
      <div style={{ display: 'flex', justifyContent: 'space-between', padding: '10px 14px', borderTop: '1px solid var(--border)', fontSize: 12 }}>
        <button
          disabled={page === 0}
          onClick={() => setPage(p => p - 1)}
          style={{ background: 'var(--bg-2)', border: '1px solid var(--border)', borderRadius: 'var(--r-xs)', padding: '4px 10px', color: page === 0 ? 'var(--text-3)' : 'var(--text-1)', cursor: page === 0 ? 'default' : 'pointer' }}
        >
          anterior
        </button>
        <span style={{ color: 'var(--text-2)', fontFamily: 'var(--font-mono)', fontSize: 11 }}>
          pagina {page + 1} · {items.length} resultados
        </span>
        <button
          disabled={items.length < limit}
          onClick={() => setPage(p => p + 1)}
          style={{ background: 'var(--bg-2)', border: '1px solid var(--border)', borderRadius: 'var(--r-xs)', padding: '4px 10px', color: items.length < limit ? 'var(--text-3)' : 'var(--text-1)', cursor: items.length < limit ? 'default' : 'pointer' }}
        >
          proxima
        </button>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Painel de Tarefas
// ---------------------------------------------------------------------------
function TasksPanel({ execucaoId }: { execucaoId: string }) {
  const query = useTasks(execucaoId);
  const { isLoading, isError, errorMessage } = useApiState(query);
  const items: TaskDTO[] = query.data?.data?.tasks ?? [];

  if (isLoading) return <LoadingState />;
  if (isError) return <ErrorState message={errorMessage ?? 'Erro'} />;
  if (!items.length) return <EmptyState title="Sem tarefas registradas" subtitle="Tarefas sao gravadas pelo orquestrador durante execute-task." />;

  const totalTR = items.reduce((a, t) => a + (t.testsRun ?? 0), 0);
  const totalTP = items.reduce((a, t) => a + (t.testsPassed ?? 0), 0);
  const lintOk  = items.filter(t => t.lintOk).length;
  const fails   = items.filter(t => t.outcome === 'fail').length;

  return (
    <div>
      <div style={{ padding: '10px 14px', borderBottom: '1px solid var(--border)', display: 'flex', gap: 24 }}>
        {[
          { label: 'Tarefas', value: items.length },
          { label: 'Pass rate', value: totalTR ? `${((totalTP / totalTR) * 100).toFixed(1)}%` : '—', color: fails > 0 ? 'var(--warning)' : 'var(--success)' },
          { label: 'Lint OK', value: `${lintOk}/${items.length}` },
          { label: 'Fails', value: fails, color: fails > 0 ? 'var(--critical)' : 'var(--success)' },
        ].map(s => (
          <div key={s.label}>
            <div style={{ fontSize: 10, color: 'var(--text-3)', textTransform: 'uppercase', letterSpacing: '0.07em', marginBottom: 2 }}>{s.label}</div>
            <div style={{ fontFamily: 'var(--font-mono)', fontSize: 14, fontWeight: 700, color: s.color ?? 'var(--text-0)' }}>{String(s.value)}</div>
          </div>
        ))}
      </div>
      <table className="tbl">
        <thead>
          <tr>
            <th>Tarefa</th>
            <th>Onda</th>
            <th>Outcome</th>
            <th className="num">Testes</th>
            <th>Lint</th>
            <th className="num">Arquivos tocados</th>
          </tr>
        </thead>
        <tbody>
          {items.map((t, idx) => (
            <tr key={idx}>
              {/* titulo (v3) e untrusted — React escapa via textContent por padrao */}
              <td>{t.title?.trim()
                ? <span style={{ color: 'var(--text-0)' }}>{t.title}</span>
                : <span className="muted">—</span>}
              </td>
              <td><span style={{ fontFamily: 'var(--font-mono)', fontSize: 11.5 }}>{t.wave}</span></td>
              <td><OutcomePill outcome={t.outcome} /></td>
              <td className="num">{t.testsPassed}/{t.testsRun}</td>
              <td>{t.lintOk == null
                ? <span className="muted">—</span>
                : t.lintOk
                  ? <span className="pill pass">ok</span>
                  : <span className="pill fail">falhou</span>}
              </td>
              <td className="num">{t.touchedFilesCount ?? '—'}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Painel de Eventos
// ---------------------------------------------------------------------------
const EVENT_META: Record<string, { label: string; color: string; icon: string }> = {
  lock_contention:   { label: 'lock_contention',   color: 'var(--warning)',  icon: 'clock' },
  validation_failed: { label: 'validation_failed', color: 'var(--critical)', icon: 'alert' },
  wave_retry:        { label: 'wave_retry',         color: 'var(--info)',     icon: 'activity' },
  schedule_wait:     { label: 'schedule_wait',      color: 'var(--text-2)',   icon: 'clock' },
  recall_consulted:  { label: 'recall_consulted',   color: 'var(--info)',     icon: 'search' },
};

function EventsPanel({ execucaoId }: { execucaoId: string }) {
  const query = useEvents(execucaoId);
  const { isLoading, isError, errorMessage } = useApiState(query);
  const items: EventDTO[] = query.data?.data ?? [];

  if (isLoading) return <LoadingState />;
  if (isError) return <ErrorState message={errorMessage ?? 'Erro'} />;
  if (!items.length) return <EmptyState title="Sem eventos de timeline" subtitle="Eventos sao lock_contention, validation_failed, wave_retry, schedule_wait." />;

  return (
    <div style={{ padding: '14px 18px', display: 'flex', flexDirection: 'column', gap: 10 }}>
      {items.map((e, idx) => {
        const m = EVENT_META[e.eventType] ?? { label: e.eventType, color: 'var(--text-2)', icon: 'zap' };
        return (
          <div key={idx} style={{ display: 'flex', alignItems: 'flex-start', gap: 12 }}>
            <div style={{ width: 90, fontSize: 10.5, color: 'var(--text-3)', fontFamily: 'var(--font-mono)', flexShrink: 0 }}>
              {fmtTimestamp(e.timestamp)}
            </div>
            <div>
              <div className="row gap-2" style={{ marginBottom: 2 }}>
                <Icon name={m.icon} size={12} style={{ color: m.color }} />
                <span style={{ fontFamily: 'var(--font-mono)', fontSize: 11.5, color: m.color, fontWeight: 600 }}>{m.label}</span>
              </div>
              {e.description && (
                <div style={{ fontSize: 12.5, color: 'var(--text-1)' }}>
                  <TextRaw value={e.description} maxLength={200} />
                </div>
              )}
            </div>
          </div>
        );
      })}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Painel de Alertas (por execucao)
// ---------------------------------------------------------------------------
function AlertsPanel({ execucaoId }: { execucaoId: string }) {
  const query = useAlertsByExecution(execucaoId);
  const { isLoading, isError, errorMessage } = useApiState(query);
  const items: AlertSignalDTO[] = query.data?.data ?? [];

  if (isLoading) return <LoadingState />;
  if (isError) return <ErrorState message={errorMessage ?? 'Erro'} />;
  if (!items.length) return <EmptyState title="Sem alertas nesta execucao" subtitle="Tudo sob controle." />;

  return (
    <div style={{ padding: '14px 18px', display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(300px, 1fr))', gap: 12 }}>
      {items.map((a, idx) => {
        const isCircular = a.type === 'circular';
        const sevColor = a.description?.includes('critical') ? 'var(--critical)' : 'var(--warning)';
        const pct = a.consumedValue != null && a.thresholdValue != null && a.thresholdValue > 0
          ? Math.min(100, Math.round((a.consumedValue / a.thresholdValue) * 100))
          : null;
        return (
          <div key={idx} style={{
            background: 'var(--bg-2)', padding: 14, borderRadius: 'var(--r-md)',
            border: '1px solid var(--border)',
          }}>
            <div className="row" style={{ justifyContent: 'space-between', marginBottom: 10 }}>
              <div className="row gap-2">
                <Icon name={isCircular ? 'activity' : 'alert'} size={14} style={{ color: sevColor }} />
                <span style={{ fontFamily: 'var(--font-mono)', fontSize: 12, fontWeight: 600, color: 'var(--text-0)' }}>
                  {isCircular ? 'movimento circular' : `breach · ${a.subtype ?? '?'}`}
                </span>
              </div>
              <span style={{ fontFamily: 'var(--font-mono)', fontSize: 11, color: 'var(--text-2)' }}>{a.wave}</span>
            </div>
            {a.description && (
              <div style={{ fontSize: 12.5, color: 'var(--text-1)', marginBottom: 10 }}>
                <TextRaw value={a.description} maxLength={160} />
              </div>
            )}
            {pct != null && (
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <div style={{ flex: 1, height: 5, background: 'var(--bg-3)', borderRadius: 3, overflow: 'hidden' }}>
                  <div style={{ width: `${pct}%`, height: '100%', background: sevColor, borderRadius: 3 }} />
                </div>
                <span style={{ fontFamily: 'var(--font-mono)', fontSize: 11, color: 'var(--text-1)' }}>
                  {a.consumedValue} / {a.thresholdValue} ({pct}%)
                </span>
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Painel de Bloqueios
// ---------------------------------------------------------------------------
function BloqueiosPanel({ execucaoId }: { execucaoId: string }) {
  const query = useBloqueios(execucaoId);
  const { isLoading, isError, errorMessage } = useApiState(query);
  const items: BlockDTO[] = query.data?.data ?? [];

  if (isLoading) return <LoadingState />;
  if (isError) return <ErrorState message={errorMessage ?? 'Erro'} />;
  if (!items.length) return <EmptyState title="Sem bloqueios humanos" subtitle="Nenhum BloqueioHumano foi registrado nesta execucao." />;

  const STATUS_COLOR: Record<string, string> = {
    pendente:   'var(--warning)',
    respondido: 'var(--success)',
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 0 }}>
      {items.map((b, idx) => {
        const color = STATUS_COLOR[b.status ?? ''] ?? 'var(--text-2)';
        return (
          <div key={idx} style={{ padding: '14px 18px', borderBottom: '1px solid var(--border-soft)' }}>
            <div className="row" style={{ justifyContent: 'space-between', marginBottom: 8 }}>
              <div className="row gap-2">
                <Icon name="users" size={13} style={{ color }} />
                <span style={{ fontSize: 11, fontWeight: 600, color, fontFamily: 'var(--font-mono)' }}>
                  {b.status ?? 'desconhecido'}
                </span>
                {b.decisionId && (
                  <span style={{ fontSize: 10.5, color: 'var(--text-3)', fontFamily: 'var(--font-mono)' }}>
                    ref: {b.decisionId}
                  </span>
                )}
              </div>
              <div className="row gap-2" style={{ fontSize: 11, color: 'var(--text-3)', fontFamily: 'var(--font-mono)' }}>
                {b.latencySeconds != null && (
                  <span>latencia: {fmtDur(b.latencySeconds)}</span>
                )}
              </div>
            </div>
            <div style={{ marginBottom: 8 }}>
              <div style={{ fontSize: 10.5, color: 'var(--text-3)', textTransform: 'uppercase', letterSpacing: '0.07em', marginBottom: 3, fontFamily: 'var(--font-mono)' }}>pergunta</div>
              <TextRaw value={b.question} />
            </div>
            {b.contextForAnswer && (
              <div style={{ marginBottom: 8 }}>
                <div style={{ fontSize: 10.5, color: 'var(--text-3)', textTransform: 'uppercase', letterSpacing: '0.07em', marginBottom: 3, fontFamily: 'var(--font-mono)' }}>contexto para humano</div>
                <TextRaw value={b.contextForAnswer} />
              </div>
            )}
            {b.answer && (
              <div>
                <div style={{ fontSize: 10.5, color: 'var(--text-3)', textTransform: 'uppercase', letterSpacing: '0.07em', marginBottom: 3, fontFamily: 'var(--font-mono)' }}>resposta</div>
                <div style={{ background: 'var(--success-soft)', borderRadius: 'var(--r-xs)', padding: '6px 10px', fontSize: 12.5 }}>
                  <TextRaw value={b.answer} />
                </div>
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Painel de Sugestoes (schema v5 — melhorias propostas pela IA a skills)
// ---------------------------------------------------------------------------
const SEVERIDADE_META: Record<string, { label: string; color: string }> = {
  impeditiva:  { label: 'impeditiva',  color: 'var(--critical)' },
  aviso:       { label: 'aviso',       color: 'var(--warning)' },
  informativa: { label: 'informativa', color: 'var(--info)' },
};

function SuggestionsPanel({ execucaoId }: { execucaoId: string }) {
  const query = useSuggestions(execucaoId);
  const { isLoading, isError, errorMessage } = useApiState(query);
  const items: SuggestionDTO[] = query.data?.data ?? [];

  if (isLoading) return <LoadingState />;
  if (isError) return <ErrorState message={errorMessage ?? 'Erro'} />;
  if (!items.length) return <EmptyState title="Sem sugestoes" subtitle="A IA nao propos melhorias a skills nesta execucao (ou a base esta em schema < v5)." />;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 0 }}>
      {items.map((s, idx) => {
        const sev = SEVERIDADE_META[s.severity ?? ''] ?? { label: s.severity ?? '—', color: 'var(--text-2)' };
        return (
          <div key={s.sourceId || idx} style={{ padding: '14px 18px', borderBottom: '1px solid var(--border-soft)' }}>
            <div className="row" style={{ justifyContent: 'space-between', marginBottom: 8 }}>
              <div className="row gap-2">
                <Icon name="zap" size={13} style={{ color: sev.color }} />
                <span style={{ fontSize: 11, fontWeight: 600, color: sev.color, fontFamily: 'var(--font-mono)' }}>
                  {sev.label}
                </span>
                {s.affectedSkill && (
                  <span style={{ fontSize: 11, color: 'var(--text-1)', fontFamily: 'var(--font-mono)', padding: '1px 7px', background: 'var(--bg-3)', borderRadius: 8 }}>
                    {s.affectedSkill}
                  </span>
                )}
                <span style={{ fontSize: 10.5, color: 'var(--text-3)', fontFamily: 'var(--font-mono)' }}>
                  {s.sourceId}
                </span>
              </div>
              <div className="row gap-2" style={{ fontSize: 11, color: 'var(--text-3)', fontFamily: 'var(--font-mono)' }}>
                {s.issueOpened
                  ? <span style={{ color: 'var(--warning)' }}>issue: {s.issueOpened}</span>
                  : <span>{fmtTimestamp(s.createdAt)}</span>}
              </div>
            </div>
            <div style={{ marginBottom: 8 }}>
              <div style={{ fontSize: 10.5, color: 'var(--text-3)', textTransform: 'uppercase', letterSpacing: '0.07em', marginBottom: 3, fontFamily: 'var(--font-mono)' }}>diagnostico</div>
              <TextRaw value={s.diagnosis} />
            </div>
            {s.proposal && (
              <div style={{ marginBottom: s.referencias.length ? 8 : 0 }}>
                <div style={{ fontSize: 10.5, color: 'var(--text-3)', textTransform: 'uppercase', letterSpacing: '0.07em', marginBottom: 3, fontFamily: 'var(--font-mono)' }}>proposta</div>
                <div style={{ background: 'var(--bg-2)', borderRadius: 'var(--r-xs)', padding: '6px 10px', fontSize: 12.5 }}>
                  <TextRaw value={s.proposal} />
                </div>
              </div>
            )}
            {s.referencias.length > 0 && (
              <div>
                <div style={{ fontSize: 10.5, color: 'var(--text-3)', textTransform: 'uppercase', letterSpacing: '0.07em', marginBottom: 3, fontFamily: 'var(--font-mono)' }}>referencias</div>
                <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
                  {s.referencias.map((r, i) => (
                    <span key={i} style={{ fontSize: 11, color: 'var(--text-1)', fontFamily: 'var(--font-mono)', padding: '2px 7px', background: 'var(--bg-3)', border: '1px solid var(--border)', borderRadius: 8 }}>
                      <TextRaw value={r} maxLength={80} />
                    </span>
                  ))}
                </div>
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Cards laterais (coluna direita) — Decisoes por score, Top skills, Sugestoes
// ---------------------------------------------------------------------------
const SCORE_COLORS = ['var(--score-0)', 'var(--score-1)', 'var(--score-2)', 'var(--score-3)'];

const SCORES = [0, 1, 2, 3] as const;

function ScoreDistCard({ execucaoId }: { execucaoId: string }) {
  const query = useScoreDistribution(execucaoId);
  const rows = query.data?.data ?? [];
  const counts = SCORES.map(s => rows.find(r => r.score === s)?.count ?? 0);
  const max = Math.max(...counts, 1);
  return (
    <div className="card">
      <div className="card-head"><h3>Decisões por score</h3></div>
      <div className="card-pad col" style={{ gap: 8 }}>
        {SCORES.map((s) => {
          const c = counts[s] ?? 0;
          return (
            <div key={s} className="row" style={{ gap: 8, alignItems: 'center' }}>
              <ScoreChip score={s} />
              <div style={{ flex: 1, height: 6, background: 'var(--bg-3)', borderRadius: 3, overflow: 'hidden' }}>
                <div style={{ width: `${(c / max) * 100}%`, height: '100%', background: SCORE_COLORS[s] }} />
              </div>
              <span className="mono" style={{ width: 20, textAlign: 'right', fontSize: 11.5 }}>{c}</span>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function TopSkillsCard({ execucaoId }: { execucaoId: string }) {
  const query = useSkills(execucaoId);
  const items: SkillDTO[] = query.data?.data ?? [];
  const counts = items.reduce<Record<string, number>>((acc, s) => {
    acc[s.skillName] = (acc[s.skillName] ?? 0) + 1;
    return acc;
  }, {});
  const data = Object.entries(counts)
    .sort(([, a], [, b]) => b - a)
    .slice(0, 6)
    .map(([label, value]) => ({ label, value, color: 'var(--info)' }));
  return (
    <div className="card">
      <div className="card-head"><h3>Skills mais invocadas</h3></div>
      <div className="card-pad">
        {data.length === 0
          ? <div style={{ color: 'var(--text-3)', fontSize: 12 }}>Nenhuma skill registrada.</div>
          : <BarH data={data} maxLabel={110} />}
      </div>
    </div>
  );
}

function SuggestionsCard({ exec }: { exec: ExecutionDTO }) {
  const issues = exec.toolkitIssuesOpened;
  return (
    <div className="card">
      <div className="card-pad">
        <div className="row" style={{ justifyContent: 'space-between' }}>
          <MiniStat label="Sugestões ao toolkit" value={String(exec.skillSuggestionsTotal ?? '—')} />
          <MiniStat
            label="Issues abertas"
            value={String(issues ?? '—')}
            {...(issues ? { valueColor: 'var(--warning)' } : {})}
          />
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// ExecutionDetail — componente principal
// ---------------------------------------------------------------------------
export function ExecutionDetail() {
  const { execucaoId } = useParams<{ execucaoId: string }>();
  const [searchParams, setSearchParams] = useSearchParams();
  const navigate = useNavigate();

  const [selectedWave, setSelectedWave] = useState<string | null>(searchParams.get('wave'));
  const [activeTab, setActiveTab] = useState(searchParams.get('tab') ?? 'decisions');

  const execQuery = useExecution(execucaoId ?? '');
  const wavesQuery = useWaves(execucaoId ?? '');
  const { isLoading, isError, errorMessage, isDegraded } = useApiState(execQuery);

  if (isLoading) return <LoadingState />;
  if (isError) return <ErrorState message={errorMessage ?? 'Erro ao carregar execucao.'} />;

  const exec: ExecutionDTO | null = execQuery.data?.data ?? null;
  const meta = execQuery.data?.meta;
  const waves: WaveDTO[] = wavesQuery.data?.data ?? [];

  if (!exec) return <EmptyState title="Execucao nao encontrada" subtitle="O execucao_id informado nao existe na base." />;

  // Rota de volta para a feature-mae (null quando a execucao nao tem feature)
  const featurePath = exec.feature
    ? `/features/${encodeURIComponent(exec.project)}/${encodeURIComponent(exec.feature)}`
    : null;

  function handleSelectWave(wave: string | null) {
    setSelectedWave(wave);
    const params = new URLSearchParams(searchParams);
    if (wave) params.set('wave', wave); else params.delete('wave');
    setSearchParams(params, { replace: true });
  }

  function handleTabChange(tab: string) {
    setActiveTab(tab);
    const params = new URLSearchParams(searchParams);
    params.set('tab', tab);
    setSearchParams(params, { replace: true });
  }

  const tabs = [
    { value: 'decisions', label: 'Decisoes',  count: exec.decisionsTotal ?? 0 },
    { value: 'tasks',     label: 'Tarefas',   count: 0 },
    { value: 'events',    label: 'Eventos',   count: 0 },
    { value: 'alerts',    label: 'Alertas',   count: 0 },
    { value: 'bloqueios', label: 'Bloqueios', count: exec.humanBlocksTotal ?? 0 },
    { value: 'suggestions', label: 'Sugestoes', count: exec.skillSuggestionsTotal ?? 0 },
  ];

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      {isDegraded && meta && <DegradedBanner meta={meta} />}

      {/* Header */}
      <div className="card">
        <div className="card-body">
          <div className="row" style={{ justifyContent: 'space-between', flexWrap: 'wrap', gap: 12, marginBottom: 12 }}>
            <div style={{ minWidth: 0 }}>
              <div className="row gap-2" style={{ marginBottom: 4 }}>
                <StatusBadge status={exec.status} />
                <span style={{ fontFamily: 'var(--font-mono)', fontSize: 11, color: 'var(--text-3)' }}>execucao</span>
                <span style={{ fontFamily: 'var(--font-mono)', fontSize: 11.5, color: 'var(--accent)', fontWeight: 600 }}>
                  {exec.executionId}
                </span>
              </div>
              <div style={{ fontSize: 18, fontWeight: 700, marginBottom: 4 }}>
                {exec.feature ?? exec.executionId}
              </div>
              <div className="row gap-2" style={{ fontSize: 11.5, color: 'var(--text-2)' }}>
                <span className="prov" style={{ fontSize: 11.5 }}>
                  <a onClick={() => navigate(`/projects/${encodeURIComponent(exec.project)}`)} title="Ir para o projeto">
                    {exec.project}
                  </a>
                  {featurePath && (
                    <>
                      <span className="sep">/</span>
                      <a onClick={() => navigate(featurePath)} title="Voltar para a feature">
                        {exec.feature}
                      </a>
                    </>
                  )}
                </span>
                <span style={{ color: 'var(--text-3)' }}>·</span>
                <span>iniciada {fmtTimestamp(exec.startedAt)}</span>
                {exec.session && (
                  <>
                    <span style={{ color: 'var(--text-3)' }}>·</span>
                    {/* sessao de worktree (schema v8) — texto livre, React escapa via textContent */}
                    <span
                      title="sessao de worktree de origem"
                      style={{
                        display: 'inline-flex', alignItems: 'center', gap: 4,
                        fontFamily: 'var(--font-mono)', fontSize: 10.5,
                        padding: '1px 7px', borderRadius: 8,
                        background: 'var(--bg-3)', color: 'var(--text-1)',
                        border: '1px solid var(--border)',
                      }}
                    >
                      <Icon name="git-branch" size={10} aria-hidden />
                      {exec.session}
                    </span>
                  </>
                )}
              </div>
            </div>
            <div className="row gap-2" style={{ flexShrink: 0 }}>
              {featurePath && (
                <button
                  className="tb-btn"
                  onClick={() => navigate(featurePath)}
                  title="Voltar ao detalhe da feature"
                >
                  <Icon name="chevron-left" size={13} aria-hidden />voltar à feature
                </button>
              )}
              <button
                className="tb-btn"
                onClick={() =>
                  navigate(
                    `/executions/${encodeURIComponent(execucaoId ?? '')}/decision-map${
                      selectedWave ? `?wave=${encodeURIComponent(selectedWave)}` : ''
                    }`
                  )
                }
                title="Abrir árvore de decisões"
              >
                <Icon name="tree" size={13} aria-hidden />árvore de decisões
              </button>
            </div>
          </div>

          {/* Stats row */}
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(120px, 1fr))', gap: 12, marginBottom: 14 }}>
            {[
              { label: 'Etapa corrente',  value: exec.currentStage ?? '—', color: exec.status === 'em_andamento' ? 'var(--inprogress)' : 'var(--text-0)', mono: true },
              { label: 'Duracao',         value: fmtDur(exec.durationSeconds) },
              { label: 'Custo · proxy',   value: fmtNum(exec.toolCallsTotal) },
              // Custo REAL da execucao = soma das ondas medidas (schema v11).
              // Fica ao lado do proxy, nao no lugar dele: um conta esforco do
              // orquestrador, o outro dinheiro, e a cobertura pode ser parcial.
              { label: 'Custo · real',    value: fmtUsd(sumOtelUsage(waves).costUsd), mono: true },
              // Contagem real das ondas (linhas da tabela waves) em vez do campo
              // denormalizado exec.wavesTotal, que o orquestrador nem sempre
              // incrementa (ver agente-00c wave bookkeeping defect). Fallback para
              // o campo cacheado enquanto a lista de ondas ainda não carregou.
              { label: 'Ondas',           value: String(waves.length || exec.wavesTotal || '—') },
              { label: 'Subagentes',      value: String(exec.subagentsSpawned ?? '—') },
              { label: 'Prof. maxima',    value: String(exec.maxDepth ?? '—') },
              { label: 'Decisoes',        value: String(exec.decisionsTotal ?? '—') },
              { label: 'Bloqueios',       value: String(exec.humanBlocksTotal ?? '—') },
            ].map(s => (
              <div key={s.label}>
                <div style={{ fontSize: 10, color: 'var(--text-3)', textTransform: 'uppercase', letterSpacing: '0.07em', marginBottom: 2 }}>{s.label}</div>
                <div style={{
                  fontFamily: s.mono ? 'var(--font-mono)' : 'inherit',
                  fontSize: 14, fontWeight: 700, color: s.color ?? 'var(--text-0)',
                }}>
                  {s.value}
                </div>
              </div>
            ))}
          </div>

          <PipelineProgress etapa={exec.currentStage} status={exec.status} labeled />

          {stackDisplayItems(exec.suggestedStack).length > 0 && (
            <div style={{ marginTop: 10, display: 'flex', gap: 6, flexWrap: 'wrap' }}>
              {stackDisplayItems(exec.suggestedStack).map(s => (
                <span key={s} style={{
                  padding: '2px 7px', borderRadius: 8, fontSize: 11,
                  background: 'var(--bg-3)', color: 'var(--text-1)',
                  border: '1px solid var(--border)', fontFamily: 'var(--font-mono)',
                }}>
                  {s}
                </span>
              ))}
            </div>
          )}
        </div>
      </div>

      {/* Gantt (esquerda) + cards laterais (direita) — layout 2 colunas */}
      <div className="exec-grid">
        <WavesTimeline
          waves={waves}
          execId={execucaoId ?? ''}
          selectedWave={selectedWave}
          onSelectWave={handleSelectWave}
        />
        <div className="col gap-4">
          <ScoreDistCard execucaoId={execucaoId ?? ''} />
          <TopSkillsCard execucaoId={execucaoId ?? ''} />
          <SuggestionsCard exec={exec} />
        </div>
      </div>

      {/* Tabs */}
      <div className="card">
        <TabBar tabs={tabs} activeTab={activeTab} onChange={handleTabChange} />
        <div>
          {activeTab === 'decisions' && (
            <DecisionsPanel execucaoId={execucaoId ?? ''} waveFilter={selectedWave} />
          )}
          {activeTab === 'tasks'     && <TasksPanel execucaoId={execucaoId ?? ''} />}
          {activeTab === 'events'    && <EventsPanel execucaoId={execucaoId ?? ''} />}
          {activeTab === 'alerts'    && <AlertsPanel execucaoId={execucaoId ?? ''} />}
          {activeTab === 'bloqueios' && <BloqueiosPanel execucaoId={execucaoId ?? ''} />}
          {activeTab === 'suggestions' && <SuggestionsPanel execucaoId={execucaoId ?? ''} />}
        </div>
      </div>
    </div>
  );
}
