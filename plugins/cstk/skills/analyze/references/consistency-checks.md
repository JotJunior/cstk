# Consistency Checks Reference

Detalhamento dos 6 passes de deteccao executados pela skill `analyze`. Cada
pass opera sobre os modelos semanticos construidos na Etapa 2.

---

## A. Deteccao de Duplicacao

**Objetivo**: identificar requisitos near-duplicate que deveriam ser consolidados.

- Comparar requisitos funcionais por similaridade semantica (mesmo verbo, mesmo objeto)
- Marcar fraseado de menor qualidade para consolidacao
- Duplicacoes em user stories vs functional requirements sao comuns — flaggear

**Severidade tipica**: HIGH quando requisitos sao duplicados em mais de uma secao; MEDIUM quando apenas near-duplicate com leve diferenca de fraseado.

---

## B. Deteccao de Ambiguidade

**Objetivo**: encontrar texto vago ou placeholder que impede implementacao.

Flaggear:
- Adjetivos vagos sem criterios mensuraveis: `rapido`, `escalavel`, `seguro`, `intuitivo`, `robusto`, `amigavel`, `flexivel`
- Placeholders nao resolvidos: `TODO`, `TKTK`, `???`, `<placeholder>`, `[NEEDS CLARIFICATION]`, `XXX`
- Verbos sem objeto: "Sistema deve suportar" (suportar o que?)
- Quantificadores vagos: "muitos usuarios", "pouco tempo", "alguns casos"

**Severidade tipica**: HIGH para seguranca/performance ambiguas; MEDIUM para resto.

---

## C. Sub-especificacao

**Objetivo**: detectar requisitos incompletos.

- Requisitos com verbos mas sem objeto ou outcome mensuravel
- User stories sem criterios de aceite alinhados
- Tasks referenciando arquivos/componentes nao definidos em spec/plan
- Success criteria sem threshold numerico

**Severidade tipica**: HIGH quando afeta requisito de alto impacto; MEDIUM para suporte.

---

## D. Alinhamento com Constitution

**Objetivo**: garantir que design/requisitos respeitam principios de governanca.

- Qualquer requisito ou elemento do plan conflitando com principio MUST
- Secoes obrigatorias ou quality gates da constitution ausentes no plan/tasks
- Decisoes tecnicas que violam defaults da constitution sem Complexity Tracking justificado

**Severidade**: **Violacoes de constitution sao automaticamente CRITICAL**, independente do contexto.

---

## E. Gaps de Cobertura

**Objetivo**: detectar requisitos orfaos e tasks orfas.

- Requisitos com zero tasks associadas
- Tasks sem requisito/story mapeado
- Requisitos nao-funcionais nao refletidos em tasks (performance, security, observability)
- Edge cases da spec sem CT correspondente em tasks

**Severidade tipica**: HIGH para requisitos funcionais core sem cobertura; MEDIUM para NFRs parciais.

---

## F. Inconsistencia

**Objetivo**: detectar drift entre artefatos.

- **Drift de terminologia**: mesmo conceito nomeado diferente entre artefatos (ex: "cliente" na spec, "customer" no plan, "user" nas tasks)
- Entidades referenciadas no plan ausentes na spec (ou vice-versa)
- Contradicoes de ordenacao de tasks (tasks de integracao antes de setup sem nota de dependencia)
- Requisitos conflitantes (ex: um requer Next.js enquanto outro especifica Vue)
- State transitions na spec divergentes do data-model no plan

**Severidade tipica**: HIGH para contradicoes; MEDIUM para drift de terminologia.

---

## Heuristica de Severidade

| Severidade | Criterio |
|------------|----------|
| **CRITICAL** | Viola principio MUST da constitution, artefato core ausente, requisito com zero cobertura que bloqueia funcionalidade baseline |
| **HIGH** | Requisito duplicado ou conflitante, atributo de seguranca/performance ambiguo, criterio de aceite nao-testavel |
| **MEDIUM** | Drift de terminologia, cobertura ausente de requisito nao-funcional, edge case sub-especificado |
| **LOW** | Melhorias de estilo/redacao, redundancia menor que nao afeta ordem de execucao |

---

## Limites Operacionais

- Max 50 findings — overflow vai para resumo de overflow
- Resultados devem ser deterministicos: re-rodar sem mudancas produz mesmos IDs e contagens
- Nunca alucinar secoes ausentes; reportar como Gap
