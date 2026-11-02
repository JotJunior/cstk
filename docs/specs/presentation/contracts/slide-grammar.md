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
| G-11 | texto narrativo sem tecniques estrutural: crases, URL, endpoint, flag, caminho, arquivo (FR-018) | `tecniques: <tipo> "<trecho>" (...)` |
| G-12 | termo do glossario `references/jargon.txt` fora de `vocabulary:` gera **aviso**, nao erro (FR-019) | `aviso: termo tecnico "X" (...)` |
| G-13 | no maximo 3 `@tag` por slide (FR-020) | `slide com N @tag (maximo 3)` |
| G-14 | com `--summary`: no maximo 4 slides, `cover` primeiro, `closing` ultimo, sem `spec`/`chapter`/`timeline`/`sources` nem `@timeline`/`@sources`, sem cobertura das specs (FR-023) | `versao resumida com N slides (maximo 4)` / `tipo X nao permitido na versao resumida` / `closing deve ser o ultimo slide na versao resumida` |
| G-15 | `highlights` com 1 a 3 `###` e `@source` obrigatorio (FR-024) | `highlights: esperado 1 a 3 secoes ###, obtido N` / `slide highlights sem @source` |

## Invariantes do render (`render-presentation.sh`)

| ID | Regra |
|----|-------|
| R-01 | texto escapado (`&`, `<`, `>`, `"`) antes da formatacao inline (FR-015) |
| R-02 | saida identica para entradas identicas (FR-012) |
| R-03 | nenhum `src=`, `href=`, `@import` ou `url(` apontando para rede no HTML gerado; o render nunca emite links a partir do texto (FR-010) |
| R-04 | um `<section class="slide ...">` por slide da story, na mesma ordem |
| R-05 | valor de metrica ausente renderizado como rotulo localizado de "nao registrado", nunca `0` |
| R-06 | `@tag` vira `<div class="tags">` com rotulo localizado ("Por tras"/"Under the hood") (FR-020) |
| R-07 | rodape: rotulo amigavel por fonte (briefing, constituicao, titulo narrativo da spec dona do arquivo, "documentacao do projeto"), deduplicado, caminhos em `title=` (FR-021) |
| R-08 | `@timeline` e `@sources` usam o titulo narrativo da spec quando o slide ja foi visto (FR-022) |
| R-09 | `highlights` renderiza com eyebrow localizado ("Valor entregue"/"Delivered value") e cartoes `cards--N`; o mesmo render produz `summary.html` a partir de `summary.md` (FR-023, FR-024) |
