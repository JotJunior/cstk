<!-- converge-status: outcome=actionable; provenance=gate; at=2026-09-26T11:48:35Z; actionable=3; tasks-digest=f34bd055edfb -->
<!-- converge-status: outcome=actionable; provenance=gate; at=2026-09-26T12:59:39Z; actionable=3; tasks-digest=7c0aa11cc58b -->
<!-- converge-status: outcome=actionable; provenance=gate; at=2026-09-26T14:58:20Z; actionable=12; tasks-digest=0ce42986bcb3 -->
<!-- converge-status: outcome=actionable; provenance=gate; at=2026-09-26T18:56:00Z; actionable=5; tasks-digest=d78c6b0c93f8 -->
<!-- converge-status: outcome=actionable; provenance=gate; at=2026-09-26T20:04:46Z; actionable=2; tasks-digest=9e683d54c041 -->
<!-- converge-status: outcome=clean; provenance=gate; at=2026-09-26T20:35:46Z; actionable=0; tasks-digest=8cbfbe56270e -->

## Ciclo 6 (onda-051) — residuais aceitos

Ciclo 6 sobre o delta da FASE 14: 0 contradicts, 0 gaps de codigo
(missing/partial). Gate MUST: `extract-must --coverage` => 5 principios
reconhecidos, `cobertura de MUST: ok`; Principio II honrado (0 invocacao
executavel de `sqlite3` em `plugins/cstk-jira/` — unica ocorrencia e texto
do usage de `jira-sync.sh`). Suites: test_jira-sync 71/71,
test_posttooluse-jira-sync 18/18, test_jira-contract 8/8,
test_doc-subcommands 4/4. Lacunas restantes, so de documentacao e sem
impacto funcional, aceitas como residuais (Decisao registrada na onda-051):

| # | severidade | path | lacuna | por que aceito |
|---|------------|------|--------|----------------|
| R1 | LOW | `docs/specs/cstk-jira/contracts/plugin-scripts.md` (linha `resolve-state-field`) | ainda diz "le um campo top-level"; nao cita o caminho pontuado, a allowlist `[A-Za-z0-9_.]` nem o exit 2 da 14.1.1 | o usage do proprio `jira-sync.sh` e os comentarios do codigo documentam o comportamento correto; SY-66/SY-67 cobrem o comportamento; contrato so desatualizado (subconjunto do real) |
| R2 | LOW | `plugins/cstk-jira/scripts/jira-sync.sh` (`_js_resolve_state_field`, ramo state.json) | caminho pontuado resolvido pela chave folha em qualquer nivel (grep/sed, sem rastrear o objeto pai) | limitacao documentada no usage e no comentario; sonda nesta onda: export real do state tem exatamente 1 ocorrencia de `canonical_project` e de `current_stage`, logo nao ha nivel errado a casar para os 2 call-sites atuais |

## Round r02 — Ciclo 1 (onda-017) — actionable

Delta r02 (FR-020..FR-025, SEC-6..SEC-13, R12-R18, sidecars, create-project,
resolve-path). Gate MUST: `extract-must --coverage` => 5 principios,
`cobertura de MUST: ok`; Principio II honrado (0 invocacao executavel de
`sqlite3` em `plugins/cstk-jira/` — unica ocorrencia e texto de usage em
`jira-sync.sh`). Documentacao alinhada ao codigo pela onda-016 NAO foi
aceita como fechamento de requisito que `plan.md`/`data-model.md` seguem
exigindo. 6 achados acionaveis, apendados como FASE 21:

| # | tipo | severidade | path | origem |
|---|------|------------|------|--------|
| 21.1 | contradicts | HIGH | `plugins/cstk-jira/scripts/jira-sync.sh` (`_js_rebaseline_marker`) | plan.md SEC-10 / fluxo 6 |
| 21.2 | contradicts | HIGH | `plugins/cstk-jira/scripts/jira-sync.sh` (`_js_cmd_links`, 404 R17) | jira-rest.md R17 / plan.md Riscos / FR-025 |
| 21.3 | partial | HIGH | `plugins/cstk-jira/hooks/posttooluse-jira-sync.sh` | plan.md Impacto em hooks |
| 21.4 | partial | MEDIUM | `plugins/cstk-jira/scripts/jira-config.sh` (`validate`) | data-model.md ProjectConfig validation rules |
| 21.5 | partial | MEDIUM | `plugins/cstk-jira/scripts/jira-setup.sh` (`check-field-support`) | plan.md Project Structure/fluxo 7/Riscos |
| 21.6 | partial | MEDIUM | `plugins/cstk-jira/skills/jira-setup/SKILL.md` (`project_create`) | data-model.md ProjectConfig / plan.md fluxo 7 |

Residuais R1/R2 do r01 inalterados (LOW, documentacao).
<!-- converge-status: outcome=actionable; provenance=gate; at=2026-09-27T15:27:31Z; actionable=6; tasks-digest=234a560d080c -->
