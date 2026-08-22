# Contract: `converge-status.sh` (CLI)

> **[PROPOSTA — a validar na implementacao]**. Este script **nao existe**
> hoje no repositorio; o contrato abaixo e desenho novo, nao a documentacao
> de uma interface ja existente (Constitution VI). O que ja existe e citado
> explicitamente como tal.

**Path**: `plugins/cstk/skills/converge/scripts/converge-status.sh`
**Linguagem**: POSIX sh (`#!/bin/sh`, `set -eu`), sem `jq` (Constitution II).
**Teste correspondente**: `tests/test_converge-status.sh` (convencao exigida
por `./tests/run.sh --check-coverage`).

## Convencoes gerais

- Dados em stdout, diagnostico em stderr.
- Exit: `0` sucesso/veredito positivo, `1` veredito negativo ou erro geral,
  `2` uso incorreto, `3` estado "nunca convergiu".
- `--feature-dir DIR` e obrigatorio em todos os subcomandos. `DIR` e o
  diretorio da feature (ex.: `docs/specs/pipeline-converge`).
- Arquivo operado: `<DIR>/converge-report.md` (criado no primeiro `record`).

## `record`

```
converge-status.sh record --feature-dir DIR --outcome clean|actionable \
                          --provenance gate|standalone --actionable N \
                          [--note TEXT]
```

Apenda uma linha `ConvergenceStatusRecord` (ver `data-model.md`). Calcula
`at` (UTC agora) e `tasks-digest` a partir de `<DIR>/tasks.md`.

| Situacao | Exit | stdout |
|----------|------|--------|
| gravado | 0 | (vazio) |
| `--outcome clean` com `--actionable > 0` (ou inverso) | 2 | — |
| valor de campo contendo `;` ou `-->` | 2 | — |
| `<DIR>/tasks.md` ausente | 2 | — |
| flag desconhecida / obrigatorio ausente | 2 | — |

Escrita atomica (`mktemp` + `mv`), preservando integralmente o conteudo
anterior — mesmo padrao ja adotado por `converge-tasks.sh append-phase`.

## `latest`

```
converge-status.sh latest --feature-dir DIR
```

Imprime a ultima linha de status do arquivo, literal.

| Situacao | Exit | stdout |
|----------|------|--------|
| ha ao menos um registro | 0 | linha `<!-- converge-status: ... -->` |
| arquivo ausente ou sem registro | 1 | (vazio) |

## `check`

Veredito consumido por `execute-task`, `review-task`,
`pipeline.sh detect-completion` e pelos orquestradores.

```
converge-status.sh check --feature-dir DIR [--quiet]
```

| Situacao | Exit | stdout (sem `--quiet`) |
|----------|------|------------------------|
| `outcome=clean` e digest do `tasks.md` bate | 0 | `converged` |
| `outcome=risk-accepted` e digest bate | 0 | `risk-accepted` |
| `outcome=actionable` (ultimo registro) | 1 | `pending actionable=N` |
| `outcome=clean\|risk-accepted` mas digest divergente | 1 | `stale` |
| nenhum registro / arquivo ausente | 3 | `never` |
| `<DIR>/tasks.md` ausente | 0 | `not-applicable` |

A ultima linha da tabela implementa FR-005: feature sem backlog nao e travada
por uma etapa que nao se aplica a ela.

## `accept-risk`

```
converge-status.sh accept-risk --feature-dir DIR --justificativa TEXT \
                               [--decisao-id dec-NNN]
```

Apenda registro `outcome=risk-accepted` com o digest corrente do `tasks.md`.

| Situacao | Exit |
|----------|------|
| gravado | 0 |
| `--justificativa` ausente e `--decisao-id` ausente | 2 |
| `<DIR>/tasks.md` ausente | 2 |

O aceite vale apenas para o digest corrente (ver `data-model.md`
§State transitions).

## Requisitos de seguranca do script (plan.md §Revisao de seguranca)

Vinculantes para a implementacao — cada item tem finding correspondente.

| Requisito | Finding | Comportamento exigido |
|-----------|---------|------------------------|
| Contencao de `--feature-dir` | F3 | Resolver e validar via `converge/scripts/path-contains.sh` (canonicaliza symlinks ANTES de checar o prefixo; fail-closed sem marcador de raiz). Fora da raiz ⇒ exit 2, sem escrita |
| Destino nao pode ser symlink | F6 | `<DIR>/converge-report.md` existente e symlink ⇒ exit 2, sem escrita |
| `mktemp` no diretorio do destino | F5 | `mktemp -- "<DIR>/converge-report.md.XXXXXX"` + `mv -f` — garante `rename(2)` no mesmo filesystem (padrao ja adotado em `converge-tasks.sh:303`) |
| Rejeicao de metacaracteres do formato | F7 | Valor de qualquer campo contendo `;`, `-->` ou newline ⇒ exit 2. Valores passados como argv; nunca `eval` |
| Parse ancorado no marcador | F2 | `check` e `latest` reconhecem **apenas** linhas que casam `^<!-- converge-status: .* -->$`; toda prosa do arquivo e ignorada |
| Vocabulario de saida fechado em `check` | F2 | stdout de `check` ∈ {`converged`, `risk-accepted`, `pending actionable=N`, `stale`, `never`, `not-applicable`} — **nunca** ecoa conteudo do arquivo. Consumidores automatizados usam `check`; `latest` e para auditoria humana |
| Aceite de risco e do operador | F8 | Em execucao autonoma o orquestrador NAO invoca `accept-risk` por conta propria: emite bloqueio humano e so registra apos resposta (FR-004 atribui o aceite ao **operador**) |

**Modelo de confianca (F4)**: `tasks-digest` detecta **mudanca** do backlog,
nao **adulteracao** do artefato — e recalculavel por qualquer um. O
`converge-report.md` e registro auditavel, nao controle de seguranca; nenhum
consumidor deve derivar dele garantia de autenticidade.

## Interface JA EXISTENTE consumida por este script

Extraida do codigo-fonte, nao suposta:

- `plugins/cstk/skills/converge/scripts/converge-tasks.sh` — subcomando
  `gap-key` documenta o algoritmo `sha256-12(...)` usado no repo para derivar
  chaves curtas; `tasks-digest` reusa o mesmo helper de digest em vez de
  introduzir convencao nova.
- `plugins/cstk/skills/converge/scripts/converge-tasks.sh append-phase` —
  precedente de escrita atomica append-only sobre artefato da feature.
