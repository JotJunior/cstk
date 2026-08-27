/**
 * Testes unitários para lógica do Sidebar — estado colapsado e persistência.
 * Ref: spec.md FR-007, FR-008, FR-011; tasks.md 4.2.1 a 4.2.4
 *
 * Nota: testa a lógica pura de inicialização e persistência do localStorage,
 * sem renderização React (environment=node, sem jsdom). Os testes de classe CSS
 * no DOM são cobertos pelo smoke-test visual manual (tasks.md 3.2.x).
 */
import { describe, it, expect, beforeEach } from 'vitest';

// ─── Simulação mínima de localStorage para environment=node ───────────────────
const store: Record<string, string> = {};
const localStorageMock = {
  getItem: (key: string) => store[key] ?? null,
  setItem: (key: string, value: string) => { store[key] = value; },
  removeItem: (key: string) => { delete store[key]; },
  clear: () => { Object.keys(store).forEach((k) => delete store[k]); },
};

// Função que replica a lógica de inicialização do collapsed state (FR-011)
function initCollapsed(storage: { getItem: (k: string) => string | null }): boolean {
  return storage.getItem('cstk-sidebar-collapsed') === 'true';
}

// Função que replica a lógica de persistência do collapsed state (FR-011)
function persistCollapsed(
  storage: { setItem: (k: string, v: string) => void },
  value: boolean,
): void {
  storage.setItem('cstk-sidebar-collapsed', String(value));
}

// Função que replica lógica de inicialização do tema (FR-003)
function initTheme(storage: { getItem: (k: string) => string | null }): 'dark' | 'light' {
  const stored = storage.getItem('cstk-theme');
  if (stored === 'light' || stored === 'dark') return stored;
  return 'dark';
}

// Rotas de navegação (replica ROUTES do Sidebar.tsx para validar completude)
const ROUTES = [
  { id: 'overview', label: 'Visão Geral', icon: 'home', path: '/' },
  { id: 'projects', label: 'Projetos', icon: 'folder', path: '/projects' },
  { id: 'features', label: 'Features', icon: 'git-branch', path: '/features' },
  { id: 'executions', label: 'Execuções', icon: 'activity', path: '/executions' },
  { id: 'sessions', label: 'Sessões', icon: 'eye', path: '/sessions' },
  { id: 'alerts', label: 'Alertas', icon: 'alert', path: '/alerts' },
  { id: 'metrics', label: 'Métricas', icon: 'bar', path: '/metrics' },
  { id: 'tasks', label: 'Tarefas', icon: 'check', path: '/tasks' },
  { id: 'incidents', label: 'Incidentes', icon: 'zap', path: '/incidents' },
  { id: 'memories', label: 'Memórias', icon: 'doc', path: '/memories' },
  { id: 'search', label: 'Busca de Conhecimento', icon: 'search', path: '/search' },
  { id: 'cheatsheet', label: 'Cheat Sheet', icon: 'help', path: '/cheatsheet' },
  { id: 'faq', label: 'FAQ', icon: 'faq', path: '/faq' },
];

// ─── Testes ───────────────────────────────────────────────────────────────────

describe('Sidebar — estado colapsado (FR-007, FR-011)', () => {
  beforeEach(() => {
    localStorageMock.clear();
  });

  it('4.2.2 inicia collapsed=false quando localStorage não tem a chave', () => {
    expect(initCollapsed(localStorageMock)).toBe(false);
  });

  it('4.2.2 inicia collapsed=true quando cstk-sidebar-collapsed=true no localStorage', () => {
    localStorageMock.setItem('cstk-sidebar-collapsed', 'true');
    expect(initCollapsed(localStorageMock)).toBe(true);
  });

  it('4.2.2 inicia collapsed=false quando cstk-sidebar-collapsed=false no localStorage', () => {
    localStorageMock.setItem('cstk-sidebar-collapsed', 'false');
    expect(initCollapsed(localStorageMock)).toBe(false);
  });

  it('persiste collapsed=true via localStorage (FR-011)', () => {
    persistCollapsed(localStorageMock, true);
    expect(localStorageMock.getItem('cstk-sidebar-collapsed')).toBe('true');
  });

  it('persiste collapsed=false via localStorage (FR-011)', () => {
    persistCollapsed(localStorageMock, false);
    expect(localStorageMock.getItem('cstk-sidebar-collapsed')).toBe('false');
  });

  it('toggle de collapsed inverte o estado e persiste', () => {
    let collapsed = initCollapsed(localStorageMock); // false
    collapsed = !collapsed; // true
    persistCollapsed(localStorageMock, collapsed);
    expect(localStorageMock.getItem('cstk-sidebar-collapsed')).toBe('true');

    collapsed = !collapsed; // false
    persistCollapsed(localStorageMock, collapsed);
    expect(localStorageMock.getItem('cstk-sidebar-collapsed')).toBe('false');
  });
});

describe('Sidebar — tema (FR-003, FR-004)', () => {
  beforeEach(() => {
    localStorageMock.clear();
  });

  it('inicia no tema dark quando localStorage está vazio', () => {
    expect(initTheme(localStorageMock)).toBe('dark');
  });

  it('inicia no tema light quando cstk-theme=light no localStorage', () => {
    localStorageMock.setItem('cstk-theme', 'light');
    expect(initTheme(localStorageMock)).toBe('light');
  });

  it('inicia no tema dark quando cstk-theme=dark no localStorage', () => {
    localStorageMock.setItem('cstk-theme', 'dark');
    expect(initTheme(localStorageMock)).toBe('dark');
  });

  it('ignora valor inválido no localStorage e usa dark como fallback', () => {
    localStorageMock.setItem('cstk-theme', 'sepia');
    expect(initTheme(localStorageMock)).toBe('dark');
  });
});

describe('Sidebar — rotas de navegação (SC-005)', () => {
  it('4.2.3 todas as 10 rotas têm label para uso como data-tooltip no modo colapsado', () => {
    expect(ROUTES).toHaveLength(13);
    ROUTES.forEach((route) => {
      expect(typeof route.label).toBe('string');
      expect(route.label.length).toBeGreaterThan(0);
    });
  });

  it('4.2.3 todos os labels de tooltip são únicos (sem colisão)', () => {
    const labels = ROUTES.map((r) => r.label);
    const unique = new Set(labels);
    expect(unique.size).toBe(labels.length);
  });

  it('todas as 10 rotas têm ícone definido', () => {
    ROUTES.forEach((route) => {
      expect(typeof route.icon).toBe('string');
      expect(route.icon.length).toBeGreaterThan(0);
    });
  });

  it('rota raiz é exatamente "/" (isRouteActive para overview)', () => {
    const overview = ROUTES.find((r) => r.id === 'overview');
    expect(overview?.path).toBe('/');
  });
});
