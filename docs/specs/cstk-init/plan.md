# Implementation Plan: cstk-init (adocao do cstk em projeto existente)

**Feature**: `cstk-init` | **Date**: 2026-11-14 | **Spec**: [spec.md](./spec.md)

## Summary

Nova skill de catalogo `cstk-init` (dec-006: sem subcomando do binario) que adota o cstk
num projeto existente: inventaria artefatos, cria ou revisa `docs/briefing.md` e
`docs/constitution.md`, e, se o operador aceitar, reconstitui specs de features
existentes com documentos complementares sob demanda. Abordagem (research.md):

- **Formato por referencia**: os documentos sao preenchidos a partir dos templates das
  skills irmas (`briefing`, `constitution`, `specify`, `plan`) lidos da mesma raiz de
  catalogo; `checklist` e invocada pela tool `Skill`. Nenhum template e copiado
  (Decision 1).
- **Determinismo onde ha regra**: seis scripts POSIX `init-*.sh` cobrem pre-condicoes,
  estado dos artefatos, inventario, conformidade, evidencias de features, guarda de
  escrita e lint de origem (Decision 3). O modelo faz so o que e semantico: ler os
  artefatos inventariados, agrupar evidencias em features e redigir.
- **Nunca sobrescrever**: escrita create-only por guarda fail-closed; alteracao de arquivo
  existente so com confirmacao explicita, e emenda de constitution versionada (Decision 6).
- **Zero fabricacao**: todo fato cita origem; sem fonte vira `[PENDENTE: ...]`; spec
  reconstituida separa observado de inferido (Decision 12, contracts/markers.md).

## Technical Context

**Language/Version**: POSIX sh (`#!/bin/sh`, `set -eu`) para scripts; Markdown para SKILL.md, references e templates
**Primary Dependencies**: ferramentas POSIX canonicas (`find`, `grep`, `awk`, `sed`, `sort`, `cmp`, `mktemp`); `git` opcional confinado em `init-probe.sh` (carve-out 1.1.0); skills irmas do perfil `sdd` (templates + `checklist/scripts/requirement-coverage.sh` + `agente-00c-runtime/scripts/secrets-filter.sh check`)
**Storage**: N/A — sem estado proprio; o sistema de arquivos do projeto-alvo e a fonte (Decision 10)
**Testing**: harness POSIX `tests/run.sh` (`tests/test_init-*.sh` + fixtures `tests/fixtures/cstk-init/`); trigger eval via `evals/triggers.jsonl`
**Target Platform**: Claude Code, via plugin nativo e instalacao classica (fonte: dec-006 / spec FR-001); mesma plataforma das demais skills do catalogo com scripts POSIX (fonte: constitution Principio II)
**Project Type**: skill de catalogo (documentacao + scripts deterministicos)
**Performance Goals**: N/A (interativo; sem meta de latencia na spec)
**Constraints**: zero rede (FR-012, Principio IV); escrita so na raiz do projeto-alvo e na allowlist do guarda; nenhum valor de arquivo `secret-bearing` lido ou copiado
**Scale/Scope**: inventario com teto default de 1000 itens (valor de design sem medicao, ajustavel por `--max-items`; FR-030) e aviso `TRUNCATED`; ate 5 perguntas por rodada e candidatas em lotes de ate 5 (padrao de politica de UX)

## Constitution Check

*GATE: Deve passar antes do Phase 0. Re-checar apos Phase 1.*

Constitution do toolkit `docs/constitution.md` 1.3.0.

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD recursivo (MUST) | PASS | spec clarificada + este plano; `tasks.md` antes de implementar; skill nova = MINOR no CHANGELOG (nao altera contrato de skill existente) |
| II. POSIX sh puro (MUST) | PASS | seis scripts `#!/bin/sh` + `set -eu`, sem `jq`; `git` opcional com fallback `VCS none` testado e confinado em `init-probe.sh` (carve-out 1.1.0, condicoes a/b/c declaradas aqui e em research Decision 7); JSON do `plugin.json` lido por `grep`/`sed` de uma chave |
| III. Formato canonico de skill (MUST) | PASS | SKILL.md enxuto + `references/`, `templates/`, `scripts/`, `evals/`; secao Gotchas; `description` como trigger com "NAO use" apontando `briefing`, `constitution`, `reconcile-docs` |
| IV. Zero coleta remota (MUST) | PASS | nenhum acesso de rede; versao vem do manifesto/plugin.json local (dec-007) |
| V. Profundidade (SHOULD) | PASS | reduz retrabalho de adocao (documentacao manual); reusa templates em vez de duplicar |
| VI. Zero fabricacao (MUST) | PASS | FR-006/FR-007 viram marcadores verificaveis por `init-provenance.sh` (`DANGLING` bloqueia conclusao); inferido sem palavra normativa; pendencia em vez de default; contratos novos marcados `[PROPOSTA]` |

## Project Structure

### Documentation (this feature)

```
docs/specs/cstk-init/
├── spec.md
├── plan.md                  # este arquivo
├── research.md              # Phase 0 (14 decisoes)
├── data-model.md            # Phase 1 (ProbeResult, ArtifactState, InventoryItem, Divergence, EvidenceSignal, FeatureCandidate, Pending, RunSummary)
├── quickstart.md            # Phase 1 (22 cenarios)
├── contracts/
│   ├── cli-invocation.md    # /cstk-init + 6 scripts
│   └── markers.md           # marcadores de origem, pendencia, reconstituicao, emenda
├── checklists/              # proxima etapa
└── tasks.md                 # proxima etapa
```

### Source Code (repository root)

```
plugins/cstk/skills/cstk-init/                    # [PROPOSTA] NOVO
├── SKILL.md                                       # fluxo, regras, Gotchas
├── references/
│   ├── conformance-rules.md                       # catalogo CR-NNN (Decision 5)
│   ├── feature-recognition.md                     # agrupamento de sinais em features (dec-008)
│   └── write-policy.md                            # create-only, emenda, migracao, VCS
├── templates/
│   ├── reconstructed-spec-addendum.md             # cabecalho de origem + secao Inferido (markers.md §3)
│   └── summary.md                                 # resumo de execucao (data-model §RunSummary)
├── scripts/
│   └── init-{probe,inventory,conformance,candidates,guard,provenance}.sh
└── evals/triggers.jsonl

plugins/cstk/evals/cstk-init/NNN/case.yaml        # gerado por tests/trigger-eval/gen-eval-cases.sh
tests/test_init-{probe,inventory,conformance,candidates,guard,provenance}.sh   # [PROPOSTA]
tests/fixtures/cstk-init/{bare,legacy,conformant,three-features,secrets,both-briefings,hostile,pending}/  # [PROPOSTA]
tests/trigger-eval/negatives.jsonl                # [EXISTENTE] + negativos de adocao, se o eval pedir

scripts/profiles.txt.in                           # [EXISTENTE] + sdd:cstk-init (Decision 2)
cli/lib/install.sh                                # [EXISTENTE] help do perfil sdd (linhas 103-105)
docs-site/manual/profiles.md                      # [EXISTENTE] lista do perfil sdd
README.md, README.pt-BR.md                        # [EXISTENTE] contagens gateadas por tests/test_doc-counts.sh:
                                                  #   "23 global skills" -> 24 (README.md:148),
                                                  #   sdd 17 -> 18 e all 30 -> 31 (README.md:343-345 e 707-709),
                                                  #   + linha na tabela do pipeline SDD (README.md:221-232)
CHANGELOG.md + manifests em lockstep              # [EXISTENTE] proximo MINOR (.claude-plugin/marketplace.json,
                                                  #   plugins/cstk/.claude-plugin/plugin.json)
```

Skills irmas consumidas (somente leitura, nenhuma alterada nesta feature salvo
descricao, ver abaixo): `plugins/cstk/skills/briefing/templates/briefing.md`,
`plugins/cstk/skills/briefing/references/discovery-guide.md`,
`plugins/cstk/skills/constitution/templates/constitution.md`,
`plugins/cstk/skills/specify/templates/feature-spec.md`,
`plugins/cstk/skills/plan/templates/data-model.md`,
`plugins/cstk/skills/checklist/scripts/requirement-coverage.sh`,
`plugins/cstk/skills/agente-00c-runtime/scripts/secrets-filter.sh`.

`tests/cstk/fixtures/regen.sh` copia `plugins/` inteiro (nao enumera skills), mas os
fixtures de release cacheados precisam ser regenerados apos adicionar a skill e o perfil
(convencao do repo para mudanca de catalogo/perfil).

**Structure Decision**: SKILL.md orquestra: `init-probe.sh preflight` (exit != 0 encerra
antes de escrever; `VCS` != `git-clean` pede confirmacao) → `init-probe.sh artifacts` +
`version` → `init-inventory.sh inventory` (exibido ao operador) → leitura dos artefatos
inventariados (nunca `secret-bearing`) → briefing: criar (template irmao, perguntas so
para lacunas) ou revisar (`init-conformance.sh check` → divergencias → confirmacao item a
item ou em lote) → constitution: idem, priorizando perguntas de principios e emendando via
regras da skill `constitution` → pergunta de registro de features → `init-candidates.sh
evidence` → lotes de candidatas → por confirmada: `init-candidates.sh name` → spec
(template irmao + addendum) → `requirement-coverage.sh` → oferta de complementares
(`Skill(checklist)`, `data-model` por template) → resumo (`templates/summary.md`). Antes da primeira escrita: `init-guard.sh scan --probe` (fail-closed, FR-027). Migracao do briefing legado: `init-guard.sh migrate` apos confirmacao por caminho (FR-032). Cada
escrita: `init-guard.sh check` → Write/Edit → `init-guard.sh scan` →
`init-provenance.sh lint`. A raiz de catalogo e resolvida a partir do diretorio da propria
skill (`<raiz>/skills/cstk-init` → irmas em `<raiz>/skills/<irma>`), na ordem projeto →
plugin → global, sem misturar raizes.

**Descricoes das irmas**: `briefing` e `constitution` so recebem nota "NAO use para adotar
o cstk em projeto existente (use `cstk-init`)" se o Scenario 16 do quickstart mostrar
colisao de trigger; alteracao de `description` de skill existente exige nota no CHANGELOG.

## Convencoes de Borda

N/A — single-layer (skill local sem API, banco ou frontend). Unica fronteira interna:
TSV dos scripts → modelo. Colunas separadas por TAB, sem cabecalho, uma entidade por linha;
linha final `STATUS\t<token>` em `init-conformance.sh` e `init-provenance.sh`. Tokens de
enum em ingles (`absent`, `legacy`, `secret-bearing`, `exists-active`, ...); rotulos do
relatorio em pt-BR.

## Riscos e mitigacoes

| Risco | Mitigacao |
|-------|-----------|
| Modelo escreve fato sem fonte ao redigir briefing/spec | `init-provenance.sh lint` (DANGLING bloqueia conclusao); Gotcha dedicado; Scenario 1/10 |
| Inventario enorme em monorepo estoura contexto | teto de itens + `TRUNCATED`; leitura so dos itens relevantes; lotes de candidatas |
| Template de irma muda e quebra o modo de revisao | regras de cabecalho derivadas do template instalado (Decision 5); exit 4 quando a irma falta |
| `secrets-filter.sh` nao detecta segredo curto (piso documentado, issue #169) | defesa a montante: arquivos `secret-bearing` nunca lidos; scan e segunda camada |
| Retomada reapresenta candidatas descartadas | limitacao aceita por FR-011 (sem ledger); documentada em Gotchas |
| Colisao de trigger com `briefing`/`constitution` | `description` com "NAO use" + Scenario 16 |
| Emenda de constitution altera texto ratificado | Edit somente de insercao; `cmp` do trecho anterior no teste da fixture `legacy` (Scenario 6) |
| Injecao indireta via README/docs leva o modelo a executar comando (LLM01/ASI01, gate owasp F1) | SKILL.md restringe o uso de Bash a invocar os scripts `init-*.sh`, `requirement-coverage.sh` e `secrets-filter.sh` (nunca comando derivado de texto lido); a escrita ja e confinada pelo guarda deterministico; Gotcha dedicado; Scenario 14 |
| Segredo em arquivo nao classificado `secret-bearing` (ex.: `docker-compose.yml`) ecoado na conversa ou no resumo (LLM02, gate owasp F2) | regra: inventario e resumo citam caminho e nome de chave, nunca valor de configuracao; `scan` cobre so documentos gravados, por isso a regra vale tambem para o texto da conversa |
| Prosa hostil copiada para spec reconstituida vira "requisito" consumido por `plan`/`converge` depois (ASI06, gate owasp F3) | spec redige comportamento com evidencia `(fonte: ...)`, sem copiar trechos imperativos dos artefatos; no modo interativo a spec e exibida para aprovacao antes de gravar; marcador `cstk-init:reconstructed` sinaliza a origem |
| Guarda de escrita meramente procedural: sob injecao indireta o modelo pode escrever sem `init-guard.sh check` (security CHK002; dec-026 D1=c, FR-026) | risco residual ACEITO e declarado no SKILL.md (Gotchas) e aqui; mitigacoes parciais: escrita confinada pelo fluxo `check` -> Write/Edit -> `scan` -> `lint`, Bash restrito aos scripts do toolkit, Scenario 14; hook `PreToolUse` `Write\|Edit` em feature futura |
| Scanner de segredos ausente deixaria documentos sem verificacao (security CHK010) | fail-closed (FR-027): `init-guard.sh scan --probe` antes da primeira escrita, exit 4 e zero escritas; Scenario 18 |
| Troca de symlink entre `init-guard.sh check` e a escrita (TOCTOU, gate owasp F4) | risco baixo (ameaca local, mesmo usuario); `check` imediatamente antes de cada Write/Edit e `scan` + `lint` depois; aceito |

## Complexity Tracking

Nenhuma violacao de constitution a justificar. Registro do uso de dependencia opcional
(carve-out 1.1.0, condicao c): `git` em `plugins/cstk/skills/cstk-init/scripts/init-probe.sh`
(unico arquivo), fallback `VCS\tnone` coberto por `tests/test_init-probe.sh` (Scenario 3).

## Re-check pos-design

| Principio | Status | Observacao apos Phase 1 |
|-----------|--------|-------------------------|
| I | PASS | design nao altera contrato de skill existente; descricoes de irmas so com nota no CHANGELOG |
| II | PASS | seis scripts com teste 1:1; nenhum usa `jq`; `secrets-filter.sh check` e POSIX (o `jq` daquele arquivo fica no subcomando `for-backup`, nao usado) |
| III | PASS | conteudo pesado em `references/`/`templates/`; templates das irmas referenciados, nao colados |
| IV | PASS | nenhum script ou passo do fluxo acessa rede |
| V | PASS | seis scripts e o minimo para tornar FR-008/010/011/016/019 verificaveis; nenhuma camada extra |
| VI | PASS | contratos novos marcados `[PROPOSTA]`; todos os paths e linhas citados neste plano foram conferidos no repositorio em 2026-11-14 |
