# Exemplo good-case — faixa media → `sonnet`

Caso canonico de input com verbos de **explicacao/documentacao**
(raciocinio simples, contexto medio, SEM decisao arquitetural).
Classificador detecta sinais consistentes em faixa unica `media`.
Modelo sugerido: `sonnet` (intermediario). Alternativa de fallback:
`haiku` (tier abaixo — economia se o operador julgar suficiente).

## Input

```text
explique o codigo e documente as funcoes resumindo o comportamento
```

## Sinais que disparam

| token | termo do catalogo | faixa | peso |
|-------|-------------------|-------|------|
| `explique` | `explique` | media | 1 |
| `documente` | `documente` | media | 1 |

Token `resumindo` NAO casa `resuma` — `grep -Fxq` exige linha exata.
Tokens funcionais (`o`, `e`, `as`, `comportamento`, `codigo`,
`funcoes`) sao ignorados.

## Regra aplicada

- `rasa=0 media=2 profunda=0` → unica faixa com contagem > 0 = `media`.
- Score = 2 (>=2 sinais consistentes na mesma faixa — FR-002).
- FR-005 (conservador) nao age (sem mistura de faixas).

## Output esperado (literal de `classify.sh`)

```markdown
## Modelo Sugerido

sonnet

## Score

2

rasa=0 media=2 profunda=0 faixa=media
score=2 modelo=sonnet alternativa=haiku

## Justificativa

sinais detectados: explique (media), documente (media); contagens rasa=0 media=2 profunda=0; sinais consistentes em faixa unica (media).

## Alternativa

haiku
```

## Reproducao

```sh
sh global/skills/model-selector/scripts/classify.sh "explique o codigo e documente as funcoes resumindo o comportamento"
```

Exit code `0`. Stderr vazio.
