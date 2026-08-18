# Contrato: leva paralela — lancamento, identificacao e notificacao

**Feature**: `roadmap-parallel-launch`
**Arquivos**: `plugins/cstk/skills/agente-00c-runtime/scripts/parallel-launch.sh`
+ prosa de `plugins/cstk/commands/agente-00c.md` / `feature-00c.md`
**Status**: `[PROPOSTA — a validar na implementacao]`

> **Todo este documento e PROPOSTA**, exceto o que estiver marcado
> "**REAL**" com fonte citada. `[PROPOSTA — a validar na implementacao]`
> aplica-se a cada secao abaixo individualmente.

---

## 1. Alocacao de responsabilidades (FR-012 — inegociavel)

| Ator | Responsabilidade | Pode interagir com operador? | Pode abrir sessao? |
|---|---|---|---|
| **Command pai** (`/agente-00c`, `/agente-00c-resume`) | calcular fronteira, perguntar teto/selecao, avisar risco, lancar as filhas, receber notificacao, oferecer proxima leva | SIM | SIM |
| **Subagente orquestrador** (`agente-00c-orchestrator`) | nada desta feature | NAO | NAO |
| **`parallel-launch.sh`** (helper POSIX) | compor/emitir os comandos exatos; detectar tmux; guarda anti-duplicidade | NAO | NAO — `emit` so compoe/imprime os comandos, nunca executa (ver §4: superficie real e `emit \| check-tmux \| -h\|--help`, sem flag `--exec`); quem executa e o command pai |
| **Sessao-filha** (`/feature-00c <short>`) | executar SUA feature e notificar ao terminar | NAO (sobre a leva) | NAO |

Base **REAL**: a secao "Fronteira command↔orquestrador" de
`plugins/cstk/agents/agente-00c-feature-orchestrator.md` fixa que lock,
init e interacao com operador pertencem ao command pai; o subagente roda
dentro do lock dele e nunca pergunta nada.

---

## 2. Momento do disparo (**REAL** quanto a sequencia citada)

Ordem MUST de `plugins/cstk/agents/agente-00c-orchestrator.md:2049-2110`
(§9.quater), **inalterada** por esta feature:

```
1. pipeline.sh detect-completion --stage roadmap
2. commit-mode.sh finalize            (se atomic-commit habilitado)
3. state-ondas.sh end --motivo-termino concluido
4. write multi-campo dos 5 campos terminais
     .execution.termination_reason = concluido_roadmap
```

**PROPOSTA** — gatilho da oferta: o command pai, ao receber o retorno do
subagente E constatar `.execution.termination_reason == "concluido_roadmap"`,
executa o fluxo de leva paralela (§3). Isto ocorre necessariamente APOS o
passo 4; nada e inserido entre os 4 passos.

**Nota de seguranca (comportamento REAL do hook, nao regressao desta
feature)**: apos o passo 4 o status e `concluida`, e o hook `PreToolUse` de
guarda de Bash so age com `status: em_andamento` — logo os comandos da leva
rodam sem decisao da guarda. Mitigacao exigida: todo short-name usado na
composicao de comando MUST vir da saida de `roadmap-frontier.sh` (que so
emite short-names ja aprovados pela validacao fail-closed
`^[a-z][a-z0-9-]*$` de `roadmap-status.sh`), NUNCA de texto livre lido do
roadmap.

---

## 3. Fluxo da oferta (US1 — FR-002, FR-003, FR-004, FR-014)

1. Calcular fronteira: `roadmap-frontier.sh --exclude-active-from-repo <PAP>`.
2. Fronteira vazia, ou exit `1`/`3` => informar e **nao oferecer nada**
   (edge cases da spec). Fim.
3. Emitir avisos de sobreposicao (§6 do contrato de `roadmap-frontier.sh`),
   se houver — informativo, nunca bloqueante (FR-014 / AC3 da US4).
4. Perguntar ao operador se deseja lancar leva paralela. **Nesta mesma
   interacao** (FR-018/CHK103), declarar explicitamente que o teto de
   concorrencia (FR-003) e um limite de blast radius, NAO uma fronteira
   de isolamento de seguranca — ver §8.bis para o detalhe do que e
   compartilhado. Recusa => fim, com o comportamento manual atual
   intacto (FR-002 / AC4 da US1).
5. Perguntar o teto. **Default `2`** quando o operador so tecla Enter
   (FR-003, fixado pela clarify). Teto maior que o numero de candidatas =>
   lanca todas as candidatas, sem exigir atingir o teto (edge case da spec).
6. Se candidatas > teto, apresentar TODAS e deixar o operador escolher quais
   entram, dentro do limite (FR-004).
7. Lancar (§4) e reportar o que foi aberto.

---

## 4. `parallel-launch.sh` — uso proposto

```
parallel-launch.sh emit  --repo PATH --feature SHORT [--feature SHORT ...]
                         [--coordinator-name NAME]
parallel-launch.sh check-tmux
parallel-launch.sh -h | --help
```

| Subcomando | Efeito |
|---|---|
| `check-tmux` | exit `0` se `command -v tmux` resolve; exit `3` se ausente |
| `emit` | imprime, para cada `--feature`, o par de comandos exatos do lancamento (sem executar) |

**Decisao de desenho**: `emit` **nao executa**. Quem executa e o command pai
(que ja tem Bash e ja e o dono da interacao). Isso torna o caminho automatico
(US1) e o degradado (US3) o MESMO texto, comparavel byte a byte no teste —
que e como AC2 da US3 ("resultado equivalente ao caminho automatico") vira
assercao verificavel em vez de promessa.

### 4.1 Comandos emitidos por feature

```
cstk session start <SHORT>
tmux new-window -c "<WORKTREE>" -n "<SHORT>" -P -F '#{pane_id}' \
  claude --name "<CHILD_NAME>" "/feature-00c <SHORT>"
```

**Regras de quoting (obrigatorias — gate `owasp-security`, finding MEDIUM
"argument/command injection")**: `<WORKTREE>` e `<CHILD_NAME>` **MUST** ser
emitidos entre aspas duplas. `<WORKTREE>` deriva de
`<pai-do-repo>/<nome-do-repo>-<SHORT>`; o `<nome-do-repo>` NAO passa pelo
filtro `^[a-z][a-z0-9-]*$` (so o `<SHORT>` passa) e pode conter espaco ou
aspa. `<CHILD_NAME>` MUST ser validado por allowlist
`^cstk-feature/[a-z][a-z0-9-]*$` antes de entrar na linha, e
`--coordinator-name` por `^cstk-coord/[A-Za-z0-9._-]{1,64}$`.

Note que o `shell-command` do `tmux new-window` e passado como **argv
separado**, nao como string unica entre aspas simples: a forma
`'claude --name <X> "..."'` (string unica) faria uma aspa simples em `<X>`
escapar do literal. tmux aceita argv multiplo nessa posicao, o que remove a
camada de re-interpretacao de shell.

Elementos **REAIS** (verificados, nao supostos):

- `cstk session start <name> [--reset|--reuse] [--force] [--claude]` —
  `cli/lib/session.sh:77`.
- `<WORKTREE>` = `<pai-do-repo>/<nome-do-repo>-<SHORT>` — derivacao literal em
  `cli/lib/session.sh:243`: `printf '%s/%s-%s\n' "$_parent" "$_repo_name" "$_name"`.
- `--claude` **nao** e usado, porque `cli/lib/session.sh:543` faz
  `exec claude` sem argumento algum — nao aceita prompt nem nome.
- `claude [options] [command] [prompt]` e `-n, --name <name>` — saida real de
  `claude --help` (versao `2.1.234`), prompt e POSICIONAL.
- `new-window [-abdkPS] [-c start-directory] ... [-n window-name] ... [shell-command]`
  — saida real de `tmux list-commands` (tmux 3.5a). `-P -F '#{pane_id}'`
  imprime o identificador do pane criado.

### 4.2 Defesa em profundidade no `emit`

O gate `owasp-security` classificou como MEDIUM o fato de a mitigacao de §2
(short-name filtrado a montante por `roadmap-status.sh`) ser **camada unica**.
Portanto `parallel-launch.sh emit` **MUST** revalidar cada `--feature` contra
`^[a-z][a-z0-9-]*$` (<= 64 chars) no momento do emit, e recusar (exit `2`) o
que nao casar — mesmo que ja tenha vindo da fronteira. Custo zero, e elimina
a dependencia de uma unica fronteira de validacao.

Cada lancamento efetuado MUST ser registrado em
`<repo>/.claude/enforcement-log.jsonl` (mesmo arquivo ja usado pelas guardas
enforced), com `source: "parallel-launch"`.

**Schema da linha (CHK125)**: mesma forma de objeto JSON-lines ja usada por
`pretooluse-bash-guard.sh` (`_pbg_write_log`,
`plugins/cstk/skills/agente-00c-runtime/hooks/pretooluse-bash-guard.sh:311-335`
— **REAL**, campos `source`/`timestamp`/`outcome`/`command`), com os campos
especificos deste lancamento:

```json
{"source":"parallel-launch","timestamp":"<ISO8601 UTC>","short_name":"<SHORT>","repo":"<nome-do-repo>","worktree_path":"<WORKTREE>","outcome":"<launched|blocked-duplicate|blocked-invalid-feature>","command":"<par de comandos emitidos, scrubbed>"}
```

| Campo | Obrigatorio | Semantica |
|---|---|---|
| `source` | sim | literal `"parallel-launch"` |
| `timestamp` | sim | `date -u +%Y-%m-%dT%H:%M:%SZ`, mesma forma do hook |
| `short_name` | sim | `<SHORT>` ja validado por §4.2 (regex `^[a-z][a-z0-9-]*$`) |
| `repo` | sim | `<nome-do-repo>` (ver §5, componente de unicidade cross-repo) |
| `worktree_path` | sim | `<WORKTREE>` resolvido (§4.1) |
| `outcome` | sim | `launched` (par de comandos emitido e executado), `blocked-duplicate` (guarda anti-duplicidade de §5 do contrato `roadmap-frontier.sh` ou o TOCTOU-recompute deste §4.2 recusaram), ou `blocked-invalid-feature` (revalidacao de `--feature` recusou, exit `2`) |
| `command` | sim | o par de comandos exatos de §4.1, **MUST** passar por
`secrets-filter.sh scrub` ANTES de qualquer truncamento — mesma ordem
obrigatoria "scrub-antes-de-truncar" ja documentada no hook citado acima
(comentario `CHK020/task 1.4/Decision 10` em `pretooluse-bash-guard.sh`) |

Falha de escrita no log **MUST NOT** abortar o lancamento (efeito colateral
de auditoria, nao gate) — mesma politica best-effort do hook citado.

**TOCTOU (finding LOW)**: a guarda anti-duplicidade de §5 do contrato de
`roadmap-frontier.sh` roda ANTES da interacao com o operador, que tem duracao
ilimitada. O command pai **MUST** recomputar a guarda imediatamente antes de
executar o par de comandos de cada feature. O backstop final continua sendo o
exit `6` de `cstk session start` (**REAL** — `cli/lib/session.sh:18`).

Em ambiente **sem tmux** (`check-tmux` exit `3`), `emit` imprime a segunda
linha em forma manual equivalente (FR-007 / US3):

```
cd <WORKTREE> && claude --name <CHILD_NAME> "/feature-00c <SHORT>"
```

Nunca aguardar por tmux, nunca falhar silenciosamente (SC-003).

---

## 5. Identidade das sessoes (FR-006) `[PROPOSTA]`

| Papel | Nome proposto |
|---|---|
| Coordenadora | `cstk-coord/<nome-do-repo>` |
| Filha | `cstk-feature/<SHORT>` |

Atribuidos via `claude --name` (real; ver §4.1). A coordenadora so recebe o
nome se tiver sido iniciada com `--name` ou renomeada via `/rename` — se nao
tiver nome, a notificacao (§6) degrada e o operador usa a via manual (§7).
Essa degradacao MUST ser informada no momento do lancamento, nao descoberta
depois.

O `pane_id` capturado por `-P -F '#{pane_id}'` e o identificador
**complementar**, util para `tmux capture-pane -t <pane_id>` na via manual.

**Unicidade entre repositorios distintos (FR-006, CHK007)**: `<SHORT>`
sozinho NAO tem componente de repositorio — duas execucoes na MESMA
maquina, em repositorios diferentes, podem usar o mesmo short-name (ex.: dois repos distintos ambos rodando uma feature
`auth-basica`). Isso nao produz ambiguidade do lado de quem recebe a
notificacao (§6): cada sessao coordenadora tem nome
`cstk-coord/<nome-do-repo>` (proprio do repo que a lancou) e so recebe
mensagens endereçadas a ela — o `SendMessage` da filha (§6) e sempre
dirigido ao nome da coordenadora que a lancou, nunca a um nome
generico. O segundo componente da identidade (o repositorio) e
carregado pelo campo `repo=<nome-do-repo>` do payload (§6), nao pelo
`<CHILD_NAME>`. Consequencia pratica: o `<CHILD_NAME>` continua sendo
so `cstk-feature/<SHORT>` (nao precisa de sufixo de repo) porque a
identidade completa (feature, repo) so importa no ponto em que a
notificacao e processada, e la o par ja esta completo (nome da
coordenadora + campo `repo=`).

---

## 6. Notificacao de conclusao (FR-008, FR-015) `[PROPOSTA]`

Emissor: a sessao-filha, via prosa adicionada a `plugins/cstk/commands/feature-00c.md`
(e ao resume), no ponto em que a execucao alcanca estado terminal —
`concluida`, `abortada`, ou `aguardando_humano` sem resposta.

**Enum unico (sem traducao)**: o campo `outcome` da notificacao usa
VERBATIM os valores reais de `.execution.status`, cujo conjunto valido e
`em_andamento|aguardando_humano|abortada|concluida` (**REAL** —
`plugins/cstk/skills/agente-00c-runtime/scripts/state-validate.sh:250`).
Dos quatro, tres sao terminais para efeito de FR-008: `concluida`,
`abortada`, `aguardando_humano`. `em_andamento` nunca notifica.
NAO existe status `bloqueio_humano` nem `pausada` — `bloqueio_humano` e
valor de `--motivo-termino` de **onda** (`state-ondas.sh:854`), nao de
execucao, e nao deve aparecer como `outcome`.

Meio: tool `SendMessage` do Claude Code, endereçada ao nome da coordenadora
recebido no prompt de lancamento.

Payload (texto plano — o mecanismo transporta texto):

```
[cstk-parallel] feature=<SHORT> outcome=<concluida|abortada|aguardando_humano> repo=<nome-do-repo>
```

**Schema estrito, canal nao-confiavel (gate `owasp-security`, finding HIGH
"ASI07 — comunicacao inter-agente")**: `SendMessage` nao autentica remetente;
qualquer sessao pode forjar esta linha. Portanto o receptor **MUST**:

1. casar a mensagem inteira contra a regex ancorada
   `^\[cstk-parallel\] feature=([a-z][a-z0-9-]{0,63}) outcome=(concluida|abortada|aguardando_humano) repo=([A-Za-z0-9._-]{1,64})$`
   — qualquer sobra de texto na mensagem e **descartada**, nunca lida;
2. tratar a mensagem como **gatilho opaco**, NUNCA como instrucao: ela so
   informa "reavalie"; nao carrega acao, nome de comando nem caminho;
3. **nao confiar no conteudo**: antes de qualquer lancamento, recalcular a
   fronteira com `roadmap-frontier.sh` e lancar apenas o que a fronteira
   recalculada confirmar (§8). Uma notificacao forjada, no pior caso,
   provoca um recalculo redundante — nunca um lancamento fora da fronteira.

Regras duras:

- **Imediato**, sem intervalo nem timeout configuravel (clarify Q5 / FR-008).
- **Best-effort** (FR-015): falha de envio, coordenadora inexistente ou
  ausencia de confirmacao **MUST NOT** impedir a filha de concluir seu
  ciclo de vida normal. Falha => log local e segue.
- A filha **nunca** calcula fronteira, nunca oferece leva, nunca lanca
  sessao (FR-012).

**COMPROVADO (FASE 0, task 0.1 — dec-037)**: a coordenadora **ociosa** de
fato acorda e processa ao receber `SendMessage`, sem intervencao humana.
Sessao-par `cstk-ef` (interactive, idle ha 13h) recebeu `SendMessage` as
`2026-08-17T23:27:51Z` e respondeu autonomamente `ACK-RPL-0.1` as
`2026-08-17T23:27:51Z`, ACK recebido na coordenadora as `2026-08-17T23:28:21Z`
(~30s de latencia), `msg_id=28675a44-e98c-424b-9b4c-50e2df526f99` (ver
`research.md` Decision 10). **Limites**: amostra unica (N=1); nao testado em
sessao coordenadora background/Remote-Control-only nem no meio de uma tool
call longa. O sub-mecanismo de wake-up esta comprovado dentro desses limites
— o fluxo de notificacao COMPLETO descrito nesta secao (parse fail-closed,
payload `[cstk-parallel] ...`, recalculo de fronteira) permanece
`[PROPOSTA]` ate a FASE 3 implementa-lo.

---

## 7. Via manual de verificacao (FR-013, segunda metade) `[PROPOSTA]`

Independente do resultado da FASE 0 (§6 acima) — a via manual **MUST**
funcionar mesmo se o wake-up automatico algum dia deixar de funcionar em
alguma condicao nao coberta pelo experimento (background/Remote-Control-only,
tool call longa — ver limites na Decision 10 de `research.md`). O operador
roda esta composicao de comandos **ja existentes**, sem nenhum script novo:

```bash
# 1. worktrees/sessoes ativas no repo coordenador (REAL: session.sh:78,
#    subcomando `list`; suporta --json, array camelCase com campo current:bool)
cstk session list [--json]

# 2. status derivado por feature (REAL: roadmap-status.sh, cabecalho linhas
#    16-24) — path relativo ao repo coordenador (skill review-features)
~/.claude/skills/review-features/scripts/roadmap-status.sh --json \
  [--roadmap docs/roadmap.md] [--specs-dir docs/specs]

# 3. panes tmux vivos (REAL: tmux list-panes; so aplicavel quando a leva
#    foi lancada em multiplexador — caminho degradado sem tmux nao tem panes)
tmux list-panes -a
```

Interpretacao: worktree presente + `em-andamento` + sem notificacao recebida
=> filha possivelmente morta abruptamente (edge case declarado na spec).

---

## 8. Proxima leva (US2 — FR-009) `[PROPOSTA]`

Ao receber notificacao (§6), o command pai coordenador:

1. recalcula a fronteira (`roadmap-frontier.sh`, mesma invocacao de §3.1);
2. se surgiram candidatas novas, oferece a proxima leva pelo MESMO fluxo (§3).

Como o status vem de `roadmap-status.sh` (dir da spec + `tasks.md`), o efeito
de FR-010 e automatico: filha abortada / com bloqueio pendente deixa
`tasks.md` com linha pendente => `em-andamento` => dependentes seguem
inelegiveis. Nenhuma logica extra e necessaria — e o mesmo predicado da §4 do
contrato de `roadmap-frontier.sh`.

---

## 8.bis Limite de isolamento (declaracao explicita)

Gate `owasp-security`, finding MEDIUM (ASI03/ASI08): **worktree e isolamento
de working tree, NAO fronteira de seguranca.** As sessoes-filha compartilham
com a coordenadora e entre si: o `.git` common-dir (portanto `hooks/` e
`config`), `$HOME`, `~/.claude`, a `knowledge.db` global e as credenciais do
operador. Uma sessao-filha comprometida alcanca a coordenadora e o host.

Consequencias normativas (formalizadas como requisito em `spec.md`
FR-017/FR-018 — CHK101/CHK103):

- O paralelismo **nao** deve ser apresentado ao operador como sandbox
  (FR-018) — a declaracao explicita disso MUST ocorrer no passo 4 do
  fluxo de oferta (§3).
- O teto de concorrencia (FR-003, default 2) e tambem um limite de blast
  radius, nao so de rate-limit (FR-018).
- MUST existir kill switch trivial: `tmux kill-window -t <pane_id>` +
  `cstk session end <SHORT>` (ambos **REAIS**), documentados junto da via
  manual (§7). `cstk session end <SHORT>` tem um segundo papel, alem de
  kill switch: e o pre-requisito de recuperacao (FR-016) apos uma
  sessao-filha travar ou morrer sem notificar — remove a worktree de
  `git worktree list --porcelain`, o que faz a feature deixar de ser
  excluida pela guarda `--exclude-active-from-repo` (§5 do contrato de
  `roadmap-frontier.sh`) e voltar a ser candidata na proxima fronteira
  calculada.

---

## 9. Invariantes

- **INV-1**: a sequencia MUST de §9.quater nunca e alterada nem reordenada.
- **INV-2**: nenhuma decisao de leva parte de sessao-filha (FR-012).
- **INV-3**: nenhuma feature ja com worktree ativa e lancada de novo (FR-011).
- **INV-4**: ausencia de tmux degrada para texto executavel; jamais trava nem
  falha em silencio (FR-007 / SC-003).
- **INV-5**: notificacao e best-effort; sua falha nunca altera o ciclo de vida
  da filha (FR-015).
- **INV-6**: nenhuma afirmacao sobre wake-up de sessao ociosa antes do
  registro da FASE 0 (Principio VI).
- **INV-7**: todo valor interpolado em linha de comando e emitido entre
  aspas e revalidado por allowlist no ponto de uso (§4.1, §4.2).
- **INV-8**: notificacao recebida e gatilho opaco; nenhuma acao e derivada
  do seu conteudo sem reconfirmacao pela fronteira recalculada (§6, §8).
