---
title: Instalacao
---

# Instalacao

Esta pagina e a fonte unica de instrucoes de instalacao. O conteudo abaixo
e includido literalmente do [`README.md`](https://github.com/JotJunior/cstk/blob/main/README.md)
da raiz do repositorio — qualquer atualizacao no README aparece aqui no
proximo build CI (FR-005).

## Pre-requisitos

- `bash` ou `sh` POSIX (Linux, macOS, WSL).
- `curl` no PATH para o one-liner de bootstrap.
- `tar` e `sha256sum` (ou `shasum -a 256` no macOS) para validar a release.
- `git` se voce planeja contribuir. **Nao** ha dependencia de Node, Python
  ou Docker para o `cstk` em si.
- `jq` e opcional — habilita merge de `settings.json` em escopo de projeto.

## Conteudo canonico (do README)

--8<-- "README.md:install-section"

## Conferindo a instalacao

```bash
cstk --version    # imprime tag semver da release instalada
cstk list         # lista skills instaladas + status (managed / drifted / unmanaged)
cstk doctor       # detalha drift entre manifest e disco
```

Se `cstk` nao aparece no PATH, garanta que `~/.local/bin` esta em `PATH`:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc   # ou ~/.bashrc
exec "$SHELL" -l
```

## Atualizacao

```bash
cstk self-update   # atualiza o proprio binario cstk a partir do GitHub
cstk update        # atualiza skills preservando edicoes locais (--force sobrescreve)
```

A skill `cstk update` deteca **drift** (edicao local depois da instalacao) e
pausa por seguranca antes de sobrescrever. Use `--force` para aceitar a
sobrescrita ou `cstk doctor` para inspecionar diferencas.
