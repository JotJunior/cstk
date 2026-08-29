/**
 * Testes da derivacao defensiva dos chips de stack sugerida.
 * Ref: stack-display.ts — cobre o caso real (objeto JSON quebrado por split(','))
 * e as demais formas observadas na base (array JSON) e legado (CSV).
 */
import { describe, it, expect } from 'vitest';
import { stackDisplayItems } from './stack-display.js';

describe('stackDisplayItems', () => {
  it('retorna [] para null/undefined/vazio', () => {
    expect(stackDisplayItems(null)).toEqual([]);
    expect(stackDisplayItems(undefined)).toEqual([]);
    expect(stackDisplayItems('')).toEqual([]);
    expect(stackDisplayItems('   ')).toEqual([]);
  });

  it('array JSON de strings vira um chip por item', () => {
    expect(stackDisplayItems('["react 19", "vite", "nodejs"]')).toEqual([
      'react 19', 'vite', 'nodejs',
    ]);
  });

  it('objeto JSON vira chips "chave: valor" (caso real do bug)', () => {
    const raw = JSON.stringify({
      language: 'TypeScript 5.4',
      runtime: 'Node >=20',
      module: 'ESM',
      reference_project: 'fotus-dimens (sibling dir)',
    });
    expect(stackDisplayItems(raw)).toEqual([
      'language: TypeScript 5.4',
      'runtime: Node >=20',
      'module: ESM',
      'reference_project: fotus-dimens (sibling dir)',
    ]);
  });

  it('NAO quebra valores que contem virgula (regressao do split)', () => {
    const raw = JSON.stringify({ validation: 'zod + zod-to-json-schema, custom' });
    expect(stackDisplayItems(raw)).toEqual(['validation: zod + zod-to-json-schema, custom']);
  });

  it('string CSV legado (nao-JSON) e dividida por virgula', () => {
    expect(stackDisplayItems('node, react, vite')).toEqual(['node', 'react', 'vite']);
    expect(stackDisplayItems('node+ts')).toEqual(['node+ts']);
  });

  it('JSON malformado cai no fallback CSV em vez de lancar', () => {
    expect(stackDisplayItems('["react", "vite"')).toEqual(['["react"', '"vite"']);
  });

  it('serializa valores aninhados em vez de [object Object]', () => {
    const raw = JSON.stringify({ deps: { a: 1 }, tags: ['x', 'y'] });
    expect(stackDisplayItems(raw)).toEqual([
      'deps: {"a":1}',
      'tags: ["x","y"]',
    ]);
  });

  it('ignora itens vazios do array e chave sem valor mantem a chave', () => {
    expect(stackDisplayItems('["react", "", null, "vite"]')).toEqual(['react', 'vite']);
    expect(stackDisplayItems('{"flag": ""}')).toEqual(['flag']);
  });
});
