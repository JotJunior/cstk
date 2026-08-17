// test/exec-mapper-parity.test.ts — teste de paridade (task 3.10.3):
// para cada tool, TODO campo do `inputSchema` deve ter exatamente uma
// entrada na tabela `FIELD_TO_FLAG_TABLE` (runtime/exec.ts), e toda entrada
// com `flag != null` deve aparecer literalmente no codigo-fonte da tool
// correspondente (task 3.10.2 — previne "campo aceito pelo schema mas nunca
// repassado ao helper: falha em silencio", risco documentado em plan.md
// §Convencoes de Borda "Mapper layer (tool <-> helper)").
//
// Ref: docs/specs/state-mcp-server/tasks.md tarefa 3.10
//      docs/specs/state-mcp-server/plan.md §Convencoes de Borda

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { FIELD_TO_FLAG_TABLE } from "../src/runtime/exec.js";
import { recordSkillInputShape } from "../src/tools/record_skill.js";
import { recordDecisionInputShape } from "../src/tools/record_decision.js";
import { openWaveInputShape } from "../src/tools/open_wave.js";
import { recordTaskInputShape } from "../src/tools/record_task.js";
import { registerHumanBlockInputShape } from "../src/tools/register_human_block.js";
import { getStatusInputShape } from "../src/tools/get_status.js";
import { closeWaveInputShape } from "../src/tools/close_wave.js";
import { collectOptinsInputShape } from "../src/tools/collect_optins.js";

const SRC_TOOLS_DIR = join(process.cwd(), "src", "tools");

/**
 * Todas as tools ja tem `tools/<nome>.ts` desde a task 4.1 (`close_wave`
 * foi a ultima a ser criada) — conjunto vazio mantido (em vez de removido)
 * para que uma tool futura antecipada na tabela (mesmo padrao usado para
 * `close_wave` antes da task 4.1) tenha onde ser listada sem precisar
 * reintroduzir a variavel.
 */
const TOOLS_WITHOUT_SOURCE_YET = new Set<string>([]);

const SCHEMA_SHAPES: Readonly<Record<string, Readonly<Record<string, unknown>>>> = {
  record_skill: recordSkillInputShape,
  record_decision: recordDecisionInputShape,
  open_wave: openWaveInputShape,
  record_task: recordTaskInputShape,
  register_human_block: registerHumanBlockInputShape,
  get_status: getStatusInputShape,
  close_wave: closeWaveInputShape,
  collect_optins: collectOptinsInputShape,
};

test("exec-mapper-parity: FIELD_TO_FLAG_TABLE nao esta vazia", () => {
  assert.ok(FIELD_TO_FLAG_TABLE.length > 0);
});

for (const [tool, shape] of Object.entries(SCHEMA_SHAPES)) {
  test(`exec-mapper-parity: todo campo do inputSchema de ${tool} tem entrada na tabela (3.10.3)`, () => {
    const schemaFields = Object.keys(shape);
    const tableFieldsForTool = FIELD_TO_FLAG_TABLE.filter((m) => m.tool === tool).map(
      (m) => m.field,
    );
    const orphans = schemaFields.filter((f) => !tableFieldsForTool.includes(f));
    assert.deepEqual(
      orphans,
      [],
      `Campo(s) orfao(s) sem entrada em FIELD_TO_FLAG_TABLE para '${tool}': ${orphans.join(", ")}`,
    );
    // Reciproco: a tabela nao pode ter entrada para campo que nao existe
    // mais no schema (tabela desatualizada apos rename/remove de campo).
    const extra = tableFieldsForTool.filter((f) => !schemaFields.includes(f));
    assert.deepEqual(
      extra,
      [],
      `Entrada(s) na tabela sem campo correspondente no schema de '${tool}': ${extra.join(", ")}`,
    );
  });
}

test("exec-mapper-parity: cada par (tool, field) aparece EXATAMENTE uma vez na tabela", () => {
  const seen = new Set<string>();
  const duplicates: string[] = [];
  for (const entry of FIELD_TO_FLAG_TABLE) {
    const key = `${entry.tool}.${entry.field}`;
    if (seen.has(key)) duplicates.push(key);
    seen.add(key);
  }
  assert.deepEqual(duplicates, [], `Entrada(s) duplicada(s) na tabela: ${duplicates.join(", ")}`);
});

test("exec-mapper-parity (3.10.2): toda flag != null da tabela aparece literalmente no arquivo-fonte da tool (evita 'falha em silencio')", () => {
  const missing: string[] = [];
  const byTool = new Map<string, string[]>();
  for (const entry of FIELD_TO_FLAG_TABLE) {
    if (entry.flag === null) continue;
    if (TOOLS_WITHOUT_SOURCE_YET.has(entry.tool)) continue;
    if (!byTool.has(entry.tool)) byTool.set(entry.tool, []);
    byTool.get(entry.tool)!.push(entry.flag);
  }
  for (const [tool, flags] of byTool) {
    const filePath = join(SRC_TOOLS_DIR, `${tool}.ts`);
    const content = readFileSync(filePath, "utf8");
    for (const flag of flags) {
      // Flag deve aparecer como literal de string entre aspas duplas no
      // codigo-fonte (`args.push("--foo", ...)` ou dentro do array literal
      // `["--foo", ...]`) — se so aparecer comentada/documentada, o campo
      // nunca chega de fato ao helper (o risco que esta task fecha).
      const literal = `"${flag}"`;
      if (!content.includes(literal)) {
        missing.push(`${tool}: flag '${flag}' nao encontrada como literal no arquivo-fonte`);
      }
    }
  }
  assert.deepEqual(missing, [], missing.join("\n"));
});
