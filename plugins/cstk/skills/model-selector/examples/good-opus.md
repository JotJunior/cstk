# Exemplo good-case — faixa profunda → `opus`

Caso canonico de input com verbos de **design/decisao** (multi-arquivo
provavel, consequencia em contrato/security/breaking change). Classificador
detecta sinais consistentes em faixa unica `profunda`. Modelo
sugerido: `opus` (mais capaz). Alternativa de fallback: `sonnet`
(tier abaixo — porem com risco de subdimensionar a tarefa).

## Input

```text
projete a api e refatore o modulo arquitetando o novo componente
```

## Sinais que disparam

| token | termo do catalogo | faixa | peso |
|-------|-------------------|-------|------|
| `projete` | `projete` | profunda | 1 |
| `refatore` | `refatore` | profunda | 1 |

Token `arquitetando` NAO casa `arquitete` — `grep -Fxq` e match
exato de linha. Tokens funcionais (`a`, `o`, `api`, `e`, `modulo`,
`novo`, `componente`) sao ignorados.

## Regra aplicada

- `rasa=0 media=0 profunda=2` → unica faixa com contagem > 0 = `profunda`.
- Score = 2 (>=2 sinais consistentes na mesma faixa — FR-002).
- FR-005 (conservador) nao age (sem mistura), mas o **mesmo** input
  sob `+1 verbo raso` (ex: "rode") manteria `profunda` como
  vencedora — vide Gotcha (b).

## Output esperado (literal de `classify.sh`)

```markdown
## Modelo Sugerido

opus

## Score

2

rasa=0 media=0 profunda=2 faixa=profunda
score=2 modelo=opus alternativa=sonnet

## Justificativa

sinais detectados: projete (profunda), refatore (profunda); contagens rasa=0 media=0 profunda=2; sinais consistentes em faixa unica (profunda).

## Alternativa

sonnet
```

## Reproducao

```sh
sh plugins/cstk/skills/model-selector/scripts/classify.sh "projete a api e refatore o modulo arquitetando o novo componente"
```

Exit code `0`. Stderr vazio.
