/**
 * Testes do painel de Documentacao da FeatureDetail (task 4.3.4; quickstart
 * Cenarios 4-6). Sem jsdom/@testing-library neste repo (vitest.config.ts
 * `environment: 'node'`, so `*.test.ts` — ver PipelineProgress.test.ts para
 * o mesmo padrao): a logica de navegacao/selecao e extraida como funcoes
 * puras (`pickDefaultArtifact`, `contentFetchId`) e testada em isolamento,
 * sem montar `DocumentationPanel`.
 */
import { describe, it, expect } from 'vitest';
import type { FeatureDocScope } from '@cstk-panel/shared-types';
import { pickDefaultArtifact, contentFetchId, type ArtifactPickCandidate } from './FeatureDetail.js';

function art(artifactId: string, produced: boolean, scope: FeatureDocScope = 'feature'): ArtifactPickCandidate {
  return { artifactId, produced, scope };
}

describe('pickDefaultArtifact', () => {
  it('escolhe o primeiro artefato PRODUZIDO na ordem da listagem', () => {
    const artifacts = [art('spec', true), art('plan', true), art('tasks', false)];
    expect(pickDefaultArtifact(artifacts)).toBe('spec');
  });

  it('prefere a spec da feature aos docs de projeto que abrem a listagem', () => {
    const artifacts = [
      art('briefing', true, 'project'),
      art('constitution', true, 'project'),
      art('spec', true),
    ];
    expect(pickDefaultArtifact(artifacts)).toBe('spec');
  });

  it('cai no doc de projeto quando a feature ainda nao produziu nada', () => {
    const artifacts = [
      art('briefing', true, 'project'),
      art('constitution', true, 'project'),
      art('spec', false),
    ];
    expect(pickDefaultArtifact(artifacts)).toBe('briefing');
  });

  it('nada produzido: cai no primeiro artefato DA FEATURE, nao no de projeto', () => {
    const artifacts = [
      art('briefing', false, 'project'),
      art('spec', false),
      art('plan', false),
    ];
    expect(pickDefaultArtifact(artifacts)).toBe('spec');
  });

  it('pula artefatos nao-produzidos ate achar o primeiro produzido (Cenario 6 — navegacao)', () => {
    const artifacts = [art('spec', false), art('plan', false), art('research', true)];
    expect(pickDefaultArtifact(artifacts)).toBe('research');
  });

  it('cai no primeiro item da lista quando NENHUM foi produzido (Cenario 5 — sem tela vazia)', () => {
    const artifacts = [art('spec', false), art('plan', false)];
    expect(pickDefaultArtifact(artifacts)).toBe('spec');
  });

  it('retorna null so quando a lista esta genuinamente vazia', () => {
    expect(pickDefaultArtifact([])).toBeNull();
  });
});

describe('contentFetchId', () => {
  it('retorna o artifactId quando o artefato selecionado ja foi produzido (Cenario 4/6)', () => {
    expect(contentFetchId(art('spec', true), 'spec')).toBe('spec');
  });

  it('retorna string vazia (desabilita o fetch) quando NAO produzido (Cenario 5 — FR-007)', () => {
    expect(contentFetchId(art('plan', false), 'plan')).toBe('');
  });

  it('retorna string vazia quando nao ha artefato selecionado', () => {
    expect(contentFetchId(null, null)).toBe('');
  });

  it('retorna string vazia se produced=true mas o id efetivo e null (defensivo)', () => {
    expect(contentFetchId(art('spec', true), null)).toBe('');
  });
});
