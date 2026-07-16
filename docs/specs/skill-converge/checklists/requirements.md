# Requirements Checklist: skill-converge

**Purpose**: Quality gate dos requisitos (spec.md + plan.md + research.md +
data-model.md + contracts + quickstart.md) antes de `create-tasks` — valida
completude, clareza, consistencia, mensurabilidade e cobertura de cenarios
da skill `converge` (reconciliacao spec-vs-codigo). Nao valida implementacao
(codigo da skill ainda nao existe — verificado nesta onda). Os 3 hardening
de seguranca (SEC-1/2/3) do gate `owasp-security` (dec-020) tem checklist
dedicado em [security.md](./security.md).
**Created**: 2026-07-16
**Feature**: [spec.md](../spec.md) · [plan.md](../plan.md)

> Legenda: `{auto}` = resolvivel contra spec/plan/research/data-model/contracts
> (resolvido com citacao). `{humano}` = julgamento de risco/negocio (aberto).
> Marcadores de gap: `[Gap]` requisito ausente, `[Ambiguity]` interpretacao
> multipla, `[Conflict]` contradicao entre artefatos.

## Completude de Requisitos

- [x] CHK001 - As tres fontes de intencao (spec/plan-quando-presente/tasks) e
  a fonte de restricao (constitution) estao distinguidas, com `plan.md`
  marcado explicitamente como opcional sem impedir a execucao? [Completude,
  Spec §FR-001/FR-002, §Edge Cases "plan.md nao existe"] {auto}
- [x] CHK002 - O requisito de avaliar o ESTADO PRESENTE do codigo,
  dissociado de historico de git/diff de sessao, esta explicito e sem
  excecao? [Completude, Spec §FR-003] {auto}
- [x] CHK003 - A proibicao de rodar suite de testes/build (leitura semantica
  estatica apenas) delimita FR-004 sem ambiguidade de escopo frente a
  "testar implementacao"? [Completude/Clareza, Spec §FR-004, §Clarifications
  Q3] {auto}
- [x] CHK004 - Os 4 tipos de divergencia sao exaustivos e mutuamente
  exclusivos ("exatamente um")? [Completude, Spec §FR-005] {auto}
- [x] CHK005 - A regra de escalada CRITICAL por violacao de MUST domina os
  demais criterios de severidade, com ordem de avaliacao explicita (primeira
  que casa vence)? [Completude, Spec §FR-006/FR-020, research.md §Decision 3
  tabela] {auto}
- [x] CHK006 - O conteudo minimo por achado (path + origem) e criterio de
  EXCLUSAO (achado sem localizacao nao e reportado), nao so campo
  recomendado? [Completude, Spec §FR-007, Constitution VI] {auto}
- [x] CHK007 - O formato da fase apendada (numeracao, checkbox, tag de
  criticidade) referencia explicitamente o formato ja em uso, evitando
  reinvencao de convencao? [Completude, Spec §FR-008, plan.md §Project
  Structure `create-tasks/templates/tasks.md`] {auto}
- [x] CHK008 - A garantia append-only cobre as tres dimensoes (nao
  modificar, nao renumerar, nao remover) de conteudo pre-existente?
  [Completude, Spec §FR-009] {auto}
- [x] CHK009 - O comportamento "zero achados acionaveis" (nao apendar fase
  vazia) esta coberto tanto pela spec quanto pelo data-model (existencia
  condicional da fase)? [Completude, Spec §FR-010, data-model.md
  §ConvergencePhase "existencia: condicional"] {auto}
- [x] CHK010 - A chave de deduplicacao (FR-012) fixa exatamente os
  atributos exigidos pela clarification correspondente (path + tipo +
  origem), sem campo a menos ou a mais? [Completude, Spec §FR-012,
  §Clarifications Session 2026-07-16 Q1] {auto}
- [ ] CHK011 - A funcao de normalizacao (`normalize()`) usada na composicao
  da `gap_key` (path e origem) esta definida em algum artefato (regras de
  trim, case-fold, separador de path, resolucao relativa)? [Gap,
  data-model.md §Entity Gap "gap_key = sha256-12(normalize(path) + " " +
  type + " " + normalize(origin))"] {auto} — **[Gap]**: nenhum artefato
  (spec/plan/research/data-model/contracts) define o que `normalize()`
  faz. Dois paths semanticamente iguais escritos de forma diferente
  (`./scripts/foo.sh` vs `scripts/foo.sh`, trailing slash, maiusculas)
  podem gerar `gap_key` diferente e quebrar FR-011/FR-012 (idempotencia/
  dedup) exatamente no mecanismo que as garante. `/create-tasks` deve
  apendar tarefa definindo `normalize()` (provavelmente em
  `extract-intent.sh` ou `converge-tasks.sh`) antes de qualquer script que
  a consuma ser implementado.
- [x] CHK012 - O destino de achados `unrequested` (item de revisao, nunca
  "implementar") e consistente entre spec (FR-013), data-model
  (`kind=revisar`) e quickstart (Scenario 3)? [Consistencia, Spec §FR-013,
  data-model.md §ConvergenceTask.kind, quickstart.md §Scenario 3] {auto}
- [x] CHK013 - O requisito de funcionamento standalone (sem exigir execucao
  ativa) e o requisito de execucao automatica incondicional dentro dos
  orquestradores estao demarcados como dois MODOS distintos de invocacao,
  sem overlap ambiguo? [Completude, Spec §FR-014/FR-015,
  contracts/converge-interfaces.md §1 "Modo standalone" vs "Modo
  autonomo"] {auto}
- [x] CHK014 - O ponto exato de disparo automatico (conclusao de
  `execute-task`, antes do inicio de `review-task` — nao a cada onda
  intermediaria de `execute-task`) esta inequivoco? [Clareza, Spec §FR-015
  "entre a conclusao de execute-task e o inicio de review-task"] {auto}
- [x] CHK015 - O conteudo minimo do relatorio (achados + resumo por tipo +
  resumo por severidade) tem formato concreto proposto, nao apenas
  descricao textual? [Completude, Spec §FR-016, contracts/
  converge-interfaces.md §7] {auto}
- [x] CHK016 - O comportamento de aborto (artefato ausente) nomeia o
  comando que gera cada artefato faltante, evitando deixar o usuario sem
  proximo passo? [Completude, Spec §FR-017, contracts/
  converge-interfaces.md §1 "/specify ou /create-tasks"] {auto}
- [ ] CHK017 - A fonte de verdade para "diretorio do projeto-alvo" (FR-018,
  usado por `path-contains.sh --root`) esta definida para o modo
  STANDALONE, onde nao ha `state.json`/`target_project_path` do
  orquestrador? [Gap, Spec §FR-018, contracts/converge-interfaces.md §6]
  {auto} — **[Gap]**: em modo autonomo o `--root` vem do `state.json`
  existente (`target_project_path`, ja resolvido pelo runtime 00c); em
  modo STANDALONE nenhum artefato define de onde vem esse valor (CWD?
  busca ascendente por `.git`? flag obrigatoria nao documentada?). Sem
  isso, `path-contains.sh` — a propria defesa de blast radius de FR-018 —
  nao tem entrada `--root` determinada em metade dos modos de invocacao da
  skill. `/create-tasks` deve fechar essa lacuna antes de implementar
  `path-contains.sh`/o fluxo standalone.
- [ ] CHK018 - A derivacao de `story_priority` (P1/P2/P3) a partir do
  `origin` de um achado (FR-NNN ou heading `### N.M` de task) esta
  definida, dado que `tasks.md` carrega apenas tags de criticidade
  `[C|A|M]` (eixo diferente de impacto) e nao uma tag de Priority de User
  Story? [Gap, Spec §FR-020, data-model.md §Entity Gap "story_priority...
  derivada da User Story de origem em spec.md",
  create-tasks/templates/tasks.md] {auto} — **[Gap]**: FR-020/research.md
  Decision 3 definem a FUNCAO `severidade(tipo, story_priority,
  must_violated)` mas nenhum artefato define o passo anterior — como
  mapear um `origin` (FR-NNN ou task `### N.M`) de volta a Priority
  (P1/P2/P3) da User Story correspondente em `spec.md`. O template de
  `tasks.md` so tem `[C|A|M]` (criticidade de negocio), eixo distinto de
  "Priority" da story. Sem essa derivacao explicita, a distincao
  HIGH-vs-MEDIUM de FR-020 (a maior parte da escala de severidade, fora do
  caso CRITICAL) fica subespecificada. `/create-tasks` deve apendar tarefa
  definindo o mecanismo de lookup origin→story_priority (ex.:
  `extract-intent.sh` carregar tambem a Priority da story-mae ao extrair
  o path).
- [x] CHK019 - Os achados `CRITICAL` em execucao autonoma tem destino de
  escalada definido (registro como Decisao + disponibilizacao ao
  orquestrador), sem a skill travar sozinha? [Completude, Spec §FR-019,
  data-model.md §ConvergenceReport "Materializacao como Decisao"] {auto}

## Clareza de Requisitos

- [x] CHK020 - O criterio para o tipo `unrequested` ("capacidade... nao
  descrita em nenhuma story/requisito... nem justificada como suporte
  incidental — config, boilerplate, wiring") e operacional o bastante para
  distinguir wiring legitimo de capacidade nao pedida, sem depender so de
  juizo subjetivo? [Clareza, Spec §US2 AC4] {auto}
- [x] CHK021 - O risco de oscilacao de classificacao entre `partial` e
  `contradicts` para o MESMO estado de codigo em execucoes distintas
  (ameaca direta a FR-011) esta reconhecido e mitigado, mesmo que a
  rubrica final fique para o `SKILL.md` (fase de implementacao)? [Clareza,
  research.md §Decision 2 "risco reconhecido... mitigacao: rubrica de
  classificacao deterministica", plan.md §Project Structure `SKILL.md`
  "fluxo agente + rubrica de classificacao deterministica"] {auto}
- [x] CHK022 - O formato canonico de `origin` (heading `### N.M` OU
  `FR-NNN`) esta fixado o bastante para servir de entrada estavel da
  `gap_key`, sem variantes equivalentes (`FR-007` vs `FR007` vs
  "Requisito 7")? [Clareza, Spec §FR-007/FR-012, research.md §Decision 4
  "o heading ### N.M ou o FR mais proximo"] {auto}

## Consistencia de Requisitos

- [x] CHK023 - FR-006 (CRITICAL por violacao de MUST, "independente do
  tipo") e a tabela de severidade de research.md §Decision 3 (avaliada em
  ordem, MUST primeiro) sao consistentes — inclusive para o caso
  `unrequested`-que-viola-MUST, que a leitura isolada da ultima linha da
  tabela ("unrequested → LOW") poderia sugerir incorretamente como
  sempre-LOW? [Consistencia, Spec §FR-006, research.md §Decision 3] {auto}
  — SIM: a regra "avaliada em ordem, primeira que casa vence" com a
  violacao de MUST na linha 1 garante que um achado unrequested-e-
  MUST-violador resolve CRITICAL antes de alcancar a linha
  `unrequested→LOW`; sem conflito.
- [x] CHK024 - O Constitution Check do plan.md confirma PASS para todos os
  principios aplicaveis, incluindo o Principio VI (Veracidade de Dados)
  que o proprio plan descreve como "materializado" pela feature?
  [Consistencia, plan.md §Constitution Check] {auto}
- [ ] CHK025 - A Decisao registrada pelo `ConvergenceReport`
  (`--escolha ∈ {aceitar, escalar-para-humano}`, contracts §8) usa o MESMO
  conjunto de opcoes do padrao generico de quality-gate ja em uso por
  `validate-documentation`/`owasp-security` nos orquestradores
  (`aceitar-risco-com-justificativa` / `corrigir-agora` /
  `escalar-para-humano`, 3 opcoes), ou a divergencia (2 opcoes, sem
  `corrigir-agora`) e intencional e deve permanecer assim? [Risco/
  Consistencia, contracts/converge-interfaces.md §8 vs
  `agente-00c-feature-orchestrator.md` §Quality Gates] {humano} — a
  omissao de `corrigir-agora` parece justificada pela propria arquitetura
  da feature (achados viram TAREFAS residuais em `tasks.md`, nunca
  correcao inline pelo orquestrador durante o gate — Decision 5/FR-008),
  mas e uma divergencia deliberada do padrao ja estabelecido nos demais
  gates; vale confirmacao do dono do produto antes de `/create-tasks`
  fixar o enum definitivamente.

## Qualidade de Criterios de Aceite (Mensurabilidade — SC-001..006)

- [x] CHK026 - SC-001 e objetivamente verificavel (zero achados
  CRITICAL/HIGH quando backlog 100% concluido e codigo fiel)?
  [Mensurabilidade, Spec §SC-001] {auto}
- [x] CHK027 - SC-002 e objetivamente verificavel (100% dos achados que
  violam MUST recebem CRITICAL, nenhum rebaixado) e sem sobreposicao
  contraditoria com SC-001? [Mensurabilidade/Consistencia, Spec
  §SC-001/SC-002] {auto}
- [x] CHK028 - SC-003 (idempotencia byte-a-byte) tem metodo de verificacao
  concreto e independente de interpretacao (`cmp`/`diff`)?
  [Mensurabilidade, Spec §SC-003, quickstart.md §Scenario 7] {auto}
- [x] CHK029 - SC-004 e SC-005 sao verificaveis por comparacao direta de
  artefato (path+origem citados / diff antes-depois), sem depender de
  leitura subjetiva? [Mensurabilidade, Spec §SC-004/SC-005] {auto}
- [x] CHK030 - SC-006 (standalone sem orquestrador) tem cenario de
  verificacao dedicado que confirma ausencia de tentativa de escrita em
  `state.json`? [Mensurabilidade, Spec §SC-006, quickstart.md
  §Scenario 12] {auto}

## Cobertura de Cenarios e Edge Cases

- [x] CHK031 - Todas as 5 User Stories (P1×2, P2×2, P3×1) tem ao menos um
  cenario de quickstart mapeado, incluindo o caso "zero achados acionaveis
  → nenhuma fase apendada" da US3-AC4? [Cobertura, spec.md §User
  Scenarios, quickstart.md Scenarios 1-12] {auto} — mapeamento: US1→
  Cen.1/2/9, US2→Cen.3/4/5, US3→Cen.6 (+ AC4 coberto por Cen.2), US4→
  Cen.7/8, US5→Cen.11.
- [ ] CHK032 - O Edge Case que a propria spec descreve como "exatamente o
  caso central desta feature" (task marcada `[x]` mas codigo nao bate →
  `partial`/`contradicts` independente do checkbox) tem um cenario de
  quickstart DEDICADO que monte esse setup especifico (checkbox concluido
  + codigo desalinhado), em vez de so cobrir `partial`/`contradicts` de
  forma generica? [Gap, Spec §Edge Cases "e exatamente o caso central
  desta feature", quickstart.md §Scenario 3] {auto} — **[Gap]**: Scenario
  3 testa a classificacao dos 4 tipos mas seu setup ("um parcialmente
  implementado", "um cujo comportamento contradiz a task") nao menciona o
  estado do checkbox `[x]`/`[ ]` na task de origem — a propria dimensao
  que a spec chama de "caso central" (Visao Geral, linhas 17-21:
  execucoes podem "deixar codigo parcialmente implementado... e nada no
  pipeline audita esse desvio"). Sem um cenario que fixe explicitamente
  "task JA marcada `[x]`, codigo diverge", o quickstart nao verifica a
  alegacao central da feature. `/create-tasks` deve apendar/ajustar um
  cenario com esse setup.
- [ ] CHK033 - Os Edge Cases "`plan.md` ausente" e "`constitution.md` do
  projeto nao existe" (ambos com comportamento degradado-mas-definido na
  spec) tem cobertura de cenario equivalente aos demais Edge Cases (que
  tem Scenario 9/10 dedicados)? [Gap, Spec §Edge Cases, quickstart.md
  Scenarios 1-12] {auto} — **[Gap]**: dos 5 Edge Cases da spec, 2
  (`plan.md` ausente: reduz contexto mas nao impede execucao;
  `constitution.md` ausente: CRITICAL por MUST fica indisponivel, demais
  severidades seguem) nao tem nenhum dos 12 cenarios de quickstart.md
  testando esse setup especifico — diferente do Edge Case "path fora do
  projeto-alvo", que tem o Scenario 10 dedicado. `/create-tasks` deve
  apendar 1-2 cenarios cobrindo essas duas ausencias de artefato.

## Dependencias e Premissas

- [x] CHK034 - A dependencia tecnica (`realpath` com fallback `cd`+
  `pwd -P`) e premissa de ambiente ja tratada em convencao global do repo
  (macOS/zsh, "nao depender de GNU-only"), nao introduzida ad-hoc por esta
  feature? [Dependencias, plan.md §Technical Context, research.md
  §Decision 6, CLAUDE.md global] {auto}
- [x] CHK035 - O reuso de runtime existente (`state-decisions.sh`,
  `state-ondas.sh`, `create-tasks/scripts/next-task-id.sh`) esta marcado
  como `[REAL]` com path verificado, distinguindo do que e `[NOVO]`/
  `[PROPOSTA]`? [Dependencias/Traceability, plan.md §Project Structure,
  contracts/converge-interfaces.md cabecalho] {auto}
- [x] CHK036 - A decisao de NAO reusar `path-guard.sh` do runtime 00c no
  core standalone tem justificativa explicita (evitar acoplar semantica de
  state-dir a um uso solo), preservando FR-014? [Dependencias/
  Consistencia, research.md §Decision 6] {auto}
- [x] CHK037 - A edicao necessaria dos dois orquestradores
  (`agente-00c-orchestrator.md`/`agente-00c-feature-orchestrator.md`) para
  o gate automatico (US5) esta explicitamente listada no Project
  Structure, para `create-tasks` nao omitir essa integracao do backlog?
  [Dependencias, plan.md §Project Structure] {auto}

## Notes

- Items `{auto}` resolvidos: 31 (`[x]` com citacao).
- Items abertos para consumo do `/create-tasks`: CHK011 `[Gap
  normalize()]`, CHK017 `[Gap --root standalone]`, CHK018 `[Gap
  origin→story_priority]`, CHK032 `[Gap cenario caso-central]`, CHK033
  `[Gap cenarios plan/constitution ausentes]`.
- Item `{humano}` aguardando dono do produto: CHK025 (enum de escolha da
  Decisao do gate converge — alinhar aos 3 valores do padrao generico ou
  manter os 2 intencionais).
- CHK011, CHK017 e CHK018 sao os tres gaps de MAIOR risco: todos atacam o
  mecanismo que garante FR-011/FR-012 (idempotencia) ou FR-018/FR-020
  (blast radius / severidade). Recomenda-se resolve-los ANTES de
  `/create-tasks` decompor os scripts correspondentes (`extract-intent.sh`,
  `path-contains.sh`, `converge-tasks.sh`), nao depois.
- Marcar items concluidos com `[x]`. Items numerados sequencialmente para
  referencia.
