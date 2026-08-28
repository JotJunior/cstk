/**
 * StatusBadge — enum status de execucao com cor semantica.
 * Tipos vem de ExecutionDTO.status — nao redefine DTO localmente.
 */
import type { ExecutionDTO } from '@cstk-panel/shared-types';

type Status = NonNullable<ExecutionDTO['status']>;

const STATUS_LABEL: Record<Status, string> = {
  em_andamento: 'em andamento',
  aguardando_humano: 'aguardando humano',
  concluida: 'concluida',
  abortada: 'abortada',
};

interface StatusBadgeProps {
  status: Status | null;
}

export function StatusBadge({ status }: StatusBadgeProps) {
  if (!status) return <span className="badge" style={{ color: 'var(--text-2)' }}>-</span>;
  return (
    <span className={`badge ${status}`}>
      <span className="dot" aria-hidden />
      {STATUS_LABEL[status] ?? status}
    </span>
  );
}
