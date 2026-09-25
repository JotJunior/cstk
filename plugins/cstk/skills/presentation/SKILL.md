---
name: presentation
description: 'Write the project story as an elegant offline HTML deck (slides + report + PDF) with a Markdown source, from the SDD docs: briefing, constitution and every spec (active, archived, living), one slide per spec covering what it is and how it was thought, enriched and implemented. Executive, inspiring tone; facts and metrics only from a deterministic inventory. Triggers: "presentation", "apresentacao do projeto", "contar a historia do projeto", "deck executivo", "relatorio humanizado", "slides do projeto", "apresentar o projeto". Skip for the status of one feature (use review-task) or a deck unrelated to the project docs.'
argument-hint: "[--docs <dir>] [--out <dir>] [--lang pt-BR|en] [--render-only] [--full]"
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Bash
  - Agent
---

# Skill: Apresentacao do Projeto

Voce e o **redator** da historia do projeto. A partir de `docs/` (briefing,
constitution e todas as specs), escreva uma narrativa executiva e
inspiradora que sirva tanto de apresentacao formal quanto de relatorio
humanizado. O resultado sempre segue o mesmo template:

| Arquivo (em `--out`) | Papel | Quem escreve |
|----------------------|-------|--------------|
| `story.md` | fonte narrativa, editavel, retroalimentada | voce (redator) |
| `inventory.tsv` | fatos e metricas, linha de base do proximo diff | `scan-project-docs.sh` |
| `index.html` | deck unico e offline (slides, relatorio, PDF) | `render-presentation.sh` |

Voce escreve **so** o `story.md`, numa gramatica fechada
(`references/slide-grammar.md`). Fatos vem do inventario; metricas, so
por chave (`@metric Rotulo | chave`). O HTML e sempre derivado.

## Pre-requisitos

- `docs/` com ao menos briefing, constitution ou specs (qualquer
  combinacao; o que faltar nao vira slide).
- Idealmente `/briefing` e `/constitution` ratificados e specs geradas
  pelo pipeline SDD (`/specify` ... `/review-task`).

## Proximos passos

- Abrir `docs/presentation/index.html` no navegador (funciona offline).
- Lapidar o texto direto no `story.md` e rodar `/presentation --render-only`.
- Rodar `/presentation` de novo quando o projeto evoluir: so os slides
  afetados sao reescritos.

## Argumentos

$ARGUMENTS

| Flag | Default | Efeito |
|------|---------|--------|
| `--docs <dir>` | `docs` | raiz das docs a varrer |
| `--out <dir>` | `docs/presentation` | destino das tres pecas |
| `--lang pt-BR\|en` | idioma do briefing (pt-BR se ausente) | idioma do texto e dos rotulos |
| `--render-only` | off | so valida e renderiza; nao toca `story.md` nem `inventory.tsv` |
| `--full` | off | ignora o diff e reescreve a story inteira |

Scripts: `S` = pasta `scripts/` ao lado deste SKILL.md
(`~/.claude/skills/presentation/scripts` na instalacao via `cstk`;
`${CLAUDE_PLUGIN_ROOT}/skills/presentation/scripts` no plugin).

---

## FLUXO DE EXECUCAO

```
1. Inventario ──► 2. Modo ──► 3. Leitura ──► 4. Redacao ──► 5. Validacao ──► 6. Render
   (script)       novo |       (fontes das     (story.md)     (script,         (script) + relato
                  incremental   specs afetadas)                 ate exit 0)
                  | render-only ────────────────────────────────►
```

## ETAPA 1: Inventario

```sh
mkdir -p "$OUT"
sh "$S/scan-project-docs.sh" inventory --docs "$DOCS" > "$OUT/inventory.new.tsv"
```

Leia o inventario inteiro: ele e a lista de slides de spec que voce deve
escrever (um por linha `spec`) e a unica fonte de numeros. Formato em
`references/slide-grammar.md` e no cabecalho do script.

`--render-only`: pule para a ETAPA 5 usando o `inventory.tsv` existente
(se nao existir, pare e peca uma execucao completa).

## ETAPA 2: Modo

- **Novo** (`story.md` ausente ou `--full`): escreva a story inteira a
  partir de `templates/story.md`.
- **Incremental** (`story.md` e `inventory.tsv` existem):

  ```sh
  sh "$S/scan-project-docs.sh" diff --old "$OUT/inventory.tsv" --new "$OUT/inventory.new.tsv"
  ```

  | Estado | Acao no `story.md` |
  |--------|--------------------|
  | `added` | escrever slide novo no capitulo certo (ordem do inventario) |
  | `changed` | reescrever o slide daquela chave (ou os slides de briefing/constitution) |
  | `removed` | apagar o slide daquela chave |
  | `unchanged` | **nao tocar**: preservar o texto literalmente, inclusive edicoes manuais |

  Depois revise so o que depende do conjunto: capitulos (se ganharam ou
  perderam specs), `timeline`, `numbers` e `closing`.

## ETAPA 3: Leitura das fontes

Siga `references/source-mapping.md`. Para cada spec a escrever: linha do
inventario, `spec.md` (titulo, Clarifications, User Story P1),
`research.md` (decisoes), `tasks.md` (fases, Escopo Coberto) e
`converge-report.md`. Leia so o necessario para quatro secoes curtas.

**Volume grande** (mais de 12 specs a escrever): delegue por capitulo com
a tool `Agent`, em paralelo. Cada subagente recebe as linhas do
inventario do capitulo, os caminhos das specs, `references/slide-grammar.md`
e `references/narrative-guide.md`, e devolve **so** os blocos
`<!-- slide: spec key=... -->` prontos. Voce costura capitulos, abertura e
fechamento, e revisa a unidade de tom.

## ETAPA 4: Redacao do `story.md`

Siga `references/narrative-guide.md` (arco, tom, limites de tamanho) e a
gramatica de `references/slide-grammar.md`. Ordem obrigatoria: `cover`
primeiro, `sources` por ultimo. Um slide `spec` por chave do inventario,
com as quatro secoes `###` na ordem: o que e, como foi pensada, como foi
enriquecida, como foi implementada.

## ETAPA 5: Validacao

```sh
sh "$S/validate-presentation.sh" --story "$OUT/story.md" --inventory "$OUT/inventory.new.tsv"
```

(Em `--render-only`, use `--inventory "$OUT/inventory.tsv"`.) Corrija cada
`story.md:LINHA: mensagem` e valide de novo ate `errors=0`. Nunca
contorne o validador (ex.: apagar o `@source` que aponta para arquivo
inexistente em vez de corrigir o caminho).

## ETAPA 6: Render e relato

```sh
mv "$OUT/inventory.new.tsv" "$OUT/inventory.tsv"   # so apos validacao OK; nunca em --render-only
sh "$S/render-presentation.sh" --story "$OUT/story.md" --inventory "$OUT/inventory.tsv" --out "$OUT/index.html"
```

Relate ao operador: caminho do `index.html`, numero de slides, specs
cobertas, o que mudou (em modo incremental) e como usar o deck:
setas navegam, `R` alterna slides e relatorio, `T` alterna o tema, `F`
tela cheia, `P` imprime (um slide por pagina, pronto para PDF).

---

## DIRETRIZES RAPIDAS

- O redator escreve narrativa; o script escreve fatos.
- Um slide por spec, sempre; densidade fixa (lead + 4 secoes curtas).
- Nada de HTML, links ou imagens no `story.md`: o render escapa tudo.
- O template (`templates/presentation.html`, `theme.css`, `deck.js`) e o
  mesmo para todo projeto; nao gere CSS nem HTML por projeto.

### Relacao com Outras Skills

| Skill | Relacao |
|-------|---------|
| `briefing`, `constitution` | fontes da abertura e da fundacao |
| `specify` ... `review-task`, `converge` | produzem os artefatos que viram os slides de spec |
| `review-features` | visao tecnica de status; `presentation` e a visao narrativa |
| `validate-documentation` | qualidade das docs de origem; rode antes se o deck parecer pobre |

## Gotchas

### "Vendavel" nao autoriza numero sem lastro

A pressao por um texto que venda puxa para "reduziu 80% do retrabalho" ou
"centenas de usuarios". Se nao esta no inventario ou literalmente numa
fonte citada, nao entra. Metrica so via `@metric Rotulo | chave`; o
validador rejeita chave inventada e o render nunca escreve `0` para valor
ausente (mostra "nao registrado").

### Estagio vem do inventario, nao da impressao do texto

Spec com tarefas pendentes e "em andamento" mesmo que o `spec.md` soe
concluido. Arquivada sem `tasks.md` nao e "implementada". Escreva a
secao "Como foi implementada" coerente com o selo que o render vai
mostrar, senao o slide se contradiz na frente do leitor.

### Nunca editar o `index.html` a mao

Ele e derivado e sera sobrescrito no proximo render. Ajuste o texto no
`story.md` e rode `--render-only`; ajuste visual e no template da skill,
para todos os projetos.

### Slide `unchanged` e intocavel na regeneracao

O operador pode ter lapidado frases a mao. Reescrever slides cuja fonte
nao mudou apaga esse trabalho em silencio. Em modo incremental, mexa so
em `added`, `changed`, `removed` e nos slides agregados (capitulos,
timeline, numbers, closing). `--full` e opt-in explicito.

### `inventory.tsv` so e promovido depois da validacao

Se voce mover o `inventory.new.tsv` antes de a story passar no
validador e a execucao parar no meio, o proximo diff vai considerar como
`unchanged` specs que nunca ganharam slide atualizado.

### Chave de spec e o caminho relativo a `specs/`

Specs vivas repetem nomes de arquivadas (`current/roadmap-mode` e
`_archived/2026-09-09-roadmap-mode`). Use sempre a chave exata do
inventario em `key=`; nome curto nao casa e o validador acusa
`key desconhecida`.

### Briefing no caminho legado

Projetos antigos tem `docs/01-briefing-discovery/briefing.md`. O scan
acha os dois caminhos; use em `@source` o caminho que o inventario
imprimiu, nunca o que voce supoe.

### Projeto enorme: delegue, mas revise o tom

Com dezenas de specs, subagentes por capitulo aceleram muito, mas cada
um escreve com um sotaque. Antes de validar, leia a story de ponta a
ponta e alinhe titulos (beneficio em ate 8 palavras) e leads (uma frase).
