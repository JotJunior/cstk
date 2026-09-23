# Quickstart: Resumo Deterministico de Fechamento de Onda

Cenarios de validacao. Os de 1 a 8 sao automatizaveis em `tests/test_wave-summary.sh`
com fixtures de estado sinteticas (backend JSON; os marcados (S) repetem sob
backend SQLite quando `sqlite3` adequado estiver disponivel). O 9 e o 10 exercitam
os commands reais.

## Scenario 1: Onda normal (US1 AS1)

1. Fixture com `onda-002` fechada: `termination_reason=etapa_concluida_avancando`,
   3 decisoes com `wave_id=onda-002`, 1 decisao de `onda-001`, `otel_usage`
   preenchido, `tool_calls=18`.
2. `wave-summary.sh emit --state-dir <fx>`
3. **Expected**: exit 0, stderr vazio; bloco cita `onda-002`, rotulo "etapa
   concluida, avancando", `Decisoes registradas na onda: 3`, proxima instrucao.
   (S)

## Scenario 2: Limite operacional vs bloqueio humano (US1 AS2/AS3, edge case)

1. Fixture A: `termination_reason=threshold_proxy_atingido`, 0 bloqueios.
2. Fixture B: `termination_reason=bloqueio_humano`, 1 bloqueio `aguardando`
   (`block-001`) + 1 `respondido`.
3. **Expected**: A traz "pausa por limite operacional", sem sufixo ATENCAO; B
   traz "bloqueio humano pendente" + ATENCAO + `Bloqueios pendentes: 1 (block-001)`.

## Scenario 3: Nao medido vs zero medido (US2, FR-010, SC-002)

1. Fixture C: `otel_usage` ausente. Fixture D: `otel_usage.total_tokens=0`,
   `total_cost_usd=0`.
2. **Expected**: C → `Consumo (OTel): nao medido` e, em `--json`,
   `cost.total_tokens=null`, `cost.measured=false`; D → `0 tokens` e
   `measured=true`. Nenhuma saida de C contem `0 tokens`.

## Scenario 4: tool_calls = 0 com e sem contador ativo (Decision 3)

1. Fixture com `tool_calls=0`, `.execution.target_project_path` apontando para
   dir sem hook de tick (tick-mode `manual`) → **Expected**: `nao medido`.
2. Mesmo estado com hook de tick provisionado no dir-alvo (tick-mode `hook`) →
   **Expected**: `Chamadas de ferramenta: 0`.

## Scenario 5: Nenhum texto livre vaza (FR-012, I-2)

1. Fixture com decisao cujo `context` contem o canario `CANARY-DEC-CTX` e um
   segredo sintetico em formato de token; bloqueio com `question` contendo
   `CANARY-BLK-Q`; `next_instruction` com o mesmo segredo sintetico + `\033[31m`.
2. Rodar em Markdown e `--json`.
3. **Expected**: nenhum canario nem o segredo sintetico aparece; `next_instruction`
   sai sem ESC e com o segredo substituido pelo marcador do `secrets-filter.sh`.

## Scenario 6: Primeira onda, zero decisoes, tarefas (edge cases, FR-008)

1. Fixture com uma unica onda, sem decisoes, `executed_stages=["execute-task"]`,
   2 tasks `pass` + 1 `fail` com `wave_id` da onda e 1 task de outra onda.
2. **Expected**: `Decisoes registradas na onda: 0` sem erro; `Tarefas: 2
   concluidas, 1 falharam`. Em fixture sem execute-task nem tasks: `Tarefas: nao
   aplicavel`.

## Scenario 7: Falhas sao best-effort (US3, FR-011)

1. `--state-dir` inexistente → **Expected**: exit 1, stdout vazio, stderr = 1 linha.
2. Estado JSON corrompido → idem exit 1.
3. `.waves` vazio / `--wave onda-999` → exit 3, 1 linha em stderr.
4. `jq` fora do PATH (shim de PATH com allowlist de utilitarios, sem `jq`) →
   exit 1, 1 linha.

## Scenario 8: Determinismo, read-only, paridade de modos (I-3, I-4, FR-014)

1. Duas execucoes consecutivas → stdout byte-identico.
2. Hash do estado antes/depois identico; nenhum arquivo novo no state-dir.
3. Mesmo documento de estado sob layout `.claude/agente-00c-state/` e sob
   `.claude/feature-00c-state/<short>/` → saidas identicas.

## Scenario 9: Integracao nos 4 commands pai (FR-001, FR-013)

1. Teste estatico (interno) sobre `plugins/cstk/commands/{feature-00c,
   feature-00c-resume,agente-00c,agente-00c-resume}.md`.
2. **Expected**: cada um invoca `wave-summary.sh emit` DEPOIS do `reconcile-wave`
   e ANTES do `ScheduleWakeup` na ordem do texto, com fallback
   `Resumo da onda indisponivel` e sem condicionar o schedule ao exit.

## Scenario 10: Roundtrip real (validacao manual, pos-release)

N/A como roundtrip backend↔frontend (feature single-layer). Substituto: rodar
`wave-summary.sh emit --state-dir <state-dir real de uma execucao feature-00c>`
contra o `state.db` real e conferir cada linha contra `state-rw.sh read | jq`.
**Expected**: zero divergencia campo-a-campo.
