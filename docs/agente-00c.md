# Agente-00C — orquestrador autônomo da pipeline SDD

> **Trilha avançada.** Não é necessário para o uso básico do toolkit (ver
> [Comece aqui](../README.md#comece-aqui)). Subsistemas de suporte:
> [Sessões paralelas](./cstk-session.md) e
> [Memória de conhecimento](./cstk-recall.md).

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
| `/feature-00c-resume <short-name> [--resposta-bloqueio "..."]` | Retomar após pausa ou schedule |
| `/feature-00c-abort <short-name> [--purge-backups]` | Aborto manual (SIGTERM + grace period 60s) |

Co-existência com `/agente-00c`: namespaces isolados
(`agente-00c-state/` vs `feature-00c-state/<short_name>/`). Features
paralelas no mesmo projeto são permitidas; concorrência com agente-00c
ativo é bloqueada (FR-026). Reuso integral do runtime POSIX
compartilhado (`agente-00c-runtime`). Detalhamento em
[`specs/_archived/feature-00c/`](./specs/_archived/feature-00c/).

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
| Helper POSIX (`is-enabled`, `set-enabled`, `guard-branch`, `stage-message`, `task-message`, `snapshot`, `stage-derived`, `finalize`) | `global/skills/agente-00c-runtime/scripts/commit-mode.sh` |
| Testes | `tests/test_commit-mode.sh` |
| Spec | [`specs/_archived/atomic-commit-pr/`](./specs/_archived/atomic-commit-pr/) |

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
| Hook + snippet de settings | `global/skills/agente-00c-runtime/hooks/pretooluse-bash-guard.sh` + `settings.snippet.json` |
| Provisionamento automático | `apply_guard_hooks()` em `cli/lib/hooks.sh` (escopo `project`) |
| Allowlist de hosts compartilhada | `cli/lib/trusted-hosts.sh` |
| Log auditável | `.claude/enforcement-log.jsonl` (por projeto-alvo) |
| Spec | [`specs/enforced-guards/`](./specs/enforced-guards/) |

Complementos do runtime: hook `PostToolUse` de métrica de tool calls
(sidecar append-only, v5.21.0) e envelope diagnóstico
`DIAG|severity|code|message|fix` nos helpers POSIX (`_diag.sh`, v5.22.0)
— o campo `fix` diz o próximo passo acionável para o agente.
