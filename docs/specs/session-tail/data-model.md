# Data Model: Session Tail

> **Definicao DUPLA de DTO — regra do repositorio.** Toda entidade abaixo existe
> em **dois** arquivos que MUST ser editados juntos:
>
> | Papel | Arquivo |
> |-------|---------|
> | Interface TypeScript manual | `packages/shared-types/src/entities.ts` |
> | Schema Zod equivalente | `packages/shared-types/src/schemas/entities.ts` |
> | Re-export do tipo | `packages/shared-types/src/index.ts` (`export type { ... } from './entities.js'`) |
> | Re-export do schema | `packages/shared-types/src/index.ts` (`export { ...Schema } from './schemas/entities.js'`) |
> | Teste de paridade | `packages/shared-types/src/__tests__/parity.test.ts` |
>
> Editar apenas um dos dois **passa no `tsc` e quebra em runtime** — o servidor
> emite um campo que o `fetchApi` do front-end rejeita no `.parse()`. As listas
> de campos dos dois arquivos MUST ser identicas, campo a campo.
>
> Convencao de caso: **camelCase** em todo DTO (padrao ja estabelecido —
> `TaskDTO` usa `executionId`, `testsRun`, `touchedFilesCount`). Nao ha camada
> de banco nesta feature, entao nao ha mapeamento snake_case ↔ camelCase a fazer:
> o unico ponto de conversao e do JSON bruto do `.jsonl` (que mistura
> `sessionId` e `session_id`) para o DTO.

> **Veracidade dos campos de origem (Principio VI).** Todo campo marcado
> *Origem: transcript* corresponde a uma chave que foi **de fato observada** em
> `~/.claude/projects/**/*.jsonl` (sonda registrada em `research.md`). Nenhum
> nome de campo foi suposto. Campos marcados *Derivado* sao computados pelo
> servidor e nao existem no arquivo.

---

## Entity: SessionSummaryDTO

Uma sessao do Claude Code descoberta no armazenamento local. E o item da
listagem de FR-002.

| Field | Type | Constraints | Origem | Notes |
|-------|------|-------------|--------|-------|
| `sessionId` | string | NOT NULL, UUID | Transcript (nome do arquivo, confirmado em `.sessionId`) | Identificador unico e chave de roteamento (FR-004) |
| `projectPath` | string \| null | — | Transcript (`.cwd`, primeira ocorrencia) | `null` quando nenhuma linha lida traz `cwd`. **Derivado de transcript ⇒ passa pelo scrub**. Ver Decision 4 |
| `projectSlug` | string | NOT NULL | Nome do diretorio pai | Chave de agrupamento **opaca** — NUNCA revertida para path (transformacao lossy). **Derivado de transcript ⇒ passa pelo scrub** |
| `lastActivityAt` | string | NOT NULL, ISO 8601 | Derivado (`statSync().mtime`) | Sinal de atividade; base do calculo de `live` |
| `live` | boolean | NOT NULL | Derivado | `now - lastActivityAt <= LIVE_WINDOW_MS` (default 5 min, SC-004). **Volatil** — recomputado a cada resposta |
| `sizeBytes` | number | NOT NULL, >= 0 | Derivado (`statSync().size`) | Permite a UI sinalizar transcript grande antes de abrir |

**Campos deliberadamente AUSENTES** (registro explicito para que ninguem os
adicione por suposicao mais tarde):

- `executionId` / vinculo com execucao autonoma — **nao existe join verificado**
  entre `.jsonl` e `executions`. Ver `research.md` Decision 3, com a evidencia de
  que `executions.session` guarda short-name, nao UUID. FR-002 permite a
  ausencia ("quando disponivel").
- `gitBranch` — o campo existe no transcript, mas **varia dentro da mesma
  sessao** (observados `main` e `docs/constitution-2.0.0` no mesmo arquivo);
  expo-lo no sumario apresentaria um valor de lancamento como se fosse o atual.
  Nenhum FR o exige.
- `lineCount` — exigiria varrer o arquivo inteiro por item de listagem,
  contradizendo Decision 8 e SC-001.

### Relationships

- `SessionSummaryDTO` 1:1 `SessionTailDTO` via `sessionId`.
- `SessionSummaryDTO` N:1 projeto via `projectSlug` (agrupamento na UI). O
  vinculo com as entidades da `knowledge.db` (`executions`, `projects`) **nao e
  estabelecido** nesta feature.

### State Transitions

O atributo `live` e derivado do tempo, nao persistido — nao ha maquina de
estados armazenada. A transicao observavel e unidirecional dentro de um ciclo
de refresh:

```
live=true  --(sem escrita por > LIVE_WINDOW_MS)-->  live=false
live=false --(nova escrita no .jsonl)-----------> live=true
```

Consequencia de FR-003: `live=false` **nao bloqueia** a leitura do tail. O
atributo governa apenas a apresentacao na listagem.

---

## Entity: SessionTailEntryDTO

Uma linha util do transcript, ja normalizada. Corresponde a UMA linha `.jsonl`
que foi parseada com sucesso.

| Field | Type | Constraints | Origem | Notes |
|-------|------|-------------|--------|-------|
| `uuid` | string \| null | — | Transcript (`.uuid`) | Chave estavel da entrada; `null` nos tipos de linha que nao a carregam |
| `type` | string | NOT NULL | Transcript (`.type`) | **Conjunto ABERTO** — modelar como `z.string()`, jamais `z.enum()` (ver nota abaixo) |
| `timestamp` | string \| null | ISO 8601 quando presente | Transcript (`.timestamp`) | Nullable: apenas 276 de 400 linhas amostradas o possuiam |
| `role` | string \| null | — | Transcript (`.message.role`) | `'user'` / `'assistant'` observados; `null` quando a linha nao tem `.message` |
| `text` | string | NOT NULL (pode ser `''`) | Derivado de `.message.content` | Achatamento — ver regra abaixo. Conteudo **UNTRUSTED** (FR-005). **Ja redigido**: passou pela cadeia de scrub no servidor, antes do truncamento |
| `textTruncated` | boolean | NOT NULL | Derivado | `true` quando `text` foi cortado pelo teto por entrada (FR-006) |

**Por que `type` e `string` e nao `enum`**: foram observados 17 valores
distintos (`assistant`, `user`, `attachment`, `bridge-session`, `mode`,
`permission-mode`, `last-prompt`, `ai-title`, `atis-latch`, `frame-link`,
`file-history-snapshot`, `system`, `queue-operation`,
`artifact-comment-monitor`, `artifact-autoreact-ledger`, `cost-state`,
`file-history-delta`). O conjunto pertence ao harness do Claude Code, nao a este
projeto, e cresce sem aviso. Um `z.enum()` transformaria "o harness ganhou um
tipo de linha novo" em falha de parse da tela inteira — violacao direta do
Principio II. `z.string()` degrada: a entrada aparece com um `type` que a UI
nao conhece e ainda assim renderiza.

**Regra de achatamento de `text`** (a partir de `.message.content`, cujo tipo e
heterogeneo — observado ora `string`, ora `array`):

| Formato de `.message.content` | Resultado em `text` |
|-------------------------------|---------------------|
| `string` | o proprio valor |
| `array` | concatenacao, por `\n`, do campo `.text` dos itens cujo `.type === 'text'` |
| ausente (linha sem `.message`) | `''` |

Itens de conteudo com `.type` em `thinking`, `tool_use` e `tool_result` **nao**
contribuem para `text` nesta versao: `tool_use` carrega `input` (payload
arbitrariamente grande — o vetor natural de uma linha de megabytes) e
`tool_result` carrega saida bruta de ferramenta. Os quatro tipos de item foram
confirmados no arquivo real (`text`, `thinking`, `tool_result`, `tool_use`); os
itens `text` tem exatamente as chaves `["text","type"]`.

> **SUPERADO na 0.34.0.** O adiamento acima ("nesta versao") foi medido contra
> um transcript real e nao se sustentou: de 356 mensagens num arquivo de 636
> linhas, **324 rendiam texto vazio** (137 `tool_use`, 137 `tool_result`, 48
> `thinking`); somados os 280 registros de sidecar do harness, a tela exibia
> **5% de conteudo util**.
>
> Comportamento vigente: `tool_use` vira entrada com `toolName` e um resumo de
> UMA linha do input (heuristica sobre chaves conhecidas, teto de 240 B
> aplicado DEPOIS do scrub); `tool_result` colapsa num marcador de tamanho e
> seu conteudo **nunca** sai do servidor — o que resolve a preocupacao
> original com payload gigante sem pagar o preco de esconder a chamada;
> `thinking` continua fora, por decisao do operador. Mensagem sem nada a
> exibir e DESCARTADA e contabilizada em `filteredEntries`, nunca renderizada
> como linha vazia. Ver `SessionTailEntryDTO.kind`.

---

## Entity: SessionTailDTO

Payload de resposta de `GET /api/v1/sessions/:sessionId/tail`. Carrega as
entradas **e** a contabilidade que FR-003a e FR-006 exigem expor.

| Field | Type | Constraints | Origem | Notes |
|-------|------|-------------|--------|-------|
| `sessionId` | string | NOT NULL, UUID | Eco do parametro | Confirma ao cliente qual sessao respondeu (FR-004) |
| `entries` | SessionTailEntryDTO[] | NOT NULL | Derivado | Ordem cronologica ascendente (mais antiga primeiro) |
| `requestedLines` | number | NOT NULL, 1..1000 | Derivado (query `lines`) | Valor **apos** clamp — o que foi de fato pedido ao leitor |
| `returnedLines` | number | NOT NULL, >= 0 | Derivado | `entries.length`. Menor que `requestedLines` quando um teto cortou |
| `skippedLines` | number | NOT NULL, >= 0 | Derivado | **FR-003a** — linhas malformadas puladas. Expor a contagem e obrigatorio |
| `truncatedByBytes` | boolean | NOT NULL | Derivado | `true` quando o orcamento de bytes encerrou a selecao antes do limite de linhas (FR-006) |
| `windowTruncated` | boolean | NOT NULL | Derivado | `true` quando o arquivo e maior que a janela de leitura, isto e, existe historico anterior ao devolvido |
| `live` | boolean | NOT NULL | Derivado | Mesma regra do sumario. **Informativo** — nunca gateia esta resposta (FR-003) |
| `lastActivityAt` | string | NOT NULL, ISO 8601 | Derivado (`statSync().mtime`) | Frescor **da sessao**; nao vai em `meta.freshness` (Decision 11) |
| `scrubMode` | `'cstk+internal'` \| `'internal'` | NOT NULL | Derivado | Qual cadeia de scrub produziu a resposta. Modelar como `z.enum([...])` — ao contrario de `type`, este conjunto **e nosso** e fechado |

**Por que `scrubMode` e um campo e nao um detalhe de implementacao**: pelo
Principio III. O operador precisa saber **com que qualidade** o conteudo que ele
esta lendo foi redigido. `'internal'` significa que o filtro do cstk nao estava
disponivel e apenas o redactor minimo rodou — uma resposta legitima, porem menos
protegida. Esconder essa diferenca seria apresentar um scrub parcial como se
fosse o completo. Nao existe valor que signifique "sem scrub": esse estado nao
e alcancavel.

**Por que `skippedLines`, `truncatedByBytes` e `windowTruncated` sao campos e
nao silencio**: os tres distinguem "acabou o historico" de "havia mais, e nao
coube". Omiti-los apresentaria um resultado parcial como completo — a mesma
falha que o Principio III proibe nas metricas, aqui aplicada ao conteudo.

### Relationships

- `SessionTailDTO` 1:N `SessionTailEntryDTO` via composicao (`entries`).
- `SessionTailDTO` 1:1 `SessionSummaryDTO` via `sessionId`.

---

## Entity: SessionsListDTO

Payload de resposta de `GET /api/v1/sessions`.

| Field | Type | Constraints | Origem | Notes |
|-------|------|-------------|--------|-------|
| `sessions` | SessionSummaryDTO[] | NOT NULL | Derivado | Ordenado por `lastActivityAt` desc |
| `total` | number | NOT NULL, >= 0 | Derivado | Total **apos** o filtro `live`; `sessions.length` quando nao ha paginacao |
| `scannedAt` | string | NOT NULL, ISO 8601 | Derivado | Instante do ultimo ciclo do watcher que alimentou o indice |
| `scrubMode` | `'cstk+internal'` \| `'internal'` | NOT NULL | Derivado | Mesma semantica do `SessionTailDTO`; a listagem tambem redige `projectPath` e `projectSlug` |

Array vazio com `total: 0` e o estado **vazio legitimo** (US1 cenario 2 /
SC-003) — nunca erro, nunca degradacao. Diretorio ausente ou ilegivel e
`degraded` no envelope (FR-008), estado distinto do vazio.

---

## Novos literais de `DegradedReason`

`packages/shared-types/src/envelope.ts` expoe `DegradedReason` como union de
literais TS. Esta feature acrescenta:

| Literal | Quando |
|---------|--------|
| `sessions-root-missing` | `~/.claude/projects` nao existe |
| `sessions-root-unreadable` | existe, mas `readdirSync` falha (permissao) |
| `session-not-found` | `:sessionId` nao resolve para arquivo sob a raiz |
| `session-rejected` | o guard de confinamento rejeitou o caminho (symlink/escape) |
| `session-scrub-failed` | a cadeia de scrub nao pode ser concluida; a rota degrada em vez de servir texto cru |

O lado Zod **nao** muda: `MetaSchema.reason` ja e `z.string().nullable()`.
Apenas o union TypeScript em `packages/shared-types/src/envelope.ts` recebe os
**cinco** literais.
