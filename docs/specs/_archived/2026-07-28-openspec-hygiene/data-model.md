# Data Model: openspec-hygiene

**Feature**: `openspec-hygiene`
**Date**: 2026-07-23

Nenhuma entidade persiste em banco/state — todas sao registros
transientes (linhas de saida de script ou convencao de filesystem).

## Entity: RequirementScenarioGap

Um Functional Requirement sem cenario associado, detectado pelo gate
`requirement-coverage.sh`. Materializa-se como uma linha `FINDING` na
saida do script (nao persiste).

| Campo | Tipo | Origem | Notas |
|-------|------|--------|-------|
| `requirement_id` | string (`FR-NNN`) | parse de `- **FR-NNN**:` sob `### Functional Requirements` | ID exato reportado (FR-003) |
| `spec_path` | string (path) | argumento `FILE` do script | ecoado na linha `RESULT` |
| `suggested_fix` | string | gerado pelo gate | instrucao acionavel na mensagem do FINDING (SC-002) |

**Representacao**: `FINDING|error|fr-no-scenario|<mensagem com FR-NNN + fix>`

**Regras**:
- Zero FRs declarados → zero gaps (passa trivialmente, FR-004).
- Gap existe sse nem fast-path (ID literal citado em cenario) nem
  heuristica textual (>= N termos-chave no corpus de cenarios) casam
  (research.md Decision 2).

## Entity: DiagnosticEnvelope

Registro estruturado emitido em stderr por script POSIX do
escopo-piloto ao falhar. Nao persiste — e uma linha parseavel.

| Campo | Tipo | Constraints | Notas |
|-------|------|-------------|-------|
| `severity` | enum `error` \| `warning` | obrigatorio | falhas fatais usam `error` |
| `code` | string kebab-case | estavel por (script, condicao de falha); unico dentro do script (FR-014) | ex.: `hash-mismatch`, `lock-contention` |
| `message` | string | legivel por humano; `\|` interno vira `/` | pode ser pt-br |
| `fix` | string | acionavel; MUST NOT repetir `message` (FR-013); `\|` interno vira `/` | proximo passo concreto |

**Representacao**: `DIAG|<severity>|<code>|<message>|<fix>` (1 linha,
stderr, emitida ADICIONALMENTE a mensagem de erro legada do script).

**Regras**:
- Emissor: helper sourceable `_diag.sh` (`diag_emit`), POSIX puro,
  zero jq (FR-016).
- Fail-fast: apenas o primeiro erro fatal gera envelope (Edge Case da
  spec — sem agregacao).
- Scripts fora do escopo-piloto: formato atual intacto (FR-015).

## Entity: ArchivedFeatureEntry

Diretorio de feature arquivado com prefixo de data. Materializa-se
como convencao de nomenclatura no filesystem.

| Campo | Tipo | Origem | Notas |
|-------|------|--------|-------|
| `archive_date` | string `YYYY-MM-DD` | data em que o arquivamento OCORRE (nao a criacao da feature) | FR-009 |
| `feature_name` | string kebab-case | nome original do diretorio da feature | preservado apos o prefixo |
| `path` | string | `docs/specs/_archived/<YYYY-MM-DD>-<feature>/` | ordenacao alfabetica == cronologica (SC-003) |

**State transitions**:
- `docs/specs/<feature>/` → (acao manual de arquivamento documentada
  em `review-features`) → `docs/specs/_archived/<YYYY-MM-DD>-<feature>/`
- Dirs pre-existentes sem prefixo: estado terminal, nunca migrados
  (FR-010).
