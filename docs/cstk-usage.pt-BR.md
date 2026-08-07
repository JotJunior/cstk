[English](./cstk-usage.md) · **Português (pt-BR)**

# Consumo avulso (`cstk usage`)

> **Trilha avançada** — opt-in, complementa a [Memória de conhecimento](./cstk-recall.pt-BR.md).

Rastreia o consumo de tokens/custo do Claude Code que acontece **fora** de
qualquer execução `agente-00c`/`feature-00c` — sessões interativas comuns.
Opt-in via a mesma configuração nativa de telemetria local que o Claude Code
já usa (sem um segundo toggle): um hook `PostToolUse` escreve um sidecar TSV
local por processo/segmento, com throttle e silencioso por design (nunca
bloqueia nem atrasa a sessão). O `cstk usage` lê esse sidecar mais a tabela
`loose_usage` do `knowledge.db` para reportar consumo por projeto/modelo, e
para comparar com o consumo de pipeline (orquestrador).

```bash
# Habilitar o hook de captura (opt-in, default DESLIGADO)
cstk hooks install --with-loose-usage

# Listar consumo avulso por projeto/modelo
cstk usage
cstk usage --project meu-projeto --since 2026-08-01 --json

# Comparar consumo avulso vs pipeline para um projeto (mix + custo blended/Mtok)
cstk usage compare --project meu-projeto

# Podar segmentos do sidecar + linhas indexadas acima do TTL de retencao
cstk usage prune --dry-run
cstk usage prune --older-than-days 30
```

## Subcomandos

- `usage [--project P] [--since ISO] [--limit N] [--json] [--db PATH]` —
  uma seção por projeto, uma linha por modelo (modelo, tokens, custo,
  participação). Campo sem medição imprime `nao medido` (texto) / `null`
  (`--json`), nunca `0`.
- `usage compare [--project P] [--since ISO] [--json] [--db PATH]` —
  `loose` (de `loose_usage`) vs `pipeline` (de `wave_model_usage`) lado a
  lado; agregado por categoria, nunca via JOIN linha a linha (granularidades
  diferentes). Inclui `blended_cost_per_mtok`
  (`SUM(cost_usd)/SUM(total_tokens)*1e6`; `null` quando a soma é zero/ausente).
- `usage prune [--dry-run] [--older-than-days N] [--db PATH]` — remove
  segmentos **fechados** do sidecar mais antigos que o TTL
  (`CSTK_LOOSE_USAGE_RETENTION_DAYS`, default `90`) mais as linhas
  `loose_usage` correspondentes. Segmentos abertos nunca são elegíveis.
  `--dry-run` reporta a mesma seleção sem nenhum efeito colateral.

**Requisitos**: `sqlite3`, `jq`. A captura exige o hook instalado
(`cstk hooks install --with-loose-usage`, opt-in, default DESLIGADO — nunca
empacotado junto dos guard hooks obrigatórios).

## Dados capturados

Apenas metadados de custo/token/modelo — `project`, `project_path`,
`process_key`, `segment_id`, `model`, `cost_usd`, `total_tokens`,
`segment_open`, `captured_at`, `ingested_at`. Não existe campo de conteúdo
de prompt/conversa no schema. Diretório/arquivos do sidecar usam permissão
restritiva (`chmod 700` em diretórios, `chmod 600` em arquivos), mesma
postura do `knowledge.db`.

## Documentação completa

- [`specs/loose-usage-capture/spec.md`](./specs/loose-usage-capture/spec.md) — user stories, FRs, success criteria
- [`specs/loose-usage-capture/contracts/cli-usage.md`](./specs/loose-usage-capture/contracts/cli-usage.md) — flags, exit codes, formatos de saída
- [`specs/loose-usage-capture/contracts/hook-loose-usage.md`](./specs/loose-usage-capture/contracts/hook-loose-usage.md) — contrato do hook de captura
- [`specs/loose-usage-capture/data-model.md`](./specs/loose-usage-capture/data-model.md) — schema + política de retenção
