/**
 * Sidebar — dark-mode-first, pixel-perfect do prototipo.
 * Suporta dois estados: expandido (232px) e colapsado (52px).
 * Ref: spec.md FR-007 a FR-016; plan.md §Sidebar.tsx
 */
import { useEffect, useState } from 'react';
import { Link, useLocation, useNavigate } from 'react-router-dom';
import { Icon } from './Icon.js';

interface NavRoute {
  id: string;
  label: string;
  icon: string;
  path: string;
  matchPrefix?: string[];
}

const ROUTES: NavRoute[] = [
  { id: 'overview', label: 'Visão Geral', icon: 'home', path: '/' },
  { id: 'projects', label: 'Projetos', icon: 'folder', path: '/projects' },
  { id: 'features', label: 'Features', icon: 'git-branch', path: '/features' },
  { id: 'executions', label: 'Execuções', icon: 'activity', path: '/executions' },
  { id: 'alerts', label: 'Alertas', icon: 'alert', path: '/alerts' },
  { id: 'metrics', label: 'Métricas', icon: 'bar', path: '/metrics' },
  { id: 'tasks', label: 'Tarefas', icon: 'check', path: '/tasks' },
  { id: 'incidents', label: 'Incidentes', icon: 'zap', path: '/incidents' },
  { id: 'memories', label: 'Memórias', icon: 'doc', path: '/memories' },
  { id: 'search', label: 'Busca de Conhecimento', icon: 'search', path: '/search' },
  { id: 'cheatsheet', label: 'Cheat Sheet', icon: 'help', path: '/cheatsheet' },
  { id: 'faq', label: 'FAQ', icon: 'faq', path: '/faq' },
];

function isRouteActive(route: NavRoute, pathname: string): boolean {
  if (route.path === '/') return pathname === '/';
  return pathname.startsWith(route.path);
}

interface SidebarProps {
  alertCount?: number;
  freshness?: { label: string; degraded: boolean };
  /** schema_version corrente da knowledge.db (vindo de /health). */
  schemaVersion?: string | undefined;
  /** Viewport mobile: a sidebar vira drawer off-canvas. */
  isMobile?: boolean;
  /** Drawer aberto (apenas mobile). */
  mobileOpen?: boolean;
  /** Fecha o drawer (chamado pelo backdrop e ao navegar no mobile). */
  onClose?: () => void;
}

type Theme = 'dark' | 'light';

export function Sidebar({
  alertCount = 0,
  freshness,
  schemaVersion,
  isMobile = false,
  mobileOpen = false,
  onClose,
}: SidebarProps) {
  const location = useLocation();
  const navigate = useNavigate();

  // Tema — persiste em localStorage e aplica data-theme no <html>.
  const [theme, setTheme] = useState<Theme>(
    () => (localStorage.getItem('cstk-theme') as Theme | null) ?? 'dark',
  );
  useEffect(() => {
    document.documentElement.dataset.theme = theme;
    localStorage.setItem('cstk-theme', theme);
  }, [theme]);

  // Estado de colapso — persistido em localStorage (FR-011).
  const [collapsed, setCollapsed] = useState<boolean>(
    () => localStorage.getItem('cstk-sidebar-collapsed') === 'true',
  );
  useEffect(() => {
    localStorage.setItem('cstk-sidebar-collapsed', String(collapsed));
  }, [collapsed]);

  const toggleCollapsed = () => setCollapsed((c) => !c);

  // No mobile a sidebar é drawer e sempre exibe o conteúdo expandido — a
  // preferência de colapso (localStorage) só vale no desktop.
  const drawerCollapsed = !isMobile && collapsed;

  // Navega e, no mobile, fecha o drawer em seguida.
  const go = (path: string) => {
    navigate(path);
    if (isMobile) onClose?.();
  };

  const cls = ['sidebar'];
  if (drawerCollapsed) cls.push('sidebar--collapsed');
  if (isMobile && mobileOpen) cls.push('sidebar--open');

  return (
    <aside className={cls.join(' ')}>
      {/* Brand — link para a Visao Geral (rota raiz); no mobile fecha o drawer
          como os demais itens de navegacao. */}
      <Link
        className="brand"
        to="/"
        title="Ir para a Visão Geral"
        aria-label="cstk-panel — ir para a Visão Geral"
        onClick={() => { if (isMobile) onClose?.(); }}
      >
        <img className="brand-logo" src="/cstk-logo.png" alt="" width={28} height={28} />
        {!drawerCollapsed && (
          <div>
            <div className="brand-name">cstk-panel</div>
            <div className="brand-tag">observabilidade · v{__APP_VERSION__}</div>
          </div>
        )}
      </Link>

      {/* Botão de colapso/expansão (FR-013, FR-016 — acessível).
          Oculto no mobile (em drawer não faz sentido recolher). */}
      <div
        className="sidebar-collapse-row"
        style={{ display: 'flex', justifyContent: drawerCollapsed ? 'center' : 'flex-end', padding: drawerCollapsed ? '4px 0' : '4px 10px' }}
      >
        <button
          className="ico-btn"
          onClick={toggleCollapsed}
          aria-label={drawerCollapsed ? 'Expandir menu' : 'Recolher menu'}
          aria-expanded={!drawerCollapsed}
          style={{ borderRadius: 'var(--r-sm)', padding: '6px' }}
        >
          <Icon
            name={drawerCollapsed ? 'chevron-right' : 'chevron-left'}
            size={14}
            aria-hidden
          />
        </button>
      </div>

      {/* Navigation */}
      <nav className="nav-section" aria-label="Navegacao principal">
        {!drawerCollapsed && <div className="nav-label">observar</div>}
        {ROUTES.slice(0, 4).map((route) => (
          <NavItem
            key={route.id}
            route={route}
            active={isRouteActive(route, location.pathname)}
            onClick={() => go(route.path)}
            collapsed={drawerCollapsed}
          />
        ))}

        {!drawerCollapsed && <div className="nav-label" style={{ marginTop: 12 }}>diagnosticar</div>}
        {ROUTES.slice(4).map((route) => (
          <NavItem
            key={route.id}
            route={route}
            active={isRouteActive(route, location.pathname)}
            onClick={() => go(route.path)}
            badge={route.id === 'alerts' && alertCount > 0 ? alertCount : undefined}
            collapsed={drawerCollapsed}
          />
        ))}
      </nav>

      {/* Footer: freshness + fonte de dados + tema */}
      <div className="sidebar-foot">
        {!drawerCollapsed && (
          <>
            <div className={`freshness-widget${freshness?.degraded ? ' degraded' : ''}`}>
              <span className="fresh-dot" />
              <div className="col" style={{ gap: 0, lineHeight: 1.3, flex: 1 }}>
                <span style={{ color: 'var(--text-1)', fontSize: 11.5 }}>
                  Indice atualizado{' '}
                  <span className="mono">{freshness?.label ?? '...'}</span>
                </span>
                <span className="mono" style={{ color: 'var(--text-3)', fontSize: 10 }}>
                  knowledge.db · schema v{schemaVersion ?? '—'}
                </span>
              </div>
            </div>
            <div className="row" style={{ justifyContent: 'space-between', marginTop: 10 }}>
              <span
                className="row gap-2"
                role="link"
                tabIndex={0}
                onClick={() => go('/source')}
                onKeyDown={(e) => e.key === 'Enter' && go('/source')}
                style={{ cursor: 'pointer', color: 'var(--text-2)', fontSize: 11 }}
              >
                <Icon name="database" size={12} aria-hidden />fonte de dados
              </span>
              <button
                className="ico-btn"
                onClick={() => setTheme(theme === 'dark' ? 'light' : 'dark')}
                title={theme === 'dark' ? 'Ativar tema claro' : 'Ativar tema escuro'}
                aria-label={theme === 'dark' ? 'Ativar tema claro' : 'Ativar tema escuro'}
              >
                <Icon name={theme === 'dark' ? 'sun' : 'moon'} size={12} aria-hidden />
              </button>
            </div>
          </>
        )}

        {/* Modo colapsado: apenas botão de toggle de tema (FR-014) */}
        {drawerCollapsed && (
          <div style={{ display: 'flex', justifyContent: 'center' }}>
            <button
              className="ico-btn"
              onClick={() => setTheme(theme === 'dark' ? 'light' : 'dark')}
              title={theme === 'dark' ? 'Ativar tema claro' : 'Ativar tema escuro'}
              aria-label={theme === 'dark' ? 'Ativar tema claro' : 'Ativar tema escuro'}
            >
              <Icon name={theme === 'dark' ? 'sun' : 'moon'} size={14} aria-hidden />
            </button>
          </div>
        )}
      </div>
    </aside>
  );
}

interface NavItemProps {
  route: NavRoute;
  active: boolean;
  onClick: () => void;
  badge?: number | undefined;
  collapsed?: boolean;
}

function NavItem({ route, active, onClick, badge, collapsed = false }: NavItemProps) {
  return (
    <div
      className={`nav-item${active ? ' active' : ''}`}
      onClick={onClick}
      role="link"
      tabIndex={0}
      onKeyDown={(e) => e.key === 'Enter' && onClick()}
      aria-current={active ? 'page' : undefined}
      data-tooltip={collapsed ? route.label : undefined}
    >
      <Icon name={route.icon} size={15} className="ico" />
      {!collapsed && <span>{route.label}</span>}
      {!collapsed && badge != null && badge > 0 && (
        <span className="nav-badge" aria-label={`${badge} alertas criticos`}>
          {badge}
        </span>
      )}
    </div>
  );
}
