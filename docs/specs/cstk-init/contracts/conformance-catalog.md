# Contract: catalogo de regras de conformidade (CR-NNN)

[PROPOSTA — a validar na implementacao] — rascunho da tarefa 2.9 (dec-024); vira
`references/conformance-rules.md` na tarefa 5.3. Consumido por `init-conformance.sh check`
(contracts/cli-invocation.md §4) e pela divergencia de data-model §Divergence.
Fontes lidas em 2026-11-14: `plugins/cstk/skills/briefing/templates/briefing.md`,
`plugins/cstk/skills/constitution/templates/constitution.md`,
`plugins/cstk/skills/specify/templates/feature-spec.md`, `plugins/cstk/skills/constitution/SKILL.md`
(principio-base, §4.2, versionamento), `plugins/cstk/skills/briefing/SKILL.md` (caminho legado).
Nenhuma regra abaixo e inventada: cada linha cita a fonte; o padrao vigente e o dos templates
instalados na raiz de catalogo da execucao (research Decision 5).

## 1. Regras derivadas de template (`missing-section`)

Emitidas como `<artifact>\tmissing-section\t<titulo-ausente>\tadd-section` quando um titulo
exigido pelo template instalado nao existe no artefato. Nao recebem ID CR-NNN (derivadas, nao
nomeadas). Titulos exigidos hoje (lidos dos templates acima):

| Artefato | Titulos exigidos (nivel + texto) |
|----------|----------------------------------|
| briefing | `## 1. Visao e Proposito`, `## 2. Usuarios e Stakeholders`, `## 3. Escopo`, `## 4. Prioridades e Trade-offs`, `## 5. Restricoes`, `## 6. Stack Tecnica`, `## 7. Qualidade e Padroes`, `## 8. Visao de Futuro`, `## Itens a Definir` |
| constitution | `## Core Principles`, `## Governance` (as secoes 2 e 3 do template tem nome livre e nao sao exigidas) |
| spec | `## User Scenarios & Testing`, `### Edge Cases`, `## Requirements`, `### Functional Requirements`, `## Success Criteria`, `### Measurable Outcomes` |

Operacao: `amend` (acrescentar a secao, so insercao, confirmacao por arquivo — FR-010).

## 2. Regras nomeadas

| ID | Artefato | Condicao de divergencia | Correcao proposta (`proposal`) | Operacao | Fonte |
|----|----------|-------------------------|--------------------------------|----------|-------|
| CR-001 | briefing | existe so em `docs/01-briefing-discovery/briefing.md` (estado `legacy`) | MOVER o arquivo para o caminho canonico `docs/briefing.md` (`migrate-path`), somente com confirmacao explicita por caminho; sem confirmacao o legado permanece (FR-032, dec-026 D6) | `migrate` | FR-010, US2 cenario 2; `briefing/SKILL.md` (caminho legado preservado, nunca movido sem o usuario) |
| CR-002 | briefing | existem os dois caminhos (estado `both`) | `manual`: apresentar os dois e pedir a decisao ao operador antes de qualquer migracao | nenhuma (decisao do operador) | spec Edge Cases ("Briefing legado e canonico coexistem") |
| CR-003 | briefing | cabecalho sem as linhas `**Data**:`, `**Status**:` ou `**Versao**:` | `manual`: propor o campo ausente a ser preenchido pelo operador (sem valor presumido) | `amend` | `briefing/templates/briefing.md` linhas 3-5 |
| CR-004 | constitution | rodape sem a linha `**Version**: ... \| **Ratified**: ... \| **Last Amended**: ...` ou malformada | `fix-footer`: restaurar o rodape com os valores ja presentes no documento; campo sem valor vira `[PENDENTE: ...]` | `amend` (bump PATCH) | `constitution/templates/constitution.md` (rodape); `constitution/SKILL.md` (SemVer) |
| CR-005 | constitution | nenhum principio "Veracidade de Dados — Zero Fabricacao" | `add-principle`: propor o texto-semente da skill `constitution`, a ser confirmado pelo operador (FR-004); nunca altera principios ratificados | `amend` (bump MINOR — novo principio) | `constitution/SKILL.md` ("Principio-base obrigatorio"; MINOR para novo principio) |
| CR-006 | constitution | principio sem a linha `**MUST:**` | `manual`: o texto normativo pertence ao operador; so listar a divergencia | nenhuma ate decisao | `constitution/SKILL.md` (linha `**MUST:**` garante M >= 1) |
| CR-007 | spec | sem a secao `## Delta Requirements` | `add-delta-section`: acrescentar a secao com o marcador `**Skip**` (a secao e opcional no template — recusar e valido) | `amend` | `specify/templates/feature-spec.md` (Delta Requirements OPCIONAL) |
| CR-008 | briefing, constitution, spec | artefato existe mas NAO foi avaliado: symlink que escapa da raiz, diretorio `docs/specs`/de spec symlink (nao seguido) ou arquivo nao regular/legivel (tarefa 7.5.2, achado L7) | `manual`: informar que nao foi avaliado e por que; decisao do operador | nenhuma ate decisao | `init-conformance.sh` (somente leitura); `STATUS` passa a `divergent` |

Cobertura das tres classes (tarefa 2.9.2): briefing (CR-001..CR-003 + `missing-section`),
constitution (CR-004..CR-006 + `missing-section`), spec (CR-007 + `missing-section`); transversal: CR-008 (artefato nao avaliado, 7.5.2).

## 3. Rastreio com o quickstart (tarefa 2.9.5)

| Divergencia do Scenario 6 (fixture `legacy`) | Regra do catalogo |
|-----------------------------------------------|-------------------|
| briefing so em `docs/01-briefing-discovery/briefing.md` ("caminho legado") | CR-001 |
| constitution "sem secao exigida" | `missing-section` (constitution, §1) |

Rastreio de cenario novo exigido: a fixture `legacy` deve incluir apenas divergencias presentes
neste catalogo; divergencia sem regra aqui e defeito da fixture ou do catalogo.

## 4. Pendencias do catalogo

- Politica de CR-001: MOVE com confirmacao por caminho (FR-032, dec-026 D6; resposta do operador ao block-001), executado por `init-guard.sh migrate`.
- Regras para specs existentes alem de CR-007 e `missing-section` (US2: "specs sem secoes
  atuais") nao tem fonte adicional nos templates lidos; nao foram inventadas.
