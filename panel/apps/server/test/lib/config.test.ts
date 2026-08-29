/**
 * Testes unitarios de resolveProjectPath (task 1.1, FR-008).
 *
 * Ref: research.md Decision 1 — mapa nome-logico -> caminho absoluto lido de
 * CSTK_PROJECT_PATHS (`nome=/abs/path;outro=/x/y`), canonicalizado via
 * path.resolve(). Retorna null (nunca lanca) quando o projeto nao esta no
 * mapa ou o env esta ausente/vazio.
 *
 * Convencao do projeto: mutar process.env diretamente em beforeEach/afterEach
 * (ver test/lib/decisions-opcoes.test.ts, test/lib/memories.test.ts).
 */
import { describe, it, expect, afterEach } from 'vitest';
import { resolve } from 'node:path';
import { resolveProjectPath } from '../../src/config.js';

afterEach(() => {
  delete process.env['CSTK_PROJECT_PATHS'];
});

describe('resolveProjectPath — mapa vazio (default)', () => {
  it('retorna null para qualquer projeto quando CSTK_PROJECT_PATHS esta ausente', () => {
    delete process.env['CSTK_PROJECT_PATHS'];
    expect(resolveProjectPath('cstk-panel')).toBeNull();
  });

  it('retorna null quando CSTK_PROJECT_PATHS esta definido mas vazio', () => {
    process.env['CSTK_PROJECT_PATHS'] = '';
    expect(resolveProjectPath('cstk-panel')).toBeNull();
  });

  it('retorna null quando CSTK_PROJECT_PATHS e so espacos', () => {
    process.env['CSTK_PROJECT_PATHS'] = '   ';
    expect(resolveProjectPath('cstk-panel')).toBeNull();
  });
});

describe('resolveProjectPath — projeto ausente do mapa', () => {
  it('retorna null (nunca lanca) para projeto nao configurado', () => {
    process.env['CSTK_PROJECT_PATHS'] = 'cstk-panel=/Users/jot/Projects/cstk-panel';
    expect(resolveProjectPath('outro-projeto')).toBeNull();
  });
});

describe('resolveProjectPath — multiplas entradas', () => {
  it('resolve o path correto para cada nome no mapa com 2+ entradas', () => {
    process.env['CSTK_PROJECT_PATHS'] =
      'cstk-panel=/Users/jot/Projects/cstk-panel;outro=/Users/jot/Projects/outro';
    expect(resolveProjectPath('cstk-panel')).toBe(resolve('/Users/jot/Projects/cstk-panel'));
    expect(resolveProjectPath('outro')).toBe(resolve('/Users/jot/Projects/outro'));
  });

  it('tolera espacos ao redor dos separadores ; e =', () => {
    process.env['CSTK_PROJECT_PATHS'] =
      ' cstk-panel = /Users/jot/Projects/cstk-panel ; outro = /Users/jot/Projects/outro ';
    expect(resolveProjectPath('cstk-panel')).toBe(resolve('/Users/jot/Projects/cstk-panel'));
    expect(resolveProjectPath('outro')).toBe(resolve('/Users/jot/Projects/outro'));
  });
});

describe('resolveProjectPath — canonicalizacao anti-traversal', () => {
  it('canonicaliza path com segmentos ".." via path.resolve()', () => {
    process.env['CSTK_PROJECT_PATHS'] = 'proj=/Users/jot/Projects/../Projects/cstk-panel';
    expect(resolveProjectPath('proj')).toBe(resolve('/Users/jot/Projects/../Projects/cstk-panel'));
    expect(resolveProjectPath('proj')).toBe('/Users/jot/Projects/cstk-panel');
  });

  it('resolve path relativo para absoluto (relativo ao cwd do processo)', () => {
    process.env['CSTK_PROJECT_PATHS'] = 'proj=relative/sub/dir';
    const result = resolveProjectPath('proj');
    expect(result).toBe(resolve('relative/sub/dir'));
    expect(result).not.toBeNull();
    expect(result!.startsWith('/')).toBe(true);
  });
});

describe('resolveProjectPath — entradas malformadas ignoradas (Principio II)', () => {
  it('ignora entrada sem "=" sem lancar excecao', () => {
    process.env['CSTK_PROJECT_PATHS'] = 'entrada-sem-igual;valido=/Users/jot/Projects/valido';
    expect(() => resolveProjectPath('valido')).not.toThrow();
    expect(resolveProjectPath('valido')).toBe(resolve('/Users/jot/Projects/valido'));
    expect(resolveProjectPath('entrada-sem-igual')).toBeNull();
  });

  it('ignora entrada com nome vazio ("=/path")', () => {
    process.env['CSTK_PROJECT_PATHS'] = '=/Users/jot/Projects/sem-nome;valido=/Users/jot/Projects/valido';
    expect(resolveProjectPath('')).toBeNull();
    expect(resolveProjectPath('valido')).toBe(resolve('/Users/jot/Projects/valido'));
  });

  it('ignora entrada com path vazio ("nome=")', () => {
    process.env['CSTK_PROJECT_PATHS'] = 'sem-path=;valido=/Users/jot/Projects/valido';
    expect(resolveProjectPath('sem-path')).toBeNull();
    expect(resolveProjectPath('valido')).toBe(resolve('/Users/jot/Projects/valido'));
  });

  it('ignora segmentos vazios entre ";;" consecutivos', () => {
    process.env['CSTK_PROJECT_PATHS'] = 'valido=/Users/jot/Projects/valido;;outro=/Users/jot/Projects/outro';
    expect(resolveProjectPath('valido')).toBe(resolve('/Users/jot/Projects/valido'));
    expect(resolveProjectPath('outro')).toBe(resolve('/Users/jot/Projects/outro'));
  });
});
