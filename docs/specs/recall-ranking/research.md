# Research: Ranking Composto no cstk recall

Documento produzido no Phase 0 do `/plan` para a feature `recall-ranking`.
Resolve os unknowns tecnicos antes do design.

> **Aterramento (Constitution VI)**: todo numero, nome de funcao, numero de
> linha e formato de dado citado abaixo foi obtido por leitura direta de
> `cli/lib/recall.sh` ou por consulta executada contra o indice real
> `~/.claude/cstk/knowledge.db` em 2026-08-20. Nenhum valor foi estimado.
> As medicoes de calibracao estao reproduzidas em `quickstart.md`
> (Scenario 8) para reexecucao independente.

## Medicoes de base (fonte de toda calibracao deste documento)

Consultas executadas contra `~/.claude/cstk/knowledge.db` (sqlite3 3.51.0),
2026-08-20.

**M1 — Distribuicao de tipos no indice** (`SELECT type, count(*) FROM
knowledge_fts GROUP BY type`):

| type | linhas |
|------|--------|
| decision | 6870 |
| skill | 1467 |
| block | 248 |
| suggestion | 112 |
| retro | 2 |
| memory | 0 |

**M2 — Formato de `source_ts`** (`SELECT length(source_ts), count(*) ...
GROUP BY 1`): 8698 linhas com `length=20` no formato ISO
`YYYY-MM-DDTHH:MM:SSZ`; **exatamente 1 linha** (`type='block'`) com
`source_ts=''` (`length=0`). O edge case de FR-008 e real e reproduzivel no
indice de producao, nao hipotetico.

**M3 — Dispersao de `bm25()` por consulta** (top-20 por consulta, `amplitude
= max-min`, `gap_medio` = media da diferenca entre vizinhos consecutivos):

| consulta | linhas | faixa bm25 | amplitude | gap medio | tipos presentes |
|----------|--------|------------|-----------|-----------|-----------------|
| `lock` | 20 | -8.494 .. -6.315 | 2.179 | 0.1147 | decision, block |
| `cache` | 20 | -8.666 .. -5.407 | 3.259 | 0.1715 | decision, block, suggestion |
| `secrets` | 20 | -8.660 .. -4.888 | 3.772 | 0.1985 | decision, suggestion, block |
| `ranking` | 9 | -11.606 .. -7.648 | 3.958 | 0.4947 | decision, block |
| `sqlite` | 20 | -7.274 .. -5.646 | 1.628 | 0.0857 | decision, suggestion |
| `hook` | 20 | -6.750 .. -5.945 | 0.805 | 0.0424 | decision, suggestion |

Leitura: `bm25()` e **negativo** (mais negativo = mais relevante); a ordem
atual `ORDER BY bm25(...)` e ASC. A coluna `gap medio` acima e a **media por
consulta**, e essas medias vao de **0.042 a 0.495** (mediana das 6 medias =
**0.143**). Olhando os 103 gaps **individuais** da amostra, a mediana e
**0.0665** e o maximo e **1.0898**. Ja a amplitude do top-20 inteiro varia de
**0.805 a 3.958**. Essa
separacao de uma ordem de grandeza entre "vizinhos" e "extremos da lista" e
a base quantitativa de toda a calibracao em D3 e D6.

**M4 — Faixa etaria real do indice** (`julianday('now') -
julianday(nullif(source_ts,''))`): de **0.0** a **100.9 dias**.

---

## Decision 1: Onde o score composto e computado

**Decision**: o score composto e computado como **expressao SQL na propria
consulta FTS**, dentro de `recall_mode_search()` e `recall_mode_context()`.
Nao ha pos-processamento de ordenacao em shell, nem coluna nova, nem tabela
auxiliar.

**Rationale**: o schema `knowledge_fts` (DDL em `cli/lib/recall.sh` linha
700-708) e uma tabela virtual FTS5 com todas as colunas de metadado
`UNINDEXED`. FTS5 nao suporta `ALTER TABLE ... ADD COLUMN`, e recriar a
tabela para materializar um score exigiria reindexacao — violando FR-007
(ranking deve valer sobre dados ja indexados) e SC-005 (zero passos manuais
de migracao). Computar na consulta mantem `RECALL_SCHEMA_VERSION=15`
inalterado e o indice intocado (invariante C-004 da feature
`cstk-knowledge-db`). Ordenar em shell exigiria trazer todas as linhas
casadas para memoria antes de aplicar `LIMIT`, degradando um caminho hoje
resolvido inteiramente pelo SQLite.

**Alternatives considered**:
- *Coluna `rank_score` materializada na ingestao*: rejeitada — exige
  migracao de schema + reindex (viola FR-007/SC-005) e congela a
  calibracao no momento da ingestao, impedindo que o desconto de recencia
  evolua com a passagem do tempo.
- *Ordenacao em shell (awk/sort) sobre o resultado bruto*: rejeitada —
  quebraria a interacao com `LIMIT` (seria preciso remover o `LIMIT` do SQL
  para reordenar corretamente), introduz aritmetica de ponto flutuante em
  `awk` no caminho critico e amplia a superficie de parsing do separador
  `|@|`.
- *Tabela auxiliar de pesos com JOIN*: rejeitada — persistencia nova para
  6 constantes; `CASE` inline e mais simples e nao adiciona estado.

## Decision 2: Constraint de escopo do `bm25()` (achado empirico)

**Decision**: a expressao de score DEVE ser construida no **mesmo nivel de
SELECT que contem o `MATCH`**. E proibido envolver a consulta FTS em
subquery/CTE e chamar `bm25()` no nivel externo.

**Rationale**: achado empirico desta pesquisa. A tentativa de agregar via
subquery externa falhou com erro literal do SQLite:

```
Error: in prepare, no such column: knowledge_fts
```

`bm25()` e uma funcao auxiliar FTS5 que so resolve o argumento
`knowledge_fts` no contexto da consulta que carrega o `MATCH` — fora dele,
`knowledge_fts` nao e um simbolo valido. As medicoes de M3 so foram
possiveis alias-ando `bm25()` dentro de uma CTE que contem o `MATCH`. O
desenho adotado (SELECT unico com `MATCH` no `WHERE` e a expressao no
`SELECT`/`ORDER BY`) e naturalmente compativel; esta decisao existe para
registrar a restricao e impedir que uma refatoracao futura "limpe" a query
movendo-a para subquery e quebre em runtime.

**Alternatives considered**: nenhuma viavel — e uma restricao do motor,
nao uma escolha.

## Decision 3: Forma da composicao e escala dos componentes

**Decision**: score aditivo por **subtracao de bonus** sobre o `bm25()`,
ordenado ASC:

```
score = bm25(knowledge_fts) - bonus_autoridade - bonus_recencia
ORDER BY score ASC
```

com `bonus_autoridade` e `bonus_recencia` sempre **>= 0**.

**Rationale**: `bm25()` e negativo e a ordenacao vigente e ASC (M3). Um
bonus positivo subtraido torna o score mais negativo, promovendo o
resultado — a direcao correta sem inverter sinais nem mexer na clausula
`ORDER BY ... ASC` ja existente. A forma aditiva e preferida a
multiplicativa porque a magnitude do efeito de autoridade fica **constante e
auditavel** (0.30 sempre significa 0.30 pontos de bm25), enquanto um fator
multiplicativo sobre um valor negativo teria efeito proporcional a
relevancia — um resultado ja muito relevante receberia um empurrao maior
que um marginal, exatamente o inverso da intencao de FR-001 ("quando a
relevancia textual for comparavel"). A forma aditiva tambem torna cada
componente diretamente exibivel na flag `--explain` (FR-005) sem
transformacao.

**Alternatives considered**:
- *Multiplicativo (`bm25 * peso_tipo`)*: rejeitado pelo efeito
  proporcional descrito acima; com bm25 negativo, `peso > 1` amplifica
  desproporcionalmente os ja-relevantes e distorce a semantica de
  "comparavel".
- *Normalizar bm25 para [0,1] e somar componentes ponderados*: rejeitado —
  normalizacao exige `min`/`max` do conjunto casado, o que reintroduz a
  subquery proibida por D2, e tornaria o score dependente da composicao do
  resultado (o mesmo achado mudaria de score conforme os vizinhos).
- *`ORDER BY` multi-clausula (`type_rank ASC, bm25 ASC`)*: rejeitado — faz
  autoridade dominar **incondicionalmente** a relevancia textual, violando
  FR-001, que so pede prioridade "quando a relevancia textual for
  comparavel". Um `skill` perfeitamente casado ficaria atras de qualquer
  `decision` marginalmente relacionada.

## Decision 4: Valores dos tiers de autoridade

**Decision**:

| Tier | Tipos | `bonus_autoridade` |
|------|-------|--------------------|
| Alta | `decision`, `block` | **0.30** |
| Intermediaria | `memory` | **0.15** |
| Default (nao enumerado) | `suggestion` + qualquer tipo futuro/desconhecido | **0.15** |
| Baixa | `retro`, `skill` | **0.00** |

**Rationale**: a calibracao deriva de M3, nao de arbitrio. O criterio e:
o spread total de autoridade (0.30 entre o tier alto e o baixo) precisa ser
**maior que o gap tipico entre vizinhos** (0.042-0.495, mediana ~0.13) para
de fato reordenar resultados de relevancia comparavel — satisfazendo
FR-001/SC-001 — e ao mesmo tempo **muito menor que a amplitude do top-20**
(0.805-3.958) para nunca promover um achado textualmente fraco por cima de
um forte. Com 0.30, a autoridade supera ~2 gaps medianos de vizinhanca e
representa entre 7.6% e 37% da amplitude tipica de uma lista — reordena
localmente, nunca globalmente. O passo intermediario de 0.15 (metade do
alto) mantem `memory` estritamente entre os dois extremos conforme exigido
por FR-010, com margem folgada (0.15) acima do gap mediano.

**Alternatives considered**:
- *Spread grande (ex.: 2.0)*: rejeitado — 2.0 e da ordem da amplitude
  inteira do top-20 de varias consultas medidas (`lock` 2.179, `sqlite`
  1.628, `hook` 0.805), o que na pratica degenera para o `ORDER BY
  type_rank` ja rejeitado em D3.
- *Spread pequeno (ex.: 0.02)*: rejeitado — fica abaixo do menor gap medio
  medido (0.0424 em `hook`) e praticamente nunca reordenaria nada,
  falhando SC-001.
- *Pesos configuraveis por env/flag*: rejeitado nesta feature — a spec nao
  pede configurabilidade, e expor pesos criaria superficie de contrato
  publico que precisaria ser mantida. Constantes nomeadas no proprio
  arquivo permanecem ajustaveis por quem edita o codigo.

## Decision 5: Tier de tipos nao enumerados pela spec (`suggestion` e futuros)

**Decision**: tipos fora da enumeracao de FR-001/FR-010 caem no tier
**default 0.15** (mesmo valor do intermediario), via o ramo `ELSE` do
`CASE`. Nenhum tipo desconhecido causa erro, exclusao ou ramo especial.

**Rationale**: `RECALL_TYPE_ENUM` (`cli/lib/recall.sh` linha 164) e
`"decision block retro skill memory suggestion"` — `suggestion` existe no
enum e tem **112 linhas reais** no indice (M1), mas a spec so classifica
`decision`/`block`, `memory` e `retro`/`skill`. Decidir por omissao seria
fabricar uma classificacao que a spec nao fez. O tier default intermediario
e a escolha conservadora: nao promove `suggestion` ao nivel de autoridade
de uma decisao ratificada (que a spec reservou a `decision`/`block`), nem a
rebaixa ao piso de `retro`/`skill` (uma sugestao registrada carrega mais
intencao deliberada que uma invocacao de skill). O ramo `ELSE` tambem
garante que um tipo introduzido por uma feature futura seja ranqueado com
um valor definido em vez de produzir `NULL` — que envenenaria a aritmetica
do score e jogaria a linha para o fim da ordenacao de forma silenciosa.

**Alternatives considered**:
- *Tratar `suggestion` como alta autoridade*: rejeitado — equipararia uma
  sugestao nao triada a uma decisao auditada; a spec deu autoridade alta
  explicitamente a `decision`/`block`.
- *Tratar `suggestion` como baixa*: rejeitado — com 112 linhas e conteudo
  deliberado (diagnostico + proposta), o piso zero a soterraria sob
  `skill`, que e a categoria mais mecanica do indice.
- *`ELSE NULL` / omitir o ramo*: rejeitado — `NULL` propaga por toda a
  aritmetica (`x - NULL = NULL`) e produziria ordenacao silenciosamente
  errada, o oposto da degradacao graciosa exigida.

## Decision 6: Funcao de desconto de recencia

**Decision**: decaimento **hiperbolico** com meia-vida `H = 90` dias e teto
`R_MAX = 0.10`:

```
bonus_recencia = coalesce(R_MAX * (H / (H + idade_dias)), 0.0)
idade_dias     = max(0.0, julianday(<instante_ref>) - julianday(nullif(source_ts,'')))
```

> **O `max(0.0, ...)` e OBRIGATORIO, nao cosmetico.** Sem ele, `idade_dias`
> negativa (achado com `source_ts` no futuro) faz o denominador encolher e o
> bonus **explodir**: medido com `sqlite3`, `idade = -80d` produz bonus
> `0.9` (9x o teto declarado) e `idade = -89.99d` produz `899.99999999954`.
> Um bonus dessa ordem domina a amplitude inteira de `bm25()` (0.805-3.958,
> M3) e todos os tiers de autoridade, fixando o achado em 1o lugar em
> qualquer consulta que o case. `source_ts` **nao e validado na ingestao**
> (vem de `jq -r` sobre o `state.json`, com `strip_nul` + `sql_escape`
> apenas), entao data futura entra por `state.json` envenenado OU por
> simples clock skew/timezone errada em qualquer maquina varrida por
> `--reindex`. No indice atual ha 0 linhas com `source_ts` futuro — nao esta
> explorado hoje, mas tambem nao havia defesa alguma. Com o clamp, o
> intervalo `[0, R_MAX]` passa a valer **por construcao**, para qualquer
> valor de `source_ts`, em vez de valer por suposicao de dominio.

Perfil resultante: idade 0 -> 0.100; 30d -> 0.075; 90d -> 0.050 (metade do
teto, por construcao); 365d -> 0.020; assintota em 0.

**Rationale**: tres propriedades exigidas simultaneamente —
(i) **monotonica decrescente** na idade, (ii) **limitada** em `(0, R_MAX]`,
(iii) computavel com **aritmetica basica apenas**. A forma exponencial
canonica (`R_MAX * exp(-ln2 * idade / H)`) exigiria `exp()`/`ln()`, que no
SQLite dependem do flag de compilacao `SQLITE_ENABLE_MATH_FUNCTIONS` — nao
garantido no piso de versao suportado pelo projeto (3.45.1) nem em builds
de distribuicao arbitrarios. A forma hiperbolica entrega a mesma semantica
de meia-vida (em `idade = H` o bonus e exatamente `R_MAX/2`) usando apenas
`+` e `/`, operadores do nucleo do SQLite. Verificado empiricamente contra
o DB real: a expressao completa executa e produz os valores esperados sem
nenhuma extensao carregada. `H = 90` dias e proporcional a faixa etaria
real do indice (M4: 0 a 100.9 dias) — a meia-vida cai perto do meio da
janela de dados existente, produzindo diferenciacao util em vez de saturar
em um dos extremos.

**Alternatives considered**:
- *Exponencial com `exp()`*: rejeitada pela dependencia de flag de
  compilacao (risco de `no such function: exp` em runtime = caminho de
  erro novo, proibido pela invariante de degradacao graciosa).
- *Linear com corte (`R_MAX * max(0, 1 - idade/365)`)*: rejeitada — nao e
  estritamente monotonica no dominio inteiro (satura em 0 apos o corte,
  tornando indistinguiveis todos os achados acima do limite) e introduz um
  parametro de corte arbitrario.
- *Degraus discretos (ex.: <30d, <90d, resto)*: rejeitada — cria saltos
  artificiais em que 1 dia de diferenca muda o bonus em um degrau inteiro,
  e produz muitos empates exatos, ampliando a dependencia do desempate.

## Decision 7: Garantia de nao-dominacao (recencia nunca inverte autoridade)

**Decision**: `R_MAX = 0.10` e escolhido estritamente **menor que o menor
passo de autoridade** (`0.15`, entre o tier baixo 0.00 e o
intermediario/default 0.15).

**Rationale**: isso torna a nao-dominacao uma propriedade **demonstravel**,
nao uma esperanca de calibracao. Com o clamp de D6, o bonus de recencia
habita `[0, 0.10]` — o extremo `0` e atingido de fato pelos achados sem
`source_ts` utilizavel (D9; caso real medido em M2, linha `block-001`). Logo
a diferenca maxima de recencia entre dois achados quaisquer e **exatamente
`0.10`**, atingivel. Como o menor degrau de autoridade e `0.15 > 0.10`, nenhum par de
achados com bm25 identico e tiers de autoridade diferentes pode ter sua
ordem invertida por recencia. Isso satisfaz literalmente FR-003, que
condiciona o efeito da recencia a autoridade ser "comparavel", e da a
`--explain` (FR-005) uma leitura consistente: o componente de recencia
nunca explica sozinho uma inversao entre tiers.

**Alternatives considered**:
- *`R_MAX` igual ou maior que o passo de autoridade*: rejeitado —
  permitiria que um `skill` recente ultrapassasse uma `decision` de mesma
  relevancia, contrariando FR-001.
- *Normalizar recencia por consulta*: rejeitado — reintroduz dependencia
  do conjunto de resultados (proibida por D2/D3).

## Decision 8: Determinismo (FR-009)

**Decision**: tres mecanismos combinados:

1. **Instante de referencia resolvido uma unica vez por invocacao**, no
   shell, e interpolado como **literal** na SQL — `julianday('now')` NAO
   aparece na consulta.
2. **Desempate estavel e total** apos o score:
   `ORDER BY score ASC, source_ts DESC, type ASC, source_id ASC`.
3. **Override do relogio para teste** — mecanismo **PENDENTE DE
   RATIFICACAO HUMANA**, ver D13. Necessario para a suite fixar o instante
   de referencia e assertar ordem por recencia.

**Rationale**: `julianday('now')` re-avalia por linha e por execucao,
tornando o score irreprodutivel entre runs — incompativel com FR-009 e
intestavel. Resolver o instante uma vez no shell congela o relogio para
toda a consulta. O desempate por `source_ts DESC` reforca a intencao de
recencia no empate exato de score; `type` e `source_id` fecham a ordem
total, pois `(project, feature, wave, source_id)` e a chave natural do
indice — sem eles, dois achados com score identico ficariam a merce da
ordem de varredura do SQLite. O mecanismo de override do relogio para teste esta
isolado em D13, porque a forma mais obvia (variavel de ambiente) carrega
risco de seguranca proprio que nao pode ser decidido por inercia.

Verificado empiricamente: com instante de referencia fixo, duas execucoes
consecutivas da mesma consulta retornaram a mesma sequencia de
`source_id` (`dec-021, block-004, dec-052, dec-018, dec-022, dec-056,
dec-072, dec-012, dec-090, dec-041`).

**Alternatives considered**:
- *Manter `julianday('now')` inline*: rejeitado — viola FR-009 e impede
  asserção de ordem em teste.
- *Truncar a idade para dias inteiros para "estabilizar"*: rejeitado —
  reduz a variabilidade mas nao a elimina (a virada do dia ainda muda o
  resultado) e ainda deixa o teste dependente da data de execucao.
- *Desempate so por `source_id`*: rejeitado — nao expressa a intencao de
  recencia no empate e ordena `dec-100` antes de `dec-99` lexicograficamente
  sem relacao com o dominio.

## Decision 9: `source_ts` ausente (FR-008)

**Decision**: `nullif(source_ts,'')` transforma a string vazia em `NULL`;
`julianday(NULL)` produz `NULL`; o `coalesce(..., 0.0)` externo converte o
resultado em **bonus de recencia 0.0** — o sinal mais baixo possivel. A
linha continua sendo retornada e ranqueada normalmente pelos outros dois
componentes.

**Rationale**: M2 confirma que o caso existe hoje no indice de producao
(1 linha `type='block'` com `source_ts=''`). Sem o `nullif`,
`julianday('')` retorna `NULL` de qualquer forma, mas sem o `coalesce` o
`NULL` propagaria pela subtracao e o **score inteiro** viraria `NULL` —
jogando a linha para o inicio ou o fim da ordenacao de modo dependente de
implementacao, e nao "com o sinal de recencia mais baixo", como FR-008
exige. Verificado empiricamente: a linha real de `source_ts=''` produz
`rec = 0.0` e permanece no resultado.

**Alternatives considered**:
- *Filtrar linhas sem `source_ts`*: rejeitado — FR-008 proibe
  explicitamente exclusao.
- *Atribuir a data da ingestao como proxy*: rejeitado — `ingested_at` nao e
  coluna de `knowledge_fts` (DDL linha 700-708), e usar um substituto
  inventado para uma data desconhecida seria fabricar dado factual
  (Constitution VI).

## Decision 10: Superficie e formato da flag `--explain`

**Decision**: `--explain` e uma flag **booleana, aditiva, exclusiva do modo
busca**. Sem ela, o stdout do modo busca e byte-identico ao atual. Com ela,
cada resultado ganha **uma linha adicional** apos o corpo, expondo os tres
componentes. O modo `--context` **nao** aceita a flag.

**Rationale**: FR-006 exige identidade de formato no caminho default, o que
manda a explicacao ser puramente aditiva — nenhuma alteracao nas linhas de
cabecalho (`printf '[%s] %s / %s / %s / %s (%s)\n'`) nem do corpo. FR-004 +
o contrato de `--context` (rotulo UNTRUSTED, teto `--max-bytes`, frase
`Aprendizado recuperado (read-back loop)`) tornam o `--context` um formato
consumido por maquina: injetar componentes de score la gastaria orcamento
de bytes com dado irrelevante ao consumidor e quebraria SC-002. A spec
tambem ja resolveu isso no Edge Case correspondente ("a explicacao e uma
capacidade de busca interativa"). Uma linha unica por resultado (em vez de
bloco multi-linha) mantem a saida legivel com `--limit 20` e preserva o
padrao de 1 bloco por achado que `scenario_04_limite_e_bm25`
(`tests/cstk/test_recall.sh` linha 143) conta via `grep -c '^\['`.

**Alternatives considered**:
- *`--explain` tambem em `--context`*: rejeitado por FR-004/SC-002.
- *Formato JSON para a explicacao*: rejeitado — introduziria dependencia de
  `jq` ou montagem manual de JSON num modo que hoje e texto puro; a spec
  pede que os componentes sejam "exibidos visivelmente" (SC-004), nao
  consumidos por maquina.
- *`--explain` alterando as linhas existentes (ex.: score no cabecalho)*:
  rejeitado — quebraria FR-006 para quem usa a flag e complicaria a
  asercao de identidade byte-a-byte.

## Decision 11: Ausencia de migracao, reindex e exposicao externa

**Decision**: nenhuma mudanca em `RECALL_SCHEMA_VERSION` (permanece **15**),
nenhuma alteracao de DDL, nenhum reindex exigido, nenhuma tool MCP,
nenhum RRF, nenhum ranking por grafo.

**Rationale**: consequencia direta de D1 (score efemero na consulta) — nao
ha nada persistido a migrar, logo FR-007/SC-005 sao satisfeitos por
construcao e nao por um passo de migracao bem-sucedido. FR-011 e FR-012
sao restricoes negativas explicitas da spec; registram-se aqui para que o
gate de convergencia futura possa verificar que nada foi adicionado por
inercia. `mcp/state-server/src/` nao e tocado por esta feature.

**Alternatives considered**: nenhuma — sao restricoes da spec, nao escolhas
em aberto.

## Decision 12: Confinamento de dependencia (Constitution II)

**Decision**: a feature nao introduz nenhuma dependencia nova. `sqlite3`
permanece confinado a `cli/lib/recall.sh`, sob o carve-out 1.1.0 ja vigente
(dep opcional com fallback graceful). Nenhum script novo e criado.

**Rationale**: as tres condicoes cumulativas do carve-out 1.1.0 permanecem
satisfeitas sem mudanca: **(a)** o fallback graceful ja existe e nao e
tocado — `recall_have_sqlite3()` ausente produz aviso e `exit 0`; **(b)** o
codigo continua num unico arquivo (`cli/lib/recall.sh`); **(c)** a dep ja
esta declarada na documentacao da feature que a introduziu
(`cstk-knowledge-db`), e esta feature apenas altera duas clausulas
`ORDER BY` dentro dela. Como nenhum `.sh` novo e criado, a regra de ouro do
projeto (script novo exige `tests/<n>.sh` correspondente, gateada por
`./tests/run.sh --check-coverage`) nao e acionada — a cobertura nova entra
como cenarios em `tests/cstk/test_recall.sh`, que ja existe.

**Alternatives considered**:
- *Extrair a logica de score para um helper novo*: rejeitado — espalharia
  referencia a `sqlite3` para um segundo arquivo, quebrando a condicao (b)
  do carve-out, e acionaria a exigencia de um arquivo de teste novo sem
  ganho algum (a logica e uma unica expressao SQL usada em dois pontos do
  mesmo arquivo).

## Decision 13: Mecanismo de override do relogio para teste — ABERTO, requer ratificacao humana

**Decision**: **PENDENTE**. O gate `owasp-security` sobre este plano
levantou 2 findings HIGH cuja raiz comum e o mecanismo de override do
relogio proposto em D8 (variavel de ambiente interpolada na SQL). A escolha
tem trade-off de seguranca real e **nao e decidida por esta skill** — vai a
bloqueio humano.

### Contexto de risco (medido, nao suposto)

O caminho de leitura `recall_query_sql()` (`cli/lib/recall.sh` L916) invoca
`sqlite3 -cmd '.timeout 5000' -- "$DB"` — **sem `mode=ro`**. O helper
read-only existe (`recall_query_sql_ro`, L964) mas hoje so e usado na
ingestao SQL->SQL. Portanto uma injecao nesse ponto **nao e apenas leitura**:
o CLI do `sqlite3` aceita multiplos statements, e `');` fecha o statement
corrente e executa o resto — habilitando `UPDATE`/`DROP` no indice e
`ATTACH` para escrita de arquivo arbitrario com os privilegios do usuario.
Alem disso, `value_has_nul` hoje cobre **apenas argv** (L3011-3017 no modo
busca, L3147-3153 no `--context`) — nenhum valor vindo de ambiente passa por
ele.

Agravante de contexto: o `bash-guard.sh` do toolkit e **denylist por
categoria sobre o texto do comando**, nao allowlist de programas. Um
`VAR=<payload> cstk recall --context ...` nao cai em nenhuma categoria
negada — logo a variavel viraria um caminho de escrita **atraves de um
comando permitido**, o que e bypass de guarda, e nao meramente "quem
controla o ambiente ja controla tudo".

### Opcao A — variavel de ambiente, com hardening completo

Mantem D8 como proposto, condicionado a **todas** as defesas abaixo:

- Nome explicito com prefixo `CSTK_` (greppavel), ex.: `CSTK_RECALL_REF_INSTANT`.
- Validacao por **allowlist ancorada na string inteira** via `case` com
  classes de digito literais
  (`[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z`).
  Nunca `grep`/substring/glob frouxo — `*T*Z*` deixaria payload passar.
- `sql_escape` **cumulativo e obrigatorio** mesmo apos a validacao (defesa em
  profundidade, mesma politica ja aplicada a todo valor interpolado).
- `value_has_nul` sobre o valor **antes** de qualquer uso.
- **Uma linha em stderr** quando o override e efetivamente honrado (sinal
  auditavel; silencio apenas quando a variavel esta ausente).
- Cenario adversarial obrigatorio no quickstart, com mutation test:
  desabilitar a validacao **deve** fazer o cenario falhar.

*Custo*: superficie de configuracao nova num binario de producao que
alimenta prompts de agentes autonomos.

### Opcao B — sem variavel: fixture com datas relativas ao relogio real

A suite gera os `source_ts` da fixture **relativos ao instante corrente**
(ex.: `now-5d`, `now-200d`) em vez de congelar o relogio. A ordem por
recencia passa a ser asserivel sem nenhum override, porque o que importa e
a **ordem relativa** das idades, nao o valor absoluto.

*Ganho*: elimina por completo a superficie de F1/F3/F4 — nao ha valor
externo interpolado na SQL, nao ha configuracao nova, nao ha invariante a
enfraquecer.
*Custo*: os cenarios de recencia passam a depender de aritmetica de data no
teste; um achado exatamente na fronteira de meia-vida teria margem menor.
O determinismo **por execucao** (FR-009) permanece garantido pelos outros
dois mecanismos de D8 (instante resolvido uma vez + desempate total), que
sao independentes desta escolha.

**Recomendacao tecnica desta analise**: **Opcao B**. Ela satisfaz a mesma
necessidade de teste sem adicionar superficie de ataque a um canal que
alimenta prompt de agente autonomo, e torna F1/F3/F4 inaplicaveis por
construcao em vez de mitigados por vigilancia. A Opcao A permanece viavel
**se e somente se** todas as defesas listadas forem implementadas.

**Alternatives considered**: flag de CLI oculta (`--ref-instant`) — mesma
superficie de injecao da Opcao A, porem exposta a qualquer chamador, sem o
beneficio de ser "invisivel"; congelar o relogio do sistema no teste —
rejeitada por exigir privilegio e afetar o host inteiro.
