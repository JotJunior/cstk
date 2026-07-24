/**
 * FeatureDetail — cabecalho + stats + tabela de execucoes da feature.
 * Layout do prototipo (screens_main.jsx · FeatureDetailScreen).
 */
import { useEffect, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { useFeature, useFeatureDocs, useFeatureDocContent } from '@/lib/hooks.js';
import { useApiState } from '@/hooks/useApiState.js';
import { LoadingState, EmptyState, ErrorState, DegradedBanner } from '@/states/index.js';
import { StatusBadge, MiniStat, PipelineProgress, Icon, MarkdownView } from '@/components/index.js';
import { fmtNum, fmtDur, fmtTimestamp } from '@/lib/format.js';
import { stackDisplayItems } from '@/lib/stack-display.js';
import type { ExecutionDTO, FeatureDocScope, RetroDTO } from '@cstk-panel/shared-types';

// ---------------------------------------------------------------------------
// Documentacao (doc-viewer, US2 — task 4.3)
// ---------------------------------------------------------------------------

/**
 * Escolhe o artefato inicial a exibir: o primeiro PRODUZIDO **da propria
 * feature** na ordem da listagem (ordem = pipeline SDD: spec, plan, research,
 * data-model, quickstart, tasks, contracts/checklists, extras). A listagem
 * comeca por briefing/constitution (escopo projeto, iguais para todas as
 * features), mas quem abre a pagina de UMA feature quer ver a spec dela —
 * por isso o escopo `feature` tem prioridade na selecao default; os
 * artefatos de projeto ficam a 1 clique na navegacao.
 *
 * Se a feature nao produziu nada ainda, cai no primeiro produzido de qualquer
 * escopo (briefing/constitution ja dao contexto util); se nada foi produzido,
 * cai no primeiro item da lista de qualquer forma — o painel mostra o estado
 * "ainda nao produzido" em vez de ficar vazio (Principio II
 * Degradar-Nunca-Quebrar). `null` somente quando a listagem esta
 * genuinamente vazia (resposta degradada, sem artefatos).
 *
 * Extraida como funcao pura para teste unitario direto (sem montar DOM —
 * mesmo padrao de `stageStates` em PipelineProgress.tsx) — task 4.3.4.
 *
 * Parametro tipado com o subconjunto MINIMO que a funcao usa (nao
 * `FeatureDocDTO` completo) deliberadamente: o campo `content` de
 * `FeatureDocDTOSchema` e opcional+nullable (ausente na listagem, `null`
 * no endpoint de conteudo quando `produced:false`) e o Zod-infer resultante
 * colide com `exactOptionalPropertyTypes` (tsconfig.base.json) ao ser
 * atribuido a interface manual `content?: string | null`. Como esta funcao
 * nunca le `content`, programar contra a interface minima evita o atrito
 * por completo (e mantem a assinatura facil de testar com fixtures leves).
 */
export interface ArtifactPickCandidate {
  artifactId: string;
  produced: boolean;
  scope: FeatureDocScope;
}

export function pickDefaultArtifact(artifacts: readonly ArtifactPickCandidate[]): string | null {
  const ownProduced = artifacts.find(a => a.produced && a.scope === 'feature');
  if (ownProduced) return ownProduced.artifactId;
  const anyProduced = artifacts.find(a => a.produced);
  if (anyProduced) return anyProduced.artifactId;
  const own = artifacts.find(a => a.scope === 'feature');
  return own?.artifactId ?? artifacts[0]?.artifactId ?? null;
}

/**
 * Decide se/qual `artifactId` buscar no endpoint de CONTEUDO: so busca
 * quando o artefato selecionado ja foi PRODUZIDO — a listagem ja informa
 * isso sem round-trip extra (Cenario 5, "ainda nao produzido" e servido
 * localmente a partir da propria listagem). String vazia desabilita
 * `useFeatureDocContent` (seu `enabled` interno e `Boolean(artifactId)`).
 * Exportada para teste unitario direto — task 4.3.4.
 */
export function contentFetchId(
  selectedEntry: ArtifactPickCandidate | null,
  effectiveArtifactId: string | null
): string {
  return selectedEntry?.produced ? (effectiveArtifactId ?? '') : '';
}

/** Grupos da navegação, na ordem da pipeline SDD (projeto antes de feature). */
const DOC_SCOPE_GROUPS: ReadonlyArray<{ scope: FeatureDocScope; label: string }> = [
  { scope: 'project', label: 'Projeto' },
  { scope: 'feature', label: 'Feature' },
];

function DocumentationPanel({ project, feature }: { project: string; feature: string }) {
  const docsQuery = useFeatureDocs(project, feature);
  const { isLoading, isError, errorMessage, isDegraded } = useApiState(docsQuery);
  const [selectedArtifactId, setSelectedArtifactId] = useState<string | null>(null);

  // Navegou para outra feature: descarta a selecao manual anterior (pode
  // nem existir na nova lista) e deixa o default ser recalculado.
  useEffect(() => {
    setSelectedArtifactId(null);
  }, [project, feature]);

  const artifacts = docsQuery.data?.data?.artifacts ?? [];
  const effectiveArtifactId = selectedArtifactId ?? pickDefaultArtifact(artifacts);
  const selectedEntry = artifacts.find(a => a.artifactId === effectiveArtifactId) ?? null;

  // So busca conteudo quando o artefato selecionado ja foi produzido —
  // evita round-trip desnecessario (listagem ja informa produced:false).
  const contentQuery = useFeatureDocContent(
    project,
    feature,
    contentFetchId(selectedEntry, effectiveArtifactId)
  );

  if (isLoading) return <div className="card"><div className="card-pad"><LoadingState /></div></div>;
  if (isError) return <div className="card"><div className="card-pad"><ErrorState message={errorMessage ?? 'Erro ao carregar documentação.'} /></div></div>;

  return (
    <div className="card">
      <div className="card-head">
        <div className="row gap-2">
          <Icon name="doc" size={15} aria-hidden />
          <h3>Documentação</h3>
        </div>
        <span className="mono muted" style={{ fontSize: 11 }}>{artifacts.length} artefato{artifacts.length !== 1 ? 's' : ''}</span>
      </div>

      {isDegraded && docsQuery.data?.meta && <div style={{ padding: '10px 14px' }}><DegradedBanner meta={docsQuery.data.meta} /></div>}

      {artifacts.length === 0 ? (
        <EmptyState title="Sem artefatos de documentação" subtitle="Esta feature ainda não produziu nenhum artefato SDD." />
      ) : (
        <div className="docs-layout">
          {/* Navegação por artefato: lista vertical à esquerda no desktop;
              no modo estreito o CSS a troca pelo select abaixo (mesmo padrão
              esconde/mostra de .projects-list/.projects-cards). Agrupada por
              escopo: briefing/constitution valem para o projeto inteiro, o
              resto é desta feature. */}
          <nav className="docs-nav" aria-label="Artefatos de documentação">
            {DOC_SCOPE_GROUPS.map(({ scope, label }) => {
              const group = artifacts.filter(a => a.scope === scope);
              if (group.length === 0) return null;
              return (
                <div key={scope} className="docs-nav-group">
                  <div className="docs-nav-group-label">{label}</div>
                  {group.map(a => (
                    <button
                      key={a.artifactId}
                      type="button"
                      className={[
                        'docs-nav-item',
                        a.artifactId === effectiveArtifactId ? 'active' : '',
                        a.produced ? '' : 'missing',
                      ].filter(Boolean).join(' ')}
                      aria-current={a.artifactId === effectiveArtifactId ? 'true' : undefined}
                      onClick={() => setSelectedArtifactId(a.artifactId)}
                    >
                      <span className="docs-nav-label">{a.artifactId}</span>
                      {!a.produced && <span className="docs-nav-hint">ausente</span>}
                    </button>
                  ))}
                </div>
              );
            })}
          </nav>
          <div className="docs-select-wrap">
            <select
              className="docs-select"
              value={effectiveArtifactId ?? ''}
              onChange={e => setSelectedArtifactId(e.target.value)}
              aria-label="Artefato de documentação"
            >
              {DOC_SCOPE_GROUPS.map(({ scope, label }) => {
                const group = artifacts.filter(a => a.scope === scope);
                if (group.length === 0) return null;
                return (
                  <optgroup key={scope} label={label}>
                    {group.map(a => (
                      <option key={a.artifactId} value={a.artifactId}>
                        {a.produced ? a.artifactId : `${a.artifactId} (ausente)`}
                      </option>
                    ))}
                  </optgroup>
                );
              })}
            </select>
          </div>
          <div className="docs-content card-pad">
            {!selectedEntry && (
              <EmptyState title="Nenhum artefato selecionado" subtitle="Escolha um artefato acima." />
            )}
            {selectedEntry && !selectedEntry.produced && (
              <EmptyState
                title="Ainda não produzido"
                subtitle={`O artefato "${selectedEntry.artifactId}" (${selectedEntry.fileName}) ainda não foi gerado ${selectedEntry.scope === 'project' ? 'neste projeto' : 'por esta feature'}.`}
              />
            )}
            {selectedEntry?.produced && contentQuery.isLoading && <LoadingState />}
            {selectedEntry?.produced && contentQuery.isError && (
              <ErrorState message="Erro ao carregar conteúdo do artefato." />
            )}
            {selectedEntry?.produced && contentQuery.data?.data?.content != null && (
              <MarkdownView content={contentQuery.data.data.content} />
            )}
          </div>
        </div>
      )}
    </div>
  );
}

interface FeatureRollupShape {
  totalExecutions: number;
  totalToolCalls: number | null;
  totalWallclock: number | null;
  totalDecisions: number | null;
  totalWaves: number | null;
  currentStage: string | null;
  latestStatus: 'em_andamento' | 'aguardando_humano' | 'concluida' | 'abortada' | null;
}

export function FeatureDetail() {
  const navigate = useNavigate();
  const { project = '', feature = '' } = useParams();
  const query = useFeature(project, feature);
  const { isLoading, isError, errorMessage } = useApiState(query);

  if (isLoading) return <LoadingState variant="kpi" />;
  if (isError) return <ErrorState message={errorMessage ?? 'Erro ao carregar feature.'} />;

  const data = query.data?.data as { rollup?: FeatureRollupShape; executions?: ExecutionDTO[]; retros?: RetroDTO[] } | null;
  if (!data) return <EmptyState title="Feature não encontrada" subtitle={`${project} / ${feature}`} />;

  const rollup = data.rollup;
  const executions = data.executions ?? [];
  const retros = data.retros ?? [];
  const status = rollup?.latestStatus ?? null;

  // Stack: primeira execucao com stack_sugerida (CARD-FTD-02)
  const stack = executions.find(e => e.suggestedStack)?.suggestedStack ?? null;
  const stackItems = stackDisplayItems(stack);
  // Execucao mais recente para "Ver execução" (CARD-FTD-03)
  const latestExecId = executions[0]?.executionId ?? null;

  return (
    <div className="col gap-4">
      {/* Cabecalho */}
      <div className="card">
        <div className="card-pad">
          <div className="row" style={{ justifyContent: 'space-between', flexWrap: 'wrap', gap: 12 }}>
            <div style={{ minWidth: 0 }}>
              <div className="row gap-2">
                <StatusBadge status={status} />
                <h2 style={{ margin: 0, fontSize: 20, fontWeight: 600 }}>{feature}</h2>
              </div>
              <div className="prov" style={{ marginTop: 6 }}>
                <a onClick={() => navigate(`/projects/${encodeURIComponent(project)}`)}>{project}</a>
                <span className="sep">/</span>
                <span>{feature}</span>
              </div>
              {stackItems.length > 0 && (
                <div className="row gap-2" style={{ marginTop: 10, flexWrap: 'wrap' }}>
                  {stackItems.map(s => (
                    <span key={s} style={{
                      padding: '2px 7px', borderRadius: 8, fontSize: 11,
                      background: 'var(--bg-3)', color: 'var(--text-1)',
                      border: '1px solid var(--border)', fontFamily: 'var(--font-mono)',
                    }}>{s}</span>
                  ))}
                </div>
              )}
            </div>
            <div className="row gap-2" style={{ flexShrink: 0, alignItems: 'flex-start' }}>
              <button
                className="tb-btn"
                disabled={!latestExecId}
                onClick={() => latestExecId && navigate(`/executions/${encodeURIComponent(latestExecId)}`)}
              >
                <Icon name="activity" size={13} aria-hidden />Ver execução
              </button>
              <button className="tb-btn" disabled title="Disponível via skill decision-tree (externo)">
                <Icon name="tree" size={13} aria-hidden />Árvore de decisões
              </button>
            </div>
          </div>

          <div className="divider" />

          <div className="grid-6">
            <MiniStat label="Etapa corrente" value={<span className="mono" style={{ color: status === 'em_andamento' ? 'var(--inprogress)' : 'var(--text-0)' }}>{rollup?.currentStage ?? '—'}</span>} />
            <MiniStat label="Ondas" value={fmtNum(rollup?.totalWaves)} />
            <MiniStat label="Tool calls" value={fmtNum(rollup?.totalToolCalls)} />
            <MiniStat label="Wallclock" value={fmtDur(rollup?.totalWallclock)} />
            <MiniStat label="Decisões" value={fmtNum(rollup?.totalDecisions)} />
            <MiniStat label="Execuções" value={rollup?.totalExecutions ?? executions.length} />
          </div>

          <div style={{ marginTop: 14 }}>
            <PipelineProgress etapa={rollup?.currentStage ?? null} status={status} labeled />
          </div>
        </div>
      </div>

      {/* Execucoes */}
      <div className="card">
        <div className="card-head">
          <h3>Execuções</h3>
          <span className="mono muted" style={{ fontSize: 11 }}>{executions.length} registro{executions.length !== 1 ? 's' : ''}</span>
        </div>
        <div style={{ overflowX: 'auto' }}>
          <table className="tbl">
            <thead>
              <tr>
                <th>execucao_id</th>
                <th>Status</th>
                <th>Iniciada</th>
                <th>Terminada</th>
                <th className="num">Duração</th>
                <th className="num">Ondas</th>
                <th className="num">Tool calls</th>
                <th>Motivo</th>
              </tr>
            </thead>
            <tbody>
              {executions.length === 0 ? (
                <tr><td colSpan={8} style={{ textAlign: 'center', color: 'var(--text-3)', padding: 24 }}>Sem execuções.</td></tr>
              ) : executions.map((e, idx) => (
                <tr key={e.executionId || idx} className="clickable" onClick={() => navigate(`/executions/${encodeURIComponent(e.executionId)}`)}>
                  <td className="mono" style={{ color: 'var(--accent)', fontSize: 11.5 }}>{e.executionId.slice(0, 40)}</td>
                  <td><StatusBadge status={e.status} /></td>
                  <td className="mono" style={{ fontSize: 11.5 }}>{fmtTimestamp(e.startedAt)}</td>
                  <td className="mono" style={{ fontSize: 11.5 }}>{fmtTimestamp(e.finishedAt)}</td>
                  <td className="num">{fmtDur(e.durationSeconds)}</td>
                  <td className="num">{e.wavesTotal ?? '—'}</td>
                  <td className="num">{fmtNum(e.toolCallsTotal)}</td>
                  <td className="mono muted" style={{ fontSize: 11.5 }}>{e.terminationReason ?? '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {/* Retrospectivas (CARD-FTD-06) */}
      <div className="card">
        <div className="card-head">
          <h3>Retrospectivas</h3>
          <span className="mono muted" style={{ fontSize: 11 }}>{retros.length} entrada{retros.length !== 1 ? 's' : ''}</span>
        </div>
        <div className="card-pad col" style={{ gap: 8 }}>
          {retros.length === 0 ? (
            <div style={{ color: 'var(--text-3)', fontSize: 12, textAlign: 'center', padding: '12px 0' }}>
              Sem retros ainda. Retros são geradas ao final das ondas relevantes.
            </div>
          ) : (
            retros.map((r, idx) => (
              <div key={`${r.executionId}/${r.wave}/${idx}`} style={{ background: 'var(--bg-2)', padding: 12, borderRadius: 'var(--r-sm)', border: '1px solid var(--border)' }}>
                <div className="row gap-2" style={{ marginBottom: 6 }}>
                  <span className="tag accent">retro</span>
                  <span className="mono muted" style={{ fontSize: 11.5 }}>{r.wave}</span>
                </div>
                <div style={{ color: 'var(--text-1)', fontSize: 12.5 }}>{r.text ?? '—'}</div>
              </div>
            ))
          )}
        </div>
      </div>

      {/* Documentacao (doc-viewer, US2 — task 4.3) */}
      <DocumentationPanel project={project} feature={feature} />
    </div>
  );
}
