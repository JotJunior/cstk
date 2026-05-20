---
title: Comandos do cstk
---

# Comandos do `cstk`

Esta pagina espelha a documentacao tecnica do CLI mantida em
[`cli/README.md`](https://github.com/JotJunior/claude-ai-tips/blob/main/cli/README.md).
A fonte canonica e o arquivo no repositorio — qualquer atualizacao aparece
aqui no proximo build CI (FR-005).

## Visao geral dos subcomandos

| Comando | Funcao |
|---------|--------|
| `cstk install` | Instala skills (perfil ou cherry-pick) em `~/.claude/` ou `./.claude/`. |
| `cstk update` | Atualiza skills do manifest, detectando drift local. |
| `cstk self-update` | Atualiza o proprio binario `cstk`. |
| `cstk list` | Lista skills instaladas com status (`managed`, `drifted`, `unmanaged`). |
| `cstk doctor` | Diagnostica drift entre manifest e arquivos em disco. |
| `cstk session` | Worktrees git isoladas para trabalho paralelo (multi-feature). |
| `cstk 00c` | Atalho para iniciar o agente-00C no projeto-alvo. |

## Documentacao canonica

--8<-- "cli/README.md"
