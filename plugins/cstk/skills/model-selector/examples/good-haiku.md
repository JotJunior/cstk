# Exemplo good-case — faixa rasa → `haiku`

Caso canonico de input com **>=2 verbos rasos** (operacao mecanica,
ZERO ambiguidade, output curto). Classificador detecta sinais consistentes em
faixa unica `rasa` e aplica TETO 2 (dec-006). Modelo sugerido: `haiku`
(barato, rapido). Alternativa de fallback: `sonnet` (tier acima).

## Input

```text
rode o grep e formate a saida
```

## Sinais que disparam

| token | termo do catalogo | faixa | peso |
|-------|-------------------|-------|------|
| `rode` | `rode` | rasa | 1 |
| `grep` | `grep` | rasa | 1 |
| `formate` | `formate` | rasa | 1 |

Tokens nao-sinal (`o`, `e`, `a`, `saida`) sao ignorados — `grep -Fxq`
e match EXATO por linha do catalogo, sem substring.

## Regra aplicada

- `rasa=3 media=0 profunda=0` → unica faixa com contagem > 0 = `rasa`.
- Faixa unica → conservador FR-005 nao age (sem contradicao).
- Score teorico (3 sinais) seria > 2, mas TETO pratico = 2 (dec-006,
  Gotcha (d) — auto-invocacao da heuristica nunca emite 3).

## Output esperado (literal de `classify.sh`)

```markdown
## Modelo Sugerido

haiku

## Score

2

rasa=3 media=0 profunda=0 faixa=rasa
score=2 modelo=haiku alternativa=sonnet

## Justificativa

sinais detectados: rode (rasa), grep (rasa), formate (rasa); contagens rasa=3 media=0 profunda=0; sinais consistentes em faixa unica (rasa); TETO 2 aplicado (score teto, dec-006).

## Alternativa

sonnet
```

## Reproducao

```sh
sh plugins/cstk/skills/model-selector/scripts/classify.sh "rode o grep e formate a saida"
```

Exit code `0`. Stderr vazio.
