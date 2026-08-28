# Implementation Plan: Watchers de Execução em Andamento e Visualização de Documentação

**Feature**: `state-watchers-and-docs` | **Date**: 2026-07-15 | **Spec**: [spec.md](./spec.md)

## Summary

Duas capacidades sobre o painel read-only `cstk-panel`:

1. **US1 (P1) — Watchers de execução em andamento**: um job de segundo plano no
   server Fastify verifica recorrentemente as execuções `em_andamento`/`aguardando_humano`
   e, em mudança do `state.json`, **delega** a ingestão canônica (`cstk recall --ingest
   --state-dir <dir>`) via subprocesso seguro — mantendo a knowledge.db fresca para que
   o polling do cliente (10s) reflita o progresso em ≤30s, sem WebSocket, sem escrita
   direta no banco e sem tocar o `state.json` (Constitution I/IV/VI).
2. **US2 (P2) — Doc-viewer**: novos endpoints `GET` expõem os artefatos de documentação
   da feature (mapa fixo etapa-SDD → arquivo, com estado "ainda não produzido"), e a UI
   renderiza markdown de forma **segura** (conteúdo UNTRUSTED — sem execução de markup),
   confinando a leitura à árvore de docs do projeto resolvido.

**Abordagem técnica** (da pesquisa): reusar integralmente o padrão existente de rota
Fastify + envelope + ETag/304 + freshness; introduzir 2 net-new controlados —
(a) `node:child_process.execFile` para o subprocesso `cstk` (primeiro uso no server;
delegação sancionada por Principio IV Opção B), (b) uma lib de markdown com HTML
desabilitado/sanitizado para o render seguro. Resolução `project`→caminho via nova
config espelhando `resolveDbPath()` (env > default). Ver [research.md](./research.md).

## Technical Context

**Language/Version**: TypeScript 5.4, Node ≥20 (`package.json`)
**Primary Dependencies**: Fastify 5, better-sqlite3 ^9.6.0 (server, CommonJS); React 19,
Vite 5, TanStack Query v5, react-router-dom v6 / HashRouter (web, ESM); Zod (dual-def
shared-types). **Net-new [PROPOSTA]**: `node:child_process` (subprocesso `cstk`); lib de
markdown seguro (ex.: `react-markdown`+`rehype-sanitize` ou `marked`+sanitizador).
**Storage**: SQLite `knowledge.db` **read-only** (`~/.claude/cstk/knowledge.db` /
`CSTK_KNOWLEDGE_DB`); filesystem para artefatos `.md`. Nenhuma tabela/coluna nova.
**Testing**: Vitest (`npm test`), parity tests em `packages/shared-types`, integração em
`apps/server/test/integration`.
**Target Platform**: processo local, bind `127.0.0.1:3001` (server) + SPA estático.
**Project Type**: web (monorepo npm workspaces: `apps/server`, `apps/web`, `packages/shared-types`).
**Performance Goals**: SC-001 — mudança visível em ≤30s (orçamento: watcher ~10s +
ingestão + polling 10s; ver research Decision 5).
**Constraints**: Read-Only Absoluto (Principio I); sem escrita direta na knowledge.db nem
no `state.json`; sem `--reindex`; sem WebSocket; conteúdo de artefato UNTRUSTED; sem 5xx
por estado de dado (Principio II).
**Scale/Scope**: uso local single-operator; N execuções observadas por tick; sem
multi-tenant/RBAC (MVP).

## Constitution Check

*GATE: passou antes do Phase 0; re-checado após Phase 1 (§Re-check).*

| Principio | Status | Notas |
|-----------|--------|-------|
| I. Read-Only Absoluto (NON-NEGOTIABLE) | **PASS** | Painel não emite mutação SQL. FR-004 **delega** a escrita ao `cstk recall --ingest` (dono canônico), sancionado por Principio IV Opção B. `state.json` é lido (assinatura, Decision 4) mas NUNCA escrito. `--reindex` nunca invocado. Superfície nova = só `GET` (contracts/docs-api §Invariantes). |
| II. Degradar, Nunca Quebrar | **PASS** | FR-012: path não resolvido/inacessível, falha de ingestão e artefato ausente são estados de 1ª classe (`meta.degraded`/`produced:false`), nunca 5xx. Reusa `wrapDegraded()`. |
| III. Honestidade de Métrica | **N/A** | Feature não introduz métrica de custo. Nenhum `$`/token exibido; nenhum campo inventado (research cita fontes reais). |
| IV. Não Reimplementar o que Tem Dono | **PASS** | Ingestão tem dono (`cstk recall`): delegada via subprocesso (Opção B), nunca reimplementada. `--reindex` (dono externo) intocado. |
| V. Conteúdo de Agente é UNTRUSTED | **PASS** | FR-010: artefatos `.md` renderizados com HTML ativo desabilitado/sanitizado (Decision 6), seguindo postura de `TextRaw.tsx`. Servidor entrega markdown bruto; nunca executa markup. |
| VI. Snapshot que Muda | **PASS** | Watcher abre/fecha DB por tick (sem conexão longa). Frescor via `meta.freshness` + ETag reusados (FR-011). Atualização por verificação recorrente, não canal persistente. |
| Padrões de Segurança | **PASS (com hardening do gate)** | Subprocesso seguro (execFile, args em array, timeout, stderr — sem shell; binário absoluto/pinado). Path traversal confinado com **realpath + rejeição de symlink** e fronteira `path.sep` (Decision 7). Markdown com **allowlist de esquema de URL** além de raw-HTML-off (Decision 6). `feature`/`session` UNTRUSTED confinados na derivação (Decision 9). Bind localhost mantido. Ver §Re-check (gate owasp-security). |

**Nenhuma violação de MUST.** Um ponto de honestidade documentado (não é violação): a
constituição §Padrões de Segurança e a Q1 citam precedência "flag/config > env > default"
para o path do DB, mas o código real (`config.ts resolveDbPath`) só implementa `env >
default` (sem camada de flag). O mapa `project`→caminho espelha o padrão REAL (env >
default) — ver research Decision 1.

## Project Structure

### Documentation (this feature)

```
docs/specs/state-watchers-and-docs/
├── spec.md              # /specify + /clarify (existente)
├── plan.md              # Este arquivo
├── research.md          # Phase 0 (8 decisões)
├── data-model.md        # Phase 1 (entidades derivadas/efêmeras)
├── quickstart.md        # Phase 1 (10 cenários, inc. Roundtrip E2E)
└── contracts/
    ├── docs-api.md      # endpoints GET do doc-viewer [PROPOSTA]
    └── watchers.md      # job de fundo + delegação a cstk [PROPOSTA]
```

### Source Code (repository root) — árvore REAL + adições [PROPOSTA]

```
apps/server/src/
├── index.ts                      # main(): registra rotas /api/v1 + INICIA watcher [+]
├── config.ts                     # resolveDbPath(); + resolveProjectPath() [+]
├── db/{open.ts,freshness.ts,columns.ts,queries/*}   # reuso (read-only)
├── lib/{envelope.ts,etag.ts,pagination.ts,fts.ts}   # reuso
├── mappers/index.ts              # reuso (normalizeStatus etc.)
├── routes/
│   ├── executions.ts …           # reuso (servem US1 já frescos)
│   └── docs.ts                    # [+] endpoints GET do doc-viewer
└── watchers/
    └── ingest-watcher.ts          # [+] job de fundo + execFile('cstk', …)

apps/web/src/
├── lib/{api.ts,query.ts,hooks.ts}                   # reuso (+ hooks de docs [+])
├── components/{TextRaw.tsx,FreshnessLabel.tsx,…}    # reuso
│   └── MarkdownView.tsx           # [+] render markdown seguro
└── screens/FeatureDetail.tsx      # reuso (+ aba/painel de docs [+])

packages/shared-types/src/
├── entities.ts + schemas/entities.ts   # [+] FeatureDoc / FeatureDocsList (dual-def)
└── __tests__/parity*.test.ts           # parity cobre os novos DTOs
```

**Structure Decision**: sem novo serviço nem nova camada de dados. Watcher e doc-viewer
vivem dentro do server Fastify existente (mesmo processo/porta). Isso preserva a
arquitetura de snapshot (Principio VI) e evita 4º componente (nenhuma entrada em
Complexity Tracking). DTOs novos seguem o padrão dual-def obrigatório (interface +
Zod), editando os DOIS arquivos (memória `cstk-panel-dto-dual-definition`).

## Convenções de Borda

Feature multi-camada (DB → backend → frontend). Fonte da verdade de cada convenção:

| Camada | Case style | Validação | Fonte da verdade |
|--------|------------|-----------|------------------|
| Colunas knowledge.db (SQLite) | snake_case | schema v7/v8 (EN) | `~/.claude/cstk/knowledge.db` (dono: `cstk recall`) — read-only |
| Backend DTO (TS) | camelCase | Zod | `packages/shared-types/src/entities.ts` + `schemas/entities.ts` |
| Frontend DTO (TS) | camelCase | Zod parse no fetch | re-export de `@cstk-panel/shared-types` (`apps/web/src/lib/api.ts`) |
| API payload (request/response) | camelCase | Zod em ambos os lados | `contracts/docs-api.md` |
| URL path params (`:project`,`:feature`,`:artifact`) | como armazenado + anti-traversal | Zod `/^[^/\\.<>]+$/` | `apps/server/src/routes/executions.ts:40-42` (padrão reusado) |

**Mapper layer (DB ↔ DTO)**: `apps/server/src/mappers/index.ts` (snake_case ↔ camelCase),
já existente (`mapExecution`, `normalizeStatus`, …); reusado, não duplicado. ORM
auto-mapping: **NÃO** (better-sqlite3 cru + mappers manuais + projeção defensiva
`hasColumn`/`NULL as col` para tolerância v2→v8).

**Validação Zod**: em ambas as bordas — o server monta o envelope tipado; o cliente
faz `ApiEnvelopeSchema(dataSchema).parse` em `fetchApi` (`apps/web/src/lib/api.ts`).
Schema compartilhado em `packages/shared-types/` (dual-def). O Roundtrip E2E
(quickstart Cenário 10) valida o payload REAL contra o DTO — anti-drift snake/camel.

## Complexity Tracking

> Vazio — Constitution Check sem violações. Nenhuma complexidade adicional a justificar
> (sem novo serviço, sem nova camada de dados, sem canal persistente). Os 2 net-new
> (`child_process`, lib de markdown) são exigências diretas de FR-004 e FR-006/FR-010,
> não complexidade acidental.

## Re-check (pós-Phase 1)

Design não introduziu 4º componente nem canal persistente; watcher e doc-viewer residem
no server existente. Principios I, V, VI seguem respeitados (delegação; render inerte;
DB por-tick). Nenhum MUST violado após o design. **Constitution gate PASS.**

**Gates de qualidade complementares** (rodados neste plan):
- `validate-documentation` (plan-profile): **PASS**, 0 findings (validate-sdd.sh limpo
  nos 6 artefatos; coerência cross-artifact — todas as FRs/SCs definidas na spec).
- `owasp-security`: **pass-with-findings** — 0 critical, 2 HIGH, 4 medium, 3 low;
  Principio I (Read-Only/GET-only) preservado. Os 2 HIGH (XSS por esquema de URL em
  markdown; escape por symlink na leitura de docs) foram **corrigidos no plano**
  (Decisions 6, 7) e os medium consolidados em Decision 9. Por a constituição tratar
  segurança como **MUST** e a regra de gate exigir bloqueio para findings HIGH de
  segurança, esta onda encerra com **BloqueioHumano** solicitando ratificação da
  postura de segurança antes de avançar para `checklist`/implementação.
