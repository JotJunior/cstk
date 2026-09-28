# Quickstart: Apresentacao Narrativa do Projeto

Cenarios de validacao. Os cenarios 1 a 10 sao automatizados em
`tests/test_{scan-project-docs,validate-presentation,render-presentation}.sh`
sobre a fixture `tests/fixtures/presentation/`; 11 e 12 sao manuais
(dogfooding).

| # | Cenario | Esperado | Cobre |
|---|---------|----------|-------|
| 1 | `scan-project-docs.sh inventory --docs docs` na fixture | registros `project`, `briefing`, `constitution`, `principle`, `spec` (ativa, arquivada, viva), `totals` | FR-003, FR-004 |
| 2 | fixture com briefing so no caminho legado | `briefing` aponta para `01-briefing-discovery/briefing.md` | FR-003 |
| 3 | spec com tasks parcialmente concluidas | `stage=in-progress`, `tasks_done<tasks_total` | FR-004 |
| 4 | `diff` apos adicionar spec e alterar outra | `added` e `changed` corretos, demais `unchanged` | FR-007 |
| 5 | `validate-presentation.sh` na story da fixture | exit 0, `errors=0` | FR-014 |
| 6 | story sem slide para uma spec | exit 1, `spec sem slide` | FR-005 |
| 7 | `@metric` com chave inventada / slide sem `@source` / placeholder | exit 1 com a linha do problema | FR-013, FR-014 |
| 8 | render da fixture | um `<section class="slide` por slide; CSS e JS inline; nenhum recurso de rede | FR-010, FR-016 |
| 9 | render duas vezes | `cmp` identico | FR-012 |
| 10 | story com `<script>` e `&` no texto | escapados no HTML | FR-015 |
| 11 | dogfooding no cstk: scan, story completa, validate, render | validate exit 0; todas as specs com slide | SC-001, SC-005 |
| 12 | abrir o `index.html` no Chromium com rede bloqueada; alternar slides (setas), relatorio (R), tema (T); largura 390px; imprimir em PDF | zero requisicoes, zero erros de console, layout integro | FR-011, SC-002 |

## Fluxo manual

```sh
S=plugins/cstk/skills/presentation/scripts
mkdir -p docs/presentation
sh $S/scan-project-docs.sh inventory --docs docs > docs/presentation/inventory.tsv
# ... redator escreve docs/presentation/story.md ...
sh $S/validate-presentation.sh --story docs/presentation/story.md --inventory docs/presentation/inventory.tsv
sh $S/render-presentation.sh --story docs/presentation/story.md --inventory docs/presentation/inventory.tsv --out docs/presentation/index.html
```
