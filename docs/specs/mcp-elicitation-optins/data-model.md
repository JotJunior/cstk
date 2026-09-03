# Data Model: mcp-elicitation-optins

Modelo de dados da feature. Duas camadas:

1. **Campos ja existentes** no `state.json` / `state.db` (valor efetivo dos
   opt-ins) — **nao mudam** de nome, tipo nem semantica.
2. **Campo novo aditivo** `.optin_responses[]` — materializa a entidade
   `RespostaDeOptIn` da spec (registro de auditoria: qual canal, qual desfecho).

> **Constitution VI**: os nomes de campo da camada 1 sao VERIFICADOS
> (`state-rw.sh:536-538`). Os da camada 2 sao
> **[PROPOSTA — a validar na implementacao]**, pois sao desenho novo desta
> feature.

---

## Entity: OptInValorEfetivo (camada 1 — existente, inalterada)

Valor que efetivamente governa o comportamento da execucao. Continua sendo a
**unica** fonte lida pelos consumidores (`commit-mode.sh is-enabled`,
`roadmap-mode.sh is-enabled`, `delivery-tier.sh get`).

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| `atomic_commit_enabled` | boolean | default `false` | VERIFICADO: `state-rw.sh:536`. Top-level. Leitura via `commit-mode.sh is-enabled` |
| `roadmap_mode_enabled` | boolean | default `false` | VERIFICADO: `state-rw.sh:537`. Escrita **write-once** apos ondas (`roadmap-mode.sh:142`) |
| `delivery_tier` | enum | `local` \| `internal-network` \| `cloud-internal` \| `cloud-public`; default `cloud-public` | VERIFICADO: `state-rw.sh:353` (default) e `:538` (campo). Leitura **exclusiva** via `delivery-tier.sh get` (INV-5) |
| `execution.status` | string | `em_andamento` no init | VERIFICADO: pre-requisito de validade do token (`mcp-session.sh:25-32`) |

### Ordinal do enum `delivery_tier`

VERIFICADO em `delivery-tier.sh` `_dt_ordinal:100-107`. O eixo e **rigor de
gate**, nao exposicao de rede:

```
local (0) → internal-network (1) → cloud-internal (2) → cloud-public (3)
   menos rigor  ──────────────────────────────────────────►  mais rigor
```

`cloud-public` = maior ordinal = **maior profundidade de gate** = o valor
seguro/restritivo de FR-006 (ver `research.md` Decision 3).

**Regra de escrita derivada (dec-037, emendada por dec-047)**: como o init
grava o ordinal 3, qualquer resposta do operador diferente de `cloud-public` e
**rebaixamento** e exige `--allow-downgrade`, senao `set` retorna exit 2 **sem
escrever** (VERIFICADO: `delivery-tier.sh:22-27`). A flag e **condicional**, e
nao incondicional: passa **somente** quando `outcome === "accepted"` **e**
`ordinal(resposta) < ordinal(tier vigente)`. Resposta de ordinal igual ou maior
grava sem flag; `declined`/`absent`/`timeout`/`unavailable`/`failed` nao
emitem escrita nenhuma (I-3), logo **nenhum desfecho degradado rebaixa o
tier** — os defaults seguros nao sao rebaixamento. Contrato completo em
`contracts/mcp-tool-collect-optins.md` §Invariante contratual C-2.

---

## Entity: RespostaDeOptIn (camada 2 — NOVA, aditiva)

**[PROPOSTA — a validar na implementacao]**

Materializa a entidade conceitual da spec ("qual campo, qual canal, qual
desfecho, qual valor final aplicado"). Vive em `.optin_responses[]`, array
top-level, **append-only**, uma entrada por campo por execucao.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| `field` | enum | `atomic_commit` \| `roadmap_mode` \| `delivery_tier` | Identifica o opt-in |
| `channel` | enum | `structured` \| `prose` \| `inherited` | Canal que produziu a resposta (FR-004); `inherited` = reabertura (`/feature-00c --reopen`, issue #192): nenhum dialogo ocorreu, valor copiado do round anterior |
| `outcome` | enum | `accepted` \| `declined` \| `absent` \| `timeout` \| `unavailable` \| `failed` | Ver tabela de desfechos abaixo |
| `applied_value` | string | valor final gravado, serializado (`"true"`, `"false"`, token do tier) | Espelha o que foi escrito na camada 1 |
| `recorded_at` | string | ISO 8601 UTC | Timestamp do registro |
| `reason` | string \| null | opcional, saneado | Diagnostico curto em `failed`; em `inherited` sem registro-fonte, explica que o valor veio de `.atomic_commit_enabled`; `null` nos demais |
| `inherited_from` | string \| null | so em `channel: "inherited"` | Rotulo do round de origem (`rounds/<label>`, ex. `r01`); ausente/`null` nos demais canais |

### Primitiva de escrita e comportamento por backend

Os 3 helpers de opt-in escrevem **apenas a camada 1**; nenhum deles conhece
`.optin_responses[]`. A escrita da camada 2 usa a primitiva generica ja
existente, **sem script novo**:

```
state-rw.sh set --state-dir <SD> --field '.optin_responses' --value <json-array>
```

(append feito lendo `.optin_responses // []` e reescrevendo o array — mesmo
padrao ja usado por `.events[]` na instrumentacao de camada B.)

**Sob backend SQLite** o campo nao tem coluna relacional e cai no catch-all
`execution.extra_fields`, reconciliado de volta ao documento no `read`.
Precedente VERIFICADO e identico: `.suggestions` — `_state-rw-db.sh:25-37`
("via o catch-all `execution.extra_fields` (JSON object), reconciliado de volta
ao documento no `read`. Nenhum dado e perdido; apenas nao ganha tratamento
relacional (sem FK/CHECK) enquanto o gap nao fecha"), com o fechamento parcial
de `state-db-runtime-parity` lote 2.4 / dec-052 registrando `.suggestions` nesse
mesmo catch-all.

Consequencia: **nenhuma edicao** a `_state-rw-db.sh` e necessaria, e o
Principio II segue PASS (nenhum script POSIX novo, nenhuma dep nova). O custo
aceito e o mesmo de `.suggestions`: sem FK/CHECK relacional para o campo novo.

**[PROPOSTA — a validar na implementacao]**: confirmar empiricamente o
round-trip `set` → `read` de `.optin_responses` sob `state.db` antes de
depender dele (cenario do `quickstart.md` Scenario 8).

### Chave natural

`(execution, field)` — **um registro VIGENTE** por campo por execucao.
Consequencia direta de FR-011/FR-008: a presenca de um registro **terminal**
para `field` e o sinal de "ja respondido, NAO re-perguntar".

#### Registros terminais x nao-terminais (correcao do gate owasp-security, M6)

O array e append-only, e o caminho degradado de
`contracts/optin-capture-order.md` §3.3(b) grava **dois** registros para o
mesmo `field`: primeiro `failed`/`unavailable` (canal `structured`), depois o
resultado da prosa (canal `prose`). Sem regra de precedencia, "ja respondido"
fica ambiguo — o campo poderia travar no default ou sofrer dupla escrita.

**Regra R-1 (precedencia)**: vale o registro **mais recente** para o `field`.

**Regra R-2 (terminalidade)**: `unavailable` e `failed` sao **NAO-terminais**
para efeito da Invariante I-1 — sinalizam "o mecanismo nao conseguiu
perguntar", nao "o operador respondeu". Todos os demais (`accepted`,
`declined`, `absent`, `timeout`) sao **terminais**.

Consequencia pratica:

| Ultimo registro do `field` | Re-perguntar? | Por que |
|----------------------------|---------------|---------|
| `accepted` / `declined` / `absent` / `timeout` | **nao** | houve resposta ou resolucao legitima (FR-011) |
| `unavailable` / `failed` | **sim, uma vez, pela prosa no pai** | o operador nunca chegou a ser perguntado de fato (FR-005) |

**Regra R-3 (anti-loop)**: a re-pergunta por prosa acontece **no maximo uma
vez** por campo por execucao. Se o registro mais recente ja tem
`channel: "prose"`, o campo esta encerrado qualquer que seja o `outcome` —
garante FR-007/SC-002 (nunca travar) mesmo se a prosa tambem falhar.

**Regra R-4 (heranca em reabertura, issue #192)**: uma execucao criada por
`/feature-00c --reopen` NAO coleta o opt-in — herda o valor do round
anterior (feature-reopen FR-022). O command pai grava, logo apos o `init`,
UM registro `channel: "inherited"` com `applied_value` = valor herdado,
`outcome` copiado do registro mais recente do round anterior (ou `absent`
com `reason` quando o round anterior nao tem registro — o evento de decisao
nao e observavel, so o valor), e `inherited_from` = rotulo do round. Esse
registro satisfaz a Invariante I-2 sem dialogo; `collect_optins` NAO e
invocado pelo orquestrador (a linha do ramo estruturado nao e injetada no
spawn) e, se for, devolve `reused` como para qualquer registro existente.
`channel: "prose"` NUNCA e gravado numa reabertura: afirmaria um dialogo que
nao ocorreu (Principio VI).

### Enum `outcome` — desfechos e origem do sinal

| `outcome` | Origem do sinal (como e detectado) | Valor aplicado | Aviso em stderr? |
|-----------|-------------------------------------|----------------|------------------|
| `accepted` | `ElicitResult.action === "accept"` + campo presente em `content` | resposta do operador | nao |
| `declined` | `ElicitResult.action === "decline"` | default seguro | nao |
| `absent` | `ElicitResult.action === "cancel"` (**envelope retornado**) | default seguro | nao |
| `timeout` | `McpError` code `RequestTimeout` (**excecao lancada**) | default seguro | nao |
| `unavailable` | capability `elicitation` ausente **antes** da chamada | default seguro | **nao** (FR-009: nunca esteve disponivel) |
| `failed` | qualquer outro erro **durante** a chamada | default seguro | **sim, exatamente 1 linha** (FR-009) |

> **Discriminador `absent` x `timeout`** (research.md Decision 6): envelope
> **retornado** vs excecao **lancada**. Sao caminhos de codigo distintos no SDK
> — nenhuma medicao de tempo decorrido participa da classificacao.

> **Discriminador `unavailable` x `failed`** (FR-009, SC-005): `unavailable` e
> detectado **antes** de emitir a requisicao (o pre-requisito nunca esteve
> satisfeito) → silencio. `failed` ocorre **depois** de emitida (o pre-requisito
> estava satisfeito e a chamada quebrou) → uma unica linha de aviso.

### Relationships

- `RespostaDeOptIn` 1:1 `OptInValorEfetivo` por `field` — o registro de
  auditoria e o **espelho** da escrita, nunca a fonte lida por consumidores.
  Nenhum consumidor existente (`is-enabled`, `get`) passa a ler
  `.optin_responses[]`.
- `RespostaDeOptIn` N:1 `Execucao` — todos os registros pertencem a uma unica
  execucao, identificada pelo `state-dir`.

### State Transitions

Cada `field` chega a um estado terminal em **no maximo dois** passos (o segundo
so existe no ramo degradado de FR-005):

```
(sem registro)
      │
      ├──► accepted | declined | absent | timeout        [TERMINAL — encerra o campo]
      │
      └──► unavailable | failed  (canal structured)      [PROVISORIO]
                  │
                  └──► accepted | declined | absent      [TERMINAL — canal prose, no pai]
                       (qualquer outcome com channel=prose encerra — regra R-3)
```

**Invariante I-1 (FR-011)**: existindo registro **terminal** para `field` (por
R-2), o formulario estruturado MUST NOT ser invocado de novo para aquele campo
— vale para retomadas e para qualquer disparo repetido na mesma execucao.

> **Recorte de FR-011**: a letra do FR-011 diz "se existir uma
> `RespostaDeOptIn` registrada, MUST reusar o valor ja registrado". Lida sem
> recorte, ela proibiria a propria captura por prosa do ramo degradado — que
> FR-005 **exige**. O recorte e R-2: `unavailable`/`failed` nao sao
> `RespostaDeOptIn` no sentido de FR-011 (nao houve resposta), sao registro de
> **tentativa frustrada**. → **Delta de spec recomendado**: tornar esse recorte
> explicito em FR-011.

**Invariante I-2 (FR-012)**: nenhuma onda pode ser aberta enquanto houver
`field` aplicavel ao `executionKind` corrente **sem** registro. "Aplicavel"
exclui `delivery_tier` **e** `roadmap_mode` quando `executionKind ===
"feature-00c"` (dec-083 — `roadmap_mode` e exclusivo de `agente-00c`).

**Invariante I-3 (FR-006)**: em **todo** desfecho que nao seja `accepted`, o
`applied_value` MUST ser identico ao default seguro ja gravado pela etapa (1)
do init — ou seja, nenhuma escrita na camada 1 e necessaria nesses casos.

### Retro-compatibilidade

Execucoes anteriores a esta feature nao possuem `.optin_responses`. Todo
leitor MUST usar a forma tolerante (`.optin_responses[]? // empty`,
`.optin_responses // []`), produzindo `[]` sem erro — mesmo padrao ja adotado
por `.tasks[]` / `.events[]` na feature `knowledge-db-metrics`.

---

## Campos que NAO mudam (nota anti-regressao)

Registrado porque a feature toca a **ordem** de escrita, e ordem e o vetor
classico de regressao silenciosa:

- `state-rw.sh init` continua aceitando `--atomic-commit` / `--roadmap-mode` /
  `--delivery-tier` (VERIFICADO: `state-rw.sh:371-386`). O **caminho legado**
  (prosa antes do init + flags) permanece intacto e continua sendo o caminho
  usado quando o mecanismo estruturado nao esta disponivel (FR-005).
- Nenhum default muda (FR-006): `false`, `false`, `cloud-public`.
