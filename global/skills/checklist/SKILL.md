---
name: checklist
description: 'Requirements quality gate ("unit tests for English") by domain (ux/api/security/performance/a11y). Triggers: "checklist", "validar requisitos", "quality gate". Validates REQUIREMENT quality, not code.'
argument-hint: "[dominio: ux | api | security | performance] [contexto adicional]"
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
---

# Skill: Checklist de Qualidade de Requisitos

Gere checklists que validam a QUALIDADE dos requisitos — nao da implementacao.
Conceito: "Unit Tests for English".

## Pre-requisitos

**Recomendado**: `spec.md` existente para referenciar requisitos. Sem spec, a
skill pode gerar um checklist generico de qualidade de requisitos, mas a
rastreabilidade (`[Spec §X.Y]`) fica comprometida.

## Proximos passos

1. Revisar o checklist e marcar items atendidos
2. `/clarify` — para resolver items que revelaram ambiguidades
3. `/plan` ou `/create-tasks` — prosseguir no fluxo SDD se o gate passou

## Argumentos

$ARGUMENTS

---

## CONCEITO FUNDAMENTAL

**Checklists sao UNIT TESTS PARA REQUISITOS** — validam qualidade, clareza e
completude dos requisitos escritos em linguagem natural.

**NAO sao para verificacao/teste de implementacao:**

- Errado: "Verificar se o botao funciona corretamente"
- Errado: "Testar se a API retorna 200"
- Errado: "Confirmar que o error handling funciona"

**SAO para validacao de qualidade dos requisitos:**

- Correto: "Sao os requisitos de hierarquia visual definidos para todos os tipos de card?"
- Correto: "E 'exibicao proeminente' quantificado com sizing/positioning especificos?"
- Correto: "Sao os requisitos de hover state consistentes entre todos os elementos interativos?"
- Correto: "Sao os requisitos de acessibilidade definidos para navegacao por teclado?"

---

## FLUXO DE EXECUCAO

```
1. CONTEXTO        Localizar artefatos da feature
     |
2. CLARIFICACAO    Perguntas de escopo (max 3)
     |
3. GERACAO         Criar checklist por dimensoes de qualidade
     |
4. SALVAMENTO      Salvar e reportar
```

---

## ETAPA 1: CONTEXTO

### 1.1 Localizar Artefatos

Buscar artefatos da feature:
1. `docs/specs/*/spec.md` — requisitos e escopo
2. `docs/specs/*/plan.md` — detalhes tecnicos
3. `docs/specs/*/tasks.md` — tarefas de implementacao

Carregar apenas porcoes relevantes (progressive disclosure, nao dump completo).

### 1.2 Identificar Dominio

Derivar dominio do checklist a partir de $ARGUMENTS:
- `ux` — hierarquia visual, interacao, acessibilidade
- `api` — endpoints, error handling, versionamento
- `security` — autenticacao, autorizacao, protecao de dados
- `performance` — latencia, throughput, escalabilidade
- `requirements` — qualidade geral de requisitos (default se nenhum dominio especificado)
- Dominio customizado — usar contexto do argumento

---

## ETAPA 2: CLARIFICACAO DE INTENT

### 2.1 Perguntas Dinamicas (max 3)

Gerar ate 3 perguntas contextuais baseadas em sinais do projeto e $ARGUMENTS.
**Pular** perguntas cujas respostas ja sao obvias dos argumentos.

Arquetipos de perguntas:
- **Refinamento de escopo**: "Deve incluir touchpoints de integracao com X e Y?"
- **Priorizacao de risco**: "Quais areas de risco devem receber checks obrigatorios?"
- **Calibracao de profundidade**: "E um checklist leve pre-commit ou gate formal de release?"
- **Framing de audiencia**: "Sera usado pelo autor ou por peers em PR review?"
- **Exclusao de limite**: "Devemos excluir items de performance tuning nesta rodada?"

Formato: tabela com opcoes A-E quando aplicavel, ou resposta livre.

Defaults quando interacao impossivel:
- Profundidade: Standard
- Audiencia: Reviewer (PR) se codigo; Author se docs
- Foco: Top 2 clusters de relevancia

---

## ETAPA 3: GERACAO

### 3.1 Dimensoes de Qualidade

Organizar items por dimensao:

**Completude de Requisitos** — Todos os requisitos necessarios estao documentados?
**Clareza de Requisitos** — Requisitos sao especificos e nao-ambiguos?
**Consistencia de Requisitos** — Requisitos se alinham sem conflitos?
**Qualidade de Criterios de Aceite** — Success criteria sao mensuráveis?
**Cobertura de Cenarios** — Todos os fluxos/casos estao cobertos?
**Cobertura de Edge Cases** — Condicoes de contorno estao definidas?
**Requisitos Nao-Funcionais** — Performance, seguranca, acessibilidade especificados?
**Dependencias e Premissas** — Estao documentadas e validadas?
**Ambiguidades e Conflitos** — O que precisa de clarificacao?

### 3.2 Como Escrever Items

**PADRAO CORRETO** — Testar QUALIDADE do requisito:

```markdown
- [ ] CHK001 - Sao os requisitos de [tipo] definidos/especificados para [cenario]? [Completude]
- [ ] CHK002 - E '[termo vago]' quantificado com criterios especificos? [Clareza, Spec §FR-2]
- [ ] CHK003 - Sao requisitos consistentes entre [secao A] e [secao B]? [Consistencia]
- [ ] CHK004 - Pode [requisito] ser objetivamente medido/verificado? [Mensurabilidade]
- [ ] CHK005 - Sao [edge cases/cenarios] cobertos nos requisitos? [Cobertura]
- [ ] CHK006 - A spec define [aspecto ausente]? [Gap]
```

**PROIBIDO** — Testar implementacao:

```markdown
- Verificar se a pagina exibe 3 cards (ERRADO — testa implementacao)
- Testar se hover states funcionam no desktop (ERRADO — testa comportamento)
- Confirmar que o logo clica para home (ERRADO — testa funcionalidade)
```

### 3.3 Exemplos por Dominio

Cada dominio tem um catalogo de items em `references/{dominio}.md` (mesmo
diretorio desta skill). Consultar sob demanda ao gerar o checklist:

- `references/ux.md` — hierarquia visual, estados de interacao, acessibilidade, responsividade
- `references/api.md` — contratos, error handling, auth, rate limiting, retry, observabilidade
- `references/security.md` — authN/Z, protecao de dados, input validation, logging, compliance
- `references/performance.md` — targets, escalabilidade, degradacao, caching, queries
- `references/requirements.md` — qualidade geral de requisitos (default)

Esses sao ponto de partida — nao copiar sem adaptar ao contexto da feature.

### 3.4 Rastreabilidade

- **MINIMO**: >= 80% dos items devem incluir pelo menos uma referencia de rastreabilidade
- Cada item deve referenciar: secao da spec `[Spec §X.Y]`, ou marcadores: `[Gap]`, `[Ambiguity]`, `[Conflict]`, `[Assumption]`

### 3.5 Consolidacao

- Soft cap: 40 items. Se > 40 candidatos, priorizar por risco/impacto
- Merge near-duplicates que checam o mesmo aspecto do requisito
- Se > 5 edge cases de baixo impacto: criar um item agregado

### 3.6 Template do Checklist

```markdown
# [DOMAIN] Checklist: [FEATURE NAME]

**Purpose**: [Descricao breve do que este checklist cobre]
**Created**: [DATE]
**Feature**: [Link para spec.md]

## [Categoria 1]

- [ ] CHK001 - [Item de checklist com referencia] [Dimensao, Ref]
- [ ] CHK002 - [Item] [Dimensao, Ref]

## [Categoria 2]

- [ ] CHK003 - [Item] [Dimensao, Ref]
- [ ] CHK004 - [Item] [Dimensao, Ref]

## Notes

- Marcar items concluidos com `[x]`
- Items numerados sequencialmente para referencia
```

---

## ETAPA 4: SALVAMENTO

### 4.1 Nomear Arquivo

- Usar nome curto e descritivo baseado no dominio: `ux.md`, `api.md`, `security.md`, `performance.md`, `requirements.md`
- Se arquivo ja existe: **APPEND** novos items, continuando do ultimo CHK ID
- Nunca deletar ou substituir conteudo existente

### 4.2 Salvar

Salvar em `docs/specs/{feature}/checklists/{domain}.md`.
Criar diretorio `checklists/` se nao existir.

### 4.3 Reportar

```markdown
## Checklist Criado

**Arquivo**: [caminho]
**Dominio**: [dominio]
**Items**: [N] items gerados
**Acao**: Novo arquivo / Append a existente

### Areas de Foco

- [Area 1]
- [Area 2]

### Proximos Passos

- Revisar e marcar items como `[x]`
- `/checklist [outro-dominio]` — Gerar checklist para outro dominio
- `/plan` ou `/create-tasks` — Prosseguir com o fluxo SDD
```

---

## Gotchas

### Checklist valida REQUISITO, nao IMPLEMENTACAO

O erro mais comum: escrever items como "Verificar se o botao funciona". Isso testa implementacao. O item correto e "Sao os requisitos de interacao definidos para o botao?". Se o item comeca com "Verificar", "Testar", "Confirmar que X funciona", esta errado.

### Rastreabilidade minima 80%

Items sem referencia a `[Spec §X.Y]`, `[Gap]`, `[Ambiguity]`, `[Conflict]` ou `[Assumption]` sao ruido — nao da para priorizar nem validar. Abaixo de 80% o checklist perde utilidade como quality gate.

### Soft cap 40 items por dominio — priorize risco

Um checklist com 200 items e ignorado. Se mais de 40 candidatos, priorizar por risco/impacto, agrupar near-duplicates, e agregar edge cases de baixo impacto num item unico.

### APPEND, nunca sobrescrever

Se o arquivo do dominio ja existe, continue os IDs (CHK015, CHK016...) ao final — nao substitua conteudo existente nem reinicie a numeracao. Usuarios ja podem ter marcado items.

### Adjetivos vagos em items de checklist tambem sao proibidos

"Sao os requisitos bem documentados?" e tao vago quanto "sistema deve ser robusto". Use criterios verificaveis: "Cada requisito funcional tem criterio de aceite mensuravel?"
