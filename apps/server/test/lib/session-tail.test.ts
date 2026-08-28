/**
 * Testes de leitura de tail por janela (lib/session-tail.ts).
 * Ref: tasks.md FASE 2 (2.3.4), FASE 3 (3.3.2), research.md Decisions
 * 8/9/10, data-model.md Entity SessionTailEntryDTO.
 *
 * Cobertura exigida por 2.3.4: transcript grande respeitando os dois tetos
 * (linhas e bytes), linha malformada pulada e contada, fixture com
 * `sessionId` e `session_id` coexistindo confirmando que o DTO final nunca
 * vaza a chave crua da linha.
 *
 * Cobertura exigida por 3.3.2 (ordem scrub-vs-truncamento): fixture com
 * segredo posicionado exatamente na fronteira do teto de bytes por
 * entrada, confirmando que o texto truncado e o texto JA redigido e que
 * `[REDACTED]` conta para o teto.
 *
 * `readSessionTail` e async desde a task 3.3 (a cadeia de scrub pode
 * invocar um subprocesso) — todo `it` que a chama e `async`, e toda
 * chamada e `await`ada. `CSTK_SECRETS_FILTER` e forcado para um path
 * inexistente em `beforeEach` para que a suite nunca dependa do
 * `secrets-filter.sh` real da maquina (determinismo entre ambientes,
 * `scrubMode: 'internal'` sempre neste arquivo — o modo `cstk+internal`
 * e coberto isoladamente em `secret-scrub.test.ts`).
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
import { resetSecretsFilterAvailabilityForTests } from '../../src/lib/secret-scrub.js';

let base: string;
const ORIGINAL_ENV = { ...process.env };

beforeEach(() => {
  base = mkdtempSync(join(realpathSync(tmpdir()), 'session-tail-'));
  // Determinismo: nunca depender do secrets-filter.sh real da maquina de
  // dev/CI — forca scrubMode: 'internal' em toda a suite (3.2.2).
  process.env['CSTK_SECRETS_FILTER'] = '/caminho/que/nao/existe/secrets-filter.sh';
  resetSecretsFilterAvailabilityForTests();
});

afterEach(() => {
  rmSync(base, { recursive: true, force: true });
  process.env = { ...ORIGINAL_ENV };
  resetSecretsFilterAvailabilityForTests();
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

/*
 * NOTA sobre as fixtures (0.34.0): elas passavam `text` no NIVEL RAIZ da
 * linha — campo que o extrator nunca leu, porque a fonte real poe o conteudo
 * em `message.content`. O resultado era que estes testes de teto de linhas e
 * bytes contavam entradas TODAS VAZIAS: passavam verdes sobre exatamente o
 * defeito reportado pelo operador (tela com 95% de linhas sem conteudo).
 * Agora as fixtures montam `message: { role, content }`, e os mesmos tetos
 * sao exercidos sobre entradas que de fato renderizam.
 */

describe('readSessionTail — arquivo inexistente/invalido (Principio II)', () => {
  it('path inexistente -> null (nunca lanca)', async () => {
    expect(await readSessionTail(join(base, 'nao-existe.jsonl'))).toBeNull();
  });

  it('path aponta para diretorio -> null', async () => {
    const dir = join(base, 'um-dir');
    mkdirSync(dir);
    expect(await readSessionTail(dir)).toBeNull();
  });
});

describe('readSessionTail — teto de linhas (default 200, clamp 1..1000)', () => {
  it('arquivo com mais linhas que o default devolve exatamente as ultimas 200, em ordem ascendente', async () => {
    const total = 300;
    const lines = Array.from({ length: total }, (_, i) => line({ uuid: `u-${i}`, type: 'user', message: { role: 'user', content: `linha ${i}` } }));
    const filePath = writeSession(lines);

    const result = await readSessionTail(filePath);
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

  it('respeita `lines` explicito dentro do range', async () => {
    const lines = Array.from({ length: 50 }, (_, i) => line({ uuid: `u-${i}`, type: 'user', message: { role: 'user', content: `x${i}` } }));
    const filePath = writeSession(lines);

    const result = await readSessionTail(filePath, { lines: 10 });
    expect(result!.requestedLines).toBe(10);
    expect(result!.returnedLines).toBe(10);
    expect(result!.entries[0]!.uuid).toBe('u-40');
    expect(result!.entries[9]!.uuid).toBe('u-49');
  });

  it('clamp: valor abaixo de 1 vira 1; acima de 1000 vira 1000', async () => {
    const filePath = writeSession([line({ uuid: 'u-0', type: 'user', message: { role: 'user', content: 'oi' } })]);

    expect((await readSessionTail(filePath, { lines: 0 }))!.requestedLines).toBe(1);
    expect((await readSessionTail(filePath, { lines: -5 }))!.requestedLines).toBe(1);
    expect((await readSessionTail(filePath, { lines: 5000 }))!.requestedLines).toBe(1000);
    expect((await readSessionTail(filePath, { lines: 1.9 }))!.requestedLines).toBe(1);
  });

  it('menos linhas no arquivo do que o solicitado devolve todas as validas', async () => {
    const lines = Array.from({ length: 5 }, (_, i) => line({ uuid: `u-${i}`, type: 'user', message: { role: 'user', content: `x${i}` } }));
    const filePath = writeSession(lines);

    const result = await readSessionTail(filePath, { lines: 50 });
    expect(result!.returnedLines).toBe(5);
    expect(result!.requestedLines).toBe(50);
  });
});

describe('readSessionTail — linha malformada (FR-003a)', () => {
  it('pula linha que nao parseia como JSON e conta em skippedLines, sem abortar', async () => {
    const filePath = writeSession([
      line({ uuid: 'u-0', type: 'user', message: { role: 'user', content: 'ok-1' } }),
      '{"uuid": "quebrada", NAO_E_JSON_VALIDO',
      line({ uuid: 'u-2', type: 'user', message: { role: 'user', content: 'ok-2' } }),
    ]);

    const result = await readSessionTail(filePath);
    expect(result!.skippedLines).toBe(1);
    expect(result!.returnedLines).toBe(2);
    expect(result!.entries.map((e) => e.uuid)).toEqual(['u-0', 'u-2']);
  });

  it('pula linha cujo JSON parseia mas nao e um objeto (array/numero/string solta)', async () => {
    const filePath = writeSession([line({ uuid: 'u-0', type: 'user', message: { role: 'user', content: 'ok' } }), '[1,2,3]', '42', '"solta"']);

    const result = await readSessionTail(filePath);
    expect(result!.skippedLines).toBe(3);
    expect(result!.returnedLines).toBe(1);
  });

  it('linhas em branco sao ignoradas sem contar como skipped', async () => {
    const filePath = writeSession([line({ uuid: 'u-0', type: 'user', message: { role: 'user', content: 'ok' } }), '', '   ']);
    const result = await readSessionTail(filePath);
    expect(result!.skippedLines).toBe(0);
    expect(result!.returnedLines).toBe(1);
  });
});

describe('readSessionTail — teto de bytes da resposta (Decision 9, FR-006)', () => {
  it('orcamento de bytes corta a selecao antes do teto de linhas quando as entradas sao grandes', async () => {
    // Cada entrada tera texto >= ENTRY_TEXT_MAX_BYTES, portanto cada uma
    // consome exatamente ENTRY_TEXT_MAX_BYTES (8 KiB) apos o corte por
    // entrada. RESPONSE_BYTE_BUDGET (256 KiB) / 8 KiB = 32 entradas cabem.
    const bigText = 'a'.repeat(ENTRY_TEXT_MAX_BYTES + 500);
    const total = 50;
    const lines = Array.from({ length: total }, (_, i) =>
      line({ uuid: `u-${i}`, type: 'user', message: { role: 'user', content: bigText } })
    );
    const filePath = writeSession(lines);

    const result = await readSessionTail(filePath, { lines: 200 });
    expect(result!.requestedLines).toBe(200);
    expect(result!.truncatedByBytes).toBe(true);
    expect(result!.returnedLines).toBe(Math.floor(RESPONSE_BYTE_BUDGET / ENTRY_TEXT_MAX_BYTES));
    // As mais recentes (u-18..u-49) devem ser as selecionadas.
    expect(result!.entries[result!.entries.length - 1]!.uuid).toBe(`u-${total - 1}`);
  });

  it('texto de uma entrada e truncado no teto por entrada, sinalizado por textTruncated', async () => {
    const bigText = 'b'.repeat(ENTRY_TEXT_MAX_BYTES * 3);
    const filePath = writeSession([
      line({ uuid: 'u-0', type: 'user', message: { role: 'user', content: bigText } }),
    ]);

    const result = await readSessionTail(filePath);
    const entry = result!.entries[0]!;
    expect(entry.textTruncated).toBe(true);
    expect(Buffer.byteLength(entry.text, 'utf8')).toBe(ENTRY_TEXT_MAX_BYTES);
  });

  it('texto dentro do teto por entrada nao e truncado', async () => {
    const filePath = writeSession([
      line({ uuid: 'u-0', type: 'user', message: { role: 'user', content: 'texto curto' } }),
    ]);
    const result = await readSessionTail(filePath);
    expect(result!.entries[0]!.textTruncated).toBe(false);
    expect(result!.entries[0]!.text).toBe('texto curto');
  });
});

describe('readSessionTail — ordem scrub-vs-truncamento (Decision 9, achado MEDIUM, task 3.3.2)', () => {
  it('segredo posicionado exatamente na fronteira do teto de bytes: o texto truncado ja vem redigido, e [REDACTED] conta para o teto', async () => {
    // Constroi um texto onde o segredo `password=hunter2-boundary-secret`
    // comeca poucos bytes ANTES do teto ENTRY_TEXT_MAX_BYTES e terminaria
    // DEPOIS dele se o corte rodasse sobre o texto CRU (truncar primeiro
    // cortaria o segredo ao meio e ele escaparia da redacao — a ressalva
    // que a task 3.3 existe para prevenir). Se a ordem estiver correta
    // (scrub ANTES do corte), o segredo inteiro e substituido por
    // `password=[REDACTED]` antes de qualquer corte acontecer, entao o
    // corte final opera sobre texto ja seguro.
    const secretAssignment = 'password=hunter2-boundary-secret-value';
    // Prefixo de enchimento com um espaco antes do segredo (o `\b` de
    // limite de palavra do redactor interno exige um separador
    // nao-alfanumerico ali) e um espaco depois (senao o `\S+` guloso do
    // redactor engoliria o sufixo inteiro como se fosse parte do valor
    // do segredo). O segredo comeca ~100 bytes antes do teto por
    // entrada — perto o bastante da fronteira para testar a ordem,
    // longe o bastante para que `[REDACTED]` caiba inteiro no texto
    // final truncado. O sufixo (`ENTRY_TEXT_MAX_BYTES` bytes de 'y')
    // garante que o texto ainda ultrapasse o teto MESMO apos a redacao
    // encurtar o segredo — provando que o corte final ainda roda.
    const prefixLen = ENTRY_TEXT_MAX_BYTES - 100;
    const prefix = `${'x'.repeat(prefixLen - 1)} `;
    const suffix = 'y'.repeat(ENTRY_TEXT_MAX_BYTES);
    const rawText = `${prefix}${secretAssignment} ${suffix}`;
    expect(Buffer.byteLength(rawText, 'utf8')).toBeGreaterThan(ENTRY_TEXT_MAX_BYTES);

    const filePath = writeSession([
      line({ uuid: 'u-0', type: 'user', message: { role: 'user', content: rawText } }),
    ]);

    const result = await readSessionTail(filePath);
    const entry = result!.entries[0]!;

    // O segredo NUNCA aparece cru no texto servido, mesmo truncado.
    expect(entry.text).not.toContain('hunter2-boundary-secret-value');
    // A redacao aconteceu ANTES do corte (prova da ordem task 3.3.1): se
    // o corte tivesse rodado primeiro sobre o rawText CRU, o resultado
    // truncado (so os primeiros ENTRY_TEXT_MAX_BYTES bytes do texto CRU)
    // conteria o segredo cortado ao meio, sem nenhum regex tendo rodado
    // sobre ele — logo sem "[REDACTED]" nenhum.
    expect(entry.text).toContain('[REDACTED]');
    // O corte ainda roda DEPOIS do scrub (nao vira no-op so porque o
    // scrub encurtou o texto) e [REDACTED] conta para o teto de bytes
    // por entrada (Decision 9) — o texto final nunca excede o teto.
    expect(entry.textTruncated).toBe(true);
    expect(Buffer.byteLength(entry.text, 'utf8')).toBeLessThanOrEqual(ENTRY_TEXT_MAX_BYTES);
  });
});

describe('readSessionTail — janela de leitura a partir do fim do arquivo (Decision 8)', () => {
  it('windowTruncated=false quando o arquivo cabe inteiro na janela', async () => {
    const filePath = writeSession([line({ uuid: 'u-0', type: 'user', message: { role: 'user', content: 'x' } })]);
    const result = await readSessionTail(filePath);
    expect(result!.windowTruncated).toBe(false);
  });

  it('arquivo maior que TAIL_READ_WINDOW_BYTES: windowTruncated=true e o conteudo final continua correto', async () => {
    // Gera linhas curtas o bastante em quantidade suficiente para ultrapassar
    // a janela de 1 MiB, sem depender de nenhuma linha individual grande.
    const approxLineBytes = 40;
    const totalLines = Math.ceil((TAIL_READ_WINDOW_BYTES * 1.5) / approxLineBytes);
    const lines: string[] = [];
    for (let i = 0; i < totalLines; i++) {
      lines.push(line({ uuid: `u-${i}`, type: 'user', message: { role: 'user', content: `linha numero ${i}` } }));
    }
    const filePath = writeSession(lines);

    const result = await readSessionTail(filePath, { lines: 200 });
    expect(result!.windowTruncated).toBe(true);
    expect(result!.returnedLines).toBe(200);
    expect(result!.skippedLines).toBe(0); // fragmento cortado pela janela foi descartado, nao contado como malformado
    expect(result!.entries[199]!.uuid).toBe(`u-${totalLines - 1}`); // a ultima linha do arquivo e sempre a mais recente
  });
});

describe('readSessionTail — achatamento de .message.content e normalizacao', () => {
  it('content string vira text diretamente; role vem de message.role', async () => {
    const filePath = writeSession([
      line({ uuid: 'u-0', type: 'assistant', timestamp: '2026-01-01T00:00:00Z', message: { role: 'assistant', content: 'ola' } }),
    ]);
    const result = await readSessionTail(filePath);
    const entry = result!.entries[0]!;
    expect(entry.role).toBe('assistant');
    expect(entry.timestamp).toBe('2026-01-01T00:00:00Z');
    expect(entry.text).toBe('ola');
  });

  it('content array: concatena apenas itens type=text, ignora thinking/tool_use/tool_result', async () => {
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
    const result = await readSessionTail(filePath);
    expect(result!.entries[0]!.text).toBe('parte 1\nparte 2');
  });

  it('sidecar do harness e FILTRADO, nao vira entrada vazia (0.34.0)', async () => {
    // Ate a 0.33.x isto virava uma linha com text:'' na tela. Medido num
    // transcript real: 280 de 636 linhas eram sidecar deste tipo.
    const filePath = writeSession([
      line({ uuid: 'u-0', type: 'file-history-snapshot' }),
      line({ uuid: 'u-1', type: 'attachment' }),
      line({ uuid: 'u-2', type: 'user', message: { role: 'user', content: 'unica conversa' } }),
    ]);
    const result = await readSessionTail(filePath);
    expect(result!.entries).toHaveLength(1);
    expect(result!.entries[0]!.text).toBe('unica conversa');
    // Descarte e REPORTADO, nunca silencioso.
    expect(result!.filteredEntries).toBe(2);
  });

  it('uuid/timestamp ausentes -> null, nunca undefined ou lancamento', async () => {
    const filePath = writeSession([line({ type: 'system', message: { role: 'system', content: 'aviso' } })]);
    const result = await readSessionTail(filePath);
    const entry = result!.entries[0]!;
    expect(entry.uuid).toBeNull();
    expect(entry.timestamp).toBeNull();
  });

  it('sessionId e session_id coexistindo na mesma linha nao vazam para o DTO da entrada', async () => {
    const filePath = writeSession([
      line({
        uuid: 'u-0',
        type: 'user',
        sessionId: '5f3c2e10-71a4-4b8e-9c1a-2d6f8b0a9e11',
        session_id: '5f3c2e10-71a4-4b8e-9c1a-2d6f8b0a9e11',
        message: { role: 'user', content: 'oi' },
      }),
    ]);
    const result = await readSessionTail(filePath);
    const entry = result!.entries[0]!;
    expect(Object.keys(entry).sort()).toEqual(
      ['kind', 'role', 'text', 'textTruncated', 'timestamp', 'toolName', 'type', 'uuid'].sort(),
    );
    expect((entry as Record<string, unknown>)['sessionId']).toBeUndefined();
    expect((entry as Record<string, unknown>)['session_id']).toBeUndefined();
  });
});

describe('readSessionTail — lastActivityAt (mtime)', () => {
  it('devolve lastActivityAt como ISO 8601 correspondente ao mtime do arquivo', async () => {
    const filePath = writeSession([line({ uuid: 'u-0', type: 'user', message: { role: 'user', content: 'oi' } })]);
    const result = await readSessionTail(filePath);
    expect(() => new Date(result!.lastActivityAt).toISOString()).not.toThrow();
    expect(new Date(result!.lastActivityAt).toISOString()).toBe(result!.lastActivityAt);
  });
});

/**
 * Chamadas de ferramenta (0.34.0). Ate a 0.33.x, `tool_use`/`tool_result`/
 * `thinking` NAO contribuiam para `text` — decisao de escopo explicita do
 * data-model.md ("nesta versao"). A medicao contra transcript real mostrou o
 * custo: de 356 mensagens num arquivo de 636 linhas, 324 rendiam texto vazio
 * (137 tool_use + 137 tool_result + 48 thinking).
 */
describe('readSessionTail — chamadas de ferramenta', () => {
  it('tool_use vira entrada com toolName e resumo de uma linha do input', async () => {
    const filePath = writeSession([
      line({
        uuid: 'u-0', type: 'assistant',
        message: { role: 'assistant', content: [
          { type: 'tool_use', name: 'Bash', input: { command: 'npm test', description: 'roda a suite' } },
        ] },
      }),
    ]);
    const e = (await readSessionTail(filePath))!.entries[0]!;
    expect(e.kind).toBe('tool_use');
    expect(e.toolName).toBe('Bash');
    // `command` tem precedencia sobre `description` na lista de chaves.
    expect(e.text).toBe('npm test');
  });

  it('tool_use sem chave conhecida no input ainda rende entrada — o NOME ja informa', async () => {
    const filePath = writeSession([
      line({
        uuid: 'u-0', type: 'assistant',
        message: { role: 'assistant', content: [
          { type: 'tool_use', name: 'FerramentaExotica', input: { algo_desconhecido: 42 } },
        ] },
      }),
    ]);
    const e = (await readSessionTail(filePath))!.entries[0]!;
    expect(e.kind).toBe('tool_use');
    expect(e.toolName).toBe('FerramentaExotica');
    expect(e.text).toBe('');
  });

  it('tool_result colapsa em marcador de tamanho — o conteudo NUNCA sai', async () => {
    const segredo = 'AKIAIOSFODNN7EXAMPLE conteudo enorme de retorno'.repeat(50);
    const filePath = writeSession([
      line({
        uuid: 'u-0', type: 'user',
        message: { role: 'user', content: [{ type: 'tool_result', content: segredo }] },
      }),
    ]);
    const e = (await readSessionTail(filePath))!.entries[0]!;
    expect(e.kind).toBe('tool_result');
    expect(e.text).toMatch(/^retorno de ferramenta · /);
    // Defesa dupla: nem o conteudo, nem qualquer fragmento dele, atravessa.
    expect(e.text).not.toContain('AKIAIOSFODNN7EXAMPLE');
    expect(e.text).not.toContain('conteudo enorme');
  });

  it('mensagem so com thinking e DESCARTADA e contabilizada', async () => {
    const filePath = writeSession([
      line({
        uuid: 'u-0', type: 'assistant',
        message: { role: 'assistant', content: [{ type: 'thinking', thinking: 'raciocinio interno longo' }] },
      }),
      line({ uuid: 'u-1', type: 'user', message: { role: 'user', content: 'oi' } }),
    ]);
    const r = (await readSessionTail(filePath))!;
    expect(r.entries).toHaveLength(1);
    expect(r.entries[0]!.text).toBe('oi');
    expect(r.filteredEntries).toBe(1);
  });

  it('texto tem PRECEDENCIA sobre tool_use na mesma mensagem', async () => {
    const filePath = writeSession([
      line({
        uuid: 'u-0', type: 'assistant',
        message: { role: 'assistant', content: [
          { type: 'text', text: 'vou rodar os testes' },
          { type: 'tool_use', name: 'Bash', input: { command: 'npm test' } },
        ] },
      }),
    ]);
    const e = (await readSessionTail(filePath))!.entries[0]!;
    // O que o agente DISSE e mais informativo que o que ele executou em seguida.
    expect(e.kind).toBe('text');
    expect(e.text).toBe('vou rodar os testes');
    expect(e.toolName).toBeNull();
  });

  it('resumo de tool_use e cortado curto, e o corte acontece DEPOIS do scrub', async () => {
    // Comando longo o suficiente para estourar o teto do resumo (240 B).
    const cmd = 'echo ' + 'a'.repeat(600);
    const filePath = writeSession([
      line({
        uuid: 'u-0', type: 'assistant',
        message: { role: 'assistant', content: [{ type: 'tool_use', name: 'Bash', input: { command: cmd } }] },
      }),
    ]);
    const e = (await readSessionTail(filePath))!.entries[0]!;
    expect(e.textTruncated).toBe(true);
    expect(Buffer.byteLength(e.text, 'utf8')).toBeLessThanOrEqual(240);
  });

  it('entrada de conversa comum mantem kind text e toolName null (nao-regressao)', async () => {
    const filePath = writeSession([
      line({ uuid: 'u-0', type: 'user', message: { role: 'user', content: 'mensagem simples' } }),
    ]);
    const e = (await readSessionTail(filePath))!.entries[0]!;
    expect(e.kind).toBe('text');
    expect(e.toolName).toBeNull();
  });
});
