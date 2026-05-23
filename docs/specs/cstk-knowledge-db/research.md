# Phase 0 — Research: cstk-knowledge-db

**Feature**: `cstk-knowledge-db` | **Date**: 2026-05-23 | **Spec**:
[spec.md](./spec.md)

Este documento consolida as decisoes tecnicas (Phase 0). Os tres
`[NEEDS CLARIFICATION]` originais foram resolvidos na fase `clarify`
(ver `spec.md` §Clarifications). As decisoes abaixo derivam dessas
respostas e da pesquisa de alinhamento com o codebase existente (`cli/`,
`global/skills/agente-00c-runtime/scripts/`, suite `tests/`).

---

## Decision 1 — Backend de armazenamento: SQLite com FTS5

**Decision**: usar SQLite (`sqlite3` CLI) como engine do indice de
conhecimento, com uma tabela virtual FTS5 para busca full-text. DB unico
e global ao usuario em `~/.claude/cstk/knowledge.db` (override via env
`CSTK_KNOWLEDGE_DB` para testes).

**Rationale**:

- SQLite e zero-config, single-file, e ja amplamente disponivel em
  ambientes de dev (macOS embute `sqlite3`; Linux via pacote comum). O
  `sqlite3` CLI satisfaz busca, upsert e FTS5 sem servidor.
- FTS5 entrega busca full-text com ranking por relevancia (`bm25()`)
  nativamente — atende FR-004 e FR-010 (ordenacao por relevancia) sem
  reimplementar ranking em shell.
- Single-file derivavel = descartavel/reconstruivel (FR-014, FR-015):
  apagar o arquivo e rodar `--reindex` reconstroi tudo a partir dos
  `state.json` / state-history.
- WAL mode (Decision 3) da concorrencia multi-processo segura sem lock
  de aplicacao.

**Alternatives considered**:

- **Arquivos texto + grep**: rejeitado. Sem ranking, sem upsert
  idempotente robusto, sem busca full-text com sintaxe. Idempotencia por
  chave composta exigiria reimplementar dedup em shell — fragil.
- **JSON Lines + jq**: rejeitado. jq nao faz full-text ranking; busca
  seria linear sem indice; upsert exigiria reescrever o arquivo inteiro
  (perda de registros sob concorrencia).
- **DuckDB / outro engine**: rejeitado. Menos ubiquo que SQLite;
  carve-out de dep opcional fica mais caro de justificar.

**Verificacao empirica** (FTS5 disponivel no ambiente):

```
sqlite3 :memory: "CREATE VIRTUAL TABLE t USING fts5(x); \
  INSERT INTO t VALUES('hello world'); \
  SELECT x FROM t WHERE t MATCH 'hello';"
-> hello world  (FTS5 compilado e funcional)
```

---

## Decision 2 — Deps opcionais sob carve-out (Principio II amendment 1.1.0)

**Decision**: `sqlite3` e `jq` entram pela carve-out de deps opcionais
da constitution (Principio II, amendment 1.1.0), satisfazendo as tres
condicoes cumulativas (a)(b)(c). Toda referencia a `sqlite3` fica
confinada a UM unico arquivo (`cli/lib/knowledge.sh`); `jq` ja tem
precedente confinado em `cli/lib/hooks.sh` mas, para a leitura do
`state.json` na ingestao, este projeto adiciona o uso de `jq` tambem em
`cli/lib/knowledge.sh` — confinamento permanece de UM arquivo por
biblioteca (FR-017 exige que a integracao com `secrets-filter.sh`
permaneca confinada a um unico arquivo; mesmo principio para sqlite3/jq).

**Rationale**:

- FR-020 exige cumprir (a) fallback graceful testado, (b) referencias
  confinadas a um arquivo identificavel, (c) dep declarada com
  justificativa/path/fallback no `plan.md`.
- (a) Sem `sqlite3`: ingestao emite aviso e pula (degradacao graciosa,
  FR-018); `recall` informa que a memoria nao esta disponivel. Sem `jq`:
  ingestao nao consegue parsear `state.json` — mesma degradacao
  graciosa. Ambos os caminhos sao cobertos por teste (FR-019).
- (b) `grep -rn 'sqlite3' cli/lib/` deve casar somente
  `cli/lib/knowledge.sh`. Mesmo para o uso de `jq` adicionado por esta
  feature.
- (c) Declarado em `plan.md` §Optional-dep registry.

**Alternatives considered**:

- **Tornar sqlite3 dep obrigatoria**: rejeitado. Viola Principio II MUST
  (deps obrigatorias sem fallback proibidas) e o invariante de
  degradacao graciosa (US3/FR-018).
- **Embutir um mini-engine em sh puro**: rejeitado. Reimplementar FTS +
  WAL em shell e inviavel e fragil; contradiz Principio V (profundidade,
  nao reinvencao).

---

## Decision 3 — Concorrencia: WAL + busy_timeout + retry/backoff

**Decision**: abrir o DB com `PRAGMA journal_mode=WAL;` e
`PRAGMA busy_timeout=5000;` (~5s). Em "database is locked" persistente
alem do busy_timeout, aplicar retry/backoff limitado (poucas tentativas
com sleep crescente) e, se ainda assim falhar, degradar graciosamente
(aviso + pular ingestao). NAO reaproveitar o file-lock do runtime
transacional (`state-lock.sh`).

**Rationale**:

- Resolve FR-016 conforme clarify: multiplas `cstk session`/worktrees
  ingerindo quase-simultaneamente no DB global nao podem corromper nem
  perder registros. WAL permite leitores concorrentes + um escritor;
  `busy_timeout` serializa escritores sem corromper.
- Reusar o `state-lock.sh` acoplaria a camada de conhecimento (aditiva,
  best-effort) ao lock transacional (caminho critico) — sob lock
  prolongado a ingestao estagnaria, ferindo o invariante de "zero risco
  no caminho critico".
- WAL e setado uma vez por DB (persistente no header) mas reconfirmado em
  cada conexao via PRAGMA por seguranca.

**Alternatives considered**:

- **Lock de arquivo proprio (flock/mkdir)**: rejeitado. SQLite ja
  serializa escritores internamente sob WAL+busy_timeout; lock externo
  seria redundante e poderia introduzir o mesmo problema de estagnacao.
- **Reusar state-lock.sh**: rejeitado explicitamente pela clarify
  (FR-016).

---

## Decision 4 — Idempotencia: upsert por chave de proveniencia

**Decision**: chave de identidade = tupla
`(project, feature, wave, type, source_id)`. Persistir em cada tabela
como UNIQUE; ingestao usa `INSERT ... ON CONFLICT(<chave>) DO UPDATE`
(upsert) — reflete a versao mais recente (FR-008) sem duplicar (FR-007).

**Rationale**:

- FR-007 define exatamente essa tupla como discriminador. Um bloqueio que
  muda de pendente para respondido entre ondas atualiza a mesma linha
  (Edge Case "mesma proveniencia que mudou").
- `source_id` = id do registro no `state.json` (`dec-NNN`, `bloq-NNN`,
  id de skill_invoked sintetizado de onda+indice). Para retros sem id
  proprio, sintetizar id estavel a partir de (wave + indice no array).

**Alternatives considered**:

- **Hash do conteudo como chave**: rejeitado. Mudanca de texto (ex:
  bloqueio respondido) geraria nova linha — viola FR-008 (upsert, nao
  insert).
- **Apenas source_id global**: rejeitado. Ids como `dec-001` colidem
  entre features/projetos diferentes; proveniencia completa e necessaria.

---

## Decision 5 — Filtro de segredos confinado, escopo texto-livre

**Decision**: reusar `secrets-filter.sh scrub` (do runtime) aplicado
SOMENTE aos campos de texto livre antes de persistir: decisoes
(justificativa/contexto/evidencia), bloqueios
(pergunta/contexto-para-resposta), retros (texto). Campos
estruturados/enumerados (ids, scores, timestamps, proveniencia, nomes de
skill) NAO passam pelo filtro. A invocacao de `secrets-filter.sh` fica
confinada a `cli/lib/knowledge.sh`.

**Rationale**:

- FR-017: o filtro nas chaves de upsert (proveniencia, source_id)
  corromperia a identidade do registro e quebraria a idempotencia
  (FR-007). Aplicar so em texto livre preserva a chave e ainda evita
  vazamento de segredos no conteudo pesquisavel.
- `state.json` ja passou por filtros de escrita do runtime, mas o scrub
  na fronteira de ingestao e defesa em profundidade (Principio IV — nada
  sai do ambiente; ainda assim, conteudo persistido nao deve carregar
  segredos crus).

**Verificacao empirica** (helper presente no runtime):

```
ls ~/.claude/skills/agente-00c-runtime/scripts/secrets-filter.sh
-> existe; subcomando `scrub` disponivel.
```

**Alternatives considered**:

- **Scrub no objeto inteiro**: rejeitado (mangle de ids/proveniencia,
  quebra upsert).
- **Sem scrub (confiar no state.json)**: rejeitado. FR-017 exige
  tratamento na fronteira; defesa em profundidade.

---

## Decision 6 — Localizacao no codebase + convencao de comando

**Decision**: a logica vive em `cli/lib/knowledge.sh` (biblioteca
sourceavel, define funcoes `knowledge_ingest`, `recall_main` e helpers).
O comando de usuario e `cstk recall`, despachado pelo binario `cstk` via
a convencao existente (`cli/lib/recall.sh` define `recall_main`). Para
evitar duplicar a logica, `cli/lib/recall.sh` faz `. knowledge.sh` e
chama o `recall_main` la definido — OU `recall.sh` e o arquivo unico que
contem tudo. Decisao final no data-model/contracts: **um unico arquivo
`cli/lib/recall.sh`** que concentra ingestao + recall + reindex,
mantendo o confinamento de sqlite3/jq/secrets-filter a UM arquivo
(condicao (b) do carve-out). A ingestao pos-onda e invocada por um shim
do runtime que chama `cstk recall --ingest` (ou funcao exportada),
mantendo o orquestrador desacoplado do schema.

**Rationale**:

- O dispatcher `cstk` (cli/cstk) mapeia `cstk <cmd>` para
  `cli/lib/<cmd>.sh::<cmd>_main`. `recall` segue o padrao →
  `cli/lib/recall.sh` com `recall_main`.
- Confinar TUDO (sqlite3, jq, secrets-filter, schema) em
  `cli/lib/recall.sh` satisfaz a condicao (b) do carve-out num unico
  grep-alvo e simplifica o mapeamento de teste
  (`tests/cstk/test_recall.sh`).
- A ingestao pos-onda e disparada por evento de fim-de-onda; o
  orquestrador/runtime invoca o mesmo arquivo (ex:
  `cstk recall --ingest --state-dir DIR` ou um helper
  `knowledge-ingest.sh` no runtime que delega). Para nao espalhar
  sqlite3 no runtime, o caminho preferido e o runtime chamar o binario
  `cstk` (degrada gracioso se `cstk` ausente). Detalhe no contracts.

**Alternatives considered**:

- **Espalhar logica entre runtime e cli**: rejeitado. Espalharia
  sqlite3/jq por dois arquivos, ferindo a condicao (b).
- **Novo top-level command separado de recall para ingest**: rejeitado.
  Mantemos `recall` como porta unica com flag `--ingest`/`--reindex`,
  menor superficie de CLI.

---

## Decision 7 — Mapeamento de teste e fixtures

**Decision**: `cli/lib/recall.sh` → `tests/cstk/test_recall.sh` (convencao
do repo). Fixtures de `state.json` sinteticos em
`tests/cstk/fixtures/`. Bytes crus em fixtures (se houver) usam escapes
OCTAIS `\NNN`, nunca hex `\xHH` (portabilidade dash/CI). Degradacao
graciosa (sqlite3 ausente, jq ausente, DB corrompido) coberta por teste
(FR-019) simulando PATH sem o binario.

**Rationale**:

- CLAUDE.md §"Como testar scripts shell": `cli/lib/<n>.sh` mapeia para
  `tests/cstk/test_<n>.sh`; `--check-coverage` falha em orfao (FR-022,
  SC-007).
- Memoria do projeto: hex `\xHH` nao e interpretado por dash/CI; usar
  octal sempre.

**Verificacao empirica** (convencao de mapeamento ativa):

```
grep -n 'cstk/test_' CLAUDE.md
-> "cli/lib/<n>.sh" -> "tests/cstk/test_<n>.sh"
```

---

## Resumo de NEEDS CLARIFICATION

| Origem | Status |
|--------|--------|
| Q1 (escopo vs memoria externa) | Resolvido (clarify): escopo auto-contido — FR-023 |
| Q2 (modelo de concorrencia SQLite) | Resolvido (clarify): WAL+busy_timeout — FR-016 |
| Q3 (escopo do secrets-filter) | Resolvido (clarify): texto-livre — FR-017 |

**NEEDS CLARIFICATION restantes**: 0.
