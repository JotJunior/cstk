# Quickstart: Plan Usage Capture

Cenarios de validacao — happy path + error cases. Todos alimentam payload
fixture via stdin (FR-012); nenhum depende de sessao interativa real do
Claude Code.

## Cenario 1 — Captura basica (User Story 1 / SC-001)

1. Alimentar `statusline-plan-usage.sh` com um payload fixture que contem
   `rate_limits.five_hour` e `rate_limits.seven_day`.
2. **Expected**: stdout contem o pass-through/fallback (nunca vazio);
   `plan_usage` ganha 2 linhas novas (uma por escopo), com
   `used_percentage`/`resets_at` iguais aos valores do fixture.
3. Rodar `cstk plan-usage`.
4. **Expected**: saida mostra os 2 escopos com os valores capturados, sem
   qualquer credencial OAuth envolvida.

## Cenario 2 — Ausencia de `rate_limits` nunca vira zero (User Story 3 / SC-002)

1. Alimentar `statusline-plan-usage.sh` com um payload fixture SEM a
   chave `rate_limits` (sessao aberta e fechada sem resposta de API).
2. **Expected**: nenhuma linha nova em `plan_usage`; pass-through de
   stdout normal.
3. Rodar `cstk plan-usage` num banco onde NUNCA houve captura.
4. **Expected**: saida mostra `nao medido` para os 2 escopos — nunca `0%`.

## Cenario 3 — Throttle descarta repeticao (FR-010)

1. Alimentar `statusline-plan-usage.sh` duas vezes em sequencia com o
   MESMO `used_percentage` (ate a 2a casa decimal) e o mesmo `resets_at`
   para `five_hour`.
2. **Expected**: apenas 1 linha nova em `plan_usage` para `five_hour` (a
   segunda captura e descartada pelo throttle).
3. Alimentar uma 3a vez com `used_percentage` mudando na 3a casa decimal
   apenas (ex.: `7.001` -> `7.009`, ambos arredondam para `7.00`).
4. **Expected**: ainda descartada (dentro da tolerancia de 2 casas).
5. Alimentar uma 4a vez com `used_percentage` mudando na 2a casa decimal
   (ex.: `7.00` -> `7.05`).
6. **Expected**: nova linha inserida (mudanca real).

## Cenario 4 — Evolucao ao longo do tempo (User Story 2 / SC-003)

1. Alimentar `statusline-plan-usage.sh` 3 vezes para `five_hour` com
   `used_percentage` crescente (`5.0`, `12.0`, `20.0`) e mudanca real a
   cada vez.
2. Rodar `cstk plan-usage history --scope five_hour`.
3. **Expected**: 3 linhas em ordem cronologica, sem precisar cruzar dados
   de fontes separadas.

## Cenario 5 — Formato de `resets_at` (SC-004)

1. Alimentar `statusline-plan-usage.sh` com `resets_at: 1786372200`
   (epoch segundos, exatamente como o payload real observado).
2. **Expected**: `plan_usage.resets_at` persistido como `1786372200`
   (INTEGER), interpretavel diretamente como epoch — sem tentativa de
   parse como string ISO.

## Cenario 6 — Zero coleta remota (SC-005 / Principio IV)

1. Rodar toda a suite de testes desta feature com rede desabilitada
   (ou instrumentada para falhar qualquer `curl`/`wget`).
2. **Expected**: nenhum teste falha por dependencia de rede — a fonte e
   exclusivamente o stdin do processo local, nunca uma chamada HTTP.

## Cenario 7 — `jq`/`sqlite3` ausentes (Principio II carve-out)

1. Simular ausencia de `jq` no PATH e alimentar
   `statusline-plan-usage.sh` com um payload valido.
2. **Expected**: pass-through de stdout ocorre normalmente; nenhuma
   captura nova em `plan_usage`; exit `0`.
3. Repetir simulando ausencia de `sqlite3`.
4. **Expected**: mesmo comportamento — pass-through intacto, captura
   pulada, exit `0`.
