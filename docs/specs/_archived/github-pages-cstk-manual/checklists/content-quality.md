# Content-Quality Checklist: GitHub Pages — Manual do cstk

**Purpose**: Validar a QUALIDADE dos requisitos relacionados a conteudo,
single-source-of-truth, integridade de links, sanitizacao de markdown
exotico, slugs estaveis e cobertura de inventario. Items abaixo testam
se os requisitos estao bem-escritos — nao a implementacao.

**Created**: 2026-05-19
**Feature**: [spec.md](../spec.md)
**Domain**: content-quality
**Aderente a**: Constitution-delta D-I (NON-NEG), D-VI; FR-004, FR-010,
FR-011, FR-016, FR-017, FR-024; SC-006, SC-008.

---

## 1. Single-Source-of-Truth (D-I)

- [ ] CHK001 - O requisito de "conteudo unico no repo-fonte" esta
  declarado de forma binaria e auditavel (nao apenas aspiracional)?
  [Clareza, Spec §FR-010]
- [ ] CHK002 - A spec define explicitamente o que NAO pode existir
  apenas no diretorio-fonte do site (`docs-site/`) — paragrafos
  substantivos, listas hardcoded de skills, copia de README?
  [Completude, Spec §FR-010]
- [ ] CHK003 - O requisito de "renderizacao do conteudo canonico do .md
  fonte sem duplicar texto" identifica os campos especificos a serem
  preservados (headings, listas, code blocks, tabelas, frontmatter)?
  [Clareza, Spec §FR-004]
- [ ] CHK004 - Existe criterio mensuravel para detectar violacao de D-I
  (ex: comando/check que falha se houver duplicacao)? [Mensurabilidade,
  Gap]
- [ ] CHK005 - O termo "paragrafo substantivo" em FR-010 esta
  quantificado ou exemplificado (vs frases-ponte aceitaveis no site)?
  [Ambiguity, Spec §FR-010]

## 2. Integridade de Links Internos (FR-011)

- [ ] CHK006 - A spec define se link interno quebrado e WARNING ou ERRO
  bloqueante para o MVP (FR-011 admite ambos como aceitaveis)?
  [Ambiguity, Spec §FR-011]
- [ ] CHK007 - O escopo de "link interno" esta definido — apenas
  paginas geradas, ou inclui referencias a imagens, anchors (#section),
  e arquivos do repo-fonte? [Completude, Spec §FR-011]
- [ ] CHK008 - Existe requisito para validar anchors (`#heading`) alem
  de paths de pagina? [Gap]
- [ ] CHK009 - O comportamento esperado para link APONTANDO para arquivo
  do repo-fonte (ex: link relativo `../briefing.md` dentro de uma skill)
  esta definido? [Gap, Spec §FR-011]
- [ ] CHK010 - O criterio de aceite de "link quebrado interno" inclui
  links que apontam para skill removida na build atual? [Cobertura,
  Spec §Edge Cases]

## 3. Sanitizacao de Markdown Exotico (FR-024)

- [ ] CHK011 - As 4 categorias de syntax exotica estao enumeradas
  exaustivamente (HTML inline, frontmatter Claude-specifico,
  comentarios HTML, code blocks com fences nao-padrao) — ou ha
  categorias implicitas nao-cobertas? [Completude, Spec §FR-024]
- [ ] CHK012 - Para frontmatter Claude-specifico, a spec lista quais
  campos sao parseados pelo plugin `meta` (`name`, `description`,
  `allowed-tools`) vs quais sao expostos como variaveis de pagina?
  [Clareza, Spec §FR-024]
- [ ] CHK013 - O criterio para emitir warning (vs ignorar silenciosamente)
  esta definido objetivamente — quais padroes disparam warning?
  [Mensurabilidade, Spec §FR-024]
- [ ] CHK014 - A spec especifica o comportamento para code-block com
  linguagem inexistente no Pygments (fallback sem highlight) e
  diferencia desse caso "linguagem invalida que quebra o parser"?
  [Clareza, Spec §FR-024]
- [ ] CHK015 - Existe requisito sobre o que acontece se HTML inline
  contem tag `<script>` (CSP bloqueia execucao, mas o tag fica visivel
  no source HTML)? [Edge Case, Spec §FR-024]
- [ ] CHK016 - O warning de syntax exotica e auditavel — registrado no
  log do build de forma greppable? [Gap]

## 4. Slugs Estaveis e Derivados (FR-016, FR-017)

- [ ] CHK017 - A regra de derivacao de slug a partir do path-fonte esta
  definida sem ambiguidade (ex: `global/skills/briefing/SKILL.md` →
  `/skills/briefing/`)? [Clareza, Spec §FR-016, §FR-017]
- [ ] CHK018 - O comportamento de slug para skill com nome contendo
  underscore, ponto ou maiusculas esta especificado (ex:
  `go-add-entity` vs `dotnet_create_test`)? [Edge Case, Gap]
- [ ] CHK019 - Para `language-related/<lang>/skills/<nome>/SKILL.md`,
  a regra `/skills/<lang>/<nome>/` esta consistente entre FR-016 e
  FR-017 (ambos descrevem o padrao identicamente)? [Consistencia,
  Spec §FR-016, §FR-017]
- [ ] CHK020 - O requisito de "slug estavel" tem criterio de violacao
  observavel (ex: skill renomeada gera 404 — ja coberto em Edge Cases
  da spec)? [Mensurabilidade, Spec §FR-016]
- [ ] CHK021 - A spec define como tratar colisao de slug — duas skills
  com mesmo nome em diferentes diretorios (ex: `global/skills/briefing/`
  e hipotetico `language-related/go/skills/briefing/`)? [Edge Case,
  Gap]
- [ ] CHK022 - O slug para agents (`global/agents/<nome>.md` —
  arquivo, nao diretorio) tem regra consistente com skills (que sao
  diretorios)? [Consistencia, Spec §FR-016]

## 5. Cobertura do Inventario (SC-006, SC-008)

- [ ] CHK023 - Os numeros minimos em SC-006 (>=21 skills globais, >=8
  Go, >=8 Dotnet, >=3 agents, >=3 commands) refletem o inventario REAL
  atual do repo (verificavel via glob)? [Mensurabilidade, Spec
  §SC-006]
- [ ] CHK024 - O criterio "ZERO listagem hardcoded no diretorio-fonte
  do site" em SC-006 esta definido objetivamente — o que conta como
  "hardcoded" vs "configuracao legitima" (ex: `nav:` em `mkdocs.yml`
  e excecao aceita)? [Clareza, Spec §SC-006]
- [ ] CHK025 - SC-008 define como verificar "adicionar skill nova e
  SUFICIENTE" — existe procedimento de teste explicito? [Mensurabilidade,
  Spec §SC-008]
- [ ] CHK026 - A spec cobre o caso de diretorio listado em
  `language-related/<lang>/skills/` mas SEM `SKILL.md` (skill
  parcialmente removida)? [Edge Case, Spec §Edge Cases]
- [ ] CHK027 - Existe requisito sobre o que conta como "skill valida"
  para o build incluir no indice (ex: precisa ter campo `name` no
  frontmatter? Precisa ter conteudo nao-vazio?)? [Gap, Spec §FR-003]

## 6. Consistencia Cross-Requirement

- [ ] CHK028 - O glob de FR-003 (`global/skills/*/SKILL.md`) e
  consistente com o glob de FR-007 (`global/skills/**/SKILL.md`) —
  um usa `*`, outro `**`? [Consistencia, Spec §FR-003, §FR-007]
- [ ] CHK029 - O numero de paginas auto-geradas em SC-006 (>=43) bate
  com a soma dos minimos (21+8+8+3+3 = 43)? [Consistencia, Spec
  §SC-006]
- [ ] CHK030 - A lista de categorias em FR-002 (Skills, Agents,
  Commands) e consistente com a lista de URLs em FR-016 (skills,
  agents, commands, manual) — manual aparece em FR-016 mas nao em
  FR-002? [Consistencia, Spec §FR-002, §FR-016]
- [ ] CHK031 - O requisito FR-010 ("conteudo apenas a partir de .md
  versionados") e compativel com a existencia de paginas-ponte do
  diretorio-fonte do site mencionadas em "Key Entities — Page"?
  [Consistencia, Spec §FR-010, §Key Entities]

## 7. Atributos de Conteudo (Key Entities)

- [ ] CHK032 - A entidade "Page" lista atributos conceituais (slug,
  titulo, categoria, descricao curta, corpo) — mas a regra para
  derivar "descricao curta" tem fallback definido quando frontmatter
  ausente E primeira frase ausente? [Edge Case, Spec §Key Entities]
- [ ] CHK033 - A entidade "Catalog Section" tem criterio de ordem
  definido — alfabetica ou curada — mas a spec nao fixa qual usar por
  categoria; isso e decisao de plan ou requisito? [Ambiguity, Spec
  §Key Entities]
- [ ] CHK034 - O atributo "tags" do Search Index (em Key Entities)
  tem origem definida — sao extraidos do frontmatter, do
  filesystem, ou nao existem ainda? [Gap, Spec §Key Entities]

## 8. Edge Cases e Premissas

- [ ] CHK035 - O Edge Case "imagem em .md referenciada com path
  relativo invalido" esta consistente com FR-011 (validacao de
  links) — imagem conta como link interno? [Consistencia, Spec
  §Edge Cases, §FR-011]
- [ ] CHK036 - A premissa "imagens podem referenciar paths relativos
  do repositorio fonte" (Assumptions) implica regra de copia de assets
  no build — isso esta documentado como requisito ou e deixado para
  plan? [Gap, Spec §Assumptions]
- [ ] CHK037 - O Edge Case "skill renomeada → 404 sem redirect" esta
  alinhado com SC-008 ("zero edicao manual") — mudanca de nome NAO e
  edicao manual, e portanto aceitavel quebrar URL antiga?
  [Consistencia, Spec §Edge Cases, §SC-008]
- [ ] CHK038 - O CHANGELOG.md (mencionado em Assumptions) tem
  requisito de geracao automatica ou e estatico mantido manualmente?
  [Ambiguity, Spec §Assumptions]

---

## Notes

- Marcar items concluidos com `[x]`.
- Items numerados sequencialmente; preservar ordem em qualquer
  re-execucao desta skill no mesmo dominio (APPEND, nao overwrite).
- Gaps e ambiguidades identificados aqui devem entrar como entrada
  para `/clarify` adicional ou para o `plan.md` resolver.
- Rastreabilidade: 36/38 items (~95%) tem referencia a secao da spec
  ou marcador `[Gap]`/`[Ambiguity]`/`[Edge Case]`/`[Consistencia]`.
