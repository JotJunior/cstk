/**
 * PipelineProgress — barra de progresso das 10 etapas SDD.
 * Portado do prototipo: modo compacto (.pipeline) e rotulado (.pipeline-labeled).
 * Ref: docs/06-ui-ux-design/castk-panel/project/components.jsx
 */
import { SDD_STAGES } from '@/lib/constants.js';

export type Status = 'em_andamento' | 'aguardando_humano' | 'concluida' | 'abortada' | null;

/** Estado visual de uma etapa. 'idle' = ainda nao alcancada (cinza). */
export type StageState = 'done' | 'current' | 'aborted' | 'idle';

/**
 * Classifica cada uma das 10 etapas SDD para um dado (etapa, status).
 * Fonte unica consumida pelos dois modos de render (compacto e rotulado).
 *
 * Nota: execucoes terminais gravam etapa='concluida'/'abortada', marcadores
 * FORA de SDD_STAGES — logo idx=-1. Por isso a decisao acende pelo STATUS,
 * nao pelo indice da etapa. O status ja chega normalizado do servidor
 * (mappers/status.ts: 'concluido'→'concluida'), entao comparar com 'concluida'
 * e seguro.
 */
export function stageStates(etapa: string | null, status: Status): StageState[] {
  const idx = etapa ? (SDD_STAGES as readonly string[]).indexOf(etapa) : -1;
  return SDD_STAGES.map((_, i) => {
    if (status === 'concluida') return 'done';
    if (status === 'abortada') return i >= idx ? 'aborted' : 'done';
    if (i < idx) return 'done';
    if (i === idx) return 'current';
    return 'idle';
  });
}

interface PipelineProgressProps {
  etapa: string | null;
  status: Status;
  labeled?: boolean;
}

export function PipelineProgress({ etapa, status, labeled = false }: PipelineProgressProps) {
  const states = stageStates(etapa, status);

  if (labeled) {
    return (
      <div className="pipeline-labeled">
        {SDD_STAGES.map((st, i) => {
          const state = states[i];
          const cls = state === 'idle' ? '' : ` ${state}`;
          return (
            <div key={st} className={`stage${cls}`}>
              <div className="bar" />
              <div className="label" style={{ whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{st}</div>
            </div>
          );
        })}
      </div>
    );
  }

  return (
    <div className="pipeline">
      {SDD_STAGES.map((st, i) => {
        const state = states[i];
        const cls = state === 'idle' ? '' : state;
        return <div key={st} className={`step ${cls}`} title={st} />;
      })}
    </div>
  );
}
