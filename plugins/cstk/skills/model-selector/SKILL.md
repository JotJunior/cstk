---
name: model-selector
description: 'Heuristica deterministica que classifica uma tarefa por complexidade (rasa/media/profunda) e SUGERE modelo (haiku/sonnet/manter-atual). Use ANTES de invocar skill/subagente caro — os orquestradores a consomem via model-routing wave-select. Apenas sugere, nunca troca modelo. Skip: input nao-textual ou decisao que exige contexto externo (precos, billing, modelo corrente).'
argument-hint: "[input textual descrevendo a tarefa proxima a executar]"
allowed-tools:
  - Read
  - Bash
---

# Skill: Model Selector

Classifica uma tarefa proxima em faixa de complexidade (rasa | media |
profunda) com base em catalogo deterministico de sinais e sugere um
rotulo abstrato de modelo (`haiku` | `sonnet` | `opus` | `manter-atual`)
+ score 0..2 + alternativa de fallback. Decisao final permanece do
operador/orquestrador — a skill nunca troca modelo silenciosamente.

A skill e POSIX-pura (sem `jq`, sem bash-isms no caminho de
classificacao) e roda offline — zero coleta remota (Principio IV).

## Quando usar

Use quando o orquestrador (agente-00c, feature-00c) ou operador humano
quiser uma sugestao deterministica de qual modelo Claude rodar a
proxima tarefa, baseada em sinais textuais (verbos, ferramentas) no
input.

NAO use quando:

- O input nao e texto (binario, imagem, audio) — skill e text-only.
- A decisao precisa de contexto externo (precos correntes, modelo
  ativo no harness, billing API) — skill nao consulta estado externo.
- Voce quer troca AUTOMATICA de modelo — esta skill apenas SUGERE.
  Quem troca e o operador ou o orquestrador apos registrar Decisao.

## Contrato I/O (resumo)

| Lado | Forma |
|------|-------|
| Input | UMA string textual, 0..4096 chars, sem null-byte |
| Output sucesso | Markdown em stdout com 4 secoes fixas: `## Sugestao`, `## Sinais detectados`, `## Justificativa`, `## Acao sugerida` |
| Exit | `0` sucesso, `2` uso incorreto, `1` erro interno (catalogo ausente/invalido) |

Contrato completo (campos obrigatorios, invariantes testaveis, edge
cases): [`contracts/skill-io.md`](../../../docs/specs/model-selector/contracts/skill-io.md).

Exemplo minimo de output:

```markdown
## Sugestao

**modelo**: haiku
**score**: 2
**alternativa**: sonnet

## Sinais detectados

- rode: rasa (peso=1)
- grep: rasa (peso=1)

## Justificativa

Verbos deterministicos (`rode`) + ferramenta POSIX (`grep`) indicam
operacao mecanica. Faixa rasa vence com 2 sinais.

## Acao sugerida (operador humano)

`/model haiku` (se operador quiser trocar; nao executado pela skill)
```

## Invocacao

```sh
# Via Skill tool (orquestrador):
#   Skill(skill="model-selector", args="<texto descrevendo a tarefa>")

# Via shell direto (humano testando):
sh plugins/cstk/skills/model-selector/scripts/classify.sh "rode o grep e conte ocorrencias"
```

A skill carrega o catalogo de sinais em
[`references/sinais.md`](references/sinais.md) (15 sinais MVP — 5 por
faixa). Operadores estendem editando esse arquivo (FR-004) — sem patch
necessario.

## Integracao com orquestradores autonomos

Handshake skill ↔ orquestrador (`agente-00c`, `feature-00c`) — Refs:
FR-007/008/009, research Decision 3.

A skill emite stdout markdown (4 secoes — ver [`skill-io.md`](../../../docs/specs/model-selector/contracts/skill-io.md));
o orquestrador parseia `modelo`/`score`/`alternativa`/`Sinais` e
constroi uma `DecisaoDeAceite` via `state-decisions.sh register`. A
skill NAO escreve no state (Gotcha (e) + Principio IV).

**Regras de score do runtime** (validadas empiricamente — resolve CHK064):

- `--justificativa` SEMPRE obrigatoria, `>=20 chars` em QUALQUER
  score (`< 20` → exit 1, "violacao Principio I").
- **Score 2** (`decide_com_suporte_de_contexto`): so exige
  justificativa; NAO exige `--evidencia`. Apropriado para registrar
  aceite/rejeicao apoiado em briefing/constitution.
- **Score 3** (`decide_sem_clarificar`): EXIGE `--evidencia >=20 chars`
  contendo COMANDO + FRAGMENTO LITERAL do output. Sem evidencia →
  exit 1 ("score=3 EXIGE --evidencia"). Match de verbo no input da
  skill NAO satisfaz FR-EVI-001 (ver Gotcha (d)).
- **Score 0/1**: pause/clarificar — input ambiguo (Gotcha (c)) ou
  sugestao em conflito com briefing/constitution.

**Campo `artefato_originador`** (data-model.md §Entidade 3 — resolve
CHK065): orquestrador escolhe UMA forma, ambas aceitas:

- `sha256:<64-hex>` — hash do stdout literal (rastreio sem persistir).
- Path relativo ao projeto-alvo — ex:
  `docs/specs/<feature>/audit/sug-NNN.md` — quando o stdout e salvo
  como artefato auditavel.

Contadores agregados (`sugestoes_total`, `por_modelo_sugerido.*`,
`por_resultado.*`, `ultima_invocacao_iso`) em
`metricas_acumuladas.model_selector` — schema canonico em
[`state-extension.md`](../../../docs/specs/model-selector/contracts/state-extension.md)
(FR-011); skill nao toca.

## Gotchas

Cinco invariantes que parecem obvias mas viraram bugs em outras
skills do toolkit. Le-las economiza uma onda de fix-reveal-fix.

### (a) Sugestao nunca troca modelo silenciosamente

A skill emite uma SUGESTAO em stdout. Quem troca o modelo e o
operador humano (executando `/model <nome>`) ou o orquestrador (apos
registrar `DecisaoDeAceite` no `state.json`). Se voce esta lendo esta
skill esperando ela "mudar o modelo do harness automaticamente",
voce esta no lugar errado — Principio IV (Blast Radius Confinado).

### (b) Sinais contraditorios = vence o conservador

Se o input mistura sinais de faixas diferentes (ex: "rode" da faixa
rasa + "arquitete" da profunda), a skill aplica regra de
conservadorismo (FR-005): vence a faixa MAIS PROFUNDA detectada. A
justificativa cita literalmente o sinal vencedor.

### (c) Input ambiguo = manter modelo atual

Input com `<3 tokens` apos tokenizacao, ou zero sinais matched no
catalogo, resulta em sugestao `manter-atual` + score 0. Isto e
fail-safe deliberado (Decision 7 do research) — nunca chutar troca
sem base.

### (d) Score 3 exige evidencia empirica do runtime

A heuristica auto-invocada tem **teto pratico de score 2** (dec-006).
Score 3 nesta skill so existe no handshake operador/orquestrador ↔
runtime, quando a `DecisaoDeAceite` registrada via
`state-decisions.sh register --score 3` cita evidencia empirica
literal (FR-EVI-001 do runtime) — ex: media historica de aceite >2.5
em N execucoes lidas de `state.json`. Match de verbo no input NUNCA
satisfaz FR-EVI-001.

### (e) Skill nao spawna subagente — sem blast radius alem do projeto

`allowed-tools` desta skill exclui propositadamente `Task` e `Agent`
(FR-013e). A skill nao spawna subagente, nao chama outra skill, nao
faz I/O alem do diretorio do projeto-alvo (le `references/sinais.md`,
escreve stdout/stderr). Operacao stateless por invocacao — nada de
mutex, scheduler ou token persistente proprio. Quem spawna subagentes
e/ou escreve `state.json` e o ORQUESTRADOR (ver
[`contracts/state-extension.md`](../../../docs/specs/model-selector/contracts/state-extension.md)
§Escopo — "a skill `model-selector` em si NAO escreve no state.json"
+ secao "## Integracao com orquestradores autonomos" acima).

## Referencias progressivas

| Topico | Arquivo |
|--------|---------|
| Contrato canonico de I/O (input, output, exit codes, invariantes) | [`../../../docs/specs/model-selector/contracts/skill-io.md`](../../../docs/specs/model-selector/contracts/skill-io.md) |
| Contrato de extensao do `state.json` (`metricas_acumuladas.model_selector`) | [`../../../docs/specs/model-selector/contracts/state-extension.md`](../../../docs/specs/model-selector/contracts/state-extension.md) |
| Catalogo de sinais (15 MVP, extensivel) | [`references/sinais.md`](references/sinais.md) |
| Spec funcional + FRs + Success Criteria | [`../../../docs/specs/model-selector/spec.md`](../../../docs/specs/model-selector/spec.md) |
| Plan tecnico + Project Structure + Constitution Check | [`../../../docs/specs/model-selector/plan.md`](../../../docs/specs/model-selector/plan.md) |
| Decisoes de research (9 decisoes tecnicas-chave) | [`../../../docs/specs/model-selector/research.md`](../../../docs/specs/model-selector/research.md) |
| Cenarios E2E (quickstart) | [`../../../docs/specs/model-selector/quickstart.md`](../../../docs/specs/model-selector/quickstart.md) |
| Exemplo good-case — faixa rasa → `haiku` | [`examples/good-haiku.md`](examples/good-haiku.md) |
| Exemplo good-case — faixa media → `sonnet` | [`examples/good-sonnet.md`](examples/good-sonnet.md) |
| Exemplo good-case — faixa profunda → `opus` | [`examples/good-opus.md`](examples/good-opus.md) |

## Mapeamento de rotulo → versao concreta (fora do escopo da skill)

A skill emite rotulo ABSTRATO (`haiku` | `sonnet` | `opus` |
`manter-atual`) — nunca uma string versionada da forma
`claude-<familia>-<N>-<M>`. Mapeamento abstrato → versao concreta e
responsabilidade do harness Claude Code (dec-005). Versao concreta no
output violaria Principio V (Adocao > Profundidade) e exigiria update
da skill a cada release Anthropic.
