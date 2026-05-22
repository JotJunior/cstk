# Feature Specification: GitHub Pages — Manual do cstk

**Feature**: `github-pages-cstk-manual`
**Created**: 2026-05-19
**Status**: Clarified
**Briefing-source**: `docs/specs/github-pages-cstk-manual/briefing.md`
**Constitution (delta)**: `docs/specs/github-pages-cstk-manual/constitution.md` v1.0.0
**Constitution (global)**: `docs/constitution.md` v1.1.0

---

## Clarifications

### Session 2026-05-19

- Q: Stack do gerador de site estatico (FR-021) — MkDocs Material vs Astro Starlight vs VitePress vs Docusaurus vs Jekyll? → A: **MkDocs Material** (score=3, evidencia empirica: constitution-delta v1.0.0 ja referencia `mkdocs.yml`, `mkdocs build`, `mkdocs-material`, plugin `mike`, e `lunr.js` em 10+ pontos — stack assumida como default; TODO no Sync Impact Report congelado apenas no pin de versao, nao na stack).
- Q: Branch e mecanismo de publicacao (FR-022) — `gh-pages` vs `main /docs` vs `actions/deploy-pages@v4`? → A: **`actions/deploy-pages@v4`** (GitHub Pages environment, sem branch dedicada).
- Q: Estrutura de URLs (FR-016) — formato dos slugs por categoria? → A: **`/skills/<nome>/`, `/agents/<nome>/`, `/commands/<nome>/`, com prefixo de linguagem para skills nao-globais** (`/skills/go/<nome>/`, `/skills/dotnet/<nome>/`).
- Q: Indexador de busca (FR-006) — built-in Lunr.js vs Pagefind vs Algolia DocSearch vs none-mvp? → A: **Lunr.js built-in do mkdocs-material** (zero infra adicional, alinhado com D-IV e Principio IV global).
- Q: Diretorio-fonte do site no repo (FR-023) — `docs/` raiz vs `site/` vs `docs-site/` vs `web/`? → A: **`docs-site/`** (evita colisao com `docs/` existente que ja contem specs SDD).
- Q: Sanitizacao de `.md` com syntax exotica (FR-024) — frontmatter Claude-specifico, HTML inline, code blocks raros? → A: **Passar puro + warning no build** (preserva conteudo canonico; frontmatter Claude-specifico parseado como YAML pelo mkdocs-material; HTML inline confinado pelo content security do tema; linguagens raras de code blocks caem para fallback sem highlight).

---

## Overview

Site estatico publicado via GitHub Pages que serve como (a) manual oficial
do `cstk` (Claude Stack Toolkit) e (b) catalogo navegavel com busca de
todas as skills, agents e commands distribuidos pelo toolkit
`claude-ai-tips`. Conteudo derivado dos arquivos `.md` ja existentes no
repositorio — sem segunda fonte de verdade. Publicacao automatica via
GitHub Actions a cada push na branch principal.

## User Scenarios & Testing

### User Story 1 - Descobrir e avaliar o toolkit (Priority: P1)

Um desenvolvedor que ouviu falar do `cstk` em uma conversa ou via search
engine acessa o site do projeto pela primeira vez. Em menos de 1 minuto
ele entende o que o toolkit faz, ve a lista de skills/agents/commands
disponiveis, e decide se quer instalar. Se decidir, encontra o one-liner
de instalacao na pagina inicial sem precisar abrir o repositorio.

**Why this priority**: este e o "primeiro contato" — sem ele o site nao
resolve o problema central declarado no briefing ("descoberta ruim"). Se
o landing nao convencer ou nao tiver indice das categorias, todas as
outras paginas ficam inalcancaveis.

**Independent Test**: abrir a home publicada em modo anonimo (sem
cache, sem sessao prior do GitHub) e verificar: (a) titulo + pitch
visiveis above-the-fold; (b) link direto para instalacao com one-liner
copiavel; (c) 3 links de categoria (Skills / Agents / Commands)
clicaveis levando a paginas-indice nao-vazias.

**Acceptance Scenarios**:

1. **Given** o site esta publicado e o usuario nao conhece o cstk,
   **When** acessa a URL raiz do site,
   **Then** ve pitch curto (1-2 paragrafos), comando de instalacao
   copiavel, e 3 links de categoria com contagem de itens cada
   (ex: "Skills (37)", "Agents (3)", "Commands (3)").
2. **Given** o usuario clica em "Skills",
   **When** a pagina carrega,
   **Then** ve listagem agrupada por categoria (Global / Go / Dotnet)
   com nome + descricao curta de cada skill, e cada item leva a uma
   pagina de detalhe.
3. **Given** o usuario quer instalar imediatamente,
   **When** copia o one-liner da home,
   **Then** o comando funciona em ambiente shell padrao (bash/zsh) sem
   modificacao.

---

### User Story 2 - Consultar referencia de uma skill/agent/command (Priority: P1)

Um usuario que ja instalou o `cstk` precisa lembrar como uma skill
especifica funciona — quais triggers, quais argumentos, qual fluxo
interno. Ele acessa o site, busca pelo nome da skill, abre a pagina e
le a documentacao renderizada do `SKILL.md` original.

**Why this priority**: este e o uso recorrente — usuarios experientes
voltam ao site dezenas de vezes para consultar referencia. Sem busca
funcional + paginas-detalhe completas, o site nao supera a UX atual de
"abrir o GitHub e procurar a pasta".

**Independent Test**: com o site publicado, executar busca por uma
skill conhecida (ex: "briefing"), confirmar que aparece nos resultados
em <=200ms, clicar e validar que a pagina-detalhe contem o conteudo
canonico do `SKILL.md` correspondente.

**Acceptance Scenarios**:

1. **Given** o site esta publicado e indexado,
   **When** o usuario digita "briefing" no campo de busca,
   **Then** ve resultado com link para `/skills/briefing/` (ou URL
   equivalente conforme estrutura clarificada) em menos de 200ms.
2. **Given** o usuario abre a pagina-detalhe de uma skill,
   **When** a pagina renderiza,
   **Then** ve cabecalho com nome + categoria + descricao curta + corpo
   do `SKILL.md` original renderizado em HTML legivel (headings,
   listas, code blocks, tabelas preservados).
3. **Given** uma skill foi removida do repositorio na ultima
   publicacao,
   **When** o usuario tenta acessar a URL antiga,
   **Then** recebe pagina 404 do GitHub Pages ou redirect explicito
   (sem 500, sem broken link).

---

### User Story 3 - Seguir o manual passo-a-passo do cstk (Priority: P2)

Um usuario novo decidiu instalar o `cstk` e quer um tutorial linear:
instalar → entender profiles → rodar primeiro comando → entender fluxo
SDD. Ele acessa a secao "Manual" e segue paginas em ordem, com
navegacao "proxima/anterior" entre paginas relacionadas.

**Why this priority**: P2 porque o landing + catalogo (P1) ja cobrem o
caminho minimo "instalar + consultar"; o manual e o "valor agregado"
que reduz friccao para novatos mas nao e bloqueador para usuarios
tecnicos que sabem ler `README.md`.

**Independent Test**: acessar a pagina "Manual / Instalacao", verificar
que tem botao "proximo" para "Manual / Comandos principais", validar
ordem coerente das paginas e que todas tem conteudo nao-vazio.

**Acceptance Scenarios**:

1. **Given** o usuario abriu o manual,
   **When** percorre a sequencia de paginas via navegacao linear,
   **Then** encontra (em qualquer ordem coerente): instalacao,
   profiles, comandos principais (`cstk install`, `cstk session`,
   `cstk 00c`), e visao do fluxo SDD com links para as skills
   correspondentes.
2. **Given** o `README.md` do toolkit foi atualizado,
   **When** o proximo ciclo de publicacao executa,
   **Then** o manual reflete a mudanca (verificavel comparando texto
   publicado com texto-fonte no commit referente).

---

### User Story 4 - Manter o site sincronizado com o codigo (Priority: P1)

O autor do toolkit edita um `SKILL.md`, adiciona uma nova skill, ou
atualiza o `README.md`. Faz `git push` para a branch principal. Em
menos de 10 minutos o site publicado reflete a mudanca, sem nenhum
passo manual do autor.

**Why this priority**: e a pre-condicao operacional de todos os outros
stories. Sem publicacao automatica, o site fica obsoleto e violamos D-I
(Documentation-as-Source-of-Truth) — duas fontes-de-verdade
inevitaveis.

**Independent Test**: alterar uma linha em `global/skills/briefing/SKILL.md`
com mudanca visivel (ex: texto de descricao), commitar e fazer push;
medir tempo entre push e publicacao da nova versao no site.

**Acceptance Scenarios**:

1. **Given** o workflow GitHub Actions esta configurado,
   **When** o autor faz push de uma mudanca em
   `global/skills/<nome>/SKILL.md`,
   **Then** o workflow dispara automaticamente, executa build, e
   publica a nova versao em menos de 10 minutos (push → site
   atualizado).
2. **Given** o autor abriu um Pull Request com mudancas em `docs/` ou
   `mkdocs.yml` (ou equivalente da stack escolhida),
   **When** o workflow de PR roda,
   **Then** executa build-only (sem publicar) e reporta status check
   verde ou falha; falha bloqueia merge.
3. **Given** o autor adicionou uma nova skill em
   `global/skills/<nova-skill>/SKILL.md`,
   **When** publica e o site rebuilda,
   **Then** a nova skill aparece automaticamente no indice de Skills
   sem edicao manual de listas hardcoded.

---

### User Story 5 - Buscar termo em todo o site (Priority: P2)

Um usuario experiente quer encontrar todas as paginas que mencionam
uma palavra-chave (ex: "constitution", "drift", "subagent") para
entender como o conceito aparece transversalmente. Ele usa a busca,
ve lista de resultados rankeada com snippets, e navega.

**Why this priority**: P2 porque busca por nome de skill (P1, User
Story 2) ja cobre o caso mais comum; busca full-text e refinamento
para usuarios avancados que pesquisam conceitos cross-page.

**Independent Test**: buscar por termo conhecido (ex: "drift") e
validar que (a) aparece em >=2 resultados, (b) cada resultado mostra
snippet com termo destacado, (c) ranking favorece titulo > heading >
corpo.

**Acceptance Scenarios**:

1. **Given** o site indexou todas as paginas no build,
   **When** o usuario busca por palavra que aparece em multiplas
   paginas,
   **Then** ve lista rankeada com snippet contendo o termo destacado.
2. **Given** o usuario pressiona o atalho de teclado de busca
   (`/` ou `s`),
   **When** o foco vai para o campo de busca,
   **Then** consegue digitar e buscar sem usar o mouse.

---

### User Story 6 - Ler o site com acessibilidade assistiva (Priority: P2)

Um usuario com leitor de tela ou que navega exclusivamente por teclado
acessa o site. Consegue percorrer o conteudo, ouvir headings
hierarquicos corretos, abrir links e ler paginas sem barreiras visuais
ou de interacao.

**Why this priority**: P2 porque e requisito da constituicao
(D-V WCAG AA) e o briefing inclui "casual-reader" entre os atores,
mas nao bloqueia o lancamento se um subset de paginas tiver score
levemente abaixo do limite (warning, nao fail). A11y e contrato com
todos os usuarios, nao opcional.

**Independent Test**: rodar Lighthouse Accessibility em (a) home e
(b) uma pagina-detalhe de skill; ambas devem score >=90.

**Acceptance Scenarios**:

1. **Given** o site esta publicado,
   **When** Lighthouse Accessibility roda na home,
   **Then** retorna score >=90 e sem violacoes criticas.
2. **Given** usuario navega exclusivamente por teclado,
   **When** percorre a home com TAB,
   **Then** chega a todos os links e controles em ordem visual, com
   foco visivel a cada passo.

---

### Edge Cases

- **Skill nova adicionada entre publicacoes**: o site automaticamente
  inclui no proximo build; ate la, URL nova retorna 404 (esperado).
- **`SKILL.md` contem HTML inline ou frontmatter Claude-specifico**:
  estrategia "passar puro + warning" (FR-024) — frontmatter parseado
  via plugin `meta` do mkdocs-material; HTML inline preservado;
  resultado nao quebra build nem renderiza tags executaveis (CSP do
  tema bloqueia scripts inline arbitrarios).
- **Skill renomeada**: URL antiga torna-se 404; sem redirect automatico
  no MVP — mudanca de nome de skill e evento raro e pode ser tratada
  caso a caso.
- **Build falha em CI**: ultima publicacao continua viva (GitHub Pages
  serve o que esta na branch de deploy); workflow loga falha; PR/commit
  recebe status check vermelho.
- **Repositorio offline / GitHub down**: site continua acessivel pois
  GitHub Pages serve estaticos de CDN; busca client-side continua
  funcionando (indice e asset estatico).
- **`SKILL.md` ausente em algum diretorio listado**: build emite warning
  + segue; a skill nao aparece no indice. Falha hard apenas se afetar
  links internos.
- **Tag de versao SemVer adicionada**: no MVP, nao gera versao da doc;
  pos-MVP planeja-se ativacao do plugin de versionamento.
- **Imagem em `.md` referenciada com path relativo invalido**: build
  emite warning; falha hard apenas se a validacao de links internos
  esta configurada como bloqueante (decisao de plan).

---

## Requirements

### Functional Requirements

- **FR-001**: Sistema MUST publicar site estatico acessivel via URL
  publica do GitHub Pages do repositorio `claude-ai-tips`.
- **FR-002**: Sistema MUST gerar landing page com pitch do toolkit,
  one-liner de instalacao copiavel, e indice navegavel para 3
  categorias (Skills, Agents, Commands) com contagem atualizada.
- **FR-003**: Sistema MUST gerar uma pagina-indice por categoria
  listando todos os itens descobertos via glob dos diretorios fonte:
  - Skills globais: `global/skills/*/SKILL.md`
  - Skills por linguagem: `language-related/<lang>/skills/*/SKILL.md`
    (atualmente `go` com 8 skills e `dotnet` com 8 skills)
  - Agents: `global/agents/*.md`
  - Commands: `global/commands/*.md`
- **FR-004**: Sistema MUST gerar uma pagina-detalhe por skill/agent/
  command, renderizando o conteudo canonico do `.md` fonte sem
  duplicar texto (alinhado com Principio D-I).
- **FR-005**: Sistema MUST gerar paginas do "Manual do cstk" cobrindo
  pelo menos: (a) instalacao via one-liner `install.sh` + profiles
  `sdd`/`complementary`/`all`; (b) comandos principais (`cstk install`,
  `cstk session`, `cstk 00c`); (c) visao do fluxo SDD com links para
  as skills correspondentes.
- **FR-006**: Sistema MUST oferecer busca client-side via plugin
  `search` built-in do mkdocs-material (lunr.js sob o capo) que
  indexa titulo, headings e corpo de TODAS as paginas geradas, com
  indice servido como asset estatico (sem chamada de rede em
  runtime, sem Algolia/DocSearch). Zero infra adicional, alinhado
  com D-IV (Searchable-by-Default) e Principio IV global (zero
  coleta remota).
- **FR-007**: Sistema MUST disparar publicacao automatica via GitHub
  Actions a cada push na branch principal que toca arquivos em `docs/`,
  `README.md`, `global/skills/**/SKILL.md`, `global/agents/*.md`,
  `global/commands/*.md`, `language-related/**/SKILL.md`, ou na
  configuracao do gerador.
- **FR-008**: Sistema MUST executar workflow de validacao build-only
  em Pull Requests (sem publicar), e reportar status check obrigatorio
  que bloqueia merge em caso de falha.
- **FR-009**: Sistema MUST suportar workflow_dispatch manual para
  re-publicacao sem mudanca de conteudo (rollback / re-build).
- **FR-010**: Sistema MUST gerar conteudo APENAS a partir de arquivos
  `.md` ja versionados no repositorio. Nenhum paragrafo substantivo
  deve existir apenas em arquivos exclusivos do diretorio-fonte do
  site (alinhado com D-I).
- **FR-011**: Sistema MUST validar links internos no build; link
  quebrado interno emite warning ou erro conforme decisao de plan
  (preferencia: erro bloqueante para o MVP).
- **FR-012**: Sistema MUST atender Lighthouse Accessibility >=90 em
  pelo menos (a) landing page e (b) uma pagina-detalhe de skill
  representativa, em ambos os temas (claro e escuro) se houver
  multiplos temas.
- **FR-013**: Sistema MUST gerar HTML com hierarquia de headings sem
  pulos (h1 → h2 → h3, sem saltar h4), navegavel por teclado com foco
  visivel, e declarar idioma da pagina via `<html lang="...">`.
- **FR-014**: Sistema MUST funcionar (leitura, navegacao por TOC,
  links internos) com JavaScript desabilitado; recursos JS (busca,
  copy-button, dark-mode toggle) sao aprimoramentos progressivos.
- **FR-015**: Sistema MUST nao realizar nenhuma chamada de rede em
  runtime do navegador para conteudo, navegacao ou analytics
  (alinhado com Principio IV global + D-II). CDN para fontes/icones
  permitida apenas com fallback local; tracking PROIBIDO.
- **FR-016**: Sistema MUST usar slugs estaveis e descritivos para
  URLs de paginas no formato:
  - `/skills/<nome>/` para skills globais (`global/skills/<nome>/SKILL.md`)
  - `/skills/<lang>/<nome>/` para skills por linguagem
    (`language-related/<lang>/skills/<nome>/SKILL.md`)
  - `/agents/<nome>/` para agents (`global/agents/<nome>.md`)
  - `/commands/<nome>/` para commands (`global/commands/<nome>.md`)
  - `/manual/<topico>/` para paginas do manual
  Renomeacao de pagina publicada exige aviso explicito em changelog
  do site.
- **FR-017**: Sistema MUST gerar URL de pagina-detalhe a partir do
  path-fonte do `.md`, sem mapeamento hardcoded — adicionar skill nova
  nao requer edicao manual de listas alem do proprio `SKILL.md`.
- **FR-018**: Sistema MUST executar build local em <=60 segundos em
  hardware do mantenedor, e workflow total CI (checkout → build →
  publish) em <=5 minutos.
- **FR-019**: Sistema MUST permitir auditoria visual de "zero servico
  externo em runtime" — inspecao manual do HTML publicado nao deve
  encontrar tags `<script src="https://...">` apontando para
  analytics, A/B testing ou CDN-tracker.
- **FR-020**: Sistema MUST permitir adicao futura do plugin de
  versionamento (ex: `mike` para mkdocs) sem reescrever a estrutura de
  navegacao ou paths — decisao de NAO ativar versionamento no MVP deve
  ser documentada em ADR ou no plan (alinhado com D-VI).
- **FR-021**: Stack do gerador de site estatico: **MkDocs Material**
  (Python, `pip install mkdocs-material`). Decisao com score=3 +
  evidencia empirica: constitution-delta v1.0.0 ja referencia
  `mkdocs.yml`, `mkdocs build`, `mkdocs-material`, plugin `mike` e
  `lunr.js` em 10+ pontos — stack assumida como default na ratificacao
  do delta; TODO no Sync Impact Report congelado apenas no pin de
  versao (`TODO(MKDOCS_VERSION_PIN)`), nao na stack. Atende todos os
  criterios do briefing: build determinista, glob nativo via
  `awesome-pages`/`gen-files`, busca built-in (lunr.js), tema AA por
  default, manutencao ativa (squidfunk/mkdocs-material — 19k+ stars,
  releases mensais).
- **FR-022**: Mecanismo de publicacao: **`actions/deploy-pages@v4`**
  (GitHub Pages environment, sem branch dedicada). Evita poluir
  historico do repo com commits de build (vs `gh-pages`), nao mistura
  artefatos de build com codigo-fonte (vs `main /docs`), e e o caminho
  recomendado pelo GitHub desde 2023. Workflow usa
  `actions/upload-pages-artifact@v3` + `actions/deploy-pages@v4` com
  permissions `pages: write` + `id-token: write`.
- **FR-023**: Diretorio-fonte do site dentro do repositorio:
  **`docs-site/`**. Escolha evita colisao com `docs/` existente
  (que ja contem `specs/`, `constitution.md`, e artefatos SDD) e
  e auto-explicativo (vs `web/` ou `site/` genericos). MkDocs
  config (`mkdocs.yml`) reside na raiz do repo; `docs_dir:` aponta
  para `docs-site/`.
- **FR-024**: Sistema MUST tratar `.md` com syntax exotica
  (HTML inline, frontmatter Claude-specifico, comentarios HTML, code
  blocks com fences nao-padrao) com estrategia **passar puro +
  warning** (opcao c):
  - Frontmatter YAML do Claude (`name:`, `description:`,
    `allowed-tools:`) e parseado pelo mkdocs-material via plugin
    `meta` e exposto como variaveis de pagina (titulo, descricao
    extraidos automaticamente).
  - HTML inline preservado (mkdocs renderiza como HTML literal);
    Content Security Policy do tema default impede execucao de
    scripts inline arbitrarios.
  - Linguagens de code block nao reconhecidas pelo Pygments caem
    para fallback sem syntax highlight, sem quebrar o build.
  - Comentarios HTML (`<!-- ... -->`) sao preservados no source mas
    nao renderizados na pagina (comportamento padrao do markdown).
  - Build emite warning (nao bloqueante) quando deteccao opcional
    encontra padroes suspeitos; falha hard apenas para link interno
    quebrado (FR-011).

### Decisoes de Infraestrutura

Feature publica conteudo estatico sem schedulers, sessoes persistentes,
tokens externos ou rotacao de chaves no runtime do navegador. A
infraestrutura runtime relevante e GitHub Pages (serve assets) +
GitHub Actions (build + publish).

- **FR-025-INFRA-SCHED**: autoSchedule = `'event-driven'` (default).
  Publicacao acionada por evento `push` ou `workflow_dispatch`. Nao ha
  cron job de re-build periodico — re-build manual suporta casos de
  rollback. `workflow_dispatch` cobre o caso "republicar sem mudanca".
- **FR-026-INFRA-IDEMP**: build e idempotente — re-executar com mesmo
  commit produz mesmo output binario-equivalente (modulo timestamps
  embutidos pela stack). Re-publicar mesma versao nao altera URL nem
  invalida cache do navegador alem do TTL padrao.
- **FR-027-INFRA-BACKUP**: N/A — site e projecao do repositorio; o
  proprio Git e o backup. Restore = re-rodar build no commit alvo.
- **FR-028-INFRA-KEY**: N/A — site nao criptografa dados; nao ha
  segredos no artefato publicado (CI tem token efemero do GitHub para
  publicar; rotacao gerida pelo GitHub Actions).
- **FR-029-INFRA-REFRESH**: N/A — site nao consome IdP ou token
  externo em runtime.
- **FR-030-INFRA-LOCK**: N/A — publicacao e single-writer (GitHub
  Actions); GitHub Pages serializa updates da branch alvo.

### Key Entities

- **Page**: representa uma URL publicada no site. Atributos
  conceituais: slug (URL path), titulo, categoria (manual /
  skill-global / skill-go / skill-dotnet / agent / command / outras),
  descricao curta (de frontmatter ou primeira frase), corpo renderizado.
  Origem: arquivo `.md` no repositorio fonte ou pagina-ponte do
  diretorio do site.
- **Catalog Section**: agrupamento de paginas relacionadas (ex:
  "Skills Globais", "Manual"). Atributos: titulo, descricao, criterio
  de inclusao (glob), ordem (alfabetica / curada). Origem: configuracao
  do gerador de site.
- **Search Index**: indice client-side com referencias serializadas
  para todas as paginas. Atributos: lista de documentos com (id, slug,
  titulo, headings, corpo, tags). Origem: gerado em build-time pelo
  plugin de busca da stack.
- **Workflow**: arquivo de definicao do pipeline GitHub Actions
  (`.github/workflows/publish-site.yml` ou equivalente). Atributos:
  triggers, steps de build, configuracao de publicacao. Origem:
  versionado no proprio repositorio.

---

## Success Criteria

### Measurable Outcomes

- **SC-001**: Tempo entre `git push` na branch principal e site
  publicado com a mudanca <=10 minutos em condicoes normais (medido
  comparando timestamp do commit com Last-Modified do HTML publicado).
- **SC-002**: Build local da stack escolhida executa em <=60 segundos
  em hardware do mantenedor; workflow CI completo (checkout → build →
  publish) executa em <=5 minutos.
- **SC-003**: Lighthouse Accessibility score >=90 em (a) landing page
  e (b) pelo menos uma pagina-detalhe de skill representativa, em
  todos os temas disponiveis.
- **SC-004**: Latencia de query de busca client-side <=200ms em
  hardware desktop modesto (~5 anos), do toque na tecla Enter ate
  primeiro resultado visivel.
- **SC-005**: Zero chamadas de rede em runtime para conteudo,
  navegacao ou analytics — auditavel via inspecao do HTML publicado
  (grep nao encontra `<script src=https://...>` para analytics/CDN-
  tracker; CDN para fontes/icones permitida apenas com fallback local).
- **SC-006**: MVP cobre auto-geracao de paginas-detalhe para o
  inventario atual: >=21 skills globais + >=8 skills Go + >=8 skills
  Dotnet + >=3 agents + >=3 commands (>=43 paginas auto-geradas), com
  ZERO listagem hardcoded no diretorio-fonte do site.
- **SC-007**: 95% dos usuarios novos conseguem completar o caminho
  "ler pitch → copiar one-liner → instalar localmente" sem precisar
  abrir outra aba do navegador para resolver duvidas (verificavel via
  teste de usabilidade leve com 5 usuarios).
- **SC-008**: Adicionar uma nova skill ao repositorio (criar diretorio
  + `SKILL.md` + push) e SUFICIENTE para que ela apareca no proximo
  site publicado — zero edicao manual de listas ou navegacao.
- **SC-009**: PR que introduz regressao bloqueante (build falha, link
  interno quebrado se configurado como erro, ou queda de Lighthouse
  abaixo do threshold) recebe status check vermelho e nao consegue
  merge sem override explicito.
- **SC-010**: Funcao essencial do site (ler texto, navegar TOC, abrir
  links internos) funciona com JavaScript desabilitado em pelo menos
  um navegador moderno (verificavel via teste manual com JS off).
- **SC-011**: Site sobrevive a falhas de build por pelo menos 30 dias
  — ultima publicacao bem-sucedida continua acessivel mesmo se builds
  subsequentes falharem (garantia operacional do GitHub Pages, nao
  responsabilidade do projeto, mas verificavel se ocorrer).

---

## Constitution Check

Esta secao audita a spec contra os principios obrigatorios. Violacoes
sao bloqueantes em `/plan` e `/analyze`.

**Global v1.1.0** (`docs/constitution.md`):

| Principio | Aderencia da spec |
|-----------|-------------------|
| I. SDD Recursivo | Spec parte de briefing + constitution-delta; clarify resolvera 6 pendencias antes de plan; alinhado. |
| II. POSIX sh puro (scripts) | FR-021 a decidir; preferencia documentada no briefing por POSIX sh quando scripts auxiliares forem necessarios. Sem violacao no escopo da spec. |
| III. Formato canonico de skill | N/A (esta feature publica skills, nao cria skills novas). |
| IV. Zero coleta remota | FR-015, FR-019, SC-005 reforcam ausencia de analytics/tracking. |
| V. Profundidade > adocao | Spec prioriza simplicidade de manutencao (briefing) e build determinista (FR-026) acima de features visuais — alinhado. |

**Delta 1.0.0** (`docs/specs/github-pages-cstk-manual/constitution.md`):

| Principio | Aderencia |
|-----------|-----------|
| D-I. Documentation-as-Source-of-Truth (NON-NEG.) | FR-004, FR-010, FR-017, SC-008 garantem conteudo unico no repo-fonte. |
| D-II. Static-Site-First (NON-NEG.) | FR-014, FR-015, FR-019, SC-005, SC-010 — site puramente estatico, sem servidor de aplicacao. |
| D-III. Automated-Publishing | FR-007, FR-008, FR-009, SC-001 — publicacao automatica + PR validation + workflow_dispatch. |
| D-IV. Searchable-by-Default | FR-006, SC-004 — busca client-side <=200ms, indice estatico. |
| D-V. Accessibility-Floor (WCAG AA) | FR-012, FR-013, SC-003 — Lighthouse >=90 + headings + navegacao por teclado. |
| D-VI. Versioning-Friendly | FR-016, FR-017, FR-020 — slugs estaveis + URLs derivaveis + hooks para `mike`. |

**Conclusao**: spec esta aderente. Tensoes potenciais identificadas:

- **Stack decision (FR-021)**: candidatos divergem em Principio II
  (POSIX sh) — MkDocs (Python) e Astro/VitePress/Docusaurus (Node)
  exigem runtime nao-POSIX. Clarify deve avaliar se o briefing relaxa
  POSIX para scripts auxiliares do gerador.
- **CDN para fontes/icones (FR-015)**: D-II permite "com fallback
  local"; plan deve confirmar que a stack escolhida pode bundlar
  assets ou que fontes vem de CDN com fallback.

---

## Assumptions

Defaults assumidos onde a spec nao tem decisao explicita (e nao foi
marcado como `[NEEDS CLARIFICATION]`):

- **Linguagem-fonte das paginas**: portugues-brasileiro misturado com
  ingles, conforme conteudo dos `.md` originais. Site declara
  `lang="pt-BR"` por padrao; paginas em ingles puro podem sobrescrever
  no frontmatter se a stack suportar.
- **Tema visual**: tema padrao da stack escolhida no MVP, com dark
  mode habilitado se a stack oferece por default. Customizacao visual
  e pos-MVP.
- **Mensagens de erro do build**: em ingles (output do gerador), nao
  traduzidas no MVP.
- **Cache HTTP**: configuracao padrao do GitHub Pages (sem custom
  headers); aceitavel para MVP.
- **Robots/SEO**: site publico, indexavel por search engines; sem
  `noindex` e sem sitemap customizado no MVP (sitemap default da
  stack, se houver, e suficiente).
- **Imagens**: paginas-detalhe podem referenciar imagens de paths
  relativos do repositorio fonte; validacao de existencia da imagem
  ocorre no build.
- **Tamanho maximo de pagina**: nao ha limite imposto pelo projeto;
  GitHub Pages tem limites operacionais (1GB do site total) que
  excedem em ordens de magnitude qualquer cenario realista do MVP.
- **CHANGELOG.md**: incluido no site como pagina dedicada se referenciado
  pela navegacao; renderizacao polida e pos-MVP.

---

## Out of Scope

Itens explicitamente fora do MVP (alinhado com briefing §3 "Fora de Escopo"):

- Backend, API, autenticacao, conta de usuario.
- Comentarios ou feedback in-page (disqus, gitalk, etc).
- Telemetria de uso do site (reforco do Principio IV global + D-II).
- CMS ou edicao do site fora do repositorio.
- Internacionalizacao multi-build (PT-BR / EN com toggle).
- Versionamento da documentacao multi-versao (latest, stable, vX.Y) no
  MVP — apenas hooks de compatibilidade (FR-020).
- Tema visual polido / branding customizado alem do default da stack.
- Diagramas Mermaid embutidos (pos-MVP).
- Pagina "Cookbook" com playbooks (pos-MVP).
- Sincronia com tags SemVer (pos-MVP).
- Edicao colaborativa fora do GitHub (sem netlify-cms).
- Dependencia de qualquer SaaS terceiro alem do GitHub (sem
  Vercel/Netlify/Cloudflare Pages como dependencia obrigatoria).

---

## Resolved Ambiguities

Resolvidas em `/clarify` na sessao 2026-05-19 (ondas 004 do agente-00c):

### 1. stack-gerador-site (FR-021)

- **Decisao**: MkDocs Material
- **Opcoes consideradas**: MkDocs Material, Astro Starlight, VitePress,
  Docusaurus, Jekyll
- **Score**: 3 (decide_sem_clarificar)
- **Evidencia**: constitution-delta v1.0.0 (`constitution.md`) ja
  referencia `mkdocs.yml`, `mkdocs build`, `mkdocs-material`, plugin
  `mike` e `lunr.js` em 10+ pontos (linhas 37, 63-64, 88, 109, 119,
  136, 145-146, 204-205, 227, 234, 236). O TODO no Sync Impact Report
  esta congelado apenas no pin de versao
  (`TODO(MKDOCS_VERSION_PIN)`), nao na escolha da stack — a stack ja
  estava implicitamente assumida na ratificacao do delta.
- **Justificativa**: MkDocs Material atende todos os criterios do
  briefing §6 (build determinista <60s, glob nativo, busca built-in,
  WCAG AA por default, manutencao ativa — 19k+ stars no GitHub,
  releases mensais) e e a stack ja referenciada na constitution-delta.

### 2. branch-publicacao (FR-022)

- **Decisao**: `actions/deploy-pages@v4` (GitHub Pages environment)
- **Opcoes consideradas**: `gh-pages` dedicada / `main /docs` / Pages
  environment via `deploy-pages@v4`
- **Score**: 2 (decide_sem_clarificar — suportado por briefing)
- **Justificativa**: caminho recomendado pelo GitHub desde 2023; evita
  poluir historico com commits de build (vs `gh-pages`); nao mistura
  artefatos com codigo-fonte (vs `main /docs`); briefing §"Itens a
  Definir" #2 explicita preferencia por "main -> Actions -> GitHub
  Pages environment".

### 3. estrutura-urls (FR-016)

- **Decisao**: `/skills/<nome>/`, `/skills/<lang>/<nome>/`,
  `/agents/<nome>/`, `/commands/<nome>/`, `/manual/<topico>/`
- **Opcoes consideradas**: prefixo `/global/skills/` espelhando
  filesystem / slugs flat por categoria
- **Score**: 2
- **Justificativa**: alinhado com D-VI (slugs estaveis e
  descritivos derivaveis do path-fonte); espelha estrutura mental do
  usuario ("o que e a skill X?") em vez do filesystem
  (`global/skills/...`). Linguagem como segmento intermediario para
  language-related skills evita colisao de nomes entre globais e
  per-lang.

### 4. indexador-busca (FR-006)

- **Decisao**: plugin `search` built-in do mkdocs-material (lunr.js)
- **Opcoes consideradas**: lunr.js (built-in) / Pagefind / Algolia
  DocSearch / none-mvp
- **Score**: 3 (decide_sem_clarificar)
- **Evidencia**: constitution.md linha 145-146 explicitamente declara
  "mkdocs-material usa lunr.js por padrao — aceito"; D-IV exige
  busca client-side <=200ms sem servico externo; Algolia DocSearch
  violaria D-II (servico externo) e Principio IV global (coleta
  remota); Pagefind exige integracao customizada quando MkDocs ja
  oferece built-in maduro.
- **Justificativa**: opcao default consagrada do mkdocs-material;
  zero infra adicional; latencia tipica <100ms em hardware modesto.

### 5. diretorio-fonte-site (FR-023)

- **Decisao**: `docs-site/`
- **Opcoes consideradas**: `docs/` raiz / `site/` / `docs-site/` /
  `web/`
- **Score**: 2
- **Justificativa**: `docs/` ja contem `specs/` (artefatos SDD do
  agente-00c) + `constitution.md` global — usar `docs/` como source
  do site geraria conflito conceitual (specs SDD nao devem ser
  publicadas como manual). `site/` e generico demais; `web/` sugere
  app, nao docs; `docs-site/` e auto-explicativo. `mkdocs.yml`
  ficara na raiz com `docs_dir: docs-site/`.

### 6. sanitizacao-md-exotico (FR-024)

- **Decisao**: passar puro + warning (opcao c do FR-024)
- **Opcoes consideradas**: (a) remover/escapar antes da
  renderizacao / (b) passar puro silencioso / (c) passar puro +
  warning no build
- **Score**: 2
- **Justificativa**: D-I (Documentation-as-Source-of-Truth)
  nao-negociavel — modificar conteudo no build cria divergencia
  invisivel entre fonte e publicacao. Frontmatter Claude-specifico
  e YAML valido (mkdocs-material consome via plugin `meta`); HTML
  inline tem CSP do tema default bloqueando scripts arbitrarios;
  linguagens raras de code blocks degradam para sem-highlight (nao
  quebram build). Warning informa o autor sem bloquear publicacao.

---

## Next Steps

1. ~~`/clarify`~~ — concluido em 2026-05-19 (6 pendencias resolvidas;
   ver Resolved Ambiguities).
2. `/plan` — gerar plano tecnico de implementacao (estrutura de
   arquivos sob `docs-site/`, `mkdocs.yml` definitivo, plugins
   `awesome-pages`/`gen-files`/`meta`, workflow YAML
   `.github/workflows/publish-site.yml` com `deploy-pages@v4`).
3. `/checklist` — validar qualidade dos requisitos antes de
   `/create-tasks`.
