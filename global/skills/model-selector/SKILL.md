---
name: model-selector
description: 'Heuristica auditavel que classifica uma tarefa em faixa de complexidade (rasa/media/profunda) e sugere modelo barato (haiku/sonnet) ou manter atual. Use quando o orquestrador (agente-00c, feature-00c) ou operador humano quiser uma sugestao deterministica baseada em catalogo de sinais ANTES de invocar uma skill ou subagente caro. NAO use quando: o input nao e textual (binario/imagem), a decisao precisa de contexto externo (precos, billing API, modelo corrente do harness), ou voce quer troca AUTOMATICA — esta skill apenas SUGERE, nunca troca modelo silenciosamente.'
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
sh global/skills/model-selector/scripts/classify.sh "rode o grep e conte ocorrencias"
```

A skill carrega o catalogo de sinais em
[`references/sinais.md`](references/sinais.md) (15 sinais MVP — 5 por
faixa). Operadores estendem editando esse arquivo (FR-004) — sem patch
necessario.

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
mutex, scheduler ou token persistente proprio.

## Referencias progressivas

| Topico | Arquivo |
|--------|---------|
| Contrato canonico de I/O (input, output, exit codes, invariantes) | [`../../../docs/specs/model-selector/contracts/skill-io.md`](../../../docs/specs/model-selector/contracts/skill-io.md) |
| Catalogo de sinais (15 MVP, extensivel) | [`references/sinais.md`](references/sinais.md) |
| Spec funcional + FRs + Success Criteria | [`../../../docs/specs/model-selector/spec.md`](../../../docs/specs/model-selector/spec.md) |
| Plan tecnico + Project Structure + Constitution Check | [`../../../docs/specs/model-selector/plan.md`](../../../docs/specs/model-selector/plan.md) |
| Decisoes de research (9 decisoes tecnicas-chave) | [`../../../docs/specs/model-selector/research.md`](../../../docs/specs/model-selector/research.md) |
| Cenarios E2E (quickstart) | [`../../../docs/specs/model-selector/quickstart.md`](../../../docs/specs/model-selector/quickstart.md) |
| Exemplos de input → output | [`examples/`](examples/) |

## Mapeamento de rotulo → versao concreta (fora do escopo da skill)

A skill emite rotulo ABSTRATO (`haiku` | `sonnet` | `opus` |
`manter-atual`) — nunca string como `claude-haiku-4-5`. Mapeamento
abstrato → versao concreta e responsabilidade do harness Claude Code
(dec-005). Versao concreta no output violaria Principio V (Adocao >
Profundidade) e exigiria update da skill a cada release Anthropic.
