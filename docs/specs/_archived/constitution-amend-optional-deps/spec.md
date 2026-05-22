# Feature Specification: Constitution Amendment — Optional Dependencies with Graceful Fallback

**Feature**: `constitution-amend-optional-deps`
**Created**: 2026-04-24
**Status**: Draft
**Constitution Target Version**: 1.0.0 → 1.1.0 (MINOR bump)

## Resumo

A constitution atual do toolkit (1.0.0) bane nominalmente ferramentas nao-POSIX
(`jq`, `ripgrep`, `fd`, `bats`) em scripts que acompanham skills, sem reconhecer a
categoria de dependencia OPCIONAL com fallback graceful. A feature `cstk-cli`
introduziu uma dep opcional em `jq` exclusivamente em `cli/lib/hooks.sh` para merge
seguro de JSON em `./.claude/settings.json` de projeto, com fallback documentado
(CLI imprime o bloco JSON para paste manual quando `jq` nao esta instalado).
Constitution §Decision Framework item 4 exige amendment formal para qualquer
excecao a MUST (Principios I/II/IV). Esta spec formaliza essa via.

A emenda NAO afrouxa o Principio II: Bash-isms continuam proibidos; `ripgrep`, `fd`
e `bats` permanecem banidos; dependencias obrigatorias continuam vetadas. A emenda
reconhece e disciplina uma CATEGORIA NOVA — dep opcional com fallback — mediante
tres guard rails cumulativos.

## User Scenarios & Testing

### User Story 1 - Maintainer amenda Principio II e atualiza versionamento (Priority: P1)

O mantenedor edita `docs/constitution.md` adicionando uma subsecao clara sob
Principio II que define a categoria "dep opcional com fallback graceful" + tres
condicoes cumulativas. Atualiza o Sync Impact Report no topo, bump da versao para
1.1.0, e registra a data do amendment. Este e o MVP — sem esta story, nao ha
amendment.

**Why this priority**: e a entrega nuclear. Tudo o mais (retroativo em cstk-cli,
propagacao downstream) depende do texto amendado existir.

**Independent Test**: comparar `docs/constitution.md` antes e depois. Verificar
que o texto original do Principio II NAO foi removido (apenas expandido com
subsecao nova). Version footer bumpou de 1.0.0 para 1.1.0. Sync Impact Report
reflete a mudanca.

**Acceptance Scenarios**:

1. **Given** constitution 1.0.0 com Principio II banindo `jq` nominalmente,
   **When** o mantenedor aplica o amendment, **Then** constitution 1.1.0 contem
   subsecao intitulada "Optional dependencies with graceful fallback" listando
   as tres condicoes cumulativas, E texto original do Principio II permanece
   inalterado, E Version footer = 1.1.0.
2. **Given** amendment aplicado, **When** um contribuidor le `docs/constitution.md`
   em ordem, **Then** encontra no Principio II primeiro a regra original ("zero
   dependencia alem de POSIX canonico") e logo abaixo a subsecao disciplinando
   a excecao — sem contradicao aparente.
3. **Given** amendment aplicado, **When** ferramentas ja banidas nominalmente
   (`ripgrep`, `fd`, `bats`) sao verificadas, **Then** elas continuam banidas
   pela letra do Principio II — amendment nao as reabilita.

---

### User Story 2 - Primeiro caso concreto (`jq` em cstk-cli) e registrado retroativamente (Priority: P2)

Com o amendment em vigor, a dep opcional em `jq` dentro de `cli/lib/hooks.sh` da
feature `cstk-cli` passa a ter status formalmente conforme. A ligacao precisa ser
explicita: constitution cita `jq` como primeiro caso concreto; `cstk-cli/plan.md`
§Complexity Tracking cita o amendment como base legal.

**Why this priority**: sem essa story, o amendment paira no abstrato — e D1 da
analise do cstk-cli continua CRITICAL. Resolver essa ligacao e o que desbloqueia
F7 do backlog do cstk-cli.

**Independent Test**: rodar `/analyze` em `docs/specs/cstk-cli/` apos amendment +
atualizacao do plan.md. O finding D1 (jq exception) deve deixar de ser CRITICAL.

**Acceptance Scenarios**:

1. **Given** constitution 1.1.0 com a subsecao nova, **When** `plan.md` do cstk-cli
   for atualizado referenciando o amendment como base para a excecao do `jq`,
   **Then** o caminho de codigo em `cli/lib/hooks.sh` fica explicitamente dentro
   das tres condicoes cumulativas.
2. **Given** amendment aplicado, **When** outra feature futura propuser uma dep
   opcional, **Then** ela pode se auto-qualificar lendo a subsecao — sem exigir
   nova amendment da constitution.

---

### User Story 3 - Propagacao obrigatoria para features ativas e CLAUDE.md (Priority: P3)

Constitution §Governance estabelece que MINOR bumps exigem: re-rodar `/analyze`
em features ativas; atualizar CLAUDE.md se principio afeta instrucoes; atualizar
Sync Impact Report. Esta story garante que essas propagacoes nao sao esquecidas.

**Why this priority**: processo de governanca existe, esta story e a execucao
ritual dele. Baixa se cstk-cli for a unica feature afetada, mas vira bloqueante
se houver outras features em andamento.

**Independent Test**: checklist de propagacao completo, verificavel linha a linha
no final da execucao.

**Acceptance Scenarios**:

1. **Given** amendment 1.1.0 aplicado, **When** o mantenedor lista features
   ativas (specs com tasks pendentes), **Then** `/analyze` foi re-rodado em cada
   uma e eventuais violacoes introduzidas pelo amendment foram documentadas.
2. **Given** amendment aplicado, **When** CLAUDE.md e lido, **Then** ou (a) contem
   apontador para a nova subsecao da constitution se relevante, ou (b) nao foi
   alterado com justificativa explicita (amendment nao afeta instrucoes gerais).

---

### Edge Cases

- **Dep opcional "vira" obrigatoria ao longo do tempo**: o que antes era opcional
  com fallback passa a ser core da feature (fallback removido). Nao viola amendment
  retroativamente, mas a feature precisa nova spec + nova avaliacao contra
  Principio II.
- **Dep espalhada por multiplos arquivos**: tentativa de justificar como "opcional"
  enquanto fere a condicao (2) de confinamento. Amendment exige refatoracao para
  consolidar em um unico arquivo antes de aceitar.
- **Fallback nao-verificavel**: feature declara fallback mas nao o testa. Viola
  condicao (1) que exige "documentado E verificavel". Amendment exige teste
  automatizado cobrindo o caminho fallback.
- **Outra ferramenta banida nominalmente** (`ripgrep`, `fd`, `bats`) tenta entrar
  via amendment atual: NAO e permitido. Amendment e carve-out para a categoria
  conceitual, nao reabilita nominalmente as banidas especificas — essas continuam
  vetadas mesmo como "opcional".

## Requirements

### Functional Requirements

- **FR-001**: `docs/constitution.md` MUST ser editado adicionando uma subsecao
  nomeada "Optional Dependencies with Graceful Fallback" sob o Principio II,
  imediatamente apos o bloco `**MUST:**` atual e antes do `**Rationale:**`.
- **FR-002**: A subsecao nova MUST enumerar exatamente tres condicoes CUMULATIVAS
  (todas precisam se satisfazer) para permitir dep nao-POSIX:
  (a) uso genuinamente opcional com fallback graceful documentado E verificavel
      por teste automatizado;
  (b) codigo que referencia a dep confinado em UM unico arquivo identificavel;
  (c) a dep declarada explicitamente na documentacao da feature que a introduz
      (em `spec.md` ou `plan.md` da feature).
- **FR-003**: A subsecao nova MUST afirmar explicitamente que: (i) Bash-isms
  permanecem proibidos em qualquer script, opcional ou nao; (ii) ferramentas ja
  banidas nominalmente (`ripgrep`, `fd`, `bats`) permanecem vetadas inclusive
  como deps opcionais; (iii) deps obrigatorias (sem fallback) permanecem
  proibidas sob Principio II.
- **FR-004**: O texto original do Principio II MUST permanecer inalterado —
  amendment e EXPANSAO, nao substituicao.
- **FR-005**: `docs/constitution.md` MUST ter Version footer atualizado para
  `1.1.0`, data `Last Amended` = 2026-04-24.
- **FR-006**: O Sync Impact Report (comentario HTML no topo de
  `docs/constitution.md`) MUST ser atualizado declarando: bump 1.0.0 → 1.1.0;
  rationale (MINOR adiciona subsecao material); Principios afetados
  (II, expandido); artefatos que precisam atualizacao (cstk-cli/plan.md
  §Complexity Tracking, CLAUDE.md se aplicavel); TODOs pendentes.
- **FR-007**: A subsecao nova MUST citar o primeiro caso concreto: dep opcional
  em `jq` em `cli/lib/hooks.sh` da feature `cstk-cli`, com link relativo para
  `docs/specs/cstk-cli/spec.md` §FR-009d e para
  `docs/specs/cstk-cli/plan.md` §Complexity Tracking.
- **FR-008**: Constitution §Decision Framework item 4 MUST ser atualizado: "Excecao
  a MUST (Principios I, II, IV) exige amendment da constitution — nao ha opt-out
  tacito" mantem-se, mas ganha nota adicional de que subsecoes de carve-out
  dentro do proprio Principio (como a introduzida por este amendment) sao
  mecanismo valido de conformidade quando precedidas por amendment com MINOR
  bump.
- **FR-009**: `/analyze` MUST ser executado manualmente pelo mantenedor em todas
  as features ativas (minimo: `docs/specs/cstk-cli/`) apos o amendment ser
  aplicado. Resultado esperado: finding D1 do cstk-cli deixa de aparecer como
  CRITICAL — aparece como PASS ou e removido.
- **FR-010**: `docs/specs/cstk-cli/plan.md` §Complexity Tracking MUST ser
  atualizado substituindo a frase "**Violacao**: Principio II" por referencia ao
  amendment e pelas tres condicoes cumulativas, demonstrando conformidade explicita.

### Key Entities

- **Constitution Document**: `docs/constitution.md`. Versionado via SemVer na
  secao Governance. Cada amendment atualiza Sync Impact Report + Version footer +
  Last Amended.
- **Optional Dependency Case**: registro (por dep) com nome da ferramenta,
  feature de origem, caminho do arquivo confinado, verificacao do fallback.
  Reside no `plan.md` da feature que introduz a dep; referenciado da constitution.
- **Amendment Spec**: esta propria spec. Vive em
  `docs/specs/constitution-amend-optional-deps/`. Historico de raciocinio
  permanente para decisoes futuras.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Apos amendment aplicado, um contribuidor novo consegue ler
  `docs/constitution.md` uma unica vez e determinar em menos de 5 minutos se
  uma proposta de dep opcional especifica passa as tres condicoes cumulativas,
  sem precisar consultar specs ou outros documentos.
- **SC-002**: Rodar `/analyze` em `docs/specs/cstk-cli/` apos amendment +
  atualizacao do plan.md (FR-010) resulta em zero findings CRITICAL relacionados
  ao Principio II. Especificamente, finding D1 ("jq exception") deixa de aparecer.
- **SC-003**: Nenhum principio MUST anterior (I, II, IV) que estava PASS na
  analise 1.0.0 passa a aparecer como FAIL apos amendment 1.1.0. Verificavel
  rodando `/analyze` em todas as specs do repo e comparando resultados.
- **SC-004**: Version footer de `docs/constitution.md` bate exatamente com
  `**Version**: 1.1.0 | **Ratified**: 2026-04-20 | **Last Amended**: 2026-04-24`
  apos amendment. Verificavel via `grep`.
- **SC-005**: O texto completo do Principio II original (incluindo todas as
  linhas sob `**MUST:**` e `**Rationale:**`) permanece byte-a-byte identico apos
  amendment. Verificavel via `diff` entre versao anterior e atual das linhas
  correspondentes. Amendment e SOMENTE adicao, nao modificacao.
- **SC-006**: A subsecao nova contem EXATAMENTE tres condicoes numeradas — nem
  mais, nem menos. Verificavel via leitura da estrutura.
- **SC-007**: Toda feature futura que introduzir dep opcional conforme o carve-out
  inclui em seu `spec.md` ou `plan.md` uma declaracao explicita apontando para
  a subsecao do amendment (rastreabilidade bidirecional). Verificavel manualmente
  em review.
