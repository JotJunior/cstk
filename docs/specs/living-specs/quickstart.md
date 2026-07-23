# Quickstart: living-specs

**Feature**: `living-specs` | **Date**: 2026-07-23

Cenarios de validacao dos fluxos criticos. Todos executaveis em fixture git
temporaria (padrao do harness `tests/run.sh`); nenhum exige rede.

## Cenario 1 — Delta ADDED aplicada no archive (happy path US1+US2)

1. Criar fixture com `docs/specs/feat-x/spec.md` contendo
   `## Delta Requirements` -> `### Capability: alpha` -> `#### ADDED` com
   `- **FR-001**: comportamento novo` (mesmo id da secao Requirements).
2. Rodar `delta-gate.sh docs/specs/feat-x/spec.md --corpus-dir docs/specs/current`
   -> **Expected**: `RESULT|...|delta=present|errors=0`, exit 0
   (`corpus-missing` apenas info).
3. Rodar `delta-merge.sh docs/specs/feat-x/spec.md --feature feat-x --date 2026-07-23`
   -> **Expected**: exit 0; `docs/specs/current/alpha.md` criado com
   `### FR-001`, texto e `*Introduzida por: feat-x (2026-07-23)*`
   (US2 cenario 4 + SC-004).
4. Mover a feature para `_archived/2026-07-23-feat-x/`
   -> **Expected**: fluxo existente intacto; corpus permanece (FR-006).

## Cenario 2 — MODIFIED e REMOVED sobre corpus existente (US2)

1. Partir do corpus do Cenario 1.
2. Spec `feat-y` com MODIFIED `FR-001` (novo texto) na capability `alpha`.
3. `delta-merge.sh ... --feature feat-y` -> **Expected**: texto de
   `### FR-001` substituido, id preservado,
   `*Ultima modificacao: feat-y (...)*` presente, `*Introduzida por:
   feat-x*` intacta.
4. Spec `feat-z` com REMOVED `FR-001` -> **Expected**: entrada movida para
   `## Removed Requirements` com `*Removida por: feat-z*` + motivo — nunca
   desaparecimento silencioso (FR-004).

## Cenario 3 — Gate bloqueia archive sem delta; skip libera (US3)

1. Spec sem secao `## Delta Requirements`.
2. `delta-gate.sh spec.md` -> **Expected**:
   `FINDING|error|delta-missing|...`, `RESULT|...|delta=missing`, exit 1.
3. Adicionar `## Delta Requirements` + `**Skip**: feature doc-only — jot,
   2026-07-23`.
4. Re-rodar gate -> **Expected**: exit 0, `RESULT|...|delta=skip`
   (auditavel, distinguivel de aplicacao normal — FR-011).
5. `delta-merge.sh` sobre a mesma spec -> **Expected**: exit 0 sem tocar o
   corpus (`delta=skip`).

## Cenario 4 — Referencia invalida e conflito bloqueiam sem mutacao (error case, clarify)

1. Spec com MODIFIED `FR-099` (id inexistente na capability `alpha`).
2. `delta-gate.sh` -> **Expected**: `FINDING|error|ref-not-found|...`,
   exit 1 (FR-013, US3 cenario 4).
3. Spec com ADDED `FR-001` (id ja ativo em `alpha`) -> **Expected**:
   `added-collision`, exit 1.
4. Spec multi-capability onde a 2a capability tem erro:
   `delta-merge.sh` -> **Expected**: exit 1 e NENHUM arquivo do corpus
   alterado (atomicidade total — hash dos arquivos antes == depois).
5. Determinismo: rodar o gate 2x sobre o mesmo input -> **Expected**:
   stdout byte-identico (edge case da spec).

## Cenario 5 — Staging por allowlist nunca varre untracked alheio (US4, FR-017)

1. Fixture git com repo inicializado, `alien.pptx` untracked na raiz
   (analogo ao incidente real) e atomic-commit habilitado no state.
2. `commit-mode.sh snapshot --state-dir SD --projeto-alvo-path PAP`
   -> **Expected**: `SD/commit-baseline.txt` contem `alien.pptx`.
3. Simular etapa: criar `docs/specs/feat-x/plan.md`; rodar
   `stage-derived --scope-dir docs/specs/feat-x ...` + commit
   -> **Expected**: commit contem so `docs/specs/feat-x/plan.md`;
   `alien.pptx` segue untracked (SC-003).
4. Simular task: criar `cli/lib/new-helper.sh` (pos-snapshot); rodar
   `stage-derived` sem scope-dir -> **Expected**: `new-helper.sh` staged,
   `alien.pptx` fora.
5. Roundtrip real (nao mock): inspecionar `git show --name-only HEAD` no
   fixture -> **Expected**: nome do alheio ausente em TODOS os commits
   gerados.

## Cenario 6 — Allowlist vazia: nenhum commit (FR-016)

1. Fixture limpa (nenhuma mudanca alem de `alien.pptx` untracked
   pre-baseline).
2. `stage-derived ...` -> **Expected**: exit 3, index intacto
   (`git diff --cached` vazio), nenhum commit criado.
3. Baseline AUSENTE + untracked novo presente -> **Expected**: untracked
   fora do staging, aviso em stderr, jamais fallback amplo (fail-closed).

## Cenario 7 — Wave-commit do agente-00c endurecido

1. Fixture com `alien.pptx` untracked pre-existente + mudanca tracked em
   `docs/specs/feat-x/spec.md`.
2. `state-ondas.sh git-commit --state-dir SD --projeto-alvo-path PAP
   --motivo teste` -> **Expected**: commit contem a mudanca tracked;
   `alien.pptx` permanece untracked (site 3 da research Decision 1
   convergido ao mesmo helper).
