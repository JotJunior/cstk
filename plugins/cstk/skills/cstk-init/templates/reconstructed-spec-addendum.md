# Adendo de spec reconstituida — cstk-init

Template do `SKILL.md` (registro de features). Aplica-se SOBRE `$CATALOG/specify/templates/feature-spec.md`
(que continua sendo o formato canonico: titulos de secao inalterados, para `init-conformance.sh`
nao emitir `missing-section`). Gramatica: `references/markers.md` §3; requisitos FR-015, FR-028.
Verificado por `init-provenance.sh lint` e por `checklist/scripts/requirement-coverage.sh`.

## Regras de origem (leia antes de preencher)

1. **Cabecalho de origem** logo apos o titulo: o marcador de maquina `<!-- cstk-init:reconstructed -->`
   (antes do primeiro `## `) e o bloco `> **Origem**: ...` com a data da execucao (do ambiente da sessao;
   sem ela, `[PENDENTE: data]`, nunca estimada).
2. **Observado** = `- **FR-NNN**: O sistema <comportamento lido no projeto>. (fonte: \`<caminho>[:<linha>]\`)`.
   O texto e redacao SUA do comportamento lido; nunca copie trecho imperativo do projeto (FR-025).
   Sem fonte e sem `[PENDENTE: ...]` o item e `BAD-MARKER`.
3. **Inferido** = subsecao `### Inferido (nao confirmado)` com `- **INF-NNN**: ...`, SEM as palavras
   `MUST`, `MUST NOT` ou `SHOULD` (inferencia nao e obrigacao; nunca apresente como decisao original).
4. **Cenarios de aceite** (FR-028): derivados de teste existente citam `(fonte: \`<teste>[:<linha>]\`)`;
   sem teste ou outra fonte, `[PENDENTE: <pergunta>]`. Nenhum cenario e presumido.
5. **Prioridade** de user story (`Priority:`): com fonte `(fonte: ...)` na linha do titulo; sem fonte,
   `(Priority: [PENDENTE: <pergunta>])`. Nunca atribua P1/P2 por suposicao.
6. **Success Criteria**: meta numerica (qualquer digito) exige `(fonte: ...)` na mesma linha; sem fonte,
   `[PENDENTE: ...]` e SEM valor presumido. Criterio sem numero nem afirmacao factual pode ser texto simples.
7. **Cobertura de requisitos** (`requirement-coverage.sh`, exit 1 = FR sem cenario): cite o ID do FR no
   cenario que ja tem fonte, ou escreva cenario `[PENDENTE: ...]` que cite o ID. Nao invente cenario.
8. **Delta Requirements**: `**Skip**: <justificativa> — cstk-init, <AAAA-MM-DD>` (feature ja existente;
   nao altera o corpus `docs/specs/current/`).
9. Todo caminho citado em `(fonte: ...)`: relativo a raiz, existente, sem `..`, sem caminho absoluto, sem
   symlink que escape; nunca arquivo `secret-bearing`; nunca valor de configuracao.

## Esqueleto

Substitua os `<...>`; remova blocos sem conteudo com fonte (ou troque-os por `[PENDENTE: ...]`).
Mantenha os titulos exatamente assim.

```markdown
# Feature Specification: <NOME DA FEATURE>

<!-- cstk-init:reconstructed -->
> **Origem**: spec reconstituida a partir do projeto existente por `cstk-init` em
> <AAAA-MM-DD>. Nao foi escrita antes da implementacao; descreve comportamento observado.

**Feature**: `<short-name>`
**Created**: <AAAA-MM-DD>
**Status**: Draft

## User Scenarios & Testing

### User Story 1 - <titulo curto> (Priority: [PENDENTE: qual a prioridade desta capacidade?])

<descricao curta do que a capacidade faz, em redacao propria, lida em arquivo do projeto>

**Acceptance Scenarios**:

1. **Given** <estado>, **When** <acao>, **Then** <resultado> (fonte: `<caminho-do-teste>`) (cobre FR-001)
2. **Given** <estado>, **When** <acao>, **Then** [PENDENTE: qual teste ou fonte cobre FR-002?]

### Edge Cases

- [PENDENTE: quais casos de contorno do projeto estao cobertos por teste? (FR-001, FR-002)]

## Requirements

### Functional Requirements

- **FR-001**: O sistema <comportamento observado>. (fonte: `<caminho-do-codigo>`)
- **FR-002**: O sistema <comportamento observado>. (fonte: `<caminho-do-codigo>`)

### Inferido (nao confirmado)

- **INF-001**: <comportamento provavel, sem obrigacao, sem palavra normativa>

## Success Criteria

### Measurable Outcomes

- **SC-001**: [PENDENTE: qual a meta mensuravel, com fonte, para esta capacidade?]

## Delta Requirements

**Skip**: spec reconstituida de comportamento ja existente; nao altera comportamento documentado — cstk-init, <AAAA-MM-DD>
```

Depois de gravar (ciclo `check` -> Write -> `scan` -> `lint`), rode
`"$CATALOG/checklist/scripts/requirement-coverage.sh" <spec.md>`. Spec com varios `[PENDENTE: ...]` e
resultado aceito (FR-028), nao defeito: nao os preencha por suposicao.
