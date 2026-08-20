# Quickstart: Ranking Composto no cstk recall

Cenarios de validacao end-to-end da feature `recall-ranking`. Cada cenario
mapeia para um Success Criterion da spec e vira cenario automatizado em
`tests/cstk/test_recall.sh`.

> **Como rodar a suite**: `LC_ALL=C ./tests/run.sh test_recall` (o locale
> importa — `pt_BR` produz FAIL falso). Suite completa: `LC_ALL=C
> ./tests/run.sh`.

> **GOTCHA de validacao manual**: `cli/lib/recall.sh` e **runtime do
> binario**, nao catalogo. Para exercitar a mudanca via `cstk recall` numa
> sessao real e obrigatorio `cstk self-update --from
> "file://$PWD/dist/cstk-X.Y.Z-dev.tar.gz"`. `cstk install`/`cstk update`
> **nao** atualizam `cli/lib/` e reportam "updated" sem tocar no arquivo —
> o codigo antigo continua rodando e o cenario passa/falha por engano.

> **Nota sobre o Scenario "Roundtrip End-to-End"** do template padrao:
> **N/A — single-layer**. Nao ha borda backend<->frontend nesta feature (CLI
> POSIX + SQLite local, sem DTO, sem serializacao cross-camada). O
> equivalente funcional — validar contra o dado REAL em vez de fixture — e
> o Scenario 8, que roda contra o indice de producao.

> **Convencao dos comandos abaixo**: `KDB` designa o caminho do indice de
> conhecimento (por padrao, o arquivo `knowledge.db` sob `~/.claude/cstk/`).
> Todas as consultas dos cenarios sao **somente leitura** — nenhum cenario
> deste documento muta o indice. Mutacao do indice se faz exclusivamente por
> `cstk recall --ingest` / `cstk recall --reindex`.

## Fixture comum (Scenarios 1-7)

Indice sintetico com clock fixo, para ordem asserivel:

1. Criar DB temporario via `--ingest` de um state sintetico (padrao ja
   usado por `_write_state` em `tests/cstk/test_recall.sh`).
2. Garantir no minimo: 1 `decision`, 1 `block`, 1 `skill`, 1 `retro`,
   1 `suggestion` e 1 `memory`, todos casando o **mesmo termo de busca** com
   corpos de comprimento comparavel (para manter `bm25()` proximo entre
   eles — o efeito de autoridade so e observavel sob relevancia comparavel).
   Helpers ja existentes em `tests/cstk/test_recall.sh`: `_write_state`
   (decisions/blocks/retros/skills), `_write_memory_dir` (linhas `memory`,
   junto de `_rc_home`, ~L2197) e `_write_suggestions_state` (linhas
   `suggestion`, ~L2793).
3. Fixar o instante de referencia — **mecanismo pendente de ratificacao
   humana**, ver `contracts/cstk-recall-ranking.md` §3 e research.md D13. Os
   cenarios 3, 4 e 6 dependem desta escolha:
   - **Opcao A** (env var, ex.: `CSTK_RECALL_REF_INSTANT`): fixar o instante
     absoluto.
   - **Opcao B** (recomendada): gerar os `source_ts` da fixture **relativos
     ao instante corrente** (`now-5d`, `now-200d`) e assertar apenas a
     **ordem relativa** — nenhum override necessario.

## Scenario 1: Autoridade promove decisao/bloqueio (SC-001, FR-001)

1. Popular a fixture comum.
2. Rodar `cstk recall <termo> --db <fixture> --limit 10`.
3. **Expected**: os achados `decision` e `block` aparecem **antes** dos
   `retro` e `skill` de relevancia textual comparavel. Nenhum resultado e
   omitido — apenas reordenado.

## Scenario 2: Tier intermediario de `memory` (FR-010)

1. Fixture com 3 achados de `bm25()` comparavel: um `decision`, um
   `memory`, um `skill`.
2. Rodar a busca com `--limit 10`.
3. **Expected**: ordem `decision` -> `memory` -> `skill`. O `memory` fica
   estritamente entre os dois — nem empatado com o topo, nem com o piso.

## Scenario 3: Recencia desempata dentro do mesmo tier (SC-003, FR-003)

1. Fixture com **dois achados do mesmo `type`** e corpos de relevancia
   comparavel, com `source_ts` separados por meses.
2. Fixar o instante de referencia.
3. Rodar a busca.
4. **Expected**: o achado mais recente vem primeiro.

## Scenario 4: Recencia NAO inverte autoridade (I-2 do contrato, FR-003)

1. Fixture com um `skill` **muito recente** e um `decision` **antigo**, com
   `bm25()` comparavel.
2. Rodar a busca.
3. **Expected**: o `decision` antigo ainda vem **antes** do `skill` recente.
   Justificativa verificavel: o spread maximo de recencia (`0.10`) e menor
   que o menor degrau de autoridade (`0.15`), logo a inversao e
   aritmeticamente impossivel — nao apenas improvavel.

## Scenario 5: `source_ts` ausente nao quebra nem exclui (FR-008)

1. Incluir na fixture um achado com `source_ts` **vazio** (`''`) — o caso
   existe no indice real (research.md M2: 1 linha `type='block'`).
2. Rodar a busca com um termo que case esse achado.
3. **Expected**: exit `0`; o achado **aparece** no resultado; com
   `--explain`, sua linha mostra `recencia=0.0000` e `idade=n/d`. Nenhum
   `NULL` vaza para a saida e o score permanece numerico.

## Scenario 6: Determinismo (SC-006 parcial, FR-009)

1. Com a fixture e o instante de referencia fixos, rodar **a mesma consulta
   duas vezes**, capturando stdout.
2. **Expected**: os dois stdout sao **byte-identicos**. Reforco: incluir na
   fixture dois achados de score exatamente igual, para exercitar o
   desempate `source_ts DESC, type ASC, source_id ASC`.

## Scenario 7: `--explain` (SC-004, FR-005) e identidade default (SC-002/SC-006, FR-006)

1. Rodar `cstk recall <termo> --db <fixture> --limit 5` (sem a flag) e
   salvar stdout como `A`.
2. Rodar o mesmo comando **na base de codigo anterior a feature** e salvar
   como `A0` — ou, equivalentemente, assertar que `A` casa o formato
   `^\[<type>\] .* / .* / .* / .* \(.*\)$` seguido do corpo indentado, sem
   nenhuma linha extra.
3. Rodar com `--explain` e salvar como `B`.
4. **Expected**:
   - `A` nao contem nenhuma linha `score=` (FR-006: formato default
     inalterado; so a ordem pode diferir de `A0`).
   - `B` contem **exatamente uma** linha `score=...` por resultado — 100%
     dos resultados explicados (SC-004).
   - Em `B`, para cada resultado, a identidade `score = bm25 - autoridade -
     recencia` fecha dentro da tolerancia de arredondamento (C-3).
   - `grep -c '^\['` retorna o **mesmo numero** de blocos em `A` e `B`
     (C-2 — a linha de explicacao nao cria bloco novo).

## Scenario 8: Reproducao da calibracao contra o indice REAL (aterramento)

Substitui o roundtrip do template: valida contra o dado de producao, nao
contra fixture. **Somente leitura** — nao muta nada.

1. Confirmar formato e o caso-limite de `source_ts` no indice real,
   consultando `KDB` com:
   `SELECT length(source_ts) L, count(*) FROM knowledge_fts GROUP BY L ORDER BY L;`

   **Expected**: uma linha `20|<N>` (ISO 8601) e uma linha `0|1` — o caso de
   FR-008 presente em producao.

2. Reproduzir a dispersao de `bm25()` que calibra os pesos (research.md M3),
   consultando `KDB` com:

   ```sql
   WITH t AS (SELECT bm25(knowledge_fts) b FROM knowledge_fts
              WHERE knowledge_fts MATCH '"lock"'
              ORDER BY bm25(knowledge_fts) LIMIT 20)
   SELECT round(max(b)-min(b),3) AS amplitude,
          (SELECT round(avg(d),4)
             FROM (SELECT b - lag(b) OVER (ORDER BY b) AS d FROM t)
            WHERE d IS NOT NULL) AS gap_medio
   FROM t;
   ```

   **Expected**: `gap_medio` uma ordem de grandeza **menor** que
   `amplitude`. Enquanto essa relacao valer, a calibracao de D4
   (autoridade `0.30` > gap tipico, << amplitude) segue justificada. Se um
   dia deixar de valer, os pesos precisam ser **remedidos**, nao chutados.

3. **Expected final**: a consulta com a expressao de score completa executa
   sem erro contra o indice real e retorna resultados ordenados —
   confirmando que nenhuma extensao matematica (`exp`/`ln`) e necessaria
   (research.md D6).

## Scenario 9 (error case): flag invalida e modos sem `--explain`

1. `cstk recall <termo> --explaain --db <fixture>` (typo).
2. **Expected**: exit `2`, mensagem de flag invalida em **stderr**, stdout
   sem resultados.
3. `cstk recall --context <termos> --explain --db <fixture>`.
4. **Expected**: exit `2` (flag invalida no modo `--context`, §2.2 do
   contrato). O modo `--context` nunca aceita a flag.
5. `cstk recall <termo> --explain --limit abc --db <fixture>`.
6. **Expected**: exit `2` por `--limit` nao-inteiro — a validacao existente
   continua precedendo qualquer efeito da flag nova.

## Scenario 10 (degradacao graciosa): I-7 preservada

1. Rodar a busca com `--db /caminho/inexistente.db`.
2. **Expected**: exit `0`, aviso em stderr sugerindo `cstk recall
   --reindex`, stdout sem resultados.
3. Rodar com um arquivo de DB corrompido (bytes aleatorios).
4. **Expected**: exit `0`, aviso de indice ilegivel/corrompido.
5. Simular `sqlite3` ausente do `PATH`.
6. **Expected**: exit `0` com aviso de memoria indisponivel.
7. **Expected final**: em nenhum desses caminhos a feature introduz exit
   != 0 — o ranking novo nao adiciona caminho de erro (I-7 do contrato).

## Scenario 11: `--context` preserva contrato, muda so a ordem (SC-002, FR-004)

1. Rodar `cstk recall --context "<termos>" --db <fixture> --limit 4
   --max-bytes 2000`.
2. **Expected**:
   - As 4 linhas do cabecalho UNTRUSTED presentes e integrais, incluindo a
     frase-contrato `Aprendizado recuperado (read-back loop)`.
   - Cada achado no formato `- **[<type>]** <proj>/<feat>/<wave> (<ts>): <body>`.
   - Nenhuma mencao a `score`, `bm25`, `autoridade` ou `recencia` no bloco.
   - Tamanho total <= `--max-bytes`.
   - Achados de `decision`/`block` aparecem antes de `retro`/`skill` de
     relevancia comparavel (o unico efeito observavel da feature aqui).
3. Rodar com `--max-bytes` pequeno o bastante para nao caber nem o primeiro
   achado.
4. **Expected**: stdout **vazio**, exit `0` — sem cabecalho orfao.

## Scenario 12: `source_ts` no FUTURO nao pode dominar o ranking (gate security F2)

Cenario de regressao do clamp `max(0.0, ...)` (contrato I-1, research.md D6).

1. Fixture com dois achados de `bm25()` comparavel: um `decision` com
   `source_ts` normal (passado) e um `skill` com `source_ts` **no futuro**
   (ex.: `<ref> + 80 dias`).
2. Rodar a busca.
3. **Expected**: o `skill` futuro **nao** ultrapassa o `decision`. Com
   `--explain`, seu `recencia=` fica dentro de `[0.0000, 0.1000]` — nunca
   acima do teto.
4. **Mutation test**: removendo o `max(0.0, ...)` da expressao, este cenario
   MUST falhar (sem o clamp, o bonus medido para `-80d` e `0.9`, 9x o teto,
   e para `-89.99d` e `~900`). Se o cenario passar sem o clamp, ele nao esta
   testando o que diz testar.

## Scenario 13: `body` contendo o separador `|@|` nao falsifica a explicacao (gate security F5)

1. Fixture com um achado cujo `body` contenha a sequencia literal `|@|`.
2. Rodar a busca com `--explain`.
3. **Expected**: a linha `score=` exibe **numeros**, nao fragmento do corpo.
   A identidade `score = bm25 - autoridade - recencia` continua fechando.
4. **Expected (regressao)**: sem `--explain`, o comportamento e identico ao
   atual — este `body` ja causa truncagem visual hoje, e isso nao muda.

## Scenario 14: falha de consulta AVISA em vez de silenciar (gate security F7, contrato I-10)

1. Forcar a consulta a falhar (ex.: `--db` apontando para um arquivo SQLite
   valido cuja tabela `knowledge_fts` foi removida, ou injetar erro de
   compilacao na expressao durante o teste).
2. Rodar o modo busca e o modo `--context`.
3. **Expected**: exit `0` nos dois (I-7 preservada), stdout inalterado
   (busca: "nenhum resultado"; `--context`: vazio), **e** uma linha de aviso
   em **stderr** distinguindo "consulta falhou" de "nenhum resultado".
4. **Por que importa**: sem esse sinal, uma expressao de score que deixe de
   compilar faz o read-back loop dos orquestradores desaparecer em silencio,
   e a pipeline segue decidindo sem memoria acreditando que nao havia
   aprendizado a recuperar.

## Scenario 15 (adversarial): override de relogio invalido degrada, nunca executa

**Aplicavel somente se a Opcao A de §3 for ratificada.** Se a Opcao B for
escolhida, este cenario e dispensado (a superficie deixa de existir).

1. Definir a variavel de relogio com payload de injecao, ex.:
   `2026-01-01T00:00:00Z'); ATTACH DATABASE '/tmp/evil.db' AS e; --`
2. Rodar o modo busca e o modo `--context`.
3. **Expected**: a consulta usa o **relogio real**, exit `0`, nenhum arquivo
   criado, nenhum statement extra executado, e um aviso em stderr indicando
   valor invalido descartado.
4. Repetir com: valor contendo byte NUL; valor `*T*Z*`-like que passaria por
   glob frouxo mas nao pela allowlist ancorada; string vazia.
5. **Mutation test**: desabilitar a validacao MUST fazer este cenario falhar.
   Um cenario adversarial que passa com a defesa desligada nao esta testando
   a defesa.
