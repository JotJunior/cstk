# Data Model: wave-token-metrics

**Feature**: `wave-token-metrics` | **Date**: 2026-07-25 | **Spec**: [spec.md](./spec.md)

> **Legenda de veracidade (Constitution VI)**
> `[EXISTE]` — campo/coluna ja presente no codigo, com arquivo:linha.
> `[PROPOSTA]` — contrato novo desenhado aqui, a validar na implementacao.

---

## Visao geral do fluxo de dados

```
tool Agent completa
        |
        v
[hook PostToolUse matcher="Agent"]        <- le tool_response do stdin
        |
        v
<state-dir>/wave-agent-usage.jsonl        [PROPOSTA] sidecar append-only
        |                                    (hook NUNCA toca state.json)
        v
[state-ondas.sh end]                      <- agrega no fechamento da onda
        |
        v
state.json  .waves[].agent_usage          [PROPOSTA]
            .waves[].agent_spawns[]       [PROPOSTA]
            .accumulated_metrics.agent_*  [PROPOSTA]
        |
        +---> [report.sh]                 -> relatorio de execucao (FR-005)
        +---> [wave-usage-report.sh]      -> review-task §4.5 (FR-007)
        +---> [cstk recall --ingest]      -> knowledge.db waves.* (FR-006)
```

---

## Entity: Metrica de Uso de Spawn (`SpawnUsage`)

Registro do consumo observado de UM spawn de subagente. E a entidade central da
spec ("Metrica de Uso de Spawn"). Materializa-se em duas representacoes: uma
linha do sidecar JSONL (transitoria, por onda) e uma entrada de
`.waves[].agent_spawns[]` (persistente).

### Campos

| Campo | Tipo | Obrigatorio | Origem | Notas |
|-------|------|-------------|--------|-------|
| `agent_id` | string | sim | `tool_response.agentId` `[EXISTE no harness]` | Identificador da run do subagente. Chave natural do spawn. |
| `agent_type` | string \| null | nao | `tool_input.subagent_type` `[EXISTE no harness]` | Ex.: `feature-00c-clarify-asker`. Null se ausente. |
| `status` | enum | sim | derivado de `tool_response.status` | `completo` \| `parcial` \| `indisponivel`. Ver "State transitions". |
| `model` | string | sim | `tool_response.resolvedModel` | **Sempre presente** (FR-003). Quando ausente na fonte => literal `"nao-aplicavel"`, nunca omitido. |
| `models_used` | array\<string\> \| null | nao | `tool_response.modelsUsed` | So quando houve swap mid-run. Requer harness >= 2.1.212. Null = sem swap ou harness antigo. |
| `total_tokens` | int \| null | sim (nullable) | `tool_response.totalTokens` | **null = nao observado**. NUNCA 0 como substituto (FR-009). |
| `input_tokens` | int \| null | sim (nullable) | `tool_response.usage.input_tokens` | Breakdown FR-001. |
| `output_tokens` | int \| null | sim (nullable) | `tool_response.usage.output_tokens` | Breakdown FR-001. |
| `cache_read_input_tokens` | int \| null | sim (nullable) | `tool_response.usage.cache_read_input_tokens` | Breakdown FR-001. |
| `cache_creation_input_tokens` | int \| null | sim (nullable) | `tool_response.usage.cache_creation_input_tokens` | Breakdown FR-001. |
| `tool_use_count` | int \| null | sim (nullable) | `tool_response.totalToolUseCount` | FR-002. |
| `duration_ms` | int \| null | sim (nullable) | `tool_response.totalDurationMs` | FR-002. |
| `source` | enum | sim | gerado | `live` \| `backfill` `[PROPOSTA]`. Proveniencia (Decision 9 do research). |
| `observed_at` | string (ISO 8601 UTC) | sim | `date -u +%Y-%m-%dT%H:%M:%SZ` | Momento da captura. |

**Campos deliberadamente NAO capturados** (Decision 5 do research):
`tool_response.content` (texto final do subagente) e `tool_input.prompt` (texto
da tarefa). Motivo duplo: (a) estourariam PIPE_BUF e quebrariam a atomicidade
do append no sidecar; (b) texto livre = superficie de vazamento de segredo.

### State transitions (campo `status`)

```
                  tool_response.status == "completed"
                  E totalTokens presente
   [spawn] ---------------------------------------------> completo

                  tool_response.status == "completed"
                  MAS algum campo de uso ausente
           ---------------------------------------------> parcial

                  tool_response.status == "async_launched"
                  (background; sem campos de usage)
           ---------------------------------------------> indisponivel

                  tool_response ausente/malformado
           ---------------------------------------------> indisponivel
```

Regras duras:

- `indisponivel` **MUST** ter todos os campos numericos de uso em `null`.
  Gravar `0` seria afirmar "medido e deu zero" — fabricacao (FR-009/SC-004).
- `parcial` grava os campos observados e mantem `null` nos nao observados
  (FR-012: parcial **somente se observavel**).
- Nenhuma transicao produz valor estimado. Nao existe caminho de codigo que
  derive um numero de uso por heuristica.

### Chave natural

`(project, feature, execution_id, wave_id, agent_id)`.

O `execution_id` explicito atende a Clarification ratificada ("identificador de
execucao explicito, precedente da coluna `session` do knowledge.db v8") e o edge
case de duas execucoes concorrentes sobre o mesmo projeto.

---

## Entity: Consumo Agregado da Onda (`WaveUsage`)

Soma das `SpawnUsage` de uma mesma onda. Persistida em
`.waves[].agent_usage` `[PROPOSTA]`.

| Campo | Tipo | Notas |
|-------|------|-------|
| `spawns_total` | int | Total de spawns observados na onda (todos os status). |
| `spawns_with_usage` | int | Quantos tinham dado de uso (`completo` + `parcial`). |
| `spawns_unavailable` | int | Quantos ficaram `indisponivel`. **Load-bearing**: ~50% dos spawns reais (research Decision 2). |
| `total_tokens` | int \| null | Soma sobre spawns com dado. `null` quando `spawns_with_usage == 0`. |
| `input_tokens` | int \| null | idem |
| `output_tokens` | int \| null | idem |
| `cache_read_input_tokens` | int \| null | idem |
| `cache_creation_input_tokens` | int \| null | idem |
| `tool_use_count` | int \| null | idem |
| `duration_ms` | int \| null | idem |

**Invariante de honestidade (SC-004)**: `spawns_total`, `spawns_with_usage` e
`spawns_unavailable` **MUST** ser exibidos junto do total sempre que
`spawns_unavailable > 0`. Um total sem esse denominador seria apresentado como
completo quando e parcial. `spawns_total = spawns_with_usage + spawns_unavailable`.

**Distincao critica**: `spawns_total == 0` significa "nenhum subagente foi
spawnado nesta onda". NAO significa "hook ausente". O segundo caso e detectado
pela ausencia do sidecar somada a evidencia de spawn — e reportado como
"metrica nao coletada", nunca como zero (research Decision 10).

---

## Extensoes ao `state.json`

Todas ADITIVAS. Nenhum campo existente muda de semantica.

### `.waves[]` — entrada de onda

Campos ja existentes `[EXISTE]` (`state-ondas.sh:259-273`, 9 campos criados por
`start`): `id`, `started_at`, `finished_at`, `executed_stages`, `tool_calls`,
`wallclock_seconds`, `termination_reason`, `next_wave_scheduled_for`,
`skills_invoked`.

Campos novos `[PROPOSTA]`:

| Campo | Tipo | Escrito por |
|-------|------|-------------|
| `agent_usage` | objeto `WaveUsage` \| null | `state-ondas.sh end` |
| `agent_spawns` | array\<`SpawnUsage`\> | `state-ondas.sh end` |

`null` / `[]` quando nenhum spawn foi observado — coerente com o comportamento
de onda antiga (retro-compatibilidade, ver abaixo).

### `.accumulated_metrics` — totais da execucao

Campos ja existentes `[EXISTE]` (`state-ondas.sh:400-406`): `waves_total`,
`tool_calls_total`, `wallclock_total_seconds`.

Campos novos `[PROPOSTA]`, incrementados no mesmo `jq` de `end`:

| Campo | Tipo |
|-------|------|
| `agent_spawns_total` | int |
| `agent_spawns_with_usage_total` | int |
| `agent_tokens_total` | int \| null |
| `agent_tool_use_count_total` | int \| null |
| `agent_duration_ms_total` | int \| null |

### Retro-compatibilidade

State de execucao anterior a esta feature nao tem os campos novos. Todo leitor
**MUST** usar o padrao ja adotado no repo — `(.campo // default)` no jq, como
em `state-ondas.sh:373` (`(.budgets.tool_calls_current_wave // ...) // 0`) — de
modo que ausencia produza `null`/`0 spawns`, nunca erro. Nenhuma migracao de
`state.json` e necessaria.

---

## Sidecar: `<state-dir>/wave-agent-usage.jsonl` `[PROPOSTA]`

Espelha o contrato ja existente de `<state-dir>/tool-call-ticks.log`
(`state-ondas.sh:219-235`).

| Propriedade | Valor |
|-------------|-------|
| Formato | JSON Lines — 1 objeto `SpawnUsage` por linha, sem `content`/`prompt` |
| Escrita | Append-only (`>>`), O_APPEND atomico para linha < PIPE_BUF |
| Escritor | Somente o hook `posttooluse-agent-usage.sh` |
| Leitor | Somente `state-ondas.sh end` (e `wave-usage-report.sh` para leitura mid-onda) |
| Reset | `start` e `end`, espelhando `_so_ticks_reset` (`state-ondas.sh:235`, chamado em `:282` e `:417`) |
| Janela | start -> end da onda corrente |
| Perda aceita | Spawns na fronteira exata start/end — mesma tolerancia ja documentada para o sidecar de ticks |

### Permissao de arquivo `[PROPOSTA]` (CHK017)

O sidecar `wave-agent-usage.jsonl` **MUST** ser criado com permissao `0600`
(leitura/escrita apenas do dono do processo) — dado numerico agregavel por
onda, sem `content`/`prompt`, mas ainda assim superficie a minimizar por
padrao (defesa em profundidade, nao porque o conteudo seja sensivel por si).
O hook `posttooluse-agent-usage.sh` aplica `umask 077` imediatamente antes do
primeiro append de cada arquivo (o primeiro append cria o arquivo se ausente;
`umask` so afeta a criacao, nao um arquivo ja existente). Mesma politica
retroativa se aplica ao sidecar irmao `<state-dir>/tool-call-ticks.log` — gap
herdado do padrao pre-existente do toolkit, resolvido aqui porque esta
feature adiciona dado novo ao mesmo mecanismo compartilhado.

### Teto de linhas `[PROPOSTA]` (CHK020)

O sidecar aceita no maximo **500 linhas** por onda (ver `research.md`
§Decision 5 para a justificativa do numero). Ao atingir o teto, o hook
`posttooluse-agent-usage.sh` **pula** o append de qualquer linha adicional
(fail-open — a tool call do spawn nunca e bloqueada) e emite um aviso unico
por onda via arquivo-sentinela `<state-dir>/.wave-agent-usage-cap-warned`
(criado/removido no mesmo ciclo `start`/`end` do sidecar). Consequencia
direta para o consumidor: spawns alem do teto ficam fora do agregado da
onda — undercounting silencioso conhecido, analogo a tolerancia ja
documentada acima para a fronteira exata start/end. `state-ondas.sh end`
reporta `spawns_total` (e os demais campos de `.waves[].agent_usage`) apenas
com base nas linhas de fato observadas no sidecar; nunca fabrica ou estima o
excedente pulado (Principio VI).

---

## Extensao do knowledge.db: v9 -> v10

`RECALL_SCHEMA_VERSION` `[EXISTE]` = 9 (`cli/lib/recall.sh:106`) -> 10
`[PROPOSTA]`.

### Tabela `waves` — colunas existentes `[EXISTE]`

`cli/lib/recall.sh:487-506`: `id`, `project`, `feature`, `wave`, `execution_id`,
`source_ts`, `source_id`, `stages`, `started_at`, `finished_at`,
`wallclock_seconds`, `tool_calls`, `termination_reason`, `n_stages`,
`n_skills`, `session`, `ingested_at`, `UNIQUE(project, feature, wave, source_id)`.

### Colunas novas `[PROPOSTA]`

| Coluna | Tipo | Fonte em `state.json` |
|--------|------|------------------------|
| `agent_spawns_total` | INTEGER | `.waves[].agent_usage.spawns_total` |
| `agent_spawns_with_usage` | INTEGER | `.waves[].agent_usage.spawns_with_usage` |
| `agent_total_tokens` | INTEGER | `.waves[].agent_usage.total_tokens` |
| `agent_input_tokens` | INTEGER | `.waves[].agent_usage.input_tokens` |
| `agent_output_tokens` | INTEGER | `.waves[].agent_usage.output_tokens` |
| `agent_cache_read_tokens` | INTEGER | `.waves[].agent_usage.cache_read_input_tokens` |
| `agent_cache_creation_tokens` | INTEGER | `.waves[].agent_usage.cache_creation_input_tokens` |
| `agent_tool_use_count` | INTEGER | `.waves[].agent_usage.tool_use_count` |
| `agent_duration_ms` | INTEGER | `.waves[].agent_usage.duration_ms` |

**Regra de nulidade (FR-009)**: todas usam `recall_int_or_null` `[EXISTE]`, o
mesmo helper ja aplicado a `wallclock_seconds` e `tool_calls`
(`cli/lib/recall.sh:1005-1055`). Onda antiga ou sem dado => `NULL`, jamais `0`.

**Migracao**: aditiva idempotente via `PRAGMA table_info(waves)` + `case`, no
padrao literal ja usado em v7->v8 e v8->v9 (`cli/lib/recall.sh:677-694`). Sem
`DROP`, dados v9 preservados. Retrofit por `recall_mode_reindex()`
(`cli/lib/recall.sh:2175`).

**Granularidade**: a knowledge.db recebe o AGREGADO por onda, nao o detalhe por
spawn. Motivo: a tabela `waves` tem grao de onda (`UNIQUE(project, feature,
wave, source_id)`), e o detalhe por spawn permanece consultavel no `state.json`
da execucao. Uma tabela `spawns` dedicada seria a extensao natural caso o
detalhe cross-projeto vire requisito — fora do escopo desta feature.

### Permissao de arquivo `[PROPOSTA]` (CHK017)

`~/.claude/cstk/knowledge.db` **MUST** ser criado com permissao `0600` — mesma
politica do sidecar acima, ja que o DB agrega, entre outras colunas
pre-existentes, dado novo de uso de tokens por onda. Aplicado em
`recall_apply_schema()`/`recall_ensure_db_dir()` (`cli/lib/recall.sh`), na
mesma sequencia ja usada para as `PRAGMA` de abertura. **Nao altera** a
permissao de um DB ja existente com modo mais aberto silenciosamente: normaliza
via `chmod 600` best-effort e loga via `log_warn` (nunca falha a ingestao/
reindex por causa disso) — evita quebrar setups locais existentes com um erro
inesperado, ao mesmo tempo que corrige o desvio na proxima escrita.

---

## Mapeamento requisito -> campo

| FR | Onde e satisfeito |
|----|-------------------|
| FR-001 (total + 4 categorias) | `SpawnUsage.total_tokens` + `input/output/cache_read/cache_creation` |
| FR-002 (tool-uses + duracao) | `SpawnUsage.tool_use_count`, `.duration_ms` |
| FR-003 (onda/execucao/feature/modelo; modelo sempre presente) | chave natural + `SpawnUsage.model` (`"nao-aplicavel"` quando ausente) |
| FR-004 (consultavel apos a sessao) | persistencia em `state.json` + knowledge.db |
| FR-005 (relatorios existentes) | `report.sh` §1 e §2 |
| FR-006 (cross-feature) | colunas novas em `waves` (knowledge.db v10) |
| FR-007 (custo x roteamento) | `wave-usage-report.sh` + `model-routing-report.sh` em review-task §4.5 |
| FR-008 (best-effort) | hook fail-open; sidecar ausente => agregado nulo |
| FR-009 (nao fabricar) | `null` em vez de `0`; `status = indisponivel` |
| FR-010/FR-011 (backfill + recusa) | `source = backfill`; recusa explicita quando transcript ausente |
| FR-012 (parcial so se observavel) | `status = parcial` com campos observados; resto `null` |
