/**
 * decision-map-layout.ts
 *
 * Engine de layout determinístico para o Decision Map Panel.
 * Converte DecisionDTO[] → MapLayout — uma ÁRVORE de decisões.
 *
 * Modelo da árvore (mirror do mockup aprovado):
 *   - Cada decisão é um nó "decisão" (pill arredondado) — o ponto de decisão.
 *   - As `opcoes_consideradas` viram nós "opção" (retângulos) abaixo da decisão,
 *     ligados por arestas de galho (branch).
 *   - A opção ESCOLHIDA (`escolha`) é destacada e é dela que parte a aresta de
 *     espinha (spine) que desce para a PRÓXIMA decisão.
 *   - Após a última decisão, um nó terminal "Fim".
 *
 * A espinha serpenteia horizontalmente: a próxima decisão nasce sob a opção
 * escolhida da anterior (que pode estar à esquerda/centro/direita), formando os
 * galhos. As coordenadas são calculadas em espaço livre (x pode ficar negativo)
 * e depois normalizadas para caber no SVG com PADDING nas bordas.
 *
 * Zero dependências de React/DOM — módulo TypeScript puro, função pura.
 *
 * Ref: spec §FR-002, FR-003, FR-004, FR-005; data-model §Entity MapNode
 */

import type { DecisionDTO } from '@cstk-panel/shared-types';
import { chosenOptionIndex } from './decision-options.js';

// ---------------------------------------------------------------------------
// Constantes de geometria
// ---------------------------------------------------------------------------

/** Largura do nó decisão (pill). */
export const PILL_W = 176;
/** Altura do nó decisão (pill). */
export const PILL_H = 48;
/** Largura do nó opção (retângulo). */
export const OPT_W = 140;
/** Altura do nó opção (retângulo). */
export const OPT_H = 58;
/** Largura do nó terminal "Fim". */
export const END_W = 96;
/** Altura do nó terminal "Fim". */
export const END_H = 44;
/** Espaço horizontal entre opções irmãs. */
export const H_GAP = 24;
/** Espaço vertical entre níveis (pill→opções e opções→próxima pill). */
export const V_GAP = 54;
/** Padding em torno do conteúdo do SVG. */
export const PADDING = 24;

// ---------------------------------------------------------------------------
// Tipos de saída
// ---------------------------------------------------------------------------

export type MapNodeKind = 'decision' | 'option' | 'end';

/** Nó do mapa SVG. */
export interface MapNode {
  /** Chave estável: `dec::${i}` | `opt::${i}::${j}` | `end`. */
  key: string;
  /** Tipo do nó — controla forma (pill vs retângulo) e interação. */
  kind: MapNodeKind;
  /**
   * Texto principal exibido no nó (UNTRUSTED — renderizar via TextRaw).
   * decisão → `etapa` (ponto de decisão); opção → texto da opção; end → "Fim".
   */
  label: string | null;
  /**
   * DTO da decisão a que este nó pertence (`null` apenas no nó `end`).
   * Decisões e opções referenciam a MESMA decisão — clicar em qualquer um abre
   * o detalhe daquela decisão.
   */
  decision: DecisionDTO | null;
  /** Índice da decisão na cadeia (0-based). O nó `end` usa `n` (último+1). */
  decisionIndex: number;
  /** Para `option`: índice da opção dentro da decisão; senão -1. */
  optionIndex: number;
  /** Para `option`: é a opção escolhida (da qual parte a espinha). */
  chosen: boolean;
  /** Posição x do canto superior esquerdo (px). */
  x: number;
  /** Posição y do canto superior esquerdo (px). */
  y: number;
  /** Largura do nó (px). */
  w: number;
  /** Altura do nó (px). */
  h: number;
}

/** Aresta direcional entre dois nós. */
export interface MapEdge {
  from: string;
  to: string;
  /** `branch`: decisão→opção (curva). `spine`: opção escolhida→próxima decisão. */
  kind: 'branch' | 'spine';
}

/** Layout completo do mapa SVG. */
export interface MapLayout {
  nodes: MapNode[];
  edges: MapEdge[];
  svgWidth: number;
  svgHeight: number;
}

// ---------------------------------------------------------------------------
// Helpers de parsing (defensivos — dados UNTRUSTED de schema variável)
// ---------------------------------------------------------------------------

/**
 * Parseia `options` (JSON array cru, ex.: `["haiku","sonnet"]`) defensivamente.
 * Retorna `[]` para null, JSON inválido, ou valor não-array (FR-V3-005).
 */
export function parseOpcoes(raw: string | null): string[] {
  if (!raw) return [];
  try {
    const v: unknown = JSON.parse(raw);
    if (Array.isArray(v)) return v.map((x) => (x == null ? '' : String(x)));
  } catch {
    /* JSON inválido → sem opções (degradação graciosa) */
  }
  return [];
}

/**
 * Deriva as opções de uma decisão + qual é a escolhida.
 *
 * Regras (defensivas):
 *  - opções vêm de `options`; a escolhida é a que casa com `choice` via
 *    `chosenOptionIndex` — match tolerante a caixa/espaço, a prefixo de namespace
 *    (`model:sonnet` casa com a opção `sonnet`) e a elaborações da escolha. Isso
 *    evita ANEXAR uma 5ª opção fantasma (`model:sonnet`) quando `sonnet` já está
 *    na lista — o bug de "escolha aparece duas vezes" na árvore.
 *  - só se `choice` NÃO casa com nenhuma opção é que ela é anexada como opção
 *    escolhida (o usuário precisa ver a escolha real, ainda que não listada).
 *  - se `choice` existe e não há opções, vira a única opção (escolhida).
 *  - se `choice` é nula/vazia, `chosenIdx = -1` (sem escolha → espinha parte da
 *    própria decisão).
 */
export function deriveOptions(d: DecisionDTO): { opts: string[]; chosenIdx: number } {
  const opts = parseOpcoes(d.options);
  const esc = d.choice;
  if (esc == null || esc === '') {
    return { opts, chosenIdx: -1 };
  }
  let chosenIdx = chosenOptionIndex(opts, esc);
  if (chosenIdx === -1) {
    opts.push(esc);
    chosenIdx = opts.length - 1;
  }
  return { opts, chosenIdx };
}

// ---------------------------------------------------------------------------
// Engine principal
// ---------------------------------------------------------------------------

/**
 * Calcula o layout em árvore do mapa de decisões.
 *
 * Caso base: `computeLayout([])` → layout vazio.
 *
 * @param items DecisionDTO[] na ordem da cadeia (rowid ASC — premissa do backend).
 */
export function computeLayout(items: DecisionDTO[]): MapLayout {
  if (items.length === 0) {
    return { nodes: [], edges: [], svgWidth: 0, svgHeight: 0 };
  }

  const n = items.length;
  const nodes: MapNode[] = [];
  const edges: MapEdge[] = [];
  /** Por decisão: chave do nó de onde a espinha continua para a próxima. */
  const spineFrom: string[] = new Array(n).fill('');

  let y = PADDING;
  let center = 0; // centro x da decisão corrente (coordenadas livres)

  for (let i = 0; i < n; i++) {
    const d = items[i]!;
    const pillKey = `dec::${i}`;

    nodes.push({
      key: pillKey,
      kind: 'decision',
      label: d.stage ?? 'decisão',
      decision: d,
      decisionIndex: i,
      optionIndex: -1,
      chosen: false,
      x: center - PILL_W / 2,
      y,
      w: PILL_W,
      h: PILL_H,
    });

    const { opts, chosenIdx } = deriveOptions(d);

    if (opts.length > 0) {
      const groupW = opts.length * OPT_W + (opts.length - 1) * H_GAP;
      const optY = y + PILL_H + V_GAP;
      const firstLeft = center - groupW / 2;

      let spineKey = pillKey;
      let nextCenter = center;

      for (let j = 0; j < opts.length; j++) {
        const optLeft = firstLeft + j * (OPT_W + H_GAP);
        const optKey = `opt::${i}::${j}`;
        const chosen = j === chosenIdx;

        nodes.push({
          key: optKey,
          kind: 'option',
          label: opts[j] ?? '',
          decision: d,
          decisionIndex: i,
          optionIndex: j,
          chosen,
          x: optLeft,
          y: optY,
          w: OPT_W,
          h: OPT_H,
        });
        edges.push({ from: pillKey, to: optKey, kind: 'branch' });

        if (chosen) {
          spineKey = optKey;
          nextCenter = optLeft + OPT_W / 2;
        }
      }

      spineFrom[i] = spineKey;
      center = chosenIdx >= 0 ? nextCenter : center;
      y = optY + OPT_H + V_GAP;
    } else {
      // Decisão sem opções nem escolha registrada: espinha parte da própria pill.
      spineFrom[i] = pillKey;
      y = y + PILL_H + V_GAP;
    }
  }

  // Arestas de espinha: opção escolhida da decisão i → pill da decisão i+1.
  for (let i = 0; i < n - 1; i++) {
    edges.push({ from: spineFrom[i]!, to: `dec::${i + 1}`, kind: 'spine' });
  }

  // Nó terminal "Fim" sob a opção escolhida da última decisão.
  const endKey = 'end';
  nodes.push({
    key: endKey,
    kind: 'end',
    label: 'Fim',
    decision: null,
    decisionIndex: n,
    optionIndex: -1,
    chosen: false,
    x: center - END_W / 2,
    y,
    w: END_W,
    h: END_H,
  });
  edges.push({ from: spineFrom[n - 1]!, to: endKey, kind: 'spine' });

  // Normalização: desloca tudo para que minX = PADDING (a espinha pode ter
  // derivado para x negativo) e calcula dimensões do SVG.
  let minX = Infinity;
  let maxRight = -Infinity;
  let maxBottom = -Infinity;
  for (const nd of nodes) {
    if (nd.x < minX) minX = nd.x;
    if (nd.x + nd.w > maxRight) maxRight = nd.x + nd.w;
    if (nd.y + nd.h > maxBottom) maxBottom = nd.y + nd.h;
  }
  const dx = PADDING - minX;
  for (const nd of nodes) {
    nd.x += dx;
  }

  const svgWidth = maxRight - minX + PADDING * 2;
  const svgHeight = maxBottom + PADDING;

  return { nodes, edges, svgWidth, svgHeight };
}

// ---------------------------------------------------------------------------
// Helpers de navegação do painel de detalhe (navegam entre DECISÕES)
// ---------------------------------------------------------------------------

/** Chave da pill da decisão anterior à do nó atual, ou null. */
export function prevKey(nodes: MapNode[], currentKey: string): string | null {
  const cur = nodes.find((nd) => nd.key === currentKey);
  if (!cur) return null;
  const prev = nodes.find((nd) => nd.kind === 'decision' && nd.decisionIndex === cur.decisionIndex - 1);
  return prev?.key ?? null;
}

/** Chave da pill da próxima decisão à do nó atual, ou null. */
export function nextKey(nodes: MapNode[], currentKey: string): string | null {
  const cur = nodes.find((nd) => nd.key === currentKey);
  if (!cur) return null;
  const nxt = nodes.find((nd) => nd.kind === 'decision' && nd.decisionIndex === cur.decisionIndex + 1);
  return nxt?.key ?? null;
}
