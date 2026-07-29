# Changelog

Todas as mudanças relevantes deste projeto são documentadas aqui.

O formato segue [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/) e
este projeto adere a [Semantic Versioning](https://semver.org/lang/pt-BR/).

## [5.34.0] - 2026-07-29

Pre-flight determinístico de telemetria: a pergunta "ESTA sessão vai ser
medida?" deixa de depender de diagnóstico manual e vira subcomando do
runtime, invocado pelos commands 00c antes da onda-001.

### Added

- **`otel-usage.sh preflight [--endpoint URL]`.** Decide deterministicamente
  se a telemetria OTel da sessão corrente vai ser medida, sem nunca
  bloquear a pipeline: `status=ok` quando o dono da porta do endpoint é
  ancestral do processo corrente (i.e. o exporter pertence a ESTA sessão —
  dono via `lsof`, ancestralidade via walk de `ps -o ppid=`);
  `status=port-conflict` (exit 3) com `owner_pid` e `owner_cwd` quando a
  porta pertence a OUTRO processo — o modo de falha silencioso da 5.33.4,
  agora detectável antes da onda-001; `status=exporter-down` (exit 4)
  quando o opt-in está ligado mas nada responde; `status=disabled` (opt-in
  ausente) e `status=unverified` (endpoint não-local/`file://` ou posse
  indeterminável com scrape respondendo — nunca acusa conflito sem
  evidência) saem com exit 0. Aviso de alta visibilidade em stderr nos
  exits 3/4. +6 cenários em `test_otel-usage.sh` com `lsof` stubado no
  PATH (dono ancestral = `$$` do teste; dono estranho = PID 1).

### Changed

- **Commands `/agente-00c` e `/feature-00c`**: o diagnóstico de coleta
  (passo 2.bis / 8) agora roda `otel-usage.sh preflight` junto do
  `guard-hooks-status.sh check` e instrui REPASSAR ao operador qualquer
  `port-conflict`/`exporter-down` antes de seguir — a execução sairia
  inteira com `otel_usage` null. Deliberadamente FORA do
  `state-ondas.sh start`: rodar o preflight a cada onda poluiria stderr de
  toda a suite em ambiente com telemetria ligada e duplicaria scrapes; o
  ponto determinístico certo é o pre-flight único do command pai.
- **READMEs + tabela de helpers do orquestrador**: documentam o subcomando
  novo como alternativa ao diagnóstico manual via `lsof`.

## [5.33.4] - 2026-07-29

Documentação do modo de falha silencioso da telemetria OTel com múltiplos
processos do Claude Code abertos — diagnóstico de caso real em que uma
execução inteira de 16 ondas não mediu consumo nenhum.

### Fixed

- **Disputa da porta fixa 9464 do exporter OTel documentada em todas as
  frentes.** Só UM processo do Claude Code consegue o bind da porta do
  exporter Prometheus — o primeiro lançado ganha; qualquer outro processo
  simultâneo (outra aba de terminal, outro projeto) falha o bind em
  silêncio: as métricas dele não são expostas em lugar nenhum, os snapshots
  por onda scrapeiam as sessões velhas do processo vencedor e o guard do
  delta descarta o resultado corretamente (Princípio VI) — `otel_usage`
  fica `null` em TODAS as ondas da execução e o painel não mostra custo.
  Caso real (2026-07-29): um `claude -c` de dois dias de outro projeto
  segurava a porta e a execução de 16 ondas da feature webhooks não mediu
  nada. Mitigação documentada: função-launcher no shell rc que sorteia
  porta livre por processo (bind na porta `0` → kernel escolhe) e exporta
  `OTEL_EXPORTER_PROMETHEUS_PORT` + `CSTK_OTEL_ENDPOINT` correspondentes —
  zero configuração por sessão, cada processo mede isolado, e o guard
  "exatamente uma sessão cresceu" passa a ver só as sessões daquele
  processo (descartes por ambiguidade praticamente desaparecem). Snippet
  completo + diagnóstico via `lsof` nos READMEs (seção "Real per-wave
  cost" / "Custo real por onda"), bloco "DISPUTA DA PORTA FIXA" no header
  do `otel-usage.sh`, e aviso no pre-flight de telemetria dos commands
  `/agente-00c` e `/feature-00c`.

## [5.33.3] - 2026-07-29

Guard de preflight para o único ambiente onde `cstk serve` quebrava sempre:
Windows + WSL2 sem Node.js instalado dentro da distro.

### Fixed

- **`serve.sh`: bloqueia o npm do WINDOWS vazando via interop de PATH do
  WSL.** Sem Node.js na distro, `command -v npm` resolve para o binário do
  Windows (`/mnt/c/Program Files/nodejs/npm` — denunciado no caso real pelo
  cache em `C:\Users\...\npm-cache`); esse npm enxerga a árvore Linux pelo
  caminho UNC `\\wsl.localhost\<distro>\...`, onde os symlinks de
  workspaces falham (`EISDIR` fatal em `node_modules/@cstk-panel/*`) e o
  cleanup falha (`EPERM rmdir`) — `npm install` morria no meio com
  stacktrace críptico. Novo `_serve_check_npm_interop` (WSL detectado via
  `WSL_DISTRO_NAME` ou `/proc/version` contendo "microsoft"; binário
  Windows por `/mnt/*`, `*.exe` ou `*.cmd`) aborta ANTES de qualquer
  download com orientação acionável: instalar Node.js DENTRO da distro
  (apt/nvm) ou usar `cstk serve --docker`, que nunca exige npm no host.
  Git Bash/MSYS e ambientes não-WSL seguem intactos (guard inerte fora do
  WSL). +5 cenários em `test_serve.sh` (bloqueio `/mnt/*` e `*.exe`,
  não-bloqueio do npm da distro, não-bloqueio fora do WSL, fluxo feliz
  completo sob WSL sem falso positivo).

## [5.33.2] - 2026-07-28

Ciclo de arquivamento do portfolio (9 features 100%) que inaugura o corpus
canonico `docs/specs/current/`, com dois fixes expostos pelo proprio ciclo.

### Fixed

- **`validate-sdd.sh`: secao `## Delta Requirements` fora da varredura de
  `duplicate-id`.** A regra 4 do contrato `delta-section-format.md`
  (living-specs) EXIGE que entradas ADDED repitam os `FR-NNN` da secao
  Functional Requirements da propria spec — a primeira spec com delta real
  (enforced-guards) falhava com 17 `duplicate-id` falsos. Cenario c05
  ajustado (o duplicado do teste agora vive FORA da secao delta) + nova
  regressao c05b com fixture real (spec arquivada com 17 FRs repetidos).
- **`model-routing.sh wave-select`: Decisao por onda grava a FASE da onda
  no `stage`** (`specify`|`plan`|...), nao mais a categoria
  `model-routing` — consumidores derivados (knowledge.db/painel) agrupam
  por `stage` como etapa SDD, o que eliminava a leitura correta (barra
  unica "model-ro" no painel). O discriminador de decisao de roteamento
  passa a ser exclusivamente o lead do contexto (FR-021), nunca o
  `stage`. `recall.sh --ingest` normaliza Decisoes legadas
  (`stage='model-routing'`) extraindo a fase do sufixo `(fase X)` do
  contexto — derivacao apenas na ingestao, `state.json` intacto (mesmo
  precedente do `etapa_corrente`); overrides do operador
  (`model-override:*`) seguem com `etapa=model-routing`.

### Changed

- **Portfolio de specs zerado e corpus canonico inaugurado.** Arquivadas
  com o fluxo `delta-gate` -> `delta-merge` -> `_archived/2026-07-28-*`:
  budget-resume-wallclock, openspec-hygiene, otel-model-breakdown,
  panel-docker, skill-converge, validate-docs-sdd-profile e
  wave-token-metrics (Skip explicito), enforced-guards e living-specs
  (delta REAL, 17 FRs verbatim cada). `docs/specs/current/` nasce com 8
  capabilities com proveniencia: bash-guard-enforcement, serve-integrity,
  trusted-release-hosts, guards-defense-in-depth, spec-delta-requirements,
  spec-corpus, delta-archive-gate, atomic-commit-staging. Backfill
  retroativo das features arquivadas antes da convencao foi DECLINADO em
  definitivo pelo operador (living-specs 6.4 / CHK038).

## [5.33.1] - 2026-07-28

Corrige o delta OTel por onda que fabricava consumo. Caso real: com a porta
9464 ocupada por um processo `claude -c` longevo, as 14 ondas da execucao
`dashboard-refactor` (cstk-panel) gravaram `otel_usage` bit-identico
(212.447.680 tokens / $88) — o "delta" era o acumulado congelado do
exporter, nao o consumo da onda. A onda-015 caiu no guard e ficou `null`
(comportamento correto que denunciou o resto).

### Fixed

- **`otel-usage.sh`: delta agora agrega por sessao.** Duas causas
  combinadas: (1) o parse descartava o `session_id` das linhas — o mesmo
  exporter pode expor MAIS de uma sessao, e o acumulado das sessoes
  congeladas entrava na soma; o guard antigo comparava so o header
  `# session_id` (primeira ocorrencia de cada arquivo) e passava com
  mistura; (2) a chave do join `(source, model, type)` colide entre linhas
  que o exporter separa por `agent_name`/`skill_name`/`effort` — o awk
  sobrescrevia a base (`s[k]=$4`) e imprimia cada duplicata do end contra
  essa base unica, transformando o "delta" em acumulado. O snapshot agora
  emite TSV de 5 colunas (`session_id` por linha) e o delta SOMA duplicatas
  nos dois lados, agrega por sessao e so aceita o resultado quando
  EXATAMENTE UMA sessao cresceu entre os snapshots — crescimento que, por
  construcao, ocorreu dentro da janela da onda.
- **Ausente nunca e zero fabricado (Principio VI), agora tambem para
  ambiguidade de sessao**: mais de uma sessao ativa no exporter, sessao do
  start ausente no end (processo dono da porta trocou) e snapshot em
  formato antigo (4 colunas) viram `null` com aviso em stderr — nunca
  chute. O `session_id` do OTel NAO e usado como identidade da sessao
  corrente (label ja observado apontando para outra sessao/projeto); a
  atribuicao e por deteccao de crescimento, sem match contra env.
- 5 cenarios novos em `tests/test_otel-usage.sh` (INV-6: soma de
  duplicatas; INV-7: isolamento por sessao, incluindo reproducao do caso
  real com sessao congelada de 212M tokens) e guard antigo renomeado para
  `scenario_delta_sessao_do_start_sumida_e_null`.

Nota de operacao: execucoes ja contaminadas nao se corrigem sozinhas —
anular `.waves[].otel_usage` das ondas afetadas no `state.json` (seguido de
`state-rw.sh sha256-update`) e rodar `cstk recall --ingest --state-dir
<dir>` corrige `waves`; linhas orfas em `wave_model_usage` exigem DELETE
manual, porque onda `null` nao regrava essa tabela por design (FR-004).

## [5.33.0] - 2026-07-28

Fecha a perda de dimensoes do OTel na ingestao: o `state.json` sempre teve o
consumo detalhado por **modelo** e por **fonte**, mas a `knowledge.db` so
guardava 5 escalares e descartava o resto.

O `otel-usage.sh delta` grava em `.waves[].otel_usage` um objeto completo —
`by_model` (custo/tokens por modelo) e `by_source` (input/output/cache_read/
cache_creation para `main` e `subagent`). O ingest projetava apenas
`otel_cost_usd`, `otel_cost_main_usd`, `otel_cost_subagent_usd`,
`otel_total_tokens` e `otel_subagent_tokens`. Consequencia pratica: era
impossivel responder "quanto desta execucao foi opus e quanto foi sonnet",
ou calcular cache-hit ratio, mesmo com o dado presente em disco.

### Added

- **`wave_model_usage`** (schema v12): tabela nova, grao **onda x modelo**,
  com `model`, `cost_usd` e `total_tokens`. O `model` e a string **BRUTA**
  do OTel, sem normalizacao — os valores reais incluem `claude-fable-5` (que
  nao tem alias no mapa fase->modelo) e `claude-opus-5[1m]` (variante de
  contexto 1M, com custo distinto); normalizar para `opus`/`sonnet`/`haiku`
  apagaria os dois.
- **8 colunas de breakdown por fonte em `waves`**:
  `otel_{main,subagent}_{input,output,cache_read,cache_creation}_tokens`.
  Antes, o breakdown do `main` sumia por completo e do `subagent` sobrava so
  o total.
- Contador `wave_model_usage` no sumario de `--ingest`/`--reindex`.

### Changed

- **`RECALL_SCHEMA_VERSION` 11 -> 12.** Migracao ADITIVA e idempotente, via
  guard `_as_wcols` no mesmo padrao do bloco v10->v11. Validada sobre uma
  `knowledge.db` real em v11 (4107 decisions / 913 waves / 67 executions):
  contagens pre-existentes intactas, segunda execucao sem duplicar nada.

  > **Requer cstk-panel >= 0.20.0.** O painel valida a versao do schema
  > contra uma allowlist; versoes anteriores rejeitam a base v12 com
  > `schema-mismatch`. Paliativo enquanto nao atualiza:
  > `CSTK_SCHEMA_VERSIONS=2,3,4,5,6,7,8,9,10,11,12`.

### Fixed

- **`scenario_end_otel_usage_null_sem_telemetria` nao isolava o ambiente.**
  O cenario nao setava `CSTK_OTEL_ENDPOINT` e caia no default
  (`localhost:9464`); numa maquina com `CLAUDE_CODE_ENABLE_TELEMETRY=1` e
  `OTEL_METRICS_EXPORTER=prometheus` ativos o snapshot funcionava,
  `otel_usage` nao ficava null e o teste falhava **sem defeito no codigo**.
  Passa a forcar uma porta fechada como "maquina sem telemetria"
  deterministica. O defeito estava mascarado no CI, que nao expoe o exporter.

### Notas

- **Ausencia de dado = NULL, jamais 0 fabricado.** Verificado em volume real:
  das 916 ondas da `knowledge.db`, apenas 7 receberam valor nas colunas
  novas; as outras 909 permaneceram NULL. O caso oposto tem teste dedicado
  com dado real (`cost_usd: 0` convivendo com `cache_creation: 4103` na mesma
  linha) — zero medido nao vira NULL.
- **`wave_model_usage` NAO alimenta `knowledge_fts`**: o label de modelo vem
  de fonte externa e nunca pode alcancar contexto de LLM via
  `cstk recall --context` (LLM01/ASI06).
- **`otel_session_id` foi deliberadamente deixado de fora.** Investigacao
  empirica mostrou que o label nao identifica a sessao que gerou o consumo —
  o mesmo `session_id` aparecia no endpoint, nesta execucao e numa execucao
  anterior de outro projeto. Indexa-lo propagaria atribuicao errada.

## [5.32.0] - 2026-07-27

Fecha o buraco da **retrospectiva proativa por marco**: o gatilho nunca era
confiavel e, quando rodava, o resultado nao chegava ao painel.

Diagnostico que originou o fix (dois projetos reais, causas diferentes):

- `gamedev-training` (66 ondas): as retros de 25 e 50 ondas **rodaram** e
  estao no `state.json` como Decisoes (`dec-102`, `dec-194`), com bloqueio
  humano respondido em cada marco. Mesmo assim o painel mostrava
  "Sem retros ainda" — a tabela `retros` da `knowledge.db` tinha **0 linhas
  no indice inteiro**, em todos os projetos, desde que foi criada.
- `mcp-project-scafold` (31 ondas): nenhuma Decisao de marco, nenhum
  `next_retrospective_milestone`. A retro simplesmente **nunca disparou**.

### Fixed

- **Retro executada nunca virava dado tipado (`type='retro'`).** O
  orquestrador registra a retrospectiva de marco como Decisao cujo `context`
  comeca com `Retrospectiva de marco`, mas `cstk recall --ingest` so lia
  `.retros[]` do `state.json` — chave que **nenhum script do toolkit jamais
  escreve** (`grep '\.retros'` em `global/` e `cli/`: zero writers). O
  resultado era uma tabela permanentemente vazia alimentando um painel que
  a consulta. O `--ingest` agora **projeta** essas Decisoes em `retros` +
  FTS, com `source_id = retro-<dec-id>` e `wave` = a onda real da Decisao.
  A projecao e **aditiva**: a Decisao original continua ingerida como
  `type='decision'`, trilha de auditoria intacta. Historico recuperavel com
  `cstk recall --reindex`. A fonte `.retros[]` continua funcionando e as
  duas coexistem.
- **Gatilho de marco era prosa, e falhava.** O hook "a cada 25 ondas" vivia
  so como instrucao em `agente-00c-orchestrator.md` (passo 10) e
  `agente-00c-feature-orchestrator.md`, dependendo de o orquestrador lembrar
  de calcular `waves.length % 25` — mesma classe de falha das guardas
  advisory que a feature `enforced-guards` fechou. Agora quem fecha a onda
  dispara: `state-ondas.sh end` registra a Decisao, abre o bloqueio LEVE
  (`sim-rodar-retro` | `nao-continuar`) e avanca
  `.next_retrospective_milestone`.

### Changed

- **Gatilho de marco e self-healing.** A condicao passou de
  `waves.length % 25 == 0` para `waves.length >= next_retrospective_milestone`
  (default 25). Um marco pulado numa onda terminada em bloqueio/aborto passa
  a disparar na proxima onda que avanca, em vez de se perder ate o proximo
  multiplo de 25 — exatamente o caso das 31 ondas sem marco.
- Motivos `bloqueio_humano`, `aborto` e `concluido` **nao** disparam o marco
  (dois bloqueios competindo confundem a resposta do operador; execucao
  encerrada nao tem o que fazer com a retro) e **nao consomem** a milestone.
- A milestone so avanca **depois** de Decisao E bloqueio gravados: falha
  parcial deixa o marco pendente para nova tentativa.
- Hook best-effort por contrato: qualquer falha (script irmao ausente,
  validacao de Principio I, I/O) vira aviso em stderr e **nunca** falha o
  `end`. Kill-switch por `CSTK_RETRO_MILESTONE_DISABLED=1`.
- Os dois orquestradores foram atualizados para **nao** registrar o marco na
  mao (duplicaria Decisao e abriria dois bloqueios) e passaram a documentar
  o contrato do prefixo `Retrospectiva de marco` no `context` da Decisao que
  consolida a retro — e esse prefixo que a projecao do `--ingest` consome.

Nenhuma mudanca de schema: `retros` ja existia desde a v1 da `knowledge.db`,
e o painel ja a consulta. Nenhuma alteracao necessaria no `cstk-panel`.

## [5.31.0] - 2026-07-26

Corrige os dois bugs que sobraram no `wave-usage-report.sh backfill` — a
reconstrução histórica do consumo por onda, que estava **inteiramente
inoperante**.

### Fixed

- **Backfill não cobria nenhuma onda** (`0/58` medido em gamedev-training).
  A atribuição era por **contenção** (`started_at <= ts < finished_at`)
  usando o timestamp do `tool_result` — mas a topologia real é o oposto: o
  command pai spawna o orquestrador, e é o orquestrador que abre e fecha a
  onda **por dentro** do spawn. Ou seja
  `spawn_start < started_at < finished_at < spawn_end`: o `tool_result`
  chega depois do fechamento, na lacuna entre ondas, e nunca casava.
  A atribuição agora tenta **enclausuramento** primeiro (o spawn envolve a
  onda) e cai na contenção como fallback — que continua valendo para spawns
  feitos de dentro de uma onda já aberta. O fix é **aditivo**, não
  substitutivo. Resultado no mesmo transcript: **62 de 65 spawns cobertos**.
- **`toolUseResult` string derrubava o backfill inteiro.** Nem todo tool
  result é objeto; vários devolvem string crua. `.agentId` sobre string
  aborta o `jq` com `Cannot index string with string`, matando o
  processamento do arquivo todo (observado em financial-support). Agora o
  tipo é checado antes de indexar, e uma linha string apenas é ignorada —
  os spawns válidos ao redor sobrevivem.
- Testes: 3 cenários de regressão em `tests/test_wave-usage-report.sh`
  (spawn que envolve a onda é atribuído; contenção continua valendo; linha
  com `toolUseResult` string não derruba os spawns seguintes).

## [5.30.0] - 2026-07-26

O custo real por onda **chega ao painel**. A v5.28.0 capturou o dado no
`state.json`; esta versão o indexa na `knowledge.db` e o expõe na UI.

### Added

- **knowledge.db schema v11**: 5 colunas aditivas em `waves` para o consumo
  medido pela telemetria OTel — `otel_cost_usd`, `otel_cost_main_usd`,
  `otel_cost_subagent_usd` (todas `REAL`), `otel_total_tokens` e
  `otel_subagent_tokens` (`INTEGER`). Migração v10→v11 idempotente, guardada
  por `PRAGMA` como as anteriores; ondas já indexadas ficam intactas com
  `NULL` nas colunas novas — **ausente, nunca zero**.
- **`recall_real_or_null`**: coerção para ponto flutuante. O custo em USD é
  fracionário (`0.098485`); `recall_int_or_null` o descartaria como
  não-numérico e gravaria `NULL`, perdendo silenciosamente a métrica.
- Testes: 4 cenários em `tests/cstk/test_recall.sh` — ingestão nas colunas,
  custo fracionário preservado, ausência vira `NULL`, e migração v10→v11
  idempotente com linha legada preservada.

### Changed

- **Ingestão** (`cli/lib/recall.sh`): `--ingest` e `--reindex` passam a ler
  `.waves[N].otel_usage`. Os tokens de subagente são somados dos quatro
  tipos (`input` + `output` + `cache_read` + `cache_creation`).

### Painel (repo cstk-panel, PR separado)

- `DEFAULT_SCHEMA_VERSIONS` aceita `11` — **sem isso o painel recusaria
  abrir a base migrada**.
- `hasOtelUsage()` + `getOtelUsage()`: sonda de capacidade e agregação. Base
  v10 ou anterior degrada para `null` em vez de erro "no such column".
- Tile "Tokens · subagentes" passa a **preferir a fonte OTel** quando
  presente (mais completa: cobre o consumo do próprio orquestrador), com
  `agentUsage` como fallback e rótulo de cobertura `N/M ondas medidas`.

## [5.29.0] - 2026-07-26

Os commands 00c passam a **pedir** a instalação dos hooks em vez de só
avisar que faltam — com o propósito de cada um e o custo em números.

### Changed

- **`/agente-00c` (passo 2.bis) e `/feature-00c` (pré-flight 8)**: o passo
  deixa de ser um aviso passivo e vira um **pedido explícito** ao operador,
  com três pontos obrigatórios:
  1. **O que instala e para que serve** — e por que nenhum dos três é
     redundante: `pretooluse-bash-guard.sh` é segurança (não substituível);
     `posttooluse-tool-call-tick.sh` é a **única** fonte de `tool_calls` (a
     telemetria OTel conta API requests e tokens, não tool calls);
     `posttooluse-agent-usage.sh` é a única fonte do detalhe **por spawn**
     (o total por onda hoje vem do OTel, com mais precisão).
  2. **O custo, com número medido** — não "tem um custo". Não há custo de
     token (são scripts shell locais); o custo é latência:
     `tool-call-tick` ~30 ms por tool call (matcher `*`, roda em todas —
     ~6 s numa onda de ~200 chamadas), `bash-guard` ~177 ms por chamada
     Bash, coleta OTel ~37 ms × 2 por onda.
  3. **Como ativar** — dois opt-ins independentes: `cstk hooks install`
     (hooks) e as duas variáveis de ambiente (custo/tokens reais por onda).
- **Regra de decisão explícita**: recusa ou silêncio **não bloqueiam** a
  pipeline, mas o que fica de fora é registrado sem eufemismo (guarda de
  Bash não enforced; `tool_calls` ausente, não "zero medido"). E o
  orquestrador **nunca instala sem consentimento** — `cstk hooks install`
  escreve em `<projeto-alvo>/.claude/settings.json`, que pode estar
  versionado no repo do operador.

## [5.28.0] - 2026-07-26

Custo real por onda, incluindo o consumo do próprio orquestrador — a fatia
que nenhuma métrica anterior conseguia capturar. Medido: **o subagente é
43–47% do gasto**, exatamente o que o painel mostrava como `—`.

### Added

- **`otel-usage.sh`** (novo helper do runtime 00c): consumo real de
  tokens/custo por onda a partir da telemetria **OpenTelemetry nativa do
  Claude Code**. Subcomandos `available` / `snapshot` / `delta`.
  - **Por que resolve o que o hook não resolvia**: `posttooluse-agent-usage.sh`
    lê o `tool_response` do spawn, mas o spawn do orquestrador **envolve** a
    onda — o `tool_result` chega depois do `end` (que já resetou o sidecar) e
    é destruído pelo `start` seguinte. Os contadores OTel são incrementados
    **a cada API request**, então o delta `start`→`end` é o consumo da onda
    independentemente de quando o spawn retorna.
  - Separa `main` / `subagent` / `auxiliary` pelo label `query_source`, com
    breakdown por modelo e por tipo de token (input/output/cacheRead/
    cacheCreation) e custo em USD.
  - **Opt-in por ambiente, sem segredo nenhum**: `CLAUDE_CODE_ENABLE_TELEMETRY=1`
    + `OTEL_METRICS_EXPORTER=prometheus`. **Não exige API key, Admin key nem
    organização** — funciona em plano de assinatura. O exporter escuta em
    `127.0.0.1:9464`; nada sai da máquina. Endpoint configurável via
    `CSTK_OTEL_ENDPOINT`.
  - **Privacidade**: os labels do exporter carregam `user_email`, `user_id`,
    `user_account_*` e `organization_id`. O snapshot extrai por allowlist
    (só `session_id`, `model`, `query_source`, `type`) e aborta se algum
    label de PII vazar — nada disso toca disco, state.json ou knowledge.db.
  - **Ausente ≠ zero** (Princípio VI): sem telemetria, snapshot faltando, ou
    `session_id` divergente entre os dois snapshots, o resultado é `null`,
    nunca um zero fabricado.
  - Overhead medido: 37 ms por snapshot, 2 por onda.
- **`.waves[N].otel_usage`**: `state-ondas.sh start`/`end` capturam os
  snapshots e gravam o delta no mesmo write atômico do fechamento da onda.
  No-op completo sem a telemetria ligada.
- Testes: `tests/test_otel-usage.sh` (17 cenários, fixtures no formato real
  do exporter com identificadores anonimizados) + 2 em `test_state-ondas.sh`.
  Suíte completa: 1889 cenários, 0 falhas.

### Changed

- **README** (`en` + `pt-BR`): seção "Real per-wave cost / Custo real por
  onda" com o opt-in e os números medidos.
- **`agente-00c-orchestrator.md`**: `otel-usage.sh` na tabela de helpers,
  marcado como automático (o orquestrador não precisa invocar).

### Nota sobre a Usage & Cost Admin API

Foi avaliada e **descartada** como fonte: exige Admin key
(`sk-ant-admin01-…`), é indisponível para contas individuais, e **não tem
dimensão de sessão** (agrupa por api_key/workspace/model). A Claude Code
Analytics API é por usuário/**dia**, com 1 h de atraso e sem tempo real. A
telemetria OTel entrega o que nenhuma das duas entrega: atribuição por
sessão e por `query_source`, em tempo real e local.

## [5.27.0] - 2026-07-26

Fecha a lacuna que a 5.26.0 deixou aberta: a detecção avisava que os hooks
00c não estavam ativos, mas o único caminho para provisioná-los duplicava o
catálogo inteiro dentro do repo-alvo. Agora há um caminho enxuto.

### Added

- **`cstk hooks install`** (novo subcomando): provisiona os três hooks do
  runtime 00c (`pretooluse-bash-guard.sh`,
  `posttooluse-tool-call-tick.sh`, `posttooluse-agent-usage.sh`) num
  projeto-alvo, tocando **apenas** `.claude/hooks/` e `.claude/settings.json`.
  Flags: `--project-path PATH` (default: diretório corrente),
  `--catalog DIR` (default: `$HOME/.claude`) e `--dry-run`.
  - **Motivação**: até 5.26.0 o único caminho documentado era
    `cstk install --scope project agente-00c-runtime`, que além dos hooks
    copia 1 skill + 6 commands + 7 agents para dentro do repo — 14 artefatos
    duplicados do catálogo global por projeto, com ruído no versionamento e
    superfície de drift. Como sem os hooks a guarda fail-closed de Bash fica
    inerte e `tool_calls`/`agent_usage` ficam zerados, o custo de ativação
    precisava cair.
  - **Nenhuma regra nova**: `hooks_main` delega integralmente a
    `apply_guard_hooks()` (`cli/lib/hooks.sh`), a mesma função usada por
    `install.sh` e `update.sh` — que segue sendo a fonte única da regra de
    provisionamento. Escopo de projeto por construção (FR-009c): apontar
    `--project-path` para `$HOME` é recusado com exit 1.
  - Testes: +9 cenários em `tests/cstk/test_hooks.sh` (incluindo idempotência
    e a asserção de que **não** cria `skills/`, `commands/` ou `agents/` no
    alvo) e +4 em `tests/cstk/test_cstk-main.sh` (wiring do dispatch).

### Changed

- **README** (`en` + `pt-BR`): nova seção "00c runtime hooks (`cstk hooks`)"
  explicando que os hooks só rodam quando copiados **e** registrados, e que
  sem eles a guarda de Bash é inerte.

## [5.26.0] - 2026-07-26

Triagem das sugestões acumuladas na `knowledge.db` — 7 correções validadas
contra o código antes de aceitas. A mais importante não é uma correção de
bug: os três hooks do runtime 00c **nunca chegaram a nenhum projeto-alvo**
desta máquina, o que deixou a guarda fail-closed de Bash inerte em toda
execução real e zerou as métricas de onda.

### Added

- **`guard-hooks-status.sh`** (agente-00c-runtime, novo helper READ-ONLY):
  responde se os três hooks 00c (`pretooluse-bash-guard.sh`,
  `posttooluse-tool-call-tick.sh`, `posttooluse-agent-usage.sh`) estão de
  fato ativos no projeto-alvo — presentes **e** registrados no
  `settings.json` (cada metade sozinha não basta: arquivo no lugar sem
  registro = hook que nunca roda). Dois subcomandos: `check` (TSV por hook +
  remediação em stderr; exit 1 se algum faltar) e `tick-mode` (`hook` |
  `manual`). Nunca copia hook nem edita `settings.json` — provisionar segue
  sendo trabalho exclusivo do `cstk install --scope project`, única fonte da
  regra. POSIX puro, sem jq.
  - **Motivação**: `apply_guard_hooks()` só roda com `--scope project` **e**
    `agente-00c-runtime` na seleção, mas o default de `cstk install`/`update`
    é `--scope global`, que pula o provisionamento por FR-009c. Como o
    `cstk install` roda no repo do cstk e não no alvo, não havia momento no
    fluxo em que o operador fosse avisado. Constatado em campo: projeto com
    35 ondas 00c executadas e zero hooks em `.claude/hooks/`.
- **`state-ondas.sh end --next-instruction TEXT`**: grava `.next_instruction`
  no **mesmo write atômico** do fechamento da onda. Antes exigia um
  `state-rw.sh set` separado e, como `end` também escreve no `state.json`,
  seguir a ordem literal `backup → hash → end` do prompt deixava backup e
  sha256 defasados.
- Testes: `tests/test_guard-hooks-status.sh` (20 cenários) + extensões em
  `test_commit-mode.sh` (+6), `test_state-ondas.sh` (+6) e
  `test_validate-sdd.sh` (+2). Suíte completa: 1857 cenários, 0 falhas.

### Changed

- **`/agente-00c` (passo 2.bis) e `/feature-00c` (pré-flight 8)** passam a
  chamar `guard-hooks-status.sh check` no init — advisory, exit 1 **não**
  aborta a execução. A guarda de Bash inativa é destacada como item grave; o
  resto é métrica.
- **Orquestradores** deixam de assumir que o hook de tick está ativo:
  consultam `guard-hooks-status.sh tick-mode` e só pulam o
  `state-ondas.sh tool-call-tick` manual quando a resposta é `hook`. O
  default `manual` impede a métrica de zerar em silêncio — a instrução
  anterior ("não ticke manualmente quando o hook está ativo") não tinha como
  verificar a condição e virava, na prática, "nunca ticke".
- **`sc-not-measurable` deixa de sinalizar `API`** (`validate-sdd.sh`): é
  termo genérico de domínio, e o `SKILL.md` de `validate-documentation` já
  prometia explicitamente que `API`/`CLI`/`JSON` não disparariam — a tabela
  de findings do próprio SKILL.md contradizia esse parágrafo e foi alinhada.
  Sobram apenas termos de performance de implementação (`TPS`, `paint time`,
  `render time`). Caso real: `SC-002` com "serviços Go que expõem API HTTP"
  era rejeitado e só passava reescrito para "endpoints HTTP".
- **`commit-mode.sh task-message`** comprime IDs por *runs* contíguos dentro
  da mesma fase. A heurística anterior tratava a transição de fase
  (`major+1`, `minor=1`) como continuidade sem verificar se os minors
  intermediários estavam na lista: `--task-ids "1.1,2.1,2.2,2.3"` (com
  1.2/1.3 bloqueadas na onda) emitia `feat: tasks 1.1-2.3`, implicando
  falsamente que tasks puladas foram concluídas. Agora emite
  `feat: tasks 1.1, 2.1-2.3`. IDs não-numéricos deixam de entrar em
  aritmética (sob `set -eu`, abortavam o script).
- **`state-ondas.sh record-task`** avisa em stderr quando `--task-id` tem 3+
  níveis (`N.M.K` = subtarefa/checkbox em vez do heading `### N.M` do
  `tasks.md`). Aviso, não erro — gravar no nível errado já aconteceu em
  campo, só descoberto depois pelo `reconcile-tasks`.

### Fixed

- **`commit-mode.sh finalize` violava o próprio contrato "sempre exit 0 +
  `push_pr_result` sempre gravado"**: o script roda sob `set -eu` e o
  `eval "cstk session pr …"` estava numa linha própria, então uma falha do
  comando abortava a função inteira antes de qualquer `_cm_record_result`.
  Observado em campo: exit 9 com `.push_pr_result` null. Agora usa
  `|| _cstk_rc=$?`, preservando o fallback `git push` + `gh pr create`.
- **`commit-mode.sh stage-derived` retornava rc=3 "allowlist vazia" enganoso
  com `--scope-dir` absoluto**: o filtro casa por prefixo contra paths de
  `git status --porcelain`, que são sempre relativos, mas os prompts dos
  orquestradores passam `<FD>`, que resolve para absoluto em vários pontos —
  o casamento nunca ocorria mesmo havendo arquivos staged-áveis. Valores
  absolutos sob `--projeto-alvo-path` agora são normalizados; fora do repo,
  emitem diagnóstico em vez de silêncio.

## [5.25.0] - 2026-07-26

Métricas de consumo por spawn de subagente (feature `wave-token-metrics`,
PR #46): os totais de tokens/tool-uses/duração que o harness registra ao fim
de cada spawn agora são capturados, agregados por onda e expostos nos
relatórios — fechando o gap "quanto custou cada onda e em qual modelo".

### Added

- **Hook `PostToolUse` `posttooluse-agent-usage.sh`** (agente-00c-runtime):
  captura o `tool_response` de spawns da tool `Agent` (totalTokens + breakdown
  input/output/cache-read/cache-creation, tool uses, duração, modelo) num
  sidecar append-only `wave-agent-usage.jsonl` — fail-open absoluto, permissão
  `0600`, cap de 500 linhas, nunca toca o `state.json`; spawns em background
  (`async_launched`, ~50% dos casos reais) viram `indisponivel` (`null` ≠ `0`,
  nunca estimado — Princípio VI). Provisionado por `apply_guard_hooks()`.
- **Agregação por onda**: `state-ondas.sh start/end` consome o sidecar →
  `.waves[N].agent_usage` + `.waves[N].agent_spawns[]` +
  `.accumulated_metrics.agent_*`, com `spawns_total` separado de
  `spawns_with_usage` e resiliência a linhas corrompidas.
- **`wave-usage-report.sh`** (novo helper read-only): `aggregate` (Markdown
  canônico + `--json`, distribuição de tokens por modelo incluindo
  `nao-aplicavel`) e `backfill` (reconstrói métricas de execuções passadas a
  partir do transcript JSONL, correlacionando `tool_use`↔`toolUseResult` via
  `tool_use_id`; opt-in, idempotente, exit 3 quando sem cobertura).
- **knowledge.db v9→v10**: 9 colunas `agent_*` na tabela `waves`; migração
  idempotente; `--ingest`/`--reindex` leem `.waves[].agent_usage` com retrofit
  `NULL` para dados antigos.
- **Consumo nos relatórios**: `report.sh` §1/§2 (linhas de spawns/tokens/
  cobertura da métrica) e `review-task` §4.5 (cruzamento custo×roteamento —
  join `wave-usage-report` × `model-routing-report` por onda).
- Testes: `tests/test_posttooluse-agent-usage.sh` (18 cenários) +
  `tests/test_wave-usage-report.sh` (31) + extensões em `test_state-ondas.sh`
  (+9), `test_report.sh` (+3), `tests/cstk/test_recall.sh` (+4) e
  `tests/cstk/test_hooks.sh` (+2).

### Changed

- `docs/specs/wave-token-metrics/` — spec/plan/contratos/checklists/tasks da
  feature (pipeline feature-00c completa: 14 ondas, 76 decisões auditadas,
  backlog 59/59).

## [5.24.0] - 2026-07-24

Documentação passa a ter o **inglês como idioma principal**, com a leitura em
pt-BR a um clique. Cada documento vira o par `X.md` (inglês, primário) +
`X.pt-BR.md` (português), com uma linha de troca de idioma no topo. Mudança
puramente documental — nenhum comportamento de skill, CLI ou runtime foi
alterado.

### Added

- **Cópias em português** de 11 documentos, como siblings `*.pt-BR.md`:
  `README`, `CONTRIBUTING`, `THIRD-PARTY-NOTICES`, `cli/README` e os 7 docs
  de tópico (`docs/sdd-pipeline`, `agente-00c`, `cstk-session`, `cstk-recall`,
  `cstk-serve`, `go-toolkit`, `conventions`).
- **Troca de idioma** no topo de cada arquivo (`**English** · [Português
  (pt-BR)](…)` no primário; inverso no sibling), com links cruzados entre
  docs resolvendo para o sibling do mesmo idioma.

### Changed

- **`README.md` e os 10 documentos relacionados agora são a versão em inglês**
  (o conteúdo em português foi preservado 1:1 nos `*.pt-BR.md`). Comandos,
  paths, nomes de skill/flag, contagens, URLs, marcadores de snippet mkdocs e
  gatilhos de skill (frases literais em pt-BR) foram mantidos byte-a-byte.
- **`tests/test_doc-counts.sh`**: a guarda de contagem de skills passa a casar
  a frase em inglês (`"<N> global skills"`) do README primário.

## [5.23.0] - 2026-07-23

Absorve o aprendizado ESTRUTURAL do benchmark OpenSpec — specs vivas com
disciplina de delta e merge — e fecha a sug-001 da execução anterior
(hardening de staging). Feature `living-specs` executada ponta-a-ponta via
`feature-00c` (9 ondas, 30 tasks, converge com 1 MEDIUM corrigido, suite
completa 1758/0/0). Mudanças aditivas — o archive datado da v5.22.0
continua valendo; o corpus é um destino ADICIONAL do conteúdo.

### Added

- **Corpus canônico de specs vivas** (`docs/specs/current/`): descreve o
  comportamento ATUAL do sistema por capability (formato em
  `contracts/corpus-format.md` da feature), alimentado no momento do
  archive — o conhecimento deixa de evaporar em `_archived/`. Origem:
  modelo `openspec/specs/` vs `openspec/changes/` do OpenSpec.
- **Seção opcional `## Delta Requirements`** no template de spec da
  `specify` (`ADDED/MODIFIED/REMOVED/RENAMED Requirements`): a spec de
  feature declara o delta que será aplicado ao corpus no archive; regra
  de descoberta/reuso de slug de capability evita fragmentar o mesmo
  conceito em arquivos distintos.
- **`delta-gate.sh`** (`global/skills/review-features/scripts/`): gate
  read-only determinístico — parser da seção delta, validação estrutural
  do corpus (`corpus-malformed`, pré-referencial), validação referencial
  (`ref-not-found`/`added-collision`/`renamed-target-exists`), regra
  "feature sem delta é inválida salvo skip explícito", anti-path-traversal
  e envelope DIAG. Cobertura: `tests/test_delta-gate.sh` (22 cenários).
- **`delta-merge.sh`** (idem): aplicação atômica do delta por capability
  (mktemp+mv), reusando o parser do gate via source. Conflito NUNCA é
  mergeado silenciosamente — vira bloqueio com diagnóstico (no fluxo
  autônomo, `bloqueios.sh register` escopado à feature). Cobertura:
  `tests/test_delta-merge.sh` (11 cenários).
- **Integração no archive do `review-features`**: a ação de arquivar roda
  `delta-gate.sh` → `delta-merge.sh` → `mv` para
  `_archived/YYYY-MM-DD-<feature>/`.
- **Hardening de staging (sug-001)**: subcomandos `snapshot` +
  `stage-derived` no `commit-mode.sh` — staging por allowlist derivada do
  diff da onda (porcelain `-z` NUL-delimitado + `--untracked-files=all`),
  NUNCA `git add -A`. Os 4 sites de staging amplo (prosa dos 2
  orquestradores + `state-ondas.sh`) convergiram ao helper; zero
  `git add -A` vivo no repo. Cobertura: +32 cenários em
  `tests/test_commit-mode.sh`, regressão em `tests/test_state-ondas.sh`
  (cenário "arquivo untracked alheio nunca staged").

## [5.22.0] - 2026-07-23

Absorve os aprendizados de higiene do benchmark OpenSpec (Fission-AI),
itens 2-5 do estudo comparativo — o item estrutural (specs vivas + delta
specs) fica para feature dedicada. Feature `openspec-hygiene` executada
ponta-a-ponta via `feature-00c` (7 ondas, 46/46 subtasks, converge com
zero gaps, suite completa 1715/0/0). Mudanças aditivas — sem breaking
changes.

### Added

- **Gate determinístico de cobertura requirement↔cenário**
  (`global/skills/checklist/scripts/requirement-coverage.sh`): verifica
  que todo FR da spec tem >=1 cenário associado por correspondência
  heurística textual de 2 vias (`--min-match` default 2), no padrão
  `FINDING|severity|code|msg` + `RESULT` dos gates existentes. Integrado
  como gate bloqueante na `specify` (ETAPA 4) e advisory na `checklist`
  (achado vira `[Gap]`). Origem: regra "Every requirement MUST have at
  least one scenario" do OpenSpec. Cobertura:
  `tests/test_requirement-coverage.sh` (11 cenários).
- **Envelope diagnóstico uniforme `_diag.sh`**
  (`global/skills/agente-00c-runtime/scripts/`): helper sourceable que
  emite `DIAG|severity|code|message|fix` — onde `fix` é uma frase
  acionável com o próximo passo — adotado como piloto ADITIVO em 4
  scripts do runtime (`state-rw.sh`, `state-lock.sh`, `state-ondas.sh`,
  `bloqueios.sh`); mensagens legadas intactas. Origem:
  docs/agent-contract.md do OpenSpec (campo `fix`). Cobertura:
  `tests/test__diag.sh` (6 cenários).
- **Guia de triagem "atualizar spec existente vs abrir feature nova"**:
  critérios do OpenSpec (mesma intenção/refino → atualizar; intenção
  mudou/escopo explodiu → nova feature) absorvidos na `specify`
  (ETAPA 0.4) e na `clarify` (ETAPA 2.3), com critério consistente
  entre as duas.
- **Convenção de archive datado**
  (`docs/specs/_archived/YYYY-MM-DD-<feature>/`): ordenação cronológica
  do histórico de features arquivadas, documentada no `review-features`.
  Anti-retroativa: diretórios já arquivados NÃO são migrados (links em
  CLAUDE.md/memórias/specs preservados).

## [5.21.0] - 2026-07-17

Fecha dois gaps de execução autônoma levantados em dogfooding (PR #37):
a triagem interativa da `specify` não tinha atalho para orquestradores
(que não têm usuário presente para responder o menu), e a métrica
`tool_calls` das ondas era sempre 0 porque nenhum mecanismo automático
invocava o tick. Mudanças aditivas — sem breaking changes.

### Added

- **Hook PostToolUse `posttooluse-tool-call-tick.sh`** (runtime
  agente-00c): alimenta de verdade a métrica de tool calls por onda.
  Matcher `*` (todas as tools), fail-OPEN absoluto (qualquer falha = no-op
  exit 0 — é métrica, nunca guarda), mesma detecção de execução ativa e
  precedência do `pretooluse-bash-guard.sh` (agente-00c vence; entre
  feature-00c, menor short-name; status `em_andamento`/`aguardando_humano`).
  Decisão de design: o hook **nunca toca o `state.json`** — PostToolUse
  dispara concorrente aos writes transacionais do orquestrador e um
  read-modify-write clobberaria Decisões/bloqueios; o tick vai num sidecar
  append-only `<state-dir>/tool-call-ticks.log`. Provisionado por
  `apply_guard_hooks()` junto do guard (best-effort: catálogo antigo sem o
  hook não é erro); `settings.snippet.json` ganha o bloco `PostToolUse`.
  Cobertura: `tests/test_posttooluse-tool-call-tick.sh` (11 cenários) +
  2 cenários novos em `tests/cstk/test_hooks.sh`.
- **ETAPA 0.0 na skill `specify`** (atalho de modo autônomo): com execução
  00c ATIVA (`AGENTE_00C_STATE_DIR` setada, OU `state.json` de
  agente-00c/feature-00c com status `em_andamento`/`aguardando_humano`), a
  invocação pelo orquestrador pai vale como a confirmação explícita da
  triagem — menu 0.3 não é apresentado e o pressuposto é registrado em uma
  linha no output. Refinamento sobre a detecção da seção de cache: state em
  disco só conta com status ativo, então um state antigo/concluído no repo
  não pula a triagem de uma invocação manual. A classificação 0.1 segue
  rodando como auditoria (divergência bugfix/refactor é registrada, não
  aborta).

### Changed

- **`state-ondas.sh` + `budget.sh` agregam o sidecar de ticks**: `end` soma
  campo do state + sidecar no fechamento da onda (e consome o sidecar);
  `start` zera a janela de contagem; `budget.sh check|status` somam
  mid-onda. Com isso o threshold `tool_calls_threshold_wave` (default 80)
  passa a comparar com número real — estourar gera fim de onda gracioso,
  não aborto; o valor 80 nunca foi validado com contagem real e deve ser
  recalibrado com dados de execução. `tool-call-tick` manual preservado
  (legado), mas NÃO deve ser usado em paralelo ao hook (contagem dobrada).
- **Prosa dos orquestradores** (`agente-00c-orchestrator.md` e
  `agente-00c-feature-orchestrator.md`): a instrução manual de tick por
  Bash call (advisory, nunca cumprida — a mesma classe de falha que motivou
  enforced-guards) foi substituída pela nota do mecanismo automático via
  hook.

## [5.20.0] - 2026-07-16

Nova skill `converge`: fecha o loop de reconciliação entre documentação
(spec/plan/tasks) e o estado REAL do código, atuando como gate incondicional
entre `execute-task` e `review-task` nos orquestradores autônomos. Skill nova
aditiva — sem breaking changes.

### Added

- **Skill `converge`** (feature `skill-converge`): reconcilia a intenção
  documentada (spec/plan/tasks) contra o estado ATUAL do código do
  projeto-alvo e apenda gaps acionáveis como nova fase de `tasks.md`,
  classificando cada divergência como `missing`/`partial`/`contradicts`/
  `unrequested`. 5 scripts POSIX novos em `global/skills/converge/scripts/`:
  `extract-intent.sh` (paths declarados + origem), `extract-must.sh`
  (princípios MUST/NON-NEGOTIABLE da constitution), `severity.sh` (função
  pura tipo×prioridade×must→severidade), `converge-tasks.sh` (mecânica
  determinística do `tasks.md`: next-phase/existing-keys/append-phase) e
  `path-contains.sh` (contenção de blast radius com resolução de symlinks,
  fail-closed). `SKILL.md` traz o fluxo de agente + rubrica de classificação
  determinística, com `templates/convergence-phase.md` e
  `evals/triggers.jsonl` para eval de disparo. Cobertura: 6 arquivos de teste
  novos (`test_extract-intent.sh`, `test_extract-must.sh`, `test_severity.sh`,
  `test_converge-tasks.sh`, `test_path-contains.sh`,
  `test_converge-orchestrator-gate.sh`), 109 cenários no total.
- **Gate incondicional `convergence`** em `agente-00c-orchestrator.md` e
  `agente-00c-feature-orchestrator.md`: disparado automaticamente na
  fronteira `execute-task → review-task`, diferente dos demais gates de
  qualidade (`validate-documentation`/`validate-docs-rendered`/
  `owasp-security`) — não é opt-outable. A própria skill `converge`
  auto-detecta modo autônomo (via `AGENTE_00C_STATE_DIR`) e auto-registra seu
  two-step (`state-decisions.sh register` + `record-skill`); findings
  `CRITICAL` viram `BloqueioHumano`, demais viram Decisão informativa.
  `quickstart.md` Scenario 11 documenta o roteiro passo-a-passo do cenário de
  integração ponta-a-ponta.
- **Perfis de instalação**: `converge` registrado em `scripts/profiles.txt.in`
  sob `sdd` (gate obrigatório dos orquestradores — mesma razão de
  `validate-documentation`/`validate-docs-rendered`/`owasp-security`) e
  `complementary` (uso standalone). Perfil `sdd` 16→17 skills, `complementary`
  12→13, `all` 30→31; `README.md` atualizado (contagem de skills, tabela de
  skills complementares, tabela de perfis de instalação).

## [5.19.0] - 2026-07-15

### Added

- **knowledge.db schema v9 (`executions-target-path`)**: coluna aditiva
  `target_project_path TEXT` (nullable) na tabela `executions`, fechando o
  gap do consumidor (cstk-panel #7) que não tinha como localizar o projeto
  no filesystem sem configuração manual (`CSTK_PROJECT_PATHS`). O
  `cstk recall --ingest` agora persiste o caminho do projeto-alvo lido do
  state.json (`.execution.target_project_path`, com fallback legado
  `.execucao.projeto_alvo_path`) — valor BRUTO, sem canonicalização nem
  validação no ingest (responsabilidade do consumidor); campo
  ausente/vazio → `NULL` silencioso (degradar-nunca-quebrar).
  - **Migração v8→v9**: `ALTER TABLE ADD COLUMN` idempotente guardado por
    `PRAGMA table_info` (mesmo padrão da coluna `session` do v8); DB v8
    existente migra sem perda, DB nova nasce v9, `waves` e `knowledge_fts`
    intocadas. Puramente aditiva: consumidores antigos que ignoram a coluna
    continuam funcionando.
  - **Backfill em re-ingestão**: como o upsert é pela chave natural
    (`project`, `feature`, `wave`, `source_id`), re-rodar `--ingest` sobre
    um state já indexado preenche a coluna em linhas pré-existentes, sem
    duplicatas.
  - **Cobertura**: 3 cenários novos em `tests/cstk/test_recall.sh` (EN +
    fallback pt + ausente→NULL; backfill idempotente sobre DB v8; migração
    v8→v9 idempotente com linhas v8 intactas) + expectativas de
    `schema_version` atualizadas 8→9 nos cenários existentes.

## [5.18.0] - 2026-07-11

### Added

- **`cstk serve`: asset de release verificável preferido ao auto-tarball da
  API**: o guard fail-closed do 5.15.0 (enforced-guards) bloqueava todo
  `cstk serve`/`--update` com `unverifiable-blocked` porque procurava o
  checksum em `<tarball_url>.sha256` — endpoint de auto-tarball da API do
  GitHub, que não tem como ter arquivo publicado; o único caminho era
  `--allow-unverified`. Agora `_serve_download_verify_extract` (modos nativo
  E `--docker`) prefere um par de assets `<nome>.tar.gz` +
  `<nome>.tar.gz.sha256` publicado na release (primeiro `.tar.gz` na ordem
  da API cujo sibling exato exista; pareamento por igualdade de string
  completa, nunca substring) e instala com outcome `verified`, sem bypass.
  Sem par completo, fallback ao auto-tarball (fail-closed intacto);
  mismatch segue bloqueio absoluto; o asset passa pela MESMA allowlist de
  hosts (`trusted-hosts.sh`). O `package_url` do `enforcement-log.jsonl`
  registra a URL de fato baixada (asset ou auto-tarball). Lado emissor:
  workflow `release.yml` adicionado ao repo do cstk-panel publica o par a
  cada tag (idempotente com release criada manualmente). 4 cenários novos
  em `tests/cstk/test_serve.sh` (55 no total).

## [5.17.0] - 2026-07-11

Feature `panel-docker`, via pipeline SDD `feature-00c`. Aditiva/não-breaking:
o modo nativo do `cstk serve` permanece 100% inalterado quando `--docker`
está ausente.

### Added

- **`cstk serve --docker`: modo opt-in de container para o painel web**.
  Roda o `cstk-panel` dentro de um container Docker local em vez de
  nativamente no host — útil quando `npm`/`node` não estão disponíveis na
  máquina. Pré-flight fail-closed checa `docker` no PATH e o daemon
  acessível (`docker info`) ANTES de qualquer rede, com mensagens
  distintas e acionáveis para cada causa. Reusa o MESMO mecanismo de
  download/allowlist/integridade fail-closed já em produção no modo
  nativo (`--allow-unverified`/`CSTK_SERVE_ALLOW_UNVERIFIED` aplicam-se
  igualmente) — sem segunda fonte de instalação.
  - Imagem local multi-stage (`node:22-alpine`, fixada por digest nos dois
    estágios; `better-sqlite3` compilado do fonte para musl no estágio de
    build) construída a partir da mesma árvore-fonte verificada usada no
    modo nativo; **nunca** publicada em registry remoto. Um encaminhador
    `socat` (`0.0.0.0:8080 -> 127.0.0.1:3001` dentro do container) resolve
    o bind hardcoded do painel em `127.0.0.1`.
  - `--update`/`--reinstall` compõem com `--docker`: reconstroem a
    **imagem** (em vez do diretório de instalação nativo) — `--update`
    só reconstrói se houver release nova (best-effort); `--reinstall`
    sempre vence sobre `--update`, em qualquer ordem dos flags.
  - `docker run` hardened por padrão: usuário não-root, `--cap-drop ALL`,
    `--security-opt no-new-privileges`, rootfs `--read-only` + `tmpfs`
    para `/tmp`, `--init` (tini) + `--rm`. Container de nome
    determinístico (`cstk-panel`) auto-reconciliado a cada execução
    (remanescente de uma execução anterior é removido antes de subir).
  - Monta o diretório do `~/.claude/cstk/` (ou o diretório de
    `$CSTK_KNOWLEDGE_DB`, se definida) **somente leitura** dentro do
    container. Verificado empiricamente contra o índice de produção
    (WAL, 13.5 MB): leitura read-only sobre o mount `:ro` funciona sem
    `immutable=1` (RISCO #1 tecnicamente fechado) com paridade EXATA nas
    12 tabelas de `/api/v1/health` vs `sqlite3` nativo; gravações
    concorrentes no host (nova onda de `agente-00c`/`feature-00c`, ou
    `cstk recall --ingest`) ficam visíveis na PRÓXIMA requisição do
    painel containerizado sem reiniciar o container; e um índice ausente
    degrada graciosamente (HTTP 200, `dbReachable:false`), em paridade
    com o modo nativo.
  - Encerramento gracioso (`Ctrl+C` → `docker stop` com o mesmo grace
    period de 5s do modo nativo).
  - `--help` do `cstk serve` documenta `--docker` e a semântica
    docker-specific de `--update`/`--reinstall`.
  - Nova suíte opt-in `tests/docker/run-panel-docker-smoke.sh` (Docker
    real, fora de `./tests/run.sh`) automatiza os 3 comportamentos acima
    como regressão contínua. Cobertura hermética (sem daemon) em
    `tests/cstk/test_serve-docker.sh` (53 cenários) + extensão de
    `tests/cstk/test_serve.sh` (regressão do modo nativo intacto).
  - Documentação: [`docs/specs/panel-docker/`](docs/specs/panel-docker/spec.md)
    (spec, plan, research, data-model, contracts, quickstart, checklists).

## [5.16.1] - 2026-07-10

Bugfixes derivados de uma varredura da `knowledge.db` (sugestões acumuladas por
execuções 00c passadas), validados contra o código atual antes de aplicar.

### Fixed

- **`state-ondas.sh git-commit` quebrava em git worktree** (afeta `cstk session`):
  o check de repositório usava `[ -d "$_pap/.git" ]`, mas em worktree o `.git` é
  um ARQUIVO (`gitdir: ...`), não diretório → falso-negativo "não é repositório
  git". Trocado por `git -C "$_pap" rev-parse --is-inside-work-tree` (worktree/
  submódulo-safe, alinhado ao `commit-mode.sh`). Regressão coberta por
  `scenario_git_commit_worktree`.
- **`report.sh` afirmava "execução abortada" em feature-00c concluída**: o campo
  "Stack final" do Resumo Executivo imprimia *"não aplicável — execução abortada
  antes de definir"* sempre que `suggested_stack` era null (sempre, em feature-00c,
  que herda a stack do projeto), contradizendo o `Status=concluida` na mesma
  tabela. O fallback agora é condicional ao status: mensagem de "abortada" só para
  `status=abortada`; caso contrário, *"não aplicável (herdada do projeto / não
  definida)"*. Regressão coberta por `scenario_stack_final_condicional_ao_status`.
- **`review-task/SKILL.md` referenciava subcomandos inexistentes**: a §4.5
  (half-records) mandava `state-decisions-reconcile.sh detect` e `repair
  --dry-run/--apply`, mas o script só expõe `check` (detect-only) — rodar `detect`
  saía com exit 2. Corrigido para `check` e reescrito para refletir que não há
  subcomando de repair (resolução de half-record é manual na retomada).
- **`validate-documentation` (perfil `--runbook`): falso-positivo de placeholder
  em corpus pt-br**. O check de placeholder residual casava o token solto `TODO`,
  colidindo com "TODO/TODA" em ênfase CAIXA-ALTA (ex.: "para TODO comando"),
  legítimo em prosa pt-br. Passa a exigir o marcador delimitado (`TODO:` ou
  `TODO(`). (O motor `validate-sdd.sh` introduzido em 5.16.0 já era imune — usa
  delimitadores `[...]`.)

## [5.16.0] - 2026-07-10

Origem: 4 sugestões geradas por IA em outra máquina, validadas contra o código
antes de implementar (Princípio VI). Duas features via pipeline SDD `feature-00c`.
A sugestão que apontava `cycles.sh check --fase` era confabulação (a flag não
existe em nenhum agent file) e foi descartada.

### Added

- **`validate-documentation`: perfil de validação de artefatos SDD**
  (sug-001/sug-003). Novo motor POSIX
  `global/skills/validate-documentation/scripts/validate-sdd.sh` com dois
  perfis: `spec-profile` (sem termos de stack/implementação, FR/SC sem ID
  duplicado, success criteria mensuráveis e technology-agnostic, seções
  obrigatórias, `[NEEDS CLARIFICATION]` ≤ 3) e `plan-profile` (rótulo
  `[EXISTENTE]`/`[PROPOSTA]` em claims de contrato, FR/SC citados existem na
  spec, zero placeholder de template não-substituído). Acionamento por flag
  `--sdd-spec`/`--sdd-plan` ou auto-detecção por path `docs/specs/*/`. Formato
  `FINDING|<severity>|<code>|<msg>`, exit 0 (ok/avisos), 1 (erro), 2 (uso). A
  skill antes só tinha os perfis UC (default) e `--runbook`. `SKILL.md` ganhou
  as seções dos dois perfis + tabela de fronteira de não-duplicação com
  `analyze` (cross-artifact) e `validate-docs-rendered` (render/links).
  Cobertura em `tests/test_validate-sdd.sh` (19 cenários).

### Fixed

- **feature-00c: falso breach de wallclock na retomada** (sug-004). Na
  retomada (`/feature-00c-resume`), o Loop de `agente-00c-feature-orchestrator.md`
  media `budget.sh check` antes de iniciar a onda, medindo o wallclock desde
  `.budgets.current_wave_start` da onda anterior já fechada (`state-ondas.sh end`
  não reseta o campo) → estouro de orçamento falso. Corrigido inserindo o passo
  `3.bis` (`state-ondas.sh start` antes do 1º `budget.sh check`), com guarda
  anti-duplicação via subcomando `wave-status` (só inicia se a onda não estiver
  `open`). O comportamento correto do `agente-00c-orchestrator.md` (que já
  inicia a onda antes do budget check) não foi alterado. Não silencia o check —
  breach legítimo dentro de onda aberta continua disparando.
- **Drift doc↔runtime nos agent files 00c** (sug-002). `state-ondas.sh start`
  não aceita `--fase` (etapas via `end --add-etapa`); `spawn-tracker.sh check`
  não tem flag `--max-depth` (o teto é a constante interna `_ST_MAX=3`); o enum
  de `--motivo-termino` usa `bloqueio_humano`, não `bloqueio`. Os exemplos
  divergentes em `agente-00c-feature-orchestrator.md` custavam 1 retry por onda.

## [5.15.0] - 2026-07-05

### Security

- **Restrições de tools dos 7 agents agora são REAIS**: os agents declaravam
  restrições em `allowed-tools:` (lista YAML), mas em **agents** o campo
  honrado pelo Claude Code é `tools:` (CSV) — `allowed-tools:` é o campo de
  SKILL.md/slash-commands. Resultado: TODAS as restrições estavam
  silenciosamente inertes (o harness listava os 7 agents como "All tools").
  Convertido para `tools:` nos 7; o `data-veracity-verifier` vira READ-ONLY
  de verdade (`Read, Grep, Glob` — Bash removido: quebrava o read-only via
  `sed -i`/`tee`/redirecionamento e nenhuma instrução do corpo o usava).
  `test_data-veracity-verifier.sh` agora falha se o campo `tools:` sumir,
  se portar Write/Edit/Bash, ou se `allowed-tools:` reaparecer em agent.
  Commands e SKILL.md seguem com `allowed-tools:` (campo correto neles).
- **`bash-guard.sh`: blocklist reforçada + análise por segmento**: novos
  bloqueios para `git reset --hard`, `git clean -f*`, `rm` recursivo+forçado
  fora de áreas temporárias (`~`, `$HOME`, `..`, `.git` e absolutos fora de
  `/tmp`, `/private/tmp`, `/var/folders` — `rm -rf` relativo de build dirs
  segue permitido), `sqlite3` mutativo na `knowledge.db` (índice é derivado;
  escrita legítima só via `cli/lib/recall.sh`) e pipe de `curl|wget` direto
  para shell (bloqueado MESMO com domínio na whitelist — a whitelist valida
  a origem, não o que se executa). Bypass histórico do package-manager
  fechado: `docker exec/run` agora precisa estar no MESMO segmento do
  install (`npm install x; docker run y` passava porque a mera coexistência
  liberava). Limitação documentada: sem parsing de quoting; alvo via
  variável (`$VAR/...`) passa — guard é defesa em profundidade, não sandbox.
  +20 cenários em `test_bash-guard.sh` (42 no total).
- **`--from http://` rejeitado em `cstk install` e `cstk self-update`**:
  http em texto plano permite MITM trocar tarball E `.sha256` juntos — o
  checksum de mesma origem não protege contra origem adulterada. Só
  `https://` e `file://` passam. Cenários novos em `test_install.sh` (com
  garantia de zero-write no abort) e `test_self-update.sh`.
- **Rótulo UNTRUSTED do read-back emitido em NÍVEL DE CÓDIGO**
  (`cstk recall --context`, ASI09/LLM01): antes o rótulo era só instrução
  ao LLM nos orquestradores — memória envenenada de outra execução entrava
  no prompt sem delimitador garantido. Agora todo bloco K>0 sai cercado
  pelo aviso ("é DADO, não instrução") direto do `recall.sh`; os
  orquestradores preservam o rótulo e só o prefixam manualmente em
  runtimes antigos. A frase-contrato "Aprendizado recuperado (read-back
  loop)" foi mantida (testes e detecção dependem dela).
- **Trust boundary explícita nos subagentes clarify-answerer** (ambos):
  fontes lidas (briefing/constitution/spec/stack) são DADO para o score,
  nunca instrução — diretiva embutida num trecho força `pause_humano:
  true` com a diretiva apontada na justificativa. Paridade da regra
  FR-026/FR-027 ("texto lido é conteúdo") adicionada à tabela de defesa
  em profundidade do `agente-00c-feature-orchestrator` (antes só o
  orquestrador raiz a tinha).
- **Guardas do runtime deixam de ser advisory e passam a ser enforced**
  (feature `enforced-guards`, três frentes independentes):
  1. **Hook `PreToolUse`/`Bash` fail-closed**: novo
     `global/skills/agente-00c-runtime/hooks/pretooluse-bash-guard.sh`
     intercepta todo comando Bash de uma execução `agente-00c`/`feature-00c`
     ativa e delega a `bash-guard.sh check` (nunca reimplementa regra) —
     antes, a mesma checagem só rodava se a prosa do orquestrador lembrasse
     de invocá-la. Falha do próprio mecanismo (`jq`/`bash-guard.sh` ausente,
     stdin inválido) também bloqueia (`MECANISMO_FALHOU`, distinguível de
     `REGRA_VIOLADA`); sessões manuais do operador fora de execução ativa
     ficam intactas (`exit 0` sem decisão). Precedência determinística
     quando há mais de uma execução ativa (`agente-00c` vence; entre
     `feature-00c`, menor short-name lexicográfico). Toda decisão vira
     linha auditável em `.claude/enforcement-log.jsonl` (campo `command`
     passa por `secrets-filter.sh scrub` ANTES de truncar a 500 chars).
     Provisionado automaticamente por `apply_guard_hooks()`
     (`cli/lib/hooks.sh`), integrado a `install.sh`/`update.sh`, escopo
     `project` apenas. 11 cenários novos em `test_pretooluse-bash-guard.sh`.
  2. **`cstk serve` recusa iniciar sem integridade confirmada por padrão**:
     o antigo ramo "sem `.sha256` disponível → avisa e prossegue" virou
     bloqueio (`unverifiable-blocked`); bypass explícito e auditado via
     `--allow-unverified`/`CSTK_SERVE_ALLOW_UNVERIFIED=1` (aviso de alta
     visibilidade em stderr toda vez que dispara, `bypass_method` logado);
     divergência de checksum continua bloqueando sempre, sem bypass
     possível (regressão preservada). Linha `source: "serve-integrity"`
     no mesmo `enforcement-log.jsonl`. Extensão de `test_serve.sh`.
  3. **Allowlist de hosts confiáveis compartilhada**: novo
     `cli/lib/trusted-hosts.sh` define `CSTK_TRUSTED_RELEASE_HOSTS`
     (`github.com`, `codeload.github.com`, `objects.githubusercontent.com`,
     `api.github.com` — mesma lista já usada pelo `serve.sh`, agora
     compartilhada) com match EXATO case-insensitive (userinfo removido
     antes de comparar; sem `grep`/substring — previne CWE-290 tipo
     `github.com.evil.com`). Consumida também por `install.sh`
     (`_install_resolve_urls`) e `self-update.sh` (`_su_resolve_urls`):
     host fora da lista é rejeitado ANTES de qualquer download.
     `file://` permanece isento (fluxo de dev). Constante fixa, não
     overridable via env (alargar a allowlist em runtime silenciaria o
     mesmo tipo de enfraquecimento que a feature existe para fechar). 13
     cenários novos em `test_trusted-hosts.sh` + extensões em
     `test_install.sh`/`test_self-update.sh`.

  Spec completa (spike de propagação do hook a subagentes, threat model,
  data model, 10 cenários de quickstart) em
  [`docs/specs/enforced-guards/`](./docs/specs/enforced-guards/).

### Added

- **`state-ondas.sh record-skill --kind skill|gate`** (default `skill`,
  higiene da métrica): separa SKILLS reais (invocadas via tool Skill) de
  GATES determinísticos de script (ex.: `validate-tasks-template.sh`). A
  ingestão da knowledge.db passa a EXCLUIR `kind=gate` da tabela `skills`
  e do `waves.n_skills` (entradas legadas sem `kind` seguem contando —
  compat). Motivo: a métrica estava poluída com gates e até comandos de
  build/lint (`go build`, `eslint`, `workout_service`...) gravados como
  "skills". Orquestradores instruídos: `--kind gate` para scripts
  determinísticos; comandos de build/test/lint NUNCA via `record-skill`
  (pertencem a `.tasks[]`/`.events[]`). Cenários novos em
  `test_state-ondas.sh` (3) e `test_recall.sh` (W8).
- **Seção "Disciplina de output (anti-estouro)"** nos dois orquestradores:
  execuções reais foram perdidas por estouro de limite de output em ondas
  longas (sinal do `/insights`). Regras duras: nunca imprimir artefato
  inteiro no turno (path + <= 3-5 linhas), exploração ampla via
  Glob/Grep dirigidos sem dumps, sumário de onda <= 40 linhas, saída de
  skill/gate registrada como RESUMO na Decisão.
- **`docs/fluxo-orquestradores-00c.md`**: diagramas Mermaid (flowchart) do
  ciclo completo dos orquestradores — setup do command pai, loop de ondas,
  sub-fluxo clarify, gates, bloqueios e condições terminais. Extraído das
  4 fontes canônicas (commands + orchestrators), sem invenção.

### Deprecated

- **Skill `image-generation`**: marcada como deprecated (`deprecated: true`,
  `deprecated_since: 5.15.0`, `remove_in: 6.0.0`). Fora do escopo do toolkit
  (documentação/SDD): sem wiring com orquestradores ou outras skills, sem uso
  registrado na knowledge.db e sem substituto planejado. Continua funcionando
  até a remoção na 6.0.0.

### Changed

- **Boot tax: descriptions enxugadas** (o catálogo de skills é carregado no
  contexto de TODA sessão): `decision-tree` 613 → ~190 bytes (deprecated
  desde a 5.6.0 e ainda pagava a description mais longa do catálogo) e
  `model-selector` 587 → ~360 bytes (removida redundância; triggers e
  contrato suggest-only preservados). `plan` e `e2e-integration-flow`
  ficaram INTACTAS de propósito: foram ajustadas recentemente e um trim
  sem rodar o harness de trigger-eval arriscaria regressão de disparo.
- **Housekeeping de specs**: 5 specs 100% concluídas movidas para
  `docs/specs/_archived/` (`atomic-commit-pr`, `panel-installer`,
  `recall-memory-mirror`, `recall-worktree-identity`, `show-tips`) + o
  relatório solto `review-features-report.md`; referências em README e
  comments de scripts atualizadas para os novos paths.

### Fixed

- **Profile `sdd` (default) não instalava 4 skills que os orquestradores
  invocam**: `review-features` (fase TERMINAL do `/agente-00c`) e os 3
  gates de qualidade obrigatórios (`validate-documentation`,
  `validate-docs-rendered`, `owasp-security`, invocados após
  specify/plan/create-tasks). Um `cstk install` default (profile `sdd`)
  instalava commands + agents do orquestrador, mas a execução quebrava ao
  invocar a primeira skill ausente — mesma classe do bug histórico do
  `agente-00c-runtime` órfão. Profile `sdd`: 12 → 16 skills. Regressão
  gateada em `test_build-release.sh` (greps de presença) e counts
  atualizados em `test_quickstart-e2e.sh`. NOVO cenário
  `scenario_profile_counts_match_sources` em `test_doc-counts.sh` compara
  os números da tabela de profiles do README com as fontes reais
  (`profiles.txt.in` + derivação do `all`) — o README declarava
  "10 sdd / 9 complementary / 29 all" com 16/12/30 reais e nada falhava.

## [5.14.1] - 2026-06-23

### Fixed

- **`reconcile-tasks` cura títulos vazios em `.tasks[]`** (`state-ondas.sh`): ondas `execute-task` longas que gravavam `record-task` em lote sem `--titulo` deixavam entradas com `title=""` (sintoma: N tasks "sem título" com a mesma contagem de testes da suíte da onda, p.ex. 18× `39/39`). O `reconcile-tasks` agora, além do back-fill de tasks ausentes, **cura** entradas já presentes com título vazio, buscando o título no `tasks.md` em duas granularidades — heading (`### N.M Título`) e checkbox (`- [x] N.M.K texto`), com precedência do heading. A fonte é sempre o backlog (rastreável, nunca inventada — Princípio VI); `tests_run`/`tests_passed` **não** são tocados (sem fonte por task → não fabrica). Só fora de `--dry-run`; a contagem de stdout (tasks back-filled) é preservada. Como `review-task` §4.6 chama `reconcile-tasks`, estados afetados se auto-curam no próximo review. Cobertura: 4 cenários novos em `tests/test_state-ondas.sh`.

## [5.14.0] - 2026-06-18

### Added

- **Princípio VI da constituição — Veracidade de Dados / Zero Fabricação (NON-NEGOTIABLE)**: nenhum artefato gerado pelo toolkit pode conter dado factual inventado. Assinaturas de request/response (nomes de propriedades, tipos, shape de payload), URLs/endpoints/querystrings e valores concretos (financeiros, status de registro, IDs, datas, resultados de API) só podem ser escritos se vierem de fonte rastreável: código-fonte, OpenAPI/Swagger, doc oficial, ou resposta de uma chamada de fato observada. Sem fonte e sem de onde extrair → bloqueio humano, nunca suposição plausível. Generaliza o aterramento de evidência de segurança (anti-confabulação) dos orquestradores para qualquer dado factual. Constituição bumpada `1.1.0 → 1.2.0` (MINOR); Decision Framework itens 1 e 4 incluem VI no conjunto NON-NEGOTIABLE. Ver `docs/constitution.md`.
- **Aterramento de dados factuais nos orquestradores autônomos** (`agente-00c-orchestrator`, `agente-00c-feature-orchestrator`): novo bloco "Aterramento de DADOS FACTUAIS (anti-fabricação)" que roteia falta-de-fonte para `bloqueios.sh register` (score 0) + encerramento gracioso da onda (`Schedule intent: none; motivo=bloqueio_humano`), em vez de inventar. Inclui diretiva de **double-check de veracidade** ao fechar `specify`/`plan`, delegada ao novo subagente `data-veracity-verifier` (com fallback inline quando o spawn está indisponível); item sem fonte vira bloqueio humano.
- **Subagente `data-veracity-verifier`** (`global/agents/data-veracity-verifier.md`): auditor READ-ONLY que recebe `artifact_paths` + `allowed_sources` e classifica cada dado factual concreto (assinaturas request/response, URLs/endpoints/querystrings, valores) como `SOURCED` / `PROPOSAL` / `UNSOURCED`, devolvendo veredito `clean | has_unsourced` + ação `proceed | human_block`. Não corrige nada — só reporta; default cético (na dúvida → `UNSOURCED`) e auto-aterramento (não pode alegar fonte sem citar a substring literal). Cobertura em `tests/test_data-veracity-verifier.sh` (8 cenários, incluindo trava de read-only no `allowed-tools` e fiação nos 2 orquestradores).
- **Princípio-base obrigatório no gerador de constituição** (skill `constitution`): toda constituição de projeto gerada passa a incluir, mesmo sem o usuário pedir, um princípio NON-NEGOTIABLE de Veracidade de Dados — Zero Fabricação (com texto-semente), espelhando o Princípio VI deste toolkit.

### Changed

- **Guardrails anti-invenção nas skills produtoras de conteúdo factual**:
  - `specify` (§3.2): a regra "usar defaults razoáveis" passa a explicitar que defaults valem para *políticas de design* (retenção, performance, auth) e **nunca** para dado factual de sistema externo (nomes de campos de payload, assinaturas, endpoints, valores) — sem fonte → `[NEEDS CLARIFICATION]`.
  - `plan` (§5.2 Contratos de Interface): contrato de interface **existente** não se inventa — assinaturas/URLs/endpoints devem vir da fonte real; sem fonte → bloqueio humano. Distingue contrato afirmado-como-real de contrato `[PROPOSTA — a validar na implementação]`.
- **Regra inviolável no `CLAUDE.md` do projeto**: nova seção no topo apontando para o Princípio VI e o mecanismo de bloqueio dos orquestradores.

## [5.13.0] - 2026-06-13

### Added

- **Modo atomic-commit opt-in para agente-00c e feature-00c**: quando ativado no inicio da execucao (`y/Y/yes/sim`; default desabilitado), os orquestradores geram commits automaticos Conventional Commits apos cada etapa de artefato (`specify`, `plan`, `clarify`, `checklist`, `create-tasks`) e um commit ranged por grupo de tasks `execute-task` com `outcome=pass` na mesma onda. Tasks com `outcome=fail` sao excluidas. O campo `.atomic_commit_enabled` e persistido no `state.json` e relido em resumes sem re-prompt. No finalize terminal (`review-features` / `review-task`), push + PR e disparado via `cstk session pr` (path confinado — `git push` cru permanece bloqueado pelo `bash-guard.sh`). Spec: `docs/specs/atomic-commit-pr/`.
- **Helper `commit-mode.sh`** em `global/skills/agente-00c-runtime/scripts/`: subcomandos `is-enabled`, `set-enabled`, `guard-branch`, `stage-message`, `task-message`, `finalize`. Guard de branch default (exit 3 se HEAD = main/master via remote HEAD ou fallback) impede commits/push acidentais na branch default. Cobertura em `tests/test_commit-mode.sh` (23 cenarios, INV-1..8 + FR-015(b)/(c)).
- **Flag `--atomic-commit <true|false>` no `state-rw.sh init`**: persiste `.atomic_commit_enabled` no schema; omitida => `false` (retro-compativel). Validacao em `state-validate.sh` (aceita `true`, `false` ou ausente). Cenarios em `tests/test_state-rw.sh`.
- **Prompt opt-in nos 4 commands de entrada** (`/agente-00c`, `/feature-00c`, `/agente-00c-resume` e `/feature-00c-resume`): pergunta com default "no" nos commands de inicio; resumes omitem o prompt e leem o estado do `state.json`.
- **Nota documental em `bash-guard.sh`**: esclarece que `git push` continua bloqueado mesmo no modo atomic; o push aprovado ocorre exclusivamente via `cstk session pr` (caminho confinado, FR-028 / Constitution §V intactos).

## [5.12.0] - 2026-06-05

### Added

- **State-dirs nascem com `.gitignore` (`*`) semeado na criação**: o estado dos orquestradores é runtime/transacional e nunca deve ser versionado — um repo trackeando `state.json` foi o gatilho do bug `.claude/.claude/` corrigido em 5.11.1. Semeadura nos DOIS pontos de criação: `state-rw.sh::_sr_ensure_state_dir` (init e writes) e `state-lock.sh acquire` (que cria o state-dir ANTES do init no fluxo do command pai). Best-effort e idempotente: `.gitignore` pré-existente do operador nunca é sobrescrito; falha de escrita não aborta o fluxo. Cobre `agente-00c-state/` e `feature-00c-state/<short>/` (incluindo `state-history/`, `backups/`, `whitelist.txt`). NÃO cobre artefatos na raiz de `.claude/` (`agente-00c-report.md`, `agente-00c-suggestions.md`) — gitignore desses fica a cargo do repo alvo. Repos que JÁ trackeiam state precisam de `git rm -r --cached` manual (gitignore não destrackeia).

## [5.11.1] - 2026-06-05

### Fixed

- **`cstk session start`: diretório espúrio `.claude/.claude/` aninhado na worktree** quando o repo alvo versiona arquivos de `.claude/` no git. O checkout do `git worktree add` materializa `<wt>/.claude/` antes da cópia, e `cp -R src dst` com destino existente copia a origem PARA DENTRO dele (semântica POSIX) — criando `<wt>/.claude/.claude/` com os artefatos runtime (`agente-00c-state/`, `agente-00c-report.md`, `scheduled_tasks.lock`...) fora do alcance da blocklist FR-002. Fix em `_session_copy_claude_filtered` (`cli/lib/session.sh`): `mkdir -p` + cópia de CONTEÚDO (`cp -R "$src/." "$dst"`), merge idempotente que nunca aninha, exista ou não o destino. Cenário de regressão `scenario_start_claude_tracked_no_nesting` em `tests/cstk/test_session.sh` (provado falhar no código pré-fix). Runtime instalado requer `cstk self-update` para receber o fix.

## [5.11.0] - 2026-06-05

### Added

- **Feature `recall-worktree-identity`**: identificação canônica de projeto real vs worktree de sessão no knowledge.db (schema v8). Resolve bug v4.7.2 onde ingestão de execuções em worktrees criadas por `cstk session start` registrava projeto fantasma na knowledge.db, quebrando anti-eco em `cstk recall --exclude-feature` e causando retorno de resultados de features diferentes no mesmo projeto.

  **Componentes entregues**:
  
  - **Schema v8 (knowledge.db)**: coluna `session TEXT` adicionada em `executions` e `waves` via migração idempotente `ALTER TABLE`. FTS (`knowledge_fts`) intocada (não suporta ALTER). Campos congelados no state.json (`canonical_project`, `session_name`) ingeridos conforme layout (agente-00c vs feature-00c).
  
  - **Derivação 3 camadas** (`recall_derive_canonical`): resolve o nome canônico do projeto com fallback robusto:
    1. Camada 1 (congelada): `.execution.canonical_project` do state.json (via `--canonical-project` flag do command pai, preenchida no init se worktree detectada)
    2. Camada 2 (git ao vivo): worktree real — `git -C $PAP rev-parse --git-common-dir`, normalizar relativo→absoluto, extrair basename do dirname
    3. Camada 3 (fallback): `basename "$TARGET_PROJECT_PATH"` (nome de fallback final)
  
  - **Bootstrap com detecção de worktree** (commands pai): `/feature-00c` e `/agente-00c` agora detectam se rodam numa worktree via sequência POSIX determinística **antes** de `state-rw.sh init`. Detecção congelada no state.json para garantir imutabilidade após sessão removida (FR-008).
  
  - **Paridade anti-eco**: both agent docs (`agente-00c-orchestrator.md` e `agente-00c-feature-orchestrator.md`) agora derivam `EXCLUDE_FEATURE` do campo `canonical_project` com fallback para basename bruto, garantindo consistência de filtragem entre ingestão (recall.sh) e consumo (read-back loop).
  
  - **State-rw.sh flags novas**: `--canonical-project NAME` e `--session-name NAME` opcionais no init; campos ausentes quando flags omitidas (FR-010, retro-compat).

  - **Cobertura de teste**: 7 cenários novos em `tests/cstk/test_recall.sh` (roundtrip v8, fallback 3 camadas, anti-eco, --reindex), 4 testes em `test_state-rw.sh` (flags novas + validação).

  **Requisitos entregues**: FR-001 até FR-010, SC-001 até SC-006 da feature spec.

### Changed

- **`cli/lib/recall.sh`**: `RECALL_SCHEMA_VERSION` bumped de 7 para 8; campos `session`, `canonical_project` agora ingeridos em `executions` e `waves`; derivação de `project` (agente-00c layout) e `feature` (feature-00c layout) centralizada em função `recall_derive_canonical` com fallback 3-camadas robusto; `--reindex` usa mesma derivação que ingest ao vivo (SC-003/SC-004).

- **`global/skills/agente-00c-runtime/scripts/state-rw.sh` e `state-validate.sh`**: flags `--canonical-project`, `--session-name` adicionadas ao init; validação aceita campos como opcionais (retrocompat FR-010); jq merge condicional garante estado minimalista.

- **Agent orchestrators**: `agente-00c-orchestrator.md` e `agente-00c-feature-orchestrator.md` atualizados para derivar `EXCLUDE_FEATURE` com fallback canônico, resolvendo paridade anti-eco após congelamento do projeto em state.json (contrato ingest-derivation.md §4).

### Fixed

- **Bug v4.7.2 revisitado**: filtragem de anti-eco `--exclude-feature` (para impedir retorno de resultados da própria execução ingerida) agora usa coluna SQL `project` derivada por 3 camadas em vez de basename bruto, eliminando falsos-positivos de worktrees removidas cujo nome coincida com o nome da feature de outra execução real.

## [5.10.2] - 2026-06-04

### Fixed

- **`feature-00c.md` pre-flight (sanitize descricao)**: o passo 2 do pre-flight
  invocava `sanitize.sh` **sem subcomando** (`printf … | sanitize.sh`), o que cai
  no branch de uso incorreto do script (subcomando obrigatório, por design) →
  `exit 2` com stdout vazio. O orquestrador capturava o resultado vazio em `_desc`
  e o exit não-zero abortava o pre-flight de `/feature-00c` antes de tocar o disco.
  Corrigido para `sanitize.sh limit-length --max 500` (emite a descrição truncada
  em stdout, conforme a intenção documentada "truncar"). Era a única invocação
  bare entre todos os callers (`agente-00c.md`, `agente-00c-resume.md` e os
  orquestradores já passavam subcomando válido).

### Changed

- **`test_doc-subcommands.sh`** (lint de invariante): além de validar subcomandos-
  fantasma, agora também pega a **classe-irmã** "script de dispatch invocado sem
  subcomando" (`… | <script>.sh)` / `| <script>.sh` em fim-de-linha) nos docs de
  command/agent. Fecha a lacuna que deixou o bug acima passar (nenhum teste
  exercita o bash dentro dos `.md` de command). Meta-self-check cobre o detector.

## [5.10.1] - 2026-06-04

### Fixed

- **`secrets-filter.sh scrub --env-file`** (issue #21): o scrub de valores do
  `.env` abortava com `sed: RE error: repetition-operator operand invalid`
  quando um valor começava por metacaractere de regex (ex.: número E.164 do
  Twilio `TWILIO_WHATSAPP_NUMBER=+5527...`). O valor era interpolado num
  `sed -E` (ERE), mas o escape só cobria metacaracteres BRE (`] \ / $ * . ^ [`),
  deixando `+ ? ( ) { } |` crus — um valor iniciado por `+` virava operador de
  repetição sem operando, o filtro saía com exit 1 e stdout vazio, bloqueando a
  etapa obrigatória de defesa em profundidade (FR-030) antes de gravar
  report/suggestions/issue. Corrigido trocando a substituição para BRE (`sed`
  sem `-E`), onde `+`/`?` são literais e o escape existente passa a ser
  suficiente. Cobertura de regressão para valores iniciados em `+` (E.164) e `*`.

## [5.10.0] - 2026-06-03

### Added

- **Harness de trigger-eval** (`tests/trigger-eval/`): mede se a `description` de
  cada skill dispara na hora certa — e qual skill é confundida com qual — via juiz
  LLM que vê **só as descriptions**. Absorve o loop de disparo do `skill-creator`
  da Anthropic. Seed de 92 queries em `global/skills/<n>/evals/triggers.jsonl`
  (tiers `base`/`hard`/`gen`) + `negatives.jsonl`. Runners (tool Workflow): `run`,
  `harden` (gera→ground-check→julga), `sweep` (multi-modelo) e `ab` (A/B causal de
  uma description); coletor POSIX+jq `collect.sh`. Periódico / **não-CI**
  (`tests/run.sh` segue sendo o gate determinístico). Anti-confabulação: escolha do
  juiz fora do catálogo é marcada como `OUT:<x>`, nunca aceita como skill real.

### Changed

- **`plan` (description)**: removido o gate implícito "from a spec" que desviava
  pedidos de design técnico (arquitetura/contratos/modelo de dados) para `specify`
  ou `advisor` quando nenhuma spec formal era mencionada; reforçado o *HOW*.
  Validado por A/B causal (desc antiga vs nova, mesmas queries/modelos): Sonnet
  12→14/14, Haiku 13→14/14, **zero regressões** nos controles. Sweep de robustez
  (92 queries × 2 modelos): Sonnet 98,9% / Haiku 97,8%.

## [5.9.0] - 2026-06-03

### Added

- **Atribuição de terceiros**: novo `THIRD-PARTY-NOTICES.md` reconhecendo o
  [GitHub Spec Kit](https://github.com/github/spec-kit) (MIT), do qual o pipeline
  SDD e o template de constituição são adaptados, além de inspirações de cortesia
  (obra/superpowers, convenções do Claude Code) e os padrões de referência
  (OWASP/MITRE/NIST/IETF/W3C/OpenID/CSA). Seção "Créditos & Atribuições" no README.

### Changed

- **`build-release.sh`** agora empacota `LICENSE` e `THIRD-PARTY-NOTICES.md` no
  tarball. O artefato distribuía o template de constituição adaptado do spec-kit
  sem nenhum aviso de copyright (e nunca carregou sequer a própria licença MIT do
  cstk); o MIT exige preservar o aviso nas porções distribuídas.

## [5.8.0] - 2026-06-02

Adiciona a skill complementar **`e2e-integration-flow`**: autoria e execução de
testes E2E de integração full-stack com Playwright. A premissa central é que a
UI é apenas o **gatilho**, não a prova — cada ação que muda estado ganha uma
asserção na camada de trás (rede/API → banco → fila/RabbitMQ → efeitos
colaterais), via um "contrato de fluxo" (tabela ação→consequência por camada)
montado antes do código. Cobre a matriz de casos (happy path, validações de
campo, bordas, erros, authz, idempotência/async), incluindo a asserção do
**espaço negativo** (input inválido não pode gerar write nem evento). Anti-flake
por princípio: nada de `sleep`, só web-first assertions e polling com timeout;
dados isolados + teardown para repetibilidade.

### Added

- **`global/skills/e2e-integration-flow/SKILL.md`** — protocolo em 8 passos
  (contexto/prereqs → contrato de fluxo → matriz de casos → harness → passos UI
  → verificação backend/async → run+triagem por camada → relatório de
  cobertura) + golden rules e fronteiras com `verify`/`bugfix`/`owasp-security`.
- **`references/playwright-patterns.md`** — config (trace/retries/projects),
  reuso de `storageState` (auth uma vez), locators semânticos, web-first
  assertions, asserção de rede (positiva e negativa), isolamento de dados,
  fixtures injetando `db`/`queue`, wiring de CI.
- **`references/backend-async-verification.md`** — asserções diretas no banco +
  cleanup; verificação de RabbitMQ em 3 estratégias (efeito-colateral do
  consumer, bind de fila temporária, management API) com o cuidado de **bindar o
  listener antes da ação**; helper de polling para consistência eventual;
  checklist de verificação por passo mutante.
- **`scripts/profiles.txt.in`**: `complementary:e2e-integration-flow` (entra no
  profile `complementary` e no `all`; não afeta o `sdd`).

## [5.7.0] - 2026-06-01

Fecha um drift silencioso na etapa `create-tasks` do pipeline SDD: o backlog
gerado inline (sub agente que registra a skill mas escreve o conteúdo "de
cabeça") podia omitir o skeleton do template canônico — checkboxes `- [ ]`,
prefixo `FASE`, legendas de status/criticidade, Matriz de Dependências, Resumo
Quantitativo e seções Escopo Coberto/Excluído. O único gate da etapa
(`validate-docs-rendered`) só valida **render** (Mermaid, links, frontmatter),
nunca **conformidade estrutural**, então o drift passava silencioso até um
humano notar. Reforço de prompt na SKILL ("aplique o template fielmente") já
existia e foi ignorado — por isso a correção é uma checagem **determinística
por Bash**, imune ao mesmo modo de falha (LLM) que gerou o problema.

### Added

- **`create-tasks/scripts/validate-tasks-template.sh`** — gate determinístico
  de fidelidade ao template. Emite `FINDING|<severity>|<code>|<msg>` +
  `RESULT`. Severidade **`critical`** (sem heading `FASE`, sem checkbox, sem
  tag de criticidade) = drift que quebra downstream (`execute-task` /
  contagem de métricas do `review-task`); **`warning`** = seção de metadados
  ausente (legendas, Matriz, Resumo, Escopo Coberto/Excluído). Honra
  `phase_prefix` do `config.json` sem `jq` (POSIX puro) ou via
  `--phase-prefix`. Exit `0` conformante, `1` drift, `2` uso/arquivo.
  Read-only. Cobertura em `tests/test_validate-tasks-template.sh` (10 cenários)
  + fixture `tests/fixtures/tasks-md/conformant.md`.
- **`assert_stdout_not_contains`** no harness de testes (`tests/lib/harness.sh`)
  — assertion negativa que faltava, espelhando `assert_stdout_contains`.

### Changed

- **Orquestradores `agente-00c` + `feature-00c`**: adicionado o pre-gate
  `template-fidelity` na etapa `create-tasks`, rodando **antes** do gate
  `docs-render` (skeleton antes de render). `critical` → Decisão + tentativa
  de Edit re-normalizando ao `templates/tasks.md` (preservando todo o conteúdo
  e o progresso `[x]`); `warning` → Decisão informativa. `record-skill` como
  nos demais gates.
- **SKILL `create-tasks`**: documenta o novo script em "Scripts auxiliares" +
  gotcha sobre o drift silencioso do backlog gerado inline.

## [5.6.0] - 2026-05-31

### Deprecated

- **Skill `decision-tree`**: marcada como deprecated (`deprecated: true`,
  `deprecated_since: 5.6.0`, `remove_in: 6.0.0`). O **cstk-panel**
  (`cstk serve`) passou a visualizar as decisões do `state.json` de forma
  mais eficiente — interface web interativa, sempre atualizada, sem gerar
  arquivos HTML avulsos. A skill continua funcionando até a remoção em
  v6.0.0; nenhum substituto será portado para dentro do toolkit (a
  visualização vive no painel). Frontmatter do `SKILL.md` recebeu os campos
  de depreciação e um banner; README marca a entrada como deprecated.

## [5.5.0] - 2026-05-30

Encerra um bug recorrente (3 ocorrências seguidas, em features distintas) em
que o orquestrador `feature-00c`/`agente-00c` **retorna sem fechar a onda nem
emitir `Schedule intent`** — deixando a onda aberta, o ponteiro
(`current_stage`/`next_instruction`) parado e a `knowledge.db` sem o
conhecimento da onda. Diagnóstico: são DUAS camadas. (1) O orquestrador (LLM)
trata o retorno da Skill da fase como fim de turno e para antes dos passos
6-13 — comportamento que o "Contrato de conclusão de turno" já tenta evitar
por reforço de prompt e que, empiricamente, **reforço de prompt não resolve**.
(2) A recuperação determinística estava documentada mas **não encodada em
nenhum dos 4 commands pai** — vinha sendo feita à mão a cada ocorrência. A
correção move o fechamento para uma rede de segurança **idempotente e
obrigatória a cada retorno** no PAI.

### Added

- **`state-ondas.sh reconcile-wave`** — rede de segurança determinística e
  idempotente para o caso "onda aberta". Guarda de idempotência via
  `wave-status`: se a onda já está fechada/ausente → NO-OP (não double-conta
  `accumulated_metrics`); se aberta → fecha deterministicamente (back-fill de
  `.tasks[]` em execute-task → `record-skill` → `end` com motivo derivado →
  avança `current_stage`/`next_instruction`, ou promove
  `.execution.status=concluida` na fase terminal). Flag `--terminal-phase`
  para terminalidade dependente de flavor (feature-00c=review-task,
  agente-00c=review-features). 13 cenários novos em `tests/test_state-ondas.sh`.
- **`state-ondas.sh wave-status`** — primitiva `open|closed|none` da última
  onda (`.waves[-1].termination_reason`), base da guarda de idempotência.

### Changed

- **4 commands pai chamam `reconcile-wave` INCONDICIONALMENTE** a cada retorno
  do orquestrador, antes do ingest na `knowledge.db` (e, no
  `/agente-00c-resume`, ainda com o lock ativo). Quando o orquestrador parou
  cedo sem emitir `Schedule intent:`, o pai passa a **derivar o agendamento do
  `.execution.status` real** (terminal → não agenda; `em_andamento` → agenda a
  próxima onda) em vez de depender da linha que o orquestrador não emitiu.

### Fixed

- **Ordem ingest-vs-fechamento**: o eco de ingest no pai rodava mesmo com a
  onda aberta (ingerindo onda incompleta); agora o `reconcile-wave` fecha
  antes.
- **Over-advance do ponteiro na fase terminal do `feature-00c`**:
  `pipeline.sh next-stage` usa a lista COMPLETA (agente-00c, termina em
  review-features), o que avançaria `review-task → review-features`
  erroneamente numa feature; `--terminal-phase review-task` corrige.

## [5.4.0] - 2026-05-30

Restaura no `feature-00c` a paridade de duas capacidades que só o
`agente-00c` (orquestrador de projeto) exercia: o registro de **Sugestões
para skills globais** (FR-020) e a **retrospectiva proativa por marco** (a
cada 25 ondas). Diagnóstico: as sugestões sumiram dos relatórios das features
recentes não por maturidade, mas porque o orquestrador `feature-00c` nunca
teve o gatilho ativo — só mencionava o mecanismo na tabela de capacidades e
ainda apontava para um subcomando fantasma (`suggestions.sh append`, que não
existe; o real é `register`). Mesmo padrão de bug-fantasma da 5.3.0. Empírico:
toda execução `feature-00c` (inclusive runs de 31 e 38 ondas) fechava com 0
sugestões, enquanto runs `agente-00c` produziam 2–9.

### Added

- **`feature-00c`: gatilho ativo de Sugestão para skill global** (passo
  `10.qua` do loop + seção "Sugestões para skills globais (FR-020)"): porta o
  checkpoint que o `agente-00c` já tinha, registrando via `suggestions.sh
  register` com `--suggestions-file` em
  `<projeto>/.claude/agente-00c-suggestions.md`. A §5 do relatório passa a
  popular-se em features (validado end-to-end: register → state → §5).
- **`feature-00c`: retrospectiva proativa por marco** (passo `10.ter` + seção
  dedicada): a cada 25 ondas emite bloqueio LEVE propondo revisão dos padrões
  acumulados e atualiza `.next_retrospective_milestone` — paridade com o
  `agente-00c`.
- **`report.sh emit --flavor feature-00c|agente-00c`** (FR-018): novo subcomando
  que resolve o caminho do relatório pelo flavor, aplica `secrets-filter`
  INTERNAMENTE e SEMPRE, e grava o arquivo. Constrói a capacidade que os docs
  do `feature-00c` (orquestrador, resume, abort) já invocavam como fantasma —
  mesma estratégia da 5.3.0 (construir o que a doc descrevia). secrets-filter
  ausente/inacessível = erro (nunca grava relatório não-filtrado). Cobertura:
  8 cenários novos em `tests/test_report.sh`.
- **`tests/test_doc-subcommands.sh`** (lint de invariante do repo): varre os
  docs de orquestrador/command e falha se uma referência `<helper>.sh
  <subcomando>` apontar para um subcomando inexistente no dispatch do script.
  Pega a classe "subcomando-fantasma" (`append`, `emit`, `check-cmd`,
  `skill-invoked`, `increment`, flags de `init`) em CI, não em runtime.

### Fixed

- **Subcomando fantasma `suggestions.sh append`** na doc do
  `agente-00c-feature-orchestrator` (tabela de capacidades + seção de issue):
  corrigido para `suggestions.sh register` (o único subcomando de escrita que
  existe no runtime). Era o motivo de o mecanismo nunca disparar mesmo quando
  o orquestrador tentava usá-lo.
- **Mais subcomandos-fantasma no `agente-00c-feature-orchestrator`** (achados
  pelo novo lint): `bash-guard.sh check-cmd` → `check`; `spawn-tracker.sh
  increment` → `enter`; `state-ondas.sh skill-invoked` → `record-skill` (4
  ocorrências, incl. uma invocação real no passo de gate). Todos já tinham a
  forma correta em OUTROS pontos do mesmo doc ou no `agente-00c` — eram
  inconsistências que só falhariam em runtime.
- **Referências a `report.sh emit` no `feature-00c`** (orquestrador, resume,
  abort) deixam de ser fantasma agora que o subcomando existe; os 2 sites do
  orquestrador ganham o `--state-dir` que faltava.

### Security

- **Guard anti-confabulação em escalada de segurança** (regra de *aterramento de
  evidência* nos 2 orquestradores + 2 comandos de resume): a evidência citada
  para um evento de segurança (prompt-injection/canary/tampering/output hostil)
  DEVE ser substring **literal** de um tool result observado; sem aterramento →
  `--score 0 --escolha ameaca-nao-verificada` (pause), nunca escalar ameaça
  fabricada. Originou da auditoria de uma execução real (`security-hardening-
  owasp`) onde um resume (PAI) **confabulou** uma string de prompt-injection num
  output SSH limpo, gravou Decisão score-3 com evidência fabricada e escalou ao
  operador (`dec-122`, depois retratada): a trava de score-3 confere que a
  evidência *existe*, não que é *real*. Move o flagra do momento-da-ação para o
  momento-do-registro. Trava de regressão textual em
  `tests/test_orchestrator-evidence-grounding.sh`.

## [5.3.0] - 2026-05-30

Normalização das chaves do `state.json` (runtime agente-00c/feature-00c) e das
colunas da `knowledge.db` de português para inglês. Originou de um bugfix: o
`/feature-00c` documentava um init via one-liner (`state-rw.sh init --short-name
… --briefing-* …` + `drift.sh extract`) que NÃO existia nos scripts — as flags
eram fantasma. A correção exigiu construir as capacidades faltantes, o que abriu
a oportunidade de uniformizar o schema inteiro. **Não-breaking**: pt-BR é aceito
na entrada via aliases; EN é canônico na saída. Remoção do suporte pt-BR = próxima
MAJOR. Mapa congelado em `docs/specs/schema-en-migration/migration-map.md`.

### Added

- **`state-rw.sh` — canonicalizador de chaves** (`_sr_canonicalize_file`):
  rename plano pt-BR → EN em toda leitura/escrita do `state.json`. O arquivo
  converge para EN a cada escrita; states pt-BR legados são lidos
  transparentemente. Subcomando novo `state-rw.sh migrate` canonicaliza um
  state in-place (idempotente; backup pt-BR em `state-history/`).
- **`state-rw.sh init` — modo-feature determinístico**: `--short-name` +
  `--briefing-path/sha256` + `--constitution-path/sha256/version` +
  `--key-aspects` emitem o schema de feature completo (`short_name`,
  `prerequisites`, `current_stage="specify"`) numa única chamada atômica.
  Encerra o recipe multi-passo (init base + N×set) que produzia states
  inconsistentes — **corrige o bug que originou esta release**.
- **`drift.sh extract --text`**: extrator real de keywords (determinístico:
  lowercase + tokenização + stopwords pt/en + dedupe + top-N). Substitui a
  referência fantasma `drift.sh extract --texto` dos docs do `/feature-00c`.

### Changed

- **Chaves do `state.json` → EN** em todo o runtime (~30 scripts +
  orquestradores/commands): `execucao→execution`, `etapa_corrente→current_stage`,
  `ondas→waves`, `decisoes→decisions`, `bloqueios_humanos→human_blocks`,
  `orcamentos→budgets`, `metricas_acumuladas→accumulated_metrics`,
  `sugestoes→suggestions`, + todas as folhas (`contexto→context`,
  `escolha→choice`, `justificativa→rationale`,
  `score_justificativa→justification_score`, etc.).
- **`drift.sh aspectos` → `key-aspects`** (alias `aspectos` mantido com aviso de
  deprecação).
- **`cli/lib/recall.sh` — schema v7**: colunas e tabelas da `knowledge.db`
  normalizadas para EN (tabela `bloqueios→blocks`; `execucao_id→execution_id` em
  todas; etc. — ver `migration-map.md §3.11`). Índice é DERIVADO: o bump
  `RECALL_SCHEMA_VERSION` 6→7 dropa+recria as tabelas renomeadas no 1º acesso de
  um DB pré-v7; `--reindex`/próximo ingest repopula a partir do `state.json` (sem
  perda). `cstk recall --type` aceita `block` (canônico) e `bloqueio` (alias
  deprecado). Ingestão lê chaves EN do `state.json` com fallback pt-BR.

### Notas

- **SemVer MINOR**: nada quebra para usuários do cstk (aliases pt-BR + EN; DB
  reconstrói sozinho). Remoção dos aliases = próxima MAJOR.
- **Fora de escopo** (follow-ups, mesma estratégia de alias): nomes de flag CLI
  (A); valores de enum como `em_andamento` (B); keys de output de relatório
  `model-routing-report`/`report` (D).
- **Consumidores da knowledge.db** (ex.: cstk-panel) precisam adequar-se aos
  nomes de coluna EN — painel é repo à parte.

## [5.2.0] - 2026-05-28

Correção de perda de informação na ingestão de decisões do `knowledge.db`.
Descoberta: ao gravar uma decisão, só a opção escolhida (`escolha`) era
indexada — todas as outras opções avaliadas (`opcoes_consideradas` no
`state.json`) eram descartadas, perdendo o contexto de *quais alternativas
foram consideradas e rejeitadas*. Schema v6 (aditivo).

### Added

- **`cli/lib/recall.sh` — schema v6**: nova coluna `decisions.opcoes (TEXT)`,
  alimentada por `.decisoes[].opcoes_consideradas` do `state.json` (array JSON
  serializado via `tojson` — todas as opções avaliadas, não só a escolhida).
  Entra também no corpo pesquisável da FTS (`type='decision'`), então buscar
  por uma opção *não escolhida* recupera a decisão. `RECALL_SCHEMA_VERSION`
  5 → 6. Migração idempotente `ALTER TABLE decisions ADD COLUMN opcoes` para
  DBs v<6 (checada via `PRAGMA table_info`, espelhando `tasks.titulo`);
  `--reindex` retro-alimenta o histórico já indexado.

## [5.1.0] - 2026-05-28

Feature `recall-suggestions` + correção de robustez na ingestão do `knowledge.db`.
Descoberta ao auditar o índice real: a tabela `retros` estava vazia em todas as
14 execuções porque nenhum produtor escreve `.retros[]` — mas o conteúdo
retrospectivo de verdade (diagnóstico + proposta de meta-padrão) já existia em
`.sugestoes[]` e nunca era indexado. E execuções com data não-canônica sumiam
silenciosamente da tabela `executions`. Schema v5 (aditivo).

### Added

- **`cli/lib/recall.sh` — schema v5**: nova tabela `suggestions (project,
  feature, wave, execucao_id, source_ts, source_id, skill_afetada, severidade,
  diagnostico, proposta, referencias, issue_aberta, ingested_at)`, alimentada
  por `.sugestoes[]` do `state.json`. `diagnostico`+`proposta` formam o corpo
  pesquisável na FTS unificada (`type='suggestion'`) e passam pelo
  `secrets-filter` (FR-006); `referencias` é `join(",")` também filtrado.
  `RECALL_SCHEMA_VERSION` 4 → 5; `RECALL_TYPE_ENUM` estendido com `suggestion`.
  `cstk recall <termo> --type suggestion` e `--reindex` retro-alimentam todo o
  histórico de execuções já indexadas.

### Fixed

- **Linha de execução sumindo silenciosamente** em `recall_ingest_state_json`:
  o cálculo de duração via `fromdateiso8601` **lançava** em `terminada_em`
  date-only (ex. `"2026-05-25"`, gravada por orquestrador antigo), e como o
  parse vivia dentro do mesmo programa `jq` que monta a linha inteira, o throw
  derrubava a execução toda (`executions=0`) sem aviso — enquanto `waves`,
  `decisions` e `bloqueios` da mesma execução eram ingeridos normalmente. Agora
  o parse é isolado em `try … catch ""`: a execução é preservada e só
  `duracao_segundos` vira NULL. Recupera execuções concluídas que estavam
  invisíveis no índice (ex. `flow-assistant-streaming`).

### Notes

- Aditivo: `CREATE TABLE IF NOT EXISTS` cria `suggestions` em DBs v<5 sem perda;
  rode `cstk recall --reindex` para popular as sugestões e recuperar execuções
  que tinham sido derrubadas pela data não-canônica. Zero mudança de surface CLI
  (apenas um valor novo no enum `--type`). Cobertura: 4 cenários novos em
  `tests/cstk/test_recall.sh` (S1–S4); suíte recall 97/97.

## [5.0.0] - 2026-05-27

**BREAKING.** O projeto foi renomeado para `cstk` (repositório
`JotJunior/claude-ai-tips` → `JotJunior/cstk`), alinhando repositório, produto e
binário sob o mesmo nome. Removidas as skills marcadas como *deprecated* desde a
v3.12.0 (remoção originalmente prevista para a v4.0.0). Documentação recalibrada
para descrever o que o toolkit realmente faz.

### Removed

- **`create-use-case`** — use `specify` (formato SDD). Removidos a skill, o
  script `next-uc-id.sh` + teste, as fixtures `tests/fixtures/ucs/`, a entrada
  em `profiles.txt.in` e as referências no catálogo de tips e em `specify`.
- **8 skills `dotnet-*`** — stack .NET descontinuada, sem substituto no toolkit
  global. Removida a árvore `language-related/dotnet/`; o profile
  `language-dotnet` deixa de existir (era auto-derivado da pasta). Quem usa .NET
  deve copiar as skills de uma release ≤ 4.10.0 para `<projeto>/.claude/skills/`.

### Changed

- **Rename `claude-ai-tips` → `cstk`** em URLs, badges, GitHub Pages e scripts de
  install/release. URLs antigas seguem vivas via redirect do GitHub.
- **Honestidade na documentação**: status do `agente-00c` atualizado (funcional,
  porém sem suíte de testes automatizada dos agentes — não mais "esqueleto FASE
  1"); autonomia recalibrada (pausa em bloqueios reais, não é "dispare-e-
  esqueça"); recall descrito como *mitigação* defense-in-depth contra
  prompt-injection (não "defesa"); `owasp-security` reposicionada como revisão
  guiada por checklist (não auditoria/pentest); removido o número não
  verificável "71 bugs / 134 sessões" do `bugfix`.

### Notes

- Profile `all` e contagem caem de **38 → 29 skills**. Quem instalou via `cstk`:
  rode `cstk update`; `cstk doctor` detecta o drift das skills removidas.

## [4.10.0] - 2026-05-27

Feature `recall-memory-mirror`: o `cstk recall` agora indexa e busca os
arquivos `.md` de auto-memoria do Claude Code (`~/.claude/projects/<encoded>/memory/`),
integrando-os na FTS unificada do `knowledge.db`. Schema v4.

### Added

- **`cli/lib/recall.sh` — schema v4**: nova tabela `memories (project, slug,
  type, description, body_scrubbed, path, indexed_at)` com chave primaria
  `(project, slug)`. `RECALL_SCHEMA_VERSION` bumped de `3` para `4`.
  `RECALL_TYPE_ENUM` extendido com `memory`.
- **`cstk recall --ingest` (aditivo)**: apos ingerir telemetria do `state.json`,
  indexa os `.md` em `~/.claude/projects/<encoded>/memory/` do projeto alvo.
  Cada `.md` vira uma entrada em `memories` e uma linha em `knowledge_fts`
  (`type='memory'`, `feature='memory'`, `wave='-'`). Body e description passam
  por `secrets-filter.sh scrub`. Linha de status extendida com `, N memories`.
- **`cstk recall --reindex` (aditivo)**: reconstroi `memories` varrendo
  `~/.claude/projects/*/memory/` no disco via reverse-derivation. Invariante
  C-004: NUNCA le do `state.json` para reconstruir memorias.
- **`cstk recall --type memory`**: filtra busca FTS retornando so memorias; ex:
  `cstk recall "setup" --type memory`.
- **`cstk recall --list-memories [--project P]`**: lista slug + description de
  todas as memorias indexadas (sem body), util para auditoria. Formato:
  `<project> / <type> / <slug> — <description>`.
- **Degradacao graciosa**: todos os novos caminhos (ingest/reindex/list-memories
  de memories) degradam graciosamente quando `sqlite3`, `jq` ou `secrets-filter`
  estao ausentes — exit 0 com aviso; nunca abortam o fluxo de ingestao.

### Notes

- A tabela `memories` e puramente derivada (indice); o `state.json` transacional
  nao e tocado. Base inteira reconstruivel via `cstk recall --reindex`.
- Projetos com underscore no basename podem apresentar `project` inconsistente
  entre ingest e reindex (limitacao CQ1 documentada em `data-model.md`).
- `--ingest` inclui memories so se o `state.json` contem `projeto_alvo_path`;
  `--reindex` inclui todos os projetos com diretorio `memory/` no HOME.
- Entrega: `recall.sh` e runtime — chega a copia instalada via
  `cstk self-update --from <tarball>` (nao via `cstk install/update`).

## [4.9.1] - 2026-05-27

Corrige um falso positivo no painel (`cstk-panel`): execuções **finalizadas com
sucesso** apareciam nas métricas ainda "em andamento" na última fase real (ex.
`review-task`), porque `etapa_corrente` nunca era promovida quando
`execucao.status` virava `concluida`. A normalização é feita na **camada
derivada** (ingestão da `knowledge.db`), mantendo o `state.json` fonte intacto.

### Fixed

- **`cstk recall --ingest` (tabela `executions`)**: quando `.execucao.status` é
  terminal de sucesso (`concluida` — canônico do `state-validate` — ou
  `concluido`, variante histórica), a coluna derivada `etapa_corrente` passa a
  ser `"concluido"`. `abortada`/`em_andamento` preservam a fase real (aborto não
  é conclusão). Só o valor **derivado** muda; o `state.json` transacional fica
  inalterado.

### Notes

- Registros já ingeridos mantêm a `etapa_corrente` antiga até um
  `cstk recall --reindex` (re-lê os `state.json` pela mesma normalização). A
  correção é prospectiva para novas ingestões.
- Entrega: o `recall.sh` é runtime — chega à cópia instalada via
  `cstk self-update`, nunca por `cstk install`/`update`.

## [4.9.0] - 2026-05-27

Rodada de robustez de processo inspirada no benchmark
[obra/superpowers](https://github.com/obra/superpowers): descriptions
orientadas a gatilho, gates à prova de racionalização e checklists de
requisitos com dono e follow-up — para deixarem de ser write-only.

### Added

- **Checklist com dono por item (`{auto}`/`{humano}`)**: a skill `checklist`
  marca cada item com seu resolvedor — `{auto}` (o agente resolve lendo a spec
  e citando evidência) ou `{humano}` (julgamento de valor/risco que cabe ao
  dono do produto). Nova auto-resolução (§3.7) marca os `{auto}` com `[x]` +
  citação, ou `[Gap]` quando a spec não satisfaz.
- **Loop gap → ação**: itens abertos ganham destino explícito (§4.4) —
  `[Ambiguity]`/`[Conflict]` para `/clarify`, `[Gap]` para `/create-tasks`,
  `{humano}` para o dono. A skill `create-tasks` passa a consumir
  `checklists/*.md` da spec e converter `[Gap]`/`[Conflict]` abertos em tarefas
  de requisito — fechando o ciclo sem reordenar o pipeline.

### Changed

- **`description` das skills = quando usar, não o que a skill faz**: removido o
  resumo de workflow dos descriptions de `execute-task` (enumerava os 9
  passos), `decision-tree` (mecanismo interno) e `apply-insights` (caminho de
  implementação). Evita que o Claude siga o resumo sem abrir o corpo da skill.
- **Gates à prova de racionalização**: `execute-task` ganha gate de evidência
  (§8.2 — cada `[x]` exige output literal; o sumário não é prova) e fecha a
  brecha do "(se aplicável)" em testes (§5). Os orquestradores `agente-00c` e
  `feature-00c` ganham 2ª auto-checagem: fechar a onda não promove
  `.execucao.status` — ler o `state.json` real, nunca o sumário do subagente.

## [4.8.0] - 2026-05-27

`cstk serve` volta ao modo de produção de porta única. A partir do
[cstk-panel](https://github.com/JotJunior/cstk-panel) **v0.2.0**, o servidor
Fastify registra `@fastify/static` e serve a API e o SPA buildado no mesmo
processo e porta — não é mais necessário o modo dev (Vite + proxy). O comando
passa a rodar `npm run build && npm run start` e a flag `--port` volta a
controlar a porta de fato.

### Changed

- **`cstk serve` agora usa `npm run build && npm run start`** (em vez de
  `npm run dev`): um único processo Fastify serve API + SPA na mesma porta. O
  `npm run build` continua obrigatório (o tarball é a árvore-fonte; o `start`
  serve `apps/web/dist`).
- **`PORT` volta a ser exportado**: o servidor lê `process.env.PORT` e binda a
  porta resolvida. **`--port` voltou a funcionar** (1024–65535; também lê
  `$PORT`) — removido o aviso de "porta ignorada em modo dev".

### Requires

- **cstk-panel >= 0.2.0** (com serving estático via `@fastify/static`). Painéis
  em cache de versões anteriores devem ser atualizados com
  `cstk serve --update` (ou `--reinstall`); do contrário o `npm run start` antigo
  sobe apenas a API e devolve JSON 404 em `/`.

## [4.7.2] - 2026-05-27

Corrige a proveniência do `knowledge.db` para execuções do **agente-00c**
(orquestrador de projeto): seus registros eram ingeridos com `feature='unknown'`
(o agente-00c não grava `short_name` como o feature-00c). Agora usam o **nome do
diretório do projeto** (basename de `projeto_alvo_path`), tornando os registros
identificáveis no índice e no painel. O `project` já era correto — a correção é
na coluna `feature`.

### Fixed

- **`cstk recall --ingest` (layout `agente-00c-state/`)**: deriva `feature` do
  nome do dir do projeto em vez de `'unknown'`. Sem `projeto_alvo_path`, degrada
  para `'unknown'` (igual ao `project`). O layout `feature-00c-state/<short>/`
  segue inalterado.
- **`agente-00c-orchestrator` (anti-eco FR-011)**: `--exclude-feature` do
  read-back passa de `"unknown"` para `basename(projeto_alvo_path)`, mantendo a
  paridade com o valor ingerido (do contrário o orquestrador ecoaria as próprias
  escritas de volta no read-back de specify/plan).

### Notes

- Registros já gravados como `feature='unknown'` permanecem assim até um
  `cstk recall --reindex` (e apenas para os `state.json` ainda presentes em
  disco). A correção é prospectiva.
- Entrega: o `recall.sh` (runtime) chega via `cstk self-update`; o
  `agente-00c-orchestrator` (catálogo) via `cstk update` — rode ambos para
  manter ingestão e anti-eco consistentes.

## [4.7.1] - 2026-05-27

Corrige `cstk serve`: o frontend (Vite) abortava com `Failed to resolve entry
for package "@cstk-panel/shared-types"`. O painel e uma arvore-fonte e o web
importa o workspace lib `@cstk-panel/shared-types`, cujo `package.json` aponta
`main` para `dist/index.js` — que nao existe ate o `npm run build`. O `cstk serve`
rodava `npm run dev` sem buildar, entao o Vite nao resolvia o pacote.

### Fixed

- **`cstk serve` agora roda `npm run build` antes de `npm run dev`**: compila os
  workspaces (gera `packages/shared-types/dist`, etc.) para que o Vite resolva
  `@cstk-panel/shared-types`. O build e idempotente e roda a cada start, cobrindo
  tambem instalacoes feitas sem build. Se o build falhar, o comando sai com erro
  (sugerindo `--reinstall`) e nao tenta iniciar o painel.

> Contexto: a validacao anterior do modo dev (4.6.1) passou por acaso porque o
> painel havia sido buildado manualmente durante a investigacao; numa instalacao
> limpa (`npm install` apenas) o `dist/` do shared-types nao existia.

## [4.7.0] - 2026-05-27

Adiciona a flag `cstk serve --update`: atualiza o painel `cstk-panel` para a
release mais recente sob demanda, reinstalando **apenas se** houver versao nova
(senao reusa o cache). O start normal continua offline-safe e instantaneo — a
checagem de rede so ocorre com `--update`.

### Added

- **`cstk serve --update`**: consulta a release mais recente via API do GitHub e
  compara com `.panel-version`. Se houver versao nova, reinstala (download +
  `npm install` + `.panel-version` atualizada); se ja estiver na latest, apenas
  informa e reusa. A checagem e best-effort: falha de rede/API **nao aborta** o
  comando — a versao instalada e mantida e o painel inicia normalmente.
- Helper interno `_serve_latest_tag` (POSIX, sem jq): extrai `tag_name` da release
  mais recente, rejeitando prerelease/draft; falha silenciosa (return 1) em
  qualquer erro de rede/parse.

### Notes

- `--reinstall` continua reinstalando incondicionalmente (ignora `--update`).
- Em modo dev, `--update` nao altera a porta da UI (servida pelo Vite na 5173).

## [4.6.2] - 2026-05-27

Unifica a fronteira **command↔orquestrador** para aquisição de lock e
inicialização de estado no agente-00c/feature-00c. Antes, a divisão de
responsabilidades era inconsistente entre as duas famílias e contraditória
internamente: `/agente-00c` (command) não adquiria o lock (o orquestrador
adquiria no loop), enquanto `/feature-00c` (command) **e** seu orquestrador
adquiriam — um double-acquire de um lock não-reentrante (`mkdir`) somado a um
double-init de `state.json`. Resultado: ao iniciar uma feature/projeto, o
agente gastava ciclos lendo 3+ arquivos para (mal-)resolver quem detém o lock,
sem um contrato canônico contra o qual decidir.

### Fixed

- **Modelo único de lock/init**: o slash command PAI (`/agente-00c` |
  `/feature-00c` no início; `*-resume` entre ondas) **adquire** o lock antes
  do spawn e o **libera SEMPRE** após o orquestrador retornar, e cria o
  `state.json`. O orquestrador (subagente) faz **zero** chamadas a
  `state-lock.sh acquire/release` e não re-inicializa estado — sempre continua
  de `.proxima_instrucao`. Idêntico em primeira-invocação e resume.
- **`/agente-00c` (command)** passou a adquirir o lock (passo 3) e a liberá-lo
  SEMPRE (novo passo 5.ter) — antes não fazia nenhum dos dois.
- **Orquestradores** (`agente-00c-orchestrator`, `agente-00c-feature-orchestrator`):
  removidas as chamadas de `acquire`/`release`; o loop apenas valida estado +
  `sha256-verify` dentro do lock já detido pelo pai.
- **Double-init neutralizado** no `feature-00c-orchestrator`: re-inicializar o
  `state.json` clobraria a Decisão de wave-select gravada pelo command pai.

### Added

- Bloco **"Fronteira command↔orquestrador (lock + init) — CONTRATO CANÔNICO"**
  presente nos 6 arquivos do pipeline (2 commands de início, 2 de resume, 2
  orquestradores), para que nenhum agente precise re-investigar a fronteira.

## [4.6.1] - 2026-05-27

Corrige `cstk serve`: o painel agora exibe a interface web. Antes, o subcomando
rodava `npm run start` — que sobe **apenas a API** (Fastify) — e ainda forcava
`PORT=5173` sobre ela, de modo que `http://127.0.0.1:5173` devolvia o envelope
JSON `{"error":"Not found"}` em vez da UI. O painel `cstk-panel` nao possui
serving estatico em producao (o server nao registra `@fastify/static`), e o SPA
depende do proxy `/api` que so existe no modo dev do Vite.

### Fixed

- **`cstk serve` agora lanca o painel via `npm run dev`** (concurrently): a API
  Fastify sobe em `:3001` e o frontend Vite em `:5173`, com o Vite servindo o SPA
  e proxiando `/api -> :3001`. Abrir `http://127.0.0.1:5173` exibe a interface.
- **Removido o `export PORT`**: forcar a porta movia a API para fora de `:3001` e
  quebrava o proxy do Vite. A porta voltada ao usuario passa a ser a do Vite.
- **`--port`**: continua validado (inteiro 1024-65535) por compatibilidade, mas em
  modo dev a UI e servida pelo Vite na `:5173`; um aviso e emitido se `!= 5173`.

> Nota: o modo dev roda um dev server (HMR/watch da fonte). Um serve de producao
> de porta unica exigiria adicionar `@fastify/static` ao server do `cstk-panel`
> (outro repositorio).

## [4.6.0] - 2026-05-27

Adiciona o subcomando `cstk show-tip` — mecanismo de dicas contextuais para skills
do toolkit. Em cada onda do orquestrador, uma dica e exibida automaticamente para
a fase corrente (ex: `--phase execute-task`), mantendo o operador informado sobre
boas praticas sem bloquear o fluxo. O catalogo `tips/catalog.md` cobre 38 skills
(81 entradas: uso, gotcha, avancado) e e extensivel em < 5 minutos por skill.
Inclui correcao de bug no parser awk que impedia a emissao de entradas alternadas.

### Added

- **`cstk show-tip [SKILL] [--phase FASE] [--audit] [--catalog PATH]`**: novo
  subcomando de exibicao de dicas. Modo exibicao: fail-silent absoluto (FR-006),
  sempre exit 0. Modo `--audit`: valida cobertura do catalogo por skill (categorias
  uso + gotcha obrigatorias, >= 2 entradas), exit 0 ok / exit 1 gaps.
- **`tips/catalog.md`**: catalogo com 81 entradas cobrindo 38 skills (23 globais +
  7 Go + 8 .NET). Cada entrada tem frontmatter YAML (`skill`, `category`, `text`)
  + corpo com exemplos concretos em fence de codigo. Formato parseavel por awk POSIX.
- **`cli/lib/show-tip.sh`**: implementacao POSIX sh pura, sem deps externas. Parser
  com maquina de estados awk (OWASP A05: valores de usuario via `-v`, nunca
  interpolados). RNG via `/dev/urandom` + fallback `date +%s`. Fail-silent em todos
  os caminhos de erro. Sourced por `cli/cstk` via dispatch.
- **`tests/cstk/test_show-tip.sh`**: 17 cenarios cobrindo exibicao (5.2), audit
  (5.3), seguranca A05 (5.4) e lint/performance (5.5-5.6). Integrado ao runner
  `tests/run.sh` via convencao `cli/lib/<n>.sh -> tests/cstk/test_<n>.sh`.
- Integracao nos dois orquestradores: `agente-00c-orchestrator.md` e
  `agente-00c-feature-orchestrator.md` exibem dica fail-silent no inicio de cada
  onda via `TIP=$(cstk show-tip --phase "$FASE" 2>/dev/null) || TIP=""`.

### Fixed

- **Parser awk de `_st_parse_catalog`**: correcao de bug onde a transicao
  `body -> "---"` mudava para `state=out` em vez de `state=frontmatter`, fazendo
  com que o frontmatter de cada segunda entrada fosse ignorado. O parser agora
  transita `body -> frontmatter` diretamente, permitindo que todas as entradas
  sequenciais do catalogo sejam emitidas corretamente (antes: 27 de 81 entries;
  depois: 81 de 81). Backward-compatible: catalogo sem terminador final continua
  sem emissao espuria.
- **`tips/catalog.md`**: adicionado terminador `---` apos a ultima entrada
  (`dotnet-testing gotcha`) para que ela seja emitida pelo parser corrigido.
  Sem o terminador, a ultima entrada do catalogo era sempre perdida.
## [4.5.0] - 2026-05-26

Adiciona o subcomando `cstk serve` — interface web local do cstk panel.
Na primeira execução, baixa automaticamente a release mais recente do
[JotJunior/cstk-panel](https://github.com/JotJunior/cstk-panel) e instala em
`~/.local/share/cstk/panel`; execuções subsequentes reutilizam o cache (sem
download). Encerramento gracioso com grace period de 5s (SIGTERM → SIGKILL).
POSIX sh puro; SSRF allowlist para `github.com` e `objects.githubusercontent.com`.

### Added

- **`cli/lib/serve.sh`**: biblioteca POSIX sh que implementa o fluxo completo do
  `cstk serve` — parse de flags (`--port`, `--host`, `--reinstall`, `--help`),
  validação de porta (1024–65535), prereq check de `curl`/`npm`, SSRF allowlist
  (`github.com`, `codeload.github.com`, `objects.githubusercontent.com`,
  `api.github.com`), lazy-install via GitHub Releases API, integridade
  best-effort (`.sha256`), `npm install`, foreground start com
  `trap SIGTERM/SIGINT`, grace period 5s + SIGKILL.
- **`cli/cstk` (dispatch)**: novo `case serve)` que sourca `cli/lib/serve.sh` e
  chama `serve_main "$@"`.
- **`tests/cstk/test_serve.sh`** (29 cenários): cobre flags/porta/host, prereq
  check, SSRF allowlist, lazy-install, tarball corrompido, `npm install` falho,
  saída espontânea do filho, zero `eval`, SIGTERM + SIGKILL (grace period), entre
  outros. Todos os stubs de `curl`/`npm` são locais (sem rede real).
- **`tests/cstk/fixtures/serve/panel-fixture.tar.gz`**: fixture de tarball mínimo
  (`package.json` + `.panel-version`) para testes de download sem rede.

### Changed

- **`README.md`**: nova seção **Painel Web (`cstk serve`)** documentando uso,
  opções, variáveis de ambiente e notas de segurança.
- **`cli/README.md`**: seção de subcomandos atualizada para incluir `serve`.

### Tests

- **`tests/cstk/test_serve.sh`**: 29 cenários PASS, cobertura via
  `--check-coverage` sem órfãos.

## [4.4.0] - 2026-05-26

Fecha um buraco de perda de dados na trilha de tasks: uma feature com 21 tasks
gravava apenas 2 no `state.json`/`knowledge.db`. A causa raiz não estava na
ingestão (`recall.sh` espelha `.tasks[]` fielmente e **não** lê `tasks.md`),
mas em como `.tasks[]` era escrito — um snippet `jq` hand-rolled na **prosa**
dos orquestradores (`§5.d.ter`), append **não-idempotente** que só rodava se o
LLM lembrasse de executá-lo a cada task. Quando o orquestrador comprimia a fase
`execute-task` em poucas ondas e pulava o append, as tasks sumiam em silêncio.
A correção introduz um caminho de escrita **auditado e idempotente**
(`record-task`) e, sobretudo, uma **rede de segurança determinística**
(`reconcile-tasks`) que deriva `.tasks[]` do `tasks.md` — o artefato que de fato
contém todas as tasks via checkboxes — em vez de depender da disciplina do LLM.
Mudança aditiva e retro-compatível (catálogo + runtime helper).

### Added

- **`global/skills/agente-00c-runtime/scripts/state-ondas.sh`** ganha dois
  subcomandos: **`record-task`** (upsert idempotente de uma entrada em
  `.tasks[]` por `task_id`; caminho atômico auditado com backup em
  `state-history/` + `sha256`; `--if-absent` não sobrescreve entrada real) e
  **`reconcile-tasks --tasks-md <path>`** (backstop determinístico: parseia o
  `tasks.md`, identifica toda task **concluída** — heading `### N.M` com TODAS
  as subtarefas-checkbox `[x]` — e back-filla via `record-task --if-absent`
  qualquer uma ausente de `.tasks[]`; tasks pendentes/bloqueadas/parciais ficam
  de fora para não fabricar `pass`/`fail`; `--dry-run` lista os faltantes).
  Campos `origem`/`recorded_at` são aditivos — a ingestão seleciona só os 8
  campos do contrato e ignora o resto.
- **`global/skills/review-task/SKILL.md` §4.6**: gate de completude
  `.tasks[] ↔ tasks.md`. Roda `reconcile-tasks --dry-run` (detecta divergência),
  depois apply (sana, idempotente), e reporta o finding
  `task-outcome-nao-gravado` quando o caminho ao vivo falhou. Read-only no
  passo 1, idempotente no passo 2 — seguro a cada review.

### Changed

- **`global/agents/agente-00c-orchestrator.md` e
  `agente-00c-feature-orchestrator.md`** (`§5.d.ter`): o snippet `jq`
  hand-rolled (`get` → `. + [$e]` → `set`) que escrevia `.tasks[]` foi
  substituído por uma chamada a `state-ondas.sh record-task` — idempotente por
  `task_id` (sem duplicatas mesmo se chamado repetidamente) e auditado. Cada
  bloco passa a documentar a rede de segurança `reconcile-tasks` como o backstop
  que garante completude. Comportamento backward-compatible.

### Tests

- **`tests/test_state-ondas.sh`** (+18 cenários): `record-task` (append,
  upsert idempotente, `--if-absent` sem clobber, acúmulo, sem onda em
  andamento, validações de `outcome`/`testes_passados ≤ rodados`/array de
  arquivos/flags obrigatórias) e `reconcile-tasks` (dry-run lista concluídas
  ausentes, ignora pendentes/bloqueadas, extração de título sem a tag de
  criticidade, não clobbera entrada real, idempotência, `tasks.md` ausente,
  flags obrigatórias). Cobre o pitfall `awk FNR==NR` com primeiro arquivo
  vazio (`.tasks[]` sem entradas) — corrigido com comparação por `FILENAME`.

## [4.3.4] - 2026-05-26

Corrige drift de contrato nos briefs do `cstk-panel`: o `event_type` da tabela
`events` era documentado como **conjunto fechado de 4 valores**
(`lock_contention`, `validation_failed`, `wave_retry`, `schedule_wait`),
omitindo `recall_consulted` (emitido pelo read-back loop em specify/plan desde
a v3.18.0). A ingestão em `recall.sh` trata `event_type` como **texto livre,
sem allowlist**, então o painel — construído sobre o contrato fechado — não
reconhecia `recall_consulted` e o exibia rotulado como `schedule_wait`. Fix
restrito à documentação de contrato (`docs/cstk-panel/*.md`); a fonte de verdade
(`state.json`) e a `knowledge.db` sempre armazenaram o valor fielmente.

### Fixed

- **`docs/cstk-panel/backend-brief.md`,
  `docs/cstk-panel/frontend-brief.md`**: contrato de `event_type` deixa de
  declarar "conjunto fechado de 4" e passa a documentá-lo como **texto livre**
  com conjunto conhecido de 5 (`+recall_consulted`). O contrato do `EventIcon`
  agora **exige fallback** para tipos desconhecidos (ícone genérico + rótulo =
  valor cru recebido), nunca recategorizando para um tipo conhecido. Fix
  recurrence-proof: como a ingestão não aplica allowlist, um 6º tipo futuro
  re-disparava o mesmo bug. Ação de deploy fica no repo do `cstk-panel` (remover
  qualquer ramo `default → schedule_wait` no `EventIcon`).

## [4.3.3] - 2026-05-26

Mitiga, na origem, o defeito que motivou a rede de segurança da v4.3.2: o
orquestrador (subagente) tratava o retorno de uma `Skill(...)` da fase como
fim de turno e parava cedo, abandonando o fechamento da onda, a ingestão na
`knowledge.db` e a emissão do `Schedule intent`. A v4.3.2 garantiu que a
ingestão acontecesse mesmo assim (camada determinística no comando-pai); esta
versão ataca a causa raiz no prompt dos orquestradores (camada que reduz a
frequência). Mudança aditiva, restrita ao catálogo (`global/agents/*.md`) —
propaga via `cstk update`. Fix de prompt é probabilístico e NÃO substitui a
rede de segurança da v4.3.2; as duas camadas coexistem.

### Fixed

- **`global/agents/agente-00c-orchestrator.md`,
  `agente-00c-feature-orchestrator.md`**: adicionada a seção "Contrato de
  conclusão de turno" antes do Loop principal, mais anotação no passo 5 (onde
  a Skill é invocada) e bullet anti-padrão. O contrato reframa o retorno de
  QUALQUER `Skill(...)` como o MEIO da onda (nunca o fim), define a linha
  `Schedule intent: ...` como o único token válido de fim de turno e prescreve
  uma auto-checagem ("a última linha que emiti é `Schedule intent:`?") antes
  de devolver controle ao comando-pai. Reduz a recorrência da parada precoce
  que deixava a onda sem fechar e a `knowledge.db` sem ingestão.

### Added

- **`tests/test_orchestrator-turn-completion.sh`**: trava de regressão (7
  cenários) que assegura a presença dos marcadores do contrato ("Contrato de
  conclusão de turno", "MEIO da onda", auto-checagem, reforço no passo 5) nos
  dois orquestradores. Registrada como interna em `tests/run.sh`
  (existence-guarded, não mapeia 1:1 a um script).

## [4.3.2] - 2026-05-26

Correção de robustez na memória de conhecimento cross-feature (`knowledge.db`).
A ingestão pós-onda vivia num único lugar — o passo `10.bis` do loop do
orquestrador, dentro do subagente. Quando o orquestrador retornava sem
completar o loop (parando cedo, antes de fechar a onda e emitir o `Schedule
intent`), o comando-pai recuperava o bookkeeping da onda mas não re-ingeria, e
a `knowledge.db` ficava vazia mesmo com o `state.json` sendo atualizado
normalmente. Esta versão adiciona uma rede de segurança de ingestão nos quatro
comandos-pai. Mudança aditiva e retrocompatível, restrita ao catálogo
(`global/commands/*.md`) — propaga via `cstk update`. Para backfill de uma
execução já rodada: `cstk recall --ingest --state-dir <state-dir>`.

### Fixed

- **`global/commands/feature-00c.md` (§5.bis), `feature-00c-resume.md`
  (§4.bis), `agente-00c.md` (§5.bis), `agente-00c-resume.md` (§8.bis)**: cada
  comando-pai agora executa `cstk recall --ingest` como rede de segurança logo
  após tratar o `Schedule intent`, garantindo que o conhecimento da onda chegue
  à `knowledge.db` mesmo quando o orquestrador retorna sem alcançar o passo
  `10.bis`. A chamada é idempotente (upsert por chave natural — re-ingestão
  após o `10.bis` é inofensiva), read-only sobre o `state.json` e degrada para
  no-op em qualquer falha (cstk fora do PATH, `sqlite3`/`jq` ausentes); nunca
  bloqueia o fechamento ou o agendamento da onda. Defesa-em-profundidade sobre
  o `10.bis` existente — não altera a causa raiz (orquestrador parar cedo).

## [4.3.1] - 2026-05-26

Correção de contrato da skill `review-task`. Ela é um relatório de status
READ-ONLY, mas a implementação ainda carregava a capacidade de escrever
arquivos e, ocasionalmente, criava um arquivo de relatório — fricção recorrente
nos dados de uso do `/insights` (o usuário precisava interromper para corrigir).
Esta versão alinha a implementação ao contrato sempre pretendido. Sem impacto
para quem usa a skill como relatório: o comportamento removido nunca foi
intencional.

### Fixed

- **`global/skills/review-task/SKILL.md`**: removido `Edit` de `allowed-tools`,
  de modo que a skill não tem mais capacidade de escrever ou criar arquivos
  (a criação de arquivo de relatório era comportamento não-intencional). Marcar
  tarefa como concluída em `tasks.md` permanece responsabilidade do
  `/execute-task`.

### Changed

- **`review-task/SKILL.md`**: adicionado invariante explícito de **contrato de
  saída** logo após a introdução — a skill emite o status na conversa (stdout) e
  nunca cria nem escreve arquivo de relatório, persistindo apenas quando o
  usuário pedir explicitamente.

## [4.3.0] - 2026-05-26

A skill `apply-insights` passa a consumir os dados do `/insights` nativo como
fonte PRIMÁRIA, em vez de depender de um resumo curado à mão (que ficava
desatualizado e podia ser de outro projeto). Mudança aditiva e retro-compatível
(degrada para o `.md` curado e depois para best-practices genéricas).

### Added

- **`global/skills/apply-insights/scripts/digest-facets.sh`**: agrega os facets
  per-sessão do `/insights` nativo (`~/.claude/usage-data/facets/*.json`) num
  digest markdown data-driven — distribuição de `goal_categories` e `outcome`,
  **`friction_counts` ranqueado** (sinal-chave para recomendações),
  `claude_helpfulness`, satisfação e **amostras de `friction_detail`** por tipo
  de fricção. Flags `--facets-dir`, `--samples N` (default 3) e `--top N`
  (default 15, corta a cauda longa de alta cardinalidade como `goal_categories`).
  `find -exec cat + | jq -s` evita ARG_MAX. **Degradação graciosa** (sem `jq`,
  diretório ausente, sem `*.json` ou `jq` falhando → exit 0 com stdout vazio).

### Changed

- **`apply-insights/SKILL.md`**: Step 1 reescrito com cadeia de fontes
  **facets digest → `~/.claude/insights/usage-insights.md` curado → genérico**,
  sempre preferindo o digest (atual, do projeto corrente) e informando ao
  usuário qual fonte foi usada. `description` e gotchas atualizados.

### Tests

- **`tests/test_digest-facets.sh`** (14 cenários): agregação, ranking
  descendente de fricção, cap `--top` da cauda longa, amostras de
  `friction_detail`, caso sem fricção, degradação (dir ausente/vazio, `jq`
  ausente via PATH shadow) e validação de argumentos (`--samples`/`--top`
  inválidos, arg desconhecido, `--help`).

## [4.2.0] - 2026-05-25

Enriquecimento da camada B do índice de conhecimento (`knowledge.db`) para
melhor observabilidade no futuro `cstk-panel`. Mudanças **aditivas e
retro-compatíveis**: o índice é derivado e reconstruível via
`cstk recall --reindex`; states e índices antigos seguem funcionando.

### Added

- **Coluna `tasks.titulo` (schema v3)**: a tabela `tasks` passa a guardar o
  título descritivo de cada task (do heading em `tasks.md`). Os orquestradores
  (`agente-00c` e `feature-00c`) gravam `.tasks[].titulo` ao registrar o
  outcome da task; a ingestão grava a coluna passando o valor por
  `secrets-filter.sh` (FR-017 — é o único campo de texto livre da camada B).
  Migração idempotente via `ALTER TABLE tasks ADD COLUMN titulo TEXT` em
  `recall_apply_schema`: índices v2 ganham a coluna **sem** precisar de
  `--reindex`; DBs novos já nascem com ela. Retro-compat: `.tasks[].titulo`
  ausente → `""`.
- **Evento `recall_consulted` + métrica de consultas ao histórico**: os
  orquestradores gravam um evento `recall_consulted` em `.eventos[]` a **cada**
  consulta do read-back loop (`cstk recall --context`) no início de
  `specify`/`plan` — **inclusive quando nada é retornado** (`hits=0`), caso que
  a Decisão `read-back PRE-DECISAO` não cobria (só registrada com `K>0`,
  FR-017). A métrica "quantas vezes o histórico foi consultado pelo
  orquestrador" = `COUNT(*) FROM events WHERE event_type='recall_consulted'`; a
  `descricao` carrega `etapa=… hits=N` para separar consultas produtivas das
  vazias. Sem mudança de schema (a ingestão de `events` aceita o tipo por
  convenção, sem allowlist). Best-effort: nunca gateia/aborta/atrasa a onda.

### Changed

- **`RECALL_SCHEMA_VERSION` 2 → 3** (apenas pela coluna `titulo`; o evento
  `recall_consulted` não altera schema).

### Tests

- `tests/cstk/test_recall.sh`: cobertura de `titulo` (scrub do segredo +
  retro-compat `""`), cenário `m13` da migração ALTER v2→v3 (coluna adicionada,
  linhas pré-existentes preservadas, idempotente) e `b23` da métrica
  `recall_consulted` (total + split produtivas/vazias). Asserts de
  `schema_version` atualizados para `3`.

## [4.1.1] - 2026-05-25

Correções na camada de memória cross-feature (`cstk recall`). Afetam apenas
`cli/lib/recall.sh` — o índice (`~/.claude/cstk/knowledge.db`) é derivado e
reconstruível via `cstk recall --reindex`. Sem mudança de schema.

### Fixed

- **Feature gravada como `unknown` no índice quando `state.json` não tem
  `short_name`**: a ingestão derivava o nome da feature apenas de
  `.short_name`. States legados sem o campo (gravados antes de o `init`
  versioná-lo) caíam no fallback `"unknown"`. Agora a resolução: (1) tolera
  `.execucao.short_name` além de `.short_name`; (2) quando ausente, deriva o
  short-name do diretório-pai no layout `feature-00c-state/<short-name>/`
  (checagem por componente — robusta para caminhos relativos e absolutos).
  O layout `agente-00c-state/` continua `unknown` por design (o orquestrador
  de projeto não grava `short_name` — anti-eco FR-011).
- **`--reindex` podia ESVAZIAR o índice (perda de dados)**: o `find` de
  descoberta de states, ao varrer uma raiz ampla (ex.: `$HOME` default), sai
  com status ≠0 ao tocar diretórios sem permissão — **mesmo tendo impresso
  matches válidos**. O idioma `find ... || _rx_states=""` descartava esses
  matches; como o reindex apaga o DB antes de repopular, o índice terminava
  vazio. Trocado por `|| :`, que preserva o stdout já capturado pela
  command-substitution.

### Tests

- `tests/cstk/test_recall.sh`: `scenario_16` (resolução de feature com
  `short_name` ausente — fallback por diretório, `.execucao.short_name`,
  caminho relativo, e `agente-00c-state` → `unknown`) e `scenario_17`
  (reindex preserva matches quando `find` sai ≠0).

## [4.1.0] - 2026-05-24

Melhorias de tooling de desenvolvimento (não afetam o tarball de release nem
o usuário instalado — apenas `tests/`, `.github/` e `.shellcheckrc`). O tarball
de catálogo é idêntico em conteúdo ao da v4.0.0; esta release é um marco de
repo (sincroniza CHANGELOG/tag) e gate de CI.

### Added

- **`tests/run.sh --fast` / `--slow`**: split da suite por velocidade. `--fast`
  pula a allowlist de tests lentos (`_is_slow_test`, derivada de medição — 11
  tests > ~5s somando ~177s de ~260s) e roda em ~1/3 do tempo; `--slow` roda só
  os lentos. Mutuamente exclusivos; compõem com PATTERN e `--list`/`--stats`.
- **`tests/run.sh --stats`**: agrega contagem de scenarios por arquivo (desc) +
  total. Respeita PATTERN e o filtro de velocidade.
- **`tests/test_run-modes.sh`**: cobertura dos novos modos (registrado como
  teste interno em `_is_internal_test`).
- **CI shellcheck advisory** (`.github/workflows/shellcheck.yml`): lint estático
  dos `.sh` em PR + push main, **não-gateante** (`continue-on-error`). Config de
  ruído sistêmico em `.shellcheckrc` (disable SC1091/SC2016/SC2148).

## [4.0.0] - 2026-05-24

**BREAKING** — feature `model-routing-por-onda`. O model-routing dos
orquestradores autônomos (`agente-00c`/`feature-00c`) **deixa de ser
audit-only**: o modelo escolhido agora **É APLICADO** à execução. Isto
**revoga a cláusula FR-017** da feature original `agente-00c-model-routing`
(v3.15.0), cuja premissa de que "o harness não aceita `model` no spawn,
logo a escolha é apenas auditoria" ficou **obsoleta** — o harness atual
aceita `model` no spawn de subagente (precedência sobre o frontmatter).
O gatilho do routing deixa de ser o caminho raro do spawn de clarify e
passa a ser **toda onda** do pipeline.

Por que MAJOR: muda o **contrato de comportamento** do orquestrador
(antes: sugere e audita, nunca aplica; depois: aplica por onda). Para
ativar o comportamento novo é preciso **build + install** da fonte
(`global/...`) — passo manual do operador; o tarball publicado é que
carrega o efeito. Camada de telemetria/auditoria permanece
retro-compatível (execuções antigas sem Decisão por-onda continuam
legíveis pelo agregador).

### Changed (BREAKING)

- **Mecanismo PRIMÁRIO — mapa fase→modelo por onda** (FR-014): novo
  `model-routing.sh wave-select --state-dir <SD>` resolve a fase (via
  `--etapa` ou `.etapa_corrente`) e retorna o modelo a **aplicar** na
  onda, com base no mapa versionado e determinístico
  `global/skills/agente-00c-runtime/references/phase-model-map.txt`
  (POSIX-puro, sem `jq`). Recorte default "3 faixas balanceado":
  `plan`/`analyze`/`constitution`→**opus**;
  `specify`/`clarify`/`checklist`/`create-tasks`/`briefing`→**sonnet**;
  `execute-task`→**sonnet** (piso refinável); `validate-docs`/`review-task`→**haiku**;
  fase não listada → `manter-atual` (FR-020 — nunca erro, evolução tolerada).
- **Aplicação no spawn de clarify** (US2, FR-003): o passo 8 da sequência
  pré-spawn passa `model=<escolha>` à tool Agent quando acionável
  (`escolha` ∈ {haiku,sonnet,opus} e `score >= 2`); em fallback/
  `manter-atual`/`score<2` o `model` é omitido e o subagente herda o
  `model:` do frontmatter. O par Decisão⟷spawn permanece 1-para-1
  (Invariante I1): a aplicação **não** cria 2a Decisão.
- **Documentação revogando o audit-only** (FR-017): banner de
  **supersessão** na spec arquivada `docs/specs/_archived/agente-00c-model-routing/spec.md`
  (Status + FR-017 + Princípio V + Out-of-Scope anotados); seção
  model-routing do `CLAUDE.md` reescrita (aplicação por onda + tabela
  fase→modelo + ordem de precedência); blocos pré-spawn dos dois agent
  files (`agente-00c-orchestrator.md`, `agente-00c-feature-orchestrator.md`)
  corrigidos para refletir aplicação (eliminadas as contradições internas
  com a nota FASE 5); `review-task/SKILL.md` ajustado.

### Added

- **`model-selector` como camada de REFINO** (FR-001/FR-019, US4): roda
  **só em `execute-task` com `--task-text`**, sobre o piso do mapa
  (sonnet), podendo **elevar→opus** (tarefa profunda) ou **rebaixar→haiku**
  (tarefa trivial). Catálogo de sinais (`global/skills/model-selector/references/sinais.md`)
  expandido além do MVP com vocabulário de fase/complexidade, coberto por
  corpus de teste (`tests/fixtures/model-selector-corpus/corpus.tsv`).
- **Precedência de resolução do modelo da onda**:
  `override manual (FR-016) > escalada mid-onda→opus (FR-015) > refino model-selector > mapa fase→modelo`.
  Override do operador via Decisão manual pré-onda lida pelo resume;
  escalada mid-onda via `.escalada_modelo_pendente=true` gravado pela onda
  anterior (sinaliza subestimação).
- **Idempotência por onda** (FR-008): `wave-select` ecoa o modelo já
  aplicado e **não** registra 2a Decisão quando já existe
  `DecisaoDeRoteamentoPorOnda` para a onda corrente (seguro em resume).
- **Auditoria sugerido-vs-aplicado** (US3, FR-012/SC-006):
  `model-routing-report.sh aggregate` ganha 2a seção "Seleção por onda —
  sugerido vs aplicado" (distribuição do modelo aplicado, por origem
  mapa/refino/override/fallback, taxas de fallback e override, contagem de
  divergências sugerido≠aplicado com `rotuladas`/`sem rotulo`). `sem rotulo`
  DEVE ser 0 (`review-task` escala finding `model-routing-divergencia-sem-rotulo`).
- **Integração nos commands** (FASE 3): `agente-00c`/`feature-00c` +
  respectivos `*-resume` aplicam o `wave-select` no início de cada onda e
  leem override manual pré-onda.
- **Cobertura de teste**: `tests/test_model-routing.sh`,
  `tests/test_model-routing-report.sh`,
  `tests/test_command-spawn-model-routing.sh`,
  `tests/test_orchestrator-spawn-model-apply.sh`,
  `tests/test_state-decisions-reconcile.sh`,
  `tests/cstk/test_model_selector_corpus.sh`, fixtures de state com routing
  por onda (mixed + unlabeled-divergence).

## [3.19.1] - 2026-05-24

Correções de coerência pós-`3.19.0`, sem mudança de comportamento do produto
(documentação + tooling de testes). Não altera o conteúdo funcional do tarball.

### Fixed

- **CHANGELOG — footer-links da série 3.x**: o rodapé de links de versão só
  cobria `1.0.0`/`1.1.0`/`2.0.0`; toda a série 3.x (28 versões, incluindo a
  própria `3.19.0`) estava sem link. Bloco regenerado a partir dos headings
  (formato `releases/tag/vX.Y.Z`, ordem descendente) — agora **31 headings =
  31 links**, consistente com a convenção Keep a Changelog.
- **`tests/run.sh --check-coverage` — falsos órfãos**: o check saía com
  exit 1 por 3 órfãos-de-script (`_log.sh`, `_state-dir.sh`, `classify.sh`) +
  27 órfãos-de-test que, na verdade, **possuem cobertura** — apenas sob tests
  de nome descritivo que não casa a convenção 1:1 `test_<base>.sh` (tests
  granulares de `model-selector` e tests de aspecto como
  `runtime-log-redaction`, `secrets-filter-backup`, `skills-cache-protocol`,
  `update-extra-kinds`, `state-dir-parametrization`). Adicionada allowlist
  coerente nos dois lados (`_is_internal_test` para tests +
  `_is_covered_by_named_test` para scripts), **cada isenção exigindo que o
  cobridor exista em disco** (anti-ponto-cego: se o script/test sumir, volta a
  ser órfão real). Resultado: `./tests/run.sh` → `ORPHANS: 0` (sem falso WARN) e
  `--check-coverage` → exit 0. Suíte completa 1043/0/0, sem regressão.

## [3.19.0] - 2026-05-24

Expande a **ingestão da memória de conhecimento** (`cstk recall`) para derivar
métricas de dashboard a partir do `state.json` transacional, **sem nunca
tocá-lo** (somente leitura) e **sem quebrar a propriedade de índice derivado**
(tudo reconstruível via `cstk recall --reindex`). O índice
(`~/.claude/cstk/knowledge.db`) sobe de **schema v1 → v2** de forma **aditiva e
retro-compatível** (`CREATE TABLE IF NOT EXISTS`): nenhuma das 4 tabelas
textuais existentes (`decisions`/`bloqueios`/`retros`/`skills`) muda de
semântica, e bases v1 instaladas migram em silêncio na primeira ingestão. Esta
feature prepara o terreno para um futuro `cstk-panel` (dashboard read-only,
**fora de escopo**): este repositório passa a ser a fonte da verdade das
métricas que o painel consumirá. Camada estritamente aditiva, best-effort,
read-only — nenhum breaking change nos modos existentes
(`search`/`--ingest`/`--reindex`/`--context`).

### Added

- **Camada A — métricas derivadas** em `cli/lib/recall.sh`: 3 novas tabelas
  ingeridas a partir de `.execucao`, `.ondas[]`, `.metricas_acumuladas`,
  `.orcamentos` e `.historico_movimento_circular` do `state.json`:
  - `executions` — uma linha por execução (proveniência project/feature/id,
    status, motivo de término filtrado, duração derivada; `NULL` quando
    `em_andamento`).
  - `waves` — uma linha por onda (ciclo de vida, `tool_calls`,
    `wallclock_seconds`, motivo de término).
  - `alert_signals` — uma linha por sinal de alerta (circular, budget breach),
    idempotente e tolerante a negativos.
  Métricas adicionais (latência humana de bloqueios, clarify-rate, mix de
  roteamento de modelos) ficam **deriváveis** a partir das tabelas — o mix de
  modelos permanece delegado ao agregador `model-routing-report.sh`.
- **Camada B — instrumentação** em `cli/lib/recall.sh` + nos dois
  orquestradores (`global/agents/agente-00c-feature-orchestrator.md` e
  `agente-00c-orchestrator.md`): 2 novas tabelas alimentadas por campos
  **aditivos** do `state.json`:
  - `tasks` — outcome por task (`outcome` pass|fail, testes rodados/passados,
    `lint_ok`, `arquivos_tocados`), chave natural
    `(project, feature, execucao_id, task_id)`.
  - `events` — eventos do ciclo de execução. Campos `.tasks[]`/`.eventos[]`
    gravados pelo **mesmo caminho de runtime auditado** dos demais writes —
    nenhum mecanismo de escrita novo (contract layer-b §5).
- **`schema_version` do índice 1 → 2** (registrado em `schema_meta`); migração
  aditiva e idempotente.

### Notes

- **Índice puramente derivado (FR-001/FR-002)**: a ingestão lê o `state.json`
  somente em modo leitura (`jq -r` + `wc -c`); auditoria empírica confirma zero
  write-back ao `state.json` e confinamento de `sqlite3` exclusivamente em
  `cli/lib/recall.sh` (FR-004). Base inteira reconstruível via `--reindex`.
- **Degradação graciosa (FR-003)**: ausência de `sqlite3`/`jq` nunca aborta a
  ingestão nem a onda — sai com status 0 emitindo aviso.
- **Idempotência (FR-008)**: toda escrita de entidade nova é idempotente por
  chave natural; re-ingerir a mesma execução não altera o índice.
- **Segredos (FR-006)**: todo texto livre persistido passa pelo filtro de
  segredos antes do `INSERT`.
- Spec: [`docs/specs/knowledge-db-metrics/`](docs/specs/knowledge-db-metrics/);
  contratos em
  [`contracts/recall-ingest-schema.md`](docs/specs/knowledge-db-metrics/contracts/recall-ingest-schema.md)
  e
  [`contracts/layer-b-instrumentation.md`](docs/specs/knowledge-db-metrics/contracts/layer-b-instrumentation.md).

## [3.18.0] - 2026-05-23

Fecha o **read-back loop** da memória de conhecimento cross-feature: até
v3.17.0 os orquestradores apenas ESCREVIAM no índice (`cstk recall --ingest`);
agora também LEEM de volta. Um novo modo `cstk recall --context` consulta o
índice (FTS5/bm25) com os termos da feature corrente e devolve um bloco
markdown enxuto pronto para injeção em prompt; os orquestradores `agente-00c`/
`feature-00c` o invocam num passo PRE-DECISAO no início das fases `specify` e
`plan`, injetando aprendizado de execuções passadas antes de decidir. Camada
estritamente aditiva, best-effort, read-only — nenhum breaking change nos modos
existentes (`search`/`--ingest`/`--reindex`).

### Added

- **Modo `cstk recall --context "<termos>"`** em `cli/lib/recall.sh`
  (`recall_mode_context`): retorna um ContextBlock markdown (`> Aprendizado
  recuperado (read-back loop) — K achados...` + uma linha por achado com
  proveniência `project/feature/wave (ts): body`). Flags: `--limit N`
  (default **4**), `--exclude-feature NAME` (anti-eco no SQL), `--max-bytes N`
  (default **2000**, corte por achado inteiro), `--type`/`--project`/`--db`
  (iguais ao modo busca). Composição **OR** entre termos (novo helper
  `fts_query_escape_or`, reusa `fts_phrase_escape`) — o modo busca permanece
  AND-implícito.
- **Passo PRE-DECISAO (read-back loop)** nos dois orquestradores
  (`global/agents/agente-00c-feature-orchestrator.md` e
  `agente-00c-orchestrator.md`): dispara somente em `specify`+`plan`, deriva
  termos de `aspectos_chave_iniciais` (≤8, fallback `projeto_alvo_descricao`),
  injeta o bloco com rótulo **UNTRUSTED / não-autoritativo** (defesa
  prompt-injection ASI09/LLM01) e registra Decisão auditável quando K>0
  (sem persistir o body bruto recuperado).

### Security

- Conteúdo recuperado pelo modo `--context` já foi *scrubbed* na ingestão
  (`secrets-filter.sh`) — o consumo não re-scrub (seguro por construção). NUL
  rejeitado em qualquer input; anti-eco aplicado no SQL via `sql_escape` (sem
  bypass por valor manipulado); injeção SQL/FTS tratada como literal.

### Notes

- `cstk recall --context` é **read-only** e **best-effort**: toda degradação
  (sem `sqlite3`, índice ausente/corrompido, zero achados, query degenerada)
  resulta em no-op silencioso (stdout vazio, exit 0) — nunca gateia uma onda.
  O teto de tempo (US3-3) é satisfeito pelo `.timeout 5000` do SQLite + a
  natureza best-effort, sem `timeout` wrapper dedicado (POSIX sh puro).
- Cobertura: 22 cenários novos em `tests/cstk/test_recall.sh` (modo `--context`
  faz parte de `recall.sh`, sem arquivo de teste órfão), rodados sob HOME real
  e HOME falso.

## [3.17.0] - 2026-05-23

Adiciona a camada aditiva de memória de conhecimento cross-feature: um índice
SQLite global (`~/.claude/cstk/knowledge.db`, FTS5) alimentado por um hook
best-effort no fim de cada onda dos orquestradores `agente-00c`/`feature-00c`,
e o novo comando `cstk recall` para busca cross-projeto/feature com
proveniência. O índice é puramente derivado — o `state.json` transacional
permanece a fonte de verdade, intacto, fora do caminho crítico. Sem breaking
changes.

### Added

- **Comando `cstk recall`** em `cli/lib/recall.sh` (POSIX sh + `jq` +
  `sqlite3`), com três modos:
  - **busca** (default): `cstk recall <query> [--project P] [--type T]
    [--limit N] [--db PATH]` — full-text via FTS5/bm25 sobre decisões,
    bloqueios, retro-execuções e skills invocadas, ordenado por relevância e
    exibindo proveniência (projeto / feature / onda / data). `--type` aceita
    `decision|bloqueio|retro|skill`; `--limit` exige inteiro positivo (default
    20).
  - **ingestão** (`--ingest --state-dir DIR`): extrai os registros de um
    `state.json` e faz upsert idempotente no índice (filtrado por
    `secrets-filter` antes da escrita). É o hook chamado no fim de onda.
  - **reconstrução** (`--reindex [--states-root DIR]`): reconstrói o índice a
    partir dos `state.json`/`state-history` existentes, tornando a base
    totalmente descartável e regenerável.
- **Hook de fim de onda** documentado em ambos os orquestradores
  (`agente-00c-orchestrator` e `agente-00c-feature-orchestrator`): após o
  backup filtrado da onda, invoca `cstk recall --ingest` em modo best-effort.
- **Segurança de entrada** em `recall.sh`: escaping em duas camadas (literais
  SQL via duplicação de aspas simples + tokens FTS5 via duplicação de aspas
  duplas), validação de `--limit` como inteiro, e rejeição/strip de bytes NUL.
- **Degradação graciosa**: a ausência de `sqlite3` ou `jq` nunca aborta uma
  onda — o hook e o `recall` saem com status 0 emitindo um aviso. O índice é
  isolado em `~/.claude/cstk/`, separado do estado transacional por projeto.
- **Cobertura**: 20 cenários em `tests/cstk/test_recall.sh` (quickstart 1-14,
  detector/strip de NUL, degradação sem `sqlite3`/`jq`, índice corrompido,
  reindex, adversariais e concorrência), `shellcheck -s sh` limpo. Spec em
  `docs/specs/cstk-knowledge-db/`.

## [3.16.0] - 2026-05-23

Adiciona a skill `decision-tree`, que gera um relatório HTML interativo em
forma de árvore de decisão a partir do `state.json` de uma execução
`agente-00c`/`feature-00c`. Inclui correção de conformidade (Princípio I e III
da constitution) e habilita a skill no profile `complementary`. Sem breaking
changes.

### Added

- **Skill `decision-tree`** em `global/skills/decision-tree/`: o script POSIX
  `render-decision-tree.sh` (subcomando `render --state PATH [--output FILE]
  [--title STR]`) extrai `.decisoes[]` via `jq` e injeta num template HTML
  autocontido (SVG + painel de detalhe + zoom, abre offline sem CDN). O tronco
  verde liga cronologicamente a `escolha` de cada Decisão à seguinte, de
  `dec-001` até um nó de conclusão. Invariantes IDT-1 (read-only), IDT-2
  (determinístico byte-a-byte), IDT-3 (POSIX puro), IDT-4 (render no cliente).
  Cobertura: 18 cenários em `tests/test_render-decision-tree.sh`,
  `shellcheck -s sh` limpo.
- **`complementary:decision-tree`** em `scripts/profiles.txt.in`: a skill agora
  é instalada por `cstk install --profile complementary` (e por `--profile
  all`). Antes só aparecia no profile auto-gerado `all`.
- **Spec retroativa** em `docs/specs/decision-tree/` (`spec.md` + `tasks.md`):
  ratifica o contrato já implementado para conformidade com o Princípio I (SDD
  recursivo) da constitution.

### Fixed

- **Seção `## Gotchas` ausente** em `global/skills/decision-tree/SKILL.md`
  (violava o Princípio III — "um SKILL.md sem Gotchas é incompleto" — e o
  quality gate `grep -L '## Gotchas'`). Adicionadas armadilhas reais: `jq`
  mandatório sem fallback, escape obrigatório de `</`, `escolha` fora das
  opções, proibição de timestamp no payload (IDT-2) e de CDN externo.
- **`model-selector` órfã de profile**: a skill (v3.14.0), consumida pelos
  orquestradores no passo 1 do model-routing, só estava no profile
  auto-gerado `all`. `cstk install` (default `sdd`) instalava os orquestradores
  mas deixava o fluxo de model-routing sem a skill que ele invoca. Adicionada a
  `sdd:model-selector` e `complementary:model-selector` em
  `scripts/profiles.txt.in` (mesma razão de `agente-00c-runtime`).

## [3.15.0] - 2026-05-23

Entrega da feature `agente-00c-model-routing` via pipeline SDD
autonoma `/feature-00c` em 21 ondas com 42+ decisoes auditaveis.
Integra a skill standalone `model-selector` (v3.14.0) aos
orquestradores autonomos `agente-00c` e `feature-00c` no spawn de
subagentes via tool Agent (clarify-asker + clarify-answerer),
registrando Decisao auditavel + entrada em
`.ondas[N].skills_invoked[]` por spawn. Sem breaking changes.

### Added

- **Helper POSIX `model-routing.sh`** em
  `global/skills/agente-00c-runtime/scripts/`: 3 subcomandos
  (`template`, `invoke`, `idempotent-check`) implementando
  invariantes INV-1..INV-6 do contract. `template` emite payload
  determinista para input do `model-selector`; `invoke` orquestra
  classify+register+skill-invoked em uma transacao atomica via
  state-lock; `idempotent-check` rejeita re-spawn com mesmo input
  (mesmo `decisao-id` + mesmo input-hash). Cobertura: 94 cenarios
  shell em `tests/test_model-routing.sh`, `shellcheck -s sh` limpo.
- **Reconciliador `state-decisions-reconcile.sh`** em
  `global/skills/agente-00c-runtime/scripts/`: 2 subcomandos
  (`detect`, `repair`). Resolve **half-records** (decisao sem
  entrada em `skills_invoked[]` ou vice-versa) detectados em
  retomadas pos-crash. `--dry-run` lista divergencias sem mutar;
  `--apply` reescreve mantendo append-only via merge auditavel.
  Cobertura: 11 cenarios em `tests/test_state-decisions-reconcile.sh`.
- **Agregador `model-routing-report.sh aggregate`** em
  `global/skills/agente-00c-runtime/scripts/`: consome state.json e
  emite tabela markdown (total de roteamentos, distribuicao por
  modelo `haiku|sonnet|opus|manter-atual`, taxa de fallback,
  half-records pendentes — deve ser 0). Consumido pelo
  `review-task` para auditoria de cobertura de model-routing.
  Cobertura: 17 cenarios em `tests/test_model-routing-report.sh`.
- **Integracao em `agente-00c-orchestrator.md` §5.e.bis**: nova
  secao "Roteamento de modelos pre-spawn" com sequencia 8-step e
  invariantes I1 (toda decisao gera skill_invoked match), I2 (toda
  retomada checa half-records), I3 (idempotencia por input-hash).
  Analogo em `agente-00c-feature-orchestrator.md`.
- **Auditoria em `review-task/SKILL.md` §4.5**: nova subsecao
  "Model-routing coverage" — review-task agora chama
  `model-routing-report.sh aggregate` e reporta saude do roteamento
  (cobertura de spawns, taxa de fallback, half-records).
- **Spec SDD completa** em
  `docs/specs/agente-00c-model-routing/`: spec.md (20 FRs),
  plan.md, research.md, data-model.md, quickstart.md, tasks.md
  (~100 tarefas em 7 fases), contracts/
  (`model-routing-helper.md` com 6 invariantes,
  `orchestrator-integration.md`), checklists/requirements.md
  (50 items, 4 load-bearing CHK032/CHK047/CHK048/CHK050).

### Fixed

- **Performance: watcher subshell leak** (descoberto durante
  execucao da feature): scripts internos do agente-00c-runtime
  spawnavam subshells de watcher em loop sem cleanup, causando
  ~16.8x overhead em ondas longas. Corrigido com trap EXIT
  explicito + PID tracking. Impacto: ondas de execute-task longas
  (>10min) agora finalizam ~17x mais rapido.

### Changed

- `review-task/SKILL.md` ganhou §4.5 (model-routing audit). Demais
  secoes inalteradas — comportamento backwards-compatible quando
  state.json nao tem `skills_invoked[]` com entries do model-selector.

## [3.14.0] - 2026-05-22

Tres entregas principais: (1) skill `model-selector` completa via
pipeline SDD autonoma, (2) Fases 1+2 da feature `artifact-cache`
(primitiva `state-cache.sh` + protocolo de leitura nas 4 skills SDD
principais), (3) otimizacoes de tokens/boot via trim de descriptions
em skills, commands e custom agents. Sem breaking changes.

### Added

- **Skill `model-selector`** (PR #17): sugestor de modelo
  (`haiku`/`sonnet`/`opus`) por heuristica POSIX pura.
  `scripts/classify.sh` (560+ linhas) classifica o input do operador em
  rasa/media/profunda e emite output markdown em 4 secoes fixas, com
  fallback `manter-atual` quando indeterminado (input <3 tokens ou
  empate de pesos). `scripts/report.sh` (118 linhas) agrega varias
  classificacoes via branch jq happy-path + fallback awk
  **byte-identical** (FR-010a — carve-out de optional-deps).
  Catalogo de sinais extensivel sem patch em `references/sinais.md`
  (15 verbos MVP, peso=1). Rotulos sempre abstratos — nunca versao
  concreta de modelo. 22 testes shell (~127 cenarios PASS),
  `shellcheck -s sh` limpo, `SKILL.md` <200 linhas. Entregue via
  pipeline SDD autonoma `/feature-00c` em 23 ondas com 100 decisoes
  auditaveis.
- **Protocolo de leitura cache em skills SDD (Fase 2 de
  artifact-cache)** (PR #16): `specify`, `clarify`, `plan` e
  `execute-task` agora consultam `state-cache.sh read` antes de ler
  briefing/constitution do disco, com fallback transparente. Reduz
  ~5-10k tokens/onda em pipelines longos do `agente-00c`/
  `feature-00c`. Hash-validation TOCTOU-safe via `_hash.sh`; skills
  standalone (sem state.json) preservam comportamento original.
- **Primitiva `state-cache.sh` + `_hash.sh` (Fase 1 de
  artifact-cache)** (PR #15): novo helper POSIX em
  `global/skills/agente-00c-runtime/scripts/state-cache.sh` com 6
  subcomandos (`init`, `read`, `write`, `invalidate`, `status`,
  `gc`) operando sobre namespace `artifact_cache` em `state.json`.
  Extensao `state-validate` aceita o novo schema. Helper sourceable
  `_hash.sh` centraliza calculo de SHA-256 com fallback
  `sha256sum`/`shasum`/`openssl`/awk.

### Added (drafts SDD — sem implementacao)

- **Feature SDD `agente-00c-artifact-cache`** drafts iniciais em
  `docs/specs/agente-00c-artifact-cache/`:
  - `spec.md` — feature spec completa com 4 User Stories
    (P1/P1/P2/P2), 17 Functional Requirements (FR-CACHE-001..017),
    Edge Cases, Constitutional Alignment, 5 Success Criteria,
    Out of Scope, e 5 Open Questions para `/clarify`.
  - `plan.md` — plano tecnico provisorio com Constitution Check,
    Data Model (state.json novo schema), API Contracts da primitiva
    nova `state-cache.sh` (6 subcomandos), Research (5 decisoes),
    Project Structure, Phase plan, Risks.
  - `tasks.md` — 20 tarefas em 5 fases (Clarify → Primitiva+schema →
    Skills → Orquestrador+report → Integracao+release), matriz de
    dependencias, coverage matrix Requirements×Tasks.
- Proposito: reduzir ~5-10k tokens/onda em pipelines longos do
  agente-00c via cache opcional de briefing.md + constitution.md
  em `state.json`, com hash-validation TOCTOU-safe e fallback
  preservado para skills standalone.
- Implementacao real fica deferida apos `/clarify` resolver as 5
  Open Questions.

### Changed

- **Slash commands + custom agents descriptions**: trim YAML `description:`
  em todos os 6 slash commands (`global/commands/`) e 6 custom agents
  (`global/agents/`). Reducao de ~5.245 chars para ~2.569 chars (~669 tokens
  economizados por boot, -51%). Triggers e discriminadores chave preservados
  (clarify-asker vs answerer, orchestrator vs feature-orchestrator, etc).
  Detalhes operacionais e flags permanecem no body de cada arquivo (so
  carrega quando o comando/agente e efetivamente invocado). Continuacao da
  otimizacao iniciada em PR #8 (skills); combinada, total ~2k tokens/boot.
  PR #9.
- **Skill descriptions**: trim YAML `description:` em todas as 21 skills de
  `global/skills/` (de ~10k chars / ~2.560 tok para ~4.6k chars / ~1.150 tok
  no contexto eager-loaded). Reducao de 54% nos descriptions, ~1.350 tokens
  economizados por boot. Triggers (frases em aspas) preservados — routing
  inalterado. Detalhe sobre frameworks, listas longas e clausulas
  "NAO use para X" extensas migrado para o body do `SKILL.md`
  (so carrega quando a skill e invocada). Otimizacao para reduzir custo
  por onda em pipelines longos (`agente-00c`, `feature-00c`). PR #8.

## [3.13.0] - 2026-05-20

Feature-00C — variante do agente-00C focada em **uma feature
individual** dentro de projeto que JA tem `briefing.md` +
`docs/constitution.md` ratificados. Reusa integralmente o runtime
POSIX do agente-00c via parametrizacao retrocompativel (zero
mudancas em comportamento do `/agente-00c`). Bump MINOR — nenhuma
breaking change.

### Added

- **3 slash commands**: `/feature-00c "<descricao>" [<short-name>]`
  (invocacao), `/feature-00c-resume <short-name>` (retomada com hash
  validation TOCTOU-safe), `/feature-00c-abort <short-name>` (aborto
  manual com SIGTERM + grace period 60s).
- **3 agentes custom**: `agente-00c-feature-orchestrator` (pipeline
  7-fases: specify → clarify → plan → checklist → create-tasks →
  execute-task → review-task), `feature-00c-clarify-asker`,
  `feature-00c-clarify-answerer` (algoritmo de score 0..3 identico
  ao 00c, mas 3a fonte = spec_corrente em vez de stack_sugerida).
- **Pre-flight `feature-00c-preflight.sh`** (FR-010A): valida hashes
  briefing + constitution registrados em state.json contra arquivos
  em disco; distingue MAJOR drift (bloqueio compulsorio) de
  MINOR/PATCH (aviso opcional). Output JSON estruturado.
- **Filtro de secrets estendido** (FR-029 §extensao + FR-036):
  `secrets-filter.sh for-backup` gera backups por onda com hash
  auto-registrado (`state_sha256_self`) sobre conteudo filtrado;
  `_log.sh` aplica filtro em stderr/stdout via helper sourceable
  com fallback `[NO-FILTER]` graceful.
- **§Quality Gates complementares** no
  `agente-00c-feature-orchestrator.md` (alinhamento com PR #6 /
  v3.12.0): integra `validate-documentation` (apos specify+plan),
  `owasp-security` (apos plan, findings critical/high =
  BloqueioHumano OBRIGATORIO) e `validate-docs-rendered` (apos
  create-tasks) como gates pos-artefato auditaveis.
- **`gate-finding` e `gate_skipped`** como `kind` validos de Decisao
  (`data-model.md` §Decisao). `/review-task` audita features com
  >2 skips sem justificativa como `quality-gate-bypass`.
- **Helper sourceable `_state-dir.sh`**: resolve diretorio de
  estado via precedencia `--state-dir arg > AGENTE_00C_STATE_DIR
  env > erro`. Inclui `_sd_flavor_to_report_name` para nomes
  canonicos por flavor (agente-00c | feature-00c).
- **Roundtrip empirico de secrets** documentado em
  `docs/specs/feature-00c/validation-runs/roundtrip-secrets-2026-05-20.md`
  — 7 checks PASSED empiricamente (contrato de privacidade da
  feature-00c validado).

### Changed

- **README.md**: nova subsecao "Feature-00C — Variante de escopo de
  feature individual" sob a secao Agente-00C, documentando os 3
  comandos novos + coexistencia com agente-00c.
- **`global/skills/agente-00c-runtime/SKILL.md`**: description
  atualizada mencionando os DOIS orquestradores que consomem o
  runtime; 3 secoes novas + 4 Gotchas cobrindo as adicoes.
- **21 scripts POSIX do agente-00c-runtime**: refactor de
  parametrizacao confirmado como majoritariamente DESNECESSARIO
  (auditoria empirica em
  `global/skills/agente-00c-runtime/scripts/_audit-paths.md`:
  18/21 ja aceitavam `--state-dir` desde v1.0).

### Tests

- **+33 cenarios POSIX** na suite global (de 651 → 672 PASS):
  - `tests/test_state-dir-parametrization.sh` (12 cenarios)
  - `tests/test_feature-00c-preflight.sh` (7 cenarios)
  - `tests/test_secrets-filter-backup.sh` (8 cenarios)
  - `tests/test_runtime-log-redaction.sh` (6 cenarios)
- **Template de cenarios manuais** em
  `docs/specs/feature-00c/validation-runs/quickstart-2026-05-20.md`
  (12 cenarios incluindo roundtrip empirico + gate-finding).

### Backward compatibility

- Zero breaking changes. `/agente-00c` continua funcionando
  bit-a-bit identico.
- Refactor de runtime e 100% retrocompativel — comportamento
  default preservado sem env var.
- Suite POSIX completa: 672 PASS / 0 FAIL / 0 ERROR / ~140s.

### Detalhamento

[`docs/specs/feature-00c/`](./docs/specs/feature-00c/): 37 FRs, 14
SCs, 11 user stories, plan + research (7 Decisions Phase 0), data-
model (8 entidades), 2 contracts (cli-invocation + report-format),
2 checklists (requirements 35 items, security 40 items), quickstart
(12 cenarios), validation-runs (coverage + quickstart-template +
roundtrip empirico).

## [3.12.0] - 2026-05-20

Auditoria estrategica de skills "complementares" do toolkit. Skills sem
referencia em nenhum orquestrador ou skill orquestradora eram codigo
morto — discoverable so via trigger phrase manual, e raramente
acionadas na pratica. Esta release toma decisao explicita skill-por-skill:
incentivar (integrando aos orquestradores), depreciar (com remocao
agendada), ou remover (quando project-specific demais para o toolkit).

### Added

- **Principio formal de escopo do toolkit** (README §Contribuindo):
  skills publicadas em `global/skills/` ou `language-related/<stack>/skills/`
  NAO devem nomear clientes/projetos especificos. Skills com forte
  acoplamento a um projeto pertencem ao proprio projeto, em
  `<projeto>/.claude/skills/`. Caso historico: `create-report`.
- **Quality Gates SDD no orchestrator** (`agente-00c-orchestrator.md`
  secao 5.f): 3 skills antes orfas (`validate-documentation`,
  `validate-docs-rendered`, `owasp-security`) viraram gates
  nao-bloqueantes pos-artefato no pipeline:
  - apos `specify` → `validate-documentation` em spec.md
  - apos `plan` → `validate-documentation` em plan.md + `owasp-security`
    (findings critical/high obrigam BloqueioHumano)
  - apos `create-tasks` → `validate-docs-rendered` no feature-dir

  Skip de gate e auditavel: requer Decisao com justificativa, e
  `/review-task` flaga features com >2 skips sem motivo solido como
  `quality-gate-bypass`.
- **Delegacao para skills Go em `execute-task` e `review-task`:**
  6 skills `go-*` antes orfas viraram atalhos explicitos quando stack
  detectado for Go (`execute-task` §4.2.1 e `review-task` "Atalhos de
  auditoria por stack"): `go-add-entity`, `go-add-consumer`,
  `go-add-migration`, `go-add-test`, `go-review-service`, `go-review-pr`.

### Deprecated

- **Skill `create-use-case`**: substituida por `specify` (formato SDD
  com user stories, success criteria e integracao com pipeline orquestrado).
  Frontmatter recebe `deprecated: true`, `deprecated_since: 3.12.0`,
  `remove_in: 4.0.0`. UC classico nao tem mais espaco no fluxo atual.
- **8 skills `dotnet-*`**: `dotnet-create-entity`, `dotnet-create-feature`,
  `dotnet-create-project`, `dotnet-create-test`,
  `dotnet-hexagonal-architecture`, `dotnet-infrastructure`,
  `dotnet-review-code`, `dotnet-testing`. Stack .NET descontinuada pelo
  mantenedor; sem substituto no toolkit global. Remocao agendada para
  v4.0.0 — usuarios que ainda usam .NET devem copiar para
  `<projeto>/.claude/skills/` antes da remocao.

### Removed

- **Skill `create-report`** (`language-related/go/skills/create-report/`):
  era altamente acoplada ao sistema GOB (nomes de servico hardcoded
  `gob-report-service`/`gob-go-commons`, exchange RabbitMQ `gob.reports`,
  caminhos ETCD do GOB, vocabulario macônico `lodge`/`federal`/`state_orient`,
  cabecalho fixo "Grande Oriente do Brasil" no PDF). Material project-specific
  pertence ao `<projeto>/.claude/skills/`, nao ao toolkit global. Caso
  historico que motivou o principio formal acima.

### Changed

- **README**: arvore de estrutura marca `create-use-case` e diretorio
  `language-related/dotnet/` como deprecated; tabela "Skills para .NET"
  recebe aviso de depreciacao; tabela "Skills para Go" reflete a
  delegacao via orquestradores; secao Contribuindo ganha o principio
  formal de escopo + regra #8 ("Generalize, ou pertence ao projeto").

### Why this release matters

Skills orfas (sem incentivo nos orquestradores) viram codigo morto
silencioso: ocupam espaco no install, complicam descoberta, mas
raramente sao acionadas. A auditoria desta release decidiu o destino
de cada uma das 24 skills "complementares" do toolkit:

- 13 ACTIVE (ja integradas — sem mudanca)
- 9 incentivadas via orquestradores (3 gates SDD + 6 go-* via
  execute-task/review-task)
- 4 mantidas standalone (`bugfix`, `advisor`, `image-generation`,
  `apply-insights` — uso por trigger manual cobre o caso)
- 9 deprecated (8 dotnet-* + create-use-case)
- 1 removida (`create-report`)

## [3.11.0] - 2026-05-19

Enforcement runtime do protocolo pre-flight constitution-conflict
(orchestrator.md §5.b). O hardening v3.8.0 documentou em texto que o
orquestrador deve emitir BloqueioHumano antes de invocar
`Skill(constitution)` quando `pipeline.sh constitution-conflict`
retorna exit=2, mas nao havia trava no runtime — dec-004 do projeto
github-pages-cstk-manual provou empiricamente que o agente pode
detectar exit=2 corretamente, listar as 3 opcoes canonicas, e ainda
assim decidir sozinho em Auto Mode (`--score 2`) e invocar a skill
sem aguardar resposta humana. Esta release fecha os dois caminhos de
bypass no runtime, sem mudar comportamento legitimo.

### Added

- **Trava em `state-decisions.sh register`**: quando `--opcoes` contem
  as 3 strings canonicas do BloqueioHumano pre-flight
  (`atualizar-global-via-bump-SemVer`,
  `criar-feature-delta-com-sync-impact-report`,
  `abortar-feature-sem-principios-proprios`), exige `--score 0`. Score
  maior reproduz dec-004 e e rejeitado com exit 1 + mensagem
  detalhada apontando para a sequencia correta (registrar score 0 →
  `bloqueios.sh register` → aguardar humano →
  `pipeline.sh require-blockade-resolved` → invocar skill).
- **`pipeline.sh require-blockade-resolved --state-dir SD --etapa STAGE`**:
  novo subcomando que valida cadeia decisao→bloqueio→resposta humana
  antes da invocacao da skill. Para `--etapa constitution`:
  - exit 0 se bloqueio respondido com `atualizar-global-via-bump-SemVer`
    ou `criar-feature-delta-com-sync-impact-report`;
  - exit 1 com diagnostico em stderr (`status: missing-preflight-decision`
    / `missing-blockade` / `blockade-pending` / `blockade-resolved-abort`
    / `blockade-invalid-response`) caso contrario;
  - outras etapas retornam `status: not-enforced` exit 0
    (extensivel para futuros protocolos).

### Changed

- **`global/agents/agente-00c-orchestrator.md` §5.b**: instrucao
  OBRIGATORIA para rodar `pipeline.sh require-blockade-resolved`
  antes de cada `Skill(constitution)`. Inclui descricao dos exit
  codes + referencia historica ao bypass dec-004 que motivou o
  enforcement.

### Tests

- 5 novos cenarios em `tests/test_state-decisions.sh` (22 total)
  cobrindo: rejeicao com 3 opcoes canonicas + score=2; aceitacao com
  score=0; ordem das opcoes irrelevante; backward-compat para
  decisoes posteriores (tipo ratificacao) com etapa=constitution mas
  opcoes diferentes; subconjunto parcial das canonicas nao dispara
  trava.
- 8 novos cenarios em `tests/test_pipeline.sh` (35 total) cobrindo:
  etapa nao-enforcada retorna 0; ausencia de decisao pre-flight
  falha; decisao sem bloqueio FK falha; bloqueio aguardando falha;
  respondido com criar-delta passa; respondido com atualizar-global
  passa; respondido com abortar falha; resposta nao-canonica falha.
- Suite completa: 639 PASS / 0 FAIL / 0 ORPHANS.

## [3.10.0] - 2026-05-19

Upgrade do `cstk session start`: nova flag `--claude` que, apos criar
a worktree isolada, entra no diretorio e dispara o Claude Code via
`exec claude`. Atalho para o fluxo mais comum (`cstk session start X
&& cd ../<repo>-X && claude`) em um unico comando.

### Added

- **`cstk session start <name> --claude`**: apos setup da sessao
  (worktree + branch + `.claude/` filtrado), faz `cd` para o path
  da sessao e substitui o processo cstk por `claude` (TTY herdado
  diretamente, sem shell intermediario). Combinavel com `--reset`,
  `--reuse` e `--force`. Quando `claude` nao esta no PATH, retorna
  exit 1 com hint manual (`cd <path> && claude`) — a sessao ja foi
  criada antes do launch, entao a falha e parcial e reversivel.

### Tests

- 3 novos scenarios em `tests/cstk/test_session.sh` (60 total na
  suite session, 626 no toolkit completo):
  - `scenario_start_claude_flag_launches_claude_binary`: stub de
    `claude` confirma que o CWD do exec e o path da sessao.
  - `scenario_start_claude_flag_missing_binary_exit_1`: PATH isolado
    sem `claude` retorna exit 1; sessao foi criada antes da falha.
  - `scenario_start_claude_flag_in_help_text`: help documenta a flag.

## [3.9.1] - 2026-05-19

Hotfix do release v3.9.0 — pipeline `release.yml` falhou em CI Ubuntu
por 2 testes ambient-specific. Sem mudanca de comportamento de feature.

### Fixed

- **`_session_pr` ordem de validacao**: spec FR-009 declara ordem
  `(a) sessao, (b) commits, (c) gh`. Implementacao inicial tinha gh
  check antes de commits check, fazendo `scenario_pr_no_commits_exit_13`
  retornar 12 (unauth) em vez de 13 (sem commits) em ambientes onde
  `gh auth status` falha (CI Ubuntu sem credenciais). Validacao local
  agora tem precedencia sobre dep externa, alinhado a spec.
- **Teste `scenario_pr_gh_not_installed_exit_11`**: PATH=/usr/bin:/bin
  incluia gh no CI Ubuntu (/usr/bin/gh). Refatorado para criar diretorio
  `isolated-bin` com symlinks apenas para essentials (git/sh/sed/etc),
  garantidamente sem gh — robusto entre macOS (brew em /opt/homebrew) e
  Ubuntu (apt em /usr/bin).

## [3.9.0] - 2026-05-19

Subcomando `cstk session` — sessoes paralelas isoladas via `git worktree`,
resolvendo colisao de working tree, branch HEAD e
`.claude/agente-00c-state/` quando o usuario abre multiplas features
simultaneas no mesmo repositorio. 4 verbos (`start`/`list`/`end`/`pr`),
zero dependencias alem de `git` + `gh` (dep opcional confinada em
`cli/lib/session.sh` sob amendment 1.1.0 da Constitution).

### Added

- **`cstk session start <name> [--reset|--reuse] [--force]`**: cria
  worktree em `<parent>/<repo>-<name>/` com branch resolvida segundo
  5 regras (nova / rastreando origin / reutilizar local / recriar
  com --reset / forcar com --reuse). Copia `.claude/` filtrado
  excluindo 8 artefatos runtime/per-env (agente-00c-state/,
  agente-00c-archive/, insights/, settings.local.json,
  agente-00c-whitelist, agente-00c-report.md,
  agente-00c-suggestions.md, .agente-00c-state.lock). `--reset` com
  commits nao-mergeados emite prompt interativo (bypassavel com
  `--force`).
- **`cstk session list [--json]`**: tabela com `NAME BRANCH IDLE
  STATUS PATH`; marcadores combinaveis `CURRENT,*,STALE`. Modo JSON
  emite array camelCase (`name`/`branch`/`path`/`idleDays`/`dirty`/
  `stale`/`current`) sem rodape. Ordenacao por idle ASC. Rodape "tip:
  rode 'git worktree prune'..." se houver STALE.
- **`cstk session end <name> [--force]`**: remove worktree + branch
  local com guards. Prompt interativo se ha mudancas nao commitadas,
  commits nao pushados ou PR aberto no GitHub. Detecta self-end
  (rodando de dentro da worktree-alvo → exit 14). `gh` opcional —
  ausente/unauth pula PR check com warning e prossegue.
- **`cstk session pr <name> [--draft] [--title T] [--body B] [--reviewer USER]`**:
  push + abre PR via `gh pr create`. Idempotente: se PR ja existe
  (OPEN/MERGED), retorna URL existente sem criar duplicata. Detecta
  default branch via `git symbolic-ref refs/remotes/origin/HEAD`
  (fallback `main`). Falha parcial (push OK + gh create falhou)
  emite stderr orientativo com comandos de recovery.
- **Boot-check `git >= 2.36`**: necessario para campo `prunable` em
  `git worktree list --porcelain`. Versao inferior → exit 15 com
  mensagem de upgrade.
- **15 exit codes especificos**: 5 (nome invalido), 6 (sessao ja
  existe), 7 (path ocupado), 8 (branch mergeada), 9 (sessao nao
  encontrada), 10 (cancelado), 11 (gh ausente), 12 (gh unauth), 13
  (sem commits), 14 (self-end), 15 (git antigo). Todos documentados
  em `contracts/cli-session.md` e exercitados por cenarios
  automatizados.
- **57 cenarios de teste** em `tests/cstk/test_session.sh` cobrindo
  os 4 subcomandos + helpers + dispatch + E2E + lint meta. 2
  cenarios de PR marcados como MANUAL (exigem rede + repo remoto
  GitHub).

### Changed

- **`cli/cstk` dispatcher**: adicionada `session` em 3 lugares
  (linha 159 case help, linha 196 dispatch principal, linha 141
  secao COMANDOS do help geral).
- **`README.md`**: nova secao "Sessoes paralelas" com exemplos e
  referencias para spec + contracts.
- **`CLAUDE.md`**: secao curta "Sessoes paralelas (cstk session)"
  apontando para a spec.

## [3.8.0] - 2026-05-19

Hardening do agente-00C contra dois bypasses encontrados em
`exec-2026-05-18-iniciacao-membro-rolledback`: (1) constitution raiz
ignorada com feature-delta silencioso (dec-004) e (2) `tasks.md` gerado
in-process sem invocar a skill `create-tasks` (dec-014). O fix endurece
`pipeline.sh detect-completion`, adiciona novo subcomando
`constitution-conflict` e introduz audit trail de invocacao de skills
via `state-ondas.sh record-skill`.

### Added

- **`pipeline.sh constitution-conflict`**: novo subcomando que detecta
  4 estados entre `docs/constitution.md` raiz e feature constitution
  (none-exists / pre-skill-alert / conflict / coordinated). Exit 2
  obriga o orquestrador a emitir BloqueioHumano com 3 opcoes
  (atualizar global via bump SemVer / criar feature-delta com Sync
  Impact Report / abortar) antes de invocar a skill `constitution`.
  Exit 1 sinaliza feature constitution silenciosa sem `Predecessor:`
  no header.
- **`state-ondas.sh record-skill`**: subcomando que registra invocacao
  formal de skill via tool Skill em `.ondas[-1].skills_invoked = [...]`.
  Idempotente para mesma combinacao (skill + decisao_id). Permite que
  `review-task` (e auditorias) identifiquem o anti-padrao "etapa
  marcada completa mas skill canonica nunca foi invocada".
- **`.ondas[N].skills_invoked: []`**: novo campo no schema do
  `state.json`, inicializado em `state-ondas.sh start`. Backward
  compatible — states pre-existentes nao quebram.
- **Regras 5.a/5.b/5.c/5.d/5.e no `agente-00c-orchestrator.md`**:
  invocacao via tool Skill OBRIGATORIA para `briefing`, `constitution`,
  `create-tasks`. Constitution exige pre-flight com
  `constitution-conflict` antes de chamar a skill. Cada etapa SDD chama
  `record-skill` apos a invocacao bem-sucedida.
- **19 novos cenarios de teste**: 13 em `test_pipeline.sh` (validacao
  briefing/tasks + 4 cenarios constitution-conflict + 2 cenarios de
  detect-completion constitution) e 7 em `test_state-ondas.sh`
  (record-skill: append, idempotencia, multi-skill, sem decisao_id,
  sem onda, validacao de flags, init com skills_invoked vazio).

### Changed

- **`pipeline.sh detect-completion --stage briefing`** agora valida
  estrutura minima do template (header `# (Project )?Briefing` + >=4
  secoes nucleares: Visao/Usuarios/Escopo/Prioridades/Restricoes/
  Stack/Qualidade/Futuro). Antes aceitava qualquer arquivo presente.
  Razao: defesa contra briefings rasos gerados in-process.
- **`pipeline.sh detect-completion --stage create-tasks`** agora valida
  estrutura do template da skill `create-tasks`: cabecalho `# Tarefas`
  ou `# Tasks`, presenca de `## FASE N`, legendas `[C]/[A]/[M]` (NAO
  aceita `P0/P1/P2/P3`), `## Matriz de Dependencias`,
  `## Resumo Quantitativo`, `## Escopo Coberto` e `## Escopo Excluido`.
  Antes so checava existencia do arquivo.
- **`pipeline.sh detect-completion --stage constitution`** quando raiz
  e feature constitution coexistem: agora exige header com
  `Predecessor:` ou referencia a `docs/constitution.md` nas primeiras
  30 linhas. Sem essa coordenacao explicita, retorna exit 1 com
  mensagem orientando o operador.

### Fixed

- **Bypass de skills SDD** (dec-004 + dec-014 da execucao-fonte): o
  orquestrador podia gerar `constitution.md` (feature-delta) e
  `tasks.md` direto via Write/Edit, sem invocar a skill canonica e sem
  detect-completion sinalizar problema. O artefato resultante drifa
  do template oficial — no caso real, `tasks.md` saiu sem Matriz de
  Dependencias / Resumo / Escopo, e a feature constitution criou 8
  principios proprios sem coordenacao com a global v1.0.0. Os 3
  gates novos (constitution-conflict + validacao estrutural + skills_invoked
  tracking) fecham esse furo em camadas: pre-flight bloqueia, validacao
  rejeita artefato fora-do-padrao, audit trail expoe etapa marcada
  completa sem skill invocada.

## [3.7.0] - 2026-05-16

Enriquecimento significativo da skill `owasp-security` com atualizacoes
posteriores a Janeiro/2026, incorporando 9 novas listas/standards e 6
mencoes de cobertura complementar. Reestruturada em `SKILL.md` (entry
point operacional) + 5 arquivos de referencia profunda em
`references/`, mantendo carregamento de contexto enxuto sem perder
profundidade.

### Added

- **OWASP LLM Top 10:2025**: nova secao irma a Agentic 2026 cobrindo
  riscos a nivel-modelo (LLM01 Prompt Injection, ..., LLM07 System
  Prompt Leakage, LLM08 Vector/Embedding Weaknesses, LLM10 Unbounded
  Consumption). Detalha indirect prompt injection (+32% Nov-2025 a
  Feb-2026 per Google), poisoning de RAG e inversao de embeddings.
- **OWASP API Security Top 10:2023**: secao completa com API1 BOLA,
  API3 BOPLA (mass assignment + excessive exposure), API6 Sensitive
  Business Flow Abuse, API7 SSRF (incluindo metadata-service guards) e
  API10 Unsafe Third-Party Consumption. Inclui patterns Python para
  cada risco.
- **OWASP CI/CD Top 10**: CICD-SEC-1..10 com deep dive em PPE (Direct,
  Indirect, Public), modern credential hygiene (OIDC federation, ESO,
  dynamic creds via Vault) e SLSA/Sigstore para integridade de
  artefato.
- **NIST SP 800-63B-4 (Final 31-Jul-2025)**: substitui aluso vaga por
  regras concretas — passwords 15 chars no AAL2, SHALL NOT impor
  composition rules, SHALL NOT requerer rotacao periodica, SHALL
  checar contra breached-password lists, SHALL NOT usar KBA recovery.
  Nova Section 5.3 Session Monitoring com reauth 12h/30min e
  step-up auth.
- **WebAuthn / Passkeys**: nova subsecao substituindo "MFA generico".
  Cobre WebAuthn L3 Working Draft (Jan-2025), passkeys como AAL2
  syncable authenticators, server-side requirements e armadilhas
  (origin check, sign-count monotonicity, cross-origin iframes).
- **OAuth 2.1 + FAPI 2.0**: cobertura de OAuth 2.1 (PKCE mandatory,
  implicit/password grants removidos), DPoP (RFC 9449) sender-
  constraining, PAR (RFC 9126), JAR (RFC 9101) e FAPI 2.0 Security
  Profile Final (19-Feb-2025) para APIs high-stakes.
- **MCP Authorization Spec (Jun-2025)**: expansao do ASI04 cobrindo
  RFC 8707 Resource Indicators, DPoP em MCP, ataque "confused deputy"
  em proxy servers e sanitizacao de tool descriptions. Checklist
  especifico para review de servidores MCP.
- **Post-Quantum Cryptography**: nova secao cobrindo FIPS 203 ML-KEM,
  204 ML-DSA, 205 SLH-DSA (publicadas 13-Ago-2024). Estrategia HNDL
  (Harvest-Now-Decrypt-Later), crypto agility, hybrid TLS
  (X25519+ML-KEM-768), timeline NIST IR 8547 e CNSA 2.0 (mandatory
  US-gov 2030-01-02).
- **Secrets Management 2026**: OIDC federation (GitHub Actions ↔ AWS
  STS), Workload Identity, External Secrets Operator, dynamic
  database credentials via Vault, SOPS/Sealed Secrets para GitOps,
  gitleaks/trufflehog em pre-commit + push protection.
- **CWE Top 25:2025 (CISA/MITRE, Dez-2025)**: tabela com top 25 + 
  mapeamento para OWASP Top 10:2025. Destaques: CWE-862 Missing
  Authorization subiu 5 posicoes, CWE-79 XSS retomou #1.
- **Modern prompt injection patterns**: indirect injection no wild
  (+32% trimestre), many-shot jailbreaking (exploits >128k context),
  tool-empowered jailbreaks (chains que individualmente parecem
  benignas). Cita pesquisa do Google e Anthropic.
- **MAESTRO threat modeling**: framework do Cloud Security Alliance
  (Fev-2025) estendendo STRIDE com camada AI-agent-specific. 7 layers
  de modelagem: foundation model, data, agent framework, tools,
  multi-agent orchestration, application logic, user/UI.
- **OWASP Mobile Top 10:2024 + MASVS 2.1**: cobertura M1-M10 com
  exemplos plataforma-especificos (Keychain iOS, EncryptedSharedPrefs
  Android, cert pinning OkHttp com backup pin).
- **OWASP Kubernetes Top 10 + Docker Top 10**: K01-K10 com Pod
  Security Standards (`restricted`), NetworkPolicy default deny,
  OPA/Kyverno admission policies, Falco runtime, distroless base
  images.
- **EU AI Act mapping**: regulation 2024/1689 com risk tiers
  (unacceptable/high-risk/limited/minimal/GPAI), obrigacoes vigentes
  desde 2-Ago-2025, multas ate EUR35M ou 7% turnover. Overlap com
  OWASP LLM Top 10 e Agentic 2026.

### Changed

- **`SKILL.md` reorganizado**: cabecalho `description` expandido para
  incluir 12+ novos triggers (passkey, FAPI, post-quantum, MCP
  security, prompt injection). Adicionada secao "Deep references"
  no topo apontando para `references/*.md`. Checklists de Auth,
  Data Protection e Agentic AI reescritos para refletir 2026 best
  practices (passkeys-first, OIDC federation, MCP OAuth 2.1).
  Gotchas atualizados com 5 regras novas (NIST 800-63B-4 no-rotation,
  passkey-first, MCP OAuth 2.1+RFC 8707+DPoP, PQC inventory now,
  LLM+Agentic complementares).
- **`OWASP-2025-2026-Report.md` expandido**: TOC reorganizado em 11
  secoes (era 5). ASVS V2.1.1 atualizado de "12 chars" para "12+
  (NIST 800-63B-4 raises to 15 for AAL2)". 6 novas secoes inseridas:
  API Security Top 10:2023, CI/CD Top 10, LLM Top 10:2025, NIST
  SP 800-63B-4 highlights, Post-Quantum Cryptography, CWE Top 25:2025.
  Sources reorganizadas por categoria (OWASP / Auth / Crypto / AI /
  Regulatory / Standards). Data atualizada para Maio/2026.
- **`README.md` linha de descricao da skill**: expandida para listar
  todas as 12 listas/standards cobertas (era apenas 3).

### Files

- `global/skills/owasp-security/SKILL.md` — 680 linhas (+110 vs 3.6.0)
- `global/skills/owasp-security/OWASP-2025-2026-Report.md` — 1061
  linhas (+269 vs 3.6.0)
- `global/skills/owasp-security/references/llm-agentic.md` — NOVO,
  273 linhas
- `global/skills/owasp-security/references/api-cicd.md` — NOVO,
  275 linhas
- `global/skills/owasp-security/references/auth-modern.md` — NOVO,
  277 linhas
- `global/skills/owasp-security/references/crypto-modern.md` — NOVO,
  198 linhas
- `global/skills/owasp-security/references/extras.md` — NOVO,
  223 linhas

## [3.6.0] - 2026-05-15

Evolucao pos-execucao do agente-00c — 14 recomendacoes priorizadas
derivadas da primeira execucao real (60 ondas, 224 decisoes,
exec-2026-05-11T19-59-58Z). Backlog completo em
`docs/specs/agente-00c-evolucao/tasks.md`; analise-fonte em
`docs/01-briefing-discovery/agente-00c-analise-licoes-aprendidas.md`.

### Added

- **FASE 1 P0 — Validacao empirica obrigatoria para `score=3`**:
  `state-decisions.sh register --score 3` agora EXIGE `--evidencia`
  (>=20 chars com comando empirico + fragmento literal do output).
  Sem evidencia, exit 1 com violacao de Principio I. Razao: 3
  decisoes historicas `score=3` afirmaram premissa tecnica falsa sem
  rodar tsc/test/grep. Adiciona Etapa 0 "Validacao Empirica de
  Premissas" no `execute-task/SKILL.md` e §Score-de-decisao no
  orchestrator.
- **FASE 1 P0 — Drift detector refatorado**: matcher bidirecional
  via tokens (`mcp-jira` casa com `integracao-bidirecional-mcp-jira`),
  3 camadas de aspectos (`iniciais` / `tecnicos` / `operacionais`),
  janela movel de 12 ondas (warn>=5 untouched, abort>=8) substitui o
  gatilho antigo de "5 consecutivas". Novos subcomandos
  `drift.sh mark-touched --aspecto X` e `drift.sh debug [--onda ID]`.
  Init aceita `--tecnicos`, `--operacionais` e `--force`.
- **FASE 1 P0 — Secrets-filter allow-list**: novo arquivo
  `.secrets-filter-ignore` (baseline com SAML_ISSUER, OIDC_ISSUER,
  COOKIE_DOMAIN, PUBLIC_*, VITE_*, etc); suporte a wildcard de
  sufixo; auto-descoberta de override por projeto-alvo
  (`<env-dir>/.claude/agente-00c-state/secrets-filter-ignore`);
  heuristica slug-com-separador para identificadores publicos
  curtos. Razao: identificadores publicos por design (sug-005,
  sug-049) eram redatados, removendo paths legiveis do report.
- **FASE 2 P1 — Pre-flight de bootstrap no briefing**: nova secao
  em `briefing/SKILL.md` instruindo geracao de
  `scripts/bootstrap-deps.sh` para stacks multi-workspace (npm
  workspaces, Go modules, Cargo). Amortiza N bloqueios `npm install`
  cirurgicos em batch unico antes de `/agente-00c`. Documentado
  tambem em `agente-00c.md` (checklist pre-execucao com heuristica
  de gap).
- **FASE 2 P1 — Sincronizacao bidirecional `tasks.md` ↔ codigo**:
  protocolo de 3 pontos (pre-execucao, decisao→sub-FASE, hook
  pos-onda) em `create-tasks/SKILL.md`; Etapa 9.3 nova em
  `execute-task/SKILL.md`; hook pos-detect-completion no
  orchestrator emitindo Decisao informativa quando diff vs checkbox
  diverge. Subsecao "Paridade de tipos compartilhados" (sug-028).
- **FASE 2 P1 — Mapeamento etapa → aspecto-chave automatizado**:
  novo subcomando `state-rw.sh infer-aspectos
  [--projeto-alvo-path PATH]` que aplica matcher fuzzy bidirecional
  (mesma logica do drift.sh) contra `git diff --name-only
  HEAD~1..HEAD` para inferir aspectos tocados pela onda. Orchestrator
  chama no hook pos-detect-completion + persiste em
  `.ondas[-1].aspectos_chave_tocados`. Tabela de fallback etapa →
  aspecto-tipico documentada.
- **FASE 3 P2 — Convencoes de Borda no plan**: nova ETAPA 5.4 em
  `plan/SKILL.md` exigindo tabela `Camada | Case style | Validacao |
  Fonte da verdade` para features com 2+ camadas. Roundtrip E2E
  obrigatorio no `quickstart.md` (chamada real, nao mock) para
  features com borda backend↔frontend. Novo pass G "Convencoes de
  Borda" em `analyze/SKILL.md`.
- **FASE 3 P2 — Decisoes de Infraestrutura Auditaveis no specify**:
  checklist de 6 itens (scheduling, key rotation, refresh policy,
  mutex multi-pod, backup/restore, idempotencia) virando FRs
  `FR-NN-INFRA-X` explicitos. `clarify/SKILL.md` ganhou categoria
  INFRA + reordenou prioridade (INFRA acima de UX).
- **FASE 3 P2 — Init de aspectos no briefing**: orchestrator §"Init
  de aspectos-chave (primeira onda apenas)" chama `drift.sh init`
  com 3 camadas apos briefing concluido. `/agente-00c-resume` aceita
  `--init-aspectos`, `--init-aspectos-tecnicos`,
  `--init-aspectos-operacionais` para execucoes legadas (relaxa
  idempotencia via `--force`).
- **FASE 4 P3 — Marco-aware retro a cada 25 ondas**: hook no passo
  10 do orchestrator emite bloqueio leve perguntando ao operador se
  deseja retro proativa em multiplos de 25 ondas. Atualiza
  `.proximo_marco_retrospectiva` no estado.
- **FASE 4 P3 — Schedule intent literal vs sentinel**: tabela do
  passo 11 do orchestrator ganhou coluna "Slash command pai".
  Pipelines de `/agente-00c-resume` usam `prompt` literal
  (`/agente-00c-resume --projeto-alvo-path <PAP>`), nao sentinel
  `<<autonomous-loop-dynamic>>` (que so funciona quando `/loop` e o
  pai).
- **FASE 4 P3 — Perfil `--runbook` no validate-documentation**:
  validacao de frontmatter (`title: RB-\d{3}:`, severidade,
  tempo-estimado, pre-requisitos), 6 secoes obrigatorias (incluindo
  Rollback quando severidade=critica), check de placeholders
  residuais (TODO/XXX/FIXME) e cross-refs validos.
- **FASE 4 P3 — Dry-run de Agent tool em clarify (orchestrator
  §5.a)**: antes do spawn de clarify-asker, verifica disponibilidade
  da tool Agent; se ausente, registra Decisao EXPLICITA de downgrade
  in-process (evita silent-fallback documentado em dec-006).
  `clarify/SKILL.md` ganhou secao "Modos de invocacao" referenciando
  o orchestrator.
- **FASE 4 P3 — Sistema canonico de tracking**: nova secao no topo
  do orchestrator instruindo a IGNORAR system-reminders sobre
  `TaskCreate`/`TaskUpdate`. Razao (sug-029): 8+ reminders em uma so
  onda historica; `state.json` + `state-decisions.sh` sao o sistema
  canonico (auditavel via 5 campos + score). Investigacao sobre hook
  do harness em `docs/specs/agente-00c-evolucao/notas-harness-hook.md`
  (conclusao: nao viavel hoje).

### Changed

- **BREAKING (interno) — `drift.sh check` muda semantica**: antes
  contava ondas CONSECUTIVAS sem aspecto (5 = abort); agora conta
  untouched em JANELA MOVEL das ultimas 12 ondas (5..7 = warn, >=8 =
  abort). Backbone tecnico intercalado (FASE 4.x) nao dispara mais
  abort. Stdout do `check` agora e numero de untouched na janela, nao
  consecutivas. Tests atualizados (21 cenarios, 21/21 verdes).
  Overrides via env: `DRIFT_WINDOW_SIZE`, `DRIFT_WARN_THRESHOLD`,
  `DRIFT_ABORT_THRESHOLD`.
- **BREAKING (interno) — schema do state.json**: adicionados
  campos opcionais `.aspectos_chave_tecnicos`,
  `.aspectos_chave_operacionais`, `.proximo_marco_retrospectiva`, e
  `.decisoes[].evidencia`. Backward-compatible para read; writers
  antigos que nao emitirem esses campos continuam funcionando.
- **BREAKING (interno) — `state-decisions.sh register` rejeita
  `score=3` sem `--evidencia`**: chamadas anteriores que emitiam
  `score=3` sem evidencia agora falham com exit 1. Para preservar
  comportamento antigo, baixar para `score=2` (que permanece valido
  sem evidencia).

### Fixed

- Drift detector deixava de detectar aspectos quando o aspecto era
  string longa contendo o token presente no texto (`integracao-
  bidirecional-mcp-jira` vs texto "mcp-jira ok"). Matcher
  bidirecional via tokens resolve.
- `SAML_ISSUER`, `COOKIE_DOMAIN`, `OIDC_ISSUER` (publicos por design)
  eram redatados como secrets, removendo paths legiveis do report.

### Testing

- `./tests/run.sh` full suite: **548 PASS / 0 FAIL / 0 ERROR / 0
  ORPHANS** apos a evolucao (+15 cenarios novos cobrindo evidencia
  score=3, drift fuzzy/camadas/janela/mark-touched/debug,
  secrets-filter allow-list/slug, e infer-aspectos).

## [3.5.3] - 2026-05-12

### Fixed

- **`cstk update` nao sincronizava `commands/` e `agents/`**: a funcao
  `update_main` em `cli/lib/update.sh` so iterava o manifest de skills.
  Commands e agents (infraestrutura global do toolkit, distribuida pelo
  install via `_install_apply_extra_kinds`) ficavam congelados em drift
  permanente apos a primeira instalacao. Sintoma reportado: orchestrator
  do agente-00C continuava emitindo "ScheduleWakeup nao disponivel neste
  harness" mesmo apos `cstk update`, porque o fix do commit 56b3959
  (orchestrator retorna `Schedule intent` em vez de invocar
  `ScheduleWakeup`) nunca alcancava o disco do usuario.

  Fix: novo `_update_apply_extra_kinds` espelha o do install, com
  semantica de update completa:
  - Idempotencia: release == manifest -> zero writes (mtime preservado)
  - Edit local: respeita `--force` (sobrescreve) e `--keep` (silencia);
    sem flag, conta em `skipped_edits` e propaga exit 4
  - Third-party (.md fora do manifest dedicado por kind): preservado
    por default; `--force` sobrescreve — caminho de recuperacao para
    instalacoes historicas em que o manifest dedicado por kind nunca
    foi criado
  - Manifest de skills vazio nao impede mais processar commands/agents
  - Summary reporta linhas `commands: ...` e `agents: ...` com seis
    counters (installed/updated/uptodate/kept/skipped/preserved)

  Help text de `cstk update --help` atualizado para refletir o escopo.
  Cobertura: 9 cenarios novos em `tests/cstk/test_update-extra-kinds.sh`
  (idempotencia, atualizacao real, third-party com/sem `--force`,
  edit local com `--force`/`--keep`/exit 4, dry-run zero writes,
  compat com tarball historico sem commands/agents). 12 cenarios
  existentes em `test_update.sh` continuam verdes.

- **agente-00c-orchestrator emitia `Schedule intent: none` mesmo com
  status `em_andamento`**: a nota explicativa do prompt comecava com
  "POR QUE NAO HA ScheduleWakeup AQUI" e descrevia o problema em tom
  negativo ("qualquer ScheduleWakeup invocado aqui firmaria — se
  firmasse — para um contexto ja extinto"). O LLM, executando como
  sub-agent, parafraseava essa explicacao e raciocinava "schedule nao
  funciona aqui, motivo=ScheduleWakeup_indisponivel" — emitindo
  `Schedule intent: none; motivo=ScheduleWakeup_indisponivel` mesmo
  quando deveria emitir `delaySeconds=...`. O slash command pai
  reproduzia a frase invalida ("Proxima onda agendada: nenhuma —
  ScheduleWakeup indisponivel; retomar via /agente-00c-resume"),
  efetivamente desabilitando schedule automatico.

  Fix em `global/agents/agente-00c-orchestrator.md`:
  - Nota de topo reescrita em tom positivo: "Schedule SEMPRE funciona.
    Voce decide os parametros, o pai executa." Lista explicita de
    antipadroes ("NUNCA emita `Schedule intent: none` com motivo
    `ScheduleWakeup indisponivel` ou similar").
  - Passo 11 reescrito: tabela de decisao expandida com coluna
    "Bloqueios pendentes" e marca **OBRIGATORIO** para o caso
    `em_andamento + 0 bloqueios`. Reforco final: "NUNCA emita
    `Schedule intent: none` com motivo `ScheduleWakeup_*`".

## [3.5.2] - 2026-05-12

### Fixed

- **`cstk 00c`: Ctrl+C nao abortava prompts limpo (#2)**: `trap
  '_00c_release_lock' EXIT INT TERM` rodava o cleanup mas nao chamava
  `exit`. POSIX consume o sinal apos o trap; `read -r` no loop de
  validacao retornava empty e o while prosseguia pedindo input —
  operador ficava preso no prompt e Ctrl+\ (SIGQUIT) era o unico escape,
  orfanando o lock per-path.

  Fix: split em duas traps. `EXIT` chama `_00c_release_lock` (cleanup);
  `INT`/`TERM` chamam `exit 130`/`exit 143`, que disparam o EXIT trap
  em sequencia. Operador sai com exit code POSIX correto e lock
  liberado.

  Regressao coberta via self-signal `kill -INT $$` em
  `scenario_issue_2_sigint_propaga_exit_130` (SIGINT real em background
  jobs nao eh testavel em POSIX sh por causa do SIG_IGN inherit).

- **agente-00c: pipeline.sh detect-completion nao reconhecia paths do
  `/initialize-docs` (#3)**: `detect-completion` so olhava em
  `--feature-dir` (`docs/specs/<feature>/`), mas as skills `briefing`
  e `constitution` salvam em paths project-level da hierarquia numerada:
  briefing -> `docs/01-briefing-discovery/briefing.md`, constitution ->
  `docs/constitution.md`. Orchestrator nunca detectava conclusao dessas
  etapas; double-write workaround duplicava o artefato em dois locais
  (suggestion `sug-001` da smoke v3.5.0).

  Fix: novo flag opcional `--projeto-alvo-path PAP` em
  `detect-completion`. Para briefing/constitution, paths do
  `/initialize-docs` sao aceitos como fallback alem do feature-dir.
  Orchestrator (`Loop principal item 6`) passa o PAP em todas as
  chamadas. Skills `briefing`/`constitution` permanecem inalteradas
  — caminho canonical delas continua nos paths numerados (decisao
  consciente: artefatos project-level separados de feature-level).

## [3.5.1] - 2026-05-12

### Fixed

- **`/agente-00c` falhava em install default por falta da skill
  `agente-00c-runtime`**: a runtime (infra interna que provê
  `state-rw.sh`, `path-guard.sh`, `whitelist-validate.sh` etc. ao
  orchestrator) so constava no profile `all` — `cstk install` default
  (profile `sdd`) instalava comandos e agentes do 00C mas deixava a
  runtime de fora. Resultado: `/agente-00c` falhava na primeira chamada
  Bash do orchestrator com referencia a script ausente.

  Tres camadas de fix:

  - `scripts/profiles.txt.in`: `agente-00c-runtime` agora pertence a
    `sdd` E `complementary` (alem do `all` ja existente). Qualquer
    install default carrega a runtime junto.
  - `cli/lib/00c-bootstrap.sh::_00c_check_deps`: pre-flight do
    `cstk 00c` estende para command + runtime executavel +
    orchestrator. Antes so checava o `.md` do command — instalacao
    parcial passava silenciosa e quebrava so dentro de uma onda.
  - `global/agents/agente-00c-orchestrator.md`: nova secao "Pre-flight
    da execucao" antes do loop de onda, com Bash check programatico de
    `state-rw.sh`/`state-lock.sh`/`path-guard.sh` (+x). Substitui a
    interpretacao em natural-language que estava produzindo
    diagnosticos hallucinados.

  Regression test em `tests/cstk/test_build-release.sh` garante que o
  profile `sdd` inclui `agente-00c-runtime` permanentemente.

- **Orchestrator (sub-agent) nao pode invocar `ScheduleWakeup` de forma
  sobrevivente**: o thread do sub-agent termina ao retornar o sumario
  para o slash command pai. Qualquer wakeup agendado pelo orchestrator
  firmaria — se firmasse — para contexto ja extinto. O resultado era o
  erro recorrente `Proxima onda agendada: nenhuma (ScheduleWakeup
  indisponivel — operador retoma via agente-00c-resume)`.

  Refactor para o padrao decide-aqui-executa-la:

  - `global/agents/agente-00c-orchestrator.md`: `ScheduleWakeup`
    removido de `allowed-tools`. Step 11 reescrito — orchestrator agora
    DECIDE `delaySeconds` + `reason` e grava o ISO planejado em
    `.ondas[-1].proxima_onda_agendada_para`. Step 13 (sumario)
    formaliza linha `Schedule intent: delaySeconds=N; reason="..."; prompt="..."`
    (ou `Schedule intent: none; motivo=<X>`) que o pai parseia.
  - `global/commands/agente-00c.md` e `global/commands/agente-00c-resume.md`:
    `ScheduleWakeup` adicionado ao `allowed-tools`. Novo step "Schedule
    da proxima onda" parseia a linha do sumario do orchestrator e
    invoca `ScheduleWakeup` no thread do pai. Em caso de falha, limpa
    `.ondas[-1].proxima_onda_agendada_para` via `state-rw.sh set`.

  Comportamento externo: `/agente-00c` e `/agente-00c-resume` agora
  realmente agendam a proxima onda quando o status e `em_andamento` sem
  bloqueios. O sumario ao operador mostra ISO real do wakeup, nao
  intencao do sub-agent.

## [3.5.0] - 2026-05-09

### Added

- **Subcomando `cstk 00c <path>` — bootstrap interativo do agente-00C
  (FASE 12 do `cstk-cli`)**: atalho recomendado para iniciar uma sessao
  do agente-00C. Cria diretorio do projeto-alvo, valida path, coleta
  parametros via prompts (descricao, stack JSON, whitelist de URLs) e
  invoca `claude` ja com `/agente-00c '<args>'` auto-submetido como
  primeiro turno. Elimina friccao de `mkdir`/`cd` + memorizar a sintaxe
  da slash command.

  - **Validacao defensiva** (FR-016b): rejeita path traversal `..`,
    rejeita 14 zonas de sistema (`/`, `/etc`, `/usr`, `/var`, `/bin`,
    `/sbin`, `/boot`, `/proc`, `/sys`, `~/.ssh`, `~/.gnupg`, `~/.aws`,
    `~/.config/claude` + canonicas e resolvidas no macOS); resolve
    symlinks via `realpath -m` (fallback POSIX `cd -P` para BSD).
    `<path>` exato em `$HOME` rejeitado, mas paths INSIDE `$HOME` sao
    permitidos.
  - **TTY-only** (FR-016a): subcomando recusa execucao em pipe/CI;
    `[ -t 0 ] && [ -t 1 ]`. Stderr pode ser redirecionado.
  - **Dir nao-vazio = recusa direta sem prompt** (FR-016b): finalidade
    e atalho para projeto NOVO; mensagem aponta `/agente-00c-resume`
    para retomada.
  - **Lock per-path** (FR-016h, novo): `mkdir <path>/.cstk-00c.lock/`
    atomico antes de qualquer prompt; release via `trap EXIT INT TERM`
    + release explicito antes do `exec claude`. Previne race entre
    duas instancias simultaneas no mesmo `<path>`.
  - **Dep checks** (FR-016d): claude CLI no PATH; `jq` no PATH (teste
    funcional via `jq --version`); `~/.claude/commands/agente-00c.md`
    instalado — ausencia dispara prompt `[Y/n]` para auto-install via
    `cstk install` em foreground (respeita lockfile global de FR-015).
    Falha do nested install propaga exit code + razao.
  - **Sanitizacao** (FR-016g): descricao escapada para shell single-quotes
    (`'` -> `'\''`); stack JSON compactada via `jq -c`; whitelist
    persistida em `<path>/.agente-00c-whitelist.txt` (chmod 600) e
    referenciada via path absoluto em `--whitelist` (evita argv overflow).
  - **Validacao de URL na whitelist**: espelha
    `agente-00c-runtime/scripts/whitelist-validate.sh` rejeitando
    patterns overly-broad (`**` puro, `*://*`, `https://*` sem dominio,
    host vazio, sem scheme http(s), wildcard fora do prefixo
    `*.dominio.tld`).
  - **Dry-run preview obrigatorio** (FR-016e): mostra path final,
    descricao, stack, whitelist count + path, e linha exata da
    `/agente-00c` que sera invocada. Confirmacao final `[Y/n]` (default
    Y); flag `--yes` pula apenas o prompt final + auto-install.
  - **Spawn auto-submit** (FR-016f): `exec claude "$slash_command"`
    passa a slash command como argv[1]; claude processa como primeiro
    turno automatico (sem exigir Enter adicional do operador).

  Implementacao em `cli/lib/00c-bootstrap.sh` (~480 linhas POSIX puro)
  com 16 helpers privados `_00c_*` + entry point publico
  `bootstrap_00c_main`. **Special-case no dispatcher** porque POSIX
  nao permite funcao com nome iniciando em digito (`00c_main` invalido).

  Cobertura de testes: 18 cenarios em `tests/cstk/test_00c-bootstrap.sh`
  com mocks de `claude` (registra argv) e `cstk install` (controlavel).
  Cenarios cobrem path validation, TTY, deps ausentes, prompts (descricao
  9/501 chars, com `$`, com unicode, JSON malformado, URL overly-broad),
  lock pre-existente, dry-run + cancel, happy path com argv correto,
  apostrofo escapado, JSON com aspas duplas internas. Suite total:
  **505 PASS / 0 FAIL**.

### Changed

- **Carve-out 1.1.0 atualizada**: `jq` agora obrigatorio em
  `cli/lib/00c-bootstrap.sh` (era opcional em outros comandos do cstk).
  Justificativa: validacao de stack JSON (FR-016c) + dep transitiva do
  `agente-00c-runtime` que o `cstk 00c` invoca via `/agente-00c` —
  falha cedo em FR-016d e melhor UX que erro tardio dentro da sessao
  do `claude`.

- **`cstk` dispatcher e `cstk --help` atualizados** com nova entrada
  `00c <path>` listando o subcomando entre os comandos validos.

- **README.md secao Agente-00C** documenta `cstk 00c <path>` como o
  caminho preferido para iniciar sessoes do agente-00C, com nota
  apontando `/agente-00c-resume` para retomada de execucoes existentes.

## [3.4.0] - 2026-05-09

### Changed

- **`/agente-00c` faz warm-up de permissoes em batch ANTES de spawnar
  o orquestrador (post-FASE 9 feedback)**: nova passo 0 invoca todas
  as 10 skills da pipeline + 3 agentes custom + ScheduleWakeup + Bash
  helpers + Read/Write em sequencia. Cada invocacao dispara o prompt
  nativo de permissao do Claude Code uma vez, com o operador presente.
  Apos confirmacao, o orquestrador roda autonomamente sem interrupcoes
  (resolve o problema de fluxo travado quando permissoes "lazy" pediam
  aprovacao em ondas posteriores onde o operador nao estava disponivel).
  `/agente-00c-resume` e `/agente-00c-abort` NAO refazem warm-up
  (resume = continuacao, abort = operacao curta com operador
  presente). Orquestrador ganhou secao "Warm-up de permissoes
  (pre-condicao)" documentando o contrato e instruindo deteccao de
  permissao pendente no meio de uma onda como BloqueioHumano.

### Added

- **Validacao end-to-end (parcial) e licoes da implementacao do agente-00C (FASE 9)**:

  - **`scripts/quickstart-shell-sim.sh`**: simula via Bash os 10 cenarios
    do quickstart compondo as primitivas dos 14 scripts do
    `agente-00c-runtime`. NAO invoca o agente Claude — exercita apenas
    composicao shell-level. Resultado: **10/10 PASS** em ~5s. Detecta
    regressao quando um script deixa de compor com outros (gate
    complementar a `tests/run.sh` que testa cada script isoladamente).

  - **`docs/specs/_archived/agente-00c/validation-runs/`** (novo diretorio): registro
    de execucoes do agente-00C. README com template + tipos
    (shell-simulation vs end-to-end-real). Primeiro registro:
    `2026-05-06-end-to-end-shell-simulation.md` (10/10 PASS, SCs
    validaveis em shell-level: SC-001, SC-002, SC-007, SC-008).

  - **`docs/specs/_archived/agente-00c/lessons-from-implementation.md`**: 5 licoes
    concretas da implementacao das 8 fases — bug jq em pipe (drift.sh),
    dupla resolucao de symlinks no macOS (path-guard.sh), "skills
    internas" como padrao (`agente-00c-runtime`), cobertura forçada
    como ROI alto (3 bugs descobertos), estratificacao 3-camadas
    (commands/agents/scripts). Cada licao com proposta concreta de FR
    para skill especifica + avaliacao contra constitution do toolkit
    (nenhuma requer amendment).

  Subtarefas da FASE 9 atendidas autonomamente: 9.1.1-9.1.11 (10
  cenarios shell-simulated + relatorio), 9.2.1-9.2.3 (bump MINOR
  determinado, CHANGELOG/README atualizados), 9.4.1-9.4.3 (licoes da
  implementacao + propostas FR + avaliacao constitution).

  Subtarefas pendentes (exigem operador): 9.2.4 (cstk doctor pos-release
  v3.4.0), 9.3.* (primeira execucao real do agente em projeto-alvo —
  exige 1-3h wallclock + curadoria de relatorio), 9.4.4 (abertura real
  de issues no toolkit — exige autorizacao + execucao com `gh`), 9.4.5
  (atualizar threat-model com threats observados em runtime real).

- **Relatorio e integracao com toolkit do agente-00C (FASE 8)**: 28
  subtarefas implementadas em 3 novos scripts cobrindo geracao de
  relatorio com 6 secoes auditaveis, registro de Sugestoes para skills
  globais e abertura automatica de Issue no toolkit GitHub.

  - `report.sh` (FR-011 + SC-001 + FR-012): subcomandos `generate` e
    `validate`. `generate` renderiza 6 secoes obrigatorias (Resumo
    Executivo com tabela de 15 campos + paragrafo, Linha do Tempo
    com tabela de ondas, Decisoes agrupadas por agente + lista
    detalhada, Bloqueios Humanos divididos em pendentes/respondidos/
    sem, Sugestoes em 3 niveis de severidade, Licoes Aprendidas
    cravado como placeholder em parcial e preenchivel via
    `--licoes-aprendidas` + `--final`) + Apendice A com 5 paths.
    `validate` checa as 6 secoes via `grep -qF` e reporta faltantes.
    Caller deve aplicar `secrets-filter.sh scrub` em pipe (FR-030).

  - `suggestions.sh` (FR-020): subcomandos `register`, `list`,
    `count`, `next-id`, `mark-issue`, `render-md`. Sugestoes vivem
    em DOIS lugares — `state.json .sugestoes[]` (ground truth JSON)
    + agente-00c-suggestions.md (export human-readable regerado a
    cada register/mark-issue). 3 severidades validadas:
    informativa, aviso, impeditiva. Diagnostico exige >=50 chars
    para forçar detalhamento acionavel. `mark-issue` atualiza
    `.issue_aberta` + incrementa `metricas_acumuladas.issues_toolkit_abertas`.

  - `issue.sh` (FR-021): subcomandos `create`, `check-duplicate`,
    `hash`. Excecao escopada ao Principio V — apenas `gh issue
    create --repo JotJunior/cstk`. Hash de 8 chars do
    diagnostico normalizado (lowercase + collapse whitespace + sha256
    + cut) para dedup via `gh issue list --search`. Template do
    `contracts/issue-template.md` aplicado via heredoc (Skill afetada,
    Diagnostico, Reproducao com decisoes recentes, Por que e
    impeditivo, Proposta de correcao, Anexos). Defense in depth:
    `secrets-filter.sh scrub` aplicado 2x (no build do body + antes
    do `gh create`). Labels `agente-00c,bug,skill-global` criadas
    automaticamente se ausentes (`gh label create --force`). Falha
    de `gh create` (sem internet, rate limit) propaga exit 1; corpo
    truncado em ~4000 chars com pointer ao relatorio local. `--dry-run`
    imprime template completo sem chamar `gh`.

  Agente orquestrador atualizado (passo 12 do Loop principal) com
  template operacional completo: pipe de `report.sh generate |
  secrets-filter.sh scrub > <report.md>` + `report.sh validate`,
  fluxo de Sugestao (impeditiva => `issue.sh create`), retentativa
  + bloqueio humano em falha persistente.

  27 cenarios de teste novos em
  `tests/test_{report,suggestions,issue}.sh`. `test_issue.sh` cobre
  apenas dry-run + hash (chamadas reais a `gh` evitadas para nao
  gerar issues em produçao — validacao end-to-end na FASE 9.1.6).

- **Continuacao cross-sessao do agente-00C (FASE 7)**: 20 subtarefas
  cobrindo `ScheduleWakeup` para ondas curtas, `/agente-00c-resume`,
  fallback `/schedule` Routines para pausas longas, e
  `/agente-00c-abort`. Sem novos scripts — todas as primitivas
  necessarias ja existem nas FASES 2-6 (state-rw, state-validate,
  state-lock, bloqueios, sanitize, secrets-filter, state-ondas).

  - **`global/agents/agente-00c-orchestrator.md`** — passo 11 expandido:
    `ScheduleWakeup` invocado APENAS para ondas nao-terminais sem
    bloqueios pendentes; tabela de calibracao de `delaySeconds`
    respeitando cache Anthropic (5min TTL): 60-270s para continuacao
    normal, 1200-1800s apos threshold proxy. Sentinela
    `<<autonomous-loop-dynamic>>` documentada. Reason no formato
    `agente-00c onda <NNN+1> apos <motivo>`. Passo 13 cravou formato do
    sumario retornado ao operador.

  - **`global/agents/agente-00c-orchestrator.md`** — nova secao "Pausas
    longas e fallback `/schedule` Routines": template completo de
    routine `/schedule criar "..." cron="..." prompt="/agente-00c-resume
    --projeto-alvo-path <PAP>"`; orientacao para incluir no relatorio
    parcial quando `aguardando_humano` + sinais de inatividade;
    explicito "NAO criar routine automaticamente" (operador escolhe
    cron especifico).

  - **`global/commands/agente-00c-resume.md`** — substituido o esqueleto
    da FASE 1 por fluxo operacional de 8 passos: parse de args, lock
    acquire, validate + sha256-verify, branch por status (terminal /
    em_andamento / aguardando_humano), apply de `--resposta-bloqueio`
    com sanitizacao via `sanitize.sh limit-length --max 2000`, spawn
    do orquestrador com prompt indicando "CONTINUACAO de execucao
    existente" + `retomada_motivo`, lock release + sumario.

  - **`global/commands/agente-00c-abort.md`** — substituido o esqueleto
    por fluxo operacional de 8 passos: parse, validacao com fail-soft
    para schema invalido (abort PROCEDE — pode ser o motivo do abort),
    idempotencia explicita (status terminal = no-op), atualizacao via
    `state-rw.sh set` (backup automatico), stub minimal de relatorio
    com `secrets-filter.sh scrub` aplicado, commit local via
    `state-ondas.sh git-commit` (fail-soft se nao e repo git, NUNCA
    push), sumario com hash do commit.

  - **`README.md`** — limitacao "Schedule mínimo de 5 min via /loop"
    atualizada para refletir clamp [60, 3600s] do `ScheduleWakeup` +
    fallback `/schedule` Routines.

- **Seguranca do agente-00C (FASE 6 — todas as 9 sub-features sao [C])**:
  56 subtarefas implementadas em 5 scripts focados no
  `agente-00c-runtime`, cobrindo 8 FRs criticos (FR-017, FR-018, FR-024,
  FR-025, FR-026, FR-027, FR-028, FR-029, FR-030, FR-031) e 5 threats
  (T1, T2, T3, T4, T5).

  - `path-guard.sh` (FR-024 + FR-017): subcomandos `validate-target`,
    `check-write`, `resolve`. Resolve symlinks via `realpath`/`readlink -f`
    com fallback portavel para paths inexistentes. Lista de zonas
    proibidas cobre 20+ paths incluindo formas canonica (`/etc`) e
    resolvida no macOS (`/private/etc`); explicitamente NAO bloqueia
    `/var/folders` (mktemp). Resolve TAMBEM cada zona antes de comparar
    (defesa T2 contra symlinks adversariais que apontam para zona
    proibida via `~`).

  - `bash-guard.sh` (FR-018 + FR-028 + SC-008): subcomandos
    `check-blocklist`, `check-whitelist`, `check`. Blocklist: sudo,
    package managers (npm/pnpm/yarn/pip/gem/brew/go install/cargo
    install) sem prefixo `docker exec/run`, `git push` (qualquer
    remote), kubectl mutativo, terraform apply/destroy, aws cli
    mutativo, gcloud deploy, docker push, docker-compose push, helm
    install/upgrade/uninstall. Whitelist: detecta network calls
    (curl/wget/gh api,issue,pr,repo,browse/git fetch,pull,clone),
    extrai URL (incluindo via `--repo OWNER/NAME` para gh) e checa
    contra whitelist; converte glob simples (`**` -> `.*`, `*` ->
    `[^/]*`) em regex. Excecao escopada: `gh issue create --repo
    JotJunior/cstk` bypass (FR-021).

  - `secrets-filter.sh` (FR-030): subcomandos `scrub`, `check`. Filtros
    em ordem (especificos primeiro para preservar tipo): AWS keys
    (`AKIA[A-Z0-9]{16,}`), Bearer tokens, basic auth em URLs, tokens
    com palavra-chave proxima (token/key/secret/password/pwd/auth/
    api_key/access_key precedendo valor 20+ chars), valores de chaves
    do `.env` (carregado via `--env-file`, valores < 8 chars
    ignorados). `[REDACTED]`, `[REDACTED-AWS-KEY]` e `[REDACTED-ENV]`
    distinguem tipo. Hashes git e UUIDs sem palavra-chave proxima NAO
    sao filtrados (anti-falso-positivo).

  - `sanitize.sh` (FR-025): subcomandos `limit-length`, `check-length`,
    `escape-commit-msg`, `escape-issue-body`, `escape-path`. Defaults
    cobrem `descricao_curta` (max 500 chars). `escape-commit-msg`
    remove newlines/tabs/dollars/backticks/quotes + limita 100 chars.
    `escape-issue-body` preserva newlines (markdown), remove `$(...)`
    e backticks. `escape-path` remove path traversal `..` + chars
    nao-`[A-Za-z0-9._-]` + limita 64 chars.

  - `whitelist-validate.sh` (FR-031): subcomandos `check`, `list`.
    Rejeita patterns "overly broad": `**` puro sem dominio, `*://*`
    (scheme com glob), `https://*` sem dominio, host vazio, sem
    scheme, wildcard fora do padrao prefixo `*.dominio.tld`.
    Diagnostico inclui numero da linha + motivo + conteudo.

  Agente orquestrador (`global/agents/agente-00c-orchestrator.md`)
  atualizado com tabela de primitivas estendida (5 novos scripts) +
  secao "Defesa em profundidade" reescrita listando os 7 mecanismos
  (bash-guard, path-guard, sanitize, secrets-filter, whitelist-validate,
  sha256-verify, goal alignment) com instrucoes operacionais explicitas
  para o LLM (quando invocar, qual subcomando, semantica de exit code).

  62 cenarios de teste novos em
  `tests/test_{path-guard,bash-guard,secrets-filter,sanitize,whitelist-validate}.sh`.
  Inclui casos adversariais: symlink que aponta para `~/.ssh`, comando
  Bash com `sudo`/`git push`/`docker push`/`kubectl apply`, payload com
  AWS key/Bearer/basic auth/.env values, whitelist com `**`/`*://*`/etc.

- **Autonomia controlada do agente-00C (FASE 5)**: 5 novos scripts em
  `global/skills/agente-00c-runtime/scripts/` cobrem os 5 mecanismos de
  aborto graceful que mantem o orquestrador dentro do orcamento e do
  escopo declarado (Principio IV — Autonomia Limitada com Aborto).

  - `budget.sh`: proxies de orcamento de sessao (FR-009, sem signal
    nativo de tokens). 3 dimensoes: tool_calls da onda (default 80),
    wallclock (default 5400s = 90min) e tamanho de state.json (default
    1MB). `check` exit 1 quando QUALQUER threshold dispara, com TSV
    `TIPO\tCURRENT\tTHRESHOLD` em stdout. Wallclock usa fallback portavel
    BSD/GNU para `date -d` vs `date -j -f`. State size via `stat -f %z`
    (BSD) / `stat -c %s` (GNU) / `wc -c` (fallback).

  - `cycles.sh`: limite de ciclos por etapa (FR-014.a — `loop_em_etapa`).
    `tick` incrementa contador; `--progress-made` zera (orquestrador
    decide quando 1 dos 4 indicadores de FR-014 aconteceu). `reset`
    explicito ao avancar de etapa (separacao de responsabilidades — nao
    infere mudanca via `.etapa_corrente`). Exit 3 em > 5 ciclos.

  - `circular.sh`: deteccao de movimento circular (FR-014.b). `push`
    armazena `{problema_hash, solucao_hash, timestamp}` em buffer FIFO
    de capacidade 6. Normalizacao: lowercase + nao-alfanumerico->space +
    20 primeiras palavras. `detect` exit 3 quando mesmo problema_hash
    aparece >=3 vezes (cobre o padrao "P=A,S=X / P=B,S=Y / P=A,S=Z /
    P=B,S=Y / P=A,S=X" do exemplo da spec).

  - `drift.sh`: drift detection / goal alignment (FR-027, threat T1).
    `init` grava 3..7 aspectos-chave (cravado pos-primeira-onda — recusa
    sobrescrever). `check` itera ondas do final para o inicio, conta
    consecutivas sem decisao mencionando aspecto (case-insensitive
    substring nos campos contexto/escolha/justificativa de cada
    decisao). Warn em 3 ondas (stderr, exit 0); abort em 5 (exit 3,
    motivo `desvio_de_finalidade`).

  - `retro.sh`: limite de retro-execucoes (FR-006). `check` valida
    `consumed < max` (default 2). `consume` exit 3 SEM mutar estado se
    incremento excederia max (defesa em profundidade — testado com
    snapshot before/after). Orquestrador converte 3a tentativa em
    BloqueioHumano via `bloqueios.sh register`.

  37 cenarios de teste em `tests/test_{budget,cycles,circular,drift,retro}.sh`.

  Agente orquestrador (`global/agents/agente-00c-orchestrator.md`)
  atualizado: tabela de primitivas inclui os 5 novos scripts; passos 7
  e 8 do Loop principal de uma onda referenciam cada gatilho de aborto
  com semantica explicita (motivo, exit code, acao do orquestrador).

- **Padrao clarify de dois atores (agente-00C FASE 4)**: implementacao
  do mecanismo de "Pause-or-Decide" (Principio II da feature), com
  mediacao orquestrada entre clarify-asker (gera 1-5 perguntas via skill
  clarify) e clarify-answerer (decide via heuristica de score 0..3).

  - `global/agents/agente-00c-clarify-asker.md`: prompt operacional
    completo. Inputs (`spec_path`, `briefing_path`, `etapa_corrente`,
    `decisoes_anteriores`, `quantidade_max_perguntas`); fluxo (Read +
    Skill clarify + filtro de redundantes); formato JSON cravado com
    `Q1..QN` + `default_sugerido` opcional; saida vazia `{ "perguntas":
    [] }` quando nao ha clarificacao pendente. Tools restritas a Skill+Read
    (sem Agent — bisneto nao recursiona).

  - `global/agents/agente-00c-clarify-answerer.md`: heuristica de score
    documentada (3 fontes: briefing, constitutions toolkit+feature,
    stack-sugerida). Tabela de decisao (>=2 decide, ==1 decide so se
    outras violarem constitution, ==0 pause-humano). Tie-breaker em 4
    niveis. Formato JSON com `pause_humano: bool` e
    `contexto_para_humano` quando aplicavel. Tools restritas a Read+Bash
    (Bash apenas para `date`).

  - `global/agents/agente-00c-orchestrator.md`: passo 5 do Loop
    principal expandido com fluxo de mediacao em 7 sub-passos (a-g):
    pre-flight via spawn-tracker, spawn asker, spawn answerer (irmaos),
    aplicar respostas validas como Decisao via state-decisions.sh,
    converter score 0 em BloqueioHumano via bloqueios.sh, fim de onda
    gracioso quando ha pendentes.

  - **Novo script** `global/skills/agente-00c-runtime/scripts/bloqueios.sh`:
    ciclo de vida de BloqueioHumano (FR-015, FR-016). 6 subcomandos:
    `register` (gera `block-NNN` sequencial; valida FK para Decisao
    existente; valida `pergunta >= 20 chars`; atualiza
    `.execucao.status = "aguardando_humano"` e
    `.metricas_acumuladas.bloqueios_humanos_total`); `respond` (marca
    `respondido` + grava `resposta_humana` + `respondido_em`; volta
    `.execucao.status = "em_andamento"` SO quando todos os bloqueios
    pendentes foram respondidos); `list` (TSV com filtro opcional por
    status); `count` (com `--pending-only`); `next-id`; `get`
    (JSON do bloqueio).

  14 cenarios de teste em `tests/test_bloqueios.sh` cobrem o lifecycle
  completo (register -> respond), FK violation, validacao de pergunta
  curta, status transitions com bloqueios multiplos, idempotencia.

- **Orquestrador raiz do agente-00C (FASE 3)**: 4 novos scripts em
  `global/skills/agente-00c-runtime/scripts/` cobrem state machine,
  decisoes auditaveis, tracking de subagentes e ciclo de vida de ondas.

  - `pipeline.sh`: 5 subcomandos. `stages` imprime as 10 etapas
    canonicas (briefing → constitution → specify → clarify → plan →
    checklist → create-tasks → execute-task → review-task →
    review-features). `next-stage`/`prev-stage` para avanco linear ou
    retro-execucao. `detect-completion` mapeia 7 etapas para artefatos
    esperados em `docs/specs/<feature>/`. `skill-conflict` detecta
    skill em local (`<projeto>/.claude/skills/`) + global
    (`~/.claude/skills/`) com 4 status (conflict/only-local/only-global/
    not-found); regra: local vence.
  - `state-decisions.sh`: registro auditavel (Principio I —
    Auditabilidade Total). `register` valida 5 campos obrigatorios
    (contexto>=20, opcoes_consideradas>=1, escolha, justificativa>=20,
    agente); falha = exit 1 com `violacao Principio I`. Ids `dec-NNN`
    sequenciais; linka a `onda_id` corrente; `--score` 0..3 para
    decisoes do clarify-answerer (FR-015). Atualiza
    `metricas_acumuladas.decisoes_total`. Subcomandos `count`, `list`,
    `next-id` para introspeccao.
  - `spawn-tracker.sh`: enforce FR-013 (max 3 niveis). `enter` valida
    `(current+1) <= 3` ANTES de qualquer escrita; falha = exit 3 SEM
    modificar estado. Atualiza `profundidade_max_atingida` e
    `subagentes_spawned`. `leave` decrementa (idempotente em min 1).
    `check` exposto para validacao read-only. Defesa em profundidade:
    agentes `agente-00c-clarify-asker` e `clarify-answerer` NAO
    declaram tool Agent.
  - `state-ondas.sh`: ciclo de vida de Ondas. `start` cria nova `onda-NNN`
    + reseta tool_calls/inicio_onda_corrente. `end` valida 1 dos 5
    motivos validos (etapa_concluida_avancando, threshold_proxy_atingido,
    bloqueio_humano, aborto, concluido), calcula wallclock (fallback
    portavel GNU `date -d` -> BSD `date -j -f`) e atualiza
    metricas_acumuladas. `tool-call-tick` para incrementar contador
    (backup so a cada 10 ticks p/ nao explodir state-history/).
    `git-commit --motivo MOTIVO` faz commit local no projeto-alvo
    (`chore(agente-00c): <onda-id> - <motivo>`); NUNCA `git push`
    (Principio V — Blast Radius Confinado).

  46 cenarios de teste em `tests/test_{pipeline,state-decisions,spawn-tracker,state-ondas}.sh`.

  Agente orquestrador (`global/agents/agente-00c-orchestrator.md`)
  atualizado com instrucoes operacionais detalhadas (13 passos do loop
  principal de uma onda) referenciando estas primitivas.

- **Skill interna `agente-00c-runtime` (agente-00C FASE 2)**: biblioteca
  POSIX consumida pelos agentes custom do agente-00C. NAO e
  user-invocavel — empacota helpers de estado, validacao e lock para a
  pipeline. Distribuida via `cstk install` (catalog/skills/) e instalada
  em `~/.claude/skills/agente-00c-runtime/`. Conteudo:

  - `scripts/state-rw.sh`: subcomandos `init`, `read`, `write`, `get`,
    `set`, `sha256-update`, `sha256-verify`, `path-check`. Implementa
    schema state.json v1.0.0, backups automaticos por onda em
    `state-history/`, integridade SHA-256 (FR-029), atomic write
    via mktemp+mv, write-probe para detectar permissao negada, captura
    de I/O errors (disco cheio).
  - `scripts/state-validate.sh`: validador FR-008 read-only com 10
    checagens (schema_version, 14 campos obrigatorios, 4 invariantes
    numericas, status x terminada_em, 5 campos de Decisao, integridade
    de FK BloqueioHumano -> Decisao, whitelist nao-vazia). Sem
    auto-correcao (Principio III).
  - `scripts/state-lock.sh`: subcomandos `acquire`, `release`, `check`,
    `check-execution-busy`. Lock via `mkdir` atomico em
    `<state-dir>/.lock/`; locks independentes por projeto-alvo
    (permite execucoes simultaneas em projetos distintos). TOCTOU
    residual (CHK072) documentado.

  Dependencia: `jq` (carve-out 1.1.0 da constitution para JSON
  estruturado). 36 cenarios de teste em `tests/test_state-{rw,validate,lock}.sh`.

- **`cstk install` distribui `commands/` e `agents/` (agente-00C FASE 1.2)**:
  o tarball de release agora inclui `catalog/commands/` e `catalog/agents/`
  (espelhos de `global/commands/` e `global/agents/`), e o `cstk install`
  copia esses `.md` soltos para `~/.claude/commands/` e `~/.claude/agents/`
  (respectivamente `./.claude/commands/` e `./.claude/agents/` em
  `--scope project`). Cada kind tem seu proprio manifest dedicado
  (`<dest>/.cstk-manifest`) com schema identico ao de skills.

  Comportamento: instalacao sempre processa TODOS os `.md` (sem filtro de
  profile — sao infraestrutura, nao skills); re-install vira "updated";
  arquivo pre-existente sem entry no manifest e PRESERVADO como third-party
  (FR-007). Tarballs historicos sem `catalog/commands/` ou
  `catalog/agents/` continuam validos — ambos os campos sao opcionais.

- **`cstk doctor` varre os 3 kinds (skills, commands, agents)**: drift em
  commands/agents (EDITED, MISSING, ORPHAN) e reportado com prefixo de
  kind (ex: `[EDITED]   commands/agente-00c`); skills continuam exibidas
  sem prefixo (compatibilidade backward). `--fix` remove entries MISSING
  do manifest correto por kind.

- **Esqueleto do agente-00C** em `global/commands/` (3 slash commands:
  `/agente-00c`, `/agente-00c-abort`, `/agente-00c-resume`) e
  `global/agents/` (3 agentes custom: orchestrator, clarify-asker,
  clarify-answerer). Esqueleto apenas — implementacao operacional ocorre
  ao longo das Fases 2-9 do backlog em
  `docs/specs/_archived/agente-00c/tasks.md`.

### Changed

- `manifest_default_path` aceita argumento opcional `kind` (default
  `skills` — backward compatible). Uso: `manifest_default_path global commands`.
- `hash.sh` exporta `hash_file <arquivo>` (wrapper sobre `sha256_file`)
  para cobrir artefatos single-file (commands/agents). `hash_dir`
  inalterado.

## [3.3.0] - 2026-05-05

### Added

- **Skill `review-features`**: relatorio comparativo de TODAS as features
  do projeto (cross-feature), complementar a `review-task` (que olha UMA
  feature). Saida: tabela com nome, descricao, % concluida, criticidade
  pendente e sugestao de acao por feature (`ARQUIVAR` / `ABANDONAR` /
  `PRIORIZAR` / `CONTINUAR` / `INDEFINIDO`).

  Heuristica deterministica:
  - `ARQUIVAR`: feature 100% concluida
  - `ABANDONAR`: 0% concluida e sem modificacao ha mais de 90 dias
  - `PRIORIZAR`: tem subtasks `[C]` pendentes e menos de 50% concluida
  - `CONTINUAR`: caso geral em andamento
  - `INDEFINIDO`: tasks.md vazio

  Acompanha script POSIX `scripts/aggregate.sh` (saida markdown ou
  JSON-lines via `--json`) com 16 cenarios de teste em
  `tests/test_aggregate.sh`. A skill e read-only — sugestao e recomendacao,
  nunca executa arquivar/deletar sem confirmacao do usuario.

## [3.2.3] - 2026-04-27

### Changed

- **`cstk install --help` agora lista os profiles disponiveis** (`sdd`,
  `complementary`, `all`) com o conteudo de cada um e marca `sdd` como
  default. Antes, o usuario via apenas "Default: sdd" e nao tinha como
  descobrir que existiam outros profiles nem o que cada um continha — a
  unica fonte era `scripts/profiles.txt.in` no repo, fora do alcance de
  quem instalou via tarball.

  Reportado por usuario: apos `cstk install` (default `sdd`), faltavam
  skills complementares (advisor, bugfix, owasp-security, etc.) e nao
  havia pista no help de como instala-las. Solucao: profile
  `complementary` instala as 9 skills de uso pontual; profile `all`
  instala tudo. Exemplos no help cobrem os 3 profiles + cherry-pick.

  Test atualizado: `scenario_install_help_exit_zero` verifica que os
  tres nomes de profile aparecem na saida.

## [3.2.2] - 2026-04-27

### Fixed

- **`cstk install` e `cstk update` sem `--from` agora consultam a API
  GitHub** para descobrir a ultima release, em vez de abortar com
  "vem na FASE 3.2 (bootstrap)" — mensagem misleading que sobreviveu
  a entrega da FASE 3.2 (que entregou apenas o bootstrap standalone,
  nao a resolucao no comando `cstk install`).

  Comportamento novo:
  - `--from URL` (explicit)             → usa a URL fornecida
  - `$CSTK_RELEASE_URL` (env)           → usa a URL do env
  - **(novo)** sem nada acima           → GitHub API /releases/latest

  Honra `$CSTK_REPO` para forks (default `JotJunior/cstk`).
  Mesmo padrao ja em uso por `cstk self-update` desde FASE 5.

  Reportado por usuario: `cstk install` apos bootstrap retornava
  "[error] install: --from URL ausente e \$CSTK_RELEASE_URL nao setado"
  — quebrava o fluxo "instalar via one-liner depois `cstk install`"
  documentado no README.

  Test atualizado: `scenario_install_sem_from_e_sem_env_consulta_api`
  usa `CSTK_REPO=invalid/nonexistent` para forcar 404 da API e validar
  que o erro reportado e "falha ao consultar" (em vez de mensagem
  antiga sobre CSTK_RELEASE_URL nao setado).

## [3.2.1] - 2026-04-27

### Fixed

- **Bootstrap one-liner (`cli/install.sh`) e `cstk self-update` baixavam
  URL com 404.** A construcao da URL do tarball usava o tag completo
  (`cstk-v3.2.0.tar.gz`), mas `scripts/build-release.sh` strip o prefixo
  `v` ao gerar o asset (`cstk-3.2.0.tar.gz`). Match falhava com 404.

  Fix: ambos `cli/install.sh` e `cli/lib/self-update.sh` agora computam
  `TAG_BARE=${TAG#v}` e usam essa variante ao construir o filename do
  asset, mantendo o tag original (com `v`) no path do release. Comporta-
  mento alinhado com `build-release.sh`.

  **Impacto**: `releases/latest/download/install.sh` em v3.2.0 esta
  quebrado — usuarios precisam usar v3.2.1 (que fixa o asset URL ao
  baixar). v3.2.0 nao foi removida; tag continua presente para
  rastreabilidade do incidente.

  Descoberto por usuario reportando `curl: (22) ... 404` ao executar o
  one-liner publicado no README.

## [3.2.0] - 2026-04-26

### Added

- **`cstk` CLI (POSIX shell)** — toolkit de instalação, atualização e
  auditoria de skills. Substitui o `cp -r` manual documentado em
  `CLAUDE.md` por um fluxo rastreável: manifest por escopo (versão +
  `source_sha256` + ISO timestamp), lock concorrente via `mkdir`,
  verificação SHA-256 obrigatória em todo download (FR-010a),
  preservação de skills de terceiros (FR-007), políticas explícitas de
  conflito em update (`--force` / `--keep`, exit 4 quando edit local
  detectado sem flag — FR-008).

  **Comandos**: `install`, `update`, `self-update`, `list`, `doctor`.

  **Profiles**: `sdd` (default — pipeline SDD com 10 skills),
  `complementary` (9 skills independentes), `all` (todos os 35 skills),
  `language-go`, `language-dotnet`. Cherry-pick por nome também
  suportado; modo interativo via `--interactive` (seletor numerado em
  TTY).

  **Escopos**: `--scope global` (`~/.claude/skills/`, default) e
  `--scope project` (`./.claude/skills/`). Hooks de `language-*` são
  instalados APENAS em escopo de projeto (FR-009c) com merge automático
  de `settings.json` quando `jq` disponível, ou paste-block instrucional
  quando ausente (FR-009d).

  **Self-update atômico** (FR-006): par `bin + lib` tratado como unidade
  indivisível via stage-and-rename coordenado + boot-check de versão
  embutida vs versão da lib. Nunca toca o manifest de skills (FR-006a;
  verificável: mtime do `.cstk-manifest` preservado).

  **Pipeline de release** em `.github/workflows/release.yml` —
  triggered por `push tag v*`, valida testes (`tests/run.sh` + cstk
  suite), gera tarball determinístico via `scripts/build-release.sh`
  e publica via `gh release create` com `cstk-X.Y.Z.tar.gz`,
  `.sha256` e `install.sh` (asset standalone para o one-liner
  `curl <url> | sh`).

  **Observabilidade**: `cstk list` (TSV/pretty) + `cstk doctor`
  (4 estados de drift: OK, EDITED, MISSING, ORPHAN — SC-007).

  **Determinismo do tarball** (`scripts/build-release.sh`): mtime
  normalizado, `gzip -n`, ordenação `LC_ALL=C sort`, detecção
  GNU-vs-BSD tar para paths portáveis. Verificado: 2 builds
  consecutivos produzem o mesmo SHA-256.

  **Cobertura de testes**: 242 cenários (`tests/run.sh` global), zero
  falhas. Gap real único (Scenario 13 SC-003 byte-a-byte) coberto por
  `tests/cstk/test_quickstart-e2e.sh`.

  Spec completa em [`docs/specs/cstk-cli/`](docs/specs/_archived/cstk-cli/);
  documentação user-facing em [`README.md`](./README.md) §Instalação.

### Governance

- **Constitution 1.0.0 → 1.1.0 (MINOR amendment)**: nova subseção "Optional
  dependencies with graceful fallback" sob Princípio II disciplinando deps
  não-POSIX em três condições cumulativas (uso opcional com fallback
  verificável, confinamento em único arquivo, declaração explícita na feature).
  Nota complementar no Decision Framework item 4 reconhece subseções de
  carve-out como mecanismo válido quando precedidas por amendment MINOR.
  Não afrouxa Princípio II — Bash-isms seguem proibidos, `ripgrep`/`fd`/`bats`
  permanecem banidos mesmo como opcionais, deps obrigatórias continuam vetadas.
  Primeiro caso concreto sob a nova regra: `jq` opcional em `cli/lib/hooks.sh`
  da feature `cstk-cli`. Ver `docs/specs/constitution-amend-optional-deps/`
  para histórico completo de raciocínio.

## [3.1.1] - 2026-04-20

Versão PATCH — correção de bug latente em `validate.sh` análogo ao
histórico de `metrics.sh` (commit `ead1b68`).

### Fixed

- **`validate.sh` deixa de poluir stderr com `integer expression expected`.**
  As linhas 244–245 continham o mesmo padrão defeituoso `grep -c ... || printf '0'`
  que quebrou `metrics.sh`: em no-match, `grep -c` imprime `"0"` e sai com
  exit 1, disparando o fallback que concatena outro `"0"` — resultado
  `"0\n0"` quebra as comparações aritméticas subsequentes. Fix aplica o
  padrão seguro `VAR=$(grep -c ...) || VAR=0`.
- **Bug latente adicional revelado**: a aritmética corrompida fazia com
  que os três `if` do bloco "Próximos Passos" (`Corrigir N ERRO(s)`,
  `N AVISO(s)`, `Nenhuma ação necessária`) falhassem silenciosamente em
  docs válidos. Com o fix, a mensagem de sucesso `- Nenhuma acao
  necessaria. Documentacao renderiza corretamente.` volta a aparecer
  quando aplicável.
- Tabela Resumo do stdout deixa de renderizar `| X | 0\n0 |` em duas
  linhas quando algum contador é zero — agora sempre em linha única
  `| X | 0 |`.

### Added

- **`tests/test_validate.sh :: scenario_stderr_limpo_em_docs_validos`**:
  regressão dedicada que captura stderr ao rodar `validate.sh` contra
  `fixtures/docs-site/valid/` e falha se contiver `"integer expression
  expected"` ou `"[: "`. Protege contra o retorno do bug histórico.
- **Assertion adicional em `scenario_docs_validos`**: trava como
  invariant a linha "Nenhuma acao necessaria" que agora aparece em docs
  válidos.
- Feature SDD completa em `docs/specs/fix-validate-stderr-noise/`:
  spec + plan + research + quickstart + tasks + checklists/requirements
  (29 subtarefas, 100% concluídas).

### Contract preserved

- Exit codes de `validate.sh` inalterados (0 em sucesso, 1 em ERROs).
- Estrutura do stdout (seções, colunas, severidades) inalterada.
- Apenas valores numéricos corrigidos onde estavam corrompidos, e
  stderr limpo. Nenhum teste existente em `test_validate.sh` quebrou.

## [3.1.0] - 2026-04-20

Versão MINOR — adição de suíte automatizada de testes para os scripts
POSIX distribuídos em `global/skills/**/scripts/`.

### Added

- **Suite automatizada de testes em `tests/`** cobrindo os 5 scripts
  shell do toolkit (`metrics.sh`, `next-task-id.sh`, `next-uc-id.sh`,
  `scaffold.sh`, `validate.sh`). Entry point único `tests/run.sh` executa
  44 scenarios em 3–4 segundos e reporta status trichotômico
  PASS / FAIL / ERROR no formato TAP.

- **Harness POSIX puro** em `tests/lib/harness.sh` com gestão isolada
  por `mktemp -d` + `trap EXIT/INT/TERM`, e os helpers `assert_exit`,
  `assert_stdout_contains`, `assert_stderr_contains`, `assert_stdout_match`,
  `assert_no_side_effect`, `fixture` e `run_all_scenarios`. Zero
  Bash-isms; zero dependências além das ferramentas POSIX canônicas.

- **Regressão dedicada do bug histórico de `metrics.sh`**
  (`scenario_regressao_bug_grep_c_sem_matches`) protegendo contra o
  retorno do padrão defeituoso `grep -c ... || printf '0'` que
  concatenava `"0\n0"` e quebrava expressões aritméticas. Validado
  revertendo o fix temporariamente durante a entrega: a suíte detectou
  3 FAILs incluindo o dedicado.

- **Modos do runner**: `--list` (lista scenarios sem executar),
  `--check-coverage` (detecta scripts sem teste e testes sem script;
  exit 1 em órfão), filtragem por `PATTERN` posicional, `--help`.

- **Governança de cobertura (FR-009 da spec)**: no modo normal, órfãos
  aparecem como warning (`ORPHANS: N` + bloco `# WARN:`) sem bloquear;
  no modo `--check-coverage`, órfãos fazem exit 1. Convenção estrita
  `tests/test_<nome>.sh` para cada `global/skills/<skill>/scripts/<nome>.sh`.

- **`tests/README.md`** com quickstart, arquitetura, formato TAP, exit
  codes, contrato do harness (tabelas de helpers) e guia para adicionar
  teste ao script novo.

- **Spec completa em `docs/specs/shell-scripts-tests/`**: `spec.md` +
  `plan.md` + `research.md` + `data-model.md` + `contracts/runner-cli.md`
  + `quickstart.md` + `checklists/requirements.md` + `tasks.md`. Feature
  entregue em 5 fases, 113 subtarefas, 100% concluídas.

### Known issue (fora do escopo desta release)

- `validate.sh` (linhas 273–284) contém o mesmo padrão
  `grep -c || printf '0'` do bug histórico de `metrics.sh`. Afeta
  apenas stderr (não exit code nem stdout). Registrado em
  `docs/specs/shell-scripts-tests/tasks.md` §FASE 2. Candidato para
  nova feature em ciclo SDD separado.

## [3.0.0] - 2026-04-20

Versão MAJOR devido a remoção de asset distribuído (contrato de instalação
muda — usuários que faziam `cp -r global/insights/` precisam migrar).

### Removed (BREAKING)

- **Diretório `global/insights/` removido do repositório.** O arquivo
  `usage-insights.md` que vivia ali era uma curadoria específica de sessões
  de um usuário (Go + TypeScript + PostgreSQL multi-serviço), não um playbook
  genérico. Distribuí-lo como parte do toolkit confundia quem clonava: o
  conteúdo era tratado como autoritativo quando era apenas o snapshot de um
  contexto.

  **Como fica agora**:

  - A skill `apply-insights` continua funcionando — ela sempre leu de
    `~/.claude/insights/usage-insights.md` (espaço do usuário), nunca de
    `global/insights/` diretamente.
  - Se o arquivo `~/.claude/insights/usage-insights.md` existir, a skill o
    usa. Caso contrário, cai em best-practices genéricas (comportamento
    já documentado no SKILL.md).
  - O modelo recomendado agora: gerar o arquivo via a slash command nativa
    `/insights` do Claude Code (que analisa suas sessões reais) ou curá-lo
    manualmente. Cada usuário mantém o seu próprio.

  **Impacto para consumidores**:

  - O comando `cp -r global/insights/ ~/.claude/insights/` (documentado no
    README) não existe mais — o diretório-fonte foi removido.
  - Quem já tinha copiado o arquivo para `~/.claude/insights/` mantém a
    cópia local intocada.
  - README atualizado: seção "Insights de Uso" reescrita para refletir o
    modelo por-usuário; diagrama de estrutura e bloco de instalação
    limpos.
  - CLAUDE.md atualizado: seção "Renomeando uma skill" não referencia mais
    `global/insights/`.

### Migration

1. Se você dependia do arquivo distribuído:

   ```bash
   # O arquivo pode continuar no seu ~/.claude/insights/ se você já o copiou
   ls ~/.claude/insights/usage-insights.md

   # Caso contrário, gere o seu via o /insights nativo do Claude Code,
   # ou mantenha um playbook curado manualmente neste caminho
   ```

2. Se você referenciava `global/insights/` em scripts ou docs próprios,
   remover a referência — o caminho não resolve mais.

## [2.0.0] - 2026-04-19

Versão MAJOR devido a rename de skill user-visível (identificador de invocação
é contrato público).

### Changed (BREAKING)

- **Skill `insights` renomeada para `apply-insights`** — o Claude Code tem uma
  slash command nativa `/insights` (analisa suas sessões de uso) que colidia
  no namespace de autocomplete com a nossa skill homônima. As duas
  coexistiam sem uma sobrescrever a outra, mas a ambiguidade gerava atrito:
  - usuários precisavam selecionar a correta a cada invocação
  - documentação que referenciasse `/insights` ficava ambígua
  - hooks que tentassem invocar por string tinham comportamento indefinido

  Rename para `apply-insights` deixa claro que a função é **prescritiva**
  (aplicar um playbook ao projeto) — distinta da nativa, que é
  **introspectiva** (analisar sessões). A description da skill agora explicita
  essa diferença para o modelo.

  **Impacto para consumidores**:
  - Invocações via `/insights` agora rodam a skill nativa do Claude Code
  - Para a função antiga, usar `/apply-insights`
  - Arquivos CLAUDE.md / documentação que referenciavam `/insights` precisam
    ser atualizados

### Migration

1. Se o seu projeto tem instalação local: `.claude/skills/insights/` →
   `.claude/skills/apply-insights/`
2. Atualizar triggers em CLAUDE.md, memórias, hooks, scripts
3. Nova invocação: `/apply-insights` (ou qualquer dos triggers em português
   como "aplicar insights", "aplicar playbook", "melhorar claude.md")

## [1.1.0] - 2026-04-19

Refatoração ampla das 18 skills globais aplicando os princípios do artigo
["Skills no Claude Code: O Guia Definitivo"](./docs/artigo.md) e adicionando
1 nova skill. Todas as mudanças são backward-compatible na invocação pelo
nome — skills continuam respondendo aos mesmos triggers e argumentos.

### Added

- **Nova skill `validate-docs-rendered`** (categoria "Verificação de Produto"
  do artigo) — valida que a documentação Markdown realmente renderiza
  corretamente: diagramas Mermaid parseáveis, links internos sem 404,
  frontmatter YAML consistente, tabelas bem formadas, code blocks com
  linguagem declarada. Script POSIX `scripts/validate.sh` roda 5 checagens
  com exit code para uso em CI/hooks.

- **Seções `Gotchas` em todas as 18 skills preexistentes** — documentando
  armadilhas recorrentes e erros típicos. Segue a recomendação do artigo de
  que "o conteúdo mais valioso de uma skill é a seção de gotchas".

- **Scripts POSIX reutilizáveis em 4 skills**:
  - `initialize-docs/scripts/scaffold.sh` — cria estrutura 01-09 com READMEs
    template, idempotente, suporta `--dry-run`, `--force`, `--dir=PATH`
  - `create-use-case/scripts/next-uc-id.sh` — calcula próximo `UC-{DOMINIO}-NNN`
    disponível; suporta `--list` para auditar domínios existentes
  - `create-tasks/scripts/next-task-id.sh` — calcula próximo ID hierárquico
    (`1.3`, `1.2.4`) com regex ancorado para evitar falsos positivos
  - `review-task/scripts/metrics.sh` — extrai métricas de progresso do
    tasks.md em formato tabular + JSON

- **Arquitetura de skill-como-pasta** com subdiretórios para *progressive
  disclosure* em 8 skills (specify, plan, create-tasks, create-use-case,
  briefing, checklist, constitution, analyze):
  - `templates/` — templates preenchíveis (feature-spec, plan, tasks,
    briefing, constitution, data-model, contracts, quickstart, research,
    use-case)
  - `examples/` — exemplos concretos (specify tem `spec-good.md` e
    `spec-bad.md` com anti-patterns comentados)
  - `references/` — documentação de apoio (catálogos de items por domínio
    para checklist; consistency-checks para analyze; discovery-guide
    detalhado para briefing)

- **Composição explícita do pipeline SDD** — cada skill do pipeline agora
  documenta em seções `## Pré-requisitos` e `## Próximos passos` quais
  artefatos consome e qual skill é o passo lógico seguinte. Torna a sequência
  briefing → constitution → specify → clarify → plan → checklist →
  create-tasks → analyze → execute-task → review-task navegável sem
  tooling formal de dependências.

- **`config.json` em 3 skills** para configuração por projeto:
  - `create-use-case/config.json` — mapa de domínios customizados, output_dir,
    formato de ID, mínimos de qualidade
  - `create-tasks/config.json` — níveis de criticidade, paths de output
    (spec_derived vs standalone), prefixo de fase, granularidade
  - `initialize-docs/config.json` — estrutura de diretórios customizável,
    `keep_in_root`, `file_routing` por padrão

  Quando `config.json` está ausente, as skills usam defaults documentados.
  Quando presente, o projeto adapta as convenções sem bifurcar a skill.

### Changed

- **Reescrita do campo `description` de todas as 18 skills** no formato de
  *trigger conditions* ("Use quando o usuário X, Y ou Z. Também quando
  mencionar A, B, C. NÃO use quando W.") em vez de resumo. Isso melhora
  descoberta — o modelo precisa decidir *quando* invocar a skill, não apenas
  o que ela faz. Particularmente relevante com Opus 4.7, que interpreta
  descrições de forma mais literal.

- **Agnosticização completa das skills** — removidas referências específicas
  a projetos, stacks e convenções de qualquer cliente/codebase. Skills agora
  tratam stack (Go/Python/React/etc.), domínios de negócio (AUTH/CAD/PED) e
  paths internos (`services/{service}/...`) como exemplos ilustrativos
  marcados, não como assunções. Cada skill funciona em qualquer projeto.

- **`bugfix` reescrita para ser stack-agnostic** — os 8 passos do protocolo
  (Step 0..7) agora usam terminologia genérica de camadas ("server /
  backend", "client / frontend", "cross-boundary") em vez de listas
  específicas de Go/React. Comandos de build/test/lint apresentados em
[5.34.0]: https://github.com/JotJunior/cstk/releases/tag/v5.34.0
[5.33.4]: https://github.com/JotJunior/cstk/releases/tag/v5.33.4
[5.33.3]: https://github.com/JotJunior/cstk/releases/tag/v5.33.3
[5.33.2]: https://github.com/JotJunior/cstk/releases/tag/v5.33.2
[5.33.1]: https://github.com/JotJunior/cstk/releases/tag/v5.33.1
[5.33.0]: https://github.com/JotJunior/cstk/releases/tag/v5.33.0
  tabela por stack.

- **`execute-task` reescrita para ser stack-agnostic** — Etapa 7 (Lint) é
  agora uma tabela com comandos típicos por stack (Go, Node, Rust, Python,
  Java, .NET) em vez de assumir `go build ./...`.

- **`create-use-case`: domínios deixam de ser enum fixo** — a lista antiga
  (AUTH, CAD, PED, FIN, FAT, LOG, MON, INAD, REC, PROP, CONT, DOM) virou
  exemplo; a skill consulta `config.json` ou UCs existentes antes de
  perguntar ao usuário.

- **Templates extraídos do SKILL.md para arquivos separados** — reduzem o
  custo de contexto no momento da invocação: o modelo carrega o template
  só quando preenche, não toda vez que decide se invoca a skill.

### Moved

- `global/skills/create-use-case/template-uc.md` →
  `global/skills/create-use-case/templates/use-case.md`
  (alinhamento com a convenção `templates/` das demais skills)

### Documentation

- README.md atualizado com:
  - Seção "Anatomia de uma skill" documentando a arquitetura (SKILL.md +
    templates/examples/references/scripts/config.json)
  - Esclarecimento de que domínios (AUTH/CAD/PED/etc.) são configuráveis
    por projeto, não uma lista universal
  - Seção "Contribuindo" revisada com guidelines para novas skills
    (trigger-condition descriptions, gotchas, progressive disclosure)
  - Link para este CHANGELOG

### Estatísticas desta versão

- 18 skills preexistentes atualizadas
- 1 skill nova (`validate-docs-rendered`)
- 19 arquivos novos de templates/references/examples
- 5 scripts POSIX (4 nas skills existentes + 1 na skill nova)
- 3 arquivos `config.json`
- 5 commits incrementais (uma fase por commit)

---

## [1.0.0] - 2026-04-18

Primeira versão publicada do toolkit.

### Added

- 18 skills globais cobrindo pipeline SDD completo (briefing, constitution,
  specify, clarify, plan, checklist, create-tasks, analyze, execute-task,
  review-task) e skills complementares (advisor, bugfix, create-use-case,
  image-generation, initialize-docs, insights, owasp-security,
  validate-documentation)
- Skills específicas para Go (commit, create-report, go-add-entity,
  go-add-migration, go-add-test, go-add-consumer, go-review-pr,
  go-review-service) e hooks de validação
- Skills específicas para .NET (create-entity, create-feature,
  create-project, create-test, hexagonal-architecture, infrastructure,
  review-code, testing)
- Arquivo `global/insights/usage-insights.md` com padrões extraídos de 134
  sessões reais de uso
- README documentando estrutura, pipeline SDD sugerido e convenções de
  nomenclatura

[5.32.0]: https://github.com/JotJunior/cstk/releases/tag/v5.32.0
[5.31.0]: https://github.com/JotJunior/cstk/releases/tag/v5.31.0
[5.30.0]: https://github.com/JotJunior/cstk/releases/tag/v5.30.0
[5.29.0]: https://github.com/JotJunior/cstk/releases/tag/v5.29.0
[5.28.0]: https://github.com/JotJunior/cstk/releases/tag/v5.28.0
[5.27.0]: https://github.com/JotJunior/cstk/releases/tag/v5.27.0
[5.26.0]: https://github.com/JotJunior/cstk/releases/tag/v5.26.0
[5.25.0]: https://github.com/JotJunior/cstk/releases/tag/v5.25.0
[5.24.0]: https://github.com/JotJunior/cstk/releases/tag/v5.24.0
[5.23.0]: https://github.com/JotJunior/cstk/releases/tag/v5.23.0
[5.22.0]: https://github.com/JotJunior/cstk/releases/tag/v5.22.0
[5.21.0]: https://github.com/JotJunior/cstk/releases/tag/v5.21.0
[5.20.0]: https://github.com/JotJunior/cstk/releases/tag/v5.20.0
[5.19.0]: https://github.com/JotJunior/cstk/releases/tag/v5.19.0
[5.18.0]: https://github.com/JotJunior/cstk/releases/tag/v5.18.0
[5.17.0]: https://github.com/JotJunior/cstk/releases/tag/v5.17.0
[5.16.1]: https://github.com/JotJunior/cstk/releases/tag/v5.16.1
[5.16.0]: https://github.com/JotJunior/cstk/releases/tag/v5.16.0
[5.15.0]: https://github.com/JotJunior/cstk/releases/tag/v5.15.0
[5.14.1]: https://github.com/JotJunior/cstk/releases/tag/v5.14.1
[5.14.0]: https://github.com/JotJunior/cstk/releases/tag/v5.14.0
[5.13.0]: https://github.com/JotJunior/cstk/releases/tag/v5.13.0
[5.12.0]: https://github.com/JotJunior/cstk/releases/tag/v5.12.0
[5.11.1]: https://github.com/JotJunior/cstk/releases/tag/v5.11.1
[5.11.0]: https://github.com/JotJunior/cstk/releases/tag/v5.11.0
[5.10.2]: https://github.com/JotJunior/cstk/releases/tag/v5.10.2
[5.10.1]: https://github.com/JotJunior/cstk/releases/tag/v5.10.1
[5.10.0]: https://github.com/JotJunior/cstk/releases/tag/v5.10.0
[5.9.0]: https://github.com/JotJunior/cstk/releases/tag/v5.9.0
[5.8.0]: https://github.com/JotJunior/cstk/releases/tag/v5.8.0
[5.7.0]: https://github.com/JotJunior/cstk/releases/tag/v5.7.0
[5.6.0]: https://github.com/JotJunior/cstk/releases/tag/v5.6.0
[5.5.0]: https://github.com/JotJunior/cstk/releases/tag/v5.5.0
[5.4.0]: https://github.com/JotJunior/cstk/releases/tag/v5.4.0
[5.3.0]: https://github.com/JotJunior/cstk/releases/tag/v5.3.0
[5.2.0]: https://github.com/JotJunior/cstk/releases/tag/v5.2.0
[5.1.0]: https://github.com/JotJunior/cstk/releases/tag/v5.1.0
[5.0.0]: https://github.com/JotJunior/cstk/releases/tag/v5.0.0
[4.10.0]: https://github.com/JotJunior/cstk/releases/tag/v4.10.0
[4.9.1]: https://github.com/JotJunior/cstk/releases/tag/v4.9.1
[4.9.0]: https://github.com/JotJunior/cstk/releases/tag/v4.9.0
[4.8.0]: https://github.com/JotJunior/cstk/releases/tag/v4.8.0
[4.7.2]: https://github.com/JotJunior/cstk/releases/tag/v4.7.2
[4.7.1]: https://github.com/JotJunior/cstk/releases/tag/v4.7.1
[4.7.0]: https://github.com/JotJunior/cstk/releases/tag/v4.7.0
[4.6.2]: https://github.com/JotJunior/cstk/releases/tag/v4.6.2
[4.6.1]: https://github.com/JotJunior/cstk/releases/tag/v4.6.1
[4.6.0]: https://github.com/JotJunior/cstk/releases/tag/v4.6.0
[4.5.0]: https://github.com/JotJunior/cstk/releases/tag/v4.5.0
[4.4.0]: https://github.com/JotJunior/cstk/releases/tag/v4.4.0
[4.3.4]: https://github.com/JotJunior/cstk/releases/tag/v4.3.4
[4.3.3]: https://github.com/JotJunior/cstk/releases/tag/v4.3.3
[4.3.2]: https://github.com/JotJunior/cstk/releases/tag/v4.3.2
[4.3.1]: https://github.com/JotJunior/cstk/releases/tag/v4.3.1
[4.3.0]: https://github.com/JotJunior/cstk/releases/tag/v4.3.0
[4.2.0]: https://github.com/JotJunior/cstk/releases/tag/v4.2.0
[4.1.1]: https://github.com/JotJunior/cstk/releases/tag/v4.1.1
[4.1.0]: https://github.com/JotJunior/cstk/releases/tag/v4.1.0
[4.0.0]: https://github.com/JotJunior/cstk/releases/tag/v4.0.0
[3.19.1]: https://github.com/JotJunior/cstk/releases/tag/v3.19.1
[3.19.0]: https://github.com/JotJunior/cstk/releases/tag/v3.19.0
[3.18.0]: https://github.com/JotJunior/cstk/releases/tag/v3.18.0
[3.17.0]: https://github.com/JotJunior/cstk/releases/tag/v3.17.0
[3.16.0]: https://github.com/JotJunior/cstk/releases/tag/v3.16.0
[3.15.0]: https://github.com/JotJunior/cstk/releases/tag/v3.15.0
[3.14.0]: https://github.com/JotJunior/cstk/releases/tag/v3.14.0
[3.13.0]: https://github.com/JotJunior/cstk/releases/tag/v3.13.0
[3.12.0]: https://github.com/JotJunior/cstk/releases/tag/v3.12.0
[3.11.0]: https://github.com/JotJunior/cstk/releases/tag/v3.11.0
[3.10.0]: https://github.com/JotJunior/cstk/releases/tag/v3.10.0
[3.9.1]: https://github.com/JotJunior/cstk/releases/tag/v3.9.1
[3.9.0]: https://github.com/JotJunior/cstk/releases/tag/v3.9.0
[3.8.0]: https://github.com/JotJunior/cstk/releases/tag/v3.8.0
[3.7.0]: https://github.com/JotJunior/cstk/releases/tag/v3.7.0
[3.6.0]: https://github.com/JotJunior/cstk/releases/tag/v3.6.0
[3.5.3]: https://github.com/JotJunior/cstk/releases/tag/v3.5.3
[3.5.2]: https://github.com/JotJunior/cstk/releases/tag/v3.5.2
[3.5.1]: https://github.com/JotJunior/cstk/releases/tag/v3.5.1
[3.5.0]: https://github.com/JotJunior/cstk/releases/tag/v3.5.0
[3.4.0]: https://github.com/JotJunior/cstk/releases/tag/v3.4.0
[3.3.0]: https://github.com/JotJunior/cstk/releases/tag/v3.3.0
[3.2.3]: https://github.com/JotJunior/cstk/releases/tag/v3.2.3
[3.2.2]: https://github.com/JotJunior/cstk/releases/tag/v3.2.2
[3.2.1]: https://github.com/JotJunior/cstk/releases/tag/v3.2.1
[3.2.0]: https://github.com/JotJunior/cstk/releases/tag/v3.2.0
[3.1.1]: https://github.com/JotJunior/cstk/releases/tag/v3.1.1
[3.1.0]: https://github.com/JotJunior/cstk/releases/tag/v3.1.0
[3.0.0]: https://github.com/JotJunior/cstk/releases/tag/v3.0.0
[2.0.0]: https://github.com/JotJunior/cstk/releases/tag/v2.0.0
[1.1.0]: https://github.com/JotJunior/cstk/releases/tag/v1.1.0
[1.0.0]: https://github.com/JotJunior/cstk/releases/tag/v1.0.0
