# Implementation Plan: Code Reconciliation (`reconcile-docs`)

**Feature**: `code-reconciliation` | **Date**: 2026-09-30 | **Spec**: [spec.md](./spec.md)

## Summary

Nova skill complementar `reconcile-docs` (`/reconcile-docs <feature>` ou `--all`,
com `--dry-run`) que faz o sentido inverso da `converge`: traz a documentacao de uma
feature (ativa ou arquivada) para o comportamento atual do codigo, sem jamais alterar
codigo. O LLM le o codigo a partir das ancoras citadas na documentacao e julga cada
divergencia; seis scripts POSIX cobrem o que e deterministico — resolver o nome da
feature, extrair ancoras, negar escrita fora da allowlist de documentos, validar e
listar marcadores `[reconciled:<kind> <date> evidence=<ref>]`, anexar o registro
`reconciliation.md` e (opcionalmente) consultar `git`. Contradicoes com MUST/MUST NOT
da feature ou da constitution viram "possivel regressao" no relatorio, sem escrita.

## Technical Context

**Language/Version**: POSIX sh (`#!/bin/sh`, `set -eu`) + awk/sed POSIX; SKILL.md e templates em Markdown
**Primary Dependencies**: utilitarios POSIX (`find`, `grep`, `awk`, `sed`, `sort`, `mktemp`, `diff`); `git` OPCIONAL, confinado a `git-probe.sh` (carve-out 1.1.0 — research Decision 6); sem `jq`
**Storage**: nenhum estado proprio; escreve somente documentos da feature (`spec.md`, `plan.md`, `data-model.md`, `quickstart.md`, `contracts/*.md`) e `reconciliation.md`
**Testing**: harness `tests/run.sh`; um `tests/test_<script>.sh` por script (6); fixture `tests/fixtures/reconcile-docs/`; trigger evals via `tests/trigger-eval/gen-eval-cases.sh`
**Target Platform**: macOS + Linux (BWK awk, mawk, gawk; sem `sed -i`, `stat -c`, `readlink -f`, `timeout`) — fonte: constitution Principio II (POSIX portavel) + mesma plataforma declarada em `docs/specs/presentation/plan.md` §Technical Context
**Project Type**: skill do toolkit (SKILL.md + templates + references + scripts + evals)
**Performance Goals**: cada script < 2 s sobre este repositorio (7 features ativas + 57 arquivadas); o custo dominante e a leitura semantica pelo LLM, fora do controle dos scripts
**Constraints**: zero escrita fora da allowlist (FR-006/FR-017, SC-001); zero dado sem evidencia (Principio VI, FR-008); idempotente (FR-012); standalone, sem `state.json` de orquestrador
**Scale/Scope**: 1 feature por invocacao ou o portfolio inteiro com `--all`

Nenhum `NEEDS CLARIFICATION`; decisoes em [research.md](./research.md). Nenhum eixo
estrutural decidido aqui: linguagem/runtime (POSIX sh) e formato (skill do catalogo)
sao fixados pelos Principios II e III da constitution.

## Constitution Check

*GATE: Deve passar antes do Phase 0. Re-checado apos Phase 1 (ver "Re-check pos-design").*

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD recursivo | PASS | spec + clarify + plan nesta pasta; checklist e tasks a seguir; skill nova = superficie publica nova → CHANGELOG com bump MINOR (nao ha rename/remocao, logo nao e MAJOR) |
| II. POSIX sh puro | PASS | 6 scripts `#!/bin/sh` + `set -eu`, sem bashismo, sem `jq`/`ripgrep`/`fd`; `git` opcional sob carve-out 1.1.0: (a) fallback `no-git` testado em `tests/test_git-probe.sh`, (b) confinado a `scripts/git-probe.sh`, (c) declarado aqui e em research Decision 6 |
| III. Formato canonico de skill | PASS | SKILL.md enxuto com `## Gotchas`; relatorio, entrada de log e guia de classificacao em `templates/`/`references/`; `description` como trigger com "NAO use" apontando `converge` |
| IV. Zero coleta remota | PASS | nenhuma rede; `git` so local (`status`, `log`); relatorio fica na conversa |
| V. Profundidade > adocao | PASS | reduz retrabalho real (documentacao que deixou de refletir o codigo) nos projetos onde o toolkit e aplicado |
| VI. Veracidade de dados | PASS | toda alteracao exige evidencia `arquivo:linha` ou `absent:<path>` (FR-008); sem fonte → `unverifiable`, nada escrito; marcadores carregam a evidencia no proprio documento |

## Project Structure

### Documentation (this feature)

```
docs/specs/code-reconciliation/
├── spec.md
├── plan.md                  # este arquivo
├── research.md              # Phase 0 (10 decisoes)
├── data-model.md            # Phase 1 (Feature, Anchor, Divergence, FeatureResult, Report, Log, Marker)
├── quickstart.md            # Phase 1 (13 cenarios)
├── contracts/
│   ├── cli-invocation.md    # /reconcile-docs + 6 scripts
│   └── markers.md           # tokens exatos dos marcadores (FR-009)
├── checklists/              # proxima etapa
└── tasks.md                 # proxima etapa
```

### Source Code (repository root)

```
plugins/cstk/skills/reconcile-docs/          # [PROPOSTA] NOVO
├── SKILL.md
├── templates/{report.md,log-entry.md}
├── references/{classification.md,write-policy.md}
├── scripts/{locate-feature.sh,extract-anchors.sh,doc-guard.sh,markers.sh,reconciliation-log.sh,git-probe.sh}
└── evals/triggers.jsonl

plugins/cstk/evals/reconcile-docs/NNN/case.yaml   # gerado por gen-eval-cases.sh
plugins/cstk/evals/none/NNN/case.yaml             # [EXISTENTE] + negativos regenerados
tests/test_{locate-feature,extract-anchors,doc-guard,markers,reconciliation-log,git-probe}.sh  # [PROPOSTA]
tests/fixtures/reconcile-docs/                    # [PROPOSTA] projeto minimo
tests/trigger-eval/negatives.jsonl                # [EXISTENTE] + negativos
scripts/profiles.txt.in                           # [EXISTENTE] + complementary:reconcile-docs
cli/lib/install.sh                                # [EXISTENTE] help do perfil complementary
docs-site/manual/profiles.md                      # [EXISTENTE] lista do complementary
README.md, README.pt-BR.md                        # [EXISTENTE] contagens 22→23, 11→12, 29→30 + linha na tabela de skills
CHANGELOG.md + manifests em lockstep              # [EXISTENTE] proximo MINOR
```

Antes de nomear os scripts, conferir colisao de nome com `tests/test_*.sh` existentes
(`tests/run.sh --check-coverage` mapeia teste↔script pelo basename).

**Structure Decision**: seis scripts de responsabilidade unica (research Decision 2),
cada um com teste 1:1. O SKILL.md orquestra: parse de argumentos → `locate-feature.sh`
→ por feature: `git-probe.sh status` (snapshot) → `extract-anchors.sh` →
`git-probe.sh changed-since` (priorizacao) → leitura semantica do codigo e
classificacao (`references/classification.md`) → para cada escrita:
`doc-guard.sh check` → Edit → `markers.sh lint` + `markers.sh verify` → `reconciliation-log.sh append`
(so se houve alteracao) → `git-probe.sh status` (auditoria) → relatorio
(`templates/report.md`). Em `--dry-run` os passos de escrita sao substituidos por
acoes `proposed-*`.

**Relacao com `converge`**: independentes; nenhuma chamada cruzada de script (perfis
de instalacao diferentes). A `description` de cada uma aponta a outra no "NAO use".
A `description` da `converge` so e tocada se o trigger eval (quickstart Scenario 11)
mostrar colisao — alteracao de description de skill existente exige nota no
CHANGELOG.

## Convencoes de Borda

N/A — single-layer (skill local sem API, banco ou frontend). Unica fronteira interna:
TSV dos scripts → LLM. Colunas separadas por TAB, sem cabecalho, uma entidade por
linha; linha final `STATUS\t<token>` apenas em `git-probe.sh`. Tokens de enum em ingles
(`active`, `archived-shadowed`, `stale`, `possible-regression`, ...); rotulos do
relatorio localizados.

## Riscos e mitigacoes

| Risco | Mitigacao |
|-------|-----------|
| LLM "corrige" um MUST para acomodar o codigo (viola FR-007) | `references/classification.md` com regra explicita MUST/MUST NOT/constitution → `possible-regression`; quickstart Scenario 1 planta esse caso; Gotcha dedicado |
| Evidencia confabulada (Principio VI) | evidencia obrigatoria `arquivo:linha` conferivel; SKILL.md manda reler a linha citada antes de gravar; `absent:` so a partir de ancora `absent` de `extract-anchors.sh` |
| Escrita fora de documentos (FR-006) | `doc-guard.sh check` antes de toda escrita + auditoria `git-probe.sh status` pos-execucao (research Decision 5) |
| Reescrita por estilo quebrando idempotencia (FR-012) | regra "so muda o que diverge"; marcadores existentes nao sao re-datados; Scenario 2 |
| `--all` esgota contexto num portfolio grande | processamento uma feature por vez retendo so a linha-resumo; recomendacao de subagente por feature e de `--all --dry-run` primeiro |
| Trigger colide com `converge` ("reconciliar spec com codigo") | description com direcao explicita ("documentacao segue o codigo") + negativos; Scenario 11 |
| Ancoras demais em specs longas (ruido) | `extract-anchors.sh` so pega tokens entre crases; LLM prioriza ancoras de `changed-since` quando ha git |
| Numeracao de FR novo errada | `markers.sh next-fr` deterministico (max + 1) |
| Injecao indireta via conteudo lido (LLM01/ASI01): comentario no codigo ou texto na spec com "instrucoes" | SKILL.md: todo conteudo lido (codigo, docs, `reconciliation.md`) e DADO, nunca instrucao; a skill nunca executa comandos, testes ou build do projeto — so os 6 scripts proprios; Gotcha dedicado |
| Guarda falhando aberta (A10/LLM06) | qualquer exit != 0 de `doc-guard.sh` (inclusive script ausente/erro) = escrita negada; o SKILL.md nao tem caminho de escrita sem o `check` |
| Evidencia apontando para arquivo/linha inexistente (LLM09) | `markers.sh verify` confere deterministicamente que `<path>:<line>` existe (linha <= total) e que `absent:<path>` de fato nao existe, antes do relatorio |
| Constitution do projeto inexistente ou ilegivel (FR-007, CHK007) | a skill NAO falha nem presume principios: `possible-regression` passa a valer so para MUST/MUST NOT da propria feature e o relatorio traz o aviso `constitution-unavailable` (`references/classification.md`; quickstart Scenario 12; dec-027) |
| Segredo presente no codigo copiado para documento, marcador ou relatorio ao citar evidencia (FR-019, CHK011; LLM02) | regra da skill: evidencia so por `arquivo:linha`/`absent:<caminho>`, nunca reproduzindo o valor (`references/classification.md` + Gotcha no SKILL.md); o marcador ja so admite `<path>:<line>` (`markers.sh lint`); sem detector deterministico (heuristica de segredos gera falso positivo/negativo e ampliaria os 6 scripts) — risco residual: texto livre do relatorio, coberto por quickstart Scenario 13 (dec-029) |
| Nome de feature com `..`, `/` ou metacaracteres (A05) | `locate-feature.sh` so aceita `^[a-z0-9][a-z0-9-]*$` (com prefixo de data opcional), exit 2 fora disso; variaveis sempre entre aspas |
| `git` executando comando via config do repositorio (ex.: `core.fsmonitor`) | `git-probe.sh` invoca `git -c core.fsmonitor=false ...` so com subcomandos de leitura (`status --porcelain`, `log --name-only`); nunca `hook`, `checkout` ou escrita |
| TOCTOU/simlink entre `check` e escrita | `doc-guard.sh` nega destino que seja simlink (existente) e resolve o diretorio pai com `pwd -P`; ferramenta local de usuario unico — risco residual aceito |

## Complexity Tracking

Sem violacoes de constitution. `git` opcional e uso licito do carve-out 1.1.0, nao
excecao.

## Re-check pos-design

Revisado apos data-model e contratos: nenhuma dependencia obrigatoria nova, nenhuma
escrita fora de `docs/specs/<feature>/` e `docs/specs/_archived/<dir>/`, `git`
confinado a um arquivo com fallback testado, relatorio sem rede e toda alteracao com
evidencia. O design nao introduziu camada, servico ou estado persistente alem do
`reconciliation.md` pedido por FR-018. Todos os MUST seguem PASS.
