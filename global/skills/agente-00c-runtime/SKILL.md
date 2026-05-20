---
name: agente-00c-runtime
description: |
  Biblioteca interna de scripts POSIX consumida pelos agentes custom do
  agente-00C (orchestrator, clarify-asker, clarify-answerer). NAO e
  user-invocavel — usuarios usam `/agente-00c`, `/agente-00c-resume` e
  `/agente-00c-abort`. Esta skill apenas empacota helpers de estado
  (state.json), validacao de schema, backups por onda e lock
  anti-concorrencia.
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
mecanismo de `cstk install` so distribui artefatos sob `global/skills/`,
`global/commands/` ou `global/agents/`.

## Estado atual

**FASE 2 do backlog em `docs/specs/agente-00c/tasks.md`.** Implementacao
operacional dos 3 scripts entregue como esqueleto + cobertura de testes
em `tests/test_state-*.sh`.

## Reuso pelo feature-00c (FASE 1 de `docs/specs/feature-00c/tasks.md`)

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
