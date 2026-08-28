# Contract: Ingest Watcher (job de segundo plano + delegação a `cstk`)

**Feature**: `state-watchers-and-docs` | **Phase**: 1 | **Date**: 2026-07-15

> **[PROPOSTA — a validar na implementação]**: o watcher é **net-new** (não há
> `child_process` no projeto hoje — verificado). Este contrato define o comportamento
> do job de fundo e a **interface de delegação** ao `cstk` (Constitution IV Opção B).
> O único comando `cstk` afirmado como real é o de ingestão canônica
> `cstk recall --ingest --state-dir DIR` — verificado em `cstk recall --help`
> (cstk v5.18.0). O que é **[PROPOSTA]** é o call-site do subprocesso no server.

## 1. Job de segundo plano (FR-001, FR-004, FR-013)

**Ciclo de vida**: iniciado em `main()` (`apps/server/src/index.ts`); timer recorrente
`WATCH_INTERVAL_MS` (default proposto `10_000`). Parado no shutdown do server.

**Tick** (pseudo-fluxo, sem SQL de mutação — Principio I):

```
1. openDb(config.dbPath, supportedSchemaVersions)   # read-only, por tick (Principio VI)
   └─ !ok ⇒ log degradado; encerra tick (sem crash — Principio II)
2. SELECT execuções WHERE status ∈ {em_andamento, aguardando_humano}   # FR-003
   └─ vazio ⇒ tick ocioso, NENHUM subprocesso disparado   # FR-013 / AC US1-3
3. db.close()
4. para cada execução ativa:
   a. path = resolveProjectPath(project)             # Decision 1
      └─ null ⇒ degradado (não observável, FR-008/FR-012); pula
   b. stateDir = derivar(path, feature, session)     # Decision 3
      └─ não existe no FS ⇒ degradado (FR-012); pula
   c. sig = assinatura(stateDir/state.json)           # mtime|sha256 (Decision 4)
      └─ sig == cache[stateDir] ⇒ pula (idempotência, FR-014)
   d. delega ingestão canônica (§2); atualiza cache[stateDir] = sig
```

**Invariantes**:
- Nenhum caminho escreve na knowledge.db nem toca `state.json` (Principio I).
- Nunca roda `cstk recall --reindex` (dono externo — FR-004, Principio IV).
- Conexão de DB é por-tick (Principio VI — sem conexão de longa duração).
- Ocioso quando não há execução ativa (FR-013).

## 2. Interface de delegação a `cstk` (subprocesso seguro)

**Comando canônico** (REAL — verificado em `cstk recall --help`, cstk v5.18.0:
"MODO INGESTAO (--ingest): --state-dir DIR"):

```
cstk recall --ingest --state-dir <stateDir>
```

**Regras de segurança** (constituição §Padrões de Segurança "Subprocesso seguro" +
Padrões de Segurança e Qualidade):

| Regra | Como |
|-------|------|
| Sem shell-string interpolada | `execFile('cstk', ['recall','--ingest','--state-dir', stateDir])` — args como **array**, nunca `exec('cstk … ' + var)` |
| **Binário resolvido** (gate owasp medium — anti PATH hijack) | resolver `cstk` a caminho absoluto verificado / pinar via config; `env`/`cwd` mínimos ao subprocesso |
| Argumentos validados + confinados | `stateDir` derivado e confinado (Decision 3/7). **`feature`/`session` vêm da knowledge.db (UNTRUSTED, Principio V)**: aplicar canonicalização + regex anti-traversal (`/^[^/\\.<>]+$/`) + confinamento ANTES de montar o path (gate owasp medium), não só existência |
| Timeout explícito | opção `{ timeout: WATCH_SUBPROCESS_TIMEOUT_MS }` [PROPOSTA] |
| Captura de stderr/stdout | logados; falha ⇒ degradado (FR-012), não crash |
| Idempotente | `cstk recall --ingest` é upsert por chave natural (seguro re-disparar) |
| **Concorrência limitada + backoff** (gate owasp medium — anti DoS/loop) | cap de subprocessos `cstk` concorrentes por tick; backoff em falha persistente [PROPOSTA] |

**Resultado**:
- Exit 0 ⇒ ingestão ok; próximo polling do cliente (10s) verá o dado fresco.
- Exit ≠ 0 / timeout ⇒ log + estado degradado sinalizado; o tick seguinte re-tenta
  com **backoff** (a assinatura ainda difere do cache pois não avançamos em falha)
  **[PROPOSTA]** (política exata de retry a fixar — evitar loop apertado).

## 3. Superfície observável do watcher (opcional)

US1 é servida pelos endpoints `GET /executions` e `GET /executions/:execucaoId`
**já existentes** (`apps/server/src/routes/executions.ts`), que passam a refletir
dado mais fresco porque a knowledge.db é mantida atualizada pelo watcher. **Nenhum
endpoint novo é obrigatório para US1.**

**[PROPOSTA — opcional]** Para sinalizar degradação do mecanismo (FR-012) de forma
observável na UI, pode-se: (a) adicionar um campo ao `meta` do envelope, ou (b) expor
`GET /api/v1/watchers` com o estado por execução observada (última ingestão, último
erro). Decisão de escopo a fechar em `/create-tasks`; não é bloqueante para o núcleo
da feature.

## 4. Invariantes de contrato (gate)

1. O painel NUNCA emite SQL de mutação; toda escrita na knowledge.db é feita pelo
   `cstk` via subprocesso (Principio I + IV Opção B).
2. `cstk recall --reindex` NUNCA é invocado pelo painel (FR-004).
3. `state.json` é lido (assinatura) mas NUNCA escrito (Principio I — Read-Only sobre
   o state alheio).
4. Subprocesso sempre com args em array + timeout + captura de stderr (sem shell).
5. Watcher ocioso sem execução ativa (FR-013); dispara só em mudança de assinatura
   (FR-014).
