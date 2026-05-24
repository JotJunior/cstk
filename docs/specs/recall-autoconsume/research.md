# Phase 0 — Research: recall-autoconsume

**Feature**: `recall-autoconsume` | **Date**: 2026-05-23 | **Spec**: [spec.md](./spec.md)

Este documento resolve os unknowns tecnicos que a spec deferiu ao `/plan`
(FR-007, FR-009) e fixa as decisoes de design que governam o COMO da
implementacao. Cada secao segue o formato **Decision / Rationale /
Alternatives considered**.

---

## Decision 1 — Composicao da query: OR explicito (nao AND-implicito)

**Decision**: O modo `--context` compoe os termos derivados com **OR
explicito** do FTS5, ao contrario do modo busca (que usa AND-implicito via
`fts_query_escape` — tokens juntados por espaco). A composicao OR sera obtida
por um novo helper `fts_query_escape_or` (ou um parametro de juncao em
`fts_query_escape`) que reusa `fts_phrase_escape` por token e junta os tokens
escapados com ` OR `. O modo busca e o modo `--ingest` permanecem **inalterados**
(AND-implicito preservado como default).

**Rationale**: probe empirica no indice real (`~/.claude/cstk/knowledge.db`,
102 rows: 72 decision, 29 skill, 1 bloqueio) durante a fase plan desta propria
feature (dogfood do read-back, dec-009/dec-010):

| Composicao | Tokens | Matches |
|-----------|--------|---------|
| AND-implicito (`fts_query_escape` atual) | `recall context bm25 no op` (5) | **0** |
| OR explicito | mesmos 5 tokens | **43** |
| OR explicito | 8 tokens high-signal, anti-eco | **30** (top-4 por bm25 = decisoes reais de cstk-knowledge-db) |

AND-implicito sobre 5-8 keywords kebab-case destiladas tende a **zero match**
(query super-restritiva: exige TODOS os termos presentes em uma unica linha
`body`). Isso e exatamente a "query degenerada" que FR-009 alerta. Para recall
amplo, OR e a composicao correta — recupera linhas que casam QUALQUER termo, e
o ranking bm25 ASC + teto N pequeno (FR-004/FR-006) controlam o ruido por
construcao.

**Alternatives considered**:
- **AND-implicito (reusar `fts_query_escape` sem mudanca)**: rejeitado por
  evidencia empirica — 0 matches quebra SC-001 (injetar >=1 achado quando ha
  sinal). E o anti-padrao que FR-009 nomeia.
- **Corte de score bm25 absoluto (piso numerico)**: rejeitado por FR-007. bm25
  do FTS5 e adimensional, dependente do corpus (magnitudes ~1e-6, sem escala
  estavel nem zero natural). Corte fixo nao e portavel (quebraria SC-005) e
  introduz degradacao agressiva (zero achado havendo sinal, ferindo
  SC-001/best-effort).
- **Corte relativo-ao-topo (descartar achados muito piores que o melhor da
  pagina)**: FR-007 PERMITE (PODE, nao MUST) como futuro; default = SEM piso.
  Deferido — so se ruido aparecer na pratica. NAO entra nesta implementacao.

---

## Decision 2 — Derivacao de termos: aspectos_chave_iniciais primario, descricao_curta fallback

**Decision**: O passo PRE-DECISAO nos orquestradores deriva os termos da query
em duas fases:
1. **Fonte primaria**: `aspectos_chave_iniciais` (array de keywords semanticas
   ja destiladas) do `state.json` da feature corrente, via `jq -r`. Os termos
   kebab-case sao normalizados para whitespace (`tr '-' ' '`) para tokenizacao
   FTS5. Teto **<=8 termos** (`.[0:8]`).
2. **Fallback**: `descricao_curta` — usada **apenas** quando
   `aspectos_chave_iniciais` esta vazio/ausente OU degenera para so
   stopwords/termos vazios apos a derivacao. Tambem sob teto <=8 termos.

NUNCA concatenar as duas fontes. Query vazia/degenerada apos derivacao =>
tratada como zero resultados (no-op).

**Rationale**: FR-009 fixou esta decisao em clarify. `aspectos_chave_iniciais`
sao keywords de alto sinal (poucos tokens, alta especificidade); `descricao_curta`
e prosa (muitos tokens de baixo sinal). Concatenar ambos sob AND tenderia a zero
match (a preocupacao original); mesmo sob OR, a descricao adiciona tokens
genericos que diluem o ranking bm25. Manter as fontes separadas e usar a
primaria preserva o sinal.

**Alternatives considered**:
- **Concatenar aspectos + descricao**: rejeitado por FR-009 (dilui sinal, e sob
  AND tende a zero match).
- **So descricao_curta**: rejeitado — prosa e baixo sinal; aspectos-chave foram
  destilados exatamente para isso.
- **Teto maior que 8**: rejeitado — mais termos sob OR aumentam o recall mas
  tambem o ruido antes do corte bm25; 8 e o teto da spec (FR-009), suficiente
  dado o ranking + teto N.

---

## Decision 3 — Formato de saida: bloco markdown enxuto com proveniencia compacta

**Decision**: O modo `--context` emite um **bloco markdown auto-contido**,
distinto do formato verboso do modo busca. Estrutura:

```markdown
> Aprendizado recuperado (read-back loop) — N achados de execucoes passadas.

- **[<type>]** <project>/<feature>/<wave> (<source_ts>): <body truncado>
- **[<type>]** ...
```

Cada achado em **uma linha** (proveniencia compacta inline: type, project,
feature, wave, ts), `body` truncado por achado para caber no teto de bytes. O
bloco abre com uma linha de cabecalho (blockquote) que sinaliza proveniencia e
contagem K — pronto para injecao direta no contexto do orquestrador. Sem
achados => stdout **vazio** (no-op, sem cabecalho).

**Rationale**: US2 exige saida "ja formatada como bloco markdown enxuto pronto
para injecao em prompt (proveniencia compacta, sem cabecalhos verbosos do modo
interativo)". O modo busca usa duas linhas por achado (`[type] proj / feat /
wave / ts (sid)` + corpo indentado) — verboso para leitura humana. O modo
`--context` comprime para uma linha por achado, otimizado para densidade de
contexto. O cabecalho blockquote da ao orquestrador um marcador claro de
proveniencia ("isto vem de execucoes passadas, nao da feature corrente").

**Alternatives considered**:
- **Reusar o formato do modo busca**: rejeitado — verboso, infla o contexto da
  onda (contra FR-006/SC-004), e mistura cabecalho de leitura humana com
  injecao programatica.
- **JSON**: rejeitado — o consumidor e um prompt de LLM (orquestrador), nao
  codigo; markdown enxuto e mais denso e legivel no contexto. JSON exigiria
  pos-processamento, contra US2 ("consumido programaticamente sem
  pos-processamento" = sem reparse, nao = formato de maquina).

---

## Decision 4 — Teto de tamanho: por N (--limit) E por bytes (--max-bytes)

**Decision**: Dois tetos cumulativos:
1. **Por numero de achados**: `--limit N`, default **4** (dentro da faixa 3-5
   da spec), reusando `validate_limit` existente.
2. **Por bytes totais do bloco**: `--max-bytes N`, default **2000** bytes
   (~500 tokens, dimensao prudente para injecao). O bloco e montado achado a
   achado; ao atingir o teto de bytes, para de adicionar achados (trunca pelo
   conjunto, nao no meio de um achado — corta o ultimo achado inteiro que nao
   coube). Cada `body` individual tambem e truncado (ex: 280 chars) antes de
   compor a linha, para que um unico achado gigante nao estoure sozinho.

O teto efetivo e o **menor** dos dois (N atingido OU bytes atingido).

**Rationale**: FR-006 exige teto "por numero de achados E por tamanho total".
SC-004 exige que o bloco "nunca exceda o teto configurado em 100% das
execucoes". So o teto N nao basta: 4 achados com bodies longos poderiam estourar
o orcamento de contexto. O teto de bytes e a garantia dura. Default 2000 bytes
e prudente (cabe folgado num prompt); observavel via flag.

**Alternatives considered**:
- **So teto N**: rejeitado por FR-006 (exige tambem por tamanho) e SC-004.
- **Truncar no meio de um achado ao atingir bytes**: rejeitado — produziria
  proveniencia/body cortados ao meio (ilegivel). Truncar pelo ultimo achado
  inteiro que cabe e mais limpo.
- **Teto de tokens (nao bytes)**: rejeitado — contar tokens em sh puro nao e
  portavel (depende de tokenizer). Bytes e uma proxy estavel e POSIX-mensuravel
  (`wc -c`).

---

## Decision 5 — Anti-eco via --exclude-feature (filtro feature !=)

**Decision**: O modo `--context` aceita `--exclude-feature <name>` que adiciona
`AND feature != '<sql_escaped>'` ao WHERE. O orquestrador SEMPRE passa
`--exclude-feature=<short_name corrente>` no passo PRE-DECISAO.

**Rationale**: FR-005 + Edge Case "Auto-eco". A coluna `feature` ja existe
UNINDEXED em `knowledge_fts` (schema da spec arquivada) — sem mudanca de schema
(Out of Scope respeitado). O valor passa por `sql_escape` (defesa SQLi,
consistente com o modo busca). Sem o filtro, uma feature que ja ingeriu seus
proprios registros numa onda anterior re-injetaria o que ela mesma produziu
(SC-002 = 0% auto-eco).

**Alternatives considered**:
- **Filtrar no orquestrador (pos-processar a saida)**: rejeitado — o filtro no
  SQL e mais barato e correto por construcao; pos-processar exigiria parsear a
  proveniencia de volta.
- **Excluir por execucao_id em vez de feature**: rejeitado — `feature` e a
  granularidade correta do anti-eco (a feature corrente pode ter multiplas
  ondas/execucoes); `feature` ja esta na FTS table.

---

## Decision 6 — Degradacao graciosa: reusar exatamente o mecanismo da busca/ingestao

**Decision**: O modo `--context` reusa os mesmos gates de degradacao do modo
busca, todos resultando em **no-op silencioso** (exit `RECALL_EXIT_OK`, stdout
vazio):
1. `sqlite3` ausente (`recall_have_sqlite3`).
2. `jq` ausente (`recall_have_jq`) — necessario no passo PRE-DECISAO do
   orquestrador (deriva termos do state.json); o modo `--context` em si nao usa
   jq, mas o documento declara a dep porque a integracao depende dela.
3. DB ausente (`! -f`).
4. DB corrompido/ilegivel (`PRAGMA quick_check != ok`).
5. Zero resultados (query degenerada ou nenhum match) — stdout vazio.
6. `database is locked` durante leitura — WAL ja configurado pela ingestao
   tolera leitura concorrente; o `-cmd '.timeout 5000'` (busy_timeout) absorve
   contencao curta; se ainda assim falhar, `recall_query_sql` retorna vazio =>
   no-op.

**Read-only (FR-014)**: o modo `--context` NUNCA chama `recall_run_sql` nem
`recall_apply_schema` (caminhos de escrita). Usa exclusivamente
`recall_query_sql` (leitura). NAO toca o `state.json` (o registro auditavel e
responsabilidade do ORQUESTRADOR, via `state-decisions.sh`, fora deste arquivo).

**Rationale**: FR-012/US3 herdam a invariante de seguranca operacional da spec
arquivada (FR-018/FR-019). Reusar o mecanismo existente (em vez de inventar
outro) garante consistencia e que os testes de degradacao ja existentes cubram
o novo modo com adaptacao minima.

**Alternatives considered**:
- **Falhar com exit != 0 em db corrompido**: rejeitado — quebraria FR-012/SC-003
  (no-op em 100% das falhas, nunca gateia a onda).
- **Timeout proprio (subshell + kill)**: rejeitado — o `busy_timeout` do sqlite3
  ja cobre contencao de lock; um timeout de wallclock adicional e overkill para
  uma leitura unica e read-only (a query e LIMIT N pequeno).

---

## Decision 7 — Pontos de integracao nos orquestradores

**Decision**: Injetar o passo PRE-DECISAO em DOIS pontos exatos de CADA
orquestrador (`agente-00c-feature-orchestrator.md` e `agente-00c-orchestrator.md`):
- **Inicio da fase `specify`** (antes de invocar a skill specify).
- **Inicio da fase `plan`** (antes de invocar a skill plan).

NAO injetar em clarify, execute-task, gates ou review (FR-010). O passo:
1. Deriva termos via jq (Decision 2).
2. Invoca `cstk recall --context "<termos>" --limit 4
   --exclude-feature <short_name> --max-bytes 2000`.
3. Se stdout nao-vazio (K>0): injeta o bloco no contexto + registra Decisao
   auditavel (Decision 8). Se vazio (K=0): no-op, registro reflete consumo=0 sem
   ruido (FR-017).

**Rationale**: FR-008/FR-010/FR-011. specify e plan sao as fases de decisao de
design — onde reaproveitar decisoes/bloqueios passados evita repetir erros.
Custo previsivel: <=2 leituras por feature (SC-006). A feature-00c-orchestrator
ja tem o `state.json` da feature corrente (com `aspectos_chave_iniciais` e
`short_name`); o agente-00c-orchestrator tem o equivalente.

**Alternatives considered**:
- **Injetar em todas as fases**: rejeitado por FR-010 (clarify/execute-task/
  gate/review nao decidem design; recall vira ruido + custo).
- **Injetar so em plan**: rejeitado — specify tambem toma decisoes de design
  (escopo, abordagem) e se beneficia do read-back.
- **Hook automatico (como a ingestao pos-onda)**: rejeitado — o consumo precisa
  dos termos derivados do state, que sao melhor montados inline no loop do
  orquestrador; um hook generico nao tem acesso facil aos aspectos-chave.

---

## Decision 8 — Auditabilidade: Decisao "consumo de conhecimento" no state.json

**Decision**: Quando o passo PRE-DECISAO injeta K>=1 achados, o orquestrador
registra uma Decisao via `state-decisions.sh register` contendo no minimo:
- termos derivados (no `--justificativa` ou `--evidencia`);
- contagem K de achados injetados (no `--contexto`);
- fase consumidora (`--etapa specify` ou `--etapa plan`).

Quando K=0 (no-op), NAO registra ruido — opcionalmente uma marcacao leve na onda
(`skills_invoked` ou ausencia explicita), mas sem Decisao dedicada (FR-017
distingue consumo efetivo de no-op).

**Rationale**: FR-016/FR-017 + Principio I (auditabilidade). `review-task` mede
a eficacia do read-back loop varrendo `.decisoes[]` por contexto "consumo de
conhecimento" / "read-back". A propria fase plan desta feature ja exercitou isso
(dec-009 registrou K=4). O registro vive no `state.json` transacional do runtime
(gerenciado pelo orquestrador), NAO no modo `--context` (que e read-only,
Decision 6).

**Alternatives considered**:
- **Registrar tambem K=0**: rejeitado por FR-017 (gera ruido quando nao ha o que
  injetar).
- **Persistir um ConsumptionRecord proprio (arquivo novo)**: rejeitado —
  reusar a entidade Decisao (ja auditada, ja consumida por review-task) evita um
  novo formato/parser.

---

## Decision 9 — Deps opcionais sob carve-out da constituicao 1.1.0

**Decision**: `sqlite3` e `jq` entram pela carve-out de deps opcionais
(Principio II, amendment 1.1.0). Conformidade com as 3 condicoes cumulativas:
- **(a) Fallback graceful testado**: ausencia de `sqlite3`/`jq` => no-op
  silencioso (Decision 6), coberto por teste automatizado (FR-013, cenarios
  novos em `tests/cstk/test_recall.sh`).
- **(b) Confinado em 1 arquivo**: TODA referencia a `sqlite3`/`jq` vive em
  `cli/lib/recall.sh` (ja o caso para os modos existentes; o modo `--context`
  nao adiciona referencias fora desse arquivo). O passo PRE-DECISAO nos
  orquestradores usa `jq` para derivar termos, mas isso e markdown de
  instrucao (nao codigo shell shipado) — a dep shell confinada permanece em
  recall.sh.
- **(c) Declarada na doc da feature**: este research.md + plan.md declaram a
  dep, o caminho confinado e o fallback.

**Rationale**: FR-018 herda FR-020 da spec arquivada. As duas deps ja sao usadas
pelos modos busca/ingest/reindex existentes em recall.sh — o modo `--context`
nao introduz dep nova, apenas reusa as ja declaradas.

**Alternatives considered**:
- **Implementar FTS em sh puro (sem sqlite3)**: rejeitado — full-text search +
  bm25 ranking em sh puro e inviavel; a carve-out existe exatamente para esse
  caso.

---

## Decision 10 — Estrategia de teste: HOME falso + CSTK_LIB (licao v3.17.0)

**Decision**: TODOS os cenarios novos do modo `--context` em
`tests/cstk/test_recall.sh` rodam em DOIS ambientes:
1. **HOME real** (ambiente local de desenvolvimento).
2. **HOME falso** (CI-like fresh-checkout, sem `~/.claude`), resolvendo helpers
   via `CSTK_LIB` apontando para `cli/lib`.

Fixtures de bytes crus usam escapes **octais `\NNN`** (nunca hex `\xHH` — dash/CI
nao interpreta hex). Para o modo `--context`, o teste usa um DB de fixture
populado e exporta `CSTK_KNOWLEDGE_DB` (ou passa `--db`) para isolar do indice
real.

**Rationale**: FR-020 + licao v3.17.0 documentada em MEMORY. A causa #1 de
"fix funciona no repo mas nao na sessao/CI": helper resolvido so via `~/.claude`
passa local (onde o runtime esta instalado) e falha no CI fresh-checkout. O modo
`--context` em si nao usa secrets-filter (leitura nao re-scrub, FR-015), mas a
disciplina de HOME falso garante que a resolucao de db e o caminho de leitura
nao dependem de `~/.claude`. SC-005 exige comprovacao explicita: HOME falso ==
HOME real.

**Alternatives considered**:
- **So testar com HOME real**: rejeitado — false-pass local, quebra CI
  (a licao v3.17.0 inteira).
- **Hex `\xHH` nos fixtures**: rejeitado — dash/CI nao interpreta (lic. octal
  em MEMORY).

---

## Unknowns resolvidos

| Unknown (deferido ao /plan) | Resolucao |
|-----------------------------|-----------|
| FR-007: piso bm25? | NAO (Decision 1) — so teto N + bm25 ASC; FR-007 PROIBE piso absoluto |
| FR-009: composicao OR vs AND | OR explicito (Decision 1) — evidencia empirica 0 vs 43 matches |
| Default de --limit | 4 (Decision 4) — dentro de 3-5 |
| Default de --max-bytes | 2000 (Decision 4) |
| Formato de saida | markdown 1-linha-por-achado + cabecalho blockquote (Decision 3) |
| Onde injetar nos orquestradores | inicio de specify + plan, ambos os orquestradores (Decision 7) |

**NEEDS CLARIFICATION restantes**: 0
