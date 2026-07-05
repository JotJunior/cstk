# Claude Code Toolkit

[![Latest Release](https://img.shields.io/github/v/release/JotJunior/cstk?label=latest%20release&color=blue)](https://github.com/JotJunior/cstk/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](./LICENSE)
[![SemVer](https://img.shields.io/badge/SemVer-5.x-orange.svg)](./CHANGELOG.md)
[![Docs Site](https://img.shields.io/badge/docs-jotjunior.github.io/cstk-blue?logo=readthedocs)](https://jotjunior.github.io/cstk/)
[![Publish Site](https://github.com/JotJunior/cstk/actions/workflows/publish-site.yml/badge.svg?branch=main)](https://github.com/JotJunior/cstk/actions/workflows/publish-site.yml)

Conjunto de ferramentas para aumentar a produtividade no desenvolvimento do dia a dia com
o [Claude Code](https://claude.ai/code).

Este repositorio contém **skills** e **hooks** que estendem as capacidades do Claude Code
para tarefas de documentação, desenvolvimento, segurança e qualidade de código.

> **Quem mantém / para quem é.** Mantido por uma pessoa, otimizado primeiro
> para o fluxo do mantenedor (microserviços em Go). As partes concretas —
> skills, hooks, CLI — são de uso geral; a **trilha avançada** (orquestrador
> autônomo) é mais experimental. Veja [Comece aqui](#comece-aqui) para a
> separação entre o básico e o avançado.

> **Versão atual:** consulte a [release mais recente no GitHub](https://github.com/JotJunior/cstk/releases/latest)
> para baixar o tarball ou acompanhar mudanças no [CHANGELOG.md](./CHANGELOG.md).
> A instalação recomendada é via `cstk` CLI (ver [seção Instalação](#instalação)).

## Comece aqui

Duas trilhas, dependendo do que você procura:

| Trilha | Para quem | Onde ir |
|--------|-----------|---------|
| **Básico** | Quer produtividade no dia a dia — especificar, revisar, corrigir, documentar com algumas skills | Esta seção + [Skills Globais](#skills-globais) |
| **Avançado** | Quer o orquestrador autônomo rodando o pipeline SDD inteiro sozinho | Seções **Agente-00C**, **Sessões paralelas** e **Memória de conhecimento** mais abaixo (marcadas como avançadas) |

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

## Estrutura

```
├── global/                     # Skills globais (independentes de linguagem)
│   └── skills/                 # 23 skills globais (cada skill é uma pasta)
│       ├── advisor/
│       ├── agente-00c-runtime/ # runtime POSIX interno (não user-invocável)
│       ├── analyze/
│       ├── apply-insights/
│       ├── briefing/
│       ├── bugfix/
│       ├── checklist/
│       ├── clarify/
│       ├── constitution/
│       ├── create-tasks/
│       ├── decision-tree/      # ⚠️ DEPRECATED (remove_in 6.0.0) — use cstk-panel (cstk serve)
│       ├── e2e-integration-flow/ # testes E2E de integração full-stack (Playwright)
│       ├── execute-task/
│       ├── image-generation/   # ⚠️ DEPRECATED (remove_in 6.0.0) — fora do escopo do toolkit
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
│   └── go/                     # Go
│       ├── skills/             # Skills para projetos Go
│       ├── hooks/              # Hooks de validação para Go
│       └── settings.json       # Configuração de hooks
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
| **e2e-integration-flow** | "e2e", "teste e2e", "playwright", "validar fluxo completo" | Cria e roda testes E2E de integração com Playwright que validam o fluxo completo de uma feature em TODAS as camadas (UI → rede/API → banco → fila/RabbitMQ → efeitos colaterais), não só o clique na UI. Profundidade sob demanda em `references/` |
| **image-generation** | Ao gerar imagens | ⚠️ **DEPRECATED** (remove_in 6.0.0 — fora do escopo do toolkit, sem substituto). Aprimora prompts de geração de imagens usando estrutura Subject-Context-Style |
| **initialize-docs** | "inicializar docs", "setup documentação" | Cria hierarquia padrão de documentação com 9 níveis |
| **apply-insights** | "aplicar insights", "aplicar playbook", "melhorar claude.md" | Analisa o projeto e aplica insights de uso comprovados ao CLAUDE.md, hooks e workflows. Renomeada de `insights` na 2.0.0 para evitar colisão com o `/insights` nativo do Claude Code (que tem função diferente — analisa suas sessões) |
| **owasp-security** | Ao revisar segurança | Revisão **guiada por checklist** sobre um catálogo de padrões modernos (OWASP Top 10:2025, API/CI-CD, ASVS 5.0, LLM/Agentic, CWE Top 25:2025, NIST 800-63B-4, WebAuthn, OAuth 2.1, FAPI 2.0, pós-quântica). Assistente de revisão — **não** substitui auditoria/pentest. Profundidade sob demanda em `references/` |
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

O skill `bugfix` implementa um protocolo de 8 etapas destilado da prática de corrigir bugs em
arquiteturas multi-serviço, com foco em eliminar ciclos de "corrige-revela-corrige":

- Classifica complexidade (simples vs. multi-camada)
- Rastreia o fluxo de dados completo antes de qualquer alteração
- Mapeia DTOs, enums e nomes de campo em todas as fronteiras
- Implementa correções em todas as camadas afetadas de uma vez

## Agente-00C (orquestrador autônomo da pipeline SDD)

> **Trilha avançada.** Não é necessário para o uso básico (ver
> [Comece aqui](#comece-aqui)). Esta seção e as duas seguintes
> (**Sessões paralelas** e **Memória de conhecimento**) cobrem o orquestrador
> autônomo e seus subsistemas.

> **Status: funcional e em uso pelo mantenedor** — porém **sem suíte de
> testes automatizada dos agentes custom** (validação por execuções reais,
> decisão consciente do briefing). Para adoção externa, trate como
> **experimental**: é um experimento pessoal de orquestração autônoma, não
> um produto com garantias de suporte. O backlog original (já concluído) está
> em [`docs/specs/_archived/agente-00c/tasks.md`](./docs/specs/_archived/agente-00c/)
> (44 tarefas, 9 fases); a feature evoluiu muito desde então — ver feature-00c,
> model-routing e a memória de conhecimento, abaixo.

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
> inicial, menos perguntas o agente faz na etapa `briefing` (ele registra
> várias dimensões de uma vez e vai direto à síntese). Use o template
> preenchível em
> [`docs/templates/briefing-prompt-ideal.md`](./docs/templates/briefing-prompt-ideal.md)
> — mapeado 1:1 com as seções do briefing e com blocos extras para
> arquiteturas complexas (decomposição em serviços, integrações, NFRs), com
> guia de poda para entregas simples.

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
> [`docs/specs/cstk-cli/contracts/cstk-00c.md`](docs/specs/_archived/cstk-cli/contracts/cstk-00c.md).

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
  com cenários manuais (`docs/specs/_archived/agente-00c/quickstart.md`). Não há
  unit tests dos agentes custom (decisão consciente do briefing —
  experimento pessoal).
- **Schema de estado v1.0.0 sem migração**: se o schema evoluir, será
  uma feature nova; execuções pendentes precisarão ser concluídas ou
  abortadas antes de upgrade.

Detalhamento completo (briefing, constitution, spec com 31 FRs, plan,
research, threat-model, contracts, quickstart) em
[`docs/specs/_archived/agente-00c/`](./docs/specs/_archived/agente-00c/).

### Feature-00C — Variante de escopo de feature individual

A partir de v3.13.0, o toolkit oferece `/feature-00c` como variante do
agente-00c focada em **uma feature** dentro de projeto que JA possui
`briefing.md` + `docs/constitution.md` ratificados. Pipeline reduzida:
`specify → clarify → plan → checklist → create-tasks → execute-task →
review-task` (sem briefing/constitution/review-features, que sao
pre-requisitos validados em FR-PRE-001..004).

| Comando | Quando usar |
|---------|-------------|
| `/feature-00c "<descricao>" [<short-name>]` | Adicionar feature nova em projeto existente |
| `/feature-00c-resume <short-name> [--resposta-bloqueio "..."]` | Retomar apos pausa ou schedule |
| `/feature-00c-abort <short-name> [--purge-backups]` | Aborto manual (SIGTERM + grace period 60s) |

Co-existencia com `/agente-00c`: namespaces isolados
(`agente-00c-state/` vs `feature-00c-state/<short_name>/`). Features
paralelas no mesmo projeto sao permitidas; concorrencia com agente-00c
ativo e bloqueada (FR-026). Reuso integral do runtime POSIX
compartilhado (`agente-00c-runtime`). Detalhamento em
[`docs/specs/_archived/feature-00c/`](./docs/specs/_archived/feature-00c/) (37 FRs, 14
SCs, 11 cenarios de validacao + roundtrip empirico de secrets).

### Roteamento de modelos no spawn (model-routing)

A partir de v3.15.0, ambos os orquestradores (`agente-00c` +
`feature-00c`) integram a skill standalone **model-selector** no
spawn de subagentes via tool Agent: antes de cada spawn (clarify-asker,
clarify-answerer), o orquestrador invoca `model-selector`, captura
sugestao (`haiku`/`sonnet`/`opus`/`manter-atual`) com score e duas
evidencias, registra **Decisao auditavel** (`state-decisions.sh`) e
append em `.ondas[N].skills_invoked[]` para auditoria via `review-task`.

| Componente | Localizacao |
|------------|-------------|
| Skill standalone (sugestor) | `global/skills/model-selector/` (entregue em v3.14.0) |
| Helper POSIX (3 subcomandos) | `global/skills/agente-00c-runtime/scripts/model-routing.sh` |
| Reconciliador half-record | `global/skills/agente-00c-runtime/scripts/state-decisions-reconcile.sh` |
| Agregador para review-task | `global/skills/agente-00c-runtime/scripts/model-routing-report.sh` |
| Integracao §5.e.bis | `global/agents/agente-00c-orchestrator.md` + `global/agents/agente-00c-feature-orchestrator.md` |
| Auditoria §4.5 | `global/skills/review-task/SKILL.md` |

Contrato **suggest-only**: skill nunca decide sozinha — apenas sugere
com evidencia. Operador SEMPRE pode override via Decisao manual.
Fallback `manter-atual` quando score < 2 (input ambiguo ou empate).
Spec completa em
[`docs/specs/_archived/agente-00c-model-routing/`](./docs/specs/_archived/agente-00c-model-routing/)
(20 FRs, 6 invariantes INV-1..INV-6, 4 load-bearing CHKs).

### Modo atomic-commit (opt-in)

A partir de v5.12.0, os orquestradores `agente-00c` e `feature-00c` oferecem
modo **atomic-commit** opt-in: cada etapa de artefato gera um commit Conventional
Commits automatico, e cada grupo de tasks `execute-task` com `outcome=pass` gera
um commit ranged ao final da onda. O finalize terminal dispara push + PR via
`cstk session pr` (push direto permanece bloqueado pelo `bash-guard.sh`).

| Componente | Localizacao |
|------------|-------------|
| Helper POSIX (`is-enabled`, `set-enabled`, `guard-branch`, `stage-message`, `task-message`, `finalize`) | `global/skills/agente-00c-runtime/scripts/commit-mode.sh` |
| Testes | `tests/test_commit-mode.sh` |
| Spec | `docs/specs/_archived/atomic-commit-pr/` |

### Guardas enforced (hook PreToolUse + integridade + allowlist de hosts)

As guardas de segurança do runtime (`bash-guard.sh`, checksum do painel,
esquema de URL) eram **advisory**: só produziam efeito se a prosa do
orquestrador lembrasse de invocá-las. A partir desta feature, três frentes
passam a ser **enforced** (não dependem mais do orquestrador lembrar):

1. **Hook `PreToolUse`/`Bash` fail-closed**: intercepta todo comando Bash
   de uma execução `agente-00c`/`feature-00c` ativa (detectada via
   `.claude/agente-00c-state/state.json` ou `.claude/feature-00c-state/*/state.json`
   com `status: em_andamento`) e delega a `bash-guard.sh check` — nunca
   reimplementa a regra. Falha do próprio mecanismo (`jq`/`bash-guard.sh`
   ausente) também bloqueia (`MECANISMO_FALHOU`, distinguível de
   `REGRA_VIOLADA`). Sessões manuais do operador (fora de execução ativa)
   ficam intactas. Cada decisão é auditável em `.claude/enforcement-log.jsonl`
   (campo `command` passa por `secrets-filter.sh scrub` antes de truncar).
2. **`cstk serve` recusa iniciar sem integridade confirmada por padrão**:
   ausência de `.sha256` do pacote baixado bloqueia (`unverifiable-blocked`);
   bypass explícito via `--allow-unverified`/`CSTK_SERVE_ALLOW_UNVERIFIED=1`
   com aviso de alta visibilidade; divergência de checksum continua
   bloqueando sempre (sem bypass possível).
3. **Allowlist de hosts confiáveis** (`CSTK_TRUSTED_RELEASE_HOSTS`, match
   exato case-insensitive, `file://` isento) aplicada em `cstk serve`,
   `cstk install --from` e `cstk self-update --from` — rejeita host fora
   da lista antes de qualquer download.

| Componente | Localizacao |
|------------|-------------|
| Hook + snippet de settings | `global/skills/agente-00c-runtime/hooks/pretooluse-bash-guard.sh` + `settings.snippet.json` |
| Provisionamento automático | `apply_guard_hooks()` em `cli/lib/hooks.sh` (integrado a `install.sh`/`update.sh`, escopo `project`) |
| Allowlist de hosts compartilhada | `cli/lib/trusted-hosts.sh` (`CSTK_TRUSTED_RELEASE_HOSTS`) |
| Log auditável | `.claude/enforcement-log.jsonl` (por projeto-alvo) |
| Spec | `docs/specs/enforced-guards/` |

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
| **go-add-entity** | "criar entidade", "novo agregado" | Adiciona CRUD vertical slice completo (domain, DTO, repo, service, handler, migration, wiring) |
| **go-add-migration** | "nova migration", "criar tabela" | Cria nova migration SQL com naming/numeração corretos |
| **go-add-test** | "adicionar testes", "cobertura" | Gera testes para handler/service seguindo convenções do projeto |
| **go-add-consumer** | "novo consumer", "subscribe evento" | Adiciona consumer de mensagens RabbitMQ |
| **go-review-pr** | "review pr", "quality gate" | Quality gate pré-PR, diff-aware, com revisão em 8 etapas |
| **go-review-service** | "review service", "auditar serviço" | Audita microserviço Go contra todas as convenções do projeto |

Estas skills agora são acionadas automaticamente pelos orchestrators
quando o stack detectado for Go — ver seção 4.2.1 de `execute-task` e
"Atalhos de auditoria por stack" em `review-task`.

### Hooks para Go

Hooks em `language-related/go/hooks/` para validações automáticas:

| Hook | Descrição |
|------|-----------|
| **go-build-gate.sh** | Valida build antes de operações |
| **check-uncommitted.sh** | Verifica alterações não commitadas |
| **check-schema-prefix.sh** | Valida prefixo de schema nas migrations |
| **check-route-order.sh** | Verifica ordenação de rotas no router |

<!-- --8<-- [start:install-section] -->
## Instalação

### Via cstk CLI (recomendado)

A partir da versão `0.1.0`, o toolkit é instalado via `cstk` —
CLI POSIX shell que baixa, valida (SHA-256), instala e atualiza skills sem
exigir clone do repositório.

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
cstk self-update                     # atualiza o próprio binário cstk
```

**Perfis disponíveis:**

| Perfil | Conteúdo | Uso típico |
|--------|----------|------------|
| `sdd` | 16 skills: pipeline Spec-Driven Development completa (briefing → review-features) + runtime interno, model-selector e os 3 gates de qualidade dos orquestradores | Instalação global default |
| `complementary` | 12 skills independentes (advisor, bugfix, e2e-integration-flow, etc.) | Complementa o pipeline SDD |
| `all` | Todas as 30 skills (sdd + complementary + language-go) | Instalação completa |
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
- [`docs/specs/cstk-cli/`](docs/specs/_archived/cstk-cli/) — spec, plan, contracts, quickstart
<!-- --8<-- [end:install-section] -->

<!-- --8<-- [start:profiles-section] -->
### Perfis de instalação (resumo)

| Perfil | Conteúdo | Uso típico |
|--------|----------|------------|
| `sdd` | 16 skills: pipeline Spec-Driven Development completa (briefing → review-features) + runtime interno, model-selector e os 3 gates de qualidade dos orquestradores | Instalação global default |
| `complementary` | 12 skills independentes (advisor, bugfix, e2e-integration-flow, etc.) | Complementa o pipeline SDD |
| `all` | Todas as 30 skills (sdd + complementary + language-go) | Instalação completa |
| `language-go` | Skills + hooks específicos para Go | Apenas em projetos Go |

Profile padrão quando nada é informado: `sdd`. Detalhes em `cstk install --help`.
<!-- --8<-- [end:profiles-section] -->

## Sessões paralelas (`cstk session`)

> **Trilha avançada** — suporte ao orquestrador autônomo.

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
- [`docs/specs/cstk-session/spec.md`](docs/specs/_archived/cstk-session/spec.md) — user stories, FRs, success criteria
- [`docs/specs/cstk-session/contracts/cli-session.md`](docs/specs/_archived/cstk-session/contracts/cli-session.md) — exit codes (5-15), flags, output formats

## Memória de conhecimento (`cstk recall`)

> **Trilha avançada** — subsistema do orquestrador autônomo.

Camada **aditiva** de memória cross-feature: um índice SQLite global
(`~/.claude/cstk/knowledge.db`, full-text via FTS5) alimentado automaticamente
no fim de cada onda dos orquestradores `agente-00c`/`feature-00c`. Permite
buscar decisões, bloqueios, retro-execuções, skills invocadas e **memorias**
(arquivos `.md` do Claude Code) de **qualquer projeto ou feature já executados**,
com proveniência (projeto / feature / onda / data).

Desde o **schema v2** (índice retro-compatível, migração aditiva e silenciosa),
a ingestão também deriva **métricas de dashboard** do `state.json` em tabelas
dedicadas: `executions` (status / motivo / duração por execução), `waves`
(ciclo de vida, `tool_calls`, `wallclock` por onda), `alert_signals` (sinais de
circular / budget breach), `tasks` (outcome pass|fail, testes, lint,
arquivos tocados) e `events`. Métricas como latência humana, clarify-rate e mix
de modelos são **deriváveis** dessas tabelas — preparando o terreno para um
futuro `cstk-panel` (dashboard read-only). As 4 tabelas textuais originais
(`decisions`/`bloqueios`/`retros`/`skills`) seguem inalteradas.

O índice é puramente **derivado** — o `state.json` transacional permanece a
fonte de verdade, intacto e fora do caminho crítico (a ingestão o lê em modo
**somente leitura**, nunca escreve). A base inteira é descartável: pode ser
reconstruída a qualquer momento via `--reindex` a partir dos
`state.json`/`state-history` existentes.

```bash
# Buscar (full-text, ordenado por relevância bm25)
cstk recall "lock contention"

# Filtrar por projeto, tipo de registro e limitar resultados
cstk recall "secrets-filter" --project cstk --type decision --limit 5

# Filtrar só memorias (.md do Claude Code)
cstk recall "setup" --type memory

# Filtrar só sugestões (aprendizado de meta-padrão: diagnóstico + proposta)
cstk recall "websocket auth" --type suggestion

# Reconstruir o índice do zero a partir dos states existentes (inclui memorias)
cstk recall --reindex

# Ingestão manual de uma feature específica (normalmente o hook faz isto; inclui memorias)
cstk recall --ingest --state-dir .claude/feature-00c-state/<short-name>

# Leitura-para-contexto (read-back loop): bloco markdown pronto para injeção
cstk recall --context "cache fts query" --limit 4 \
  --exclude-feature minha-feature-corrente --max-bytes 2000

# Listar memorias indexadas (slug + description, sem body)
cstk recall --list-memories [--project P]
```

**Flags do modo busca**:

- `--project P` — filtra pelo projeto de origem
- `--type T` — `decision` | `bloqueio` | `retro` | `skill` | `memory` | `suggestion`
- `--limit N` — máximo de resultados (inteiro positivo; default 20)
- `--db PATH` — índice alternativo (default `$CSTK_KNOWLEDGE_DB` ou
  `~/.claude/cstk/knowledge.db`)

**Modo `--context` (read-back loop)**: fecha o ciclo da memória — em vez de
exibir resultados para leitura humana, retorna um **bloco markdown enxuto**
pronto para injeção no contexto de um prompt. Os orquestradores `agente-00c`/
`feature-00c` o invocam automaticamente no início das fases `specify` e `plan`
(passo PRE-DECISAO), injetando aprendizado de execuções passadas **antes** de
decidir. Diferenças face ao modo busca: composição **OR** entre termos (maior
recall sobre keywords kebab da feature), anti-eco `--exclude-feature` (omite a
feature corrente para não ecoar suas próprias escritas), e teto duro de bytes.

- `--exclude-feature NAME` — anti-eco: omite achados da feature `NAME` (no SQL)
- `--limit N` — máximo de achados (default **4**; faixa recomendada 3-5)
- `--max-bytes N` — teto de bytes do bloco (default **2000**; corta por achado
  inteiro, nunca no meio)
- `--type T` / `--project P` / `--db PATH` — iguais ao modo busca

É **read-only** e **best-effort**: toda degradação (sem `sqlite3`, índice
ausente/corrompido, zero achados) resulta em **no-op silencioso** (stdout vazio,
exit 0) — nunca gateia uma onda. Contra prompt-injection via memória recuperada
há **duas camadas** (ASI09/LLM01): (1) *scrubbing* de segredos na **ingestão**
(controle técnico real) e (2) injeção com rótulo **UNTRUSTED / não-autoritativo**
— uma **mitigação** defense-in-depth, **não uma garantia**. O risco residual de
um registro antigo *instruir* o modelo permanece; por isso o conteúdo nunca é
tratado como instrução.

**Degradação graciosa**: a ausência de `sqlite3` ou `jq` **nunca** aborta uma
onda — o hook de ingestão e o `recall` saem com status 0 emitindo apenas um
aviso. O índice fica isolado em `~/.claude/cstk/`, separado do estado
transacional por projeto.

**Documentação completa**:
- [`docs/specs/_archived/cstk-knowledge-db/spec.md`](docs/specs/_archived/cstk-knowledge-db/spec.md) — user stories, FRs, success criteria
- [`docs/specs/_archived/cstk-knowledge-db/contracts/cstk-recall.md`](docs/specs/_archived/cstk-knowledge-db/contracts/cstk-recall.md) — modos, flags, exit codes, esquema FTS5
- [`docs/specs/_archived/knowledge-db-metrics/spec.md`](docs/specs/_archived/knowledge-db-metrics/spec.md) — ingestão de métricas (schema v2): tabelas `executions`/`waves`/`alert_signals`/`tasks`/`events`
- [`docs/specs/_archived/knowledge-db-metrics/data-model.md`](docs/specs/_archived/knowledge-db-metrics/data-model.md) — DDL das novas tabelas e chaves naturais

## Painel Web (`cstk serve`)

Inicia a interface web do cstk panel localmente. Na primeira execução, baixa
automaticamente a release mais recente de
[JotJunior/cstk-panel](https://github.com/JotJunior/cstk-panel) e instala em
`~/.local/share/cstk/panel`. Execuções subsequentes reutilizam a instalação em
cache.

O `cstk serve` compila os workspaces (`npm run build` — shared-types, server e
web) e então sobe um **único processo Fastify** (`npm run start`) que serve a
**API e o SPA buildado** (`apps/web/dist`) na **mesma porta**. Não há mais modo
dev nem proxy do Vite. Abra **http://127.0.0.1:5173** (ou a porta de `--port`)
no navegador. Requer `cstk-panel >= 0.2.0`.

**Dependências**: `curl`, `npm` e `node` (Node.js) disponíveis no PATH — o
`npm install` traz as devDependencies necessárias ao build do painel.

```bash
cstk serve                      # compila e inicia o painel (API + SPA na mesma porta, http://127.0.0.1:5173)
cstk serve --update             # atualiza o painel se houver release nova, depois inicia
cstk serve --reinstall          # remove e reinstala do zero, depois inicia
```

**Opções**:

| Flag | Padrão | Descrição |
|------|--------|-----------|
| `--update` | — | Consulta o GitHub e reinstala o painel **somente** se houver release mais nova (best-effort: falha de rede/API mantém a versão instalada e o painel inicia normalmente). |
| `--reinstall` | — | Remove a instalação existente e reinstala do GitHub (incondicional; ignora `--update`). |
| `--port PORT` | `5173` | Porta onde o servidor Fastify escuta (inteiro 1024–65535; também lê `$PORT`). O painel binda essa porta diretamente. |
| `--host HOST` | `127.0.0.1` | Host de bind (apenas loopback tem suporte completo). |
| `--help`, `-h` | — | Exibe ajuda e sai. |

**Variáveis de ambiente**:

- `CSTK_PANEL_DIR` — Substitui o diretório de instalação (padrão:
  `~/.local/share/cstk/panel`).
- `PORT` — Porta padrão quando `--port` não é informado.

**Exit codes**: `0` sucesso · `1` erro geral (prereq ausente, download/build
falhou, instalação corrompida) · `2` erro de uso (porta inválida, flag
desconhecida).

**Segurança**: apenas URLs de `api.github.com`, `github.com`,
`codeload.github.com` e `objects.githubusercontent.com` são autorizadas no
download (SSRF allowlist). Host `127.0.0.1` é o único com suporte completo —
outras interfaces emitem aviso.

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
seu domínio.

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

Contribuições são bem-vindas. O guia completo — modelo mental do sistema, fluxo
de desenvolvimento e política de versionamento — está em
[CONTRIBUTING.md](./CONTRIBUTING.md). Resumo para adicionar skills ou hooks:

> **Princípio fundamental — escopo do toolkit global (v3.12.0+):**
>
> Skills publicadas em `global/skills/` ou `language-related/<stack>/skills/`
> deste toolkit **NÃO devem nomear clientes, empresas ou projetos
> específicos**. Hardcoded em uma skill global: nomes de serviços de
> um produto específico, exchanges/queues internas, paths ETCD de um
> cliente, vocabulário de domínio proprietário, branding em templates
> de output.
>
> Skills com forte acoplamento a um projeto pertencem ao próprio
> projeto, em `<projeto>/.claude/skills/<nome>/` — ali elas ficam ao
> lado do código que documentam, versionam com o projeto e não poluem
> o toolkit reutilizável.
>
> Caso histórico: `create-report` foi removida em v3.12.0 porque
> codificava `gob-report-service`, exchange `gob.reports`, vocabulário
> maçônico (lodge, federal, state_orient) e cabeçalho fixo "Grande
> Oriente do Brasil" no PDF — material que pertence ao projeto GOB,
> não ao toolkit.

1. Siga a estrutura de pasta de uma skill existente (ver [Anatomia de uma skill](#anatomia-de-uma-skill))
2. Crie um `SKILL.md` como ponto de entrada — mantenha enxuto e use subpastas para conteúdo pesado
3. **description**: escreva como trigger condition, não resumo — "Use quando X, Y ou Z. Também quando mencionar A, B, C. NÃO use quando W."
4. **Gotchas**: documente armadilhas conhecidas — o conteúdo mais valioso de uma skill
5. **Templates/examples/references**: extraia conteúdo que o modelo consulta sob demanda
6. **Scripts**: prefira POSIX sh para operações determinísticas (next-id, validação, scaffold)
7. **config.json**: use para parâmetros que variam entre projetos
8. **Generalize**: se a skill referencia algo de um projeto específico, refatore para parâmetros — se não der, ela pertence ao `<projeto>/.claude/skills/`, não a este toolkit
9. Teste com o Claude Code antes de submeter

## Versionamento

Este projeto segue [Semantic Versioning](https://semver.org/) e mantém um
[CHANGELOG.md](./CHANGELOG.md) com o histórico de mudanças.

## Créditos & Atribuições

Parte do pipeline SDD deste toolkit é adaptada do [GitHub Spec Kit](https://github.com/github/spec-kit)
(MIT) — em especial o vocabulário de etapas e o template de constituição. Outras
skills tiveram inspiração conceitual de [obra/superpowers](https://github.com/obra/superpowers)
e das convenções do Claude Code. Padrões públicos (OWASP, NIST, IETF, W3C, MITRE)
são citados como referência. Detalhes e avisos de licença em
[THIRD-PARTY-NOTICES.md](./THIRD-PARTY-NOTICES.md).

## Licença

Distribuído sob a licença MIT. Veja o arquivo [LICENSE](./LICENSE) para o
texto completo.
