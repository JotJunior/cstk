# Contract — `model-routing.sh wave-select` + integração de command

Interface do novo subcomando que computa o modelo por onda e dos pontos de
integração nos commands/orquestradores. Idioma do contrato: agnóstico de impl,
mas aterrado nos helpers POSIX existentes do `agente-00c-runtime`.

## Subcomando novo: `model-routing.sh wave-select`

Computa o modelo a aplicar na próxima onda e registra a Decisão auditável.

```
model-routing.sh wave-select --state-dir <SD> [--etapa <fase>] [--task-text <desc>]
```

| Flag | Obrigatória | Descrição |
|---|---|---|
| `--state-dir` | sim | diretório de estado da execução |
| `--etapa` | não | fase da próxima onda; default = ler `.etapa_corrente` do state |
| `--task-text` | não | descrição da tarefa corrente (só usado quando fase=execute-task, alimenta o refino via `invoke --input-text`). Tratado como UNTRUSTED — ver §Segurança |

**Saída (stdout)**: uma linha com o modelo a aplicar:
`haiku` | `sonnet` | `opus` | `manter-atual`.

**Efeito colateral**: registra uma `DecisãoDeRoteamentoPorOnda` (via
`state-decisions.sh register`) + `state-ondas.sh record-skill` quando o refino
invocou model-selector (par atômico-lógico I3 reusado da feature original).

**Exit codes**: `0` sucesso (inclui fallback graceful); `2` uso incorreto
(flags inválidas); nunca aborta por indisponibilidade do model-selector.

**Algoritmo** (espelha State Transitions do data-model):
1. Resolver fase (flag ou `.etapa_corrente`).
2. Idempotência: se já existe DecisãoDeRoteamentoPorOnda para esta onda, ecoar o
   modelo já decidido e sair (FR-008, reusa `idempotent-check`).
3. Override: procurar DecisãoDeOverride não-consumida p/ a onda → se houver, aplica
   (origem=override-operador), marca consumida.
4. Mapa (primário): `phase-model-lookup --fase <f>` → modelo-base (origem=mapa).
5. Refino (só execute-task + task-text): `invoke --input-text <desc>`; se
   `score_runtime >= 2` e `fallback=false`, ajusta a faixa (origem=refino).
6. Validar modelo ∈ {haiku,sonnet,opus,manter-atual}; inválido → manter-atual
   (origem=fallback).
7. Registrar Decisão (sugerido, aplicado, origem) + record-skill se refinou.
8. Emitir modelo aplicado em stdout.

## Subcomando novo: `model-routing.sh phase-model-lookup`

Lookup POSIX-puro (sem jq) no `references/phase-model-map.txt`.

```
model-routing.sh phase-model-lookup --fase <fase>
```

**Saída**: `faixa|modelo` (ex.: `profunda|opus`); fase desconhecida → `|manter-atual`
(FR-020 — tolera evolução do mapa, nunca erro). Path do mapa confinado ao diretório
do runtime, canonicalizado, sem traversal (FR-024).

## Segurança e robustez

- **`--task-text` UNTRUSTED (FR-022)**: vem de descrição de tarefa potencialmente
  arbitrária. Antes de alimentar o `invoke --input-text`: remover NUL, truncar a um
  teto de bytes documentado, e nunca expandir sem aspas (reuso das mitigações
  F-001/F-002 da feature original — `jq --arg`, sem `eval`).
- **Override validado (FR-023)**: o valor `model-override:<x>` é validado contra
  `{haiku,sonnet,opus}`; inválido → fallback (mapa/`manter-atual`) com Decisão
  auditável, nunca propagado ao spawn. Escopo: uma única onda.
- **Dado sensível em Decisão (FR-025)**: texto livre derivado da tarefa gravado em
  `justificativa`/`sinais_text` segue o mesmo scrub untrusted aplicado na ingestão
  do recall; nenhum segredo novo é introduzido no `state.json`.
- **Modelo validado (SC-007)**: toda sugestão (mapa/refino/override) é validada
  contra o enum antes do spawn; valor inválido → `manter-atual`.

## Integração: commands de spawn (agente-00c, feature-00c) e resume

**Ponto de inserção**: imediatamente ANTES do bloco `Agent(...)` que spawna o
orquestrador (step 6 do resume; passo equivalente no command inicial).

**Procedimento instruído ao top-level**:
1. `MODEL=$(model-routing.sh wave-select --state-dir <SD>)` (via Bash).
2. Se `MODEL = manter-atual`: spawnar `Agent(...)` SEM o param `model` (herda).
3. Senão: spawnar `Agent(... , model: <MODEL>, ...)`.

> O contrato do prompt do orquestrador não muda — só o invólucro do spawn ganha o
> param `model`. O orquestrador (subagente) permanece inalterado quanto a isso.

## Integração: sequência pré-spawn de clarify (orquestradores)

**Mudança no passo 8** (§5.e.bis / seção model-routing dos orquestradores): quando
o spawn de `clarify-asker`/`clarify-answerer` de fato ocorre, passar
`model=<MODELO>` (do JSON do `invoke`, se `score>=2` e não-fallback) ao
`tool Agent`. Caso `manter-atual`/fallback: omitir (FR-003, FR-006).

**Preservar (FR-004)**: quando o spawn degrada para mediação inline, NÃO aplicar
override e NÃO gerar Decisão órfã — comportamento atual intacto.

## Integração: agregador de auditoria (review-task)

`model-routing-report.sh aggregate` passa a reportar, além do existente:
- distribuição do `modelo_aplicado` (não só sugerido);
- taxa de `origem=fallback` (manter-atual) e `origem=override-operador`;
- contagem de divergências sugerido≠aplicado com origem rotulada (deve casar
  fallback+override; 0 divergências sem rótulo — SC-006);
- half-records pendentes = 0 (reusa reconciliador existente).

**Coexistência com Decisões legadas (FR-021)**: o agregador trata SEM erro duas
gerações de Decisão de model-routing — as novas (com `modelo_aplicado`/`origem`) e
as legadas audit-only da feature original (`escolha=fallback-default`, sem campo
aplicado). Decisões legadas são contabilizadas como `origem=fallback` (não
aplicado) e distinguidas no relatório, sem quebrar a agregação.

## Escalonamento mid-onda (FR-015)

Quando o orquestrador detecta que a onda excedeu a complexidade prevista, registra
um sinal no state (campo/flag de escalada) e **conclui a onda no modelo atual**. O
`wave-select` da PRÓXIMA onda lê esse sinal e força `opus` (origem=mapa com nota de
escalada), independentemente do mapa-base da fase seguinte. Sem abortar, sem trocar
modelo mid-run.
</content>
