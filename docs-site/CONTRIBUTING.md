---
title: Contribuindo com a documentacao do site
description: Como contribuir com mudancas de conteudo do site (regra de ouro D-I).
---

# Contribuindo com a documentacao do site

Este site (`https://jotjunior.github.io/cstk/`) e gerado a
partir dos **arquivos fonte canonicos** do toolkit. **Nao edite paginas
diretamente neste diretorio (`docs-site/`)** se a pagina e auto-gerada
— a proxima execucao do hook `gen_pages.py` sobrescreve sua mudanca
em memoria.

## Regra de ouro: editar o arquivo fonte canonico

Para mudar o conteudo de qualquer skill, agent ou command que aparece
no site, edite **direto no arquivo de origem**:

| Para mudar pagina em... | Edite o arquivo... |
|--------------------------|---------------------|
| `/skills/<nome>/` | `global/skills/<nome>/SKILL.md` |
| `/skills/go/<nome>/` | `language-related/go/skills/<nome>/SKILL.md` |
| `/skills/dotnet/<nome>/` | `language-related/dotnet/skills/<nome>/SKILL.md` |
| `/agents/<nome>/` | `global/agents/<nome>.md` |
| `/commands/<nome>/` | `global/commands/<nome>.md` |

Apos editar e fazer push para a branch publicadora (normalmente `main`),
o workflow `publish-site.yml` re-publica em ate 10 minutos.

### Por que essa regra existe

O site segue o **Principio D-I (Zero Duplicacao)** da feature
`github-pages-cstk-manual`: cada paragrafo de conteudo vive em **um
unico arquivo**. O hook `docs-site/hooks/gen_pages.py` gera paginas
virtuais que sao apenas **shims** apontando para os arquivos fonte via
diretiva `--8<--` do `pymdownx.snippets`. Resultado: editar o fonte
atualiza o site automaticamente, sem risco de divergencia entre
"verdade do toolkit" e "verdade renderizada".

## O que VIVE em `docs-site/` (editavel aqui)

| Arquivo | Conteudo |
|---------|----------|
| `docs-site/index.md` | Landing page (pitch + categorias) |
| `docs-site/manual/*.md` | Manual operacional (cstk install, troubleshooting) |
| `docs-site/changelog.md` | Apontamento para `CHANGELOG.md` da raiz |
| `docs-site/overrides/` | Customizacoes do tema Material |
| `docs-site/assets/` | Imagens, logos, favicons especificos do site |

Esses arquivos NAO sao auto-gerados — editar diretamente neste diretorio
e o caminho correto.

## Como rodar o site localmente

```sh
# 1. Imprime instrucoes de instalacao (manual, FR-018):
sh scripts/bootstrap-docs.sh

# 2. Seguir os passos impressos (criar venv + pip install)

# 3. Servidor de desenvolvimento:
mkdocs serve
# abre em http://127.0.0.1:8000/

# 4. Build estrito (mesma chamada do CI):
mkdocs build --strict
```

Validacao adicional (sem mkdocs instalado):

```sh
python3 scripts/check-links.py    # valida links internos + snippets
sh     scripts/smoke-site.sh      # apos mkdocs build, faz grep negativo de trackers
```

## Pull requests

1. Faca a edicao no arquivo fonte canonico (ver tabela acima).
2. Rode `mkdocs build --strict` localmente — se falha por link quebrado,
   corrija antes de abrir PR.
3. Abra PR descrevendo o que mudou e por que.
4. Aguarde o CI `publish-site.yml` rodar verde no preview.

## Adicionar nova skill / agent / command

Basta criar o arquivo no path canonico:

```
global/skills/<novo-nome>/SKILL.md       # nova skill global
language-related/go/skills/<novo>/SKILL.md  # nova skill Go
global/agents/<novo>.md                  # novo agent
global/commands/<novo>.md                # novo command
```

`gen_pages.py` descobre via glob — **zero edits aqui** sao necessarios.
Apos o proximo build, o item aparece em `/skills/`, `/agents/` ou
`/commands/` automaticamente.

## Mais informacoes

- Spec da feature: `docs/specs/github-pages-cstk-manual/spec.md`
- Decisoes tecnicas: `docs/specs/github-pages-cstk-manual/plan.md`
- Runbook de deploy: `docs/specs/github-pages-cstk-manual/runbook-deploy.md`
