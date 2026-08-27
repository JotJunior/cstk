/**
 * Testes do guard de confinamento de path de sessoes (lib/sessions-root.ts).
 * Ref: tasks.md FASE 2 (2.1.5), research.md Decision 5,
 * contracts/sessions-api.md "Guard de path (obrigatorio)".
 *
 * Cobertura exigida por 2.1.5: escape via `..`, symlink apontando para fora,
 * UUID invalido rejeitado ANTES do path-join, caixa mista resolvendo ao
 * mesmo arquivo, raiz ausente.
 */
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import {
  mkdtempSync,
  mkdirSync,
  writeFileSync,
  symlinkSync,
  rmSync,
  realpathSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  isValidSessionId,
  normalizeSessionId,
  resolveSessionsRoot,
  resolveConfinedSessionPath,
  readConfinedSessionFile,
} from '../../src/lib/sessions-root.js';

let base: string;
let root: string;
let savedRoot: string | undefined;

const VALID_UUID = '5f3c2e10-71a4-4b8e-9c1a-2d6f8b0a9e11';

beforeEach(() => {
  // realpath do tmpdir: no macOS /var -> /private/var; normaliza para que
  // caminhos criados == caminhos canonicalizados nas assercoes.
  base = mkdtempSync(join(realpathSync(tmpdir()), 'sessions-root-'));
  root = join(base, 'projects');
  mkdirSync(root);
  savedRoot = process.env['CSTK_SESSIONS_ROOT'];
  process.env['CSTK_SESSIONS_ROOT'] = root;
});

afterEach(() => {
  rmSync(base, { recursive: true, force: true });
  if (savedRoot === undefined) delete process.env['CSTK_SESSIONS_ROOT'];
  else process.env['CSTK_SESSIONS_ROOT'] = savedRoot;
});

describe('isValidSessionId (CHK016 — validar UUID antes do path-join)', () => {
  it('aceita UUID minusculo valido', () => {
    expect(isValidSessionId(VALID_UUID)).toBe(true);
  });

  it('aceita UUID em caixa mista (normaliza internamente)', () => {
    expect(isValidSessionId(VALID_UUID.toUpperCase())).toBe(true);
  });

  it('rejeita string com traversal antes de qualquer path-join', () => {
    expect(isValidSessionId('../../etc/passwd')).toBe(false);
  });

  it('rejeita string arbitraria nao-UUID', () => {
    expect(isValidSessionId('nao-e-um-uuid')).toBe(false);
    expect(isValidSessionId('')).toBe(false);
    expect(isValidSessionId(null)).toBe(false);
    expect(isValidSessionId(undefined)).toBe(false);
    expect(isValidSessionId(123)).toBe(false);
  });
});

describe('normalizeSessionId', () => {
  it('normaliza caixa e espacos', () => {
    expect(normalizeSessionId(`  ${VALID_UUID.toUpperCase()}  `)).toBe(VALID_UUID);
  });
});

describe('resolveSessionsRoot', () => {
  it('resolve a raiz configurada via CSTK_SESSIONS_ROOT', () => {
    expect(resolveSessionsRoot()).toBe(root);
  });

  it('raiz ausente -> null (nunca lanca)', () => {
    process.env['CSTK_SESSIONS_ROOT'] = join(base, 'nao-existe');
    expect(resolveSessionsRoot()).toBeNull();
  });

  it('raiz aponta para arquivo (nao-diretorio) -> null', () => {
    const file = join(base, 'arquivo.txt');
    writeFileSync(file, 'x');
    process.env['CSTK_SESSIONS_ROOT'] = file;
    expect(resolveSessionsRoot()).toBeNull();
  });
});

describe('resolveConfinedSessionPath', () => {
  it('resolve sessao existente sob slug de projeto', () => {
    const slugDir = join(root, 'meu-projeto');
    mkdirSync(slugDir);
    const sessionFile = join(slugDir, `${VALID_UUID}.jsonl`);
    writeFileSync(sessionFile, '{}\n');

    const resolved = resolveConfinedSessionPath(root, 'meu-projeto', VALID_UUID);
    expect(resolved).toBe(sessionFile);
  });

  it('caixa mista no sessionId resolve ao mesmo arquivo (CHK018)', () => {
    const slugDir = join(root, 'meu-projeto');
    mkdirSync(slugDir);
    const sessionFile = join(slugDir, `${VALID_UUID}.jsonl`);
    writeFileSync(sessionFile, '{}\n');

    const resolved = resolveConfinedSessionPath(root, 'meu-projeto', VALID_UUID.toUpperCase());
    expect(resolved).toBe(sessionFile);
  });

  it('UUID invalido (com traversal) e rejeitado sem jamais montar/resolver um path — resultado null mesmo com arquivo real presente sob o alvo do traversal', () => {
    // Prova comportamental de CHK016: cria deliberadamente o alvo que um
    // path-join ingenuo alcancaria SE a validacao de UUID nao rodasse
    // antes (join(root, 'meu-projeto', '../../../etc/passwd.jsonl')). Se a
    // guarda de UUID nao estivesse na frente, este arquivo existiria e
    // poderia ser alcancado; com a guarda, a rejeicao ocorre pela forma da
    // string, nao pela ausencia de alvo.
    const slugDir = join(root, 'meu-projeto');
    mkdirSync(slugDir, { recursive: true });
    const resolved = resolveConfinedSessionPath(root, 'meu-projeto', '../../../etc/passwd');
    expect(resolved).toBeNull();
  });

  it('sessionId com traversal disfarcado de UUID-like ainda e rejeitado (nao e UUID valido)', () => {
    const resolved = resolveConfinedSessionPath(root, 'meu-projeto', '../../etc/passwd');
    expect(resolved).toBeNull();
  });

  it('escape via symlink apontando para fora da raiz e rejeitado', () => {
    const slugDir = join(root, 'meu-projeto');
    mkdirSync(slugDir);
    const outside = join(base, 'fora-da-raiz');
    mkdirSync(outside);
    const secretFile = join(outside, 'segredo.jsonl');
    writeFileSync(secretFile, '{"segredo": true}\n');
    const link = join(slugDir, `${VALID_UUID}.jsonl`);
    symlinkSync(secretFile, link);

    const resolved = resolveConfinedSessionPath(root, 'meu-projeto', VALID_UUID);
    expect(resolved).toBeNull();
  });

  it('projectSlug com ".." tentando escapar via segmento intermediario e rejeitado', () => {
    // join('root', '../outside', 'x.jsonl') resolve para fora da raiz apos
    // realpathSync — mesmo que o arquivo exista la, o confinamento rejeita.
    const outsideDir = join(base, 'outside');
    mkdirSync(outsideDir);
    const outsideFile = join(outsideDir, `${VALID_UUID}.jsonl`);
    writeFileSync(outsideFile, '{}\n');

    const resolved = resolveConfinedSessionPath(root, '../outside', VALID_UUID);
    expect(resolved).toBeNull();
  });

  it('sessao inexistente sob slug valido -> null', () => {
    const slugDir = join(root, 'meu-projeto');
    mkdirSync(slugDir);
    const resolved = resolveConfinedSessionPath(root, 'meu-projeto', VALID_UUID);
    expect(resolved).toBeNull();
  });

  it('projectSlug vazio -> null', () => {
    expect(resolveConfinedSessionPath(root, '', VALID_UUID)).toBeNull();
  });
});

describe('readConfinedSessionFile (CHK017 — leitura unica, sem TOCTOU)', () => {
  it('le o conteudo do arquivo ja confinado', () => {
    const slugDir = join(root, 'meu-projeto');
    mkdirSync(slugDir);
    const sessionFile = join(slugDir, `${VALID_UUID}.jsonl`);
    writeFileSync(sessionFile, '{"hello":"world"}\n');

    const resolved = resolveConfinedSessionPath(root, 'meu-projeto', VALID_UUID);
    expect(resolved).not.toBeNull();
    const content = readConfinedSessionFile(resolved as string);
    expect(content?.toString('utf8')).toBe('{"hello":"world"}\n');
  });

  it('path inexistente -> null (nunca lanca)', () => {
    expect(readConfinedSessionFile(join(root, 'nao-existe.jsonl'))).toBeNull();
  });

  it('path apontando para diretorio (nao-arquivo) -> null', () => {
    const dir = join(root, 'um-diretorio');
    mkdirSync(dir);
    expect(readConfinedSessionFile(dir)).toBeNull();
  });
});
