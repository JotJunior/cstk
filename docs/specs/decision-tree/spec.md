# Feature Specification: decision-tree

**Feature**: `decision-tree`
**Created**: 2026-05-23
**Status**: Retroativa (skill já implementada e testada — esta spec ratifica o
contrato existente para conformidade com o Princípio I da constitution)

> **Nota de retroatividade.** A skill `decision-tree` foi adicionada ao
> repositório antes de receber `spec.md`/`tasks.md`, em violação ao Princípio I
> (SDD recursivo). Esta especificação documenta o contrato **já implementado**
> em `global/skills/decision-tree/` e coberto por
> `tests/test_render-decision-tree.sh` (18 cenários). Não introduz mudança de
> comportamento; serve como ratificação e base para evoluções futuras.

## Visão geral

Gera um relatório HTML interativo em forma de **árvore de decisão** a partir do
`state.json` de uma execução do orquestrador `agente-00c` / `feature-00c`. Cada
Decisão de `.decisoes[]` vira um nó; os galhos são as `opcoes_consideradas` e o
galho da `escolha` (tronco verde) conecta cronologicamente à Decisão seguinte,
de `dec-001` até a última, terminando num nó de conclusão.

A renderização (SVG + painel de detalhe + zoom) roda no navegador a partir de um
payload JSON embutido; o script POSIX apenas extrai os dados via `jq` e os
injeta num template HTML autocontido (abre offline, sem CDN).

## User Scenarios

### US-1 — Visualizar como a IA decidiu

Como **operador** de uma execução `agente-00c`/`feature-00c`, quero **ver
graficamente a sequência de decisões** registradas no `state.json`, para
auditar o caminho percorrido sem ler JSON cru.

- **Dado** um `state.json` com `.decisoes[]` não vazio,
- **Quando** rodo o gerador apontando `--state` e `--output`,
- **Então** recebo um `.html` autocontido com o tronco cronológico, cada nó
  com selo de score, e painel de detalhe (contexto, opções, justificativa).

### US-2 — Inspecionar uma decisão específica

Como operador, ao **passar o mouse ou clicar num nó**, quero ver o contexto
completo, todas as opções consideradas (escolhida destacada) e a justificativa.

### US-3 — Pipe para outra ferramenta

Como operador, quero **omitir `--output`** e receber o HTML em `stdout` para
encadear com outro processo.

## Requisitos Funcionais

- **FR-001**: Ler um `state.json` informado via `--state PATH`; `--state` é
  obrigatório. Ausência → exit 2 (uso incorreto).
- **FR-002**: Por Decisão em `.decisoes[]`, consumir `id`, `onda_id`, `etapa`,
  `contexto`, `opcoes_consideradas[]`, `escolha`, `justificativa`,
  `score_justificativa`. Campos ausentes degradam para vazio/`null` (sem erro).
- **FR-003**: Usar `.execucao.id`, `.execucao.projeto_alvo_descricao` e
  `.execucao.status` para o cabeçalho (todos opcionais).
- **FR-004**: Emitir o tronco cronológico ligando a `escolha` de cada Decisão
  ao nó da Decisão seguinte (`dec-001` → … → fim), terminando num nó de
  conclusão rotulado com `.execucao.status`.
- **FR-005**: Sem `--output`, emitir o HTML em `stdout`. Com `--output FILE`,
  gravar em `FILE` e emitir mensagem de progresso em `stderr`.
- **FR-006**: Aceitar `--title STR` para sobrescrever o título do cabeçalho.
- **FR-007**: Escapar `</` para `<\/` em todo o payload, de modo que nenhum
  campo de texto livre possa fechar a tag `<script>` prematuramente.
- **FR-008**: Falhar com exit 1 (mensagem em `stderr`) quando: `--state` aponta
  para arquivo inexistente; JSON ilegível; `jq` ausente no PATH; `.decisoes[]`
  vazio.
- **FR-009**: Subcomando/flag desconhecido ou ausência de subcomando → imprimir
  USO em `stderr` e exit 2.

## Invariantes (load-bearing)

- **IDT-1 (read-only)**: nunca modifica o `state.json` — `jq` sem `-i`, sem
  redirect ao arquivo de entrada.
- **IDT-2 (determinístico)**: sem timestamps/valores variáveis no payload —
  mesmo `state.json` produz o mesmo HTML byte-a-byte.
- **IDT-3 (POSIX puro)**: `#!/bin/sh`, `set -eu`, sem bash-isms; depende apenas
  de `jq`, `sed`, `printf`, `cat`, `command`.
- **IDT-4 (render no cliente)**: a renderização SVG roda no navegador a partir
  do payload embutido; o shell apenas extrai dados + injeta no template.

## Success Criteria

- **SC-1**: `tests/test_render-decision-tree.sh` cobre dispatch, IDT-1/2/3,
  escaping `</script>`, `--output`, `escolha` fora das opções e os exit codes
  0/1/2. Suite verde via `tests/run.sh decision-tree`.
- **SC-2**: `shellcheck -s sh render-decision-tree.sh` sem warnings.
- **SC-3**: `tests/run.sh --check-coverage` não acusa o script como órfão.
- **SC-4**: HTML abre offline em navegador moderno, sem requisição de rede.

## Key Entities

- **Decisão**: unidade do caminho (`.decisoes[i]`) → um nó da árvore.
- **Opção**: item de `opcoes_consideradas[]` → galho/pílula; a que casa com
  `escolha` é o tronco.
- **Payload**: `{ meta, decisoes }` derivado do `state.json`, embutido no HTML.

## Constraint Tecnológica

POSIX sh + `jq` (dependência mandatória — ver Gotchas em `SKILL.md`). Sobre a
relação com o Princípio II (zero dep externa): o uso de `jq` é o mesmo padrão já
estabelecido por todo o `agente-00c-runtime`, cujo `state.json` é a única fonte
da árvore. Não há fallback graceful; portanto **não** se enquadra no carve-out
de deps opcionais (amendment 1.1.0) — é dívida sistêmica do runtime, herdada,
não introduzida por esta feature.

## Escopo Excluído

| Item | Motivo |
|------|--------|
| Métricas agregadas de seleção de modelo | Usar `model-routing-report.sh aggregate` |
| Status/progresso de tarefas | Usar a skill `review-task` |
| Geração sem `.decisoes[]` | A árvore deriva 100% desse campo (exit 1) |
| Edição/escrita no `state.json` | IDT-1 read-only |
