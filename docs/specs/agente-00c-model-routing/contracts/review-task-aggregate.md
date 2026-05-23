---
title: Contrato — Agregado de selecao de modelo no relatorio review-task
feature: agente-00c-model-routing
refs:
  - spec.md#FR-018
  - spec.md#SC-003
  - spec.md#US-3
  - tasks.md#F5.2.1
  - tasks.md#F5.2.2
  - tasks.md#F5.2.3
  - clarify dec-006 (jq real-time sobre .decisoes[])
status: ratificado
versao: 1.0.0
data: 2026-05-23
---

# Contrato — Agregado `review-task` (model-routing)

Este contrato define **o que** o `review-task` (skill global em
`global/skills/review-task/SKILL.md`) MUST emitir quando agregar as
Decisoes de selecao de modelo persistidas pelo
`agente-00c-feature-orchestrator` em `state.json`. Cobre as duas
ambiguidades load-bearing do clarify (CHK032 + CHK047) e e o ponto de
verificacao do SC-003.

> **Escopo**: este documento e o contrato de saida visivel ao operador
> humano. O contrato de input (formato das Decisoes em `.decisoes[]`)
> esta em [`orchestrator-integration.md`](orchestrator-integration.md)
> §"Invariantes consumidas por `review-task`". O contrato do helper
> que produz o agregado esta em
> [`model-routing-helper.md`](model-routing-helper.md).

---

## 1. Path canonico do relatorio (CHK032)

| Campo | Valor |
|-------|-------|
| **Path canonico** | `docs/specs/<feature>/review-<onda-id>.md` |
| **Convencao de `<onda-id>`** | string opaca, exatamente como aparece em `.ondas[N].onda_id` no `state.json` — convencao atual do toolkit e `onda-NNN` (zero-padded a 3 digitos, ex: `onda-001`, `onda-018`) |
| **Diretorio pai** | `docs/specs/<feature>/` — MUST ja existir (criado por `specify`) |
| **Modo de escrita** | overwrite atomico (`mktemp` + `mv`); MUST NOT acumular `review-<onda-id>.md` duplicado para a mesma onda |
| **Encoding** | UTF-8 sem BOM, LF |

**Exemplo concreto** (este projeto, onda corrente): `docs/specs/agente-00c-model-routing/review-onda-018.md`.

**Rationale**: alinhado ao padrao ja praticado por `report.sh emit`
(`<state-dir>/<flavor>-report.md`) — review-task simplesmente nomeia
por onda em vez de "report" para permitir auditoria temporal de
multiplos snapshots durante o ciclo de vida da feature.

**Defesa em profundidade**: se `<feature>` ainda nao tem `docs/specs/`
(ex: review-task invocado em projeto sem SDD), review-task DEVE cair
no fallback `tasks.md`-only e NAO emitir secao de model-routing
(graceful skip — vide §4).

---

## 2. Trigger de inclusao da secao

A secao "Selecao de modelo por subagente (model-routing)" MUST aparecer
no relatorio quando, **e somente quando**:

1. O `state.json` da feature **existe** em
   `<projeto>/.claude/feature-00c-state/<feature>/state.json`, **E**
2. O helper `model-routing-report.sh aggregate --state-dir <DIR>`
   retorna exit 0 com `.total > 0` (ha >=1 Decisao matching o filtro
   `^Selecao de modelo para subagente `).

Quando `.total == 0` (helper retorna 0 mas sem selecoes), review-task
MUST **omitir** a secao por completo — nao emitir tabela vazia nem
rodape "(nenhuma selecao)". Isso evita ruido em features
pure-doc/specify-only que nunca spawnaram subagentes.

---

## 3. Formato exato da secao (CHK047)

A secao MUST ser emitida verbatim no formato abaixo, com cabecalho de
nivel 2 (`##`), tabela Markdown padrao GFM, e bloco "Sumario" com
contagens por rotulo. O conteudo da tabela e do sumario vem direto do
stdout de `model-routing-report.sh aggregate --state-dir <DIR>` (sem
`--json`) — review-task NAO reformata.

### 3.1 Cabecalho da secao

```markdown
## Selecao de modelo por subagente (model-routing)
```

Texto exato, case-sensitive, sem variacoes. E o que o teste de
integracao F5.2.4 valida via `grep -F`.

### 3.2 Tabela

Colunas (nessa ordem, nesse cabecalho exato):

```markdown
| subagent_type | etapa | onda | modelo | score | fallback |
|---------------|-------|------|--------|-------|----------|
```

Uma linha por Decisao matching o filtro, na ordem em que aparecem em
`.decisoes[]` (ordem cronologica de registro, garantida pelo append-only
do `state-decisions.sh register`).

| Coluna | Origem em `.decisoes[N]` | Formato |
|--------|--------------------------|---------|
| `subagent_type` | `sub(.contexto; "^Selecao de modelo para subagente "; "")` | string (ex: `agente-00c-clarify-asker`) |
| `etapa` | `.etapa` (fallback string vazia se ausente) | string |
| `onda` | `.onda_id` (fallback string vazia se ausente) | string opaca; convencao do toolkit e `onda-NNN` (zero-padded a 3 digitos) |
| `modelo` | `.escolha` | um de: `haiku`, `sonnet`, `opus`, `manter-atual`, `fallback-default` |
| `score` | `.score_justificativa` (fallback `0`) | inteiro 0..3 |
| `fallback` | `.escolha == "fallback-default"` | `yes` ou `no` |

**Defesa**: rotulos fora do enum (defesa de regressao do helper) sao
**ignorados** silenciosamente — nao aparecem na tabela nem no sumario.
Isso e auditado pelo helper (`scenario_aggregate_fixture_json_contagens_corretas`
verifica que a Decisao `dec-999-noise` com contexto fora do prefixo nao
entra no agregado).

### 3.3 Sumario

Imediatamente apos a tabela (linha em branco entre), bloco verbatim:

```markdown
**Sumario**:
- Total: <N>
- haiku: <n>
- sonnet: <n>
- opus: <n>
- manter-atual: <n>
- fallback-default: <n> (<pct>%)
```

Onde:

- `<N>` = total de Decisoes matching (inteiro, sempre >=1 — vide §2)
- `<n>` para cada rotulo = contagem; **todas as 5 chaves SEMPRE
  aparecem**, mesmo com `0` (garantido por `zero_counts` no jq do
  helper)
- `<pct>` = `fallback-default / Total * 100`, arredondado para 1 casa
  decimal (ex: `12.5%`, `0.0%`, `100.0%`)

### 3.4 Exemplo canonico completo

Para um state com 8 Decisoes (4 asker-haiku + 3 answerer-sonnet + 1
answerer-fallback) — exatamente a fixture
`tests/fixtures/state-with-selecao-decisoes.json`:

```markdown
## Selecao de modelo por subagente (model-routing)

| subagent_type | etapa | onda | modelo | score | fallback |
|---------------|-------|------|--------|-------|----------|
| agente-00c-clarify-asker | clarify | onda-001 | haiku | 3 | no |
| agente-00c-clarify-asker | clarify | onda-001 | haiku | 3 | no |
| agente-00c-clarify-asker | clarify | onda-001 | haiku | 2 | no |
| agente-00c-clarify-asker | clarify | onda-001 | haiku | 3 | no |
| agente-00c-clarify-answerer | clarify | onda-001 | sonnet | 3 | no |
| agente-00c-clarify-answerer | clarify | onda-002 | sonnet | 3 | no |
| agente-00c-clarify-answerer | clarify | onda-002 | sonnet | 2 | no |
| agente-00c-clarify-answerer | clarify | onda-002 | fallback-default | 2 | yes |

**Sumario**:
- Total: 8
- haiku: 4
- sonnet: 3
- opus: 0
- manter-atual: 0
- fallback-default: 1 (12.5%)
```

---

## 4. Posicionamento da secao dentro do relatorio

A secao MUST ser inserida **apos** "Progresso por Fase" e **antes** de
"Recomendacoes" no template do relatorio definido em
`global/skills/review-task/SKILL.md` §"Formato do Relatorio".

Justificativa: a secao e contexto auditavel de _como_ o pipeline rodou
(qual modelo cada subagente usou), nao input para priorizacao — logo
fica entre o resumo de progresso e a recomendacao de proximos passos.

**Skip auditavel**: se o helper retorna exit !=0 (state.json corrompido,
jq ausente, etc), review-task MUST registrar nota informativa em
"Recomendacoes" com texto literal:

```markdown
> Nota: secao "Selecao de modelo por subagente" omitida — helper
> `model-routing-report.sh aggregate` retornou exit <N>. Investigar
> manualmente via `jq '.decisoes[] | select(.contexto | test("Selecao
> de modelo"))' <state.json>`.
```

Isso garante que falhas do agregado nao silenciem regressoes.

---

## 5. Invariantes

| ID | Invariante | Auditavel via |
|----|------------|---------------|
| INV-RT-1 | Tabela e sumario byte-a-byte identicos ao stdout default do helper | `diff <(model-routing-report.sh aggregate --state-dir DIR) <secao-extraida-do-relatorio>` |
| INV-RT-2 | Path do relatorio segue padrao `docs/specs/<feature>/review-<onda-id>.md` (sem `..`, sem absolutos no template) | grep no relatorio gerado |
| INV-RT-3 | Secao omitida quando `.total == 0` (nao emite tabela vazia) | test F5.2.4 com fixture sem selecoes |
| INV-RT-4 | Secao presente quando `.total >= 1`, com cabecalho exato `## Selecao de modelo por subagente (model-routing)` | test F5.2.4 com fixture canonica |
| INV-RT-5 | Skip auditavel (nota em Recomendacoes) quando helper retorna exit !=0 | test futuro F6.x; nao bloqueia F5 |

---

## 6. Compatibilidade com `report.sh` (status F5.3)

### 6.1 Estado atual

`global/skills/agente-00c-runtime/scripts/report.sh` expoe apenas
`generate` e `validate` (sem flag `--flavor` nem `--include-model-routing`).
Inspecao do dispatch confirma:

```sh
case "$1" in
  generate)  _rp_cmd_generate "$@" ;;
  validate)  _rp_cmd_validate "$@" ;;
  ...
esac
```

### 6.2 Decisao F5.3 (5.3.1)

A integracao `report.sh emit --include-model-routing` foi
**adiada/nao-implementada** nesta onda. Justificativa:

1. O agregado ja e renderizado pelo review-task (caminho canonico — §3).
2. report.sh nao possui hoje secao "model-routing", e a renderizacao
   secundaria duplicaria o helper sem entregar valor novo (mesma fonte
   de dados, mesmo helper, mesmo contrato visual).
3. O ROI de estender report.sh hoje e baixo: o consumidor humano
   busca o agregado no review-N.md; o report.sh e mais usado para
   audit de onda + bloqueios + ondas.

### 6.3 Quando reativar F5.3

Se no futuro o `report.sh` ganhar `--flavor feature-00c` e
`--include-model-routing`, o contrato visual do agregado MUST ser
identico ao desta secao (mesmo cabecalho, mesmas colunas, mesmo
sumario), **reusando o helper `model-routing-report.sh aggregate`** —
sem duplicar logica jq. Isso evita drift entre os dois renders.

### 6.4 Fonte de verdade

Ate F5.3 ser implementado, este contrato e a unica fonte de verdade
do agregado, consumido exclusivamente via review-task (§4.5 do
`global/skills/review-task/SKILL.md`).

---

## 7. Versionamento

Mudancas neste contrato sao **breaking** para review-task e para o
helper `model-routing-report.sh`. Bump SemVer:

- **MAJOR**: mudar nome do cabecalho, colunas, ou semantica dos rotulos
- **MINOR**: adicionar coluna opcional ou linha de sumario adicional
  (com default zerado mantendo back-compat)
- **PATCH**: clarificacao textual sem mudar formato emitido

Versao atual: **1.0.0** (rifle inicial, F5.2.2).
