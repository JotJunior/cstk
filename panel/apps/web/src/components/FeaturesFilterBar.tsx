/**
 * FeaturesFilterBar — controles de filtro da tabela de features
 * (busca + select de projeto + select de status). Portado do prototipo
 * (screens_main.jsx · ProjectsScreen / FeaturesListScreen card-head).
 * Controlado: o estado vive na tela; aqui so renderiza e emite onChange.
 */
import {
  STATUS_OPTIONS,
  type FeatureFilterState,
} from '@/lib/features-filter.js';

interface Props {
  state: FeatureFilterState;
  onChange: (next: FeatureFilterState) => void;
  /** Projetos distintos para o select; ocultar quando a tela ja e de um unico projeto. */
  projects?: string[];
}

export function FeaturesFilterBar({ state, onChange, projects }: Props) {
  return (
    <div className="row gap-2">
      <input
        className="input"
        style={{ width: 200 }}
        placeholder="Buscar feature…"
        aria-label="Buscar feature"
        value={state.q}
        onChange={(e) => onChange({ ...state, q: e.target.value })}
      />
      {projects && projects.length > 0 && (
        <select
          className="select"
          aria-label="Filtrar por projeto"
          value={state.project}
          onChange={(e) => onChange({ ...state, project: e.target.value })}
        >
          <option value="">Todos os projetos</option>
          {projects.map((p) => (
            <option key={p} value={p}>{p}</option>
          ))}
        </select>
      )}
      <select
        className="select"
        aria-label="Filtrar por status"
        value={state.status}
        onChange={(e) => onChange({ ...state, status: e.target.value })}
      >
        {STATUS_OPTIONS.map((s) => (
          <option key={s.value} value={s.value}>{s.label}</option>
        ))}
      </select>
    </div>
  );
}
