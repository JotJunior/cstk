# Quickstart: validate-docs-sdd-profile

Cenarios de aceitacao executaveis para os perfis spec-profile e plan-profile.
Cada cenario e o oraculo de um teste em `tests/test_validate-sdd.sh`. O
formato de saida e os exit codes referenciados vivem em
`contracts/validate-sdd-cli.md`.

> Comando abreviado: `vsdd` = `global/skills/validate-documentation/scripts/validate-sdd.sh`.

## Cenario 1 — spec.md conformante (spec-profile, 0 erros) [US1, SC-001]

1. Apontar para um `spec.md` real e limpo:
   `vsdd docs/specs/enforced-guards/spec.md`
2. Perfil resolvido automaticamente por path → spec-profile.
3. **Expected**: nenhuma linha `FINDING|error|...`;
   `RESULT|...|profile=spec|errors=0|warnings=0`; **exit 0**.

## Cenario 2 — spec.md com secao obrigatoria ausente (spec-profile) [US1 AS2, FR-001]

1. Copiar `enforced-guards/spec.md` removendo a secao `## Success Criteria`.
2. `vsdd <copia-quebrada>.md --sdd-spec`
3. **Expected**: `FINDING|error|missing-section|...Success Criteria...`;
   `errors>=1`; **exit 1**.

## Cenario 3 — spec.md com termo de stack em Success Criteria (spec-profile) [US1 AS4, FR-002/FR-003]

1. Copiar um `spec.md` bom e inserir em Success Criteria um criterio com
   jargao tecnico (ex.: "API response time under 200ms", "React render <50ms")
   — os anti-padroes 1 e 2 de `specify/examples/spec-bad.md`.
2. `vsdd <copia>.md`
3. **Expected**: `FINDING|error|sc-not-measurable|...` e/ou
   `FINDING|error|impl-detail-in-spec|...`; **exit 1**.

## Cenario 4 — spec.md com > 3 `[NEEDS CLARIFICATION]` (spec-profile) [US1 AS3, FR-004]

1. Copiar um `spec.md` bom e adicionar um QUARTO marcador
   `[NEEDS CLARIFICATION]`.
2. `vsdd <copia>.md`
3. **Expected**: `FINDING|error|too-many-clarifications|...contagem=4...limite=3`;
   **exit 1**.

## Cenario 5 — spec.md com ID duplicado (spec-profile) [Gotcha da skill]

1. Copiar um `spec.md` bom e duplicar um `FR-001` (dois requisitos com o
   mesmo ID).
2. `vsdd <copia>.md`
3. **Expected**: `FINDING|error|duplicate-id|...FR-001...`; **exit 1**.

## Cenario 6 — avisos nao bloqueiam (spec-profile) [FR-005/006/007, FR-017]

1. Copiar um `spec.md` bom, remover nada obrigatorio, mas deixar uma secao
   `N/A` residual (FR-005) e um adjetivo vago sem metrica (FR-006).
2. `vsdd <copia>.md`
3. **Expected**: linhas `FINDING|warning|na-placeholder-section|...` e
   `FINDING|warning|vague-adjective|...`; `errors=0`; **exit 0** (Aviso
   recomenda, nao bloqueia — semantica de severidade da skill).

## Cenario 7 — plan.md conformante (plan-profile, 0 erros) [US2, SC-003]

1. `vsdd docs/specs/enforced-guards/plan.md`
2. Perfil resolvido automaticamente por path → plan-profile.
3. **Expected**: nenhuma linha `FINDING|error|...`;
   `RESULT|...|profile=plan|errors=0|warnings=0`; **exit 0**.

## Cenario 8 — plan.md com placeholder de template residual (plan-profile) [US2 AS4, FR-009]

1. Copiar um `plan.md` bom e deixar um `[FEATURE]` (ou `[DATE]`,
   `[short-name]`) literal, nao preenchido.
2. `vsdd <copia>.md`
3. **Expected**: `FINDING|error|template-placeholder|...[FEATURE]...`;
   **exit 1**.

## Cenario 9 — plan.md cita FR/SC inexistente na spec (plan-profile) [US2 AS2, FR-012]

1. Copiar um `plan.md` bom e inserir uma citacao a `FR-099` que NAO existe
   na `spec.md` da mesma feature.
2. `vsdd <copia>.md --spec docs/specs/enforced-guards/spec.md`
3. **Expected**: `FINDING|error|dangling-fr-sc-ref|...FR-099...`; **exit 1**.
4. **Nao-Expected** (fronteira FR-013): NENHUM achado sobre link/anchor
   quebrado no disco — isso e de `validate-docs-rendered`, nao deste perfil.

## Cenario 10 — contracts/*.md sem rotulo real-vs-proposto (plan-profile) [US2 AS3, FR-010/SC-004]

1. Copiar um `contracts/*.md` bom e remover o rotulo
   `[PROPOSTA — a validar na implementacao]` de uma entrada que documenta um
   endpoint/evento.
2. `vsdd <copia>.md --sdd-plan`
3. **Expected**: `FINDING|error|unlabeled-contract|...`; **exit 1**.

## Cenario 11 — perfil indeterminado fora da convencao (US3 AS3) [FR-016]

1. `vsdd /tmp/fora-da-convencao/spec.md` (arquivo chamado `spec.md` mas fora
   de `docs/specs/<feature>/`, sem flag).
2. **Expected**: mensagem em stderr "Perfil nao determinado ... use
   --sdd-spec ou --sdd-plan"; **exit 2**; NENHUM perfil aplicado
   silenciosamente.

## Cenario 12 — deteccao automatica por path (US3 AS1/AS2) [FR-015]

1. `vsdd docs/specs/enforced-guards/research.md` (sem flag).
2. **Expected**: perfil plan-profile aplicado automaticamente (research.md e
   da familia `/plan`); `RESULT|...|profile=plan|...`.
3. Repetir com `docs/specs/enforced-guards/spec.md` → `profile=spec`.
