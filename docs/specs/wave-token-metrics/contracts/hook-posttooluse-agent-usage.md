# Contract: hook `posttooluse-agent-usage.sh`

**Feature**: `wave-token-metrics` | **Status**: `[PROPOSTA — a validar na implementacao]`
**Arquivo alvo**: `global/skills/agente-00c-runtime/hooks/posttooluse-agent-usage.sh`

> Este contrato tem duas metades com estatutos diferentes:
> **§1 (entrada)** e um contrato **EXISTENTE do harness Claude Code**, extraido
> da doc oficial `https://code.claude.com/docs/en/hooks.md` (baixada e lida em
> 2026-07-25) e confirmado em transcripts reais — nao foi inventado.
> **§2 em diante** e o contrato **NOVO** desta feature.

---

## 1. Entrada — payload do harness (CONTRATO EXISTENTE, verificado)

O hook recebe um objeto JSON no **stdin**.

### 1.1 Campos comuns a todo hook event

| Campo | Tipo | Uso neste hook |
|-------|------|----------------|
| `session_id` | string | nao usado |
| `prompt_id` | string | nao usado |
| `transcript_path` | string | **nao usado ao vivo** — escrito assincronamente, pode ter lag no instante do hook (doc L617). Reservado ao backfill offline. |
| `cwd` | string | **usado** — raiz para deteccao de execucao ativa (mesmo uso de `posttooluse-tool-call-tick.sh:53`) |
| `permission_mode` | string | nao usado |
| `hook_event_name` | string | `"PostToolUse"` |

### 1.2 Campos especificos de `PostToolUse`

| Campo | Tipo | Uso |
|-------|------|-----|
| `tool_name` | string | **usado** — deve ser `"Agent"` (guarda defensiva mesmo com matcher) |
| `tool_use_id` | string | nao usado (o `agentId` e a chave do spawn) |
| `tool_input` | object | **usado** — so `subagent_type` |
| `tool_response` | object | **usado** — portador da telemetria |

### 1.3 `tool_input` da tool `Agent` (doc, secao `##### Agent`)

| Campo | Tipo | Consumido? |
|-------|------|-----------|
| `prompt` | string | **NAO** — texto livre, proibido no sidecar |
| `description` | string | NAO |
| `subagent_type` | string | SIM -> `agent_type` |
| `model` | string | NAO — usa-se `resolvedModel` do response (modelo efetivo) |

### 1.4 `tool_response` com `status = "completed"` (doc L1483-1495)

Citacao literal do doc (L1483):

> In `PostToolUse`, `tool_response` for a completed Agent call carries the
> subagent's final text along with usage telemetry. Read these fields to record
> per-subagent cost from a hook:

| Campo | Tipo | Consumido? | Destino |
|-------|------|-----------|---------|
| `status` | string | SIM | deriva `SpawnUsage.status` |
| `agentId` | string | SIM | `agent_id` |
| `content` | array | **NAO** — texto livre, proibido no sidecar | — |
| `resolvedModel` | string | SIM | `model` (requer harness >= 2.1.174) |
| `modelsUsed` | array | SIM | `models_used` (requer harness >= 2.1.212) |
| `totalTokens` | number | SIM | `total_tokens` |
| `totalDurationMs` | number | SIM | `duration_ms` |
| `totalToolUseCount` | number | SIM | `tool_use_count` |
| `usage.input_tokens` | number | SIM | `input_tokens` |
| `usage.output_tokens` | number | SIM | `output_tokens` |
| `usage.cache_creation_input_tokens` | number | SIM | `cache_creation_input_tokens` |
| `usage.cache_read_input_tokens` | number | SIM | `cache_read_input_tokens` |

### 1.5 `tool_response` com `status = "async_launched"` (doc L1497)

Citacao literal:

> For background subagents, the tool returns when the task moves to the
> background, so `tool_response` carries no usage fields (...) It has
> `status: "async_launched"`, `agentId`, `description`, `prompt`, `outputFile`,
> and `resolvedModel`.

Chaves observadas empiricamente num transcript real deste projeto:

```json
["agentId","canReadOutputFile","description","isAsync","outputFile","prompt","resolvedModel","status"]
```

**Consequencia contratual**: neste caso o hook grava `status = "indisponivel"`
com **todos** os campos numericos em `null`. NUNCA `0`.

> **Frequencia real, nao suposta**: contagem nos transcripts deste projeto =
> **52 `async_launched` vs 51 `completed`**. O caminho "indisponivel" e tao
> comum quanto o caminho feliz e MUST ser tratado como fluxo normal.

---

## 2. Saida — linha do sidecar `[PROPOSTA]`

**Destino**: `<state-dir>/wave-agent-usage.jsonl`, append-only.

Uma linha JSON compacta (`jq -c`) por spawn:

```json
{"agent_id":"a1b598e5d8f9a0318","agent_type":"agente-00c-feature-orchestrator","status":"completo","model":"claude-sonnet-5","models_used":null,"total_tokens":131692,"input_tokens":2,"output_tokens":1097,"cache_read_input_tokens":130176,"cache_creation_input_tokens":417,"tool_use_count":45,"duration_ms":681768,"source":"live","observed_at":"2026-07-25T21:04:49Z"}
```

> Os valores acima nao sao ilustrativos inventados: `agent_id`, `agent_type`
> (do `subagent_type` do `tool_use` correlato), `model`, `total_tokens`,
> `tool_use_count`, `duration_ms` e os 4 campos de breakdown derivam de um
> `toolUseResult` real observado no transcript
> `01d83125-e6c0-4c7d-859a-a1b94d6de09e.jsonl` desta sessao. Apenas `status`,
> `source` e `observed_at` sao campos DERIVADOS pelo desenho novo (nao existem
> na fonte).

Exemplo do caso indisponivel (tambem de registro real do mesmo diretorio de
transcripts — spawn background, `status = "async_launched"`):

```json
{"agent_id":"a35a086e9e6589c0b","agent_type":"general-purpose","status":"indisponivel","model":"claude-opus-4-8[1m]","models_used":null,"total_tokens":null,"input_tokens":null,"output_tokens":null,"cache_read_input_tokens":null,"cache_creation_input_tokens":null,"tool_use_count":null,"duration_ms":null,"source":"live","observed_at":"2026-07-25T21:05:10Z"}
```

**Restricoes duras da linha**:

1. **MUST NOT** conter `content`, `prompt` ou `description` — texto livre e
   proibido (tamanho + vazamento de segredo).
2. **MUST** caber em uma linha curta (< PIPE_BUF) para preservar a atomicidade
   do append O_APPEND — a mesma premissa documentada em
   `posttooluse-tool-call-tick.sh:39-41`.
3. **MUST NOT** conter `null` disfarcado de `0` em nenhum campo numerico.

---

## 3. Politica de falha: fail-OPEN absoluto

Identica a de `posttooluse-tool-call-tick.sh` (cabecalho L21-27) e **oposta** a
do `pretooluse-bash-guard.sh` (que e fail-closed por ser guarda, nao metrica).

| Condicao | Comportamento |
|----------|---------------|
| `jq` ausente | `exit 0` silencioso |
| stdin vazio/invalido | `exit 0` silencioso |
| `cwd` vazio | `exit 0` silencioso |
| `tool_name != "Agent"` | `exit 0` silencioso |
| nenhuma execucao 00c ativa | `exit 0` silencioso, zero interferencia |
| append negado (permissao/disco) | `exit 0` silencioso |
| `tool_response` malformado | grava `status = "indisponivel"`, ou `exit 0` se nem `agentId` houver |

**MUST NOT** usar `set -e` (mesma justificativa do hook irmao: um erro nao
tratado viraria exit != 0 e o harness exporia stderr ao operador).
**MUST NOT** escrever em stdout. **MUST NOT** bloquear, atrasar ou reprovar a
tool call — este hook e metrica, nunca guarda.

---

## 4. Deteccao de execucao ativa (REUSO, nao reimplementacao)

Algoritmo **identico** ao de `posttooluse-tool-call-tick.sh:68-100`, que por sua
vez espelha `pretooluse-bash-guard.sh`:

1. `<cwd>/.claude/agente-00c-state/state.json` com
   `.execution.status ∈ {em_andamento, aguardando_humano}` -> vence.
2. Senao, varrer `<cwd>/.claude/feature-00c-state/*/state.json` com o mesmo
   filtro de status; desempate pelo **menor short-name em ordem lexicografica
   byte-wise** (`LC_ALL=C sort`).
3. Nenhuma ativa -> `exit 0`.

**MUST NOT** divergir desse algoritmo: divergencia entre os dois hooks faria a
metrica de uso e a de tool calls apontarem para state dirs diferentes na mesma
sessao.

---

## 5. Provisionamento

`cli/lib/hooks.sh::apply_guard_hooks()` (L193) `[EXISTE]` ganha um terceiro `cp`
best-effort, simetrico ao de `posttooluse-tool-call-tick.sh` (L256-263): falha
de copia emite `log_warn` e **nao** altera o state word retornado
(`merged | paste-instructed | hooks-only | not-applicable | error`).

`global/skills/agente-00c-runtime/hooks/settings.snippet.json` `[EXISTE]` ganha
uma terceira entrada `[PROPOSTA]`:

```json
{
  "matcher": "Agent",
  "hooks": [
    {
      "type": "command",
      "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/posttooluse-agent-usage.sh",
      "timeout": 5
    }
  ]
}
```

Escopo `project` apenas — nunca `global`, mesma regra ja aplicada aos hooks
existentes.

---

## 6. Testes

`tests/test_posttooluse-agent-usage.sh` `[PROPOSTA]`.

**Atencao a convencao** (verificado em `tests/run.sh`): hooks vivem em
`.../hooks/`, fora do `_find_scripts()`, logo um teste novo seria marcado como
*teste orfao* por `--check-coverage`. E necessario adicionar isencao
existence-guarded em `_is_internal_test`, replicando o precedente literal de
`tests/run.sh:298-303`.

Cenarios minimos:

| # | Cenario | Assercao |
|---|---------|----------|
| 1 | `status=completed` completo | linha com todos os campos; `status=completo` |
| 2 | `status=async_launched` | `status=indisponivel`; todos numericos `null` |
| 3 | `completed` sem `usage` | `status=parcial`; observados preenchidos, resto `null` |
| 4 | `resolvedModel` ausente | `model == "nao-aplicavel"` |
| 5 | `jq` ausente | exit 0, sidecar nao criado |
| 6 | sem execucao ativa | exit 0, sidecar nao criado |
| 7 | `tool_name != Agent` | exit 0, sidecar nao criado |
| 8 | 2 features ativas | escreve no menor short-name lexicografico |
| 9 | stdin malformado | exit 0, sem crash |
| 10 | append repetido | 2 spawns => 2 linhas, ordem preservada |
| 11 | anti-vazamento | `content`/`prompt` presentes na entrada nunca aparecem na linha |
