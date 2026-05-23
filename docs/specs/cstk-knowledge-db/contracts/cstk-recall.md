# Contract — Comando `cstk recall`

**Feature**: `cstk-knowledge-db` | **Date**: 2026-05-23

Define o contrato do comando de **recuperacao** (e dos modos auxiliares
`--ingest` e `--reindex`) exposto via o binario `cstk`. Despachado pela
convencao existente: `cstk recall` → `cli/lib/recall.sh::recall_main`.

Implementacao confinada a `cli/lib/recall.sh` (unico arquivo com
`sqlite3`/`jq`/`secrets-filter.sh` — carve-out condicao (b)).

---

## Sinopse

```
cstk recall <query> [--project P] [--type T] [--limit N] [--db PATH]
cstk recall --ingest --state-dir DIR [--db PATH]
cstk recall --reindex [--states-root DIR] [--db PATH]
```

---

## Modo busca (default) — FR-010, FR-011, FR-012, FR-013

```
cstk recall <query> [flags]
```

| Flag/arg | Obrigatorio | Default | Descricao |
|----------|-------------|---------|-----------|
| `<query>` | sim | — | termo(s) de busca full-text |
| `--project P` | nao | (todos) | filtra por projeto de origem (FR-012) |
| `--type T` | nao | (todos) | `decision`\|`bloqueio`\|`retro`\|`skill` (FR-012) |
| `--limit N` | nao | 20 | maximo de resultados (FR-012) |
| `--db PATH` | nao | `$CSTK_KNOWLEDGE_DB` ou `~/.claude/cstk/knowledge.db` | indice |

### Comportamento

1. Se `sqlite3` ausente → aviso "memoria de conhecimento indisponivel
   (sqlite3 nao instalado)" + exit 0 (degradacao graciosa).
2. Se DB ausente → mensagem "indice vazio/ausente; rode `cstk recall
   --reindex` para popular" + exit 0.
3. Se DB ilegivel/corrompido → mensagem do problema + sugestao de
   `--reindex` + exit 0 (US3 AS2; nao trava).
4. **Sanitizacao da query** (Edge Case "caracteres especiais"; A05
   Injection / CWE-89): a entrada do usuario NUNCA e interpolada crua na
   sintaxe FTS5. ATENCAO: o `sqlite3` CLI NAO oferece bind parameters a
   partir de argv (binding nativo exige a C API / um binding de
   linguagem). Como o caminho e POSIX sh + `sqlite3` CLI, a unica
   mitigacao viavel e **escaping rigoroso de string literal**, em DUAS
   camadas cumulativas:
   - **Camada SQL** (string literal SQL): toda aspa simples `'` no valor
     e duplicada (`'` → `''`) antes de compor o SQL. Neutraliza o vetor
     classico de SQLi (ex: `O'Brien'; DROP TABLE x; --` e armazenado/
     comparado literalmente, sem injecao). Verificado empiricamente.
   - **Camada FTS5** (expressao MATCH): a query e **tokenizada em
     whitespace** e CADA token vira uma frase literal FTS5 — envolvido em
     aspas duplas, com cada `"` interno DUPLICADO (`"` → `""`) — e os
     tokens sao juntados por espaco (AND implicito do FTS5). Ex:
     `escaping FTS5` → `"escaping" "FTS5"` (ambos os termos devem
     aparecer, em qualquer posicao). Assim aspas, `*`, `(`, `)`, `:`,
     `^`, `-` e operadores booleanos sao interpretados como texto POR
     TOKEN, nunca como sintaxe — nenhum erro de sintaxe FTS5 e nenhum
     vetor de injecao. Decisao de design (fix pos-review): tratar a query
     inteira como UMA frase contigua tornava a busca multi-palavra
     inutil (so casava sequencias exatas); o token-AND restaura a
     utilidade preservando a neutralizacao de sintaxe. Verificado
     empiricamente (cenario 15 de test_recall.sh).
   O valor escapado pelas duas camadas e o que entra na string SQL final
   (o `?` abaixo e notacao logica do bind, materializado por
   substituicao escapada, NAO por bind nativo do CLI).
4a. **Rejeicao de NUL bytes** (hardening dec-015, block-001): TODO input
   do usuario (`<query>`, `--project`, `--type`, `--db`) e verificado
   quanto a bytes NUL (`\000`) ANTES de qualquer escaping/validacao/
   interpolacao. Um byte NUL trunca strings em C (e portanto no
   `sqlite3` CLI e em `jq`), podendo corromper a query ou contornar
   filtros. A presenca de qualquer NUL em um input do usuario e tratada
   como entrada invalida: **rejeitar com exit 2** (forma defensiva
   default) OU strip silencioso do(s) NUL antes de prosseguir — a
   implementacao escolhe uma das duas; este contrato exige que NUL nunca
   chegue intacto a camada SQL/FTS5. Coberto por teste com fixture de
   byte cru NUL (escape OCTAL `\000`, nunca hex).
5. Executar (notacao logica; `?` = valor escapado interpolado, nao bind
   nativo do CLI):
   `SELECT type, project, feature, wave, source_ts, source_id, body
    FROM knowledge_fts WHERE knowledge_fts MATCH ?
    [AND project = ?] [AND type = ?]
    ORDER BY bm25(knowledge_fts) LIMIT ?;`
   Os valores de `--project` e `--type` tambem sao escapados (camada
   SQL) e/ou validados (`--type` contra o enum). O `--limit` NAO e
   string-escapado: e **integer-validado** (hardening dec-015,
   block-001) — o valor DEVE casar `^[1-9][0-9]*$` (inteiro positivo);
   qualquer valor nao-inteiro (ex: `5; DROP TABLE x`, `abc`, `-1`, `0`,
   `1.5`, vazio) e **rejeitado com exit 2** ANTES de compor o SQL, nunca
   interpolado. Como `--limit` alimenta a clausula `LIMIT N` (onde N e
   sintaticamente um inteiro, nao um literal de string), a defesa correta
   e a validacao de tipo, nao o escaping: um inteiro validado entra direto
   no SQL sem risco de injecao.
6. Renderizar cada resultado COM proveniencia (FR-011): projeto, feature,
   onda, data + um trecho do conteudo. Formato legivel (uma entrada por
   bloco), parseavel o suficiente para inspecao.
7. **Sem resultados** (FR-013): imprimir "nenhum resultado para
   '<query>'" e **exit 0** (sucesso, nao erro).

### Exit codes (modo busca)

| Code | Significado |
|------|-------------|
| `0` | resultados encontrados OU nenhum resultado OU degradacao graciosa |
| `2` | uso incorreto (flag invalida, `--type` fora do enum, `--limit` nao-inteiro, NUL byte em input quando politica = rejeitar) |

---

## Modo ingestao — `--ingest`

Delegado ao contrato [ingest-helper.md](./ingest-helper.md). Mesma
implementacao (mesmo arquivo); aqui apenas a porta de CLI.

```
cstk recall --ingest --state-dir DIR [--db PATH]
```

---

## Modo reconstrucao — `--reindex` (FR-014, FR-015)

```
cstk recall --reindex [--states-root DIR] [--db PATH]
```

| Flag | Obrigatorio | Default | Descricao |
|------|-------------|---------|-----------|
| `--reindex` | sim (modo) | — | seleciona reconstrucao |
| `--states-root DIR` | nao | descoberta padrao | raiz para varrer `state.json`/state-history |
| `--db PATH` | nao | `~/.claude/cstk/knowledge.db` | indice destino |

### Comportamento

1. Se `sqlite3`/`jq` ausente → aviso + exit 0.
2. **Recriar** o DB do zero: dropar/recriar tabelas + FTS (ou apagar o
   arquivo e recriar) — indice e descartavel.
3. Varrer os `state.json` (e opcionalmente state-history) sob
   `--states-root` (descobrindo `**/.claude/feature-00c-state/*/state.json`
   e `**/.claude/agente-00c-state/state.json`) e ingerir cada um via o
   mesmo caminho de ingestao (upsert idempotente).
4. Resultado: conteudo equivalente ao que a ingestao incremental
   produziria (FR-015, SC-005). Rodar `--reindex` de novo e idempotente.

### Exit codes (reindex)

| Code | Significado |
|------|-------------|
| `0` | reconstruido OU degradacao graciosa |
| `2` | uso incorreto |

---

## Tratamento seguro de entrada (Edge Case; A05 / CWE-89)

A query do usuario pode conter aspas, `*`, `:`, `^`, `-`, parenteses
(operadores FTS5). O contrato exige que NENHUMA dessas entradas cause
erro de sintaxe NEM permita injecao de SQL/FTS: a query e escapada nas
duas camadas (SQL: `'`→`''`; FTS5: frase com `"`→`""`) e so entao
interpolada — nunca concatenada crua. Como o `sqlite3` CLI nao tem bind
nativo via argv, o escaping e a defesa primaria (nao opcional).

Hardenings adicionais ratificados em dec-015 (resolucao do block-001 do
gate owasp-security):

- **`--limit` integer-validado, nao string-escapado**: rejeitar valor
  nao-inteiro (`^[1-9][0-9]*$`) com exit 2 antes de compor o SQL. `LIMIT`
  recebe inteiro sintatico, nao literal de string — validacao de tipo e a
  defesa correta.
- **NUL bytes rejeitados/stripados em TODOS os inputs** (`<query>`,
  `--project`, `--type`, `--db`) antes de escaping/validacao/
  interpolacao. NUL trunca strings em C e pode contornar filtros; nunca
  chega intacto a camada SQL/FTS5.

Coberto por teste (`tests/cstk/test_recall.sh`), incluindo payloads
adversariais (`'; DROP TABLE ...; --`, aspas e operadores FTS5),
`--limit` nao-inteiro, e fixture de byte cru NUL (escape OCTAL `\000`).

---

## Cenarios de aceite mapeados

| Cenario (spec) | Comportamento |
|----------------|---------------|
| US1 AS1 (termo so na feature A) | resultado lista feature A com proveniencia, exclui B |
| US1 AS2 (filtro por tipo) | so registros do tipo pedido |
| US1 AS3 (limite) | no maximo N resultados, por relevancia |
| US1 AS4 (sem match) | mensagem "nenhum resultado" + exit 0 |
| US3 AS2 (indice corrompido) | informa + sugere reindex, sem travar |
| US3 AS3 / US4 (reconstrucao) | indice recriado de state.json/history, conteudo equivalente |
| US4 AS2 (reindex repetido) | idempotente, sem duplicatas |
| Edge: caracteres especiais | sem erro de sintaxe FTS5 |
| Edge: `--limit` nao-inteiro (dec-015) | rejeitado com exit 2, sem interpolacao |
| Edge: NUL byte em input (dec-015) | rejeitado (exit 2) ou stripado; nunca chega ao SQL/FTS5 |
