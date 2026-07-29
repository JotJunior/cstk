# Contract: hook `PreToolUse` (interceptacao enforced de Bash — US1)

Contrato do script `[PROPOSTA] global/skills/agente-00c-runtime/hooks/pretooluse-bash-guard.sh`,
registrado no harness sob `"hooks"."PreToolUse"` com `matcher: "Bash"`.

> **Fonte do formato de entrada/saida do harness**: documentacao oficial
> `https://code.claude.com/docs/en/hooks` (verificada nesta onda via agente
> `claude-code-guide`). Campos e nomes abaixo marcados "harness" sao contrato
> EXTERNO ja existente, nao inventado por esta feature — reproduzidos aqui
> tal como documentados. Campos marcados "desta feature" sao decisao de
> design nova ([PROPOSTA]).

## Input (stdin, harness)

```json
{
  "session_id": "string",
  "cwd": "/path/absoluto/do/projeto",
  "hook_event_name": "PreToolUse",
  "tool_name": "Bash",
  "tool_input": {
    "command": "string — o comando shell literal que seria executado"
  }
}
```

| Field | Type | Required | Origem |
|-------|------|----------|--------|
| cwd | string | yes | harness — base para localizar `.claude/agente-00c-state/` e `.claude/feature-00c-state/*/` (Decision 3) |
| tool_name | string | yes | harness — hook so age quando `"Bash"` (defesa redundante: `matcher` do settings.json ja filtra) |
| tool_input.command | string | yes | harness — string literal validada contra `bash-guard.sh check` |

### Precedencia quando ha MAIS DE UMA execucao ativa (CHK007, task 1.3)

Se `agente-00c-state/state.json` E um ou mais `feature-00c-state/<short>/state.json`
estiverem simultaneamente `em_andamento` sob o mesmo `cwd`, o hook resolve
`detected_execution`/`detected_execution_path` (campos de
`EnforcementDecisionLog`, ver `data-model.md`) por ordem FIXA e
deterministica: (1) `agente-00c` vence se presente e ativo; (2) senao, entre
os `feature-00c` ativos, o de MENOR `<short>` em ordem lexicografica
(byte-wise) vence. A regra de precedencia so afeta QUAL execucao e citada no
log — a decisao de bloqueio (`bash-guard.sh check`) e identica
independentemente de qual delas foi escolhida. Regra completa e rationale
em `data-model.md::EnforcementDecisionLog §Precedencia deterministica`.

## Output (stdout, desta feature aplicando o contrato do harness)

**Caso 1 — fora do escopo (sem execucao ativa, FR-006/Decision 3) ou comando
permitido**: `exit 0`, stdout vazio. Harness aplica fluxo normal de permissoes
(nenhuma decisao do hook).

**Caso 2 — bloqueado (por regra OU por falha do mecanismo, FR-002/FR-007)**:
`exit 0` + stdout:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "<prefixo>: <motivo>"
  }
}
```

`<prefixo>` (desta feature, para diagnostico distinguivel — FR-002/FR-007):

| Prefixo | Quando |
|---------|--------|
| `REGRA_VIOLADA` | `bash-guard.sh check` retornou exit 1 (violacao de blocklist ou whitelist de rede) |
| `MECANISMO_FALHOU` | qualquer falha interna do proprio hook: `jq` ausente (Decision 2), `bash-guard.sh` ausente/nao-executavel, `bash-guard.sh` retornou exit 2 (uso incorreto — bug do hook), timeout |

`<motivo>` reusa a mensagem ja emitida por `bash-guard.sh` (`_bg_emit_block`,
formato `"categoria=%s — %s"`) quando `REGRA_VIOLADA`; texto proprio do hook
(ex: `"jq ausente, comando nao pode ser validado com seguranca"`) quando
`MECANISMO_FALHOU`.

## Efeito colateral obrigatorio (FR-016)

Toda saida do **Caso 2**, e toda saida do **Caso 1 quando havia execucao
ativa detectada** (comando permitido dentro do escopo, para auditoria
positiva tambem), MUST gravar uma linha em
`<cwd>/.claude/enforcement-log.jsonl` conforme `data-model.md::EnforcementDecisionLog`
ANTES de emitir o stdout/exit final. Falha ao escrever o log NAO MUST impedir
a decisao de bloqueio/permissao ja tomada (o log e auditoria, nao gate — mas
a falha de escrita em si e best-effort logada em stderr do proprio hook, sem
interromper o fluxo do harness).

## Erros do proprio contrato (nao de regra de negocio)

| Situacao | Tratamento |
|----------|------------|
| stdin vazio ou JSON invalido | `MECANISMO_FALHOU` (fail-closed, mesma logica de Decision 2) |
| `tool_name != "Bash"` (nao deveria acontecer dado o `matcher`, defesa em profundidade) | `exit 0` sem decisao — nao e escopo deste hook |
| `bash-guard.sh` demora mais que o timeout do hook (`GuardHookRegistration.timeout`) | tratado pelo PROPRIO harness como falha do hook — comportamento de timeout do harness nao e definido por esta feature; nota de risco em `research.md` Decision 1 |
