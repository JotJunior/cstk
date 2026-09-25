# Feature Specification: Apresentacao Narrativa do Projeto

**Feature**: `presentation`
**Created**: 2026-09-25
**Status**: Draft

## Clarifications

### Session 2026-09-25

- Q: O template visual (design system) da apresentacao deve ser produzido
  por handoff do Claude Design ou criado diretamente nesta feature? → A:
  Criado diretamente nesta feature, autocontido (sem CDN nem fonte remota,
  Principio IV); pode ser refinado depois no Claude Design sem mudar o
  contrato da gramatica.
- Q: Qual o formato de saida gerado em cada projeto? → A: Duas pecas em
  `docs/presentation/`: `story.md` (fonte narrativa editavel e
  retroalimentada) e `index.html` (arquivo unico offline com modo slides,
  modo relatorio e impressao em PDF). O HTML e sempre derivado do
  `story.md`.
- Q: Projetos maduros tem dezenas de specs. Como tratar a densidade? → A:
  Um slide por spec (ativa, arquivada ou viva), agrupadas em capitulos por
  onda/data de arquivamento. Completo mesmo que longo.
- Q: Como impedir que o tom "vendavel" produza numeros inventados
  (Principio VI)? → A: Metricas nunca sao escritas pelo redator: o
  `story.md` referencia chaves do inventario (`@metric Rotulo | chave`) e o
  render resolve o valor a partir do inventario deterministico. Chave
  desconhecida e erro de validacao.
- Q: Onde fica a linha de base para a retroalimentacao (saber o que mudou
  desde a ultima geracao)? → A: Em `docs/presentation/inventory.tsv`,
  snapshot do inventario gravado junto do `story.md`; o diff entre o
  snapshot e um scan novo aponta specs novas, alteradas e removidas.

## User Scenarios & Testing

### User Story 1 - Gerar a apresentacao do projeto a partir das docs (Priority: P1)

Um lider de projeto que usa o pipeline SDD do cstk precisa apresentar o
projeto a stakeholders (diretoria, cliente, time novo). Toda a historia ja
esta escrita em `docs/` (briefing, constitution, specs com clarify,
research, checklists, tasks e converge), mas espalhada em dezenas de
arquivos tecnicos. Ele invoca `/presentation` e recebe um documento unico,
bonito e narrativo que conta de onde o projeto veio, no que acredita, o
que foi construido e como cada feature foi pensada, enriquecida e
implementada.

**Why this priority**: e o valor central da skill; sem ela nenhum outro
cenario existe.

**Independent Test**: rodar a skill sobre um projeto com briefing,
constitution e ao menos duas specs e abrir o `index.html` gerado sem rede.

**Acceptance Scenarios**:

1. **Given** um projeto com briefing, constitution e specs em `docs/`,
   **When** o operador invoca `/presentation`, **Then** sao gerados
   `docs/presentation/story.md`, `docs/presentation/inventory.tsv` e
   `docs/presentation/index.html` (FR-001, FR-002).
2. **Given** o inventario lista N specs (ativas, arquivadas e vivas),
   **When** a apresentacao e gerada, **Then** existe exatamente um slide
   de spec para cada uma das N specs, agrupadas em capitulos (FR-004,
   FR-005).
3. **Given** um slide de spec, **When** ele e renderizado, **Then** mostra
   quatro blocos: o que e, como foi pensada, como foi enriquecida e como
   foi implementada, mais selo de estagio e faixa de metricas (FR-006).
4. **Given** o `index.html` gerado, **When** aberto num navegador sem
   acesso a rede, **Then** renderiza completo, sem nenhuma requisicao
   externa (FR-010).
5. **Given** o `index.html` aberto, **When** o leitor alterna entre modo
   slides, modo relatorio e impressao, **Then** o mesmo conteudo e
   apresentado nos tres modos (FR-011).

---

### User Story 2 - Retroalimentar a apresentacao quando o projeto evolui (Priority: P2)

Semanas depois, novas specs foram criadas e outras arquivadas. O operador
invoca `/presentation` de novo. A skill detecta o que mudou desde a ultima
geracao e reescreve apenas os slides afetados, preservando os ajustes que
ele fez a mao nos demais.

**Why this priority**: sem retroalimentacao a apresentacao envelhece e a
skill vira uso unico; e o que a torna "viva".

**Independent Test**: gerar, editar um slide inalterado a mao, adicionar
uma spec nova, regenerar e verificar que o slide editado permanece e o
novo aparece.

**Acceptance Scenarios**:

1. **Given** um `inventory.tsv` de uma geracao anterior e uma spec nova em
   `docs/specs/`, **When** o diff de inventario roda, **Then** a spec nova
   aparece como `added` e as demais como `unchanged` (FR-007).
2. **Given** um slide cuja fonte nao mudou e que foi editado a mao,
   **When** a apresentacao e regenerada sem `--full`, **Then** o texto
   editado e preservado (FR-008).
3. **Given** uma spec removida do inventario, **When** o diff roda,
   **Then** ela aparece como `removed` e o redator remove o slide
   correspondente (FR-007).

---

### User Story 3 - Ajustar o texto e re-renderizar sem reescrever (Priority: P3)

O operador revisa o `story.md`, lapida uma frase e quer so atualizar o
HTML, sem que o redator mexa em nada.

**Why this priority**: conveniencia de edicao; o HTML e derivado e nunca
deve ser editado a mao.

**Independent Test**: editar o `story.md`, rodar `--render-only` e
conferir o texto novo no HTML, com o `story.md` byte a byte inalterado.

**Acceptance Scenarios**:

1. **Given** um `story.md` valido, **When** o operador invoca
   `/presentation --render-only`, **Then** apenas `index.html` e
   regenerado e o `story.md` nao e alterado (FR-009).
2. **Given** o mesmo `story.md` e o mesmo `inventory.tsv`, **When** o
   render roda duas vezes, **Then** os dois `index.html` sao identicos
   byte a byte (FR-012).

---

### Edge Cases

- Projeto sem briefing ou sem constitution: a skill segue com o que
  existe; o slide ausente nao e fabricado e o validador nao exige o tipo
  correspondente (FR-003, FR-013).
- Briefing no layout legado `docs/01-briefing-discovery/briefing.md`: o
  scan localiza nos dois caminhos (FR-003).
- Spec arquivada sem `spec.md` ou sem `tasks.md`: aparece com os
  artefatos que tem; o estagio nunca e "implementada" sem tarefas
  concluidas que comprovem (FR-006, FR-013).
- `@metric` com chave inexistente, slide factual sem `@source`, `@source`
  apontando para arquivo inexistente ou spec do inventario sem slide: o
  validador falha com a linha do problema e o render nao roda (FR-013,
  FR-014).
- Texto com `<`, `>` ou `&` no `story.md`: e escapado no HTML, nunca
  interpretado como marcacao (FR-015).
- Nenhuma spec em `docs/specs/`: a apresentacao cobre briefing e
  constitution; o capitulo de specs fica ausente sem erro (FR-004).
- Instalacao via `cstk install` com perfil `complementary`: a skill chega
  com seus scripts POSIX, cada um coberto por teste 1:1 na suite (FR-017).

## Requirements

### Functional Requirements

- **FR-001**: A skill MUST ser invocavel como `/presentation`, aceitando
  `--docs <dir>` (default `docs`), `--out <dir>` (default
  `docs/presentation`), `--lang <pt-BR|en>`, `--render-only` e `--full`.
- **FR-002**: A saida MUST consistir em `story.md` (fonte narrativa),
  `inventory.tsv` (snapshot do inventario) e `index.html` (derivado),
  todos no diretorio de saida.
- **FR-003**: Um script deterministico MUST inventariar briefing (caminho
  atual ou legado), constitution (versao e principios) e specs (ativas em
  `specs/*/`, arquivadas em `specs/_archived/*/`, vivas em
  `specs/current/*.md`), sem depender do redator para extrair fatos.
- **FR-004**: O inventario de cada spec MUST conter chave unica, status
  (`active|archived|living`), data de arquivamento quando houver,
  artefatos presentes, sessoes e perguntas de clarify, tarefas concluidas
  e totais, ultimo outcome de converge, estagio derivado, titulo e digest.
- **FR-005**: A apresentacao MUST conter exatamente um slide de spec para
  cada spec do inventario, agrupados em capitulos.
- **FR-006**: Cada slide de spec MUST ter quatro secoes (o que e, como foi
  pensada, como foi enriquecida, como foi implementada), selo de estagio
  vindo do inventario e ao menos uma citacao de fonte.
- **FR-007**: O script MUST comparar dois inventarios e classificar cada
  item como `added`, `changed`, `removed` ou `unchanged` pelo digest.
- **FR-008**: Em regeneracao sem `--full`, o redator MUST reescrever
  apenas slides de itens `added` ou `changed`, remover slides de itens
  `removed` e preservar literalmente os slides de itens `unchanged`.
- **FR-009**: Com `--render-only`, a skill MUST apenas validar e
  renderizar, sem alterar `story.md` nem `inventory.tsv`.
- **FR-010**: O `index.html` MUST ser um arquivo unico autocontido (CSS e
  JS inline, fontes do sistema), sem nenhuma referencia a recurso de rede.
- **FR-011**: O `index.html` MUST oferecer modo slides (navegacao por
  teclado, progresso, deep link), modo relatorio (rolagem continua com
  indice) e folha de impressao com um slide por pagina, alem de tema
  claro e escuro.
- **FR-012**: O render MUST ser deterministico: mesmas entradas geram
  saida identica byte a byte (nenhum timestamp de execucao embutido).
- **FR-013**: Metricas MUST ser resolvidas pelo render a partir de chaves
  do inventario (`@metric Rotulo | chave`); o redator MUST NOT escrever
  valores numericos de metrica, e chave desconhecida MUST falhar a
  validacao.
- **FR-014**: Um validador MUST checar, antes do render: frontmatter,
  tipos de slide do catalogo fechado, cobertura 1:1 das specs, quatro
  secoes por slide de spec, `@source` existente em slides factuais,
  chaves de metrica validas e ausencia de placeholders; cada violacao
  reportada com numero de linha.
- **FR-015**: O render MUST escapar HTML de todo texto do `story.md` antes
  de aplicar a formatacao inline suportada.
- **FR-016**: Todo resultado MUST obedecer ao mesmo template: catalogo
  fechado de tipos de slide (`cover`, `manifesto`, `briefing`,
  `constitution`, `chapter`, `spec`, `timeline`, `numbers`, `closing`,
  `sources`) e layout fixo por tipo.
- **FR-017**: A skill MUST ser distribuida no perfil `complementary` do
  cstk, com scripts POSIX sh testados 1:1.

### Key Entities

- **Inventario**: TSV deterministico com registros `project`, `briefing`,
  `constitution`, `principle`, `spec` e `totals`. Gerado por
  `scan-project-docs.sh`; persistido como `inventory.tsv`.
- **Story**: `story.md` com frontmatter e slides delimitados por
  comentario HTML, numa gramatica restrita. Unica peca escrita pelo
  redator.
- **Slide**: unidade da apresentacao, de um tipo do catalogo fechado; o
  slide de spec aponta para uma chave do inventario.
- **Deck**: `index.html` derivado de story + inventario + template.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Para o proprio repositorio cstk, 100% das specs do
  inventario tem slide correspondente e o validador sai com exit 0.
- **SC-002**: O `index.html` gerado faz zero requisicoes de rede ao ser
  aberto (verificado em navegador com rede bloqueada).
- **SC-003**: Nenhuma metrica exibida no deck deixa de ter origem no
  inventario (verificado pelo validador: zero `@metric` com chave fora do
  contrato).
- **SC-004**: Duas execucoes do render sobre as mesmas entradas produzem
  arquivos identicos (comparacao por `cmp`).
- **SC-005**: Render e validacao do cstk (mais de 50 specs) terminam em
  menos de 5 segundos cada.

## Delta Requirements

**Skip**: Feature inteiramente nova; nenhuma capacidade ativa em `docs/specs/current/` cobre geracao de apresentacao ou relatorio narrativo do projeto.
