# Research: living-specs

**Feature**: `living-specs` | **Date**: 2026-07-23
**Input**: [spec.md](./spec.md)

Todas as fontes citadas foram verificadas no repo real nesta sessao
(Constitution VI — nenhum fato abaixo e suposicao).

## Decision 1 — Onde vive o `git add` amplo que causou o incidente

**Decision**: o staging amplo NAO esta em `commit-mode.sh` (o helper nao tem
subcomando de staging nenhum — so `is-enabled | set-enabled | guard-branch |
stage-message | task-message | finalize`). Os sites reais de staging amplo sao
TRES:

1. `global/agents/agente-00c-feature-orchestrator.md` — prosa dos passos
   7.bis e 10.qui: `git -C "$PAP" add -A` (linhas 335 e 403).
2. `global/agents/agente-00c-orchestrator.md` — prosa equivalente
   (linhas 678 e 1552): `git -C <PAP> add -A`.
3. `global/skills/agente-00c-runtime/scripts/state-ondas.sh` —
   `_so_cmd_git_commit` (linha ~794): `git add -- .` real em codigo
   (commit local por onda do agente-00c).

**Rationale**: o fix precisa de um subcomando de staging DETERMINISTICO em
`commit-mode.sh` (codigo, testavel) que os 3 sites passem a consumir — corrigir
so a prosa deixaria o site (3) em codigo intacto e o bug voltaria pelo caminho
do wave-commit.

**Alternatives considered**: corrigir apenas a prosa dos orquestradores
(rejeitado: prosa nao e testavel por `tests/run.sh` e o site (3) e codigo);
corrigir apenas `state-ondas.sh` (rejeitado: o incidente real veio do caminho
da prosa via atomic-commit).

## Decision 2 — Derivacao da allowlist de staging (FR-014..FR-016)

**Decision**: novo par de subcomandos em `commit-mode.sh`:

- `snapshot` — captura baseline de untracked (`git status --porcelain`,
  paths ordenados) num sidecar `commit-baseline.txt` no state dir (mesmo
  padrao sidecar de `tool-call-ticks.log`: NUNCA dentro do `state.json`).
- `stage-derived` — computa a allowlist e faz `git add --` caminho a
  caminho. Allowlist = (tracked modificados/deletados) + (untracked atuais
  MENOS baseline), opcionalmente intersectada com `--scope-dir` (repetivel).
  Allowlist vazia => exit 3 (nada a commitar; caller pula o commit — FR-016).
  Baseline ausente => degrada FAIL-CLOSED: so tracked entram, untracked
  ficam fora, com aviso em stderr (nunca fallback para staging amplo).

Dois regimes de chamada:

| Caller | scope-dirs | baseline |
|--------|-----------|----------|
| commit por etapa (specify/plan/clarify/checklist/create-tasks) | `docs/specs/<feature>/` + state dir da execucao | dispensavel (escopo confina) |
| commit por task (execute-task) e wave-commit (state-ondas) | nenhum (task pode tocar qualquer path do repo) | obrigatorio (snapshot no inicio da onda) |

**Rationale**: tasks legitimamente CRIAM arquivos untracked em qualquer lugar
do repo — a unica forma deterministica de distinguir "untracked criado pela
task" de "untracked alheio pre-existente" (o `.pptx` do incidente) e o
diff de conjuntos contra um baseline capturado antes do trabalho da onda.
`comm` sobre listas ordenadas e POSIX puro (Constitution II).

**Alternatives considered**: allowlist so por scope-dirs para tasks
(rejeitado: task que cria `cli/lib/foo.sh` ficaria fora de qualquer escopo
previsivel); derivar dos `touched_files` de `.tasks[]` (rejeitado: hoje esse
campo e computado de `git diff HEAD~1..HEAD` APOS o commit — circular);
`git add -u` + lista manual de untracked na prosa (rejeitado: prosa nao
testavel, mesmo modo de falha do incidente).

## Decision 3 — Quem orquestra o archive hoje

**Decision**: o archive e ACAO MANUAL sugerida pela skill `review-features`
(SKILL.md, "Proximos passos sugeridos" item 3: "Mover features `ARQUIVAR`
para `docs/specs/_archived/<YYYY-MM-DD>-<feature>/` (acao manual, pedir
confirmacao ao usuario antes de mover...)"). Nao existe script que mova specs
para `_archived/` — verificado por grep em `global/` e `cli/`. Portanto o
gate (US3) e o merge (US2) entram como PASSOS OBRIGATORIOS na prosa dessa
mesma acao de archive em `review-features/SKILL.md`, implementados como
scripts em `global/skills/review-features/scripts/` (a skill ja tem
`scripts/aggregate.sh`, entao o diretorio e precedente).

**Rationale**: FR-008 exige que o corpus atualize "como parte da acao de
archive ja existente" — a acao existente e a da review-features; ancorar os
scripts nela evita criar um fluxo paralelo. O archive atual (mover para
`_archived/`) permanece intacto (US2 cenario 5).

**Alternatives considered**: skill nova dedicada "archive" (rejeitado: bump
de contagem de skills + fluxo paralelo ao ja documentado); scripts no
`agente-00c-runtime` (rejeitado: archive e acao de operador/skill, nao passo
do runtime dos orquestradores).

## Decision 4 — Formato da secao Delta na spec (US1)

**Decision**: secao OPCIONAL `## Delta Requirements` dentro do proprio
`spec.md` (a spec ja fixou isso na Key Entity "Delta Requirements Section:
bloco dentro da spec de uma feature"), com agrupamento por capability e
quatro subtipos:

```markdown
## Delta Requirements

### Capability: <capability-slug>

#### ADDED
- **FR-NNN**: <texto>

#### MODIFIED
- **FR-NNN**: <novo texto>

#### REMOVED
- **FR-NNN**: <motivo>

#### RENAMED
- **FR-NNN -> FR-MMM**
```

Skip explicito (FR-011) e um marcador na MESMA secao:
`**Skip**: <justificativa> — <autor>, <YYYY-MM-DD>`.

Contrato completo em
[contracts/delta-section-format.md](./contracts/delta-section-format.md)
`[PROPOSTA — a validar na implementacao]`.

**Impacto verificado nos gates existentes (fatos, nao suposicao)**:

- `validate-sdd.sh` spec-profile exige apenas "User Scenarios & Testing",
  "Requirements" e "Success Criteria" (linha 189) — secao adicional nao gera
  finding.
- `requirement-coverage.sh` so extrai FR ids de dentro de
  `### Functional Requirements` (linha 116; reseta em qualquer `##`/`###`
  seguinte) — entradas delta nao entram na contagem de cobertura.
- A nota "templates core congelados" (memoria `reference_spec_kit_benchmark`)
  refere-se aos templates do UPSTREAM spec-kit (sem drift a perseguir), nao a
  um congelamento do template do cstk — mudar
  `global/skills/specify/templates/feature-spec.md` e permitido.

**Rationale**: arquivo separado (`delta.md`) criaria segundo artefato a
sincronizar e a spec ja decidiu "bloco dentro da spec". Marcador de skip
dentro da secao viaja junto com a spec para `_archived/` (auditavel por git
e por qualquer leitor), sem estado paralelo.

**Alternatives considered**: `delta.md` separado (rejeitado: segunda fonte a
manter em sync; a spec ja fixou secao interna); skip como flag de CLI sem
registro em arquivo (rejeitado: FR-011 exige quem/quando/por-que auditavel e
persistente); seta unicode `→` no RENAMED (rejeitado: `->` ASCII e mais
robusto para parsing POSIX e digitacao).

## Decision 5 — Organizacao do corpus (US2)

**Decision**: `docs/specs/current/<capability-slug>.md` — um arquivo por
capability, paralelo a `_archived/` (layout fixado no clarify). Identificador
de entrada (`FR-NNN`) e unico POR ARQUIVO de capability, nao globalmente.
Colisao dentro da mesma capability (edge case da spec) => FINDING + bloqueio.
Mesma numeracao em capabilities distintas nao colide (namespace = capability).

Estrutura do arquivo de capability (contrato completo em
[contracts/corpus-format.md](./contracts/corpus-format.md)):

- `## Requirements` — entradas ativas (`### FR-NNN` + texto + proveniencia
  "Introduzida por" e "Ultima modificacao" — FR-007).
- `## Removed Requirements` — remocoes rastreaveis (FR-004: nunca
  desaparecimento silencioso).
- `## Renamed Identifiers` — tabela old-id -> new-id com feature e data
  (FR-005).

**Rationale**: id global unico exigiria coordenacao de numeracao entre todas
as features (fragil); arquivo unico monolitico cresce sem limite e maximiza
conflito; per-capability e o desenho do proprio OpenSpec (requirements
escopados por capability spec) adaptado a arquivo unico por capability. O
autor do delta declara a capability-alvo no header da subsecao (Decision 4).

**Alternatives considered**: corpus monolitico `current/corpus.md`
(rejeitado: crescimento sem particao e todo archive toca o mesmo arquivo);
id globalmente unico (rejeitado: forca renumeracao cross-feature);
diretorio por capability com spec.md dentro (paridade literal com OpenSpec;
rejeitado: profundidade extra sem ganho para arquivo unico de texto).

## Decision 6 — Gate e merge como scripts deterministicos (FR-012)

**Decision**: dois scripts POSIX novos em
`global/skills/review-features/scripts/`:

- `delta-gate.sh SPEC_MD [--corpus-dir DIR]` — read-only; veredito
  bloquear/liberar. Padrao de saida IDENTICO aos gates v5.22.0
  (verificado em `validate-sdd.sh` linhas 28-41 e
  `requirement-coverage.sh`): linhas `FINDING|<severity>|<code>|<msg>` +
  linha final `RESULT|...`; exit 0 (pass) / 1 (bloqueio) / 2 (uso
  incorreto).
- `delta-merge.sh SPEC_MD --feature NAME [--corpus-dir DIR] [--dry-run]` —
  aplica ADDED/MODIFIED/REMOVED/RENAMED no corpus de forma ATOMICA:
  monta os arquivos novos em `mktemp`, valida TODAS as entradas, e so
  entao faz `mv`; qualquer conflito => exit 1 SEM mutacao parcial
  (clarify: bloqueio com diagnostico, nunca merge silencioso).

Ambos com testes `tests/test_delta-gate.sh` e `tests/test_delta-merge.sh`
(convencao `global/skills/<X>/scripts/<n>.sh -> tests/test_<n>.sh`;
`--check-coverage` gateia).

**Rationale**: duas responsabilidades distintas (veredicto read-only vs
mutacao) com codigos de saida proprios; o fluxo de archive roda gate ->
merge -> mover para `_archived/`. Determinismo do edge case da spec ("duas
execucoes MUST produzir o mesmo veredito") vem de ser script puro, sem
julgamento de modelo.

**Alternatives considered**: script unico com flag `--apply` (rejeitado:
mistura exit codes de veredicto com exit codes de mutacao e complica os
testes); implementar como prosa de skill (rejeitado: viola FR-012
explicitamente).

## Decision 7 — Envelope `_diag.sh` nos scripts novos

**Decision**: os scripts novos emitem a linha `DIAG|severity|code|message|fix`
nas saidas de erro (dogfooding do piloto v5.22.0). Como o piloto vive
confinado em `global/skills/agente-00c-runtime/scripts/_diag.sh` e e
consumido apenas por sourcing same-dir (verificado: consumidores sao
`bloqueios.sh`, `state-lock.sh`, `state-rw.sh`, `state-ondas.sh` — todos no
mesmo diretorio; nenhum sourcing cross-skill existe no repo), a
`review-features/scripts/` recebe uma COPIA vendored de `_diag.sh` (skills
sao self-contained quando instaladas em `~/.claude/skills/<nome>/`).
Cabecalho da copia aponta a fonte canonica
(`agente-00c-runtime/scripts/_diag.sh`) e o contrato
(`docs/specs/openspec-hygiene/contracts/diagnostic-envelope.md`).
Cobertura: `tests/test__diag.sh` ja existe e o mapeamento por NOME do
`--check-coverage` cobre a copia automaticamente.

**Alternatives considered**: sourcing por path relativo cross-skill
(`../../agente-00c-runtime/scripts/_diag.sh`) (rejeitado: acopla layout de
instalacao entre skills; quebra se uma skill for instalada sem a outra);
inline de um printf avulso (rejeitado: perderia as validacoes de contrato
de `diag_emit` — severity valida, fix != message).

## Decision 8 — Enforcement do gate no fluxo autonomo vs manual

**Decision**: o gate roda nos DOIS fluxos pela mesma porta: a prosa da acao
de archive em `review-features/SKILL.md` passa a exigir
`delta-gate.sh` (exit != 0 => nao mover para `_archived/`) e, no fluxo
autonomo, o `agente-00c-orchestrator.md` (fase review-features) herda o
comportamento por invocar a mesma skill. Nenhum hook novo e necessario.

**Rationale**: FR-008 ("sem exigir passo manual adicional alem do que o
archive ja requer") — o gate e parte da mesma acao, nao um passo extra; a
skill e o unico ponto de entrada documentado do archive (Decision 3).

## Decision 9 — Migracao retroativa e primeiro corpus

**Decision**: `docs/specs/current/` nasce VAZIO (criado pelo primeiro merge
— US2 cenario 4: corpus inexistente => criado). Nenhum backfill das ~15
features de `_archived/` (Out of Scope explicito da spec; backfill pode
virar task OPCIONAL no backlog sem gatear conclusao). Features hoje abertas
em `docs/specs/*` (7 alem desta) chegarao ao archive sem secao delta e
cairao no gate: preencher delta retroativamente ou registrar skip (edge
case previsto na spec).
