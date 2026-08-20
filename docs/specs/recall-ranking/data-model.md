# Data Model: Ranking Composto no cstk recall

## Veredito: nenhuma entidade persistida nova

Esta feature **nao cria, altera ou remove nenhuma estrutura persistida**.
Registrado explicitamente em vez de omitido, para que `/analyze` e o gate de
convergencia possam distinguir "N/A justificado" de "esquecido".

| Aspecto | Situacao |
|---------|----------|
| Tabelas novas | Nenhuma |
| Colunas novas | Nenhuma |
| Indices novos | Nenhum |
| `RECALL_SCHEMA_VERSION` | Permanece **15** (`cli/lib/recall.sh` linha 161) |
| Migracao exigida | Nenhuma (FR-007 / SC-005) |
| Reindex exigido | Nenhum |

**Motivo**: as duas Key Entities da spec sao **projecoes efemeras**,
calculadas dentro da consulta SQL e descartadas ao fim da invocacao. Nada
delas sobrevive ao processo. Ver `research.md` D1 para a decisao e as
alternativas persistentes rejeitadas.

## Estrutura existente consumida (somente leitura)

`knowledge_fts` — tabela virtual FTS5 ja existente, **intocada** por esta
feature. DDL em `cli/lib/recall.sh` linhas 700-708:

| Coluna | Indexada | Uso nesta feature |
|--------|----------|-------------------|
| `body` | sim (FTS) | alimenta `bm25()` via `MATCH` |
| `type` | `UNINDEXED` | entrada do `CASE` de autoridade |
| `project` | `UNINDEXED` | filtro `--project` (ja existente) |
| `feature` | `UNINDEXED` | anti-eco `--exclude-feature` (ja existente) |
| `wave` | `UNINDEXED` | apenas proveniencia na saida |
| `source_id` | `UNINDEXED` | desempate final |
| `source_ts` | `UNINDEXED` | entrada do calculo de recencia + desempate |

> FTS5 **nao** suporta `ALTER TABLE ... ADD COLUMN`; materializar um score
> exigiria recriar a tabela e reindexar, violando FR-007/SC-005 e a
> invariante C-004 (indice derivado, reconstruivel, nunca fonte de verdade).

## Entity: Resultado de Busca (efemera — linha de resultado da consulta)

Projecao por linha, existente apenas durante a execucao da consulta.

| Campo | Tipo | Origem | Notas |
|-------|------|--------|-------|
| `type` | text | coluna de `knowledge_fts` | enum `RECALL_TYPE_ENUM` (linha 164) |
| `project` | text | coluna | proveniencia |
| `feature` | text | coluna | proveniencia |
| `wave` | text | coluna | proveniencia |
| `source_ts` | text | coluna | ISO 8601 `YYYY-MM-DDTHH:MM:SSZ`; pode ser `''` |
| `source_id` | text | coluna | parte da chave natural |
| `body` | text | coluna | ja filtrado por `secrets-filter` na ingestao |
| `relevancia_textual` | real | `bm25(knowledge_fts)` | **negativa**; mais negativo = mais relevante |
| `bonus_autoridade` | real | `CASE` sobre `type` | `[0.00, 0.30]`, nunca `NULL` |
| `bonus_recencia` | real | decaimento hiperbolico sobre a idade **clampada** (`max(0.0, ...)`) | `[0.00, 0.10]` para qualquer `source_ts`, nunca `NULL` |
| `score` | real | `relevancia - bonus_autoridade - bonus_recencia` | chave de ordenacao primaria |

### Restricoes

- **R-1**: `0 <= bonus_autoridade <= 0.30` e `0 <= bonus_recencia <= 0.10`,
  nunca `NULL`, para **qualquer** valor de `source_ts` — vazio, malformado ou
  no futuro. Garantido por tres mecanismos: ramo `ELSE` do `CASE`,
  `max(0.0, ...)` sobre a idade e `coalesce` **externo ao produto inteiro**.
  Sem o clamp, `source_ts` futuro levaria `bonus_recencia` a ordens de
  grandeza acima do teto (research.md D6).
- **R-2**: `score` e sempre numerico. Nenhuma linha pode produzir `score
  NULL` (o que a ordenaria de forma dependente de implementacao).
- **R-3**: a ordem total e `(score ASC, source_ts DESC, type ASC,
  source_id ASC)` — deterministica para o mesmo conjunto de dados e
  instante de referencia (FR-009).
- **R-4**: `bm25()` so e resolvivel no nivel de SELECT que contem o `MATCH`
  (research.md D2) — a projecao nao pode ser aninhada em subquery.

### Ciclo de vida

```
consulta emitida -> linhas casadas por MATCH -> componentes calculados na SQL
  -> ordenacao por score -> LIMIT N -> render em stdout -> descartado
```

Nenhuma etapa escreve em disco.

## Entity: Explicacao de Ranking (efemera — apenas com `--explain`)

Decomposicao por resultado, materializada **somente** como texto de saida
quando a flag esta presente. Nao e persistida nem serializada em formato de
maquina.

| Campo | Tipo | Origem | Precisao exibida |
|-------|------|--------|------------------|
| `score` | real | score composto final | 4 casas |
| `bm25` | real | `relevancia_textual` | 4 casas |
| `autoridade` | real | `bonus_autoridade` | 2 casas |
| `recencia` | real | `bonus_recencia` | 4 casas |
| `idade_dias` | real \| `n/d` | idade calculada | 1 casa; `n/d` quando `source_ts` vazio |

### Restricoes

- **R-5**: presente para **100%** dos resultados quando `--explain` e usada
  (SC-004), inclusive os de `source_ts` vazio.
- **R-6**: ausente por completo quando a flag nao e usada (FR-006 —
  identidade byte-a-byte do formato default).
- **R-7**: nunca aparece no modo `--context` (FR-004 / I-8 do contrato).
- **R-8**: `score = bm25 - autoridade - recencia` deve fechar na saida
  dentro da tolerancia de arredondamento exibida.

### State transitions

N/A — ambas as entidades sao imutaveis dentro de uma invocacao: sao
calculadas uma vez, renderizadas e descartadas. Nao ha maquina de estados.
