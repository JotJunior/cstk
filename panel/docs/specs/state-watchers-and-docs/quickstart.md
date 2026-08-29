# Quickstart / Cenários de Teste: state-watchers-and-docs

**Feature**: `state-watchers-and-docs` | **Phase**: 1 | **Date**: 2026-07-15

> Ambiente de dev (verificado): `npm run dev` sobe server (Fastify, `:3001`) + web
> (Vite, `:5173`), HashRouter, API em `/api/v1` (`apps/web/src/lib/api.ts`).
> knowledge.db em `~/.claude/cstk/knowledge.db` (ou `CSTK_KNOWLEDGE_DB`).
> Build/test/typecheck: `npm run build`, `npm test` (vitest), `npm run typecheck`,
> `npm run lint`.

## Cenário 1 — Watcher reflete execução em andamento ≤30s (US1, SC-001)

1. Configurar `CSTK_PROJECT_PATHS` [PROPOSTA] com `<project>=<abs-path>` de um projeto
   que tenha uma execução `feature-00c`/`agente-00c` **em andamento**.
2. Abrir o painel; navegar até a execução em andamento.
3. Provocar mudança observável na execução (nova onda concluída / nova decisão /
   transição para `aguardando_humano`) — o state.json muda.
4. Aguardar sem recarregar a página.
5. **Expected**: o watcher detecta a mudança de assinatura do state.json (FR-014),
   dispara `cstk recall --ingest --state-dir <dir>`, a knowledge.db fica fresca, e o
   polling do cliente (10s) reflete o novo estado (contagem de ondas / última
   decisão / etapa / status) **em ≤ 30s**, sem ação manual. O `FreshnessLabel`
   avança (`meta.freshness.maxIngestedAt`).

## Cenário 2 — Watcher ocioso sem execução ativa (US1 AC-3, FR-013)

1. Garantir que NENHUM projeto observado tem execução `em_andamento`/`aguardando_humano`.
2. Manter o painel aberto por vários ticks.
3. **Expected**: o watcher não dispara nenhum subprocesso `cstk` (verificável no log/
   ausência de processos filhos); permanece ocioso; nenhuma verificação contínua
   desnecessária.

## Cenário 3 — Watcher para de observar execução concluída (US1 AC-4, FR-003)

1. Com uma execução em andamento sendo observada, levá-la a `concluida`/`abortada`.
2. **Expected**: no tick seguinte a execução sai do conjunto ativo; o watcher deixa
   de disparar ingestão para ela (passa a ser dado histórico).

## Cenário 4 — Doc-viewer renderiza spec.md formatado (US2 AC-1, FR-005/FR-006)

1. Abrir a visão de uma feature que já tem `spec.md`.
2. **Expected**: o conteúdo do `spec.md` aparece **formatado** (headings, listas,
   tabelas), não como texto bruto; sem sair do painel.

## Cenário 5 — "Ainda não produzido" (US2 AC-2, FR-007)

1. Abrir a visão de uma feature que ainda NÃO passou por `/plan` (sem `plan.md`).
2. Solicitar o artefato "plano".
3. **Expected**: o painel indica claramente "ainda não produzido" (`produced:false`),
   **sem erro** (nada de 404 vermelho / tela quebrada).

## Cenário 6 — Navegação entre artefatos (US2 AC-3, SC-002)

1. Abrir feature com múltiplos artefatos (`spec`, `plan`, `tasks`, `research`, extras).
2. **Expected**: usuário navega entre os artefatos disponíveis; 100% dos já
   produzidos são visualizáveis, inclusive arquivos extras fora do mapa fixo.

## Cenário 7 (error case) — Caminho do projeto inacessível (FR-012)

1. Configurar um `project` cujo caminho foi removido / sem permissão.
2. Abrir a visão de docs / observar a execução.
3. **Expected**: resposta `200` com `meta.degraded:true` e `meta.reason` explicando
   (ex.: `project-path-inaccessible`); **nenhum 5xx**; UI mostra estado degradado,
   não omite a falha silenciosamente.

## Cenário 8 (segurança) — Conteúdo UNTRUSTED não executa (FR-010, Principio V)

1. Ter um artefato `.md` com HTML/`<script>` embutido (documentos são gerados por
   agentes — não confiáveis).
2. Abrir esse artefato no doc-viewer.
3. **Expected**: o markup ativo é renderizado **inerte** (não executa; sem alert/DOM
   injection). Nunca `dangerouslySetInnerHTML` com HTML não sanitizado.

## Cenário 9 (segurança) — Path traversal rejeitado (FR-009)

1. Chamar `GET /api/v1/features/:project/:feature/docs/..%2f..%2fetc%2fpasswd`
   (ou variações de traversal em `:artifact`).
2. **Expected**: `400` (param inválido) — a leitura é confinada a
   `<projectPath>/docs/specs/<feature>/`; nenhum arquivo fora da fronteira é servido.

---

## Cenário 10 — Roundtrip End-to-End (OBRIGATÓRIO — borda backend↔frontend)

> Motivo: 40 ondas históricas mascararam um drift snake_case↔camelCase porque os
> testes parseavam mocks, não o payload real (memória `migration-gates-false-green`).
> Este cenário faz chamada REAL ao backend e compara o shape contra o contrato.

1. Subir o backend real (`npm run dev` ou `npm start`) apontando para uma
   knowledge.db populada e um `CSTK_PROJECT_PATHS` válido.
2. Fazer uma chamada HTTP REAL (não mock, não fixture) a
   `GET /api/v1/features/<project>/<feature>/docs` e capturar o payload de resposta.
3. Validar o payload contra o schema Zod `FeatureDocsListSchema` [PROPOSTA]
   (`packages/shared-types/src/schemas/…`) — parse deve passar.
4. Repetir para `GET /api/v1/features/<project>/<feature>/docs/spec` e validar
   contra `FeatureDocSchema` [PROPOSTA].
5. **Expected**:
   - Campos em `camelCase` exatamente como o contrato `contracts/docs-api.md`
     (`artifactId`, `fileName`, `produced`, `extra`, `content`).
   - Envelope tem `meta.freshness.{mtime,maxIngestedAt}` e `meta.schemaVersion`.
   - Header `ETag` presente; segunda chamada com `If-None-Match` retorna `304`.
   - **Zero divergência** entre o shape do payload real e o DTO declarado — qualquer
     drift é falha do teste (não do mock).

**Comando de verificação** (após implementação): `npm test` (inclui parity
`packages/shared-types/src/__tests__/parity*.test.ts`) + o teste de roundtrip
`apps/server/test/integration/*` [PROPOSTA].
