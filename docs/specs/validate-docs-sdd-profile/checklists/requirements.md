# Requirements Checklist: validate-docs-sdd-profile

**Purpose**: Valida a QUALIDADE dos requisitos (spec.md + plan.md) antes de
`/create-tasks` — foco em (a) cobertura dos dois perfis spec-profile/
plan-profile, (b) fronteira de nao-duplicacao com `analyze`/
`validate-docs-rendered` testavel, (c) completude do contrato CLI para
implementar, (d) convencao `tests/test_<nome>.sh` refletida, (e) criterios
derivados de fonte real (Principio VI). "Unit tests for English."
**Created**: 2026-07-10
**Feature**: [spec.md](../spec.md) · [plan.md](../plan.md) · [contracts/validate-sdd-cli.md](../contracts/validate-sdd-cli.md)

> Legenda: `{auto}` resolvivel contra artefatos; `{humano}` julgamento de
> negocio; marcadores `[Gap]`/`[Ambiguity]`/`[Conflict]`.

## (a) Cobertura dos dois perfis (US1 spec-profile / US2 plan-profile)

- [x] CHK001 - Os FRs do spec-profile cobrem as 3 secoes obrigatorias e os 6 anti-padroes estruturalmente detectaveis catalogados em `specify/examples/spec-bad.md`? [Completude, Spec §FR-001..007, SC-002] {auto} — SIM: FR-001 (secoes), FR-002 (impl. detail), FR-003 (SC nao-mensuravel/jargao), FR-004 (>3 NEEDS CLARIFICATION), FR-005 (N/A residual), FR-006 (adjetivo vago), FR-007 (stories acopladas) — 1:1 com os 6 anti-padroes referenciados em SC-002.
- [x] CHK002 - Os FRs do plan-profile cobrem as 4 secoes obrigatorias, placeholder de template, rotulo real-vs-proposto, `[NEEDS CLARIFICATION]` residual e referencia `FR-`/`SC-` inexistente? [Completude, Spec §FR-008..012] {auto} — SIM: FR-008 (secoes), FR-009 (placeholder), FR-010 (rotulo, aplica Principio VI), FR-011 (clarification residual), FR-012 (dangling ref).
- [x] CHK003 - Cada Acceptance Scenario de US1 (AS1-4) e US2 (AS1-4) tem um FR correspondente rastreavel? [Traceability, Spec §User Scenarios] {auto} — SIM: US1 AS1→FR-001(zero erros), AS2→FR-001, AS3→FR-004, AS4→FR-002/FR-003; US2 AS1→FR-008, AS2→FR-012, AS3→FR-010, AS4→FR-009.
- [ ] CHK004 - O finding `duplicate-id` (catalogado no contrato e exercitado no quickstart Cenario 5) tem um FR correspondente na secao Requirements do `spec.md`? [Traceability, contracts/validate-sdd-cli.md §Catalogo, quickstart.md §Cenario 5] {auto} — **[Gap]**: o contrato marca a origem como "Gotcha da skill" (nao um FR novo) e a citacao e legitima — `global/skills/validate-documentation/SKILL.md:267` ja trata "IDs duplicados dentro do mesmo documento" como erro para o perfil UC existente, entao o check REUSA convencao ja estabelecida, nao inventa criterio (Principio VI preservado). Ainda assim, nenhum FR-NNN do `spec.md` desta feature cobre explicitamente esse check para o spec-profile — `create-tasks` deve garantir que a task de implementacao do `duplicate-id` cite `SKILL.md:267` como fonte (nao um FR ausente) para nao ficar orfa de rastreabilidade.
- [x] CHK005 - As Key Entities (`SddSpecArtifact`, `SddPlanArtifact`, `SddValidationProfile`, `ValidationFinding`) cobrem os conceitos usados pelos FRs sem introduzir vocabulario novo nao explicado? [Consistencia, Spec §Key Entities, data-model.md] {auto} — SIM: `data-model.md` reproduz as 4 entidades como conceituais (sem persistencia) e mapeia cada uma ao artefato/linha de saida correspondente do contrato.

## (b) Fronteira de nao-duplicacao com `analyze`/`validate-docs-rendered`

- [x] CHK006 - FR-018 declara, por categoria de check, qual das tres skills e a dona (nao apenas afirmacao solta de "nao duplica")? [Clareza, Spec §FR-018, plan.md §Fronteira] {auto} — SIM: `plan.md` §"Fronteira de responsabilidade (SC-005)" materializa uma tabela de 8 categorias × dono, reproduzindo `research.md` Decision 4.
- [x] CHK007 - A fronteira e verificavel por teste, nao apenas declarativa? [Mensurabilidade, quickstart.md §Cenario 9] {auto} — SIM: Cenario 9 tem um "Nao-Expected" explicito ("NENHUM achado sobre link/anchor quebrado no disco") junto do "Expected" (`dangling-fr-sc-ref`), tornando a fronteira FR-012 vs FR-013 um assert negativo executavel, nao so prosa.
- [x] CHK008 - O formato de saida (`FINDING|severity|code|msg`) evita colisao de namespace com os achados de `validate-docs-rendered` (que usa saida tab-separated com categorias `Link`/`Frontmatter`/`Mermaid`, nao `code` kebab-case)? [Consistencia] {auto} — SIM verificado por leitura direta de `global/skills/validate-docs-rendered/scripts/validate.sh` (linhas 46-52, 167, 193): formato e vocabulario de campo sao inteiramente distintos do contrato desta feature; os dois scripts nunca emitem para o mesmo stream combinado.
- [x] CHK009 - SC-005 ("zero achados sobrepondo categoria de `analyze`/`validate-docs-rendered`") define um mecanismo de verificacao concreto, nao so aspiracional? [Mensurabilidade, Spec §SC-005] {auto} — SIM (com ressalva): o mecanismo declarado e "checklist documentado de fronteira" (tabela em `plan.md`), nao um teste automatizado de sobreposicao — escolha deliberada registrada em `research.md` Decision 4 (rejeitou deixar a fronteira implicita na prosa). E verificavel por auditoria humana/CI de doc, nao por assert de codigo; suficiente para o escopo desta feature de tooling.

## (c) Completude do contrato CLI (`contracts/validate-sdd-cli.md`)

- [x] CHK010 - A precedencia entre flag explicita (`--sdd-spec`/`--sdd-plan`), deteccao automatica por path e "perfil indeterminado" esta definida sem ambiguidade de ordem? [Clareza, contracts/validate-sdd-cli.md §Selecao de perfil, Spec §FR-014..016] {auto} — SIM: 3 niveis numerados explicitos (flag > auto-path > indeterminado exit 2), com FR-014/FR-015/FR-016 correspondentes.
- [x] CHK011 - O formato de saida (stdout) documenta TODOS os campos (severity, code, mensagem, linha RESULT final) com exemplo concreto? [Completude, contracts/validate-sdd-cli.md §Saida] {auto} — SIM: secao "Saida (stdout)" define os 3 campos + linha `RESULT` sempre emitida, com 3 exemplos completos (conformante/reprovado/indeterminado) na secao final.
- [x] CHK012 - Os 3 exit codes (0/1/2) tem semantica e rationale registrados (por que exit-por-Erro, nao exit-por-qualquer-finding)? [Clareza, contracts/validate-sdd-cli.md §Exit codes, research.md Decision 3] {auto} — SIM: tabela de exit codes + link explicito para `research.md` Decision 3, que compara com o precedente divergente de `validate-tasks-template.sh` e justifica a escolha.
- [ ] CHK013 - Todo finding code do catalogo tem FR de origem definido sem ambiguidade? [Rastreabilidade, contracts/validate-sdd-cli.md §Catalogo] {auto} — **[Gap]** (mesma raiz de CHK004): 12 dos 13 codes tem FR direto; `duplicate-id` cita "(Gotcha da skill: ...)" em vez de um FR-NNN — consistente e rastreavel (ver CHK004), mas quebra o padrao 1:1 code→FR dos demais 12 e merece nota explicita na task de implementacao para nao ser lido como omissao acidental.
- [ ] CHK014 - O default de resolucao da `spec.md` correspondente (flag `--spec`, usado pelo check FR-012) esta especificado para TODOS os casos de invocacao, inclusive artefatos de teste fora da convencao `docs/specs/<feature>/`? [Clareza, contracts/validate-sdd-cli.md §Argumentos] {auto} — **[Ambiguity]**: o contrato define o default como `<dir-de-FILE-ou-pai>/spec.md resolvido pela convencao docs/specs/<feature>/`, cobrindo os 2 casos reais do pipeline (arquivo direto em `docs/specs/<f>/` e `contracts/*.md` um nivel abaixo). Nao cobre explicitamente o caso de fixture de teste fora dessa convencao (ex.: copia em dir temporario para `tests/test_validate-sdd.sh`) sem `--spec` — o contrato esta marcado `[PROPOSTA]`, entao a resolucao fica para `/execute-task` (baixo risco: `research.md` Decision 5 ja assume fixtures copiadas de `docs/specs/enforced-guards/`, que preserva a convencao de path).
- [x] CHK015 - O contrato distingue claramente decisao de design `[PROPOSTA — a validar na implementacao]` de fonte real, evitando que a CLI ainda-nao-implementada seja lida como contrato observado (Principio VI)? [Clareza, contracts/validate-sdd-cli.md linhas 9-18] {auto} — SIM: bloco de abertura do contrato e explicito ("Nenhum campo abaixo e extraido de fonte real observada") e cita os precedentes REAIS verificados por leitura (`validate-tasks-template.sh`, `validate.sh`) separadamente das decisoes de design novas.

## (d) Convencao `tests/test_<nome>.sh`

- [x] CHK016 - A obrigatoriedade do teste-irmao para o novo script esta documentada no plano de implementacao? [Completude, plan.md §Technical Context "Testing", §Project Structure] {auto} — SIM: `plan.md` cita `tests/test_validate-sdd.sh` explicitamente com a convencao `global/skills/*/scripts/<n>.sh → tests/test_<n>.sh` e o gate `./tests/run.sh --check-coverage`.
- [x] CHK017 - O plano identifica a fonte das fixtures de teste (boas/quebradas) como artefato real existente, nao fabricado? [Traceability, plan.md §Project Structure, research.md Decision 5] {auto} — SIM: fixtures "boas" citam `docs/specs/enforced-guards/{spec,plan}.md`, artefato real e verificavel no repo (nao hipotetico).
- [x] CHK018 - A criacao do teste esta refletida como item de estrutura de source code a criar (nao apenas mencionada em prosa solta)? [Clareza, plan.md §Source Code] {auto} — SIM: bloco "Source Code" lista `tests/test_validate-sdd.sh` com marcador `CRIAR` e descricao do gate, no mesmo nivel do script principal.

## (e) Veracidade de dados — Principio VI

- [x] CHK019 - As decisoes tecnicas do plano (precedentes `validate-tasks-template.sh`, `validate.sh`) citam fonte verificavel por leitura, nao suposicao? [Traceability, research.md Decision 1, Decision 3] {auto} — SIM: research.md registra "foi verificado por leitura direta" para a ausencia de `scripts/` em `validate-documentation` e cita linhas/arquivos concretos para os precedentes.
- [x] CHK020 - O check `unlabeled-contract` (FR-010) aplica o proprio Principio VI ao artefato validado, em vez de introduzir um vetor de fabricacao na propria feature? [Consistencia, Spec §FR-010, plan.md §Constitution Check linha VI] {auto} — SIM: FR-010 exige rotulagem real-vs-proposto em `contracts/*.md`; a Constitution Check do proprio `plan.md` marca a linha VI como PASS citando que o proprio contrato desta feature segue essa rotulagem (`[PROPOSTA — a validar na implementacao]`).
- [x] CHK021 - Os valores concretos citados no plano (ex.: numero de secoes obrigatorias, contagem de finding codes) sao derivados de contagem real dos artefatos, nao estimativa solta? [Mensurabilidade, plan.md §Technical Context "Scale/Scope"] {auto} — SIM: "~13 finding codes" e "~2 perfis" batem com a contagem real do catalogo em `contracts/validate-sdd-cli.md` (8 codes spec-profile + 5 codes plan-profile = 13).

## Consistencia e Rastreabilidade

- [x] CHK022 - A terminologia spec-profile/plan-profile e usada de forma consistente entre spec.md, plan.md e o contrato (sem sinonimo divergente)? [Consistencia] {auto} — SIM: os 3 artefatos usam exatamente "spec-profile"/"plan-profile" sem variacao (ex.: nunca "perfil-spec" ou "spec profile").
- [x] CHK023 - Os Success Criteria SC-001..006 se ligam a cenarios concretos do quickstart? [Traceability, quickstart.md] {auto} — SIM: SC-001→Cenario 1/2, SC-002→Cenarios 3/4/5/6, SC-003→Cenario 7, SC-004→Cenario 10, SC-005→fronteira (CHK009), SC-006→adocao pelos orquestradores (fora do escopo do quickstart, tracked via plan §Proximos Passos).
- [x] CHK024 - As FRs desta feature nao contradizem a constitution do projeto (v1.2.0, 6 principios)? [Constitution Alignment, plan.md §Constitution Check] {auto} — SIM: tabela de 6 principios no plan.md, todos PASS, com nota especifica de que o Principio VI e REFORCADO (nao apenas nao-violado) pelo FR-010.
- [x] CHK025 - A premissa de estabilidade da convencao `docs/specs/<feature>/` (base da deteccao automatica US3) esta documentada com contingencia caso mude? [Clareza, Spec §Dependencies & Assumptions] {auto} — SIM: ultima "Assume" da secao declara explicitamente "se essa convencao mudar, a deteccao automatica precisa ser revisada".

## Ambiguidades e decisao de produto

- [ ] CHK026 - A ordem de implementacao proposta em `plan.md` §Proximos Passos (script → SKILL.md → teste, US1 antes de US2/US3) reflete a prioridade real de entrega, ou o dono do produto prefere entregar US1+US3 (ergonomia de deteccao automatica) antes de aprofundar US2? [Risco, Spec §User Scenarios prioridades P1/P2/P3] {humano} — spec ja justifica P1(US1)/P2(US2)/P3(US3) por "MVP mais frequente primeiro"; aguardando confirmacao do dono do produto de que essa ordem serve tambem para `/create-tasks` (nenhum sinal em contrario nos artefatos).

## Notes

- Items `{auto}` resolvidos: 23 (`[x]` com citacao).
- Items abertos para `/create-tasks`: CHK004/CHK013 `[Gap]` (finding `duplicate-id` sem FR direto — task deve citar `SKILL.md:267` como fonte explicita, nao criar FR fantasma), CHK014 `[Ambiguity]` (default de `--spec` para fixtures fora da convencao — resolver em `/execute-task` do script).
- Item `{humano}`: CHK026 (confirmar ordem de entrega US1→US2→US3 para o backlog).
- Nenhum `[Conflict]` encontrado entre spec.md e plan.md nesta rodada.
