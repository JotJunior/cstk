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

## Round r02 — Ciclo 2 (onda-020) — actionable

Verificacao da FASE 21 no CODIGO e nos testes (nao na doc):

| achado c1 | veredito | evidencia |
|-----------|----------|-----------|
| 21.1 | fechado | `jira-sync.sh` `_js_rebaseline_marker` (~741-873): R6 GET antes do PUT, carry-forward das 2 chaves, re-derivacao restrita (`milestone-id-known`, `^phase-[0-9]+$`) |
| 21.2 | fechado | `_js_cmd_links` (~1466-1486): 404 de R17 => `visibility_or_disabled` so da aresta; cascata so com 404 de R16 (~1333); enum em `jira-map.sh:277` + data-model.md:466 |
| 21.3 | fechado | `posttooluse-jira-sync.sh` (~265-287): `milestone=`/`links_unrepresentable=`/`links_stale=` ancorados, omitidos no caminho feliz; contracts/hooks.md 5.bis ESTENDIDO |
| 21.4 | fechado | `jira-config.sh` `_jc_cmd_validate`: 5 enums + SEC-6 + SEC-1 |
| 21.5 | fechado | `jira-setup.sh` `check-field-support` (~380-411) + skill `jira-setup` ETAPA 5.bis/ETAPA 8 |
| 21.6 | fechado | `create-project`/`consent-question` recusam `never` antes de qualquer requisicao (~611, ~670); skill ETAPA 2.bis pula a oferta |

Suites (uma a uma, `JIRA_IO_BACKOFF_SECONDS=0 LC_ALL=C`): test_jira-sync
98/98, test_jira-config 36/36, test_jira-setup 39/39,
test_posttooluse-jira-sync 21/21. Gate MUST: `extract-must --coverage` =>
5 principios, `cobertura de MUST: ok`; Principio II honrado (`sqlite3` so
em comentario/usage). Varredura de ponta a ponta de FR-020..FR-025 achou 2
gaps novos, apendados como FASE 22:

| # | tipo | severidade | path | origem |
|---|------|------------|------|--------|
| 22.1 | partial | HIGH | `plugins/cstk-jira/scripts/jira-sync.sh` (`milestone ensure`) + `jira-setup.sh` (`write-config`) | FR-020 / research R2-4 / data-model Milestone |
| 22.2 | contradicts | HIGH | `plugins/cstk-jira/scripts/jira-sync.sh` (`_js_rebaseline_marker` sob `overwrite`) | data-model ConflictRecord ("`overwrite` reaplica") / FR-022 |

22.2 inclui doc alinhada ao codigo (skill `jira-sync`, item `overwrite`),
que nao conta como fechamento. Residuais R1/R2 do r01 inalterados (LOW,
documentacao).
<!-- converge-status: outcome=actionable; provenance=gate; at=2026-09-27T17:09:19Z; actionable=2; tasks-digest=aae6563e4a62 -->
