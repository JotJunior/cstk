# Data Model: Apresentacao Narrativa do Projeto

## Entity: Inventario (`inventory.tsv`)

Saida de `scan-project-docs.sh inventory`. Texto, uma linha por registro,
campos separados por TAB, primeiro campo = tipo do registro. Primeira
linha e o cabecalho `# cstk-presentation-inventory v1`. Valor ausente =
`-` (nunca `0` inventado). Paths relativos ao diretorio de trabalho em
que o scan rodou (ex.: `docs/specs/foo/spec.md`).

| Registro | Campos (apos o tipo) |
|----------|----------------------|
| `project` | `name` |
| `briefing` | `path`, `digest`, `title` |
| `constitution` | `path`, `digest`, `version` |
| `principle` | `ordinal`, `numeral`, `non_negotiable` (`yes`/`no`), `title` |
| `spec` | `key`, `status`, `date`, `stage`, `artifacts`, `clarify_sessions`, `clarify_questions`, `tasks_done`, `tasks_total`, `converge`, `digest`, `path`, `title` |
| `totals` | `specs`, `active`, `archived`, `living`, `tasks_done`, `tasks_total`, `clarify_questions`, `principles` |

### Campos de `spec`

| Campo | Regra |
|-------|-------|
| `key` | caminho relativo a `specs/`: `foo`, `_archived/2026-09-09-foo`, `current/foo` |
| `status` | `active` (`specs/*/`), `archived` (`specs/_archived/*/`), `living` (`specs/current/*.md`) |
| `date` | prefixo `AAAA-MM-DD-` do diretorio arquivado; `-` caso contrario |
| `artifacts` | lista separada por virgula dentre `spec,plan,research,data-model,quickstart,tasks,checklists,contracts,converge-report`; `-` se vazia |
| `clarify_sessions` | linhas `### Session` em `spec.md` |
| `clarify_questions` | linhas `- Q:` em `spec.md` |
| `tasks_done` / `tasks_total` | itens `- [x]` / itens `- [ ]`, `[x]`, `[~]`, `[!]` em `tasks.md`; `-` sem `tasks.md` |
| `converge` | ultimo `outcome=` de `converge-report.md`; `-` sem marcador |
| `stage` | `living` se viva; `implemented` se `tasks_total>0` e `done=total`; `in-progress` se `tasks_total>0` e `done<total`; `archived` se arquivada sem tasks; `specified` caso contrario |
| `digest` | `cksum` do conteudo concatenado dos arquivos da spec em ordem `LC_ALL=C` |
| `title` | titulo do `# ` de `spec.md` sem o prefixo `Feature Specification:`/`Capability:`; fallback = nome do diretorio |

**Ordem**: arquivadas por (`date` ou `0000-00-00`, `key`), depois ativas
por `key`, depois vivas por `key` (research Decision 8).

## Entity: Diff de inventario

Saida de `scan-project-docs.sh diff --old A --new B`: uma linha por item
(`briefing`, `constitution`, cada `spec`), `estado<TAB>tipo<TAB>chave`,
com `estado` em `added|changed|removed|unchanged`.

## Entity: Story (`story.md`)

Frontmatter YAML simples (`chave: valor`, uma por linha) entre `---`:
`title` (obrigatorio), `subtitle`, `project`, `lang` (obrigatorio,
`pt-BR` ou `en`), `generated` (`AAAA-MM-DD`). Corpo = sequencia de
slides. Contrato completo em
[contracts/slide-grammar.md](./contracts/slide-grammar.md).

## Entity: Slide

| Atributo | Regra |
|----------|-------|
| `type` | um de `cover`, `manifesto`, `briefing`, `constitution`, `chapter`, `spec`, `timeline`, `numbers`, `closing`, `sources` |
| `key` | obrigatorio e unico em `spec`; deve existir no inventario |
| conteudo | Markdown restrito + diretivas `@metric`, `@source`, `@timeline`, `@sources` |

## Entity: Chave de metrica

| Escopo | Chaves |
|--------|--------|
| slide `spec` | `tasks` (`done/total`), `tasks-done`, `tasks-total`, `clarify-sessions`, `clarify-questions`, `artifacts` (quantidade), `converge`, `date`, `stage`, `status` |
| demais slides | `specs`, `specs-active`, `specs-archived`, `specs-living`, `tasks` (`done/total`), `tasks-done`, `tasks-total`, `clarify-questions`, `principles`, `constitution-version` |

Valor `-` no inventario e exibido como "nao registrado" (ou "not
recorded"), nunca como numero.

## Entity: Deck (`index.html`)

Derivado. Um `<section class="slide slide--<tipo>">` por slide, dentro do
template com CSS e JS inline. Nunca editado a mao.
