/**
 * Testes da classificacao de etapas do pipeline (stageStates).
 *
 * Regressao: execucoes terminais gravam etapa_corrente='concluida' (marcador
 * FORA de SDD_STAGES → idx=-1). A logica antiga do modo rotulado acendia por
 * `i < idx`, entao idx=-1 deixava TODAS as barras cinzas na visao da execucao.
 * A decisao agora acende pelo STATUS, identico nos dois modos de render.
 */
import { describe, it, expect } from 'vitest';
import { SDD_STAGES } from '@/lib/constants.js';
import { stageStates } from './PipelineProgress.js';

const N = SDD_STAGES.length; // 10

describe('stageStates', () => {
  it('concluida acende TODAS as etapas (done), independente da etapa', () => {
    // etapa='concluida' nao esta em SDD_STAGES → idx=-1: o caso que apagava tudo
    expect(stageStates('concluida', 'concluida')).toEqual(Array(N).fill('done'));
    // mesmo sem etapa informada
    expect(stageStates(null, 'concluida')).toEqual(Array(N).fill('done'));
  });

  it('em_andamento: etapas anteriores done, a corrente current, futuras idle', () => {
    // 'plan' e o indice 4
    const states = stageStates('plan', 'em_andamento');
    expect(states).toEqual([
      'done', 'done', 'done', 'done', 'current',
      'idle', 'idle', 'idle', 'idle', 'idle',
    ]);
  });

  it('aguardando_humano comporta-se como em andamento (corrente = current)', () => {
    const states = stageStates('specify', 'aguardando_humano'); // idx=2
    expect(states[1]).toBe('done');
    expect(states[2]).toBe('current');
    expect(states[3]).toBe('idle');
  });

  it('abortada: anteriores done, a partir da corrente aborted', () => {
    const states = stageStates('clarify', 'abortada'); // idx=3
    expect(states).toEqual([
      'done', 'done', 'done',
      'aborted', 'aborted', 'aborted', 'aborted', 'aborted', 'aborted', 'aborted',
    ]);
  });

  it('abortada sem etapa (idx=-1) marca tudo como aborted', () => {
    expect(stageStates('abortada', 'abortada')).toEqual(Array(N).fill('aborted'));
  });

  it('status null: primeira etapa idle (nada alcancado)', () => {
    expect(stageStates(null, null)).toEqual(Array(N).fill('idle'));
  });
});

/**
 * Regressao do caso GERAL: uma etapa que o pipeline emite e o painel nao
 * conhece derruba a barra inteira para cinza — `indexOf` devolve -1 e nenhuma
 * etapa satisfaz `i < idx` nem `i === idx`.
 *
 * O cabecalho deste arquivo ja documentava o sintoma para MARCADORES TERMINAIS
 * ('concluida'/'abortada'), resolvido acendendo pelo status. `converge` foi a
 * segunda ocorrencia, agora por etapa REAL em execucao: a feature
 * `pipeline-converge` do cstk a inseriu entre `execute-task` e `review-task`, e
 * toda execucao que chegou nela exibiu 10 barras cinzas enquanto 10 ondas
 * haviam rodado.
 */
describe('stageStates — etapa converge (regressao)', () => {
  it('converge esta na lista canonica, entre execute-task e review-task', () => {
    const idx = (SDD_STAGES as readonly string[]).indexOf('converge');
    expect(idx).toBeGreaterThan((SDD_STAGES as readonly string[]).indexOf('execute-task'));
    expect(idx).toBeLessThan((SDD_STAGES as readonly string[]).indexOf('review-task'));
  });

  it('em converge, tudo antes fica done e review-task fica idle — nunca tudo cinza', () => {
    const states = stageStates('converge', 'em_andamento');
    const idx = (SDD_STAGES as readonly string[]).indexOf('converge');

    expect(states[idx]).toBe('current');
    expect(states.slice(0, idx).every(s => s === 'done')).toBe(true);
    expect(states[idx + 1]).toBe('idle');
    // O bug: nenhuma barra acesa com a execucao em andamento.
    expect(states.every(s => s === 'idle')).toBe(false);
  });

  it('aguardando_humano em converge tambem acende (caso do bloqueio na etapa)', () => {
    const states = stageStates('converge', 'aguardando_humano');
    expect(states.some(s => s === 'current')).toBe(true);
  });

  it('LIMITACAO CONHECIDA: etapa desconhecida e nao-terminal ainda apaga a barra', () => {
    // Nao ha como o painel posicionar uma etapa que ainda nao existe. Este
    // teste NAO valida um comportamento desejavel — ele documenta o custo de
    // deixar SDD_STAGES desatualizada, que e exatamente o que aconteceu com
    // `converge`. Se um dia isso for resolvido (ex.: renderizar a etapa
    // desconhecida como current no fim da barra), este teste deve MUDAR, nao
    // ser apagado.
    expect(stageStates('etapa-que-nao-existe', 'em_andamento')).toEqual(Array(N).fill('idle'));
  });
});
