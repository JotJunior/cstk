# Data Model: Code Reconciliation (`reconcile-docs`)

Nao ha banco nem estado persistente de orquestrador. As entidades abaixo existem como
saida TSV dos scripts, como texto no relatorio da conversa ou como arquivos Markdown
da feature. Identificadores e valores de enum sao em ingles; rotulos exibidos ao
usuario podem ser em portugues.

## Entity: Feature (feature reconciliavel)

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| name | string | kebab-case, basename sem prefixo de data | identidade da feature (spec, Assumptions) |
| location | enum | `active` \| `archived` | `active` = `docs/specs/<name>/`; `archived` = `docs/specs/_archived/[AAAA-MM-DD-]<name>/` |
| dir | path | relativo a raiz do projeto, existente | nunca sob `docs/specs/current/` |
| shadowed | bool | so `archived` | `true` quando existe versao `active` de mesmo nome (FR-015) |
| docs | list<path> | subconjunto da allowlist | `spec.md`, `plan.md`, `data-model.md`, `quickstart.md`, `contracts/*.md` presentes |

### Relationships

- Feature 1:N Anchor (extraidas dos `docs`)
- Feature 1:N Divergence
- Feature 1:1 FeatureResult (por execucao)
- Feature 0:1 ReconciliationLog (`reconciliation.md`)

## Entity: Anchor (saida de `extract-anchors.sh`)

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| kind | enum | `path` \| `flag` \| `command` \| `req-id` | classificacao lexical do token entre crases |
| token | string | sem crases, sem espacos | ex.: um caminho relativo citado no plan |
| source | string | `<doc>:<line>` | documento e linha onde o token aparece |
| presence | enum | `present` \| `absent` \| `n/a` | so `path` recebe `present`/`absent` (relativo a raiz) |

## Entity: Divergence

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| feature | string | FK Feature.name | |
| type | enum | `stale` \| `removed` \| `undocumented` \| `possible-regression` \| `unverifiable` | pt: desatualizada, removida, nao documentada, possivel regressao, nao verificavel |
| doc | path | um dos `Feature.docs` | documento afetado |
| locator | string | heading ou `linha N` ou id `FR-NNN` | trecho afetado |
| claim | string | curto | o que a documentacao afirma |
| evidence | string | `<path>:<line>` \| `absent:<path>` \| vazio so em `unverifiable` | FR-008, SC-004 |
| action | enum | ver tabela abaixo | FR-010 |

Elegibilidade ao denominador de SC-005 ("acerto pontual"), derivavel do `type` (sem limiar
numerico): `stale`, `removed` e `undocumented` sao elegiveis; `possible-regression` e
`unverifiable` NAO sao (exigem decisao humana ou fonte inexistente por desenho —
FR-007/FR-008). O numerador e o subconjunto elegivel resolvido em uma unica invocacao sem
edicao manual (`action` em `updated`, `marked-removed`, `added`). O METODO de medicao
(quem e como) segue pendente de decisao do dono do produto (tasks 1.4/6.5).

Regras de `type` → `action` (FR-005, FR-007, FR-009):

| type | action (modo gravacao) | action (`--dry-run`) | marcador no documento |
|------|------------------------|----------------------|------------------------|
| `stale` (SHOULD / descritivo) | `updated` | `proposed-update` | `[reconciled:updated ...]` |
| `stale` que contradiz MUST/MUST NOT da feature ou principio da constitution | `reported-human-decision` (type vira `possible-regression`) | idem | nenhum |
| `removed` | `marked-removed` | `proposed-mark-removed` | `[reconciled:removed ...]` |
| `undocumented` | `added` (novo FR-NNN) | `proposed-add` | `[reconciled:added ...]` |
| `possible-regression` | `reported-human-decision` | idem | nenhum |
| `unverifiable` | `unverifiable` | idem | nenhum |
| qualquer, quando `doc-guard.sh check` nega o caminho | `ignored` (motivo `write-denied`) | idem | nenhum |

## Entity: FeatureResult

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| feature | string | FK Feature.name | |
| status | enum | `reconciled` \| `no-divergence` \| `skipped` \| `error` | spec US2 cenario 1 |
| reason | string | obrigatorio em `skipped`/`error` | ex.: `shadowed-by-active`, `no-reconcilable-docs`, `unreadable:<doc>` |
| counts | map<type,int> | | uma contagem por `Divergence.type` |
| docs_changed | list<path> | vazio em `--dry-run` e `no-divergence` | |

### State Transitions (por feature, numa execucao)

```
located → anchors-extracted → compared → { no-divergence
                                          | reconciled  (>=1 doc alterado; log anexado)
                                          | error       (falha; lote segue — FR-013) }
located → skipped   (shadowed-by-active | no-reconcilable-docs)
```

Em `--dry-run`, `reconciled` e exibido como "alteracoes propostas" e nada e gravado.

## Entity: ReconciliationReport (saida da conversa)

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| mode | enum | `single` \| `all` | |
| dry_run | bool | | FR-011 |
| results | list<FeatureResult> | uma por feature processada | SC-006: todas contabilizadas |
| divergences | list<Divergence> | agrupadas por feature | |
| audit | enum | `clean` \| `violation` \| `skipped-no-git` | camada 2 da guarda (research Decision 5) |
| notices | list<string> | | ex.: versao arquivada existente (FR-015), `no-git` (FR-016), `constitution-unavailable` (FR-007) |

## Entity: ReconciliationLog (`<feature-dir>/reconciliation.md`)

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| entries | list<LogEntry> | append-only | criado so na primeira reconciliacao com alteracao |

### LogEntry

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| date | date | `YYYY-MM-DD` | heading `## <date>` |
| counts | map<type,int> | | por `Divergence.type` |
| docs_changed | list<path> | >= 1 | nunca ha entrada sem alteracao (FR-018) |
| summary | string | <= 10 linhas | resumo, nao o relatorio completo |

## Entity: Marker

Definido em [contracts/markers.md](./contracts/markers.md) (`kind`, `date`, `evidence`).
