# Data Model — model-routing-por-onda

Entidades conceituais da feature. Não são tabelas SQL — são estruturas de dados
em arquivos versionados e campos de Decisão no `state.json` transacional.

## Entity: MapaFaseModelo (phase-model-map.txt)

Tabela versionada que define o modelo-piso por fase do pipeline (FR-014, mecanismo
PRIMÁRIO).

| Campo | Tipo | Notas |
|---|---|---|
| `fase` | string (enum) | nome da fase: specify, clarify, plan, checklist, create-tasks, analyze, execute-task, validate-docs, review-task, briefing, constitution |
| `faixa` | enum | rasa \| media \| profunda |
| `modelo` | enum | haiku \| sonnet \| opus \| manter-atual |

**Recorte default "3 faixas balanceado"** (FR-014):

| fase | faixa | modelo |
|---|---|---|
| plan | profunda | opus |
| analyze | profunda | opus |
| constitution | profunda | opus |
| specify | media | sonnet |
| clarify | media | sonnet |
| checklist | media | sonnet |
| create-tasks | media | sonnet |
| briefing | media | sonnet |
| execute-task | rasa | sonnet |
| validate-docs | rasa | haiku |
| review-task | rasa | haiku |

> `execute-task` parte de sonnet como piso, mas é a fase onde o **refino** por
> model-selector (D5) pode elevar para opus (tarefa profunda) ou baixar para haiku
> (tarefa trivial) conforme a descrição da tarefa.

**Versão (FR-020)**: o arquivo declara um header de versão (ex. primeira linha
`# phase-model-map v1`). O lookup tolera evolução: fase/linha desconhecida →
`manter-atual` (nunca erro), de modo que adicionar/remover fases não quebra
execuções nem o agregador.

**Regras**: fase não listada → `manter-atual` (sem override). Arquivo lido por
`model-routing.sh phase-model-lookup --fase <f>` (POSIX-puro, sem jq), com path
confinado ao diretório do runtime (FR-024 — canonicalizado, sem traversal).

## Entity: DecisãoDeRoteamentoPorOnda

Decisão auditável registrada no `state.json` (`.decisoes[]`) por onda roteada
(FR-007). Estende o registro de model-routing existente.

| Campo | Tipo | Notas |
|---|---|---|
| `etapa` | string | `model-routing` |
| `contexto` | string | `Selecao de modelo para onda <N> (fase <f>)` |
| `opcoes` | array | `["haiku","sonnet","opus","manter-atual"]` |
| `escolha` | string | modelo **aplicado** (formato `model:<x>` no sucesso; `manter-atual` no fallback) |
| `modelo_sugerido` | string | modelo do mapa/refino antes do override |
| `modelo_aplicado` | string | modelo efetivamente passado ao spawn |
| `origem` | enum | `mapa` \| `refino` \| `override-operador` \| `fallback` |
| `score` | int | 0/2/3 mapeado do model-selector (0 quando origem=mapa puro) |
| `justificativa` | string | sinais do mapa + refino |

**Invariante**: `modelo_sugerido` e `modelo_aplicado` podem divergir SOMENTE com
`origem ∈ {override-operador, fallback}` (SC-006).

## Entity: DecisãoDeOverride (input do operador)

Decisão manual pré-onda que o operador registra para forçar um modelo (FR-016).

| Campo | Tipo | Notas |
|---|---|---|
| `etapa` | string | `model-routing` |
| `escolha` | string | `model-override:<haiku\|sonnet\|opus>` |
| `contexto` | string | começa com `Override de modelo para onda <N>` |
| `consumida` | bool (derivado) | marcada como consumida pela Decisão de roteamento que a aplicou |

**Precedência**: override não-consumido para a onda-alvo vence mapa e refino.

## Entity: ClassificaçãoDeTarefa (refino, efêmera)

Saída do `model-routing.sh invoke --input-text <descrição da tarefa>` (D5). Não
persistida diretamente; alimenta a DecisãoDeRoteamentoPorOnda.

| Campo | Tipo | Notas |
|---|---|---|
| `modelo` | enum | sugestão do model-selector |
| `score_runtime` | int | 0/2/3 |
| `sinais_text` | string | justificativa do classify.sh |
| `fallback` | bool | true se skill ausente/erro → não refina |

## Entity: SinalDeFase (expansão do catálogo)

Linhas adicionadas a `references/sinais.md` do model-selector (FR-018). Mesma
estrutura do `SinalDeClassificacao` existente.

| Campo | Tipo | Notas |
|---|---|---|
| `termo` | string lowercase | sem espaços; formas flexionadas explícitas |
| `faixa` | enum | rasa \| media \| profunda |
| `peso` | int >=1 | default 1 |

## State Transitions — modelo por onda

```
[resume dispara] 
   → le .etapa_corrente (fase da próxima onda)
   → ha DecisãoDeOverride não-consumida p/ a onda?
       sim → modelo_aplicado = override; origem=override-operador
       não → modelo_base = MapaFaseModelo[fase]   (origem=mapa)
             fase==execute-task E ha descrição de tarefa?
                 sim → invoke --input-text <tarefa>
                       score>=2 ? ajusta faixa (origem=refino) : mantém mapa
                 não → mantém mapa
   → modelo inválido/desconhecido OU model-selector indisponível ?
       → fallback manter-atual (origem=fallback)
   → registra DecisãoDeRoteamentoPorOnda (sugerido, aplicado, origem)
   → spawn do orquestrador com model=<aplicado> (omitido se manter-atual)
[mid-onda: subestimação detectada]
   → conclui onda no modelo atual
   → sinaliza escalada → próxima onda parte de opus (FR-015)
```
</content>
