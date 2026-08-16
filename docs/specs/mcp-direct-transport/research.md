# Research: Transporte MCP direto (sem container, resolucao por chamada)

**Feature**: `mcp-direct-transport` | **Date**: 2026-08-16 | **Phase**: 0

## Como ler este documento

Todas as Decisions abaixo foram produzidas com **auditoria empirica do
codigo real** durante a onda-004 desta execucao autonoma, e estao
registradas no `state.json`/`state.db` da feature com o campo `evidence`
contendo a citacao literal que as sustenta. Nenhuma foi derivada de
suposicao sobre como o sistema "provavelmente" funciona (Constitution VI).

A coluna **Decisao** referencia o id auditavel no state
(`.claude/feature-00c-state/mcp-direct-transport/`), consultavel via:

```sh
state-rw.sh read --state-dir <SD> | jq '.decisions[] | select(.id=="dec-021")'
```

| # | Tema | Decisao |
|---|------|---------|
| 0 | Memoria cross-feature (read-back) | dec-020 |
| 1 | Ponto de corte do bootstrap | dec-021 |
| 2 | Custo da resolucao por chamada + cache | dec-022 |
| 3 | Envs do launcher apos a saida do Docker | dec-023 |
| 4 | Gap pre-existente: auditoria nunca cabeada | dec-024 |
| 5 | Onde passa a viver o `dist/` do servidor | dec-025 |
| 6 | Runtime x catalogo (duas metades da instalacao) | dec-026 |
| 7 | Superficie real em `stop`/`gc`/`status` | dec-027 |
| 8 | Causa-raiz do sintoma e fluxo do token | dec-028 |
| 9 | Regressao de seguranca SEC-H2 | dec-029 |
| 10 | Mudanca de contrato na vida do processo | dec-030 |
| 11 | Orfao de cobertura ao remover `mcp-docker.sh` | dec-033 |
| 12 | Lacuna de gate: `npm test` nao roda em CI | dec-034 |
| 13 | Ordem de corte entre as camadas | dec-035 |

> dec-031 e dec-032 sao decisoes de processo da execucao autonoma
> (encerramento da onda-004 por orcamento e roteamento de modelo da onda),
> nao decisoes tecnicas da feature — registradas no state, fora deste
> documento por nao afetarem o desenho.

---

## Decision 0 — Consulta a memoria de execucoes anteriores (read-back)

**Decision**: consumir os achados historicos da `knowledge.db` como
contexto do plano, tratando-os como referencia nao-autoritativa.

**Rationale**: 3 dos 4 achados recuperados sao **o sintoma exato que esta
feature resolve**, observado em execucoes independentes: tools
`mcp__cstk-state__*` ausentes do toolset do subagente apesar de o servidor
constar como ativo (`esp32-c6`/onda-004, `cstk/state-db-runtime-parity`/
onda-006, `reality`/onda-007). Isso eleva o problema de "incomodo local"
para **padrao reproduzido em 3 projetos distintos**. O 4o achado
(`orchestrator-mcp-allowlist`/onda-009) e o finding de seguranca do token
usado como sufixo do nome do container — vetor que **desaparece** com a
remocao do Docker, e que a US3/FR-009 formaliza.

**Alternatives considered**: ignorar a memoria e planejar so a partir da
spec — rejeitado: perderia a confirmacao independente de que o sintoma nao
e ambiental desta maquina.

**Evidencia**: dec-020 (K=4 achados injetados, anti-eco
`--exclude-feature mcp-direct-transport`).

---

## Decision 1 — Ponto de corte do bootstrap: so a SESSAO migra para por-chamada

**Decision**: mover para resolucao por chamada **apenas** a sessao. Os
demais limites resolvidos no startup permanecem por processo.

**Rationale**: a auditoria do `bootstrap()` mostrou que, das 3 coisas
resolvidas no startup, **so uma depende da sessao**:

| Resolvido no startup | Depende da sessao? | Destino |
|----------------------|--------------------|---------|
| `resolveActiveSession({projectPath, token, env})` | SIM | migra para por-chamada |
| `parseMaxToolCalls(env.MCP_MAX_TOOL_CALLS)` | NAO (puro env) | permanece por processo |
| `resolveScriptsDir(env)` / `resolveEnforcementLogPath(env)` | NAO (puro env) | permanece por processo |

O ponto decisivo e **o quao pouco as tools usam da sessao**: um grep por
`session.<campo>` em todo `src/` retorna somente `session.stateDir` e
`session.token`. Os campos `targetProjectPath`, `shortName`,
`executionKind`, `mode` e `container` **nunca sao lidos por tool alguma**.
Ou seja, o objeto que hoje amarra o processo inteiro a uma execucao e, na
pratica, um par `(stateDir, token)` — o que torna a migracao para
resolucao por chamada uma mudanca pequena e bem delimitada, nao uma
refatoracao do servidor.

**Consequencia que MUST ser documentada**: `maxToolCalls` permanece um
contador **por processo**, mas **muda de semantica**. Hoje o comentario em
`index.ts:128-131` justifica o contador com "sessao == processo, um
container por execucao" — premissa que deixa de valer: o processo passa a
poder atender N sessoes. O teto SEC-L1 passa a ser um limite do
**processo/sessao-do-harness**, nao mais da execucao autonoma.

**Alternatives considered**: mover tambem `maxToolCalls` para por-sessao
(contador em mapa `token -> usados`) — rejeitado nesta feature: nenhum FR
pede, adiciona estado mutavel em memoria com ciclo de vida proprio, e a
mudanca de semantica documentada e suficiente para nao enganar o leitor.

**Evidencia** (dec-021): `index.ts:124` `const session = await
resolveActiveSession({ projectPath, token, env });` — chamada unica.
Confirmado nesta onda: `bootstrap()` (`index.ts:114`) so registra as tools
(`server.registerTool`, primeira ocorrencia em `index.ts:152`) **depois**
da linha 124, com o comentario `index.ts:120-123` declarando a escolha
fail-closed explicitamente: "sem sessao resolvida, o servidor nao registra
NENHUMA tool de mutacao".

---

## Decision 2 — Resolucao por chamada: cachear `token -> state_dir`, revalidar SEMPRE

**Decision**: cachear **apenas** o mapeamento `token -> state_dir`, e
revalidar a autorizacao a cada chamada usando o **modo direto**
(`mcp-session.sh resolve --state-dir`). Nunca cachear a decisao de
autorizacao.

**Rationale**: o custo de resolver por chamada nao e uniforme — ele se
concentra no **tree-walk** (modo `--project-path`), que e O(N execucoes):
le `agente-00c-state/mcp-server.json` e faz glob em
`feature-00c-state/*/mcp-server.json`, com 2 spawns de `jq` por descritor.
O **modo direto** (`--state-dir`) ja existe, ja e testado, e le **um unico
descritor**.

O ponto critico e *o que* pode ser cacheado sem quebrar o fail-closed. O
mapeamento `token -> state_dir` e **estavel por construcao** (o token e
gerado uma vez por `cstk mcp start` e gravado naquele state-dir). Ja o
**status** da execucao muda no tempo — e e exatamente ele que autoriza ou
recusa. Como `_ms_check_descriptor` rele `stopped_at` do disco em toda
chamada, revalidar via modo direto preserva integralmente a rejeicao de
execucao terminal, reduzindo de O(N) para **1 descritor lido por chamada**.

**Alternatives considered**:

- **Cache com TTL do descritor inteiro** — **rejeitado por seguranca**:
  criaria uma janela (de duracao do TTL) em que um token de execucao ja
  terminal continuaria autorizando mutacao. Viola o invariante fail-closed
  do FR-003 e o Edge Case explicito da spec ("sessao terminal nunca
  autoriza mutacao"). Nenhum ganho de performance justifica isso.
- **Sem cache algum (tree-walk a cada chamada)** — funcionalmente correto
  e fail-closed, mas O(N) desnecessario quando a primeira resolucao ja
  descobriu o `state_dir` daquele token.

**Evidencia** (dec-022): `mcp-session.sh:130` `[ -z $_stopped ] || return
1   # execucao ja terminal — nunca roteia (fail-closed)` dentro de
`_ms_check_descriptor`, invocado tanto no modo direto (linha 200) quanto
no tree-walk (214/224); `mcp-session.sh:196-205` mostra o modo direto
lendo apenas `$_state_dir/mcp-server.json`, sem tree-walk.

---

## Decision 3 — Envs do launcher apos a saida do Docker

**Decision**: manter `CSTK_MCP_PROJECT_PATH`, **remover**
`CSTK_MCP_STATE_DIR` como env de processo, e tratar
`CSTK_MCP_SCRIPTS_DIR` como **obrigatoria na pratica**.

**Rationale**, env a env:

| Env | Destino | Por que |
|-----|---------|---------|
| `CSTK_MCP_PROJECT_PATH` | **mantida** | a primeira resolucao de um token desconhecido ainda precisa da raiz do projeto para o tree-walk |
| `CSTK_MCP_STATE_DIR` | **removida** | existia so porque, dentro do container, o path do host nao existia; amarra o processo a UMA execucao — incompativel com resolucao por chamada, onde o `state_dir` passa a ser derivado do token |
| `CSTK_MCP_SCRIPTS_DIR` | deixa de ser override opcional, vira **obrigatoria** | o default `/opt/cstk/scripts` e o mount do container e **nao existe no host** |
| `CSTK_MCP_ENFORCEMENT_LOG_PATH` | mesmo problema, porem **inerte hoje** | default `/data/enforcement-log.jsonl` tambem e path de container — ver Decision 4 |

**Alternatives considered**: manter `CSTK_MCP_STATE_DIR` como "dica" para
a primeira resolucao — rejeitado: reintroduziria a ambiguidade "qual
execucao este processo serve", que e precisamente o que FR-011 proibe
("nunca contra a sessao ativa mais provavel").

**Evidencia** (dec-023): `exec.ts:144` `const DEFAULT_SCRIPTS_DIR =
"/opt/cstk/scripts";`; `exec.ts:298` `const DEFAULT_ENFORCEMENT_LOG_PATH =
"/data/enforcement-log.jsonl";`; `resolve.ts:60` `const
CONTAINER_STATE_DIR_ENV = "CSTK_MCP_STATE_DIR";` com o comentario 51-58
explicitando que existe porque "dentro do container apenas /data/state
esta montado"; `mcp-launch.sh:123`
`_ml_project_path=${CSTK_MCP_PROJECT_PATH:-$(pwd)}`.

---

## Decision 4 — Gap pre-existente: `appendAuditRecord` implementado e nunca chamado

**Decision**: registrar como **gap pre-existente**, manter **fora do
escopo** desta feature, e documenta-lo no plano.

**Rationale**: a auditoria descobriu que `appendAuditRecord`
(`enforcement-log.jsonl`, FR-005/FR-006 da feature-base `state-mcp-server`)
esta implementado e coberto por testes, mas **nenhuma tool o chama**. Isso
significa que a trilha de auditoria do servidor MCP **ja nascia desligada**,
antes desta feature.

Cabear a auditoria agora seria mudanca de comportamento que **nenhum dos 15
FRs pede** e expandiria escopo. Mas o achado MUST constar no plano por dois
motivos concretos:

1. O default do path (`/data/enforcement-log.jsonl`) e **de dentro do
   container** e ficaria invalido apos o cutover — quem for cabear depois
   precisa saber que tera de derivar o path da **sessao resolvida**, nao de
   um default estatico.
2. Evita que a proxima auditoria conclua que **esta feature** quebrou a
   auditoria. Ela ja estava quebrada.

**Alternatives considered**: cabear a auditoria dentro desta feature —
rejeitado por escopo; remover o codigo morto — rejeitado: e implementacao
correta de um requisito real da feature-base, apenas nao ligada.

**Evidencia** (dec-024): `grep -rn 'appendAuditRecord(' mcp/state-server/src/`
retorna **uma unica** linha — `src/audit/log.ts:111:export async function
appendAuditRecord(` (a propria definicao). Nenhuma tool importa
`audit/log`; as unicas ocorrencias do modulo em `src/` fora do arquivo sao
**comentarios** (`record_skill.ts:76`, `sanitize.ts:5` e `:59`,
`exec.ts:88`). As 16 referencias restantes estao todas em
`test/audit-log.test.ts`.

---

## Decision 5 — Onde passa a viver o `dist/`: build lazy no host

**Decision**: **build lazy no host**, cacheado em
`~/.claude/mcp/state-server`, herdando o padrao ja em producao do painel
web (`cstk serve`).

**Rationale**: este era o ponto mais dificil do plano. Hoje o build
(`npm ci` + `tsc`) so acontece **dentro do `docker build`** que esta sendo
removido — sem ele, nao existe `dist/` em maquina instalada por tarball.
As 3 alternativas foram **medidas, nao supostas**:

| Alternativa | Custo medido | Veredito |
|-------------|--------------|----------|
| Pre-buildar no tarball | deps de producao ~50M descompactados **contra tarball atual de 1,0M** (~50x) + exige `setup-node` no `release.yml` | rejeitada |
| Bundle unico via esbuild | reduz tamanho, mas **adiciona devDep de bundling nova** e tambem exige `setup-node`; nenhum bundler existe na arvore hoje | rejeitada |
| **Build lazy no host** | tarball segue 1,0M; pipeline de release intocado | **escolhida** |

O ponto que desempata nao e so o tamanho: build lazy **nao e invencao**. E
exatamente o padrao ja em producao **no mesmo repo** para o painel web
(`cstk serve`), incluindo o preflight de major do Node e o registro do
major que rodou — problema de ABI/`NODE_MODULE_VERSION` ja enfrentado la
(issue #113). Herdar um mecanismo ja endurecido por bugfix real vale mais
que inventar um novo.

**Custo aceito e explicito** (nao minimizado): a **primeira** execucao numa
maquina exige `npm` + rede. Consequencia de desenho obrigatoria: o launcher
MUST **degradar para modo idle** enquanto o `dist/` nao existir — nunca
falhar a sessao. Um servidor que recusa subir por falta de build
reproduziria exatamente o sintoma da US1 que a feature existe para
eliminar.

**Evidencia** (dec-025), medicoes literais: `du -sh node_modules` = **57M**
total, devDeps (typescript 3,5M + @types 2,5M) = 6M, logo producao ~50M;
`ls -lh dist/*.tar.gz` do cstk = **1,0M** (`cstk-7.5.2-dev`);
`grep -ln setup-node .github/workflows/*.yml` **nao retorna nenhum
arquivo**. Precedente no repo: `cli/lib/serve.sh:574` executa o install de
pacotes no host dentro de `_serve_install`, com `cli/lib/serve.sh:127`
`_SERVE_SUPPORTED_NODE_MAJORS="20 22 23 24"` e `_serve_node_preflight`
(linha 160). Estado instalado auditado: `~/.claude/mcp/state-server/`
contem `src/ package.json package-lock.json tsconfig.json .dockerignore` e
**nao contem** `dist/` nem `node_modules/`.

Confirmacao adicional obtida nesta onda: `mcp/state-server/.gitignore`
lista `node_modules/` (linha 1) e `dist/` (linha 2), e
`scripts/build-release.sh:260-263` copia para o tarball **apenas** `src/`
mais `package.json package-lock.json tsconfig.json .dockerignore` — ou
seja, o tarball ja distribui **fonte, nunca build**, o que torna o build
lazy a continuacao natural do que ja existe (e nao uma mudanca de
politica de distribuicao).

---

## Decision 6 — A feature toca as DUAS metades da instalacao

**Decision**: documentar explicitamente no plano a divisao runtime x
catalogo, e exigir que ambas sejam atualizadas no mesmo passo.

**Rationale**: o GOTCHA do `CLAUDE.md` ("Installed vs Source Drift") vale
aqui com gravidade **acima do normal**:

| Arquivo | Metade | Atualizado por | Destino |
|---------|--------|----------------|---------|
| `cli/lib/mcp.sh`, `cli/lib/mcp-docker.sh`, binario `cstk` | **runtime** | `cstk self-update --from` | `~/.local` |
| `mcp-launch.sh`, `mcp-session.sh` | **catalogo** (skill `agente-00c-runtime`) | `cstk install` / `cstk update` | `~/.claude` |
| `mcp/state-server/` | **catalogo** | `cstk install` / `cstk update` | `~/.claude/mcp/state-server` |

O sintoma de atualizar so uma metade seria **pior que o classico**
"funciona-no-repo-mas-nao-na-sessao": um launcher novo (catalogo) tentando
`exec node` contra um `cstk mcp start` antigo (runtime) que ainda grava
`mode=docker` — combinacao que produz falha confusa em vez de erro claro.

**Evidencia** (dec-026): `cli/lib/install.sh:769-784`
`_install_apply_mcp_server` copia `catalog/mcp/state-server` para
`$HOME/.claude/mcp/state-server` e retorna cedo se `scope != global`;
`cli/install.sh:159-163` procura **exclusivamente** `*/cli/cstk` e
`*/cli/lib` no tarball, destino `$HOME/.local` (`INSTALL_BIN`/`INSTALL_LIB`
nas linhas 45-46) — nenhum dos dois toca a metade do outro.

---

## Decision 7 — Superficie real de mudanca em `stop`/`gc`/`status`: minima

**Decision**: mudanca **cirurgica**. O esforco concentra-se em `start` e no
launcher; `stop`/`gc`/`status` sao quase no-change.

**Rationale**: contra a intuicao de que "remover Docker" implica reescrever
o lifecycle inteiro, a auditoria mostrou que ele **ja e majoritariamente
agnostico**:

| Comando | FR | Situacao real |
|---------|-----|---------------|
| `stop` | FR-008 | ja agnostico: o `docker stop` e condicionado a `mode=docker`; sem esse branch a gravacao de `stopped_at` acontece identica — FR-008 (incl. idempotencia) **ja passa hoje sem Docker** |
| `gc` | FR-015 | ja degrada com `summary` e **exit 0** quando o preflight falha; FR-015 pede exatamente que **continue** recolhendo containers legados ⇒ **no-change** |
| `status` | FR-007 | o healthcheck de container e guardado por `--live` **e** `mode=docker`; sem `mode=docker` o bloco e pulado e o status ja vem do descritor |
| `start` | FR-006, FR-010, FR-014 | **aqui esta o trabalho**: hoje encadeia preflight -> build -> run -> healthcheck |

**Evidencia** (dec-027): `mcp.sh:731` `if [ $_msp_mode = docker ] && [
$_msp_container != - ] && [ -n $_msp_container ]; then` guarda a **unica**
chamada docker do `stop`; `mcp.sh:805-808` `if ! _mcp_docker_preflight
2>/dev/null; then printf summary=docker-indisponivel examined:0 removed:0
kept:0 skipped:0; return 0`; `mcp.sh:349` `if [ $_live = 1 ] && [ $_mode =
docker ] && [ $_container != - ]` guarda o healthcheck do `status`.

---

## Decision 8 — Causa-raiz do sintoma e por onde o token passa a fluir

**Decision**: apos o cutover, o token flui **exclusivamente** pelo prompt
de spawn (FR-013) ate virar o argumento `session_id` de cada chamada. O
processo do servidor **nunca precisa conhece-lo no boot**.

**Rationale**: a causa-raiz mecanica do sintoma da US1 ("connected — no
tools") ficou estabelecida: o `.mcp.json` registrado e **estatico e nao tem
bloco `env`**. Logo `MCP_SESSION_TOKEN` **nunca chegou** ao launcher por
essa via, e o launcher caia **sempre** no modo idle (0 tools). Isso tambem
explica por que o achado empirico manual funcionou: la o token foi
exportado a mao.

Injetar `env` no `.mcp.json` seria a **correcao errada**, por 3 motivos
independentes:

1. o arquivo e escrito **uma vez** por `cstk mcp install`, nao por execucao;
2. o token **muda a cada** `cstk mcp start`;
3. colocar um token de capacidade num arquivo **versionavel do projeto**
   contraria SEC-H3 e a propria US3.

**Alternatives considered**: injetar `env.MCP_SESSION_TOKEN` no
`.mcp.json` (acima, rejeitada nos 3 pontos); manter o token so em env do
processo (impossivel apos a resolucao por chamada — o processo passa a
poder atender N sessoes).

**Evidencia** (dec-028): heredoc `MCPJSON` em `cli/lib/mcp.sh`:
`{ "mcpServers": { "cstk-state": { "type": "stdio", "command":
"$_mci_launcher", "args": [] } } }` — chaves `type`/`command`/`args`
apenas, **sem `env`**; o `.mcp.json` real do projeto confirma o mesmo
shape. `mcp-launch.sh:128-130` `if [ -z ${MCP_SESSION_TOKEN:-} ]; then
_ml_idle_serve nenhuma execucao 00c ativa nesta sessao (sem token)`.

Confirmacao adicional nesta onda: as tools **ja aceitam `session_id` como
argumento** e ja o validam — `record_decision.ts:55` `session_id:
z.string().min(1, "session_id obrigatorio")` e `:143` `if
(!matchesResolvedSession(session, input.session_id))`, com o mesmo par
presente em `open_wave.ts:31/68`, `get_status.ts:38/98`,
`close_wave.ts:105/246`. **Nenhum contrato de tool muda** nesta feature —
muda apenas *quando* a sessao contra a qual o argumento e comparado passa a
ser resolvida.

---

## Decision 9 — REGRESSAO DE SEGURANCA declarada: SEC-H2 perde enforcement

**Decision**: **declarar a regressao** e documentar a nova postura, sem
alegar paridade.

**Rationale**: o confinamento do servidor (SEC-H2) era **efeito de flags do
`docker run`** — monta so `/data/state`, os scripts `:ro` e o arquivo de
enforcement-log, nunca o `.claude` inteiro. Rodando `node` direto no host,
o processo **herda o filesystem do usuario**: nao ha como reproduzir a
montagem seletiva. **Alegar paridade seria, ele proprio, violacao do
Principio VI.**

A postura defensavel — e que o plano MUST expor — e que **o modelo de
ameaca muda de eixo**:

- **Antes**: confinamento do **PROCESSO** (o processo nao alcanca o que nao
  esta montado).
- **Depois**: confinamento da **AUTORIZACAO** (todo caminho de mutacao
  continua passando pelos helpers POSIX, que so tocam o state-dir resolvido
  **pelo token apresentado na chamada**).

Vale notar que o adversario do modelo original **ja era o conteudo lido
pelo LLM**, nao o proprio servidor — o servidor nunca foi a parte
nao-confiavel. Isso nao anula a perda; contextualiza-a.

**Contrapartida real, favoravel**: a US3/FR-009 **elimina** o vazamento do
token via nome de container — um vetor que existe hoje e tem finding
registrado.

**Ganho e perda MUST aparecer lado a lado no plano, sem spin.**

**Evidencia** (dec-029): `tests/cstk/test_mcp-docker.sh:486`
`scenario_run_sec_h2_montagens_proibidas` e `:389` `scenario_run_hardening`
sao os **unicos** pontos onde SEC-H2 e verificado, e ambos exercitam flags
do `docker run`; `cli/lib/mcp-docker.sh:333-342` mostra as 3 montagens
(state dir, scripts `:ro`, enforcement log) como argumentos do `docker
run` — **nenhuma tem equivalente em processo direto**.

---

## Decision 10 — Mudanca de contrato: vida do processo

**Decision**: **assumir a mudanca de contrato explicitamente**. O processo
passa a ser coextensivo com a **sessao do harness**; a **sessao MCP**
(descritor + token) permanece coextensiva com a **execucao**.

**Rationale**: ha conflito real entre dois contratos, e a spec corrente
escolheu o novo:

| Contrato | Origem | Diz que |
|----------|--------|---------|
| Antigo | FR-010 da feature-base `state-mcp-server` | sessao coextensiva com a EXECUCAO, sobrevive a pausas |
| **Novo** | **FR-012 desta spec** | processo encerra junto com a sessao do Claude Code |

A separacao que torna a mudanca **consistente** e: o **processo** morre com
a sessao do harness, enquanto o **descritor + token** permanecem no disco,
sobrevivendo a pausas. Reconectar o `/mcp` numa sessao nova **recria** o
processo, que volta a resolver o mesmo token por chamada — nada se perde
porque nada de duravel vivia no processo.

Preservar o contrato antigo exigiria um **daemon de longa duracao** —
exatamente o que a spec descarta.

**Consequencia obrigatoria**: os 2 cenarios de
`tests/test_command-spawn-mcp-lifecycle.sh` que hoje afirmam sobrevivencia
a pausa **passam a mentir** apos o cutover e MUST ser reescritos para
afirmar a nova divisao — senao a mudanca fica **sem teste que a proteja**.

**Evidencia** (dec-030): `spec.md` FR-012 "O processo do servidor MCP MUST
ser encerrado junto com a sessao do Claude Code que o hospeda, sem
permanecer ativo como processo orfao"; testes hoje vigentes em
`tests/test_command-spawn-mcp-lifecycle.sh:121` e `:125`
(`scenario_resume_*_nao_para_em_aguardando_humano`) codificam o contrato
ANTIGO.

---

## Decision 11 — Remover `mcp-docker.sh` orfana o teste e quebra `--check-coverage`

**Decision**: remover `cli/lib/mcp-docker.sh` e
`tests/cstk/test_mcp-docker.sh` **no MESMO commit**.

**Rationale**: o `--check-coverage` e **bidirecional** — detecta script sem
teste **e teste sem script**. Como `tests/run.sh` mapeia `*/cli/lib/*` para
`tests/cstk/test_<base>.sh` por convencao, o teste so e legitimo enquanto o
script existir. Separar os dois commits deixa a suite **vermelha entre
eles**, quebrando o bisect que o fatiamento por camadas (Decision 13)
existe para preservar.

**Alternatives considered**:

- Manter `cli/lib/mcp-docker.sh` vazio/stub — rejeitado: conservaria
  exatamente o codigo morto que o cutover existe para eliminar.
- Adicionar o teste a allowlist de "internos" (`_is_internal_test`) —
  rejeitado: **mentiria sobre a natureza do arquivo**. A allowlist e para
  testes de scripts *fora da convencao* de path; este e teste de um script
  *removido*. Usar a allowlist para esconder um orfao real corromperia o
  proprio sinal do `--check-coverage`.

**Evidencia** (dec-033): `tests/run.sh:58` `--check-coverage    Detecta
scripts sem teste e testes sem script;` e `:72` `1  Pelo menos um FAIL ou
ERROR (ou --check-coverage detectou orfao).`; `tests/run.sh:168`
`*/cli/lib/*)                 printf '%s\n' "$TESTS_ROOT/cstk/test_$_ets_base.sh" ;;`.

---

## Decision 12 — Lacuna de gate: os testes do servidor NAO rodam em CI

**Decision**: **registrar a lacuna** e manter a adicao do step de CI **fora
de escopo**; mitigar por validacao manual obrigatoria no `quickstart.md` e
como gate de aceite das fases.

**Rationale**: e uma lacuna **real e nao mitigada por esta feature**, e o
plano nao pode fingir que existe rede de protecao. Os 15 arquivos
`*.test.ts` de `mcp/state-server/test/` — incluindo `index.test.ts` e
`resolve.test.ts`, que cobrem **exatamente** o caminho que esta feature
reescreve — **so rodam por invocacao local**.

Adicionar `setup-node` ao `release.yml` acoplaria o pipeline de release do
toolkit inteiro (hoje POSIX-puro) a uma toolchain Node por causa de um
componente **opcional** — a mesma razao que reprovou o pre-build no tarball
(Decision 5). Fazer isso "de brinde" dentro desta feature tambem
expandiria escopo sem FR que o sustente.

**Alternatives considered**: workflow novo dedicado ao `mcp/` — nao
rejeitado por merito, mas por escopo; e candidato natural a feature
propria, e o plano o registra como recomendacao, nao como entrega.

**Mitigacao dentro do escopo**: `npm test` local vira **passo obrigatorio**
do `quickstart.md` e criterio de aceite declarado das fases que tocam
`mcp/state-server/`.

**Evidencia** (dec-034): `ls .github/workflows/` = `publish-site.yml
release.yml shellcheck.yml` (3 arquivos); `grep -rn
'npm|node-version|setup-node' .github/workflows/` retorna **zero linhas**.
`mcp/state-server/package.json` declara `"test": "npm run build && node
--test dist/test/*.test.js"` — existe, mas so dispara localmente.

---

## Decision 13 — Ordem de corte: fatiar por camada, cutover por ultimo

**Decision**: fatiar por **camada**, com o cutover do launcher como **ultimo**
passo observavel. **Nao** fatiar por User Story.

**Rationale**: o fatiamento por User Story (padrao SDD) **falha aqui** por
uma razao estrutural: as 3 stories compartilham **um unico ponto de corte
fisico**. Enquanto o servidor registrar tools so apos resolver a sessao,
**nenhuma** das 3 e observavel; assim que registrar antes, as 3 mudam
**juntas**.

O perigo concreto do fatiamento ingenuo e um **estado intermediario
enganoso**: o servidor ja registra tools (US1 *aparentemente* OK — `/mcp`
lista as 7 tools) mas os commands ainda condicionam a injecao do token a
`mode == "docker"` (FR-013 pendente). Resultado: **toda chamada morre em
`SESSION_MISMATCH`** e o operador conclui que a feature esta **quebrada**,
quando ela esta apenas **incompleta**. Esse e o pior desfecho possivel para
uma feature cujo objetivo e restaurar confianca no mecanismo MCP.

Dai a ordem: o **dist lazy** vem **antes** do launcher que depende dele; o
**cutover do launcher** (`exec node`) entra **depois** de servidor + CLI +
commands ja prontos.

**Alternatives considered**: big-bang num commit unico — rejeitado por
impedir `git bisect` numa mudanca que atravessa 3 linguagens (TypeScript,
POSIX sh, prosa de command).

**Evidencia** (dec-035): `spec.md` FR-013 "os commands `/agente-00c` e
`/feature-00c` MUST injetar o token ... a condicao anterior restrita a
`mode == docker` (`feature-00c.md:728` e `agente-00c.md:487`) MUST ser
removida/generalizada"; Decision 8 (dec-028) ja estabeleceu que o
`.mcp.json` nao tem bloco `env`, logo sem FR-013 o caminho fica **sem
token** mesmo com o servidor correto.

---

## NEEDS CLARIFICATION restantes

**Nenhum.** As 4 questoes de ambiguidade da spec foram resolvidas na fase
`clarify` (dec-010, dec-011, dec-014, dec-015 — ver `spec.md`
§Clarifications) e as 8 questoes tecnicas do desenho foram resolvidas
acima com evidencia literal.
