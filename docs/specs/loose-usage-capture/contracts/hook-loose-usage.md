# Contracts: hook `posttooluse-loose-usage.sh` `[PROPOSTA — a validar na implementacao]`

Hook `PostToolUse` dedicado a captura de consumo avulso (dec-006). **Nao
existe hoje**; o molde e `global/skills/agente-00c-runtime/hooks/posttooluse-tool-call-tick.sh`
(EXISTENTE, 159 linhas), cujas invariantes sao herdadas integralmente.

---

## Registro no harness `[PROPOSTA]`

Bloco em arquivo SEPARADO do `settings.snippet.json` atual (dec-008 / FR-006).
O snippet existente registra os tres hooks obrigatorios
(`pretooluse-bash-guard` em `PreToolUse`/`Bash`, `posttooluse-tool-call-tick`
em `PostToolUse`/`*`, `posttooluse-agent-usage` em `PostToolUse`/`Agent`) —
o hook de captura avulsa NAO entra ali.

| Campo | Valor |
|-------|-------|
| Evento | `PostToolUse` |
| `matcher` | `*` |
| `command` | `"$CLAUDE_PROJECT_DIR"/.claude/hooks/posttooluse-loose-usage.sh` |
| `timeout` | `5` (mesmo teto dos hooks existentes) |

Provisionado por `cstk hooks install --with-loose-usage` `[PROPOSTA]` —
flag nova, default DESLIGADA. Sem a flag, `apply_guard_hooks()` mantem
exatamente o comportamento atual.

---

## Entrada

STDIN: payload JSON do harness. Campos consumidos (os mesmos ja consumidos
pelo molde, linhas 73-78):

| Campo | Uso |
|-------|-----|
| `.cwd` | Projeto ao qual o consumo e atribuido (FR-002). Vazio ⇒ no-op |
| `.tool_name` | Sanidade do payload. Vazio ⇒ no-op (nao inventa captura) |

Ambiente consumido:

| Variavel | Uso | Fonte |
|----------|-----|-------|
| `CSTK_OTEL_ENDPOINT` | Endpoint por processo; **ancora de identidade** | Observada presente no subprocesso do harness (research.md Decision 3) |
| `CSTK_LOOSE_USAGE_INTERVAL_S` | Override do intervalo de throttle `[PROPOSTA]` | Default `300` |

**NAO consumidas**: `OTEL_METRICS_EXPORTER` e `OTEL_EXPORTER_PROMETHEUS_PORT`
— observadas AUSENTES no ambiente do subprocesso (research.md Decision 3).
Gatear por elas produziria zero captura.

---

## Saida

| Canal | Contrato |
|-------|----------|
| stdout | SEMPRE vazio |
| stderr | SEMPRE vazio (nenhuma falha e reportada ao operador) |
| exit | SEMPRE `0` |
| Efeito | No maximo: escrita sob `~/.claude/cstk/loose-usage/<process_key>/` |

**REGRA DURA (herdada do molde, linhas 22-35)**: o hook NUNCA le nem escreve
`state.json`/`state.db`, e NUNCA abre o `knowledge.db`. `PostToolUse` dispara
concorrente as tool calls; qualquer read-modify-write de estado compartilhado
poderia clobberar uma escrita transacional.

---

## Sequencia (ordem obrigatoria — barato antes de caro)

| # | Passo | Falha ⇒ |
|---|-------|---------|
| 1 | `CSTK_OTEL_ENDPOINT` presente? | no-op |
| 2 | `jq` disponivel? | no-op (dep opcional, fail-open — igual ao molde linha 68) |
| 3 | Parse do stdin; `.cwd` e `.tool_name` nao-vazios? | no-op |
| 4 | Throttle: `now - meta.updated_at >= intervalo`? | no-op (caminho O(1), sem rede) |
| 5 | Deteccao de execucao ativa (invertida — abaixo) | conforme tabela |
| 6 | `otel-usage.sh snapshot` no diretorio do segmento | no-op (o proprio snapshot ja degrada) |
| 7 | Atualiza `meta.tsv` (`updated_at`, `current_segment`) | no-op |

O passo 4 antes do 5 e deliberado: o throttle e a checagem mais barata que
descarta a maioria esmagadora dos ticks; so depois vale sondar estado.

---

## Polaridade da deteccao de execucao ativa (INVERTIDA — dec-006)

Helper `_hook-active-exec.sh` (EXISTENTE; contrato no cabecalho, linhas 31-36):

| Exit do helper | Significado | Acao do hook de captura | Acao do hook de tick (molde) |
|----------------|-------------|--------------------------|------------------------------|
| `0` | ativa | **fecha o segmento**, nao captura | grava tick |
| `1` | inativa | **captura** | no-op |
| `2` | indeterminada | no-op | no-op |
| `3` | uso incorreto | no-op | no-op |

`indeterminada` NAO e tratada como `inativa`: capturar sob incerteza
fabricaria consumo avulso (Constitution VI). A assimetria e intencional —
SC-002 exige 100% de exclusao das janelas de pipeline; nao ha requisito
simetrico de 100% de captura do avulso.

**Pre-check inline**: o molde sai barato quando NAO ha nenhum
`state.json`/`state.db` sob `.claude/agente-00c-state/` ou
`.claude/feature-00c-state/*/` (linhas 85-106). Sob polaridade invertida esse
mesmo teste conclui `inativa` — e o hook segue para a captura sem sourcear o
helper. Mantem-se o requisito SEC-H1 do molde: o pre-check usa
EXCLUSIVAMENTE builtins do shell, antes de qualquer resolucao de dependencia.

`HAE_BUSY_TIMEOUT_MS`: `50` (mesma politica de hook de metrica do molde,
linhas 137-140) — sob contencao do SQLite o helper devolve `indeterminada` e
o tick e pulado, nunca esperado.

---

## Resolucao de dependencias

Mesma cadeia do molde (`_ptt_resolve_dep_hae`, linhas 115-130), com `$HOME`
antes de `<cwd>` e teste `-r` (helpers `_*.sh` do runtime nao sao
executaveis):

1. `<dir do hook>/../scripts/<rel>`
2. `$HOME/.claude/skills/agente-00c-runtime/scripts/<rel>`
3. `<cwd>/.claude/skills/agente-00c-runtime/scripts/<rel>`

Dependencias resolvidas por essa cadeia: `_hook-active-exec.sh` (sourceado) e
`otel-usage.sh` (executado). Qualquer uma irresolvivel ⇒ no-op silencioso.

---

## Privacidade (Constitution IV)

- Toda leitura e de `127.0.0.1` (loopback). Nada e transmitido para fora.
- Os labels de PII (`user_id`, `user_email`, `user_account_uuid`,
  `user_account_id`, `organization_id`) sao descartados por construcao no
  parse do `otel-usage.sh` (allowlist de 4 labels, linhas 170-197) e
  reconferidos por defesa em profundidade antes de o snapshot ser publicado
  (linhas 276-281, que APAGAM o arquivo e falham alto se algum vazar).
- Nenhum artefato desta feature sai do filesystem local do operador.
