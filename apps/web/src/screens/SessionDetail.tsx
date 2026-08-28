/**
 * SessionDetail — tail do transcript de UMA sessao do Claude Code (US2).
 *
 * Roteia EXCLUSIVAMENTE pelo `sessionId` da propria sessao (FR-004) — nunca
 * por `executionId`; nao ha join verificado entre sessao e execucao
 * (dec-025). Servido independente de liveness (FR-003): uma sessao com
 * `live: false` ainda exibe conteudo normalmente.
 *
 * `entries[].text` e UNTRUSTED (FR-005, Principio V) — renderizado via
 * `TextBlockRaw`, NUNCA `dangerouslySetInnerHTML`.
 *
 * Ref: contracts/sessions-api.md; tasks.md §6.3.2.
 */
import { useParams } from 'react-router-dom';
import { useSessionTail } from '@/lib/hooks.js';
import { useApiState } from '@/hooks/useApiState.js';
import { LoadingState, EmptyState, ErrorState, DegradedBanner } from '@/states/index.js';
import { FreshnessLabel, TextBlockRaw } from '@/components/index.js';
import { fmtRelative, fmtTimestamp } from '@/lib/format.js';
import type { SessionTailEntryDTO, DegradedReason } from '@cstk-panel/shared-types';

/**
 * Copy legivel por `reason` de degradacao de `GET /sessions/:sessionId/tail`
 * (US3 — cada condicao adversa tem renderizacao propria, nunca tela em
 * branco). `default` cobre qualquer literal futuro sem quebrar a tela.
 */
export function sessionDetailDegradedCopy(reason: DegradedReason | string | null): { title: string; subtitle: string } {
  switch (reason) {
    case 'session-not-found':
      return {
        title: 'Sessão não encontrada',
        subtitle: 'Ela pode ter sido encerrada e removida do índice entre a listagem e este acesso.',
      };
    case 'session-rejected':
      return {
        title: 'Caminho da sessão rejeitado',
        subtitle: 'O identificador não resolveu para um arquivo sob a raiz confinada de sessões.',
      };
    case 'sessions-root-missing':
      return {
        title: 'Raiz de sessões ausente',
        subtitle: '~/.claude/projects não foi encontrado neste host.',
      };
    case 'session-scrub-failed':
      return {
        title: 'Filtro de segredos indisponível',
        subtitle: 'O conteúdo não pôde ser exibido com segurança e foi bloqueado (nunca texto cru).',
      };
    default:
      return {
        title: 'Sessão indisponível no momento',
        subtitle: 'Tente novamente em instantes.',
      };
  }
}

/** Chave estavel de uma linha do tail — `uuid` quando presente, senao o indice. */
export function sessionEntryKey(entry: Pick<SessionTailEntryDTO, 'uuid'>, index: number): string {
  return entry.uuid ?? `entry-${index}`;
}

export function SessionDetail() {
  const { sessionId = '' } = useParams<{ sessionId: string }>();
  const query = useSessionTail(sessionId);
  const { isLoading, isError, errorMessage, isDegraded } = useApiState(query);

  if (isLoading) return <LoadingState variant="table" />;
  if (isError) return <ErrorState message={errorMessage ?? 'Erro ao carregar o transcript da sessão.'} />;

  const meta = query.data?.meta;
  const data = query.data?.data;

  if (isDegraded) {
    const copy = sessionDetailDegradedCopy(meta?.reason ?? null);
    return (
      <div className="col gap-4">
        {meta && <DegradedBanner meta={meta} />}
        <EmptyState title={copy.title} subtitle={copy.subtitle} />
      </div>
    );
  }

  const entries: SessionTailEntryDTO[] = data?.entries ?? [];

  return (
    <div className="col gap-4">
      <div className="page-head">
        <div>
          <h1>Sessão</h1>
          <div className="sub" style={{ fontFamily: 'var(--font-mono)' }}>{sessionId}</div>
        </div>
        <FreshnessLabel
          freshness={data ? { mtime: data.lastActivityAt, maxIngestedAt: data.lastActivityAt } : null}
        />
      </div>

      {/* Indicadores de estado do tail (live/skippedLines/windowTruncated) */}
      <div className="card">
        <div className="card-pad row gap-4" style={{ flexWrap: 'wrap' }}>
          <span
            style={{
              display: 'inline-flex', alignItems: 'center', gap: 5,
              fontSize: 11, fontWeight: 600,
              color: data?.live ? 'var(--success)' : 'var(--text-3)',
            }}
          >
            <span
              style={{
                width: 6, height: 6, borderRadius: '50%',
                background: data?.live ? 'var(--success)' : 'var(--text-3)',
                display: 'inline-block',
              }}
              aria-hidden
            />
            {data?.live ? 'ao vivo' : 'inativa'}
          </span>
          <span style={{ fontSize: 11, color: 'var(--text-2)' }}>
            {data?.returnedLines ?? 0} de {data?.requestedLines ?? 0} linhas solicitadas
          </span>
          {(data?.skippedLines ?? 0) > 0 && (
            <span style={{ fontSize: 11, color: 'var(--warning)' }}>
              {data?.skippedLines} linha(s) malformada(s) ignorada(s)
            </span>
          )}
          {data?.windowTruncated && (
            <span style={{ fontSize: 11, color: 'var(--text-2)' }} title="Existe historico anterior ao devolvido nesta janela">
              histórico truncado
            </span>
          )}
          {data?.truncatedByBytes && (
            <span style={{ fontSize: 11, color: 'var(--text-2)' }} title="Orcamento de bytes encerrou a selecao">
              corte por tamanho
            </span>
          )}
          <span style={{ marginLeft: 'auto', fontSize: 11, color: 'var(--text-2)' }} title={fmtTimestamp(data?.lastActivityAt)}>
            última atividade: {fmtRelative(data?.lastActivityAt)}
          </span>
        </div>
      </div>

      {/* Tail do transcript */}
      <div className="card">
        <div className="card-head"><h3>Transcript (tail)</h3></div>
        {entries.length === 0 ? (
          <EmptyState title="Sem linhas recentes" subtitle="O transcript desta sessão ainda não tem conteúdo útil." />
        ) : (
          <div className="card-pad col" style={{ gap: 12 }}>
            {entries.map((entry, idx) => (
              <div key={sessionEntryKey(entry, idx)} style={{ borderBottom: '1px solid var(--border)', paddingBottom: 10 }}>
                <div className="row gap-2" style={{ fontSize: 10.5, color: 'var(--text-2)', marginBottom: 4 }}>
                  <span style={{ fontFamily: 'var(--font-mono)' }}>{entry.type}</span>
                  {/* `role` so aparece quando ACRESCENTA informacao: a fonte
                      repete o papel no tipo (assistant/assistant, user/user) e
                      exibir os dois so gastava espaco. */}
                  {entry.role && entry.role !== entry.type && (
                    <span style={{ fontFamily: 'var(--font-mono)' }}>· {entry.role}</span>
                  )}
                  {entry.kind === 'tool_use' && entry.toolName && (
                    <span
                      className="mono"
                      style={{
                        fontSize: 10, fontWeight: 600, padding: '1px 6px', borderRadius: 4,
                        background: 'var(--inprogress-soft)', color: 'var(--inprogress)',
                      }}
                    >
                      {entry.toolName}
                    </span>
                  )}
                  {entry.timestamp && <span style={{ marginLeft: 'auto' }}>{fmtTimestamp(entry.timestamp)}</span>}
                </div>
                {/* tool_use sem resumo (input sem chave conhecida) nao rende
                    bloco de texto vazio — o nome da ferramenta no cabecalho ja
                    responde "o que a sessao esta fazendo". */}
                {entry.text !== '' && (
                  entry.kind === 'tool_result'
                    ? <div className="mono" style={{ fontSize: 11.5, color: 'var(--text-3)' }}>{entry.text}</div>
                    : <TextBlockRaw value={entry.text} />
                )}
                {entry.textTruncated && (
                  <div style={{ fontSize: 10, color: 'var(--text-3)', marginTop: 4 }}>[texto truncado]</div>
                )}
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
