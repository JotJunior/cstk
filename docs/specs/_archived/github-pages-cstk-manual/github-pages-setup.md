# GitHub Pages — Ativacao do site

Documento operacional para habilitar a publicacao do site MkDocs no
GitHub Pages do repositorio `JotJunior/claude-ai-tips`. Refere-se a
FR-022 da spec e §6.4 do `tasks.md`.

## Pre-requisitos

- Workflow `.github/workflows/publish-site.yml` ja commitado na branch
  `main` (FASE 6, T-6.1/T-6.2).
- Permissoes de admin no repositorio.

## Passo a passo (UI do GitHub)

1. Abra `https://github.com/JotJunior/claude-ai-tips/settings/pages`.
2. Em **Build and deployment**:
   - **Source**: selecione **GitHub Actions** (NAO "Deploy from a branch").
   - O GitHub detecta automaticamente o workflow `publish-site.yml` —
     nao e necessario configurar o branch nem o path.
3. Salve. A URL publica gerada sera:
   `https://jotjunior.github.io/claude-ai-tips/`
4. Faca um push minimo em `main` (ex: editar README.md trivial) e
   acompanhe a aba **Actions** ate o job `deploy` finalizar com sucesso.
5. Abra a URL publica e valide que o site renderiza.

## Verificacao via CLI (opcional)

```bash
# Listar workflows
gh workflow list --repo JotJunior/claude-ai-tips

# Disparar manualmente apos configurar o Pages
gh workflow run publish-site.yml --repo JotJunior/claude-ai-tips

# Acompanhar a execucao mais recente
gh run watch --repo JotJunior/claude-ai-tips
```

## Branch protection (opcional — §6.5)

Para single-dev project este passo e opcional. Se desejar:

1. `Settings → Branches → main → Add classic branch protection rule`.
2. Marque **Require status checks to pass before merging**.
3. Em **Status checks**, busque por `publish-site / Build (mkdocs --strict)`
   e adicione como obrigatorio.
4. Save.

Resultado: PRs com build quebrado nao podem fazer merge.

## Custos / SLA

- GitHub Pages e gratuito para repositorios publicos (limite generoso
  de banda).
- Tempo medio de deploy: 1-3 minutos (build ~30-60s + deploy ~30s).
- SC-002 alvo: <=5 min wallclock end-to-end.

## Rollback

Se um deploy quebrar o site:

1. Reverter o commit problematico em `main` (`git revert HEAD`).
2. Push — o workflow re-roda automaticamente com a versao anterior.
3. O environment `github-pages` no GitHub mostra historico de deploys
   e permite re-deploy de um deploy anterior via UI:
   `https://github.com/JotJunior/claude-ai-tips/deployments`.
