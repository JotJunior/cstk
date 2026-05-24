# Quickstart — model-routing-por-onda (cenários de teste)

Cenários executáveis que validam os fluxos críticos. Feature é single-layer
(helpers POSIX + agents/commands markdown) — sem borda backend↔frontend, logo sem
roundtrip HTTP. A validação é via `tests/run.sh` (harness POSIX existente).

## Cenário 1 — Mapa primário decide onda mecânica (happy path)

1. Preparar state com `.etapa_corrente = "review-task"`.
2. Rodar `model-routing.sh wave-select --state-dir <SD>`.
3. **Expected**: stdout = `haiku`; uma DecisãoDeRoteamentoPorOnda registrada com
   `origem=mapa`, `modelo_sugerido=modelo_aplicado=haiku`, score 0.

## Cenário 2 — Onda de raciocínio mantém opus

1. State com `.etapa_corrente = "plan"`.
2. `wave-select`.
3. **Expected**: stdout = `opus`; Decisão `origem=mapa`, aplicado=opus.

## Cenário 3 — Refino eleva execute-task profundo

1. State com `.etapa_corrente = "execute-task"`; tarefa corrente descrita com
   verbos profundos do catálogo expandido (ex.: "refatore e arquitete o módulo").
2. `wave-select --task-text "<descrição>"`.
3. **Expected**: mapa-base = sonnet, refino com score>=2 → stdout = `opus`;
   Decisão `origem=refino`, sugerido=sonnet, aplicado=opus; record-skill
   model-selector presente.

## Cenário 4 — Refino sem sinal mantém o mapa

1. State `execute-task`; task-text sem verbos do catálogo.
2. `wave-select --task-text "<descrição neutra>"`.
3. **Expected**: stdout = piso do mapa (sonnet); Decisão `origem=mapa` (refino
   retornou indeterminado/manter-atual, não alterou).

## Cenário 5 — Override do operador vence (FR-016)

1. Registrar DecisãoDeOverride `escolha=model-override:haiku` para a onda N.
2. State `.etapa_corrente = "plan"` (mapa diria opus).
3. `wave-select`.
4. **Expected**: stdout = `haiku`; Decisão `origem=override-operador`,
   sugerido=opus, aplicado=haiku; override marcado consumido.

## Cenário 6 — Fallback gracioso (model-selector ausente)

1. Forçar model-selector indisponível (skill-not-found via path).
2. State `execute-task` com task-text.
3. `wave-select --task-text "..."`.
4. **Expected**: exit 0; stdout = piso do mapa (refino não roda); Decisão sem
   record-skill órfão; nenhuma onda abortada.

## Cenário 7 — Idempotência na retomada (FR-008)

1. State com DecisãoDeRoteamentoPorOnda já presente para a onda corrente.
2. `wave-select` (simula re-entrada via resume).
3. **Expected**: stdout = modelo já decidido; NENHUMA segunda Decisão registrada.

## Cenário 8 — manter-atual omite o param model no spawn

1. State com fase não-mapeada (→ manter-atual).
2. `wave-select`.
3. **Expected**: stdout = `manter-atual`; o command, ao ver isso, spawna o
   orquestrador SEM o param `model` (herda o modelo da sessão).

## Cenário 9 — Escalonamento mid-onda (FR-015)

1. Onda spawnada em sonnet sinaliza subestimação no state.
2. `wave-select` da próxima onda.
3. **Expected**: stdout = `opus` independentemente do mapa-base da fase seguinte;
   Decisão com nota de escalada.

## Cenário 10 — Catálogo expandido discrimina (SC-008)

1. Rodar `classify.sh` sobre o corpus de referência rotulado em `tests/fixtures/`.
2. **Expected**: taxa de `indeterminado` ≤ 25%; rasa vs profunda corretas nos
   demais; contagem de termos do catálogo bate com o snippet de validação
   atualizado em `sinais.md`.

## Cenário 11 — Override inválido cai em fallback (FR-023)

1. Registrar DecisãoDeOverride `escolha=model-override:gpt4` (modelo inválido) p/ a
   onda N.
2. State `.etapa_corrente = "plan"`.
3. `wave-select`.
4. **Expected**: override rejeitado (não está no enum); stdout = modelo do mapa
   (opus); Decisão `origem=fallback`/mapa com nota de override inválido; nada
   inválido propagado ao spawn.

## Cenário 12 — task-text untrusted é sanitizado (FR-022)

1. State `execute-task`; `--task-text` contendo metacaracteres/NUL/payload longo
   (ex.: `"; rm -rf /` + bytes NUL + 10 KB de texto).
2. `wave-select --task-text "<payload>"`.
3. **Expected**: exit 0; NUL removido, input truncado ao teto, nenhum comando
   executado (sem eval/expansão); refino roda sobre o texto sanitizado ou degrada
   para o mapa; nenhuma onda abortada.

## Verificação geral

```bash
./tests/run.sh model-routing      # subcomandos wave-select + phase-model-lookup
./tests/run.sh model_selector     # catálogo expandido + regressão
./tests/run.sh --check-coverage   # todo .sh novo tem teste (orphan check)
```
</content>
