# Data Model: panel-docker

Esta feature nao introduz tabelas nem schema persistente. As "entidades" abaixo sao
recursos de runtime (container, imagem, mount) e seus atributos de identidade/ciclo de
vida. Aterradas na spec (Key Entities) e nas fontes de `research.md`. Nenhum valor
concreto e inventado: numeros/nomes marcados `[a fixar]` sao decisoes de implementacao.

## Entity: Verified Panel Installation (Instalacao Verificada do Painel)

A mesma arvore-fonte do painel obtida e verificada pelo fluxo existente
(`_serve_install`, serve.sh L194-354), reaproveitada como contexto de build da imagem.
NAO e uma fonte de download nem verificacao separadas (spec Key Entities).

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| source_tarball_url | string (URL) | host em `CSTK_TRUSTED_RELEASE_HOSTS` | da API GitHub (serve.sh L55, L225) |
| panel_version | string | ex. `v0.12.1` | grava/le `.panel-version` (serve.sh L348) |
| integrity_outcome | enum | `verified` \| `unverifiable-bypassed` \| `unverifiable-blocked` \| `mismatch-blocked` | serve.sh L288-313; blocked = aborta |
| extracted_tree_path | path | dir temporario no host | contexto do `docker build` (Decision 1) |
| host_npm_used | bool | **MUST ser false** no modo Docker | FR-006 — o `npm ci` roda no build da imagem (estagio de build), nunca no host |

**Diferenca face ao nativo**: no modo nativo, esta arvore recebe `npm install` no host
e vira `~/.local/share/cstk/panel`. No modo Docker, para em `extracted_tree_path`
(sem npm no host) e serve de contexto de build.

## Entity: Panel Image (Imagem do Painel)

Imagem Docker local construida a partir da Verified Panel Installation.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| image_tag | string | local, deterministico | ex. `cstk-panel:<panel_version>` `[a fixar]`; nunca registry remoto (FR-013) |
| base_image | string | `node:22-alpine`, musl (multi-stage) | Decision 1; digest fixado (dec-037) `sha256:16e22a550f3863206a3f701448c45f7912c6896a62de43add43bb9c86130c3e2` |
| contains_npm_node | bool | true | fornece runtime de linguagem (FR-006) |
| contains_forwarder | bool | true | `socat` ou proxy Node (Decision 2) |
| contains_knowledge_db | bool | **MUST ser false** | db e montado em runtime, nunca baked (Decision 7) |
| build_trigger | enum | `absent` \| `--reinstall` \| `--update`(versao nova) | quando (re)construir (Decision 5) |

### State Transitions

```
(sem imagem) --build--> built --[--update: versao nova]--> rebuilt
                          |
                          +--[--reinstall]--> removed --build--> built
```

## Entity: Containerized Panel Instance (Instancia Containerizada do Painel)

A execucao do painel dentro do container (spec Key Entities). Ciclo de vida atrelado a
uma invocacao do modo Docker.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| container_name | string | deterministico, unico por host | ex. `cstk-panel` `[a fixar]`; chave de idempotencia (FR-012-INFRA-IDEMP) |
| management_label | string | ex. `cstk.managed=serve` | reconciliacao/descoberta (Decision 6) |
| host_published_bind | string | `127.0.0.1:<porta-host>` por default | `-p` no loopback do host (Decision 4) |
| host_port | int | 1024-65535 | de `--port` (default 5173); validacao serve.sh L488-508 |
| container_listen_port | int | forwarder em `0.0.0.0` | `[a fixar]` (Decision 4) |
| panel_internal_port | int | painel em `127.0.0.1` | `PORT` no container (config.ts L80 default 3001) |
| knowledge_db_mount | ref | read-only | ver entidade abaixo |
| auto_remove | bool | true (`--rm`) | happy-path sem vestigio (Decision 6) |
| init_pid1 | bool | true (`--init`) | propagacao de sinal + reaping (Decision 6) |

### State Transitions

```
(reconciliar remanescente: rm -f nome, idempotente)
        |
        v
   not-running --run--> starting --ready--> running
                                              |
                        Ctrl+C / SIGTERM do host -> docker stop (grace ~5s)
                                              |
                                              v
                                          stopped --(--rm)--> removed
```

- **Reconcile pre-run** (FR-012-INFRA-IDEMP): container remanescente (parado OU rodando)
  de mesmo nome e removido antes de `run` — nunca erro cru do runtime (US4).
- **Interrupcao durante build/start** (Edge Case): se Ctrl+C ocorre antes de `ready`,
  o handler para/remticra o container parcial pelo nome deterministico (sem orfao, FR-011).

## Entity: Knowledge DB Mount (Montagem do Indice de Conhecimento)

Exposicao read-only do knowledge.db do host ao container (FR-008/FR-009).

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| host_source | path | dir de dados do cstk | `dirname(CSTK_KNOWLEDGE_DB)` senao `~/.claude/cstk/` (config.ts L49/L53) |
| mount_mode | enum | **`ro` (read-only)** | FR-009; segunda barreira ao read-only do painel (open.ts L100-121) |
| container_target | path | dir montado no container | `[a fixar]` |
| env_pointer | string | `CSTK_KNOWLEDGE_DB=<target>/knowledge.db` | resolucao do painel (config.ts L49) |
| journal_mode | enum | `wal` (fato empirico) | requer `-shm`/`-wal` visiveis -> montar diretorio (Decision 3) |
| wal_readonly_verified | bool | **MUST ser verificado** | RISCO #1 — read-only WAL sem `immutable=1` (research.md Decision 3) |

## Entity: Container Runtime Check (Checagem do Runtime de Container)

Pre-flight fail-closed antes de qualquer rede (FR-003/FR-004).

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| binary_present | bool | `command -v docker` | ausente -> "nao instalado" (exit 1) |
| daemon_reachable | bool | sonda server-side | inacessivel -> "daemon parado/inacessivel" (exit 1), mensagem DISTINTA (FR-004) |
| checked_before_network | bool | **MUST true** | FR-003 / SC-006 (<5s, sem rede antes) |

### State Transitions

```
start --check binary--> [absent] -> fail-closed "docker nao instalado"
                    \--> [present] --check daemon--> [down] -> fail-closed "daemon inacessivel"
                                                \--> [up]  -> prosseguir (download+build+run)
```
