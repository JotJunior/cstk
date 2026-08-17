# Requirements Checklist: Opt-ins iniciais via MCP elicitation (com fallback de prosa)

**Purpose**: Gate formal de qualidade de requisitos antes de `/create-tasks`
(execucao autonoma feature-00c, onda-007). Foco: ancoragem dos 3 MEDIUM
remanescentes do gate `owasp-security` (M6/M7/M8, ja resolvidos H1/H2 na
onda-006), veracidade das premissas nao-medidas (Principio VI), granularidade
auditavel dos desfechos do formulario, e paridade de fallback nos dois ramos
degradados.
**Created**: 2026-08-17
**Feature**: [spec.md](../spec.md) | [plan.md](../plan.md) | [data-model.md](../data-model.md) | [contracts/mcp-tool-collect-optins.md](../contracts/mcp-tool-collect-optins.md) | [contracts/optin-capture-order.md](../contracts/optin-capture-order.md)

## Completude de Requisitos

- [x] CHK001 - O escopo dos 3 opt-ins (`atomic_commit`, `roadmap_mode`, `delivery_tier`) esta definido por orquestrador, incluindo a assimetria de escopo do tier? [Completude, Spec §FR-001; Contract mcp-tool-collect-optins.md linhas 48-56] {auto}
- [x] CHK002 - Os desfechos possiveis do formulario tem registro de auditoria distinguivel exigido em nivel de spec? [Completude, Spec §FR-004] {auto}
- [x] CHK003 - O requisito de nunca travar indefinidamente (FR-007) tem contraparte tecnica definida (quem impoe o teto, onde)? [Completude, Spec §FR-007/FR-010; Contract mcp-tool-collect-optins.md linhas 198-207] {auto}
- [x] CHK004 - M7 e M8 (regras 2 e 3 do INV-4) estao cobertos pelo mesmo entregavel da emenda H2, evitando que fiquem orfaos no `create-tasks`? [Completude, Plan §Resultado dos gates linhas 274-281 + Contract mcp-tool-collect-optins.md linhas 315-343 "reescrita das regras 1, 2 e 3"] {auto}
- [ ] CHK005 - M6 (cap de chamadas de `collect_optins`) tem uma tarefa de destino com criterio de pronto definido, ou permanece apenas mencao textual solta na lista de MEDIUM a enderecar? [Completude, Plan §Resultado dos gates linhas 270-271 e 331-343] {auto} — **[Gap]**: `plan.md` nomeia M6 e cita `MCP_MAX_TOOL_CALLS`/`TOOL_CALL_LIMIT_EXCEEDED` (`index.ts:200`, `:203-217`) apenas como *precedente*, mecanismo **process-wide** — nenhum trecho define se M6 exige um cap **especifico de `collect_optins`** (por campo/por execucao) ou se reusa o cap generico do processo. Sem essa decisao, `create-tasks` pode gerar uma tarefa vaga ou nenhuma.
- [x] CHK006 - A lacuna de gate dos testes Node (`mcp/state-server/test/*.test.ts` sem CI/`tests/run.sh`) esta declarada explicitamente como decisao de escopo, nao omitida? [Completude, Plan §Camada NAO gateada linhas 222-238; Quickstart Scenario 10] {auto}

## Clareza de Requisitos

- [x] CHK007 - "Defaults seguros" estao quantificados por campo (nao e termo vago)? [Clareza, Spec §FR-006] {auto}
- [x] CHK008 - O termo "pre-requisito do mecanismo estruturado satisfeito", usado em FR-001/005/009, tem definicao operacional unica e consistente entre os FRs? [Clareza, Spec §FR-001 ("sessao com suporte ao mecanismo + servidor de estado ativo")] {auto}
- [x] CHK009 - O init em duas etapas (FR-012) tem criterio objetivo de quando cada etapa termina? [Clareza, Spec §FR-012] {auto}
- [x] CHK010 - O campo `message` como portador do aviso de rebaixamento (H1/dec-047) esta marcado consistentemente como premissa nao-medida em vez de apresentado como garantia? [Clareza/Principio VI, Contract mcp-tool-collect-optins.md linhas 138-196 "Pendencia de medicao"] {auto}

## Consistencia de Requisitos

- [x] CHK011 - FR-006 (default seguro) e FR-012 (etapa 1 grava defaults) usam o mesmo valor para `delivery_tier` (`cloud-public`)? [Consistencia, Spec §FR-006/FR-012] {auto}
- [ ] CHK012 - FR-013 da spec e consistente com o que o proprio `plan.md` verificou sobre chamadores existentes das 3 primitivas de escrita? [Consistencia/Principio VI, Spec §FR-013 vs Plan §Correcoes de premissa item 1, linhas 82-87] {auto} — **[Conflict]**: `spec.md` FR-013 afirma que as tres primitivas "ate esta feature nao tinham chamador ativo"; `plan.md` corrige que `delivery-tier.sh set` **ja tem** chamadores (`agente-00c.md:433`, `agente-00c-resume.md:214/218`) — vale so para as outras duas. `plan.md` recomenda "Delta de spec" mas `spec.md` nao foi atualizado nesta sessao.
- [ ] CHK013 - O Edge Case de `spec.md` sobre falha do servidor apos a etapa 1 usa o discriminador correto de sinal? [Consistencia/Principio VI, Spec Edge Cases linhas 197-208 vs Plan §Correcoes de premissa item 3, linhas 91-98; `optin-capture-order.md` §5] {auto} — **[Conflict]**: `spec.md` cita `mode=bash-fallback` como o sinal de falha do servidor; `plan.md`/`optin-capture-order.md` §5 (VERIFICADO: `mcp.sh:708-709`, `:100-107`) confirmam que **nenhum** caminho de codigo emite esse valor e proibem qualquer teste que o asserte. `spec.md` nao foi corrigido para "token vazio / descritor ausente".
- [ ] CHK014 - A granularidade do enum `outcome` (6 valores: `accepted`/`declined`/`absent`/`timeout`/`unavailable`/`failed`, `data-model.md` linhas 136-149) esta ancorada a um FR de `spec.md` que a exija, ou e elaboracao de design sem requisito correspondente? [Consistencia/Rastreabilidade, Spec §FR-004 vs data-model.md §Enum outcome] {auto} — **[Gap]**: `FR-004` fala em **tres** desfechos (aceitou / recusou / ausente-default) e so exige distinguir os dois ultimos entre si. A distincao mais fina `absent` x `timeout` x `unavailable` x `failed` nasce inteiramente em `data-model.md`/`research.md` Decision 6, sem FR de `spec.md` que a torne requisito (nao apenas detalhe de implementacao) — relevante porque essa granularidade e o que M8 usa como evidencia de consentimento.

## Mensurabilidade dos Criterios de Aceite

- [x] CHK015 - FR-010 (teto de tempo do lado servidor) tem cenario de aceite mensuravel? [Mensurabilidade, Spec §FR-010; Quickstart Scenario 4 linhas 151-164] {auto}
- [x] CHK016 - FR-008/FR-011 (idempotencia em retomada) tem cenario de aceite mensuravel (zero requisicoes `elicitation/create` emitidas)? [Mensurabilidade, Spec §FR-008/FR-011; Quickstart Scenario 7 linhas 199-210] {auto}
- [x] CHK017 - SC-005 ("exatamente UMA linha de aviso") e objetivamente contavel/automatizavel? [Mensurabilidade, Spec §SC-005] {auto}
- [ ] CHK018 - O cap de M6 tem valor ou mecanismo numerico definido e mensuravel, ou permanece apenas intencao textual? [Mensurabilidade, Plan §Resultado dos gates linhas 270-271] {auto} — **[Gap]**, mesma raiz de CHK005: sem numero/mecanismo, nao ha o que medir.

## Cobertura de Cenarios

- [x] CHK019 - O happy path do operador presente respondendo esta coberto? [Cobertura, Spec §US1; Quickstart Scenario 1] {auto}
- [x] CHK020 - A ausencia de operador / execucao headless esta coberta? [Cobertura, Spec §US2; Quickstart Scenario 4] {auto}
- [x] CHK021 - O mecanismo indisponivel desde o inicio (ramo legado) esta coberto com garantia de zero regressao? [Cobertura, Spec §US3 Acceptance Scenario 1/SC-003; Quickstart Scenario 5] {auto}
- [ ] CHK022 - O mecanismo ativo que falha NO MEIO da chamada (US3 Acceptance Scenario 2) tem garantia de PARIDADE de captura via prosa equivalente a SC-003, ou apenas garantia do aviso em stderr? [Cobertura, Spec §US3 Scenario 2/SC-003/SC-005; Quickstart Scenario 6] {auto} — **[Gap]**: `SC-003` esta textualmente escopado a "sessoes **sem** o mecanismo estruturado disponivel" (Scenario 5) e `SC-005` so mede a contagem de linhas de aviso. Nenhum SC afirma explicitamente que a captura via prosa **apos** uma falha no meio (Scenario 6) produz o **mesmo resultado observavel** que a captura em prosa de hoje — a paridade fica implicita em `contracts/optin-capture-order.md` §3.3(b) (nivel de design), sem eco em `spec.md`.
- [x] CHK023 - A recusa explicita e distinguivel de ausencia de operador nos criterios de aceite? [Cobertura, Spec §US1 Scenario 3/SC-004] {auto}

## Cobertura de Edge Cases

- [x] CHK024 - O disparo repetido do mesmo formulario na mesma execucao (retomada) esta coberto e resolvido (reuso, sem re-pergunta)? [Edge Case, Spec Edge Cases/FR-011; Quickstart Scenario 7] {auto}
- [x] CHK025 - O escopo assimetrico do campo `delivery_tier` entre os dois orquestradores esta coberto com teste de escopo negativo? [Edge Case, Spec Edge Cases; Quickstart Scenario 2 linhas 116-129] {auto}
- [x] CHK026 - A elicitation disparada por subagente sem operador humano presente esta marcada como fora de escopo (Deferred), em vez de assumida como resolvida por este desenho? [Edge Case, Spec Edge Cases ultimo item, linhas 209-213] {auto}

## Requisitos Nao-Funcionais (Seguranca)

- [x] CHK027 - A emenda ao INV-4 (regras 1-3 de `cli-delivery-tier.md` §2.2) e o ajuste do teste que a guarda estao redigidos como UMA UNICA tarefa/commit, evitando emenda normativa sem o teste correspondente? [Nao-Funcional/Seguranca, Plan §Entregavel obrigatorio de H2 linhas 316-329; Contract mcp-tool-collect-optins.md linhas 353-363] {auto}
- [ ] CHK028 - O cap adequado para M6 (valor numerico, escopo por campo vs por processo) e uma decisao de risco de produto explicita? [Risco] {humano}
- [ ] CHK029 - O teto de tempo default de `collect_optins` (120000 ms) e adequado ao apetite de risco/UX do produto, ou deveria ser calibrado por experiencia real antes de virar default fixo? [Risco, Contract mcp-tool-collect-optins.md linhas 198-207] {humano}

## Dependencias e Premissas

- [x] CHK030 - A premissa central do desenho (o harness renderiza `elicitation/create` originado de subagente) esta marcada como bloqueante e testada antes de qualquer implementacao? [Dependencias, Plan §Riscos R1; Quickstart Scenario 0] {auto}
- [x] CHK031 - A renderizacao de `message` ao operador esta marcada como premissa NAO MEDIDA (nao fato), com consequencia de contrato definida caso falhe? [Dependencias/Principio VI, Contract mcp-tool-collect-optins.md linhas 172-196] {auto}
- [x] CHK032 - A lacuna de CI para os testes Node esta acompanhada de uma decisao de escopo separada, em vez de expandir silenciosamente o escopo desta feature? [Dependencias, Plan §Camada NAO gateada linhas 234-238] {auto}

## Notes

- Items `{auto}` ja vem resolvidos pelo agente (`[x]` com citacao, ou marcador `[Gap]`/`[Conflict]`).
- Items `{humano}` ficam `[ ]` aguardando decisao do dono do produto.
- **Resumo de desfechos**: 26 `[x]` resolvidos, 4 `[Gap]`, 2 `[Conflict]`, 2 `{humano}` em aberto — total 32 items, 100% com referencia rastreavel (Spec/Plan/Contract/Quickstart ou marcador).

### Follow-up obrigatorio (gaps viram acao — §4.4 da skill)

| Item | Marcador | Destino |
|------|----------|---------|
| CHK005, CHK018 | `[Gap]` M6 sem cap numerico/mecanismo definido | `/create-tasks` — tarefa "definir e implementar cap de `collect_optins`" so pode nascer objetiva apos CHK028 ({humano}) decidir o mecanismo |
| CHK012 | `[Conflict]` FR-013 vs chamadores reais de `delivery-tier.sh set` | `/clarify` ou edicao direta de `spec.md` FR-013 antes do `/create-tasks` — texto atual afirma fato ja contradito pelo proprio `plan.md` |
| CHK013 | `[Conflict]` Edge Case cita `mode=bash-fallback` (nunca emitido) | `/clarify` ou edicao direta de `spec.md` Edge Cases — mesma correcao ja aplicada em `optin-capture-order.md` §5, ausente em `spec.md` |
| CHK014 | `[Gap]` granularidade do enum `outcome` sem FR correspondente | `/create-tasks` — considerar adicionar clausula a FR-004 (ou FR novo) exigindo a distincao `absent`/`timeout`/`unavailable`/`failed` no registro, ja que M8 depende dela como evidencia de consentimento |
| CHK022 | `[Gap]` sem SC de paridade de prosa no ramo degradado mid-call (Scenario 6) | `/create-tasks` — ou adicionar SC dedicado, ou apontar explicitamente que SC-003 cobre por extensao (decisao do dono do produto) |
| CHK028, CHK029 | `{humano}` cap de M6 e teto de 120000ms | decisao do dono do produto antes de `/execute-task` |
