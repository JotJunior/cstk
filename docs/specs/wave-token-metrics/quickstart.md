# Quickstart: wave-token-metrics

**Feature**: `wave-token-metrics` | **Date**: 2026-07-25 | **Spec**: [spec.md](./spec.md)

Cenarios de validacao end-to-end. Cada um mapeia a um Success Criteria da spec.
Todos rodam sobre o repo do proprio toolkit (`cstk`), que ja e projeto-alvo de
execucoes `feature-00c`.

> **Nota sobre roundtrip backend↔frontend**: N/A — feature single-layer
> (hooks + scripts POSIX + SQLite local). Nao ha borda HTTP nem DTO
> serializado entre servicos. A borda real aqui e **harness -> hook (stdin
> JSON)**, coberta pelo Cenario 1, que le o payload REAL do harness, nao um
> fixture.

---

## Cenario 1 — Captura ao vivo de um spawn concluido (SC-001)

**Objetivo**: provar que o hook captura tokens/tool-uses/duracao de um spawn
real, com dado do harness e nao de mock.

1. Garantir o hook provisionado no projeto-alvo:
   `cstk update` (ou `apply_guard_hooks()` via install) e confirmar que
   `<projeto>/.claude/hooks/posttooluse-agent-usage.sh` existe e e executavel,
   e que `.claude/settings.json` tem a entrada `PostToolUse` com matcher
   `"Agent"`.
2. Iniciar uma execucao autonoma (`/feature-00c <short-name>`) cuja onda
   spawne pelo menos um subagente em **foreground**
   (`run_in_background: false` — ver Cenario 3 para o caso background).
3. Ao fim da onda, inspecionar o sidecar antes do reset:
   `cat <state-dir>/wave-agent-usage.jsonl`
4. Fechar a onda e inspecionar o state:
   `jq '.waves[-1].agent_usage, .waves[-1].agent_spawns' <state-dir>/state.json`

**Expected**:
- O sidecar tem 1 linha JSON por spawn, com `status: "completo"`,
  `total_tokens` > 0 e os 4 campos de breakdown preenchidos.
- A linha **nao** contem `content`, `prompt` nem `description`.
- `.waves[-1].agent_usage.spawns_total` == numero de spawns da onda.
- `.waves[-1].agent_usage.total_tokens` == soma dos `total_tokens` dos spawns
  com dado.
- O sidecar foi removido apos o `end` (reset da janela).

---

## Cenario 2 — Metrica indisponivel nunca vira zero (SC-004, FR-009)

**Objetivo**: provar a regra central de nao-fabricacao.

1. Simular o payload de um spawn background alimentando o hook diretamente:

```sh
printf '%s' '{"cwd":"<projeto>","tool_name":"Agent","tool_input":{"subagent_type":"Explore"},"tool_response":{"status":"async_launched","agentId":"abc123","resolvedModel":"claude-sonnet-5","outputFile":"/tmp/x","prompt":"...","description":"..."}}' \
  | <projeto>/.claude/hooks/posttooluse-agent-usage.sh
echo "exit=$?"
```

2. Inspecionar a linha gravada:
   `tail -1 <state-dir>/wave-agent-usage.jsonl | jq .`
3. Fechar a onda e rodar o relatorio:
   `wave-usage-report.sh aggregate --state-dir <state-dir>`

**Expected**:
- `exit=0` (fail-open).
- A linha tem `status: "indisponivel"` e **todos** os campos numericos em
  `null` — nenhum `0`.
- O relatorio renderiza a palavra `indisponivel` naquela celula, nunca `0`
  nem celula vazia.
- O sumario mostra `spawns` e `com uso` separados, mais a linha
  `Cobertura da metrica`.

---

## Cenario 3 — Onda mista: metade dos spawns sem usage (Edge case real)

**Objetivo**: cobrir o caso medido como ~50% da realidade (research Decision 2),
garantindo que o total parcial nao seja apresentado como completo.

1. Rodar uma onda que spawne 2 subagentes em foreground e 2 em background.
2. `wave-usage-report.sh aggregate --state-dir <state-dir> --json | jq .`

**Expected**:
- `spawns_total == 4`, `spawns_with_usage == 2`, `spawns_unavailable == 2`.
- `coverage_pct == "50.0%"`.
- `total_tokens` reflete **apenas** os 2 spawns observados, e a saida deixa
  explicito que 2 spawns nao tem dado.
- Em nenhum ponto os 2 spawns sem dado somam `0` ao total silenciosamente.

---

## Cenario 4 — Best-effort: hook nunca quebra a onda (FR-008)

**Objetivo**: provar o contrato fail-open em todas as degradacoes.

1. Rodar o hook com `jq` fora do PATH:
   `PATH=/usr/bin:/bin env -u HOME sh -c 'printf "{}" | <hook>'`
2. Rodar com stdin vazio: `printf '' | <hook>; echo $?`
3. Rodar com JSON malformado: `printf '{oops' | <hook>; echo $?`
4. Rodar fora de qualquer execucao ativa (nenhum `state.json` com status
   `em_andamento`).
5. Tornar o state dir somente-leitura e disparar o hook.

**Expected**:
- Todos retornam `exit 0`, stdout vazio.
- Nenhum caso cria sidecar parcial ou corrompido.
- Em nenhum caso o `state.json` e tocado pelo hook.
- Uma onda executada com o hook quebrado conclui normalmente, apenas sem a
  metrica.

---

## Cenario 5 — Persistencia apos a sessao (SC-002, FR-004)

1. Concluir uma execucao com metricas capturadas.
2. Encerrar a sessao do Claude Code.
3. Em sessao nova: `report.sh emit --flavor feature-00c --state-dir <state-dir>`

**Expected**:
- §1 do relatorio mostra `Spawns de subagente`, `Tokens totais (observados)` e
  `Cobertura da metrica`.
- §2 (Linha do Tempo) mostra as colunas `spawns` e `tokens` por onda.
- Nenhuma consulta depende da conversa original estar aberta.

---

## Cenario 6 — Custo x modelo roteado (SC-003, FR-007)

1. Rodar duas ondas que roteiem modelos diferentes (ex.: uma `plan` -> opus,
   uma `review-task` -> haiku).
2. Rodar a skill `review-task` e ler §4.5.

**Expected**:
- O bloco de `model-routing-report.sh` (modelo **roteado**) e o de
  `wave-usage-report.sh` (consumo **observado**, agrupado por
  `resolvedModel`) aparecem lado a lado.
- O operador compara tokens por modelo sem calculo manual fora do toolkit.
- Divergencia entre modelo roteado e `resolvedModel` observado aparece como
  sinal legivel (ex.: swap mid-run via `models_used`), nao como erro de captura.

---

## Cenario 7 — Consulta cross-feature (SC-002/FR-006)

1. `cstk recall --ingest --state-dir <state-dir>`
2. ```sh
   sqlite3 ~/.claude/cstk/knowledge.db \
     "SELECT project, feature, wave, agent_spawns_total, agent_total_tokens
      FROM waves WHERE agent_total_tokens IS NOT NULL LIMIT 5;"
   ```
3. Conferir a versao do schema:
   `sqlite3 ~/.claude/cstk/knowledge.db "SELECT value FROM schema_meta WHERE key='schema_version';"`

**Expected**:
- `schema_version == 10`.
- Ondas com metrica trazem valores; ondas antigas trazem `NULL` (nao `0`).
- A proveniencia (`project`, `feature`, `wave`, `execution_id`, `session`)
  acompanha o registro, igual aos demais tipos ja indexados.

---

## Cenario 8 — Migracao v9 -> v10 preserva dados (FR-006)

1. Partir de uma knowledge.db v9 existente; anotar
   `SELECT COUNT(*) FROM waves;` e alguns `tool_calls`.
2. Rodar um `cstk recall --ingest` com o codigo novo.
3. Repetir as contagens e conferir `PRAGMA table_info(waves);`.

**Expected**:
- `schema_version` passa a `10`; as 9 colunas novas existem.
- `COUNT(*)` inalterado e `tool_calls` preservados — **sem `DROP`**.
- Colunas novas em `NULL` para as linhas pre-existentes.
- Rodar a ingestao 2x nao duplica linhas nem falha (idempotencia do
  `ADD COLUMN` guardado por `PRAGMA`).

---

## Cenario 9 — Backfill retroativo (SC-005, FR-010)

1. Escolher uma execucao concluida antes desta feature, com transcript ainda
   em `~/.claude/projects/<encoded>/<session>.jsonl`.
2. `wave-usage-report.sh backfill --state-dir <state-dir> --transcript <path> --dry-run`
3. Repetir sem `--dry-run`; depois `cstk recall --ingest`.

**Expected**:
- O dry-run lista os spawns e a onda a que cada um seria atribuido.
- Apos aplicar, os spawns aparecem com `source: "backfill"` (nunca `"live"`).
- Re-executar o backfill **nao** duplica registros (dedup por
  `(wave_id, agent_id)`).
- O consumo passa a aparecer nos mesmos lugares que um dado ao vivo.

---

## Cenario 10 — Backfill recusa explicita (FR-011)

1. `wave-usage-report.sh backfill --state-dir <state-dir> --transcript /caminho/inexistente.jsonl`

**Expected**:
- Exit code `3`.
- Mensagem nomeia explicitamente a execucao que **nao pode ser reconstruida**.
- Nenhum campo de metrica e escrito — nem `0`, nem estimativa.

---

## Cenario 11 — Hook nao provisionado != consumo zero (research Decision 10)

**Objetivo**: o modo de falha silencioso mais provavel na pratica — e o unico
que pode enganar o operador.

1. Rodar uma onda com spawns num projeto **sem** o hook provisionado
   (estado atual do proprio repo `cstk`: `.claude/settings.local.json` so tem
   matchers `Edit|Write`, e as ondas 001-004 registram `tool_calls: 0`).
2. `wave-usage-report.sh aggregate --state-dir <state-dir>`

**Expected**:
- A saida diz explicitamente que a metrica **nao foi coletada** (hook ausente),
  e **nao** que o consumo foi zero.
- `cstk doctor` sinaliza a ausencia do hook no projeto.

---

## Regressao — suite completa

```sh
./tests/run.sh test_posttooluse-agent-usage.sh
./tests/run.sh test_wave-usage-report.sh
./tests/run.sh test_state-ondas.sh
./tests/run.sh cstk/test_recall.sh
./tests/run.sh cstk/test_hooks.sh
./tests/run.sh --check-coverage
./tests/run.sh            # suite completa antes de fechar a feature
```

**Expected**: tudo verde; `--check-coverage` sem orfaos (exige a isencao
existence-guarded do teste do hook em `_is_internal_test`).

> **Nota de tempo**: a suite completa leva ~12 min (memoria
> `feedback_full_suite_slow_background_parent`) — rodar em background preso ao
> processo pai, nao em foreground com timeout curto.
