# Contract: scripts internos do plugin (`plugins/cstk-jira/scripts/`)

Interface de linha de comando PROJETADA por este plano (nao e contrato de
sistema externo — Principio VI nao exige fonte para interface nova; os pontos
em que ela toca o Jira remetem a `jira-rest.md`/`rovo-mcp.md`).

Convencoes comuns (Principio II):

- `#!/bin/sh`, `set -eu`, sem bash-isms; dados em stdout, diagnostico em stderr.
- Exit codes: `0` sucesso; `1` erro geral; `2` uso incorreto; `3` plugin
  inativo/nao configurado (FR-017 — chamador trata como no-op);
  `4` credencial ausente/rejeitada (FR-016); `5` dependencia ausente
  (`jq`/cliente HTTP — carve-out 1.1.0, condicao a); `6` conflito detectado
  (FR-011) ou orfao (FR-012) — nada foi sobrescrito.
- Nenhum script aceita URL, host ou credencial por argumento: host vem de
  `ProjectConfig.site_host`, credencial de `Credential` (`data-model.md`).
- Instalado o plugin, SO a subarvore `plugins/cstk-jira/` existe no disco do
  usuario: nenhum script referencia `cli/lib/` nem o plugin `cstk` por caminho
  relativo do repositorio.

## `jira-io.sh` — UNICO arquivo com `jq` e cliente HTTP (carve-out 1.1.0 b)

| Subcomando | Entrada | Saida | Notas |
|------------|---------|-------|-------|
| `deps-check` | — | nada | exit 5 + instrucao de instalacao se faltar `jq` ou o cliente HTTP |
| `request METHOD PATH [--body-file F]` | METHOD em `GET`/`POST`/`PUT` (allowlist fechada — nao existe `DELETE`, FR-012); PATH relativo iniciado em `/rest/` | corpo da resposta em stdout; status HTTP na 1a linha de stderr estruturado | monta `https://<site_host><PATH>`; valida host por IGUALDADE exata (sem userinfo, sem porta) antes de cada requisicao; NAO segue redirect para host diferente (FR-015); credencial passada ao cliente HTTP por arquivo de config temporario `0600` removido em `trap`, nunca em argv |
| `json-get FILTER` | JSON em stdin | valor em stdout | wrapper de leitura (restringe `jq` a este arquivo) |
| `json-build ...` | pares chave/valor | JSON em stdout | monta corpos a partir de `contracts/jira-rest.md` |

Mapeamento de status HTTP (politica de design):

| Resposta | Tratamento |
|----------|-----------|
| 2xx | sucesso |
| 401 / 403 em chamada autenticada | exit 4 (`auth_failed`) — nunca retry (FR-016/FR-019) |
| 429 | exit 1 com `retry_after=<s>` em stderr quando o header `Retry-After` vier (research Decision 3) — evento vira `deferred` |
| 5xx / erro de rede / timeout | `deferred`, backoff limitado a 3 tentativas por drain |
| 400 em transicao concorrente | `deferred` (research Decision 3: requisicoes simultaneas na mesma issue) |

## `jira-config.sh`

| Subcomando | Descricao |
|------------|-----------|
| `get KEY` | le `ProjectConfig`; exit 3 se arquivo ausente |
| `validate` | valida campos obrigatorios, `site_host` como hostname puro e `status_fail != status_pass` |
| `credential-check` | confere existencia e permissao `0600` do arquivo de credencial para `site_host` (sem imprimir valores) |

## `jira-tasks.sh` (POSIX, `awk`)

| Subcomando | Saida (TSV) |
|------------|-------------|
| `items --feature F` | `local_key  kind  phase  criticality  local_state  title` para Epic + tasks + subtasks do `tasks.md` (regras de `data-model.md` §LocalWorkItem) |

## `jira-map.sh` (POSIX)

| Subcomando | Descricao |
|------------|-----------|
| `get --feature F --local-key K` | linha do mapeamento ou exit 1 |
| `put --feature F --local-key K --kind KIND --jira-id ID --jira-key KEY` | insere de forma atomica (tmp + `mv`); recusa `local_key` ja `active` (FR-013) |
| `mark-orphans --feature F` | marca `orphan` as chaves ausentes de `jira-tasks.sh items`; imprime os orfaos |
| `relink --feature F --local-key K --jira-key KEY` | religa um orfao por decisao humana |

## `jira-sync.sh` — motor

| Subcomando | Descricao |
|------------|-----------|
| `plan --feature F` | dry-run: lista criacoes, atualizacoes, transicoes, orfaos e conflitos previstos, sem rede de escrita |
| `convert --feature F` | US1: cria Epic, depois Tasks (filhas do Epic), depois Sub-tasks, gravando o mapeamento item a item; pre-condicao: `deps-check`, `validate`, `credential-check` e validacao de credencial remota — qualquer falha aborta ANTES da 1a criacao (US1 cenario 3: sem artefato parcial por credencial invalida) |
| `enqueue --feature F --local-key K --state S --source SRC` | append no outbox |
| `drain --feature F` | processa o outbox com lock `runtime/.drain.lock/`; para cada item: le issue + SyncMarker, detecta conflito, transiciona para o status mapeado, regrava SyncMarker |
| `status [--feature F]` | resumo do outbox + conflitos + orfaos + `auth_failed` |
| `resolve --feature F --local-key K --choice keep_jira\|overwrite\|ignored` | fecha ConflictRecord por decisao humana |

## Caminho interativo (skills) sem `jq`/cliente HTTP

As skills `jira-setup`, `jira-convert` e `jira-sync` usam as tools do Rovo MCP
(`rovo-mcp.md`) quando visiveis na sessao, e so chamam `jira-map.sh`,
`jira-tasks.sh` e `jira-config.sh` (POSIX puro). Esse e o fallback verificavel
da condicao (a) do carve-out 1.1.0: sem `jq`/cliente HTTP a conversao e a
sincronizacao continuam possiveis pela sessao interativa; o que degrada e o
sync AUTONOMO, que sai com exit 5 + diagnostico e mantem os eventos no outbox
para o proximo `jira-sync` interativo.
