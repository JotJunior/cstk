# Quickstart: validacao de `mcp-direct-transport`

**Feature**: `mcp-direct-transport` | **Phase**: 1 | **Date**: 2026-08-16

Cenarios de aceite executaveis. Cada um mapeia para um Success Criteria da
spec. **Nenhum cenario usa mock** — todos exercitam o caminho real.

> **Gate obrigatorio antes de qualquer cenario**: cenario 0. Ele existe
> porque o CI **nao** roda os testes do servidor (research Decision 12) —
> a validacao manual e a unica rede de protecao.

---

## Cenario 0 — Gate manual: suite do servidor + suite POSIX

**Cobre**: mitigacao declarada da lacuna de CI (research Decision 12).

1. `cd mcp/state-server && npm ci`
2. `npm test`
   → **Expected**: os 15 arquivos `*.test.ts` compilam e passam. O script
   real e `"test": "npm run build && node --test dist/test/*.test.js"`
   ([REAL] `package.json`).
3. `cd <repo-root> && LC_ALL=C ./tests/run.sh --check-coverage`
   → **Expected**: exit 0, **zero orfaos**. Este passo falha se
   `cli/lib/mcp-docker.sh` e `tests/cstk/test_mcp-docker.sh` nao sairem no
   mesmo commit (research Decision 11).
4. `LC_ALL=C ./tests/run.sh mcp`
   → **Expected**: todos os cenarios MCP verdes.

> `LC_ALL=C` evita FAIL falso por locale pt_BR na suite.

---

## Cenario 1 — Tools disponiveis sem execucao ativa (US1, SC-001)

**Pre-condicao**: nenhuma execucao 00c ativa no projeto; `.mcp.json` ja
registrado (`cstk mcp install`).

1. Confirmar que **nao** ha execucao ativa:
   `cstk mcp status --project-path <repo>`
   → **Expected**: `status=unavailable` (ou `stopped`), **exit 0** —
   `status=unavailable` **nao e erro** ([REAL] `mcp.sh:78`).
2. Abrir uma sessao nova do Claude Code no repositorio.
3. Listar os servidores MCP (`/mcp`).
   → **Expected**: `cstk-state` **connected**, com as **7 tools**
   listadas (`record_skill`, `record_decision`, `open_wave`,
   `record_task`, `register_human_block`, `get_status`, `close_wave`).
   → **NAO Expected**: `connected - no tools` / `Capabilities: none` —
   esse e exatamente o sintoma que a feature elimina.

**Falha diagnostica**: se ainda aparecer `no tools`, verificar se o
launcher instalado e o novo — o sintoma sobrevive a atualizacao de **uma
so** metade da instalacao (research Decision 6).

---

## Cenario 2 — Tool disponivel NAO implica mutacao autorizada (US1 cenario 2, SC-002)

**Pre-condicao**: cenario 1 concluido; nenhuma execucao 00c ativa.

1. Chamar uma tool de mutacao (ex.: `record_decision`) passando um
   `session_id` arbitrario inexistente.
   → **Expected**: resposta com `outcome: "rejected"`, `isError: true`, e
   `reason` explicito. A mensagem de mismatch e
   `"session_id nao corresponde ao token de capacidade desta sessao"`
   ([REAL] `record_decision.ts:148`).
2. Chamar a mesma tool com `session_id` vazio (`""`).
   → **Expected**: rejeicao pelo schema Zod, antes de qualquer I/O —
   `"session_id obrigatorio"` ([REAL] `record_decision.ts:55`).
3. Confirmar que **nada** foi mutado: `git status` no state-dir alvo e
   inspecao do `state.json`/`state.db`.
   → **Expected**: nenhuma alteracao.

---

## Cenario 3 — Lifecycle sem motor de containers (US2, SC-003)

**Pre-condicao**: maquina **sem** Docker instalado ou com o daemon parado.

1. `cstk mcp start --state-dir <SD>`
   → **Expected**: **exit 0** e descritor gravado. **NAO Expected**:
   exit 3 com `mode=bash-fallback` por motivo de Docker.
2. `cat <SD>/mcp-server.json`
   → **Expected**: `session_id` preenchido, `container_name: null`,
   `stopped_at: null`, `mode: "direct"` **[VALIDADO — task 3.2]**.
3. `cstk mcp status --state-dir <SD>`
   → **Expected**: `status=active`, `session_id=<id>`, `container=-`.
4. `cstk mcp status --state-dir <SD> --live`
   → **Expected**: mesmo resultado — `--live` vira no-op sem container
   (contrato ST-3).
5. `cstk mcp stop --state-dir <SD>`
   → **Expected**: exit 0; `stopped_at` passa a nao-nulo.
6. `cstk mcp stop --state-dir <SD>` (de novo)
   → **Expected**: exit 0, idempotente, sem erro (FR-008).
7. Chamar qualquer tool com o token daquela sessao.
   → **Expected**: **rejeitada** — sessao terminal nunca autoriza mutacao
   ([REAL] `mcp-session.sh:130` fail-closed).

---

## Cenario 4 — Idempotencia de `start` (FR-010, SC-005)

1. `cstk mcp start --state-dir <SD>` → capturar `session_id` (chamar de A).
2. `cstk mcp start --state-dir <SD>` de novo → capturar `session_id` (B).
   → **Expected**: exit 0; **A == B** (sessao reusada, nao invalidada).
3. Chamar uma tool com o token A.
   → **Expected**: aceita — a segunda chamada de `start` **nao**
   interrompeu chamadas em curso.
4. Verificar que nao ha segundo processo servidor.
   → **Expected**: nenhum processo duplicado; o processo e criado pelo
   harness, nao pelo `start` (contrato S-5).

---

## Cenario 5 — Descritor legado `mode=docker` (FR-014)

**Pre-condicao**: um `<SD>/mcp-server.json` com `mode: "docker"` e
`container_name` preenchido (formato pre-cutover).

1. `cstk mcp start --state-dir <SD>`
   → **Expected**: **exit 0** (nunca recusa por estado legado) **e** aviso
   explicito em **stderr** mencionando o descritor legado.
2. `cat <SD>/mcp-server.json`
   → **Expected**: sobrescrito com o novo formato; `container_name: null`.

---

## Cenario 6 — `gc` recolhe o passivo Docker (FR-015)

**Pre-condicao**: pelo menos um container `cstk-mcp-state-*` remanescente,
de sessao criada antes do cutover.

1. `cstk mcp gc --dry-run`
   → **Expected**: summary listando o container como candidato; **nada**
   removido.
2. `cstk mcp gc`
   → **Expected**: container removido; summary com contagem.
3. Em maquina **sem** Docker: `cstk mcp gc`
   → **Expected**: **exit 0** com `summary=docker-indisponivel
   examined:0 removed:0 kept:0 skipped:0` ([REAL] `mcp.sh:805-808`) — `gc`
   **nao** vira no-op nem erro.

---

## Cenario 7 — Roundtrip End-to-End real (borda orquestrador ↔ servidor)

**O cenario que so o caminho real revela.** Exercita a cadeia inteira:
command pai → prompt de spawn → argumento de tool → helper POSIX → state.

**Pre-condicao**: uma execucao `feature-00c` real, com `cstk mcp start` ja
executado.

1. Iniciar a execucao pelo command pai (`/feature-00c <short-name>`).
2. Confirmar que o token foi injetado no prompt de spawn do orquestrador —
   **sem** depender de `mode == "docker"` (FR-013).
   → **Expected**: o orquestrador recebe `session_id`.
3. O orquestrador chama uma tool de mutacao real (ex.: `record_decision`).
   → **Expected**: `outcome: "accepted"`.
4. Ler o estado pela **fonte de verdade**, nao pela resposta da tool:
   `state-rw.sh read --state-dir <SD> | jq '.decisions[-1]'`
   → **Expected**: a decisao gravada bate campo a campo com o que foi
   enviado.
5. Repetir com **duas** execucoes ativas simultaneas no mesmo projeto
   (`agente-00c` + `feature-00c`), cada uma chamando tools com o proprio
   token.
   → **Expected**: cada chamada muta **exclusivamente** o state-dir da
   sessao cujo token foi apresentado (FR-011). Nenhum cross-talk.

> O passo 5 e o unico que exercita a mudanca de cardinalidade
> **1 processo : N sessoes** (`data-model.md` §Relacionamentos). Sem ele, a
> regressao mais grave possivel desta feature — uma chamada mutando o
> state-dir errado — passaria despercebida.

---

## Cenario 8 — Token nunca observavel por outros processos (US3, SC-004)

1. Com uma sessao MCP ativa, listar processos:
   `ps aux | grep -i state-server`
   → **Expected**: nenhum argumento/nome contendo o `session_id`.
2. Listar containers (se Docker existir na maquina):
   `docker ps -a --format '{{.Names}}'`
   → **Expected**: nenhum container **novo** `cstk-mcp-state-<token>`.
   Remanescentes pre-cutover podem existir ate o `gc` (cenario 6).
3. Inspecionar o `.mcp.json` do projeto.
   → **Expected**: **sem** bloco `env`, sem token — arquivo versionavel
   nunca carrega credencial (contrato I-2).
4. Confirmar a permissao do descritor: `ls -l <SD>/mcp-server.json`
   → **Expected**: `600` ([REAL] `mcp.sh:469`).

---

## Cenario 9 — Build lazy ausente degrada para idle, nao para falha (contrato L-5)

**Pre-condicao**: `~/.claude/mcp/state-server/` **sem** `dist/` nem
`node_modules/` — estado real de uma instalacao nova ([REAL], dec-025).

1. Abrir uma sessao do Claude Code.
   → **Expected**: o launcher tenta o build lazy. Havendo `npm` + rede,
   conclui e o servidor sobe normalmente (cenario 1 se aplica).
2. Simular indisponibilidade (`npm` fora do PATH, ou sem rede).
   → **Expected**: o launcher **degrada para idle** com motivo explicito.
   **NAO Expected**: falha da sessao do harness, ou erro opaco.
3. Restaurar `npm` e reabrir a sessao.
   → **Expected**: build lazy conclui; `dist/src/index.js` passa a existir
   ([REAL] `package.json` `"main"`); tools listadas.

---

## Cenario 10 — Processo morre com a sessao do harness (FR-012)

1. Com o servidor conectado, identificar o processo node do servidor.
2. Encerrar a sessao do Claude Code.
3. Verificar processos remanescentes.
   → **Expected**: **nenhum** processo orfao do servidor.
4. Verificar o descritor: `cat <SD>/mcp-server.json`
   → **Expected**: **ainda existe**, com `stopped_at` inalterado. A
   **sessao MCP** (descritor + token) sobrevive a morte do **processo** —
   e a separacao central de research Decision 10.
5. Abrir sessao nova e chamar uma tool com o **mesmo** token.
   → **Expected**: aceita — o processo recriado resolve o mesmo token por
   chamada. Nada de duravel vivia no processo.

---

## Matriz de rastreabilidade

| Cenario | FRs | SCs |
|---------|-----|-----|
| 0 | — (gate de qualidade) | — |
| 1 | FR-001, FR-004, FR-005 | SC-001 |
| 2 | FR-003 | SC-002 |
| 3 | FR-005, FR-006, FR-007, FR-008 | SC-003 |
| 4 | FR-010 | SC-005 |
| 5 | FR-014 | — |
| 6 | FR-015 | — |
| 7 | FR-002, FR-011, FR-013 | SC-002 |
| 8 | FR-009 | SC-004 |
| 9 | FR-004 | SC-001 |
| 10 | FR-012 | — |
