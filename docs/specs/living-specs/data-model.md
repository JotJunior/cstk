# Data Model: living-specs

**Feature**: `living-specs` | **Date**: 2026-07-23
**Input**: [spec.md](./spec.md) · [research.md](./research.md)

Nao ha banco de dados: todas as entidades sao arquivos Markdown (corpus,
secao delta) ou artefatos de git/sidecar (allowlist, baseline). "Campos"
abaixo descrevem a estrutura textual deterministicamente parseavel.

## Entity: CorpusCapabilityFile

Um arquivo `docs/specs/current/<capability-slug>.md` por capability
(research Decision 5).

| Campo | Tipo | Obrigatorio | Notas |
|-------|------|-------------|-------|
| `capability_slug` | string kebab-case | sim | derivado do nome do arquivo; `[a-z0-9-]+` |
| `requirements` | CorpusEntry[] | sim (pode ser vazio) | secao `## Requirements` |
| `removed_requirements` | RemovedEntry[] | nao | secao `## Removed Requirements` (FR-004) |
| `renamed_identifiers` | RenameRecord[] | nao | secao `## Renamed Identifiers`, tabela (FR-005) |

**Relacionamentos**: criado/mutado exclusivamente por `delta-merge.sh`;
lido por `delta-gate.sh` (checagens de referencia) e por humanos/agentes
(FR-009).

**State transitions**: inexistente -> criado no primeiro merge que declara a
capability (US2 cenario 4). Nunca deletado pelo merge (mesmo sem entradas
ativas, remove-se para `## Removed Requirements`, nao o arquivo).

## Entity: CorpusEntry

Uma entrada ativa do corpus — heading `### FR-NNN` dentro de
`## Requirements`.

| Campo | Tipo | Obrigatorio | Notas |
|-------|------|-------------|-------|
| `id` | `FR-NNN` | sim | unico DENTRO do arquivo de capability (colisao => FINDING) |
| `text` | markdown | sim | corpo do requisito (comportamento ATUAL) |
| `introduced_by` | feature short-name + data | sim | proveniencia de origem (FR-007, SC-004) |
| `last_modified_by` | feature short-name + data | nao | presente apos primeiro MODIFIED |

**State transitions**:

```
(inexistente) --ADDED--> ativa --MODIFIED--> ativa (texto substituido, id preservado)
ativa --REMOVED--> movida para Removed Requirements (com proveniencia da remocao)
ativa --RENAMED--> ativa sob novo id + linha em Renamed Identifiers
```

Transicoes invalidas (todas => bloqueio, nunca no-op silencioso — FR-013):
MODIFIED/REMOVED/RENAMED sobre id inexistente ou ja removido; ADDED sobre id
ja ativo na mesma capability; RENAMED para id ja existente.

## Entity: DeltaSection

Secao `## Delta Requirements` dentro do `spec.md` da feature
(research Decision 4; contrato em
[contracts/delta-section-format.md](./contracts/delta-section-format.md)).

| Campo | Tipo | Obrigatorio | Notas |
|-------|------|-------------|-------|
| `capabilities` | CapabilityDelta[] | condicional | >=1 se nao houver skip |
| `skip` | SkipRecord | condicional | mutuamente exclusivo com `capabilities` |

Exatamente UM dos dois presentes; ambos ausentes = secao invalida; secao
inteira ausente = archive bloqueado por default (FR-010).

## Entity: CapabilityDelta

Bloco `### Capability: <slug>` dentro da DeltaSection.

| Campo | Tipo | Obrigatorio | Notas |
|-------|------|-------------|-------|
| `capability_slug` | string kebab-case | sim | alvo em `docs/specs/current/` |
| `added` | DeltaEntry[] | nao | `#### ADDED` |
| `modified` | DeltaEntry[] | nao | `#### MODIFIED` |
| `removed` | DeltaEntry[] | nao | `#### REMOVED` |
| `renamed` | RenameDelta[] | nao | `#### RENAMED` |

Pelo menos um dos quatro grupos nao-vazio (delta valida "mesmo que so com
entradas REMOVED" — US3 cenario 3).

## Entity: DeltaEntry

| Campo | Tipo | Obrigatorio | Notas |
|-------|------|-------------|-------|
| `id` | `FR-NNN` | sim | ADDED: mesmo id da secao Requirements da propria spec (US1 cenario 1); MODIFIED/REMOVED: id da entrada do corpus referenciada |
| `text` | markdown | sim | ADDED/MODIFIED: texto integral novo; REMOVED: motivo |

## Entity: RenameDelta / RenameRecord

| Campo | Tipo | Obrigatorio | Notas |
|-------|------|-------------|-------|
| `old_id` | `FR-NNN` | sim | deve existir ativo no corpus |
| `new_id` | `FR-NNN` | sim | nao pode existir no corpus (ativo ou removido) |
| `feature` | short-name | sim (RenameRecord) | proveniencia do rename |
| `date` | YYYY-MM-DD | sim (RenameRecord) | data do archive |

## Entity: SkipRecord (Archive Skip)

Marcador `**Skip**: <justificativa> — <autor>, <YYYY-MM-DD>` dentro da
DeltaSection (FR-011: quem, quando, por que; distinguivel de aplicacao
normal em qualquer trilha — o `RESULT|` do gate reporta `delta=skip`).

| Campo | Tipo | Obrigatorio | Notas |
|-------|------|-------------|-------|
| `justification` | texto nao-vazio | sim | por que este archive nao precisa de delta |
| `author` | texto nao-vazio | sim | quem autorizou |
| `date` | YYYY-MM-DD | sim | quando |

## Entity: CommitAllowlist (efemera)

Conjunto de caminhos computado por `commit-mode.sh stage-derived` no momento
do commit (research Decision 2). Nunca persistida; derivada de:

| Componente | Fonte | Notas |
|-----------|-------|-------|
| tracked modificados/deletados | `git status --porcelain` (estados `M`, `D`, etc. na arvore) | sempre incluidos |
| untracked novos do passo | untracked atuais MENOS UntrackedBaseline | exige baseline; sem baseline => excluidos (fail-closed) |
| filtro de escopo | `--scope-dir` (0..N) | quando presente, allowlist intersectada com os prefixos |

Allowlist vazia => exit 3, nenhum commit (FR-016). Nunca ha fallback para
`git add -A`/`git add .` (FR-014/FR-015).

## Entity: UntrackedBaseline (sidecar)

Arquivo `commit-baseline.txt` no state dir da execucao (`$SD/`), uma linha
por path untracked, ordenado (`sort`), escrito por `commit-mode.sh snapshot`
no inicio da onda. Mesmo padrao sidecar de `tool-call-ticks.log`: fora do
`state.json`, nunca versionado, reconstruivel. Paths presentes no baseline
sao "alheios pre-existentes" e NUNCA entram em commit automatico (FR-015 —
o `.pptx` do incidente cai aqui).
