# Catalogo de regras de conformidade — cstk-init

Referencia do `SKILL.md` (lida sob demanda no modo de revisao). Consumida por
`init-conformance.sh check --root <dir> --catalog-root <dir-de-skills>`, que emite uma linha por
divergencia: `<artifact><TAB><rule><TAB><detail><TAB><proposal>` e a linha final
`STATUS<TAB>conformant|divergent` (exit 0 com ou sem divergencias; exit 4 = template de irma
ausente, instrua `cstk install`, perfil `sdd`).

O "padrao vigente" e o dos templates instalados na raiz de catalogo da execucao
(`briefing/templates/briefing.md`, `constitution/templates/constitution.md`,
`specify/templates/feature-spec.md`); a versao do cstk usada vem de `init-probe.sh version` e
deve ser declarada no relatorio. Nenhuma regra abaixo consulta rede. IDs `CR-NNN` sao
1:1 com os emitidos pelo script (teste: `tests/test_init-conformance.sh`); cada regra cita a fonte.

Politica de aplicacao (confirmacao por caminho, emenda por insercao, bump): `write-policy.md`.
Divergencia `manual` nunca vira escrita sem decisao e texto do operador.

## 1. Regras derivadas de template (`missing-section`)

Emitidas como `<artifact><TAB>missing-section<TAB><titulo-ausente><TAB>add-section` quando um
titulo exigido pelo template instalado nao existe no artefato (comparacao por titulo exato, fora
de bloco de codigo). Nao recebem ID `CR-NNN`: sao derivadas, nao nomeadas. Os titulos sao LIDOS do
template instalado (titulos sem placeholder `[`/`<`); hoje:

| Artefato | Titulos exigidos |
|----------|------------------|
| briefing | `## 1. Visao e Proposito`, `## 2. Usuarios e Stakeholders`, `## 3. Escopo`, `## 4. Prioridades e Trade-offs`, `## 5. Restricoes`, `## 6. Stack Tecnica`, `## 7. Qualidade e Padroes`, `## 8. Visao de Futuro`, `## Itens a Definir` |
| constitution | `## Core Principles`, `## Governance` (as secoes 2 e 3 do template tem nome livre e nao sao exigidas) |
| spec | `## User Scenarios & Testing`, `### Edge Cases`, `## Requirements`, `### Functional Requirements`, `## Success Criteria`, `### Measurable Outcomes` (`## Delta Requirements` e coberto por `CR-007`; `### Key Entities` e condicional) |

Proposta: `add-section`. Operacao: `amend` (so insercao; corpo da secao vindo do operador ou
`[PENDENTE: ...]`), com confirmacao por arquivo.

## 2. Regras nomeadas

### CR-001 — briefing so no caminho legado

- **Artefato**: briefing. **Condicao**: existe so em `docs/01-briefing-discovery/briefing.md` (estado `legacy`).
- **Proposta (`migrate-path`)**: MOVER para `docs/briefing.md`, somente com confirmacao explicita do
  caminho; sem confirmacao o legado permanece (FR-032).
- **Operacao**: `migrate` (via `init-guard.sh migrate --root <raiz> --confirmed`).
- **Fonte**: FR-010, US2 cenario 2; `briefing/SKILL.md` (caminho legado preservado, nunca movido sem o usuario).

### CR-002 — briefing nos dois caminhos

- **Artefato**: briefing. **Condicao**: existem `docs/briefing.md` e o caminho legado (estado `both`).
- **Proposta (`manual`)**: apresentar os dois caminhos e pedir a decisao do operador antes de qualquer migracao; `migrate` recusa (`exists`).
- **Operacao**: nenhuma (decisao do operador).
- **Fonte**: spec, Edge Cases ("Briefing legado e canonico coexistem").

### CR-003 — cabecalho do briefing incompleto

- **Artefato**: briefing. **Condicao**: cabecalho sem a linha `**Data**:`, `**Status**:` ou `**Versao**:` (rotulos lidos do template instalado, antes do primeiro `## `).
- **Proposta (`manual`)**: propor o campo ausente para o operador preencher; sem valor presumido.
- **Operacao**: `amend`.
- **Fonte**: `briefing/templates/briefing.md` (cabecalho).

### CR-004 — rodape de versao da constitution ausente ou malformado

- **Artefato**: constitution. **Condicao**: nenhuma linha `**Version**: v | **Ratified**: v | **Last Amended**: v` com os tres valores nao vazios e sem placeholder.
- **Proposta (`fix-footer`)**: restaurar o rodape com os valores ja presentes no documento; campo sem valor vira `[PENDENTE: ...]`.
- **Operacao**: `amend` (bump PATCH).
- **Fonte**: `constitution/templates/constitution.md` (rodape); `constitution/SKILL.md` (SemVer).

### CR-005 — principio "Veracidade de Dados" ausente

- **Artefato**: constitution. **Condicao**: nenhum titulo de principio contem `Veracidade de Dados`.
- **Proposta (`add-principle`)**: propor o texto-semente da skill `constitution` ("Principio-base obrigatorio"), a ser confirmado pelo operador (FR-004); nunca altera principios ratificados.
- **Operacao**: `amend` (bump MINOR: novo principio).
- **Fonte**: `constitution/SKILL.md` (principio-base obrigatorio; MINOR para novo principio).

### CR-006 — principio sem linha `**MUST:**`

- **Artefato**: constitution. **Condicao**: um `### ` sob `## Core Principles` cujo bloco nao tem linha `**MUST:**`.
- **Proposta (`manual`)**: o texto normativo pertence ao operador; so listar a divergencia.
- **Operacao**: nenhuma ate decisao do operador.
- **Fonte**: `constitution/SKILL.md` (a linha `**MUST:**` garante cobertura de MUST pelo gate `converge`).

### CR-007 — spec sem `## Delta Requirements`

- **Artefato**: spec (`docs/specs/<short>/spec.md`). **Condicao**: secao `## Delta Requirements` ausente.
- **Proposta (`add-delta-section`)**: acrescentar a secao com o marcador `**Skip**` e justificativa nao vazia (a secao e opcional no template: recusar e valido).
- **Operacao**: `amend`.
- **Fonte**: `specify/templates/feature-spec.md` (Delta Requirements opcional).

### CR-008 — artefato existente NAO avaliado

- **Artefato**: briefing (canonico ou legado), constitution, `docs/specs` ou spec. **Condicao**: o
  artefato existe mas o `check` nao pode le-lo com seguranca: caminho com symlink que escapa da raiz,
  diretorio `docs/specs` ou de spec que e symlink (nao seguido) ou arquivo que existe mas nao e
  regular/legivel. O conteudo nunca e lido; ha aviso em stderr.
- **Proposta (`manual`)**: informar o operador de que o artefato NAO foi avaliado e por que; a
  decisao (corrigir o link/permissao e reexecutar, ou aceitar) e dele.
- **Operacao**: nenhuma ate decisao do operador.
- **Efeito no `STATUS`**: conta como divergencia, logo `STATUS<TAB>divergent`; "nao avaliado" nunca
  aparece como `conformant`. Ausencia de arquivo (nada a avaliar) NAO e CR-008.

## 3. Cobertura e limites

- **Briefing**: `CR-001`..`CR-003` + `missing-section`. Nenhum briefing = nenhuma divergencia (modo de criacao).
- **Constitution**: `CR-004`..`CR-006` + `missing-section`.
- **Spec**: `CR-007` + `missing-section`. Specs sob `_archived/`, `current/` e `_*` nao sao avaliadas (ignoradas, sem achado); diretorio ou arquivo de spec symlink, ou que escape da raiz, nao e avaliado e gera `CR-008`.
- **Qualquer artefato**: `CR-008` quando existe e nao pode ser avaliado (ver acima).
- Regras para specs existentes alem destas (por exemplo "specs sem secoes atuais" de forma geral) nao tem
  fonte adicional nos templates lidos e NAO foram inventadas: nao crie regra nova durante a execucao.
- Decisao do operador sobre cada divergencia (`accepted`, `refused`, `pending`) vive so na conversa e
  no resumo; recusada = arquivo identico byte a byte (SC-004).
