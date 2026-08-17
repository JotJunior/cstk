# Quickstart: mcp-elicitation-optins

Cenarios de validacao end-to-end. Cobrem os tres User Stories da spec, os seis
desfechos de `RespostaDeOptIn` e a lacuna de gate declarada em
`research.md` Decision 12.

> **Convencao**: `SD` = `<projeto-alvo>/.claude/feature-00c-state/<short>/`
> (ou `.claude/agente-00c-state/` para `agente-00c`).
> Leitura de estado sempre via `state-rw.sh get` — nunca `cat state.json`
> (sob backend SQLite o arquivo pode nem existir).

---

## Scenario 0: Validacao de premissa (BLOQUEANTE — rodar ANTES de tudo)

Valida a unica premissa nao medida de que o desenho inteiro depende
(`research.md` Decision 1): que um `elicitation/create` originado de tool
chamada por **subagente** chegue ao operador.

1. Sessao interativa, servidor `cstk-state` conectado via `.mcp.json`
2. Spawnar o orquestrador e faze-lo invocar `collect_optins`
3. **Expected**: o formulario aparece **para o operador**, com o campo de
   selecao renderizado como picker.
4. **Se NAO aparecer**: PARAR. O desenho de `contracts/optin-capture-order.md`
   §3 e invalido e a feature precisa voltar ao `plan` — nao contornar com
   suposicao sobre quem mais poderia disparar.

Registrar tambem, na mesma sondagem, os tres itens **nao medidos**
(`contracts/mcp-tool-collect-optins.md`): `title` vira label? `description`
vira subtexto? `default` vem pre-aplicado? O resultado decide se o texto
explicativo de FR-002 pode ficar nas propriedades ou MUST migrar para
`message`.

---

## Scenario 1: Happy path — operador responde (US1, FR-001/002/003)

1. `cstk mcp status --state-dir "$SD"` reporta token presente
2. Iniciar `/agente-00c` (ramo ESTRUTURADO)
3. Confirmar que **nenhum** bloco de prosa de opt-in foi exibido (Invariante O-2)
4. Formulario aparece com **3** campos (`agente-00c`); responder:
   commit atomico = `sim`, roadmap = `nao`, tier = `local`
5. **Expected**:
   - `commit-mode.sh is-enabled --state-dir "$SD"` → `true`
   - `roadmap-mode.sh is-enabled --state-dir "$SD"` → `false`
   - `delivery-tier.sh get --state-dir "$SD"` → `local`
   - `.optin_responses[]` tem 3 entradas, todas com `channel: "structured"`;
     `atomic_commit` e `delivery_tier` com `outcome: "accepted"`
   - `state-ondas.sh wave-status` → onda so abre **depois** disso

> **Ponto critico deste cenario (dec-037)**: `local` e ordinal 0 e o init
> gravou ordinal 3 (`cloud-public`) — e um **rebaixamento**. Se a
> implementacao esquecer `--allow-downgrade`, `delivery-tier.sh set` retorna
> exit 2 **sem escrever** e o passo 5 mostra `cloud-public`. Este cenario e o
> detector primario desse defeito.

---

## Scenario 2: Escopo por orquestrador (FR-001, Edge Case)

1. Iniciar `/feature-00c` (nao `/agente-00c`) no ramo ESTRUTURADO
2. **Expected**: o formulario tem **2** campos — `atomic_commit` e
   `roadmap_mode`. O campo de finalidade de entrega **NAO** aparece.
3. `delivery-tier.sh get --state-dir "$SD"` → `cloud-public` (default do init,
   intocado)
4. `.optin_responses[]` tem **2** entradas; nenhuma para `delivery_tier`

> Derivado de `ResolvedSession.executionKind` (VERIFICADO), nao de heuristica
> de path.

---

## Scenario 3: Recusa explicita x ausencia de operador (US1-3, FR-004, SC-004)

**3a — recusa explicita**

1. Formulario aberto; operador **recusa** (acao de decline do cliente)
2. **Expected**: todos os campos com `outcome: "declined"`, `applied_value`
   igual ao default seguro; execucao prossegue sem pausa; **zero** linhas em
   stderr

**3b — sem operador (headless)**

1. Rodar a execucao em sessao nao-interativa
2. **Expected**: cliente responde `cancel` imediato; campos com
   `outcome: "absent"`; defaults seguros; **zero** linhas em stderr

3. **Expected (comparacao 3a x 3b)**: os dois registros sao
   **distinguiveis** — `declined` vs `absent` — com o mesmo `applied_value`.
   Esta e a assercao de SC-004.

---

## Scenario 4: Teto de tempo (US2-2, FR-007, FR-010)

1. Sessao interativa; formulario aparece; **nao responder**
2. Aguardar `MCP_ELICIT_TIMEOUT_MS` (default 120000 ms; reduzir por env para
   tornar o teste rapido)
3. **Expected**:
   - a execucao **prossegue** — nao trava (SC-002)
   - registros com `outcome: "timeout"`, defaults seguros
   - `outcome` e **`timeout`**, nunca `absent`

> **Assercao central (research.md Decision 6)**: `timeout` vem de `McpError`
> code `RequestTimeout` **lancado**; `absent` vem de envelope `cancel`
> **retornado**. O teste MUST distinguir pelo mecanismo. Um teste que
> classifique por tempo decorrido esta errado mesmo que passe.

---

## Scenario 5: Mecanismo nunca disponivel — ramo LEGADO (US3-1, FR-005, SC-003)

1. Garantir descritor ausente / token vazio (execucao sem `cstk mcp start`)
2. Iniciar `/agente-00c`
3. **Expected**:
   - os **3 blocos de prosa** aparecem exatamente como hoje
   - init recebe as flags (`--atomic-commit` etc.) — caminho legado intacto
   - **zero** linhas de aviso em stderr (SC-005: "nunca esteve disponivel" e
     silencioso)
   - nenhuma mencao a MCP na experiencia do operador

---

## Scenario 6: Mecanismo ativo que falha no meio (US3-2, FR-009, SC-005)

1. Token presente (ramo ESTRUTURADO); induzir falha na chamada de elicitation
   **apos** a requisicao ser emitida
2. **Expected**:
   - **exatamente UMA** linha em stderr informando que o formulario falhou e
     que a execucao seguiu com os defaults seguros
   - registros com `outcome: "failed"`
   - o orquestrador **nao abre onda** e devolve o turno
   - o pai le `.optin_responses[]`, roda os blocos de prosa, persiste com
     `channel: "prose"` e re-spawna
   - o operador **nao** e perguntado duas vezes (US3-2)

3. **Expected (contraste com Scenario 5)**: a diferenca observavel entre
   Scenario 5 (nenhum aviso) e Scenario 6 (um aviso) e a assercao de SC-005.

---

## Scenario 7: Idempotencia em retomada (FR-008, FR-011)

1. Executar Scenario 1 ate as respostas ficarem gravadas
2. Interromper e retomar via `/agente-00c-resume`
3. **Expected**:
   - **nenhum** formulario e exibido
   - `collect_optins` retorna `reused` com os 3 campos
   - **zero** requisicoes `elicitation/create` emitidas
   - valores da camada 1 inalterados
4. Repetir o resume mais uma vez → mesmo resultado (idempotente, nao apenas
   "uma vez a menos")

---

## Scenario 8: Roundtrip de borda — envelope real x contrato

Substitui o cenario "backend↔frontend" do template: a borda real desta feature
e **servidor MCP (Node/TS) ↔ helpers POSIX ↔ state**. Sem mock, sem fixture.

1. Subir o servidor de fato e invocar `collect_optins` numa execucao real
2. Capturar o envelope retornado pela tool
3. Comparar contra `contracts/mcp-tool-collect-optins.md`:
   - nomes de campo do envelope (`outcome`, `reason`, `stage`, `result`) —
     **camelCase/snake_case conforme declarado**, sem coercao silenciosa
   - tokens de enum de `outcome` batem **literalmente** com os seis do
     `data-model.md`
   - `applied_value` bate com o que `commit-mode.sh is-enabled` /
     `roadmap-mode.sh is-enabled` / `delivery-tier.sh get` retornam **de fato**
4. **Expected**: zero divergencia entre envelope real, contrato declarado e
   estado lido pelos helpers.

> Por que obrigatorio: esta feature tem **duas** convencoes de nomenclatura em
> contato (wire MCP camelCase x campos de estado snake_case x flags kebab-case
> — ver `plan.md` §Convencoes de Borda). Drift de case entre camadas e
> exatamente a classe de defeito que so aparece em roundtrip empirico.

---

## Scenario 9: Guard de composicao e clausula revogada (dec-029, dec-032)

1. `./tests/run.sh test_orchestrator-allowlist-guard`
2. **Expected**:
   - o cenario de allowlist exige **8** tools, incluindo `collect_optins`
   - a assercao do item 8 verifica os **dois** recortes (permitido com operador
     presente; diferido sem operador presente), nos dois orquestradores
   - `scenario_allowlist_preserva_bash` continua verde

3. **Teste de mutacao (obrigatorio)**: inverter a semantica do item 8 num dos
   orquestradores **mantendo** o literal `elicitation/create`.
   **Expected**: a suite fica **VERMELHA**.
   Se ficar verde, a assercao continua cega e o entregavel de
   `contracts/optin-capture-order.md` §6.1 nao foi cumprido — a unica prova de
   que a cegueira foi fechada.

---

## Scenario 10: Lacuna de gate — verificacao honesta (dec-027)

1. `grep -rin node .github/workflows/` → **zero linhas** (VERIFICADO hoje)
2. `grep -nE "mcp/state-server|npm test|node --test" tests/run.sh` → **sem match**
   (VERIFICADO hoje)
3. **Expected**: enquanto os dois comandos acima seguirem com esse resultado,
   **nenhum** artefato desta feature pode afirmar que a logica de elicitation
   esta coberta por gate. Os `*.test.ts` novos existem e rodam sob `npm test`
   manual — isso e **intencao verificavel**, nao cobertura.
4. Ao fechar a decisao de escopo (criar workflow Node **ou** wirar `npm test`
   em `tests/run.sh`), este cenario inverte: os comandos passam a casar e a
   afirmacao de cobertura passa a ser sustentavel.
