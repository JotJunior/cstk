/**
 * Testes do redactor interno + cadeia de scrub (lib/secret-scrub.ts).
 * Ref: tasks.md FASE 3 (3.1.3, 3.2.7), quickstart.md Scenario 12/12.1/12.2.
 *
 * Cobre a matriz POSITIVA e NEGATIVA lado a lado (0.4) — um redactor que
 * so mede cobertura (positivos) passaria mesmo destruindo prosa legitima
 * (falsos-positivos); este arquivo exercita as 7 linhas (P1-P4, N1-N3)
 * como casos individuais, conforme quickstart.md Scenario 12.2.
 */
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import {
  scrubTextInternal,
  scrubTranscriptText,
  isSecretsFilterAvailable,
  resetSecretsFilterAvailabilityForTests,
  type ExecFileWithStdinFn,
  type ScrubFailureInfo,
} from '../../src/lib/secret-scrub.js';

const ORIGINAL_ENV = { ...process.env };

beforeEach(() => {
  resetSecretsFilterAvailabilityForTests();
});

afterEach(() => {
  process.env = { ...ORIGINAL_ENV };
  resetSecretsFilterAvailabilityForTests();
});

describe('scrubTextInternal — matriz positiva (Scenario 12.2, P1-P4)', () => {
  it('P1 — password= com valor curto (7 chars, abaixo do piso {20,} do cstk) e redigido', () => {
    expect(scrubTextInternal('password=hunter2')).toBe('password=[REDACTED]');
  });

  it('P2 — bloco BEGIN...END PRIVATE KEY inteiro vira um unico [REDACTED]', () => {
    const input = [
      '-----BEGIN RSA PRIVATE KEY-----',
      'MIIEowIBAAKCAQEA1234567890abcdefghijklmnopqrstuvwxyz',
      'AnotherLineOfBase64Content==',
      '-----END RSA PRIVATE KEY-----',
    ].join('\n');
    expect(scrubTextInternal(input)).toBe('[REDACTED]');
  });

  it('P3 — Authorization: Bearer <token longo> redige so o token', () => {
    const input = 'Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.abcdefghijklmnop.zzzzzzzzzzzzzzzz';
    expect(scrubTextInternal(input)).toBe('Authorization: Bearer [REDACTED]');
  });

  it('P4 — chave AWS AKIA... vira [REDACTED-AWS-KEY]', () => {
    expect(scrubTextInternal('AKIAIOSFODNN7EXAMPLE')).toBe('[REDACTED-AWS-KEY]');
  });
});

describe('scrubTextInternal — matriz negativa (Scenario 12.2, N1-N3): NUNCA redigir prosa', () => {
  it('N1 — mencao a "password" em prosa, sem valor associado, fica identica', () => {
    const input = 'o campo password e obrigatorio neste formulario';
    expect(scrubTextInternal(input)).toBe(input);
  });

  it('N2 — mencao a "token" em prosa, sem valor associado, fica identica', () => {
    const input = 'o token de acesso expira em 1 hora';
    expect(scrubTextInternal(input)).toBe(input);
  });

  it('N3 — mencao a "secret"/segredo em sentido comum, sem atribuicao, fica identica', () => {
    const input = 'nao existe segredo aqui';
    expect(scrubTextInternal(input)).toBe(input);
  });
});

describe('scrubTextInternal — entrada patologica (0.2.2/Scenario 12.1): teto de tempo', () => {
  it('blob adversarial de ~5MB com bloco de chave privada no meio completa em < 100ms', () => {
    const noise = 'a'.repeat(1000) + '\n';
    const before = noise.repeat(2500); // ~2.5MB de ruido antes do bloco
    const keyBlock = [
      '-----BEGIN RSA PRIVATE KEY-----',
      'X'.repeat(1000),
      '-----END RSA PRIVATE KEY-----',
      '',
    ].join('\n');
    const after = noise.repeat(2500); // ~2.5MB de ruido depois do bloco
    const input = before + keyBlock + after;
    expect(Buffer.byteLength(input, 'utf8')).toBeGreaterThan(4_500_000);

    const start = performance.now();
    const output = scrubTextInternal(input);
    const elapsedMs = performance.now() - start;

    expect(elapsedMs).toBeLessThan(100); // teto documentado em quickstart.md Scenario 12.1
    expect(output).toContain('[REDACTED]');
    expect(output).not.toContain('BEGIN RSA PRIVATE KEY');
    expect(output).not.toContain('X'.repeat(1000));
  });
});

function makeExecStub(behavior: 'success' | 'fail' | 'timeout', opts?: { stdout?: string }): ExecFileWithStdinFn {
  return async () => {
    if (behavior === 'success') {
      return { stdout: opts?.stdout ?? '' };
    }
    if (behavior === 'fail') {
      throw Object.assign(new Error('exit 1'), { code: 1, killed: false });
    }
    // timeout
    throw Object.assign(new Error('timeout'), { code: null, killed: true, signal: 'SIGTERM' });
  };
}

describe('scrubTranscriptText — cadeia completa (3.2.7, Scenario 12 Ramos A-C/F)', () => {
  it('Ramo B — cstk indisponivel (path inexistente) -> scrubMode internal, ainda redige', async () => {
    process.env['CSTK_SECRETS_FILTER'] = '/caminho/que/nao/existe/secrets-filter.sh';
    resetSecretsFilterAvailabilityForTests();
    expect(isSecretsFilterAvailable()).toBe(false);

    const result = await scrubTranscriptText('password=hunter2');
    expect(result.scrubMode).toBe('internal');
    expect(result.text).toBe('password=[REDACTED]');
  });

  it('CHK013 — CSTK_SECRETS_FILTER relativo e tratado como indisponivel (nunca resolvido por PATH)', () => {
    process.env['CSTK_SECRETS_FILTER'] = 'secrets-filter.sh';
    resetSecretsFilterAvailabilityForTests();
    expect(isSecretsFilterAvailable()).toBe(false);
  });

  it('Ramo A (simulado) — subprocesso sucesso -> scrubMode cstk+internal, passo 2 ainda roda sobre a saida', async () => {
    // Simula o cstk cobrindo AWS/Bearer mas deixando password= curto passar
    // (comportamento real medido em plan.md §Cobertura medida do filtro do cstk).
    const execImpl = makeExecStub('success', {
      stdout: '[REDACTED-AWS-KEY]\nBearer [REDACTED]\npassword=hunter2\n',
    });
    // Forca o caminho "disponivel": aponta para este proprio arquivo de teste
    // (existe e e realmente um arquivo — accessSync X_OK e o unico requisito
    // adicional verificado pelo modulo antes de decidir invocar execImpl).
    process.env['CSTK_SECRETS_FILTER'] = process.execPath; // executavel real qualquer — execImpl injetado ignora o conteudo
    resetSecretsFilterAvailabilityForTests();

    const result = await scrubTranscriptText('irrelevante — execImpl e quem decide a saida do passo 1', {
      execImpl,
    });
    expect(result.scrubMode).toBe('cstk+internal');
    // password=hunter2 sobreviveu ao passo 1 (simulado) mas o passo 2 (interno,
    // sempre encadeado — dec-032) pega: a diferenca central do Scenario 12.
    expect(result.text).toContain('password=[REDACTED]');
    expect(result.text).not.toContain('hunter2');
  });

  it('Ramo C — subprocesso falha (exit 1) apos escrever stdout parcial -> descarta parcial, usa entrada original', async () => {
    process.env['CSTK_SECRETS_FILTER'] = process.execPath; // executavel real qualquer — execImpl injetado ignora o conteudo
    resetSecretsFilterAvailabilityForTests();

    const execImpl = makeExecStub('fail');
    let loggedInfo: ScrubFailureInfo | null = null;
    const result = await scrubTranscriptText('password=hunter2', {
      execImpl,
      onSubprocessFailure: (info) => {
        loggedInfo = info;
      },
    });

    expect(result.scrubMode).toBe('internal');
    expect(result.text).toBe('password=[REDACTED]');
    expect(loggedInfo).toEqual({ exitCode: 1, timedOut: false });
  });

  it('Ramo F — timeout do subprocesso: log tem SOMENTE exitCode/timedOut, nunca conteudo', async () => {
    process.env['CSTK_SECRETS_FILTER'] = process.execPath; // executavel real qualquer — execImpl injetado ignora o conteudo
    resetSecretsFilterAvailabilityForTests();

    const execImpl = makeExecStub('timeout');
    const secretInput = 'password=hunter2-vazou-no-stdout';
    let loggedInfo: ScrubFailureInfo | null = null;
    let loggedRaw = '';
    const result = await scrubTranscriptText(secretInput, {
      execImpl,
      onSubprocessFailure: (info) => {
        loggedInfo = info;
        loggedRaw = JSON.stringify(info);
      },
    });

    expect(result.scrubMode).toBe('internal');
    expect(loggedInfo).toEqual({ exitCode: null, timedOut: true });
    // O segredo do stdin/stdout do subprocesso MUST NOT aparecer no log (3.2.4).
    expect(loggedRaw).not.toContain('hunter2');
    expect(Object.keys(loggedInfo as ScrubFailureInfo).sort()).toEqual(['exitCode', 'timedOut']);
  });

  it('nunca lanca mesmo com onSubprocessFailure ausente (usa logger default silencioso quanto a conteudo)', async () => {
    process.env['CSTK_SECRETS_FILTER'] = process.execPath; // executavel real qualquer — execImpl injetado ignora o conteudo
    resetSecretsFilterAvailabilityForTests();
    const execImpl = makeExecStub('fail');
    await expect(scrubTranscriptText('password=hunter2', { execImpl })).resolves.toMatchObject({
      scrubMode: 'internal',
    });
  });
});
