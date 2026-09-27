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
