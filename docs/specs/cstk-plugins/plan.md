# Implementation Plan: Plugin System for cstk

**Feature**: `cstk-plugins` | **Date**: 2026-06-08 | **Spec**: [spec.md](./spec.md)

## Summary

Adiciona ao cstk um sistema de plugins que instala repositorios externos
(`cstk-plugin-<name>`) com integridade verificada (manifest + checksum
sha256), sem mergea-los no catalogo core. Tres subcomandos CLI
(`plugin-add`/`plugin-list`/`plugin-remove`) + flag `--llm <name>` nos
entrypoints SDD 00c (path-prepending: skills do plugin consultadas antes do
core, sem copiar/symlinkar — dec-006). Abordagem tecnica: reusar a
infraestrutura POSIX sh existente (`http.sh`, `hash.sh`/`hash_dir`,
`compat.sh`/`sha256_file`, `tarball.sh`, convencao de dispatch
`cli/lib/<cmd>.sh`), zero dependencia obrigatoria nova. `jq` e `sha256*`
entram como deps OPCIONAIS confinadas (carve-out Constitution 1.1.0 §II).

## Technical Context

**Language/Version**: POSIX sh (`#!/bin/sh`, `set -eu`) — Constitution II.
**Primary Dependencies**: ferramentas POSIX canonicas + reuso de
`cli/lib/{http,hash,compat,tarball,common}.sh`. Deps opcionais (carve-out
1.1.0, confinadas, com fallback): `sha256sum`/`shasum -a 256` (via
`compat.sh`, FR-017); `jq` (so em `plugin-common.sh`, fallback POSIX p/
registry).
**Storage**: filesystem user-local. Plugin store: `~/.claude/cstk/plugins/`
(namespace dedicado — research D1, evita colisao com plugins NATIVOS do
Claude Code em `~/.claude/plugins/`). Registry: `registry.json` ali dentro.
Um campo `execution.llm_plugin` em `state.json` (via write path existente).
**Testing**: suite POSIX sh do toolkit (`tests/run.sh`, `tests/cstk/test_*.sh`,
`tests/test_*.sh`), shellcheck `-s sh`. Novos: `tests/cstk/test_plugin-add.sh`,
`test_plugin-list.sh`, `test_plugin-remove.sh`, `test_plugin-common.sh`.
**Target Platform**: qualquer POSIX (macOS/Linux); distribuido via catalogo
`~/.claude` (install/update) + runtime `cli/lib` via self-update.
**Project Type**: cli (single-layer; sem servidor/frontend).
**Performance Goals**: `plugin-list` <2s (SC-004); add→ativar <60s (SC-001).
**Constraints**: zero dep obrigatoria nova (Princ. II); zero coleta remota
(Princ. IV); rede SO no `plugin-add` explicito (FR-006/FR-018); shellcheck
zero-warning (SC-005).
**Scale/Scope**: poucos plugins por usuario; um plugin ativo por invocacao
`--llm`.

## Constitution Check

*GATE: passou antes do Phase 0; re-checado apos Phase 1.*

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD recursivo (NON-NEG) | PASS | Esta feature segue o pipeline (spec→clarify→plan→...); contrato de novos subcomandos documentado em `contracts/`; bump SemVer + CHANGELOG previstos nas tasks. |
| II. POSIX sh, zero dep externa (NON-NEG) | PASS (com carve-out) | Todos os `cli/lib/plugin-*.sh` sao `#!/bin/sh` + `set -eu`, sem Bash-isms. `sha256*` e `jq` entram como deps OPCIONAIS sob o carve-out 1.1.0 §II — confinadas, com fallback documentado e testado (ver "Optional-dep registry" abaixo). |
| III. Formato canonico de skill | N/A | Feature nao cria skill (cria subcomandos CLI + flag). O sistema de plugins, porem, HOSPEDA skills de terceiros (que devem seguir o formato — fora do controle desta feature). |
| IV. Zero coleta remota (NON-NEG) | PASS | `plugin-add` baixa artefato sob comando explicito do usuario, da URL derivada do nome (FR-001), NAO de endpoint do autor nem telemetria. `plugin-list`/`remove`/ativacao 100% offline (FR-018). Declarado em research D3 — exatamente o caso "fetch inerente de rede" permitido pelo Princ. IV. |
| V. Profundidade > adocao (SHOULD) | PASS | Feature nasceu de dor real (PR de adaptacao Codex recusado no core); resolve retrabalho/fragmentacao do catalogo. Sem marketing/badges. |

### Re-check pos-Phase 1

Design NAO introduziu camada/servico extra nem dep obrigatoria. Path-prepending
e read-only (dec-006). O unico desvio de contrato e o store path (research D1,
`~/.claude/cstk/plugins/` em vez do default literal de FR-007) — motivado por
integridade, dentro da mesma feature, com o MUST de FR-007 (nao escrever em
`~/.claude/skills/`) integralmente preservado. **Constitution Check: PASS.**

### Optional-dep registry (carve-out 1.1.0 §II — condicoes a/b/c)

| Dep | (a) Opcional + fallback testado | (b) Confinada a 1 arquivo | (c) Declarada |
|-----|--------------------------------|---------------------------|---------------|
| `sha256sum`/`shasum` | Sim — `compat.sh:sha256_file` ja detecta ambos; ausencia → erro claro, integridade FALHA graceful (nao instala sem verificar). Teste: Scenario 8 / `test_compat.sh`. | `cli/lib/compat.sh` (ja existente; reuso). | research D2 + FR-017. |
| `jq` | Sim — `plugin-common.sh` cai em parser POSIX `grep`/`sed` p/ os campos flat do `registry.json` quando `jq` ausente. Teste: `test_plugin-common.sh` com PATH sem jq. | `cli/lib/plugin-common.sh` (`grep -n jq cli/lib/plugin-*.sh` casa so este). Precedente: `hooks.sh`. | research D5 + esta tabela. |

## Project Structure

### Documentation (this feature)

```
docs/specs/cstk-plugins/
├── spec.md
├── plan.md          # This file
├── research.md      # Phase 0 (6 decisions)
├── data-model.md    # Phase 1 (4 entities)
├── quickstart.md    # Phase 1 (8 scenarios)
└── contracts/       # Phase 1
    ├── cli-commands.md          # plugin-add/list/remove
    └── pipeline-integration.md  # --llm + path-prepending + resume
```

### Source Code (repository root) — arvore REAL do projeto

```
cli/
├── cstk                       # dispatcher (case "$_cmd" → <cmd>_main); EDITAR: rotear plugin-*
├── VERSION                    # bump SemVer
└── lib/
    ├── common.sh  compat.sh  http.sh  hash.sh  tarball.sh   # reuso (sha256, download, hash_dir)
    ├── 00c-bootstrap.sh       # EDITAR: parser de flags ganha --llm; pre-start gate FR-015
    ├── plugin-common.sh       # NOVO: nome→URL, validacao, checksum, registry CRUD, resolve_skill_dir
    ├── plugin-add.sh          # NOVO: plugin_add_main
    ├── plugin-list.sh         # NOVO: plugin_list_main
    └── plugin-remove.sh       # NOVO: plugin_remove_main
global/commands/
    ├── feature-00c.md  agente-00c.md            # EDITAR: aceitar/encaminhar --llm
    ├── feature-00c-resume.md  agente-00c-resume.md   # EDITAR: resume gate FR-016
tests/cstk/
    ├── test_plugin-add.sh  test_plugin-list.sh  test_plugin-remove.sh  test_plugin-common.sh  # NOVO
    └── fixtures/                                 # NOVO: bundles fixture + manifests (ok/tampered)
CHANGELOG.md                  # EDITAR: entrada da feature
```

**Structure Decision**: Segue 1-para-1 a convencao de dispatch existente
(`cli/lib/<subcommand>.sh` + `<subcommand>_main`, vide `cli/cstk` ~L239). O
helper compartilhado `plugin-common.sh` espelha o papel de `tarball.sh`/
`hash.sh` (logica reaproveitavel por multiplos subcomandos). Plugin store em
namespace dedicado `~/.claude/cstk/plugins/` (research D1). Catalogo core
(`~/.claude/skills/`) permanece IMUTAVEL (FR-007 MUST).

## Convencoes de Borda

**N/A — single-layer.** A feature e CLI POSIX sh + artefatos de filesystem
(manifest/registry JSON). Nao ha borda backend↔frontend, DB↔backend ou
broker↔consumer; logo nao ha divergencia de case style (snake_case vs
camelCase) entre camadas. Os "contratos" sao formatos de arquivo JSON
(data-model.md) e a CLI surface (contracts/cli-commands.md). A unica
convencao transversal e o nome do plugin (`^[a-z][a-z0-9-]{0,63}$`, FR-002),
cuja fonte da verdade e `plugin-common.sh` (validacao) e o sufixo do repo
`cstk-plugin-<name>`.

## Infraestrutura / Decisoes Auditaveis

| Aspecto | Decisao | Nota |
|---------|---------|------|
| Idempotencia de install | `plugin-add` re-rodado: detecta versao instalada, exige `--force` ou confirmacao (FR-009); checksum sempre re-verificado | Evita overwrite acidental |
| Verificacao de integridade | Checksum no install (FR-004, gate) + re-verificacao na ativacao/`--verify` (FR-005) | `hash_dir` (research D2); SC-002 100% determinista |
| Atomicidade / rollback de install | Staging em tmp; move p/ store SO apos checksum OK (FR-008); falha/interrupcao → limpa tmp, store intacto | Sem estado parcial (US1-AS2/AS4) |
| Scheduling/infra de estado | N/A para add/remove/list (CLI stateless). `--llm` grava 1 campo em `state.json` via write path existente | Sem nova infraestrutura (spec §SC) |

## Security Threat Model (OWASP gate — plan phase)

Resultado do gate `owasp-security` sobre o design. Foco: A03 (supply chain),
A08 (integrity), A05 (path traversal), ASI04/ASI05 (third-party code execution).
Quatro findings `high` enderecados EM DESIGN (sem codigo ainda):

| Risco | OWASP | Severidade | Mitigacao no design |
|-------|-------|-----------|---------------------|
| **Tar-slip na extracao** | A05 / A08 | high | `plugin-add` MUST validar cada entrada do tarball ANTES de extrair: rejeitar entradas com `..`, path absoluto, ou symlink que aponte para fora do staging. Extracao em `mktemp -d` isolado; qualquer entrada fora do prefixo aborta o install (exit 1, limpa tmp). Detalhado em `contracts/cli-commands.md` §plugin-add passo 5.bis. Sem esse guard, um tarball malicioso escreve fora do store ANTES do checksum rodar. |
| **Sem version pinning** | A03 | high (aceito p/ MVP, documentado) | `plugin-add <name>` resolve a release mais recente; nao ha pin de tag/commit no MVP. Mitigacao parcial: o `bundle_sha256` verificado e gravado no registry (`registry.json`), entao reinstalacoes futuras podem comparar contra o hash conhecido (TOFU — trust on first use). Pin explicito (`plugin-add <name>@<ver>`) e extensao futura anotada. SC-002 protege contra corrupcao de transporte, NAO contra substituicao upstream sem mudanca de versao declarada. |
| **Manifest auto-assinado (checksum no mesmo source)** | A08 | high (residual, documentado) | O `sha256` vive DENTRO do `plugin-manifest.json`, baixado da MESMA origem do bundle. Um upstream comprometido troca bundle + manifest juntos e o checksum casa. Portanto o checksum garante "os bytes sao os que o autor empacotou", NAO "os bytes sao seguros". Confianca de ORIGEM e delegada ao trust model do GitHub namespace (FR-001 default `JotJunior/`, mesmo trust do toolkit). Assinatura destacada (GPG/minisign) e extensao futura (campo `signature` reservado no schema). **SC-002 reformulado mentalmente: deteccao de MISMATCH bundle↔manifest, nao deteccao de upstream malicioso.** |
| **Execucao de codigo de terceiros via skills do plugin** | ASI04/ASI05/LLM01 | high (aceito por design, documentado) | Um plugin entrega `SKILL.md` (instrucoes p/ o LLM) + `scripts/*.sh` (POSIX) que a pipeline SEGUE/EXECUTA quando `--llm <plugin>` ativo. O checksum verifica os BYTES, nao a SEGURANCA. Nenhum sandbox e proposto (incompativel com Princ. II POSIX-sh zero-dep). **Controle = honestidade do trust model**: instalar um plugin equivale a `cp` de codigo arbitrario para o seu toolkit; o plugin roda com a MESMA confianca do catalogo core. SKILL.md de plugin e conteudo NAO-confiavel sob a otica de LLM01 (prompt injection indireta) — a documentacao do usuario MUST avisar para so instalar plugins de autores confiaveis. |

**Pontos fortes do design (sem finding)**: validacao de nome `^[a-z][a-z0-9-]{0,63}$`
antes de fs/rede (A05, FR-002); checksum-gate antes de qualquer escrita +
staging atomico (A08, FR-004/FR-008); re-verificacao na ativacao (FR-005);
rede SO em `plugin-add` explicito, demais ops offline (A03/Princ. IV,
FR-006/FR-018).

## Complexity Tracking

> Sem violacoes de constitution que exijam justificativa de complexidade. O
> uso de deps opcionais (`sha256*`, `jq`) NAO e violacao — e conformidade
> explicita sob o carve-out 1.1.0 §II (ver "Optional-dep registry" acima),
> que o Decision Framework item 4 reconhece como mecanismo valido. Nenhuma
> camada/servico extra introduzido.

| Violacao | Por Que Necessario | Alternativa Simples Rejeitada Porque |
|----------|-------------------|--------------------------------------|
| (nenhuma) | — | — |
