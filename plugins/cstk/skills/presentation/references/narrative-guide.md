# Guia Narrativo

Como escrever o `story.md`: executivo, inspirador e vendavel, sem nunca
deixar de ser verdadeiro. O leitor tipico e alguem que decide (diretoria,
cliente, investidor, time novo) e tem 10 minutos. Ele precisa sair
sabendo **de onde o projeto veio, no que acredita, o que ja entregou e
para onde vai**.

## O arco

```
cover → manifesto → briefing → constitution
      → [chapter → spec, spec, ...] x N
      → timeline → numbers → closing → sources
```

| Ato | Slides | Pergunta que responde |
|-----|--------|------------------------|
| Abertura | `cover`, `manifesto` | Por que isto importa? |
| Fundacao | `briefing`, `constitution` | Qual problema, para quem, com quais conviccoes? |
| Jornada | `chapter` + `spec` | O que foi construido, e como cada decisao nasceu? |
| Balanco | `timeline`, `numbers` | Quanto caminho ja foi percorrido? |
| Horizonte | `closing` | O que vem agora? |
| Lastro | `sources` | Onde conferir cada afirmacao? |

## Capitulos

- Siga a ordem do inventario: arquivadas em ordem cronologica (as sem
  data abrem como "origens"), depois ativas, depois vivas.
- Um capitulo por onda de arquivamento (mesma data) ou por tema quando
  varias datas contam uma mesma historia. Nome do capitulo = a ideia do
  periodo ("A fundacao", "Autonomia", "Confianca"), nunca "Onda 3".
- Ativas fecham a jornada num capitulo como "Em construcao". Vivas ficam
  num capitulo final como "Como o sistema se comporta hoje".
- Paragrafo do capitulo: uma ou duas frases que costuram o que une as
  specs dele.

## Slide de spec (o coracao do deck)

- `##` titulo = o beneficio, em ate 8 palavras ("Entrar sem atrito"),
  nunca o nome tecnico da spec. O nome tecnico ja aparece no rodape.
- Lead: uma frase (ate 25 palavras) com a transformacao que a spec trouxe.
- Quatro secoes, na ordem, ate ~45 palavras cada:
  1. **O que e**: a capacidade, em linguagem de quem usa.
  2. **Como foi pensada**: o problema e a escolha central (research,
     plan: alternativas consideradas e por que esta venceu).
  3. **Como foi enriquecida**: o que o clarify, o checklist e o converge
     mudaram; perguntas que fecharam ambiguidades, gaps que viraram
     requisito.
  4. **Como foi implementada**: o que foi entregue e o estado real
     (use o estagio do inventario: em andamento nunca vira "entregue").
- Metricas: 2 ou 3 `@metric` por spec (`tasks`, `clarify-questions`,
  `converge` sao as mais expressivas).
- `@source` para o `spec.md` (ou o arquivo da spec viva); acrescente
  outros arquivos citados (research, plan) quando o texto depender deles.

## Tom

- **Executivo**: comece pelo resultado, depois o como. Frases curtas.
  Voz ativa. Sujeito concreto ("o time", "o operador", "o sistema").
- **Inspirador**: mostre a intencao por tras de cada decisao; use o
  vocabulario do briefing (a visao, o porque) como fio condutor.
- **Vendavel**: destaque o valor para quem usa e o cuidado com que foi
  construido. O argumento de venda e o rigor: decisoes pensadas,
  questionadas e verificadas.
- **Humano**: o relatorio tambem sera lido rolando a pagina. Cada slide
  deve fazer sentido sozinho.

## Veracidade (Constitution Principio VI, inegociavel)

- Todo fato vem de um arquivo citado em `@source`. Na duvida, corte.
- **Nenhum numero literal no texto.** Quantidades, contagens, versoes e
  percentuais so via `@metric Rotulo | chave`. Datas podem aparecer
  quando estao no nome do diretorio arquivado ou no texto da fonte.
- Nada de superlativo sem lastro: "revolucionario", "o melhor",
  "inedito", "100% seguro" so se a fonte disser exatamente isso.
- Nao invente usuarios, clientes, resultados de negocio ou impacto
  financeiro. Se o briefing nao fala de receita, o deck tambem nao fala.
- Estagio vem do inventario: `in-progress` e "em andamento",
  `specified` e "especificada", `archived` sem tarefas e "arquivada".

## Estilo

- Escreva no idioma do `lang`, com acentuacao e gramatica corretas
  (em pt-BR: "decisão", "não", "construção").
- Sem emojis. Sem travessao (—): use virgula, dois-pontos ou ponto.
- `**negrito**` para a ideia-chave de um paragrafo, no maximo uma vez.
- `>` citacao: frases de efeito da capa, do manifesto e do fechamento, ou
  uma frase literal marcante do briefing (com `@source`).
- Listas so no `briefing` (escopo, restricoes) e quando enumerar de fato.

## Checklist antes de validar

- [ ] Toda spec do inventario tem exatamente um slide (`key=` certo).
- [ ] Cada slide de spec tem as quatro secoes `###` na ordem.
- [ ] Nenhum numero literal fora de `@metric`.
- [ ] Todo slide factual tem `@source` apontando para arquivo existente.
- [ ] Nenhum placeholder (`{{`, TODO, TBD) sobrou do esqueleto.
