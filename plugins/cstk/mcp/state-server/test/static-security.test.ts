// test/static-security.test.ts — assercao estatica obrigatoria (SEC-H1,
// task 2.2.7): o codigo-fonte do servidor NUNCA pode invocar um helper
// POSIX por `exec()`, `execSync()`, `spawn(..., { shell: true })`, ou
// template string montando a linha de comando inteira. Falha o build/CI se
// algum desses padroes aparecer em src/**/*.ts — nao depende de o revisor
// humano lembrar de checar a cada PR.
//
// Ref: docs/specs/state-mcp-server/contracts/mcp-tools.md
//   §SEC-H1 (HIGH) — invocacao por argv, jamais por shell

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, extname } from "node:path";

const SRC_DIR = join(process.cwd(), "src");

function listTsFiles(dir: string): string[] {
  const entries = readdirSync(dir);
  const files: string[] = [];
  for (const entry of entries) {
    const full = join(dir, entry);
    const st = statSync(full);
    if (st.isDirectory()) {
      files.push(...listTsFiles(full));
    } else if (extname(full) === ".ts") {
      files.push(full);
    }
  }
  return files;
}

const SOURCE_FILES = listTsFiles(SRC_DIR);

// Comentarios (// ..., /** ... */, linhas de continuacao "* ...") podem
// legitimamente MENCIONAR os padroes proibidos ao documentar a propria
// proibicao (ex.: o cabecalho deste arquivo, ou runtime/exec.ts). A
// assercao estatica MUST varrer apenas codigo executavel — nao a prosa que
// o descreve. Heuristica simples de linha (nao um parser de TS completo,
// mas suficiente para uma base de codigo pequena e com estilo consistente).
function stripCommentLines(content: string): string {
  return content
    .split("\n")
    .filter((line) => {
      const trimmed = line.trim();
      return !(
        trimmed.startsWith("//") ||
        trimmed.startsWith("/**") ||
        trimmed.startsWith("/*") ||
        trimmed.startsWith("*")
      );
    })
    .join("\n");
}

test("static-security: ha pelo menos 1 arquivo .ts em src/ para varrer (guarda contra falso-positivo por diretorio vazio)", () => {
  assert.ok(SOURCE_FILES.length > 0, "src/ nao deveria estar vazio nesta task");
});

test("SEC-H1: nenhum arquivo de src/ chama exec( ou execSync(", () => {
  // \b garante que `execFile(`/`execFileSync(` NAO casam (o caractere apos
  // "exec" precisa ser um `(` diretamente, nao "File").
  const banned = /\b(exec|execSync)\s*\(/;
  const offenders: string[] = [];
  for (const file of SOURCE_FILES) {
    const content = stripCommentLines(readFileSync(file, "utf8"));
    for (const line of content.split("\n")) {
      if (banned.test(line)) offenders.push(`${file}: ${line.trim()}`);
    }
  }
  assert.deepEqual(offenders, [], `Uso proibido de exec()/execSync() (SEC-H1):\n${offenders.join("\n")}`);
});

test("SEC-H1: nenhum arquivo de src/ passa shell:true/shell: true para spawn/execFile", () => {
  const banned = /shell\s*:\s*true/;
  const offenders: string[] = [];
  for (const file of SOURCE_FILES) {
    const content = stripCommentLines(readFileSync(file, "utf8"));
    for (const line of content.split("\n")) {
      if (banned.test(line)) offenders.push(`${file}: ${line.trim()}`);
    }
  }
  assert.deepEqual(offenders, [], `Uso proibido de shell:true (SEC-H1):\n${offenders.join("\n")}`);
});

test("SEC-H1: nenhuma chamada de processo (exec/execSync/spawn/execFile/spawnSync) usa template string como comando", () => {
  // Casa o padrao perigoso especifico: backtick IMEDIATAMENTE como primeiro
  // argumento de uma funcao de processo — ex.: `exec(\`cmd ${x}\`)`. Nao
  // bane backticks em geral (usados legitimamente para mensagens de erro
  // interpoladas nesta base de codigo).
  const banned = /\b(exec|execSync|spawn|spawnSync|execFile|execFileSync)\s*\(\s*`/;
  const offenders: string[] = [];
  for (const file of SOURCE_FILES) {
    const content = stripCommentLines(readFileSync(file, "utf8"));
    for (const line of content.split("\n")) {
      if (banned.test(line)) offenders.push(`${file}: ${line.trim()}`);
    }
  }
  assert.deepEqual(
    offenders,
    [],
    `Template string montando comando de processo (SEC-H1):\n${offenders.join("\n")}`,
  );
});

test("SEC-H1 (positivo): a unica invocacao de child_process usa execFile com shell:false explicito", () => {
  const execFilePath = join(SRC_DIR, "runtime", "exec.ts");
  const content = readFileSync(execFilePath, "utf8");
  assert.match(content, /import \{ execFile \} from "node:child_process";/);
  assert.match(content, /shell:\s*false/);
});
