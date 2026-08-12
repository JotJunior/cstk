# Contract: ingestao de rounds no `knowledge.db`

**Status**: mudanca `[PROPOSTA — a validar na implementacao]` sobre codigo
**existente**. O que esta marcado *(existente)* foi lido em `cli/lib/recall.sh`
em 2026-08-11; o resto e desenho.

**Path**: `cli/lib/recall.sh`
**Teste**: extensao de `tests/cstk/test_recall.sh` *(existente)*

Cobre FR-018 ("rounds preservados MUST NOT ser interpretados como execucoes
ativas por nenhum leitor de estado, e a reconstrucao do indice MUST contar cada
round exatamente uma vez"), SC-003 e a paridade de backend de FR-010.

## Confinamento de dependencia

`sqlite3` e `secrets-filter` seguem confinados a `cli/lib/recall.sh` — nenhuma
outra lib do `cstk` passa a depender deles. Regra pre-existente do projeto,
preservada por esta mudanca.

---

## Estado atual *(existente)*

### Enumeracao do `--reindex` (`cli/lib/recall.sh:3189-3193`)

```sh
_rx_states=$(find "$_rx_states_root" \
    -type f -name 'state.json' \
    \( -path '*/.claude/feature-00c-state/*/state.json' \
       -o -path '*/.claude/agente-00c-state/state.json' \) \
    2>/dev/null) || :
```

Dois fatos medidos, ambos load-bearing:

1. **Sem `-maxdepth`**, e em `find -path` o `*` **casa `/`**. Logo
   `<state-dir>/rounds/r01/state.json` ja seria varrido hoje.
2. **Nao existe nenhum `find` para `state.db`** em `recall_mode_reindex`
   (`:3131-3227`). Toda execucao com backend SQLite e, hoje, invisivel ao
   `--reindex`.

### Chave de idempotencia *(existente, `:1247`)*

```
ON CONFLICT(project, feature, wave, source_id)
```

| Tipo de linha | `wave` | `source_id` |
|---------------|--------|-------------|
| `executions` | `-` | `execution_id` (`feat-<short>-<ts>`) |
| decisoes / bloqueios / skills | `onda-NNN` | `dec-NNN`, etc. |

### Normalizacao de atividade *(existente, `:1194-1195`)*

```jq
(if ($status == "concluida" or $status == "concluido")
 then "concluido" else ((.current_stage // .etapa_corrente) // "") end)
```

Equivalente SQL em `:2156`. Nao ha filtro de status na ingestao.

---

## Problema

A linha de `executions` **nao** colide entre rounds: `execution_id` embute
timestamp, logo e distinto por round. Mas decisoes, bloqueios e skills colidem —
`r01` e a execucao viva comecam ambos em `onda-001`/`dec-001`, com o mesmo
`project` e o mesmo `feature`. Sem discriminador, a ingestao de um **sobrescreve**
o outro e o historico das duas rodadas e corrompido.

Ou seja: o defeito nao e o `find` alcancar `rounds/` — e a chave nao carregar a
proveniencia do round.

---

## Mudanca 1: namespace de proveniencia por round *(novo)*

Ingestao de um estado localizado sob `<state-dir>/rounds/<label>/` passa a
carregar `<label>` na proveniencia:

| Tipo de linha | `feature` | `wave` hoje | `wave` proposto |
|---------------|-----------|-------------|-----------------|
| `executions` | `<short_name>` *(inalterado)* | `-` | `<label>` |
| decisoes / bloqueios / skills | `<short_name>` *(inalterado)* | `onda-NNN` | `<label>/onda-NNN` |

`feature` **nao muda**: as duas rodadas sao a mesma feature, e e isso que faz
"execucoes contadas == numero de rounds" (SC-003) valer sem fatiar a feature em
N features distintas.

Deteccao do label: o componente de path imediatamente acima do arquivo de
estado, quando seu avo se chama `rounds`. Sem esse padrao, comportamento
**identico ao atual** — execucoes normais nao mudam em nada.

> Nota de derivacao *(existente, `:1099-1129`)*: `feature` vem de `.short_name`
> do proprio documento, com fallback por path. Para
> `<short>/rounds/r01/state.json` o avo e `rounds` (nao `feature-00c-state`),
> entao o fallback por path **nao** resolveria — mas `.short_name` esta presente
> nos estados reais e resolve corretamente. A deteccao do label nao depende do
> fallback.

## Mudanca 2: paridade de backend no `--reindex` *(novo)*

Acrescentar segunda varredura para `state.db`, roteando para
`recall_ingest_state_db` — a mesma funcao que o `--ingest` ja usa *(existente,
`:2773-2777`)*:

```sh
if [ -r "$_ing_state_dir/state.db" ]; then
  recall_ingest_state_db "$_ing_state_dir/state.db" "$_ing_state_dir" "$_ing_db"
else
  recall_ingest_state_json "$_ing_state_dir/state.json" "$_ing_db"
fi
```

**Ancoragem obrigatoria de path (achado do gate de seguranca).** A varredura
nova MUST replicar **exatamente** as mesmas ancoras `-path` da varredura de
`state.json`, trocando so o `-name`:

```sh
find "$_rx_states_root" \
    -type f -name 'state.db' \
    \( -path '*/.claude/feature-00c-state/*/state.db' \
       -o -path '*/.claude/agente-00c-state/state.db' \) \
    2>/dev/null
```

Motivo: `--states-root` tem **`$HOME` como default**. Um `-name 'state.db'` sem
ancora varreria a home inteira e ingeriria o `state.db` de **qualquer outra
aplicacao** no `knowledge.db` global — vazamento de dados de terceiros para um
indice compartilhado. A ancora confina a varredura ao layout 00c.

Teste obrigatorio: um `state.db` isca fora do layout ancorado (ex.:
`~/algum-app/state.db`) **nao** pode ser ingerido (T-46b).

**Precedencia**: coexistindo `state.db` e `state.json` no mesmo diretorio,
`state.db` vence — espelha a regra ja implementada no `--ingest` e evita
ingerir o mesmo round duas vezes.

**Validacao do label detectado por path**: o label extraido do path MUST casar
`^r[0-9]{2,}$` antes de compor `wave`. Os valores ja passam por `sql_escape()`
na ingestao (`recall.sh:1246`, `:1653`, `:1721`), logo nao ha injecao de SQL —
a validacao existe para impedir proveniencia malformada, nao por risco de SQLi.

Sem esta mudanca, SC-003 falha para rounds SQLite e SC-004 nao se sustenta (5
das 26 execucoes concluidas do repo usam `state.db`).

## Mudanca 3: nao introduzir poda *(decisao explicita)*

`rounds/` **nao** e podado do `--reindex`. Podar mataria SC-003, que exige
contar cada round exatamente uma vez. O requisito de FR-018 e que rounds nao
sejam tratados como **ativos** — nao que sejam invisiveis.

Isso ja e satisfeito pela normalizacao existente: round terminal com
`status == "concluida"` vira `current_stage = "concluido"`. Round `abortada`
preserva o proprio status (FR-020) e tambem nao e ativo.

---

## Leitores que NAO mudam *(verificado)*

Todos os demais leitores de state-dir usam **glob de shell**
(`for d in "$froot"/*/`), e glob de shell **nao casa `/`** — alcanca exatamente
um nivel. `rounds/<label>/` esta dois niveis abaixo e ja e invisivel para eles:

| Leitor | Mecanismo | Rounds visiveis? |
|--------|-----------|------------------|
| `pretooluse-bash-guard.sh` (`_pbg_scope_has_state`) | glob de shell | Nao |
| `posttooluse-tool-call-tick.sh` | glob de shell | Nao |
| `posttooluse-agent-usage.sh` | glob de shell | Nao |
| `posttooluse-loose-usage.sh` | glob de shell | Nao |
| `mcp-session.sh` | glob de shell | Nao |
| `guard-hooks-status.sh` | glob de shell | Nao |
| `cli/lib/recall.sh --reindex` | `find -path`, sem `-maxdepth` | **Sim** — unico afetado |

Consequencia pratica: a guarda fail-closed do `PreToolUse` **nao** passa a ver
um round como execucao ativa, e a metrica de `tool_calls` nao e desviada. Nenhum
desses arquivos precisa ser alterado por esta feature.

---

## Invariantes de teste (extensao de `tests/cstk/test_recall.sh`)

| ID | Invariante | Origem |
|----|------------|--------|
| T-40 | feature com `r01` + execucao viva ⇒ `--reindex` produz exatamente 2 linhas de `executions` para `(project, feature)` | SC-003 |
| T-41 | `dec-001` de `r01` e `dec-001` da execucao viva coexistem — nenhum sobrescreve o outro | FR-018 |
| T-42 | nenhum round preservado aparece com etapa ativa apos `--reindex` | FR-018 |
| T-43 | round `abortada` preserva `status=abortada` e nao e ativo | FR-020 |
| T-44 | round com `state.db` e ingerido (hoje: invisivel) | FR-010, Decision 6 |
| T-45 | rounds `json` e `sqlite` produzem o mesmo numero de linhas | FR-010, I-K3 |
| T-46 | `state.db` + `state.json` no mesmo dir ⇒ ingerido uma vez, `state.db` vence | Decision 6 |
| T-47 | `--reindex` 2x consecutivos ⇒ contagens identicas (idempotencia) | SC-003 |
| T-48 | state-dir sem `rounds/` ⇒ comportamento identico ao atual (nao-regressao) | — |
| T-49 | `--reindex` nao escreve em nenhum `state.json`/`state.db` (indice e derivado) | invariante do recall |
