/**
 * `converge-report.md` NAO e um relatorio em prosa, apesar do nome: e um
 * ledger append-only de vereditos em comentarios HTML. Servido cru, o card de
 * documentacao marca `produced: true` e o operador recebe uma PAGINA EM
 * BRANCO — Markdown nao renderiza comentario.
 *
 * Medido em 2026-08-27: os 6 arquivos existentes em todos os projetos locais
 * tinham ZERO linhas de conteudo visivel.
 */
import { describe, it, expect } from 'vitest';
import { renderConvergeLedger } from '../../src/docs/converge-ledger.js';

/** Conteudo LITERAL de docs/specs/doctor-shadowed-scope/converge-report.md. */
const REAL = [
  '<!-- converge-status: outcome=actionable; provenance=gate; at=2026-08-28T01:26:39Z; actionable=1; tasks-digest=3a6aa2070be8 -->',
  '<!-- converge-status: outcome=clean; provenance=gate; at=2026-08-28T02:07:50Z; actionable=0; tasks-digest=f9b9beaf7884 -->',
  '',
].join('\n');

describe('renderConvergeLedger', () => {
  it('traduz o ledger real numa tabela com uma linha por veredito', () => {
    const out = renderConvergeLedger(REAL)!;
    expect(out).not.toBeNull();
    expect(out).toContain('| Quando | Veredito | Acionáveis | Origem | Digest do tasks.md |');
    expect(out).toContain('2026-08-28T01:26:39Z');
    expect(out).toContain('2026-08-28T02:07:50Z');
    expect(out).toContain('3a6aa2070be8');
    expect(out).toContain('2 verificação(ões)');
  });

  it('o veredito MAIS RECENTE define a situacao atual, nao o primeiro', () => {
    const out = renderConvergeLedger(REAL)!;
    expect(out).toContain('Situação atual: convergida');
  });

  it('situacao actionable reporta a contagem, sem afirmar convergencia', () => {
    const soPendente =
      '<!-- converge-status: outcome=actionable; provenance=gate; at=2026-08-28T01:26:39Z; actionable=3; tasks-digest=abc -->';
    const out = renderConvergeLedger(soPendente)!;
    expect(out).toContain('`actionable`');
    expect(out).toContain('3 item(ns)');
    expect(out).not.toContain('convergida');
  });

  it('campo ausente no marcador vira travessao — NUNCA um valor inventado', () => {
    const out = renderConvergeLedger('<!-- converge-status: outcome=clean -->')!;
    expect(out).toContain('| — |');
  });

  it('devolve null quando nao ha marcador algum (arquivo serve cru)', () => {
    expect(renderConvergeLedger('# Relatorio\n\nTexto normal.')).toBeNull();
    expect(renderConvergeLedger('')).toBeNull();
  });

  it('PRESERVA prosa que exista junto dos marcadores — traduzir nunca esconde', () => {
    const misto = [
      '<!-- converge-status: outcome=clean; at=2026-01-01T00:00:00Z; actionable=0 -->',
      '',
      '## Achado importante',
      'Texto que um humano escreveu e nao pode sumir.',
    ].join('\n');
    const out = renderConvergeLedger(misto)!;
    expect(out).toContain('Achado importante');
    expect(out).toContain('Texto que um humano escreveu e nao pode sumir.');
    // E a tabela vai junto, nao no lugar.
    expect(out).toContain('| Quando |');
  });

  it('ignora comentario HTML que nao e marcador de converge-status', () => {
    expect(renderConvergeLedger('<!-- outro comentario qualquer -->')).toBeNull();
  });
});
