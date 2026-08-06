# Contracts: `cstk usage` `[PROPOSTA — a validar na implementacao]`

Superficie de consulta do consumo avulso (FR-009 / SC-005). Subcomando NOVO —
**nao existe hoje**. A lista atual de subcomandos do dispatch em `cli/cstk` e
`install | update | self-update | list | doctor | session | serve | recall |
show-tip | hooks | state | mcp`; `usage` esta livre.

Convencoes herdadas do CLI existente: mensagens de erro em stderr, dados em
stdout, exit `0` sucesso / `1` erro geral / `2` uso incorreto (Constitution II).

---

## `cstk usage` (listagem por projeto)

**Comando**: `cstk usage [--project P] [--since ISO] [--limit N] [--json] [--db PATH]`
**Auth**: N/A (local, sem rede)

### Parametros

| Flag | Type | Required | Validation |
|------|------|----------|------------|
| `--project` | string | nao | Default: projeto do diretorio corrente |
| `--since` | ISO 8601 | nao | Filtra por `captured_at >= valor` |
| `--limit` | int | nao | Inteiro positivo; default `20` (paridade com `cstk recall`) |
| `--json` | flag | nao | Saida maquina-legivel em vez de texto |
| `--db` | path | nao | Override do `knowledge.db` (paridade com `cstk recall --db`) |

### Saida (texto, exit 0)

Uma secao por projeto com uma linha por modelo: modelo, tokens, custo e
participacao. Campo sem medicao imprime **`nao medido`**, nunca `0`
(FR-005 / SC-004).

### Saida (`--json`, exit 0)

Objeto com `project`, `category: "loose"` e `models[]`, onde cada item traz
`model`, `total_tokens`, `cost_usd`. Campos nao medidos sao `null` JSON —
a ausencia e representada por `null`, nunca por `0`.

### Comportamento sem dados

| Situacao | Saida | Exit |
|----------|-------|------|
| `knowledge.db` ausente | Aviso em stderr + `nao medido` | 0 |
| Tabela `loose_usage` vazia p/ o projeto | `nao medido — sem cobertura de captura` | 0 |
| `sqlite3` ausente | Aviso em stderr explicando a dep | 1 |
| Flag desconhecida | Uso em stderr | 2 |

> "Sem cobertura" e "medido e zero" sao mensagens DISTINTAS (FR-005). A
> distincao vem da existencia de linhas em `loose_usage`, nao do valor.

---

## `cstk usage compare` (avulso vs pipeline)

**Comando**: `cstk usage compare [--project P] [--since ISO] [--json] [--db PATH]`

Atende FR-009 e SC-005: mix de modelos e custo blended por milhao de tokens,
das duas categorias lado a lado, para o mesmo projeto.

### Fontes

| Categoria | Tabela | Situacao |
|-----------|--------|----------|
| `loose` | `loose_usage` | NOVA (`[PROPOSTA]`, schema v13) |
| `pipeline` | `wave_model_usage` | JA EXISTE — `cli/lib/recall.sh` linhas 625-637 (`project`, `model`, `cost_usd`, `total_tokens`) |

### Saida (por categoria)

| Campo | Type | Descricao |
|-------|------|-----------|
| `category` | enum `loose`\|`pipeline` | Conjunto fechado |
| `models[]` | array | `{model, total_tokens, cost_usd, share_pct}` |
| `blended_cost_per_mtok` | number \| null | `SUM(cost_usd)/SUM(total_tokens)*1e6` |

**Agregacao, nao JOIN**: as duas tabelas tem granularidades diferentes
(processo x segmento x modelo vs onda x modelo). A comparacao soma cada
categoria separadamente e as apresenta lado a lado — nunca correlaciona
linha a linha.

### Regras de ausencia

| Situacao | Resultado |
|----------|-----------|
| Categoria sem nenhuma linha | `nao medido` / `null`; a outra categoria ainda e exibida |
| `SUM(total_tokens)` = 0 ou NULL | `blended_cost_per_mtok = null` (divisao indefinida nao vira 0) |
| Ambas vazias | `nao medido` nas duas; exit 0 |

---

## Restricao de arquitetura (Constitution II)

`cli/lib/usage.sh` `[PROPOSTA]` **nao invoca `sqlite3` diretamente**: delega
aos helpers ja existentes de `cli/lib/recall.sh` (que hoje concentram
`recall_apply_schema`, `recall_run_sql`, `recall_query_sql`).

A regra ja esta escrita no codigo — `cli/lib/serve-docker.sh` linhas 11-13:
*"`cli/lib/recall.sh` (unico arquivo autorizado a `sqlite3`)"*.

Invariante verificavel na revisao (o `grep -l 'sqlite3'` simples NAO serve:
retorna 5 arquivos hoje, por casar comentarios, `sqlite3 --version` de
diagnostico em `doctor.sh` e o pacote npm `better-sqlite3` em
`serve-docker.sh`):

```sh
# Arquivos que ABREM banco via sqlite3 — deve continuar sendo so recall.sh
grep -nE '(^|[^-[:alnum:]_])sqlite3[[:space:]]+(-cmd[[:space:]]|--[[:space:]])' cli/lib/*.sh
```

(O espaco exigido apos `--` e o que exclui o `sqlite3 --version` de
diagnostico do `cli/lib/doctor.sh` linha 438, que nunca abre banco.)

Isso preserva a condicao (b) do carve-out de dep opcional (Constitution
Principio II, amendment 1.1.0): "codigo que referencia a dep confinado em UM
unico arquivo identificavel". Ver tambem `plan.md` §Principio II para o
detalhamento por arquivo.
