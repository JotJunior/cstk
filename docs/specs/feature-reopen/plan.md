# Implementation Plan: Reabertura incremental de feature concluida

**Feature**: `feature-reopen` | **Date**: 2026-08-11 | **Spec**: [spec.md](./spec.md)

## Summary

Hoje uma feature concluida e um beco sem saida: o estado terminal fica no disco
e qualquer re-invocacao com o mesmo `short-name` morre no `init`
(`state-rw.sh:411-418`), com mensagem que cita comandos do escopo errado. Esta
feature adiciona um **modo de reabertura** ao `/feature-00c` que preserva a
execucao anterior como *round* imutavel, inicia uma execucao limpa apontando
para ela, e trata o incremento como `## Delta Requirements` na spec existente.

Abordagem tecnica, saida do Phase 0:

- **Rotacao recuperavel** (`state-rounds.sh`, novo): journal de intencao +
  diretorio de estagio, com o commit deslocado para um unico `mv` de diretorio —
  o unico primitivo atomico disponivel em POSIX. Interrupcao sai por
  `recover`, nunca por edicao manual.
- **Sidecars resolvidos na raiz**: `PRAGMA wal_checkpoint(TRUNCATE)` antes de
  mover, e o round guarda **so** `state.db`. Elimina por construcao a divergencia
  macOS × Ubuntu que quebrou a release v6.4.0.
- **Ponteiro sem migracao**: `.previous_round` cai no catch-all
  `execution.extra_fields` — verificado empiricamente, nao inferido.
- **Indice de conhecimento**: rounds continuam sendo ingeridos (SC-003 exige
  conta-los), mas com **namespace de proveniencia por round**, porque a chave
  `(project, feature, wave, source_id)` colidiria entre rodadas.
- **Triagem na camada de linguagem**, veredito como bloqueio humano — nunca um
  score decidindo sozinho.

## Technical Context

**Language/Version**: POSIX `sh` (shebang `#!/bin/sh`, `set -eu`) — inferido de
`docs/constitution.md` Principio II e do padrao de
`plugins/cstk/skills/agente-00c-runtime/scripts/*.sh`
**Primary Dependencies**: `sqlite3` e `jq` (obrigatorias, camada de estado
transacional, amendment 1.3.0); `git` e `gh` (opcionais, com skip nao-fatal,
amendment 1.1.0)
**Storage**: estado transacional por execucao (`state.json` **ou** `state.db`,
schema `1.0.0`) + indice derivado `~/.claude/cstk/knowledge.db` (schema `14`)
**Testing**: harness POSIX proprio — `./tests/run.sh` (~1100 cenarios);
`tests/test_<nome>.sh` para scripts de skill, `tests/cstk/test_<nome>.sh` para
`cli/lib/`; `--check-coverage` falha com exit `1` em script orfao
**Target Platform**: macOS/zsh (dev) **e** Ubuntu (CI) — paridade obrigatoria
**Project Type**: CLI tool / toolkit de documentacao (single-layer)
**Performance Goals**: N/A — a rotacao e um `mv` de 1-2 arquivos por reabertura,
operacao rara e nao esta em caminho quente
**Constraints**: zero bashismo; zero GNU-only (`sed -i` sem sufixo, `stat`
GNU-first, `readlink -f`); `sqlite3` confinado a `cli/lib/recall.sh` no lado do
binario; `gh` confinado a `commit-mode.sh`
**Scale/Scope**: 27 state-dirs no repo de referencia (21 `state.json`, 6
`state.db`), 40 diretorios de spec arquivada (18 com prefixo de data, 22 sem;
a 41a entrada de `_archived/` e o arquivo `review-features-report.md`, nao uma
spec)

Nenhum `NEEDS CLARIFICATION` remanescente: os 5 do clarify foram respondidos na
spec e os 13 unknowns tecnicos estao resolvidos em `research.md`.

## Constitution Check

*GATE: passou antes do Phase 0. Re-checado apos Phase 1 — ver §Re-check.*

Constitution v1.3.0 (ratificada 2026-04-20, ultima emenda 2026-07-30).

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD recursivo (NON-NEGOTIABLE) | PASS | A propria feature roda a pipeline: `spec.md` + `clarify` + este `plan.md` antes de qualquer codigo. |
| II. POSIX sh puro, zero dep externa (NON-NEGOTIABLE) | PASS | `state-rounds.sh` e `#!/bin/sh` + `set -eu`, sem bashismo e sem GNU-only. `sqlite3`/`jq` sao **obrigatorias mas licitas**: o script pertence a camada de estado transacional, coberta pelo carve-out do amendment 1.3.0 (4 condicoes atendidas — ver abaixo). `git`/`gh` sao **opcionais** com skip nao-fatal, sob o carve-out 1.1.0. |
| III. Formato canonico de skill | N/A | Nenhuma skill nova. Muda-se um command (`feature-00c.md`), um script de runtime e `cli/lib/recall.sh` — nenhum SKILL.md e criado. |
| IV. Zero coleta remota (NON-NEGOTIABLE) | PASS | Toda escrita e local ao projeto-alvo e a `~/.claude/cstk/`. O unico acesso externo e `gh pr view` — leitura do repo do proprio operador, opcional, ja praticada por `commit-mode.sh`. Nenhuma telemetria. |
| V. Profundidade acima de metricas | PASS | Feature nasce de defeito observado (26 execucoes em beco sem saida) e resolve a causa, nao o sintoma: corrige tambem a opcao inalcancavel do pre-flight (FR-016) e a mensagem de escopo errado (FR-017). |
| VI. Veracidade de dados (NON-NEGOTIABLE) | PASS | Todo contrato afirmado como existente foi lido na fonte; todo contrato novo esta marcado `[PROPOSTA — a validar na implementacao]`. FR-021 exige citar a fonte de cada afirmacao e proibe converter "nao verificado" em "sem pendencia" (I-P1). |

### Detalhamento do carve-out 1.3.0 (dep obrigatoria) para `state-rounds.sh`

| Condicao | Como e satisfeita |
|----------|-------------------|
| (a) confinamento de camada | O script so manipula estado transacional (`state.json`/`state.db`). Nenhuma skill de documentacao, CLI de catalogo ou hook passa a exigir `sqlite3` por causa dele. |
| (b) fail-fast diagnostico | Ausencia de `sqlite3`/`jq` ⇒ exit `1` imediato com instrucao de instalacao, coberto por teste — mesmo padrao ja vigente em `state-rw.sh`. |
| (c) consumidores derivados degradam | `recall`/`knowledge.db` e o painel seguem best-effort; a mudanca de ingestao nao propaga obrigatoriedade a eles. |
| (d) declaracao explicita | Esta secao + `research.md` Decision 2 e 6. |

### Detalhamento do carve-out 1.1.0 (dep opcional) para `git`/`gh`

| Condicao | Como e satisfeita |
|----------|-------------------|
| (a) fallback graceful testado | Sem `git`/`gh`, a sonda retorna `probe_status=skipped-*` e o fluxo prossegue; o aviso vira "nao verificado". Coberto por Scenario 17. |
| (b) confinada a UM arquivo | **NAO SATISFEITA — desvio pre-existente, alheio a esta feature.** Medicao direta: `gh` e invocado em `commit-mode.sh`, `issue.sh` (L92-93, L241, L250, L333+) e `cli/lib/session.sh`. Ver Decision 9 §Correcao de premissa. A sonda de FR-021 vai para `commit-mode.sh` por razao tecnica (concentra os helpers `git`/`gh`), **nao** porque isso restaure um confinamento — ele ja nao existia. Esta feature **nao piora** o desvio, mas tambem **nao o corrige**. |
| (c) declarada na feature | Esta secao + `research.md` Decision 9. |

**Resultado do gate**: nenhum FAIL introduzido **por esta feature**. Ha, porem,
um **desvio pre-existente do Principio II** (condicao (b) do carve-out 1.1.0
para `gh`) que esta feature toca ao estender `commit-mode.sh` — descoberto pelo
gate de veracidade e **registrado como bloqueio humano**, nao absorvido em
silencio. A decisao de regularizar (amendment declarando `gh` como dep opcional
multi-arquivo, ou consolidacao num unico adapter) e do operador e esta fora do
escopo desta feature.

**Honestidade sobre a versao anterior deste gate**: a primeira redacao marcou a
condicao (b) como "resolvida" apoiada na premissa falsa de que `gh` estava
confinado a um arquivo. A linha foi corrigida em vez de mantida — Principio VI
vale tambem para as afirmacoes que o proprio Constitution Check faz sobre si.

## Project Structure

### Documentation (this feature)

```
docs/specs/feature-reopen/
├── spec.md                        # existente (clarificada, com Delta Requirements)
├── plan.md                        # este arquivo
├── research.md                    # Phase 0 — 13 decisions
├── data-model.md                  # Phase 1 — 6 entidades
├── quickstart.md                  # Phase 1 — 18 cenarios
└── contracts/
    ├── state-rounds.md            # CLI do script novo (PROPOSTA)
    ├── reopen-flow.md             # fluxo do --reopen no command
    └── recall-rounds.md           # ingestao de rounds no knowledge.db
```

### Source Code (repository root)

Arvore real do repo, com o delta desta feature anotado:

```
plugins/cstk/
├── commands/
│   └── feature-00c.md                    # MODIFICAR — modo --reopen; itens 6/7
└── skills/agente-00c-runtime/
    ├── scripts/
    │   ├── state-rounds.sh               # NOVO — rotacao/recover/list
    │   ├── commit-mode.sh                # MODIFICAR — sonda de trabalho pendente
    │   ├── state-rw.sh                   # (referencia; init/get/set inalterados)
    │   ├── state-lock.sh                 # (referencia; check-execution-busy reusado)
    │   ├── _state-rw-db.sh               # (referencia; extra_fields inalterado)
    │   └── state-db-schema.sh            # (referencia; WAL / schema inalterados)
    └── hooks/                            # NAO MUDAM — glob de shell nao ve rounds
cli/lib/
└── recall.sh                             # MODIFICAR — namespace de round + find de state.db
tests/
├── test_state-rounds.sh                  # NOVO — obrigatorio (--check-coverage); T-01..T-16
├── test_feature-00c-preflight.sh         # ESTENDER — T-20..T-34 (fluxo --reopen)
├── test_commit-mode.sh                   # ESTENDER — T-50..T-53 (sonda de pendencia)
├── test_state-parity-sweep.sh            # ESTENDER — allowlist do leitor novo
└── cstk/
    └── test_recall.sh                    # ESTENDER — rounds + paridade de backend
docs/
├── constitution.md                       # NAO MUDA — nenhum amendment necessario
└── specs/_archived/                      # LIDO (copia); nunca movido/alterado
```

**Structure Decision**: nenhum diretorio ou camada nova. A feature se encaixa
nas tres camadas ja existentes — command (politica e interacao), runtime de
estado (primitiva POSIX), `cli/lib` (indice derivado). O unico arquivo novo de
codigo e `state-rounds.sh`, com seu teste obrigatorio pareado. Rounds vivem sob
o proprio state-dir (`<SD>/rounds/<label>/`), o que e pre-requisito da
atomicidade: o `mv` de commit so e atomico dentro do mesmo filesystem.

## Convencoes de Borda

**N/A — single-layer.**

Justificativa (a secao e declarada, nao omitida): a feature nao atravessa
nenhuma fronteira de serializacao entre camadas independentes. Nao ha
backend↔frontend, nao ha broker↔consumer, nao ha DTO cruzando processo. Todos os
artefatos sao locais e consumidos pelo mesmo runtime POSIX que os escreve:

| Superficie | Formato | Fonte da verdade | Ha borda? |
|------------|---------|------------------|-----------|
| Estado transacional | JSON (`state.json`) ou SQLite (`state.db`) | `state-rw.sh` + `_state-rw-db.sh` | Nao — mesmo runtime le e escreve; a canonicalizacao ja e responsabilidade do `state-rw.sh` |
| `rounds/<label>/` | mesmo formato do estado que preservou | `state-rounds.sh` | Nao — o round e o mesmo artefato, so relocado |
| `.rotate-journal` | `key=value`, uma por linha | `state-rounds.sh` | Nao — escrito e lido pelo mesmo script |
| Saida dos subcomandos | linha pipe-delimitada (`ROUND\|...`, `RECOVER\|...`) | `contracts/state-rounds.md` | Nao — convencao ja usada por `delta-gate.sh` (`RESULT\|...`) |
| `knowledge.db` | SQLite, schema `14` | `cli/lib/recall.sh` | Nao — indice **derivado** e reconstruivel; nunca fonte da verdade |

Consequencia pratica: **nao ha cenario "Roundtrip End-to-End"** no
`quickstart.md`, e isso e deliberado — nao ha payload real de backend contra o
qual comparar shape. O risco que aquele cenario existe para pegar (drift
snake_case × camelCase entre camadas) nao tem analogo aqui. O drift equivalente
nesta feature e **divergencia entre plataformas**, e esse sim tem cenario
dedicado (Scenario 3: paridade macOS × Ubuntu dos sidecars).

Convencao de nomes aplicada (regra global do repo): sintaxe em ingles
(`previous_round`, `rounds/`, `label`, `staging`), mensagens e comentarios em
portugues.

## Escopo do trabalho

| # | Entrega | Arquivo | FRs |
|---|---------|---------|-----|
| 1 | `state-rounds.sh` (`next-label`, `rotate`, `recover`, `list`) + guardas G1..G7 | novo | FR-007..FR-011 |
| 2 | `tests/test_state-rounds.sh` (T-01..T-16) | novo | Quality Standard |
| 3 | Modo `--reopen` + correcao dos itens 6/7 do pre-flight | `feature-00c.md` | FR-001..FR-006, FR-016, FR-017, FR-019 |
| 3b | **Extensao de `tests/test_feature-00c-preflight.sh` (T-20..T-34)** | teste | SC-001, SC-005, SC-007 |
| 4 | Sonda de trabalho pendente + heranca de `--atomic-commit` | `commit-mode.sh`, `feature-00c.md` | FR-021, FR-022 |
| 4b | **Extensao de `tests/test_commit-mode.sh` (T-50..T-53)** | teste | FR-021 |
| 5 | Restauracao de spec arquivada (so `-type d`; 2 formas de nome) | `feature-00c.md` | FR-013 |
| 6 | Namespace de round + varredura ancorada de `state.db` no `--reindex` | `cli/lib/recall.sh` | FR-010, FR-018 |
| 7 | Extensao de `test_recall.sh` (T-40..T-49) | teste | SC-003 |
| 8 | Delta na spec existente (`## Delta Requirements`) | `feature-00c.md` | FR-014 |
| 9 | Continuidade de backlog por fase apendada | `feature-00c.md` | FR-015 |
| 10 | **Heranca de backend do round anterior** (Decision 14) | `feature-00c.md` / `state-rw.sh` | FR-010 |

Invariantes de teste novos exigidos pelos gates:

| ID | Invariante | Origem |
|----|------------|--------|
| T-50 | sonda com branch nao mesclada ⇒ reporta pendencia citando o comando | FR-021 |
| T-51 | `gh` ausente/nao autenticado ⇒ `probe_status=skipped-*` e "nao verificado" — **nunca** "sem pendencia" | FR-021, I-P1 |
| T-52 | branch com nome iniciado por `-` nao e consumida como flag (`--` separador) | gate security (LOW) |
| T-53 | sonda nunca bloqueia: com pendencia detectada, a reabertura prossegue apos confirmacao | FR-021 |
| T-35 | backend do round anterior e herdado pela execucao nova, contra config global divergente | FR-010, Decision 14 |

### Fora de escopo (registrado deliberadamente)

- **`/agente-00c` e seus resumes** — FR-019 exclui explicitamente.
- **Amendment de constitution** — nenhum necessario; os dois carve-outs
  existentes cobrem as dependencias (por isso a sonda vai para `commit-mode.sh`
  em vez de script novo).
- **Migracao de `schema_version`** — `.previous_round` usa o catch-all
  `extra_fields`; nenhuma coluna e adicionada.
- **Mensagens de estado pre-existente dentro do proprio `state-rw.sh init`** —
  sao **duas**, com defeitos **diferentes**, e so uma foi descrita na primeira
  redacao deste plano:
  - `init: state.json ja existe em $_sd. Use /agente-00c-abort ou
    /agente-00c-resume.` — cita comandos do escopo de **projeto**; incorreta
    para o modo feature.
  - `init: state.db ja existe em $_sd (projeto migrado para backend SQLite) —
    init nao se aplica; use os subcomandos normais (state-ondas.sh etc.)
    diretamente.` — **nao** cita `/agente-00c-*`, mas tambem nao aponta nenhum
    caminho util ao operador de feature.

  Ambas deixam de ser alcancaveis pelo caminho de reabertura, mas permanecem
  como estao em invocacoes diretas. Corrigi-las exige o `init` distinguir modo
  projeto de modo feature. Divida conhecida, nao coberta por FR desta feature.

- **Regularizacao do `gh` perante a condicao (b) do carve-out 1.1.0** — desvio
  pre-existente (invocado em `commit-mode.sh`, `issue.sh` e `cli/lib/session.sh`).
  Ver §Constitution Check e Decision 9. Requer decisao do operador
  (amendment ou consolidacao num adapter unico).

- **Liveness do lock (limite de G6)** — `state-lock.sh acquire --force` so
  recusa com owner **vivo**, e o owner gravado e o `$PPID` de um shell de tool
  call tipicamente ja morto. FR-012 fica robusto contra concorrencia normal, mas
  nao contra `--force` concorrente. Registrado, nao resolvido aqui.

## Riscos e mitigacoes

| Risco | Severidade | Mitigacao |
|-------|------------|-----------|
| Colisao de chave na ingestao entre rounds corrompe historico das duas rodadas | **Alta** | Namespace de proveniencia por round (Decision 5); T-41 cobre |
| Sidecars WAL/SHM divergirem entre macOS e Ubuntu (repetir v6.4.0) | **Alta** | Checkpoint TRUNCATE + round guarda so `state.db`; T-06 e Scenario 3 cobrem nas duas plataformas |
| Rotacao interrompida deixar state-dir hibrido | **Alta** | Journal + staging + commit por rename unico; `recover` idempotente; T-08..T-11 |
| Recusa criar state-dir fantasma (lock e init escrevem antes de validar) | Media | Ordem estrita: toda recusa antes do `acquire` (Decision 7); T-20 assere zero inode novo |
| Rounds SQLite invisiveis ao `--reindex` (lacuna ja existente) | Media | Varredura de `state.db` (Decision 6); T-44/T-45 |
| Sonda de pendencia afirmar ausencia sem ter verificado | Media | `probe_status` + I-P1: skip vira "nao verificado"; Scenario 17 passo 4-5 |
| TOCTOU entre checagem de pre-condicao e `acquire` | Baixa | Re-verificacao pos-lock (passo 7.a); janela residual documentada |
| `r99` → `r100` quebra ordenacao lexicografica | Baixa | Limite documentado (Decision 3); cenario nao observado — nenhuma feature foi reaberta ate hoje |

## Re-check de Constitution (pos-Phase 1)

Revalidacao apos o design, conforme ETAPA 7 — **nao** por inercia:

| Pergunta | Veredito |
|----------|----------|
| O design introduziu complexidade nao justificada? | Nao. Um script novo, tres arquivos modificados, zero camada nova, zero tabela nova, zero migracao de schema. |
| Algum MUST passou a ser violado pelo design? | Nao. O unico risco real que o design **criou** foi o `gh` num script novo (quebraria a condicao (b) do carve-out 1.1.0) — resolvido movendo a sonda para `commit-mode.sh`, que ja detem a dependencia. |
| Principio II segue integro apos o design? | Sim. `wal_checkpoint`, `integrity_check`, journal `key=value` e saida pipe-delimitada sao todos POSIX-parseaveis sem GNU-only e sem bashismo. |
| Principio VI segue integro? | Sim. Contratos existentes citam arquivo e linha; contratos novos estao marcados `[PROPOSTA]`; FR-021 proibe explicitamente converter "nao verificado" em "sem pendencia". |
| Algum amendment de constitution passou a ser necessario? | Nao — e esse foi um resultado do design, nao uma premissa. |

**Resultado do re-check: PASS.** `## Complexity Tracking` fica **vazio** por
ausencia de violacao a justificar.

## Complexity Tracking

> Preencher APENAS se Constitution Check tem violacoes que precisam justificativa.

Nenhuma violacao. Secao intencionalmente vazia.
