# Requirements Checklist: wave-token-metrics

**Purpose**: validar qualidade, clareza, completude e rastreabilidade dos
requisitos de `spec.md` e do desenho tecnico de `plan.md` — nao valida
implementacao (ainda inexistente).
**Created**: 2026-07-25
**Feature**: [spec.md](../spec.md) · [plan.md](../plan.md)

## Completude de Requisitos

- [x] CHK001 - Os requisitos funcionais cobrem tokens (total + 4 categorias), tool-uses e duracao para cada spawn concluido? [Completude, Spec §FR-001, §FR-002] {auto}
  - Satisfeito: FR-001 exige "total agregado e um breakdown por categoria (input, output, cache-read, cache-creation)"; FR-002 exige "contagem de tool-uses" e "duracao" — ambos MUST.
- [x] CHK002 - Requisitos nao-funcionais (seguranca/zero-egress/observabilidade) estao cobertos? [Completude] {auto}
  - Satisfeito: Plan §Constitution Check, Principio IV — "todo dado permanece local... Nenhum egress, nenhum endpoint, nenhum identificador enviado a lugar algum. O hook nao faz rede."
- [ ] CHK003 - Existe uma secao explicita de "Fora de Escopo" na spec? [Completude] {auto} [Gap]
  - Nao satisfeito: `spec.md` nao tem heading dedicado de fora-de-escopo. Ha apenas fronteiras implicitas em "Assumptions & Dependencies" (linha 308-309: "Esta feature nao especifica o schema de armazenamento nem o formato exato dos campos de captura — isso e decisao tecnica de `/plan`"). O plan.md preenche a lacuna tecnica (Data Model, contracts), mas a spec em si carece do heading formal.
- [x] CHK004 - Dependencias externas (harness `PostToolUse` matcher `Agent`, `jq`, `sqlite3`) estao documentadas? [Completude, Spec §Assumptions & Dependencies] {auto}
  - Satisfeito: Spec §Assumptions cita as duas fontes de dados observadas; Plan §Technical Context declara `jq`/`sqlite3` como deps opcionais ja confinadas, "Nenhuma dep nova e introduzida."
- [x] CHK005 - Premissas de fonte de dados sao apoiadas por evidencia observada (nao suposicao)? [Completude, Spec §Assumptions & Dependencies] {auto}
  - Satisfeito: Spec linhas 274-289 cita transcript real com correspondencia numerica (`tokens=106664, tool-uses=38`) contra o que foi exibido ao operador na mesma onda — evidencia citavel, nao suposicao.
- [x] CHK006 - Ha fallback definido para dependencia/fonte indisponivel (hook nao provisionado, `jq` ausente)? [Completude, Spec §FR-008] {auto}
  - Satisfeito: FR-008 MUST best-effort; Plan §Riscos R2 antecipa explicitamente "o hook de `tool_calls` nao esta provisionado" neste proprio repo e define a mitigacao (relatorio distingue "0 spawns" de "metrica nao coletada").

## Clareza de Requisitos

- [x] CHK007 - Cada requisito funcional usa verbo MUST/SHOULD testavel? [Clareza, Spec §Functional Requirements] {auto}
  - Satisfeito: 12/12 FRs usam MUST, exceto FR-010 (SHOULD, justificado por prioridade P4/fase separada — nao e ambiguidade, e escolha deliberada de escopo).
- [x] CHK008 - Os termos de status ("indisponivel", "parcial", "nao-aplicavel") estao definidos com semantica exata (nao apenas rotulo vago)? [Clareza, Spec §FR-009, §FR-012, §Key Entities] {auto}
  - Satisfeito: §Key Entities enumera o enum fechado — "completo, parcial (dado ate o momento de uma falha, apenas quando observavel) ou indisponivel (nenhum dado observavel) — nunca estimada".
- [x] CHK009 - Todas as marcacoes de clarificacao/placeholder (`[NEEDS CLARIFICATION]`, TODO) foram resolvidas? [Clareza] {auto}
  - Satisfeito: `grep -ni 'NEEDS CLARIFICATION\|TODO\|TKTK'` sobre spec.md retornou zero ocorrencias; secao "## Clarifications / Session 2026-07-25" registra 5 perguntas, todas com resposta objetiva.
- [x] CHK010 - "Best-effort" (FR-008) esta operacionalmente definido, nao apenas rotulado? [Clareza, Spec §FR-008] {auto}
  - Satisfeito: FR-008 define o comportamento exato — "a ausencia ou malformacao da fonte de dados de uso subjacente MUST NOT abortar nem bloquear a onda".

## Consistencia de Requisitos

- [x] CHK011 - Os requisitos sao consistentes com os principios da constitution do projeto? [Constitution Alignment] {auto}
  - Satisfeito: Plan §Constitution Check lista os 6 principios — todos `PASS` ou `PASS parcial/N/A` justificado, nenhuma violacao aberta (confirmado por "Veredito: mantido PASS em todos os principios" no re-check pos-Phase 1).
- [x] CHK012 - A terminologia e consistente entre spec (Key Entities) e o desenho tecnico (plan/data-model)? [Consistencia] {auto}
  - Satisfeito: `data-model.md` §"Mapeamento requisito -> campo" traduz 1:1 "Metrica de Uso de Spawn" (spec) para a entidade tecnica `SpawnUsage` (plan/data-model), sem introduzir conceito paralelo.
- [x] CHK013 - FR-010 (SHOULD, prioridade menor) nao contradiz os MUST de captura ao vivo (FR-001/002/003)? [Consistencia, Spec §FR-010] {auto}
  - Satisfeito: Plan §"Fases de implementacao sugeridas" declara F1-F3 (US1, captura ao vivo) "independentes de F4-F6"; F6 (backfill/FR-010) e isolado e nao bloqueia nem e bloqueado pelos MUST.

## Mensurabilidade / Success Criteria

- [x] CHK014 - Cada Success Criterion e objetivamente verificavel, sem termo vago? [Mensurabilidade, Spec §Success Criteria] {auto}
  - Satisfeito: SC-001 ("100% dos spawns... quando a fonte estava disponivel"), SC-004 ("100% dos relatorios marcam... explicitamente") e SC-003 ("sem precisar fazer calculo manual fora do toolkit") sao todos criterios binarios/verificaveis, sem adjetivo vago.
- [x] CHK015 - SC-004 (nunca inventar) tem criterio de verificacao concreto, alem da intencao? [Mensurabilidade, Spec §SC-004] {auto}
  - Satisfeito: redacao e binaria e auditavel — "100% dos relatorios marcam a metrica... nunca exibem um numero inventado ou um zero apresentado como valor real" e diretamente checavel contra a saida de qualquer relatorio gerado.
- [ ] CHK016 - A meta "100%" de SC-001/SC-004 e realista/aceitavel dado que ~50% dos spawns reais nao tem `usage` (`async_launched`, achado do plan)? [Risco, Spec §SC-001, Plan §Summary "achado que molda o desenho"] {humano}
  - Depende de julgamento de risco/expectativa do dono do produto: o 100% e formalmente correto (esta condicionado a "quando a fonte de dados de uso estava disponivel"), mas comunicar essa condicional aos stakeholders sem gerar percepcao de metrica "quebrada" e decisao de produto, nao de qualidade textual do requisito.

## Cobertura de Cenarios

- [x] CHK017 - O happy path (spawn unico concluido normalmente) esta coberto? [Cobertura, Spec §US1 AS1] {auto}
  - Satisfeito: US1 Acceptance Scenario 1 cobre exatamente esse caso; Quickstart Cenario 1 (§"Captura ao vivo de um spawn concluido (SC-001)") da o teste executavel correspondente.
- [x] CHK018 - O cenario de multiplos spawns paralelos na mesma onda esta coberto (atribuicao individual + agregado)? [Cobertura, Spec §US1 AS2, §Edge Cases] {auto}
  - Satisfeito: US1 AS2 e a 3a pergunta de Edge Cases tratam exatamente disso; Quickstart Cenario 3 ("Onda mista: metade dos spawns sem usage") exercita o caso real observado no proprio projeto.
- [x] CHK019 - O cenario de falha/aborto parcial de spawn esta coberto (dado parcial vs indisponivel)? [Cobertura, Spec §FR-012, §Edge Cases] {auto}
  - Satisfeito: FR-012 e o 1o item de Edge Cases descrevem o comportamento exato (parcial se observavel, indisponivel senao); resolvido nesta sessao (marcado "RESOLVIDO" no bloco Clarifications).
- [x] CHK020 - O cenario de execucoes concorrentes no mesmo projeto (atribuicao sem mistura entre execucoes) esta coberto? [Cobertura, Spec §Edge Cases] {auto}
  - Satisfeito: ultimo item de Edge Cases + Clarifications Q3 exigem identificador de execucao explicito na Metrica de Uso de Spawn, precedente citado (coluna `session` do knowledge.db v8).
- [x] CHK021 - O cenario de reconstrucao retroativa com dados ja removidos do disco (recusa explicita) esta coberto? [Cobertura, Spec §FR-011, §US4 AS2] {auto}
  - Satisfeito: FR-011 MUST + US4 Acceptance Scenario 2 definem a recusa explicita; Quickstart Cenario 10 ("Backfill recusa explicita (FR-011)") da o teste correspondente.
- [x] CHK022 - O gate deterministico de cobertura de cenarios (`requirement-coverage.sh`) confirma que todo FR tem cenario associado? [Cobertura] {auto}
  - Satisfeito: `RESULT|docs/specs/wave-token-metrics/spec.md|requirements=12|covered=12|errors=0` (exit 0) — registrado como Decisao dec-033 nesta onda.

## Requisitos Nao-Funcionais

- [x] CHK023 - O requisito de nao-bloqueio (fail-open) tem restricao qualitativa explicita, mesmo sem alvo numerico de latencia? [Nao-Funcional, Plan §Technical Context "Constraints"] {auto}
  - Satisfeito: Plan declara restricao dura "(a) hook MUST NOT escrever no state.json... " e "o hook MUST NOT bloquear, atrasar ou reprovar uma tool call (fail-open)", reusando o teto `timeout: 5` ja praticado pelos hooks existentes.
- [ ] CHK024 - A ausencia deliberada de alvo numerico de performance/latencia (plan declara "N/A quantitativo") e aceitavel para este release, ou o operador quer um teto explicito adicional? [Risco, Plan §Technical Context "Performance Goals"] {humano}
  - Depende de apetite de risco do dono do produto — a spec/plan documentam a ausencia honestamente (nao fabricam um numero), mas decidir se isso e suficiente para aprovar o release e julgamento de negocio.

## Dependencias e Premissas

- [x] CHK025 - A fonte de dados do payload do hook foi verificada contra doc oficial, nao suposta? [Assumption, Spec §Assumptions & Dependencies, Plan §Constitution Check Principio VI] {auto}
  - Satisfeito: Plan cita fonte primaria rastreavel — "Todo campo do payload do harness citado nos contratos foi extraido da doc oficial baixada e lida (`https://code.claude.com/docs/en/hooks.md`, 2026-07-25) e cruzado com transcripts reais."
- [x] CHK026 - O "risco em aberto" declarado na spec (payload exato do hook nao verificado) foi endereçado antes do plan avancar para o design? [Assumption, Spec §Assumptions & Dependencies "Risco em aberto"] {auto}
  - Satisfeito: Plan §Summary confirma que "o unknown central da spec... foi resolvido com fonte oficial" no Phase 0 (`research.md` Decision 1), fechando o risco antes da Fase 1 (design).
- [x] CHK027 - A spec distingue corretamente entre a decisao historica anterior ("harness nao expoe tokens a scripts/env") e o canal novo assumido por esta feature (transcript/tool_response)? [Consistencia, Spec §Assumptions & Dependencies "Nao contradiz decisao historica"] {auto}
  - Satisfeito: paragrafo dedicado explica que a conclusao anterior vale so para o canal de env vars testado, e que o canal desta feature (dado persistido em disco / tool_response) e diferente e nao testado por aquela decisao — evita contradicao aparente.

## Rastreabilidade

- [x] CHK028 - Cada User Story se liga a Requisitos Funcionais especificos? [Traceability] {auto}
  - Satisfeito: `data-model.md` §"Mapeamento requisito -> campo" cobre os 12/12 FRs com campo tecnico correspondente, e cada FR ja cita a User Story de origem no proprio corpo da spec (US1: FR-001/002/003/004/005/008/009; US2: FR-007; US3: FR-006; US4: FR-010/011).
- [x] CHK029 - Os Success Criteria se ligam a Requisitos/User Stories de forma rastreavel (nao numeros soltos)? [Traceability, Spec §Success Criteria] {auto}
  - Satisfeito: `quickstart.md` amarra cada cenario executavel a um par explicito FR+SC (ex.: "Cenario 1 — Captura ao vivo de um spawn concluido (SC-001)", "Cenario 6 — Custo x modelo roteado (SC-003, FR-007)").

## Ambiguidades e Conflitos

- [x] CHK030 - Todas as ambiguidades levantadas na sessao de clarify foram resolvidas com decisao explicita (nao "manter em aberto")? [Ambiguity, Spec §Clarifications] {auto}
  - Satisfeito: 5/5 perguntas da sessao 2026-07-25 tem resposta objetiva (`→ A:`); nenhuma ficou com resposta ambigua ou "a definir depois".
- [x] CHK031 - Ha conflito entre o MUST de FR-009 (nunca fabricar) e alguma pressao de completude (ex.: exibir 100% de cobertura)? [Conflict] {auto}
  - Nao satisfeito nao se aplica — verificado, sem conflito: SC-001/SC-004 condicionam explicitamente o 100% a disponibilidade da fonte ("quando a fonte de dados de uso estava disponivel"), preservando FR-009 sem criar pressao para fabricar dado ausente.

## Notes

- Items `{auto}` ja vem resolvidos pelo agente (`[x]` com citacao, ou marcador `[Gap]`).
- Items `{humano}` ficam `[ ]` aguardando decisao do dono do produto.
- **{auto} resolvidos**: 27
- **{humano} aguardando decisao**: 2 (CHK016, CHK024)
- **Gaps abertos**: 1 (CHK003 — `[Gap]`, secao "Fora de Escopo" ausente na spec)
- Gate `requirement-coverage.sh`: `requirements=12|covered=12|errors=0` (exit 0) — nenhum `[Gap]` adicional de cenario-por-FR foi necessario (ver CHK022).
