# Data Model: validate-docs-sdd-profile

## N/A — feature de tooling sem modelo de dados persistente

Esta feature nao introduz nenhuma entidade persistida (sem banco, sem
schema, sem arquivo de estado novo). E um motor de validacao sincrono e
stateless: le UM artefato de texto, aplica checks e emite achados em stdout.
Portanto NAO ha modelo de dados relacional/documental a projetar.

As "Key Entities" listadas na spec sao entidades CONCEITUAIS (tipos de
artefato e de achado), nao registros persistidos. Documentadas abaixo apenas
para rastreabilidade spec ↔ plan; sua representacao em runtime e efemera (o
proprio arquivo de entrada e as linhas `FINDING`/`RESULT` de saida definidas
em `contracts/validate-sdd-cli.md`).

| Entidade (spec) | Natureza | Representacao em runtime |
|-----------------|----------|--------------------------|
| **SddSpecArtifact** | Conceitual — um `spec.md` gerado por `specify` | O arquivo `FILE` passado ao script quando o perfil resolvido e spec-profile. Nao persistido pela feature. |
| **SddPlanArtifact** | Conceitual — um artefato da familia `/plan` (`plan.md`, `research.md`, `data-model.md`, `quickstart.md`, `contracts/*.md`) | O arquivo `FILE` passado ao script quando o perfil resolvido e plan-profile. Nao persistido. |
| **SddValidationProfile** | Conceitual — conjunto de checks aplicavel a um tipo de artefato | Ramo de codigo do script selecionado por flag/deteccao de path (spec-profile vs plan-profile). Sem estado. |
| **ValidationFinding** | Conceitual — achado individual com severidade e localizacao | Linha `FINDING|<severity>|<code>|<msg>` em stdout (contrato). Efemero; nao gravado. |

**Transicoes de estado**: N/A — a validacao e uma funcao pura
`(artefato, perfil) → lista de achados + veredito de exit`. Nao ha ciclo de
vida, nao ha mutacao de registro.

**Relacionamentos**: a unica relacao entre entidades e a referencia SEMANTICA
de um `SddPlanArtifact` (`plan.md`) para os IDs `FR-`/`SC-` de um
`SddSpecArtifact` (`spec.md`) da mesma feature — verificada por FR-012 (o ID
citado existe na spec) e explicitamente NAO por resolucao de path/anchor no
disco (FR-013, dono `validate-docs-rendered`).
