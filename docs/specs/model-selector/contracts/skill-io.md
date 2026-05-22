# Contract: Skill `model-selector` — I/O canonico

Contrato de entrada e saida da skill toolkit `model-selector`. Como a
feature e single-layer (skill toolkit), nao ha REST API nem endpoint
HTTP — o "contrato" e a forma como a skill recebe input via `args` do
Skill tool e o que devolve em stdout.

---

## Invocation surface

A skill e invocada via:

1. **Skill tool do Claude Code** (orquestradores agente-00c /
   feature-00c, ou operador humano via `/model-selector` se exposta
   como slash command futura).
2. **Direta no shell** (humano testando manualmente — equivalente a
   `sh global/skills/model-selector/scripts/classify.sh "<input>"`).

Ambos os caminhos compartilham o MESMO contrato — argumento textual
de entrada, output markdown estruturado em stdout, exit code POSIX.

---

## Input

| Campo | Tipo | Obrigatorio | Validacao |
|-------|------|-------------|-----------|
| input | string | sim | 0..4096 chars; sem null-byte; encoding UTF-8 |

**Forma de entrega**:
- Via Skill tool: passado como `args` do tool.
- Via shell direto: `sh scripts/classify.sh "<input>"` — UMA string
  como `$1` (operador escapa aspas conforme shell).

**Edge cases de entrada**:
- Input vazio (`""`) → sugestao `manter-atual`, score 0 (Decision 7
  do research).
- Input com somente whitespace → tratado como vazio.
- Input >4096 chars → truncado para 4096 com warning em stderr;
  classificacao prossegue sobre o truncado (fail-open conservador).
- Input com caracteres nao-imprimiveis (control chars) → strip via
  `tr -dc '[:print:][:space:]'` antes da tokenizacao.

---

## Output — sucesso (exit code 0)

**Formato**: markdown UTF-8 em stdout, 4 secoes fixas em ordem
deterministica.

```markdown
## Sugestao

**modelo**: haiku
**score**: 2
**alternativa**: sonnet

## Sinais detectados

- rode: rasa (peso=1)
- grep: rasa (peso=1)
- conte: rasa (peso=1)

## Justificativa

Verbos deterministicos (`rode`, `conte`) + ferramenta POSIX (`grep`)
indicam operacao mecanica de baixa complexidade. Faixa rasa vence
com 3 sinais contra 0 nas demais faixas.

## Acao sugerida (operador humano)

`/model haiku` (se operador quiser trocar; nao executado pela skill)
```

### Campos obrigatorios em ordem

1. **`## Sugestao`** com 3 sub-campos em ordem fixa:
   - `**modelo**:` enum `haiku|sonnet|opus|manter-atual`
   - `**score**:` inteiro 0..2 (teto pratico — dec-006)
   - `**alternativa**:` enum `haiku|sonnet|opus|none`
2. **`## Sinais detectados`** — lista bullet `- <termo>: <faixa> (peso=<N>)`
   ou linha unica `(nenhum sinal detectado)` quando vazio.
3. **`## Justificativa`** — texto livre 1..500 chars, MUST citar
   literalmente ao menos 1 termo de `Sinais detectados` (ou citar
   "input curto demais para classificacao confiavel" no caso
   degenerado).
4. **`## Acao sugerida (operador humano)`** — UMA linha literal
   `` `/model <modelo>` `` (backticks inclusos) + texto explanatorio.
   Quando `modelo == manter-atual`, linha vira `` `(nenhuma troca
   sugerida — manter modelo atual)` ``.

### Invariantes do output (testaveis)

- `awk '/^## /' <output>` retorna exatamente 4 linhas, na ordem
  exata: Sugestao, Sinais detectados, Justificativa, Acao sugerida.
- `grep -c '^\*\*modelo\*\*: ' <output>` retorna 1.
- `grep -E '^\*\*score\*\*: [0-2]$' <output>` retorna 1 (apenas
  inteiros 0, 1 ou 2 — teto pratico).
- Sem campo `versao`/`version`/`claude-haiku-4-5` em qualquer linha
  (rotulo abstrato — dec-005). Testavel via
  `! grep -E 'haiku-[0-9]|sonnet-[0-9]|opus-[0-9]' <output>`.

---

## Output — modo no-op (exit code 0)

Quando orquestrador chama a skill e detecta-se que `modelo sugerido
== modelo corrente` (edge case 2 da spec), a skill ainda emite output
NORMAL — quem decide marcar como no-op e o orquestrador (ao registrar
a `DecisaoDeAceite`). A skill nao tem acesso ao "modelo corrente" do
harness (Principio IV — nao consulta estado externo).

---

## Output — erro de uso (exit code 2)

Stderr recebe mensagem de uso; stdout vazio.

| Condicao | Mensagem stderr | Exit code |
|----------|-----------------|-----------|
| Argumento ausente | `model-selector: input obrigatorio (uso: classify.sh "<texto>")` | 2 |
| Mais de 1 argumento posicional | `model-selector: aceita exatamente 1 argumento (recebi N)` | 2 |
| Argumento contendo null-byte | `model-selector: input contem null-byte (rejeitado)` | 2 |

---

## Output — erro interno (exit code 1)

Reservado para falhas inesperadas (catalogo de sinais ausente,
formato invalido, etc). Stderr descreve o problema; stdout vazio.

| Condicao | Mensagem stderr | Exit code |
|----------|-----------------|-----------|
| `references/sinais.md` ausente | `model-selector: catalogo de sinais nao encontrado em <path>` | 1 |
| Catalogo com 0 entradas validas | `model-selector: catalogo vazio (esperado >=15 sinais MVP)` | 1 |
| Catalogo com faixa invalida | `model-selector: faixa invalida na linha N do catalogo: <faixa>` | 1 |

---

## Contract addendum: `scripts/report.sh` (FR-012)

Sub-comando read-only que **nao classifica nada** — apenas le
state.json(s) e emite relatorio agregado das sugestoes ja registradas.

### Input

| Campo | Tipo | Obrigatorio | Validacao |
|-------|------|-------------|-----------|
| state-dir | string (path) | nao (default = `.claude/feature-00c-state/`) | Diretorio existente; flag `--state-dir <path>` |
| feature-glob | string | nao (default = `*`) | Filtro de short-name; flag `--feature <glob>` |

### Output (exit code 0)

Tabela markdown em stdout:

```markdown
| feature | sugestoes | aceitas | rejeitadas | no-op | haiku | sonnet | opus | manter-atual |
|---------|-----------|---------|------------|-------|-------|--------|------|--------------|
| model-selector | 5 | 3 | 2 | 0 | 2 | 1 | 0 | 2 |
| outra-feature  | 3 | 3 | 0 | 0 | 1 | 1 | 0 | 1 |
| **total**      | 8 | 6 | 2 | 0 | 3 | 2 | 0 | 3 |
```

Quando nenhuma sugestao foi registrada em nenhuma execucao:
```
nenhuma sugestao registrada
```

### Performance (SC-003)

- `time scripts/report.sh --state-dir <fixture-com-20-execucoes>` <500ms
  total em maquinas dev tipicas (M1/M2/Linux comum).
- Caminho `jq` e caminho `awk` fallback produzem MESMO output —
  validado por `test_report_without_jq.sh`.

### Exit codes

- `0` — sucesso (incluindo "nenhuma sugestao registrada").
- `1` — erro interno (state-dir inacessivel, JSON corrompido).
- `2` — uso incorreto (flag desconhecida, argumento invalido).

---

## Compatibilidade reversa

- Adicionar novos campos OPCIONAIS ao output (ex: `**tier-economia**:
  N` no futuro) e MINOR — orquestradores existentes ignoram chaves
  desconhecidas.
- Adicionar nova faixa (4a — ex: `experimental`) e MAJOR — quebra
  invariante "3 faixas literais"; requer amendment da spec.
- Renomear/remover campo do output e MAJOR — quebra parsers
  orquestrador-side.
- Adicionar chave em `metricas_acumuladas.model_selector` e MINOR —
  schema do state.json e tolerante a campos novos.
