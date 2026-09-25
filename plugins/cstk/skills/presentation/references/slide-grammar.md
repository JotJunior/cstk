# Gramatica do `story.md`

Contrato entre o redator (LLM) e `render-presentation.sh`. Tudo o que nao
estiver aqui e texto comum (vira paragrafo escapado). O validador
(`validate-presentation.sh`) aplica cada regra marcada com **[V]**.

## Frontmatter

```
---
title: Nome da apresentacao            # [V] obrigatorio
subtitle: Frase curta sob o titulo      # opcional
project: Nome do projeto                # opcional (default: inventario)
lang: pt-BR                             # [V] obrigatorio: pt-BR | en
generated: 2026-09-25                   # opcional, AAAA-MM-DD, vai para o rodape
---
```

Uma chave por linha, `chave: valor`, sem aspas nem listas. `lang` define
os rotulos gerados pelo render (estagios, "Capitulo", "nao registrado").

## Delimitador de slide

```
<!-- slide: <tipo> [key=<chave-da-spec>] -->
```

- **[V]** `<tipo>` pertence ao catalogo abaixo.
- **[V]** `key=` e obrigatorio em `spec`, existe no inventario e aparece
  uma unica vez; proibido nos demais tipos.
- Tudo entre dois delimitadores pertence ao slide anterior.

## Catalogo de tipos

| Tipo | Papel | Regras |
|------|-------|--------|
| `cover` | capa | **[V]** exatamente um, primeiro slide |
| `manifesto` | abertura inspiradora (o porque) | opcional |
| `briefing` | visao, problema, usuarios, escopo, restricoes | **[V]** ao menos um se o inventario tem `briefing`; `@source` obrigatorio |
| `constitution` | principios que governam o projeto | **[V]** ao menos um se o inventario tem `constitution`; `@source` obrigatorio |
| `chapter` | abertura de capitulo (onda ou periodo) | numerado automaticamente |
| `spec` | uma spec do inventario | **[V]** um por spec; **[V]** exatamente 4 secoes `###`; `@source` obrigatorio |
| `timeline` | evolucao no tempo | use `@timeline` |
| `numbers` | o projeto em numeros | so `@metric`; nenhum numero literal |
| `closing` | visao de futuro e chamada final | **[V]** ao menos um |
| `sources` | apendice de fontes | **[V]** exatamente um, ultimo slide; use `@sources` |

## Markdown suportado

| Sintaxe | Uso |
|---------|-----|
| `# Texto` | titulo principal (capa) |
| `## Texto` | titulo do slide |
| `### Texto` | secao/cartao dentro do slide |
| paragrafo | linhas consecutivas nao vazias |
| `- item` | lista (um nivel) |
| `> texto` | citacao de destaque |
| `**negrito**`, `*enfase*`, `` `codigo` `` | formatacao inline |

Nao suportado (vira texto literal, escapado): HTML cru, links, imagens,
tabelas, listas aninhadas, listas numeradas.

### Layout por tipo

- `cover`: `#` titulo, `##` subtitulo, paragrafos = lead, `>` = frase de impacto.
- `briefing` e `constitution`: cada `###` vira um cartao na grade. Em
  `constitution`, cartao cujo titulo contem `NON-NEGOTIABLE` ou
  `INEGOCIAVEL` ganha destaque.
- `spec`: paragrafos antes do primeiro `###` = lead; as 4 secoes `###`
  ocupam os quadrantes na ordem: **o que e**, **como foi pensada**,
  **como foi enriquecida**, **como foi implementada** (os rotulos sao
  livres e localizados; a ordem e fixa).

## Diretivas (linha propria, comecando em `@`)

| Diretiva | Onde | Efeito |
|----------|------|--------|
| `@metric Rotulo \| chave` | qualquer slide | chip (ou tile em `numbers`) com o valor resolvido do inventario. **[V]** chave valida para o escopo |
| `@source caminho` | qualquer slide | rodape de fontes. **[V]** o arquivo existe; **[V]** obrigatorio em `briefing`, `constitution`, `spec` |
| `@timeline` | `timeline` | cronologia gerada do inventario (arquivadas por data, depois ativas) |
| `@sources` | `sources` | indice de todas as fontes do inventario |

### Chaves de `@metric`

- Em slide `spec` (escopo da spec do `key=`): `tasks` (`feitas/total`),
  `tasks-done`, `tasks-total`, `clarify-sessions`, `clarify-questions`,
  `artifacts`, `converge`, `date`, `stage`, `status`.
- Nos demais slides (escopo do projeto): `specs`, `specs-active`,
  `specs-archived`, `specs-living`, `tasks`, `tasks-done`, `tasks-total`,
  `clarify-questions`, `principles`, `constitution-version`.

Valor ausente no inventario (`-`) aparece como "nao registrado". Nunca
escreva o numero voce mesmo: a chave existe justamente para isso.

## Proibicoes **[V]**

- Placeholders: `{{`, `TODO`, `TBD`, `[PREENCHER`, `NEEDS CLARIFICATION`,
  `lorem ipsum`.
- Diretiva desconhecida (linha iniciada por `@` fora da tabela acima).

## Exemplo minimo

```
---
title: Atlas
lang: pt-BR
---

<!-- slide: cover -->
# Atlas
## Da ideia ao produto, uma decisao por vez
> Cada linha de codigo nasceu de uma pergunta bem feita.

<!-- slide: spec key=_archived/2026-01-10-login -->
## Entrar sem atrito
O login deixou de ser uma barreira.
### O que e
Autenticacao por link magico.
### Como foi pensada
A pesquisa comparou senha, OTP e link.
### Como foi enriquecida
Tres perguntas de clarify fecharam o escopo.
### Como foi implementada
Backlog concluido e convergido.
@metric Tarefas | tasks
@metric Perguntas de clarify | clarify-questions
@source docs/specs/_archived/2026-01-10-login/spec.md

<!-- slide: sources -->
## Fontes
@sources
```
