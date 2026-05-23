# Contract: Extensao do `state.json` — `metricas_acumuladas.model_selector`

Refs:
- Spec FR-011 (persistencia em `metricas_acumuladas.model_selector`)
- Spec FR-012 (relatorio agregado read-only — `scripts/report.sh`)
- data-model.md §Extensao do state.json
- research.md Decision 6 (contadores agregados no namespace
  `metricas_acumuladas`)
- Plan §Project Structure — observacao "NENHUMA mudanca exigida em
  `state-validate.sh`"
- Checklist CHK066 (tolerancia a corrupcao do state.json)
- Runtime: `agente-00c-runtime/scripts/state-validate.sh` v1.0.0,
  `state-rw.sh sha256-update/verify`, `state-decisions.sh register`

Este contrato descreve UMA fronteira: como a skill `model-selector`
(via orquestrador autonomo) ESTENDE o `state.json` gerenciado pelo
runtime `agente-00c-runtime`, sem modificar o schema canonico. E
complementar a `skill-io.md` (que cobre invocacao + stdout da skill);
o presente documento cobre a forma persistida apos a aceitacao da
sugestao pelo orquestrador.

---

## Escopo

- Quem ESCREVE: o orquestrador autonomo (agente-00c-orchestrator OU
  agente-00c-feature-orchestrator) ao registrar a `DecisaoDeAceite`
  (data-model.md §Entidade 3) — via runtime
  `state-decisions.sh register` para a decisao auditavel + via
  atualizacao incremental dos contadores em `metricas_acumuladas`.
- Quem LE: `scripts/report.sh` da propria skill (read-only, agregando
  state.json de >=1 execucoes — FR-012).
- Quem NAO toca: a skill `model-selector` em si NAO escreve no
  state.json (Principio IV — sem efeito colateral). A skill emite
  stdout markdown; o orquestrador parseia e aplica.

---

## Schema canonico do campo

Caminho JSON: `metricas_acumuladas.model_selector`.

Tipo: `object` (lazy — pode estar ausente em state.json gerados antes
da feature). Sub-campos abaixo:

| Sub-campo | Tipo | Default lazy | Descricao |
|-----------|------|--------------|-----------|
| `sugestoes_total` | `integer >= 0` | `0` | Numero total de sugestoes emitidas pela skill nesta execucao (contador monotonico nao-decrescente) |
| `por_modelo_sugerido` | `object` | objeto com 4 chaves zeradas | Distribuicao do `modelo` (1o campo do output) por faixa abstrata |
| `por_modelo_sugerido.haiku` | `integer >= 0` | `0` | Sugestoes com `modelo=haiku` |
| `por_modelo_sugerido.sonnet` | `integer >= 0` | `0` | Sugestoes com `modelo=sonnet` |
| `por_modelo_sugerido.opus` | `integer >= 0` | `0` | Sugestoes com `modelo=opus` |
| `por_modelo_sugerido.manter-atual` | `integer >= 0` | `0` | Sugestoes em que a skill recomendou `manter-atual` (input <3 tokens ou indeterminado) |
| `por_resultado` | `object` | objeto com 3 chaves zeradas | Distribuicao da `DecisaoDeAceite` do orquestrador |
| `por_resultado.aceitas` | `integer >= 0` | `0` | Orquestrador adotou o `modelo` sugerido |
| `por_resultado.rejeitadas` | `integer >= 0` | `0` | Orquestrador NAO adotou o `modelo` sugerido (escolheu outro ou manteve atual) |
| `por_resultado.no_op_ja_no_modelo` | `integer >= 0` | `0` | Modelo sugerido coincide com o modelo corrente do harness (edge case 2 da spec) |
| `ultima_invocacao_iso` | `string \| null` | `null` | ISO-8601 UTC da ultima sugestao registrada; `null` enquanto `sugestoes_total == 0` |

Rotulos `haiku/sonnet/opus/manter-atual` sao ABSTRATOS (Decision 5 do
research) — nunca incluir sufixo de versao (`haiku-4`, `sonnet-3.5`,
etc). Snake_case canonico do runtime, exceto `manter-atual` que e
literal kebab por compatibilidade com o enum do output da skill
(`skill-io.md` §Campos obrigatorios — `modelo: haiku|sonnet|opus|manter-atual`).

---

## Exemplo de estado — antes da 1a sugestao

Estado lazy (campo ausente, equivalente a defaults zerados):

```json
{
  "schema_version": "1.0.0",
  "execucao": { "...": "..." },
  "metricas_acumuladas": {
    "ondas_total": 14,
    "decisoes_total": 64,
    "tool_calls_total": 0,
    "tempo_wallclock_total_segundos": 20390
  }
}
```

## Exemplo de estado — apos 3 sugestoes registradas

```json
{
  "schema_version": "1.0.0",
  "execucao": { "...": "..." },
  "metricas_acumuladas": {
    "ondas_total": 17,
    "decisoes_total": 70,
    "tool_calls_total": 0,
    "tempo_wallclock_total_segundos": 22150,
    "model_selector": {
      "sugestoes_total": 3,
      "por_modelo_sugerido": {
        "haiku": 2,
        "sonnet": 1,
        "opus": 0,
        "manter-atual": 0
      },
      "por_resultado": {
        "aceitas": 2,
        "rejeitadas": 1,
        "no_op_ja_no_modelo": 0
      },
      "ultima_invocacao_iso": "2026-05-21T10:00:00Z"
    }
  }
}
```

---

## Invariantes do contador (testaveis)

1. `sugestoes_total == sum(por_modelo_sugerido.values()) ==
   sum(por_resultado.values())` — igualdade dupla. Violacao indica bug
   no orquestrador (incremento parcial). Verificavel via `jq`:

   ```sh
   jq -e '
     .metricas_acumuladas.model_selector as $m
     | $m == null
       or (
         $m.sugestoes_total
         == ([$m.por_modelo_sugerido[]] | add)
         and
         $m.sugestoes_total
         == ([$m.por_resultado[]] | add)
       )
   ' state.json
   ```

2. Todos os sub-campos numericos sao MONOTONICOS NAO-DECRESCENTES
   ao longo da vida do `state.json`. Nunca decrementar; nunca
   resetar (a unica forma valida de "zerar" e iniciar um novo
   `state.json` em nova execucao).

3. `ultima_invocacao_iso == null  <=>  sugestoes_total == 0`.

4. `por_resultado.no_op_ja_no_modelo` so incrementa quando o
   orquestrador detecta que o `modelo` sugerido pela skill coincide
   com o modelo corrente do harness (edge case 2 da spec); nesse
   caso, NAO incrementa `aceitas` nem `rejeitadas`.

5. Inicializacao LAZY — o objeto `model_selector` so e criado quando a
   primeira sugestao chega. Ate la, o caminho
   `metricas_acumuladas.model_selector` retorna `null` (em `jq`) ou
   eh ausente — ambos os casos sao validos e devem ser tratados pelo
   `report.sh` como "0 sugestoes registradas" (sem falha).

6. Rotulos do enum sao FIXOS: chaves de `por_modelo_sugerido` sao
   exatamente `{haiku, sonnet, opus, manter-atual}` (4 chaves);
   chaves de `por_resultado` sao exatamente
   `{aceitas, rejeitadas, no_op_ja_no_modelo}` (3 chaves). Chave
   adicional = bump MINOR de contrato (skill-io.md
   §Compatibilidade reversa).

---

## Validacao pelo runtime — `state-validate.sh`

Resultado empirico (subtask 3.1.2, onda-015):

```sh
# state.json mockado com metricas_acumuladas.model_selector populado
$ sh global/skills/agente-00c-runtime/scripts/state-validate.sh \
    --state-dir <tmpdir>
$ echo $?
0
```

`state-validate.sh` (v1.0.0, linhas 113-144) enumera campos
obrigatorios em **top-level** do state.json + sub-campos de
`.execucao`, `.orcamentos`, etc. Sub-chaves de `metricas_acumuladas`
NAO sao enumeradas explicitamente — o validador apenas verifica que
`.metricas_acumuladas` (e demais campos top-level) existem com o
tipo esperado. Isso significa que **adicionar chaves opcionais sob
`metricas_acumuladas.*` e compat retroativa por construcao** — sem
mudanca exigida no runtime (alinhado com plan.md §Project Structure
L160-163).

Consequencia operacional:
- State.json antigo (sem `model_selector`) — `state-validate.sh` PASS.
- State.json novo (com `model_selector` populado conforme schema acima)
  — `state-validate.sh` PASS.
- State.json novo com sub-campo invalido (ex: `sugestoes_total: -3`)
  — `state-validate.sh` PASS (validador nao introspeciona valores de
  `metricas_acumuladas`); a invariante MUST ser validada pelo
  produtor (orquestrador) e/ou pelo consumidor (`report.sh`)
  defensivamente.

---

## Tolerancia a corrupcao do `state.json` — comportamento de `report.sh` (CHK066)

`report.sh` e o UNICO consumidor desta extensao dentro da skill
(FR-012). Comportamento esperado em cada cenario degenerado:

| Cenario | Comportamento `report.sh` | Exit code | Stderr |
|---------|---------------------------|-----------|--------|
| `state.json` ausente em `--state-dir` | Ignora silenciosamente o diretorio | 0 (se outros ok) ou "nenhuma sugestao registrada" | `report.sh: aviso: state.json ausente em <path>` |
| `state.json` nao parseavel (JSON malformado) | Ignora aquele state.json e prossegue com os demais; ao final, se NENHUM state.json valido foi lido, emite "nenhuma sugestao registrada"; se houve corrupcao parcial entre N arquivos, emite o output + ruido em stderr. NAO trava o relatorio inteiro. | 1 (corrupcao detectada) | `report.sh: state.json corrompido em <path> (linha N: <fragmento>)` |
| Campo `metricas_acumuladas` ausente | Tratado como "0 sugestoes registradas" para a feature em questao | 0 | (sem) |
| Campo `metricas_acumuladas.model_selector` ausente | Tratado como "0 sugestoes registradas" (caso lazy default) | 0 | (sem) |
| Sub-campo numerico invalido (string em vez de int, valor negativo) | Coluna correspondente exibida como `?` na tabela; demais colunas preservadas | 1 (invariante violada) | `report.sh: invariante violada em <path>: <campo>=<valor>` |
| `ultima_invocacao_iso` em formato invalido | Coluna nao agregada (eh metadata, nao contador) | 0 | (sem) |

Alinhamento com `state-rw.sh sha256-verify` do runtime: quando o
operador roda o orquestrador (e nao o `report.sh` standalone), uma
adulteracao do `state.json` que invalide o hash sha256 ja e detectada
pelo runtime ANTES de a skill ser invocada — `report.sh` opera no
modo "best-effort read-only" assumindo que o caller (humano ou CI)
aceita resultados parciais quando algum state.json esta corrompido,
mas SINALIZA via exit code 1 e stderr para que o caller possa
escalar.

Mecanismo de "linha corrompida" no stderr (CHK066 criterio cravado):
- `report.sh` usa `jq -e .` para detectar parseabilidade. Se `jq`
  ausente, fallback usa `awk` linha-a-linha + heuristica de match
  de chaves esperadas — nesse caminho, "linha N: <fragmento>"
  corresponde a primeira linha onde a heuristica falhou (40 chars
  iniciais maximos, sem newline embedded).

---

## Handshake skill <-> orquestrador (resumo — detalhado em 3.2)

O fluxo "sugestao -> aceite -> contador" e:

1. Orquestrador invoca skill via tool Skill: `Skill(skill="model-selector", args="<texto-da-decisao>")`.
2. Skill emite stdout markdown (formato `skill-io.md`).
3. Orquestrador parseia: extrai `modelo`, `score`, `alternativa`.
4. Orquestrador compara `modelo` sugerido com modelo corrente do
   harness (informacao que vive fora do state.json — fornecida pelo
   ambiente do orquestrador).
5. Orquestrador registra `DecisaoDeAceite` via
   `state-decisions.sh register` (5 campos obrigatorios; score 2
   tipicamente — adocao de sugestao da skill nao requer evidencia
   empirica adicional alem do output da skill).
6. Orquestrador incrementa contadores em
   `metricas_acumuladas.model_selector` via patch jq (ou awk fallback
   se jq indisponivel — mesmo carve-out FR-010a do `report.sh`).
7. Orquestrador chama `state-rw.sh sha256-update` para reselar o
   state.json.

Detalhamento completo do handshake (incluindo `artefato_originador`
e politica de score) em **tarefa 3.2** — secao a ser criada em
`SKILL.md` "Integracao com orquestradores autonomos".

---

## Compatibilidade reversa do contrato

Politica alinhada com `skill-io.md` §Compatibilidade reversa, refinada
para esta fronteira:

| Mudanca | Tipo | Justificativa |
|---------|------|---------------|
| Adicionar nova chave OPCIONAL em `model_selector.*` (ex: `score_medio`) | MINOR | Schema do state.json e tolerante a campos novos; `report.sh` ignora chaves desconhecidas. |
| Renomear sub-campo (ex: `sugestoes_total` -> `total`) | MAJOR | Quebra `report.sh` existente. Requer amendment da spec. |
| Adicionar nova chave em `por_modelo_sugerido` (ex: faixa nova) | MAJOR | Quebra invariante "4 chaves fixas". Requer amendment. |
| Adicionar nova chave em `por_resultado` (ex: `parcial`) | MAJOR | Idem acima. |
| Mudar tipo de sub-campo (ex: `integer` -> `string`) | MAJOR | Quebra `report.sh`. |
| Marcar campo lazy ausente como "tolerado" em vez de "erro" | MINOR | Movimento conservador. |

---

## Glossario de invariantes (cross-ref)

- **Lazy init** — campo so criado na primeira escrita; ate la, ausente.
- **Monotonico nao-decrescente** — nunca decrementar; nunca resetar
  durante a vida do state.json.
- **Rotulo abstrato** — `haiku|sonnet|opus|manter-atual` sem versao
  (Decision 5 do research, FR-002a).
- **Compat retroativa por construcao** — validador do runtime ignora
  sub-chaves de `metricas_acumuladas`; novas chaves nao quebram
  state.json existentes.
- **Best-effort read-only (report.sh)** — degrada com elegancia;
  exit 1 sinaliza corrupcao parcial sem impedir geracao de relatorio
  para os state.json validos.
