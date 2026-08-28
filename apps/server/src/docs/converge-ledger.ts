/**
 * Renderizacao do `converge-report.md`.
 *
 * POR QUE ESTE MODULO EXISTE
 *
 * Apesar do nome, `converge-report.md` NAO e um relatorio em prosa: e um
 * LEDGER append-only de vereditos, gravado como comentarios HTML e lido por
 * `converge-status.sh check`. Medido em 2026-08-27 nos 6 arquivos existentes
 * em todos os projetos locais: TODOS tinham zero linhas de conteudo visivel.
 *
 * Consequencia de servi-lo cru: o card de documentacao marca `produced: true`,
 * o operador clica, e recebe uma pagina em BRANCO — Markdown nao renderiza
 * comentario. Parece defeito e nao informa nada.
 *
 * Os marcadores, porem, carregam observabilidade real: veredito, quando,
 * quantos itens acionaveis, e um digest do `tasks.md` da epoca. Da para ler a
 * historia da feature convergindo ao longo das ondas. Este modulo traduz isso
 * para uma tabela legivel.
 *
 * INVARIANTE: NUNCA descarta conteudo. Se o arquivo tiver prosa de verdade
 * (hoje nenhum tem, mas o formato pode mudar), ela e PRESERVADA e a tabela vai
 * junto. Transformar para exibir e legitimo; esconder o que o autor escreveu
 * nao e.
 */

/** Um veredito do ledger. Campos ausentes viram `null` — nunca inventados. */
export interface ConvergeMarker {
  outcome: string | null;
  provenance: string | null;
  at: string | null;
  actionable: string | null;
  tasksDigest: string | null;
}

const MARKER_RE = /^\s*<!--\s*converge-status:\s*(.+?)\s*-->\s*$/;

function parseMarkerLine(line: string): ConvergeMarker | null {
  const m = MARKER_RE.exec(line);
  if (m === null) return null;
  const fields = new Map<string, string>();
  for (const pair of m[1]!.split(';')) {
    const idx = pair.indexOf('=');
    if (idx <= 0) continue;
    fields.set(pair.slice(0, idx).trim(), pair.slice(idx + 1).trim());
  }
  return {
    outcome: fields.get('outcome') ?? null,
    provenance: fields.get('provenance') ?? null,
    at: fields.get('at') ?? null,
    actionable: fields.get('actionable') ?? null,
    tasksDigest: fields.get('tasks-digest') ?? null,
  };
}

/** `-` para ausente: a tabela nunca preenche um campo que o marcador nao tinha. */
function cell(v: string | null): string {
  return v === null || v === '' ? '—' : v;
}

/**
 * Traduz o ledger em Markdown legivel. Devolve `null` quando nao ha marcador
 * algum — nesse caso o chamador serve o conteudo original intacto (o arquivo
 * pode ser um relatorio de verdade num formato futuro).
 */
export function renderConvergeLedger(content: string): string | null {
  const lines = content.split('\n');
  const markers: ConvergeMarker[] = [];
  const rest: string[] = [];

  for (const line of lines) {
    const parsed = parseMarkerLine(line);
    if (parsed !== null) markers.push(parsed);
    else rest.push(line);
  }
  if (markers.length === 0) return null;

  const last = markers[markers.length - 1]!;
  const out: string[] = ['# Convergência'];

  out.push('');
  out.push(
    last.outcome === 'clean'
      ? '**Situação atual: convergida.** A última verificação não encontrou divergência acionável entre o que spec, plano e tarefas afirmam e o que o código faz.'
      : `**Situação atual: \`${cell(last.outcome)}\`**, com ${cell(last.actionable)} item(ns) acionável(is) na última verificação.`,
  );

  out.push('');
  out.push(`## Histórico (${markers.length} verificação(ões))`);
  out.push('');
  out.push('| Quando | Veredito | Acionáveis | Origem | Digest do tasks.md |');
  out.push('| --- | --- | --- | --- | --- |');
  for (const m of markers) {
    out.push(
      `| ${cell(m.at)} | \`${cell(m.outcome)}\` | ${cell(m.actionable)} | ${cell(m.provenance)} | \`${cell(m.tasksDigest)}\` |`,
    );
  }

  out.push('');
  out.push(
    '> Este arquivo é um registro append-only gravado pela etapa `converge` e lido por `converge-status.sh`. ' +
      'A tabela acima é uma leitura dos marcadores — o arquivo em si não contém texto corrido.',
  );

  const leftover = rest.join('\n').trim();
  if (leftover !== '') {
    // Preserva prosa eventual — traduzir para exibir nunca pode esconder o
    // que o autor de fato escreveu.
    out.push('');
    out.push('## Conteúdo do arquivo');
    out.push('');
    out.push(leftover);
  }

  return out.join('\n');
}
