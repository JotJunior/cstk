# Contracts: tool MCP `record_decision` (structural-decision-human-gate)

Delta do contrato da tool MCP de registro de Decisao. Rotulos: `[EXISTENTE]` =
campo/erro real hoje, verificado em
`mcp/state-server/src/tools/record_decision.ts`;
`[PROPOSTA — a validar na implementacao]` = introduzido por esta feature.

Paridade obrigatoria (FR-004): as regras R1..R3 do `data-model.md` valem
identicamente aqui e no helper POSIX — o mesmo padrao ja adotado pela regra de
constitution-conflict, que hoje existe nas duas pontas (zod `superRefine` na
tool, `jq -e` no helper).

---

## Command: `record_decision` (tool MCP, transporte stdio)

**Arquivo**: `mcp/state-server/src/tools/record_decision.ts`
**Contrato-base**: `docs/specs/_archived/2026-08-03-state-mcp-server/contracts/mcp-tools.md` §`record_decision`

### Request

| Field | Type | Required | Validation |
|-------|------|----------|------------|
| `session_id` | string | yes | [EXISTENTE] `min(1)`; resolve a sessao e o `state_dir` |
| `agent` | string | yes | [EXISTENTE] `min(1)` |
| `stage` | string | yes | [EXISTENTE] `min(1)` |
| `context` | string | yes | [EXISTENTE] `min(20)` |
| `options_considered` | array | yes | [EXISTENTE] `min(1)`; item = string ou objeto com `rotulo`/`label` |
| `choice` | string | yes | [EXISTENTE] `min(1)` |
| `rationale` | string | yes | [EXISTENTE] `min(20)` |
| `justification_score` | `0\|1\|2\|3`, nullable | no | [EXISTENTE] |
| `evidence` | string, nullable | no | [EXISTENTE] `min(20)`; obrigatorio se score = 3 |
| `references` | string[], nullable | no | [EXISTENTE] |
| `originating_artifact` | string, nullable | no | [EXISTENTE] |
| `decision_class` | `"estrutural" \| "operacional"`, nullable | condicional | **[PROPOSTA]** obrigatorio quando R1 dispara |
| `structural_axis` | string, nullable | condicional | **[PROPOSTA]** obrigatorio quando `decision_class = "estrutural"`; validado contra o enum de eixos |

### Mapeamento campo -> flag

Entradas novas em `FIELD_TO_FLAG_TABLE` (`mcp/state-server/src/runtime/exec.ts`),
tool `record_decision`:

| Field | Flag |
|-------|------|
| `decision_class` | `--classe` |
| `structural_axis` | `--eixo` |

O mapper local da tool passa cada flag **condicionalmente** (apenas quando o
campo vier definido e nao-nulo), no mesmo padrao ja usado por `--score`,
`--evidencia` e `--artefato-originador`. A execucao continua por
`execFile` com argv array — **nenhum campo novo atravessa shell**.

### Response (accepted)

Inalterada:

```
{ "outcome": "accepted", "reason": null, "stage": null,
  "result": { "decision_id": "dec-NNN" } }
```

`decision_id` continua sendo o `stdout` do helper, nunca gerado pela tool.

### Error Responses

| Code | Origem | Descricao |
|------|--------|-----------|
| `SESSION_MISMATCH` | [EXISTENTE] | Token divergente; helper nao e invocado |
| `TEXT_TOO_SHORT` | [EXISTENTE] | `context`/`rationale` < 20 |
| `EVIDENCE_REQUIRED` | [EXISTENTE] | score 3 sem evidencia valida |
| `SCORE_OUT_OF_RANGE` | [EXISTENTE] | score fora de 0..3 |
| `CONSTITUTION_CONFLICT_SCORE` | [EXISTENTE] | 3 opcoes canonicas com score != 0 |
| `HELPER_FAILED` | [EXISTENTE] | Falha nao classificada do helper |
| `STRUCTURAL_CLASS_REQUIRED` | **[PROPOSTA]** | R1: token de bloqueio humano nas opcoes e `decision_class` ausente |
| `STRUCTURAL_REQUIRES_HUMAN_BLOCK` | **[PROPOSTA]** | R2: classe estrutural com `choice` fora da familia de bloqueio ou score != 0 |
| `STRUCTURAL_AXIS_INVALID` | **[PROPOSTA]** | R3: eixo ausente com classe estrutural, ou fora do enum |

Os tres codigos novos entram no union `McpToolErrorCode` de
`mcp/state-server/src/runtime/exec.ts`. Envelope de erro preservado:
`{ outcome: "rejected", reason: "<CODE>: <mensagem>", stage, result: null }`,
com `isError = true` na serializacao MCP.

### Defesa em profundidade (duas barreiras, deliberado)

| Barreira | Onde | Efeito |
|----------|------|--------|
| 1 | `superRefine` do zod na tool | Rejeita antes de invocar o helper (`stage = "schema"`); erro tipado imediato |
| 2 | Validacao no `state-decisions.sh` | Rejeita mesmo se a tool for contornada (chamada direta ao helper, ou tool desatualizada) |

A barreira 2 e a que garante FR-003 de fato: a tool e uma porta conveniente, o
helper e a porta **autoritativa**. `classifyHelperError()` ganha o match das
mensagens novas do helper para traduzir stderr em codigo tipado, no mesmo padrao
ja usado para `violacao protocolo constitution-conflict`.

### Invariantes

- **INV-M1**: paridade estrita helper <-> tool. Divergir e regressao, nao
  detalhe: a #146 mostrou que uma unica porta sem trava basta para a decisao
  passar.
- **INV-M2**: `exec-mapper-parity.test.ts` gateia a adicao. Ao acrescentar campo
  ao `inputSchema` e obrigatorio (a) uma entrada correspondente em
  `FIELD_TO_FLAG_TABLE` (checagem reciproca: campo orfao e entrada orfa ambos
  falham) e (b) a flag literal entre aspas duplas no arquivo-fonte da tool —
  comentario nao conta.
- **INV-M3**: nenhum campo novo e texto livre; ambos sao enum fechado. Nao ha
  superficie nova de injecao via conteudo (LLM01).
