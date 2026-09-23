# Data Model: Resumo Deterministico de Fechamento de Onda

A feature NAO cria nem altera persistencia: o `WaveSummary` e uma projecao
efemera, computada sob demanda a partir do documento de estado existente e
impressa em stdout. Nenhum campo novo e gravado em `state.json`/`state.db`.

## Entity: WaveSummary [PROPOSTA — projecao, nao persistida]

Chaves do modo `--json` (sintaxe em ingles — regra global). Fonte de cada campo
[EXISTENTE] conforme `research.md` Decision 1.

| Field | Type | Constraints | Fonte / Notas |
|-------|------|-------------|---------------|
| `wave_id` | string | NOT NULL, `^onda-[0-9]{3,}$` | `.waves[alvo].id` |
| `wave_closed` | bool | NOT NULL | `termination_reason != null` |
| `termination_reason` | enum \| null | `etapa_concluida_avancando`, `threshold_proxy_atingido`, `bloqueio_humano`, `aborto`, `concluido`; `null` se aberta | `.waves[alvo].termination_reason` |
| `attention_required` | bool | NOT NULL | `true` se `pending_blocks.count > 0` OU `termination_reason = bloqueio_humano` |
| `executed_stages` | string[] | pode ser vazio | `.waves[alvo].executed_stages` |
| `current_stage` | string \| null | | `.current_stage` (ponteiro APOS o fechamento) |
| `execution_status` | string \| null | | `.execution.status` |
| `next_instruction` | string \| null | <= 200 chars, sem controle, scrubbed | `.next_instruction` saneada (Decision 5) |
| `decisions_count` | int | >= 0 (sempre medido) | `count(.decisions[] where wave_id == alvo)` |
| `pending_blocks.count` | int | >= 0 | `count(.human_blocks[] where status == "aguardando")` — escopo EXECUCAO, nao onda |
| `pending_blocks.ids` | string[] | so `id` (`block-NNN`) | nunca `question`/`context_for_answer` |
| `tool_calls.value` | int \| null | `null` quando nao medido | `.waves[alvo].tool_calls` + regra Decision 3 |
| `tool_calls.measured` | bool | | |
| `wallclock_seconds.value` | int \| null | | `.waves[alvo].wallclock_seconds` |
| `wallclock_seconds.measured` | bool | | |
| `cost.total_tokens` | int \| null | | `.waves[alvo].otel_usage.total_tokens` |
| `cost.total_cost_usd` | number \| null | | `.waves[alvo].otel_usage.total_cost_usd` |
| `cost.measured` | bool | `false` se `otel_usage` ausente/null | |
| `tasks.applicable` | bool | | `execute-task ∈ executed_stages` OU ha task com `wave_id == alvo` |
| `tasks.passed` | int \| null | `null` se nao aplicavel | `count(.tasks[] where wave_id==alvo and outcome=="pass")` |
| `tasks.failed` | int \| null | idem | `outcome=="fail"` |

### Relationships

- `WaveSummary` 1:1 `Wave` (`.waves[]`) — a onda-alvo.
- `Wave` 1:N `Decision` via `.decisions[].wave_id` (so contagem).
- `Wave` 1:N `Task` via `.tasks[].wave_id` (so contagens pass/fail).
- `HumanBlock` e agregado no escopo da execucao (pendencia e da execucao, nao
  da onda) — so `count` + `id`s.

### Invariantes

- **I-1 (FR-010)**: todo campo numerico `null` ⇔ `measured=false`; nenhum `0`
  e emitido para metrica nao medida.
- **I-2 (FR-012)**: nenhum valor de `context`/`rationale`/`evidence`/
  `options_considered`/`choice` (decisao) nem `question`/`context_for_answer`/
  `human_answer` (bloqueio) aparece na saida, em nenhum dos dois formatos.
- **I-3 (determinismo)**: mesma entrada ⇒ saida byte-identica; o helper nao
  le relogio nem ambiente alem do estado e do `tick-mode`.
- **I-4 (read-only)**: o hash do estado e identico antes e depois da execucao.

### State Transitions

N/A — projecao sem ciclo de vida. O helper observa o estado da onda
(`aberta → fechada`), nunca o altera.
