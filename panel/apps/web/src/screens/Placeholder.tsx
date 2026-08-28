/**
 * Placeholder — tela generica para rotas ainda nao implementadas.
 * Substituido por telas reais na FASE 6.
 */
interface PlaceholderProps {
  title: string;
  description?: string;
}

export function Placeholder({ title, description }: PlaceholderProps) {
  return (
    <div className="card">
      <div className="card-head">
        <h3>{title}</h3>
      </div>
      <div className="card-body empty-state">
        <div className="empty-title">{title}</div>
        <div className="empty-sub">
          {description ?? 'Implementado na FASE 6.'}
        </div>
      </div>
    </div>
  );
}
