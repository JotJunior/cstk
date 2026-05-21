# Requirements Quality Checklist: Agente-00C

**Purpose**: validar qualidade dos requisitos da feature agente-00C antes de
decompor em backlog (`/create-tasks`). Foco em completude, clareza,
consistencia, mensurabilidade e cobertura — nao em verificar implementacao.
**Created**: 2026-05-05
**Feature**: [spec.md](../spec.md)

---

## Completude de Requisitos

- [ ] CHK001 - Toda user story tem pelo menos 1 acceptance scenario no formato Given/When/Then? [Completude, Spec §User Scenarios]
- [ ] CHK002 - Toda etapa da pipeline (briefing, constitution, specify, clarify, plan, checklist, create-tasks, execute-task, review-task, review-features) tem comportamento especificado em FRs? [Completude, Spec §FR-004]
- [ ] CHK003 - Toda transicao do diagrama de estado da Execucao (`em_andamento → aguardando_humano → em_andamento`, etc) tem o trigger documentado? [Completude, data-model.md §Execucao]
- [ ] CHK004 - Cada gatilho de aborto listado em FR-014 (loop, movimento circular, impossibilidade tecnica, desvio de finalidade, bug em skill global) tem cenario correspondente em quickstart.md? [Completude, Spec §FR-014]
- [ ] CHK005 - O comportamento ao atingir 80% janela semanal esta especificado, dado que pesquisa mostrou ausencia de proxy confiavel? [Gap, Spec §FR-009]
- [ ] CHK006 - Existe requisito para o caso de operador renomear ou mover o diretorio do projeto-alvo durante uma execucao em curso? [Gap]
- [ ] CHK007 - Existe requisito para multiplas execucoes 00C concorrentes em projetos-alvo distintos (ou explicitamente fora de escopo)? [Gap]
- [ ] CHK008 - Comportamento quando disco fica sem espaco para escrever estado/backup esta especificado? [Gap, Spec §FR-007]
- [ ] CHK009 - Comportamento quando o orquestrador nao tem permissao de escrita no diretorio do projeto-alvo esta especificado? [Gap, Spec §FR-017]
- [ ] CHK010 - O conteudo minimo da secao "Licoes aprendidas" do relatorio esta definido (numero minimo de itens, formato)? [Gap, contracts/report-format.md §6]

## Clareza de Requisitos

- [ ] CHK011 - O termo "score >= 2 decide" do clarify-answerer esta operacionalizado de forma mecanica e verificavel sem ambiguidade? [Clareza, research.md Decision 6]
- [ ] CHK012 - "Movimento circular" tem definicao operacional precisa o suficiente para implementacao sem decisao subjetiva? [Clareza, research.md Decision 4]
- [ ] CHK013 - "Progresso mensuravel" no contexto do gatilho "5 ciclos sem progresso" esta definido (qual sinal medir)? [Ambiguity, Spec §FR-014]
- [ ] CHK014 - Os thresholds iniciais (80 tool calls, 90 min wallclock, 1MB de estado) estao marcados como ajustaveis ou cravados? [Ambiguity, research.md Decision 2]
- [ ] CHK015 - "Bug impeditivo" tem definicao que permite distinguir de "bug nao impeditivo" sem decisao subjetiva? [Ambiguity, Spec §FR-021]
- [ ] CHK016 - O formato exato da resposta de bloqueio humano via `--resposta-bloqueio "<id>:<resposta>"` suporta respostas multilinha ou somente linha unica? [Ambiguity, contracts/cli-invocation.md]
- [ ] CHK017 - "Anonimizacao automatica" antes do envio de issue tem regras especificas verificaveis (regex, lista de padroes)? [Ambiguity, contracts/issue-template.md]

## Consistencia de Requisitos

- [ ] CHK018 - As 5 secoes obrigatorias do relatorio em FR-011 batem com as 6 secoes em research.md Decision 10 e contracts/report-format.md? [Conflict, Spec §FR-011 vs research.md §10]
- [ ] CHK019 - Os 5 campos obrigatorios da Decisao em FR-010 batem com os 8 campos da entidade Decisao em data-model.md? Os 3 campos extras (timestamp, score, referencias, artefato_originador) sao opcionais ou obrigatorios? [Consistency, Spec §FR-010 vs data-model.md §Decisao]
- [ ] CHK020 - A constitution feature §V (`gh issue` permitida apenas no toolkit) e a Constitution Check do plano (PASS com excecao) tem o mesmo escopo de excecao? [Consistency, constitution.md §V vs plan.md §Constitution Check]
- [ ] CHK021 - A whitelist em research.md Decision 5 (linha-por-URL com globs) e o estado em contracts/state-schema.md (`whitelist_urls_externas` como array) sao formatos compativeis (carregamento converte um para outro)? [Consistency, research.md §5 vs contracts/state-schema.md]
- [ ] CHK022 - O limite de 3 niveis de subagentes (Spec §FR-013) e a frase "filho, neto, bisneto" (constitution.md §IV) usam a mesma definicao de profundidade (orquestrador raiz e nivel 0 ou 1)? [Ambiguity]
- [ ] CHK023 - O comportamento "finaliza onda + libera sessao" em bloqueio humano (Spec §FR-016) e idempotente com a estrategia schedule/clear/continue (Spec §US3)? [Consistency, Spec §FR-016 vs §FR-007/FR-008]

## Mensurabilidade de Success Criteria

- [ ] CHK024 - SC-001 ("100% das execucoes produzem relatorio com 6 secoes") tem metodo de verificacao automatizado proposto (script que checa secoes obrigatorias)? [Mensurabilidade, Spec §SC-001]
- [ ] CHK025 - SC-002 (">= 95% decisoes com 5 campos completos") tem definicao de "campo completo" suficientemente operacional (string nao vazia? min N chars?)? [Mensurabilidade, Spec §SC-002]
- [ ] CHK026 - SC-006 ("leitor reproduz mentalmente decisoes sem logs externos") tem metodo de verificacao alem de "revisao manual" — protocolo, amostragem, criterio? [Ambiguity, Spec §SC-006]
- [ ] CHK027 - SC-007 ("nunca 'pareceu razoavel'") tem detector automatizado (busca textual contra blacklist de frases) ou exige inspecao manual? [Mensurabilidade, Spec §SC-007]
- [ ] CHK028 - SC-010 ("a cada 3 execucoes, 1 licao concreta") define o que conta como "licao concreta" — formato, profundidade, criterios mecanicos para distinguir de "observacao generica"? [Ambiguity, Spec §SC-010]
- [ ] CHK029 - Todos os 10 success criteria sao technology-agnostic (nenhum cita "Claude Code", "JSON", "tool call" como exigencia mensuravel)? [Mensurabilidade, Spec §Success Criteria]

## Cobertura de Cenarios

- [ ] CHK030 - Cobertura de cenarios em quickstart.md (10 cenarios) cobre todas as 5 user stories? [Cobertura, quickstart.md vs Spec §User Stories]
- [ ] CHK031 - Cada functional requirement (FR-001 a FR-023) e exercitado por pelo menos 1 cenario em quickstart.md ou tem justificativa de "verificavel apenas por inspecao do estado"? [Cobertura]
- [ ] CHK032 - Cenarios de happy path (US1 sucesso completo) e error paths (aborto, pause, retomada apos corrupcao) tem proporcao razoavel — happy nao domina? [Cobertura, quickstart.md]

## Cobertura de Edge Cases

- [ ] CHK033 - Os 12 edge cases listados na Spec §Edge Cases tem cobertura em FRs especificos ou em cenarios de quickstart? [Cobertura, Spec §Edge Cases]
- [ ] CHK034 - Edge case "skill local conflitando com global de mesmo nome" tem comportamento testavel (skill local vence) e cenario, ou apenas mencao? [Gap, Spec §Edge Cases item 11]
- [ ] CHK035 - Edge case ".env ausente" distingue entre "etapa precisa de credencial" vs "etapa nao precisa" — qual o criterio mecanico? [Ambiguity, Spec §Edge Cases item 9]

## Requisitos Nao-Funcionais

- [ ] CHK036 - Limite de tamanho do relatorio (linhas, KB) esta definido para evitar relatorio de 50MB em execucao gigante? [Gap]
- [ ] CHK037 - Comportamento de retencao/limpeza de state-history/ esta especificado (mantem todos? rotaciona apos N? operador limpa?)? [Gap, contracts/state-schema.md]
- [ ] CHK038 - Requisito de seguranca: filtro de privacidade no issue-template tem regex/blacklist documentada ou apenas descrita conceitualmente? [Ambiguity, contracts/issue-template.md]

## Dependencias e Premissas

- [ ] CHK039 - Dependencias externas listadas em plan.md §Technical Context (ScheduleWakeup, gh, git, jq opcional) tem premissas de versao minima documentadas onde relevante? [Completude, plan.md §Technical Context]
- [ ] CHK040 - Premissa "Claude Code com Auto mode ativo" e marcada como recomendada vs obrigatoria, com comportamento esperado em cada caso? [Ambiguity, contracts/cli-invocation.md]

---

## Notes

- Marcar items concluidos com `[x]`
- Items numerados sequencialmente para append futuro de outros checklists (security, performance, etc)
- Total: 40 items, dentro do soft cap

### Metricas

- Rastreabilidade: 38/40 = **95%** dos items referenciam spec/plan/research/data-model/contracts ou marcam Gap/Ambiguity/Conflict (acima do minimo de 80%).
- Distribuicao por dimensao:
  - Completude: 10 (CHK001-CHK010)
  - Clareza: 7 (CHK011-CHK017)
  - Consistencia: 6 (CHK018-CHK023)
  - Mensurabilidade: 6 (CHK024-CHK029)
  - Cobertura cenarios: 3 (CHK030-CHK032)
  - Cobertura edge cases: 3 (CHK033-CHK035)
  - Nao-funcionais: 3 (CHK036-CHK038)
  - Dependencias: 2 (CHK039-CHK040)

### Areas com mais gaps detectados

1. **Edge cases operacionais** (CHK006, CHK007, CHK008, CHK009): operador
   renomeando projeto-alvo, execucoes concorrentes, sem espaco, sem permissao
   — nao endereçados na spec.
2. **Mensurabilidade de SCs subjetivas** (CHK026, CHK027, CHK028): SC-006,
   SC-007, SC-010 dependem de inspecao manual — risco de virarem inverificaveis.
3. **Definicao operacional de termos** (CHK013, CHK015, CHK038): "progresso
   mensuravel", "bug impeditivo", "anonimizacao automatica" carecem de
   criterios mecanicos.
4. **Politicas nao-funcionais** (CHK036, CHK037): tamanho maximo de
   relatorio, retencao de state-history — sem requisito atual.

### Recomendacao

Antes de `/create-tasks`, considerar:

- **Endereçar gaps de prioridade alta** via update na spec: CHK006-CHK009
  (edge cases operacionais), CHK013, CHK015 (definicoes operacionais
  faltantes). Sao gaps de escopo que viram ambiguidades em runtime.
- **Endereçar mensurabilidade duvidosa**: CHK026, CHK027, CHK028 podem ser
  refinados — SC-006 ganha protocolo de revisao com amostragem; SC-007
  ganha lista negra de frases a evitar; SC-010 define "licao concreta" com
  formato.
- **Aceitar gaps de baixa prioridade como conscientes**: CHK036, CHK037
  podem virar "Items a Definir" se nao bloquearem o experimento. Limite de
  tamanho de relatorio so importa em execucoes >> 100 ondas.
