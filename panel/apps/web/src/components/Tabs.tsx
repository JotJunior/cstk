/**
 * Tabs — abas com contador opcional. Portado do prototipo (.tabs).
 */
export interface TabItem { value: string; label: string; count?: number | null; }

interface TabsProps {
  items: TabItem[];
  value: string;
  onChange: (value: string) => void;
}

export function Tabs({ items, value, onChange }: TabsProps) {
  return (
    <div className="tabs" role="tablist">
      {items.map(it => (
        <button
          key={it.value}
          role="tab"
          aria-selected={value === it.value}
          className={value === it.value ? 'active' : ''}
          onClick={() => onChange(it.value)}
        >
          {it.label}
          {it.count != null && <span className="count">{it.count}</span>}
        </button>
      ))}
    </div>
  );
}
