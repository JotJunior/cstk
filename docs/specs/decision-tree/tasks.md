# Tasks: decision-tree

**Feature**: `decision-tree`
**Spec**: [spec.md](./spec.md)
**Status**: Concluída (retroativa — skill já implementada e testada)

> Estas tarefas documentam, em retrospecto, o trabalho já entregue em
> `global/skills/decision-tree/`. Todas estão marcadas como concluídas porque a
> implementação e os testes precederam a criação desta spec (correção de
> conformidade com o Princípio I). Servem de baseline para evoluções futuras.

## Fase 1 — Contrato e gerador

- [x] **T-001** Definir o contrato de entrada (`.decisoes[]` + `.execucao`) e o
  formato do payload `{ meta, decisoes }`. → `scripts/render-decision-tree.sh`
  (`_dt_jq_program`). [FR-001..FR-003]
- [x] **T-002** Implementar dispatch POSIX (`render`, `-h/--help`, subcomando
  desconhecido) com exit codes 0/1/2. [FR-009, IDT-3]
- [x] **T-003** Parsing de flags `--state` (obrigatória), `--output`,
  `--title`, com validações (arquivo existe, JSON legível, `jq` presente,
  `.decisoes[]` não vazio). [FR-001, FR-005, FR-006, FR-008]
- [x] **T-004** Extração via `jq` + escape `</` → `<\/` no payload. [FR-007]

## Fase 2 — Renderização HTML

- [x] **T-005** Template HTML autocontido (CSS + SVG + painel + zoom), sem CDN.
  [FR-004, IDT-4, SC-4]
- [x] **T-006** Layout do tronco cronológico, faixas de etapa, selos de score e
  nó de conclusão. [FR-004]
- [x] **T-007** Fallback de robustez para `escolha` fora de
  `opcoes_consideradas[]` (tronco segue pelo eixo). [FR-002]

## Fase 3 — Qualidade e conformidade

- [x] **T-008** `tests/test_render-decision-tree.sh` (18 cenários) + fixture
  `tests/fixtures/decision-tree-state/state.json`. [SC-1]
- [x] **T-009** Garantir IDT-1 (read-only) e IDT-2 (determinístico byte-a-byte)
  via cenários dedicados. [IDT-1, IDT-2]
- [x] **T-010** `shellcheck -s sh` limpo + sem órfão em
  `tests/run.sh --check-coverage`. [SC-2, SC-3]
- [x] **T-011** `SKILL.md` com `description`-como-trigger, progressive
  disclosure e **seção `## Gotchas`** (Princípio III). _(Gotchas adicionada em
  2026-05-23 durante a correção de conformidade.)_
- [x] **T-012** Registrar `complementary:decision-tree` em
  `scripts/profiles.txt.in` para instalar via `cstk install --profile
  complementary`. _(Adicionado em 2026-05-23.)_
- [x] **T-013** Entrada no `CHANGELOG.md` (MINOR). _(Adicionada em 2026-05-23.)_
