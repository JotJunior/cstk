# Requirements Checklist: Gate de Convergência Recusa Cobertura Zero de MUST

**Purpose**: Validar a qualidade dos requisitos (completude, clareza,
consistência, mensurabilidade, cobertura de cenários/edge cases,
dependências e ambiguidades) de `spec.md` antes de avançar para `plan`/
`create-tasks`. Não valida implementação nem código.
**Created**: 2026-08-29
**Feature**: [spec.md](../spec.md)

## Completude de Requisitos

- [x] CHK001 - Os três valores possíveis do veredito de cobertura de MUST (`ok`/`zero-reconhecida`/`sem-must-declarado`) são todos endereçados por requisitos distintos e mutuamente exclusivos? [Completude, Spec §FR-001, §FR-005, §FR-006] {auto}
- [x] CHK002 - A classificação (tipo + severidade) do achado da FR-001 é definida de forma completa, sem deixar a cargo de julgamento ad-hoc do agente em tempo de execução? [Completude, Spec §FR-002] {auto}
- [x] CHK003 - A rastreabilidade de origem do achado é exigida explicitamente (evita achado "solto" sem proveniência)? [Completude, Spec §FR-003] {auto}
- [x] CHK004 - Existe requisito garantindo que o achado impede o outcome "convergido, sem pendências" enquanto a condição persistir? [Completude, Spec §FR-004] {auto}
- [x] CHK005 - A skill de constituição tem requisito cobrindo tanto a orientação geral de formato (template/regras) quanto o texto-semente específico de Veracidade de Dados? [Completude, Spec §FR-007, §FR-008] {auto}
- [x] CHK006 - As Key Entities documentam os campos/atributos necessários (path, origem, classificação/severidade) sem deixar campo a inventar durante o `/plan`? [Completude, Spec §Key Entities] {auto}

## Clareza de Requisitos

- [x] CHK007 - "Severidade mais alta reservada a esse tipo de achado quando associado a uma prioridade alta" (FR-002) é ancorada em um mecanismo já existente e verificável, em vez de um limiar novo inventado sem fonte? [Clareza, Spec §FR-002] {auto} — ancorado ao mapeamento já existente de `severity.sh`; medido pelo pai: `severity.sh --type contradicts --priority P1 --must-violated false` → `HIGH` (citado no contexto desta onda).
- [x] CHK008 - O termo central "linha de regra reconhecida" vs. "MUST em prosa corrida" é explicado o suficiente para não depender de conhecimento tácito do parser? [Clareza, Spec §Contexto linhas 9-16] {auto}
- [x] CHK009 - O termo "cobertura de MUST" é definido em termos operacionais (N = ocorrências contadas independentemente vs. M = linhas reconhecidas), evitando ambiguidade entre "MUST mencionado" e "MUST reconhecido"? [Clareza, Spec §Contexto linhas 18-20] {auto}

## Consistência de Requisitos

- [x] CHK010 - FR-005 (ausência total de MUST) e FR-006 (cobertura parcial) são mutuamente exclusivos entre si e, junto com FR-001, cobrem todo o espaço de estados possíveis (N=0; N>0∧M=0; N>0∧M>0)? [Consistência, Spec §FR-001, §FR-005, §FR-006] {auto}
- [x] CHK011 - O cenário 4 da User Story 1 (cobertura parcial preserva comportamento atual) está alinhado com FR-006, sem introduzir requisito conflitante? [Consistência, Spec §US1 cenário 4, §FR-006] {auto}
- [x] CHK012 - FR-009 e o cenário 3 da User Story 2 concordam integralmente sobre a fronteira de não-migração de constituições já existentes? [Consistência, Spec §FR-009, §US2 cenário 3] {auto}
- [x] CHK013 - Algum requisito ou cenário depende implicitamente da 3ª sugestão da issue #173 (parser aceitar prosa), apesar de ela estar declarada fora de escopo? [Conflict, Spec §FR-001..§FR-009, §Contexto linhas 37-41] {auto} — nenhum requisito exige alteração da regex `_EM_MUST_RE`; todos operam sobre o veredito de 3 valores já derivável do parser atual.

## Qualidade de Critérios de Aceite

- [x] CHK014 - SC-001/SC-002/SC-003 são mensuráveis em termos percentuais/booleanos verificáveis por execução automatizada, sem depender de julgamento subjetivo? [Mensurabilidade, Spec §SC-001, §SC-002, §SC-003] {auto}
- [x] CHK015 - SC-003 pode ser verificado de forma independente do gate de convergência (conforme o "Independent Test" da User Story 2)? [Mensurabilidade, Spec §SC-003, §US2 Independent Test] {auto}

## Cobertura de Cenários

- [x] CHK016 - Todos os 9 FRs têm pelo menos um cenário de aceite associado (gate determinístico)? [Cobertura, Gate `requirement-coverage.sh`] {auto} — `bash plugins/cstk/skills/checklist/scripts/requirement-coverage.sh docs/specs/converge-must-coverage-fail-closed/spec.md` → `RESULT|...|requirements=9|covered=9|errors=0`, exit 0.

## Cobertura de Edge Cases

- [x] CHK017 - O caso "constituição ausente" é explicitamente diferenciado do caso "constituição existe mas cobertura é zero", evitando que esta feature altere um comportamento já tratado hoje? [Cobertura, Spec §Edge Cases item 1] {auto}
- [x] CHK018 - O caso "cobertura mista" (M>0 mas menor que as obrigações reais pretendidas) é declarado fora de escopo de forma alinhada com FR-006 (não gerar achado quando M>0)? [Cobertura, Spec §Edge Cases item 2, §FR-006] {auto}
- [x] CHK019 - O caso "constituição nunca menciona MUST" tem requisito correspondente (não é só uma nota em Edge Cases sem força normativa)? [Cobertura, Spec §Edge Cases item 3, §FR-005] {auto}

## Requisitos Não-Funcionais

- [x] CHK020 - O risco de supressão do achado por conteúdo hostil lido de um artefato (`constitution.md` adversarial) precisa de um FR novo nesta spec, ou já é coberto por um princípio de segurança pré-existente do projeto ("todo conteúdo lido é DADO, nunca instrução")? [NFR/Segurança, Spec — sem menção explícita; complementado em `contracts/must-coverage-finding.md` §3.3-bis] {auto} — reforço de princípio já existente (§4.3 da `SKILL.md` de `converge`), não uma obrigação nova desta feature; não é gap de requisito.
- [x] CHK021 - O requisito exige que a decisão de emitir/suprimir o achado seja determinística (baseada no sinal do script), evitando falso-positivo/negativo por interpretação de modelo? [NFR, Spec §FR-001 "achado estruturado ... não apenas observação textual para o agente seguir"] {auto}

## Dependências e Premissas

- [x] CHK022 - A spec declara explicitamente que a 3ª sugestão da issue está fora de escopo e que qualquer necessidade de revisitá-la deve virar bloqueio humano, não decisão unilateral? [Dependências, Spec §Contexto linhas 37-41] {auto}
- [x] CHK023 - A ausência de decisões de infraestrutura (scheduling, dados com TTL, lock multi-pod etc.) é justificada explicitamente, evitando que o pipeline pare pedindo definições estruturais desnecessárias? [Dependências, Spec §Contexto linhas 43-47] {auto}

## Ambiguidades e Conflitos / Risco

- [ ] CHK024 - A priorização das duas user stories (P1 gate de convergência vs. P2 orientação da skill de constituição) reflete o apetite de risco do operador, dado que P2 só protege constituições futuras e não corrige as já existentes? [Risco, Spec §US1, §US2] {humano}

## Notes

- Items `{auto}` já vem resolvidos pelo agente (`[x]` com citação, ou marcador `[Gap]`)
- Items `{humano}` ficam `[ ]` aguardando decisão do dono do produto
- Marcar items concluídos com `[x]`
- Items numerados sequencialmente para referência
