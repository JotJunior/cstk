# Research: Recall Memory Mirror

**Feature**: `recall-memory-mirror` | **Date**: 2026-05-27 | **Phase**: 0 (Research)

Resolucao de unknowns tecnicos antes do design. Duas das decisoes mais impactantes
(`project` derivado de `basename`; `--ingest` aditivo) ja foram resolvidas na fase
clarify (CQ1 dec-006, CQ2 dec-007, ambas score 3). Esta secao consolida o restante
e formaliza o raciocinio empirico das que ja existem.

## Decision 1 — Tabela DEDICADA `memories` (nao reuso de `knowledge_fts`-como-base)

**Decision**: criar uma tabela relacional `memories` separada das 9 tabelas
existentes (`decisions`, `bloqueios`, `retros`, `skills`, `executions`, `waves`,
`alert_signals`, `tasks`, `events`), e alimentar a FTS5 virtual `knowledge_fts`
existente com linhas de `type='memory'` (mesmo padrao das tabelas de texto-livre).

**Rationale**:
- A invariante C-003 (separacao de tabelas) exige que `memories` nunca derive de
  telemetria. Uma tabela dedicada e a forma mais simples de garantir isso por
  construcao: a query de busca filtra por `type`, e nada cruza dados.
- `knowledge_fts` ja e o ponto de unificacao de busca (decisions/bloqueios/retros/skills
  todos inserem la com `type` discriminador). Reusa-la para `memory` da SC-001 de graca:
  `cstk recall "termo"` passa a retornar memorias sem nenhuma flag nova, pois o SELECT
  ja varre `knowledge_fts` inteiro ordenado por `bm25`.
- `tasks`/`events` (camada B) NAO alimentam `knowledge_fts` (sao estruturados/numericos).
  `memories` SIM alimenta — e texto-livre buscavel, igual a decisions/bloqueios.

**Evidencia empirica** (recall.sh L455-494): a FTS5 `knowledge_fts` tem colunas
`body, type UNINDEXED, project UNINDEXED, feature UNINDEXED, wave UNINDEXED,
source_id UNINDEXED, source_ts UNINDEXED`. O padrao de insercao (L970-972 para
decisions) e: `DELETE FROM knowledge_fts WHERE type=... AND project=... AND
feature=... AND wave=... AND source_id=...; INSERT INTO knowledge_fts(...) VALUES(...)`.
Memorias reusam exatamente esse upsert-em-FTS, mapeando: `project`→project do dir,
`feature`→`'memory'` literal (ou slug), `wave`→`'-'`, `source_id`→slug.

**Alternatives considered**:
- *Reusar `decisions` com `type='memory'`*: rejeitado — viola C-003 (mistura semantica
  e schema), e `decisions` tem colunas (`score`, `etapa`, `agente`) sem sentido p/ memoria.
- *Tabela separada SEM alimentar knowledge_fts*: rejeitado — quebraria SC-001 (busca
  unificada); exigiria UNION manual no SELECT, mais codigo e mais frageis.

## Decision 2 — Bump de schema_version 3 → 4 (idempotente)

**Decision**: `RECALL_SCHEMA_VERSION=4`. O DDL ganha `CREATE TABLE IF NOT EXISTS
memories (...)`. O `INSERT INTO schema_meta(...) ON CONFLICT DO UPDATE` ja existente
atualiza a versao gravada. Banco v3 pre-existente ganha a tabela sem perda.

**Rationale**: a feature `knowledge-db-metrics` ja estabeleceu o padrao de bump
idempotente (v1→v2→v3) via `CREATE TABLE IF NOT EXISTS` + `ON CONFLICT` no schema_meta
(recall.sh L495-500). `memories` segue o mesmo trilho — nenhuma migracao destrutiva,
nenhum `ALTER` necessario (tabela nova, nao coluna nova).

**Evidencia empirica**: `sqlite3 ~/.claude/cstk/knowledge.db "SELECT value FROM
schema_meta WHERE key='schema_version'"` retorna `3` no DB atual; `.tables` confirma
ausencia de `memories`. O proximo `--ingest`/`--reindex` aplicara o DDL v4 (que e
super-conjunto do v3) sem tocar dados existentes.

**Gotcha herdado** (recall.sh L521-537): a migracao v2→v3 (`tasks.titulo`) precisou de
`PRAGMA table_info` + `ALTER TABLE ADD COLUMN` porque `CREATE TABLE IF NOT EXISTS` NAO
altera tabela ja-existente. `memories` NAO sofre disso: e tabela nova; em DB v3
pre-existente o `IF NOT EXISTS` simplesmente cria. Nenhum `ALTER` na migracao v3→v4.

**Alternatives considered**:
- *Nao versionar (deixar schema_version=3)*: rejeitado — perde rastreabilidade; um
  `--reindex` futuro nao saberia distinguir DBs com/sem memories. Bump e barato e correto.

## Decision 3 — Localizacao do diretorio `memory/` via forward-encoding (CQ1, dec-006)

**Decision**: `encoded-path = sed 's|^/||; s|[/_]|-|g; s|^|-|'` aplicado ao path
absoluto do projeto, depois `~/.claude/projects/<encoded-path>/memory/`.

**Rationale**: e a codificacao que o harness do Claude Code usa de fato para persistir
auto-memories. CQ1 fixou `project = basename(projeto_alvo_path)` (paridade com a
telemetria existente, que ja usa `basename` em recall.sh L636).

**Evidencia empirica** (re-verificada nesta onda de plan):
```
/Users/jot                                          -> -Users-jot
/Users/jot/Projects/_lab/Jot/misc/cstk    -> -Users-jot-Projects--lab-Jot-misc-cstk
```
E o dir real `~/.claude/projects/-Users-jot-Projects--lab-Jot-misc-cstk/memory/`
existe e contem 31 arquivos `.md` (verificado via `ls`).

**Limitacao conhecida e aceita** (CQ1): no `--reindex`, sem `state.json` para mapear o
encoded-path de volta ao path original, o `project` e derivado do proprio encoded-path
(`basename` do segmento final). Projetos cujo basename original tinha underscore (ex:
`my_project` → encoded `...my-project`) terao `project=my-project` no reindex
(inconsistente com o ingest normal que le `basename(projeto_alvo_path)` direto). Aceito
porque (a) `--ingest --state-dir` e o caminho principal (orquestradores), (b) `--reindex`
e reconstrucao corretiva. Documentado em data-model §reverse-derivation.

## Decision 4 — `--ingest` aditivo dentro de `recall_mode_ingest` (CQ2, dec-007)

**Decision**: nova funcao `recall_ingest_memories STATE_DIR DB` chamada ao FINAL de
`recall_mode_ingest`, apos `recall_ingest_state_json`. Sem subcomando `--ingest-memories`.

**Rationale**: zero breaking change para orquestradores que ja invocam
`cstk recall --ingest --state-dir`. O `projeto_alvo_path` ja esta disponivel em
`$STATE_DIR/state.json` no contexto do ingest. Surface de API menor.

**Evidencia empirica** (recall.sh L1264-1317): `recall_mode_ingest` ja le o state.json
(via `recall_ingest_state_json "$_ing_state_dir/state.json"`), ja resolve `_ing_db`, ja
aplica schema, ja tem as guardas de deps (sqlite3/jq/secrets-filter). O unico ponto de
edicao e: (a) chamar `recall_ingest_memories "$_ing_state_dir" "$_ing_db"` antes do
`printf 'ingested: ...'`, e (b) acrescentar `%d memories` na linha de status. As guardas
de deps ja cobrem a degradacao graciosa para o caminho de memorias tambem.

## Decision 5 — Scrub do body via `secrets-filter.sh` (FR-005, ASI09/LLM01)

**Decision**: o body de cada `.md` passa por `recall_scrub` (que chama `$RECALL_SF scrub`)
ANTES de ser gravado em `memories.body_scrubbed` E em `knowledge_fts.body`. A descricao
(primeira linha nao-vazia) tambem e scrubbed. O `.md` original NUNCA e tocado (C-002).

**Rationale**: conteudo de `.md` de memoria e UNTRUSTED — pode conter token/senha que o
usuario colou numa nota, ou conteudo adversarial (injection). O mesmo `recall_scrub`
(recall.sh L603-605) ja usado para texto-livre de decisions/bloqueios cobre isso. O
slug, type, path e indexed_at sao estruturados (nao scrubbed; mas `path` passa por
`sql_escape` como qualquer valor).

**Evidencia empirica**: `recall_scrub VALUE` (L603) = `printf '%s' "$1" | "$RECALL_SF"
scrub`. O `RECALL_SF` ja e resolvido por `recall_secrets_filter_path` nas guardas de
deps de ingest/reindex (L1292-1295, L1669-1672). Memorias reusam essa mesma variavel —
nenhuma nova dep, confinamento C-001/FR-014 preservado.

**Gotcha de injection FTS5**: o body scrubbed AINDA precisa passar por `sql_escape`
(camada SQL) ao ser interpolado no INSERT, e nao precisa de `fts_phrase_escape` (isso e
so para QUERY de busca, nao para o conteudo indexado). O conteudo gravado em
`knowledge_fts.body` e texto literal; a busca o trata como documento, nao como query.

## Decision 6 — `--reindex` re-le os `.md`, NUNCA o state.json (FR-009/FR-010, C-004)

**Decision**: `recall_mode_reindex` ganha, apos o loop de `recall_ingest_state_json`, uma
varredura de `~/.claude/projects/*/memory/*.md` que chama `recall_ingest_memories` (ou um
helper de baixo nivel compartilhado) por projeto encontrado. As memorias sao reconstruidas
dos arquivos `.md`, jamais do state.json.

**Rationale**: e a invariante critica de resiliencia (US3/C-004). Como `--reindex` faz
`rm -f` do DB antes de repopular (recall.sh L1681), se as memorias dependessem do
state.json elas seriam perdidas em qualquer reindex (state.json nao guarda memorias).
Re-ler os `.md` (fonte canonica imutavel) garante reconstrucao 100% (SC-002).

**Evidencia empirica** (recall.sh L1703-1716): o reindex ja varre
`*/.claude/feature-00c-state/*/state.json` e `*/.claude/agente-00c-state/state.json` via
`find` sob `$HOME` (default). A varredura de memorias e analoga mas sobre
`$HOME/.claude/projects/*/memory/*.md` — raiz diferente, mesmo padrao de loop com
`IFS=newline`. O gotcha do `find` exit!=0 com matches validos (L1698-1707, `|| :` em vez
de `|| _rx=""`) DEVE ser replicado na varredura de memorias para nao perder dados.

**Alternatives considered**:
- *Derivar memorias do state.json no reindex*: rejeitado — viola C-004/FR-010 frontalmente;
  state.json nao contem memorias, resultaria em perda total no reindex.

## Decision 7 — Derivacao de `type` por convencao de nome de arquivo (FR-007)

**Decision**: `MEMORY.md`→`index`; `feedback_*`→`feedback`; `project_*`→`project`;
`reference_*`→`reference`; demais→`user`. Via `case` POSIX sobre o basename.

**Rationale**: a convencao de nome ja e usada de fato (o dir real tem
`feedback_*.md`, `project_*.md`, `reference_*.md`, `MEMORY.md`). Derivar `type` do prefixo
da auditoria/filtragem util sem custo. `case` POSIX e suficiente (sem regex, sem deps).

**Evidencia empirica**: `ls ~/.claude/projects/.../memory/` mostra prefixos
`feedback_`, `project_`, `reference_` e `MEMORY.md` — exatamente os 4 prefixos + fallback.

## Decision 8 — Enum `RECALL_TYPE_ENUM` extendido com `memory` (FR-012)

**Decision**: `RECALL_TYPE_ENUM="decision bloqueio retro skill memory"`. `validate_type`
(recall.sh L236-245) passa a aceitar `--type memory`.

**Rationale**: `--type memory` precisa ser aceito pelo `validate_type` (que itera o enum,
L237). Adicionar `memory` ao enum e a unica mudanca; o filtro `AND type = 'memory'` no
SELECT (L1405-1407) ja funciona generico. O modo `--context` (read-back) tambem se
beneficia automaticamente (usa o mesmo `validate_type`).

**Evidencia empirica** (recall.sh L73, L236-245): `RECALL_TYPE_ENUM="decision bloqueio
retro skill"`; `validate_type` faz `for _vt in $RECALL_TYPE_ENUM; do [ "$1" = "$_vt" ] &&
return 0; done`. Adicionar `memory` ao string e suficiente.

## Decision 9 — `--list-memories` como modo/flag novo (FR-013, US4)

**Decision**: `cstk recall --list-memories [--project P]` lista `slug` + `description`
(sem body) de `memories`. Implementado como ramo no dispatcher `recall_main` (detectar
`--list-memories` na varredura de argv, analogo a `--ingest`/`--reindex`/`--context`),
roteando para `recall_mode_list_memories`.

**Rationale**: `--list-memories` nao e busca FTS (nao tem query), e um SELECT direto da
tabela relacional `memories` ordenado por slug. Modo proprio mantem `recall_mode_search`
simples. Degradacao graciosa: sqlite3 ausente → no-op exit 0; sem memorias → stdout vazio
exit 0 (US4 cenario 2).

**Evidencia empirica** (recall.sh L574-588): `recall_main` ja despacha por varredura de
argv com precedencia (ultima flag vence). Adicionar `--list-memories) _mode="list-memories"`
ao loop e um `case` no dispatch e o padrao estabelecido.

**Alternatives considered**:
- *Embutir em `--type memory` sem query*: rejeitado — modo busca exige query obrigatoria
  (L1351); listar sem termo nao cabe la sem quebrar o contrato de busca.

## Resumo de unknowns

Nenhum `NEEDS CLARIFICATION` restante. Todas as decisoes tecnicas estao resolvidas por
clarify (CQ1/CQ2) ou por evidencia empirica do codigo existente (Decisions 1-2, 5-9).
