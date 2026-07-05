# Data Model: Show Tips

**Feature**: `show-tips` | **Date**: 2026-05-27 | **Phase**: 1 (Design)

A feature e stateless e sem banco de dados. O "modelo de dados" e o formato em
disco do catalogo de dicas (`tips/catalog.md`) e as estruturas logicas que o
mecanismo de exibicao produz. Tudo em texto plano POSIX-parseavel.

---

## Entity: Tip (Dica)

Unidade atomica do catalogo. Persistida como um bloco Markdown + frontmatter
YAML dentro de `tips/catalog.md`, delimitado por linhas `---`.

| Campo | Tipo | Obrigatorio | Origem | Notas |
|-------|------|-------------|--------|-------|
| `skill` | string | sim | frontmatter `skill:` | nome exato da skill alvo (ex: `review-task`); casa com diretorio em `global/skills/` ou `language-related/*/skills/` |
| `category` | enum | sim | frontmatter `category:` | `uso` \| `gotcha` \| `avancado` |
| `text` | string | sim | frontmatter `text:` | texto da dica, max 2 frases; uma linha logica no YAML |
| `examples` | string[] | sim (>=1) | corpo Markdown | um ou mais exemplos de uso concreto; cada exemplo pode conter comando e/ou resultado em fence de codigo |

**Validacoes** (verificadas pelo audit, nao em runtime de exibicao):
- `category` ∈ {`uso`, `gotcha`, `avancado`} — valores fora do enum sao
  ignorados pelo filtro mas reportados pela auditoria.
- `text` nao-vazio.
- `examples` com >= 1 entrada (FR-001).

**State transitions**: N/A — Tip e imutavel em runtime; so muda quando o
mantenedor edita o arquivo.

### Representacao em disco (exemplo de uma entrada)

```markdown
---
skill: review-task
category: uso
text: Use /review-task para um relatorio completo do andamento da feature, com tarefas prontas para iniciar.
---
Quer saber como esta o andamento da sua feature?

    /review-task nome-da-skill

Retorna progresso por fase e proximas tarefas desbloqueadas.
```

> Nota de parsing (research.md Decision 2): o separador de entradas e uma linha
> contendo EXATAMENTE `---`. Exemplos no corpo usam fence de codigo ou indentacao,
> nunca uma linha isolada `---`, para nao confundir a maquina de estados do `awk`.

---

## Entity: Tip Catalog

Colecao de todas as Tips do projeto. Fonte unica de verdade para o mecanismo.

| Campo | Tipo | Notas |
|-------|------|-------|
| `path` | path | `tips/catalog.md` (relativo a raiz do repo) |
| `entries` | Tip[] | todas as entradas, em ordem de arquivo |
| `skills_covered` | derivado | conjunto de valores distintos de `Tip.skill` |

**Invariantes** (verificados por `cstk show-tip --audit`, SC-004):
- Cada skill do universo (`global/skills/*` + `language-related/*/skills/*`) tem
  >= 2 entradas (SC-001, FR-002).
- Cada skill coberta tem ao menos as categorias `uso` e `gotcha` (FR-002).
- Cada Tip tem >= 1 exemplo (FR-001).

**Organizacao**: entradas agrupadas logicamente por skill no arquivo (ordem de
leitura humana), mas o parser nao depende da ordem — agrupa por valor de `skill:`.

---

## Entity: Tip Block (saida)

Representacao formatada de uma Tip selecionada, emitida em stdout pelo mecanismo
de exibicao. Estrutura efemera (nao persistida).

| Componente | Conteudo |
|------------|----------|
| borda superior | separador visual (FR-004) |
| cabecalho | skill referenciada + categoria |
| corpo | `text` da dica |
| exemplos | os `examples` da Tip, identados |
| borda inferior | separador visual |

Caso especial (FR-006): quando o catalogo esta ausente/ilegivel ou a skill
solicitada nao tem dicas, o Tip Block e **string vazia** (modo automatico/onda)
ou uma mensagem amigavel com sugestao de skills disponiveis (modo sob demanda
explicito — US3 cenario 2).

---

## Entity: Display Trigger (logico)

Ponto de invocacao do mecanismo. Nao e persistido; e o modo de chamada.

| Trigger | Invocacao | Comportamento em falha |
|---------|-----------|------------------------|
| inicio de onda (automatico, US1/US4) | `cstk show-tip --phase <fase>` | string vazia, exit 0 (fail-silent) |
| sob demanda por skill (US3) | `cstk show-tip <skill>` | mensagem amigavel se skill sem dicas |
| sob demanda sem skill (US3 cenario 3) | `cstk show-tip` | dica aleatoria de qualquer skill |

> Mapeamento fase→skill (modo `--phase`): a fase corrente pode sugerir uma skill
> relevante (ex: fase `plan` → dica da skill `plan`). Quando nao ha mapeamento
> direto, cai para selecao aleatoria global (FR-010). Detalhe no contrato CLI.
