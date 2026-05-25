# Implementation Plan — model-routing-por-onda

**Spec**: [spec.md](./spec.md) (Status: Clarified) · **Created**: 2026-05-24

## Summary

Tornar o model-routing **aplicado de verdade** (não audit-only) e movê-lo da
fronteira de spawn de clarify para a **fronteira de onda**. Mecanismo primário: um
mapa determinístico fase→modelo lido no command/resume, que passa `model=<chosen>`
ao spawn do orquestrador. Camada secundária: refino por `model-selector` em ondas
`execute-task` (com catálogo expandido). Revoga a cláusula audit-only do FR-017 da
feature original (BREAKING → MAJOR).

## Technical Context

| Campo | Valor |
|---|---|
| Linguagem | POSIX sh (helpers) + Markdown (agents/commands) |
| Runtime alvo | `agente-00c-runtime` (helpers) + orquestradores + commands |
| Dependências | reuso de `state-decisions.sh`, `state-ondas.sh`, `model-routing.sh`, `model-routing-report.sh`, `state-decisions-reconcile.sh`; `jq` já presente no runtime (pré-existente) |
| Storage | `state.json` transacional (Decisões); arquivos versionados `references/*.txt`/`*.md` |
| Testes | `tests/run.sh` (harness POSIX); `tests/cstk/` para cli/lib, `tests/` para skills scripts |
| Plataforma | qualquer POSIX (macOS/Linux) |
| Tool Agent | aceita `model=sonnet\|opus\|haiku` (precedência sobre frontmatter) — habilitador da feature |

NEEDS CLARIFICATION restantes: **0** (resolvidos na spec + research.md).

## Constitution Check

*GATE: passou antes do Phase 0; re-checado pós-design.*

| Princípio | Status | Notas |
|---|---|---|
| I. SDD recursivo | PASS | feature segue spec→plan→tasks |
| II. POSIX sh puro | PASS | novos subcomandos (`wave-select`, `phase-model-lookup`) são POSIX-puros; lookup do mapa sem jq. `jq` usado por `model-routing.sh` é **pré-existente** (runtime manipula state.json) — não introduzido aqui (ver Complexity Tracking) |
| III. Formato de skill | PASS | expansão do catálogo do model-selector preserva formato de tabela; SKILL.md/Gotchas afetados só se necessário |
| IV. Zero coleta remota | PASS | model-selector permanece heurística local; nenhuma billing API |
| V. Profundidade > adoção | PASS | refino de feature existente, reduz custo/retrabalho real |

## Project Structure

### Documentação (feature)
```
docs/specs/model-routing-por-onda/
├── spec.md          (4 stories, 19 FRs, 8 SCs)
├── plan.md          (este)
├── research.md      (6 decisions)
├── data-model.md    (5 entidades + state transitions)
├── contracts/
│   └── wave-select.md
└── quickstart.md    (10 cenários)
```

### Código (pontos de edição reais — verificados)
```
global/skills/agente-00c-runtime/
├── scripts/model-routing.sh           # + subcomandos wave-select, phase-model-lookup; passo 8 aplica model
└── references/phase-model-map.txt     # NOVO — mapa fase→modelo (FR-014)

global/skills/model-selector/
└── references/sinais.md               # expandir catálogo (FR-018) + atualizar snippet de validação

global/agents/
├── agente-00c-orchestrator.md         # §5.e.bis passo 8: aplicar model no spawn clarify (FR-003/004)
└── agente-00c-feature-orchestrator.md # seção model-routing equivalente

global/commands/
├── agente-00c.md            # inserir wave-select antes do spawn do orquestrador
├── agente-00c-resume.md     # idem (step 6)
├── feature-00c.md           # idem
└── feature-00c-resume.md    # idem

tests/
├── test_model-routing.sh              # estender: wave-select, phase-model-lookup
├── test_model_selector_*.sh           # atualizar contagem do catálogo expandido
└── fixtures/                          # NOVO corpus rotulado p/ SC-008

CLAUDE.md + CHANGELOG.md + docs/specs/_archived/agente-00c-model-routing/  # FR-017 (BREAKING/MAJOR)
```

## Convenções de Borda

**N/A — single-layer.** A feature é helpers POSIX + instruções markdown
(agents/commands) operando sobre `state.json` local. Não há borda
backend↔frontend, DB↔backend, nem broker↔consumer. A única "fronteira" é
helper↔state.json, cuja fonte da verdade já é o `state.json` transacional
(manipulado por `jq` no runtime existente). Sem case-style cross-layer a declarar.

## Abordagem por story

- **US1 (P1, routing por onda)**: `phase-model-lookup` + `wave-select` + integração
  nos 4 commands. Núcleo da economia. Testes: cenários 1,2,8,9.
- **US2 (P2, clarify spawn)**: editar passo 8 dos orquestradores para aplicar model;
  preservar degradação inline. Testes: derivados do JSON do `invoke`.
- **US4 (P2, catálogo)**: expandir `sinais.md` + corpus + atualizar validação.
  Testes: cenário 10 (SC-008).
- **US3 (P3, auditoria)**: estender `model-routing-report.sh aggregate` + review-task
  §4.5 para sugerido-vs-aplicado. Testes: cenários 3,5,6 (origem rotulada).

Ordem sugerida de implementação: US1 (mapa+wave-select) → US4 (catálogo, habilita
refino) → US2 (clarify) → US3 (auditoria). US4 antes de fechar US1 porque o refino
de US1 (execute-task) depende do catálogo expandido para ter valor.

## Complexity Tracking

| Item | Justificativa |
|---|---|
| Dependência `jq` em `model-routing.sh` | **Pré-existente**, não introduzida por esta feature. Todo o runtime `agente-00c-runtime` manipula `state.json` (JSON) via jq. Os subcomandos NOVOS desta feature (`phase-model-lookup`) são POSIX-puros; `wave-select` reusa os helpers de Decisão existentes (que já dependem de jq). Nenhuma NOVA superfície de dependência criada. Se a constituição vier a exigir confinamento estrito de jq no runtime, é divida pré-existente para uma feature própria, não bloqueia esta. |
| Mudança BREAKING (FR-017 audit-only revogado) | Inerente ao objetivo. Documentada como MAJOR no CHANGELOG; a feature original fica arquivada com nota de superseção. |

## Re-check pós-design

Design não introduziu serviço/camada nova nem dependência nova. Mapa em arquivo
texto + 2 subcomandos POSIX + edição de markdown. Princípios MUST seguem PASS.
</content>
