# cstk-panel — Brief de Back-End (API read-only sobre knowledge.db)

> **Objetivo deste documento**: especificar o **serviço de back-end** que lê o
> `knowledge.db` e serve os dados ao protótipo de front-end descrito em
> [`frontend-brief.md`](./frontend-brief.md). É um brief de **contrato de API +
> arquitetura**, não de implementação linha-a-linha. Toda métrica e endpoint
> aqui é **aterrado no schema v2 real** do banco. O front-end é a referência das
> telas; este documento define **de onde cada número vem e como ele é servido**.

---

## 1. O que é o back-end do cstk-panel

Um **servidor de API HTTP estritamente read-only** que abre o índice
`~/.claude/cstk/knowledge.db` (SQLite + FTS5, schema **v2**) e expõe endpoints
JSON consumidos pelo dashboard. Sua única responsabilidade é **ler, agregar e
servir** — nunca escrever, migrar ou mutar o banco.

- **Consumidor**: o front-end `cstk-panel` (SPA, ver frontend-brief).
- **Natureza**: **read-only absoluto**. Sem CRUD, sem POST/PUT/DELETE de dados.
  Os únicos verbos são `GET` (consulta) e, no máximo, `GET` com query-params para
  busca/filtro. O servidor abre o SQLite em modo somente-leitura (ver §4).
- **Posição na arquitetura**: o back-end é **mais um consumidor derivado** da
  knowledge.db, exatamente como o `cstk recall`. **A fonte da verdade é o
  `state.json` transacional** de cada execução; a knowledge.db é um índice
  derivado e reconstruível (`cstk recall --reindex`). O back-end **nunca** toca
  o `state.json` nem reconstrói o índice — só lê o que já está lá.

```
state.json (fonte da verdade, transacional, por feature)
   │  ingestão best-effort (hook fim-de-onda) / cstk recall --reindex
   ▼
knowledge.db (índice derivado, SQLite+FTS5, ~/.claude/cstk/)
   │  ABRE EM MODO RO  ◄── este back-end vive aqui (read-only)
   ▼
API HTTP/JSON ──► cstk-panel (SPA)
```

---

## 2. Princípios inegociáveis

Estes princípios herdam diretamente da natureza da knowledge.db e **moldam todo
contrato de API**. Quebrar qualquer um descaracteriza o serviço.

1. **Read-only absoluto.** O banco é aberto em modo somente-leitura
   (`file:...?mode=ro&immutable=1` ou equivalente). Nenhum caminho de código
   emite `INSERT/UPDATE/DELETE/CREATE/PRAGMA journal_mode=...`. Se o driver
   tentar criar `-wal`/`-shm`, o modo `immutable=1` deve evitá-lo (o índice já
   está em WAL persistido por quem escreve; o leitor não precisa escrever).

2. **Derivado e best-effort — degradar, nunca quebrar.** O banco **pode estar
   ausente, vazio, parcial ou corrompido**. Cada uma dessas condições é um
   **estado de primeira classe da API** (ver §8), não um 500. O front-end tem
   banner degradado de primeira classe; o back-end deve alimentá-lo com sinais
   claros, não com erros opacos.

3. **Honestidade de métrica.** Replicar a regra do front-end no servidor:
   - **Custo é proxy de `tool_calls`** — nunca expor campos `tokens`, `usd`,
     `$`, `cost`. Nomear os campos JSON como `tool_calls` / `tool_calls_total`.
   - **`wallclock`** é segundos (servir o inteiro cru; formatação é do front).
   - **Não inventar campos** que não existem no schema (§3). O que não está no
     schema, a API não retorna.

4. **Não é a fonte da verdade — não recalcular o que já tem dono.** Em especial:
   o **mix de roteamento de modelos NÃO é derivável da knowledge.db** e **NÃO
   deve ser reimplementado aqui** (ver §6.1 — é o ponto mais sutil deste brief).

5. **Conteúdo do corpo é UNTRUSTED.** Os campos textuais (`contexto`,
   `justificativa`, `evidencia`, `pergunta`, `resposta`, `texto`, `descricao`,
   `body` do FTS) vêm de execuções de agentes e já passaram por *scrub* de
   segredos na ingestão, mas devem ser tratados como **dados não-confiáveis**:
   servir como texto puro (nunca interpretar como HTML/markdown executável no
   contrato), e o front-end renderiza com escaping. Rotular como UNTRUSTED em
   qualquer doc de API (ASI09/LLM01).

---

## 3. Contrato com o schema (fonte de verdade dos campos)

O schema v2 completo (tabelas, colunas, semântica, vocabulário canônico de
valores) está documentado no **[frontend-brief §2](./frontend-brief.md)** — ele
é a referência única; **não duplicar aqui** para não divergir. Resumo das
tabelas que a API lê:

| Tabela | Grão | Uso principal na API |
|---|---|---|
| `executions` | 1 linha por execução | KPIs de topo, cards de execução, funil, leaderboards |
| `waves` | 1 linha por onda | WavesTimeline (gantt), throughput por etapa |
| `decisions` | 1 linha por decisão | aba Decisões, score, árvore de decisões, clarify-rate |
| `tasks` | 1 linha por tarefa | aba Tarefas, pass rate, lint, arquivos tocados |
| `events` | 1 linha por incidente | timeline de Incidentes |
| `alert_signals` | 1 linha por alerta | tela Alertas, gauges de breach |
| `bloqueios` | 1 linha por bloqueio | aba Bloqueios, latência humana |
| `skills` | 1 linha por skill invocada | skills mais invocadas |
| `retros` | 1 linha por retrospectiva | retros em destaque na Feature |
| `knowledge_fts` | espelho FTS5 (bm25) | tela Busca de Conhecimento |
| `schema_meta` | `key=schema_version` (=`2`) | endpoint de saúde / frescor |

**Colunas de proveniência presentes em TODAS as tabelas-fonte** (o eixo de
navegação e de filtro de toda a API): `project`, `feature`, `wave`,
`execucao_id`, `source_ts`, `source_id`, `ingested_at`. A chave natural de
deduplicação é `UNIQUE(project, feature, wave, source_id)`.

> ⚠️ **Realidade dos dados é esparsa.** Na base real de referência (8 projetos):
> `decisions`≈856, `waves`≈231, `skills`≈127, `alert_signals`≈20 (todos
> `tipo='circular'`, zero `budget_breach`), `executions`≈11, mas `tasks`=1,
> `events`=1, `retros`=0. **Tabelas inteiras podem vir vazias.** A API e o
> front-end devem tratar contagem zero como estado normal (vazio), não erro. Não
> assumir que `budget_breach` ou `retros` existem só porque o schema os prevê.

---

## 4. Arquitetura do serviço

### 4.1 Abertura do banco (read-only)

- Resolver o caminho do DB na mesma ordem do `cstk recall`:
  **flag/config explícita > `$CSTK_KNOWLEDGE_DB` > `~/.claude/cstk/knowledge.db`**.
- Abrir com DSN read-only + immutable, ex.:
  `file:/abs/path/knowledge.db?mode=ro&immutable=1&_busy_timeout=5000`.
- **`PRAGMA quick_check`** na inicialização e/ou no health endpoint para
  detectar corrupção (espelha o guard do recall: resultado != `ok` ⇒ degradado).
- **Não** segurar a conexão indefinidamente assumindo imutabilidade total: o
  índice é reescrito por trás (ingestão best-effort no fim de cada onda). Tratar
  o arquivo como **snapshot que muda**: reabrir/reconsultar por requisição (ou
  pool curto), e expor frescor via `mtime` do arquivo + `schema_meta`.

### 4.2 Frescor (data freshness)

O front-end tem `DataFreshnessIndicator` ("índice atualizado há Xm"). O back-end
serve a verdade desse selo:

- `mtime` do arquivo `knowledge.db` (proxy de "última ingestão").
- `max(ingested_at)` cross-tabela (mais preciso que mtime para conteúdo).
- `schema_meta.schema_version` (deve ser `2`; divergência ⇒ avisar).

### 4.3 Stack — decisão em aberto (não travada por este brief)

O serviço é, em essência, **um leitor SQLite + agregador SQL + servidor JSON**.
Qualquer stack que abra SQLite em modo RO serve. O **contrato de API (§5) é
agnóstico de linguagem**. Candidatos naturais, em ordem de menor atrito:

- **Go** (coerente com o ecossistema CashBeer/microsserviços; `mattn/go-sqlite3`
  ou `modernc.org/sqlite` puro-Go; binário único, fácil de empacotar junto ao
  `cstk`).
- **Node/TS** (coerente com o front-end React/TS; `better-sqlite3` síncrono e
  rápido para read-only).
- **Python** (`sqlite3` stdlib + FastAPI; FTS5 nativo).

> **Recomendação default**: **Go**, por alinhamento com o resto do ecossistema e
> empacotamento como subcomando/binário do `cstk` (ex. `cstk panel serve`). Mas
> isto é uma decisão de implementação — confirmar com o operador antes de
> codar. O brief não depende dela.

---

## 5. Superfície de API (endpoints por tela)

REST/JSON. Todos os endpoints são `GET`. Todos aceitam os **filtros globais**
como query-params (quando fizer sentido): `project`, `feature`, `status`,
`period` (`24h|7d|30d|all`), `q` (busca). Paginação por `limit`+`offset` ou
cursor. Respostas envelopadas com metadados de frescor/degradação (§8).

Convenção: o prefixo é `/api/v1`. As shapes abaixo listam os **campos do schema**
que cada endpoint projeta (sem inventar nada).

### 5.1 Saúde e metadados

```
GET /api/v1/health
  → { ok: bool, db_present: bool, db_readable: bool, schema_version: "2",
      degraded: bool, reason?: string, freshness: { mtime, max_ingested_at },
      counts: { executions, waves, decisions, tasks, events,
                alert_signals, bloqueios, skills, retros } }
```

Endpoint que alimenta o `DataFreshnessIndicator`, o banner degradado e a tela
opcional "Sobre / Fonte de Dados" (frontend §5.11). **Nunca retorna erro HTTP por
banco ausente** — retorna `200` com `db_present:false, degraded:true`.

### 5.2 Visão Geral (Overview / Portfolio) — frontend §5.1

```
GET /api/v1/overview?period=
  → {
      kpis: {
        projetos_ativos,            // count(distinct project)
        features_total,             // count(distinct feature)
        execucoes_por_status: {em_andamento, concluida, abortada, aguardando_humano},
        alertas_criticos_abertos,   // count(alert_signals)
        tool_calls_total,           // Σ executions.tool_calls_total  (rótulo: proxy)
        wallclock_total_segundos    // Σ executions.wallclock_total_segundos
      },
      alertas_recentes: [ {tipo, subtipo, project, feature, wave, valor_consumido, valor_threshold, source_ts} ],
      execucoes_em_andamento: [ {execucao_id, project, feature, etapa_corrente, tool_calls_total, ondas_total} ],
      atividade_recente: [ {kind, project, feature, source_ts, ...} ],   // feed cronológico derivado
      leaderboard_custo: [ {feature, project, tool_calls_total} ],       // top-N por tool_calls
      funil_pipeline: [ {etapa, count} ]                                 // features por etapa_corrente
      // mix_modelos: ver §6.1 — NÃO sai daqui
    }
```

### 5.3 Projetos — frontend §5.2

```
GET /api/v1/projects
  → [ { project, n_features, execucoes_por_status, tool_calls_total,
        alertas_abertos, ultima_atividade } ]      // rollup por project
GET /api/v1/projects/{project}
  → { project, features: [...], metricas_agregadas: {...} }
```

### 5.4 Features — frontend §5.3

```
GET /api/v1/features?project=&status=
  → [ { feature, project, status, etapa_corrente, ondas_total,
        tool_calls_total, duracao_segundos, decisoes_total,
        bloqueios_humanos_total, alertas_abertos } ]
GET /api/v1/features/{project}/{feature}
  → { ...campos da feature..., stack_sugerida,
      execucoes: [ {execucao_id, status, ...} ],
      retros: [ {wave, texto, source_ts} ],
      metricas_agregadas: {...} }
```

### 5.5 Detalhe da Execução — frontend §5.4 (a mais rica)

```
GET /api/v1/executions/{execucao_id}
  → { ...todos os campos de executions...,
      // status, motivo_termino, etapa_corrente, iniciada_em, terminada_em,
      // duracao_segundos, ondas_total, tool_calls_total, wallclock_total_segundos,
      // subagentes_spawned, profundidade_max, decisoes_total,
      // bloqueios_humanos_total, sugestoes_skills_total, issues_toolkit_abertas
    }

GET /api/v1/executions/{execucao_id}/waves
  → [ { wave, etapas, inicio, fim, wallclock_seconds, tool_calls,
        motivo_termino, n_etapas, n_skills } ]      // alimenta WavesTimeline/gantt

GET /api/v1/executions/{execucao_id}/decisions?wave=&etapa=&score=
  → [ { wave, etapa, agente, escolha, score, contexto, justificativa,
        evidencia, source_ts, source_id } ]         // UNTRUSTED nos campos textuais

GET /api/v1/executions/{execucao_id}/tasks
  → { kpi: { pass_rate, total, pass, fail },
      itens: [ { wave, outcome, testes_rodados, testes_passados,
                 lint_ok, arquivos_tocados } ] }

GET /api/v1/executions/{execucao_id}/events
  → [ { event_type, timestamp, descricao, wave } ]

GET /api/v1/executions/{execucao_id}/alerts
  → [ { tipo, subtipo, valor_consumido, valor_threshold, descricao, wave } ]

GET /api/v1/executions/{execucao_id}/bloqueios
  → [ { status, pergunta, contexto_para_resposta, resposta, decisao_id,
        disparado_em, respondido_em, latencia_segundos } ]   // UNTRUSTED textual

GET /api/v1/executions/{execucao_id}/skills
  → [ { skill_name, decisao_id, wave } ]
```

> A "árvore de decisões" (botão na tela de execução) é gerada pela skill
> `decision-tree` a partir do `state.json`, **não** da knowledge.db. O back-end
> pode no máximo **linkar/sinalizar disponibilidade**, não reproduzi-la.

### 5.6 Alertas — frontend §5.5

```
GET /api/v1/alerts?tipo=&project=&feature=&period=
  → { resumo: { por_tipo: {circular, budget_breach} },
      itens: [ { tipo, subtipo, valor_consumido, valor_threshold,
                 descricao, project, feature, wave, execucao_id, source_ts } ] }
```

> Realidade: hoje a base só tem `tipo='circular'`. `budget_breach` é previsto
> pelo schema mas pode ter contagem 0 — servir array vazio, não 404.

### 5.7 Métricas agregadas — frontend §5.6

```
GET /api/v1/metrics/cost-over-time?project=&period=     → série tool_calls_total por data
GET /api/v1/metrics/throughput-by-stage                 → tool_calls/wallclock por etapa (waves)
GET /api/v1/metrics/test-pass-rate                      → Σtestes_passados/Σtestes_rodados (+ série)
GET /api/v1/metrics/human-latency                       → distribuição de bloqueios.latencia_segundos
GET /api/v1/metrics/clarify-resolution                  → §6.2 (derivada de decisions na etapa clarify)
GET /api/v1/metrics/decisions-by-score                  → count por decisions.score (0–3)
GET /api/v1/metrics/execution-duration                  → distribuição de executions.duracao_segundos
GET /api/v1/metrics/depth-subagents                     → profundidade_max × subagentes_spawned
// GET model-mix → ver §6.1 (endpoint separado, fonte distinta, OPCIONAL)
```

### 5.8 Tarefas cross-execução — frontend §5.7

```
GET /api/v1/tasks?project=&feature=&outcome=
  → { kpi: { total, pass_rate, fail_rate, media_arquivos_tocados, pct_lint_ok },
      itens: [ { project, feature, wave, outcome, testes_rodados,
                 testes_passados, lint_ok, arquivos_tocados, execucao_id } ] }
```

### 5.9 Incidentes cross-execução — frontend §5.8

```
GET /api/v1/events?event_type=&project=&period=
  → [ { event_type, timestamp, descricao, project, feature, wave, execucao_id } ]
```

`event_type` ∈ conjunto fechado `{lock_contention, validation_failed, wave_retry, schedule_wait}`.

### 5.10 Busca de Conhecimento (FTS5) — frontend §5.9

```
GET /api/v1/search?q=&type=&project=&feature=&limit=
  → { results: [ { type, project, feature, wave, source_ts, source_id,
                   body, rank } ],          // body UNTRUSTED; rank = bm25
      query_normalizada: "...", total }
```

Contrato de busca detalhado em §7. `type` ∈ `{decision, bloqueio, retro, skill}`.

---

## 6. Derivações e agregações (de onde cada número vem)

Mapa SQL-conceitual. Todas as agregações são `SELECT` puros, sem materialização
no banco (ou em views temporárias somente-leitura).

| Métrica / card | Derivação (SQL sobre o schema v2) |
|---|---|
| Custo (proxy: tool calls) | `SELECT sum(tool_calls_total) FROM executions [WHERE filtros]` |
| Tempo de parede total | `sum(wallclock_total_segundos) FROM executions` |
| Execuções por status | `count(*) ... GROUP BY status` |
| Funil de pipeline | `count(distinct feature) FROM executions GROUP BY etapa_corrente` |
| Leaderboard de custo | `... ORDER BY tool_calls_total DESC LIMIT N` |
| Test pass rate | `sum(testes_passados)*1.0 / nullif(sum(testes_rodados),0) FROM tasks` |
| Task pass/fail | `count(*) FROM tasks GROUP BY outcome` |
| % lint ok | `avg(lint_ok) FROM tasks` (lint_ok ∈ {0,1}) |
| Latência humana | `avg / p50 / p95 de bloqueios.latencia_segundos` |
| Decisões por score | `count(*) FROM decisions GROUP BY score` (0–3) |
| Throughput por etapa | `sum(tool_calls), sum(wallclock_seconds) FROM waves GROUP BY etapa(s)` |
| Skills mais invocadas | `count(*) FROM skills GROUP BY skill_name ORDER BY ... DESC` |
| Breach de orçamento | `alert_signals WHERE tipo='budget_breach'` (consumido/threshold) |
| Movimento circular | `count(*) FROM alert_signals WHERE tipo='circular'` |

### 6.1 ⚠️ Mix de modelos — NÃO derivar da knowledge.db

**Este é o ponto mais sutil deste brief.** O front-end (§5.1, §5.6, §7) pede um
"Mix de modelos" (haiku/sonnet/opus/manter-atual + taxa de fallback). **Esse
agregado NÃO está na knowledge.db e NÃO pode ser reconstruído a partir dela**:

- `decisions.escolha` **não** carrega o token `model:<...>` no índice (verificado
  na base real: zero linhas `escolha LIKE 'model:%'`). A ingestão não materializa
  o mix.
- Por decisão de arquitetura (FR-017, contract §6 da feature
  `knowledge-db-metrics`), a **fonte única e canônica** do mix é o agregador já
  existente do runtime: **`model-routing-report.sh aggregate --json`**, que lê de
  um **state-dir** (`.claude/agente-00c-state/...` / `feature-00c-state/...`),
  **não** do `knowledge.db`. Reimplementar a agregação aqui violaria FR-017 e o
  invariante SC-006 ("0 divergências com a ferramenta existente").

**Implicações para o back-end:**

- **Opção A (recomendada para um leitor puro de knowledge.db):** o endpoint de
  mix de modelos fica **fora de escopo** da API que lê só o DB. O card no
  front-end exibe estado "métrica indisponível nesta fonte" — honesto e correto.
- **Opção B (se o back-end tiver acesso de leitura aos state-dirs):** expor
  `GET /api/v1/metrics/model-mix?state_dir=...` que **invoca/delegada** ao
  `model-routing-report.sh aggregate --json` e repassa o JSON **sem
  reimplementar a lógica**. Isso amplia a superfície (acesso a state-dirs, exec de
  subprocesso) e deve ser decidido explicitamente com o operador.

Não escolher silenciosamente: **registrar a decisão A vs B** antes de implementar.

### 6.2 Clarify auto-resolution rate

Derivada (não há campo direto): proporção de itens da etapa `clarify` resolvidos
autonomamente. Aproximação coerente com a heurística de score (0–3):

```
decisões na etapa 'clarify' com score >= 2  (auto-resolvidas por contexto/evidência)
  vs
bloqueios escalados a humano  (bloqueios cuja decisão veio da etapa clarify, ou status escalado)
```

Servir numerador, denominador e a razão — **rotular como derivada/aproximada** no
contrato, já que não há um campo canônico de "clarify resolvido".

---

## 7. Busca FTS5 — contrato (espelhar o recall, não reinventar)

A tela de Busca consulta a virtual table `knowledge_fts` (colunas: `body`
indexada; `type, project, feature, wave, source_id, source_ts` UNINDEXED).
**Ranqueamento por `bm25(knowledge_fts)` ASC** (mais relevante primeiro).

**Escaping obrigatório de duas camadas** (idêntico ao `cstk recall`, sob risco de
injeção de sintaxe FTS5/SQL — ver `cli/lib/recall.sh`):

1. **Camada FTS5 (por token):** tokenizar `q` por whitespace; cada token vira uma
   **frase entre aspas** com `"` interno duplicado. Isso neutraliza a sintaxe
   FTS5 (`* ( ) : ^ -` e operadores booleanos viram texto literal). Junção:
   - **AND implícito** (espaço entre frases) para a **busca da tela** — multi-termo
     útil, ambos precisam aparecer (espelha `fts_query_escape`).
   - **OR** entre frases **só** se algum dia houver um modo "read-back"/recall na
     API (espelha `fts_query_escape_or`; não é o caso da tela de busca).
2. **Camada SQL:** o resultado da camada 1 ainda passa por escaping SQL antes de
   ir ao `MATCH '...'`. **Preferir binding parametrizado** (`?`) para o valor do
   `MATCH` e para os filtros `project`/`type` — elimina a 2ª camada manual.

**Guards a replicar:**
- Query só-whitespace (degenerada) ⇒ frase vazia ⇒ **0 resultados, sem erro**.
- `limit` deve ser **inteiro positivo** (`^[1-9][0-9]*$`); rejeitar com `400`
  (ou clampar a um default). Nunca interpolar `limit` não-validado.
- Banco ausente/corrompido (`PRAGMA quick_check != 'ok'`) ⇒ resposta degradada
  (§8), não 500.

Filtros aplicáveis no `WHERE` junto ao `MATCH`: `type`, `project` (e por extensão
`feature`/`wave`, todas UNINDEXED mas filtráveis).

---

## 8. Estados, erros e envelope de resposta

O back-end **traduz a natureza best-effort do índice em semântica HTTP clara**.
A regra de ouro espelha o `recall`: **toda degradação do índice é resposta `200`
com sinal de degradação, não erro de servidor.**

| Condição | HTTP | Corpo |
|---|---|---|
| Banco ausente | `200` | `{ degraded:true, reason:"db_absent", data: <vazio> }` |
| Banco vazio (0 linhas) | `200` | dados vazios + `degraded:false` (vazio é normal) |
| Banco corrompido (`quick_check != ok`) | `200` | `{ degraded:true, reason:"db_corrupt" }` |
| `schema_version != 2` | `200` | `{ degraded:true, reason:"schema_mismatch", schema_version }` |
| Recurso não encontrado (`execucao_id` inexistente) | `404` | `{ error:"not_found" }` |
| Query-param inválido (`limit`, `period`, `type`) | `400` | `{ error:"bad_request", detail }` |
| Erro interno real (bug, não estado de dado) | `500` | `{ error:"internal" }` |

**Envelope sugerido** (todas as respostas de dados):

```json
{
  "data": ...,
  "meta": {
    "degraded": false,
    "reason": null,
    "freshness": { "mtime": "...", "max_ingested_at": "..." },
    "schema_version": "2"
  }
}
```

Isso alimenta diretamente os estados do front-end: **carregando** (latência da
chamada), **vazio** (`data` vazio, `degraded:false`), **erro** (`4xx/5xx`),
**degradado** (`meta.degraded:true` → banner não-bloqueante).

---

## 9. Segurança

Mesmo sendo read-only e (provavelmente) local, aplicar:

1. **Read-only reforçado no driver** (mode=ro/immutable) — defesa em
   profundidade contra qualquer caminho de escrita acidental.
2. **Sem SQL injection:** todos os filtros via **prepared statements/binding**.
   O FTS `MATCH` recebe a string já escapada por token (§7) e parametrizada.
3. **Conteúdo UNTRUSTED:** campos textuais servidos como `text/plain` no JSON,
   sem interpretação. Cabeçalho `Content-Type: application/json`,
   `X-Content-Type-Options: nosniff`. O front-end escapa na renderização.
   (LLM01/ASI09: o corpo veio de saída de agente; já *scrubbed* na ingestão, mas
   não confiar.)
4. **Path traversal:** a resolução do caminho do DB (e de qualquer `state_dir` na
   Opção B do §6.1) deve ser **canonicalizada e confinada** — nunca aceitar path
   arbitrário do cliente. Default fixo + allowlist via config do servidor.
5. **CORS:** restrito à origem do front-end (não `*` em produção).
6. **Sem autenticação real no protótipo** (coerente com o front-end), mas o
   serviço deve **bind em `localhost` por padrão** e não expor a rede sem
   decisão explícita. Rate-limit leve na busca (FTS pode ser custoso).
7. **Subprocesso (só Opção B):** se invocar `model-routing-report.sh`, executar
   com argumentos validados, sem shell-string interpolada, timeout e captura de
   stderr (degradar a indisponível em qualquer falha).

---

## 10. Performance e caching

- **Read-only ⇒ cache agressivo é seguro**, invalidado por frescor. Chavear cache
  por `mtime`+`max(ingested_at)`; servir `ETag`/`Last-Modified`; aceitar
  `If-None-Match` ⇒ `304`.
- Agregações de Overview/Métricas: memoizar por janela curta (ex. 15–60s) — o
  índice só muda no fim de uma onda, raramente.
- Índices SQLite: o schema já cobre as buscas via `UNIQUE(project, feature, wave,
  source_id)` e o FTS5 próprio. Para agregações pesadas por `project`/`status`,
  o leitor pode criar **índices em memória/temp read-only** se necessário —
  **nunca** alterar o arquivo do banco.
- Paginação obrigatória em `decisions` (≈856 linhas) e `search`.

---

## 11. Não-objetivos (fora do escopo do back-end)

- **Nenhuma escrita** no `knowledge.db` (sem ingestão, sem `--reindex`, sem
  migração — isso é do `cstk recall`/hook, não da API).
- **Não tocar `state.json`** nem qualquer estado transacional (fonte da verdade).
- **Não reimplementar o mix de modelos** (§6.1) — delegar ou omitir.
- **Não reimplementar a árvore de decisões** (é da skill `decision-tree` sobre
  `state.json`).
- **Não expor tokens/$ de custo** — não existem; usar `tool_calls`.
- **Sem auth/RBAC real, sem mutação, sem config de orquestrador.** O painel (e seu
  back-end) só **observam**.

---

## 12. Decisões em aberto (confirmar com o operador antes de codar)

1. **Stack** (§4.3): Go (recomendado) vs Node/TS vs Python.
2. **Empacotamento**: subcomando do `cstk` (ex. `cstk panel serve`) vs serviço
   standalone separado.
3. **Mix de modelos** (§6.1): **Opção A** (omitir — leitor puro de knowledge.db)
   vs **Opção B** (delegar a `model-routing-report.sh` com acesso a state-dirs).
4. **Formato**: REST/JSON (assumido neste brief) vs GraphQL.
5. **Escopo de "atividade recente" e séries temporais**: o schema tem `source_ts`
   / `iniciada_em` / `terminada_em` / `timestamp`, mas a granularidade de série
   (por dia? por execução?) depende do volume — validar com dados reais.

---

*Brief derivado do schema v2 real do `knowledge.db` (`cli/lib/recall.sh`,
`RECALL_SCHEMA_VERSION=2`) e do contrato de proveniência do ecossistema cstk.
Pareia com [`frontend-brief.md`](./frontend-brief.md) — este repositório
(`claude-ai-tips`) é a fonte da verdade dos dados; o back-end do `cstk-panel` é
um consumidor read-only, exatamente como o `cstk recall`.*
