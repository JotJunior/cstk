/**
 * Testes unitarios de lib/fts.ts — task 3.5.5.
 * Garante que: inputs hostis nao produzem caracteres FTS5 ativos;
 * aspas internas sao escapadas corretamente; tokens limitados a 10.
 */
import { describe, it, expect } from 'vitest';
import { sanitizeFts, isValidFtsInput } from '../../src/lib/fts.js';

describe('sanitizeFts', () => {
  it('query simples: dois tokens embrulhados em aspas', () => {
    expect(sanitizeFts('npm install')).toBe('"npm" "install"');
  });

  it('token com aspas internas: aspas duplicadas (escape FTS5)', () => {
    // input: "aspas"  (uma string com aspas duplas ao redor)
    // token resultante apos split: "aspas"
    // escape interno: "" + aspas + "" → """aspas"""
    const result = sanitizeFts('"aspas"');
    expect(result).toBe('"""aspas"""');
  });

  it('input hostil: parenteses e OR nao ficam como operadores ativos', () => {
    // ') OR 1=1 -- → tokens: [')'], [OR], [1=1], [--]
    // cada um envolvido em aspas duplas — nao ha operador OR solto no FTS5
    const result = sanitizeFts("') OR 1=1 --");
    expect(result).toContain("\"')\"");
    expect(result).toContain('"OR"');
    expect(result).toContain('"1=1"');
    expect(result).toContain('"--"');
  });

  it('string vazia retorna ""', () => {
    expect(sanitizeFts('')).toBe('');
  });

  it('string so com espacos retorna ""', () => {
    expect(sanitizeFts('   ')).toBe('');
  });

  it('limite de 10 tokens: excesso descartado', () => {
    const input = 'a b c d e f g h i j k l m';
    const result = sanitizeFts(input);
    const parts = result.split(' ');
    expect(parts.length).toBe(10);
  });

  it('token unico: embrulhado em aspas', () => {
    expect(sanitizeFts('hello')).toBe('"hello"');
  });

  it('barra invertida preservada (nao e metacaractere FTS5)', () => {
    // backslash nao e especial em FTS5 — preservado literalmente
    const result = sanitizeFts('back\\slash');
    expect(result).toBe('"back\\slash"');
  });

  it('DROP TABLE: tokens tokenizados separadamente', () => {
    const result = sanitizeFts('DROP TABLE users');
    expect(result).toBe('"DROP" "TABLE" "users"');
  });

  it('input com multiplos espacos: tokens normalizados', () => {
    expect(sanitizeFts('  foo   bar  ')).toBe('"foo" "bar"');
  });
});

describe('isValidFtsInput', () => {
  it('input valido retorna true', () => {
    expect(isValidFtsInput('hello world')).toBe(true);
  });

  it('string vazia retorna false', () => {
    expect(isValidFtsInput('')).toBe(false);
  });

  it('string de espacos retorna false', () => {
    expect(isValidFtsInput('   ')).toBe(false);
  });
});
