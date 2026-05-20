# Implementation Plan: GitHub Pages — Manual do cstk

**Feature**: `github-pages-cstk-manual`
**Created**: 2026-05-19
**Spec**: `docs/specs/github-pages-cstk-manual/spec.md` (Status: Clarified)
**Constitution (global)**: `docs/constitution.md` v1.1.0
**Constitution (delta)**: `docs/specs/github-pages-cstk-manual/constitution.md` v1.0.0
**Branch**: `github-pages`

---

## Summary

Site estatico publicado via GitHub Pages que serve como (a) manual do
`cstk` e (b) catalogo navegavel das skills/agents/commands distribuidos
pelo toolkit `claude-ai-tips`. Conteudo derivado dos arquivos `.md`
canonicos do repositorio (D-I: Documentation-as-Source-of-Truth) — sem
segunda fonte de verdade.

**Abordagem tecnica** (consolidada do `/clarify`):

- **Stack**: MkDocs Material (Python) — build determinista, busca
  built-in (lunr.js), tema WCAG AA por default, ja referenciada na
  constitution-delta.
- **Source dir**: `docs-site/` (na raiz do repo), com `mkdocs.yml`
  tambem na raiz (`docs_dir: docs-site/`).
- **Pipeline de geracao**: hook `mkdocs-gen-files` que enumera SKILL.md
  / agent.md / command.md das fontes canonicas (`global/skills/*/`,
  `language-related/<lang>/skills/*/`, `global/agents/*.md`,
  `global/commands/*.md`) e gera shims em `docs-site/` referenciando
  o conteudo via `!!! include` ou `{% include %}` (macros plugin).
  Sem duplicacao fisica do conteudo.
- **Plugins**: `material` (tema), `search` (lunr.js built-in),
  `awesome-pages` (nav hierarquica auto), `gen-files` (geracao de
  shims), `macros` (include de arquivos externos), `meta` (frontmatter).
- **Publicacao**: `actions/upload-pages-artifact@v3` +
  `actions/deploy-pages@v4` em workflow `.github/workflows/publish-site.yml`,
  triggers `push` na `main` + `pull_request` (build-only) +
  `workflow_dispatch`.
- **Versionamento da doc**: NAO no MVP (hook arquitetural para `mike`
  pos-MVP, conforme D-VI + FR-020).
- **Bootstrap**: `scripts/bootstrap-docs.sh` (POSIX sh) lista comandos
  para o operador instalar deps manualmente — script NAO executa
  `pip install` autonomamente (FR-018 do agente-00c).

---

## Constitution Check

*GATE: deve passar antes do Phase 0. Re-checado apos Phase 1 (secao
final).*

### Global v1.1.0 (`docs/constitution.md`)

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD Recursivo | PASS | Plan parte de spec.md Clarified + constitution-delta. Plano nao gera codigo, so artefatos SDD. |
| II. POSIX sh puro (scripts) | PASS | `scripts/bootstrap-docs.sh` sera POSIX sh `#!/bin/sh` (sem bashisms). MkDocs em si e Python, mas roda em CI/maquina do operador — nao e script do toolkit. |
| III. Formato canonico de skill | N/A | Feature publica skills existentes, nao cria skills novas. |
| IV. Zero coleta remota | PASS | Busca client-side (lunr.js asset estatico), sem analytics. CDN para fontes opcional com fallback local. Auditavel via grep no HTML publicado (SC-005, FR-019). |
| V. Profundidade > adocao | PASS | Build determinista (FR-026), idempotente. Sem features de UI superfluas no MVP (tema default, sem branding custom). |

### Delta v1.0.0 (`docs/specs/github-pages-cstk-manual/constitution.md`)

| Principio | Status | Notas |
|-----------|--------|-------|
| D-I. Documentation-as-Source-of-Truth (NON-NEG.) | PASS | Hook `gen-files` cria shims que apenas `include` o conteudo canonico — zero paragrafo substantivo em `docs-site/` alem de metadados/CSS. |
| D-II. Static-Site-First (NON-NEG.) | PASS | Build gera HTML+CSS+JS estaticos. Sem servidor de app. JS opcional (busca, copy-button) — leitura funciona com JS off (FR-014, SC-010). |
| D-III. Automated-Publishing | PASS | Workflow `publish-site.yml` com triggers push/PR/dispatch. Tempo total <=5min (SC-002). PR sem publish, status check obrigatorio. |
| D-IV. Searchable-by-Default | PASS | Plugin `search` built-in mkdocs-material (lunr.js). Indice estatico, latencia <=200ms (SC-004). |
| D-V. Accessibility-Floor (WCAG AA) | PASS | Tema Material entrega AA por default. Plano define meta Lighthouse >=90 (SC-003), `<html lang>` (FR-013), TAB-navigation (FR-013). |
| D-VI. Versioning-Friendly | PASS | Slugs estaveis derivados do path-fonte (FR-016, FR-017). `mkdocs.yml` estruturado para receber `mike` no futuro (FR-020). |

**Resultado**: GATE PASS. Sem violacoes bloqueantes.

---

## Technical Context

| Campo | Valor |
|-------|-------|
| **Linguagem (build)** | Python >=3.11 (mkdocs e ecossistema) |
| **Linguagem (scripts)** | POSIX sh (`#!/bin/sh`) — `scripts/bootstrap-docs.sh`, hooks opcionais |
| **Gerador de site** | MkDocs `>=1.6.0` |
| **Tema** | `mkdocs-material >=9.5.0` |
| **Plugins MkDocs** | `mkdocs-awesome-pages-plugin >=2.9`, `mkdocs-gen-files >=0.5`, `mkdocs-macros-plugin >=1.0`, `mkdocs-material[imaging]` (opcional, social cards) |
| **Markdown extensions** | `pymdown-extensions >=10.7` (admonitions, tabbed, superfences, snippets para include) |
| **Storage** | filesystem do runner Ubuntu (CI) + artifact do GitHub Pages |
| **Auth/secrets** | `GITHUB_TOKEN` efemero do runner (`permissions: pages:write, id-token:write`) |
| **Plataforma de deploy** | GitHub Pages environment (`github-pages`) via `actions/deploy-pages@v4` |
| **CI runner** | `ubuntu-latest` |
| **Source dir** | `docs-site/` (relativo a raiz) |
| **Config file** | `mkdocs.yml` (raiz do repo) |
| **Workflow** | `.github/workflows/publish-site.yml` |
| **Build time target** | <=60s local, <=5min CI total (FR-018, SC-002) |
| **Search latency target** | <=200ms (SC-004) |
| **A11y target** | Lighthouse Accessibility >=90 (SC-003) |
| **Testing** | `mkdocs build --strict` (link check builtin), smoke render manual, Lighthouse manual (MVP) |
| **NEEDS CLARIFICATION restantes** | 0 (clarify resolveu 6/6 + delta congelou pin de versao para resolucao pos-MVP) |

**Pin de versao** (resolve `TODO(MKDOCS_VERSION_PIN)` do delta): pinar
no `requirements-docs.txt` versoes minimas com upper bound de minor
(ex: `mkdocs-material>=9.5,<10.0`). Rationale: minor bumps do material
sao backward-compatible historicamente; major (10.0) sera evaluation
event explicito.

---

## Phase 0 — Research

### Decision 1. Plugin de inclusao de arquivos externos ao `docs_dir`

**Problema**: o conteudo canonico vive FORA do `docs-site/` (em
`global/skills/*/SKILL.md`, `README.md`, `CHANGELOG.md`, etc). MkDocs
nativamente so consome arquivos sob `docs_dir`. Precisamos de
mecanismo de "ponte" que evite copia fisica do conteudo (D-I).

**Decision**: `mkdocs-gen-files` (gera arquivos virtuais em build-time
sem polluir o filesystem) + `pymdown-extensions/snippets` (sintaxe
`--8<-- "path/to/file.md"` para inclusao literal).

**Rationale**:

- `mkdocs-gen-files` ja e padrao consagrado na comunidade MkDocs para
  geracao de paginas (ex: mkdocstrings, awesome-pages combinam com ele).
- `snippets` resolve a inclusao em runtime do build sem copiar
  arquivos — caminho relativo a raiz do repo via `base_path`.
- Hook Python (`docs-site/hooks/gen_pages.py`) enumera as fontes
  canonicas via glob, cria virtual page `docs-site/skills/<nome>.md`
  com conteudo `--8<-- "global/skills/<nome>/SKILL.md"` + frontmatter
  derivado (titulo, categoria).
- Mantem o `docs-site/` enxuto: so config, CSS minimo, overrides de
  template e arquivos do manual escritos especificamente para o site
  (que tambem devem ser pontes para README/CHANGELOG quando possivel).

**Alternatives considered**:

- **Symlinks** (criar `docs-site/skills/briefing.md` -> `../../global/skills/briefing/SKILL.md`):
  rejeitado — frageis em Windows; mistura conteudo no `docs-site/` no
  filesystem (mesmo que via symlink, fere D-I "nenhum texto substantivo
  no docs/site/").
- **Copy step em CI** (cp dos `.md` para `docs-site/` antes do `mkdocs build`):
  rejeitado — cria copia fisica intermediaria; build local divergiria
  do CI a menos que o operador rode o copy manualmente; viola
  idempotencia perceptual (`git status` mostra arquivos copiados).
- **Plugin `mkdocs-monorepo-plugin`** (suporte a `nav: [!include /path/mkdocs.yml]`):
  rejeitado — overkill, projetado para monorepo de docs (multi-mkdocs),
  nao para nosso caso de "varios arquivos espalhados".

### Decision 2. Geracao automatica de navegacao

**Problema**: FR-017 exige que adicionar uma nova skill seja
SUFICIENTE para que ela apareca no proximo build — zero edicao manual
de listas hardcoded.

**Decision**: `mkdocs-awesome-pages-plugin` para nav hierarquica auto
+ `mkdocs-gen-files` cria as paginas virtuais.

**Rationale**:

- `awesome-pages` infere navegacao da estrutura de diretorios do
  `docs_dir`, ordenando por filename (alfabetico) ou via `.pages` files
  que sobrescrevem ordem/titulo localmente.
- Como `gen-files` produz a estrutura `docs-site/skills/<nome>.md`,
  `docs-site/skills/<lang>/<nome>.md`, etc. dinamicamente,
  `awesome-pages` ja gera o `nav` correto sem edicao do `mkdocs.yml`.
- Para o "Manual" (paginas escritas a mao em `docs-site/manual/`),
  ordem nao-alfabetica e definida via `.pages` em
  `docs-site/manual/.pages`.

**Alternatives considered**:

- **`nav` explicita no `mkdocs.yml`**: rejeitado — requer edicao
  manual a cada skill nova, viola FR-017/SC-008.
- **`mkdocs-literate-nav`**: rejeitado — formato `SUMMARY.md` exige
  manutencao manual de uma lista (mesmo problema).

### Decision 3. Estrategia de slug/URL

**Problema**: FR-016 fixa estrutura `/skills/<nome>/`,
`/skills/<lang>/<nome>/`, `/agents/<nome>/`, `/commands/<nome>/`,
`/manual/<topico>/`. Precisamos garantir que `gen-files` produza
exatamente esses paths.

**Decision**: hook `gen_pages.py` cria virtual paths consistentes:

| Fonte canonica | Path virtual em `docs-site/` | URL gerada |
|---|---|---|
| `global/skills/<nome>/SKILL.md` | `skills/<nome>.md` | `/skills/<nome>/` |
| `language-related/<lang>/skills/<nome>/SKILL.md` | `skills/<lang>/<nome>.md` | `/skills/<lang>/<nome>/` |
| `global/agents/<nome>.md` | `agents/<nome>.md` | `/agents/<nome>/` |
| `global/commands/<nome>.md` | `commands/<nome>.md` | `/commands/<nome>/` |
| `docs-site/manual/<topico>.md` (escrito a mao) | `manual/<topico>.md` | `/manual/<topico>/` |

Configurar `use_directory_urls: true` no `mkdocs.yml` (default do
material) para que `/skills/briefing/` resolva para
`skills/briefing/index.html`.

**Rationale**: o nome do diretorio fonte (`global/skills/briefing/`) ja
e o slug — nao ha transformacao alem de strip do prefixo `global/`.
Renomear skill = renomear diretorio = URL muda automaticamente. Aviso
explicito em CHANGELOG do site (FR-016) e responsabilidade humana.

### Decision 4. Tratamento de frontmatter Claude-specifico

**Problema**: SKILL.md tem frontmatter YAML com `name:`,
`description:`, `allowed-tools:`, `model:`, etc. MkDocs material ja
parseia frontmatter, mas chaves nao-padrao podem gerar warning ou ser
ignoradas. FR-024 manda passar puro + warning.

**Decision**: confiar no parseamento default do mkdocs-material
(extensao `meta` builtin). Chaves nao reconhecidas ficam como
metadados de pagina acessiveis via `page.meta.<key>` no template
(consumido por overrides para mostrar "Triggers" ou "Allowed tools"
no header da pagina, opcional pos-MVP).

**Mapping minimo**:

- `name:` -> usado como `title` se nao houver h1 explicito no body.
- `description:` -> renderizado como subtitulo na pagina (via override
  de template OU como `meta description` para SEO).
- `allowed-tools:`, `model:`, demais campos -> ignorados pelo
  rendering padrao no MVP; preservados em `page.meta` para uso futuro.

**Build emite warning** quando `gen_pages.py` detecta frontmatter
malformado (YAML invalido) — warning nao bloqueia build (FR-024).

### Decision 5. Link checking

**Problema**: FR-011 exige validacao de links internos no build, com
preferencia por erro bloqueante no MVP.

**Decision**: usar `mkdocs build --strict` como gate. O modo strict do
MkDocs ja eleva warnings (incluindo broken internal links) para erro,
bloqueando build.

**Rationale**:

- Built-in, zero plugin adicional.
- Cobre links internos (`[txt](other-page.md)`) automaticamente.
- Para links externos (http://, https://) NAO valida — aceitavel no
  MVP (validar links externos exige rede em CI, gera flakes e nao tem
  blast radius critico).

**Alternatives considered**:

- **`mkdocs-htmlproofer-plugin`**: rejeitado para MVP — adiciona
  dependencia e tempo de build; pode entrar em fase pos-MVP se broken
  external links virarem problema operacional.
- **`mkdocs-linkcheck`**: rejeitado pelo mesmo motivo.

### Decision 6. CSP e HTML inline em SKILL.md

**Problema**: alguns SKILL.md contem HTML inline. FR-024 manda
preservar (pass-through) mas o tema mkdocs-material aplica
sanitization via Python-Markdown.

**Decision**: usar configuracao default do material — HTML inline
permitido por Markdown padrao (`md_extensions: [md_in_html]`). CSP
hardening e responsabilidade do GitHub Pages (que serve com
`Content-Security-Policy` minimo via headers default). Scripts inline
arbitrarios sao impotentes pois nao temos backend para `eval`.

**Limitacao aceita**: SKILL.md que contem JavaScript inline com tags
`<script>` sera renderizado como tag `<script>` literal mas o navegador
o executara como qualquer outro script da pagina. Mitigacao no MVP:
auditoria manual periodica de SKILL.md (zero JS hoje, verificavel via
`grep -rn '<script' global/`). Pos-MVP: adicionar custom CSP header
via `_headers` (nao suportado por GitHub Pages diretamente — pode
exigir migracao para Cloudflare Pages futuramente, mas violaria D-II
"sem SaaS terceiro obrigatorio").

### Decision 7. Bootstrap de dependencias sem instalacao autonoma

**Problema**: FR-018 (do agente-00c) proibe instalar deps
autonomamente. Operador precisa rodar `pip install -r
requirements-docs.txt` antes de `mkdocs build` local.

**Decision**: criar `scripts/bootstrap-docs.sh` (POSIX sh) que apenas
EMITE comandos a serem executados, sem rodar:

```sh
#!/bin/sh
# bootstrap-docs.sh — emite instrucoes para instalar deps do site
set -eu
cat <<EOF
# Bootstrap do site (docs-site/):
python3 -m venv .venv-docs
. .venv-docs/bin/activate
pip install -r requirements-docs.txt
# Para build:
mkdocs build --strict
# Para serve local:
mkdocs serve
EOF
```

Em CI, o workflow instala via `pip install -r requirements-docs.txt`
diretamente (sem chamar o script).

### Decision 8. Versionamento (mike) — explicitamente adiado

**Decision**: NAO ativar `mike` no MVP, conforme spec §FR-020 +
constitution-delta §D-VI SHOULD.

**Rationale**: complexidade adicional sem demanda do briefing.
Estrutura de paths e `mkdocs.yml` ja sao compativeis com adicao
futura (slugs estaveis derivados do path-fonte).

**Trigger para reavaliar**: primeira tag SemVer MAJOR do toolkit
(v2.0.0) ou primeiro pedido externo por "versao anterior da doc".

### Decision 9. Conteudo do "Manual"

**Problema**: FR-005 lista paginas obrigatorias do manual:
instalacao, profiles, comandos principais (`cstk install`, `cstk
session`, `cstk 00c`), fluxo SDD. Onde vive a fonte canonica?

**Decision**:

- **Instalacao** + **profiles**: fonte canonica e `README.md` da raiz.
  `docs-site/manual/instalacao.md` e ponte (`--8<-- "README.md:install-section"`)
  usando ANCORAS de snippets (marcadores no README:
  `<!-- --8<-- [start:install-section] -->`
  ... `<!-- --8<-- [end:install-section] -->`).
- **Comandos principais**: fonte canonica e `cli/README.md`.
  `docs-site/manual/comandos.md` faz `--8<-- "cli/README.md"` (inclusao
  total ou seccionada via ancoras).
- **Fluxo SDD**: pagina escrita a mao em `docs-site/manual/fluxo-sdd.md`
  com narrativa proprio do manual + links para skills (`/skills/briefing/`,
  `/skills/specify/`, `/skills/clarify/`, etc).

**Rationale**: D-I exige fonte unica; ancoras de snippets permitem
seccionar README sem duplicar. Onde nao existe fonte canonica (visao
narrativa do fluxo SDD), criar conteudo de manual conta como
"metadados de navegacao" (D-I MUST permite "arquivos-ponte que
referenciam fontes canonicas" + paginas-indice).

### Decision 10. Pagina-indice CHANGELOG

**Decision**: criar `docs-site/changelog.md` com `--8<-- "CHANGELOG.md"`
e link no header do site. Inclusao total — CHANGELOG.md ja e
auto-suficiente.

---

## Phase 1 — Design

### 1.1 Project Structure (a ser criada)

```
claude-ai-tips/                       # repo raiz
|
+-- mkdocs.yml                        # config MkDocs (raiz, docs_dir: docs-site/)
+-- requirements-docs.txt             # deps Python pinadas
+-- scripts/
|   +-- bootstrap-docs.sh             # NOVO: emite instrucoes pip install
|
+-- docs-site/                        # NOVO: source dir do site
|   +-- index.md                      # landing page (pitch + 3 categorias)
|   +-- .pages                        # awesome-pages: ordem do top-level
|   +-- changelog.md                  # ponte para CHANGELOG.md
|   |
|   +-- manual/                       # paginas escritas a mao + pontes
|   |   +-- .pages                    # ordem: instalacao, profiles, comandos, fluxo-sdd
|   |   +-- instalacao.md             # ponte para README.md (snippet)
|   |   +-- profiles.md               # ponte para README.md (snippet)
|   |   +-- comandos.md               # ponte para cli/README.md
|   |   +-- fluxo-sdd.md              # narrativa proprio + links para skills
|   |
|   +-- skills/                       # virtual (gerado por gen_pages.py)
|   |   +-- index.md                  # auto-listagem (gerada) — Skills Globais + per-lang
|   |   +-- <nome>.md                 # 1 por skill global (virtual)
|   |   +-- go/
|   |   |   +-- <nome>.md             # 1 por skill go (virtual)
|   |   +-- dotnet/
|   |       +-- <nome>.md             # 1 por skill dotnet (virtual)
|   |
|   +-- agents/                       # virtual
|   |   +-- index.md
|   |   +-- <nome>.md
|   |
|   +-- commands/                     # virtual
|   |   +-- index.md
|   |   +-- <nome>.md
|   |
|   +-- hooks/
|   |   +-- gen_pages.py              # mkdocs-gen-files hook
|   |
|   +-- overrides/                    # custom templates do material (opcional, MVP usa default)
|   |   +-- (vazio no MVP)
|   |
|   +-- assets/
|       +-- favicon.png               # opcional
|       +-- extra.css                 # CSS minimo (vazio no MVP)
|
+-- .github/
    +-- workflows/
        +-- publish-site.yml          # NOVO: workflow GitHub Actions
        +-- release.yml               # existente, nao toca
```

### 1.2 `requirements-docs.txt` (pinned versions)

```text
# MVP pin — bump via PR explicito
mkdocs>=1.6.0,<2.0.0
mkdocs-material>=9.5.0,<10.0.0
mkdocs-awesome-pages-plugin>=2.9.0,<3.0.0
mkdocs-gen-files>=0.5.0,<1.0.0
mkdocs-macros-plugin>=1.0.0,<2.0.0
pymdown-extensions>=10.7.0,<11.0.0
```

### 1.3 `mkdocs.yml` (esqueleto)

```yaml
site_name: cstk — Claude Stack Toolkit
site_url: https://jotjunior.github.io/claude-ai-tips/
site_description: Manual do cstk e catalogo de skills, agents e commands do toolkit claude-ai-tips
repo_url: https://github.com/JotJunior/claude-ai-tips
repo_name: JotJunior/claude-ai-tips
edit_uri: edit/main/

docs_dir: docs-site
use_directory_urls: true
strict: true                          # broken internal links viram erro (FR-011)

theme:
  name: material
  language: pt-BR
  features:
    - navigation.tabs
    - navigation.sections
    - navigation.indexes
    - navigation.top
    - search.suggest
    - search.highlight
    - content.code.copy
    - content.tabs.link
  palette:
    - media: "(prefers-color-scheme: light)"
      scheme: default
      toggle:
        icon: material/weather-night
        name: Tema escuro
    - media: "(prefers-color-scheme: dark)"
      scheme: slate
      toggle:
        icon: material/weather-sunny
        name: Tema claro

plugins:
  - search                            # lunr.js built-in (D-IV)
  - awesome-pages                     # nav hierarquica auto
  - gen-files:
      scripts:
        - hooks/gen_pages.py
  - macros

markdown_extensions:
  - admonition
  - attr_list
  - footnotes
  - md_in_html
  - pymdownx.details
  - pymdownx.highlight:
      anchor_linenums: true
  - pymdownx.inlinehilite
  - pymdownx.snippets:
      base_path:
        - .                           # raiz do repo
        - docs-site
      check_paths: true
  - pymdownx.superfences
  - pymdownx.tabbed:
      alternate_style: true
  - tables
  - toc:
      permalink: true

extra_css:
  - assets/extra.css                  # vazio no MVP, hook para customizacao
```

### 1.4 `hooks/gen_pages.py` (estrutura conceitual)

```python
"""mkdocs-gen-files hook — enumera fontes canonicas e gera shims em docs-site/."""
from pathlib import Path
import mkdocs_gen_files

REPO_ROOT = Path(__file__).resolve().parents[2]  # docs-site/hooks/ -> repo root


def gen_skill_pages():
    # Skills globais: global/skills/<nome>/SKILL.md -> docs-site/skills/<nome>.md
    for skill_dir in (REPO_ROOT / "global" / "skills").iterdir():
        skill_md = skill_dir / "SKILL.md"
        if not skill_md.is_file():
            continue
        slug = skill_dir.name
        virtual_path = f"skills/{slug}.md"
        with mkdocs_gen_files.open(virtual_path, "w") as f:
            # snippets include do conteudo canonico
            f.write(f'--8<-- "global/skills/{slug}/SKILL.md"\n')
        mkdocs_gen_files.set_edit_path(virtual_path, f"global/skills/{slug}/SKILL.md")

    # Skills por linguagem: language-related/<lang>/skills/<nome>/SKILL.md
    lang_root = REPO_ROOT / "language-related"
    if lang_root.is_dir():
        for lang_dir in lang_root.iterdir():
            skills_dir = lang_dir / "skills"
            if not skills_dir.is_dir():
                continue
            lang = lang_dir.name
            for skill_dir in skills_dir.iterdir():
                skill_md = skill_dir / "SKILL.md"
                if not skill_md.is_file():
                    continue
                slug = skill_dir.name
                virtual_path = f"skills/{lang}/{slug}.md"
                with mkdocs_gen_files.open(virtual_path, "w") as f:
                    f.write(f'--8<-- "language-related/{lang}/skills/{slug}/SKILL.md"\n')
                mkdocs_gen_files.set_edit_path(
                    virtual_path, f"language-related/{lang}/skills/{slug}/SKILL.md"
                )


def gen_agent_pages():
    for agent_md in (REPO_ROOT / "global" / "agents").glob("*.md"):
        slug = agent_md.stem
        virtual_path = f"agents/{slug}.md"
        with mkdocs_gen_files.open(virtual_path, "w") as f:
            f.write(f'--8<-- "global/agents/{slug}.md"\n')
        mkdocs_gen_files.set_edit_path(virtual_path, f"global/agents/{slug}.md")


def gen_command_pages():
    for cmd_md in (REPO_ROOT / "global" / "commands").glob("*.md"):
        slug = cmd_md.stem
        virtual_path = f"commands/{slug}.md"
        with mkdocs_gen_files.open(virtual_path, "w") as f:
            f.write(f'--8<-- "global/commands/{slug}.md"\n')
        mkdocs_gen_files.set_edit_path(virtual_path, f"global/commands/{slug}.md")


def gen_index_pages():
    """Gera index.md de skills/, agents/, commands/ com auto-listagem."""
    # ... (enumera novamente e escreve listas markdown)


gen_skill_pages()
gen_agent_pages()
gen_command_pages()
gen_index_pages()
```

### 1.5 Workflow `.github/workflows/publish-site.yml`

```yaml
name: Publish docs site

on:
  push:
    branches: [main]
    paths:
      - 'global/skills/**'
      - 'language-related/**'
      - 'global/agents/**'
      - 'global/commands/**'
      - 'docs-site/**'
      - 'mkdocs.yml'
      - 'requirements-docs.txt'
      - 'README.md'
      - 'CHANGELOG.md'
      - 'cli/README.md'
      - '.github/workflows/publish-site.yml'
  pull_request:
    paths:
      - 'global/skills/**'
      - 'language-related/**'
      - 'global/agents/**'
      - 'global/commands/**'
      - 'docs-site/**'
      - 'mkdocs.yml'
      - 'requirements-docs.txt'
      - 'README.md'
      - 'CHANGELOG.md'
      - 'cli/README.md'
  workflow_dispatch:                          # republicacao manual

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: pages-${{ github.ref }}
  cancel-in-progress: false

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'
          cache: pip

      - name: Install deps
        run: pip install -r requirements-docs.txt

      - name: Build
        run: mkdocs build --strict

      - name: Upload artifact
        if: github.event_name == 'push' || github.event_name == 'workflow_dispatch'
        uses: actions/upload-pages-artifact@v3
        with:
          path: site/

  deploy:
    if: github.event_name == 'push' || github.event_name == 'workflow_dispatch'
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - id: deployment
        uses: actions/deploy-pages@v4
```

**Notas operacionais**:

- Job `build` roda em push, PR e dispatch — sempre valida `--strict`.
- Job `deploy` so roda em push/dispatch (PR e build-only, conforme
  D-III + FR-008).
- `concurrency` evita publicacoes concorrentes; `cancel-in-progress:
  false` para nao matar deploy parcial.

### 1.6 Data Model (mapping fontes -> destinos)

| Fonte canonica (path no repo) | Tipo | Destino virtual em `docs-site/` | URL publicada |
|---|---|---|---|
| `global/skills/<nome>/SKILL.md` | skill global | `skills/<nome>.md` (virtual) | `/skills/<nome>/` |
| `language-related/<lang>/skills/<nome>/SKILL.md` | skill per-lang | `skills/<lang>/<nome>.md` (virtual) | `/skills/<lang>/<nome>/` |
| `global/agents/<nome>.md` | agent | `agents/<nome>.md` (virtual) | `/agents/<nome>/` |
| `global/commands/<nome>.md` | command | `commands/<nome>.md` (virtual) | `/commands/<nome>/` |
| `README.md` (raiz) | manual | `manual/instalacao.md` (real, com snippet) | `/manual/instalacao/` |
| `README.md` (raiz) | manual | `manual/profiles.md` (real, com snippet) | `/manual/profiles/` |
| `cli/README.md` | manual | `manual/comandos.md` (real, com snippet) | `/manual/comandos/` |
| `CHANGELOG.md` | meta | `changelog.md` (real, com snippet completo) | `/changelog/` |
| (escrito a mao) | manual narrativo | `manual/fluxo-sdd.md` | `/manual/fluxo-sdd/` |
| (escrito a mao) | landing | `index.md` | `/` |

**Inventario MVP esperado** (FR-003, SC-006):

- 21 skills globais -> 21 paginas `/skills/<nome>/`
- 8 skills go -> 8 paginas `/skills/go/<nome>/`
- 8 skills dotnet -> 8 paginas `/skills/dotnet/<nome>/`
- 3 agents -> 3 paginas `/agents/<nome>/`
- 3 commands -> 3 paginas `/commands/<nome>/`
- 5+ paginas de manual (`instalacao`, `profiles`, `comandos`,
  `fluxo-sdd`, `changelog`)
- 1 landing (`/`)
- 3 indexes auto (`/skills/`, `/agents/`, `/commands/`)

Total minimo: **52+ paginas geradas**, atende SC-006 (>=43).

### 1.7 Entities (conceitual)

- **CanonicalSource**: arquivo `.md` no repositorio fora de
  `docs-site/`. Atributos: `path` (relativo a raiz), `kind`
  (`skill-global` / `skill-go` / `skill-dotnet` / `agent` / `command`
  / `manual-readme` / `manual-cli` / `changelog`), `slug` (nome do
  arquivo ou diretorio).
- **VirtualShim**: arquivo gerado por `gen_pages.py` em build-time.
  Atributos: `virtual_path` (relativo a `docs-site/`), `content` (apenas
  diretiva `--8<-- "..."`), `edit_path` (aponta para CanonicalSource).
- **ManualPage**: arquivo escrito a mao em `docs-site/manual/`.
  Atributos: `path`, `kind` (`bridge-snippet` / `narrative`), `content`
  (snippet include OU prosa).
- **NavigationNode**: nodo da arvore de navegacao gerada por
  `awesome-pages`. Atributos: `title`, `path`, `order` (inferido ou de
  `.pages`).
- **SearchIndex**: artefato JSON gerado pelo plugin `search` em
  build-time. Localizacao: `site/search/search_index.json`. Consumido
  pelo lunr.js client-side.
- **PublishArtifact**: tarball gerado por `actions/upload-pages-artifact@v3`,
  consumido por `actions/deploy-pages@v4`.

### 1.8 Convencoes de Borda

**Single-layer** (build estatico + assets HTTP servidos por GitHub
Pages). Sem fronteira backend-frontend, sem DB, sem broker. N/A para a
tabela detalhada de convencoes — mas registramos as poucas convencoes
relevantes:

| Camada | Convencao | Validacao | Fonte da verdade |
|--------|-----------|-----------|------------------|
| Slugs de URL | lowercase, kebab-case, sem accent | nome do diretorio/arquivo fonte ja segue | `global/skills/<nome>/`, `global/agents/<nome>.md` |
| Frontmatter YAML | chaves lowercase, camelCase nao usado | parser YAML nativo do material | `SKILL.md` de cada skill |
| Markdown | CommonMark + pymdown-extensions | `mkdocs build --strict` | `mkdocs.yml` (`markdown_extensions`) |
| Encoding | UTF-8 | filesystem + git | todo arquivo `.md` |

**Mapper layer**: N/A. Snippets do `pymdown-extensions` faz inclusao
literal sem transformacao.

**Validacao Zod / schema externo**: N/A.

### 1.9 Quickstart / Cenarios de Teste

#### Cenario 1: Build local determinista

1. Operador instala deps: `sh scripts/bootstrap-docs.sh` -> copia/cola
   comandos -> `pip install -r requirements-docs.txt` no venv.
2. Roda `mkdocs build --strict` na raiz do repo.
3. Roda `mkdocs build --strict` SEGUNDA vez em outro dir
   (`site2/`): `mkdocs build --strict --site-dir site2`.
4. Compara: `diff -r site/ site2/ -x '*.txt' -x 'sitemap.xml'`.
   **Expected**: diff vazio (modulo timestamps embutidos).

#### Cenario 2: Smoke render — landing, skill, agent, command

1. Roda `mkdocs serve` na raiz.
2. Acessa `http://127.0.0.1:8000/` no browser.
3. **Expected**: ve pitch + 3 cards de categoria (Skills, Agents,
   Commands) com contagens nao-nulas, comando de instalacao copiavel.
4. Clica em "Skills" -> ve listagem agrupada (Globais, Go, Dotnet).
5. Abre `/skills/briefing/` -> ve conteudo renderizado de
   `global/skills/briefing/SKILL.md`.
6. Abre `/agents/agente-00c-orchestrator/` -> ve conteudo de
   `global/agents/agente-00c-orchestrator.md`.
7. Abre `/commands/agente-00c/` -> ve conteudo de
   `global/commands/agente-00c.md`.

#### Cenario 3: Busca client-side

1. Abre site no browser.
2. Pressiona `/` (atalho de teclado padrao do material).
3. Digita "briefing".
4. **Expected**: resultado aparece em <=200ms; primeiro hit aponta para
   `/skills/briefing/` com snippet relevante.

#### Cenario 4: Link interno quebrado bloqueia build

1. Edita uma pagina do manual e introduz `[link](pagina-que-nao-existe.md)`.
2. Roda `mkdocs build --strict`.
3. **Expected**: build falha com exit != 0 e mensagem indicando link
   quebrado. PR com essa mudanca recebe status check vermelho (FR-008,
   SC-009).

#### Cenario 5: Skill nova aparece sem edicao manual

1. Cria `global/skills/teste-nova/SKILL.md` com frontmatter minimo +
   body curto.
2. Roda `mkdocs build --strict`.
3. **Expected**: `site/skills/teste-nova/index.html` existe; aparece no
   indice `/skills/` automaticamente (FR-017, SC-008).

#### Cenario 6: Frontmatter exotica nao quebra

1. Inspeciona `global/skills/<qualquer-com-allowed-tools>/SKILL.md`.
2. Roda `mkdocs build --strict`.
3. **Expected**: build conclui com sucesso; pagina renderiza body
   completo; `page.meta` no template tem campos custom acessiveis (mas
   nao quebra rendering se tema default nao os usa).

#### Cenario 7: Acessibilidade

1. Roda Lighthouse no Chrome DevTools em (a) `/` e (b)
   `/skills/briefing/`.
2. **Expected**: Accessibility >=90 em ambas (SC-003). Sem violacoes
   criticas reportadas.

#### Cenario 8: JS desabilitado

1. Desabilita JavaScript no browser.
2. Recarrega `/` e `/skills/briefing/`.
3. **Expected**: conteudo legivel; TOC funciona; links internos
   navegam (SC-010). Busca nao funciona (esperado — JS feature).

#### Cenario 9: Workflow CI verde em PR

1. Cria branch `test/site-build` com mudanca em `docs-site/manual/`.
2. Abre PR contra `main`.
3. **Expected**: workflow `Publish docs site` dispara, job `build`
   passa, job `deploy` NAO roda (so em push/dispatch). Status check
   `build` verde (FR-008).

#### Cenario 10: Auditoria de zero coleta remota

1. Apos build, roda no `site/`:
   ```sh
   grep -rn 'src="https://' site/ | grep -vE '(fonts.gstatic.com|fonts.googleapis.com)' | grep -E '(analytics|tracking|gtm|ga\.js)'
   ```
2. **Expected**: zero match (FR-019, SC-005).

---

## Complexity Tracking

Sem violacoes de constitution. Esta secao fica VAZIA — todas as
decisoes do plan se justificam pelos principios ou sao N/A.

---

## Constitution Re-check (pos-design)

Re-validacao apos Phase 1 (project structure + workflow YAML + hook
Python desenhados):

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD Recursivo | PASS | Plan gera apenas artefatos SDD (sem codigo); hook Python sera implementado em execute-task. |
| II. POSIX sh puro (scripts) | PASS | `bootstrap-docs.sh` desenhado como POSIX sh `#!/bin/sh`, sem bashisms. Workflow YAML usa apenas comandos POSIX. |
| III. Formato canonico de skill | N/A | Feature publica skills, nao cria. |
| IV. Zero coleta remota | PASS | Workflow nao adiciona analytics; CSS extra vazio no MVP; tema material default nao traz tracker. |
| V. Profundidade > adocao | PASS | MVP minimalista: tema default, sem branding, sem versionamento, sem htmlproofer. |
| D-I. Documentation-as-Source-of-Truth (NON-NEG.) | PASS | `gen_pages.py` cria virtuals com `--8<-- "..."`; `manual/instalacao.md` usa snippet do README; CHANGELOG via snippet. Nenhum paragrafo substantivo nasce em `docs-site/`. |
| D-II. Static-Site-First (NON-NEG.) | PASS | Build gera site/ HTML+CSS+JS; deploy via Pages environment; sem servico externo runtime; CDN para fontes ja habilita fallback local automaticamente no material >=9.5. |
| D-III. Automated-Publishing | PASS | Workflow: push -> build+deploy; PR -> build only; dispatch -> build+deploy. Tempo <=5min realista. |
| D-IV. Searchable-by-Default | PASS | Plugin `search` ativo no `mkdocs.yml`. |
| D-V. Accessibility-Floor | PASS | Tema material em palette dual (light/dark), `language: pt-BR`, atalhos teclado nativos. Verificacao manual via Lighthouse em execute-task. |
| D-VI. Versioning-Friendly | PASS | `use_directory_urls: true` + slugs derivados do path-fonte; `mkdocs.yml` sem nav hardcoded; `mike` plugavel sem rewrite. |

**Resultado pos-design**: GATE PASS.

---

## Artefatos Gerados (deste plan)

| Arquivo | Status |
|---------|--------|
| `docs/specs/github-pages-cstk-manual/plan.md` | Criado (este arquivo) |
| `docs/specs/github-pages-cstk-manual/research.md` | Inline no plan (Decisions 1-10 acima) — nao foi criado arquivo separado pois research e enxuto e referenciar 10 decisoes locais e mais legivel que externalizar |
| `docs/specs/github-pages-cstk-manual/data-model.md` | Inline no plan (secao 1.6 + 1.7) |
| `docs/specs/github-pages-cstk-manual/contracts/` | N/A — site nao expoe API; "contrato" e o workflow YAML, descrito inline em 1.5 |
| `docs/specs/github-pages-cstk-manual/quickstart.md` | Inline no plan (secao 1.9 — 10 cenarios) |

**Nota sobre artefatos inline**: o template padrao de `/plan` sugere
splittar em arquivos. Para esta feature, manter inline e melhor porque
(a) tudo cabe em um documento navegavel, (b) research e data-model
sao curtos e contextualmente acoplados ao plan, (c) cenarios de teste
beneficiam de proximidade com o data-model. Caso `/create-tasks`
precise referenciar secoes especificas, usar anchor links
(`plan.md#cenario-2-smoke-render`).

---

## Next Steps

1. `/checklist` — gerar quality gate dos artefatos SDD (validar
   completude da spec + plan).
2. `/create-tasks` — decompor o plano em backlog executavel.
3. `/analyze` — validar consistencia cross-artifact (spec / plan /
   tasks) apos `create-tasks`.
4. Execucao real (`/execute-task`) sera ondas futuras do agente-00c.
