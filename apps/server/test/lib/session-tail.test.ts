/**
 * Testes de leitura de tail por janela (lib/session-tail.ts).
 * Ref: tasks.md FASE 2 (2.3.4), research.md Decisions 8/9/10,
 * data-model.md Entity SessionTailEntryDTO.
 *
 * Cobertura exigida por 2.3.4: transcript grande respeitando os dois tetos
 * (linhas e bytes), linha malformada pulada e contada, fixture com
 * `sessionId` e `session_id` coexistindo confirmando que o DTO final nunca
 * vaza a chave crua da linha.
 */
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, realpathSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  readSessionTail,
  TAIL_READ_WINDOW_BYTES,
  RESPONSE_BYTE_BUDGET,
  ENTRY_TEXT_MAX_BYTES,
  DEFAULT_TAIL_LINES,
} from '../../src/lib/session-tail.js';

let base: string;

beforeEach(() => {
  base = mkdtempSync(join(realpathSync(tmpdir()), 'session-tail-'));
});

afterEach(() => {
  rmSync(base, { recursive: true, force: true });
});

function writeSession(lines: string[]): string {
  const filePath = join(base, 'sessao.jsonl');
  mkdirSync(base, { recursive: true });
  writeFileSync(filePath, lines.map((l) => `${l}\n`).join(''));
  return filePath;
}

function line(fields: Record<string, unknown>): string {
  return JSON.stringify(fields);
}

describe('readSessionTail — arquivo inexistente/invalido (Principio II)', () => {
  it('path inexistente -> null (nunca lanca)', () => {
    expect(readSessionTail(join(base, 'nao-existe.jsonl'))).toBeNull();
  });

  it('path aponta para diretorio -> null', () => {
    const dir = join(base, 'um-dir');
    mkdirSync(dir);
    expect(readSessionTail(dir)).toBeNull();
  });
});

describe('readSessionTail — teto de linhas (default 200, clamp 1..1000)', () => {
  it('arquivo com mais linhas que o default devolve exatamente as ultimas 200, em ordem ascendente', () => {
    const total = 300;
    const lines = Array.from({ length: total }, (_, i) => line({ uuid: `u-${i}`, type: 'user', text: `linha ${i}` }));
    const filePath = writeSession(lines);

    const result = readSessionTail(filePath);
    expect(result).not.toBeNull();
    expect(result!.requestedLines).toBe(DEFAULT_TAIL_LINES);
    expect(result!.returnedLines).toBe(200);
    expect(result!.entries).toHaveLength(200);
    // As 200 mais recentes: indices 100..299, em ordem ascendente (mais antiga primeiro).
    expect(result!.entries[0]!.uuid).toBe('u-100');
    expect(result!.entries[199]!.uuid).toBe('u-299');
    expect(result!.skippedLines).toBe(0);
    expect(result!.truncatedByBytes).toBe(false);
  });

  it('respeita `lines` explicito dentro do range', () => {
    const lines = Array.from({ length: 50 }, (_, i) => line({ uuid: `u-${i}`, type: 'user', text: `x${i}` }));
    const filePath = writeSession(lines);

    const result = readSessionTail(filePath, { lines: 10 });
    expect(result!.requestedLines).toBe(10);
    expect(result!.returnedLines).toBe(10);
    expect(result!.entries[0]!.uuid).toBe('u-40');
    expect(result!.entries[9]!.uuid).toBe('u-49');
  });

  it('clamp: valor abaixo de 1 vira 1; acima de 1000 vira 1000', () => {
    const filePath = writeSession([line({ uuid: 'u-0', type: 'user', text: 'oi' })]);

    expect(readSessionTail(filePath, { lines: 0 })!.requestedLines).toBe(1);
    expect(readSessionTail(filePath, { lines: -5 })!.requestedLines).toBe(1);
    expect(readSessionTail(filePath, { lines: 5000 })!.requestedLines).toBe(1000);
    expect(readSessionTail(filePath, { lines: 1.9 })!.requestedLines).toBe(1);
  });

  it('menos linhas no arquivo do que o solicitado devolve todas as validas', () => {
    const lines = Array.from({ length: 5 }, (_, i) => line({ uuid: `u-${i}`, type: 'user', text: `x${i}` }));
    const filePath = writeSession(lines);

    const result = readSessionTail(filePath, { lines: 50 });
    expect(result!.returnedLines).toBe(5);
    expect(result!.requestedLines).toBe(50);
  });
});

describe('readSessionTail — linha malformada (FR-003a)', () => {
  it('pula linha que nao parseia como JSON e conta em skippedLines, sem abortar', () => {
    const filePath = writeSession([
      line({ uuid: 'u-0', type: 'user', text: 'ok-1' }),
      '{"uuid": "quebrada", NAO_E_JSON_VALIDO',
      line({ uuid: 'u-2', type: 'user', text: 'ok-2' }),
    ]);

    const result = readSessionTail(filePath);
    expect(result!.skippedLines).toBe(1);
    expect(result!.returnedLines).toBe(2);
    expect(result!.entries.map((e) => e.uuid)).toEqual(['u-0', 'u-2']);
  });

  it('pula linha cujo JSON parseia mas nao e um objeto (array/numero/string solta)', () => {
    const filePath = writeSession([line({ uuid: 'u-0', type: 'user', text: 'ok' }), '[1,2,3]', '42', '"solta"']);

    const result = readSessionTail(filePath);
    expect(result!.skippedLines).toBe(3);
    expect(result!.returnedLines).toBe(1);
  });

  it('linhas em branco sao ignoradas sem contar como skipped', () => {
    const filePath = writeSession([line({ uuid: 'u-0', type: 'user', text: 'ok' }), '', '   ']);
    const result = readSessionTail(filePath);
    expect(result!.skippedLines).toBe(0);
    expect(result!.returnedLines).toBe(1);
  });
});

describe('readSessionTail — teto de bytes da resposta (Decision 9, FR-006)', () => {
  it('orcamento de bytes corta a selecao antes do teto de linhas quando as entradas sao grandes', () => {
    // Cada entrada tera texto >= ENTRY_TEXT_MAX_BYTES, portanto cada uma
    // consome exatamente ENTRY_TEXT_MAX_BYTES (8 KiB) apos o corte por
    // entrada. RESPONSE_BYTE_BUDGET (256 KiB) / 8 KiB = 32 entradas cabem.
    const bigText = 'a'.repeat(ENTRY_TEXT_MAX_BYTES + 500);
    const total = 50;
    const lines = Array.from({ length: total }, (_, i) =>
      line({ uuid: `u-${i}`, type: 'user', message: { role: 'user', content: bigText } })
    );
    const filePath = writeSession(lines);

    const result = readSessionTail(filePath, { lines: 200 });
    expect(result!.requestedLines).toBe(200);
    expect(result!.truncatedByBytes).toBe(true);
    expect(result!.returnedLines).toBe(Math.floor(RESPONSE_BYTE_BUDGET / ENTRY_TEXT_MAX_BYTES));
    // As mais recentes (u-18..u-49) devem ser as selecionadas.
    expect(result!.entries[result!.entries.length - 1]!.uuid).toBe(`u-${total - 1}`);
  });

  it('texto de uma entrada e truncado no teto por entrada, sinalizado por textTruncated', () => {
    const bigText = 'b'.repeat(ENTRY_TEXT_MAX_BYTES * 3);
    const filePath = writeSession([
      line({ uuid: 'u-0', type: 'user', message: { role: 'user', content: bigText } }),
    ]);

    const result = readSessionTail(filePath);
    const entry = result!.entries[0]!;
    expect(entry.textTruncated).toBe(true);
    expect(Buffer.byteLength(entry.text, 'utf8')).toBe(ENTRY_TEXT_MAX_BYTES);
  });

  it('texto dentro do teto por entrada nao e truncado', () => {
    const filePath = writeSession([
      line({ uuid: 'u-0', type: 'user', message: { role: 'user', content: 'texto curto' } }),
    ]);
    const result = readSessionTail(filePath);
    expect(result!.entries[0]!.textTruncated).toBe(false);
    expect(result!.entries[0]!.text).toBe('texto curto');
  });
});

describe('readSessionTail — janela de leitura a partir do fim do arquivo (Decision 8)', () => {
  it('windowTruncated=false quando o arquivo cabe inteiro na janela', () => {
    const filePath = writeSession([line({ uuid: 'u-0', type: 'user', text: 'x' })]);
    const result = readSessionTail(filePath);
    expect(result!.windowTruncated).toBe(false);
  });

  it('arquivo maior que TAIL_READ_WINDOW_BYTES: windowTruncated=true e o conteudo final continua correto', () => {
    // Gera linhas curtas o bastante em quantidade suficiente para ultrapassar
    // a janela de 1 MiB, sem depender de nenhuma linha individual grande.
    const approxLineBytes = 40;
    const totalLines = Math.ceil((TAIL_READ_WINDOW_BYTES * 1.5) / approxLineBytes);
    const lines: string[] = [];
    for (let i = 0; i < totalLines; i++) {
      lines.push(line({ uuid: `u-${i}`, type: 'user', text: `linha numero ${i}` }));
    }
    const filePath = writeSession(lines);

    const result = readSessionTail(filePath, { lines: 200 });
    expect(result!.windowTruncated).toBe(true);
    expect(result!.returnedLines).toBe(200);
    expect(result!.skippedLines).toBe(0); // fragmento cortado pela janela foi descartado, nao contado como malformado
    expect(result!.entries[199]!.uuid).toBe(`u-${totalLines - 1}`); // a ultima linha do arquivo e sempre a mais recente
  });
});

describe('readSessionTail — achatamento de .message.content e normalizacao', () => {
  it('content string vira text diretamente; role vem de message.role', () => {
    const filePath = writeSession([
      line({ uuid: 'u-0', type: 'assistant', timestamp: '2026-01-01T00:00:00Z', message: { role: 'assistant', content: 'ola' } }),
    ]);
    const result = readSessionTail(filePath);
    const entry = result!.entries[0]!;
    expect(entry.role).toBe('assistant');
    expect(entry.timestamp).toBe('2026-01-01T00:00:00Z');
    expect(entry.text).toBe('ola');
  });

  it('content array: concatena apenas itens type=text, ignora thinking/tool_use/tool_result', () => {
    const filePath = writeSession([
      line({
        uuid: 'u-0',
        type: 'assistant',
        message: {
          role: 'assistant',
          content: [
            { type: 'thinking', thinking: 'raciocinio interno' },
            { type: 'text', text: 'parte 1' },
            { type: 'tool_use', input: { comando: 'rm -rf /' } },
            { type: 'text', text: 'parte 2' },
            { type: 'tool_result', content: 'saida bruta gigante' },
          ],
        },
      }),
    ]);
    const result = readSessionTail(filePath);
    expect(result!.entries[0]!.text).toBe('parte 1\nparte 2');
  });

  it('linha sem .message -> role null e text vazio', () => {
    const filePath = writeSession([line({ uuid: 'u-0', type: 'file-history-snapshot' })]);
    const result = readSessionTail(filePath);
    const entry = result!.entries[0]!;
    expect(entry.role).toBeNull();
    expect(entry.text).toBe('');
    expect(entry.type).toBe('file-history-snapshot');
  });

  it('uuid/timestamp ausentes -> null, nunca undefined ou lancamento', () => {
    const filePath = writeSession([line({ type: 'system' })]);
    const entry = readSessionTail(filePath)!.entries[0]!;
    expect(entry.uuid).toBeNull();
    expect(entry.timestamp).toBeNull();
  });

  it('sessionId e session_id coexistindo na mesma linha nao vazam para o DTO da entrada', () => {
    const filePath = writeSession([
      line({
        uuid: 'u-0',
        type: 'user',
        sessionId: '5f3c2e10-71a4-4b8e-9c1a-2d6f8b0a9e11',
        session_id: '5f3c2e10-71a4-4b8e-9c1a-2d6f8b0a9e11',
        message: { role: 'user', content: 'oi' },
      }),
    ]);
    const entry = readSessionTail(filePath)!.entries[0]!;
    expect(Object.keys(entry).sort()).toEqual(['role', 'text', 'textTruncated', 'timestamp', 'type', 'uuid'].sort());
    expect((entry as Record<string, unknown>)['sessionId']).toBeUndefined();
    expect((entry as Record<string, unknown>)['session_id']).toBeUndefined();
  });
});

describe('readSessionTail — lastActivityAt (mtime)', () => {
  it('devolve lastActivityAt como ISO 8601 correspondente ao mtime do arquivo', () => {
    const filePath = writeSession([line({ uuid: 'u-0', type: 'user', text: 'oi' })]);
    const result = readSessionTail(filePath);
    expect(() => new Date(result!.lastActivityAt).toISOString()).not.toThrow();
    expect(new Date(result!.lastActivityAt).toISOString()).toBe(result!.lastActivityAt);
  });
});
