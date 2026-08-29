/**
 * Filtro client-side de features (CARD-PRJ-03 / CARD-FT-02).
 * Reusado por Projetos e Features. Filtra por texto (feature/projeto),
 * projeto exato e status exato. Campos vazios ('') significam "todos".
 */

export type FeatureStatus = 'em_andamento' | 'aguardando_humano' | 'concluida' | 'abortada' | null;

export interface FeatureFilterState {
  q: string;
  project: string;
  status: string;
}

export const EMPTY_FEATURE_FILTER: FeatureFilterState = { q: '', project: '', status: '' };

/** Opcoes do select de status (alinhado ao prototipo). */
export const STATUS_OPTIONS: { value: string; label: string }[] = [
  { value: '', label: 'Todos os status' },
  { value: 'em_andamento', label: 'em_andamento' },
  { value: 'concluida', label: 'concluida' },
  { value: 'aguardando_humano', label: 'aguardando_humano' },
  { value: 'abortada', label: 'abortada' },
];

interface FilterableFeature {
  project: string;
  feature: string;
  latestStatus?: FeatureStatus;
}

export function filterFeatures<T extends FilterableFeature>(
  items: T[],
  { q, project, status }: FeatureFilterState,
): T[] {
  const needle = q.trim().toLowerCase();
  return items.filter((f) => {
    if (project && f.project !== project) return false;
    if (status && (f.latestStatus ?? '') !== status) return false;
    if (needle) {
      const hay = `${f.feature} ${f.project}`.toLowerCase();
      if (!hay.includes(needle)) return false;
    }
    return true;
  });
}

/** Lista ordenada e distinta de projetos a partir das features. */
export function distinctProjects<T extends { project: string }>(items: T[]): string[] {
  return Array.from(new Set(items.map((f) => f.project))).sort();
}
