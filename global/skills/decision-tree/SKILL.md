---
name: decision-tree
description: 'DEPRECATED (deprecated_since 5.6.0, remove_in 6.0.0 — use o cstk-panel via `cstk serve`, que ja visualiza as decisoes do state.json de forma mais eficiente). Gera um relatorio HTML interativo em arvore de decisao a partir do state.json de uma execucao agente-00c/feature-00c. Use quando o operador pedir para "visualizar/desenhar a arvore de decisoes", "fluxograma das decisoes da IA", "relatorio das decisoes do state.json", "como a IA decidiu", ou similar. NAO use para metricas agregadas de selecao de modelo (use model-routing-report.sh) nem para auditar status de tarefas (use review-task).'
argument-hint: "[caminho para o state.json] [arquivo .html de saida opcional]"
deprecated: true
deprecated_since: 5.6.0
remove_in: 6.0.0
allowed-tools:
  - Read
  - Bash
---

# Skill: Decision Tree

> **⚠️ DEPRECATED desde v5.6.0 — remoção agendada para v6.0.0.**
> O **cstk-panel** (`cstk serve`) trouxe uma solução mais eficiente para
> visualizar as decisões do `state.json` — interface web interativa,
> sempre atualizada, sem gerar arquivos HTML avulsos. Prefira o painel.
> Esta skill continua funcionando até a remoção; nenhum substituto será
> portado para dentro do toolkit (a visualização vive no painel).

Transforma o histórico de decisões de uma execução do orquestrador
(`agente-00c` / `feature-00c`) num diagrama navegável em forma de árvore.
O tronco verde é o caminho cronológico realmente percorrido pela IA: cada
Decisão ramifica nas opções que ela considerou e o galho da opção escolhida
emenda no nó da próxima decisão, de `dec-001` até a última, terminando num
nó de conclusão. Galhos descartados aparecem como folhas tracejadas.

A renderização (SVG + painel de detalhe + zoom) roda no navegador a partir
de um payload JSON embutido; o script POSIX apenas extrai os dados via `jq`
e os injeta no template. O HTML é autocontido (abre offline, sem CDN).

## Quando usar

Use quando o operador pedir para visualizar, desenhar ou inspecionar
visualmente as decisões registradas num `state.json`, por exemplo:

- "monte a árvore de decisões dessa execução"
- "quero um fluxograma de como a IA decidiu"
- "gera o relatório das decisões do state.json"
- "mostra as opções consideradas e o que foi escolhido em cada passo"

NÃO use quando:

- O pedido é por métricas agregadas de seleção de modelo (haiku/sonnet/opus
  + fallback) — use `model-routing-report.sh aggregate`.
- O pedido é por status/progresso de tarefas — use a skill `review-task`.
- Não existe um `state.json` com `.decisoes[]` (a árvore deriva 100% desse
  campo).

## Contrato de entrada

Lê um `state.json` com a estrutura do runtime do agente-00c. Campos
consumidos por Decisão (em `.decisoes[]`):

| Campo | Uso na árvore |
|---|---|
| `id` | rótulo do nó (ex: `dec-001`) |
| `onda_id` | subtítulo do nó |
| `etapa` | agrupamento/faixa colorida de fase |
| `contexto` | título curto sob o nó + painel |
| `opcoes_consideradas[]` | galhos (pílulas de opção) |
| `escolha` | galho destacado que vira tronco para a próxima decisão |
| `justificativa` | painel de detalhe |
| `score_justificativa` | selo de score no nó |

Também usa `.execucao.id`, `.execucao.projeto_alvo_descricao` e
`.execucao.status` para o cabeçalho (todos opcionais).

## Como usar

1. Localize o `state.json` (o operador costuma anexá-lo ou apontar o caminho;
   no runtime fica em `.claude/agente-00c-state/state.json`).
2. Rode o gerador, gravando o HTML na pasta de trabalho/saída:

   ```sh
   sh global/skills/decision-tree/scripts/render-decision-tree.sh \
     render --state /caminho/para/state.json \
            --output /caminho/saida/arvore-decisoes.html
   ```

   - Sem `--output`, o HTML sai em stdout (útil para pipe).
   - `--title "Texto"` sobrescreve o título do cabeçalho (opcional).

3. Entregue o arquivo HTML ao operador (link/clicável). O HTML é autocontido.

## Saída

Um único arquivo `.html` autocontido:

- Tronco verde cronológico ligando as escolhas (`dec-001` → … → fim).
- Cada nó com selo de score; faixas coloridas marcam a troca de etapa.
- Hover/clique abre painel lateral com contexto, todas as opções (escolhida
  destacada) e a justificativa completa.
- Controles de zoom e "ajustar à largura".

## Invariantes

- **IDT-1** read-only: nunca modifica o `state.json` (apenas lê via `jq`).
- **IDT-2** determinístico: sem timestamps no payload — mesmo `state.json`
  produz o mesmo HTML byte-a-byte.
- **IDT-3** POSIX puro (`#!/bin/sh`, `set -eu`), dependendo apenas de `jq`,
  `sed`, `printf`, `cat`, `command`.

## Exemplo

```sh
# Gera a árvore a partir de um state exportado e abre no navegador
sh global/skills/decision-tree/scripts/render-decision-tree.sh \
  render --state ./state.json --output ./arvore-decisoes.html
# render-decision-tree: HTML gerado em ./arvore-decisoes.html (44 decisoes)
```

## Códigos de saída

| Código | Significado |
|---|---|
| 0 | sucesso |
| 1 | erro genérico (state ausente/inválido, `jq` ausente, `.decisoes[]` vazio) |
| 2 | uso incorreto (flag/argumento/subcomando inválido) |

## Gotchas

- **`jq` é dependência OBRIGATÓRIA, sem fallback.** Ao contrário de skills
  com degradação graceful, se `jq` não estiver no PATH o script sai com
  exit 1 — não há caminho alternativo. É consistente com o resto do runtime
  `agente-00c` (todos os helpers exigem `jq`), pois a árvore deriva 100% do
  `state.json` que esse runtime produz.
- **Não remover o `sed 's,</,<\/,g'`** (linha do `_dt_payload`). Campos de
  texto livre do operador (`contexto`, `justificativa`) podem conter literais
  `</script>`; sem esse escape eles fechariam a tag `<script>` do template e
  quebrariam o HTML (ou abririam XSS). A forma escapada `<\/` continua sendo
  JSON/JS válida. O teste `scenario_render_escapa_fechamento_de_script`
  trava essa invariante — exatamente 1 `</script>` legítimo no output.
- **`escolha` fora de `opcoes_consideradas[]` não quebra, mas não destaca
  pílula.** Quando `escolha` não consta nas opções (`_chosenIdx === -1`), o
  tronco verde continua pelo eixo central (AXIS) e nenhuma pílula aparece
  marcada como escolhida (`✓`). A geração segue sem erro — é fallback de
  robustez, não bug. Se você esperava ver a escolha destacada e ela não
  aparece, cheque se o valor de `escolha` bate exatamente com um item de
  `opcoes_consideradas` (comparação literal, sensível a espaços/acentos).
- **Determinismo (IDT-2) proíbe timestamp no payload.** Não adicione data/
  hora de geração ao JSON embutido nem ao HTML — `scenario_render_-`
  `deterministico_byte_a_byte` compara duas execuções byte-a-byte. Qualquer
  valor variável (timestamp, `$RANDOM`, ordem não-determinística) faz o
  teste falhar e destrói a reprodutibilidade.
- **`state.json` válido mas com `.decisoes[]` vazio → exit 1.** A árvore não
  tem o que desenhar sem decisões; isso é intencional (não gera um HTML
  vazio enganoso). Se o operador reclamar de "erro" logo após iniciar uma
  execução, provavelmente ainda não há decisões registradas no state.
- **HTML autocontido — não introduzir CDN/`<script src=...>` externo.**
  O arquivo precisa abrir offline e não fazer requisição de rede
  (Princípio IV). Toda a renderização SVG roda do payload embutido.
