# Contract: Layer B instrumentation (orchestrators write new state.json fields)

**Feature**: `knowledge-db-metrics` | **Components**:
`global/agents/agente-00c-orchestrator.md`,
`global/agents/agente-00c-feature-orchestrator.md`

Contrato da camada B (US3, **alto risco**): os campos NOVOS que os orquestradores
passam a gravar no `state.json` para que a ingestao (camada A ja entregue) possa
derivar as entidades `tasks` e `events`. **So inicia apos a camada A estar verde**
(FR-010 / SC-008).

## 1. Pre-condicao (FR-018, FR-010)

A camada A (executions, waves, alert_signals) DEVE estar concluida e validada por
teste automatizado (SC-008) antes de qualquer edicao nos agent files. A camada B
e puramente aditiva ao `state.json`: nenhum campo existente muda de semantica.

## 2. Campo novo: `.tasks[]` (FR-018, FR-019)

Gravado durante execute-task/review-task. Uma entrada por task por execucao.

```json
{
  "tasks": [
    {
      "task_id": "T001",
      "wave_id": "onda-003",
      "outcome": "pass",
      "testes_rodados": 12,
      "testes_passados": 12,
      "lint_ok": true,
      "arquivos_tocados": ["cli/lib/recall.sh", "tests/cstk/test_recall.sh"]
    }
  ]
}
```

| Campo | Tipo | Obrigatorio | Notas |
|-------|------|-------------|-------|
| task_id | string | sim | identificador da task |
| wave_id | string | sim | onda em que a task rodou (proveniencia) |
| outcome | enum `pass`\|`fail` | sim | |
| testes_rodados | int | sim | 0 se nao aplicavel |
| testes_passados | int | sim | <= testes_rodados |
| lint_ok | bool | sim | |
| arquivos_tocados | string[] | sim | contagem derivada na ingestao |

**Chave natural** (clarify Q2 / dec-006): `(project, feature, execucao_id, task_id)`.

## 3. Campo novo: `.eventos[]` (FR-020)

Timeline cronologica. Conjunto MVP fechado (clarify Q3 / dec-007), extensivel sem
mudanca de schema.

```json
{
  "eventos": [
    { "event_type": "lock_contention", "timestamp": "2026-05-24T02:31:00Z", "descricao": "lock ocupado, retry" },
    { "event_type": "wave_retry", "timestamp": "2026-05-24T02:35:10Z" },
    { "event_type": "validation_failed", "timestamp": "2026-05-24T02:40:00Z" },
    { "event_type": "schedule_wait", "timestamp": "2026-05-24T02:42:00Z" }
  ]
}
```

| event_type (MVP) | Quando gravar |
|------------------|---------------|
| `wave_retry` | falha de onda seguida de retry |
| `lock_contention` | tentativa de adquirir lock ocupado |
| `validation_failed` | `state-validate.sh` ou hash-verify reprovou |
| `schedule_wait` | onda encerrada aguardando proximo wakeup |

Cada evento: `event_type` (do conjunto), `timestamp` (ISO), `descricao` (texto
livre opcional → scrubbed na ingestao).

## 4. Contrato de retro-compatibilidade (FR-022, SC-009)

`state.json` SEM `.tasks`/`.eventos` (execucao antiga, pre-instrumentacao) → a
ingestao da camada B produz 0 linhas de Task/Evento para aquela execucao, 0 erro.
Implementacao: `jq '.tasks[]? // empty'` / `jq '.eventos[]? // empty'`.

**Garantia (SC-009)**: 0 registros + 0 erros para state nao-instrumentado.

## 5. Contrato de proveniencia da escrita

Os campos sao gravados pelos helpers de runtime existentes (mesma disciplina dos
demais writes: `state-rw.sh` para mutacao, hash recomputado via `sha256-update`,
backup filtrado via `secrets-filter.sh for-backup`). Camada B NAO introduz novo
caminho de escrita fora do runtime ja auditado.

## 6. Custo em tokens (FR-021, SC-010)

DECISAO REGISTRADA (clarify Q1 / dec-005, score 3 empirico): a harness do Claude
Code NAO expoe contabilidade de tokens a scripts/env. Portanto:
- O sistema NAO grava nem ingere custo em tokens/$.
- `tool_calls` (`.metricas_acumuladas.tool_calls_total`, `.ondas[].tool_calls`)
  permanece como **proxy de custo documentado**.
- Em NENHUM caso ha valor de custo inventado.

Se uma versao futura da harness expuser tokens, o campo SHOULD ser adicionado a
`.metricas_acumuladas` e ingerido — fora do escopo desta feature.
