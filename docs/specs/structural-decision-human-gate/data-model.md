# Data Model: Decisoes estruturais exigem gate humano

Modelo de dados da feature `structural-decision-human-gate`. Todas as mudancas
sao **aditivas**: nenhum campo existente muda de tipo, nome ou semantica
(FR-005, FR-013).

Legenda de rotulo: `[EXISTENTE]` = campo ja no schema atual, reproduzido aqui
por contexto; `[NOVO]` = introduzido por esta feature.

## Entity: Decisao (`decision` / `.decisions[]`)

Entidade auditavel do Principio I. Colunas atuais verificadas em
`plugins/cstk/skills/agente-00c-runtime/references/state-db-schema.sql:135-165`.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| id | TEXT | PK, `dec-NNN` | [EXISTENTE] gerado por subquery na propria transacao |
| execution_id | TEXT | NOT NULL, FK `execution(id)` | [EXISTENTE] |
| wave_id | TEXT | FK `wave(id)`, nullable | [EXISTENTE] NULL = "init" |
| timestamp | TEXT | NOT NULL, ISO 8601 | [EXISTENTE] |
| agent | TEXT | NOT NULL, length > 0 | [EXISTENTE] identifica o decisor |
| stage | TEXT | NOT NULL, length > 0 | [EXISTENTE] etapa SDD |
| context | TEXT | NOT NULL, length >= 20 | [EXISTENTE] |
| options_considered | TEXT | NOT NULL, JSON array, length >= 1 | [EXISTENTE] |
| choice | TEXT | NOT NULL, length > 0 | [EXISTENTE] |
| rationale | TEXT | NOT NULL, length >= 20 | [EXISTENTE] |
| justification_score | INTEGER | NULL ou 0..3 | [EXISTENTE] |
| evidence | TEXT | NULL; obrigatorio >= 20 se score = 3 | [EXISTENTE] |
| references | TEXT | NULL, JSON array | [EXISTENTE] nome citado entre aspas no DDL |
| originating_artifact | TEXT | NULL | [EXISTENTE] usado pelo par de invalidacao |
| **decision_class** | TEXT | NULL; quando nao-NULL ∈ {`estrutural`,`operacional`} | **[NOVO]** NULL = nao declarada (legado, FR-013) |
| **structural_axis** | TEXT | NULL; quando nao-NULL ∈ enum de eixos | **[NOVO]** obrigatorio quando `decision_class = 'estrutural'` |

### Enum: `decision_class`

| Valor | Significado |
|-------|-------------|
| `estrutural` | Fixa um dos eixos da tabela de Eixo Estrutural para o projeto ou feature. Sujeita a FR-003. |
| `operacional` | Qualquer outra decisao. Regua de score atual integral (FR-005). |
| (ausente / NULL) | Nao declarada. Unico valor possivel em registros anteriores a esta feature (FR-013). Leitores tratam como "nao declarada", nunca como `operacional`. |

### Enum: `structural_axis`

Lista fechada nesta versao, materializada em
`plugins/cstk/skills/agente-00c-runtime/references/structural-axis-map.txt`
(Decision 4 do research.md). Derivada da tabela ratificada na spec.

| Token | Eixo |
|-------|------|
| `linguagem-runtime` | Linguagem / runtime e versao minima |
| `stack-frameworks` | Stack e frameworks principais; reuso de legado vs reescrita |
| `arquitetura` | Arquitetura de alto nivel (monolito / hibrido / servicos) |
| `persistencia` | Persistencia principal |
| `ambiente-alvo` | Ambiente de execucao onde o entregavel roda |
| `tier-entrega` | Tier de entrega (ja coberto por `delivery-tier`, INV-4) |

### Regras de integridade (aplicadas no helper e na tool MCP, nao como CHECK)

As regras abaixo NAO viram `CHECK` no DDL: a coluna e adicionada por
`ALTER TABLE ADD COLUMN` (Decision 3), e SQLite nao permite acrescentar CHECK a
tabela existente sem recriar. A validacao vive nas duas portas de escrita, que
ja e o padrao da trava de constitution-conflict existente.

| Regra | Enunciado | FR |
|-------|-----------|----|
| R1 | `options_considered` contendo token da familia de bloqueio humano => `decision_class` obrigatoria; ausente = recusa sem gravar nada | FR-002 |
| R2 | `decision_class = 'estrutural'` + `agent` nao-humano => exige `choice` = token de bloqueio humano E `justification_score = 0`; qualquer outra combinacao e recusada citando classe, eixo e caminho correto | FR-003 |
| R3 | `decision_class = 'estrutural'` => `structural_axis` obrigatorio e dentro do enum | FR-003 |
| R4 | `decision_class = 'operacional'` ou ausente => nenhuma regra nova; comportamento identico ao atual | FR-005, FR-013 |
| R5 | Paridade: R1..R4 identicas no helper POSIX e na tool MCP `record_decision`, com erro tipado | FR-004 |

### Familia de token de bloqueio humano

Reconhecida por prefixo, sobre os itens **string** de `options_considered`
(itens objeto `{rotulo, descricao}` sao avaliados pelo seu `rotulo`):
`bloqueio-humano*` e `pause-humano`. `pause-humano` e o token literal ja usado
pela sequencia de constitution-conflict documentada em `state-decisions.sh`.

### State Transitions

A Decisao e append-only (Principio I) — nao ha transicao de estado no registro.
O que transiciona e a resolucao do bloqueio associado:

```
decisao estrutural registrada (choice = bloqueio-humano, score 0)
  -> BloqueioHumano pendente
  -> operador responde via /feature-00c-resume ou /agente-00c-resume
  -> Decisao subsequente com agent = operador (consentimento rastreavel)
  -> eixo considerado decidido: nao re-perguntado nesta execucao
```

### Relationships

- `Decisao` 1:N `BloqueioHumano` via `decision_id` (relacao [EXISTENTE], ja
  validada por `state-validate.sh` regra 9).
- `Decisao (estrutural)` 0..1:1 `Item a Definir (briefing)` via correspondencia
  de eixo — relacao **derivada em leitura**, nunca persistida como FK: o
  briefing nao e entidade do `state.db`.

## Entity: Item a Definir (briefing)

Linha da tabela `## Itens a Definir` do briefing. **Nao e persistida** em
`state.json` nem em `state.db`: e extraida sob demanda pelo helper
`briefing-items.sh` a cada consulta (fonte da verdade permanece o arquivo).

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| item | string | nao-vazio | Texto da coluna `Item` |
| dimensao | string | pode ser vazio | Texto da coluna `Dimensao` |
| impacto | string | token inicial casado case-insensitive | So `Alto` e consumido (FR-007) |

### Regras de parsing (tolerancia deliberada — Decision 5 do research.md)

| Regra | Comportamento |
|-------|---------------|
| P1 | Heading `## Itens a Definir` casado ignorando caixa e espacos extras |
| P2 | Linha de cabecalho (`\| Item \| Dimensao \| Impacto \|`) e separadora (`\|---\|`) descartadas |
| P3 | Impacto casado pelo **token inicial** da celula — cobre `Alto — ...`, `Medio (...)`, `Baixo hoje, sobe...` observados em briefings reais |
| P4 | Heading presente sem tabela reconhecivel (ex.: lista numerada) => zero itens + aviso em stderr, exit 0 |
| P5 | Briefing ausente/ilegivel => zero itens + aviso, exit 0 — nunca falha a onda |
| P6 | Aceita briefing canonico (`docs/briefing.md`) e legado (`docs/01-briefing-discovery/briefing.md`) — a resolucao do path e do chamador |

## Entity: Eixo Estrutural (tabela de referencia)

Arquivo `references/structural-axis-map.txt`, lido por parser POSIX-puro sem jq.
Formato de linha de dados: `eixo|rotulo`. Primeira linha declara a versao do
mapa, no mesmo padrao de `tier-gate-map.txt` e `phase-model-map.txt`.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| eixo | string | token kebab-case, unico | Chave; e o valor gravado em `structural_axis` |
| rotulo | string | nao-vazio | Texto legivel usado na mensagem de recusa e no relatorio |

Regras de lookup: linhas iniciadas por `#` e linhas vazias sao ignoradas; eixo
nao listado e **rejeitado** (exit 2), diferente do fail-safe de
`tier-gate-map.txt` — aqui a direcao segura e recusar um eixo desconhecido, nao
aceita-lo, porque aceitar permitiria burlar o enum por texto livre.

## Entity: Anomalia de Governanca (derivada, nunca gravada)

Nao possui armazenamento. E um predicado avaliado em tempo de leitura por
`report.sh` e por `review-task`, no mesmo padrao ja usado para detectar Decisao
INVALIDADA (par derivado, sem campo de estado na linha original).

**Predicado**: `decision_class = 'estrutural'` **E** `choice` nao pertence a
familia de token de bloqueio humano **E** `agent` nao e humano rastreavel.

| Field | Type | Origem |
|-------|------|--------|
| decision_id | string | `.decisions[].id` |
| structural_axis | string | `.decisions[].structural_axis` |
| agent | string | `.decisions[].agent` |
| choice | string | `.decisions[].choice` |

Esperado em execucao saudavel posterior a esta feature: **contagem 0**
(SC-002). Contagem > 0 indica estado legado ou bypass, e e reportada — nunca
corrigida automaticamente (spec, Edge Cases: nao retroativa).

## Entity: `decisions` na knowledge.db (indice derivado)

Tabela do indice global `~/.claude/cstk/knowledge.db`
(`cli/lib/recall.sh:435-453`). Colunas atuais: `id, project, feature, wave,
execution_id, source_ts, source_id, agent, stage, choice, options, score,
context, rationale, evidence, ingested_at`.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| **decision_class** | TEXT | NULL | **[NOVO]** espelha a coluna do state |
| **structural_axis** | TEXT | NULL | **[NOVO]** espelha a coluna do state |

`RECALL_SCHEMA_VERSION`: `14` -> `15`. Migracao aditiva idempotente pelo padrao
ja existente naquele arquivo (`PRAGMA table_info` + `ALTER TABLE ADD COLUMN`),
aplicada aos dois caminhos de ingestao (JSON->SQL e SQL->SQL), que compartilham
o mesmo tuple de colunas. Base inteiramente reconstruivel via `--reindex`.

Nenhum dos dois campos novos e texto livre: sao tokens de enum fechado, logo
**nao** passam por `recall_scrub` (mesmo tratamento de `choice`, que ja nao
passa). O eixo nunca carrega segredo por construcao.
