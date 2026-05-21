# Feature Specification: Model Selector — Sugerir modelos mais baratos para tarefas rasas

**Feature**: `model-selector`
**Created**: 2026-05-21
**Status**: Draft

> **Contexto**: este toolkit (claude-ai-tips) hospeda orquestradores autonomos
> (agente-00c e feature-00c) que gastam contexto e custo em CADA chamada de
> ferramenta e CADA invocacao de subagente. Muitas dessas chamadas sao
> mecanicas — concatenar JSON, registrar uma decisao trivial, formatar
> markdown, executar um grep, gerar uma resposta clarify de score >=2 sem
> ambiguidade — e nao se beneficiam do modelo "topo de linha" (Opus). Hoje a
> escolha de modelo e implicita: o orquestrador roda no modelo do operador
> humano (frequentemente Opus 4.7 1M), e os subagentes herdam. A feature
> propoe uma **heuristica auditavel** que classifique a tarefa proxima em uma
> faixa de complexidade e SUGIRA ao orquestrador (ou ao operador humano)
> trocar para um modelo mais barato (Haiku, Sonnet) sem perda mensuravel de
> qualidade. Decisao da troca permanece humana/orquestrador — a feature
> nunca troca silenciosamente o modelo.

---

## User Scenarios & Testing

### User Story 1 — Orquestrador recebe sugestao de modelo barato antes de spawn de subagente trivial (Priority: P1)

Joao roda `/feature-00c` para uma feature nova. O orquestrador
`agente-00c-feature-orchestrator` esta na fase `clarify` e precisa spawnar
`feature-00c-clarify-answerer` para responder 3 perguntas onde a evidencia ja
esta no briefing + constitution (score esperado: 2 a 3, zero pausa humana
prevista). Hoje o answerer roda no mesmo modelo que o orquestrador (Opus).
A feature propoe que, antes do spawn, o orquestrador consulte a heuristica
de selecao de modelo, receba uma sugestao "Haiku basta para 3 perguntas com
evidencia direta no briefing", registre a sugestao como Decisao auditavel
(score 2+ com justificativa), e — se aceitar — spawne o answerer ja
parametrizado com o modelo sugerido.

**Why this priority**: maior volume de chamadas LLM no toolkit hoje vem de
spawns de clarify-answerer/clarify-asker; e onde a economia per-onda e mais
sensivel sem risco de regressao de qualidade (perguntas com evidencia direta
sao o caso de uso mais simples do answerer).

**Independent Test**: rodar uma onda de `/feature-00c` em uma feature de
escopo trivial (ex: documentar uma constante existente) com a heuristica
ativa. Verificar que (a) Decisao "modelo sugerido: haiku para clarify-
answerer; aceito" foi registrada em `state.decisoes`, (b) o spawn do
subagente recebeu parametro de modelo barato, (c) a resposta JSON do
answerer continua valida (schema scores 0..3 + perguntas com 1 escolhida).

**Acceptance Scenarios**:

1. **Given** orquestrador em fase `clarify` com 3 perguntas com evidencia
   direta no briefing/constitution, **When** invoca a heuristica antes do
   spawn, **Then** recebe sugestao "haiku" + justificativa citando os
   sinais ("perguntas com evidencia direta", "score esperado >=2", "zero
   ambiguidade detectada") + score de confianca da sugestao.
2. **Given** orquestrador recebeu sugestao "haiku", **When** aceita,
   **Then** registra Decisao em `state.decisoes` com 5 campos
   obrigatorios + score 2 + referencia ao artefato (sugestao da heuristica)
   + spawna o subagente com flag/parametro de modelo (interface a definir).
3. **Given** orquestrador recebeu sugestao "haiku" mas detecta sinal de
   ambiguidade na ultima pergunta (texto contem "pode ser que" ou similar),
   **When** decide ignorar a sugestao, **Then** registra Decisao "rejeitar
   sugestao do model-selector" com justificativa empirica (citacao literal
   do sinal de ambiguidade) e spawna com modelo padrao.

---

### User Story 2 — Operador humano recebe sugestao de modelo barato no inicio de uma sessao manual (Priority: P2)

Joao abre o Claude Code para uma tarefa que ele sabe ser trivial — "rode
`grep` em um diretorio e me diga quantos matches" ou "renomeie esta funcao
em 3 arquivos com `sed`". O modelo padrao do harness e Opus. A feature
expoe um meio (skill ou hook leve) que, dado o texto da primeira mensagem
do operador, classifique a tarefa e sugira "Haiku ou Sonnet seria
suficiente para isso — quer trocar com `/model haiku`?". A sugestao e
informativa, nunca obrigatoria. O operador segue no Opus se quiser.

**Why this priority**: economia direta no uso interativo do operador, sem
mexer em orquestradores. Vale como complemento mas tem risco menor que a
sugestao a orquestradores autonomos (que rodam many-shot sem humano no
loop).

**Independent Test**: invocar a skill com input "execute `grep -rn foo
src/` e me diga quantos resultados" e validar que o output e (a) uma
sugestao "modelo sugerido: haiku" + (b) justificativa baseada em sinais
(verbo `execute`, ferramenta `grep`, output esperado contagem numerica)
+ (c) referencia explicita ao comando `/model haiku` para o operador
trocar. Sem efeito colateral — a skill apenas sugere.

**Acceptance Scenarios**:

1. **Given** operador escreve "rode `grep -c TODO src/` e me retorne o
   numero", **When** invoca a heuristica, **Then** recebe sugestao "haiku"
   + justificativa (verbo deterministico + ferramenta POSIX + output
   numerico) + comando exato sugerido para trocar (`/model haiku`).
2. **Given** operador escreve "refatore este modulo para usar pattern
   Repository", **When** invoca a heuristica, **Then** recebe sugestao
   "manter modelo atual (Opus)" + justificativa (verbo `refatore` +
   conceito arquitetural + multi-arquivo provavel).
3. **Given** operador escreve "explique este bug" em um arquivo de 500
   linhas, **When** invoca a heuristica, **Then** recebe sugestao
   "sonnet" + justificativa (verbo `explique` exige raciocinio mas nao
   geracao complexa; contexto medio).

---

### User Story 3 — Auditoria das sugestoes acumuladas por feature/projeto (Priority: P3)

Apos rodar varias features do `/feature-00c` com a heuristica ativa, Joao
quer ver quanto a sugestao economizou de fato, e quantas vezes o
orquestrador aceitou vs rejeitou. A feature persiste cada sugestao + aceite
no `state.json` da execucao (campo novo) e expoe um relatorio agregado
(comando de leitura, sem efeito colateral) com colunas:
sugestao | aceito | modelo-final-usado | quantas-chamadas-no-modelo-final.

**Why this priority**: alinha com Principio V da constitution (profundidade
> adocao — medir e refinar e mais valioso que adicionar features). Sem
auditoria, a heuristica fica como "caixa preta" e pode regredir
silenciosamente.

**Independent Test**: rodar 2 ondas de `/feature-00c` em features
distintas com a heuristica ativa. Invocar o comando de relatorio. Validar
que (a) o relatorio agrupa por feature, (b) mostra contagem aceitas/
rejeitadas, (c) e POSIX sh puro lendo apenas `state.json` (sem chamada
remota — Principio IV).

**Acceptance Scenarios**:

1. **Given** 2 ondas de feature-00c executadas com 5 sugestoes (3
   aceitas, 2 rejeitadas), **When** operador roda o comando de relatorio,
   **Then** ve linha por feature com totais corretos.
2. **Given** state.json sem sugestoes registradas, **When** roda o
   relatorio, **Then** retorna mensagem "nenhuma sugestao registrada"
   sem erro.

---

### Edge Cases

- O que acontece se a heuristica nao consegue classificar (input
  ambiguo, ex: "faz aquela coisa que conversamos ontem")? Resposta
  esperada: sugestao "manter modelo atual" + justificativa "input
  ambiguo, sinais insuficientes" — nunca chute para modelo barato.
- O que acontece se o orquestrador esta rodando ja em um modelo barato
  (ex: Haiku) e a heuristica sugere "haiku"? Resposta esperada:
  sugestao registrada como "ja no modelo sugerido — no-op" (ainda
  auditavel via Decisao).
- O que acontece se o modelo sugerido nao esta disponivel no harness
  do operador (ex: Haiku ainda nao foi liberado para o tier do
  operador)? Resposta esperada: sugestao traz alternativa do mesmo
  "tier de barateamento" (ex: Sonnet em vez de Haiku) — falha graceful.
- O que acontece se a heuristica entra em loop (chamadas mutuas
  orquestrador → heuristica → orquestrador → heuristica)? Resposta
  esperada: a heuristica e estritamente um-shot por invocacao (sem
  estado proprio, sem spawn de subagente — Principio IV da
  constitution do toolkit, Principio IV do agente-00c sobre blast
  radius confinado).
- Sinal contraditorio: input contem palavras-chave de tarefa simples
  E complexa simultaneamente (ex: "explique e refatore"). Resposta
  esperada: o sinal mais conservador vence (refatore → manter modelo
  atual) — fail-safe.

## Requirements

### Functional Requirements

- **FR-001**: A feature MUST expor uma **skill** (formato canonico do
  toolkit — `SKILL.md` com progressive disclosure + gotchas +
  description-como-trigger conforme Principio III da constitution)
  capaz de receber um texto de tarefa em linguagem natural ou um
  contexto estruturado (proxima fase do pipeline, tipo de subagente,
  artefatos de input) e retornar uma sugestao de modelo.
- **FR-002**: A sugestao retornada MUST conter exatamente: (a) modelo
  sugerido (`haiku` | `sonnet` | `opus` | `manter-atual`), (b) score
  de confianca da sugestao em escala 0..3 (alinhado com FR-EVI-001 do
  runtime — score 3 exige evidencia empirica citada), (c)
  justificativa em texto livre listando os sinais detectados, (d)
  alternativa do mesmo tier (fallback se modelo nao disponivel).
- **FR-003**: A heuristica MUST classificar entrada em **tres faixas
  de complexidade** com sinais explicitos e auditaveis:
  - **Faixa rasa (sugere Haiku)**: verbo deterministico (`rode`,
    `liste`, `conte`, `grep`, `formate`, `renomeie`, `mova`), output
    esperado curto/numerico/estruturado, contexto necessario pequeno
    (1 arquivo ou snippet), zero ambiguidade detectada, scope de UMA
    operacao mecanica.
  - **Faixa media (sugere Sonnet)**: raciocinio simples mas com
    contexto medio (`explique`, `documente`, `resuma`, `traduza`,
    `compare 2 arquivos`), output narrativo curto, sem decisao
    arquitetural.
  - **Faixa profunda (mantem Opus / manter-atual)**: verbo de
    design/decisao (`projete`, `refatore`, `arquitete`, `debate`,
    `escolha entre`), multi-arquivo provavel, decisao com
    consequencia (security, contrato publico, breaking change),
    ambiguidade nao resolvida no input.
- **FR-004**: O catalogo de sinais (verbos, ferramentas, padroes)
  MUST viver em arquivo separado em `references/` da skill
  (progressive disclosure — Principio III), nao hardcoded no
  `SKILL.md`. Operadores podem customizar acrescentando entradas via
  edicao local, sem necessidade de patch.
- **FR-005**: Em caso de **sinais contraditorios** no input, a
  heuristica MUST favorecer o sinal mais conservador (mais
  profundo): ambiguidade entre haiku e sonnet → sonnet; entre sonnet
  e opus → opus. Justificativa MUST citar literalmente o sinal
  conservador que venceu.
- **FR-006**: A sugestao MUST ser **informativa, nunca prescritiva**.
  A skill nao tem permissao de trocar modelo do harness, nao chama
  `/model`, nao manipula estado de sessao. O orquestrador ou
  operador humano executa a troca explicitamente.
- **FR-007**: Quando invocada por um orquestrador autonomo (agente-
  00c ou feature-00c), a sugestao MUST ser registrada como **Decisao
  auditavel** em `state.decisoes` via `state-decisions.sh register`
  do runtime compartilhado — 5 campos obrigatorios + score 0..3 +
  justificativa. Sem registro = violacao do Principio I de
  auditabilidade total.
- **FR-008**: Quando o orquestrador **aceita** a sugestao, MUST
  spawnar o proximo subagente parametrizado com o modelo sugerido. O
  mecanismo exato de parametrizacao (flag CLI, prompt-prefix,
  variavel de ambiente, header) e **uma decisao tecnica da fase
  `/plan`** — esta spec apenas exige que o parametro chegue ao
  subagente.
- **FR-009**: Quando o orquestrador **rejeita** a sugestao, MUST
  registrar Decisao explicita "rejeitar sugestao do model-selector"
  com justificativa empirica (sinal contrario citado literalmente do
  contexto). Rejeitar sem justificativa = violacao FR-EVI-001 do
  runtime (score < 2 forcado).
- **FR-010**: A heuristica MUST ser implementada em **POSIX sh puro**
  (Principio II da constitution). Sem `jq`, sem `ripgrep`, sem
  Bash-isms. Catalogo de sinais em arquivo de texto simples
  (markdown ou flat-text), parsing via `awk`/`grep`/`sed`. Excecao a
  POSIX sh PURO so permitida via o carve-out de "deps opcionais com
  fallback graceful" do amendment 1.1.0 — se aplicado, MUST estar
  declarado neste spec antes de aparecer no plano.
- **FR-011**: A feature MUST **persistir cada sugestao + aceite/
  rejeite no `state.json`** das execucoes do agente-00c/feature-00c,
  em campo dedicado (ex: `metricas_acumuladas.model_selector` com
  contadores por modelo sugerido e por modelo final usado). O nome
  exato do campo e contrato com runtime sao decisao de `/plan`.
- **FR-012**: A feature MUST oferecer **comando de relatorio
  read-only** (script POSIX sh em `scripts/` da skill) que leia
  `state.json` de uma ou mais execucoes e emita tabela markdown com
  sugestoes/aceites/rejeites por feature. Read-only = sem efeito
  colateral, sem chamada remota (Principio IV).
- **FR-013**: A feature MUST documentar em `SKILL.md` secao
  **Gotchas** obrigatoria (Principio III) cobrindo no minimo: (a)
  "sugestao nunca troca modelo silenciosamente", (b) "sinais
  contraditorios = vence o conservador", (c) "input ambiguo = manter
  modelo atual", (d) "score 3 exige evidencia empirica conforme
  FR-EVI-001 do runtime", (e) "skill nao spawna subagente — sem
  blast radius alem do diretorio do projeto-alvo".
- **FR-014**: O `description` do `SKILL.md` MUST ser **trigger
  condition** no formato canonico do toolkit ("Use quando X / NAO
  use quando Y") — Principio III.
- **FR-015**: Decisoes de infraestrutura: **N/A explicito** — a
  feature e stateless por invocacao (sem scheduler, sem token, sem
  mutex), persistencia entre invocacoes acontece em `state.json` que
  ja tem politica de backup/lock/rotacao herdada do runtime
  agente-00c. A skill em si nao introduz novo estado persistente
  proprio.
- **FR-016**: A feature MUST respeitar **zero coleta remota**
  (Principio IV): a heuristica nunca faz HTTP request, nunca chama
  API de modelo externa para "perguntar qual modelo usar". Toda
  classificacao roda local, deterministica, do catalogo de sinais.
- **FR-017**: A feature MUST estar coberta por **testes
  automatizados** seguindo o padrao da suite `shell-scripts-tests`
  (em construcao no projeto). Cobertura minima: classificacao das 3
  faixas + caso ambiguo + sinais contraditorios + input vazio.

### Key Entities

- **SinalDeClassificacao**: unidade do catalogo. Atributos: termo
  (verbo, ferramenta ou padrao), faixa associada (`rasa` | `media` |
  `profunda`), peso (default 1, customizavel). Nao implementacao —
  contrato semantico apenas.
- **SugestaoDeModelo**: artefato retornado pela skill. Atributos:
  modelo-sugerido, score (0..3), justificativa, sinais-detectados
  (lista de SinalDeClassificacao matched), alternativa-de-fallback.
- **DecisaoDeAceite**: registro auditavel em `state.decisoes` quando
  invocada por orquestrador. Atributos herdados do schema de Decisao
  do runtime (contexto, opcoes, escolha, justificativa, score) +
  referencia ao SugestaoDeModelo originador.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Em uma amostra de 10 invocacoes da skill com inputs
  classificados manualmente pelo autor em uma das 3 faixas, a
  heuristica acerta a faixa em pelo menos **8 de 10 casos** (80%) —
  com os outros 2 sendo casos ambiguos justificadamente classificados
  como conservadores (FR-005).
- **SC-002**: Em uma execucao real de `/feature-00c` com a
  heuristica ativa, **pelo menos 30%** das chamadas de subagente
  (clarify-asker, clarify-answerer) recebem sugestao de modelo
  barato (haiku ou sonnet) e, das aceitas, **nenhuma resulta em
  retro-execucao** por qualidade insuficiente da resposta
  (medido via `retro_execucoes_consumidas` no state.json).
- **SC-003**: O comando de relatorio (FR-012) executa em **menos de
  500ms** em um diretorio com 20 execucoes de `state.json`
  acumuladas (verificavel via `time` no shell — meta de
  responsividade interativa, nao "alta performance").
- **SC-004**: A skill consome **menos de 200 linhas** no
  `SKILL.md` (sem contar templates/exemplos/references) — preserva
  o padrao de progressive disclosure do toolkit.
- **SC-005**: **Zero invocacoes externas de rede** em qualquer
  caminho de execucao da skill, verificavel via `grep -rn 'curl\|
  wget\|http' global/skills/model-selector/` retornando vazio
  exceto comentarios.
- **SC-006**: **Zero falsos positivos para "haiku" em inputs com
  verbos de design** (`refatore`, `projete`, `arquitete`,
  `escolha`) — verificavel via teste automatizado dedicado (faz
  parte da cobertura minima de FR-017).
