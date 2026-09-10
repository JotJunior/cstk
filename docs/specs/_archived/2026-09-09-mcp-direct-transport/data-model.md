# Data Model: Transporte MCP direto

**Feature**: `mcp-direct-transport` | **Date**: 2026-08-16 | **Phase**: 1

## Convencao de veracidade deste documento

Cada campo/estrutura abaixo e marcado com uma destas etiquetas:

- **[REAL]** — existe hoje no codigo, com path e linha citados. Extraido
  da fonte, nao suposto.
- **[PROPOSTA — a validar na implementacao]** — desenho novo desta
  feature. Ainda **nao existe**; nomes e valores sao proposta e MUST ser
  confirmados/ajustados ao implementar (Constitution VI).

Nenhum campo neste documento foi afirmado como real sem citacao de origem.

---

## Entity: Descritor de Sessao MCP (`mcp-server.json`) [REAL]

Arquivo por execucao, gravado em `<state-dir>/mcp-server.json` com
permissao `600`. E a **fonte de verdade** do vinculo execucao <-> sessao
MCP e sobrevive ao processo do servidor (Decision 10).

**Fonte**: `cli/lib/mcp.sh:457-468` (`_mcp_write_descriptor`, bloco `jq -n`),
`cli/lib/mcp.sh:469` (`chmod 600`).

| Campo | Tipo | Nullable | Origem/Semantica |
|-------|------|----------|------------------|
| `session_id` | string | nao | Token de capacidade CSPRNG (>= 128 bits). Gerado por `cstk mcp start` |
| `execution_kind` | string | nao | Tipo da execucao autonoma (`agente-00c` / `feature-00c`), resolvido por `_mcp_resolve_execution_kind` (`mcp.sh:388`) |
| `short_name` | string | **sim** (`-` vira `null`) | Nome curto da feature; `null` para execucao `agente-00c` |
| `state_dir` | string | nao | Path absoluto do state-dir da execucao |
| `target_project_path` | string | nao | Raiz do projeto-alvo |
| `container_name` | string | **sim** | Nome do container Docker. **Ver mudanca abaixo** |
| `mode` | string | nao | Modo de transporte. **Ver mudanca abaixo** |
| `unavailable_reason` | string | **sim** | Motivo quando o transporte nao pode ser preparado |
| `started_at` | string (ISO 8601 UTC) | nao | `date -u +%Y-%m-%dT%H:%M:%SZ` (`mcp.sh:572`) |
| `stopped_at` | string (ISO 8601 UTC) | **sim** | **Campo que autoriza/desautoriza**: nao-nulo ⇒ sessao terminal ⇒ nunca roteia |

### Valores observados de `mode` [REAL]

| Valor | Quando | Fonte |
|-------|--------|-------|
| `docker` | container subiu e passou no healthcheck | `mcp.sh:651`, `mcp.sh:681` |
| `bash-fallback` | qualquer falha do caminho Docker (preflight, fonte ausente, build, start, health-timeout) | `mcp.sh:583`, `:601`, `:615`, `:656`, `:671` |

### Mudancas propostas nesta feature

| Campo | Mudanca | Etiqueta |
|-------|---------|----------|
| `mode` | ganha o valor `direct` para toda sessao criada apos o cutover; `docker` deixa de ser gravado por sessoes novas (FR-014 trata as legadas) | **[VALIDADO — task 3.2]** — `mcp.sh::_mcp_cmd_start` grava `direct` literal |
| `container_name` | passa a ser `null` em toda sessao nova (nao ha container) | **[VALIDADO — task 3.2]** — decorre de FR-005/FR-009; o campo permanece no schema por retro-compatibilidade com descritores legados que `gc`/`status --live`/`stop` ainda precisam ler (FR-015) |
| demais 8 campos | **sem mudanca** | [REAL] |

**Invariante preservado**: nenhum campo e removido do schema. Descritores
legados (`mode=docker`, `container_name` preenchido) continuam **legiveis** —
requisito duro de FR-014 (detectar+avisar+sobrescrever) e FR-015 (`gc`
recolhe containers remanescentes).

### State transitions [REAL]

```
(inexistente) --cstk mcp start--> ATIVA (stopped_at = null)
ATIVA --cstk mcp start (de novo)--> ATIVA          (FR-010: idempotente, reusa)
ATIVA --cstk mcp stop--> TERMINAL (stopped_at != null)
TERMINAL --cstk mcp stop (de novo)--> TERMINAL     (FR-008: idempotente)
TERMINAL --qualquer chamada de tool--> REJEITADA   (fail-closed, FR-003)
```

O guard de autorizacao le `stopped_at` **do disco a cada chamada** —
`mcp-session.sh:130` `[ -z $_stopped ] || return 1   # execucao ja terminal
— nunca roteia (fail-closed)`. E por isso que a Decision 2 do research
**proibe** cachear o descritor: qualquer TTL abriria janela em que uma
sessao TERMINAL ainda autorizaria mutacao.

---

## Entity: Token de capacidade [REAL]

Nao e uma estrutura separada em disco — e o campo `session_id` do descritor,
com semantica de **credencial**.

| Propriedade | Valor | Fonte |
|-------------|-------|-------|
| Geracao | CSPRNG via `/dev/urandom`, com erro explicito se indisponivel | `mcp.sh:372-376` |
| Apresentacao | argumento `session_id` de **cada** chamada de tool | `record_decision.ts:55`, `open_wave.ts:31`, `get_status.ts:38`, `close_wave.ts:105` |
| Validacao | `matchesResolvedSession(session, input.session_id)` | `resolve.ts:169`; uso em `record_decision.ts:143`, `open_wave.ts:68`, `get_status.ts:98`, `close_wave.ts:246` |
| Rejeicao | `"session_id nao corresponde ao token de capacidade desta sessao"` | mesmas linhas acima (+3 de cada) |

### Superficie de exposicao

| Canal | Hoje [REAL] | Apos a feature |
|-------|-------------|----------------|
| Nome de container Docker (sufixo) | **expoe** o token a `docker ps` | **eliminado** — nao ha container (FR-009 / US3) |
| `.mcp.json` do projeto | **nao expoe** — o arquivo nao tem bloco `env` | inalterado; injetar `env` la foi rejeitado (research Decision 8) |
| Prompt de spawn do orquestrador | injeta o token | **generalizado**: deixa de ser condicionado a `mode == "docker"` (FR-013) |
| Descritor `mcp-server.json` | contem o token, `chmod 600` | inalterado |

---

## Entity: Chamada de tool [REAL]

Unidade de interacao. Aceita/rejeitada **independentemente**, com motivo
explicito.

| Campo | Tipo | Origem |
|-------|------|--------|
| `session_id` | string, `min(1)` | schema Zod de cada tool — ex.: `record_decision.ts:55` `z.string().min(1, "session_id obrigatorio")` |
| (demais args) | por tool | schemas proprios em `src/tools/*.ts` |

**Envelope de resposta** [REAL] — `index.ts:100-111`:

| Campo | Semantica |
|-------|-----------|
| `outcome` | `"accepted"` \| `"rejected"` |
| `reason` | motivo textual quando `rejected` |
| `stage` / `result` | payload da operacao |
| `isError` | `response.outcome === "rejected"` |

**Nenhum contrato de tool muda nesta feature.** As 7 tools ja recebem e
validam `session_id`; o que muda e **quando** a sessao comparada e
resolvida (boot -> por chamada). Ver `contracts/mcp-tools-session-resolution.md`.

---

## Entity: Cache de resolucao `token -> state_dir` [PROPOSTA — a validar na implementacao]

Estrutura **em memoria**, no processo do servidor. Nao persiste em disco,
nao sobrevive ao processo.

| Propriedade | Valor proposto |
|-------------|----------------|
| Chave | `session_id` (token apresentado na chamada) |
| Valor | `state_dir` resolvido na primeira chamada daquele token |
| Escopo | processo (morre com ele — Decision 10) |
| TTL | **nenhum, deliberadamente** |
| Invalidacao | nao aplicavel — o par `token -> state_dir` e imutavel por construcao |

**O que este cache NAO cacheia** (invariante de seguranca, Decision 2):

> A **autorizacao** nunca e cacheada. A cada chamada, mesmo com hit de
> cache, o servidor revalida via `mcp-session.sh resolve --state-dir
> <cached>`, que rele `session_id` **e** `stopped_at` do descritor em
> disco. Um token cujo `stopped_at` passou a ser nao-nulo e rejeitado na
> chamada seguinte, sem janela.

Efeito medido em custo: reduz de **O(N execucoes)** descritores lidos
(tree-walk com glob + 2 `jq` por descritor) para **1** descritor por
chamada.

**Caso de miss**: token desconhecido ⇒ tree-walk normal via
`CSTK_MCP_PROJECT_PATH` ⇒ popula o cache ⇒ segue o caminho normal. Miss
nunca falha a chamada por si so.

---

## Entity: Cache de build do servidor (`dist/`) [PROPOSTA — a validar na implementacao]

Artefato de build local, resultado do build lazy (Decision 5).

| Propriedade | Valor proposto | Base |
|-------------|----------------|------|
| Localizacao | `~/.claude/mcp/state-server/` (mesmo dir ja usado pelo catalogo) | `cli/lib/install.sh:769-784` copia `catalog/mcp/state-server` para la [REAL] |
| Conteudo esperado apos build | `node_modules/` + `dist/` | ausentes hoje na instalacao [REAL, dec-025] |
| Entrypoint | `dist/src/index.js` | `package.json` `"main": "dist/src/index.js"` [REAL] |
| Comando de build | `npm run build` (`tsc -p tsconfig.json`) | `package.json` `"scripts"` [REAL] |
| Preflight de Node | major suportado + registro do major que buildou | herda o padrao de `cli/lib/serve.sh:127` `_SERVE_SUPPORTED_NODE_MAJORS` e `:160` `_serve_node_preflight` [REAL] |
| Estado quando ausente | launcher **degrada para idle**, nunca falha | exigencia de desenho da Decision 5 |

**Por que nao vem pronto no tarball** [REAL]: `mcp/state-server/.gitignore`
lista `node_modules/` (linha 1) e `dist/` (linha 2);
`scripts/build-release.sh:260-263` copia para o tarball **apenas** `src/`
mais `package.json`, `package-lock.json`, `tsconfig.json`, `.dockerignore`.
O tarball ja distribui **fonte, nunca build**.

---

## Relacionamentos

```
Execucao 00c (state-dir)
      │ 1:1
      ▼
Descritor de Sessao MCP (mcp-server.json)  ── contem ──▶ Token de capacidade
      │                                                          │
      │ N sessoes podem coexistir no mesmo projeto                │ apresentado em
      │ (agente-00c + N feature-00c)                              ▼
      │                                              Chamada de tool (session_id)
      │                                                          │
      └──────────── resolvida por chamada, nunca por             │
                    "a sessao ativa mais provavel" (FR-011) ◀────┘

Processo do servidor MCP (1 por sessao do harness)
      │ atende N sessoes MCP  ◀── mudanca desta feature (antes: 1:1)
      └── mantem: cache token->state_dir [PROPOSTA] + contador maxToolCalls [REAL]
```

**Mudanca de cardinalidade** — o coracao desta feature:

| Relacao | Antes [REAL] | Depois |
|---------|--------------|--------|
| Processo do servidor : Sessao MCP | **1 : 1** (um container por execucao) | **1 : N** |
| Processo do servidor : Sessao do harness | N/A (independente) | **1 : 1** (FR-012) |
| Sessao MCP : Execucao 00c | 1 : 1 | **inalterado** |

A consequencia documentada em research Decision 1: `maxToolCalls`
(`index.ts:132`) continua sendo contador **por processo**, mas seu
comentario justificador (`index.ts:128-131`, "sessao == processo, um
container por execucao") **deixa de ser verdadeiro** e MUST ser atualizado
junto com o codigo — caso contrario o comentario passa a mentir sobre o
proprio invariante.
