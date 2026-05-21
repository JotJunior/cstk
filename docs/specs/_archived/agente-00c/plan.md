# Implementation Plan: Agente-00C

**Feature**: `agente-00c` | **Date**: 2026-05-05 | **Spec**: [spec.md](./spec.md)

## Summary

O agente-00C e um orquestrador autonomo da pipeline Spec-Driven Development do
toolkit `claude-ai-tips`, invocavel via slash command `/agente-00c`. Ele recebe
uma descricao curta de POC/MVP e (opcionalmente) uma stack-sugerida, e executa
a pipeline `briefing → constitution → specify → clarify → plan → checklist →
create-tasks → execute-task → review-task → review-features` sem intervencao
humana entre etapas, gerando como entregavel-mor um relatorio auditavel rico em
decisoes, bloqueios e licoes aprendidas.

A abordagem tecnica derivada da pesquisa (Phase 0):

- **Forma**: slash command + agente custom orquestrador + agentes especializados
  (clarify-asker, clarify-answerer) — sem skill formal, pois progressive
  disclosure cabe nas instrucoes do agente custom.
- **Continuacao cross-sessao**: `/loop` dynamic mode com `ScheduleWakeup` para
  ondas curtas (~5min); `/schedule` Routines como fallback para pausas longas
  (>=1h, sobrevivem laptop suspenso).
- **Observabilidade de orcamento**: nao ha sinal nativo de tokens consumidos no
  Claude Code; orcamento via 3 proxies (tool calls da onda, wallclock da onda,
  tamanho do estado). FR-009 da spec ajustado em consequencia.
- **Persistencia**: JSON unico (`state.json`) com `schema_version` versionado +
  backups por onda em `state-history/`.
- **Padrao clarify**: dois subagentes mediados pelo pai, sem `SendMessage` —
  asker retorna perguntas+opcoes, pai spawna answerer com contexto, answerer
  usa heuristica de score 0..3 baseado em (briefing, constitution, stack-sugerida).
- **Recursividade**: max 3 niveis (filho, neto, bisneto); tool Agent bloqueada
  na definicao do bisneto.
- **Movimento circular**: buffer deslizante de 6 pares (problema, solucao)
  hashed.
- **Excecao de blast radius**: `gh issue create` em
  `JotJunior/claude-ai-tips` apenas para bugs impeditivos em skills globais,
  sem upload de relatorio/estado.

## Technical Context

**Language/Version**: instrucoes em markdown (frontmatter YAML) para slash
commands e agentes custom; sem linguagem de programacao tradicional. Tools
acionadas pelo agente: Bash (zsh, POSIX-friendly), Agent, Skill, Read, Write,
Edit, Glob, Grep, ScheduleWakeup. Uso de `gh`, `git`, `date`, `jq` (este via
fallback/instrucao — opcional, ver constitution toolkit II).

**Primary Dependencies**: Claude Code Opus 4.x ou Sonnet 4.6, com Auto mode
recomendado; harness com tool ScheduleWakeup disponivel; `gh` CLI autenticado
localmente; `git` no PATH.

**Storage**: arquivos planos em
`<projeto-alvo>/.claude/agente-00c-state/` (state.json, state-history/),
artefatos da pipeline em `<projeto-alvo>/docs/specs/<feature>/`, sugestoes em
`<projeto-alvo>/.claude/agente-00c-suggestions.md`, whitelist em
`<projeto-alvo>/.claude/agente-00c-whitelist`, relatorio em
`<projeto-alvo>/.claude/agente-00c-report.md`.

**Testing**: testes manuais via cenarios em `quickstart.md` (10 cenarios). Sem
suite automatizada nesta feature — o experimento usa execucoes reais como
"dataset de teste" e cada execucao alimenta o relatorio. Ver SC-010 para
metrica longitudinal.

**Target Platform**: Claude Code rodando localmente em macOS/Linux (joao usa
darwin 25.x). Continuacao de longa duracao usa `/schedule` Routines (cloud
Anthropic).

**Project Type**: meta-tool dentro do toolkit `claude-ai-tips` — nao e
biblioteca, nao e servico, e uma colecao de slash commands + agentes
custom + (opcionalmente) configuracao de skills.

**Performance Goals**:

- Onda tipica: 30-90 minutos wallclock, 30-80 tool calls.
- Geracao de relatorio parcial pos-aborto: < 60 segundos (SC-005).
- Validacao de schema na retomada: < 2 segundos.

**Constraints**:

- Subordinada a constitution do toolkit (zero coleta remota com excecao de
  issues no toolkit; POSIX sh em scripts; SDD recursivo).
- Subordinada a constitution da feature (auditabilidade total, pause-or-decide,
  idempotencia, autonomia orcada, blast radius confinado).
- Sem push, sem deploy externo, sem sudo, docker apenas local.

**Scale/Scope**:

- Escopo: experimento pessoal de joao. 1 operador. N execucoes ao longo do
  tempo (cada uma em projeto-alvo distinto).
- Tamanho do toolkit afetado: 5 novos artefatos (commands + agents). Sem
  mudanca em skills existentes; apenas leitura.

## Constitution Check

*GATE: deve passar antes do Phase 0. Re-checar apos Phase 1.*

### Toolkit Constitution v1.1.0 (`docs/constitution.md`)

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD recursivo (NON-NEGOTIABLE) | PASS | Esta feature segue SDD a si propria — briefing, constitution, specify, plan completos. Pipeline gera as proximas etapas. |
| II. POSIX sh puro em scripts (NON-NEGOTIABLE) | PASS (N/A na maior parte) | 00C nao introduz scripts `.sh` em `global/skills/*/scripts/`. Onde houver invocacao via tool Bash dentro de agente custom, manter compatibilidade POSIX (sem bashismos como `[[ ]]`, arrays, etc) por disciplina. Nao ha dependencia em `jq`/`ripgrep`/`fd`/`bats`. |
| III. Formato canonico de skill (NON-NEGOTIABLE) | PASS (N/A) | 00C nao e skill — e command + agents. Principio cobre apenas `global/skills/*`. Se uma skill for adicionada futuramente para 00C, devera respeitar formato. |
| IV. Zero coleta remota (NON-NEGOTIABLE) | PASS com excecao documentada | `gh issue create` em `JotJunior/claude-ai-tips` e excecao explicitamente autorizada pelo usuario no briefing. **Nao e telemetria/analytics/feature-flag/Sentry.** Conteudo enviado e bug report manualmente curado, nao log/relatorio. Relatorio e estado **permanecem locais**. Filtro de privacidade automatico aplicado antes de envio. |
| V. Profundidade sobre adocao (SHOULD) | PASS | 00C e ferramenta para o autor — nenhum esforco de marketing. Refinamentos visam reducao de retrabalho, nao visibilidade. |

### Feature Constitution v1.0.0 (`docs/specs/agente-00c/constitution.md`)

| Principio | Status | Notas |
|-----------|--------|-------|
| I. Auditabilidade Total (NON-NEGOTIABLE) | PASS | Schema do estado exige Decisao com 5 campos; relatorio tem secao obrigatoria de Decisoes; validacao na retomada checa preenchimento. |
| II. Pause-or-Decide (NON-NEGOTIABLE) | PASS | Heuristica de score 0..3 do clarify-answerer (research.md Decision 6) implementa o principio mecanicamente. |
| III. Idempotencia de Retomada (NON-NEGOTIABLE) | PASS | `schema_version` validado em cada onda; estado contem `proxima_instrucao` explicita; estado corrompido = bloqueio sem auto-correcao. |
| IV. Autonomia Limitada com Aborto (NON-NEGOTIABLE) | PASS | Orcamentos cravados no estado (recursividade, retro, ciclos, proxies); cada gatilho tem cenario de aborto em quickstart.md. |
| V. Blast Radius Confinado (NON-NEGOTIABLE) | PASS | Escrita restrita ao projeto-alvo (validado na invocacao); whitelist explicita (formato em research.md Decision 5); excecao gh-issue-toolkit limitada e documentada. |

**Resultado**: PASS em todas as 10 verificacoes (5 toolkit + 5 feature). Phase 0 pode prosseguir.

## Project Structure

### Documentation (this feature)

```
docs/specs/agente-00c/
├── briefing.md          # ratificado (Phase prior)
├── constitution.md      # ratificado (Phase prior)
├── spec.md              # ratificado (Phase prior, atualizado em FR-009 pela Decision 2)
├── plan.md              # este arquivo
├── research.md          # Phase 0 — 10 decisoes
├── data-model.md        # Phase 1 — entidades persistidas
├── quickstart.md        # Phase 1 — 10 cenarios de teste
└── contracts/           # Phase 1 — interfaces externas
    ├── cli-invocation.md   # /agente-00c, /agente-00c-abort, /agente-00c-resume
    ├── state-schema.md     # JSON do state.json + regras de validacao
    ├── report-format.md    # estrutura do relatorio final
    └── issue-template.md   # template de issue no toolkit GitHub
```

### Source Code (repository root)

Estrutura existente do toolkit `claude-ai-tips`:

```
.
├── CHANGELOG.md
├── CLAUDE.md
├── README.md
├── cli/                                    # cstk CLI (existente)
├── docs/
│   ├── 01-briefing-discovery/              # briefing do toolkit (existente)
│   ├── constitution.md                     # constitution do toolkit (existente)
│   ├── specs/
│   │   ├── agente-00c/                     # ESTA feature
│   │   ├── constitution-amend-optional-deps/  # existente
│   │   ├── cstk-cli/                       # existente
│   │   ├── fix-validate-stderr-noise/      # existente
│   │   └── shell-scripts-tests/            # existente
│   └── tasks-insights-2026-05.md           # existente, sem relacao
├── global/
│   └── skills/                             # 21 skills existentes (read-only para 00C)
├── language-related/                       # existente
├── scripts/                                # existente
└── tests/                                  # existente, suite de scripts shell
```

Adicoes desta feature (criadas no Phase 2 — `/create-tasks` e `/execute-task`):

```
global/
├── commands/                               # NOVO diretorio
│   ├── agente-00c.md                       # NOVO — slash command de invocacao
│   ├── agente-00c-abort.md                 # NOVO — aborto manual
│   └── agente-00c-resume.md                # NOVO — retomada apos pause/schedule
├── agents/                                 # NOVO diretorio
│   ├── agente-00c-orchestrator.md          # NOVO — agente custom orquestrador
│   ├── agente-00c-clarify-asker.md         # NOVO — gera perguntas
│   └── agente-00c-clarify-answerer.md      # NOVO — decide com score 0..3
└── skills/
    └── (sem alteracoes)                    # skills existentes permanecem intactas
```

**Structure Decision**: criar dois novos diretorios top-level dentro de `global/`
para acomodar o ponto de entrada (`commands/`) e os agentes custom
(`agents/`). Nao colocar dentro de `global/skills/` porque o 00C nao e skill —
ele orquestra skills. O `cstk install` (existente) precisara ser atualizado
para copiar tambem `global/commands/` e `global/agents/` para
`~/.claude/commands/` e `~/.claude/agents/` (criar tarefa correspondente em
create-tasks).

## Complexity Tracking

> Constitution Check passou em todos os principios — nenhuma violacao a
> justificar. Esta secao fica vazia.

---

## Re-check pos-Phase 1

**Design introduziu complexidade nao justificada?** Nao.

- Estado JSON unico em vez de SQLite/multiplo: simplicidade.
- Heuristicas (movimento circular, score, proxies) sao todas variantes
  de algoritmos lineares simples — nada exige biblioteca ou modelo
  externo.
- 3 slash commands + 3 agentes custom: minimo para cobrir invocacao,
  aborto, retomada e o padrao de dois atores. Reducao adicional
  comprometeria o requisito.

**Principios MUST continuam respeitados?** Sim — todos os 10. A excecao do
Principio IV do toolkit (gh issue create) e (a) explicitamente autorizada
no briefing, (b) escopada a bug reports curados, (c) sem upload de relatorio
ou estado. Nao reabre vetor de telemetria.

**Tabela de Constitution Check atualizada?** Nao houve mudanca de status
entre Phase 0 e pos-Phase 1.
