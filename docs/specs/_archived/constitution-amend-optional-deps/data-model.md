# Data Model: Constitution Amendment — Optional Dependencies

Entidades relevantes ao amendment. Por ser feature documental, "modelo" aqui
descreve artefatos textuais e suas invariantes, nao schema de DB.

## Entity: Constitution Document

Arquivo unico `docs/constitution.md`. Fonte de verdade de principios de governanca
do toolkit.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| sync_impact_report | HTML comment block at top | obrigatorio em MAJOR/MINOR | Formato fixo (ver Decision 3 do research) |
| principios_core | secoes `### Principio N` | 5 principios (I a V) | III adicionada nao-triviamente exige MAJOR |
| quality_standards | secao `## Quality Standards` | | Detalhamento operacional |
| decision_framework | secao `## Decision Framework` | | Regras de desempate |
| governance | secao `## Governance` | | Amendment process + authority |
| version_footer | linha final `**Version**: X.Y.Z \| **Ratified**: YYYY-MM-DD \| **Last Amended**: YYYY-MM-DD` | SemVer rigoroso | Datas ISO |

### Invariantes

- Versao sobe monotonica (nunca decresce em amendment valido).
- `Ratified` data e imutavel apos criacao (1.0.0 ratificacao = 2026-04-20).
- `Last Amended` sempre >= `Ratified`.
- Principios existentes (I..V) nao sao removidos nem renumerados em MINOR — apenas
  expandidos via subsecoes.
- Remocao ou renomeacao de principio = MAJOR obrigatorio.

### State transitions

```
1.0.0 (ratificado 2026-04-20)
  |
  | amendment 1.1.0 — optional-deps carve-out (esta feature)
  v
1.1.0 (last amended 2026-04-24)
  |
  | (amendments futuros)
  v
1.X.Y
```

## Entity: Principio II Subsection — "Optional Dependencies with Graceful Fallback"

Subsecao textual adicionada ao Principio II pelo amendment 1.1.0.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| heading | `#### Optional dependencies with graceful fallback (amendment 1.1.0)` | exatamente este texto | Marcacao do nivel 4 |
| position | entre bloco MUST existente e `**Rationale:**` | imutavel apos insercao em 1.1.0 | Preserva leitura linear |
| condicoes | 3 itens (a, b, c) | exatamente 3, nao 2 nem 4 | SC-006 |
| afirmacoes_negativas | lista explicita do que NAO muda | 3 afirmacoes | FR-003 |
| referencia_primeiro_caso | paragrafo apontando jq em cstk-cli | links relativos | FR-007, SC-007 |

### Invariantes

- As tres condicoes sao CUMULATIVAS (AND logico). O texto e explicitamente
  "todas MUST ser satisfeitas".
- Bash-isms continuam proibidos — nota explicita na subsecao.
- `ripgrep`, `fd`, `bats` continuam banidos NOMINALMENTE — nota explicita.
- Deps obrigatorias (sem fallback) continuam vetadas — nota explicita.

## Entity: Optional Dependency Case Registry

Registro de casos concretos que invocam o carve-out. Reside no `plan.md` da
feature que introduz a dep; referenciado da constitution.

| Field | Type | Source | Notes |
|-------|------|--------|-------|
| dep_name | string | nome do executavel externo | ex: `jq` |
| feature_of_origin | path | `docs/specs/<feature>/spec.md` | ex: cstk-cli |
| confined_file | path | unico arquivo que referencia a dep | condicao (b) |
| fallback_mechanism | texto | descricao + como verificar | condicao (a) |
| verification_test | path | teste automatizado que cobre o fallback | condicao (a) parte "verificavel" |
| ratified_in | versao | amendment que autoriza | ex: 1.1.0 |

### Invariantes

- Um caso por dep por feature. Duas features que usam a mesma dep (ex: ambas usam
  `jq`) registram DOIS casos independentes.
- `confined_file` aponta para um unico arquivo, nao glob nem diretorio.
- Mudanca de `fallback_mechanism` de "existe" para "removido" invalida o caso —
  feature vira violacao de Principio II e precisa nova spec.

## Relationships

```
Constitution Document 1..1 ── contains ──▶ Principio II Subsection
Principio II Subsection 1..N ── lists ──▶ Optional Dependency Case (registry)
Optional Dependency Case 1..1 ── cited in ──▶ Feature plan.md §Complexity Tracking
```

## Non-entities (explicitly out-of-scope)

- **Automated policy engine** — nenhum sistema executa validacao automatica das
  tres condicoes. E disciplina humana reforcada por `/analyze` na feature alvo.
- **Registry centralizado** — nao existe "tabela unica" listando todos os casos;
  cada caso vive no plan.md da feature que o introduz. A constitution cita
  apenas o primeiro caso como ilustracao. Futuramente, se houver 3+ casos,
  considerar um documento-indice separado.
