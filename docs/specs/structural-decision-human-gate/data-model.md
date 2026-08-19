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
| **human_consent_block_id** | TEXT | NULL; quando nao-NULL, id de `human_block` da MESMA execucao com `status = 'respondido'` | **[NOVO]** unico portador de consentimento humano (FR-003, emenda dec-024). Nao e FK no DDL — vide R6 |

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
| R2 | `decision_class = 'estrutural'` **sem consentimento humano valido** (vide R6) => exige `choice` = token de bloqueio humano E `justification_score = 0`; qualquer outra combinacao e recusada citando classe, eixo e caminho correto. Com consentimento valido, a regua de score volta a ser a atual | FR-003 |
| R3 | `decision_class = 'estrutural'` => `structural_axis` obrigatorio e dentro do enum | FR-003 |
| R4 | `decision_class = 'operacional'` ou ausente => nenhuma regra nova; comportamento identico ao atual | FR-005, FR-013 |
| R5 | Paridade: R1..R4 e R6 identicas no helper POSIX e na tool MCP `record_decision`, com erro tipado | FR-004 |
| R6 | `human_consent_block_id` nao-NULL => o bloqueio MUST existir na execucao corrente, ter `status = 'respondido'` **e** ter `subject_key = 'axis:' \|\| structural_axis` da Decisao. Ausente, de outra execucao, `aguardando`, ou de assunto divergente = recusa sem gravar nada. A verificacao le o estado no momento do registro — nunca confia no valor apresentado | FR-003, FR-012 |

### Predicado de consentimento humano (normativo)

Definicao unica, usada identicamente pela trava de registro (R2), pelo relatorio
e por `review-task`:

```
consentimento_humano(D) :=
      D.human_consent_block_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM human_block B
               WHERE B.id           = D.human_consent_block_id
                 AND B.execution_id = D.execution_id
                 AND B.status       = 'respondido'
                 AND B.subject_key  = 'axis:' || D.structural_axis)
```

A ultima condicao — o **vinculo de assunto** — nao e detalhe: sem ela o
consentimento seria um cheque em branco. Um bloqueio respondido sobre
`linguagem-runtime` autorizaria uma decisao sobre `persistencia`, porque a regra
so perguntaria "existe algum bloqueio respondido?". E o padrao classico de
confused deputy (A01 / ASI03): a autorizacao existe, mas para outra coisa.
Detectado pelo gate de seguranca sobre a propria emenda e corrigido em
`dec-030`.

Consequencia de projeto: um bloqueio que serve de consentimento para decisao
estrutural **precisa** ter `subject_key = axis:<eixo>`. Bloqueios de outra
natureza (marco de retrospectiva, escalada de gate, item de briefing) tem outro
prefixo ou `subject_key` NULL e por isso nunca podem ser citados como
consentimento estrutural — o que e exatamente o desejado.

O campo `agent` **nao participa** do predicado, nem como condicao, nem como
desempate. Ele permanece exibido no relatorio como informacao de proveniencia.

**Racional da emenda (dec-024, resposta ao `block-001`)**: `agent` e `TEXT NOT
NULL` com unica restricao `length(agent) > 0` — texto livre, escrito pelo mesmo
agente cuja autoridade se pretendia verificar. `human_block.status`, ao
contrario, e enum fechado por `CHECK (status IN ('aguardando','respondido'))` e
so transiciona para `respondido` pelo caminho de resposta do operador. Ancorar o
predicado no segundo troca uma auto-declaracao por um evento verificavel.

**Por que nao e FK no DDL**: a coluna e adicionada por `ALTER TABLE ADD COLUMN`
(Decision 3) e SQLite nao aceita acrescentar constraint de chave estrangeira a
tabela existente sem recria-la; alem disso a FK sozinha nao expressaria a
condicao que importa (`status = 'respondido'` no momento do registro). A
verificacao vive nas duas portas de escrita, como as demais regras.

### Residual do consentimento (declarado)

Mesmo vinculado ao eixo, o consentimento carrega dois residuais que nenhuma
regra de schema alcanca — registrados para nao serem descobertos tarde:

| Residual | Descricao | Por que nao vira regra |
|----------|-----------|------------------------|
| Qualidade da pergunta | O consentimento e tao informado quanto a `question` que o agente escreveu. Um bloqueio de assunto correto porem redigido de forma vaga produz um `respondido` tecnicamente valido | Julgar qualidade de prosa e exatamente o tipo de avaliacao que esta feature substitui por mecanismo. O contrapeso e humano: o operador le a pergunta antes de responder |
| Reuso do mesmo consentimento | Um bloqueio respondido sobre um eixo autoriza **N** decisoes daquele eixo na mesma execucao, nao apenas uma | E o comportamento desejado: o eixo foi decidido. Exigir um bloqueio por decisao transformaria o gate em ruido e violaria SC-006 |

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
  -> BloqueioHumano pendente (status = aguardando, subject_key = <chave>)
  -> operador responde via /feature-00c-resume ou /agente-00c-resume
  -> BloqueioHumano status = respondido            <- unico evento de consentimento
  -> Decisao subsequente com human_consent_block_id = <block-NNN>
     (aceita escolha concreta e score > 0, pois R6 e satisfeita)
  -> assunto considerado decidido: nao re-perguntado nesta execucao
     (dedup por subject_key sobre bloqueios respondidos)
```

Note que o consentimento **nao** e a Decisao do operador: e a transicao do
bloqueio para `respondido`. A Decisao subsequente apenas **cita** esse evento.
Quem a registra (agente ou operador) e irrelevante para a trava.

### Relationships

- `Decisao` 1:N `BloqueioHumano` via `decision_id` (relacao [EXISTENTE], ja
  validada por `state-validate.sh` regra 9) — aponta da Decisao que **abriu** o
  bloqueio para o bloqueio.
- `BloqueioHumano` 1:N `Decisao` via `human_consent_block_id` (**[NOVO]**,
  sentido inverso) — aponta da Decisao que **consome** o consentimento para o
  bloqueio que o produziu. Os dois sentidos coexistem e nao se confundem: o
  primeiro registra "esta pergunta nasceu daqui", o segundo "esta escolha foi
  autorizada ali".
- `BloqueioHumano` 0..1:1 `Item a Definir (briefing)` via `subject_key` —
  igualdade exata de string. Relacao **derivada em leitura**, nunca persistida
  como FK: o briefing nao e entidade do `state.db`.

## Entity: BloqueioHumano (`human_block` / `.human_blocks[]`)

Colunas atuais verificadas em
`plugins/cstk/skills/agente-00c-runtime/references/state-db-schema.sql:170-187`.
Reproduzidas aqui apenas as relevantes a esta feature.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| id | TEXT | PK, `block-NNN` | [EXISTENTE] |
| execution_id | TEXT | NOT NULL, FK `execution(id)` | [EXISTENTE] |
| decision_id | TEXT | NOT NULL, FK `decision(id)` | [EXISTENTE] Decisao que abriu o bloqueio |
| status | TEXT | NOT NULL, `CHECK (status IN ('aguardando','respondido'))` | [EXISTENTE] enum fechado — base do predicado de consentimento |
| human_answer | TEXT | NULL; preenchido na resposta | [EXISTENTE] |
| answered_at | TEXT | NULL quando `aguardando`, NOT NULL quando `respondido` (CHECK) | [EXISTENTE] |
| **subject_key** | TEXT | NULL; quando nao-NULL, token kebab-case com prefixo de origem | **[NOVO]** chave de assunto (FR-008) |

### Enum de prefixo de `subject_key`

Prefixo obrigatorio, para que chaves de origens distintas nunca colidam:

| Prefixo | Origem | Exemplo |
|---------|--------|---------|
| `briefing-item:` | Item de impacto `Alto` da tabela "Itens a Definir" | `briefing-item:linguagem-e-runtime-do-backend` |
| `axis:` | Eixo estrutural perguntado fora do briefing | `axis:linguagem-runtime` |

### Derivacao da chave (funcao pura, FR-008)

Para `briefing-item:`, o sufixo e derivado **exclusivamente** do texto da coluna
`Item`, por `briefing-items.sh`, na seguinte ordem fixa: caixa baixa; qualquer
caractere fora de `[a-z0-9]` vira `-`; sequencias de `-` colapsam em um; `-` das
pontas removidos; truncagem do slug em 48 caracteres; e sufixo `-<checksum>`,
onde `<checksum>` e o valor de `cksum` sobre o texto **integral** ja normalizado.
Sem lista de sinonimos, sem stemming, sem consulta a estado — a mesma entrada
produz sempre a mesma chave.

**Por que o checksum, e nao so a truncagem** (finding do gate de seguranca sobre
a emenda): dois itens longos que compartilhem os primeiros 48 caracteres apos a
normalizacao colapsariam na mesma chave. O efeito da colisao seria **fail-open**
— o segundo item seria considerado "ja decidido" por causa da resposta dada ao
primeiro, e jamais perguntado. Como o checksum cobre o texto inteiro, itens
distintos so colidem se colidirem em ambos os componentes.

Declarado com honestidade: `cksum` e CRC, nao hash criptografico. Nao e
resistente a colisao **adversarial** — quem controla o texto do briefing pode,
com esforco, construir duas entradas colidentes. Isso e aceito porque o briefing
e artefato humano ratificado e a chave e um mecanismo de deduplicacao dentro de
uma execucao, nao uma fronteira de autorizacao (a fronteira e o `status` do
bloqueio, vide R6). Para colisao acidental entre itens escritos de boa-fe, a
combinacao slug+CRC e folgada.

Consequencia aceita e declarada: reescrever o texto do item no briefing produz
chave nova e **re-pergunta** o item (spec, Edge Cases). A alternativa —
reconhecer o item reescrito como "o mesmo" — exigiria julgamento sobre prosa,
que e exatamente o modo de falha que esta chave existe para eliminar.

### Dedup do FR-008 (leitura)

```
ja_decidido(chave) :=
  EXISTS (SELECT 1 FROM human_block
           WHERE execution_id = <execucao corrente>
             AND subject_key  = <chave>
             AND status       = 'respondido')
```

Retrocompatibilidade: bloqueios anteriores a esta feature tem `subject_key`
NULL e nunca casam com chave alguma — nem como dedup, nem como consentimento — logo nao suprimem pergunta nenhuma. A
direcao segura da degradacao e **perguntar de novo**, nunca presumir decidido.

## Entity: Item a Definir (briefing)

Linha da tabela `## Itens a Definir` do briefing. **Nao e persistida** em
`state.json` nem em `state.db`: e extraida sob demanda pelo helper
`briefing-items.sh` a cada consulta (fonte da verdade permanece o arquivo).

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| item_key | string | token derivado (vide §Derivacao da chave) | **[NOVO nesta emenda]** primeira coluna da saida; e o sufixo do `subject_key` |
| item | string | nao-vazio | Texto da coluna `Item` |
| dimensao | string | pode ser vazio | Texto da coluna `Dimensao` |
| impacto | string | token inicial casado case-insensitive | So `Alto` e consumido (FR-007) |

### Regras de parsing (tolerancia deliberada — Decision 5 do research.md)

| Regra | Comportamento |
|-------|---------------|
| P1 | Heading `## Itens a Definir` casado ignorando caixa e espacos extras |
| P2 | Linha de cabecalho (`\| Item \| Dimensao \| Impacto \|`) e separadora (`\|---\|`) descartadas |
| P3 | Impacto casado pelo **token inicial** da celula — cobre `Alto — ...`, `Medio (...)`, `Baixo hoje, sobe...` observados em briefings reais |
| P4 | Heading presente sem tabela reconhecivel (ex.: lista numerada) => zero itens + aviso em stderr, exit 0, `STATUS=tabela-irreconhecivel` |
| P5 | Briefing ausente/ilegivel => zero itens + aviso, exit 0, `STATUS=briefing-ausente` — nunca falha a onda |
| P6 | Aceita briefing canonico (`docs/briefing.md`) e legado (`docs/01-briefing-discovery/briefing.md`) — a resolucao do path e do chamador |
| P7 | Toda celula e **saneada antes de compor a linha de saida**: NUL, TAB, CR e LF removidos e whitespace colapsado. Sem isso uma celula contendo TAB forjaria uma coluna a mais na saida TSV (finding L1 do gate de seguranca) |

### Distincao obrigatoria: "sem itens" nao e "sem briefing" (finding M2)

O parser MUST emitir, como **ultima linha de stdout**, um registro de estado no
formato `STATUS<TAB><token>`, com `<token>` em enum fechado:

| `STATUS` | Significado | Reacao esperada do gate FR-008 |
|----------|-------------|--------------------------------|
| `ok` | Tabela lida com sucesso | Bloqueia se houver itens `Alto`; segue se nao houver |
| `sem-itens-alto` | Tabela lida, nenhum item `Alto` | Segue sem bloquear |
| `tabela-irreconhecivel` | Heading presente, tabela nao parseavel | **Aviso visivel** no sumario da onda; segue |
| `briefing-ausente` | Arquivo ausente ou ilegivel | **Aviso visivel** no sumario da onda; segue |

**Por que existe**: sem esse token, "briefing ausente" e "briefing com zero itens
Alto" produzem a mesma saida (stdout vazio, exit 0) e o gate de governanca passa
silenciosamente justamente no caso em que tem menos informacao — fail-open
indistinguivel de caminho feliz. Com o token, a degradacao continua nao falhando
a onda (exigencia da spec), mas deixa de ser **invisivel**.

O helper continua com exit 0 nos quatro casos: quem decide o que fazer com o
estado degradado e o orquestrador, nao o parser.

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
familia de token de bloqueio humano **E** `consentimento_humano(D)` e falso
(vide §Predicado de consentimento humano).

O campo `agent` **nao** entra no predicado (emenda dec-024) — e reportado como
proveniencia. Uma Decisao estrutural com escolha concreta cujo `agent` diga
`operador` mas sem `human_consent_block_id` valido **e** anomalia; era
exatamente o bypass que a versao anterior deste predicado nao detectava.

| Field | Type | Origem |
|-------|------|--------|
| decision_id | string | `.decisions[].id` |
| structural_axis | string | `.decisions[].structural_axis` |
| agent | string | `.decisions[].agent` (informativo, nao normativo) |
| choice | string | `.decisions[].choice` |
| human_consent_block_id | string \| null | `.decisions[].human_consent_block_id` |

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
| **human_consent_block_id** | TEXT | NULL | **[NOVO]** espelha a coluna do state; sem ele o indice nao consegue avaliar o predicado de anomalia |

`RECALL_SCHEMA_VERSION`: `14` -> `15`. Migracao aditiva idempotente pelo padrao
ja existente naquele arquivo (`PRAGMA table_info` + `ALTER TABLE ADD COLUMN`),
aplicada aos dois caminhos de ingestao (JSON->SQL e SQL->SQL), que compartilham
o mesmo tuple de colunas. Base inteiramente reconstruivel via `--reindex`.

Nenhum dos tres campos novos e texto livre: dois sao tokens de enum fechado e o
terceiro e um id `block-NNN` gerado pelo runtime, logo **nao** passam por
`recall_scrub` (mesmo tratamento de `choice`, que ja nao passa). Nem o eixo nem
o id de bloqueio carregam segredo por construcao.

`subject_key` **nao** e propagado ao indice nesta feature: e derivado do texto do
briefing, portanto e o unico dos campos novos que poderia carregar conteudo do
projeto. Propaga-lo exigiria decidir seu tratamento em `recall_scrub`, o que nao
e necessario para nenhum consumidor atual — a dedup do FR-008 e sempre avaliada
contra a execucao corrente, no `state`, nunca contra o indice global.
