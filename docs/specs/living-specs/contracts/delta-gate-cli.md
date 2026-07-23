# Contract: delta-gate.sh CLI

> **[PROPOSTA — a validar na implementacao]** — script NOVO em
> `global/skills/review-features/scripts/delta-gate.sh`. O padrao de saida
> FINDING/RESULT e exit codes replica o dos gates REAIS v5.22.0
> (`validate-sdd.sh`, `requirement-coverage.sh` — verificados no repo).

**Feature**: `living-specs` | FRs: FR-010, FR-011, FR-012, FR-013

## Uso

```
delta-gate.sh SPEC_MD [--corpus-dir DIR]
```

- `SPEC_MD` — path do `spec.md` da feature candidata a archive.
- `--corpus-dir DIR` — raiz do corpus (default:
  `<repo>/docs/specs/current/`, resolvida subindo a partir de SPEC_MD pela
  convencao `docs/specs/<feature>/spec.md`; sem convencao e sem flag =>
  exit 2).

Read-only: nunca escreve em SPEC_MD nem no corpus. Deterministico: mesmo
input => mesmo veredito (edge case da spec).

## Saida (stdout)

```
FINDING|<severity>|<code>|<mensagem>
RESULT|<spec>|delta=<present|skip|missing>|errors=<N>|warnings=<M>
```

`severity in {error, warning, info}`. Erros de uso emitem adicionalmente
`DIAG|error|<code>|<message>|<fix>` em stderr (envelope `_diag.sh` vendored
— research Decision 7).

## Codes

| Code | Severity | Condicao |
|------|----------|----------|
| `delta-missing` | error | sem secao `## Delta Requirements` e sem skip (FR-010) |
| `skip-invalid` | error | marcador Skip sem justificativa, autor ou data (FR-011) |
| `delta-empty` | error | secao presente mas sem nenhum bloco Capability nem skip |
| `capability-slug-invalid` | error | slug fora de `[a-z0-9][a-z0-9-]*` |
| `entry-malformed` | error | entrada fora da gramatica do contrato delta-section-format |
| `ref-not-found` | error | MODIFIED/REMOVED/RENAMED referencia id inexistente/inativo no corpus (FR-013, US3 cenario 4) |
| `added-collision` | error | ADDED com id ja existente na capability (edge case colisao) |
| `renamed-target-exists` | error | RENAMED para id ja usado (ativo, removido ou aposentado) |
| `skip-with-delta` | error | Skip E blocos Capability na mesma secao (mutuamente exclusivos) |
| `corpus-malformed` | error | arquivo `docs/specs/current/<slug>.md` referenciado pela secao delta viola invariante estrutural do contrato corpus-format (heading `# Capability:`/`## Requirements`/`### FR-NNN` mal-formado, ou id duplicado considerando `## Requirements` + `## Removed Requirements` + coluna Antigo/Novo de `## Renamed Identifiers` simultaneamente) — CHK034 |
| `corpus-missing` | info | corpus/capability ainda inexistente com apenas ADDED (valido — primeiro merge cria); distinto de `corpus-malformed` (corpus existe mas esta invalido) |

## Exit codes

| Exit | Significado |
|------|-------------|
| 0 | archive liberado (delta valida OU skip valido; so warnings/infos) |
| 1 | archive bloqueado (>=1 FINDING error) |
| 2 | uso incorreto / SPEC_MD inexistente / corpus-dir irresoluvel |

## Invariantes

1. POSIX sh puro (`#!/bin/sh`, `set -eu`, sem jq — Constitution II).
2. Skip valido => exit 0 com `delta=skip` no RESULT (distinguivel de
   aplicacao normal em qualquer trilha — FR-011).
3. Delta so-REMOVED e valida (US3 cenario 3).
4. **Seguranca (gate owasp pos-plan)**: o slug vem de texto UNTRUSTED do
   spec.md — a validacao `[a-z0-9][a-z0-9-]*` e a PRIMEIRA checagem do
   parser, ANTES de qualquer composicao de path com o valor (anti path
   traversal `../`); texto delta nunca passa por `printf "$var"` (sempre
   `printf '%s'`).
5. Teste: `tests/test_delta-gate.sh` (convencao de cobertura), incluindo
   cenario de slug hostil (`../escape`, absoluto, com espaco).
6. **Ordem de validacao (CHK034)**: para cada capability referenciada
   pela secao delta que ja existe no corpus, a checagem estrutural
   (`corpus-malformed`) roda como PRE-CHECAGEM, ANTES de qualquer
   validacao referencial (`ref-not-found`/`added-collision`/
   `renamed-target-exists`) contra o conteudo daquele arquivo — um corpus
   malformado nao pode ser lido de forma confiavel para validar
   referencias. Corpus inexistente permanece `corpus-missing` (nao e
   `corpus-malformed`).
