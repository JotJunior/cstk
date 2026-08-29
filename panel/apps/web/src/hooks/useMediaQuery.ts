/**
 * useMediaQuery — retorna `true` enquanto a media query bate; reavalia em resize.
 * Client-only (o painel roda 100% no browser). Usado para alternar entre o
 * layout desktop (sidebar fixa) e o mobile (sidebar em drawer off-canvas).
 */
import { useEffect, useState } from 'react';

export function useMediaQuery(query: string): boolean {
  const [matches, setMatches] = useState<boolean>(
    () => typeof window !== 'undefined' && window.matchMedia(query).matches,
  );

  useEffect(() => {
    const mql = window.matchMedia(query);
    const onChange = () => setMatches(mql.matches);
    onChange();
    mql.addEventListener('change', onChange);
    return () => mql.removeEventListener('change', onChange);
  }, [query]);

  return matches;
}
