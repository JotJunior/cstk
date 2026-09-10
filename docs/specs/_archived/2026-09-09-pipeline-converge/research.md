# Research: pipeline-converge

Documento produzido no Phase 0 do `/plan`. Resolve os unknowns de design antes
do Phase 1. Toda afirmacao sobre o comportamento atual do toolkit foi extraida
por leitura direta do codigo-fonte citado (path + linha), nunca inferida
(Constitution VI).

## Decision 1: Nome e posicao da etapa na lista canonica

**Decision**: a etapa se chama `converge` — mesmo token do nome da skill
(`plugins/cstk/skills/converge/`) — e e inserida em
`_PL_STAGES_LIST` (`plugins/cstk/skills/agente-00c-runtime/scripts/pipeline.sh:96`)
entre `execute-task` e `review-task`, levando a lista canonica de 10 para 11
etapas:

```
briefing constitution specify clarify plan checklist create-tasks \
  execute-task converge review-task review-features
```

**Rationale**: todas as etapas da lista atual sao o token exato de uma skill
homonima (`specify`, `clarify`, `plan`, `checklist`, `create-tasks`,
`execute-task`, `review-task`, `review-features`, `briefing`, `constitution`).
Usar `converge` mantem a bijecao etapa↔skill, que e o que permite ao
orquestrador resolver "qual skill invocar nesta etapa" sem tabela de traducao.
Atende FR-001 e SC-004 (mesmo nome em todos os pontos).

**Alternatives considered**:
- `convergence` / `converge-check`: quebraria a bijecao etapa↔skill e criaria
  dois vocabularios para a mesma coisa.
- Manter `converge` fora da lista e tratar como sub-passo de `execute-task`:
  e exatamente o estado atual que a feature existe para eliminar (US2).

## Decision 2: Alargar `_PL_STAGES_LIST` NAO viola a invariante do `--mode`

**Decision**: alargar a lista canonica de 10 para 11 etapas e legitimo; a
invariante existente permanece intacta e seu comentario sera reescrito para
deixar o escopo explicito.

**Rationale**: o comentario em `pipeline.sh:147` ("_PL_STAGES_LIST permanece
INALTERADA (invariante dura, SC-003)") e o de `pipeline.sh:490-492` ("a lista
global (_PL_STAGES_LIST) nunca se alarga") pertencem a feature `roadmap-mode`
e afirmam que **o parametro `--mode` nao edita a lista global** — `--mode`
apenas seleciona qual lista os subcomandos iteram (`_pl_mode_list`,
`pipeline.sh:160-167`). A invariante e sobre o mecanismo `--mode`, nao sobre a
imutabilidade eterna do conteudo da lista. Adicionar uma etapa canonica por
uma mudanca deliberada de versao e ortogonal: `--mode roadmap` continua
retornando exatamente `briefing constitution roadmap`, e `--stage roadmap`
continua so aceito com `--mode roadmap` (fail-closed preservado).

**Alternatives considered**:
- Introduzir `--mode` novo (ex.: `--mode converge`) para nao tocar a lista
  global: nao atende FR-001/SC-004 — a etapa ficaria invisivel na sequencia
  oficial, que e o problema que a feature resolve.
- Deixar a lista intacta e resolver a transicao so na prosa dos
  orquestradores: e o estado atual (US2 existe para elimina-lo).

**Impacto medido em testes** (inventario por varredura do repo, cada item
verificado em arquivo+linha):

| Teste | Cenario | Efeito |
|-------|---------|--------|
| `tests/test_pipeline.sh:98` | `scenario_stages_lista_10_etapas_em_ordem` | QUEBRA — compara stdout byte-a-byte com heredoc de 10 linhas. Renomear para `..._11_etapas_...` e inserir `converge` |
| `tests/test_pipeline.sh:778` | `scenario_stages_sem_mode_permanece_10_etapas_intacta` | QUEBRA — mesma lista literal. Renomear e atualizar |
| `tests/test_pipeline.sh:805` | `scenario_stages_mode_default_byte_identico_a_sem_mode` | SOBREVIVE — compara `stages` com `stages --mode default`, nao o conteudo |
| `tests/test_pipeline.sh:121` | `scenario_next_stage_avanca_linear` | SOBREVIVE — cobre `briefing->constitution` e `plan->checklist`, nao a fronteira alterada |
| `tests/test_state-ondas.sh:2045` | `scenario_sqlite_end_advance_avanca_ponteiro_na_mesma_transacao` | QUEBRA — seed `current_stage=execute-task` espera `review-task` |
| `tests/test_state-ondas.sh:1025` | `scenario_reconcile_wave_execute_task_backlog_completo_avanca` | QUEBRA — seed `current_stage=execute-task` com backlog completo, assere avanco para `review-task` |
| `tests/test_state-ondas.sh:1033-1042` | `scenario_reconcile_wave_dry_run_reporta_hold` | SOBREVIVE — backlog INCOMPLETO (`- [ ] 1.1.1 pendente`), assere `HOLD`; nao depende do nome da proxima etapa |
| `tests/test_state-ondas.sh:2352-2359` | `scenario_sqlite_reconcile_wave_fecha_e_avanca_ponteiro` | SOBREVIVE no assert — o cenario seta `current_stage=review-task` (linha 2357) para exercitar o ramo terminal. Mas o **comentario** das linhas 2352-2356 afirma literalmente "execute-task -> review-task" como o ramo nao-terminal: passa a ser `execute-task -> converge` e precisa ser atualizado |
| `tests/test_converge-orchestrator-gate.sh:52,56` | `scenario_*_fronteira_execute_task_review_task` | QUEBRA — regex `execute-task.{0,5}(->|→).{0,5}review-task` nao casa com `execute-task → converge → review-task` |
| `tests/test_model-routing.sh:2088-2100` | `_PML_EXPECTED` (11 fases) | Atualizar para 12 fases ao incluir `converge` no mapa (Decision 10) |
| `tests/test_model-routing.sh:2135` | `scenario_fase1_map_so_tem_linhas_validas_ou_comentario` | SOBREVIVE — `converge\|profunda\|opus` esta dentro dos enums `{rasa,media,profunda}`/`{haiku,sonnet,opus,manter-atual}` |
| `tests/cstk/test_build-release.sh:170-188` | contagem `sdd` = 17 skills | SOBREVIVE — `converge` ja consta em `scripts/profiles.txt.in:37-41` (`sdd:converge`); a feature nao adiciona skill nova |

Os dois cenarios de `test_state-ondas.sh` sao o achado mais relevante: nao sao
"apenas teste". Eles capturam **comportamento de producao** — `end --advance` e
`reconcile-wave` passam a apontar `execute-task -> converge`. Isso e o efeito
desejado (US2-AS2), mas confirma que a mudanca nao e cosmetica e exige revisao
do `--terminal-phase` usado pelos commands (ver Decision 14).

## Decision 3: `converge` precisa de artefato de status persistente

**Decision**: a skill `converge` passa a gravar, alem da fase residual em
`tasks.md`, um artefato de status append-only no diretorio da feature:
`docs/specs/<feature>/converge-report.md`. Cada invocacao apenda UMA linha
marcadora parseavel por ferramenta POSIX.

**Rationale**: tres consumidores precisam saber "a convergencia mais recente
rodou? apontou pendencias?" — `execute-task` (orientacao de proximos passos,
FR-002), `review-task` (soft gate, FR-004) e
`pipeline.sh detect-completion --stage converge` (maquina de etapas, FR-001).
Dois deles rodam **tambem em execucao manual**, onde nao existe `state.json`
(a clarificacao da spec estende a obrigatoriedade ao operador manual). Logo o
fato precisa viver num artefato do feature-dir, nao apenas no estado
transacional.

Hoje a skill nao deixa rastro consultavel quando converge limpo: os unicos
marcadores gravados sao `<!-- converge-key: ... -->` dentro de `tasks.md`
(`plugins/cstk/skills/converge/scripts/converge-tasks.sh`, subcomando
`existing-keys`), e eles so existem quando houve achado acionavel — ausencia
de marcador e ambigua entre "nunca convergiu" e "convergiu limpo".

**Alternatives considered**:
- Marcador dentro do proprio `tasks.md`: polui o backlog com metadado de
  processo e colide com o contrato append-only de fases do
  `converge-tasks.sh append-phase`.
- Guardar so no `state.json`: nao cobre execucao manual (violaria a
  clarificacao de escopo da spec).
- `detect-completion --stage converge` sempre exit 0 (como `review-task` e
  `review-features` fazem hoje, `pipeline.sh:572-576`): deixaria FR-004 sem
  lastro — a etapa seria "obrigatoria" apenas de nome.

## Decision 4: formato do marcador de status (POSIX-parseavel, sem `jq`)

**Decision**: uma linha de comentario HTML por invocacao, no mesmo estilo ja
usado pelo `converge-key`, com pares `chave=valor` separados por `; `:

```
<!-- converge-status: outcome=clean; provenance=gate; at=2026-08-21T12:00:00Z; actionable=0; tasks-digest=ab12cd34ef56 -->
```

Campos: `outcome` (`clean` | `actionable` | `risk-accepted`), `provenance`
(`gate` | `standalone`), `at` (ISO 8601 UTC), `actionable` (inteiro),
`tasks-digest` (12 hex, ver Decision 6) e, quando houver, `decision-id`
(`dec-NNN`) e `note`.

**Rationale**: Constitution II (NON-NEGOTIABLE) bane `jq` em scripts que
acompanham skills — `plugins/cstk/skills/converge/scripts/` e exatamente esse
caso (a excecao de dependencia opcional da amendment 1.1.0/1.2.x cobre a
camada de estado transacional do `agente-00c-runtime`, nao a skill
`converge`). `grep`/`sed`/`awk` sobre linha `chave=valor` e POSIX puro. O
formato ja tem precedente no proprio codebase (`converge-key`), reduzindo
vocabulario novo.

**Alternatives considered**:
- YAML frontmatter: exigiria parser proprio para historico multi-entrada.
- JSON + `jq`: proibido pelo Principio II neste diretorio.
- Um arquivo por invocacao (`converge-2026-08-21.md`): dificulta "qual e a
  mais recente" e polui o feature-dir.

## Decision 5: script determinístico novo `converge-status.sh`

**Decision**: criar
`plugins/cstk/skills/converge/scripts/converge-status.sh` (POSIX sh,
`set -eu`, sem `jq`) com quatro subcomandos:

| Subcomando | Efeito | Exit |
|-----------|--------|------|
| `record --feature-dir D --outcome O --provenance P --actionable N` | apenda linha de status | 0 ok / 2 uso |
| `latest --feature-dir D` | imprime a ultima linha de status | 0 ok / 1 nunca convergiu |
| `check --feature-dir D` | veredito consultavel pelos consumidores | 0 convergida / 1 pendente / 3 nunca rodou |
| `accept-risk --feature-dir D --justificativa T [--decisao-id ID]` | apenda `outcome=risk-accepted` | 0 ok / 2 uso |

**Rationale**: Constitution III exige que a mecanica deterministica viva em
`scripts/`, nao na prosa do `SKILL.md`; a propria skill `converge` ja segue
esse padrao (toda escrita em `tasks.md` passa por `converge-tasks.sh`, nunca
por Edit/Write direto). Um script unico e a fonte de verdade do formato do
marcador — nenhum consumidor (execute-task, review-task, pipeline.sh,
orquestradores) reimplementa o parse. Regra de teste do projeto: nasce com
`tests/test_converge-status.sh` (convencao verificada por
`./tests/run.sh --check-coverage`).

**Alternatives considered**:
- Estender `converge-tasks.sh` com os subcomandos novos: mistura duas
  responsabilidades (backlog vs status de processo) num script que ja tem 5
  subcomandos.
- Cada consumidor faz seu proprio `grep`: N implementacoes do formato,
  divergencia garantida na primeira mudanca.

## Decision 6: invalidacao por digest do `tasks.md` cobre reabertura (FR-007)

**Decision**: a linha de status grava `tasks-digest=<12 hex>` do `tasks.md` no
momento da convergencia. `check` compara o digest gravado com o digest atual:
divergiu ⇒ o status limpo esta **stale** e o veredito e "pendente" (exit 1),
exigindo nova convergencia.

**Rationale**: resolve FR-007 (round reaberto tambem precisa convergir) sem
acoplar a skill `converge` — que roda no feature-dir e tambem em modo manual —
ao mecanismo de rounds do estado transacional. Verificado: os rounds vivem em
`<state-dir>/rounds/<label>/`
(`plugins/cstk/skills/agente-00c-runtime/scripts/state-rounds.sh:18,23`),
**nao** no `docs/specs/<feature>/`; um artefato do feature-dir nao tem como
observar o round por si so. O digest e um invariante mais forte e mais geral:
qualquer mudanca no backlog apos a convergencia (round reaberto, fase residual
executada, tarefa nova) invalida o veredito — que e precisamente o
comportamento desejado por FR-003 (loop incremental) e FR-007 (reabertura).

**Rationale do algoritmo**: `sha256` ja e usado no mesmo diretorio de scripts
para derivar `gap-key`
(`converge-tasks.sh`, subcomando `gap-key`: `sha256-12(normalize(path) + " " +
type + " " + normalize(origin))`) — reusar o helper existente evita introduzir
dependencia ou convencao nova.

**Alternatives considered**:
- Gravar `round=<N>` lido do estado: indisponivel em execucao manual e
  ausente do feature-dir (verificado acima).
- Comparar `mtime` do `tasks.md`: fragil (checkout git, `touch`, clone
  reordenam mtime sem mudar conteudo).
- Contar tarefas `[x]`: nao detecta edicao de conteudo de tarefa nem
  reordenacao; falso "convergido" possivel.

## Decision 7: criterio de `detect-completion --stage converge`

**Decision**:

1. `tasks.md` ausente no feature-dir ⇒ **exit 0** (etapa nao se aplica).
2. `tasks.md` presente ⇒ delega a `converge-status.sh check`: exit 0 quando o
   veredito e convergida (limpa ou risco aceito), exit 1 quando pendente ou
   nunca rodou.

**Rationale**: (1) implementa FR-005 literalmente — feature que nunca passou
por criacao/execucao de tarefas nao tem backlog a reconciliar e nao pode ser
travada artificialmente; e coerente com o precedente do proprio
`detect-completion`, que para `execute-task` ja exige `tasks.md`
(`pipeline.sh:567-571`). (2) da a FR-004 lastro deterministico na maquina de
etapas.

**Nota de acoplamento**: `pipeline.sh` vive em
`plugins/cstk/skills/agente-00c-runtime/scripts/` e passaria a chamar um
script de outra skill (`converge/scripts/converge-status.sh`). Ha precedente
explicito no repo — `converge-tasks.sh` documenta o "Reuso obrigatorio de
create-tasks/scripts/next-task-id.sh".

**Mitigacao (revista pelo gate `owasp-security` — finding F1)**: a degradacao
distingue dois casos, em vez de tolerar ausencia indiscriminadamente:

- **skill `converge` nao instalada** (diretorio `skills/converge/` ausente) ⇒
  exit 0 + aviso: a etapa nao se aplica a esse catalogo, e a maquina de etapas
  nao pode travar por isso.
- **skill instalada, mas `converge-status.sh` ausente/nao-executavel/falho** ⇒
  exit 1 (**fail-closed**) + diagnostico: indica catalogo corrompido ou
  adulterado. Degradar para exit 0 aqui seria fail-**open** num ponto que
  decide avanco de etapa — a convergencia seria dada como concluida sem nunca
  ter sido avaliada.

A redacao original desta decisao previa exit 0 para ambos os casos; foi
corrigida antes do fechamento da etapa `plan`.

**Alternatives considered**:
- `pipeline.sh` parsear o marcador diretamente: duplicaria o formato,
  contrariando Decision 5.
- Falhar quando o script nao existe: quebraria projetos com catalogo parcial
  por uma etapa que e, para eles, inexistente.

## Decision 8: soft gate em `review-task` e onde mora o aceite de risco

**Decision**: `review-task` ganha um passo de auditoria que invoca
`converge-status.sh check`. Veredito pendente ⇒ emite finding
`converge-pending` no relatorio e instrui o registro do aceite; **nunca
bloqueia** (a clarificacao da spec fixou soft gate). O aceite de risco e
registrado em dois lugares complementares:

- **execucao autonoma**: `state-decisions.sh register` (Decisao auditavel no
  historico de execucao, conforme a clarificacao) e, em seguida,
  `converge-status.sh accept-risk --decisao-id <dec-NNN>` para que o artefato
  carregue o vinculo.
- **execucao manual**: `converge-status.sh accept-risk --justificativa "..."`
  apenas — o artefato e o unico historico disponivel.

**Rationale**: a clarificacao exige "decisao auditavel no historico de
execucao (nao apenas um campo flag simples)". Em execucao autonoma o historico
de execucao e o `state.json`/`state.db`; em execucao manual ele nao existe, e
o artefato append-only assume o papel. Registrar nos dois lados quando ambos
existem mantem `state.json` como fonte de verdade da execucao e o feature-dir
auto-contido para leitura posterior.

**Alternatives considered**:
- Hard gate (bloquear `review-task`): contraria diretamente a clarificacao.
- So `state.json`: deixa a execucao manual sem mecanismo de aceite.
- So o artefato: perderia a Decisao auditavel exigida pela clarificacao em
  execucao autonoma.

## Decision 9: proveniencia gate-vs-avulsa (FR-010)

**Decision**: duas gravacoes, uma por camada:

- **artefato**: campo `provenance=gate|standalone` na linha de status.
- **historico de execucao autonoma**: `state-ondas.sh record-skill --skill
  converge --kind gate` quando disparada pela fronteira
  `execute-task → review-task`; `--kind skill` (default) quando avulsa.

A proveniencia e **parametro explicito** da invocacao (a skill recebe
`--provenance`, default `standalone`), nunca heuristica.

**Rationale**: a clarificacao pediu explicitamente "no mesmo padrao usado por
`record-skill --kind gate`" — o padrao ja existe e e consumido pela ingestao
do `cstk recall` (a prosa dos orquestradores instrui `--kind gate` para gates
deterministicos). Parametro explicito evita a classe de bug em que a
proveniencia e inferida de variavel de ambiente e mente quando o operador roda
a skill manualmente dentro de uma sessao com execucao ativa.

**Alternatives considered**:
- Inferir de `AGENTE_00C_STATE_DIR`: mente no caso acima (operador invoca
  avulsamente durante execucao autonoma).
- So no `state.json`: nao cobre execucao manual (FR-010 nao restringe modo).

## Decision 10: faixa de modelo da etapa `converge`

**Decision**: adicionar `converge|profunda|opus` a
`plugins/cstk/skills/agente-00c-runtime/references/phase-model-map.txt` e
atualizar o comentario de enum do arquivo (hoje declara "Enum de fases
cobertas (11)").

**Rationale**: sem entrada, o lookup resolve `manter-atual` (regra FR-020
documentada no cabecalho do proprio mapa) — nao quebra, mas deixa a etapa sem
piso. `converge` faz leitura semantica de codigo e classificacao de
divergencia contra spec/plan/tasks + `MUST` da constitution, carga
equivalente a `analyze` (`analyze|profunda|opus` no mapa atual), nao a
`review-task` (`rasa|haiku`, que so le o backlog).

**Alternatives considered**:
- `media|sonnet`: mais barato, mas a etapa e o gate anti-drift do pipeline —
  falso "convergido" por leitura rasa e o modo de falha caro.
- Nao mexer no mapa: aceitavel (degrada para `manter-atual`), mas perde a
  oportunidade de dar piso a uma etapa nova; custo de uma linha.

## Decision 11: superficie de documentacao de usuario (FR-009 / SC-004)

**Decision**: a sequencia oficial e atualizada em **todos** os pontos abaixo,
levantados por varredura do repositorio (cada um verificado em arquivo+linha).
Omissao de qualquer um e violacao direta de SC-004, verificavel por `grep`.

**Lista de 10 etapas (agente-00c)** — passa a 11:

| Arquivo | Linha(s) | Natureza |
|---------|----------|----------|
| `plugins/cstk/agents/agente-00c-orchestrator.md` | 3 (frontmatter `description`), 108, 460 | agente (fonte) |
| `plugins/cstk/commands/agente-00c.md` | frontmatter | command |
| `docs/fluxo-orquestradores-00c.md` | 18, 46 (mermaid) | doc interna |
| `docs/agente-00c.md` / `docs/agente-00c.pt-BR.md` | 22, 93 | doc de usuario (bilingue) |
| `docs/sdd-pipeline.md` / `docs/sdd-pipeline.pt-BR.md` | 17-73 (diagrama ①..⑩), 89, 94 | doc de usuario (bilingue) |
| `docs-site/manual/fluxo-sdd.md` | 8 ("10 etapas"), 17-49, 123 | site |
| `docs-site/index.md` | 103, 164 | site |
| `docs-site/manual/profiles.md` | 17-18 | site |
| `CONTRIBUTING.md` / `CONTRIBUTING.pt-BR.md` | 61-63 / 60-62 (mermaid) | contribuicao (bilingue) |
| `README.md` / `README.pt-BR.md` | 114, 187 / 115, 188 | doc de usuario (bilingue) |
| `CLAUDE.md` | bloco "SDD Pipeline" / "Complementary" | convencoes do repo |

**Lista curta de 7 etapas (feature-00c)** — passa a 8:

| Arquivo | Linha(s) |
|---------|----------|
| `plugins/cstk/agents/agente-00c-feature-orchestrator.md` | 3 (frontmatter), 38-42 (§Escopo de pipeline) |
| `plugins/cstk/commands/feature-00c.md` | 2 (frontmatter) |
| `docs/fluxo-orquestradores-00c.md` | 113, 147 (mermaid) |
| `docs/cstk-panel/frontend-brief.md` | 15-16, 114 |

**Skills** — secao `## Proximos passos`: `execute-task`, `review-task`,
`converge`.

**Rationale**: SC-004 exige lista identica — mesma ordem, mesmos nomes — em
todos os pontos onde e referenciada para o usuario. O padrao bilingue do repo
(arquivo EN + contraparte `.pt-BR.md`) e observavel e deve ser respeitado.

**Nota de sincronizacao (GOTCHA do repo)**: as copias instaladas em
`.claude/agents/agente-00c-orchestrator.md` e
`.claude/agents/agente-00c-feature-orchestrator.md` divergem hoje das fontes em
`plugins/cstk/agents/`. A edicao MUST acontecer na fonte
(`plugins/cstk/agents/`); a copia instalada e sincronizada por
`cstk install --from <tarball>` (catalogo), conforme §"Installed vs Source
Drift" do `CLAUDE.md`. Editar a copia instalada e perda de trabalho na proxima
sincronizacao.

**Alternatives considered**:
- Atualizar so `docs/sdd-pipeline.md`: quebra SC-004 nos demais pontos.
- Atualizar so EN: quebra a paridade bilingue ja estabelecida no repo.

## Decision 12: reposicionar `converge` de "complementar" para "pipeline"

**Decision**: no `CLAUDE.md` e no `README.md`, `converge` sai do bloco
"Complementary (use anytime)" e passa para o bloco da pipeline SDD, na
posicao entre `execute-task` e `review-task` — mantendo, no texto, a nota de
que a invocacao avulsa continua permitida (FR-008).

**Rationale**: FR-009 pede exatamente essa reclassificacao. FR-008 preserva o
uso avulso, entao a nota evita que a formalizacao seja lida como restricao.

**Alternatives considered**:
- Listar nos dois blocos: duplicacao que degrada em divergencia na primeira
  edicao.

## Decision 13: esta feature REVOGA uma decisao arquitetural registrada

**Decision**: a insercao de `converge` em `_PL_STAGES_LIST` revoga
explicitamente a Decision 5 da feature `skill-converge`
(`docs/specs/_archived/2026-07-28-skill-converge/research.md:155-180`, reforcada
em `tasks.md:298` como escopo excluido). A revogacao e registrada no `plan.md`
e no `CHANGELOG.md`, nunca feita silenciosamente.

**Rationale**: a decisao original rejeitou o stage novo com dois argumentos
(citados literalmente do arquivo):

1. *"Inserir `converge` ali mudaria a ordem linear e exigiria um mapeamento
   `detect-completion` artificial (converge nao gera artefato-arquivo proprio —
   seu output e uma Decisao + append no `tasks.md`)"*
   (`research.md:165-168`).
2. *"FR-019 ja compara converge a `validate-documentation`/`owasp-security`, que
   sao gates in-phase (...). Seguir esse padrao e o caminho de menor disrupcao e
   maior coerencia"* (`research.md:169-172`).

> Nota de transcricao: o documento arquivado usa acentuacao plena ("nao" ->
> "nao"/"não", "Decisao" -> "Decisão", "e" -> "é"). As citacoes acima preservam
> a redacao e a pontuacao originais, mas seguem a convencao ASCII sem acento
> adotada neste documento — sao fieis em conteudo, nao byte-a-byte.

O argumento (1) deixa de valer por construcao: a Decision 3 desta feature faz
`converge` **passar a gerar artefato-arquivo proprio**
(`converge-report.md`), eliminando exatamente a condicao que tornava o
mapeamento "artificial". O argumento (2) deixa de valer porque a premissa
mudou de escopo: a clarificacao desta spec estendeu a obrigatoriedade da
convergencia a **execucao manual do operador**, onde nao existe `state.json` —
e "Decisao auditavel + record-skill" (o mecanismo dos gates in-phase) nao esta
disponivel. Um gate que so existe na prosa do orquestrador nao pode, por
definicao, cobrir quem nao usa orquestrador.

O custo que a decisao original queria evitar (disrupcao em
`next`/`prev`/`detect-completion`) e real e esta medido na tabela da Decision 2
— e aceito deliberadamente como o preco de FR-001/FR-002.

**Alternatives considered**:
- Manter a decisao antiga e resolver so na prosa: e o estado atual; nao atende
  o escopo manual da clarificacao.
- Revogar sem registrar: viola Constitution I (mudanca de contrato exige
  artefato) e apagaria o rastro de por que a arquitetura mudou de ideia.

## Decision 14: `--terminal-phase` e `reconcile-wave` continuam corretos sem alteracao

**Decision**: nenhum ajuste em `--terminal-phase`. `feature-00c` continua
fechando com `--terminal-phase review-task` e `agente-00c` com
`--terminal-phase review-features`.

**Rationale**: `--terminal-phase` declara qual e a **ultima** etapa do escopo
daquele orquestrador, nao a proxima — serve para o `--advance` falhar
fail-closed ao tentar avancar alem do escopo. Sao duas guardas distintas:
`state-ondas.sh:889-891` recusa `--advance` quando a fase corrente **e** a
terminal ("--advance em fase terminal ... fechamento terminal usa
--motivo-termino concluido"), e `state-ondas.sh:897-898` recusa quando
`next-stage` nao devolve proxima etapa ("--advance sem proxima etapa a partir
de ..."). Como `converge` e inserida **antes** de `review-task`,
as duas fases terminais permanecem terminais. O que muda e o caminho ate elas,
resolvido automaticamente por `next-stage` (Decision 2).

O `reconcile-wave` tem um hold especifico em `execute-task`
(`state-ondas.sh:1675`) que so avanca quando ha zero linhas `- [ ]` pendentes
em `tasks.md` — com a lista alargada, esse mesmo hold passa a liberar para
`converge` em vez de `review-task`, que e exatamente o ponto de FR-002. O hold
nao precisa de logica nova.

**Verificacao pendente na implementacao**: nao existe hold analogo para a etapa
`converge` — sem um, `reconcile-wave` avancaria `converge -> review-task` mesmo
com convergencia pendente. A tarefa correspondente deve avaliar um hold
simetrico consultando `converge-status.sh check`, respeitando o carater soft
gate (avanca, mas o finding de `review-task` permanece).

**Resolucao (FASE 6, tarefa 6.2)**: implementado como **aviso soft, NAO
bloqueante** — `reconcile-wave` (`state-ondas.sh:_so_cmd_reconcile_wave`)
consulta `pipeline.sh detect-completion --feature-dir <dirname
--tasks-md> --stage converge` (mesma resolucao de `converge-status.sh` que a
propria etapa ja usa — sem logica nova, conforme a Decision acima) IMEDIATAMENTE
antes da transicao `converge -> review-task`. Quando o veredito nao e
converged/risk-accepted/not-applicable (exit != 0), a fase avanca **do mesmo
jeito** para `review-task`, mas a `next_instruction` grava um sufixo
`AVISO: convergencia pendente em <feature-dir> (...) — revisar em review-task
antes de finalizar.`; o mesmo aviso aparece no stdout de `reconciled (...)` e
`would reconcile (...)` (`--dry-run`). Deliberadamente **nao** um hold
bloqueante (ao contrario do hold de `execute-task`): FR-019 estabelece que
`converge` nunca trava sozinha — quem decide bloqueio e o
orquestrador/operador, e o soft gate ja existente em `review-task` (finding
`converge-pending`) permanece como a rede real. Um hold duro em
`reconcile-wave` duplicaria esse gate num caminho mecanico de baixo nivel
(safety net do command pai, nao o fluxo de decisao do orquestrador) e criaria
risco de a feature ficar presa em `converge` indefinidamente se o veredito
nunca virar `converged`/`risk-accepted` (ex.: `converge-status.sh` ausente por
drift de instalacao). Cobertura: `tests/test_state-ondas.sh` cenarios
`reconcile_wave_converge_*`.

**Alternatives considered**:
- Passar `--terminal-phase converge` em algum caminho: mudaria a semantica de
  "ultima etapa do escopo" e travaria `review-task`.

## Decision 15: divergencia pre-existente do `analyze` na documentacao

**Decision**: normalizar a representacao de `analyze` nos pontos de
documentacao tocados, mantendo-o como **cross-check read-only lateral** (nao
como etapa sequencial), e registrar a divergencia como achado — sem expandir o
escopo para reclassificar `analyze`.

**Rationale**: a varredura encontrou que varios pontos de documentacao ja
descrevem a sequencia **incluindo `analyze`** — `docs-site/index.md:103`,
`docs-site/manual/profiles.md:17-18`, `docs-site/manual/fluxo-sdd.md` (que
numera `[8] analyze`), `cli/lib/install.sh:91-93`,
`docs/01-briefing-discovery/briefing.md:11` — enquanto `_PL_STAGES_LIST` **nao
contem** `analyze`. Ou seja: SC-004 ("lista identica em todos os pontos") ja
falha hoje, antes desta feature, por um motivo alheio a ela.

O `CONTRIBUTING.md:61-63` mostra a representacao correta e ja adotada em um
ponto do repo: `analyze -. read-only cross-check .-> specify`, fora da cadeia
linear. Normalizar os demais pontos para essa forma resolve SC-004 sem
inventar uma decisao nova sobre o papel do `analyze` — apenas propaga a
representacao que o proprio repo ja escolheu.

**Alternatives considered**:
- Adicionar `analyze` a `_PL_STAGES_LIST`: decisao arquitetural nova, fora do
  escopo desta spec, e sem respaldo em nenhum requisito.
- Ignorar a divergencia: SC-004 ficaria insatisfeito por causa pre-existente,
  com a feature levando a culpa na verificacao.

## Decision 16: superficies auxiliares que reconhecem etapa

**Decision**: tres ajustes aditivos, todos de baixo risco:

| Superficie | Estado atual (verificado) | Ajuste |
|-----------|---------------------------|--------|
| `cli/lib/show-tip.sh:320-331` `_st_phase_to_skill()` | `case` fechado (`specify\|clarify\|plan\|create-tasks\|execute-task\|review-task\|checklist`) com fallback `*)` para dica aleatoria | adicionar `converge` ao `case` e ao texto de `--help` (`:559-560`) |
| `plugins/cstk/skills/agente-00c-runtime/scripts/commit-mode.sh:527-538` | `case` stage->scope com fallback `*) _scope="$_stage"` | adicionar `converge) _scope="converge"` explicito; sem o ajuste ja funciona (`docs(converge): ...`), mas por fallback |
| `tips/catalog.md` | nenhuma entrada `skill: converge` (gap pre-existente) | opcional/aditivo: nao bloqueia a feature |

**Rationale**: nenhuma dessas superficies falha de forma dura com uma etapa
desconhecida — todas tem fallback (`show-tip` cai em dica aleatoria,
`commit-mode` deriva o scope do proprio nome). Sao melhorias de qualidade, nao
pre-requisitos. Registrar evita que a ausencia seja lida depois como esquecimento.

**Confirmado sem necessidade de mudanca** (verificado no codigo, nao suposto):

- `state-ondas.sh:245-258` — `--add-etapa` valida **token regex**
  (`^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$`), nao enum: `converge` ja e aceito hoje.
- `state-decisions.sh:601` — `stage` e texto livre, sem enum.
- `references/state-db-schema.sql:32,141,163` — `current_stage`/`stage` sem
  `CHECK` de enum (os `CHECK` existentes sao de `status`,
  `termination_reason`, `human_blocks.status`).
- `mcp/state-server/src/tools/close_wave.ts:127-131` e
  `record_skill.ts:43-45` — validacao por regex de identificador, sem enum de
  etapa.
- `cli/lib/recall.sh:1425,2352-2361` — normalizacao de `executed_stages` por
  regex/GLOB de token, sem enum.
- `references/tier-gate-map.txt` — cobre **exclusivamente** o gate
  `owasp-security` (comentario `:23-26`); nao e mapa de etapas.
