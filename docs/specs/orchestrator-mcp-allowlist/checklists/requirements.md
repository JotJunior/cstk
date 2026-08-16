# REQUIREMENTS Checklist: Allowlist MCP para orquestradores 00c

**Purpose**: Unit tests para a qualidade dos requisitos de
`orchestrator-mcp-allowlist` — nao valida implementacao, valida se os FRs,
SCs, edge cases e clarifications estao completos, claros, consistentes,
mensuraveis e rastreaveis antes de `create-tasks`.
**Created**: 2026-08-16
**Feature**: [spec.md](../spec.md)
**Executado por**: feature-00c (autonomo), onda-005

## Completude de Requisitos

- [x] CHK001 - Cada uma das 4 user stories tem pelo menos um FR que a
  cobre? [Completude, Spec §User Scenarios+Requirements] {auto}
  Evidencia: US1→FR-001/FR-002/FR-004/FR-007; US2→FR-003/FR-004/FR-009;
  US3→FR-005/FR-006; US4→FR-008. Nenhuma story orfa.
- [x] CHK002 - Requisitos nao-funcionais (degradacao graciosa, roteamento
  seguro por sessao) estao cobertos, nao so os funcionais de exposicao de
  tools? [Completude, Spec §FR-007,FR-008] {auto}
  Evidencia: FR-007 (preservar garantia de nao-degradacao) e FR-008
  (validacao de roteamento por token) sao ambos NFR de seguranca/robustez,
  presentes no corpo de Requirements (spec.md:247-256).
- [x] CHK003 - Declaracoes explicitas de fora-de-escopo estao documentadas
  (retry automatico, mecanismo de rodizio/particionamento de allowlist,
  novo mecanismo de sessao)? [Completude, Spec §FR-009,FR-010] {auto}
  Evidencia: FR-009 exclui explicitamente "mecanismo de
  rodizio/particionamento" (spec.md:262-263); FR-010 exclui retry
  (herda contrato 0-retry de FR-006); nota apos FR-012 declara N/A para
  scheduling/key rotation/mutex/backup (spec.md:290-293).
- [x] CHK004 - O requisito do guard (FR-002) e agnostico a forma YAML do
  frontmatter `tools:` (inline `tools: A, B` vs. lista `tools:` + `- A`),
  em vez de assumir implicitamente uma unica forma? [Completude, Clareza,
  Spec §FR-002] {auto}
  Evidencia: o texto de FR-002 fala em "frontmatter `tools:` resolve para
  conjunto vazio OU e composto exclusivamente por `mcp__*`" (spec.md:212-215)
  — nao referencia nenhuma sintaxe YAML especifica, e portanto nao
  hardcoda a forma inline nem a forma de lista. A robustez as duas formas
  e um requisito de PLANO (research.md Decision 4, spec.md:178-227),
  corretamente deixado fora do spec.md (WHAT, nao HOW) — mas o encadeamento
  spec→plan so fecha porque Decision 4 EXISTE. Sondagem empirica desta
  sessao confirma que a lacuna e real: `printf 'tools: Agent, Skill, Bash,
  ..., mcp__cstk-state__open_wave\n' | grep -Eq '^\s*-\s*mcp__'` retorna
  NAO-CASADO contra a ERE do guard antigo
  (tests/test_orchestrator-mcp-fallback.sh:61,70) — a mesma forma inline
  usada de fato pelos 7 arquivos de agente do repo (`grep -n '^tools:'
  plugins/cstk/agents/*.md`, ambos orquestradores em forma inline).

## Clareza de Requisitos

- [x] CHK005 - "somente-MCP" e "conjunto vazio" (condicoes de falha do
  guard, FR-002) estao definidos sem margem de interpretacao dupla?
  [Clareza, Spec §FR-002] {auto}
  Evidencia: FR-002 define objetivamente as duas condicoes de falha
  ("resolve para conjunto vazio OU e composto exclusivamente por entradas
  `mcp__*`") e Decision 4 (research.md) formaliza a tabela de veredito
  completa (vazio/so-MCP/mista/so-nativa/glob-vazio → FAIL/PASS), sem
  ambiguidade residual.
- [x] CHK006 - "fallback imediato uniforme, sem retry" (FR-006) esta
  quantificado com o contrato exato, nao deixado como adjetivo vago?
  [Clareza, Spec §FR-006] {auto}
  Evidencia: FR-006 cita o contrato numerico exato — "0 retries + 1
  confirmacao via `cstk mcp status --live` + comutacao para Bash no resto
  da onda" (spec.md:242-246), com fonte literal em dois commands
  (`feature-00c.md:738`, `agente-00c.md:497`).
- [x] CHK007 - Placeholders nao resolvidos (`TODO`, `TKTK`,
  `[NEEDS CLARIFICATION]`) ainda existem na spec? [Clareza, Completude]
  {auto}
  Evidencia: `grep -nE 'TODO|TKTK|NEEDS CLARIFICATION'
  docs/specs/orchestrator-mcp-allowlist/spec.md` = zero ocorrencias; as 3
  perguntas abertas na sessao de clarify (spec.md:162-203) tem resposta
  registrada, nenhuma pendente.

## Consistencia de Requisitos

- [x] CHK008 - FR-003/FR-004 (allowlist mista obrigatoria) sao
  consistentes com o Acceptance Scenario 3 de US1 (mistura passa no
  guard)? [Consistencia, Spec §FR-003,FR-004,US1-AC3] {auto}
  Evidencia: FR-004 exige >=1 tool nativa sempre; US1 Acceptance Scenario
  3 (spec.md:41-43) afirma que o guard passa com mistura de nativas +
  `mcp__*` — nenhuma contradicao, a mesma regra em duas camadas
  (requisito normativo + cenario observavel).
- [x] CHK009 - A terminologia "orquestrador autonomo" e usada de forma
  consistente entre o corpo da spec e os Edge Cases/Clarifications
  (deteccao por sufixo `-orchestrator`)? [Consistencia] {auto}
  Evidencia: FR-002 e o Edge Case resolvido (spec.md:150-154) usam a
  mesma formulacao ("deteccao por padrao de nome / sufixo
  `-orchestrator`"), e a Clarification Q1 (spec.md:164-176) reforca com
  a mesma regra e a mesma contagem empirica (2 de 7 arquivos).
- [x] CHK010 - FR-010 (Deferred) esta marcado de forma consistente em
  todo o documento, sem nenhuma outra FR/SC tratando seu comportamento
  como ja definido? [Consistencia, Spec §FR-010] {auto}
  Evidencia: `grep -n 'elicitation' spec.md` so ocorre em FR-010
  (spec.md:266-279); nenhuma outra FR ou SC pressupoe comportamento de
  elicitation. FR-005/FR-006 (orientacao de uso) tratam elicitation
  explicitamente como fora de escopo de uso ativo (spec.md:276-279), sem
  contradizer o Deferred.

## Qualidade de Criterios de Aceite / Mensurabilidade

- [x] CHK011 - SC-001 a SC-005 sao objetivamente verificaveis (nao
  dependem de juizo subjetivo do avaliador)? [Mensurabilidade, Spec
  §Success Criteria] {auto}
  Evidencia: todos os 5 SCs usam criterio binario ou percentual associado
  a evento observavel — "100% das execucoes... sem bloqueio" (SC-001),
  "cada uma verificavel por uma chamada real" (SC-002), "bloqueia 100%
  das configuracoes" (SC-003), "aceita/rejeitada... validado por pelo
  menos um caso real" (SC-004), "suite... 100% verde" (SC-005).
- [x] CHK012 - SC-002 enumera as 7 operacoes de forma que cada uma seja
  testavel individualmente, nao so como bloco agregado? [Mensurabilidade,
  Spec §SC-002] {auto}
  Evidencia: SC-002 lista as 7 por nome ("abrir onda, registrar decisao,
  registrar skill invocada, registrar task, registrar bloqueio humano,
  fechar onda, consultar status") — mesma enumeracao de FR-003/Decision 5,
  cada uma independentemente chamavel/verificavel.
- [x] CHK013 - SC-003 e SC-004 tem criterio de aceite binario
  (aceita/rejeita, bloqueia/nao-bloqueia), sem zona cinzenta?
  [Mensurabilidade, Spec §SC-003,SC-004] {auto}
  Evidencia: SC-003 = "bloqueia 100% das configuracoes que deixem... sem
  fallback nativo" (binario); SC-004 = "chamada com token correto e
  aceita, chamada com token ausente/divergente e rejeitada" (binario,
  2 categorias exaustivas).

## Cobertura de Cenarios

- [x] CHK014 - O happy path de US2 (servidor MCP ativo, 7 operacoes
  acessiveis) esta coberto por Acceptance Scenario dedicado?
  [Cobertura, Spec §US2-AC1] {auto}
  Evidencia: US2 Acceptance Scenario 1 (spec.md:69-71) cobre
  explicitamente o caso servidor-ativo + operacao-acessivel.
- [x] CHK015 - O error path (servidor MCP indisponivel, fallback nativo
  sem erro visivel) esta coberto por Acceptance Scenario dedicado?
  [Cobertura, Spec §US2-AC2] {auto}
  Evidencia: US2 Acceptance Scenario 2 (spec.md:72-75) cobre
  explicitamente indisponibilidade total + fallback nativo sem pausa.
- [x] CHK016 - O cenario intermediario — servidor ATIVO mas UMA chamada
  especifica falha (nao indisponibilidade total) — esta coberto pelos
  requisitos normativos, e nao so mencionado en passant nos Edge Cases?
  [Cobertura, Edge Case, Spec §FR-006,Clarifications] {auto}
  Evidencia: promovido de Edge Case a requisito MUST explicito em FR-006
  (spec.md:236-246) apos a Clarification Session 2026-08-16
  (spec.md:186-197) — nao fica so implicito no Edge Cases, tem FR proprio
  com contrato numerico citado (CHK006).

## Cobertura de Edge Cases

- [x] CHK017 - A afirmacao "allowlist so-MCP e recusada antes do spawn"
  (premissa central de US1) tem evidencia empirica citavel, nao apenas
  hipotese de design? [Edge Case, Spec §US1] {auto}
  Evidencia: sondagem empirica desta sessao (claude-code 2.1.233),
  transcript persistido em `/private/tmp/claude-502/
  -Users-jot-Projects--lab-Jot-misc-cstk/bf5a2993-5a81-4403-8b5c-dc399a413e2f/
  scratchpad/fase0/A5b.log` — allowlist so-`mcp__absent__*` (servidor
  nunca registrado) produz recusa de spawn com a mensagem literal "would
  be spawned with zero tools — refusing". Fecha a lacuna que a onda-004
  havia deixado como caveat (sem transcript persistido).
- [x] CHK018 - A afirmacao "allowlist mista degrada em silencio quando o
  servidor MCP esta ausente" (o que torna FR-003/FR-004 seguros) tem
  evidencia empirica citavel? [Edge Case, Spec §US1,FR-004] {auto}
  Evidencia: sondagem empirica desta sessao, transcript persistido em
  `.../scratchpad/fase0/A6b.log` — allowlist mista (`Bash`, `Read` +
  `mcp__absent__ping`, servidor nunca registrado) rodou com sucesso; o
  subagente reportou "MCP_AUSENTE — mcp__absent__ping nao existe; segui
  sem erro" e completou o fallback Bash (`echo FALLBACK_BASH_OK` →
  `FALLBACK_BASH_OK`). Fecha a segunda lacuna deixada pela onda-004.
- [x] CHK019 - O caso de uma tool MCP renomeada/removida no servidor
  enquanto o frontmatter ainda referencia o nome antigo tem comportamento
  MUST definido (degradar, nunca travar)? [Edge Case, Spec §Edge
  Cases,FR-006] {auto}
  Evidencia: Edge Cases (spec.md:155-158) — "A chamada deve degradar para
  o caminho nativo, nunca travar a onda" — e o mesmo contrato de FR-006
  (tool nao resolvida e uma das causas de indisponibilidade listadas,
  spec.md:236-239).
- [x] CHK020 - O caso de um terceiro orquestrador futuro (arquivo
  `*-orchestrator.md` novo em `plugins/cstk/agents/`) esta coberto sem
  exigir edicao manual do guard? [Edge Case, Spec §Edge Cases,FR-002]
  {auto}
  Evidencia: Edge Case resolvido explicitamente (spec.md:150-154) +
  FR-002 (spec.md:216-220) — deteccao por padrao de nome, "nunca por
  lista hardcodeada dos dois arquivos atuais".

## Dependencias e Premissas

- [x] CHK021 - A premissa revogada por esta feature ("`mcp__*` no
  frontmatter quebra a garantia de degradacao graciosa") esta marcada
  explicitamente como incorreta, com a fonte da sondagem que a revogou?
  [Dependencias, Spec §US1] {auto}
  Evidencia: US1 (spec.md:11-20) afirma textualmente "Uma sondagem
  empirica mostrou que essa premissa esta errada", com a distincao exata
  (so-MCP vs. mista) — nao e so uma mudanca de opiniao sem justificativa.
- [x] CHK022 - O fallback nativo permanece disponivel como premissa em
  TODOS os casos de indisponibilidade listados por FR-006 (servidor
  ausente, tool nao resolvida, sessao nao autenticada, erro pontual)?
  [Dependencias, Spec §FR-006,FR-007] {auto}
  Evidencia: FR-006 (spec.md:236-246) enumera as 4 causas e para cada uma
  "confirmar que o caminho nativo permanece disponivel"; FR-007
  (spec.md:247-252) generaliza isso como garantia MUST preservada, nao
  enfraquecida.
- [Gap] CHK023 - As 7 operacoes MCP tem SLA/timeout de chamada
  documentado que delimite quando uma chamada "esta pendente" vs. "falhou"
  para efeito do fallback de FR-006? [Dependencias, Gap] {auto}
  Nao encontrado em spec.md/plan.md/data-model.md; o contrato citado
  (feature-00c.md:738/agente-00c.md:497) fala em "erro de transporte", que
  cobre falha explicita mas nao define um teto de latencia antes de
  declarar a chamada como erro. Nao bloqueante para esta rodada (FR-010,
  timeout de elicitation, e explicitamente Deferred por fonte pendente) —
  destino: `/clarify` numa proxima rodada se o comportamento observado em
  producao revelar chamadas penduradas sem timeout.

## Rastreabilidade

- [x] CHK024 - Cada uma das 4 user stories se liga a pelo menos um FR e a
  pelo menos um SC? [Traceability] {auto}
  Evidencia: US1→FR-001/002/004/007→SC-001/003; US2→FR-003/004/009→SC-002;
  US3→FR-005/006→(instrumental, sem SC dedicado — ver CHK025);
  US4→FR-008→SC-004.
- [Gap] CHK025 - US3 (orientacao MCP-vs-nativo) tem um Success Criterion
  proprio, ou fica so instrumental as demais? [Traceability, Gap] {auto}
  Nao encontrado SC dedicado a US3/FR-005/FR-006/FR-011 em spec.md
  §Success Criteria (SC-001 a SC-005 cobrem execucao/exposicao/guard/
  token/suite, nenhum mede "orientacao presente e seguida"). A propria
  spec justifica isso ("Why this priority": instrumental para US2 ter
  efeito pratico) — tratamento consciente, nao descuido; registrado aqui
  como Gap de rastreabilidade formal, nao como bloqueio.
- [x] CHK026 - FR-011 (teste de paridade do bloco de orientacao) se liga
  a um requisito de implementacao verificavel (nao so a intencao de
  "nao duplicar")? [Traceability, Spec §FR-011] {auto}
  Evidencia: FR-011 (spec.md:280-284) exige "teste automatizado de
  PARIDADE" entre os dois blocos — verificavel por diff/byte-comparacao,
  coerente com plan.md (Decision 7, blocos byte-identicos delimitados por
  marcadores estaveis).

## Ambiguidades e Conflitos

- [x] CHK027 - FR-010 documenta explicitamente a fonte pendente (sondagem
  em curso, fora do escopo desta execucao) e a razao de nao bloquear as
  demais FRs, sem ambiguidade sobre se e obrigatorio nesta rodada?
  [Ambiguity, Spec §FR-010] {auto}
  Evidencia: FR-010 (spec.md:266-279) — "Deferred — fonte pendente...
  NAO MUST bloquear as demais FRs desta feature — a sondagem empirica que
  mediria esse comportamento esta em curso, fora do escopo desta
  execucao. Nenhum comportamento MUST ser suposto sem essa fonte
  (Principio VI)". Sem ambiguidade: nao resolvido nesta rodada, tratado
  como {humano}/Deferred abaixo (CHK030), NAO reaberto nem suposto aqui.
- [x] CHK028 - Existe conflito real entre FR-003 ("MUST listar as 7 tools
  MCP") e FR-004 ("MUST manter >=1 tool nativa")? [Conflict, Spec
  §FR-003,FR-004] {auto}
  Evidencia: nao ha conflito — sao requisitos aditivos por desenho.
  FR-003 e explicito: "em adicao as (nunca em substituicao das) tools
  nativas ja listadas" (spec.md:222-224); FR-004 formaliza o piso minimo
  do mesmo lado aditivo.

## Risco / Julgamento de Produto

- [ ] CHK029 - A priorizacao P1 (US1+US2) vs. P2 (US3+US4) reflete o
  apetite de risco aceitavel para considerar a feature "utilizavel" se
  apenas as duas P1 forem entregues nesta rodada (orientacao de uso e
  validacao de token ficando para depois)? [Risco, Spec §Priority] {humano}
- [ ] CHK030 - E aceitavel operacionalmente que FR-010 (comportamento de
  elicitation/create sem operador humano) permaneca Deferred sem uma
  data-limite ou gate que impeca merge futuro de uma chamada de
  elicitation por um orquestrador antes da definicao existir? [Risco,
  Spec §FR-010] {humano}

## Notes

- Items `{auto}` ja vem resolvidos pelo agente (`[x]` com citacao, ou
  marcador `[Gap]` quando a evidencia nao foi encontrada nos artefatos).
- Items `{humano}` ficam `[ ]` aguardando decisao do dono do produto —
  CHK029/CHK030 sao julgamento de apetite de risco/prioridade, nao
  verificaveis so com os artefatos.
- Gate `requirement-coverage.sh` sobre `spec.md`: `requirements=12
  covered=12 errors=0` (exit 0) — nenhum FR sem cenario associado;
  nenhum `[Gap]` adicional gerado pelo gate.
- CHK023/CHK025 sao os unicos `[Gap]` deste checklist — ambos de baixo
  risco e com destino explicito (ver secao "Proximos Passos" no relatorio
  desta onda), nenhum bloqueia FR-010 nem a rodada corrente.
