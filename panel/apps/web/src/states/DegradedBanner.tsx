/**
 * DegradedBanner — banner de degradacao de 1a classe (US6, FR-006).
 * Aparece quando meta.degraded=true. Exibe reason + freshness.
 * NUNCA usa dangerouslySetInnerHTML.
 */
import type { Meta } from '@cstk-panel/shared-types';

interface DegradedBannerProps {
  meta: Meta;
}

const REASON_LABELS: Record<string, string> = {
  'db-missing': 'base de dados ausente',
  'db-corrupt': 'base de dados corrompida',
  'schema-mismatch': 'versao de schema incompativel',
  'table-empty': 'tabela vazia',
  // Doc-viewer (state-watchers-and-docs, FASE 3) — degradacao por caminho
  // de projeto, nao pela knowledge.db (artefatos vem do filesystem).
  'project-path-unresolved': 'caminho do projeto não configurado',
  'project-path-inaccessible': 'caminho do projeto inacessível',
  // Session Tail (feature session-tail, FASE 6) — degradacoes de
  // GET /sessions e GET /sessions/:sessionId/tail.
  'sessions-root-missing': 'raiz de sessões (~/.claude/projects) ausente',
  'sessions-root-unreadable': 'raiz de sessões sem permissão de leitura',
  'session-not-found': 'sessão não encontrada',
  'session-rejected': 'caminho da sessão rejeitado (fora da raiz confinada)',
  'session-scrub-failed': 'filtro de segredos indisponível — conteúdo não pôde ser exibido',
};

function fmtRelative(iso: string): string {
  const diff = (Date.now() - new Date(iso).getTime()) / 1000;
  if (diff < 60) return 'agora';
  if (diff < 3600) return `ha ${Math.floor(diff / 60)}m`;
  if (diff < 86400) return `ha ${Math.floor(diff / 3600)}h`;
  return `ha ${Math.floor(diff / 86400)}d`;
}

export function DegradedBanner({ meta }: DegradedBannerProps) {
  if (!meta.degraded) return null;

  const reasonLabel = meta.reason
    ? (REASON_LABELS[meta.reason] ?? meta.reason)
    : 'degradado';

  const freshnessStr = meta.freshness?.mtime
    ? fmtRelative(meta.freshness.mtime)
    : '?';

  return (
    <div className="degraded-banner" role="alert" aria-live="polite">
      <svg
        className="dg-icon"
        width={16}
        height={16}
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth={2}
        strokeLinecap="round"
        strokeLinejoin="round"
        aria-hidden
      >
        <path d="M10.3 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z" />
        <line x1="12" y1="9" x2="12" y2="13" />
        <line x1="12" y1="17" x2="12.01" y2="17" />
      </svg>
      <span>
        Base degradada &mdash;{' '}
        <span className="dg-reason">{reasonLabel}</span>
      </span>
      <span className="dg-fresh">
        snapshot: {freshnessStr}
      </span>
    </div>
  );
}
