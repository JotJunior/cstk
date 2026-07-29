# Implementation Plan: panel-docker

**Feature**: `panel-docker` | **Date**: 2026-07-11 | **Spec**: [spec.md](./spec.md)

## Summary

Adicionar um modo **opt-in** `--docker` ao `cstk serve` que sobe o mesmo painel
(`cstk-panel`) dentro de um container local, para usuarios sem `npm`/`node` no host,
sem alterar o comportamento nativo (default) nem o repositorio externo `cstk-panel`.

Abordagem tecnica (aterrada em `research.md`): reaproveitar o fluxo de download +
integridade fail-closed + trusted-hosts JA existente (`_serve_install`, serve.sh) para
obter a arvore-fonte VERIFICADA do painel; construir uma **imagem Docker local
multi-stage** (base `node:22-alpine`, musl) cujo estagio de build faz `npm ci && npm run
build` — compilando o modulo nativo `better-sqlite3` do fonte (sem prebuild musl) — e
cujo estagio de runtime slim carrega apenas o painel ja buildado; assim `npm` fica na
imagem, nao no host (FR-006). O painel faz bind hardcoded em `127.0.0.1` (config.ts
L81), entao um **encaminhador in-container** (`socat` recomendado) escuta em
`0.0.0.0:<porta>` e repassa ao loopback interno (FR-005, resolvido 100% do lado
cstk/Docker). O `knowledge.db` do host e exposto por **bind mount read-only** +
`CSTK_KNOWLEDGE_DB` (FR-008/009). Ciclo de vida idempotente por nome deterministico com
reconciliacao de remanescentes e `docker stop` gracioso espelhando `_serve_shutdown`
(FR-011 + requisito INFRA-IDEMP). Nenhuma imagem e enviada a registry (FR-013).

## Technical Context

**Language/Version**: POSIX sh (Constituicao II) para o codigo cstk; a imagem usa Node
`22` (satisfaz `engines.node >=20.0.0`, package.json L28). Base `node:22-alpine` (musl),
multi-stage (Decision 1).
**Primary Dependencies**: runtime de container (`docker`, opt-in — carve-out II, ver
Constitution Check); `curl` + `tar` (host, download/extracao — ja usados); painel traz
`fastify ^5`, `@fastify/static ^8`, `better-sqlite3 ^9.6.0` (nativo); encaminhador
`socat` (ou proxy Node) na imagem.
**Storage**: nenhum novo. Le `~/.claude/cstk/knowledge.db` (WAL) read-only.
**Testing**: harness POSIX do toolkit — `tests/cstk/test_serve.sh` (estender) + testes
do novo helper docker; `./tests/run.sh`.
**Target Platform**: host de desktop (macOS/Linux) com Docker; container linux musl (alpine).
**Project Type**: CLI (extensao de `cstk serve`), orquestracao de container.
**Performance Goals**: SC-006 — diagnostico de runtime ausente/inacessivel <5s, sem
rede antes da checagem.
**Constraints**: FR-002 (zero mudanca no default nativo); FR-006 (sem `npm` no host);
FR-013 (sem push a registry); Constituicao II (POSIX sh, sem Bash-isms) e VI (zero
fabricacao).
**Scale/Scope**: single-host, single-instance por host (requisito INFRA-IDEMP da
spec); sem
scheduling/mutex multi-pod/rotacao de chave (spec: N/A explicitos).

## Constitution Check

*GATE: Deve passar antes do Phase 0. Re-checado apos Phase 1 (§RE-CHECK abaixo).*

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD recursivo (MUST) | PASS | feature entra pela pipeline: spec.md + clarify + este plan; tasks a seguir |
| II. POSIX sh, zero dep externa (MUST) | PASS (via carve-out 1.1.0) | codigo cstk permanece POSIX sh sem Bash-isms; `docker` e **dep opcional opt-in** — ver Complexity Tracking (3 condicoes cumulativas). Espelha o precedente de `curl`/`npm` como prereqs opt-in ja aceitos em serve.sh |
| III. Formato canonico de skill (MUST) | N/A | nao ha skill nova; e runtime CLI (`cli/lib`) |
| IV. Zero coleta remota (MUST) | PASS | FR-013 proibe push/registry; unica rede e a checagem de release GitHub JA existente (nao-autenticada); nenhuma telemetria |
| V. Profundidade > adocao (SHOULD) | PASS | reduz atrito real (rodar sem `npm`); nao e feature de vaidade |
| VI. Veracidade de dados (MUST) | PASS | todo dado concreto em spec/plan/research/contracts aterrado em fonte citada; unknowns marcados como pendentes-de-clarificacao / detalhe-de-execute-task no research.md, nunca inventados; RISCO #1 (WAL read-only) sinalizado para verificacao empirica |

Nenhum FAIL em principio MUST. Prosseguiu para Phase 0/1.

## Project Structure

### Documentation (this feature)

```
docs/specs/panel-docker/
├── spec.md
├── plan.md          # This file
├── research.md      # Phase 0 — 7 decisoes aterradas + unknowns
├── data-model.md    # Phase 1 — entidades de runtime (container/imagem/mount)
├── quickstart.md    # Phase 1 — 10 cenarios (inclui roundtrip de paridade)
└── contracts/
    └── cli-docker-mode.md   # Phase 1 — flag --docker + contrato docker run
```

### Source Code (repository root — arvore real)

```
cli/
├── cstk                     # dispatch `serve)` -> serve_main (L211-220)  [editar --help/wire]
└── lib/
    ├── serve.sh             # fluxo nativo; adicionar caminho --docker (ou delegar)  [editar]
    ├── trusted-hosts.sh     # trusted_host_check — REUSAR intacto no download docker
    ├── http.sh              # http_download — reusado
    └── compat.sh            # sha256_file — reusado
tests/
└── cstk/
    └── test_serve.sh        # estender com cenarios --docker  [editar]
```

**Structure Decision**: manter o codigo docker **confinado** para satisfazer a condicao
(b) do carve-out do Principio II (dep opcional em um arquivo identificavel). Duas opcoes
a decidir em create-tasks/execute-task: (i) um novo `cli/lib/serve-docker.sh` sourced
por `serve.sh` quando `--docker`; ou (ii) um bloco coeso dentro de `serve.sh`. Preferir
(i) para isolar as mencoes a `docker` num unico arquivo (facilita grep + teste +
conformidade com a condicao b). O Dockerfile/entrypoint sao gerados/enviados pelo cstk
(pequenos, deterministicos), localizacao `[a fixar em create-tasks]`.

## Convencoes de Borda

**N/A — single-layer.** Esta feature e orquestracao CLI/shell de container; NAO
introduz nova fronteira backend↔frontend nem novos payloads/DTOs. O painel
(`cstk-panel`) ja tem suas proprias convencoes de borda e NAO e alterado por esta
feature (Clarification: resolucao 100% do lado cstk/Docker).

A unica "borda" nova e **host (shell cstk) ↔ container**, cujo contrato (variaveis de
ambiente, mounts, portas, nome/label, ciclo de vida) esta declarado em
[`contracts/cli-docker-mode.md`](./contracts/cli-docker-mode.md), com a fonte da verdade
de cada valor apontada (serve.sh / config.ts / decisoes do research.md). O relay de
porta (FR-005) e a resolucao do `CSTK_KNOWLEDGE_DB` sao os pontos dessa borda; nenhum
envolve case-style/serializacao de payload.

## Complexity Tracking

> Registro da conformidade do Principio II (carve-out "Optional dependencies with
> graceful fallback", amendment 1.1.0) para a dependencia `docker`.

| Item | Conformidade |
|------|--------------|
| (a) uso opcional + fallback documentado E testavel | `docker` so e exigido quando `--docker` (opt-in); o "fallback" e o **modo nativo** intacto (FR-002), que funciona sem `docker`. Quando `--docker` e dado e `docker` esta ausente/inacessivel, o comportamento e **fail-closed com mensagem acionavel** (FR-003/004) — mesmo padrao ja aceito para os prereqs `curl`/`npm` do modo nativo (serve.sh L519-527). Coberto por testes (quickstart Scenarios 2-3; `tests/cstk/test_serve.sh`). |
| (b) dep confinada em UM arquivo identificavel | mencoes a `docker` confinadas a `cli/lib/serve-docker.sh` (preferido) — grep por `docker` localiza tudo num arquivo (Structure Decision). |
| (c) dep declarada na doc da feature | declarada aqui (spec FR-001/003/004/006 + este plan + research.md). |

> **Nota sobre "fallback graceful" vs "fail-closed"**: o carve-out pede fallback que
> "produz resultado correto". Aqui, o fallback e a NAO-ativacao do modo (rodar sem
> `--docker` = nativo, plenamente funcional). Pedir explicitamente `--docker` num host
> sem `docker` NAO deve cair em nativo silenciosamente (seria surpresa/insergurança
> quanto ao isolamento esperado) — por isso fail-closed com diagnostico, coerente com
> como serve.sh ja trata `npm`/`curl` ausentes. Este e o mesmo criterio de "prereq de
> ferramenta" ja em producao, nao uma nova excecao a MUST.

### Risco tecnico rastreado (nao e violacao de constitution)

- **RISCO #1 (research.md Decision 3)**: leitura do knowledge.db em WAL, conexao
  readonly better-sqlite3 **sem `immutable=1`**, sobre mount read-only. Modo de falha
  conhecido do SQLite. Mitigacao proposta (montar o diretorio `:ro` com sidecars)
  precisa de **verificacao empirica** em execute-task (quickstart Scenario 4). Se
  insuficiente, a dependencia do patch `immutable=1` no `cstk-panel` (adiado na
  Clarification) volta a escopo — a registrar como bloqueio, nunca presumir resolvido.

## Re-check (pos Phase 1)

Design nao introduziu servico/camada extra nao justificada. `docker` permanece a unica
dep nova, confinada e opt-in (carve-out II). Nenhum novo caminho de rede alem do
GitHub-release ja existente (IV preservado). FR-013 (sem push) mantido no desenho da
imagem. Constitution Check permanece **PASS** apos o design.

## Artefatos

| Arquivo | Status |
|---------|--------|
| docs/specs/panel-docker/plan.md | Criado |
| docs/specs/panel-docker/research.md | Criado |
| docs/specs/panel-docker/data-model.md | Criado |
| docs/specs/panel-docker/contracts/cli-docker-mode.md | Criado |
| docs/specs/panel-docker/quickstart.md | Criado |

## Proximos Passos

1. `/checklist` — quality gate dos requisitos antes de implementar.
2. `/create-tasks` — decompor em backlog (fixar: layout do arquivo docker confinado,
   Dockerfile/entrypoint, invocacao socat, sonda de daemon, flags de hardening,
   verificacao empirica do RISCO #1).
3. `/analyze` — consistencia cross-artifact apos tasks.
