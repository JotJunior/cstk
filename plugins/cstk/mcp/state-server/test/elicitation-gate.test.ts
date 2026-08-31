// test/elicitation-gate.test.ts — cobertura de runtime/elicitation-gate.ts
// (gate owasp-security, achado L3; docs/specs/mcp-elicitation-optins/tasks.md
// FASE 9, task 9.5.1): allowlist mecanica de quais tools podem chamar
// `elicitInput` — hoje SOMENTE `collect_optins`.

import { test } from "node:test";
import assert from "node:assert/strict";
import type { ElicitResult } from "@modelcontextprotocol/sdk/types.js";
import {
  ELICITATION_ALLOWED_TOOLS,
  ElicitationNotAllowedError,
  grantElicitationAccess,
  type ElicitationAllowedTool,
  type ElicitationServer,
} from "../src/runtime/elicitation-gate.js";

test("ELICITATION_ALLOWED_TOOLS: allowlist fechada contem EXATAMENTE 'collect_optins' — nenhuma das outras 7 tools", () => {
  assert.deepEqual(ELICITATION_ALLOWED_TOOLS, ["collect_optins"]);
});

test("grantElicitationAccess: tool permitida ('collect_optins') devolve um ElicitationServer que delega ao bruto", async () => {
  let capabilitiesCalled = false;
  let elicitCalled = false;
  const raw: ElicitationServer = {
    getClientCapabilities: () => {
      capabilitiesCalled = true;
      return { elicitation: {} };
    },
    elicitInput: async () => {
      elicitCalled = true;
      return { action: "cancel", content: {} } as ElicitResult;
    },
  };

  const granted = grantElicitationAccess("collect_optins", raw);
  granted.getClientCapabilities();
  await granted.elicitInput({ message: "m", requestedSchema: { type: "object", properties: {} } } as never);

  assert.equal(capabilitiesCalled, true);
  assert.equal(elicitCalled, true);
});

test("grantElicitationAccess (adversarial, SEC L3): tool FORA da allowlist -- mesmo via cast contornando o tipo estatico -- lanca ElicitationNotAllowedError em RUNTIME", () => {
  const raw: ElicitationServer = {
    getClientCapabilities: () => ({ elicitation: {} }),
    elicitInput: async () => ({ action: "cancel", content: {} }) as unknown as Promise<ElicitResult> as never,
  };

  // A barreira de COMPILACAO (uniao fechada de 1 literal) so protege
  // chamadas escritas com o tipo correto — este teste prova a barreira de
  // RUNTIME, que sobrevive a um `as` que contorne o tipo estatico (ex.:
  // uma tool futura que herde `tool` de uma variavel `string` generica em
  // vez de um literal).
  const notAllowed = "record_skill" as unknown as ElicitationAllowedTool;

  assert.throws(
    () => grantElicitationAccess(notAllowed, raw),
    (err: unknown) => err instanceof ElicitationNotAllowedError && /record_skill/.test(err.message),
  );
});

test("grantElicitationAccess: e passthrough puro -- devolve a MESMA referencia recebida (nenhum wrapper/proxy que possa divergir)", () => {
  const raw: ElicitationServer = {
    getClientCapabilities: () => ({ elicitation: {} }),
    elicitInput: async () => ({ action: "cancel", content: {} }) as ElicitResult,
  };

  const granted = grantElicitationAccess("collect_optins", raw);

  assert.equal(granted, raw);
});
