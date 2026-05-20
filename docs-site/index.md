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
curl -fsSL https://github.com/JotJunior/claude-ai-tips/releases/latest/download/install.sh | sh
cstk install
```

O one-liner baixa o `cstk` CLI (POSIX shell, sem Node/Python), valida SHA-256
e instala em `~/.local/bin/`. O `cstk install` (sem args) coloca o perfil
`sdd` em `~/.claude/skills/`. Manual completo: [Instalacao](manual/instalacao.md).

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

Codigo-fonte: [github.com/JotJunior/claude-ai-tips](https://github.com/JotJunior/claude-ai-tips) - MIT License.
