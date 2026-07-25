# Phase 0 Research: wave-token-metrics

**Feature**: `wave-token-metrics` | **Date**: 2026-07-25 | **Spec**: [spec.md](./spec.md)

> **Convencao de veracidade (Constitution Principio VI)**: cada fato abaixo
> carrega sua fonte. `[VERIFICADO]` = extraido de fonte rastreavel (doc oficial
> baixada e lida, codigo do repo com arquivo:linha, ou output observado nesta
> sessao). `[PROPOSTA]` = desenho novo, ainda nao existente, a validar na
> implementacao. Nenhum numero de performance ou custo em $ e estimado.

---

## Unknown central da feature

A spec (secao "Assumptions & Dependencies") deixou explicitamente em aberto:

> **Risco em aberto — mecanismo exato de captura**: nao foi verificado ainda o
> payload exato que um hook de pos-execucao de tool call recebe no momento em
> que um spawn de subagente completa (qual identificador de tool chega, e se os
> totais de uso vem diretamente nesse payload ou exigem acesso ao arquivo de
> transcript por um caminho fornecido separadamente).

Este research resolve esse unknown por completo. **Resultado: os totais de uso
vem DIRETAMENTE no payload do hook** — nao e necessario ler o transcript ao
vivo. O caminho por transcript fica reservado ao backfill offline (US4).

---

## Decision 1 — Fonte de captura: hook `PostToolUse` com matcher `Agent`

**Decision**: capturar via hook `PostToolUse` filtrado pelo matcher `Agent`,
lendo os campos de uso diretamente de `tool_response` no stdin do hook.

**Rationale** `[VERIFICADO]`:

Fonte: `https://code.claude.com/docs/en/hooks.md` (baixada em 2026-07-25 e lida
localmente; 238174 bytes).

1. **A tool de spawn se chama `Agent`, nao `Task`.** Linha 2049 do doc, literal:

   > To inject context into the parent session after a subagent returns, use a
   > [`PostToolUse`](#posttooluse) hook on the `Agent` tool instead.

   O doc tem uma secao dedicada `##### Agent` (L1472-1480) descrevendo o
   `tool_input` (`prompt`, `description`, `subagent_type`, `model`).

   Confirmacao empirica independente: no transcript
   `~/.claude/projects/-Users-jot-Projects--lab-Jot-misc-cstk/01d83125-e6c0-4c7d-859a-a1b94d6de09e.jsonl`,
   os 6 `tool_use_id` cujo resultado carrega `toolUseResult.totalTokens`
   correlacionam 6/6 com `tool_use` de `name = "Agent"`.

2. **O payload do hook JA carrega a telemetria de uso.** Linha 1483, literal:

   > In `PostToolUse`, `tool_response` for a completed Agent call carries the
   > subagent's final text along with usage telemetry. Read these fields to
   > record per-subagent cost from a hook:

   Ou seja: o doc oficial documenta **exatamente o caso de uso desta feature**.
   Campos de `tool_response` para `status = "completed"` (tabela L1485-1495):

   | Campo | Tipo | Observacao do doc |
   |-------|------|-------------------|
   | `status` | string | `"completed"` (foreground) ou `"async_launched"` (background) |
   | `agentId` | string | identificador da run do subagente |
   | `content` | array | blocos de texto finais do subagente |
   | `resolvedModel` | string | modelo em que o subagente iniciou; requer Claude Code >= v2.1.174 |
   | `modelsUsed` | array | modelos usados em ordem, so quando houve swap mid-run; requer >= v2.1.212 |
   | `totalTokens` | number | total de tokens faturados nos turnos do subagente |
   | `totalDurationMs` | number | duracao wall-clock da run |
   | `totalToolUseCount` | number | contagem de tool calls do subagente |
   | `usage` | object | breakdown: `input_tokens`, `output_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens` |

   Isso cobre FR-001 (total + breakdown por 4 categorias), FR-002 (tool-uses +
   duracao) e FR-003 (modelo, via `resolvedModel`) numa unica leitura.

3. **Campos comuns do stdin do hook** (doc, secao "Common input fields"):
   `session_id`, `prompt_id`, `transcript_path`, `cwd`, `permission_mode`,
   `hook_event_name`; e especificos do PostToolUse: `tool_name`, `tool_use_id`,
   `tool_input`, `tool_response`. O campo `cwd` e o mesmo ja consumido por
   `posttooluse-tool-call-tick.sh:53` para detectar execucao ativa — a
   deteccao existente e reusavel sem mudanca.

**Alternatives considered**:

- **Hook `SubagentStop`** — REJEITADO. Doc L2028: recebe `stop_hook_active`,
  `agent_id`, `agent_type`, `agent_transcript_path`, `last_assistant_message`.
  **Nenhum campo de usage.** Daria identidade do subagente mas nao o consumo,
  exigindo um segundo passo de leitura de transcript (que sofre o lag da
  Decision 3). Descartado como fonte primaria.
- **Ler `transcript_path` dentro do hook** — REJEITADO (ver Decision 3).
- **Capturar no proprio orquestrador, do tool result inline** — REJEITADO. O
  orquestrador ve o resumo de uso no retorno da tool Agent, mas depender da
  prosa do orquestrador para registrar metrica e exatamente o modo de falha
  "mecanismo advisory" que o cabecalho de `posttooluse-tool-call-tick.sh:5-13`
  documenta como causa raiz do gap anterior (`tool_calls` nunca avancava
  porque nenhum mecanismo automatico invocava o tick). Hook e deterministico;
  prosa nao e.

---

## Decision 2 — ~50% dos spawns reais NAO tem usage (`status = async_launched`)

**Decision**: tratar `async_launched` como o caso **"indisponivel"** da FR-009 /
FR-012, registrando o spawn com os campos de uso NULOS e um status explicito —
nunca zero, nunca estimado. Nao alterar a semantica de execucao do orquestrador
para "forcar" foreground.

**Rationale** `[VERIFICADO]`:

1. Doc L1497, literal:

   > For background subagents, the tool returns when the task moves to the
   > background, so `tool_response` carries no usage fields: a background launch
   > returns immediately, and a foreground task that Claude Code backgrounds
   > mid-run returns at that transition. It has `status: "async_launched"`,
   > `agentId`, `description`, `prompt`, `outputFile`, and `resolvedModel`.

2. Doc L1487 (nota de versao na linha do campo `status`):

   > As of v2.1.198, subagents run in the background by default, so an omitted
   > `run_in_background` also produces `"async_launched"`

3. **Medicao real** (nao estimativa) nos transcripts deste projeto,
   `~/.claude/projects/-Users-jot-Projects--lab-Jot-misc-cstk/*.jsonl`:

   ```
   52 async_launched
   51 completed
   ```

   Keys observadas num `toolUseResult` com `status = "async_launched"`:

   ```json
   ["agentId","canReadOutputFile","description","isAsync","outputFile","prompt","resolvedModel","status"]
   ```

   — sem `totalTokens`, sem `usage`. Confirma o doc.

**Consequencia de desenho (importante)**: o caso "metrica indisponivel" da
FR-009/SC-004 **nao e um edge case raro** — na pratica observada e ~metade dos
spawns. O relatorio precisa exibir "indisponivel" de forma legivel e rotineira,
e o agregado da onda precisa distinguir `spawns_total` de
`spawns_com_usage`, senao o operador le um total parcial como se fosse total.

**Ambiente local** `[VERIFICADO]`: `claude --version` => `2.1.220 (Claude Code)`
— acima dos pisos de `resolvedModel` (2.1.174) e `modelsUsed` (2.1.212), logo
os dois campos estao disponiveis aqui. O desenho trata ambos como opcionais
(ausencia => campo nulo) para nao quebrar em harness mais antigo.

**Alternatives considered**:

- **Forcar `run_in_background: false` em todos os spawns do orquestrador** —
  REJEITADO como requisito desta feature. Aumentaria a cobertura da metrica,
  mas muda a semantica de execucao da orquestracao (paralelismo de subagentes)
  para servir a observabilidade — o rabo abanando o cachorro. Fica registrado
  como **recomendacao aditiva e opcional** ao orquestrador, fora do escopo.
- **Ler `outputFile` do spawn background para extrair uso** — REJEITADO: o doc
  descreve `outputFile` como o destino da saida da task, nao como portador de
  telemetria; nao ha campo de uso documentado ali. Supor que teria seria
  fabricacao (Principio VI).
- **Estimar o consumo do spawn background** — PROIBIDO por FR-009.

---

## Decision 3 — `transcript_path` serve so para backfill offline, nunca ao vivo

**Decision**: nao ler `transcript_path` de dentro do hook. O caminho por
transcript e reservado a US4 (reconstrucao retroativa, FR-010/FR-011), que
opera sobre transcripts de sessoes ja encerradas.

**Rationale** `[VERIFICADO]`: doc L617, literal:

> Path to conversation JSON. The transcript file is written asynchronously and
> may lag the in-memory conversation, so it may not yet include the current
> turn's most recent messages when a hook fires.

Ler o transcript no instante do hook seria nao-deterministico: a entrada do
proprio spawn que acabou de completar pode ainda nao estar no arquivo. Para
backfill, o lag e irrelevante (a sessao ja terminou e o arquivo esta estavel).

**Nota sobre a spec**: a secao "Assumptions & Dependencies" da spec levantou as
duas fontes possiveis (transcript persistido vs resultado da tool call) e
deixou a escolha para o `/plan`. A escolha e: **tool call para captura ao vivo
(US1-US3), transcript para reconstrucao retroativa (US4)** — as duas fontes
sao usadas, cada uma onde e deterministica.

---

## Decision 4 — Hook novo dedicado (matcher `Agent`), nao extensao do hook de ticks

**Decision**: criar `global/skills/agente-00c-runtime/hooks/posttooluse-agent-usage.sh`
`[PROPOSTA]`, registrado com matcher `"Agent"`, em vez de estender
`posttooluse-tool-call-tick.sh` (matcher `"*"`).

**Rationale**:

- O matcher `"Agent"` faz o harness filtrar antes de invocar o processo: o hook
  novo so roda em spawns de subagente, nao a cada tool call. Estender o hook de
  ticks (que roda em `"*"`) adicionaria trabalho no caminho quente de toda tool
  call.
- Separacao de responsabilidade: o hook de ticks conta; o hook novo mede uso.
  Cada um mantem seu proprio contrato fail-open simples.
- O provisionamento ja tem o padrao pronto: `cli/lib/hooks.sh:256-263`
  (`apply_guard_hooks()`) ja copia `posttooluse-tool-call-tick.sh` em modo
  best-effort (falha so emite `log_warn`, nao muda o state word). Um terceiro
  `cp` no mesmo bloco e simetrico.

**Custo aceito (declarado, nao escondido)**:

1. Mais uma entrada em `global/skills/agente-00c-runtime/hooks/settings.snippet.json`
   (hoje tem 2: PreToolUse matcher `"Bash"` L3-14; PostToolUse matcher `"*"`
   L15-26).
2. Mais uma isencao em `tests/run.sh::_is_internal_test`. **Verificado**: hooks
   vivem em `.../hooks/`, fora do `_find_scripts()` (que varre
   `global/skills/*/scripts/*.sh` e `cli/lib/*.sh`), entao um
   `tests/test_posttooluse-agent-usage.sh` seria sinalizado como *teste orfao*.
   O precedente exato ja existe em `tests/run.sh:298-303`, que isenta
   `test_posttooluse-tool-call-tick.sh` de forma existence-guarded:

   ```sh
   test_posttooluse-tool-call-tick.sh)
     # cobre global/skills/agente-00c-runtime/hooks/posttooluse-tool-call-tick.sh
     [ -f "$REPO_ROOT/global/skills/agente-00c-runtime/hooks/posttooluse-tool-call-tick.sh" ] && return 0
   ```

   O hook novo replica esse padrao.

**Alternative considered**: estender o hook de ticks com um `case` em
`tool_name`. Menos arquivos e um unico caminho de provisionamento, mas paga
custo em toda tool call e mistura duas metricas num script cujo contrato
fail-open depende de ser trivialmente auditavel. Rejeitado por margem estreita
— e uma escolha reversivel se o provisionamento duplo se mostrar fragil.

---

## Decision 5 — Sidecar append-only, state.json intocado pelo hook

**Decision**: o hook escreve UMA linha JSON por spawn em
`<state-dir>/wave-agent-usage.jsonl` `[PROPOSTA]`, append-only, e **nunca**
toca `state.json`. A agregacao para o `state.json` acontece em
`state-ondas.sh end`, que ja e o ponto transacional de fechamento de onda.

**Rationale** `[VERIFICADO]`: o cabecalho de `posttooluse-tool-call-tick.sh:28-37`
documenta a regra dura e o motivo, e vale identicamente aqui:

> REGRA DURA — NAO tocar o state.json: PostToolUse dispara CONCORRENTE as tool
> calls do orquestrador (batches paralelos do harness). Um read-modify-write do
> state.json aqui (...) poderia clobberar um write transacional
> (Decisao/bloqueio/onda) gravado entre o read e o `mv` do tick.

**Restricao de tamanho de linha (load-bearing)**: o mesmo cabecalho (L39-41)
justifica a atomicidade do append por a linha ser curta:

> Append com O_APPEND e atomico para linhas curtas (< PIPE_BUF).

Consequencia direta de desenho: a linha JSONL **MUST** conter apenas os campos
numericos e identificadores curtos. `content` (texto final do subagente) e
`prompt` (texto da tarefa) **MUST NOT** ser gravados — por tamanho (estourariam
PIPE_BUF e quebrariam a atomicidade do append) e por conteudo (texto livre =
superficie de vazamento de segredo). Isso tambem mantem o sidecar barato de
agregar.

**Ciclo de vida**: reset em `start` e em `end`, espelhando
`_so_ticks_reset` (`state-ondas.sh:235`, chamado em `:282` no start e `:417`
no end). Janela de contagem = start→end, igual ao sidecar de ticks.

---

## Decision 6 — Agregacao em `state-ondas.sh end` (ponto ja existente)

**Decision**: `end` le o sidecar, agrega, e grava no mesmo `jq` transacional que
ja escreve o fechamento da onda.

**Rationale** `[VERIFICADO]`: `state-ondas.sh:373-377` ja faz exatamente esse
padrao para os ticks:

```sh
_tc_field=$(jq -r '(.budgets.tool_calls_current_wave // .orcamentos.tool_calls_onda_corrente) // 0' "$_sf")
_tc_side=$(_so_ticks_count "$_sdir")
_tc=$((_tc_field + _tc_side))
```

e grava em `:391-410` via `.waves[-1] |= (...)` mais incrementos em
`.accumulated_metrics`. O caminho ja e coberto por `_so_backup_current` +
`_so_atomic_write` + `_so_update_sha` (`:412-418`) — a metrica nova herda
backup, escrita atomica e recomputo de hash sem mecanismo novo.

**Rede de seguranca**: `reconcile-wave` (`state-ondas.sh:928`) so age em onda
ABERTA e e no-op idempotente em onda fechada (`:947-956`) — ondas recuperadas
pelo comando pai passam pelo mesmo `end`, logo herdam a agregacao sem trabalho
extra.

---

## Decision 7 — knowledge.db v9 -> v10 por colunas aditivas em `waves`

**Decision**: bump `RECALL_SCHEMA_VERSION` 9 -> 10 (`cli/lib/recall.sh:106`) e
adicionar colunas aditivas a tabela `waves`, seguindo o padrao idempotente ja
usado nas migracoes v7->v8 e v8->v9.

**Rationale** `[VERIFICADO]`: o padrao existe literalmente em
`cli/lib/recall.sh:677-694` — `PRAGMA table_info(<tabela>)` + `case` que so
emite o `ALTER TABLE ... ADD COLUMN` se a coluna faltar (SQLite nao tem
`ADD COLUMN IF NOT EXISTS`). **Sem DROP** — dados v9 preservados. Exemplo
literal da v8->v9 no arquivo:

```sh
case "$_as_ecols" in
  ''|*'|target_project_path|'*) : ;;
  *) _as_extra="$_as_extra
ALTER TABLE executions ADD COLUMN target_project_path TEXT;" ;;
esac
```

**Retrofit**: `recall_mode_reindex()` (`cli/lib/recall.sh:2175`) reconstroi do
zero a partir dos `state.json` encontrados — execucoes cujo state.json ja tenha
os campos novos passam a popular as colunas novas sem trabalho manual.

**Regra de nao-fabricacao na ingestao** `[VERIFICADO]`: o bloco de waves usa
`recall_int_or_null` para `wallclock_seconds` e `tool_calls`
(`cli/lib/recall.sh:1005-1055`). As colunas novas **MUST** usar o mesmo helper:
onda antiga (sem o campo) => `NULL`, jamais `0`. `NULL` significa "nao medido";
`0` significaria "medido e deu zero" — confundir os dois viola FR-009/SC-004.

---

## Decision 8 — Helper de relatorio novo, sem contaminar `model-routing-report.sh`

**Decision**: criar
`global/skills/agente-00c-runtime/scripts/wave-usage-report.sh` `[PROPOSTA]`
com subcomando `aggregate --state-dir DIR [--json]`, e consumi-lo em
`review-task` (§4.5) ao lado do agregado de model-routing.

**Rationale** `[VERIFICADO]`: `model-routing-report.sh` le **somente**
`.decisions[]` e nao le `.waves` — e uma decisao registrada e explicita no
cabecalho do proprio script (L5-6, "agregacao real-time derivada de
`.decisions[]` (sem campo agregado em `.waves`)"). Fazer esse script ler
`.waves` quebraria o invariante que ele documenta. Helper separado preserva os
dois contratos.

**Beneficio colateral de convencao** `[VERIFICADO]`: por viver em
`global/skills/*/scripts/`, o helper novo cai na regra 1:1 de
`tests/run.sh::_expected_test_for_script` e ganha
`tests/test_wave-usage-report.sh` **sem** precisar de isencao em
`_is_internal_test` — o oposto do caso do hook (Decision 4).

**Correlacao custo x modelo (US2/FR-007)**: o cruzamento se da por onda —
`wave-usage-report.sh` traz consumo por onda/spawn (incluindo `resolvedModel`
observado) e `model-routing-report.sh` traz o modelo *roteado* por onda. A
distincao importa e esta documentada em data-model.md: `resolvedModel` e o
modelo **aplicado observado no harness**, enquanto a Decisao de model-routing e
o modelo **escolhido pelo toolkit**. Divergencia entre os dois e sinal util
(ex.: swap mid-run via `modelsUsed`), nao um bug de captura.

---

## Decision 9 — Backfill (US4/P4) por janela temporal, com recusa explicita

**Decision**: subcomando `wave-usage-report.sh backfill` `[PROPOSTA]` que le um
transcript ja encerrado, extrai os `toolUseResult` de tool calls `Agent` e os
atribui a ondas por **janela temporal** (`started_at` <= ts < `finished_at` de
cada entrada de `.waves[]`). Quando o transcript nao existe mais em disco,
retorna recusa explicita — nunca preenche.

**Rationale** `[VERIFICADO]`: a estrutura do transcript foi confirmada
empiricamente nesta sessao (ver Decision 1). O transcript **nao carrega
identificador de onda** — nao ha chave direta de juncao, entao a janela
temporal e a unica correlacao disponivel a partir de dados reais. Os campos
`started_at`/`finished_at` existem em toda entrada de `.waves[]`
(`state-ondas.sh:259-273` cria `started_at`; `:391-410` grava `finished_at`).

**Risco declarado**: a atribuicao por janela temporal e uma **heuristica**, nao
uma chave. Spawns exatamente na fronteira entre ondas podem ser mal atribuidos.
Mitigacao: marcar a proveniencia do registro como `backfill` (vs `live`) para
que o operador saiba que aquele numero veio de correlacao temporal. Esta e a
razao de US4 ser P4 e candidata a fase separada — o dado ao vivo (US1) nao
depende dessa heuristica.

**FR-011** (transcript ausente): retorno de recusa explicita com exit code
distinto e mensagem nomeando a execucao que nao pode ser reconstruida.

---

## Decision 10 — Provisionamento e o elo fraco (risco herdado, nao introduzido)

**Decision**: reusar `apply_guard_hooks()` e adicionar uma verificacao de
diagnostico, tratando o gap de provisionamento como risco explicito com task
propria — nao como pressuposto silencioso.

**Rationale** `[VERIFICADO]` — estado real observado neste proprio repo:

```
find .claude -name tool-call-ticks.log   => (vazio)
jq .hooks .claude/settings.local.json    => apenas matchers Edit|Write
state.json .waves[].tool_calls (001-004) => 0, 0, 0, 0
```

Ou seja: **o hook de metrica de tool calls nao esta provisionado no repo do
proprio toolkit**, e por isso todas as ondas desta execucao registram
`tool_calls: 0`. Isso corrobora o comportamento degradado ja documentado
(`agente-00c-feature-orchestrator.md`, passo 4 do Loop: "Sem o hook provisionado
a metrica degrada para 0 — best-effort, nunca gateia").

A feature nova herda exatamente o mesmo risco: hook perfeito + provisionamento
ausente = metrica vazia. A mitigacao NAO e mudar o desenho (o fail-open e
correto e constitucional), e sim tornar o gap **visivel**: o relatorio deve
distinguir "0 spawns nesta onda" de "hook nao provisionado / metrica nao
coletada", e `cstk doctor` e o lugar natural para sinalizar a ausencia do hook.

---

## Riscos residuais consolidados

| # | Risco | Severidade | Mitigacao |
|---|-------|-----------|-----------|
| R1 | ~50% dos spawns sao `async_launched` sem usage (Decision 2) | Alta | Status explicito `indisponivel`; separar `spawns_total` de `spawns_com_usage` no agregado |
| R2 | Hook nao provisionado no projeto-alvo (Decision 10) | Alta | Diagnostico explicito; nunca apresentar ausencia como zero |
| R3 | Linha do sidecar > PIPE_BUF quebra atomicidade do append (Decision 5) | Media | Proibir `content`/`prompt` na linha; so numeros + ids curtos |
| R4 | Backfill por janela temporal pode mal-atribuir spawn de fronteira (Decision 9) | Media | Marcar proveniencia `backfill` vs `live`; US4 e P4, isolada |
| R5 | Campos `resolvedModel`/`modelsUsed` exigem harness >= 2.1.174 / >= 2.1.212 | Baixa | Tratar como opcionais; ausencia => campo nulo, nunca inventado |
| R6 | Crescimento do `state.json` com detalhe por spawn | Baixa | `budget.sh` ja monitora `state_size_threshold_bytes` (default 1048576, `budget.sh:97-100`); spawns por onda sao poucos |

---

## Fontes

| Fonte | Tipo | Uso |
|-------|------|-----|
| `https://code.claude.com/docs/en/hooks.md` (baixada 2026-07-25) | Doc oficial | Decisions 1, 2, 3 |
| `~/.claude/projects/-Users-jot-Projects--lab-Jot-misc-cstk/*.jsonl` | Transcript real | Decisions 1, 2, 9 |
| `global/skills/agente-00c-runtime/hooks/posttooluse-tool-call-tick.sh` | Codigo do repo | Decisions 4, 5 |
| `global/skills/agente-00c-runtime/scripts/state-ondas.sh` | Codigo do repo | Decisions 5, 6, 9 |
| `global/skills/agente-00c-runtime/scripts/budget.sh` | Codigo do repo | R6 |
| `cli/lib/recall.sh` | Codigo do repo | Decision 7 |
| `cli/lib/hooks.sh` | Codigo do repo | Decisions 4, 10 |
| `global/skills/agente-00c-runtime/scripts/model-routing-report.sh` | Codigo do repo | Decision 8 |
| `tests/run.sh` | Codigo do repo | Decisions 4, 8 |
| `claude --version` => `2.1.220 (Claude Code)` | Ambiente local | Decision 2 |
