[English](./agente-00c.md) · **Português (pt-BR)**

# Agente-00C — orquestrador autônomo da pipeline SDD

> **Trilha avançada.** Não é necessário para o uso básico do toolkit (ver
> [Comece aqui](../README.pt-BR.md#comece-aqui)). Subsistemas de suporte:
> [Sessões paralelas](./cstk-session.pt-BR.md) e
> [Memória de conhecimento](./cstk-recall.pt-BR.md).

> **Status: funcional e em uso pelo mantenedor** — porém **sem suíte de
> testes automatizada dos agentes custom** (validação por execuções reais,
> decisão consciente do briefing). Para adoção externa, trate como
> **experimental**: é um experimento pessoal de orquestração autônoma, não
> um produto com garantias de suporte. O backlog original (já concluído) está
> em [`specs/_archived/agente-00c/`](./specs/_archived/agente-00c/)
> (44 tarefas, 9 fases); a feature evoluiu muito desde então — ver
> feature-00c, model-routing e a memória de conhecimento.

O `agente-00C` é um **orquestrador autônomo** da pipeline SDD do toolkit:
você invoca `/agente-00c` com uma descrição curta de POC/MVP e ele conduz
`briefing → constitution → specify → clarify → plan → checklist →
create-tasks → execute-task → review-task → review-features`, **pausando
apenas em bloqueios reais** (decisões que exigem um humano) e entre ondas
agendadas — **não** é "dispare-e-esqueça". O entregável-mor é um **relatório
auditável** rico em decisões, bloqueios e lições aprendidas: ele existe
justamente para você revisar a rota, em vez de confiar cegamente na cadeia
de etapas.

> **Dica — prompt ideal para o briefing**: quanto mais completa a descrição
> inicial, menos perguntas o agente faz na etapa `briefing`. Use o template
> preenchível em
> [`templates/briefing-prompt-ideal.md`](./templates/briefing-prompt-ideal.md)
> — mapeado 1:1 com as seções do briefing e com blocos extras para
> arquiteturas complexas, com guia de poda para entregas simples.

## Comandos expostos

| Comando | Função |
|---------|--------|
| `cstk 00c <path>` | **Atalho recomendado**: bootstrap interativo (cria diretório, coleta parâmetros e invoca `claude` já com `/agente-00c` montada) |
| `/agente-00c <descricao> [--stack ...] [--whitelist ...] [--projeto-alvo-path ...]` | Invocação direta no claude (alternativa ao `cstk 00c`) |
| `/agente-00c-resume [--projeto-alvo-path ...] [--resposta-bloqueio <id>:<resp>]` | Retoma após pausa ou schedule |
| `/agente-00c-abort [--projeto-alvo-path ...]` | Aborto manual |

> **`cstk 00c <path>`** é o caminho preferido para iniciar um POC/MVP novo:
> ele valida o path, cria o diretório, coleta descrição/stack/whitelist via
> prompts e dá `exec claude` com a slash command auto-submetida. Requer
> TTY interativo e só opera em paths novos ou vazios — para retomar execução
> existente, use `/agente-00c-resume` diretamente no claude. Detalhes em
> [`specs/_archived/cstk-cli/contracts/cstk-00c.md`](./specs/_archived/cstk-cli/contracts/cstk-00c.md).

## Pré-requisitos

- **Claude Code** (Opus 4.x ou Sonnet 4.6 recomendado), **Auto mode**
  ativo para reduzir interrupções.
- **`gh` CLI autenticado** (necessário para abertura automática de issue
  no toolkit em caso de bug em skill global — FR-021).
- **`git` no PATH** (commit local entre ondas).
- **Docker local** (apenas se a stack-sugerida usar containers; orquestrador
  recusa qualquer `docker push`/deploy externo — Princípio V da feature).
- **Toolkit instalado via `cstk install`** para que os slash commands e
  agentes custom estejam disponíveis.

## Limitações conhecidas

- **Schedule limitado a 60-3600s via `ScheduleWakeup`**: continuação
  cross-sessão usa `ScheduleWakeup`; para pausas longas (>=1h ou
  bloqueios que só serão respondidos em horas/dias), o relatório
  parcial sugere criar uma routine manual via `/schedule` que sobrevive
  laptop suspend/restart (cloud Anthropic).
- **Sem observabilidade nativa de tokens consumidos**: o orçamento de
  sessão usa proxies (tool calls da onda, wallclock, tamanho do estado).
- **Sem `git push` cru, sem deploy externo, sem `sudo`**: por constituição da
  feature, blast radius é confinado ao `--projeto-alvo-path`. O caminho
  confinado de push+PR existe apenas no finalize do modo atomic-commit.
- **Suíte de testes automatizada**: validação ocorre via execuções reais
  com cenários manuais
  ([`specs/_archived/agente-00c/quickstart.md`](./specs/_archived/agente-00c/quickstart.md)).
- **Schema de estado sem migração automática entre versões maiores**:
  execuções pendentes precisam ser concluídas ou abortadas antes de upgrade.

Detalhamento completo (briefing, constitution, spec com 31 FRs, plan,
research, threat-model, contracts, quickstart) em
[`specs/_archived/agente-00c/`](./specs/_archived/agente-00c/).

## Feature-00C — variante de escopo de feature individual

A partir de v3.13.0, o toolkit oferece `/feature-00c` como variante do
agente-00c focada em **uma feature** dentro de projeto que JÁ possui
`briefing.md` + `docs/constitution.md` ratificados. Pipeline reduzida:
`specify → clarify → plan → checklist → create-tasks → execute-task →
review-task` (sem briefing/constitution/review-features, que são
pré-requisitos validados em FR-PRE-001..004).

| Comando | Quando usar |
|---------|-------------|
| `/feature-00c "<descricao>" [<short-name>]` | Adicionar feature nova em projeto existente |
| `/feature-00c "<incremento>" --reopen=<short-name>` | Reabrir feature concluída para receber um incremento (v7.3.0 — ver abaixo) |
| `/feature-00c-resume <short-name> [--resposta-bloqueio "..."]` | Retomar após pausa ou schedule |
| `/feature-00c-abort <short-name> [--purge-backups]` | Aborto manual (SIGTERM + grace period 60s) |

Co-existência com `/agente-00c`: namespaces isolados
(`agente-00c-state/` vs `feature-00c-state/<short_name>/`). Features
paralelas no mesmo projeto são permitidas; concorrência com agente-00c
ativo é bloqueada (FR-026). Reuso integral do runtime POSIX
compartilhado (`agente-00c-runtime`). Detalhamento em
[`specs/_archived/feature-00c/`](./specs/_archived/feature-00c/).

### Reabrindo uma feature concluída (`--reopen`)

Até a v7.3.0 uma feature concluída era um beco sem saída: reinvocar
`/feature-00c` com o mesmo short-name morria no init porque o estado já
existia, e a única saída era editar estado à mão ou abrir uma feature
paralela — fragmentando a spec e perdendo a identidade do que é,
conceitualmente, a mesma capacidade. O
`/feature-00c "<incremento>" --reopen=<short-name>` resolve isso:

- **A execução anterior é preservada como round imutável** e a execução
  nova inicia apontando para ela. Primitiva de rotação: `state-rounds.sh`
  (`next-label`, `rotate`, `recover`, `list`); o commit da rotação é um
  único `mv` de diretório (o único primitivo atômico do POSIX) com
  journal + staging, e `recover` resolve interrupção por comando — sem
  edição manual de arquivo. Rounds com zero-padding (`r01`, `r02`) para
  ordenação lexicográfica correta.
- **O incremento pousa na spec existente, não numa paralela**: a spec
  arquivada é restaurada e o `specify` grava o incremento como
  `## Delta Requirements`; o `create-tasks` detecta a reabertura e
  **apenda** uma fase nova ao `tasks.md`, preservando as tarefas já
  concluídas (número da fase calculado por `next-task-id.sh --phase`).
- **Parecer advisory + bloqueio humano antes de tocar disco**: o command
  emite parecer reabrir-vs-criar-feature-nova e pausa para a decisão
  humana antes de qualquer escrita.
- **Sonda de trabalho pendente fail-closed**: `commit-mode.sh
  probe-pending-work` verifica trabalho não integrado (branch não mesclada
  na default, PR aberto). Um campo só recebe valor concreto de leitura
  bem-sucedida e parseada; qualquer outro desfecho mantém `unknown` +
  `probe_status=skipped-*` — nunca infere `merged=no` a partir de falha.
- **Proveniência por round no índice de conhecimento**: o `cstk recall
  --reindex` dá namespace de proveniência por round, então rounds
  preservados nunca são contados como execução ativa nem duplicam contagem
  (incluindo rounds no backend SQLite).

Spec: [`specs/feature-reopen/`](./specs/feature-reopen/)
([`contracts/reopen-flow.md`](./specs/feature-reopen/contracts/reopen-flow.md),
[`contracts/state-rounds.md`](./specs/feature-reopen/contracts/state-rounds.md),
[`contracts/pending-work-probe.md`](./specs/feature-reopen/contracts/pending-work-probe.md)).

## Roteamento de modelos por onda (model-routing)

> **BREAKING v4.0.0** — o model-routing **deixou de ser audit-only**
> (premissa da v3.15.0, revogada): o harness atual aceita `model` no spawn
> de subagente, e o modelo agora **É APLICADO** a cada onda.

No início de cada onda, o **command pai** (`/agente-00c`, `/feature-00c` e
resumes) chama `model-routing.sh wave-select` e aplica o modelo retornado no
spawn do orquestrador. A base é um mapa determinístico fase→modelo
(`references/phase-model-map.txt`, POSIX puro):

| Fase | Faixa | Modelo-piso |
|------|-------|-------------|
| `plan`, `analyze`, `constitution` | profunda | **opus** |
| `specify`, `clarify`, `checklist`, `create-tasks`, `briefing` | média | **sonnet** |
| `execute-task` | rasa | **sonnet** (piso; refinável ↑opus / ↓haiku) |
| `validate-docs`, `review-task` | rasa | **haiku** |
| fase não listada | — | `manter-atual` (nunca erro) |

Precedência de resolução:
`override manual do operador > escalada mid-onda (opus) > refino model-selector > mapa fase→modelo`.

A skill **model-selector** virou camada de refino opcional (só em
`execute-task` com `--task-text`): pode elevar para opus ou rebaixar para
haiku sobre o piso do mapa, citando sinais. Contrato **suggest-only**
preservado: a skill nunca troca modelo sozinha — quem aplica é o command pai.
Auditoria sugerido-vs-aplicado via `model-routing-report.sh aggregate`
(consumida pelo `review-task` §4.5).

Specs: [`specs/_archived/model-routing-por-onda/`](./specs/_archived/model-routing-por-onda/)
(mecanismo atual) e
[`specs/_archived/agente-00c-model-routing/`](./specs/_archived/agente-00c-model-routing/)
(feature original, audit-only revogado).

## Modo atomic-commit (opt-in)

A partir de v5.12.0, os orquestradores oferecem modo **atomic-commit**
opt-in: cada etapa de artefato gera um commit Conventional Commits
automático, e cada grupo de tasks `execute-task` com `outcome=pass` gera
um commit ranged ao final da onda. O finalize terminal dispara push + PR via
`cstk session pr` (push direto permanece bloqueado pelo `bash-guard.sh`).

Desde v5.23.0, o staging é **por allowlist derivada** do diff da onda
(subcomandos `snapshot`/`stage-derived` do `commit-mode.sh`) — nunca
`git add -A`: arquivos untracked alheios à execução jamais entram nos
commits automáticos.

| Componente | Localização |
|------------|-------------|
| Helper POSIX (`is-enabled`, `set-enabled`, `guard-branch`, `stage-message`, `task-message`, `snapshot`, `stage-derived`, `finalize`) | `plugins/cstk/skills/agente-00c-runtime/scripts/commit-mode.sh` |
| Testes | `tests/test_commit-mode.sh` |
| Spec | [`specs/_archived/atomic-commit-pr/`](./specs/_archived/atomic-commit-pr/) |

## Modo roadmap e levas paralelas de features

O modo roadmap (opt-in no início do `/agente-00c`) encurta a cadeia para
`briefing → constitution → roadmap`: o orquestrador escreve `docs/roadmap.md`
(entradas ordenadas com `depende-de`, um DAG acíclico de dependências) e a
execução termina com `termination_reason=concluido_roadmap`. Desde a feature
`roadmap-parallel-launch` a **sessão coordenadora não para aí**: o command
pai (`agente-00c.md` §6.ter / resume §9.ter) computa a *fronteira* — entradas
`nao-iniciada` cujas dependências estão todas `concluida`, status derivado de
`docs/specs/` por `roadmap-status.sh`, nunca de um campo `status` no roadmap
— e oferece uma **leva paralela**:

1. `roadmap-frontier.sh --specs-dir docs/specs [--json]
   [--exclude-active-from-repo <repo>]` lista as candidatas elegíveis
   (worktrees já ativas são filtradas); um *indício de sobreposição* ("as
   entradas X e Y mencionam ambas `<token>`") pode ser impresso a partir da
   prosa do roadmap, sanitizado e rotulado `roadmap-prose-untrusted` — nunca
   redigido como conflito confirmado.
2. O operador é perguntado se quer lançar, com **teto default de 2** features
   por leva (também limite de blast radius — worktree é isolamento de
   filesystem, **não** sandbox de segurança: as filhas compartilham `.git`,
   `$HOME`, `~/.claude` e credenciais) e, acima do teto, quais.
3. `parallel-launch.sh emit --repo <repo> --feature <short> [...]` **só
   imprime** os comandos de lançamento por feature — `cstk session start
   <short>` + `tmux new-window ... claude --name ... "/feature-00c <short>"`,
   ou a forma degradada `cd ... && claude ...` quando `check-tmux` diz que o
   tmux está ausente (exit 3). Quem executa é o pai; o script nunca executa
   nada e nunca toca `cli/lib/session.sh`.
4. Quando uma execução-filha chega a estado terminal (`concluida`, `abortada`
   ou `aguardando_humano`), `feature-00c.md` §5.quater envia, best-effort via
   a tool `SendMessage` do Claude Code, o gatilho opaco
   `[cstk-parallel] feature=<short> outcome=<...> repo=<repo>`. A
   coordenadora (`agente-00c.md` §6.quater) faz o parse fail-closed com
   `parallel-notification-parse.sh check` (regex ancorada na mensagem
   inteira; qualquer sobra ⇒ exit 1) e **recomputa a fronteira** antes de
   oferecer a próxima leva — uma notificação forjada causa, no máximo, um
   recálculo redundante (INV-8).

Verificado empiricamente (dec-037 da feature): uma sessão Claude Code ociosa
há 13 h acordou ao receber `SendMessage` e respondeu em ~30 s sem intervenção
humana. Kill switch: `tmux kill-window -t <pane>` + `cstk session end
<short>`. Via manual de verificação: `cstk session list`,
`roadmap-status.sh --json`, `tmux list-panes -a` (§6.bis).

| Componente | Localização |
|-----------|-------------|
| Fronteira + indício de sobreposição | `plugins/cstk/skills/review-features/scripts/roadmap-frontier.sh` |
| Composição do lançamento (`emit`, `check-tmux`) | `plugins/cstk/skills/agente-00c-runtime/scripts/parallel-launch.sh` |
| Parser da notificação (fail-closed) | `plugins/cstk/skills/agente-00c-runtime/scripts/parallel-notification-parse.sh` |
| Prosa dos commands pai | `plugins/cstk/commands/agente-00c.md` §6.ter/§6.quater, `agente-00c-resume.md` §9.ter/§9.quater, `feature-00c.md` §5.quater |
| Testes | `tests/test_roadmap-frontier.sh`, `tests/test_parallel-launch.sh`, `tests/test_parallel-notification-parse.sh`, `tests/test_command-spawn-parallel-launch.sh` |
| Specs | [`specs/roadmap-mode/`](./specs/roadmap-mode/), [`specs/roadmap-parallel-launch/`](./specs/roadmap-parallel-launch/) |

## Guardas enforced (hook PreToolUse + integridade + allowlist de hosts)

As guardas de segurança do runtime (`bash-guard.sh`, checksum do painel,
esquema de URL) eram **advisory**. Três frentes passaram a ser **enforced**
(não dependem do orquestrador lembrar):

1. **Hook `PreToolUse`/`Bash` fail-closed**: intercepta todo comando Bash
   de uma execução `agente-00c`/`feature-00c` ativa e delega a
   `bash-guard.sh check` — nunca reimplementa a regra. Falha do próprio
   mecanismo também bloqueia (`MECANISMO_FALHOU`, distinguível de
   `REGRA_VIOLADA`). Sessões manuais do operador ficam intactas. Decisões
   auditáveis em `.claude/enforcement-log.jsonl` (scrub de segredos antes
   de truncar).
2. **`cstk serve` fail-closed por padrão**: ausência de `.sha256` do pacote
   bloqueia (`unverifiable-blocked`); bypass explícito e auditado via
   `--allow-unverified`/`CSTK_SERVE_ALLOW_UNVERIFIED=1`; divergência de
   checksum bloqueia sempre, sem bypass.
3. **Allowlist de hosts confiáveis** (`CSTK_TRUSTED_RELEASE_HOSTS`, match
   exato case-insensitive, `file://` isento) aplicada em `cstk serve`,
   `cstk install --from` e `cstk self-update --from`.

| Componente | Localização |
|------------|-------------|
| Hook + snippet de settings | `plugins/cstk/skills/agente-00c-runtime/hooks/pretooluse-bash-guard.sh` + `settings.snippet.json` |
| Provisionamento automático | `apply_guard_hooks()` em `cli/lib/hooks.sh` (escopo `project`) |
| Allowlist de hosts compartilhada | `cli/lib/trusted-hosts.sh` |
| Log auditável | `.claude/enforcement-log.jsonl` (por projeto-alvo) |
| Spec | [`specs/_archived/2026-07-28-enforced-guards/`](./specs/_archived/2026-07-28-enforced-guards/) |

Complementos do runtime: hook `PostToolUse` de métrica de tool calls
(sidecar append-only, v5.21.0) e envelope diagnóstico
`DIAG|severity|code|message|fix` nos helpers POSIX (`_diag.sh`, v5.22.0)
— o campo `fix` diz o próximo passo acionável para o agente.
