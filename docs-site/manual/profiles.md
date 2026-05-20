---
title: Perfis de instalacao
---

# Perfis de instalacao

O `cstk install` agrupa skills em **perfis** — colecoes nomeadas que voce
instala juntas. O perfil default (sem argumento) e `sdd`, focado no pipeline
Spec-Driven Development.

--8<-- "README.md:profiles-section"

## Quando usar cada perfil

- **`sdd`** — voce esta comecando uma feature do zero e quer o pipeline
  completo (`briefing` -> `constitution` -> `specify` -> `clarify` -> `plan`
  -> `checklist` -> `create-tasks` -> `analyze` -> `execute-task` ->
  `review-task`). Default global, suficiente para 80% dos casos.
- **`complementary`** — voce ja tem o `sdd` instalado e quer skills
  ortogonais (`advisor`, `bugfix`, `owasp-security`, `apply-insights`,
  `validate-docs-rendered`, etc).
- **`all`** — instala tudo, inclusive `language-go` e `language-dotnet`.
  Util em maquinas de trabalho multi-stack.
- **`language-go`** / **`language-dotnet`** — sempre em `--scope project`,
  porque hooks de linguagem so fazem sentido dentro do repo-alvo.

## Cherry-pick

Voce nao precisa instalar um perfil inteiro. Liste skills por nome:

```bash
cstk install advisor bugfix owasp-security
cstk install --scope project create-use-case go-add-entity
```

Cherry-pick respeita as mesmas regras do perfil: hashes verificados,
manifest atualizado, drift detectavel via `cstk doctor`.

## Modo interativo

```bash
cstk install --interactive
```

Lista perfis e skills numeradas; voce alterna selecao por numero. Util em
sessoes onde voce ainda esta decidindo o que quer.
