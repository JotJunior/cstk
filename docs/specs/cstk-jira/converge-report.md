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

## Round r02 — Ciclo 5 (onda-027) — actionable

Conferencia da FASE 24 no CODIGO e nos testes:

| achado c4 | veredito | evidencia |
|-----------|----------|-----------|
| 24.1 | fechado (codigo) | `jira-sync.sh` `_js_reconcile_epic_milestone`: R2 com `else` explicito e `http_status` nao-2xx => falha (~1754-1770), WRITTEN inalterado. O chamador do drain (~2978-2987) esta guardado: exit 4 => `_JSPE_BREAK`, demais => `_jspr_had_deferred`. Cenarios 400/403/401 verdes. Mutantes medidos fora do repo: sem a checagem de `http_status`, o cenario 400 falha; com a atribuicao nua no chamador, os 3 cenarios falham. A parte de mutation da 24.1.3 nao existe no mutation suite (achado 25.2) |
| 24.2 | fechado | `_js_process_one_event` le e repassa `written_fix_version_id`/`written_phase_label` (~3289-3290, ~3398-3399). `scenario_mutation_24_2_1` verde |
| 24.3 | fechado | `_js_maybe_update_mapped_issue`: `http_status` nao-2xx do R2 => sem R6 (~2206-2216); carry-forward no R6 (~2240-2241). `scenario_mutation_24_3_1` verde |
| 24.4 | fechado | `_js_cmd_links`: `active` so com `2??` (~1573-1589). Nao-2xx nao grava nada. `scenario_mutation_24_4_1` verde |
| 24.5 | fechado | `_js_process_reconcile_event`: as duas chamadas a `items` estao guardadas (~2806-2826). `scenario_mutation_24_5_1` verde |

Varredura de regressao da FASE 24:

- **Leitura de `http_status` de escrita.** As 4 implementacoes (`phase_label` ~1878, `epic_milestone` ~1761, `maybe_update` ~2206, `cmd_links` ~1573) usam o mesmo parse (`grep '^http_status=' | tail -n 1 | cut -d= -f2`, `case 2??`). Nas tres de R2, o nao-2xx so promove exit 0 para 1 e preserva o exit 4. Nenhum caminho que classificava `auth_failed` deixou de classificar.
- **Chamador de `_js_reconcile_phase_label`.** E o unico dos quatro cujo chamador (~3026-3031) descarta o exit code. Medido com um probe fora do repo: R2 de labels com 401 => evento `done`, sem `auth_failed`; com 403 => `done`, sem `deferred`. O marco do Epic, no mesmo drain, da `auth_failed`/`deferred`. Isso e anterior a FASE 24 (vem da guarda 23.1), mas ficou evidente com a 24.1.2, e o comentario do chamador (~3024-3025) ficou falso. Virou o achado 25.1.
- **R6 PUT do marker.** Sao 6 sitios (~938, ~2246, ~2324, ~3055, ~3127, ~3406). Os 5 que regravam um marker existente carregam `written_fix_version_id`/`written_phase_label`; o de ~2324 e a criacao. Nenhum outro script faz PUT em properties, e `resolve`/`relink`/`convert` passam por esses mesmos sitios.
- **24.4 com 400 deterministico.** Nao ha loop dentro de uma execucao: cada `links` faz um R17 por aresta e segue (`continue`). Entre execucoes, a aresta e retentada a cada `links`, sem estado persistido. O data-model de links (~465-479) so tem `active`/`stale`/`unrepresentable`, e `unrepresentable` exige prova (404/413/R16/sem ancora), entao nao ha estado para "erro permanente". No drain, a saida de `links` e descartada (~3152, `>/dev/null 2>&1`), e a aresta nao aparece em `links_active` nem em `links_unrepresentable`. O 400 do R17 e documentado como "comentario nao criado" (contracts/jira-rest.md:548), e o motor nunca envia `comment`. **Residual LOW aceito.**
- **24.1.2 com 4xx deterministico.** O evento `reconcile` fica `deferred` indefinidamente. Os eventos de reconcile nao sao coalescidos no enqueue, entao cada `close_wave` soma mais um. O R4 com 403/400 ja se comportava assim antes da FASE 24, e o estado fica visivel como `deferred=N` no resumo. **Residual LOW aceito.**
- **`_js_maybe_update_mapped_issue`.** Trata 401 como "item pulado" com diagnostico em stderr, e nao como `auth_failed` (~2088-2094, ~2213). O `convert` e acionado pelo operador e esse comportamento e anterior a FASE 24. **Residual LOW aceito.**

| # | tipo | severidade | path | origem |
|---|------|------------|------|--------|
| 25.1 | contradicts | HIGH | `plugins/cstk-jira/scripts/jira-sync.sh` (chamador de `_js_reconcile_phase_label` em `_js_process_reconcile_event`) | FR-016 / task 17.3.1 |
| 25.2 | partial | HIGH | `tests/cstk/test_jira-mutation.sh` (mutantes 24.1.1/24.1.2) | FR-020 / task 24.1.3 |

Severidades calculadas por `severity.sh`, com `must-violated=false` e US3 P1: contradicts+P1 => HIGH e partial+P1 => HIGH.

Cobertura de FR-020..FR-025, de ponta a ponta: FR-021, FR-023 e FR-024 nao tem gap novo; FR-020 tem o codigo fechado e falta so o guard de mutation (25.2); FR-022 esta fechado no carry-forward e com gap de classificacao no chamador (25.1); FR-025 tem so o residual LOW acima.

Suites rodadas uma a uma nesta onda, com `JIRA_IO_BACKOFF_SECONDS=0 LC_ALL=C`: test_jira-sync 116/116, test_jira-mutation 22/22, test_jira-map 44/44, test_jira-setup 41/41, test_jira-config 36/36, test_jira-tasks 29/29, test_jira-io 129/129, test_posttooluse-jira-sync 21/21.

Gate MUST: `extract-must --coverage` => 5 principios (I, II, III, IV, VI), `cobertura de MUST: ok`. Principio II honrado: `sqlite3` so aparece no texto de usage (~239). Os residuais R1/R2 do r01 seguem inalterados (LOW, documentacao).
<!-- converge-status: outcome=actionable; provenance=gate; at=2026-09-27T20:34:26Z; actionable=2; tasks-digest=f820af305787 -->

## Round r02 — Ciclo 6 (onda-029) — actionable

Conferencia da FASE 25 no CODIGO e nos testes:

| achado c5 | veredito | evidencia |
|-----------|----------|-----------|
| 25.1 | fechado (codigo e comportamento) | `jira-sync.sh` ~3031-3042: o `else` do chamador de `_js_reconcile_phase_label` captura `_jspr_phl_ec=$?`; exit 4 => `_JSPE_BREAK=yes` + `break`; os demais => `_jspr_had_deferred=yes`. E a mesma convencao do marco do Epic (~2978-2988). O fallback para WRITTEN foi mantido, e a reconciliacao de status do mesmo item segue. O comentario (~3015-3030) foi corrigido; a frase "ainda devolve sempre 0" nao existe mais no arquivo. Cenarios 401 (`auth_failed`) e 403 (`deferred`) verdes. Mutante medido fora do repo (o `else` volta a so restaurar WRITTEN): os 2 cenarios falham. A parte de mutation da 25.1.2 nao existe no mutation suite (achado 26.1) |
| 25.2 | fechado | `test_jira-mutation.sh`: `scenario_mutation_24_1_1_reconcile_epic_milestone_http_status` (~841) e `scenario_mutation_24_1_2_drain_epic_milestone_caller_guard` (~925). Cada um tem guarda `mutant_stale`, confere que a mutacao foi aplicada (grep pos-sed; `assert` do python3 + grep pos-mutacao) e roda controle no original antes do mutante. Discriminam: A => 0 PUT ao marker do Epic no controle e 1 no mutante; B => controle transiciona a Task (R4), mutante sai com exit != 0 sem chegar a Task. Suite 24/24 |

Regressao da FASE 25 (o diff de codigo desde a onda-027 e so o bloco do `else` acima):

- **Alcance do `break`.** Esta dentro do `while ... done < "$_jspr_items_file"` (~2835-3150), sem loop aninhado entre ele e o `while`. Sai do loop de ITENS, igual ao ramo do marco. Depois, `links` e pulado (`_JSPE_BREAK` ~3159), o evento vira `auth_failed` (~3167-3169) e `_js_cmd_drain` interrompe o loop de EVENTOS (~3583-3585). Os eventos seguintes ficam `queued` e nao sao marcados `done`. O gate FR-016 no inicio do proximo `drain` (~3499-3506) bloqueia chamadas novas enquanto houver `auth_failed`. O estado da outbox e o mesmo do ramo do marco.
- **Marker no break/deferred.** Com exit 4, nenhum R6 PUT e feito para o item (o `break` vem antes). Com exit != 4, o item segue com `_jspr_written_phase_label` inalterado, e o R6 PUT de status regrava a baseline antiga (label nao aplicado). Nao ha baseline falsa. Os cenarios 401/403 exigem 6 chamadas e zero PUT em properties.
- **Contagens do resumo.** `status` (~3660, ~3687) conta direto da outbox. `auth_failed`/`deferred` passam a aparecer onde antes saia `done`. Nenhuma contagem e derivada do evento processado.
- **Outro chamador.** `_js_rebaseline_marker` (~888) e acionado pelo operador e ja falha alto (`return 1` com diagnostico). Nao foi alterado.

Revisao dos residuais LOW aceitos, somados aos fixes recentes:

- **dec-081** (overwrite de `milestone_drift` igual a `keep_jira`): nenhum codigo tocado. Segue LOW.
- **dec-088** (R4 404/422 e R6 PUT 400/404 em passthrough): nenhum codigo tocado. As falhas continuam aparecendo no proximo R3/R6 GET. Segue LOW.
- **dec-095 (a)** (R17 400 retentado) e **(c)** (`maybe_update` com 401): nenhum codigo tocado. Seguem LOW.
- **dec-095 (b)** (reconcile `deferred` acumulando, um evento por `close_wave`): a 25.1.1 ALARGA o gatilho. Um 4xx deterministico no R2 de labels, que antes fechava `done`, agora e `deferred` como o R4 403/400 e o marco. `enqueue` nao coalesce (~2697-2707), e `deferred` sem Retry-After e elegivel em todo `drain` (~3529-3532). Num projeto com esse defeito, cada `drain` reprocessa todos os eventos acumulados. A classe e a mesma ja aceita: spec, data-model e contratos nao exigem coalescencia (nada encontrado por grep), `deferred --> queued` no proximo `drain` e o comportamento especificado, e o estado aparece como `deferred=N`. A alternativa (`done`) era o defeito 25.1. **Segue LOW**, com o gatilho ampliado registrado.

| # | tipo | severidade | path | origem |
|---|------|------------|------|--------|
| 26.1 | partial | HIGH | `tests/cstk/test_jira-mutation.sh` (mutante da classificacao do `else` do chamador de `_js_reconcile_phase_label`) | FR-016 / task 25.1.2 |

Severidade calculada por `severity.sh` (partial + P1 + must-violated=false => HIGH). A classificacao e a mesma do 25.2 no ciclo 5 (FR-011).

Cobertura de FR-020..FR-025, de ponta a ponta:

- FR-021, FR-023 e FR-024: sem gap.
- FR-020: fechado, inclusive o guard de mutation.
- FR-022: codigo fechado (carry-forward e classificacao no chamador). Falta so o guard de mutation da 26.1.
- FR-025: so o residual LOW de dec-095(a).

Suites rodadas uma a uma nesta onda, com `JIRA_IO_BACKOFF_SECONDS=0 LC_ALL=C`: test_jira-sync 117/117, test_jira-mutation 24/24, test_jira-map 44/44, test_jira-setup 41/41, test_jira-config 36/36, test_jira-tasks 29/29, test_jira-io 129/129, test_posttooluse-jira-sync 21/21.

Gate MUST: `extract-must --coverage` => 5 principios, 0 so por heading, `cobertura de MUST: ok`. Os residuais R1/R2 do r01 seguem inalterados (LOW, documentacao).
<!-- converge-status: outcome=actionable; provenance=gate; at=2026-09-27T21:09:47Z; actionable=1; tasks-digest=d39413f3a9d5 -->

## Round r02 — Ciclo 7 (onda-031) — actionable

Conferencia da FASE 26 no CODIGO e nos testes:

| achado c6 | veredito | evidencia |
|-----------|----------|-----------|
| 26.1 | fechado | `test_jira-mutation.sh`: `scenario_mutation_25_1_1_drain_phase_label_caller_classification` (~1038-1138). Guarda `mutant_stale` (~1087-1088, padrao `_jspr_phl_ec=$?`). Mutacao multi-linha via python3 com `assert old in content` (~1089-1116). Checagem de aplicacao (~1117-1121: rc do python3 e `_jspr_phl_ec=$?` ausente). Controle no original (~1074-1081: 6 chamadas e `e1` = `auth_failed`). Mutante com outbox reenfileirado (~1124-1136: `e1` MUST NOT ser `auth_failed`). O padrao da mutacao casa o bloco real de `jira-sync.sh` ~3031-3041. Suite 25/25 nesta onda, `ok 20` e este cenario. A onda-030 so tocou `tasks.md` e `test_jira-mutation.sh` (`git diff --stat aaf077e c16995c`); `plugins/cstk-jira/scripts/*` nao mudou |

Varredura de fechamento: tarefas `[x]` das FASES 15-26 que exigem mutation, com o cenario correspondente.

| tarefa | cenario | suite |
|--------|---------|-------|
| 16.1.5 | `scenario_mutation_16_1_5_validate_version_name_allowlist` | test_jira-mutation |
| 16.2.5 | `scenario_mutation_16_2_5_milestone_round_divergence_check` | test_jira-mutation |
| 16.3.7 | `scenario_mutation_16_3_7_milestone_put_current_downgrade` | test_jira-mutation |
| 16.4.7 | `scenario_mutation_16_4_7_milestone_id_known_sec10` | test_jira-mutation |
| 17.1.4 | `scenario_mutation_17_1_4_label_allowlist` | test_jira-mutation |
| 17.3.6 | `scenario_mutation_17_3_6_phase_label_sec10` | test_jira-mutation |
| 18.1.4 | `scenario_mutation_18_1_4_check_link_type_membership` | test_jira-mutation |
| 18.2.4 | `scenario_mutation_18_2_4_resolve_link_type_ambiguity_picks_first` | test_jira-mutation |
| 18.3.5 | `scenario_mutation_18_3_5_link_put_stale_never_disappears` | test_jira-mutation |
| 18.4.7 | `scenario_mutation_18_4_7_links_idempotency_skips_active` | test_jira-mutation |
| 19.1.8 / 19.1.9 | `scenario_mutation_19_1_9_sec9_uso_unico` | test_jira-mutation |
| 19.2.4 | `scenario_mutation_19_2_4_project_create_dupla_condicao` | test_jira-mutation |
| 20.1.5 | `scenario_mutation_20_1_5_resolve_path_grava_na_principal` | test_jira-config |
| 21.1.2 | **ausente** | nenhuma |
| 21.2.2 | **ausente** | nenhuma |
| 21.4.2 | `scenario_mutation_21_4_2_remove_enum_check_fails` | test_jira-config |
| 21.5.3 | `scenario_mutation_21_5_3_check_field_support_ignora_stdin` | test_jira-setup |
| 22.1.3 | **ausente** | nenhuma |
| 22.2.2 | **ausente** | nenhuma |
| 23.1.3 | oraculo declarado era mutante EQUIVALENTE (ciclo 4). O mutante efetivo e `scenario_mutation_24_1_4_reconcile_phase_label_http_status`, e o comentario foi corrigido na 24.1.4 | test_jira-mutation |
| 24.1.3 | `scenario_mutation_24_1_1_reconcile_epic_milestone_http_status` + `scenario_mutation_24_1_2_drain_epic_milestone_caller_guard` | test_jira-mutation |
| 24.2.2 | `scenario_mutation_24_2_1_process_one_event_carryforward` | test_jira-mutation |
| 24.3.3 | `scenario_mutation_24_3_1_maybe_update_mapped_issue_http_status` | test_jira-mutation |
| 24.4.2 | `scenario_mutation_24_4_1_cmd_links_r17_http_status` | test_jira-mutation |
| 24.5.2 | `scenario_mutation_24_5_1_process_reconcile_event_items_bare_assignment` | test_jira-mutation |
| 25.1.2 / 26.1.1 | `scenario_mutation_25_1_1_drain_phase_label_caller_classification` | test_jira-mutation |

Nas 4 ausencias, a tarefa aponta `tests/cstk/test_jira-sync.sh`, e essa suite nao tem nenhum cenario de mutacao. Todos os mutantes de `jira-sync.sh` ficam em `test_jira-mutation.sh`. Dois comentarios de teste afirmam o oraculo sem executa-lo: ~1359-1364 (21.1.2) e ~3344-3349 (22.1.3). Na 23.1.3, um oraculo afirmado e nao executado se revelou falso.

Discriminacao medida nesta onda com copias mutadas do plugin fora do repo. `REPO_ROOT` aponta para a copia, e so o cenario roda, pelo `_SCENARIOS` do harness:

| tarefa | mutante | cenario | original | mutante |
|--------|---------|---------|----------|---------|
| 21.1.2 | `jira-sync.sh` ~829-830: leitura das 2 chaves do R6 GET vira atribuicao vazia | `scenario_resolve_keep_jira_fecha_registro_e_encerra_evento_conflict_do_outbox` | ok | not ok |
| 21.2.2 | ~1607: `visibility_or_disabled` vira `linking_disabled` e seta `_jsl_linking_disabled=yes` (cascata) | `scenario_links_404_r17_isolado_vira_unrepresentable_por_aresta_sem_cascata` | ok | not ok |
| 22.1.3 | ~1270: guarda `blocked` vira `if false` | `scenario_milestone_ensure_blocked_repetido_zero_chamadas` | ok | not ok |
| 22.2.2 | ~861: ramo `overwrite` vira `if false` (re-deriva como `keep_jira`) | `scenario_resolve_overwrite_label_drift_sem_phase_reaplica_fase_local` | ok | not ok |

Os 4 testes de comportamento discriminam hoje. Falta so o guard de regressao, a mesma classe do 25.2 e do 26.1.

| # | tipo | severidade | path | origem |
|---|------|------------|------|--------|
| 27.1 | partial | HIGH | `tests/cstk/test_jira-mutation.sh` (mutante do carry-forward de `_js_rebaseline_marker`) | FR-022 / task 21.1.2 |
| 27.2 | partial | HIGH | `tests/cstk/test_jira-mutation.sh` (mutante da cascata do R17 404 em `_js_cmd_links`) | FR-025 / task 21.2.2 |
| 27.3 | partial | HIGH | `tests/cstk/test_jira-mutation.sh` (mutante da guarda `blocked` de `milestone ensure`) | FR-020 / task 22.1.3 |
| 27.4 | partial | HIGH | `tests/cstk/test_jira-mutation.sh` (mutante do ramo `overwrite` de `label_drift`) | FR-022 / task 22.2.2 |

Severidade calculada por `severity.sh` (partial + P1 + must-violated=false => HIGH). A prioridade e a mesma do ciclo 1, que ligou 21.1/21.2 a US3 (P1). A classificacao repete a do 25.2 e do 26.1 (FR-011).

Revisao final de FR-020..FR-025 e dos residuais LOW. O codigo de `plugins/cstk-jira/` e o mesmo revisado no ciclo 6, e os vereditos daquele ciclo continuam valendo:

- FR-020: codigo fechado. Falta o guard 27.3.
- FR-021 e FR-023: sem gap.
- FR-022: codigo fechado. Faltam os guards 27.1 e 27.4.
- FR-024: sem gap. Guards 19.1.9 e 19.2.4 presentes.
- FR-025: codigo fechado. Falta o guard 27.2. O residual dec-095(a) segue.
- **dec-081** (`overwrite` de `milestone_drift` igual a `keep_jira`), **dec-088** (R4 404/422 e R6 PUT 400/404 em passthrough), **dec-095 (a)** (R17 400 retentado), **dec-095 (b)** (reconcile `deferred` acumulando, com o gatilho ampliado pela 25.1.1) e **dec-095 (c)** (`maybe_update` com 401): nenhum codigo tocado desde o ciclo 6. Seguem LOW.
- **dec-099**: registrada no ciclo 6. Nenhum codigo tocado, segue LOW.

Suites rodadas uma a uma nesta onda, com `JIRA_IO_BACKOFF_SECONDS=0 LC_ALL=C`, todas com exit 0: test_jira-mutation 25/25, test_jira-sync 117/117, test_jira-map 44/44, test_jira-setup 41/41, test_jira-config 36/36, test_jira-tasks 29/29, test_jira-io 129/129, test_posttooluse-jira-sync 21/21.

Gate MUST: `extract-must --coverage` => 17 ocorrencias, 5 linhas reconhecidas, 5 principios (I, II, III, IV, VI), 0 so por heading, `cobertura de MUST: ok`. Principio II honrado: em `jira-sync.sh`, `sqlite3` so aparece em usage e comentarios (~239, ~424, ~432, ~3988). Os residuais R1/R2 do r01 seguem inalterados (LOW, documentacao).
<!-- converge-status: outcome=actionable; provenance=gate; at=2026-09-27T21:37:17Z; actionable=4; tasks-digest=de6339141e6b -->

## Round r02 — Ciclo 8 (onda-033) — clean

Conferencia da FASE 27 no CODIGO e nos testes:

| achado c7 | veredito | evidencia |
|-----------|----------|-----------|
| 27.1 | fechado | `test_jira-mutation.sh` ~1844-1916 `scenario_mutation_21_1_2_rebaseline_marker_carryforward`. Guarda `mutant_stale` ~1876-1879 (as 2 leituras `_jrm_written_fixver=$(printf`/`_jrm_written_phase_label=$(printf`). Mutacao via python3 com `assert old in content` ~1880-1893, que troca as 2 linhas juntas. Checagem de aplicacao ~1894-1898. Controle no original ~1861-1871: 3 chamadas, R6 PUT preserva `10099`/`phase-3`. Mutante ~1906-1914: as 2 chaves MUST ficar `AUSENTE`. O padrao casa `jira-sync.sh:829-830` |
| 27.2 | fechado | ~1932-2023 `scenario_mutation_21_2_2_links_r17_404_sem_cascata`. Guarda ~2002-2003, mutacao sed ~2004-2005, checagem ~2006-2007. Controle ~1984-1997: `linking=enabled`, `links_active=2`, `links_unrepresentable=1`, 3 chamadas, nenhuma linha `linking_disabled`. Mutante ~2013-2021: MUST NOT `links_active=2` e MUST NOT 3 chamadas. O padrao casa `jira-sync.sh:1607` |
| 27.3 | fechado | ~2033-2075 `scenario_mutation_22_1_3_milestone_ensure_blocked_guard`. Guarda ~2062-2063, mutacao `if false; then` ~2064-2065, checagem ~2066-2067. Controle ~2049-2057: exit 7 nas 2 chamadas, total de chamadas continua 3. Mutante ~2070-2073: total MUST NOT continuar 3. O padrao casa `jira-sync.sh:1270` |
| 27.4 | fechado | ~2087-2152 `scenario_mutation_22_2_2_overwrite_label_drift_reaplica_fase_local`. Guarda ~2130-2131, mutacao ~2132-2133, checagem ~2134-2135. Controle ~2114-2124: 4 chamadas, R2 `[{"add":"phase-5"}]`, marker `phase-5`. Mutante ~2143-2150: 3 chamadas, `written_phase_label` `AUSENTE`. O padrao casa `jira-sync.sh:861` |

Helper `_make_curl_stub_seq` (~142-196): usa diretorio (`bin-seq`) e mapa (`io-curl-map-seq`) proprios. Consome em FIFO a 1a linha do mapa que casa a URL e a remove em seguida. Quando a URL aparece uma unica vez, o efeito e o mesmo de `_make_curl_stub`. `_make_curl_stub` (~99-140) nao mudou: `git diff 8cb8553 0f5b83f` na suite tem so 2 hunks, ambos de insercao pura (`@@ -139,6 +139,62 @@` e `@@ -1773,4 +1829,326 @@`). Nenhuma outra suite usa o helper. `git diff c16995c HEAD -- plugins/` vem vazio, e `git diff e88ce0c HEAD -- plugins/` tambem: o codigo do plugin e o mesmo desde a onda-028.

Suite `JIRA_IO_BACKOFF_SECONDS=0 LC_ALL=C sh tests/cstk/test_jira-mutation.sh`: exit 0, 29/29, zero `not ok`, `ok 13`-`ok 16` sao os 4 cenarios novos. Os 25 cenarios anteriores seguem `ok`, entao nenhum teste existente mudou de comportamento. Desde `aaf077e`, `test_jira-mutation.sh` e o unico arquivo alterado em `tests/` e `plugins/`, e por isso as demais suites nao foram re-rodadas. As contagens do ciclo 7 continuam validas.

Varredura de fechamento das FASES 15-27: extracao por bloco de tarefa (inclui as linhas de continuacao) de toda tarefa com mutation/mutante. 36 tarefas, todas `[x]`. Cada uma tem cenario definido (`^scenario_mutation_<id>()`), ou e a propria tarefa que cria o cenario:

- 24 cenarios em `test_jira-mutation.sh`: 16.1.5, 16.2.5, 16.3.7, 16.4.7, 17.1.4, 17.3.6, 18.1.4, 18.2.4, 18.3.5, 18.4.7, 19.1.3/19.1.8/19.1.9 (-> 19_1_9), 19.2.4, 21.1.2, 21.2.2, 22.1.3, 22.2.2, 23.1.3/24.1.4 (-> 24_1_4), 24.1.3 (-> 24_1_1 + 24_1_2), 24.2.2 (-> 24_2_1), 24.3.3 (-> 24_3_1), 24.4.2 (-> 24_4_1), 24.5.2 (-> 24_5_1), 25.1.2/26.1.1 (-> 25_1_1).
- 2 em `test_jira-config.sh`: 20.1.5, 21.4.2.
- 1 em `test_jira-setup.sh`: 21.5.3.
- 25.2.1 e 27.1.1-27.4.1 sao as tarefas que criam os cenarios.
- 20.4.3 so cita cenarios no texto e nao exige mutacao.

**Zero ausencias.**

Revisao final de FR-020..FR-025. O codigo de `plugins/cstk-jira/` nao mudou desde a onda-028, entao os vereditos de codigo do ciclo 6/7 seguem validos, agora com os guards presentes:

- FR-020: fechado. O guard 27.3 existe.
- FR-021 e FR-023: sem gap.
- FR-022: fechado. Os guards 27.1 e 27.4 existem.
- FR-024: sem gap (19.1.9, 19.2.4).
- FR-025: fechado. O guard 27.2 existe.
- Residuais LOW aceitos, nenhum codigo tocado: **dec-081**, **dec-088**, **dec-095 (a/b/c)**, **dec-099**, **dec-105**. Seguem LOW.
- Nota LOW nova, sem gap: em 27.2, `mutant_run` exige exit 0 do mutante. Se o mutante mudar de exit, o cenario falha ruidosamente, nunca em silencio. Conservador, nenhuma acao.

Gate MUST: `extract-must` => I, II, III, IV, VI (exit 0). `--coverage`:

```
fontes declaradas: docs/constitution.md
ocorrencias da palavra MUST no arquivo (contagem independente): 17
linhas de regra MUST reconhecidas pelo parser: 5
principios emitidos: 5
principios emitidos so por rotulo de heading (sem regra MUST lida): 0
cobertura de MUST: ok
```

Achados acima de LOW: 0. missing 0 | partial 0 | contradicts 0 | unrequested 0. Nenhuma fase apendada: feature convergida no round r02.
<!-- converge-status: outcome=clean; provenance=gate; at=2026-09-27T22:18:15Z; actionable=0; tasks-digest=2d0fcfd15088 -->
