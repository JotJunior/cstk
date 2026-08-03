# Contract: interface de I/O dos tres hooks 00C

**Feature**: `hooks-db-parity`
**Arquivos**: `global/skills/agente-00c-runtime/hooks/{pretooluse-bash-guard,posttooluse-tool-call-tick,posttooluse-agent-usage}.sh`

> Todos os contratos deste documento sao `[EXISTENTE]` — extraidos por
> leitura direta do codigo-fonte dos tres hooks e do
> `settings.snippet.json`. Esta feature **nao altera** nenhuma assinatura
> abaixo; altera apenas *quando* o estado "execucao ativa" e alcancado.
> As linhas marcadas **[MUDA]** indicam o unico ponto de comportamento
> afetado.

---

## Event: `PreToolUse` / matcher `Bash` [EXISTENTE]

Hook: `pretooluse-bash-guard.sh`. Registrado com `"timeout": 5` (segundos)
em `settings.snippet.json`.

### stdin (JSON do harness)

| Campo | Tipo | Uso |
|-------|------|-----|
| `cwd` | string | raiz do projeto; ausente/vazio => `MECANISMO_FALHOU` |
| `tool_name` | string | defesa redundante do matcher; `!= "Bash"` => `exit 0` |
| `tool_input.command` | string | comando submetido a `bash-guard.sh check` |

### Exit code

**Sempre `0`.** O harness so interpreta bloqueio via o JSON de
`hookSpecificOutput`, nunca via exit code — decisao original da feature
`enforced-guards`.

### stdout

Caso permitido / fora de escopo: **vazio**.

Caso bloqueado:

```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"<PREFIXO>: <motivo>"}}
```

`<PREFIXO>` pertence a um conjunto fechado de dois valores:

| Prefixo | Significado |
|---------|-------------|
| `REGRA_VIOLADA` | `bash-guard.sh check` retornou exit `1` (regra de fato violada) |
| `MECANISMO_FALHOU` | o hook nao conseguiu decidir com seguranca |

`<motivo>` **MUST** passar por `secrets-filter.sh scrub` antes de compor a
mensagem no caminho `REGRA_VIOLADA` (o texto cru do `bash-guard.sh` pode
embutir o comando original).

### Condicoes de `MECANISMO_FALHOU` [MUDA]

| # | Condicao | Status |
|---|----------|--------|
| 1 | `jq` ausente | existente |
| 2 | stdin vazio | existente |
| 3 | stdin com JSON malformado | existente |
| 4 | campo `cwd` ausente | existente |
| 5 | `bash-guard.sh` irresolvivel ou nao executavel | existente |
| 6 | `mktemp` indisponivel | existente |
| 7 | `bash-guard.sh` retornou exit fora de `{0,1}` | existente |
| 8 | **`state.db` presente e status indeterminavel** (`sqlite3` ausente, DB corrompido, erro de leitura) | **novo — FR-003** |
| 9 | **`state.db` presente e helper de deteccao irresolvivel** | **novo — FR-003** |

Contrapartida (FR-007): ausencia total de state (`state.json` **e**
`state.db` ausentes) permanece **fora de escopo** — `exit 0`, stdout vazio,
nenhuma linha de log. Nao e falha de mecanismo.

### Efeito colateral

Append de 1 linha em `<cwd>/.claude/enforcement-log.jsonl`, **apenas**
quando ha execucao ativa detectada. Schema em `data-model.md`
§EnforcementDecisionLog. Falha de escrita nunca aborta o hook (aviso em
stderr, `exit 0`).

**[MUDA]**: sob backend SQLite, o campo `detected_execution_path` passa a
poder apontar para um `state.db`.

---

## Event: `PostToolUse` / matcher `*` [EXISTENTE]

Hook: `posttooluse-tool-call-tick.sh`. `"timeout": 5`.

### stdin

| Campo | Tipo | Uso |
|-------|------|-----|
| `cwd` | string | raiz do projeto; vazio => no-op |
| `tool_name` | string | vazio => no-op (payload anomalo, nao inventa tick) |

### Exit code

**Sempre `0`.** Fail-open absoluto.

### stdout / stderr

**Ambos sempre vazios.** Requisito duro: este hook dispara a cada tool call
e qualquer saida polui a sessao do operador.

### Efeito colateral

Append de 1 linha (timestamp ISO 8601 UTC) em
`<state-dir>/tool-call-ticks.log`, apenas quando ha execucao ativa.

### Modos de no-op (fail-open) [MUDA]

| # | Condicao | Status |
|---|----------|--------|
| 1 | `jq` ausente | existente |
| 2 | stdin vazio ou malformado | existente |
| 3 | `cwd` ou `tool_name` vazios | existente |
| 4 | nenhuma execucao ativa | existente |
| 5 | append negado (permissao/disco) | existente |
| 6 | **`state.db` presente e status indeterminavel** | **novo — FR-004** |
| 7 | **helper de deteccao irresolvivel** | **novo — FR-004** |

Em nenhum desses casos ha stdout, stderr ou exit != 0.

---

## Event: `PostToolUse` / matcher `Agent` [EXISTENTE]

Hook: `posttooluse-agent-usage.sh`. `"timeout": 5`.

### stdin

| Campo | Tipo | Uso |
|-------|------|-----|
| `cwd` | string | raiz do projeto |
| `tool_name` | string | guarda defensiva: `!= "Agent"` => no-op |
| `tool_input.subagent_type` | string | `agent_type` da linha de uso |
| `tool_response.agentId` | string | chave minima; ausente => nenhuma linha |
| `tool_response.status` | string | `"completed"` + `totalTokens` => `completo`; `"completed"` sem tokens => `parcial`; senao `indisponivel` |
| `tool_response.totalTokens` | number | |
| `tool_response.usage.{input_tokens,output_tokens,cache_read_input_tokens,cache_creation_input_tokens}` | number | |
| `tool_response.totalToolUseCount` | number | |
| `tool_response.totalDurationMs` | number | |
| `tool_response.resolvedModel` | string | default `"nao-aplicavel"` |
| `tool_response.modelsUsed` | array | |

### Exit code

**Sempre `0`.** Fail-open absoluto.

### stdout / stderr

- **stdout**: sempre vazio.
- **stderr**: vazio, com **uma unica excecao pre-existente** — aviso de teto
  de 500 linhas por onda, emitido no maximo uma vez por onda (guardado pelo
  sentinela `.wave-agent-usage-cap-warned`).

### Efeito colateral

Append de 1 objeto JSON (SpawnUsage) em
`<state-dir>/wave-agent-usage.jsonl`, criado sob `umask 077` + `chmod 600`
best-effort.

Campos da linha: `agent_id`, `agent_type`, `status`, `model`, `models_used`,
`total_tokens`, `input_tokens`, `output_tokens`, `cache_read_input_tokens`,
`cache_creation_input_tokens`, `tool_use_count`, `duration_ms`, `source`,
`observed_at`. Quando `status = indisponivel`, todos os campos numericos
**MUST** ser `null` (nunca `0`).

**Nunca** inclui `content`, `prompt` ou `description` (texto livre).

### Modos de no-op (fail-open) [MUDA]

Mesma tabela do hook de ticks, mais: `tool_response.agentId` ausente.

---

## Invariantes comuns aos tres hooks

| # | Invariante | Requisito |
|---|------------|-----------|
| I1 | Fora de execucao ativa: zero interferencia — sem stdout, sem escrita, sem bloqueio | FR-006, SC-004 |
| I2 | Deteccao de execucao ativa identica nos tres (mesmo helper, mesma precedencia) | FR-001, FR-002 |
| I3 | `jq` e dep opcional; ausencia => `MECANISMO_FALHOU` no guard, no-op nas metricas | Constitution II (1.1.0) |
| I4 | `sqlite3` e dep opcional; ausencia com `state.db` presente => `MECANISMO_FALHOU` no guard, no-op nas metricas | Constitution II (1.1.0), FR-003, FR-004 |
| I5 | Nenhum hook escreve **dentro** do documento de estado (`state.json`/`state.db`) — apenas sidecars ao lado | pre-existente |
| I6 | Exit code do processo e sempre `0` nos tres hooks | pre-existente |
