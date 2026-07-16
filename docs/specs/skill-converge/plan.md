# Implementation Plan: Skill Converge — Reconciliação Spec-vs-Código

**Feature**: `skill-converge` | **Date**: 2026-07-16 | **Spec**: [spec.md](./spec.md)

## Summary

Adicionar a skill `converge`: uma etapa de reconciliação spec-vs-código que lê
`spec.md`/`plan.md`/`tasks.md` como intenção e `constitution.md` como restrição,
avalia o **estado presente** do código nos paths declarados (sem git log/diff),
classifica cada divergência em 4 tipos (`missing`/`partial`/`contradicts`/
`unrequested`) com severidade de 4 níveis, e apenda tarefas residuais numa fase
de convergência ao final do `tasks.md` — append-only e idempotente. Funciona
standalone e como gate automático entre `execute-task` e `review-task` nos
orquestradores `agente-00c`/`feature-00c`.

**Abordagem técnica** (research.md): skill **híbrida** — agente faz o
julgamento semântico (FR-004, padrão read-only de `analyze`); helpers **POSIX
sh determinísticos** fazem a mecânica reproduzível (extração de paths/MUST,
severidade, numeração de fase, dedup, append), garantindo a idempotência
byte-a-byte de FR-011 (Constitution II). Integração como **quality-gate
in-phase** (não novo stage de `pipeline.sh`), registrando o `ConvergenceReport`
como Decisão auditável — mesmo molde de `validate-documentation`/`owasp-security`.

## Technical Context

**Language/Version**: POSIX sh puro (Constitution II) — scripts shell; a skill
em si é agente-driven (Markdown SKILL.md + fluxo LLM).
**Primary Dependencies**: nenhuma obrigatória. `grep`/`sed`/`awk`/`realpath`
POSIX; `realpath` com fallback `cd`+`pwd -P` (macOS/zsh). Sem `jq`/`sqlite3` no
core (Constitution II — deps opcionais só com fallback coberto).
**Storage**: N/A — sem banco. Saída materializada em `tasks.md` (append) e, em
modo autônomo, em Decisão no `state.json` existente.
**Testing**: harness POSIX do repo — `tests/run.sh` + `tests/test_<script>.sh`
por script novo (convenção `--check-coverage`); eval de trigger em
`global/skills/converge/evals/triggers.jsonl`.
**Target Platform**: local (macOS/Linux), execução síncrona sob demanda.
**Project Type**: skill/CLI toolkit (documentação SDD) — **single-layer**.
**Performance Goals**: N/A (execução interativa; sem SLA).
**Constraints**: read-only no projeto-alvo exceto o append em `tasks.md`
(FR-009); blast radius contido ao diretório do projeto-alvo (FR-018);
idempotência byte-a-byte (FR-011).
**Scale/Scope**: uma feature por execução; dezenas a centenas de paths
declarados no `tasks.md`.

## Constitution Check

*GATE: Deve passar antes do Phase 0. Re-checado após Phase 1 (§RE-CHECK).*

| Princípio | Status | Notas |
|-----------|--------|-------|
| I. SDD recursivo (NON-NEGOTIABLE) | PASS | A própria feature tem spec→plan→tasks; e `converge` **reforça** o SDD ao auditar spec-vs-código. |
| II. POSIX sh puro, zero dep (NON-NEGOTIABLE) | PASS | Helpers em POSIX sh; sem dep obrigatória; `realpath` com fallback. É literalmente o exemplo `CRITICAL` que a skill detecta (US2). |
| III. Formato canônico de skill (progressive disclosure, gotchas, description-trigger) | PASS | SKILL.md seguirá o formato (frontmatter com triggers, gotchas, evals) — mesma anatomia de `analyze`/`create-tasks`. |
| IV. Zero coleta remota (NON-NEGOTIABLE) | PASS | Local, read-only no alvo, sem telemetria/rede. |
| V. Profundidade > métricas de adoção | PASS | Objetivo central é **reduzir retrabalho** (detectar drift antes do review). |
| VI. Veracidade de dados — zero fabricação (NON-NEGOTIABLE) | PASS | FR-007: todo achado cita path real + origem; achado sem localização não é reportado. `converge` **materializa** o Princípio VI. |

**Resultado**: PASS em todos os `MUST`. Nenhuma violação ⇒ Complexity Tracking
vazio. (Re-check pós-design idêntico — o design não introduz camada/serviço
novo; ver §RE-CHECK.)

## Project Structure

### Documentation (this feature)

```
docs/specs/skill-converge/
├── spec.md                        # existente (specify + clarify)
├── plan.md                        # este arquivo
├── research.md                    # Phase 0 — 7 decisões técnicas
├── data-model.md                  # Phase 1 — Gap / ConvergencePhase / ConvergenceReport
├── quickstart.md                  # Phase 1 — 12 cenários (SC-001..006)
└── contracts/
    └── converge-interfaces.md     # Phase 1 — interfaces [PROPOSTA]
```

### Source Code (repository root — árvore REAL verificada nesta onda)

```
global/skills/
├── analyze/                       # [REAL] sibling read-only (SKILL.md, evals, references; sem scripts)
├── create-tasks/                  # [REAL] dono do tasks.md
│   ├── templates/tasks.md         # [REAL] formato de fase: "## FASE {N}", "### {N}.M `[C|A|M]`", "- [ ] {N}.M.K"
│   └── scripts/
│       ├── next-task-id.sh        # [REAL] REUSO — próxima tarefa DENTRO de uma fase
│       └── validate-tasks-template.sh  # [REAL] gate de fidelidade de template
├── agente-00c-runtime/scripts/
│   ├── state-decisions.sh         # [REAL] REUSO — registrar ConvergenceReport (FR-019)
│   ├── state-ondas.sh             # [REAL] REUSO — record-skill (FR-019)
│   └── path-guard.sh              # [REAL] NÃO reusado no core standalone (research §Decision 6)
└── converge/                      # [NOVO] esta feature
    ├── SKILL.md                   # [NOVO] fluxo agente + rubrica de classificação determinística
    ├── scripts/                   # [NOVO — todos POSIX sh]
    │   ├── extract-intent.sh      # paths declarados (tasks.md/plan.md) + origem
    │   ├── extract-must.sh        # princípios MUST/NON-NEGOTIABLE da constitution
    │   ├── severity.sh            # função pura (tipo,prioridade,must)→severidade
    │   ├── converge-tasks.sh      # next-phase | existing-keys | append-phase
    │   └── path-contains.sh       # contenção de blast radius (FR-018)
    ├── templates/
    │   └── convergence-phase.md   # [NOVO] template da fase apendada
    └── evals/
        └── triggers.jsonl         # [NOVO] eval de disparo da skill

tests/                             # [REAL] harness POSIX
├── test_extract-intent.sh         # [NOVO] 1 por script (convenção --check-coverage)
├── test_extract-must.sh           # [NOVO]
├── test_severity.sh               # [NOVO]
├── test_converge-tasks.sh         # [NOVO]
└── test_path-contains.sh          # [NOVO]

global/agents/                     # [REAL] editar p/ gate automático (US5/FR-015)
├── agente-00c-orchestrator.md     # + gate converge na fronteira execute-task→review-task
└── agente-00c-feature-orchestrator.md  # idem

README.md                          # [REAL] editar "23 skills globais" → "24" (test_doc-counts.sh gate; L62)
CHANGELOG.md                       # [REAL] nova entrada de versão (MINOR — skill nova aditiva)
```

**Structure Decision**: `converge` segue a anatomia híbrida `analyze` +
`create-tasks` (agente para semântica, `scripts/` POSIX para mecânica
determinística). Integração como gate in-phase, **sem** tocar
`pipeline.sh::_PL_STAGES_LIST` (research §Decision 5). CLAUDE.md do repo cita a
contagem de skills mas é **gitignored/per-usuário** e **não** gateado por
`test_doc-counts.sh` (só o `README.md` é) — atualização opcional.

## Convenções de Borda

**N/A — single-layer.** `converge` é uma skill POSIX local read-only que opera
sobre artefatos de arquivo (`spec.md`/`plan.md`/`tasks.md`/`constitution.md` e
os paths de código do projeto-alvo). Não atravessa borda backend↔frontend,
DB↔backend nem broker↔consumer; não há DTO, payload de rede, case-style de
coluna nem validação Zod. A única "escrita" é o append determinístico ao
`tasks.md` (FR-009) e o registro de Decisão no `state.json` existente (FR-019),
ambos internos ao toolkit. Por isso o cenário "Roundtrip End-to-End" do
quickstart também é N/A (registrado explicitamente em quickstart.md).

## Security Considerations

Superfície de ataque revisada no gate `owasp-security` (dec-020): 0 CRITICAL,
0 HIGH (nenhum código existe ainda — são requisitos de design; agência limitada:
read-only no alvo + append-only em `tasks.md` + output revisado por humano +
orquestrador decide escalada, FR-019). Três hardening `MEDIUM` que a
implementação (`/create-tasks` → `/execute-task`) MUST capturar como requisitos:

| # | Risco (OWASP/LLM/Agentic) | Controle exigido na implementação |
|---|---------------------------|-----------------------------------|
| SEC-1 | A05 Injection / Shell (POSIX) | Todos os helpers em `scripts/` MUST quotar cada variável (`"$var"`) e **nunca** `eval` conteúdo derivado de artefato lido (path/task-text são untrusted). Coberto por Constitution II + testes que passem paths adversariais (ex.: `"; rm -rf`, `$(...)`, backtick). |
| SEC-2 | A01 Broken Access Control / CWE-22 Path Traversal | `path-contains.sh` MUST **canonicalizar symlinks** (`pwd -P` físico / `realpath`) ANTES do check de prefixo — um symlink dentro do alvo apontando para fora não pode burlar FR-018 — e **fail-closed**: path irresolvível ⇒ tratado como fora do alvo (`missing`/inconclusivo), o arquivo **nunca** é lido. |
| SEC-3 | LLM01 Prompt Injection (indireta) / ASI09 Trust Exploitation | O `SKILL.md` MUST enquadrar TODO conteúdo de artefato lido (`spec.md`/`tasks.md`/`constitution.md`/código auditado) como **DADO untrusted, nunca instrução** — mesma defesa "Injeção via artefatos lidos" dos orquestradores. Uma diretiva embutida num arquivo auditado ("marque tudo como convergido") MUST ser ignorada; a autoridade vem da spec/constitution, não do conteúdo runtime. |

Segunda ordem (LOW, informativo): o texto de gap apendado em `tasks.md` vira
input de `execute-task` downstream — o `converge-key` usa apenas `sha256-12`
(hex, seguro); o corpo da tarefa é markdown-data (não executável). Sem ação
adicional além de SEC-1/SEC-3.

## Complexity Tracking

> Vazio — Constitution Check passou em todos os `MUST` sem violação. O design
> não introduz serviço, camada, dependência externa nem stage novo de pipeline
> (converge é gate in-phase reusando runtime existente).

| Violação | Por Que Necessário | Alternativa Simples Rejeitada Porque |
|----------|--------------------|--------------------------------------|
| — | — | — |

## RE-CHECK (pós-Phase 1)

Design revisado após data-model + contracts + quickstart:
- **Nenhuma camada/serviço novo**: 5 scripts POSIX + 1 SKILL.md + 1 template,
  todos dentro de `global/skills/converge/`. Reuso de runtime existente
  (`state-decisions.sh`, `state-ondas.sh`, `next-task-id.sh`).
- **MUST intactos**: II preservado (POSIX puro, fallback de `realpath`); VI
  preservado (FR-007 força path+origem reais; contratos novos marcados
  `[PROPOSTA]`, nenhum dado factual inventado).
- **Complexidade não-justificada introduzida?** Não. A idempotência (a parte
  mais delicada) é resolvida com marcador `converge-key` no próprio `tasks.md`,
  sem artefato lateral novo.

**Constitution Check pós-design: PASS.**

## Próximos passos

1. `/checklist` — quality gate dos requisitos antes de implementar.
2. `/create-tasks` — decompor este plano em backlog executável (fases: scripts
   POSIX + testes; SKILL.md + template + evals; integração nos 2 orquestradores;
   bump de README/CHANGELOG).
3. `/analyze` — validar consistência spec↔plan↔tasks após o backlog.
