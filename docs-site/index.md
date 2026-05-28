---
title: Claude Code Toolkit
hide:
  - navigation
  - toc
---

# Claude Code Toolkit

Conjunto curado de **skills**, **agents** e **slash commands** que estendem o
[Claude Code](https://claude.ai/code) com pipelines reproduziveis para
Spec-Driven Development (SDD), revisao de codigo, seguranca e operacao
autonoma de longo prazo.

## Instale em 30 segundos

```bash
curl -fsSL https://github.com/JotJunior/cstk/releases/latest/download/install.sh | sh
cstk install
```

O one-liner baixa o `cstk` CLI (POSIX shell, sem Node/Python), valida SHA-256
e instala em `~/.local/bin/`. O `cstk install` (sem args) coloca o perfil
`sdd` em `~/.claude/skills/`. Manual completo: [Instalacao](manual/instalacao.md).

## Cookbook: comece a usar agora 🧑‍🍳

Instalou e ficou na duvida do que fazer? Esta secao e um **livro de receitas**.
Cada receita resolve **um objetivo** com o **comando exato** e o **que esperar**.
Voce nao precisa entender a arquitetura para colher o primeiro resultado —
escolha o nivel, copie a receita e cozinhe.

!!! tip "A unica regra que voce precisa saber"
    Tudo acontece **dentro do Claude Code**, conversando em portugues normal.
    As frases entre aspas abaixo sao literalmente o que voce digita no chat.
    O `/comando` (com barra) e um atalho nomeado; a frase em linguagem natural
    faz a mesma coisa. Errou? E so dizer "desfaz" ou pedir de novo.

=== "🥄 Basico — para o primeiro dia"

    Quatro receitas cobrem 90% do uso diario. Faca na ordem se for sua
    primeira vez.

    **1. Transformar uma ideia em codigo (do zero, no piloto automatico)**

    O jeito mais rapido de ver a ferramenta trabalhar: descreva o que quer e
    deixe o orquestrador conduzir todo o pipeline sozinho, em ondas.

    ```text
    /feature-00c "quero um encurtador de URLs com painel de cliques"
    ```

    > 👀 **O que acontece:** o `agente-00C` roda discovery → spec → plano →
    > tarefas → implementacao → revisao, fazendo commit a cada etapa. Ele
    > pausa e te pergunta quando precisa de uma decisao sua.

    **2. Corrigir um bug**

    ```text
    "corrija este bug: o login aceita senha vazia"
    ```

    > 👀 **O que acontece:** dispara a skill `bugfix`, que investiga camada por
    > camada (rastreia a causa antes de aplicar o patch) em vez de remendar o
    > primeiro sintoma.

    **3. Saber em que pe esta o projeto**

    ```text
    "revisar tarefas"
    ```

    > 👀 **O que acontece:** a skill `review-task` gera um painel de progresso
    > (concluidas / pendentes / bloqueadas) e sugere qual tarefa atacar a seguir.

    **4. Documentar uma feature existente**

    ```text
    "criar uma spec para o fluxo de checkout"
    ```

    > 👀 **O que acontece:** a skill `specify` transforma sua descricao livre em
    > uma spec estruturada (user stories, requisitos, criterios de sucesso) —
    > a base de todo o resto.

    !!! note "Dica de iniciante"
        Comeca sempre pedindo o `briefing` ("vamos iniciar o discovery") quando
        o projeto e novo. Pular o discovery faz o Claude inventar premissas no
        meio do caminho. Detalhes em [Fluxo SDD](manual/fluxo-sdd.md).

=== "🔬 Avancado — quando ja pegou o jeito"

    Aqui voce assume o controle fino: roda o pipeline manualmente, paraleliza
    features e reaproveita o aprendizado de execucoes passadas.

    **1. Rodar o pipeline SDD etapa por etapa (controle total)**

    Em vez do piloto automatico, invoque cada skill na ordem e revise a saida
    de cada uma antes de avancar:

    ```text
    briefing → constitution → specify → clarify → plan
             → checklist → create-tasks → analyze → execute-task → review-task
    ```

    > 📖 Cada etapa, o que produz e quando pular: [Fluxo SDD](manual/fluxo-sdd.md).

    **2. Delegar um projeto inteiro ao orquestrador autonomo**

    ```text
    /agente-00c
    ```

    > 👀 **O que acontece:** executa o pipeline em **ondas**, persistindo
    > `state.json` e commitando apos cada onda. Ideal para POC/MVP longo ou
    > rodar em background. Retome ou aborte quando quiser:
    >
    > ```text
    > /agente-00c-resume    # continua de onde parou
    > /agente-00c-abort     # encerra com relatorio final
    > ```

    **3. Trabalhar em varias features ao mesmo tempo (sem colisao)**

    ```bash
    cstk session start encurtador     # cria worktree + branch isolada
    cstk session list                 # mostra sessoes ativas
    cstk session pr encurtador        # abre o PR via gh
    cstk session end encurtador       # remove worktree + branch
    ```

    > 👀 **O que acontece:** cada sessao tem seu proprio working tree e estado
    > do orquestrador — voce roda dois `agente-00C` em paralelo sem um pisar no
    > outro.

    **4. Reaproveitar o aprendizado de execucoes passadas**

    ```bash
    cstk recall "lock contention"                 # busca full-text
    cstk recall "secrets" --type decision --limit 5
    ```

    > 👀 **O que acontece:** consulta um indice global (SQLite) alimentado a cada
    > onda dos orquestradores — decisoes, bloqueios e retros de qualquer projeto
    > ja executado, com proveniencia (projeto / feature / onda / data).

    **5. Escolher o modelo certo para cada etapa**

    O orquestrador ja aplica um modelo por fase automaticamente (opus no
    planejamento profundo, sonnet/haiku nas etapas rasas). Para uma sugestao
    deterministica antes de uma tarefa cara, peca a skill `model-selector`.

    > 📖 Subcomandos completos do CLI: [Comandos](manual/comandos.md) ·
    > Perfis de instalacao: [Perfis](manual/profiles.md).

## Catalogo

<div class="grid cards" markdown>

-   :material-toolbox: **Skills**

    ---

    21 skills globais — pipeline SDD (briefing -> review-task), advisor,
    bugfix, owasp-security, validate-docs-rendered e mais.

    [Ver skills :material-arrow-right:](skills/)

-   :material-robot: **Agents**

    ---

    3 sub-agents do `agente-00C` — orquestrador autonomo + dois clarify
    workers (asker / answerer).

    [Ver agents :material-arrow-right:](agents/)

-   :material-console: **Slash commands**

    ---

    3 comandos `/agente-00c*` que dirigem o pipeline 00C end-to-end:
    iniciar, retomar, abortar.

    [Ver commands :material-arrow-right:](commands/)

</div>

## Comece pelo manual

| Topico | Pagina |
|--------|--------|
| Como instalar e atualizar | [Instalacao](manual/instalacao.md) |
| Perfis (`sdd`, `complementary`, `all`, `language-*`) | [Perfis](manual/profiles.md) |
| Subcomandos do `cstk` | [Comandos](manual/comandos.md) |
| Fluxo Spec-Driven Development | [Fluxo SDD](manual/fluxo-sdd.md) |
| Historico de versoes | [Changelog](changelog.md) |

## Conceitos rapidos

- **Skill**: pasta com `SKILL.md` que o Claude carrega sob demanda (progressive disclosure). Ex: `briefing/`, `bugfix/`.
- **Agent**: sub-agent invocado via tool `Agent`, com escopo e tools restritas. Ex: `agente-00c-orchestrator`.
- **Slash command**: alias declarativo em `.claude/commands/*.md` que dispara skill/agent. Ex: `/agente-00c`.

Codigo-fonte: [github.com/JotJunior/cstk](https://github.com/JotJunior/cstk) - MIT License.
