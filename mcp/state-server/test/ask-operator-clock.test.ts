// test/ask-operator-clock.test.ts — cobertura da politica de relogios da
// superficie `ask_operator` (task 1.3.4).
//
// Cobre: faixa derivada correta para clientTimeoutMs=300000 -> [60000,240000];
// valor requisitado fora da faixa cai no default (nao clampa); combinacao
// explicitamente ilegal recusa subir (BootTimeoutError); env ausente assume
// 300000 + emite exatamente 1 aviso; as duas constantes de 60000 nunca
// compartilham identidade (regressao textual/estrutural, nao so numerica).

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  ASK_MIN_TIMEOUT_MS,
  CLOCK_SAFETY_MARGIN_MS,
  DEFAULT_CLIENT_TIMEOUT_MS,
  BootTimeoutError,
  deriveAskTimeoutRange,
  parseAskTimeoutMs,
  resolveAndValidateBootTimeout,
  resolveClientTimeoutMs,
  validateClientTimeoutMs,
} from "../src/tools/ask-operator-clock.js";

test("deriveAskTimeoutRange — clientTimeoutMs=300000 produz [60000,240000], default=240000", () => {
  const range = deriveAskTimeoutRange(300000);
  assert.equal(range.min, 60000);
  assert.equal(range.max, 240000);
  assert.equal(range.default, 240000);
});

test("parseAskTimeoutMs — requested dentro da faixa e preservado", () => {
  assert.equal(parseAskTimeoutMs(300000, "120000"), 120000);
  assert.equal(parseAskTimeoutMs(300000, 120000), 120000);
});

test("parseAskTimeoutMs — requested undefined/vazio cai no default (topo da faixa)", () => {
  assert.equal(parseAskTimeoutMs(300000, undefined), 240000);
  assert.equal(parseAskTimeoutMs(300000, ""), 240000);
});

test("parseAskTimeoutMs — requested abaixo do piso cai no default, NUNCA clampa para a borda", () => {
  // Precedente verificado: parseElicitTimeoutMs nao clampa, cai no default.
  assert.equal(parseAskTimeoutMs(300000, "1000"), 240000);
  assert.notEqual(parseAskTimeoutMs(300000, "1000"), 60000);
});

test("parseAskTimeoutMs — requested acima do teto cai no default, NUNCA clampa para a borda", () => {
  assert.equal(parseAskTimeoutMs(300000, "999999"), 240000);
});

test("parseAskTimeoutMs — requested acima do teto com default != max cai no default (nao no max)", () => {
  // client_timeout_ms maior faz default (== max) divergir de um teto
  // hipotetico anterior — usamos um requested MUITO acima do max para
  // provar que o valor devolvido e sempre `range.default`, nunca uma borda
  // calculada de outra forma.
  const range = deriveAskTimeoutRange(600000);
  assert.equal(parseAskTimeoutMs(600000, "10000000"), range.default);
  assert.equal(range.default, range.max);
});

test("parseAskTimeoutMs — requested nao-numerico cai no default", () => {
  assert.equal(parseAskTimeoutMs(300000, "abc"), 240000);
  assert.equal(parseAskTimeoutMs(300000, "60000.5"), 240000);
  assert.equal(parseAskTimeoutMs(300000, "-1000"), 240000);
});

test("validateClientTimeoutMs — combinacao legal (folga >= 60000) aprova", () => {
  const result = validateClientTimeoutMs(300000);
  assert.equal(result.ok, true);
  assert.equal(result.reason, undefined);
});

test("validateClientTimeoutMs — combinacao EXPLICITAMENTE ilegal reprova com motivo", () => {
  // clientTimeoutMs=30000 => max = 30000-60000 = -30000 < min=60000 (ilegal)
  const result = validateClientTimeoutMs(30000);
  assert.equal(result.ok, false);
  assert.match(result.reason ?? "", /ilegal/);
  assert.match(result.reason ?? "", /CSTK_CLIENT_TOOL_TIMEOUT_MS/);
});

test("validateClientTimeoutMs — fronteira exata (folga == 60000) aprova", () => {
  // clientTimeoutMs = ASK_MIN_TIMEOUT_MS + CLOCK_SAFETY_MARGIN_MS => max == min
  const boundary = ASK_MIN_TIMEOUT_MS + CLOCK_SAFETY_MARGIN_MS;
  const result = validateClientTimeoutMs(boundary);
  assert.equal(result.ok, true);
});

test("resolveClientTimeoutMs — env ausente assume DEFAULT_CLIENT_TIMEOUT_MS e sinaliza usedDefault", () => {
  const r1 = resolveClientTimeoutMs(undefined);
  assert.equal(r1.clientTimeoutMs, DEFAULT_CLIENT_TIMEOUT_MS);
  assert.equal(r1.usedDefault, true);

  const r2 = resolveClientTimeoutMs("");
  assert.equal(r2.clientTimeoutMs, DEFAULT_CLIENT_TIMEOUT_MS);
  assert.equal(r2.usedDefault, true);
});

test("resolveClientTimeoutMs — env invalida (nao-numerica, negativa, zero) degrada para default", () => {
  assert.equal(resolveClientTimeoutMs("abc").usedDefault, true);
  assert.equal(resolveClientTimeoutMs("-5000").usedDefault, true);
  assert.equal(resolveClientTimeoutMs("0").usedDefault, true);
});

test("resolveClientTimeoutMs — env valida e preservada sem usar default", () => {
  const r = resolveClientTimeoutMs("450000");
  assert.equal(r.clientTimeoutMs, 450000);
  assert.equal(r.usedDefault, false);
});

test("resolveAndValidateBootTimeout — env ausente NUNCA recusa subir, emite EXATAMENTE 1 aviso", () => {
  const warnings: string[] = [];
  const result = resolveAndValidateBootTimeout({}, (msg) => warnings.push(msg));
  assert.equal(result.clientTimeoutMs, DEFAULT_CLIENT_TIMEOUT_MS);
  assert.equal(warnings.length, 1);
  assert.match(warnings[0]!, /CSTK_CLIENT_TOOL_TIMEOUT_MS/);
});

test("resolveAndValidateBootTimeout — env valida legal nao emite aviso", () => {
  const warnings: string[] = [];
  const result = resolveAndValidateBootTimeout(
    { CSTK_CLIENT_TOOL_TIMEOUT_MS: "300000" },
    (msg) => warnings.push(msg),
  );
  assert.equal(result.clientTimeoutMs, 300000);
  assert.equal(warnings.length, 0);
});

test("resolveAndValidateBootTimeout — combinacao explicitamente ilegal lanca BootTimeoutError e recusa subir", () => {
  assert.throws(
    () => resolveAndValidateBootTimeout({ CSTK_CLIENT_TOOL_TIMEOUT_MS: "30000" }, () => {}),
    BootTimeoutError,
  );
});

test("regressao: ASK_MIN_TIMEOUT_MS e CLOCK_SAFETY_MARGIN_MS sao numericamente iguais mas NUNCA compartilham identidade (dois const distintos, sem alias)", () => {
  // Numericamente iguais, de proposito (coincidencia declarada em research.md
  // Decision 7) — mas devem ser DOIS bindings `const` distintos no source,
  // nunca um alias do outro (ex.: `export const CLOCK_SAFETY_MARGIN_MS =
  // ASK_MIN_TIMEOUT_MS;`), o que corromperia um ajuste independente futuro.
  assert.equal(ASK_MIN_TIMEOUT_MS, 60000);
  assert.equal(CLOCK_SAFETY_MARGIN_MS, 60000);

  const source = readFileSync(
    join(process.cwd(), "src", "tools", "ask-operator-clock.ts"),
    "utf8",
  );
  // Cada constante tem sua PROPRIA declaracao `export const NOME = 60000;`
  // — nenhuma referencia a outra constante do par no lado direito.
  assert.match(source, /export const ASK_MIN_TIMEOUT_MS\s*=\s*60000;/);
  assert.match(source, /export const CLOCK_SAFETY_MARGIN_MS\s*=\s*60000;/);
  assert.doesNotMatch(
    source,
    /export const CLOCK_SAFETY_MARGIN_MS\s*=\s*ASK_MIN_TIMEOUT_MS/,
  );
  assert.doesNotMatch(
    source,
    /export const ASK_MIN_TIMEOUT_MS\s*=\s*CLOCK_SAFETY_MARGIN_MS/,
  );
  // Nenhum comentario deve dizer "mesmo valor de" acoplando as duas —
  // acoplamento textual e o modo de falha descrito no contrato (R-CLOCK-7).
  assert.doesNotMatch(source, /mesmo valor d[ae] (ASK_MIN_TIMEOUT_MS|CLOCK_SAFETY_MARGIN_MS)/i);
});
