# Research: Apresentacao Narrativa do Projeto

## Decision 1: Render deterministico em awk, redator escreve so a story

- **Decision**: o LLM escreve apenas `story.md`; o HTML sai de
  `render-presentation.sh` (awk) + template.
- **Rationale**: o usuario pediu que "todo resultado obedeca ao mesmo
  formato". Se o LLM escrevesse HTML, cada execucao divergiria em
  estrutura e classes. Com gramatica fechada + render deterministico, o
  formato e garantido por construcao e testavel (FR-012, FR-016).
- **Alternatives considered**: LLM preenche o HTML diretamente (rejeitado:
  nao deterministico, sem teste possivel); gerador em Node/Python
  (rejeitado: Principio II, dependencia externa).

## Decision 2: Metricas por chave do inventario

- **Decision**: `@metric Rotulo | chave`; o render resolve o valor.
- **Rationale**: Principio VI. O pedido de texto "apaixonadamente
  vendavel" cria pressao para numeros de efeito; tirar o numero da mao do
  redator elimina a classe de erro, em vez de depender de revisao.
- **Alternatives considered**: validar numeros literais contra o
  inventario (rejeitado: heuristica fragil, falsos positivos em datas e
  versoes).

## Decision 3: Linha de base da retroalimentacao em `inventory.tsv`

- **Decision**: gravar o inventario da geracao junto da story e comparar
  por digest (`cksum`) na proxima execucao.
- **Rationale**: diff simples, legivel e versionavel; nao polui a story
  com metadados. `cksum` e POSIX (sem `sha256sum`/`shasum`, que variam
  entre Linux e macOS).
- **Alternatives considered**: digests no frontmatter da story (rejeitado:
  a story e editada a mao e o bloco seria corrompido); mtime (rejeitado:
  muda em checkout).

## Decision 4: Template autocontido com fontes do sistema

- **Decision**: CSS e JS inline, pilhas de fontes do sistema (serifada
  editorial para titulos, `system-ui` para texto, mono para metricas),
  timeline em CSS, sem mermaid.
- **Rationale**: Principio IV e uso offline (apresentacao em sala sem
  rede, anexo de e-mail). O bundle do Claude Design do painel
  (`panel/docs/06-ui-ux-design/castk-panel/`) carregava Google Fonts e
  unpkg; aqui isso seria violacao.
- **Alternatives considered**: embutir fontes em base64 (rejeitado: peso
  e licenciamento); reveal.js (rejeitado: CDN ou vendoring grande).

## Decision 5: Um HTML, tres modos

- **Decision**: sem JS o documento ja e o modo relatorio (rolagem); o JS
  ativa o modo slides (canvas 16:9 escalado) e alterna com a tecla R;
  `@media print` gera um slide por pagina.
- **Rationale**: o mesmo artefato serve de apresentacao formal e de
  relatorio humanizado, como pedido; degradacao graciosa.

## Decision 6: Precedente `decision-tree`

- **Decision**: seguir o padrao da skill removida `decision-tree`
  (`docs/specs/_archived/decision-tree/`): script POSIX + template HTML,
  saida offline, read-only sobre as fontes.
- **Rationale**: o padrao ja passou pelo crivo da constitution. A
  diferenca e que aqui a narrativa e escrita pelo LLM, e por isso a
  validacao contra o inventario e obrigatoria.

## Decision 7: Chave unica de spec = caminho relativo a `specs/`

- **Decision**: `wave-close-summary`, `_archived/2026-09-09-roadmap-wave`,
  `current/roadmap-mode`.
- **Rationale**: specs vivas reutilizam o nome de specs arquivadas
  (`roadmap-mode` existe nos dois lugares); o caminho relativo e unico e
  auto-explicativo.

## Decision 8: Ordem narrativa do inventario

- **Decision**: arquivadas em ordem cronologica (sem data primeiro, como
  "origens"), depois ativas, depois vivas.
- **Rationale**: conta a historia do passado ao presente e termina no
  comportamento vigente do sistema; o redator agrupa capitulos seguindo
  essa ordem.
