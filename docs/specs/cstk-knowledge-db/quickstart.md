# Quickstart / Cenarios de Teste: cstk-knowledge-db

**Feature**: `cstk-knowledge-db` | **Date**: 2026-05-23 | **Spec**:
[spec.md](./spec.md)

Cenarios de validacao end-to-end. Cada cenario e a base de um test case
em `tests/cstk/test_recall.sh`. O DB de teste usa `--db` apontando para
um tmp (override via `CSTK_KNOWLEDGE_DB`), nunca o indice global do
usuario.

> Esta feature e **single-layer** (CLI tool sobre SQLite). N/A para
> roundtrip backend↔frontend — nao ha fronteira de serializacao
> snake/camel. A "fonte da verdade" da convencao e o schema SQL em
> `cli/lib/recall.sh` (Decision 1/4 do research; data-model.md).

---

## Cenario 1 — Ingestao basica + recuperacao com proveniencia (US1, US2)

1. Preparar um `state.json` sintetico em `$TMP/featA/state.json` com 2
   decisoes, 1 bloqueio, 1 retro, 2 skills (proveniencia: project=projX,
   feature=featA, execucao_id, ondas).
2. `cstk recall --ingest --state-dir $TMP/featA --db $TMP/k.db`
3. `cstk recall "<termo presente na decisao 1>" --db $TMP/k.db`
4. **Expected**: retorna a decisao 1 com proveniencia completa (projX,
   featA, onda, data); exit 0. (FR-003, FR-011, SC-001)

---

## Cenario 2 — Filtro cross-feature exclui ruido (US1 AS1, SC-004)

1. Ingerir `state.json` de featA (projX) e de featB (projY), cada um com
   uma decisao contendo o mesmo termo `widget`.
2. `cstk recall "widget" --project projX --db $TMP/k.db`
3. **Expected**: retorna so o registro de projX/featA; NAO inclui projY.
   (FR-012, SC-004)

---

## Cenario 3 — Filtro por tipo (US1 AS2)

1. Indice com decisao + bloqueio + retro casando `deploy`.
2. `cstk recall "deploy" --type bloqueio --db $TMP/k.db`
3. **Expected**: apenas registros do tipo bloqueio. (FR-012)

---

## Cenario 4 — Limite + ordenacao por relevancia (US1 AS3)

1. Indice com 5 registros casando `cache`.
2. `cstk recall "cache" --limit 2 --db $TMP/k.db`
3. **Expected**: no maximo 2 resultados, ordenados por relevancia (bm25).
   (FR-010, FR-012)

---

## Cenario 5 — Sem resultados = sucesso (US1 AS4, FR-013)

1. Indice populado.
2. `cstk recall "termo-inexistente-xyz" --db $TMP/k.db; echo "rc=$?"`
3. **Expected**: mensagem "nenhum resultado para 'termo-inexistente-xyz'"
   e `rc=0` (NAO erro). (FR-013)

---

## Cenario 6 — Idempotencia da ingestao (US2 AS2, SC-002)

1. Ingerir `state.json` de featA. Contar linhas (`SELECT count(*)`).
2. Ingerir o MESMO `state.json` de novo. Contar linhas.
3. **Expected**: contagem identica nas duas medicoes (zero duplicatas).
   (FR-007, SC-002)

---

## Cenario 7 — Upsert reflete versao mais recente (US2 AS3, FR-008)

1. Ingerir featA com bloqueio `status=pendente`.
2. Mutar o `state.json` (mesma chave de proveniencia) para
   `status=respondido` + `resposta="..."`. Reingerir.
3. `cstk recall "<termo do bloqueio>" --type bloqueio --db $TMP/k.db`
4. **Expected**: linha unica refletindo `respondido` + a resposta; NAO
   duas linhas. (FR-008, Edge "mesma proveniencia que mudou")

---

## Cenario 8 — Fonte transacional intacta (US2 AS4, SC-006)

1. Calcular `sha256` do `state.json` (e do `state.json.sha256`).
2. Rodar `cstk recall --ingest --state-dir $TMP/featA --db $TMP/k.db`.
3. Recalcular `sha256`.
4. **Expected**: hashes byte-a-byte identicos antes/depois. (FR-009,
   SC-006)

---

## Cenario 9 — Degradacao graciosa sem sqlite3 (US3 AS1, FR-018, FR-019, SC-003)

1. Rodar ingestao com PATH manipulado para esconder `sqlite3`
   (`PATH=/usr/bin/false-dir` ou wrapper que oculta o binario).
2. `cstk recall --ingest --state-dir $TMP/featA --db $TMP/k.db; echo "rc=$?"`
3. **Expected**: aviso em stderr ("sqlite3 ausente..."), `rc=0`, o DB
   NAO foi criado/alterado, o `state.json` intacto. (FR-018, FR-019,
   SC-003)

---

## Cenario 10 — Degradacao graciosa sem jq (FR-018, FR-019)

1. Esconder `jq` do PATH. Rodar ingestao.
2. **Expected**: aviso + `rc=0`, sem alterar indice nem state.json.

---

## Cenario 11 — Indice corrompido na busca (US3 AS2)

1. Escrever lixo num arquivo `$TMP/bad.db`.
2. `cstk recall "qualquer" --db $TMP/bad.db; echo "rc=$?"`
3. **Expected**: mensagem do problema + sugestao de `--reindex`; nao
   trava; `rc=0`. (US3 AS2)

---

## Cenario 12 — Reconstrucao a partir da fonte (US4, FR-014, FR-015, SC-005)

1. Ingerir state.json de 2 features. Guardar resultado de uma busca B0.
2. Apagar o DB. `cstk recall --reindex --states-root $TMP --db $TMP/k.db`.
3. Repetir a busca B1.
4. **Expected**: B1 == B0 (mesmo conjunto, sem duplicatas). Rodar
   `--reindex` de novo nao muda contagem. (FR-014, FR-015, SC-005)

---

## Cenario 13 — Query com caracteres especiais (Edge Case)

1. Indice populado.
2. `cstk recall '"aspas" AND (parenteses) *' --db $TMP/k.db; echo "rc=$?"`
3. **Expected**: nenhum erro de sintaxe FTS5; `rc=0` (com ou sem
   resultados). (Edge "caracteres especiais")

---

## Cenario 13b — Payload adversarial de injecao na busca (A05 / CWE-89)

1. Indice com uma tabela conhecida (ex: `decisions` com >=1 linha).
2. `cstk recall "'; DROP TABLE decisions; --" --db $TMP/k.db; echo "rc=$?"`
3. **Expected**: `rc=0`, nenhum erro, e a tabela `decisions` CONTINUA
   existindo com a mesma contagem de linhas (injecao neutralizada pelo
   escaping de duas camadas). (A05 Injection)

---

## Cenario 13c — Payload adversarial de injecao na ingestao (A05 / CWE-89)

1. `state.json` sintetico com um campo de texto livre contendo
   `O'Brien'); DROP TABLE decisions; --` E um campo de proveniencia
   (ex: feature/short_name) contendo uma aspa simples.
2. `cstk recall --ingest --state-dir $TMP/adv --db $TMP/k.db; echo "rc=$?"`
3. **Expected**: `rc=0`, tabelas intactas, o registro armazenado com o
   texto literal (aspas preservadas), busca posterior recupera o texto
   sem corrupcao. (A05 Injection; valores escapados, nao executados)

---

## Cenario 14 — Concorrencia WAL (FR-016) — best-effort

1. Disparar duas ingestoes quase-simultaneas no mesmo `--db` (subshells
   em background apontando para state.json distintos).
2. Aguardar ambas.
3. **Expected**: DB nao corrompido; ambos os conjuntos de registros
   presentes (ou, sob contencao extrema, uma das ingestoes degrada
   gracioso com aviso — nunca corrompe nem aborta). (FR-016, SC-003)

> Nota de portabilidade: fixtures com bytes crus (cenario 11) usam
> escapes OCTAIS `\NNN`, nunca hex `\xHH` (dash/CI nao interpreta hex).
