/**
 * FreshnessLabel — exibe mtime/maxIngestedAt formatado como "ha Xm".
 * Ref: spec.md FR-014; data-model.md §Freshness
 */
import type { Freshness } from '@cstk-panel/shared-types';

interface FreshnessLabelProps {
  freshness: Freshness | undefined | null;
  /** Se true, usa mtime; se false, usa maxIngestedAt */
  useIngested?: boolean;
}

function fmtRelative(iso: string): string {
  const diff = (Date.now() - new Date(iso).getTime()) / 1000;
  if (diff < 60) return 'agora';
  if (diff < 3600) return `ha ${Math.floor(diff / 60)}m`;
  if (diff < 86400) return `ha ${Math.floor(diff / 3600)}h`;
  return `ha ${Math.floor(diff / 86400)}d`;
}

export function FreshnessLabel({ freshness, useIngested = false }: FreshnessLabelProps) {
  if (!freshness) return <span className="freshness-label muted-2">-</span>;
  const iso = useIngested ? freshness.maxIngestedAt : freshness.mtime;
  if (!iso) return <span className="freshness-label muted-2">-</span>;
  return (
    <span className="freshness-label" title={iso}>
      {fmtRelative(iso)}
    </span>
  );
}
