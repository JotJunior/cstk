# Sugestoes do Agente-00C — feat-session-tail-20260827T030838Z

Total: 1 sugestoes registradas.

## sug-001 — skill `agente-00c-runtime` — severidade: aviso

**Criada em**: 2026-08-27T12:06:27Z

**Issue aberta**: (nenhuma)

**Diagnostico**:

commit-mode.sh stage-derived so trata como 'derivado da onda' arquivos untracked ausentes do commit-baseline.txt; se o orquestrador criar arquivos ANTES de state-ondas.sh start/open_wave rodar (ex.: subagente escreve codigo antes de o Loop principal formalmente abrir a onda), a baseline os captura como pre-existentes e stage-derived os pula silenciosamente (exit 0, so o subconjunto tracked staged), exigindo git add explicito de fallback.

**Proposta**:

Documentar explicitamente na secao 7.bis/10.qui do orquestrador que 'snapshot'/'start' (que gera commit-baseline.txt) MUST rodar ANTES de qualquer Write/Edit de arquivo novo na onda, nao apenas antes do commit; ou stage-derived emitir um aviso quando encontrar arquivos novos NAO staged que tenham mtime posterior ao commit-baseline.txt, para o orquestrador nao precisar descobrir isso por diff manual.

**Referencias**:

- apps/server/src/lib/sessions-root.ts
- apps/server/test/lib/sessions-root.test.ts
- .claude/skills/agente-00c-runtime/scripts/commit-mode.sh

---

