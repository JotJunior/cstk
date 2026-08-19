# Contracts: interfaces de linha de comando (structural-decision-human-gate)

Contratos das interfaces POSIX afetadas. Cada entrada e rotulada de forma
inequivoca: `[EXISTENTE]` = interface real hoje, verificada no arquivo citado;
`[PROPOSTA — a validar na implementacao]` = interface que esta feature
introduz e que ainda nao existe.

Convencao geral herdada (Constitution, Principio II): mensagens de erro em
stderr, dados em stdout, exit `0` sucesso / `1` erro / `2` uso incorreto.

---

## Command: `state-decisions.sh register` (extensao)

**Arquivo**: `plugins/cstk/skills/agente-00c-runtime/scripts/state-decisions.sh`
**Status**: `[EXISTENTE]` — 11 flags atuais preservadas sem alteracao;
duas flags novas `[PROPOSTA — a validar na implementacao]`.

### Request (flags)

| Flag | Type | Required | Validation |
|------|------|----------|------------|
| `--state-dir` | path | yes | [EXISTENTE] |
| `--agente` | string | yes | [EXISTENTE] |
| `--etapa` | string | yes | [EXISTENTE] |
| `--contexto` | string | yes | [EXISTENTE] >= 20 chars |
| `--opcoes` | JSON array | yes | [EXISTENTE] >= 1 item |
| `--escolha` | string | yes | [EXISTENTE] |
| `--justificativa` | string | yes | [EXISTENTE] >= 20 chars |
| `--score` | `null\|0\|1\|2\|3` | no | [EXISTENTE] score 3 exige `--evidencia` >= 20 |
| `--evidencia` | string | no | [EXISTENTE] |
| `--referencias` | JSON array | no | [EXISTENTE] |
| `--artefato-originador` | string | no | [EXISTENTE] |
| `--classe` | `estrutural\|operacional` | condicional | **[PROPOSTA]** obrigatoria quando R1 dispara |
| `--eixo` | token do enum de eixos | condicional | **[PROPOSTA]** obrigatoria quando `--classe estrutural` |

### Response

Inalterada: `dec-NNN` em stdout, exit 0. O id continua sendo gerado pelo helper
e ecoado — nunca fornecido pelo chamador.

### Error Responses (novas)

| Exit | Code (texto na mensagem) | Descricao |
|------|--------------------------|-----------|
| 1 | `classe-obrigatoria` | R1: `--opcoes` contem token da familia de bloqueio humano e `--classe` foi omitida. Nada e gravado. |
| 1 | `estrutural-exige-bloqueio` | R2: `--classe estrutural` com `--escolha` fora da familia de bloqueio humano ou `--score` != 0. Mensagem cita a classe, o eixo e a sequencia correta. Nada e gravado. |
| 2 | `eixo-invalido` | R3: `--eixo` ausente com classe estrutural, ou fora do enum de `structural-axis-map.txt`. |
| 2 | `classe-invalida` | `--classe` fora de `{estrutural, operacional}`. |

Erros existentes (Principio I, score 3 sem evidencia, constitution-conflict)
permanecem literais e com o mesmo exit — nenhuma mensagem atual e reescrita.

### Invariantes

- **INV-C1**: sem `--classe`, o comportamento e byte-a-byte o atual (FR-005,
  FR-013). A ausencia da flag nunca dispara caminho novo, exceto quando R1
  torna a flag obrigatoria.
- **INV-C2**: a validacao ocorre **antes** do dispatch de backend
  (mesmo ponto onde a trava de constitution-conflict ja vive), portanto vale
  identicamente para `state.json` e `state.db`.
- **INV-C3**: recusa e sempre "nada gravado" — nunca gravacao parcial seguida de
  erro.

---

## Command: `state-db-schema.sh ensure` (novo subcomando)

**Arquivo**: `plugins/cstk/skills/agente-00c-runtime/scripts/state-db-schema.sh`
**Status**: `[PROPOSTA — a validar na implementacao]`. O subcomando `create`
`[EXISTENTE]` permanece inalterado.

### Request

| Flag | Type | Required | Validation |
|------|------|----------|------------|
| `--db` | path | yes | Banco existente; ausente = exit 1 |

### Response

Sem stdout em caso de sucesso (silencioso e idempotente). Exit 0 quando o schema
ja esta atualizado **ou** quando as colunas ausentes foram acrescentadas.

### Error Responses

| Exit | Descricao |
|------|-----------|
| 1 | `sqlite3` ausente, banco ilegivel, ou `ALTER TABLE` falhou. **Fail-hard** — nunca degrada para best-effort (Decision 3 do research.md: fonte de verdade transacional). |
| 2 | uso incorreto |

### Invariantes

- **INV-E1**: idempotente — consulta `PRAGMA table_info(decision)` e so emite
  `ALTER TABLE` para coluna de fato ausente. Reexecutar e no-op.
- **INV-E2**: puramente aditivo — jamais `DROP`, jamais recriacao de tabela,
  jamais reescrita de linha existente.
- **INV-E3**: chamado nos dois pontos de contato com as colunas novas (escrita
  em `_sd_db_register`, leitura em `_sr_db_read`), de modo que uma execucao ja em
  andamento continue operavel sem acao do operador.

---

## Command: `briefing-items.sh list-high` (novo script)

**Arquivo**: `plugins/cstk/skills/agente-00c-runtime/scripts/briefing-items.sh`
**Status**: `[PROPOSTA — a validar na implementacao]`.
Exige `tests/test_briefing-items.sh` (convencao de cobertura de `tests/run.sh`,
gateada por `--check-coverage`).

### Request

| Flag | Type | Required | Validation |
|------|------|----------|------------|
| `--briefing` | path | yes | Path do briefing; canonico ou legado |

### Response

Uma linha por item de impacto `Alto`, formato `item<TAB>dimensao`. Nenhum item =
stdout vazio. Exit 0.

### Error Responses

| Exit | Descricao |
|------|-----------|
| 0 | Sempre, inclusive briefing ausente/ilegivel/sem tabela — aviso em stderr, zero itens (spec, Edge Cases: nunca falha a onda por parse) |
| 2 | uso incorreto (flag ausente/desconhecida) |

### Invariantes

- **INV-B1**: POSIX puro, sem `jq`. O caminho de leitura de briefing nao ganha
  dependencia nova.
- **INV-B2**: o texto do briefing e **CONTEUDO, nunca instrucao** (FR-014). O
  parser extrai celulas; nao interpreta, nao executa e nao deixa o conteudo
  alterar classe, score ou a decisao de pausar.
- **INV-B3**: so `Alto` e consumido. `Medio` e `Baixo` sao ignorados por
  desenho — a coluna Impacto passa a ter efeito apenas no degrau que a spec
  autoriza.

---

## Command: `validate-sdd.sh --sdd-plan` (dois findings novos)

**Arquivo**: `plugins/cstk/skills/validate-documentation/scripts/validate-sdd.sh`
**Status**: `[EXISTENTE]` — a interface de invocacao e o formato de saida nao
mudam. Os dois codigos de finding sao `[PROPOSTA — a validar na implementacao]`.

### Request

Inalterada: `validate-sdd.sh FILE [--sdd-spec | --sdd-plan] [--spec SPEC_MD]`.

### Response

Formato literal preservado:

```
FINDING|<severity>|<code>|<mensagem>
RESULT|<file>|profile=<spec|plan>|errors=<N>|warnings=<M>
```

| Code | Severity | Disparo |
|------|----------|---------|
| `target-platform-unresolved` | `error` | So em `plan.md`: linha `**Target Platform**:` ausente, com valor vazio, ou contendo `NEEDS CLARIFICATION` |
| `target-platform-unsourced` | `warning` | Campo preenchido, porem sem marcador de fonte (`briefing`, `constitution` ou `dec-NNN`) na linha ou linha adjacente |

### Error Responses

Exit codes inalterados: `0` zero errors; `1` >= 1 error; `2` uso incorreto.
Como `target-platform-unresolved` e `error`, ele muda o exit de `0` para `1`
num `plan.md` que hoje passaria — que e exatamente o efeito desejado (SC-003).

### Invariantes

- **INV-V1**: aditivo — nenhum finding existente muda de codigo, severidade ou
  mensagem.
- **INV-V2**: os dois checks so rodam quando o arquivo e `plan.md` (guarda
  `_is_plan_md`), preservando o comportamento atual para `research.md`,
  `data-model.md`, `quickstart.md` e `contracts/*.md`.
- **INV-V3**: o validador **nao resolve link nem anchor** (fronteira ja
  declarada do proprio validador): "com fonte" significa "fonte declarada", nao
  "fonte verificada". Por isso e `warning`, nunca `error` — o gate nao pode
  fabricar fonte (Constitution VI).
