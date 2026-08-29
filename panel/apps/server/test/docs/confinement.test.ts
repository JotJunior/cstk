/**
 * Testes de seguranca de confineArtifactPath (task 3.4.4).
 *
 * Ref: research.md Decision 7 (FR-009); gate owasp-security finding HIGH;
 * quickstart.md Cenario 9 ("path traversal rejeitado").
 *
 * Cobre: leitura valida dentro da raiz; traversal via `..`; symlink
 * escapando a raiz; symlink DENTRO da raiz (tambem rejeitado — postura
 * conservadora, ver comentario em confinement.ts); cap de tamanho
 * (injetado via parametro `maxBytes` para nao precisar escrever um
 * arquivo de 5 MiB real no teste).
 */
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, symlinkSync, realpathSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { confineArtifactPath, readConfinedArtifact, MAX_ARTIFACT_BYTES } from '../../src/docs/confinement.js';

let tmpRoot: string;
let root: string;

beforeEach(() => {
  // realpathSync logo apos criar: no macOS, os.tmpdir() ("/var/folders/...")
  // e um symlink para "/private/var/folders/...". confineArtifactPath ja
  // faz realpath internamente (Decision 7) — sem isto aqui, comparacoes
  // diretas de string (`toBe`) quebram por causa do prefixo "/private"
  // que so aparece do lado do resultado, nao do lado do path construido
  // manualmente no teste.
  const rawTmpRoot = mkdtempSync(join(tmpdir(), 'cstk-confinement-'));
  tmpRoot = realpathSync(rawTmpRoot);
  root = join(tmpRoot, 'docs', 'specs', 'minha-feature');
  mkdirSync(root, { recursive: true });
});

afterEach(() => {
  rmSync(tmpRoot, { recursive: true, force: true });
});

describe('confineArtifactPath — caminho valido', () => {
  it('retorna ok:true para um arquivo regular dentro da raiz', () => {
    const filePath = join(root, 'spec.md');
    writeFileSync(filePath, '# spec');
    const result = confineArtifactPath(root, filePath);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.realPath).toBe(filePath);
      expect(result.sizeBytes).toBeGreaterThan(0);
    }
  });

  it('confina corretamente artefatos em subdiretorio (contracts/)', () => {
    mkdirSync(join(root, 'contracts'), { recursive: true });
    const filePath = join(root, 'contracts', 'docs-api.md');
    writeFileSync(filePath, '# contrato');
    const result = confineArtifactPath(root, filePath);
    expect(result.ok).toBe(true);
  });
});

describe('confineArtifactPath — path traversal (Cenario 9)', () => {
  it('rejeita candidato que escapa a raiz via ".." (path-escapes-root)', () => {
    const outsideFile = join(tmpRoot, 'evil.md');
    writeFileSync(outsideFile, '# evil');
    const traversalCandidate = join(root, '..', '..', '..', 'evil.md');
    const result = confineArtifactPath(root, traversalCandidate);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe('path-escapes-root');
  });

  it('nao confunde raiz com prefixo textual similar ("root" vs "root-evil")', () => {
    const rootEvil = `${root}-evil`;
    mkdirSync(rootEvil, { recursive: true });
    const filePath = join(rootEvil, 'spec.md');
    writeFileSync(filePath, '# nao deveria ser confinavel por "root"');
    const result = confineArtifactPath(root, filePath);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe('path-escapes-root');
  });

  it('retorna not-found para candidato inexistente dentro da raiz (nunca lanca)', () => {
    const missing = join(root, 'nao-existe.md');
    expect(() => confineArtifactPath(root, missing)).not.toThrow();
    const result = confineArtifactPath(root, missing);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe('not-found');
  });
});

describe('confineArtifactPath — symlink (Decision 7, gate owasp HIGH)', () => {
  it('rejeita symlink apontando para FORA da raiz', () => {
    const outsideFile = join(tmpRoot, 'segredo.md');
    writeFileSync(outsideFile, '# segredo fora da raiz');
    const linkPath = join(root, 'evil.md');
    symlinkSync(outsideFile, linkPath);

    const result = confineArtifactPath(root, linkPath);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe('symlink-rejected');
  });

  it('rejeita symlink mesmo quando o ALVO esta dentro da raiz (postura conservadora)', () => {
    const realFile = join(root, 'real.md');
    writeFileSync(realFile, '# real');
    const linkPath = join(root, 'link-interno.md');
    symlinkSync(realFile, linkPath);

    const result = confineArtifactPath(root, linkPath);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe('symlink-rejected');
  });

  it('nunca retorna conteudo para um symlink escapando a raiz (garantia fim-a-fim)', () => {
    const outsideFile = join(tmpRoot, 'etc-passwd-fake.md');
    writeFileSync(outsideFile, 'CONTEUDO_SECRETO_FORA_DA_RAIZ');
    const linkPath = join(root, 'passwd.md');
    symlinkSync(outsideFile, linkPath);

    const result = confineArtifactPath(root, linkPath);
    expect(result.ok).toBe(false);
    // Garantia central: nenhum caminho de codigo chama readConfinedArtifact
    // quando ok:false — o proprio tipo (union discriminada) impede acessar
    // `realPath` fora do branch ok:true, entao o teste de tipo + o assert
    // acima juntos cobrem a garantia "nunca conteudo fora da fronteira".
  });
});

describe('confineArtifactPath — cap de tamanho (Decision 7)', () => {
  it('usa MAX_ARTIFACT_BYTES = 5 MiB como default', () => {
    expect(MAX_ARTIFACT_BYTES).toBe(5 * 1024 * 1024);
  });

  it('rejeita arquivo que excede o cap injetado (too-large)', () => {
    const filePath = join(root, 'grande.md');
    writeFileSync(filePath, 'x'.repeat(100));
    const result = confineArtifactPath(root, filePath, 10); // cap artificial de 10 bytes
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe('too-large');
  });

  it('aceita arquivo dentro do cap injetado', () => {
    const filePath = join(root, 'pequeno.md');
    writeFileSync(filePath, 'x'.repeat(5));
    const result = confineArtifactPath(root, filePath, 10);
    expect(result.ok).toBe(true);
  });
});

describe('readConfinedArtifact', () => {
  it('le o conteudo bruto (UTF-8) de um artefato ja confinado', () => {
    const filePath = join(root, 'spec.md');
    writeFileSync(filePath, '# Titulo\n\nConteudo com acentuação.');
    const result = confineArtifactPath(root, filePath);
    expect(result.ok).toBe(true);
    if (result.ok) {
      const content = readConfinedArtifact(result.realPath);
      expect(content).toBe('# Titulo\n\nConteudo com acentuação.');
    }
  });
});
