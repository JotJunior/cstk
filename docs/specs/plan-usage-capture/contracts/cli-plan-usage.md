# Contracts: `cstk plan-usage` `[PROPOSTA — a validar na implementacao]`

Superficie de consulta do uso do plano (FR-007/FR-008). Subcomando NOVO —
**nao existe hoje**. Lista atual de subcomandos do dispatch em `cli/cstk`
(`grep -n 'case "\$1"' -A40 cli/cstk`, verificado nesta onda): `install |
update | self-update | list | doctor | session | serve | recall |
show-tip | hooks | state | mcp | usage` — `plan-usage` esta livre.

Convencoes herdadas do CLI existente: mensagens de erro em stderr, dados
em stdout, exit `0` sucesso / `1` erro geral / `2` uso incorreto
(Constitution II).

---

## `cstk plan-usage` (uso mais recente — FR-007)

**Comando**: `cstk plan-usage [--json] [--db PATH]`

Retorna a captura mais recente de `five_hour` e `seven_day`, sem
credencial OAuth.

### Parametros

| Flag | Type | Required | Validation |
|------|------|----------|------------|
| `--json` | flag | nao | Saida maquina-legivel em vez de texto |
| `--db` | path | nao | Override do `knowledge.db` (paridade com `cstk usage --db`) |

### Saida (texto, exit 0)

Duas linhas, uma por escopo: percentual usado + horario de reset
(convertido para local time na apresentacao — a persistencia continua
epoch, FR-003). Campo sem medicao imprime **`nao medido`**, nunca `0`
(FR-002/SC-002).

### Saida (`--json`, exit 0)

```json
{
  "five_hour": {"used_percentage": 7.000000000000001, "resets_at": 1786372200, "captured_at": "2026-08-10T13:00:00Z"},
  "seven_day": {"used_percentage": null, "resets_at": null, "captured_at": null}
}
```

`used_percentage`/`resets_at`/`captured_at` sao `null` JSON quando o
escopo nunca teve nenhuma captura com `rate_limits` presente — a ausencia
e representada por `null`, nunca por `0` (SC-002).

### Comportamento sem dados

| Situacao | Saida | Exit |
|----------|-------|------|
| `knowledge.db` ausente | Aviso em stderr + `nao medido` para os 2 escopos | 0 |
| Tabela `plan_usage` vazia | `nao medido — nenhuma captura registrada ainda` | 0 |
| `sqlite3` ausente | Aviso em stderr explicando a dep | 1 |
| Flag desconhecida | Uso em stderr | 2 |

---

## `cstk plan-usage history` (serie temporal — FR-008)

**Comando**: `cstk plan-usage history [--scope five_hour|seven_day] [--limit N] [--since ISO] [--json] [--db PATH]`

Atende FR-008/User Story 2: evolucao do uso ao longo do tempo, por
escopo, em ordem cronologica.

### Parametros

| Flag | Type | Required | Validation |
|------|------|----------|------------|
| `--scope` | enum `five_hour`\|`seven_day` | nao | Default: ambos os escopos, series separadas (FR-005) |
| `--limit` | int | nao | Inteiro positivo; default `20` — **reusa literalmente a mesma convencao de `cstk usage --limit`** (dec-014/Q5, resolvida via bloqueio `block-002`) |
| `--since` | ISO 8601 | nao | Filtra por `captured_at >= valor` — **reusa a mesma flag de `cstk usage --since`** (dec-014) |
| `--json` | flag | nao | Saida maquina-legivel |
| `--db` | path | nao | Override do `knowledge.db` |

**Sem convencao nova de paginacao**: dec-014 e explicita — nao inventar
cursor/offset novo; `--limit`/`--since` sao os UNICOS controles, ja
existentes em `cstk usage` e agora reusados aqui verbatim.

### Saida (texto, exit 0)

Uma secao por escopo (quando `--scope` omitido, as duas secoes aparecem,
nunca misturadas — FR-005), cada uma com ate `--limit` linhas em ordem
cronologica: timestamp (`captured_at`) + percentual usado.

### Saida (`--json`, exit 0)

```json
{
  "five_hour": [
    {"used_percentage": 6.5, "resets_at": 1786372200, "captured_at": "2026-08-10T12:00:00Z"},
    {"used_percentage": 7.0, "resets_at": 1786372200, "captured_at": "2026-08-10T13:00:00Z"}
  ]
}
```

Chave presente so para o(s) escopo(s) pedido(s); array vazio (nao `null`)
quando o escopo existe mas nao tem captura no filtro pedido.

### Comportamento sem dados

Mesma tabela de `cstk plan-usage` acima (`knowledge.db` ausente / tabela
vazia / `sqlite3` ausente / flag desconhecida).

---

## `cstk plan-usage ingest --stdin` (uso interno, NAO documentado como
superficie publica)

Consumido exclusivamente por
`plugins/cstk/skills/agente-00c-runtime/hooks/statusline-plan-usage.sh`
(research.md Decision 6) — recebe o payload bruto da statusline via stdin,
aplica o throttle (FR-010) e insere em `plan_usage` quando aplicavel.
Sem flags de usuario, sem entrada na tabela de help publica de
`cstk plan-usage --help` (mesmo tratamento que outros subcomandos internos
do dispatch, se existirem precedentes — a decomposicao exata fica para
`create-tasks`).

Exit sempre `0` mesmo em erro interno (o hook que o invoca NUNCA pode
propagar falha para a sessao do operador — FR-011/Principio IV, mesma
disciplina fail-open de `posttooluse-loose-usage.sh`).
