# Validation Run — Quickstart Manual (Template)

**Data planejada**: 2026-05-20
**Status**: TEMPLATE — execucao manual pendente
**Executor**: jot (operador)
**Referencia**: [quickstart.md](../quickstart.md) (11 cenarios)

## Pre-requisitos

- Toolkit `claude-ai-tips` instalado via `cstk install` (apos FASE 6)
- Projeto-alvo de teste em path local, COM:
  - `docs/01-briefing-discovery/briefing.md` ratificado
  - `docs/constitution.md` versao >=1.0.0
  - Sem `agente-00c-state/` ativo (status terminal ou inexistente)
- Claude Code session aberta no projeto-alvo

## Cenarios

Marcar com `[x]` apos execucao bem-sucedida; `[!]` em caso de bug.
Anotar exit code e tempo wallclock por cenario.

### Cenario 1 — Happy path (P1)

- [ ] Invocar: `/feature-00c "Adicionar export CSV de relatorios" export-csv`
- [ ] Pre-flight passa (briefing + constitution OK, sem coexistencia)
- [ ] state.json criado em `.claude/feature-00c-state/export-csv/`
- [ ] Pipeline atravessa 7 fases (specify → ... → review-task)
- [ ] Codigo da feature implementado + testes passam
- [ ] `feature-00c-report.md` gerado com 6 secoes
- [ ] Status final: `concluida`
- [ ] Sem secrets em report ou backups (grep manual)

**Resultado**: ___ | **Wallclock**: ___ | **Ondas**: ___ | **Decisoes**: ___

### Cenario 2 — Pre-flight failure: briefing ausente

- [ ] Setup: projeto SEM `briefing.md`
- [ ] Invocar: `/feature-00c "Qualquer feature"`
- [ ] Exit code 1
- [ ] stderr contem: "rode `/briefing` antes ou use `/agente-00c`"
- [ ] **SC-PRE-001**: `.claude/feature-00c-state/` permanece inexistente

### Cenario 3 — Clarify autonomo com score 3/3 (P2)

- [ ] Setup: spec com 3 ambiguidades intencionais
- [ ] Forcar pipeline ate fase clarify
- [ ] asker gera 1-5 perguntas
- [ ] answerer escolhe opcoes com score >=2
- [ ] Cada Decisao registrada com 5 campos + referencias citando
      constitution.version (FR-PRE-004 + FR-017)
- [ ] Spec atualizada com secao `## Clarifications`

### Cenario 4 — Resume apos wakeup (P3)

- [ ] Setup: execucao em fase plan, onda 3, threshold atingido
- [ ] Aguardar wakeup (~270s)
- [ ] `/feature-00c-resume` invocado automaticamente pelo harness
- [ ] Lock check OK
- [ ] state.sha256 validado (FR-014)
- [ ] briefing+constitution hashes validados (FR-PRE-004)
- [ ] Onda 4 inicia exatamente onde parou (mesma fase + decisoes preservadas)

### Cenario 5 — Aborto manual graceful (P4)

- [ ] Setup: execucao em andamento com PID detentor de lock
- [ ] Invocar: `/feature-00c-abort export-csv`
- [ ] SIGTERM enviado ao PID
- [ ] Grace period 60s: onda corrente persiste state graciosamente
- [ ] Exit 0 dentro de 120s (SC-005 ajustado)
- [ ] `feature-00c-report.md` com Secao 1 indicando aborto manual
- [ ] Status: `abortada`
- [ ] Backup final wave-N.json gerado
- [ ] Re-invocar abort: exit 0 com "ja em status terminal" (idempotente)

### Cenario 6 — Coexistencia com agente-00c em terminal (P5 AC#1)

- [ ] Setup: `.claude/agente-00c-state/state.json` com status=concluida
- [ ] Invocar: `/feature-00c "Adicionar paginacao" paginacao`
- [ ] Execucao inicia normalmente
- [ ] `agente-00c-state/` NAO modificado (diff antes/depois)
- [ ] **SC-012**: snapshot mostra apenas novos arquivos sob `feature-00c-state/`

### Cenario 7 — Conflito com agente-00c ativo (P5 AC#2)

- [ ] Setup: `agente-00c-state/state.json` com status=em_andamento
- [ ] Invocar: `/feature-00c "Nova feature"`
- [ ] Exit 2
- [ ] stderr: "agente-00c esta ativo... Resolva via /agente-00c-abort ou /agente-00c-resume"
- [ ] `feature-00c-state/` NAO criado

### Cenario 8 — Features paralelas no mesmo projeto (P5 AC#3)

- [ ] Setup: feature A (`user-auth`) ja em andamento em
      `feature-00c-state/user-auth/`
- [ ] Em sessao 2 (paralela): `/feature-00c "Dashboard" analytics-dashboard`
- [ ] Lock de `analytics-dashboard` ausente, inicia normalmente
- [ ] Ambas correm em paralelo sem interferencia
- [ ] `suggestions.md` compartilhada recebe entradas de ambas (append-only)

### Cenario 9 — Gatilho de loop: 6 ciclos sem progresso (P4 + FR-022.a)

- [ ] Setup: execucao com task T003 falhando ha 5 ondas
- [ ] Onda 6 inicia
- [ ] `cycles.sh check` detecta 5 ondas sem "progresso mensuravel"
- [ ] Aborto: status=abortada, motivo_termino="tendencia a loop em fase execute-task"
- [ ] Relatorio parcial em <60s
- [ ] Secao 6 (Licoes) contem item sobre T003

### Cenario 10 — Roundtrip empirico de secrets (CRITICAL-PATH)

> Este cenario foi executado AUTOMATICAMENTE — ver
> [roundtrip-secrets-2026-05-20.md](./roundtrip-secrets-2026-05-20.md)
> para resultados empiricos detalhados.

- [x] Setup com `.env` contendo `API_TOKEN=sk-prod-aaaaaaaaaaaaaaaaaaaaaaa`
- [x] Execucao registra decisao com texto contendo o token
- [x] `grep "sk-prod-" state.json` → MATCH (operacional preservado)
- [x] `grep "sk-prod-" backups/wave-NNN.json` → SEM MATCH (filtrado)
- [x] `grep "REDACTED" backups/wave-NNN.json` → MATCH
- [x] `grep "sk-prod-" feature-00c-report.md` → SEM MATCH
- [x] `state_sha256_self` recalculado bate com campo gravado

### Cenario 11 — Constitution evolui MAJOR durante pausa

- [ ] Setup: execucao pausada (aguardando_humano), `constitution.sha256`
      aponta para v1.1.0
- [ ] Operador edita `docs/constitution.md` para v2.0.0
- [ ] Invocar: `/feature-00c-resume <short> --resposta-bloqueio "..."`
- [ ] Resume detecta MAJOR drift
- [ ] Bloqueio humano compulsorio: novo blq em `bloqueios_humanos[]`
- [ ] Exit 4 + relatorio parcial atualizado

## Resumo

| # | Foco | Status | Wallclock | Notas |
|---|------|--------|-----------|-------|
| 1 | Happy path | pendente | | |
| 2 | Briefing ausente | pendente | | |
| 3 | Clarify autonomo | pendente | | |
| 4 | Resume cross-onda | pendente | | |
| 5 | Abort SIGTERM+grace | pendente | | |
| 6 | Coexistencia OK | pendente | | |
| 7 | Coexistencia bloqueada | pendente | | |
| 8 | Features paralelas | pendente | | |
| 9 | Loop trigger | pendente | | |
| 10 | **Roundtrip secrets** | **EXECUTADO** | <1s | Ver roundtrip-secrets-2026-05-20.md |
| 11 | Constitution MAJOR drift | pendente | | |

**Bugs encontrados**: anotar com `[!]` no checkbox + descricao + filing de
`suggestions.md` ou issue.

**Quando executar**: apos FASE 6 (release) + instalacao via `cstk install`.
