---
name: validate-docs-rendered
description: 'Validate that docs RENDER correctly — Mermaid parseable, internal links resolve, YAML frontmatter consistent, code blocks have language. Triggers: "validar renderizacao", "verificar diagramas", "checar links". Complements validate-documentation (textual) and analyze (cross-artifact).'
argument-hint: "[diretorio a validar | caminho do arquivo | vazio para docs/]"
allowed-tools:
  - Read
  - Glob
  - Grep
  - Bash
---

# Skill: Validar Renderizacao de Documentacao

Esta skill e uma **skill de verificacao de produto** (categoria 2 do artigo
original). Ela nao valida se a documentacao esta escrita corretamente — isso e
responsabilidade de `validate-documentation` e `analyze`. Ela valida se a
documentacao **realmente funciona quando renderizada** em GitHub, GitLab,
viewers Markdown, ou outros consumidores downstream.

O gap que ela fecha e o mesmo que o artigo cita: "a diferenca entre doc que
passa no review e doc que renderiza corretamente em producao e onde moram os
bugs mais caros".

## Pre-requisitos

**Obrigatorio**: diretorio com documentacao Markdown existente (tipicamente
`docs/`). Se argumento vazio, assume `docs/` como default.

## Proximos passos

1. Corrigir issues reportados (diagramas invalidos, links quebrados)
2. Re-rodar a skill para confirmar zero issues
3. Considerar rodar como hook pre-commit para prevenir regressao

---

## FLUXO DE EXECUCAO

```
1. LOCALIZAR        Descobrir escopo (arquivo unico ou arvore)
     |
2. VALIDAR          Rodar scripts de validacao em paralelo
     |
3. CLASSIFICAR      Agrupar findings por severidade
     |
4. REPORTAR         Output tabular + exit code
```

---

## ETAPA 1: LOCALIZAR

Determinar o escopo a partir de `$ARGUMENTS`:

- **Caminho para arquivo** (ex: `docs/foo.md`): validar apenas esse arquivo
- **Caminho para diretorio** (ex: `docs/02-requisitos-casos-uso/`): validar recursivamente
- **Vazio**: assumir `docs/` na raiz do projeto

Se o caminho nao existe, abortar com mensagem clara.

---

## ETAPA 2: VALIDAR

Usar o script `scripts/validate.sh` (mesmo diretorio desta skill). O script
executa 4 validacoes em paralelo onde possivel:

### 2.1 Diagramas Mermaid

Verifica sintaxe de blocos ` ```mermaid `:

- Participantes declarados antes de uso em `sequenceDiagram`
- Setas validas (`->>`, `-->>`, `->`, `-->`, etc.)
- Nos com IDs unicos em `flowchart`/`graph`
- Fechamento correto de `alt`/`else`/`end`, `loop`/`end`, `par`/`end`
- Sintaxe de `erDiagram` (relacionamentos, cardinalidade)

**Severidade**: ERRO (quebra renderizacao).

### 2.2 Links internos

Verifica links `[texto](path/relativo.md)` e `[texto](./foo.md#anchor)`:

- Arquivo apontado existe
- Anchor (`#secao`) corresponde a um header existente (normalizado via slug)
- Links absolutos comecando com `/` resolvidos contra raiz do repo

**Severidade**: ERRO para quebrados, AVISO para anchors case-sensitive
inconsistentes.

### 2.3 Code blocks sem linguagem

Verifica ` ``` ` sem linguagem declarada (reduz syntax highlighting):

- Todo fence de 3 backticks deve ter linguagem (ex: `bash`, `python`, `md`)
- Excecao: code blocks inline ou explicitamente marcados como `text`/`plain`

**Severidade**: AVISO.

### 2.4 Frontmatter YAML

Para arquivos que comecam com `---`:

- Frontmatter fecha com `---` em linha proxima
- Campos obrigatorios do projeto (ex: `name`, `description` em skills) presentes
- YAML parseavel (sem indentacao inconsistente, strings nao-escapadas)

**Severidade**: ERRO se malformado.

### 2.5 Tabelas Markdown malformadas

- Header tem linha separadora (`| --- |`)
- Numero de colunas consistente entre linhas

**Severidade**: AVISO.

---

## ETAPA 3: CLASSIFICAR

| Severidade | Criterio | Impacto |
|------------|----------|---------|
| **ERRO** | Quebra renderizacao no GitHub/viewer | Bloqueia merge / viewer mostra fallback ruim |
| **AVISO** | Renderiza mas sub-otimo | Afeta legibilidade mas nao quebra |
| **INFO** | Sugestao de melhoria | Opcional |

---

## ETAPA 4: REPORTAR

Output em formato tabular:

```markdown
## Rendering Validation Report

**Escopo**: [path validado]
**Arquivos analisados**: [N]

### Resumo

| Severidade | Quantidade |
|------------|------------|
| ERRO       | [N]        |
| AVISO      | [N]        |
| INFO       | [N]        |

### Findings

| Arquivo | Linha | Severidade | Tipo | Mensagem |
|---------|-------|------------|------|----------|
| docs/foo.md | 42 | ERRO | Mermaid | participant `Usuario` nao declarado antes de uso |
| docs/bar.md | 15 | ERRO | Link | Arquivo nao encontrado: `../baz.md` |
| docs/baz.md | 88 | AVISO | CodeBlock | Fence sem linguagem declarada |

### Proximos Passos

- Corrigir ERROs antes de commitar
- AVISOs podem ser agendados para proximo cleanup
- Re-rodar esta skill para confirmar fix
```

**Exit code**: 0 se zero ERROs, 1 se houver ERROs (para uso em hook/CI).

---

## Gotchas

### Esta skill NAO substitui validate-documentation nem analyze

- `validate-documentation`: valida estrutura textual de um documento (secoes obrigatorias, minimos de conteudo)
- `analyze`: valida consistencia cross-artifact (spec vs plan vs tasks)
- `validate-docs-rendered`: valida que a documentacao **renderiza corretamente** quando consumida

As tres sao complementares — rodar todas num fluxo de quality gate.

### Validacao de Mermaid e heuristica, nao renderer real

Sem um renderer Mermaid de verdade (mmdc, kroki), a validacao se baseia em
regex e regras sintaticas. Captura a maioria dos erros mas pode deixar passar
edge cases. Para validacao 100%, considerar integrar com `@mermaid-js/mermaid-cli`
no pipeline CI.

### Links case-sensitive em GitHub mas case-insensitive em macOS

Um link `[x](./Foo.md)` funciona em macOS (filesystem case-insensitive por
default) mas quebra em Linux/GitHub. A validacao trata essa discrepancia como
AVISO, nao ERRO — ajustar para ERRO se o time roda Linux exclusivamente.

### Code blocks em Markdown aninhados

Quando um arquivo .md documenta sintaxe Markdown, os fences aninhados podem
confundir a validacao. A skill escapa isso detectando `~~~` como delimitador
alternativo ou ignorando blocks dentro de heredocs.

### Anchors do GitHub seguem regra especifica

O slug de um header em GitHub e: lowercase, `-` no lugar de espacos, remocao
de pontuacao. Mas GitLab e MkDocs tem regras ligeiramente diferentes. A skill
valida contra a regra do GitHub por padrao — configurar em `config.json` se
o consumidor principal e outro.

### Rodar em CI e valioso — local como pre-commit e rapido demais

Esta skill e rapida (segundos para arvores pequenas) mas ainda assim,
rodar a validacao completa em cada commit pode irritar. Consideracoes:
- **Local (pre-commit)**: validar so arquivos alterados
- **CI (PR checks)**: validar arvore completa
- **Scheduled**: rodar em main periodicamente para detectar link rot externo
