# Quickstart: agente-00c model-routing

Cenarios de teste end-to-end que validam a feature funcionando real
sobre orquestrador + state.json + skill model-selector instalada.
Todos os cenarios assumem repo limpo + `cstk install` recente + skill
`model-selector` em `~/.claude/skills/`.

## Scenario 1: Happy path — 1 spawn registrado com sinais matched

1. Operador inicia `agente-00c` em projeto-alvo com briefing+constitution
   ratificados (ex: este proprio toolkit).
2. Orquestrador chega na fase clarify, encontra ambiguidades, prepara
   spawn de `agente-00c-clarify-asker`.
3. Sequencia pre-spawn roda:
   `spawn-tracker check` -> exit 0 (depth=1 disponivel)
   `model-routing.sh idempotent-check` -> exit 1 (sem decisao previa)
   `model-routing.sh invoke --subagent-type agente-00c-clarify-asker
       --etapa clarify` -> exit 0 com JSON.
4. Orquestrador registra Decisao via `state-decisions.sh register`
   com `escolha=haiku`, `score=3`, `evidencia=<sinais>`.
5. `state-ondas.sh record-skill --skill model-selector --decisao-id
   dec-NNN` cria entrada em `.ondas[N].skills_invoked[]`.
6. `spawn-tracker increment` + tool Agent spawn proceed.

**Expected**:

- `jq '.decisoes[-1] | {contexto, escolha, score}'` retorna
  `{"contexto": "Selecao de modelo para subagente
  agente-00c-clarify-asker", "escolha": "haiku", "score": 3}`.
- `.ondas[<corrente>].skills_invoked` contem 1 entrada com
  `skill="model-selector"` + `decisao_id` apontando para a Decisao
  acima.
- Onda prossegue sem erro; subagente clarify-asker e spawnado.

## Scenario 2: Skill model-selector ausente — fallback gracioso

1. Operador renomeia `~/.claude/skills/model-selector` para
   `~/.claude/skills/model-selector.disabled` simulando ausencia.
2. Inicia `feature-00c` numa feature qualquer; pipeline chega em
   clarify.
3. Sequencia pre-spawn roda; `model-routing.sh invoke` detecta skill
   ausente (verificacao via `[ -x ~/.claude/skills/model-selector/scripts/classify.sh ]`).
4. Helper retorna JSON com `fallback: true`, `fallback_reason:
   "skill-not-found"`, exit 0.
5. Orquestrador registra Decisao com `escolha=fallback-default`,
   `score=0`, justificativa `"fallback: skill-not-found; stderr: ..."`.
6. Spawn do asker prossegue normalmente.

**Expected**:

- Pipeline conclui clarify com exit 0.
- ZERO bloqueios humanos abertos por causa da ausencia.
- `jq '.decisoes[] | select(.escolha == "fallback-default") | length'`
  >= 1.
- Subagente clarify-asker spawnou e produziu output normalmente.

## Scenario 3: Retomada — idempotencia preserva Decisao

1. Operador roda `feature-00c` ate decisao do asker ser registrada
   (cenario 1 ou 2).
2. Operador interrompe execucao via Ctrl+C antes do spawn-tracker
   increment.
3. Retomada via `/feature-00c-resume <short-name>` re-executa
   caminho pre-spawn.
4. `model-routing.sh idempotent-check` detecta Decisao ja existente,
   retorna exit 0 com `dec-NNN`.
5. Orquestrador pula `invoke` + `register` + `record-skill`; vai
   direto para `spawn-tracker increment` + tool Agent.

**Expected**:

- `jq '[.decisoes[] | select(.contexto | startswith("Selecao de modelo
  para subagente agente-00c-clarify-asker"))] | length'` retorna
  exatamente `1` (sem duplicacao).
- Pipeline continua de onde parou.

## Scenario 4: Input >4096 chars — truncagem reportada

1. Forcar template longo (override via `--input-text` com 5000 chars
   sinteticos): `helper invoke --subagent-type agente-00c-clarify-asker
   --etapa clarify --input-text "$(seq 1 1500 | tr '\n' ' ')"`.
2. Helper detecta `wc -c` > 4096; aplica truncagem 2000+marker+2000.
3. JSON retorna `input_truncado: true`, `input_bytes: 4016`.
4. Orquestrador registra Decisao com justificativa contendo nota
   `"... input truncado (2000+marker+2000); semantica de borda preservada"`.

**Expected**:

- `model-routing.sh invoke` retorna JSON com `input_truncado: true`.
- Skill model-selector e invocada com string de exatos 4016 bytes.
- Decisao registrada cita truncagem na justificativa (validavel
  com `jq '.decisoes[-1].justificativa | test("truncad")'` -> true).

## Scenario 5: Asker retorna `perguntas: []` — NAO registra Decisao do answerer

1. Pipeline executa fase clarify; spawn do asker acontece com Decisao
   `agente-00c-clarify-asker` registrada (cenario 1).
2. Asker conclui retornando `{"perguntas": []}` (sem ambiguidades
   detectadas).
3. Orquestrador interpreta `perguntas: []` -> NAO spawnar answerer
   -> avancar para plan.

**Expected**:

- `.decisoes` contem 1 Decisao do asker, ZERO do answerer
  (validavel com `jq '[.decisoes[] | select(.contexto | endswith
  "agente-00c-clarify-answerer"))] | length'` retorna `0`).
- Invariante "1 Decisao por spawn real" honrada (FR-015 + edge case
  da spec).

## Scenario 6: review-task agrega corretamente

1. Apos pipeline completar (>= 1 onda de clarify com asker+answerer),
   operador roda `/review-task` na feature.
2. review-task le state.json via jq query base da §Decision 8 do
   research.

**Expected**:

- Relatorio contem secao com agregacao por subagent_type:
  - `agente-00c-clarify-asker`: total=N, fallbacks=M, distribuicao={haiku: X, sonnet: Y, ...}
  - `agente-00c-clarify-answerer`: idem
- Percentual de fallback explicito (ex: `1/4 (25%)` quando 1 de 4
  spawns deu fallback — cenario 2 + 3 spawns OK).

## Scenario 7: Roundtrip End-to-End — N/A para esta feature

**Justificativa**: feature e single-layer (toolkit POSIX puro,
manipulando apenas JSON local). NAO atravessa fronteira
backend↔frontend. Roundtrip End-to-End como definido no template
de quickstart e dispensavel.

A equivalencia funcional para esta feature e a validacao do
**fluxo via cli/lib + tests/run.sh**: cada subcomando do helper
`model-routing.sh` tem teste correspondente em
`tests/test_model-routing.sh` que invoca o script real e valida o
JSON de saida + side-effects em fixture de state.json. Essa e a
"borda" real desta feature — codigo POSIX <-> persistencia JSON.
