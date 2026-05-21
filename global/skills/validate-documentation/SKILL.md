---
name: validate-documentation
description: 'Validate a single existing document''s quality/completeness against structural standards. Triggers: "validar documentacao", "verificar UC", "audit docs". Skip for cross-artifact spec/plan/tasks consistency (use analyze).'
allowed-tools:
  - Read
  - Glob
  - Grep
---

# Skill: Validação de Documentação

Esta skill analisa e valida documentação existente contra padrões de qualidade.

## Quando Usar

Claude deve invocar esta skill automaticamente quando:
- Usuário pedir para validar/verificar documentação
- Usuário mencionar "review", "audit" ou "checar" documentos
- Antes de finalizar criação de documentação (auto-validação)
- Usuário pedir status de qualidade da documentação

## Critérios de Validação

### 1. Validação Estrutural (Documentos UC)

**Seções Obrigatórias:**
```
- [ ] Informações Gerais (tabela com ID, Nome, Domínio)
- [ ] Descrição (mínimo 2 parágrafos)
- [ ] Atores (tabela com tipo e descrição)
- [ ] Pré-condições (lista numerada)
- [ ] Pós-condições (sucesso e falha)
- [ ] Fluxo Principal (diagrama + tabela)
- [ ] Fluxos Alternativos (ao menos 1)
- [ ] Exceções (tabela com códigos)
- [ ] Regras de Negócio (tabela com IDs)
- [ ] Casos de Teste (tabela com cenários)
- [ ] Dependências (relacionamentos)
```

**Padrões de ID:**
```regex
UC-[A-Z]{2,4}-\d{3}     # UC-CAD-001, UC-AUTH-001
RN\d{2}                  # RN01, RN02
CT\d{2}                  # CT01, CT02
E\d{3}                   # E001, E002
FA\d                     # FA1, FA2
RNF\d{2}                 # RNF01, RNF02
```

### 2. Validação de Conteúdo

**Descrição:**
- Mínimo 100 caracteres
- Deve explicar O QUE e POR QUE

**Atores:**
- Pelo menos 1 ator primário
- Tipo deve ser: Primário, Secundário ou Sistema
- Descrição deve ser clara

**Fluxo Principal:**
- Diagrama Mermaid deve ser válido
- Passos devem ser numerados sequencialmente
- Cada passo deve ter descrição clara

**Regras de Negócio:**
- Cada regra deve ser acionável
- Regras complexas devem ter detalhamento

**Casos de Teste:**
- Mínimo 5 casos por UC
- Deve cobrir: sucesso, erro, edge cases
- Cada caso deve ter entrada e saída esperada

### 3. Validação de Consistência

**Cross-references:**
- Dependências devem referenciar UCs existentes
- Links internos devem ser válidos
- IDs não devem ser duplicados

**Nomenclatura:**
- Campos devem seguir padrão (camelCase ou UPPER_CASE)
- Nomes de atores consistentes entre documentos
- Terminologia uniforme

### 4. Validação de Diagramas Mermaid

**sequenceDiagram:**
```
- Participantes definidos
- Mensagens com setas corretas (->>, -->>)
- Alt/else para fluxos condicionais
- Loop para repetições
```

**flowchart:**
```
- Nós com IDs únicos
- Conexões válidas
- Decisões com múltiplas saídas
```

## Relatório de Validação

Formato do relatório gerado:

```markdown
# Relatório de Validação de Documentação

**Data:** YYYY-MM-DD
**Arquivos analisados:** N

## Resumo

| Status | Quantidade |
|--------|------------|
| OK     | X          |
| Aviso  | Y          |
| Erro   | Z          |

## Detalhes por Arquivo

### UC-XXX-NNN.md

**Status:** OK | Aviso | Erro

**Validações:**
- [x] Estrutura completa
- [x] Conteúdo adequado
- [ ] Consistência - Falta detalhar RN03
- [x] Diagramas válidos

**Ações recomendadas:**
1. Adicionar detalhamento para RN03
2. Incluir mais casos de teste de erro

---
```

## Níveis de Severidade

| Nível | Descrição | Ação |
|-------|-----------|------|
| **Erro** | Seção obrigatória ausente | Bloqueia aprovação |
| **Aviso** | Conteúdo insuficiente | Recomenda correção |
| **Info** | Sugestão de melhoria | Opcional |

## Processo de Validação

1. Identificar arquivos a validar (glob `UC-*.md`)
2. Para cada arquivo:
   - Verificar estrutura
   - Validar conteúdo
   - Checar consistência
   - Testar diagramas
3. Gerar relatório consolidado
4. Sugerir correções específicas

## Comandos de Validação

**Validar um arquivo:**
```
Valide o documento UC-CAD-001.md
```

**Validar todos os UCs:**
```
Valide toda a documentação de casos de uso
```

**Validar com auto-correção:**
```
Valide e corrija os problemas encontrados em UC-CAD-001.md
```

**Validar runbook (perfil --runbook):**
```
Valide o runbook RB-001-restore-drill.md com perfil --runbook
```

---

## Perfil `--runbook` (RB-NNN)

Runbooks operacionais (`docs/08-operacoes/RB-*.md`) tem padrao
estrutural diferente de UCs e exigem perfil dedicado. Acionar via
flag `--runbook` ou quando o filename casa `RB-\d{3}-*.md`.

### Frontmatter YAML obrigatorio

Todo runbook DEVE ter frontmatter YAML com pelo menos:

```yaml
---
title: "RB-001: Restore Drill PostgreSQL"
versao: 1.0
severidade: critica  # critica | alta | media | baixa
tempo-estimado: 45min
pre-requisitos:
  - acesso-ssh-droplet-prod
  - backup-recente-em-s3
---
```

Campos obrigatorios:
- `title` casa regex `^RB-\d{3}: .+`
- `versao` (semver ou inteiro)
- `severidade` (enum acima)
- `tempo-estimado` (string com unidade — `min`, `h`)
- `pre-requisitos` (array de strings)

### Secoes obrigatorias

Cada runbook DEVE ter (na ordem):

1. **Descricao** — 2-5 paragrafos explicando quando rodar
2. **Pre-requisitos** — checklist de itens necessarios
3. **Procedimento** — passos numerados com comandos literais
4. **Verificacao / Validacao** — como saber se o RB rodou OK
5. **Rollback** — passos reversos (OBRIGATORIO se `severidade=critica`)
6. **Contatos** — quem chamar em caso de problema

Ausencia de qualquer secao acima e Erro (nao Aviso). Para
`severidade=critica` sem secao Rollback, erro adicional CRITICO.

### Checks adicionais

- **Sem placeholders residuais**: rejeitar se conteudo contem
  `TODO`, `XXX`, `FIXME`, `<placeholder>`, `lorem ipsum`,
  `TBD`, `[FILL ME]`. Runbook e operacional — placeholder e
  dividida tecnica que vira incidente.
- **Cross-refs validos**: paths relativos em links Markdown
  (`[texto](../path)`) devem existir no disco. Reportar
  link quebrado como Erro.
- **Comandos sem variavel de ambiente nao-documentada**: se
  procedimento usa `$VAR`, `VAR` deve estar listado em
  Pre-requisitos OU em frontmatter `env-vars: [...]`. Caso
  contrario, Aviso (operador pode esquecer de exportar).

### Criterio de aceitacao

Novo `RB-NNN` e REJEITADO por `validate-documentation --runbook` se
faltar qualquer:
- Campo obrigatorio do frontmatter
- Secao obrigatoria
- Rollback (quando severidade=critica)
- Cross-ref valido em link interno

Razao para rigor extra: runbooks rodam em incidente, com operador
sob pressao. Placeholder = pessoa errada lendo o passo errado em
2h da manha.

---

## Gotchas

### Valida DOCUMENTO INDIVIDUAL, nao relacionamento entre artefatos

Para verificar se o `tasks.md` cobre os requisitos do `spec.md`, ou se `plan.md` viola `constitution.md`, use a skill `analyze`. Esta skill valida UM documento contra padroes estruturais — UC tem todas as secoes, diagramas parseaveis, IDs nao-duplicados, etc.

### Diagrama Mermaid com erro de sintaxe nao e cosmetico

Um `sequenceDiagram` sem `participant` declarado, ou setas fora do padrao (`-->` ao inves de `->>`), quebra o render em GitHub/viewers. Sempre validar que o diagrama parseia — idealmente via script.

### IDs duplicados dentro do mesmo documento sao erro, nao aviso

RN01 aparecendo duas vezes, ou CT03 com dois cenarios distintos, quebra rastreabilidade. Detectar e reportar como Erro, nao Aviso.

### Minimo 5 casos de teste (sucesso + erro + edge) — abaixo disso reprova

UC com 2 CTs e incompleto. A cobertura minima e: 1-2 cenarios de sucesso + 1-2 de erro + 1 edge case. Menos que isso, o UC nao esta pronto para implementacao.

### Auto-correcao pede confirmacao — nao aplicar direto

Mesmo quando o usuario pediu "valide e corrija", apresentar o que sera mudado antes de escrever. Correcao automatica em documento humano sem review gera desconfianca do sistema.