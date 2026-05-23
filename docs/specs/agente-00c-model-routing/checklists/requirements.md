# Requirements Checklist: agente-00c-model-routing

**Purpose**: Quality gate ("unit tests for English") sobre os requisitos
escritos em `../spec.md`. Valida completude, clareza, consistencia,
mensurabilidade, rastreabilidade e cobertura — antes de avancar para
`/create-tasks`.

**Created**: 2026-05-22 (onda-004)
**Feature**: [spec.md](../spec.md)
**Domain**: requirements
**Reviewer**: agente-00c-feature-orchestrator (onda-004)

---

## Completude de Requisitos

- [ ] CHK001 - Cada Functional Requirement tem ID unico no formato `FR-NNN` sem gaps nem duplicatas entre FR-001..FR-020? [Completude, Spec §Functional Requirements]
- [ ] CHK002 - Sao os requisitos de invocacao do `model-selector` definidos para AMBOS os orquestradores (`agente-00c-orchestrator` e `agente-00c-feature-orchestrator`)? [Completude, Spec §FR-001, §FR-016]
- [ ] CHK003 - Sao os requisitos de registro auditavel definidos para os 5 campos obrigatorios + agente + etapa? [Completude, Spec §FR-003]
- [ ] CHK004 - Sao os requisitos de audit trail definidos para o campo `skills_invoked[]` na onda corrente? [Completude, Spec §FR-004]
- [ ] CHK005 - A spec define template de input para CADA `subagent_type` do escopo (asker e answerer, em ambos orquestradores = 4 tipos)? [Completude, Spec §FR-002, Key Entities — Template de input]
- [ ] CHK006 - Sao os requisitos de fallback definidos para os 3 modos de falha (skill ausente, exit nao-zero, output mal-formado)? [Completude, Spec §FR-008, US-2 Acceptance Scenarios 1-3]
- [ ] CHK007 - Sao os requisitos de mapeamento de score (skill 0..2 → runtime 0..3) definidos com tabela explicita? [Completude, Spec §FR-005]
- [ ] CHK008 - A spec define ordem exata da sequencia pre-spawn (`spawn-tracker check` → invocar skill → registrar Decisao → record-skill → `spawn-tracker enter` → tool Agent)? [Completude, Spec §FR-010, §FR-011, §FR-016]
- [ ] CHK009 - Sao os requisitos de idempotencia em retomadas definidos com chave de deduplicacao explicita? [Completude, Spec §FR-012]
- [ ] CHK010 - A spec cobre o requisito de NAO-aplicacao automatica do modelo (suggest-only)? [Completude, Spec §FR-017]

## Clareza de Requisitos

- [ ] CHK011 - Cada FR usa palavra normativa (MUST / MUST NAO / SHALL) sem mistura com verbos imprecisos ("deveria", "poderia", "talvez")? [Clareza, Spec §FR-001..§FR-020]
- [ ] CHK012 - E o termo "fallback" definido com criterios objetivos (escolha=`fallback-default`, score=0, justificativa contendo motivo, NAO bloqueia)? [Clareza, Spec §FR-008, §FR-009]
- [ ] CHK013 - E "input excede 4096 chars" quantificado com regra de truncagem exata (2000 + marcador literal + 2000 = 4016)? [Clareza, Spec §FR-013]
- [ ] CHK014 - E "tarefa do subagente" definida com 3 partes objetivas (perfil + entradas esperadas + saida esperada)? [Clareza, Spec §FR-001, §FR-002]
- [ ] CHK015 - E "sinais detectados" referenciado com origem exata (secao `## Sinais detectados` do markdown de saida da skill)? [Clareza, Spec §FR-006]
- [ ] CHK016 - E "output mal-formado" definido com criterio testavel (faltando secao `## Sugestao` ou campo `modelo`)? [Clareza, Spec §FR-008]
- [ ] CHK017 - Cada FR esta livre de modificadores vagos ("etc.", "como apropriado", "se necessario", "razoavel")? [Clareza, Spec §Functional Requirements — leitura linha-a-linha]
- [ ] CHK018 - E o limite de 200 chars do stderr (FR-008) ancorado em decisao explicita ou e numero arbitrario? [Clareza/Ambiguity, Spec §FR-008]

## Consistencia entre FRs / Edge Cases / Success Criteria

- [ ] CHK019 - A chave de idempotencia em FR-012 (`contexto matchando "Selecao de modelo para subagente <subagent_type>" AND onda_id == onda_corrente`) e consistente com o pattern de `contexto` em Key Entities (§Decisao de selecao de modelo)? [Consistencia, Spec §FR-012, §Key Entities]
- [ ] CHK020 - O conjunto de rotulos validos em `--escolha` (`haiku`/`sonnet`/`opus`/`manter-atual`/`fallback-default`) e identico em FR-007, FR-008, US-1 Acceptance Scenario 1, e SC-001? [Consistencia, Spec §FR-007, §FR-008, US-1 AS1, §SC-001]
- [ ] CHK021 - O Edge Case "Spawn em depth maxima" e refletido em FR explicito (FR-010)? [Consistencia, Spec §Edge Cases item 1, §FR-010]
- [ ] CHK022 - O Edge Case "Multiplas retomadas dentro da mesma fase" e coberto por FR-012 (idempotencia) sem contradicao? [Consistencia, Spec §Edge Cases item 5, §FR-012]
- [ ] CHK023 - O Edge Case "Mesma onda spawna asker, recebe `perguntas: []`, NAO spawna answerer" e consistente com FR-015 (1 Decisao por spawn REAL, nao potencial)? [Consistencia, Spec §Edge Cases item 4, §FR-015]
- [ ] CHK024 - O Edge Case "Score 0 do answerer" — invariante de que Decisao tecnica do orquestrador NAO dispara pause-humano — e coberto por FR-009? [Consistencia, Spec §Edge Cases item 2, §FR-009]
- [ ] CHK025 - O Edge Case "Input excede 4096 chars" e totalmente coberto por FR-013 (sem residuo de ambiguidade)? [Consistencia, Spec §Edge Cases item 6, §FR-013]
- [ ] CHK026 - FR-014 (compatibilidade com `agente-00c-artifact-cache`) e consistente com SC-004 (testes de regressao com cache ON)? [Consistencia, Spec §FR-014, §SC-004]
- [ ] CHK027 - FR-017 (manter como sugestao) e consistente com Out-of-Scope item 1 (aplicacao automatica fora do escopo)? [Consistencia, Spec §FR-017, §Out-of-Scope item 1]

## Mensurabilidade de Success Criteria

- [ ] CHK028 - SC-001 ("100% dos spawns geram Decisao matchando pattern") e objetivamente verificavel via jq sobre `state.json`? [Mensurabilidade, Spec §SC-001]
- [ ] CHK029 - SC-002 ("ate 3 tool calls extras por spawn") e quantificado com fonte de medicao (`state.json.metricas.tool_calls_total` antes/depois)? [Mensurabilidade, Spec §SC-002]
- [ ] CHK030 - SC-005 ("0 bloqueios humanos com skill desinstalada") tem procedimento de teste de regressao reproduzivel (renomear pasta da skill)? [Mensurabilidade, Spec §SC-005, US-2 Independent Test]
- [ ] CHK031 - SC-006 ("<2s por invocacao em maquina dev tipica") tem metodo de verificacao definido (comparacao de timestamps de Decisoes consecutivas)? [Mensurabilidade, Spec §SC-006]
- [ ] CHK032 - SC-003 ("agregado contendo distribuicao por subagente no review-task") tem path-de-arquivo concreto de saida ou esta TBD? [Mensurabilidade/Ambiguity, Spec §SC-003 — observar "(ou onde quer que `review-task` salve)"]

## Cobertura de Edge Cases

- [ ] CHK033 - Sao cobertos os 6 Edge Cases enumerados na spec, cada um com FR ou Acceptance Scenario correspondente? [Cobertura, Spec §Edge Cases]
- [ ] CHK034 - A spec considera Edge Case adicional: subagent_type fora do enum esperado (asker/answerer)? [Gap potencial, Spec §FR-002 — enum nao re-validado para tipos futuros]
- [ ] CHK035 - A spec considera Edge Case: `model-selector` retorna rotulo nao mapeado (ex: novo tier `gemini`)? [Gap potencial, Spec §FR-007 — assume enum fechado]
- [ ] CHK036 - A spec considera Edge Case: `state-decisions.sh register` falha por state.json corrompido durante FR-003? [Gap potencial, Spec §FR-003 — sem path de erro]

## Rastreabilidade

- [ ] CHK037 - Cada Decisao de Infraestrutura Auditavel (Q1..Q5 do clarify, dec-003..dec-007) tem entrada na tabela §Decisoes de Infraestrutura Auditaveis com FR correspondente? [Rastreabilidade, Spec §Clarifications, §Decisoes de Infraestrutura Auditaveis]
- [ ] CHK038 - Cada User Story (US-1, US-2, US-3) tem pelo menos 1 SC mapeado de volta (SC-001/SC-005 → US-1+US-2; SC-003 → US-3)? [Rastreabilidade, Spec §User Scenarios, §Success Criteria]
- [ ] CHK039 - Cada item Out-of-Scope tem justificativa explicita ligada a um Principio da constitution ou a uma DIA original? [Rastreabilidade, Spec §Out-of-Scope items 1-5]
- [ ] CHK040 - As 5 entradas em §Clarifications (Q1..Q5) tem decisao-id auditavel (dec-003..dec-007) verificavel em `state.json`? [Rastreabilidade, Spec §Clarifications]

## Out-of-Scope e Limites Explicitos

- [ ] CHK041 - Out-of-Scope item 1 (aplicacao automatica) define explicitamente que mudanca futura requer nova feature? [Cobertura de limite, Spec §Out-of-Scope item 1]
- [ ] CHK042 - Out-of-Scope item 2 (cache cross-onda) define gatilho concreto para revisitacao ("se houver evidencia de custo proibitivo")? [Cobertura de limite, Spec §Out-of-Scope item 2]
- [ ] CHK043 - Out-of-Scope item 3 (outros pontos de delegacao alem de clarify) confirma que aplicar a fases futuras e "mudanca incremental trivial" — afirmacao testavel via FR-016? [Cobertura de limite, Spec §Out-of-Scope item 3, §FR-016]
- [ ] CHK044 - Out-of-Scope item 4 (NAO modificar skill model-selector) e consistente com Principio III (formato canonico)? [Cobertura de limite, Spec §Out-of-Scope item 4, §Constitution Alignment]

## Estado de Clarificacao

- [ ] CHK045 - Status declarado "0 ambiguidades pendentes" em §Open Ambiguities e verificavel — nao ha marcadores `[NEEDS CLARIFICATION]`, `TBD`, `???` no corpo da spec? [Completude/Clareza, Spec §Open Ambiguities — confirmar via grep]
- [ ] CHK046 - Todas as 5 DIAs (Q1..Q5) da tabela §Decisoes de Infraestrutura Auditaveis tem status "Resolvida" (sem "Pendente" / "TBD")? [Completude, Spec §Decisoes de Infraestrutura Auditaveis]

## Ambiguidades / Conflitos / Riscos

- [ ] CHK047 - Existe ambiguidade em FR-018 — termo "agregar" e operacional ("derivacao real-time via jq") mas o FORMATO do agregado no relatorio nao e especificado (markdown? json? tabela?). Precisa clarify? [Ambiguity, Spec §FR-018, §SC-003]
- [ ] CHK048 - Existe possivel conflito: SC-002 limita "3 tool calls extras por spawn" mas a sequencia FR-010+FR-011 + idempotency check (jq) + invoke + register + record-skill totaliza >3 calls em sh — esses contam como tool calls do harness ou apenas as chamadas de Skill/Bash de alto nivel? [Conflict, Spec §SC-002, §FR-003, §FR-004, §FR-012]
- [ ] CHK049 - Existe assumption nao documentada: FR-006 cita literalmente sinais da skill — assume-se que o output da skill e estavel entre versoes, mas spec nao referencia versao minima da skill `model-selector`? [Assumption, Spec §FR-006, §References]
- [ ] CHK050 - Existe risco implicito de seguranca: o template em FR-002 e free-form text passado a sub-processo POSIX — nao ha requisito de quoting/escape no input. Cobertura adequada ou requer FR adicional? [Gap, Spec §FR-002, cross-ref OWASP gate F-001 onda-004]

---

## Notes

- Marcar items como `[x]` ao validar; items nao-marcados ao fim do checklist representam debito de clareza que pode reabrir `/clarify` ou virar tasks no `/create-tasks`.
- Items `[Gap]`, `[Ambiguity]`, `[Conflict]`, `[Assumption]` sao candidatos diretos a nova sessao de clarify se forem load-bearing — ou a Out-of-Scope explicito se nao forem.
- Rastreabilidade: 49/50 items (98%) com referencia direta a `[Spec §X]` ou marcador de gap, acima do minimo de 80%.
- Cobertura de FRs: todos os 20 FRs aparecem em pelo menos 1 item de validacao.
- Items load-bearing para `/create-tasks`:
  - CHK032, CHK047 → onde o agregado de review-task aparece e em que formato?
  - CHK048 → contagem exata de tool calls atravessa SC-002.
  - CHK050 → cross-ref com finding F-001 do owasp-security gate (onda-004).
