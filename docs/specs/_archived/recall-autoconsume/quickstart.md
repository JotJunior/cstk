# Quickstart / Cenarios de Teste: recall-autoconsume

**Feature**: `recall-autoconsume` | **Spec**: [spec.md](./spec.md) |
**Contrato**: [contracts/cstk-recall-context.md](./contracts/cstk-recall-context.md)

Cenarios criticos do modo `cstk recall --context`. Mapeiam para cenarios novos
em **`tests/cstk/test_recall.sh`** (sem arquivo orfao — o modo entra no mesmo
`cli/lib/recall.sh`, ver FR-020 / convencao do repo).

> **LICAO v3.17.0 (CRITICA)**: CADA cenario abaixo MUST rodar em DOIS ambientes
> — HOME real E HOME falso (CI-like, `HOME=$tmp` sem `~/.claude`), resolvendo
> helpers via `CSTK_LIB="$REPO_ROOT/cli/lib"`. Fixtures de bytes crus usam
> escapes **octais `\NNN`**, nunca hex `\xHH`. Isola o indice via DB de fixture
> (`--db "$tmp/k.db"` ou `CSTK_KNOWLEDGE_DB="$tmp/k.db"`).

---

## Cenario 1 — Bloco markdown com proveniencia (happy path, US1/US2)

1. Popular DB de fixture com decisoes/bloqueios de feature `outra-feature`
   (via `cstk recall --ingest` ou SQL direto no fixture).
2. `cstk recall --context "termo relevante" --limit 4 --db "$tmp/k.db"`
3. **Expected**: stdout = bloco markdown com cabecalho `> Aprendizado
   recuperado (read-back loop) — K achados...` + ate 4 linhas `- **[type]**
   proj/feat/wave (ts): body`. Formato distinto do modo busca (1 linha/achado).
   Exit 0. (SC-001)

## Cenario 2 — Anti-eco: feature corrente excluida (US1 cenario 2, SC-002)

1. DB de fixture com registros de `feat-A` E `feat-B` que casam a query.
2. `cstk recall --context "termo" --exclude-feature feat-A --db "$tmp/k.db"`
3. **Expected**: nenhuma linha com `/feat-A/` no bloco; apenas `/feat-B/`.
   (SC-002 = 0% auto-eco)

## Cenario 3 — Zero match => no-op (US1 cenario 3, US3)

1. DB de fixture sem registros casando a query (ou indice vazio).
2. `cstk recall --context "tokeninexistentexyz" --db "$tmp/k.db"`
3. **Expected**: stdout **vazio**, exit 0, sem erro. (FR-012)

## Cenario 4 — Composicao OR (Decision 1, FR-009)

1. DB de fixture com uma linha que casa `tokenA` mas NAO `tokenB`, e outra que
   casa `tokenB` mas NAO `tokenA`.
2. `cstk recall --context "tokenA tokenB" --db "$tmp/k.db"`
3. **Expected**: AMBAS as linhas aparecem (OR — qualquer termo). Contraste com
   o modo busca (AND-implicito) que retornaria 0 para os mesmos termos disjuntos.
   Valida que OR != AND e que o default de busca NAO mudou.

## Cenario 5 — Teto de bytes trunca (FR-006, SC-004)

1. DB de fixture com >4 achados de body longo (ex: 500 chars cada) que casam.
2. `cstk recall --context "termo" --limit 4 --max-bytes 600 --db "$tmp/k.db"`
3. **Expected**: `wc -c` do stdout <= 600. Bloco contem menos achados do que
   `--limit` permitiria (cortado pelo teto de bytes), cada achado inteiro (sem
   corte no meio). (SC-004 — verificar em 100% das execucoes)

## Cenario 6 — Default --limit (3-5)

1. DB de fixture com 10 achados casando.
2. `cstk recall --context "termo" --db "$tmp/k.db"` (sem --limit)
3. **Expected**: exatamente 4 achados (default). (FR-004)

## Cenario 7 — sqlite3 ausente => no-op (US3 cenario 1, SC-003)

1. PATH stub sem `sqlite3` (mascarar via `PATH` que nao contem sqlite3).
2. `cstk recall --context "termo" --db "$tmp/k.db"`
3. **Expected**: exit 0, stdout vazio, opcional aviso em stderr, sem stack
   trace. (SC-003 = no-op em 100%)

## Cenario 8 — jq ausente (no passo PRE-DECISAO) (US3 cenario 1)

1. Simular derivacao de termos sem `jq` no PATH.
2. **Expected**: passo PRE-DECISAO degrada para no-op; orquestrador avanca a
   fase normalmente (sem chamar `--context` sem termos).

## Cenario 9 — DB ausente => no-op (US3 cenario 2)

1. `--db "$tmp/inexistente.db"` (arquivo nao existe).
2. `cstk recall --context "termo" --db "$tmp/inexistente.db"`
3. **Expected**: exit 0, stdout vazio. (FR-012)

## Cenario 10 — DB corrompido => no-op (US3 cenario 2)

1. Criar `$tmp/k.db` com bytes invalidos (NAO um sqlite valido). Bytes crus em
   OCTAL `\NNN`.
2. `cstk recall --context "termo" --db "$tmp/k.db"`
3. **Expected**: `PRAGMA quick_check != ok` detectado, exit 0, stdout vazio.
   (FR-012)

## Cenario 11 — Read-only verificavel (FR-014, SC-006)

1. DB de fixture populado; capturar `stat` (size + mtime) antes.
2. `cstk recall --context "termo" --db "$tmp/k.db"`
3. **Expected**: size + mtime do DB INALTERADOS apos a invocacao. Nenhuma
   escrita no indice. (SC-006 — read-only)

## Cenario 12 — HOME falso == HOME real (SC-005, licao v3.17.0)

1. Rodar o Cenario 1 com `HOME=$tmp_fake` (sem `~/.claude`) e
   `CSTK_LIB="$REPO_ROOT/cli/lib"`, `--db "$tmp/k.db"`.
2. **Expected**: saida IDENTICA ao Cenario 1 com HOME real. A resolucao de db e
   o caminho de leitura NAO dependem de `~/.claude`. (SC-005)

## Cenario 13 — Injecao SQL/FTS nos termos (seguranca, reuso de escaping)

1. `cstk recall --context "termo'; DROP TABLE knowledge_fts; --" --db "$tmp/k.db"`
2. **Expected**: tratado como texto literal (via `sql_escape` + `fts_phrase_escape`),
   sem efeito de SQLi; DB intacto (combina com Cenario 11). Reusa o escaping ja
   testado do modo busca.

## Cenario 14 — NUL em input rejeitado (RECALL_EXIT_USAGE)

1. `cstk recall --context "$(printf 'a\000b')" --db "$tmp/k.db"`
2. **Expected**: exit 2 (`RECALL_EXIT_USAGE`), input com NUL rejeitado antes de
   qualquer escaping. (consistente com modo busca)

## Cenario 15 — Auditabilidade do consumo (FR-016/FR-017, SC-007)

> Cenario de integracao (orquestrador), nao do modo `--context` isolado.

1. Apos uma onda specify/plan que consumiu o indice com K>0, inspecionar o
   `state.json`.
2. **Expected**: existe uma Decisao com etapa specify/plan, contexto contendo
   "read-back"/"consumo de conhecimento", K e os termos. K=0 NAO gera Decisao
   dedicada. (SC-007)

---

## Matriz cenario -> requisito -> SC

| Cenario | FR(s) | SC |
|---------|-------|-----|
| 1 | FR-001, FR-002, FR-003 | SC-001 |
| 2 | FR-005 | SC-002 |
| 3 | FR-012 | — |
| 4 | FR-009 (composicao OR) | — |
| 5 | FR-006 | SC-004 |
| 6 | FR-004 | — |
| 7 | FR-012, FR-018 | SC-003 |
| 8 | FR-012 | SC-003 |
| 9 | FR-012 | — |
| 10 | FR-012 | — |
| 11 | FR-014 | SC-006 |
| 12 | FR-020 (HOME falso) | SC-005 |
| 13 | FR-002 (reuso escaping) | — |
| 14 | (consistencia busca) | — |
| 15 | FR-016, FR-017 | SC-007 |
