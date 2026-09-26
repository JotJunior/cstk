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
