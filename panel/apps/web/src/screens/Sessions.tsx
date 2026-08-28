/**
 * Sessions — trilha de sessoes do Claude Code (US1, spec.md).
 *
 * Lista sessoes VIVAS (janela de liveness, FR-007) descobertas no disco
 * pelo watcher de sessoes. Drill-down para `/sessions/:sessionId` (US2).
 *
 * IMPORTANTE (dec-025): NAO ha join verificado entre sessao e execucao —
 * `executions.session` guarda short-name, nao o `sessionId` (UUID). Esta
 * tela exibe exclusivamente os campos reais de `SessionSummaryDTO`
 * (sessionId, projectPath, projectSlug, lastActivityAt, live, sizeBytes) —
 * nenhum vinculo com execucao/onda e inferido ou exibido.
 *
 * Ref: contracts/sessions-api.md; tasks.md §6.3.1; plan.md §Complexity
 * Tracking (`refetchInterval` explicito via useSessions).
 */
import { useNavigate } from 'react-router-dom';
import { useSessions } from '@/lib/hooks.js';
import { useApiState } from '@/hooks/useApiState.js';
import { LoadingState, EmptyState, ErrorState, DegradedBanner } from '@/states/index.js';
import { FreshnessLabel } from '@/components/index.js';
import { fmtRelative, fmtTimestamp } from '@/lib/format.js';
import type { SessionSummaryDTO, DegradedReason } from '@cstk-panel/shared-types';

/** Bytes → "B"/"KB"/"MB", mesma escala usada em Source.tsx. */
export function fmtSessionBytes(bytes: number | null | undefined): string {
  if (bytes == null) return '—';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

/**
 * Copy legivel por `reason` de degradacao de `GET /sessions` (US3 —
 * cada condicao adversa tem renderizacao propria, nunca tela em branco).
 * `default` cobre qualquer literal futuro sem quebrar a tela (Principio II).
 */
export function sessionsDegradedCopy(reason: DegradedReason | string | null): { title: string; subtitle: string } {
  switch (reason) {
    case 'sessions-root-missing':
      return {
        title: 'Raiz de sessões ausente',
        subtitle: '~/.claude/projects não foi encontrado neste host.',
      };
    case 'sessions-root-unreadable':
      return {
        title: 'Raiz de sessões sem permissão de leitura',
        subtitle: 'O diretório existe, mas não pôde ser lido (permissão do sistema de arquivos).',
      };
    default:
      return {
        title: 'Sessões indisponíveis no momento',
        subtitle: 'Tente novamente em instantes.',
      };
  }
}

/** Rotulo de projeto: prefere `projectPath` (mais legivel); cai para `projectSlug`. */
export function sessionProjectLabel(s: Pick<SessionSummaryDTO, 'projectPath' | 'projectSlug'>): string {
  return s.projectPath ?? s.projectSlug;
}

export function Sessions() {
  const navigate = useNavigate();
  const query = useSessions(true);
  const { isLoading, isError, errorMessage, isDegraded } = useApiState(query);

  if (isLoading) return <LoadingState variant="table" />;
  if (isError) return <ErrorState message={errorMessage ?? 'Erro ao carregar sessões.'} />;

  const meta = query.data?.meta;
  const data = query.data?.data;

  if (isDegraded) {
    const copy = sessionsDegradedCopy(meta?.reason ?? null);
    return (
      <div className="col gap-4">
        {meta && <DegradedBanner meta={meta} />}
        <EmptyState title={copy.title} subtitle={copy.subtitle} />
      </div>
    );
  }

  const sessions: SessionSummaryDTO[] = data?.sessions ?? [];
  const scannedAt = data?.scannedAt ?? null;

  return (
    <div className="col gap-4">
      <div className="page-head">
        <div>
          <h1>Sessões</h1>
          <div className="sub">
            Sessões do Claude Code vivas neste host · atualiza automaticamente
          </div>
        </div>
        <FreshnessLabel freshness={scannedAt ? { mtime: scannedAt, maxIngestedAt: scannedAt } : null} />
      </div>

      <div className="card">
        <div className="card-head">
          <div className="row gap-2">
            <h3>Sessões vivas</h3>
            <span style={{ background: 'var(--bg-3)', color: 'var(--text-1)', fontSize: 10, fontWeight: 600, fontFamily: 'var(--font-mono)', padding: '1px 7px', borderRadius: 10 }}>
              {sessions.length}
            </span>
          </div>
        </div>
        {sessions.length === 0 ? (
          <EmptyState title="Nenhuma sessão ativa" subtitle="Nenhuma sessão do Claude Code está viva neste momento." />
        ) : (
          <div style={{ overflowX: 'auto' }}>
            <table className="tbl">
              <thead>
                <tr>
                  <th>Sessão</th>
                  <th>Projeto</th>
                  <th>Estado</th>
                  <th className="num">Tamanho</th>
                  <th>Última atividade</th>
                </tr>
              </thead>
              <tbody>
                {sessions.map((s) => (
                  <tr
                    key={s.sessionId}
                    className="clickable"
                    onClick={() => navigate(`/sessions/${encodeURIComponent(s.sessionId)}`)}
                  >
                    <td>
                      <span style={{ fontFamily: 'var(--font-mono)', fontSize: 11, color: 'var(--accent)' }}>
                        {s.sessionId.slice(0, 8)}…
                      </span>
                    </td>
                    <td>
                      <span style={{ fontSize: 12.5, color: 'var(--text-0)' }} title={s.projectPath ?? undefined}>
                        {sessionProjectLabel(s)}
                      </span>
                    </td>
                    <td>
                      <span
                        style={{
                          display: 'inline-flex', alignItems: 'center', gap: 5,
                          fontSize: 11, fontWeight: 600,
                          color: s.live ? 'var(--success)' : 'var(--text-3)',
                        }}
                      >
                        <span
                          style={{
                            width: 6, height: 6, borderRadius: '50%',
                            background: s.live ? 'var(--success)' : 'var(--text-3)',
                            display: 'inline-block',
                          }}
                          aria-hidden
                        />
                        {s.live ? 'ao vivo' : 'inativa'}
                      </span>
                    </td>
                    <td className="num" style={{ fontFamily: 'var(--font-mono)', fontSize: 11 }}>
                      {fmtSessionBytes(s.sizeBytes)}
                    </td>
                    <td>
                      <span style={{ fontFamily: 'var(--font-mono)', fontSize: 11, color: 'var(--text-2)' }} title={fmtTimestamp(s.lastActivityAt)}>
                        {fmtRelative(s.lastActivityAt)}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
