---
name: agente-00c-runtime
description: 'Internal POSIX runtime helpers for agente-00c/feature-00c orchestrators (state, lock, validation, hashes, secrets filter). NOT user-invocable.'
allowed-tools:
  - Bash
  - Read
---

# Agente-00C Runtime

Scripts POSIX que implementam as primitivas de estado da pipeline 00C.
Consumidos via tool Bash pelos agentes em `~/.claude/agents/agente-00c-*.md`.

## Layout

```
~/.claude/skills/agente-00c-runtime/
└── scripts/
    ├── state-rw.sh        # init/read/write/get/set/sha256/path-validate
    ├── state-validate.sh  # FR-008: schema + invariantes (read-only)
    └── state-lock.sh      # acquire/release/check (mkdir atomico)
```

## Convencao de path do estado

```
<projeto-alvo>/.claude/agente-00c-state/
├── state.json
├── state.json.sha256
├── .lock/                 # diretorio criado por mkdir atomico
└── state-history/
    └── onda-NNN-<iso8601>.json
```

Todos os scripts aceitam `--state-dir <path>` apontando para o diretorio
acima — nao para o `state.json` diretamente.

## Dependencia: jq

Os helpers de leitura/escrita de state.json **exigem** `jq` no PATH. Sem
jq, os scripts falham com mensagem clara orientando instalacao
(`brew install jq` no macOS / `apt install jq` em Debian/Ubuntu). Esta e
uma excecao escopada ao Principio II do toolkit (POSIX sh puro), alinhada
com o carve-out 1.1.0 da constitution para JSON estruturado.

## NAO e skill user-invocavel

Esta skill NAO tem trigger automatico — `description` indica claramente
que e infraestrutura interna. Nao deve aparecer como sugestao para o
operador. A presenca em `~/.claude/skills/` e necessaria apenas porque o
mecanismo de `cstk install` so distribui artefatos sob `plugins/cstk/skills/`,
`plugins/cstk/commands/` ou `plugins/cstk/agents/`.

## Estado atual

**FASE 2 do backlog em `docs/specs/_archived/agente-00c/tasks.md`.** Implementacao
operacional dos 3 scripts entregue como esqueleto + cobertura de testes
em `tests/test_state-*.sh`.

## Reuso pelo feature-00c (FASE 1 de `docs/specs/_archived/feature-00c/tasks.md`)

Este runtime e compartilhado entre `/agente-00c` (orquestracao de
projeto inteiro) e `/feature-00c` (orquestracao de feature individual).
Auditoria empirica em `scripts/_audit-paths.md` confirma que 18/21
scripts ja aceitam `--state-dir DIR` desde a v1.0 — nenhum refactor
mecanico necessario. Os 3 scripts restantes (issue.sh, report.sh,
secrets-filter.sh) tem decisoes de design documentadas no audit.

### Helper sourceable `_state-dir.sh`

`scripts/_state-dir.sh` fornece resolucao consistente do diretorio de
estado entre callers. Contrato:

```sh
. "$(dirname -- "$0")/_state-dir.sh"

# resolve precedencia: arg explicito > env var > erro
STATE_DIR=$(_sd_resolve "$EXPLICIT_DIR") || exit 1

# valida que e diretorio gravavel
_sd_require_dir "$STATE_DIR" || exit 1

# resolve nome canonico do report/suggestions por flavor
REPORT_NAME=$(_sd_flavor_to_report_name "$FLAVOR") || exit 1
```

Variavel de ambiente reconhecida: **`AGENTE_00C_STATE_DIR`**. Sem
`--state-dir` e sem env var = erro claro em stderr (nao fallback
silencioso — Principio I, auditabilidade).

### Decisao SHARED para `secrets-filter-ignore`

Ambos orquestradores leem do mesmo arquivo
`<projeto-alvo>/.claude/agente-00c-state/secrets-filter-ignore`. Razao:
e config do projeto-alvo, nao do orquestrador — quem define o que e
"sensivel localmente" no projeto e o operador, e ambos orquestradores
operam ao mesmo nivel de confianca. Detalhe em
`scripts/_audit-paths.md` §"Detalhamento das 3 ocorrencias HARDCODED".

## Gotchas

### `--state-dir` e o contrato canonico — env var e atalho, nao default silencioso

Todos os scripts do runtime que tocam estado aceitam `--state-dir DIR`
como argumento. A variavel `AGENTE_00C_STATE_DIR` (introduzida pelo
helper `_state-dir.sh`) e apenas conveniencia quando o caller esta
embutido num contexto que ja conhece o path. Sem nenhum dos dois =
erro explicito; nunca fallback para path historico hardcoded.

### Flavor afeta apenas rendering de paths em templates (report/issue)

`--flavor=agente-00c|feature-00c` (default `agente-00c`) e usado pelos
helpers `_sd_flavor_to_report_name` e `_sd_flavor_to_suggestions_name`
para renderizar nomes de arquivo nos corpos de relatorio/issue. NAO
afeta operacoes de I/O sobre state.json (essas usam state-dir
diretamente).

### Backward-compat de `/agente-00c`: zero mudancas em comportamento default

Todas as adicoes da feature-00c (helper `_state-dir.sh`, contrato
SHARED de secrets-filter-ignore, conceito de flavor) sao
**retrocompativeis**. Invocacoes existentes de `/agente-00c` continuam
funcionando bit-a-bit identicas — verificavel pela suite completa em
`tests/run.sh` (todos os `test_*` passam sem alteracao).

### Helper `_log.sh` exige `AGENTE_00C_RUNTIME_SCRIPTS_DIR` quando sourceado de contexto sem `$0` valido

`scripts/_log.sh` resolve o path do `secrets-filter.sh` para aplicar
filtro antes da emissao (FR-036). Quando sourceado de um script normal,
auto-detecta via `$(dirname "$0")`. Quando sourceado via `sh -c "..."`
(tests, eval, etc), `$0` aponta para `sh` e a deteccao falha. **Callers
devem setar `AGENTE_00C_RUNTIME_SCRIPTS_DIR=/path/to/scripts/dir` antes
de sourcing** nesses casos. Sem isso, `_log.sh` cai no fallback
`[NO-FILTER] <msg>` — degradado mas nao silencioso.

### Subcomando `secrets-filter.sh for-backup` para backups com hash auto-registrado

Le state.json em stdin, aplica filtros + emite envelope JSON
`{wave_number, captured_at, state_sha256_self, state_snapshot}` em
stdout. Hash calculado sobre o conteudo FILTRADO (nao o state operacional).
Permite verificacao retroativa de corrupcao via
`sha256sum < (jq '.state_snapshot' backup.json) == .state_sha256_self`.
Uso: `cat state.json | secrets-filter.sh for-backup --wave-number 7 > backups/wave-007.json`.

### Script `feature-00c-preflight.sh` valida hashes antes da fase plan (FR-010A)

Pre-flight invocavel via `feature-00c-preflight.sh check --state-dir DIR`.
Verifica: (a) briefing.sha256 em disco vs state.json, (b) constitution.sha256
e version (MAJOR drift = error/exit 1; MINOR/PATCH = warn/exit 0),
(c) chama `pipeline.sh constitution-conflict` para forward-compat.
Output JSON estruturado `{ok: bool, findings: [...]}`. Reuso direto do
runtime do agente-00c (Principio I, sem implementacao paralela).

### Scripts `mcp-session.sh` e `mcp-launch.sh` (feature `state-mcp-server`)

`mcp-session.sh resolve` implementa a resolucao da execucao ativa por TOKEN
DE CAPACIDADE (SEC-H3): dado um token (`--token`/`--token-file`/env
`MCP_SESSION_TOKEN`), varre os descritores `mcp-server.json` de
`.claude/agente-00c-state/` + `.claude/feature-00c-state/*/` (modo
`--project-path`, tree-walk) ou le direto um unico state-dir (modo
`--state-dir`, usado DENTRO do container — dec-081). Roteamento de MUTACAO
e sempre por posse do token, nunca por precedencia de ambiente — divergencia,
ausencia ou colisao de token e sempre `SESSION_MISMATCH` (exit 3,
fail-closed), sem fallback para "a execucao ativa mais provavel". Consumido
pelo servidor MCP de estado (`plugins/cstk/mcp/state-server/src/session/resolve.ts`) e
pelo `mcp-launch.sh` (abaixo).

`mcp-launch.sh` e o comando registrado em `.mcp.json` (via `cstk mcp
install`) que o Claude Code invoca ao conectar ao servidor MCP `cstk-state`.
Desde o cutover `mcp-direct-transport` (v8.0.0) ele faz `exec node
dist/src/index.js` direto (build lazy via `mcp-build-lazy.sh`; a sessao e
resolvida por chamada pelo token). Quando o processo real NAO pode subir
(Node < 22/ausente, build lazy falhou), serve um stub IDLE com 0 tools —
no `/mcp` aparece `connected · no tools`. `mcp-launch.sh preflight`
(bugfix 8.3.1) reproduz as mesmas checagens sem servir nem buildar e
imprime `ready|<entrypoint>` (exit 0) ou `idle|<motivo>` (exit 3); os
commands `/agente-00c` e `/feature-00c` o usam para decidir o ramo de
opt-ins e explicar o IDLE ao operador — a prova final de que a tool existe
segue sendo o toolset do proprio command pai.

Ambos POSIX puros + `jq`, seguem a mesma convencao `--state-dir` do resto
do runtime. Detalhes completos: `docs/specs/state-mcp-server/`
(`contracts/mcp-session-lifecycle.md`, `contracts/mcp-tools.md`).

### Paridade dos leitores com o backend SQLite (feature `state-db-runtime-parity`)

Todos os leitores do runtime funcionam contra os DOIS backends de estado
(`state.json` e `state.db`) via a interface canonica de materializacao —
nenhum leitor constroi o path `state.json` na mao:

- **`_state-read.sh`** (sibling sourceable): `state_read_materialize DIR`
  devolve o proprio `state.json` no backend JSON (zero mudanca, FR-004) ou
  materializa o documento via `state-rw.sh read` num `mktemp` 0600 FORA do
  state-dir no backend SQLite (anti-mirror FR-003). Falha de leitura de um
  `state.db` presente (corrompido, `sqlite3` ausente) PROPAGA exit+stderr
  do read — nunca degrada mudo (FR-012). Cleanup por trap
  `state_read_cleanup EXIT INT TERM`.
- **`state-rw.sh set` multi-campo**: aceita N pares `--field/--value` num
  UNICO envelope transacional — necessario para promocao terminal sob
  SQLite, cujo schema tem CHECK constraint C2 (status terminal exige
  `finished_at`); set de campo unico para status terminal e REJEITADO com
  diagnostico e estado intacto (sem escrita parcial). Mesmo `--field`
  repetido no lote = last-wins (FR-005).
- **`state-lock.sh acquire --force`**: readquire lock orfao (dono morto)
  com diagnostico auditavel `DIAG|warning|lock-force-acquired|...`;
  pre-condicao CONTRATUAL (SIGTERM + grace 60s) e do caller. Sem
  `--force`, lock ocupado segue exit 3. `check-execution-busy` le o estado
  pelos DOIS backends (FR-010).
- **`report.sh generate|emit` exit 7**: estado ausente (nem `state.json`
  nem `state.db` legivel) retorna exit 7 contratual (FR-008, alinha o
  contrato de invocacao do feature-00c); exit 2 (uso) e exit 1 (falha
  generica) inalterados.
- **Varredura anti-regressao**: `tests/test_state-parity-sweep.sh` roda o
  manifest dos 15 leitores contra state-dir SQLite populado + grep
  estatico de acesso direto com allowlist literal (CHK016) — helper novo
  lendo `state.json` direto falha a suite.

Spec: `docs/specs/state-db-runtime-parity/` (contracts/runtime-interfaces.md).

### Scripts parallel-launch.sh e parallel-notification-parse.sh (feature roadmap-parallel-launch)

Consumidos SOMENTE pelos commands pai (`agente-00c.md` §6.ter/§6.quater,
`feature-00c.md` §5.quater) — o orquestrador-subagente nunca oferta, lanca
nem notifica (nao tem `SendMessage`/`ListAgents`; FR-012).

- **`parallel-launch.sh emit --repo PATH --feature SHORT [--description
  TEXT] [--roadmap PATH] [--coordinator-name NAME]`** compoe e **so
  imprime** os comandos de lancamento por feature (`cstk session start
  <SHORT>` + `tmux split-window ... claude --name ... '/feature-00c
  "<DESCRICAO>" <SHORT>'`, ou `cd ... && claude ...` quando `check-tmux`
  sai 3). O wrapper tmux e SEMPRE `split-window` (pane irmao no window da
  coordenadora), nunca `new-window`. A `<DESCRICAO>` vem de
  `--description`, senao do `**Descricao**:` do roadmap, senao do proprio
  short-name (aviso em stderr); e sempre sanitizada (sem aspas nem
  metacaractere de shell) e truncada a 300 chars. NUNCA executa nada e NUNCA toca
  `cli/lib/session.sh` (que faz `exec claude` sem argumentos — por isso a
  composicao e externa). Revalida o short-name (`^[a-z][a-z0-9-]*$`,
  <=64), quoting + allowlist de `<WORKTREE>`/`<CHILD_NAME>`, recomputa a
  guarda anti-duplicidade (`git worktree list --porcelain`, iterar TODAS as
  entradas — nunca `| head -1`) imediatamente antes de compor (TOCTOU) e
  registra linha em `<repo>/.claude/enforcement-log.jsonl`
  (`source: "parallel-launch"`, `command` via `secrets-filter.sh scrub`,
  best-effort). `--coordinator-name` e validado
  (`^cstk-coord/[A-Za-z0-9._-]{1,64}$`) mas NAO entra na composicao (dec-052:
  o endereco da coordenadora e resolvido por convencao via git-common-dir).
- **`parallel-notification-parse.sh check "<msg>"`** casa a mensagem
  INTEIRA contra a regex ancorada do contrato
  (`^\[cstk-parallel\] feature=([a-z][a-z0-9-]{0,63}) outcome=(concluida|abortada|aguardando_humano) repo=([A-Za-z0-9._-]{1,64})$`);
  match ⇒ imprime `feature=`/`outcome=`/`repo=` (uma por linha), exit 0;
  qualquer sobra, enum fora do conjunto ou newline embutida ⇒ exit 1 SEM
  stdout (fail-closed — GOTCHA: `grep -E`/`sed -E` ancoram por LINHA, por
  isso ha guarda anti-multilinha antes do regex). O resultado e **gatilho
  opaco** (INV-8): o receptor recalcula a fronteira com
  `roadmap-frontier.sh` e nunca deriva comando/caminho da mensagem.
- Portabilidade (dec-044/dec-046): trim de colchete via `sed -n
  's/^\[\(.*\)\]$/\1/p'` (parameter expansion `${x#[}` diverge dash/bash);
  JSON-escaping via `awk` (idioma `sed ':a;N;$!ba'` falha no BSD sed em
  input de 1 linha); `$(...)` remove newlines finais — sentinela de lista
  nao pode ser `\n`.
- Testes: `tests/test_parallel-launch.sh` (25), `tests/test_parallel-notification-parse.sh` (15),
  `tests/test_command-spawn-parallel-launch.sh` (interno, 40).

Spec: `docs/specs/roadmap-parallel-launch/` (contracts/parallel-launch.md §4/§6).
