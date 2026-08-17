# cstk-panel — Dashboard de Observabilidade Read-Only

Dashboard de observabilidade sobre as execuções dos orquestradores `agente-00c` / `feature-00c` (pipeline SDD do CLI `cstk`).
Lê diretamente da `knowledge.db` (SQLite + FTS5, schemas **v2 a v14**) — **não escreve, não muta, não reconstrói o índice**.

Além das execuções (ondas, decisões, tarefas, skills, eventos, alertas, bloqueios, memórias), o painel expõe o consumo medido pela telemetria do Claude Code (tokens e custo real em USD por onda/modelo, schema v11/v12), o consumo avulso fora de execuções (`loose_usage`, v13) e o gauge de rate limits da conta (`plan_usage`, v14) — sempre que a base contiver essas tabelas.

## Como o painel é distribuído

- **Via CLI `cstk` (recomendado)**: `cstk serve [--docker] [--update] [--port N]` (cstk ≥ 5.18.0) baixa o tarball da GitHub Release (`cstk-panel-<versão>.tar.gz` + `.sha256`, publicados pelo workflow `release.yml` no push de tag `v*`), verifica a integridade (fail-closed), instala em `~/.local/share/cstk/panel` e sobe API + SPA numa porta só. `--update` atualiza para a última release (sem o par de assets verificáveis o update bloqueia e exige `--allow-unverified`); `--docker` roda em container, sem `node`/`npm` no host. Detalhes na tela **FAQ** do próprio painel.
- **Standalone (este repositório)**: clone + `npm install` + `npm run build` + `npm start` (ver abaixo).

## Pré-requisitos

- Node.js 20, 22, 23 ou 24 (`better-sqlite3` ≥ 12.4 traz prebuilds para todas essas ABIs — sem `node-gyp` no usuário)
- npm ≥ 10
- `~/.claude/cstk/knowledge.db` (gerada por `cstk recall --ingest`)
- CLI `cstk` no `PATH` (ou apontado por `CSTK_BINARY_PATH`) — usado pelo watcher de ingestão em segundo plano; sem ele o painel continua funcionando, apenas não ingere sozinho

## Setup (desenvolvimento)

```bash
# 1. Instalar dependências (todos os workspaces)
npm install

# 2. Server (Fastify, :3001) + web (Vite, :5173) em paralelo, com hot-reload
npm run dev
```

O front-end de desenvolvimento sobe em `http://127.0.0.1:5173` e faz proxy de `/api` para o servidor em `http://127.0.0.1:3001`.

## Build e execução (produção)

```bash
# Compila shared-types -> server -> web (ordem de dependências)
npm run build

# Sobe API + SPA no MESMO processo/porta (default http://127.0.0.1:3001)
npm start
```

Em produção o servidor Fastify serve o bundle de `apps/web/dist` via `@fastify/static` (SPA com `HashRouter`, fallback para `index.html`) e a API em `/api/v1`. Se o build do web estiver ausente, o servidor sobe **somente a API** e registra um aviso — nunca falha o boot.

## Variáveis de ambiente

| Variável | Padrão | Descrição |
|----------|--------|-----------|
| `CSTK_KNOWLEDGE_DB` | `~/.claude/cstk/knowledge.db` | Path absoluto da base SQLite de conhecimento |
| `PORT` | `3001` | Porta do servidor HTTP (bind **sempre** em `127.0.0.1`) |
| `CORS_ORIGIN` | `http://localhost:5173` | Origem permitida pelo CORS |
| `LOG_LEVEL` | `info` | Nível de log do Fastify (`trace`/`debug`/`info`/`warn`/`error`) |
| `CSTK_SCHEMA_VERSIONS` | `2,3,…,14` | CSV de versões de `schema_meta.schema_version` aceitas na abertura (allowlist; versão fora da lista → painel degradado) |
| `CSTK_WEB_DIR` | `apps/web/dist` | Diretório do SPA buildado servido pelo `npm start` |
| `CSTK_PROJECT_PATHS` | *(vazio)* | Mapa `nome=/abs/path;outro=/abs/path` de projetos observáveis — usado pelo watcher (descoberta via filesystem) e pelas rotas de docs; desde o schema v9 há fallback automático via `executions.target_project_path` |
| `CSTK_WATCH_INTERVAL_MS` | `5000` | Cadência do watcher de ingestão |
| `CSTK_INGEST_TIMEOUT_MS` | `90000` | Timeout do subprocesso `cstk recall --ingest` |
| `CSTK_BINARY_PATH` | *(resolve no `PATH`)* | Caminho explícito do binário `cstk` |

Exemplo apontando para base alternativa:

```bash
CSTK_KNOWLEDGE_DB=/path/to/knowledge.db PORT=4001 npm start
```

## Watcher de ingestão

O servidor roda um watcher em segundo plano que, a cada tick, verifica execuções ativas na `knowledge.db` **e** state-dirs (`.claude/agente-00c-state/`, `.claude/feature-00c-state/<feature>/`) presentes no filesystem das raízes conhecidas (`CSTK_PROJECT_PATHS` + `executions.target_project_path`) — assim um `state.json` recém-criado é ingerido antes mesmo de existir linha em `executions`. A ingestão é **delegada** ao dono canônico via subprocesso (`cstk recall --ingest`): o painel nunca escreve na base, nunca toca o `state.json` (só `stat`/`readdir`) e nunca roda `--reindex`. Limite de 4 subprocessos concorrentes por tick, backoff de 60s após falha, e falha de tick nunca derruba o processo.

## Telas

Menu principal (`observar` / `diagnosticar`):

| Rota | Tela | O que mostra |
|------|------|--------------|
| `/` | Visão Geral | 8 KPIs, filtros de período e projeto |
| `/projects`, `/projects/:project` | Projetos | Lista com features, atividade, tokens e custo (OTel / spawn) por projeto; detalhe |
| `/features`, `/features/:project/:feature` | Features | Portfólio de features; detalhe com doc-viewer dos artefatos SDD (spec, plan, research, data-model, quickstart, tasks, contracts, checklists) lidos do filesystem do projeto-alvo — Markdown GFM + diagramas Mermaid, sanitizados |
| `/executions`, `/executions/:execucaoId` | Execuções | Lista e detalhe da execução: ondas, decisões, tarefas (filtráveis por onda), skills, eventos, alertas, bloqueios, sugestões, distribuição de score |
| `/executions/:execucaoId/decision-map` | Mapa de decisões | Visualização das decisões da execução |
| `/alerts` | Alertas | Sinais de alerta por período |
| `/metrics` | Métricas | Duração, throughput e mix de modelos por etapa SDD, tokens/custo ao longo do tempo (OTel), uso de agentes, taxa de testes, latência humana, recall, consumo avulso e rate limits do plano |
| `/tasks` | Tarefas | Backlog cruzado de tarefas |
| `/incidents` | Incidentes | Timeline global de eventos operacionais |
| `/memories` | Memórias | Memórias ingeridas (schema v4+) |
| `/search` | Busca de Conhecimento | FTS5 sobre a `knowledge_fts` (entrada sanitizada; rota limitada a 30 req/min por IP) |
| `/cheatsheet` | Cheat Sheet | Referência rápida do CLI `cstk` |
| `/faq` | FAQ | Passo-a-passo de uso |
| `/source` | Fonte de Dados | Metadados da base (caminho, schema, frescor, tamanho, contagem por tabela) via `/health` |

Tema claro/escuro, menu retrátil e drawer no mobile (< 768px).

## API

Prefixo `/api/v1`, **44 endpoints `GET`** (não há métodos de escrita), agrupados em: `health`, `overview`, `projects`, `features` (+ `docs`), `executions` (+ `waves`, `decisions`, `tasks`, `skills`, `events`, `alerts`, `bloqueios`, `suggestions`, `score-distribution`), `alerts`, `tasks`, `events`, `memories`, `search` e 20 rotas `metrics/*`.

Toda resposta usa o envelope padrão (`packages/shared-types`):

```jsonc
{
  "data": { /* ... */ },          // null quando degradado
  "meta": {
    "degraded": false,           // true quando base ausente/corrompida/schema não aceito
    "reason": null,              // motivo da degradação
    "freshness": { "mtime": "…", "maxIngestedAt": "…" },
    "schemaVersion": "14"
  },
  "error": null
}
```

Respostas carregam `ETag` derivado do frescor da base; trocar a base invalida o cache (o cliente web usa `If-None-Match` e valida todo payload com os schemas Zod de `shared-types`). Rotas `/api/*` desconhecidas devolvem 404 JSON (nunca HTML). Headers globais: `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Cache-Control: no-store`.

## Estrutura do monorepo

```
cstk-panel/
├── apps/
│   ├── server/          # @cstk-panel/server — Fastify 5 + better-sqlite3 (read-only)
│   │   ├── src/
│   │   │   ├── config.ts    # env, allowlist de schema, mapa de projetos
│   │   │   ├── db/          # abertura read-only, freshness, queries
│   │   │   ├── routes/      # 12 módulos de rotas /api/v1
│   │   │   ├── mappers/     # snake_case -> camelCase, normalizações
│   │   │   ├── lib/         # envelope, etag, fts (sanitização), pagination, project-root
│   │   │   ├── watchers/    # ingest-watcher (delegação a `cstk recall --ingest`)
│   │   │   └── docs/        # leitura de artefatos SDD do projeto-alvo
│   │   └── test/            # integração Vitest sobre base fixture real
│   └── web/             # @cstk-panel/web — React 19 + Vite 5 + TanStack Query + react-router (HashRouter)
│       └── src/         # screens/, components/, hooks/, estados transversais
├── packages/
│   └── shared-types/    # DTOs (interfaces) + schemas Zod + envelope — contrato BE<->FE
├── scripts/             # create-fixture.mjs, migrate-fixture-v3.mjs (fixtures de teste)
├── docs/                # constitution.md, briefing, design de UI/UX, specs SDD por feature
└── .github/workflows/release.yml   # tarball + sha256 anexados à GitHub Release no push de tag v*
```

Cada DTO existe em dois lugares que devem andar juntos: a interface em `packages/shared-types/src/entities.ts` e o schema Zod em `packages/shared-types/src/schemas/entities.ts` — os testes de paridade (`parity*.test.ts`) validam payloads reais contra os schemas.

## Scripts

| Comando | Descrição |
|---------|-----------|
| `npm run dev` | Server (3001) + web (5173) em paralelo, hot-reload |
| `npm run build` | Build de produção (shared-types → server → web) |
| `npm start` | API + SPA em um processo (`node apps/server/dist/index.js`) |
| `npm test` | Suite Vitest completa (server + web + shared-types) |
| `npm run lint` | ESLint em todos os workspaces |
| `npm run lint:readonly-check` | Falha se houver verbo SQL de mutação em `apps/server/src` |
| `npm run typecheck` | `tsc --noEmit` em todos os workspaces |

## Testes

57 arquivos / **754 testes** (Vitest), rodando em ~4s:

- **Server** (`apps/server/test/`) — saúde e headers, abertura da base e motivos de degradação, freshness/ETag, roundtrip com payload real, todas as rotas GET, degradação por endpoint, ausência de mutação + payloads hostis FTS5, mappers, watcher, docs.
- **Web** (`apps/web/src/**/*.test.ts`) — lógica de telas/componentes (formatação, filtros, navegação).
- **Shared-types** (`packages/shared-types/`) — schemas Zod do envelope e paridade de cada DTO (sintético e com payloads reais).

```bash
npm test                                   # tudo
cd apps/server && npx vitest run           # só server (usa base fixture)
cd packages/shared-types && npx vitest run # só paridade de tipos
```

Ver `CONTRIBUTING.md` para invariantes a checar antes de abrir PR e para o fluxo de release.

## Princípios constitucionais (`docs/constitution.md`)

1. **Read-Only Absoluto (NON-NEGOTIABLE)** — conexão `readonly: true` + `PRAGMA query_only = 1`; zero verbos de mutação SQL (guardado por `lint:readonly-check`).
2. **Degradar, Nunca Quebrar** — base ausente/corrompida/schema não aceito → `meta.degraded=true`, nunca 5xx; web ausente → só API; tick do watcher falho → só log.
3. **Honestidade de Métrica** — cada número é rotulado como proxy (`tool_calls`), derivado ou **medido**; custo em USD só quando medido na fonte (OTel, v11+), com cobertura de amostra explícita; ausência de medição é `—`, nunca `0`/`$0`; nada é estimado a partir de preço de token.
4. **Não Reimplementar o que Tem Dono** — mix de modelos (`model-routing-report.sh`), árvore de decisões (skill `decision-tree`) e reindex (`cstk recall --reindex`) não são duplicados; quando preciso, delega-se via subprocesso seguro.
5. **Conteúdo de Agente é UNTRUSTED** — campos vindos da base renderizados como texto (`<TextRaw>`), nunca `dangerouslySetInnerHTML`; Markdown do doc-viewer passa por `rehype-sanitize`/DOMPurify; FTS5 sanitizado; anti-traversal e lista de zonas proibidas em paths derivados da base.
6. **Snapshot que Muda** — `freshness` em todo envelope (mtime + max `ingested_at`); ETag invalida cache ao trocar a base.

## Changelog

Histórico completo em [`CHANGELOG.md`](./CHANGELOG.md) (Keep a Changelog + SemVer).
