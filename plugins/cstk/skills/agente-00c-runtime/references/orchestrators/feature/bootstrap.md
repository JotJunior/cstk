# Referencia de fase: bootstrap (feature)

> Conteudo movido do prompt-base `agente-00c-feature-orchestrator.md` sem alteracao semantica
> (feature orchestrator-slim, FR-004). Secoes na ordem original.

1. **Validar coexistencia com agente-00c** (FR-026): checar
   `<projeto-alvo>/.claude/agente-00c-state/state.json`. Se status =
   `em_andamento` ou `aguardando_humano`, abortar com diagnostico
   apontando `/agente-00c-abort` ou `/agente-00c-resume`.
   (Esta checagem normalmente acontece no slash command pai antes de
   invocar voce — re-validar aqui como defesa em profundidade.)

2. **Lock**: NAO adquirir — o command pai ja detem o lock (ver Fronteira).
   Voce roda inteiramente dentro do lock do pai.

3. **Init de state.json**: o command pai ja criou o `state.json`. NAO
   re-inicializar. Apenas como fallback defensivo, SE o estado estiver
   AUSENTE, criar via `state-rw.sh init` com:
   - `short_name`, `target_project_path`, `descricao_curta`
   - `briefing.path` + `briefing.sha256` (FR-PRE-004)
   - `constitution.path` + `constitution.sha256` + `constitution.version` (FR-PRE-004)
   - `initial_key_aspects` (via `--key-aspects` do init): usar `drift.sh
     extract --text` para obter 3-7 keywords semanticas da descricao
     (FR-027 herdado).

3.bis **Coleta de opt-ins via MCP (mcp-elicitation-optins, dec-030/FR-012)**:
   SOMENTE nesta primeira invocacao (onda-001), ANTES de `state-ondas.sh
   start`/`open_wave` (passo 4 abaixo). Se o prompt de spawn desta execucao
   apresenta um `session_id` de capacidade E `mcp__cstk-state__collect_optins`
   esta de fato visivel entre as tools disponiveis (mesmo criterio do item 1
   de "Orientacao MCP-vs-Bash" acima), chame
   `mcp__cstk-state__collect_optins` com esse `session_id` como o **primeiro
   ato** desta execucao. O escopo de campos do formulario e derivado
   server-side de `executionKind` (`collect_optins.ts:FIELDS_BY_EXECUTION_KIND`)
   — para `feature-00c` isso e SOMENTE `atomic_commit` (`roadmap_mode` e o
   campo de finalidade de entrega sao exclusivos de `agente-00c`; dec-083).
   O discriminador do ramo e a PRESENCA, no prompt de spawn, da linha
   `MCP: ramo estruturado de opt-ins ativo` — nunca o token (bugfix 8.3.1:
   o pai pode injetar token com ramo LEGADO quando o servidor esta
   registrado mas sem tools nesta sessao). Tres casos:
   - **Linha ausente** (ramo legado, com ou sem token): NAO trate como
     erro (SC-003) — a prosa de opt-in do pai ja cobriu a captura e
     persistiu `.optin_responses[]`; siga normalmente para o passo 4.
   - **Linha presente E tool visivel**: chame `collect_optins` (acima).
   - **Linha presente E tool NAO visivel no toolset** (servidor IDLE, nao
     carregado nesta sessao, plugin/catalogo desatualizado): trate
     EXATAMENTE como `mechanism: "unavailable"` abaixo — NAO chame
     `state-ondas.sh start`/`open_wave`, devolva o turno ao pai
     IMEDIATAMENTE, em silencio (sem relatorio de onda, sem `Schedule
     intent`, sem escrever em `.optin_responses[]` — INV-4). O pai detecta
     pelo sinal estrutural "campo aplicavel sem registro + zero ondas"
     (4.bis dele), roda a prosa e re-spawna. NUNCA "siga para o passo 4"
     nesse caso: o guard M4/I-2 travaria a onda-001 e o turno seria
     queimado a toa (caso real 2026-08-18 no `/agente-00c`, `cstk-state ·
     connected · no tools`).
   **Invariante I-2**: nenhuma onda pode abrir
   enquanto houver `field` aplicavel a `executionKind` sem registro em
   `.optin_responses[]` — a guarda mecanica completa vive no runtime (FASE
   9.3/M4 de `mcp-elicitation-optins`); aqui a obrigacao e prosa: nao chame
   `state-ondas.sh start` antes de `collect_optins` retornar (ou de
   confirmar que o ramo e legado). **Cap de 1 coleta por execucao
   (dec-057)**: em RETOMADAS (`/feature-00c-resume`), NUNCA chame
   `collect_optins` de novo — leia `.optin_responses[]` (ja persistido pela
   onda-001) para saber o valor efetivo de `atomic_commit`.

   **Degradacao mid-call (FASE 6.2, `contracts/optin-capture-order.md`
   §3.3(b))**: leia `result.mechanism` da resposta de `collect_optins`.
   - `mechanism: "structured"` — captura funcionou (mesmo se o operador
     recusou/cancelou/expirou — `accepted`/`declined`/`absent`/`timeout` sao
     TERMINAIS, R-2); prossiga normalmente ao passo 4.
   - `mechanism: "unavailable"` ou `"failed"` para qualquer campo aplicavel
     (R-2: nao-terminal) — o mecanismo nao conseguiu de fato perguntar.
     `Vede` a abertura da onda-001 (NAO chame `state-ondas.sh start`) e
     devolva o turno ao command pai IMEDIATAMENTE, sem relatorio de onda
     nem `Schedule intent` (nenhuma onda foi aberta — nao ha o que
     fechar). O pai detecta a situacao lendo `.optin_responses[]`
     estruturalmente (nunca pelo seu sumario de texto — mesma disciplina
     de "fonte de verdade e o state") e roda a prosa de fallback, depois
     re-spawna esta execucao (contrato completo em
     `contracts/optin-capture-order.md` §3.3(b) itens 1-5).
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
