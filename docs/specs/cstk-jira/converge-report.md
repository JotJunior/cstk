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

## Round r02 — Ciclo 3 (onda-022) — actionable

Verificacao da FASE 22 no CODIGO e nos testes (nao na doc):

| achado c2 | veredito | evidencia |
|-----------|----------|-----------|
| 22.1 | fechado | `jira-sync.sh` `_js_cmd_milestone_ensure` (~1245-1265): `state=blocked` para a mesma `(project_key, name)` => `status=blocked` exit 7 com diagnostico, ANTES do GET de project/R13/R12; `milestone-unblock` (~3745-3782) delega a `jira-map.sh milestone-clear-blocked` (~656-686: charset `[A-Za-z0-9_-]` validado, so apaga `$5 == "blocked"`, header preservado); `jira-setup.sh write-config` (~545-567) chama os dois best-effort so apos gravar; contrato `plugin-scripts.md` 133/205/215/216 bate com o codigo; SY-92 (0 chamadas na 2a ensure) + JS-20/21 + 3 cenarios de `milestone-clear-blocked` |
| 22.2 | fechado no caminho feliz | `_js_rebaseline_marker` (~858-890): `overwrite` de `label_drift` reaplica `phase-<N>` local so com `add` e grava `written_phase_label`; `keep_jira` mantem a re-derivacao de 21.1; os 2 unicos chamadores (`_js_cmd_resolve` ~3642 `overwrite`, ~3650 `keep_jira`) passam CHOICE; skill `jira-sync` (~282-296) restaurada |

Regressao encontrada (FASE 23): o ramo novo de 22.2.1 depende do exit code
de `_js_reconcile_phase_label`, que nunca e nao-zero no R2 (`_jrpl_ec=$?`
apos `fi` sem `else` ~1800 => sempre 0; 400 em R2 e passthrough exit 0 em
`jira-io.sh` ~927). Medido com o stub: R2 403 => `resolve` exit 0 e marker
sem `written_phase_label` (overwrite volta a ser keep_jira); R2 400 =>
marker com `written_phase_label=phase-5` sem o label aplicado (baseline
falsa). O ramo `overwrite` tambem ignora `labels_enabled=off`.

| # | tipo | severidade | path | origem |
|---|------|------------|------|--------|
| 23.1 | contradicts | HIGH | `plugins/cstk-jira/scripts/jira-sync.sh` (`_js_reconcile_phase_label` / ramo `overwrite` de `_js_rebaseline_marker`) | FR-022 / task 22.2.1 / data-model.md ConflictRecord + :406 |

dec-079 (`overwrite` de `milestone_drift` igual a `keep_jira`) avaliado:
honra o "overwrite reaplica" do data-model (baseline vazia auto-cura no
proximo reconcile, `_js_reconcile_epic_milestone` sem guard de written
nao-vazio); residual LOW aceito (dec-081): as 2 escolhas ficam
indistinguiveis para `milestone_drift`. Tambem LOW: JS-20 nao assere a R13
da ensure seguinte (decorre da guarda nao casar). Cobertura FR-020..FR-025:
sem outros gaps. Suites (uma a uma, `JIRA_IO_BACKOFF_SECONDS=0 LC_ALL=C`):
test_jira-sync 104/104, test_jira-map 44/44, test_jira-setup 41/41,
test_jira-config 36/36, test_posttooluse-jira-sync 21/21. Gate MUST:
`extract-must --coverage` => 5 principios, `cobertura de MUST: ok`;
Principio II honrado (`sqlite3` so em comentario/usage). Residuais R1/R2
do r01 inalterados (LOW, documentacao).
<!-- converge-status: outcome=actionable; provenance=gate; at=2026-09-27T18:04:24Z; actionable=1; tasks-digest=7cfa44107059 -->

## Round r02 — Ciclo 4 (onda-024) — actionable

Conferencia da FASE 23 no CODIGO e nos testes:

| achado c3 | veredito | evidencia |
|-----------|----------|-----------|
| 23.1 | fechado | `jira-sync.sh` `_js_reconcile_phase_label`: R3 GET com `if VAR=$(cmd); then :; else ec=$?; fi` (~1772-1778) e R2 PUT com `else` explicito mais `http_status` nao-2xx => falha (~1827-1845); `_js_rebaseline_marker` le `labels_enabled` e com `off` nao faz R2/R3 e deixa a baseline vazia (~873-895); o chamador do drain absorve a falha com `if/else` e fallback para WRITTEN (~2915-2920), sem perder a reconciliacao de status. `scenario_mutation_17_3_6` discrimina: o stub zera o log a cada `_make_curl_stub`, o controle exige 1 PUT R2 e o mutante exige 0 |

Residuais da FASE 23 (LOW, registrados):

- O oraculo de mutation declarado em `tests/cstk/test_jira-sync.sh` ~3879-3880 (23.1.3, "reintroduzir `$?` apos o `fi` MUST falhar") e falso. Esse mutante e EQUIVALENTE, porque a checagem de `http_status` ja converte qualquer nao-2xx em falha. Medido com uma copia mutada do plugin fora do repo: os 3 cenarios 23.1 passam. O oraculo que discrimina e remover a checagem de `http_status`, e com ele o cenario 400 falha (medido). A correcao do comentario ficou na tarefa 24.1.4.
- A nota de execucao da onda-023 informa `test_jira-sync 110/110`, mas o arquivo tem 108 cenarios (104 + 3 + 1), e a rodada desta onda deu 108/108.

Decisao sobre o achado colateral dec-084 (`_js_reconcile_epic_milestone`): **confirmado e classificado HIGH**, nao LOW. `_jrem_ec=$?` e lido apos `fi` sem `else` (~1725; medido `if false; then :; fi; echo $?` => 0), e 400/404/409/422 do R2 (contracts/jira-rest.md:121, passthrough exit 0 em `jira-io.sh` ~956-958) imprimem o id NOVO. O drain grava entao um `written_fix_version_id` falso, o Epic nunca e corrigido, `milestone_drift` nunca reabre e o round seguinte deixa duas Fix Versions no Epic. O impacto e distinto do residual aceito em dec-081 (`overwrite` igual a `keep_jira`). Virou a tarefa 24.1.

Varredura de `$?` morto (todos os `.sh` de `plugins/cstk-jira/scripts` e `hooks`: 28 leituras de `$?` fora de comentario):

| sitio | padrao | veredito |
|-------|--------|----------|
| `jira-sync.sh:1725` | `$?` apos `if...fi` sem `else` | defeito (24.1) |
| `jira-sync.sh:2726`, `:2730` | `$?` apos atribuicao NUA sob `set -eu` | defeito (24.5; medido: `drain` exit 1 silencioso, evento seguinte nao processado) |
| `jira-io.sh:821`, `:829` | `|| _jir_ec=$?` | correto |
| demais 23 (21 em `jira-sync.sh`, `jira-setup.sh:730/803`) | `$?` logo apos `else` | correto |

Nenhum `if ! ...; then ... $?` restante (o de `_js_reconcile_phase_label` foi corrigido na 23.1.1). Os hooks e os scripts `jira-map`/`jira-config`/`jira-tasks`/`jira-title`/`jira-conflict-view` nao leem `$?`.

Varredura de status nao-2xx de ESCRITA tratado como sucesso (`jira-io.sh` so classifica 400/409 em R4 e 400 em R12; os demais codigos vao em passthrough com exit 0, contracts/plugin-scripts.md:58):

| sitio | op | efeito | veredito |
|-------|----|--------|----------|
| `jira-sync.sh:1719` | R2 fixVersions | baseline de marco falsa e acumulo de 2 versoes | 24.1 HIGH |
| `jira-sync.sh:1554` | R17 | aresta `active` sem link, nunca retentada | 24.4 HIGH |
| `jira-sync.sh:2139` | R2 summary/descricao | baseline falsa e `manual_edit` espurio | 24.3 HIGH |
| `jira-sync.sh:1827` | R2 labels | ja trata `http_status` | ok (23.1) |
| `jira-sync.sh:1306` | R12 | 400 classificado; outro nao-2xx => sem `.id` => `_js_die` | fail-closed, ok |
| `jira-sync.sh:2476` | R1 | nao-2xx => sem id/key => `_js_die` | fail-closed, ok |
| `jira-setup.sh:799` | R18 | nao-2xx => sem `.key` => `_js_die` | fail-closed, ok |
| `jira-sync.sh:2984`, `:3233` | R4 | 400/409 => deferred; 404/422 em passthrough gravam o status alvo no marker | LOW: a divergencia reaparece no proximo R3 como `manual_edit` |
| `jira-sync.sh:938`, `:2172`, `:2250`, `:2944`, `:3016`, `:3277` | R6 PUT marker | 400/404 em passthrough => marker nao gravado | LOW: aparece no proximo R6 GET como `marker_missing`/`manual_edit`; o corpo e montado por `json-build`, entao 400 e improvavel |

Achado novo, fora das duas varreduras: escritores de SyncMarker que apagam as baselines r02. O R6 PUT substitui a propriedade inteira (~2848-2851), e `_js_process_one_event` (~3253-3255) e `_js_maybe_update_mapped_issue` (~2152-2157) nao carregam `written_phase_label`/`written_fix_version_id`. Medido com o stub de fila: marker lido com `written_phase_label=phase-1` e R6 PUT da transicao por evento gravado sem o campo. Como a reconciliacao de FASE exige esse campo (~2895-2896), ela deixa de rodar para o item depois da primeira transicao de status (FR-022). Viraram as tarefas 24.2 e 24.3.

| # | tipo | severidade | path | origem |
|---|------|------------|------|--------|
| 24.1 | contradicts | HIGH | `plugins/cstk-jira/scripts/jira-sync.sh` (`_js_reconcile_epic_milestone` + chamador do drain ~2877) | FR-020 / task 16.4.2 |
| 24.2 | contradicts | HIGH | `plugins/cstk-jira/scripts/jira-sync.sh` (`_js_process_one_event` R6 marker) | FR-022 / task 17.3.1 |
| 24.3 | contradicts | HIGH | `plugins/cstk-jira/scripts/jira-sync.sh` (`_js_maybe_update_mapped_issue`) | FR-011 / task 12.5.1 |
| 24.4 | contradicts | HIGH | `plugins/cstk-jira/scripts/jira-sync.sh` (`_js_cmd_links` R17) | FR-025 / task 18.4 |
| 24.5 | contradicts | HIGH | `plugins/cstk-jira/scripts/jira-sync.sh` (`_js_process_reconcile_event` items) | FR-004 / task 10.3 |

Severidades calculadas por `severity.sh` (contradicts + P1 + must-violated=false => HIGH). Probabilidade de disparo por item:

- 24.2: fluxo normal da US3.
- 24.1, 24.3, 24.4: exigem um 4xx documentado no contrato.
- 24.5: exige `tasks.md` ausente.

Cobertura de FR-020..FR-025: FR-021 (reuso), FR-023 (Epic por feature) e FR-024 (gate da criacao de projeto) nao tem gap novo; os gaps de FR-020, FR-022 e FR-025 estao acima.

Suites rodadas uma a uma nesta onda, com `JIRA_IO_BACKOFF_SECONDS=0 LC_ALL=C`: test_jira-sync 108/108, test_jira-mutation 17/17.

Gate MUST: `extract-must --coverage` => 5 principios, `cobertura de MUST: ok`. Os residuais R1/R2 do r01 seguem inalterados (LOW, documentacao).
<!-- converge-status: outcome=actionable; provenance=gate; at=2026-09-27T19:06:53Z; actionable=5; tasks-digest=09017c961b85 -->
