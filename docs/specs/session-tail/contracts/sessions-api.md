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
| `scrubMode` | `'cstk+internal'` \| `'internal'` | Qual cadeia de scrub produziu esta resposta (**FR-scrub**) |

`SessionSummaryDTO`: `sessionId` (string), `projectPath` (string\|null),
`projectSlug` (string), `lastActivityAt` (string ISO), `live` (boolean),
`sizeBytes` (number). Definicao normativa em `data-model.md`.

**Scrub obrigatorio tambem nesta rota.** `projectPath` e `projectSlug` derivam
de conteudo de transcript (`.cwd` e nome de diretorio) e passam pela mesma
cadeia de scrub do tail antes de sair do servidor. A cobertura e por **origem
do dado**, nao por rota: qualquer campo de preview/sumario derivado do
transcript que venha a ser adicionado a listagem entra automaticamente na
mesma regra. Ver `plan.md` §Seguranca de Conteudo.

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
| `scrubMode` | `'cstk+internal'` \| `'internal'` | Qual cadeia de scrub produziu esta resposta |

`SessionTailEntryDTO`: `uuid` (string\|null), `type` (string — conjunto
ABERTO, nunca enum), `timestamp` (string\|null), `role` (string\|null), `text`
(string), `textTruncated` (boolean).

**`text` e conteudo UNTRUSTED** (FR-005, Principio V): produzido por um LLM,
possivelmente contendo markup ativo ou texto que se parece com instrucao. O
servidor o entrega como string literal, sem sanitizacao criativa; o front-end
o renderiza via componente de escaping (`TextBlockRaw`), nunca via
`dangerouslySetInnerHTML`.

**`text` passa por scrub de segredos NO SERVIDOR antes de sair** — obrigatorio,
sem caminho alternativo. Esta feature le o `.jsonl` direto do disco e portanto
**nao** herda o scrub da ingestao do cstk; o scrub e proprio e acontece antes do
`wrap()`, nunca no cliente. A cadeia e `secrets-filter.sh scrub` do cstk quando
disponivel, **seguido sempre** de um redactor interno minimo; ausencia do cstk
degrada a qualidade do scrub e nunca o desativa. O scrub roda **antes** do corte
de `textTruncated`, logo o que e truncado ja e o texto redigido e `[REDACTED]`
conta para o teto de bytes. Especificacao normativa: `plan.md`
§Seguranca de Conteudo.

### Response 200 — degradada

| `reason` | Condicao |
|----------|----------|
| `session-not-found` | `sessionId` nao resolve para arquivo sob a raiz |
| `session-rejected` | guard de confinamento rejeitou o caminho |
| `sessions-root-missing` | raiz de sessoes ausente |
| `session-scrub-failed` | a cadeia de scrub nao pode ser concluida. Resposta `200` com `data: null` — **nunca** o texto cru |

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

## Scrub de segredos — resumo normativo

| Aspecto | Regra |
|---------|-------|
| Onde roda | **servidor**, imediatamente antes do `wrap()`; nunca no cliente |
| Cadeia | `secrets-filter.sh scrub` (quando disponivel) → redactor interno (**sempre**) |
| Ausencia do cstk | degrada a **qualidade** (`scrubMode: 'internal'`); jamais desativa o scrub |
| Falha do subprocesso (exit != 0 / timeout) | descarta a saida parcial e aplica o redactor interno sobre a entrada original |
| Campos cobertos | `entries[].text`, `sessions[].projectPath`, `sessions[].projectSlug` |
| Ordem | scrub **antes** do truncamento por bytes |
| Invocacao | sem shell, argumentos fixos, conteudo por **stdin**; caminho do script vem de config do servidor, nunca do cliente |
| Conteudo cru | **em nenhum caminho e em nenhuma condicao de erro** |

---

## Configuracao (variaveis de ambiente)

**[PROPOSTA]**, seguindo o padrao de `apps/server/src/config.ts`
(`CSTK_KNOWLEDGE_DB`, `CSTK_WATCH_INTERVAL_MS`, ...).

| Variavel | Default | Papel |
|----------|---------|-------|
| `CSTK_SESSIONS_ROOT` | `~/.claude/projects` | Raiz confinada de sessoes |
| `CSTK_SESSION_LIVE_WINDOW_MS` | `300000` (5 min) | Janela de liveness (SC-004) |
| `CSTK_SESSIONS_WATCH_INTERVAL_MS` | `5000` | Intervalo do polling do watcher |
| `CSTK_SECRETS_FILTER` | `~/.claude/skills/agente-00c-runtime/scripts/secrets-filter.sh` | Caminho do filtro do cstk usado no passo 1 do scrub. Caminho inexistente ⇒ `scrubMode: 'internal'`, nunca falha |
| `CSTK_SECRETS_FILTER_TIMEOUT_MS` | `2000` | Teto por invocacao do subprocesso; estouro ⇒ descarta a saida parcial e cai no redactor interno |

O caminho da raiz vem **exclusivamente** de configuracao do servidor, nunca do
cliente — mesma regra que a constituicao ja impoe ao caminho do banco.
