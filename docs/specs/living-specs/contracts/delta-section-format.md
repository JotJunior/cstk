# Contract: Delta Requirements Section (spec.md)

> **[PROPOSTA — a validar na implementacao]** — contrato NOVO, projetado do
> zero nesta feature (nenhuma API existente e afirmada aqui). Formato do
> OpenSpec usado como inspiracao conceitual (ADDED/MODIFIED/REMOVED/RENAMED),
> nao como fonte de sintaxe (sem fonte suficiente do parser deles —
> Principio VI).

**Feature**: `living-specs` | FRs: FR-001, FR-010, FR-011

## Localizacao

Secao opcional `## Delta Requirements` no `spec.md` da feature, apos
`## Success Criteria` (posicao recomendada; o parser localiza pelo heading,
nao pela posicao). Template: nova secao opcional comentada em
`global/skills/specify/templates/feature-spec.md`.

## Gramatica (parseavel por awk/grep POSIX)

```markdown
## Delta Requirements

### Capability: <capability-slug>

#### ADDED

- **FR-NNN**: <texto integral do requisito>

#### MODIFIED

- **FR-NNN**: <novo texto integral que substitui a entrada do corpus>

#### REMOVED

- **FR-NNN**: <motivo da remocao>

#### RENAMED

- **FR-NNN -> FR-MMM**
```

Regras:

1. `<capability-slug>` casa `[a-z0-9][a-z0-9-]*` e mapeia para
   `docs/specs/current/<capability-slug>.md`.
2. Blocos `### Capability:` sao repetiveis (uma feature pode tocar N
   capabilities). Cada um contem >=1 dos quatro grupos `####`.
3. Entrada comeca em `- **FR-NNN**:` (ADDED/MODIFIED/REMOVED) ou
   `- **FR-NNN -> FR-MMM**` (RENAMED). Linhas seguintes indentadas
   (2+ espacos) continuam o texto da mesma entrada.
4. Em ADDED, `FR-NNN` e o MESMO identificador usado na secao
   `### Functional Requirements` da propria spec (US1 cenario 1). Em
   MODIFIED/REMOVED/RENAMED, o id referencia a entrada do corpus.
5. Seta do RENAMED e ASCII `->` (nunca `→`).

## Skip explicito (FR-011)

Forma alternativa da secao — mutuamente exclusiva com blocos Capability:

```markdown
## Delta Requirements

**Skip**: <justificativa nao-vazia> — <autor>, <YYYY-MM-DD>
```

Os tres campos sao obrigatorios; ausencia de qualquer um => skip invalido
(gate bloqueia com `skip-invalid`).

## Interacao com gates existentes (verificada no repo)

- `validate-sdd.sh` spec-profile: nao exige nem proibe a secao (exige so
  "User Scenarios & Testing", "Requirements", "Success Criteria").
- `requirement-coverage.sh`: ignora a secao (so le
  `### Functional Requirements`); ids delta nao entram na cobertura.
