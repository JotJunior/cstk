# Contracts: superfície de operador (`cstk`)

Contratos de interface externa expostos ao operador pelo binário `cstk`.

> **STATUS: `[PROPOSTA — a validar na implementação]`**
> Nenhum dos comandos desta página existe hoje. Verificado em 2026-08-01:
> `cli/lib/state.sh` implementa **apenas** o subcomando `migrate`
> (`state_main`, `case` em L85-90) e `cli/lib/doctor.sh` aceita **apenas** as
> flags `--fix` e `--scope` (`_doctor_parse_args`, L180-...). Este documento
> projeta superfície nova; não descreve comportamento existente.

---

## Command: `cstk state enable-sqlite`

Ativa o backend SQLite como padrão para **novas** inicializações de execução 00c,
gravando a declaração na configuração global por-usuário.

**Superfície**: `cstk state enable-sqlite`
**Escreve**: `$HOME/.claude/cstk/config` (somente no caminho de sucesso)
**Delegação**: `cli/lib/state.sh` resolve e invoca o script do runtime
(Decision 2), repassando o exit code verbatim — mesmo padrão já usado por
`cstk state migrate`.

### Argumentos

Nenhum argumento posicional.

| Flag | Required | Descrição |
|------|----------|-----------|
| `-h`, `--help` | não | Imprime uso e sai 0 |

### Pré-condições verificadas (nesta ordem, todas antes de qualquer escrita)

| # | Verificação | Falha ⇒ |
|---|-------------|---------|
| 1 | `sqlite3` presente no `PATH` | Exit não-zero, config inalterada (FR-004) |
| 2 | Versão de `sqlite3` ≥ `3.45.1` | Exit não-zero, config inalterada (FR-004) |
| 3 | Runtime do catálogo instalado suporta backend config | Exit não-zero, config inalterada (FR-004A) |

A ordem importa: nenhuma escrita ocorre antes de as três passarem. Isso é o que
torna SC-002 verdadeiro por construção e não por limpeza posterior.

### Comportamento

Em **todo** caminho de sucesso (linhas 1-3 da tabela abaixo), a primeira linha
emitida MUST citar qual caminho foi validado na checagem de capability (P8,
decisão da task 1.1/CHK010 — ver `state-backend-runtime.md` §Nota sobre P8):
`cstk state enable-sqlite: capability verificado via <origem> (<path>)`, onde
`<origem>` ∈ `catalogo-instalado` \| `arvore-do-repo` e `<path>` é o path
absoluto de fato inspecionado. Essa linha é seguida pela linha de resultado
descrita na coluna "Resultado".

| Estado inicial da config | Resultado |
|--------------------------|-----------|
| Ausente, pré-condições OK | Cria o arquivo com `state_backend=sqlite`, exit 0 |
| `state_backend=json`, pré-condições OK | Reescreve a linha para `sqlite`, exit 0 |
| `state_backend=sqlite`, pré-condições OK | **No-op silencioso**, exit 0, sem duplicar entrada (FR-009-INFRA-IDEMP) |
| Qualquer, pré-condição falha | Config **byte-a-byte inalterada**, exit não-zero, diagnóstico em stderr |

### Diagnósticos de recusa

Cada mensagem MUST citar o que foi observado e o que era exigido — nunca apenas
"falhou". Conteúdo obrigatório por caso:

| Caso | A mensagem MUST citar |
|------|-----------------------|
| `sqlite3` ausente | que a dependência está ausente + a versão mínima exigida (`3.45.1`) + como instalar |
| `sqlite3` abaixo do mínimo | a versão **mínima exigida** e a versão **efetivamente detectada** (FR-004, literal) |
| Runtime incapaz | **a linha `cstk state enable-sqlite: capability verificado via <origem> (<path>)`** (P8 — qual caminho foi validado, repo vs. catálogo instalado) seguida da necessidade de rodar `cstk update` / `cstk self-update` (FR-004A, literal) |

> **Decisão de escopo (CHK010, task 1.1)**: a linha "caminho validado" é
> exigida SOMENTE nos casos ligados à checagem de capability (sucesso e
> "Runtime incapaz") — é aí que existe uma noção de caminho repo-vs-catálogo a
> reportar (P8/SEC-03). As recusas por `sqlite3` ausente/abaixo do mínimo não
> ganham essa linha: dizem respeito à presença/versão do binário `sqlite3` no
> `PATH`, sem relação com qual runtime do catálogo foi validado.

### Exit codes

| Code | Significado |
|------|-------------|
| 0 | Ativado, ou já ativado (no-op idempotente) |
| não-zero | Recusado por pré-condição; config inalterada |

> Os exit codes já publicados por `cstk state` (`0` sucesso, `1` falha, `2` uso
> incorreto, `3` recusado por pré-condição — documentados no cabeçalho de
> `cli/lib/state.sh`) permanecem a convenção da família. A recusa por dependência
> ou por runtime incapaz é conceitualmente "recusado por pré-condição".

---

## Command: `cstk doctor --deps`

Reporta o estado das dependências relevantes à decisão de backend e qual backend
seria efetivamente usado numa nova inicialização **agora**, com o motivo.

**Superfície**: `cstk doctor --deps`
**Escreve**: nada — estritamente read-only.

### Argumentos

| Flag | Required | Descrição |
|------|----------|-----------|
| `--deps` | sim (para este modo) | Ativa o diagnóstico de dependências |

> `--deps` é **aditiva** às flags existentes de `cstk doctor` (`--fix`,
> `--scope`), que permanecem com comportamento inalterado.

### Saída (stdout)

Relatório legível contendo, no mínimo (FR-007):

- para cada dependência relevante (**ao menos** `sqlite3` e `jq`): presença,
  versão detectada e, quando aplicável, versão mínima exigida;
- o **backend efetivo** que uma nova inicialização usaria agora;
- o **motivo** dessa escolha (domínio de `reason` em `data-model.md`).

O relatório é emitido em stdout **tanto no caminho de sucesso quanto no de
anomalia** — um gate de CI que falha precisa dizer o que falhou na mesma execução.

### Exit codes

| Code | Condição |
|------|----------|
| 0 | Nenhuma anomalia detectada |
| não-zero | Ao menos uma anomalia: dependência ausente ou abaixo do mínimo |

**"Nunca configurado" não é anomalia** — é o default legítimo de qualquer
instalação que não optou pelo SQLite (FR-008). Tratá-lo como anomalia faria o gate
falhar em toda instalação padrão, tornando-o inútil.

### Uso como gate de CI

```sh
cstk doctor --deps || exit 1
```

Sem parsing da saída — o exit code é suficiente (SC-003).
