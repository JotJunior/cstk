# Research: roadmap-parallel-launch

**Feature**: `roadmap-parallel-launch`
**Created**: 2026-08-17
**Fase**: Phase 0 — resolucao de unknowns

> **Disciplina de veracidade (Constitution VI)**: cada decisao abaixo cita a
> fonte real consultada (arquivo:linha deste repo, ou comando de fato
> executado com sua saida literal). Nenhuma flag, exit code ou campo foi
> inferido por plausibilidade. Onde a fonte nao existe, a decisao esta
> marcada como **NAO COMPROVADO** e vira task de validacao empirica, nunca
> uma afirmacao.

---

## Decision 1 — Fonte de verdade da fronteira do DAG

**Decision**: reusar `plugins/cstk/skills/review-features/scripts/roadmap-status.sh --json`
como UNICA fonte de status por entrada; a fronteira e derivada em cima da
saida dele, nunca de leitura propria de `docs/roadmap.md`.

**Rationale**: o contrato ja existe e ja e fail-closed. Fonte literal
(`roadmap-status.sh:200-201`):

```
_json_line=$(printf '{"ordem":%s,"short_name":"%s","status":"%s","depende_de":%s}' \
  "$_ordem" "$_short_j" "$_status_j" "$_deps_json")
```

Flags reais (cabecalho do mesmo script, linhas 16-24): `--roadmap PATH`
(default `docs/roadmap.md`), `--specs-dir DIR` (default `docs/specs`),
`--json`. Exit codes reais (linhas 31-35): `0` sucesso (inclusive roadmap
valido com 0 entradas), `1` roadmap AUSENTE, `2` uso incorreto, `3` roadmap
presente mas invalido (sem header `# Roadmap`).

O enum de status vem de `docs/specs/roadmap-mode/contracts/roadmap-artifact.md` §5:
`nao-iniciada` (dir `docs/specs/<short>/` nao existe) | `em-andamento` (dir
existe sem `tasks.md`, OU `tasks.md` com >= 1 linha pendente `- [ ]`/`- [~]`)
| `concluida` (`tasks.md` sem nenhuma linha pendente). A §2.2 do mesmo
contrato PROIBE um campo `status` persistido dentro de `docs/roadmap.md` —
por isso a derivacao e sempre contra o portfolio real de specs.

**Alternatives considered**:
- *Parsear `docs/roadmap.md` diretamente no helper novo*: descartado —
  duplicaria a validacao fail-closed ja implementada (short-name fora de
  `^[a-z][a-z0-9-]*$` ou > 64 chars => entrada descartada; token de
  `depende-de` invalido => token descartado, entrada permanece) e criaria
  duas fontes de verdade divergentes para SC-004.
- *Persistir um campo `status` no roadmap*: proibido pela §2.2 do contrato
  vigente.

---

## Decision 2 — Onde a oferta de leva entra sem violar a ordem MUST de §9.quater

**Decision**: a oferta acontece no **command pai** (`/agente-00c`,
`/agente-00c-resume`), DEPOIS que o subagente orquestrador retorna com
`.execution.termination_reason = concluido_roadmap` — isto e, apos o passo 4
da sequencia MUST. A sequencia de 4 passos de §9.quater permanece
byte-identica; nada e inserido entre os passos.

**Rationale**: `plugins/cstk/agents/agente-00c-orchestrator.md:2049-2110`
define a ordem MUST: (1) `pipeline.sh detect-completion --stage roadmap`;
(2) `commit-mode.sh finalize`; (3) `state-ondas.sh end --motivo-termino
concluido`; (4) write multi-campo dos 5 campos terminais. O texto e explicito
que a ordem "jamais [pode ser] invertida" e que o passo 2 MUST vir antes do 4
por razao de seguranca (o hook `PreToolUse` de guarda de Bash so age com
`status: em_andamento`; promover antes deixaria o `git push` do finalize
rodar com a guarda desligada).

A oferta e **interativa com o operador**, e a fronteira command<->orquestrador
(FR-012 da spec; secao "Fronteira command↔orquestrador" de
`plugins/cstk/agents/agente-00c-feature-orchestrator.md`) reserva ao command
pai tudo que interage com o operador e spawna sessoes. O subagente
orquestrador nao pode nem perguntar nem lancar. Logo o unico ponto valido e
depois do retorno do subagente — que por construcao ja e depois do passo 4.

**Consequencia de seguranca declarada (nao mitigada por este plano)**: nesse
instante `.execution.status` ja e `concluida`, portanto o hook `PreToolUse` de
guarda de Bash trata a execucao como INATIVA e nao decide sobre os comandos da
leva (`cstk session start`, `tmux new-window`). Isso e o comportamento
existente do hook, nao uma regressao introduzida aqui — mas MUST estar
documentado no contrato de lancamento, e os comandos emitidos MUST ser
derivados de valores ja validados (short-names que passaram pelo filtro
fail-closed de `roadmap-status.sh`), nunca de texto livre do roadmap.

**Alternatives considered**:
- *Oferecer entre os passos 3 e 4 (execucao ainda ativa, guarda ligada)*:
  descartado — exigiria que o SUBAGENTE interagisse com o operador,
  violando FR-012 e a fronteira command↔orquestrador, que sao inegociaveis.
- *Oferecer dentro de `review-features`*: descartado — no modo roadmap a fase
  terminal e `roadmap`, nao `review-features` (mesmo trecho, linhas 2042-2047).

---

## Decision 3 — Como lancar a sessao-filha ja executando `/feature-00c`

**Decision**: **nao** alterar `cli/lib/session.sh`. O lancamento e composto em
dois passos desacoplados:

1. `cstk session start <short-name>` (SEM `--claude`) — cria worktree + branch
   isolados;
2. `tmux new-window -c <worktree> -n <short-name> -P -F '#{pane_id}' \
   'claude --name <nome-da-sessao-filha> "/feature-00c <short-name>"'`.

**Rationale**: a limitacao foi verificada no codigo, nao suposta.
`cli/lib/session.sh:543` termina o caminho `--claude` em:

```
  printf 'Iniciando Claude Code em %s...\n' "$_session_path"
  exec claude
```

`exec claude` **sem nenhum argumento** — logo `--claude` nao consegue nem
passar o prompt inicial (`/feature-00c <short>`) nem nomear a sessao. Ja o CLI
`claude` aceita ambos, verificado por execucao real nesta maquina:

```
$ claude --version
2.1.234 (Claude Code)
$ claude --help | head -1
Usage: claude [options] [command] [prompt]
$ claude --help | grep -- '--name'
  -n, --name <name>                     Set a display name for this session
```

Ou seja: o prompt e argumento POSICIONAL e existe `-n, --name`. Compondo o
lancamento pelo tmux, `--claude` simplesmente nao e usado e **nenhuma linha de
`cli/lib/` precisa mudar** — a feature fica inteiramente na metade "catalogo"
da instalacao (`cstk install`/`cstk update`), sem exigir `cstk self-update`.

O path da worktree e deterministico e tambem foi lido, nao suposto
(`cli/lib/session.sh:243`):

```
  printf '%s/%s-%s\n' "$_parent" "$_repo_name" "$_name"
```

isto e, `<diretorio-pai-do-repo>/<nome-do-repo>-<name>`.

As assinaturas de tmux usadas foram confirmadas por execucao real
(`tmux list-commands`, tmux 3.5a):

```
new-window (neww) [-abdkPS] [-c start-directory] [-e environment] [-F format] [-n window-name] [-t target-window] [shell-command]
split-window (splitw) [-bdefhIPvZ] [-c start-directory] ... [shell-command]
capture-pane (capturep) [-aCeJNpPqT] ... [-t target-pane]
```

`-c` (start-directory), `-n` (window-name), `-P` + `-F` (imprimir informacao
da janela criada — usado para capturar o identificador do pane, FR-006) e o
`shell-command` posicional sao todos reais nesta versao.

**Alternatives considered**:
- *Adicionar flag nova a `cstk session start` (ex.: passar prompt/nome ao
  `exec claude`)*: descartado por custo/beneficio — obrigaria a tocar
  `cli/lib/session.sh` (metade "runtime" da instalacao, exigindo
  `cstk self-update` alem de `cstk install`), ampliaria a superficie de um
  comando estavel e nao entrega nada que a composicao por tmux ja entregue.
  Fica registrado como evolucao possivel, nao como pre-requisito.
- *`cstk session start --claude` + `/feature-00c` digitado pelo operador*:
  descartado — quebra SC-001 (no maximo 1-2 rodadas de pergunta, sem
  comando montado a mao — redefinido na task 1.1.4/CHK018) e reintroduz
  o trabalho manual que a feature existe para eliminar.

---

## Decision 4 — Multiplexador: tmux, com degradacao por impressao de comandos

**Decision**: tmux e o alvo primario (ja fixado pela spec via clarify);
ausencia de tmux degrada para imprimir os comandos exatos (US3/FR-007).

**Rationale**: presenca verificada por execucao real neste ambiente
(`tmux -V` => `tmux 3.5a`). A deteccao usada sera `command -v tmux` (padrao
POSIX ja empregado nos scripts do repo). Nao ha integracao nativa do Claude
Code com tmux alem de agent teams (experimental, explicitamente fora de
escopo desta feature); portanto toda interacao com tmux e via comandos de
shell.

Importante: o caminho degradado NAO e um caminho inferior de correcao — os
comandos impressos sao literalmente os MESMOS que o caminho automatico
executaria (AC2 da US3), o que torna a paridade testavel por comparacao de
string.

**Alternatives considered**:
- *screen / zellij / Terminal.app AppleScript*: descartados pela clarify da
  spec (tmux e o unico com integracao oficial e ja em uso pelo operador);
  suportar mais de um multiplexador multiplicaria caminhos sem demanda real.

---

## Decision 5 — Notificacao sessao-filha -> sessao coordenadora

**Decision**: usar cross-session messaging do Claude Code (tools `SendMessage`
/ `ListAgents`), disparado pela sessao-filha ao alcancar estado terminal,
best-effort (FR-015). O endereçamento e feito pelo **nome de sessao**
atribuido no lancamento via `claude --name` (FR-006).

**ATUALIZACAO (ver Decision 10)**: esta afirmacao de "NAO COMPROVADO" foi o
estado ANTES da FASE 0. O experimento da task 0.1 (dec-037) comprovou o
wake-up dentro dos limites descritos na Decision 10 — o texto original
abaixo e preservado como registro historico do raciocinio pre-experimento.

**NAO COMPROVADO (estado pre-FASE 0) — e o nucleo de FR-013/SC-005**: que uma sessao coordenadora
**ociosa** de fato *acorde* ao receber a mensagem NAO esta comprovado. A
documentacao oficial consultada
(https://code.claude.com/docs/en/cross-session-messaging.md) descreve entrega
de texto plano **entre tool calls** — o que, lido literalmente, sugere que a
entrega depende de a sessao destino estar executando tool calls, e nao diz que
uma sessao parada em idle e retomada. A versao instalada nesta maquina
(`claude --version` => `2.1.234`) satisfaz o requisito minimo documentado
(>= 2.1.224), mas satisfazer a versao nao comprova o comportamento.

Consequencia direta no plano: a **primeira task da primeira fase** e um
experimento dedicado que comprova OU refuta esse wake-up e registra o
resultado (FASE 0, task 0.1). Ate esse resultado existir, nenhum artefato pode
afirmar que a notificacao acorda a coordenadora — e a via manual de checagem
(FR-013, segunda metade) MUST existir independentemente do resultado.

**Alternatives considered**:
- *Polling da coordenadora sobre o state das filhas*: descartado como
  mecanismo primario — a spec (clarify Q5) fixou notificacao imediata sem
  intervalo/timeout configuravel. Permanece, porem, como a base da **via
  manual** exigida por FR-013 (ver Decision 6), que nao e opcional.
- *Arquivo-sentinela + watcher*: descartado — introduz estado persistido novo,
  que a propria spec declara desnecessario ("nao ha scheduler nem estado
  persistido alem do ja existente").

---

## Decision 6 — Via manual de verificacao de status das filhas (FR-013)

**Decision**: a via manual reusa fontes ja existentes, sem estado novo:
`cstk session list` (worktrees ativas) cruzado com o status derivado por
`roadmap-status.sh --json` (que ja enxerga `docs/specs/<short>/tasks.md` de
cada feature).

**Rationale**: `cli/lib/session.sh` (cabecalho, linhas 10-13) documenta
`list — listar sessoes ativas`, e o bloco de `list` emite tambem `--json`
(array JSON camelCase com campo `current: bool`). Cruzar "worktree ainda
existe" com "status derivado da spec" cobre inclusive o edge case da
sessao-filha morta abruptamente sem notificar (worktree presente + status
ainda `em-andamento` + nenhuma notificacao recebida).

**Alternatives considered**:
- *Novo comando `cstk parallel status`*: descartado nesta feature —
  duplicaria informacao ja obtida por dois comandos existentes e criaria
  superficie de CLI nova sem necessidade comprovada.

---

## Decision 7 — Guarda anti-duplicidade (FR-011)

**Decision**: antes de lancar, verificar se ja existe worktree/branch para
aquele short-name via `git worktree list --porcelain` no repo coordenador,
casando a linha `branch refs/heads/<short-name>`.

**Rationale**: `cstk session start` ja falha com exit `6` (sessao ja existe)
e `7` (path destino ocupado por nao-worktree) — codigos lidos no cabecalho de
`cli/lib/session.sh:18-19`. A guarda propria existe para **nao chegar a
tentar**: a mensagem ao operador deve dizer "X ja esta em execucao, pulada da
leva", em vez de expor um exit code de falha. O parse escolhido e o mesmo
formato `--porcelain` que `session.sh` ja consome internamente (linhas
261-283: `/^branch refs\/heads\//`), o que evita parsear JSON sem `jq`
(proibido pelo Principio II nos scripts que acompanham skills).

**Alternatives considered**:
- *Parsear `cstk session list --json`*: descartado — exigiria parser JSON em
  POSIX sh puro dentro do helper, quando o `--porcelain` do git ja e
  line-oriented e e o formato que o proprio `session.sh` usa.

---

## Decision 8 — Deteccao de sobreposicao de artefatos (FR-014, US4)

**Decision**: heuristica textual sobre o bloco de prosa de cada entrada de
`docs/roadmap.md` (unica fonte disponivel antes do `/specify` da candidata —
fixado pela clarify Q4), emitindo AVISO informativo, jamais bloqueio.

**Rationale**: a §3.4 de `docs/specs/roadmap-mode/contracts/roadmap-artifact.md`
estabelece que cada entrada tem bloco de prosa. Como o texto e livre, a
heuristica so pode reportar **indicios** — e o AC2 da US4 ja preve
explicitamente o caso "informacao insuficiente => segue oferecendo sem
bloquear". Por isso a saida do aviso MUST ser redigida como indicio ("as
entradas X e Y mencionam ambas o artefato Z"), nunca como afirmacao de
conflito. Afirmar conflito a partir de heuristica textual seria fabricacao
(Principio VI).

**Alternatives considered**:
- *Ler `docs/specs/<short>/plan.md` das candidatas*: impossivel por
  construcao — candidatas da fronteira sao `nao-iniciada`, isto e, o diretorio
  `docs/specs/<short>/` sequer existe (Decision 1, enum de status).
- *Rodar `/specify` das candidatas so para descobrir sobreposicao*: descartado
  — inverteria o custo da feature (US4 e P4, mitigacao barata) e iniciaria
  features que o operador ainda nao escolheu, colidindo com FR-011.

---

## Decision 9 — Localizacao dos artefatos novos e metade da instalacao

**Decision**:

| Artefato novo | Diretorio | Metade | Teste exigido |
|---|---|---|---|
| `roadmap-frontier.sh` | `plugins/cstk/skills/review-features/scripts/` | catalogo (`cstk install`/`update`) | `tests/test_roadmap-frontier.sh` |
| `parallel-launch.sh` | `plugins/cstk/skills/agente-00c-runtime/scripts/` | catalogo (`cstk install`/`update`) | `tests/test_parallel-launch.sh` |
| prosa do command pai | `plugins/cstk/commands/agente-00c.md`, `agente-00c-resume.md` | catalogo | `tests/test_command-spawn-parallel-launch.sh` |
| prosa da sessao-filha | `plugins/cstk/commands/feature-00c.md` (+ resume) | catalogo | coberto pelo teste acima |

Nenhum arquivo em `cli/lib/` muda (ver Decision 3) — portanto **nao ha
metade "runtime"** nesta feature e `cstk self-update` nao e pre-requisito.

**Rationale**: `roadmap-frontier.sh` fica ao lado de `roadmap-status.sh`, sua
unica dependencia, dentro da MESMA skill — evitando o acoplamento cross-skill
que o proprio repo ja rejeitou por escrito. Fonte literal
(`plugins/cstk/skills/agente-00c-runtime/scripts/report.sh:439-440`):

```
# `roadmap-status.sh` (script de outra skill, review-features) para
# evitar acoplamento entre skills instaladas independentemente.
```

`parallel-launch.sh` fica no runtime porque seu consumidor e o command pai
(que ja resolve helpers desse diretorio) e porque ele nao depende de
`roadmap-status.sh` — recebe a fronteira ja calculada como entrada.

A convencao de teste e a documentada no `CLAUDE.md` do repo
(`plugins/cstk/skills/<X>/scripts/<n>.sh` => `tests/test_<n>.sh`), gateada por
`./tests/run.sh --check-coverage` (exit 1 em orfao).

**Alternatives considered**:
- *Tudo em `cli/lib/parallel.sh` como subcomando `cstk parallel`*: descartado
  — obrigaria `cstk self-update` alem de `cstk install`, exatamente o GOTCHA
  de sincronizacao pela metade documentado no `CLAUDE.md` ("fix funciona no
  repo mas nao na sessao"), sem ganho funcional.
- *`roadmap-frontier.sh` dentro de `agente-00c-runtime`*: descartado pelo
  precedente citado acima (acoplamento entre skills instaladas
  independentemente).

---

## Decision 10 — Resultado do experimento de wake-up (FASE 0, task 0.1)

**Decision**: o experimento empirico exigido pela Decision 5 (FR-013/SC-005)
foi executado e o resultado e **FUNCIONA**: uma sessao coordenadora
**ociosa** de fato acorda e processa ao receber `SendMessage` de uma
sessao-par, sem intervencao humana.

**Rationale — fonte real (dec-037, state.json de feature-00c, onda-006)**:
sessao-par `cstk-ef` (interactive, idle ha 13h segundo `ListAgents`) recebeu
`SendMessage` as `2026-08-17T23:27:51Z` e respondeu autonomamente
`ACK-RPL-0.1 sent_at=2026-08-17T23:27:51Z`; o ACK foi recebido pela sessao
coordenadora as `2026-08-17T23:28:21Z` (~30s de latencia), sem qualquer
intervencao do operador. `msg_id=28675a44-e98c-424b-9b4c-50e2df526f99`,
canal `uds:/tmp/cc-socks/4201.sock`.

**Limites declarados do experimento (nao ocultar)**:
- Amostra unica (N=1) — nao ha replicacao estatistica do comportamento.
- Nao testado: sessao coordenadora em modo background / Remote-Control-only
  (o experimento usou uma sessao `interactive`).
- Nao testado: sessao coordenadora no meio de uma tool call longa no momento
  do `SendMessage` (o experimento usou uma sessao ociosa em repouso).

**Consequencia direta**: a Decision 5 deixa de rotular o wake-up como
"NAO COMPROVADO" — o sub-mecanismo de wake-up esta comprovado dentro dos
limites acima. O fluxo de notificacao COMPLETO (parse fail-closed, payload
`[cstk-parallel] ...`, recalculo de fronteira) permanece `[PROPOSTA]` ate a
FASE 3 implementa-lo — o experimento comprova apenas que a entrega/wake-up
em si funciona, nao o protocolo inteiro descrito no contrato §6.

**Alternatives considered**: nenhuma — esta Decision documenta um resultado
medido (task 0.1), nao uma escolha de design entre alternativas.
