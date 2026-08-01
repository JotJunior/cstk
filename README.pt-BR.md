[English](./README.md) · **Português (pt-BR)**

# Claude Code Toolkit

[![Latest Release](https://img.shields.io/github/v/release/JotJunior/cstk?label=latest%20release&color=blue)](https://github.com/JotJunior/cstk/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](./LICENSE)
[![SemVer](https://img.shields.io/badge/SemVer-5.x-orange.svg)](./CHANGELOG.md)
[![Docs Site](https://img.shields.io/badge/docs-jotjunior.github.io/cstk-blue?logo=readthedocs)](https://jotjunior.github.io/cstk/)
[![Publish Site](https://github.com/JotJunior/cstk/actions/workflows/publish-site.yml/badge.svg?branch=main)](https://github.com/JotJunior/cstk/actions/workflows/publish-site.yml)

Conjunto de ferramentas para aumentar a produtividade no desenvolvimento do dia a dia com
o [Claude Code](https://claude.ai/code): **skills** e **hooks** para
documentação, desenvolvimento, segurança e qualidade de código.

> **Quem mantém / para quem é.** Mantido por uma pessoa, otimizado primeiro
> para o fluxo do mantenedor (microserviços em Go). As partes concretas —
> skills, hooks, CLI — são de uso geral; a **trilha avançada** (orquestrador
> autônomo) é mais experimental.

> **Versão atual:** [release mais recente](https://github.com/JotJunior/cstk/releases/latest)
> · histórico no [CHANGELOG.md](./CHANGELOG.md). Instalação recomendada via
> `cstk` CLI (ver [Instalação](#instalação)).

## Comece aqui

Duas trilhas, dependendo do que você procura:

| Trilha | Para quem | Onde ir |
|--------|-----------|---------|
| **Básico** | Quer produtividade no dia a dia — especificar, revisar, corrigir, documentar com algumas skills | Esta seção + [Skills Globais](#skills-globais) |
| **Avançado** | Quer o orquestrador autônomo rodando o pipeline SDD inteiro sozinho | [Trilha avançada](#trilha-avançada-orquestrador-autônomo) |

### Trilha básica em 3 passos

```bash
# 1. Instale (uma vez por máquina)
curl -fsSL https://github.com/JotJunior/cstk/releases/latest/download/install.sh | sh
```

```text
# 2. Abra o Claude Code no seu projeto e invoque uma skill pelo gatilho:
#    "especifica essa feature: ..."   → specify  (ideia → spec)
#    "revisa a segurança desse código" → owasp-security
#    "corrige esse bug: ..."          → bugfix   (investigação multi-camada)
#    "me aconselhe sobre esse plano"  → advisor  (crítica estratégica)
```

```text
# 3. Pronto. As skills são auto-invocadas por contexto — você descreve a
#    intenção em linguagem natural e o gatilho dispara a skill certa.
```

> Não precisa do orquestrador autônomo para começar. Ele é a trilha avançada
> — adote quando quiser que o pipeline SDD rode de ponta a ponta sem você
> conduzir cada etapa.

### Depois de instalar: ative a captura de custo e tokens

Duas variáveis de ambiente — **sem API key, sem Admin key, sem organização**;
funciona em plano de assinatura:

```bash
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_METRICS_EXPORTER=prometheus
```

Com elas, cada onda do orquestrador passa a registrar o consumo **real**
(custo e tokens, separando `main` de `subagent`) em `.waves[N].otel_usage`,
e o painel mostra o gasto por onda. Sem elas tudo é no-op e o campo fica
`null` — ausente, nunca zero fabricado. Ponha no seu `~/.zshrc`/`~/.bashrc`
para não perder ondas por esquecimento.

Nada sai da máquina (exporter em `127.0.0.1:9464`) e labels de identidade são
descartados antes de tocar o disco.

> **Mais de um processo do Claude Code ao mesmo tempo?** Só o primeiro
> consegue o bind da porta fixa — os demais não medem nada em silêncio
> (`otel_usage` `null` em toda onda). Use o launcher de porta por processo
> mostrado em [Custo real por onda](#custo-real-por-onda-otel-usagesh) para
> cada processo ganhar seu próprio exporter automaticamente.

## Estrutura

```
├── global/                     # Skills globais (independentes de linguagem)
│   └── skills/                 # 22 skills globais (cada skill é uma pasta)
│       ├── advisor/
│       ├── agente-00c-runtime/ # runtime POSIX interno (não user-invocável)
│       ├── analyze/
│       ├── apply-insights/
│       ├── briefing/
│       ├── bugfix/
│       ├── checklist/
│       ├── clarify/
│       ├── constitution/
│       ├── converge/           # reconcilia spec/plan/tasks vs código real
│       ├── create-tasks/
│       ├── e2e-integration-flow/ # testes E2E de integração full-stack (Playwright)
│       ├── execute-task/
│       ├── initialize-docs/
│       ├── model-selector/     # heurística de roteamento de modelo (sugestor)
│       ├── owasp-security/
│       ├── plan/
│       ├── review-features/
│       ├── review-task/
│       ├── specify/
│       ├── validate-docs-rendered/
│       └── validate-documentation/
├── language-related/           # Skills e hooks específicos por linguagem
│   └── go/                     # Go — ver docs/go-toolkit.md
├── cli/                        # Binário cstk + libs POSIX
└── docs/                       # Documentação por tópicos (ver índice abaixo)
```

### Anatomia de uma skill

Cada skill é uma pasta com um `SKILL.md` (ponto de entrada) e, conforme o
caso, subpastas consultadas sob demanda (*progressive disclosure* — o modelo
paga só o contexto necessário no momento da invocação):

```
skills/<nome>/
├── SKILL.md             # Quando invocar, regras de alto nível, gotchas
├── templates/           # Templates preenchíveis
├── examples/            # Casos concretos (good.md vs bad.md)
├── references/          # Documentação de apoio
├── scripts/             # Scripts POSIX determinísticos
└── config.json          # Configuração por projeto (opcional)
```

Nem toda skill usa todas as subpastas — skills simples são só um `SKILL.md`.

## Skills Globais

Skills em `global/skills/`, independentes de linguagem ou framework.

### Pipeline SDD (Spec-Driven Development)

Sequência recomendada para levar uma ideia do discovery à implementação.
Detalhes, diagrama do fluxo e atalhos em
[docs/sdd-pipeline.md](./docs/sdd-pipeline.pt-BR.md).

| Skill | Trigger | Descrição |
|-------|---------|-----------|
| **briefing** | "briefing", "discovery", "novo projeto" | Entrevista estruturada de discovery (visão, usuários, restrições, stack) |
| **constitution** | "constitution", "princípios do projeto" | Princípios imutáveis de governança que guiam decisões |
| **specify** | "specify", "criar spec", "nova feature" | Descrição natural → feature spec SDD (stories, requisitos, success criteria). Gate: todo requisito exige >=1 cenário; seção opcional Delta Requirements (specs vivas) |
| **clarify** | "clarify", "resolver ambiguidades" | Resolve ambiguidades da spec via perguntas estruturadas (max 5) |
| **plan** | "plan", "plano técnico" | Plano de implementação: pesquisa, modelo de dados, contratos |
| **checklist** | "checklist", "quality gate" | "Unit Tests for English" — valida qualidade dos REQUISITOS; gaps viram tarefas |
| **create-tasks** | "criar tarefas", "criar backlog" | Backlog de tarefas por fases com dependências e criticidade |
| **analyze** | "analyze", "analisar consistência" | Análise read-only de consistência cross-artifact |
| **execute-task** | "executar tarefa", "execute task" | Executa tarefa seguindo workflow obrigatório de 9 etapas |
| **review-task** | "revisar tarefas", "status das tarefas" | Relatório de status com progresso e recomendações |

### Skills Complementares

| Skill | Trigger | Descrição |
|-------|---------|-----------|
| **advisor** | "me aconselhe", "analise estratégica" | Conselheiro brutalmente honesto que disseca raciocínio e gera planos de ação |
| **bugfix** | "bugfix", "fix bug", "debug" | Protocolo estruturado de correção de bugs multi-camada |
| **converge** | "converge", "o código bate com a spec?" | Reconcilia spec/plan/tasks contra o código ATUAL e apenda gaps como nova fase de tasks. Gate incondicional entre execute-task e review-task nos orquestradores |
| **e2e-integration-flow** | "e2e", "playwright", "validar fluxo completo" | Testes E2E de integração full-stack (UI → API → banco → fila → efeitos colaterais) |
| **initialize-docs** | "inicializar docs", "setup documentação" | Cria hierarquia padrão de documentação com 9 níveis |
| **apply-insights** | "aplicar insights", "melhorar claude.md" | Aplica insights de uso comprovados ao CLAUDE.md, hooks e workflows — ver [Insights de uso](#insights-de-uso) |
| **owasp-security** | Ao revisar segurança | Revisão guiada por checklist (OWASP Top 10:2025, ASVS 5.0, LLM/Agentic, NIST, OAuth 2.1...). Não substitui auditoria/pentest |
| **review-features** | "status global", "comparar features" | Relatório cross-feature com sugestão de arquivar/abandonar/priorizar; a ação de archive aplica os deltas ao corpus de specs vivas |
| **validate-documentation** | "validar documentação", "verificar UC" | Valida documentos individuais contra padrões estruturais |
| **validate-docs-rendered** | "validar renderização", "verificar diagramas" | Valida que o Markdown renderiza (Mermaid, links, frontmatter, tabelas) |

## Trilha avançada (orquestrador autônomo)

> **Experimental** — funcional e em uso pelo mantenedor, sem garantias de
> suporte para adoção externa.

O `/agente-00c` conduz a pipeline SDD inteira sobre um projeto-alvo, pausando
apenas em bloqueios reais; o `/feature-00c` faz o mesmo para UMA feature em
projeto existente. Subsistemas: roteamento de modelos por onda, modo
atomic-commit (commits automáticos + push/PR no finalize), guardas enforced
(hook fail-closed), sessões paralelas em worktrees e memória de conhecimento
cross-feature consultada antes de decidir.

| Tópico | Documento |
|--------|-----------|
| Orquestradores `/agente-00c` + `/feature-00c`, model-routing, atomic-commit, guardas | [docs/agente-00c.md](./docs/agente-00c.pt-BR.md) |
| Sessões paralelas (`cstk session`) | [docs/cstk-session.md](./docs/cstk-session.pt-BR.md) |
| Memória de conhecimento (`cstk recall`) | [docs/cstk-recall.md](./docs/cstk-recall.pt-BR.md) |
| Painel web de métricas (`cstk serve`) | [docs/cstk-serve.md](./docs/cstk-serve.pt-BR.md) |

## Insights de uso

A skill `apply-insights` é **prescritiva**: lê seu playbook
(`~/.claude/insights/usage-insights.md`, por usuário — gere via `/insights`
nativo do Claude Code) e o aplica ao projeto. Distinta do `/insights` nativo,
que é **introspectivo** (analisa suas sessões).

<!-- --8<-- [start:install-section] -->
## Instalação

### Via cstk CLI (recomendado)

O toolkit é instalado via `cstk` — CLI POSIX shell que baixa, valida
(SHA-256), instala e atualiza skills sem exigir clone do repositório.

**One-liner de bootstrap** (instala `cstk` em `~/.local/bin/`):

```bash
curl -fsSL https://github.com/JotJunior/cstk/releases/latest/download/install.sh | sh
```

Depois disso, comandos típicos:

```bash
cstk --version                       # confirma instalação
cstk install                         # instala perfil 'sdd' em ~/.claude/skills/
cstk install --profile all           # instala TODAS as 29 skills (inclui language-go)
cstk install advisor bugfix          # cherry-pick por nome
cstk update                          # aplica novas releases preservando edits locais
cstk update --force                  # sobrescreve skills com edição local
cstk list                            # lista skills instaladas + status
cstk doctor                          # detecta drift entre manifest e disco
cstk self-update                     # atualiza o próprio binário cstk + cli/lib
```

> **`install`/`update` tocam só o catálogo** (skills/commands/agents em
> `~/.claude/`); o runtime (`cli/lib/*.sh` + binário) atualiza via
> **`cstk self-update`**.

**Perfis disponíveis:**

| Perfil | Conteúdo | Uso típico |
|--------|----------|------------|
| `sdd` | 17 skills: pipeline Spec-Driven Development completa (briefing → review-features) + runtime interno, model-selector e os 4 gates de qualidade dos orquestradores | Instalação global default |
| `complementary` | 11 skills independentes (advisor, bugfix, e2e-integration-flow, etc.) | Complementa o pipeline SDD |
| `all` | Todas as 29 skills (sdd + complementary + language-go) | Instalação completa |
| `language-go` | Skills + hooks específicos para Go | Apenas em projetos Go |

Profile padrão quando nada é informado: `sdd`.

**Escopo de projeto** (`./.claude/skills/` no CWD em vez de `~/.claude/skills/`):

```bash
# Em um projeto Go: instala skills + hooks + merge de settings.json
cd ~/projetos/meu-app-go
cstk install --scope project --profile language-go

# Cherry-pick em escopo de projeto
cstk install --scope project advisor owasp-security

# Hooks de language-* SÃO instalados apenas em --scope project
# (em --scope global, hooks são omitidos com aviso no summary — FR-009c)
```

### Hooks do runtime 00c (`cstk hooks`)

Os três hooks do runtime 00c — `pretooluse-bash-guard.sh` (guarda
fail-closed de Bash), `posttooluse-tool-call-tick.sh` e
`posttooluse-agent-usage.sh` (métricas por onda) — só rodam num projeto-alvo
depois de copiados para `.claude/hooks/` **e** registrados em
`.claude/settings.json`.

O `cstk install --scope project agente-00c-runtime` faz isso, mas também
copia a skill, 6 commands e 7 agents para dentro do repo. Quando você quer
apenas os hooks:

```bash
cd ~/projects/meu-projeto-alvo
cstk hooks install                    # toca só .claude/hooks/ + settings.json
cstk hooks install --dry-run          # mostra o plano sem escrever
cstk hooks install --project-path ../outro-projeto
```

Sem esse passo a guarda de Bash fica inerte e `tool_calls`/`agent_usage`
ficam zerados em todas as ondas. Para conferir o estado atual sem escrever
nada:

```bash
guard-hooks-status.sh check --projeto-alvo-path .
```

### Custo real por onda (`otel-usage.sh`)

Os contadores OpenTelemetry nativos do Claude Code são incrementados **a
cada API request** e carregam o label `query_source` (`main` / `subagent` /
`auxiliary`). Um snapshot no início e outro no fim da onda dão o consumo
exato dela — inclusive o do próprio orquestrador, que o hook de spawn nunca
consegue capturar (o spawn do orquestrador *envolve* a onda, então o
`tool_result` dele chega depois que a onda já fechou).

Ativa-se com duas variáveis de ambiente — **sem API key, sem Admin key, sem
organização**; funciona em plano de assinatura:

```bash
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_METRICS_EXPORTER=prometheus
```

O `state-ondas.sh start`/`end` passa a preencher `.waves[N].otel_usage`
sozinho. Sem as variáveis tudo é no-op e o campo fica `null` — **ausente,
nunca zero fabricado**.

Medido numa task delegada: `main` $0,156, `subagent` $0,141, `auxiliary`
$0,001 — o subagente era ~47% do gasto, exatamente a fatia que o painel
mostrava como `—`.

O exporter escuta em `127.0.0.1:9464`; nada sai da máquina. Labels de
identidade (`user_email`, `user_id`, `user_account_*`, `organization_id`)
são descartados no snapshot e nunca tocam o disco. Use `CSTK_OTEL_ENDPOINT`
para apontar a outra porta.

**Vários processos do Claude Code ao mesmo tempo? Dê uma porta a cada um.**
Só UM processo consegue o bind da porta fixa `9464` — o primeiro que abrir
ganha. Qualquer outro processo (outra aba do terminal, outro projeto) falha o
bind em silêncio: as métricas dele não são expostas em lugar nenhum, os
snapshots por onda scrapeiam as sessões velhas do processo *vencedor*, e o
guard do delta descarta o resultado corretamente — `otel_usage` sai `null` em
**todas as ondas** daquela execução, com o painel sem custo nenhum. Caso real:
um `claude -c` de dois dias de outro projeto segurava a porta e uma execução
inteira de 16 ondas não mediu nada.

A correção é uma função-launcher no seu `~/.zshrc` que pede ao OS uma porta
livre a cada lançamento (bind na porta `0` deixa o kernel escolher) e aponta o
scraper do cstk para ela via `CSTK_OTEL_ENDPOINT` — hooks e scripts do runtime
rodam dentro do processo do Claude, então herdam as duas variáveis:

```zsh
# Um exporter OTel por processo do claude: OS sorteia porta livre a cada lancamento.
claude() {
  local _otel_port
  _otel_port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()' 2>/dev/null)
  if [ -n "$_otel_port" ]; then
    OTEL_EXPORTER_PROMETHEUS_PORT=$_otel_port \
    CSTK_OTEL_ENDPOINT="http://127.0.0.1:${_otel_port}/metrics" \
    command claude "$@"
  else
    command claude "$@"   # sem python3: cai na porta default fixa
  fi
}
```

Zero configuração por sessão: cada `claude` que você digita ganha um exporter
isolado e uma medição isolada. De bônus, o guard "exatamente uma sessão
cresceu" do delta passa a ver só as sessões daquele processo — os descartes
por ambiguidade (`null` por sessões concorrentes) praticamente desaparecem.
O wrapper só cobre processos lançados do seu shell — o que nascer por fora
(IDE, app desktop) continua na porta default fixa.

Diagnóstico rápido quando o painel não mostra custo em onda nenhuma: veja
quem é o dono da porta e se o diretório de trabalho dele é mesmo o projeto
da execução:

```bash
lsof -nP -iTCP:9464 -sTCP:LISTEN     # quem e o dono da porta do exporter?
lsof -p <PID> | grep cwd             # ...e de qual projeto?
```

Ou deixe o runtime decidir: `otel-usage.sh preflight` responde "ESTA sessão
vai ser medida?" deterministicamente — `status=ok` (exporter pertence a um
ancestral deste processo), `port-conflict` com PID e cwd do dono (exit 3),
`exporter-down` (exit 4), `disabled` ou `unverified`. Os commands 00c rodam
o preflight no diagnóstico inicial e repassam qualquer aviso ao operador
antes da onda-001.

**Modo interativo** (seletor numerado em TTY) e **dry-run**:

```bash
cstk install --interactive   # lista perfis + skills numerados; seleção via toggle
cstk install --dry-run --profile all
cstk update --dry-run
```

### Instalação manual (deprecated, ainda suportada)

Copia direta dos diretórios continua funcionando (`cp -r global/skills/
~/.claude/skills/`), mas **não rastreia versões nem detecta drift** — ver
[`CLAUDE.md`](./CLAUDE.md) §"Installed vs Source Drift". O `cstk` resolve
isso via manifest + hash_dir.

### Documentação completa do cstk

- [`cli/README.md`](./cli/README.pt-BR.md) — visão técnica, convenções, processo de release
- [`docs/specs/_archived/cstk-cli/`](docs/specs/_archived/cstk-cli/) — spec, plan, contracts, quickstart
<!-- --8<-- [end:install-section] -->

<!-- --8<-- [start:profiles-section] -->
### Perfis de instalação (resumo)

| Perfil | Conteúdo | Uso típico |
|--------|----------|------------|
| `sdd` | 17 skills: pipeline Spec-Driven Development completa (briefing → review-features) + runtime interno, model-selector e os 4 gates de qualidade dos orquestradores | Instalação global default |
| `complementary` | 11 skills independentes (advisor, bugfix, e2e-integration-flow, etc.) | Complementa o pipeline SDD |
| `all` | Todas as 29 skills (sdd + complementary + language-go) | Instalação completa |
| `language-go` | Skills + hooks específicos para Go | Apenas em projetos Go |

Profile padrão quando nada é informado: `sdd`. Detalhes em `cstk install --help`.
<!-- --8<-- [end:profiles-section] -->

## Documentação por tópicos

| Tópico | Documento |
|--------|-----------|
| Pipeline SDD: fluxo completo, quando usar cada skill, atalhos, specs vivas | [docs/sdd-pipeline.md](./docs/sdd-pipeline.pt-BR.md) |
| Orquestrador autônomo (agente-00c / feature-00c) | [docs/agente-00c.md](./docs/agente-00c.pt-BR.md) |
| Sessões paralelas (`cstk session`) | [docs/cstk-session.md](./docs/cstk-session.pt-BR.md) |
| Memória de conhecimento (`cstk recall`) | [docs/cstk-recall.md](./docs/cstk-recall.pt-BR.md) |
| Painel web (`cstk serve`) | [docs/cstk-serve.md](./docs/cstk-serve.pt-BR.md) |
| Skills e hooks para Go | [docs/go-toolkit.md](./docs/go-toolkit.pt-BR.md) |
| Convenções de nomenclatura e hierarquia de docs | [docs/conventions.md](./docs/conventions.pt-BR.md) |
| Manual navegável (site) | [jotjunior.github.io/cstk](https://jotjunior.github.io/cstk/) |

## Contribuindo

Contribuições são bem-vindas. O guia completo — modelo mental do sistema,
fluxo de desenvolvimento, política de versionamento e o **princípio de escopo
do toolkit global** (skills publicadas aqui não devem nomear clientes,
empresas ou projetos específicos) — está em
[CONTRIBUTING.md](./CONTRIBUTING.pt-BR.md). Resumo para adicionar uma skill:

1. Siga a estrutura de pasta de uma skill existente (ver [Anatomia de uma skill](#anatomia-de-uma-skill))
2. `SKILL.md` enxuto como ponto de entrada; conteúdo pesado em subpastas
3. **description** como trigger condition, não resumo
4. **Gotchas** documentados — o conteúdo mais valioso de uma skill
5. Scripts em POSIX sh para operações determinísticas; todo `.sh` novo exige `tests/test_<nome>.sh`
6. Generalize: se referencia algo de um projeto específico, pertence ao `<projeto>/.claude/skills/`, não a este toolkit
7. Teste com o Claude Code antes de submeter

## Versionamento

Este projeto segue [Semantic Versioning](https://semver.org/) e mantém um
[CHANGELOG.md](./CHANGELOG.md) com o histórico de mudanças.

## Créditos & Atribuições

Parte do pipeline SDD é adaptada do [GitHub Spec Kit](https://github.com/github/spec-kit)
(MIT) — em especial o vocabulário de etapas e o template de constituição. O
modelo de specs vivas com delta requirements foi inspirado no
[OpenSpec](https://github.com/Fission-AI/OpenSpec). Outras skills tiveram
inspiração conceitual de [obra/superpowers](https://github.com/obra/superpowers)
e das convenções do Claude Code. Padrões públicos (OWASP, NIST, IETF, W3C,
MITRE) são citados como referência. Detalhes e avisos de licença em
[THIRD-PARTY-NOTICES.md](./THIRD-PARTY-NOTICES.pt-BR.md).

## Licença

Distribuído sob a licença MIT. Veja o arquivo [LICENSE](./LICENSE) para o
texto completo.
