# Project Briefing: GitHub Pages — Manual do cstk

**Data**: 2026-05-19
**Status**: Draft
**Versao**: 1.0
**Feature**: github-pages-cstk-manual
**Projeto-Pai**: cstk (worktree na branch `github-pages`)

---

## 1. Visao e Proposito

**O que e**: Site estatico publicado via GitHub Pages que serve como manual oficial do `cstk` (Claude Stack Toolkit) e catalogo navegavel de todas as skills, agents e commands distribuidos pelo toolkit `cstk`.

**Problema que resolve**: hoje a documentacao do cstk e dos artefatos do toolkit vive espalhada em arquivos `.md` dentro do repositorio (README.md raiz, CHANGELOG.md, global/skills/*/SKILL.md, global/agents/*.md, global/commands/*.md, language-related/<lang>/skills/*/SKILL.md, docs/specs/*/...). Para um desenvolvedor que quer (a) instalar e usar o `cstk` ou (b) descobrir quais skills/agents/commands estao disponiveis, e preciso navegar a arvore do repo no GitHub — UX ruim, sem indice, sem busca, sem agrupamento por categoria.

**Proposta de valor**: pagina web publica, navegavel, com busca, que serve como ponto de entrada unico para o toolkit. Manual passo-a-passo do `cstk` (instalacao, comandos, profiles, fluxo) + catalogo categorizado de skills/agents/commands com a documentacao de cada um renderizada a partir dos `.md` ja existentes no repositorio. Gerado automaticamente via CI a cada push na branch de publicacao.

## 2. Usuarios e Stakeholders

| Ator | Papel | Acoes Principais |
|------|-------|-----------------|
| Desenvolvedor avaliando o toolkit | Descobrir o que o `cstk` faz antes de instalar | Le pagina inicial, navega skills/agents catalogos, decide instalar |
| Usuario novo do `cstk` | Instalar e fazer primeiros usos | Segue manual de instalacao, copia one-liner, consulta lista de comandos |
| Usuario experiente do `cstk` | Consultar referencia de skill/agent/command | Busca skill especifica no catalogo, le pagina de detalhe da skill |
| Autor do toolkit (Joao Zanon) | Manter o site sincronizado com codigo | Edita .md, faz push; CI rebuilda o site automaticamente |

**Caracteristica-chave**: o site e **derivado** dos arquivos `.md` ja existentes no repositorio — nao deve introduzir uma segunda fonte de verdade. Toda documentacao de skill/agent/command permanece no proprio diretorio do artefato; o build do site coleta e organiza para apresentacao web.

**Stakeholders de decisao**: autor do toolkit (Joao Zanon / jot) decide direcao, stack e escopo do site. Sob licenca MIT.

## 3. Escopo

### MVP (Essencial)

1. **Landing page** com pitch curto do toolkit + link para instalacao + indice das 3 categorias (Skills, Agents, Commands).
2. **Manual do `cstk`** — pagina(s) cobrindo:
   - Instalacao (one-liner `install.sh`, profiles `sdd`/`complementary`/`all`, requisitos)
   - Comandos principais (`cstk install`, `cstk session`, `cstk 00c`, etc — derivar de `cli/` + `README.md`)
   - Fluxo SDD (briefing → constitution → ... → review-task) — vinculando as skills correspondentes
3. **Catalogo de skills globais** — pagina indice + uma pagina por skill em `global/skills/*/SKILL.md`. 21 skills atualmente.
4. **Catalogo de skills por linguagem** — `language-related/go/skills/` (8) e `language-related/dotnet/skills/` (8); paginas analogas as globais, agrupadas por linguagem.
5. **Catalogo de agents** — paginas geradas a partir de `global/agents/*.md` (atualmente 3: clarify-asker, clarify-answerer, orchestrator).
6. **Catalogo de commands** — paginas geradas a partir de `global/commands/*.md` (atualmente 3: `/agente-00c`, `/agente-00c-resume`, `/agente-00c-abort`).
7. **Busca client-side** — campo de busca que indexa titulos + conteudos de todas as paginas geradas.
8. **Deploy automatico via GitHub Actions** — workflow disparado por push em branch dedicada (provavelmente `main`, publicando em `github-pages` ou `gh-pages`); CI roda o build do gerador de site estatico e publica.

### Pos-MVP (Desejavel)

1. Versionamento da documentacao (selector de versao alinhado com tags SemVer do `cstk`).
2. Tema escuro/claro + design polido (depende da stack escolhida).
3. Diagramas embutidos do fluxo SDD (Mermaid).
4. CHANGELOG.md renderizado como pagina dedicada com anchors por versao.
5. Pagina "Cookbook" com receitas/playbooks de uso (a partir de `docs/playbooks/` se existir).

### Fora de Escopo

- **Backend / API / autenticacao** — site puramente estatico, sem interatividade alem de busca client-side.
- **Comentarios / feedback in-page** — sem disqus, sem gitalk; feedback continua via GitHub Issues.
- **Telemetria de uso do site** — coerente com a postura do projeto (briefing global: "rejeita telemetria mesmo sabendo que daria sinais valiosos").
- **Edicao do site fora do repo** — sem CMS, sem netlify-cms; conteudo SEMPRE em arquivos `.md` versionados.
- **i18n** — projeto e majoritariamente em portugues/ingles misto; nao havera build multi-idioma no MVP.

## 4. Prioridades e Trade-offs

**Ordem de prioridade**: Simplicidade de manutencao > UX/visual > Velocidade de implementacao > Features.

**Decisoes explicitas**:

- Reutilizar `.md` existentes — o site NUNCA deve ter conteudo duplicado de `global/skills/*/SKILL.md`; quando necessario, importar via include ou copia em build-time.
- Stack a ser decidida em clarify — candidatos: MkDocs Material, Astro Starlight, VitePress, Docusaurus, Jekyll. Criterios: baixo atrito de setup, build rapido em GitHub Actions, suporte nativo a busca, capacidade de auto-gerar paginas a partir de glob de `.md`.
- Build deve rodar em ambiente CI sem dependencias proprietarias (sem Vercel/Netlify) — somente GitHub Actions + artefato estatico publicavel em GitHub Pages.
- Aceitar tempo de build mais longo (ate ~5min) em troca de geracao automatizada do catalogo — preferivel a manter listas hardcoded.
- Layout das paginas de skill/agent/command deve incluir frontmatter destacado (categoria, descricao curta) + corpo do `.md` renderizado.

## 5. Restricoes

| Restricao | Valor | Notas |
|-----------|-------|-------|
| Prazo | Sem prazo externo rigido | Subprojeto do `cstk`, ritmo do autor |
| Equipe | Autor solo | Joao Zanon |
| Budget | Zero | GitHub Pages gratuito, GitHub Actions dentro do free tier |
| Tecnica | Site estatico publicavel em GitHub Pages | Sem backend, sem DB, sem servidor |
| Tecnica | Build em GitHub Actions | Sem pipelines externas |
| Tecnica | Conteudo derivado de .md ja existentes | Nao criar segunda fonte de verdade |
| Tecnica | Nao quebrar publicacao quando novas skills sao adicionadas | Build deve auto-descobrir glob de skills/agents/commands |

## 6. Stack Tecnica

| Camada | Tecnologia | Justificativa |
|--------|-----------|---------------|
| Gerador de site estatico | A decidir em clarify | Candidatos: MkDocs Material (Python, maduro em docs), Astro Starlight (rapido, moderno, otimo para docs+catalogo), VitePress (Vue, leve), Docusaurus (React, peso maior), Jekyll (Ruby, nativo do GH Pages mas menos moderno). Decisao em clarify (FR-EVI-001) deve estar ancorada em comparativo concreto. |
| Build/CI | GitHub Actions | Workflow ja existente para release (`.github/workflows/release.yml`); novo workflow para deploy do site. |
| Hosting | GitHub Pages | Custo zero, integracao nativa com o repo. |
| Linguagem auxiliar (scripts de geracao do catalogo) | POSIX sh | Coerente com a postura do projeto-pai ("POSIX sh puro para scripts deterministicos"); pode ser relaxado se a stack escolhida ja oferece API de plugin que dispensa scripts shell. |
| Busca | Client-side (Lunr.js / Pagefind / similar) | Stack-dependente; criterio: zero infra adicional. |
| Diagramas (pos-MVP) | Mermaid | Stack-dependente; preferencia por renderizacao em build-time. |

**Aspecto-chave para drift detection**: a stack escolhida em clarify CONGELA esta secao. Mudancas posteriores exigem retrospectiva.

## 7. Qualidade e Padroes

**Padroes adotados**:

- Build determinstico — mesma fonte produz mesmo output (relevante para reprodutibilidade do site).
- Validacao de links internos em CI — quebrou link, quebrou build.
- Frontmatter consistente — toda pagina de skill/agent/command tem `title`, `category`, `tags` minimos.
- Linting de Markdown — opcional no MVP; preferir lint passivo (warnings) a bloqueante.
- Acessibilidade — contraste minimo WCAG AA; navegacao por teclado funcional. Verificacao manual aceitavel no MVP (sem audit automatico).

**Compliance**: nenhum especifico — site publico, sem dados pessoais, sem coleta.

## 8. Visao de Futuro

**6 meses**:

- Site no ar com catalogo completo + manual do `cstk`.
- Workflow de release do `cstk` aciona rebuild do site (sincronia versao-toolkit <-> versao-site).
- Tema visual polido + dark mode.

**12 meses**:

- Versionamento da doc alinhado com tags SemVer.
- Secao "Cookbook" com playbooks reais de uso (extraidos de `docs/playbooks/` ou similar).
- Diagramas Mermaid do fluxo SDD embutidos em paginas relevantes.
- Possivel internacionalizacao (PT-BR / EN) — pendente de demanda.

## Itens a Definir

1. **Stack do gerador de site estatico** — escolha entre MkDocs Material / Astro Starlight / VitePress / Docusaurus / Jekyll. Decisao deve ser feita em `/clarify` com `score=3 + --evidencia` (POC minimo ou comparativo concreto de critterios: tempo de build, suporte a glob de .md, busca nativa, tema, manutencao a longo prazo).
2. **Branch de publicacao do GitHub Pages** — `gh-pages` (convencao classica) vs `github-pages` (worktree atual) vs publicar a partir de `main` via Actions com `actions/deploy-pages@v4`. Provavel: `main` -> Actions -> GitHub Pages environment.
3. **Estrutura de URLs** — `/skills/<nome>/`, `/agents/<nome>/`, `/commands/<nome>/` (proposta) — confirmar em clarify ou plan.
4. **Indexador de busca** — depende da stack; documentar decisao quando stack escolhida.
5. **Diretorio fonte do site no repo** — `site/`, `docs-site/`, `web/`? Convencao a definir no plan.
6. **Comportamento quando .md tem syntax exotica (HTML inline, frontmatter Claude-specifico)** — definir sanitizacao/transformacao no plan.

---

## Setup / Bootstrap

**Pre-flight obrigatorio**: nao aplicavel ate decisao de stack. O `scripts/bootstrap-deps.sh` sera materializado em fase posterior (apos `/clarify` definir a stack e `/plan` materializar `§Project Structure`). Stacks candidatas tem perfis de bootstrap diferentes:

- MkDocs Material: `pip install mkdocs-material` (single-package, sem multi-workspace — bootstrap trivial).
- Astro Starlight / VitePress / Docusaurus: `npm install` na pasta do site (single-package; bootstrap trivial).
- Jekyll: `bundle install` (Ruby; trivial).

Nenhuma das stacks candidatas e multi-workspace, entao `bootstrap-deps.sh` provavelmente NAO sera necessario para esta feature.
