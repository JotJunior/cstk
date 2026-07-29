# Contract: delta-merge.sh CLI

> **[PROPOSTA — a validar na implementacao]** — script NOVO em
> `global/skills/review-features/scripts/delta-merge.sh`.

**Feature**: `living-specs` | FRs: FR-002..FR-008

## Uso

```
delta-merge.sh SPEC_MD --feature NAME [--corpus-dir DIR] \
  [--date YYYY-MM-DD] [--dry-run]
```

- `--feature NAME` — short-name gravado como proveniencia (FR-007).
- `--date` — data de proveniencia (default: data corrente UTC).
- `--dry-run` — valida tudo e reporta o que SERIA aplicado; zero escrita.
- `--corpus-dir` — mesma resolucao do delta-gate.

## Comportamento

1. Parseia a secao `## Delta Requirements` de SPEC_MD (mesma gramatica do
   contrato delta-section-format).
2. Skip valido presente => no-op declarado: `RESULT|...|delta=skip` e
   exit 0 sem tocar o corpus.
3. Valida TODAS as pre-condicoes de TODAS as entradas contra o corpus
   (tabela do contrato corpus-format) ANTES de escrever qualquer byte.
4. Aplicacao atomica por arquivo de capability: novo conteudo montado em
   `mktemp`, so apos validacao total ocorre `mv` para
   `docs/specs/current/<slug>.md`. Multiplas capabilities: TODAS validadas
   antes do primeiro `mv` (falha => exit 1 sem NENHUMA mutacao, nem
   parcial).
5. Corpus/arquivo de capability inexistente + so ADDED => cria o arquivo
   (US2 cenario 4). Diretorio `current/` criado sob demanda.

## Saida (stdout)

```
FINDING|<severity>|<code>|<mensagem>
RESULT|<spec>|delta=<applied|skip|blocked>|added=<N>|modified=<N>|removed=<N>|renamed=<N>
```

Codes de erro: mesmos do delta-gate (`ref-not-found`, `added-collision`,
`renamed-target-exists`, `entry-malformed`, `corpus-malformed`, ...) — o
merge re-valida (defesa em profundidade; gate e merge podem rodar em
momentos distintos e o corpus pode ter mudado entre eles). Erros de uso:
`DIAG|` em stderr.

## Exit codes

| Exit | Significado |
|------|-------------|
| 0 | aplicado com sucesso (ou dry-run valido, ou skip) |
| 1 | bloqueado — conflito/referencia invalida; corpus intacto |
| 2 | uso incorreto / SPEC_MD inexistente |

## Invariantes

1. POSIX sh puro (Constitution II).
2. Nunca last-write-wins: qualquer pre-condicao violada bloqueia TUDO
   (clarify da spec).
2-bis. **Seguranca (gate owasp pos-plan)**: o merge RE-VALIDA o slug
   (`[a-z0-9][a-z0-9-]*`) como primeira checagem, antes de compor
   qualquer path — nunca confia que o gate rodou antes (defesa em
   profundidade contra path traversal); texto delta escrito no corpus
   sempre via `printf '%s'`, nunca como format string.
2-ter. **Estrutura do corpus (CHK034)**: o merge RE-VALIDA a estrutura de
   cada arquivo de capability existente (mesmas invariantes de
   `corpus-format.md`, code `corpus-malformed`) ANTES de aplicar qualquer
   mutacao — mesmo padrao de defesa em profundidade da invariante 2-bis
   (gate e merge podem rodar em momentos distintos; o corpus pode ter
   sido editado a mao entre um e outro). Corpus malformado bloqueia o
   merge com `corpus-malformed`, exit 1, corpus intacto.
3. Determinismo byte-a-byte: mesmos inputs (spec + corpus + --date) =>
   mesmo corpus resultante (entradas ordenadas por id).
4. O fluxo de archive na prosa de `review-features/SKILL.md` roda:
   `delta-gate.sh` -> `delta-merge.sh` -> mover para
   `_archived/<YYYY-MM-DD>-<feature>/` (fluxo existente intacto — US2
   cenario 5).
5. Teste: `tests/test_delta-merge.sh`.
