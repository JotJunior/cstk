# Data Model: Retomada da Oferta de Leva Paralela do Roadmap

**Feature**: `roadmap-wave` | **Date**: 2026-08-18 | **Fase**: Phase 1

## Nota de escopo — esta feature NAO cria estado persistente

Nenhuma entidade abaixo e persistida por `roadmap-wave`. Todas ja
existem no sistema e sao **derivadas em tempo de invocacao**:

- `Roadmap` e `Entrada de roadmap` sao lidos de `docs/roadmap.md` por
  `roadmap-status.sh` (script irmao ja existente).
- `Fronteira elegivel` e computada por `roadmap-frontier.sh`, descrito
  no proprio cabecalho como *"computacao pura sobre a saida de
  `roadmap-status.sh --json` (script irmao, INV-3: status NUNCA e
  derivado por leitura propria)"*
  (`plugins/cstk/skills/review-features/scripts/roadmap-frontier.sh:9-12`).
- `Leva` existe apenas durante a interacao (memoria do turno).
- `Ambiente de trabalho isolado` e a worktree criada por
  `cstk session start`, cujo estado vive no git/worktree, nao aqui.

Consequencia normativa: **nao ha `state.json`, nao ha `state.db`, nao
ha migracao de schema, nao ha lock** nesta feature. Ela nao e uma
execucao 00c — e um ponto de entrada que le, oferece e delega.

---

## Entity: Roadmap

Fonte: `docs/roadmap.md` do projeto-alvo (default) ou o path passado em
`--roadmap`.

| Campo | Tipo | Origem | Notas |
|---|---|---|---|
| entradas | lista de `Entrada de roadmap` | `roadmap-status.sh --json` | ordem preservada |

Estados possiveis do artefato inteiro, observaveis **so** pelo exit code
de `roadmap-frontier.sh` (`roadmap-frontier.sh:44-49`):

| Estado | Exit | Significado |
|---|---|---|
| ausente | `1` | roadmap nao encontrado no path resolvido |
| invalido | `3` | presente, mas mal-formado/ilegivel |
| valido | `0` | parseado com sucesso (inclusive fronteira vazia) |
| erro de uso | `2` | flag desconhecida ou path com `..` |
| dependencia ausente | `4` | `roadmap-status.sh` nao esta no diretorio irmao |

---

## Entity: Entrada de roadmap

| Campo | Tipo | Origem | Notas |
|---|---|---|---|
| ordem | inteiro | coluna `ordem` da tabela markdown | `contracts/roadmap-frontier.md:188-191` |
| short_name | string | coluna `short-name` | filtro `^[a-z][a-z0-9-]*$` no launch (`parallel-launch.sh:52`) |
| depende_de | lista de short_name | coluna `depende-de` | `-` literal = sem dependencia |
| status | enum | derivado por `roadmap-status.sh` | `nao-iniciada` \| `em-andamento` \| `concluida` |

**State transitions**: nao sao geridas por esta feature. `status` e
derivado de `tasks.md` da feature-filha — comportamento ja documentado
em `agente-00c.md:1087` (*"`roadmap-status.sh` deriva
`em-andamento` a partir disso (nao de `.execution.status`)"*).

---

## Entity: Fronteira elegivel

Regra de pertencimento (nao reimplementar — ja normatizada em
`docs/specs/roadmap-parallel-launch/contracts/roadmap-frontier.md:74-90`):

1. `E.status == "nao-iniciada"`; **E**
2. para todo `d` em `E.depende_de`, existe `D` com `D.short_name == d`
   e `D.status == "concluida"`.

Filtro adicional aplicado quando `--exclude-active-from-repo PATH` e
usado: remove short-names que ja tem worktree ativa no repo (guarda
anti-duplicidade, FR-009 desta spec).

| Campo | Tipo | Notas |
|---|---|---|
| candidatas | lista de `Entrada de roadmap` | pode ser vazia — **nao e erro** (`contracts/roadmap-frontier.md:193-199`) |
| avisos | secao markdown `### Avisos` opcional | indicio de sobreposicao de artefatos; NUNCA afirmacao de conflito |

---

## Entity: Leva

Efemera (vive so no turno da invocacao).

| Campo | Tipo | Regra |
|---|---|---|
| teto | inteiro >= 1 | default **2** (`agente-00c.md:983`); `--max N` sobrepoe (FR-013) |
| selecionadas | lista de short_name | `|selecionadas| <= teto` (FR-006, SC-004) |
| confirmada | booleano | `false` por default; so `true` com confirmacao explicita (FR-007, FR-014) |

Invariante: `confirmada == false` ⇒ zero worktrees criadas, zero
efeitos colaterais.

---

## Entity: Ambiente de trabalho isolado (worktree)

Criado por `cstk session start <SHORT>`; caminho derivado em
`cli/lib/session.sh:243` (`<pai-do-repo>/<nome-do-repo>-<SHORT>`),
conforme ja documentado em
`docs/specs/roadmap-parallel-launch/contracts/parallel-launch.md` §4.1.

Esta feature **nao cria worktree por conta propria**: executa os
comandos compostos por `parallel-launch.sh emit`, que so imprime.
