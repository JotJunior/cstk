# Contract: Gramatica do `story.md`

**Fonte canonica**: `plugins/cstk/skills/presentation/references/slide-grammar.md`
(distribuida com a skill, lida pelo redator em tempo de execucao). Este
contrato fixa os pontos que os testes verificam; divergencia entre os
dois arquivos e defeito.

## Invariantes verificados por `validate-presentation.sh`

| ID | Regra | Mensagem (stderr, prefixo `story.md:LINHA:`) |
|----|-------|---------------------------------------------|
| G-01 | frontmatter com `title` e `lang` (`pt-BR`/`en`) | `frontmatter: ...` |
| G-02 | tipo de slide no catalogo fechado (FR-016) | `tipo de slide desconhecido: X` |
| G-03 | `cover` unico e primeiro; `sources` unico e ultimo | `cover ...` / `sources ...` |
| G-04 | `briefing`/`constitution` presentes quando o inventario os tem; `closing` presente | `falta slide ...` |
| G-05 | `spec` com `key=` existente e unico; toda spec do inventario coberta (FR-005) | `spec sem slide: K` / `key desconhecida: K` / `key duplicada: K` |
| G-06 | `spec` com exatamente 4 `###` (FR-006) | `spec K: esperado 4 secoes ###, obtido N` |
| G-07 | `@source` presente em `briefing`, `constitution`, `spec`; arquivo existe | `slide sem @source` / `@source inexistente: P` |
| G-08 | `@metric` com chave valida para o escopo (FR-013) | `@metric chave invalida: K` |
| G-09 | diretiva conhecida | `diretiva desconhecida: @X` |
| G-10 | sem placeholders | `placeholder: X` |

## Invariantes do render (`render-presentation.sh`)

| ID | Regra |
|----|-------|
| R-01 | texto escapado (`&`, `<`, `>`, `"`) antes da formatacao inline (FR-015) |
| R-02 | saida identica para entradas identicas (FR-012) |
| R-03 | nenhum `src=`, `href=`, `@import` ou `url(` apontando para rede no HTML gerado; o render nunca emite links a partir do texto (FR-010) |
| R-04 | um `<section class="slide ...">` por slide da story, na mesma ordem |
| R-05 | valor de metrica ausente renderizado como rotulo localizado de "nao registrado", nunca `0` |
