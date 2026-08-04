# Quickstart: state-mcp-server

Cenarios que validam a implementacao end-to-end. Todos rodam contra um
**projeto-alvo descartavel** (`mktemp -d`), nunca contra o repo do operador.

> **Pre-requisito absoluto**: os cenarios 0.x (spikes) sao **gate**. Se S1 falhar,
> nenhum outro cenario tem valor — a feature perde o consumidor primario e o
> caminho correto e bloqueio humano (research.md §Spike Obrigatorio).

---

## Scenario 0.1: Spike S1 — subagente consegue chamar tool MCP (BLOQUEANTE)

1. Criar projeto-alvo temporario com um servidor MCP stdio minimo (uma tool
   `ping` que retorna `pong`), registrado via `cstk mcp install`
2. Abrir sessao do Claude Code nesse projeto
3. Spawnar um subagente de teste (tool `Agent`) instruido a chamar `ping`
4. **Expected**: o subagente chama a tool e recebe `pong`.
   **Se falhar**: registrar Decisao com a saida literal como evidencia e **abrir
   bloqueio humano** — nao prosseguir para os demais cenarios.

## Scenario 0.2: Spike S2 — nome da tool na allowlist do subagente

1. Com S1 verde, inspecionar como a tool aparece na sessao
2. Restringir o `tools:` do frontmatter do subagente ao nome descoberto
3. **Expected**: o nome exato e conhecido e documentado; com a allowlist
   restrita a ele, a chamada continua funcionando (e outras tools ficam de fora).

## Scenario 0.3: Spike S5 — helpers POSIX sob busybox (alpine)

1. Construir a imagem e rodar, **dentro do container**, o subconjunto de estado
   da suite (`state-rw`, `state-ondas`, `state-decisions`, `bloqueios`)
2. **Expected**: mesmos resultados que no host. Divergencia (ex.: `stat`
   GNU-first — gotcha ja conhecido no repo) ⇒ trocar base para `node:22-slim`.

---

## Scenario 1: Happy path — onda inteira so por tools (User Story 1)

1. Criar execucao de teste (`state-rw.sh init`) e subir o servidor
   (`cstk mcp start --state-dir <SD>`)
2. `open_wave`
3. `record_decision` com `justification_score=3` **e** `evidence` >= 20 chars
4. `record_skill` com o `decision_id` retornado (par two-step)
5. `record_task` com `task_id=1.1`, `outcome=pass`
6. `close_wave` com `termination_reason=etapa_concluida_avancando`
7. **Expected**:
   - estado tao integro quanto pelo caminho Bash: onda com `termination_reason`
     nao-nulo, task com outcome, decisao com `evidence`;
   - `cstk mcp status` reporta `status=active`;
   - **zero comando Bash de escrita de estado** foi necessario (Independent Test
     da US1).

## Scenario 2: Error case — score 3 sem evidencia (FR-002 / SC-002)

1. Com onda aberta, chamar `record_decision` com `justification_score=3` e
   `evidence` ausente
2. **Expected**: `outcome=rejected`, `reason=EVIDENCE_REQUIRED`, `stage=schema`
   (rejeicao **antes** do handler) e — verificacao decisiva — **a contagem de
   decisoes no estado nao muda** (`state-decisions.sh count` identico antes e
   depois). Nada persistiu.

## Scenario 3: Error case — chamada fora de ordem (FR-009 / Edge Case)

1. Com a onda **fechada**, chamar `record_task`
2. **Expected**: `outcome=rejected`, `reason=NO_OPEN_WAVE`, sem side-effect
   parcial
3. Chamar `close_wave` com a onda ja fechada
4. **Expected**: `outcome=rejected`, `reason=NO_OPEN_WAVE` — e a rejeicao
   aparece no `enforcement-log.jsonl` (Independent Test da US3)

## Scenario 4: Idempotencia de `record_task` (FR-004)

1. `record_task` com `task_id=2.1`, `outcome=fail` → `result.operation=inserted`
2. Repetir com o **mesmo** `task_id`, agora `outcome=pass` →
   `result.operation=updated`
3. **Expected**: exatamente **uma** entrada para `2.1`, com `outcome=pass`.
   Nenhuma duplicata (PK `(execution_id, task_id)`).

## Scenario 5: Atomicidade de `close_wave` (FR-003)

1. Injetar falha na etapa de `sha256-update` (ex.: tornar o state-dir
   temporariamente somente-leitura apos o `end`)
2. Chamar `close_wave`
3. **Expected**: `outcome=rejected`, `reason=CLOSE_ROLLED_BACK`, e
   `state-ondas.sh wave-status` volta a reportar **`open`** — a onda **nao** fica
   parcialmente fechada. Pre-imagem restaurada.

## Scenario 6: Confinamento entre execucoes concorrentes (FR-008 / FR-016)

1. Criar **duas** execucoes no mesmo projeto: uma `agente-00c` e uma
   `feature-00c/<short>`; subir servidor para ambas
2. **Expected**: dois containers distintos, dois `mcp-server.json` distintos
3. Chamar uma tool na sessao A passando o `session_id` da sessao B
4. **Expected**: `SESSION_MISMATCH`; o `state-dir` de B permanece **byte-identico**
   (comparar sha256 antes/depois)
4b. **Regressao de confused deputy (SEC-H3)**: com **ambas** ativas, o
   orquestrador da `feature-00c` chama uma tool apresentando o **seu** token.
   **Expected**: a mutacao cai no state-dir da `feature-00c` — **nunca** no da
   `agente-00c`, que venceria por precedencia. Este e o cenario que a precedencia
   ambiente quebrava (US2 cenario 3 / FR-008)
4c. Chamar uma tool **sem** `session_id`, ou com token inventado
   **Expected**: `SESSION_MISMATCH` — **sem** fallback para "a execucao ativa mais
   provavel" (fail-closed)
5. Inspecionar as montagens do container A
6. **Expected**: nenhuma montagem do state-dir de B; **nenhuma montagem de
   `knowledge.db`** (FR-013)

## Scenario 7: Fallback sem Docker (FR-007 / FR-012 / SC-004)

1. Rodar a execucao de teste com `docker` indisponivel no `PATH`
2. **Expected**: `cstk mcp status` → `status=unavailable`, `reason=docker-absent`,
   **exit 0** (indisponivel nao e erro); state grava `mode=bash-fallback`
3. Rodar a mesma execucao ate o fim pelo caminho Bash
4. **Expected**: mesmas invariantes finais do Scenario 1 — zero regressao
   observavel, zero intervencao manual, **nenhum prompt ao operador**

## Scenario 8: Servidor sobrevive a pausa entre ondas (FR-010)

1. Fechar a onda com `termination_reason=etapa_concluida_avancando` e simular a
   pausa de `Schedule intent`
2. **Expected**: `cstk mcp status` continua `active` durante a pausa — o
   container **nao** foi parado nem recriado (comparar `container` e
   `session_id`, que devem ser identicos antes e depois)
3. Levar a execucao a estado terminal (`concluida`)
4. **Expected**: `cstk mcp stop` roda como parte do encerramento; `docker ps` nao
   lista o container; nenhum processo orfao (US2 cenario 2)

---

## Scenario 9: Roundtrip End-to-End (obrigatorio — borda Node ↔ POSIX ↔ state)

Esta feature tem borda entre camadas com convencoes de nome diferentes (JSON
camelCase/snake_case do MCP ↔ flags kebab-case em portugues dos helpers ↔ colunas
snake_case do `state.db`). O cenario existe para pegar drift **na primeira
execucao**, nao 40 ondas depois.

1. Subir o servidor de verdade (sem mock, sem fixture)
2. Chamar `record_decision` com **todos** os campos opcionais preenchidos
3. Ler o registro resultante direto da fonte: `state-decisions.sh list` **e**
   (quando backend sqlite) `sqlite3 state.db 'SELECT ... FROM decision'`
4. Comparar campo a campo contra `contracts/mcp-tools.md`:
   - `justification_score` (tool) ↔ `--score` (flag) ↔ `justification_score` (coluna)
   - `evidence` ↔ `--evidencia` ↔ `evidence`
   - `options_considered` ↔ `--opcoes` ↔ `options_considered`
   - `rationale` ↔ `--justificativa` ↔ `rationale`
   - `originating_artifact` ↔ `--artefato-originador` ↔ `originating_artifact`
5. Repetir o passo 4 com backend **`json`** (state-dir sem `state.db`)
6. **Expected**: zero divergencia entre payload da tool, flag do helper e coluna
   persistida, **nos dois backends**. Campo que "some" na traducao (tipico:
   opcional que nunca chega ao helper) e o defeito que este cenario existe para
   expor.
