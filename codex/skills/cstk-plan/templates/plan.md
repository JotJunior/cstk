# Implementation Plan: [FEATURE]

**Feature**: `[short-name]` | **Date**: [DATE] | **Spec**: [link relativo]

## Summary

[Requisito primario + abordagem tecnica da pesquisa]

## Technical Context

**Language/Version**: [ex: Go 1.24, Python 3.11, TypeScript 5.x ou NEEDS CLARIFICATION]
**Primary Dependencies**: [ex: Chi v5, FastAPI, React 18 ou NEEDS CLARIFICATION]
**Storage**: [ex: PostgreSQL, Redis, files ou N/A]
**Testing**: [ex: go test, pytest, vitest ou NEEDS CLARIFICATION]
**Target Platform**: [ex: Kubernetes, Vercel, mobile ou NEEDS CLARIFICATION]
**Project Type**: [ex: library, cli, web-service, mobile-app ou NEEDS CLARIFICATION]
**Performance Goals**: [ex: 1000 req/s, 60 fps ou NEEDS CLARIFICATION]
**Constraints**: [ex: <200ms p95, <100MB memory ou NEEDS CLARIFICATION]
**Scale/Scope**: [ex: 10k users, 1M LOC ou NEEDS CLARIFICATION]

## Constitution Check

*GATE: Deve passar antes do Phase 0. Re-checar apos Phase 1.*

| Principio | Status | Notas |
|-----------|--------|-------|
| [Nome] | PASS / FAIL / N/A | [Detalhes] |

## Project Structure

### Documentation (this feature)

```
docs/specs/[feature]/
├── spec.md
├── plan.md          # This file
├── research.md      # Phase 0 output
├── data-model.md    # Phase 1 output
├── quickstart.md    # Phase 1 output
└── contracts/       # Phase 1 output
```

### Source Code (repository root)

[Arvore de diretorios real do projeto, com paths concretos]

**Structure Decision**: [Decisao documentada sobre estrutura escolhida]

## Complexity Tracking

> Preencher APENAS se Constitution Check tem violacoes que precisam justificativa

| Violacao | Por Que Necessario | Alternativa Simples Rejeitada Porque |
|----------|-------------------|--------------------------------------|
| [ex: 4o servico] | [necessidade] | [por que 3 sao insuficientes] |
