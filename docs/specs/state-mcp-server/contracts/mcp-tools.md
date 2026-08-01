# Contracts: state-mcp-server — Tools MCP

Contrato das 6 tools de mutacao de estado exigidas por FR-001.

> **Status de todo este documento: `[PROPOSTA — a validar na implementacao]`.**
> Nenhuma destas tools existe hoje: nao ha `package.json`, `.ts` nem
> `@modelcontextprotocol/sdk` no repo [VERIFICADO por varredura]. O que **e**
> fato verificado sao (a) as flags dos helpers POSIX para os quais cada tool
> delega e (b) as colunas do `state.db` afetadas — ambas citadas por tool. O
> desenho da assinatura MCP e novo e, portanto, proposta.

## Forma geral

[VERIFICADO — docs oficiais do SDK TS]: registro via
`server.registerTool(name, { description, inputSchema }, handler)`; o SDK
**valida `inputSchema` antes de invocar o handler**. Isso e o que permite que
FR-002 seja imposto **no schema**, e nao em codigo do handler.

**Argumento comum a TODAS as tools** (nao repetido em cada tabela):

| Field | Type | Required | Validation |
|-------|------|----------|------------|
| `session_id` | string | yes | Deve casar com `<state-dir>/mcp-server.json`; divergencia ⇒ `SESSION_MISMATCH` (FR-008) |

O `state_dir` **NAO** e argumento de tool: e propriedade da sessao, resolvida do
descritor. Aceitar `state_dir` do chamador permitiria que uma sessao mutasse
outra execucao — exatamente o que FR-008 proibe.

**Envelope de resposta** (todas as tools):

| Field | Type | Description |
|-------|------|-------------|
| `outcome` | `"accepted"` \| `"rejected"` | |
| `reason` | string \| null | Motivo acionavel quando `rejected` (FR-009) |
| `stage` | `"schema"` \| `"precondition"` \| `"delegation"` \| null | Onde parou |
| `result` | object \| null | Dados da mutacao aceita (ex.: `decision_id`) |

**Erros comuns a todas** (alem dos especificos por tool):

| Code | Quando |
|------|--------|
| `SESSION_MISMATCH` | `session_id` nao corresponde ao token de capacidade da sessao (FR-008; ver `mcp-session-lifecycle.md` §SEC-H3) |
| `EXECUTION_TERMINAL` | `execution.status` ∈ `abortada\|concluida` — nao se muta execucao terminal |
| `HELPER_FAILED` | Helper POSIX retornou != 0; `reason` carrega o stderr do helper (scrubbed e limitado — ver SEC-M1) |

---

## Controles de seguranca da fronteira Node → POSIX (do gate `owasp-security`)

Todo campo de texto livre destas tools (`context`, `rationale`, `evidence`,
`question`, `title`, `touched_files`, ...) chega de um LLM que pode ter lido
conteudo nao-confiavel (arquivos do projeto, saida de ferramenta) — ou seja, e
**entrada hostil em potencial por injecao indireta** (LLM01/ASI01), nao texto de
um humano. As regras abaixo sao **MUST** e devem ter assercao estatica no teste.

### SEC-H1 (HIGH) — invocacao por argv, jamais por shell

O handler MUST invocar o helper por **`execFile`/`spawn` com array de argumentos
e `shell: false`**. E **PROIBIDO**: `exec()`, `execSync()`, `spawn(..., {shell:
true})`, template string montando linha de comando, e qualquer forma de `eval`.

```
PROIBIDO:  exec(`state-decisions.sh register --evidencia "${evidence}"`)
EXIGIDO:   execFile(helperPath, ["register", "--state-dir", sd,
                                 "--evidencia", evidence], { shell: false })
```

Sem isso, um `evidence` contendo `"; curl … | sh; #` vira **execucao de comando
arbitrario dentro do container**, que tem o state-dir montado rw (A05 Injection /
ASI02 Tool Misuse). O array de argv elimina a classe inteira: o valor nunca e
interpretado por um shell.

**Assercao estatica obrigatoria** (teste que falha o build): `grep` no fonte do
servidor nao pode casar `exec(`, `execSync(`, `shell: true` nem crase com
`.sh`.

### SEC-M2 (MEDIUM) — campos de identificador sao allowlist, nao texto livre

Texto livre e seguro como **valor** de flag (argv o preserva), mas campos que
viram identificadores MUST ser validados por allowlist no `inputSchema`, para
nao serem confundidos com flags nem corromper ids:

| Campo | Allowlist |
|-------|-----------|
| `task_id` | `^[A-Za-z0-9._-]{1,64}$` |
| `decision_id` | `^dec-[0-9]{1,9}$` |
| `skill` | `^[A-Za-z0-9._-]{1,64}$` |
| `executed_stages[]` | `^[A-Za-z0-9._-]{1,64}$` [VERIFICADO: mesma regra do helper] |
| `kind`, `outcome`, `termination_reason` | enum fechado (ja especificado) |
| `touched_files[]` | path **relativo**; rejeitar absoluto, `..` e byte NUL |

Regra transversal: nenhum campo de identificador pode comecar com `-`.

### SEC-M1 (MEDIUM) — saida do helper e DADO, com teto

O `reason` devolvido ao modelo carrega stderr do helper, que pode ecoar conteudo
influenciado pelo atacante (ex.: um path vindo de `touched_files`). Isso e
**saida de ferramenta voltando ao contexto do LLM** (LLM05 / injecao indireta).
MUST: remover caracteres de controle, limitar a **2 KiB**, e nunca reinjetar sem
o rotulo de dado nao-confiavel.

### SEC-M3 (MEDIUM) — a linha de auditoria e serializada, nunca concatenada

A linha do `enforcement-log.jsonl` MUST ser produzida por um **serializador JSON
real** (`JSON.stringify`, ou `jq -nc` como faz o hook [VERIFICADO:
`pretooluse-bash-guard.sh:150-163`]) — **nunca** por `printf`/concatenacao de
string. Um `"` ou `\n` num campo de texto livre quebraria a linha e permitiria
**forjar entradas de auditoria** (A09 / ASI09).

Ordem obrigatoria e integral: `scrub` → `truncate` → `serialize`. O truncamento
MUST ocorrer em **code points**, nao bytes (cortar UTF-8 no meio produz JSON
invalido e derruba a linha inteira do log).

### SEC-L1 (LOW) — teto de chamadas por sessao

Nenhum limite de chamadas por tool/sessao existe hoje (item do checklist MCP;
LLM10 Unbounded Consumption). Recomendado: teto por sessao com o mesmo espirito
do `budget.sh` (que orca a **onda**, nao a tool). Nao bloqueante para o MVP.

---

## Tool: `record_decision`

Registra Decisao auditavel. **Delega para** [VERIFICADO]:
`state-decisions.sh register --state-dir <SD> --agente --etapa --contexto
--opcoes --escolha --justificativa [--score] [--evidencia] [--referencias]
[--artefato-originador]`.

### Request

| Field | Type | Required | Validation |
|-------|------|----------|------------|
| `agent` | string | yes | min 1 |
| `stage` | string | yes | Etapa SDD corrente |
| `context` | string | yes | **min 20 chars** [VERIFICADO: `state-decisions.sh:185-189`] |
| `options_considered` | string[] | yes | min 1 item |
| `choice` | string | yes | min 1 |
| `rationale` | string | yes | **min 20 chars** [VERIFICADO: mesma linha] |
| `justification_score` | integer \| null | no | `null \| 0 \| 1 \| 2 \| 3` [VERIFICADO: `state-decisions.sh:198-201`] |
| `evidence` | string \| null | condicional | **Obrigatorio e min 20 chars quando `justification_score == 3`** [VERIFICADO: `state-decisions.sh:208-215`] |
| `references` | string[] \| null | no | |
| `originating_artifact` | string \| null | no | |

**FR-002 no schema**: a condicional `score == 3 ⇒ evidence` e expressa como
refinamento do `inputSchema` (Zod `.refine()` ou equivalente), logo a rejeicao
ocorre **antes do handler** — nenhum byte persiste. A trava do helper permanece
como segunda barreira (defesa em profundidade: se o schema for afrouxado por
engano, o helper ainda rejeita).

### Response (accepted)

| Field | Type | Description |
|-------|------|-------------|
| `result.decision_id` | string | Id emitido pelo helper (ex.: `dec-013`) — **ecoado do stdout do helper, nunca gerado pela tool** |

### Errors

| Code | Description |
|------|-------------|
| `EVIDENCE_REQUIRED` | `justification_score == 3` sem `evidence` >= 20 chars (SC-002) |
| `TEXT_TOO_SHORT` | `context` ou `rationale` < 20 chars |
| `SCORE_OUT_OF_RANGE` | `justification_score` fora de `null\|0..3` |
| `CONSTITUTION_CONFLICT_SCORE` | `options_considered` contem as strings canonicas de conflito com constitution e `justification_score != 0` [VERIFICADO: `state-decisions.sh:225-235`] |

---

## Tool: `open_wave`

Abre a onda. **Delega para** [VERIFICADO]: `state-ondas.sh start --state-dir <SD>`
(o `start` nao aceita `--fase`).

### Request

Somente `session_id`.

### Response (accepted)

| Field | Type | Description |
|-------|------|-------------|
| `result.wave_id` | string | Ex.: `onda-004` (stdout do helper) |

### Errors

| Code | Description |
|------|-------------|
| `WAVE_ALREADY_OPEN` | Ja existe onda aberta. **Pre-condicao checada com `state-ondas.sh wave-status` (`open\|closed\|none`) antes de delegar** [VERIFICADO] — `start` **nao e idempotente**: cada chamada faz append em `.waves[]`, e chama-lo com onda aberta duplicaria a onda |

> Esta e a mesma armadilha que o Loop principal do orquestrador trata hoje no
> passo 3.bis. A tool a torna fisicamente impossivel, em vez de depender de o LLM
> lembrar da guarda — que e o proposito declarado da feature.

---

## Tool: `close_wave`

Fecha a onda **atomicamente** (FR-003). **Delega para** [VERIFICADO]:
`secrets-filter.sh for-backup --wave-number N` → `state-ondas.sh end --state-dir
<SD> --motivo-termino <M> [--proxima-agendada-para] [--add-etapa] [--next-instruction]`
→ `state-rw.sh sha256-update --state-dir <SD>`, com pre-imagem e compensacao
(research.md Decision 3).

### Request

| Field | Type | Required | Validation |
|-------|------|----------|------------|
| `termination_reason` | enum | yes | **exatamente** `etapa_concluida_avancando` \| `threshold_proxy_atingido` \| `bloqueio_humano` \| `aborto` \| `concluido` [VERIFICADO: `state-ondas.sh:714`] |
| `executed_stages` | string[] \| null | no | Cada item casa `[A-Za-z0-9._-]`, <= 64 chars [VERIFICADO]; vira N x `--add-etapa` |
| `next_scheduled_for` | string \| null | no | ISO 8601 |
| `next_instruction` | string \| null | no | Checkpoint da proxima onda |

### Response (accepted)

| Field | Type | Description |
|-------|------|-------------|
| `result.wave_id` | string | Onda fechada |
| `result.backup_path` | string | Backup gerado (pos-condicao de FR-003) |
| `result.state_sha256` | string | Selo recalculado |

### Errors

| Code | Description |
|------|-------------|
| `NO_OPEN_WAVE` | `wave-status` != `open` |
| `INVALID_TERMINATION_REASON` | Fora do enum de 5 valores |
| `INVALID_STAGE_TOKEN` | Item de `executed_stages` com caractere fora de `[A-Za-z0-9._-]` ou > 64 chars |
| `CLOSE_ROLLED_BACK` | Falha em backup/hash apos a mutacao ⇒ pre-imagem restaurada; **a onda permanece aberta** (nunca parcialmente fechada) |

---

## Tool: `record_task`

Registra outcome de task, **idempotente por `task_id`** (FR-004). **Delega para**
[VERIFICADO]: `state-ondas.sh record-task --state-dir <SD> --task-id --outcome
[--titulo] [--wave-id] [--testes-rodados] [--testes-passados] [--lint-ok]
[--arquivos] [--origem] [--if-absent]`.

### Request

| Field | Type | Required | Validation |
|-------|------|----------|------------|
| `task_id` | string | yes | Ex.: `4.1` |
| `outcome` | enum | yes | `pass` \| `fail` |
| `title` | string \| null | no | Titulo do heading em `tasks.md`; `""` se indisponivel |
| `wave_id` | string \| null | no | Default: onda corrente |
| `tests_run` | integer | no | >= 0, default 0 |
| `tests_passed` | integer | no | >= 0 e **<= `tests_run`** |
| `lint_ok` | boolean | no | |
| `touched_files` | string[] | no | Paths relativos |
| `source` | string \| null | no | Ex.: `execute-task` |
| `if_absent` | boolean | no | `true` ⇒ nao sobrescreve entrada existente (back-fill) |

### Response (accepted)

| Field | Type | Description |
|-------|------|-------------|
| `result.task_id` | string | |
| `result.operation` | `"inserted"` \| `"updated"` | Evidencia do upsert (FR-004) |

**Base da idempotencia** [VERIFICADO]: PK `(execution_id, task_id)` em
`task_outcome` (`state-db-schema.sql:192`). Repetir a chamada **atualiza**; nunca
duplica.

### Errors

| Code | Description |
|------|-------------|
| `TESTS_PASSED_EXCEEDS_RUN` | `tests_passed > tests_run` |
| `NO_OPEN_WAVE` | Registrar task sem onda aberta (Edge Case "fora de ordem") |

---

## Tool: `register_human_block`

Registra bloqueio humano. **Delega para** [VERIFICADO]: `bloqueios.sh register
--state-dir <SD> --decisao-id --pergunta --contexto-para-resposta
[--opcoes-recomendadas]`.

### Request

| Field | Type | Required | Validation |
|-------|------|----------|------------|
| `decision_id` | string | yes | Decisao associada (ex.: `dec-012`) |
| `question` | string | yes | min 1 |
| `context_for_answer` | string | yes | min 1 |
| `recommended_options` | string[] \| null | no | |

### Response (accepted)

| Field | Type | Description |
|-------|------|-------------|
| `result.block_id` | string | Ex.: `block-001` (stdout do helper) |
| `result.execution_status` | string | `aguardando_humano` — **efeito colateral verificado do helper** |

### Errors

| Code | Description |
|------|-------------|
| `DECISION_NOT_FOUND` | `decision_id` inexistente (FK `human_block.decision_id`) |

---

## Tool: `record_skill`

Registra invocacao de skill/gate na onda. **Delega para** [VERIFICADO]:
`state-ondas.sh record-skill --state-dir <SD> --skill [--decisao-id] [--kind]`.

### Request

| Field | Type | Required | Validation |
|-------|------|----------|------------|
| `skill` | string | yes | Nome da skill/gate |
| `decision_id` | string \| null | no | Par two-step com `record_decision` |
| `kind` | enum | no | `skill` \| `gate` [VERIFICADO: CHECK em `skill_invocation.kind`]; default `skill` |

### Response (accepted)

| Field | Type | Description |
|-------|------|-------------|
| `result.wave_id` | string | Onda que recebeu o registro |

### Errors

| Code | Description |
|------|-------------|
| `NO_OPEN_WAVE` | Sem onda aberta |
| `INVALID_KIND` | `kind` fora de `skill\|gate` |

> **Higiene de metrica** (herdada do contrato dos orquestradores): `kind=gate`
> para gates deterministicos de script; `kind=skill` apenas para invocacao real
> da tool Skill. Comandos de build/test/lint **nao** entram aqui — pertencem a
> `record_task`.

---

## Nao-tools (fora de escopo deliberado)

| Capacidade | Por que nao e tool |
|-----------|--------------------|
| Consultar status do servidor (FR-015) | E consulta do **operador/command pai**, nao do orquestrador ⇒ CLI (`cstk mcp status`), ver `mcp-session-lifecycle.md` |
| Qualquer escrita em `knowledge.db` | **FR-013**: read-only, e o container sequer a monta |
| Adquirir/liberar lock | **research.md Decision 4**: o lock do command pai ja envolve a onda; `state-lock.sh` e nao-reentrante (um `acquire` daria exit 3 sempre) |
| `state-rw.sh set` generico | Escape hatch que anularia todo o proposito da feature — mutacao arbitraria sem contrato |
