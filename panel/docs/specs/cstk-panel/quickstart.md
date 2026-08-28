# Quickstart & Cenários de Teste: cstk-panel

**Feature**: `cstk-panel`
**Objetivo**: validar os fluxos críticos (happy path + erro + degradação +
roundtrip real) sobre a `knowledge.db` schema v2.

> Pré-requisito: monorepo instalado (`npm install` na raiz), `apps/server` e
> `apps/web` buildáveis. Base de referência:
> `~/.claude/cstk/knowledge.db` (schema v2, real).

---

## Setup

### Desenvolvimento (hot-reload)

```bash
# 1. Instalar dependencias
npm install

# 2. Iniciar server + web em paralelo (ambos com hot-reload)
npm run dev
# server: http://127.0.0.1:3001
# web:    http://localhost:5173
```

Para apontar para uma base alternativa:
```bash
CSTK_KNOWLEDGE_DB=~/.claude/cstk/knowledge.db npm run dev
```

### Producao (build + start)

```bash
# Build em ordem correta de dependencias: shared-types -> server -> web
npm run build

# Iniciar o servidor de API
npm start
# Equivalent a: node apps/server/dist/index.js

# Servir o front-end buildado (qualquer static server)
npx serve apps/web/dist -p 4000
```

Variaveis de ambiente disponiveis: `CSTK_KNOWLEDGE_DB`, `PORT` (padrao 3001), `CORS_ORIGIN`, `LOG_LEVEL`.

---

## Cenário 1 — Roundtrip End-to-End (chamada REAL, não mock) — OBRIGATÓRIO

> Razão (dec-172/dec-173, 40 ondas históricas): testes que parseiam mocks
> mascararam drift snake_case↔camelCase. Só o payload **real** do backend expõe
> isso. Este cenário é teste de integração (Vitest) **e** verificação manual.

1. Com o back-end no ar sobre a base real, fazer `GET /api/v1/overview?period=7d`.
2. Capturar o payload **real** da resposta (não fixture).
3. **Expected**:
   - Status `200`.
   - Corpo casa o envelope: `{ data, meta: { degraded, reason, freshness:
     { mtime, maxIngestedAt }, schemaVersion } }`.
   - `meta.schemaVersion === "2"`.
   - `meta.degraded === false` (base real populada).
   - As chaves de `data` estão em **camelCase** (`toolCallsTotal`, não
     `tool_calls_total`) — `safeParse` do schema Zod de `shared-types` passa.
4. Fazer `GET /api/v1/search?q=plan&limit=5`.
5. **Expected**:
   - Status `200`; `data.results` é array com até 5 itens; cada item tem
     `body`/`type`/`sourceId`/`rank` em camelCase; `meta.pagination` presente.
   - Nenhum campo de proveniência crua vazado fora do contrato.
6. Reexecutar a mesma `GET /api/v1/overview` com `If-None-Match: <ETag da 1ª>`.
7. **Expected**: `304 Not Modified`, corpo vazio (cache válido — Princípio VI).

> **Critério de drift**: o shape parseado do payload real DEVE bater 1:1 com o
> schema Zod de `shared-types`. Divergência de case/tipo = falha de roundtrip
> (não "corrigir o teste para passar").

---

## Cenário 2 — Drill-down até o nível granular (US1, SC-004)

1. Abrir Visão Geral.
2. Clicar num projeto → feature → execução → onda → decisão.
3. **Expected**: cada clique navega mantendo breadcrumb; o nível mais granular
   (decisão/tarefa/evento/alerta) é alcançado em **≤ 4 cliques** de drill-down;
   o detalhe da decisão mostra `contexto`/`justificativa`/`evidencia`.

---

## Cenário 3 — Honestidade de métrica (US1/US5, SC-002)

1. Abrir Visão Geral e tela de Métricas (`cost-over-time`).
2. Inspecionar todo rótulo de custo.
3. **Expected**: custo aparece como `tool_calls` rotulado **"proxy: tool
   calls"**; **zero** ocorrências de `$`, `USD` ou `token`. Métricas derivadas
   (clarify-resolution) rotuladas como derivada/aproximada (`meta.approximate`).

---

## Cenário 4 — Conteúdo UNTRUSTED renderizado como texto puro (US2, FR-011)

1. Localizar (ou inserir num fixture de teste read-only) uma decisão cujo campo
   `justificativa` contenha `<script>alert(1)</script>` ou markdown ativo.
2. Abrir o detalhe da decisão.
3. **Expected**: o conteúdo é renderizado **literal** (texto visível
   `<script>...`), sem execução de script nem interpretação de markup.

---

## Cenário 5 — Busca hostil não quebra (US3, SC-005)

1. Buscar `q=") OR 1=1 --` e depois `q="aspas" (parenteses) NEAR/3`.
2. **Expected**: ambas retornam `200` com `results` (possivelmente vazio); nenhum
   `5xx`; nenhum vazamento de SQL/erro de parser FTS5.

---

## Cenário 6 — Degradar, nunca quebrar (US6, SC-001)

1. Apontar o back-end para um caminho **inexistente**
   (`CSTK_KNOWLEDGE_DB=/tmp/nao-existe.db`).
2. Fazer `GET /api/v1/overview`, `/api/v1/executions/x/decisions`,
   `/api/v1/search?q=a`, `/api/v1/health`.
3. **Expected**: **todas** respondem `200` com `meta.degraded=true`,
   `meta.reason="db-missing"` e `data` vazio tipado. Nenhum `5xx`.
4. Corromper a base (truncar o arquivo) e repetir.
5. **Expected**: `200` + `meta.reason="db-corrupt"` (via `quick_check`).
6. (UI) Abrir qualquer tela com base ausente.
7. **Expected**: `DegradedBanner` visível com motivo + frescor; e os 4 estados
   (loading/empty/error/degraded) existem por tela.

---

## Cenário 7 — Snapshot que muda / frescor (US-transversal, SC-007)

1. Anotar `meta.freshness.maxIngestedAt` de `GET /api/v1/overview`.
2. Reescrever a base (rodar `cstk recall --ingest` por fora — dono externo) ou
   `touch` no arquivo.
3. Repetir o `GET`.
4. **Expected**: `freshness.mtime` (e/ou `maxIngestedAt`) **avança**; o `ETag`
   muda; uma requisição com o `ETag` antigo **não** retorna `304`.

---

## Cenário 8 — Read-only absoluto auditável (SC-003)

1. `grep -rniE '\b(INSERT|UPDATE|DELETE|CREATE|DROP|ALTER)\b' apps/server/src`
   nos caminhos de dados.
2. Inspecionar a abertura da conexão.
3. **Expected**: zero verbos de mutação em caminhos de dados; conexão aberta com
   `readonly: true` + `PRAGMA query_only=1`; toda rota é `GET`.
