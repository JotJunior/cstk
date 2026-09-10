# Research: delivery-tier

**Feature**: `delivery-tier`
**Fase**: Phase 0 — resolucao de unknowns
**Data**: 2026-08-15

Todas as decisoes abaixo foram apuradas contra o codigo-fonte real do
toolkit (path + linha citados) ou por probe empirico executado nesta
fase. Nenhuma flag, campo, coluna ou assinatura foi suposta
(Constitution VI). Onde um mecanismo **nao existe** hoje, isso esta dito
explicitamente e a decisao e marcada como desenho a criar.

Restricoes de entrada (decisoes ja travadas pelo operador na etapa
`clarify`, Session 2026-08-15 — NAO reabertas aqui): escopo restrito ao
`/agente-00c` (dec-011); matriz cobre apenas `owasp-security` (dec-012);
omissao de fases e divisao binaria nuvem/nao-nuvem (dec-013).

---

## Decision 1 — Persistencia do tier: `extra_fields`, sem coluna nem DDL

**Decision**: o tier e persistido como campo top-level `.delivery_tier`
(string do enum de 4 tokens) no estado da execucao, gravado no `init` via
nova flag `--delivery-tier <token>`. **Nenhuma coluna nova** e criada em
`state.db` e **nenhum DDL e alterado**.

**Rationale**: a tabela `execution` do backend SQLite tem conjunto de
colunas fixo, mas possui a coluna catch-all `extra_fields TEXT` declarada
em
`plugins/cstk/skills/agente-00c-runtime/references/state-db-schema.sql:69`
exatamente para campos top-level ainda nao modelados. O dispatcher de
`set` cai nesse catch-all quando o campo nao mapeia para coluna conhecida
(`plugins/cstk/skills/agente-00c-runtime/scripts/_state-rw-db.sh:749-767`),
o `read` remonta o documento fazendo merge de `extra_fields` no nivel de
topo (`_state-rw-db.sh:361-367`, `($ext + $core)`) e o `write` preserva
campos extras por construcao — a lista de `del(...)` em
`_state-rw-db.sh:934` nao os remove.

Probe empirico executado nesta fase (state-dir descartavel,
`CSTK_STATE_BACKEND=sqlite`), saida literal:

```
$ state-rw.sh set --state-dir <tmp> --field '.delivery_tier' --value '"local"'
state-rw: set: .delivery_tier atualizado (backend sqlite)

$ state-rw.sh get --state-dir <tmp> --field '.delivery_tier // "ABSENT"'
local

$ sqlite3 <tmp>/state.db "SELECT extra_fields FROM execution;"
{"roadmap_mode_enabled":false,"delivery_tier":"local"}

$ sqlite3 <tmp>/state.db "PRAGMA table_info(execution);" | grep delivery_tier
(nenhuma linha — nao existe coluna dedicada)
```

O round-trip preserva o valor sem qualquer alteracao de DDL. Isso remove
do escopo da feature: `references/state-db-schema.sql`,
`state-db-migrate.sh` e o mapa de colunas `_sr_exec_col_lookup`
(`_state-rw-db.sh:388-433`).

**Precedente literal e recente**: `roadmap_mode_enabled` (feature
`roadmap-mode`, 2026-08-14) tomou exatamente esta decisao, com o
comentario normativo no proprio codigo
(`_state-rw-db.sh:156-165`): *"sem coluna dedicada (research.md
Decision 1) — pousa no catch-all `extra_fields`"*. Registro original em
`docs/specs/roadmap-mode/research.md` §Decision 1 (dec-010, score 3).

**Fato relevante sobre versionamento de schema do `state.db`**: **NAO
EXISTE** versionamento de DDL para o `state.db` — nao ha `PRAGMA
user_version`, nao ha tabela `schema_meta`, nao ha `ALTER TABLE` em
`state-db-schema.sh`/`state-db-migrate.sh`. A coluna `schema_version` e
apenas um campo TEXT da linha de `execution`. O padrao de migracao
aditiva versionada existe em **outro** banco (`knowledge.db`,
`cli/lib/recall.sh:146` `RECALL_SCHEMA_VERSION=14`) e nao se aplica aqui.
Portanto "adicionar coluna com migracao" nao e um caminho barato neste
banco — e mais um argumento a favor do catch-all.

**Alternatives considered**:

- *Coluna dedicada `delivery_tier TEXT` (espelhando
  `atomic_commit_enabled`, declarada em `state-db-schema.sql:34`)*:
  rejeitada. Como nao ha mecanismo de migracao de DDL, bancos ja criados
  nao ganhariam a coluna, e a paridade INSERT-vs-materializacao teria de
  ser mantida a mao em 4 pontos de `_state-rw-db.sh`. Custo
  desproporcional para um enum de 4 valores.
- *Sidecar de arquivo no state-dir (precedente `commit-baseline.txt`)*:
  rejeitada pelo mesmo motivo ja registrado em `roadmap-mode`: nao
  participa do backup filtrado da onda nem do hash de integridade, e
  ficaria invisivel ao relatorio.

**Ponto de modificacao real que esta decisao IMPLICA**: o objeto de
`extra_fields` montado no `init` sob SQLite e **hardcoded com uma unica
chave** hoje — `_state-rw-db.sh:165`:

```sh
_ie_extra_json=$(jq -cn --argjson v "$_ie_roadmap" '{roadmap_mode_enabled: $v}')
```

Para que o tier seja gravado **no init** (exigencia literal de FR-002),
essa linha precisa passar a compor as duas chaves. Sem essa alteracao o
campo so existiria apos um `set` posterior. Isto e um `[MOD]` obrigatorio,
nao opcional.

---

## Decision 2 — Captura da resposta: prompt em prosa no command, nao tool

**Decision**: a pergunta de finalidade e um **bloco de prosa** no
`plugins/cstk/commands/agente-00c.md`, na mesma janela dos opt-ins ja
existentes, com 4 opcoes numeradas e default explicito. A resposta e
capturada numa variavel do proprio command e repassada ao
`state-rw.sh init` como flag.

**Rationale**: e o mecanismo que os dois opt-ins existentes usam, e o
unico disponivel. Verificacao: `grep -rn "AskUserQuestion" plugins/`
retorna **zero ocorrencias** — a tool `AskUserQuestion` **NAO E USADA em
nenhum ponto do catalogo**. O padrao real esta em
`plugins/cstk/commands/agente-00c.md:273-295` (atomic-commit) e
`:319-343` (roadmap), ambos dentro da secao `### 3. Aquisicao do lock +
inicializacao de estado`, ANTES da chamada de init em `:345-354`.

O opt-in do roadmap e o modelo mais completo porque ja carrega a clausula
que FR-003 exige (`agente-00c.md:338-339`, literal):

```
- **Nao-interativo**: cai no default sem bloquear — nenhuma execucao pode
  travar esperando resposta (FR-001).
```

**Diferenca face aos precedentes**: ambos os opt-ins existentes sao
booleanos `[s/N]`. O tier e um enum de 4 valores, entao a convencao de
resposta passa a ser `[1/2/3/4]` com **default 4** (`cloud-public`).
Entrada vazia, invalida ou ausencia de operador cai no default — a mesma
regra de "qualquer outra resposta cai no default seguro", so que aqui o
default seguro e o de MAIOR profundidade (zero regressao, FR-003), nao o
de menor.

**Nota**: a persistencia e feita **pela flag do `init`**, nao por
`set-enabled`. Verificacao: `set-enabled` existe em `commit-mode.sh` e
`roadmap-mode.sh` mas **nao tem nenhum caller** em `plugins/`, `cli/` ou
`tests/`. O caminho vivo e sempre a flag do init.

**Alternatives considered**:

- *Pergunta aberta em texto livre ("para que serve o produto?")*:
  rejeitada. Exigiria classificacao por LLM para chegar ao token, o que
  reintroduz nao-determinismo num dado que governa gates de seguranca.
  Enum fechado e auditavel.
- *Derivar o tier do briefing em vez de perguntar*: rejeitada. O briefing
  roda DEPOIS do init (etapa inicial da pipeline), e FR-001 exige a
  captura **antes** da inicializacao do estado.

---

## Decision 3 — Enum e ordem de profundidade

**Decision**: 4 tokens estaveis, ordenados por profundidade crescente:

```
local  <  internal-network  <  cloud-internal  <  cloud-public
```

com ordinal numerico `1..4` usado apenas para comparar elevacao vs
rebaixamento (Decision 8). O token e o dado persistido; o ordinal e
derivado, nunca gravado.

**Rationale**: os 4 tokens sao literais de FR-001 da spec. A ordem e
literal de Key Entities (`spec.md` §Key Entities: *"ordenados por
profundidade crescente de entrega"*). O ordinal precisa existir em algum
lugar porque FR-009 distingue elevacao de rebaixamento; derivá-lo evita
persistir um segundo campo redundante que poderia divergir do token.

**Alternatives considered**:

- *Persistir o ordinal junto do token*: rejeitada — dois campos para o
  mesmo fato, com risco de divergencia; o ordinal e funcao pura do token.

---

## Decision 4 — Helper `delivery-tier.sh`, espelhando os dois precedentes

**Decision**: criar
`plugins/cstk/skills/agente-00c-runtime/scripts/delivery-tier.sh`
(POSIX sh puro) com 3 subcomandos: `get`, `set`, `gate-mode`. Contrato
completo em `contracts/cli-delivery-tier.md`.

**Rationale**: e o formato ja praticado por `commit-mode.sh` (is-enabled /
set-enabled) e `roadmap-mode.sh`, que declara no proprio cabecalho
(`roadmap-mode.sh:9-10`) *"Espelha commit-mode.sh is-enabled/set-enabled
(mesmo contrato de exit-0-sempre em is-enabled, mesma leitura defensiva
via state-rw.sh get)"*. A leitura defensiva literal de `commit-mode.sh`
(subcomando `is-enabled`) e:

```sh
_val=$(sh "$_rw" get --state-dir "$_sdir" \
  --field '.atomic_commit_enabled // false' 2>/dev/null) || _val="false"
```

`delivery-tier.sh get` usa a mesma forma com `// "cloud-public"` — o que
implementa FR-010 (estado legado sem o campo) **na propria leitura**, sem
precisar de migracao de dados. Exit 0 SEMPRE: campo ausente, estado
ilegivel, `state-rw.sh` ausente ou token fora do enum ⇒ imprime
`cloud-public`.

**Consequencia de teste (regra de ouro do repo)**: script novo em
`plugins/cstk/skills/*/scripts/` exige `tests/test_delivery-tier.sh`,
senao `./tests/run.sh --check-coverage` sai 1 (`tests/run.sh:10-13`,
`:58-59`). O esqueleto canonico esta em `tests/README.md:139-176`, com a
regra critica de **nao usar `set -eu` no arquivo de teste**.

**Alternatives considered**:

- *Sem helper: cada consumidor faz `state-rw.sh get --field
  '.delivery_tier // "cloud-public"'` inline*: rejeitada. O fallback
  FR-010 e a resolucao da matriz (Decision 5) ficariam replicados em 5+
  pontos de prosa, cada um livre para errar o default. Um helper
  deterministico e a unica forma de o fail-safe nao depender de o LLM
  lembrar.

---

## Decision 5 — Matriz tier x gate: tabela versionada em `references/`

**Decision**: criar
`plugins/cstk/skills/agente-00c-runtime/references/tier-gate-map.txt`,
formato `tier|gate|modo`, consumido por `delivery-tier.sh gate-mode
--tier <t> --gate <g>` em POSIX puro (sem `jq`). Fail-safe: par
`(tier, gate)` ausente ⇒ `completo`, exit 0. Formato completo em
`contracts/tier-gate-map.md`.

**Rationale**: o precedente exato pedido pela spec (FR-005: *"matriz
tier x gate versionada no toolkit"*) existe e foi lido:
`references/phase-model-map.txt`. Ele estabelece as convencoes que a nova
tabela reusa integralmente — 1a linha declara a versao como comentario,
`#` e linha vazia ignorados, campos separados por `|`, e **chave nao
listada nunca e erro** (retorna o default e sai 0). O parser de
referencia esta em `model-routing.sh:1076-1101` e traz um gotcha de
portabilidade que a nova implementacao **deve** herdar (comentario
literal no codigo):

> NOTA DE PORTABILIDADE: NAO usar `case ... esac` dentro deste `$( ... )`.
> Varios `sh` (inclusive bash em modo POSIX no macOS) falham no parse de
> `case` aninhado em command-substitution. Skip de comentario/branco e
> feito via expansao de parametro.

Conteudo de dados da tabela v1 — 4 linhas, **somente `owasp-security`**
(dec-012):

```
local|owasp-security|skip
internal-network|owasp-security|leve
cloud-internal|owasp-security|completo
cloud-public|owasp-security|completo
```

Os demais gates (`checklist`, `validate-documentation`,
`validate-docs-rendered`, `analyze`) **nao tem linha** — e e justamente
por isso que rodam completos nos 4 tiers: eles caem no fail-safe, nao
numa regra escrita. Isso torna dec-012 uma propriedade estrutural da
tabela, nao uma promessa em prosa.

**Alternatives considered**:

- *Matriz embutida como `case` dentro do helper*: rejeitada. FR-005 pede
  matriz **versionada**; um `case` no script nao e inspecionavel nem
  diffavel como dado, e mistura politica com mecanismo.
- *Matriz em JSON com `jq`*: rejeitada. `phase-model-map.txt` foi
  deliberadamente jq-free; manter POSIX puro evita acoplar a resolucao de
  gate a camada de estado transacional (Principio II).

---

## Decision 6 — Propagacao as etapas (FR-004): dois canais, um normativo

**Decision**: o tier chega as etapas `briefing`/`specify`/`plan` por dois
canais complementares:

1. **Normativo (deterministico)**: a propria skill le o tier via
   `delivery-tier.sh get --state-dir "$AGENTE_00C_STATE_DIR"`, com
   fallback `cloud-public` quando roda standalone (sem execucao ativa).
2. **Aditivo (contextual)**: o orquestrador cita o tier vigente e a
   instrucao de calibracao na string `args` da tool Skill.

**Rationale**: o canal 2, sozinho, e fragil — e a unica superficie de
parametro que a tool Skill tem. Verificacao: as invocacoes reais no
orquestrador sao todas `Skill(skill=..., args="<string livre>")`
(`agente-00c-orchestrator.md:358`, `:517`, `:542`, `:1470`), e **NAO
EXISTE** parametro estruturado/tipado — `args` e texto livre. Depender so
disso significa depender de o LLM lembrar de escrever a frase certa em
toda onda, que e exatamente a classe de falha que o repo ja documentou ao
criar um gate deterministico em Bash (`validate-tasks-template.sh`) em vez
de confiar numa skill LLM para checar conformidade.

O canal 1 torna a propagacao uma leitura de estado, nao uma lembranca.
Como efeito colateral desejavel, faz FR-006 funcionar tambem quando
`create-tasks` e invocada **fora** do orquestrador (uso manual), onde o
canal 2 nao existe.

**Nota de precedente**: propagacao de contexto rico hoje so acontece para
SUBAGENTES (tool Agent), nao para Skills — `.execution.suggested_stack` e
passado no prompt do `clarify-answerer`
(`agente-00c-orchestrator.md:940-945`), e essa e a **unica** ocorrencia de
`suggested_stack` no arquivo. Nao ha precedente de skill que leia estado
do orquestrador para se auto-calibrar; a skill `plan` ja le o state-dir
para outro fim (cache de artefatos foundational, `plan/SKILL.md`
§"Leitura de artefatos foundational"), o que confirma que o canal e viavel
e ja praticado — mas o uso para calibracao e **novo**.

**Alternatives considered**:

- *So o canal 2 (prosa nos args)*: rejeitada pela fragilidade acima.
- *So o canal 1 (skill le sozinha)*: rejeitada porque FR-004 diz
  literalmente que **o orquestrador** deve propagar; e o texto nos `args`
  tambem serve de rastro auditavel no transcript da onda.

---

## Decision 7 — FR-006 em `create-tasks`: condicionar exemplos, declarar omissao

**Decision**: a divisao binaria entra como regra condicional na secao
`### Organizacao de Fases` do `create-tasks/SKILL.md`, e o tier usado e
registrado no proprio `tasks.md` na secao **Escopo Coberto/Excluido** ja
obrigatoria pelo template.

**Rationale**: a estrutura de fases do backlog **nao e um enum fixo** —
`create-tasks/SKILL.md:210-211` diz literalmente *"Os exemplos abaixo sao
ilustrativos — adaptar a estrutura as camadas reais do projeto"*, e as
duas listas (`:214-231`) sao exemplos. **NAO EXISTE** hoje nenhuma fase
nomeada "deploy" ou "producao", nem qualquer condicional/flag de omissao
de fase. As fases que FR-006 quer omitir aparecem embutidas: infra/CI-CD
em "FASE 1 - Fundacao" e observabilidade em "FASE 7 - Observabilidade".

Consequencia pratica: FR-006 nao pode ser implementado como "remover item
N da lista canonica" — nao ha lista canonica. Implementa-se como regra de
geracao: nos tiers `local` e `internal-network`, o backlog **nao cria**
fase de deploy em nuvem, escalabilidade ou observabilidade de producao, e
declara essa exclusao na secao "Escopo Excluido".

**Compatibilidade com o gate deterministico**: `validate-tasks-template.sh`
impoe prefixo `FASE`, checkboxes, tag de criticidade, legendas, Matriz de
Dependencias, Resumo Quantitativo e Escopo Coberto/Excluido — **nao impoe
nomes de fase nem quantidade minima**. Portanto omitir fases nao quebra o
gate. Registrar o tier dentro de "Escopo Excluido" usa uma secao que o
gate ja exige, sem inventar estrutura nova.

**Alternatives considered**:

- *Nova secao obrigatoria `## Tier` no `tasks.md`, checada como
  `critical` por `validate-tasks-template.sh`*: rejeitada nesta feature.
  Tornaria `critical` uma ausencia em todo `tasks.md` legitimo ja
  existente no repo, quebrando o gate retroativamente. Se vier, deve
  vir como `warning` numa feature propria.
- *`config.json` da skill (`phase_prefix` etc.) como lugar do tier*:
  rejeitada. `config.json` e configuracao por projeto, estatica; o tier e
  por execucao.

---

## Decision 8 — Elevacao vs rebaixamento (FR-009): guarda no `set`

**Decision**: `delivery-tier.sh set --state-dir DIR --value <tier>` grava
o tier. Se o novo ordinal for **menor** que o atual (rebaixamento), o
comando **recusa com exit 2 sem escrever**, a menos que
`--allow-downgrade` seja passado explicitamente. Elevacao e sempre
permitida. Em ambos os casos, quem registra a Decisao auditavel e o
chamador (operador via resume), nao o helper.

**Rationale**: FR-009 exige que rebaixamento *"MUST NOT ser aplicado sem
decisao manual explicita"*. A forma que o repo ja usa para "mutacao
perigosa em voo" e recusa com exit 2 sem escrita: `roadmap-mode.sh`
declara no cabecalho a trava write-once com *"exit 2, sem escrever"*
quando a execucao ja passou de `constitution`. O `--allow-downgrade`
materializa o "explicito" da spec — o operador tem de digitar a intencao,
nao apenas repetir o comando.

O helper nao registra Decisao por conta propria para nao duplicar: o
fluxo de elevacao acontece entre ondas, onde o `/agente-00c-resume` ja
tem o padrao de registrar Decisao antes de agir. Artefatos ja gerados nao
sao reprocessados — o tier novo vale das ondas seguintes, o que decorre
de o helper so alterar estado (nenhum artefato e reescrito).

**Alternatives considered**:

- *Bloquear rebaixamento sempre (write-once puro, como o roadmap-mode)*:
  rejeitada. A spec preve rebaixamento com decisao manual explicita; um
  write-once absoluto contrariaria FR-009.
- *Permitir rebaixamento silencioso e so registrar Decisao*: rejeitada.
  "Registrar depois" nao satisfaz "MUST NOT ser aplicado sem decisao
  explicita".

---

## Decision 9 — Visibilidade (FR-008): linha no relatorio + leitura no review-task

**Decision**: adicionar UMA linha a tabela da secao 1 do relatorio final,
em `_rp_render_secao_1` de
`plugins/cstk/skills/agente-00c-runtime/scripts/report.sh`, e uma
subsecao curta no `review-task/SKILL.md` que le o tier e cruza com as
Decisoes de gate.

**Rationale**: a secao 1 do relatorio ja e uma tabela `| Campo | Valor |`
montada por `jq` com fallback textual para campo ausente — o padrao esta
em `report.sh:144` (`suggested_stack` com `//` e texto explicativo) e
`:146` (`termination_reason // "(em andamento)"`). Uma linha nova segue
exatamente essa forma, com fallback que torna FR-010 visivel em vez de
mudo:

```
| Tier de entrega | \(($exec.delivery_tier // .delivery_tier) // "cloud-public (nao declarado — estado legado)") |
```

As **consequencias** exigidas por FR-008 (gates pulados / versao leve) ja
sao auditaveis sem trabalho novo: cada skip ou modo leve gera Decisao
(FR-005), e Decisoes ja sao renderizadas integralmente na secao 3 do
mesmo relatorio (`report.sh:204-255`). O relatorio ganha o tier; o
cruzamento fica no `review-task`, que e onde a auditoria de gates ja
mora.

**Nota de escopo**: o campo e top-level (`.delivery_tier`), nao
`.execution.delivery_tier` — espelha `atomic_commit_enabled` e
`roadmap_mode_enabled`, ambos irmaos de `.execution`, nao filhos. A
expressao acima tolera as duas formas por seguranca de leitura.

---

## Decision 10 — Validacao de tipo em `state-validate.sh`

**Decision**: adicionar a `state-validate.sh` uma checagem de que
`.delivery_tier` e **um dos 4 tokens OU ausente** — nunca outra coisa.

**Rationale**: FR-010 exige que estado legado *"sem re-prompt, sem erro de
validacao"* seja aceito. Hoje isso ja acontece por omissao (o validador
nao rejeita campos desconhecidos), mas por omissao nao e verificavel. O
padrao explicito existe para o campo gemeo em
`state-validate.sh:193-201`, que aceita `boolean|null` e reporta erro
para qualquer outro tipo — `null` sendo exatamente "ausente = ok". Uma
checagem analoga torna a retro-compatibilidade uma assercao testavel em
vez de um efeito colateral.

**Nota honesta de precedente**: `roadmap-mode` **nao** adicionou essa
checagem para `.roadmap_mode_enabled` — `grep roadmap
state-validate.sh` nao retorna nada. Portanto isto e uma escolha desta
feature (ir um passo alem do precedente), nao a replicacao de um padrao
universal.

**Alternatives considered**:

- *Nao mexer em `state-validate.sh` (paridade estrita com roadmap-mode)*:
  aceitavel, mas deixa FR-010 sem assercao propria. Custo da checagem e
  ~8 linhas + 2 cenarios de teste.

---

## Decision 11 — Superficie deliberadamente NAO tocada

**Decision**: esta feature **nao** altera: `/feature-00c` e seus commands
(dec-011); `mcp/state-server/`; `cli/lib/recall.sh` e a `knowledge.db`;
`references/state-db-schema.sql` e `state-db-migrate.sh`;
`model-routing.sh`, `phase-model-map.txt` e qualquer decisao de modelo.

**Rationale**: cada exclusao tem base verificada, nao presuncao.

- **`/feature-00c`**: decisao registrada do operador (dec-011); a spec
  reescreve isso em `spec.md` §Contexto.
- **MCP e knowledge.db**: verificado que o precedente direto nao os
  tocou — `grep -rn "roadmap_mode_enabled" mcp/ cli/ tests/cstk/` retorna
  **zero ocorrencias**. Campos que vivem em `extra_fields` e nao sao
  mutaveis por tool MCP nao entram no mapper de paridade.
- **DDL do `state.db`**: consequencia direta da Decision 1.
- **model-routing**: fora de escopo por decisao do operador registrada na
  propria spec (`spec.md` §Contexto, 2026-08-14): *"o tier NAO influencia
  o model-routing"*.

---

## Unknowns restantes

**Zero.** Nenhum `NEEDS CLARIFICATION` permanece no Technical Context do
`plan.md`. Os tres pontos que eram ambiguos na spec foram fechados na
etapa `clarify` (dec-011/012/013) e entraram aqui como restricoes de
entrada, nao como decisoes de design reabertas.
