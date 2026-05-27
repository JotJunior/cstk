# Relatorio de Status das Tarefas — show-tips

**Data:** 2026-05-27
**Projeto:** claude-ai-tips (cstk toolkit)
**Feature:** show-tips (sistema de dicas das skills)
**Tipo:** Misto (CLI POSIX + conteudo + integracao)
**Arquivo de Tarefas:** docs/specs/show-tips/tasks.md
**Onda:** onda-010 (review-task, fase final)

---

## Resumo Executivo

| Metrica | Valor |
|---------|-------|
| Total de Tarefas | 25 |
| Concluidas | 25 (100%) |
| Subtarefas | 89 |
| Subtarefas concluidas | 89 (100%) |
| Em Progresso | 0 |
| Pendentes | 0 |
| Bloqueadas | 0 |
| Bloqueios humanos | 0 |
| Ondas executadas | 10 |
| Decisoes auditaveis | 32 |
| Divergencias .tasks[] vs tasks.md | 0 (reconcile limpo) |

Feature **100% implementada**. Todos os criterios de aceite atendidos; testes passando; sem pendencias.

---

## Progresso por Fase

| Fase | Descricao | Status |
|------|-----------|--------|
| FASE 1 | Catalogo de dicas (tips/catalog.md) | 100% (5 tasks) |
| FASE 2 | Script POSIX cli/lib/show-tip.sh | 100% (8 tasks) |
| FASE 3 | Dispatcher cstk show-tip | 100% (1 task) |
| FASE 4 | Integracao orquestradores (agente-00c + feature-00c) | 100% (2 tasks) |
| FASE 5 | Testes automatizados | 100% (6 tasks) |
| FASE 6 | Documentacao e release (CHANGELOG 4.6.0) | 100% (3 tasks) |

## Selecao de modelo por onda (sugerido vs aplicado)

| onda | etapa | sugerido | aplicado | origem | divergente |
|------|-------|----------|----------|--------|------------|
| init | specify | sonnet | sonnet | mapa | no |
| onda-001 | clarify | sonnet | sonnet | mapa | no |
| onda-002 | plan | opus | opus | mapa | no |
| onda-003 | checklist | sonnet | sonnet | mapa | no |
| onda-004 | create-tasks | sonnet | sonnet | mapa | no |
| onda-005 | execute-task | sonnet | sonnet | mapa | no |
| onda-006 | execute-task | sonnet | sonnet | mapa | no |
| onda-007 | execute-task | sonnet | sonnet | mapa | no |
| onda-008 | execute-task | sonnet | sonnet | mapa | no |
| onda-009 | review-task | haiku | haiku | mapa | no |

**Sumario por onda**:
- Total de ondas roteadas: 10
- aplicado haiku/sonnet/opus/manter-atual: 1/8/1/0
- origem mapa/refino/override-operador/fallback: 10/0/0/0
- fallback (manter-atual): 0 (0%)
- override do operador: 0 (0%)
- divergencias sugerido!=aplicado: 0 (rotuladas: 0, sem rotulo: 0)

> SC-006 satisfeito: 0 divergencias sem rotulo. Roteamento 100% via mapa fase->modelo (FR-009 bidirecional: plan->opus, review-task->haiku).

---

## Entregaveis verificados empiricamente

| Artefato | Verificacao |
|----------|-------------|
| `tips/catalog.md` | 81 entradas, 38 skills (23 global + 7 Go + 8 .NET), >=2 dicas/skill; `cstk show-tip --audit` = "catalogo completo (38 skills cobertas)" |
| `cli/lib/show-tip.sh` | `shellcheck -s sh` exit 0 (POSIX puro); RNG /dev/urandom + fallback `date +%s`; awk `-v` (anti-injecao A05); fail-silent FR-006 |
| `cli/cstk` | subcomando `show-tip` operacional (show-tip <skill> / sem-args / --audit / --help) |
| Integracao orquestradores | `global/agents/agente-00c-orchestrator.md` (passo 2.bis) + `agente-00c-feature-orchestrator.md` (passo 4.ter), fail-silent |
| `tests/cstk/test_show-tip.sh` | 17 cenarios; `tests/run.sh --fast` = 855 PASS / 0 FAIL; performance 51ms (< SC-002 1s) |
| `CHANGELOG.md` | entrada 4.6.0 (Added + Fixed) |

## Bugs corrigidos durante a execucao

1. **Constitution Principio II (dec-012/018)**: `$RANDOM` (bash-ism) substituido por `/dev/urandom` + `awk srand()` — confirmado via shellcheck SC3028.
2. **Parser awk (FASE 5)**: transicao `body -> out` em vez de `body -> frontmatter` ignorava o frontmatter de entradas pares — emitia 27 de 81 entradas; corrigido para 81/81.
3. **Catalogo**: terminador `---` ausente apos a ultima entrada + nota ao mantenedor.

## Notas de processo

- Ondas 006/007 (execute-task, sonnet) e 010 (review-task, haiku) tiveram o orquestrador retornando sem completar o loop 6-13 / sem `Schedule intent`; recuperadas deterministicamente pelo command pai (`/feature-00c-resume`) via reconcile-tasks + state-ondas end + ingest. Sem impacto no produto.

---

## Recomendacoes

### Acoes Imediatas
- Nenhuma tarefa pendente. Feature pronta para release (CHANGELOG 4.6.0).
- Sugestao pos-merge: validar a exibicao real da dica no inicio de uma onda do agente-00c/feature-00c em uso normal (smoke manual).
