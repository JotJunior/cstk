# Feature Specification: Agente-00C Artifact Cache

**Feature**: `agente-00c-artifact-cache`
**Created**: 2026-05-20
**Status**: Draft

## Clarifications

### Session 2026-05-21

- Q: Como o orquestrador gera o resumo executivo de briefing/constitution na onda 1? → A: Heuristica extractiva — algoritmo deterministico que extrai todos os `## H2` e `### H3` headings + primeira linha de corpo nao-vazia de cada, dropando `### H3` ate caber em `resumo_max_chars`. Zero tokens, deterministico, totalmente testavel. (Resolve Q1 do bloco "Open Questions for /clarify".)
- Q: Qual o threshold de chars onde o cache cai em `passthrough`? → A: Fixo em **3000 chars** como default conservador (break-even entre overhead de geracao e ganho de re-leitura), com override opcional via `config.cache.passthrough_threshold_chars` no `state.json`. Threshold dinamico baseado em ondas esperadas foi descartado por exigir heuristica frangil. (Resolve Q2.)
- Q: Quando ambos existem (raiz `docs/constitution.md` + feature-delta `docs/specs/<feat>/constitution.md`), como o cache trata? → A: Cachear **apenas a "constitution ativa"** — resolvida via `pipeline.sh constitution-conflict` (primitiva ja existente). Para projeto sem feature-delta, cache aponta para a raiz; para projeto com feature-delta, cache aponta para a feature-delta. UM campo unico `constitution_cache` em `state.json` (com `source_path` indicando qual foi cacheada). Constitution raiz nao referenciada pela feature corrente nao consome espaco no cache. (Resolve Q3.)
- Q: Em retomada de execucao (resume apos pausa), o cache deve ser sempre regenerado ou confiar no backup-de-onda quando hash bate? → A: **Confiar no backup quando hash bate**. Na retomada, le `state.json` (com cache) do backup-de-onda + valida sha256 contra arquivo source em disco. Hash igual = cache valido, prossegue. Hash diferente = trata como drift normal (regenera via politica FR-CACHE-009 ou escala para BloqueioHumano se MAJOR via FR-CACHE-010). Reusa logica de `feature-00c-preflight.sh` ja existente. Flag opcional `--regenerate-cache` em /agente-00c-resume foi descartada por adicionar caminho duplicado de codigo sem ganho real (drift detection ja cobre o caso de cache stale). (Resolve Q4.)
- Q: Como o relatorio mede "tokens economizados"? → A: **Heuristica `(source_chars - resumo_chars) * tokens_per_char_ratio`** por hit. Ratio configuravel via `config.cache.tokens_per_char_ratio` no `state.json` (default 0.25 = chars/4 para pt-br; override para 0.33 = chars/3 em projetos majoritariamente em ingles). Zero dependencias externas, deterministico, mensuravel em tests offline. Precisao boa o suficiente para validar SC-001 (alvo >=70% economia em piloto T4.2). Plug-in via API Anthropic foi descartado por exigir API key em runtime POSIX puro e falhar offline. (Resolve Q5.)

---

> **Contexto**: o orquestrador agente-00c (e sua variante feature-00c)
> executa a pipeline SDD em multiplas ondas (waves). Cada onda e uma
> invocacao fresca do Claude Code, com cold-start de contexto. As
> skills do pipeline (`specify`, `clarify`, `plan`, `execute-task`)
> leem `briefing.md` e `docs/constitution.md` em disco completos a
> cada invocacao. Em pipelines longas (10+ ondas), isso representa
> overhead estimado de **5-10k tokens por onda** (50-100k tokens por
> execucao completa) somente para re-carregar artefatos foundational
> que mudam raramente.
>
> Esta feature introduz um cache opcional de artefatos foundational
> em `state.json`, com hash-validation TOCTOU-safe para invalidacao
> automatica. O cache e populado na onda 1 (resumo executivo de
> briefing + constitution gerado pelo orquestrador) e consultado
> pelas skills nas ondas N>1 quando rodando dentro do agente-00c.
> Comportamento standalone das skills (invocacao manual fora do
> orquestrador) e preservado integralmente.

---

## User Scenarios & Testing

### User Story 1 — Reducao mensuravel de tokens em pipelines longos (Priority: P1)

Joao roda `/agente-00c "<descricao de POC>"` em um projeto de medio
porte. A execucao atravessa 10 ondas (briefing → constitution →
specify → clarify → plan → checklist → create-tasks → execute-task
× N tasks → review-task → review-features). A partir da onda 2,
sempre que uma skill do pipeline precisa do conteudo de
`briefing.md` ou `docs/constitution.md`, em vez de ler o arquivo
completo (5-15k tokens cada), consulta o resumo executivo cacheado
em `state.json` (1-2k tokens cada). Ao final da execucao, o
relatorio inclui metrica `tokens_economizados_por_cache` mostrando
o ganho real comparado a baseline historica.

**Why this priority**: este e o produto da feature. Sem reducao
mensuravel de tokens, a feature nao tem razao de existir. P1 garante
end-to-end: cache populado, consumido, e medicao registrada.

**Independent Test**: rodar `/agente-00c` em projeto pequeno (3-5
ondas) e em projeto medio (10+ ondas); comparar `state.json.metricas.
tokens_cache_hits` e `state.json.metricas.tokens_economizados_por_cache`
contra baseline pre-feature (capturada em research.md de `/plan`).
Esperado: economia >= 70% do conteudo de briefing+constitution em
ondas N>1.

**Acceptance Scenarios**:

1. **Given** uma execucao do agente-00c com briefing+constitution
   pre-existentes e cache populado na onda 1, **When** uma skill do
   pipeline na onda 2 (ou posterior) precisa do conteudo de
   `briefing.md`, **Then** a skill consulta o resumo cacheado em
   `state.json.briefing_cache.resumo` em vez de ler o arquivo
   completo em disco, e a metrica `tokens_cache_hits` incrementa.
2. **Given** uma execucao concluida com cache ativo, **When** Joao
   abre o relatorio final, **Then** encontra a secao
   `### Cache de Artefatos` com: tamanho original vs resumo
   (chars + tokens estimados), numero de hits por skill,
   numero de invalidacoes detectadas, e economia liquida em
   tokens.
3. **Given** uma execucao em projeto pequeno onde briefing tem
   <3k chars, **When** o orquestrador avalia custo-beneficio na
   onda 1, **Then** marca `briefing_cache.estrategia = "passthrough"`
   (cache desabilitado para esse artefato; arquivo eh pequeno o
   bastante para nao justificar resumo), e skills leem direto do
   disco como hoje. Decisao auditavel registrada em
   `state.json.decisoes[]`.

---

### User Story 2 — Standalone behavior das skills preservado (Priority: P1)

Maria invoca a skill `plan` manualmente via `/plan <descricao>` em
um projeto que NAO tem agente-00c rodando. A skill detecta ausencia
de `state.json` (ou ausencia de `briefing_cache`/`constitution_cache`)
e cai no comportamento atual: le `briefing.md` e
`docs/constitution.md` diretamente do disco. Maria nao percebe
diferenca operacional alguma — a skill funciona identicamente ao
pre-feature.

**Why this priority**: as skills SDD sao user-facing e usadas tanto
standalone quanto dentro do orquestrador. Quebrar o caminho
standalone em nome da otimizacao orquestrada eh inaceitavel — viola
o principio de menor surpresa e quebra docs publicas que ensinam
uso manual. P1 = mesma prioridade do ganho, porque sem essa
garantia o ganho vem com regressao.

**Independent Test**: invocar `/plan`, `/specify`, `/clarify`,
`/execute-task` em um projeto sem `state.json` (ou com state.json
sem campos de cache); validar que cada skill produz o mesmo output
que produziria pre-feature, e que ler os arquivos foundational do
disco continua sendo o comportamento default.

**Acceptance Scenarios**:

1. **Given** projeto SEM `.claude/agente-00c-state/state.json`,
   **When** usuario invoca `/plan <feature>`, **Then** a skill le
   `docs/constitution.md` direto do disco, gera plan.md, e nao
   tenta acessar campos de cache.
2. **Given** projeto COM `state.json` mas sem campos
   `briefing_cache`/`constitution_cache` (execucao legada
   pre-feature), **When** usuario invoca uma skill afetada, **Then**
   a skill detecta ausencia dos campos e cai no fallback de leitura
   direta, sem erro.
3. **Given** invocacao de skill via tool `Skill` dentro de teste
   automatizado, **When** o teste roda em ambiente sem agente-00c,
   **Then** o teste passa identicamente ao baseline pre-feature.

---

### User Story 3 — Invalidacao automatica via hash mismatch (Priority: P2)

Durante uma execucao do agente-00c que dura varias horas, Joao
edita `docs/constitution.md` em outra janela (corrige um typo num
principio). Na proxima onda, antes de qualquer skill consultar o
cache, o orquestrador (ou a primeira skill que tenta consumir o
cache) detecta que o `sha256` registrado em
`state.json.constitution_cache.source_sha256` nao bate com o hash
do arquivo em disco. O cache eh invalidado, o orquestrador regenera
o resumo a partir do arquivo atual, atualiza o sha256, registra uma
`Decisao` auditavel descrevendo o evento, e a pipeline prossegue
sem perda de informacao.

**Why this priority**: drift entre cache e source-of-truth eh o
modo de falha classico de qualquer cache. Sem deteccao automatica,
decisoes da pipeline ficariam baseadas em conteudo obsoleto — o que
violaria o Principio I (Auditabilidade Total) silenciosamente. P2
porque eh defensivo, nao produtivo — sem ele a feature ainda funciona
no caso default (sem edicao concorrente), mas com risco residual
importante.

**Independent Test**: rodar uma execucao do agente-00c ate a onda 3
ou maior; editar `docs/constitution.md` (alterar uma linha do corpo
de um principio); aguardar proxima onda; verificar logs/relatorio
para confirmar que a invalidacao foi detectada, registrada como
Decisao, e cache regenerado.

**Acceptance Scenarios**:

1. **Given** cache populado e arquivo `docs/constitution.md`
   modificado em disco apos a populacao, **When** o orquestrador
   inicia a proxima onda, **Then** detecta hash mismatch (via
   primitiva nova `state-cache.sh check-drift`), invalida o cache,
   regenera o resumo, atualiza sha256, e registra uma `Decisao`
   informativa com 5 campos preenchidos (contexto: "drift de
   constitution detectado entre ondas N e N+1"; opcoes:
   ["regenerar-cache", "abortar-feature", "marcar-cache-stale"];
   escolha: "regenerar-cache"; justificativa: politica default
   FR-CACHE-009; agente: "agente-00c-orchestrator").
2. **Given** mismatch de hash detectado durante consumo do cache
   pela skill (TOCTOU possivel entre check-drift inicial e
   consumo posterior), **When** a skill detecta mismatch via
   double-check antes de usar o resumo, **Then** invoca leitura
   direta do disco como fallback (sem abortar a execucao) e
   registra metrica `cache_toctou_miss` para auditoria.
3. **Given** uma mudanca MAJOR em `docs/constitution.md` (numero
   de principios alterado, ou rodape `**Version**` bumped no
   primeiro digito), **When** o orquestrador detecta o drift,
   **Then** alem de regenerar cache, emite um `BloqueioHumano`
   obrigatorio com pergunta "constitution evoluiu MAJOR durante
   execucao — re-validar decisoes anteriores ou abortar?",
   espelhando o tratamento ja existente para drift em retomadas
   (FR-PRE-004 do feature-00c).

---

### User Story 4 — Filtro de secrets aplicado ao conteudo cacheado (Priority: P2)

A constitution de um projeto pode conter texto que mencione tokens
de exemplo (`AKIA[...]`), URLs com credenciais embutidas, ou
fragmentos sensitivos em exemplos. Antes de gravar o resumo de
briefing/constitution em `state.json`, o filtro de secrets
(`secrets-filter.sh scrub`) eh aplicado ao texto — exatamente como
ja eh aplicado a backups por onda (FR-029 §extensao). Conteudo
sensitivo eh redacted antes da gravacao; o source-of-truth (arquivo
em disco) permanece intocado.

**Why this priority**: o `state.json` eh commitado localmente (via
`state-ondas.sh git-commit`) e backupeado a cada onda. Vazar
secrets via cache seria um regressao de seguranca. P2 porque eh
defesa em profundidade — o filtro ja existe no toolkit, so precisa
ser estendido ao novo campo.

**Independent Test**: criar `docs/constitution.md` contendo um token
de exemplo (`AKIA0000000000000000`); rodar agente-00c; verificar
que `state.json.constitution_cache.resumo` nao contem o token
literal (foi substituido por `[REDACTED-AWS-KEY]` ou equivalente).

**Acceptance Scenarios**:

1. **Given** `briefing.md` ou `docs/constitution.md` contendo
   patterns reconhecidos como secrets (regex de
   `secrets-filter.sh`), **When** o orquestrador gera o resumo
   cacheado, **Then** aplica `secrets-filter.sh scrub` ao texto
   ANTES de gravar em `state.json.briefing_cache.resumo` ou
   `state.json.constitution_cache.resumo`.
2. **Given** cache populado com conteudo filtrado, **When** uma
   skill consome o resumo, **Then** recebe a versao filtrada (com
   redactions visiveis); decisoes baseadas em segredos especificos
   ficam impossiveis (esperado — segredos nao deveriam estar em
   documentos de governanca).
3. **Given** uma execucao concluida, **When** Joao audita o
   `state.json`, **Then** confirma que nenhum campo do cache
   contem patterns que `secrets-filter.sh check` reconheceria.

---

### Edge Cases

- **Briefing/constitution ausentes no projeto-alvo**: o cache fica
  marcado como `desabilitado` (nao tenta gerar resumo de algo que
  nao existe). Skills caem no fallback default (que tambem falha
  graciosamente quando os arquivos faltam — comportamento atual).
- **Arquivos foundational gigantes (>50k chars)**: o orquestrador
  pode falhar em produzir um resumo util em uma so onda. Politica
  inicial: `briefing_cache.estrategia = "passthrough"` para arquivos
  acima de threshold configuravel (default 30k chars); skills caem
  no fallback de leitura direta. Decisao auditavel registrada
  explicando a estrategia escolhida.
- **Resumo gerado for maior que o arquivo original**: bug de
  qualidade no gerador — registrar como Decisao + sugestao + cair
  em `passthrough`.
- **state.json sem schema bumpado**: validacao em
  `state-validate.sh` detecta schema_version desalinhada e bloqueia
  a execucao com diagnostico (sem auto-migracao silenciosa).
- **Cache populado, mas arquivo source deletado**: drift maximo —
  trata como `BloqueioHumano` obrigatorio ("arquivo source
  desaparecido entre ondas — abortar ou continuar com cache
  stale?").
- **Race entre invalidacao automatica e consumo em paralelo**: o
  cache eh lido sob o lock ja existente (`state-lock.sh acquire`),
  garantindo serializacao por onda. Skills que rodam DENTRO de uma
  onda compartilham snapshot do cache lido no inicio da onda.
- **Filtro de secrets renderiza resumo inutil**: se >50% do conteudo
  cacheado foi redacted, registrar Decisao + cair em `passthrough`
  para esse artefato (skill le direto do disco, onde filtro de
  secrets NAO eh aplicado — mas leitura direta nao persiste em
  state.json, entao seguranca eh preservada).
- **Execucao retomada (resume) com cache do disco diferente do
  cache em backup**: a primitiva `feature-00c-preflight.sh` ja
  detecta isso para briefing/constitution diretamente — estender
  para cache opcional, com o mesmo tratamento (MAJOR drift =
  bloqueio compulsorio; MINOR/PATCH = aviso).
- **Skill consome cache mas Decisao referencia versao errada**:
  campo `constitution.version` registrado em FR-PRE-004 do
  feature-00c continua sendo o source-of-truth para auditoria;
  cache eh apenas otimizacao de leitura, nao substitui o
  registro de versao consumida.

---

## Requirements

### Functional Requirements

**Estrutura do cache em state.json**

- **FR-CACHE-001**: `state.json` MUST aceitar dois novos campos
  top-level opcionais: `briefing_cache` e `constitution_cache`. A
  ausencia dos campos eh estado valido (execucoes legadas e skills
  standalone continuam funcionando).
- **FR-CACHE-002**: Cada campo de cache MUST conter, quando
  presente, no minimo:
  - `source_path`: caminho absoluto do arquivo source.
  - `source_sha256`: hash do conteudo no momento da populacao.
  - `source_chars`: tamanho do conteudo original em chars.
  - `resumo`: texto do resumo executivo (apos filtro de secrets).
  - `resumo_chars`: tamanho do resumo em chars.
  - `estrategia`: enum `"resumo"`, `"passthrough"`, `"desabilitado"`.
  - `gerado_em`: ISO-8601 timestamp.
  - `gerado_na_onda`: integer (numero da onda que gerou/atualizou).
- **FR-CACHE-003**: Schema_version do `state.json` MUST ser
  bumpada (MINOR) com fallback graceful: state.json legado sem
  os novos campos eh upgrade-compatible (campos opcionais).
  Migracao automatica explicita NAO eh necessaria — cache eh
  populado na proxima onda 1 (ou primeira onda que invocar
  `state-cache.sh ensure`).

**Populacao e atualizacao do cache**

- **FR-CACHE-004**: Sistema MUST popular o cache no momento em que
  briefing/constitution sao validados pela primeira vez na pipeline
  (etapa `briefing` para `briefing_cache`; etapa `constitution`
  para `constitution_cache`). Para `feature-00c`, populacao ocorre
  durante FR-PRE-004 do feature-00c (validacao + registro de hashes).
- **FR-CACHE-005**: A geracao do resumo MUST usar **heuristica
  extractiva deterministica** (resolvido em clarify 2026-05-21):
  1. Extrair todos os headings `## H2` e `### H3` do arquivo source.
  2. Para cada heading, extrair a primeira linha de corpo nao-vazia
     imediatamente abaixo dele.
  3. Concatenar como markdown valido preservando hierarquia
     (`##` antes de `###`).
  4. Se output excede `resumo_max_chars` (default 2000), dropar
     `### H3` em ordem inversa (do fim para o comeco) ate caber.
  5. Mesma entrada de bytes => mesma saida de bytes (deterministico).

  Sem chamada a LLM. Sem dependencia de prompt-cache. Plug-in
  alternativo (LLM-summarizer) avaliado se SC-001 falhar em piloto
  real (T4.2 do tasks.md).
- **FR-CACHE-006**: O resumo gerado MUST ser submetido a
  `secrets-filter.sh scrub` ANTES de ser persistido em
  `state.json`. O resultado filtrado eh o que vai para o campo
  `resumo`.
- **FR-CACHE-007**: Sistema MUST avaliar custo-beneficio na
  populacao: se `source_chars < threshold` (default 3000), marcar
  `estrategia = "passthrough"` e nao gerar resumo (cache desabilitado
  para esse artefato; skills leem direto do disco). Threshold
  configuravel via campo opcional no state.json
  (`config.cache.passthrough_threshold_chars`, default 3000).

**Consumo do cache**

- **FR-CACHE-008**: Cada skill afetada (`specify`, `clarify`,
  `plan`, `execute-task`, e quaisquer outras que leiam
  briefing/constitution) MUST adotar o seguinte protocolo de
  leitura:
  1. Detectar se esta rodando dentro do agente-00c (presenca de
     `state.json` no `.claude/agente-00c-state/` ou variant) E se
     o cache aplicavel esta populado com `estrategia = "resumo"`.
  2. Em caso positivo: chamar `state-cache.sh get-resumo --artifact
     <briefing|constitution>` para obter o resumo. Antes de usar,
     fazer double-check de drift (`state-cache.sh check-drift
     --artifact <name>`) — TOCTOU-safe.
  3. Em caso negativo OU drift detectado: ler o arquivo source
     direto do disco (comportamento atual).
- **FR-CACHE-009**: Politica default de invalidacao: hash mismatch
  detectado durante consumo OU entre ondas DEVE invalidar e
  regenerar automaticamente (sem bloqueio humano), exceto quando
  drift eh classificado como MAJOR (FR-CACHE-010). Toda invalidacao
  automatica registra `Decisao` informativa.
- **FR-CACHE-010**: Drift MAJOR (mudanca do primeiro digito de
  `constitution.version`, ou mudanca de >50% nos chars do source
  entre ondas) MUST escalar para `BloqueioHumano` obrigatorio
  ANTES de qualquer skill consumir o cache. Pergunta padrao:
  "<arquivo> evoluiu MAJOR durante execucao — re-validar decisoes
  anteriores ou abortar?".

**Auditabilidade e telemetria**

- **FR-CACHE-011**: Toda invalidacao de cache MUST gerar `Decisao`
  com 5 campos preenchidos (contexto, opcoes, escolha,
  justificativa, agente), registrada via `state-decisions.sh
  register`. Categoria sugerida: `cache-invalidacao`.
- **FR-CACHE-012**: `state.json` MUST conter contadores acumulados
  em `metricas.cache`:
  - `tokens_cache_hits`: numero de invocacoes que consumiram
    cache em vez de disco.
  - `tokens_cache_misses_drift`: invocacoes que detectaram drift
    e regeneraram.
  - `tokens_cache_misses_disabled`: invocacoes que cairam em
    fallback porque cache estava `desabilitado` ou `passthrough`.
  - `tokens_economizados_estimados`: soma de `source_chars -
    resumo_chars` por hit, convertida para tokens (chars / 4 para
    portugues, chars / 3 para ingles — heuristica configuravel).
- **FR-CACHE-013**: Relatorio final do agente-00c (`report.sh
  generate`) MUST incluir secao nova `### Cache de Artefatos`
  reportando as 4 metricas + breakdown por artefato + listagem
  das invalidacoes detectadas.

**Compatibilidade com skills standalone**

- **FR-CACHE-014**: Cada skill afetada MUST permanecer funcional
  quando invocada FORA do contexto agente-00c (sem state.json
  acessivel). Testes de regressao MUST cobrir invocacao standalone.
- **FR-CACHE-015**: A nova primitiva `state-cache.sh` MUST
  retornar exit-codes distintos para os casos:
  - `0`: cache hit; resumo retornado via stdout.
  - `1`: cache miss (campo ausente, estrategia != "resumo", ou
    drift detectado); skill DEVE cair em leitura direta.
  - `2`: erro fatal (state.json corrompido, lock indisponivel); skill
    DEVE abortar com diagnostico — NAO assumir fallback silencioso.

**Pre-flight e seguranca**

- **FR-CACHE-016**: A primitiva `state-cache.sh` MUST ser
  invocavel SOMENTE quando o `state-lock.sh` esta acquired (mesmo
  contrato das outras primitivas de estado). Tentativa de invocar
  sem lock = exit 2.
- **FR-CACHE-017**: `state-validate.sh` MUST validar invariantes
  do cache quando os campos estao presentes:
  - `source_sha256` eh hex de 64 chars.
  - `estrategia` esta no enum permitido.
  - `resumo_chars <= source_chars` (resumo nunca pode ser maior
    que original).
  - `gerado_em` eh ISO-8601 valido.
  - `gerado_na_onda` >= 1 e <= numero da onda corrente.

---

## Constitutional Alignment

Verificacao contra os 5 principios MUST da constitution
(`docs/constitution.md`):

| Principio | Como esta feature alinha |
|-----------|--------------------------|
| **I. Auditabilidade Total** | Toda invalidacao de cache gera `Decisao` com 5 campos. Metricas de cache em `metricas.cache`. Secao dedicada no relatorio final. |
| **II. Pause-or-Decide** | Drift MAJOR escala para `BloqueioHumano`; outros tipos de drift sao auto-resolvidos via politica default explicita (FR-CACHE-009). |
| **III. Idempotencia de Retomada** | Cache pode ser reconstruido a qualquer momento do source. Source eh canonico; cache eh derivado. Pre-flight em retomada detecta drift entre cache+backup vs disco. |
| **IV. Autonomia Limitada com Aborto** | Cache nao introduz nova classe de loop — invalidacoes contam para metrica de saude mas nao para ciclos consumidos. |
| **V. Blast Radius Confinado** | Cache vive em `state.json` (dentro de `.claude/agente-00c-state/` do projeto-alvo). Filtro de secrets aplicado antes de gravar. Source files (`briefing.md`, `constitution.md`) sao read-only para esta feature. |

---

## Success Criteria

- **SC-001**: Em pipeline de 10 ondas com briefing+constitution
  totalizando >= 10k chars combinados, o overhead total de
  re-leitura de artefatos foundational fica >= 70% MENOR que
  baseline pre-feature. Medido via `metricas.cache.
  tokens_economizados_estimados` no relatorio final.
- **SC-002**: Skills standalone (invocadas fora do agente-00c)
  produzem output identico ao baseline pre-feature em suite de
  regressao com >= 5 fixtures conhecidas (1 por skill afetada).
  Identico = diff = 0 em arquivos gerados.
- **SC-003**: Drift detectado entre ondas (briefing ou
  constitution modificados em disco) eh detectado em 100% dos
  casos, com Decisao auditavel registrada, em <= 100ms de overhead
  por check (medido em test fixture).
- **SC-004**: Zero secrets vazados via cache em suite de teste com
  briefing/constitution contendo patterns sensitivos plantados.
- **SC-005**: Nenhuma regressao em `./tests/run.sh` apos
  implementacao. Novos testes adicionados: >= 15 cenarios cobrindo
  cache-hit, cache-miss-drift, cache-disabled-threshold,
  toctou-safe-double-check, secrets-filter-applied,
  standalone-skill-fallback, schema-validation.

---

## Out of Scope

- **Cache de outros artefatos SDD** (spec.md, plan.md, tasks.md):
  estes mudam com mais frequencia entre ondas e ja sao consumidos
  por skills especificas com leitura full justificavel. Avaliacao
  futura em feature separada.
- **Cache compartilhado entre execucoes** (cache global em
  `~/.claude/cache/`): cada execucao mantem cache proprio em seu
  state.json. Compartilhamento cross-execucao introduz invalidacao
  cross-process complexa, fora de escopo.
- **Cache distribuido / multi-maquina**: agente-00c roda em uma so
  maquina por execucao. Sem necessidade de coordinacao distribuida.
- **Migracao automatica de state.json legado**: state.json sem
  campos de cache eh upgrade-compatible (cache fica vazio,
  populado na proxima onda). Sem migrador.
- **Cache de prompts/responses do LLM**: o prompt-cache do
  Anthropic API ja cobre isso em outra camada (system prompt,
  tools). Esta feature otimiza apenas conteudo de arquivos de
  projeto.
- **Configuracao por skill da estrategia de cache**: politica
  global (definida no orquestrador) eh suficiente para v1.
  Customizacao por-skill avaliada se demanda surgir.

---

## Dependencies

**Pre-requisitos internos do toolkit**:
- `agente-00c-runtime` skill (state-rw.sh, state-lock.sh,
  state-decisions.sh, state-validate.sh, secrets-filter.sh,
  state-ondas.sh) — sera estendida com `state-cache.sh`.
- Schema `state.json` versao corrente (a ser bumped MINOR).
- Pipeline SDD existente (skills: specify, clarify, plan,
  execute-task) — sera modificada para protocolo de leitura
  FR-CACHE-008.

**Pre-requisitos externos**:
- Nenhuma dependencia nova de runtime (continua POSIX shell +
  jq + sha256sum).

**Features paralelas**:
- `feature-00c` (PR #6 merged) — cache aplica automaticamente
  quando `agente-00c-feature-orchestrator` invoca skills
  afetadas (mesma primitiva `state-cache.sh`, mesmo state.json
  com escopo per-short-name).

---

## Validation Plan

1. **Spec review** (esta fase): garantir cobertura de cenarios
   end-to-end, edge cases, e alinhamento constitucional.
2. **Clarify** (proxima): resolver `[NEEDS CLARIFICATION]`
   gerados, especialmente em torno de:
   - Threshold default de `passthrough` (3000 chars eh defensavel?)
   - Politica de geracao de resumo (LLM in-session vs heuristica
     extractiva)
   - Como medir "tokens economizados" sem instrumentacao do LLM
     (estimativa por chars/4 eh aceitavel?)
3. **Plan**: arquitetura detalhada, contracts da nova primitiva
   `state-cache.sh`, modificacoes em cada skill afetada,
   schema_version bump strategy, plano de migracao.
4. **Checklist**: quality gate dos requisitos por dominio
   (performance, security, compatibility).
5. **Tasks**: decomposicao em fases com criticidade
   ([C]/[A]/[M]).
6. **Execute**: implementacao seguindo SDD pipeline padrao.

---

## Open Questions for /clarify

_(todas resolvidas em Session 2026-05-21 — ver bloco `## Clarifications`
no topo deste arquivo. Resumo das decisoes:)_

- **Q1** → Heuristica extractiva deterministica (sem LLM call).
- **Q2** → Threshold fixo de 3000 chars, override opcional.
- **Q3** → Cachear apenas a "constitution ativa" (1 campo).
- **Q4** → Confiar no backup-de-onda quando hash bate (drift detection cobre stale).
- **Q5** → Heuristica `chars * tokens_per_char_ratio` (default 0.25 pt-br).
