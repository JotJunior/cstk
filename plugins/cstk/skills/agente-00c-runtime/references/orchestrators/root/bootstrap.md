# Referencia de fase: bootstrap (root)

> Conteudo movido do prompt-base `agente-00c-orchestrator.md` sem alteracao semantica
> (feature orchestrator-slim, FR-004). Secoes na ordem original.

## Init de aspectos-chave (primeira onda apenas)

A PRIMEIRA onda do orquestrador (`invocation_type=primeira_invocacao`)
DEVE gravar `initial_key_aspects` no estado antes de finalizar a
onda. Sem isso, `drift.sh check` fica em modo `desabilitado` (warn-only)
para o resto da execucao — detector cego, sem capacidade de abort.

Quando aplicar:
- Apos a skill `briefing` completar e o `briefing.md` estar salvo
- ANTES do `state-ondas.sh end` da onda-001
- Apenas se `.initial_key_aspects == null` (idempotencia)

Procedimento:

1. Extrair 3-7 aspectos-chave do `briefing.md` recem-gerado. Aspectos
   devem ser substantivos curtos, lowercase, kebab-case, que capturam
   o produto/UCs essenciais (ex: `slack`, `bot`, `threads` para um
   bot Slack; `triagem`, `priorizacao`, `mcp-jira` para um sistema
   de triagem).
2. Quando aplicavel, tambem extrair aspectos tecnicos e operacionais
   das secoes correspondentes do briefing:
   - `--tecnicos`: auth, sessao, db, infra, mensageria
   - `--operacionais`: runbooks, ci-cd, monitoring
3. Chamar:

   ```bash
   drift.sh init --state-dir <SD> \
     --aspectos '["produto-a","produto-b","produto-c"]' \
     [--tecnicos '["auth","sessao","db"]'] \
     [--operacionais '["runbooks","ci-cd"]']
   ```

4. Registrar Decisao informativa documentando os aspectos escolhidos
   e a justificativa (extracao do briefing).

Se o estado ja tem `initial_key_aspects` populado, pular esta
secao (idempotencia). Se a execucao e legada (criada antes da FASE 3
da evolucao, sem aspectos), o operador re-inicializa via
`/agente-00c-resume --init-aspectos '["..."]'` — ver
`agente-00c-resume.md`.

1.bis **Coleta de opt-ins via MCP (mcp-elicitation-optins, dec-030/FR-012)**:
   SOMENTE quando `invocation_type=primeira_invocacao` (onda-001), ANTES
   do `state-ondas.sh start` do passo 2. Se o prompt de spawn desta
   execucao apresenta um `session_id` de capacidade E
   `mcp__cstk-state__collect_optins` esta de fato visivel entre as tools
   disponiveis nesta sessao (mesmo criterio do item 1 de "Orientacao
   MCP-vs-Bash"), chame `mcp__cstk-state__collect_optins` com esse
   `session_id` como o **primeiro ato** desta execucao. O escopo de campos
   e derivado server-side de `executionKind`
   (`collect_optins.ts:FIELDS_BY_EXECUTION_KIND`) — para `agente-00c` isso
   e `atomic_commit` + `roadmap_mode` + `delivery_tier` (os 3 campos; ver
   tabela completa no contrato da feature). O discriminador do ramo e a
   PRESENCA, no prompt de spawn, da linha `MCP: ramo estruturado de
   opt-ins ativo` — nunca o token (bugfix 8.3.1: o pai pode injetar token
   com ramo LEGADO quando o servidor esta registrado mas sem tools nesta
   sessao). Tres casos:
   - **Linha ausente** (ramo legado, com ou sem token): NAO trate como
     erro (SC-003) — a prosa de opt-in do pai ja cobriu a captura e
     persistiu `.optin_responses[]`; siga normalmente para o passo 2.
   - **Linha presente E tool visivel**: chame `collect_optins` (acima).
   - **Linha presente E tool NAO visivel no toolset** (servidor IDLE, nao
     carregado nesta sessao, plugin/catalogo desatualizado): trate
     EXATAMENTE como `mechanism: "unavailable"` abaixo — NAO chame
     `state-ondas.sh start`, devolva o turno ao pai IMEDIATAMENTE, em
     silencio (sem relatorio de onda, sem `Schedule intent`, sem
     escrever em `.optin_responses[]` — INV-4). O pai detecta pelo sinal
     estrutural "campo aplicavel sem registro + zero ondas" (4.bis dele),
     roda a prosa e re-spawna. NUNCA "siga para o passo 2" nesse caso: o
     guard M4/I-2 travaria a onda-001 e o turno seria queimado a toa (caso
     real 2026-08-18, `cstk-state · connected · no tools`).
   **Invariante I-2**: nenhuma onda pode abrir enquanto houver `field`
   aplicavel a `executionKind` sem registro em `.optin_responses[]` — a
   guarda mecanica completa vive no runtime (FASE 9.3/M4 de
   `mcp-elicitation-optins`); aqui a obrigacao e prosa: nao chame
   `state-ondas.sh start` antes de `collect_optins` retornar (ou de
   confirmar que o ramo e legado). **Cap de 1 coleta por execucao
   (dec-057)**: em RETOMADAS (`invocation_type != primeira_invocacao`),
   NUNCA chame `collect_optins` de novo — leia `.optin_responses[]` (ja
   persistido pela onda-001) para saber os valores efetivos.

   **Degradacao mid-call (FASE 6.2, `contracts/optin-capture-order.md`
   §3.3(b))**: leia `result.mechanism` da resposta de `collect_optins`.
   - `mechanism: "structured"` — captura funcionou (mesmo se o operador
     recusou/cancelou/expirou — `accepted`/`declined`/`absent`/`timeout` sao
     TERMINAIS, R-2); prossiga normalmente ao passo 2.
   - `mechanism: "unavailable"` ou `"failed"` para qualquer campo aplicavel
     (R-2: nao-terminal) — o mecanismo nao conseguiu de fato perguntar.
     NAO chame `state-ondas.sh start` e devolva o turno ao command pai
     IMEDIATAMENTE, sem relatorio de onda nem `Schedule intent` (nenhuma
     onda foi aberta — nao ha o que fechar). O pai detecta a situacao
     lendo `.optin_responses[]` estruturalmente (nunca pelo seu sumario de
     texto — mesma disciplina de "fonte de verdade e o state") e roda a
     prosa de fallback, depois re-spawna esta execucao (contrato completo
     em `contracts/optin-capture-order.md` §3.3(b) itens 1-5).
   - **Aviso em stderr**: SOMENTE no sub-caso `"failed"`, emita via
     `log_err` **exatamente uma linha**: `collect_optins: mecanismo
     estruturado falhou apos oferecido (mid-call) — devolvendo ao command
     pai para captura por prosa (FR-005/FR-009)`. `"unavailable"` e
     SILENCIOSO (FR-009: o mecanismo nunca esteve de fato disponivel nesta
     chamada — a experiencia MUST ficar indistinguivel do ramo legado).
   - **Anti-loop (R-3/6.2.3)**: no re-spawn apos a prosa do pai, chame
     `collect_optins` normalmente de novo (e o "primeiro ato" de toda
     bootstrap da onda-001) — a propria tool detecta que TODOS os campos
     aplicaveis ja tem registro (agora com `channel: "prose"`, terminal) e
     retorna `reused` sem re-disparar `elicitation/create` (cap M6). O
     operador NUNCA e perguntado duas vezes pelo mesmo campo.

<!-- ORCH-REF-END -->
