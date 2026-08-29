/**
 * Features — tabela de todas as features cross-project.
 * Layout do prototipo (screens_main.jsx · FeaturesListScreen).
 * Filtros (busca + projeto + status): CARD-FT-02.
 */
import { useState } from 'react';
import { useFeatures } from '@/lib/hooks.js';
import { useApiState } from '@/hooks/useApiState.js';
import { LoadingState, EmptyState, ErrorState } from '@/states/index.js';
import { FeaturesTable } from '@/components/FeaturesTable.js';
import { FeaturesFilterBar } from '@/components/FeaturesFilterBar.js';
import { filterFeatures, distinctProjects, EMPTY_FEATURE_FILTER } from '@/lib/features-filter.js';
import type { FeatureRollup } from '@cstk-panel/shared-types';

export function Features() {
  const query = useFeatures();
  const { isLoading, isError, errorMessage, isEmpty } = useApiState(query);
  const [filter, setFilter] = useState(EMPTY_FEATURE_FILTER);

  if (isLoading) return <LoadingState variant="kpi" />;
  if (isError) return <ErrorState message={errorMessage ?? 'Erro ao carregar features.'} />;
  if (isEmpty) return <EmptyState title="Nenhuma feature" subtitle="Execute o orquestrador para ver dados aqui." />;

  const features = (query.data?.data ?? []) as FeatureRollup[];
  const visible = filterFeatures(features, filter);

  return (
    <div className="col gap-4">
      <div className="page-head">
        <div>
          <h1>Features</h1>
          <div className="sub">{features.length} features · todas, cross-project</div>
        </div>
      </div>

      <div className="card">
        <div className="card-head">
          <h3>Features · todas</h3>
          <FeaturesFilterBar
            state={filter}
            onChange={setFilter}
            projects={distinctProjects(features)}
          />
        </div>
        <FeaturesTable features={visible} />
      </div>
    </div>
  );
}
