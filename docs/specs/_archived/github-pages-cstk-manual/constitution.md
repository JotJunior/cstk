<!--
Predecessor: docs/constitution.md v1.1.0
Scope: feature github-pages-cstk-manual

Sync Impact Report
- Version: (none) → 1.0.0  [initial ratification, feature-delta]
- Tipo: feature-delta constitution (NAO substitui a global v1.1.0)
- Relacao com global v1.1.0: HERDA integralmente os Principios I-V do
  toolkit (SDD recursivo, POSIX sh puro, formato canonico de skill, zero
  coleta remota, profundidade > adocao). ESPECIALIZA o escopo de
  documentacao publicada adicionando 6 principios proprios desta feature.
- Em caso de tensao entre delta e global: global vence (regra do
  Predecessor — ver Governance abaixo).
- Principios criados (1.0.0):
  D-I.   Documentation-as-Source-of-Truth (NON-NEGOTIABLE)
  D-II.  Static-Site-First (NON-NEGOTIABLE)
  D-III. Automated-Publishing
  D-IV.  Searchable-by-Default
  D-V.   Accessibility-Floor (WCAG 2.1 AA)
  D-VI.  Versioning-Friendly
- Secoes adicionadas: Core Principles (delta), Quality Standards
  (delta), Decision Framework (delta), Governance (delta).
- Artefatos que precisam atualizacao quando ratificada:
  * docs/specs/github-pages-cstk-manual/spec.md — referenciar este
    delta em Constitution Check (a criar na etapa specify);
  * docs/specs/github-pages-cstk-manual/plan.md — Constitution Check
    deve validar contra v1.1.0 (global) + 1.0.0 (delta) (a criar na
    etapa plan);
  * docs/specs/github-pages-cstk-manual/tasks.md — toda task de
    publicacao/build/UI deve citar principio aplicavel (a criar na
    etapa create-tasks).
- TODOs pendentes:
  * TODO(SOURCE_DIR_PATH): caminho-fonte do README oficial do toolkit
    sera definido em /clarify (pergunta-pendente 5 do briefing).
  * TODO(PUBLISH_BRANCH): branch de publicacao (gh-pages vs main /docs)
    sera definida em /clarify (pergunta-pendente 2 do briefing).
  * TODO(MKDOCS_VERSION_PIN): versao especifica de mkdocs-material a
    pinar sera definida em /plan apos clarify (pergunta-pendente 1).
-->

# github-pages-cstk-manual Constitution (feature-delta)

Principios especializados desta feature para publicacao do manual do
toolkit `claude-ai-tips` como site estatico em GitHub Pages. Esta
constitution e **delta** da constituicao global do toolkit
(`docs/constitution.md` v1.1.0): herda os 5 principios da raiz e
adiciona 6 principios proprios do dominio de documentacao publicada.
Violacoes sao bloqueantes em `/plan` e `/analyze` desta feature.

Briefing-fonte: `docs/specs/github-pages-cstk-manual/briefing.md`.

## Core Principles

### D-I. Documentation-as-Source-of-Truth (NON-NEGOTIABLE)

O conteudo canonico da documentacao vive nos arquivos-fonte do
repositorio (README.md, docs/*.md, SKILL.md de cada skill). O site
publicado e **projecao** desse conteudo, nao copia divergente.

**MUST:**

- Nenhum texto substantivo e escrito apenas no `docs/site/` (ou
  equivalente do mkdocs source dir). Conteudo unico-do-site limita-se
  a metadados de navegacao (`mkdocs.yml`), CSS/branding minimo e
  arquivos-ponte que `include` ou referenciam fontes canonicas.
- Quando o README.md ou SKILL.md sofre mudanca substantiva, o site
  reflete na proxima publicacao automatica. Drift entre fonte e site
  por mais de 1 ciclo de publicacao e bug bloqueante.
- Duplicacao de conteudo (mesmo paragrafo em 2+ arquivos) e proibida
  exceto em sumarios de navegacao explicitamente marcados como "veja
  tambem".

**Rationale:** o briefing identifica que o README do toolkit ja e
extenso e bem estruturado; o problema e descoberta/navegacao, nao
falta de conteudo. Reescrever a documentacao para o site criaria duas
fontes-de-verdade — exatamente o anti-padrao que o toolkit combate em
projetos que ele apoia (Principio I global: SDD recursivo).

### D-II. Static-Site-First (NON-NEGOTIABLE)

O site e 100% estatico: HTML + CSS + JS pre-construidos no momento do
build. Sem servidor de aplicacao, sem renderizacao server-side em
runtime, sem dependencia de servico externo para funcao essencial.

**MUST:**

- Build determinista: mesmo input (commits da main) + mesma versao
  pinada do mkdocs-material produz mesmo output binario-equivalente
  (modulo timestamps).
- Funcao essencial (ler texto, navegar TOC, abrir links internos)
  funciona com JavaScript desabilitado. JS pode aprimorar (busca
  client-side, copy-button, dark-mode toggle) mas nao habilitar core.
- Zero chamada para API externa em runtime do navegador para conteudo
  ou navegacao. CDN para fontes/icones e aceitavel se com fallback
  local; analytics/tracking sao PROIBIDOS (reforco do Principio IV
  global: zero coleta remota).
- Sem dependencia de servico hospedado de terceiros para build
  alem do GitHub Pages e GitHub Actions. Nao usar Netlify, Vercel,
  Cloudflare Pages como dependencia obrigatoria.

**Rationale:** GitHub Pages so serve estaticos, entao a restricao e
fisica. Mas o principio tambem garante longevidade — site sobrevive
ao fim de qualquer SaaS terceiro, e o conteudo continua acessivel
mesmo se o build break por meses (ultima publicacao continua viva).

### D-III. Automated-Publishing

Cada push na branch principal (main) com mudanca em
`docs/`, `README.md`, `mkdocs.yml`, ou `global/skills/**/SKILL.md`
dispara publicacao automatica via GitHub Actions. Deploy manual e
excecao, nao caminho feliz.

**MUST:**

- Workflow GitHub Actions versionado em `.github/workflows/` com
  triggers em `push` para main + `pull_request` (build-only, sem
  publish) para validar PRs.
- Tempo total do workflow (checkout → build → publish) <=5 minutos
  em condicoes normais. Build local (`mkdocs build`) <=60s.
- Falha de build em PR bloqueia merge (status check obrigatorio).
- Publish gravando em branch dedicada (default `gh-pages`) OU em
  diretorio `/docs` da main, conforme decisao na etapa /clarify
  (ver TODO(PUBLISH_BRANCH) no Sync Impact Report).

**SHOULD:**

- Workflow loga URL do site publicado em comentario de PR (quando
  acionado por PR de mantenedor) ou em annotation de commit.
- Re-publicacao manual (workflow_dispatch) disponivel para casos de
  rollback ou re-build sem mudanca de conteudo.

**Rationale:** o briefing marca explicitamente que publicacao deve ser
"automatica a cada push" (feature MVP #7). Workflow manual entropiza
— maintainer esquece, drift acumula, contribuidores nao tem feedback
visual rapido. Automatizar e o caminho ja consagrado no ecossistema
(Read the Docs, Astro, Docusaurus seguem mesmo padrao).

### D-IV. Searchable-by-Default

Busca client-side e funcionalidade core, embutida no build, sem servico
externo.

**MUST:**

- Indice de busca gerado no momento do build (mkdocs-material usa
  lunr.js por padrao — aceito).
- Busca cobre titulo, headings, e corpo de todas as paginas
  publicadas. Code blocks indexados quando contem nomes de skills
  ou comandos de CLI (`cstk *`, `/agente-00c *`).
- Latencia de query <=200ms em hardware comum (desktop modesto, ~5
  anos). Indice servido como asset estatico (sem network round-trip).
- Resultado de busca preserva ranking por relevancia + contexto
  (snippet com termo destacado).

**SHOULD:**

- Hotkey de teclado (default `/` ou `s`) abre busca sem mouse.

**Rationale:** o briefing identifica "busca" como pendencia explicita
(pendencia 4) e o problema central do README atual e "encontrar a
secao certa rapido". Sem busca, o site repete o problema do README;
com busca remota (Algolia, etc), violamos D-II e Principio IV global
(coleta remota).

### D-V. Accessibility-Floor (WCAG 2.1 AA minimo)

O site atende WCAG 2.1 nivel AA como piso minimo nao-negociavel para
contraste, navegacao por teclado, semantica de headings e textos
alternativos.

**MUST:**

- Contraste de texto >=4.5:1 para body, >=3:1 para texto grande
  (>=18pt). Tema dark e light ambos auditados.
- Toda imagem informativa tem `alt` text descritivo; imagens
  puramente decorativas tem `alt=""` explicito (nao omitido).
- Hierarquia de headings sem pulos (h1 → h2 → h3, sem saltar para
  h4). Lighthouse Accessibility score >=90 em pagina representativa.
- Navegacao por teclado funcional: TAB percorre links e controles em
  ordem visual; foco visivel (outline nao removido sem substituto).
- Linguagem da pagina declarada (`<html lang="pt-BR">` ou similar
  conforme idioma-fonte).

**SHOULD:**

- Skip-to-content link no inicio de cada pagina.
- Suporte a prefers-reduced-motion (sem animacoes nao-essenciais).

**Rationale:** o briefing menciona 4 atores incluindo "casual-reader"
que pode incluir usuarios com tecnologia assistiva. AA e o piso
internacional minimo para documentacao publica; ir abaixo seria
exclusao ativa. Material theme ja entrega AA por default — o
principio garante que mudancas customizadas nao regridem.

### D-VI. Versioning-Friendly

Estrutura de arquivos, URLs e configuracao permite introducao futura
de versoes multiplas (latest, stable, vX.Y) sem rewrite arquitetural.

**MUST:**

- URLs de paginas usam slugs estaveis e descritivos (`/skills/specify/`
  e nao `/p/42/`). Renomear pagina exige redirect ou aviso explicito.
- `mkdocs.yml` estruturado de forma que adicao futura de plugin
  `mike` (versionamento de mkdocs-material) nao exija reescrever
  navegacao ou paths.
- Conteudo gerado a partir de SKILL.md das skills usa caminho
  derivavel do path-fonte (`global/skills/<nome>/SKILL.md` →
  `/skills/<nome>/`). Sem hardcoded mappings que quebrem ao mover
  skill.

**SHOULD:**

- Documentar em ADR (ou em plan.md desta feature) a decisao de NAO
  ativar versionamento no MVP — para que ativacao futura seja
  amendment incremental (PATCH/MINOR), nao MAJOR.

**Rationale:** o briefing nao pede versionamento agora (escopo MVP),
mas o toolkit cresce e versoes futuras (com BREAKING) sao
inevitaveis. Decidir agora "facilitar a transicao" custa pouco;
adiar custa rewrite quando v2 vier.

## Quality Standards (delta)

Quality gates desta feature, complementando o global v1.1.0:

- **Build determinista verificavel** — `mkdocs build` rodado duas vezes
  consecutivas produz output identico (modulo timestamps embutidos).
  Verificavel via `diff -r site/ site2/` filtrando timestamps.
- **Lighthouse Accessibility >=90** — score auditado em pelo menos
  duas paginas (home + uma SKILL renderizada). Falha bloqueia merge
  do PR que introduziu regressao.
- **Tempo de build local <=60s** — em hardware do mantenedor.
  Detectavel via `time mkdocs build` em CI; warn em >45s, fail em >60s.
- **Workflow GitHub Actions verde** — status check obrigatorio em PRs
  que tocam docs/* ou mkdocs.yml.
- **Zero dependencia de servico externo em runtime** — auditavel via
  inspecao manual do HTML publicado: nao ha `<script src=https://...>`
  apontando para analytics, A/B testing, CDN-tracker.
- **README e SKILL.md sao fontes canonicas** — verificavel: paginas
  geradas referenciam-nos via include/ponte; busca textual no
  diretorio fonte do site nao encontra paragrafos duplicados.

## Decision Framework (delta)

Quando principios desta feature entram em tensao com a constituicao
global ou entre si:

1. **Global vence delta.** Se um principio desta feature aparenta
   conflitar com a constituicao global v1.1.0 (Principios I-V do
   toolkit), o global vence. Esta feature **especializa** o global,
   nunca o sobrescreve. Exemplo: se D-IV (busca embutida) exigisse
   coleta remota, Principio IV global (zero coleta) prevalece e D-IV
   e redesenhado.

2. **NON-NEGOTIABLE vence SHOULD dentro do delta.** D-I e D-II sao
   MUST nao-negociaveis; D-III, D-IV, D-V, D-VI tem mistura de MUST
   + SHOULD. Em tensao, MUST vence SHOULD.

3. **Acessibilidade vence estetica.** Em conflito entre D-V
   (acessibilidade) e refinamento visual (cor, tipografia,
   animacao), D-V vence. Refinamento e redesenhado para atender AA.

4. **Excecao a MUST exige amendment desta constitution** (MINOR
   bump). Excecao a SHOULD pode ser registrada em `plan.md` da
   feature com secao `Constitution Exception` justificando o
   trade-off e sunset.

## Governance (delta)

**Authority:**

- Autor/mantenedor do toolkit (jot) aprova amendments desta
  constitution feature-delta. Quando um amendment desta delta
  conflitar com a global, prevalece a global ate que a global
  receba amendment correspondente.

**Amendment process:**

- Amendments desta delta seguem mesmo SemVer do toolkit (MAJOR/
  MINOR/PATCH), mas a versao desta delta e independente da global
  (esta delta comeca em 1.0.0).
- Amendment que remove ou redefine principio desta delta
  incompativelmente = MAJOR bump desta delta.
- Amendment que adiciona novo principio ou expande materialmente uma
  secao desta delta = MINOR bump.
- Amendment que clarifica texto sem mudar semantica = PATCH bump.

**Propagacao obrigatoria em MAJOR/MINOR desta delta:**

- Atualizar Sync Impact Report no topo deste arquivo.
- Re-rodar `/analyze` na feature `github-pages-cstk-manual` e
  documentar violacoes introduzidas.
- Avaliar se mudanca desta delta sugere mudanca correspondente na
  global (ex: principio desta delta provou-se util cross-feature).

**Relacao com global:**

- Sempre que a global (`docs/constitution.md`) sofrer amendment
  MAJOR ou MINOR, esta delta deve ser re-validada para garantir
  compatibilidade. Compatibilidade pode exigir amendment desta
  delta (PATCH se cosmetic, MINOR se realinha principio).

**Versioning:**

- SemVer rigoroso: MAJOR.MINOR.PATCH (desta delta, independente da
  global).
- Datas em ISO YYYY-MM-DD.
- Versao inicial 1.0.0.

**Version**: 1.0.0 | **Ratified**: 2026-05-19 | **Last Amended**: 2026-05-19
