# Contracts: state-mcp-server — Ciclo de vida da sessao (CLI + registro + container)

Contrato da superficie **nao-MCP**: o subcomando `cstk mcp`, a entrada no
`.mcp.json` e o container. Cobre FR-010, FR-011, FR-012, FR-015, FR-016.

> **Status: `[PROPOSTA — a validar na implementacao]`** para tudo que descreve
> comportamento novo. Marcacoes **[VERIFICADO]** apontam o precedente real do
> repo que esta sendo espelhado.

---

## CLI: `cstk mcp`

Novo grupo de subcomandos em `cli/lib/mcp.sh` (⇒ teste obrigatorio em
`tests/cstk/test_mcp.sh` [VERIFICADO: mapeamento em `tests/run.sh:152-162`]).

### `cstk mcp install [--project-path PATH] [--dry-run]`

Registra a entrada **estatica e unica** no `.mcp.json` do projeto-alvo. Roda
**uma vez por projeto**, nao por execucao (research.md Decision 2).

| Exit | Significado |
|------|-------------|
| 0 | Entrada criada ou ja presente e equivalente (idempotente) |
| 1 | Erro de IO/merge |
| 2 | Uso incorreto |
| 3 | Recusa: `--project-path` aponta para `$HOME` (mesma recusa do provisionamento de hooks) [VERIFICADO: `cli/lib/hooks.sh:338-341`] |

**Merge**: preservar conteudo existente do `.mcp.json`, no espirito do
`merge_settings` de hooks — `jq -s '.[0] * .[1]'`, **target vence em conflito**
[VERIFICADO: `hooks.sh:117`]. Sem `jq`, emitir bloco para colagem manual (mesmo
fallback ja praticado), preservando o carve-out de dep opcional.

**Forma da entrada** [PROPOSAL; chaves conforme doc oficial do `.mcp.json` —
VERIFICADO que sao `type`/`command`/`args`/`env`]:

```json
{
  "mcpServers": {
    "cstk-state": {
      "type": "stdio",
      "command": "<catalogo>/skills/agente-00c-runtime/scripts/mcp-launch.sh",
      "args": []
    }
  }
}
```

Deliberadamente **sem `env` com valores interpolados**: a sintaxe exata de
expansao de variaveis em `.mcp.json` e [NAO-VERIFICADO] (spike S5). O launcher
descobre tudo do disco — nao depende de env injetada pelo harness.

### `cstk mcp status [--state-dir DIR] [--project-path PATH]`

**Satisfaz FR-015**: responde sem que o operador inspecione Docker.

Saida (stdout, uma chave por linha — mesmo estilo de `state-backend.sh resolve`
[VERIFICADO: emite `effective_backend=` / `reason=`]):

```
status=active|stopped|unavailable
reason=<motivo>            # presente quando != active
container=<nome>|-
session_id=<id>|-
mode=docker|bash-fallback
```

| Exit | Significado |
|------|-------------|
| 0 | Consulta bem-sucedida (inclusive `status=unavailable` — **nao e erro**) |
| 1 | Erro inesperado |
| 2 | Uso incorreto |

Motivos canonicos de `unavailable`: `docker-absent`, `daemon-unreachable`,
`image-build-failed`, `health-timeout`, `no-active-execution`.

### `cstk mcp start --state-dir DIR` / `cstk mcp stop --state-dir DIR`

**[VERIFICADO — task 5.3.1, validado com Docker real de ponta a ponta:
build da imagem, `docker run`, health check MCP real via
`get_status`, `cstk mcp stop`, ciclo `active` → `stopped` idempotente]**

Invocados **pelo command pai**, nao pelo operador no caminho normal.

- `start`: preflight de Docker → build/reuso da imagem → reconcilia
  container remanescente → **grava `<state-dir>/mcp-server.json` (`session_id`
  CSPRNG, `mode=docker`) ANTES do `docker run`** → `docker run` → health check
  → confirma sucesso. **Exit 3 = indisponivel** ⇒ grava `mode=bash-fallback` +
  `unavailable_reason` e retorna sem abortar a execucao (FR-007/FR-012), sem
  erro para o operador. Motivos: `docker-absent`, `daemon-unreachable`,
  `image-build-failed`, `container-start-failed`, `health-timeout`. Falha do
  health check derruba o container recem-subido (`docker stop`) antes de
  reportar `bash-fallback` — nunca deixa um container saudavel-de-mentirinha
  para tras.
  - **Achado empirico (task 5.3.1)**: o processo PID1 do servidor
    (`mcp/state-server/src/index.ts::bootstrap`) resolve a propria sessao
    **uma vez no startup** e recusa subir se `resolveActiveSession` falhar
    (fail-closed). Isso EXIGE que o descritor exista no disco, com o
    `session_id` ja batendo o token, **antes** do `docker run` — gravar
    depois (como uma implementacao ingênua faria) produz
    `SESSION_MISMATCH` garantido no boot do container. A ordem
    grava-depois-builda-depois-run acima e, portanto, MANDATORIA, nao
    estilistica.
- `stop`: `docker stop -t 5` [VERIFICADO: `_SD_STOP_GRACE_SECONDS="5"` em
  `serve-docker.sh`] + preenche `stopped_at`. **Idempotente**: parar o que ja
  esta parado, ou `--state-dir` sem descritor algum, e exit 0. So invoca
  `docker stop` quando `mode=docker` E `stopped_at` ainda nulo.

### `cstk mcp status --live` (task 5.3.3, FR-010)

Extensao de `cstk mcp status` (mesmas flags `--state-dir`/`--project-path`,
mesma saida de 5 linhas). Quando `mode=docker` e a sessao nao esta `stopped`,
roda um health check **de verdade** (mesmo handshake MCP real de `start` —
`_mcp_docker_healthcheck`) em vez de so ecoar o descritor gravado em disco.
Falha ⇒ reporta `status=unavailable`/`reason=health-timeout` — **nunca
reinicia o container** (FR-010: "reverifica saude SEM reiniciar") e **nunca
muta o descritor em disco** (observacional, sem efeito colateral). Usado pelo
command pai em cada `-resume` para confirmar que a sessao sobreviveu a pausa
entre ondas antes de injetar `session_id`/tools no proximo spawn do
orquestrador. Sem `--live` (default), o comportamento e identico ao de antes
desta task — leitura pura, zero custo de Docker.

---

## Health check (FR-011)

| Aspecto | Contrato |
|---------|----------|
| Metodo | Handshake MCP `initialize` pelo stdio do container + uma chamada de tool read-only trivial |
| Timeout | 30s [PROPOSAL — a calibrar no spike]; estourar ⇒ `unavailable:health-timeout` |
| Quando | (a) apos `start`, **antes** da primeira mutacao; (b) a cada `-resume` (FR-010: verificar saude, **nao** reiniciar) |
| Falha | Nunca aborta a execucao: rebaixa para `bash-fallback` (FR-007) |

---

## Contrato do container [PROPOSAL, espelhando precedente VERIFICADO]

Espelha `cli/lib/serve-docker.sh:712-724`, com **uma diferenca deliberada**:
nenhuma porta publicada.

| Aspecto | Valor | Origem |
|---------|-------|--------|
| Base | `node:22-alpine` **pinada por digest** | [VERIFICADO: `_SD_BASE_IMAGE`] |
| Extras | `jq`, `sqlite` (>= 3.45.1) via `apk`, versao pinada | Exigidos pelos helpers (Decision 1); piso [VERIFICADO: `state-backend.sh:69`] |
| Dockerfile | **gerado em runtime** em dir `mktemp`, nao versionado | [VERIFICADO: `_serve_docker_write_dockerfile`] |
| Lock de deps | `package-lock.json` **obrigatorio**; ausencia ⇒ build falha fechado | [VERIFICADO: `serve-docker.sh:356`] |
| Nome | `cstk-mcp-state-<session_id>` | [PROPOSAL] — **um por execucao** (FR-016) |
| Label | `cstk.managed=mcp-state` | [PROPOSAL], espelha `cstk.managed=serve` |
| Flags | `--init --rm --cap-drop ALL --security-opt no-new-privileges --read-only --tmpfs /tmp:rw,noexec,nosuid` | [VERIFICADO no precedente] |
| Rede | **nenhuma porta publicada** (`-i` para stdio) | Diferenca vs `serve-docker` (que publica) |
| Proibido | `--network host`, `--privileged`, qualquer push | [VERIFICADO: proibicao ja asseverada estaticamente em `tests/cstk/test_serve-docker.sh`] — **replicar a assercao estatica** para este container |

### Montagens (a lista **e** o perimetro de blast radius — FR-008)

| Origem | Destino | Modo |
|--------|---------|------|
| `<state-dir>` da execucao resolvida | `/data/state` | **rw** |
| `<catalogo>/skills/agente-00c-runtime/scripts` | `/opt/cstk/scripts` | **ro** |
| `<projeto-alvo>/.claude/enforcement-log.jsonl` (**o arquivo**, nao o diretorio) | `/data/enforcement-log.jsonl` | **rw** |
| `knowledge.db` (qualquer path) | — | **NAO MONTADO** (FR-013) |

Nenhuma outra montagem e permitida. Um segundo `<state-dir>` montado seria
violacao direta de FR-008 e deve ser asseverado estaticamente no teste.

> **SEC-H2 (finding HIGH do gate `owasp-security`) — por que o mount e do ARQUIVO,
> nunca do diretorio `.claude`**: montar `<projeto-alvo>/.claude` inteiro em modo
> rw daria ao container permissao de escrita sobre `.claude/hooks/pretooluse-bash-guard.sh`
> e `.claude/settings.json` — isto e, sobre a **guarda que protege a sessao do
> operador no host**. Um comprometimento do servidor (ex.: via injecao na fronteira
> Node→POSIX, SEC-H1) escalaria de "mutar estado da propria execucao" para
> "executar codigo arbitrario no host no proximo comando Bash do operador"
> (ASI03 Privilege Abuse + ASI05). O bind-mount de **arquivo unico** elimina a
> escalada mantendo a capacidade exigida por FR-005. O arquivo MUST existir (criar
> vazio com `chmod 600` antes do `docker run`) — bind-mount de arquivo inexistente
> faz o Docker criar um **diretorio** no host.
>
> Teste estatico obrigatorio em `tests/cstk/test_mcp-docker.sh`: nenhuma linha de
> `docker run` pode montar `.claude` como diretorio, `$HOME`, `/`, o socket
> `/var/run/docker.sock` ou o diretorio do `knowledge.db`.

---

## Ciclo de vida ponta a ponta

```
/feature-00c (ou /agente-00c)
  └─ cstk mcp status ──unavailable──> mode=bash-fallback ──> pipeline atual (zero regressao)
       │ active
       ├─ cstk mcp start  ─> container dedicado + mcp-server.json
       ├─ spawn do orquestrador ──> tools MCP durante N ondas
       │     ⋮  (Schedule intent: servidor PERMANECE ativo — FR-010)
       ├─ /…-resume ──> cstk mcp status (health, sem restart)
       └─ estado terminal (concluida|abortada) ──> cstk mcp stop
```

**Encerramento e abort concorrente** (Edge Case da spec): `stop` usa `docker stop
-t 5`, dando ao processo janela de grace para concluir a chamada em voo. Uma
mutacao interrompida **dentro** de `close_wave` cai na compensacao por pre-imagem
(research.md Decision 3) — nunca em fechamento parcial. Se o container morrer sem
grace (SIGKILL), a rede de seguranca externa (`reconcile-wave` do command pai,
[VERIFICADO: subcomando existente de `state-ondas.sh`]) continua aplicavel na
retomada, exatamente como hoje (US4 cenario 2).

---

## Resolucao da execucao ativa (helper `mcp-session.sh`)

Novo script POSIX em `global/skills/agente-00c-runtime/scripts/mcp-session.sh`
(⇒ teste obrigatorio em `tests/test_mcp-session.sh`).

> **Modo direto `--state-dir` (dec-081, task 5.3)**: `resolve` aceita
> `--state-dir DIR` como alternativa MUTUAMENTE EXCLUSIVA a
> `--project-path PATH` — valida `DIR/mcp-server.json` diretamente, sem
> tree-walk. Existe porque, DENTRO do container (§Montagens abaixo), so o
> state-dir da propria execucao esta montado (`/data/state`, flat); o
> `CSTK_MCP_PROJECT_PATH` (path do HOST) nao existe como diretorio ali, e o
> modo `--project-path` sempre falharia. O container e 1:1 com uma unica
> execucao (data-model.md), entao nao ha ambiguidade a resolver — a MESMA
> autorizacao por token de capacidade se aplica identica (fail-closed).
> `env CSTK_MCP_STATE_DIR=/data/state` (gravado por `_mcp_docker_run`, dec-081)
> sinaliza a `session/resolve.ts` para usar este modo; fora do container, a
> env fica ausente e o comportamento `--project-path` e inalterado.
>
> **[VERIFICADO — task 5.3.1, achado empirico com Docker real]**: no modo
> direto, o `state_dir=` retornado no output e o valor de `--state-dir`
> **usado para localizar o descritor** (i.e., `/data/state` visto de DENTRO
> do container), **nunca** o campo `.state_dir` do proprio JSON — esse
> campo e sempre o path ABSOLUTO DO HOST (`cli/lib/mcp.sh::
> _mcp_write_descriptor`, data-model.md). Sem essa distincao, TODA tool MCP
> subsequente (que usa `session.stateDir` para chamar `state-rw.sh`/
> `state-ondas.sh`/`bloqueios.sh` — `mcp/state-server/src/session/
> resolve.ts`) recebia um path que nao existe no filesystem do container e
> falhava (`state-ondas.sh wave-status: state.json ausente em
> <path-do-host>`; sonda: `docker logs` de um `cstk mcp start`
> bem-sucedido, capturado ao validar o health check ponta a ponta). No
> modo `--project-path` (tree-walk, sempre executado no HOST), nenhum
> override e aplicado — `.state_dir` do descritor permanece a fonte,
> comportamento inalterado.

### SEC-H3 (finding HIGH do gate) — roteamento e por CAPACIDADE, nao por precedencia

O desenho inicial roteava a chamada para a "execucao ativa" resolvida por
precedencia (a mesma regra do hook `PreToolUse`). **Isso e um confused deputy**
(ASI03): com uma `agente-00c` e uma `feature-00c` ativas ao mesmo tempo — cenario
explicitamente previsto por FR-016 e por US2 cenario 3 — a precedencia elegeria
sempre a `agente-00c`, e o orquestrador da `feature-00c` teria suas mutacoes
**aplicadas no state-dir da outra execucao**. Violacao direta de FR-008.

Causa raiz: precedencia e uma regra **ambiente** (decide por si), adequada a uma
guarda que apenas **bloqueia**, e inadequada a um roteador que **muta**.

**Contrato corrigido — `session_id` e um token de capacidade (bearer)**:

| Aspecto | Regra |
|---------|-------|
| Geracao | `cstk mcp start` gera token aleatorio de **>= 128 bits** de fonte CSPRNG (`/dev/urandom`), por execucao |
| Guarda | Gravado em `<state-dir>/mcp-server.json` com **`chmod 600`**; o state-dir ja e `chmod 600` no backend sqlite [VERIFICADO: `_state_db_secure_perms`] |
| Entrega | O **command pai** injeta o token no prompt de spawn do orquestrador (mesmo caminho por onde ja injeta `state_dir`, `short_name` e modelo da onda) |
| Roteamento | O launcher resolve o alvo **pelo token apresentado**, procurando o descritor que o contem entre as execucoes ativas — **nunca** por precedencia |
| Rejeicao | Token ausente, desconhecido ou de execucao ja terminal ⇒ `SESSION_MISMATCH`, **sem** fallback para "a execucao ativa mais provavel" (fail-closed) |
| Rotacao | Novo token a cada `cstk mcp start`; `stop` o invalida |

Posse do token **e** a autorizacao. Isso substitui, no escopo local/stdio, o papel
que OAuth 2.1 + RFC 8707 (resource indicators) cumpririam num servidor MCP remoto
— ver §Nota de autenticacao abaixo.

**Onde a precedencia do hook continua valendo**: apenas em `cstk mcp status`
**sem** `--state-dir` (consulta humana de conveniencia, read-only). Nenhuma
mutacao usa precedencia. A regra do hook segue sendo a unica para o hook — nao
ha duplicacao de logica, ha **separacao de papeis**: o guard bloqueia por
ambiente; o MCP muta por capacidade.

### Nota de autenticacao (MCP Authorization Spec — justificativa de N/A)

O checklist MCP exige OAuth 2.1 + PKCE + RFC 8707 + DPoP. Esses controles
enderecam servidores **remotos/HTTP** com credenciais ambientes e multiplos
chamadores. Aqui: transporte `stdio`, **nenhum listener de rede**, nenhuma
credencial ambiente, um container por execucao. A fronteira de autenticacao e o
**processo + permissao de filesystem**, reforcada pelo token de capacidade acima.
N/A **justificado e registrado** — nao omitido. Se o plano B (Streamable HTTP)
for acionado, este N/A **caduca** e o checklist completo volta a ser exigivel.
