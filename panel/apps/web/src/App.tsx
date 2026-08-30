/**
 * App — shell principal: Sidebar 232px + Topbar + area de conteudo.
 * HashRouter configurado em main.tsx; rotas aqui via React Router v6 Routes.
 *
 * Layout pixel-perfect do prototipo:
 *  grid: 232px sidebar | 1fr main
 *  main: topbar sticky 52px + conteudo scrollavel
 *
 * Ref: spec.md FR-021, FR-022; tasks.md §5.1, §5.2, §6
 */
import { useEffect, useState } from 'react';
import { Routes, Route } from 'react-router-dom';
import { Sidebar } from '@/components/Sidebar.js';
import { Topbar } from '@/components/Topbar.js';
import { useMediaQuery } from '@/hooks/useMediaQuery.js';
import { Overview } from '@/screens/Overview.js';
import { ExecutionDetail } from '@/screens/ExecutionDetail.js';
import { DecisionMapScreen } from '@/screens/DecisionMapScreen.js';
import { Executions } from '@/screens/Executions.js';
import { Search } from '@/screens/Search.js';
import { Alerts } from '@/screens/Alerts.js';
import { Metrics } from '@/screens/Metrics.js';
import { Projects } from '@/screens/Projects.js';
import { ProjectDetail } from '@/screens/ProjectDetail.js';
import { Features } from '@/screens/Features.js';
import { FeatureDetail } from '@/screens/FeatureDetail.js';
import { Tasks } from '@/screens/Tasks.js';
import { Incidents } from '@/screens/Incidents.js';
import { Memories } from '@/screens/Memories.js';
import { Source } from '@/screens/Source.js';
import { Sessions } from '@/screens/Sessions.js';
import { SessionDetail } from '@/screens/SessionDetail.js';
import { Interventions } from '@/screens/Interventions.js';
import { CheatSheet } from '@/screens/CheatSheet.js';
import { Faq } from '@/screens/Faq.js';
import { Placeholder } from '@/screens/Placeholder.js';
import { useHealth, useAlerts } from '@/lib/hooks.js';
import { fmtRelative } from '@/lib/format.js';
import type { PeriodParam, AlertSignalDTO } from '@cstk-panel/shared-types';

// Periodo global — compartilhado entre telas (elevado ao App)
type Period = PeriodParam;

export default function App() {
  const [period, setPeriod] = useState<Period>('7d');
  // FR-022: filtro global de projeto (controla as métricas do dashboard).
  // '' = todos os projetos.
  const [projectFilter, setProjectFilter] = useState('');

  // Layout responsivo: abaixo de 768px a sidebar vira drawer off-canvas.
  const isMobile = useMediaQuery('(max-width: 768px)');
  const [navOpen, setNavOpen] = useState(false);
  // Fecha o drawer com Esc quando aberto no mobile.
  useEffect(() => {
    if (!isMobile || !navOpen) return;
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && setNavOpen(false);
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [isMobile, navOpen]);

  // Frescor + contagem de alertas criticos para a Sidebar (CARD-SHELL-03).
  const healthQ = useHealth();
  const alertsQ = useAlerts({ period });
  const fresh = healthQ.data?.meta?.freshness;
  const freshness = {
    label: fmtRelative(fresh?.maxIngestedAt || fresh?.mtime),
    degraded: healthQ.data?.meta?.degraded ?? false,
  };
  const alertItems: AlertSignalDTO[] = alertsQ.data?.data?.alerts ?? [];
  const alertCount = alertItems.filter((a) =>
    a.consumedValue != null && a.thresholdValue != null && a.thresholdValue > 0
      ? a.consumedValue / a.thresholdValue >= 1
      : false,
  ).length;

  return (
    <div className="app">
      {/* Sidebar 232px fixo (desktop) / drawer off-canvas (mobile) */}
      <Sidebar
        alertCount={alertCount}
        freshness={freshness}
        schemaVersion={healthQ.data?.meta?.schemaVersion}
        isMobile={isMobile}
        mobileOpen={navOpen}
        onClose={() => setNavOpen(false)}
      />

      {/* Backdrop do drawer (apenas mobile, quando aberto) */}
      {isMobile && navOpen && (
        <div className="nav-backdrop" onClick={() => setNavOpen(false)} aria-hidden="true" />
      )}

      {/* Area principal */}
      <div className="main">
        {/* Topbar sticky 52px */}
        <Topbar
          period={period}
          onPeriodChange={setPeriod}
          projectFilter={projectFilter}
          onProjectFilterChange={setProjectFilter}
          onMenuClick={() => setNavOpen(true)}
        />

        {/* Conteudo das rotas */}
        <main className="content">
          <Routes>
            {/* Rota raiz — Visao Geral (US1) */}
            <Route path="/" element={<Overview period={period} project={projectFilter} />} />

            {/* Projetos */}
            <Route path="/projects" element={<Projects />} />
            <Route path="/projects/:project" element={<ProjectDetail />} />

            {/* Features */}
            <Route path="/features" element={<Features />} />
            <Route path="/features/:project/:feature" element={<FeatureDetail />} />

            {/* Execucoes (US2) */}
            <Route path="/executions" element={<Executions />} />
            <Route path="/executions/:execucaoId" element={<ExecutionDetail />} />
            <Route path="/executions/:execucaoId/decision-map" element={<DecisionMapScreen />} />

            {/* Alertas (US4) */}
            <Route path="/alerts" element={<Alerts period={period} />} />

            {/* Metricas (US5) */}
            <Route path="/metrics" element={<Metrics period={period} />} />

            {/* Tarefas e Incidentes (cross-execucao) */}
            <Route path="/tasks" element={<Tasks />} />
            <Route path="/incidents" element={<Incidents />} />

            {/* Memorias (auto-memorias do Claude Code, schema v4) */}
            <Route path="/memories" element={<Memories />} />

            {/* Sessoes do Claude Code (session-tail, US1/US2) */}
            <Route path="/sessions" element={<Sessions />} />
            <Route path="/sessions/:sessionId" element={<SessionDetail />} />

            {/* Ponte de intervencao humana (human-bridge, US1/US2) */}
            <Route path="/interventions" element={<Interventions />} />

            {/* Busca FTS5 (US3) */}
            <Route path="/search" element={<Search />} />

            {/* Fonte de dados */}
            <Route path="/source" element={<Source />} />

            {/* Cheat sheet do CLI (conteudo estatico) */}
            <Route path="/cheatsheet" element={<CheatSheet />} />

            {/* FAQ passo-a-passo (conteudo estatico) */}
            <Route path="/faq" element={<Faq />} />

            {/* Fallback */}
            <Route path="*" element={<Placeholder title="Pagina nao encontrada" description="A rota solicitada nao existe." />} />
          </Routes>
        </main>
      </div>
    </div>
  );
}
