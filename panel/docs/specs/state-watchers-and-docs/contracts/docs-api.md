# Contract: Doc-Viewer Read API

**Feature**: `state-watchers-and-docs` | **Phase**: 1 | **Date**: 2026-07-15

> **[PROPOSTA — a validar na implementação]**: os DOIS endpoints abaixo são
> **net-new** (não existem hoje). Não são afirmados como reais. O que É real e
> reusado sem alteração: o padrão de rota Fastify, o envelope, o ETag/304 e a
> degradação — citados abaixo à fonte. Naming de campos em `camelCase` (Convenções
> de Borda). Superfície exclusivamente `GET` (Principio I — Read-Only Absoluto).

## Padrões reais reusados (NÃO inventados)

| Peça | Fonte real | Reuso |
|------|-----------|-------|
| Envelope `{ data, meta:{degraded,reason,freshness,schemaVersion} }` | `apps/server/src/lib/envelope.ts` (`wrap`, `wrapDegraded`) | idêntico |
| ETag fraco + 304 | `apps/server/src/lib/etag.ts` (`generateETag`, `etagMatches`) | idêntico ao padrão de `executions.ts:99-104` |
| Validação anti-traversal de path param | `apps/server/src/routes/executions.ts:40-42` (`/^[^/\\.<>]+$/`) | aplicada a `:project`, `:feature`, `:artifact` |
| Freshness | `apps/server/src/db/freshness.ts` (`computeFreshness`) | idêntico |
| Base path `/api/v1` | `apps/server/src/index.ts` | idêntico |

Nota de frescor: como os artefatos vêm do **filesystem** (não da knowledge.db), o
ETag destes endpoints **[PROPOSTA]** deve derivar do `mtime` do(s) arquivo(s) `.md`
lidos — não do `mtime` do DB. O `meta.freshness` do envelope segue existindo
(computado do DB) para consistência do envelope, mas o ETag de invalidação é do
arquivo. (Detalhe de implementação a confirmar.)

---

## GET /api/v1/features/:project/:feature/docs — listar artefatos

Lista os artefatos esperados (mapa fixo, Decision 8) com estado produzido/ausente,
mais arquivos extras presentes (SC-002). Nenhum `content` (só metadados).

**Path params** (validados anti-traversal):
- `project`: string, `/^[^/\\.<>]+$/`
- `feature`: string, `/^[^/\\.<>]+$/`

**Response 200** (envelope padrão):

```json
{
  "data": {
    "project": "cstk-panel",
    "feature": "state-watchers-and-docs",
    "artifacts": [
      { "stage": "specify",      "artifactId": "spec",       "fileName": "spec.md",       "produced": true,  "extra": false },
      { "stage": "plan",         "artifactId": "plan",       "fileName": "plan.md",       "produced": true,  "extra": false },
      { "stage": "plan",         "artifactId": "research",   "fileName": "research.md",   "produced": true,  "extra": false },
      { "stage": "plan",         "artifactId": "data-model", "fileName": "data-model.md", "produced": true,  "extra": false },
      { "stage": "plan",         "artifactId": "quickstart", "fileName": "quickstart.md", "produced": true,  "extra": false },
      { "stage": "create-tasks", "artifactId": "tasks",      "fileName": "tasks.md",      "produced": false, "extra": false }
    ]
  },
  "meta": { "degraded": false, "reason": null, "freshness": { "mtime": "…", "maxIngestedAt": "…" }, "schemaVersion": "8" }
}
```

- `produced: false` ⇒ artefato do mapa ainda não gerado (FR-007) — **não é erro**.
- `extra: true` ⇒ arquivo presente na árvore fora do mapa fixo (listável, SC-002).
- Header `ETag` presente; `If-None-Match` casando ⇒ `304` (sem corpo).

**Response 200 degradado** (FR-008/FR-012):
- `project` sem entrada no mapa de caminhos, OU caminho inacessível ⇒
  `wrapDegraded(reason, dbPath)` com `data: null`, `meta.degraded: true`,
  `meta.reason` explicando (ex.: `"project-path-unresolved"` / `"project-path-inaccessible"`).
  **[PROPOSTA]** os valores de `reason` são novos; os existentes hoje são
  `'db-missing'|'db-corrupt'|'schema-mismatch'|'table-empty'` (`packages/shared-types/src/envelope.ts`).

**Response 400**: path param inválido (traversal) ⇒ `{ data:null, meta:…, error:'Invalid …' }`
(mesmo shape de erro de `executions.ts:112`).

---

## GET /api/v1/features/:project/:feature/docs/:artifact — conteúdo de um artefato

Retorna o conteúdo markdown bruto de UM artefato para render seguro no cliente.

**Path params**: `project`, `feature`, `artifact` (todos anti-traversal). `:artifact`
== `artifactId` do mapa (ex.: `spec`, `plan`) OU nome de arquivo extra sanitizado.

**Response 200**:

```json
{
  "data": {
    "stage": "specify",
    "artifactId": "spec",
    "fileName": "spec.md",
    "produced": true,
    "extra": false,
    "content": "# Feature Specification: …\n\n…"
  },
  "meta": { "degraded": false, "reason": null, "freshness": { … }, "schemaVersion": "8" }
}
```

Nota (validada empiricamente na implementação, task 4.2): `stage`/`extra` fazem
parte de `FeatureDocDTO` (obrigatorios, sem `?`) e a rota real
(`routes/docs.ts`, `{ ...entry, content }`) sempre os inclui — omiti-los do
exemplo acima e um erro de brevidade do contrato, nao do wire format real.

- `content`: markdown BRUTO, tratado como **UNTRUSTED** (FR-010 / Principio V). O
  cliente renderiza via `MarkdownView` (`apps/web/src/components/MarkdownView.tsx`,
  task 4.1 — react-markdown + rehype-sanitize + allowlist proprio de esquema de
  URL) com HTML ativo desabilitado/sanitizado (Decision 6) — NUNCA
  `dangerouslySetInnerHTML` com HTML não sanitizado.
- Leitura confinada a `<projectPath>/docs/specs/<feature>/` (FR-009, Decision 7).

**Response 200 "ainda não produzido"** (FR-007):

```json
{ "data": { "stage": "plan", "artifactId": "plan", "fileName": "plan.md", "produced": false, "extra": false, "content": null }, "meta": { … } }
```
Ausência do artefato é sinalizada com `produced:false` + `content:null`, **não** 404.

**Response 200 degradado**: idem endpoint de lista (path não resolvido/inacessível).

**Response 400**: `:artifact` que escapa a fronteira (traversal) ⇒ rejeitado.

---

## Invariantes de contrato (gate Principio I/V)

1. Todos os métodos são `GET`. Nenhum `POST/PUT/PATCH/DELETE` (Principio I).
2. Nenhum path do cliente é usado sem canonicalização + confinamento (FR-009). O
   confinamento resolve **symlinks** (`fs.realpath`) e re-confina sob `realpath(root)+sep`,
   rejeitando `.md` symlinkado (gate owasp HIGH — Decision 7); comparação de prefixo na
   fronteira `path.sep`; cap de tamanho na leitura.
3. `content` nunca é interpretado como HTML no servidor nem entregue como HTML
   sanitizado pelo servidor — o servidor entrega markdown bruto; a sanitização/
   render seguro acontece no cliente (Decision 6). O servidor NÃO executa markup. O
   cliente **descarta esquemas de URL perigosos** (`javascript:`/`data:`/`vbscript:`)
   em links/imagens além de desligar raw HTML (gate owasp HIGH).
4. Ausência de artefato = `produced:false` (sucesso), nunca 5xx nem 404-erro.
