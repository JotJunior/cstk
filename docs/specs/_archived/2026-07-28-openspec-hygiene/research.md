# Research: openspec-hygiene

**Feature**: `openspec-hygiene`
**Date**: 2026-07-23
**Input**: `spec.md` (17 FRs, zero NEEDS CLARIFICATION)

Toda decisao abaixo foi verificada empiricamente contra o repo real
(Constitution VI — zero fabricacao). Comandos de sonda citados em cada
decisao.

## Decision 1 — Gate requirement↔cenario: script novo `requirement-coverage.sh` em `global/skills/checklist/scripts/`

**Decision**: implementar o gate (FR-001..FR-005) como script NOVO
`global/skills/checklist/scripts/requirement-coverage.sh`, seguindo o
padrao exato dos gates deterministicos existentes:
`FINDING|<severity>|<code>|<mensagem>` por achado + linha
`RESULT|<file>|...` final, exit 0 (passa) / 1 (>=1 error) / 2 (uso
incorreto), POSIX sh `set -eu`.

**Rationale**:
- Padrao confirmado por sonda nos dois gates existentes:
  `global/skills/validate-documentation/scripts/validate-sdd.sh`
  (linhas 28-29: `FINDING|<severity>|<code>|<mensagem>` +
  `RESULT|<file>|profile=...|errors=N|warnings=M`; exit 0/1/2) e
  `global/skills/create-tasks/scripts/validate-tasks-template.sh`
  (linhas 19-20, mesmo formato com `critical=/warning=`).
- Script NOVO (nao extensao do `validate-sdd.sh`) porque: (a) o
  matching heuristico textual do FR-005 e qualitativamente diferente
  dos checks estruturais estritos do spec-profile — mistura-los
  poluiria um gate hoje 100% deterministico-estrutural com uma
  heuristica calibravel; (b) `validate-sdd.sh` ja tem contrato
  arquivado proprio (`docs/specs/_archived/validate-docs-sdd-profile/`)
  com 12 cenarios de quickstart congelados; (c) FR-001 pede
  explicitamente "um script deterministico que, dado um spec.md,
  verifica...".
- Localizado em `checklist/scripts/` porque a spec enquadra o gate como
  "o equivalente a unit tests para requisitos que o `checklist` ja faz
  para qualidade de linguagem" e `checklist` e a skill-gate semantica.
  Invocacao cross-skill por `specify` (FR-002) tem precedente
  estabelecido: o orquestrador feature-00c ja invoca
  `create-tasks/scripts/validate-tasks-template.sh` de fora da skill
  dona.
- O check `dangling-fr-sc-ref` do `validate-sdd.sh` (linha 342) NAO
  cobre este caso: ele valida plan.md citando FR inexistente na spec —
  direcao inversa e artefato diferente do que FR-001 pede (cobertura de
  cenario dentro da propria spec).

**Alternatives considered**:
- Estender `validate-sdd.sh` spec-profile com code novo
  `fr-no-scenario-coverage`: rejeitado pelos motivos (a)-(c) acima.
- Colocar em `specify/scripts/`: rejeitado — `specify` e a skill de
  criacao, nao de gate; `checklist` e o dono natural.

## Decision 2 — Heuristica de associacao FR↔cenario (FR-005)

**Decision**: associacao em duas vias, na ordem:
1. **Fast-path (citacao literal)**: se qualquer cenario/Edge Case cita
   o ID literal (`FR-NNN`), o requisito esta coberto.
2. **Correspondencia heuristica textual**: extrair termos-chave do
   enunciado do requisito (tokens normalizados lowercase, sem
   pontuacao, comprimento >= 5, excluindo stoplist embutida de termos
   genericos pt/en — ex.: `sistema`, `system`, `deve`, `campo`,
   `script`, `formato`, `arquivo`, `feature`); requisito coberto se
   >= N termos distintos (default N=2, flag `--min-match N`) aparecem
   no corpus normalizado das secoes de cenarios (`Acceptance
   Scenarios` de todas as User Stories + `### Edge Cases`).
   Requisito com < N termos elegiveis: coberto se >= 1 termo casa.

**Rationale**:
- Clarify Session 2026-07-23 da spec fixou correspondencia heuristica
  SEM citacao de ID e SEM mudanca no template `feature-spec.md`.
- Formato de parsing confirmado no template real
  (`global/skills/specify/templates/feature-spec.md`): FRs sao itens
  `- **FR-NNN**:` sob `### Functional Requirements`; cenarios sob
  `**Acceptance Scenarios**:` por User Story + secao `### Edge Cases`.
- Ferramentas 100% POSIX: `grep`, `tr`, `sort`, `awk` (Constitution
  II). Zero `jq`.
- Threshold calibravel por flag para ajuste sem release; default
  conservador (2 termos) definido para minimizar falso-negativo em
  specs pt-br inflexionadas.
- Calibracao empirica obrigatoria na implementacao: rodar o gate
  contra as specs reais do repo (incluindo esta propria spec) como
  fixtures antes de fixar a stoplist final.

**Alternatives considered**:
- Exigir citacao de FR-ID nos cenarios: rejeitado no clarify (forcaria
  retrofit de todo o portfolio + mudanca de template).
- Stemming/lematizacao: fora do alcance de POSIX sh puro; comprimento
  minimo de token >= 5 + prefixo comum e aproximacao suficiente.

## Decision 3 — Envelope diagnostico: helper sourceable `_diag.sh` + emissao ADITIVA; escopo-piloto de 4 scripts

**Decision**:
- Criar helper sourceable
  `global/skills/agente-00c-runtime/scripts/_diag.sh` (padrao identico
  ao `_log.sh` ja existente) expondo
  `diag_emit <severity> <code> <message> <fix>`, que emite UMA linha
  `DIAG|<severity>|<code>|<message>|<fix>` em stderr. Caracter `|`
  dentro de message/fix e substituido por `/` antes da emissao
  (parseabilidade garantida). Zero dependencia nao-POSIX (FR-016).
- Emissao **ADITIVA**: os scripts migrados MANTEM sua mensagem de erro
  atual intacta e ACRESCENTAM a linha `DIAG|...` — nenhum teste que
  verifica mensagem literal quebra (FR-015, SC-006).
- **Escopo-piloto (FR-012/FR-015)**: exatamente 4 scripts, os de maior
  consumo programatico pelos orquestradores:
  1. `state-rw.sh` (falhas: state ausente, JSON invalido, hash
     divergente — hoje `printf '%s: %s\n' ... >&2`, linhas 77/82/619)
  2. `state-lock.sh` (contention, lock stale)
  3. `state-ondas.sh` (start com onda aberta, end sem onda aberta)
  4. `bloqueios.sh` (respond a bloqueio inexistente)
  Todos os demais scripts ficam explicitamente FORA do escopo desta
  rodada (FR-015) — formato de erro atual inalterado.

**Rationale**:
- Sonda confirmou o estilo atual de erro do runtime (`printf ... >&2`
  simples em `state-rw.sh`; `_log.sh` so filtra secrets, nao
  estrutura).
- Recomendacao do benchmark (registrada no kickoff da feature):
  comecar pelos scripts consumidos por agentes — os 4 escolhidos sao
  as primitivas de estado que TODA onda invoca e cujas falhas o
  orquestrador precisa distinguir programaticamente (ex.: hash
  divergente = tampering → aborto; contention → exit 3).
- Formato pipe-delimited espelha o `FINDING|` dos gates — vocabulario
  ja estabelecido no toolkit, parseavel com `grep '^DIAG|'` +
  `cut -d'|'`.
- Precedente de teste para helper underscore: `_hash.sh` →
  `tests/test__hash.sh` (confirmado por `ls tests/`). `_diag.sh` →
  `tests/test__diag.sh` (FR-017).

**Alternatives considered**:
- JSON em stderr: exigiria `jq` para consumo confortavel e quebraria
  FR-016 no espirito; pipe-delimited e o padrao da casa.
- Migrar todos os ~30 scripts do runtime de uma vez: rejeitado pela
  propria spec (FR-015 — migracao aditiva, superficie de risco em
  testes literais).
- Substituir mensagens atuais pelo envelope: quebraria testes
  existentes que verificam texto literal (risco citado na US4).

## Decision 4 — Prefixo de data no archive: mudanca doc-only, zero consumidores dinamicos a ajustar

**Decision**: FR-009..FR-011 sao implementados APENAS como atualizacao
de prosa na skill `review-features` (SKILL.md — passo manual "mover
para `_archived/`", linhas 45, 183 e Gotcha 224-225) instruindo o
destino `docs/specs/_archived/<YYYY-MM-DD>-<feature>/` com a data do
arquivamento. Nenhum script novo, nenhuma migracao retroativa.

**Rationale** (sondas executadas em 2026-07-23):
- `grep -rn "_archived" global/ tests/ cli/` retornou SOMENTE
  referencias ESTATICAS a diretorios ja arquivados especificos (ex.:
  `_archived/agente-00c/contracts/...`) — que permanecem intactos por
  FR-010, logo nenhum link quebra.
- Unico consumidor que varre `docs/specs/` dinamicamente e
  `global/skills/review-features/scripts/aggregate.sh`: usa
  `find "$ROOT" -mindepth 1 -maxdepth 1 -type d` e pula qualquer dir
  sem `tasks.md` (`[ -f "$_tasks" ] || continue`, linha ~247).
  `docs/specs/_archived/` nao tem `tasks.md` no topo, logo ja e
  ignorado hoje; o conteudo interno (datado ou nao) nunca e visitado
  (maxdepth 1). Zero ajuste necessario.
- `cli/lib/list.sh` nao varre `docs/specs` (refs sao só comentarios).

**Alternatives considered**:
- Script de arquivamento automatizado: fora do escopo da spec (acao
  segue manual, conforme `review-features` Gotcha "nunca arquivar sem
  confirmacao").
- Migracao retroativa dos dirs antigos: proibida por FR-010.

## Decision 5 — Triagem update-vs-nova: prosa em `specify` ETAPA 0 + `clarify` ETAPA 2, sem script

**Decision**: FR-006..FR-008 sao implementados como prosa:
- `specify/SKILL.md`: novo sub-passo na ETAPA 0 (TRIAGEM, ja existente
  — linhas 98-195 com 0.0 atalho autonomo, 0.1 classificar, 0.2
  relevancia SDD, 0.3 decisao), inserindo a avaliacao "refina spec
  existente vs feature nova": listar `docs/specs/*/spec.md` ativas
  (excluindo `_archived/`), comparar intencao/atores/objetivo do
  pedido com as specs candidatas e recomendar com criterio citado.
  Sem spec relacionada → seguir direto (FR-008, zero overhead).
- `clarify/SKILL.md`: nota na ETAPA 2 (ESCANEAR AMBIGUIDADES)
  aplicando o mesmo criterio quando um pedido do operador durante a
  clarificacao constitui expansao de escopo (recomendar `specify` para
  feature nova em vez de inchar a spec corrente).

**Rationale**: sonda confirmou que a ETAPA 0 de triagem ja existe em
`specify` (estrutura 0.0-0.3) — o novo criterio encaixa como extensao
natural, sem script (mesmo padrao do guia ja absorvido de triagem
feature-vs-bugfix). `clarify` nao tem triagem hoje; a nota e aditiva.

**Alternatives considered**:
- Script de similaridade textual entre pedido e specs existentes:
  overengineering — a decisao e semantica (intencao/escopo), cabe ao
  LLM/operador com criterio documentado, nao a um matcher POSIX.

## Decision 6 — Severidade e retroatividade do gate de cobertura

**Decision**: achado de requisito sem cenario = severity `error`
(bloqueia, exit 1), code `fr-no-scenario` — inclusive para specs
escritas antes desta feature (sem excecao retroativa, conforme Edge
Case da spec). Mensagem inclui o ID exato + fix acionavel ("adicionar
Acceptance Scenario ou Edge Case cobrindo os termos centrais de
FR-NNN"), satisfazendo FR-003/SC-002.

**Rationale**: e o comportamento pedido pelos Acceptance Scenarios 1-3
da US1 e pelo Edge Case de retroatividade. Specs degeneradas (zero
FRs) passam trivialmente (FR-004) — `RESULT` com `errors=0`.

## Resolucao de NEEDS CLARIFICATION

A spec entrou com zero `[NEEDS CLARIFICATION]` (clarify concluido na
onda anterior; FR-005 resolvido em Clarifications Session 2026-07-23).
Nenhum unknown restante no Technical Context.
