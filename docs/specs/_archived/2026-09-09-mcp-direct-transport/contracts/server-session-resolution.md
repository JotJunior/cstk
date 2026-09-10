# Contrato: Servidor MCP + Launcher (resolucao por chamada)

**Feature**: `mcp-direct-transport` | **Phase**: 1 | **Date**: 2026-08-16

Cobre FR-001, FR-002, FR-003, FR-004, FR-005, FR-011, FR-012.

## Etiquetas

- **[REAL]** — comportamento vigente, com fonte citada.
- **[PROPOSTA — a validar na implementacao]** — desenho novo. Nomes de
  simbolos, mensagens e codigos sao proposta; MUST ser confirmados ao
  implementar (Constitution VI).

---

## 1. Bootstrap do servidor

### 1.1 Comportamento atual [REAL]

```
bootstrap(env)
  ├─ token       = env.MCP_SESSION_TOKEN ?? ""        (index.ts:117)
  ├─ projectPath = env.CSTK_MCP_PROJECT_PATH ?? ""    (index.ts:118)
  ├─ session     = await resolveActiveSession(...)    (index.ts:124)  ◀── BLOQUEIA
  ├─ server      = new McpServer(...)                 (index.ts:126)
  └─ server.registerTool(...) x7                      (index.ts:152+)
```

Se `resolveActiveSession` lanca `SessionMismatchError`, `main()` escreve em
stderr e sai com `exitCode = 1` (`index.ts:275-279`) — **nenhuma tool e
registrada**. O comentario `index.ts:120-123` declara a escolha:
*"Fail-closed (SEC-H3): sem sessao resolvida, o servidor nao registra
NENHUMA tool de mutacao."*

**Este e o mecanismo exato do sintoma da US1**: sem token, sem sessao; sem
sessao, zero tools.

### 1.2 Comportamento contratado [PROPOSTA — a validar na implementacao]

```
bootstrap(env)
  ├─ maxToolCalls = parseMaxToolCalls(env.MCP_MAX_TOOL_CALLS)   [inalterado]
  ├─ scriptsDir   = resolveScriptsDir(env)                      [inalterado]
  ├─ server       = new McpServer(...)
  └─ server.registerTool(...) x7        ◀── SEM resolver sessao antes
```

| Regra | Requisito |
|-------|-----------|
| C-1 | `bootstrap()` MUST registrar **todas** as 7 tools independentemente da existencia de token (FR-001) |
| C-2 | `bootstrap()` MUST NOT chamar `resolveActiveSession` (FR-002) |
| C-3 | Ausencia de `MCP_SESSION_TOKEN` MUST NOT impedir o processo de subir nem de conectar o transporte (FR-004) |
| C-4 | O transporte permanece `StdioServerTransport` (`index.ts:283`) — **inalterado** |

**Invariante de nao-regressao**: a remocao do fail-closed do *boot* NAO
relaxa o fail-closed da *chamada*. Ele apenas **muda de lugar** — de uma
vez no startup para toda chamada (secao 2). Disponibilidade de tool nunca
implicou e continua nao implicando permissao de mutacao (Acceptance
Scenario 2 da US1).

---

## 2. Resolucao por chamada

### 2.1 Fluxo contratado [PROPOSTA — a validar na implementacao]

Para **cada** invocacao de tool, antes de qualquer mutacao:

```
handler(input)
  ├─ 1. limite:   checkCallLimit()                    [REAL, inalterado]
  ├─ 2. token:    input.session_id                    [REAL, ja existe]
  ├─ 3. cache:    stateDir = cache.get(input.session_id)      [PROPOSTA]
  ├─ 4. resolve:  session = resolveSessionForCall(...)        [PROPOSTA]
  │        ├─ hit  → mcp-session.sh resolve --state-dir <cached>   (modo direto)
  │        └─ miss → mcp-session.sh resolve --project-path <PP>    (tree-walk)
  │                  └─ sucesso ⇒ cache.set(token, session.stateDir)
  ├─ 5. guard:    matchesResolvedSession(session, input.session_id)  [REAL]
  └─ 6. delega ao helper POSIX com session.stateDir              [REAL]
```

Os passos 1, 2, 5 e 6 **ja existem**; 3 e 4 sao novos.

### 2.2 Regras de autorizacao

| Regra | Requisito | Referencia |
|-------|-----------|------------|
| A-1 | `session_id` ausente/vazio MUST ser rejeitado pelo schema Zod antes de qualquer I/O | [REAL] `z.string().min(1, "session_id obrigatorio")` |
| A-2 | `session_id` que nao resolve para nenhuma sessao MUST ser rejeitado com motivo explicito | [REAL] `SESSION_MISMATCH` |
| A-3 | `session_id` de execucao com `stopped_at` nao-nulo MUST ser rejeitado | [REAL] `mcp-session.sh:~130` (proxy do descritor) |
| A-3.1 | `session_id` de execucao cujo status REAL (`.execution.status` via `state-rw.sh get`, backend-agnostico) NAO esteja em `{em_andamento, aguardando_humano}` MUST ser rejeitado, MESMO que o proxy A-3 (`stopped_at`) ainda diga nulo | [REAL] `mcp-session.sh::_ms_execution_active`, dec-060/dec-061 — corrige gap: `stopped_at` so e gravado por `cstk mcp stop`, chamado em best-effort (`\|\| :`) pelos commands pai; se nunca rodar, A-3 sozinho nunca dispara |
| A-3.2 | Falha ao LER o status real (self-dir irresolvivel, `state-rw.sh` ausente, state ausente/corrompido, `jq`/`sqlite3` indisponivel) MUST ser tratada como rejeicao, nunca como "ativa" | [REAL] `_ms_execution_active` retorna 1 em qualquer falha de leitura (fail-closed) |
| A-4 | A resolucao MUST usar **exclusivamente** o `session_id` da propria chamada, nunca "a sessao ativa mais provavel" (FR-011) | [REAL] preservado |
| A-5 | Hit de cache MUST revalidar via modo direto — **nunca** autorizar so pelo cache | **[PROPOSTA]** research Decision 2 |
| A-6 | Rejeicao MUST NOT mutar estado algum | [REAL] guard precede a delegacao |

**Mensagem de rejeicao** [REAL, preservada literalmente]:
`"session_id nao corresponde ao token de capacidade desta sessao"`.

> **A-3 vs A-3.1** (dec-060/dec-061): A-3 e um proxy barato (um campo do
> proprio descritor); A-3.1 e a fonte de verdade (status real da execucao
> no `state.json`/`state.db`). As duas camadas devem concordar — qualquer
> uma recusando basta para SESSION_MISMATCH. Antes desta correcao, so A-3
> existia, e o Edge Case "sessao terminal nunca autoriza mutacao" citado
> em K-2 acima (§2.3) estava, na pratica, incompleto: uma execucao podia
> terminar sem `cstk mcp stop` rodar e o token continuar autorizando
> indefinidamente.

### 2.3 Contrato de cache [PROPOSTA — a validar na implementacao]

| Regra | Requisito |
|-------|-----------|
| K-1 | Cachear **somente** `session_id -> stateDir` |
| K-2 | **Proibido** cachear `stopped_at`, o descritor, ou qualquer veredito de autorizacao |
| K-3 | **Sem TTL** — desnecessario, porque nada expiravel e cacheado |
| K-4 | Escopo = processo; nao persiste em disco |
| K-5 | Miss MUST degradar para tree-walk, nunca falhar a chamada por si so |

> **Por que K-2 e inegociavel**: cachear o descritor criaria uma janela em
> que um token de execucao **terminal** ainda autorizaria mutacao —
> violacao direta do FR-003 e do Edge Case "sessao terminal nunca autoriza
> mutacao". Foi a alternativa explicitamente rejeitada em research
> Decision 2.

---

## 3. Variaveis de ambiente do processo

| Env | Antes [REAL] | Depois | Regra |
|-----|--------------|--------|-------|
| `MCP_SESSION_TOKEN` | exigida no boot; ausencia ⇒ 0 tools | **nao usada no boot** | o token chega por argumento de tool [PROPOSTA] |
| `CSTK_MCP_PROJECT_PATH` | raiz do projeto | **mantida** | necessaria para o tree-walk de miss (research Decision 3) |
| `CSTK_MCP_STATE_DIR` | override do state-dir (path de container) | **removida** | amarrava o processo a UMA execucao [PROPOSTA] |
| `CSTK_MCP_SCRIPTS_DIR` | override opcional; default `/opt/cstk/scripts` (`exec.ts:144`) | **obrigatoria na pratica** | o default e path de container e nao existe no host |
| `CSTK_MCP_ENFORCEMENT_LOG_PATH` | default `/data/enforcement-log.jsonl` (`exec.ts:298`) | inerte | ver secao 6 |
| `MCP_MAX_TOOL_CALLS` | teto por processo (`index.ts:132`) | **inalterado**, semantica muda | ver secao 5 |

---

## 4. Launcher (`mcp-launch.sh`)

### 4.1 Comportamento atual [REAL]

| Aspecto | Hoje | Fonte |
|---------|------|-------|
| Raiz do projeto | `${CSTK_MCP_PROJECT_PATH:-$(pwd)}` | `mcp-launch.sh:123` |
| Sem token | `_ml_idle_serve "nenhuma execucao 00c ativa nesta sessao (sem token)"` | `mcp-launch.sh:128-130` |

Como o `.mcp.json` **nao tem bloco `env`** (research Decision 8), o token
nunca chegava por essa via ⇒ o launcher caia **sempre** no modo idle.

### 4.2 Comportamento contratado [PROPOSTA — a validar na implementacao]

| Regra | Requisito |
|-------|-----------|
| L-1 | O launcher MUST fazer `exec` no processo `node` real, **sem** exigir token (FR-004; clarify dec-010 elimina o stub em shell) |
| L-2 | O launcher MUST NOT depender de motor de containers (FR-005) |
| L-3 | Entrypoint: `dist/src/index.js` sob `~/.claude/mcp/state-server/` ([REAL] `package.json` `"main"`) |
| L-4 | Se o `dist/` nao existir, o launcher MUST tentar o **build lazy** (research Decision 5) |
| L-5 | Se o build lazy nao for possivel (sem `npm`, sem rede, Node incompativel), o launcher MUST **degradar para idle** com motivo explicito — **nunca** falhar a sessao do harness |
| L-6 | O preflight de major do Node MUST seguir o padrao ja em producao de `cli/lib/serve.sh` ([REAL] `:127` `_SERVE_SUPPORTED_NODE_MAJORS`, `:160` `_serve_node_preflight`) |
| L-7 | `exec` (nao fork em background) — o processo MUST morrer com a sessao do harness (FR-012) |

> **L-5 e o guard-rail que impede regredir ao sintoma da US1.** Um servidor
> que recusa subir por falta de build reproduz exatamente "connected — no
> tools" com outra causa. Degradar para idle mantem o canal previsivel e
> o motivo diagnosticavel.

---

## 5. Teto de chamadas (SEC-L1)

| Aspecto | Antes [REAL] | Depois |
|---------|--------------|--------|
| Implementacao | contador por processo (`index.ts:132-150`) | **inalterada** |
| Justificativa no comentario | `index.ts:128-131`: *"sessao == processo, um container por execucao"* | **deixa de ser verdadeira** |
| Semantica efetiva | teto por execucao autonoma | teto por **processo / sessao do harness** |

| Regra | Requisito |
|-------|-----------|
| T-1 | O comentario `index.ts:128-131` MUST ser atualizado no mesmo commit que muda a cardinalidade — comentario obsoleto aqui mente sobre o invariante de seguranca |
| T-2 | O texto da rejeicao `TOOL_CALL_LIMIT_EXCEEDED` ([REAL] `index.ts:146`) MUST permanecer acionavel (instrui comutar para o caminho Bash) |
| T-3 | Estender o teto para por-sessao esta **fora de escopo** — nenhum FR o pede (research Decision 1) |

---

## 6. Auditoria (`enforcement-log.jsonl`) — gap pre-existente

| Fato [REAL] | Consequencia |
|-------------|--------------|
| `appendAuditRecord` e definido em `src/audit/log.ts:111` e **nunca chamado** por tool alguma | a trilha de auditoria do servidor **ja nascia desligada**, antes desta feature |
| Default do path e `/data/enforcement-log.jsonl` (`exec.ts:298`) — path **de dentro do container** | apos o cutover esse default fica **invalido** |

| Regra | Requisito |
|-------|-----------|
| U-1 | Cabear a auditoria esta **fora do escopo** desta feature (research Decision 4) |
| U-2 | O plano MUST registrar o gap para que auditoria futura nao o atribua a esta feature |
| U-3 | Quem for cabea-la depois MUST derivar o path da **sessao resolvida**, nao de um default estatico |

---

## 7. Postura de seguranca: o que se perde e o que se ganha

Declaracao honesta exigida por research Decision 9. **Nao ha alegacao de
paridade.**

| Aspecto | Antes [REAL] | Depois | Veredito |
|---------|--------------|--------|----------|
| Confinamento de filesystem (SEC-H2) | flags do `docker run`: monta so `/data/state`, scripts `:ro`, enforcement log (`cli/lib/mcp-docker.sh:333-342`) | processo herda o filesystem do usuario | **REGRESSAO declarada** — sem equivalente |
| Token em identificador observavel | sufixo do nome do container ⇒ visivel a `docker ps` | **nao existe container** | **GANHO** (FR-009 / US3) |
| Autorizacao por token | fail-closed no boot | fail-closed **por chamada** | preservado, escopo mais fino |
| Superficie de ataque de infra | daemon Docker no caminho critico | processo local sem daemon | reducao |

**Mudanca de eixo do modelo de ameaca**: o confinamento deixa de ser do
**PROCESSO** e passa a ser da **AUTORIZACAO** — todo caminho de mutacao
continua passando pelos helpers POSIX, que so tocam o `state_dir` resolvido
pelo token apresentado na chamada. Contexto relevante (que **nao** anula a
perda): o adversario do modelo original ja era o conteudo lido pelo LLM,
nao o proprio servidor.

**Cobertura de teste perdida**: `tests/cstk/test_mcp-docker.sh:486`
(`scenario_run_sec_h2_montagens_proibidas`) e `:389`
(`scenario_run_hardening`) sao os **unicos** pontos que verificam SEC-H2, e
ambos exercitam flags do `docker run` — saem junto com o script (research
Decision 11). Nenhum teste os substitui, porque **nao ha mecanismo
equivalente a testar**. Registrar isso e parte da declaracao honesta.
