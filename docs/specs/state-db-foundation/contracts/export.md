# Contract: Export derivado state.db → state.json (FR-007)

**Feature**: `state-db-foundation` | **Phase**: 1
**Status**: o *formato de destino* é fato verificável (é o `state.json` que
`state-rw.sh init` produz hoje e que `state-validate.sh` valida). A
*interface do comando de export* é `[PROPOSTA — a validar na implementação]`.

---

## Propósito

Manter os consumidores atuais do `state.json` funcionando sem reescrita
durante a transição (spec US3). O export é **derivado e descartável**: a
fonte de verdade é o `state.db`; regenerar o export nunca perde informação.

---

## Consumidores reais a preservar

Verificado por varredura do repo — scripts que leem `state.json`:

**Fora do runtime** (4): `cli/lib/recall.sh` (ingestão do knowledge.db),
`cli/lib/00c-bootstrap.sh`, `global/skills/model-selector/scripts/report.sh`,
`global/skills/decision-tree/scripts/render-decision-tree.sh`.

**Dentro do runtime** (~20), incluindo os 3 hooks provisionados por projeto:
`hooks/pretooluse-bash-guard.sh`, `hooks/posttooluse-agent-usage.sh`,
`hooks/posttooluse-tool-call-tick.sh`; e os scripts `cycles.sh`,
`circular.sh`, `retro.sh`, `pipeline.sh`, `bash-guard.sh`,
`guard-hooks-status.sh`, `otel-usage.sh`, `report.sh`, `secrets-filter.sh`,
além dos de estado já listados em [primitives.md](./primitives.md).

**Consumidor externo ao repo**: o painel `cstk-panel`, que lê o
`knowledge.db` (não o `state.json` diretamente) — logo é protegido
indiretamente, via FR-008/FR-009.

> **Consequência de escopo**: o export não é conveniência, é o que evita
> reescrever ~24 consumidores nesta fase. Qualquer divergência estrutural
> entre o export e o `state.json` nativo quebra consumidores silenciosamente.

---

## Contrato de saída

### E1 — Equivalência estrutural (MUST)

O export MUST produzir um documento JSON que:

1. Passa em `state-validate.sh --state-dir <dir>` com **exit 0** (spec US3
   AS-1). Esse script é o oráculo de conformidade — ele já valida
   `schema_version`, tipos dos campos obrigatórios, consistência
   `status` × `finished_at`, os tetos de `budgets`, os 5 campos de cada
   decisão e a integridade referencial dos bloqueios.
2. Declara `schema_version` igual ao do formato corrente (`"1.0.0"`).
3. Contém **todos** os campos de topo que `state-rw.sh init` cria:
   `schema_version`, `short_name` (só modo-feature), `execution`,
   `prerequisites` (só modo-feature), `current_stage`, `next_instruction`,
   `waves`, `decisions`, `human_blocks`, `budgets`, `accumulated_metrics`,
   `external_urls_whitelist`, `circular_movement_history`,
   `initial_key_aspects`, `atomic_commit_enabled` — mais os campos que os
   demais scripts acrescentam ao longo da execução: `tasks`, `events`,
   `suggestions`, `retros`, `briefing_cache`, `constitution_cache`,
   `push_pr_result`, `next_retrospective_milestone`.

### E2 — Fidelidade de nomes (MUST)

Nomes de campo e formatos de ID MUST ser preservados **literalmente**:

- IDs: `dec-NNN`, `block-NNN`, `onda-NNN` (3 dígitos, zero-padded).
- O campo de score da decisão é `justification_score` (a flag é `--score`;
  os nomes não coincidem — preservar o do campo).
- Campos de onda: `id`, `started_at`, `finished_at`, `executed_stages`,
  `tool_calls`, `wallclock_seconds`, `termination_reason`,
  `next_wave_scheduled_for`, `skills_invoked`, e quando presentes
  `agent_usage`, `agent_spawns`, `otel_usage`.
- Campos de task: `task_id`, `title`, `wave_id`, `outcome`, `tests_run`,
  `tests_passed`, `lint_ok`, `touched_files`, `recorded_at`, `source`.
- Campos de bloqueio: `id`, `decision_id`, `question`, `context_for_answer`,
  `recommended_options`, `status`, `human_answer`, `answered_at`,
  `triggered_at`.

Chaves em inglês (a canonicalização pt-BR→EN já é vigente via
`_SR_RENAME_MAP` em `state-rw.sh`). O export **não** reintroduz chaves
pt-BR — os consumidores já leem EN-first com fallback.

### E3 — Ordem e aninhamento (MUST)

- `waves`, `decisions`, `human_blocks`, `tasks`, `events` são **arrays**, na
  mesma ordem cronológica de hoje. Convenções que dependem disso e MUST ser
  preservadas: `.waves[-1]` é a onda corrente (usado por `wave-status`,
  `current-id`, `record-skill`); a ordem de `events` é a de append.
- `skills_invoked` volta a ser **aninhado dentro de cada onda**
  (`.waves[N].skills_invoked[]`), embora no banco seja tabela própria. A
  ingestão do recall lê exatamente esse caminho aninhado, filtrando
  `kind == "gate"`.
- Campos ausentes vs. nulos: `state-rw.sh init` omite as chaves
  `canonical_project`/`session_name` quando as flags não são passadas (a
  chave fica **ausente**, não `null`). O export MUST reproduzir essa
  distinção — `state-validate.sh` aceita "string ou ausente", e emitir
  `null` onde hoje há ausência muda o que os consumidores veem.

### E4 — Campos derivados (MUST)

`accumulated_metrics` é agregação (ver data-model.md): os totais MUST ser
computados a partir das tabelas no momento do export, não lidos de um
contador materializado. Campos: `waves_total`, `tool_calls_total`,
`wallclock_total_seconds`, `max_depth_reached`, `subagents_spawned`,
`decisions_total`, `human_blocks_total`, `global_skill_suggestions_total`,
`toolkit_issues_opened`, além dos acumuladores de agente
(`agent_spawns_total`, `agent_spawns_with_usage_total`,
`agent_tokens_total`, `agent_tool_use_count_total`,
`agent_duration_ms_total`).

Ganho colateral: hoje esses contadores são incrementados manualmente por
vários scripts e podem divergir da realidade. Derivá-los no export elimina
a divergência por construção.

### E5 — Frescor (MUST, SC-004)

O export MUST refletir uma mutação em **até 5 segundos** após ela ser
aplicada. Satisfeito trivialmente se o export for regenerado sob demanda.
**DECISÃO EM ABERTO (E5-a)**: gatilho do export — (a) sob demanda por
comando explícito; (b) automático ao fim de cada onda (`state-ondas.sh end`,
que já é o ponto onde o snapshot de `state-history/` é gerado); (c) ambos.
A opção (b) atende SC-004 e FR-013-INFRA-BACKUP no mesmo ponto de código.

### E6 — Falha de export não bloqueia a fonte de verdade (MUST)

Spec §Edge Cases, literal: *"o fechamento da onda no `state.db` não pode
ficar condicionado ao sucesso do export — a falha de export degrada, não
bloqueia a fonte de verdade"*.

Logo: falha ao gerar o export (disco cheio, interrupção) MUST ser reportada
em stderr e MUST NOT reverter nem impedir o commit da transação que fechou a
onda. O export é regenerável a qualquer momento a partir do banco.

### E7 — Filtro de segredos (MUST NOT alterar)

O export é o `state.json` **bruto** — o filtro de segredos permanece onde
está hoje: aplicado na geração de backup (`secrets-filter.sh for-backup`) e
na ingestão do recall. O export **não** aplica scrub por conta própria; se
aplicasse, o `state.json` derivado deixaria de ser equivalente ao nativo e
E1 quebraria.

---

## Interface do comando `[PROPOSTA]`

Duas formas possíveis, ambas compatíveis com C1 de
[primitives.md](./primitives.md):

**Opção A — reusar `state-rw.sh read`** (preferida): sob backend
`state.db`, `read` já precisa devolver o estado como JSON. O export vira
`state-rw.sh read --state-dir <dir> > state.json`, sem subcomando novo.
Vantagem: consumidores que hoje chamam `read` passam a funcionar sem
qualquer mudança.

**Opção B — subcomando dedicado** (ex.: `state-rw.sh export`): explícito
quanto à materialização em disco, ao custo de superfície nova.

Decidir na task de FR-007. Em ambos os casos, o oráculo de aceitação é o
mesmo: `state-validate.sh` sai 0 sobre o resultado.

---

## Cenário de aceitação (spec US3 AS-3)

> *Um consumidor que só sabe ler `state.json` não percebe diferença
> estrutural em relação a um `state.json` escrito diretamente pelo mecanismo
> atual.*

Teste operacional: gerar o export de um projeto migrado e comparar com o
`state.json` original **canonicalizado** (chaves ordenadas, whitespace
normalizado — ex. `jq -S .`). Diferença aceitável: nenhuma em nomes de
campo, IDs, valores ou aninhamento. Diferença tolerada: apenas formatação
não-semântica (indentação, ordem de chaves em objeto), já que nenhum
consumidor real depende da ordem de chaves de um objeto JSON.
