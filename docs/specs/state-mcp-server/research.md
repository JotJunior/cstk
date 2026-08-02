# Research: state-mcp-server

Documento produzido no Phase 0 do `/plan`. Resolve os `NEEDS CLARIFICATION` do
Technical Context antes do design.

## Convencao de marcacao (Principio VI — Veracidade de Dados)

Toda afirmacao factual neste documento carrega um destes rotulos:

| Rotulo | Significado |
|--------|-------------|
| **[VERIFICADO]** | Extraido de fonte rastreavel do repo (path + linha) ou de doc oficial citada |
| **[PROPOSAL]** | Desenho novo desta feature — nao existe ainda, sera validado na implementacao |
| **[NAO-VERIFICADO]** | Consultado em fonte externa mas sem confirmacao conclusiva; exige spike empirico antes de virar compromisso |
| **[OBSERVADO]** | Resultado literal de execucao REAL feita nesta execucao (onda 7, feature-00c, 2026-08-01) — servidor/subagente/container de fato rodados; nunca simulado |

Nada neste plano afirma como real uma assinatura de API que nao foi lida de uma
fonte. As lacunas estao concentradas na Decision 2 e no §Spike Obrigatorio.

---

## Decision 1: Como o servidor acessa o estado — delegar aos helpers POSIX vs SQL direto

**Decision**: **Delegar aos helpers POSIX do `agente-00c-runtime`** (invocacao de
subprocesso), NUNCA reimplementar regra de estado em JavaScript nem emitir SQL
direto contra `state.db`.

**Rationale**:

1. **Nao-duplicacao da regra e requisito da propria spec** (FR-014: "MUST NOT
   enfraquecer nenhuma garantia ... as ferramentas MCP sao uma interface aditiva
   sobre as mesmas invariantes"). Reimplementar em JS cria duas fontes de verdade
   que divergem no tempo — o modo de falha e silencioso e cumulativo.
2. **As invariantes exigidas pelos FRs ja existem e sao testadas nos helpers**
   [VERIFICADO]:
   - score 3 exige `--evidencia` >= 20 chars — `state-decisions.sh:208-215`
     (atende FR-002 sem escrever regra nova);
   - `--contexto` e `--justificativa` >= 20 chars — `state-decisions.sh:185-189`;
   - upsert idempotente de task — PK `(execution_id, task_id)` em `task_outcome`
     (`references/state-db-schema.sql:192`) (atende FR-004 no schema);
   - onda unica aberta — indice parcial `ux_wave_single_open` + trigger
     `trg_wave_close_once` (`state-db-schema.sql:119,125`) (atende parte de FR-009).
3. **Cobertura dos dois backends de graca** [VERIFICADO]: `_state-rw-db.sh:42-48`
   (`_sr_backend`) resolve `sqlite` sse `<state-dir>/state.db` existe, senao
   `json`. Delegando ao helper, o servidor MCP funciona nos dois sem saber a
   diferenca. SQL direto quebraria toda execucao com backend `json` — que
   permanece o default global enquanto `cstk state enable-sqlite` nao for rodado.
4. **Custo aceitavel**: o gargalo de uma onda e a inferencia do LLM (segundos),
   nao o `fork+exec` de um helper (ordem de dezenas de ms). Nao ha requisito de
   throughput na spec.

**Alternatives considered**:

- **SQL direto em `state.db` via `better-sqlite3`/`node:sqlite`**: rejeitado.
  Ganho de latencia irrelevante (item 4) contra duplicacao de ~6 conjuntos de
  regra de validacao e perda total do backend `json`. Violaria FR-014 na pratica.
- **Hibrido (leitura por SQL, escrita por helper)**: rejeitado por ora. Adiciona
  um segundo caminho de acesso para ganhar pouco (as tools desta feature sao de
  MUTACAO; leitura e secundaria). Reavaliar so se surgir tool de consulta pesada.

**Consequencia de desenho**: o container MUST conter `sh`, `jq` e `sqlite3` e MUST
montar o diretorio de scripts do runtime — ver Decision 5.

---

## Decision 2: Transporte MCP e ponto de registro (RISCO #1 da feature)

**Decision** [PROPOSAL]: **transporte `stdio`**, com **uma entrada estatica e
unica** no `.mcp.json` do projeto-alvo apontando para um *launcher* POSIX, e
**resolucao preguicosa (lazy) da execucao ativa a cada chamada de tool**. O
launcher e quem materializa o container Docker dedicado daquela execucao.

**Problema que forcou a decisao** [NAO-VERIFICADO — origem do spike]:

A documentacao do Claude Code indica que `claude mcp add`/edicao de `.mcp.json`
sao operacoes de terminal cujo efeito vale na **proxima** sessao; nao ha
confirmacao explicita de que um servidor MCP possa ser **adicionado a uma sessao
ja em curso**. Isso colide frontalmente com a User Story 2 ("o command pai sobe o
servidor no inicio de uma execucao autonoma"), porque o command pai roda *dentro*
de uma sessao ja iniciada. Se o registro so valesse na proxima sessao, o desenho
ingenuo ("o pai registra e sobe o servidor") nao entregaria tool nenhuma a
execucao corrente.

**Como a decisao contorna**: separar **registro** (estatico, feito uma vez por
projeto por `cstk mcp install`) de **roteamento** (dinamico, resolvido por
chamada). A entrada no `.mcp.json` nunca muda entre execucoes — muda apenas para
QUAL execucao o launcher roteia, e isso e decidido em tempo de chamada lendo o
disco. Com isso:

- FR-016 (instancia isolada por execucao) e preservado: o launcher materializa
  **um container por execucao**, nao um processo multiplexador. [PROPOSAL]
- Nao ha registro dinamico no `.mcp.json` — logo o entrave acima deixa de estar
  no caminho critico. [PROPOSAL]

**Resolucao da execucao ativa** [VERIFICADO como precedente]: reusar a MESMA
precedencia deterministica ja implementada pelo hook `PreToolUse` —
`agente-00c` vence; entre varias `feature-00c`, menor `short-name` lexicografico
(documentado em `CLAUDE.md` §Guardas enforced e implementado em
`global/skills/agente-00c-runtime/hooks/pretooluse-bash-guard.sh`). Nao inventar
uma segunda regra de precedencia: duas regras divergentes de "qual execucao esta
ativa" seria um bug latente entre o guard e o MCP.

**Nota sobre "porta" em FR-016**: com `stdio` **nao ha porta nem socket** — o
isolamento e por processo/container dedicado, que e *mais* forte que porta
dedicada (superficie de rede zero). Interpretamos o texto "sua propria
instancia/porta isolada" como exigencia de **isolamento fisico sem
multiplexacao**, que `stdio` satisfaz por construcao. Esta e uma
**interpretacao de desenho** [PROPOSAL], nao um fato — se o operador exigir
literalmente uma porta, ver a alternativa HTTP abaixo.

**Alternatives considered**:

- **Streamable HTTP com porta por execucao**: rejeitado como caminho primario.
  Exigiria que a URL no `.mcp.json` mudasse a cada execucao (porta efemera) —
  ou seja, exatamente o registro dinamico cuja viabilidade e [NAO-VERIFICADO].
  Alem disso abriria superficie de rede local (bind, `Origin`, DNS-rebinding),
  cujo tratamento pelo Claude Code tambem e [NAO-VERIFICADO]. Mantido como
  plano B **caso o spike prove** que registro mid-session funciona E que stdio
  nao atende.
- **Servidor unico multiplexando por sessao**: **rejeitado pela propria spec** —
  clarify de FR-016 decidiu "sem multiplexacao" (Clarifications, Session
  2026-08-01). Nao reabrir.
- **Processo Node local sem container**: **rejeitado pela propria spec** —
  clarify de FR-012 decidiu "sem modo Node-local intermediario". Sem Docker,
  cai direto no fallback Bash (FR-007).

---

## Decision 3: Atomicidade de `close_wave` (FR-003) sem transacao distribuida

**Decision** [PROPOSAL]: implementar `close_wave` como **sequencia ordenada com
compensacao por pre-imagem**, dentro de uma unica chamada de tool:

```
1. pre-imagem: copiar state.json  (backend json)
              ou  state.db + -wal + -shm  (backend sqlite)  para area temporaria
2. gerar backup da onda   (secrets-filter.sh for-backup)   -- efeito idempotente
3. state-ondas.sh end --motivo-termino <...>               -- mutacao
4. state-rw.sh sha256-update                                -- selo de integridade
5. em QUALQUER falha de 2-4: restaurar a pre-imagem e retornar erro
```

**Rationale**: a spec exige que "qualquer falha no meio do processo nao deixa a
onda em estado parcialmente fechado" (FR-003, US1 cenario 2) — o que exige
all-or-nothing **observavel**, nao necessariamente uma transacao SQL unica. Duas
das tres pos-condicoes (backup e hash) sao efeitos **fora** do banco, logo nenhuma
transacao SQLite as cobriria. Compensacao por pre-imagem e o mecanismo mais
simples que produz o efeito exigido e funciona identico nos dois backends.

Observacao [VERIFICADO]: a etapa 3 ja e atomica por si no backend sqlite — o
trigger `trg_wave_close_once` e o indice `ux_wave_single_open`
(`state-db-schema.sql:119,125`) impedem fechar duas vezes ou manter duas ondas
abertas. A compensacao existe para as etapas 2 e 4, nao para a 3.

**Alternatives considered**:

- **`BEGIN IMMEDIATE ... COMMIT` abrangendo tudo**: impossivel — backup e hash
  sao arquivos fora do banco; e inaplicavel ao backend `json`.
- **Ordem "end primeiro, backup depois"**: rejeitado — inverte o risco para o
  lado ruim (onda fechada sem backup e a falha que a spec quer proibir).
- **Aceitar fechamento parcial e confiar no `reconcile-wave`**: rejeitado como
  desenho primario (violaria FR-003 literalmente), mas o `reconcile-wave`
  permanece como rede de seguranca externa (US4 cenario 2).

---

## Decision 4: Exclusao mutua (FR-017) — o servidor MCP **nao** adquire o lock

**Decision**: o servidor MCP **NAO** chama `state-lock.sh acquire`. Ele opera
como delegado do orquestrador **dentro da janela de lock que o command pai ja
detem**, exatamente como o orquestrador faz hoje pelo caminho Bash.

**Rationale** — este e um achado que muda o desenho ingenuo:

1. [VERIFICADO] `state-lock.sh` e um mutex **mkdir-based e NAO-reentrante**
   (`_SL_LOCK="$_SL_STATE_DIR/.lock"`, `mkdir -- "$_SL_LOCK"` na linha 116;
   `rmdir` no release; exit 3 = ocupado; **sem deteccao de stale**, documentado
   explicitamente nas linhas 43-48 do proprio script).
2. [VERIFICADO] Na fronteira command↔orquestrador vigente, **o command pai
   adquire o lock antes de spawnar o orquestrador e so o libera depois que ele
   retorna** (documentado em `global/agents/agente-00c-feature-orchestrator.md`
   §"Fronteira command↔orquestrador (lock + init)" e no gemeo
   `agente-00c-orchestrator.md`; o orquestrador faz **zero** chamadas a
   `state-lock.sh`).
3. Logo, um servidor MCP que tentasse `acquire` durante uma onda receberia
   **exit 3 sempre** — o lock esta legitimamente ocupado pelo pai. Um retry
   ingenuo viraria espera infinita; um "force-acquire" quebraria a garantia.

**Como FR-017 e satisfeito entao**: por tres camadas ja existentes, nao por um
lock novo:

| Camada | Mecanismo | Fonte |
|--------|-----------|-------|
| Fronteira de execucao | lock de diretorio do command pai envolve a onda inteira (MCP e Bash operam ambos dentro dela) | contrato dos orquestradores [VERIFICADO] |
| Serializacao de chamadas | o orquestrador emite uma tool call por vez (nao ha concorrencia intra-onda) | modelo de execucao do harness [VERIFICADO] |
| Banco | `PRAGMA busy_timeout=5000` + retry ate 4 tentativas em `_state_db_exec_with_retry` (`_state-db.sh:122-142`) + `journal_mode=WAL` | [VERIFICADO] |

**Alternatives considered**:

- **Lock proprio do servidor (segundo mutex)**: rejeitado — dois mutex sobre o
  mesmo recurso e receita de deadlock, e o segundo nao protegeria contra o
  caminho Bash (que so respeita o primeiro).
- **Tornar `state-lock.sh` reentrante**: rejeitado nesta feature — alteraria uma
  primitiva de seguranca usada por todos os commands 00c; se necessario, e
  feature propria com spec propria (Principio I).

---

## Decision 5: Empacotamento Docker e montagens

**Decision** [PROPOSAL]: espelhar o precedente `cli/lib/serve-docker.sh`
[VERIFICADO nas linhas citadas], com o conjunto minimo de montagens:

| Montagem | Modo | Por que |
|----------|------|---------|
| `<state-dir>` (da execucao resolvida) | **rw** | unico alvo de mutacao (FR-008 confina a UMA execucao) |
| `<catalogo>/skills/agente-00c-runtime/scripts` | **ro** | helpers POSIX invocados (Decision 1); o servidor nao os altera |
| `<projeto-alvo>/.claude` | **rw** | destino do `enforcement-log.jsonl` (Decision 6) |
| `knowledge.db` / seu diretorio | **NAO MONTAR** | FR-013: knowledge.db permanece unico e read-only; a forma mais forte de garantir e ausencia total de montagem |

Herdado do precedente [VERIFICADO em `serve-docker.sh:712-724`]: `docker run`
com `--init`, `--rm`, `--name` dedicado, `--label` de gestao, `--cap-drop ALL`,
`--security-opt no-new-privileges`, `--read-only` (rootfs) e `--tmpfs
/tmp:rw,noexec,nosuid`. Imagem base `node:22-alpine` **pinada por digest**
(mesmo padrao de `_SD_BASE_IMAGE`). Build multi-stage com `package-lock.json`
obrigatorio (o precedente ja falha fechado sem lock — `serve-docker.sh:356`).

**Diferenca deliberada face ao precedente**: `serve-docker.sh` publica porta
(`-p host:port:8080`); aqui **nenhuma porta e publicada** — o transporte e
`stdio` via `docker run -i` (Decision 2). Superficie de rede do container: zero.

**Pacotes extras no estagio final** [PROPOSAL]: `jq` e `sqlite` (via `apk`),
exigidos pelos helpers (Decision 1). Devem ser instalados com versao pinada e
declarados; `sqlite3` >= 3.45.1 e o piso ja vigente no toolkit
[VERIFICADO: `_SB_MIN_SQLITE_VERSION="3.45.1"` em `state-backend.sh:69`].

**Risco conhecido a validar** [NAO-VERIFICADO]: os helpers POSIX rodam hoje em
`sh` do macOS/Linux; dentro do alpine rodarao sob **busybox**. O repo ja tem
historico de divergencia nesse eixo (memoria de projeto: "GOTCHA stat GNU-first").
Ver task de validacao no §Spike Obrigatorio.

---

## Decision 6: Trilha de auditoria (FR-005/FR-006)

**Decision** [PROPOSAL]: escrever em `<projeto-alvo>/.claude/enforcement-log.jsonl`
— o **mesmo arquivo** ja usado pelas guardas — com um `source` novo e proprio,
seguindo o contrato existente.

**Rationale**: [VERIFICADO] o arquivo ja e multi-writer com discriminacao por
campo `source`: `"pretooluse-bash-guard"` (hook, `pretooluse-bash-guard.sh:150-163`,
composto via `jq -nc`) e `"serve-integrity"` (`cli/lib/serve.sh:216-217`). Os
campos comuns aos dois writers sao `source`, `timestamp`, `outcome`; o restante e
especifico por writer. Adicionar um terceiro `source` e extensao natural do
contrato (`docs/specs/_archived/2026-07-28-enforced-guards/contracts/enforcement-log.md`),
nao um formato novo — e o operador ja tem ferramenta e habito de ler esse arquivo.

**Disciplina de segredos** [VERIFICADO como precedente obrigatorio]: o hook aplica
`secrets-filter.sh scrub` **ANTES** de truncar (`cut -c1-500`) — a ordem importa,
porque truncar antes poderia partir um segredo ao meio e derrota-lo o scrub. O
writer novo MUST replicar essa ordem (scrub → truncate) para o payload da tool.

**Alternatives considered**:

- **Arquivo separado (`mcp-tool-log.jsonl`)**: rejeitado — fragmentaria a trilha
  de auditoria do projeto em dois lugares, contra o espirito do Principio I
  (auditabilidade total, um lugar para olhar).
- **Registrar como `event` no proprio `state.db`**: rejeitado como **unico**
  destino — chamadas **rejeitadas** precisam sobreviver justamente quando a
  mutacao de estado nao aconteceu (FR-005 exige registrar a rejeicao). Escrever a
  rejeicao no estado que a rejeicao impediu de mutar e contraditorio.

---

## Decision 7: Deteccao de disponibilidade e fallback (FR-007/FR-011/FR-012)

**Decision** [PROPOSAL]: o **command pai** decide o caminho **antes** de delegar
ao orquestrador, e grava a decisao no state; o orquestrador nao "descobre"
sozinho:

```
1. cstk mcp status --state-dir <SD>   ->  active | unavailable:<motivo>
2. se active     : grava .mcp_state_server = {mode:"mcp", ...}
   se unavailable: grava .mcp_state_server = {mode:"bash", reason:"<motivo>"}
                   e a execucao segue exatamente como hoje (zero regressao)
3. em cada -resume: repetir 1 (health check por retomada, FR-010/FR-011)
```

**Rationale**: FR-007 exige "sem exigir intervencao manual" e FR-011 exige
"verificar que o container esta saudavel **antes** da primeira chamada". Ambos
sao responsabilidade natural do pai — que ja e quem detem lock, faz init e
seleciona modelo da onda (mesma fronteira). Colocar a deteccao no orquestrador
significaria descobrir a indisponibilidade **no meio** de uma onda, que e o caso
degradado (US4 cenario 2), nao o caminho normal.

Sem Docker no host: `unavailable:docker-absent` → fallback Bash direto, por
decisao ja tomada no clarify de FR-012. Nenhum modo Node-local.

---

## Decision 8: Linguagem, build e testes da arvore Node

**Decision** [PROPOSAL]:

- **TypeScript compilado para JS** no build multi-stage (o SDK oficial e TS; o
  runtime e Node 22). Identificadores em **ingles** (regra global do operador).
- **Testes de unidade com `node:test`** (runner embutido no Node >= 18) —
  **nao** adiciona dependencia de teste. Relevante porque o toolkit **bane
  nominalmente `bats`** e afins (Principio II); `node:test` nao e um framework
  externo, e parte do runtime ja obrigatorio para esta feature.
- **Testes dos `.sh` novos** seguem o harness POSIX existente, com o mapeamento
  ja gateado [VERIFICADO em `tests/run.sh:152-162`]:
  - `cli/lib/<n>.sh` → `tests/cstk/test_<n>.sh`
  - `global/skills/*/scripts/<n>.sh` → `tests/test_<n>.sh`
  `./tests/run.sh --check-coverage` sai 1 em orfao — logo cada `.sh` novo nasce
  com teste no mesmo commit.

**Fato relevante de contexto** [VERIFICADO]: **nao existe hoje nenhum
`package.json`, nenhum `.ts` e nenhuma referencia a `@modelcontextprotocol/sdk`
no repo**. Esta feature introduz a **primeira arvore Node** do `cstk` — o que e
motivo para confina-la num diretorio unico (`mcp/state-server/`) e nao espalhar
build de Node pela raiz do projeto.

---

## Fatos verificados sobre o SDK MCP (base dos contratos)

Consultados em documentacao oficial; registrados aqui para rastreabilidade.

| Fato | Status | Consequencia no desenho |
|------|--------|------------------------|
| Classe de servidor `McpServer`; registro via `server.registerTool(name, {description, inputSchema}, handler)` | [VERIFICADO — docs oficiais do SDK TS] | Base dos contratos em `contracts/mcp-tools.md` |
| `inputSchema` aceita Standard Schema (Zod v4 e compativeis); o SDK **valida o input antes de invocar o handler** | [VERIFICADO — docs oficiais] | **FR-002 e implementavel no schema**: score 3 sem evidencia e rejeitado antes de qualquer persistencia |
| Transportes server-side: `stdio` e Streamable HTTP | [VERIFICADO] | Decision 2 |
| Revisao 2026-07-28 da spec e stateless; header `Mcp-Session-Id` removido | [VERIFICADO] | Reforca resolucao lazy por chamada (Decision 2) — nao ha sessao de transporte para amarrar |
| `.mcp.json` (escopo project) com `mcpServers.<nome> = {type, url\|command, args, env, headers}`; precedencia local > project > user | [VERIFICADO] | `contracts/mcp-session-lifecycle.md` |
| Aceitacao de **JSON Schema cru** (sem Zod) pelo SDK | [OBSERVADO — REJEITADO, ver Spike S4] | `mcp/state-server/package.json` fixa `zod` como dependencia obrigatoria |
| Sintaxe exata de expansao de env em `.mcp.json` | [NAO-VERIFICADO] | Nao testada nesta onda (fora do escopo dos 5 spikes obrigatorios); nao depender dela ate confirmar |
| Padrao de nome de tool MCP em allowlist de subagente (`mcp__<server>__<tool>`?) | [OBSERVADO — CONFIRMADO, ver Spike S2] | Contratos em `contracts/mcp-tools.md` podem referenciar `mcp__state-mcp-server__<tool>` como nome literal |
| Subagente enxerga tools MCP herdadas da sessao | [OBSERVADO — CONFIRMADO com ressalva, ver Spike S1] | Consumidor primario (orquestrador→subagente) e viavel, DESDE QUE o servidor esteja registrado ANTES do boot da sessao top-level |
| Adicao de servidor MCP em sessao ja em curso | [OBSERVADO — NAO ENTRA EM VIGOR, ver Spike S3] | Confirma a necessidade da Decision 2 (entrada estatica, resolucao lazy por chamada) |
| Claude Code valida `Origin`/loopback em servidor HTTP local | [NAO-VERIFICADO] | Irrelevante no caminho `stdio` escolhido; so volta a importar no plano B |

---

## Spike Obrigatorio (FASE 0 da implementacao — gate antes de codar)

Nenhuma linha do servidor deve ser escrita antes destes cinco spikes. Motivo: a
feature inteira so tem valor se o **orquestrador (que e um subagente)** conseguir
chamar as tools. Se S1 falhar, nao existe consumidor — e o caminho correto e
**bloqueio humano**, nao contornar.

| ID | Pergunta empirica | Como validar | Se falhar |
|----|-------------------|--------------|-----------|
| **S1** | Um subagente spawnado via tool `Agent` consegue chamar uma tool MCP? | Servidor stdio minimo ("echo tool") + `.mcp.json` + subagente de teste que a invoca | **BLOQUEIO HUMANO** — feature perde o consumidor primario; reavaliar escopo |
| **S2** | Qual o nome exato da tool na allowlist `tools:` do frontmatter do subagente? | Inspecionar a tool exposta na sessao; testar allowlist com o nome descoberto | Sem o nome, o subagente nao consegue restringir/usar → escala junto de S1 |
| **S3** | `.mcp.json` novo/alterado passa a valer na sessao corrente? | Criar entrada com a sessao aberta e tentar usar | Confirma a necessidade da Decision 2 (entrada estatica); nao bloqueia |
| **S4** | O SDK aceita JSON Schema cru ou exige Zod? | Registrar uma tool de cada forma | Fixar Zod como dependencia (afeta `package.json`, nao o desenho) |
| **S5** | Os helpers POSIX rodam corretos sob busybox (alpine)? | Rodar `tests/run.sh` (subset de state) dentro do container | Trocar base para `node:22-slim` (Debian) — custo de tamanho, nao de desenho |

Cada spike encerra registrando **Decisao auditavel** com a saida observada como
`--evidencia` (aterramento empirico: score 3 exige evidencia literal de >= 20
chars — `state-decisions.sh:208-215`).

### Resultados observados (onda 7, feature-00c, 2026-08-01)

Todos os 5 spikes foram executados de fato (nao simulados). Harness descartavel
em scratchpad da onda (nao versionado no repo): servidor stdio minimo com
`@modelcontextprotocol/sdk` + `zod`, dependencias instaladas via
`docker run --network=host node:22.17.0 npm install` (o guard de package-manager
do host bloqueia `npm install` direto; o wrapper docker e o caminho aprovado).

**S1 — subagente consegue chamar tool MCP? [OBSERVADO: SIM, com pre-condicao]**

Duas tentativas:

1. **Dentro desta MESMA sessao ja em curso** (subagente geral spawnado via tool
   `Agent`, apos `claude mcp add -s user state-mcp-spike-s1 -- node
   <scratchpad>/server.js`): a tool NAO apareceu no catalogo do subagente
   (`tools_relacionadas_encontradas: nenhuma`). Resultado negativo, mas
   CONFUNDIDO — a sessao top-level ja estava rodando antes do registro.
2. **Processo `claude` NOVO** (`claude -p ... --allowedTools "Task,mcp__state-mcp-spike-s1__ping"`,
   cwd num projeto descartavel `mktemp -d`, servidor ja registrado em escopo
   `user` antes do boot): o processo usou a tool `Task` para spawnar um
   subagente `general-purpose`, que localizou e chamou
   `mcp__state-mcp-spike-s1__ping` com `{"echo":"subagent-nested-call"}` e
   recebeu de volta o texto literal `pong:subagent-nested-call`. Resposta
   textual completa do processo: *"Subagent's literal finding: `pong:subagent-nested-call`.
   The tool was available (as a deferred tool, schema loaded via ToolSearch
   before calling)."*

**Conclusao**: o consumidor primario (orquestrador spawnando subagente que
chama a tool) FUNCIONA — mas so quando o servidor MCP ja esta registrado
ANTES do boot do processo `claude`/da sessao. Registrar um servidor novo
NO MEIO de uma sessao ja em curso nao basta (ver S3). Para os orquestradores
00c em producao isso e naturalmente satisfeito: o `.mcp.json`/registro do
servidor `state-mcp-server` e provisionado durante `cstk install`, antes de
qualquer sessao `/agente-00c`/`/feature-00c` iniciar.

**S2 — nome exato da tool na allowlist [OBSERVADO: CONFIRMADO]**

O processo `claude -p` fresco, quando instruido a listar (sem chamar) tools
cujo nome contivesse "ping"/"mcp"/"state-mcp-spike-s1", reportou exatamente
uma: `` `mcp__state-mcp-spike-s1__ping` ``. Confirma literalmente o padrao
presumido `mcp__<nome-do-servidor>__<nome-da-tool>`.

**S3 — `.mcp.json`/registro de servidor novo vale na sessao corrente? [OBSERVADO: NAO]**

Coberto pela primeira tentativa de S1 acima: registrar o servidor em escopo
`user` (`claude mcp add -s user ...`) enquanto esta sessao ja estava aberta
NAO tornou a tool disponivel para um subagente spawnado nesta mesma sessao
depois do registro. Nao-bloqueante (ja esperado pelo desenho — Decision 2,
resolucao lazy por chamada, sem depender de "hot reload" de config).

**S4 — SDK aceita JSON Schema cru ou exige Zod? [OBSERVADO: REJEITA JSON Schema cru]**

`server.registerTool("ping-raw", { inputSchema: { type: "object", properties: {...} } }, ...)`
lancou em runtime, na propria chamada de registro (antes de qualquer conexao
de transporte):

```
Error: inputSchema must be a Zod schema or raw shape, received an unrecognized object
    at getZodSchemaObject (.../node_modules/@modelcontextprotocol/sdk/dist/esm/server/mcp.js:869:15)
    at McpServer._createRegisteredTool (.../server/mcp.js:611:26)
    at McpServer.registerTool (.../server/mcp.js:704:21)
```

A mesma tool registrada com `inputSchema: { echo: z.string().optional() }` (Zod
raw shape) funcionou normalmente; um cliente MCP padrao (`Client` +
`StdioClientTransport` do proprio SDK, testado fora do Claude Code) confirmou
`tools/list` retornando o schema convertido para JSON Schema no protocolo
(`"$schema": "http://json-schema.org/draft-07/schema#"`) e que **a validacao
roda antes do handler**: uma chamada com `{"echo": 123}` (tipo errado) voltou
`isError: true` com `"MCP error -32602: Input validation error: Invalid
arguments for tool ping: Invalid input: expected string, received number at echo"`
sem o handler ter sido executado (texto de retorno `pong:...` nunca apareceu).

**Consequencia**: `mcp/state-server/package.json` MUST fixar `zod` (ou outro
Standard Schema compativel) como dependencia direta — JSON Schema cru na API
`registerTool()` de alto nivel nao e uma opcao.

**S5 — helpers POSIX rodam corretos sob busybox (alpine)? [OBSERVADO: SIM, apos isolar 2 falsos-positivos do ambiente de teste]**

Container `node:20-alpine` (imagem ja em cache local), montando o repo
read-only, rodando o subset `tests/run.sh state-rw|state-ondas|state-decisions|bloqueios`:

- 1a rodada (root, sem `curl` no container): `state-rw` 72/73 pass (1 fail:
  `scenario_path_check_perm_negada`); `state-ondas` 118/119 pass (1 fail:
  `scenario_end_otel_usage_captura_delta_da_onda`, mensagem `esperado 6
  ((4-1)+(3.5-0.5)), obtido 'null'`); `state-decisions` 59/59; `bloqueios`
  40/40.
- Investigacao das 2 falhas (leitura de codigo, nao suposicao): (a) o teste de
  permissao nega escrita via `chmod`, mas o container roda como `root`
  (`uid=0`), que ignora bits de permissao — artefato do container, nao do
  script; (b) `otel-usage.sh` exige `curl` (`_ou_have_curl`) para o scrape —
  a imagem `node:20-alpine` base nao traz `curl` por padrao.
- Rodada de confirmacao com `curl` instalado (root): `state-ondas` **119/119
  pass, 0 fail**.
- Rodada de confirmacao como usuario nao-root (`adduser -D spiketester`,
  `su spiketester`): `state-rw` **73/73 pass, 0 fail**.

**Conclusao**: com o container configurado corretamente (usuario nao-root +
dependencias completas, `curl` incluido), as 291 cenas dos 4 arquivos de teste
passam integralmente sob busybox/alpine — nao ha divergencia de comportamento
dos helpers POSIX (`jq`, `sqlite3`, `awk`, aritmetica) atribuivel a alpine em
si. Base `node:XX-alpine` confirmada como viavel; nao ha motivo, por este
spike, para trocar para `node:22-slim` (Debian). O Dockerfile de producao do
servidor MUST incluir `curl` no conjunto de pacotes (junto de `jq`/`sqlite3`,
ja previstos) se algum dia depender de `otel-usage.sh`; caso contrario o alerta
serve como nota para o proprio Dockerfile de teste/CI.
