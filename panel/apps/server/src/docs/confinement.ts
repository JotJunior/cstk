/**
 * Confinamento anti-traversal e anti-symlink para LEITURA de conteudo de
 * artefatos de documentacao (research.md Decision 7; spec.md FR-009; gate
 * owasp-security finding HIGH). Task 3.4.
 *
 * A listagem (artifact-map.ts, task 3.1) so reporta METADADOS (existencia,
 * nome, mtime) e nao aplica este guard — o risco real (leitura arbitraria
 * de arquivo local) so existe quando BYTES sao retornados ao cliente, o
 * que so acontece no endpoint de conteudo (task 3.3). Por isso o guard
 * vive isolado aqui e e chamado exclusivamente antes de `readFileSync`.
 *
 * Postura CONSERVADORA (mais estrita que o minimo literal da task 3.4.2
 * "rejeitar symlink apontando para fora da raiz"): QUALQUER entrada
 * symlinkada e rejeitada incondicionalmente, mesmo que o alvo esteja
 * dentro da raiz permitida. Nenhum artefato de documentacao legitimo
 * gerado pela pipeline SDD e um symlink; a mera presenca de um e sempre
 * suspeita (o `.md` e conteudo gerado por agente = UNTRUSTED, Principio
 * V) e simplifica o raciocinio de seguranca (sem necessidade de resolver
 * o alvo do link para decidir).
 */
import { lstatSync, readFileSync, realpathSync, statSync } from 'node:fs';
import { resolve, sep } from 'node:path';

/**
 * Cap de tamanho de leitura (Decision 7 — "evitar exaustao de memoria em
 * arquivo grande"). 5 MiB. Validado empiricamente (2026-07-15): o maior
 * artefato `.md` REAL observado neste repo (`find docs/specs -name
 * "*.md" | xargs wc -c | sort -rn`) e `docs/specs/new-schema/tasks.md`
 * com 39761 bytes (~39KB) — 5 MiB da > 100x de folga sobre o maior
 * artefato real hoje, sem abrir uma janela de exaustao de memoria via
 * arquivo gigante plantado.
 */
export const MAX_ARTIFACT_BYTES = 5 * 1024 * 1024;

export type ConfinementFailureReason =
  | 'not-found'         // ausente, ou race TOCTOU (existia na listagem, sumiu na leitura)
  | 'symlink-rejected'   // entrada e symlink (QUALQUER symlink, nao so o que escapa a raiz)
  | 'path-escapes-root'  // path.resolve/realpath do candidato cai fora de `root`
  | 'too-large';         // st.size > maxBytes

export type ConfinementResult =
  | { ok: true; realPath: string; sizeBytes: number; mtimeMs: number }
  | { ok: false; reason: ConfinementFailureReason };

function withinBoundary(root: string, candidate: string): boolean {
  const boundary = root.endsWith(sep) ? root : root + sep;
  return candidate === root || candidate.startsWith(boundary);
}

/**
 * Resolve e confina `candidate` sob `root` (Decision 7). NUNCA lanca
 * (Principio II) — qualquer falha vira `{ok:false, reason}`.
 *
 * Controles, na ordem:
 * 1. `path.resolve` de ambos + comparacao de prefixo na FRONTEIRA de
 *    `path.sep` (evita `/root` casar `/root-evil` via `startsWith` ingenuo).
 * 2. `lstat` do candidato: QUALQUER symlink e rejeitado incondicionalmente
 *    (nao segue para decidir se o alvo esta dentro/fora — ver nota de
 *    postura conservadora no topo do arquivo).
 * 3. `fs.realpath` do candidato E da raiz — re-confina o caminho REAL
 *    (defesa em profundidade contra ancestrais symlinkados nao cobertos
 *    pelo lstat do passo 2, que so olha o arquivo final).
 * 4. Cap de tamanho (`maxBytes`, default `MAX_ARTIFACT_BYTES` — parametro
 *    exposto so para os testes injetarem um cap pequeno sem escrever
 *    arquivos de 5 MiB).
 */
export function confineArtifactPath(
  root: string,
  candidate: string,
  maxBytes: number = MAX_ARTIFACT_BYTES
): ConfinementResult {
  const resolvedRoot = resolve(root);
  const resolvedCandidate = resolve(candidate);

  if (!withinBoundary(resolvedRoot, resolvedCandidate)) {
    return { ok: false, reason: 'path-escapes-root' };
  }

  let lst;
  try {
    lst = lstatSync(resolvedCandidate);
  } catch {
    return { ok: false, reason: 'not-found' };
  }
  if (lst.isSymbolicLink()) {
    return { ok: false, reason: 'symlink-rejected' };
  }
  if (!lst.isFile()) {
    return { ok: false, reason: 'not-found' };
  }

  let realCandidate: string;
  let realRoot: string;
  try {
    realCandidate = realpathSync(resolvedCandidate);
    realRoot = realpathSync(resolvedRoot);
  } catch {
    return { ok: false, reason: 'not-found' };
  }
  if (!withinBoundary(realRoot, realCandidate)) {
    return { ok: false, reason: 'path-escapes-root' };
  }

  const st = statSync(realCandidate);
  if (st.size > maxBytes) {
    return { ok: false, reason: 'too-large' };
  }

  return { ok: true, realPath: realCandidate, sizeBytes: st.size, mtimeMs: st.mtimeMs };
}

/**
 * Le o conteudo markdown bruto de um artefato JA confinado (task 3.3.2).
 * Chamador DEVE ter chamado `confineArtifactPath` antes e checado
 * `ok:true` — esta funcao nao repete os controles de seguranca.
 */
export function readConfinedArtifact(realPath: string): string {
  return readFileSync(realPath, 'utf-8');
}
