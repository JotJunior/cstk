# Claude Code Toolkit

[![Latest Release](https://img.shields.io/github/v/release/JotJunior/claude-ai-tips?label=latest%20release&color=blue)](https://github.com/JotJunior/claude-ai-tips/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](#licença)
[![SemVer](https://img.shields.io/badge/SemVer-3.x-orange.svg)](./CHANGELOG.md)

Conjunto de ferramentas para aumentar a produtividade no desenvolvimento do dia a dia com
o [Claude Code](https://claude.ai/code).

Este repositorio contém **skills** e **hooks** que estendem as capacidades do Claude Code
para tarefas de documentação, desenvolvimento, segurança e qualidade de código.

> **Versão atual:** consulte a [release mais recente no GitHub](https://github.com/JotJunior/claude-ai-tips/releases/latest)
> para baixar o tarball ou acompanhar mudanças no [CHANGELOG.md](./CHANGELOG.md).
> A instalação recomendada é via `cstk` CLI (ver [seção Instalação](#instalação)).

## Estrutura

```
├── global/                     # Skills globais (independentes de linguagem)
│   └── skills/                 # 20 skills globais (cada skill é uma pasta)
│       ├── advisor/
│       ├── analyze/
│       ├── apply-insights/
│       ├── briefing/
│       ├── bugfix/
│       ├── checklist/
│       ├── clarify/
│       ├── constitution/
│       ├── create-tasks/
│       ├── create-use-case/
│       ├── execute-task/
│       ├── image-generation/
│       ├── initialize-docs/
│       ├── owasp-security/
│       ├── plan/
│       ├── review-features/
│       ├── review-task/
│       ├── specify/
│       ├── validate-docs-rendered/
│       └── validate-documentation/
├── language-related/           # Skills e hooks específicos por linguagem
│   ├── go/                     # Go
│   │   ├── skills/             # Skills para projetos Go
│   │   ├── hooks/              # Hooks de validação para Go
│   │   └── settings.json       # Configuração de hooks
│   └── dotnet/                 # .NET
│       └── skills/             # Skills para projetos .NET
```

### Anatomia de uma skill

Cada skill é uma pasta contendo um `SKILL.md` (ponto de entrada) e, conforme
o caso, subpastas que o Claude consulta sob demanda. Isso aplica o princípio
de *progressive disclosure* — o modelo paga só o contexto necessário no
momento de invocação, e carrega detalhes sob demanda:

```
skills/<nome>/
├── SKILL.md             # Ponto de entrada: quando invocar, regras de alto
│                        # nível, gotchas, ponteiros para subpastas
├── templates/           # Templates preenchíveis (feature-spec, plan, tasks...)
├── examples/            # Casos concretos (good.md vs bad.md)
├── references/          # Documentação de apoio (guias, catálogos, tabelas)
├── scripts/             # Scripts POSIX executáveis (next-id, scaffold, metrics...)
└── config.json          # Configuração por projeto (opcional)
```

Nem toda skill usa todas as subpastas — skills simples são só um `SKILL.md`.

## Skills Globais

Skills disponíveis em `global/skills/`, independentes de linguagem ou framework:

### Pipeline SDD (Spec-Driven Development)

Skills que formam o pipeline completo de desenvolvimento orientado por especificação:

| Skill | Trigger | Descrição |
|-------|---------|-----------|
| **briefing** | "briefing", "discovery", "novo projeto" | Entrevista estruturada de discovery coletando visão, usuários, restrições e contexto técnico |
| **constitution** | "constitution", "princípios do projeto" | Cria princípios imutáveis de governança que guiam decisões de arquitetura e qualidade |
| **specify** | "specify", "criar spec", "nova feature" | Transforma descrição natural em feature spec SDD com user stories, requisitos e critérios de aceite |
| **clarify** | "clarify", "resolver ambiguidades" | Identifica áreas sub-especificadas e resolve ambiguidades via perguntas estruturadas (max 5) |
| **plan** | "plan", "plano técnico" | Gera plano de implementação com pesquisa de tecnologias, modelo de dados e contratos de API |
| **checklist** | "checklist", "quality gate" | Gera checklists de validação de qualidade de requisitos — "Unit Tests for English" |
| **create-tasks** | "criar tarefas", "criar backlog" | Cria backlog de tarefas técnicas estruturado por fases com dependências |
| **analyze** | "analyze", "analisar consistência" | Análise read-only de consistência cross-artifact entre spec, plan, tasks e constitution |
| **execute-task** | "executar tarefa", "execute task" | Executa tarefa seguindo workflow obrigatório de 9 etapas |
| **review-task** | "revisar tarefas", "status das tarefas" | Gera relatório de status com progresso e recomendações |

### Skills Complementares

Skills independentes que podem ser usados em qualquer momento:

| Skill | Trigger | Descrição |
|-------|---------|-----------|
| **advisor** | "me aconselhe", "analise estratégica" | Conselheiro brutalmente honesto que disseca raciocínio e gera planos de ação |
| **bugfix** | "bugfix", "fix bug", "debug" | Protocolo estruturado de correção de bugs multi-camada |
| **create-use-case** | "criar caso de uso", "gerar UC" | Gera documentação de caso de uso com template de 15 seções e diagramas Mermaid |
| **image-generation** | Ao gerar imagens | Aprimora prompts de geração de imagens usando estrutura Subject-Context-Style |
| **initialize-docs** | "inicializar docs", "setup documentação" | Cria hierarquia padrão de documentação com 9 níveis |
| **apply-insights** | "aplicar insights", "aplicar playbook", "melhorar claude.md" | Analisa o projeto e aplica insights de uso comprovados ao CLAUDE.md, hooks e workflows. Renomeada de `insights` na 2.0.0 para evitar colisão com o `/insights` nativo do Claude Code (que tem função diferente — analisa suas sessões) |
| **owasp-security** | Ao revisar segurança | Revisão de segurança cobrindo OWASP Top 10:2025, API Security Top 10:2023, CI/CD Top 10, ASVS 5.0, LLM Top 10:2025, Agentic AI 2026, CWE Top 25:2025, NIST SP 800-63B-4, WebAuthn/Passkeys, OAuth 2.1, FAPI 2.0 e Post-Quantum Cryptography |
| **review-features** | "review features", "status global", "comparar features", "quais features priorizar" | Relatório comparativo de TODAS as features (cross-feature) com tabela agregada e sugestão de arquivar/abandonar/priorizar/continuar por feature |
| **validate-documentation** | "validar documentação", "verificar UC" | Valida documentos individuais contra padrões de qualidade estrutural |
| **validate-docs-rendered** | "validar renderização", "verificar diagramas" | Valida que a documentação Markdown renderiza corretamente (Mermaid, links internos, frontmatter, tabelas) |

---

### Pipeline SDD — Sequência de Uso

O pipeline SDD é a sequência recomendada para levar uma ideia desde o discovery até a implementação.
Cada skill consome os artefatos do anterior e alimenta o próximo.

```
 ┌──────────────┐
 │  DISCOVERY   │
 └──────┬───────┘
        │
   ① briefing          Entrevista de discovery → docs/01-briefing-discovery/briefing.md
        │                Coleta visão, usuários, escopo, restrições e stack.
        │                Pergunta UMA pergunta por vez (max 10).
        ▼
   ② constitution      Briefing → docs/constitution.md
        │                Define princípios MUST/SHOULD que governam todas as decisões.
        │                Validado contra artefatos existentes (propagação).
        ▼
 ┌──────────────┐
 │ ESPECIFICAÇÃO│
 └──────┬───────┘
        │
   ③ specify            Descrição natural → docs/specs/{feature}/spec.md
        │                Gera user stories priorizadas, requisitos funcionais,
        │                critérios de aceite e success criteria mensuráveis.
        │                Foco no QUE e POR QUÊ — nunca no COMO.
        ▼
   ④ clarify            Spec → Spec refinada (in-place)
        │                Escaneia ambiguidades por taxonomia (10 categorias).
        │                Faz max 5 perguntas com opções e recomendação.
        │                Integra respostas diretamente na spec.
        ▼
 ┌──────────────┐
 │ PLANEJAMENTO │
 └──────┬───────┘
        │
   ⑤ plan              Spec → docs/specs/{feature}/plan.md + research.md + data-model.md
        │                Pesquisa tecnologias, define modelo de dados,
        │                contratos de API e cenários de teste.
        │                Valida contra constitution (gate obrigatório).
        ▼
   ⑥ checklist          Plan + Spec → docs/specs/{feature}/checklists/{domain}.md
        │                "Unit Tests for English" — valida QUALIDADE dos requisitos,
        │                não da implementação. Domínios: ux, api, security, performance.
        ▼
 ┌──────────────┐
 │ IMPLEMENTAÇÃO│
 └──────┬───────┘
        │
   ⑦ create-tasks      Plan → Backlog de tarefas estruturado por fases
        │                Tarefas com IDs, criticidade e matriz de dependências.
        ▼
   ⑧ analyze           Spec + Plan + Tasks + Constitution → Relatório de consistência
        │                Detecta duplicações, ambiguidades, gaps de cobertura
        │                e violações de princípios. Estritamente READ-ONLY.
        ▼
   ⑨ execute-task      Task → Código implementado (workflow de 9 etapas)
        │                Análise → Localização → Planejamento → Implementação →
        │                Testes → Validação → Lint → Conclusão → Atualização.
        ▼
   ⑩ review-task       Tasks → Relatório de status com métricas e próximas ações
```

#### Quando usar cada skill

| Momento | Skill | Entrada | Saída |
|---------|-------|---------|-------|
| Projeto novo ou feature grande | `briefing` | Conversa interativa | `briefing.md` |
| Após briefing | `constitution` | Briefing + contexto | `constitution.md` |
| Nova feature | `specify` | Descrição em linguagem natural | `spec.md` |
| Spec com dúvidas | `clarify` | `spec.md` existente | `spec.md` atualizada |
| Spec pronta | `plan` | `spec.md` | `plan.md`, `data-model.md`, `contracts/` |
| Antes de implementar | `checklist` | Spec + Plan | `checklists/{domain}.md` |
| Plan pronto | `create-tasks` | `plan.md` | Backlog estruturado |
| Tasks criadas | `analyze` | Todos os artefatos | Relatório de consistência |
| Task específica | `execute-task` | ID da tarefa | Código + relatório |
| Acompanhamento | `review-task` | Arquivo de tasks | Relatório de progresso |

#### Atalhos — Nem sempre é preciso percorrer todo o pipeline

- **Feature simples**: `specify` → `plan` → `create-tasks` → `execute-task`
- **Bug fix**: `bugfix` (skill independente, não requer pipeline)
- **Projeto existente sem docs**: `initialize-docs` → `briefing` → `constitution`
- **Só precisa de tasks**: `create-tasks` direto (se já tem contexto suficiente)

---

### Workflow: execute-task

O skill `execute-task` impõe um workflow completo de 9 etapas:

1. **Análise** - Detectar contexto e ler documentação
2. **Localização** - Encontrar tarefa no arquivo de tarefas
3. **Planejamento** - Definir escopo e identificar padrões
4. **Implementação** - Executar a tarefa
5. **Testes** - Rodar testes se aplicável
6. **Validação** - Verificar qualidade e consistência
7. **Lint** - Checar formatação e padrões
8. **Conclusão** - Gerar relatório de execução
9. **Atualização** - Marcar tarefa como concluída

### Protocolo: bugfix

O skill `bugfix` implementa um protocolo de 8 etapas derivado da análise de 71 correções de bugs
em 134 sessões. Projetado para eliminar ciclos de "corrige-revela-corrige" em arquiteturas multi-serviço:

- Classifica complexidade (simples vs. multi-camada)
- Rastreia o fluxo de dados completo antes de qualquer alteração
- Mapeia DTOs, enums e nomes de campo em todas as fronteiras
- Implementa correções em todas as camadas afetadas de uma vez

## Agente-00C (orquestrador autônomo da pipeline SDD)

> **Status: experimental — esqueleto FASE 1 instalado.** Implementação
> operacional em andamento. Acompanhe o backlog em
> [`docs/specs/agente-00c/tasks.md`](./docs/specs/agente-00c/) (44 tarefas,
> 9 fases).

O `agente-00C` é um **orquestrador autônomo** da pipeline SDD do toolkit:
você invoca `/agente-00c` com uma descrição curta de POC/MVP e ele conduz
`briefing → constitution → specify → clarify → plan → checklist →
create-tasks → execute-task → review-task → review-features` sem
intervenção humana entre etapas, gerando como entregável-mor um
**relatório auditável** rico em decisões, bloqueios e lições aprendidas.

### Comandos expostos

| Comando | Função |
|---------|--------|
| `cstk 00c <path>` | **Atalho recomendado**: bootstrap interativo (cria diretório, coleta parâmetros e invoca `claude` já com `/agente-00c` montada) |
| `/agente-00c <descricao> [--stack ...] [--whitelist ...] [--projeto-alvo-path ...]` | Invocação direta no claude (alternativa ao `cstk 00c`) |
| `/agente-00c-resume [--projeto-alvo-path ...] [--resposta-bloqueio <id>:<resp>]` | Retoma após pausa ou schedule |
| `/agente-00c-abort [--projeto-alvo-path ...]` | Aborto manual |

> **`cstk 00c <path>`** é o caminho preferido para iniciar um POC/MVP novo:
> ele valida o path, cria o diretório, coleta descrição/stack/whitelist via
> prompts e dá `exec claude` com a slash command auto-submetida. Requer
> TTY interativo (não automatizável via pipe) e só opera em paths novos
> ou vazios — para retomar execução existente, use `/agente-00c-resume`
> diretamente no claude. Ver detalhes em
> [`docs/specs/cstk-cli/contracts/cstk-00c.md`](./docs/specs/cstk-cli/contracts/cstk-00c.md).

### Pré-requisitos

- **Claude Code** (Opus 4.x ou Sonnet 4.6 recomendado), **Auto mode**
  ativo para reduzir interrupções.
- **`gh` CLI autenticado** (necessário para abertura automática de issue
  no toolkit em caso de bug em skill global — FR-021).
- **`git` no PATH** (commit local entre ondas).
- **Docker local** (apenas se a stack-sugerida usar containers; orquestrador
  recusa qualquer `docker push`/deploy externo — Princípio V da feature).
- **Toolkit instalado via `cstk install`** (ver seção Instalação) para que
  os 3 slash commands e 3 agentes custom estejam disponíveis.

### Limitações conhecidas

- **Schedule limitado a 60-3600s via `ScheduleWakeup`**: continuação
  cross-sessão usa `ScheduleWakeup`; para pausas longas (>=1h ou
  bloqueios que só serão respondidos em horas/dias), o relatório
  parcial sugere criar uma routine manual via `/schedule` que sobrevive
  laptop suspend/restart (cloud Anthropic). Não há criação automática
  de routines — operador escolhe cron específico.
- **Sem observabilidade nativa de tokens consumidos**: o orçamento de
  sessão usa 3 proxies (tool calls da onda, wallclock, tamanho do estado).
  Não há sinal direto de quantos tokens foram gastos.
- **Sem `git push`, sem deploy externo, sem `sudo`**: por constituição da
  feature, blast radius é confinado ao `--projeto-alvo-path`. Tentativas
  são bloqueadas com aborto explícito.
- **Suíte de testes automatizada**: validação ocorre via execuções reais
  com cenários manuais (`docs/specs/agente-00c/quickstart.md`). Não há
  unit tests dos agentes custom (decisão consciente do briefing —
  experimento pessoal).
- **Schema de estado v1.0.0 sem migração**: se o schema evoluir, será
  uma feature nova; execuções pendentes precisarão ser concluídas ou
  abortadas antes de upgrade.

Detalhamento completo (briefing, constitution, spec com 31 FRs, plan,
research, threat-model, contracts, quickstart) em
[`docs/specs/agente-00c/`](./docs/specs/agente-00c/).

## Insights de Uso

A skill `apply-insights` aplica insights de uso ao projeto. Ela lê de
`~/.claude/insights/usage-insights.md` (se existir) e cai em best-practices
genéricas quando ausente.

O arquivo de insights é **por usuário**, não distribuído neste repositório:
gere o seu via a slash command nativa `/insights` do Claude Code (que
analisa suas sessões reais) ou mantenha um playbook curado manualmente.
A skill `apply-insights` deste toolkit é **prescritiva** (aplica o playbook
ao projeto) — distinta do `/insights` nativo, que é **introspectivo**
(analisa suas sessões). O rename da skill de `insights` → `apply-insights`
em 2.0.0 foi feito justamente para tornar essa separação explícita.

## Skills para Go

Skills em `language-related/go/skills/` para projetos Go:

| Skill | Trigger | Descrição |
|-------|---------|-----------|
| **commit** | "commit", "commitar" | Commits com conventional commits, suporte a submodules e mudanças multi-serviço |
| **create-report** | "criar relatório", "novo relatório" | Implementa novo tipo de relatório end-to-end em 4 serviços |
| **go-add-entity** | — | Adiciona uma nova entidade ao serviço |
| **go-add-migration** | — | Cria nova migration SQL |
| **go-add-test** | — | Gera testes para código Go |
| **go-add-consumer** | — | Adiciona consumer de mensagens (RabbitMQ) |
| **go-review-pr** | "review pr", "quality gate" | Quality gate pré-PR, diff-aware, com revisão em 8 etapas |
| **go-review-service** | — | Revisa qualidade de um serviço Go |

### Hooks para Go

Hooks em `language-related/go/hooks/` para validações automáticas:

| Hook | Descrição |
|------|-----------|
| **go-build-gate.sh** | Valida build antes de operações |
| **check-uncommitted.sh** | Verifica alterações não commitadas |
| **check-schema-prefix.sh** | Valida prefixo de schema nas migrations |
| **check-route-order.sh** | Verifica ordenação de rotas no router |

## Skills para .NET

Skills em `language-related/dotnet/skills/` para projetos .NET:

| Skill | Descrição |
|-------|-----------|
| **dotnet-create-entity** | Cria entidade com mapeamento EF Core |
| **dotnet-create-feature** | Gera feature completa (handler, validator, etc.) |
| **dotnet-create-project** | Scaffolding de novo projeto .NET |
| **dotnet-create-test** | Gera testes unitários e de integração |
| **dotnet-hexagonal-architecture** | Aplica arquitetura hexagonal |
| **dotnet-infrastructure** | Configura infraestrutura (DB, cache, messaging) |
| **dotnet-review-code** | Revisa qualidade de código .NET |
| **dotnet-testing** | Estratégias e padrões de teste |

## Instalação

### Via cstk CLI (recomendado)

A partir da versão `0.1.0`, o toolkit é instalado via `cstk` —
CLI POSIX shell que baixa, valida (SHA-256), instala e atualiza skills sem
exigir clone do repositório.

**One-liner de bootstrap** (instala `cstk` em `~/.local/bin/`):

```bash
curl -fsSL https://github.com/JotJunior/claude-ai-tips/releases/latest/download/install.sh | sh
```

Depois disso, comandos típicos:

```bash
cstk --version                       # confirma instalação
cstk install                         # instala perfil 'sdd' em ~/.claude/skills/
cstk install --profile all           # instala TODAS as 35 skills (inclui language-*)
cstk install advisor bugfix          # cherry-pick por nome
cstk update                          # aplica novas releases preservando edits locais
cstk update --force                  # sobrescreve skills com edição local
cstk list                            # lista skills instaladas + status
cstk doctor                          # detecta drift entre manifest e disco
cstk self-update                     # atualiza o próprio binário cstk
```

**Perfis disponíveis:**

| Perfil | Conteúdo | Uso típico |
|--------|----------|------------|
| `sdd` | 10 skills do pipeline Spec-Driven Development (briefing → review-task) | Instalação global default |
| `complementary` | 9 skills independentes (advisor, bugfix, owasp-security, etc.) | Complementa o pipeline SDD |
| `all` | Todas as 35 skills (sdd + complementary + language-*) | Instalação completa |
| `language-go` | Skills + hooks específicos para Go | Apenas em projetos Go |
| `language-dotnet` | Skills específicos para .NET | Apenas em projetos .NET |

Profile padrão quando nada é informado: `sdd`.

**Escopo de projeto** (`./.claude/skills/` no CWD em vez de `~/.claude/skills/`):

```bash
# Em um projeto Go: instala skills + hooks + merge de settings.json
cd ~/projetos/meu-app-go
cstk install --scope project --profile language-go

# Cherry-pick em escopo de projeto
cstk install --scope project create-use-case advisor

# Hooks de language-* SÃO instalados apenas em --scope project
# (em --scope global, hooks são omitidos com aviso no summary — FR-009c)
```

**Modo interativo** (seletor numerado em TTY):

```bash
cstk install --interactive   # lista perfis + skills numerados; seleção via toggle
cstk update --interactive    # mesmo, mas sobre skills do manifest
```

**Dry-run** (mostra plano sem escrever):

```bash
cstk install --dry-run --profile all
cstk update --dry-run
```

### Instalação manual (deprecated, ainda suportada)

Se preferir não usar o `cstk`, copia direta dos diretórios continua funcionando:

```bash
# Skills globais — instalação global
cp -r global/skills/ ~/.claude/skills/

# Skills de Go — copiar para projeto Go
cp -r language-related/go/skills/ seu-projeto/.claude/skills/
cp -r language-related/go/hooks/ seu-projeto/.claude/hooks/
cp language-related/go/settings.json seu-projeto/.claude/settings.json
```

Esta abordagem **não rastreia versões nem detecta drift** — você acaba
recorrentemente com uma cópia instalada divergente do source. Se for usar,
mantenha disciplina manual de `diff -r` (ver [`CLAUDE.md`](./CLAUDE.md)
§"Installed vs Source Drift"). O `cstk` resolve isso via manifest +
hash_dir.

### Estrutura de Destino

```
~/.claude/                  # Instalação global
├── skills/                 # (gerenciado por cstk: contém .cstk-manifest)
└── insights/               # (opcional, gerado pelo /insights nativo)

seu-projeto/
└── .claude/                # Instalação por projeto
    ├── skills/             # (gerenciado por cstk: --scope project)
    ├── hooks/              # (opcional, para hooks de linguagem)
    ├── settings.json       # (mesclado por cstk quando jq disponível)
    └── insights/           # (opcional)
```

### Documentação completa do cstk

- [`cli/README.md`](./cli/README.md) — visão técnica, convenções, processo de release
- [`docs/specs/cstk-cli/`](./docs/specs/cstk-cli/) — spec, plan, contracts, quickstart

## Sessões paralelas (`cstk session`)

Permite trabalhar em múltiplas features simultaneamente no mesmo repositório sem
colisão de working tree, branch HEAD ou `.claude/agente-00c-state/`. Isola cada
sessão em uma worktree git irmã do repo principal.

```bash
# Iniciar nova sessão (cria worktree + branch + .claude/ filtrado)
cstk session start iniciacao-membro
# → cria <parent>/<repo>-iniciacao-membro/ com branch iniciacao-membro

# Listar sessões ativas
cstk session list
# NAME              BRANCH              IDLE  STATUS   PATH
# iniciacao-membro  iniciacao-membro    0d    CURRENT  /home/jot/Projects/meta-gob-ms-iniciacao-membro
# oauth2-refresh    feat/oauth2         2d    *        /home/jot/Projects/meta-gob-ms-oauth2-refresh

# Abrir PR via gh (idempotente)
cstk session pr iniciacao-membro

# Encerrar sessão (com guards para dirty/unpushed/PR aberto)
cstk session end iniciacao-membro
# Ou forçar sem prompts:
cstk session end iniciacao-membro --force
```

**Quatro subcomandos**:

- `start <name> [--reset|--reuse] [--force]` — cria worktree + branch + `.claude/`
  filtrado (exclui `agente-00c-state/`, `agente-00c-archive/`, `insights/`,
  `settings.local.json`, `agente-00c-whitelist`, `agente-00c-report.md`,
  `agente-00c-suggestions.md`, `.agente-00c-state.lock`)
- `list [--json]` — tabela com `NAME BRANCH IDLE STATUS PATH`; marcadores
  combináveis `CURRENT,*,STALE`
- `end <name> [--force]` — remove worktree + branch local; prompt se há
  mudanças não commitadas, commits não pushados ou PR aberto
- `pr <name> [--draft] [--title T] [--body B] [--reviewer USER]` — push + abre
  PR via `gh pr create`; idempotente (retorna URL existente se PR já criado)

**Requisitos**: `git >= 2.36`, `gh` (obrigatório só para `pr`; opcional em `end`).

**Documentação completa**:
- [`docs/specs/cstk-session/spec.md`](./docs/specs/cstk-session/spec.md) — user stories, FRs, success criteria
- [`docs/specs/cstk-session/contracts/cli-session.md`](./docs/specs/cstk-session/contracts/cli-session.md) — exit codes (5-15), flags, output formats

## Convenções de Nomenclatura

| Tipo | Padrão | Exemplo |
|------|--------|---------|
| Casos de Uso | `UC-{DOMÍNIO}-{NNN}` | UC-CAD-001 |
| Decisões de Arquitetura | `ADR-{NNN}-{título}` | ADR-001-database |
| Regras de Negócio | `RN{NN}` | RN01 |
| Casos de Teste | `CT{NN}` | CT01 |
| Exceções | `E{NNN}` | E001 |

### Códigos de Domínio

Os códigos de domínio são **definidos por projeto**, não universais. A partir
de 1.1.0, as skills consultam os domínios reais via:

1. Campo `domains` em `config.json` (quando o projeto define explicitamente)
2. Glob de UCs existentes (quando o projeto já tem documentação)
3. Pergunta ao usuário via AskUserQuestion (quando ambos ausentes)

Exemplos comuns em projetos de negócio: `AUTH` (autenticação), `CAD`
(cadastros), `PED` (pedidos), `FIN` (financeiro). Use o que faz sentido no
seu domínio — a skill `create-use-case` não assume mais uma lista fixa.

## Hierarquia de Documentação

O skill `/initialize-docs` cria a seguinte estrutura:

```
docs/
├── 01-briefing-discovery/      # Requisitos iniciais, PDFs
├── 02-requisitos-casos-uso/    # Casos de uso (UC-*)
├── 03-modelagem-dados/         # DERs, schemas
├── 04-arquitetura-sistema/     # ADRs, diagramas
├── 05-definicao-apis/          # REST, gRPC, Webhooks, Messaging
├── 06-ui-ux-design/            # Wireframes, mockups
├── 07-plano-testes/            # Planos de teste
├── 08-operacoes/               # Runbooks
└── 09-entregaveis/             # Release notes
```

## Contribuindo

Contribuições são bem-vindas. Para adicionar novos skills ou hooks:

1. Siga a estrutura de pasta de uma skill existente (ver [Anatomia de uma skill](#anatomia-de-uma-skill))
2. Crie um `SKILL.md` como ponto de entrada — mantenha enxuto e use subpastas para conteúdo pesado
3. **description**: escreva como trigger condition, não resumo — "Use quando X, Y ou Z. Também quando mencionar A, B, C. NÃO use quando W."
4. **Gotchas**: documente armadilhas conhecidas — o conteúdo mais valioso de uma skill
5. **Templates/examples/references**: extraia conteúdo que o modelo consulta sob demanda
6. **Scripts**: prefira POSIX sh para operações determinísticas (next-id, validação, scaffold)
7. **config.json**: use para parâmetros que variam entre projetos
8. Teste com o Claude Code antes de submeter

## Versionamento

Este projeto segue [Semantic Versioning](https://semver.org/) e mantém um
[CHANGELOG.md](./CHANGELOG.md) com o histórico de mudanças.

## Licença

MIT
