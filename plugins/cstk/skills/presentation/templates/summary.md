---
title: {{NOME DO PROJETO}}
subtitle: {{PROMESSA EM UMA FRASE}}
project: {{NOME DO PROJETO}}
lang: pt-BR
generated: {{AAAA-MM-DD}}
vocabulary: {{mesmos termos do story.md, ou apague a linha}}
---

<!-- Esqueleto canonico da versao resumida (visao C-Level) da skill presentation. -->
<!-- No maximo 4 slides: cover primeiro, closing por ultimo. Gramatica: references/slide-grammar.md -->
<!-- Validar com: validate-presentation.sh --summary -->

<!-- slide: cover -->
# {{NOME DO PROJETO}}
## {{PROMESSA EM UMA FRASE}}
{{Uma frase com o valor do projeto para o negocio, a partir do briefing.}}
> {{Frase de impacto que resume a visao.}}

<!-- slide: briefing -->
## {{O problema que resolvemos}}
### O problema
{{A dor, em uma frase, nas palavras do briefing.}}
### Para quem
{{Quem ganha e o que ganha.}}
### A proposta
{{Como o projeto responde, pelo resultado.}}
@source {{docs/briefing.md}}

<!-- slide: highlights -->
## {{O que ja entregamos}}
{{Lead: a transformacao entregue ate aqui, em uma frase.}}
### {{Valor 1, em ate 5 palavras}}
{{O ganho para quem usa, agrupando as specs que o entregam.}}
### {{Valor 2, em ate 5 palavras}}
{{O ganho para quem usa, agrupando as specs que o entregam.}}
### {{Valor 3, em ate 5 palavras}}
{{O ganho para quem usa, agrupando as specs que o entregam.}}
@metric Entregas | specs
@metric Tarefas entregues | tasks
@metric Duvidas esclarecidas | clarify-questions
@source {{docs/specs/.../spec.md}}

<!-- slide: closing -->
## {{Para onde vamos}}
{{O horizonte e o que esta em construcao, a partir do briefing e das specs ativas.}}
> {{Frase final.}}
@metric Em construcao | specs-active
@source {{docs/briefing.md}}
