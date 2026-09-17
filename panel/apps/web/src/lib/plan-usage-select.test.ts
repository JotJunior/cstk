/**
 * plan-usage-select — view-model do gauge de PLANO (schema v14, `plan_usage`,
 * cstk 7.2.0).
 *
 * O que se trava aqui (Principio III — Honestidade de Metrica):
 * - os 3 estados nao colapsam: `degraded` (base v<14, tabela ausente),
 *   `empty` (tabela presente, hook de statusline nao instalado) e `measured`;
 * - `usedPercentage` null renderiza "não medido", JAMAIS "0%" — ausencia de
 *   leitura e plano intocado sao afirmacoes diferentes sobre a conta;
 * - `0` medido sobrevive como "0.0%", nao vira "não medido";
 * - as duas janelas ficam separadas e na ordem canonica (5h antes de 7d);
 * - escopo desconhecido (o cstk pode adicionar outro) aparece no fim em vez de
 *   sumir da tela;
 * - `resetsAt` e epoch em SEGUNDOS e o "agora" e INJETADO (funcao pura).
 */
import { describe, it, expect } from 'vitest';
import {
  selectPlanUsage, seriesForScope, fmtPlanPct, fmtResetsIn,
  planUsageBand, planUsageCoverageLabel, scopeLabel, tightestScope,
  shortScopeLabel, planUsageCapture, fmtCaptureAge, CAPTURE_AGING_FACTOR,
} from '@/lib/plan-usage-select.js';
import type { PlanUsageResult, PlanUsagePoint, PlanUsageScopeState } from '@cstk-panel/shared-types';

const COVERAGE_MEASURED = {
  rowsTotal: 4, scopes: 2, sessions: 2, projects: 1,
  firstCapturedAt: '2026-08-10T09:00:00Z', lastCapturedAt: '2026-08-10T13:00:00Z',
};

const MEASURED: PlanUsageResult = {
  byScope: [
    {
      scope: 'seven_day', usedPercentage: 43, resetsAt: 1786400000,
      capturedAt: '2026-08-10T13:00:00Z', peakUsedPercentage: 43, captures: 2,
    },
    {
      scope: 'five_hour', usedPercentage: 91.5, resetsAt: 1786000000,
      capturedAt: '2026-08-10T13:00:00Z', peakUsedPercentage: 95, captures: 2,
    },
  ],
  series: [
    { scope: 'five_hour', capturedAt: '2026-08-10T09:00:00Z', usedPercentage: 10 },
    { scope: 'five_hour', capturedAt: '2026-08-10T13:00:00Z', usedPercentage: 91.5 },
    { scope: 'seven_day', capturedAt: '2026-08-10T13:00:00Z', usedPercentage: 43 },
  ],
  coverage: COVERAGE_MEASURED,
  seriesTruncated: false,
};

describe('selectPlanUsage — estados', () => {
  it('data ausente (base v<14) vira degraded, nao empty', () => {
    const vm = selectPlanUsage(null);
    // rowsTotal null so acontece no caminho `table-empty` do servidor.
    expect(vm.state).toBe('degraded');
    expect(vm.byScope).toEqual([]);
    expect(vm.coverage.rowsTotal).toBeNull();
  });

  it('tabela presente e vazia vira empty (hook opt-in desligado)', () => {
    const vm = selectPlanUsage({
      byScope: [], series: [], seriesTruncated: false,
      coverage: { rowsTotal: 0, scopes: 0, sessions: 0, projects: 0, firstCapturedAt: null, lastCapturedAt: null },
    });
    // A distincao importa: "base velha" e "captura nao ligada" pedem instrucoes
    // diferentes na tela.
    expect(vm.state).toBe('empty');
  });

  it('com capturas vira measured', () => {
    expect(selectPlanUsage(MEASURED).state).toBe('measured');
  });
});

describe('selectPlanUsage — ordenacao dos escopos', () => {
  it('janela curta primeiro, mesmo quando a origem devolve fora de ordem', () => {
    const vm = selectPlanUsage(MEASURED);
    expect(vm.byScope.map(s => s.scope)).toEqual(['five_hour', 'seven_day']);
  });

  it('escopo desconhecido vai para o fim, nunca e descartado', () => {
    const vm = selectPlanUsage({
      ...MEASURED,
      byScope: [
        { scope: 'thirty_day', usedPercentage: 5, resetsAt: null, capturedAt: null, peakUsedPercentage: 5, captures: 1 },
        ...MEASURED.byScope,
      ],
    });
    expect(vm.byScope.map(s => s.scope)).toEqual(['five_hour', 'seven_day', 'thirty_day']);
  });

  it('escopo sem rotulo conhecido exibe o identificador bruto', () => {
    expect(scopeLabel('five_hour')).toBe('Janela de 5 horas');
    expect(scopeLabel('thirty_day')).toBe('thirty_day');
  });
});

describe('seriesForScope', () => {
  it('separa as janelas — nunca mistura as duas series', () => {
    const vm = selectPlanUsage(MEASURED);
    expect(seriesForScope(vm.series, 'five_hour')).toHaveLength(2);
    expect(seriesForScope(vm.series, 'seven_day')).toHaveLength(1);
  });
});

describe('fmtPlanPct', () => {
  it('null vira "não medido", jamais 0%', () => {
    expect(fmtPlanPct(null)).toBe('não medido');
    expect(fmtPlanPct(undefined)).toBe('não medido');
  });

  it('0 medido sobrevive como 0.0%', () => {
    // Regressao do Principio III: um `|| 'não medido'` colapsaria 0 em ausencia.
    expect(fmtPlanPct(0)).toBe('0.0%');
  });

  it('arredonda so na exibicao (a origem grava sem arredondar)', () => {
    // Valor com ruido de float, como o cstk persiste vindo do payload.
    expect(fmtPlanPct(7.000000000000001)).toBe('7.0%');
    expect(fmtPlanPct(91.53)).toBe('91.5%');
  });
});

describe('fmtResetsIn', () => {
  const NOW_MS = 1786000000 * 1000; // instante fixo; a funcao nunca le o relogio

  it('null vira "—", sem inventar prazo', () => {
    expect(fmtResetsIn(null, NOW_MS)).toBe('—');
  });

  it('reset no passado e "expirado", nao 0%', () => {
    // A janela virou mas ninguem capturou ainda; fabricar "0%" seria mentir.
    expect(fmtResetsIn(1786000000 - 60, NOW_MS)).toBe('expirado');
  });

  it('formata horas e minutos restantes', () => {
    expect(fmtResetsIn(1786000000 + 3600 + 1800, NOW_MS)).toBe('em 1h 30m');
    expect(fmtResetsIn(1786000000 + 600, NOW_MS)).toBe('em 10m');
  });

  it('acima de 24h usa dias (janela de 7 dias)', () => {
    expect(fmtResetsIn(1786000000 + 2 * 86400 + 3 * 3600, NOW_MS)).toBe('em 2d 3h');
  });
});

describe('planUsageBand', () => {
  it('null nao tem faixa — nao existe "verde por falta de medicao"', () => {
    expect(planUsageBand(null)).toBe('none');
  });

  it('faixas por severidade da cota', () => {
    expect(planUsageBand(0)).toBe('ok');
    expect(planUsageBand(69.9)).toBe('ok');
    expect(planUsageBand(70)).toBe('warn');
    expect(planUsageBand(89.9)).toBe('warn');
    expect(planUsageBand(90)).toBe('critical');
    expect(planUsageBand(100)).toBe('critical');
  });
});

describe('planUsageCoverageLabel', () => {
  it('base sem a tabela e explicito sobre a fonte', () => {
    expect(planUsageCoverageLabel(selectPlanUsage(null).coverage)).toBe('dado não coletado nesta base');
  });

  it('conta capturas e sessoes do recorte', () => {
    expect(planUsageCoverageLabel(COVERAGE_MEASURED)).toBe('4 capturas · 2 sessões');
  });
});

describe('tightestScope', () => {
  it('escolhe a janela de MAIOR percentual e diz qual é (não funde as duas)', () => {
    const vm = selectPlanUsage(MEASURED);
    const t = tightestScope(vm.byScope);
    // 91.5% (5h) vs 43% (7d): a janela apertada é a de 5h.
    expect(t?.scope).toBe('five_hour');
    expect(t?.usedPercentage).toBe(91.5);
  });

  it('ignora janelas sem leitura em vez de deixá-las vencer', () => {
    const t = tightestScope([
      { scope: 'five_hour', usedPercentage: null, resetsAt: null, capturedAt: null, peakUsedPercentage: null, captures: 1 },
      { scope: 'seven_day', usedPercentage: 12, resetsAt: null, capturedAt: null, peakUsedPercentage: 12, captures: 1 },
    ]);
    expect(t?.scope).toBe('seven_day');
  });

  it('nenhuma janela medida devolve null, nunca a primeira por default', () => {
    expect(tightestScope([])).toBeNull();
    expect(tightestScope([
      { scope: 'five_hour', usedPercentage: null, resetsAt: null, capturedAt: null, peakUsedPercentage: null, captures: 1 },
    ])).toBeNull();
  });

  it('0% medido conta como leitura válida (não é ausência)', () => {
    const t = tightestScope([
      { scope: 'five_hour', usedPercentage: 0, resetsAt: null, capturedAt: null, peakUsedPercentage: 0, captures: 1 },
    ]);
    expect(t?.usedPercentage).toBe(0);
  });
});


// ---------------------------------------------------------------------------
// issue #208 — o KPI compacto trocava de janela sem sinalizar e nao dizia ha
// quanto tempo a captura foi feita. Os dois pontos viram contrato aqui: os
// rotulos curtos (as DUAS janelas na mesma linha) e o frescor derivado do
// intervalo REALMENTE observado, nunca de um corte arbitrado.
// ---------------------------------------------------------------------------

const NOW = Date.parse('2026-08-10T13:00:00Z');

/** Ponto da serie de um escopo, a N segundos antes de NOW. */
function pointAgo(scope: string, secAgo: number, pct: number | null): PlanUsagePoint {
  return { scope, capturedAt: new Date(NOW - secAgo * 1000).toISOString(), usedPercentage: pct };
}

/** Estado de janela cuja captura mais recente tem N segundos de idade. */
function scopeAgo(scope: string, secAgo: number | null): PlanUsageScopeState {
  return {
    scope,
    usedPercentage: 50,
    resetsAt: null,
    capturedAt: secAgo == null ? null : new Date(NOW - secAgo * 1000).toISOString(),
    peakUsedPercentage: 50,
    captures: 3,
  };
}

describe('shortScopeLabel', () => {
  it('encurta as janelas conhecidas para caberem lado a lado no KPI', () => {
    expect(shortScopeLabel('five_hour')).toBe('5h');
    expect(shortScopeLabel('seven_day')).toBe('7d');
  });

  it('escopo desconhecido cai no identificador bruto, nunca some', () => {
    expect(shortScopeLabel('thirty_day')).toBe('thirty_day');
  });
});

describe('planUsageCapture — frescor derivado do intervalo observado', () => {
  it('sem captura: idade null e estado unknown (nao "agora")', () => {
    const c = planUsageCapture(scopeAgo('five_hour', null), [], NOW);
    expect(c.capturedAt).toBeNull();
    expect(c.ageSec).toBeNull();
    expect(c.state).toBe('unknown');
    expect(fmtCaptureAge(c.ageSec)).toBe('—');
  });

  it('menos de 2 pontos: idade existe, mas nenhuma suspeita e afirmada', () => {
    const c = planUsageCapture(scopeAgo('five_hour', 7200), [pointAgo('five_hour', 7200, 50)], NOW);
    expect(c.ageSec).toBe(7200);
    expect(c.typicalIntervalSec).toBeNull();
    // Sem base de comparacao o card mostra a idade e cala sobre o resto.
    expect(c.state).toBe('unknown');
  });

  it('captura dentro do intervalo tipico observado e fresh', () => {
    // Intervalos observados: 600s e 600s -> mediana 600s; idade 600s < 3x600s.
    const series = [
      pointAgo('five_hour', 1800, 40),
      pointAgo('five_hour', 1200, 45),
      pointAgo('five_hour', 600, 50),
    ];
    const c = planUsageCapture(scopeAgo('five_hour', 600), series, NOW);
    expect(c.typicalIntervalSec).toBe(600);
    expect(c.state).toBe('fresh');
  });

  it(`captura mais velha que ${CAPTURE_AGING_FACTOR}x o intervalo observado vira aging`, () => {
    // Mediana 600s; idade 5400s = 9x -> a ambiguidade throttle-vs-parada e
    // sinalizada, sem afirmar qual das duas leituras e a verdadeira.
    const series = [
      pointAgo('five_hour', 6600, 40),
      pointAgo('five_hour', 6000, 45),
      pointAgo('five_hour', 5400, 50),
    ];
    const c = planUsageCapture(scopeAgo('five_hour', 5400), series, NOW);
    expect(c.typicalIntervalSec).toBe(600);
    expect(c.ageSec).toBe(5400);
    expect(c.state).toBe('aging');
  });

  it('exatamente no corte ainda e fresh (o limite e "passou de", nao "chegou a")', () => {
    const series = [pointAgo('five_hour', 1800, 40), pointAgo('five_hour', 1200, 50)];
    // Mediana 600s, corte 1800s, idade 1800s.
    const c = planUsageCapture(scopeAgo('five_hour', 1800), series, NOW);
    expect(c.state).toBe('fresh');
  });

  it('so considera pontos DA janela pedida — a outra serie nao entra na mediana', () => {
    const series = [
      pointAgo('five_hour', 1200, 40),
      pointAgo('five_hour', 600, 50),
      // 7d em cadencia propria (1000s). Misturar as duas series daria
      // intervalos [1000, 1800, 600] -> mediana 1000, nao 600: fixture
      // escolhido para DISCRIMINAR o filtro, nao so para exercita-lo.
      pointAgo('seven_day', 4000, 20),
      pointAgo('seven_day', 3000, 24),
    ];
    const c = planUsageCapture(scopeAgo('five_hour', 600), series, NOW);
    expect(c.typicalIntervalSec).toBe(600);
  });

  it('duas capturas no mesmo segundo nao viram base de comparacao', () => {
    // Mediana 0 tornaria QUALQUER idade "aging" — o estado volta a unknown.
    const series = [pointAgo('five_hour', 600, 50), pointAgo('five_hour', 600, 50)];
    const c = planUsageCapture(scopeAgo('five_hour', 600), series, NOW);
    expect(c.typicalIntervalSec).toBeNull();
    expect(c.state).toBe('unknown');
  });

  it('data invalida nao vira idade zero', () => {
    const scope = { ...scopeAgo('five_hour', 60), capturedAt: 'nao-e-data' };
    const c = planUsageCapture(scope, [], NOW);
    expect(c.ageSec).toBeNull();
    expect(c.state).toBe('unknown');
  });
});

describe('fmtCaptureAge', () => {
  it('formata a idade em degraus legiveis', () => {
    expect(fmtCaptureAge(0)).toBe('agora');
    expect(fmtCaptureAge(59)).toBe('agora');
    expect(fmtCaptureAge(240)).toBe('ha 4m');
    expect(fmtCaptureAge(7200)).toBe('ha 2h');
    expect(fmtCaptureAge(3 * 86400)).toBe('ha 3d');
  });

  it('ausencia e "—", nunca "agora"', () => {
    expect(fmtCaptureAge(null)).toBe('—');
    expect(fmtCaptureAge(undefined)).toBe('—');
  });
});
