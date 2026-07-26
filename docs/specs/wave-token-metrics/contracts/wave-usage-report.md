# Contract: `wave-usage-report.sh` + extensoes de agregacao

**Feature**: `wave-token-metrics` | **Status**: `[PROPOSTA — a validar na implementacao]`
**Arquivo alvo**: `global/skills/agente-00c-runtime/scripts/wave-usage-report.sh`

> Contratos EXISTENTES citados com `arquivo:linha`. Tudo o mais e novo.

---

## 1. Por que um helper novo (e nao estender `model-routing-report.sh`)

`model-routing-report.sh` le **somente** `.decisions[]` e nao le `.waves` — e
uma decisao registrada no cabecalho do proprio script (L5-6: "agregacao
real-time derivada de `.decisions[]` (sem campo agregado em `.waves`)"). Fazer
esse script ler `.waves` quebraria o invariante que ele documenta.

Beneficio colateral: por viver em `global/skills/*/scripts/`, o helper novo cai
na regra 1:1 de `tests/run.sh::_expected_test_for_script` e ganha
`tests/test_wave-usage-report.sh` **sem** precisar de isencao em
`_is_internal_test` (ao contrario do hook).

---

## 2. Subcomando `aggregate`

```
wave-usage-report.sh aggregate --state-dir DIR [--json]
```

| Flag | Obrigatoria | Descricao |
|------|-------------|-----------|
| `--state-dir DIR` | sim | diretorio contendo `state.json` |
| `--json` | nao | emite JSON em vez de Markdown |

**Exit codes** (espelham `model-routing-report.sh`, `_mrr_die "aggregate:
state.json nao encontrado..." 1`): `0` sucesso; `2` uso invalido (flag
ausente/desconhecida); `1` erro generico, inclusive `state.json`
inexistente.

**Read-only**: MUST NOT escrever no `state.json`.

### 2.1 Saida Markdown (default)

```markdown
## Consumo por onda (tokens / tool-uses / duracao)

| onda | spawns | com uso | tokens | input | output | cache-read | cache-creation | tool-uses | duracao |
|------|--------|---------|--------|-------|--------|------------|----------------|-----------|---------|
| onda-004 | 3 | 2 | 254.0k | 4 | 1975 | 250.9k | 1049 | 72 | 923s |
| onda-005 | 2 | 0 | indisponivel | indisponivel | indisponivel | indisponivel | indisponivel | indisponivel | indisponivel |

**Sumario**:
- Ondas com metrica: 1 de 2
- Spawns observados: 5 (com uso: 2; indisponiveis: 3)
- Tokens totais: 254.0k (input 4 / output 1975 / cache-read 250.9k / cache-creation 1049)
- Cobertura da metrica: 40.0% dos spawns
```

**Regras de renderizacao (nao-negociaveis, FR-009/SC-004)**:

1. Campo sem dado renderiza a palavra `indisponivel` — **nunca** `0`, `-` ou
   celula vazia.
2. A coluna `com uso` **MUST** sempre acompanhar `spawns`. Exibir tokens sem o
   denominador apresentaria um total parcial como se fosse completo.
3. A linha `Cobertura da metrica` **MUST** aparecer sempre que
   `spawns_indisponiveis > 0`.
4. Quando o sidecar/hook nunca produziu dado em nenhuma onda, a saida **MUST**
   dizer explicitamente que a metrica **nao foi coletada** — e nao que o consumo
   foi zero (research Decision 10).

### 2.2 Saida `--json`

```json
{
  "waves_total": 2,
  "waves_with_usage": 1,
  "spawns_total": 5,
  "spawns_with_usage": 2,
  "spawns_unavailable": 3,
  "coverage_pct": "40.0%",
  "total_tokens": 254000,
  "input_tokens": 4,
  "output_tokens": 1975,
  "cache_read_input_tokens": 250900,
  "cache_creation_input_tokens": 1049,
  "tool_use_count": 72,
  "duration_ms": 923000,
  "por_onda": [],
  "por_modelo": {}
}
```

`por_modelo` agrupa consumo pelo `resolvedModel` observado — e o insumo direto
de FR-007 (custo x modelo). Campos sem dado sao `null`, nunca `0`.

---

## 3. Subcomando `backfill` (US4 / FR-010 / FR-011)

```
wave-usage-report.sh backfill --state-dir DIR --transcript PATH [--dry-run]
```

| Flag | Obrigatoria | Descricao |
|------|-------------|-----------|
| `--state-dir DIR` | sim | execucao alvo |
| `--transcript PATH` | sim | transcript `.jsonl` da sessao original |
| `--dry-run` | nao | reporta o que faria sem escrever |

**Algoritmo**: extrai do transcript os registros cujo `toolUseResult` tem
`totalTokens` (correlacionados a `tool_use` com `name == "Agent"` — verificado
6/6 nesta sessao), e atribui cada spawn a onda cuja janela
`started_at <= ts < finished_at` o contem.

**Proveniencia obrigatoria**: todo registro gravado por backfill leva
`source = "backfill"` (vs `"live"`). A atribuicao por janela temporal e
**heuristica**, nao chave — o transcript nao carrega id de onda. Spawns na
fronteira entre ondas podem ser mal atribuidos, e o operador precisa saber
disso pela proveniencia.

**Exit codes**:

| Code | Significado |
|------|-------------|
| 0 | backfill aplicado (ou dry-run OK) |
| 2 | uso invalido |
| 3 | **transcript ausente/ilegivel** — FR-011: recusa explicita nomeando a execucao que nao pode ser reconstruida. **MUST NOT** preencher com valor estimado. |

**Idempotencia**: re-executar sobre o mesmo transcript **MUST NOT** duplicar
spawns — dedup pela chave natural `(wave_id, agent_id)`.

---

## 4. Extensao de `state-ondas.sh end` (contrato EXISTENTE estendido)

`end` `[EXISTE]` (`state-ondas.sh:337`) hoje agrega o sidecar de ticks em
`:373-377` e grava em `:391-410`. A extensao adiciona, **no mesmo `jq`
transacional**, os campos definidos em `data-model.md`.

**Flags inalteradas** `[EXISTE]`: `--state-dir`, `--motivo-termino`
(`etapa_concluida_avancando|threshold_proxy_atingido|bloqueio_humano|aborto|concluido`),
`--proxima-agendada-para`, `--add-etapa` (repetivel). **Nenhuma flag nova.**

**Reset do sidecar**: `_so_ticks_reset` `[EXISTE]` (`:235`, chamado em `:282` e
`:417`) ganha um irmao para `wave-agent-usage.jsonl`, nos mesmos dois pontos.

**Herdado sem trabalho novo**: `_so_backup_current` + `_so_atomic_write` +
`_so_update_sha` (`:412-418`) ja cobrem backup, escrita atomica e recomputo de
hash. `reconcile-wave` (`:928`) e no-op idempotente em onda fechada
(`:947-956`), logo ondas recuperadas pelo comando pai herdam a agregacao.

---

## 5. Consumo em `review-task` §4.5 (contrato EXISTENTE estendido)

`global/skills/review-task/SKILL.md` §4.5 `[EXISTE]` (L138-206) hoje invoca:

```bash
~/.claude/skills/agente-00c-runtime/scripts/model-routing-report.sh \
  aggregate --state-dir "$STATE_DIR"
```

e cola a saida **verbatim** (invariante INV-RT-1, L458 — reformatar quebra o
contrato). A extensao adiciona uma segunda invocacao, mesma disciplina:

```bash
~/.claude/skills/agente-00c-runtime/scripts/wave-usage-report.sh \
  aggregate --state-dir "$STATE_DIR"
```

**Posicionamento**: imediatamente apos o bloco de model-routing (que fica entre
"Progresso por Fase" e "Recomendacoes"), para que modelo roteado e consumo
observado sejam lidos lado a lado — e o que torna FR-007/SC-003 verificavel sem
calculo manual.

**Regra de inclusao** (espelha a existente): incluir quando exit 0 e ha >= 1
linha de tabela; omitir quando nao ha nenhuma onda com metrica; registrar "skip
auditavel" em "Recomendacoes" quando exit != 0.

---

## 6. Extensao de `report.sh` (contrato EXISTENTE estendido)

`report.sh` `[EXISTE]` emite 6 secoes: `## 1. Resumo Executivo` (L80),
`## 2. Linha do Tempo` (L109), `## 3. Decisoes` (L130), `## 4. Bloqueios
Humanos` (L182), `## 5. Sugestoes para Skills Globais` (L246),
`## 6. Licoes Aprendidas` (L317).

**§1 Resumo Executivo** — hoje tem a linha `| Tool calls totais | ... |`
(L93). Ganha linhas irmas `[PROPOSTA]`: `Spawns de subagente`,
`Tokens totais (observados)`, `Cobertura da metrica`. A linha de cobertura e o
que impede ler um total parcial como completo.

**§2 Linha do Tempo** — a tabela por onda (L118) hoje tem colunas
`id | inicio | fim | etapas | tool_calls | wallclock | motivo`. Ganha
`spawns` e `tokens` `[PROPOSTA]`, com `indisponivel` onde nao ha dado.

**Retro-compatibilidade**: usar o padrao `(.campo // default)` ja adotado no
arquivo, de modo que state antigo renderize `indisponivel` sem erro.

---

## 7. Extensao da ingestao (`cli/lib/recall.sh`)

Ver `data-model.md` §"Extensao do knowledge.db: v9 -> v10" para as 9 colunas.

Pontos de toque `[EXISTE]`:

| Ponto | Linha | Mudanca |
|-------|-------|---------|
| `RECALL_SCHEMA_VERSION` | 106 | `9` -> `10` |
| DDL da tabela `waves` | 487-506 | +9 colunas |
| Migracao idempotente | 677-694 | +`case` com `PRAGMA table_info(waves)` |
| Bloco de ingestao de waves | 1005-1055 | +9 campos no array `@base64` e no `INSERT ... ON CONFLICT` |

**MUST** usar `recall_int_or_null` `[EXISTE]` em todas as colunas novas — onda
sem dado => `NULL`, jamais `0` (FR-009).

**MUST NOT** alterar a chave `UNIQUE(project, feature, wave, source_id)`.

Cobertura: `tests/cstk/test_recall.sh` `[EXISTE]`, com cenarios de migracao
v9->v10 preservando dados e de `NULL` para onda antiga.
