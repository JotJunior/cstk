# Contract: `statusline-plan-usage.sh` `[PROPOSTA — a validar na implementacao]`

Ponto de entrada de captura, configurado via `statusLine.command` no
`settings.json` do harness (research.md Decision 1). Nao existe hoje —
`grep -rn statusLine` no repo inteiro nao retorna nenhuma ocorrencia
anterior a esta feature.

## Invocacao

O harness Claude Code invoca o comando configurado em
`statusLine.command`, alimentando o JSON completo do estado da sessao no
**stdin** do processo, e espera o texto a ser renderizado na UI no
**stdout** (memoria `reference_statusline_usage_payload.md`, schema
completo).

```
<statusLine.command> < payload.json > texto_renderizado
```

## Contrato de entrada (payload — schema OBSERVADO, nao inferido)

Ver memoria `reference_statusline_usage_payload.md` para o schema completo
verificado empiricamente (Claude Code 2.1.226, macOS, 2026-08-10). Campos
consumidos por esta feature:

| Campo | Presenca | Uso |
|-------|----------|-----|
| `.session_id` | sempre | `plan_usage.session_id` |
| `.workspace.current_dir` / `.workspace.project_dir` | sempre | `plan_usage.project_path` (basename -> `project`) |
| `.rate_limits.five_hour.used_percentage` | so apos 1a resposta de API completar na sessao | `plan_usage.used_percentage` (scope=`five_hour`) |
| `.rate_limits.five_hour.resets_at` | idem | `plan_usage.resets_at` (scope=`five_hour`) |
| `.rate_limits.seven_day.*` | idem | mesma logica, scope=`seven_day` |

Campos NAO consumidos por esta feature (fora de escopo, FR-006):
`.model`, `.cost`, `.context_window`, `.exceeds_200k_tokens`,
`.thinking`, `.effort`, `.output_style`, `.version`.

## Contrato de saida (obrigatorio — research.md Decision 2)

O script MUST imprimir em stdout o texto que a UI deve renderizar,
independente de a captura ter sucesso ou falha:

1. Se `CSTK_STATUSLINE_INNER_COMMAND` estiver definida: reencaminhar o
   payload original (stdin, sem modificacao) para o comando dela e
   repassar o stdout verbatim.
2. Senao: imprimir fallback minimo de 1 linha, construido so a partir de
   `model.display_name` e (quando presente nesta mesma captura)
   `rate_limits.five_hour.used_percentage`.

**Nunca** imprimir erro de diagnostico da captura (jq ausente, sqlite3
ausente, `knowledge.db` sem permissao de escrita) em stdout — isso
contaminaria a UI. Erros de captura, se logados, vao para stderr
(consistente com Constitution II) ou sao descartados silenciosamente
(fail-open, mesma disciplina de `posttooluse-loose-usage.sh`).

## Comportamento de captura (best-effort, nunca bloqueante)

| Situacao | Comportamento |
|----------|----------------|
| `.rate_limits` ausente no payload | Pass-through normal; NENHUM INSERT (nao e "captura com NULL" — e "sessao sem nenhuma resposta de API", Edge Case da spec); throttle nao se aplica porque nao ha valor novo a comparar |
| `.rate_limits` presente, `used_percentage` identico ao ultimo registro do escopo ate 2 casas decimais E `resets_at` igual | Pass-through normal; captura descartada pelo throttle (FR-010), nenhum INSERT |
| `.rate_limits` presente, valor mudou alem de 2 casas decimais OU `resets_at` mudou | Pass-through normal + INSERT em `plan_usage` (via `cstk plan-usage ingest --stdin`) |
| `jq` ausente | Pass-through normal; captura pulada (Decision 3 do research.md) |
| `sqlite3`/`knowledge.db` indisponivel | Pass-through normal; captura pulada |
| Payload malformado (JSON invalido) | Pass-through normal (best-effort — tenta repassar stdin cru); captura pulada |

Em NENHUM cenario o script sai com codigo diferente de `0`, nem atrasa a
renderizacao da UI de forma perceptivel — nenhuma chamada de rede,
throttle O(1) no caminho de leitura (`SELECT ... ORDER BY id DESC LIMIT 1`
por escopo, mesmo custo de `recall_apply_sql_with_retry`).

**Threshold verificavel (CHK022, politica de design — nao medicao
empirica)**: a captura completa (parse do payload + throttle + INSERT,
quando aplicavel) MUST adicionar no maximo **50ms** de latencia por
render em relacao ao pass-through puro (sem captura). Este e um orcamento
de design, na mesma ordem de grandeza do teto de 5s de timeout de hook do
harness (`docs/specs/_archived/2026-08-08-loose-usage-capture/contracts/hook-loose-usage.md`,
linha 22) dividido por um fator
de folga generoso para uma operacao sincrona e visivel ao operador a cada
render — nao uma medicao ja realizada nesta feature. FASE 5 (task 5.1)
MUST validar esse orcamento empiricamente com `time` sobre o script com
fixtures reais antes de declarar o requisito atendido; se a medicao real
exceder 50ms de forma consistente, o numero MUST ser revisto via Decisao
auditavel (nao silenciosamente ignorado).

## Teste (FR-012 — sem sessao interativa real)

```sh
printf '%s' "$FIXTURE_PAYLOAD" | statusline-plan-usage.sh
```

`$FIXTURE_PAYLOAD` e um JSON fixture estatico (variantes: com
`rate_limits`, sem `rate_limits`, com `rate_limits` repetido dentro da
tolerancia de throttle) — nunca uma sessao `claude` real (GOTCHA: a
statusline nao dispara em `claude -p`).
