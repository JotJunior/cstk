# Contract: ordenacao composta e `--explain` no `cstk recall`

Contrato de interface de linha de comando afetado pela feature
`recall-ranking`. Estende o contrato existente de
[`cstk-recall.md`](../../_archived/cstk-knowledge-db/contracts/cstk-recall.md)
(modo busca) e
[`cstk-recall-context.md`](../../_archived/recall-autoconsume/contracts/cstk-recall-context.md)
(modo `--context`), **sem revoga-los**.

> **Marcacao de veracidade (Constitution VI)**: o que ja existe hoje foi
> extraido por leitura direta de `cli/lib/recall.sh` e esta marcado
> **[ATUAL]**. O que esta feature propoe e novo e esta marcado
> **[PROPOSTA — a validar na implementacao]**.

## 1. Comando: `cstk recall <query> [flags]` (modo busca)

### 1.1 Flags

| Flag | Tipo | Default | Status |
|------|------|---------|--------|
| `--project P` | string | (sem filtro) | [ATUAL] |
| `--type T` | enum | (sem filtro) | [ATUAL] |
| `--limit N` | inteiro positivo | `20` | [ATUAL] |
| `--db PATH` | path | `~/.claude/cstk/knowledge.db` | [ATUAL] |
| `--explain` | booleana (sem valor) | ausente | **[PROPOSTA]** |

Enum de `--type` [ATUAL]: `decision`, `block`, `retro`, `skill`, `memory`,
`suggestion` (`RECALL_TYPE_ENUM`, `cli/lib/recall.sh` linha 164; alias
deprecado `bloqueio` -> `block`).

`--explain` [PROPOSTA] e **booleana**: nao consome o proximo argumento.
Repeticoes sao idempotentes. Invalida em qualquer outro modo (`--ingest`,
`--reindex`, `--context`, `--list-memories`) — nesses modos o parser ja
rejeita flags desconhecidas com `RECALL_EXIT_USAGE` (exit 2), comportamento
[ATUAL] que se aplica sem mudanca.

### 1.2 Ordenacao

**[ATUAL]** `ORDER BY bm25(knowledge_fts) LIMIT N` (`cli/lib/recall.sh`
linha 3067).

**[PROPOSTA]** ordenacao pelo score composto, com desempate total:

```
ORDER BY <score> ASC, source_ts DESC, type ASC, source_id ASC
LIMIT N
```

onde:

```
<score> = bm25(knowledge_fts)
        - <bonus_autoridade>
        - <bonus_recencia>
```

| Componente | Definicao | Faixa |
|------------|-----------|-------|
| `bm25(knowledge_fts)` | relevancia textual FTS5, negativa; mais negativo = mais relevante | observado -11.6 .. -4.9 |
| `<bonus_autoridade>` | `CASE type WHEN 'decision'/'block' -> 0.30; 'memory' -> 0.15; 'retro'/'skill' -> 0.00; ELSE 0.15` | `[0.00, 0.30]` |
| `<bonus_recencia>` | `coalesce(0.10 * (90.0 / (90.0 + <idade_dias>)), 0.0)` | `[0.00, 0.10]` |
| `<idade_dias>` | `max(0.0, julianday(<instante_ref>) - julianday(nullif(source_ts,'')))` | `NULL` quando `source_ts` vazio |

> O `max(0.0, ...)` e **normativo**. Sem ele, `source_ts` no futuro produz
> `<idade_dias>` negativa, o denominador encolhe e o bonus **excede o teto
> declarado em ordens de grandeza** (medido: `-80d` -> `0.9`; `-89.99d` ->
> `~900`), quebrando I-1, I-2 e a faixa `[0.00, 0.10]` desta tabela. Ver
> research.md D6.
>
> O `coalesce` e **externo ao produto inteiro** e assim deve permanecer.
> Move-lo para dentro do denominador (`90.0 + coalesce(<idade_dias>, 0.0)`)
> daria bonus **maximo** ao achado sem `source_ts`, invertendo FR-008. A
> divisao por zero (`source_ts` exatamente `<instante_ref> + 90d`, so
> alcancavel sem o clamp) resulta em `NULL` no SQLite — nao em erro — e e
> absorvida por esse mesmo `coalesce` externo.

Invariantes do contrato:

- **I-1**: `0 <= <bonus_autoridade> <= 0.30` e
  `0 <= <bonus_recencia> <= 0.10` para **qualquer** valor de `source_ts` —
  incluindo vazio, malformado e no futuro. Garantido por construcao pelo
  ramo `ELSE` do `CASE`, pelo `max(0.0, ...)` e pelo `coalesce` externo, nao
  por suposicao sobre o dominio dos dados. O score nunca e maior (menos
  relevante) que o `bm25()` puro.
- **I-2**: `max(<bonus_recencia>) = 0.10 < 0.15 = menor degrau de
  autoridade`. Recencia **nunca** inverte a ordem entre dois tiers de
  autoridade distintos com `bm25()` igual. Depende de I-1 valer no dominio
  inteiro — por isso o clamp e normativo, e nao uma otimizacao.
- **I-3**: tipo fora do enum cai no ramo `ELSE` (0.15). Nenhum tipo produz
  `NULL`, erro ou exclusao.
- **I-4**: `source_ts` vazio/ausente produz `<bonus_recencia> = 0.0` e a
  linha **permanece** no resultado.
- **I-5**: o `<instante_ref>` e resolvido **uma unica vez por invocacao** e
  interpolado como literal. `julianday('now')` nao aparece na consulta.
- **I-6**: a expressao de score e construida no **mesmo nivel de SELECT** que
  contem o `MATCH` (restricao do FTS5; ver research.md D2).

### 1.2.bis Ordem das colunas projetadas [PROPOSTA — normativa]

O render atual faz `awk -F '\\|@\\|'` com **indices fixos**, e `body` e a
**ultima** coluna (`$7`). As colunas numericas de score, quando projetadas,
**MUST** vir **antes** de `body` no `SELECT`, mantendo `body` como ultima
coluna.

**Por que e normativo**: `body` e conteudo indexado, nao controlado pelo
runtime. Um `body` que contenha a sequencia separadora `|@|` desloca os
indices do `awk`. Hoje isso causa apenas truncagem visual do corpo. Se as
colunas de score forem anexadas **depois** de `body`, o mesmo `body` passa a
deslocar os campos numericos, e a linha `score=` renderiza **texto vindo do
conteudo indexado** no lugar dos numeros reais — ou seja, o proprio canal de
auditoria do ranking passa a ser falsificavel por quem escreve no indice.

Projecao normativa (modo busca):

```
SELECT type, project, feature, wave, source_ts, source_id,
       <score>, <bm25>, <bonus_autoridade>, <bonus_recencia>, <idade_dias>,
       body
FROM knowledge_fts ...
```

Sem `--explain`, as colunas de score **podem** ser omitidas da projecao (o
render default nao as consome); se forem projetadas, a posicao acima
continua valendo. `body` permanece a ultima coluna nos dois casos —
preservando FR-006.

### 1.3 Saida sem `--explain` [ATUAL — inalterada, FR-006]

Dois `printf` por resultado, byte-identicos ao comportamento atual:

```
[<type>] <project> / <feature> / <wave> / <source_ts> (<source_id>)
  <body>

```

Apenas a **ordem** dos resultados pode mudar. Nenhum byte do formato muda.

### 1.4 Saida com `--explain` [PROPOSTA]

Formato aditivo: as duas linhas de 1.3 permanecem **inalteradas**, seguidas
de **uma** linha de explicacao antes da linha em branco separadora:

```
[<type>] <project> / <feature> / <wave> / <source_ts> (<source_id>)
  <body>
  score=<S> = bm25=<B> - autoridade=<A> - recencia=<R> (idade=<D>d)

```

| Campo | Origem | Formato |
|-------|--------|---------|
| `<S>` | score composto final | numerico, 4 casas decimais |
| `<B>` | `bm25(knowledge_fts)` | numerico, 4 casas decimais |
| `<A>` | bonus de autoridade aplicado | numerico, 2 casas decimais |
| `<R>` | bonus de recencia aplicado | numerico, 4 casas decimais |
| `<D>` | idade em dias | numerico, 1 casa decimal; `n/d` quando `source_ts` vazio |

Requisitos:

- **C-1** (SC-004): quando `--explain` esta presente, **100%** dos
  resultados retornados exibem a linha de explicacao — inclusive os de
  `source_ts` vazio (que mostram `recencia=0.0000 (idade=n/d)`).
- **C-2**: a linha comeca com dois espacos, alinhada ao corpo, e **nao**
  comeca com `[` — preservando a contagem de blocos por
  `grep -c '^\['` usada por `scenario_04_limite_e_bm25`
  (`tests/cstk/test_recall.sh` linha 143).
- **C-3**: a identidade `<S> = <B> - <A> - <R>` deve ser verificavel na
  saida dentro da tolerancia de arredondamento exibida.

### 1.5 Exit codes [ATUAL — inalterados]

| Codigo | Situacao |
|--------|----------|
| `0` | sucesso, inclusive "nenhum resultado", `sqlite3` ausente, indice ausente, indice corrompido |
| `2` | erro de uso (flag invalida, `--limit` nao-inteiro, `--type` fora do enum, byte NUL em input) |

**I-7**: a feature **nao introduz nenhum caminho de erro novo**. A
degradacao graciosa (aviso em stderr + `exit 0`) permanece invariante em
todos os caminhos de falha de infraestrutura.

**I-10 [PROPOSTA]**: falha de **execucao da consulta** MUST ser distinguivel
de "nenhum resultado". Hoje `recall_query_sql` descarta stderr (`2>/dev/null`)
e ambos os callers mapeiam falha para string vazia (`|| _se_out=""`,
`|| _cx_out=""`), de modo que uma SQL que nao compile produz "nenhum
resultado" no modo busca e **stdout vazio** no `--context`, com exit `0`. Se
a expressao de score falhar (interpolacao malformada, mudanca futura do
SQLite, violacao de I-6), o read-back loop dos orquestradores desapareceria
**sem sinal algum** e a pipeline seguiria decidindo sem memoria, acreditando
que nao havia aprendizado a recuperar. Exigido: checar o exit do `sqlite3`
separadamente do resultado vazio e emitir `log_warn` em **stderr** quando a
consulta falhou — mantendo `exit 0` e stdout intactos (I-7 preservada).

## 2. Comando: `cstk recall --context <termos> [flags]`

### 2.1 O que muda

**Apenas a ordem dos achados** — a mesma expressao de score e desempate da
secao 1.2, aplicada em `cli/lib/recall.sh` linha 3216.

### 2.2 O que NAO muda [ATUAL — preservado integralmente, FR-004/SC-002]

- Flags aceitas: `--project`, `--type`, `--exclude-feature`, `--limit`
  (default `4`), `--max-bytes` (default `2000`), `--db`. **`--explain` nao
  e aceita** e continua caindo no ramo de flag invalida (exit 2).
- Cabecalho UNTRUSTED de 4 linhas, integral e byte-identico, incluindo a
  frase-contrato `Aprendizado recuperado (read-back loop)`.
- Render de 1 linha por achado:
  `- **[<type>]** <project>/<feature>/<wave> (<source_ts>): <body>`
- Truncagem do corpo em 280 chars com sufixo `...`.
- Teto duro `--max-bytes` cortando pelo **ultimo achado inteiro** que cabe.
- `K=0` (nenhum achado) => stdout **vazio**, sem cabecalho orfao, exit 0.
- Se nem o primeiro achado cabe no teto => stdout vazio, exit 0.
- Anti-eco `--exclude-feature` aplicado no SQL.

**I-8**: nenhum componente de score aparece no bloco de contexto. O
orcamento de bytes e integralmente gasto com conteudo, como hoje.

## 3. Relogio de referencia para teste — **RATIFICADO: sem variavel de ambiente**

> **Status**: **RATIFICADO** pelo operador (bloqueio `block-002`, decisao
> `dec-021`, 2026-08-20). O gate `owasp-security` classificou o mecanismo
> originalmente proposto — variavel de ambiente interpolada na SQL — como
> **HIGH** em dois findings independentes (F1/F3/F4). A escolha ratificada
> foi **eliminar a superficie**, nao blinda-la. Ver research.md D13.

Necessidade a atender: tornar a ordem por recencia (secao 1.2) asserivel de
forma deterministica pela suite.

### 3.1 Mecanismo normativo

A suite gera os `source_ts` da fixture **relativos ao relogio real** no
momento em que a fixture e montada (ex.: `now-5d`, `now-200d`, `now-400d`) e
assere a **ordem relativa** das idades. O `<instante_ref>` da secao 1.2
permanece sendo **sempre** o instante corrente resolvido uma unica vez por
invocacao (I-5), em producao e em teste, sem excecao.

Clausulas normativas:

| Aspecto | Definicao normativa |
|---------|---------------------|
| Origem do `<instante_ref>` | **exclusivamente** o relogio real, via `date -u`, resolvido uma vez por invocacao (I-5) |
| Configurabilidade | **nenhuma**. Nao ha variavel de ambiente, flag de CLI, arquivo de config nem argumento que altere o `<instante_ref>` |
| Interpolacao na SQL | o unico valor de instante interpolado e o produzido internamente por `date -u`; **nenhum valor de origem externa** (ambiente, argv, arquivo, indice) entra na expressao de idade |
| Fixture de teste | `source_ts` calculados como deslocamentos do instante corrente no proprio teste; asserção sobre **ordem relativa**, nunca sobre valor absoluto |
| Tolerancia de fronteira | cenarios de recencia MUST usar deslocamentos com folga ampla entre si (ordens de grandeza de dias), de modo que a passagem do tempo durante o run nao altere a ordem esperada |
| Escaping cumulativo do literal | o valor produzido por `date -u` MUST passar por `sql_escape()` antes de ser interpolado, **mesmo sendo de origem interna**. Nao e defesa contra o `date`: e conformidade com a politica cumulativa ja vigente no arquivo, onde **todo** valor interpolado — inclusive timestamps internos — passa por `sql_escape` (precedente: `cli/lib/recall.sh` L1384, `'$(sql_escape "$_isj_now")'`). Sem isso, a expressao de score seria o unico ponto do arquivo a interpolar valor cru |
| Falha do `date` | se `date -u` falhar ou retornar vazio, o `<instante_ref>` MUST cair no fallback ja usado no arquivo (`1970-01-01T00:00:00Z`, L1273/L2203/L2803/L2866). Consequencia deliberada: todas as idades ficam enormes, `<bonus_recencia>` tende a `0` para todas as linhas e o ranking degrada para `bm25 - autoridade` — degradacao **uniforme**, que preserva I-1/I-2/I-7 e nunca promove um achado sobre outro. **Proibido** interpolar string vazia sem clausula explicita |
| Fronteira de arredondamento | cenarios que assertam **igualdade byte-a-byte** de stdout entre duas execucoes consecutivas (Scenario 6) MUST usar idades afastadas de fronteiras de arredondamento dos campos de `--explain` (`recencia` 4 casas, `idade` 1 casa). Ver I-13 |

**I-12 [nova, normativa]**: `cli/lib/recall.sh` **MUST NOT** ler nenhuma
variavel de ambiente nova para compor a expressao de score. Verificavel por
inspecao estatica **por allowlist exata**: o conjunto de nomes casados por
`grep -oE 'CSTK_[A-Z_]+' cli/lib/recall.sh | sort -u` MUST permanecer
`CSTK_COMMON_LOADED`, `CSTK_KNOWLEDGE_DB`, `CSTK_LIB` — o conjunto medido
antes desta feature. Allowlist, e nao padrao negativo: um padrao como
`CSTK_[A-Z_]*(REF|INSTANT|CLOCK|NOW)` casa `CSTK_KNOWLEDGE_DB` por acidente
lexico (`NOW` dentro de `KNOWLEDGE`) e reprovaria antes de qualquer
implementacao. Ver quickstart Scenario 15.

**I-13 [nova, normativa — escopo do determinismo]**: o determinismo exigido
por FR-009 e garantido **por construcao dentro de uma invocacao** (I-5: um
unico `<instante_ref>` para todas as linhas). **Entre** invocacoes
separadas, o `<instante_ref>` avanca com o relogio real; a ordem permanece
estavel porque o deslocamento (segundos) e desprezivel frente a meia-vida de
90 dias, e a saida default (secao 1.3) nao expoe valor algum de score. A
igualdade **byte-a-byte** entre duas execucoes so e assegurada quando as
idades da fixture nao caem em fronteira de arredondamento dos campos de
`--explain`. Esta e uma afirmacao de escopo, nao uma garantia absoluta: a
redacao anterior, que dependia de um relogio congelado por variavel de
ambiente, deixou de existir junto com a variavel.

### 3.2 Consequencias de seguranca (por construcao, nao por vigilancia)

Com a Opcao B ratificada, os findings F1, F3 e F4 do gate `owasp-security`
tornam-se **inaplicaveis por construcao**, e nao "mitigados":

- Nao existe valor de origem externa interpolado no caminho de leitura,
  logo nao existe a injecao que tornava relevante o fato de
  `recall_query_sql()` abrir o DB em **read-write** (`sqlite3 -cmd '.timeout
  5000' -- "$DB"`, sem `mode=ro`).
- Nao existe configuracao nova a validar, escapar ou auditar; nenhum
  hardening precisa ser mantido correto ao longo do tempo.
- Nao existe bypass da denylist do `bash-guard.sh` via `VAR=<payload> cstk
  recall ...`, porque nenhuma variavel de ambiente influencia a consulta.

> **Limite honesto destas afirmacoes (escopo declarado)**: elas valem para
> **a superficie que esta feature adicionaria**. O `<instante_ref>` continua
> sendo produzido por um `date` resolvido via `PATH`, e o processo herda o
> ambiente do usuario — quem ja controla `PATH` do processo nao precisa
> desta feature para nada. O que se afirma e mais estreito e verificavel:
> **nenhum canal de configuracao novo** e criado, e o unico valor
> interpolado na expressao de idade e produzido internamente e escapado
> (§3.1). Nao se afirma que o caminho de leitura do `recall` como um todo
> esteja endurecido — ele nao esta, e a linha abaixo diz por que.

> **Observacao registrada, fora do escopo desta feature**: o fato de
> `recall_query_sql()` abrir o DB em read-write enquanto
> `recall_query_sql_ro()` ja existe permanece uma aspereza preexistente do
> caminho de leitura. Esta feature **nao** a corrige e **nao** a agrava —
> apenas deixa de adicionar superficie sobre ela.

### 3.3 Invariantes desta secao

- **I-9 [corrigida]**: a ordenacao composta **nao altera formato de saida
  nem exit code**; **altera a ordenacao e, portanto, pode alterar quais
  achados entram sob `LIMIT`**. A redacao anterior ("nunca altera ...
  conteudo") era factualmente falsa: sob `LIMIT N` a ordenacao determina o
  conjunto retornado, e no modo `--context` (default `--limit 4`) esse
  conjunto e injetado no prompt de agentes autonomos.
- **I-11 [revisada apos ratificacao]**: nao ha valor externo de relogio a
  ser invalido. A degradacao graciosa exigida (`exit 0`, stdout intacto)
  permanece coberta por I-7 para os caminhos que de fato existem —
  `source_ts` vazio, malformado ou no futuro (I-1/I-4 + clamp da secao 1.2).

## 4. Fora de escopo (restricoes negativas verificaveis)

| Restricao | FR |
|-----------|-----|
| Nenhuma tool MCP exposta; `mcp/state-server/` intocado | FR-012 |
| Nenhum RRF (reciprocal-rank fusion) | FR-011 |
| Nenhum ranking por grafo de links entre achados | FR-011 |
| Nenhuma alteracao de DDL; `RECALL_SCHEMA_VERSION` permanece `15` | FR-007 |
| Nenhum reindex/migracao exigido do operador | SC-005 |
| Nenhum arquivo alem de `cli/lib/recall.sh` e `tests/cstk/test_recall.sh` | Constitution II |
| **Nenhuma variavel de ambiente nova** lida por `cli/lib/recall.sh`; nenhum override do `<instante_ref>` (secao 3.1, I-12) | dec-021 / block-002 |
