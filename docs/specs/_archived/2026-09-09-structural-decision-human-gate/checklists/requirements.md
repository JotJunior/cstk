# REQUIREMENTS Checklist: structural-decision-human-gate

**Purpose**: Validar qualidade, clareza e completude dos requisitos da spec antes de prosseguir para `create-tasks`.
**Created**: 2026-08-19
**Feature**: [spec.md](../spec.md)

## Completude de Requisitos

- [x] CHK001 - Existe requisito para a declaracao obrigatoria de classe quando ha token de bloqueio nas opcoes? [Completude, Spec §FR-002] {auto}
- [x] CHK002 - Existe requisito cobrindo o caminho MCP com a mesma regra do helper CLI (paridade)? [Completude, Spec §FR-004] {auto}
- [x] CHK003 - Existe requisito para retrocompatibilidade de Decisoes legadas sem classe? [Completude, Spec §FR-013] {auto}
- [x] CHK004 - Existe requisito de auditoria/relatorio que identifique decisoes estruturais e anomalias? [Completude, Spec §FR-012] {auto}
- [ ] CHK005 - Existe requisito que cubra o eixo `tier de entrega` de forma explicita, alem de referenciar `delivery-tier` por completude? [Completude, Spec §Contexto "Definicao: classe estrutural"] {humano}

## Clareza de Requisitos

- [x] CHK006 - E 'consentimento humano rastreavel' definido de forma verificavel (nao apenas descritiva)? [Clareza, Spec §FR-003] {auto}
- [x] CHK007 - E 'chave de assunto' definida com criterio deterministico (funcao pura + igualdade exata de string)? [Clareza, Spec §FR-008, Key Entities] {auto}
- [x] CHK008 - E 'ja decidido por humano' (FR-008) quantificado sem depender de julgamento do agente? [Clareza, Spec §FR-008] {auto}
- [x] CHK009 - E 'fonte rastreavel' (US3) definida com exemplos concretos (briefing/constitution/Decisao humana)? [Clareza, Spec §US3 Acceptance Scenario 2] {auto}

## Consistencia de Requisitos

- [x] CHK010 - O criterio de "consentimento" em FR-003 (bloqueio respondido + mesmo eixo) e consistente com o predicado de anomalia em FR-012? [Consistencia, Spec §FR-003, §FR-012] {auto}
- [x] CHK011 - A regra "campo de agente decisor MUST NOT ter papel" e aplicada de forma consistente em FR-003 e FR-012 (nao so num dos dois)? [Consistencia, Spec §FR-003, §FR-012] {auto}
- [x] CHK012 - A definicao de classe operacional (default, sem mudanca de comportamento) e consistente com FR-005 (regressao zero)? [Consistencia, Spec §Contexto, §FR-005] {auto}

## Qualidade de Criterios de Aceite

- [x] CHK013 - SC-001 e mensuravel (100% das execucoes, criterio binario de pausa antes do plan.md)? [Mensurabilidade, Spec §SC-001] {auto}
- [x] CHK014 - SC-002 exclui explicitamente o campo de agente decisor como evidencia valida, evitando ambiguidade de medicao? [Mensurabilidade, Spec §SC-002] {auto}
- [x] CHK015 - SC-006 (bloqueios de decisoes operacionais nao aumentam) tem um metodo de medicao definido (re-execucao de projeto de referencia antes x depois)? [Mensurabilidade, Spec §SC-006] {auto}

## Cobertura de Cenarios

- [x] CHK016 - Gate deterministico `requirement-coverage.sh` confirma cenario associado para todos os 14 FRs? [Cobertura, requirement-coverage.sh: requirements=14 covered=14 errors=0] {auto}
- [x] CHK017 - Ha cenario de aceite cobrindo a omissao do token de bloqueio nas opcoes (fraqueza declarada L1)? [Cobertura, Spec §Edge Cases "Orquestrador omite o token"] {auto}
- [x] CHK018 - Ha cenario cobrindo resposta humana "decida voce" como consentimento valido? [Cobertura, Spec §Edge Cases "responde ao bloqueio... decida voce"] {auto}
- [x] CHK019 - Ha cenario cobrindo reaparicao do mesmo item Alto entre `specify` e `plan` (chave estavel) e item reescrito (chave nova)? [Cobertura, Spec §Edge Cases "Mesmo item Alto reaparece"] {auto}

## Cobertura de Edge Cases

- [x] CHK020 - Briefing legado / tabela com cabecalho variante esta coberto (parser tolerante, tabela irreconhecivel = zero itens)? [Cobertura, Spec §Edge Cases "Briefing legado"] {auto}
- [x] CHK021 - Execucao ja em andamento na instalacao da feature (nao-retroatividade) esta coberta? [Cobertura, Spec §Edge Cases "Execucao ja em andamento"] {auto}
- [x] CHK022 - Tentativa de forjar consentimento (apontar bloqueio inexistente/de outra execucao/pendente) esta coberta? [Cobertura, Spec §Edge Cases "Agente tenta forjar consentimento"] {auto}
- [ ] CHK023 - Ha criterio explicito para o caso de DOIS itens Alto pendentes simultaneamente na mesma etapa (bloqueio unico agregando ambos, ou dois bloqueios sequenciais)? [Gap] {humano}

## Requisitos Nao-Funcionais

- [x] CHK024 - Performance: overhead do gate de briefing/plan e delimitado (SC-005, sem chamada de rede)? [Nao-funcional, Spec §SC-005] {auto}
- [x] CHK025 - Seguranca/governanca: a trava recusa qualquer combinacao de score/evidencia que nao seja bloqueio+score 0 para estrutural sem consentimento? [Nao-funcional, Spec §FR-003] {auto}
- [ ] CHK026 - Ha requisito nao-funcional de UX para a mensagem de recusa (formato, idioma, tamanho maximo) alem de "cita a classe, o eixo e o caminho correto"? [Ambiguity, Spec §FR-003] {humano}

## Dependencias e Premissas

- [x] CHK027 - A dependencia da US4 (create-tasks ordena gate de dependencias apos stack) em relacao a US1 (decisao estrutural existir) esta explicita? [Dependencia, Spec §US4 Acceptance Scenario 1] {auto}
- [x] CHK028 - A premissa de que `delivery-tier`/INV-4 ja cobre o eixo "tier de entrega" esta declarada, evitando escopo duplicado? [Premissa, Spec §Contexto tabela de eixos] {auto}

## Ambiguidades e Conflitos

- [ ] CHK029 - "Item Alto do briefing ambiguo (texto nao casa claramente com um eixo estrutural) ainda assim e bloqueio" (Edge Case) — falta definir se o texto do item vira literalmente a pergunta do bloqueio ou se o agente pode reformular; reformulacao poderia reintroduzir julgamento vetado pelo FR-008. [Ambiguity, Spec §Edge Cases "Item Alto do briefing ambiguo"] {humano}

## Limitacoes Declaradas (escopo, dec-024)

- [x] CHK030 - As limitacoes L1 (cobertura deterministica parcial) e L2 (portas de escrita sem guarda) estao declaradas com consequencia honesta, nao apresentadas como resolvidas? [Completude, Spec §"Limitacoes declaradas"] {auto}

## Notes

- Items `{auto}` ja vem resolvidos pelo agente (`[x]` com citacao, ou marcador `[Gap]`)
- Items `{humano}` ficam `[ ]` aguardando decisao do dono do produto
- Marcar items concluidos com `[x]`
- Items numerados sequencialmente para referencia
