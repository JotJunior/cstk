# Dominio: Requirements (Generico)

Items exemplo para checklist de qualidade geral de requisitos — usar quando o
dominio especifico nao se aplica ou como complemento.

## Completude

- Todos os requisitos funcionais necessarios estao documentados? [Completude]
- Requisitos nao-funcionais estao cobertos (perf, security, observability)? [Completude]
- Sao declaracoes explicitas de fora-de-escopo documentadas? [Completude]

## Clareza

- Cada requisito usa verbo imperativo testavel (MUST, SHOULD)? [Clareza]
- Adjetivos vagos (robusto, escalavel, intuitivo) sao quantificados? [Clareza]
- Placeholders (TODO, TKTK, ???) foram resolvidos? [Completude]

## Consistencia

- Requisitos se alinham sem conflitos entre si? [Consistencia]
- Terminologia e consistente (mesmo conceito com mesmo nome)? [Consistencia]
- Requisitos nao contradizem principios da constitution? [Constitution Alignment]

## Mensurabilidade

- Success criteria sao objetivamente verificaveis? [Mensurabilidade]
- Criterios de aceite podem ser transformados em teste automatizado? [Mensurabilidade]
- Metricas tem threshold definido (nao apenas "deve ser rapido")? [Clareza]

## Cobertura de Cenarios

- Happy paths estao documentados? [Cobertura]
- Error paths tem comportamento esperado definido? [Cobertura]
- Edge cases (limite, concorrencia, timeout) sao cobertos? [Edge Case, Gap]

## Dependencias e Premissas

- Dependencias externas sao explicitas e validadas? [Completude]
- Premissas assumidas estao documentadas? [Clareza]
- Fallbacks em caso de dependencia indisponivel sao definidos? [Completude]

## Rastreabilidade

- User stories se ligam a requisitos funcionais? [Traceability]
- Tasks mapeiam a requisitos/stories? [Traceability]
- Criterios de aceite se ligam a success criteria? [Traceability]

## Ambiguidades

- Marcacoes `[NEEDS CLARIFICATION]` foram resolvidas? [Ambiguity]
- Requisitos com interpretacao multipla foram refinados? [Ambiguity]
