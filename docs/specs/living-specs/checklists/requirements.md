# Requirements Checklist: Specs Vivas — Corpus Canonico, Delta Specs no Archive e Staging Explicito

**Purpose**: validar a qualidade dos requisitos (FR-001..FR-017, US1-4) antes
de `/create-tasks` — nao valida implementacao (nenhum script existe ainda,
todos os contratos estao `[PROPOSTA]`).
**Created**: 2026-07-23
**Feature**: [spec.md](../spec.md) | [plan.md](../plan.md)

## Delta Requirements Section (US1 / FR-001)

- [x] CHK001 - E a gramatica exata da secao `## Delta Requirements` (heading, blocos `### Capability:`, subgrupos `####`, prefixo de entrada) especificada de forma parseavel deterministicamente? [Clareza, Spec §FR-001] {auto}
  — Satisfeito: `contracts/delta-section-format.md` define a gramatica completa (heading, `### Capability: <slug>`, 4 subgrupos `####`, formato `- **FR-NNN**: <texto>` / `- **FR-NNN -> FR-MMM**`).
- [x] CHK002 - O identificador usado em ADDED e explicitamente amarrado ao mesmo esquema `FR-NNN` da secao `### Functional Requirements` da propria spec (evita dois namespaces de id)? [Clareza, Spec §FR-001, US1 Cenario 1] {auto}
  — Satisfeito: spec.md linha 81-82 ("cada requisito novo aparece listado sob ADDED com o mesmo identificador (`FR-NNN`) usado na secao de Requirements da propria spec") + contrato regra 4.
- [x] CHK003 - O formato do marcador RENAMED evita ambiguidade de seta (unicode vs ASCII) que quebraria parsing POSIX? [Clareza, Contract delta-section-format §Regras] {auto}
  — Satisfeito: research.md Decision 4 registra a rejeicao explicita de `→` unicode em favor de `->` ASCII; contrato regra 5 confirma.
- [x] CHK004 - O registro de Skip explicito (FR-011) especifica TODOS os campos obrigatorios (quem, quando, por que) e o que torna um skip invalido? [Completude, Spec §FR-011] {auto}
  — Satisfeito: `contracts/delta-section-format.md §Skip explicito` define os 3 campos obrigatorios (justificativa, autor, data) e o codigo `skip-invalid` para ausencia de qualquer um.
- [x] CHK005 - E vedada a coexistencia de Skip e blocos Capability na mesma secao (estado ambiguo "aplicar delta E pular")? [Consistencia, Contract delta-gate-cli §Codes] {auto}
  — Satisfeito: code `skip-with-delta` no `delta-gate-cli.md` cobre exatamente esse conflito.
- [ ] CHK006 - E a interacao entre a secao Delta Requirements nova e os gates SDD ja existentes (`validate-sdd.sh` spec-profile, `requirement-coverage.sh`) verificada para nao gerar falso-positivo (ex.: secao extra confundida com requisito nao coberto)? [Consistencia, Spec §FR-001] {auto}
  — Satisfeito: research.md Decision 4 cita verificacao real no repo (`validate-sdd.sh` linha 189 exige so 3 secoes fixas; `requirement-coverage.sh` linha 116 so extrai de `### Functional Requirements`, reseta em qualquer `##`/`###` seguinte) — ids delta nao entram na cobertura.

## Corpus Canonico (US2 / FR-002..FR-009)

- [x] CHK007 - E a estrutura de arquivo do corpus (`docs/specs/current/<capability-slug>.md`) especificada com secoes fixas (Requirements ativos, Removed, Renamed) de forma nao-ambigua? [Completude, Spec §FR-002..FR-006] {auto}
  — Satisfeito: `contracts/corpus-format.md` define as 3 secoes e o template de cada uma.
- [x] CHK008 - O campo de proveniencia (FR-007: "rastreavel ate a(s) feature(s) que a introduziu ou modificou por ultimo") esta quantificado com um formato concreto, nao so em prosa? [Mensurabilidade, Spec §FR-007] {auto}
  — Satisfeito: `corpus-format.md` define `*Introduzida por: <feature> (<data>)*` (imutavel) e `*Ultima modificacao: <feature> (<data>)*` (so apos 1o MODIFIED).
- [x] CHK009 - E o escopo de unicidade do identificador `FR-NNN` dentro do corpus explicitamente definido (global vs por-capability), evitando ambiguidade de colisao entre capabilities distintas? [Clareza, Spec Key Entities "Corpus Entry"] {auto}
  — Satisfeito: research.md Decision 5 fixa unicidade POR ARQUIVO de capability (namespace = capability); mesma numeracao em capabilities distintas nao colide.
- [x] CHK010 - E o comportamento de REMOVED especificado para nunca resultar em desaparecimento silencioso (preserva rastro do "porque")? [Completude, Spec §FR-004] {auto}
  — Satisfeito: FR-004 explicito + `corpus-format.md` secao `## Removed Requirements` com `*Removida por:*` + motivo obrigatorio.
- [x] CHK011 - E o comportamento de RENAMED especificado para preservar a rastreabilidade historica ligando id antigo a id novo? [Completude, Spec §FR-005] {auto}
  — Satisfeito: FR-005 + `corpus-format.md` secao `## Renamed Identifiers` (tabela Antigo/Novo/Feature/Data); id aposentado nunca reciclado (regra 1).
- [x] CHK012 - O determinismo do merge (mesmos inputs => mesmo corpus resultante byte-a-byte) e um requisito explicito, nao so uma expectativa implicita? [Mensurabilidade, Spec Edge Cases ultimo item] {auto}
  — Satisfeito: spec.md Edge Cases ("gate ... MUST produzir sempre o mesmo veredito") + `delta-merge-cli.md` invariante 3 (ordenacao por id, mesma data => mesmo resultado).
- [x] CHK013 - E especificado que a atualizacao do corpus e ADICIONAL ao archive existente e nunca uma substituicao (garante nao-regressao do fluxo hoje funcional)? [Consistencia, Spec §FR-006, US2 Cenario 5] {auto}
  — Satisfeito: FR-006 explicito + US2 Cenario 5.
- [x] CHK014 - E o caso "corpus/capability ainda nao existe" (primeiro merge) coberto sem exigir passo manual de bootstrap? [Cobertura de Edge Cases, Spec §US2 Cenario 4] {auto}
  — Satisfeito: US2 Cenario 4 + `corpus-format.md` ("Diretorio nasce vazio e e criado pelo primeiro merge") + `delta-gate-cli.md` code `corpus-missing` (severity=info, nao bloqueia).
- [x] CHK015 - Existe orientacao para o autor de uma nova feature descobrir/reusar o slug de capability ja em uso por outra feature (evitando fragmentar o mesmo conceito em dois arquivos de corpus por slugs distintos, ex. `commit-mode` vs `commit-staging`)? [Gap, Spec Key Entities "Living Spec Corpus"] {auto}
  — Satisfeito (fechado por tasks 1.1 + 2.2): `contracts/delta-section-format.md §Gramatica` item 1 fixa a regra de descoberta (`ls docs/specs/current/*.md` antes de declarar slug novo) + `specify/SKILL.md` implementa a prosa da orientacao. Julgamento de reuso permanece do autor (nao script), conforme 1.1.2.

## Gate Deterministico (US3 / FR-010..FR-013)

- [x] CHK016 - O gate especifica TODOS os codigos de bloqueio possiveis (nao so "delta ausente"), incluindo casos de referencia invalida e colisao? [Completude, Spec §FR-010, FR-013] {auto}
  — Satisfeito: `delta-gate-cli.md §Codes` lista 10 codes (`delta-missing`, `skip-invalid`, `delta-empty`, `capability-slug-invalid`, `entry-malformed`, `ref-not-found`, `added-collision`, `renamed-target-exists`, `skip-with-delta`, `corpus-missing`).
- [x] CHK017 - E o veredito do gate para "so REMOVED" (sem ADDED/MODIFIED) explicitamente coberto, evitando falso-bloqueio por secao "incompleta"? [Cobertura de Edge Cases, Spec §US3 Cenario 3] {auto}
  — Satisfeito: US3 Cenario 3 + `delta-gate-cli.md` invariante 3 ("Delta so-REMOVED e valida").
- [x] CHK018 - E o formato de saida do gate (severidade, exit codes) consistente com o padrao ja adotado por outros gates deterministicos do toolkit, evitando um terceiro formato paralelo? [Consistencia, Spec §FR-012] {auto}
  — Satisfeito: FR-012 exige "mesmo padrao ja adotado" + `delta-gate-cli.md` replica literalmente o formato `FINDING|`/`RESULT|` de `validate-sdd.sh`/`requirement-coverage.sh` (research.md Decision 6, fontes verificadas no repo).
- [x] CHK019 - O skip auditavel (FR-011) e distinguivel de uma aplicacao normal de delta em QUALQUER trilha que liste o archive, nao so no output do gate? [Mensurabilidade, Spec §FR-011] {auto}
  — Satisfeito no nivel do gate: `delta-gate-cli.md` invariante 2 (`delta=skip` no RESULT). Cobertura em `review-features` (relatorio de portfolio) nao verificada nesta checklist — ver CHK023.
- [x] CHK020 - E o comportamento do orquestrador autonomo (`agente-00c`, fase `review-features`) especificado para o caso em que `delta-gate.sh` bloqueia (exit 1) durante uma execucao sem supervisao — vira bloqueio humano via `bloqueios.sh`, ou a fase falha silenciosamente? [Gap, Spec Edge Cases + Plan Decision 8] {auto}
  — Satisfeito (fechado por tasks 1.2 + 4.2): `agente-00c-orchestrator.md` (fase `review-features`) registra `bloqueios.sh register` ESCOPADO a feature bloqueada (nao aborta a onda inteira), citando o `RESULT|...` literal do gate como evidencia; fluxo manual (`/review-features` interativo) segue reportando em prosa, sem `bloqueios.sh`.
- [x] CHK021 - E exigido que o gate seja um script determinístico (nao julgamento de modelo), removendo variabilidade de veredito entre execucoes? [Mensurabilidade, Spec §FR-012, Edge Cases ultimo item] {auto}
  — Satisfeito: FR-012 + Edge Cases ("roda como script deterministico... MUST produzir sempre o mesmo veredito") + `delta-gate-cli.md` invariante 1 (POSIX puro, sem jq).
- [ ] CHK022 - A politica de bloqueio para os 4 subcasos de conflito (MODIFIED/REMOVED/RENAMED referenciando id inexistente, colisao ADDED, RENAMED para id ja usado, referencia cross-feature nao arquivada) reflete o apetite de risco correto do mantenedor, ou algum desses casos deveria ser aviso (warning) em vez de bloqueio (error)? [Risco] {humano}

## Staging Explicito no Commit Atomico (US4 / FR-014..FR-017)

- [x] CHK023 - A proibicao de staging amplo especifica EXATAMENTE quais formas de "adicionar tudo" sao vedadas (nao so `git add -A`)? [Clareza, Spec §FR-014] {auto}
  — Satisfeito: `commit-staging-cli.md §stage-derived` passo 5 lista as 3 formas proibidas explicitamente: `git add -A`, `git add .`, `git add --all`.
- [x] CHK024 - Todos os sites de codigo/prosa que hoje fazem staging amplo estao identificados e listados, evitando que o fix corrija so um caminho e deixe outro intacto (o proprio modo de falha do incidente original)? [Completude, Spec §US4] {auto}
  — Satisfeito: research.md Decision 1 lista os 3 sites reais (2 arquivos de prosa dos orquestradores + `state-ondas.sh::_so_cmd_git_commit` em codigo), com rationale explicito de por que corrigir so a prosa reintroduziria o bug pelo caminho do wave-commit.
- [x] CHK025 - E o criterio para distinguir "untracked criado pela task corrente" de "untracked alheio pre-existente" especificado de forma deterministica (nao heuristica)? [Mensurabilidade, Spec §FR-015] {auto}
  — Satisfeito: `commit-staging-cli.md §snapshot`/`§stage-derived` define baseline capturado ANTES do trabalho da onda + `comm -13` (diff de conjuntos ordenados) — deterministico, sem heuristica de nome/extensao.
- [x] CHK026 - E o comportamento especificado para o caso "baseline de snapshot ausente" (nao deveria abrir uma janela de fallback para staging amplo)? [Cobertura de Edge Cases, Spec §FR-015] {auto}
  — Satisfeito: `commit-staging-cli.md` passo 2 ("Baseline AUSENTE => conjunto vazio + aviso em stderr — fail-closed: untracked nunca entram sem baseline; jamais fallback amplo").
- [x] CHK027 - E o caso "allowlist vazia" (etapa/task sem mudancas) especificado para nao gerar commit vazio nem cair em fallback amplo? [Cobertura de Edge Cases, Spec §FR-016] {auto}
  — Satisfeito: FR-016 + US4 Cenario 3 + `commit-staging-cli.md` passo 4 (exit 3, nenhum `git add` executado).
- [x] CHK028 - E exigida cobertura de teste de regressao automatizada especificamente para o cenario que causou o incidente real (nao so para o comportamento geral de staging)? [Mensurabilidade, Spec §FR-017, SC-003] {auto}
  — Satisfeito: FR-017 + SC-003 + `commit-staging-cli.md §Regressao obrigatoria` lista 5 cenarios de teste, incluindo fixture com arquivo untracked alheio analogo ao `.pptx` do incidente real.
- [x] CHK029 - O tratamento de paths com caracteres especiais (espacos, unicode, C-style quoting do `git status --porcelain`, renames) esta coberto para evitar que a allowlist derive um path incorreto ou perca uma entrada legitima? [Cobertura de Edge Cases + Seguranca, Contract commit-staging-cli §stage-derived passo 1] {auto}
  — Satisfeito: `commit-staging-cli.md` passo 1 especifica `core.quotepath=false`, tratamento de renames (path novo staged) e teste dedicado para path com espaco/char nao-ASCII. Cita explicitamente ser hardening do gate `owasp-security` pos-plan (ver onda-003).
- [ ] CHK030 - O staging por `--scope-dir` no commit por etapa (que confina a allowlist a `docs/specs/<feature>/` + state dir) e suficientemente restritivo para features cuja etapa TAMBEM edita codigo fora desses dirs (ex.: etapa `plan` que ja ajusta um contrato existente em `global/`) — ou esse caso deveria alargar o scope-dir dinamicamente? [Risco] {humano}

## Seguranca e Robustez Cross-Cutting

- [x] CHK031 - E o slug de capability (dado UNTRUSTED vindo de texto livre da spec) validado ANTES de ser usado para compor qualquer path de arquivo, prevenindo path traversal (`../`)? [Seguranca, Contract delta-gate-cli invariante 4, delta-merge-cli invariante 2-bis] {auto}
  — Satisfeito: ambos os contratos exigem a validacao `[a-z0-9][a-z0-9-]*` como PRIMEIRA checagem, antes de qualquer composicao de path, em AMBOS os scripts (defesa em profundidade — merge nunca confia que o gate ja rodou). Teste dedicado com slug hostil (`../escape`, absoluto, com espaco) exigido.
- [x] CHK032 - E vedado o uso de `printf "$var"` (format-string injection) ao emitir texto delta UNTRUSTED nos artefatos gerados? [Seguranca, Contract delta-gate-cli invariante 4] {auto}
  — Satisfeito: `delta-gate-cli.md` invariante 4 ("texto delta nunca passa por `printf "$var"` (sempre `printf '%s'`)") + `delta-merge-cli.md` invariante 2-bis (mesma regra para o texto escrito no corpus).
- [x] CHK033 - E a mutacao do corpus atomica (sem estado parcial visivel em caso de falha no meio de multiplas capabilities)? [Robustez, Spec Edge Cases (colisao/conflito)] {auto}
  — Satisfeito: `delta-merge-cli.md §Comportamento` passo 3-4 (validacao TOTAL de todas as entradas de todas as capabilities ANTES do primeiro `mv`; `mktemp` + `mv` atomico por arquivo).
- [x] CHK034 - O corpus gerado (`docs/specs/current/*.md`) tem alguma protecao contra edicao manual acidental que divirja do formato esperado pelo parser do merge (o contrato so recomenda em prosa "nao editar a mao", sem enforcement)? [Gap, Contract corpus-format §Estrutura] {auto}
  — Satisfeito (fechado por tasks 1.3 + 3.3 + 3.7): `delta-gate.sh` valida estrutura do corpus (headings/duplicidade de ids) ANTES da validacao referencial, novo `FINDING` code `corpus-malformed` (severity=error); `delta-merge.sh` RE-VALIDA a mesma estrutura antes de qualquer mutacao (defesa em profundidade), corpus malformado bloqueia o merge intacto.

## Consistencia Cross-Artifact e Dependencias

- [x] CHK035 - Toda FR (FR-001..FR-017) tem pelo menos um cenario de aceite ou edge case associado, evitando requisito "orfao" sem forma de verificacao? [Cobertura, Gate requirement-coverage.sh] {auto}
  — Satisfeito: `requirement-coverage.sh docs/specs/living-specs/spec.md` executado nesta onda retornou `RESULT|...|requirements=17|covered=17|errors=0` (exit 0, zero FINDING).
- [x] CHK036 - As decisoes de escopo negativo (Out of Scope: backfill retroativo, multi-repo stores) tem justificativa rastreavel e nao apenas uma omissao silenciosa? [Clareza, Spec §Out of Scope] {auto}
  — Satisfeito: ambos os itens tem rationale explicito (fonte insuficiente sobre o algoritmo do OpenSpec para multi-repo; volume de 15 features + opcionalidade de task para backfill).
- [x] CHK037 - A ausencia de fonte externa suficiente sobre o algoritmo exato de merge do OpenSpec concorrente foi tratada como bloqueio de suposicao (Principio VI) em vez de inventada? [Veracidade, Spec §Clarifications Q2] {auto}
  — Satisfeito: `## Clarifications` Q2 registra explicitamente "sem fonte externa suficiente sobre o algoritmo exato do OpenSpec para adotar como suposicao (Principio VI)" como justificativa da politica de bloqueio automatico escolhida.
- [ ] CHK038 - A tarefa opcional de backfill incremental (Out of Scope, mas mencionada como possivel task) tem criterio de prontidao definido, ou fica indefinidamente em backlog sem dono? [Risco/Priorizacao] {humano}

## Notes

- Items `{auto}` ja vem resolvidos pelo agente (`[x]` com citacao, ou `[ ]`
  com `[Gap]`/marcador quando a evidencia nao sustenta).
- Items `{humano}` ficam `[ ]` aguardando decisao do dono do produto — NAO
  bloqueiam a progressao para `/create-tasks` (nenhum e `[Conflict]`/`[Gap]`
  critico).
- Gate `requirement-coverage.sh` (ETAPA 4.2.1): `RESULT|...|requirements=17|covered=17|errors=0`, exit 0 — nenhum `[Gap]` adicional gerado por esse gate.
- Rastreabilidade: 38/38 items (100%) citam `[Spec §X]`, `[Contract ...]`, `[Gap]` ou `[Risco]` — acima do minimo de 80%.

### Resolucao

- **{auto} resolvidos**: 35 (`[x]` com evidencia citada — inclui CHK015,
  CHK020, CHK034, fechados por `execute-task` FASE 1/2/3/4; ver nota
  abaixo)
- **{humano} aguardando decisao**: 3 (CHK022, CHK030, CHK038)

### Proximos Passos (historico)

- `[Gap]` CHK015, CHK020, CHK034 -> `/create-tasks` gerou tarefas de
  requisito dedicadas (FASE 1: 1.1/1.2/1.3), implementadas em FASE 2
  (2.2), FASE 3 (3.3/3.7) e FASE 4 (4.2). Marcados `[x]` nesta revisao
  (FASE 6, `/analyze`) apos confirmacao empirica de que a implementacao
  fecha cada gap — ver dec-043 no state da execucao `feature-00c`.
- `{humano}` CHK022, CHK030, CHK038 -> decisao do dono do produto
  permanece em aberto; nao bloqueiam a conclusao desta feature
  (nenhum e `[Conflict]`/`[Gap]` critico).
