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
| `--consentimento` | id `block-NNN` | condicional | **[PROPOSTA]** unica forma de registrar estrutural com escolha concreta; validada contra o estado — existencia, execucao, `status = respondido` e `subject_key` do **mesmo eixo** (R6) |

### Response

Inalterada: `dec-NNN` em stdout, exit 0. O id continua sendo gerado pelo helper
e ecoado — nunca fornecido pelo chamador.

### Error Responses (novas)

| Exit | Code (texto na mensagem) | Descricao |
|------|--------------------------|-----------|
| 1 | `classe-obrigatoria` | R1: `--opcoes` contem token da familia de bloqueio humano e `--classe` foi omitida. Nada e gravado. |
| 1 | `estrutural-exige-bloqueio` | R2: `--classe estrutural` **sem `--consentimento` valido** e com `--escolha` fora da familia de bloqueio humano, ou `--score` != 0. Mensagem cita a classe, o eixo e a sequencia correta. Nada e gravado. |
| 1 | `consentimento-invalido` | R6: `--consentimento` aponta bloqueio inexistente, de outra execucao, ou com `status != respondido`. Mensagem cita o id apresentado e o status encontrado (ou "ausente"). Nada e gravado. |
| 1 | `consentimento-de-outro-assunto` | R6: o bloqueio esta respondido, porem seu `subject_key` nao e `axis:<eixo desta Decisao>`. Mensagem cita os dois assuntos, lado a lado. Nada e gravado. Fecha o confused deputy: consentimento dado para um eixo nao autoriza outro. |
| 2 | `eixo-invalido` | R3: `--eixo` ausente com classe estrutural, ou fora do enum de `structural-axis-map.txt`. |
| 2 | `classe-invalida` | `--classe` fora de `{estrutural, operacional}`. |

Erros existentes (Principio I, score 3 sem evidencia, constitution-conflict)
permanecem literais e com o mesmo exit — nenhuma mensagem atual e reescrita.

### Invariantes

- **INV-C1**: sem `--classe`, o comportamento e byte-a-byte o atual (FR-005,
  FR-013). A ausencia da flag nunca dispara caminho novo, exceto quando R1
  torna a flag obrigatoria.
- **INV-C2**: R1..R3 sao validacao **pura de entrada** (nao leem estado) e
  ocorrem antes do dispatch de backend, no mesmo ponto onde a trava de
  constitution-conflict ja vive. **R6 e diferente por natureza**: precisa
  consultar o BloqueioHumano citado, logo depende do backend. Ela roda no inicio
  do ramo de cada backend, usando o leitor ja existente daquele backend, e antes
  de qualquer escrita. O contrato observavel e o mesmo nos dois backends (mesmo
  exit, mesma mensagem, nada gravado); o que difere e so o mecanismo de leitura.
  Declarar isso evita a armadilha de tentar implementar R6 no ponto pre-dispatch,
  onde nao ha como ler estado.
- **INV-C3**: recusa e sempre "nada gravado" — nunca gravacao parcial seguida de
  erro.
- **INV-C4**: o valor de `--consentimento` e **sempre verificado contra o
  estado**, jamais aceito como declaracao. O helper le o bloqueio citado e
  confere `execution_id`, `status` e `subject_key`; nao ha caminho em que a mera
  presenca da flag satisfaca R2.
- **INV-C6**: um consentimento so vale para o eixo que o originou. Nao existe
  bloqueio "curinga": `subject_key` NULL ou de outro prefixo nunca satisfaz R6.
- **INV-C5**: o campo `--agente` **nao** participa de nenhuma das regras novas.
  Trocar `--agente` de `agente-00c-orchestrator` para `operador` nao muda o
  resultado de nenhuma validacao (verificavel por teste: mesmo input com os dois
  valores produz o mesmo exit e a mesma mensagem).

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
- **INV-E3**: chamado **apenas em caminhos de escrita** (`_sd_db_register`,
  `init`, migracao json->db), de modo que uma execucao ja em andamento continue
  operavel sem acao do operador. O caminho de leitura **nunca** invoca `ensure`
  e **nunca** emite DDL (correcao do finding M3): ele consulta
  `PRAGMA table_info(decision)` e escolhe entre duas consultas literais fixas —
  a que projeta as colunas novas e a que projeta `NULL` no lugar delas.
- **INV-E4**: nenhuma operacao declarada read-only (relatorio, auditoria,
  `review-task`) requer permissao de escrita no banco por causa desta feature.

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

Uma linha por item de impacto `Alto`, formato `item_key<TAB>item<TAB>dimensao`,
seguida **sempre** de uma linha final `STATUS<TAB><token>` com `<token>` em
`{ok, sem-itens-alto, tabela-irreconhecivel, briefing-ausente}`. Exit 0.

Nenhum item **nao** produz stdout vazio: produz a linha `STATUS` sozinha. Essa e
a correcao do finding M2 — antes, "briefing ausente" e "briefing sem itens Alto"
eram indistinguiveis (ambos stdout vazio + exit 0), e o gate de governanca
passava silenciosamente exatamente no caso de menor informacao.

`item_key` e derivado por funcao pura do texto do item (regra literal em
`data-model.md` §Derivacao da chave); e o sufixo do `subject_key` gravado no
BloqueioHumano.

### Error Responses

| Exit | Descricao |
|------|-----------|
| 0 | Sempre, inclusive briefing ausente/ilegivel/sem tabela — aviso em stderr, zero itens e `STATUS` correspondente em stdout (spec, Edge Cases: nunca falha a onda por parse). Quem decide o que fazer com o estado degradado e o orquestrador, nao o parser |
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
- **INV-B4**: cada celula e saneada (NUL/TAB/CR/LF removidos, whitespace
  colapsado) **antes** de compor a linha TSV. Nenhum conteudo de briefing pode
  acrescentar colunas a saida (finding L1).
- **INV-B5**: mesma entrada produz sempre a mesma `item_key`; entradas
  diferentes produzem chaves diferentes. Sem estado, sem rede, sem lista de
  sinonimos.

---

## Command: `bloqueios.sh register` / `list` (extensao — chave de assunto)

**Arquivo**: `plugins/cstk/skills/agente-00c-runtime/scripts/bloqueios.sh`
**Status**: `[EXISTENTE]` — as flags atuais de `register` (`--state-dir`,
`--decisao-id`, `--pergunta`, `--contexto-para-resposta`,
`--opcoes-recomendadas`) e a saida de `list` sao preservadas.
Uma flag nova em cada, `[PROPOSTA — a validar na implementacao]`.

### Request — `register`

| Flag | Type | Required | Validation |
|------|------|----------|------------|
| `--chave-assunto` | token com prefixo fechado | no | **[PROPOSTA]** `briefing-item:<slug>` ou `axis:<eixo>`; prefixo fora do enum = exit 2 |

Ausente = `subject_key` NULL, comportamento atual integral (bloqueios que nao
representam um assunto deduplicavel).

### Request — `list`

| Flag | Type | Required | Validation |
|------|------|----------|------------|
| `--chave-assunto` | token | no | **[PROPOSTA]** filtra por igualdade exata; combinavel com `--status` |

### Response

`register`: inalterada (`block-NNN` em stdout, exit 0).
`list`: o TSV atual (`id`, `decision_id`, `status`, `triggered_at`, `pergunta`)
**nao muda de colunas** — a flag apenas filtra linhas. Manter a largura do TSV
evita quebrar todo consumidor existente por um campo que so o gate FR-008 le.

### Consulta de dedup (FR-008)

```sh
# vazio => ainda nao decidido => registrar bloqueio
bloqueios.sh list --state-dir "$SD" --status respondido \
  --chave-assunto "briefing-item:$KEY"
```

### Error Responses

| Exit | Descricao |
|------|-----------|
| 2 | `--chave-assunto` com prefixo fora de `{briefing-item:, axis:}` ou sufixo vazio |

Demais exits inalterados.

### Invariantes

- **INV-K1**: bloqueios anteriores a esta feature tem `subject_key` NULL e nunca
  casam com chave alguma. A degradacao e sempre no sentido de **perguntar de
  novo**, jamais de presumir decidido.
- **INV-K2**: a chave nunca e escolhida pelo orquestrador quando origina do
  briefing — vem de `briefing-items.sh`. Isso impede que um agente suprima a
  propria pergunta reusando a chave de um assunto ja respondido.
- **INV-K3**: `subject_key` nao e propagado a knowledge.db (unico campo novo
  derivado de texto de projeto; a dedup e sempre avaliada na execucao corrente).

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
