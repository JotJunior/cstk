// test/sanitize.test.ts — cobertura das primitivas de saneamento
// compartilhadas (runtime/sanitize.ts, extraidas de tools/record_skill.ts
// na task 2.3 para reuso por audit/log.ts).

import { test } from "node:test";
import assert from "node:assert/strict";
import {
  stripControlChars,
  truncateUtf8ByteBudget,
  truncateCodePoints,
  sanitizeForLlmContext,
} from "../src/runtime/sanitize.js";

test("stripControlChars: substitui caracteres de controle por espaco, preserva texto normal", () => {
  const withControl = "linha1" + String.fromCharCode(0) + "linha2" + String.fromCharCode(127);
  const cleaned = stripControlChars(withControl);
  assert.equal(cleaned, "linha1 linha2 ");
});

test("stripControlChars: preserva newline/tab (nao fazem parte da classe removida)", () => {
  const text = "a\nb\tc";
  assert.equal(stripControlChars(text), "a\nb\tc");
});

test("truncateUtf8ByteBudget: nao corta caractere multi-byte ao meio (emoji na fronteira do teto)", () => {
  // "a" (1 byte) repetido + um emoji (4 bytes UTF-8). Teto = 3 bytes: o
  // emoji nao cabe inteiro, entao deve ser omitido por completo (nunca
  // cortado pela metade).
  const text = "aa" + "\u{1F600}"; // "aa" + emoji (4 bytes)
  const truncated = truncateUtf8ByteBudget(text, 3);
  assert.equal(truncated, "aa");
  // Resultado deve ser UTF-8 valido (Array.from nao produz surrogate solto).
  assert.equal(Buffer.byteLength(truncated, "utf8"), 2);
});

test("truncateUtf8ByteBudget: texto menor que o teto retorna intacto", () => {
  assert.equal(truncateUtf8ByteBudget("abc", 100), "abc");
});

test("truncateCodePoints: trunca por CONTAGEM de code points, nao bytes", () => {
  const text = "\u{1F600}".repeat(10); // 10 emojis, 4 bytes cada = 40 bytes
  const truncated = truncateCodePoints(text, 3);
  assert.equal(Array.from(truncated).length, 3);
});

test("truncateCodePoints: texto menor que o teto retorna intacto", () => {
  assert.equal(truncateCodePoints("abc", 100), "abc");
});

test("sanitizeForLlmContext: strip + trim + truncate, com fallback quando fica vazio", () => {
  const onlyControl = String.fromCharCode(0) + String.fromCharCode(1);
  assert.equal(
    sanitizeForLlmContext(onlyControl, 2048),
    "helper falhou sem mensagem de erro utilizavel",
  );
});

test("sanitizeForLlmContext: respeita teto de bytes informado", () => {
  const long = "x".repeat(5000);
  const result = sanitizeForLlmContext(long, 2048);
  assert.equal(Buffer.byteLength(result, "utf8"), 2048);
});
