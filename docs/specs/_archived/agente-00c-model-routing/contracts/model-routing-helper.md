# Contract: helper `model-routing.sh`

Contrato de invocacao do helper POSIX novo desta feature, residente em
`~/.claude/skills/agente-00c-runtime/scripts/model-routing.sh` (fonte:
`global/skills/agente-00c-runtime/scripts/model-routing.sh`).

Nao ha REST API. Esta feature e single-layer — toolkit CLI sobre
shell POSIX. O contrato cobre 3 subcomandos invocados pelos
orquestradores no caminho pre-spawn da fase clarify.

---

## Subcommand: `template`

Emite o input textual deterministico para o `subagent_type` solicitado.
Cumpre FR-002 (template por tipo) sem precisar de arquivo externo.

### Invocacao

```sh
model-routing.sh template --subagent-type <type>
```

### Argumentos

| Field | Type | Required | Validation |
|-------|------|----------|------------|
| `--subagent-type` | string | yes | enum: `agente-00c-clarify-asker`, `agente-00c-clarify-answerer`, `feature-00c-clarify-asker`, `feature-00c-clarify-answerer` |

### Output (exit 0)

Texto em stdout — string sem aspas, sem JSON wrapping. Exemplo:

```
enumerative scan of spec for ambiguities producing up to 5 questions.
inputs: spec text, briefing summary, constitution principles.
output: JSON list of questions referencing FR/edge case ids.
```

### Error Responses

| Exit | Codigo | Descricao |
|------|--------|-----------|
| 2 | `unknown-subagent-type` | `--subagent-type` ausente ou nao mapeado |
| 1 | `usage` | falta de flag obrigatoria |

---

## Subcommand: `invoke`

Sequencia completa de uma invocacao: trunca input se necessario,
chama `model-selector` via shell, parseia output, retorna JSON
canonico em stdout para o orquestrador consumir.

### Invocacao

```sh
model-routing.sh invoke \
  --subagent-type <type> \
  --etapa <stage> \
  [--input-text <override>]
```

### Argumentos

| Field | Type | Required | Validation |
|-------|------|----------|------------|
| `--subagent-type` | string | yes | mesmo enum do `template` |
| `--etapa` | string | yes | `clarify` (futuras fases entrarao via FR-016) |
| `--input-text` | string | no | se omitido, usa `template --subagent-type T`; se passado, substitui template (caso de teste / override manual) |

### Output (exit 0)

JSON UTF-8 em stdout. Schema:

```json
{
  "subagent_type": "agente-00c-clarify-asker",
  "etapa": "clarify",
  "modelo": "haiku",
  "score_skill": 2,
  "score_runtime": 3,
  "alternativa": "sonnet",
  "sinais_text": "- rode: rasa (peso=1)\n- grep: rasa (peso=1)",
  "fallback": false,
  "input_truncado": false,
  "input_bytes": 218,
  "raw_stdout_first_200": "## Sugestao\n\n**modelo**: haiku..."
}
```

### Output em fallback (exit 0 ainda — fallback nao e erro)

Se a skill falhou (exit != 0, ausente, output mal-formado):

```json
{
  "subagent_type": "agente-00c-clarify-asker",
  "etapa": "clarify",
  "modelo": "fallback-default",
  "score_skill": null,
  "score_runtime": 0,
  "alternativa": null,
  "sinais_text": null,
  "fallback": true,
  "fallback_reason": "skill-not-found",
  "fallback_stderr_first_200": "...",
  "input_truncado": false,
  "input_bytes": 218
}
```

`fallback_reason` enum: `skill-not-found` | `parse-failure` |
`exit-nonzero` | `tool-skill-unavailable`.

### Error Responses (apenas erros de USO do helper)

| Exit | Codigo | Descricao |
|------|--------|-----------|
| 2 | `usage` | flag obrigatoria ausente ou enum invalido |
| 1 | `state-dir-missing` | helper invocado sem AGENTE_00C_STATE_DIR no env (necessario para metricas opcionais) — somente quando metricas estao habilitadas |

**Importante**: falha da skill NAO retorna exit nao-zero. Conforme
FR-008 + FR-009, a falha vira `fallback: true` no JSON e o helper
mantem exit 0. Isso preserva o invariante de que invocar
`model-selector` NUNCA derruba o orquestrador.

---

## Subcommand: `idempotent-check`

Determina se ja existe Decisao registrada para o par
`(subagent_type, onda_id)` na onda corrente. Cumpre FR-012.

### Invocacao

```sh
model-routing.sh idempotent-check \
  --state-dir <dir> \
  --onda-id <onda-NNN> \
  --subagent-type <type>
```

### Argumentos

| Field | Type | Required | Validation |
|-------|------|----------|------------|
| `--state-dir` | path | yes | diretorio com `state.json` legivel |
| `--onda-id` | string | yes | pattern `^onda-[0-9]{3}$` |
| `--subagent-type` | string | yes | mesmo enum |

### Output

| Exit | Stdout | Significado |
|------|--------|-------------|
| 0 | `dec-NNN` | ja existe — orquestrador pula invocacao da skill |
| 1 | (vazio) | nao existe — orquestrador prossegue para `invoke` |
| 2 | (vazio) | erro de uso (flag ausente, state.json inexistente) |

---

## Invariantes testaveis (consumidas por `/checklist`)

- **INV-1**: `invoke` SEMPRE retorna exit 0 quando flags sao validas,
  mesmo com a skill quebrada (FR-009).
- **INV-2**: `invoke` retorna JSON parseavel por jq em 100% dos casos
  de exit 0.
- **INV-3**: para `--input-text` com >4096 chars, output JSON contem
  `"input_truncado": true` e `input_bytes <= 4016`.
- **INV-4**: `idempotent-check` e read-only — NUNCA escreve em
  state.json. Pode ser invocado em paralelo sem race.
- **INV-5**: `template` e puro — output identico para mesmo input
  em qualquer ambiente; sem leitura de arquivos externos.
- **INV-6**: helper completo respeita Principio II — `#!/bin/sh`,
  `set -eu`, zero bash-isms, deps apenas em `awk`, `wc`, `head`,
  `tail`, `tr`, `jq` (este ultimo herdado do runtime).
