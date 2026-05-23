# Data Model: model-selector

A feature e **stateless por invocacao** (FR-015) — nao introduz novo
schema persistente proprio. As "entidades" abaixo sao contratos
semanticos (in-memory por chamada) + extensoes ao schema do
`state.json` ja gerenciado pelo runtime `agente-00c-runtime`.

---

## Entity: SinalDeClassificacao

Unidade do catalogo `references/sinais.md`. Representa um termo
(verbo, ferramenta ou padrao linguistico) associado a uma faixa de
complexidade com peso default.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| termo | string | NOT NULL, lowercase, min 1 char | Token literal — sem regex, sem espacos internos |
| faixa | enum | `rasa` \| `media` \| `profunda` | Faixa de complexidade associada |
| peso | integer | NOT NULL, >=1, default=1 | Peso de contribuicao ao score da faixa (operador pode customizar) |
| origem | enum | `mvp-builtin` \| `operador-local` | Opcional, marca de auditoria — informativo apenas |

**Persistencia**: arquivo markdown em
`global/skills/model-selector/references/sinais.md` (formato tabela
markdown com 3-4 colunas). Lido em modo streaming a cada invocacao
(Phase 0 / Decision 1 do `research.md`).

**Tamanho MVP**: 15 sinais (5 por faixa) — dec-004.

### Invariantes

- Termo e unico globalmente no catalogo (case-insensitive). Dois
  registros para `rode` (um rasa, um profunda) violam o contrato e o
  comportamento e indefinido — operador e responsavel pela
  consistencia ao customizar.
- Faixa e fechada e literal (3 valores). Adicionar uma 4a faixa
  exige amendment da spec (FR-003 cita 3 faixas explicitamente).
- Peso >=1 inteiro (sem fracoes — manter classificador deterministico
  e portavel; tie-break resolvido por FR-005, nao por peso fracionario).

### State Transitions

N/A — entidade imutavel por execucao. Mudancas no catalogo sao
edicoes de arquivo (FR-004), nao mutacoes em runtime.

---

## Entity: SugestaoDeModelo

Artefato emitido pela skill em cada invocacao. Representado em
memoria durante a execucao e materializado como **markdown
estruturado** no stdout da skill (Decision 4 do `research.md`).

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| modelo | enum | `haiku` \| `sonnet` \| `opus` \| `manter-atual` | Rotulo abstrato — sem versao concreta (dec-005) |
| score | integer | 0..2 (teto pratico) | Teto = 2 conforme dec-006; score 3 reservado para evolucao futura |
| alternativa | enum | `haiku` \| `sonnet` \| `opus` \| `none` | Tier-mapping de fallback (Decision 9 do research) |
| sinais_detectados | list[SinalDeClassificacao] | possivelmente vazia | Subset do catalogo que matched o input |
| justificativa | string | NOT NULL, 1..500 chars | Texto livre citando sinais decisivos |
| acao_sugerida_operador | string | NOT NULL, literal `/model <modelo>` | Comando exato para humano copiar (FR-002 + User Story 2) |

**Persistencia**: stdout-only. Apos consumo pelo orquestrador, e
**transcrita** como Decisao auditavel em `state.decisoes` (ver
`DecisaoDeAceite` abaixo) e como contador agregado em
`metricas_acumuladas.model_selector` (ver "Extensao do state.json").

### Invariantes

- `modelo == manter-atual` implica `alternativa == none` (no-op nao
  tem fallback).
- `modelo == opus` implica `alternativa == none` (ja no topo do
  tier-mapping).
- `score == 0` implica `modelo == manter-atual` (zero confianca
  forca conservadorismo — Decision 7 do research + FR-005).
- `sinais_detectados` vazio implica `score == 0` E
  `modelo == manter-atual` (sem sinal nao ha base para sugerir
  baratear).
- `justificativa` MUST citar literalmente ao menos 1 termo presente
  em `sinais_detectados`, OU citar literalmente "input curto demais
  para classificacao confiavel" no caso de Decision 7.

### State Transitions

N/A — entidade in-flight emitida e consumida na mesma chamada.

---

## Entity: DecisaoDeAceite

Registro auditavel persistido em `state.decisoes` (schema ja
existente do runtime) quando a sugestao e invocada por orquestrador
autonomo (agente-00c ou feature-00c). NAO e nova tabela — e
*especializacao* do schema de Decisao.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| id | string | gerado pelo runtime (formato `dec-NNN`) | PK; auto-incrementado por `state-decisions.sh register` |
| onda_id | string | FK -> ondas[].id | Onda corrente quando a sugestao chegou |
| timestamp | ISO-8601 | NOT NULL, UTC | Auto-set pelo runtime |
| etapa | string | NOT NULL | Etapa do pipeline quando a sugestao foi feita |
| agente | string | NOT NULL | Geralmente "agente-00c-orchestrator" ou "agente-00c-feature-orchestrator" |
| contexto | string | NOT NULL, MUST conter "model-selector" | Cita literalmente "sugestao do model-selector" para audit grep |
| opcoes_consideradas | list[string] | NOT NULL, len>=2 | Inclui obrigatoriamente "aceitar-sugestao" e "rejeitar-sugestao" + opcional "ja-no-modelo-no-op" |
| escolha | string | NOT NULL | Uma das `opcoes_consideradas`; deriva o `por_resultado.*` em metricas |
| justificativa | string | NOT NULL, >=20 chars se score=3 | Reusa `SugestaoDeModelo.justificativa` quando aceita; quando rejeita, cita sinal contrario (FR-009) |
| score_justificativa | integer | 0..3 | Score da DECISAO (nao da sugestao); pode ser 3 com `evidencia` valida (FR-EVI-001) |
| evidencia | string\|null | >=20 chars se score=3 | Comando+output literal; null se score <3 |
| referencias | list[string] | opcional | Aponta para input classificado e/ou regiao do briefing/constitution que justifica |
| artefato_originador | string\|null | opcional | Path ou hash do output da skill que originou a sugestao |

**Persistencia**: `state.decisoes[]` no `state.json` da execucao do
agente-00c/feature-00c, gerenciado por
`global/skills/agente-00c-runtime/scripts/state-decisions.sh
register`.

### Invariantes herdadas do runtime

- Score 3 EXIGE `evidencia` com comando+output literal (FR-EVI-001 do
  runtime; trava em `state-decisions.sh register`).
- Score 3 NAO e atingivel pela heuristica auto-invocada (dec-006) —
  apenas o orquestrador, ao rejeitar sugestao com sonda empirica,
  pode atingir score 3 nesta DecisaoDeAceite.

### State Transitions

```
[sugestao emitida]
        |
        v
[orquestrador avalia]
   /     |       \
aceita rejeita  ja-no-modelo (no-op)
   |     |         |
   v     v         v
  state.decisoes (5 campos obrigatorios + score + evidencia opcional)
        |
        v
  metricas_acumuladas.model_selector.por_resultado.<resultado>++
```

---

## Extensao do `state.json` (FR-011)

Esta feature **adiciona uma chave nova** sob
`metricas_acumuladas`. Compativel com schema existente — campos
novos sao opcionais para o validador
(`agente-00c-runtime/scripts/state-validate.sh`).

```json
{
  "metricas_acumuladas": {
    "ondas_total": "<int>           // ja existia",
    "decisoes_total": "<int>        // ja existia",
    "...": "...                     // demais campos existentes",
    "model_selector": {
      "sugestoes_total": 0,
      "por_modelo_sugerido": {
        "haiku": 0,
        "sonnet": 0,
        "opus": 0,
        "manter-atual": 0
      },
      "por_resultado": {
        "aceitas": 0,
        "rejeitadas": 0,
        "no_op_ja_no_modelo": 0
      },
      "ultima_invocacao_iso": null
    }
  }
}
```

### Invariantes do contador

- `sugestoes_total ==
   sum(por_modelo_sugerido.values()) ==
   sum(por_resultado.values())` (igualdade dupla; violacao indica
  bug).
- `por_resultado.no_op_ja_no_modelo` so incrementa quando o
  orquestrador detecta que ja esta no modelo sugerido (edge case 2
  da spec).
- `ultima_invocacao_iso` e sempre ISO-8601 UTC; null apenas quando
  `sugestoes_total == 0`.
- Inicializacao "lazy" — o objeto so e criado quando a primeira
  sugestao chega; ate la, nem o campo existe (compat retroativa
  com state.json gerados antes desta feature).

---

## Relacionamentos

```
SinalDeClassificacao  --(N, lookup)--> SugestaoDeModelo
                                              |
                                              v
                                       DecisaoDeAceite
                                              |
                                              v
                            metricas_acumuladas.model_selector
                                              |
                                              v
                                       scripts/report.sh
                                              |
                                              v
                                      tabela markdown agregada
```

- **N:1** — Muitos `SinalDeClassificacao` podem matchear UMA
  `SugestaoDeModelo` (lista `sinais_detectados`).
- **1:0..1** — Uma `SugestaoDeModelo` gera **no maximo uma**
  `DecisaoDeAceite` (so quando invocada por orquestrador; invocacoes
  manuais do operador humano nao geram `DecisaoDeAceite`).
- **N:1 (agregacao)** — Muitas `DecisaoDeAceite` agregam para UM
  registro em `metricas_acumuladas.model_selector` (contador unico
  por execucao do state.json).

---

## Validacao e integridade

- Catalogo `references/sinais.md` validado por
  `tests/cstk/test_model_selector_*.sh` (Decision 8 do research).
  Schema check: header markdown, 3 colunas obrigatorias
  (`termo|faixa|peso`), faixa ∈ {rasa, media, profunda}, peso>=1.
- `SugestaoDeModelo` validada pelas invariantes acima ao ser
  emitida (skill aborta com exit 2 se inconsistente — bug interno).
- `DecisaoDeAceite` validada pelo proprio
  `state-decisions.sh register` (FR-EVI-001 + 5 campos obrigatorios)
  — sem responsabilidade dupla.
- Integridade do `state.json` (incluindo
  `metricas_acumuladas.model_selector`) coberta pelo SHA-256 do
  arquivo, gerenciado por `state-rw.sh sha256-update` (herdado do
  runtime).
