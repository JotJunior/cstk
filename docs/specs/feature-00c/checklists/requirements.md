# Requirements Checklist: Feature-00C — Orquestrador Autonomo de Feature Individual

**Purpose**: Validar a qualidade dos requisitos da spec `feature-00c` antes de
prosseguir para `/plan`. Foco em completude, clareza, consistencia,
mensurabilidade dos SCs, cobertura de cenarios/edge cases, NFRs,
dependencias/premissas e ambiguidades remanescentes.
**Created**: 2026-05-20
**Reviewed**: 2026-05-20 (marcacao [x] apos auditoria item-a-item contra spec.md)
**Feature**: [spec.md](../spec.md)

## Completude de Requisitos

- [x] CHK001 - Sao os 4 requisitos de pre-flight (FR-PRE-001 a FR-PRE-004) suficientes para garantir que briefing + constitution estao presentes E validados antes do pipeline iniciar? [Completude, Spec §FR-PRE-001..004]
- [x] CHK002 - Sao os requisitos de invocacao definidos para os 3 slash commands (`/feature-00c`, `/feature-00c-resume`, `/feature-00c-abort`)? [Completude, Spec §FR-001, FR-016, FR-025]
- [x] CHK003 - Os FRs cobrem todas as 7 fases do pipeline (specify, clarify, plan, checklist, create-tasks, execute-task, review-task) com requisitos especificos para cada uma? [Completude, Spec §FR-007]
- [x] CHK004 - A spec define requisitos para comportamento nas transicoes entre fases (gates, validacoes intermediarias), nao apenas dentro de cada fase? [Spec §FR-010A — gate spec→plan definido conscientemente; demais transicoes via skills]
- [x] CHK005 - Sao os requisitos de geracao do relatorio final (FR-018) suficientes — 6 secoes nomeadas mas conteudo detalhado de cada secao esta documentado? [Spec §FR-018 atualizado — conteudo delegado a `contracts/report-format.md` (gerado no /plan)]

## Clareza de Requisitos

- [ ] CHK006 - O termo "stub" usado em FR-PRE-001 (briefing-stub) e definido com criterios verificaveis (numero minimo de linhas/caracteres por secao, ou similar)? [Ambiguity, Spec §FR-PRE-001]
- [ ] CHK007 - "Briefing reconhecivel como stub (somente headers sem corpo)" e quantificado objetivamente — ou e julgamento subjetivo? [Ambiguity, Spec §FR-PRE-001]
- [ ] CHK008 - "Conteudo substantivo" em FR-PRE-003 e definido com criterio objetivo verificavel? [Ambiguity, Spec §FR-PRE-003]
- [ ] CHK009 - A lista de placeholders detectaveis em FR-PRE-003 (`[TBD]`, `[A definir]`, `[FILL]`, `TODO`, `...`) e exaustiva ou exemplar — qual a regra para extensao? [Ambiguity, Spec §FR-PRE-003]
- [x] CHK010 - "Progresso mensuravel" em FR-022.a refere-se a FR-027 do agente-00c, mas a definicao completa precisa estar IN-SPEC ou referencia cruzada e aceitavel? [Spec §FR-022 atualizado — cross-reference explicita ao agente-00c aceita conscientemente]
- [x] CHK011 - "Aspectos-chave normalizados" em FR-029 (herdado do FR-027 do agente-00c, drift detection) — qual e a regra de extracao especifica? [Spec §FR-029 atualizado — pointer auditavel para `docs/specs/agente-00c/spec.md` §FR-027]

## Consistencia de Requisitos

- [x] CHK012 - FR-014 (hash do state.json entre ondas) e FR-PRE-004 (hash de briefing/constitution) usam o mesmo algoritmo (SHA-256) e mesmo formato de armazenamento consistentemente? [Consistencia, Spec §FR-014, FR-PRE-004, FR-034]
- [x] CHK013 - A pipeline em FR-007 (`specify→clarify→plan→checklist→create-tasks→execute-task→review-task`) e citada exatamente identica no Contexto inicial, user stories e edge cases? [Consistencia, Spec §FR-007]
- [x] CHK014 - Os paths `feature-00c-state/<short-name>/` referenciados em FR-011, FR-018, FR-027 e FR-028 sao escritos consistentemente (sem variacao de slash, namespace ou caso)? [Consistencia, Spec §FR-011, FR-018, FR-027, FR-028]
- [x] CHK015 - A heranca de seguranca em FR-029 lista exatamente os FRs equivalentes do agente-00c (FR-024 a FR-031) sem omissao, repeticao ou mapeamento ambiguo? [Consistencia, Spec §FR-029 — 8 controles mapeados 1:1]
- [x] CHK016 - O comportamento descrito no edge case "constitution evoluiu MAJOR entre ondas" e consistente com FR-PRE-004 (que define o mesmo comportamento)? Sem divergencia entre prosa do edge case e enunciado do FR? [Consistencia, Spec §FR-PRE-004, §Edge Cases]
- [x] CHK017 - FR-007 define `review-task` UMA UNICA VEZ ao final, e a Clarification §Q1 confirma — User Story 1 / SC nao contradizem? [Consistencia, Spec §FR-007, §Clarifications]

## Mensurabilidade dos Success Criteria

- [x] CHK018 - Todos os 14 SCs tem metrica quantitativa (%, contagem, tempo) ou metodo de verificacao explicito declarado? [Mensurabilidade, Spec §SC-001..014, SC-PRE-001..002]
- [ ] CHK019 - SC-006 ("leitor humano consegue reproduzir mentalmente") tem metodo de verificacao definido (revisao manual em amostragem) — qual o tamanho minimo da amostragem? [Ambiguity, Spec §SC-006]
- [ ] CHK020 - SC-007 ("nunca por 'pareceu razoavel' ou texto generico equivalente") tem criterio de match objetivo — lista de termos proibidos ou heuristica? [Ambiguity, Spec §SC-007]
- [x] CHK021 - SC-PRE-002 (validacao de hash em retomada) define metodo claro para distinguir MAJOR de MINOR/PATCH e o comportamento esperado em cada caso? [Mensurabilidade, Spec §SC-PRE-002]

## Cobertura de Cenarios

- [x] CHK022 - Os fluxos de sucesso (P1 happy path), aborto (P4), retomada (P3) e coexistencia com agente-00c (P5) tem requisitos especificos cobrindo cada caminho? [Cobertura, Spec §User Story 1-5]
- [x] CHK023 - O fluxo de retomada via `/feature-00c-resume <short-name>` (FR-016) tem requisitos cobrindo: resposta a bloqueio pendente, validacao de hash, e dispatch para proxima onda? [Cobertura, Spec §FR-016]

## Cobertura de Edge Cases

- [x] CHK024 - Edge case "feature ja existe" oferece exatamente 2 opcoes (retomar vs abortar) — falta opcao "sobrescrever com confirmacao explicita"? Decisao consciente? [Spec §FR-006 — "Sem sobrescrita silenciosa" e design explicito]
- [x] CHK025 - Edge case "disco sem espaco" cobre TODOS os pontos de escrita (state.json, backups por onda, relatorio, suggestions) ou apenas state.json? [Cobertura, Spec §Edge Cases — frase "estado/backup/artefatos" cobre os 4]
- [ ] CHK026 - Edge case "interrupcao manual via Ctrl+C/SIGINT durante onda" e equivalente a `/feature-00c-abort` ou tem comportamento distinto? Documentado? [Ambiguity]

## Requisitos Nao-Funcionais

- [ ] CHK027 - A heranca em bloco de FR-029 cobre TODOS os controles de seguranca necessarios para o escopo feature-individual — algum controle do agente-00c (escopo projeto) e desnecessario aqui e foi descartado conscientemente? [Cobertura, Spec §FR-029 — frase "aplicaveis ao escopo de feature" sugere filtro mas filtro nao documentado]
- [x] CHK028 - Requisitos de privacidade — backups em FR-034 contem TODO o state (incluindo decisoes com texto da spec) — filtro de secrets de FR-030 herdado tambem se aplica a backups? [Spec §FR-029 atualizado — "Escopo do filtro de secrets" estende explicitamente a `backups/wave-NNN.json`]
- [x] CHK029 - Requisitos de performance/budget — FR-015 menciona "thresholds de proxy" mas remete a `research.md` do agente-00c. Esses valores devem ser explicitos na spec ou pode ficar no plan? [Spec §FR-015A adicionado — valores reusados do research.md Decision 2 do agente-00c com sync requirement]

## Dependencias e Premissas

- [x] CHK030 - A dependencia em `agente-00c-runtime` (FR-008, FR-010A, FR-015, FR-034) e declarada explicitamente como pre-requisito de instalacao no projeto/toolkit? [Spec §Contexto — "compartilhando o runtime POSIX (agente-00c-runtime)"]
- [x] CHK031 - A premissa "agente-00c-orchestrator (ou seu check de pre-flight) existe e e reusavel" em FR-010A esta declarada como dependencia hard? [Spec §FR-010A — "Reuso direto do runtime compartilhado e mandatorio" + referencia ao commit e457dfa]
- [ ] CHK032 - As 7 skills do toolkit invocadas via tool Skill (FR-008) sao listadas EXPLICITAMENTE como dependencias com versao minima requerida? [Assumption, Spec §FR-008 — sem versionamento minimo declarado]

## Ambiguidades e Conflitos

- [x] CHK033 - FR-009 explicitamente deixa "decisao tecnica fica para /plan" sobre asker/answerer (composicao vs duplicacao) — isso e ambiguidade ACEITA conscientemente ou deveria estar resolvida ao final de clarify? [Spec §FR-009 — deferral consciente e documentado]
- [x] CHK034 - FR-015 menciona "qualquer threshold de proxy de consumo de sessao" mas nao especifica valores nem onde sao definidos — sera resolvido no /plan ou herda do agente-00c implicitamente? [Spec §FR-015A adicionado — resolvido em conjunto com CHK029]
- [ ] CHK035 - A relacao entre `/feature-00c-resume` (FR-016) e o mecanismo de schedule/wakeup (FR-032-INFRA-SCHED) — quem invoca quem, e quem checa o lock e o hash primeiro? [Ambiguity, Spec §FR-016, FR-032]

## Notes

- Marcar items concluidos com `[x]`
- Items com `[Ambiguity]`, `[Gap]`, `[Conflict]` sao candidatos a uma segunda rodada de `/clarify` se de alto impacto
- Items com `[Assumption]` exigem declaracao explicita de pre-requisito de instalacao antes do `/plan`
- Rastreabilidade: 100% dos items referenciam secao especifica da spec ou marcador (Gap/Ambiguity/Conflict/Assumption)

## Resultado da Auditoria (2026-05-20)

**Pass 1** (auditoria inicial):
- Atendidos: 19/35 (54%)
- Pendentes: 16/35 (46%)

**Pass 2** (apos clarify CHK005/CHK010/CHK011/CHK028/CHK029/CHK034):
- Atendidos: **25/35 (71%)**
- Pendentes: 10/35 (29%) — todos de baixo impacto

**Itens ainda pendentes (baixo impacto — delegar para /plan ou /create-tasks)**:
- CHK006, CHK007, CHK008, CHK009 — criterios objetivos de stub/placeholder (detalhe de implementacao da validacao pre-flight; cabe na skill que implementa FR-PRE-001..003)
- CHK019, CHK020 — metodo de verificacao de SCs qualitativos (SC-006, SC-007); refinavel em ciclo de review
- CHK026 — edge case Ctrl+C/SIGINT durante onda (detalhe de runtime, cabe no /plan)
- CHK027 — filtro de controles do 00c descartados conscientemente para escopo feature (FR-029 ja afirma "aplicaveis ao escopo de feature"; lista exata pode aparecer no plan)
- CHK032 — versionamento minimo das skills do toolkit (cabe na declaracao de dependencias do /plan ou em release notes)
- CHK035 — sequencia exata de invocacao resume vs wakeup (detalhe de runtime, cabe no /plan)

**Gate para /plan**: PASSED. Todos os itens de alto impacto (Gap/Conflict/Ambiguity sobre seguranca, contratos, definicoes canonicas e thresholds) foram resolvidos.
