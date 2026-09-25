# Implementation Plan: Apresentacao Narrativa do Projeto

**Feature**: `presentation` | **Date**: 2026-09-25 | **Spec**: [spec.md](./spec.md)

## Summary

Nova skill complementar `presentation` (`/presentation`) que atua como
redatora: um script POSIX deterministico inventaria `docs/` (briefing,
constitution, specs ativas, arquivadas e vivas), o LLM escreve a narrativa
em `story.md` numa gramatica restrita, um validador confere a story contra
o inventario e um render em `awk` injeta os slides num template HTML
autocontido (CSS e JS inline, fontes do sistema). Metricas nunca sao
escritas pelo redator: a story referencia chaves do inventario e o render
resolve os valores. A retroalimentacao usa o `inventory.tsv` gravado na
geracao anterior como linha de base de digests.

## Technical Context

**Language/Version**: POSIX sh (`#!/bin/sh`, `set -eu`) + POSIX awk; HTML5/CSS/JS vanilla no template
**Primary Dependencies**: nenhuma alem de utilitarios POSIX (`awk`, `sed`, `grep`, `find`, `sort`, `cksum`); sem `jq`
**Storage**: arquivos no projeto-alvo: `docs/presentation/{story.md,inventory.tsv,index.html}`
**Testing**: harness `tests/run.sh`; `tests/test_scan-project-docs.sh`, `tests/test_validate-presentation.sh`, `tests/test_render-presentation.sh`; fixture `tests/fixtures/presentation/`
**Target Platform**: macOS + Linux (BWK awk, mawk e gawk; nada de `gensub`, `match(..., arr)`, `sed -i`, `stat -c`); HTML em navegadores evergreen, offline
**Project Type**: skill do toolkit (SKILL.md + templates + references + scripts)
**Performance Goals**: scan, validate e render < 5 s cada sobre o proprio cstk (> 50 specs)
**Constraints**: zero rede no HTML (Principio IV); zero fabricacao de metrica (Principio VI); render deterministico byte a byte; saida sem emojis
**Scale/Scope**: projetos de 0 a ~100 specs; um slide por spec

Nenhum `NEEDS CLARIFICATION`; detalhes em [research.md](./research.md).

## Constitution Check

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD recursivo | PASS | spec, clarify, plan, checklist, tasks nesta pasta; bump MINOR (skill nova) |
| II. POSIX sh puro | PASS | 3 scripts `#!/bin/sh` + `set -eu`, awk POSIX, sem `jq`; teste 1:1 para cada |
| III. Formato canonico de skill | PASS | SKILL.md enxuto com `## Gotchas`; template, gramatica e guia narrativo em subpastas; description como trigger |
| IV. Zero coleta remota | PASS | HTML autocontido, sem CDN, sem fontes remotas, sem links externos gerados; nada sai do filesystem local |
| V. Profundidade > adocao | PASS | serve aos projetos onde o toolkit e aplicado (reduz retrabalho de redigir status e decks a partir de artefatos existentes); nao e marketing do cstk |
| VI. Veracidade de dados | PASS | fatos vem do scan; metricas por chave resolvida no render; `@source` obrigatorio em slides factuais; valor ausente vira "nao registrado", nunca `0` |

## Project Structure

### Documentation (this feature)

```
docs/specs/presentation/
├── spec.md
├── plan.md                      # este arquivo
├── research.md                  # Phase 0
├── data-model.md                # Phase 1 (Inventario, Story, Slide, Deck)
├── quickstart.md                # Phase 1 (cenarios de validacao)
├── checklists/requirements.md
├── contracts/
│   ├── cli-invocation.md        # /presentation + 3 scripts
│   └── slide-grammar.md         # gramatica do story.md
└── tasks.md
```

### Source Code (repository root)

```
plugins/cstk/skills/presentation/            # [PROPOSTA] NOVO
├── SKILL.md
├── templates/{story.md,presentation.html,theme.css,deck.js}
├── references/{slide-grammar.md,narrative-guide.md,source-mapping.md}
├── scripts/{scan-project-docs.sh,validate-presentation.sh,render-presentation.sh}
└── evals/triggers.jsonl

plugins/cstk/evals/presentation/NNN/case.yaml  # gerado por gen-eval-cases.sh
tests/test_{scan-project-docs,validate-presentation,render-presentation}.sh
tests/fixtures/presentation/                   # projeto minimo + story valida
tests/trigger-eval/negatives.jsonl             # [EXISTENTE] + negativos
scripts/profiles.txt.in                        # [EXISTENTE] + complementary:presentation
README.md, README.pt-BR.md                     # [EXISTENTE] contagens 21→22, 10→11, 28→29
CHANGELOG.md + manifests em lockstep           # 10.8.0
```

**Structure Decision**: tres scripts de responsabilidade unica (fatos,
validacao, render) em vez de um script com muitos subcomandos: cada um e
testavel isolado e o SKILL.md orquestra a sequencia. O template fica em
quatro arquivos editaveis (HTML, CSS, JS, story) que o render costura num
arquivo unico.

## Convencoes de Borda

Unica fronteira: story (texto do LLM) → HTML. Todo texto e escapado
(`&`, `<`, `>`, `"`) antes da formatacao inline; nenhum HTML cru do
redator chega ao deck. Identificadores e chaves em ingles (`active`,
`implemented`, `tasks-done`); rotulos visiveis localizados por `lang`.

## Riscos e mitigacoes

| Risco | Mitigacao |
|-------|-----------|
| Diferencas entre awks (BWK/mawk/gawk) | so funcoes POSIX (`index`, `substr`, `split`, `sub`, `gsub`, `sprintf`); teste roda com o awk do sistema |
| Tom "vendavel" inventar numeros | `@metric` por chave; guia narrativo proibe numero literal fora de `@metric`; validador pega chave invalida |
| Deck enorme em projetos maduros | modo relatorio com indice; slide de spec com densidade fixa (4 blocos curtos); guia recomenda delegar capitulos a subagentes |
| `</script>` ou `{{` no conteudo | texto escapado; marcadores do template so reconhecidos em linha propria |
| Edicao manual perdida na regeneracao | FR-008: slides `unchanged` preservados literalmente; `--full` e opt-in explicito |

## Complexity Tracking

Sem violacoes de constitution.

## Re-check pos-design

Design manteve scripts POSIX sem dependencia nova, HTML sem rede e
metricas por chave. Todos os MUST seguem PASS.
