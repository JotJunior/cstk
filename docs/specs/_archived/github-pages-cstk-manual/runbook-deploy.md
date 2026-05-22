# Runbook — Primeiro Deploy + Operacao Continua do Site

**Feature:** `github-pages-cstk-manual`
**Audiencia:** operador/mantenedor do repositorio `claude-ai-tips`
**Pre-requisito:** branch `github-pages` (ou `main`, conforme `publish-site.yml`)
com todos os artefatos das FASES 1-8 commitados.

> Este runbook fecha o ciclo execute-task da feature. Ele documenta
> exatamente o que o operador precisa fazer **uma unica vez** para
> publicar o site, mais o que precisa rodar **depois** (Lighthouse,
> JS-disabled, smoke browser) — tarefas que dependem do site real
> rodando e nao podem ser feitas pelo orquestrador autonomo.

---

## 1. Pre-flight local (opcional mas recomendado)

Antes de empurrar para o GitHub, valide o build localmente.

### 1.1 Bootstrap das dependencias

```sh
# Imprime instrucoes de instalacao (NAO instala automaticamente —
# respeita FR-018 do agente-00c: zero side-effect de install).
sh scripts/bootstrap-docs.sh
```

O script imprime o passo-a-passo para criar `.venv-docs`, instalar
`requirements-docs.txt` e rodar `mkdocs build --strict`. Execute os
comandos manualmente conforme indicado.

### 1.2 Smoke build local

```sh
sh scripts/smoke-site.sh           # build estrito + grep negativo de trackers
sh scripts/smoke-site.sh --serve   # build + servidor em http://127.0.0.1:8000/
```

O smoke checa:

- `mkdocs build --strict` retorna exit 0
- `site/` contem `index.html`, `skills/index.html`, `agents/index.html`,
  `commands/index.html`
- Nenhuma string `googletagmanager`, `google-analytics`, `gtag(`, `ga(`,
  `mixpanel`, `segment` no HTML gerado (cenario 10 do plan §1.9)

Se o smoke falha localmente, corrigir antes de empurrar — o CI tambem
falhara.

### 1.3 Re-validacao do gen_pages.py (sem mkdocs)

Para verificar que o hook continua emitindo o conjunto correto de paginas
mesmo sem instalar mkdocs, ver o apendice empirico em
`quality-report.md` (secao A.1).

---

## 2. Primeiro deploy (one-shot)

### 2.1 Habilitar GitHub Pages

No GitHub, em `Settings -> Pages`:

1. **Source:** `GitHub Actions` (NAO `Deploy from a branch`)
2. **Custom domain:** vazio (a menos que o operador queira CNAME)
3. **Enforce HTTPS:** ativado

Sem esse passo, o workflow `publish-site.yml` falha na etapa
`actions/deploy-pages` com `Pages site not found`.

### 2.2 Push da branch publicadora

```sh
# Confirme a branch alvo no workflow:
grep -A2 'on:' .github/workflows/publish-site.yml | head -10

# Push (normalmente main; nesta feature usa-se github-pages durante o
# desenvolvimento, depois faz-se merge para main):
git push origin <branch>
```

### 2.3 Monitorar o build

1. Abrir `https://github.com/JotJunior/claude-ai-tips/actions`
2. Localizar a run mais recente do workflow `publish-site.yml`
3. Aguardar jobs `build` e `deploy` ficarem verdes
4. SLA esperado: push -> site publicado <= 10 minutos (SC-001 da spec)

### 2.4 Validar URL publica

URL canonica: **`https://jotjunior.github.io/claude-ai-tips/`**

```sh
# Smoke remoto rapido (sem login)
curl -sI https://jotjunior.github.io/claude-ai-tips/ | head -3
curl -sI https://jotjunior.github.io/claude-ai-tips/skills/briefing/ | head -3
```

Esperado: HTTP/2 200 em ambas.

---

## 3. Post-deploy manual (acoes do operador)

Estas validacoes nao podem ser automatizadas pelo agente-00c — exigem
browser, GUI ou interacao humana. Ficam aqui documentadas para
checklist pos-primeiro-deploy.

### 3.1 Validacao em modo anonimo (T-8.2)

1. Abrir `https://jotjunior.github.io/claude-ai-tips/` em janela
   privada/anonima (sem cache, sem sessao GitHub).
2. Validar **acceptance scenario 1** da spec User Story 1:
   - Pitch "Conjunto de ferramentas para aumentar a produtividade"
     visivel acima da dobra
   - 3 categorias (skills, agents, commands) com cards
   - One-liner `cstk install` copiavel via botao de code-block
3. Acessar `/skills/briefing/` e validar:
   - Renderiza `SKILL.md` integralmente
   - Botao "Edit this page" aponta para
     `https://github.com/JotJunior/claude-ai-tips/edit/main/global/skills/briefing/SKILL.md`
4. Testar busca: digitar "briefing" no header search — autocompletar
   deve mostrar a pagina e o snippet.

### 3.2 Lighthouse (T-7.2.1 a T-7.2.4 deferidas)

Rodar via DevTools Chrome ou CLI:

```sh
# Via CLI (requer Node + lighthouse global):
npx lighthouse https://jotjunior.github.io/claude-ai-tips/ \
  --only-categories=performance,accessibility \
  --preset=desktop --view

npx lighthouse https://jotjunior.github.io/claude-ai-tips/skills/briefing/ \
  --only-categories=performance,accessibility \
  --preset=desktop --view
```

**SC-003 da spec:** score Performance >= 90 e Accessibility >= 90 em
ambas as URLs. Documentar violacoes em
`docs/specs/github-pages-cstk-manual/FASE-8-report.md` (criar apenas
se houver achados).

### 3.3 JS-disabled validation (T-7.5 deferida)

1. DevTools Chrome -> Command Menu (Cmd+Shift+P) -> "Disable JavaScript"
2. Recarregar `/` e `/skills/briefing/`
3. Validar:
   - Conteudo principal legivel (markdown renderizado server-side)
   - TOC visivel e links navegam
   - Botao "Copy" do code block NAO funciona (esperado — progressive enhancement)
   - Busca NAO funciona (esperado — lunr.js precisa de JS)
4. Re-habilitar JS apos validar

### 3.4 Inspecao de trackers (T-7.4.3 deferida)

DevTools -> Network -> filtrar por "analytics", "tracking", "gtag", "ga":
deve ficar VAZIO.

DevTools -> Elements -> inspecionar `<head>`: nenhum
`<script src="https://(analytics|gtm|ga|mixpanel|segment)...">`.

### 3.5 Decisao sobre fontes (T-7.4.4, T-8.6)

A configuracao atual em `mkdocs.yml`:

```yaml
theme:
  font:
    text: Inter
    code: JetBrains Mono
```

Material >= 9.5 baixa essas fontes de `fonts.googleapis.com` /
`fonts.gstatic.com` no primeiro acesso. **Isso e CDN, nao analytics**
— cenario 10 do plan exclui explicitamente `fonts.gstatic.com` /
`fonts.googleapis.com` da auditoria de trackers.

Opcoes:

| Opcao | Tradeoff | Quando escolher |
|-------|----------|-----------------|
| Manter Inter + JetBrains Mono via CDN | Default Material; melhor tipografia | Maioria dos casos (escolha atual) |
| `theme.font: false` | Usa system stack; zero CDN externo | Compliance estrito (privacidade UE) |
| Self-host fontes | Performance previsivel; mais infra | Quando CDN do Google e bloqueado |

**Decisao da feature** (registrada em `state.json`): manter CDN Material
default. Justificativa: site e documentacao publica de toolkit
open-source, sem PII, sem requisito de compliance privacidade. CDN
google fonts e standard de Material e nao constitui tracker (nao
correlaciona usuario, apenas serve arquivos de fonte estaticos).

---

## 4. Operacao continua

### 4.1 Atualizacao de conteudo

**Regra de ouro (Principio D-I):** edite SEMPRE o arquivo fonte
canonico, NUNCA o shim virtual.

| Atualizar | Editar arquivo |
|-----------|----------------|
| Conteudo de uma skill | `global/skills/<nome>/SKILL.md` |
| Conteudo de skill Go/.NET | `language-related/<lang>/skills/<nome>/SKILL.md` |
| Pagina de agent | `global/agents/<nome>.md` |
| Pagina de command | `global/commands/<nome>.md` |
| Landing page | `docs-site/index.md` |
| Manual operacional | `docs-site/manual/*.md` |
| Catalogos auto-gerados | NAO EDITAR — `docs-site/hooks/gen_pages.py` enumera dinamicamente |

Apos editar e fazer push, o workflow `publish-site.yml` re-publica em
<= 10 minutos.

### 4.2 Rebuild manual (sem mudanca de conteudo)

Cenarios: recovery apos falha CI, rollback, validar mudanca de
dependencia em `requirements-docs.txt`.

1. Abrir `Actions -> publish-site.yml`
2. Botao "Run workflow" -> selecionar branch -> "Run workflow"
3. Aguardar deploy verde

Tambem disparavel via `gh` CLI:

```sh
gh workflow run publish-site.yml --ref main
```

### 4.3 Rollback (apos deploy quebrado)

**Opcao A — revert + push (recomendado):**

```sh
# Identificar commit ruim
git log --oneline -5

# Reverter
git revert <sha-ruim>
git push origin main
```

O workflow re-publica a versao revertida em <= 10 min.

**Opcao B — re-deploy de versao anterior:**

```sh
# Resetar para commit anterior conhecido como bom
git reset --hard <sha-bom>
git push --force-with-lease origin main
```

NUNCA fazer `git push --force` sem `--force-with-lease`. NUNCA fazer
isso em main sem confirmacao explicita do mantenedor.

### 4.4 Resolver issues capturadas pos-deploy (T-8.5)

1. Inspecionar logs do build: `Actions -> publish-site.yml -> <run> -> build job`
2. Erros comuns:
   - **`mkdocs build --strict` falha por link quebrado:** procurar
     `WARNING - Documentation file 'X' contains a link to 'Y' which
     does not exist` no log; corrigir o link em `<arquivo-fonte>.md`.
   - **`gen_pages.py` falha:** geralmente YAML malformado em algum
     SKILL.md; corrigir frontmatter.
   - **Deploy job falha com "Pages site not found":** Settings -> Pages
     nao tem `Source: GitHub Actions` (ver secao 2.1).
3. Bugs estruturais (nao apenas conteudo): abrir issue em
   `https://github.com/JotJunior/claude-ai-tips/issues` com label
   `docs-site` + reproducao + log relevante.

---

## 5. Smoke pos-publish (1x por release importante)

Apos qualquer release major (mudanca de tema, mudanca de toolchain,
upgrade de Material), repetir manualmente:

- [ ] Secao 3.1 (validacao anonima)
- [ ] Secao 3.2 (Lighthouse)
- [ ] Secao 3.3 (JS-disabled)
- [ ] Secao 3.4 (sem trackers)

Documentar resultados em `docs/specs/github-pages-cstk-manual/FASE-8-report.md`
(criar arquivo na primeira vez).

---

## Apendice — Mapa de arquivos relevantes

| Arquivo | Funcao |
|---------|--------|
| `mkdocs.yml` | Config raiz do site (tema, nav, plugins) |
| `requirements-docs.txt` | Deps pinadas (mkdocs, material, gen-files) |
| `docs-site/hooks/gen_pages.py` | Hook que enumera fontes canonicas |
| `docs-site/index.md` | Landing page com pitch + 3 categorias |
| `docs-site/manual/` | Manual operacional (instalacao, atualizacao, troubleshooting) |
| `docs-site/overrides/` | Customizacoes do tema Material |
| `scripts/bootstrap-docs.sh` | Imprime instrucoes de instalacao local |
| `scripts/smoke-site.sh` | Build estrito + grep negativo de trackers |
| `scripts/check-links.py` | Validador stdlib de links internos + snippets |
| `.github/workflows/publish-site.yml` | CI/CD de publicacao |

---

**Fim do runbook.** Em duvida, consultar `docs/specs/github-pages-cstk-manual/spec.md`
(requisitos funcionais com IDs FR-XXX) e `plan.md` (decisoes tecnicas).
