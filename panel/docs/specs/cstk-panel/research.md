# Research: cstk-panel — Phase 0

**Feature**: `cstk-panel`
**Objetivo**: resolver unknowns técnicos e decisões em aberto (D2/D3/D5) antes
do design. Nenhum `NEEDS CLARIFICATION` deve sobreviver a este documento.

> Schema v2 verificado **empiricamente** (não inferido): `sqlite3` em
> `mode=ro&immutable=1` sobre `~/.claude/cstk/knowledge.db` retornou
> `schema_version=2`, 10 tabelas-fonte + `knowledge_fts` (FTS5), com 12
> execuções / 232 ondas / 875 decisões / 1019 linhas FTS. Toda decisão de
> modelo abaixo se apoia nesse DDL real.

---

## Decision 1 — Driver SQLite read-only (Node/TS)

**Decision**: `better-sqlite3` com `new Database(path, { readonly: true,
fileMustExist: false })` + `PRAGMA query_only = 1` + DSN lógica
`file:/abs/path/knowledge.db?mode=ro&immutable=1&_busy_timeout=5000`.

**Rationale**:
- API **síncrona** — ideal para um painel read-only: queries simples sobre base
  pequena (~3MB), sem necessidade de pool assíncrono. Código linear, fácil de
  auditar contra mutação (Princípio I).
- `readonly: true` + `query_only=1` é defesa em profundidade: mesmo um `prepare`
  acidental com verbo de mutação falha em runtime.
- `fileMustExist: false` permite tratar **base ausente** como degradação
  (Princípio II) em vez de exceção de bootstrap.
- `immutable=1` informa ao SQLite que o arquivo não muda durante a conexão →
  evita locking; reabrimos por requisição para respeitar o "snapshot que muda"
  (Princípio VI), capturando `mtime` a cada request.

**Alternatives considered**:
- `node:sqlite` (built-in, Node 22+): ainda experimental; descartado por
  maturidade e por exigir runtime mais novo.
- `sql.js` (WASM): carrega a base inteira em memória; desperdício e perde
  semântica de `immutable`/`mtime`.
- Driver assíncrono (`sqlite3` callback): assincronia desnecessária complica a
  auditabilidade read-only sem ganho mensurável nesta escala.

---

## Decision 2 — Framework HTTP (back-end)

**Decision**: **Fastify 5**.

**Rationale**: overhead baixo, hooks (`onSend`) para injetar headers
(`X-Content-Type-Options: nosniff`, `ETag`) e cache 304 de forma centralizada,
plugin oficial de CORS (restrito a `localhost`) e `@fastify/rate-limit` para o
rate-limit leve da busca FTS5 (FR-020). Schema-first casa com Zod.

**Alternatives considered**:
- Express 5: maduro, porém hooks de resposta e rate-limit exigem mais cola
  manual; sem schema-first nativo.
- Hono: excelente, mas o ecossistema de plugins (rate-limit, cors) é menos
  consolidado para um serviço local single-purpose.
- `node:http` puro: reinventa roteamento/headers/cache sem ganho.

---

## Decision 3 (D3) — Mix de modelos: **Opção A-revisada (exibir mix DERIVADO e rotulado)**

> **Revisão 2026-05-25:** a decisão original (Opção A — card "indisponível nesta
> fonte") foi **revista**. O painel passa a **exibir o mix DERIVADO** das decisões
> de roteamento, rotulado, em Métricas — consistente com o que a **Visão Geral já
> fazia** (`getModelMix`, FR-010 "derivado · decisões"). Ver "Revisão" abaixo.

**Decision (original)**: o painel não reimplementa nem delega o mix; onde a UI
esperaria essa visão, exibia o card "indisponível nesta fonte".

**Rationale (original)**:
- Princípio IV (MUST NOT reimplementar dono canônico): o mix tem dono
  `model-routing-report.sh`, que opera sobre `state.json`.
- Opção B (delegar via subprocesso) **amplia a superfície de ataque** (exec,
  leitura fora da `knowledge.db`, stdout não-confiável). Conflita com read-only.
- ~~A `knowledge.db` schema v2 não tem coluna de modelo por decisão~~ —
  **incorreto/desatualizado**: as decisões de roteamento são gravadas como
  `escolha='model:<modelo>'` na tabela `decisions` (é o que `getModelMix` consome).

**Revisão (2026-05-25) — por que mudou**:
- As decisões `escolha='model:%'` **existem** na base e a **Visão Geral já exibia**
  o mix derivado delas (rotulado "derivado · decisões", justificado por FR-010).
  Manter Métricas como "indisponível" era **inconsistente** com a mesma fonte.
- A harness **permite delegar o modelo** (param `model` do Agent/Task, frontmatter
  de subagente, fast mode); o orquestrador **registra essa intenção**. O que falta
  é *confirmação pós-hoc do modelo executado* (fallback silencioso) — isso é
  detalhe de **rótulo**, não de disponibilidade.
- **Não viola o Princípio IV / FR-010**: exibir uma visão **derivada e rotulada**
  (`'intenção do roteador · derivado · canônico: model-routing-report.sh'`,
  `meta.approximate=true`) **não é reimplementar o relatório canônico** — é a mesma
  postura já aceita no Overview. A verdade canônica continua em
  `model-routing-report.sh` sobre `state.json`.

**Implementação**: endpoints `/metrics/model-mix` (donut total) e
`/metrics/model-mix-by-stage` (empilhado por etapa), derivados de
`decisions.escolha='model:%'`, ambos com `meta.approximate=true`.

**Gap remanescente (data-gaps.md #5):** mix *confirmado* (modelo efetivamente
executado, incl. fallback) exigiria o orquestrador logar `modelo_confirmado`.

**Alternatives considered**:
- Opção B (delegar ao dono via subprocesso): rejeitada por superfície de ataque /
  confinação read-only. A visão derivada não precisa dela.

---

## Decision 4 (D2) — Empacotamento: **standalone no MVP, com gancho para `cstk panel serve` depois**

**Decision**: MVP entrega o painel como **monorepo standalone** (`apps/server` +
`apps/web`) iniciável por script local (`npm run dev` / `npm start`). O
empacotamento como subcomando `cstk panel serve` fica documentado como evolução,
não bloqueante.

**Rationale**:
- O projeto-alvo hoje não tem código; criar o monorepo standalone é o caminho de
  menor atrito e mais testável isoladamente.
- Acoplar à CLI `cstk` agora introduziria dependência de build/distribuição do
  toolkit (dono externo) sem ganho no MVP.
- A resolução de path do DB (config > `$CSTK_KNOWLEDGE_DB` > default) já é
  compatível com ambos os empacotamentos — a migração futura é aditiva.

**Alternatives considered**:
- Subcomando `cstk panel serve` desde já: maior acoplamento ao toolkit e ao seu
  ciclo de release; adiado.

---

## Decision 5 (D5) — Granularidade de séries temporais: **por dia, com fallback por execução**

**Decision**: métricas temporais (`cost-over-time`) agregam **por dia**
(`date(source_ts)` / `date(iniciada_em)`), com o período selecionável
(`24h|7d|30d|all`). Quando o volume de um bucket diário é baixo demais para ser
informativo, a série permanece por dia (sem reagrupar) e a UI rotula a
escassez — nunca interpola/inventa pontos (Princípio III).

**Rationale**:
- Base atual é pequena (12 execuções); agregação diária é legível e barata em
  SQLite (`GROUP BY date(...)`).
- "Por execução" produziria eixo-x irregular e difícil de comparar entre
  períodos.
- Decisão revisável quando houver volume real — documentada como aproximação
  controlada, não como verdade absoluta.

**Alternatives considered**:
- Por execução: rejeitada por irregularidade do eixo temporal.
- Por hora: granularidade excessiva para o volume atual; reavaliável.

---

## Decision 6 — Escaping FTS5 (2 camadas) e segurança da busca

**Decision**: a busca aplica **duas camadas** independentes (Princípio V / FR-012):
1. **Camada FTS5 (tokenização)**: o termo do usuário é dividido em tokens; cada
   token é **envolvido em aspas duplas** e aspas internas são escapadas
   (duplicadas), produzindo uma query FTS5 de *phrase tokens* segura. Operadores
   FTS (`AND`/`OR`/`NEAR`/`*`/parênteses) digitados pelo usuário são tratados
   como **texto literal**, não como sintaxe — evita erro de parser e injeção de
   operador.
2. **Camada SQL (binding parametrizado)**: a string FTS resultante é passada via
   **placeholder `?`** ao `MATCH` — `SELECT ... FROM knowledge_fts WHERE
   knowledge_fts MATCH ? ORDER BY bm25(knowledge_fts) LIMIT ? OFFSET ?`. **Nunca**
   interpolação de string crua.

**Rationale**: cobre tanto FTS5-injection (sintaxe hostil quebrando o parser)
quanto SQL-injection. Entrada hostil → resultado válido ou vazio, jamais `5xx`
(SC-005). Precedente recuperado (read-back): `knowledge-db-metrics/onda-002`
auditou a mesma superfície (`sql_escape` duplicando aspas) com 0 critical/0 high.

**Alternatives considered**:
- Repassar a query crua ao `MATCH`: rejeitada (quebra com parênteses/aspas; risco
  de injeção de operador).
- Sanitização por blacklist de caracteres: frágil; preferida a tokenização +
  quoting + binding.

---

## Decision 7 — Cache, frescor e `ETag`/304 (Princípio VI)

**Decision**: `ETag` por recurso derivado de `mtime` do arquivo da base +
`max(ingested_at)` da(s) tabela(s) relevante(s) (ex:
`W/"<mtime_epoch>-<max_ingested_at>"`). `If-None-Match` casando → `304 Not
Modified`. `meta.freshness = { mtime, maxIngestedAt }` em **todo** envelope.
Conexão reaberta por requisição (sem long-lived assumindo imutabilidade).

**Rationale**: a ingestão best-effort reescreve a base por trás; tratar como
imutável exibiria dado obsoleto como atual. `mtime`+`max(ingested_at)` é
suficiente e barato para invalidar. `304` reduz tráfego sem assumir
imutabilidade.

**Alternatives considered**:
- Cache em memória com TTL fixo: arrisca servir dado obsoleto após reescrita;
  rejeitada.
- `Last-Modified` apenas: `mtime` sozinho não captura reescritas que preservam
  mtime; combinamos com `max(ingested_at)`.

---

## Decision 8 — Degradação como estado de 1ª classe (Princípio II)

**Decision**: `db/open.ts` retorna um *resultado* (`{ ok: true, db } | { ok:
false, reason }`) em vez de lançar; rotas mapeiam `ok:false` →
`200 { data: <vazio/null tipado>, meta: { degraded: true, reason } }`. Razões
discriminadas: `db-missing`, `db-corrupt` (`quick_check` ≠ `ok`),
`schema-mismatch` (`schema_version ≠ 2`), `table-empty` (por recurso).

**Rationale**: SC-001 exige 100% das telas respondendo com sucesso sob base
ausente/vazia/corrompida; nenhum `5xx` por condição de dado. `quick_check` na
saúde e na abertura surfaceia corrupção como degradação.

**Alternatives considered**:
- Lançar e capturar em error-handler global mapeando p/ 200: funciona, mas o
  *resultado* explícito é mais auditável e evita 5xx acidental.

---

## Síntese

| Unknown | Status | Decisão |
|---------|--------|---------|
| D1 stack back-end | **Resolvido (clarify)** | Node.js + TypeScript |
| D2 empacotamento | **Resolvido** | Standalone monorepo (gancho p/ `cstk panel serve`) |
| D3 mix de modelos | **Revisado (2026-05-25)** | Exibir mix DERIVADO e rotulado (consistente com Overview/FR-010); endpoints `/metrics/model-mix[-by-stage]`, `meta.approximate=true` |
| D4 formato API | **Resolvido (briefing)** | REST/JSON |
| D5 granularidade séries | **Resolvido** | Por dia + período selecionável |
| Driver SQLite | **Resolvido** | `better-sqlite3` readonly+query_only |
| Framework HTTP | **Resolvido** | Fastify 5 |
| Escaping FTS5 | **Resolvido** | 2 camadas (tokenização aspas + binding `?`) |
| Cache/frescor | **Resolvido** | ETag(mtime+max_ingested_at)/304 |
| Degradação | **Resolvido** | Resultado explícito → 200 + meta.degraded |

**NEEDS CLARIFICATION restantes: 0.**
