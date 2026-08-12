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

## Gauge de uso do plano (`cstk statusline` + `cstk plan-usage`)

Desde a v7.2.0 o mesmo `knowledge.db` também guarda o **gauge de uso do
plano** que você vê no `/usage` — sem credencial OAuth, sem API key: o
Claude Code já envia `rate_limits.five_hour`/`seven_day` no payload da
`statusLine.command` a cada render, então o hook de captura
(`statusline-plan-usage.sh`) só lê o que já está passando e persiste na
tabela `plan_usage` (migração aditiva de schema 13→14).

```bash
# Habilitar a captura (opt-in, default DESLIGADO)
cstk statusline install

# A captura está ativa (e o settings.json válido)?
cstk statusline status

# Captura mais recente por escopo (five_hour / seven_day)
cstk plan-usage [--json] [--db PATH]

# Série temporal por escopo
cstk plan-usage history [--scope five_hour|seven_day] [--limit N] [--since ISO] [--json] [--db PATH]
```

- `statusline install` — escreve/atualiza `statusLine.command` em
  `~/.claude/settings.json` apontando para o hook de captura. Um comando de
  statusline customizado já existente é preservado em
  `CSTK_STATUSLINE_INNER_COMMAND` e encadeado como pass-through obrigatório
  do stdout — nunca sobrescrito em silêncio. Idempotente (rodar 2x não
  aninha wrapper sobre wrapper); desde a v7.2.1 também **repara** estado
  quebrado (`statusLine.type` ausente, que faz o harness descartar o arquivo
  inteiro) e preserva a permissão original do arquivo.
- `statusline status` — reporta o estado atual; imprime `INVALIDO` com a
  remediação (exit 1) quando o `settings.json` está num estado que o
  harness rejeitaria.
- `plan-usage` / `plan-usage history` — captura mais recente por escopo /
  série temporal; `history` reusa literalmente `--limit`/`--since` do
  `cstk usage` (sem convenção nova de paginação). Escopo sem medição
  imprime `nao medido` (texto) / `null` (`--json`) — nunca `0` fabricado.

Semântica da captura (Princípio VI): ausência TOTAL de `rate_limits` no
payload nunca gera linha; ausência PARCIAL de um campo dentro de um escopo
presente grava `NULL` explícito, nunca `0`. O throttle compara sempre contra
o **último registro persistido** daquele escopo, com tolerância de 2 casas
decimais em `used_percentage` — ruído de ponto flutuante do harness não gera
linha nova.

Spec: [`specs/plan-usage-capture/`](./specs/plan-usage-capture/)
([`contracts/cli-plan-usage.md`](./specs/plan-usage-capture/contracts/cli-plan-usage.md),
[`contracts/statusline-hook.md`](./specs/plan-usage-capture/contracts/statusline-hook.md),
[`data-model.md`](./specs/plan-usage-capture/data-model.md)).

## Documentação completa

- [`specs/_archived/2026-08-08-loose-usage-capture/spec.md`](./specs/_archived/2026-08-08-loose-usage-capture/spec.md) — user stories, FRs, success criteria
- [`specs/_archived/2026-08-08-loose-usage-capture/contracts/cli-usage.md`](./specs/_archived/2026-08-08-loose-usage-capture/contracts/cli-usage.md) — flags, exit codes, formatos de saída
- [`specs/_archived/2026-08-08-loose-usage-capture/contracts/hook-loose-usage.md`](./specs/_archived/2026-08-08-loose-usage-capture/contracts/hook-loose-usage.md) — contrato do hook de captura
- [`specs/_archived/2026-08-08-loose-usage-capture/data-model.md`](./specs/_archived/2026-08-08-loose-usage-capture/data-model.md) — schema + política de retenção
