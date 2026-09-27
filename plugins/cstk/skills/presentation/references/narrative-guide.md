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
  nunca o nome tecnico da spec. O render usa esse titulo tambem na linha
  do tempo, no rodape de fontes e no apendice.
- Lead: uma frase (ate 25 palavras) com a transformacao que a spec trouxe.
- Quatro secoes, na ordem, ate ~45 palavras cada:
  1. **O que e**: a capacidade, em linguagem de quem usa. O que muda na
     vida de quem usa, nao como o sistema faz.
  2. **Como foi pensada**: o problema e a escolha central (research,
     plan: alternativas consideradas e por que esta venceu), contados
     como decisao de produto, nao como arquitetura.
  3. **Como foi enriquecida**: o que as rodadas de perguntas e revisoes
     mudaram; duvidas que viraram decisao, lacunas que viraram garantia.
  4. **Como foi implementada**: o que foi entregue e o estado real
     (use o estagio do inventario: em andamento nunca vira "entregue"),
     descrito pelo resultado, nunca por arquivos, comandos ou tecnologias.
- Metricas: 2 ou 3 `@metric` por spec (`tasks`, `clarify-questions`,
  `converge` sao as mais expressivas), com rotulos em linguagem comum:
  "Tarefas entregues", "Duvidas esclarecidas", "Revisao final".
- Ate 3 `@tag` por slide quando uma tecnologia ajudar a ilustrar (ver
  "Linguagem de produto").
- `@source` para o `spec.md` (ou o arquivo da spec viva); acrescente
  outros arquivos citados (research, plan) quando o texto depender deles.

## Linguagem de produto (sem tecniques)

A audiencia nao e tecnica. O deck deve **encantar e vender o produto**:
o que ele resolve, para quem, com que cuidado. Arquitetura, frameworks,
linguagens de programacao, endpoints, comandos de terminal, nomes de
arquivo e caminhos nao sao relevantes para quem decide.

**Bloqueado pelo validador (G-11)** no texto narrativo: trecho entre
crases, URL, endpoint (`GET /...`), flag de linha de comando (`--algo`),
caminho de arquivo e nome de arquivo com extensao tecnica. Traduza para o
efeito que isso produz.

**Aviso do validador (G-12)**: termos do glossario
(`references/jargon.txt`: API, backend, SQLite, script, hook, commit...).
Resolva de um destes jeitos:

1. **Reescreva** em linguagem de produto (o caminho preferido).
2. **Traduza na mesma frase**, quando o nome for estritamente necessario
   para o contexto: nome + descricao curta em linguagem comum. Exemplo:
   "A aplicacao guarda os dados localmente com o SQLite, que e como um
   banco de dados de bolso: funciona sem internet e sem nenhum sistema
   pesado por tras."
3. **Mova para `@tag`**: selos discretos ("Por tras: SQLite"), no maximo
   3 por slide. E o unico lugar em que nomes tecnicos entram sem
   explicacao, como ilustracao.
4. **Declare como vocabulario do produto** em `vocabulary:` no
   frontmatter, quando o termo e a propria linguagem do produto (ex.:
   "skill" e "pipeline" num toolkit de desenvolvimento). Use com parcimonia.

| Em vez de | Escreva |
|-----------|---------|
| "migrou o estado para SQLite com transacoes" | "o historico de cada execucao passou a ficar num cofre local que nao se corrompe se algo falhar no meio" |
| "`converge-status.sh record` grava o marcador" | "cada entrega passa por uma conferencia final contra o que foi combinado" |
| "hook PreToolUse bloqueia comandos" | "uma guarda automatica impede acoes perigosas antes que acontecam" |
| "endpoint `POST /reservas` com payload JSON" | "a reserva e confirmada em um unico passo" |
| "suite POSIX com 113 testes" | "cada peca e verificada automaticamente antes de chegar a quem usa" (e o numero via `@metric`) |

Rotulos de metrica tambem sao texto de produto: "Duvidas esclarecidas",
nao "Perguntas de clarify".

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
- [ ] Zero erros de tecniques (G-11) e cada aviso de glossario (G-12)
      resolvido: reescrito, traduzido na frase, movido para `@tag` ou
      declarado em `vocabulary:`.
