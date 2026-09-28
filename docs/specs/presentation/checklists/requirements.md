# REQUIREMENTS Checklist: Apresentacao Narrativa do Projeto

**Purpose**: Validar a qualidade dos requisitos de `presentation` (spec.md +
plan.md) antes de `/create-tasks`: completude, clareza, consistencia,
mensurabilidade e cobertura de edge cases.
**Created**: 2026-09-25
**Feature**: [spec.md](../spec.md)

## Completude de Requisitos

- [x] CHK001 - As tres pecas de saida e seu diretorio estao definidos?
  [Completude, Spec §FR-002, §Clarifications Q2] {auto}
- [x] CHK002 - As fontes varridas (briefing atual e legado, constitution,
  specs ativas, arquivadas e vivas) estao enumeradas? [Completude, Spec §FR-003] {auto}
- [x] CHK003 - Os campos do inventario por spec estao definidos, incluindo
  a regra de estagio? [Completude, Spec §FR-004, data-model.md] {auto}
- [x] CHK004 - A densidade (um slide por spec) esta decidida? [Completude,
  Spec §FR-005, §Clarifications Q3] {auto}
- [x] CHK005 - O conteudo obrigatorio do slide de spec (4 secoes, estagio,
  fonte) esta definido? [Completude, Spec §FR-006] {auto}
- [x] CHK006 - O comportamento de regeneracao (added/changed/removed/
  unchanged e preservacao de edicao manual) esta definido? [Completude,
  Spec §FR-007, §FR-008] {auto}
- [x] CHK007 - O catalogo de tipos de slide e fechado e enumerado?
  [Completude, Spec §FR-016] {auto}

## Clareza

- [x] CHK008 - "Autocontido/offline" esta definido de forma verificavel
  (CSS/JS inline, fontes do sistema, zero recurso de rede)? [Clareza, Spec §FR-010, §SC-002] {auto}
- [x] CHK009 - "Mesmo formato" esta traduzido em regra testavel (catalogo
  fechado + render deterministico)? [Clareza, Spec §FR-012, §FR-016] {auto}
- [x] CHK010 - O tom executivo/inspirador tem limite explicito frente ao
  Principio VI? [Clareza, Spec §FR-013, §Clarifications Q4] {auto}

## Consistencia

- [x] CHK011 - `--render-only` e consistente com "HTML sempre derivado"?
  [Consistencia, Spec §FR-009, §Clarifications Q2] {auto}
- [x] CHK012 - Chave de spec e unica mesmo com specs vivas homonimas de
  arquivadas? [Consistencia, data-model.md §Campos de spec, research Decision 7] {auto}

## Mensurabilidade

- [x] CHK013 - Todos os SC sao mensuraveis sem julgamento subjetivo?
  [Mensurabilidade, Spec §SC-001..SC-005] {auto}
- [ ] CHK014 - A qualidade estetica ("esteticamente bonito") tem criterio
  objetivo, ou depende de aprovacao humana do deck gerado? [Mensurabilidade,
  Risco] {humano}

## Edge Cases

- [x] CHK015 - Projeto sem briefing/constitution/specs esta coberto?
  [Edge Case, Spec §Edge Cases] {auto}
- [x] CHK016 - Conteudo com caracteres HTML esta coberto? [Edge Case,
  Spec §FR-015] {auto}
- [x] CHK017 - Spec sem tasks nao pode aparecer como implementada?
  [Edge Case, Spec §Edge Cases, data-model.md §stage] {auto}

## Dependencias

- [x] CHK018 - Nenhuma dependencia fora do POSIX (sem `jq`, sem runtime de
  JS no build)? [Dependencias, plan.md §Technical Context] {auto}

## Notes

- Gate deterministico `requirement-coverage.sh` sobre `spec.md`:
  `requirements=17 covered=17 errors=0` (exit 0).
- CHK014 e `{humano}` por natureza: a estetica e aprovada pelo dono do
  produto sobre os prints do dogfooding (quickstart cenario 12). Nao
  bloqueia a implementacao.
