# Schema EN Migration — Frozen Naming Map & Idiom

> **Status**: FROZEN (congelado). Esta é a fonte única de verdade para a
> migração pt-BR → EN das chaves do `state.json`. Os agentes do workflow da
> Fase 3 consomem APENAS este documento para nomes canônicos — não inventam.

## 1. Decisão

Migrar os **nomes de chave** (keys) do `state.json` de pt-BR para inglês,
uniformizando com os verbos de subcomando que já são EN (`init`, `check`,
`start`, `register`, `acquire`…). Resolve a "mistura" pt/en sinalizada
(gatilho: `drift.sh extract` vs `drift.sh aspectos`).

**Mecanismo — canonicalização centralizada + fallback pontual** (NÃO espalhar
`(.en // .pt)` em 747 sítios):

- `state-rw.sh` ganha `_sr_canonicalize` — um filtro jq que renomeia chaves
  pt→en recursivamente (mapa **context-free**, ver §5). Aplicado em **write**
  (o arquivo converge para EN a cada escrita) e em **read/get** (callers veem
  EN).
- **Direct-jq-on-file readers** (scripts que fazem `jq … "$state_file"` sem
  passar por `state-rw.sh`): query em path EN **+ fallback `(.en // .pt)`** só
  nos campos que tocam, OU roteiam via `state-rw.sh read | jq`.
- `cli/lib/recall.sh` (ingestão da knowledge.db, confined-deps): fallback
  `(.en // .pt)` nas leituras de `state.json`. **Colunas da knowledge.db
  permanecem inalteradas** (insula o cstk-panel; evita migração de DB).

**Convergência EN-on-disk (resolve o doc-misto dos direct-writers).** Um
direct-writer que faz `jq '.waves += [...]'` sobre um state pt-BR vivo criaria
doc misto (`.ondas` + `.waves`). Solução escolhida (arquitetura B+, sem helper
compartilhado): garantir que o state já esteja EM EN no disco antes de qualquer
direct-writer rodar. Dois mecanismos:
- **`state-rw.sh migrate --state-dir DIR`** — canonicaliza um state pt-BR → EN
  no lugar (idempotente; backup pt-BR em `state-history/`). Usado no rollout
  (migrar os 17 states vivos) e exposto para o usuário.
- **Migrate defensivo no command-pai**: `/feature-00c[-resume]` e `/agente-00c
  [-resume]` chamam `state-rw.sh migrate` no início de CADA onda (one-liner),
  ANTES de spawnar o orquestrador. Assim os direct-writers (state-ondas,
  state-decisions, …) sempre veem EN.

Consequência para o sweep: **direct-writers [wf] só renomeiam** pt→en no jq
deles — NÃO precisam canonicalizar-base-primeiro nem sourçar helper. `state-rw`
(read/get/set/write) já é self-healing via `_sr_canonicalize_file`.

**Não-breaking**: pt aceito na entrada, EN canônico na saída. Remoção do
suporte pt = **próxima MAJOR** (basta dropar as regras do mapa em
`_sr_canonicalize` + os fallbacks). **SemVer desta migração: MINOR** (aditivo).

## 2. Escopo

| | Item | Nesta migração? |
|---|---|---|
| ✅ | Nomes de chave do `state.json` (todos os containers) | **SIM** |
| ✅ | Subcomando `drift.sh aspectos` → `key-aspects` (alias `aspectos` deprecado) | **SIM** |
| ✅ | `drift.sh extract --text` (extrator real — hoje fantasma no doc) | **SIM** (cria) |
| ✅ | `state-rw.sh init` modo-feature (determinístico, fim do recipe multi-passo) | **SIM** |
| ⏭️ | **Nomes de flag CLI** (`--decisao-id`→`--decision-id`, `--justificativa`→`--rationale`…) | **FOLLOW-UP A** |
| ⏭️ | **Valores de enum** (`status: em_andamento/aguardando_humano/concluida`, `motivo_termino: …`) | **FOLLOW-UP B** |
| ✅ | **Colunas da knowledge.db** (`executions.*`, `waves.*`, `decisions.*`, `blocks.*`, `suggestions.*`, etc.) | **EM ESCOPO** (decisão do operador) — DB é derivado/recriável; bump `schema_meta` + `--reindex` reconstrói. **cstk-panel = tarefa do operador** (165 refs em outro repo). |
| ⏭️ | **Keys de OUTPUT de relatório/agregação** (`model-routing-report.sh` `por_modelo_aplicado`/`divergencias_*`/`selecoes_*`; `report.sh`; `decision-tree`) | **FOLLOW-UP D** |

**Por que as 3 camadas adjacentes ficam para follow-up (mesmo padrão de alias):**
são separáveis e de risco distinto.
- **(A) Flags** acoplam aos call-sites nos orquestradores (.md).
- **(B) Valores de enum** acoplam a `case`-matching em ~15 scripts + os 17
  states vivos + a normalização na ingestão (`status`/`motivo_termino`).
- **(C) Colunas da knowledge.db** exigem bump de schema do DB + `--reindex`
  global de TODOS os projetos + mudança no cstk-panel. Mantê-las pt-BR e
  mapear `state.json`(EN) → coluna(pt) na ingestão **insula o painel por
  construção**.

Bundlar tudo numa tacada multiplica o risco. Esta migração entrega a camada de
**schema persistido do `state.json`** (keys) inteira; A/B/C seguem com o mesmo
mecanismo de alias, cada uma no seu passe.

> Se o operador quiser A, B e/ou C JÁ neste passe, reabrir o escopo aqui antes
> da Fase 3.

## 3. Mapa canônico FROZEN (pt-BR → EN)

Regra geral: `snake_case`. `(keep)` = já EN ou neutro, não renomear.
**Valores** (à direita de `:`) NUNCA são tocados nesta migração.

### 3.1 Top-level

| pt-BR | EN |
|---|---|
| `schema_version` | (keep) |
| `execucao` | `execution` |
| `etapa_corrente` | `current_stage` |
| `proxima_instrucao` | `next_instruction` |
| `ondas` | `waves` |
| `decisoes` | `decisions` |
| `bloqueios_humanos` | `human_blocks` |
| `orcamentos` | `budgets` |
| `metricas_acumuladas` | `accumulated_metrics` |
| `whitelist_urls_externas` | `external_urls_whitelist` |
| `historico_movimento_circular` | `circular_movement_history` |
| `aspectos_chave_iniciais` | `initial_key_aspects` |
| `aspectos_chave_tecnicos` | `technical_key_aspects` |
| `aspectos_chave_operacionais` | `operational_key_aspects` |
| `pre_requisitos` | `prerequisites` |
| `tasks` | (keep) |

### 3.2 `execution.*`

| pt-BR | EN |
|---|---|
| `id` | (keep) |
| `projeto_alvo_path` | `target_project_path` |
| `projeto_alvo_descricao` | `target_project_description` |
| `stack_sugerida` | `suggested_stack` |
| `status` | (keep — valor pt fica) |
| `motivo_termino` | `termination_reason` |
| `iniciada_em` | `started_at` |
| `terminada_em` | `finished_at` |

### 3.3 `waves[].*` (state-ondas.sh)

| pt-BR | EN |
|---|---|
| `id` | (keep) |
| `inicio` | `started_at` |
| `fim` | `finished_at` |
| `etapas_executadas` | `executed_stages` |
| `tool_calls` | (keep) |
| `wallclock_seconds` | (keep) |
| `motivo_termino` | `termination_reason` |
| `proxima_onda_agendada_para` | `next_wave_scheduled_for` |
| `skills_invoked` | (keep) |

`waves[].skills_invoked[].*`: `skill` (keep), `timestamp` (keep),
`decisao_id` → `decision_id`.

`waves[].aspectos_chave_tocados` → `touched_key_aspects` (MAP-GAP achado no
freeze de drift.sh — escrito por `mark-touched`, lido pelo drift lib).

### 3.4 `tasks[].*` (state-ondas.sh record-task)

| pt-BR | EN |
|---|---|
| `task_id` | (keep) |
| `outcome` | (keep) |
| `titulo` | `title` |
| `wave_id` | (keep) |
| `testes_rodados` | `tests_run` |
| `testes_passados` | `tests_passed` |
| `lint_ok` | (keep) |
| `arquivos_tocados` | `touched_files` | (chave persistida; o flag `--arquivos` fica — follow-up A) |
| `origem` | `source` |

### 3.5 `decisions[].*` (state-decisions.sh)

| pt-BR | EN |
|---|---|
| `id` | (keep) |
| `onda_id` | `wave_id` |
| `timestamp` | (keep) |
| `etapa` | `stage` |
| `agente` | `agent` |
| `contexto` | `context` |
| `opcoes_consideradas` | `options_considered` |
| `escolha` | `choice` |
| `justificativa` | `rationale` |
| `score_justificativa` | `justification_score` | (chave real do score 0-3; `--score` é o flag) |
| `evidencia` | `evidence` |
| `referencias` | `references` |
| `artefato_originador` | `originating_artifact` |

### 3.6 `human_blocks[].*` (bloqueios.sh)

| pt-BR | EN |
|---|---|
| `id` | (keep) |
| `decisao_id` | `decision_id` |
| `pergunta` | `question` |
| `contexto_para_resposta` | `context_for_answer` |
| `opcoes_recomendadas` | `recommended_options` |
| `status` | (keep — valor pt fica) |
| `resposta_humana` | `human_answer` |
| `respondido_em` | `answered_at` |
| `disparado_em` | `triggered_at` |

### 3.7 `budgets.*`

| pt-BR | EN |
|---|---|
| `recursividade_max` | `max_recursion` |
| `profundidade_corrente_subagentes` | `current_subagent_depth` |
| `retro_execucoes_max_por_feature` | `max_retro_executions_per_feature` |
| `retro_execucoes_consumidas` | `retro_executions_consumed` |
| `ciclos_max_por_etapa` | `max_cycles_per_stage` |
| `ciclos_consumidos_etapa_corrente` | `cycles_consumed_current_stage` |
| `tool_calls_threshold_onda` | `tool_calls_threshold_wave` |
| `wallclock_threshold_segundos` | `wallclock_threshold_seconds` |
| `estado_size_threshold_bytes` | `state_size_threshold_bytes` |
| `tool_calls_onda_corrente` | `tool_calls_current_wave` |
| `inicio_onda_corrente` | `current_wave_start` |

### 3.8 `accumulated_metrics.*`

| pt-BR | EN |
|---|---|
| `ondas_total` | `waves_total` |
| `tool_calls_total` | (keep) |
| `tempo_wallclock_total_segundos` | `wallclock_total_seconds` |
| `profundidade_max_atingida` | `max_depth_reached` |
| `subagentes_spawned` | `subagents_spawned` |
| `decisoes_total` | `decisions_total` |
| `bloqueios_humanos_total` | `human_blocks_total` |
| `sugestoes_skills_globais_total` | `global_skill_suggestions_total` |
| `issues_toolkit_abertas` | `toolkit_issues_opened` |

### 3.9 `prerequisites.*` (feature-00c)

| pt-BR | EN |
|---|---|
| `briefing.{path,sha256}` | (keep) |
| `constitution.{path,sha256,version}` | (keep) |
| `ratificados_em` | `ratified_at` |

### 3.9b `suggestions[]` (`sugestoes` — suggestions.sh; ground-truth em state.json)

Container **`sugestoes` → `suggestions`**. Folhas:

| pt-BR | EN |
|---|---|
| `id` | (keep) |
| `skill_afetada` | `affected_skill` |
| `diagnostico` | `diagnosis` |
| `severidade` | `severity` |
| `proposta` | `proposal` |
| `referencias` | `references` |
| `issue_aberta` | `issue_opened` |
| `criada_em` | `created_at` |

> `severidade` VALUES (`informativa|aviso|impeditiva`) NÃO mudam (follow-up B).
> `issue.sh` é READER de `.suggestions[]` (fallback). (MAP-GAP do batch 1.)

### 3.9c `circular_movement_history[]` (circular.sh)

| pt-BR | EN |
|---|---|
| `problema_hash` | `problem_hash` |
| `solucao_hash` | `solution_hash` |
| `timestamp` | (keep) |

(MAP-GAP do batch 1; folhas do buffer de detecção de movimento circular.)

### 3.9d cache (state-cache.sh) + escalada (model-routing.sh)

`escalada_modelo_pendente` → `pending_model_escalation` (bool top-level; escrito
pelo orquestrador via `state-rw set`, lido por model-routing.sh com fallback).

Subsistema de cache (`.briefing_cache`, `.constitution_cache`,
`.accumulated_metrics.cache`). Containers já EN (`briefing_cache`,
`constitution_cache`, `cache`) e folhas `source_path`/`source_sha256`/
`source_chars`/`tokens_cache_*` = (keep). Renomear:

| pt-BR | EN |
|---|---|
| `resumo` | `summary` |
| `resumo_chars` | `summary_chars` |
| `resumo_max_chars` | `summary_max_chars` |
| `estrategia` | `strategy` |
| `gerado_em` | `generated_at` |
| `gerado_na_onda` | `generated_in_wave` |
| `tokens_economizados_estimados` | `estimated_tokens_saved` |

> `estrategia` VALUES (`resumo|passthrough|desabilitado`) NÃO mudam (follow-up
> B). Par coordenado: `state-cache.sh` (writer) ↔ `state-validate.sh` (reader).
> (MAP-GAP do batch 2 — deferido corretamente pelos agentes.)

### 3.11 Colunas da knowledge.db (recall.sh — EM ESCOPO, decisão do operador)

DB derivado/recriável → bump `RECALL_SCHEMA_VERSION` 6→**7** e, no boot do
schema, se `schema_meta.schema_version < 7`, **DROP de todas as tabelas + FTS**
antes do `CREATE TABLE IF NOT EXISTS` (rename de coluna NÃO passa por
`IF NOT EXISTS`). `--reindex`/próximo ingest repopula. Sem perda (fonte =
state.json). Atualizar: DDL, INSERTs, `ON CONFLICT … SET`, SELECTs (search/read/
context), e os `--arg` jq que alimentam as colunas.

- **Universal (todas as tabelas)**: `execucao_id` → `execution_id`.
- **Tabela `bloqueios` → `blocks`**; valor FTS `type='bloqueio'` → `'block'`;
  `cstk recall --type` aceita `block` (novo) + `bloqueio` (alias deprecado).
- **`decisions`**: `agente→agent`, `etapa→stage`, `escolha→choice`,
  `opcoes→options`, `contexto→context`, `justificativa→rationale`,
  `evidencia→evidence` (`score`, `source_*` keep).
- **`blocks`**: `pergunta→question`, `contexto_para_resposta→context_for_answer`,
  `resposta→answer`, `decisao_id→decision_id`, `disparado_em→triggered_at`,
  `respondido_em→answered_at`, `latencia_segundos→latency_seconds`.
- **`retros`**: `texto→text`. **`skills`**: `decisao_id→decision_id`.
- **`executions`**: `motivo_termino→termination_reason`,
  `etapa_corrente→current_stage`, `iniciada_em→started_at`,
  `terminada_em→finished_at`, `duracao_segundos→duration_seconds`,
  `stack_sugerida→suggested_stack`, `ondas_total→waves_total`,
  `wallclock_total_segundos→wallclock_total_seconds`,
  `subagentes_spawned→subagents_spawned`, `profundidade_max→max_depth`,
  `decisoes_total→decisions_total`, `bloqueios_humanos_total→human_blocks_total`,
  `sugestoes_skills_total→skill_suggestions_total`,
  `issues_toolkit_abertas→toolkit_issues_opened` (`tool_calls_total` keep).
- **`waves`**: `etapas→stages`, `inicio→started_at`, `fim→finished_at`,
  `motivo_termino→termination_reason`, `n_etapas→n_stages` (`n_skills`,
  `wallclock_seconds`, `tool_calls` keep).
- **`alert_signals`**: `tipo→type`, `subtipo→subtype`,
  `valor_consumido→consumed_value`, `valor_threshold→threshold_value`,
  `descricao→description`.
- **`tasks`**: `titulo→title`, `testes_rodados→tests_run`,
  `testes_passados→tests_passed`, `arquivos_tocados→touched_files`.
- **`events`**: `descricao→description`. **`memories`**: já EN (keep).
- **`suggestions`**: `skill_afetada→affected_skill`, `severidade→severity`,
  `diagnostico→diagnosis`, `proposta→proposal`, `referencias→references`,
  `issue_aberta→issue_opened`.

> Os nomes batem com o mapa §3 do state.json (a coluna recebe o MESMO nome EN
> do campo que a alimenta) — exceto as recall-específicas acima.

### 3.9e events + chaves do orquestrador raiz (MAP-GAPs do batch 4)

- `eventos` → `events` (container top-level `.events[]`, camada B; escrito por
  AMBOS orquestradores — batch 4 pegou um split-key: o feature-orch escrevia
  `.eventos` enquanto o orch já usava `.events`). Folha `descricao` → `description`.
- `tipo_invocacao` → `invocation_type` (`.execution.invocation_type`).
- `proximo_marco_retrospectiva` → `next_retrospective_milestone` (top-level).

> **Prompt-protocol FORA de escopo** (como flags): os campos do contrato de
> prompt asker↔orquestrador↔answerer (`perguntas`, `pergunta`, `contexto`,
> `opcoes_recomendadas`, `rotulo`, `decisoes_anteriores`) NÃO são chaves do
> `state.json` — são o JSON de comunicação entre subagentes. Renomear exigiria
> sincronizar asker+answerer+orquestrador juntos; deferido (agentes do batch 4
> corretamente não tocaram). O orquestrador mapeia esses campos para as chaves
> EN do `state.json` (`human_blocks[].question` etc.) ao persistir.

### 3.10 Regra para folhas NÃO listadas

Se um agente encontrar uma chave pt-BR não mapeada acima: traduzir para
`snake_case` EN óbvio E emitir uma linha `MAP-GAP: <pt> -> <en-proposto> @<arquivo>`
no retorno, para ratificação humana. **Nunca** inventar silenciosamente um
nome que outro script possa também usar com nome divergente.

## 4. Idiom (regras para os agentes da Fase 3)

1. **Writers** (objetos jq construídos no script — `jq -n '{…}'`,
   `jq '.waves += [{…}]'`): emitir chaves **EN**. NÃO canonicalizar-base-
   primeiro nem sourçar helper — o state já chega EN no disco (migrate
   defensivo do command-pai + rollout). Só renomear pt→en no jq.
2. **Readers via `state-rw.sh get/read`**: usar paths **EN** (o canonicalizer
   garante EN).
3. **Direct-jq-on-file readers** (`jq '…' "$state_file"`): paths EN **+
   fallback** `(.en // .pt)` nos campos lidos. Ex.:
   `jq '(.current_stage // .etapa_corrente)'`.
4. **Flags CLI**: NÃO renomear nesta migração (follow-up). Manter `--decisao-id`
   etc. como estão.
5. **Valores de enum**: NUNCA traduzir (`status`, `motivo_termino`, nomes de
   etapa permanecem).
5b. **Keys de OUTPUT de relatório/agregação** (jq que CONSTRÓI um objeto/relatório
   emitido em **stdout**, não escrito em `state.json` — ex.: `model-routing-
   report.sh aggregate`, `report.sh`, `decision-tree`): NÃO migrar (follow-up D).
   Só migram chaves LIDAS DE ou ESCRITAS EM `state.json`. Distinção: o jq termina
   em `> state.json`/`atomic_write` (state) vs `printf`/stdout (output).
6. **Testes** (`tests/test_<n>.sh` ou `tests/cstk/test_<n>.sh`): atualizar
   fixtures/asserts para EN **E manter ≥1 fixture pt-BR** por script provando
   que o fallback/canonicalizer ainda lê (regressão de back-compat).
7. **Comentários e mensagens de log**: PODEM ficar em pt-BR (convenção do
   projeto: identificadores EN, prosa pt-BR OK).

## 5. `_sr_canonicalize` — mapa context-free

Verificação feita: **nenhuma** chave pt mapeia para EN diferente conforme o
contexto, e nenhum par pt→en colide entre containers (`motivo_termino` e
`decisao_id` aparecem em 2 containers mas com o MESMO destino). Logo o
canonicalizer pode ser um **rename plano** aplicado recursivamente:

```sh
# pseudo: jq filter
walk(if type == "object"
     then with_entries(.key |= ($RENAME_MAP[.] // .))
     else . end)
```

`$RENAME_MAP` = o dicionário pt→en das tabelas §3.1–3.9 (só as linhas que NÃO
são `(keep)`). Removê-lo na próxima MAJOR torna o schema EN-only.

## 6. Arquivos NO blast radius (handler)

`[me]` = feito por mim em sequencial (lógica nova/sensível). `[wf]` = agente do
workflow (Fase 3). `[me]` exemplifica o padrão que os agentes `[wf]` seguem.

| Arquivo | Handler | Nota |
|---|---|---|
| `state-rw.sh` | **[me] ✅** | canonicalizer + init feature-mode + migrate + write/set/get — FEITO, testado |
| `drift.sh` | **[me] ✅** | `aspectos`→`key-aspects` + novo `extract` + aspect keys EN — FEITO, testado. **Exemplar do padrão reader-fallback/writer-EN.** |
| `cli/lib/recall.sh` | **[wf] ⚠️** | ALTO CUIDADO: fallback `(.en // .pt)` só nos jq READS de state.json; **NUNCA tocar nomes de coluna SQL** (`ON CONFLICT … SET col=excluded.col` em L816/864/1041/1105/1323 = FOLLOW-UP C). Verify adversarial diff do SQL. |
| `state-validate.sh` | [wf] | checagens de campo: EN + fallback |
| `state-ondas.sh`, `state-decisions.sh`, `bloqueios.sh`, `budget.sh`, `cycles.sh`, `circular.sh`, `retro.sh`, `spawn-tracker.sh`, `model-routing.sh`, `model-routing-report.sh`, `state-cache.sh`, `state-decisions-reconcile.sh`, `suggestions.sh`, `issue.sh`, `pipeline.sh`, `report.sh`, `feature-00c-preflight.sh`, `bash-guard.sh`, `secrets-filter.sh` | [wf] | aplicar mapa §3 + idiom §4 + atualizar test |
| `test_state-rw.sh`, `test_drift.sh` | [wf] | atualizar p/ EN + novos cenários (feature-init, migrate, extract, alias `aspectos`) — scripts já feitos por [me] |
| `global/agents/agente-00c-orchestrator.md`, `agente-00c-feature-orchestrator.md`, clarify-asker/answerer (×4) | [wf] | bash snippets + prosa. **Inclui fix do bug-origem**: orchestrator L166-173 + migrate defensivo no início da onda |
| `global/commands/*-00c*.md` (×6) | [wf] | bash snippets. **feature-00c.md §3**: usar a one-liner `state-rw.sh init --short-name …` que agora EXISTE + `drift.sh extract` real |
| contrato de schema (`docs/specs/_archived/agente-00c/contracts/state-schema.md`) | [me] | atualizar |
| `CHANGELOG.md`, `CLAUDE.md` | [me] | nota de migração + deprecação |

## 7. Fases

1. **Freeze** — este doc. ✅
2. **Núcleo `[me]`** — `state-rw.sh` (canonicalizer + init feature-mode) +
   `cli/lib/recall.sh` fallback + `state-validate.sh`. Com testes.
3. **Sweep `[wf]`** — workflow: 1 agente por script `[wf]` aplicando §3+§4 e
   atualizando seu `test_<n>.sh`; verificação adversarial; coletar `MAP-GAP:`.
4. **Ratificar `MAP-GAP`** — eu reviso folhas não-mapeadas que os agentes
   acharam; congelo no doc.
5. **Docs `[me]`** — orquestradores/commands (se não pegos no sweep), contrato,
   CHANGELOG, CLAUDE.md.
6. **Regressão `[me]`** — `./tests/run.sh` inteiro + ler os 17 `state.json`
   vivos via fallback (provar back-compat) + `cstk recall --reindex` smoke.

## 8. Verificações (fechadas pós-freeze)

- [x] `cli/lib/recall.sh` é o **único** arquivo em `cli/` que lê `state.json`
      direto. Lista exata de jq paths lidos → levantar no início da Fase 2
      (handler [me]).
- [x] knowledge.db usa colunas pt-BR (`etapa_corrente`, `motivo_termino`,
      `projeto_alvo`) → **mantidas** (FOLLOW-UP C). Ingestão mapeia
      `state.json`(EN, com fallback pt) → coluna(pt).
- [x] Contagem real ~**731** ocorrências (subconjunto distintivo: 747). Ordem
      de grandeza confirmada.
- [x] `cstk-panel` insulado **por construção**: lê a knowledge.db, cujas
      colunas não mudam neste passe.
