// runtime/identifiers.ts — allowlist patterns para campos de identificador
// (SEC-M2), compartilhados entre tools. Extraidos de `tools/record_skill.ts`
// (onde `IDENTIFIER_PATTERN`/`DECISION_ID_PATTERN` viviam duplicados) para
// que as tools novas de F3 (record_decision, open_wave, record_task,
// register_human_block, get_status) usem a MESMA fonte — evita a mesma
// regra divergir entre arquivos ao longo do tempo (mesmo racional de
// `runtime/sanitize.ts`, task 2.3). Consolidacao COMPLETA do mapper
// (campo -> flag) fica para a task 3.10 (F3); este arquivo cobre apenas
// os padroes de validacao de forma (schema), nao o mapeamento de flags.
//
// Ref: docs/specs/state-mcp-server/contracts/mcp-tools.md §SEC-M2

/**
 * Token de identificador generico (skill, task_id): primeiro caractere
 * OBRIGATORIAMENTE alfanumerico, ate 64 chars no total [VERIFICADO:
 * global/skills/agente-00c-runtime/scripts/state-ondas.sh:228-235,
 * funcao `_so_is_stage_token`]. Regra transversal do contrato: nenhum
 * campo de identificador pode comecar com `-` (nao pode ser confundido
 * com uma flag do helper).
 */
export const IDENTIFIER_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/;

/**
 * Formato de id de Decisao emitido por `state-decisions.sh register`
 * [VERIFICADO: `contracts/mcp-tools.md`, mesmo formato usado nesta
 * propria execucao, ex.: dec-049].
 */
export const DECISION_ID_PATTERN = /^dec-[0-9]{1,9}$/;

/**
 * Formato de id de onda emitido por `state-ondas.sh start`
 * [VERIFICADO: `state-ondas.sh:588` e `_state-ondas-db.sh:182`, ambos
 * `printf 'onda-%03d' N` — mesmo formato nos dois backends json/sqlite].
 */
export const WAVE_ID_PATTERN = /^onda-[0-9]{3,}$/;

/**
 * Formato de id de bloqueio humano emitido por `bloqueios.sh register`
 * [VERIFICADO: `bloqueios.sh` `_bl_next_block_id`/`_bl_db_next_block_num_expr`,
 * `printf 'block-%03d' N`].
 */
export const BLOCK_ID_PATTERN = /^block-[0-9]{3,}$/;

/** Byte NUL literal, usado para rejeitar `touched_files[]` com NUL embutido. */
const NUL_CHAR = String.fromCharCode(0);

/**
 * `touched_files[]` MUST ser path relativo (SEC-M2): rejeita absoluto,
 * `..` (traversal) e byte NUL. Nao valida existencia do arquivo — so a
 * FORMA do path.
 */
export function isSafeRelativePath(path: string): boolean {
  if (path.length === 0) return false;
  if (path.startsWith("/")) return false;
  if (path.includes(NUL_CHAR)) return false;
  if (path === ".." || path.startsWith("../") || path.includes("/../") || path.endsWith("/..")) {
    return false;
  }
  return true;
}
