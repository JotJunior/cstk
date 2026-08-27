# Contracts: Session Tail — API

> **[PROPOSTA — a validar na implementacao]**
> Os dois endpoints abaixo **ainda nao existem** no repositorio. Este documento
> os PROJETA; ele nao descreve uma API observada. A distincao importa: o envelope
> (`data` + `meta`) e os helpers `wrap`/`wrapDegraded` sao **reais e verificados**
> em `apps/server/src/lib/envelope.ts`; a forma de `data` destes dois recursos e
> proposta e so vira fato quando o cenario de roundtrip do `quickstart.md`
> confirmar o payload real.

**Auth**: nenhuma (o painel roda em `localhost`, sem autenticacao real — secao
"Padroes de Seguranca e Qualidade" da constituicao).
**Metodo**: exclusivamente `GET`. Nenhum verbo nao-`GET` e introduzido — o
Principio I so admite excecao sob `/api/v1/bridge/*`, que esta feature nao usa.
**Headers de resposta**: `Content-Type: application/json; charset=utf-8`
(aplicado pelo hook `onSend` do escopo `/api/v1` em `apps/server/src/index.ts`).

## Envelope comum (real, verificado)

Toda resposta, inclusive degradada, tem esta forma:

```jsonc
{
  "data": { /* ...ou null quando degraded=true... */ },
  "meta": {
    "degraded": false,
    "reason": null,
    "freshness": { "mtime": "", "maxIngestedAt": "" },
    "schemaVersion": "2"
  }
}
```

`freshness` vem vazio e `schemaVersion` vem no fallback `"2"` porque estas rotas
**nao abrem a `knowledge.db`** — sao produzidas por `wrap(data, opts,
config.dbPath, null)`, o mesmo caminho que toda resposta degradada do painel ja
usa hoje. Nao e omissao: e a ausencia honesta de um snapshot de corpus por tras
destas rotas. O frescor relevante ao operador viaja no dado
(`lastActivityAt`) — ver `research.md` Decision 11.

---

## GET /api/v1/sessions

Lista as sessoes do Claude Code descobertas no armazenamento local (FR-001,
FR-002).

### Request

| Param | In | Type | Required | Default | Validation |
|-------|-----|------|----------|---------|------------|
| `live` | query | boolean | nao | `true` | `'true'` \| `'false'`. `true` devolve apenas sessoes dentro da janela de liveness (FR-007) |
| `limit` | query | number | nao | `100` | inteiro 1..500; clamp silencioso fora da faixa |

Validacao por Zod com `safeParse` sobre `request.query`, seguindo o padrao de
`apps/server/src/routes/tasks.ts`. Query invalida **nao** produz `4xx` de dado:
cai no clamp/default (Principio II).

### Response 200 — `data`

| Field | Type | Description |
|-------|------|-------------|
| `sessions` | `SessionSummaryDTO[]` | Ordenado por `lastActivityAt` desc |
| `total` | number | Total apos o filtro `live` |
| `scannedAt` | string (ISO 8601) | Instante do ciclo do watcher que alimentou o indice |

`SessionSummaryDTO`: `sessionId` (string), `projectPath` (string\|null),
`projectSlug` (string), `lastActivityAt` (string ISO), `live` (boolean),
`sizeBytes` (number). Definicao normativa em `data-model.md`.

### Response 200 — degradada

`data: null`, `meta.degraded: true`, `meta.reason` em:

| `reason` | Condicao |
|----------|----------|
| `sessions-root-missing` | `~/.claude/projects` nao existe |
| `sessions-root-unreadable` | existe mas `readdirSync` falha (permissao) |

### Nao ha respostas de erro

| Status | Quando |
|--------|--------|
| `4xx` | **nunca** por condicao de dado |
| `5xx` | **nunca** por condicao de dado (FR-008, Principio II) |

Diretorio existente e vazio **nao** e degradacao: e
`{ sessions: [], total: 0 }` com `degraded: false` (US1 cenario 2, SC-003).

---

## GET /api/v1/sessions/:sessionId/tail

Devolve a porcao mais recente do transcript de uma sessao (FR-003, FR-006).

### Request

| Param | In | Type | Required | Default | Validation |
|-------|-----|------|----------|---------|------------|
| `sessionId` | path | string | sim | — | UUID; usado para resolver `<raiz>/<slug>/<sessionId>.jsonl`. **Nunca** um `executionId` (FR-004) |
| `lines` | query | number | nao | `200` | inteiro 1..1000; clamp silencioso |

**Servido independente de liveness** (FR-003): uma sessao com `live: false`
responde `200` com conteudo normalmente. O unico gate e o `sessionId` resolver
para um arquivo existente **sob a raiz confinada**.

**Guard de path (obrigatorio)**: o `sessionId` e conteudo de cliente. Antes de
qualquer leitura, o caminho resolvido passa por `realpathSync` e MUST permanecer
sob a raiz de sessoes; qualquer escape (`..`, symlink apontando para fora)
resulta em `session-rejected`. Ver `research.md` Decision 5 — este guard e novo e
proprio, e nao afrouxa `validateProjectRootPath`.

### Response 200 — `data`

| Field | Type | Description |
|-------|------|-------------|
| `sessionId` | string | Eco do parametro |
| `entries` | `SessionTailEntryDTO[]` | Ordem cronologica ascendente |
| `requestedLines` | number | Valor apos clamp |
| `returnedLines` | number | `entries.length` |
| `skippedLines` | number | Linhas malformadas puladas (**FR-003a**) |
| `truncatedByBytes` | boolean | Orcamento de bytes encerrou a selecao (**FR-006**) |
| `windowTruncated` | boolean | Existe historico anterior ao devolvido |
| `live` | boolean | Informativo; nao gateia a resposta |
| `lastActivityAt` | string (ISO 8601) | `mtime` do arquivo |

`SessionTailEntryDTO`: `uuid` (string\|null), `type` (string — conjunto
ABERTO, nunca enum), `timestamp` (string\|null), `role` (string\|null), `text`
(string), `textTruncated` (boolean).

**`text` e conteudo UNTRUSTED** (FR-005, Principio V): produzido por um LLM,
possivelmente contendo markup ativo ou texto que se parece com instrucao. O
servidor o entrega como string literal, sem sanitizacao criativa; o front-end
o renderiza via componente de escaping (`TextBlockRaw`), nunca via
`dangerouslySetInnerHTML`.

### Response 200 — degradada

| `reason` | Condicao |
|----------|----------|
| `session-not-found` | `sessionId` nao resolve para arquivo sob a raiz |
| `session-rejected` | guard de confinamento rejeitou o caminho |
| `sessions-root-missing` | raiz de sessoes ausente |

`session-not-found` responde **`200` com `degraded: true`**, nao `404`. Motivo:
o Principio II classifica ausencia de dado como estado de primeira classe, e a
constituicao exige que toda rota fora de `/api/v1/bridge/*` responda `200` com
sinal de degradacao em condicao de dado. Uma sessao pode desaparecer entre a
listagem e o clique — cenario normal, nao erro.

### Nao ha respostas de erro

| Status | Quando |
|--------|--------|
| `4xx` / `5xx` | **nunca** por condicao de dado |

---

## Contrato do watcher (interno, nao HTTP)

**[PROPOSTA — a validar na implementacao]**. Espelha o padrao real de
`apps/server/src/watchers/ingest-watcher.ts`, em instancia **separada** (FR-011).

| Simbolo | Assinatura proposta | Papel |
|---------|--------------------|-------|
| `startSessionsWatcher` | `(opts: StartSessionsWatcherOptions) => SessionsWatcherHandle` | Factory; inicia o polling |
| `SessionsWatcherHandle` | `{ stop: () => void }` | Encerramento no `onClose` do Fastify |
| `runSessionsWatcherTick` | `(opts) => Promise<SessionsWatcherTickResult>` | Unidade de trabalho, exportada para teste direto |
| `getSessionsIndex` | `() => SessionSummaryDTO[]` | Leitura do indice em memoria pelas rotas |
| `resetSessionsIndexForTests` | `() => void` | Helper de teste, espelhando `resetWatcherCacheForTests` |

Invariantes MUST: o timer e `.unref()`'d (nao segura o processo); um tick nunca
lanca (diretorio ausente vira indice vazio + flag de degradacao); a instancia e
independente da do `ingest-watcher` — falha de uma nao afeta a outra.

## Configuracao (variaveis de ambiente)

**[PROPOSTA]**, seguindo o padrao de `apps/server/src/config.ts`
(`CSTK_KNOWLEDGE_DB`, `CSTK_WATCH_INTERVAL_MS`, ...).

| Variavel | Default | Papel |
|----------|---------|-------|
| `CSTK_SESSIONS_ROOT` | `~/.claude/projects` | Raiz confinada de sessoes |
| `CSTK_SESSION_LIVE_WINDOW_MS` | `300000` (5 min) | Janela de liveness (SC-004) |
| `CSTK_SESSIONS_WATCH_INTERVAL_MS` | `5000` | Intervalo do polling do watcher |

O caminho da raiz vem **exclusivamente** de configuracao do servidor, nunca do
cliente — mesma regra que a constituicao ja impoe ao caminho do banco.
