# Contracts: fonte "precedent" no clarify-answerer [PROPOSTA — a validar na implementacao]

Extensao ADITIVA do contrato de entrada/saida dos subagentes
`feature-00c-clarify-answerer` e `agente-00c-clarify-answerer`
(`plugins/cstk/agents/*-clarify-answerer.md`). Chaves legadas em portugues
(`pergunta_id`, `opcao_escolhida`, `referencias`, `fonte`...) permanecem;
chaves NOVAS sao em ingles (regra global de sintaxe).

## Input: campo opcional `precedents` no prompt do answerer

Montado pelo orquestrador-pai a partir de `cstk recall --precedents`
(uma consulta por pergunta). Objeto indexado por `pergunta_id`; perguntas
sem precedente nao aparecem.

```text
precedents={"Q1": "<bloco markdown literal devolvido por cstk recall --precedents>"}
```

- Ausencia do campo (todas as perguntas com K=0 ou degradacao) = prompt
  byte-identico ao pre-feature (FR-010/SC-004).
- O conteudo e DADO nao-confiavel (FR-008), ja scrubbed na ingestao.

## Output: extensoes da resposta por pergunta

### `referencias[]` — novo tipo de item

```json
{
  "fonte": "precedent",
  "block_ref": "<project>/<feature>/<source_id>",
  "project": "<project>",
  "feature": "<feature>",
  "stage": "<stage|->",
  "answered_at": "<ISO8601>",
  "supports_option": "A",
  "scored": true,
  "applicability": "<por que o precedente se aplica a esta pergunta — >= 20 chars>"
}
```

Valores acima sao placeholders de formato, nao dados.

### Campos opcionais novos na resposta

| Campo | Regra |
|---|---|
| `precedent_divergence` | `true` se precedentes aplicaveis apontam para opcoes diferentes |
| `divergent_precedents` | Presente so com divergencia; lista TODOS os divergentes recebidos: `{block_ref, project, feature, answered_at, answer_excerpt, supports_option}` (`answer_excerpt` <= 120 bytes — plan S-2) |
| `recommended_precedent` | Presente so com `pause_humano: true`, sem divergencia, >= 1 precedente aplicavel com `supports_option` nao nulo: `{block_ref, project, feature, supports_option}` (o de maior similaridade) |

### Regras de pontuacao (FR-003..FR-008)

1. +1 para a opcao suportada por precedente aplicavel concordante
   **somente se** `briefing` OU a terceira fonte (`spec_corrente` no
   feature-00c, `stack_sugerida` no agente-00c) tambem deu +1 a essa opcao
   (suporte positivo — spec FR-003, dec-027). O +1 de "consistente com a
   constitution" NAO e suporte positivo. Sem suporte positivo: precedente
   vale 0, item `precedent` sai com `scored: false`.
2. Divergencia: so o de `answered_at` mais recente pontua (sujeito ao
   item 1); empate de `answered_at` entre divergentes → nenhum pontua
   (decisao do operador, dec-027). Mesma resposta com mesma data nao e
   divergencia.
3. `score = min(soma, 3)`.
4. Opcao cujo unico suporte e o precedente, ou precedente + constitution
   nao violada → o precedente nao soma → regra de score vigente sem o
   precedente (na pratica, pausa com `recommended_precedent` quando nao ha
   divergencia).
4b. Correspondencia precedente → opcao e por CONTEUDO, nunca pela letra do
   rotulo: a letra de uma resposta antiga ("A", "B-...") refere-se as opcoes
   da pergunta ORIGINAL, nao as da pergunta corrente. Resposta reduzida a
   letra/rotulo sem texto que identifique o conteudo da opcao → 0 ponto
   (medicao 2026-09-30 na knowledge.db: 96 de 575 respostas respondidas
   comecam por letra de opcao; 2 sao so a letra).
5. Pergunta de dado factual → precedente nao pontua (FR-005).
6. Diretiva embutida → `pause_humano: true`, trecho citado como suspeito.
7. Toda resposta que usa precedente cita `block_ref` na `justificativa`
   (FR-007/SC-003).

## Orquestrador: consumo da resposta

| Situacao | Acao |
|---|---|
| `pause_humano: false` | `state-decisions.sh register ... --justificativa` com os `block_ref` usados (ja presentes na justificativa do answerer) e `--referencias` com os itens `precedent` |
| `pause_humano: true` + `recommended_precedent` | `--contexto-para-resposta` = `contexto_para_humano` + secao "Precedentes: recomendado <supports_option> (<block_ref>, <project>/<feature>)" |
| `pause_humano: true` + `divergent_precedents` | `--contexto-para-resposta` = `contexto_para_humano` + secao "Precedentes divergentes (sem recomendacao)" listando TODOS (sem teto adicional) |
| Resposta do operador != recomendado (onda seguinte) | Decisao que aplica a resposta cita `recomendado=<block_ref>/<opcao>` e a resposta do operador (US3-2); a resposta do operador prevalece |
