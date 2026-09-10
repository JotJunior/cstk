# Contract: maquina de etapas (`pipeline.sh`) — delta

Documenta o contrato **existente** de
`plugins/cstk/skills/agente-00c-runtime/scripts/pipeline.sh` (extraido por
leitura direta do arquivo) e o delta introduzido por esta feature. O delta
esta marcado como **[PROPOSTA — a validar na implementacao]**; o restante
descreve comportamento hoje verificavel.

## Estado ATUAL (verificado no codigo)

`_PL_STAGES_LIST` (linha 96) — 10 etapas:

```
briefing constitution specify clarify plan checklist create-tasks execute-task review-task review-features
```

Subcomandos que iteram a lista: `stages`, `next-stage`, `prev-stage`, e a
validacao de `--stage` em `detect-completion` (via `_pl_is_valid_stage_in`).

`--mode` (feature `roadmap-mode`): `_pl_mode_list` seleciona a lista efetiva —
`roadmap` devolve `briefing constitution roadmap`; qualquer outro valor
devolve `_PL_STAGES_LIST`. `--mode` **nunca edita** a lista global.

`detect-completion` — artefato esperado por etapa (recorte relevante):

| Etapa | Criterio atual |
|-------|----------------|
| `create-tasks` | `tasks.md` existe **e** passa `_pl_validate_tasks` |
| `execute-task` | `tasks.md` existe **e** tem ao menos uma linha `- [x]` |
| `review-task`, `review-features` | `return 0` incondicional — "etapas de review nao deixam artefato persistente" |

## Delta [PROPOSTA — a validar na implementacao]

### D1. Lista canonica: 10 -> 11 etapas

```
briefing constitution specify clarify plan checklist create-tasks \
  execute-task converge review-task review-features
```

Invariante preservada: `--mode roadmap` continua devolvendo exatamente
`briefing constitution roadmap`, e `--stage roadmap` continua so aceito com
`--mode roadmap` (fail-closed). O comentario das linhas ~147 e ~490-492 e
reescrito para dizer o que de fato afirma — que **`--mode` nao altera a lista
global** — em vez de sugerir imutabilidade permanente do conteudo.

Efeitos automaticos (nenhuma linha adicional de codigo):

| Chamada | Antes | Depois |
|---------|-------|--------|
| `stages` | 10 linhas | 11 linhas |
| `next-stage --current execute-task` | `review-task` | `converge` |
| `next-stage --current converge` | erro (etapa desconhecida) | `review-task` |
| `prev-stage --current review-task` | `execute-task` | `converge` |
| `stages --mode roadmap` | 3 linhas | 3 linhas (inalterado) |

### D2. `detect-completion --stage converge`

```
pipeline.sh detect-completion --feature-dir DIR --stage converge
```

| Situacao | Exit |
|----------|------|
| `DIR/tasks.md` ausente OU sem nenhuma linha de tarefa | 0 (FR-005 — etapa nao se aplica) |
| `converge-status.sh check` exit 0 | 0 |
| `converge-status.sh check` exit 1 ou 3 | 1 |
| skill `converge` **nao instalada** (diretorio `skills/converge/` ausente) | 0 + aviso em stderr — etapa nao se aplica |
| skill `converge` instalada mas `converge-status.sh` ausente/nao-executavel/falho | **1 (fail-closed)** + diagnostico em stderr |

**Decisao de definicao (fecha CHK004)**: `tasks.md` presente mas sem
nenhuma linha de tarefa (0 checkboxes `- [ ]`/`- [~]`/`- [x]`/`- [!]`) e
tratado **igual** a `tasks.md` ausente — a etapa `converge` nao se aplica
(FR-005), mesmo veredito `not-applicable`/exit 0 nos dois casos. Um backlog
esvaziado por edicao manual nao tem nada para reconciliar contra codigo, o
mesmo raciocinio de FR-005 para features que nunca passaram por
criacao/execucao de tarefas.

A distincao das duas ultimas linhas e deliberada e e um requisito de
seguranca (plan.md §Revisao de seguranca, F1). `pipeline.sh` pertence a skill
`agente-00c-runtime` e precisa continuar funcionando em instalacao onde a
skill `converge` nao esta presente — esse e o unico caso de degradacao
aceitavel. Ja um script ausente **dentro de uma skill instalada** indica
catalogo corrompido ou adulterado: degradar para exit 0 ali seria fail-**open**
num ponto que decide avanco de etapa, e a maquina de etapas passaria a
considerar a convergencia concluida sem nunca te-la avaliado.

### D3. Consumidor derivado: `state-ondas.sh end --advance`

Sem alteracao de codigo. `end --advance` resolve a proxima fase por
`pipeline.sh next-stage` e grava `current_stage` + `next_instruction` no mesmo
write atomico; com D1, fechar a onda de `execute-task` com `--advance` passa a
apontar para `converge`. E o mecanismo que satisfaz US2-AS2 em execucao
autonoma.

## Compatibilidade

- **Estado antigo** com `current_stage=review-task` gravado antes desta
  mudanca continua valido: `review-task` segue sendo etapa da lista, e
  `next-stage --current review-task` segue devolvendo `review-features`.
- **Execucao em andamento** que ja passou de `execute-task` para
  `review-task` nao e reprocessada retroativamente — nada le a lista para
  reescrever historico.
- **`--mode roadmap`** e o caminho `roadmap` de `detect-completion` sao
  literalmente intocados.
