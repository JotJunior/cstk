# Implementation Plan — model-selector

**Feature**: `model-selector`
**Date**: 2026-05-21
**Spec**: [`spec.md`](spec.md)
**Status**: Draft (Phase 1 complete; aguarda /checklist e /create-tasks)

---

## Summary

Adicionar nova skill toolkit `model-selector` em
`global/skills/model-selector/` que recebe texto descritivo de uma
tarefa (input natural ou contexto estruturado de orquestrador) e
emite, via stdout markdown, uma **sugestao auditavel de modelo**
(`haiku|sonnet|opus|manter-atual`) com score 0..2, lista de sinais
detectados e justificativa. A skill **nunca troca o modelo** e **nao
chama `/model`** — apenas sugere. Orquestradores autonomos
(`agente-00c`, `feature-00c`) integram a sugestao registrando uma
`DecisaoDeAceite` em `state.decisoes` via runtime compartilhado e
acumulando contadores em `metricas_acumuladas.model_selector` do
proprio `state.json`. Um script `scripts/report.sh` agrega leituras
do estado e emite tabela markdown — unico ponto onde `jq` opcional e
permitido conforme FR-010a (carve-out POSIX 1.1.0) com fallback POSIX
puro em `awk` testado.

**Abordagem tecnica resumida da Phase 0 (research.md):**
- **Catalogo de sinais**: 15 entradas MVP em
  `references/sinais.md` (tabela markdown 3 colunas), parseado por
  `awk` em modo streaming (Decision 1).
- **Match de input**: tokenizacao via `tr` + `grep -Fxq` (fixed
  string exact line) contra catalogo lowercased (Decision 2).
- **Spawn de subagente**: **NAO e responsabilidade da skill** —
  orquestrador consome sugestao e adapta ao mecanismo local
  (Decision 3, FR-006).
- **Output**: markdown estruturado com 4 secoes fixas (Decision 4) —
  rotulo abstrato dec-005.
- **`jq` opcional**: confinado a `scripts/report.sh` com fallback
  `awk` linha-a-linha; teste dedicado verifica equivalencia
  (Decision 5, FR-010a).
- **State.json**: novo objeto `metricas_acumuladas.model_selector`
  (Decision 6) + Decisoes auditaveis em `state.decisoes`.
- **Fail-safe**: input <3 tokens → `manter-atual` score 0
  (Decision 7).
- **10 testes shellscript** em `tests/cstk/test_model_selector_*.sh`
  cobrindo cada SC e FR critico (Decision 8).
- **Tier-mapping fixo** para alternativa (Decision 9, edge case 3).

---

## Technical Context

| Campo | Valor |
|-------|-------|
| Linguagem | POSIX sh (shebang `#!/bin/sh`, `set -eu`, sem bash-isms) + Markdown (catalogo + SKILL.md) |
| Build | Nenhum — skill distribuida via `cp -r` (modelo canonico do toolkit) |
| Test | `tests/cstk/test_model_selector_*.sh` integrado em `tests/run.sh` (suite shell-scripts-tests) |
| Storage | Nenhum proprio — extensao do `state.json` ja gerenciado pelo runtime `agente-00c-runtime` |
| Deps obrigatorias | `find`, `grep`, `awk`, `sed`, `tr`, `cut`, `sort`, `printf`, `cat`, `date`, `mkdir` (todas POSIX canonicas) |
| Deps opcionais | `jq` (>=1.6 — confinado em `scripts/report.sh`, conformidade Constitution II amendment 1.1.0; ver dec-008 + Decision 5 do research). **Justificativa do `>=1.6`**: pipe operator (`\|`), funcoes de objeto (`from_entries`, `to_entries`) e `--arg`/`--argjson` usadas no agregador estao estaveis desde 1.5; 1.6 e a versao amplamente disponivel em distros LTS (Ubuntu 18.04+, Debian 10+, macOS Homebrew). Versoes <1.5 nao sao suportadas (resolve CHK011). |
| Platform | macOS + Linux (BSD coreutils + GNU coreutils — ambos suportados explicitamente per CHK005 resolvido em onda-006). `date` portavel apenas para output ISO-8601 (`date -u +%Y-%m-%dT%H:%M:%SZ` — POSIX comum). |
| Project Type | skill toolkit single-layer (sem backend, sem frontend, sem broker, sem DB) |
| Performance Goals | Classificacao: <50ms p95 (**meta interna nao-bloqueante**, nao e SC formal — resolve CHK015). Relatorio: <500ms para 20 execucoes (SC-003, hardware-base M1/M2 ou Linux x86_64 modesto, 5 runs medianos — resolve CHK016/CHK017). |
| Constraints | `SKILL.md` <200 linhas (SC-004); zero rede em qualquer caminho de execucao (SC-005, Principio IV); zero falsos positivos haiku em verbos de design (SC-006). |
| Scale/Scope | Catalogo MVP 15 sinais; operador estende localmente sem limite hard. Sugestoes per-execucao tipicas: 0-50 (escala com ondas do feature-00c). |
| Observability | stdout markdown + exit codes documentados (contracts/skill-io.md). Sem telemetria — Principio IV. |
| Security | Input rejeita null-byte; sem `eval`; sem fetch HTTP; sem `find` sobre paths derivados do input. |

Zero `NEEDS CLARIFICATION` remanescentes — todos os campos preenchidos
ou explicitamente N/A.

---

## Constitution Check

**Constitution version**: 1.1.0 (`docs/constitution.md`, ratificada
2026-04-20, ultimo amendment 2026-04-24).

*GATE: Deve passar antes do Phase 0. Re-checar apos Phase 1 (ver §
"Re-check pos Phase 1" abaixo).*

| Principio | Status | Notas |
|-----------|--------|-------|
| **I. SDD recursivo** (NON-NEGOTIABLE) | PASS | Feature segue o pipeline completo: briefing pre-existente + constitution v1.1.0 + spec + clarify (8 decisoes auditadas dec-001..dec-008) + plan (este documento) + checklist + create-tasks pendentes. `docs/specs/model-selector/` ja contem spec.md e este plan.md. Bump no CHANGELOG ao concluir. |
| **II. POSIX sh puro, zero deps** (NON-NEGOTIABLE) | PASS com carve-out | Classificador (`scripts/classify.sh`) e catalogo (`references/sinais.md`) sao POSIX puro estrito — sem `jq`, sem `ripgrep`, sem bash-isms. Carve-out 1.1.0 INVOCADO **apenas para `jq` opcional em `scripts/report.sh`** conforme FR-010a — conformidade demonstrada abaixo. Bash-isms vetados em qualquer arquivo (regra preservada). Ripgrep/fd/bats permanecem VETADOS inclusive como deps opcionais (L97-98). |
| **III. Skill canonica: progressive disclosure + Gotchas + description-como-trigger** | PASS | `SKILL.md` <200 linhas (SC-004) — conteudo pesado em `references/sinais.md` (catalogo) e `examples/` (good vs bad). Gotchas obrigatorios listados em FR-013 (cinco gotchas: a-e). `description` em frontmatter sera escrito como trigger condition ("Use quando X / NAO use quando Y") — verificavel em `/checklist`. |
| **IV. Zero coleta remota** (NON-NEGOTIABLE) | PASS | Skill nao faz HTTP/IPC em nenhum caminho. FR-016 explicito. SC-005 verificavel via `grep -rn 'curl\|wget\|http' global/skills/model-selector/` (Scenario 10 do quickstart). Skill nao consulta API de modelo, nao consulta estado externo do harness (Decision 3 + Decision 9 do research). |
| **V. Profundidade > adocao** | PASS | Feature reduz retrabalho real do autor (custo Opus em chamadas mecanicas) — alinhamento direto com SC-002 (>=30% sugestoes baratas, zero retro-execucoes). Rotulo abstrato (dec-005) prioriza profundidade sobre perseguir "modelo do mes". Nenhuma feature "anunciavel" sem valor — toda decisao ancorada em FR mensuravel. |

### Conformidade detalhada com Constitution II amendment 1.1.0 (FR-010a)

O carve-out de `jq` opcional para `scripts/report.sh` satisfaz as **3
condicoes cumulativas** do amendment 1.1.0:

| Condicao | Como satisfeita | Verificavel via |
|----------|-----------------|-----------------|
| (a) Uso genuinamente opcional com fallback graceful documentado E verificavel | Fallback POSIX puro em `awk` linha-a-linha produz MESMO output da tabela markdown. Caminho testado em `tests/cstk/test_report_without_jq.sh` que mascara `jq` via `PATH` minimizado (Scenario 8 do quickstart). | `test_report_without_jq.sh` |
| (b) Codigo que referencia a dep confinado em UM unico arquivo identificavel | Apenas `scripts/report.sh` cita `jq`. `SKILL.md`, `references/`, `scripts/classify.sh` e demais arquivos NAO referenciam `jq`. | `grep -rn '\bjq\b' global/skills/model-selector/` retorna 1 arquivo unico (Scenario 9 do quickstart) + `test_report_jq_confinement.sh` |
| (c) Dep declarada explicitamente na documentacao da feature que a introduz | Declaracao em **3 lugares**: (1) `spec.md` §FR-010a (texto integral do carve-out); (2) este `plan.md` (Technical Context "Deps opcionais" + esta tabela); (3) `research.md` §Decision 5 (Rationale + Alternatives). | leitura humana |

**Gate**: **PASS**. Prosseguir com Phase 0/Phase 1.

---

## Project Structure

### Documentation (this feature)

```
docs/specs/model-selector/
├── spec.md                       # User stories, FRs, success criteria + Clarifications
├── plan.md                       # Este documento
├── research.md                   # Phase 0 — 9 decisoes tecnicas
├── data-model.md                 # Phase 1 — entidades + extensao state.json
├── contracts/
│   └── skill-io.md               # Contrato canonico de I/O da skill + report.sh
├── quickstart.md                 # Phase 1 — 11 cenarios E2E
└── tasks.md                      # (criado por /create-tasks — pendente)
```

### Source code (mudancas no projeto-alvo)

```
global/skills/model-selector/                  # NOVO diretorio inteiro
├── SKILL.md                                   # NOVO: <200 linhas, frontmatter trigger, gotchas
├── references/
│   └── sinais.md                              # NOVO: catalogo 15 sinais MVP (5 por faixa)
├── scripts/
│   ├── classify.sh                            # NOVO: POSIX puro (sem jq) — classificador
│   └── report.sh                              # NOVO: jq opcional + fallback awk
└── examples/                                  # NOVO (opcional MVP):
    ├── good-haiku.md                          # exemplo input → sugestao haiku
    ├── good-sonnet.md                         # exemplo input → sugestao sonnet
    └── good-opus.md                           # exemplo input → sugestao manter-atual

tests/cstk/                                    # arquivos adicionados a suite existente
├── test_model_selector_faixa_rasa.sh          # NOVO (SC-001)
├── test_model_selector_faixa_media.sh         # NOVO (SC-001)
├── test_model_selector_faixa_profunda.sh      # NOVO (SC-001, SC-006)
├── test_model_selector_ambiguo.sh             # NOVO (FR-005)
├── test_model_selector_input_vazio.sh         # NOVO (Decision 7)
├── test_model_selector_zero_rede.sh           # NOVO (SC-005)
├── test_model_selector_skill_lines.sh         # NOVO (SC-004)
├── test_report_without_jq.sh                  # NOVO (FR-010a (a))
├── test_report_jq_confinement.sh              # NOVO (FR-010a (b))
└── test_report_performance.sh                 # NOVO (SC-003)

tests/fixtures/
└── state-dirs-20/                             # NOVO: fixture com 20 state.json mockados (SC-003)
    ├── feature-a/state.json
    ├── feature-b/state.json
    └── ... (18 mais)

CHANGELOG.md                                   # MODIFICAR: entrada MINOR (nova skill)
```

**Mudancas em arquivos existentes**:
- `CHANGELOG.md`: entrada `[MINOR] Add model-selector skill (FR-010a
  invokes optional-deps carve-out for jq in scripts/report.sh)`.
- `global/skills/agente-00c-runtime/scripts/state-validate.sh`:
  **NENHUMA mudanca exigida** — o validador ja aceita campos novos
  sob `metricas_acumuladas.*` (compat retroativa do schema). Tarefa
  `/create-tasks` deve confirmar este ponto empiricamente.

**Structure Decision**: skill toolkit standalone em
`global/skills/model-selector/`, seguindo o padrao canonico de
outras skills do repo (`clarify`, `plan`, `analyze`, etc.) — diretorio
proprio com `SKILL.md` + subpastas `references/`, `scripts/`,
`examples/`. Zero acoplamento com outras skills exceto leitura
read-only do schema de `state.json` (lido por `report.sh`) cujo
contrato e gerenciado pelo runtime `agente-00c-runtime`. A skill
**nao depende de runtime instalado** para o caminho `classify.sh`
(somente o `report.sh` se beneficia do state.json gerado pelo
runtime, e ainda assim funciona em qualquer JSON com a chave
`metricas_acumuladas.model_selector`).

---

## Convencoes de Borda

**N/A — single-layer**. A feature e uma skill toolkit POSIX pura
sem fronteira backend↔frontend, sem DB com mapper, sem broker com
consumer. Toda a comunicacao acontece via stdout markdown / stdin
texto / exit codes POSIX, em uma unica camada.

A unica "borda" relevante e a fronteira **skill ↔ state.json
gerenciado pelo runtime**, coberta integralmente pelo contrato ja
existente do `agente-00c-runtime` (campos JSON sob
`metricas_acumuladas` sao tolerantes a chaves novas). Sem case-style
divergente — todos os campos do state.json sao `snake_case`
canonicos do runtime; novos campos introduzidos por esta feature
(`model_selector`, `sugestoes_total`, `por_modelo_sugerido`,
`por_resultado`, `ultima_invocacao_iso`) mantem `snake_case`.

---

## Re-check pos Phase 1 (gate final)

Apos producao de `research.md` + `data-model.md` + `contracts/` +
`quickstart.md`, re-checagem dos principios:

| Principio | Status pos-design | Notas |
|-----------|-------------------|-------|
| I. SDD recursivo | PASS | Todos os artefatos do Phase 1 produzidos sob `docs/specs/model-selector/`. /checklist e /create-tasks pendentes (proxima onda). |
| II. POSIX puro + carve-out | PASS | Design confirma confinamento de `jq` em UM arquivo (`scripts/report.sh`). `classify.sh`, `references/sinais.md` e demais arquivos sao POSIX puro. Bash-isms NAO introduzidos (verificavel via shellcheck `-s sh` em `/checklist`). |
| III. Skill canonica | PASS | Estrutura de diretorios projetada em §Project Structure casa com o padrao das outras skills do repo. `SKILL.md` planejado para <200 linhas com Gotchas obrigatorios (FR-013) + description-trigger (FR-014). |
| IV. Zero coleta remota | PASS | Design nao introduz nenhuma chamada de rede. Decision 9 do research confirma que detecao de disponibilidade do modelo NAO acontece em runtime (skill emite tier-mapping fixo, orquestrador decide). |
| V. Profundidade > adocao | PASS | Phase 1 nao adicionou caracteristicas "vistosas". Tudo o que esta em design tem justificativa direta em FR ou SC mensuravel. |

**Gate final**: **PASS**. Phase 2 (checklist + tasks) liberada.

---

## Complexity Tracking

> Preencher APENAS se Constitution Check tem violacoes que precisam
> justificativa.

**Nao ha violacoes em Phase 1**. A unica excecao disciplinada
invocada e o **carve-out 1.1.0** para `jq` opcional em
`scripts/report.sh` — que NAO e violacao, mas mecanismo formal de
conformidade introduzido pelo amendment 1.1.0 da constitution
(reconhecido explicitamente no Decision Framework item 4: "Subsecoes
de carve-out dentro de um Principio (...) sao mecanismo valido de
conformidade quando precedidas por amendment com MINOR bump —
representam disciplina explicita do principio, nao opt-out").

Conformidade demonstrada na tabela da §Constitution Check acima e em
tres lugares concretos da especificacao + plano + research, conforme
exigido pela condicao (c) do amendment.

| Item | Por Que Necessario | Alternativa Simples Rejeitada Porque |
|------|--------------------|--------------------------------------|
| `jq` opcional em `scripts/report.sh` (FR-010a) | Parsing JSON aninhado (`state.decisoes[]`) com `awk` puro e fragil para nested arrays of objects — risco real de bug silencioso ao agregar contadores. | (a) Eliminar relatorio (FR-012) — viola User Story 3. (b) Forcar POSIX puro estrito sem `jq` — funcional mas com risco operacional documentado em Decision 5 do research. (c) Tornar `jq` obrigatorio — viola Principio II MUST (carve-out exige fallback). |

---

## Artefatos

| Arquivo | Status |
|---------|--------|
| `docs/specs/model-selector/spec.md` | Pre-existente (Clarified) |
| `docs/specs/model-selector/plan.md` | Criado (este documento) |
| `docs/specs/model-selector/research.md` | Criado (9 decisoes tecnicas) |
| `docs/specs/model-selector/data-model.md` | Criado (3 entidades + extensao state.json) |
| `docs/specs/model-selector/contracts/skill-io.md` | Criado (I/O da skill + report.sh) |
| `docs/specs/model-selector/quickstart.md` | Criado (11 cenarios) |
| `docs/specs/model-selector/tasks.md` | Pendente — proximo /create-tasks |

---

## Proximos Passos

1. **`/checklist`** — gerar quality gate antes de implementar:
   shellcheck `-s sh`, skill anatomy check (`SKILL.md` < 200 linhas,
   Gotchas presentes, description-trigger), grep de confinamento de
   `jq`, grep de zero-rede.
2. **`/create-tasks`** — decompor este plano em backlog executavel:
   tarefas tipicamente em fases (catalogo, classificador, output,
   integracao state.json, report.sh com fallback, testes, doc).
3. **`/analyze`** — apos `tasks.md` existir, validar consistencia
   cross-artifact (spec ↔ plan ↔ tasks ↔ constitution).
