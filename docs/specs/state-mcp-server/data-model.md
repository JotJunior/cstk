# Data Model: state-mcp-server

Escopo: esta feature **nao cria nenhuma tabela nova** no `state.db` e **nao
altera nenhum schema existente**. As tres Key Entities da spec sao ou (a) efemeras
(vivem numa chamada), ou (b) mapeadas para artefatos que ja existem em disco.

Rotulos conforme `research.md`: **[VERIFICADO]** = lido da fonte;
**[PROPOSAL]** = introduzido por esta feature.

---

## Superficie de estado JA existente (nao alterar)

[VERIFICADO — `global/skills/agente-00c-runtime/references/state-db-schema.sql`]

| Tabela | Papel nesta feature | Tool que a alcanca (sempre via helper) |
|--------|--------------------|-----------------------------------------|
| `execution` | escopo de confinamento (FR-008); campo `status` ∈ `em_andamento\|aguardando_humano\|abortada\|concluida` | leitura para validacao de pre-condicao |
| `wave` | onda corrente; `ux_wave_single_open` (unique parcial, `WHERE termination_reason IS NULL`) + trigger `trg_wave_close_once` | `open_wave`, `close_wave` |
| `decision` | Decisao auditavel; colunas `justification_score`, `evidence` | `record_decision` |
| `human_block` | bloqueio humano; muda `execution.status` para `aguardando_humano` | `register_human_block` |
| `task_outcome` | outcome de task; **PK `(execution_id, task_id)`** ⇒ upsert idempotente e propriedade do schema | `record_task` |
| `skill_invocation` | roster de skills/gates da onda; `kind ∈ ('skill','gate')` | `record_skill` |
| `event` | timeline (`event_type`, `timestamp`, `description`) | efeito indireto |
| `migration_run` | **fora de escopo** | nenhuma |

**Invariante herdada**: quando `<state-dir>/state.db` **nao** existe, o backend e
`state.json` [VERIFICADO — `_state-rw-db.sh:42-48`]. As tools sao agnosticas: elas
falam com helpers, e o helper resolve o backend. Nenhuma tool le/escreve o arquivo
de estado diretamente.

---

## Entity: Orchestrator Server Session [PROPOSAL]

Janela de vida do servidor associada a **exatamente uma** execucao autonoma.
Materializada como um arquivo de descritor no proprio state-dir da execucao —
nao em tabela, porque e estado **operacional** (vai embora com o container) e nao
estado **transacional auditavel**.

**Local**: `<state-dir>/mcp-server.json` [PROPOSAL]

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| `session_id` | string | NOT NULL, unico, **>= 128 bits de CSPRNG** | **Token de capacidade** (bearer), nao apenas identificador: e ele que autoriza o roteamento da chamada. Arquivo `chmod 600`. Ver `contracts/mcp-session-lifecycle.md` §SEC-H3 |
| `execution_kind` | enum | `agente-00c` \| `feature-00c` | Qual layout de execucao |
| `short_name` | string \| null | NOT NULL se `feature-00c` | `null` para `agente-00c` |
| `state_dir` | string | NOT NULL, path absoluto | Escopo unico de mutacao (FR-008) |
| `target_project_path` | string | NOT NULL, path absoluto | Raiz do projeto-alvo |
| `container_name` | string \| null | NOT NULL quando `mode=docker` | Nome do container dedicado |
| `mode` | enum | `docker` \| `bash-fallback` | `bash-fallback` = servidor nunca subiu (FR-007) |
| `unavailable_reason` | string \| null | NOT NULL quando `mode=bash-fallback` | Ex.: `docker-absent`, `health-timeout` |
| `started_at` | timestamp | ISO 8601 UTC | |
| `stopped_at` | timestamp \| null | ISO 8601 UTC | Preenchido no encerramento limpo |

### State Transitions

```
(inexistente) --cstk mcp start--> starting --health ok--> active
                                     |                      |
                                     | health timeout       | execucao chega a estado terminal
                                     v                      v  (concluida | abortada)
                              bash-fallback              stopped
```

- `active` persiste **atraves de pausas** entre ondas (`Schedule intent`) —
  decisao de clarify sobre FR-010: a sessao e coextensiva com a **execucao**, nao
  com a onda. Em cada `-resume` o pai apenas **verifica saude**, sem reiniciar.
- `bash-fallback` e um estado **terminal e nao-fatal**: a execucao prossegue pelo
  caminho Bash de hoje, sem intervencao manual (FR-007).

### Relationships

- `Orchestrator Server Session` **1:1** `execution` (via `state_dir`). A
  cardinalidade 1:1 **e** o requisito FR-008/FR-016 — duas execucoes concorrentes
  produzem dois descritores, dois containers, zero compartilhamento.

---

## Entity: MCP Tool Call [PROPOSAL — efemera]

Invocacao de uma tool de mutacao. **Nao e persistida como tal**: existe durante a
chamada e se materializa em disco unicamente como `Tool Invocation Audit Record`
(abaixo) e, quando aceita, como mutacao nas tabelas ja existentes.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| `tool` | enum | 1 das 6 tools (ver `contracts/mcp-tools.md`) | |
| `arguments` | object | validado pelo `inputSchema` **antes** do handler | [VERIFICADO: o SDK valida pre-handler] |
| `session_id` | string | NOT NULL | Amarra a chamada a uma Session (FR-008) |
| `outcome` | enum | `accepted` \| `rejected` | |
| `rejection_reason` | string \| null | NOT NULL quando `rejected` | Motivo acionavel (FR-009) |
| `received_at` | timestamp | ISO 8601 UTC | |

### Ciclo de validacao (ordem obrigatoria)

```
1. schema        (SDK, pre-handler)   -> rejeita tipo/campo faltante/score fora de 0..3
2. pre-condicao  (handler)            -> onda aberta? execucao nao-terminal? (FR-009)
3. delegacao     (helper POSIX)       -> a regra de negocio real (ex.: evidencia >= 20 chars)
4. auditoria     (SEMPRE)             -> registra accepted OU rejected, aconteca o que acontecer
```

O passo 4 roda **inclusive** quando 1, 2 ou 3 rejeitam — e o que satisfaz
SC-003 ("100% das chamadas ... aceitas ou rejeitadas aparecem no historico").

---

## Entity: Tool Invocation Audit Record [PROPOSAL]

Linha JSONL anexada a `<projeto-alvo>/.claude/enforcement-log.jsonl` — **o mesmo
arquivo** dos writers existentes, discriminado por `source` [VERIFICADO: o arquivo
ja e multi-writer, com `"pretooluse-bash-guard"` e `"serve-integrity"`].

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| `source` | string | **literal** `"mcp-state-tool"` | Discriminador do writer [PROPOSAL] |
| `timestamp` | string | ISO 8601 UTC (`date -u +%Y-%m-%dT%H:%M:%SZ`) | Mesmo formato dos writers atuais [VERIFICADO] |
| `outcome` | enum | `accepted` \| `rejected` | |
| `tool` | string | NOT NULL | Nome da tool chamada |
| `session_id` | string | NOT NULL | Sessao/execucao de origem (exigido por FR-005) |
| `detected_execution` | string \| null | `agente-00c` ou `feature-00c:<short-name>` | Nomenclatura herdada do hook [VERIFICADO] |
| `detected_execution_path` | string \| null | path do state-dir | Idem |
| `reason` | string \| null | NOT NULL quando `rejected` | Motivo acionavel |
| `stage` | enum \| null | `schema` \| `precondition` \| `delegation` | Onde a rejeicao ocorreu |
| `arguments_digest` | string | **scrub → truncate**, nesta ordem | Ver regra abaixo |

### Regra de sanitizacao (ordem e obrigatoria)

[VERIFICADO — precedente em `pretooluse-bash-guard.sh:150-163`]: o hook aplica
`secrets-filter.sh scrub` **antes** de `cut -c1-500`. A ordem importa: truncar
primeiro poderia cortar um segredo ao meio e faze-lo escapar do scrub.

```
arguments_digest = truncate( scrub( json(arguments) ), 500 )
```

Campos **nao** sanitizados (por serem vocabulario fechado, sem texto livre):
`source`, `timestamp`, `outcome`, `tool`, `stage`.

### Relationships

- `Tool Invocation Audit Record` **N:1** `Orchestrator Server Session` via
  `session_id`.
- Sobrevive ao encerramento do servidor (arquivo no projeto-alvo, nao no
  container) — exigencia literal de US3 cenario 1.

---

## O que esta feature explicitamente NAO modela

| Item | Por que fora |
|------|--------------|
| Tabelas novas no `state.db` | As 6 tools mutam entidades ja existentes via helpers (research.md Decision 1) |
| Qualquer escrita em `knowledge.db` | **FR-013**: permanece unico e read-only; o container **nao o monta** (research.md Decision 5) |
| Lock proprio do servidor | **research.md Decision 4**: o lock do command pai ja envolve a onda; `state-lock.sh` e nao-reentrante |
| Estado de sessao no transporte | A revisao 2026-07-28 do MCP e stateless (`Mcp-Session-Id` removido) — a sessao e resolvida por chamada, do disco |
