# Research: panel-docker

Documento do Phase 0 do `/plan`. Resolve os unknowns tecnicos do modo Docker
do `cstk serve` ANTES do design. Toda afirmacao concreta e aterrada na fonte
real (Constituicao Principio VI — Zero Fabricacao); o que nao pode ser afirmado
com fonte esta marcado `[NEEDS CLARIFICATION]` ou `[detalhe de execute-task]`.

## Fontes consultadas (aterramento)

| Fonte | Fato extraido (com localizacao) |
|-------|----------------------------------|
| `cli/lib/serve.sh` | panel dir `${CSTK_PANEL_DIR:-~/.local/share/cstk/panel}` (L530); porta default `${PORT:-5173}`, host `127.0.0.1` (L360-361); valida porta inteiro 1024-65535, <1024 exit 1 (L488-508); prereq `curl`+`npm` ANTES de rede (L519-527); GitHub API `https://api.github.com/repos/JotJunior/cstk-panel/releases/latest` (L55); integridade FAIL-CLOSED `.sha256` + bypass `--allow-unverified`/`CSTK_SERVE_ALLOW_UNVERIFIED=1`, mismatch bloqueia sempre (L270-313); enforcement-log em `$(pwd)/.claude/enforcement-log.jsonl` source `serve-integrity` (L147-182); build+start `export PORT` + `npm run build` + `npm run start` em background captura `_SERVE_NPM_PID` (L586-610); shutdown trap INT/TERM -> `_serve_shutdown` SIGTERM -> espera 5s (10x0.5s) -> SIGKILL (L103-123, L602); exit codes 0/1/2 (L8-11) |
| `cli/lib/trusted-hosts.sh` | `trusted_host_check`: `file://` isento, `https://` match EXATO de host case-insensitive com userinfo removido (L52-88); `CSTK_TRUSTED_RELEASE_HOSTS="github.com codeload.github.com objects.githubusercontent.com api.github.com"` NAO overridable via env (L47) |
| `cli/cstk` | dispatch `serve)` -> source `$CSTK_LIB/serve.sh` -> `serve_main "$@"` (L211-220) |
| `~/.local/share/cstk/panel/package.json` (v0.12.1) | `engines.node ">=20.0.0"`, `engines.npm ">=10.0.0"` (L28-31); root `start` = `node apps/server/dist/index.js` (L13); root `build` compila shared-types + server + web (L12) |
| `~/.local/share/cstk/panel/apps/server/package.json` | deps: `fastify ^5.0.0`, `@fastify/static ^8.0.0`, `better-sqlite3 ^9.6.0` (modulo NATIVO), `@fastify/cors`, `@fastify/rate-limit`, `zod` |
| `apps/server/src/config.ts` | porta `parseInt(process.env['PORT'] ?? '3001')` (L80); host `'127.0.0.1'` HARDCODED (L81); knowledge.db via env `CSTK_KNOWLEDGE_DB` (L49) senao `resolve(homedir(), '.claude','cstk','knowledge.db')` (L53) |
| `apps/server/src/index.ts` | `server.listen({ port: config.port, host: config.host })` (L110) — bind unico em 127.0.0.1 |
| `apps/server/src/db/open.ts` | `new Database(dbPath, { readonly: true, fileMustExist: false })` (L100-102) + `PRAGMA query_only = 1` (L121); comentario L15-19: `immutable=1` **nao e alcancavel** por better-sqlite3 (a lib nao repassa DSN query params), logo NAO ignora `-wal`/`-shm` |
| `~/.claude/cstk/knowledge.db` (empirico) | `PRAGMA journal_mode` = **wal**; sidecars `knowledge.db-shm` (32KB) e `knowledge.db-wal` presentes no diretorio |
| host (empirico) | `docker` em `/usr/local/bin/docker`; NENHUM codigo docker pre-existente em `serve.sh`/`cstk` (clean slate) |

---

## Decision 1: Estrategia de imagem — build local a partir da arvore verificada

**Decision** (revisada por **dec-037**, supersede **dec-011**): Construir uma imagem
Docker **local multi-stage** a partir da arvore-fonte do painel JA baixada e verificada
pelo fluxo de integridade existente. O `npm ci` e o `npm run build` do painel rodam
**DENTRO do estagio de build da imagem** (`RUN` no Dockerfile), nunca no host. Ambos os
estagios (build e runtime) partem da base oficial **`node:22-alpine`** (musl), que
satisfaz `engines.node ">=20.0.0"` (package.json L28). O `better-sqlite3` **e compilado
do fonte** no estagio de build (nao ha prebuild musl); o estagio de runtime slim so
recebe o painel ja buildado.

**Rationale**:
- **FR-006** exige que o modo Docker NAO precise de `npm` no host. Como `node`+`npm`
  vivem na imagem, o `npm ci`/`npm run build` do painel MUST ocorrer no estagio de
  build da imagem. O host so precisa de `docker` + `curl` (download/verificacao) + `tar`
  (extracao) — nunca `npm`/`node`.
- **Reuso da "Instalacao Verificada do Painel"** (spec Key Entities): o download +
  `trusted_host_check` + integridade fail-closed + extracao ja existem em
  `_serve_install` (serve.sh L194-354). O modo Docker reaproveita ESSE fluxo ate a
  extracao e alimenta a arvore verificada como contexto de `docker build` — sem
  segunda fonte de download nem segundo mecanismo de verificacao (FR-007).
- **Alpine/musl com compilacao do `better-sqlite3` no estagio de build**: `better-sqlite3
  ^9.6.0` (server package.json) e um **modulo nativo** (binding C++ do SQLite) e NAO tem
  prebuild musl, entao e **compilado do fonte** no estagio de build — que para isso
  instala o toolchain com `apk add --no-cache python3 make g++`. O `better_sqlite3.node`
  resultante linka musl (`libc.musl-aarch64.so.1`) e `require()` + create/insert/select
  funcionam (verificado empiricamente). O estagio de runtime nao carrega o toolchain
  (imagem slim). HISTORICO: a escolha original (**dec-011**) era base glibc
  (`node:20-bookworm-slim`) para aproveitar o prebuild sem compilador; **dec-037
  supersede dec-011** e adota alpine multi-stage por dois motivos — (a) o daemon do
  sandbox nao conseguia puxar a base glibc, e (b) alpine multi-stage com compilacao
  nativa no estagio de build e padrao de producao e as bases ja estavam em cache.

**Alternatives considered**:
- **Bind-mount do painel instalado no host dentro de uma imagem node generica**
  (Opcao B do prompt): REJEITADA — depende de o host ja ter feito o install nativo
  (com `npm`), violando FR-006 para hosts sem `npm`; e acopla o runtime do container
  a uma `node_modules` construida para a plataforma do host (nao necessariamente
  linux/container).
- **Base glibc com prebuild (ex.: `node:20-bookworm-slim`)**: era a escolha original
  (dec-011), agora REVERTIDA por **dec-037** (ver HISTORICO acima). O prebuild musl
  inexistente do `better-sqlite3` e resolvido de forma padrao compilando do fonte no
  estagio de build; mantida aqui apenas como registro historico.

**Fixado em execute-task (dec-037, verificado empiricamente):**
- Base fixada por digest, **ambos os estagios**:
  `node:22-alpine@sha256:16e22a550f3863206a3f701448c45f7912c6896a62de43add43bb9c86130c3e2`
  (digest lido de `docker inspect node:22-alpine` RepoDigests no host).
- Dockerfile **multi-stage**. Estagio `AS build`: `RUN apk add --no-cache python3 make
  g++` (toolchain) -> `COPY . .` -> `RUN npm ci` -> `RUN npm run build` (compila
  `better-sqlite3` do fonte + workspaces). Estagio de runtime: `RUN apk add --no-cache
  socat` -> `COPY --from=build --chown=node:node /app /app` -> entrypoint embutido via
  heredoc `COPY <<'EOF'` + `chmod +x` -> `USER node` -> `EXPOSE 8080` -> `ENTRYPOINT`.
  Usa `npm ci` (nao instalacao sem lockfile) a partir do `package-lock.json`.
- A diretiva `# syntax=docker/dockerfile:1` NAO e emitida: o frontend BuildKit builtin
  (Docker >= 23) suporta heredocs `COPY` nativamente, e emitir `# syntax` forcava um
  pull de imagem-frontend que travava no sandbox — omitir remove essa dependencia de
  rede.

---

## Decision 2: Encaminhador in-container (FR-005) — contrato + ferramenta recomendada

**Decision**: Rodar, dentro do container, um **processo leve de encaminhamento TCP**
que escuta em `0.0.0.0:<porta-interna-publicada>` e repassa para
`127.0.0.1:<porta-do-painel>` no MESMO network namespace. Ferramenta recomendada:
**`socat`** (relay TCP de proposito unico, uma linha). O painel continua fazendo
bind em `127.0.0.1` (config.ts L81) — nada muda no `cstk-panel` (Clarification da
spec: resolvido 100% do lado cstk/Docker).

**Rationale**:
- O servidor Fastify do painel faz bind **hardcoded** em `127.0.0.1` (config.ts L81,
  index.ts L110). Num container, `127.0.0.1` so aceita conexoes originadas do proprio
  netns; publicar a porta (`-p`) encaminha para a interface publicada do container
  (0.0.0.0), onde o painel NAO escuta. Logo, publicar a porta sozinho NAO torna o
  painel alcancavel — exatamente o que a Clarification descreve. Um relay in-container
  0.0.0.0 -> 127.0.0.1 fecha essa lacuna sem tocar o painel.
- `socat` e o utilitario padrao para este relay; a forma canonica
  `socat TCP-LISTEN:<pub>,fork,reuseaddr TCP:127.0.0.1:<painel>` e amplamente usada
  para este proposito. NAO esta no `node` oficial por default -> MUST ser adicionado
  no Dockerfile (base alpine: `apk add --no-cache socat` no estagio de runtime).

**Alternatives considered**:
- **Forwarder em Node** (`net.createServer` ~10 linhas de proxy TCP): evita adicionar
  pacote de SO (o `node` ja esta na imagem) e mantem tudo em uma linguagem. Custo:
  mais codigo proprio para manter/testar. **Documentado como alternativa** caso a
  instalacao de `socat` na base escolhida seja indesejada.
- **`--network host`**: REJEITADA (Clarification da spec) — sem suporte uniforme em
  Docker Desktop (macOS/Windows), quebraria a promessa de "mesma convencao local".
- **`iptables`/DNAT (REDIRECT) no container**: REJEITADA — exigiria `CAP_NET_ADMIN`,
  violando o minimo-privilegio de FR-009/Decision 7.
- **Patch no `cstk-panel` para bind configuravel** (aceitar host via env/flag):
  removeria a necessidade do relay, mas e cross-repo e foi **explicitamente adiado**
  na Clarification — NAO e pre-requisito desta feature.

**`[detalhe de execute-task]`** (NAO afirmar como exato sem validar no ambiente):
- Invocacao EXATA do `socat` (flags `fork`/`reuseaddr`/`TCP4` vs `TCP`) e a confirmacao
  de que o pacote `socat` instala na base escolhida.
- Se optar pelo forwarder Node, o script exato do proxy.
- Como as portas interna-publicada e do-painel se relacionam (ver Decision 4).

---

## Decision 3: Exposicao do knowledge.db — bind READ-ONLY + `CSTK_KNOWLEDGE_DB`

**Decision**: Dar ao container acesso de **somente leitura** ao knowledge.db do host
via **bind mount read-only** e apontar o painel para ele com
`-e CSTK_KNOWLEDGE_DB=<caminho-no-container>`. O painel ja abre o arquivo em modo
read-only estrito (open.ts L100-102 `{ readonly: true }` + L121 `PRAGMA query_only=1`)
— o mount `:ro` e uma segunda barreira, consistente com o desenho read-only do painel
(FR-008/FR-009).

**Granularidade do mount**: montar o **diretorio de dados do cstk** que contem o
`knowledge.db` (`<dir-resolvido>` = `~/.claude/cstk/` por default, ou `dirname` de
`CSTK_KNOWLEDGE_DB` se setado no host) como `:ro`, e setar
`CSTK_KNOWLEDGE_DB=<container-path>/knowledge.db`.

**Rationale**:
- Resolucao de caminho aterrada em config.ts: env `CSTK_KNOWLEDGE_DB` (L49) senao
  `~/.claude/cstk/knowledge.db` (L53). O modo Docker resolve o caminho do host pela
  MESMA regra e monta ESSE arquivo.
- **Por que o diretorio e nao so o arquivo** — risco WAL (empirico): o knowledge.db
  esta em `journal_mode=wal` e ha sidecars `-shm`/`-wal` no diretorio. O painel abre
  `readonly` mas **sem `immutable=1`** (open.ts L15-19 confirma que better-sqlite3 nao
  alcanca `immutable=1`), logo o SQLite **nao ignora** `-wal`/`-shm`. Montar apenas o
  arquivo unico deixaria os sidecars invisiveis ao container. Alem disso, bind-mount
  de um arquivo INEXISTENTE (o `-wal` pode estar 0-byte/ausente) cria um DIRETORIO
  vazio no destino (gotcha conhecido do Docker) — fragil. Montar o diretorio
  read-only e mais robusto e mantem o escopo restrito ao dir de dados do cstk (nao
  ao home inteiro), atendendo FR-009 (read-only + escopo estreito).

**`[RESOLVIDO — FASE 5 task 5.1, dec-060]`** (era `NEEDS CLARIFICATION / risco #1`):
Abrir um WAL db em conexao **readonly sem `immutable=1` sobre um mount read-only** e
um modo de falha conhecido do SQLite: se for necessaria recuperacao de WAL ou escrita
no `-shm`, uma conexao read-only pode falhar (`SQLITE_CANTOPEN`/torn read). O painel
JA le este db em modo nativo no host (onde o FS e read-write), entao pode depender de
o `-shm` existente estar acessivel. Verificado empiricamente (FASE 5, dec-060,
reforcando dec-049/onda-009): opcao 1 (mount read-only do diretorio incluindo
`-shm`/`-wal`) e **suficiente** — container com o hardening COMPLETO de producao
(`--cap-drop ALL --security-opt no-new-privileges --read-only --tmpfs /tmp --init --rm`)
+ knowledge.db REAL de producao (nao fixture) montado `:ro` respondeu
`dbReachable:true quickCheck:true`, zero erro, com paridade EXATA vs `sqlite3` nativo
do host em TODAS as 12 tabelas de `/api/v1/health`. As opcoes 2 (checkpoint no host
antes do mount) e 3 (`immutable=1` no painel, cross-repo) permanecem REJEITADAS/adiadas
— nao foram necessarias.

**Alternatives considered**:
- Montar apenas `knowledge.db` (arquivo unico) `:ro`: escopo minimo mas quebra com o
  WAL sidecar gotcha (acima). Rejeitado como default.
- Copiar o db para dentro da imagem: REJEITADO — quebraria US2 cenario 3 (atualizacao
  ao vivo do indice deve refletir no painel) e assaria dado no artefato de imagem.

**Visibilidade de escrita concorrente (`[RESOLVIDO — FASE 5 task 5.2, dec-061]`, CHK017/US2
Acceptance Scenario 3)**: com o container `running`, uma escrita do HOST (INSERT/DELETE via
`sqlite3` direto na `knowledge.db` de producao) fica visivel na **PROXIMA requisicao** do
painel containerizado, **sem restart**. Mecanismo aterrado no codigo-fonte do painel:
`apps/server/src/db/open.ts::openDb()` e chamado (com `db.close()` em `finally`) A CADA
requisicao HTTP em toda rota (`overview.ts` L54/L191 e as ~11 rotas irmas) — nunca uma
conexao cacheada/long-lived aberta no boot do container. Cada requisicao portanto abre uma
conexao readonly fresca, que observa o estado WAL committed no momento da leitura. Confirmado
empiricamente 2x: (a) manualmente contra a `knowledge.db` REAL de producao, `executions`
54->55 apos INSERT do host (container ja rodando, sem restart), 55->54 apos DELETE de limpeza
(idem); (b) automatizado em `tests/docker/run-panel-docker-smoke.sh::scenario_concurrent_write_visible_without_restart`.
Implicacao para o usuario: **nao ha necessidade de reiniciar o painel Docker** apos uma nova
onda de orquestrador gravar no indice — a premissa original de US2 Acceptance Scenario 3
(visibilidade em tempo real) esta CONFIRMADA, nao refutada.

---

## Decision 4: Mapeamento de porta e alcancabilidade

**Decision**: Publicar a porta **ligada ao loopback do host**:
`docker run -p 127.0.0.1:<porta-host>:<porta-container> ...`. `<porta-host>` = valor
de `--port` (default 5173, mesma validacao 1024-65535 da serve.sh L488-508).
`<porta-container>` = porta onde o **encaminhador** (Decision 2) escuta; o painel
escuta em `127.0.0.1:<porta-painel-interna>` via `PORT` exportado no container.

**Fluxo de alcancabilidade** (aterrado em Decisions 2-3):
`navegador -> http://127.0.0.1:<porta-host>` -> Docker publica em
`127.0.0.1:<porta-host>` -> `0.0.0.0:<porta-container>` (encaminhador) ->
`127.0.0.1:<porta-painel-interna>` (Fastify). Confirma alcancabilidade sem `npm`/rede
de container exposta ao usuario (FR-005).

**Rationale**:
- Publicar em `127.0.0.1:<host>` (e nao `0.0.0.0`) mantem o painel restrito ao
  loopback do host por default — paridade com o default nativo `127.0.0.1`
  (serve.sh L361) e com FR-009/Decision 7 (nao expor em todas as interfaces).
- `--host`: modo nativo so suporta plenamente `127.0.0.1` e avisa para outros valores
  (serve.sh L510-517). Docker mode mantem a mesma semantica: `--host` controla o lado
  host do `-p` (`<host>:<porta-host>`), com o mesmo aviso para nao-loopback.

**`[detalhe de execute-task]`**: escolha concreta de `<porta-container>` e
`<porta-painel-interna>` (ex.: fixar a interna e publicar `--port` na externa). Nao
inventar numeros aqui alem do default 5173 ja aterrado.

---

## Decision 5: Contrato da flag `--docker` e composicao com flags existentes

**Decision**: Adicionar flag opt-in `--docker` ao `cstk serve`. Composicao com as
flags existentes:

| Flag | Semantica no modo Docker |
|------|--------------------------|
| `--docker` | ativa o modo container (opt-in). Ausente = comportamento nativo intacto (FR-002) |
| `--port P` | porta publicada no host (`-p 127.0.0.1:P:...`); mesma validacao 1024-65535 |
| `--host H` | lado host do `-p`; so `127.0.0.1` plenamente suportado, mesmo aviso do nativo |
| `--update` | consulta release mais recente; se houver versao nova, re-baixa+verifica e **reconstroi a imagem**; senao reusa a imagem cacheada (best-effort, falha de rede mantem a imagem existente) |
| `--reinstall` | **remove a imagem cacheada e reconstroi do zero**, incondicional (espelha o `rm -rf` do dir nativo, serve.sh L533-535) |
| `--allow-unverified` / `CSTK_SERVE_ALLOW_UNVERIFIED=1` | mesmo bypass de integridade, aplicado ao **download do painel** (etapa de host, mesmo code path da serve.sh); mismatch continua bloqueio absoluto |

**Pre-flight fail-closed do runtime de container (FR-003/FR-004)**: ANTES de qualquer
rede, checar o runtime na ordem:
1. `command -v docker` falha -> **"docker nao instalado"** (mensagem acionavel, exit 1);
2. runtime presente mas daemon inacessivel (a sonda de daemon — ex.: `docker info` /
   `docker version` no lado server — retorna != 0) -> **"daemon parado/inacessivel"**
   (mensagem acionavel DISTINTA, exit 1).
Docker ausente/inacessivel = **fail-closed**, NUNCA fallback silencioso ao modo nativo
(espelha a filosofia fail-closed da integridade, serve.sh L270-313). Espelha tambem o
prereq nativo `command -v npm`/`curl` (serve.sh L519-527), que ja falha cedo.

**Exit codes** (paridade com serve.sh L434-438): `0` painel subiu / `--help`; `1` erro
geral (docker ausente/daemon down, download/integridade, build da imagem, run falhou);
`2` uso incorreto (porta invalida, flag desconhecida).

**Rationale**: FR-010 pede semantica equivalente a nativa para update/reinstall; a
unica traducao e "reinstalar dir" -> "reconstruir imagem". FR-014 exige descoberta via
`--help` (ver Decision abaixo). FR-003 exige checar runtime ANTES de rede.

**`[detalhe de execute-task]`**: comando EXATO da sonda de daemon (`docker info`
vs `docker version --format ...`) e seu parsing de exit — descrever o contrato aqui;
fixar o comando na implementacao/teste. SC-006 (<5s, sem rede antes da checagem) e
requisito de aceitacao dessa sonda.

**FR-014 (ajuda)**: o bloco `--help` de `serve_main` (serve.sh L395-456) MUST ganhar
a documentacao de `--docker` e da semantica docker de `--update`/`--reinstall`.

---

## Decision 6: Ciclo de vida e idempotencia (FR-011, FR-012-INFRA-IDEMP)

**Decision**:
- **Nome/label deterministicos**: container com nome fixo (ex.: `cstk-panel`) e/ou
  label de gestao (ex.: `--label cstk.managed=serve`). Chave de idempotencia = uma
  instancia do modo Docker por host (spec FR-012-INFRA-IDEMP), sem TTL.
- **Reconciliacao a cada invocacao**: antes de subir, remover um container remanescente
  de mesmo nome (parado ou rodando) — `docker rm -f <nome>` tolerando "no such
  container" — e entao subir novo. Rodar com **auto-remocao no fim** (`--rm`) para o
  happy-path nao deixar vestigio; o `rm -f` pre-run cobre restos de queda/`kill -9`.
- **Encerramento gracioso (FR-011)**: reusar o mecanismo de trap da serve.sh. No
  Ctrl+C/SIGTERM do host, o handler emite `docker stop` (SIGTERM ao PID 1 do container,
  com grace) espelhando `_serve_shutdown` (serve.sh L103-123). Usar `docker run --init`
  (tini como PID 1) para propagar sinais aos 2 processos (painel + encaminhador) e
  reapear zumbis. Grace de `docker stop` alinhado ao nativo (5s) via `-t`.

**Rationale**: FR-012-INFRA-IDEMP pede reconciliacao automatica (nunca erro cru do
runtime); nome deterministico + `rm -f` idempotente entrega isso. `--init` e o
mecanismo padrao para sinal/reaping com mais de um processo no container, necessario
porque o container roda painel + encaminhador (Decision 2). O grace de 5s espelha o
contrato ja existente da serve.sh (L111-117).

**`[detalhe de execute-task]`**: valor exato do `-t` do `docker stop`; se o entrypoint
sera um script sh POSIX (Principio II) que inicia painel em background + encaminhador
em foreground com trap, ou se `--init` sozinho basta. Descrever contrato; fixar script
na implementacao.

---

## Decision 7: Superficie de seguranca (alimenta o gate owasp)

**Decision** (todas aterradas em FR-007/008/009/013 + Constituicao IV):
- **knowledge.db read-only** (`:ro`, Decision 3) — nenhum caminho de escrita ao dado do
  host.
- **Container nao-root** (owasp MEDIUM): a imagem MUST rodar como usuario nao-privilegiado
  (`USER node` — as imagens oficiais `node` trazem o usuario `node` pronto). O painel e
  read-only e nao precisa de root; root + socket + mount `:ro` e privilegio desnecessario.
- **`no-new-privileges` + drop de caps por default** (owasp MEDIUM): `--security-opt
  no-new-privileges`, `--cap-drop ALL` (o relay so precisa bind em porta nao-privilegiada
  >=1024, sem cap especial) e `--read-only` no rootfs com `tmpfs` para escrita efemera —
  adotados como **default**, nao apenas "avaliar". `[detalhe de execute-task]` validar
  empiricamente que o runtime do painel funciona sob esse conjunto.
- **Sem `CAP_NET_ADMIN`** — elimina forwarder via iptables (reforca Decision 2).
- **Porta no loopback do host por default** (`-p 127.0.0.1:...`, Decision 4). `--host`
  nao-loopback (ex.: `0.0.0.0`) expoe o painel na rede — mesmo caveat do modo nativo
  (serve.sh L510-517, so avisa); documentar e manter default loopback (owasp LOW).
- **Supply chain reproducivel** (owasp MEDIUM, A03/A08/CICD-SEC-9): a base `node` MUST ser
  fixada por **digest** (`node:22-alpine@sha256:16e22a550f3863206a3f701448c45f7912c6896a62de43add43bb9c86130c3e2`,
  ambos os estagios), nao tag flutuante; e o install do painel na imagem MUST usar
  `npm ci` (lockfile `package-lock.json`, ~201KB na v0.12.1), para build
  reproduzivel/travado.
- **Integridade + trusted-hosts preservados**: o download do painel continua no code
  path de host com `trusted_host_check` (trusted-hosts.sh L52-88) + integridade
  fail-closed (serve.sh L270-313) + linha `serve-integrity` no enforcement-log. O
  `docker build` NAO baixa release por fora desse caminho. NOTA (owasp LOW, herdado): o
  `cstk-panel` frequentemente NAO publica `.sha256` (serve.sh L18-22), entao o caminho
  comum e `unverifiable-blocked` a menos que `--allow-unverified` — mesmo trade-off
  auditado do modo nativo, nao um novo risco.
- **FR-013 — nunca push**: a imagem e `docker build` LOCAL com tag local; nenhum
  `docker push`/registry remoto. Consistente com Principio IV (zero coleta remota) e o
  confinamento de raio de acao do toolkit. Defesa em profundidade (owasp LOW): adicionar
  teste que assegura que o helper docker NUNCA emite `docker push`.
- **knowledge.db NAO baked na imagem**: montado em runtime, nunca `COPY` para dentro da
  imagem (evita vazar dado local em artefato de imagem).
- **Escopo do mount vs FR-009** (owasp MEDIUM): montar o diretorio `~/.claude/cstk/` `:ro`
  (necessario pelo WAL, Decision 3) expoe tambem os `knowledge.db.bak-*` sibling
  (read-only, mesma classe de dado do usuario). Tensao com "escopo estreito" de FR-009 —
  se a leitura WAL permitir, preferir montar um conjunto minimo (db + `-wal` + `-shm`) ou
  um dir dedicado; senao aceitar o dir `:ro` documentando a exposicao read-only.

**Rationale**: o gate `owasp-security` avalia a superficie (mount, forwarder, porta
exposta, build). Estas escolhas minimizam privilegio e preservam as garantias ja
existentes do modo nativo. Nenhum finding critical/high (ferramenta local em loopback);
os MEDIUM viraram defaults de hardening acima, os LOW ficaram documentados.

**`[detalhe de execute-task]`**: conjunto exato de flags de hardening (`--cap-drop ALL`,
`--security-opt no-new-privileges`, `--read-only`, `tmpfs`, `USER node`) a validar
empiricamente para nao quebrar o runtime do painel; pin de digest da base; `npm ci`.

---

## Unknowns remanescentes (resumo)

| # | Item | Estado | Onde resolver |
|---|------|--------|---------------|
| 1 | Leitura de WAL db read-only sem `immutable=1` sobre mount `:ro` (FR-008/US2) | **RESOLVIDO (dec-060, task 5.1, onda-011)** — FECHAMENTO FORMAL: re-run limpo confirmou `dbReachable:true quickCheck:true` + paridade EXATA em TODAS as 12 tabelas vs `sqlite3` nativo (amplia dec-049/onda-009, que comparara so 3); `wal_readonly_verified=true` gravado em data-model.md; regressao automatizada em `tests/docker/run-panel-docker-smoke.sh` | FECHADO (FASE 5, 5.1) |
| 2 | Invocacao exata do `socat` (ou proxy Node) + presenca do pacote na base | detalhe de implementacao | execute-task (Decision 2) |
| 3 | Tag/digest exatos da base node + compilacao musl do `better-sqlite3` | **RESOLVIDO (dec-037)** — `node:22-alpine` multi-stage (digest em Decision 1), compilado do fonte no estagio de build | execute-task (Decision 1) |
| 4 | Comando exato da sonda de daemon (`docker info`/`version`) + SC-006 <5s | **RESOLVIDO (dec-042)** — `docker info` | execute-task (Decision 5) |
| 5 | Flags exatas de hardening (`--cap-drop`/`--read-only`/`tmpfs`) | **RESOLVIDO (dec-046 fixou as flags; dec-049 validou empiricamente sem necessidade de ajuste, task 3.1)** | execute-task (Decision 7) |
| 6 | Visibilidade de escrita concorrente sem restart (CHK017/US2 Acceptance Scenario 3) | **RESOLVIDO (dec-061, task 5.2, onda-011)** — CONFIRMADA (nao refutada): `openDb()` roda por-requisicao (open.ts), nunca cacheia conexao; INSERT/DELETE do host 54<->55 refletido na PROXIMA requisicao do painel containerizado, sem restart (producao real + `tests/docker/run-panel-docker-smoke.sh::scenario_concurrent_write_visible_without_restart`) | FECHADO (FASE 5, 5.2) |
| 7 | Indice ausente no modo Docker nao falha a inicializacao (US2 Acceptance Scenario 2) | **RESOLVIDO (dec-062, task 5.3, onda-011)** — painel inicia normalmente, `GET /api/v1/health` retorna `dbReachable:false reason:"db-missing"` (mesma degradacao de 1a classe do modo nativo); teste dedicado em `tests/docker/run-panel-docker-smoke.sh::scenario_missing_index_graceful` | FECHADO (FASE 5, 5.3) |

Nenhum item acima e um dado factual inventado: todos sao decisoes de implementacao a
FIXAR e TESTAR na fase execute-task, ou (item 1) um risco real explicitamente
sinalizado para verificacao empirica — nunca presumido resolvido.
